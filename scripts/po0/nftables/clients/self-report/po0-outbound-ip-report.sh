#!/usr/bin/env bash
set -uo pipefail

RAW_URL="https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/self-report/po0-outbound-ip-report.sh"
ENV_WORKER_URL="${WORKER_URL-}"
ENV_SOURCE_ID="${SOURCE_ID-}"
ENV_IDENTITY="${IDENTITY-}"
ENV_ALLOW_HTTP="${ALLOW_HTTP-}"
ENV_IP_CHECK_URL="${IP_CHECK_URL-}"
ENV_IP_CHECK_URLS="${IP_CHECK_URLS-}"
ENV_INSTALL_PATH="${INSTALL_PATH-}"
ENV_MINUTES="${MINUTES-}"
CONFIG_FILE="${PO0_SELF_REPORT_CONFIG:-${SELF_REPORT_CONFIG:-}}"
WORKER_URL=""
SOURCE_ID="self-report"
IDENTITY="$(hostname 2>/dev/null || printf 'self-report')"
SECRET=""
ALLOW_HTTP=""
IP_CHECK_URL="https://ip9.com.cn/get"
IP_CHECK_URLS=""
INSTALL_PATH=""
INSTALL_CRON=""
SHOW_MENU=""
SAVE_CONFIG=""
PAUSE_SCHEDULE=""
RESUME_SCHEDULE=""
SHOW_SCHEDULE_STATUS=""
SCHEDULE_PAUSED="0"
CRON_MINUTES="60"
MAX_CRON_MINUTES="10080"
HAD_ARGS=0
[[ "$#" -gt 0 ]] && HAD_ARGS=1

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

path_dirname() {
    local path="$1"
    case "${path}" in
        */*) printf '%s\n' "${path%/*}" ;;
        *) printf '.\n' ;;
    esac
}

default_config_file() {
    if [[ -n "${CONFIG_FILE}" ]]; then
        printf '%s\n' "${CONFIG_FILE}"
    elif [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]]; then
        printf '%s\n' "/etc/po0-self-report/settings.env"
    elif [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
        printf '%s\n' "${XDG_CONFIG_HOME}/po0-self-report/settings.env"
    elif [[ -n "${HOME:-}" ]]; then
        printf '%s\n' "${HOME}/.config/po0-self-report/settings.env"
    else
        printf '%s\n' "./po0-self-report.env"
    fi
}

prime_config_path_from_args() {
    local arg next
    while [[ $# -gt 0 ]]; do
        arg="$1"
        case "${arg}" in
            --config)
                next="${2:-}"
                [[ -n "${next}" ]] && CONFIG_FILE="${next}"
                shift 2 2>/dev/null || shift
                ;;
            --config=*)
                CONFIG_FILE="${arg#--config=}"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
}

setup_colors() {
    C_RESET=""
    C_BOLD=""
    C_DIM=""
    C_GREEN=""
    C_YELLOW=""
    C_RED=""
    C_CYAN=""
    C_PANEL=""
    if [[ -t 1 && -n "${TERM:-}" && "${TERM}" != "dumb" ]]; then
        C_RESET=$'\033[0m'
        C_BOLD=$'\033[1m'
        C_DIM=$'\033[2m'
        C_GREEN=$'\033[32m'
        C_YELLOW=$'\033[33m'
        C_RED=$'\033[31m'
        C_CYAN=$'\033[96m'
        C_PANEL=$'\033[38;5;208m'
    fi
}

setup_colors

print_menu_divider() {
    printf '%b%s%b\n' "${C_CYAN}" "------------------------" "${C_RESET}"
}

print_menu_footer() {
    print_menu_divider
}

print_menu_section() {
    print_menu_divider
    printf '%b%s%b\n' "${C_BOLD}${C_CYAN}" "$1" "${C_RESET}"
}

print_menu_item() {
    local number="$1"
    local label="$2"
    printf '  %b%2s%b) %s\n' "${C_CYAN}" "${number}" "${C_RESET}" "${label}"
}

print_menu_pair() {
    local left_number="$1"
    local left_label="$2"
    local right_number="${3:-}"
    local right_label="${4:-}"
    local right_column=46
    printf '  %b%2s%b) %s' "${C_CYAN}" "${left_number}" "${C_RESET}" "${left_label}"
    if [[ -n "${right_number}" ]]; then
        if [[ -t 1 ]]; then
            printf '\033[%sG' "${right_column}"
        else
            printf '    '
        fi
        printf '%b%2s%b) %s' "${C_CYAN}" "${right_number}" "${C_RESET}" "${right_label}"
    fi
    printf '\n'
}

print_panel_divider() {
    printf '%b%s%b\n' "${C_PANEL}" "------------------------" "${C_RESET}"
}

print_panel_section() {
    print_panel_divider
    printf '%b%s%b\n' "${C_BOLD}${C_PANEL}" "$1" "${C_RESET}"
}

print_panel_value_column() {
    if [[ -t 1 ]]; then
        printf '\033[24G'
    else
        printf '    '
    fi
}

print_panel_row() {
    local label="$1"
    shift
    printf '  %b%s%b' "${C_PANEL}" "${label}" "${C_RESET}"
    print_panel_value_column
    printf ': %s\n' "$*"
}

print_panel_note() {
    printf '  '
    print_panel_value_column
    printf '  %s\n' "$*"
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

self_report_completed() {
    printf '%bSelf-report 已完成：%s%b\n' "${C_GREEN}" "$1" "${C_RESET}"
}

self_report_incomplete() {
    printf '%bSelf-report 未完成：%s%b\n' "${C_RED}" "$1" "${C_RESET}" >&2
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

write_env_assignment() {
    local name="$1"
    local value="$2"
    printf '%s=%s\n' "${name}" "$(sh_quote "${value}")"
}

load_saved_config() {
    [[ -r "${CONFIG_FILE}" ]] || return 0
    # This file is created by this script with chmod 600 and may contain secrets.
    # shellcheck disable=SC1090
    . "${CONFIG_FILE}" || return 1
}

apply_env_overrides() {
    [[ -n "${PO0_LAN_WORKER_URL+x}" ]] && WORKER_URL="${PO0_LAN_WORKER_URL}"
    [[ -n "${ENV_WORKER_URL}" ]] && WORKER_URL="${ENV_WORKER_URL}"
    [[ -n "${PO0_SELF_REPORT_SOURCE+x}" ]] && SOURCE_ID="${PO0_SELF_REPORT_SOURCE}"
    [[ -n "${ENV_SOURCE_ID}" ]] && SOURCE_ID="${ENV_SOURCE_ID}"
    [[ -n "${PO0_SELF_REPORT_IDENTITY+x}" ]] && IDENTITY="${PO0_SELF_REPORT_IDENTITY}"
    [[ -n "${ENV_IDENTITY}" ]] && IDENTITY="${ENV_IDENTITY}"
    [[ -n "${PO0_SELF_REPORT_SECRET+x}" ]] && SECRET="${PO0_SELF_REPORT_SECRET}"
    [[ -n "${SELF_REPORT_SECRET+x}" ]] && SECRET="${SELF_REPORT_SECRET}"
    [[ -n "${PO0_SELF_REPORT_ALLOW_HTTP+x}" ]] && ALLOW_HTTP="${PO0_SELF_REPORT_ALLOW_HTTP}"
    [[ -n "${ENV_ALLOW_HTTP}" ]] && ALLOW_HTTP="${ENV_ALLOW_HTTP}"
    [[ -n "${ENV_IP_CHECK_URL}" ]] && IP_CHECK_URL="${ENV_IP_CHECK_URL}"
    [[ -n "${ENV_IP_CHECK_URLS}" ]] && IP_CHECK_URLS="${ENV_IP_CHECK_URLS}"
    [[ -n "${PO0_SELF_REPORT_INSTALL_PATH+x}" ]] && INSTALL_PATH="${PO0_SELF_REPORT_INSTALL_PATH}"
    [[ -n "${ENV_INSTALL_PATH}" ]] && INSTALL_PATH="${ENV_INSTALL_PATH}"
    [[ -n "${PO0_SELF_REPORT_MINUTES+x}" ]] && CRON_MINUTES="${PO0_SELF_REPORT_MINUTES}"
    [[ -n "${ENV_MINUTES}" ]] && CRON_MINUTES="${ENV_MINUTES}"
    [[ -n "${PO0_SELF_REPORT_MAX_MINUTES+x}" ]] && MAX_CRON_MINUTES="${PO0_SELF_REPORT_MAX_MINUTES}"
    [[ -n "${PO0_SELF_REPORT_PAUSED+x}" ]] && SCHEDULE_PAUSED="${PO0_SELF_REPORT_PAUSED}"
}

save_config_file() {
    local dir tmp old_umask
    validate_cron_minutes || return 1
    dir="$(path_dirname "${CONFIG_FILE}")"
    mkdir -p "${dir}" || return 1
    tmp="${CONFIG_FILE}.tmp.$$"
    old_umask="$(umask)"
    umask 077
    {
        printf '# PO0 self-report client settings. This file may contain secrets.\n'
        write_env_assignment "WORKER_URL" "${WORKER_URL}"
        write_env_assignment "SOURCE_ID" "${SOURCE_ID}"
        write_env_assignment "IDENTITY" "${IDENTITY}"
        write_env_assignment "SECRET" "${SECRET}"
        write_env_assignment "ALLOW_HTTP" "${ALLOW_HTTP}"
        write_env_assignment "IP_CHECK_URL" "${IP_CHECK_URL}"
        write_env_assignment "IP_CHECK_URLS" "${IP_CHECK_URLS}"
        write_env_assignment "INSTALL_PATH" "${INSTALL_PATH}"
        write_env_assignment "CRON_MINUTES" "${CRON_MINUTES}"
        write_env_assignment "MAX_CRON_MINUTES" "${MAX_CRON_MINUTES}"
        write_env_assignment "SCHEDULE_PAUSED" "${SCHEDULE_PAUSED}"
    } > "${tmp}" || {
        umask "${old_umask}"
        rm -f "${tmp}" 2>/dev/null || true
        return 1
    }
    umask "${old_umask}"
    mv -f "${tmp}" "${CONFIG_FILE}" || return 1
    chmod 600 "${CONFIG_FILE}" 2>/dev/null || true
    self_report_completed "配置已保存：${CONFIG_FILE}"
}

normalize_worker_url() {
    local value="$1" rest
    value="$(trim "${value}")"
    [[ -n "${value}" ]] || { printf '\n'; return 0; }
    case "${value}" in
        http://*|https://*) ;;
        *) value="https://${value}" ;;
    esac
    rest="${value#*://}"
    if [[ "${rest}" != */* ]]; then
        value="${value}/report"
    elif [[ "${value}" == */ ]]; then
        value="${value%/}/report"
    fi
    printf '%s\n' "${value}"
}

http_allowed() {
    case "${ALLOW_HTTP,,}" in
        1|true|yes|y) return 0 ;;
        *) return 1 ;;
    esac
}

schedule_paused() {
    case "${SCHEDULE_PAUSED,,}" in
        1|true|yes|y) return 0 ;;
        *) return 1 ;;
    esac
}

validate_worker_url() {
    WORKER_URL="$(normalize_worker_url "${WORKER_URL}")"
    [[ -n "${WORKER_URL}" ]] || {
        printf '缺少 --worker-url；请先配置并保存上报参数。\n' >&2
        return 1
    }
    case "${WORKER_URL}" in
        https://*) return 0 ;;
        http://*)
            if http_allowed; then
                return 0
            fi
            printf 'Self-report 默认只允许 HTTPS。若仅用于本地调试或旧环境，请显式加 --allow-http。\n' >&2
            return 1
            ;;
        *)
            printf 'LAN Worker self-report 地址无效：%s\n' "${WORKER_URL}" >&2
            return 1
            ;;
    esac
}

config_complete() {
    [[ -n "${WORKER_URL}" ]] || return 1
    validate_worker_url >/dev/null 2>&1 || return 1
    validate_cron_minutes >/dev/null 2>&1 || return 1
}

pause_before_return() {
    read_prompt "按回车返回菜单..." >/dev/null || true
}

menu_clear_screen() {
    [[ "${MENU_CLEAR:-1}" == "0" ]] && return 0
    [[ -t 1 && -n "${TERM:-}" && "${TERM}" != "dumb" ]] || return 0
    command -v clear >/dev/null 2>&1 && clear || printf '\033[H\033[2J'
}

validate_cron_minutes() {
    [[ "${MAX_CRON_MINUTES}" =~ ^[0-9]+$ && "${MAX_CRON_MINUTES}" -ge 1 ]] || MAX_CRON_MINUTES="10080"
    [[ "${CRON_MINUTES}" =~ ^[0-9]+$ && "${CRON_MINUTES}" -ge 1 && "${CRON_MINUTES}" -le "${MAX_CRON_MINUTES}" ]] || {
        printf '上报间隔必须是 1-%s 分钟。\n' "${MAX_CRON_MINUTES}" >&2
        return 1
    }
    MAX_CRON_MINUTES="$((10#${MAX_CRON_MINUTES}))"
    CRON_MINUTES="$((10#${CRON_MINUTES}))"
}

cron_interval_label() {
    local minutes="$1"
    if (( minutes == 1440 )); then
        printf '每天'
    elif (( minutes > 1440 && minutes % 1440 == 0 )); then
        printf '每 %s 天' "$((minutes / 1440))"
    elif (( minutes == 60 )); then
        printf '每小时'
    elif (( minutes > 60 && minutes % 60 == 0 )); then
        printf '每 %s 小时' "$((minutes / 60))"
    else
        printf '每 %s 分钟' "${minutes}"
    fi
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
    printf '# PO0_SELF_REPORT_BEGIN %s\n' "${CONFIG_FILE}"
}

cron_end_marker() {
    printf '# PO0_SELF_REPORT_END %s\n' "${CONFIG_FILE}"
}

write_cron_without_managed_block() {
    awk '/# PO0_SELF_REPORT_BEGIN/{skip=1; next} /# PO0_SELF_REPORT_END/{skip=0; next} !skip{print}'
}

cron_managed_block_exists() {
    crontab -l 2>/dev/null | grep -q '^# PO0_SELF_REPORT_BEGIN'
}

build_cron_job() {
    local minutes="$1"
    local run_cmd="$2"
    local schedule hours
    if (( minutes < 60 )); then
        schedule="*/${minutes} * * * *"
        printf '%s %s\n' "${schedule}" "${run_cmd}"
    elif (( minutes == 60 )); then
        printf '0 * * * * %s\n' "${run_cmd}"
    elif (( minutes < 1440 && minutes % 60 == 0 )); then
        hours=$((minutes / 60))
        printf '0 */%s * * * %s\n' "${hours}" "${run_cmd}"
    elif (( minutes == 1440 )); then
        printf '0 0 * * * %s\n' "${run_cmd}"
    elif (( minutes % 60 == 0 )); then
        hours=$((minutes / 60))
        printf '0 * * * * now=$(date +\\%%s); if [ $((now / 3600 \\%% %s)) -eq 0 ]; then %s; fi\n' "${hours}" "${run_cmd}"
    else
        printf '* * * * now=$(date +\\%%s); if [ $((now / 60 \\%% %s)) -eq 0 ]; then %s; fi\n' "${minutes}" "${run_cmd}"
    fi
}

install_cron() {
    local script job tmp run_cmd
    validate_cron_minutes || { self_report_incomplete "上报间隔配置无效，未安装 cron。"; return 1; }
    validate_worker_url || { self_report_incomplete "LAN Worker URL 未通过检查，未安装 cron。"; return 1; }
    save_config_file || { self_report_incomplete "配置保存失败，未安装 cron。"; return 1; }
    command -v crontab >/dev/null 2>&1 || {
        echo "未找到 crontab 命令。" >&2
        self_report_incomplete "缺少 crontab，未安装 cron。"
        return 1
    }
    script="$(install_self)" || { self_report_incomplete "脚本落盘失败，未安装 cron。"; return 1; }
    run_cmd="bash $(sh_quote "${script}") --config $(sh_quote "${CONFIG_FILE}") >/tmp/po0-self-report.log 2>&1"
    job="$(build_cron_job "${CRON_MINUTES}" "${run_cmd}")"
    if schedule_paused; then
        job="# ${job}"
    fi
    tmp="/tmp/po0-self-report-cron.$$"
    {
        crontab -l 2>/dev/null | write_cron_without_managed_block
        cron_begin_marker
        printf '# paused=%s\n' "$(schedule_paused && printf '1' || printf '0')"
        echo "${job}"
        cron_end_marker
    } > "${tmp}" || { self_report_incomplete "写入临时 cron 配置失败。"; return 1; }
    crontab "${tmp}" || {
        rm -f "${tmp}" 2>/dev/null || true
        self_report_incomplete "crontab 写入失败，未安装 cron。"
        return 1
    }
    rm -f "${tmp}" 2>/dev/null || true
    echo "已安装 self-report cron：$(cron_interval_label "${CRON_MINUTES}")上报一次。"
    echo "脚本路径：${script}"
    echo "配置文件：${CONFIG_FILE}"
    if schedule_paused; then
        self_report_completed "定时上报已安装 / 更新，但当前保持暂停。"
    else
        self_report_completed "定时上报已安装 / 更新，$(cron_interval_label "${CRON_MINUTES}")执行一次。"
    fi
}

remove_cron() {
    local tmp
    command -v crontab >/dev/null 2>&1 || {
        echo "未找到 crontab 命令。" >&2
        self_report_incomplete "缺少 crontab，未删除 cron。"
        return 1
    }
    tmp="/tmp/po0-self-report-cron.$$"
    crontab -l 2>/dev/null | write_cron_without_managed_block > "${tmp}" || true
    crontab "${tmp}" || {
        rm -f "${tmp}" 2>/dev/null || true
        self_report_incomplete "crontab 写入失败，未删除 cron。"
        return 1
    }
    rm -f "${tmp}" 2>/dev/null || true
    echo "已删除本脚本管理的 self-report cron。"
    self_report_completed "已删除本脚本管理的定时上报。"
}

show_cron_status() {
    local line in_block=0 found=0
    print_panel_section "Self-report 定时上报"
    print_panel_row "配置文件" "${CONFIG_FILE}"
    print_panel_row "保存状态" "$([[ -f "${CONFIG_FILE}" ]] && printf '已保存' || printf '未保存')"
    print_panel_row "暂停状态" "$(schedule_paused && printf '已暂停（手动立即上报仍可用）' || printf '未暂停')"
    if ! command -v crontab >/dev/null 2>&1; then
        print_panel_row "cron" "当前系统没有 crontab 命令"
        return 0
    fi
    while IFS= read -r line || [[ -n "${line}" ]]; do
        case "${line}" in
            "# PO0_SELF_REPORT_BEGIN"*) in_block=1; found=1; continue ;;
            "# PO0_SELF_REPORT_END"*) in_block=0; continue ;;
        esac
        [[ "${in_block}" == "1" ]] && print_panel_row "当前计划" "${line}"
    done < <(crontab -l 2>/dev/null || true)
    [[ "${found}" == "1" ]] || print_panel_row "当前计划" "未安装本脚本管理的 self-report cron"
}

set_schedule_paused() {
    local value="$1"
    SCHEDULE_PAUSED="${value}"
    save_config_file || return 1
    if command -v crontab >/dev/null 2>&1 && cron_managed_block_exists; then
        install_cron || return 1
    fi
    if schedule_paused; then
        self_report_completed "定时上报已暂停；手动立即上报仍可用。"
    else
        self_report_completed "定时上报已恢复。"
    fi
}

toggle_schedule_interactive() {
    if schedule_paused; then
        set_schedule_paused "0"
    else
        set_schedule_paused "1"
    fi
}

report_once() {
    local ip response curl_rc secret_header=()
    validate_worker_url || { self_report_incomplete "LAN Worker URL 未通过检查。"; return 1; }
    command -v curl >/dev/null 2>&1 || {
        echo "缺少 curl，无法上报到 LAN Worker。" >&2
        self_report_incomplete "缺少 curl，无法发起上报。"
        return 1
    }
    ip="$(detect_outbound_ipv4)" || {
        echo "未能探测到当前公网出口 IPv4。" >&2
        self_report_incomplete "未能探测到当前公网出口 IPv4。"
        return 1
    }
    [[ -n "${SECRET}" ]] && secret_header=(-H "X-PO0-Token: ${SECRET}")
    echo "上报当前公网出口 IPv4 ${ip} 到 LAN Worker：${WORKER_URL}"
    if response="$(curl -fsS --get "${secret_header[@]}" \
        --data-urlencode "source=${SOURCE_ID}" \
        --data-urlencode "ip=${ip}" \
        --data-urlencode "identity=${IDENTITY}" \
        "${WORKER_URL}")"; then
        [[ -n "${response}" ]] && printf '%s\n' "${response}"
        self_report_completed "公网出口 IPv4 ${ip} 已被 LAN Worker 接收。"
    else
        curl_rc=$?
        self_report_incomplete "LAN Worker 未确认本次上报（curl exit ${curl_rc}）。"
        return "${curl_rc}"
    fi
}

show_current_config() {
    print_panel_section "Self-report 客户端配置"
    print_panel_row "配置文件" "${CONFIG_FILE}"
    print_panel_row "保存状态" "$([[ -f "${CONFIG_FILE}" ]] && printf '已保存' || printf '未保存')"
    print_panel_row "LAN Worker URL" "${WORKER_URL:-未设置}"
    print_panel_row "Source ID" "${SOURCE_ID:-未设置}"
    print_panel_row "Identity" "${IDENTITY:-未设置}"
    print_panel_row "Secret" "$(mask_secret "${SECRET}")"
    print_panel_row "HTTP 上报" "$(if http_allowed; then printf '已显式允许'; else printf '默认拒绝'; fi)"
    print_panel_row "上报间隔" "$(cron_interval_label "${CRON_MINUTES}")（安装 cron 时使用）"
    print_panel_row "定时暂停" "$(schedule_paused && printf '已暂停' || printf '未暂停')"
    print_panel_row "放行 TTL" "由 LAN Worker Self-report 目标控制，默认 3600 秒"
    if [[ -n "${IP_CHECK_URLS}" ]]; then
        print_panel_row "IP 探测列表" "${IP_CHECK_URLS}"
    else
        print_panel_row "首选 IP 探测" "${IP_CHECK_URL}"
    fi
}

configure_interactive() {
    local secret_input
    WORKER_URL="$(prompt_default "LAN Worker self-report HTTPS 接收地址（域名或 https://域名/report）" "${WORKER_URL:-https://report.example.com/report}")"
    WORKER_URL="$(normalize_worker_url "${WORKER_URL}")"
    if [[ "${WORKER_URL}" == http://* ]] && ! http_allowed; then
        if prompt_yes_no "检测到 http:// 地址。仅本地调试/旧环境才允许，是否继续允许 HTTP" "n"; then
            ALLOW_HTTP="1"
        else
            printf '已拒绝 HTTP。请改用 https://域名/report。\n' >&2
            return 1
        fi
    fi
    validate_worker_url || return 1
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
    CRON_MINUTES="$(prompt_default "客户端每几分钟上报一次（1-${MAX_CRON_MINUTES}）" "${CRON_MINUTES}")"
    validate_cron_minutes || return 1
    IP_CHECK_URL="$(prompt_default "首选公网 IPv4 探测 URL" "${IP_CHECK_URL}")"
    if prompt_yes_no "是否覆盖完整 IP 探测 URL 列表" "n"; then
        IP_CHECK_URLS="$(prompt_default "完整探测 URL 列表，逗号分隔" "${IP_CHECK_URLS}")"
    fi
    save_config_file
}

run_once_interactive() {
    if ! config_complete; then
        configure_interactive || return 1
    fi
    report_once
}

install_cron_interactive() {
    if ! config_complete; then
        configure_interactive || return 1
    fi
    install_cron
}

menu_loop() {
    local choice
    while true; do
        menu_clear_screen
        show_current_config
        print_menu_section "手动上报"
        print_menu_pair 1 "配置并保存上报参数" 2 "立即上报一次"
        print_menu_section "定时上报"
        print_menu_pair 3 "安装 / 更新定时上报" 4 "暂停 / 恢复定时上报"
        print_menu_pair 5 "查看定时上报状态" 6 "删除定时上报"
        print_menu_section "查看"
        print_menu_item 7 "显示当前配置"
        print_menu_section "退出"
        print_menu_item 0 "退出"
        print_menu_footer
        choice="$(read_prompt "请选择操作 [0-7]: ")" || return 0
        choice="$(trim "${choice}")"
        case "${choice}" in
            1) configure_interactive; pause_before_return ;;
            2) run_once_interactive; pause_before_return ;;
            3) install_cron_interactive; pause_before_return ;;
            4) toggle_schedule_interactive; pause_before_return ;;
            5) show_cron_status; pause_before_return ;;
            6)
                if prompt_yes_no "确认删除 self-report 定时上报" "n"; then
                    remove_cron
                else
                    echo "已取消。"
                fi
                pause_before_return
                ;;
            7) show_current_config; pause_before_return ;;
            0) return 0 ;;
            "") ;;
            *) printf '无效选择。\n' >&2; pause_before_return ;;
        esac
    done
}

usage() {
    printf '%s\n' \
        "PO0 自上报客户端（Linux/OpenWrt）" \
        "" \
        "本脚本探测当前设备的公网出口 IPv4，并上报到 LAN Worker 的 self-report" \
        "接收服务。访问设备不直接连接 PO0。Self-report 放行 TTL 由 LAN Worker" \
        "接收端配置，不由客户端决定。" \
        "" \
        "用法:" \
        "  curl -fsSL ${RAW_URL} | bash" \
        "  bash po0-outbound-ip-report.sh --menu" \
        "  bash po0-outbound-ip-report.sh --worker-url https://report.example.com/report --source-id laptop --secret SECRET --save-config" \
        "  curl -fsSL ${RAW_URL} | bash -s -- --worker-url https://report.example.com/report --source-id laptop --secret SECRET --install-cron 60" \
        "" \
        "参数:" \
        "  --menu                打开交互菜单。" \
        "  --config PATH         self-report 本地配置文件；默认 root 用 /etc/po0-self-report/settings.env，普通用户用 ~/.config/po0-self-report/settings.env。" \
        "  --save-config         保存当前参数到本地配置文件，不安装 cron。" \
        "  --worker-url URL      LAN Worker self-report HTTPS 接收地址，例如 https://report.example.com/report；裸域名会自动补全。" \
        "  --allow-http          允许 http:// 上报；仅用于本地调试或临时旧环境。" \
        "  --source-id ID        写入 PO0 client_ip 记录的来源 ID。默认: ${SOURCE_ID}" \
        "  --identity ID         LAN Worker/PO0 日志里的设备或用户标签。默认: ${IDENTITY}" \
        "  --secret SECRET       可选的 LAN Worker self-report 共享密钥。" \
        "  --ip-check-url URL    第一个公网 IPv4 探测地址。默认: ${IP_CHECK_URL}" \
        "  --ip-check-urls CSV   覆盖完整探测地址列表，多个 URL 用逗号分隔。" \
        "  --install-cron [N]    安装 / 更新 cron，每 N 分钟自上报一次。默认: ${CRON_MINUTES}。" \
        "  --pause-schedule      暂停本脚本管理的定时上报；手动立即上报仍可用。" \
        "  --resume-schedule     恢复本脚本管理的定时上报。" \
        "  --schedule-status     查看本脚本管理的定时上报状态。" \
        "  --minutes N           设置 cron 上报间隔，范围 1-${MAX_CRON_MINUTES}。" \
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

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --menu)
                SHOW_MENU="1"
                shift
                ;;
            --config)
                CONFIG_FILE="${2:-}"
                shift 2
                ;;
            --config=*)
                CONFIG_FILE="${1#--config=}"
                shift
                ;;
            --save-config)
                SAVE_CONFIG="1"
                shift
                ;;
            --worker-url|--lan-worker-url)
                WORKER_URL="${2:-}"
                shift 2
                ;;
            --allow-http)
                ALLOW_HTTP="1"
                shift
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
            --pause-schedule)
                PAUSE_SCHEDULE="1"
                shift
                ;;
            --resume-schedule)
                RESUME_SCHEDULE="1"
                shift
                ;;
            --schedule-status)
                SHOW_SCHEDULE_STATUS="1"
                shift
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
}

prime_config_path_from_args "$@"
CONFIG_FILE="$(default_config_file)"
load_saved_config
apply_env_overrides
parse_args "$@"
CONFIG_FILE="$(default_config_file)"

if [[ "${SAVE_CONFIG}" == "1" ]]; then
    save_config_file
elif [[ "${PAUSE_SCHEDULE}" == "1" ]]; then
    set_schedule_paused "1"
elif [[ "${RESUME_SCHEDULE}" == "1" ]]; then
    set_schedule_paused "0"
elif [[ "${SHOW_SCHEDULE_STATUS}" == "1" ]]; then
    show_cron_status
elif [[ "${SHOW_MENU}" == "1" || ( "${HAD_ARGS}" == "0" && -r /dev/tty && -w /dev/tty ) ]]; then
    menu_loop
elif [[ "${INSTALL_CRON}" == "1" ]]; then
    install_cron
else
    report_once
fi
