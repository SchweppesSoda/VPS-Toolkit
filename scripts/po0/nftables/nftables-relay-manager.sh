#!/usr/bin/env bash
set -uo pipefail

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
RESOURCE_TASK_HISTORY_LIMIT=500
DYNAMIC_ALLOWLIST_MAX_PER_SOURCE="${PO0_DYNAMIC_ALLOWLIST_MAX_PER_SOURCE:-5}"
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
LAN_WORKER_RAW_URL="https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/tools/po0-lan-client.sh"
OUTBOUND_IP_REPORTER_RAW_URL="https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/tools/po0-outbound-ip-report.sh"
OUTBOUND_IP_REPORTER_PS_RAW_URL="https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/tools/po0-outbound-ip-report.ps1"
EGERN_SSH_REPORT_MODULE_RAW_URL="https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/egern/PO0-SSH-IP-Report.yaml"
REPORT_KEY_WRAPPER_PATH="${CONF_DIR}/po0-report-key-wrapper"

NAT_TABLE="po0_relay_nat"
MANGLE_TABLE="po0_relay_mangle"
BLOCKED_LISTEN_PORTS="22 80 443 8080 8443 8000 1080"
FORWARD_PORT_MIN="24576"
FORWARD_PORT_MAX="49151"
FORWARD_PORT_RANDOM_TRIES="200"

RELAY_MODE="mixed"
RELAY_LAN_IP=""
ENABLE_MSS_CLAMP="1"
MSS_VALUE="1452"
MANAGE_INPUT_FIREWALL="1"
SSH_PORTS=""
ENABLE_SRC_ALLOWLIST="0"
SRC_ALLOWLIST_MODE="trusted_dynamic"
SRC_ALLOWLIST_REGION_IDS=""
AUTOMATION_MODE="regular"
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
        C_CYAN=$'\033[36m'
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

print_divider() {
    printf '%s\n' "------------------------------------------------------------"
}

print_title() {
    echo ""
    print_divider
    printf '%b%s%b\n' "${C_BOLD}${C_CYAN}" "$1" "${C_RESET}"
    print_divider
}

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "${value}"
}

check_root() {
    if [[ ${EUID} -ne 0 ]]; then
        err "请使用 root 运行此脚本。"
        exit 1
    fi
}

confirm_yes() {
    local ans
    read -r -p "$1 [y/N]: " ans
    [[ "${ans}" =~ ^[Yy]$ ]]
}

confirm_strong_yes() {
    local ans
    read -r -p "$1（输入 YES 确认）: " ans
    [[ "${ans}" == "YES" ]]
}

prompt_with_default() {
    local prompt="$1"
    local default="${2-}"
    local value
    if [[ -n "${default}" ]]; then
        read -r -p "${prompt} [当前: ${default}]: " value
        printf '%s\n' "${value:-${default}}"
    else
        read -r -p "${prompt}: " value
        printf '%s\n' "${value}"
    fi
}

pause_before_return() {
    echo ""
    read -r -p "按回车返回主菜单..." _
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

normalize_ipv4_cidr_or_host() {
    local raw="$1"
    local ip prefix value mask network
    raw="$(trim "${raw}")"
    if validate_host_ipv4 "${raw}"; then
        printf '%s/32\n' "${raw}"
        return 0
    fi
    validate_ipv4_cidr "${raw}" || return 1
    ip="${raw%/*}"
    prefix="${raw#*/}"
    value="$(ipv4_to_int "${ip}")" || return 1
    if (( prefix == 0 )); then
        network=0
    else
        mask=$(( (0xffffffff << (32 - prefix)) & 0xffffffff ))
        network=$(( value & mask ))
    fi
    printf '%s/%s\n' "$(int_to_ipv4 "${network}")" "${prefix}"
}

cidr_prefix_length() {
    local cidr="$1"
    [[ "${cidr}" == */* ]] || return 1
    printf '%s\n' "${cidr#*/}"
}

validate_mss() {
    local value="$1"
    [[ "${value}" =~ ^[0-9]+$ ]] || return 1
    (( value >= 536 && value <= 65535 ))
}

is_private_ipv4() {
    local ip="$1"
    local o1 o2
    validate_ip "${ip}" || return 1
    IFS='.' read -r o1 o2 _ _ <<< "${ip}"
    (( o1 == 10 )) && return 0
    (( o1 == 192 && o2 == 168 )) && return 0
    (( o1 == 172 && o2 >= 16 && o2 <= 31 )) && return 0
    (( o1 == 100 && o2 >= 64 && o2 <= 127 )) && return 0
    return 1
}

is_public_ipv4() {
    local ip="$1"
    local o1 o2
    validate_ip "${ip}" || return 1
    is_private_ipv4 "${ip}" && return 1
    IFS='.' read -r o1 o2 _ _ <<< "${ip}"
    (( o1 == 0 )) && return 1
    (( o1 == 10 )) && return 1
    (( o1 == 127 )) && return 1
    (( o1 == 169 && o2 == 254 )) && return 1
    (( o1 == 198 && o2 >= 18 && o2 <= 19 )) && return 1
    (( o1 >= 224 )) && return 1
    return 0
}

extract_ipv4_from_cidr() {
    local cidr="$1"
    printf '%s\n' "${cidr%%/*}"
}

first_ipv4_from_ip_output() {
    local prefer_private="${1:-0}"
    local line cidr ip candidate=""
    while IFS= read -r line; do
        cidr="$(awk '{print $4}' <<< "${line}")"
        [[ -n "${cidr}" ]] || continue
        ip="$(extract_ipv4_from_cidr "${cidr}")"
        validate_ip "${ip}" || continue
        if [[ "${prefer_private}" == "1" ]]; then
            is_private_ipv4 "${ip}" && {
                printf '%s\n' "${ip}"
                return 0
            }
        elif [[ -z "${candidate}" ]]; then
            candidate="${ip}"
        fi
    done
    [[ -n "${candidate}" ]] && printf '%s\n' "${candidate}"
}

get_default_route_interface() {
    local iface
    iface="$(
        ip route show default 2>/dev/null | awk '
            {
                for (i = 1; i <= NF; i++) {
                    if ($i == "dev" && (i + 1) <= NF) {
                        print $(i + 1)
                        exit
                    }
                }
            }
        ' || true
    )"
    [[ -n "${iface}" ]] && printf '%s\n' "${iface}"
}

get_route_src_ipv4() {
    local target="${1:-1.1.1.1}"
    local src
    src="$(
        ip route get "${target}" 2>/dev/null | awk '
            {
                for (i = 1; i <= NF; i++) {
                    if ($i == "src" && (i + 1) <= NF) {
                        print $(i + 1)
                        exit
                    }
                }
            }
        ' || true
    )"
    validate_ip "${src}" && printf '%s\n' "${src}"
}

detect_relay_ip_from_nft_conf() {
    local value
    [[ -f "${NFT_CONF}" ]] || return 1
    value="$(
        awk '
            /^[[:space:]]*define[[:space:]]+RELAY_LAN_IP[[:space:]]*=/ {
                ip = $NF
                gsub(/[[:space:]]/, "", ip)
                print ip
                exit
            }
        ' "${NFT_CONF}" 2>/dev/null || true
    )"
    validate_ip "${value}" && printf '%s\n' "${value}"
}

detect_relay_ip_from_system() {
    local iface ip

    if command -v ip &>/dev/null; then
        iface="$(get_default_route_interface)"
        if [[ -n "${iface}" ]]; then
            ip="$(ip -4 -o addr show dev "${iface}" scope global up 2>/dev/null | first_ipv4_from_ip_output 1 || true)"
            validate_ip "${ip}" && {
                printf '%s\n' "${ip}"
                return 0
            }
        fi

        ip="$(ip -4 -o addr show scope global up 2>/dev/null | first_ipv4_from_ip_output 1 || true)"
        validate_ip "${ip}" && {
            printf '%s\n' "${ip}"
            return 0
        }

        if [[ -n "${iface}" ]]; then
            ip="$(ip -4 -o addr show dev "${iface}" scope global up 2>/dev/null | first_ipv4_from_ip_output 0 || true)"
            validate_ip "${ip}" && {
                printf '%s\n' "${ip}"
                return 0
            }
        fi

        ip="$(ip -4 -o addr show scope global up 2>/dev/null | first_ipv4_from_ip_output 0 || true)"
        validate_ip "${ip}" && {
            printf '%s\n' "${ip}"
            return 0
        }
    fi

    if command -v hostname &>/dev/null; then
        for ip in $(hostname -I 2>/dev/null); do
            validate_ip "${ip}" || continue
            if is_private_ipv4 "${ip}"; then
                printf '%s\n' "${ip}"
                return 0
            fi
        done
        for ip in $(hostname -I 2>/dev/null); do
            validate_ip "${ip}" && {
                printf '%s\n' "${ip}"
                return 0
            }
        done
    fi

    return 1
}

detect_public_ip_from_system() {
    local iface ip

    if command -v ip &>/dev/null; then
        ip="$(get_route_src_ipv4 "1.1.1.1" || true)"
        is_public_ipv4 "${ip}" && {
            printf '%s\n' "${ip}"
            return 0
        }

        iface="$(get_default_route_interface)"
        if [[ -n "${iface}" ]]; then
            ip="$(
                ip -4 -o addr show dev "${iface}" scope global up 2>/dev/null | awk '
                    {
                        split($4, a, "/")
                        print a[1]
                    }
                ' | while IFS= read -r value; do
                    [[ -n "${value}" ]] && printf '%s\n' "${value}"
                done | while IFS= read -r value; do
                    is_public_ipv4 "${value}" && {
                        printf '%s\n' "${value}"
                        break
                    }
                done
            )"
            is_public_ipv4 "${ip}" && {
                printf '%s\n' "${ip}"
                return 0
            }
        fi

        ip="$(
            ip -4 -o addr show scope global up 2>/dev/null | awk '
                {
                    split($4, a, "/")
                    print a[1]
                }
            ' | while IFS= read -r value; do
                [[ -n "${value}" ]] && printf '%s\n' "${value}"
            done | while IFS= read -r value; do
                is_public_ipv4 "${value}" && {
                    printf '%s\n' "${value}"
                    break
                }
            done
        )"
        is_public_ipv4 "${ip}" && {
            printf '%s\n' "${ip}"
            return 0
        }
    fi

    if command -v hostname &>/dev/null; then
        for ip in $(hostname -I 2>/dev/null); do
            is_public_ipv4 "${ip}" && {
                printf '%s\n' "${ip}"
                return 0
            }
        done
    fi

    return 1
}

extract_port_from_addr() {
    local addr="$1"
    addr="${addr##*:}"
    [[ "${addr}" =~ ^[0-9]+$ ]] && printf '%s\n' "${addr}"
}

detect_ssh_ports() {
    local ports=""
    local server_port line port

    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        read -r _ _ _ server_port _ <<< "${SSH_CONNECTION}"
        validate_port "${server_port}" && ports+=" ${server_port}"
    fi

    if command -v ss &>/dev/null; then
        while IFS= read -r line || [[ -n "${line}" ]]; do
            [[ "${line}" == *sshd* ]] || continue
            port="$(extract_port_from_addr "$(awk '{ print $4 }' <<< "${line}")")"
            validate_port "${port}" && ports+=" ${port}"
        done < <(ss -H -tlnp 2>/dev/null || true)

        if [[ -z "$(normalize_port_list "${ports}")" ]]; then
            local_port_in_use 22 tcp && ports+=" 22"
        fi
    fi

    if command -v sshd &>/dev/null; then
        while IFS= read -r port || [[ -n "${port}" ]]; do
            validate_port "${port}" && ports+=" ${port}"
        done < <(sshd -T 2>/dev/null | awk '$1 == "port" { print $2 }' || true)
    fi

    if [[ -f /etc/ssh/sshd_config ]]; then
        while IFS= read -r port || [[ -n "${port}" ]]; do
            validate_port "${port}" && ports+=" ${port}"
        done < <(awk 'tolower($1) == "port" && $0 !~ /^[[:space:]]*#/ { print $2 }' /etc/ssh/sshd_config 2>/dev/null || true)
    fi

    normalize_port_list "${ports}"
}

detect_ssh_client_ip() {
    local client_ip=""
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        read -r client_ip _ _ _ _ <<< "${SSH_CONNECTION}"
    fi
    is_public_ipv4 "${client_ip}" && printf '%s\n' "${client_ip}"
}

ensure_input_firewall_ready() {
    [[ "${MANAGE_INPUT_FIREWALL}" == "1" ]] || return 0
    SSH_PORTS="$(normalize_port_list "${SSH_PORTS}")"
    if [[ -z "${SSH_PORTS}" ]]; then
        SSH_PORTS="$(detect_ssh_ports || true)"
    fi
    SSH_PORTS="$(normalize_port_list "${SSH_PORTS}")"
    [[ -n "${SSH_PORTS}" ]] || {
        err "已启用托管入站防火墙，但无法探测 SSH 端口。请先在中转机参数里设置 SSH_PORTS。"
        return 1
    }
}

detect_public_ip_online() {
    local value=""
    local fetcher=""
    local py_bin=""
    local url
    local -a urls=(
        "https://api.ipify.org"
        "https://ipv4.icanhazip.com"
        "https://ifconfig.me/ip"
    )

    if command -v curl &>/dev/null; then
        fetcher="curl"
    elif command -v wget &>/dev/null; then
        fetcher="wget"
    fi

    if [[ -n "${fetcher}" ]]; then
        for url in "${urls[@]}"; do
            if [[ "${fetcher}" == "curl" ]]; then
                value="$(curl -4fsS --max-time 2 "${url}" 2>/dev/null | tr -d '[:space:]' || true)"
            else
                value="$(wget -4 -qO- --timeout=2 "${url}" 2>/dev/null | tr -d '[:space:]' || true)"
            fi
            is_public_ipv4 "${value}" && {
                printf '%s\n' "${value}"
                return 0
            }
        done
    fi

    if command -v dig &>/dev/null; then
        value="$(dig +short myip.opendns.com @resolver1.opendns.com A 2>/dev/null | awk 'NF { gsub(/"/, "", $0); print; exit }' || true)"
        is_public_ipv4 "${value}" && {
            printf '%s\n' "${value}"
            return 0
        }
        value="$(dig +short TXT o-o.myaddr.l.google.com @ns1.google.com 2>/dev/null | awk 'NF { gsub(/"/, "", $0); print; exit }' || true)"
        is_public_ipv4 "${value}" && {
            printf '%s\n' "${value}"
            return 0
        }
    fi

    if command -v nslookup &>/dev/null; then
        value="$(nslookup myip.opendns.com resolver1.opendns.com 2>/dev/null | awk '/^Address: / { print $2 }' | tail -n 1 | tr -d '[:space:]' || true)"
        is_public_ipv4 "${value}" && {
            printf '%s\n' "${value}"
            return 0
        }
    fi

    if command -v python3 &>/dev/null; then
        py_bin="python3"
    elif command -v python &>/dev/null; then
        py_bin="python"
    fi
    if [[ -n "${py_bin}" ]]; then
        value="$("${py_bin}" -c "import urllib.request; print(urllib.request.urlopen('https://api.ipify.org', timeout=2).read().decode().strip())" 2>/dev/null | tr -d '[:space:]' || true)"
        is_public_ipv4 "${value}" && {
            printf '%s\n' "${value}"
            return 0
        }
    fi

    return 1
}

relay_ip_source_label() {
    case "${RELAY_LAN_IP_SOURCE}" in
        settings)
            printf '已保存配置'
            ;;
        nft_conf)
            printf '从现有 relay 配置回读'
            ;;
        auto)
            printf '自动探测'
            ;;
        *)
            printf '未设置'
            ;;
    esac
}

rules_source_label() {
    local source_name="${1:-${RULES_SOURCE}}"
    case "${source_name}" in
        rules_file)
            printf '规则状态文件'
            ;;
        nft_conf)
            printf '现有 relay 配置回读'
            ;;
        live_table)
            printf '当前已加载 nftables 表'
            ;;
        ruleset)
            printf '完整 nft ruleset 扫描'
            ;;
        *)
            printf '未读取到规则'
            ;;
    esac
}

clear_discovery_cache() {
    DISCOVERED_RULES=()
    DISCOVERED_RULES_SOURCE="none"
    DISCOVERED_RULE_COUNT=0
    DISCOVERY_CACHE_READY="0"
}

join_with_comma() {
    local out=""
    local item
    for item in "$@"; do
        [[ -n "${item}" ]] || continue
        if [[ -z "${out}" ]]; then
            out="${item}"
        else
            out="${out}, ${item}"
        fi
    done
    printf '%s\n' "${out}"
}

normalize_region_ids() {
    local raw="$1"
    local id
    local out=""
    local seen=" "
    for id in ${raw//,/ }; do
        id="$(trim "${id}")"
        [[ -n "${id}" ]] || continue
        [[ "${id}" =~ ^[A-Za-z0-9._-]+$ ]] || continue
        [[ "${seen}" == *" ${id} "* ]] && continue
        seen+="${id} "
        if [[ -z "${out}" ]]; then
            out="${id}"
        else
            out+=" ${id}"
        fi
    done
    printf '%s\n' "${out}"
}

normalize_src_allowlist_mode() {
    local value
    value="$(trim "${1:-}")"
    value="${value,,}"
    case "${value}" in
        ""|trusted_dynamic|trusted-dynamic|dynamic|trusted|custom|manual|device|devices)
            printf 'trusted_dynamic\n'
            ;;
        manual_only|manual-only|manualonly|static|static_only|static-only)
            printf 'manual_only\n'
            ;;
        region_plus_trusted|region-plus-trusted|region_trusted|region+trusted|region_custom|custom_region|both|mixed|region+custom|custom+region)
            printf 'region_plus_trusted\n'
            ;;
        region_only|region-only|region|regions|iplist|geo)
            printf 'region_only\n'
            ;;
        custom_sources|custom-sources|sources|advanced)
            printf 'custom_sources\n'
            ;;
        *)
            return 1
            ;;
    esac
}

src_allowlist_mode_default_sources() {
    case "${1:-${SRC_ALLOWLIST_MODE}}" in
        manual_only)
            printf 'manual\n'
            ;;
        trusted_dynamic)
            printf 'manual,ddns,client_ip,ssh_report,webauth,learned\n'
            ;;
        region_plus_trusted)
            printf 'region,manual,ddns,client_ip,ssh_report,webauth,learned\n'
            ;;
        region_only)
            printf 'region\n'
            ;;
        custom_sources)
            load_allowlist_sets 2>/dev/null || true
            local set
            for set in "${ALLOWLIST_SETS[@]}"; do
                parse_allowlist_set_line "${set}" || continue
                if [[ "${ALLOWLIST_SET_ID}" == "default" ]]; then
                    printf '%s\n' "${ALLOWLIST_SET_SOURCES}"
                    return 0
                fi
            done
            printf 'manual,ddns,client_ip,ssh_report,webauth,learned\n'
            ;;
        *)
            printf 'manual,ddns,client_ip,ssh_report,webauth,learned\n'
            ;;
    esac
}

source_type_allowed_by_mode() {
    local source_type="$1"
    local mode="${2:-${SRC_ALLOWLIST_MODE}}"
    local sources source
    source_type="$(normalize_allowlist_entry_source_type "${source_type}")" || return 1
    sources="$(src_allowlist_mode_default_sources "${mode}")"
    for source in ${sources//,/ }; do
        [[ "${source}" == "${source_type}" ]] && return 0
    done
    return 1
}

sanitize_allowlist_set_text() {
    local value="$1"
    value="${value//$'\t'/ }"
    value="${value//$'\r'/ }"
    value="${value//$'\n'/ }"
    value="${value//|//}"
    value="$(trim "${value}")"
    [[ ${#value} -le 96 ]] || value="${value:0:96}"
    printf '%s\n' "${value}"
}

validate_allowlist_set_id() {
    local id="$1"
    [[ "${id}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$ ]]
}

normalize_allowlist_set_scope() {
    local value
    value="$(trim "${1:-}")"
    value="${value,,}"
    case "${value}" in
        ""|public|global|common|default|all)
            printf 'public\n'
            ;;
        ports|port|custom|per_port|per-port)
            printf 'ports\n'
            ;;
        *)
            return 1
            ;;
    esac
}

normalize_allowlist_set_ports() {
    local raw="${1:-}"
    local scope="${2:-ports}"
    local token proto port out="" seen=" "

    if [[ "${scope}" == "public" ]]; then
        printf '*\n'
        return 0
    fi

    raw="${raw//,/ }"
    raw="${raw//;/ }"
    for token in ${raw}; do
        token="$(trim "${token}")"
        [[ -n "${token}" ]] || continue
        if [[ "${token}" == */* ]]; then
            proto="${token%%/*}"
            port="${token#*/}"
        else
            proto="both"
            port="${token}"
        fi
        proto="$(normalize_proto "${proto}")" || return 1
        validate_port "${port}" || return 1
        token="${proto}/${port}"
        [[ "${seen}" == *" ${token} "* ]] && continue
        seen+="${token} "
        if [[ -z "${out}" ]]; then
            out="${token}"
        else
            out+=",${token}"
        fi
    done
    [[ -n "${out}" ]] || return 1
    printf '%s\n' "${out}"
}

normalize_allowlist_set_sources() {
    local raw="${1:-region,manual,learned}"
    local source normalized out="" seen=" "

    raw="${raw//,/ }"
    raw="${raw//;/ }"
    for source in ${raw}; do
        source="$(trim "${source}")"
        source="${source,,}"
        [[ -n "${source}" ]] || continue
        case "${source}" in
            region|regions|iplist|geo)
                normalized="region"
                ;;
            manual|custom|user)
                normalized="manual"
                ;;
            learned|learn|conntrack)
                normalized="learned"
                ;;
            ssh|ssh_temp|ssh-temp)
                normalized="ssh_temp"
                ;;
            ddns|domain)
                normalized="ddns"
                ;;
            client_ip|client-ip|mobile|device_ip|device-ip)
                normalized="client_ip"
                ;;
            ssh_report|ssh-report|ssh_ip|ssh-ip|egern|egern_ssh|egern-ssh)
                normalized="ssh_report"
                ;;
            webauth|web_auth|web-auth|cf_access|cf-access|cloudflare_access|cloudflare-access)
                normalized="webauth"
                ;;
            *)
                return 1
                ;;
        esac
        [[ "${seen}" == *" ${normalized} "* ]] && continue
        seen+="${normalized} "
        if [[ -z "${out}" ]]; then
            out="${normalized}"
        else
            out+=",${normalized}"
        fi
    done
    [[ -n "${out}" ]] || out="manual,ddns,client_ip,ssh_report,webauth,learned"
    printf '%s\n' "${out}"
}

default_allowlist_set_record() {
    serialize_allowlist_set \
        "default" \
        "Default public allowlist" \
        "1" \
        "public" \
        "*" \
        "manual,ddns,client_ip,ssh_report,webauth,learned" \
        "Legacy global source allowlist mapped to the public set"
}

serialize_allowlist_set() {
    local id="$1"
    local label="$2"
    local enabled="$3"
    local scope="$4"
    local ports="$5"
    local sources="$6"
    local note="${7:-}"
    printf '%s|%s|%s|%s|%s|%s|%s\n' \
        "${id}" "${label}" "${enabled}" "${scope}" "${ports}" "${sources}" "${note}"
}

parse_allowlist_set_line() {
    local line="$1"
    local id label enabled scope ports sources note
    local -a fields=()

    PARSED_ALLOWLIST_SET=""
    ALLOWLIST_SET_ID=""
    ALLOWLIST_SET_LABEL=""
    ALLOWLIST_SET_ENABLED=""
    ALLOWLIST_SET_SCOPE=""
    ALLOWLIST_SET_PORTS=""
    ALLOWLIST_SET_SOURCES=""
    ALLOWLIST_SET_NOTE=""

    line="${line%$'\r'}"
    line="$(trim "${line}")"
    [[ -n "${line}" && ! "${line}" =~ ^# ]] || return 1

    IFS='|' read -r -a fields <<< "${line}"
    [[ ${#fields[@]} -ge 6 ]] || return 1

    id="$(trim "${fields[0]}")"
    label="$(sanitize_allowlist_set_text "${fields[1]}")"
    enabled="$(trim "${fields[2]}")"
    scope="$(normalize_allowlist_set_scope "${fields[3]}")" || return 1
    ports="$(normalize_allowlist_set_ports "${fields[4]}" "${scope}")" || return 1
    sources="$(normalize_allowlist_set_sources "${fields[5]}")" || return 1
    note=""
    if [[ ${#fields[@]} -ge 7 ]]; then
        note="$(sanitize_allowlist_set_text "${fields[6]}")"
    fi

    validate_allowlist_set_id "${id}" || return 1
    [[ "${enabled}" == "0" || "${enabled}" == "1" ]] || return 1
    [[ -n "${label}" ]] || label="${id}"

    ALLOWLIST_SET_ID="${id}"
    ALLOWLIST_SET_LABEL="${label}"
    ALLOWLIST_SET_ENABLED="${enabled}"
    ALLOWLIST_SET_SCOPE="${scope}"
    ALLOWLIST_SET_PORTS="${ports}"
    ALLOWLIST_SET_SOURCES="${sources}"
    ALLOWLIST_SET_NOTE="${note}"
    PARSED_ALLOWLIST_SET="$(serialize_allowlist_set \
        "${id}" "${label}" "${enabled}" "${scope}" "${ports}" "${sources}" "${note}")"
}

ensure_default_allowlist_set() {
    local set found_default=0
    for set in "${ALLOWLIST_SETS[@]}"; do
        parse_allowlist_set_line "${set}" || continue
        [[ "${ALLOWLIST_SET_ID}" == "default" ]] && found_default=1
    done
    if [[ "${found_default}" != "1" ]]; then
        ALLOWLIST_SETS=("$(default_allowlist_set_record)" "${ALLOWLIST_SETS[@]}")
    fi
}

write_allowlist_sets_file() {
    local path="$1"
    local set
    cat > "${path}" <<'EOF'
# Managed by nftables relay manager
# format: id|label|enabled|scope|ports|sources|note
# scope:
#   public = applies to all enabled managed relay listen ports
#   ports  = applies only to listed proto/port tokens
# ports:
#   public scope: *
#   ports scope : tcp/30001,udp/30002,both/30003
# sources:
#   region,manual,learned,ssh_temp,ddns,client_ip,ssh_report,webauth
EOF
    for set in "${ALLOWLIST_SETS[@]}"; do
        parse_allowlist_set_line "${set}" || continue
        printf '%s\n' "${PARSED_ALLOWLIST_SET}" >> "${path}"
    done
}

load_allowlist_sets() {
    local force_reload="${1:-0}"
    local line
    if [[ "${ALLOWLIST_SETS_CACHE_READY}" == "1" && "${force_reload}" != "1" ]]; then
        return 0
    fi
    ALLOWLIST_SETS=()
    if [[ -f "${ALLOWLIST_SETS_FILE}" ]]; then
        while IFS= read -r line || [[ -n "${line}" ]]; do
            parse_allowlist_set_line "${line}" || continue
            ALLOWLIST_SETS+=("${PARSED_ALLOWLIST_SET}")
        done < "${ALLOWLIST_SETS_FILE}"
    fi
    ensure_default_allowlist_set
    ALLOWLIST_SETS_CACHE_READY="1"
}

save_allowlist_sets() {
    local tmp
    mkdir -p "${CONF_DIR}" || return 1
    ensure_default_allowlist_set
    make_temp_file "${ALLOWLIST_SETS_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    write_allowlist_sets_file "${tmp}" || return 1
    mv -f "${tmp}" "${ALLOWLIST_SETS_FILE}"
    ALLOWLIST_SETS_CACHE_READY="1"
}

allowlist_set_count() {
    load_allowlist_sets
    printf '%s\n' "${#ALLOWLIST_SETS[@]}"
}

allowlist_set_count_for_file() {
    local file="$1"
    local line count=0
    [[ -f "${file}" ]] || {
        printf '0\n'
        return 0
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_set_line "${line}" || continue
        ((count++))
    done < "${file}"
    printf '%s\n' "${count}"
}

show_allowlist_sets_summary() {
    local set status scope_label ports_label sources_label
    load_allowlist_sets
    for set in "${ALLOWLIST_SETS[@]}"; do
        parse_allowlist_set_line "${set}" || continue
        if [[ "${ALLOWLIST_SET_ENABLED}" == "1" ]]; then
            status="启用"
        else
            status="停用"
        fi
        case "${ALLOWLIST_SET_SCOPE}" in
            public)
                scope_label="公共集"
                ports_label="全部托管转发端口"
                ;;
            *)
                scope_label="端口专属集"
                ports_label="${ALLOWLIST_SET_PORTS}"
                ;;
        esac
        sources_label="${ALLOWLIST_SET_SOURCES//,/ }"
        printf '  - %-16s %-4s 范围=%s 端口=%s 来源=%s\n' \
            "${ALLOWLIST_SET_ID}" "${status}" "${scope_label}" "${ports_label}" "${sources_label}"
    done
}

allowlist_set_nft_name() {
    local id="${1:-default}"
    validate_allowlist_set_id "${id}" || id="default"
    id="${id//./_}"
    id="${id//-/_}"
    printf 'po0_src_%s\n' "${id}"
}

default_allowlist_nft_set_name() {
    allowlist_set_nft_name "default"
}

normalize_allowlist_entry_source_type() {
    local value
    value="$(trim "${1:-manual}")"
    value="${value,,}"
    case "${value}" in
        region|regions|iplist|geo)
            printf 'region\n'
            ;;
        manual|custom|user)
            printf 'manual\n'
            ;;
        learned|learn|conntrack)
            printf 'learned\n'
            ;;
        ssh|ssh_temp|ssh-temp)
            printf 'ssh_temp\n'
            ;;
        ddns|domain)
            printf 'ddns\n'
            ;;
        client_ip|client-ip|mobile|device_ip|device-ip)
            printf 'client_ip\n'
            ;;
        ssh_report|ssh-report|ssh_ip|ssh-ip|egern|egern_ssh|egern-ssh)
            printf 'ssh_report\n'
            ;;
        webauth|web_auth|web-auth|cf_access|cf-access|cloudflare_access|cloudflare-access)
            printf 'webauth\n'
            ;;
        *)
            return 1
            ;;
    esac
}

allowlist_source_type_label() {
    case "$(normalize_allowlist_entry_source_type "${1:-}" 2>/dev/null || true)" in
        region) printf '地区库' ;;
        manual) printf '手动 CIDR' ;;
        learned) printf '学习提升' ;;
        ssh_temp) printf 'SSH 临时' ;;
        ddns) printf 'DDNS 上报' ;;
        client_ip) printf '客户端 IP' ;;
        ssh_report) printf 'SSH report' ;;
        webauth) printf 'WebAuth' ;;
        *) printf '%s' "${1:-unknown}" ;;
    esac
}

allowlist_sources_label() {
    local raw="${1:-}"
    local source out="" label
    raw="${raw//,/ }"
    for source in ${raw}; do
        [[ -n "${source}" ]] || continue
        label="$(allowlist_source_type_label "${source}")"
        if [[ -z "${out}" ]]; then
            out="${label}(${source})"
        else
            out+=", ${label}(${source})"
        fi
    done
    printf '%s\n' "${out:-无}"
}

sanitize_allowlist_entry_text() {
    local value="$1"
    value="${value//$'\t'/ }"
    value="${value//$'\r'/ }"
    value="${value//$'\n'/ }"
    value="${value//|//}"
    value="$(trim "${value}")"
    [[ ${#value} -le 128 ]] || value="${value:0:128}"
    printf '%s\n' "${value}"
}

serialize_allowlist_entry() {
    local set_id="$1"
    local cidr="$2"
    local source_type="$3"
    local source_value="${4:-}"
    local note="${5:-}"
    local created_at="${6:-}"
    local expires_at="${7:-}"
    printf '%s|%s|%s|%s|%s|%s|%s\n' \
        "${set_id}" "${cidr}" "${source_type}" "${source_value}" "${note}" "${created_at}" "${expires_at}"
}

parse_allowlist_entry_line() {
    local line="$1"
    local set_id cidr source_type source_value note created_at expires_at
    local -a fields=()

    PARSED_ALLOWLIST_ENTRY=""
    ALLOWLIST_ENTRY_SET_ID=""
    ALLOWLIST_ENTRY_CIDR=""
    ALLOWLIST_ENTRY_SOURCE_TYPE=""
    ALLOWLIST_ENTRY_SOURCE_VALUE=""
    ALLOWLIST_ENTRY_NOTE=""
    ALLOWLIST_ENTRY_CREATED_AT=""
    ALLOWLIST_ENTRY_EXPIRES_AT=""

    line="${line%$'\r'}"
    line="$(trim "${line}")"
    [[ -n "${line}" && ! "${line}" =~ ^# ]] || return 1

    IFS='|' read -r -a fields <<< "${line}"
    [[ ${#fields[@]} -ge 3 ]] || return 1

    set_id="$(trim "${fields[0]}")"
    cidr="$(normalize_ipv4_cidr_or_host "$(trim "${fields[1]}")")" || return 1
    source_type="$(normalize_allowlist_entry_source_type "$(trim "${fields[2]}")")" || return 1
    source_value=""
    note=""
    created_at=""
    expires_at=""
    [[ ${#fields[@]} -ge 4 ]] && source_value="$(sanitize_allowlist_entry_text "${fields[3]}")"
    [[ ${#fields[@]} -ge 5 ]] && note="$(sanitize_allowlist_entry_text "${fields[4]}")"
    [[ ${#fields[@]} -ge 6 ]] && created_at="$(sanitize_allowlist_entry_text "${fields[5]}")"
    [[ ${#fields[@]} -ge 7 ]] && expires_at="$(sanitize_allowlist_entry_text "${fields[6]}")"

    validate_allowlist_set_id "${set_id}" || return 1

    ALLOWLIST_ENTRY_SET_ID="${set_id}"
    ALLOWLIST_ENTRY_CIDR="${cidr}"
    ALLOWLIST_ENTRY_SOURCE_TYPE="${source_type}"
    ALLOWLIST_ENTRY_SOURCE_VALUE="${source_value}"
    ALLOWLIST_ENTRY_NOTE="${note}"
    ALLOWLIST_ENTRY_CREATED_AT="${created_at}"
    ALLOWLIST_ENTRY_EXPIRES_AT="${expires_at}"
    PARSED_ALLOWLIST_ENTRY="$(serialize_allowlist_entry \
        "${set_id}" "${cidr}" "${source_type}" "${source_value}" "${note}" "${created_at}" "${expires_at}")"
}

write_allowlist_entries_header() {
    local path="$1"
    cat > "${path}" <<'EOF'
# Managed by nftables relay manager
# format: set_id|cidr|source_type|source_value|note|created_at|expires_at
# source_type: region,manual,learned,ssh_temp,ddns,client_ip,ssh_report,webauth
EOF
}

ensure_allowlist_entries_file() {
    mkdir -p "${CONF_DIR}" || return 1
    if [[ ! -f "${ALLOWLIST_ENTRIES_FILE}" ]]; then
        write_allowlist_entries_header "${ALLOWLIST_ENTRIES_FILE}"
    fi
}

allowlist_entries_count() {
    local line count=0
    [[ -f "${ALLOWLIST_ENTRIES_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_entry_line "${line}" || continue
        ((count++))
    done < "${ALLOWLIST_ENTRIES_FILE}"
    printf '%s\n' "${count}"
}

allowlist_entries_count_for_set() {
    local set_id="${1:-default}"
    local line count=0
    [[ -f "${ALLOWLIST_ENTRIES_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_entry_line "${line}" || continue
        [[ "${ALLOWLIST_ENTRY_SET_ID}" == "${set_id}" ]] || continue
        ((count++))
    done < "${ALLOWLIST_ENTRIES_FILE}"
    printf '%s\n' "${count}"
}

allowlist_active_entries_count_for_set() {
    local set_id="${1:-default}"
    local line count=0
    [[ -f "${ALLOWLIST_ENTRIES_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_entry_line "${line}" || continue
        [[ "${ALLOWLIST_ENTRY_SET_ID}" == "${set_id}" ]] || continue
        allowlist_entry_is_expired "${ALLOWLIST_ENTRY_EXPIRES_AT}" && continue
        ((count++))
    done < "${ALLOWLIST_ENTRIES_FILE}"
    printf '%s\n' "${count}"
}

utc_now_iso() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

utc_after_hours_iso() {
    local hours="${1:-24}"
    [[ "${hours}" =~ ^[0-9]+$ ]] || hours="24"
    if date -u -d "+${hours} hours" '+%Y-%m-%dT%H:%M:%SZ' >/dev/null 2>&1; then
        date -u -d "+${hours} hours" '+%Y-%m-%dT%H:%M:%SZ'
    else
        utc_now_iso
    fi
}

allowlist_entry_is_expired() {
    local expires_at="$1"
    local now
    expires_at="$(sanitize_allowlist_entry_text "${expires_at}")"
    [[ -n "${expires_at}" ]] || return 1
    [[ "${expires_at}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || return 1
    now="$(utc_now_iso)"
    [[ "${expires_at}" < "${now}" || "${expires_at}" == "${now}" ]]
}

utc_after_seconds_iso() {
    local seconds="${1:-3600}"
    [[ "${seconds}" =~ ^[0-9]+$ ]] || seconds="3600"
    if date -u -d "+${seconds} seconds" '+%Y-%m-%dT%H:%M:%SZ' >/dev/null 2>&1; then
        date -u -d "+${seconds} seconds" '+%Y-%m-%dT%H:%M:%SZ'
    else
        utc_now_iso
    fi
}

utc_add_seconds_iso() {
    local iso="$1"
    local seconds="${2:-3600}"
    local epoch
    [[ "${seconds}" =~ ^[0-9]+$ ]] || seconds="3600"
    epoch="$(iso_to_epoch_utc "${iso}")" || {
        utc_after_seconds_iso "${seconds}"
        return 0
    }
    if date -u -d "@$((epoch + seconds))" '+%Y-%m-%dT%H:%M:%SZ' >/dev/null 2>&1; then
        date -u -d "@$((epoch + seconds))" '+%Y-%m-%dT%H:%M:%SZ'
    else
        utc_after_seconds_iso "${seconds}"
    fi
}

automation_mode_is_attack() {
    [[ "${AUTOMATION_MODE}" == "attack" ]]
}

auto_source_type_is_freezable() {
    case "$(normalize_allowlist_entry_source_type "${1:-}" 2>/dev/null || true)" in
        ddns|client_ip|ssh_report|webauth)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

dynamic_allowlist_source_type() {
    case "$(normalize_allowlist_entry_source_type "${1:-}" 2>/dev/null || true)" in
        ddns|client_ip|ssh_report|webauth)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

dynamic_allowlist_max_per_source() {
    local value="${DYNAMIC_ALLOWLIST_MAX_PER_SOURCE:-5}"
    [[ "${value}" =~ ^[0-9]+$ ]] || value="5"
    (( value >= 1 )) || value="1"
    (( value <= 50 )) || value="50"
    printf '%s\n' "${value}"
}

write_auto_pending_header() {
    local path="$1"
    cat > "${path}" <<'EOF'
# Managed by nftables relay manager
# format: id|created_at|source_type|source_value|cidr|note|status
EOF
}

ensure_auto_pending_file() {
    mkdir -p "${CONF_DIR}" || return 1
    if [[ ! -f "${AUTO_PENDING_FILE}" ]]; then
        write_auto_pending_header "${AUTO_PENDING_FILE}"
    fi
}

queue_pending_auto_source() {
    local source_type="$1"
    local source_value="$2"
    local cidr="$3"
    local note="${4:-}"
    local id now
    source_type="$(normalize_allowlist_entry_source_type "${source_type}")" || return 1
    source_value="$(sanitize_allowlist_entry_text "${source_value}")"
    cidr="$(normalize_ipv4_cidr_or_host "${cidr}")" || return 1
    note="$(sanitize_allowlist_entry_text "${note}")"
    ensure_auto_pending_file || return 1
    if grep -Fq "|${source_type}|${source_value}|${cidr}|" "${AUTO_PENDING_FILE}" 2>/dev/null; then
        return 0
    fi
    now="$(utc_now_iso)"
    id="pending-$(date '+%s')-${RANDOM}"
    printf '%s|%s|%s|%s|%s|%s|pending\n' \
        "${id}" "${now}" "${source_type}" "${source_value}" "${cidr}" "${note}" >> "${AUTO_PENDING_FILE}"
}

list_pending_auto_sources() {
    ensure_auto_pending_file || return 1
    awk -F '|' 'NF >= 7 && $1 !~ /^#/ && $7 == "pending" {
        printf "  - %s  %s  %s  %s  %s\n", $1, $3, $4, $5, $2
        if ($6 != "") printf "    note: %s\n", $6
    }' "${AUTO_PENDING_FILE}"
}

append_allowlist_entry() {
    local set_id="$1"
    local cidr="$2"
    local source_type="$3"
    local source_value="${4:-}"
    local note="${5:-}"
    local expires_at="${6:-}"
    local created_at line

    validate_allowlist_set_id "${set_id}" || return 1
    cidr="$(normalize_ipv4_cidr_or_host "${cidr}")" || return 1
    source_type="$(normalize_allowlist_entry_source_type "${source_type}")" || return 1
    source_value="$(sanitize_allowlist_entry_text "${source_value}")"
    note="$(sanitize_allowlist_entry_text "${note}")"
    expires_at="$(sanitize_allowlist_entry_text "${expires_at}")"
    created_at="$(utc_now_iso)"
    ensure_allowlist_entries_file || return 1

    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_entry_line "${line}" || continue
        if [[ "${ALLOWLIST_ENTRY_SET_ID}" == "${set_id}" \
            && "${ALLOWLIST_ENTRY_CIDR}" == "${cidr}" \
            && "${ALLOWLIST_ENTRY_SOURCE_TYPE}" == "${source_type}" \
            && "${ALLOWLIST_ENTRY_SOURCE_VALUE}" == "${source_value}" ]]; then
            return 0
        fi
    done < "${ALLOWLIST_ENTRIES_FILE}"

    serialize_allowlist_entry "${set_id}" "${cidr}" "${source_type}" "${source_value}" "${note}" "${created_at}" "${expires_at}" \
        >> "${ALLOWLIST_ENTRIES_FILE}"
}

remove_allowlist_entries_for_cidr() {
    local set_id="$1"
    local cidr="$2"
    local line tmp removed=0
    validate_allowlist_set_id "${set_id}" || return 1
    cidr="$(normalize_ipv4_cidr_or_host "${cidr}")" || return 1
    [[ -f "${ALLOWLIST_ENTRIES_FILE}" ]] || return 0
    make_temp_file "${ALLOWLIST_ENTRIES_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    write_allowlist_entries_header "${tmp}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if parse_allowlist_entry_line "${line}"; then
            if [[ "${ALLOWLIST_ENTRY_SET_ID}" == "${set_id}" && "${ALLOWLIST_ENTRY_CIDR}" == "${cidr}" ]]; then
                removed=1
                continue
            fi
            printf '%s\n' "${PARSED_ALLOWLIST_ENTRY}" >> "${tmp}"
        elif [[ -n "$(trim "${line}")" && ! "$(trim "${line}")" =~ ^# ]]; then
            printf '%s\n' "${line}" >> "${tmp}"
        fi
    done < "${ALLOWLIST_ENTRIES_FILE}"
    mv -f "${tmp}" "${ALLOWLIST_ENTRIES_FILE}"
    [[ "${removed}" == "1" ]] || return 0
}

append_allowlist_entries_to_cache() {
    local set_id="${1:-default}"
    local tmp="$2"
    local line count=0
    [[ -f "${ALLOWLIST_ENTRIES_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_entry_line "${line}" || continue
        [[ "${ALLOWLIST_ENTRY_SET_ID}" == "${set_id}" ]] || continue
        source_type_allowed_by_mode "${ALLOWLIST_ENTRY_SOURCE_TYPE}" "${SRC_ALLOWLIST_MODE}" || continue
        allowlist_entry_is_expired "${ALLOWLIST_ENTRY_EXPIRES_AT}" && continue
        printf '%s\n' "${ALLOWLIST_ENTRY_CIDR}" >> "${tmp}"
        ((count++))
    done < "${ALLOWLIST_ENTRIES_FILE}"
    printf '%s\n' "${count}"
}

allowlist_active_entries_count_for_mode() {
    local set_id="${1:-default}"
    local line count=0
    [[ -f "${ALLOWLIST_ENTRIES_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_entry_line "${line}" || continue
        [[ "${ALLOWLIST_ENTRY_SET_ID}" == "${set_id}" ]] || continue
        source_type_allowed_by_mode "${ALLOWLIST_ENTRY_SOURCE_TYPE}" "${SRC_ALLOWLIST_MODE}" || continue
        allowlist_entry_is_expired "${ALLOWLIST_ENTRY_EXPIRES_AT}" && continue
        ((count++))
    done < "${ALLOWLIST_ENTRIES_FILE}"
    printf '%s\n' "${count}"
}

write_allowlist_sources_header() {
    local path="$1"
    cat > "${path}" <<'EOF'
# Managed by nftables relay manager
# format: set_id|source_type|name|value|enabled|ttl_seconds|last_resolved_at|last_result
# source_type: ddns
# last_result: report:<ip_csv> for external reports, local:<ip_csv> for legacy compatibility, or ERROR ...
EOF
}

ensure_allowlist_sources_file() {
    mkdir -p "${CONF_DIR}" || return 1
    if [[ ! -f "${ALLOWLIST_SOURCES_FILE}" ]]; then
        write_allowlist_sources_header "${ALLOWLIST_SOURCES_FILE}"
    fi
}

sanitize_allowlist_source_text() {
    local value="$1"
    value="${value//$'\t'/ }"
    value="${value//$'\r'/ }"
    value="${value//$'\n'/ }"
    value="${value//|//}"
    value="$(trim "${value}")"
    [[ ${#value} -le 128 ]] || value="${value:0:128}"
    printf '%s\n' "${value}"
}

validate_ddns_domain() {
    local value="$1"
    [[ ${#value} -ge 1 && ${#value} -le 253 ]] || return 1
    [[ "${value}" =~ ^[A-Za-z0-9.-]+$ ]] || return 1
    [[ "${value}" == *.* ]] || return 1
    [[ ! "${value}" == .* && ! "${value}" == *. ]] || return 1
}

normalize_source_ttl_seconds() {
    local ttl="${1:-300}"
    [[ "${ttl}" =~ ^[0-9]+$ ]] || ttl="300"
    (( ttl >= 60 )) || ttl=60
    (( ttl <= 86400 )) || ttl=86400
    printf '%s\n' "${ttl}"
}

serialize_allowlist_source() {
    local set_id="$1"
    local source_type="$2"
    local name="$3"
    local value="$4"
    local enabled="$5"
    local ttl_seconds="$6"
    local last_resolved_at="${7:-}"
    local last_result="${8:-}"
    printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
        "${set_id}" "${source_type}" "${name}" "${value}" "${enabled}" "${ttl_seconds}" "${last_resolved_at}" "${last_result}"
}

parse_allowlist_source_line() {
    local line="$1"
    local set_id source_type name value enabled ttl_seconds last_resolved_at last_result
    local -a fields=()

    PARSED_ALLOWLIST_SOURCE=""
    ALLOWLIST_SOURCE_SET_ID=""
    ALLOWLIST_SOURCE_TYPE=""
    ALLOWLIST_SOURCE_NAME=""
    ALLOWLIST_SOURCE_VALUE=""
    ALLOWLIST_SOURCE_ENABLED=""
    ALLOWLIST_SOURCE_TTL_SECONDS=""
    ALLOWLIST_SOURCE_LAST_RESOLVED_AT=""
    ALLOWLIST_SOURCE_LAST_RESULT=""

    line="${line%$'\r'}"
    line="$(trim "${line}")"
    [[ -n "${line}" && ! "${line}" =~ ^# ]] || return 1

    IFS='|' read -r -a fields <<< "${line}"
    [[ ${#fields[@]} -ge 6 ]] || return 1

    set_id="$(trim "${fields[0]}")"
    source_type="$(normalize_allowlist_entry_source_type "$(trim "${fields[1]}")")" || return 1
    name="$(sanitize_allowlist_source_text "${fields[2]}")"
    value="$(sanitize_allowlist_source_text "${fields[3]}")"
    enabled="$(trim "${fields[4]}")"
    ttl_seconds="$(normalize_source_ttl_seconds "${fields[5]}")"
    last_resolved_at=""
    last_result=""
    [[ ${#fields[@]} -ge 7 ]] && last_resolved_at="$(sanitize_allowlist_source_text "${fields[6]}")"
    [[ ${#fields[@]} -ge 8 ]] && last_result="$(sanitize_allowlist_source_text "${fields[7]}")"

    validate_allowlist_set_id "${set_id}" || return 1
    [[ "${source_type}" == "ddns" ]] || return 1
    [[ -n "${name}" ]] || name="${value}"
    validate_ddns_domain "${value}" || return 1
    [[ "${enabled}" == "0" || "${enabled}" == "1" ]] || return 1

    ALLOWLIST_SOURCE_SET_ID="${set_id}"
    ALLOWLIST_SOURCE_TYPE="${source_type}"
    ALLOWLIST_SOURCE_NAME="${name}"
    ALLOWLIST_SOURCE_VALUE="${value}"
    ALLOWLIST_SOURCE_ENABLED="${enabled}"
    ALLOWLIST_SOURCE_TTL_SECONDS="${ttl_seconds}"
    ALLOWLIST_SOURCE_LAST_RESOLVED_AT="${last_resolved_at}"
    ALLOWLIST_SOURCE_LAST_RESULT="${last_result}"
    PARSED_ALLOWLIST_SOURCE="$(serialize_allowlist_source \
        "${set_id}" "${source_type}" "${name}" "${value}" "${enabled}" "${ttl_seconds}" "${last_resolved_at}" "${last_result}")"
}

allowlist_sources_count() {
    local line count=0
    [[ -f "${ALLOWLIST_SOURCES_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_source_line "${line}" || continue
        ((count++))
    done < "${ALLOWLIST_SOURCES_FILE}"
    printf '%s\n' "${count}"
}

join_csv() {
    local item out=""
    for item in "$@"; do
        if [[ -z "${out}" ]]; then
            out="${item}"
        else
            out+=",${item}"
        fi
    done
    printf '%s\n' "${out}"
}

normalize_public_ipv4_csv() {
    local raw="$1"
    local token out="" seen=" "
    raw="${raw//,/ }"
    raw="${raw//;/ }"
    for token in ${raw}; do
        token="$(trim "${token}")"
        is_public_ipv4 "${token}" || continue
        [[ "${seen}" == *" ${token} "* ]] && continue
        seen+="${token} "
        if [[ -z "${out}" ]]; then
            out="${token}"
        else
            out+=",${token}"
        fi
    done
    [[ -n "${out}" ]] || return 1
    printf '%s\n' "${out}"
}

print_ipv4_csv_lines() {
    local csv="$1"
    local token
    csv="${csv//,/ }"
    for token in ${csv}; do
        token="$(trim "${token}")"
        is_public_ipv4 "${token}" && printf '%s\n' "${token}"
    done
}

ddns_result_public_ipv4_csv() {
    local result="$1"
    result="$(sanitize_allowlist_source_text "${result}")"
    case "${result}" in
        report:*)
            result="${result#report:}"
            ;;
        local:*)
            result="${result#local:}"
            ;;
        ERROR*|"")
            return 1
            ;;
    esac
    normalize_public_ipv4_csv "${result}"
}

iso_to_epoch_utc() {
    local iso="$1"
    [[ "${iso}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || return 1
    date -u -d "${iso}" '+%s' 2>/dev/null
}

ddns_report_is_fresh() {
    local resolved_at="$1"
    local ttl="$2"
    local result="$3"
    local resolved_epoch now age
    [[ "${result}" == report:* ]] || return 1
    ttl="$(normalize_source_ttl_seconds "${ttl}")"
    resolved_epoch="$(iso_to_epoch_utc "${resolved_at}")" || return 1
    now="$(date -u '+%s')"
    age=$((now - resolved_epoch))
    (( age >= 0 && age <= ttl ))
}

reported_ddns_ipv4_records() {
    local resolved_at="$1"
    local ttl="$2"
    local result="$3"
    local csv
    ddns_report_is_fresh "${resolved_at}" "${ttl}" "${result}" || return 1
    csv="$(ddns_result_public_ipv4_csv "${result}")" || return 1
    print_ipv4_csv_lines "${csv}"
}

replace_allowlist_entries_for_source_with_expiry() {
    local set_id="$1"
    local source_type="$2"
    local source_value="$3"
    local note="$4"
    local expires_at="${5:-}"
    shift 5
    local cidr line tmp created_at normalized_type normalized_value normalized_note existing_seen=" " skipped=0 added=0
    local dynamic_mode=0 max_keep selected selected_count best_idx best_created idx found_idx
    local -a dynamic_cidrs=()
    local -a dynamic_notes=()
    local -a dynamic_created=()
    local -a dynamic_expires=()
    validate_allowlist_set_id "${set_id}" || return 1
    normalized_type="$(normalize_allowlist_entry_source_type "${source_type}")" || return 1
    normalized_value="$(sanitize_allowlist_entry_text "${source_value}")"
    normalized_note="$(sanitize_allowlist_entry_text "${note}")"
    expires_at="$(sanitize_allowlist_entry_text "${expires_at}")"
    dynamic_allowlist_source_type "${normalized_type}" && dynamic_mode=1
    ensure_allowlist_entries_file || return 1
    make_temp_file "${ALLOWLIST_ENTRIES_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    write_allowlist_entries_header "${tmp}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if parse_allowlist_entry_line "${line}"; then
            if [[ "${ALLOWLIST_ENTRY_SET_ID}" == "${set_id}" \
                && "${ALLOWLIST_ENTRY_SOURCE_TYPE}" == "${normalized_type}" \
                && "${ALLOWLIST_ENTRY_SOURCE_VALUE}" == "${normalized_value}" ]]; then
                if [[ "${dynamic_mode}" == "1" ]]; then
                    allowlist_entry_is_expired "${ALLOWLIST_ENTRY_EXPIRES_AT}" && continue
                    dynamic_cidrs+=("${ALLOWLIST_ENTRY_CIDR}")
                    dynamic_notes+=("${ALLOWLIST_ENTRY_NOTE}")
                    dynamic_created+=("${ALLOWLIST_ENTRY_CREATED_AT}")
                    dynamic_expires+=("${ALLOWLIST_ENTRY_EXPIRES_AT}")
                    existing_seen+="${ALLOWLIST_ENTRY_CIDR} "
                else
                    existing_seen+="${ALLOWLIST_ENTRY_CIDR} "
                fi
                continue
            fi
            printf '%s\n' "${PARSED_ALLOWLIST_ENTRY}" >> "${tmp}"
        elif [[ -n "$(trim "${line}")" && ! "$(trim "${line}")" =~ ^# ]]; then
            printf '%s\n' "${line}" >> "${tmp}"
        fi
    done < "${ALLOWLIST_ENTRIES_FILE}"
    created_at="$(utc_now_iso)"
    if [[ "${dynamic_mode}" == "1" ]]; then
        for cidr in "$@"; do
            cidr="$(normalize_ipv4_cidr_or_host "${cidr}")" || return 1
            if automation_mode_is_attack && auto_source_type_is_freezable "${normalized_type}" && [[ "${existing_seen}" != *" ${cidr} "* ]]; then
                queue_pending_auto_source "${normalized_type}" "${normalized_value}" "${cidr}" "${normalized_note}" || true
                ((skipped++))
                continue
            fi
            found_idx=-1
            for idx in "${!dynamic_cidrs[@]}"; do
                if [[ "${dynamic_cidrs[$idx]}" == "${cidr}" ]]; then
                    found_idx="${idx}"
                    break
                fi
            done
            if (( found_idx >= 0 )); then
                dynamic_notes[$found_idx]="${normalized_note}"
                dynamic_created[$found_idx]="${created_at}"
                dynamic_expires[$found_idx]="${expires_at}"
            else
                dynamic_cidrs+=("${cidr}")
                dynamic_notes+=("${normalized_note}")
                dynamic_created+=("${created_at}")
                dynamic_expires+=("${expires_at}")
            fi
            existing_seen+="${cidr} "
            ((added++))
        done
        max_keep="$(dynamic_allowlist_max_per_source)"
        selected=" "
        selected_count=0
        while (( selected_count < max_keep )); do
            best_idx=-1
            best_created=""
            for idx in "${!dynamic_cidrs[@]}"; do
                [[ "${selected}" == *" ${idx} "* ]] && continue
                [[ -n "${dynamic_cidrs[$idx]}" ]] || continue
                allowlist_entry_is_expired "${dynamic_expires[$idx]}" && continue
                if (( best_idx < 0 )) || [[ "${dynamic_created[$idx]}" > "${best_created}" ]]; then
                    best_idx="${idx}"
                    best_created="${dynamic_created[$idx]}"
                fi
            done
            (( best_idx >= 0 )) || break
            serialize_allowlist_entry "${set_id}" "${dynamic_cidrs[$best_idx]}" "${normalized_type}" "${normalized_value}" "${dynamic_notes[$best_idx]}" "${dynamic_created[$best_idx]}" "${dynamic_expires[$best_idx]}" \
                >> "${tmp}"
            selected+="${best_idx} "
            ((selected_count++))
        done
    else
        for cidr in "$@"; do
            cidr="$(normalize_ipv4_cidr_or_host "${cidr}")" || return 1
            if automation_mode_is_attack && auto_source_type_is_freezable "${normalized_type}" && [[ "${existing_seen}" != *" ${cidr} "* ]]; then
                queue_pending_auto_source "${normalized_type}" "${normalized_value}" "${cidr}" "${normalized_note}" || true
                ((skipped++))
                continue
            fi
            serialize_allowlist_entry "${set_id}" "${cidr}" "${normalized_type}" "${normalized_value}" "${normalized_note}" "${created_at}" "${expires_at}" \
                >> "${tmp}"
            ((added++))
        done
    fi
    mv -f "${tmp}" "${ALLOWLIST_ENTRIES_FILE}"
    DYNAMIC_REPORT_ADDED_COUNT="${added}"
    DYNAMIC_REPORT_PENDING_COUNT="${skipped}"
}

replace_allowlist_entries_for_source() {
    local set_id="$1"
    local source_type="$2"
    local source_value="$3"
    local note="$4"
    shift 4
    replace_allowlist_entries_for_source_with_expiry "${set_id}" "${source_type}" "${source_value}" "${note}" "" "$@"
}

cleanup_dynamic_allowlist_entries() {
    local line tmp dynamic_tmp sorted_tmp created key record count max_keep
    local removed_expired=0 trimmed=0 kept_dynamic=0 kept_static=0
    declare -A group_counts=()
    max_keep="$(dynamic_allowlist_max_per_source)"
    ensure_allowlist_entries_file || return 1
    make_temp_file "${ALLOWLIST_ENTRIES_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    make_temp_file "${ALLOWLIST_ENTRIES_FILE}.dynamic" || return 1
    dynamic_tmp="${TEMP_FILE_RESULT}"
    make_temp_file "${ALLOWLIST_ENTRIES_FILE}.sorted" || return 1
    sorted_tmp="${TEMP_FILE_RESULT}"
    write_allowlist_entries_header "${tmp}"
    : > "${dynamic_tmp}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if parse_allowlist_entry_line "${line}"; then
            if dynamic_allowlist_source_type "${ALLOWLIST_ENTRY_SOURCE_TYPE}"; then
                if allowlist_entry_is_expired "${ALLOWLIST_ENTRY_EXPIRES_AT}"; then
                    ((removed_expired++))
                    continue
                fi
                created="${ALLOWLIST_ENTRY_CREATED_AT:-0000-00-00T00:00:00Z}"
                key="${ALLOWLIST_ENTRY_SOURCE_TYPE}|${ALLOWLIST_ENTRY_SOURCE_VALUE}"
                printf '%s\t%s\t%s\n' "${created}" "${key}" "${PARSED_ALLOWLIST_ENTRY}" >> "${dynamic_tmp}"
            else
                printf '%s\n' "${PARSED_ALLOWLIST_ENTRY}" >> "${tmp}"
                ((kept_static++))
            fi
        elif [[ -n "$(trim "${line}")" && ! "$(trim "${line}")" =~ ^# ]]; then
            printf '%s\n' "${line}" >> "${tmp}"
        fi
    done < "${ALLOWLIST_ENTRIES_FILE}"
    sort -r "${dynamic_tmp}" > "${sorted_tmp}"
    while IFS=$'\t' read -r created key record || [[ -n "${record:-}" ]]; do
        [[ -n "${record:-}" ]] || continue
        count="${group_counts[$key]:-0}"
        if (( count < max_keep )); then
            printf '%s\n' "${record}" >> "${tmp}"
            group_counts[$key]=$((count + 1))
            ((kept_dynamic++))
        else
            ((trimmed++))
        fi
    done < "${sorted_tmp}"
    mv -f "${tmp}" "${ALLOWLIST_ENTRIES_FILE}"
    printf '动态来源清理完成：保留动态 %s 条，保留静态 %s 条，删除过期 %s 条，裁剪超量 %s 条；每个来源最多保留 %s 个 IP。\n' \
        "${kept_dynamic}" "${kept_static}" "${removed_expired}" "${trimmed}" "${max_keep}"
}

do_cleanup_dynamic_allowlist() {
    ensure_layout || return 1
    load_settings 1
    cleanup_dynamic_allowlist_entries || return 1
    if src_allowlist_enabled; then
        write_nft_conf || return 1
        save_settings || return 1
        apply_or_save_notice "动态来源清理已应用。" "动态来源清理已保存到托管配置。"
    fi
}

remove_allowlist_entries_for_source() {
    local set_id="$1"
    local source_type="$2"
    local source_value="$3"
    local line tmp normalized_type normalized_value
    validate_allowlist_set_id "${set_id}" || return 1
    normalized_type="$(normalize_allowlist_entry_source_type "${source_type}")" || return 1
    normalized_value="$(sanitize_allowlist_entry_text "${source_value}")"
    ensure_allowlist_entries_file || return 1
    make_temp_file "${ALLOWLIST_ENTRIES_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    write_allowlist_entries_header "${tmp}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if parse_allowlist_entry_line "${line}"; then
            if [[ "${ALLOWLIST_ENTRY_SET_ID}" == "${set_id}" \
                && "${ALLOWLIST_ENTRY_SOURCE_TYPE}" == "${normalized_type}" \
                && "${ALLOWLIST_ENTRY_SOURCE_VALUE}" == "${normalized_value}" ]]; then
                continue
            fi
            printf '%s\n' "${PARSED_ALLOWLIST_ENTRY}" >> "${tmp}"
        elif [[ -n "$(trim "${line}")" && ! "$(trim "${line}")" =~ ^# ]]; then
            printf '%s\n' "${line}" >> "${tmp}"
        fi
    done < "${ALLOWLIST_ENTRIES_FILE}"
    mv -f "${tmp}" "${ALLOWLIST_ENTRIES_FILE}"
}

sync_ddns_entries_removed() {
    local set_id="$1"
    local name="$2"
    local value="$3"
    remove_allowlist_entries_for_source "${set_id}" "ddns" "${value}" || return 1
    if [[ "${name}" != "${value}" ]]; then
        remove_allowlist_entries_for_source "${set_id}" "ddns" "${name}" || return 1
    fi
}

ensure_ddns_report_token() {
    local token
    mkdir -p "${CONF_DIR}" || return 1
    if [[ ! -s "${DDNS_REPORT_TOKEN_FILE}" ]]; then
        if command -v openssl &>/dev/null; then
            token="$(openssl rand -hex 24 2>/dev/null || true)"
        fi
        if [[ -z "${token:-}" ]]; then
            token="$(date '+%s')-$RANDOM-$RANDOM-$RANDOM"
        fi
        printf '%s\n' "${token}" > "${DDNS_REPORT_TOKEN_FILE}" || return 1
        chmod 600 "${DDNS_REPORT_TOKEN_FILE}" 2>/dev/null || true
    fi
}

ddns_report_token_value() {
    ensure_ddns_report_token || return 1
    tr -d '[:space:]' < "${DDNS_REPORT_TOKEN_FILE}"
}

validate_ddns_report_token() {
    local provided="${1:-}"
    local expected
    [[ -f "${DDNS_REPORT_TOKEN_FILE}" ]] || return 0
    expected="$(ddns_report_token_value)" || return 1
    [[ -n "${expected}" && "${provided}" == "${expected}" ]]
}

validate_ddns_report_token_readonly() {
    local provided="${1:-}"
    local expected
    [[ -s "${DDNS_REPORT_TOKEN_FILE}" ]] || return 0
    expected="$(tr -d '[:space:]' < "${DDNS_REPORT_TOKEN_FILE}")" || return 1
    [[ -n "${expected}" && "${provided}" == "${expected}" ]]
}

ensure_token_file() {
    local path="$1"
    local token=""
    mkdir -p "${CONF_DIR}" || return 1
    if [[ ! -s "${path}" ]]; then
        if command -v openssl &>/dev/null; then
            token="$(openssl rand -hex 24 2>/dev/null || true)"
        fi
        if [[ -z "${token}" ]]; then
            token="$(date '+%s')-$RANDOM-$RANDOM-$RANDOM"
        fi
        printf '%s\n' "${token}" > "${path}" || return 1
        chmod 600 "${path}" 2>/dev/null || true
    fi
}

token_file_value() {
    local path="$1"
    ensure_token_file "${path}" || return 1
    tr -d '[:space:]' < "${path}"
}

token_file_matches() {
    local path="$1"
    local provided="${2:-}"
    local expected
    [[ -s "${path}" ]] || return 0
    expected="$(tr -d '[:space:]' < "${path}")" || return 1
    [[ -n "${expected}" && "${provided}" == "${expected}" ]]
}

client_ip_report_token_value() {
    token_file_value "${CLIENT_IP_REPORT_TOKEN_FILE}"
}

validate_client_ip_report_token() {
    token_file_matches "${CLIENT_IP_REPORT_TOKEN_FILE}" "${1:-}"
}

ssh_report_token_value() {
    token_file_value "${SSH_REPORT_TOKEN_FILE}"
}

validate_ssh_report_token() {
    token_file_matches "${SSH_REPORT_TOKEN_FILE}" "${1:-}"
}

webauth_report_token_value() {
    token_file_value "${WEBAUTH_REPORT_TOKEN_FILE}"
}

validate_webauth_report_token() {
    token_file_matches "${WEBAUTH_REPORT_TOKEN_FILE}" "${1:-}"
}

write_ddns_report_stats_header() {
    local path="$1"
    cat > "${path}" <<'EOF'
# Managed by nftables relay manager
# format: key|accepted_count|rejected_count|last_status|last_at|last_ips|last_error
EOF
}

write_generic_report_stats_header() {
    local path="$1"
    cat > "${path}" <<'EOF'
# Managed by nftables relay manager
# format: key|accepted_count|rejected_count|last_status|last_at|last_ips|last_error
EOF
}

ensure_generic_report_stats_file() {
    local path="$1"
    mkdir -p "${CONF_DIR}" || return 1
    if [[ ! -f "${path}" ]]; then
        write_generic_report_stats_header "${path}"
    fi
}

update_generic_report_stats() {
    local path="$1"
    local key="$2"
    local status="$3"
    local ips="${4:-}"
    local error="${5:-}"
    local line tmp stat_key accepted rejected last_status last_at last_ips last_error found=0 now
    key="$(sanitize_allowlist_source_text "${key}")"
    [[ -n "${key}" ]] || key="unknown"
    ips="$(sanitize_allowlist_source_text "${ips:-无}")"
    error="$(sanitize_allowlist_source_text "${error:-无}")"
    [[ -n "${ips}" ]] || ips="无"
    [[ -n "${error}" ]] || error="无"
    now="$(utc_now_iso)"
    ensure_generic_report_stats_file "${path}" || return 1
    make_temp_file "${path}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    write_generic_report_stats_header "${tmp}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        line="$(trim "${line}")"
        [[ -n "${line}" && ! "${line}" =~ ^# ]] || continue
        IFS='|' read -r stat_key accepted rejected last_status last_at last_ips last_error <<< "${line}"
        stat_key="$(sanitize_allowlist_source_text "${stat_key}")"
        [[ -n "${stat_key}" ]] || continue
        [[ "${accepted}" =~ ^[0-9]+$ ]] || accepted=0
        [[ "${rejected}" =~ ^[0-9]+$ ]] || rejected=0
        if [[ "${stat_key}" == "${key}" ]]; then
            found=1
            if [[ "${status}" == "accepted" ]]; then
                accepted=$((accepted + 1))
            else
                rejected=$((rejected + 1))
            fi
            printf '%s|%s|%s|%s|%s|%s|%s\n' \
                "${key}" "${accepted}" "${rejected}" "${status}" "${now}" "${ips}" "${error}" >> "${tmp}"
            continue
        fi
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${path}"
    if [[ "${found}" != "1" ]]; then
        accepted=0
        rejected=0
        if [[ "${status}" == "accepted" ]]; then
            accepted=1
        else
            rejected=1
        fi
        printf '%s|%s|%s|%s|%s|%s|%s\n' \
            "${key}" "${accepted}" "${rejected}" "${status}" "${now}" "${ips}" "${error}" >> "${tmp}"
    fi
    mv -f "${tmp}" "${path}"
}

load_generic_report_stats() {
    local path="$1"
    local key="$2"
    local line stat_key accepted rejected last_status last_at last_ips last_error
    REPORT_STAT_ACCEPTED="0"
    REPORT_STAT_REJECTED="0"
    REPORT_STAT_LAST_STATUS=""
    REPORT_STAT_LAST_AT=""
    REPORT_STAT_LAST_IPS=""
    REPORT_STAT_LAST_ERROR=""
    key="$(sanitize_allowlist_source_text "${key}")"
    [[ -f "${path}" ]] || return 0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        line="$(trim "${line}")"
        [[ -n "${line}" && ! "${line}" =~ ^# ]] || continue
        IFS='|' read -r stat_key accepted rejected last_status last_at last_ips last_error <<< "${line}"
        stat_key="$(sanitize_allowlist_source_text "${stat_key}")"
        if [[ "${stat_key}" == "${key}" ]]; then
            REPORT_STAT_ACCEPTED="${accepted:-0}"
            REPORT_STAT_REJECTED="${rejected:-0}"
            REPORT_STAT_LAST_STATUS="${last_status:-}"
            REPORT_STAT_LAST_AT="${last_at:-}"
            REPORT_STAT_LAST_IPS="${last_ips:-}"
            REPORT_STAT_LAST_ERROR="${last_error:-}"
            return 0
        fi
    done < "${path}"
}

ensure_ddns_report_stats_file() {
    mkdir -p "${CONF_DIR}" || return 1
    if [[ ! -f "${DDNS_REPORT_STATS_FILE}" ]]; then
        write_ddns_report_stats_header "${DDNS_REPORT_STATS_FILE}"
    fi
}

update_ddns_report_stats() {
    local key="$1"
    local status="$2"
    local ips="${3:-}"
    local error="${4:-}"
    local line tmp stat_key accepted rejected last_status last_at last_ips last_error found=0 now
    key="$(sanitize_allowlist_source_text "${key}")"
    [[ -n "${key}" ]] || key="unknown"
    ips="$(sanitize_allowlist_source_text "${ips:-无}")"
    error="$(sanitize_allowlist_source_text "${error:-无}")"
    [[ -n "${ips}" ]] || ips="无"
    [[ -n "${error}" ]] || error="无"
    now="$(utc_now_iso)"
    ensure_ddns_report_stats_file || return 1
    make_temp_file "${DDNS_REPORT_STATS_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    write_ddns_report_stats_header "${tmp}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        line="$(trim "${line}")"
        [[ -n "${line}" && ! "${line}" =~ ^# ]] || continue
        IFS='|' read -r stat_key accepted rejected last_status last_at last_ips last_error <<< "${line}"
        stat_key="$(sanitize_allowlist_source_text "${stat_key}")"
        [[ -n "${stat_key}" ]] || continue
        [[ "${accepted}" =~ ^[0-9]+$ ]] || accepted=0
        [[ "${rejected}" =~ ^[0-9]+$ ]] || rejected=0
        if [[ "${stat_key}" == "${key}" ]]; then
            found=1
            if [[ "${status}" == "accepted" ]]; then
                accepted=$((accepted + 1))
            else
                rejected=$((rejected + 1))
            fi
            printf '%s|%s|%s|%s|%s|%s|%s\n' \
                "${key}" "${accepted}" "${rejected}" "${status}" "${now}" "${ips}" "${error}" >> "${tmp}"
            continue
        fi
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${DDNS_REPORT_STATS_FILE}"
    if [[ "${found}" != "1" ]]; then
        accepted=0
        rejected=0
        if [[ "${status}" == "accepted" ]]; then
            accepted=1
        else
            rejected=1
        fi
        printf '%s|%s|%s|%s|%s|%s|%s\n' \
            "${key}" "${accepted}" "${rejected}" "${status}" "${now}" "${ips}" "${error}" >> "${tmp}"
    fi
    mv -f "${tmp}" "${DDNS_REPORT_STATS_FILE}"
}

load_ddns_report_stats() {
    local key="$1"
    local line stat_key accepted rejected last_status last_at last_ips last_error
    DDNS_STAT_ACCEPTED="0"
    DDNS_STAT_REJECTED="0"
    DDNS_STAT_LAST_STATUS=""
    DDNS_STAT_LAST_AT=""
    DDNS_STAT_LAST_IPS=""
    DDNS_STAT_LAST_ERROR=""
    key="$(sanitize_allowlist_source_text "${key}")"
    [[ -f "${DDNS_REPORT_STATS_FILE}" ]] || return 0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        line="$(trim "${line}")"
        [[ -n "${line}" && ! "${line}" =~ ^# ]] || continue
        IFS='|' read -r stat_key accepted rejected last_status last_at last_ips last_error <<< "${line}"
        stat_key="$(sanitize_allowlist_source_text "${stat_key}")"
        if [[ "${stat_key}" == "${key}" ]]; then
            DDNS_STAT_ACCEPTED="${accepted:-0}"
            DDNS_STAT_REJECTED="${rejected:-0}"
            DDNS_STAT_LAST_STATUS="${last_status:-}"
            DDNS_STAT_LAST_AT="${last_at:-}"
            DDNS_STAT_LAST_IPS="${last_ips:-}"
            DDNS_STAT_LAST_ERROR="${last_error:-}"
            return 0
        fi
    done < "${DDNS_REPORT_STATS_FILE}"
}

print_ddns_report_stats_line() {
    local key="$1"
    local status_label
    load_ddns_report_stats "${key}"
    if [[ -z "${DDNS_STAT_LAST_STATUS}" ]]; then
        printf '      外部上报统计：尚无记录\n'
        return 0
    fi
    case "${DDNS_STAT_LAST_STATUS}" in
        accepted)
            status_label="接受"
            ;;
        rejected)
            status_label="拒绝"
            ;;
        *)
            status_label="${DDNS_STAT_LAST_STATUS}"
            ;;
    esac
    printf '      外部上报统计：接受=%s 拒绝=%s 最近=%s 状态=%s IP=%s\n' \
        "${DDNS_STAT_ACCEPTED}" "${DDNS_STAT_REJECTED}" "${DDNS_STAT_LAST_AT:-未知}" \
        "${status_label}" "${DDNS_STAT_LAST_IPS:-无}"
    if [[ -n "${DDNS_STAT_LAST_ERROR}" && "${DDNS_STAT_LAST_ERROR}" != "无" ]]; then
        printf '      最近错误：%s\n' "${DDNS_STAT_LAST_ERROR}"
    fi
}

remove_ddns_report_stats() {
    local key="$1"
    local line stat_key tmp
    key="$(sanitize_allowlist_source_text "${key}")"
    [[ -f "${DDNS_REPORT_STATS_FILE}" ]] || return 0
    make_temp_file "${DDNS_REPORT_STATS_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    write_ddns_report_stats_header "${tmp}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        line="$(trim "${line}")"
        [[ -n "${line}" && ! "${line}" =~ ^# ]] || continue
        IFS='|' read -r stat_key _ <<< "${line}"
        stat_key="$(sanitize_allowlist_source_text "${stat_key}")"
        [[ "${stat_key}" == "${key}" ]] && continue
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${DDNS_REPORT_STATS_FILE}"
    mv -f "${tmp}" "${DDNS_REPORT_STATS_FILE}"
}

normalize_client_ttl_seconds() {
    local ttl="${1:-3600}"
    [[ "${ttl}" =~ ^[0-9]+$ ]] || ttl="3600"
    (( ttl >= 60 )) || ttl=60
    (( ttl <= 604800 )) || ttl=604800
    printf '%s\n' "${ttl}"
}

normalize_report_expires_at() {
    local value="${1:-}"
    value="$(sanitize_allowlist_entry_text "${value}")"
    if [[ "${value}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
        printf '%s\n' "${value}"
        return 0
    fi
    if [[ "${value}" =~ ^[0-9]+$ ]]; then
        date -u -d "@${value}" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null && return 0
    fi
    utc_after_seconds_iso 3600
}

report_client_ip_source() {
    local source_id="$1"
    local ip="$2"
    local token="$3"
    local identity="${4:-}"
    local ttl="${5:-3600}"
    local expires_at note cidr
    source_id="$(sanitize_allowlist_source_text "${source_id}")"
    identity="$(sanitize_allowlist_source_text "${identity}")"
    [[ -n "${source_id}" ]] || {
        update_generic_report_stats "${CLIENT_IP_REPORT_STATS_FILE}" "unknown" "rejected" "${ip}" "missing_source_id" || true
        err "缺少客户端来源 ID。"
        return 1
    }
    is_public_ipv4 "${ip}" || {
        update_generic_report_stats "${CLIENT_IP_REPORT_STATS_FILE}" "${source_id}" "rejected" "${ip}" "invalid_public_ipv4" || true
        err "客户端上报 IP 无效：${ip}"
        return 1
    }
    validate_client_ip_report_token "${token}" || {
        update_generic_report_stats "${CLIENT_IP_REPORT_STATS_FILE}" "${source_id}" "rejected" "${ip}" "invalid_token" || true
        err "客户端 IP 上报 token 无效。"
        return 1
    }
    ttl="$(normalize_client_ttl_seconds "${ttl}")"
    expires_at="$(utc_after_seconds_iso "${ttl}")"
    cidr="${ip}/32"
    note="client_ip ${source_id}"
    [[ -n "${identity}" ]] && note="${note} identity=${identity}"
    note="${note} ttl=${ttl} $(ipdb_snapshot_for_ip "${ip}")"
    replace_allowlist_entries_for_source_with_expiry "default" "client_ip" "${source_id}" "${note}" "${expires_at}" "${cidr}" || return 1
    update_generic_report_stats "${CLIENT_IP_REPORT_STATS_FILE}" "${source_id}" "accepted" "${ip}" "pending=${DYNAMIC_REPORT_PENDING_COUNT:-0}" || true
    CLIENT_IP_REPORT_SOURCE="${source_id}"
    CLIENT_IP_REPORT_IP="${ip}"
    CLIENT_IP_REPORT_IDENTITY="${identity}"
    CLIENT_IP_REPORT_TTL="${ttl}"
}

report_ssh_ip_source() {
    local source_id="$1"
    local ip="$2"
    local token="$3"
    local identity="${4:-}"
    local ttl="${5:-3600}"
    local expires_at note cidr
    source_id="$(sanitize_allowlist_source_text "${source_id}")"
    identity="$(sanitize_allowlist_source_text "${identity}")"
    [[ -n "${source_id}" ]] || {
        update_generic_report_stats "${SSH_REPORT_STATS_FILE}" "unknown" "rejected" "${ip}" "missing_source_id" || true
        err "missing ssh report source id"
        return 1
    }
    is_public_ipv4 "${ip}" || {
        update_generic_report_stats "${SSH_REPORT_STATS_FILE}" "${source_id}" "rejected" "${ip}" "invalid_public_ipv4" || true
        err "invalid ssh report public IPv4: ${ip}"
        return 1
    }
    validate_ssh_report_token "${token}" || {
        update_generic_report_stats "${SSH_REPORT_STATS_FILE}" "${source_id}" "rejected" "${ip}" "invalid_token" || true
        err "invalid ssh report token"
        return 1
    }
    ttl="$(normalize_client_ttl_seconds "${ttl}")"
    expires_at="$(utc_after_seconds_iso "${ttl}")"
    cidr="${ip}/32"
    note="ssh_report ${source_id}"
    [[ -n "${identity}" ]] && note="${note} identity=${identity}"
    note="${note} ttl=${ttl} $(ipdb_snapshot_for_ip "${ip}")"
    replace_allowlist_entries_for_source_with_expiry "default" "ssh_report" "${source_id}" "${note}" "${expires_at}" "${cidr}" || return 1
    update_generic_report_stats "${SSH_REPORT_STATS_FILE}" "${source_id}" "accepted" "${ip}" "pending=${DYNAMIC_REPORT_PENDING_COUNT:-0}" || true
    SSH_REPORT_SOURCE="${source_id}"
    SSH_REPORT_IP="${ip}"
    SSH_REPORT_IDENTITY="${identity}"
    SSH_REPORT_TTL="${ttl}"
}

report_webauth_source() {
    local source_id="$1"
    local ip="$2"
    local identity="$3"
    local expires_at="$4"
    local token="$5"
    local note_extra="${6:-}"
    local note cidr
    source_id="$(sanitize_allowlist_source_text "${source_id}")"
    identity="$(sanitize_allowlist_source_text "${identity}")"
    note_extra="$(sanitize_allowlist_source_text "${note_extra}")"
    [[ -n "${source_id}" && -n "${identity}" ]] || {
        update_generic_report_stats "${WEBAUTH_REPORT_STATS_FILE}" "${source_id:-unknown}" "rejected" "${ip}" "missing_source_or_identity" || true
        err "缺少 WebAuth 来源 ID 或身份。"
        return 1
    }
    is_public_ipv4 "${ip}" || {
        update_generic_report_stats "${WEBAUTH_REPORT_STATS_FILE}" "${source_id}" "rejected" "${ip}" "invalid_public_ipv4" || true
        err "WebAuth 上报 IP 无效：${ip}"
        return 1
    }
    validate_webauth_report_token "${token}" || {
        update_generic_report_stats "${WEBAUTH_REPORT_STATS_FILE}" "${source_id}" "rejected" "${ip}" "invalid_token" || true
        err "WebAuth 上报 token 无效。"
        return 1
    }
    expires_at="$(normalize_report_expires_at "${expires_at}")"
    cidr="${ip}/32"
    note="webauth ${source_id} identity=${identity}"
    [[ -n "${note_extra}" ]] && note="${note} ${note_extra}"
    note="${note} $(ipdb_snapshot_for_ip "${ip}")"
    replace_allowlist_entries_for_source_with_expiry "default" "webauth" "${source_id}" "${note}" "${expires_at}" "${cidr}" || return 1
    update_generic_report_stats "${WEBAUTH_REPORT_STATS_FILE}" "${source_id}" "accepted" "${ip}" "pending=${DYNAMIC_REPORT_PENDING_COUNT:-0}" || true
    WEBAUTH_REPORT_SOURCE="${source_id}"
    WEBAUTH_REPORT_IP="${ip}"
    WEBAUTH_REPORT_IDENTITY="${identity}"
    WEBAUTH_REPORT_EXPIRES_AT="${expires_at}"
}

report_ddns_allowlist_source() {
    local key="$1"
    local raw_ips="$2"
    local token="${3:-}"
    local csv line tmp now replacement note cidr expires_at found=0 disabled=0 disabled_stat_key=""
    local -a cidrs=()

    key="$(sanitize_allowlist_source_text "${key}")"
    csv="$(normalize_public_ipv4_csv "${raw_ips}")" || {
        err "外部上报 DDNS 结果无效：没有可用公网 IPv4。"
        update_ddns_report_stats "${key}" "rejected" "无" "invalid_public_ipv4" || true
        return 1
    }
    validate_ddns_report_token "${token}" || {
        err "DDNS 外部上报 token 无效。"
        update_ddns_report_stats "${key}" "rejected" "${csv}" "invalid_token" || true
        return 1
    }
    ensure_allowlist_sources_file || return 1
    ensure_allowlist_entries_file || return 1
    make_temp_file "${ALLOWLIST_SOURCES_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    write_allowlist_sources_header "${tmp}"

    while IFS= read -r line || [[ -n "${line}" ]]; do
        if parse_allowlist_source_line "${line}"; then
            if [[ "${ALLOWLIST_SOURCE_NAME}" == "${key}" || "${ALLOWLIST_SOURCE_VALUE}" == "${key}" ]]; then
                found=1
                if [[ "${ALLOWLIST_SOURCE_ENABLED}" != "1" ]]; then
                    disabled=1
                    disabled_stat_key="${ALLOWLIST_SOURCE_VALUE}"
                    printf '%s\n' "${PARSED_ALLOWLIST_SOURCE}" >> "${tmp}"
                    continue
                fi
                now="$(utc_now_iso)"
                cidrs=()
                while IFS= read -r cidr; do
                    cidrs+=("${cidr}/32")
                done < <(print_ipv4_csv_lines "${csv}")
                expires_at="$(utc_after_seconds_iso "${ALLOWLIST_SOURCE_TTL_SECONDS}")"
                note="ddns report ${ALLOWLIST_SOURCE_NAME} ${ALLOWLIST_SOURCE_VALUE} $(ipdb_snapshot_for_ip "${cidrs[0]%/32}")"
                replace_allowlist_entries_for_source_with_expiry \
                    "${ALLOWLIST_SOURCE_SET_ID}" \
                    "ddns" \
                    "${ALLOWLIST_SOURCE_VALUE}" \
                    "${note}" \
                    "${expires_at}" \
                    "${cidrs[@]}" || return 1
                if [[ "${ALLOWLIST_SOURCE_NAME}" != "${ALLOWLIST_SOURCE_VALUE}" ]]; then
                    remove_allowlist_entries_for_source "${ALLOWLIST_SOURCE_SET_ID}" "ddns" "${ALLOWLIST_SOURCE_NAME}" || return 1
                fi
                replacement="$(serialize_allowlist_source \
                    "${ALLOWLIST_SOURCE_SET_ID}" \
                    "${ALLOWLIST_SOURCE_TYPE}" \
                    "${ALLOWLIST_SOURCE_NAME}" \
                    "${ALLOWLIST_SOURCE_VALUE}" \
                    "${ALLOWLIST_SOURCE_ENABLED}" \
                    "${ALLOWLIST_SOURCE_TTL_SECONDS}" \
                    "${now}" \
                    "report:${csv}")"
                printf '%s\n' "${replacement}" >> "${tmp}"
                DDNS_REPORT_NAME="${ALLOWLIST_SOURCE_NAME}"
                DDNS_REPORT_DOMAIN="${ALLOWLIST_SOURCE_VALUE}"
                DDNS_REPORT_IPS="${csv}"
                continue
            fi
            printf '%s\n' "${PARSED_ALLOWLIST_SOURCE}" >> "${tmp}"
        elif [[ -n "$(trim "${line}")" && ! "$(trim "${line}")" =~ ^# ]]; then
            printf '%s\n' "${line}" >> "${tmp}"
        fi
    done < "${ALLOWLIST_SOURCES_FILE}"

    if [[ "${found}" != "1" ]]; then
        err "未找到 DDNS 来源：${key}。请先在菜单里添加。"
        update_ddns_report_stats "${key}" "rejected" "${csv}" "source_not_found" || true
        return 1
    fi
    if [[ "${disabled}" == "1" ]]; then
        err "DDNS 来源已停用：${key}。请先启用。"
        update_ddns_report_stats "${disabled_stat_key:-${key}}" "rejected" "${csv}" "source_disabled" || true
        return 1
    fi
    mv -f "${tmp}" "${ALLOWLIST_SOURCES_FILE}"
    update_ddns_report_stats "${DDNS_REPORT_DOMAIN:-${key}}" "accepted" "${csv}" "无" || true
}

refresh_ddns_allowlist_sources() {
    local line tmp result ips_csv cidr note expires_at reported=0 failed=0 disabled=0
    local -a ips=()
    local -a cidrs=()
    ensure_allowlist_sources_file || return 1
    ensure_allowlist_entries_file || return 1
    make_temp_file "${ALLOWLIST_SOURCES_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    write_allowlist_sources_header "${tmp}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if ! parse_allowlist_source_line "${line}"; then
            if [[ -n "$(trim "${line}")" && ! "$(trim "${line}")" =~ ^# ]]; then
                printf '%s\n' "${line}" >> "${tmp}"
            fi
            continue
        fi
        if [[ "${ALLOWLIST_SOURCE_ENABLED}" != "1" ]]; then
            ((disabled++))
            sync_ddns_entries_removed "${ALLOWLIST_SOURCE_SET_ID}" "${ALLOWLIST_SOURCE_NAME}" "${ALLOWLIST_SOURCE_VALUE}" || return 1
            printf '%s\n' "${PARSED_ALLOWLIST_SOURCE}" >> "${tmp}"
            continue
        fi
        mapfile -t ips < <(reported_ddns_ipv4_records \
            "${ALLOWLIST_SOURCE_LAST_RESOLVED_AT}" \
            "${ALLOWLIST_SOURCE_TTL_SECONDS}" \
            "${ALLOWLIST_SOURCE_LAST_RESULT}" || true)
        if [[ ${#ips[@]} -gt 0 ]]; then
            cidrs=()
            for cidr in "${ips[@]}"; do
                cidrs+=("${cidr}/32")
            done
            expires_at="$(utc_add_seconds_iso "${ALLOWLIST_SOURCE_LAST_RESOLVED_AT}" "${ALLOWLIST_SOURCE_TTL_SECONDS}")"
            note="ddns report ${ALLOWLIST_SOURCE_NAME} ${ALLOWLIST_SOURCE_VALUE} $(ipdb_snapshot_for_ip "${cidrs[0]%/32}")"
            replace_allowlist_entries_for_source_with_expiry \
                "${ALLOWLIST_SOURCE_SET_ID}" \
                "ddns" \
                "${ALLOWLIST_SOURCE_VALUE}" \
                "${note}" \
                "${expires_at}" \
                "${cidrs[@]}" || return 1
            if [[ "${ALLOWLIST_SOURCE_NAME}" != "${ALLOWLIST_SOURCE_VALUE}" ]]; then
                remove_allowlist_entries_for_source "${ALLOWLIST_SOURCE_SET_ID}" "ddns" "${ALLOWLIST_SOURCE_NAME}" || return 1
            fi
            ips_csv="$(join_csv "${ips[@]}")"
            result="report:${ips_csv}"
            ((reported++))
        else
            result="${ALLOWLIST_SOURCE_LAST_RESULT}"
            ((failed++))
        fi
        printf '%s\n' "$(serialize_allowlist_source \
            "${ALLOWLIST_SOURCE_SET_ID}" \
            "${ALLOWLIST_SOURCE_TYPE}" \
            "${ALLOWLIST_SOURCE_NAME}" \
            "${ALLOWLIST_SOURCE_VALUE}" \
            "${ALLOWLIST_SOURCE_ENABLED}" \
            "${ALLOWLIST_SOURCE_TTL_SECONDS}" \
            "${ALLOWLIST_SOURCE_LAST_RESOLVED_AT}" \
            "${result}")" >> "${tmp}"
    done < "${ALLOWLIST_SOURCES_FILE}"
    mv -f "${tmp}" "${ALLOWLIST_SOURCES_FILE}"
    DDNS_REPORTED_COUNT="${reported}"
    DDNS_LOCAL_COUNT="0"
    DDNS_REFRESHED_COUNT="${reported}"
    DDNS_FAILED_COUNT="${failed}"
    DDNS_DISABLED_COUNT="${disabled}"
}

src_allowlist_mode_to_label() {
    case "$1" in
        manual_only)
            printf '仅手动来源'
            ;;
        trusted_dynamic)
            printf '可信动态来源'
            ;;
        region_plus_trusted)
            printf '地区 + 可信动态来源'
            ;;
        region_only)
            printf '仅地区库'
            ;;
        custom_sources)
            printf '高级自选来源'
            ;;
        *)
            printf '可信动态来源'
            ;;
    esac
}

src_allowlist_mode_uses_region() {
    [[ "${SRC_ALLOWLIST_MODE}" == "region_only" || "${SRC_ALLOWLIST_MODE}" == "region_plus_trusted" ]]
}

src_allowlist_mode_uses_custom() {
    [[ "${SRC_ALLOWLIST_MODE}" != "region_only" ]]
}

src_allowlist_enabled() {
    [[ "${ENABLE_SRC_ALLOWLIST}" == "1" ]] || return 1
    case "${SRC_ALLOWLIST_MODE}" in
        manual_only|trusted_dynamic|custom_sources)
            custom_allowlist_has_entries
            ;;
        region_plus_trusted)
            [[ -n "${SRC_ALLOWLIST_REGION_IDS}" ]] || custom_allowlist_has_entries
            ;;
        region_only)
            [[ -n "${SRC_ALLOWLIST_REGION_IDS}" ]]
            ;;
        *)
            custom_allowlist_has_entries
            ;;
    esac
}

validate_src_allowlist_ready() {
    [[ "${ENABLE_SRC_ALLOWLIST}" == "1" ]] || return 0
    case "${SRC_ALLOWLIST_MODE}" in
        manual_only|trusted_dynamic|custom_sources)
            custom_allowlist_has_entries || {
                err "$(src_allowlist_mode_to_label "${SRC_ALLOWLIST_MODE}") 没有任何可用 CIDR。"
                return 1
            }
            ;;
        region_plus_trusted)
            [[ -n "${SRC_ALLOWLIST_REGION_IDS}" ]] || custom_allowlist_has_entries || {
                err "地区 + 可信动态来源模式没有任何地区或可信来源 CIDR。"
                return 1
            }
            ;;
        region_only)
            [[ -n "${SRC_ALLOWLIST_REGION_IDS}" ]] || {
                err "仅地区库模式未选择任何地区。"
                return 1
            }
            ;;
        *)
            custom_allowlist_has_entries || {
                err "白名单没有任何可用 CIDR。"
                return 1
            }
            ;;
    esac
}

src_allowlist_region_count() {
    local count=0 id
    for id in ${SRC_ALLOWLIST_REGION_IDS}; do
        [[ -n "${id}" ]] && ((count++))
    done
    printf '%s\n' "${count}"
}

sanitize_custom_note() {
    local note="$1"
    note="${note//$'\t'/ }"
    note="${note//$'\r'/ }"
    note="${note//$'\n'/ }"
    note="${note//|//}"
    note="$(trim "${note}")"
    [[ ${#note} -le 80 ]] || note="${note:0:80}"
    printf '%s\n' "${note}"
}

custom_allowlist_line_is_data() {
    local line="$1"
    line="${line%$'\r'}"
    line="$(trim "${line}")"
    [[ -n "${line}" && ! "${line}" =~ ^# ]]
}

parse_custom_allowlist_line() {
    local line="$1"
    local cidr note
    CUSTOM_ALLOWLIST_CIDR=""
    CUSTOM_ALLOWLIST_NOTE=""
    custom_allowlist_line_is_data "${line}" || return 1
    line="${line%$'\r'}"
    line="$(trim "${line}")"
    cidr="${line%%|*}"
    if [[ "${line}" == *"|"* ]]; then
        note="${line#*|}"
    else
        note=""
    fi
    cidr="$(normalize_ipv4_cidr_or_host "${cidr}")" || return 1
    CUSTOM_ALLOWLIST_CIDR="${cidr}"
    CUSTOM_ALLOWLIST_NOTE="$(sanitize_custom_note "${note}")"
}

custom_allowlist_count() {
    local line count=0
    [[ -f "${CUSTOM_SRC_ALLOWLIST_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_custom_allowlist_line "${line}" || continue
        ((count++))
    done < "${CUSTOM_SRC_ALLOWLIST_FILE}"
    printf '%s\n' "${count}"
}

custom_allowlist_count_for_file() {
    local file="$1"
    local line count=0
    [[ -f "${file}" ]] || {
        printf '0\n'
        return 0
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_custom_allowlist_line "${line}" || continue
        ((count++))
    done < "${file}"
    printf '%s\n' "${count}"
}

custom_allowlist_has_entries() {
    [[ "$(custom_allowlist_count)" -gt 0 || "$(allowlist_active_entries_count_for_mode default)" -gt 0 ]]
}

custom_allowlist_contains_cidr() {
    local target="$1"
    local line
    target="$(normalize_ipv4_cidr_or_host "${target}")" || return 1
    [[ -f "${CUSTOM_SRC_ALLOWLIST_FILE}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_custom_allowlist_line "${line}" || continue
        [[ "${CUSTOM_ALLOWLIST_CIDR}" == "${target}" ]] && return 0
    done < "${CUSTOM_SRC_ALLOWLIST_FILE}"
    return 1
}

add_custom_allowlist_entry() {
    local cidr="$1"
    local note="${2:-}"
    local prefix
    cidr="$(normalize_ipv4_cidr_or_host "${cidr}")" || {
        err "CIDR/IP 无效：${cidr}"
        return 1
    }
    note="$(sanitize_custom_note "${note}")"
    custom_allowlist_contains_cidr "${cidr}" && {
        warn "自定义白名单已存在：${cidr}"
        return 0
    }
    mkdir -p "${CONF_DIR}" || return 1
    if [[ ! -f "${CUSTOM_SRC_ALLOWLIST_FILE}" ]]; then
        cat > "${CUSTOM_SRC_ALLOWLIST_FILE}" <<'EOF'
# format: cidr_or_ip|note
# examples:
# 203.0.113.10|home router, observed manually
# 203.0.113.0/24|home ISP candidate, confirm before using
EOF
    fi
    if [[ -n "${note}" ]]; then
        printf '%s|%s\n' "${cidr}" "${note}" >> "${CUSTOM_SRC_ALLOWLIST_FILE}"
    else
        printf '%s\n' "${cidr}" >> "${CUSTOM_SRC_ALLOWLIST_FILE}"
    fi
    append_allowlist_entry "default" "${cidr}" "manual" "" "${note}" "" || return 1
    prefix="$(cidr_prefix_length "${cidr}")"
    if (( prefix < 24 )); then
        warn "已加入较宽网段 ${cidr}；建议确认它确实只覆盖可信来源。"
    fi
}

remove_custom_allowlist_entry() {
    local target="$1"
    local line tmp removed=0
    target="$(normalize_ipv4_cidr_or_host "${target}")" || return 1
    [[ -f "${CUSTOM_SRC_ALLOWLIST_FILE}" ]] || return 1
    make_temp_file "${CUSTOM_SRC_ALLOWLIST_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if parse_custom_allowlist_line "${line}" && [[ "${CUSTOM_ALLOWLIST_CIDR}" == "${target}" ]]; then
            removed=1
            continue
        fi
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${CUSTOM_SRC_ALLOWLIST_FILE}"
    mv -f "${tmp}" "${CUSTOM_SRC_ALLOWLIST_FILE}"
    remove_allowlist_entries_for_cidr "default" "${target}" || true
    [[ "${removed}" == "1" ]]
}

show_custom_allowlist_entries() {
    local line idx=1
    if [[ ! -f "${CUSTOM_SRC_ALLOWLIST_FILE}" ]] || ! custom_allowlist_has_entries; then
        echo "  (未添加自定义 CIDR)"
        return 0
    fi
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_custom_allowlist_line "${line}" || continue
        if [[ -n "${CUSTOM_ALLOWLIST_NOTE}" ]]; then
            printf '  %2d) %-18s %s\n' "${idx}" "${CUSTOM_ALLOWLIST_CIDR}" "${CUSTOM_ALLOWLIST_NOTE}"
        else
            printf '  %2d) %s\n' "${idx}" "${CUSTOM_ALLOWLIST_CIDR}"
        fi
        ((idx++))
    done < "${CUSTOM_SRC_ALLOWLIST_FILE}"
}

validate_allowlist_profile_name() {
    local name="$1"
    [[ "${name}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || {
        err "配置档案名称只能使用字母、数字、点、下划线、短横线，且必须以字母或数字开头，最长 64 个字符。"
        return 1
    }
}

sanitize_profile_label() {
    local label="$1"
    label="${label//$'\t'/ }"
    label="${label//$'\r'/ }"
    label="${label//$'\n'/ }"
    label="$(trim "${label}")"
    [[ ${#label} -le 80 ]] || label="${label:0:80}"
    printf '%s\n' "${label}"
}

generate_allowlist_profile_id() {
    local id
    while true; do
        if command -v uuidgen >/dev/null 2>&1; then
            id="$(uuidgen 2>/dev/null || true)"
        elif [[ -r /proc/sys/kernel/random/uuid ]]; then
            IFS= read -r id < /proc/sys/kernel/random/uuid || id=""
        else
            id="$(date -u '+%Y%m%d%H%M%S')-${RANDOM}-${RANDOM}"
        fi
        id="p-${id,,}"
        validate_allowlist_profile_name "${id}" >/dev/null 2>&1 || continue
        allowlist_profile_exists "${id}" || {
            printf '%s\n' "${id}"
            return 0
        }
    done
}

allowlist_profile_env_file() {
    local name="$1"
    printf '%s/%s.env\n' "${ALLOWLIST_PROFILE_DIR}" "${name}"
}

allowlist_profile_label_file() {
    local name="$1"
    printf '%s/%s.label.txt\n' "${ALLOWLIST_PROFILE_DIR}" "${name}"
}

allowlist_profile_custom_file() {
    local name="$1"
    printf '%s/%s.custom.txt\n' "${ALLOWLIST_PROFILE_DIR}" "${name}"
}

allowlist_profile_sets_file() {
    local name="$1"
    printf '%s/%s.sets.tsv\n' "${ALLOWLIST_PROFILE_DIR}" "${name}"
}

allowlist_profile_entries_file() {
    local name="$1"
    printf '%s/%s.entries.tsv\n' "${ALLOWLIST_PROFILE_DIR}" "${name}"
}

allowlist_profile_sources_file() {
    local name="$1"
    printf '%s/%s.sources.tsv\n' "${ALLOWLIST_PROFILE_DIR}" "${name}"
}

allowlist_profile_exists() {
    local name="$1"
    [[ -f "$(allowlist_profile_env_file "${name}")" ]]
}

allowlist_profile_count() {
    local file name count=0
    [[ -d "${ALLOWLIST_PROFILE_DIR}" ]] || {
        printf '0\n'
        return 0
    }
    for file in "${ALLOWLIST_PROFILE_DIR}"/*.env; do
        [[ -f "${file}" ]] || continue
        name="$(basename "${file}" .env)"
        [[ "${name}" == "${ALLOWLIST_LAST_PROFILE_NAME}" ]] && continue
        ((count++))
    done
    printf '%s\n' "${count}"
}

save_allowlist_profile_state() {
    local name="$1"
    local quiet="${2:-0}"
    local label="${3:-}"
    local env_file label_file custom_file sets_file entries_file sources_file tmp saved_at
    mkdir -p "${ALLOWLIST_PROFILE_DIR}" || return 1
    env_file="$(allowlist_profile_env_file "${name}")"
    label_file="$(allowlist_profile_label_file "${name}")"
    custom_file="$(allowlist_profile_custom_file "${name}")"
    sets_file="$(allowlist_profile_sets_file "${name}")"
    entries_file="$(allowlist_profile_entries_file "${name}")"
    sources_file="$(allowlist_profile_sources_file "${name}")"
    saved_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    label="$(sanitize_profile_label "${label}")"
    ENABLE_SRC_ALLOWLIST="$([[ "${ENABLE_SRC_ALLOWLIST}" == "1" ]] && printf '1' || printf '0')"
    SRC_ALLOWLIST_MODE="$(normalize_src_allowlist_mode "${SRC_ALLOWLIST_MODE}" 2>/dev/null || printf 'trusted_dynamic')"
    SRC_ALLOWLIST_REGION_IDS="$(normalize_region_ids "${SRC_ALLOWLIST_REGION_IDS}")"
    load_allowlist_sets

    make_temp_file "${env_file}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    cat > "${tmp}" <<EOF
PROFILE_FORMAT_VERSION="1"
PROFILE_SAVED_AT="${saved_at}"
ENABLE_SRC_ALLOWLIST="${ENABLE_SRC_ALLOWLIST}"
SRC_ALLOWLIST_MODE="${SRC_ALLOWLIST_MODE}"
SRC_ALLOWLIST_REGION_IDS="${SRC_ALLOWLIST_REGION_IDS}"
EOF
    mv -f "${tmp}" "${env_file}"

    make_temp_file "${label_file}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    printf '%s\n' "${label}" > "${tmp}"
    mv -f "${tmp}" "${label_file}"

    make_temp_file "${custom_file}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    if [[ -f "${CUSTOM_SRC_ALLOWLIST_FILE}" ]]; then
        cp -- "${CUSTOM_SRC_ALLOWLIST_FILE}" "${tmp}" || return 1
    else
        cat > "${tmp}" <<'EOF'
# format: cidr_or_ip|note
EOF
    fi
    mv -f "${tmp}" "${custom_file}"

    make_temp_file "${sets_file}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    write_allowlist_sets_file "${tmp}" || return 1
    mv -f "${tmp}" "${sets_file}"

    make_temp_file "${entries_file}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    if [[ -f "${ALLOWLIST_ENTRIES_FILE}" ]]; then
        cp -- "${ALLOWLIST_ENTRIES_FILE}" "${tmp}" || return 1
    else
        write_allowlist_entries_header "${tmp}"
    fi
    mv -f "${tmp}" "${entries_file}"

    make_temp_file "${sources_file}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    if [[ -f "${ALLOWLIST_SOURCES_FILE}" ]]; then
        cp -- "${ALLOWLIST_SOURCES_FILE}" "${tmp}" || return 1
    else
        write_allowlist_sources_header "${tmp}"
    fi
    mv -f "${tmp}" "${sources_file}"
    [[ "${quiet}" == "1" ]] || success "白名单配置档案已保存：${label:-${name}}"
}

save_allowlist_last_snapshot() {
    save_allowlist_profile_state "${ALLOWLIST_LAST_PROFILE_NAME}" 1 ""
}

read_allowlist_profile_metadata() {
    local name="$1"
    local env_file label_file line key raw_value value
    PROFILE_ENABLE_SRC_ALLOWLIST=""
    PROFILE_SRC_ALLOWLIST_MODE=""
    PROFILE_SRC_ALLOWLIST_REGION_IDS=""
    PROFILE_SAVED_AT=""
    PROFILE_LABEL=""
    env_file="$(allowlist_profile_env_file "${name}")"
    label_file="$(allowlist_profile_label_file "${name}")"
    [[ -f "${env_file}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        line="$(trim "${line}")"
        [[ -z "${line}" || "${line}" =~ ^# || "${line}" != *=* ]] && continue
        key="$(trim "${line%%=*}")"
        raw_value="${line#*=}"
        value="$(unquote_setting_value "${raw_value}")"
        case "${key}" in
            PROFILE_LABEL)
                PROFILE_LABEL="$(sanitize_profile_label "${value}")"
                ;;
            PROFILE_SAVED_AT)
                PROFILE_SAVED_AT="${value}"
                ;;
            ENABLE_SRC_ALLOWLIST)
                PROFILE_ENABLE_SRC_ALLOWLIST="${value}"
                ;;
            SRC_ALLOWLIST_MODE)
                PROFILE_SRC_ALLOWLIST_MODE="${value}"
                ;;
            SRC_ALLOWLIST_REGION_IDS)
                PROFILE_SRC_ALLOWLIST_REGION_IDS="${value}"
                ;;
        esac
    done < "${env_file}"
    if [[ -f "${label_file}" ]]; then
        IFS= read -r line < "${label_file}" || line=""
        PROFILE_LABEL="$(sanitize_profile_label "${line}")"
    fi
    [[ "${PROFILE_ENABLE_SRC_ALLOWLIST}" == "0" || "${PROFILE_ENABLE_SRC_ALLOWLIST}" == "1" ]] || PROFILE_ENABLE_SRC_ALLOWLIST="0"
    PROFILE_SRC_ALLOWLIST_MODE="$(normalize_src_allowlist_mode "${PROFILE_SRC_ALLOWLIST_MODE}" 2>/dev/null || printf 'trusted_dynamic')"
    PROFILE_SRC_ALLOWLIST_REGION_IDS="$(normalize_region_ids "${PROFILE_SRC_ALLOWLIST_REGION_IDS}")"
}

print_allowlist_profile_summary() {
    local name="$1"
    local display_name="${2:-$1}"
    local custom_file custom_count status_label saved_label
    read_allowlist_profile_metadata "${name}" || return 1
    if [[ -n "${PROFILE_LABEL}" && "${name}" != "${ALLOWLIST_LAST_PROFILE_NAME}" ]]; then
        display_name="${PROFILE_LABEL} (${name})"
    fi
    custom_file="$(allowlist_profile_custom_file "${name}")"
    custom_count="$(custom_allowlist_count_for_file "${custom_file}")"
    if [[ "${PROFILE_ENABLE_SRC_ALLOWLIST}" == "1" ]]; then
        status_label="$(src_allowlist_mode_to_label "${PROFILE_SRC_ALLOWLIST_MODE}")"
    else
        status_label="关闭"
    fi
    saved_label="${PROFILE_SAVED_AT:-未知时间}"
    printf '  - %-18s %s，地区 %s / 自定义 %s，保存于 %s\n' \
        "${display_name}" \
        "${status_label}" \
        "$(printf '%s\n' "${PROFILE_SRC_ALLOWLIST_REGION_IDS}" | wc -w | tr -d '[:space:]')" \
        "${custom_count}" \
        "${saved_label}"
}

show_allowlist_profiles() {
    local file name found=0
    if [[ ! -d "${ALLOWLIST_PROFILE_DIR}" ]]; then
        echo "  (未保存白名单配置档案)"
        return 0
    fi
    for file in "${ALLOWLIST_PROFILE_DIR}"/*.env; do
        [[ -f "${file}" ]] || continue
        name="$(basename "${file}" .env)"
        [[ "${name}" == "${ALLOWLIST_LAST_PROFILE_NAME}" ]] && continue
        print_allowlist_profile_summary "${name}" || continue
        found=1
    done
    [[ "${found}" == "1" ]] || echo "  (未保存白名单配置档案)"
    if allowlist_profile_exists "${ALLOWLIST_LAST_PROFILE_NAME}"; then
        echo "上一次快照:"
        print_allowlist_profile_summary "${ALLOWLIST_LAST_PROFILE_NAME}" "last" || true
    fi
}

select_allowlist_profile() {
    local file name choice idx=1 summary
    local -a names=()
    SELECTED_ALLOWLIST_PROFILE=""
    [[ -d "${ALLOWLIST_PROFILE_DIR}" ]] || {
        err "当前没有白名单配置档案。"
        return 1
    }
    for file in "${ALLOWLIST_PROFILE_DIR}"/*.env; do
        [[ -f "${file}" ]] || continue
        name="$(basename "${file}" .env)"
        [[ "${name}" == "${ALLOWLIST_LAST_PROFILE_NAME}" ]] && continue
        names+=("${name}")
    done
    [[ ${#names[@]} -gt 0 ]] || {
        err "当前没有白名单配置档案。"
        return 1
    }
    for name in "${names[@]}"; do
        summary="$(print_allowlist_profile_summary "${name}")"
        summary="${summary#  - }"
        printf '  %2d) %s\n' "${idx}" "${summary}"
        ((idx++))
    done
    read -r -p "请选择配置档案 [1-${#names[@]}]: " choice
    [[ "${choice}" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= ${#names[@]} )) || return 1
    SELECTED_ALLOWLIST_PROFILE="${names[$((choice - 1))]}"
}

apply_allowlist_profile() {
    local name="$1"
    local save_last="${2:-1}"
    local custom_file sets_file entries_file sources_file tmp
    read_allowlist_profile_metadata "${name}" || {
        err "配置档案不存在：${name}"
        return 1
    }
    if [[ "${save_last}" == "1" ]]; then
        save_allowlist_last_snapshot || return 1
    fi
    ENABLE_SRC_ALLOWLIST="${PROFILE_ENABLE_SRC_ALLOWLIST}"
    SRC_ALLOWLIST_MODE="${PROFILE_SRC_ALLOWLIST_MODE}"
    SRC_ALLOWLIST_REGION_IDS="${PROFILE_SRC_ALLOWLIST_REGION_IDS}"
    SETTINGS_CACHE_READY="1"
    custom_file="$(allowlist_profile_custom_file "${name}")"
    make_temp_file "${CUSTOM_SRC_ALLOWLIST_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    if [[ -f "${custom_file}" ]]; then
        cp -- "${custom_file}" "${tmp}" || return 1
    else
        cat > "${tmp}" <<'EOF'
# format: cidr_or_ip|note
EOF
    fi
    mv -f "${tmp}" "${CUSTOM_SRC_ALLOWLIST_FILE}"

    sets_file="$(allowlist_profile_sets_file "${name}")"
    if [[ -f "${sets_file}" ]]; then
        make_temp_file "${ALLOWLIST_SETS_FILE}" || return 1
        tmp="${TEMP_FILE_RESULT}"
        cp -- "${sets_file}" "${tmp}" || return 1
        mv -f "${tmp}" "${ALLOWLIST_SETS_FILE}"
        ALLOWLIST_SETS_CACHE_READY="0"
        load_allowlist_sets 1
    else
        ALLOWLIST_SETS=("$(default_allowlist_set_record)")
        ALLOWLIST_SETS_CACHE_READY="1"
        save_allowlist_sets || return 1
    fi

    entries_file="$(allowlist_profile_entries_file "${name}")"
    if [[ -f "${entries_file}" ]]; then
        make_temp_file "${ALLOWLIST_ENTRIES_FILE}" || return 1
        tmp="${TEMP_FILE_RESULT}"
        cp -- "${entries_file}" "${tmp}" || return 1
        mv -f "${tmp}" "${ALLOWLIST_ENTRIES_FILE}"
    else
        make_temp_file "${ALLOWLIST_ENTRIES_FILE}" || return 1
        tmp="${TEMP_FILE_RESULT}"
        write_allowlist_entries_header "${tmp}"
        mv -f "${tmp}" "${ALLOWLIST_ENTRIES_FILE}"
    fi

    sources_file="$(allowlist_profile_sources_file "${name}")"
    if [[ -f "${sources_file}" ]]; then
        make_temp_file "${ALLOWLIST_SOURCES_FILE}" || return 1
        tmp="${TEMP_FILE_RESULT}"
        cp -- "${sources_file}" "${tmp}" || return 1
        mv -f "${tmp}" "${ALLOWLIST_SOURCES_FILE}"
    else
        make_temp_file "${ALLOWLIST_SOURCES_FILE}" || return 1
        tmp="${TEMP_FILE_RESULT}"
        write_allowlist_sources_header "${tmp}"
        mv -f "${tmp}" "${ALLOWLIST_SOURCES_FILE}"
    fi

    apply_src_allowlist_changes
}

learning_service_status_label() {
    if ! command -v systemctl &>/dev/null; then
        printf '不可用（无 systemctl）'
        return 0
    fi
    if systemctl is-active --quiet "${LEARN_SERVICE_NAME}" 2>/dev/null; then
        printf '运行中'
    elif systemctl is-enabled --quiet "${LEARN_SERVICE_NAME}" 2>/dev/null; then
        printf '已安装，未运行'
    elif [[ -f "${LEARN_SERVICE_FILE}" ]]; then
        printf '已安装，未启用'
    else
        printf '未安装'
    fi
}

learning_log_count() {
    [[ -f "${LEARN_LOG_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    awk -F '\t' 'NF >= 10 { count++ } END { print count + 0 }' "${LEARN_LOG_FILE}" 2>/dev/null
}

learning_summary_count() {
    [[ -f "${LEARN_SUMMARY_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    awk -F '\t' 'NF >= 11 && $1 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ { count++ } END { print count + 0 }' "${LEARN_SUMMARY_FILE}" 2>/dev/null
}

learning_log_line_count() {
    [[ -f "${LEARN_LOG_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    wc -l < "${LEARN_LOG_FILE}" 2>/dev/null | tr -d '[:space:]'
}

learning_log_size_bytes() {
    [[ -f "${LEARN_LOG_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    wc -c < "${LEARN_LOG_FILE}" 2>/dev/null | tr -d '[:space:]'
}

format_bytes() {
    local bytes="$1"
    [[ "${bytes}" =~ ^[0-9]+$ ]] || bytes=0
    if (( bytes >= 1048576 )); then
        printf '%s MiB' "$(((bytes + 524288) / 1048576))"
    elif (( bytes >= 1024 )); then
        printf '%s KiB' "$(((bytes + 512) / 1024))"
    else
        printf '%s B' "${bytes}"
    fi
}

format_seconds() {
    local seconds="$1"
    [[ "${seconds}" =~ ^[0-9]+$ ]] || seconds=0
    if (( seconds >= 86400 )); then
        printf '%sd%02sh' "$((seconds / 86400))" "$(((seconds % 86400) / 3600))"
    elif (( seconds >= 3600 )); then
        printf '%sh%02sm' "$((seconds / 3600))" "$(((seconds % 3600) / 60))"
    elif (( seconds >= 60 )); then
        printf '%sm%02ss' "$((seconds / 60))" "$((seconds % 60))"
    else
        printf '%ss' "${seconds}"
    fi
}

format_learn_time() {
    local iso="$1"
    iso="${iso%Z}"
    iso="${iso/T/ }"
    printf '%s UTC' "${iso}"
}

tsv_safe() {
    local value="$1"
    value="${value//$'\t'/ }"
    value="${value//$'\r'/ }"
    value="${value//$'\n'/ }"
    printf '%s\n' "${value}"
}

ipdb_python_cmd() {
    if [[ -x "${IPDB_VENV_PYTHON}" ]]; then
        printf '%s\n' "${IPDB_VENV_PYTHON}"
        return 0
    fi
    command -v python3 2>/dev/null && return 0
    return 1
}

ipdb_lookup_ready() {
    local py
    [[ -f "${IPDB_FILE}" ]] || return 1
    py="$(ipdb_python_cmd)" || return 1
    "${py}" - "${IPDB_FILE}" <<'PY' >/dev/null 2>&1
import sys
try:
    import ipdb
    if not hasattr(ipdb, "City"):
        raise RuntimeError("ipip-ipdb parser not available")
    ipdb.City(sys.argv[1])
except Exception:
    sys.exit(1)
PY
}

ipdb_status_label() {
    local py
    if [[ ! -f "${IPDB_FILE}" ]]; then
        printf '未上传（%s）' "${IPDB_FILE}"
        return 0
    fi
    if ! py="$(ipdb_python_cmd)"; then
        printf '已上传，但缺少 python3'
        return 0
    fi
    if ! "${py}" - "${IPDB_FILE}" <<'PY' >/dev/null 2>&1
import sys
try:
    import ipdb
    if not hasattr(ipdb, "City"):
        raise RuntimeError("ipip-ipdb parser not available")
    ipdb.City(sys.argv[1])
except Exception:
    sys.exit(1)
PY
    then
        printf '已上传，但缺少 Python 包 ipip-ipdb'
        return 0
    fi
    printf '可用（%s，%s）' "${IPDB_FILE}" "${py}"
}

ipdb_lookup_ip() {
    local ip="$1"
    local ready="${2:-0}"
    local info py
    validate_ip "${ip}" || {
        printf '-'
        return 0
    }
    [[ "${ready}" == "1" ]] || {
        printf '-'
        return 0
    }
    if [[ -n "${IPDB_LOOKUP_CACHE[${ip}]+set}" ]]; then
        printf '%s' "${IPDB_LOOKUP_CACHE[${ip}]}"
        return 0
    fi
    py="$(ipdb_python_cmd)" || {
        printf '-'
        return 0
    }
    info="$(
        "${py}" - "${IPDB_FILE}" "${IPDB_LANGUAGE}" "${ip}" <<'PY' 2>/dev/null
import sys

path, lang, ip = sys.argv[1:4]

try:
    import ipdb
    db = ipdb.City(path)
    data = db.find_map(ip, lang)

    def pick(key):
        value = data.get(key, "")
        if value is None:
            return ""
        return str(value).strip()

    location = []
    for key in ("country_name", "region_name", "city_name", "district_name"):
        value = pick(key)
        if value and value not in location:
            location.append(value)

    network = []
    for key in ("isp_domain", "owner_domain"):
        value = pick(key)
        if value and value not in network:
            network.append(value)

    parts = []
    if location:
        parts.append("/".join(location))
    if network:
        parts.append(" ".join(network))
    print(" ".join(parts) if parts else "-")
except Exception:
    print("-")
PY
    )" || info="-"
    info="$(trim "${info}")"
    [[ -n "${info}" ]] || info="-"
    IPDB_LOOKUP_CACHE["${ip}"]="${info}"
    printf '%s' "${info}"
}

file_sha256_short() {
    local path="$1"
    [[ -f "${path}" ]] || {
        printf '-'
        return 0
    }
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${path}" 2>/dev/null | awk '{ print substr($1, 1, 16) }'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "${path}" 2>/dev/null | awk '{ print substr($1, 1, 16) }'
    else
        printf '-'
    fi
}

file_mtime_epoch() {
    local path="$1"
    [[ -f "${path}" ]] || {
        printf '-'
        return 0
    }
    stat -c '%Y' "${path}" 2>/dev/null || stat -f '%m' "${path}" 2>/dev/null || printf '-'
}

ipdb_snapshot_for_ip() {
    local ip="$1"
    local ready=0 info sha mtime lookup_at
    ipdb_lookup_ready && ready=1
    info="$(ipdb_lookup_ip "${ip}" "${ready}")"
    info="$(sanitize_allowlist_entry_text "${info}")"
    sha="$(file_sha256_short "${IPDB_FILE}")"
    mtime="$(file_mtime_epoch "${IPDB_FILE}")"
    lookup_at="$(utc_now_iso)"
    printf 'ipdb_sha=%s;ipdb_mtime=%s;lookup_at=%s;geo=%s\n' "${sha}" "${mtime}" "${lookup_at}" "${info:-legacy/no snapshot}"
}

reload_learning_rules_if_needed() {
    local now
    now="$(date '+%s')"
    if (( now - LEARN_RULES_RELOAD_TS >= 60 )); then
        load_settings 1
        load_rules 1
        LEARN_RULES_RELOAD_TS="${now}"
    fi
}

find_learning_rule_match() {
    local proto="$1"
    local listen_port="$2"
    local reply_src="${3:-}"
    local reply_sport="${4:-}"
    local rule
    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        [[ "${RULE_ENABLED}" == "1" ]] || continue
        protocols_overlap "${RULE_PROTO}" "${proto}" || continue
        [[ "${RULE_LPORT}" == "${listen_port}" ]] || continue
        if [[ -n "${reply_src}" && "${reply_src}" != "${RULE_DIP}" ]]; then
            continue
        fi
        if [[ -n "${reply_sport}" && "${reply_sport}" != "${RULE_DPORT}" ]]; then
            continue
        fi
        return 0
    done
    return 1
}

append_learning_event() {
    local src_ip="$1"
    local proto="$2"
    local listen_port="$3"
    local source_port="$4"
    local ts iso current_day snapshot
    ts="$(date '+%s')"
    iso="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    current_day="${iso:0:10}"
    snapshot="$(ipdb_snapshot_for_ip "${src_ip}")"
    mkdir -p "${CONF_DIR}" || return 1
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${ts}" \
        "${iso}" \
        "${src_ip}" \
        "${proto}" \
        "${listen_port}" \
        "${source_port}" \
        "$(tsv_safe "${RULE_ID}")" \
        "$(tsv_safe "${RULE_NAME}")" \
        "${RULE_DIP}" \
        "${RULE_DPORT}" \
        "$(tsv_safe "${snapshot}")" >> "${LEARN_LOG_FILE}"
    ((LEARN_APPEND_COUNT++))
    if [[ -n "${LEARN_LAST_COMPACT_DAY}" && "${current_day}" != "${LEARN_LAST_COMPACT_DAY}" ]]; then
        LEARN_LAST_COMPACT_DAY="${current_day}"
        compact_learning_log_if_needed "daily" || true
        return 0
    fi
    [[ -n "${LEARN_LAST_COMPACT_DAY}" ]] || LEARN_LAST_COMPACT_DAY="${current_day}"
    if (( LEARN_APPEND_COUNT % LEARN_COMPACT_CHECK_INTERVAL == 0 )); then
        compact_learning_log_if_needed "auto" || true
    fi
}

update_learning_daily_ip_counts() {
    local path="$1"
    local tmp existing_daily_ip_file
    [[ -s "${path}" ]] || return 0
    mkdir -p "${CONF_DIR}" || return 1
    make_temp_file "${LEARN_DAILY_IP_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    existing_daily_ip_file="${LEARN_DAILY_IP_FILE}"
    [[ -f "${existing_daily_ip_file}" ]] || existing_daily_ip_file="/dev/null"
    awk -F '\t' '
        function add(day, ip, n, first_iso, last_iso, key) {
            if (day == "" || ip == "" || n <= 0) {
                return
            }
            key = day SUBSEP ip
            count[key] += n
            if (!(key in first) || first_iso < first[key]) {
                first[key] = first_iso
            }
            if (!(key in last) || last_iso > last[key]) {
                last[key] = last_iso
            }
        }
        FILENAME == ARGV[1] {
            if (NF >= 5 && $1 !~ /^#/) {
                add($1, $2, $3 + 0, $4, $5)
            }
            next
        }
        NF >= 10 {
            add(substr($2, 1, 10), $3, 1, $2, $2)
        }
        END {
            for (key in count) {
                split(key, part, SUBSEP)
                print part[1] "\t" part[2] "\t" count[key] "\t" first[key] "\t" last[key]
            }
        }
    ' "${existing_daily_ip_file}" "${path}" 2>/dev/null | sort -t "$(printf '\t')" -k1,1 -k2,2 > "${tmp}"
    {
        printf '%s\n' '# format: day<TAB>ip<TAB>count<TAB>first_event_iso<TAB>last_event_iso'
        cat "${tmp}"
    } > "${tmp}.with_header"
    mv -f "${tmp}.with_header" "${LEARN_DAILY_IP_FILE}"
}

learning_daily_top_values() {
    local mode="$1"
    local limit="${2:-20}"
    [[ -s "${LEARN_DAILY_IP_FILE}" ]] || return 0
    awk -F '\t' -v mode="${mode}" '
        NF >= 5 && $1 !~ /^#/ {
            day = $1
            item = $2
            if (mode == "net24") {
                split($2, o, ".")
                item = o[1] "." o[2] "." o[3] ".0/24"
            } else if (mode == "net16") {
                split($2, o, ".")
                item = o[1] "." o[2] ".0.0/16"
            }
            count[day SUBSEP item] += $3
        }
        END {
            for (key in count) {
                split(key, part, SUBSEP)
                print part[1] "\t" part[2] "\t" count[key]
            }
        }
    ' "${LEARN_DAILY_IP_FILE}" \
        | sort -t "$(printf '\t')" -k1,1 -k3,3nr \
        | awk -F '\t' -v limit="${limit}" '
            current != $1 {
                if (current != "") {
                    print current "\t" out
                }
                current = $1
                out = ""
                n = 0
            }
            n < limit {
                item = $2 "=" $3
                out = out ? out ";" item : item
                n++
            }
            END {
                if (current != "") {
                    print current "\t" out
                }
            }
        '
}

regenerate_learning_daily_summary() {
    local stats_tmp top_ip_tmp top_24_tmp top_16_tmp tmp
    [[ -s "${LEARN_DAILY_IP_FILE}" ]] || return 0
    make_temp_file "${LEARN_SUMMARY_FILE}.stats" || return 1
    stats_tmp="${TEMP_FILE_RESULT}"
    make_temp_file "${LEARN_SUMMARY_FILE}.top_ip" || return 1
    top_ip_tmp="${TEMP_FILE_RESULT}"
    make_temp_file "${LEARN_SUMMARY_FILE}.top24" || return 1
    top_24_tmp="${TEMP_FILE_RESULT}"
    make_temp_file "${LEARN_SUMMARY_FILE}.top16" || return 1
    top_16_tmp="${TEMP_FILE_RESULT}"
    make_temp_file "${LEARN_SUMMARY_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    awk -F '\t' '
        NF >= 5 && $1 !~ /^#/ {
            day = $1
            ip = $2
            events[day] += $3
            if (!(day in first) || $4 < first[day]) {
                first[day] = $4
            }
            if (!(day in last) || $5 > last[day]) {
                last[day] = $5
            }
            unique_ip[day]++
            split(ip, o, ".")
            net24 = o[1] "." o[2] "." o[3] ".0/24"
            net16 = o[1] "." o[2] ".0.0/16"
            if (!seen_24[day SUBSEP net24]++) {
                unique_24[day]++
            }
            if (!seen_16[day SUBSEP net16]++) {
                unique_16[day]++
            }
        }
        END {
            for (day in events) {
                print day "\t" events[day] "\t" first[day] "\t" last[day] "\t" unique_ip[day] "\t" unique_24[day] "\t" unique_16[day]
            }
        }
    ' "${LEARN_DAILY_IP_FILE}" | sort -t "$(printf '\t')" -k1,1 > "${stats_tmp}"
    learning_daily_top_values ip 20 > "${top_ip_tmp}"
    learning_daily_top_values net24 20 > "${top_24_tmp}"
    learning_daily_top_values net16 20 > "${top_16_tmp}"
    awk -F '\t' -v updated="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" '
        FILENAME == ARGV[1] { top_ip[$1] = $2; next }
        FILENAME == ARGV[2] { top_24[$1] = $2; next }
        FILENAME == ARGV[3] { top_16[$1] = $2; next }
        {
            print $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6 "\t" $7 "\t" top_ip[$1] "\t" top_24[$1] "\t" top_16[$1] "\t" updated
        }
    ' "${top_ip_tmp}" "${top_24_tmp}" "${top_16_tmp}" "${stats_tmp}" > "${tmp}"
    {
        printf '%s\n' '# format: day<TAB>events<TAB>first_event_iso<TAB>last_event_iso<TAB>unique_ips<TAB>unique_24s<TAB>unique_16s<TAB>top_ips<TAB>top_24s<TAB>top_16s<TAB>updated_iso'
        cat "${tmp}"
    } > "${tmp}.with_header"
    mv -f "${tmp}.with_header" "${LEARN_SUMMARY_FILE}"
}

archive_learning_events() {
    local path="$1"
    [[ -s "${path}" ]] || return 0
    update_learning_daily_ip_counts "${path}" || return 1
    regenerate_learning_daily_summary || return 1
}

compact_learning_log_if_needed() {
    local reason="${1:-auto}"
    local size total overflow today archive_tmp keep_tmp archived_count
    [[ -s "${LEARN_LOG_FILE}" ]] || return 0
    size="$(learning_log_size_bytes)"
    total="$(learning_log_line_count)"
    [[ "${size}" =~ ^[0-9]+$ ]] || size=0
    [[ "${total}" =~ ^[0-9]+$ ]] || total=0
    overflow=0
    if (( total > LEARN_LOG_KEEP_LINES )); then
        overflow=$((total - LEARN_LOG_KEEP_LINES))
    elif (( size > LEARN_LOG_MAX_BYTES )); then
        overflow=$((total / 2))
    fi
    today="$(date -u '+%Y-%m-%d')"
    make_temp_file "${LEARN_LOG_FILE}.archive" || return 1
    archive_tmp="${TEMP_FILE_RESULT}"
    make_temp_file "${LEARN_LOG_FILE}.keep" || return 1
    keep_tmp="${TEMP_FILE_RESULT}"
    awk -F '\t' -v today="${today}" -v overflow="${overflow}" -v archive_path="${archive_tmp}" -v keep_path="${keep_tmp}" '
        NF >= 10 {
            event_day = substr($2, 1, 10)
            if (event_day < today || NR <= overflow) {
                print > archive_path
                next
            }
        }
        {
            print > keep_path
        }
    ' "${LEARN_LOG_FILE}" || return 1
    archived_count="$(awk 'END { print NR + 0 }' "${archive_tmp}" 2>/dev/null)"
    [[ "${archived_count}" =~ ^[0-9]+$ ]] || archived_count=0
    (( archived_count > 0 )) || {
        rm -f -- "${archive_tmp}" "${keep_tmp}" 2>/dev/null || true
        return 0
    }
    archive_learning_events "${archive_tmp}" || return 1
    mv -f "${keep_tmp}" "${LEARN_LOG_FILE}"
    rm -f -- "${archive_tmp}" 2>/dev/null || true
}

process_conntrack_event() {
    local line="$1"
    local proto=""
    local token key value
    local orig_src="" orig_dst="" orig_sport="" orig_dport=""
    local reply_src="" reply_dst="" reply_sport="" reply_dport=""
    local src_seen=0 dst_seen=0 sport_seen=0 dport_seen=0

    [[ "${line}" == *ASSURED* ]] || return 0
    if [[ "${line}" =~ (^|[[:space:]])tcp[[:space:]] ]]; then
        proto="tcp"
    elif [[ "${line}" =~ (^|[[:space:]])udp[[:space:]] ]]; then
        proto="udp"
    else
        return 0
    fi

    for token in ${line}; do
        [[ "${token}" == *=* ]] || continue
        key="${token%%=*}"
        value="${token#*=}"
        value="${value%,}"
        case "${key}" in
            src)
                if (( src_seen == 0 )); then
                    orig_src="${value}"
                elif (( src_seen == 1 )); then
                    reply_src="${value}"
                fi
                ((src_seen++))
                ;;
            dst)
                if (( dst_seen == 0 )); then
                    orig_dst="${value}"
                elif (( dst_seen == 1 )); then
                    reply_dst="${value}"
                fi
                ((dst_seen++))
                ;;
            sport)
                if (( sport_seen == 0 )); then
                    orig_sport="${value}"
                elif (( sport_seen == 1 )); then
                    reply_sport="${value}"
                fi
                ((sport_seen++))
                ;;
            dport)
                if (( dport_seen == 0 )); then
                    orig_dport="${value}"
                elif (( dport_seen == 1 )); then
                    reply_dport="${value}"
                fi
                ((dport_seen++))
                ;;
        esac
    done

    is_public_ipv4 "${orig_src}" || return 0
    validate_port "${orig_dport}" || return 0
    validate_port "${orig_sport}" || orig_sport=""
    reload_learning_rules_if_needed
    find_learning_rule_match "${proto}" "${orig_dport}" "${reply_src}" "${reply_sport}" || return 0
    append_learning_event "${orig_src}" "${proto}" "${orig_dport}" "${orig_sport}"
}

run_learning_service() {
    check_root
    ensure_layout || exit 1
    command -v conntrack &>/dev/null || {
        err "学习服务需要 conntrack，请先安装 conntrack。"
        exit 1
    }
    load_settings 1
    load_rules 1
    LEARN_RULES_RELOAD_TS="$(date '+%s')"
    compact_learning_log_if_needed "startup" || true
    LEARN_LAST_COMPACT_DAY="$(date -u '+%Y-%m-%d')"
    info "来源 IP 学习服务已启动，只记录已完成双向转发的公网来源 IP。"
    conntrack -E 2>/dev/null | while IFS= read -r line; do
        process_conntrack_event "${line}"
    done
}

current_script_path() {
    if command -v readlink &>/dev/null; then
        readlink -f "$0" 2>/dev/null && return 0
    fi
    if command -v realpath &>/dev/null; then
        realpath "$0" 2>/dev/null && return 0
    fi
    printf '%s\n' "$0"
}

shell_quote() {
    local quoted
    printf -v quoted '%q' "$1"
    printf '%s' "${quoted}"
}

is_transient_script_path() {
    local path="$1"
    [[ -n "${path}" ]] || return 0
    [[ -f "${path}" ]] || return 0
    case "${path}" in
        /dev/fd/*|/proc/*/fd/*|/tmp/*|/var/tmp/*)
            return 0
            ;;
    esac
    return 1
}

install_manager_self() {
    local target="${1:-${MANAGER_INSTALL_PATH}}"
    local source tmp
    source="$(current_script_path 2>/dev/null || true)"
    if [[ -n "${source}" && "${source}" == "${target}" && -f "${target}" ]]; then
        chmod 0755 "${target}" 2>/dev/null || true
        printf '%s\n' "${target}"
        return 0
    fi
    mkdir -p "$(dirname "${target}")" || return 1
    tmp="${target}.tmp.$$"
    if [[ -n "${source}" ]] && ! is_transient_script_path "${source}"; then
        cp -- "${source}" "${tmp}" || return 1
    else
        err "当前脚本来自 stdin/临时路径，不能可靠落盘。请先把 nftables-relay-manager.sh 上传到 ${target} 后再运行。"
        rm -f -- "${tmp}" 2>/dev/null || true
        return 1
    fi
    chmod 0755 "${tmp}" || {
        rm -f -- "${tmp}" 2>/dev/null || true
        return 1
    }
    mv -f -- "${tmp}" "${target}" || return 1
    printf '%s\n' "${target}"
}

ensure_persistent_manager_script() {
    local source
    source="$(current_script_path 2>/dev/null || true)"
    if [[ -n "${source}" ]] && ! is_transient_script_path "${source}"; then
        printf '%s\n' "${source}"
        return 0
    fi
    warn "当前主控脚本来自临时路径，安装 cron 前需要先落盘。" >&2
    install_manager_self "${MANAGER_INSTALL_PATH}"
}

write_learning_runner() {
    local script_path escaped_path tmp
    script_path="$(current_script_path)" || return 1
    printf -v escaped_path '%q' "${script_path}"
    tmp="${LEARN_RUNNER}.tmp.$$"
    mkdir -p "$(dirname "${LEARN_RUNNER}")" || return 1
    cat > "${tmp}" <<EOF
#!/usr/bin/env bash
exec /usr/bin/env bash ${escaped_path} --learn-service
EOF
    chmod 0755 "${tmp}" || return 1
    mv -f "${tmp}" "${LEARN_RUNNER}"
}

write_learning_service_unit() {
    cat > "${LEARN_SERVICE_FILE}" <<EOF
[Unit]
Description=nftables relay source IP learning service
After=network-online.target nftables.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=${LEARN_RUNNER}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

enable_learning_service() {
    command -v systemctl &>/dev/null || {
        err "系统缺少 systemctl，无法安装学习服务。"
        return 1
    }
    install_conntrack_if_needed || return 1
    write_learning_runner || return 1
    write_learning_service_unit || return 1
    systemctl daemon-reload || return 1
    systemctl enable --now "${LEARN_SERVICE_NAME}" || return 1
}

disable_learning_service() {
    command -v systemctl &>/dev/null || {
        err "系统缺少 systemctl。"
        return 1
    }
    systemctl disable --now "${LEARN_SERVICE_NAME}" 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
}

learned_ip_candidates() {
    [[ -s "${LEARN_LOG_FILE}" ]] || return 0
    awk -F '\t' '
        NF >= 10 {
            ip = $3
            count[ip]++
            if (!(ip in first_epoch) || $1 < first_epoch[ip]) {
                first_epoch[ip] = $1
                first_iso[ip] = $2
            }
            if (!(ip in last_epoch) || $1 > last_epoch[ip]) {
                last_epoch[ip] = $1
                last_iso[ip] = $2
            }
            key = $4 "/" $5
            if (ports[ip] == "") {
                ports[ip] = key
            } else if (index("," ports[ip] ",", "," key ",") == 0) {
                ports[ip] = ports[ip] "," key
            }
        }
        END {
            for (ip in count) {
                span = last_epoch[ip] - first_epoch[ip]
                print ip "\t" count[ip] "\t" span "\t" first_iso[ip] "\t" last_iso[ip] "\t" ports[ip]
            }
        }
    ' "${LEARN_LOG_FILE}" | sort -t "$(printf '\t')" -k2,2nr -k5,5r
}

qualified_learned_ip_candidates() {
    learned_ip_candidates | awk -F '\t' \
        -v min_hits="${LEARN_IP_MIN_HITS}" \
        -v min_span="${LEARN_IP_MIN_SPAN_SECONDS}" \
        '($2 >= min_hits) || ($2 >= 2 && $3 >= min_span)'
}

learned_cidr24_candidates() {
    [[ -s "${LEARN_LOG_FILE}" ]] || return 0
    awk -F '\t' '
        NF >= 10 {
            split($3, o, ".")
            net = o[1] "." o[2] "." o[3] ".0/24"
            total[net]++
            if (!seen[net SUBSEP $3]++) unique[net]++
            if (!(net in first_epoch) || $1 < first_epoch[net]) {
                first_epoch[net] = $1
                first_iso[net] = $2
            }
            if (!(net in last_epoch) || $1 > last_epoch[net]) {
                last_epoch[net] = $1
                last_iso[net] = $2
            }
        }
        END {
            for (net in total) {
                if (unique[net] >= 2 || total[net] >= 3) {
                    span = last_epoch[net] - first_epoch[net]
                    print net "\t" unique[net] "\t" total[net] "\t" span "\t" first_iso[net] "\t" last_iso[net]
                }
            }
        }
    ' "${LEARN_LOG_FILE}" | sort -t "$(printf '\t')" -k2,2nr -k3,3nr -k6,6r
}

qualified_learned_cidr24_candidates() {
    learned_cidr24_candidates | awk -F '\t' \
        -v min_hits="${LEARN_NET24_MIN_HITS}" \
        -v min_unique="${LEARN_NET24_MIN_UNIQUE_IPS}" \
        '($2 >= min_unique) || ($3 >= min_hits)'
}

learned_cidr16_candidates() {
    [[ -s "${LEARN_LOG_FILE}" ]] || return 0
    awk -F '\t' '
        NF >= 10 {
            split($3, o, ".")
            net = o[1] "." o[2] ".0.0/16"
            net24 = o[1] "." o[2] "." o[3] ".0/24"
            total[net]++
            if (!seen_ip[net SUBSEP $3]++) unique_ip[net]++
            if (!seen_net24[net SUBSEP net24]++) unique_24[net]++
            if (!(net in first_epoch) || $1 < first_epoch[net]) {
                first_epoch[net] = $1
                first_iso[net] = $2
            }
            if (!(net in last_epoch) || $1 > last_epoch[net]) {
                last_epoch[net] = $1
                last_iso[net] = $2
            }
        }
        END {
            for (net in total) {
                span = last_epoch[net] - first_epoch[net]
                print net "\t" unique_ip[net] "\t" unique_24[net] "\t" total[net] "\t" span "\t" first_iso[net] "\t" last_iso[net]
            }
        }
    ' "${LEARN_LOG_FILE}" | sort -t "$(printf '\t')" -k3,3nr -k2,2nr -k4,4nr -k7,7r
}

qualified_learned_cidr16_candidates() {
    learned_cidr16_candidates | awk -F '\t' \
        -v min_hits="${LEARN_NET16_MIN_HITS}" \
        -v min_unique_24="${LEARN_NET16_MIN_UNIQUE_24S}" \
        '($3 >= min_unique_24) || ($4 >= min_hits)'
}

print_learning_daily_summary() {
    local row idx=1
    local day events first last unique_ips unique_24s unique_16s top_ips top_24s top_16s updated
    local -a rows=()
    [[ -s "${LEARN_SUMMARY_FILE}" ]] || return 0
    mapfile -t rows < <(awk -F '\t' 'NF >= 11 && $1 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ { print }' "${LEARN_SUMMARY_FILE}" | tail -n 7)
    [[ ${#rows[@]} -gt 0 ]] || return 0
    echo ""
    echo "每日历史汇总（最近 7 天）："
    for row in "${rows[@]}"; do
        IFS=$'\t' read -r day events first last unique_ips unique_24s unique_16s top_ips top_24s top_16s updated <<< "${row}"
        printf '  [%d] %s | 归档 %s 条 | 来源 IP %s 个 | /24 %s 个 | /16 %s 个\n' \
            "${idx}" "${day}" "${events}" "${unique_ips}" "${unique_24s}" "${unique_16s}"
        printf '      事件时间: %s -> %s\n' "$(format_learn_time "${first}")" "$(format_learn_time "${last}")"
        [[ -n "${top_ips}" ]] && printf '      Top IP: %s\n' "${top_ips}"
        [[ -n "${top_24s}" ]] && printf '      Top /24: %s\n' "${top_24s}"
        ((idx++))
    done
}

print_learning_stats() {
    local row idx=1
    local ipdb_ready=0 ip_info
    local -a rows=()
    ipdb_lookup_ready && ipdb_ready=1
    printf '学习日志   : %s（%s 条事件，%s）\n' \
        "${LEARN_LOG_FILE}" "$(learning_log_count)" "$(format_bytes "$(learning_log_size_bytes)")"
    printf '每日汇总   : %s（%s 天）\n' "${LEARN_SUMMARY_FILE}" "$(learning_summary_count)"
    printf '自动压缩   : 跨 UTC 日期归档；或超过 %s / %s 行时保留最近 %s 行；每 %s 条做一次大小兜底检查\n' \
        "$(format_bytes "${LEARN_LOG_MAX_BYTES}")" "${LEARN_LOG_KEEP_LINES}" "${LEARN_LOG_KEEP_LINES}" \
        "${LEARN_COMPACT_CHECK_INTERVAL}"
    printf 'IPDB 数据  : %s\n' "$(ipdb_status_label)"
    if [[ ! -s "${LEARN_LOG_FILE}" ]]; then
        echo "  (暂无学习记录)"
        print_learning_daily_summary
        return 0
    fi
    echo ""
    echo "来源 IP 统计："
    mapfile -t rows < <(learned_ip_candidates | head -n 30)
    if [[ ${#rows[@]} -eq 0 ]]; then
        echo "  (暂无可用来源 IP)"
    else
        for row in "${rows[@]}"; do
            IFS=$'\t' read -r SELECTED_LEARN_CIDR count span first last ports <<< "${row}"
            ip_info="$(ipdb_lookup_ip "${SELECTED_LEARN_CIDR}" "${ipdb_ready}")"
            printf '  [%d] %s | 命中 %s 次 | 观察 %s | %s\n' \
                "${idx}" "${SELECTED_LEARN_CIDR}" "${count}" "$(format_seconds "${span}")" "${ip_info}"
            printf '      时间: %s -> %s | 中转机监听端口: %s\n' \
                "$(format_learn_time "${first}")" "$(format_learn_time "${last}")" "${ports}"
            ((idx++))
        done
    fi

    echo ""
    echo "/24 候选网段："
    idx=1
    mapfile -t rows < <(learned_cidr24_candidates | head -n 20)
    if [[ ${#rows[@]} -eq 0 ]]; then
        echo "  (暂无 /24 候选)"
    else
        for row in "${rows[@]}"; do
            IFS=$'\t' read -r cidr unique total span first last <<< "${row}"
            printf '  [%d] %s | 来源 IP %s 个 | 命中 %s 次 | 观察 %s\n' \
                "${idx}" "${cidr}" "${unique}" "${total}" "$(format_seconds "${span}")"
            printf '      时间: %s -> %s\n' "$(format_learn_time "${first}")" "$(format_learn_time "${last}")"
            ((idx++))
        done
    fi

    echo ""
    echo "/16 候选网段（高风险）："
    idx=1
    mapfile -t rows < <(learned_cidr16_candidates | head -n 20)
    if [[ ${#rows[@]} -eq 0 ]]; then
        echo "  (暂无 /16 候选)"
    else
        for row in "${rows[@]}"; do
            IFS=$'\t' read -r cidr unique unique24 total span first last <<< "${row}"
            printf '  [%d] %s | 来源 IP %s 个 | 覆盖 /24 %s 个 | 命中 %s 次 | 观察 %s\n' \
                "${idx}" "${cidr}" "${unique}" "${unique24}" "${total}" "$(format_seconds "${span}")"
            printf '      时间: %s -> %s\n' "$(format_learn_time "${first}")" "$(format_learn_time "${last}")"
            ((idx++))
        done
    fi
    print_learning_daily_summary
}

select_learned_ip_candidate() {
    local choice row ip count span first last ports
    local ipdb_ready=0 ip_info
    local -a rows=()
    SELECTED_LEARN_CIDR=""
    SELECTED_LEARN_NOTE=""
    ipdb_lookup_ready && ipdb_ready=1
    mapfile -t rows < <(qualified_learned_ip_candidates | head -n 50)
    [[ ${#rows[@]} -gt 0 ]] || {
        err "暂无达到门槛的学习 IP（至少 ${LEARN_IP_MIN_HITS} 次，或 2 次且跨度 >= $(format_seconds "${LEARN_IP_MIN_SPAN_SECONDS}")）。"
        return 1
    }
    local idx=1
    for row in "${rows[@]}"; do
        IFS=$'\t' read -r ip count span first last ports <<< "${row}"
        ip_info="$(ipdb_lookup_ip "${ip}" "${ipdb_ready}")"
        printf '  [%d] %s | 命中 %s 次 | 观察 %s | %s\n' \
            "${idx}" "${ip}" "${count}" "$(format_seconds "${span}")" "${ip_info}"
        printf '      最近: %s | 中转机监听端口: %s\n' "$(format_learn_time "${last}")" "${ports}"
        ((idx++))
    done
    read -r -p "请选择要加入自定义白名单的 IP [1-${#rows[@]}]: " choice
    [[ "${choice}" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= ${#rows[@]} )) || return 1
    IFS=$'\t' read -r ip count span first last ports <<< "${rows[$((choice - 1))]}"
    SELECTED_LEARN_CIDR="${ip}/32"
    SELECTED_LEARN_NOTE="learned hits=${count}, span=$(format_seconds "${span}"), last=${last}, ports=${ports}"
}

select_learned_cidr24_candidate() {
    local choice row cidr unique total span first last
    local -a rows=()
    SELECTED_LEARN_CIDR=""
    SELECTED_LEARN_NOTE=""
    mapfile -t rows < <(qualified_learned_cidr24_candidates | head -n 50)
    [[ ${#rows[@]} -gt 0 ]] || {
        err "暂无达到门槛的 /24 候选（至少 ${LEARN_NET24_MIN_UNIQUE_IPS} 个 IP，或 ${LEARN_NET24_MIN_HITS} 次命中）。"
        return 1
    }
    local idx=1
    for row in "${rows[@]}"; do
        IFS=$'\t' read -r cidr unique total span first last <<< "${row}"
        printf '  [%d] %s | 来源 IP %s 个 | 命中 %s 次 | 观察 %s | 最近 %s\n' \
            "${idx}" "${cidr}" "${unique}" "${total}" "$(format_seconds "${span}")" "$(format_learn_time "${last}")"
        ((idx++))
    done
    read -r -p "请选择要加入自定义白名单的 /24 网段 [1-${#rows[@]}]: " choice
    [[ "${choice}" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= ${#rows[@]} )) || return 1
    IFS=$'\t' read -r cidr unique total span first last <<< "${rows[$((choice - 1))]}"
    SELECTED_LEARN_CIDR="${cidr}"
    SELECTED_LEARN_NOTE="learned /24 unique=${unique}, hits=${total}, span=$(format_seconds "${span}"), last=${last}"
}

select_learned_cidr16_candidate() {
    local choice row cidr unique unique24 total span first last
    local -a rows=()
    SELECTED_LEARN_CIDR=""
    SELECTED_LEARN_NOTE=""
    mapfile -t rows < <(qualified_learned_cidr16_candidates | head -n 50)
    [[ ${#rows[@]} -gt 0 ]] || {
        err "暂无达到门槛的 /16 候选（至少 ${LEARN_NET16_MIN_UNIQUE_24S} 个 /24，或 ${LEARN_NET16_MIN_HITS} 次命中）。"
        return 1
    }
    local idx=1
    for row in "${rows[@]}"; do
        IFS=$'\t' read -r cidr unique unique24 total span first last <<< "${row}"
        printf '  [%d] %s | 来源 IP %s 个 | 覆盖 /24 %s 个 | 命中 %s 次 | 观察 %s | 最近 %s\n' \
            "${idx}" "${cidr}" "${unique}" "${unique24}" "${total}" "$(format_seconds "${span}")" "$(format_learn_time "${last}")"
        ((idx++))
    done
    read -r -p "请选择要加入自定义白名单的 /16 网段 [1-${#rows[@]}]: " choice
    [[ "${choice}" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= ${#rows[@]} )) || return 1
    IFS=$'\t' read -r cidr unique unique24 total span first last <<< "${rows[$((choice - 1))]}"
    SELECTED_LEARN_CIDR="${cidr}"
    SELECTED_LEARN_NOTE="learned /16 unique_ip=${unique}, unique_24=${unique24}, hits=${total}, span=$(format_seconds "${span}"), last=${last}"
}

iplist_ready() {
    [[ -f "${IPLIST_DOC}" && -f "${IPLIST_MANIFEST}" ]]
}

iplist_region_record() {
    local id="$1"
    [[ -f "${IPLIST_MANIFEST}" ]] || return 1
    awk -F '\t' -v id="${id}" '$1 == id { print; exit }' "${IPLIST_MANIFEST}"
}

iplist_region_label() {
    local id="$1"
    local record name rel
    record="$(iplist_region_record "${id}" || true)"
    if [[ -n "${record}" ]]; then
        IFS=$'\t' read -r _ name rel _ <<< "${record}"
        printf '%s (%s)' "${name}" "${id}"
    else
        printf '%s (missing)' "${id}"
    fi
}

build_iplist_manifest_for_dir() {
    local root="$1"
    local doc="${root}/docs/cncity.md"
    local manifest="${root}/manifest.tsv"
    local tmp
    [[ -f "${doc}" ]] || {
        err "iplist 包缺少 docs/cncity.md。"
        return 1
    }
    make_temp_file "${manifest}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    awk -F '|' '
        function trim_value(s) {
            gsub(/^[ \t\r\n]+/, "", s)
            gsub(/[ \t\r\n]+$/, "", s)
            return s
        }
        NF >= 3 {
            name = trim_value($2)
            url = trim_value($3)
            if (name == "" || url == "" || url == "无") next
            if (url !~ /^https?:\/\// || url !~ /\.txt$/) next
            rel = url
            sub(/^.*\/iplist\//, "", rel)
            if (rel !~ /^data\/cncity\//) {
                sub(/^.*\/data\/cncity\//, "data/cncity/", rel)
            }
            if (rel !~ /^data\/cncity\//) next
            id = rel
            sub(/^.*\//, "", id)
            sub(/\.txt$/, "", id)
            gsub(/[^A-Za-z0-9._-]/, "_", id)
            print id "\t" name "\t" rel "\t" url
        }
    ' "${doc}" | sort -u > "${tmp}"
    [[ -s "${tmp}" ]] || {
        err "无法从 cncity.md 解析出地区列表。"
        return 1
    }
    while IFS=$'\t' read -r _ _ rel _; do
        [[ -f "${root}/${rel}" ]] || {
            err "iplist 包缺少数据文件：${rel}"
            return 1
        }
    done < "${tmp}"
    mv -f "${tmp}" "${manifest}"
}

import_iplist_package() {
    local package="$1"
    local tmpdir olddir ts
    package="$(trim "${package}")"
    [[ -f "${package}" ]] || {
        err "文件不存在：${package}"
        return 1
    }
    command -v tar &>/dev/null || {
        err "系统缺少 tar，无法解压 iplist 包。"
        return 1
    }
    make_temp_dir "${CONF_DIR}" "po0-iplist.import" || return 1
    tmpdir="${TEMP_DIR_RESULT}"
    case "${package}" in
        *.tar.gz|*.tgz)
            tar -xzf "${package}" -C "${tmpdir}" || return 1
            ;;
        *.tar)
            tar -xf "${package}" -C "${tmpdir}" || return 1
            ;;
        *)
            err "仅支持 .tar.gz、.tgz 或 .tar 格式。"
            return 1
            ;;
    esac
    [[ -f "${tmpdir}/docs/cncity.md" ]] || {
        err "压缩包根目录必须包含 docs/cncity.md。"
        return 1
    }
    build_iplist_manifest_for_dir "${tmpdir}" || return 1

    ts="$(date '+%Y%m%d_%H%M%S')"
    olddir="${IPLIST_DIR}.old.${ts}"
    [[ -d "${olddir}" ]] && rm -rf -- "${olddir}"
    [[ -d "${IPLIST_DIR}" ]] && mv "${IPLIST_DIR}" "${olddir}"
    mv "${tmpdir}" "${IPLIST_DIR}" || {
        [[ -d "${olddir}" ]] && mv "${olddir}" "${IPLIST_DIR}" 2>/dev/null || true
        return 1
    }
    TEMP_DIRS=("${TEMP_DIRS[@]/${tmpdir}/}")
    [[ -d "${olddir}" ]] && rm -rf -- "${olddir}"
    success "iplist 离线包已导入。"
}

resource_task_write_header() {
    local path="$1"
    cat > "${path}" <<'EOF'
# format: id|type|status|created_at|claimed_at|finished_at|worker_id|artifact_path|sha256|size|message
EOF
}

ensure_resource_task_layout() {
    mkdir -p "${CONF_DIR}" "${RESOURCE_INBOX_DIR}" || return 1
    chmod 700 "${RESOURCE_INBOX_DIR}" 2>/dev/null || true
    if [[ ! -f "${RESOURCE_TASKS_FILE}" ]]; then
        resource_task_write_header "${RESOURCE_TASKS_FILE}" || return 1
        chmod 600 "${RESOURCE_TASKS_FILE}" 2>/dev/null || true
    fi
}

resource_task_lock() {
    ensure_resource_task_layout || return 1
    exec 9>"${RESOURCE_TASK_LOCK_FILE}" || return 1
    if command -v flock >/dev/null 2>&1; then
        flock -w 15 9 || {
            err "资源任务队列正忙，请稍后重试。"
            exec 9>&-
            return 1
        }
    fi
}

resource_task_unlock() {
    if command -v flock >/dev/null 2>&1; then
        flock -u 9 2>/dev/null || true
    fi
    exec 9>&- 2>/dev/null || true
}

resource_task_token_value() {
    [[ -f "${RESOURCE_TASK_TOKEN_FILE}" ]] || return 1
    tr -d '\r\n' < "${RESOURCE_TASK_TOKEN_FILE}"
}

resource_task_token_matches() {
    local supplied="$1"
    local expected
    expected="$(resource_task_token_value 2>/dev/null || true)"
    [[ -n "${expected}" && -n "${supplied}" && "${supplied}" == "${expected}" ]]
}

resource_task_token_matches_readonly() {
    local supplied="$1"
    local expected
    [[ -s "${RESOURCE_TASK_TOKEN_FILE}" ]] || return 1
    expected="$(tr -d '[:space:]' < "${RESOURCE_TASK_TOKEN_FILE}")" || return 1
    [[ -n "${expected}" && -n "${supplied}" && "${supplied}" == "${expected}" ]]
}

do_resource_task_ping() {
    local token="${1:-}"
    if resource_task_token_matches_readonly "${token}"; then
        printf 'OK|资源任务 Token 可用\n'
        return 0
    fi
    printf 'ERROR|资源任务 Token 错误或尚未生成\n'
    return 1
}

generate_resource_task_token() {
    local token
    ensure_resource_task_layout || return 1
    if command -v openssl >/dev/null 2>&1; then
        token="$(openssl rand -hex 24 2>/dev/null || true)"
    fi
    if [[ -z "${token:-}" ]] && [[ -r /dev/urandom ]]; then
        token="$(od -An -N24 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
    fi
    [[ -n "${token:-}" ]] || {
        err "无法生成资源任务 Token。"
        return 1
    }
    printf '%s\n' "${token}" > "${RESOURCE_TASK_TOKEN_FILE}" || return 1
    chmod 600 "${RESOURCE_TASK_TOKEN_FILE}" 2>/dev/null || true
    printf '%s\n' "${token}"
}

resource_task_type_label() {
    case "$1" in
        iplist) printf 'iplist 地区库' ;;
        ipdb) printf 'qqwry.ipdb' ;;
        *) printf '%s' "$1" ;;
    esac
}

resource_task_status_label() {
    case "$1" in
        pending) printf '等待领取' ;;
        running) printf '执行中' ;;
        success) printf '成功' ;;
        failed) printf '失败' ;;
        *) printf '%s' "$1" ;;
    esac
}

resource_task_artifact_name() {
    case "$1" in
        iplist) printf 'iplist.tar.gz' ;;
        ipdb) printf 'qqwry.ipdb' ;;
        *) return 1 ;;
    esac
}

resource_task_new_id() {
    local suffix
    suffix="$(printf '%05d' "$((RANDOM % 100000))")"
    printf '%s-%s\n' "$(date -u '+%Y%m%dT%H%M%SZ')" "${suffix}"
}

compact_resource_tasks_file() {
    local tmp
    make_temp_file "${RESOURCE_TASKS_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    awk -F '|' -v keep="${RESOURCE_TASK_HISTORY_LIMIT}" '
        BEGIN {
            print "# format: id|type|status|created_at|claimed_at|finished_at|worker_id|artifact_path|sha256|size|message"
        }
        /^#/ || NF < 3 { next }
        $3 == "pending" || $3 == "running" {
            active[++active_count] = $0
            next
        }
        {
            terminal[++terminal_count] = $0
        }
        END {
            start = terminal_count - keep + 1
            if (start < 1) start = 1
            for (i = start; i <= terminal_count; i++) print terminal[i]
            for (i = 1; i <= active_count; i++) print active[i]
        }
    ' "${RESOURCE_TASKS_FILE}" > "${tmp}" || return 1
    mv -f "${tmp}" "${RESOURCE_TASKS_FILE}"
}

create_resource_task() {
    local type="$1"
    local id now
    resource_task_artifact_name "${type}" >/dev/null || {
        err "不支持的资源任务类型：${type}"
        return 1
    }
    resource_task_lock || return 1
    id="$(resource_task_new_id)"
    now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf '%s|%s|pending|%s|||||||等待内网机器领取\n' \
        "${id}" "${type}" "${now}" >> "${RESOURCE_TASKS_FILE}" || {
        resource_task_unlock
        return 1
    }
    compact_resource_tasks_file || {
        resource_task_unlock
        return 1
    }
    resource_task_unlock
    success "已创建任务 ${id}：$(resource_task_type_label "${type}")。"
}

normalize_resource_task_create_type() {
    local type
    type="$(trim "${1:-all}")"
    case "${type}" in
        iplist|ipdb)
            printf '%s\n' "${type}"
            ;;
        all|both)
            printf 'all\n'
            ;;
        *)
            err "资源任务类型无效：${type:-空}。可用值：iplist、ipdb、all。"
            return 1
            ;;
    esac
}

create_resource_tasks_for_type() {
    local type failed=0
    type="$(normalize_resource_task_create_type "${1:-all}")" || return 1
    ensure_resource_task_layout || return 1
    case "${type}" in
        iplist|ipdb)
            create_resource_task "${type}"
            ;;
        all)
            create_resource_task "iplist" || failed=1
            create_resource_task "ipdb" || failed=1
            return "${failed}"
            ;;
    esac
}

resource_task_cron_begin_marker() {
    printf '# BEGIN PO0 nftables resource task scheduler\n'
}

resource_task_cron_end_marker() {
    printf '# END PO0 nftables resource task scheduler\n'
}

write_resource_task_cron_without_managed_block() {
    local begin end line in_block=0
    begin="$(resource_task_cron_begin_marker)"
    end="$(resource_task_cron_end_marker)"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" == "${begin}" ]]; then
            in_block=1
            continue
        fi
        if [[ "${line}" == "${end}" ]]; then
            in_block=0
            continue
        fi
        [[ "${in_block}" == "1" ]] && continue
        printf '%s\n' "${line}"
    done
}

normalize_resource_task_cron_schedule() {
    local raw field
    local -a fields=()
    raw="$(trim "$*")"
    [[ -n "${raw}" ]] || raw="daily"
    case "${raw}" in
        hourly)
            printf '17 * * * *\n'
            return 0
            ;;
        daily)
            printf '17 4 * * *\n'
            return 0
            ;;
        weekly)
            printf '17 4 * * 0\n'
            return 0
            ;;
        monthly)
            printf '17 4 1 * *\n'
            return 0
            ;;
        @hourly|@daily|@weekly|@monthly)
            printf '%s\n' "${raw}"
            return 0
            ;;
    esac
    read -r -a fields <<< "${raw}"
    if [[ "${#fields[@]}" -ne 5 ]]; then
        err "cron 表达式无效：请使用 hourly/daily/weekly/monthly，或 5 字段 cron 表达式。"
        return 1
    fi
    for field in "${fields[@]}"; do
        [[ "${field}" =~ ^[-A-Za-z0-9*/,]+$ ]] || {
            err "cron 字段包含不支持的字符：${field}"
            return 1
        }
    done
    printf '%s %s %s %s %s\n' "${fields[0]}" "${fields[1]}" "${fields[2]}" "${fields[3]}" "${fields[4]}"
}

print_resource_task_cron_summary() {
    local begin end line in_block=0 found=0
    command -v crontab >/dev/null 2>&1 || {
        printf '系统未安装 crontab\n'
        return 0
    }
    begin="$(resource_task_cron_begin_marker)"
    end="$(resource_task_cron_end_marker)"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" == "${begin}" ]]; then
            in_block=1
            continue
        fi
        if [[ "${line}" == "${end}" ]]; then
            in_block=0
            continue
        fi
        [[ "${in_block}" == "1" ]] || continue
        [[ -n "${line}" ]] || continue
        printf '%s\n' "${line}"
        found=1
    done < <(crontab -l 2>/dev/null || true)
    [[ "${found}" == "1" ]] || printf '未安装\n'
}

install_resource_task_cron() {
    local type schedule script_path escaped_script escaped_type job tmp
    type="$(normalize_resource_task_create_type "${1:-all}")" || return 1
    shift || true
    schedule="$(normalize_resource_task_cron_schedule "$@")" || return 1
    ensure_resource_task_layout || return 1
    command -v crontab >/dev/null 2>&1 || {
        err "当前系统没有 crontab 命令。请先安装 cron，或改用 systemd timer 调用 --resource-task-create。"
        return 1
    }
    script_path="$(ensure_persistent_manager_script)" || return 1
    chmod 0755 "${script_path}" 2>/dev/null || true
    escaped_script="$(shell_quote "${script_path}")"
    escaped_type="$(shell_quote "${type}")"
    job="${schedule} bash ${escaped_script} --resource-task-create ${escaped_type} >/tmp/po0-resource-task-cron.log 2>&1"
    tmp="${CONF_DIR}/po0-resource-task-cron.$$"
    {
        crontab -l 2>/dev/null | write_resource_task_cron_without_managed_block || true
        printf '%s\n' "$(resource_task_cron_begin_marker)"
        printf '%s\n' "${job}"
        printf '%s\n' "$(resource_task_cron_end_marker)"
    } > "${tmp}" || return 1
    crontab "${tmp}" || {
        rm -f -- "${tmp}" 2>/dev/null || true
        return 1
    }
    rm -f -- "${tmp}" 2>/dev/null || true
    success "已安装/更新资源任务定时创建：${type}，计划：${schedule}"
    info "Worker 会在自己的轮询周期内领取这些任务并回传资源文件。"
}

remove_resource_task_cron() {
    local tmp
    mkdir -p "${CONF_DIR}" || return 1
    command -v crontab >/dev/null 2>&1 || {
        err "当前系统没有 crontab 命令。"
        return 1
    }
    tmp="${CONF_DIR}/po0-resource-task-cron.rm.$$"
    {
        crontab -l 2>/dev/null | write_resource_task_cron_without_managed_block || true
    } > "${tmp}" || return 1
    crontab "${tmp}" || {
        rm -f -- "${tmp}" 2>/dev/null || true
        return 1
    }
    rm -f -- "${tmp}" 2>/dev/null || true
    success "已删除资源任务定时创建 cron。"
}

dynamic_allowlist_cron_begin_marker() {
    printf '# BEGIN PO0 nftables dynamic allowlist cleanup\n'
}

dynamic_allowlist_cron_end_marker() {
    printf '# END PO0 nftables dynamic allowlist cleanup\n'
}

write_dynamic_allowlist_cron_without_managed_block() {
    local begin end line in_block=0
    begin="$(dynamic_allowlist_cron_begin_marker)"
    end="$(dynamic_allowlist_cron_end_marker)"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" == "${begin}" ]]; then
            in_block=1
            continue
        fi
        if [[ "${line}" == "${end}" ]]; then
            in_block=0
            continue
        fi
        [[ "${in_block}" == "1" ]] && continue
        printf '%s\n' "${line}"
    done
}

print_dynamic_allowlist_cron_summary() {
    local begin end line in_block=0 found=0
    command -v crontab >/dev/null 2>&1 || {
        printf '系统未安装 crontab\n'
        return 0
    }
    begin="$(dynamic_allowlist_cron_begin_marker)"
    end="$(dynamic_allowlist_cron_end_marker)"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" == "${begin}" ]]; then
            in_block=1
            continue
        fi
        if [[ "${line}" == "${end}" ]]; then
            in_block=0
            continue
        fi
        [[ "${in_block}" == "1" ]] || continue
        [[ -n "${line}" ]] || continue
        printf '%s\n' "${line}"
        found=1
    done < <(crontab -l 2>/dev/null || true)
    [[ "${found}" == "1" ]] || printf '未安装\n'
}

install_dynamic_allowlist_cleanup_cron() {
    local schedule script_path escaped_script job tmp
    schedule="$(normalize_resource_task_cron_schedule "$@")" || return 1
    ensure_layout || return 1
    command -v crontab >/dev/null 2>&1 || {
        err "当前系统没有 crontab 命令。请先安装 cron，或手动调用 --cleanup-dynamic-allowlist。"
        return 1
    }
    script_path="$(ensure_persistent_manager_script)" || return 1
    chmod 0755 "${script_path}" 2>/dev/null || true
    escaped_script="$(shell_quote "${script_path}")"
    job="${schedule} bash ${escaped_script} --cleanup-dynamic-allowlist >/tmp/po0-dynamic-allowlist-cleanup.log 2>&1"
    tmp="${CONF_DIR}/po0-dynamic-allowlist-cleanup-cron.$$"
    {
        crontab -l 2>/dev/null | write_dynamic_allowlist_cron_without_managed_block || true
        printf '%s\n' "$(dynamic_allowlist_cron_begin_marker)"
        printf '%s\n' "${job}"
        printf '%s\n' "$(dynamic_allowlist_cron_end_marker)"
    } > "${tmp}" || return 1
    crontab "${tmp}" || {
        rm -f -- "${tmp}" 2>/dev/null || true
        return 1
    }
    rm -f -- "${tmp}" 2>/dev/null || true
    success "已安装/更新动态来源清理 cron：${schedule}"
}

remove_dynamic_allowlist_cleanup_cron() {
    local tmp
    mkdir -p "${CONF_DIR}" || return 1
    command -v crontab >/dev/null 2>&1 || {
        err "当前系统没有 crontab 命令。"
        return 1
    }
    tmp="${CONF_DIR}/po0-dynamic-allowlist-cleanup-cron.rm.$$"
    {
        crontab -l 2>/dev/null | write_dynamic_allowlist_cron_without_managed_block || true
    } > "${tmp}" || return 1
    crontab "${tmp}" || {
        rm -f -- "${tmp}" 2>/dev/null || true
        return 1
    }
    rm -f -- "${tmp}" 2>/dev/null || true
    success "已删除动态来源清理 cron。"
}

do_install_dynamic_allowlist_cleanup_cron_interactive() {
    local schedule
    print_title "安装动态来源清理 cron"
    echo "计划可填：hourly、daily、weekly、monthly，或标准 5 字段 cron 表达式。默认 daily。"
    schedule="$(prompt_with_default "请输入计划" "daily")"
    install_dynamic_allowlist_cleanup_cron "${schedule}"
}

do_install_resource_task_cron_interactive() {
    local choice type schedule
    print_title "安装资源任务定时创建"
    echo "  1) iplist 地区库"
    echo "  2) qqwry.ipdb"
    echo "  3) 全部更新"
    read -r -p "请选择要定时创建的任务 [1-3，默认 3]: " choice
    case "${choice:-3}" in
        1) type="iplist" ;;
        2) type="ipdb" ;;
        3) type="all" ;;
        *)
            err "无效选择。"
            return 1
            ;;
    esac
    echo ""
    echo "计划可填：hourly、daily、weekly、monthly，或标准 5 字段 cron 表达式。"
    schedule="$(prompt_with_default "请输入计划" "daily")"
    install_resource_task_cron "${type}" "${schedule}"
}

list_resource_tasks() {
    local line id type status created claimed finished worker artifact sha size message count=0
    ensure_resource_task_layout || return 1
    printf '任务文件 : %s\n' "${RESOURCE_TASKS_FILE}"
    printf '收件目录 : %s\n' "${RESOURCE_INBOX_DIR}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -n "${line}" && "${line}" != \#* ]] || continue
        IFS='|' read -r id type status created claimed finished worker artifact sha size message <<< "${line}"
        ((count++))
        printf '  %2d) %s  %-10s %-8s 创建=%s\n' \
            "${count}" "${id}" "$(resource_task_type_label "${type}")" "$(resource_task_status_label "${status}")" "${created:-未知}"
        [[ -n "${worker}" ]] && printf '      worker=%s 领取=%s 完成=%s\n' "${worker}" "${claimed:-未知}" "${finished:-未完成}"
        [[ -n "${artifact}" ]] && printf '      文件=%s 大小=%s SHA256=%s\n' "${artifact}" "${size:-未知}" "${sha:-未知}"
        [[ -n "${message}" ]] && printf '      结果=%s\n' "${message}"
    done < "${RESOURCE_TASKS_FILE}"
    [[ "${count}" -gt 0 ]] || printf '  (暂无任务)\n'
}

claim_resource_task() {
    local worker="$1"
    local token="$2"
    local line id type status created claimed finished old_worker artifact sha size message
    local tmp now upload_path found=0
    worker="$(tsv_safe "$(trim "${worker}")")"
    [[ "${worker}" =~ ^[A-Za-z0-9._:-]{1,80}$ ]] || {
        printf 'ERROR|worker_id 无效\n'
        return 1
    }
    resource_task_token_matches "${token}" || {
        printf 'ERROR|Token 错误\n'
        return 1
    }
    resource_task_lock || return 1
    make_temp_file "${RESOURCE_TASKS_FILE}" || {
        resource_task_unlock
        return 1
    }
    tmp="${TEMP_FILE_RESULT}"
    now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${found}" == "0" && -n "${line}" && "${line}" != \#* ]]; then
            IFS='|' read -r id type status created claimed finished old_worker artifact sha size message <<< "${line}"
            if [[ "${status}" == "pending" ]]; then
                found=1
                upload_path="${RESOURCE_INBOX_DIR}/${id}.$(resource_task_artifact_name "${type}")"
                printf '%s|%s|running|%s|%s||%s||||已由内网机器领取\n' \
                    "${id}" "${type}" "${created}" "${now}" "${worker}" >> "${tmp}"
                continue
            fi
        fi
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${RESOURCE_TASKS_FILE}"
    mv -f "${tmp}" "${RESOURCE_TASKS_FILE}"
    resource_task_unlock
    if [[ "${found}" == "1" ]]; then
        printf 'TASK|%s|%s|%s\n' "${id}" "${type}" "${upload_path}"
    else
        printf 'NO_TASK\n'
    fi
}

validate_ipdb_file() {
    local file="$1"
    local py metadata_size metadata file_size
    local b1 b2 b3 b4
    [[ -s "${file}" ]] || {
        err "IPDB 文件为空。"
        return 1
    }
    command -v od >/dev/null 2>&1 && command -v dd >/dev/null 2>&1 || {
        err "校验 qqwry.ipdb 需要 od 和 dd。"
        return 1
    }
    read -r b1 b2 b3 b4 < <(od -An -N4 -tu1 "${file}" 2>/dev/null)
    [[ "${b1:-}" =~ ^[0-9]+$ && "${b2:-}" =~ ^[0-9]+$ && "${b3:-}" =~ ^[0-9]+$ && "${b4:-}" =~ ^[0-9]+$ ]] || {
        err "IPDB 文件头无效。"
        return 1
    }
    metadata_size=$((b1 * 16777216 + b2 * 65536 + b3 * 256 + b4))
    (( metadata_size >= 32 && metadata_size <= 1048576 )) || {
        err "IPDB 元数据长度无效。"
        return 1
    }
    file_size="$(wc -c < "${file}" | tr -d '[:space:]')"
    [[ "${file_size}" =~ ^[0-9]+$ ]] && (( file_size > metadata_size + 4 )) || {
        err "IPDB 文件缺少数据区。"
        return 1
    }
    metadata="$(dd if="${file}" bs=1 skip=4 count="${metadata_size}" 2>/dev/null)" || return 1
    printf '%s' "${metadata}" | grep -q '"fields"' || { err "IPDB 元数据缺少 fields。"; return 1; }
    printf '%s' "${metadata}" | grep -q '"languages"' || { err "IPDB 元数据缺少 languages。"; return 1; }
    printf '%s' "${metadata}" | grep -q '"node_count"' || { err "IPDB 元数据缺少 node_count。"; return 1; }

    py="$(ipdb_python_cmd 2>/dev/null || true)"
    [[ -n "${py}" ]] || return 0
    "${py}" - "${file}" <<'PY' >/dev/null 2>&1
import json
import struct
import sys

path = sys.argv[1]
with open(path, "rb") as fh:
    header = fh.read(4)
    if len(header) != 4:
        raise SystemExit(1)
    metadata_size = struct.unpack(">I", header)[0]
    if metadata_size < 32 or metadata_size > 1024 * 1024:
        raise SystemExit(1)
    metadata = json.loads(fh.read(metadata_size).decode("utf-8"))
    if not isinstance(metadata.get("fields"), list):
        raise SystemExit(1)
    if "languages" not in metadata or "node_count" not in metadata:
        raise SystemExit(1)
    if fh.read(1) == b"":
        raise SystemExit(1)
PY
}

install_received_ipdb() {
    local source="$1"
    local tmp backup
    validate_ipdb_file "${source}" || return 1
    make_temp_file "${IPDB_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    cp "${source}" "${tmp}" || return 1
    validate_ipdb_file "${tmp}" || return 1
    if [[ -f "${IPDB_FILE}" ]]; then
        backup="${BACKUP_DIR}/qqwry.ipdb.$(date '+%Y%m%d_%H%M%S')"
        cp "${IPDB_FILE}" "${backup}" 2>/dev/null || true
    fi
    mv -f "${tmp}" "${IPDB_FILE}" || return 1
    chmod 600 "${IPDB_FILE}" 2>/dev/null || true
}

activate_received_iplist() {
    local package="$1"
    import_iplist_package "${package}" || return 1
    load_settings 1
    if src_allowlist_enabled; then
        build_src_allowlist_cache || return 1
        backup_managed_files
        write_nft_conf || return 1
        apply_or_save_notice "iplist 已刷新并应用。" "iplist 已刷新，托管配置已更新。" || return 1
    fi
}

finish_resource_task() {
    local task_id="$1"
    local worker="$2"
    local reported_sha="$3"
    local reported_size="$4"
    local token="$5"
    local line id type status created claimed finished task_worker artifact sha size message
    local tmp now expected_path actual_sha actual_size result_message found=0 ok=0
    [[ "${task_id}" =~ ^[A-Za-z0-9._-]+$ ]] || { printf 'ERROR|任务 ID 无效\n'; return 1; }
    [[ "${worker}" =~ ^[A-Za-z0-9._:-]{1,80}$ ]] || { printf 'ERROR|worker_id 无效\n'; return 1; }
    resource_task_token_matches "${token}" || { printf 'ERROR|Token 错误\n'; return 1; }
    resource_task_lock || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -n "${line}" && "${line}" != \#* ]] || continue
        IFS='|' read -r id type status created claimed finished task_worker artifact sha size message <<< "${line}"
        if [[ "${id}" == "${task_id}" ]]; then
            found=1
            [[ "${status}" == "running" && "${task_worker}" == "${worker}" ]] || {
                resource_task_unlock
                printf 'ERROR|任务状态或领取机器不匹配\n'
                return 1
            }
            break
        fi
    done < "${RESOURCE_TASKS_FILE}"
    [[ "${found}" == "1" ]] || {
        resource_task_unlock
        printf 'ERROR|任务不存在\n'
        return 1
    }
    expected_path="${RESOURCE_INBOX_DIR}/${task_id}.$(resource_task_artifact_name "${type}")"
    [[ -f "${expected_path}" ]] || {
        resource_task_unlock
        printf 'ERROR|尚未收到任务文件\n'
        return 1
    }
    command -v sha256sum >/dev/null 2>&1 || {
        resource_task_unlock
        printf 'ERROR|PO0 缺少 sha256sum\n'
        return 1
    }
    actual_sha="$(sha256sum "${expected_path}" | awk '{print $1}')"
    actual_size="$(wc -c < "${expected_path}" | tr -d '[:space:]')"
    if [[ "${actual_sha}" != "${reported_sha}" || "${actual_size}" != "${reported_size}" ]]; then
        resource_task_unlock
        printf 'ERROR|SHA256 或文件大小不匹配\n'
        return 1
    fi
    case "${type}" in
        iplist)
            if activate_received_iplist "${expected_path}" >/dev/null; then
                ok=1
                result_message="iplist 已校验、导入并按当前白名单状态应用"
            else
                result_message="iplist 校验或导入失败，旧数据已保留"
            fi
            ;;
        ipdb)
            if install_received_ipdb "${expected_path}"; then
                ok=1
                result_message="qqwry.ipdb 已校验并替换"
            else
                result_message="qqwry.ipdb 格式校验或安装失败，旧数据已保留"
            fi
            ;;
    esac
    now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    make_temp_file "${RESOURCE_TASKS_FILE}" || {
        resource_task_unlock
        return 1
    }
    tmp="${TEMP_FILE_RESULT}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ -n "${line}" && "${line}" != \#* ]]; then
            IFS='|' read -r id type status created claimed finished task_worker artifact sha size message <<< "${line}"
            if [[ "${id}" == "${task_id}" ]]; then
                if [[ "${ok}" == "1" ]]; then
                    status="success"
                else
                    status="failed"
                fi
                printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
                    "${id}" "${type}" "${status}" "${created}" "${claimed}" "${now}" "${task_worker}" \
                    "${expected_path}" "${actual_sha}" "${actual_size}" "$(tsv_safe "${result_message}")" >> "${tmp}"
                continue
            fi
        fi
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${RESOURCE_TASKS_FILE}"
    mv -f "${tmp}" "${RESOURCE_TASKS_FILE}"
    compact_resource_tasks_file || {
        resource_task_unlock
        return 1
    }
    [[ "${ok}" == "1" ]] && rm -f -- "${expected_path}" 2>/dev/null || true
    resource_task_unlock
    if [[ "${ok}" == "1" ]]; then
        printf 'OK|%s\n' "${result_message}"
        return 0
    fi
    printf 'ERROR|%s\n' "${result_message}"
    return 1
}

fail_resource_task() {
    local task_id="$1"
    local worker="$2"
    local reason="$3"
    local token="$4"
    local line id type status created claimed finished task_worker artifact sha size message
    local tmp now found=0
    [[ "${task_id}" =~ ^[A-Za-z0-9._-]+$ ]] || { printf 'ERROR|任务 ID 无效\n'; return 1; }
    resource_task_token_matches "${token}" || { printf 'ERROR|Token 错误\n'; return 1; }
    reason="$(tsv_safe "${reason}")"
    resource_task_lock || return 1
    make_temp_file "${RESOURCE_TASKS_FILE}" || {
        resource_task_unlock
        return 1
    }
    tmp="${TEMP_FILE_RESULT}"
    now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ -n "${line}" && "${line}" != \#* ]]; then
            IFS='|' read -r id type status created claimed finished task_worker artifact sha size message <<< "${line}"
            if [[ "${id}" == "${task_id}" && "${status}" == "running" && "${task_worker}" == "${worker}" ]]; then
                found=1
                printf '%s|%s|failed|%s|%s|%s|%s||||%s\n' \
                    "${id}" "${type}" "${created}" "${claimed}" "${now}" "${task_worker}" "${reason:-内网机器执行失败}" >> "${tmp}"
                continue
            fi
        fi
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${RESOURCE_TASKS_FILE}"
    mv -f "${tmp}" "${RESOURCE_TASKS_FILE}"
    compact_resource_tasks_file || {
        resource_task_unlock
        return 1
    }
    resource_task_unlock
    [[ "${found}" == "1" ]] || { printf 'ERROR|任务状态或领取机器不匹配\n'; return 1; }
    printf 'OK|失败原因已记录\n'
}

retry_resource_tasks() {
    local line id type status created claimed finished worker artifact sha size message tmp count=0
    ensure_resource_task_layout || return 1
    resource_task_lock || return 1
    make_temp_file "${RESOURCE_TASKS_FILE}" || {
        resource_task_unlock
        return 1
    }
    tmp="${TEMP_FILE_RESULT}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ -n "${line}" && "${line}" != \#* ]]; then
            IFS='|' read -r id type status created claimed finished worker artifact sha size message <<< "${line}"
            if [[ "${status}" == "failed" || "${status}" == "running" ]]; then
                ((count++))
                printf '%s|%s|pending|%s|||||||手动重新排队\n' "${id}" "${type}" "${created}" >> "${tmp}"
                continue
            fi
        fi
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${RESOURCE_TASKS_FILE}"
    mv -f "${tmp}" "${RESOURCE_TASKS_FILE}"
    compact_resource_tasks_file || {
        resource_task_unlock
        return 1
    }
    resource_task_unlock
    success "已将 ${count} 个失败或执行中的任务重新排队。"
}

ensure_iplist_ready() {
    iplist_ready && return 0
    err "尚未导入 iplist 离线包，请先使用菜单导入 iplist.tar.gz。"
    return 1
}

region_id_is_selected() {
    local needle="$1"
    local id
    for id in ${SRC_ALLOWLIST_REGION_IDS}; do
        [[ "${id}" == "${needle}" ]] && return 0
    done
    return 1
}

add_allowlist_region_id() {
    local id="$1"
    [[ -n "$(iplist_region_record "${id}" || true)" ]] || return 1
    region_id_is_selected "${id}" && return 0
    SRC_ALLOWLIST_REGION_IDS="$(normalize_region_ids "${SRC_ALLOWLIST_REGION_IDS} ${id}")"
}

remove_allowlist_region_id() {
    local target="$1"
    local id out=""
    for id in ${SRC_ALLOWLIST_REGION_IDS}; do
        [[ "${id}" == "${target}" ]] && continue
        if [[ -z "${out}" ]]; then
            out="${id}"
        else
            out+=" ${id}"
        fi
    done
    SRC_ALLOWLIST_REGION_IDS="${out}"
}

show_selected_allowlist_regions() {
    local id
    if [[ -z "${SRC_ALLOWLIST_REGION_IDS}" ]]; then
        echo "  (未选择地区)"
        return 0
    fi
    for id in ${SRC_ALLOWLIST_REGION_IDS}; do
        printf '  - %s\n' "$(iplist_region_label "${id}")"
    done
}

allowlist_pending_count() {
    if [[ -s "${AUTO_PENDING_FILE}" ]]; then
        awk -F '|' 'NF >= 7 && $1 !~ /^#/ && $7 == "pending" { c++ } END { print c + 0 }' "${AUTO_PENDING_FILE}" 2>/dev/null
    else
        printf '0\n'
    fi
}

allowlist_cache_count() {
    if [[ -s "${SRC_ALLOWLIST_CACHE}" ]]; then
        wc -l < "${SRC_ALLOWLIST_CACHE}" 2>/dev/null | tr -d '[:space:]' || printf '0'
    else
        printf '0\n'
    fi
}

show_allowlist_entry_table() {
    local line idx=1 status allowed expires value note source_label
    if [[ ! -f "${ALLOWLIST_ENTRIES_FILE}" ]] || [[ "$(allowlist_entries_count)" == "0" ]]; then
        echo "  (暂无手动/动态来源条目)"
        return 0
    fi
    printf '  %3s  %-18s %-10s %-8s %-12s %-18s %-20s %s\n' "#" "CIDR" "来源" "状态" "参与当前模式" "来源 key" "过期时间" "备注"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_entry_line "${line}" || continue
        if allowlist_entry_is_expired "${ALLOWLIST_ENTRY_EXPIRES_AT}"; then
            status="过期"
        else
            status="生效"
        fi
        if source_type_allowed_by_mode "${ALLOWLIST_ENTRY_SOURCE_TYPE}" "${SRC_ALLOWLIST_MODE}"; then
            allowed="是"
        else
            allowed="否"
        fi
        source_label="$(allowlist_source_type_label "${ALLOWLIST_ENTRY_SOURCE_TYPE}")"
        value="${ALLOWLIST_ENTRY_SOURCE_VALUE:-"-"}"
        expires="${ALLOWLIST_ENTRY_EXPIRES_AT:-"-"}"
        note="${ALLOWLIST_ENTRY_NOTE:-"-"}"
        printf '  %3d  %-18s %-10s %-8s %-12s %-18s %-20s %s\n' \
            "${idx}" "${ALLOWLIST_ENTRY_CIDR}" "${source_label}" "${status}" "${allowed}" "${value}" "${expires}" "${note}"
        ((idx++))
    done < "${ALLOWLIST_ENTRIES_FILE}"
}

do_show_allowlist_source_entries() {
    ensure_layout || return 1
    load_settings 1
    print_title "白名单来源 / IP 明细"
    printf '当前模式       : %s\n' "$(src_allowlist_mode_to_label "${SRC_ALLOWLIST_MODE}")"
    printf '当前允许来源   : %s\n' "$(allowlist_sources_label "$(src_allowlist_mode_default_sources "${SRC_ALLOWLIST_MODE}")")"
    printf '自动来源安全模式: %s\n' "$([[ "${AUTOMATION_MODE}" == "attack" ]] && printf 'attack（新自动 IP 进入待审核）' || printf 'regular（新自动 IP 直接生效）')"
    printf 'entries 文件    : %s\n' "${ALLOWLIST_ENTRIES_FILE}"
    echo ""
    echo "说明：这里显示手动 CIDR、SSH 临时、DDNS、Client IP、SSH report、WebAuth、学习提升等条目。地区库的海量 CIDR 不逐条存在 entries 文件，最终展开结果看“最终 CIDR 缓存”。"
    echo ""
    show_allowlist_entry_table
}

do_show_src_allowlist_cache() {
    local total limit="${1:-200}"
    ensure_layout || return 1
    print_title "最终生效 CIDR 缓存"
    if [[ ! -s "${SRC_ALLOWLIST_CACHE}" ]]; then
        echo "白名单缓存尚未生成。可先执行“重建并应用白名单”。"
        printf '缓存路径: %s\n' "${SRC_ALLOWLIST_CACHE}"
        return 0
    fi
    total="$(allowlist_cache_count)"
    printf '缓存路径 : %s\n' "${SRC_ALLOWLIST_CACHE}"
    printf 'CIDR 数量: %s\n' "${total}"
    echo ""
    if [[ "${total}" =~ ^[0-9]+$ ]] && (( total > limit )); then
        printf '仅显示前 %s 条；完整内容请在服务器上查看该文件。\n' "${limit}"
    fi
    sed -n "1,${limit}p" "${SRC_ALLOWLIST_CACHE}" | sed 's/^/  /'
}

do_explain_src_allowlist_fields() {
    print_title "白名单字段说明"
    cat <<EOF
白名单缓存
  最终写入 nftables 的 CIDR 列表，路径：${SRC_ALLOWLIST_CACHE}
  它由地区库 + 手动 CIDR + 动态来源条目合并生成。

自定义 CIDR
  手工维护的静态白名单，路径：${CUSTOM_SRC_ALLOWLIST_FILE}
  适合放你明确确认过的固定公网 IP 或网段。它不是全部白名单。

entries
  手动、SSH 临时、DDNS、Client IP、SSH report、WebAuth、learned 等条目的统一记录表：
  ${ALLOWLIST_ENTRIES_FILE}

允许来源
  当前白名单模式会采用哪些 source_type。比如 trusted_dynamic 会采用：
  manual、ddns、client_ip、ssh_report、webauth、learned。ssh_temp 只在手动开启时参与。

待审核 IP
  attack 模式下，新的 DDNS / Client IP / SSH report / WebAuth 等自动来源不会直接放行，
  而是进入待审核队列：${AUTO_PENDING_FILE}

地区库
  来自离线 iplist 包。菜单中选择“杭州市”等地区后，最终展开进白名单缓存。
EOF
}

print_src_allowlist_details() {
    local cache_count custom_count
    if iplist_ready; then
        printf 'iplist 数据 : 已导入（%s）\n' "${IPLIST_DIR}"
    else
        printf 'iplist 数据 : 未导入\n'
    fi

    if [[ -s "${SRC_ALLOWLIST_CACHE}" ]]; then
        cache_count="$(wc -l < "${SRC_ALLOWLIST_CACHE}" 2>/dev/null | tr -d '[:space:]' || true)"
        printf '白名单缓存 : 已生成（%s 条 CIDR，%s）\n' "${cache_count:-0}" "${SRC_ALLOWLIST_CACHE}"
    else
        printf '白名单缓存 : 未生成\n'
    fi

    custom_count="$(custom_allowlist_count)"
    if src_allowlist_enabled; then
        printf '白名单状态 : 开启（%s）\n' "$(src_allowlist_mode_to_label "${SRC_ALLOWLIST_MODE}")"
    elif [[ "${ENABLE_SRC_ALLOWLIST}" == "1" ]]; then
        printf '白名单状态 : 配置不完整（%s）\n' "$(src_allowlist_mode_to_label "${SRC_ALLOWLIST_MODE}")"
    else
        printf '白名单状态 : 关闭\n'
    fi
    printf '自动白名单 : %s\n' "$([[ "${AUTOMATION_MODE}" == "attack" ]] && printf 'attack（新自动 IP 进入待审核）' || printf 'regular')"
    printf '允许来源   : %s\n' "$(allowlist_sources_label "$(src_allowlist_mode_default_sources "${SRC_ALLOWLIST_MODE}")")"
    printf '来源条目   : %s 条（%s）\n' "$(allowlist_entries_count)" "${ALLOWLIST_ENTRIES_FILE}"
    printf '动态缓存   : ddns/client_ip/ssh_report/webauth 每个来源最多保留 %s 个有效 IP，过期条目不进入最终缓存\n' "$(dynamic_allowlist_max_per_source)"
    printf '待审核 IP  : %s 条（%s）\n' "$(allowlist_pending_count)" "${AUTO_PENDING_FILE}"
    printf '地区数量   : %s\n' "$(src_allowlist_region_count)"
    printf '手动 CIDR  : %s 条（%s）\n' "${custom_count}" "${CUSTOM_SRC_ALLOWLIST_FILE}"
    printf '阻挡日志   : %s 条，%s；summary %s 行\n' \
        "$(block_log_count)" \
        "$(format_bytes "$(block_log_size_bytes)")" \
        "$(block_summary_count)"
    printf '学习服务   : %s\n' "$(learning_service_status_label)"
    printf 'IPDB 数据  : %s\n' "$(ipdb_status_label)"
    echo "白名单地区 :"
    show_selected_allowlist_regions
    echo "手动 CIDR:"
    show_custom_allowlist_entries
}

build_src_allowlist_cache() {
    local output="${1:-${SRC_ALLOWLIST_CACHE}}"
    local id record name rel url line tmp count=0 custom_added=0 entries_added=0
    make_temp_file "${output}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    : > "${tmp}"

    if src_allowlist_mode_uses_region; then
        if [[ -n "${SRC_ALLOWLIST_REGION_IDS}" ]]; then
            ensure_iplist_ready || return 1
            for id in ${SRC_ALLOWLIST_REGION_IDS}; do
                record="$(iplist_region_record "${id}" || true)"
                [[ -n "${record}" ]] || {
                    err "地区 ${id} 不存在于当前 iplist。"
                    return 1
                }
                IFS=$'\t' read -r _ name rel url <<< "${record}"
                [[ -f "${IPLIST_DIR}/${rel}" ]] || {
                    err "地区 ${name} 缺少数据文件：${rel}"
                    return 1
                }
                while IFS= read -r line || [[ -n "${line}" ]]; do
                    line="${line%$'\r'}"
                    line="$(trim "${line}")"
                    [[ -z "${line}" || "${line}" =~ ^# ]] && continue
                    validate_ipv4_cidr "${line}" || {
                        err "地区 ${name} 存在无效 CIDR：${line}"
                        return 1
                    }
                    printf '%s\n' "${line}" >> "${tmp}"
                    ((count++))
                done < "${IPLIST_DIR}/${rel}"
            done
        elif [[ "${SRC_ALLOWLIST_MODE}" == "region_only" ]]; then
            err "仅地区库模式未选择任何地区。"
            return 1
        fi
    fi

    if src_allowlist_mode_uses_custom; then
        entries_added="$(append_allowlist_entries_to_cache "default" "${tmp}")" || return 1
        if [[ "${entries_added}" =~ ^[0-9]+$ && "${entries_added}" -gt 0 ]]; then
            count=$((count + entries_added))
            custom_added=1
        fi
        if [[ -f "${CUSTOM_SRC_ALLOWLIST_FILE}" ]]; then
            while IFS= read -r line || [[ -n "${line}" ]]; do
                custom_allowlist_line_is_data "${line}" || continue
                parse_custom_allowlist_line "${line}" || {
                    err "自定义白名单存在无效 CIDR：${line}"
                    return 1
                }
                printf '%s\n' "${CUSTOM_ALLOWLIST_CIDR}" >> "${tmp}"
                ((count++))
                custom_added=1
            done < "${CUSTOM_SRC_ALLOWLIST_FILE}"
        fi
        if [[ "${SRC_ALLOWLIST_MODE}" != "region_plus_trusted" && "${SRC_ALLOWLIST_MODE}" != "region_only" && "${custom_added}" != "1" ]]; then
            err "$(src_allowlist_mode_to_label "${SRC_ALLOWLIST_MODE}") 没有任何可用 CIDR。"
            return 1
        fi
    fi

    [[ "${count}" -gt 0 ]] || {
        err "源 IP 白名单没有可用 CIDR。"
        return 1
    }
    sort -u "${tmp}" -o "${tmp}"
    mv -f "${tmp}" "${output}"
}

write_nft_allowlist_set() {
    local tmp="$1"
    local cache="${2:-${SRC_ALLOWLIST_CACHE}}"
    local line set_name
    [[ -s "${cache}" ]] || return 1
    set_name="$(default_allowlist_nft_set_name)"
    cat >> "${tmp}" <<EOF
    set ${set_name} {
        type ipv4_addr
        flags interval
        auto-merge
        elements = {
EOF
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="$(trim "${line}")"
        [[ -n "${line}" ]] || continue
        printf '            %s,\n' "${line}" >> "${tmp}"
    done < "${cache}"
    cat >> "${tmp}" <<'EOF'
        }
    }

EOF
}

enabled_rule_ports_set() {
    local want_proto="$1"
    local rule port out="" seen=" "
    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        [[ "${RULE_ENABLED}" == "1" ]] || continue
        case "${want_proto}:${RULE_PROTO}" in
            tcp:tcp|tcp:both|udp:udp|udp:both)
                port="${RULE_LPORT}"
                ;;
            *)
                continue
                ;;
        esac
        [[ "${seen}" == *" ${port} "* ]] && continue
        seen+="${port} "
        if [[ -z "${out}" ]]; then
            out="${port}"
        else
            out+=", ${port}"
        fi
    done
    printf '%s\n' "${out}"
}

enabled_rule_count() {
    local rule count=0
    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        [[ "${RULE_ENABLED}" == "1" ]] || continue
        ((count++))
    done
    printf '%s\n' "${count}"
}

relay_lan_snat_required() {
    local rule
    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        [[ "${RULE_ENABLED}" == "1" ]] || continue
        [[ "${RULE_SNAT_MODE}" == "relay_lan" ]] && return 0
    done
    return 1
}

apply_relay_mode_to_rules() {
    local idx rule snat_mode
    [[ "${RELAY_MODE}" == "mixed" ]] && return 0
    snat_mode="$(relay_mode_default_snat_mode)"
    for idx in "${!RULES[@]}"; do
        rule="${RULES[$idx]}"
        parse_rule "${rule}"
        RULES[$idx]="$(serialize_rule "${RULE_ID}" "${RULE_NAME}" "${RULE_PROTO}" "${RULE_LPORT}" "${RULE_DIP}" "${RULE_DPORT}" "${RULE_ENABLED}" "${snat_mode}")"
    done
}

validate_managed_listen_ports() {
    local rule
    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        [[ "${RULE_ENABLED}" == "1" ]] || continue
        ensure_listen_port_allowed "${RULE_LPORT}" "${RULE_PROTO}" || return 1
    done
}

get_unmanaged_runtime_dnat_summary() {
    local text=""
    local current_family=""
    local current_table=""
    local line parsed key lport dip dport tables
    local -A seen_rules=()
    local -A seen_tables=()

    command -v nft &>/dev/null || return 1
    text="$(nft list ruleset 2>/dev/null || true)"
    [[ -n "${text}" ]] || return 1

    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ ^table[[:space:]]+([[:alnum:]_]+)[[:space:]]+([^[:space:]]+)[[:space:]]*\{ ]]; then
            current_family="${BASH_REMATCH[1]}"
            current_table="${BASH_REMATCH[2]}"
            continue
        fi

        parsed="$(parse_rule_from_line "${line}" || true)"
        [[ -n "${parsed}" ]] || continue
        [[ "${current_family}" == "ip" || "${current_family}" == "inet" ]] || continue
        [[ "${current_table}" == "${NAT_TABLE}" ]] && continue

        IFS='|' read -r _ lport dip dport _ <<< "${parsed}"
        key="${current_table}|${lport}|${dip}|${dport}"
        seen_rules["${key}"]=1
        seen_tables["${current_table}"]=1
    done <<< "${text}"

    [[ ${#seen_rules[@]} -gt 0 ]] || return 1
    tables="$(join_with_comma "${!seen_tables[@]}")"
    printf '%s|%s\n' "${#seen_rules[@]}" "${tables}"
}

print_runtime_drift_hint() {
    local summary count tables
    summary="$(get_unmanaged_runtime_dnat_summary || true)"
    [[ -n "${summary}" ]] || return 0
    IFS='|' read -r count tables <<< "${summary}"
    warn "发现 ${count} 条脚本未管理的 DNAT 转发规则：它们正在系统里生效，但不在本脚本的规则列表中。"
    [[ -n "${tables}" ]] && info "所在 nft 表：${tables}"
    info "常见原因：旧脚本、手动 nft 命令、其它面板或防火墙工具留下了转发规则。"
    info "处理方式：想保留就可以先不管；想交给本脚本管理，用 [7] 导入当前 nft 运行时规则；确认不要了，再用 [1] 初始化接管或手动删除对应表。"
}

public_ip_source_label() {
    case "${PUBLIC_IP_SOURCE}" in
        system)
            printf '已缓存（本机路由或网卡）'
            ;;
        online)
            printf '已缓存（公网服务查询）'
            ;;
        manual)
            printf '手动设置'
            ;;
        settings)
            printf '已缓存配置'
            ;;
        *)
            printf '未探测到'
            ;;
    esac
}

refresh_relay_lan_ip() {
    RELAY_LAN_IP="$(detect_relay_ip_from_system 2>/dev/null || true)"
    if validate_host_ipv4 "${RELAY_LAN_IP}"; then
        RELAY_LAN_IP_SOURCE="auto"
        return 0
    fi
    RELAY_LAN_IP=""
    RELAY_LAN_IP_SOURCE="none"
    return 1
}

refresh_public_ip() {
    PUBLIC_IP="$(detect_public_ip_from_system 2>/dev/null || true)"
    if is_public_ipv4 "${PUBLIC_IP}"; then
        PUBLIC_IP_SOURCE="system"
    else
        info "本机路由或网卡未读到公网 IP，开始查询公网服务。"
        PUBLIC_IP="$(detect_public_ip_online 2>/dev/null || true)"
        if is_public_ipv4 "${PUBLIC_IP}"; then
            PUBLIC_IP_SOURCE="online"
        else
            PUBLIC_IP=""
            PUBLIC_IP_SOURCE="none"
            PUBLIC_IP_CACHE=""
            PUBLIC_IP_CACHE_SOURCE="none"
            PUBLIC_IP_PROBE_DONE="1"
            return 1
        fi
    fi
    PUBLIC_IP_CACHE="${PUBLIC_IP}"
    PUBLIC_IP_CACHE_SOURCE="${PUBLIC_IP_SOURCE}"
    PUBLIC_IP_PROBE_DONE="1"
    return 0
}

unique_loaded_rule_name() {
    local requested="$1"
    local lport="$2"
    local base candidate suffix=2

    requested="$(trim "${requested}")"
    if validate_rule_name "${requested}"; then
        base="${requested}"
    else
        base="relay-${lport}"
    fi

    candidate="${base}"
    while rule_name_exists "${candidate}"; do
        candidate="${base}-${suffix}"
        ((suffix++))
    done
    printf '%s\n' "${candidate}"
}

parse_rule_from_line() {
    local line="$1"
    local proto="both"
    local name=""
    local port=""
    local dst_ip=""
    local dst_port=""

    [[ "${line}" == *dnat* ]] || return 1

    if [[ "${line}" =~ ^[[:space:]]*tcp[[:space:]]+dport[[:space:]]+([0-9]+)[[:space:]]+dnat[[:space:]]+(ip[[:space:]]+)?to[[:space:]]+([0-9.]+):([0-9]+) ]]; then
        proto="tcp"
        port="${BASH_REMATCH[1]}"
        dst_ip="${BASH_REMATCH[3]}"
        dst_port="${BASH_REMATCH[4]}"
    elif [[ "${line}" =~ ^[[:space:]]*udp[[:space:]]+dport[[:space:]]+([0-9]+)[[:space:]]+dnat[[:space:]]+(ip[[:space:]]+)?to[[:space:]]+([0-9.]+):([0-9]+) ]]; then
        proto="udp"
        port="${BASH_REMATCH[1]}"
        dst_ip="${BASH_REMATCH[3]}"
        dst_port="${BASH_REMATCH[4]}"
    elif [[ "${line}" =~ meta[[:space:]]+l4proto[[:space:]]+\{[[:space:]]*tcp,[[:space:]]*udp[[:space:]]*\} ]]; then
        proto="both"
    elif [[ "${line}" =~ meta[[:space:]]+l4proto[[:space:]]+tcp([[:space:]]|$) ]] || [[ "${line}" =~ (^|[[:space:]])tcp[[:space:]]+dport[[:space:]]+ ]]; then
        proto="tcp"
    elif [[ "${line}" =~ meta[[:space:]]+l4proto[[:space:]]+udp([[:space:]]|$) ]] || [[ "${line}" =~ (^|[[:space:]])udp[[:space:]]+dport[[:space:]]+ ]]; then
        proto="udp"
    fi

    if [[ -z "${port}" && "${line}" =~ th[[:space:]]+dport[[:space:]]+([0-9]+) ]]; then
        port="${BASH_REMATCH[1]}"
    elif [[ -z "${port}" && "${line}" =~ (tcp|udp)[[:space:]]+dport[[:space:]]+([0-9]+) ]]; then
        port="${BASH_REMATCH[2]}"
    fi

    if [[ -z "${dst_ip}" && "${line}" =~ dnat[[:space:]]+(ip[[:space:]]+)?to[[:space:]]+([0-9.]+):([0-9]+) ]]; then
        dst_ip="${BASH_REMATCH[2]}"
        dst_port="${BASH_REMATCH[3]}"
    fi

    if [[ "${line}" =~ comment[[:space:]]+\"([^\"]+)\" ]]; then
        name="${BASH_REMATCH[1]}"
    fi

    [[ -n "${port}" && -n "${dst_ip}" && -n "${dst_port}" ]] || return 1
    printf '%s|%s|%s|%s|%s\n' "${proto}" "${port}" "${dst_ip}" "${dst_port}" "${name}"
}

append_loaded_rule() {
    local proto="$1"
    local lport="$2"
    local dip="$3"
    local dport="$4"
    local name="$5"
    local idx=0 rule merged_name

    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        if [[ "${RULE_LPORT}" == "${lport}" && "${RULE_DIP}" == "${dip}" && "${RULE_DPORT}" == "${dport}" ]]; then
            merged_name="${RULE_NAME}"
            [[ -n "${name}" ]] && merged_name="${name}"
            if [[ "${RULE_PROTO}" != "${proto}" ]]; then
                RULE_PROTO="both"
            fi
            RULE_NAME="${merged_name}"
            RULES[$idx]="$(serialize_rule "${RULE_ID}" "${RULE_NAME}" "${RULE_PROTO}" "${RULE_LPORT}" "${RULE_DIP}" "${RULE_DPORT}" "${RULE_ENABLED}" "${RULE_SNAT_MODE}")"
            return 0
        fi
        ((idx++))
    done

    name="$(unique_loaded_rule_name "${name}" "${lport}")"
    RULES+=("$(serialize_rule "$(generate_unique_rule_id)" "${name}" "${proto}" "${lport}" "${dip}" "${dport}" "1")")
}

extract_rules_from_nft_text() {
    local text="$1"
    local line parsed
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parsed="$(parse_rule_from_line "${line}" || true)"
        [[ -n "${parsed}" ]] && printf '%s\n' "${parsed}"
    done <<< "${text}"
}

load_rules_from_nft_text() {
    local text="$1"
    local source_name="$2"
    local proto lport dip dport name

    while IFS='|' read -r proto lport dip dport name; do
        [[ -n "${proto}" ]] || continue
        validate_listen_port_value "${lport}" || continue
        validate_host_ipv4 "${dip}" || continue
        validate_port "${dport}" || continue
        append_loaded_rule "${proto}" "${lport}" "${dip}" "${dport}" "${name}"
    done < <(extract_rules_from_nft_text "${text}")

    [[ ${#RULES[@]} -gt 0 ]] || return 1
    RULES_SOURCE="${source_name}"
}

load_rules_from_nft_conf() {
    local text
    [[ -f "${NFT_CONF}" ]] || return 1
    text="$(cat "${NFT_CONF}" 2>/dev/null || true)"
    [[ -n "${text}" ]] || return 1
    load_rules_from_nft_text "${text}" "nft_conf"
}

load_rules_from_live_table() {
    local text
    command -v nft &>/dev/null || return 1
    text="$(nft list table ip "${NAT_TABLE}" 2>/dev/null || true)"
    [[ -n "${text}" ]] || return 1
    load_rules_from_nft_text "${text}" "live_table"
}

extract_rules_from_ruleset_text() {
    extract_rules_from_nft_text "$1"
}

load_rules_from_ruleset() {
    local text proto lport dip dport name
    command -v nft &>/dev/null || return 1
    text="$(nft list ruleset 2>/dev/null || true)"
    [[ -n "${text}" ]] || return 1

    while IFS='|' read -r proto lport dip dport name; do
        [[ -n "${proto}" ]] || continue
        validate_listen_port_value "${lport}" || continue
        validate_host_ipv4 "${dip}" || continue
        validate_port "${dport}" || continue
        append_loaded_rule "${proto}" "${lport}" "${dip}" "${dport}" "${name}"
    done < <(extract_rules_from_ruleset_text "${text}")

    [[ ${#RULES[@]} -gt 0 ]] || return 1
    RULES_SOURCE="ruleset"
}

discover_existing_rules() {
    local force_reload="${1:-0}"
    local -a saved_rules=("${RULES[@]}")
    local saved_source="${RULES_SOURCE}"

    if [[ "${DISCOVERY_CACHE_READY}" == "1" && "${force_reload}" != "1" ]]; then
        [[ ${DISCOVERED_RULE_COUNT} -gt 0 ]]
        return
    fi

    DISCOVERED_RULES=()
    DISCOVERED_RULES_SOURCE="none"
    DISCOVERED_RULE_COUNT=0

    RULES=()
    RULES_SOURCE="none"
    if load_rules_from_nft_conf || load_rules_from_live_table || load_rules_from_ruleset; then
        DISCOVERED_RULES=("${RULES[@]}")
        DISCOVERED_RULES_SOURCE="${RULES_SOURCE}"
        DISCOVERED_RULE_COUNT=${#DISCOVERED_RULES[@]}
    fi

    RULES=("${saved_rules[@]}")
    RULES_SOURCE="${saved_source}"
    DISCOVERY_CACHE_READY="1"
    [[ ${DISCOVERED_RULE_COUNT} -gt 0 ]]
}

validate_rule_name() {
    local value="$1"
    [[ -n "${value}" ]] || return 1
    [[ ${#value} -le 48 ]] || return 1
    [[ "${value}" != *'|'* ]] || return 1
    [[ "${value}" != *$'\n'* ]] || return 1
    [[ "${value}" != *$'\r'* ]] || return 1
    [[ "${value}" == "$(trim "${value}")" ]]
}

validate_rule_id() {
    local value="$1"
    [[ -n "${value}" ]] || return 1
    [[ "${value}" =~ ^[A-Za-z0-9._-]+$ ]]
}

normalize_proto() {
    local value
    value="$(trim "${1}")"
    value="${value,,}"
    case "${value}" in
        both|all|tcp+udp|tcpudp|"")
            printf 'both\n'
            ;;
        tcp)
            printf 'tcp\n'
            ;;
        udp)
            printf 'udp\n'
            ;;
        *)
            return 1
            ;;
    esac
}

proto_to_label() {
    case "$1" in
        tcp) printf 'tcp' ;;
        udp) printf 'udp' ;;
        *) printf 'tcp+udp' ;;
    esac
}

proto_to_nft_expr() {
    case "$1" in
        tcp) printf 'tcp' ;;
        udp) printf 'udp' ;;
        *) printf '{ tcp, udp }' ;;
    esac
}

normalize_snat_mode() {
    local value
    value="$(trim "${1:-}")"
    value="${value,,}"
    case "${value}" in
        ""|1|relay|relay_lan|lan|inner|private|po0|po0_lan)
            printf 'relay_lan\n'
            ;;
        2|masq|masquerade|public|wan|egress|route)
            printf 'masquerade\n'
            ;;
        3|none|no|off|disable|disabled|keep|transparent)
            printf 'none\n'
            ;;
        *)
            return 1
            ;;
    esac
}

normalize_relay_mode() {
    local value
    value="$(trim "${1:-}")"
    value="${value,,}"
    case "${value}" in
        1|lan|relay_lan|inner|private|po0|po0_lan)
            printf 'lan\n'
            ;;
        2|public|wan|masq|masquerade|egress)
            printf 'public\n'
            ;;
        ""|3|mixed|both|hybrid|all)
            printf 'mixed\n'
            ;;
        *)
            return 1
            ;;
    esac
}

relay_mode_to_label() {
    case "$1" in
        lan)
            printf '纯内网/无感内网转发'
            ;;
        public)
            printf '公网转发'
            ;;
        *)
            printf '内网/公网混合转发'
            ;;
    esac
}

relay_mode_uses_lan() {
    [[ "${RELAY_MODE}" == "lan" || "${RELAY_MODE}" == "mixed" ]]
}

relay_mode_default_snat_mode() {
    case "${RELAY_MODE}" in
        public)
            printf 'masquerade\n'
            ;;
        *)
            printf 'relay_lan\n'
            ;;
    esac
}

snat_mode_to_label() {
    case "$1" in
        masquerade)
            printf '公网出口'
            ;;
        none)
            printf '透明转发'
            ;;
        *)
            printf '内网回源'
            ;;
    esac
}

snat_mode_to_short() {
    case "$1" in
        masquerade)
            printf 'masq'
            ;;
        none)
            printf 'none'
            ;;
        *)
            printf 'lan'
            ;;
    esac
}

protocols_overlap() {
    case "$1:$2" in
        both:*|*:both|tcp:tcp|udp:udp)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

enabled_to_label() {
    if [[ "$1" == "1" ]]; then
        printf '%b启用%b' "${C_GREEN}" "${C_RESET}"
    else
        printf '%b停用%b' "${C_DIM}" "${C_RESET}"
    fi
}

enabled_to_short() {
    if [[ "$1" == "1" ]]; then
        printf '%bON %b' "${C_GREEN}" "${C_RESET}"
    else
        printf '%bOFF%b' "${C_DIM}" "${C_RESET}"
    fi
}

generate_rule_id() {
    printf 'r%s%04d' "$(date '+%Y%m%d%H%M%S')" "$((RANDOM % 10000))"
}

rule_id_exists() {
    local id="$1"
    local rule
    for rule in "${RULES[@]}" "${IMPORTED_RULES[@]}"; do
        [[ -n "${rule}" ]] || continue
        parse_rule "${rule}"
        [[ "${RULE_ID}" == "${id}" ]] && return 0
    done
    return 1
}

generate_unique_rule_id() {
    local id attempts=0
    while (( attempts < 100 )); do
        id="$(generate_rule_id)"
        rule_id_exists "${id}" || {
            printf '%s\n' "${id}"
            return 0
        }
        ((attempts++))
    done

    while true; do
        id="r$(date '+%Y%m%d%H%M%S')${RANDOM}${RANDOM}"
        rule_id_exists "${id}" || {
            printf '%s\n' "${id}"
            return 0
        }
    done
}

serialize_rule() {
    local snat_mode="${8:-relay_lan}"
    snat_mode="$(normalize_snat_mode "${snat_mode}" 2>/dev/null || printf 'relay_lan')"
    printf '%s|%s|%s|%s|%s|%s|%s|%s' "$1" "$2" "$3" "$4" "$5" "$6" "$7" "${snat_mode}"
}

parse_rule() {
    IFS='|' read -r RULE_ID RULE_NAME RULE_PROTO RULE_LPORT RULE_DIP RULE_DPORT RULE_ENABLED RULE_SNAT_MODE _ <<< "$1"
    RULE_SNAT_MODE="$(normalize_snat_mode "${RULE_SNAT_MODE:-relay_lan}" 2>/dev/null || printf 'relay_lan')"
}

rule_name_exists() {
    local name="$1"
    local skip_id="${2-}"
    local rule
    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        [[ "${RULE_ID}" == "${skip_id}" ]] && continue
        [[ "${RULE_NAME}" == "${name}" ]] && return 0
    done
    return 1
}

rule_port_conflict_exists() {
    local listen_port="$1"
    local proto="$2"
    local skip_id="${3-}"
    local rule
    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        [[ "${RULE_ID}" == "${skip_id}" ]] && continue
        [[ "${RULE_LPORT}" == "${listen_port}" ]] || continue
        protocols_overlap "${RULE_PROTO}" "${proto}" && return 0
    done
    return 1
}

refresh_rule_counts() {
    local rule
    RULE_TOTAL=${#RULES[@]}
    RULE_ENABLED_COUNT=0
    RULE_DISABLED_COUNT=0
    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        if [[ "${RULE_ENABLED}" == "1" ]]; then
            ((RULE_ENABLED_COUNT++))
        else
            ((RULE_DISABLED_COUNT++))
        fi
    done
}

detect_pkg_manager() {
    if command -v apt-get &>/dev/null; then
        echo apt
    elif command -v dnf &>/dev/null; then
        echo dnf
    elif command -v yum &>/dev/null; then
        echo yum
    elif command -v pacman &>/dev/null; then
        echo pacman
    else
        echo unknown
    fi
}

install_nftables_if_needed() {
    local pkg_mgr
    command -v nft &>/dev/null && return 0
    pkg_mgr="$(detect_pkg_manager)"
    case "${pkg_mgr}" in
        apt) apt-get update -y && apt-get install -y nftables ;;
        dnf) dnf install -y nftables ;;
        yum) yum install -y nftables ;;
        pacman) pacman -Sy --noconfirm nftables ;;
        *)
            err "无法识别包管理器，请手动安装 nftables。"
            return 1
            ;;
    esac
    command -v nft &>/dev/null || {
        err "nftables 安装失败。"
        return 1
    }
}

install_conntrack_if_needed() {
    local pkg_mgr
    command -v conntrack &>/dev/null && return 0
    pkg_mgr="$(detect_pkg_manager)"
    case "${pkg_mgr}" in
        apt) apt-get update -y && apt-get install -y conntrack ;;
        dnf) dnf install -y conntrack-tools ;;
        yum) yum install -y conntrack-tools ;;
        pacman) pacman -Sy --noconfirm conntrack-tools ;;
        *)
            err "无法识别包管理器，请手动安装 conntrack。"
            return 1
            ;;
    esac
    command -v conntrack &>/dev/null || {
        err "conntrack 安装失败。"
        return 1
    }
}

python_venv_works() {
    local tmp
    command -v python3 &>/dev/null || return 1
    tmp="$(mktemp -d "/tmp/po0-ipdb-venv-test.XXXXXX")" || return 1
    if python3 -m venv "${tmp}" >/dev/null 2>&1 && [[ -x "${tmp}/bin/python" ]]; then
        rm -rf -- "${tmp}" 2>/dev/null || true
        return 0
    fi
    rm -rf -- "${tmp}" 2>/dev/null || true
    return 1
}

install_ipdb_python_base_if_needed() {
    local pkg_mgr
    if python_venv_works; then
        return 0
    fi
    pkg_mgr="$(detect_pkg_manager)"
    case "${pkg_mgr}" in
        apt)
            apt-get update -y && apt-get install -y python3 python3-venv python3-pip
            ;;
        dnf)
            dnf install -y python3 python3-pip
            ;;
        yum)
            yum install -y python3 python3-pip
            ;;
        pacman)
            pacman -Sy --noconfirm python python-pip
            ;;
        *)
            err "无法识别包管理器，请手动安装 python3、venv 和 pip。"
            return 1
            ;;
    esac
    command -v python3 &>/dev/null || {
        err "python3 安装失败。"
        return 1
    }
    python_venv_works || {
        err "python3 venv 仍不可用。Debian/Ubuntu 请确认已安装 python3-venv 或当前版本对应的 python3.x-venv。"
        return 1
    }
}

ipdb_venv_has_pip() {
    [[ -x "${IPDB_VENV_PYTHON}" ]] || return 1
    "${IPDB_VENV_PYTHON}" -m pip --version >/dev/null 2>&1
}

create_ipdb_venv() {
    rm -rf -- "${IPDB_VENV_DIR}" 2>/dev/null || true
    python3 -m venv "${IPDB_VENV_DIR}" || return 1
    ipdb_venv_has_pip && return 0
    "${IPDB_VENV_PYTHON}" -m ensurepip --upgrade >/dev/null 2>&1 || return 1
    ipdb_venv_has_pip
}

pip_index_label() {
    case "$1" in
        https://mirrors.cloud.tencent.com/pypi/simple) printf '腾讯云 PyPI 镜像' ;;
        https://pypi.tuna.tsinghua.edu.cn/simple) printf '清华 PyPI 镜像' ;;
        https://mirrors.aliyun.com/pypi/simple/) printf '阿里云 PyPI 镜像' ;;
        https://pypi.org/simple) printf '官方 PyPI' ;;
        *) printf '%s' "$1" ;;
    esac
}

prompt_ipdb_pip_index() {
    local choice custom
    echo "请选择 pip 安装源：" >&2
    echo "  1) 腾讯云 PyPI 镜像（推荐）" >&2
    echo "  2) 清华 PyPI 镜像" >&2
    echo "  3) 阿里云 PyPI 镜像" >&2
    echo "  4) 官方 PyPI" >&2
    echo "  5) 自定义源" >&2
    read -r -p "请选择 [1-5，默认: 腾讯云 PyPI 镜像]: " choice
    case "${choice:-1}" in
        1) printf '%s\n' "https://mirrors.cloud.tencent.com/pypi/simple" ;;
        2) printf '%s\n' "https://pypi.tuna.tsinghua.edu.cn/simple" ;;
        3) printf '%s\n' "https://mirrors.aliyun.com/pypi/simple/" ;;
        4) printf '%s\n' "https://pypi.org/simple" ;;
        5)
            custom="$(prompt_with_default "请输入 pip simple 源 URL" "${IPDB_DEFAULT_PIP_INDEX_URL}")"
            if [[ ! "${custom}" =~ ^https?:// ]]; then
                err "pip 源 URL 必须以 http:// 或 https:// 开头。"
                return 1
            fi
            printf '%s\n' "${custom}"
            ;;
        *)
            err "无效选择。"
            return 1
            ;;
    esac
}

install_ipdb_parser_package() {
    local pip_index_url
    pip_index_url="${IPDB_PIP_INDEX_URL:-${IPDB_DEFAULT_PIP_INDEX_URL}}"
    warn "将从 $(pip_index_label "${pip_index_url}") 安装；如果该源不可达，会在超时后失败。"
    "${IPDB_VENV_PYTHON}" -m pip install \
        --disable-pip-version-check \
        --index-url "${pip_index_url}" \
        --retries 1 \
        --timeout 20 \
        --upgrade \
        ipip-ipdb
}

install_ipdb_parser_dependency() {
    ensure_layout || return 1
    install_ipdb_python_base_if_needed || return 1
    if ! ipdb_venv_has_pip; then
        if [[ -x "${IPDB_VENV_PYTHON}" ]]; then
            warn "检测到旧的 IPDB venv 缺少 pip，将删除并重建。"
        fi
        if ! create_ipdb_venv; then
            warn "首次创建 IPDB 专用 venv 失败，尝试重新安装 Python venv 组件后重试。"
            install_ipdb_python_base_if_needed || return 1
            create_ipdb_venv || {
                err "创建 IPDB 专用 Python venv 失败：${IPDB_VENV_DIR}"
                err "如果仍看到 No module named pip，请手动安装 python3-venv 或 python3.x-venv 后重试。"
                return 1
            }
        fi
    fi
    install_ipdb_parser_package || {
        err "安装 ipip-ipdb 失败。"
        err "如果当前 pip 源不可达，请重新运行安装入口并选择其它镜像源或自定义源。"
        return 1
    }
    if ! "${IPDB_VENV_PYTHON}" - <<'PY' >/dev/null 2>&1
import ipdb
assert hasattr(ipdb, "City")
PY
    then
        err "ipip-ipdb 安装后仍无法导入。"
        return 1
    fi
    success "IPDB 解析依赖已安装到 ${IPDB_VENV_DIR}。"
}

warn_conflicts() {
    local found=0
    if systemctl is-active --quiet firewalld 2>/dev/null; then
        warn "检测到 firewalld 正在运行，托管式 nftables 中转脚本不建议与其混用。"
        found=1
    fi
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -qw active; then
        warn "检测到 UFW 正在运行，托管式 nftables 中转脚本不建议与其混用。"
        found=1
    fi
    (( found == 1 )) && warn "如继续初始化，将由 nftables 独占接管这台中转机。"
}

ensure_layout() {
    mkdir -p "${CONF_DIR}" "${BACKUP_DIR}" "${EXPORT_DIR}" "${ALLOWLIST_PROFILE_DIR}" "${RESOURCE_INBOX_DIR}" || return 1
    [[ -f "${SETTINGS_FILE}" ]] || save_settings
    [[ -f "${RULES_FILE}" ]] || save_rules
    [[ -f "${ALLOWLIST_SETS_FILE}" ]] || save_allowlist_sets
    [[ -f "${ALLOWLIST_ENTRIES_FILE}" ]] || ensure_allowlist_entries_file
    [[ -f "${ALLOWLIST_SOURCES_FILE}" ]] || ensure_allowlist_sources_file
    [[ -f "${BLOCK_LOG_FILE}" ]] || ensure_block_log_file
    [[ -f "${BLOCK_SUMMARY_FILE}" ]] || regenerate_block_summary
    [[ -f "${AUTO_PENDING_FILE}" ]] || ensure_auto_pending_file
    [[ -f "${CLIENT_IP_REPORT_STATS_FILE}" ]] || ensure_generic_report_stats_file "${CLIENT_IP_REPORT_STATS_FILE}"
    [[ -f "${SSH_REPORT_STATS_FILE}" ]] || ensure_generic_report_stats_file "${SSH_REPORT_STATS_FILE}"
    [[ -f "${WEBAUTH_REPORT_STATS_FILE}" ]] || ensure_generic_report_stats_file "${WEBAUTH_REPORT_STATS_FILE}"
    [[ -f "${RESOURCE_TASKS_FILE}" ]] || resource_task_write_header "${RESOURCE_TASKS_FILE}"
}

manager_controls_main_conf() {
    [[ -f "${MAIN_CONF}" ]] || return 1
    [[ -f "${NFT_CONF}" ]] || return 1
    grep -Fq 'include "/etc/nftables.d/*.conf"' "${MAIN_CONF}" 2>/dev/null
}

apply_or_save_notice() {
    local applied_msg="$1"
    local saved_msg="$2"
    if manager_controls_main_conf; then
        reload_managed_rules || return 1
        success "${applied_msg}"
    else
        success "${saved_msg}"
        info "当前运行中的 nftables 尚未由脚本接管；执行 [1] 安装 / 初始化 nftables 后，托管配置才会统一接管并生效。"
    fi
}

backup_takeover_files() {
    local ts file
    ts="$(date '+%Y%m%d_%H%M%S')"
    [[ -f "${MAIN_CONF}" ]] && mv "${MAIN_CONF}" "${MAIN_CONF}.bak.${ts}" 2>/dev/null || true
    for file in "${CONF_DIR}"/*.conf; do
        [[ -f "${file}" ]] || continue
        mv "${file}" "${file}.bak.${ts}" 2>/dev/null || true
    done
}

backup_managed_files() {
    local ts file
    ts="$(date '+%Y%m%d_%H%M%S')"
    for file in "${NFT_CONF}" "${SETTINGS_FILE}" "${RULES_FILE}" "${SRC_ALLOWLIST_CACHE}" "${CUSTOM_SRC_ALLOWLIST_FILE}" "${ALLOWLIST_SETS_FILE}" "${ALLOWLIST_ENTRIES_FILE}" "${ALLOWLIST_SOURCES_FILE}" "${DDNS_REPORT_STATS_FILE}" "${CLIENT_IP_REPORT_STATS_FILE}" "${SSH_REPORT_STATS_FILE}" "${WEBAUTH_REPORT_STATS_FILE}" "${AUTO_PENDING_FILE}" "${BLOCK_LOG_FILE}" "${BLOCK_SUMMARY_FILE}"; do
        [[ -f "${file}" ]] && cp "${file}" "${BACKUP_DIR}/$(basename "${file}").${ts}" 2>/dev/null || true
    done
}

unquote_setting_value() {
    local value="$1"
    value="$(trim "${value}")"
    if [[ "${value}" =~ ^\".*\"$ ]]; then
        value="${value:1:${#value}-2}"
    elif [[ "${value}" =~ ^\'.*\'$ ]]; then
        value="${value:1:${#value}-2}"
    fi
    printf '%s\n' "${value}"
}

read_settings_file() {
    local line key raw_value value
    [[ -f "${SETTINGS_FILE}" ]] || return 0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        line="$(trim "${line}")"
        [[ -z "${line}" ]] && continue
        [[ "${line}" =~ ^# ]] && continue
        [[ "${line}" == *=* ]] || continue
        key="$(trim "${line%%=*}")"
        raw_value="${line#*=}"
        value="$(unquote_setting_value "${raw_value}")"
        case "${key}" in
            RELAY_MODE)
                RELAY_MODE="${value}"
                ;;
            RELAY_LAN_IP)
                RELAY_LAN_IP="${value}"
                ;;
            PUBLIC_IP)
                PUBLIC_IP="${value}"
                ;;
            PUBLIC_IP_SOURCE)
                PUBLIC_IP_SOURCE="${value}"
                ;;
            ENABLE_MSS_CLAMP)
                ENABLE_MSS_CLAMP="${value}"
                ;;
            MSS_VALUE)
                MSS_VALUE="${value}"
                ;;
            MANAGE_INPUT_FIREWALL)
                MANAGE_INPUT_FIREWALL="${value}"
                ;;
            SSH_PORTS)
                SSH_PORTS="${value}"
                ;;
            ENABLE_SRC_ALLOWLIST)
                ENABLE_SRC_ALLOWLIST="${value}"
                ;;
            SRC_ALLOWLIST_MODE)
                SRC_ALLOWLIST_MODE="${value}"
                ;;
            SRC_ALLOWLIST_REGION_IDS)
                SRC_ALLOWLIST_REGION_IDS="${value}"
                ;;
            AUTOMATION_MODE)
                AUTOMATION_MODE="${value}"
                ;;
        esac
    done < "${SETTINGS_FILE}"
}

load_settings() {
    local force_reload="${1:-0}"
    if [[ "${SETTINGS_CACHE_READY}" == "1" && "${force_reload}" != "1" ]]; then
        return 0
    fi
    RELAY_MODE="mixed"
    RELAY_LAN_IP=""
    PUBLIC_IP=""
    PUBLIC_IP_CACHE=""
    PUBLIC_IP_CACHE_SOURCE="none"
    ENABLE_MSS_CLAMP="1"
    MSS_VALUE="1452"
    MANAGE_INPUT_FIREWALL="1"
    SSH_PORTS=""
    ENABLE_SRC_ALLOWLIST="0"
    SRC_ALLOWLIST_MODE="trusted_dynamic"
    SRC_ALLOWLIST_REGION_IDS=""
    AUTOMATION_MODE="regular"
    RELAY_LAN_IP_SOURCE="none"
    PUBLIC_IP_SOURCE="none"
    read_settings_file
    RELAY_MODE="$(normalize_relay_mode "${RELAY_MODE}" 2>/dev/null || printf 'mixed')"
    if validate_host_ipv4 "${RELAY_LAN_IP}"; then
        RELAY_LAN_IP_SOURCE="settings"
    fi
    if is_public_ipv4 "${PUBLIC_IP}"; then
        case "${PUBLIC_IP_SOURCE}" in
            system|online|manual)
                ;;
            *)
                PUBLIC_IP_SOURCE="settings"
                ;;
        esac
        PUBLIC_IP_CACHE="${PUBLIC_IP}"
        PUBLIC_IP_CACHE_SOURCE="${PUBLIC_IP_SOURCE}"
    else
        PUBLIC_IP=""
        PUBLIC_IP_SOURCE="none"
    fi
    [[ "${ENABLE_MSS_CLAMP}" == "0" || "${ENABLE_MSS_CLAMP}" == "1" ]] || ENABLE_MSS_CLAMP="1"
    validate_mss "${MSS_VALUE}" || MSS_VALUE="1452"
    [[ "${MANAGE_INPUT_FIREWALL}" == "0" || "${MANAGE_INPUT_FIREWALL}" == "1" ]] || MANAGE_INPUT_FIREWALL="1"
    SSH_PORTS="$(normalize_port_list "${SSH_PORTS}")"
    if [[ "${MANAGE_INPUT_FIREWALL}" == "1" && -z "${SSH_PORTS}" ]]; then
        SSH_PORTS="$(detect_ssh_ports || true)"
    fi
    SSH_PORTS="$(normalize_port_list "${SSH_PORTS}")"
    [[ "${ENABLE_SRC_ALLOWLIST}" == "0" || "${ENABLE_SRC_ALLOWLIST}" == "1" ]] || ENABLE_SRC_ALLOWLIST="0"
    SRC_ALLOWLIST_MODE="$(normalize_src_allowlist_mode "${SRC_ALLOWLIST_MODE}" 2>/dev/null || printf 'trusted_dynamic')"
    SRC_ALLOWLIST_REGION_IDS="$(normalize_region_ids "${SRC_ALLOWLIST_REGION_IDS}")"
    case "${AUTOMATION_MODE}" in
        regular|attack) ;;
        *) AUTOMATION_MODE="regular" ;;
    esac
    SETTINGS_CACHE_READY="1"
}

save_settings() {
    local tmp
    make_temp_file "${SETTINGS_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    RELAY_MODE="$(normalize_relay_mode "${RELAY_MODE}" 2>/dev/null || printf 'mixed')"
    if validate_host_ipv4 "${RELAY_LAN_IP}"; then
        RELAY_LAN_IP_SOURCE="settings"
    else
        RELAY_LAN_IP=""
        RELAY_LAN_IP_SOURCE="none"
    fi
    if ! is_public_ipv4 "${PUBLIC_IP}"; then
        PUBLIC_IP=""
        PUBLIC_IP_SOURCE="none"
    fi
    SRC_ALLOWLIST_MODE="$(normalize_src_allowlist_mode "${SRC_ALLOWLIST_MODE}" 2>/dev/null || printf 'trusted_dynamic')"
    case "${AUTOMATION_MODE}" in
        regular|attack) ;;
        *) AUTOMATION_MODE="regular" ;;
    esac
    cat > "${tmp}" <<EOF
RELAY_MODE="${RELAY_MODE}"
RELAY_LAN_IP="${RELAY_LAN_IP}"
PUBLIC_IP="${PUBLIC_IP}"
PUBLIC_IP_SOURCE="${PUBLIC_IP_SOURCE}"
ENABLE_MSS_CLAMP="${ENABLE_MSS_CLAMP}"
MSS_VALUE="${MSS_VALUE}"
MANAGE_INPUT_FIREWALL="${MANAGE_INPUT_FIREWALL}"
SSH_PORTS="${SSH_PORTS}"
ENABLE_SRC_ALLOWLIST="${ENABLE_SRC_ALLOWLIST}"
SRC_ALLOWLIST_MODE="${SRC_ALLOWLIST_MODE}"
SRC_ALLOWLIST_REGION_IDS="${SRC_ALLOWLIST_REGION_IDS}"
AUTOMATION_MODE="${AUTOMATION_MODE}"
EOF
    mv -f "${tmp}" "${SETTINGS_FILE}"
    SETTINGS_CACHE_READY="1"
}

parse_rule_line() {
    local line="$1"
    local rid name proto lport dip dport enabled snat_mode
    local -a fields=()

    IFS='|' read -r -a fields <<< "${line}"
    case "${#fields[@]}" in
        3)
            rid="$(generate_unique_rule_id)"
            lport="$(trim "${fields[0]}")"
            dip="$(trim "${fields[1]}")"
            dport="$(trim "${fields[2]}")"
            proto="both"
            name="relay-${lport}"
            enabled="1"
            snat_mode="$(relay_mode_default_snat_mode)"
            ;;
        6)
            rid="$(generate_unique_rule_id)"
            name="$(trim "${fields[0]}")"
            proto="$(trim "${fields[1]}")"
            lport="$(trim "${fields[2]}")"
            dip="$(trim "${fields[3]}")"
            dport="$(trim "${fields[4]}")"
            enabled="$(trim "${fields[5]}")"
            snat_mode="$(relay_mode_default_snat_mode)"
            ;;
        7)
            if normalize_proto "$(trim "${fields[1]}")" >/dev/null 2>&1 \
                && validate_port "$(trim "${fields[2]}")" \
                && validate_host_ipv4 "$(trim "${fields[3]}")" \
                && validate_port "$(trim "${fields[4]}")" \
                && [[ "$(trim "${fields[5]}")" =~ ^[01]$ ]] \
                && normalize_snat_mode "$(trim "${fields[6]}")" >/dev/null 2>&1; then
                rid="$(generate_unique_rule_id)"
                name="$(trim "${fields[0]}")"
                proto="$(trim "${fields[1]}")"
                lport="$(trim "${fields[2]}")"
                dip="$(trim "${fields[3]}")"
                dport="$(trim "${fields[4]}")"
                enabled="$(trim "${fields[5]}")"
                snat_mode="$(trim "${fields[6]}")"
            else
                rid="$(trim "${fields[0]}")"
                name="$(trim "${fields[1]}")"
                proto="$(trim "${fields[2]}")"
                lport="$(trim "${fields[3]}")"
                dip="$(trim "${fields[4]}")"
                dport="$(trim "${fields[5]}")"
                enabled="$(trim "${fields[6]}")"
                snat_mode="relay_lan"
            fi
            ;;
        8)
            rid="$(trim "${fields[0]}")"
            name="$(trim "${fields[1]}")"
            proto="$(trim "${fields[2]}")"
            lport="$(trim "${fields[3]}")"
            dip="$(trim "${fields[4]}")"
            dport="$(trim "${fields[5]}")"
            enabled="$(trim "${fields[6]}")"
            snat_mode="$(trim "${fields[7]}")"
            ;;
        *)
            return 1
            ;;
    esac

    [[ -n "${rid}" ]] || rid="$(generate_unique_rule_id)"
    if ! validate_rule_id "${rid}" || rule_id_exists "${rid}"; then
        rid="$(generate_unique_rule_id)"
    fi
    proto="$(normalize_proto "${proto}")" || return 1
    [[ "${enabled}" == "0" || "${enabled}" == "1" ]] || return 1
    validate_rule_name "${name}" || return 1
    validate_listen_port_value "${lport}" || return 1
    validate_host_ipv4 "${dip}" || return 1
    validate_port "${dport}" || return 1
    snat_mode="$(normalize_snat_mode "${snat_mode}")" || return 1

    PARSED_RULE="$(serialize_rule "${rid}" "${name}" "${proto}" "${lport}" "${dip}" "${dport}" "${enabled}" "${snat_mode}")"
}

load_rules() {
    local force_reload="${1:-0}"
    local line
    if [[ "${RULES_CACHE_READY}" == "1" && "${force_reload}" != "1" ]]; then
        return 0
    fi
    RULES=()
    RULES_SOURCE="none"
    if [[ -f "${RULES_FILE}" ]]; then
        while IFS= read -r line || [[ -n "${line}" ]]; do
            line="${line%$'\r'}"
            line="${line#$'\ufeff'}"
            line="$(trim "${line}")"
            [[ -z "${line}" ]] && continue
            [[ "${line}" =~ ^# ]] && continue
            parse_rule_line "${line}" || continue
            RULES+=("${PARSED_RULE}")
        done < "${RULES_FILE}"
    fi
    if [[ ${#RULES[@]} -gt 0 ]]; then
        RULES_SOURCE="rules_file"
        RULES_CACHE_READY="1"
        return 0
    fi
    RULES_CACHE_READY="1"
}

save_rules() {
    local tmp
    local rule
    make_temp_file "${RULES_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    cat > "${tmp}" <<'EOF'
# Managed by nftables relay manager
# format: id|name|proto|listen_port|dest_ip|dest_port|enabled|snat_mode
EOF
    for rule in "${RULES[@]}"; do
        printf '%s\n' "${rule}" >> "${tmp}"
    done
    mv -f "${tmp}" "${RULES_FILE}"
    RULES_SOURCE="rules_file"
    RULES_CACHE_READY="1"
    clear_discovery_cache
}

settings_ready() {
    load_settings
    load_rules
    if ! relay_lan_snat_required; then
        return 0
    fi
    validate_host_ipv4 "${RELAY_LAN_IP}" || {
        err "当前存在内网/无感内网 SNAT 规则，但中转机内网 IP 尚未设置。请先执行【10】修改中转机参数。"
        return 1
    }
}

print_runtime_rule_hint() {
    [[ ${#RULES[@]} -eq 0 ]] || return 0
    discover_existing_rules || return 0
    printf '  现有 nft 规则 : %s 条（%s）\n' \
        "${DISCOVERED_RULE_COUNT}" \
        "$(rules_source_label "${DISCOVERED_RULES_SOURCE}")"
    printf '               可用 [1] 初始化接管或 [8] 导入托管配置。\n'
}

print_settings() {
    load_settings
    load_rules
    printf '中转模式    : %s\n' "$(relay_mode_to_label "${RELAY_MODE}")"
    if validate_host_ipv4 "${RELAY_LAN_IP}"; then
        printf '中转机内网 IP : %s (%s)\n' "${RELAY_LAN_IP}" "$(relay_ip_source_label)"
    else
        printf '中转机内网 IP : 未设置\n'
    fi
    if is_public_ipv4 "${PUBLIC_IP}"; then
        printf '公网 IP     : %s (%s)\n' "${PUBLIC_IP}" "$(public_ip_source_label)"
    else
        printf '公网 IP     : 未探测到（可用菜单 [14] 手动刷新）\n'
    fi
    if [[ ${#RULES[@]} -gt 0 && "${RULES_SOURCE}" != "rules_file" ]]; then
        printf '规则来源    : %s\n' "$(rules_source_label)"
    fi
    if [[ "${ENABLE_MSS_CLAMP}" == "1" ]]; then
        printf 'MSS 修正    : 开启 (%s)\n' "${MSS_VALUE}"
    else
        printf 'MSS 修正    : 关闭\n'
    fi
    if [[ "${MANAGE_INPUT_FIREWALL}" == "1" ]]; then
        printf '入站防火墙 : 接管（SSH: %s，其它未托管端口默认 drop）\n' "${SSH_PORTS:-未探测}"
    else
        printf '入站防火墙 : 不接管\n'
    fi
    if src_allowlist_enabled; then
        printf '源 IP 白名单 : 开启（%s，地区 %s / 自定义 %s）\n' \
            "$(src_allowlist_mode_to_label "${SRC_ALLOWLIST_MODE}")" \
            "$(src_allowlist_region_count)" \
            "$(custom_allowlist_count)"
    elif [[ "${ENABLE_SRC_ALLOWLIST}" == "1" ]]; then
        printf '源 IP 白名单 : 配置不完整（%s）\n' "$(src_allowlist_mode_to_label "${SRC_ALLOWLIST_MODE}")"
    else
        printf '源 IP 白名单 : 关闭\n'
    fi
    printf '学习服务    : %s\n' "$(learning_service_status_label)"
}

print_status_panel() {
    local nft_status ip_forward_status runtime_drift_summary runtime_drift_count runtime_drift_tables
    runtime_drift_count=""
    runtime_drift_tables=""
    load_settings
    load_rules
    refresh_rule_counts
    runtime_drift_summary="$(get_unmanaged_runtime_dnat_summary || true)"
    if [[ -n "${runtime_drift_summary}" ]]; then
        IFS='|' read -r runtime_drift_count runtime_drift_tables <<< "${runtime_drift_summary}"
    fi

    if command -v nft &>/dev/null; then
        nft_status="${C_GREEN}已安装${C_RESET}"
    else
        nft_status="${C_YELLOW}未安装${C_RESET}"
    fi

    if [[ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" == "1" ]]; then
        ip_forward_status="${C_GREEN}已开启${C_RESET}"
    else
        ip_forward_status="${C_YELLOW}未开启${C_RESET}"
    fi

    printf '%b当前状态%b\n' "${C_BOLD}" "${C_RESET}"
    printf '  nftables   : %b\n' "${nft_status}"
    printf '  IPv4 转发 : %b\n' "${ip_forward_status}"
    if manager_controls_main_conf; then
        printf '  接管状态   : 已接管\n'
    else
        printf '  接管状态   : 未接管（仅管理配置文件）\n'
    fi
    printf '  中转模式   : %s\n' "$(relay_mode_to_label "${RELAY_MODE}")"
    if validate_host_ipv4 "${RELAY_LAN_IP}"; then
        printf '  中转机内网IP : %s\n' "${RELAY_LAN_IP}"
        if [[ "${RELAY_LAN_IP_SOURCE}" != "settings" ]]; then
            printf '               %s\n' "$(relay_ip_source_label)"
        fi
    else
        printf '  中转机内网IP : 未设置\n'
    fi
    if is_public_ipv4 "${PUBLIC_IP}"; then
        printf '  公网 IP    : %s\n' "${PUBLIC_IP}"
        printf '               %s\n' "$(public_ip_source_label)"
    else
        printf '  公网 IP    : 未探测到（可用 [14] 手动刷新）\n'
    fi
    if [[ ${RULE_TOTAL} -gt 0 && "${RULES_SOURCE}" != "rules_file" ]]; then
        printf '  规则来源   : %s\n' "$(rules_source_label)"
    fi
    if [[ "${ENABLE_MSS_CLAMP}" == "1" ]]; then
        printf '  MSS 修正   : 开启 (%s)\n' "${MSS_VALUE}"
    else
        printf '  MSS 修正   : 关闭\n'
    fi
    if [[ "${MANAGE_INPUT_FIREWALL}" == "1" ]]; then
        printf '  入站防火墙 : 接管（SSH: %s，其它未托管端口默认 drop）\n' "${SSH_PORTS:-未探测}"
    else
        printf '  入站防火墙 : 不接管\n'
    fi
    if src_allowlist_enabled; then
        printf '  源 IP 白名单 : 开启（%s，地区 %s / 自定义 %s）\n' \
            "$(src_allowlist_mode_to_label "${SRC_ALLOWLIST_MODE}")" \
            "$(src_allowlist_region_count)" \
            "$(custom_allowlist_count)"
    elif [[ "${ENABLE_SRC_ALLOWLIST}" == "1" ]]; then
        printf '  源 IP 白名单 : 配置不完整（%s）\n' "$(src_allowlist_mode_to_label "${SRC_ALLOWLIST_MODE}")"
    else
        printf '  源 IP 白名单 : 关闭\n'
    fi
    printf '  学习服务   : %s（%s 条记录，%s；每日汇总 %s 天）\n' \
        "$(learning_service_status_label)" \
        "$(learning_log_count)" \
        "$(format_bytes "$(learning_log_size_bytes)")" \
        "$(learning_summary_count)"
    printf '  规则总数   : %s（启用 %s / 停用 %s）\n' "${RULE_TOTAL}" "${RULE_ENABLED_COUNT}" "${RULE_DISABLED_COUNT}"
    if [[ -n "${runtime_drift_count}" ]]; then
        printf '  额外生效规则 : %s 条脚本未管理的 DNAT 转发\n' "${runtime_drift_count}"
        [[ -n "${runtime_drift_tables}" ]] && printf '               所在 nft 表: %s\n' "${runtime_drift_tables}"
        printf '               说明: 这些规则正在生效，但修改脚本列表不会影响它们\n'
    fi
}

prompt_relay_mode() {
    local current="${1:-mixed}"
    local choice
    current="$(normalize_relay_mode "${current}" 2>/dev/null || printf 'mixed')"
    while true; do
        echo "选择中转机使用场景：" >&2
        echo "  1) 纯内网/无感内网转发：默认使用内网回源" >&2
        echo "  2) 公网转发：默认使用公网出口" >&2
        echo "  3) 内网/公网混合转发：新增规则时逐条选择" >&2
        read -r -p "请选择转发模式 [1=纯内网/无感内网转发, 2=公网转发, 3=内网/公网混合转发；当前: $(relay_mode_to_label "${current}")]: " choice
        choice="$(trim "${choice}")"
        case "${choice,,}" in
            "")
                printf '%s\n' "${current}"
                return 0
                ;;
            1|lan|relay_lan|inner|private|po0|po0_lan)
                printf 'lan\n'
                return 0
                ;;
            2|public|wan|masq|masquerade|egress)
                printf 'public\n'
                return 0
                ;;
            3|mixed|both|hybrid|all)
                printf 'mixed\n'
                return 0
                ;;
        esac
        err "使用场景只能选择 1 / 2 / 3。"
    done
}

refresh_cached_ips_for_mode() {
    if relay_mode_uses_lan && ! validate_host_ipv4 "${RELAY_LAN_IP}"; then
        if refresh_relay_lan_ip; then
            info "已自动探测并缓存中转机内网 IP：${RELAY_LAN_IP}"
        else
            warn "未能自动探测到中转机内网 IP。"
        fi
    fi

    if ! is_public_ipv4 "${PUBLIC_IP}"; then
        if refresh_public_ip; then
            info "已自动探测并缓存公网 IP：${PUBLIC_IP}"
        else
            warn "未能自动探测到公网 IP。"
        fi
    fi
    return 0
}

prompt_settings() {
    local input ans
    load_settings
    RELAY_MODE="$(prompt_relay_mode "${RELAY_MODE}")" || return
    refresh_cached_ips_for_mode || true
    if [[ "${RELAY_LAN_IP_SOURCE}" == "auto" ]]; then
        info "已自动探测到内网 IP：${RELAY_LAN_IP}"
    elif [[ "${RELAY_LAN_IP_SOURCE}" == "nft_conf" ]]; then
        info "已从现有 relay 配置回读到内网 IP：${RELAY_LAN_IP}"
    fi
    if relay_mode_uses_lan; then
        while true; do
            input="$(prompt_with_default "请输入中转机内网 IP（输入 none 可跳过）" "${RELAY_LAN_IP}")"
            input="$(trim "${input}")"
            if [[ -z "${input}" || "${input,,}" == "none" ]]; then
                if [[ "${RELAY_MODE}" == "lan" ]]; then
                    err "纯内网/无感内网模式必须设置中转机内网 IP。"
                    continue
                fi
                RELAY_LAN_IP=""
                RELAY_LAN_IP_SOURCE="none"
                break
            fi
            validate_host_ipv4 "${input}" && {
                RELAY_LAN_IP="${input}"
                RELAY_LAN_IP_SOURCE="settings"
                break
            }
            err "IP 地址无效，不能使用 0.0.0.0、127.0.0.1、169.254.x.x 或组播/保留地址。"
        done
    else
        RELAY_LAN_IP=""
        RELAY_LAN_IP_SOURCE="none"
    fi
    if [[ "${ENABLE_MSS_CLAMP}" == "1" ]]; then
        read -r -p "是否保留 MSS 修正（默认开启）[Y/n]: " ans
        [[ "${ans}" =~ ^[Nn]$ ]] && {
            ENABLE_MSS_CLAMP="0"
            return 0
        }
    else
        read -r -p "是否开启 MSS 修正 [y/N]: " ans
        [[ "${ans}" =~ ^[Yy]$ ]] || {
            ENABLE_MSS_CLAMP="0"
            return 0
        }
    fi
    ENABLE_MSS_CLAMP="1"
    while true; do
        input="$(prompt_with_default "请输入 MSS 值" "${MSS_VALUE}")"
        validate_mss "${input}" && {
            MSS_VALUE="${input}"
            return 0
        }
        err "MSS 值无效，请输入 536-65535。"
    done
}

prompt_input_firewall_settings() {
    local ans input
    SSH_PORTS="$(normalize_port_list "${SSH_PORTS}")"
    [[ -n "${SSH_PORTS}" ]] || SSH_PORTS="$(detect_ssh_ports || true)"
    SSH_PORTS="$(normalize_port_list "${SSH_PORTS}")"

    if [[ "${MANAGE_INPUT_FIREWALL}" == "1" ]]; then
        read -r -p "是否接管入站防火墙（保留 SSH，其它未托管端口默认 drop）[Y/n]: " ans
        [[ "${ans}" =~ ^[Nn]$ ]] && MANAGE_INPUT_FIREWALL="0" || MANAGE_INPUT_FIREWALL="1"
    else
        read -r -p "是否接管入站防火墙（保留 SSH，其它未托管端口默认 drop）[y/N]: " ans
        [[ "${ans}" =~ ^[Yy]$ ]] && MANAGE_INPUT_FIREWALL="1" || MANAGE_INPUT_FIREWALL="0"
    fi

    if [[ "${MANAGE_INPUT_FIREWALL}" == "1" ]]; then
        while true; do
            input="$(prompt_with_default "请输入 SSH 端口，多个用空格或逗号分隔" "${SSH_PORTS}")"
            input="$(normalize_port_list "${input}")"
            [[ -n "${input}" ]] && {
                SSH_PORTS="${input}"
                return 0
            }
            err "SSH 端口不能为空，否则默认 drop 入站会导致无法登录。"
        done
    fi
}

prompt_protocol() {
    local current="${1:-both}"
    local choice
    while true; do
        read -r -p "选择协议 [1=tcp+udp, 2=tcp, 3=udp，当前: $(proto_to_label "${current}")] : " choice
        choice="$(trim "${choice}")"
        case "${choice,,}" in
            "" )
                printf '%s\n' "${current}"
                return 0
                ;;
            1|both|all|tcp+udp|tcpudp)
                printf 'both\n'
                return 0
                ;;
            2|tcp)
                printf 'tcp\n'
                return 0
                ;;
            3|udp)
                printf 'udp\n'
                return 0
                ;;
        esac
        err "协议只能选择 1 / 2 / 3，或直接输入 tcp、udp、both。"
    done
}

prompt_snat_mode() {
    local current="${1:-relay_lan}"
    local choice
    current="$(normalize_snat_mode "${current}" 2>/dev/null || printf 'relay_lan')"
    while true; do
        echo "选择这条规则的回程模式：" >&2
        echo "  1) 内网回源：适合内网/无感内网目标" >&2
        echo "  2) 公网出口：适合普通公网目标" >&2
        echo "  3) 透明转发：保留客户端真实来源，要求目标机已有回程路由" >&2
        read -r -p "请选择回程模式 [1=内网回源, 2=公网出口, 3=透明转发；当前: $(snat_mode_to_label "${current}")]: " choice
        choice="$(trim "${choice}")"
        case "${choice,,}" in
            "")
                printf '%s\n' "${current}"
                return 0
                ;;
            1|relay|relay_lan|lan|inner|private|po0|po0_lan)
                printf 'relay_lan\n'
                return 0
                ;;
            2|masq|masquerade|public|wan|egress|route)
                printf 'masquerade\n'
                return 0
                ;;
            3|none|no|off|keep|transparent)
                warn "透明转发不会改写来源地址，目标机必须已有正确回程路由；大多数中转场景不需要它。" >&2
                confirm_yes "确认使用透明转发" || continue
                printf 'none\n'
                return 0
                ;;
        esac
        err "回程方式只能选择 1 / 2 / 3。"
    done
}

select_rule_snat_mode() {
    local current="${1:-}"
    if [[ "${RELAY_MODE}" == "mixed" ]]; then
        [[ -n "${current}" ]] || current="$(relay_mode_default_snat_mode)"
        prompt_snat_mode "${current}"
    else
        relay_mode_default_snat_mode
    fi
}

prompt_relay_lan_ip_if_needed() {
    local snat_mode="$1"
    local input
    [[ "${snat_mode}" == "relay_lan" ]] || return 0
    validate_host_ipv4 "${RELAY_LAN_IP}" && return 0

    warn "内网/无感内网 SNAT 模式需要中转机内网 IP。"
    while true; do
        input="$(prompt_with_default "请输入中转机内网 IP" "${RELAY_LAN_IP}")"
        input="$(trim "${input}")"
        validate_host_ipv4 "${input}" && {
            RELAY_LAN_IP="${input}"
            RELAY_LAN_IP_SOURCE="settings"
            return 0
        }
        err "IP 地址无效，不能使用 0.0.0.0、127.0.0.1、169.254.x.x 或组播/保留地址。"
    done
}

prompt_enabled_flag() {
    local current="${1:-1}"
    local choice
    while true; do
        read -r -p "规则状态 [1=启用, 2=停用，当前: $([[ "${current}" == "1" ]] && printf '启用' || printf '停用')] : " choice
        choice="$(trim "${choice}")"
        case "${choice}" in
            "")
                printf '%s\n' "${current}"
                return 0
                ;;
            1|on|ON|enable|ENABLE)
                printf '1\n'
                return 0
                ;;
            2|off|OFF|disable|DISABLE)
                printf '0\n'
                return 0
                ;;
        esac
        err "状态只能选择 1 或 2。"
    done
}

prompt_rule_name() {
    local default="$1"
    local skip_id="${2-}"
    local input
    while true; do
        input="$(prompt_with_default "规则名称" "${default}")"
        input="$(trim "${input}")"
        validate_rule_name "${input}" || {
            err "规则名称不能为空，不能包含 |，长度不能超过 48 个字符。"
            continue
        }
        rule_name_exists "${input}" "${skip_id}" && {
            err "规则名称已存在，请换一个。"
            continue
        }
        printf '%s\n' "${input}"
        return 0
    done
}

prompt_port_value() {
    local prompt="$1"
    local default="${2-}"
    local input
    while true; do
        input="$(prompt_with_default "${prompt}" "${default}")"
        input="$(trim "${input}")"
        validate_port "${input}" && {
            printf '%s\n' "${input}"
            return 0
        }
        err "端口无效。"
    done
}

prompt_listen_port_value() {
    local prompt="$1"
    local proto="$2"
    local default="${3-}"
    local allow_existing="${4-}"
    local input
    while true; do
        input="$(prompt_with_default "${prompt}" "${default}")"
        input="$(trim "${input}")"
        ensure_listen_port_allowed "${input}" "${proto}" || continue
        if [[ -n "${allow_existing}" && "${input}" == "${allow_existing}" ]]; then
            printf '%s\n' "${input}"
            return 0
        fi
        listen_port_in_forward_range "${input}" && {
            printf '%s\n' "${input}"
            return 0
        }
        err "监听端口必须在 ${FORWARD_PORT_MIN}-${FORWARD_PORT_MAX} 范围内；既有旧规则保持原端口时可继续兼容。"
    done
}

random_forward_listen_port() {
    local span=$((FORWARD_PORT_MAX - FORWARD_PORT_MIN + 1))
    local n

    if command -v shuf &>/dev/null; then
        shuf -i "${FORWARD_PORT_MIN}-${FORWARD_PORT_MAX}" -n 1
        return 0
    fi

    if command -v od &>/dev/null && [[ -r /dev/urandom ]]; then
        n="$(od -An -N4 -tu4 /dev/urandom 2>/dev/null | tr -d '[:space:]')"
        if [[ "${n}" =~ ^[0-9]+$ ]]; then
            printf '%s\n' "$((FORWARD_PORT_MIN + (n % span)))"
            return 0
        fi
    fi

    printf '%s\n' "$((FORWARD_PORT_MIN + (RANDOM % span)))"
}

choose_forward_listen_port() {
    local proto="${1:-both}"
    local port

    for _ in $(seq 1 "${FORWARD_PORT_RANDOM_TRIES}"); do
        port="$(random_forward_listen_port)"
        ensure_new_listen_port_allowed "${port}" "${proto}" >/dev/null 2>&1 || continue
        rule_port_conflict_exists "${port}" "${proto}" && continue
        printf '%s\n' "${port}"
        return 0
    done

    for ((port = FORWARD_PORT_MIN; port <= FORWARD_PORT_MAX; port++)); do
        ensure_new_listen_port_allowed "${port}" "${proto}" >/dev/null 2>&1 || continue
        rule_port_conflict_exists "${port}" "${proto}" && continue
        printf '%s\n' "${port}"
        return 0
    done

    return 1
}

prompt_ip_value() {
    local prompt="$1"
    local default="${2-}"
    local input
    while true; do
        input="$(prompt_with_default "${prompt}" "${default}")"
        input="$(trim "${input}")"
        validate_host_ipv4 "${input}" && {
            printf '%s\n' "${input}"
            return 0
        }
        err "IP 地址无效，不能使用 0.0.0.0、127.0.0.1、169.254.x.x 或组播/保留地址。"
    done
}

describe_rule() {
    parse_rule "$1"
    printf '%s [%s] :%s -> %s:%s (%s, %s)' \
        "${RULE_NAME}" \
        "$(proto_to_label "${RULE_PROTO}")" \
        "${RULE_LPORT}" \
        "${RULE_DIP}" \
        "${RULE_DPORT}" \
        "$([[ "${RULE_ENABLED}" == "1" ]] && printf '启用' || printf '停用')" \
        "$(snat_mode_to_label "${RULE_SNAT_MODE}")"
}

print_rule_line() {
    local idx="$1"
    parse_rule "$2"
    printf '%-4s %-8b %-10s :%-8s %-21s %-8s %s\n' \
        "${idx}." \
        "$(enabled_to_short "${RULE_ENABLED}")" \
        "$(proto_to_label "${RULE_PROTO}")" \
        "${RULE_LPORT}" \
        "${RULE_DIP}:${RULE_DPORT}" \
        "$(snat_mode_to_short "${RULE_SNAT_MODE}")" \
        "${RULE_NAME}"
}

print_rules_table() {
    local idx=1
    local rule
    refresh_rule_counts
    if [[ ${#RULES[@]} -eq 0 ]]; then
        info "当前没有转发规则。"
        return 0
    fi
    printf '%b%-4s %-8s %-10s %-10s %-21s %-8s %s%b\n' \
        "${C_BOLD}" "#" "状态" "协议" "监听端口" "目标地址" "回程" "规则名称" "${C_RESET}"
    print_divider
    for rule in "${RULES[@]}"; do
        print_rule_line "${idx}" "${rule}"
        ((idx++))
    done
}

select_single_rule_index() {
    local max="$1"
    local choice
    while true; do
        read -r -p "请输入规则序号 [1-${max}, 0 取消]: " choice
        choice="$(trim "${choice}")"
        if [[ -z "${choice}" || "${choice}" == "0" ]]; then
            return 1
        fi
        if [[ "${choice}" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= max )); then
            printf '%s\n' "${choice}"
            return 0
        fi
        err "规则序号无效。"
    done
}

prompt_rule_position() {
    local max="$1"
    local default="${2-}"
    local choice
    while true; do
        choice="$(prompt_with_default "请输入目标位置 [1-${max}]" "${default}")"
        choice="$(trim "${choice}")"
        if [[ "${choice}" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= max )); then
            printf '%s\n' "${choice}"
            return 0
        fi
        err "目标位置无效。"
    done
}

declare -a SELECTED_INDICES=()

parse_selection() {
    local raw="$1"
    local max="$2"
    local token start end i
    local -a tokens=()
    local -A seen=()

    raw="${raw// /}"
    [[ -n "${raw}" ]] || return 1

    SELECTED_INDICES=()
    IFS=',' read -r -a tokens <<< "${raw}"
    for token in "${tokens[@]}"; do
        [[ -n "${token}" ]] || return 1
        if [[ "${token}" =~ ^[0-9]+-[0-9]+$ ]]; then
            start="${token%-*}"
            end="${token#*-}"
            (( start >= 1 && end >= start && end <= max )) || return 1
            for ((i=start; i<=end; i++)); do
                if [[ -z "${seen[$i]+x}" ]]; then
                    SELECTED_INDICES+=("${i}")
                    seen[$i]=1
                fi
            done
        elif [[ "${token}" =~ ^[0-9]+$ ]]; then
            (( token >= 1 && token <= max )) || return 1
            if [[ -z "${seen[$token]+x}" ]]; then
                SELECTED_INDICES+=("${token}")
                seen[$token]=1
            fi
        else
            return 1
        fi
    done

    [[ ${#SELECTED_INDICES[@]} -gt 0 ]]
}

print_selected_rules() {
    local idx
    for idx in "${SELECTED_INDICES[@]}"; do
        printf '  - %s\n' "$(describe_rule "${RULES[$((idx - 1))]}")"
    done
}

unique_dest_ip_set() {
    local seen=" "
    local out=""
    local rule
    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        [[ "${RULE_ENABLED}" == "1" ]] || continue
        [[ "${RULE_PROTO}" == "udp" ]] && continue
        if [[ "${seen}" != *" ${RULE_DIP} "* ]]; then
            [[ -n "${out}" ]] && out+=", "
            out+="${RULE_DIP}"
            seen+=" ${RULE_DIP} "
        fi
    done
    printf '%s' "${out}"
}

print_rule_counters() {
    local nft_text line current_chain name packets bytes
    local packets_value bytes_value
    local -A rule_packets=()
    local -A rule_bytes=()
    local rule

    command -v nft &>/dev/null || return 0
    nft_text="$(nft list table ip "${NAT_TABLE}" 2>/dev/null || true)"
    [[ -n "${nft_text}" ]] || {
        warn "当前未读取到 NAT 表规则计数。"
        return 0
    }

    current_chain=""
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ chain[[:space:]]+([A-Za-z0-9_-]+)[[:space:]]+\{ ]]; then
            current_chain="${BASH_REMATCH[1]}"
            continue
        fi
        [[ "${current_chain}" == "prerouting" ]] || continue
        [[ "${line}" =~ comment[[:space:]]+\"([^\"]+)\" ]] || continue
        name="${BASH_REMATCH[1]}"
        packets_value=0
        bytes_value=0
        if [[ "${line}" =~ counter[[:space:]]+packets[[:space:]]+([0-9]+)[[:space:]]+bytes[[:space:]]+([0-9]+) ]]; then
            packets_value="${BASH_REMATCH[1]}"
            bytes_value="${BASH_REMATCH[2]}"
        fi
        rule_packets["${name}"]="${packets_value}"
        rule_bytes["${name}"]="${bytes_value}"
    done <<< "${nft_text}"

    echo "规则命中计数:"
    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        packets="${rule_packets[${RULE_NAME}]:-0}"
        bytes="${rule_bytes[${RULE_NAME}]:-0}"
        printf '  - %-20s packets=%s bytes=%s\n' "${RULE_NAME}" "${packets}" "${bytes}"
    done
}

escape_nft_comment() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '%s' "${value}"
}

write_main_conf() {
    local tmp
    make_temp_file "${MAIN_CONF}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    cat > "${tmp}" <<'EOF'
#!/usr/sbin/nft -f
flush ruleset
include "/etc/nftables.d/*.conf"
EOF
    mv -f "${tmp}" "${MAIN_CONF}"
}

write_nft_conf() {
    local output="${1:-${NFT_CONF}}"
    local allowlist_cache="${2:-${SRC_ALLOWLIST_CACHE}}"
    local tmp
    local rule lport dip dport ip_set proto_expr comment
    local allowlist_active="0"
    local tcp_ports udp_ports
    local input_policy="accept"
    local ssh_ports_nft=""
    local relay_lan_ip_define
    make_temp_file "${output}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    load_settings
    load_rules
    load_allowlist_sets
    validate_managed_listen_ports || return 1
    if relay_lan_snat_required && ! validate_host_ipv4 "${RELAY_LAN_IP}"; then
        err "存在内网/无感内网 SNAT 规则，但中转机内网 IP 未设置。"
        return 1
    fi
    relay_lan_ip_define="${RELAY_LAN_IP:-0.0.0.0}"
    ensure_input_firewall_ready || return 1
    if [[ "${MANAGE_INPUT_FIREWALL}" == "1" ]]; then
        input_policy="drop"
        ssh_ports_nft="$(ports_to_nft_set "${SSH_PORTS}")"
    fi
    if [[ "${ENABLE_SRC_ALLOWLIST}" == "1" ]]; then
        validate_src_allowlist_ready || return 1
        build_src_allowlist_cache "${allowlist_cache}" || return 1
        allowlist_active="1"
    fi
    cat > "${tmp}" <<EOF
#!/usr/sbin/nft -f
# Managed by nftables relay manager
define RELAY_LAN_IP = ${relay_lan_ip_define}

table ip ${NAT_TABLE} {
EOF
    if [[ "${allowlist_active}" == "1" ]]; then
        write_nft_allowlist_set "${tmp}" "${allowlist_cache}" || return 1
    fi
    cat >> "${tmp}" <<EOF
    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
EOF
    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        [[ "${RULE_ENABLED}" == "1" ]] || continue
        proto_expr="$(proto_to_nft_expr "${RULE_PROTO}")"
        comment="$(escape_nft_comment "${RULE_NAME}")"
        if [[ "${allowlist_active}" == "1" ]]; then
            printf '\n        ip saddr @%s meta l4proto %s th dport %s counter dnat to %s:%s comment "%s"\n' \
                "$(default_allowlist_nft_set_name)" \
                "${proto_expr}" "${RULE_LPORT}" "${RULE_DIP}" "${RULE_DPORT}" "${comment}" >> "${tmp}"
        else
            printf '\n        meta l4proto %s th dport %s counter dnat to %s:%s comment "%s"\n' \
                "${proto_expr}" "${RULE_LPORT}" "${RULE_DIP}" "${RULE_DPORT}" "${comment}" >> "${tmp}"
        fi
    done
    cat >> "${tmp}" <<EOF
    }
EOF
    if [[ "${allowlist_active}" == "1" || "${MANAGE_INPUT_FIREWALL}" == "1" ]]; then
        tcp_ports="$(enabled_rule_ports_set tcp)"
        udp_ports="$(enabled_rule_ports_set udp)"
        cat >> "${tmp}" <<EOF

    chain input_guard {
        type filter hook input priority filter; policy ${input_policy};
EOF
        if [[ "${MANAGE_INPUT_FIREWALL}" == "1" ]]; then
            printf '        iifname "lo" counter accept comment "po0-allow-loopback"\n' >> "${tmp}"
            printf '        ct state established,related counter accept comment "po0-allow-established"\n' >> "${tmp}"
            printf '        ip protocol icmp counter accept comment "po0-allow-icmp"\n' >> "${tmp}"
            printf '        tcp dport { %s } counter accept comment "po0-allow-ssh"\n' "${ssh_ports_nft}" >> "${tmp}"
        fi
        if [[ "${allowlist_active}" == "1" ]]; then
            [[ -n "${tcp_ports}" ]] && printf '        ip saddr != @%s tcp dport { %s } limit rate 10/minute burst 20 packets log prefix "po0-block set=default proto=tcp " counter drop comment "po0-src-allowlist-tcp"\n' "$(default_allowlist_nft_set_name)" "${tcp_ports}" >> "${tmp}"
            [[ -n "${udp_ports}" ]] && printf '        ip saddr != @%s udp dport { %s } limit rate 10/minute burst 20 packets log prefix "po0-block set=default proto=udp " counter drop comment "po0-src-allowlist-udp"\n' "$(default_allowlist_nft_set_name)" "${udp_ports}" >> "${tmp}"
        fi
        cat >> "${tmp}" <<'EOF'
    }
EOF
    fi
    cat >> "${tmp}" <<EOF
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
EOF
    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        [[ "${RULE_ENABLED}" == "1" ]] || continue
        proto_expr="$(proto_to_nft_expr "${RULE_PROTO}")"
        comment="$(escape_nft_comment "${RULE_NAME}")"
        case "${RULE_SNAT_MODE}" in
            masquerade)
                printf '\n        ip daddr %s meta l4proto %s th dport %s ct status dnat counter masquerade comment "%s"\n' \
                    "${RULE_DIP}" "${proto_expr}" "${RULE_DPORT}" "${comment}" >> "${tmp}"
                ;;
            none)
                ;;
            *)
                printf '\n        ip daddr %s meta l4proto %s th dport %s ct status dnat counter snat to $RELAY_LAN_IP comment "%s"\n' \
                    "${RULE_DIP}" "${proto_expr}" "${RULE_DPORT}" "${comment}" >> "${tmp}"
                ;;
        esac
    done
    cat >> "${tmp}" <<EOF
    }
}
EOF
    if [[ "${ENABLE_MSS_CLAMP}" == "1" ]]; then
        ip_set="$(unique_dest_ip_set)"
        cat >> "${tmp}" <<EOF

table ip ${MANGLE_TABLE} {
    chain forward {
        type filter hook forward priority mangle; policy accept;
EOF
        [[ -n "${ip_set}" ]] && printf '        ip daddr { %s } tcp flags syn tcp option maxseg size set %s comment "po0-mss-clamp"\n' "${ip_set}" "${MSS_VALUE}" >> "${tmp}"
        cat >> "${tmp}" <<'EOF'
    }
}
EOF
    fi
    mv -f "${tmp}" "${output}"
}

reload_managed_rules() {
    nft -c -f "${NFT_CONF}" >/dev/null 2>&1 || {
        err "relay 配置预检失败，请检查 ${NFT_CONF}。"
        return 1
    }
    nft delete table ip "${NAT_TABLE}" 2>/dev/null || true
    nft delete table ip "${MANGLE_TABLE}" 2>/dev/null || true
    nft -f "${NFT_CONF}" || {
        err "加载 ${NFT_CONF} 失败。"
        return 1
    }
}

apply_full_config() {
    nft -c -f "${MAIN_CONF}" >/dev/null 2>&1 || {
        err "主配置预检失败。"
        return 1
    }
    nft -f "${MAIN_CONF}" || {
        err "加载 ${MAIN_CONF} 失败。"
        return 1
    }
}

enable_ip_forward() {
    mkdir -p "$(dirname "${SYSCTL_CONF}")" 2>/dev/null || true
    touch "${SYSCTL_CONF}" 2>/dev/null || true
    grep -qE '^[[:space:]]*net\.ipv4\.ip_forward[[:space:]]*=' "${SYSCTL_CONF}" 2>/dev/null \
        && sed -i -E 's|^[[:space:]]*net\.ipv4\.ip_forward[[:space:]]*=.*|net.ipv4.ip_forward=1|' "${SYSCTL_CONF}" 2>/dev/null \
        || echo "net.ipv4.ip_forward=1" >> "${SYSCTL_CONF}" 2>/dev/null
    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
    sysctl -p "${SYSCTL_CONF}" >/dev/null 2>&1 || true
}

enable_bbr_fq() {
    modprobe tcp_bbr 2>/dev/null || true
    grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null || {
        warn "当前内核不支持 BBR。"
        return 0
    }
    sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1 || true
    sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1 || true
    grep -qE '^[[:space:]]*net\.core\.default_qdisc[[:space:]]*=' "${SYSCTL_CONF}" 2>/dev/null \
        && sed -i -E 's|^[[:space:]]*net\.core\.default_qdisc[[:space:]]*=.*|net.core.default_qdisc=fq|' "${SYSCTL_CONF}" 2>/dev/null \
        || echo "net.core.default_qdisc=fq" >> "${SYSCTL_CONF}" 2>/dev/null
    grep -qE '^[[:space:]]*net\.ipv4\.tcp_congestion_control[[:space:]]*=' "${SYSCTL_CONF}" 2>/dev/null \
        && sed -i -E 's|^[[:space:]]*net\.ipv4\.tcp_congestion_control[[:space:]]*=.*|net.ipv4.tcp_congestion_control=bbr|' "${SYSCTL_CONF}" 2>/dev/null \
        || echo "net.ipv4.tcp_congestion_control=bbr" >> "${SYSCTL_CONF}" 2>/dev/null
    sysctl -p "${SYSCTL_CONF}" >/dev/null 2>&1 || true
    success "已写入 BBR + fq。"
}

check_port_conflict() {
    local port="$1"
    local proto="$2"
    ensure_listen_port_allowed "${port}" "${proto}"
}

show_import_format_hint() {
    echo "导入文件支持注释行和空行，推荐使用新格式："
    echo ""
    echo "  新格式: 名称|协议|监听端口|目标IP|目标端口|启用状态|回程方式"
    echo "  字段说明:"
    echo "    - 名称: 自定义规则名称，不能重复，不能包含 |"
    echo "    - 协议: both / tcp / udp"
    echo "    - 监听端口: 不能使用保留服务端口，也不能占用本机已有服务端口"
    echo "    - 启用状态: 1=启用, 0=停用"
    echo "    - 回程方式: relay_lan / masquerade / none"
    echo ""
    echo "  示例:"
    echo "    hk-relay|both|30080|10.0.0.2|443|1|relay_lan"
    echo "    public-api|tcp|30081|203.0.113.10|443|1|masquerade"
    echo "    transparent|tcp|30082|10.0.0.3|443|0|none"
    echo ""
    echo "  兼容旧格式: 监听端口|目标IP|目标端口 或 名称|协议|监听端口|目标IP|目标端口|启用状态"
    echo "  旧格式会自动补齐为:"
    echo "    - 名称: relay-监听端口"
    echo "    - 协议: both"
    echo "    - 启用状态: 1"
    echo "    - 回程方式: 跟随当前中转模式（混合模式下默认 relay_lan）"
}

write_import_template() {
    local path="$1"
    local tmp
    make_temp_file "${path}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    cat > "${tmp}" <<'EOF'
# nftables relay import template
# 说明:
# 1. 每行一条规则，支持空行和 # 注释行
# 2. 推荐格式:
#    名称|协议|监听端口|目标IP|目标端口|启用状态|回程方式
# 3. 协议支持:
#    both / tcp / udp
# 4. 启用状态:
#    1=启用, 0=停用
# 5. 回程方式:
#    relay_lan   = 内网/无感内网，SNAT 到中转机内网 IP
#    masquerade  = 普通公网转发，SNAT 到出口网卡地址
#    none        = 不改写源地址，要求目标机有回程路由
# 6. 兼容旧格式:
#    监听端口|目标IP|目标端口
#    未写回程方式时会跟随当前中转模式（混合模式下默认 relay_lan）

# 推荐新格式示例:
hk-relay|both|30080|10.0.0.2|443|1|relay_lan
public-api|tcp|30081|203.0.113.10|443|1|masquerade
transparent|tcp|30082|10.0.0.4|443|0|none

# 兼容旧格式示例:
# 30083|10.0.0.5|80
EOF
    mv -f "${tmp}" "${path}"
}

create_import_template_interactive() {
    local path
    ensure_layout || return 1
    path="$(prompt_with_default "模板输出路径" "${EXPORT_DIR}/po0-relay-import-template.txt")"
    path="$(trim "${path}")"
    [[ -n "${path}" ]] || {
        err "模板路径不能为空。"
        return 1
    }
    mkdir -p "$(dirname "${path}")" 2>/dev/null || true
    if [[ -e "${path}" ]]; then
        confirm_yes "模板文件已存在，是否覆盖" || return 1
    fi
    write_import_template "${path}"
    success "导入模板已生成：${path}"
    printf '你可以先编辑这个模板，再回到本菜单执行导入。\n'
    TEMPLATE_OUTPUT_PATH="${path}"
}

prompt_import_mode() {
    local choice
    while true; do
        read -r -p "导入模式 [1=追加导入, 2=覆盖现有规则]: " choice
        case "${choice}" in
            1)
                printf 'append\n'
                return 0
                ;;
            2)
                printf 'replace\n'
                return 0
                ;;
        esac
        err "无效选择。"
    done
}

load_import_rules() {
    local path="$1"
    local mode="$2"
    local line line_no=0 rule
    local candidate_id candidate_name candidate_proto candidate_lport candidate_dip candidate_dport candidate_enabled candidate_snat_mode
    IMPORTED_RULES=()

    while IFS= read -r line || [[ -n "${line}" ]]; do
        ((line_no++))
        line="${line%$'\r'}"
        line="${line#$'\ufeff'}"
        line="$(trim "${line}")"
        [[ -z "${line}" ]] && continue
        [[ "${line}" =~ ^# ]] && continue
        parse_rule_line "${line}" || {
            err "导入失败：第 ${line_no} 行格式无效。"
            return 1
        }

        parse_rule "${PARSED_RULE}"
        candidate_id="$(generate_unique_rule_id)"
        candidate_name="${RULE_NAME}"
        candidate_proto="${RULE_PROTO}"
        candidate_lport="${RULE_LPORT}"
        candidate_dip="${RULE_DIP}"
        candidate_dport="${RULE_DPORT}"
        candidate_enabled="${RULE_ENABLED}"
        candidate_snat_mode="${RULE_SNAT_MODE}"
        ensure_new_listen_port_allowed "${candidate_lport}" "${candidate_proto}" || {
            err "导入失败：监听端口 ${candidate_lport} 不可用。"
            return 1
        }
        PARSED_RULE="$(serialize_rule "${candidate_id}" "${candidate_name}" "${candidate_proto}" "${candidate_lport}" "${candidate_dip}" "${candidate_dport}" "${candidate_enabled}" "${candidate_snat_mode}")"

        for rule in "${IMPORTED_RULES[@]}"; do
            parse_rule "${rule}"
            if [[ "${RULE_NAME}" == "${candidate_name}" ]]; then
                err "导入失败：文件内存在重复规则名称。"
                return 1
            fi
            if [[ "${RULE_LPORT}" == "${candidate_lport}" ]] && protocols_overlap "${RULE_PROTO}" "${candidate_proto}"; then
                err "导入失败：文件内存在监听端口/协议冲突。"
                return 1
            fi
        done

        if [[ "${mode}" == "append" ]]; then
            rule_name_exists "${candidate_name}" && {
                err "导入失败：规则名称 ${candidate_name} 已存在。"
                return 1
            }
            rule_port_conflict_exists "${candidate_lport}" "${candidate_proto}" && {
                err "导入失败：监听端口 ${candidate_lport} 与现有规则冲突。"
                return 1
            }
        fi

        IMPORTED_RULES+=("${PARSED_RULE}")
    done < "${path}"

    [[ ${#IMPORTED_RULES[@]} -gt 0 ]] || {
        err "导入文件中没有可用规则。"
        return 1
    }
}

load_runtime_import_rules() {
    local rule
    discover_existing_rules 1 || {
        err "当前未检测到可导入的 nft 运行时规则。"
        return 1
    }
    IMPORTED_RULES=("${DISCOVERED_RULES[@]}")
    for rule in "${IMPORTED_RULES[@]}"; do
        parse_rule "${rule}"
        ensure_listen_port_allowed "${RULE_LPORT}" "${RULE_PROTO}" || return 1
    done
}

do_install() {
    print_title "安装 / 初始化 nftables"
    warn "该脚本按专用中转机思路工作，将接管 /etc/nftables.conf。"
    warn "初始化会 flush ruleset，并改写为 include /etc/nftables.d/*.conf。"
    warn_conflicts
    confirm_yes "是否继续初始化" || {
        info "已取消。"
        return
    }
    install_nftables_if_needed || return
    ensure_layout || return
    backup_takeover_files
    backup_managed_files
    load_rules
    if [[ ${#RULES[@]} -eq 0 ]] && discover_existing_rules 1; then
        warn "检测到当前系统已有 ${DISCOVERED_RULE_COUNT} 条 nft 运行时转发规则（$(rules_source_label "${DISCOVERED_RULES_SOURCE}")）。"
        RULES=("${DISCOVERED_RULES[@]}")
        print_rules_table
        RULES=()
        confirm_yes "是否在初始化时将这些规则导入为脚本托管规则" && {
            RULES=("${DISCOVERED_RULES[@]}")
            RULES_SOURCE="rules_file"
        }
    fi
    prompt_settings || return
    prompt_input_firewall_settings || return
    apply_relay_mode_to_rules
    save_settings || return
    save_rules || return
    write_main_conf || return
    write_nft_conf || return
    enable_ip_forward
    apply_full_config || return
    systemctl enable --now nftables 2>/dev/null || warn "无法自动启用 nftables 服务，请手动执行 systemctl enable --now nftables"
    success "初始化完成。"
    print_settings
}

do_list() {
    print_title "概览与规则列表"
    print_status_panel
    print_runtime_drift_hint
    print_runtime_rule_hint
    echo ""
    printf '%b源 IP 白名单%b\n' "${C_BOLD}" "${C_RESET}"
    print_src_allowlist_details
    echo ""
    print_rules_table
    pause_before_return
}

do_add() {
    local name proto lport dip dport enabled snat_mode rule default_lport
    print_title "新增转发规则"
    command -v nft &>/dev/null || {
        err "请先执行【1】安装/初始化。"
        return
    }
    settings_ready || return
    ensure_layout || return
    load_rules

    proto="$(prompt_protocol "both")" || return
    default_lport="$(choose_forward_listen_port "${proto}" || true)"
    lport="$(prompt_listen_port_value "请输入中转机监听端口" "${proto}" "${default_lport}")" || return
    rule_port_conflict_exists "${lport}" "${proto}" && {
        err "监听端口 ${lport} 与现有规则冲突。"
        return
    }
    dip="$(prompt_ip_value "请输入落地机 IP")" || return
    dport="$(prompt_port_value "请输入落地机端口" "${lport}")" || return
    snat_mode="$(select_rule_snat_mode)" || return
    prompt_relay_lan_ip_if_needed "${snat_mode}" || return
    name="$(prompt_rule_name "relay-${lport}")" || return
    enabled="$(prompt_enabled_flag "1")" || return

    echo "即将新增规则："
    printf '  - %s [%s] :%s -> %s:%s (%s)\n' \
        "${name}" "$(proto_to_label "${proto}")" "${lport}" "${dip}" "${dport}" \
        "$([[ "${enabled}" == "1" ]] && printf '启用' || printf '停用')"
    printf '  - 转发类型: %s\n' "$(snat_mode_to_label "${snat_mode}")"
    case "${snat_mode}" in
        relay_lan) printf '  - 回程源地址改写（SNAT）-> %s\n' "${RELAY_LAN_IP}" ;;
        masquerade) printf '  - 回程源地址改写（SNAT）-> 出口网卡地址（masquerade）\n' ;;
        none) printf '  - 回程源地址改写（SNAT）-> 不改写\n' ;;
    esac
    [[ "${ENABLE_MSS_CLAMP}" == "1" ]] && printf '  - TCP MSS 自动修正（MSS clamp）-> %s\n' "${MSS_VALUE}"
    confirm_yes "确认新增" || {
        info "已取消。"
        return
    }

    backup_managed_files
    rule="$(serialize_rule "$(generate_unique_rule_id)" "${name}" "${proto}" "${lport}" "${dip}" "${dport}" "${enabled}" "${snat_mode}")"
    RULES+=("${rule}")
    apply_relay_mode_to_rules
    save_settings || return
    save_rules || return
    write_nft_conf || return
    apply_or_save_notice "新增成功。" "规则已保存到托管配置。"
}

do_edit_rule() {
    local choice current rule proto lport dip dport name enabled snat_mode
    local current_id current_name current_proto current_lport current_dip current_dport current_enabled current_snat_mode
    print_title "编辑转发规则"
    command -v nft &>/dev/null || {
        err "请先执行【1】安装/初始化。"
        return
    }
    settings_ready || return
    load_rules
    [[ ${#RULES[@]} -gt 0 ]] || {
        info "当前没有转发规则。"
        return
    }

    print_rules_table
    choice="$(select_single_rule_index "${#RULES[@]}")" || {
        info "已取消。"
        return
    }

    current="${RULES[$((choice - 1))]}"
    parse_rule "${current}"
    current_id="${RULE_ID}"
    current_name="${RULE_NAME}"
    current_proto="${RULE_PROTO}"
    current_lport="${RULE_LPORT}"
    current_dip="${RULE_DIP}"
    current_dport="${RULE_DPORT}"
    current_enabled="${RULE_ENABLED}"
    current_snat_mode="${RULE_SNAT_MODE}"

    name="$(prompt_rule_name "${current_name}" "${current_id}")" || return
    proto="$(prompt_protocol "${current_proto}")" || return
    lport="$(prompt_listen_port_value "请输入中转机监听端口" "${proto}" "${current_lport}" "${current_lport}")" || return
    if rule_port_conflict_exists "${lport}" "${proto}" "${current_id}"; then
        err "监听端口 ${lport} 与现有规则冲突。"
        return
    fi
    dip="$(prompt_ip_value "请输入落地机 IP" "${current_dip}")" || return
    dport="$(prompt_port_value "请输入落地机端口" "${current_dport}")" || return
    snat_mode="$(select_rule_snat_mode "${current_snat_mode}")" || return
    prompt_relay_lan_ip_if_needed "${snat_mode}" || return
    enabled="$(prompt_enabled_flag "${current_enabled}")" || return

    rule="$(serialize_rule "${current_id}" "${name}" "${proto}" "${lport}" "${dip}" "${dport}" "${enabled}" "${snat_mode}")"
    echo "即将更新为："
    printf '  - %s\n' "$(describe_rule "${rule}")"
    confirm_yes "确认更新" || {
        info "已取消。"
        return
    }

    backup_managed_files
    RULES[$((choice - 1))]="${rule}"
    apply_relay_mode_to_rules
    save_settings || return
    save_rules || return
    write_nft_conf || return
    apply_or_save_notice "规则已更新。" "规则已保存到托管配置。"
}

do_reorder_rules() {
    local from to source_idx target_idx current i
    local -a remaining=()
    local -a reordered=()
    print_title "调整规则顺序"
    command -v nft &>/dev/null || {
        err "请先执行 [1] 安装 / 初始化。"
        return
    }
    settings_ready || return
    load_rules
    [[ ${#RULES[@]} -gt 1 ]] || {
        info "至少需要 2 条规则才能调整顺序。"
        return
    }

    print_rules_table
    from="$(select_single_rule_index "${#RULES[@]}")" || {
        info "已取消。"
        return
    }
    to="$(prompt_rule_position "${#RULES[@]}" "${from}")" || return
    if [[ "${from}" == "${to}" ]]; then
        info "规则顺序未变化。"
        return
    fi

    source_idx=$((from - 1))
    target_idx=$((to - 1))
    current="${RULES[${source_idx}]}"

    for i in "${!RULES[@]}"; do
        [[ "${i}" -eq "${source_idx}" ]] && continue
        remaining+=("${RULES[$i]}")
    done

    for ((i=0; i<=${#remaining[@]}; i++)); do
        if [[ "${i}" -eq "${target_idx}" ]]; then
            reordered+=("${current}")
        fi
        if [[ "${i}" -lt "${#remaining[@]}" ]]; then
            reordered+=("${remaining[$i]}")
        fi
    done

    echo "即将调整规则顺序："
    printf '  - %s\n' "$(describe_rule "${current}")"
    printf '  - 位置: %s -> %s\n' "${from}" "${to}"
    confirm_yes "确认调整" || {
        info "已取消。"
        return
    }

    backup_managed_files
    RULES=("${reordered[@]}")
    save_rules || return
    write_nft_conf || return
    apply_or_save_notice "规则顺序已更新。" "规则顺序已保存到托管配置。"
}

do_toggle_rules() {
    local action selection idx target updated need_relay_lan_ip=0
    print_title "启用 / 停用规则"
    command -v nft &>/dev/null || {
        err "请先执行【1】安装/初始化。"
        return
    }
    settings_ready || return
    load_rules
    [[ ${#RULES[@]} -gt 0 ]] || {
        info "当前没有转发规则。"
        return
    }

    print_rules_table
    read -r -p "请输入规则序号，支持 1,3,5-7: " selection
    parse_selection "${selection}" "${#RULES[@]}" || {
        err "序号格式无效。"
        return
    }

    read -r -p "操作类型 [1=启用, 2=停用, 3=切换]: " action
    case "${action}" in
        1) action="enable" ;;
        2) action="disable" ;;
        3) action="toggle" ;;
        *)
            err "无效选择。"
            return
            ;;
    esac

    for idx in "${SELECTED_INDICES[@]}"; do
        target="${RULES[$((idx - 1))]}"
        parse_rule "${target}"
        if [[ "${action}" == "enable" || ( "${action}" == "toggle" && "${RULE_ENABLED}" != "1" ) ]]; then
            ensure_new_listen_port_allowed "${RULE_LPORT}" "${RULE_PROTO}" || return
            [[ "${RULE_SNAT_MODE}" == "relay_lan" ]] && need_relay_lan_ip=1
        fi
    done
    if [[ "${need_relay_lan_ip}" == "1" ]]; then
        prompt_relay_lan_ip_if_needed "relay_lan" || return
    fi

    echo "即将处理以下规则："
    print_selected_rules
    confirm_yes "确认继续" || {
        info "已取消。"
        return
    }

    backup_managed_files
    for idx in "${SELECTED_INDICES[@]}"; do
        target="${RULES[$((idx - 1))]}"
        parse_rule "${target}"
        case "${action}" in
            enable) RULE_ENABLED="1" ;;
            disable) RULE_ENABLED="0" ;;
            toggle)
                if [[ "${RULE_ENABLED}" == "1" ]]; then
                    RULE_ENABLED="0"
                else
                    RULE_ENABLED="1"
                fi
                ;;
        esac
        updated="$(serialize_rule "${RULE_ID}" "${RULE_NAME}" "${RULE_PROTO}" "${RULE_LPORT}" "${RULE_DIP}" "${RULE_DPORT}" "${RULE_ENABLED}" "${RULE_SNAT_MODE}")"
        RULES[$((idx - 1))]="${updated}"
    done

    save_settings || return
    save_rules || return
    write_nft_conf || return
    apply_or_save_notice "规则状态已更新。" "规则状态已保存到托管配置。"
}

do_delete() {
    local selection idx
    print_title "删除转发规则"
    command -v nft &>/dev/null || {
        err "请先执行【1】安装/初始化。"
        return
    }
    settings_ready || return
    load_rules
    [[ ${#RULES[@]} -gt 0 ]] || {
        info "当前没有转发规则。"
        return
    }

    print_rules_table
    read -r -p "请输入要删除的规则序号，支持 1,3,5-7: " selection
    parse_selection "${selection}" "${#RULES[@]}" || {
        err "序号格式无效。"
        return
    }

    echo "即将删除以下规则："
    print_selected_rules
    confirm_yes "确认删除" || {
        info "已取消。"
        return
    }

    backup_managed_files
    for idx in "${SELECTED_INDICES[@]}"; do
        unset 'RULES[$((idx - 1))]'
    done
    RULES=("${RULES[@]}")
    save_rules || return
    write_nft_conf || return
    apply_or_save_notice "规则已删除。" "规则已从托管配置删除。"
}

do_import_rules() {
    local path mode choice source_kind="file"
    local -a current_rules=()
    local -a final_rules=()
    print_title "批量导入规则"
    command -v nft &>/dev/null || {
        err "请先执行【1】安装/初始化。"
        return
    }
    settings_ready || return
    ensure_layout || return
    load_rules

    show_import_format_hint
    echo ""
    echo "导入助手:"
    echo "  1) 直接导入规则文件"
    echo "  2) 先生成导入模板"
    echo "  3) 导入当前 nft 运行时规则"
    echo "  0) 返回"
    read -r -p "请选择操作 [0-3]: " choice
    case "${choice}" in
        1)
            mode="$(prompt_import_mode)" || return
            ;;
        2)
            create_import_template_interactive || {
                info "已取消。"
                return
            }
            echo ""
            confirm_yes "是否继续导入刚生成的模板文件" || {
                info "已返回上级菜单。"
                return
            }
            path="${TEMPLATE_OUTPUT_PATH}"
            mode="$(prompt_import_mode)" || return
            ;;
        3)
            source_kind="runtime"
            mode="replace"
            echo ""
            info "开始扫描当前 nft 运行时规则。"
            load_runtime_import_rules || return
            ;;
        0|"")
            info "已取消。"
            return
            ;;
        *)
            err "无效选择。"
            return
            ;;
    esac

    if [[ "${source_kind}" == "file" ]]; then
        if [[ -z "${path:-}" ]]; then
            path="$(prompt_with_default "请输入导入文件路径" "${EXPORT_DIR}/po0-relay-import-template.txt")"
        fi
        path="$(trim "${path}")"
        [[ -n "${path}" && -f "${path}" ]] || {
            err "导入文件不存在。"
            return
        }

        echo ""
        info "开始检查导入文件格式与规则冲突。"
        load_import_rules "${path}" "${mode}" || return
        echo ""
        info "导入文件检查通过。"
    else
        echo ""
        info "已从 $(rules_source_label "${DISCOVERED_RULES_SOURCE}") 读取到 ${#IMPORTED_RULES[@]} 条运行时规则。"
    fi

    current_rules=("${RULES[@]}")
    RULES=("${IMPORTED_RULES[@]}")
    apply_relay_mode_to_rules
    IMPORTED_RULES=("${RULES[@]}")
    echo "即将导入 ${#IMPORTED_RULES[@]} 条规则："
    print_rules_table
    RULES=("${current_rules[@]}")
    if [[ "${mode}" == "replace" ]]; then
        final_rules=("${IMPORTED_RULES[@]}")
    else
        final_rules=("${current_rules[@]}" "${IMPORTED_RULES[@]}")
    fi
    RULES=("${final_rules[@]}")
    apply_relay_mode_to_rules
    final_rules=("${RULES[@]}")
    if relay_lan_snat_required; then
        prompt_relay_lan_ip_if_needed "relay_lan" || {
            RULES=("${current_rules[@]}")
            return
        }
    fi
    RULES=("${current_rules[@]}")

    if [[ "${source_kind}" == "runtime" ]]; then
        warn "运行时导入会用当前 nft 规则快照覆盖脚本托管规则文件。"
        info "这一步先保存为托管配置；如果当前系统还没被脚本接管，不会强行改动正在运行的 nftables。"
    elif [[ "${mode}" == "replace" ]]; then
        warn "覆盖模式会替换当前全部规则。"
    else
        info "追加模式会保留现有规则，并在通过校验后追加导入。"
    fi
    confirm_yes "确认导入" || {
        info "已取消。"
        return
    }

    backup_managed_files
    if [[ "${mode}" == "replace" ]]; then
        RULES=("${IMPORTED_RULES[@]}")
    else
        RULES+=("${IMPORTED_RULES[@]}")
    fi
    apply_relay_mode_to_rules
    save_settings || return
    save_rules || return
    write_nft_conf || return
    apply_or_save_notice "规则导入完成。" "规则已导入托管配置。"
}

do_export_rules() {
    local path tmp rule
    print_title "导出规则"
    ensure_layout || return
    load_rules
    [[ ${#RULES[@]} -gt 0 ]] || {
        info "当前没有转发规则。"
        return
    }

    path="$(prompt_with_default "导出文件路径" "${EXPORT_DIR}/po0-relay-export-$(date '+%Y%m%d_%H%M%S').txt")"
    path="$(trim "${path}")"
    [[ -n "${path}" ]] || {
        err "导出路径不能为空。"
        return
    }
    if [[ -e "${path}" ]]; then
        confirm_yes "目标文件已存在，是否覆盖" || {
            info "已取消。"
            return
        }
    fi

    mkdir -p "$(dirname "${path}")" 2>/dev/null || true
    make_temp_file "${path}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    cat > "${tmp}" <<'EOF'
# nftables relay import/export file
# format: name|proto|listen_port|dest_ip|dest_port|enabled|snat_mode
# proto: both | tcp | udp
# enabled: 1=启用, 0=停用
# snat_mode: relay_lan | masquerade | none
EOF
    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        printf '%s|%s|%s|%s|%s|%s|%s\n' \
            "${RULE_NAME}" "${RULE_PROTO}" "${RULE_LPORT}" "${RULE_DIP}" "${RULE_DPORT}" "${RULE_ENABLED}" "${RULE_SNAT_MODE}" >> "${tmp}"
    done
    mv -f "${tmp}" "${path}"
    success "规则已导出到 ${path}"
}

do_diagnose() {
    print_title "诊断 / 自检"
    local nat_loaded="0"
    load_settings
    load_rules
    print_status_panel
    print_runtime_drift_hint
    print_runtime_rule_hint
    echo ""
    command -v nft &>/dev/null && info "nftables: $(nft --version 2>/dev/null)" || err "nftables: 未安装"
    [[ -f "${NFT_CONF}" ]] && nft -c -f "${NFT_CONF}" >/dev/null 2>&1 && info "relay 配置语法: 通过" || warn "relay 配置语法: 未通过或文件不存在"
    [[ -f "${MAIN_CONF}" ]] && nft -c -f "${MAIN_CONF}" >/dev/null 2>&1 && info "主配置语法: 通过" || warn "主配置语法: 未通过或文件不存在"
    if nft list table ip "${NAT_TABLE}" &>/dev/null; then
        nat_loaded="1"
        info "NAT 表已加载"
    else
        warn "NAT 表未加载"
    fi
    if [[ "${ENABLE_MSS_CLAMP}" == "1" ]]; then
        nft list table ip "${MANGLE_TABLE}" &>/dev/null && info "MSS 表已加载" || warn "MSS 表未加载"
    fi
    if [[ "${nat_loaded}" == "1" && ${#RULES[@]} -gt 0 ]]; then
        echo ""
        print_rule_counters
    fi
    warn_conflicts
    echo ""
    printf '托管文件:\n'
    printf '  - %s\n' "${MAIN_CONF}"
    printf '  - %s\n' "${NFT_CONF}"
    printf '  - %s\n' "${SETTINGS_FILE}"
    printf '  - %s\n' "${RULES_FILE}"
    printf '  - %s\n' "${SRC_ALLOWLIST_CACHE}"
    printf '  - %s\n' "${CUSTOM_SRC_ALLOWLIST_FILE}"
    printf '  - %s\n' "${ALLOWLIST_SETS_FILE}"
    printf '  - %s\n' "${ALLOWLIST_ENTRIES_FILE}"
    printf '  - %s\n' "${ALLOWLIST_SOURCES_FILE}"
    printf '  - %s\n' "${DDNS_REPORT_STATS_FILE}"
    printf '  - %s\n' "${BLOCK_LOG_FILE}"
    printf '  - %s\n' "${BLOCK_SUMMARY_FILE}"
    printf '  - %s\n' "${LEARN_LOG_FILE}"
    printf '  - %s\n' "${LEARN_SUMMARY_FILE}"
    printf '  - %s\n' "${LEARN_DAILY_IP_FILE}"
    printf '被阻挡访问日志: %s 条（统计 %s 行）\n' "$(block_log_count)" "$(block_summary_count)"
    printf '  - %s\n' "${LEARN_SERVICE_FILE}"
    printf '  - %s\n' "${IPDB_FILE}"
    printf '  - %s\n' "${IPLIST_DIR}"
    printf '  - %s\n' "${BACKUP_DIR}"
}

do_edit_settings() {
    print_title "修改中转机参数"
    command -v nft &>/dev/null || {
        err "请先执行【1】安装/初始化。"
        return
    }
    ensure_layout || return
    load_rules
    prompt_settings || return
    prompt_input_firewall_settings || return
    apply_relay_mode_to_rules
    backup_managed_files
    save_settings || return
    save_rules || return
    write_nft_conf || return
    apply_or_save_notice "中转机参数已更新。" "中转机参数已保存到托管配置。" || return
    print_settings
}

do_refresh_public_ip() {
    local ok=0
    print_title "手动刷新中转机 IP 缓存"
    ensure_layout || return
    load_settings 1
    if relay_mode_uses_lan; then
        if refresh_relay_lan_ip; then
            success "中转机内网 IP 已刷新：${RELAY_LAN_IP}"
            ok=1
        else
            warn "未能探测到中转机内网 IP。"
        fi
    fi

    if refresh_public_ip; then
        success "公网 IP 已刷新：${PUBLIC_IP}（$(public_ip_source_label)）"
        ok=1
    else
        warn "未能探测到公网 IP。"
        info "如果这是纯内网中转机，属于正常情况；也可以稍后网络稳定后再试。"
    fi
    save_settings || return
    [[ "${ok}" == "1" ]] || warn "没有刷新到可用 IP，已保留空缓存。"
    pause_before_return
}

select_iplist_region_interactive() {
    local keyword choice idx record id name rel url
    local -a matches=()
    SELECTED_REGION_ID=""
    ensure_iplist_ready || return 1
    read -r -p "请输入地区关键词或代码（例如 深圳 / 440300）: " keyword
    keyword="$(trim "${keyword}")"
    [[ -n "${keyword}" ]] || return 1
    mapfile -t matches < <(
        awk -F '\t' -v q="${keyword}" '
            index($1, q) || index($2, q) { print }
        ' "${IPLIST_MANIFEST}" | head -n 30
    )
    [[ ${#matches[@]} -gt 0 ]] || {
        err "未找到匹配地区。"
        return 1
    }
    echo "匹配地区："
    idx=1
    for record in "${matches[@]}"; do
        IFS=$'\t' read -r id name rel url <<< "${record}"
        printf '  %2d) %s (%s)\n' "${idx}" "${name}" "${id}"
        ((idx++))
    done
    read -r -p "请选择地区序号 [1-${#matches[@]}]: " choice
    [[ "${choice}" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= ${#matches[@]} )) || return 1
    IFS=$'\t' read -r id name rel url <<< "${matches[$((choice - 1))]}"
    SELECTED_REGION_ID="${id}"
}

select_selected_allowlist_region() {
    local choice idx id
    local -a ids=()
    SELECTED_REGION_ID=""
    for id in ${SRC_ALLOWLIST_REGION_IDS}; do
        ids+=("${id}")
    done
    [[ ${#ids[@]} -gt 0 ]] || {
        err "当前没有已选择地区。"
        return 1
    }
    idx=1
    for id in "${ids[@]}"; do
        printf '  %2d) %s\n' "${idx}" "$(iplist_region_label "${id}")"
        ((idx++))
    done
    read -r -p "请选择要删除的地区序号 [1-${#ids[@]}]: " choice
    [[ "${choice}" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= ${#ids[@]} )) || return 1
    SELECTED_REGION_ID="${ids[$((choice - 1))]}"
}

prompt_src_allowlist_mode() {
    local choice
    while true; do
        echo "选择源 IP 限制方式："
        echo "  0) 关闭：不限制访问转发端口的来源 IP"
        echo "  1) 仅手动来源：手动 CIDR（SSH 临时需在菜单中手动开启）"
        echo "  2) 可信动态来源：手动 + DDNS + Client IP + SSH report + WebAuth + learned（不默认含 SSH 临时）"
        echo "  3) 地区 + 可信动态来源"
        echo "  4) 仅地区库"
        echo "  5) 高级自选来源组合"
        read -r -p "请选择 [0-5，当前: $([[ "${ENABLE_SRC_ALLOWLIST}" == "1" ]] && src_allowlist_mode_to_label "${SRC_ALLOWLIST_MODE}" || printf '关闭')]: " choice
        case "${choice}" in
            0)
                ENABLE_SRC_ALLOWLIST="0"
                return 0
                ;;
            1)
                ENABLE_SRC_ALLOWLIST="1"
                SRC_ALLOWLIST_MODE="manual_only"
                return 0
                ;;
            2)
                ENABLE_SRC_ALLOWLIST="1"
                SRC_ALLOWLIST_MODE="trusted_dynamic"
                return 0
                ;;
            3)
                ENABLE_SRC_ALLOWLIST="1"
                SRC_ALLOWLIST_MODE="region_plus_trusted"
                return 0
                ;;
            4)
                ENABLE_SRC_ALLOWLIST="1"
                SRC_ALLOWLIST_MODE="region_only"
                return 0
                ;;
            5)
                ENABLE_SRC_ALLOWLIST="1"
                SRC_ALLOWLIST_MODE="custom_sources"
                configure_default_allowlist_sources_interactive || return 1
                return 0
                ;;
            "")
                return 0
                ;;
            *)
                err "无效选择。"
                ;;
        esac
    done
}

configure_default_allowlist_sources_interactive() {
    local raw normalized
    load_allowlist_sets
    raw="$(src_allowlist_mode_default_sources custom_sources)"
    echo ""
    echo "可选来源：region, manual, ssh_temp, ddns, client_ip, ssh_report, webauth, learned"
    raw="$(prompt_with_default "请输入允许的来源，逗号分隔" "${raw}")"
    normalized="$(normalize_allowlist_set_sources "${raw}")" || {
        err "来源组合无效。"
        return 1
    }
    set_default_allowlist_sources "${normalized}" || return 1
    success "高级来源组合已更新：${normalized}"
}

set_default_allowlist_sources() {
    local sources="$1"
    local set replaced=0
    local -a next=()
    sources="$(normalize_allowlist_set_sources "${sources}")" || return 1
    load_allowlist_sets
    for set in "${ALLOWLIST_SETS[@]}"; do
        parse_allowlist_set_line "${set}" || continue
        if [[ "${ALLOWLIST_SET_ID}" == "default" ]]; then
            next+=("$(serialize_allowlist_set \
                "${ALLOWLIST_SET_ID}" \
                "${ALLOWLIST_SET_LABEL}" \
                "${ALLOWLIST_SET_ENABLED}" \
                "${ALLOWLIST_SET_SCOPE}" \
                "${ALLOWLIST_SET_PORTS}" \
                "${sources}" \
                "${ALLOWLIST_SET_NOTE}")")
            replaced=1
        else
            next+=("${PARSED_ALLOWLIST_SET}")
        fi
    done
    if [[ "${replaced}" != "1" ]]; then
        next+=("$(serialize_allowlist_set "default" "Default public allowlist" "1" "public" "*" "${sources}" "Custom source-type allowlist")")
    fi
    ALLOWLIST_SETS=("${next[@]}")
    save_allowlist_sets
}

enable_allowlist_source_type_for_current_mode() {
    local source_type="$1"
    local sources source normalized
    source_type="$(normalize_allowlist_entry_source_type "${source_type}")" || return 1
    ENABLE_SRC_ALLOWLIST="1"
    sources="$(src_allowlist_mode_default_sources "${SRC_ALLOWLIST_MODE}")"
    for source in ${sources//,/ }; do
        if [[ "${source}" == "${source_type}" ]]; then
            return 0
        fi
    done
    normalized="$(normalize_allowlist_set_sources "${sources},${source_type}")" || return 1
    SRC_ALLOWLIST_MODE="custom_sources"
    set_default_allowlist_sources "${normalized}" || return 1
    info "已切换为高级自选来源，并启用 ${source_type}。"
}

do_manage_allowlist_source_switches() {
    save_allowlist_last_snapshot || return 1
    ENABLE_SRC_ALLOWLIST="1"
    SRC_ALLOWLIST_MODE="custom_sources"
    configure_default_allowlist_sources_interactive || return 1
    apply_src_allowlist_changes
}

select_custom_allowlist_entry() {
    local line choice idx=1
    local -a entries=()
    SELECTED_LEARN_CIDR=""
    [[ -f "${CUSTOM_SRC_ALLOWLIST_FILE}" ]] || {
        err "当前没有自定义 CIDR。"
        return 1
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_custom_allowlist_line "${line}" || continue
        entries+=("${CUSTOM_ALLOWLIST_CIDR}|${CUSTOM_ALLOWLIST_NOTE}")
    done < "${CUSTOM_SRC_ALLOWLIST_FILE}"
    [[ ${#entries[@]} -gt 0 ]] || {
        err "当前没有自定义 CIDR。"
        return 1
    }
    for line in "${entries[@]}"; do
        IFS='|' read -r CUSTOM_ALLOWLIST_CIDR CUSTOM_ALLOWLIST_NOTE <<< "${line}"
        if [[ -n "${CUSTOM_ALLOWLIST_NOTE}" ]]; then
            printf '  %2d) %-18s %s\n' "${idx}" "${CUSTOM_ALLOWLIST_CIDR}" "${CUSTOM_ALLOWLIST_NOTE}"
        else
            printf '  %2d) %s\n' "${idx}" "${CUSTOM_ALLOWLIST_CIDR}"
        fi
        ((idx++))
    done
    read -r -p "请选择要删除的自定义 CIDR [1-${#entries[@]}]: " choice
    [[ "${choice}" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= ${#entries[@]} )) || return 1
    IFS='|' read -r SELECTED_LEARN_CIDR SELECTED_LEARN_NOTE <<< "${entries[$((choice - 1))]}"
}

enable_allowlist_for_region_add() {
    ENABLE_SRC_ALLOWLIST="1"
    case "${SRC_ALLOWLIST_MODE}" in
        manual_only|trusted_dynamic)
            SRC_ALLOWLIST_MODE="region_plus_trusted"
            ;;
        region_only|region_plus_trusted|custom_sources)
            ;;
        *)
            SRC_ALLOWLIST_MODE="region_only"
            ;;
    esac
}

enable_allowlist_for_custom_add() {
    ENABLE_SRC_ALLOWLIST="1"
    case "${SRC_ALLOWLIST_MODE}" in
        region_only)
            SRC_ALLOWLIST_MODE="region_plus_trusted"
            ;;
        manual_only|trusted_dynamic|region_plus_trusted|custom_sources)
            ;;
        *)
            SRC_ALLOWLIST_MODE="trusted_dynamic"
            ;;
    esac
}

apply_src_allowlist_changes() {
    backup_managed_files
    write_nft_conf || return 1
    save_settings || return 1
    apply_or_save_notice "源 IP 白名单已更新。" "源 IP 白名单已保存到托管配置。" || return 1
}

do_refresh_ddns_allowlist_sources() {
    ensure_layout || return 1
    load_settings 1
    warn "DDNS 刷新只使用 LAN Worker/路由器已经上报且仍在 TTL 内的结果；PO0 不做本地 DNS 解析，也不延长原上报 TTL。"
    backup_managed_files
    refresh_ddns_allowlist_sources || return 1
    printf 'DDNS 来源刷新：外部上报续期 %s 个，失败/无新鲜上报 %s 个，停用 %s 个\n' \
        "${DDNS_REPORTED_COUNT:-0}" "${DDNS_FAILED_COUNT:-0}" "${DDNS_DISABLED_COUNT:-0}"
    if [[ "${DDNS_REFRESHED_COUNT:-0}" -gt 0 ]]; then
        enable_allowlist_for_custom_add
        apply_src_allowlist_changes || return 1
    elif [[ "${DDNS_DISABLED_COUNT:-0}" -gt 0 ]]; then
        disable_src_allowlist_if_no_custom_entries
        apply_src_allowlist_changes || return 1
    fi
    if [[ "${DDNS_FAILED_COUNT:-0}" -gt 0 ]]; then
        warn "DDNS 刷新失败；旧的 DDNS 白名单结果已保留，不会被清空。"
        return 1
    fi
    if [[ "${DDNS_REFRESHED_COUNT:-0}" -eq 0 && "${DDNS_DISABLED_COUNT:-0}" -eq 0 ]]; then
        success "没有启用的 DDNS 来源需要刷新。"
    fi
}

do_report_ddns_allowlist_source() {
    local key="${1:-}"
    local ips="${2:-}"
    local token="${3:-}"
    [[ -n "${key}" && -n "${ips}" ]] || {
        err "用法：--ddns-report <source-key> <公网IPv4[,公网IPv4...]> [token]"
        return 1
    }
    ensure_layout || return 1
    load_settings 1
    report_ddns_allowlist_source "${key}" "${ips}" "${token}" || return 1
    enable_allowlist_for_custom_add
    apply_src_allowlist_changes || return 1
    printf 'DDNS 上报已接收：%s (%s) -> %s\n' \
        "${DDNS_REPORT_NAME:-${key}}" "${DDNS_REPORT_DOMAIN:-${key}}" "${DDNS_REPORT_IPS:-${ips}}"
}

do_report_client_ip_source() {
    local source_id="${1:-}"
    local ip="${2:-}"
    local token="${3:-}"
    local identity="${4:-}"
    local ttl="${5:-3600}"
    [[ -n "${source_id}" && -n "${ip}" ]] || {
        err "用法：--client-ip-report <source-id> <ipv4> <token> [identity] [ttl]"
    }
    ensure_layout || return 1
    load_settings 1
    report_client_ip_source "${source_id}" "${ip}" "${token}" "${identity}" "${ttl}" || return 1
    enable_allowlist_for_custom_add
    apply_src_allowlist_changes || return 1
    if [[ "${DYNAMIC_REPORT_PENDING_COUNT:-0}" -gt 0 ]]; then
        printf '客户端 IP 已记录为待审核（attack mode）：%s -> %s\n' "${CLIENT_IP_REPORT_SOURCE:-${source_id}}" "${CLIENT_IP_REPORT_IP:-${ip}}"
    else
        printf '客户端 IP 上报已接收：%s -> %s，TTL %ss\n' "${CLIENT_IP_REPORT_SOURCE:-${source_id}}" "${CLIENT_IP_REPORT_IP:-${ip}}" "${CLIENT_IP_REPORT_TTL:-${ttl}}"
    fi
}

do_check_client_ip_report_source() {
    local source_id="${1:-}"
    local token="${2:-}"
    source_id="$(sanitize_allowlist_source_text "$(trim "${source_id}")")"
    [[ -n "${source_id}" ]] || {
        printf 'ERROR|缺少客户端来源 ID\n'
        return 1
    }
    validate_client_ip_report_token "${token}" || {
        printf 'ERROR|客户端 IP 上报 token 无效\n'
        return 1
    }
    printf 'OK|客户端 IP 来源可上报：%s\n' "${source_id}"
}

do_report_ssh_ip_source() {
    local source_id="${1:-}"
    local ip="${2:-}"
    local token="${3:-}"
    local identity="${4:-}"
    local ttl="${5:-3600}"
    [[ -n "${source_id}" && -n "${ip}" ]] || {
        err "用法：--ssh-ip-report <source-id> <ipv4> <token> [identity] [ttl]"
        return 1
    }
    ensure_layout || return 1
    load_settings 1
    report_ssh_ip_source "${source_id}" "${ip}" "${token}" "${identity}" "${ttl}" || return 1
    enable_allowlist_for_custom_add
    apply_src_allowlist_changes || return 1
    if [[ "${DYNAMIC_REPORT_PENDING_COUNT:-0}" -gt 0 ]]; then
        printf 'SSH report IP 已记录为待审核（attack mode）：%s -> %s\n' "${SSH_REPORT_SOURCE:-${source_id}}" "${SSH_REPORT_IP:-${ip}}"
    else
        printf 'SSH report 已接收：%s -> %s，TTL %ss\n' "${SSH_REPORT_SOURCE:-${source_id}}" "${SSH_REPORT_IP:-${ip}}" "${SSH_REPORT_TTL:-${ttl}}"
    fi
}

do_check_ssh_ip_report_source() {
    local source_id="${1:-}"
    local token="${2:-}"
    source_id="$(sanitize_allowlist_source_text "$(trim "${source_id}")")"
    [[ -n "${source_id}" ]] || {
        printf 'ERROR|missing ssh report source id\n'
        return 1
    }
    validate_ssh_report_token "${token}" || {
        printf 'ERROR|invalid ssh report token\n'
        return 1
    }
    printf 'OK|ssh report source can report: %s\n' "${source_id}"
}

do_report_webauth_source() {
    local source_id="${1:-}"
    local ip="${2:-}"
    local identity="${3:-}"
    local expires_at="${4:-}"
    local token="${5:-}"
    local note="${6:-}"
    [[ -n "${source_id}" && -n "${ip}" && -n "${identity}" && -n "${expires_at}" ]] || {
        err "用法：--webauth-report <source-id> <ipv4> <identity> <expires-at> <token> [note]"
        return 1
    }
    ensure_layout || return 1
    load_settings 1
    report_webauth_source "${source_id}" "${ip}" "${identity}" "${expires_at}" "${token}" "${note}" || return 1
    enable_allowlist_for_custom_add
    apply_src_allowlist_changes || return 1
    if [[ "${DYNAMIC_REPORT_PENDING_COUNT:-0}" -gt 0 ]]; then
        printf 'WebAuth IP 已记录为待审核（attack mode）：%s -> %s identity=%s\n' "${WEBAUTH_REPORT_SOURCE:-${source_id}}" "${WEBAUTH_REPORT_IP:-${ip}}" "${WEBAUTH_REPORT_IDENTITY:-${identity}}"
    else
        printf 'WebAuth 上报已接收：%s -> %s identity=%s expires=%s\n' "${WEBAUTH_REPORT_SOURCE:-${source_id}}" "${WEBAUTH_REPORT_IP:-${ip}}" "${WEBAUTH_REPORT_IDENTITY:-${identity}}" "${WEBAUTH_REPORT_EXPIRES_AT:-${expires_at}}"
    fi
}

do_check_webauth_report_source() {
    local source_id="${1:-}"
    local token="${2:-}"
    source_id="$(sanitize_allowlist_source_text "$(trim "${source_id}")")"
    [[ -n "${source_id}" ]] || {
        printf 'ERROR|缺少 WebAuth 来源 ID\n'
        return 1
    }
    validate_webauth_report_token "${token}" || {
        printf 'ERROR|WebAuth 上报 token 无效\n'
        return 1
    }
    printf 'OK|WebAuth 来源可上报：%s\n' "${source_id}"
}

do_show_client_ip_report_token() {
    local token
    ensure_layout || return 1
    token="$(client_ip_report_token_value)" || return 1
    print_title "Client IP / 自上报 Token"
    printf 'Token 文件 : %s\n' "${CLIENT_IP_REPORT_TOKEN_FILE}"
    printf 'Token      : %s\n' "${token}"
    echo ""
    echo "PO0 接收命令（SSH only；通常由 LAN Worker 自动执行）："
    printf '  bash %s --client-ip-report self-report 1.2.3.4 %s lan-worker 3600\n' "$(basename "$0")" "${token}"
    echo ""
    echo "LAN Worker self-report server（HTTP 只跑在 LAN Worker，不跑在 PO0）："
    printf '  po0-lan-client --self-report-server --self-report-listen 127.0.0.1:8788 --po0-host <PO0_HOST> --po0-script %s --self-report-source self-report --client-ip-token %s --self-report-secret <SELF_REPORT_SECRET>\n' \
        "$(shell_quote "${MANAGER_INSTALL_PATH}")" "$(shell_quote "${token}")"
    echo ""
    echo "Linux / OpenWrt 自上报 client（访问设备 -> LAN Worker）："
    printf '  curl -fsSL %s | bash -s -- --worker-url <LAN_WORKER_REPORT_URL> --source-id <CLIENT_ID> --secret <SELF_REPORT_SECRET> --install-cron 5\n' \
        "${OUTBOUND_IP_REPORTER_RAW_URL}"
    echo ""
    echo "Windows PowerShell 自上报 client（访问设备 -> LAN Worker）："
    printf "  \$env:PO0_LAN_WORKER_URL='<LAN_WORKER_REPORT_URL>'; \$env:PO0_SELF_REPORT_SOURCE='<CLIENT_ID>'; \$env:PO0_SELF_REPORT_SECRET='<SELF_REPORT_SECRET>'; \$env:INSTALL_TASK='1'; \$env:MINUTES='5'; irm -UseBasicParsing '%s' | iex\n" \
        "${OUTBOUND_IP_REPORTER_PS_RAW_URL}"
}

normalize_report_key_scope() {
    case "$(trim "${1:-}")" in
        egern|ssh_report|ssh-report) printf 'egern\n' ;;
        worker|lan|lan-worker) printf 'worker\n' ;;
        all|both|"") printf 'all\n' ;;
        *) printf 'all\n' ;;
    esac
}

report_key_scope_allows() {
    case "$(normalize_report_key_scope "${1:-}")" in
        egern) printf '%s\n' '--ssh-ip-report --ssh-ip-report-check' ;;
        worker) printf '%s\n' '--ddns-report --ddns-report-check --client-ip-report --client-ip-report-check --webauth-report --webauth-report-check' ;;
        *) printf '%s\n' '--ssh-ip-report --ssh-ip-report-check --ddns-report --ddns-report-check --client-ip-report --client-ip-report-check --webauth-report --webauth-report-check' ;;
    esac
}

report_key_user_home() {
    local user="${1:-root}"
    if command -v getent >/dev/null 2>&1; then
        getent passwd "${user}" | awk -F: '{print $6; exit}'
        return
    fi
    awk -F: -v user="${user}" '$1 == user {print $6; exit}' /etc/passwd
}

report_key_auth_file() {
    local user="${1:-root}" home
    home="$(report_key_user_home "${user}")"
    [[ -n "${home}" ]] || return 1
    printf '%s/.ssh/authorized_keys\n' "${home}"
}

report_key_public_part() {
    local line="$1" token key_type=""
    for token in ${line}; do
        case "${token}" in
            ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521)
                key_type="${token}"
                continue
                ;;
        esac
        if [[ -n "${key_type}" ]]; then
            printf '%s %s\n' "${key_type}" "${token}"
            return 0
        fi
    done
    return 1
}

report_key_fingerprint() {
    local public_part="$1" tmp fp
    if ! command -v ssh-keygen >/dev/null 2>&1; then
        printf 'ssh-keygen unavailable\n'
        return 0
    fi
    make_temp_file "${CONF_DIR}/po0-report-key.pub" || return 1
    tmp="${TEMP_FILE_RESULT}"
    printf '%s\n' "${public_part}" > "${tmp}"
    fp="$(ssh-keygen -lf "${tmp}" 2>/dev/null || true)"
    printf '%s\n' "${fp:-unparseable}"
}

ensure_report_key_wrapper() {
    mkdir -p "$(dirname "${REPORT_KEY_WRAPPER_PATH}")" || return 1
    cat > "${REPORT_KEY_WRAPPER_PATH}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
scope="${1:-all}"
manager="${2:-/root/nftables-relay-manager.sh}"
orig="${SSH_ORIGINAL_COMMAND:-}"

deny() { printf 'PO0 restricted report key denied: %s\n' "$*" >&2; exit 126; }

is_public_ipv4() {
    [[ "${1:-}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    local IFS=. o o1 o2 o3 o4
    read -r o1 o2 o3 o4 <<< "$1"
    for o in "$o1" "$o2" "$o3" "$o4"; do
        [[ "$o" =~ ^[0-9]+$ ]] || return 1
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

allow_action() {
    local action="$1"
    case "${scope}" in
        egern) [[ "${action}" == "--ssh-ip-report" || "${action}" == "--ssh-ip-report-check" ]] ;;
        worker)
            case "${action}" in
                --ddns-report|--ddns-report-check|--client-ip-report|--client-ip-report-check|--webauth-report|--webauth-report-check) return 0 ;;
                *) return 1 ;;
            esac
            ;;
        all)
            case "${action}" in
                --ssh-ip-report|--ssh-ip-report-check|--ddns-report|--ddns-report-check|--client-ip-report|--client-ip-report-check|--webauth-report|--webauth-report-check) return 0 ;;
                *) return 1 ;;
            esac
            ;;
        *) return 1 ;;
    esac
}

[[ -n "${orig}" ]] || deny "empty command"
clean="${orig//\'/}"
clean="${clean//\"/}"
read -r first second third rest <<< "${clean}"
if [[ "${first}" == "bash" || "${first}" == "/bin/bash" || "${first}" == "/usr/bin/bash" ]]; then
    [[ "${second}" == "${manager}" ]] || deny "unexpected manager path"
    action="${third}"
    read -r -a args <<< "${rest:-}"
elif [[ "${first}" == "${manager}" ]]; then
    action="${second}"
    read -r -a args <<< "${third:-} ${rest:-}"
else
    deny "unexpected command"
fi
allow_action "${action}" || deny "action ${action} not allowed for scope ${scope}"
case "${action}" in
    --ssh-ip-report|--client-ip-report)
        [[ "${#args[@]}" -ge 3 ]] || deny "${action} needs source ip token"
        is_public_ipv4 "${args[1]}" || deny "invalid public IPv4"
        [[ "${#args[@]}" -lt 5 || "${args[4]}" =~ ^[0-9]+$ ]] || deny "invalid ttl"
        ;;
    --ddns-report) [[ "${#args[@]}" -ge 2 ]] || deny "${action} needs source ips" ;;
    --webauth-report)
        [[ "${#args[@]}" -ge 5 ]] || deny "${action} needs source ip identity expires token"
        is_public_ipv4 "${args[1]}" || deny "invalid public IPv4"
        ;;
    --ssh-ip-report-check|--client-ip-report-check|--ddns-report-check|--webauth-report-check)
        [[ "${#args[@]}" -ge 1 ]] || deny "${action} needs source"
        ;;
esac
exec bash "${manager}" "${action}" "${args[@]}"
EOF
    chmod 700 "${REPORT_KEY_WRAPPER_PATH}" || return 1
}

report_key_restricted_options() {
    local scope
    scope="$(normalize_report_key_scope "${1:-all}")"
    printf 'restrict,no-pty,no-agent-forwarding,no-X11-forwarding,no-port-forwarding,command="%s %s %s"' \
        "${REPORT_KEY_WRAPPER_PATH}" "${scope}" "${MANAGER_INSTALL_PATH}"
}

show_report_keys_for_user() {
    local user="${1:-root}" auth line idx=1 public_part fp scope category
    auth="$(report_key_auth_file "${user}")" || { err "无法确定 ${user} 的 authorized_keys 路径。"; return 1; }
    printf '用户: %s\n' "${user}"
    printf 'authorized_keys: %s\n' "${auth}"
    [[ -f "${auth}" ]] || { printf '  (文件不存在)\n'; return 0; }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="$(trim "${line}")"
        [[ -n "${line}" && ! "${line}" =~ ^# ]] || continue
        public_part="$(report_key_public_part "${line}" || true)"
        [[ -n "${public_part}" ]] || continue
        fp="$(report_key_fingerprint "${public_part}")"
        if [[ "${line}" == *"po0-report:scope="* ]]; then
            scope="${line#*po0-report:scope=}"
            scope="${scope%%,*}"
            category="PO0 受限上报 key"
        elif [[ "${line}" == *"command="* || "${line}" == restrict,* ]]; then
            scope="-"; category="其它 forced-command/restricted key"
        else
            scope="-"; category="普通登录 key"
        fi
        printf '  %2d) %s\n' "${idx}" "${category}"
        printf '      fingerprint: %s\n' "${fp}"
        printf '      scope      : %s\n' "${scope}"
        [[ "${category}" == "PO0 受限上报 key" ]] && printf '      allowed    : %s\n      wrapper    : %s\n' "$(report_key_scope_allows "${scope}")" "${REPORT_KEY_WRAPPER_PATH}"
        ((idx++))
    done < "${auth}"
}

install_report_public_key() {
    local user="$1" scope="$2" pubkey="$3" auth ssh_dir group public_part blob existing line options comment tmp converted=0
    scope="$(normalize_report_key_scope "${scope}")"
    auth="$(report_key_auth_file "${user}")" || return 1
    ssh_dir="$(dirname "${auth}")"
    public_part="$(report_key_public_part "${pubkey}")" || { err "请输入 OpenSSH public key，不要粘贴私钥。"; return 1; }
    blob="${public_part#* }"
    ensure_report_key_wrapper || return 1
    mkdir -p "${ssh_dir}" || return 1
    chmod 700 "${ssh_dir}" 2>/dev/null || true
    touch "${auth}" || return 1
    chmod 600 "${auth}" 2>/dev/null || true
    group="$(id -gn "${user}" 2>/dev/null || printf '%s' "${user}")"
    chown "${user}:${group}" "${ssh_dir}" "${auth}" 2>/dev/null || true
    options="$(report_key_restricted_options "${scope}")"
    comment="po0-report:scope=${scope},script=${MANAGER_INSTALL_PATH},created=$(utc_now_iso)"
    line="${options} ${public_part} ${comment}"
    if grep -Fq "${blob}" "${auth}" 2>/dev/null; then
        printf '检测到相同公钥已存在，将把匹配行转换/更新为 PO0 受限上报 key。\n'
        make_temp_file "${auth}" || return 1
        tmp="${TEMP_FILE_RESULT}"
        while IFS= read -r existing || [[ -n "${existing}" ]]; do
            if [[ "${existing}" == *"${blob}"* && "${converted}" == "0" ]]; then
                printf '%s\n' "${line}" >> "${tmp}"
                converted=1
            else
                printf '%s\n' "${existing}" >> "${tmp}"
            fi
        done < "${auth}"
        mv -f "${tmp}" "${auth}"
    else
        printf '%s\n' "${line}" >> "${auth}"
    fi
    chmod 600 "${auth}" 2>/dev/null || true
    printf '已安装 PO0 受限上报 key：user=%s scope=%s\n' "${user}" "${scope}"
}

do_manage_report_keys() {
    local choice user scope pubkey
    ensure_layout || return
    while true; do
        print_title "专用受限上报 key"
        echo "  1) 显示已有 key 分类"
        echo "  2) 新增 / 转换 public key 为受限上报 key"
        echo "  0) 返回"
        read -r -p "请选择操作 [0-2]: " choice
        case "${choice}" in
            1) user="$(prompt_with_default "系统用户" "root")"; show_report_keys_for_user "${user}"; pause_before_return ;;
            2)
                user="$(prompt_with_default "系统用户" "root")"
                scope="$(prompt_with_default "scope: egern / worker / all" "egern")"
                echo "请粘贴 public key（.pub 内容），不要粘贴私钥："
                read -r pubkey
                install_report_public_key "${user}" "${scope}" "${pubkey}"
                pause_before_return
                ;;
            0) return ;;
            *) err "无效选择。" ;;
        esac
    done
}

do_show_report_keys_cli() {
    ensure_layout || return 1
    show_report_keys_for_user "${1:-root}"
}

do_install_report_key_cli() {
    local scope="${1:-}" pubkey="${2:-}" user="${3:-root}"
    [[ -n "${scope}" && -n "${pubkey}" ]] || { err "用法：--install-report-key <egern|worker|all> '<public-key-line>' [user]"; return 1; }
    ensure_layout || return 1
    install_report_public_key "${user}" "${scope}" "${pubkey}"
}

do_show_ssh_report_token() {
    local token
    ensure_layout || return 1
    token="$(ssh_report_token_value)" || return 1
    print_title "Egern / SSH report Token"
    printf 'Token file : %s\n' "${SSH_REPORT_TOKEN_FILE}"
    printf 'Token      : %s\n' "${token}"
    echo ""
    echo "PO0 SSH-only report command:"
    printf '  bash %s --ssh-ip-report iphone 1.2.3.4 %s egern 3600\n' "$(basename "$0")" "${token}"
    echo ""
    echo "Egern module:"
    printf '  Module URL: %s\n' "${EGERN_SSH_REPORT_MODULE_RAW_URL}"
    printf '  SSH_REPORT_TOKEN=%s\n' "${token}"
    printf '  PO0_SCRIPT=%s\n' "${MANAGER_INSTALL_PATH}"
    echo ""
    echo "Multiple PO0: import one Egern module and merge all target rows into SSH_REPORT_TARGETS."
    printf '  SSH_REPORT_TARGETS row: source_id|host|port|user|script|token|identity|ttl\n'
    printf '    egern-po0|<PO0_HOST>|22|root|%s|%s|egern|3600\n' "${MANAGER_INSTALL_PATH}" "${token}"
}

do_show_webauth_report_token() {
    local token
    ensure_layout || return 1
    token="$(webauth_report_token_value)" || return 1
    print_title "LAN Worker WebAuth 上报 Token"
    printf 'Token 文件 : %s\n' "${WEBAUTH_REPORT_TOKEN_FILE}"
    printf 'Token      : %s\n' "${token}"
    echo ""
    echo "WebAuth 上报示例（由 LAN Worker 通过 SSH 调用）："
    printf '  bash %s --webauth-report cf-access 1.2.3.4 user@example.com %s %s\n' \
        "$(basename "$0")" "$(utc_after_seconds_iso 3600)" "${token}"
}

set_automation_mode() {
    local mode="${1:-}"
    case "${mode}" in
        regular|normal|off)
            AUTOMATION_MODE="regular"
            ;;
        attack|on|freeze)
            AUTOMATION_MODE="attack"
            ;;
        *)
            err "自动白名单安全模式无效：${mode:-空}。可用值：regular、attack。"
            return 1
            ;;
    esac
    ensure_layout || return 1
    load_settings 1
    case "${mode}" in
        regular|normal|off) AUTOMATION_MODE="regular" ;;
        attack|on|freeze) AUTOMATION_MODE="attack" ;;
    esac
    save_settings || return 1
    success "自动白名单安全模式已切换为：${AUTOMATION_MODE}"
}

do_list_pending_auto_sources() {
    ensure_layout || return 1
    print_title "自动来源待审核 IP"
    if [[ ! -s "${AUTO_PENDING_FILE}" ]]; then
        echo "  (暂无待审核自动来源 IP)"
        return 0
    fi
    list_pending_auto_sources
}

do_compat_check() {
    print_title "兼容性检查"
    load_settings 1
    load_rules 1
    load_allowlist_sets 1
    printf '设置文件     : %s\n' "$([[ -f "${SETTINGS_FILE}" ]] && printf 'OK' || printf 'missing')"
    printf '规则文件     : %s 条\n' "${#RULES[@]}"
    printf '白名单模式   : %s (%s)\n' "${SRC_ALLOWLIST_MODE}" "$(src_allowlist_mode_to_label "${SRC_ALLOWLIST_MODE}")"
    printf '允许来源     : %s\n' "$(src_allowlist_mode_default_sources "${SRC_ALLOWLIST_MODE}")"
    printf '旧 custom 文件: %s 条\n' "$(custom_allowlist_count)"
    printf 'entries      : %s 条\n' "$(allowlist_entries_count)"
    printf 'DDNS sources : %s 个\n' "$(allowlist_sources_count)"
    printf '自动白名单安全模式 : %s\n' "${AUTOMATION_MODE}"
    success "兼容性检查完成；未修改任何文件。"
}

do_cleanup_legacy() {
    local mode="${1:---dry-run}"
    local ts
    print_title "清理旧文件"
    case "${mode}" in
        --dry-run|"")
            echo "dry-run：只列出候选，不删除文件。"
            ;;
        --apply)
            ts="$(date '+%Y%m%d_%H%M%S')"
            mkdir -p "${BACKUP_DIR}/legacy-cleanup-${ts}" || return 1
            echo "apply：本版本只执行安全备份和说明，不删除 live state。"
            ;;
        *)
            err "用法：--cleanup-legacy --dry-run|--apply"
            return 1
            ;;
    esac
    echo "保留 live state：规则、白名单、token、DDNS sources、资源任务、日志。"
    echo "可人工检查的旧路径候选："
    printf '  - %s\n' "/usr/local/sbin/nftables-relay-manager"
    printf '  - %s\n' "${CUSTOM_SRC_ALLOWLIST_FILE}（旧 custom 兼容文件，仍参与迁移，不建议删除）"
    success "清理检查完成。"
}

do_check_ddns_report_source() {
    local key="${1:-}"
    local token="${2:-}"
    local line found=0 disabled=0
    key="$(sanitize_allowlist_source_text "$(trim "${key}")")"
    [[ -n "${key}" ]] || {
        printf 'ERROR|缺少 DDNS 来源名称或域名\n'
        return 1
    }
    validate_ddns_report_token_readonly "${token}" || {
        printf 'ERROR|DDNS 外部上报 token 无效\n'
        return 1
    }
    [[ -f "${ALLOWLIST_SOURCES_FILE}" ]] || {
        printf 'ERROR|尚未配置 DDNS 来源\n'
        return 1
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_source_line "${line}" || continue
        [[ "${ALLOWLIST_SOURCE_TYPE}" == "ddns" ]] || continue
        if [[ "${ALLOWLIST_SOURCE_NAME}" == "${key}" || "${ALLOWLIST_SOURCE_VALUE}" == "${key}" ]]; then
            found=1
            if [[ "${ALLOWLIST_SOURCE_ENABLED}" != "1" ]]; then
                disabled=1
            fi
            break
        fi
    done < "${ALLOWLIST_SOURCES_FILE}"
    [[ "${found}" == "1" ]] || {
        printf 'ERROR|未找到 DDNS 来源：%s\n' "${key}"
        return 1
    }
    [[ "${disabled}" != "1" ]] || {
        printf 'ERROR|DDNS 来源已停用：%s\n' "${key}"
        return 1
    }
    printf 'OK|DDNS 来源可上报：%s -> %s\n' "${ALLOWLIST_SOURCE_NAME}" "${ALLOWLIST_SOURCE_VALUE}"
}

print_lan_worker_ddns_bootstrap_example() {
    local ddns_token="${1:-<SOURCE_TOKEN>}"
    echo "LAN Worker DDNS 解析部署示例："
    printf '  curl -fsSL %s | bash -s -- --bootstrap --po0-host <PO0_HOST> --po0-script %s --source-key <DDNS_SOURCE_KEY> --ddns-domain <DDNS_DOMAIN> --token %s --install-cron 5\n' \
        "${LAN_WORKER_RAW_URL}" "$(shell_quote "${MANAGER_INSTALL_PATH}")" "${ddns_token}"
}

print_lan_worker_resource_bootstrap_example() {
    local resource_token="${1:-<RESOURCE_TOKEN>}"
    echo "LAN Worker 资源任务部署示例："
    printf '  curl -fsSL %s | bash -s -- --bootstrap --po0-host <PO0_HOST> --po0-script %s --resource-token %s --install-cron 5\n' \
        "${LAN_WORKER_RAW_URL}" "$(shell_quote "${MANAGER_INSTALL_PATH}")" "${resource_token}"
    echo "只探测资源任务 token，不写配置、不安装 cron："
    printf '  curl -fsSL %s | bash -s -- --probe --po0-host <PO0_HOST> --po0-script %s --resource-token %s\n' \
        "${LAN_WORKER_RAW_URL}" "$(shell_quote "${MANAGER_INSTALL_PATH}")" "${resource_token}"
}

deploy_token_values() {
    DEPLOY_DDNS_TOKEN="$(ddns_report_token_value 2>/dev/null || printf '<DDNS_TOKEN>')"
    DEPLOY_RESOURCE_TOKEN="$(resource_task_token_value 2>/dev/null || printf '<RESOURCE_TOKEN>')"
    DEPLOY_CLIENT_TOKEN="$(client_ip_report_token_value 2>/dev/null || printf '<CLIENT_REPORT_TOKEN>')"
    DEPLOY_SSH_TOKEN="$(ssh_report_token_value 2>/dev/null || printf '<SSH_REPORT_TOKEN>')"
    DEPLOY_WEBAUTH_TOKEN="$(webauth_report_token_value 2>/dev/null || printf '<WEBAUTH_TOKEN>')"
}

deploy_ensure_resource_token() {
    DEPLOY_RESOURCE_TOKEN="$(resource_task_token_value 2>/dev/null || generate_resource_task_token 2>/dev/null || printf '<RESOURCE_TOKEN>')"
}

do_show_client_deploy_index() {
    ensure_layout || return 1
    print_title "LAN Worker / 客户端 / Egern 分场景部署"
    printf 'PO0 主控路径 : %s\n' "${MANAGER_INSTALL_PATH}"
    printf 'LAN Worker RAW   : %s\n' "${LAN_WORKER_RAW_URL}"
    printf '自上报 Client RAW: %s\n' "${OUTBOUND_IP_REPORTER_RAW_URL}"
    echo ""
    echo "进入具体菜单后，只显示对应场景的命令："
    echo "  1) PO0 主控脚本上传命令"
    echo "  2) LAN Worker 专用 token"
    echo "  3) LAN Worker 资源任务 Worker"
    echo "  4) LAN Worker DDNS 解析 Worker"
    echo "  5) LAN Worker self-report server"
    echo "  6) Self-report client"
    echo "  7) LAN Worker WebAuth worker"
    echo "  8) Egern SSH report"
    echo "  9) 专用受限 SSH 上报 key"
    echo ""
    echo "CLI 示例："
    echo "  bash nftables-relay-manager.sh --show-client-deploy-commands tokens"
    echo "  bash nftables-relay-manager.sh --show-client-deploy-commands lan-ddns"
    echo "  bash nftables-relay-manager.sh --show-client-deploy-commands egern"
}

do_show_po0_manager_deploy_commands() {
    ensure_layout || return 1
    print_title "PO0 主控脚本上传"
    printf '安装路径 : %s\n' "${MANAGER_INSTALL_PATH}"
    echo ""
    echo "在本地机器执行上传，然后登录 PO0 启动主控脚本："
    printf '  scp scripts/po0/nftables/nftables-relay-manager.sh root@<PO0_HOST>:%s\n' "${MANAGER_INSTALL_PATH}"
    printf '  ssh root@<PO0_HOST> "chmod +x %s && bash %s"\n' "${MANAGER_INSTALL_PATH}" "${MANAGER_INSTALL_PATH}"
}

do_show_lan_worker_tokens() {
    ensure_layout || return 1
    deploy_token_values
    deploy_ensure_resource_token
    print_title "LAN Worker 专用 token"
    printf 'DDNS_TOKEN        : %s\n' "${DEPLOY_DDNS_TOKEN}"
    printf 'RESOURCE_TOKEN    : %s\n' "${DEPLOY_RESOURCE_TOKEN}"
    printf 'CLIENT_IP_TOKEN   : %s\n' "${DEPLOY_CLIENT_TOKEN}"
    printf 'WEBAUTH_TOKEN     : %s\n' "${DEPLOY_WEBAUTH_TOKEN}"
    printf 'SSH_REPORT_TOKEN  : %s\n' "${DEPLOY_SSH_TOKEN}"
    printf 'PO0_SCRIPT        : %s\n' "${MANAGER_INSTALL_PATH}"
    echo ""
    echo "可直接复制的 LAN Worker token bundle："
    printf 'DDNS_TOKEN=%s\n' "${DEPLOY_DDNS_TOKEN}"
    printf 'RESOURCE_TOKEN=%s\n' "${DEPLOY_RESOURCE_TOKEN}"
    printf 'CLIENT_IP_TOKEN=%s\n' "${DEPLOY_CLIENT_TOKEN}"
    printf 'WEBAUTH_TOKEN=%s\n' "${DEPLOY_WEBAUTH_TOKEN}"
    printf 'PO0_SCRIPT=%s\n' "${MANAGER_INSTALL_PATH}"
    echo ""
    printf 'Token 文件：\n'
    printf '  DDNS       : %s\n' "${DDNS_REPORT_TOKEN_FILE}"
    printf '  Resource   : %s\n' "${RESOURCE_TASK_TOKEN_FILE}"
    printf '  Client IP  : %s\n' "${CLIENT_IP_REPORT_TOKEN_FILE}"
    printf '  WebAuth    : %s\n' "${WEBAUTH_REPORT_TOKEN_FILE}"
    printf '  SSH report : %s\n' "${SSH_REPORT_TOKEN_FILE}"
}

do_show_lan_resource_worker_commands() {
    ensure_layout || return 1
    deploy_token_values
    deploy_ensure_resource_token
    print_title "LAN Worker 资源任务 Worker"
    echo "在 LAN Worker 机器上执行；只负责轮询和上传 iplist/ipdb 资源任务。"
    echo ""
    printf '  curl -fsSL %s | bash -s -- --bootstrap --po0-host <PO0_HOST> --po0-script %s --resource-token %s --install-cron 5\n' \
        "${LAN_WORKER_RAW_URL}" "$(shell_quote "${MANAGER_INSTALL_PATH}")" "$(shell_quote "${DEPLOY_RESOURCE_TOKEN}")"
    echo ""
    echo "只探测，不写配置、不安装 cron："
    printf '  curl -fsSL %s | bash -s -- --probe --po0-host <PO0_HOST> --po0-script %s --resource-token %s\n' \
        "${LAN_WORKER_RAW_URL}" "$(shell_quote "${MANAGER_INSTALL_PATH}")" "$(shell_quote "${DEPLOY_RESOURCE_TOKEN}")"
}

do_show_lan_ddns_worker_commands() {
    ensure_layout || return 1
    deploy_token_values
    print_title "LAN Worker DDNS 解析"
    echo "在 LAN Worker 机器上执行；LAN Worker 解析 DDNS 后通过 SSH 上报 PO0。"
    echo ""
    printf '  curl -fsSL %s | bash -s -- --bootstrap --po0-host <PO0_HOST> --po0-script %s --source-key <DDNS_SOURCE_KEY> --ddns-domain <DDNS_DOMAIN> --token %s --install-cron 5\n' \
        "${LAN_WORKER_RAW_URL}" "$(shell_quote "${MANAGER_INSTALL_PATH}")" "$(shell_quote "${DEPLOY_DDNS_TOKEN}")"
    echo ""
    printf 'DDNS 目标行: source_key|ddns_domain|host|port|user|script|token|ssh_args\n'
    printf '  <DDNS_SOURCE_KEY>|<DDNS_DOMAIN>|<PO0_HOST>|22|root|%s|%s|\n' "${MANAGER_INSTALL_PATH}" "${DEPLOY_DDNS_TOKEN}"
    echo ""
    printf '临时合并多个目标：\n'
    printf '  po0-lan-client --run --ddns-targets "<TARGET1;TARGET2>"\n'
}

do_show_self_report_server_commands() {
    ensure_layout || return 1
    deploy_token_values
    print_title "LAN Worker self-report server"
    echo "HTTP 只监听在 LAN Worker；访问设备先报 LAN Worker，再由 LAN Worker 通过 SSH 上报 PO0。"
    echo ""
    printf '  curl -fsSL %s | bash -s -- --install-self\n' "${LAN_WORKER_RAW_URL}"
    printf '  po0-lan-client --self-report-server --self-report-listen 127.0.0.1:8788 --po0-host <PO0_HOST> --po0-script %s --self-report-source self-report --client-ip-token %s --self-report-secret <SELF_REPORT_SECRET>\n' \
        "$(shell_quote "${MANAGER_INSTALL_PATH}")" "$(shell_quote "${DEPLOY_CLIENT_TOKEN}")"
    echo ""
    printf 'Self-report PO0 目标行: source|host|port|user|script|token|ttl|ssh_args\n'
    printf '  self-report|<PO0_HOST>|22|root|%s|%s|3600|\n' "${MANAGER_INSTALL_PATH}" "${DEPLOY_CLIENT_TOKEN}"
    echo ""
    printf '合并多个目标行：\n'
    printf '  po0-lan-client --self-report-server --self-report-targets "<TARGET1;TARGET2>" --self-report-secret <SELF_REPORT_SECRET>\n'
}

do_show_self_report_client_commands() {
    ensure_layout || return 1
    print_title "Self-report client"
    echo "在访问设备上执行；检测设备当前出口 IPv4 后上报 LAN Worker，不直连 PO0。"
    echo ""
    echo "Linux / OpenWrt:"
    printf '  curl -fsSL %s | bash -s -- --worker-url <LAN_WORKER_REPORT_URL> --source-id <CLIENT_ID> --secret <SELF_REPORT_SECRET> --install-cron 5\n' \
        "${OUTBOUND_IP_REPORTER_RAW_URL}"
    echo ""
    echo "Windows PowerShell:"
    printf "  \$env:PO0_LAN_WORKER_URL='<LAN_WORKER_REPORT_URL>'; \$env:PO0_SELF_REPORT_SOURCE='<CLIENT_ID>'; \$env:PO0_SELF_REPORT_SECRET='<SELF_REPORT_SECRET>'; \$env:INSTALL_TASK='1'; \$env:MINUTES='5'; irm -UseBasicParsing '%s' | iex\n" \
        "${OUTBOUND_IP_REPORTER_PS_RAW_URL}"
}

do_show_webauth_worker_commands() {
    ensure_layout || return 1
    deploy_token_values
    print_title "LAN Worker WebAuth worker"
    echo "PO0 不开放 HTTP；建议在 LAN Worker 监听前面接 Cloudflare Access/Tunnel。"
    echo ""
    printf '  curl -fsSL %s | bash -s -- --install-self\n' "${LAN_WORKER_RAW_URL}"
    printf '  po0-lan-client --webauth-server --listen 127.0.0.1:8787 --po0-host <PO0_HOST> --po0-script %s --webauth-source cf-access --webauth-token %s\n' \
        "$(shell_quote "${MANAGER_INSTALL_PATH}")" "$(shell_quote "${DEPLOY_WEBAUTH_TOKEN}")"
    echo ""
    printf 'WebAuth PO0 目标行: source|host|port|user|script|token|ttl|ssh_args\n'
    printf '  cf-access|<PO0_HOST>|22|root|%s|%s|3600|\n' "${MANAGER_INSTALL_PATH}" "${DEPLOY_WEBAUTH_TOKEN}"
    echo ""
    printf '合并多个目标行：\n'
    printf '  po0-lan-client --webauth-server --webauth-targets "<TARGET1;TARGET2>" --listen 127.0.0.1:8787\n'
}

do_show_egern_deploy_commands() {
    ensure_layout || return 1
    deploy_token_values
    print_title "Egern SSH report"
    echo "Egern 通过 SSH 直接向 PO0 上报当前出口 IPv4，归类为 ssh_report。"
    echo ""
    printf 'Module URL        : %s\n' "${EGERN_SSH_REPORT_MODULE_RAW_URL}"
    printf 'SSH_REPORT_TOKEN  : %s\n' "${DEPLOY_SSH_TOKEN}"
    printf 'PO0_SCRIPT        : %s\n' "${MANAGER_INSTALL_PATH}"
    echo ""
    printf 'SSH_REPORT_TARGETS row: source_id|host|port|user|script|token|identity|ttl\n'
    printf '  egern-po0|<PO0_HOST>|22|root|%s|%s|egern|3600\n' "${MANAGER_INSTALL_PATH}" "${DEPLOY_SSH_TOKEN}"
}

do_show_restricted_report_key_commands() {
    ensure_layout || return 1
    print_title "专用受限 SSH 上报 key"
    echo "在白名单菜单里安装专用受限 public key："
    echo "  管理源 IP 白名单 -> 安装 / 显示专用受限上报 key"
    echo ""
    echo "推荐 scope："
    echo "  Egern      : egern"
    echo "  LAN Worker : worker"
    echo ""
    echo "CLI:"
    printf '  bash %s --install-report-key worker "<PUBLIC_KEY_LINE>" root\n' "$(basename "$0")"
    printf '  bash %s --install-report-key egern "<PUBLIC_KEY_LINE>" root\n' "$(basename "$0")"
}

do_show_client_deploy_topic() {
    case "${1:-index}" in
        index|menu|"") do_show_client_deploy_index ;;
        po0|manager) do_show_po0_manager_deploy_commands ;;
        token|tokens|bundle|worker-token|worker-tokens) do_show_lan_worker_tokens ;;
        lan-resource|resource|worker-resource) do_show_lan_resource_worker_commands ;;
        lan-ddns|ddns|worker-ddns) do_show_lan_ddns_worker_commands ;;
        self-server|self-report-server|self-report) do_show_self_report_server_commands ;;
        self-client|client) do_show_self_report_client_commands ;;
        webauth|webauth-worker) do_show_webauth_worker_commands ;;
        egern|ssh-report) do_show_egern_deploy_commands ;;
        key|keys|restricted-key) do_show_restricted_report_key_commands ;;
        all|legacy) do_show_client_deploy_index ;;
        *)
            err "未知部署主题：${1}"
            do_show_client_deploy_index
            return 1
            ;;
    esac
}

do_manage_client_deploy_commands() {
    local choice
    while true; do
        print_title "LAN Worker / 客户端 / Egern 分场景部署"
        echo "  1) PO0 主控脚本上传命令"
        echo "  2) LAN Worker 专用 token"
        echo "  3) LAN Worker 资源任务 Worker"
        echo "  4) LAN Worker DDNS 解析 Worker"
        echo "  5) LAN Worker self-report server"
        echo "  6) Self-report client"
        echo "  7) LAN Worker WebAuth worker"
        echo "  8) Egern SSH report"
        echo "  9) 专用受限 SSH 上报 key"
        echo " 10) 显示简短索引"
        echo "  0) 返回"
        read -r -p "请选择操作 [0-10]: " choice
        case "${choice}" in
            1) do_show_po0_manager_deploy_commands; pause_before_return ;;
            2) do_show_lan_worker_tokens; pause_before_return ;;
            3) do_show_lan_resource_worker_commands; pause_before_return ;;
            4) do_show_lan_ddns_worker_commands; pause_before_return ;;
            5) do_show_self_report_server_commands; pause_before_return ;;
            6) do_show_self_report_client_commands; pause_before_return ;;
            7) do_show_webauth_worker_commands; pause_before_return ;;
            8) do_show_egern_deploy_commands; pause_before_return ;;
            9) do_show_restricted_report_key_commands; pause_before_return ;;
            10) do_show_client_deploy_index; pause_before_return ;;
            0) return ;;
            *) err "无效选择。" ;;
        esac
    done
}

do_show_client_deploy_commands() {
    do_show_client_deploy_topic "${1:-index}"
    return $?
}


do_worker_token_bundle() {
    local ensure_resource="${1:-}"
    local ddns_token resource_token client_token ssh_token webauth_token
    ensure_layout || return 1
    ddns_token="$(ddns_report_token_value)" || return 1
    client_token="$(client_ip_report_token_value)" || return 1
    ssh_token="$(ssh_report_token_value)" || return 1
    webauth_token="$(webauth_report_token_value)" || return 1
    if [[ "${ensure_resource}" == "--ensure-resource-token" ]]; then
        resource_token="$(resource_task_token_value 2>/dev/null || generate_resource_task_token)" || return 1
    else
        resource_token="$(resource_task_token_value 2>/dev/null || true)"
    fi
    printf 'DDNS_TOKEN=%s\n' "${ddns_token}"
    printf 'RESOURCE_TOKEN=%s\n' "${resource_token}"
    printf 'CLIENT_IP_TOKEN=%s\n' "${client_token}"
    printf 'SSH_REPORT_TOKEN=%s\n' "${ssh_token}"
    printf 'WEBAUTH_TOKEN=%s\n' "${webauth_token}"
    printf 'PO0_SCRIPT=%s\n' "${MANAGER_INSTALL_PATH}"
}

do_manage_automation_mode() {
    local choice
    ensure_layout || return
    load_settings 1
    while true; do
        print_title "自动白名单安全模式"
        printf '当前模式 : %s\n' "${AUTOMATION_MODE}"
        echo "  1) regular：自动来源新 IP 可直接进入白名单"
        echo "  2) attack：新自动 IP 只进入待审核，不直接放行"
        echo "  3) 查看自动来源待审核 IP"
        echo "  0) 返回"
        read -r -p "请选择操作 [0-3]: " choice
        case "${choice}" in
            1) set_automation_mode regular; pause_before_return ;;
            2) set_automation_mode attack; pause_before_return ;;
            3) do_list_pending_auto_sources; pause_before_return ;;
            0) return ;;
            *) err "无效选择。" ;;
        esac
        load_settings 1
    done
}

do_show_ddns_report_token() {
    local token
    ensure_layout || return 1
    token="$(ddns_report_token_value)" || return 1
    print_title "DDNS 外部上报 Token"
    printf 'Token 文件 : %s\n' "${DDNS_REPORT_TOKEN_FILE}"
    printf 'Token      : %s\n' "${token}"
    echo ""
    echo "SSH 上报示例："
    printf '  bash %s --ddns-report home 1.2.3.4 %s\n' "$(basename "$0")" "${token}"
    echo ""
    print_lan_worker_ddns_bootstrap_example "${token}" "<RESOURCE_TOKEN>"
    echo ""
    echo "说明：如果通过 SSH 只允许可信用户执行，也可以不创建/不使用 token；一旦 token 文件存在，上报命令必须携带正确 token。"
}

show_ddns_allowlist_sources() {
    local line idx=1 status
    ensure_allowlist_sources_file || return 1
    if [[ "$(allowlist_sources_count)" == "0" ]]; then
        echo "  (尚未添加 DDNS 来源)"
        return 0
    fi
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_source_line "${line}" || continue
        if [[ "${ALLOWLIST_SOURCE_ENABLED}" == "1" ]]; then
            status="启用"
        else
            status="停用"
        fi
        printf '  %2d) %-4s %-16s 域名=%s TTL=%ss 上次=%s 结果=%s\n' \
            "${idx}" "${status}" "${ALLOWLIST_SOURCE_NAME}" "${ALLOWLIST_SOURCE_VALUE}" \
            "${ALLOWLIST_SOURCE_TTL_SECONDS}" "${ALLOWLIST_SOURCE_LAST_RESOLVED_AT:-从未}" \
            "${ALLOWLIST_SOURCE_LAST_RESULT:-无}"
        print_ddns_report_stats_line "${ALLOWLIST_SOURCE_VALUE}"
        ((idx++))
    done < "${ALLOWLIST_SOURCES_FILE}"
}

select_ddns_allowlist_source() {
    local line choice idx=1
    local -a sources=()
    ensure_allowlist_sources_file || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_source_line "${line}" || continue
        sources+=("${PARSED_ALLOWLIST_SOURCE}")
    done < "${ALLOWLIST_SOURCES_FILE}"
    [[ ${#sources[@]} -gt 0 ]] || {
        err "当前没有 DDNS 来源。"
        return 1
    }
    show_ddns_allowlist_sources
    read -r -p "请选择 DDNS 来源 [1-${#sources[@]}]: " choice
    [[ "${choice}" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= ${#sources[@]} )) || return 1
    parse_allowlist_source_line "${sources[$((choice - 1))]}"
}

append_ddns_allowlist_source() {
    local name="$1"
    local domain="$2"
    local ttl="$3"
    local enabled="$4"
    local line
    name="$(sanitize_allowlist_source_text "${name}")"
    domain="$(sanitize_allowlist_source_text "${domain}")"
    ttl="$(normalize_source_ttl_seconds "${ttl}")"
    [[ "${enabled}" == "0" || "${enabled}" == "1" ]] || enabled="1"
    [[ -n "${name}" ]] || name="${domain}"
    validate_ddns_domain "${domain}" || return 1
    ensure_allowlist_sources_file || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_source_line "${line}" || continue
        if [[ "${ALLOWLIST_SOURCE_SET_ID}" == "default" \
            && ("${ALLOWLIST_SOURCE_NAME}" == "${name}" || "${ALLOWLIST_SOURCE_VALUE}" == "${domain}") ]]; then
            err "DDNS 来源已存在：${name} / ${domain}"
            return 1
        fi
    done < "${ALLOWLIST_SOURCES_FILE}"
    serialize_allowlist_source "default" "ddns" "${name}" "${domain}" "${enabled}" "${ttl}" "" "" >> "${ALLOWLIST_SOURCES_FILE}"
}

rewrite_selected_ddns_source() {
    local old_set="$1"
    local old_name="$2"
    local old_value="$3"
    local replacement="${4:-}"
    local line tmp
    ensure_allowlist_sources_file || return 1
    make_temp_file "${ALLOWLIST_SOURCES_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    write_allowlist_sources_header "${tmp}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if parse_allowlist_source_line "${line}"; then
            if [[ "${ALLOWLIST_SOURCE_SET_ID}" == "${old_set}" \
                && "${ALLOWLIST_SOURCE_NAME}" == "${old_name}" \
                && "${ALLOWLIST_SOURCE_VALUE}" == "${old_value}" ]]; then
                [[ -n "${replacement}" ]] && printf '%s\n' "${replacement}" >> "${tmp}"
                continue
            fi
            printf '%s\n' "${PARSED_ALLOWLIST_SOURCE}" >> "${tmp}"
        elif [[ -n "$(trim "${line}")" && ! "$(trim "${line}")" =~ ^# ]]; then
            printf '%s\n' "${line}" >> "${tmp}"
        fi
    done < "${ALLOWLIST_SOURCES_FILE}"
    mv -f "${tmp}" "${ALLOWLIST_SOURCES_FILE}"
}

disable_src_allowlist_if_no_custom_entries() {
    case "${SRC_ALLOWLIST_MODE}" in
        manual_only|trusted_dynamic|custom_sources)
            custom_allowlist_has_entries || ENABLE_SRC_ALLOWLIST="0"
            ;;
        region_plus_trusted)
            [[ -n "${SRC_ALLOWLIST_REGION_IDS}" ]] || custom_allowlist_has_entries || ENABLE_SRC_ALLOWLIST="0"
            ;;
        region_only)
            [[ -n "${SRC_ALLOWLIST_REGION_IDS}" ]] || ENABLE_SRC_ALLOWLIST="0"
            ;;
    esac
}

do_add_ddns_allowlist_source() {
    local name domain ttl enabled answer
    read -r -p "请输入 DDNS 显示名（例如 home，可空）: " name
    read -r -p "请输入 DDNS 域名（例如 home.example.com）: " domain
    domain="$(trim "${domain}")"
    validate_ddns_domain "${domain}" || {
        err "DDNS 域名无效：${domain}"
        return 1
    }
    [[ -n "$(trim "${name}")" ]] || name="${domain}"
    ttl="$(prompt_with_default "请输入刷新 TTL 秒数（60-86400）" "300")"
    ttl="$(normalize_source_ttl_seconds "${ttl}")"
    read -r -p "是否启用这个 DDNS 来源 [Y/n]: " answer
    case "${answer,,}" in
        n|no)
            enabled="0"
            ;;
        *)
            enabled="1"
            ;;
    esac
    printf '即将添加 : 名称=%s 域名=%s TTL=%ss 状态=%s\n' \
        "$(sanitize_allowlist_source_text "${name}")" "${domain}" "${ttl}" \
        "$([[ "${enabled}" == "1" ]] && printf '启用' || printf '停用')"
    confirm_yes "确认添加 DDNS 来源" || return 1
    save_allowlist_last_snapshot || return 1
    append_ddns_allowlist_source "${name}" "${domain}" "${ttl}" "${enabled}" || return 1
    if [[ "${enabled}" == "1" ]]; then
        success "DDNS 来源已添加并启用；等待 LAN Worker/路由器解析后通过 SSH 上报。"
    else
        success "DDNS 来源已添加，但尚未启用。"
    fi
}

do_delete_ddns_allowlist_source() {
    local old_set old_name old_value
    select_ddns_allowlist_source || return 1
    old_set="${ALLOWLIST_SOURCE_SET_ID}"
    old_name="${ALLOWLIST_SOURCE_NAME}"
    old_value="${ALLOWLIST_SOURCE_VALUE}"
    confirm_yes "确认删除 DDNS 来源 ${old_name} (${old_value})" || return 1
    save_allowlist_last_snapshot || return 1
    rewrite_selected_ddns_source "${old_set}" "${old_name}" "${old_value}" "" || return 1
    sync_ddns_entries_removed "${old_set}" "${old_name}" "${old_value}" || return 1
    remove_ddns_report_stats "${old_value}" || true
    [[ "${old_name}" != "${old_value}" ]] && remove_ddns_report_stats "${old_name}" || true
    disable_src_allowlist_if_no_custom_entries
    apply_src_allowlist_changes || return 1
}

do_edit_ddns_allowlist_source() {
    local old_set old_name old_value old_enabled old_ttl
    local new_name new_domain new_ttl answer new_enabled replacement line duplicate=0
    select_ddns_allowlist_source || return 1
    old_set="${ALLOWLIST_SOURCE_SET_ID}"
    old_name="${ALLOWLIST_SOURCE_NAME}"
    old_value="${ALLOWLIST_SOURCE_VALUE}"
    old_enabled="${ALLOWLIST_SOURCE_ENABLED}"
    old_ttl="${ALLOWLIST_SOURCE_TTL_SECONDS}"

    new_name="$(prompt_with_default "请输入 DDNS 显示名" "${old_name}")"
    new_domain="$(prompt_with_default "请输入 DDNS 域名" "${old_value}")"
    new_domain="$(trim "${new_domain}")"
    validate_ddns_domain "${new_domain}" || {
        err "DDNS 域名无效：${new_domain}"
        return 1
    }
    [[ -n "$(trim "${new_name}")" ]] || new_name="${new_domain}"
    new_name="$(sanitize_allowlist_source_text "${new_name}")"
    new_domain="$(sanitize_allowlist_source_text "${new_domain}")"
    new_ttl="$(prompt_with_default "请输入刷新 TTL 秒数（60-86400）" "${old_ttl}")"
    new_ttl="$(normalize_source_ttl_seconds "${new_ttl}")"
    if [[ "${old_enabled}" == "1" ]]; then
        answer="$(prompt_with_default "是否启用这个 DDNS 来源 [Y/n]" "Y")"
    else
        answer="$(prompt_with_default "是否启用这个 DDNS 来源 [y/N]" "N")"
    fi
    case "${answer,,}" in
        y|yes)
            new_enabled="1"
            ;;
        n|no)
            new_enabled="0"
            ;;
        *)
            new_enabled="${old_enabled}"
            ;;
    esac

    ensure_allowlist_sources_file || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_source_line "${line}" || continue
        if [[ "${ALLOWLIST_SOURCE_SET_ID}" == "${old_set}" \
            && "${ALLOWLIST_SOURCE_NAME}" == "${old_name}" \
            && "${ALLOWLIST_SOURCE_VALUE}" == "${old_value}" ]]; then
            continue
        fi
        if [[ "${ALLOWLIST_SOURCE_SET_ID}" == "default" \
            && ("${ALLOWLIST_SOURCE_NAME}" == "${new_name}" || "${ALLOWLIST_SOURCE_VALUE}" == "${new_domain}") ]]; then
            duplicate=1
            break
        fi
    done < "${ALLOWLIST_SOURCES_FILE}"
    [[ "${duplicate}" != "1" ]] || {
        err "DDNS 来源已存在：${new_name} / ${new_domain}"
        return 1
    }

    printf '即将修改 : %s (%s) -> %s (%s)，TTL=%ss，状态=%s\n' \
        "${old_name}" "${old_value}" "${new_name}" "${new_domain}" "${new_ttl}" \
        "$([[ "${new_enabled}" == "1" ]] && printf '启用' || printf '停用')"
    confirm_yes "确认修改 DDNS 来源" || return 1
    save_allowlist_last_snapshot || return 1
    replacement="$(serialize_allowlist_source \
        "${old_set}" \
        "ddns" \
        "${new_name}" \
        "${new_domain}" \
        "${new_enabled}" \
        "${new_ttl}" \
        "" \
        "")"
    rewrite_selected_ddns_source "${old_set}" "${old_name}" "${old_value}" "${replacement}" || return 1
    if [[ "${new_domain}" != "${old_value}" || "${new_name}" != "${old_name}" ]]; then
        sync_ddns_entries_removed "${old_set}" "${old_name}" "${old_value}" || return 1
        remove_ddns_report_stats "${old_value}" || true
        [[ "${old_name}" != "${old_value}" ]] && remove_ddns_report_stats "${old_name}" || true
    fi
    if [[ "${new_enabled}" == "1" ]]; then
        do_refresh_ddns_allowlist_sources
    else
        sync_ddns_entries_removed "${old_set}" "${new_name}" "${new_domain}" || return 1
        disable_src_allowlist_if_no_custom_entries
        apply_src_allowlist_changes || return 1
    fi
}

do_toggle_ddns_allowlist_source() {
    local old_set old_name old_value new_enabled replacement
    select_ddns_allowlist_source || return 1
    old_set="${ALLOWLIST_SOURCE_SET_ID}"
    old_name="${ALLOWLIST_SOURCE_NAME}"
    old_value="${ALLOWLIST_SOURCE_VALUE}"
    if [[ "${ALLOWLIST_SOURCE_ENABLED}" == "1" ]]; then
        new_enabled="0"
    else
        new_enabled="1"
    fi
    replacement="$(serialize_allowlist_source \
        "${ALLOWLIST_SOURCE_SET_ID}" \
        "${ALLOWLIST_SOURCE_TYPE}" \
        "${ALLOWLIST_SOURCE_NAME}" \
        "${ALLOWLIST_SOURCE_VALUE}" \
        "${new_enabled}" \
        "${ALLOWLIST_SOURCE_TTL_SECONDS}" \
        "${ALLOWLIST_SOURCE_LAST_RESOLVED_AT}" \
        "${ALLOWLIST_SOURCE_LAST_RESULT}")"
    confirm_yes "确认$([[ "${new_enabled}" == "1" ]] && printf '启用' || printf '停用') DDNS 来源 ${old_name}" || return 1
    save_allowlist_last_snapshot || return 1
    rewrite_selected_ddns_source "${old_set}" "${old_name}" "${old_value}" "${replacement}" || return 1
    if [[ "${new_enabled}" == "1" ]]; then
        do_refresh_ddns_allowlist_sources
    else
        sync_ddns_entries_removed "${old_set}" "${old_name}" "${old_value}" || return 1
        disable_src_allowlist_if_no_custom_entries
        apply_src_allowlist_changes || return 1
    fi
}

do_manage_ddns_allowlist_sources() {
    local choice
    ensure_layout || return
    load_settings 1
    while true; do
        print_title "管理 DDNS 来源"
        printf '当前 DDNS 来源数量：%s\n' "$(allowlist_sources_count)"
        echo ""
        echo "  1) 查看 DDNS 来源和上报统计"
        echo "  2) 添加 DDNS 来源"
        echo "  3) 编辑 DDNS 来源"
        echo "  4) 删除 DDNS 来源"
        echo "  5) 启用 / 停用 DDNS 来源"
        echo "  6) 按已上报结果刷新并应用已启用 DDNS 来源"
        echo "  7) 显示 / 生成外部上报 Token"
        echo "  0) 返回"
        read -r -p "请选择操作 [0-7]: " choice
        case "${choice}" in
            1)
                show_ddns_allowlist_sources
                pause_before_return
                ;;
            2)
                do_add_ddns_allowlist_source || pause_before_return
                ;;
            3)
                do_edit_ddns_allowlist_source || pause_before_return
                ;;
            4)
                do_delete_ddns_allowlist_source || pause_before_return
                ;;
            5)
                do_toggle_ddns_allowlist_source || pause_before_return
                ;;
            6)
                do_refresh_ddns_allowlist_sources || pause_before_return
                ;;
            7)
                do_show_ddns_report_token || pause_before_return
                ;;
            0)
                return
                ;;
            *)
                err "无效选择。"
                ;;
        esac
    done
}

do_collect_blocked_ips() {
    local since="${1:-1 hour ago}"
    ensure_layout || return 1
    collect_blocked_ip_logs "${since}" || return 1
    printf '被阻挡访问日志：新增 %s 条，跳过 %s 条，当前总计 %s 条\n' \
        "${BLOCK_LOG_ADDED_COUNT:-0}" \
        "${BLOCK_LOG_SKIPPED_COUNT:-0}" \
        "$(block_log_count)"
    printf '日志文件：%s\n' "${BLOCK_LOG_FILE}"
    printf '说明：日志文件保存来源 IP、协议、目标端口、阻挡时间；归属地/运营商在查看统计时通过 IPDB 实时显示。\n'
}

do_print_blocked_log_stats() {
    local row idx=1 ip proto dport set_id count first_seen last_seen ip_info
    local ipdb_ready=0
    local -a rows=()
    ensure_layout || return 1
    regenerate_block_summary || return 1
    ipdb_lookup_ready && ipdb_ready=1

    print_title "被阻挡访问统计"
    printf '日志文件   : %s（%s 条，%s）\n' \
        "${BLOCK_LOG_FILE}" "$(block_log_count)" "$(format_bytes "$(block_log_size_bytes)")"
    printf '统计文件   : %s（%s 行）\n' "${BLOCK_SUMMARY_FILE}" "$(block_summary_count)"
    printf 'IPDB 数据  : %s\n' "$(ipdb_status_label)"
    printf '说明       : 文件只保存 IP/协议/端口/时间；归属地和运营商由 IPDB 查询显示。\n'

    mapfile -t rows < <(awk -F '|' 'NF >= 7 && $1 !~ /^#/ { print }' "${BLOCK_SUMMARY_FILE}" | head -n 30)
    if [[ ${#rows[@]} -eq 0 ]]; then
        echo "  (暂无被阻挡访问记录)"
        return 0
    fi

    echo ""
    echo "Top 被阻挡来源："
    for row in "${rows[@]}"; do
        IFS='|' read -r ip proto dport set_id count first_seen last_seen <<< "${row}"
        ip_info="$(ipdb_lookup_ip "${ip}" "${ipdb_ready}")"
        printf '  [%d] %s | %s | %s/%s | 命中 %s 次\n' \
            "${idx}" "${ip}" "${ip_info}" "${proto}" "${dport}" "${count}"
        printf '      首次: %s | 最近: %s | 集合: %s\n' \
            "$(format_learn_time "${first_seen}")" "$(format_learn_time "${last_seen}")" "${set_id}"
        ((idx++))
    done
}

do_compact_block_log() {
    local before_count before_size before_summary after_count after_size after_summary
    ensure_layout || return 1
    before_count="$(block_log_count)"
    before_size="$(block_log_size_bytes)"
    before_summary="$(block_summary_count)"
    compact_block_log_if_needed "manual" || return 1
    after_count="$(block_log_count)"
    after_size="$(block_log_size_bytes)"
    after_summary="$(block_summary_count)"
    if [[ "${before_count}" == "${after_count}" && "${before_size}" == "${after_size}" && "${before_summary}" == "${after_summary}" ]]; then
        info "被阻挡访问日志尚未超过压缩阈值；统计文件已刷新。"
    else
        success "被阻挡访问日志已压缩：${before_count} 条 / $(format_bytes "${before_size}") -> ${after_count} 条 / $(format_bytes "${after_size}")；统计 ${after_summary} 行。"
    fi
}

do_clear_block_log() {
    ensure_layout || return 1
    [[ -s "${BLOCK_LOG_FILE}" ]] || {
        warn "被阻挡访问日志为空。"
        return 0
    }
    confirm_yes "确认清空被阻挡访问日志" || return 1
    write_block_log_header "${BLOCK_LOG_FILE}" || return 1
    regenerate_block_summary || return 1
    success "被阻挡访问日志已清空。"
}

do_save_allowlist_profile() {
    local name label
    if (( $(allowlist_profile_count) >= ALLOWLIST_PROFILE_MAX_COUNT )); then
        err "白名单配置档案最多保存 ${ALLOWLIST_PROFILE_MAX_COUNT} 个，请先删除不用的配置档案。"
        return 1
    fi
    read -r -p "请输入白名单配置档案显示名: " label
    label="$(sanitize_profile_label "${label}")"
    [[ -n "${label}" ]] || {
        err "显示名不能为空。"
        return 1
    }
    name="$(generate_allowlist_profile_id)" || return 1
    save_allowlist_profile_state "${name}" 0 "${label}"
}

do_apply_allowlist_profile() {
    select_allowlist_profile || return 1
    confirm_yes "确认应用白名单配置档案 ${SELECTED_ALLOWLIST_PROFILE}" || return 1
    apply_allowlist_profile "${SELECTED_ALLOWLIST_PROFILE}" 1
}

do_restore_last_allowlist_profile() {
    allowlist_profile_exists "${ALLOWLIST_LAST_PROFILE_NAME}" || {
        err "还没有上一次白名单快照。"
        return 1
    }
    print_allowlist_profile_summary "${ALLOWLIST_LAST_PROFILE_NAME}" "last" || true
    confirm_yes "确认恢复上一次白名单快照" || return 1
    apply_allowlist_profile "${ALLOWLIST_LAST_PROFILE_NAME}" 0
}

do_delete_allowlist_profile() {
    local env_file label_file custom_file sets_file entries_file sources_file
    select_allowlist_profile || return 1
    confirm_yes "确认删除白名单配置档案 ${SELECTED_ALLOWLIST_PROFILE}" || return 1
    env_file="$(allowlist_profile_env_file "${SELECTED_ALLOWLIST_PROFILE}")"
    label_file="$(allowlist_profile_label_file "${SELECTED_ALLOWLIST_PROFILE}")"
    custom_file="$(allowlist_profile_custom_file "${SELECTED_ALLOWLIST_PROFILE}")"
    sets_file="$(allowlist_profile_sets_file "${SELECTED_ALLOWLIST_PROFILE}")"
    entries_file="$(allowlist_profile_entries_file "${SELECTED_ALLOWLIST_PROFILE}")"
    sources_file="$(allowlist_profile_sources_file "${SELECTED_ALLOWLIST_PROFILE}")"
    rm -f -- "${env_file}" "${label_file}" "${custom_file}" "${sets_file}" "${entries_file}" "${sources_file}"
    success "白名单配置档案已删除：${SELECTED_ALLOWLIST_PROFILE}"
}

do_manage_allowlist_profiles() {
    local choice
    while true; do
        print_title "白名单配置档案"
        show_allowlist_profiles
        echo ""
        echo "  1) 保存当前白名单为配置档案"
        echo "  2) 应用配置档案"
        echo "  3) 恢复上一次白名单快照"
        echo "  4) 删除配置档案"
        echo "  0) 返回"
        read -r -p "请选择操作 [0-4]: " choice
        case "${choice}" in
            1)
                do_save_allowlist_profile || pause_before_return
                ;;
            2)
                do_apply_allowlist_profile || pause_before_return
                ;;
            3)
                do_restore_last_allowlist_profile || pause_before_return
                ;;
            4)
                do_delete_allowlist_profile || pause_before_return
                ;;
            0)
                return
                ;;
            *)
                err "无效选择。"
                ;;
        esac
    done
}

do_add_custom_allowlist_entry() {
    local cidr note
    read -r -p "请输入自定义来源 IP 或 CIDR（例如 1.2.3.4 或 1.2.3.0/24）: " cidr
    cidr="$(trim "${cidr}")"
    [[ -n "${cidr}" ]] || return 1
    read -r -p "备注（可空）: " note
    save_allowlist_last_snapshot || return 1
    add_custom_allowlist_entry "${cidr}" "${note}" || return 1
    enable_allowlist_for_custom_add
    apply_src_allowlist_changes
}

do_add_ssh_temp_allowlist_entry() {
    local ip hours expires_at note
    ip="$(detect_ssh_client_ip || true)"
    [[ -n "${ip}" ]] || {
        err "未检测到当前 SSH 客户端公网 IPv4。此功能只能在 SSH 会话内使用。"
        return 1
    }
    hours="$(prompt_with_default "请输入临时放行小时数" "24")"
    hours="$(trim "${hours}")"
    [[ "${hours}" =~ ^[0-9]+$ && "${hours}" -ge 1 && "${hours}" -le 720 ]] || {
        err "临时放行小时数必须是 1-720。"
        return 1
    }
    expires_at="$(utc_after_hours_iso "${hours}")"
    note="ssh client ${ip}, expires ${expires_at}"
    printf 'SSH 来源 IP : %s/32\n' "${ip}"
    printf '过期时间    : %s\n' "${expires_at}"
    confirm_yes "确认加入 default 临时白名单" || return 1
    save_allowlist_last_snapshot || return 1
    append_allowlist_entry "default" "${ip}/32" "ssh_temp" "SSH_CONNECTION" "${note}" "${expires_at}" || return 1
    enable_allowlist_source_type_for_current_mode "ssh_temp" || return 1
    apply_src_allowlist_changes
}

do_delete_custom_allowlist_entry() {
    select_custom_allowlist_entry || return 1
    save_allowlist_last_snapshot || return 1
    remove_custom_allowlist_entry "${SELECTED_LEARN_CIDR}" || {
        err "删除自定义 CIDR 失败。"
        return 1
    }
    disable_src_allowlist_if_no_custom_entries
    apply_src_allowlist_changes
}

do_promote_learned_ip() {
    select_learned_ip_candidate || return 1
    save_allowlist_last_snapshot || return 1
    add_custom_allowlist_entry "${SELECTED_LEARN_CIDR}" "${SELECTED_LEARN_NOTE}" || return 1
    enable_allowlist_for_custom_add
    apply_src_allowlist_changes
}

do_promote_learned_cidr24() {
    select_learned_cidr24_candidate || return 1
    warn "${SELECTED_LEARN_CIDR} 是按学习记录推测的 /24 网段，不等于只属于你的设备。"
    confirm_yes "确认加入这个 /24 自定义白名单" || return 1
    save_allowlist_last_snapshot || return 1
    add_custom_allowlist_entry "${SELECTED_LEARN_CIDR}" "${SELECTED_LEARN_NOTE}" || return 1
    enable_allowlist_for_custom_add
    apply_src_allowlist_changes
}

do_promote_learned_cidr16() {
    select_learned_cidr16_candidate || return 1
    warn "${SELECTED_LEARN_CIDR} 是按学习记录推测的 /16 网段，可能覆盖大量同运营商出口用户。"
    warn "这不是设备级白名单，只适合作为蜂窝网络出口池的宽泛兜底。"
    confirm_strong_yes "确认加入这个 /16 自定义白名单" || return 1
    save_allowlist_last_snapshot || return 1
    add_custom_allowlist_entry "${SELECTED_LEARN_CIDR}" "${SELECTED_LEARN_NOTE}" || return 1
    enable_allowlist_for_custom_add
    apply_src_allowlist_changes
}

do_toggle_learning_service() {
    if command -v systemctl &>/dev/null && systemctl is-active --quiet "${LEARN_SERVICE_NAME}" 2>/dev/null; then
        confirm_yes "确认停止来源 IP 学习服务" || return 1
        disable_learning_service || return 1
        success "来源 IP 学习服务已停止。"
    else
        warn "学习服务只记录成功完成双向转发的来源公网 IP，不会自动放行。"
        confirm_yes "确认安装并启动来源 IP 学习服务" || return 1
        enable_learning_service || return 1
        success "来源 IP 学习服务已启动。"
    fi
}

do_clear_learning_log() {
    [[ -s "${LEARN_LOG_FILE}" ]] || {
        warn "学习日志为空。"
        return 0
    }
    confirm_yes "确认清空学习日志" || return 1
    : > "${LEARN_LOG_FILE}"
    success "学习日志已清空。"
}

do_compact_learning_log() {
    local before_count before_size after_count after_size before_snapshots after_snapshots
    before_count="$(learning_log_count)"
    before_size="$(learning_log_size_bytes)"
    before_snapshots="$(learning_summary_count)"
    compact_learning_log_if_needed "manual" || return 1
    after_count="$(learning_log_count)"
    after_size="$(learning_log_size_bytes)"
    after_snapshots="$(learning_summary_count)"
    if [[ "${before_count}" == "${after_count}" && "${before_size}" == "${after_size}" && "${before_snapshots}" == "${after_snapshots}" ]]; then
        info "学习日志尚未超过压缩阈值，无需压缩。"
    else
        success "学习日志已压缩：${before_count} 条 / $(format_bytes "${before_size}") -> ${after_count} 条 / $(format_bytes "${after_size}")；每日汇总 ${after_snapshots} 天。"
    fi
}

do_install_ipdb_parser() {
    print_title "安装 IPDB 解析依赖"
    warn "将创建专用 Python venv：${IPDB_VENV_DIR}"
    warn "将安装 Python 包：ipip-ipdb"
    IPDB_PIP_INDEX_URL="$(prompt_ipdb_pip_index)" || return 1
    info "已选择 pip 源：$(pip_index_label "${IPDB_PIP_INDEX_URL}")"
    confirm_yes "是否继续安装" || return 1
    install_ipdb_parser_dependency || return 1
    printf 'IPDB 状态 : %s\n' "$(ipdb_status_label)"
}

do_manage_region_allowlist() {
    local choice id
    while true; do
        print_title "地区白名单"
        echo "已选地区："
        show_selected_allowlist_regions
        echo ""
        echo "  1) 添加地区"
        echo "  2) 删除地区"
        echo "  0) 返回"
        read -r -p "请选择操作 [0-2]: " choice
        case "${choice}" in
            1)
                select_iplist_region_interactive || {
                    pause_before_return
                    continue
                }
                id="${SELECTED_REGION_ID}"
                save_allowlist_last_snapshot || {
                    pause_before_return
                    continue
                }
                add_allowlist_region_id "${id}" || {
                    err "添加地区失败。"
                    pause_before_return
                    continue
                }
                enable_allowlist_for_region_add
                apply_src_allowlist_changes || pause_before_return
                ;;
            2)
                select_selected_allowlist_region || {
                    pause_before_return
                    continue
                }
                id="${SELECTED_REGION_ID}"
                save_allowlist_last_snapshot || {
                    pause_before_return
                    continue
                }
                remove_allowlist_region_id "${id}"
                disable_src_allowlist_if_no_custom_entries
                apply_src_allowlist_changes || pause_before_return
                ;;
            0)
                return
                ;;
            *)
                err "无效选择。"
                ;;
        esac
    done
}

do_manage_custom_allowlist() {
    local choice
    while true; do
        print_title "自定义 CIDR 白名单"
        show_custom_allowlist_entries
        echo ""
        echo "  1) 添加自定义 IP/CIDR"
        echo "  2) 删除自定义 IP/CIDR"
        echo "  0) 返回"
        read -r -p "请选择操作 [0-2]: " choice
        case "${choice}" in
            1)
                do_add_custom_allowlist_entry || pause_before_return
                ;;
            2)
                do_delete_custom_allowlist_entry || pause_before_return
                ;;
            0)
                return
                ;;
            *)
                err "无效选择。"
                ;;
        esac
    done
}

do_manage_learning_allowlist() {
    local choice
    while true; do
        print_title "学习服务与候选提升"
        printf '学习服务 : %s\n' "$(learning_service_status_label)"
        printf '学习日志 : %s（%s 条事件，%s）\n' \
            "${LEARN_LOG_FILE}" "$(learning_log_count)" "$(format_bytes "$(learning_log_size_bytes)")"
        printf '每日汇总 : %s（%s 天）\n' "${LEARN_SUMMARY_FILE}" "$(learning_summary_count)"
        printf 'IPDB 数据: %s\n' "$(ipdb_status_label)"
        echo ""
        echo "  1) 启动 / 停止学习服务"
        echo "  2) 查看学习记录统计"
        echo "  3) 清空学习记录"
        echo "  4) 将学习到的单 IP 加入自定义白名单"
        echo "  5) 将学习到的 /24 候选加入自定义白名单"
        echo "  6) 将学习到的 /16 候选加入自定义白名单（高风险）"
        echo "  7) 立即压缩学习日志"
        echo "  0) 返回"
        read -r -p "请选择操作 [0-7]: " choice
        case "${choice}" in
            1)
                do_toggle_learning_service || pause_before_return
                ;;
            2)
                print_learning_stats
                pause_before_return
                ;;
            3)
                do_clear_learning_log || pause_before_return
                ;;
            4)
                do_promote_learned_ip || pause_before_return
                ;;
            5)
                do_promote_learned_cidr24 || pause_before_return
                ;;
            6)
                do_promote_learned_cidr16 || pause_before_return
                ;;
            7)
                do_compact_learning_log || pause_before_return
                ;;
            0)
                return
                ;;
            *)
                err "无效选择。"
                ;;
        esac
    done
}

do_manage_ipdb_tools() {
    local choice
    while true; do
        print_title "IPDB 数据与解析"
        printf 'IPDB 状态 : %s\n' "$(ipdb_status_label)"
        echo ""
        echo "  1) 查看 IPDB 状态"
        echo "  2) 安装 IPDB 解析依赖"
        echo "  0) 返回"
        read -r -p "请选择操作 [0-2]: " choice
        case "${choice}" in
            1)
                printf 'IPDB 状态 : %s\n' "$(ipdb_status_label)"
                pause_before_return
                ;;
            2)
                do_install_ipdb_parser || pause_before_return
                ;;
            0)
                return
                ;;
            *)
                err "无效选择。"
                ;;
        esac
    done
}

do_manage_resource_tasks() {
    local choice token
    ensure_layout || return
    while true; do
        print_title "内网资源更新任务"
        printf 'IPDB 下载源: %s\n' "${IPDB_DOWNLOAD_URL}"
        if token="$(resource_task_token_value 2>/dev/null)"; then
            printf '任务 Token : %s\n' "${token}"
            print_lan_worker_resource_bootstrap_example "${token}"
        else
            printf '任务 Token : 未生成\n'
        fi
        printf '定时创建 : '
        print_resource_task_cron_summary
        echo ""
        echo "  1) 查看任务和结果"
        echo "  2) 创建 iplist 更新任务"
        echo "  3) 创建 qqwry.ipdb 更新任务"
        echo "  4) 创建全部更新任务"
        echo "  5) 重新排队失败 / 执行中任务"
        echo "  6) 生成 / 重置任务 Token"
        echo "  7) 安装 / 更新定时创建任务"
        echo "  8) 删除定时创建任务"
        echo "  0) 返回"
        read -r -p "请选择操作 [0-8]: " choice
        case "${choice}" in
            1)
                list_resource_tasks
                pause_before_return
                ;;
            2)
                create_resource_task "iplist"
                pause_before_return
                ;;
            3)
                create_resource_task "ipdb"
                pause_before_return
                ;;
            4)
                create_resource_task "iplist"
                create_resource_task "ipdb"
                pause_before_return
                ;;
            5)
                confirm_yes "确认重新排队所有失败或执行中的任务" && retry_resource_tasks
                pause_before_return
                ;;
            6)
                confirm_yes "确认生成新 Token（旧客户端 Token 将立即失效）" && {
                    token="$(generate_resource_task_token)" || {
                        pause_before_return
                        continue
                    }
                    success "新任务 Token：${token}"
                    print_lan_worker_resource_bootstrap_example "${token}"
                }
                pause_before_return
                ;;
            7)
                do_install_resource_task_cron_interactive
                pause_before_return
                ;;
            8)
                confirm_yes "确认删除资源任务定时创建 cron" && remove_resource_task_cron
                pause_before_return
                ;;
            0)
                return
                ;;
            *)
                err "无效选择。"
                ;;
        esac
    done
}

do_import_iplist_package() {
    local path
    print_title "导入 / 刷新 iplist 离线包"
    ensure_layout || return
    load_settings 1
    path="$(prompt_with_default "请输入 iplist 离线包路径" "/root/iplist.tar.gz")"
    path="$(trim "${path}")"
    import_iplist_package "${path}" || {
        pause_before_return
        return
    }
    if src_allowlist_enabled; then
        build_src_allowlist_cache || {
            pause_before_return
            return
        }
        backup_managed_files
        write_nft_conf || {
            pause_before_return
            return
        }
        apply_or_save_notice "iplist 已刷新并应用。" "iplist 已刷新，托管配置已更新。"
    fi
    pause_before_return
}

do_manage_src_allowlist() {
    local choice
    ensure_layout || return
    load_settings 1
    while true; do
        print_title "管理源 IP 白名单"
        print_src_allowlist_details
        echo ""
        echo "  [查看]"
        echo "  1) 字段说明：缓存 / entries / pending / 手动 CIDR"
        echo "  2) 查看白名单来源 / IP 明细"
        echo "  3) 查看最终生效 CIDR 缓存"
        echo ""
        echo "  [模式与静态来源]"
        echo "  4) 设置源 IP 限制方式"
        echo "  5) 管理地区白名单"
        echo "  6) 管理手动 CIDR"
        echo "  7) 从当前 SSH 来源临时加入 default /32"
        echo "  8) 管理动态来源开关（高级自选来源）"
        echo ""
        echo "  [动态来源 / 客户端]"
        echo "  9) 管理 DDNS 来源"
        echo " 10) 显示 LAN Worker Self-report / Client IP Token"
        echo " 11) 显示 Egern / SSH report Token"
        echo " 12) 显示 WebAuth 上报 Token"
        echo " 13) 安装 / 显示专用受限上报 key"
        echo " 14) 自动来源安全模式 / pending IP"
        echo " 15) 立即清理动态来源过期 / 超量 IP"
        echo " 16) 安装 / 更新动态来源清理 cron"
        echo " 17) 删除动态来源清理 cron"
        echo ""
        echo "  [学习与阻挡日志]"
        echo " 18) 学习服务与候选提升"
        echo " 19) 采集被阻挡访问日志"
        echo " 20) 查看被阻挡访问统计"
        echo " 21) 压缩被阻挡访问日志"
        echo " 22) 清空被阻挡访问日志"
        echo ""
        echo "  [数据与维护]"
        echo " 23) IPDB 数据与解析"
        echo " 24) 导入 / 刷新 iplist 离线包"
        echo " 25) 重建并应用白名单"
        echo " 26) 管理白名单配置档案"
        echo " 27) 管理内网资源更新任务"
        echo "  0) 返回"
        read -r -p "请选择操作 [0-27]: " choice
        case "${choice}" in
            1)
                do_explain_src_allowlist_fields
                pause_before_return
                ;;
            2)
                do_show_allowlist_source_entries
                pause_before_return
                ;;
            3)
                do_show_src_allowlist_cache
                pause_before_return
                ;;
            4)
                save_allowlist_last_snapshot || {
                    pause_before_return
                    continue
                }
                prompt_src_allowlist_mode || {
                    pause_before_return
                    continue
                }
                apply_src_allowlist_changes || pause_before_return
                ;;
            5)
                do_manage_region_allowlist
                ;;
            6)
                do_manage_custom_allowlist
                ;;
            7)
                do_add_ssh_temp_allowlist_entry || pause_before_return
                ;;
            8)
                do_manage_allowlist_source_switches || pause_before_return
                ;;
            9)
                do_manage_ddns_allowlist_sources
                ;;
            10)
                do_show_client_ip_report_token
                pause_before_return
                ;;
            11)
                do_show_ssh_report_token
                pause_before_return
                ;;
            12)
                do_show_webauth_report_token
                pause_before_return
                ;;
            13)
                do_manage_report_keys
                ;;
            14)
                do_manage_automation_mode
                ;;
            15)
                do_cleanup_dynamic_allowlist || pause_before_return
                ;;
            16)
                do_install_dynamic_allowlist_cleanup_cron_interactive
                ;;
            17)
                confirm_yes "确认删除动态来源清理 cron" && remove_dynamic_allowlist_cleanup_cron
                pause_before_return
                ;;
            18)
                do_manage_learning_allowlist
                ;;
            19)
                do_collect_blocked_ips || pause_before_return
                ;;
            20)
                do_print_blocked_log_stats || pause_before_return
                ;;
            21)
                do_compact_block_log || pause_before_return
                ;;
            22)
                do_clear_block_log || pause_before_return
                ;;
            23)
                do_manage_ipdb_tools
                ;;
            24)
                do_import_iplist_package
                ;;
            25)
                src_allowlist_enabled || {
                    err "白名单未开启，或当前模式没有可用 CIDR。"
                    pause_before_return
                    continue
                }
                apply_src_allowlist_changes || pause_before_return
                ;;
            26)
                do_manage_allowlist_profiles
                ;;
            27)
                do_manage_resource_tasks
                ;;
            0)
                return
                ;;
            *)
                err "无效选择。"
                ;;
        esac
    done
}
do_enable_bbr() {
    print_title "可选开启 BBR + fq"
    warn "纯 nftables 内核转发本身并不依赖 BBR，此项仅作可选优化。"
    confirm_yes "是否继续开启 BBR + fq" || {
        info "已取消。"
        return
    }
    enable_bbr_fq
}

print_recommended_operations() {
    printf '%b推荐操作%b\n' "${C_BOLD}" "${C_RESET}"
    printf '  首次部署: 安装/初始化 -> 新增或导入转发规则 -> 管理源 IP 白名单 -> 诊断/自检\n'
    printf '  日常维护: 查看概览与规则列表；按需新增/编辑规则；管理源 IP 白名单\n'
    printf '  白名单收紧: 管理源 IP 白名单 -> 学习服务与候选提升 -> 手动加入自定义白名单\n'
    printf '  安全基线: 保持入站防火墙接管开启；SSH 端口会自动例外放行\n'
    echo ""
}

count_file_lines() {
    local file="$1"
    [[ -s "${file}" ]] || {
        printf '0\n'
        return 0
    }
    wc -l < "${file}" 2>/dev/null | tr -d '[:space:]'
}

write_block_log_header() {
    local path="$1"
    cat > "${path}" <<'EOF'
# Managed by nftables relay manager
# format: observed_at|src_ip|proto|dport|set_id|raw|ipdb_snapshot
EOF
}

ensure_block_log_file() {
    mkdir -p "${CONF_DIR}" || return 1
    if [[ ! -f "${BLOCK_LOG_FILE}" ]]; then
        write_block_log_header "${BLOCK_LOG_FILE}"
    fi
}

write_block_summary_header() {
    local path="$1"
    cat > "${path}" <<'EOF'
# Managed by nftables relay manager
# format: src_ip|proto|dport|set_id|count|first_seen|last_seen
EOF
}

sanitize_block_log_text() {
    local value="$1"
    value="${value//$'\t'/ }"
    value="${value//$'\r'/ }"
    value="${value//$'\n'/ }"
    value="${value//|//}"
    value="$(trim "${value}")"
    [[ ${#value} -le 512 ]] || value="${value:0:512}"
    printf '%s\n' "${value}"
}

parse_block_log_line() {
    local line="$1"
    BLOCK_LOG_SRC_IP=""
    BLOCK_LOG_PROTO=""
    BLOCK_LOG_DPORT=""
    BLOCK_LOG_SET_ID="default"
    BLOCK_LOG_RAW="$(sanitize_block_log_text "${line}")"
    [[ "${line}" == *"po0-block "* ]] || return 1
    if [[ "${line}" =~ SRC=([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) ]]; then
        BLOCK_LOG_SRC_IP="${BASH_REMATCH[1]}"
    fi
    if [[ "${line}" =~ DPT=([0-9]+) ]]; then
        BLOCK_LOG_DPORT="${BASH_REMATCH[1]}"
    fi
    if [[ "${line}" =~ PROTO=([A-Za-z0-9]+) ]]; then
        BLOCK_LOG_PROTO="${BASH_REMATCH[1],,}"
    fi
    if [[ "${line}" =~ po0-block[[:space:]][^[:space:]]*set=([A-Za-z0-9._-]+) ]]; then
        BLOCK_LOG_SET_ID="${BASH_REMATCH[1]}"
    fi
    if [[ "${line}" =~ po0-block[[:space:]].*proto=([A-Za-z0-9]+) ]]; then
        BLOCK_LOG_PROTO="${BASH_REMATCH[1],,}"
    fi
    validate_host_ipv4 "${BLOCK_LOG_SRC_IP}" || return 1
    validate_port "${BLOCK_LOG_DPORT}" || return 1
    [[ "${BLOCK_LOG_PROTO}" == "tcp" || "${BLOCK_LOG_PROTO}" == "udp" ]] || return 1
}

read_block_log_lines() {
    local since="${1:-1 hour ago}"
    if command -v journalctl &>/dev/null; then
        journalctl -k --no-pager --since "${since}" 2>/dev/null | grep -F 'po0-block ' || true
    elif command -v dmesg &>/dev/null; then
        dmesg 2>/dev/null | grep -F 'po0-block ' || true
    fi
}

collect_blocked_ip_logs() {
    local since="${1:-1 hour ago}"
    local line observed_at snapshot added=0 skipped=0
    ensure_block_log_file || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_block_log_line "${line}" || {
            ((skipped++))
            continue
        }
        if grep -Fq "|${BLOCK_LOG_RAW}" "${BLOCK_LOG_FILE}" 2>/dev/null; then
            ((skipped++))
            continue
        fi
        observed_at="$(utc_now_iso)"
        snapshot="$(ipdb_snapshot_for_ip "${BLOCK_LOG_SRC_IP}")"
        snapshot="$(sanitize_block_log_text "${snapshot}")"
        printf '%s|%s|%s|%s|%s|%s|%s\n' \
            "${observed_at}" \
            "${BLOCK_LOG_SRC_IP}" \
            "${BLOCK_LOG_PROTO}" \
            "${BLOCK_LOG_DPORT}" \
            "${BLOCK_LOG_SET_ID}" \
            "${BLOCK_LOG_RAW}" \
            "${snapshot}" >> "${BLOCK_LOG_FILE}"
        ((added++))
    done < <(read_block_log_lines "${since}")
    BLOCK_LOG_ADDED_COUNT="${added}"
    BLOCK_LOG_SKIPPED_COUNT="${skipped}"
    compact_block_log_if_needed "collect" || return 1
}

block_log_count() {
    local line count=0
    [[ -f "${BLOCK_LOG_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="$(trim "${line}")"
        [[ -n "${line}" && ! "${line}" =~ ^# ]] || continue
        ((count++))
    done < "${BLOCK_LOG_FILE}"
    printf '%s\n' "${count}"
}

block_log_line_count() {
    [[ -f "${BLOCK_LOG_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    wc -l < "${BLOCK_LOG_FILE}" 2>/dev/null | tr -d '[:space:]'
}

block_log_size_bytes() {
    [[ -f "${BLOCK_LOG_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    wc -c < "${BLOCK_LOG_FILE}" 2>/dev/null | tr -d '[:space:]'
}

block_summary_count() {
    [[ -f "${BLOCK_SUMMARY_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    awk -F '|' 'NF >= 7 && $1 !~ /^#/ { count++ } END { print count + 0 }' "${BLOCK_SUMMARY_FILE}" 2>/dev/null
}

regenerate_block_summary() {
    local tmp
    ensure_block_log_file || return 1
    make_temp_file "${BLOCK_SUMMARY_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    write_block_summary_header "${tmp}"
    awk -F '|' '
        NF >= 6 && $1 !~ /^#/ {
            key = $2 "|" $3 "|" $4 "|" $5
            count[key]++
            if (!(key in first) || $1 < first[key]) first[key] = $1
            if (!(key in last) || $1 > last[key]) last[key] = $1
        }
        END {
            for (key in count) {
                print key "|" count[key] "|" first[key] "|" last[key]
            }
        }
    ' "${BLOCK_LOG_FILE}" | sort -t '|' -k5,5nr -k1,1 >> "${tmp}"
    mv -f "${tmp}" "${BLOCK_SUMMARY_FILE}"
}

compact_block_log_if_needed() {
    local reason="${1:-auto}"
    local size total data_lines overflow tmp
    ensure_block_log_file || return 1
    size="$(block_log_size_bytes)"
    total="$(block_log_line_count)"
    [[ "${size}" =~ ^[0-9]+$ ]] || size=0
    [[ "${total}" =~ ^[0-9]+$ ]] || total=0
    data_lines="$(block_log_count)"
    [[ "${data_lines}" =~ ^[0-9]+$ ]] || data_lines=0
    overflow=0
    if (( data_lines > BLOCK_LOG_KEEP_LINES )); then
        overflow=$((data_lines - BLOCK_LOG_KEEP_LINES))
    elif (( size > BLOCK_LOG_MAX_BYTES )); then
        overflow=$((data_lines / 2))
    fi
    if (( overflow > 0 )); then
        make_temp_file "${BLOCK_LOG_FILE}.compact" || return 1
        tmp="${TEMP_FILE_RESULT}"
        write_block_log_header "${tmp}"
        awk -F '|' -v overflow="${overflow}" '
            $1 ~ /^#/ { next }
            {
                data_seen++
                if (data_seen <= overflow) next
                print
            }
        ' "${BLOCK_LOG_FILE}" >> "${tmp}"
        mv -f "${tmp}" "${BLOCK_LOG_FILE}"
    fi
    regenerate_block_summary || return 1
}

do_render() {
    local render_dir render_conf render_cache
    make_temp_dir "${TMPDIR:-/tmp}" "po0-relay-render" || return 1
    render_dir="${TEMP_DIR_RESULT}"
    render_conf="${render_dir}/po0-relay.conf"
    render_cache="${render_dir}/po0-relay-src-allowlist.txt"
    write_nft_conf "${render_conf}" "${render_cache}" || return 1
    cat "${render_conf}"
}

print_cli_usage() {
    printf '%s\n' \
        "用法: nftables-relay-manager.sh [命令]" \
        "" \
        "PO0 主控部署（PO0 不依赖 HTTPS 拉取，推荐本地上传后运行）:" \
        "  scp scripts/po0/nftables/nftables-relay-manager.sh root@<PO0_HOST>:${MANAGER_INSTALL_PATH}" \
        "  ssh root@<PO0_HOST> \"chmod +x ${MANAGER_INSTALL_PATH} && bash ${MANAGER_INSTALL_PATH}\"" \
        "" \
        "LAN Worker / 客户端快速启动（在 LAN Worker/客户端上执行，不在 PO0 上执行）:" \
        "  bash ${MANAGER_INSTALL_PATH} --show-client-deploy-commands tokens" \
        "  bash ${MANAGER_INSTALL_PATH} --show-client-deploy-commands lan-resource" \
        "  bash ${MANAGER_INSTALL_PATH} --show-client-deploy-commands lan-ddns" \
        "  bash ${MANAGER_INSTALL_PATH} --show-client-deploy-commands self-server" \
        "  bash ${MANAGER_INSTALL_PATH} --show-client-deploy-commands egern" \
        "" \
        "常用命令:" \
        "  --render         将计划生成的 nftables 配置输出到标准输出。" \
        "  --refresh-ddns   按 LAN Worker/路由器已上报且仍在 TTL 内的 DDNS 结果重建/应用；PO0 不做本地 DNS 解析，也不延长原上报 TTL。" \
        "  --collect-blocked [since]" \
        "                   采集 po0-block 内核日志到被阻挡访问 TSV。默认范围: 1 hour ago。" \
        "  白名单模式      manual_only / trusted_dynamic / region_plus_trusted / region_only / custom_sources。" \
        "                   custom_sources 可在菜单中手动组合 manual、ssh_temp、ddns、client_ip、ssh_report、webauth、learned、region。" \
        "" \
        "DDNS / Worker 上报接口（SSH only，PO0 不开放 HTTP）:" \
        "  --ddns-report <source-key> <公网IPv4[,公网IPv4...]> [token]" \
        "                   接收 LAN Worker/路由器解析好的 DDNS A 记录，写入 PO0 DDNS 来源白名单。" \
        "  --ddns-report-check <source-key> [token]" \
        "                   只读检查 PO0 DDNS 来源 key 和上报 token，供 LAN Worker probe 使用。" \
        "  --outbound-ip-report / --outbound-ip-report-check" \
        "                   旧脚本兼容别名；新自上报应先报 LAN Worker，再由 LAN Worker 调 --client-ip-report。" \
        "  --client-ip-report <source-id> <ipv4> <token> [identity] [ttl]" \
        "                   接收 LAN Worker self-report 代报的访问设备公网 IPv4。" \
        "  --client-ip-report-check <source-id> [token]" \
        "                   只读检查客户端 IP 上报 token。" \
        "  --ssh-ip-report <source-id> <ipv4> <token> [identity] [ttl]" \
        "                   接收 Egern / 直接 SSH 上报的当前出口公网 IPv4，写入 ssh_report 来源。" \
        "  --ssh-ip-report-check <source-id> [token]" \
        "                   只读检查 SSH report token。" \
        "  --webauth-report <source-id> <ipv4> <identity> <expires-at> <token> [note]" \
        "                   接收 LAN Worker WebAuth 上报；PO0 不开放 HTTP。" \
        "  --webauth-report-check <source-id> [token]" \
        "                   只读检查 WebAuth 上报 token。" \
        "  --automation-mode <regular|attack>" \
        "                   attack 模式冻结自动新增白名单，新自动 IP 进入待审核。" \
        "  --pending-auto-sources" \
        "                   查看自动来源待审核 IP。" \
        "  --cleanup-dynamic-allowlist" \
        "                   清理 ddns/client_ip/ssh_report/webauth 的过期和超量 IP；每个来源默认最多保留 5 个。" \
        "  --install-dynamic-allowlist-cleanup-cron [hourly|daily|weekly|monthly|CRON_EXPR]" \
        "                   安装/更新动态来源清理 cron，默认 daily。" \
        "  --remove-dynamic-allowlist-cleanup-cron" \
        "                   删除动态来源清理 cron。" \
        "  --show-client-deploy-commands [tokens|lan-resource|lan-ddns|self-server|self-client|webauth|egern|key|all]" \
        "                   按主题输出 LAN Worker、Self-report、WebAuth、Egern 的部署命令；all 为旧版全量输出。" \
        "  --worker-token-bundle [--ensure-resource-token]" \
        "                   输出 LAN Worker 向导使用的 KEY=value token bundle（SSH only）。" \
        "  --show-report-keys [user]" \
        "                   显示普通登录 key、PO0 受限上报 key、其它 restricted key 分类。" \
        "  --install-report-key <egern|worker|all> '<public-key-line>' [user]" \
        "                   追加或转换专用受限上报 public key；不接收私钥。" \
        "  --compat-check   只读检查旧配置/旧白名单/旧日志兼容状态。" \
        "  --cleanup-legacy --dry-run|--apply" \
        "                   清理旧文件候选；默认不删除 live state。" \
        "" \
        "内网资源任务管理（PO0 管理员）:" \
        "  --resource-task-create <iplist|ipdb|all>" \
        "                   创建一次资源更新任务，等待内网 Worker 领取。" \
        "  --install-resource-task-cron <iplist|ipdb|all> [hourly|daily|weekly|monthly|CRON_EXPR]" \
        "                   安装/更新 PO0 端定时创建任务。默认 daily；CRON_EXPR 需整体加引号；管道运行时会自动落盘。" \
        "  --remove-resource-task-cron" \
        "                   删除 PO0 端资源任务定时创建 cron。" \
        "" \
        "内网资源任务接口（供 Worker 调用）:" \
        "  --resource-task-ping <token>" \
        "                   只读检查资源任务 token，供内网 Worker probe 使用。" \
        "  --resource-task-claim <worker_id> <token>" \
        "                   内网机器领取一个等待中的 iplist/IPDB 更新任务。" \
        "  --resource-task-complete <task_id> <worker_id> <sha256> <size> <token>" \
        "                   校验已回传文件，导入资源并记录任务结果。" \
        "  --resource-task-fail <task_id> <worker_id> <reason> <token>" \
        "                   记录内网机器执行失败。" \
        "" \
        "后台服务:" \
        "  --learn-service  运行后台来源 IP 学习服务。" \
        "  --help           显示本帮助。" \
        "" \
        "不带命令运行时进入交互菜单。"
}

main_menu() {
    local choice
    while true; do
        print_title "nftables relay manager"
        print_status_panel
        print_runtime_rule_hint
        print_recommended_operations
        echo ""
        printf '%b基础操作%b\n' "${C_BOLD}" "${C_RESET}"
        echo "  1) 安装 / 初始化 nftables"
        echo "  2) 手动刷新 PO0 公网 IP 缓存"
        echo "  3) 查看概览与规则列表"
        echo ""
        printf '%b规则管理%b\n' "${C_BOLD}" "${C_RESET}"
        echo "  4) 新增转发规则"
        echo "  5) 编辑转发规则"
        echo "  6) 调整规则顺序"
        echo "  7) 启用 / 停用规则"
        echo "  8) 删除转发规则"
        echo "  9) 导入规则 / 接管现有 nft 规则"
        echo " 10) 导出规则"
        echo ""
        printf '%b访问来源 / 白名单 / 客户端%b\n' "${C_BOLD}" "${C_RESET}"
        echo " 11) 管理源 IP 白名单"
        echo " 12) LAN Worker / 客户端 / Egern 部署命令"
        echo " 13) 管理内网资源更新任务"
        echo ""
        printf '%b系统维护%b\n' "${C_BOLD}" "${C_RESET}"
        echo " 14) 修改中转机参数"
        echo " 15) 诊断 / 自检"
        echo " 16) 可选开启 BBR + fq"
        echo "  0) 退出"
        print_divider
        read -r -p "请选择操作 [0-16]: " choice
        case "${choice}" in
            1) do_install ;;
            2) do_refresh_public_ip ;;
            3) do_list ;;
            4) do_add ;;
            5) do_edit_rule ;;
            6) do_reorder_rules ;;
            7) do_toggle_rules ;;
            8) do_delete ;;
            9) do_import_rules ;;
            10) do_export_rules ;;
            11) do_manage_src_allowlist ;;
            12) do_manage_client_deploy_commands ;;
            13) do_manage_resource_tasks ;;
            14) do_edit_settings ;;
            15) do_diagnose ;;
            16) do_enable_bbr ;;
            0)
                info "再见。"
                exit 0
                ;;
            *)
                err "无效选择，请输入 0-16。"
                ;;
        esac
    done
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    print_cli_usage
    exit 0
fi

check_root
case "${1:-}" in
    --learn-service)
        run_learning_service
        exit $?
        ;;
    --render)
        do_render
        exit $?
        ;;
    --refresh-ddns)
        do_refresh_ddns_allowlist_sources
        exit $?
        ;;
    --outbound-ip-report|--ddns-report)
        do_report_ddns_allowlist_source "${2:-}" "${3:-}" "${4:-}"
        exit $?
        ;;
    --outbound-ip-report-check|--ddns-report-check)
        do_check_ddns_report_source "${2:-}" "${3:-}"
        exit $?
        ;;
    --client-ip-report)
        do_report_client_ip_source "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}"
        exit $?
        ;;
    --client-ip-report-check)
        do_check_client_ip_report_source "${2:-}" "${3:-}"
        exit $?
        ;;
    --ssh-ip-report)
        do_report_ssh_ip_source "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}"
        exit $?
        ;;
    --ssh-ip-report-check)
        do_check_ssh_ip_report_source "${2:-}" "${3:-}"
        exit $?
        ;;
    --webauth-report)
        do_report_webauth_source "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}" "${7:-}"
        exit $?
        ;;
    --webauth-report-check)
        do_check_webauth_report_source "${2:-}" "${3:-}"
        exit $?
        ;;
    --automation-mode)
        set_automation_mode "${2:-}"
        exit $?
        ;;
    --pending-auto-sources)
        do_list_pending_auto_sources
        exit $?
        ;;
    --cleanup-dynamic-allowlist)
        do_cleanup_dynamic_allowlist
        exit $?
        ;;
    --install-dynamic-allowlist-cleanup-cron)
        install_dynamic_allowlist_cleanup_cron "${@:2}"
        exit $?
        ;;
    --remove-dynamic-allowlist-cleanup-cron)
        remove_dynamic_allowlist_cleanup_cron
        exit $?
        ;;
    --show-client-deploy-commands)
        do_show_client_deploy_commands "${2:-index}"
        exit $?
        ;;
    --worker-token-bundle)
        do_worker_token_bundle "${2:-}"
        exit $?
        ;;
    --show-report-keys)
        do_show_report_keys_cli "${2:-root}"
        exit $?
        ;;
    --install-report-key)
        do_install_report_key_cli "${2:-}" "${3:-}" "${4:-root}"
        exit $?
        ;;
    --compat-check)
        do_compat_check
        exit $?
        ;;
    --cleanup-legacy)
        do_cleanup_legacy "${2:---dry-run}"
        exit $?
        ;;
    --resource-task-create)
        create_resource_tasks_for_type "${2:-all}"
        exit $?
        ;;
    --install-resource-task-cron)
        install_resource_task_cron "${2:-all}" "${@:3}"
        exit $?
        ;;
    --remove-resource-task-cron)
        remove_resource_task_cron
        exit $?
        ;;
    --resource-task-ping)
        do_resource_task_ping "${2:-}"
        exit $?
        ;;
    --resource-task-claim)
        claim_resource_task "${2:-}" "${3:-}"
        exit $?
        ;;
    --resource-task-complete)
        finish_resource_task "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}"
        exit $?
        ;;
    --resource-task-fail)
        fail_resource_task "${2:-}" "${3:-}" "${4:-}" "${5:-}"
        exit $?
        ;;
    --collect-blocked)
        do_collect_blocked_ips "${2:-1 hour ago}"
        exit $?
        ;;
    "")
        main_menu
        ;;
    *)
        print_cli_usage >&2
        exit 2
        ;;
esac
