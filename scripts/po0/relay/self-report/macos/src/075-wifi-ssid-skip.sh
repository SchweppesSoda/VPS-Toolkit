normalize_wifi_ssid_skip_list() {
    local raw="$1" rest item out=""
    rest="${raw};"
    while [[ -n "${rest}" ]]; do
        item="${rest%%;*}"
        rest="${rest#*;}"
        item="$(trim "${item}")"
        [[ -n "${item}" ]] || continue
        if [[ -n "${out}" ]]; then
            out="${out};${item}"
        else
            out="${item}"
        fi
    done
    printf '%s' "${out}"
}

append_skip_wifi_ssid() {
    local ssid="$1"
    ssid="$(trim "${ssid}")"
    [[ -n "${ssid}" ]] || return 0
    if [[ -n "${SKIP_WIFI_SSIDS}" ]]; then
        SKIP_WIFI_SSIDS="${SKIP_WIFI_SSIDS};${ssid}"
    else
        SKIP_WIFI_SSIDS="${ssid}"
    fi
    SKIP_WIFI_SSIDS="$(normalize_wifi_ssid_skip_list "${SKIP_WIFI_SSIDS}")"
}

skip_wifi_ssids_label() {
    local list
    list="$(normalize_wifi_ssid_skip_list "${SKIP_WIFI_SSIDS:-}")"
    if [[ -n "${list}" ]]; then
        printf '%s\n' "${list}"
    else
        printf '未设置\n'
    fi
}

wifi_hardware_device() {
    command -v networksetup >/dev/null 2>&1 || return 1
    networksetup -listallhardwareports 2>/dev/null | awk '
        /^Hardware Port: / {
            port=$0
            sub(/^Hardware Port: /, "", port)
            wifi=(port == "Wi-Fi" || port == "AirPort")
            next
        }
        wifi && /^Device: / {
            sub(/^Device: /, "")
            print
            exit
        }
    '
}

networksetup_wifi_ssid() {
    local device="$1" output ssid
    [[ -n "${device}" ]] || return 1
    command -v networksetup >/dev/null 2>&1 || return 1
    output="$(networksetup -getairportnetwork "${device}" 2>/dev/null || true)"
    output="${output%$'\r'}"
    case "${output}" in
        *"not associated"*|*"Not associated"*|"")
            return 1
            ;;
    esac
    [[ "${output}" == *:* ]] || return 1
    ssid="${output#*:}"
    ssid="$(trim "${ssid}")"
    [[ -n "${ssid}" ]] || return 1
    printf '%s\n' "${ssid}"
}

ipconfig_wifi_ssid() {
    local device="$1" ssid
    [[ -n "${device}" ]] || return 1
    command -v ipconfig >/dev/null 2>&1 || return 1
    ssid="$(ipconfig getsummary "${device}" 2>/dev/null | awk '
        /^[[:space:]]*SSID[[:space:]]*:/ {
            line=$0
            sub(/^[^:]*:[[:space:]]*/, "", line)
            print line
            exit
        }
    ')"
    ssid="$(trim "${ssid}")"
    [[ -n "${ssid}" ]] || return 1
    printf '%s\n' "${ssid}"
}

airport_command_path() {
    if command -v airport >/dev/null 2>&1; then
        command -v airport
        return 0
    fi
    if [[ -x "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport" ]]; then
        printf '%s\n' "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"
        return 0
    fi
    return 1
}

airport_wifi_ssid() {
    local airport ssid
    airport="$(airport_command_path 2>/dev/null || true)"
    [[ -n "${airport}" ]] || return 1
    ssid="$("${airport}" -I 2>/dev/null | awk '
        /^[[:space:]]*SSID[[:space:]]*:/ {
            line=$0
            sub(/^[^:]*:[[:space:]]*/, "", line)
            print line
            exit
        }
    ')"
    ssid="$(trim "${ssid}")"
    [[ -n "${ssid}" ]] || return 1
    printf '%s\n' "${ssid}"
}

current_wifi_ssid() {
    local device ssid
    device="$(wifi_hardware_device 2>/dev/null || true)"
    if [[ -n "${device}" ]]; then
        ssid="$(networksetup_wifi_ssid "${device}" 2>/dev/null || true)"
        if [[ -n "${ssid}" ]]; then
            printf '%s\n' "${ssid}"
            return 0
        fi
        ssid="$(ipconfig_wifi_ssid "${device}" 2>/dev/null || true)"
        if [[ -n "${ssid}" ]]; then
            printf '%s\n' "${ssid}"
            return 0
        fi
    fi
    ssid="$(airport_wifi_ssid 2>/dev/null || true)"
    if [[ -n "${ssid}" ]]; then
        printf '%s\n' "${ssid}"
        return 0
    fi
    return 1
}

current_wifi_ssid_label() {
    local ssid
    ssid="$(current_wifi_ssid 2>/dev/null || true)"
    if [[ -n "${ssid}" ]]; then
        printf '%s\n' "${ssid}"
    else
        printf '读取失败或未连接（fail-open）\n'
    fi
}

wifi_ssid_in_skip_list() {
    local ssid="$1" list="${2:-${SKIP_WIFI_SSIDS:-}}" rest item
    list="$(normalize_wifi_ssid_skip_list "${list}")"
    [[ -n "${ssid}" && -n "${list}" ]] || return 1
    rest="${list};"
    while [[ -n "${rest}" ]]; do
        item="${rest%%;*}"
        rest="${rest#*;}"
        item="$(trim "${item}")"
        [[ -n "${item}" ]] || continue
        [[ "${item}" == "${ssid}" ]] && return 0
    done
    return 1
}

force_report_enabled() {
    case "$(to_lower "${FORCE_REPORT:-0}")" in
        1|true|yes|y|on|enabled) return 0 ;;
        *) return 1 ;;
    esac
}

should_skip_wifi_ssid_report() {
    local list ssid
    force_report_enabled && return 1
    list="$(normalize_wifi_ssid_skip_list "${SKIP_WIFI_SSIDS:-}")"
    [[ -n "${list}" ]] || return 1
    ssid="$(current_wifi_ssid 2>/dev/null || true)"
    [[ -n "${ssid}" ]] || return 1
    if wifi_ssid_in_skip_list "${ssid}" "${list}"; then
        WIFI_SKIP_LAST_SSID="${ssid}"
        return 0
    fi
    return 1
}

wifi_ssid_skip_message() {
    local ssid="${1:-${WIFI_SKIP_LAST_SSID:-}}"
    if [[ -n "${ssid}" ]]; then
        printf '已跳过：当前 Wi-Fi SSID "%s" 命中跳过列表。' "${ssid}"
    else
        printf '已跳过：当前 Wi-Fi SSID 命中跳过列表。'
    fi
}

prompt_skip_wifi_ssids_interactive() {
    local input
    SKIP_WIFI_SSIDS="$(normalize_wifi_ssid_skip_list "${SKIP_WIFI_SSIDS:-}")"
    if [[ -n "${SKIP_WIFI_SSIDS}" ]]; then
        input="$(read_prompt "跳过上报的 Wi-Fi SSID（分号 ; 分隔，精确大小写匹配；回车保留，输入 - 清空）[${SKIP_WIFI_SSIDS}]: ")" || input=""
        input="$(trim "${input}")"
        case "${input}" in
            "") ;;
            "-") SKIP_WIFI_SSIDS="" ;;
            *) SKIP_WIFI_SSIDS="$(normalize_wifi_ssid_skip_list "${input}")" ;;
        esac
    else
        input="$(read_prompt "跳过上报的 Wi-Fi SSID（分号 ; 分隔，留空不跳过）: ")" || input=""
        SKIP_WIFI_SSIDS="$(normalize_wifi_ssid_skip_list "${input}")"
    fi
}
