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

extract_first_public_ipv4() {
    local text="$1" ip
    while IFS= read -r ip; do
        ip="$(trim "${ip}")"
        is_public_ipv4 "${ip}" || continue
        printf '%s\n' "${ip}"
        return 0
    done < <(printf '%s\n' "${text}" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' || true)
    return 1
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

wan_selection_display() {
    local selection
    selection="$(normalize_wan_selection_list "${WANS:-}")"
    case "${selection}" in
        "")
            if [[ -n "${ROUTER_PROBE_URL:-}" ]]; then
                printf '上游路由器全部已启用的 mwan3 WAN\n'
            else
                printf '默认路由（单出口）\n'
            fi
            ;;
        all)
            if [[ -n "${ROUTER_PROBE_URL:-}" ]]; then
                printf '上游路由器全部已启用的 mwan3 WAN\n'
            else
                printf '全部已启用的 mwan3 WAN\n'
            fi
            ;;
        *) printf '%s\n' "${selection}" ;;
    esac
}

list_enabled_mwan3_wans() {
    local wan enabled found=0
    command -v uci >/dev/null 2>&1 || return 1
    command -v ubus >/dev/null 2>&1 || return 1
    while IFS= read -r wan; do
        wan="$(trim "${wan}")"
        [[ -n "${wan}" ]] || continue
        enabled="$(uci -q get "mwan3.${wan}.enabled" 2>/dev/null || printf '1')"
        case "$(to_lower "$(trim "${enabled}")")" in
            0|false|no|off) continue ;;
        esac
        printf '%s\n' "${wan}"
        found=1
    done < <(uci -q show mwan3 2>/dev/null | sed -n 's/^mwan3\.\([^.=]*\)=interface$/\1/p')
    [[ "${found}" == "1" ]]
}

resolve_report_wans() {
    local selection rest wan
    selection="$(normalize_wan_selection_list "${WANS:-}")"
    if [[ -n "${ROUTER_PROBE_URL:-}" && ( -z "${selection}" || "${selection}" == "all" ) ]]; then
        list_upstream_router_wans
        return $?
    fi
    if [[ -z "${selection}" ]]; then
        printf '__default__\n'
        return 0
    fi
    if [[ "${selection}" == "all" ]]; then
        list_enabled_mwan3_wans
        return $?
    fi
    rest="${selection};"
    while [[ "${rest}" == *";"* ]]; do
        wan="${rest%%;*}"
        rest="${rest#*;}"
        [[ -n "${wan}" ]] && printf '%s\n' "${wan}"
    done
}

router_probe_http_get() {
    local wan="$1"
    command -v curl >/dev/null 2>&1 || return 1
    curl -4 -fsS --connect-timeout 5 --max-time 30 "${ROUTER_PROBE_URL}?wan=${wan}"
}

prepare_router_probe_batch() {
    local selection raw first_name
    ROUTER_PROBE_BATCH_RAW=""
    [[ -n "${ROUTER_PROBE_URL:-}" ]] || return 0
    selection="$(normalize_wan_selection_list "${WANS:-}")"
    [[ -z "${selection}" || "${selection}" == "all" ]] || return 0
    command -v jsonfilter >/dev/null 2>&1 || return 0
    raw="$(router_probe_http_get all 2>/dev/null || true)"
    [[ -n "${raw}" ]] || return 0
    first_name="$(printf '%s' "${raw}" | jsonfilter -e '@.wans[0].name' 2>/dev/null || true)"
    [[ "${first_name}" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$ ]] || return 0
    ROUTER_PROBE_BATCH_RAW="${raw}"
}

router_probe_batch_field() {
    local wan="$1" field="$2" index=0 name value
    [[ -n "${ROUTER_PROBE_BATCH_RAW:-}" ]] || return 1
    while (( index < 128 )); do
        name="$(printf '%s' "${ROUTER_PROBE_BATCH_RAW}" | jsonfilter -e "@.wans[${index}].name" 2>/dev/null || true)"
        [[ -n "${name}" ]] || return 1
        if [[ "${name}" == "${wan}" ]]; then
            value="$(printf '%s' "${ROUTER_PROBE_BATCH_RAW}" | jsonfilter -e "@.wans[${index}].${field}" 2>/dev/null || true)"
            printf '%s\n' "${value}"
            return 0
        fi
        index=$((index + 1))
    done
    return 1
}

list_upstream_router_wans() {
    local raw wan found=0 index=0
    if [[ -n "${ROUTER_PROBE_BATCH_RAW:-}" ]]; then
        while (( index < 128 )); do
            wan="$(printf '%s' "${ROUTER_PROBE_BATCH_RAW}" | jsonfilter -e "@.wans[${index}].name" 2>/dev/null || true)"
            [[ -n "${wan}" ]] || break
            [[ "${wan}" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$ ]] || return 1
            printf '%s\n' "${wan}"
            found=1
            index=$((index + 1))
        done
        [[ "${found}" == "1" ]]
        return $?
    fi
    raw="$(router_probe_http_get list)" || return 1
    while IFS= read -r wan; do
        wan="$(trim "${wan}")"
        [[ -n "${wan}" ]] || continue
        [[ "${wan}" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$ ]] || return 1
        printf '%s\n' "${wan}"
        found=1
    done <<< "${raw}"
    [[ "${found}" == "1" ]]
}

detect_outbound_ipv4_via_router() {
    local wan="$1" raw ip ok
    if [[ -n "${ROUTER_PROBE_BATCH_RAW:-}" ]]; then
        ok="$(router_probe_batch_field "${wan}" ok 2>/dev/null || true)"
        [[ "${ok}" == "true" || "${ok}" == "1" ]] || return 1
        ip="$(router_probe_batch_field "${wan}" ip 2>/dev/null || true)"
        is_public_ipv4 "${ip}" || return 1
        printf '%s\n' "${ip}"
        return 0
    fi
    raw="$(router_probe_http_get "${wan}")" || return 1
    ip="$(extract_first_public_ipv4 "${raw}" 2>/dev/null || true)"
    [[ -n "${ip}" ]] || return 1
    printf '%s\n' "${ip}"
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

wan_scoped_report_token() {
    local base="$1" wan="$2" fallback="$3" suffix max_base
    base="$(normalize_report_token "${base}" "${fallback}")"
    suffix="$(sanitize_device_id_part "${wan}" 2>/dev/null || printf 'wan')"
    [[ ${#suffix} -le 24 ]] || suffix="${suffix:0:24}"
    max_base=$((47 - ${#suffix}))
    (( max_base >= 1 )) || max_base=1
    [[ ${#base} -le max_base ]] || base="${base:0:max_base}"
    while [[ "${base}" == *- ]]; do base="${base%-}"; done
    [[ -n "${base}" ]] || base="r"
    printf '%s-%s\n' "${base}" "${suffix}"
}

fetch_url_no_proxy() {
    local url="$1" bind_device="${2:-}"
    if command -v curl >/dev/null 2>&1; then
        if [[ -n "${bind_device}" ]]; then
            env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
                curl -4 -fsSL --noproxy '*' --interface "${bind_device}" --connect-timeout 10 --max-time 20 "${url}"
        else
            env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
                curl -4 -fsSL --noproxy '*' --connect-timeout 10 --max-time 20 "${url}"
        fi
        return $?
    fi
    if [[ -n "${bind_device}" ]]; then
        echo "缺少 curl，无法绑定 WAN 接口探测公网出口 IPv4。" >&2
        return 1
    fi
    if command -v wget >/dev/null 2>&1; then
        env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
            wget -q -T 20 -O- "${url}"
        return $?
    fi
    echo "缺少 curl 或 wget，无法探测公网出口 IPv4。" >&2
    return 1
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

read_ip_check_index() {
    local count="$1" state raw
    [[ "${count}" =~ ^[0-9]+$ && "${count}" -gt 0 ]] || { printf '0\n'; return 0; }
    state="$(ip_check_state_file)"
    if [[ ! -r "${state}" && -r "$(legacy_ip_check_state_file)" ]]; then
        state="$(legacy_ip_check_state_file)"
    fi
    if [[ -r "${state}" ]]; then
        IFS= read -r raw < "${state}" || raw=""
        raw="$(digits_only "${raw}")"
    else
        raw=""
    fi
    [[ -n "${raw}" ]] || raw="0"
    printf '%s\n' "$((raw % count))"
}

write_ip_check_index() {
    local count="$1" index="$2" state dir
    [[ "${count}" =~ ^[0-9]+$ && "${count}" -gt 0 ]] || return 0
    [[ "${index}" =~ ^[0-9]+$ ]] || index="0"
    state="$(ip_check_state_file)"
    dir="$(dirname "${state}")"
    mkdir -p "${dir}" 2>/dev/null || true
    printf '%s\n' "$((index % count))" > "${state}" 2>/dev/null || true
}

detect_outbound_ipv4() {
    local bind_device="${1:-}" urls raw url ip start i idx count
    local -a url_array=()
    if [[ -n "${IP_CHECK_URLS}" ]]; then
        urls="${IP_CHECK_URLS}"
    else
        urls="${IP_CHECK_URL},https://mail.163.com/fgw/mailsrv-ipdetail/detail,https://api.live.bilibili.com/client/v1/Ip/getInfoNew,https://ipservice.ws.126.net/locate/api/getLocByIp,https://r.inews.qq.com/api/ip2city?otype=json,https://data.video.iqiyi.com/v.f4v,https://ip.apps.cntv.cn/whereis?client=json,https://myip.ipip.net/json"
    fi
    IFS=',' read -r -a url_array <<< "${urls}"
    count="${#url_array[@]}"
    [[ "${count}" -gt 0 ]] || return 1
    start="$(read_ip_check_index "${count}")"
    for ((i = 0; i < count; i++)); do
        idx=$(((start + i) % count))
        url="${url_array[$idx]}"
        url="$(trim "${url}")"
        [[ -n "${url}" ]] || continue
        raw="$(fetch_url_no_proxy "${url}" "${bind_device}" 2>/dev/null || true)"
        ip="$(extract_first_public_ipv4 "${raw}" 2>/dev/null || true)"
        if [[ -n "${ip}" ]]; then
            write_ip_check_index "${count}" "$(((idx + 1) % count))"
            printf '%s\n' "${ip}"
            return 0
        fi
    done
    write_ip_check_index "${count}" "$(((start + 1) % count))"
    return 1
}
