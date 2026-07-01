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

wifi_ssid_read_failure_label() {
    case "${WIFI_SSID_LAST_ERROR:-}" in
        privacy)
            printf '读取失败或被 macOS 隐私权限隐藏（fail-open）\n'
            ;;
        *)
            printf '读取失败或未连接（fail-open）\n'
            ;;
    esac
}

accepted_wifi_ssid_value() {
    local ssid lowered
    ssid="$(trim "${1:-}")"
    lowered="$(to_lower "${ssid}")"
    case "${lowered}" in
        ""|"<none>")
            return 1
            ;;
        "<redacted>"|"redacted")
            return 2
            ;;
    esac
    printf '%s\n' "${ssid}"
}

capture_wifi_ssid_probe() {
    local ssid rc
    WIFI_SSID_PROBE_VALUE=""
    rc=0
    ssid="$("$@" 2>/dev/null)" || rc=$?
    if [[ "${rc}" == "0" && -n "${ssid}" ]]; then
        WIFI_SSID_LAST_ERROR=""
        WIFI_SSID_PROBE_VALUE="${ssid}"
        return 0
    fi
    if [[ "${rc}" == "2" ]]; then
        WIFI_SSID_LAST_ERROR="privacy"
    fi
    return 1
}

print_wifi_ssid_permission_guidance() {
    printf '%s\n' \
        "权限说明：macOS 可能把 Wi-Fi SSID/BSSID 作为定位相关信息保护。" \
        "Location Services：如果系统隐藏 SSID，请在 macOS 定位服务里授权当前终端或运行环境。" \
        "如果看到 redacted，请在 系统设置 > 隐私与安全性 > 定位服务 中允许当前终端或运行环境访问位置。" \
        "launchd 后台任务和手动 Terminal/iTerm 可能是不同授权主体；授权后请重新运行 --show-wifi-ssid 验证。" \
        "no auto-grant：本脚本只做诊断和提示，不会自动授予 macOS 隐私权限。" \
        "本脚本不会自动获取或修改系统权限，不会写入 TCC 数据库，不会使用 sudo 缓存凭据。" \
        "读取不到 SSID 时仍会 fail-open 继续正常上报。"
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

networksetup_all_devices() {
    command -v networksetup >/dev/null 2>&1 || return 1
    networksetup -listallhardwareports 2>/dev/null | awk '
        /^Device:[[:space:]]*/ {
            sub(/^Device:[[:space:]]*/, "")
            if ($0 != "") {
                print
            }
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
        *"not associated"*|*"Not associated"*|*"not a Wi-Fi interface"*|*"not a Wi-Fi device"*|*"not an AirPort interface"*|"")
            return 1
            ;;
    esac
    [[ "${output}" == *:* ]] || return 1
    ssid="${output#*:}"
    accepted_wifi_ssid_value "${ssid}"
}

networksetup_any_wifi_ssid() {
    local device ssid seen=";" rc
    while IFS= read -r device || [[ -n "${device}" ]]; do
        device="$(trim "${device}")"
        [[ -n "${device}" ]] || continue
        case "${seen}" in
            *";${device};"*) continue ;;
        esac
        seen="${seen}${device};"
        rc=0
        ssid="$(networksetup_wifi_ssid "${device}" 2>/dev/null)" || rc=$?
        if [[ "${rc}" == "0" && -n "${ssid}" ]]; then
            printf '%s\n' "${ssid}"
            return 0
        fi
        [[ "${rc}" == "2" ]] && return 2
    done < <(networksetup_all_devices)
    return 1
}

networksetup_common_wifi_ssid() {
    local device ssid rc
    for device in en0 en1 en2; do
        rc=0
        ssid="$(networksetup_wifi_ssid "${device}" 2>/dev/null)" || rc=$?
        if [[ "${rc}" == "0" && -n "${ssid}" ]]; then
            printf '%s\n' "${ssid}"
            return 0
        fi
        [[ "${rc}" == "2" ]] && return 2
    done
    return 1
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
    accepted_wifi_ssid_value "${ssid}"
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
    accepted_wifi_ssid_value "${ssid}"
}

wdutil_wifi_ssid() {
    local ssid
    command -v wdutil >/dev/null 2>&1 || return 1
    ssid="$(wdutil info 2>/dev/null | awk '
        /^[[:space:]]*SSID[[:space:]]*:/ {
            line=$0
            sub(/^[^:]*:[[:space:]]*/, "", line)
            print line
            exit
        }
    ')"
    case "$(to_lower "$(trim "${ssid}")")" in
        none)
            return 1
            ;;
    esac
    accepted_wifi_ssid_value "${ssid}"
}

current_wifi_ssid() {
    local device
    WIFI_SSID_LAST_ERROR=""
    WIFI_SSID_PROBE_VALUE=""
    device="$(wifi_hardware_device 2>/dev/null || true)"
    if [[ -n "${device}" ]]; then
        if capture_wifi_ssid_probe networksetup_wifi_ssid "${device}"; then
            printf '%s\n' "${WIFI_SSID_PROBE_VALUE}"
            return 0
        fi
        if capture_wifi_ssid_probe ipconfig_wifi_ssid "${device}"; then
            printf '%s\n' "${WIFI_SSID_PROBE_VALUE}"
            return 0
        fi
    fi
    if capture_wifi_ssid_probe networksetup_any_wifi_ssid; then
        printf '%s\n' "${WIFI_SSID_PROBE_VALUE}"
        return 0
    fi
    if capture_wifi_ssid_probe networksetup_common_wifi_ssid; then
        printf '%s\n' "${WIFI_SSID_PROBE_VALUE}"
        return 0
    fi
    if capture_wifi_ssid_probe airport_wifi_ssid; then
        printf '%s\n' "${WIFI_SSID_PROBE_VALUE}"
        return 0
    fi
    if capture_wifi_ssid_probe wdutil_wifi_ssid; then
        printf '%s\n' "${WIFI_SSID_PROBE_VALUE}"
        return 0
    fi
    return 1
}

current_wifi_ssid_label() {
    if current_wifi_ssid >/dev/null 2>&1; then
        printf '%s\n' "${WIFI_SSID_PROBE_VALUE}"
    else
        wifi_ssid_read_failure_label
    fi
}

show_current_wifi_ssid_once() {
    if current_wifi_ssid >/dev/null 2>&1; then
        printf '当前 Wi-Fi SSID：%s\n' "${WIFI_SSID_PROBE_VALUE}"
        return 0
    fi
    printf '当前 Wi-Fi SSID：%s\n' "$(wifi_ssid_read_failure_label)"
    return 1
}

show_wifi_ssid_permission_help() {
    if current_wifi_ssid >/dev/null 2>&1; then
        printf '当前 Wi-Fi SSID：%s\n\n' "${WIFI_SSID_PROBE_VALUE}"
    else
        printf '当前 Wi-Fi SSID：%s\n\n' "$(wifi_ssid_read_failure_label)"
    fi
    print_wifi_ssid_permission_guidance
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
    current_wifi_ssid >/dev/null 2>&1 || return 1
    ssid="${WIFI_SSID_PROBE_VALUE:-}"
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
