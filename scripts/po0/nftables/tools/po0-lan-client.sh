#!/usr/bin/env bash
set -uo pipefail

RAW_URL="https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/tools/po0-lan-client.sh"
DEFAULT_PO0_SCRIPT="/root/nftables-relay-manager.sh"
PO0_HOST="${PO0_HOST:-}"
PO0_PORT="${PO0_PORT:-22}"
PO0_USER="${PO0_USER:-root}"
PO0_SCRIPT="${PO0_SCRIPT:-${DEFAULT_PO0_SCRIPT}}"
DDNS_DOMAIN="${PO0_SOURCE_KEY:-${SOURCE_KEY:-${DDNS_SOURCE_KEY:-${DDNS_DOMAIN:-}}}}"
DDNS_RESOLVE_DOMAIN="${PO0_DDNS_DOMAIN:-${DDNS_RESOLVE_DOMAIN:-}}"
REPORT_MODE="${PO0_REPORT_MODE:-${REPORT_MODE:-}}"
REPORT_KEY="${REPORT_KEY:-${DDNS_NAME:-}}"
DDNS_TOKEN="${PO0_SOURCE_TOKEN:-${OUTBOUND_IP_TOKEN:-${DDNS_TOKEN:-}}}"
CLIENT_IP_TOKEN="${PO0_CLIENT_IP_TOKEN:-${CLIENT_IP_TOKEN:-}}"
RESOURCE_TOKEN="${PO0_RESOURCE_TOKEN:-}"
SSH_EXTRA_ARGS="${SSH_EXTRA_ARGS:-}"
CONFIG_FILE="${PO0_LAN_CLIENT_CONFIG:-}"
STATS_FILE="${PO0_LAN_CLIENT_STATS:-}"
RESOURCE_STATS_FILE="${PO0_LAN_RESOURCE_STATS:-}"
INSTALL_PATH="${PO0_LAN_CLIENT_INSTALL_PATH:-}"
IPDB_DOWNLOAD_URL="${PO0_IPDB_DOWNLOAD_URL:-https://raw.githubusercontent.com/nmgliangwei/qqwry.ipdb/main/qqwry.ipdb}"
WORKER_ID="${PO0_WORKER_ID:-$(hostname 2>/dev/null || printf 'po0-worker')}"
STATS_FILE_EXPLICIT="0"
ACTION=""
CRON_MINUTES="5"
INSTALL_CRON=""
BOOTSTRAP_RUN="1"
BOOTSTRAP_PROBE="1"
BOOTSTRAP_LABEL=""
WEBAUTH_LISTEN="${PO0_WEBAUTH_LISTEN:-127.0.0.1:8787}"
WEBAUTH_SOURCE="${PO0_WEBAUTH_SOURCE:-cf-access}"
WEBAUTH_TOKEN="${PO0_WEBAUTH_TOKEN:-}"
WEBAUTH_TTL_SECONDS="${PO0_WEBAUTH_TTL_SECONDS:-3600}"
SELF_REPORT_LISTEN="${PO0_SELF_REPORT_LISTEN:-127.0.0.1:8788}"
SELF_REPORT_SOURCE="${PO0_SELF_REPORT_SOURCE:-self-report}"
SELF_REPORT_SECRET="${PO0_SELF_REPORT_SECRET:-}"
SELF_REPORT_TTL_SECONDS="${PO0_SELF_REPORT_TTL_SECONDS:-3600}"

[[ -n "${STATS_FILE}" ]] && STATS_FILE_EXPLICIT="1"

default_config_file() {
    if [[ -n "${CONFIG_FILE}" ]]; then
        printf '%s\n' "${CONFIG_FILE}"
    elif [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
        printf '%s\n' "${XDG_CONFIG_HOME}/po0-lan-client/targets.tsv"
    elif [[ -n "${HOME:-}" ]]; then
        printf '%s\n' "${HOME}/.config/po0-lan-client/targets.tsv"
    else
        printf '%s\n' "./po0-lan-client-targets.tsv"
    fi
}

CONFIG_FILE="$(default_config_file)"

usage() {
    printf '%s\n' \
        "PO0 内网 Worker" \
        "" \
        "用法:" \
        "  bash po0-lan-client.sh --menu" \
        "  bash po0-lan-client.sh --probe --po0-host HOST --source-key home --ddns-domain home.example.com --token TOKEN --resource-token TOKEN" \
        "  bash po0-lan-client.sh --bootstrap --po0-host HOST --source-key home --ddns-domain home.example.com --token TOKEN --resource-token TOKEN --install-cron 5" \
        "  bash po0-lan-client.sh --bootstrap --po0-host HOST --resource-token TOKEN --install-cron 5" \
        "  curl -fsSL ${RAW_URL} | bash -s -- --bootstrap --po0-host HOST --source-key home --ddns-domain home.example.com --token TOKEN --resource-token TOKEN --install-cron 5" \
        "  po0-lan-client --webauth-server --listen 127.0.0.1:8787 --po0-host HOST --webauth-token TOKEN" \
        "  po0-lan-client --self-report-server --self-report-listen 127.0.0.1:8788 --po0-host HOST --client-ip-token TOKEN" \
        "" \
        "常用命令:" \
        "  --probe              只检测依赖、DDNS 解析、SSH、PO0 token，不修改 PO0 白名单。" \
        "  --bootstrap          写入本机目标配置，默认先 probe，再执行一次 --run。" \
        "  --install-cron [N]   安装/更新定时任务；管道运行时会自动落盘。" \
        "  --source-key KEY     PO0 端来源 key/名称；脚本不会解析这个值。" \
        "  --ddns-domain DOMAIN LAN Worker 要解析的 DDNS 域名；结果通过 SSH 上报 PO0。" \
        "  --domain DOMAIN      兼容旧参数：没有 --ddns-domain 时同时作为 source-key 和 DDNS 域名。" \
        "  --ssh-extra-args STR 可选 SSH 参数，例如 '-i /path/key -o BatchMode=yes'。" \
        "  --no-run             bootstrap 后不立即执行 DDNS 解析上报和资源轮询。" \
        "  --no-cron            bootstrap 时不安装定时任务。" \
        "  --run                执行已配置目标的 DDNS 解析上报和资源任务轮询。" \
        "  --webauth-server     在 LAN Worker 本地运行 WebAuth 接收服务；PO0 不开放 HTTP。" \
        "  --install-webauth-service 安装 systemd 服务运行 WebAuth server。" \
        "  --webauth-probe      检查 WebAuth 依赖和 PO0 上报 token。" \
        "  --self-report-server 在 LAN Worker 本地运行自上报接收服务；访问设备先报 LAN Worker，再由 LAN Worker SSH 上报 PO0。" \
        "  --self-report-probe  检查自上报接收端依赖和 PO0 client-ip token。" \
        "  --menu               进入高级菜单。" \
        "" \
        "默认 PO0_SCRIPT=${DEFAULT_PO0_SCRIPT}；可用 --po0-script 覆盖，兼容旧配置。" \
        "WebAuth server 只运行在 LAN Worker 上，推荐经 cloudflared tunnel + Cloudflare Access 暴露。" \
        "DDNS resolver 模式解析 --ddns-domain；--source-key 只用于匹配 PO0 端来源，不在本机解析。" \
        "Self-report 模式接收访问设备上报/请求里的公网 IP，再通过 PO0 的 client_ip 来源写白名单。" \
        "资源任务由 PO0 创建，本机主动领取固定白名单任务（iplist/ipdb），构建/下载后通过 SCP 回传；不需要来源 key 也可以只做资源任务。" \
        "配置文件会明文保存 Token，请放在可信内网机器上，并注意文件权限。"
}

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "${value}"
}

sanitize_field() {
    local value="$1"
    value="${value//$'\t'/ }"
    value="${value//$'\r'/ }"
    value="${value//$'\n'/ }"
    value="${value//|/ }"
    trim "${value}"
}

path_dirname() {
    local path="$1"
    case "${path}" in
        */*)
            printf '%s\n' "${path%/*}"
            ;;
        *)
            printf '.\n'
            ;;
    esac
}

refresh_stats_file() {
    if [[ "${STATS_FILE_EXPLICIT}" != "1" || -z "${STATS_FILE}" ]]; then
        STATS_FILE="$(path_dirname "${CONFIG_FILE}")/stats.tsv"
    fi
}

refresh_resource_stats_file() {
    if [[ -z "${RESOURCE_STATS_FILE}" ]]; then
        RESOURCE_STATS_FILE="$(path_dirname "${CONFIG_FILE}")/resource-stats.tsv"
    fi
}

sh_quote() {
    local value="$1"
    value="${value//\'/\'\\\'\'}"
    printf "'%s'" "${value}"
}

have_cmd() {
    command -v "$1" >/dev/null 2>&1
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

is_public_ipv4() {
    local ip="$1"
    local o1 o2
    validate_ip "${ip}" || return 1
    IFS='.' read -r o1 o2 _ _ <<< "${ip}"
    (( o1 == 0 )) && return 1
    (( o1 == 10 )) && return 1
    (( o1 == 127 )) && return 1
    (( o1 == 169 && o2 == 254 )) && return 1
    (( o1 == 172 && o2 >= 16 && o2 <= 31 )) && return 1
    (( o1 == 192 && o2 == 168 )) && return 1
    (( o1 == 100 && o2 >= 64 && o2 <= 127 )) && return 1
    (( o1 >= 224 )) && return 1
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

extract_public_ipv4_csv() {
    local text="$1" ip csv="" seen=","
    while IFS= read -r ip; do
        ip="$(trim "${ip}")"
        is_public_ipv4 "${ip}" || continue
        case "${seen}" in
            *,"${ip}",*) continue ;;
        esac
        seen+="${ip},"
        if [[ -n "${csv}" ]]; then
            csv+=",${ip}"
        else
            csv="${ip}"
        fi
    done < <(printf '%s\n' "${text}" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' || true)
    [[ -n "${csv}" ]] || return 1
    printf '%s\n' "${csv}"
}

normalize_report_mode() {
    local mode
    mode="$(trim "${1:-}")"
    case "${mode}" in
        ""|auto)
            printf 'auto\n'
            ;;
        ddns|ddns-resolver|resolver)
            printf 'ddns\n'
            ;;
        none|resource|resource-only|off)
            printf 'none\n'
            ;;
        *)
            printf 'auto\n'
            ;;
    esac
}

resolve_ddns_ipv4_csv() {
    local domain="$1" raw="" out=""
    domain="$(trim "${domain}")"
    [[ -n "${domain}" ]] || return 1
    if have_cmd getent; then
        raw+="$(getent ahostsv4 "${domain}" 2>/dev/null || true)"$'\n'
    fi
    if have_cmd dig; then
        raw+="$(dig +short A "${domain}" 2>/dev/null || true)"$'\n'
    fi
    if have_cmd host; then
        raw+="$(host -t A "${domain}" 2>/dev/null || true)"$'\n'
    fi
    if have_cmd nslookup; then
        raw+="$(nslookup -type=A "${domain}" 2>/dev/null || true)"$'\n'
    fi
    out="$(extract_public_ipv4_csv "${raw}" 2>/dev/null || true)"
    [[ -n "${out}" ]] || return 1
    printf '%s\n' "${out}"
}

ensure_config_file() {
    local dir
    dir="$(path_dirname "${CONFIG_FILE}")"
    if [[ ! -d "${dir}" ]]; then
        if command -v mkdir >/dev/null 2>&1; then
            mkdir -p "${dir}" || return 1
        else
            printf '配置目录不存在，且当前系统缺少 mkdir：%s\n' "${dir}" >&2
            return 1
        fi
    fi
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        {
            printf '# enabled|label|source_key(optional if resource_token)|report_key|po0_host|po0_port|po0_user|po0_script|source_token|ssh_extra_args|resource_token|report_mode|ddns_domain\n'
        } > "${CONFIG_FILE}" || return 1
        chmod 600 "${CONFIG_FILE}" 2>/dev/null || true
    fi
}

ensure_resource_stats_file() {
    local dir
    refresh_resource_stats_file
    dir="$(path_dirname "${RESOURCE_STATS_FILE}")"
    mkdir -p "${dir}" || return 1
    if [[ ! -f "${RESOURCE_STATS_FILE}" ]]; then
        printf '# endpoint_id|success_count|fail_count|last_task|last_type|last_status|last_at|last_message\n' > "${RESOURCE_STATS_FILE}" || return 1
        chmod 600 "${RESOURCE_STATS_FILE}" 2>/dev/null || true
    fi
}

ensure_stats_file() {
    local dir
    refresh_stats_file
    dir="$(path_dirname "${STATS_FILE}")"
    if [[ ! -d "${dir}" ]]; then
        if command -v mkdir >/dev/null 2>&1; then
            mkdir -p "${dir}" || return 1
        else
            printf '统计目录不存在，且当前系统缺少 mkdir：%s\n' "${dir}" >&2
            return 1
        fi
    fi
    if [[ ! -f "${STATS_FILE}" ]]; then
        {
            printf '# target_id|success_count|fail_count|last_status|last_at|last_ip_csv|last_error\n'
        } > "${STATS_FILE}" || return 1
        chmod 600 "${STATS_FILE}" 2>/dev/null || true
    fi
}

require_arg_value() {
    local option="$1"
    [[ $# -ge 2 && -n "${2:-}" ]] || {
        printf '缺少参数值：%s\n' "${option}" >&2
        exit 1
    }
}

prompt_default() {
    local prompt="$1"
    local default="$2"
    local value
    if [[ -n "${default}" ]]; then
        read -r -p "${prompt} [${default}]: " value
        value="$(trim "${value}")"
        [[ -n "${value}" ]] || value="${default}"
    else
        read -r -p "${prompt}: " value
        value="$(trim "${value}")"
    fi
    printf '%s\n' "${value}"
}

parse_target_line() {
    local line="$1"
    line="$(trim "${line}")"
    [[ -n "${line}" ]] || return 1
    case "${line}" in
        \#*)
            return 1
            ;;
    esac
    if [[ "${line}" == *"|"* ]]; then
        IFS='|' read -r TARGET_ENABLED TARGET_LABEL TARGET_DOMAIN TARGET_REPORT_KEY TARGET_PO0_HOST TARGET_PO0_PORT TARGET_PO0_USER TARGET_PO0_SCRIPT TARGET_TOKEN TARGET_SSH_EXTRA_ARGS TARGET_RESOURCE_TOKEN TARGET_REPORT_MODE TARGET_DDNS_RESOLVE_DOMAIN <<< "${line}"
    else
        # Legacy whitespace configs had no resource_token column; keep all
        # remaining words in ssh_extra_args for backward compatibility.
        read -r TARGET_ENABLED TARGET_LABEL TARGET_DOMAIN TARGET_REPORT_KEY TARGET_PO0_HOST TARGET_PO0_PORT TARGET_PO0_USER TARGET_PO0_SCRIPT TARGET_TOKEN TARGET_SSH_EXTRA_ARGS <<< "${line}"
        TARGET_RESOURCE_TOKEN=""
        TARGET_REPORT_MODE=""
        TARGET_DDNS_RESOLVE_DOMAIN=""
    fi
    TARGET_ENABLED="$(sanitize_field "${TARGET_ENABLED}")"
    TARGET_LABEL="$(sanitize_field "${TARGET_LABEL}")"
    TARGET_DOMAIN="$(sanitize_field "${TARGET_DOMAIN}")"
    TARGET_REPORT_KEY="$(sanitize_field "${TARGET_REPORT_KEY}")"
    TARGET_PO0_HOST="$(sanitize_field "${TARGET_PO0_HOST}")"
    TARGET_PO0_PORT="$(sanitize_field "${TARGET_PO0_PORT}")"
    TARGET_PO0_USER="$(sanitize_field "${TARGET_PO0_USER}")"
    TARGET_PO0_SCRIPT="$(sanitize_field "${TARGET_PO0_SCRIPT}")"
    TARGET_TOKEN="$(sanitize_field "${TARGET_TOKEN}")"
    TARGET_SSH_EXTRA_ARGS="$(sanitize_field "${TARGET_SSH_EXTRA_ARGS}")"
    TARGET_RESOURCE_TOKEN="$(sanitize_field "${TARGET_RESOURCE_TOKEN:-}")"
    TARGET_REPORT_MODE="$(normalize_report_mode "${TARGET_REPORT_MODE:-}")"
    TARGET_DDNS_RESOLVE_DOMAIN="$(sanitize_field "${TARGET_DDNS_RESOLVE_DOMAIN:-}")"
    if [[ "${TARGET_REPORT_MODE}" == "auto" ]]; then
        if [[ -n "${TARGET_DOMAIN}" ]]; then
            TARGET_REPORT_MODE="ddns"
            [[ -n "${TARGET_DDNS_RESOLVE_DOMAIN}" ]] || TARGET_DDNS_RESOLVE_DOMAIN="${TARGET_DOMAIN}"
        else
            TARGET_REPORT_MODE="none"
        fi
    fi
    if [[ "${TARGET_REPORT_MODE}" == "ddns" && -z "${TARGET_DDNS_RESOLVE_DOMAIN}" ]]; then
        TARGET_DDNS_RESOLVE_DOMAIN="${TARGET_DOMAIN}"
    fi
    [[ -n "${TARGET_PO0_HOST}" ]] || return 1
    [[ -n "${TARGET_DOMAIN}" || -n "${TARGET_RESOURCE_TOKEN}" ]] || return 1
}

target_line_count() {
    local line count=0
    [[ -f "${CONFIG_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        count=$((count + 1))
    done < "${CONFIG_FILE}"
    printf '%s\n' "${count}"
}

list_targets() {
    local line idx=1 status key_label target_id domain_label mode_label
    ensure_config_file || return 1
    prune_stats_to_current_targets || true
    printf '配置文件：%s\n' "${CONFIG_FILE}"
    refresh_stats_file
    printf '统计文件：%s\n' "${STATS_FILE}"
    if [[ "$(target_line_count)" == "0" ]]; then
        printf '  (尚未添加上报目标)\n'
        return 0
    fi
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        [[ "${TARGET_ENABLED}" == "1" ]] && status="启用" || status="停用"
        domain_label="${TARGET_DOMAIN:-资源-only}"
        key_label="${TARGET_REPORT_KEY:-${TARGET_DOMAIN:-无}}"
        mode_label="${TARGET_REPORT_MODE:-none}"
        target_id="$(target_id_for "${TARGET_DOMAIN}" "${key_label}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT:-22}" "${TARGET_PO0_USER:-root}")"
        printf '  %2d) %-4s %-14s mode=%s source=%s key=%s PO0=%s@%s:%s\n' \
            "${idx}" "${status}" "${TARGET_LABEL:-未命名}" "${mode_label}" "${domain_label}" "${key_label}" "${TARGET_PO0_USER:-root}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT:-22}"
        if [[ "${TARGET_REPORT_MODE}" == "ddns" ]]; then
            printf '      DDNS 域名：%s\n' "${TARGET_DDNS_RESOLVE_DOMAIN:-${TARGET_DOMAIN}}"
            print_target_stats "${target_id}"
        else
            printf '      统计：无 DDNS 解析上报（只轮询资源任务或服务模式）\n'
        fi
        if [[ -n "${TARGET_RESOURCE_TOKEN}" ]]; then
            printf '      资源任务：已配置 Token\n'
        else
            printf '      资源任务：未配置\n'
        fi
        ((idx++))
    done < "${CONFIG_FILE}"
}

target_id_is_current() {
    local needle="$1"
    local line key_label current_id
    [[ -f "${CONFIG_FILE}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        key_label="${TARGET_REPORT_KEY:-${TARGET_DOMAIN}}"
        current_id="$(target_id_for "${TARGET_DOMAIN}" "${key_label}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT:-22}" "${TARGET_PO0_USER:-root}")"
        [[ "${current_id}" == "${needle}" ]] && return 0
    done < "${CONFIG_FILE}"
    return 1
}

prune_stats_to_current_targets() {
    local line id rest tmp
    ensure_config_file || return 1
    ensure_stats_file || return 1
    tmp="${STATS_FILE}.tmp.$$"
    printf '# target_id|success_count|fail_count|last_status|last_at|last_ip_csv|last_error\n' > "${tmp}" || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="$(trim "${line}")"
        [[ -n "${line}" && ! "${line}" == \#* ]] || continue
        IFS='|' read -r id rest <<< "${line}"
        target_id_is_current "${id}" || continue
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${STATS_FILE}"
    replace_file_from_tmp "${tmp}" "${STATS_FILE}"
}

clear_stats_interactive() {
    local answer
    ensure_stats_file || return 1
    read -r -p "确认清空本机上报统计 [y/N]: " answer
    answer="$(trim "${answer}")"
    case "${answer,,}" in
        y|yes)
            {
                printf '# target_id|success_count|fail_count|last_status|last_at|last_ip_csv|last_error\n'
            } > "${STATS_FILE}" || return 1
            chmod 600 "${STATS_FILE}" 2>/dev/null || true
            printf '已清空本机上报统计。\n'
            ;;
        *)
            printf '已取消。\n'
            ;;
    esac
}

append_target() {
    local enabled="$1"
    local label="$2"
    local domain="$3"
    local report_key="$4"
    local po0_host="$5"
    local po0_port="$6"
    local po0_user="$7"
    local po0_script="$8"
    local token="$9"
    local ssh_extra_args="${10:-}"
    local resource_token="${11:-}"
    local report_mode="${12:-auto}"
    local ddns_resolve_domain="${13:-}"
    ensure_config_file || return 1
    report_mode="$(normalize_report_mode "${report_mode}")"
    if [[ "${report_mode}" == "auto" ]]; then
        [[ -n "${ddns_resolve_domain:-${domain}}" ]] && report_mode="ddns" || report_mode="none"
    fi
    [[ -n "${ddns_resolve_domain}" ]] || ddns_resolve_domain="${domain}"
    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
        "$(sanitize_field "${enabled}")" \
        "$(sanitize_field "${label}")" \
        "$(sanitize_field "${domain}")" \
        "$(sanitize_field "${report_key}")" \
        "$(sanitize_field "${po0_host}")" \
        "$(sanitize_field "${po0_port}")" \
        "$(sanitize_field "${po0_user}")" \
        "$(sanitize_field "${po0_script}")" \
        "$(sanitize_field "${token}")" \
        "$(sanitize_field "${ssh_extra_args}")" \
        "$(sanitize_field "${resource_token}")" \
        "$(sanitize_field "${report_mode}")" \
        "$(sanitize_field "${ddns_resolve_domain}")" >> "${CONFIG_FILE}"
}

upsert_target() {
    local enabled="$1"
    local label="$2"
    local domain="$3"
    local report_key="$4"
    local po0_host="$5"
    local po0_port="$6"
    local po0_user="$7"
    local po0_script="$8"
    local token="$9"
    local ssh_extra_args="${10:-}"
    local resource_token="${11:-}"
    local report_mode="${12:-auto}"
    local ddns_resolve_domain="${13:-}"
    local tmp line found=0
    ensure_config_file || return 1
    report_mode="$(normalize_report_mode "${report_mode}")"
    if [[ "${report_mode}" == "auto" ]]; then
        [[ -n "${ddns_resolve_domain:-${domain}}" ]] && report_mode="ddns" || report_mode="none"
    fi
    [[ -n "${ddns_resolve_domain}" ]] || ddns_resolve_domain="${domain}"
    tmp="${CONFIG_FILE}.tmp.$$"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if parse_target_line "${line}"; then
            if [[ "${TARGET_DOMAIN}" == "${domain}" \
                && "${TARGET_REPORT_KEY:-${TARGET_DOMAIN}}" == "${report_key:-${domain}}" \
                && "${TARGET_PO0_HOST}" == "${po0_host}" \
                && "${TARGET_PO0_PORT:-22}" == "${po0_port:-22}" \
                && "${TARGET_PO0_USER:-root}" == "${po0_user:-root}" ]]; then
                found=1
                printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
                    "$(sanitize_field "${enabled}")" \
                    "$(sanitize_field "${label}")" \
                    "$(sanitize_field "${domain}")" \
                    "$(sanitize_field "${report_key:-${domain}}")" \
                    "$(sanitize_field "${po0_host}")" \
                    "$(sanitize_field "${po0_port:-22}")" \
                    "$(sanitize_field "${po0_user:-root}")" \
                    "$(sanitize_field "${po0_script:-${DEFAULT_PO0_SCRIPT}}")" \
                    "$(sanitize_field "${token}")" \
                    "$(sanitize_field "${ssh_extra_args}")" \
                    "$(sanitize_field "${resource_token}")" \
                    "$(sanitize_field "${report_mode}")" \
                    "$(sanitize_field "${ddns_resolve_domain}")" >> "${tmp}"
                continue
            fi
        fi
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${CONFIG_FILE}"
    if [[ "${found}" != "1" ]]; then
        printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
            "$(sanitize_field "${enabled}")" \
            "$(sanitize_field "${label}")" \
            "$(sanitize_field "${domain}")" \
            "$(sanitize_field "${report_key:-${domain}}")" \
            "$(sanitize_field "${po0_host}")" \
            "$(sanitize_field "${po0_port:-22}")" \
            "$(sanitize_field "${po0_user:-root}")" \
            "$(sanitize_field "${po0_script:-${DEFAULT_PO0_SCRIPT}}")" \
            "$(sanitize_field "${token}")" \
            "$(sanitize_field "${ssh_extra_args}")" \
            "$(sanitize_field "${resource_token}")" \
            "$(sanitize_field "${report_mode}")" \
            "$(sanitize_field "${ddns_resolve_domain}")" >> "${tmp}"
    fi
    replace_config_from_tmp "${tmp}"
}

replace_file_from_tmp() {
    local tmp="$1"
    local target="$2"
    local line
    if command -v mv >/dev/null 2>&1; then
        mv -f "${tmp}" "${target}"
        return $?
    fi
    : > "${target}" || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        printf '%s\n' "${line}" >> "${target}"
    done < "${tmp}"
    rm -f "${tmp}" 2>/dev/null || true
}

replace_config_from_tmp() {
    replace_file_from_tmp "$1" "${CONFIG_FILE}"
}

target_id_for() {
    local domain="$1"
    local report_key="$2"
    local po0_host="$3"
    local po0_port="$4"
    local po0_user="$5"
    printf '%s,%s,%s,%s,%s\n' \
        "$(sanitize_field "${domain}")" \
        "$(sanitize_field "${report_key:-${domain}}")" \
        "$(sanitize_field "${po0_host}")" \
        "$(sanitize_field "${po0_port:-22}")" \
        "$(sanitize_field "${po0_user:-root}")"
}

load_target_stats() {
    local target_id="$1"
    local line id success fail last_status last_at last_ip_csv last_error
    STAT_SUCCESS="0"
    STAT_FAIL="0"
    STAT_LAST_STATUS=""
    STAT_LAST_AT=""
    STAT_LAST_IP_CSV=""
    STAT_LAST_ERROR=""
    [[ -f "${STATS_FILE}" ]] || return 0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -n "$(trim "${line}")" && ! "$(trim "${line}")" =~ ^# ]] || continue
        IFS='|' read -r id success fail last_status last_at last_ip_csv last_error <<< "${line}"
        if [[ "${id}" == "${target_id}" ]]; then
            STAT_SUCCESS="${success:-0}"
            STAT_FAIL="${fail:-0}"
            STAT_LAST_STATUS="${last_status:-}"
            STAT_LAST_AT="${last_at:-}"
            STAT_LAST_IP_CSV="${last_ip_csv:-}"
            STAT_LAST_ERROR="${last_error:-}"
            return 0
        fi
    done < "${STATS_FILE}"
}

print_target_stats() {
    local target_id="$1"
    ensure_stats_file || return 1
    load_target_stats "${target_id}"
    if [[ -z "${STAT_LAST_STATUS}" ]]; then
        printf '      统计：尚无上报记录\n'
        return 0
    fi
    [[ "${STAT_LAST_IP_CSV}" == "无" ]] && STAT_LAST_IP_CSV=""
    [[ "${STAT_LAST_ERROR}" == "无" ]] && STAT_LAST_ERROR=""
    printf '      统计：成功=%s 失败=%s 上次=%s 状态=%s IP=%s\n' \
        "${STAT_SUCCESS}" "${STAT_FAIL}" "${STAT_LAST_AT:-未知}" "${STAT_LAST_STATUS}" "${STAT_LAST_IP_CSV:-无}"
    if [[ -n "${STAT_LAST_ERROR}" ]]; then
        printf '      错误：%s\n' "${STAT_LAST_ERROR}"
    fi
}

update_target_stats() {
    local target_id="$1"
    local status="$2"
    local ip_csv="$3"
    local error="$4"
    local tmp line id success fail last_status last_at last_ip_csv last_error found=0 now stored_ip stored_error
    ensure_stats_file || return 1
    now="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf 'unknown')"
    stored_ip="$(sanitize_field "${ip_csv}")"
    stored_error="$(sanitize_field "${error}")"
    [[ -n "${stored_ip}" ]] || stored_ip="无"
    [[ -n "${stored_error}" ]] || stored_error="无"
    tmp="${STATS_FILE}.tmp.$$"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ -z "$(trim "${line}")" || "$(trim "${line}")" =~ ^# ]]; then
            printf '%s\n' "${line}" >> "${tmp}"
            continue
        fi
        IFS='|' read -r id success fail last_status last_at last_ip_csv last_error <<< "${line}"
        if [[ "${id}" == "${target_id}" ]]; then
            found=1
            [[ "${success}" =~ ^[0-9]+$ ]] || success=0
            [[ "${fail}" =~ ^[0-9]+$ ]] || fail=0
            if [[ "${status}" == "成功" ]]; then
                ((success++))
            else
                ((fail++))
            fi
            printf '%s|%s|%s|%s|%s|%s|%s\n' \
                "${target_id}" "${success}" "${fail}" "${status}" "${now}" "${stored_ip}" "${stored_error}" >> "${tmp}"
            continue
        fi
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${STATS_FILE}"
    if [[ "${found}" != "1" ]]; then
        success=0
        fail=0
        if [[ "${status}" == "成功" ]]; then
            success=1
        else
            fail=1
        fi
        printf '%s|%s|%s|%s|%s|%s|%s\n' \
            "${target_id}" "${success}" "${fail}" "${status}" "${now}" "${stored_ip}" "${stored_error}" >> "${tmp}"
    fi
    replace_file_from_tmp "${tmp}" "${STATS_FILE}"
}

add_target_interactive() {
    local label domain report_key po0_host po0_port po0_user po0_script token ssh_extra_args resource_token report_mode ddns_resolve_domain
    ensure_config_file || return 1
    printf '\n添加 PO0 Worker 目标\n'
    report_mode="$(prompt_default "上报模式：ddns 或 none" "${REPORT_MODE:-ddns}")"
    report_mode="$(normalize_report_mode "${report_mode}")"
    [[ "${report_mode}" == "auto" ]] && report_mode="ddns"
    if [[ "${report_mode}" == "ddns" ]]; then
        ddns_resolve_domain="$(prompt_default "LAN Worker 要解析的 DDNS 域名" "${DDNS_RESOLVE_DOMAIN:-${DDNS_DOMAIN}}")"
        domain="$(prompt_default "PO0 来源 key，默认同 DDNS 域名" "${DDNS_DOMAIN:-${ddns_resolve_domain}}")"
    else
        ddns_resolve_domain=""
        domain="$(prompt_default "PO0 来源 key，可空（只做资源任务时留空）" "${DDNS_DOMAIN}")"
    fi
    po0_host="$(prompt_default "PO0 SSH 地址" "${PO0_HOST}")"
    [[ -n "${po0_host}" ]] || { printf 'PO0 SSH 地址不能为空。\n' >&2; return 1; }
    po0_port="$(prompt_default "PO0 SSH 端口" "${PO0_PORT:-22}")"
    po0_user="$(prompt_default "PO0 SSH 用户" "${PO0_USER:-root}")"
    po0_script="$(prompt_default "PO0 管理脚本路径" "${PO0_SCRIPT:-${DEFAULT_PO0_SCRIPT}}")"
    token="$(prompt_default "DDNS 来源上报 token，可空" "${DDNS_TOKEN}")"
    resource_token="$(prompt_default "资源任务 Token，可空" "${RESOURCE_TOKEN}")"
    [[ -n "${domain}" || -n "${resource_token}" ]] || {
        printf 'PO0 来源 key 和资源任务 Token 不能同时为空。\n' >&2
        return 1
    }
    [[ "${report_mode}" != "ddns" || -n "${ddns_resolve_domain}" ]] || {
        printf 'DDNS resolver 模式必须填写 --ddns-domain。\n' >&2
        return 1
    }
    label="$(prompt_default "显示名" "${domain:-resource-${po0_host}}")"
    if [[ -n "${domain}" ]]; then
        report_key="$(prompt_default "PO0 匹配 key，默认直接用来源 key" "${domain}")"
    else
        report_key=""
    fi
    ssh_extra_args="$(prompt_default "额外 SSH 参数，可空" "${SSH_EXTRA_ARGS}")"
    append_target "1" "${label}" "${domain}" "${report_key}" "${po0_host}" "${po0_port}" "${po0_user}" "${po0_script}" "${token}" "${ssh_extra_args}" "${resource_token}" "${report_mode}" "${ddns_resolve_domain}" || return 1
    printf '已添加：%s -> %s\n' "${domain:-资源-only}" "${po0_host}"
}

rewrite_targets_by_index() {
    local selected="$1"
    local mode="$2"
    local line idx=0 tmp
    ensure_config_file || return 1
    tmp="${CONFIG_FILE}.tmp.$$"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if ! parse_target_line "${line}"; then
            printf '%s\n' "${line}" >> "${tmp}"
            continue
        fi
        idx=$((idx + 1))
        if [[ "${idx}" == "${selected}" ]]; then
            if [[ "${mode}" == "delete" ]]; then
                continue
            fi
            [[ "${TARGET_ENABLED}" == "1" ]] && TARGET_ENABLED="0" || TARGET_ENABLED="1"
            printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
                "${TARGET_ENABLED}" "${TARGET_LABEL}" "${TARGET_DOMAIN}" "${TARGET_REPORT_KEY}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT}" "${TARGET_PO0_USER}" "${TARGET_PO0_SCRIPT}" "${TARGET_TOKEN}" "${TARGET_SSH_EXTRA_ARGS}" "${TARGET_RESOURCE_TOKEN}" "${TARGET_REPORT_MODE}" "${TARGET_DDNS_RESOLVE_DOMAIN}" >> "${tmp}"
            continue
        fi
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${CONFIG_FILE}"
    replace_config_from_tmp "${tmp}"
}

SELECTED_TARGET_INDEX=""

select_target_index() {
    local count choice
    count="$(target_line_count)"
    [[ "${count}" != "0" ]] || {
        printf '当前没有上报目标。\n' >&2
        return 1
    }
    list_targets
    read -r -p "请选择目标 [1-${count}]: " choice
    choice="$(trim "${choice}")"
    [[ "${choice}" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= count )) || return 1
    SELECTED_TARGET_INDEX="${choice}"
}

delete_target_interactive() {
    local idx
    select_target_index || return 1
    idx="${SELECTED_TARGET_INDEX}"
    rewrite_targets_by_index "${idx}" "delete" || return 1
    prune_stats_to_current_targets || true
    printf '已删除目标 %s。\n' "${idx}"
}

toggle_target_interactive() {
    local idx
    select_target_index || return 1
    idx="${SELECTED_TARGET_INDEX}"
    rewrite_targets_by_index "${idx}" "toggle" || return 1
    printf '已切换目标 %s 的启用状态。\n' "${idx}"
}

edit_target_interactive() {
    local selected line idx=0 tmp
    local enabled label domain report_key po0_host po0_port po0_user po0_script token ssh_extra_args resource_token report_mode ddns_resolve_domain
    select_target_index || return 1
    selected="${SELECTED_TARGET_INDEX}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        ((idx++))
        if [[ "${idx}" == "${selected}" ]]; then
            enabled="${TARGET_ENABLED}"
            label="${TARGET_LABEL}"
            domain="${TARGET_DOMAIN}"
            report_key="${TARGET_REPORT_KEY}"
            po0_host="${TARGET_PO0_HOST}"
            po0_port="${TARGET_PO0_PORT}"
            po0_user="${TARGET_PO0_USER}"
            po0_script="${TARGET_PO0_SCRIPT}"
            token="${TARGET_TOKEN}"
            ssh_extra_args="${TARGET_SSH_EXTRA_ARGS}"
            resource_token="${TARGET_RESOURCE_TOKEN}"
            report_mode="${TARGET_REPORT_MODE}"
            ddns_resolve_domain="${TARGET_DDNS_RESOLVE_DOMAIN}"
            break
        fi
    done < "${CONFIG_FILE}"
    [[ -n "${po0_host:-}" ]] || return 1

    printf '\n编辑目标；直接回车保留当前值。\n'
    label="$(prompt_default "显示名" "${label}")"
    report_mode="$(prompt_default "上报模式：ddns 或 none" "${report_mode:-ddns}")"
    report_mode="$(normalize_report_mode "${report_mode}")"
    [[ "${report_mode}" == "auto" ]] && report_mode="ddns"
    if [[ "${report_mode}" == "ddns" ]]; then
        ddns_resolve_domain="$(prompt_default "LAN Worker 要解析的 DDNS 域名" "${ddns_resolve_domain:-${domain}}")"
        domain="$(prompt_default "PO0 来源 key，默认同 DDNS 域名" "${domain:-${ddns_resolve_domain}}")"
    else
        ddns_resolve_domain=""
        domain="$(prompt_default "PO0 来源 key，可空（只做资源任务时留空）" "${domain}")"
    fi
    report_key="$(prompt_default "PO0 匹配 key" "${report_key:-${domain}}")"
    po0_host="$(prompt_default "PO0 SSH 地址" "${po0_host}")"
    po0_port="$(prompt_default "PO0 SSH 端口" "${po0_port:-22}")"
    po0_user="$(prompt_default "PO0 SSH 用户" "${po0_user:-root}")"
    po0_script="$(prompt_default "PO0 管理脚本路径" "${po0_script:-${DEFAULT_PO0_SCRIPT}}")"
    token="$(prompt_default "DDNS 来源上报 Token，可空" "${token}")"
    resource_token="$(prompt_default "资源任务 Token，可空" "${resource_token}")"
    ssh_extra_args="$(prompt_default "额外 SSH 参数，可空" "${ssh_extra_args}")"
    [[ -n "${domain}" ]] || report_key=""
    [[ -n "${po0_host}" && ( -n "${domain}" || -n "${resource_token}" ) ]] || {
        printf 'PO0 SSH 地址不能为空；PO0 来源 key 和资源任务 Token 不能同时为空。\n' >&2
        return 1
    }
    [[ "${report_mode}" != "ddns" || -n "${ddns_resolve_domain}" ]] || {
        printf 'DDNS resolver 模式必须填写 DDNS 域名。\n' >&2
        return 1
    }

    tmp="${CONFIG_FILE}.tmp.$$"
    idx=0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if ! parse_target_line "${line}"; then
            printf '%s\n' "${line}" >> "${tmp}"
            continue
        fi
        ((idx++))
        if [[ "${idx}" == "${selected}" ]]; then
            printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
                "${enabled}" "$(sanitize_field "${label}")" "$(sanitize_field "${domain}")" "$(sanitize_field "${report_key}")" \
                "$(sanitize_field "${po0_host}")" "$(sanitize_field "${po0_port}")" "$(sanitize_field "${po0_user}")" \
                "$(sanitize_field "${po0_script}")" "$(sanitize_field "${token}")" "$(sanitize_field "${ssh_extra_args}")" \
                "$(sanitize_field "${resource_token}")" "$(sanitize_field "${report_mode}")" "$(sanitize_field "${ddns_resolve_domain}")" >> "${tmp}"
            continue
        fi
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${CONFIG_FILE}"
    replace_config_from_tmp "${tmp}"
    prune_stats_to_current_targets || true
    printf '已更新目标 %s。\n' "${selected}"
}

report_once() {
    local source_key="$1"
    local report_key="$2"
    local resolve_domain="$3"
    local po0_host="$4"
    local po0_port="$5"
    local po0_user="$6"
    local po0_script="$7"
    local token="$8"
    local ssh_extra_args="${9:-}"
    local ip_csv remote_cmd target_id
    local -a ssh_args=()
    [[ -n "${source_key}" ]] || { printf '缺少 PO0 来源 key。\n' >&2; return 1; }
    [[ -n "${resolve_domain}" ]] || { printf '缺少要解析的 DDNS 域名。\n' >&2; return 1; }
    [[ -n "${po0_host}" ]] || { printf '缺少 PO0 SSH 地址。\n' >&2; return 1; }
    [[ -n "${report_key}" ]] || report_key="${source_key}"
    [[ -n "${po0_port}" ]] || po0_port="22"
    [[ -n "${po0_user}" ]] || po0_user="root"
    [[ -n "${po0_script}" ]] || po0_script="${DEFAULT_PO0_SCRIPT}"
    target_id="$(target_id_for "${source_key}" "${report_key}" "${po0_host}" "${po0_port}" "${po0_user}")"

    ip_csv="$(resolve_ddns_ipv4_csv "${resolve_domain}")" || {
        printf '解析失败：无法解析 DDNS 域名的公网 A 记录：%s\n' "${resolve_domain}" >&2
        update_target_stats "${target_id}" "失败" "" "解析失败：无法解析 DDNS 域名 ${resolve_domain}" || true
        return 1
    }

    remote_cmd="bash $(sh_quote "${po0_script}") --ddns-report $(sh_quote "${report_key}") $(sh_quote "${ip_csv}")"
    if [[ -n "${token}" ]]; then
        remote_cmd+=" $(sh_quote "${token}")"
    fi

    ssh_args+=(-p "${po0_port}")
    if [[ -n "${ssh_extra_args}" ]]; then
        read -r -a extra_args <<< "${ssh_extra_args}"
        ssh_args+=("${extra_args[@]}")
    fi

    printf '上报：DDNS %s -> %s -> %s@%s:%s，来源=%s\n' "${resolve_domain}" "${ip_csv}" "${po0_user}" "${po0_host}" "${po0_port}" "${report_key}"
    if ! ssh "${ssh_args[@]}" "${po0_user}@${po0_host}" "${remote_cmd}"; then
        printf '上报失败：%s -> %s\n' "${source_key}" "${po0_host}" >&2
        update_target_stats "${target_id}" "失败" "${ip_csv}" "SSH 或 PO0 上报命令失败" || true
        return 1
    fi
    update_target_stats "${target_id}" "成功" "${ip_csv}" "" || true
}

remote_manager_call() {
    local host="$1"
    local port="$2"
    local user="$3"
    local script="$4"
    local extra="$5"
    shift 5
    local remote_cmd arg
    local -a ssh_args=(-p "${port:-22}")
    local -a extra_args=()
    [[ -n "${user}" ]] || user="root"
    [[ -n "${script}" ]] || script="${DEFAULT_PO0_SCRIPT}"
    if [[ -n "${extra}" ]]; then
        read -r -a extra_args <<< "${extra}"
        ssh_args+=("${extra_args[@]}")
    fi
    remote_cmd="bash $(sh_quote "${script}")"
    for arg in "$@"; do
        remote_cmd+=" $(sh_quote "${arg}")"
    done
    ssh "${ssh_args[@]}" "${user}@${host}" "${remote_cmd}"
}

probe_ok() {
    printf '[OK] %s\n' "$1"
}

probe_warn() {
    printf '[WARN] %s\n' "$1" >&2
}

probe_fail() {
    printf '[FAIL] %s\n' "$1" >&2
}

probe_client_dependencies() {
    local failed=0
    have_cmd ssh || { probe_fail "缺少 ssh，无法连接 PO0。"; failed=1; }
    if [[ -n "${RESOURCE_TOKEN}" ]]; then
        have_cmd scp || { probe_fail "缺少 scp，无法回传资源文件。"; failed=1; }
        have_cmd tar || { probe_fail "缺少 tar，无法构建/解包 iplist 资源。"; failed=1; }
        have_cmd grep || { probe_fail "缺少 grep，无法解析 iplist 清单。"; failed=1; }
        have_cmd sort || { probe_fail "缺少 sort，无法整理 iplist 清单。"; failed=1; }
        have_cmd wc || { probe_fail "缺少 wc，无法计算资源文件大小。"; failed=1; }
        if ! have_cmd sha256sum && ! have_cmd shasum; then
            probe_fail "缺少 sha256sum 或 shasum，无法计算资源文件 SHA-256。"
            failed=1
        fi
        if ! have_cmd curl && ! have_cmd wget; then
            probe_fail "缺少 curl 或 wget，无法下载资源文件。"
            failed=1
        fi
    fi
    if [[ -n "${DDNS_RESOLVE_DOMAIN}" || "${REPORT_MODE}" == "ddns" ]]; then
        if ! have_cmd getent && ! have_cmd dig && ! have_cmd host && ! have_cmd nslookup; then
            probe_fail "缺少 getent/dig/host/nslookup，无法解析 DDNS 域名。"
            failed=1
        fi
    fi
    [[ "${failed}" == "0" ]] && probe_ok "本机依赖检查通过"
    return "${failed}"
}

probe_worker_target() {
    local failed=0 ip_csv response key mode resolve_domain
    key="${REPORT_KEY:-${DDNS_DOMAIN}}"
    mode="$(normalize_report_mode "${REPORT_MODE}")"
    [[ "${mode}" == "auto" && -n "${DDNS_RESOLVE_DOMAIN}" ]] && mode="ddns"
    [[ "${mode}" == "auto" ]] && mode="none"
    resolve_domain="${DDNS_RESOLVE_DOMAIN}"
    [[ -n "${PO0_HOST}" ]] || { probe_fail "缺少 --po0-host。"; return 1; }
    [[ -n "${PO0_PORT}" ]] || PO0_PORT="22"
    [[ -n "${PO0_USER}" ]] || PO0_USER="root"
    [[ -n "${PO0_SCRIPT}" ]] || PO0_SCRIPT="${DEFAULT_PO0_SCRIPT}"
    probe_client_dependencies || failed=1

    if [[ "${mode}" == "ddns" && -n "${resolve_domain}" ]]; then
        if ip_csv="$(resolve_ddns_ipv4_csv "${resolve_domain}")"; then
            probe_ok "DDNS 解析结果：${resolve_domain} -> ${ip_csv}；将作为 ${key} 上报"
        else
            probe_fail "无法解析 DDNS 域名的公网 A 记录：${resolve_domain}"
            failed=1
        fi
    else
        probe_warn "未配置 DDNS resolver，将只检测 PO0 连接和资源任务。"
    fi

    if response="$(remote_manager_call "${PO0_HOST}" "${PO0_PORT}" "${PO0_USER}" "${PO0_SCRIPT}" "${SSH_EXTRA_ARGS}" --help 2>&1)"; then
        probe_ok "SSH 可达，PO0 管理脚本可调用：${PO0_USER}@${PO0_HOST}:${PO0_PORT}"
    else
        probe_fail "SSH 或 PO0 管理脚本检查失败：${response}"
        failed=1
    fi

    if [[ "${mode}" == "ddns" && -n "${DDNS_DOMAIN}" ]]; then
        if response="$(remote_manager_call "${PO0_HOST}" "${PO0_PORT}" "${PO0_USER}" "${PO0_SCRIPT}" "${SSH_EXTRA_ARGS}" --ddns-report-check "${key}" "${DDNS_TOKEN}" 2>&1)"; then
            probe_ok "DDNS 上报权限检查通过：${response}"
        else
            probe_fail "DDNS 上报权限检查失败：${response}"
            failed=1
        fi
    fi

    if [[ -n "${RESOURCE_TOKEN}" ]]; then
        if response="$(remote_manager_call "${PO0_HOST}" "${PO0_PORT}" "${PO0_USER}" "${PO0_SCRIPT}" "${SSH_EXTRA_ARGS}" --resource-task-ping "${RESOURCE_TOKEN}" 2>&1)"; then
            probe_ok "资源任务权限检查通过：${response}"
        else
            probe_fail "资源任务权限检查失败：${response}"
            failed=1
        fi
    else
        probe_warn "未配置资源任务 Token。"
    fi

    [[ "${failed}" == "0" ]]
}

run_config_targets() {
    local line ok=0 fail=0 skipped=0 no_ddns=0
    ensure_config_file || return 1
    prune_stats_to_current_targets || true
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        if [[ "${TARGET_ENABLED}" != "1" ]]; then
            ((skipped++))
            continue
        fi
        if [[ "${TARGET_REPORT_MODE}" != "ddns" || -z "${TARGET_DOMAIN}" || -z "${TARGET_DDNS_RESOLVE_DOMAIN}" ]]; then
            ((no_ddns++))
            continue
        fi
        if report_once "${TARGET_DOMAIN}" "${TARGET_REPORT_KEY:-${TARGET_DOMAIN}}" "${TARGET_DDNS_RESOLVE_DOMAIN}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT}" "${TARGET_PO0_USER}" "${TARGET_PO0_SCRIPT}" "${TARGET_TOKEN}" "${TARGET_SSH_EXTRA_ARGS}"; then
            ((ok++))
        else
            ((fail++))
        fi
    done < "${CONFIG_FILE}"
    printf 'DDNS resolver 上报完成：成功 %s，失败 %s，停用跳过 %s，无 DDNS 任务跳过 %s。\n' "${ok}" "${fail}" "${skipped}" "${no_ddns}"
    [[ "${fail}" == "0" ]]
}

resource_endpoint_id_for() {
    printf '%s,%s,%s\n' \
        "$(sanitize_field "$1")" \
        "$(sanitize_field "${2:-22}")" \
        "$(sanitize_field "${3:-root}")"
}

update_resource_stats() {
    local endpoint_id="$1" task_id="$2" task_type="$3" status="$4" message="$5"
    local tmp line id success fail last_task last_type last_status last_at last_message found=0 now
    ensure_resource_stats_file || return 1
    now="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf 'unknown')"
    tmp="${RESOURCE_STATS_FILE}.tmp.$$"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ -z "$(trim "${line}")" || "$(trim "${line}")" == \#* ]]; then
            printf '%s\n' "${line}" >> "${tmp}"
            continue
        fi
        IFS='|' read -r id success fail last_task last_type last_status last_at last_message <<< "${line}"
        if [[ "${id}" == "${endpoint_id}" ]]; then
            found=1
            [[ "${success}" =~ ^[0-9]+$ ]] || success=0
            [[ "${fail}" =~ ^[0-9]+$ ]] || fail=0
            case "${status}" in
                成功) ((success++)) ;;
                无任务) ;;
                *) ((fail++)) ;;
            esac
            printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
                "${endpoint_id}" "${success}" "${fail}" "${task_id:-无}" "${task_type:-无}" "${status}" "${now}" "$(sanitize_field "${message}")" >> "${tmp}"
            continue
        fi
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${RESOURCE_STATS_FILE}"
    if [[ "${found}" == "0" ]]; then
        success=0
        fail=0
        case "${status}" in
            成功) success=1 ;;
            无任务) ;;
            *) fail=1 ;;
        esac
        printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
            "${endpoint_id}" "${success}" "${fail}" "${task_id:-无}" "${task_type:-无}" "${status}" "${now}" "$(sanitize_field "${message}")" >> "${tmp}"
    fi
    replace_file_from_tmp "${tmp}" "${RESOURCE_STATS_FILE}"
}

list_resource_stats() {
    local line endpoint success fail task type status at message count=0
    ensure_resource_stats_file || return 1
    printf '资源任务统计：%s\n' "${RESOURCE_STATS_FILE}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -n "$(trim "${line}")" && "$(trim "${line}")" != \#* ]] || continue
        IFS='|' read -r endpoint success fail task type status at message <<< "${line}"
        ((count++))
        printf '  %s 成功=%s 失败=%s 上次=%s 任务=%s/%s 时间=%s\n' \
            "${endpoint}" "${success:-0}" "${fail:-0}" "${status:-未知}" "${task:-无}" "${type:-无}" "${at:-未知}"
        [[ -n "${message}" ]] && printf '      %s\n' "${message}"
    done < "${RESOURCE_STATS_FILE}"
    [[ "${count}" -gt 0 ]] || printf '  (尚无资源任务记录)\n'
}

fetch_to_file() {
    local url="$1" output="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 --connect-timeout 15 --max-time 180 "${url}" -o "${output}"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=180 "${url}" -O "${output}"
    else
        printf '系统缺少 curl 或 wget。\n' >&2
        return 1
    fi
}

build_iplist_resource() {
    local output="$1"
    local work doc urls url rel downloaded=0
    work="$(mktemp -d "${TMPDIR:-/tmp}/po0-iplist-worker.XXXXXX")" || return 1
    doc="${work}/docs/cncity.md"
    urls="${work}/urls.txt"
    mkdir -p "${work}/docs" "${work}/data/cncity" || {
        rm -rf -- "${work}"
        return 1
    }
    fetch_to_file "https://raw.githubusercontent.com/metowolf/iplist/refs/heads/master/docs/cncity.md" "${doc}" || {
        rm -rf -- "${work}"
        return 1
    }
    grep -Eo 'https?://[^|[:space:]]+\.txt' "${doc}" | sort -u > "${urls}"
    [[ -s "${urls}" ]] || {
        rm -rf -- "${work}"
        return 1
    }
    while IFS= read -r url; do
        case "${url}" in
            */iplist/data/cncity/*.txt)
                rel="data/cncity/${url#*/iplist/data/cncity/}"
                ;;
            */data/cncity/*.txt)
                rel="data/cncity/${url#*/data/cncity/}"
                ;;
            *)
                continue
                ;;
        esac
        printf '下载：%s\n' "${rel}"
        fetch_to_file "${url}" "${work}/${rel}" || {
            rm -rf -- "${work}"
            return 1
        }
        ((downloaded++))
    done < "${urls}"
    [[ "${downloaded}" -gt 0 ]] || {
        rm -rf -- "${work}"
        return 1
    }
    tar -czf "${output}" -C "${work}" docs data || {
        rm -rf -- "${work}"
        return 1
    }
    rm -rf -- "${work}"
}

sha256_file() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${file}" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "${file}" | awk '{print $1}'
    else
        return 1
    fi
}

report_resource_failure() {
    local task_id="$1" worker_id="$2" reason="$3" host="$4" port="$5" user="$6" script="$7" token="$8" extra="$9"
    local remote_cmd
    local -a ssh_args=(-p "${port}")
    local -a extra_args=()
    if [[ -n "${extra}" ]]; then
        read -r -a extra_args <<< "${extra}"
        ssh_args+=("${extra_args[@]}")
    fi
    remote_cmd="bash $(sh_quote "${script}") --resource-task-fail $(sh_quote "${task_id}") $(sh_quote "${worker_id}") $(sh_quote "${reason}") $(sh_quote "${token}")"
    ssh "${ssh_args[@]}" "${user}@${host}" "${remote_cmd}" >/dev/null 2>&1 || true
}

run_resource_endpoint() {
    local host="$1" port="$2" user="$3" script="$4" token="$5" extra="$6"
    local worker_id endpoint_id remote_cmd response protocol task_id task_type upload_path work output sha size complete_response reason=""
    local -a ssh_args=(-p "${port}")
    local -a scp_args=(-P "${port}")
    local -a extra_args=()
    worker_id="$(sanitize_field "${WORKER_ID}")"
    worker_id="${worker_id// /_}"
    endpoint_id="$(resource_endpoint_id_for "${host}" "${port}" "${user}")"
    if [[ -n "${extra}" ]]; then
        read -r -a extra_args <<< "${extra}"
        ssh_args+=("${extra_args[@]}")
        scp_args+=("${extra_args[@]}")
    fi
    remote_cmd="bash $(sh_quote "${script}") --resource-task-claim $(sh_quote "${worker_id}") $(sh_quote "${token}")"
    if ! response="$(ssh "${ssh_args[@]}" "${user}@${host}" "${remote_cmd}" 2>&1)"; then
        printf '资源任务查询失败：%s@%s:%s\n' "${user}" "${host}" "${port}" >&2
        update_resource_stats "${endpoint_id}" "" "" "查询失败" "${response}" || true
        return 1
    fi
    protocol="$(printf '%s\n' "${response}" | grep -E '^(TASK|NO_TASK|ERROR)(\||$)' | tail -n 1)"
    case "${protocol}" in
        NO_TASK)
            printf '资源任务：%s 暂无任务。\n' "${host}"
            update_resource_stats "${endpoint_id}" "" "" "无任务" "PO0 当前没有等待任务" || true
            return 0
            ;;
        ERROR\|*)
            printf '资源任务查询被拒绝：%s\n' "${protocol#ERROR|}" >&2
            update_resource_stats "${endpoint_id}" "" "" "查询失败" "${protocol#ERROR|}" || true
            return 1
            ;;
        TASK\|*)
            IFS='|' read -r _ task_id task_type upload_path <<< "${protocol}"
            ;;
        *)
            printf 'PO0 返回了无法识别的任务响应：%s\n' "${response}" >&2
            update_resource_stats "${endpoint_id}" "" "" "查询失败" "无法识别 PO0 响应" || true
            return 1
            ;;
    esac
    work="$(mktemp -d "${TMPDIR:-/tmp}/po0-resource-task.XXXXXX")" || return 1
    case "${task_type}" in
        iplist)
            output="${work}/iplist.tar.gz"
            printf '执行资源任务 %s：构建 iplist.tar.gz\n' "${task_id}"
            build_iplist_resource "${output}" || reason="构建 iplist.tar.gz 失败"
            ;;
        ipdb)
            output="${work}/qqwry.ipdb"
            printf '执行资源任务 %s：下载 qqwry.ipdb\n' "${task_id}"
            fetch_to_file "${IPDB_DOWNLOAD_URL}" "${output}" || reason="下载 qqwry.ipdb 失败"
            if [[ -z "${reason}" ]]; then
                size="$(wc -c < "${output}" | tr -d '[:space:]')"
                [[ "${size}" =~ ^[0-9]+$ && "${size}" -ge 102400 ]] || reason="qqwry.ipdb 文件过小"
            fi
            ;;
        *)
            reason="PO0 下发了不支持的任务类型"
            ;;
    esac
    if [[ -n "${reason}" ]]; then
        report_resource_failure "${task_id}" "${worker_id}" "${reason}" "${host}" "${port}" "${user}" "${script}" "${token}" "${extra}"
        update_resource_stats "${endpoint_id}" "${task_id}" "${task_type}" "失败" "${reason}" || true
        rm -rf -- "${work}"
        return 1
    fi
    sha="$(sha256_file "${output}")" || reason="本机缺少 SHA-256 工具"
    size="$(wc -c < "${output}" | tr -d '[:space:]')"
    if [[ -n "${reason}" ]]; then
        report_resource_failure "${task_id}" "${worker_id}" "${reason}" "${host}" "${port}" "${user}" "${script}" "${token}" "${extra}"
        update_resource_stats "${endpoint_id}" "${task_id}" "${task_type}" "失败" "${reason}" || true
        rm -rf -- "${work}"
        return 1
    fi
    if ! scp "${scp_args[@]}" "${output}" "${user}@${host}:${upload_path}"; then
        reason="SCP 回传文件失败"
        report_resource_failure "${task_id}" "${worker_id}" "${reason}" "${host}" "${port}" "${user}" "${script}" "${token}" "${extra}"
        update_resource_stats "${endpoint_id}" "${task_id}" "${task_type}" "失败" "${reason}" || true
        rm -rf -- "${work}"
        return 1
    fi
    remote_cmd="bash $(sh_quote "${script}") --resource-task-complete $(sh_quote "${task_id}") $(sh_quote "${worker_id}") $(sh_quote "${sha}") $(sh_quote "${size}") $(sh_quote "${token}")"
    if ! complete_response="$(ssh "${ssh_args[@]}" "${user}@${host}" "${remote_cmd}" 2>&1)"; then
        reason="PO0 校验或导入失败：${complete_response}"
        report_resource_failure "${task_id}" "${worker_id}" "${reason}" "${host}" "${port}" "${user}" "${script}" "${token}" "${extra}"
        update_resource_stats "${endpoint_id}" "${task_id}" "${task_type}" "失败" "${reason}" || true
        rm -rf -- "${work}"
        printf '%s\n' "${reason}" >&2
        return 1
    fi
    if [[ "${complete_response}" != *"OK|"* ]]; then
        reason="PO0 返回了无法识别的完成响应：${complete_response}"
        report_resource_failure "${task_id}" "${worker_id}" "${reason}" "${host}" "${port}" "${user}" "${script}" "${token}" "${extra}"
        update_resource_stats "${endpoint_id}" "${task_id}" "${task_type}" "失败" "${reason}" || true
        rm -rf -- "${work}"
        printf '%s\n' "${reason}" >&2
        return 1
    fi
    update_resource_stats "${endpoint_id}" "${task_id}" "${task_type}" "成功" "${complete_response##*OK|}" || true
    rm -rf -- "${work}"
    printf '资源任务完成：%s\n' "${complete_response##*OK|}"
}

run_resource_targets() {
    local line endpoint_key seen=";" ok=0 fail=0 skipped=0
    ensure_config_file || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        [[ "${TARGET_ENABLED}" == "1" ]] || continue
        if [[ -z "${TARGET_RESOURCE_TOKEN}" ]]; then
            ((skipped++))
            continue
        fi
        endpoint_key="${TARGET_PO0_USER:-root}@${TARGET_PO0_HOST}:${TARGET_PO0_PORT:-22}:${TARGET_PO0_SCRIPT}:${TARGET_RESOURCE_TOKEN}"
        [[ "${seen}" == *";${endpoint_key};"* ]] && continue
        seen+="${endpoint_key};"
        if run_resource_endpoint "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT:-22}" "${TARGET_PO0_USER:-root}" "${TARGET_PO0_SCRIPT:-${DEFAULT_PO0_SCRIPT}}" "${TARGET_RESOURCE_TOKEN}" "${TARGET_SSH_EXTRA_ARGS}"; then
            ((ok++))
        else
            ((fail++))
        fi
    done < "${CONFIG_FILE}"
    printf '资源任务轮询完成：成功/无任务 %s，失败 %s，未配置 Token 跳过 %s。\n' "${ok}" "${fail}" "${skipped}"
    [[ "${fail}" == "0" ]]
}

run_all_client_jobs() {
    local failed=0
    run_config_targets || failed=1
    run_resource_targets || failed=1
    return "${failed}"
}

probe_webauth_target() {
    local failed=0 response
    [[ -n "${PO0_HOST}" ]] || { probe_fail "缺少 --po0-host。"; return 1; }
    [[ -n "${WEBAUTH_TOKEN}" ]] || { probe_fail "缺少 --webauth-token。"; return 1; }
    have_cmd ssh || { probe_fail "缺少 ssh。"; failed=1; }
    if ! have_cmd python3 && ! have_cmd python; then
        probe_fail "缺少 python3/python，无法运行 WebAuth 本地 HTTP 服务。"
        failed=1
    fi
    if response="$(remote_manager_call "${PO0_HOST}" "${PO0_PORT}" "${PO0_USER}" "${PO0_SCRIPT}" "${SSH_EXTRA_ARGS}" --webauth-report-check "${WEBAUTH_SOURCE}" "${WEBAUTH_TOKEN}" 2>&1)"; then
        probe_ok "WebAuth 上报权限检查通过：${response}"
    else
        probe_fail "WebAuth 上报权限检查失败：${response}"
        failed=1
    fi
    return "${failed}"
}

run_webauth_server() {
    local py listen_host listen_port extra_json
    [[ -n "${PO0_HOST}" ]] || { printf '缺少 --po0-host。\n' >&2; return 1; }
    [[ -n "${WEBAUTH_TOKEN}" ]] || { printf '缺少 --webauth-token。\n' >&2; return 1; }
    if have_cmd python3; then
        py="python3"
    elif have_cmd python; then
        py="python"
    else
        printf '缺少 python3/python，无法运行 WebAuth server。\n' >&2
        return 1
    fi
    listen_host="${WEBAUTH_LISTEN%:*}"
    listen_port="${WEBAUTH_LISTEN##*:}"
    [[ -n "${listen_host}" && "${listen_host}" != "${WEBAUTH_LISTEN}" ]] || listen_host="127.0.0.1"
    [[ "${listen_port}" =~ ^[0-9]+$ ]] || listen_port="8787"
    export PO0_HOST PO0_PORT PO0_USER PO0_SCRIPT SSH_EXTRA_ARGS WEBAUTH_SOURCE WEBAUTH_TOKEN WEBAUTH_TTL_SECONDS
    printf 'WebAuth server listening on %s:%s；PO0 不开放 HTTP。\n' "${listen_host}" "${listen_port}"
    "${py}" - "${listen_host}" "${listen_port}" <<'PY'
import http.server
import os
import re
import shlex
import socketserver
import subprocess
import sys
import time

listen_host, listen_port = sys.argv[1], int(sys.argv[2])

def is_public_ipv4(ip):
    m = re.match(r"^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$", ip or "")
    if not m:
        return False
    o = [int(x) for x in m.groups()]
    if any(x < 0 or x > 255 for x in o):
        return False
    if o[0] in (0, 10, 127) or o[0] >= 224:
        return False
    if o[0] == 100 and 64 <= o[1] <= 127:
        return False
    if o[0] == 169 and o[1] == 254:
        return False
    if o[0] == 172 and 16 <= o[1] <= 31:
        return False
    if o[0] == 192 and o[1] == 168:
        return False
    return True

def env(name, default=""):
    return os.environ.get(name, default)

def report(ip, identity, note):
    host = env("PO0_HOST")
    port = env("PO0_PORT", "22")
    user = env("PO0_USER", "root") or "root"
    script = env("PO0_SCRIPT", "/root/nftables-relay-manager.sh")
    source = env("WEBAUTH_SOURCE", "cf-access")
    token = env("WEBAUTH_TOKEN")
    ttl = int(env("WEBAUTH_TTL_SECONDS", "3600") or "3600")
    expires_at = str(int(time.time()) + max(60, ttl))
    remote = " ".join([
        "bash",
        shlex.quote(script),
        "--webauth-report",
        shlex.quote(source),
        shlex.quote(ip),
        shlex.quote(identity or "unknown"),
        shlex.quote(expires_at),
        shlex.quote(token),
        shlex.quote(note or "lan-webauth"),
    ])
    cmd = ["ssh", "-p", port]
    extra = env("SSH_EXTRA_ARGS")
    if extra:
        cmd.extend(shlex.split(extra))
    cmd.extend([f"{user}@{host}", remote])
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/health"):
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK\n")
            return
        ip = self.headers.get("CF-Connecting-IP") or self.headers.get("X-Real-IP") or ""
        if not ip and self.headers.get("X-Forwarded-For"):
            ip = self.headers.get("X-Forwarded-For").split(",", 1)[0].strip()
        if not ip:
            ip = self.client_address[0]
        identity = (
            self.headers.get("Cf-Access-Authenticated-User-Email")
            or self.headers.get("CF-Access-Authenticated-User-Email")
            or self.headers.get("X-Forwarded-User")
            or "unknown"
        )
        if not is_public_ipv4(ip):
            self.send_response(400)
            self.end_headers()
            self.wfile.write(f"invalid public ipv4: {ip}\n".encode())
            return
        try:
            result = report(ip, identity, "cf-access")
        except Exception as exc:
            self.send_response(502)
            self.end_headers()
            self.wfile.write(f"report failed: {exc}\n".encode())
            return
        if result.returncode == 0:
            self.send_response(200)
            self.end_headers()
            self.wfile.write((result.stdout or f"OK {ip}\n").encode())
        else:
            self.send_response(502)
            self.end_headers()
            self.wfile.write((result.stderr or result.stdout or "report failed\n").encode())

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

with socketserver.ThreadingTCPServer((listen_host, listen_port), Handler) as httpd:
    httpd.serve_forever()
PY
}

install_webauth_service() {
    local script_path unit name="po0-lan-webauth.service"
    [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]] || {
        printf '安装 systemd 服务需要 root。\n' >&2
        return 1
    }
    command -v systemctl >/dev/null 2>&1 || {
        printf '当前系统没有 systemctl，无法安装服务。\n' >&2
        return 1
    }
    script_path="$(ensure_persistent_script)" || return 1
    unit="/etc/systemd/system/${name}"
    cat > "${unit}" <<EOF
[Unit]
Description=PO0 LAN WebAuth client reporter
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/env bash $(sh_quote "${script_path}") --webauth-server --listen $(sh_quote "${WEBAUTH_LISTEN}") --po0-host $(sh_quote "${PO0_HOST}") --po0-port $(sh_quote "${PO0_PORT}") --po0-user $(sh_quote "${PO0_USER}") --po0-script $(sh_quote "${PO0_SCRIPT}") --webauth-source $(sh_quote "${WEBAUTH_SOURCE}") --webauth-token $(sh_quote "${WEBAUTH_TOKEN}") --webauth-ttl $(sh_quote "${WEBAUTH_TTL_SECONDS}")
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload || return 1
    systemctl enable --now "${name}" || return 1
    printf '已安装并启动 WebAuth 服务：%s\n' "${name}"
}

probe_self_report_target() {
    local response failed=0
    [[ -n "${PO0_HOST}" ]] || { probe_fail "缺少 --po0-host。"; return 1; }
    [[ -n "${CLIENT_IP_TOKEN}" ]] || { probe_fail "缺少 --client-ip-token。"; return 1; }
    have_cmd ssh || { probe_fail "缺少 ssh，无法连接 PO0。"; failed=1; }
    if have_cmd python3 || have_cmd python; then
        probe_ok "Python 可用，可运行 self-report server"
    else
        probe_fail "缺少 python3/python，无法运行 self-report server。"
        failed=1
    fi
    if response="$(remote_manager_call "${PO0_HOST}" "${PO0_PORT}" "${PO0_USER}" "${PO0_SCRIPT}" "${SSH_EXTRA_ARGS}" --client-ip-report-check "${SELF_REPORT_SOURCE}" "${CLIENT_IP_TOKEN}" 2>&1)"; then
        probe_ok "Client IP 上报权限检查通过：${response}"
    else
        probe_fail "Client IP 上报权限检查失败：${response}"
        failed=1
    fi
    [[ "${failed}" == "0" ]]
}

run_self_report_server() {
    local py listen_host listen_port
    [[ -n "${PO0_HOST}" ]] || { printf '缺少 --po0-host。\n' >&2; return 1; }
    [[ -n "${CLIENT_IP_TOKEN}" ]] || { printf '缺少 --client-ip-token。\n' >&2; return 1; }
    if have_cmd python3; then
        py="python3"
    elif have_cmd python; then
        py="python"
    else
        printf '缺少 python3/python，无法运行 self-report server。\n' >&2
        return 1
    fi
    listen_host="${SELF_REPORT_LISTEN%:*}"
    listen_port="${SELF_REPORT_LISTEN##*:}"
    [[ -n "${listen_host}" && "${listen_host}" != "${SELF_REPORT_LISTEN}" ]] || listen_host="127.0.0.1"
    [[ "${listen_port}" =~ ^[0-9]+$ ]] || listen_port="8788"
    export PO0_HOST PO0_PORT PO0_USER PO0_SCRIPT SSH_EXTRA_ARGS SELF_REPORT_SOURCE CLIENT_IP_TOKEN SELF_REPORT_SECRET SELF_REPORT_TTL_SECONDS
    printf 'Self-report server listening on %s:%s；访问设备 -> LAN Worker -> SSH -> PO0。\n' "${listen_host}" "${listen_port}"
    "${py}" - "${listen_host}" "${listen_port}" <<'PY'
import http.server
import os
import re
import shlex
import socketserver
import subprocess
import sys
import urllib.parse

listen_host, listen_port = sys.argv[1], int(sys.argv[2])

def is_public_ipv4(ip):
    m = re.match(r"^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$", ip or "")
    if not m:
        return False
    o = [int(x) for x in m.groups()]
    if any(x < 0 or x > 255 for x in o):
        return False
    if o[0] in (0, 10, 127) or o[0] >= 224:
        return False
    if o[0] == 100 and 64 <= o[1] <= 127:
        return False
    if o[0] == 169 and o[1] == 254:
        return False
    if o[0] == 172 and 16 <= o[1] <= 31:
        return False
    if o[0] == 192 and o[1] == 168:
        return False
    return True

def env(name, default=""):
    return os.environ.get(name, default)

def first(values, default=""):
    for value in values:
        if value:
            return value
    return default

def bearer(auth):
    if not auth:
        return ""
    parts = auth.split(None, 1)
    if len(parts) == 2 and parts[0].lower() == "bearer":
        return parts[1].strip()
    return ""

def parse_request(handler):
    parsed = urllib.parse.urlparse(handler.path)
    params = {k: v[-1] for k, v in urllib.parse.parse_qs(parsed.query).items()}
    if handler.command == "POST":
        length = int(handler.headers.get("Content-Length") or "0")
        if length:
            body = handler.rfile.read(length).decode("utf-8", "replace")
            params.update({k: v[-1] for k, v in urllib.parse.parse_qs(body).items()})
    return parsed.path, params

def report(ip, identity, source):
    host = env("PO0_HOST")
    port = env("PO0_PORT", "22")
    user = env("PO0_USER", "root") or "root"
    script = env("PO0_SCRIPT", "/root/nftables-relay-manager.sh")
    source = source or env("SELF_REPORT_SOURCE", "self-report")
    token = env("CLIENT_IP_TOKEN")
    ttl = env("SELF_REPORT_TTL_SECONDS", "3600") or "3600"
    remote = " ".join([
        "bash",
        shlex.quote(script),
        "--client-ip-report",
        shlex.quote(source),
        shlex.quote(ip),
        shlex.quote(token),
        shlex.quote(identity or "self-report"),
        shlex.quote(ttl),
    ])
    cmd = ["ssh", "-p", port]
    extra = env("SSH_EXTRA_ARGS")
    if extra:
        cmd.extend(shlex.split(extra))
    cmd.extend([f"{user}@{host}", remote])
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.handle_report()

    def do_POST(self):
        self.handle_report()

    def handle_report(self):
        path, params = parse_request(self)
        if path.startswith("/health"):
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK\n")
            return

        secret = env("SELF_REPORT_SECRET")
        supplied = first([
            params.get("token"),
            self.headers.get("X-PO0-Token"),
            bearer(self.headers.get("Authorization")),
        ])
        if secret and supplied != secret:
            self.send_response(401)
            self.end_headers()
            self.wfile.write(b"unauthorized\n")
            return

        ip = first([
            params.get("ip"),
            self.headers.get("X-PO0-Client-IP"),
            self.headers.get("CF-Connecting-IP"),
            self.headers.get("X-Real-IP"),
            (self.headers.get("X-Forwarded-For") or "").split(",", 1)[0].strip(),
            self.client_address[0],
        ])
        source = first([
            params.get("source"),
            params.get("source_id"),
            env("SELF_REPORT_SOURCE", "self-report"),
        ])
        identity = first([
            params.get("identity"),
            self.headers.get("Cf-Access-Authenticated-User-Email"),
            self.headers.get("CF-Access-Authenticated-User-Email"),
            self.headers.get("X-Forwarded-User"),
            "self-report",
        ])

        if not is_public_ipv4(ip):
            self.send_response(400)
            self.end_headers()
            self.wfile.write(f"invalid public ipv4: {ip}\n".encode())
            return
        try:
            result = report(ip, identity, source)
        except Exception as exc:
            self.send_response(502)
            self.end_headers()
            self.wfile.write(f"report failed: {exc}\n".encode())
            return
        if result.returncode == 0:
            self.send_response(200)
            self.end_headers()
            self.wfile.write((result.stdout or f"OK {ip}\n").encode())
        else:
            self.send_response(502)
            self.end_headers()
            self.wfile.write((result.stderr or result.stdout or "report failed\n").encode())

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

with socketserver.ThreadingTCPServer((listen_host, listen_port), Handler) as httpd:
    httpd.serve_forever()
PY
}

install_self_report_service() {
    local script_path unit name="po0-lan-self-report.service"
    [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]] || {
        printf '安装 systemd 服务需要 root。\n' >&2
        return 1
    }
    command -v systemctl >/dev/null 2>&1 || {
        printf '当前系统没有 systemctl，无法安装服务。\n' >&2
        return 1
    }
    script_path="$(ensure_persistent_script)" || return 1
    unit="/etc/systemd/system/${name}"
    cat > "${unit}" <<EOF
[Unit]
Description=PO0 LAN self-report receiver
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/env bash $(sh_quote "${script_path}") --self-report-server --self-report-listen $(sh_quote "${SELF_REPORT_LISTEN}") --po0-host $(sh_quote "${PO0_HOST}") --po0-port $(sh_quote "${PO0_PORT}") --po0-user $(sh_quote "${PO0_USER}") --po0-script $(sh_quote "${PO0_SCRIPT}") --self-report-source $(sh_quote "${SELF_REPORT_SOURCE}") --client-ip-token $(sh_quote "${CLIENT_IP_TOKEN}") --self-report-secret $(sh_quote "${SELF_REPORT_SECRET}") --self-report-ttl $(sh_quote "${SELF_REPORT_TTL_SECONDS}")
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload || return 1
    systemctl enable --now "${name}" || return 1
    printf '已安装并启动 Self-report 服务：%s\n' "${name}"
}

print_cron_example() {
    local minutes="$1"
    local script_path
    [[ "${minutes}" =~ ^[0-9]+$ && "${minutes}" -ge 1 && "${minutes}" -le 59 ]] || minutes="5"
    script_path="$(script_self_path)"
    printf '%s\n' \
        "cron 示例（每 ${minutes} 分钟执行 DDNS 解析上报并轮询资源任务）：" \
        "*/${minutes} * * * * bash $(sh_quote "${script_path}") --config $(sh_quote "${CONFIG_FILE}") --run >/tmp/po0-lan-client.log 2>&1"
}

default_install_path() {
    if [[ -n "${INSTALL_PATH}" ]]; then
        printf '%s\n' "${INSTALL_PATH}"
    elif [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]]; then
        printf '%s\n' "/usr/local/sbin/po0-lan-client"
    elif [[ -n "${HOME:-}" ]]; then
        printf '%s\n' "${HOME}/.local/bin/po0-lan-client"
    else
        printf '%s\n' "./po0-lan-client"
    fi
}

script_source_path() {
    local script="${BASH_SOURCE[0]}"
    if [[ "${script}" != */* ]]; then
        script="$(command -v "${script}" 2>/dev/null || printf '%s' "${script}")"
    fi
    case "${script}" in
        /*)
            printf '%s\n' "${script}"
            ;;
        *)
            printf '%s/%s\n' "$(pwd -P)" "${script}"
            ;;
    esac
}

is_transient_script_path() {
    case "$1" in
        /dev/fd/*|/proc/self/fd/*|/proc/*/fd/*|/dev/stdin|*/bash|*/sh)
            return 0
            ;;
    esac
    [[ -r "$1" ]] || return 0
    return 1
}

script_self_path() {
    local script
    script="$(script_source_path)"
    if ! is_transient_script_path "${script}"; then
        printf '%s\n' "${script}"
        return 0
    fi
    default_install_path
}

install_self() {
    local src dest dir
    src="$(script_source_path)"
    dest="$(default_install_path)"
    dir="$(path_dirname "${dest}")"
    mkdir -p "${dir}" || return 1
    if [[ -r "${src}" && "${src}" != */bash && "${src}" != */sh ]]; then
        if [[ -e "${dest}" ]] && [[ "${src}" -ef "${dest}" ]]; then
            :
        else
            cp "${src}" "${dest}" || return 1
        fi
    elif have_cmd curl; then
        curl -fsSL "${RAW_URL}" -o "${dest}" || return 1
    elif have_cmd wget; then
        wget -qO "${dest}" "${RAW_URL}" || return 1
    else
        printf '无法落盘：当前脚本不可复制，且系统缺少 curl/wget。\n' >&2
        return 1
    fi
    chmod 755 "${dest}" 2>/dev/null || true
    printf '%s\n' "${dest}"
}

ensure_persistent_script() {
    local script
    script="$(script_source_path)"
    if ! is_transient_script_path "${script}"; then
        printf '%s\n' "${script}"
        return 0
    fi
    install_self
}

cron_begin_marker() {
    printf '# PO0_LAN_CLIENT_BEGIN %s\n' "${CONFIG_FILE}"
}

cron_end_marker() {
    printf '# PO0_LAN_CLIENT_END %s\n' "${CONFIG_FILE}"
}

write_cron_without_managed_block() {
    local begin end line in_block=0
    begin="$(cron_begin_marker)"
    end="$(cron_end_marker)"
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

install_cron_interactive() {
    local minutes script_path
    ensure_config_file || return 1
    minutes="$(prompt_default "每几分钟上报一次（1-59）" "${CRON_MINUTES}")"
    minutes="$(trim "${minutes}")"
    script_path="$(ensure_persistent_script)" || return 1
    install_cron_minutes "${minutes}" "${script_path}"
}

install_cron_minutes() {
    local minutes="$1"
    local script_path="${2:-}"
    local job tmp
    ensure_config_file || return 1
    command -v crontab >/dev/null 2>&1 || {
        printf '当前系统没有 crontab 命令。请先安装 cron，或改用 systemd timer。\n' >&2
        return 1
    }
    [[ "${minutes}" =~ ^[0-9]+$ && "${minutes}" -ge 1 && "${minutes}" -le 59 ]] || {
        printf '分钟数无效。\n' >&2
        return 1
    }
    [[ -n "${script_path}" ]] || script_path="$(script_self_path)"
    job="*/${minutes} * * * * bash $(sh_quote "${script_path}") --config $(sh_quote "${CONFIG_FILE}") --run >/tmp/po0-lan-client.log 2>&1"
    tmp="${CONFIG_FILE}.cron.$$"
    {
        crontab -l 2>/dev/null | write_cron_without_managed_block || true
        printf '%s\n' "$(cron_begin_marker)"
        printf '%s\n' "${job}"
        printf '%s\n' "$(cron_end_marker)"
    } > "${tmp}" || return 1
    crontab "${tmp}" || {
        rm -f "${tmp}" 2>/dev/null || true
        return 1
    }
    rm -f "${tmp}" 2>/dev/null || true
    printf '已安装/更新定时任务：每 %s 分钟执行 DDNS 解析上报和资源任务轮询。\n' "${minutes}"
}

bootstrap_worker() {
    local label script_path failed=0 mode ddns_resolve_domain
    [[ -n "${PO0_HOST}" ]] || { printf '缺少 --po0-host。\n' >&2; return 1; }
    mode="$(normalize_report_mode "${REPORT_MODE}")"
    ddns_resolve_domain="${DDNS_RESOLVE_DOMAIN}"
    if [[ "${mode}" == "auto" ]]; then
        if [[ -n "${ddns_resolve_domain}" ]]; then
            mode="ddns"
        else
            mode="none"
        fi
    fi
    if [[ "${mode}" == "ddns" ]]; then
        [[ -n "${ddns_resolve_domain}" ]] || ddns_resolve_domain="${DDNS_DOMAIN}"
        [[ -n "${DDNS_DOMAIN}" ]] || DDNS_DOMAIN="${ddns_resolve_domain}"
    fi
    [[ "${mode}" == "ddns" || -n "${RESOURCE_TOKEN}" ]] || {
        printf '缺少 --ddns-domain 或 --resource-token。LAN Worker 主路径是 DDNS resolver/资源任务；访问设备自上报请使用 --self-report-server。\n' >&2
        return 1
    }
    if [[ "${mode}" == "ddns" ]]; then
        [[ -n "${ddns_resolve_domain}" ]] || { printf 'DDNS resolver 模式缺少 --ddns-domain。\n' >&2; return 1; }
        [[ -n "${REPORT_KEY}" ]] || REPORT_KEY="${DDNS_DOMAIN}"
    else
        REPORT_KEY=""
        DDNS_DOMAIN=""
        ddns_resolve_domain=""
    fi
    [[ -n "${PO0_PORT}" ]] || PO0_PORT="22"
    [[ -n "${PO0_USER}" ]] || PO0_USER="root"
    [[ -n "${PO0_SCRIPT}" ]] || PO0_SCRIPT="${DEFAULT_PO0_SCRIPT}"
    REPORT_MODE="${mode}"
    DDNS_RESOLVE_DOMAIN="${ddns_resolve_domain}"
    label="${BOOTSTRAP_LABEL:-${DDNS_DOMAIN:-resource-${PO0_HOST}}}"

    if [[ "${BOOTSTRAP_PROBE}" == "1" ]]; then
        probe_worker_target || return 1
    else
        probe_warn "已跳过 probe，仅写入本机配置。"
    fi

    upsert_target "1" "${label}" "${DDNS_DOMAIN}" "${REPORT_KEY}" "${PO0_HOST}" "${PO0_PORT}" "${PO0_USER}" "${PO0_SCRIPT}" "${DDNS_TOKEN}" "${SSH_EXTRA_ARGS}" "${RESOURCE_TOKEN}" "${mode}" "${ddns_resolve_domain}" || return 1
    chmod 600 "${CONFIG_FILE}" 2>/dev/null || true
    printf '已写入 worker 目标配置：%s\n' "${CONFIG_FILE}"

    if [[ "${INSTALL_CRON}" == "1" ]]; then
        script_path="$(ensure_persistent_script)" || return 1
        printf 'worker 脚本路径：%s\n' "${script_path}"
        install_cron_minutes "${CRON_MINUTES}" "${script_path}" || return 1
    fi

    if [[ "${BOOTSTRAP_RUN}" == "1" ]]; then
        run_all_client_jobs || failed=1
    fi
    return "${failed}"
}

remove_cron_interactive() {
    local tmp
    ensure_config_file || return 1
    command -v crontab >/dev/null 2>&1 || {
        printf '当前系统没有 crontab 命令。\n' >&2
        return 1
    }
    tmp="${CONFIG_FILE}.cron.$$"
    crontab -l 2>/dev/null | write_cron_without_managed_block > "${tmp}" || true
    crontab "${tmp}" || {
        rm -f "${tmp}" 2>/dev/null || true
        return 1
    }
    rm -f "${tmp}" 2>/dev/null || true
    printf '已删除本脚本管理的定时任务。\n'
}

show_cron_status() {
    local begin end line in_block=0 found=0
    command -v crontab >/dev/null 2>&1 || {
        printf '当前系统没有 crontab 命令。\n'
        return 0
    }
    begin="$(cron_begin_marker)"
    end="$(cron_end_marker)"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" == "${begin}" ]]; then
            in_block=1
            found=1
            continue
        fi
        if [[ "${line}" == "${end}" ]]; then
            in_block=0
            continue
        fi
        if [[ "${in_block}" == "1" ]]; then
            printf '当前定时任务：%s\n' "${line}"
        fi
    done < <(crontab -l 2>/dev/null || true)
    [[ "${found}" == "1" ]] || printf '当前没有本脚本管理的定时任务。\n'
}

menu_loop() {
    local choice
    while true; do
        printf '\n%s\n' "PO0 内网 Worker"
        printf '%s\n' "配置文件：${CONFIG_FILE}"
        printf '%s\n' "  1) 查看上报目标和统计"
        printf '%s\n' "  2) 添加上报目标"
        printf '%s\n' "  3) 编辑上报目标"
        printf '%s\n' "  4) 删除上报目标"
        printf '%s\n' "  5) 启用 / 停用上报目标"
        printf '%s\n' "  6) 立即执行 DDNS 解析上报"
        printf '%s\n' "  7) 立即领取并执行资源任务"
        printf '%s\n' "  8) 查看本机资源任务统计"
        printf '%s\n' "  9) 安装 / 更新定时任务"
        printf '%s\n' " 10) 删除定时任务"
        printf '%s\n' " 11) 查看定时任务状态"
        printf '%s\n' " 12) 清空本机 DDNS 解析上报统计"
        printf '%s\n' " 13) WebAuth probe"
        printf '%s\n' " 14) 启动 WebAuth 本地服务"
        printf '%s\n' " 15) Self-report probe"
        printf '%s\n' " 16) 启动 Self-report 本地服务"
        printf '%s\n' "  0) 退出"
        read -r -p "请选择操作 [0-16]: " choice
        choice="$(trim "${choice}")"
        case "${choice}" in
            1) list_targets ;;
            2) add_target_interactive ;;
            3) edit_target_interactive ;;
            4) delete_target_interactive ;;
            5) toggle_target_interactive ;;
            6) run_config_targets ;;
            7) run_resource_targets ;;
            8) list_resource_stats ;;
            9) install_cron_interactive ;;
            10) remove_cron_interactive ;;
            11) show_cron_status ;;
            12) clear_stats_interactive ;;
            13) probe_webauth_target ;;
            14) run_webauth_server ;;
            15) probe_self_report_target ;;
            16) run_self_report_server ;;
            0) return 0 ;;
            *) printf '无效选择。\n' >&2 ;;
        esac
    done
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)
            require_arg_value "$@"
            CONFIG_FILE="${2:-}"
            shift 2
            ;;
        --po0-host)
            require_arg_value "$@"
            PO0_HOST="${2:-}"
            shift 2
            ;;
        --po0-port)
            require_arg_value "$@"
            PO0_PORT="${2:-}"
            shift 2
            ;;
        --po0-user)
            require_arg_value "$@"
            PO0_USER="${2:-}"
            shift 2
            ;;
        --po0-script)
            require_arg_value "$@"
            PO0_SCRIPT="${2:-}"
            shift 2
            ;;
        --source-key|--source)
            require_arg_value "$@"
            DDNS_DOMAIN="${2:-}"
            shift 2
            ;;
        --ddns-domain|--resolve-domain)
            require_arg_value "$@"
            DDNS_RESOLVE_DOMAIN="${2:-}"
            [[ -n "${REPORT_MODE}" ]] || REPORT_MODE="ddns"
            shift 2
            ;;
        --report-mode)
            require_arg_value "$@"
            REPORT_MODE="${2:-}"
            shift 2
            ;;
        --domain)
            require_arg_value "$@"
            DDNS_DOMAIN="${2:-}"
            [[ -n "${DDNS_RESOLVE_DOMAIN}" ]] || DDNS_RESOLVE_DOMAIN="${2:-}"
            [[ -n "${REPORT_MODE}" ]] || REPORT_MODE="ddns"
            shift 2
            ;;
        --key)
            require_arg_value "$@"
            REPORT_KEY="${2:-}"
            shift 2
            ;;
        --name)
            require_arg_value "$@"
            REPORT_KEY="${2:-}"
            shift 2
            ;;
        --token)
            require_arg_value "$@"
            DDNS_TOKEN="${2:-}"
            shift 2
            ;;
        --resource-token)
            require_arg_value "$@"
            RESOURCE_TOKEN="${2:-}"
            shift 2
            ;;
        --ssh-extra-args)
            require_arg_value "$@"
            SSH_EXTRA_ARGS="${2:-}"
            shift 2
            ;;
        --install-path)
            require_arg_value "$@"
            INSTALL_PATH="${2:-}"
            shift 2
            ;;
        --worker-id)
            require_arg_value "$@"
            WORKER_ID="${2:-}"
            shift 2
            ;;
        --listen)
            require_arg_value "$@"
            WEBAUTH_LISTEN="${2:-}"
            shift 2
            ;;
        --webauth-source)
            require_arg_value "$@"
            WEBAUTH_SOURCE="${2:-}"
            shift 2
            ;;
        --webauth-token)
            require_arg_value "$@"
            WEBAUTH_TOKEN="${2:-}"
            shift 2
            ;;
        --webauth-ttl)
            require_arg_value "$@"
            WEBAUTH_TTL_SECONDS="${2:-}"
            shift 2
            ;;
        --self-report-listen)
            require_arg_value "$@"
            SELF_REPORT_LISTEN="${2:-}"
            shift 2
            ;;
        --self-report-source)
            require_arg_value "$@"
            SELF_REPORT_SOURCE="${2:-}"
            shift 2
            ;;
        --self-report-secret)
            require_arg_value "$@"
            SELF_REPORT_SECRET="${2:-}"
            shift 2
            ;;
        --client-ip-token|--self-report-token)
            require_arg_value "$@"
            CLIENT_IP_TOKEN="${2:-}"
            shift 2
            ;;
        --self-report-ttl)
            require_arg_value "$@"
            SELF_REPORT_TTL_SECONDS="${2:-}"
            shift 2
            ;;
        --label)
            require_arg_value "$@"
            BOOTSTRAP_LABEL="${2:-}"
            shift 2
            ;;
        --menu)
            ACTION="menu"
            shift
            ;;
        --probe)
            ACTION="probe"
            shift
            ;;
        --bootstrap)
            ACTION="bootstrap"
            shift
            ;;
        --list)
            ACTION="list"
            shift
            ;;
        --add)
            ACTION="add"
            shift
            ;;
        --delete)
            ACTION="delete"
            shift
            ;;
        --toggle)
            ACTION="toggle"
            shift
            ;;
        --run)
            ACTION="run"
            shift
            ;;
        --webauth-server)
            ACTION="webauth-server"
            shift
            ;;
        --self-report-server)
            ACTION="self-report-server"
            shift
            ;;
        --self-report-probe)
            ACTION="self-report-probe"
            shift
            ;;
        --install-self-report-service)
            ACTION="install-self-report-service"
            shift
            ;;
        --install-webauth-service)
            ACTION="install-webauth-service"
            shift
            ;;
        --webauth-probe)
            ACTION="webauth-probe"
            shift
            ;;
        --install-self)
            ACTION="install-self"
            shift
            ;;
        --install-cron)
            INSTALL_CRON="1"
            if [[ -n "${2:-}" && "${2:-}" =~ ^[0-9]+$ ]]; then
                CRON_MINUTES="${2:-}"
                shift 2
            else
                shift
            fi
            if [[ -z "${ACTION}" ]]; then
                ACTION="install-cron"
            fi
            ;;
        --no-cron)
            INSTALL_CRON="0"
            shift
            ;;
        --no-run)
            BOOTSTRAP_RUN="0"
            shift
            ;;
        --no-probe)
            BOOTSTRAP_PROBE="0"
            shift
            ;;
        --print-cron)
            ACTION="print-cron"
            if [[ -n "${2:-}" && "${2:-}" =~ ^[0-9]+$ ]]; then
                CRON_MINUTES="${2:-}"
                shift 2
            else
                shift
            fi
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            printf '未知参数：%s\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

case "${ACTION}" in
    menu)
        menu_loop
        exit $?
        ;;
    probe)
        probe_worker_target
        exit $?
        ;;
    bootstrap)
        bootstrap_worker
        exit $?
        ;;
    list)
        list_targets
        exit $?
        ;;
    add)
        add_target_interactive
        exit $?
        ;;
    delete)
        delete_target_interactive
        exit $?
        ;;
    toggle)
        toggle_target_interactive
        exit $?
        ;;
    run)
        run_all_client_jobs
        exit $?
        ;;
    webauth-server)
        run_webauth_server
        exit $?
        ;;
    self-report-server)
        run_self_report_server
        exit $?
        ;;
    install-webauth-service)
        install_webauth_service
        exit $?
        ;;
    install-self-report-service)
        install_self_report_service
        exit $?
        ;;
    webauth-probe)
        probe_webauth_target
        exit $?
        ;;
    self-report-probe)
        probe_self_report_target
        exit $?
        ;;
    install-self)
        install_self
        exit $?
        ;;
    install-cron)
        script_path="$(ensure_persistent_script)" || exit 1
        install_cron_minutes "${CRON_MINUTES}" "${script_path}"
        exit $?
        ;;
    print-cron)
        print_cron_example "${CRON_MINUTES}"
        exit $?
        ;;
esac

if [[ -z "${PO0_HOST}" && -z "${DDNS_DOMAIN}" ]]; then
    menu_loop
    exit $?
fi

if [[ -z "${DDNS_DOMAIN}" ]]; then
    printf 'DDNS 解析上报需要 --source-key/--domain；只做资源任务请使用 --bootstrap 或 --run。\n' >&2
    exit 1
fi

if [[ -z "${DDNS_RESOLVE_DOMAIN}" ]]; then
    printf 'DDNS 解析上报需要 --ddns-domain；旧参数 --domain 会同时作为 source key 和 DDNS 域名。\n' >&2
    exit 1
fi
report_once "${DDNS_DOMAIN}" "${REPORT_KEY:-${DDNS_DOMAIN}}" "${DDNS_RESOLVE_DOMAIN}" "${PO0_HOST}" "${PO0_PORT}" "${PO0_USER}" "${PO0_SCRIPT}" "${DDNS_TOKEN}" "${SSH_EXTRA_ARGS}"
