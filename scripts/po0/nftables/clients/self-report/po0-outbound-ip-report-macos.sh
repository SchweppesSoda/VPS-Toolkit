#!/usr/bin/env bash
set -uo pipefail

PO0_RELEASE_DOWNLOAD_BASE_URL="${PO0_RELEASE_DOWNLOAD_BASE_URL:-https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download}"
DOWNLOAD_URL="${PO0_SELF_REPORT_MACOS_DOWNLOAD_URL:-${PO0_RELEASE_DOWNLOAD_BASE_URL}/po0-outbound-ip-report-macos.sh}"
SCRIPT_NAME="po0-self-report-macos"
SCRIPT_VERSION="2026.06.25+build.2"
SCRIPT_RELEASE_DATE="2026-06-25"
# CHANGELOG_BEGIN
# - 定时上报状态页的最近结果改为短缩进摘要，并保留原始日志路径。
# CHANGELOG_END
MENU_RIGHT_COLUMN=46
PANEL_VALUE_COLUMN=24
ENV_WORKER_URL="${WORKER_URL-}"
ENV_SOURCE_ID="${SOURCE_ID-}"
ENV_IDENTITY="${IDENTITY-}"
ENV_ALLOW_HTTP="${ALLOW_HTTP-}"
ENV_IP_CHECK_URL="${IP_CHECK_URL-}"
ENV_IP_CHECK_URLS="${IP_CHECK_URLS-}"
ENV_INSTALL_PATH="${INSTALL_PATH-}"
ENV_MINUTES="${MINUTES-}"
ENV_INTERVAL_SECONDS="${INTERVAL_SECONDS-}"
CONFIG_FILE="${PO0_SELF_REPORT_CONFIG:-${SELF_REPORT_CONFIG:-}}"
WORKER_URL=""
SOURCE_ID=""
IDENTITY=""
SOURCE_ID_EXPLICIT="0"
IDENTITY_EXPLICIT="0"
SECRET=""
ALLOW_HTTP=""
IP_CHECK_URL="https://ip9.com.cn/get"
IP_CHECK_URLS=""
INSTALL_PATH=""
INSTALL_CRON=""
SHOW_MENU=""
SHOW_VERSION=""
SHOW_CHANGELOG=""
UPGRADE_SELF=""
SAVE_CONFIG=""
PAUSE_SCHEDULE=""
RESUME_SCHEDULE=""
SHOW_SCHEDULE_STATUS=""
SCHEDULE_PAUSED="0"
CRON_MINUTES="60"
MAX_CRON_MINUTES="10080"
INTERVAL_SECONDS=""
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

print_title() {
    printf '\n'
    print_menu_divider
    printf '%b%s%b\n' "${C_BOLD}${C_CYAN}" "$1" "${C_RESET}"
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
    printf '  %b%2s%b) %s' "${C_CYAN}" "${left_number}" "${C_RESET}" "${left_label}"
    if [[ -n "${right_number}" ]]; then
        if [[ -t 1 ]]; then
            printf '\033[%sG' "${MENU_RIGHT_COLUMN}"
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
        printf '\033[%sG' "${PANEL_VALUE_COLUMN}"
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
    printf '    %s\n' "$*"
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

script_file_var() {
    local file="$1"
    local name="$2"
    awk -F= -v key="${name}" '
        $1 == key {
            value=$0
            sub("^[^=]*=", "", value)
            gsub(/^[[:space:]]*"/, "", value)
            gsub(/"[[:space:]]*$/, "", value)
            print value
            exit
        }
    ' "${file}" 2>/dev/null || true
}

script_file_changelog() {
    local file="$1"
    local line in_block=0 found=0
    [[ -r "${file}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" == "# CHANGELOG_BEGIN" ]]; then
            in_block=1
            continue
        fi
        if [[ "${line}" == "# CHANGELOG_END" ]]; then
            break
        fi
        [[ "${in_block}" == "1" ]] || continue
        line="${line#\# }"
        line="${line#\#}"
        line="$(trim "${line}")"
        [[ -n "${line}" ]] || continue
        found=1
        printf '%s\n' "${line}"
    done < "${file}"
    [[ "${found}" == "1" ]]
}

current_script_source_file() {
    local source="${BASH_SOURCE[0]:-}" dir base abs_dir
    case "${source}" in
        ""|"-"|"/dev/stdin"|/dev/fd/*|/proc/self/fd/*) return 1 ;;
    esac
    [[ -f "${source}" ]] || return 1
    if command -v readlink >/dev/null 2>&1; then
        readlink -f "${source}" 2>/dev/null && return 0
    fi
    if command -v realpath >/dev/null 2>&1; then
        realpath "${source}" 2>/dev/null && return 0
    fi
    case "${source}" in
        /*) printf '%s\n' "${source}" ;;
        *)
            dir="${source%/*}"
            base="${source##*/}"
            [[ "${dir}" == "${source}" ]] && dir="."
            if abs_dir="$(cd -P -- "${dir}" 2>/dev/null && pwd -P)"; then
                printf '%s/%s\n' "${abs_dir}" "${base}"
            else
                printf '%s\n' "${source}"
            fi
            ;;
    esac
}

current_script_path() {
    local source="${BASH_SOURCE[0]:-}" path
    if path="$(current_script_source_file)"; then
        printf '%s\n' "${path}"
        return 0
    fi
    case "${source}" in
        ""|"-"|"bash"|"main"|"/dev/stdin"|/dev/fd/*|/proc/self/fd/*)
            printf '标准输入（bash -s / curl | bash，未落盘）\n'
            ;;
        *)
            printf '未知（%s 不可读）\n' "${source}"
            ;;
    esac
}

script_build_label() {
    if [[ "${SCRIPT_VERSION}" == *"+"* ]]; then
        printf '%s\n' "${SCRIPT_VERSION#*+}"
    else
        printf '未标识\n'
    fi
}

show_version() {
    printf '%s\n' \
        "脚本名称：${SCRIPT_NAME}" \
        "版本：${SCRIPT_VERSION}" \
        "构建标识：$(script_build_label)" \
        "发布日期：${SCRIPT_RELEASE_DATE}" \
        "执行来源：$(current_script_path)" \
        "默认安装路径：$(default_install_path)" \
        "配置文件：${CONFIG_FILE}" \
        "定时上报：$(cron_status_summary)" \
        "下载 URL：${DOWNLOAD_URL}"
}

show_changelog() {
    local changelog script_file=""
    script_file="$(current_script_source_file || true)"
    if [[ -n "${script_file}" ]] && changelog="$(script_file_changelog "${script_file}")"; then
        printf '%s\n' "${changelog}"
    else
        printf '当前脚本未提供更新内容。\n'
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

to_lower() {
    local value="$1" out="" ch i
    for ((i = 0; i < ${#value}; i++)); do
        ch="${value:i:1}"
        case "${ch}" in
            A) out="${out}a" ;;
            B) out="${out}b" ;;
            C) out="${out}c" ;;
            D) out="${out}d" ;;
            E) out="${out}e" ;;
            F) out="${out}f" ;;
            G) out="${out}g" ;;
            H) out="${out}h" ;;
            I) out="${out}i" ;;
            J) out="${out}j" ;;
            K) out="${out}k" ;;
            L) out="${out}l" ;;
            M) out="${out}m" ;;
            N) out="${out}n" ;;
            O) out="${out}o" ;;
            P) out="${out}p" ;;
            Q) out="${out}q" ;;
            R) out="${out}r" ;;
            S) out="${out}s" ;;
            T) out="${out}t" ;;
            U) out="${out}u" ;;
            V) out="${out}v" ;;
            W) out="${out}w" ;;
            X) out="${out}x" ;;
            Y) out="${out}y" ;;
            Z) out="${out}z" ;;
            *) out="${out}${ch}" ;;
        esac
    done
    printf '%s\n' "${out}"
}

digits_only() {
    local value="$1" out="" ch i
    for ((i = 0; i < ${#value}; i++)); do
        ch="${value:i:1}"
        case "${ch}" in
            [0-9]) out="${out}${ch}" ;;
        esac
    done
    printf '%s\n' "${out}"
}

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local suffix value
    case "$(to_lower "${default}")" in
        y|yes|1|true) suffix="Y/n"; default="y" ;;
        *) suffix="y/N"; default="n" ;;
    esac
    while true; do
        value="$(read_prompt "${prompt} [${suffix}]: ")" || return 1
        value="$(trim "${value}")"
        [[ -n "${value}" ]] || value="${default}"
        case "$(to_lower "${value}")" in
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
    if [[ -n "${PO0_SELF_REPORT_SOURCE+x}" ]]; then
        SOURCE_ID="${PO0_SELF_REPORT_SOURCE}"
        SOURCE_ID_EXPLICIT="1"
    fi
    if [[ -n "${ENV_SOURCE_ID}" ]]; then
        SOURCE_ID="${ENV_SOURCE_ID}"
        SOURCE_ID_EXPLICIT="1"
    fi
    if [[ -n "${PO0_SELF_REPORT_IDENTITY+x}" ]]; then
        IDENTITY="${PO0_SELF_REPORT_IDENTITY}"
        IDENTITY_EXPLICIT="1"
    fi
    if [[ -n "${ENV_IDENTITY}" ]]; then
        IDENTITY="${ENV_IDENTITY}"
        IDENTITY_EXPLICIT="1"
    fi
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
    [[ -n "${PO0_SELF_REPORT_INTERVAL_SECONDS+x}" ]] && INTERVAL_SECONDS="${PO0_SELF_REPORT_INTERVAL_SECONDS}"
    [[ -n "${ENV_INTERVAL_SECONDS}" ]] && INTERVAL_SECONDS="${ENV_INTERVAL_SECONDS}"
    [[ -n "${PO0_SELF_REPORT_MAX_MINUTES+x}" ]] && MAX_CRON_MINUTES="${PO0_SELF_REPORT_MAX_MINUTES}"
    [[ -n "${PO0_SELF_REPORT_PAUSED+x}" ]] && SCHEDULE_PAUSED="${PO0_SELF_REPORT_PAUSED}"
}

sanitize_device_id_part() {
    local value="$1" out="" ch i
    value="$(trim "${value}")"
    value="$(to_lower "${value}")"
    for ((i = 0; i < ${#value}; i++)); do
        ch="${value:i:1}"
        case "${ch}" in
            [a-z0-9._-])
                out+="${ch}"
                ;;
            *)
                [[ "${out}" == *- ]] || out+="-"
                ;;
        esac
    done
    while [[ "${out}" == -* ]]; do out="${out#-}"; done
    while [[ "${out}" == *- ]]; do out="${out%-}"; done
    [[ -n "${out}" ]] || return 1
    [[ ${#out} -le 48 ]] || out="${out:0:48}"
    while [[ "${out}" == *- ]]; do out="${out%-}"; done
    printf '%s\n' "${out}"
}

normalize_report_token() {
    local value="$1" fallback="${2:-self-report}" normalized
    normalized="$(sanitize_device_id_part "${value}" 2>/dev/null || true)"
    if [[ -n "${normalized}" ]]; then
        printf '%s\n' "${normalized}"
    else
        printf '%s\n' "${fallback}"
    fi
}

default_device_hostname() {
    local value
    value="$(hostname 2>/dev/null || true)"
    value="$(trim "${value}")"
    case "$(to_lower "${value}")" in
        ""|"(none)"|"localhost"|"localhost.localdomain")
            value=""
            ;;
    esac
    if [[ -z "${value}" && -r /proc/sys/kernel/hostname ]]; then
        IFS= read -r value < /proc/sys/kernel/hostname || value=""
        value="$(trim "${value}")"
    fi
    [[ -n "${value}" ]] || value="linux-device"
    printf '%s\n' "${value}"
}

default_machine_id_part() {
    local path value
    for path in /etc/machine-id /var/lib/dbus/machine-id; do
        [[ -r "${path}" ]] || continue
        IFS= read -r value < "${path}" || value=""
        value="$(trim "${value}")"
        value="${value//-/}"
        value="$(to_lower "${value}")"
        [[ "${value}" =~ ^[0-9a-f]+$ ]] || continue
        if [[ ${#value} -ge 8 ]]; then
            printf '%s\n' "${value:0:16}"
            return 0
        fi
    done
    return 1
}

default_mac_id_part() {
    local path iface value
    for path in /sys/class/net/*/address; do
        [[ -r "${path}" ]] || continue
        iface="${path%/address}"
        iface="${iface##*/}"
        [[ "${iface}" == "lo" ]] && continue
        IFS= read -r value < "${path}" || value=""
        value="$(trim "${value}")"
        value="${value//:/}"
        value="$(to_lower "${value}")"
        [[ ${#value} -eq 12 ]] || continue
        [[ "${value}" =~ ^[0-9a-f]+$ ]] || continue
        [[ "${value}" =~ ^0+$ ]] && continue
        printf '%s\n' "${value}"
        return 0
    done
    return 1
}

default_source_id() {
    local host host_part id_part
    host="$(default_device_hostname)"
    host_part="$(sanitize_device_id_part "${host}" 2>/dev/null || true)"
    [[ -n "${host_part}" ]] || host_part="linux-device"
    id_part="$(default_machine_id_part 2>/dev/null || default_mac_id_part 2>/dev/null || true)"
    if [[ -n "${id_part}" ]]; then
        printf '%s-%s\n' "${host_part}" "${id_part}"
    else
        printf '%s\n' "${host_part}"
    fi
}

apply_device_defaults() {
    if [[ "${IDENTITY_EXPLICIT}" != "1" ]]; then
        case "${IDENTITY}" in
            ""|"self-report"|"linux-self-report")
                IDENTITY="$(default_device_hostname)"
                ;;
        esac
    fi
    if [[ "${SOURCE_ID_EXPLICIT}" != "1" ]]; then
        case "${SOURCE_ID}" in
            ""|"self-report"|"linux-self-report")
                SOURCE_ID="$(default_source_id)"
                ;;
        esac
    fi
    SOURCE_ID="$(normalize_report_token "${SOURCE_ID}" "$(default_source_id)")"
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
        write_env_assignment "INTERVAL_SECONDS" "$((10#${CRON_MINUTES:-60} * 60))"
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
    case "$(to_lower "${ALLOW_HTTP}")" in
        1|true|yes|y) return 0 ;;
        *) return 1 ;;
    esac
}

schedule_paused() {
    case "$(to_lower "${SCHEDULE_PAUSED}")" in
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

normalize_interval_seconds_to_minutes() {
    local seconds="${1:-}"
    local max_minutes="${2:-10080}"
    local max_seconds
    seconds="$(trim "${seconds}")"
    [[ "${max_minutes}" =~ ^[0-9]+$ && "${max_minutes}" -ge 1 ]] || max_minutes="10080"
    max_seconds=$((10#${max_minutes} * 60))
    [[ "${seconds}" =~ ^[0-9]+$ ]] || return 1
    (( 10#${seconds} >= 60 && 10#${seconds} <= max_seconds )) || return 1
    (( 10#${seconds} % 60 == 0 )) || return 1
    printf '%s\n' "$((10#${seconds} / 60))"
}

cron_minutes_to_seconds() {
    local minutes="${1:-}"
    [[ "${minutes}" =~ ^[0-9]+$ && "${minutes}" -ge 1 ]] || minutes="60"
    printf '%s\n' "$((10#${minutes} * 60))"
}

max_interval_seconds() {
    local max="${MAX_CRON_MINUTES:-10080}"
    [[ "${max}" =~ ^[0-9]+$ && "${max}" -ge 1 ]] || max="10080"
    printf '%s\n' "$((10#${max} * 60))"
}

apply_interval_seconds_override() {
    local max_display
    [[ -n "${INTERVAL_SECONDS:-}" ]] || return 0
    max_display="${MAX_CRON_MINUTES:-10080}"
    [[ "${max_display}" =~ ^[0-9]+$ && "${max_display}" -ge 1 ]] || max_display="10080"
    CRON_MINUTES="$(normalize_interval_seconds_to_minutes "${INTERVAL_SECONDS}" "${MAX_CRON_MINUTES}")" || {
        printf '上报间隔秒数无效：请输入 60-%s 且为 60 倍数的整数。\n' "$((10#${max_display} * 60))" >&2
        return 1
    }
}

cron_interval_label() {
    local minutes="$1"
    if [[ "${minutes}" =~ ^[0-9]+$ ]]; then
        printf '每 %s 分钟' "$((10#${minutes}))"
    else
        printf '每 %s 分钟' "${minutes}"
    fi
}

cron_interval_label_from_minutes() {
    local minutes="$1"
    [[ "${minutes}" =~ ^[0-9]+$ && "${minutes}" -ge 1 ]] || return 1
    cron_interval_label "$((10#${minutes}))"
}

interval_seconds_label() {
    local seconds="$1"
    [[ "${seconds}" =~ ^[0-9]+$ && "${seconds}" -ge 1 ]] || return 1
    if (( 10#${seconds} % 60 == 0 )); then
        cron_interval_label_from_minutes "$((10#${seconds} / 60))"
    else
        printf '每 %s 秒' "$((10#${seconds}))"
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
    local dest dir source
    dest="$(default_install_path)"
    dir="$(dirname "${dest}")"
    source="${BASH_SOURCE[0]}"
    mkdir -p "${dir}" || return 1
    if [[ -r "${source}" && "${source}" != /dev/fd/* && "${source}" != /proc/* && "${source}" != /dev/stdin ]]; then
        if [[ -e "${dest}" && "${source}" -ef "${dest}" ]]; then
            :
        else
            cp "${source}" "${dest}" || return 1
        fi
    elif command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 15 --max-time 120 "${DOWNLOAD_URL}" -o "${dest}" || return 1
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 120 -O "${dest}" "${DOWNLOAD_URL}" || return 1
    else
        echo "缺少 curl/wget，无法把管道运行的脚本落盘。" >&2
        return 1
    fi
    chmod 755 "${dest}" || true
    printf '%s\n' "${dest}"
}

upgrade_self_from_download() {
    local reopen_mode="${1:-}" dest dir tmp new_version changelog chmod_message
    dest="$(default_install_path)"
    dir="$(dirname "${dest}")"
    mkdir -p "${dir}" || return 1
    if command -v mktemp >/dev/null 2>&1; then
        tmp="$(mktemp "${dir}/.po0-self-report.XXXXXX")" || return 1
    else
        tmp="${dest}.tmp.$$"
    fi
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 15 --max-time 120 "${DOWNLOAD_URL}" -o "${tmp}" || {
            rm -f "${tmp}" 2>/dev/null || true
            return 1
        }
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 120 -O "${tmp}" "${DOWNLOAD_URL}" || {
            rm -f "${tmp}" 2>/dev/null || true
            return 1
        }
    else
        rm -f "${tmp}" 2>/dev/null || true
        printf '无法更新：系统缺少 curl/wget。\n' >&2
        return 1
    fi
    if ! grep -q 'po0-outbound-ip-report-macos.sh' "${tmp}" || ! grep -q 'PO0 自上报客户端（macOS）' "${tmp}"; then
        rm -f "${tmp}" 2>/dev/null || true
        printf '更新文件校验失败：下载到的脚本不是 Self-report macOS 客户端。\n' >&2
        return 1
    fi
    if ! bash -n "${tmp}"; then
        rm -f "${tmp}" 2>/dev/null || true
        printf '更新文件校验失败：下载到的脚本未通过 bash -n。\n' >&2
        return 1
    fi
    new_version="$(script_file_var "${tmp}" "SCRIPT_VERSION")"
    changelog="$(script_file_changelog "${tmp}")"
    mv -f "${tmp}" "${dest}" || {
        rm -f "${tmp}" 2>/dev/null || true
        return 1
    }
    if chmod 755 "${dest}" 2>/dev/null; then
        chmod_message="已设置执行权限：chmod 755 ${dest}"
    else
        chmod_message="警告：已更新，但自动设置执行权限失败；请手动执行 chmod 755 ${dest}"
    fi
    printf '已更新 Self-report 客户端脚本：%s\n' "${dest}"
    printf '下载 URL：%s\n' "${DOWNLOAD_URL}"
    printf '%s\n' "${chmod_message}"
    if [[ -n "${new_version}" ]]; then
        if [[ "${new_version}" == "${SCRIPT_VERSION}" ]]; then
            printf '版本：%s（与当前执行脚本相同）\n' "${new_version}"
        else
            printf '版本：%s -> %s\n' "${SCRIPT_VERSION}" "${new_version}"
        fi
    else
        printf '版本：无法读取新脚本版本。\n'
    fi
    if [[ -n "${changelog}" ]]; then
        printf '更新内容：\n%s\n' "${changelog}"
    else
        printf '更新内容：新脚本未提供更新说明。\n'
    fi
    if [[ "${reopen_mode}" == "--reopen-menu" ]]; then
        read_prompt "更新完成。按回车打开新版菜单..." >/dev/null || true
        printf '正在重新打开新版菜单：%s --menu\n' "${dest}"
        exec "${BASH:-bash}" "${dest}" --config "${CONFIG_FILE}" --install-path "${dest}" --menu
        printf '重新打开新版脚本失败，请手动执行：%s --menu\n' "${dest}" >&2
        return 1
    fi
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
    command -v crontab >/dev/null 2>&1 || return 1
    crontab -l 2>/dev/null | grep -q '^# PO0_SELF_REPORT_BEGIN'
}

is_macos() {
    [[ "$(uname -s 2>/dev/null || printf '')" == "Darwin" ]]
}

launchd_label() {
    printf '%s\n' "fr.schweppes.po0-self-report"
}

launchd_supported() {
    is_macos || return 1
    command -v launchctl >/dev/null 2>&1 || return 1
    if [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]]; then
        return 0
    fi
    [[ -n "${HOME:-}" ]]
}

launchd_plist_path() {
    local label
    label="$(launchd_label)"
    if [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]]; then
        printf '/Library/LaunchDaemons/%s.plist\n' "${label}"
    else
        printf '%s/Library/LaunchAgents/%s.plist\n' "${HOME}" "${label}"
    fi
}

launchd_domain() {
    if [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]]; then
        printf 'system\n'
    else
        printf 'gui/%s\n' "$(id -u)"
    fi
}

xml_escape() {
    local value="$1"
    value="${value//&/&amp;}"
    value="${value//</&lt;}"
    value="${value//>/&gt;}"
    value="${value//\"/&quot;}"
    printf '%s' "${value}"
}

write_launchd_plist() {
    local plist="$1" script="$2" interval_seconds="$3" log_path disabled
    log_path="$(self_report_log_path)"
    if schedule_paused; then
        disabled="true"
    else
        disabled="false"
    fi
    cat > "${plist}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$(xml_escape "$(launchd_label)")</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$(xml_escape "${script}")</string>
        <string>--config</string>
        <string>$(xml_escape "${CONFIG_FILE}")</string>
    </array>
    <key>StartInterval</key>
    <integer>${interval_seconds}</integer>
    <key>Disabled</key>
    <${disabled}/>
    <key>StandardOutPath</key>
    <string>$(xml_escape "${log_path}")</string>
    <key>StandardErrorPath</key>
    <string>$(xml_escape "${log_path}")</string>
</dict>
</plist>
EOF
}

launchd_unload() {
    local plist="$1" domain
    domain="$(launchd_domain)"
    launchctl bootout "${domain}" "${plist}" >/dev/null 2>&1 || launchctl unload "${plist}" >/dev/null 2>&1 || true
}

launchd_load() {
    local plist="$1" domain label
    domain="$(launchd_domain)"
    label="$(launchd_label)"
    launchctl bootstrap "${domain}" "${plist}" >/dev/null 2>&1 || launchctl load "${plist}" >/dev/null 2>&1 || return 1
    launchctl enable "${domain}/${label}" >/dev/null 2>&1 || true
}

launchd_interval_seconds_from_plist() {
    local plist="$1"
    awk '/<key>StartInterval<\/key>/{getline; gsub(/.*<integer>|<\/integer>.*/, ""); print; exit}' "${plist}" 2>/dev/null
}

launchd_disabled_from_plist() {
    local plist="$1" disabled
    disabled="$(awk '/<key>Disabled<\/key>/{getline; if ($0 ~ /<true\/>/) print "1"; else print "0"; exit}' "${plist}" 2>/dev/null)"
    printf '%s\n' "${disabled:-0}"
}

read_launchd_status_snapshot() {
    local plist interval_seconds interval="" config_paused disabled state consistency="ok"
    launchd_supported || return 1
    plist="$(launchd_plist_path)"
    config_paused="$(schedule_paused && printf '1' || printf '0')"
    [[ -f "${plist}" ]] || {
        printf 'uninstalled||%s||ok\n' "${config_paused}"
        return 0
    }
    interval_seconds="$(launchd_interval_seconds_from_plist "${plist}")"
    interval="$(interval_seconds_label "${interval_seconds}" 2>/dev/null || true)"
    disabled="$(launchd_disabled_from_plist "${plist}")"
    if [[ "${disabled}" == "1" || "${config_paused}" == "1" ]]; then
        state="paused"
    else
        state="running"
    fi
    if [[ "${state}" == "running" && "${config_paused}" == "1" ]]; then
        consistency="drift"
    elif [[ "${state}" == "paused" && "${config_paused}" != "1" && "${disabled}" == "1" ]]; then
        consistency="drift"
    fi
    printf '%s|%s|%s|launchd: %s|%s\n' "${state}" "${interval}" "${config_paused}" "${plist}" "${consistency}"
}

schedule_backend() {
    if launchd_supported; then
        printf 'launchd\n'
    elif command -v crontab >/dev/null 2>&1; then
        printf 'cron\n'
    else
        printf 'none\n'
    fi
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

install_launchd() {
    local script plist dir interval_seconds
    validate_cron_minutes || { self_report_incomplete "上报间隔配置无效，未安装 launchd 计划。"; return 1; }
    validate_worker_url || { self_report_incomplete "LAN Worker URL 未通过检查，未安装 launchd 计划。"; return 1; }
    save_config_file || { self_report_incomplete "配置保存失败，未安装 launchd 计划。"; return 1; }
    launchd_supported || {
        echo "当前系统不支持 launchd 安装。" >&2
        self_report_incomplete "缺少 crontab，且当前环境不是可用的 macOS launchd。"
        return 1
    }
    script="$(install_self)" || { self_report_incomplete "脚本落盘失败，未安装 launchd 计划。"; return 1; }
    plist="$(launchd_plist_path)"
    dir="$(path_dirname "${plist}")"
    mkdir -p "${dir}" || { self_report_incomplete "LaunchAgent 目录创建失败：${dir}"; return 1; }
    interval_seconds="$(cron_minutes_to_seconds "${CRON_MINUTES}")"
    write_launchd_plist "${plist}" "${script}" "${interval_seconds}" || {
        self_report_incomplete "LaunchAgent 写入失败：${plist}"
        return 1
    }
    chmod 644 "${plist}" 2>/dev/null || true
    if [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]]; then
        chown root:wheel "${plist}" 2>/dev/null || true
    fi
    launchd_unload "${plist}"
    if ! schedule_paused; then
        launchd_load "${plist}" || {
            self_report_incomplete "launchd 加载失败，已写入 plist：${plist}"
            return 1
        }
    fi
    echo "已安装 self-report launchd 计划：每 ${interval_seconds} 秒上报一次。"
    echo "LaunchAgent：${plist}"
    echo "脚本路径：${script}"
    echo "配置文件：${CONFIG_FILE}"
    if schedule_paused; then
        self_report_completed "定时上报已安装 / 更新，但当前保持暂停。"
    else
        self_report_completed "定时上报已安装 / 更新，每 ${interval_seconds} 秒执行一次。"
    fi
}

install_cron_backend() {
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
        printf '# interval_minutes=%s\n' "${CRON_MINUTES}"
        echo "${job}"
        cron_end_marker
    } > "${tmp}" || { self_report_incomplete "写入临时 cron 配置失败。"; return 1; }
    crontab "${tmp}" || {
        rm -f "${tmp}" 2>/dev/null || true
        self_report_incomplete "crontab 写入失败，未安装 cron。"
        return 1
    }
    rm -f "${tmp}" 2>/dev/null || true
    echo "已安装 self-report cron：每 $(cron_minutes_to_seconds "${CRON_MINUTES}") 秒上报一次。"
    echo "脚本路径：${script}"
    echo "配置文件：${CONFIG_FILE}"
    if schedule_paused; then
        self_report_completed "定时上报已安装 / 更新，但当前保持暂停。"
    else
        self_report_completed "定时上报已安装 / 更新，每 $(cron_minutes_to_seconds "${CRON_MINUTES}") 秒执行一次。"
    fi
}

install_cron() {
    case "$(schedule_backend)" in
        cron) install_cron_backend ;;
        launchd) install_launchd ;;
        *)
            echo "未找到 crontab 命令。" >&2
            self_report_incomplete "缺少 crontab，且当前环境不是可用的 macOS launchd。"
            return 1
            ;;
    esac
}

remove_launchd() {
    local plist
    launchd_supported || return 1
    plist="$(launchd_plist_path)"
    if [[ -f "${plist}" ]]; then
        launchd_unload "${plist}"
        rm -f "${plist}" || {
            self_report_incomplete "删除 launchd plist 失败：${plist}"
            return 1
        }
        echo "已删除本脚本管理的 self-report launchd 计划：${plist}"
    else
        echo "未发现本脚本管理的 self-report launchd 计划。"
    fi
}

remove_cron_backend() {
    local tmp
    command -v crontab >/dev/null 2>&1 || {
        echo "未找到 crontab 命令。" >&2
        self_report_incomplete "缺少 crontab，未删除 cron。"
        return 1
    }
    if command -v mktemp >/dev/null 2>&1; then
        tmp="$(mktemp "${TMPDIR:-/tmp}/po0-self-report-cron.XXXXXX")" || return 1
    else
        tmp="${TMPDIR:-/tmp}/po0-self-report-cron.$$"
    fi
    crontab -l 2>/dev/null | write_cron_without_managed_block > "${tmp}" || true
    crontab "${tmp}" || {
        rm -f "${tmp}" 2>/dev/null || true
        self_report_incomplete "crontab 写入失败，未删除 cron。"
        return 1
    }
    rm -f "${tmp}" 2>/dev/null || true
    echo "已删除本脚本管理的 self-report cron。"
}

remove_cron() {
    local did=0 errors=0
    if command -v crontab >/dev/null 2>&1; then
        remove_cron_backend || errors=1
        did=1
    fi
    if launchd_supported && [[ -f "$(launchd_plist_path)" ]]; then
        remove_launchd || errors=1
        did=1
    fi
    if [[ "${did}" != "1" ]]; then
        echo "未发现可删除的 self-report 定时上报。"
    fi
    if [[ "${errors}" == "1" ]]; then
        self_report_incomplete "定时上报删除未完全成功。"
        return 1
    fi
    self_report_completed "已删除本脚本管理的定时上报。"
}

self_report_log_path() {
    printf '%s\n' "/tmp/po0-self-report.log"
}

log_file_mtime_label() {
    local path="$1" value
    value="$(stat -c '%y' "${path}" 2>/dev/null || true)"
    if [[ -n "${value}" ]]; then
        printf '%s\n' "${value%%.*}"
        return 0
    fi
    value="$(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "${path}" 2>/dev/null || true)"
    [[ -n "${value}" ]] || return 1
    printf '%s\n' "${value}"
}

normalize_self_report_log_line() {
    local line="$1"
    line="${line%$'\r'}"
    line="$(trim "${line}")"
    [[ -n "${line}" ]] || return 1
    if [[ "${line}" =~ ^\[[^]]+\][[:space:]]+\[[^]]+\][[:space:]]+(.*)$ ]]; then
        line="${BASH_REMATCH[1]}"
    elif [[ "${line}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[T[:space:]][0-9:.+Z-]+[[:space:]]+\[?[A-Za-z]+\]?[[:space:]:-]+(.*)$ ]]; then
        line="${BASH_REMATCH[1]}"
    elif [[ "${line}" =~ ^\[[A-Za-z]+\][[:space:]]+(.*)$ ]]; then
        line="${BASH_REMATCH[1]}"
    elif [[ "${line}" =~ ^(INFO|WARN|WARNING|ERROR|DEBUG)[[:space:]:-]+(.*)$ ]]; then
        line="${BASH_REMATCH[2]}"
    fi
    line="$(trim "${line}")"
    [[ -n "${line}" ]] || return 1
    printf '%s\n' "${line}"
}

self_report_log_event_summary() {
    local line="$1"
    line="$(normalize_self_report_log_line "${line}")" || return 1
    case "${line}" in
        "Self-report 已完成："*)
            printf '成功：%s\n' "${line#Self-report 已完成：}"
            ;;
        "Self-report 未完成："*)
            printf '失败：%s\n' "${line#Self-report 未完成：}"
            ;;
        *"未能探测到当前公网出口 IPv4"*)
            printf '探测失败：未能探测到当前公网出口 IPv4\n'
            ;;
        curl:\ *|*"curl exit "*)
            printf '网络错误：%s\n' "${line}"
            ;;
        *)
            return 1
            ;;
    esac
}

show_recent_self_report_log() {
    local log_path mtime line event max_events=5 i
    local events=()
    log_path="$(self_report_log_path)"
    print_panel_section "最近日志"
    print_panel_row "原始日志" "${log_path}"
    print_panel_row "查看原文" "tail -n 40 ${log_path}"
    if [[ ! -e "${log_path}" ]]; then
        print_panel_row "最近结果" "暂无日志"
        return 0
    fi
    if [[ ! -s "${log_path}" ]]; then
        print_panel_row "最近结果" "日志为空"
        return 0
    fi
    mtime="$(log_file_mtime_label "${log_path}" 2>/dev/null || true)"
    [[ -n "${mtime}" ]] && print_panel_row "最后更新" "${mtime}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        event="$(self_report_log_event_summary "${line}" 2>/dev/null || true)"
        [[ -n "${event}" ]] || continue
        events+=("${event}")
        if (( ${#events[@]} > max_events )); then
            events=("${events[@]:1}")
        fi
    done < <(tail -n 120 "${log_path}" 2>/dev/null || true)
    if (( ${#events[@]} == 0 )); then
        print_panel_row "最近结果" "未发现可摘要的 self-report 结果；请查看原始日志"
        return 0
    fi
    print_panel_row "最近结果" "${events[0]}"
    for ((i = 1; i < ${#events[@]}; i++)); do
        print_panel_note "${events[$i]}"
    done
}

remove_file_if_exists() {
    local label="$1"
    local path="$2"
    [[ -n "${path}" ]] || return 0
    if [[ -e "${path}" || -L "${path}" ]]; then
        if rm -f -- "${path}"; then
            printf '已删除%s：%s\n' "${label}" "${path}"
        else
            printf '删除%s失败：%s\n' "${label}" "${path}" >&2
            return 1
        fi
    else
        printf '%s不存在：%s\n' "${label}" "${path}"
    fi
}

remove_cron_for_uninstall() {
    if command -v crontab >/dev/null 2>&1 || launchd_supported; then
        remove_cron
    else
        echo "未找到 crontab 命令，且当前环境不能使用 macOS launchd，跳过定时上报删除。"
    fi
}

uninstall_self_report_interactive() {
    local install_path log_path remove_data errors=0
    install_path="$(default_install_path)"
    log_path="$(self_report_log_path)"
    echo "卸载会删除本脚本管理的定时上报和本机安装脚本。"
    echo "本机安装脚本：${install_path}"
    echo "配置文件和日志默认保留，后续可选择是否一起删除。"
    if ! prompt_yes_no "确认卸载 self-report 客户端" "n"; then
        echo "已取消。"
        return 2
    fi
    remove_cron_for_uninstall || errors=1
    remove_file_if_exists "本机脚本" "${install_path}" || errors=1
    if prompt_yes_no "是否同时删除配置文件和日志" "n"; then
        remove_data="1"
    else
        remove_data="0"
    fi
    if [[ "${remove_data}" == "1" ]]; then
        remove_file_if_exists "配置文件" "${CONFIG_FILE}" || errors=1
        remove_file_if_exists "日志文件" "${log_path}" || errors=1
    else
        echo "已保留配置文件：${CONFIG_FILE}"
        echo "已保留日志文件：${log_path}"
    fi
    if [[ "${errors}" == "1" ]]; then
        self_report_incomplete "卸载已执行，但有项目删除失败。"
        return 1
    fi
    self_report_completed "卸载已完成。"
}

cron_job_has_schedule() {
    local line="$1" minute hour day month weekday rest
    read -r minute hour day month weekday rest <<< "${line}"
    [[ -n "${minute:-}" && -n "${hour:-}" && -n "${day:-}" && -n "${month:-}" && -n "${weekday:-}" ]]
}

cron_job_interval_label() {
    local line="$1" minute hour day month weekday rest
    read -r minute hour day month weekday rest <<< "${line}"
    if [[ "${line}" =~ now[[:space:]]*/[[:space:]]*60[[:space:]]*\\%[[:space:]]*([0-9]+) ]]; then
        cron_interval_label_from_minutes "${BASH_REMATCH[1]}"
        return $?
    fi
    if [[ "${line}" =~ now[[:space:]]*/[[:space:]]*3600[[:space:]]*\\%[[:space:]]*([0-9]+) ]]; then
        cron_interval_label_from_minutes "$((10#${BASH_REMATCH[1]} * 60))"
        return $?
    fi
    if [[ "${minute:-}" =~ ^\*/([0-9]+)$ && "${hour:-}" == "*" ]]; then
        cron_interval_label_from_minutes "${BASH_REMATCH[1]}"
    elif [[ "${minute:-}" == "0" && "${hour:-}" == "*" && "${day:-}" == "*" && "${month:-}" == "*" && "${weekday:-}" == "*" ]]; then
        cron_interval_label_from_minutes 60
    elif [[ "${minute:-}" == "0" && "${hour:-}" =~ ^\*/([0-9]+)$ && "${day:-}" == "*" && "${month:-}" == "*" && "${weekday:-}" == "*" ]]; then
        cron_interval_label_from_minutes "$((10#${BASH_REMATCH[1]} * 60))"
    elif [[ "${minute:-}" == "0" && "${hour:-}" == "0" && "${day:-}" == "*" && "${month:-}" == "*" && "${weekday:-}" == "*" ]]; then
        cron_interval_label_from_minutes 1440
    else
        return 1
    fi
}

read_cron_status_snapshot() {
    local line in_block=0 found=0 active_job="" paused_job="" metadata_interval="" job=""
    local state interval="" config_paused consistency="ok"
    config_paused="$(schedule_paused && printf '1' || printf '0')"
    if ! command -v crontab >/dev/null 2>&1; then
        if launchd_supported; then
            read_launchd_status_snapshot
            return 0
        fi
        printf 'unavailable||%s||ok\n' "${config_paused}"
        return 0
    fi
    while IFS= read -r line || [[ -n "${line}" ]]; do
        case "${line}" in
            "# PO0_SELF_REPORT_BEGIN"*) in_block=1; found=1; continue ;;
            "# PO0_SELF_REPORT_END"*) in_block=0; continue ;;
        esac
        [[ "${in_block}" == "1" ]] || continue
        case "${line}" in
            "# interval_minutes="*)
                metadata_interval="${line#"# interval_minutes="}"
                ;;
            "# paused="*|"")
                ;;
            \#*)
                job="${line#\#}"
                job="${job# }"
                if cron_job_has_schedule "${job}"; then
                    paused_job="${job}"
                fi
                ;;
            *)
                if cron_job_has_schedule "${line}"; then
                    active_job="${line}"
                fi
                ;;
        esac
    done < <(crontab -l 2>/dev/null || true)

    if [[ "${found}" != "1" ]]; then
        if launchd_supported && [[ -f "$(launchd_plist_path)" ]]; then
            read_launchd_status_snapshot
            return 0
        fi
        printf 'uninstalled||%s||ok\n' "${config_paused}"
        return 0
    fi
    if [[ -n "${active_job}" ]]; then
        state="running"
        job="${active_job}"
    elif [[ -n "${paused_job}" ]]; then
        state="paused"
        job="${paused_job}"
    else
        printf 'invalid||%s||ok\n' "${config_paused}"
        return 0
    fi

    if ! interval="$(cron_interval_label_from_minutes "${metadata_interval}" 2>/dev/null)"; then
        interval="$(cron_job_interval_label "${job}" 2>/dev/null || true)"
    fi
    if [[ "${state}" == "running" && "${config_paused}" == "1" ]]; then
        consistency="drift"
    elif [[ "${state}" == "paused" && "${config_paused}" != "1" ]]; then
        consistency="drift"
    fi
    printf '%s|%s|%s|%s|%s\n' "${state}" "${interval}" "${config_paused}" "${job}" "${consistency}"
}

cron_state_label() {
    case "$1" in
        running) printf '运行中' ;;
        paused) printf '已暂停' ;;
        uninstalled) printf '未安装' ;;
        unavailable) printf '不可用（缺少 crontab，且当前环境不能使用 macOS launchd）' ;;
        invalid) printf '异常：cron block 无任务' ;;
        *) printf '未知' ;;
    esac
}

cron_status_summary() {
    local state interval config_paused job consistency summary
    IFS='|' read -r state interval config_paused job consistency < <(read_cron_status_snapshot)
    case "${state}" in
        running|paused)
            summary="$(cron_state_label "${state}")"
            [[ -n "${interval}" ]] && summary="${summary}，${interval}"
            [[ "${consistency}" == "drift" ]] && summary="${summary}（与配置暂停标记不一致）"
            printf '%s' "${summary}"
            ;;
        *)
            cron_state_label "${state}"
            ;;
    esac
}

show_cron_status() {
    local state interval config_paused job consistency
    IFS='|' read -r state interval config_paused job consistency < <(read_cron_status_snapshot)
    print_panel_section "Self-report 定时上报"
    print_panel_row "配置文件" "${CONFIG_FILE}"
    print_panel_row "保存状态" "$([[ -f "${CONFIG_FILE}" ]] && printf '已保存' || printf '未保存')"
    print_panel_row "配置暂停标记" "$(schedule_paused && printf '已暂停（手动立即上报仍可用）' || printf '未暂停')"
    print_panel_row "实际状态" "$(cron_state_label "${state}")"
    if [[ -n "${interval}" ]]; then
        print_panel_row "计划间隔" "${interval}"
    elif [[ "${state}" == "running" || "${state}" == "paused" ]]; then
        print_panel_row "计划间隔" "已安装，未识别间隔"
    fi
    if [[ "${consistency}" == "drift" ]]; then
        print_panel_row "一致性" "不一致，执行安装 / 更新定时上报可刷新"
    elif [[ "${state}" == "running" || "${state}" == "paused" ]]; then
        print_panel_row "一致性" "一致"
    fi
    [[ -n "${job}" ]] && print_panel_row "当前命令" "${job}"
    show_recent_self_report_log
}

set_schedule_paused() {
    local value="$1" had_schedule=0 previous_paused="${SCHEDULE_PAUSED}"
    if cron_managed_block_exists; then
        had_schedule=1
    elif launchd_supported && [[ -f "$(launchd_plist_path)" ]]; then
        had_schedule=1
    fi
    SCHEDULE_PAUSED="${value}"
    save_config_file || return 1
    if [[ "${had_schedule}" == "1" ]]; then
        if ! install_cron; then
            SCHEDULE_PAUSED="${previous_paused}"
            save_config_file >/dev/null 2>&1 || true
            self_report_incomplete "定时上报暂停状态未同步，已尝试恢复配置标记。"
            return 1
        fi
    fi
    if schedule_paused; then
        if [[ "${had_schedule}" == "1" ]]; then
            self_report_completed "定时上报已暂停；手动立即上报仍可用。"
        else
            self_report_completed "已记录暂停标记；当前未安装定时上报，安装后会按此状态写入。"
        fi
    else
        if [[ "${had_schedule}" == "1" ]]; then
            self_report_completed "定时上报已恢复。"
        else
            self_report_completed "已记录恢复标记；当前未安装定时上报，安装后会按此状态写入。"
        fi
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
    local ip response curl_rc report_source report_identity curl_args=() http_code
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
    report_source="$(normalize_report_token "${SOURCE_ID}" "$(default_source_id)")"
    report_identity="$(normalize_report_token "${IDENTITY}" "${report_source}")"
    echo "上报当前公网出口 IPv4 ${ip} 到 LAN Worker：${WORKER_URL}"
    curl_args=(-sS --get --connect-timeout 10 --max-time 30)
    if [[ -n "${SECRET}" ]]; then
        curl_args+=(-H "X-PO0-Token: ${SECRET}")
    fi
    curl_args+=(--data-urlencode "source=${report_source}")
    curl_args+=(--data-urlencode "ip=${ip}")
    curl_args+=(--data-urlencode "identity=${report_identity}")
    curl_args+=(-w $'\n%{http_code}')
    curl_args+=("${WORKER_URL}")
    if response="$(curl "${curl_args[@]}")"; then
        http_code="${response##*$'\n'}"
        response="${response%$'\n'*}"
        if [[ "${http_code}" == 2* ]]; then
            [[ -n "${response}" ]] && printf '%s\n' "${response}"
            self_report_completed "公网出口 IPv4 ${ip} 已被 LAN Worker 接收。"
        else
            [[ -n "${response}" ]] && printf '%s\n' "${response}" >&2
            self_report_incomplete "LAN Worker 未确认本次上报（HTTP ${http_code}）。"
            return 1
        fi
    else
        curl_rc=$?
        [[ -n "${response}" ]] && printf '%s\n' "${response}" >&2
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
    print_panel_row "上报间隔" "$(cron_minutes_to_seconds "${CRON_MINUTES}") 秒（安装定时上报时使用）"
    print_panel_row "定时暂停" "$(schedule_paused && printf '已暂停' || printf '未暂停')"
    print_panel_row "放行 TTL" "由 LAN Worker Self-report 目标控制，默认 43200 秒"
    if [[ -n "${IP_CHECK_URLS}" ]]; then
        print_panel_row "IP 探测列表" "${IP_CHECK_URLS}"
    else
        print_panel_row "首选 IP 探测" "${IP_CHECK_URL}"
    fi
}

show_menu_dashboard() {
    print_title "PO0 Self-report Client"
    print_panel_section "脚本信息"
    print_panel_row "脚本名称" "${SCRIPT_NAME}"
    print_panel_row "版本" "${SCRIPT_VERSION}"
    print_panel_row "构建标识" "$(script_build_label)"
    print_panel_row "发布日期" "${SCRIPT_RELEASE_DATE}"
    print_panel_row "执行来源" "$(current_script_path)"
    print_panel_row "默认安装路径" "$(default_install_path)"
    print_panel_row "下载 URL" "${DOWNLOAD_URL}"

    print_panel_section "当前状态"
    print_panel_row "配置文件" "${CONFIG_FILE}"
    print_panel_row "保存状态" "$([[ -f "${CONFIG_FILE}" ]] && printf '已保存' || printf '未保存')"
    print_panel_row "LAN Worker URL" "${WORKER_URL:-未设置}"
    print_panel_row "Source ID" "${SOURCE_ID:-未设置}"
    print_panel_row "Identity" "${IDENTITY:-未设置}"
    print_panel_row "定时上报" "$(cron_status_summary)"
    print_panel_row "上报间隔" "$(cron_minutes_to_seconds "${CRON_MINUTES}") 秒（安装定时上报时使用）"
}

configure_interactive() {
    local secret_input cron_seconds
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
    SOURCE_ID="$(prompt_default "Source ID" "${SOURCE_ID:-$(default_source_id)}")"
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
    cron_seconds="$(prompt_default "客户端每几秒上报一次（60-$(max_interval_seconds)；必须是 60 的倍数）" "$(cron_minutes_to_seconds "${CRON_MINUTES}")")"
    CRON_MINUTES="$(normalize_interval_seconds_to_minutes "${cron_seconds}" "${MAX_CRON_MINUTES}")" || {
        printf '上报间隔秒数无效：请输入 60-%s 且为 60 倍数的整数。\n' "$(max_interval_seconds)" >&2
        return 1
    }
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
    local cron_seconds
    if ! config_complete; then
        configure_interactive || return 1
    else
        cron_seconds="$(prompt_default "定时上报每几秒执行一次（60-$(max_interval_seconds)；必须是 60 的倍数）" "$(cron_minutes_to_seconds "${CRON_MINUTES}")")"
        CRON_MINUTES="$(normalize_interval_seconds_to_minutes "${cron_seconds}" "${MAX_CRON_MINUTES}")" || {
            printf '上报间隔秒数无效：请输入 60-%s 且为 60 倍数的整数。\n' "$(max_interval_seconds)" >&2
            return 1
        }
    fi
    install_cron
}

menu_loop() {
    local choice rc
    while true; do
        menu_clear_screen
        show_menu_dashboard
        print_menu_section "手动上报"
        print_menu_pair 1 "配置并保存上报参数" 2 "立即上报一次"
        print_menu_section "定时上报"
        print_menu_pair 3 "安装 / 更新定时上报" 4 "暂停 / 恢复定时上报"
        print_menu_pair 5 "查看定时上报状态" 6 "删除定时上报"
        print_menu_section "查看"
        print_menu_item 7 "显示当前配置"
        print_menu_section "维护"
        print_menu_pair 8 "从 GitHub 更新脚本" 9 "卸载本客户端"
        print_menu_section "退出"
        print_menu_item 0 "退出"
        print_menu_footer
        choice="$(read_prompt "请选择操作 [0-9]: ")" || return 0
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
            8) upgrade_self_from_download --reopen-menu || pause_before_return ;;
            9)
                uninstall_self_report_interactive
                rc=$?
                pause_before_return
                [[ "${rc}" == "0" ]] && return 0
                ;;
            0) return 0 ;;
            "") ;;
            *) printf '无效选择。\n' >&2; pause_before_return ;;
        esac
    done
}

usage() {
    printf '%s\n' \
        "PO0 自上报客户端（macOS）" \
        "" \
        "本脚本探测当前设备的公网出口 IPv4，并上报到 LAN Worker 的 self-report" \
        "接收服务。访问设备不直接连接 PO0。Self-report 放行 TTL 由 LAN Worker" \
        "接收端配置，不由客户端决定。" \
        "" \
        "用法:" \
        "  curl -fsSL ${DOWNLOAD_URL} | bash" \
        "  bash po0-outbound-ip-report-macos.sh --menu" \
        "  bash po0-outbound-ip-report-macos.sh --version" \
        "  bash po0-outbound-ip-report-macos.sh --upgrade-self" \
        "  curl -fsSL ${DOWNLOAD_URL} | bash -s -- --save-config --menu" \
        "  bash po0-outbound-ip-report-macos.sh --worker-url https://report.example.com/report --secret SECRET --save-config" \
        "  curl -fsSL ${DOWNLOAD_URL} | bash -s -- --worker-url https://report.example.com/report --secret SECRET --interval-seconds 3600 --install-launchd" \
        "" \
        "参数:" \
        "  --menu                打开交互菜单。" \
        "  --version             显示脚本版本、发布日期、当前路径和默认安装路径。" \
        "  --changelog           显示当前版本更新内容。" \
        "  --upgrade-self        从 GitHub Release 下载并更新本机脚本；菜单内更新会自动重开新版菜单。" \
        "  --config PATH         self-report 本地配置文件；默认 root 用 /etc/po0-self-report/settings.env，普通用户用 ~/.config/po0-self-report/settings.env。" \
        "  --save-config         保存当前参数到本地配置文件；可与 --menu 组合为首次保存后打开菜单。" \
        "  --worker-url URL      LAN Worker self-report HTTPS 接收地址，例如 https://report.example.com/report；裸域名会自动补全。" \
        "  --allow-http          允许 http:// 上报；仅用于本地调试或临时旧环境。" \
        "  --source-id ID        写入 PO0 client_ip 记录的来源 ID；默认由 hostname + machine-id/MAC 生成: ${SOURCE_ID}" \
        "  --identity ID         LAN Worker/PO0 日志里的设备或用户标签；默认使用设备名: ${IDENTITY}" \
        "  --secret SECRET       可选的 LAN Worker self-report 共享密钥。" \
        "  --ip-check-url URL    第一个公网 IPv4 探测地址。默认: ${IP_CHECK_URL}" \
        "  --ip-check-urls CSV   覆盖完整探测地址列表，多个 URL 用逗号分隔。" \
        "  --install-launchd [N] 安装 / 更新 macOS launchd 定时上报；不带 N 时默认 3600 秒。" \
        "  --install-cron [N]    兼容旧参数，等同 --install-launchd；N 为兼容分钟参数。" \
        "  --pause-schedule      暂停本脚本管理的定时上报；手动立即上报仍可用。" \
        "  --resume-schedule     恢复本脚本管理的定时上报。" \
        "  --schedule-status     查看本脚本管理的定时上报状态。" \
        "  --interval-seconds N  设置 launchd 上报间隔秒数，必须是 60 的倍数，默认 3600。" \
        "  --minutes N           兼容旧参数：设置定时上报间隔分钟数，范围 1-${MAX_CRON_MINUTES}。" \
        "" \
        "默认公网 IPv4 探测顺序:" \
        "  https://ip9.com.cn/get" \
        "  https://mail.163.com/fgw/mailsrv-ipdetail/detail" \
        "  https://api.live.bilibili.com/client/v1/Ip/getInfoNew" \
        "  https://ipservice.ws.126.net/locate/api/getLocByIp" \
        "  https://r.inews.qq.com/api/ip2city?otype=json" \
        "  https://data.video.iqiyi.com/v.f4v" \
        "  https://ip.apps.cntv.cn/whereis?client=json" \
        "  https://myip.ipip.net/json"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --menu)
                SHOW_MENU="1"
                shift
                ;;
            --version)
                SHOW_VERSION="1"
                shift
                ;;
            --changelog)
                SHOW_CHANGELOG="1"
                shift
                ;;
            --upgrade-self)
                UPGRADE_SELF="1"
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
                SOURCE_ID_EXPLICIT="1"
                shift 2
                ;;
            --identity)
                IDENTITY="${2:-}"
                IDENTITY_EXPLICIT="1"
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
                INTERVAL_SECONDS=""
                shift 2
                ;;
            --interval-seconds)
                INTERVAL_SECONDS="${2:-}"
                shift 2
                ;;
            --install-cron|--install-launchd)
                INSTALL_CRON="1"
                if [[ "${2:-}" =~ ^[0-9]+$ ]]; then
                    CRON_MINUTES="${2:-}"
                    INTERVAL_SECONDS=""
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
apply_device_defaults
parse_args "$@"
if [[ "${SHOW_VERSION}" != "1" && "${SHOW_CHANGELOG}" != "1" && "${UPGRADE_SELF}" != "1" ]]; then
    apply_interval_seconds_override || exit 1
fi
apply_device_defaults
CONFIG_FILE="$(default_config_file)"

if [[ "${SHOW_VERSION}" == "1" ]]; then
    show_version
elif [[ "${SHOW_CHANGELOG}" == "1" ]]; then
    show_changelog
elif [[ "${UPGRADE_SELF}" == "1" ]]; then
    upgrade_self_from_download
elif [[ "${SAVE_CONFIG}" == "1" && "${SHOW_MENU}" == "1" ]]; then
    save_config_file || exit 1
    menu_loop
elif [[ "${SAVE_CONFIG}" == "1" ]]; then
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
