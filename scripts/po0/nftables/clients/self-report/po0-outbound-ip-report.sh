#!/usr/bin/env bash
set -uo pipefail

RAW_URL="https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/self-report/po0-outbound-ip-report.sh"
WORKER_URL="${PO0_LAN_WORKER_URL:-${WORKER_URL:-}}"
SOURCE_ID="${PO0_SELF_REPORT_SOURCE:-${SOURCE_ID:-self-report}}"
IDENTITY="${PO0_SELF_REPORT_IDENTITY:-${IDENTITY:-$(hostname 2>/dev/null || printf 'self-report')}}"
SECRET="${PO0_SELF_REPORT_SECRET:-${SELF_REPORT_SECRET:-}}"
IP_CHECK_URL="${IP_CHECK_URL:-https://ip9.com.cn/get}"
IP_CHECK_URLS="${IP_CHECK_URLS:-}"
INSTALL_CRON=""
CRON_MINUTES="5"

usage() {
    printf '%s\n' \
        "PO0 自上报客户端（Linux/OpenWrt）" \
        "" \
        "本脚本探测当前设备的公网出口 IPv4，并上报到 LAN Worker 的 self-report" \
        "接收服务。访问设备不直接连接 PO0。" \
        "" \
        "用法:" \
        "  bash po0-outbound-ip-report.sh --worker-url https://worker.example.com/report --source-id laptop --secret SECRET" \
        "  curl -fsSL ${RAW_URL} | bash -s -- --worker-url https://worker.example.com/report --source-id laptop --secret SECRET --install-cron 5" \
        "" \
        "参数:" \
        "  --worker-url URL      LAN Worker self-report 接收地址，例如 https://auth.example.com/report。" \
        "  --source-id ID        写入 PO0 client_ip 记录的来源 ID。默认: ${SOURCE_ID}" \
        "  --identity ID         LAN Worker/PO0 日志里的设备或用户标签。默认: ${IDENTITY}" \
        "  --secret SECRET       可选的 LAN Worker self-report 共享密钥。" \
        "  --ip-check-url URL    第一个公网 IPv4 探测地址。默认: ${IP_CHECK_URL}" \
        "  --ip-check-urls CSV   覆盖完整探测地址列表，多个 URL 用逗号分隔。" \
        "  --install-cron [N]    安装 cron，每 N 分钟自上报一次。默认: 5。" \
        "" \
        "默认公网 IPv4 探测顺序:" \
        "  https://ip9.com.cn/get" \
        "  https://mail.163.com/fgw/mailsrv-ipdetail/detail" \
        "  https://api.live.bilibili.com/client/v1/Ip/getInfoNew" \
        "  https://ipservice.ws.126.net/locate/api/getLocByIp" \
        "  https://r.inews.qq.com/api/ip2city?otype=json" \
        "  https://data.video.iqiyi.com/v.f4v" \
        "  https://ip.apps.cntv.cn/whereis?client=json" \
        "  https://exservice.12306.cn/excater/bonree/grip" \
        "  https://myip.ipip.net/json"
}

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "${value}"
}

sh_quote() {
    local value="$1"
    value="${value//\'/\'\\\'\'}"
    printf "'%s'" "${value}"
}

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
            wget -qO- "${url}"
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
    raw="$(cat "${state}" 2>/dev/null | tr -cd '0-9' || true)"
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
        urls="${IP_CHECK_URL},https://mail.163.com/fgw/mailsrv-ipdetail/detail,https://api.live.bilibili.com/client/v1/Ip/getInfoNew,https://ipservice.ws.126.net/locate/api/getLocByIp,https://r.inews.qq.com/api/ip2city?otype=json,https://data.video.iqiyi.com/v.f4v,https://ip.apps.cntv.cn/whereis?client=json,https://exservice.12306.cn/excater/bonree/grip,https://myip.ipip.net/json"
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

script_path() {
    local script="${BASH_SOURCE[0]}"
    case "${script}" in
        /dev/fd/*|/proc/*|/dev/stdin)
            printf '/usr/local/sbin/po0-self-report\n'
            ;;
        /*)
            printf '%s\n' "${script}"
            ;;
        *)
            printf '%s/%s\n' "$(pwd -P)" "${script}"
            ;;
    esac
}

install_self() {
    local dest="/usr/local/sbin/po0-self-report"
    mkdir -p "$(dirname "${dest}")" || return 1
    if [[ -r "${BASH_SOURCE[0]}" && "${BASH_SOURCE[0]}" != /dev/fd/* && "${BASH_SOURCE[0]}" != /proc/* ]]; then
        cp "${BASH_SOURCE[0]}" "${dest}" || return 1
    elif command -v curl >/dev/null 2>&1; then
        curl -fsSL "${RAW_URL}" -o "${dest}" || return 1
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "${dest}" "${RAW_URL}" || return 1
    else
        echo "缺少 curl/wget，无法把管道运行的脚本落盘。" >&2
        return 1
    fi
    chmod 755 "${dest}" || true
    printf '%s\n' "${dest}"
}

install_cron() {
    local script job tmp
    command -v crontab >/dev/null 2>&1 || {
        echo "未找到 crontab 命令。" >&2
        return 1
    }
    script="$(install_self)" || return 1
    job="*/${CRON_MINUTES} * * * * bash $(sh_quote "${script}") --worker-url $(sh_quote "${WORKER_URL}") --source-id $(sh_quote "${SOURCE_ID}") --identity $(sh_quote "${IDENTITY}") --secret $(sh_quote "${SECRET}") --ip-check-url $(sh_quote "${IP_CHECK_URL}") >/tmp/po0-self-report.log 2>&1"
    tmp="/tmp/po0-self-report-cron.$$"
    {
        crontab -l 2>/dev/null | awk '/# PO0_SELF_REPORT_BEGIN/{skip=1; next} /# PO0_SELF_REPORT_END/{skip=0; next} !skip{print}'
        echo "# PO0_SELF_REPORT_BEGIN"
        echo "${job}"
        echo "# PO0_SELF_REPORT_END"
    } > "${tmp}" || return 1
    crontab "${tmp}" || return 1
    rm -f "${tmp}"
    echo "已安装 self-report cron：每 ${CRON_MINUTES} 分钟上报一次。"
}

report_once() {
    local ip
    [[ -n "${WORKER_URL}" ]] || {
        echo "缺少 --worker-url。" >&2
        return 1
    }
    command -v curl >/dev/null 2>&1 || {
        echo "缺少 curl，无法上报到 LAN Worker。" >&2
        return 1
    }
    ip="$(detect_outbound_ipv4)" || {
        echo "未能探测到当前公网出口 IPv4。" >&2
        return 1
    }
    echo "上报当前公网出口 IPv4 ${ip} 到 LAN Worker：${WORKER_URL}"
    curl -fsS --get \
        --data-urlencode "source=${SOURCE_ID}" \
        --data-urlencode "ip=${ip}" \
        --data-urlencode "identity=${IDENTITY}" \
        --data-urlencode "token=${SECRET}" \
        "${WORKER_URL}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --worker-url|--lan-worker-url) WORKER_URL="${2:-}"; shift 2 ;;
        --source-id) SOURCE_ID="${2:-}"; shift 2 ;;
        --identity) IDENTITY="${2:-}"; shift 2 ;;
        --secret|--self-report-secret) SECRET="${2:-}"; shift 2 ;;
        --ip-check-url) IP_CHECK_URL="${2:-}"; shift 2 ;;
        --ip-check-urls) IP_CHECK_URLS="${2:-}"; shift 2 ;;
        --install-cron)
            INSTALL_CRON="1"
            if [[ "${2:-}" =~ ^[0-9]+$ ]]; then CRON_MINUTES="${2:-}"; shift 2; else shift; fi
            ;;
        --po0-host|--po0-script|--source-key|--domain|--token)
            echo "不再支持直接向 PO0 自上报。请使用 --worker-url 上报到 LAN Worker。" >&2
            exit 1
            ;;
        --help|-h) usage; exit 0 ;;
        *) echo "未知参数：$1" >&2; usage >&2; exit 1 ;;
    esac
done

if [[ "${INSTALL_CRON}" == "1" ]]; then
    install_cron
else
    report_once
fi
