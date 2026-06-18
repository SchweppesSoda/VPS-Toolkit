#!/usr/bin/env bash
set -uo pipefail

RAW_URL="https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/self-report/po0-outbound-ip-report.sh"
WORKER_URL="${PO0_LAN_WORKER_URL:-${WORKER_URL:-}}"
SOURCE_ID="${PO0_SELF_REPORT_SOURCE:-${SOURCE_ID:-self-report}}"
IDENTITY="${PO0_SELF_REPORT_IDENTITY:-${IDENTITY:-$(hostname 2>/dev/null || printf 'self-report')}}"
SECRET="${PO0_SELF_REPORT_SECRET:-${SELF_REPORT_SECRET:-}}"
IP_CHECK_URL="${IP_CHECK_URL:-https://ip9.com.cn/get}"
IP_CHECK_URLS="${IP_CHECK_URLS:-}"
INSTALL_PATH="${PO0_SELF_REPORT_INSTALL_PATH:-${INSTALL_PATH:-}}"
INSTALL_CRON=""
SHOW_MENU=""
CRON_MINUTES="${PO0_SELF_REPORT_MINUTES:-${MINUTES:-15}}"
HAD_ARGS=0
[[ "$#" -gt 0 ]] && HAD_ARGS=1

usage() {
    printf '%s\n' \
        "PO0 自上报客户端（Linux/OpenWrt）" \
        "" \
        "本脚本探测当前设备的公网出口 IPv4，并上报到 LAN Worker 的 self-report" \
        "接收服务。访问设备不直接连接 PO0。Self-report 放行 TTL 由 LAN Worker" \
        "接收端配置，不由客户端决定。" \
        "" \
        "用法:" \
        "  bash po0-outbound-ip-report.sh --menu" \
        "  bash po0-outbound-ip-report.sh --worker-url https://worker.example.com/report --source-id laptop --secret SECRET" \
        "  curl -fsSL ${RAW_URL} | bash -s -- --worker-url https://worker.example.com/report --source-id laptop --secret SECRET --install-cron 15" \
        "" \
        "参数:" \
        "  --menu                打开交互菜单。" \
        "  --worker-url URL      LAN Worker self-report 接收地址，例如 https://auth.example.com/report。" \
        "  --source-id ID        写入 PO0 client_ip 记录的来源 ID。默认: ${SOURCE_ID}" \
        "  --identity ID         LAN Worker/PO0 日志里的设备或用户标签。默认: ${IDENTITY}" \
        "  --secret SECRET       可选的 LAN Worker self-report 共享密钥。" \
        "  --ip-check-url URL    第一个公网 IPv4 探测地址。默认: ${IP_CHECK_URL}" \
        "  --ip-check-urls CSV   覆盖完整探测地址列表，多个 URL 用逗号分隔。" \
        "  --install-cron [N]    安装 cron，每 N 分钟自上报一次。默认: ${CRON_MINUTES}。" \
        "  --minutes N           设置 cron 上报间隔，范围 1-59。" \
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

mask_secret() {
    local value="$1"
    local len
    [[ -n "${value}" ]] || { printf '未设置'; return 0; }
    len="${#value}"
    if (( len <= 8 )); then
        printf '***'
    else
        printf '%s***%s' "${value:0:3}" "${value: -3}"
    fi
}

read_prompt() {
    local prompt="$1"
    local value
    if [[ -r /dev/tty && -w /dev/tty ]]; then
        if { printf '%s' "${prompt}" > /dev/tty && IFS= read -r value < /dev/tty; } 2>/dev/null; then
            printf '%s\n' "${value}"
            return 0
        fi
    fi
    printf '%s' "${prompt}" >&2
    IFS= read -r value || return 1
    printf '%s\n' "${value}"
}

prompt_default() {
    local prompt="$1"
    local default="$2"
    local value
    if [[ -n "${default}" ]]; then
        value="$(read_prompt "${prompt} [${default}]: ")" || value=""
        value="$(trim "${value}")"
        [[ -n "${value}" ]] || value="${default}"
    else
        value="$(read_prompt "${prompt}: ")" || value=""
        value="$(trim "${value}")"
    fi
    printf '%s\n' "${value}"
}

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local suffix value
    case "${default,,}" in
        y|yes|1|true) suffix="Y/n"; default="y" ;;
        *) suffix="y/N"; default="n" ;;
    esac
    while true; do
        value="$(read_prompt "${prompt} [${suffix}]: ")" || return 1
        value="$(trim "${value}")"
        [[ -n "${value}" ]] || value="${default}"
        case "${value,,}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) printf '请输入 y 或 n。\n' >&2 ;;
        esac
    done
}

pause_before_return() {
    read_prompt "按回车返回菜单..." >/dev/null || true
}

validate_cron_minutes() {
    [[ "${CRON_MINUTES}" =~ ^[0-9]+$ && "${CRON_MINUTES}" -ge 1 && "${CRON_MINUTES}" -le 59 ]] || {
        printf '上报间隔必须是 1-59 分钟。\n' >&2
        return 1
    }
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

default_install_path() {
    if [[ -n "${INSTALL_PATH}" ]]; then
        printf '%s\n' "${INSTALL_PATH}"
    elif [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]]; then
        printf '%s\n' "/usr/local/sbin/po0-self-report"
    elif [[ -n "${HOME:-}" ]]; then
        printf '%s\n' "${HOME}/.local/bin/po0-self-report"
    else
        printf '%s\n' "./po0-self-report"
    fi
}

install_self() {
    local dest dir
    dest="$(default_install_path)"
    dir="$(dirname "${dest}")"
    mkdir -p "${dir}" || return 1
    if [[ -r "${BASH_SOURCE[0]}" && "${BASH_SOURCE[0]}" != /dev/fd/* && "${BASH_SOURCE[0]}" != /proc/* && "${BASH_SOURCE[0]}" != /dev/stdin ]]; then
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

cron_begin_marker() {
    printf '# PO0_SELF_REPORT_BEGIN\n'
}

cron_end_marker() {
    printf '# PO0_SELF_REPORT_END\n'
}

write_cron_without_managed_block() {
    awk '/# PO0_SELF_REPORT_BEGIN/{skip=1; next} /# PO0_SELF_REPORT_END/{skip=0; next} !skip{print}'
}

install_cron() {
    local script job tmp ip_args
    validate_cron_minutes || return 1
    [[ -n "${WORKER_URL}" ]] || {
        echo "缺少 --worker-url。" >&2
        return 1
    }
    command -v crontab >/dev/null 2>&1 || {
        echo "未找到 crontab 命令。" >&2
        return 1
    }
    script="$(install_self)" || return 1
    if [[ -n "${IP_CHECK_URLS}" ]]; then
        ip_args="--ip-check-urls $(sh_quote "${IP_CHECK_URLS}")"
    else
        ip_args="--ip-check-url $(sh_quote "${IP_CHECK_URL}")"
    fi
    job="*/${CRON_MINUTES} * * * * bash $(sh_quote "${script}") --worker-url $(sh_quote "${WORKER_URL}") --source-id $(sh_quote "${SOURCE_ID}") --identity $(sh_quote "${IDENTITY}") --secret $(sh_quote "${SECRET}") ${ip_args} >/tmp/po0-self-report.log 2>&1"
    tmp="/tmp/po0-self-report-cron.$$"
    {
        crontab -l 2>/dev/null | write_cron_without_managed_block
        echo "$(cron_begin_marker)"
        echo "${job}"
        echo "$(cron_end_marker)"
    } > "${tmp}" || return 1
    crontab "${tmp}" || {
        rm -f "${tmp}" 2>/dev/null || true
        return 1
    }
    rm -f "${tmp}" 2>/dev/null || true
    echo "已安装 self-report cron：每 ${CRON_MINUTES} 分钟上报一次。"
    echo "脚本路径：${script}"
}

remove_cron() {
    local tmp
    command -v crontab >/dev/null 2>&1 || {
        echo "未找到 crontab 命令。" >&2
        return 1
    }
    tmp="/tmp/po0-self-report-cron.$$"
    crontab -l 2>/dev/null | write_cron_without_managed_block > "${tmp}" || true
    crontab "${tmp}" || {
        rm -f "${tmp}" 2>/dev/null || true
        return 1
    }
    rm -f "${tmp}" 2>/dev/null || true
    echo "已删除本脚本管理的 self-report cron。"
}

show_cron_status() {
    local line in_block=0 found=0
    command -v crontab >/dev/null 2>&1 || {
        echo "当前系统没有 crontab 命令。"
        return 0
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        case "${line}" in
            "# PO0_SELF_REPORT_BEGIN") in_block=1; found=1; continue ;;
            "# PO0_SELF_REPORT_END") in_block=0; continue ;;
        esac
        [[ "${in_block}" == "1" ]] && printf '%s\n' "${line}"
    done < <(crontab -l 2>/dev/null || true)
    [[ "${found}" == "1" ]] || echo "未安装本脚本管理的 self-report cron。"
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

show_current_config() {
    printf '%s\n' "------------------------"
    printf '%s\n' "Self-report 客户端配置"
    printf '  LAN Worker URL : %s\n' "${WORKER_URL:-未设置}"
    printf '  Source ID      : %s\n' "${SOURCE_ID:-未设置}"
    printf '  Identity       : %s\n' "${IDENTITY:-未设置}"
    printf '  Secret         : %s\n' "$(mask_secret "${SECRET}")"
    printf '  上报间隔       : 每 %s 分钟（安装 cron 时使用）\n' "${CRON_MINUTES}"
    printf '  放行 TTL       : 由 LAN Worker Self-report 目标控制，默认 3600 秒\n'
    if [[ -n "${IP_CHECK_URLS}" ]]; then
        printf '  IP 探测列表    : %s\n' "${IP_CHECK_URLS}"
    else
        printf '  首选 IP 探测   : %s\n' "${IP_CHECK_URL}"
    fi
}

configure_interactive() {
    local secret_input
    WORKER_URL="$(prompt_default "LAN Worker self-report 接收地址" "${WORKER_URL}")"
    SOURCE_ID="$(prompt_default "Source ID" "${SOURCE_ID:-self-report}")"
    IDENTITY="$(prompt_default "Identity" "${IDENTITY}")"
    if [[ -n "${SECRET}" ]]; then
        secret_input="$(read_prompt "Self-report secret [已设置，回车保留，输入 - 清空]: ")" || secret_input=""
        secret_input="$(trim "${secret_input}")"
        case "${secret_input}" in
            "") ;;
            "-") SECRET="" ;;
            *) SECRET="${secret_input}" ;;
        esac
    else
        SECRET="$(prompt_default "Self-report secret，可空" "")"
    fi
    CRON_MINUTES="$(prompt_default "客户端每几分钟上报一次（1-59）" "${CRON_MINUTES}")"
    validate_cron_minutes || return 1
    IP_CHECK_URL="$(prompt_default "首选公网 IPv4 探测 URL" "${IP_CHECK_URL}")"
    if prompt_yes_no "是否覆盖完整 IP 探测 URL 列表" "n"; then
        IP_CHECK_URLS="$(prompt_default "完整探测 URL 列表，逗号分隔" "${IP_CHECK_URLS}")"
    fi
}

run_once_interactive() {
    if [[ -z "${WORKER_URL}" ]]; then
        configure_interactive || return 1
    fi
    report_once
}

install_cron_interactive() {
    configure_interactive || return 1
    install_cron
}

menu_loop() {
    local choice
    while true; do
        show_current_config
        printf '%s\n' "------------------------"
        printf '%s\n' "请选择操作"
        printf '  %s\n' "1. 配置上报目标 / 间隔"
        printf '  %s\n' "2. 立即上报一次"
        printf '  %s\n' "3. 安装 / 更新定时上报"
        printf '  %s\n' "4. 查看定时上报状态"
        printf '  %s\n' "5. 删除定时上报"
        printf '  %s\n' "6. 显示当前配置"
        printf '  %s\n' "0. 退出"
        printf '%s\n' "------------------------"
        choice="$(read_prompt "请选择操作 [0-6]: ")" || return 0
        choice="$(trim "${choice}")"
        case "${choice}" in
            1) configure_interactive; pause_before_return ;;
            2) run_once_interactive; pause_before_return ;;
            3) install_cron_interactive; pause_before_return ;;
            4) show_cron_status; pause_before_return ;;
            5)
                if prompt_yes_no "确认删除 self-report 定时上报" "n"; then
                    remove_cron
                else
                    echo "已取消。"
                fi
                pause_before_return
                ;;
            6) show_current_config; pause_before_return ;;
            0) return 0 ;;
            "") ;;
            *) printf '无效选择。\n' >&2; pause_before_return ;;
        esac
    done
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --menu)
            SHOW_MENU="1"
            shift
            ;;
        --worker-url|--lan-worker-url)
            WORKER_URL="${2:-}"
            shift 2
            ;;
        --source-id)
            SOURCE_ID="${2:-}"
            shift 2
            ;;
        --identity)
            IDENTITY="${2:-}"
            shift 2
            ;;
        --secret|--self-report-secret)
            SECRET="${2:-}"
            shift 2
            ;;
        --ip-check-url)
            IP_CHECK_URL="${2:-}"
            shift 2
            ;;
        --ip-check-urls)
            IP_CHECK_URLS="${2:-}"
            shift 2
            ;;
        --install-path)
            INSTALL_PATH="${2:-}"
            shift 2
            ;;
        --minutes|--cron-minutes)
            CRON_MINUTES="${2:-}"
            shift 2
            ;;
        --install-cron)
            INSTALL_CRON="1"
            if [[ "${2:-}" =~ ^[0-9]+$ ]]; then
                CRON_MINUTES="${2:-}"
                shift 2
            else
                shift
            fi
            ;;
        --po0-host|--po0-script|--source-key|--domain|--token)
            echo "不再支持直接向 PO0 自上报。请使用 --worker-url 上报到 LAN Worker。" >&2
            exit 1
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "未知参数：$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ "${SHOW_MENU}" == "1" || ( "${HAD_ARGS}" == "0" && -r /dev/tty && -w /dev/tty && -z "${WORKER_URL}" ) ]]; then
    menu_loop
elif [[ "${INSTALL_CRON}" == "1" ]]; then
    install_cron
else
    report_once
fi
