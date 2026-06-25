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

fetch_url_no_proxy() {
    local url="$1"
    if command -v curl >/dev/null 2>&1; then
        env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
            curl -fsSL --noproxy '*' --connect-timeout 10 --max-time 20 "${url}"
        return $?
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
    local urls raw url ip start i idx count
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
        raw="$(fetch_url_no_proxy "${url}" 2>/dev/null || true)"
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
