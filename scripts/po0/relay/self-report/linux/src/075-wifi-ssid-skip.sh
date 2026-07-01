ENV_SKIP_WIFI_SSIDS="${ENV_SKIP_WIFI_SSIDS-${SKIP_WIFI_SSIDS-}}"
SKIP_WIFI_SSIDS=""
FORCE_REPORT="${FORCE_REPORT-}"

normalize_wifi_ssid_skip_list() {
    local value="$1" item out=""
    local -a items=()
    IFS=';' read -r -a items <<< "${value}"
    for item in "${items[@]}"; do
        item="$(trim "${item}")"
        [[ -n "${item}" ]] || continue
        if [[ -n "${out}" ]]; then
            out="${out};${item}"
        else
            out="${item}"
        fi
    done
    printf '%s\n' "${out}"
}

append_wifi_ssid_skip_value() {
    local value="$1" item current
    item="$(trim "${value}")"
    [[ -n "${item}" ]] || return 0
    current="$(normalize_wifi_ssid_skip_list "${SKIP_WIFI_SSIDS:-}")"
    if [[ -n "${current}" ]]; then
        SKIP_WIFI_SSIDS="${current};${item}"
    else
        SKIP_WIFI_SSIDS="${item}"
    fi
}

wifi_ssid_skip_list_display() {
    local value
    value="$(normalize_wifi_ssid_skip_list "${SKIP_WIFI_SSIDS:-}")"
    if [[ -n "${value}" ]]; then
        printf '%s\n' "${value}"
    else
        printf '未设置'
    fi
}

strip_wifi_ssid_value() {
    local value="$1"
    value="${value%$'\r'}"
    value="$(trim "${value}")"
    case "${value}" in
        \"*\")
            value="${value#\"}"
            value="${value%\"}"
            ;;
    esac
    case "${value}" in
        ""|"off/any"|"<hidden>"|"unknown") return 1 ;;
    esac
    printf '%s\n' "${value}"
}

extract_iw_link_ssid() {
    local text="$1" line value
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="$(trim "${line}")"
        case "${line}" in
            SSID:*)
                value="${line#SSID:}"
                strip_wifi_ssid_value "${value}" && return 0
                ;;
        esac
    done <<< "${text}"
    return 1
}

detect_wifi_ssid_iw() {
    command -v iw >/dev/null 2>&1 || return 1
    local output iface line ssid
    output="$(iw dev 2>/dev/null || true)"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="$(trim "${line}")"
        case "${line}" in
            Interface\ *)
                iface="$(trim "${line#Interface }")"
                [[ -n "${iface}" ]] || continue
                ssid="$(extract_iw_link_ssid "$(iw dev "${iface}" link 2>/dev/null || true)" 2>/dev/null || true)"
                if [[ -n "${ssid}" ]]; then
                    printf '%s\n' "${ssid}"
                    return 0
                fi
                ;;
        esac
    done <<< "${output}"
    return 1
}

extract_iwinfo_client_ssid() {
    local text="$1" ssid
    ssid="$(
        printf '%s\n' "${text}" | awk '
            function maybe_emit() {
                if (mode == "Client" && essid != "" && essid != "off/any" && essid != "unknown" && essid != "<hidden>") {
                    print essid
                    found = 1
                    exit 0
                }
            }
            /^[^[:space:]]/ {
                maybe_emit()
                essid = ""
                mode = ""
            }
            {
                if ($0 ~ /ESSID:[[:space:]]*"/) {
                    value = $0
                    sub(/^.*ESSID:[[:space:]]*"/, "", value)
                    sub(/".*$/, "", value)
                    essid = value
                } else if ($0 ~ /ESSID:/) {
                    value = $0
                    sub(/^.*ESSID:[[:space:]]*/, "", value)
                    sub(/[[:space:]].*$/, "", value)
                    essid = value
                }
                if ($0 ~ /Mode:[[:space:]]*/) {
                    value = $0
                    sub(/^.*Mode:[[:space:]]*/, "", value)
                    sub(/[[:space:]].*$/, "", value)
                    mode = value
                }
            }
            END {
                if (!found) {
                    maybe_emit()
                }
            }
        ' 2>/dev/null || true
    )"
    strip_wifi_ssid_value "${ssid}" 2>/dev/null
}

detect_wifi_ssid_iwinfo() {
    command -v iwinfo >/dev/null 2>&1 || return 1
    local output ssid iface path seen=";"
    output="$(iwinfo 2>/dev/null || true)"
    ssid="$(extract_iwinfo_client_ssid "${output}" 2>/dev/null || true)"
    if [[ -n "${ssid}" ]]; then
        printf '%s\n' "${ssid}"
        return 0
    fi
    while IFS= read -r iface || [[ -n "${iface}" ]]; do
        iface="$(trim "${iface}")"
        [[ -n "${iface}" ]] || continue
        [[ "${seen}" == *";${iface};"* ]] && continue
        seen="${seen}${iface};"
        ssid="$(extract_iwinfo_client_ssid "$(iwinfo "${iface}" info 2>/dev/null || true)" 2>/dev/null || true)"
        if [[ -n "${ssid}" ]]; then
            printf '%s\n' "${ssid}"
            return 0
        fi
    done < <(printf '%s\n' "${output}" | awk '/^[^[:space:]]/ { print $1 }' 2>/dev/null || true)
    for path in /sys/class/net/*; do
        [[ -e "${path}" ]] || continue
        iface="${path##*/}"
        [[ -n "${iface}" ]] || continue
        [[ "${seen}" == *";${iface};"* ]] && continue
        seen="${seen}${iface};"
        ssid="$(extract_iwinfo_client_ssid "$(iwinfo "${iface}" info 2>/dev/null || true)" 2>/dev/null || true)"
        if [[ -n "${ssid}" ]]; then
            printf '%s\n' "${ssid}"
            return 0
        fi
    done
    return 1
}

extract_wpa_cli_ssid() {
    local text="$1" line value
    while IFS= read -r line || [[ -n "${line}" ]]; do
        case "${line}" in
            ssid=*)
                value="${line#ssid=}"
                strip_wifi_ssid_value "${value}" && return 0
                ;;
        esac
    done <<< "${text}"
    return 1
}

detect_wifi_ssid_wpa_cli() {
    command -v wpa_cli >/dev/null 2>&1 || return 1
    local ssid sock iface seen=";"
    ssid="$(extract_wpa_cli_ssid "$(wpa_cli status 2>/dev/null || true)" 2>/dev/null || true)"
    if [[ -n "${ssid}" ]]; then
        printf '%s\n' "${ssid}"
        return 0
    fi
    for sock in /var/run/wpa_supplicant/* /run/wpa_supplicant/*; do
        [[ -e "${sock}" ]] || continue
        iface="${sock##*/}"
        [[ -n "${iface}" ]] || continue
        [[ "${seen}" == *";${iface};"* ]] && continue
        seen="${seen}${iface};"
        ssid="$(extract_wpa_cli_ssid "$(wpa_cli -i "${iface}" status 2>/dev/null || true)" 2>/dev/null || true)"
        if [[ -n "${ssid}" ]]; then
            printf '%s\n' "${ssid}"
            return 0
        fi
    done
    return 1
}

detect_wifi_ssid_nmcli() {
    command -v nmcli >/dev/null 2>&1 || return 1
    local line value
    while IFS= read -r line || [[ -n "${line}" ]]; do
        case "${line}" in
            yes:*)
                value="${line#yes:}"
                strip_wifi_ssid_value "${value}" && return 0
                ;;
        esac
    done < <(LC_ALL=C nmcli -t -f active,ssid dev wifi 2>/dev/null || true)
    return 1
}

detect_wifi_ssid_iwgetid() {
    command -v iwgetid >/dev/null 2>&1 || return 1
    strip_wifi_ssid_value "$(iwgetid -r 2>/dev/null || true)" 2>/dev/null
}

detect_wifi_ssid_iwconfig() {
    command -v iwconfig >/dev/null 2>&1 || return 1
    local line value
    while IFS= read -r line || [[ -n "${line}" ]]; do
        case "${line}" in
            *ESSID:\"*)
                value="${line#*ESSID:\"}"
                value="${value%%\"*}"
                strip_wifi_ssid_value "${value}" && return 0
                ;;
            *ESSID:*)
                value="${line#*ESSID:}"
                value="${value%%[[:space:]]*}"
                strip_wifi_ssid_value "${value}" && return 0
                ;;
        esac
    done < <(iwconfig 2>/dev/null || true)
    return 1
}

current_wifi_ssid() {
    local ssid
    ssid="$(detect_wifi_ssid_iw 2>/dev/null || true)"
    [[ -n "${ssid}" ]] && { printf '%s\n' "${ssid}"; return 0; }
    ssid="$(detect_wifi_ssid_iwinfo 2>/dev/null || true)"
    [[ -n "${ssid}" ]] && { printf '%s\n' "${ssid}"; return 0; }
    ssid="$(detect_wifi_ssid_wpa_cli 2>/dev/null || true)"
    [[ -n "${ssid}" ]] && { printf '%s\n' "${ssid}"; return 0; }
    ssid="$(detect_wifi_ssid_nmcli 2>/dev/null || true)"
    [[ -n "${ssid}" ]] && { printf '%s\n' "${ssid}"; return 0; }
    ssid="$(detect_wifi_ssid_iwgetid 2>/dev/null || true)"
    [[ -n "${ssid}" ]] && { printf '%s\n' "${ssid}"; return 0; }
    ssid="$(detect_wifi_ssid_iwconfig 2>/dev/null || true)"
    [[ -n "${ssid}" ]] && { printf '%s\n' "${ssid}"; return 0; }
    return 1
}

wifi_ssid_in_skip_list() {
    local ssid="$1" item
    local -a items=()
    ssid="$(trim "${ssid}")"
    [[ -n "${ssid}" ]] || return 1
    IFS=';' read -r -a items <<< "${SKIP_WIFI_SSIDS:-}"
    for item in "${items[@]}"; do
        item="$(trim "${item}")"
        [[ -n "${item}" ]] || continue
        [[ "${ssid}" == "${item}" ]] && return 0
    done
    return 1
}

force_report_enabled() {
    case "$(to_lower "${FORCE_REPORT:-}")" in
        1|true|yes|y) return 0 ;;
        *) return 1 ;;
    esac
}

wifi_ssid_report_skip_match() {
    local ssid
    SKIP_WIFI_SSIDS="$(normalize_wifi_ssid_skip_list "${SKIP_WIFI_SSIDS:-}")"
    [[ -n "${SKIP_WIFI_SSIDS}" ]] || return 1
    ssid="$(current_wifi_ssid 2>/dev/null || true)"
    [[ -n "${ssid}" ]] || return 1
    wifi_ssid_in_skip_list "${ssid}" || return 1
    printf '%s\n' "${ssid}"
}

skip_report_for_wifi_ssid_if_needed() {
    local ssid
    force_report_enabled && return 1
    ssid="$(wifi_ssid_report_skip_match 2>/dev/null || true)"
    [[ -n "${ssid}" ]] || return 1
    self_report_completed "已跳过：当前 Wi-Fi SSID \"${ssid}\" 在跳过列表中。"
    return 0
}
