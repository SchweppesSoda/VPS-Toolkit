is_public_ipv4() {
    local ip="$1" o1 o2 o3 o4
    [[ "${ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS='.' read -r o1 o2 o3 o4 <<< "${ip}"
    for o in "${o1}" "${o2}" "${o3}" "${o4}"; do
        (( o >= 0 && o <= 255 )) || return 1
    done
    (( o1 == 0 || o1 == 10 || o1 == 127 || o1 >= 224 )) && return 1
    (( o1 == 100 && o2 >= 64 && o2 <= 127 )) && return 1
    (( o1 == 169 && o2 == 254 )) && return 1
    (( o1 == 172 && o2 >= 16 && o2 <= 31 )) && return 1
    (( o1 == 192 && o2 == 168 )) && return 1
    (( o1 == 198 && o2 >= 18 && o2 <= 19 )) && return 1
    return 0
}


normalize_wan_selection_list() {
    local value="${1:-}" rest item lowered out=""
    value="${value//,/;}"
    rest="${value};"
    while [[ "${rest}" == *";"* ]]; do
        item="${rest%%;*}"
        rest="${rest#*;}"
        item="$(trim "${item}")"
        [[ -n "${item}" ]] || continue
        lowered="$(to_lower "${item}")"
        if [[ "${lowered}" == "all" ]]; then
            printf 'all\n'
            return 0
        fi
        case ";${out};" in
            *";${item};"*) ;;
            *)
                if [[ -n "${out}" ]]; then
                    out+=";${item}"
                else
                    out="${item}"
                fi
                ;;
        esac
    done
    printf '%s\n' "${out}"
}

append_wan_selection_value() {
    local value="${1:-}"
    if [[ "${WANS_CLI_SEEN:-0}" != "1" ]]; then
        WANS=""
        WANS_CLI_SEEN="1"
    fi
    if [[ -n "${WANS}" ]]; then
        WANS="${WANS};${value}"
    else
        WANS="${value}"
    fi
    WANS="$(normalize_wan_selection_list "${WANS}")"
}

validate_wan_selection() {
    local selection rest wan
    selection="$(normalize_wan_selection_list "${WANS:-}")"
    [[ -n "${selection}" ]] || return 0
    [[ "${selection}" == "all" ]] && return 0
    rest="${selection};"
    while [[ "${rest}" == *";"* ]]; do
        wan="${rest%%;*}"
        rest="${rest#*;}"
        [[ -n "${wan}" ]] || continue
        if [[ ! "${wan}" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$ ]]; then
            printf 'OpenWrt WAN 逻辑接口名无效：%s\n' "${wan}" >&2
            return 1
        fi
    done
}

gateway_source_mode() {
    [[ "${PO0_OUTBOUND_IP_REPORT_PROBE_MODE:-}" == source ]]
}

gateway_wan_source() {
    local wan="$1" source=''
    case "$wan" in
        wan1) source="${PO0_OUTBOUND_IP_REPORT_SOURCE_WAN1:-}" ;;
        wan2) source="${PO0_OUTBOUND_IP_REPORT_SOURCE_WAN2:-}" ;;
        *) return 1 ;;
    esac
    [[ "$source" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    ip -o -4 address show | awk -v wanted="$source" '
        { split($4, address, "/"); if (address[1] == wanted) found = 1 }
        END { exit !found }
    ' || return 1
    printf '%s\n' "$source"
}


openwrt_wan_l3_device() {
    local wan="$1" status up device
    command -v ubus >/dev/null 2>&1 || return 1
    command -v jsonfilter >/dev/null 2>&1 || return 1
    status="$(ubus call "network.interface.${wan}" status 2>/dev/null)" || return 1
    up="$(printf '%s' "${status}" | jsonfilter -e '@.up' 2>/dev/null || true)"
    [[ "${up}" == "true" || "${up}" == "1" ]] || return 1
    device="$(printf '%s' "${status}" | jsonfilter -e '@.l3_device' 2>/dev/null || true)"
    device="$(trim "${device}")"
    [[ -n "${device}" ]] || return 1
    printf '%s\n' "${device}"
}


# Resolve each probe through the configured real DNS service. Only answer
# addresses following a Name record are accepted, never the resolver address.
gateway_probe_resolve() {
    local url="$1" authority host port dns raw address addresses=''
    dns="${PO0_OUTBOUND_IP_REPORT_PROBE_DNS_SERVER:-192.168.88.1}"
    [[ "$dns" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    printf '%s\n' "$dns" | awk -F. '{ for (i=1;i<=4;i++) if ($i+0>255) exit 1 }' || return 1
    case "$url" in
        https://*) authority="${url#https://}"; port=443 ;;
        http://*) authority="${url#http://}"; port=80 ;;
        *) return 1 ;;
    esac
    authority="${authority%%[/?#]*}"
    host="${authority%%:*}"
    if [[ "$authority" == *:* ]]; then port="${authority#*:}"; fi
    [[ "$host" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ && "$port" =~ ^[0-9]{1,5}$ ]] || return 1
    (( 10#$port >= 1 && 10#$port <= 65535 )) || return 1
    if [[ "$host" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        is_public_ipv4 "$host" || return 1
        printf '%s:%s:%s\n' "$host" "$port" "$host"
        return 0
    fi
    command -v nslookup >/dev/null 2>&1 || return 1
    raw="$(nslookup -type=A "$host" "$dns" 2>/dev/null)" || return 1
    while IFS= read -r address; do
        [[ -n "$address" ]] || continue
        is_public_ipv4 "$address" || return 1
        case ",$addresses," in *",$address,"*) continue ;; esac
        addresses="${addresses:+${addresses},}${address}"
    done < <(printf '%s\n' "$raw" | awk '
        /^[[:space:]]*Name:[[:space:]]*/ { answer=1; next }
        answer && /^[[:space:]]*Address([[:space:]]+[0-9]+)?:[[:space:]]*/ {
            sub(/^[^:]*:[[:space:]]*/, ""); split($0, fields, /[[:space:]]+/); print fields[1]
        }
    ')
    [[ -n "$addresses" ]] || return 1
    printf '%s:%s:%s\n' "$host" "$port" "$addresses"
}


ip_check_state_file() {
    if [[ -n "${XDG_STATE_HOME:-}" ]]; then
        printf '%s\n' "${XDG_STATE_HOME}/po0-outbound-ip-report/ip-check-index"
    elif [[ -n "${HOME:-}" ]]; then
        printf '%s\n' "${HOME}/.local/state/po0-outbound-ip-report/ip-check-index"
    else
        printf '%s\n' "/tmp/po0-outbound-ip-report-ip-check-index"
    fi
}

legacy_ip_check_state_file() {
    if [[ -n "${XDG_STATE_HOME:-}" ]]; then
        printf '%s\n' "${XDG_STATE_HOME}/po0-self-report/ip-check-index"
    elif [[ -n "${HOME:-}" ]]; then
        printf '%s\n' "${HOME}/.local/state/po0-self-report/ip-check-index"
    else
        printf '%s\n' "/tmp/po0-self-report-ip-check-index"
    fi
}
