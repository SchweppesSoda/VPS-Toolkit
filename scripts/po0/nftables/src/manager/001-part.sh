#!/usr/bin/env bash
set -uo pipefail

SCRIPT_NAME="po0-nftables-relay-manager"
SCRIPT_VERSION="2026.06.24+build.1"
SCRIPT_RELEASE_DATE="2026-06-24"
# CHANGELOG_BEGIN
# - PO0 可部署脚本默认下载源迁到 GitHub Release asset，并保留环境变量覆盖入口。
# - LAN Worker、Self-report 部署命令改用 Release 下载地址；Egern 模块 raw 地址暂作为兼容白名单保留。
# CHANGELOG_END
CONF_DIR="${PO0_CONF_DIR:-/etc/nftables.d}"
MAIN_CONF="/etc/nftables.conf"
NFT_CONF="${CONF_DIR}/po0-relay.conf"
SETTINGS_FILE="${CONF_DIR}/po0-relay.env"
RULES_FILE="${CONF_DIR}/po0-relay.rules"
BACKUP_DIR="${CONF_DIR}/backups"
EXPORT_DIR="${BACKUP_DIR}/exports"
SYSCTL_CONF="/etc/sysctl.d/99-po0-relay.conf"
IPLIST_DIR="${CONF_DIR}/po0-iplist"
IPLIST_DOC="${IPLIST_DIR}/docs/cncity.md"
IPLIST_MANIFEST="${IPLIST_DIR}/manifest.tsv"
SRC_ALLOWLIST_CACHE="${CONF_DIR}/po0-relay-src-allowlist.txt"
CUSTOM_SRC_ALLOWLIST_FILE="${CONF_DIR}/po0-relay-custom-src-allowlist.txt"
ALLOWLIST_SETS_FILE="${CONF_DIR}/po0-relay-allowlist-sets.tsv"
ALLOWLIST_ENTRIES_FILE="${CONF_DIR}/po0-relay-allowlist-entries.tsv"
ALLOWLIST_SOURCES_FILE="${CONF_DIR}/po0-relay-allowlist-sources.tsv"
DDNS_REPORT_TOKEN_FILE="${CONF_DIR}/po0-relay-ddns-report.token"
DDNS_REPORT_STATS_FILE="${CONF_DIR}/po0-relay-ddns-report-stats.tsv"
CLIENT_IP_REPORT_TOKEN_FILE="${CONF_DIR}/po0-relay-client-ip-report.token"
CLIENT_IP_REPORT_STATS_FILE="${CONF_DIR}/po0-relay-client-ip-report-stats.tsv"
SSH_REPORT_TOKEN_FILE="${CONF_DIR}/po0-relay-ssh-report.token"
SSH_REPORT_STATS_FILE="${CONF_DIR}/po0-relay-ssh-report-stats.tsv"
WEBAUTH_REPORT_TOKEN_FILE="${CONF_DIR}/po0-relay-webauth-report.token"
WEBAUTH_REPORT_STATS_FILE="${CONF_DIR}/po0-relay-webauth-report-stats.tsv"
AUTO_PENDING_FILE="${CONF_DIR}/po0-relay-auto-pending.tsv"
RESOURCE_TASKS_FILE="${CONF_DIR}/po0-relay-resource-tasks.tsv"
RESOURCE_TASK_TOKEN_FILE="${CONF_DIR}/po0-relay-resource-task.token"
RESOURCE_INBOX_DIR="${CONF_DIR}/po0-relay-resource-inbox"
RESOURCE_TASK_LOCK_FILE="${CONF_DIR}/po0-relay-resource-tasks.lock"
DYNAMIC_STATE_LOCK_FILE="${CONF_DIR}/po0-relay-dynamic-state.lock"
RESOURCE_TASK_HISTORY_LIMIT=500
DYNAMIC_ALLOWLIST_MAX_PER_SOURCE="${PO0_DYNAMIC_ALLOWLIST_MAX_PER_SOURCE:-12}"
SSH_REPORT_ALLOWLIST_MAX_PER_SOURCE="${PO0_SSH_REPORT_ALLOWLIST_MAX_PER_SOURCE:-12}"
ALLOWLIST_PROFILE_DIR="${CONF_DIR}/po0-relay-allowlist-profiles"
ALLOWLIST_LAST_PROFILE_NAME="_last"
ALLOWLIST_PROFILE_MAX_COUNT=10
LEARN_LOG_FILE="${CONF_DIR}/po0-relay-learn.tsv"
LEARN_SUMMARY_FILE="${CONF_DIR}/po0-relay-learn-summary.tsv"
LEARN_DAILY_IP_FILE="${CONF_DIR}/po0-relay-learn-daily-ip.tsv"
BLOCK_LOG_FILE="${CONF_DIR}/po0-relay-blocked.tsv"
BLOCK_SUMMARY_FILE="${CONF_DIR}/po0-relay-blocked-summary.tsv"
LEARN_SERVICE_NAME="nftables-relay-learn.service"
LEARN_SERVICE_FILE="/etc/systemd/system/${LEARN_SERVICE_NAME}"
LEARN_RUNNER="/usr/local/sbin/nftables-relay-learn"
LEARN_LOG_MAX_BYTES=52428800
LEARN_LOG_KEEP_LINES=500000
BLOCK_LOG_MAX_BYTES=10485760
BLOCK_LOG_KEEP_LINES=100000
LEARN_COMPACT_CHECK_INTERVAL=100000
LEARN_IP_MIN_HITS=3
LEARN_IP_MIN_SPAN_SECONDS=600
LEARN_NET24_MIN_HITS=3
LEARN_NET24_MIN_UNIQUE_IPS=2
LEARN_NET16_MIN_HITS=3
LEARN_NET16_MIN_UNIQUE_24S=2
IPDB_FILE="${CONF_DIR}/qqwry.ipdb"
IPDB_LANGUAGE="CN"
IPDB_VENV_DIR="${CONF_DIR}/po0-ipdb-venv"
IPDB_VENV_PYTHON="${IPDB_VENV_DIR}/bin/python"
IPDB_DEFAULT_PIP_INDEX_URL="https://mirrors.cloud.tencent.com/pypi/simple"
IPDB_PIP_INDEX_URL=""
IPDB_DOWNLOAD_URL="https://raw.githubusercontent.com/nmgliangwei/qqwry.ipdb/main/qqwry.ipdb"
MANAGER_INSTALL_PATH="${PO0_MANAGER_INSTALL_PATH:-/root/nftables-relay-manager.sh}"
PO0_RELEASE_DOWNLOAD_BASE_URL="${PO0_RELEASE_DOWNLOAD_BASE_URL:-https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download}"
MANAGER_DOWNLOAD_URL="${PO0_MANAGER_DOWNLOAD_URL:-${PO0_RELEASE_DOWNLOAD_BASE_URL}/nftables-relay-manager.sh}"
LAN_WORKER_DOWNLOAD_URL="${PO0_LAN_CLIENT_DOWNLOAD_URL:-${PO0_RELEASE_DOWNLOAD_BASE_URL}/po0-lan-client.sh}"
OUTBOUND_IP_REPORTER_DOWNLOAD_URL="${PO0_SELF_REPORT_DOWNLOAD_URL:-${PO0_RELEASE_DOWNLOAD_BASE_URL}/po0-outbound-ip-report.sh}"
OUTBOUND_IP_REPORTER_PS_DOWNLOAD_URL="${PO0_SELF_REPORT_PS_DOWNLOAD_URL:-${PO0_RELEASE_DOWNLOAD_BASE_URL}/po0-outbound-ip-report.ps1}"
EGERN_SSH_REPORT_MODULE_RAW_URL="https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/egern/PO0-SSH-IP-Report.yaml"
REPORT_KEY_WRAPPER_PATH="${CONF_DIR}/po0-report-key-wrapper"
REPORT_KEY_DENY_LOG="${CONF_DIR}/po0-report-key-denied.log"

NAT_TABLE="po0_relay_nat"
MANGLE_TABLE="po0_relay_mangle"
BLOCKED_LISTEN_PORTS="22 80 443 8080 8443 8000 1080"
FORWARD_PORT_MIN="24576"
FORWARD_PORT_MAX="49151"
FORWARD_PORT_RANDOM_TRIES="200"

RELAY_MODE="mixed"
NODE_NAME=""
RELAY_LAN_IP=""
ENABLE_MSS_CLAMP="1"
MSS_VALUE="1452"
MANAGE_INPUT_FIREWALL="1"
SSH_PORTS=""
ENABLE_SRC_ALLOWLIST="0"
SRC_ALLOWLIST_MODE="trusted_dynamic"
SRC_ALLOWLIST_REGION_IDS=""
AUTOMATION_MODE="regular"
MANAGER_UPDATE_URL=""
declare -a RULES=()
declare -a IMPORTED_RULES=()
declare -a DISCOVERED_RULES=()
declare -a ALLOWLIST_SETS=()

C_RESET=""
C_BOLD=""
C_DIM=""
C_GREEN=""
C_YELLOW=""
C_RED=""
C_CYAN=""
C_PANEL=""

RULE_ID=""
RULE_NAME=""
RULE_PROTO=""
RULE_LPORT=""
RULE_DIP=""
RULE_DPORT=""
RULE_ENABLED=""
RULE_SNAT_MODE=""
PARSED_RULE=""
RULE_TOTAL=0
RULE_ENABLED_COUNT=0
RULE_DISABLED_COUNT=0
TEMPLATE_OUTPUT_PATH=""
SELECTED_REGION_ID=""
RELAY_LAN_IP_SOURCE="none"
RULES_SOURCE="none"
DISCOVERED_RULES_SOURCE="none"
PUBLIC_IP=""
PUBLIC_IP_SOURCE="none"
PUBLIC_IP_CACHE=""
PUBLIC_IP_CACHE_SOURCE="none"
PUBLIC_IP_PROBE_DONE="0"
CUSTOM_ALLOWLIST_CIDR=""
CUSTOM_ALLOWLIST_NOTE=""
SELECTED_LEARN_CIDR=""
SELECTED_LEARN_NOTE=""
SELECTED_ALLOWLIST_PROFILE=""
ALLOWLIST_SET_ID=""
ALLOWLIST_SET_LABEL=""
ALLOWLIST_SET_ENABLED=""
ALLOWLIST_SET_SCOPE=""
ALLOWLIST_SET_PORTS=""
ALLOWLIST_SET_SOURCES=""
ALLOWLIST_SET_NOTE=""
PARSED_ALLOWLIST_SET=""
ALLOWLIST_ENTRY_SET_ID=""
ALLOWLIST_ENTRY_CIDR=""
ALLOWLIST_ENTRY_SOURCE_TYPE=""
ALLOWLIST_ENTRY_SOURCE_VALUE=""
ALLOWLIST_ENTRY_NOTE=""
ALLOWLIST_ENTRY_CREATED_AT=""
ALLOWLIST_ENTRY_EXPIRES_AT=""
PARSED_ALLOWLIST_ENTRY=""
ALLOWLIST_SOURCE_SET_ID=""
ALLOWLIST_SOURCE_TYPE=""
ALLOWLIST_SOURCE_NAME=""
ALLOWLIST_SOURCE_VALUE=""
ALLOWLIST_SOURCE_ENABLED=""
ALLOWLIST_SOURCE_TTL_SECONDS=""
ALLOWLIST_SOURCE_LAST_RESOLVED_AT=""
ALLOWLIST_SOURCE_LAST_RESULT=""
PARSED_ALLOWLIST_SOURCE=""
CLIENT_IP_REPORT_SOURCE=""
CLIENT_IP_REPORT_IP=""
CLIENT_IP_REPORT_IDENTITY=""
CLIENT_IP_REPORT_TTL=""
SSH_REPORT_SOURCE=""
SSH_REPORT_IP=""
SSH_REPORT_IDENTITY=""
SSH_REPORT_TTL=""
WEBAUTH_REPORT_SOURCE=""
WEBAUTH_REPORT_IP=""
WEBAUTH_REPORT_IDENTITY=""
WEBAUTH_REPORT_EXPIRES_AT=""
REPORT_STAT_ACCEPTED="0"
REPORT_STAT_REJECTED="0"
REPORT_STAT_LAST_STATUS=""
REPORT_STAT_LAST_AT=""
REPORT_STAT_LAST_IPS=""
REPORT_STAT_LAST_ERROR=""
PROFILE_ENABLE_SRC_ALLOWLIST=""
PROFILE_SRC_ALLOWLIST_MODE=""
PROFILE_SRC_ALLOWLIST_REGION_IDS=""
PROFILE_SAVED_AT=""
PROFILE_LABEL=""
LEARN_RULES_RELOAD_TS=0
LEARN_APPEND_COUNT=0
LEARN_LAST_COMPACT_DAY=""
declare -A IPDB_LOOKUP_CACHE=()
SETTINGS_CACHE_READY="0"
RULES_CACHE_READY="0"
ALLOWLIST_SETS_CACHE_READY="0"
DISCOVERY_CACHE_READY="0"
DISCOVERED_RULE_COUNT=0
declare -a TEMP_FILES=()
TEMP_FILE_RESULT=""
declare -a TEMP_DIRS=()
TEMP_DIR_RESULT=""


setup_colors() {
    if [[ -t 1 ]]; then
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

info() { printf '%b[信息]%b %s\n' "${C_GREEN}" "${C_RESET}" "$1"; }
warn() { printf '%b[警告]%b %s\n' "${C_YELLOW}" "${C_RESET}" "$1"; }
err() { printf '%b[错误]%b %s\n' "${C_RED}" "${C_RESET}" "$1" >&2; }
success() { printf '%b[完成]%b %s\n' "${C_GREEN}" "${C_RESET}" "$1"; }

cleanup_temp_files() {
    local tmp
    for tmp in "${TEMP_FILES[@]}"; do
        [[ -e "${tmp}" ]] && rm -f -- "${tmp}" 2>/dev/null || true
    done
    for tmp in "${TEMP_DIRS[@]}"; do
        [[ -d "${tmp}" ]] && rm -rf -- "${tmp}" 2>/dev/null || true
    done
}

trap cleanup_temp_files EXIT
trap 'cleanup_temp_files; exit 130' INT
trap 'cleanup_temp_files; exit 143' TERM

make_temp_file() {
    local target="$1"
    local dir base tmp
    dir="$(dirname "${target}")"
    base="$(basename "${target}")"
    tmp="$(mktemp "${dir}/${base}.tmp.XXXXXX")" || return 1
    TEMP_FILES+=("${tmp}")
    TEMP_FILE_RESULT="${tmp}"
}

make_temp_dir() {
    local parent="$1"
    local prefix="$2"
    local tmp
    mkdir -p "${parent}" || return 1
    tmp="$(mktemp -d "${parent}/${prefix}.XXXXXX")" || return 1
    TEMP_DIRS+=("${tmp}")
    TEMP_DIR_RESULT="${tmp}"
}

dynamic_state_lock() {
    [[ "${DYNAMIC_STATE_LOCK_HELD:-0}" == "1" ]] && return 0
    mkdir -p "${CONF_DIR}" || return 1
    exec 8>"${DYNAMIC_STATE_LOCK_FILE}" || return 1
    if command -v flock >/dev/null 2>&1; then
        flock -w 15 8 || {
            err "动态来源状态文件正忙，请稍后重试。"
            exec 8>&- 2>/dev/null || true
            return 1
        }
    fi
    DYNAMIC_STATE_LOCK_HELD=1
}

dynamic_state_unlock() {
    [[ "${DYNAMIC_STATE_LOCK_HELD:-0}" == "1" ]] || return 0
    if command -v flock >/dev/null 2>&1; then
        flock -u 8 2>/dev/null || true
    fi
    exec 8>&- 2>/dev/null || true
    DYNAMIC_STATE_LOCK_HELD=0
}

with_dynamic_state_lock() {
    local rc
    if [[ "${DYNAMIC_STATE_LOCK_HELD:-0}" == "1" ]]; then
        "$@"
        return $?
    fi
    dynamic_state_lock || return 1
    "$@"
    rc=$?
    dynamic_state_unlock
    return "${rc}"
}

print_divider() {
    printf '%b%s%b\n' "${C_DIM}" "================================================================" "${C_RESET}"
}

print_title() {
    echo ""
    print_divider
    printf '%b%s%b\n' "${C_BOLD}${C_CYAN}" "$1" "${C_RESET}"
    print_divider
}

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

print_panel_action() {
    print_panel_row "$@"
}

menu_clear_screen() {
    [[ "${MENU_CLEAR:-1}" == "0" ]] && return 0
    [[ -t 1 && -n "${TERM:-}" && "${TERM}" != "dumb" ]] || return 0
    command -v clear >/dev/null 2>&1 && clear || printf '\033[H\033[2J'
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

read_menu_choice() {
    local prompt="$1"
    local choice
    choice="$(read_prompt "${prompt}")" || return 1
    printf '%s\n' "$(trim "${choice}")"
}

read_menu_choice_or_return() {
    local __target="$1"
    local prompt="$2"
    local __choice_value
    if ! __choice_value="$(read_menu_choice "${prompt}")"; then
        printf '\n输入结束，退出当前菜单。\n'
        return 1
    fi
    printf -v "${__target}" '%s' "${__choice_value}"
}

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "${value}"
}

validate_node_name() {
    local value="$1"
    [[ -z "${value}" ]] && return 0
    [[ ${#value} -le 32 ]] || return 1
    [[ "${value}" =~ ^[A-Za-z0-9._-]+$ ]]
}

export_rules_default_path() {
    local prefix=""
    validate_node_name "${NODE_NAME}" || NODE_NAME=""
    [[ -n "${NODE_NAME}" ]] && prefix="${NODE_NAME}-"
    printf '%s/%spo0-relay-export-%s.txt\n' "${EXPORT_DIR}" "${prefix}" "$(date '+%Y%m%d_%H%M%S')"
}

check_root() {
    if [[ ${EUID} -ne 0 ]]; then
        err "请使用 root 运行此脚本。"
        exit 1
    fi
}

confirm_yes() {
    local ans
    ans="$(read_prompt "$1 [y/N]: ")" || return 1
    [[ "${ans}" =~ ^[Yy]$ ]]
}

confirm_strong_yes() {
    local ans
    ans="$(read_prompt "$1（输入 YES 确认）: ")" || return 1
    [[ "${ans}" == "YES" ]]
}

prompt_with_default() {
    local prompt="$1"
    local default="${2-}"
    local value
    if [[ -n "${default}" ]]; then
        value="$(read_prompt "${prompt} [当前: ${default}]: ")" || value=""
        printf '%s\n' "${value:-${default}}"
    else
        value="$(read_prompt "${prompt}: ")" || value=""
        printf '%s\n' "${value}"
    fi
}

pause_before_return() {
    echo ""
    read_prompt "按回车返回菜单..." >/dev/null || true
}

validate_port() {
    local port="$1"
    [[ "${port}" =~ ^[0-9]+$ ]] || return 1
    [[ ! "${port}" =~ ^0[0-9] ]] || return 1
    (( port >= 1 && port <= 65535 ))
}

normalize_port_list() {
    local raw="$1"
    local port
    local out=""
    local seen=" "
    for port in ${raw//,/ }; do
        port="$(trim "${port}")"
        validate_port "${port}" || continue
        [[ "${seen}" == *" ${port} "* ]] && continue
        seen+="${port} "
        if [[ -z "${out}" ]]; then
            out="${port}"
        else
            out+=" ${port}"
        fi
    done
    printf '%s\n' "${out}"
}

ports_to_nft_set() {
    local out=""
    local port
    for port in $1; do
        if [[ -z "${out}" ]]; then
            out="${port}"
        else
            out+=", ${port}"
        fi
    done
    printf '%s\n' "${out}"
}

is_blocked_listen_port() {
    local port="$1"
    local blocked
    for blocked in ${BLOCKED_LISTEN_PORTS}; do
        [[ "${port}" == "${blocked}" ]] && return 0
    done
    return 1
}

validate_listen_port_value() {
    local port="$1"
    validate_port "${port}" || return 1
    is_blocked_listen_port "${port}" && return 1
    return 0
}

listen_port_in_forward_range() {
    local port="$1"
    validate_port "${port}" || return 1
    (( port >= FORWARD_PORT_MIN && port <= FORWARD_PORT_MAX ))
}

local_port_in_use() {
    local port="$1"
    local proto="$2"
    command -v ss &>/dev/null || return 1

    if [[ "${proto}" == "both" || "${proto}" == "tcp" ]]; then
        ss -H -tln 2>/dev/null | awk '{ print $4 }' | grep -Eq "(^|[^0-9])${port}$" && return 0
    fi
    if [[ "${proto}" == "both" || "${proto}" == "udp" ]]; then
        ss -H -uln 2>/dev/null | awk '{ print $4 }' | grep -Eq "(^|[^0-9])${port}$" && return 0
    fi
    return 1
}

ensure_listen_port_allowed() {
    local port="$1"
    local proto="$2"
    validate_port "${port}" || {
        err "监听端口无效：${port}"
        return 1
    }
    if is_blocked_listen_port "${port}"; then
        err "监听端口 ${port} 属于保留服务端口，不允许作为转发入口。"
        return 1
    fi
    if local_port_in_use "${port}" "${proto}"; then
        err "监听端口 ${port} 已被本机其它服务占用，不允许作为转发入口。"
        return 1
    fi
    return 0
}

ensure_new_listen_port_allowed() {
    local port="$1"
    local proto="$2"
    ensure_listen_port_allowed "${port}" "${proto}" || return 1
    if ! listen_port_in_forward_range "${port}"; then
        err "监听端口必须在 ${FORWARD_PORT_MIN}-${FORWARD_PORT_MAX} 范围内。"
        return 1
    fi
    return 0
}

validate_ip() {
    local ip="$1"
    local IFS='.'
    local octet
    local -a octets=()
    [[ "${ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    [[ ! "${ip}" =~ (^|\.)0[0-9] ]] || return 1
    read -r -a octets <<< "${ip}"
    for octet in "${octets[@]}"; do
        (( octet >= 0 && octet <= 255 )) || return 1
    done
}

validate_host_ipv4() {
    local ip="$1"
    local o1 o2 o3 o4
    validate_ip "${ip}" || return 1
    IFS='.' read -r o1 o2 o3 o4 <<< "${ip}"
    (( o1 == 0 )) && return 1
    (( o1 == 127 )) && return 1
    (( o1 == 169 && o2 == 254 )) && return 1
    (( o1 >= 224 )) && return 1
    (( o1 == 255 && o2 == 255 && o3 == 255 && o4 == 255 )) && return 1
    return 0
}

validate_ipv4_cidr() {
    local cidr="$1"
    local ip prefix
    [[ "${cidr}" == */* ]] || return 1
    ip="${cidr%/*}"
    prefix="${cidr#*/}"
    validate_ip "${ip}" || return 1
    [[ "${prefix}" =~ ^[0-9]+$ ]] || return 1
    (( prefix >= 0 && prefix <= 32 ))
}

ipv4_to_int() {
    local ip="$1"
    local o1 o2 o3 o4
    validate_ip "${ip}" || return 1
    IFS='.' read -r o1 o2 o3 o4 <<< "${ip}"
    printf '%u\n' "$(( (o1 << 24) + (o2 << 16) + (o3 << 8) + o4 ))"
}

int_to_ipv4() {
    local value="$1"
    printf '%u.%u.%u.%u\n' \
        "$(( (value >> 24) & 255 ))" \
        "$(( (value >> 16) & 255 ))" \
        "$(( (value >> 8) & 255 ))" \
        "$(( value & 255 ))"
}
