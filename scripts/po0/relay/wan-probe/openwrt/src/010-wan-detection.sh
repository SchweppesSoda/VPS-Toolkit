trim() {
    printf '%s' "${1:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

append_allowed_source() {
    ALLOWED_SOURCES="${ALLOWED_SOURCES}${ALLOWED_SOURCES:+
}$1"
}

append_allowed_wan() {
    ALLOWED_WANS="${ALLOWED_WANS}${ALLOWED_WANS:+
}$1"
}

load_probe_config() {
    if [ -r /lib/functions.sh ] && command -v uci >/dev/null 2>&1; then
        # shellcheck disable=SC1091
        . /lib/functions.sh
        config_load "${CONFIG_NAME}" 2>/dev/null || true
        config_get PROBE_ENABLED "${CONFIG_SECTION}" enabled "1"
        config_get IP_CHECK_URLS "${CONFIG_SECTION}" ip_check_urls "${DEFAULT_IP_CHECK_URLS}"
        config_list_foreach "${CONFIG_SECTION}" allowed_source append_allowed_source
        config_list_foreach "${CONFIG_SECTION}" wan append_allowed_wan
    fi
    [ -n "${ALLOWED_SOURCES}" ] || ALLOWED_SOURCES="${DEFAULT_ALLOWED_SOURCE}"
}

valid_wan_name() {
    case "${1:-}" in
        ""|*[!A-Za-z0-9_.-]*|-*|.*) return 1 ;;
        *) [ "${#1}" -le 64 ] ;;
    esac
}

is_public_ipv4() {
    ip="${1:-}"
    old_ifs="${IFS}"
    IFS=.
    set -- ${ip}
    IFS="${old_ifs}"
    [ "$#" -eq 4 ] || return 1
    for octet in "$@"; do
        case "${octet}" in ""|*[!0-9]*) return 1 ;; esac
        [ "${octet}" -le 255 ] 2>/dev/null || return 1
    done
    o1="$1" o2="$2"
    [ "${o1}" -ne 0 ] && [ "${o1}" -ne 10 ] && [ "${o1}" -ne 127 ] && [ "${o1}" -lt 224 ] || return 1
    { [ "${o1}" -ne 100 ] || [ "${o2}" -lt 64 ] || [ "${o2}" -gt 127 ]; } || return 1
    { [ "${o1}" -ne 169 ] || [ "${o2}" -ne 254 ]; } || return 1
    { [ "${o1}" -ne 172 ] || [ "${o2}" -lt 16 ] || [ "${o2}" -gt 31 ]; } || return 1
    { [ "${o1}" -ne 192 ] || [ "${o2}" -ne 168 ]; } || return 1
    { [ "${o1}" -ne 198 ] || [ "${o2}" -lt 18 ] || [ "${o2}" -gt 19 ]; } || return 1
}

extract_first_public_ipv4() {
    printf '%s\n' "${1:-}" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' 2>/dev/null | while IFS= read -r candidate; do
        if is_public_ipv4 "${candidate}"; then
            printf '%s\n' "${candidate}"
            break
        fi
    done
}

list_enabled_mwan3_wans() {
    command -v uci >/dev/null 2>&1 || return 1
    found=0
    uci -q show mwan3 2>/dev/null | sed -n 's/^mwan3\.\([^.=]*\)=interface$/\1/p' | while IFS= read -r wan; do
        valid_wan_name "${wan}" || continue
        enabled="$(uci -q get "mwan3.${wan}.enabled" 2>/dev/null || printf '1')"
        case "${enabled}" in 0|false|no|off) continue ;; esac
        printf '%s\n' "${wan}"
    done
}

wan_is_enabled() {
    wanted="$1"
    list_enabled_mwan3_wans | while IFS= read -r wan; do
        [ "${wan}" = "${wanted}" ] && exit 0
    done
    [ "$(list_enabled_mwan3_wans | grep -Fxc "${wanted}" 2>/dev/null || true)" -gt 0 ]
}

wan_is_allowed() {
    wanted="$1"
    [ -n "${ALLOWED_WANS}" ] || return 0
    printf '%s\n' "${ALLOWED_WANS}" | grep -Fqx "${wanted}"
}

source_is_allowed() {
    remote="${REMOTE_ADDR:-}"
    [ -n "${remote}" ] || return 1
    printf '%s\n' "${ALLOWED_SOURCES}" | grep -Fqx "${remote}"
}

wan_status_json() {
    wan="$1"
    command -v ubus >/dev/null 2>&1 || return 1
    ubus call "network.interface.${wan}" status 2>/dev/null
}

wan_l3_device() {
    status="$(wan_status_json "$1")" || return 1
    up="$(printf '%s' "${status}" | jsonfilter -e '@.up' 2>/dev/null || true)"
    [ "${up}" = "true" ] || [ "${up}" = "1" ] || return 1
    device="$(printf '%s' "${status}" | jsonfilter -e '@.l3_device' 2>/dev/null || true)"
    device="$(trim "${device}")"
    [ -n "${device}" ] || return 1
    printf '%s\n' "${device}"
}

wan_interface_public_ipv4() {
    status="$(wan_status_json "$1")" || return 1
    ip="$(printf '%s' "${status}" | jsonfilter -e '@["ipv4-address"][0].address' 2>/dev/null || true)"
    ip="$(trim "${ip}")"
    is_public_ipv4 "${ip}" || return 1
    printf '%s\n' "${ip}"
}

wan_external_public_ipv4() {
    device="$1"
    command -v curl >/dev/null 2>&1 || return 1
    old_ifs="${IFS}"
    IFS=,
    set -- ${IP_CHECK_URLS}
    IFS="${old_ifs}"
    for url in "$@"; do
        url="$(trim "${url}")"
        [ -n "${url}" ] || continue
        raw="$(curl -4 -fsSL --interface "${device}" --connect-timeout 10 --max-time 20 "${url}" 2>/dev/null || true)"
        ip="$(extract_first_public_ipv4 "${raw}" | head -n 1)"
        [ -n "${ip}" ] || continue
        printf '%s\n' "${ip}"
        return 0
    done
    return 1
}

detect_wan_public_ipv4() {
    wan="$1"
    ip="$(wan_interface_public_ipv4 "${wan}" 2>/dev/null || true)"
    if [ -n "${ip}" ]; then
        printf '%s\n' "${ip}"
        return 0
    fi
    device="$(wan_l3_device "${wan}")" || return 1
    wan_external_public_ipv4 "${device}"
}

json_escape() {
    printf '%s' "${1:-}" | sed 's/\\/\\\\/g;s/"/\\"/g'
}

