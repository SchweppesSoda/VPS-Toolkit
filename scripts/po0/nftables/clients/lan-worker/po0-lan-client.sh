#!/usr/bin/env bash
set -uo pipefail

RAW_URL="https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/lan-worker/po0-lan-client.sh"
SCRIPT_NAME="po0-lan-worker-client"
SCRIPT_VERSION="2026.06.20+build.9"
SCRIPT_RELEASE_DATE="2026-06-20"
# CHANGELOG_BEGIN
# - 修复 Self-report HTTPS Caddy snippet 使用 respond 404 时被 directive order 提前执行，导致 /health 和 /report 返回 404 的问题。
# - 修复 Self-report HTTPS 域名校验对合法域名静默失败，导致菜单未写入 Caddy 配置的问题。
# - Self-report 新增 HTTPS 域名模式，可在菜单配置 Caddy 自动证书并将后端切到 127.0.0.1:8788。
# - Self-report 默认监听收紧为 127.0.0.1:8788；公网入口默认通过 HTTPS 域名/Caddy。
# - Self-report 后台服务安装/更新后强制 restart，确保旧的失败 unit 立即被新 ExecStart 覆盖。
# - Self-report 后台服务安装时 secret 为空则省略参数，避免 systemd unit 因空参数反复重启失败。
# - Self-report 后台服务安装前检查可用 PO0 目标，避免写入空参数后反复重启失败。
# - Self-report 菜单新增后台服务状态、最近日志和实时日志入口。
# - Self-report 主菜单入口改为配置子菜单，避免按菜单项后直接进入前台监听造成误解。
# - Self-report 子菜单新增监听地址、secret 生成/修改、后台服务安装和前台启动入口。
# - 资源任务本机检查间隔默认改为 1440 分钟，可设置到 10080 分钟。
# - DDNS 菜单新增目标 / 上报计划入口，说明 PO0 DDNS TTL 设置位置并可直接更新本机 DDNS 上报计划。
# CHANGELOG_END
RESOURCE_UPLOAD_MODE="manager-stdin"
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
DDNS_TARGETS="${PO0_DDNS_TARGETS:-}"
CLIENT_IP_TOKEN="${PO0_CLIENT_IP_TOKEN:-${CLIENT_IP_TOKEN:-}}"
RESOURCE_TOKEN="${PO0_RESOURCE_TOKEN:-}"
SSH_EXTRA_ARGS="${SSH_EXTRA_ARGS:-}"
CONFIG_FILE="${PO0_LAN_CLIENT_CONFIG:-}"
STATS_FILE="${PO0_LAN_CLIENT_STATS:-}"
RESOURCE_STATS_FILE="${PO0_LAN_RESOURCE_STATS:-}"
RESOURCE_EVENTS_FILE="${PO0_LAN_RESOURCE_EVENTS:-}"
INSTALL_PATH="${PO0_LAN_CLIENT_INSTALL_PATH:-}"
IPDB_DOWNLOAD_URL="${PO0_IPDB_DOWNLOAD_URL:-https://raw.githubusercontent.com/nmgliangwei/qqwry.ipdb/main/qqwry.ipdb}"
IPLIST_JOBS="${PO0_IPLIST_JOBS:-${IPLIST_JOBS:-16}}"
RESOURCE_TASK_MAX_PER_RUN="${PO0_RESOURCE_TASK_MAX_PER_RUN:-10}"
RESOURCE_UPLOAD_TIMEOUT_SECONDS="${PO0_RESOURCE_UPLOAD_TIMEOUT_SECONDS:-900}"
RESOURCE_COMPLETE_TIMEOUT_SECONDS="${PO0_RESOURCE_COMPLETE_TIMEOUT_SECONDS:-600}"
RESOURCE_CONTROL_TIMEOUT_SECONDS="${PO0_RESOURCE_CONTROL_TIMEOUT_SECONDS:-30}"
RESOURCE_EVENTS_KEEP="${PO0_RESOURCE_EVENTS_KEEP:-500}"
REMOTE_STATUS_TIMEOUT_SECONDS="${PO0_REMOTE_STATUS_TIMEOUT_SECONDS:-8}"
SSH_CONNECT_TIMEOUT_SECONDS="${PO0_SSH_CONNECT_TIMEOUT_SECONDS:-15}"
WORKER_ID="${PO0_WORKER_ID:-$(hostname 2>/dev/null || printf 'po0-worker')}"
STATS_FILE_EXPLICIT="0"
ACTION=""
CRON_MINUTES="5"
DDNS_CRON_MINUTES="${PO0_DDNS_CRON_MINUTES:-${DDNS_CRON_MINUTES:-5}}"
DDNS_CRON_MAX_MINUTES="${PO0_DDNS_CRON_MAX_MINUTES:-1440}"
RESOURCE_CRON_MINUTES="${PO0_RESOURCE_CRON_MINUTES:-${RESOURCE_CRON_MINUTES:-1440}}"
RESOURCE_CRON_MAX_MINUTES="${PO0_RESOURCE_CRON_MAX_MINUTES:-10080}"
INSTALL_CRON=""
BOOTSTRAP_RUN="1"
BOOTSTRAP_PROBE="1"
BOOTSTRAP_LABEL=""
WEBAUTH_LISTEN="${PO0_WEBAUTH_LISTEN:-127.0.0.1:8787}"
WEBAUTH_SOURCE="${PO0_WEBAUTH_SOURCE:-cf-access}"
WEBAUTH_TOKEN="${PO0_WEBAUTH_TOKEN:-}"
WEBAUTH_TTL_SECONDS="${PO0_WEBAUTH_TTL_SECONDS:-3600}"
WEBAUTH_TARGETS="${PO0_WEBAUTH_TARGETS:-}"
SELF_REPORT_LISTEN="${PO0_SELF_REPORT_LISTEN:-127.0.0.1:8788}"
SELF_REPORT_SOURCE="${PO0_SELF_REPORT_SOURCE:-self-report}"
SELF_REPORT_SECRET="${PO0_SELF_REPORT_SECRET:-}"
SELF_REPORT_TTL_SECONDS="${PO0_SELF_REPORT_TTL_SECONDS:-3600}"
SELF_REPORT_TARGETS="${PO0_SELF_REPORT_TARGETS:-}"
SELF_REPORT_HTTPS_DOMAIN="${PO0_SELF_REPORT_HTTPS_DOMAIN:-}"
SELF_REPORT_HTTPS_BACKEND="${PO0_SELF_REPORT_HTTPS_BACKEND:-127.0.0.1:8788}"
SELF_REPORT_CADDY_SNIPPET="${PO0_SELF_REPORT_CADDY_SNIPPET:-/etc/caddy/conf.d/po0-self-report.caddy}"
CADDYFILE_PATH="${PO0_CADDYFILE:-/etc/caddy/Caddyfile}"
C_RESET=""
C_BOLD=""
C_DIM=""
C_GREEN=""
C_YELLOW=""
C_RED=""
C_CYAN=""
C_PANEL=""

[[ -n "${STATS_FILE}" ]] && STATS_FILE_EXPLICIT="1"

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

print_divider() {
    printf '%b%s%b\n' "${C_DIM}" "================================================================" "${C_RESET}"
}

print_title() {
    printf '\n'
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

resource_upload_mode_label() {
    case "${RESOURCE_UPLOAD_MODE}" in
        manager-stdin)
            printf '通过 PO0 manager stdin 上传资源产物（不使用 SCP）'
            ;;
        *)
            printf '%s' "${RESOURCE_UPLOAD_MODE}"
            ;;
    esac
}

script_file_var() {
    local file="$1"
    local name="$2"
    local line value
    [[ -r "${file}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ "${line}" == "${name}="* ]] || continue
        value="${line#*=}"
        value="${value%\"}"
        value="${value#\"}"
        printf '%s\n' "${value}"
        return 0
    done < "${file}"
    return 1
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
        printf '  %s\n' "${line}"
    done < "${file}"
    [[ "${found}" == "1" ]]
}

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
        "  bash po0-lan-client.sh" \
        "  bash po0-lan-client.sh --wizard" \
        "  bash po0-lan-client.sh --menu" \
        "  bash po0-lan-client.sh --probe --po0-host HOST --source-key home --ddns-domain home.example.com --token TOKEN --resource-token TOKEN" \
        "  bash po0-lan-client.sh --bootstrap --po0-host HOST --source-key home --ddns-domain home.example.com --token TOKEN --resource-token TOKEN --install-cron 5" \
        "  bash po0-lan-client.sh --bootstrap --po0-host HOST --resource-token TOKEN --install-cron 1440" \
        "  curl -fsSL ${RAW_URL} | bash -s -- --bootstrap --po0-host HOST --source-key home --ddns-domain home.example.com --token TOKEN --resource-token TOKEN --install-cron 5" \
        "  po0-lan-client --webauth-server --listen 127.0.0.1:8787 --po0-host HOST --webauth-token TOKEN" \
        "  po0-lan-client --install-self-report-https --self-report-https-domain report.example.com --po0-host HOST --client-ip-token TOKEN --self-report-secret SECRET" \
        "  po0-lan-client --self-report-server --self-report-listen 127.0.0.1:8788 --po0-host HOST --client-ip-token TOKEN" \
        "" \
        "常用命令:" \
        "  --probe              只做依赖、DDNS 解析、SSH、PO0 token 连通性/权限检查，不修改 PO0 白名单。" \
        "  --bootstrap          写入本机目标配置，默认先做连通性/权限检查，再执行一次 --run。" \
        "  --install-cron [N]   安装/更新本机 Worker 轮询器；N 为兼容参数，会同时作为 DDNS/资源间隔。" \
        "                        不带 N 时，DDNS 默认 ${DDNS_CRON_MINUTES} 分钟，资源任务默认 ${RESOURCE_CRON_MINUTES} 分钟。" \
        "                        资源任务创建周期在 PO0 nft manager 里设置，本机只定期领取已创建任务。" \
        "                        如果目标启用了 DDNS resolver，DDNS 间隔应小于 PO0 端该 DDNS 来源 TTL。" \
        "  PO0_IPLIST_JOBS=N   iplist txt 并发下载数，默认 16，范围 1-50。" \
        "  PO0_RESOURCE_TASK_MAX_PER_RUN=N 每轮最多处理资源任务数，默认 10；0 表示不设上限。" \
        "  PO0_RESOURCE_UPLOAD_TIMEOUT_SECONDS=N 上传资源产物到 PO0 的超时秒数，默认 900；0 表示不设超时。" \
        "  PO0_RESOURCE_COMPLETE_TIMEOUT_SECONDS=N PO0 校验/导入资源产物的超时秒数，默认 600。" \
        "  --source-key KEY     PO0 端来源 key/名称；脚本不会解析这个值。" \
        "  --ddns-domain DOMAIN LAN Worker 要解析的 DDNS 域名；结果通过 SSH 上报 PO0。" \
        "  --install-self-report-https --self-report-https-domain DOMAIN  配置 Self-report HTTPS/Caddy，后端监听 127.0.0.1:8788。" \
        "  --ddns-targets STR  DDNS 上报目标；格式 source_key|ddns_domain|host|port|user|script|token|ssh_args，多目标用分号或换行分隔。" \
        "  --domain DOMAIN      兼容旧参数：没有 --ddns-domain 时同时作为 source-key 和 DDNS 域名。" \
        "  --ssh-extra-args STR 可选 SSH 参数，例如 '-i /path/key -J jump-host'；不是私钥短语。" \
        "  --no-run             bootstrap 后不立即执行 DDNS 解析上报和资源任务轮询领取。" \
        "  --no-cron            bootstrap 时不安装本机 Worker 轮询器。" \
        "  --run                执行已配置目标的 DDNS 解析上报，并轮询领取 PO0 已创建的资源任务。" \
        "  --run-ddns           只执行 DDNS resolver 上报。" \
        "  --run-resource       只轮询领取 PO0 已创建的资源任务。" \
        "  --webauth-server     在 LAN Worker 本地运行 WebAuth 接收服务；PO0 不开放 HTTP。" \
        "  --webauth-targets STR WebAuth 上报目标；格式 source|host|port|user|script|token|ttl|ssh_args，多目标用分号或换行分隔。" \
        "  --install-webauth-service 安装 systemd 服务运行 WebAuth server。" \
        "  --webauth-probe      检查 WebAuth 依赖和 PO0 上报 token。" \
        "  --self-report-server 在 LAN Worker 本地运行自上报接收服务；访问设备先报 LAN Worker，再由 LAN Worker SSH 上报 PO0。" \
        "  --self-report-targets STR 设备自上报目标；格式 source|host|port|user|script|token|ttl|ssh_args，多目标用分号或换行分隔。" \
        "  --self-report-probe  检查自上报接收端依赖和 PO0 client-ip token。" \
        "  --version            显示当前脚本名称、版本、发布日期、路径和本机状态。" \
        "  --upgrade-self       从 ${RAW_URL} 覆盖更新本机 po0-lan-client 命令，设置权限，并输出版本变化和更新内容。" \
        "  --wizard             进入交互式安装向导。" \
        "  --menu               进入高级菜单。" \
        "" \
        "默认 PO0_SCRIPT=${DEFAULT_PO0_SCRIPT}；可用 --po0-script 覆盖，兼容旧配置。" \
        "WebAuth server 只运行在 LAN Worker 上，推荐经 cloudflared tunnel + Cloudflare Access 暴露。" \
        "DDNS resolver 模式解析 --ddns-domain；--source-key 只用于匹配 PO0 端来源，不在本机解析。" \
        "Self-report 模式接收访问设备上报/请求里的公网 IP，再通过 PO0 的 client_ip 来源写白名单。" \
        "资源任务由 PO0 创建，PO0 端 cron 决定创建周期；本机 Worker 轮询器只负责领取待处理任务，构建/下载后通过 SSH 调 PO0 manager 上传。" \
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

refresh_resource_events_file() {
    if [[ -z "${RESOURCE_EVENTS_FILE}" ]]; then
        RESOURCE_EVENTS_FILE="$(path_dirname "${CONFIG_FILE}")/resource-events.tsv"
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
    (( o1 == 198 && o2 >= 18 && o2 <= 19 )) && return 1
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
    if [[ ! -d "${dir}" ]]; then
        if command -v mkdir >/dev/null 2>&1; then
            mkdir -p "${dir}" || return 1
        else
            printf '资源统计目录不存在，且当前系统缺少 mkdir：%s\n' "${dir}" >&2
            return 1
        fi
    fi
    if [[ ! -f "${RESOURCE_STATS_FILE}" ]]; then
        printf '# endpoint_id|success_count|fail_count|last_task|last_type|last_status|last_at|last_message\n' > "${RESOURCE_STATS_FILE}" || return 1
        chmod 600 "${RESOURCE_STATS_FILE}" 2>/dev/null || true
    fi
}

ensure_resource_events_file() {
    local dir
    refresh_resource_events_file
    dir="$(path_dirname "${RESOURCE_EVENTS_FILE}")"
    if [[ ! -d "${dir}" ]]; then
        if command -v mkdir >/dev/null 2>&1; then
            mkdir -p "${dir}" || return 1
        else
            printf '资源事件目录不存在，且当前系统缺少 mkdir：%s\n' "${dir}" >&2
            return 1
        fi
    fi
    if [[ ! -f "${RESOURCE_EVENTS_FILE}" ]]; then
        printf '# at|endpoint_id|task_id|task_type|status|message\n' > "${RESOURCE_EVENTS_FILE}" || return 1
        chmod 600 "${RESOURCE_EVENTS_FILE}" 2>/dev/null || true
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
        if ! value="$(read_prompt "${prompt} [${default}]: ")"; then
            value=""
        fi
        value="$(trim "${value}")"
        [[ -n "${value}" ]] || value="${default}"
    else
        if ! value="$(read_prompt "${prompt}: ")"; then
            value=""
        fi
        value="$(trim "${value}")"
    fi
    printf '%s\n' "${value}"
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

drain_tty_input_buffer() {
    local line
    [[ -r /dev/tty ]] || return 0
    while IFS= read -r -t 0.05 line < /dev/tty 2>/dev/null; do
        :
    done
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

pause_before_return() {
    read_prompt "按回车返回菜单..." >/dev/null || true
}

menu_clear_screen() {
    [[ "${MENU_CLEAR:-1}" == "0" ]] && return 0
    [[ -t 1 && -n "${TERM:-}" && "${TERM}" != "dumb" ]] || return 0
    command -v clear >/dev/null 2>&1 && clear || printf '\033[H\033[2J'
}

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local suffix value
    case "${default,,}" in
        y|yes|1|true)
            suffix="Y/n"
            default="y"
            ;;
        *)
            suffix="y/N"
            default="n"
            ;;
    esac
    while true; do
        if ! value="$(read_prompt "${prompt} [${suffix}]: ")"; then
            return 1
        fi
        value="$(trim "${value}")"
        [[ -n "${value}" ]] || value="${default}"
        case "${value,,}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) printf '请输入 y 或 n。\n' >&2 ;;
        esac
    done
}

random_secret() {
    local token=""
    if command -v openssl >/dev/null 2>&1; then
        token="$(openssl rand -hex 24 2>/dev/null || true)"
    fi
    if [[ -z "${token}" ]] && [[ -r /dev/urandom ]]; then
        token="$(od -An -N24 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
    fi
    [[ -n "${token}" ]] || token="$(date '+%s')-$RANDOM-$RANDOM-$RANDOM"
    printf '%s\n' "${token}"
}

mask_secret() {
    local value="$1"
    local len
    [[ -n "${value}" ]] || { printf '<empty>\n'; return; }
    len="${#value}"
    if (( len <= 10 )); then
        printf '***\n'
    else
        printf '%s...%s\n' "${value:0:6}" "${value: -4}"
    fi
}

safe_filename_token() {
    local value="$1"
    value="${value//[!A-Za-z0-9_.-]/_}"
    value="${value##_}"
    value="${value%%_}"
    [[ -n "${value}" ]] || value="po0"
    printf '%s\n' "${value}"
}

is_private_key_begin_line() {
    case "$1" in
        -----BEGIN\ *PRIVATE\ KEY-----) return 0 ;;
        *) return 1 ;;
    esac
}

is_private_key_end_line() {
    case "$1" in
        -----END\ *PRIVATE\ KEY-----) return 0 ;;
        *) return 1 ;;
    esac
}

read_private_key_from_first_line() {
    local line="$1"
    local key="" seen_begin=0 seen_end=0
    while true; do
        line="${line%$'\r'}"
        if [[ -z "${line}" && "${seen_begin}" == "0" ]]; then
            printf '未读取到私钥内容。\n' >&2
            return 1
        fi
        key+="${line}"$'\n'
        if is_private_key_begin_line "${line}"; then
            seen_begin=1
        fi
        if is_private_key_end_line "${line}"; then
            seen_end=1
            break
        fi
        if [[ -r /dev/tty && -w /dev/tty ]]; then
            IFS= read -r line < /dev/tty || return 1
        else
            IFS= read -r line || return 1
        fi
    done
    [[ "${seen_begin}" == "1" && "${seen_end}" == "1" ]] || {
        printf '私钥内容不完整。\n' >&2
        return 1
    }
    printf '%s' "${key}"
}

validate_ssh_private_key_file() {
    local path="$1"
    command -v ssh-keygen >/dev/null 2>&1 || return 0
    ssh-keygen -y -f "${path}" >/dev/null 2>&1
}

read_private_key_paste() {
    local line key
    if [[ -w /dev/tty ]]; then
        printf '请粘贴 SSH 私钥，粘贴到 END ... PRIVATE KEY 行后会自动结束；空输入取消。\n' > /dev/tty
    else
        printf '请粘贴 SSH 私钥，粘贴到 END ... PRIVATE KEY 行后会自动结束；空输入取消。\n' >&2
    fi
    if [[ -r /dev/tty && -w /dev/tty ]]; then
        IFS= read -r line < /dev/tty || return 1
    else
        IFS= read -r line || return 1
    fi
    if key="$(read_private_key_from_first_line "${line}")"; then
        drain_tty_input_buffer
        printf '%s' "${key}"
        return 0
    fi
    drain_tty_input_buffer
    return 1
}

save_ssh_key_content() {
    local host="$1"
    local port="$2"
    local user="$3"
    local key="$4"
    local dir key_path host_token port_token user_token old_umask backup_path=""
    ensure_config_file || return 1
    dir="$(path_dirname "${CONFIG_FILE}")"
    host_token="$(safe_filename_token "${host}")"
    port_token="$(safe_filename_token "${port:-22}")"
    user_token="$(safe_filename_token "${user:-root}")"
    key_path="${dir}/ssh-key-${user_token}-${host_token}-${port_token}"
    if [[ -e "${key_path}" ]]; then
        prompt_yes_no "私钥文件已存在，是否覆盖：${key_path}" "n" || return 1
        backup_path="${key_path}.bak.$$"
        cp -p "${key_path}" "${backup_path}" 2>/dev/null || backup_path=""
    fi
    old_umask="$(umask)"
    umask 077
    printf '%s\n' "${key}" > "${key_path}" || {
        umask "${old_umask}"
        [[ -n "${backup_path}" ]] && mv -f "${backup_path}" "${key_path}" 2>/dev/null || true
        return 1
    }
    umask "${old_umask}"
    chmod 600 "${key_path}" 2>/dev/null || true
    if ! validate_ssh_private_key_file "${key_path}"; then
        if [[ -n "${backup_path}" && -f "${backup_path}" ]]; then
            mv -f "${backup_path}" "${key_path}" 2>/dev/null || true
        else
            rm -f -- "${key_path}" 2>/dev/null || true
        fi
        printf 'SSH 私钥保存后校验失败，未使用这次粘贴内容。请确认粘贴的是完整 OpenSSH 私钥，或改用 1Password 导出到文件后填写路径。\n' >&2
        return 1
    fi
    [[ -n "${backup_path}" ]] && rm -f -- "${backup_path}" 2>/dev/null || true
    printf '%s\n' "${key_path}"
}

save_pasted_ssh_key() {
    local host="$1"
    local port="$2"
    local user="$3"
    local key
    key="$(read_private_key_paste)" || return 1
    save_ssh_key_content "${host}" "${port}" "${user}" "${key}"
}

prompt_ssh_key_path_or_paste() {
    local prompt="$1"
    local default="$2"
    local host="$3"
    local port="$4"
    local user="$5"
    local value key
    value="$(prompt_default "${prompt}" "${default}")"
    if is_private_key_begin_line "${value}"; then
        printf '[WARN] 检测到你把私钥内容粘贴到了“路径”输入框，正在继续读取剩余私钥内容并保存。\n' >&2
        key="$(read_private_key_from_first_line "${value}")" || { drain_tty_input_buffer; return 1; }
        drain_tty_input_buffer
        save_ssh_key_content "${host}" "${port}" "${user}" "${key}"
        return 0
    fi
    printf '%s\n' "${value}"
}

ssh_extra_without_private_key_text() {
    local extra="$1"
    local -a parts=()
    local out="" token private_key_words=0
    local i
    [[ -n "${extra}" ]] || { printf '\n'; return 0; }
    read -r -a parts <<< "${extra}"
    for ((i = 0; i < ${#parts[@]}; i++)); do
        token="${parts[$i]}"
        if [[ "${private_key_words}" == "1" ]]; then
            case "${token}" in
                OPENSSH|RSA|DSA|EC|ECDSA|ED25519|PRIVATE|KEY|KEY-----|*KEY-----|-----END*)
                    [[ "${token}" == *KEY----- || "${token}" == -----END* ]] && private_key_words=0
                    continue
                    ;;
            esac
        fi
        case "${token}" in
            -----BEGIN*|-----END*)
                private_key_words=1
                [[ "${token}" == *KEY----- || "${token}" == -----END* ]] && private_key_words=0
                continue
                ;;
        esac
        out="${out:+${out} }${token}"
    done
    printf '%s\n' "${out}"
}

prompt_ssh_extra_args() {
    local prompt="$1"
    local default="$2"
    local host="$3"
    local port="$4"
    local user="$5"
    local value raw key key_path cleaned used_default=0
    if [[ -n "${default}" ]]; then
        raw="$(read_prompt "${prompt} [${default}]: ")" || raw=""
        raw="$(trim "${raw}")"
        if [[ -n "${raw}" ]]; then
            value="${raw}"
        else
            value="${default}"
            used_default=1
        fi
    else
        raw="$(read_prompt "${prompt}: ")" || raw=""
        value="$(trim "${raw}")"
    fi
    if [[ "${used_default}" == "0" ]] && is_private_key_begin_line "${value}"; then
        printf '[WARN] 检测到你把私钥内容粘贴到了“额外 SSH 参数”输入框，正在保存为私钥文件。\n' >&2
        key="$(read_private_key_from_first_line "${value}")" || { drain_tty_input_buffer; return 1; }
        drain_tty_input_buffer
        key_path="$(save_ssh_key_content "${host}" "${port}" "${user}" "${key}")" || return 1
        cleaned="$(ssh_extra_without_identity "${default}")"
        ssh_extra_with_identity "${cleaned}" "${key_path}"
        return 0
    fi
    case "${value}" in
        *"-----BEGIN "*"PRIVATE KEY-----"*|*"-----END "*"PRIVATE KEY-----"*)
            if [[ "${used_default}" == "1" ]]; then
                printf '[WARN] 清理旧配置中残留的私钥正文片段；请使用 -i /path/key 引用私钥文件。\n' >&2
                ssh_extra_without_private_key_text "${value}"
                return 0
            fi
            printf '额外 SSH 参数不能填写私钥正文；请选择“粘贴私钥并保存到本机”，或先保存私钥文件后填写 -i /path/key。\n' >&2
            return 1
            ;;
    esac
    printf '%s\n' "${value}"
}

ssh_extra_identity_path() {
    local extra="$1"
    local -a parts=()
    local i token next
    [[ -n "${extra}" ]] || return 1
    read -r -a parts <<< "${extra}"
    for ((i = 0; i < ${#parts[@]}; i++)); do
        token="${parts[$i]}"
        next="${parts[$((i + 1))]:-}"
        case "${token}" in
            -i)
                [[ -n "${next}" ]] && { printf '%s\n' "${next}"; return 0; }
                ;;
            -i?*)
                printf '%s\n' "${token#-i}"
                return 0
                ;;
            IdentityFile=*)
                printf '%s\n' "${token#IdentityFile=}"
                return 0
                ;;
            -o)
                case "${next}" in
                    IdentityFile=*)
                        printf '%s\n' "${next#IdentityFile=}"
                        return 0
                        ;;
                esac
                ;;
            -oIdentityFile=*)
                printf '%s\n' "${token#-oIdentityFile=}"
                return 0
                ;;
        esac
    done
    return 1
}

ssh_extra_without_identity() {
    local extra="$1"
    local -a parts=()
    local out="" token next private_key_words=0
    local i skip_next=0
    [[ -n "${extra}" ]] || { printf '\n'; return 0; }
    read -r -a parts <<< "${extra}"
    for ((i = 0; i < ${#parts[@]}; i++)); do
        if [[ "${skip_next}" == "1" ]]; then
            skip_next=0
            continue
        fi
        token="${parts[$i]}"
        next="${parts[$((i + 1))]:-}"
        if [[ "${private_key_words}" == "1" ]]; then
            case "${token}" in
                OPENSSH|RSA|DSA|EC|ECDSA|ED25519|PRIVATE|KEY|KEY-----|*KEY-----|-----END*)
                    [[ "${token}" == *KEY----- || "${token}" == -----END* ]] && private_key_words=0
                    continue
                    ;;
            esac
        fi
        case "${token}" in
            -----BEGIN*|-----END*)
                private_key_words=1
                [[ "${token}" == *KEY----- || "${token}" == -----END* ]] && private_key_words=0
                continue
                ;;
            -i)
                skip_next=1
                continue
                ;;
            -i?*|IdentityFile=*|-oIdentityFile=*)
                continue
                ;;
            -o)
                case "${next}" in
                    IdentityFile=*)
                        skip_next=1
                        continue
                        ;;
                esac
                ;;
        esac
        out="${out:+${out} }${token}"
    done
    printf '%s\n' "${out}"
}

ssh_extra_with_identity() {
    local extra="$1"
    local key_path="$2"
    local out
    out="$(ssh_extra_without_identity "${extra}")"
    key_path="$(trim "${key_path}")"
    if [[ -n "${key_path}" ]]; then
        out="-i ${key_path}${out:+ ${out}}"
    fi
    printf '%s\n' "${out}"
}

ssh_extra_warn_ignored() {
    local context="$1"
    local reason="$2"
    printf '[WARN] %s: ignored SSH extra arg (%s).\n' "${context:-SSH extra args}" "${reason}" >&2
}

sanitize_ssh_extra_args() {
    local extra="$1"
    local context="${2:-SSH extra args}"
    local -a parts=()
    local token next
    local i
    local has_batchmode=0 has_connect_timeout=0 has_strict_host=0 connect_timeout
    local has_connection_attempts=0 has_number_prompts=0 has_preferred_auth=0 has_password_auth=0 has_kbd_auth=0 has_gssapi=0
    local private_key_words=0 private_key_warned=0
    SSH_EXTRA_ARGV=()
    connect_timeout="$(timeout_seconds "${SSH_CONNECT_TIMEOUT_SECONDS}" 15)"
    if [[ -n "${extra}" ]]; then
        read -r -a parts <<< "${extra}"
    fi
    for ((i = 0; i < ${#parts[@]}; i++)); do
        token="${parts[$i]}"
        next="${parts[$((i + 1))]:-}"
        [[ -n "${token}" ]] || continue
        if [[ "${private_key_words}" == "1" ]]; then
            case "${token}" in
                OPENSSH|RSA|DSA|EC|ECDSA|ED25519|PRIVATE|KEY|KEY-----|*KEY-----|-----END*)
                    [[ "${token}" == *KEY----- || "${token}" == -----END* ]] && private_key_words=0
                    continue
                    ;;
            esac
        fi
        case "${token}" in
            -----BEGIN*|-----END*)
                if [[ "${private_key_warned}" == "0" ]]; then
                    ssh_extra_warn_ignored "${context}" "private key text is not an SSH option; save it to a file and use -i /path/key"
                    private_key_warned=1
                fi
                private_key_words=1
                [[ "${token}" == *KEY----- || "${token}" == -----END* ]] && private_key_words=0
                continue
                ;;
            -|--*)
                ssh_extra_warn_ignored "${context}" "invalid option/private-key marker"
                continue
                ;;
            -p)
                ssh_extra_warn_ignored "${context}" "port belongs in the PO0 SSH port field"
                if [[ -n "${next}" && "${next}" != -* ]]; then
                    ((i++))
                fi
                continue
                ;;
            -p?*)
                ssh_extra_warn_ignored "${context}" "port belongs in the PO0 SSH port field"
                continue
                ;;
            BatchMode=*)
                has_batchmode=1
                SSH_EXTRA_ARGV+=(-o "${token}")
                continue
                ;;
            ConnectTimeout=*)
                has_connect_timeout=1
                SSH_EXTRA_ARGV+=(-o "${token}")
                continue
                ;;
            StrictHostKeyChecking=*)
                has_strict_host=1
                SSH_EXTRA_ARGV+=(-o "${token}")
                continue
                ;;
            ConnectionAttempts=*)
                has_connection_attempts=1
                SSH_EXTRA_ARGV+=(-o "${token}")
                continue
                ;;
            NumberOfPasswordPrompts=*)
                has_number_prompts=1
                SSH_EXTRA_ARGV+=(-o "${token}")
                continue
                ;;
            PreferredAuthentications=*)
                has_preferred_auth=1
                SSH_EXTRA_ARGV+=(-o "${token}")
                continue
                ;;
            PasswordAuthentication=*)
                has_password_auth=1
                SSH_EXTRA_ARGV+=(-o "${token}")
                continue
                ;;
            KbdInteractiveAuthentication=*)
                has_kbd_auth=1
                SSH_EXTRA_ARGV+=(-o "${token}")
                continue
                ;;
            GSSAPIAuthentication=*)
                has_gssapi=1
                SSH_EXTRA_ARGV+=(-o "${token}")
                continue
                ;;
            IdentityFile=*|UserKnownHostsFile=*|HostKeyAlias=*|ProxyJump=*|ProxyCommand=*)
                SSH_EXTRA_ARGV+=(-o "${token}")
                continue
                ;;
            -oBatchMode=*)
                has_batchmode=1
                SSH_EXTRA_ARGV+=("${token}")
                continue
                ;;
            -oConnectTimeout=*)
                has_connect_timeout=1
                SSH_EXTRA_ARGV+=("${token}")
                continue
                ;;
            -oStrictHostKeyChecking=*)
                has_strict_host=1
                SSH_EXTRA_ARGV+=("${token}")
                continue
                ;;
            -oConnectionAttempts=*)
                has_connection_attempts=1
                SSH_EXTRA_ARGV+=("${token}")
                continue
                ;;
            -oNumberOfPasswordPrompts=*)
                has_number_prompts=1
                SSH_EXTRA_ARGV+=("${token}")
                continue
                ;;
            -oPreferredAuthentications=*)
                has_preferred_auth=1
                SSH_EXTRA_ARGV+=("${token}")
                continue
                ;;
            -oPasswordAuthentication=*)
                has_password_auth=1
                SSH_EXTRA_ARGV+=("${token}")
                continue
                ;;
            -oKbdInteractiveAuthentication=*)
                has_kbd_auth=1
                SSH_EXTRA_ARGV+=("${token}")
                continue
                ;;
            -oGSSAPIAuthentication=*)
                has_gssapi=1
                SSH_EXTRA_ARGV+=("${token}")
                continue
                ;;
        esac
        case "${token}" in
            -B|-b|-c|-D|-E|-e|-F|-I|-i|-J|-L|-l|-m|-O|-o|-P|-Q|-R|-S|-W|-w)
                if [[ -z "${next}" || "${next}" == -* ]]; then
                    ssh_extra_warn_ignored "${context}" "missing value for ${token}"
                    continue
                fi
                if [[ "${token}" == "-o" ]]; then
                    case "${next}" in
                        BatchMode=*) has_batchmode=1 ;;
                        ConnectTimeout=*) has_connect_timeout=1 ;;
                        StrictHostKeyChecking=*) has_strict_host=1 ;;
                        ConnectionAttempts=*) has_connection_attempts=1 ;;
                        NumberOfPasswordPrompts=*) has_number_prompts=1 ;;
                        PreferredAuthentications=*) has_preferred_auth=1 ;;
                        PasswordAuthentication=*) has_password_auth=1 ;;
                        KbdInteractiveAuthentication=*) has_kbd_auth=1 ;;
                        GSSAPIAuthentication=*) has_gssapi=1 ;;
                    esac
                fi
                SSH_EXTRA_ARGV+=("${token}" "${next}")
                ((i++))
                ;;
            -*)
                SSH_EXTRA_ARGV+=("${token}")
                ;;
            *)
                ssh_extra_warn_ignored "${context}" "bare value without an SSH option"
                ;;
        esac
    done
    [[ "${has_batchmode}" == "1" ]] || SSH_EXTRA_ARGV+=(-o BatchMode=yes)
    [[ "${has_connect_timeout}" == "1" ]] || SSH_EXTRA_ARGV+=(-o "ConnectTimeout=${connect_timeout}")
    [[ "${has_strict_host}" == "1" ]] || SSH_EXTRA_ARGV+=(-o StrictHostKeyChecking=accept-new)
    [[ "${has_connection_attempts}" == "1" ]] || SSH_EXTRA_ARGV+=(-o ConnectionAttempts=1)
    [[ "${has_number_prompts}" == "1" ]] || SSH_EXTRA_ARGV+=(-o NumberOfPasswordPrompts=0)
    [[ "${has_preferred_auth}" == "1" ]] || SSH_EXTRA_ARGV+=(-o PreferredAuthentications=publickey)
    [[ "${has_password_auth}" == "1" ]] || SSH_EXTRA_ARGV+=(-o PasswordAuthentication=no)
    [[ "${has_kbd_auth}" == "1" ]] || SSH_EXTRA_ARGV+=(-o KbdInteractiveAuthentication=no)
    [[ "${has_gssapi}" == "1" ]] || SSH_EXTRA_ARGV+=(-o GSSAPIAuthentication=no)
}

build_batchmode_ssh_extra_args() {
    local key_path="$1"
    local extra="$2"
    local out="" raw_extra
    key_path="$(trim "${key_path}")"
    extra="$(trim "${extra}")"
    raw_extra="${extra}"
    extra="$(ssh_extra_without_private_key_text "${extra}")"
    if [[ "${raw_extra}" != "${extra}" ]]; then
        printf '[WARN] 已忽略额外 SSH 参数中的私钥正文片段；私钥必须保存为文件并通过 -i /path/key 引用。\n' >&2
    fi
    if [[ -n "${key_path}" ]]; then
        case "${key_path}" in
            *" "*)
                printf '当前 ssh extra args 解析不支持带空格的私钥路径，请改用不含空格的路径或手动填写 --ssh-extra-args。\n' >&2
                return 1
                ;;
        esac
        extra="$(ssh_extra_without_identity "${extra}")"
        out="-i ${key_path}"
    fi
    [[ -n "${extra}" ]] && out="${out:+${out} }${extra}"
    case " ${out} " in
        *" BatchMode=yes "*|*" BatchMode yes "*)
            ;;
        *)
            out="${out:+${out} }-o BatchMode=yes"
            ;;
    esac
    case " ${out} " in
        *" StrictHostKeyChecking="*|*" StrictHostKeyChecking "*)
            ;;
        *)
            out="${out:+${out} }-o StrictHostKeyChecking=accept-new"
            ;;
    esac
    printf '%s\n' "${out}"
}

print_host_key_failure_help() {
    local host="$1"
    local port="$2"
    local user="$3"
    local extra="$4"
    local key_path
    [[ "${extra}" == *"Host key verification failed"* ]] || return 0
    key_path="$(ssh_extra_identity_path "${SSH_EXTRA_ARGS}" 2>/dev/null || true)"
    printf '\n[提示] SSH 主机指纹校验失败。\n' >&2
    printf '如果这是第一次连接该 PO0，重新运行新版向导会自动使用 StrictHostKeyChecking=accept-new。\n' >&2
    printf '你也可以先手动确认并写入 known_hosts：\n' >&2
    if [[ -n "${key_path}" ]]; then
        printf '  ssh -i %s -p %s %s@%s true\n' "${key_path}" "${port:-22}" "${user:-root}" "${host}" >&2
    else
        printf '  ssh -p %s %s@%s true\n' "${port:-22}" "${user:-root}" "${host}" >&2
    fi
    printf '如果提示 REMOTE HOST IDENTIFICATION HAS CHANGED，先确认 PO0 主机确实是你的机器，再清理旧指纹：\n' >&2
    printf '  ssh-keygen -R "[%s]:%s"\n' "${host}" "${port:-22}" >&2
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
        IFS='|' read -r TARGET_ENABLED TARGET_LABEL TARGET_DOMAIN TARGET_REPORT_KEY TARGET_PO0_HOST TARGET_PO0_PORT TARGET_PO0_USER TARGET_PO0_SCRIPT TARGET_TOKEN TARGET_SSH_EXTRA_ARGS TARGET_RESOURCE_TOKEN TARGET_REPORT_MODE TARGET_DDNS_RESOLVE_DOMAIN TARGET_CLIENT_IP_TOKEN TARGET_CLIENT_IP_SOURCE TARGET_CLIENT_IP_TTL TARGET_WEBAUTH_TOKEN TARGET_WEBAUTH_SOURCE TARGET_WEBAUTH_TTL TARGET_REPORT_SSH_EXTRA_ARGS <<< "${line}"
    else
        # Legacy whitespace configs had no resource_token column; keep all
        # remaining words in ssh_extra_args for backward compatibility.
        read -r TARGET_ENABLED TARGET_LABEL TARGET_DOMAIN TARGET_REPORT_KEY TARGET_PO0_HOST TARGET_PO0_PORT TARGET_PO0_USER TARGET_PO0_SCRIPT TARGET_TOKEN TARGET_SSH_EXTRA_ARGS <<< "${line}"
        TARGET_RESOURCE_TOKEN=""
        TARGET_REPORT_MODE=""
        TARGET_DDNS_RESOLVE_DOMAIN=""
        TARGET_CLIENT_IP_TOKEN=""
        TARGET_CLIENT_IP_SOURCE=""
        TARGET_CLIENT_IP_TTL=""
        TARGET_WEBAUTH_TOKEN=""
        TARGET_WEBAUTH_SOURCE=""
        TARGET_WEBAUTH_TTL=""
        TARGET_REPORT_SSH_EXTRA_ARGS=""
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
    TARGET_CLIENT_IP_TOKEN="$(sanitize_field "${TARGET_CLIENT_IP_TOKEN:-}")"
    TARGET_CLIENT_IP_SOURCE="$(sanitize_field "${TARGET_CLIENT_IP_SOURCE:-}")"
    TARGET_CLIENT_IP_TTL="$(sanitize_field "${TARGET_CLIENT_IP_TTL:-}")"
    TARGET_WEBAUTH_TOKEN="$(sanitize_field "${TARGET_WEBAUTH_TOKEN:-}")"
    TARGET_WEBAUTH_SOURCE="$(sanitize_field "${TARGET_WEBAUTH_SOURCE:-}")"
    TARGET_WEBAUTH_TTL="$(sanitize_field "${TARGET_WEBAUTH_TTL:-}")"
    TARGET_REPORT_SSH_EXTRA_ARGS="$(sanitize_field "${TARGET_REPORT_SSH_EXTRA_ARGS:-}")"
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
    [[ -n "${TARGET_DOMAIN}" || -n "${TARGET_RESOURCE_TOKEN}" || -n "${TARGET_CLIENT_IP_TOKEN}" || -n "${TARGET_WEBAUTH_TOKEN}" ]] || return 1
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
        printf '  %2d) %-4s %-14s 类型=%s PO0=%s@%s:%s\n' \
            "${idx}" "${status}" "${TARGET_LABEL:-未命名}" "$(target_kind_summary)" "${TARGET_PO0_USER:-root}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT:-22}"
        if [[ "${TARGET_REPORT_MODE}" == "ddns" ]]; then
            printf '      来源 key：%s；PO0 匹配 key：%s\n' "${domain_label}" "${key_label}"
            printf '      DDNS 域名：%s\n' "${TARGET_DDNS_RESOLVE_DOMAIN:-${TARGET_DOMAIN}}"
            print_target_stats "${target_id}"
        fi
        [[ -n "${TARGET_CLIENT_IP_TOKEN}" ]] && printf '      设备自上报：source=%s ttl=%s\n' "${TARGET_CLIENT_IP_SOURCE:-${SELF_REPORT_SOURCE}}" "${TARGET_CLIENT_IP_TTL:-${SELF_REPORT_TTL_SECONDS}}"
        [[ -n "${TARGET_WEBAUTH_TOKEN}" ]] && printf '      WebAuth 放行：source=%s ttl=%s\n' "${TARGET_WEBAUTH_SOURCE:-${WEBAUTH_SOURCE}}" "${TARGET_WEBAUTH_TTL:-${WEBAUTH_TTL_SECONDS}}"
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
    if ! answer="$(read_prompt "确认清空本机上报统计 [y/N]: ")"; then
        printf '\n输入结束，取消清空。\n'
        return 0
    fi
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
    local client_ip_token="${14:-}"
    local client_ip_source="${15:-}"
    local client_ip_ttl="${16:-}"
    local webauth_token="${17:-}"
    local webauth_source="${18:-}"
    local webauth_ttl="${19:-}"
    local report_ssh_extra_args="${20:-}"
    ensure_config_file || return 1
    ssh_extra_args="$(ssh_extra_without_private_key_text "${ssh_extra_args}")"
    report_ssh_extra_args="$(ssh_extra_without_private_key_text "${report_ssh_extra_args}")"
    report_mode="$(normalize_report_mode "${report_mode}")"
    if [[ "${report_mode}" == "auto" ]]; then
        [[ -n "${ddns_resolve_domain:-${domain}}" ]] && report_mode="ddns" || report_mode="none"
    fi
    [[ -n "${ddns_resolve_domain}" ]] || ddns_resolve_domain="${domain}"
    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
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
        "$(sanitize_field "${ddns_resolve_domain}")" \
        "$(sanitize_field "${client_ip_token}")" \
        "$(sanitize_field "${client_ip_source}")" \
        "$(sanitize_field "${client_ip_ttl}")" \
        "$(sanitize_field "${webauth_token}")" \
        "$(sanitize_field "${webauth_source}")" \
        "$(sanitize_field "${webauth_ttl}")" \
        "$(sanitize_field "${report_ssh_extra_args}")" >> "${CONFIG_FILE}"
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
    local client_ip_token="${14:-}"
    local client_ip_source="${15:-}"
    local client_ip_ttl="${16:-}"
    local webauth_token="${17:-}"
    local webauth_source="${18:-}"
    local webauth_ttl="${19:-}"
    local report_ssh_extra_args="${20:-}"
    local tmp line found=0
    ensure_config_file || return 1
    ssh_extra_args="$(ssh_extra_without_private_key_text "${ssh_extra_args}")"
    report_ssh_extra_args="$(ssh_extra_without_private_key_text "${report_ssh_extra_args}")"
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
                printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
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
                    "$(sanitize_field "${ddns_resolve_domain}")" \
                    "$(sanitize_field "${client_ip_token}")" \
                    "$(sanitize_field "${client_ip_source}")" \
                    "$(sanitize_field "${client_ip_ttl}")" \
                    "$(sanitize_field "${webauth_token}")" \
                    "$(sanitize_field "${webauth_source}")" \
                    "$(sanitize_field "${webauth_ttl}")" \
                    "$(sanitize_field "${report_ssh_extra_args}")" >> "${tmp}"
                continue
            fi
        fi
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${CONFIG_FILE}"
    if [[ "${found}" != "1" ]]; then
        printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
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
            "$(sanitize_field "${ddns_resolve_domain}")" \
            "$(sanitize_field "${client_ip_token}")" \
            "$(sanitize_field "${client_ip_source}")" \
            "$(sanitize_field "${client_ip_ttl}")" \
            "$(sanitize_field "${webauth_token}")" \
            "$(sanitize_field "${webauth_source}")" \
            "$(sanitize_field "${webauth_ttl}")" \
            "$(sanitize_field "${report_ssh_extra_args}")" >> "${tmp}"
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

target_kind_summary() {
    local kinds=""
    if [[ "${TARGET_REPORT_MODE}" == "ddns" && -n "${TARGET_DOMAIN}" && -n "${TARGET_DDNS_RESOLVE_DOMAIN}" ]]; then
        kinds="DDNS 上报"
    fi
    if [[ -n "${TARGET_CLIENT_IP_TOKEN}" ]]; then
        [[ -n "${kinds}" ]] && kinds+=", "
        kinds+="设备自上报"
    fi
    if [[ -n "${TARGET_WEBAUTH_TOKEN}" ]]; then
        [[ -n "${kinds}" ]] && kinds+=", "
        kinds+="WebAuth 放行"
    fi
    if [[ -n "${TARGET_RESOURCE_TOKEN}" ]]; then
        [[ -n "${kinds}" ]] && kinds+=", "
        kinds+="资源任务"
    fi
    printf '%s\n' "${kinds:-未配置任务}"
}

dashboard_stat_totals() {
    local line id success fail last_status last_at last_ip_csv last_error
    DASH_SUCCESS_TOTAL=0
    DASH_FAIL_TOTAL=0
    DASH_LAST_STATUS=""
    DASH_LAST_AT=""
    DASH_LAST_IP_CSV=""
    DASH_LAST_ERROR=""
    [[ -f "${STATS_FILE}" ]] || return 0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="$(trim "${line}")"
        [[ -n "${line}" && ! "${line}" =~ ^# ]] || continue
        IFS='|' read -r id success fail last_status last_at last_ip_csv last_error <<< "${line}"
        [[ "${success}" =~ ^[0-9]+$ ]] || success=0
        [[ "${fail}" =~ ^[0-9]+$ ]] || fail=0
        DASH_SUCCESS_TOTAL=$((DASH_SUCCESS_TOTAL + success))
        DASH_FAIL_TOTAL=$((DASH_FAIL_TOTAL + fail))
        if [[ -n "${last_at}" && ( -z "${DASH_LAST_AT}" || "${last_at}" > "${DASH_LAST_AT}" ) ]]; then
            DASH_LAST_STATUS="${last_status}"
            DASH_LAST_AT="${last_at}"
            DASH_LAST_IP_CSV="${last_ip_csv}"
            DASH_LAST_ERROR="${last_error}"
        fi
    done < "${STATS_FILE}"
}

cron_status_summary() {
    local begin end line in_block=0 found=0 cron_line="" count=0
    begin="$(cron_begin_marker)"
    end="$(cron_end_marker)"
    if ! have_cmd crontab; then
        printf 'crontab 不可用'
        return 0
    fi
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
            [[ -n "${line}" ]] || continue
            count=$((count + 1))
            if [[ -z "${cron_line}" ]]; then
                cron_line="${line}"
            else
                cron_line="${cron_line} ; ${line}"
            fi
        fi
    done < <(crontab -l 2>/dev/null || true)
    if [[ "${found}" == "1" ]]; then
        printf '已安装 %s 条：%s' "${count}" "${cron_line:-本脚本管理的 Worker 轮询器}"
    else
        printf '未安装'
    fi
}

remote_resource_task_cron_status() {
    local host="$1"
    local port="$2"
    local user="$3"
    local script="$4"
    local extra="$5"
    local response line key value status="unknown" detail="未读取到 PO0 状态"
    local timeout rc
    timeout="$(timeout_seconds "${REMOTE_STATUS_TIMEOUT_SECONDS}" 8)"
    response="$(remote_manager_call_timeout "${timeout}" "${host}" "${port}" "${user}" "${script}" "${extra}" --resource-task-cron-status 2>&1)"
    rc=$?
    if [[ "${rc}" -ne 0 ]]; then
        if [[ "${rc}" == "124" ]]; then
            response="远端查询超时（${timeout} 秒）"
        elif [[ "${response}" == *"action --resource-task-cron-status not allowed for scope worker"* ]]; then
            response="PO0 受限 SSH wrapper 未刷新；请在 PO0 上执行：bash ${script} --refresh-report-key-wrapper"
        fi
        printf '查询失败|%s\n' "$(sanitize_field "${response}")"
        return 1
    fi
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ "${line}" == *=* ]] || continue
        key="${line%%=*}"
        value="${line#*=}"
        case "${key}" in
            STATUS) status="${value}" ;;
            DETAIL) detail="${value}" ;;
        esac
    done <<< "${response}"
    case "${status}" in
        installed) printf '已安装|%s\n' "${detail}" ;;
        missing) printf '未安装|PO0 尚未设置资源任务定时创建\n' ;;
        unavailable) printf '不可用|%s\n' "${detail}" ;;
        *) printf '未知|%s\n' "${detail}" ;;
    esac
}

show_remote_resource_task_cron_status() {
    local line any=0 status detail label
    ensure_config_file || return 1
    print_panel_section "PO0 资源更新计划"
    print_panel_row "读取模式" "只读"
    print_panel_row "说明" "显示 PO0 何时自动生成 iplist/ipdb 更新任务；本机 Worker 只领取并执行"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        [[ "${TARGET_ENABLED}" == "1" && -n "${TARGET_RESOURCE_TOKEN}" ]] || continue
        any=1
        label="${TARGET_LABEL:-${TARGET_PO0_HOST}}"
        if IFS='|' read -r status detail < <(remote_resource_task_cron_status \
            "${TARGET_PO0_HOST}" \
            "${TARGET_PO0_PORT:-22}" \
            "${TARGET_PO0_USER:-root}" \
            "${TARGET_PO0_SCRIPT:-${DEFAULT_PO0_SCRIPT}}" \
            "${TARGET_SSH_EXTRA_ARGS}"); then
            print_panel_row "${label}" "${status} - ${detail}"
        else
            print_panel_row "${label}" "${status:-查询失败} - ${detail:-无法连接 PO0}"
        fi
    done < "${CONFIG_FILE}"
    [[ "${any}" == "1" ]] || print_panel_row "目标" "没有启用的资源任务目标"
}

print_dashboard() {
    local line total=0 enabled=0 ddns=0 resource=0 self_report=0 webauth=0 disabled=0
    ensure_config_file || return 1
    refresh_stats_file
    refresh_resource_stats_file
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        total=$((total + 1))
        if [[ "${TARGET_ENABLED}" == "1" ]]; then
            enabled=$((enabled + 1))
        else
            disabled=$((disabled + 1))
        fi
        [[ "${TARGET_REPORT_MODE}" == "ddns" && -n "${TARGET_DOMAIN}" && -n "${TARGET_DDNS_RESOLVE_DOMAIN}" ]] && ddns=$((ddns + 1))
        [[ -n "${TARGET_RESOURCE_TOKEN}" ]] && resource=$((resource + 1))
        [[ -n "${TARGET_CLIENT_IP_TOKEN}" ]] && self_report=$((self_report + 1))
        [[ -n "${TARGET_WEBAUTH_TOKEN}" ]] && webauth=$((webauth + 1))
    done < "${CONFIG_FILE}"
    dashboard_stat_totals
    print_title "PO0 内网 Worker"
    print_panel_section "基础信息"
    print_panel_row "脚本名称" "${SCRIPT_NAME}"
    print_panel_row "当前脚本" "$(script_source_path)"
    print_panel_row "版本" "${SCRIPT_VERSION}"
    print_panel_row "发布日期" "${SCRIPT_RELEASE_DATE}"
    print_panel_row "资源上传" "$(resource_upload_mode_label)"
    print_panel_row "配置文件" "${CONFIG_FILE}"
    print_panel_row "统计文件" "${STATS_FILE}"
    print_panel_row "资源统计" "${RESOURCE_STATS_FILE}"
    print_panel_row "资源事件" "${RESOURCE_EVENTS_FILE:-$(path_dirname "${CONFIG_FILE}")/resource-events.tsv}"
    print_panel_row "Worker ID" "${WORKER_ID}"

    print_panel_section "目标概览"
    print_panel_row "目标数量" "总计 ${total}，启用 ${enabled}，停用 ${disabled}"
    print_panel_row "资源任务" "${resource} 个目标（PO0 创建计划，本机只轮询领取）"
    print_panel_row "DDNS 上报" "${ddns} 个目标"
    print_panel_row "自上报" "${self_report} 个目标，监听 ${SELF_REPORT_LISTEN}"
    print_panel_row "WebAuth" "${webauth} 个目标，监听 ${WEBAUTH_LISTEN}"
    print_panel_row "本机轮询器" "$(cron_status_summary)"

    print_panel_section "最近 DDNS 统计"
    print_panel_row "汇总" "成功=${DASH_SUCCESS_TOTAL} 失败=${DASH_FAIL_TOTAL} 最近=${DASH_LAST_AT:-无} 状态=${DASH_LAST_STATUS:-无} IP=${DASH_LAST_IP_CSV:-无}"
    [[ -n "${DASH_LAST_ERROR}" && "${DASH_LAST_ERROR}" != "无" ]] && print_panel_row "最近错误" "${DASH_LAST_ERROR}"

    print_panel_section "链路提示"
    print_panel_action "WebAuth" "Cloudflare Access/Tunnel -> LAN Worker -> SSH -> PO0"
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
    ssh_extra_args="$(prompt_ssh_extra_args "额外 SSH 参数，可空（不是私钥短语；例如 -J jump-host 或 -o StrictHostKeyChecking=accept-new）" "${SSH_EXTRA_ARGS}" "${po0_host}" "${po0_port}" "${po0_user}")" || return 1
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
            printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
                "${TARGET_ENABLED}" "${TARGET_LABEL}" "${TARGET_DOMAIN}" "${TARGET_REPORT_KEY}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT}" "${TARGET_PO0_USER}" "${TARGET_PO0_SCRIPT}" "${TARGET_TOKEN}" "${TARGET_SSH_EXTRA_ARGS}" "${TARGET_RESOURCE_TOKEN}" "${TARGET_REPORT_MODE}" "${TARGET_DDNS_RESOLVE_DOMAIN}" "${TARGET_CLIENT_IP_TOKEN}" "${TARGET_CLIENT_IP_SOURCE}" "${TARGET_CLIENT_IP_TTL}" "${TARGET_WEBAUTH_TOKEN}" "${TARGET_WEBAUTH_SOURCE}" "${TARGET_WEBAUTH_TTL}" "${TARGET_REPORT_SSH_EXTRA_ARGS}" >> "${tmp}"
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
    if ! choice="$(read_prompt "请选择目标 [1-${count}]: ")"; then
        printf '\n输入结束，取消选择。\n'
        return 1
    fi
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
    local client_ip_token client_ip_source client_ip_ttl webauth_token webauth_source webauth_ttl report_ssh_extra_args
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
            client_ip_token="${TARGET_CLIENT_IP_TOKEN}"
            client_ip_source="${TARGET_CLIENT_IP_SOURCE}"
            client_ip_ttl="${TARGET_CLIENT_IP_TTL}"
            webauth_token="${TARGET_WEBAUTH_TOKEN}"
            webauth_source="${TARGET_WEBAUTH_SOURCE}"
            webauth_ttl="${TARGET_WEBAUTH_TTL}"
            report_ssh_extra_args="${TARGET_REPORT_SSH_EXTRA_ARGS}"
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
    ssh_extra_args="$(prompt_ssh_extra_args "额外 SSH 参数，可空（不是私钥短语；例如 -J jump-host 或 -o StrictHostKeyChecking=accept-new）" "${ssh_extra_args}" "${po0_host}" "${po0_port}" "${po0_user}")" || return 1
    [[ -n "${domain}" ]] || report_key=""
    [[ -n "${po0_host}" && ( -n "${domain}" || -n "${resource_token}" ) ]] || {
        printf 'PO0 SSH 地址不能为空；PO0 来源 key 和资源任务 Token 不能同时为空。\n' >&2
        return 1
    }
    [[ "${report_mode}" != "ddns" || -n "${ddns_resolve_domain}" ]] || {
        printf 'DDNS resolver 模式必须填写 DDNS 域名。\n' >&2
        return 1
    }
    ssh_extra_args="$(ssh_extra_without_private_key_text "${ssh_extra_args}")"
    report_ssh_extra_args="$(ssh_extra_without_private_key_text "${report_ssh_extra_args}")"

    tmp="${CONFIG_FILE}.tmp.$$"
    idx=0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if ! parse_target_line "${line}"; then
            printf '%s\n' "${line}" >> "${tmp}"
            continue
        fi
        ((idx++))
        if [[ "${idx}" == "${selected}" ]]; then
            printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
                "${enabled}" "$(sanitize_field "${label}")" "$(sanitize_field "${domain}")" "$(sanitize_field "${report_key}")" \
                "$(sanitize_field "${po0_host}")" "$(sanitize_field "${po0_port}")" "$(sanitize_field "${po0_user}")" \
                "$(sanitize_field "${po0_script}")" "$(sanitize_field "${token}")" "$(sanitize_field "${ssh_extra_args}")" \
                "$(sanitize_field "${resource_token}")" "$(sanitize_field "${report_mode}")" "$(sanitize_field "${ddns_resolve_domain}")" \
                "$(sanitize_field "${client_ip_token}")" "$(sanitize_field "${client_ip_source}")" "$(sanitize_field "${client_ip_ttl}")" \
                "$(sanitize_field "${webauth_token}")" "$(sanitize_field "${webauth_source}")" "$(sanitize_field "${webauth_ttl}")" \
                "$(sanitize_field "${report_ssh_extra_args}")" >> "${tmp}"
            continue
        fi
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${CONFIG_FILE}"
    replace_config_from_tmp "${tmp}"
    prune_stats_to_current_targets || true
    printf '已更新目标 %s。\n' "${selected}"
}

update_target_ssh_args_by_index() {
    local selected="$1"
    local new_extra="$2"
    local old_extra="$3"
    local update_report_extra="${4:-0}"
    local line idx=0 tmp
    ensure_config_file || return 1
    tmp="${CONFIG_FILE}.tmp.$$"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if ! parse_target_line "${line}"; then
            printf '%s\n' "${line}" >> "${tmp}"
            continue
        fi
        ((idx++))
        if [[ "${idx}" == "${selected}" ]]; then
            TARGET_SSH_EXTRA_ARGS="$(sanitize_field "$(ssh_extra_without_private_key_text "${new_extra}")")"
            if [[ "${update_report_extra}" == "1" || -z "${TARGET_REPORT_SSH_EXTRA_ARGS}" || "${TARGET_REPORT_SSH_EXTRA_ARGS}" == "${old_extra}" ]]; then
                TARGET_REPORT_SSH_EXTRA_ARGS="${TARGET_SSH_EXTRA_ARGS}"
            else
                TARGET_REPORT_SSH_EXTRA_ARGS="$(sanitize_field "$(ssh_extra_without_private_key_text "${TARGET_REPORT_SSH_EXTRA_ARGS}")")"
            fi
        fi
        printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
            "${TARGET_ENABLED}" "${TARGET_LABEL}" "${TARGET_DOMAIN}" "${TARGET_REPORT_KEY}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT}" "${TARGET_PO0_USER}" "${TARGET_PO0_SCRIPT}" "${TARGET_TOKEN}" "${TARGET_SSH_EXTRA_ARGS}" "${TARGET_RESOURCE_TOKEN}" "${TARGET_REPORT_MODE}" "${TARGET_DDNS_RESOLVE_DOMAIN}" "${TARGET_CLIENT_IP_TOKEN}" "${TARGET_CLIENT_IP_SOURCE}" "${TARGET_CLIENT_IP_TTL}" "${TARGET_WEBAUTH_TOKEN}" "${TARGET_WEBAUTH_SOURCE}" "${TARGET_WEBAUTH_TTL}" "${TARGET_REPORT_SSH_EXTRA_ARGS}" >> "${tmp}"
    done < "${CONFIG_FILE}"
    replace_config_from_tmp "${tmp}"
}

manage_target_ssh_interactive() {
    local selected line idx=0 choice key_path new_key_path extra old_extra new_extra current_report_extra update_report_extra=0
    local po0_host po0_port po0_user
    select_target_index || return 1
    selected="${SELECTED_TARGET_INDEX}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        ((idx++))
        if [[ "${idx}" == "${selected}" ]]; then
            po0_host="${TARGET_PO0_HOST}"
            po0_port="${TARGET_PO0_PORT:-22}"
            po0_user="${TARGET_PO0_USER:-root}"
            extra="${TARGET_SSH_EXTRA_ARGS}"
            current_report_extra="${TARGET_REPORT_SSH_EXTRA_ARGS}"
            break
        fi
    done < "${CONFIG_FILE}"
    [[ -n "${po0_host:-}" ]] || return 1
    old_extra="${extra}"
    key_path="$(ssh_extra_identity_path "${extra}" 2>/dev/null || true)"

    while true; do
        menu_clear_screen
        printf '\n目标 SSH 连接配置：%s@%s:%s\n' "${po0_user}" "${po0_host}" "${po0_port}"
        printf '当前私钥路径：%s\n' "${key_path:-未单独指定，使用系统默认 SSH 配置/agent}"
        printf '当前额外 SSH 参数：%s\n' "${extra:-无}"
        if [[ -n "${current_report_extra}" && "${current_report_extra}" != "${extra}" ]]; then
            printf 'Self-report/WebAuth 上报 SSH 参数覆盖：%s\n' "${current_report_extra}"
        fi
        print_menu_item 1 "设置 / 更换私钥路径"
        print_menu_item 2 "粘贴私钥并保存到本机"
        print_menu_item 3 "清除私钥路径（保留其它 SSH 参数）"
        print_menu_item 4 "编辑额外 SSH 参数（不是私钥短语）"
        print_menu_item 0 "返回"
        print_menu_footer
        read_menu_choice_or_return choice "请选择操作 [0-4]: " || return 2
        case "${choice}" in
            1)
                new_key_path="$(prompt_ssh_key_path_or_paste "SSH 私钥路径（路径不要含空格；如要粘贴私钥请选 2）" "${key_path}" "${po0_host}" "${po0_port}" "${po0_user}")"
                new_extra="$(ssh_extra_with_identity "${extra}" "${new_key_path}")"
                break
                ;;
            2)
                new_key_path="$(save_pasted_ssh_key "${po0_host}" "${po0_port}" "${po0_user}")" || return 1
                printf '[OK] 已保存 SSH 私钥：%s\n' "${new_key_path}"
                new_extra="$(ssh_extra_with_identity "${extra}" "${new_key_path}")"
                break
                ;;
            3)
                new_extra="$(ssh_extra_without_identity "${extra}")"
                break
                ;;
            4)
                new_extra="$(prompt_ssh_extra_args "额外 SSH 参数，例如 -J jump-host 或 -o StrictHostKeyChecking=accept-new" "${extra}" "${po0_host}" "${po0_port}" "${po0_user}")" || return 1
                break
                ;;
            0)
                return 2
                ;;
            "")
                ;;
            *)
                printf '无效选择。\n' >&2
                pause_before_return
                ;;
        esac
    done
    if [[ -n "${current_report_extra}" && "${current_report_extra}" != "${old_extra}" ]]; then
        prompt_yes_no "Self-report/WebAuth 上报 SSH 参数有单独覆盖，是否同步更新" "n" && update_report_extra=1
    fi
    update_target_ssh_args_by_index "${selected}" "${new_extra}" "${old_extra}" "${update_report_extra}" || return 1
    printf '已更新目标 %s 的 SSH 连接配置。\n' "${selected}"
}

update_target_tokens_by_index() {
    local selected="$1"
    local ddns_token="$2"
    local resource_token="$3"
    local client_ip_token="$4"
    local webauth_token="$5"
    local line idx=0 tmp
    ensure_config_file || return 1
    tmp="${CONFIG_FILE}.tmp.$$"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if ! parse_target_line "${line}"; then
            printf '%s\n' "${line}" >> "${tmp}"
            continue
        fi
        ((idx++))
        if [[ "${idx}" == "${selected}" ]]; then
            TARGET_TOKEN="$(sanitize_field "${ddns_token}")"
            TARGET_RESOURCE_TOKEN="$(sanitize_field "${resource_token}")"
            TARGET_CLIENT_IP_TOKEN="$(sanitize_field "${client_ip_token}")"
            TARGET_WEBAUTH_TOKEN="$(sanitize_field "${webauth_token}")"
        fi
        printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
            "${TARGET_ENABLED}" "${TARGET_LABEL}" "${TARGET_DOMAIN}" "${TARGET_REPORT_KEY}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT}" "${TARGET_PO0_USER}" "${TARGET_PO0_SCRIPT}" "${TARGET_TOKEN}" "${TARGET_SSH_EXTRA_ARGS}" "${TARGET_RESOURCE_TOKEN}" "${TARGET_REPORT_MODE}" "${TARGET_DDNS_RESOLVE_DOMAIN}" "${TARGET_CLIENT_IP_TOKEN}" "${TARGET_CLIENT_IP_SOURCE}" "${TARGET_CLIENT_IP_TTL}" "${TARGET_WEBAUTH_TOKEN}" "${TARGET_WEBAUTH_SOURCE}" "${TARGET_WEBAUTH_TTL}" "${TARGET_REPORT_SSH_EXTRA_ARGS}" >> "${tmp}"
    done < "${CONFIG_FILE}"
    replace_config_from_tmp "${tmp}"
}

manage_target_tokens_interactive() {
    local selected line idx=0
    local ddns_token resource_token client_ip_token webauth_token
    select_target_index || return 1
    selected="${SELECTED_TARGET_INDEX}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        ((idx++))
        if [[ "${idx}" == "${selected}" ]]; then
            ddns_token="${TARGET_TOKEN}"
            resource_token="${TARGET_RESOURCE_TOKEN}"
            client_ip_token="${TARGET_CLIENT_IP_TOKEN}"
            webauth_token="${TARGET_WEBAUTH_TOKEN}"
            break
        fi
    done < "${CONFIG_FILE}"
    printf '\n目标 Token 维护；直接回车保留当前值，输入 - 可清空。\n'
    ddns_token="$(prompt_default "DDNS 来源上报 Token" "${ddns_token}")"
    resource_token="$(prompt_default "资源任务 Token" "${resource_token}")"
    client_ip_token="$(prompt_default "Self-report client-ip Token" "${client_ip_token}")"
    webauth_token="$(prompt_default "WebAuth Token" "${webauth_token}")"
    [[ "${ddns_token}" == "-" ]] && ddns_token=""
    [[ "${resource_token}" == "-" ]] && resource_token=""
    [[ "${client_ip_token}" == "-" ]] && client_ip_token=""
    [[ "${webauth_token}" == "-" ]] && webauth_token=""
    update_target_tokens_by_index "${selected}" "${ddns_token}" "${resource_token}" "${client_ip_token}" "${webauth_token}" || return 1
    printf '已更新目标 %s 的 Token。\n' "${selected}"
}

update_target_report_ttl_by_index() {
    local selected="$1"
    local client_ip_source="$2"
    local client_ip_ttl="$3"
    local webauth_source="$4"
    local webauth_ttl="$5"
    local line idx=0 tmp
    ensure_config_file || return 1
    tmp="${CONFIG_FILE}.tmp.$$"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if ! parse_target_line "${line}"; then
            printf '%s\n' "${line}" >> "${tmp}"
            continue
        fi
        ((idx++))
        if [[ "${idx}" == "${selected}" ]]; then
            TARGET_CLIENT_IP_SOURCE="$(sanitize_field "${client_ip_source}")"
            TARGET_CLIENT_IP_TTL="$(sanitize_field "${client_ip_ttl}")"
            TARGET_WEBAUTH_SOURCE="$(sanitize_field "${webauth_source}")"
            TARGET_WEBAUTH_TTL="$(sanitize_field "${webauth_ttl}")"
        fi
        printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
            "${TARGET_ENABLED}" "${TARGET_LABEL}" "${TARGET_DOMAIN}" "${TARGET_REPORT_KEY}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT}" "${TARGET_PO0_USER}" "${TARGET_PO0_SCRIPT}" "${TARGET_TOKEN}" "${TARGET_SSH_EXTRA_ARGS}" "${TARGET_RESOURCE_TOKEN}" "${TARGET_REPORT_MODE}" "${TARGET_DDNS_RESOLVE_DOMAIN}" "${TARGET_CLIENT_IP_TOKEN}" "${TARGET_CLIENT_IP_SOURCE}" "${TARGET_CLIENT_IP_TTL}" "${TARGET_WEBAUTH_TOKEN}" "${TARGET_WEBAUTH_SOURCE}" "${TARGET_WEBAUTH_TTL}" "${TARGET_REPORT_SSH_EXTRA_ARGS}" >> "${tmp}"
    done < "${CONFIG_FILE}"
    replace_config_from_tmp "${tmp}"
}

manage_target_report_ttl_interactive() {
    local selected line idx=0
    local client_ip_source client_ip_ttl webauth_source webauth_ttl
    select_target_index || return 1
    selected="${SELECTED_TARGET_INDEX}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        ((idx++))
        if [[ "${idx}" == "${selected}" ]]; then
            client_ip_source="${TARGET_CLIENT_IP_SOURCE}"
            client_ip_ttl="${TARGET_CLIENT_IP_TTL}"
            webauth_source="${TARGET_WEBAUTH_SOURCE}"
            webauth_ttl="${TARGET_WEBAUTH_TTL}"
            break
        fi
    done < "${CONFIG_FILE}"
    printf '\nSelf-report / WebAuth source 与 TTL 维护；直接回车保留当前值，输入 - 可清空目标覆盖。\n'
    client_ip_source="$(prompt_default "Self-report source id" "${client_ip_source:-${SELF_REPORT_SOURCE}}")"
    client_ip_ttl="$(prompt_default "Self-report 放行 TTL 秒数" "${client_ip_ttl:-${SELF_REPORT_TTL_SECONDS:-3600}}")"
    webauth_source="$(prompt_default "WebAuth source id" "${webauth_source:-${WEBAUTH_SOURCE}}")"
    webauth_ttl="$(prompt_default "WebAuth 放行 TTL 秒数" "${webauth_ttl:-${WEBAUTH_TTL_SECONDS:-3600}}")"
    [[ "${client_ip_source}" == "-" ]] && client_ip_source=""
    [[ "${client_ip_ttl}" == "-" ]] && client_ip_ttl=""
    [[ "${webauth_source}" == "-" ]] && webauth_source=""
    [[ "${webauth_ttl}" == "-" ]] && webauth_ttl=""
    if [[ -n "${client_ip_ttl}" && ! "${client_ip_ttl}" =~ ^[0-9]+$ ]]; then
        printf 'Self-report TTL 必须是秒数，或输入 - 清空目标覆盖。\n' >&2
        return 1
    fi
    if [[ -n "${webauth_ttl}" && ! "${webauth_ttl}" =~ ^[0-9]+$ ]]; then
        printf 'WebAuth TTL 必须是秒数，或输入 - 清空目标覆盖。\n' >&2
        return 1
    fi
    update_target_report_ttl_by_index "${selected}" "${client_ip_source}" "${client_ip_ttl}" "${webauth_source}" "${webauth_ttl}" || return 1
    printf '已更新目标 %s 的 Self-report / WebAuth source 与 TTL。\n' "${selected}"
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

    ssh_args+=(-n -p "${po0_port}")
    sanitize_ssh_extra_args "${ssh_extra_args}" "DDNS ${source_key}@${po0_host}:${po0_port}"
    ssh_args+=("${SSH_EXTRA_ARGV[@]}")

    printf '上报：DDNS %s -> %s -> %s@%s:%s，来源=%s\n' "${resolve_domain}" "${ip_csv}" "${po0_user}" "${po0_host}" "${po0_port}" "${report_key}"
    if ! ssh "${ssh_args[@]}" "${po0_user}@${po0_host}" "${remote_cmd}"; then
        printf '上报失败：%s -> %s\n' "${source_key}" "${po0_host}" >&2
        update_target_stats "${target_id}" "失败" "${ip_csv}" "SSH 或 PO0 上报命令失败" || true
        return 1
    fi
    update_target_stats "${target_id}" "成功" "${ip_csv}" "" || true
}

run_ddns_target_lines() {
    local raw="$1" line source_key resolve_domain host port user script token extra ok=0 fail=0 skipped=0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="$(trim "${line}")"
        [[ -n "${line}" && ! "${line}" == \#* ]] || continue
        IFS='|' read -r source_key resolve_domain host port user script token extra <<< "${line}"
        source_key="$(sanitize_field "${source_key}")"
        resolve_domain="$(sanitize_field "${resolve_domain}")"
        host="$(sanitize_field "${host}")"
        port="$(sanitize_field "${port:-22}")"
        user="$(sanitize_field "${user:-root}")"
        script="$(sanitize_field "${script:-${DEFAULT_PO0_SCRIPT}}")"
        token="$(sanitize_field "${token}")"
        extra="$(sanitize_field "${extra:-}")"
        if [[ -z "${source_key}" || -z "${resolve_domain}" || -z "${host}" ]]; then
            printf '跳过无效 DDNS 上报目标：%s\n' "${line}" >&2
            skipped=$((skipped + 1))
            continue
        fi
        if report_once "${source_key}" "${source_key}" "${resolve_domain}" "${host}" "${port:-22}" "${user:-root}" "${script:-${DEFAULT_PO0_SCRIPT}}" "${token}" "${extra}"; then
            ok=$((ok + 1))
        else
            fail=$((fail + 1))
        fi
    done < <(printf '%s\n' "${raw}" | tr ';' '\n')
    printf 'DDNS 临时上报目标执行完成：成功 %s，失败 %s，跳过 %s。\n' "${ok}" "${fail}" "${skipped}"
    [[ "${fail}" == "0" ]]
}

remote_manager_call() {
    local host="$1"
    local port="$2"
    local user="$3"
    local script="$4"
    local extra="$5"
    shift 5
    local remote_cmd arg
    local -a ssh_args=(-n -p "${port:-22}")
    [[ -n "${user}" ]] || user="root"
    [[ -n "${script}" ]] || script="${DEFAULT_PO0_SCRIPT}"
    sanitize_ssh_extra_args "${extra}" "PO0 manager ${user}@${host}:${port:-22}"
    ssh_args+=("${SSH_EXTRA_ARGV[@]}")
    remote_cmd="bash $(sh_quote "${script}")"
    for arg in "$@"; do
        remote_cmd+=" $(sh_quote "${arg}")"
    done
    ssh "${ssh_args[@]}" "${user}@${host}" "${remote_cmd}"
}

remote_manager_call_timeout() {
    local seconds="$1"
    local host="$2"
    local port="$3"
    local user="$4"
    local script="$5"
    local extra="$6"
    shift 6
    local remote_cmd arg
    local -a ssh_args=(-n -p "${port:-22}")
    [[ -n "${user}" ]] || user="root"
    [[ -n "${script}" ]] || script="${DEFAULT_PO0_SCRIPT}"
    sanitize_ssh_extra_args "${extra}" "PO0 manager ${user}@${host}:${port:-22}"
    ssh_args+=("${SSH_EXTRA_ARGV[@]}")
    remote_cmd="bash $(sh_quote "${script}")"
    for arg in "$@"; do
        remote_cmd+=" $(sh_quote "${arg}")"
    done
    run_with_optional_timeout "$(timeout_seconds "${seconds}" 8)" ssh "${ssh_args[@]}" "${user}@${host}" "${remote_cmd}"
}

fetch_worker_token_bundle() {
    local ensure_resource="${1:-0}"
    local response line key value
    if [[ "${ensure_resource}" == "1" ]]; then
        response="$(remote_manager_call "${PO0_HOST}" "${PO0_PORT}" "${PO0_USER}" "${PO0_SCRIPT}" "${SSH_EXTRA_ARGS}" --worker-token-bundle --ensure-resource-token)" || return 1
    else
        response="$(remote_manager_call "${PO0_HOST}" "${PO0_PORT}" "${PO0_USER}" "${PO0_SCRIPT}" "${SSH_EXTRA_ARGS}" --worker-token-bundle)" || return 1
    fi
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ "${line}" == *=* ]] || continue
        key="${line%%=*}"
        value="${line#*=}"
        case "${key}" in
            DDNS_TOKEN) DDNS_TOKEN="${value}" ;;
            RESOURCE_TOKEN) RESOURCE_TOKEN="${value}" ;;
            CLIENT_IP_TOKEN) CLIENT_IP_TOKEN="${value}" ;;
            WEBAUTH_TOKEN) WEBAUTH_TOKEN="${value}" ;;
        esac
    done <<< "${response}"
}

po0_lan_wizard() {
    local key_path extra ssh_response ssh_ok=0
    local use_resource=0 use_ddns=0 use_self_report=0 use_webauth=0
    local label install_periodic=0 ddns_cron_minutes resource_cron_minutes run_now=0 script_path
    local generated_secret

    print_title "PO0 LAN Worker 安装向导"
    printf '此向导会把 token 明文保存到本机配置文件：%s\n' "${CONFIG_FILE}"
    printf 'PO0 自动取 token 需要当前机器已经可以通过密钥 SSH 登录 PO0。\n\n'

    PO0_HOST="$(prompt_default "PO0 SSH 地址" "${PO0_HOST}")"
    [[ -n "${PO0_HOST}" ]] || { printf 'PO0 SSH 地址不能为空。\n' >&2; return 1; }
    PO0_PORT="$(prompt_default "PO0 SSH 端口" "${PO0_PORT:-22}")"
    PO0_USER="$(prompt_default "PO0 SSH 用户" "${PO0_USER:-root}")"
    PO0_SCRIPT="$(prompt_default "PO0 管理脚本路径" "${PO0_SCRIPT:-${DEFAULT_PO0_SCRIPT}}")"
    print_menu_section "SSH 认证方式"
    print_menu_item 1 "使用系统默认 SSH 配置 / agent"
    print_menu_item 2 "填写私钥文件路径"
    print_menu_item 3 "粘贴私钥并保存到本机"
    print_menu_footer
    case "$(prompt_default "请选择" "1")" in
        2)
            key_path="$(prompt_ssh_key_path_or_paste "SSH 私钥路径（路径不要含空格）" "" "${PO0_HOST}" "${PO0_PORT}" "${PO0_USER}")"
            ;;
        3)
            key_path="$(save_pasted_ssh_key "${PO0_HOST}" "${PO0_PORT}" "${PO0_USER}")" || return 1
            printf '[OK] 已保存 SSH 私钥：%s\n' "${key_path}"
            ;;
        *)
            key_path=""
            ;;
    esac
    extra="$(prompt_ssh_extra_args "额外 SSH 参数，可空（不是私钥短语；例如 -J jump-host 或 -o StrictHostKeyChecking=accept-new）" "${SSH_EXTRA_ARGS}" "${PO0_HOST}" "${PO0_PORT}" "${PO0_USER}")" || return 1
    SSH_EXTRA_ARGS="$(build_batchmode_ssh_extra_args "${key_path}" "${extra}")" || return 1

    printf '\n检查密钥 SSH 和 PO0 管理脚本...\n'
    if ssh_response="$(remote_manager_call "${PO0_HOST}" "${PO0_PORT}" "${PO0_USER}" "${PO0_SCRIPT}" "${SSH_EXTRA_ARGS}" --help 2>&1)"; then
        ssh_ok=1
        printf '[OK] SSH 可用：%s@%s:%s\n' "${PO0_USER}" "${PO0_HOST}" "${PO0_PORT}"
    else
        printf '[WARN] 密钥 SSH 检查失败：%s\n' "${ssh_response}" >&2
        print_host_key_failure_help "${PO0_HOST}" "${PO0_PORT}" "${PO0_USER}" "${ssh_response}"
        printf '可以继续手动粘贴 token 并保存配置，但不要安装本机 Worker 轮询器或 service，直到免密 SSH 可用。\n' >&2
    fi

    print_menu_section "本机角色"
    prompt_yes_no "启用资源任务 Worker（领取 PO0 的 iplist/ipdb 更新任务）" "y" && use_resource=1
    prompt_yes_no "启用 DDNS resolver（本机解析 DDNS 后 SSH 上报 PO0）" "y" && use_ddns=1
    prompt_yes_no "启用 Self-report server 目标配置（访问设备先报本机，再由本机报 PO0）" "n" && use_self_report=1
    prompt_yes_no "启用 WebAuth server 目标配置（本机接收认证入口，再由本机报 PO0）" "n" && use_webauth=1

    if (( use_resource == 0 && use_ddns == 0 && use_self_report == 0 && use_webauth == 0 )); then
        printf '至少需要选择一个角色。\n' >&2
        return 1
    fi

    if (( ssh_ok == 1 )); then
        if fetch_worker_token_bundle "${use_resource}" 2>/dev/null; then
            printf '[OK] 已从 PO0 自动读取所需 token。\n'
        else
            printf '[WARN] SSH 可用，但未能自动读取 token；稍后请手动粘贴需要的 token。\n' >&2
        fi
    fi

    if (( use_ddns == 1 )); then
        REPORT_MODE="ddns"
        DDNS_RESOLVE_DOMAIN="$(prompt_default "LAN Worker 要解析的 DDNS 域名" "${DDNS_RESOLVE_DOMAIN:-${DDNS_DOMAIN}}")"
        [[ -n "${DDNS_RESOLVE_DOMAIN}" ]] || { printf 'DDNS resolver 必须填写 DDNS 域名。\n' >&2; return 1; }
        DDNS_DOMAIN="$(prompt_default "PO0 来源 key（默认同 DDNS 域名）" "${DDNS_DOMAIN:-${DDNS_RESOLVE_DOMAIN}}")"
        REPORT_KEY="$(prompt_default "PO0 匹配 key（默认同来源 key）" "${REPORT_KEY:-${DDNS_DOMAIN}}")"
        DDNS_TOKEN="$(prompt_default "DDNS 来源上报 token" "${DDNS_TOKEN}")"
        [[ -n "${DDNS_TOKEN}" ]] || { printf 'DDNS resolver 需要 DDNS token。\n' >&2; return 1; }
    else
        REPORT_MODE="none"
        DDNS_DOMAIN=""
        REPORT_KEY=""
        DDNS_RESOLVE_DOMAIN=""
    fi

    if (( use_resource == 1 )); then
        RESOURCE_TOKEN="$(prompt_default "资源任务 Token" "${RESOURCE_TOKEN}")"
        [[ -n "${RESOURCE_TOKEN}" ]] || { printf '资源任务 Worker 需要 resource token。\n' >&2; return 1; }
    else
        RESOURCE_TOKEN=""
    fi

    if (( use_self_report == 1 )); then
        CLIENT_IP_TOKEN="$(prompt_default "Client IP 上报 token" "${CLIENT_IP_TOKEN}")"
        [[ -n "${CLIENT_IP_TOKEN}" ]] || { printf 'Self-report 需要 client-ip token。\n' >&2; return 1; }
        SELF_REPORT_SOURCE="$(prompt_default "Self-report source id" "${SELF_REPORT_SOURCE:-self-report}")"
        if prompt_yes_no "使用 Self-report HTTPS 域名 / Caddy（推荐；DNS 需已指向本机）" "y"; then
            SELF_REPORT_HTTPS_DOMAIN="$(prompt_default "Self-report HTTPS 域名" "${SELF_REPORT_HTTPS_DOMAIN}")"
            SELF_REPORT_HTTPS_DOMAIN="$(normalize_self_report_https_domain "${SELF_REPORT_HTTPS_DOMAIN}")"
            validate_self_report_https_domain "${SELF_REPORT_HTTPS_DOMAIN}" || return 1
            SELF_REPORT_LISTEN="${SELF_REPORT_HTTPS_BACKEND}"
        else
            SELF_REPORT_LISTEN="$(prompt_default "Self-report 本地监听地址（HTTP 直连，不推荐公网暴露）" "${SELF_REPORT_LISTEN:-127.0.0.1:8788}")"
        fi
        generated_secret="$(random_secret)"
        SELF_REPORT_SECRET="$(prompt_default "Self-report secret（访问设备上报 LAN Worker 用）" "${SELF_REPORT_SECRET:-${generated_secret}}")"
        SELF_REPORT_TTL_SECONDS="$(prompt_default "Self-report 放行 TTL 秒数" "${SELF_REPORT_TTL_SECONDS:-3600}")"
    else
        CLIENT_IP_TOKEN=""
    fi

    if (( use_webauth == 1 )); then
        WEBAUTH_TOKEN="$(prompt_default "WebAuth 上报 token" "${WEBAUTH_TOKEN}")"
        [[ -n "${WEBAUTH_TOKEN}" ]] || { printf 'WebAuth 需要 webauth token。\n' >&2; return 1; }
        WEBAUTH_SOURCE="$(prompt_default "WebAuth source id" "${WEBAUTH_SOURCE:-cf-access}")"
        WEBAUTH_LISTEN="$(prompt_default "WebAuth 本地监听地址" "${WEBAUTH_LISTEN:-127.0.0.1:8787}")"
        WEBAUTH_TTL_SECONDS="$(prompt_default "WebAuth 放行 TTL 秒数" "${WEBAUTH_TTL_SECONDS:-3600}")"
    else
        WEBAUTH_TOKEN=""
    fi

    label="$(prompt_default "显示名" "${BOOTSTRAP_LABEL:-${DDNS_DOMAIN:-resource-${PO0_HOST}}}")"
    upsert_target "1" "${label}" "${DDNS_DOMAIN}" "${REPORT_KEY}" "${PO0_HOST}" "${PO0_PORT}" "${PO0_USER}" "${PO0_SCRIPT}" "${DDNS_TOKEN}" "${SSH_EXTRA_ARGS}" "${RESOURCE_TOKEN}" "${REPORT_MODE}" "${DDNS_RESOLVE_DOMAIN}" "${CLIENT_IP_TOKEN}" "${SELF_REPORT_SOURCE}" "${SELF_REPORT_TTL_SECONDS}" "${WEBAUTH_TOKEN}" "${WEBAUTH_SOURCE}" "${WEBAUTH_TTL_SECONDS}" "${SSH_EXTRA_ARGS}" || return 1
    chmod 600 "${CONFIG_FILE}" 2>/dev/null || true
    printf '\n[OK] 已写入配置：%s\n' "${CONFIG_FILE}"
    script_path="$(ensure_persistent_script)" || return 1
    printf '[OK] 已安装本机命令：%s\n' "${script_path}"

    if (( ssh_ok == 1 )); then
        if (( use_ddns == 1 || use_resource == 1 )); then
            probe_worker_target || printf '[WARN] DDNS/资源任务连通性/权限检查未全部通过，请按上方错误修正后再安装本机 Worker 轮询器。\n' >&2
        fi
        (( use_self_report == 1 )) && probe_self_report_target || true
        (( use_webauth == 1 )) && probe_webauth_target || true
    fi

    if (( use_ddns == 1 || use_resource == 1 )); then
        if (( ssh_ok == 1 )); then
            if prompt_yes_no "安装/更新本机 Worker 轮询器（资源创建周期在 PO0 设置）" "y"; then
                install_periodic=1
                if (( use_resource == 1 )); then
                    resource_cron_minutes="$(prompt_default "资源任务每几分钟检查一次（1-${RESOURCE_CRON_MAX_MINUTES}；只领取 PO0 已创建任务）" "${RESOURCE_CRON_MINUTES}")"
                fi
                if (( use_ddns == 1 )); then
                    ddns_cron_minutes="$(prompt_default "DDNS resolver 每几分钟上报一次（1-${DDNS_CRON_MAX_MINUTES}；应小于 PO0 端 DDNS 来源 TTL）" "${DDNS_CRON_MINUTES}")"
                fi
                install_worker_crons "${ddns_cron_minutes:-}" "${resource_cron_minutes:-}" "${script_path}" || return 1
            fi
            prompt_yes_no "现在立即执行一次 DDNS 上报/资源任务轮询" "y" && run_now=1
            (( run_now == 1 )) && run_all_client_jobs
        else
            printf '[WARN] 跳过本机 Worker 轮询器安装：免密 SSH 未通过。\n' >&2
        fi
    fi

    if (( use_self_report == 1 )); then
        if [[ -n "${SELF_REPORT_HTTPS_DOMAIN}" ]]; then
            if prompt_yes_no "安装/更新 Self-report HTTPS/Caddy 和后台服务" "y"; then
                install_self_report_https || return 1
            else
                printf 'Self-report HTTPS 手动安装命令：po0-lan-client --install-self-report-https --self-report-https-domain %s\n' "${SELF_REPORT_HTTPS_DOMAIN}"
            fi
        elif prompt_yes_no "安装/更新 systemd Self-report server 服务（HTTP 直连模式）" "n"; then
            install_self_report_service || return 1
        else
            printf 'Self-report 手动启动命令：po0-lan-client --self-report-server --self-report-listen %s\n' "${SELF_REPORT_LISTEN}"
        fi
    fi

    if (( use_webauth == 1 )); then
        if prompt_yes_no "安装/更新 systemd WebAuth server 服务" "n"; then
            install_webauth_service || return 1
        else
            printf 'WebAuth 手动启动命令：po0-lan-client --webauth-server --listen %s\n' "${WEBAUTH_LISTEN}"
        fi
    fi

    print_title "安装摘要"
    printf '  PO0: %s@%s:%s\n' "${PO0_USER}" "${PO0_HOST}" "${PO0_PORT}"
    printf '  SSH 参数: %s\n' "${SSH_EXTRA_ARGS}"
    printf '  DDNS token: %s\n' "$(mask_secret "${DDNS_TOKEN}")"
    printf '  Resource token: %s\n' "$(mask_secret "${RESOURCE_TOKEN}")"
    printf '  Client IP token: %s\n' "$(mask_secret "${CLIENT_IP_TOKEN}")"
    printf '  WebAuth token: %s\n' "$(mask_secret "${WEBAUTH_TOKEN}")"
    (( install_periodic == 1 )) && printf '  本机 Worker 轮询器: 已安装\n'
    printf '完成。\n'
}

probe_ok() {
    printf '%b[OK]%b %s\n' "${C_GREEN}" "${C_RESET}" "$1"
}

probe_warn() {
    printf '%b[WARN]%b %s\n' "${C_YELLOW}" "${C_RESET}" "$1" >&2
}

probe_fail() {
    printf '%b[FAIL]%b %s\n' "${C_RED}" "${C_RESET}" "$1" >&2
}

probe_client_dependencies() {
    local failed=0
    have_cmd ssh || { probe_fail "缺少 ssh，无法连接 PO0。"; failed=1; }
    if [[ -n "${RESOURCE_TOKEN}" ]]; then
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
        if ! have_cmd xargs; then
            probe_warn "缺少 xargs，iplist txt 下载会退回逐个下载。"
        elif ! xargs_supports_parallel; then
            probe_warn "当前 xargs 不支持并发参数，iplist txt 下载会退回逐个下载。"
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
    if [[ -n "${DDNS_TARGETS}" ]]; then
        run_ddns_target_lines "${DDNS_TARGETS}"
        return $?
    fi
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

resource_endpoint_label() {
    local endpoint_id="$1"
    local host port user line label=""
    IFS=',' read -r host port user <<< "${endpoint_id}"
    host="${host:-}"
    port="${port:-22}"
    user="${user:-root}"
    if [[ -f "${CONFIG_FILE}" ]]; then
        while IFS= read -r line || [[ -n "${line}" ]]; do
            parse_target_line "${line}" || continue
            [[ -n "${TARGET_RESOURCE_TOKEN}" ]] || continue
            if [[ "${TARGET_PO0_HOST}" == "${host}" && "${TARGET_PO0_PORT:-22}" == "${port}" && "${TARGET_PO0_USER:-root}" == "${user}" ]]; then
                label="${TARGET_LABEL:-${TARGET_PO0_HOST}}"
                break
            fi
        done < "${CONFIG_FILE}"
    fi
    if [[ -n "${label}" ]]; then
        printf '%s (%s@%s:%s)\n' "${label}" "${user}" "${host}" "${port}"
    elif [[ -n "${host}" ]]; then
        printf '%s@%s:%s\n' "${user}" "${host}" "${port}"
    else
        printf '%s\n' "${endpoint_id}"
    fi
}

resource_success_rate() {
    local success="${1:-0}" fail="${2:-0}" total
    [[ "${success}" =~ ^[0-9]+$ ]] || success=0
    [[ "${fail}" =~ ^[0-9]+$ ]] || fail=0
    total=$((success + fail))
    if (( total == 0 )); then
        printf 'n/a'
    else
        printf '%s%%' "$(((success * 100) / total))"
    fi
}

short_text() {
    local value="$1"
    local max="${2:-180}"
    if [[ "${#value}" -gt "${max}" ]]; then
        printf '%s...\n' "${value:0:max}"
    else
        printf '%s\n' "${value}"
    fi
}

append_resource_event() {
    local at="$1" endpoint_id="$2" task_id="$3" task_type="$4" status="$5" message="$6"
    ensure_resource_events_file || return 1
    printf '%s|%s|%s|%s|%s|%s\n' \
        "${at}" \
        "$(sanitize_field "${endpoint_id}")" \
        "$(sanitize_field "${task_id:-无}")" \
        "$(sanitize_field "${task_type:-无}")" \
        "$(sanitize_field "${status}")" \
        "$(sanitize_field "${message}")" >> "${RESOURCE_EVENTS_FILE}"
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
    replace_file_from_tmp "${tmp}" "${RESOURCE_STATS_FILE}" || return 1
    append_resource_event "${now}" "${endpoint_id}" "${task_id:-无}" "${task_type:-无}" "${status}" "${message}" || true
}

list_resource_stats() {
    local line endpoint success fail task type status at message count=0 label total rate summary
    ensure_resource_stats_file || return 1
    ensure_resource_events_file || true
    print_panel_section "资源任务汇总"
    print_panel_row "聚合统计" "${RESOURCE_STATS_FILE}"
    print_panel_row "事件日志" "${RESOURCE_EVENTS_FILE}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -n "$(trim "${line}")" && "$(trim "${line}")" != \#* ]] || continue
        IFS='|' read -r endpoint success fail task type status at message <<< "${line}"
        ((count++))
        [[ "${success}" =~ ^[0-9]+$ ]] || success=0
        [[ "${fail}" =~ ^[0-9]+$ ]] || fail=0
        total=$((success + fail))
        rate="$(resource_success_rate "${success}" "${fail}")"
        label="$(resource_endpoint_label "${endpoint}")"
        summary="状态=${status:-未知} 最近=${at:-未知} 成功=${success} 失败=${fail} 成功率=${rate}"
        [[ "${total}" == "0" ]] && summary+="（尚无成功/失败任务）"
        print_panel_row "${label}" "${summary}"
        print_panel_note "任务=${task:-无}/${type:-无}；$(short_text "${message:-无消息}" 160)"
    done < "${RESOURCE_STATS_FILE}"
    [[ "${count}" -gt 0 ]] || print_panel_row "记录" "尚无资源任务记录"
    list_recent_resource_events 12
}

list_recent_resource_events() {
    local limit="${1:-12}" line total start i
    local at endpoint task type status message label detail
    local -a events=()
    ensure_resource_events_file || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -n "$(trim "${line}")" && "$(trim "${line}")" != \#* ]] || continue
        events+=("${line}")
    done < "${RESOURCE_EVENTS_FILE}"
    print_panel_section "最近资源任务事件"
    total="${#events[@]}"
    if (( total == 0 )); then
        print_panel_row "记录" "尚无事件日志"
        return 0
    fi
    [[ "${limit}" =~ ^[0-9]+$ && "${limit}" -gt 0 ]] || limit=12
    if (( total > limit )); then
        start=$((total - limit))
    else
        start=0
    fi
    for ((i = start; i < total; i++)); do
        IFS='|' read -r at endpoint task type status message <<< "${events[$i]}"
        label="$(resource_endpoint_label "${endpoint}")"
        detail="${label}；状态=${status:-未知}；任务=${task:-无}/${type:-无}"
        print_panel_row "${at:-未知}" "${detail}"
        [[ -n "${message}" ]] && print_panel_note "$(short_text "${message}" 180)"
    done
}

resource_events_keep_count() {
    local keep="${1:-${RESOURCE_EVENTS_KEEP}}"
    [[ "${keep}" =~ ^[0-9]+$ ]] || keep=500
    printf '%s\n' "${keep}"
}

prune_resource_events() {
    local keep="${1:-${RESOURCE_EVENTS_KEEP}}" line total start i tmp
    local -a events=()
    keep="$(resource_events_keep_count "${keep}")"
    ensure_resource_events_file || return 1
    (( keep > 0 )) || return 0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -n "$(trim "${line}")" && "$(trim "${line}")" != \#* ]] || continue
        events+=("${line}")
    done < "${RESOURCE_EVENTS_FILE}"
    total="${#events[@]}"
    (( total > keep )) || return 0
    start=$((total - keep))
    tmp="${RESOURCE_EVENTS_FILE}.tmp.$$"
    printf '# at|endpoint_id|task_id|task_type|status|message\n' > "${tmp}" || return 1
    for ((i = start; i < total; i++)); do
        printf '%s\n' "${events[$i]}" >> "${tmp}"
    done
    replace_file_from_tmp "${tmp}" "${RESOURCE_EVENTS_FILE}"
}

clear_resource_stats_interactive() {
    local choice keep
    ensure_resource_stats_file || return 1
    ensure_resource_events_file || return 1
    print_panel_section "清理资源任务统计"
    print_panel_row "聚合统计" "${RESOURCE_STATS_FILE}"
    print_panel_row "事件日志" "${RESOURCE_EVENTS_FILE}"
    print_panel_row "自动裁剪" "每次资源轮询后保留最近 ${RESOURCE_EVENTS_KEEP} 条事件；设 PO0_RESOURCE_EVENTS_KEEP 可调整"
    printf '%s\n' "  1) 清空资源事件日志"
    printf '%s\n' "  2) 清空聚合统计和事件日志"
    printf '%s\n' "  3) 裁剪事件日志，只保留最近 N 条"
    printf '%s\n' "  0) 取消"
    choice="$(read_prompt "请选择清理方式 [0-3]: ")" || {
        printf '\n输入结束，取消清理。\n'
        return 0
    }
    choice="$(trim "${choice}")"
    case "${choice}" in
        1)
            if prompt_yes_no "确认清空资源事件日志" "n"; then
                printf '# at|endpoint_id|task_id|task_type|status|message\n' > "${RESOURCE_EVENTS_FILE}" || return 1
                chmod 600 "${RESOURCE_EVENTS_FILE}" 2>/dev/null || true
                printf '已清空资源事件日志。\n'
            else
                printf '已取消。\n'
            fi
            ;;
        2)
            if prompt_yes_no "确认清空资源聚合统计和事件日志" "n"; then
                printf '# endpoint_id|success_count|fail_count|last_task|last_type|last_status|last_at|last_message\n' > "${RESOURCE_STATS_FILE}" || return 1
                printf '# at|endpoint_id|task_id|task_type|status|message\n' > "${RESOURCE_EVENTS_FILE}" || return 1
                chmod 600 "${RESOURCE_STATS_FILE}" "${RESOURCE_EVENTS_FILE}" 2>/dev/null || true
                printf '已清空资源聚合统计和事件日志。\n'
            else
                printf '已取消。\n'
            fi
            ;;
        3)
            keep="$(prompt_default "保留最近多少条事件" "${RESOURCE_EVENTS_KEEP}")"
            keep="$(resource_events_keep_count "${keep}")"
            prune_resource_events "${keep}" || return 1
            printf '已裁剪资源事件日志，保留最近 %s 条。\n' "${keep}"
            ;;
        0|"")
            printf '已取消。\n'
            ;;
        *)
            printf '无效选择。\n' >&2
            return 1
            ;;
    esac
}

fetch_to_file() {
    local url="$1" output="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 --connect-timeout 15 --max-time 180 "${url}" -o "${output}"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=180 "${url}" -O "${output}"
    else
        printf '系统缺少 curl 或 wget。\n' >&2
        return 1
    fi
}

progress_cat() {
    local file="$1"
    local total="${2:-0}"
    local block_size=262144 blocks idx sent percent
    if command -v pv >/dev/null 2>&1 && [[ "${total}" =~ ^[0-9]+$ && "${total}" -gt 0 ]]; then
        pv -f -p -t -e -r -b -s "${total}" "${file}"
        return $?
    fi
    if ! [[ "${total}" =~ ^[0-9]+$ ]] || [[ "${total}" -le 0 ]]; then
        cat "${file}"
        return $?
    fi
    blocks=$(((total + block_size - 1) / block_size))
    idx=0
    while [[ "${idx}" -lt "${blocks}" ]]; do
        dd if="${file}" bs="${block_size}" skip="${idx}" count=1 2>/dev/null || return 1
        sent=$(((idx + 1) * block_size))
        [[ "${sent}" -gt "${total}" ]] && sent="${total}"
        percent=$((sent * 100 / total))
        printf '\r上传进度：%3s%% %s/%s bytes' "${percent}" "${sent}" "${total}" >&2
        idx=$((idx + 1))
    done
    printf '\n' >&2
}

iplist_parallel_jobs() {
    local jobs="${IPLIST_JOBS:-16}"
    [[ "${jobs}" =~ ^[0-9]+$ ]] || jobs=16
    (( jobs >= 1 )) || jobs=1
    (( jobs <= 50 )) || jobs=50
    printf '%s\n' "${jobs}"
}

relative_iplist_data_path() {
    local url="$1"
    case "${url}" in
        */iplist/data/cncity/*.txt)
            printf '%s\n' "data/cncity/${url#*/iplist/data/cncity/}"
            ;;
        */data/cncity/*.txt)
            printf '%s\n' "data/cncity/${url#*/data/cncity/}"
            ;;
        *)
            return 1
            ;;
    esac
}

xargs_supports_parallel() {
    command -v xargs >/dev/null 2>&1 || return 1
    printf 'test\0' | xargs -0 -n 1 -P 1 sh -c ':' _ >/dev/null 2>&1
}

build_iplist_resource() {
    local output="$1"
    local work doc urls queue url rel supported=0 jobs
    work="$(mktemp -d "${TMPDIR:-/tmp}/po0-iplist-worker.XXXXXX")" || return 1
    doc="${work}/docs/cncity.md"
    urls="${work}/urls.txt"
    queue="${work}/download-queue.bin"
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
    : > "${queue}" || {
        rm -rf -- "${work}"
        return 1
    }
    while IFS= read -r url; do
        rel="$(relative_iplist_data_path "${url}")" || continue
        ((supported++))
        printf '%s\0%s\0%s\0%s\0' "${supported}" "${rel}" "${url}" "${work}/${rel}" >> "${queue}"
    done < "${urls}"
    [[ "${supported}" -gt 0 ]] || {
        rm -rf -- "${work}"
        return 1
    }
    jobs="$(iplist_parallel_jobs)"
    printf 'iplist 数据下载：%s 个文件，并发 %s\n' "${supported}" "${jobs}"
    if [[ "${jobs}" -gt 1 ]] && xargs_supports_parallel; then
        TOTAL_SUPPORTED="${supported}" xargs -0 -n 4 -P "${jobs}" bash -c '
idx="$1"
rel="$2"
url="$3"
output="$4"
mkdir -p "$(dirname "${output}")"
printf "[%s/%s] %s\n" "${idx}" "${TOTAL_SUPPORTED}" "${rel}"
if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 --connect-timeout 15 --max-time 180 "${url}" -o "${output}"
elif command -v wget >/dev/null 2>&1; then
    wget -q --timeout=180 "${url}" -O "${output}"
else
    echo "系统缺少 curl 或 wget。" >&2
    exit 1
fi
' _ < "${queue}" || {
            rm -rf -- "${work}"
            return 1
        }
    else
        [[ "${jobs}" -gt 1 ]] && printf '当前 xargs 不支持并发参数，退回逐个下载。\n' >&2
        while IFS= read -r -d '' _idx && IFS= read -r -d '' rel && IFS= read -r -d '' url && IFS= read -r -d '' _output; do
            printf '[%s/%s] %s\n' "${_idx}" "${supported}" "${rel}"
            mkdir -p "${work}/${rel%/*}" || {
                rm -rf -- "${work}"
                return 1
            }
            fetch_to_file "${url}" "${work}/${rel}" || {
                rm -rf -- "${work}"
                return 1
            }
        done < "${queue}"
    fi
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
    local -a ssh_args=(-n -p "${port}")
    sanitize_ssh_extra_args "${extra}" "resource fail ${user}@${host}:${port}"
    ssh_args+=("${SSH_EXTRA_ARGV[@]}")
    remote_cmd="bash $(sh_quote "${script}") --resource-task-fail $(sh_quote "${task_id}") $(sh_quote "${worker_id}") $(sh_quote "${reason}") $(sh_quote "${token}")"
    run_with_optional_timeout "$(timeout_seconds "${RESOURCE_CONTROL_TIMEOUT_SECONDS}" 120)" ssh "${ssh_args[@]}" "${user}@${host}" "${remote_cmd}" >/dev/null 2>&1 || true
}

timeout_seconds() {
    local value="${1:-}" fallback="${2:-0}"
    [[ "${value}" =~ ^[0-9]+$ ]] || value="${fallback}"
    printf '%s\n' "${value}"
}

run_with_optional_timeout() {
    local seconds="$1"
    shift
    if [[ "${seconds}" -gt 0 ]] && command -v timeout >/dev/null 2>&1; then
        timeout "${seconds}" "$@"
    else
        "$@"
    fi
}

resource_task_max_per_run() {
    local max="${RESOURCE_TASK_MAX_PER_RUN:-10}"
    [[ "${max}" =~ ^[0-9]+$ ]] || max=10
    (( max <= 100 )) || max=100
    printf '%s\n' "${max}"
}

run_resource_endpoint() {
    local host="$1" port="$2" user="$3" script="$4" token="$5" extra="$6"
    local worker_id endpoint_id remote_cmd response protocol task_id task_type upload_path work output sha size upload_response complete_response reason
    local processed=0 failed=0 max_per_run upload_timeout complete_timeout control_timeout upload_rc complete_rc claim_rc
    local -a ssh_args=(-p "${port}")
    local -a control_ssh_args=(-n -p "${port}")
    worker_id="$(sanitize_field "${WORKER_ID}")"
    worker_id="${worker_id// /_}"
    endpoint_id="$(resource_endpoint_id_for "${host}" "${port}" "${user}")"
    sanitize_ssh_extra_args "${extra}" "resource ${user}@${host}:${port}"
    ssh_args+=("${SSH_EXTRA_ARGV[@]}")
    control_ssh_args+=("${SSH_EXTRA_ARGV[@]}")
    max_per_run="$(resource_task_max_per_run)"
    upload_timeout="$(timeout_seconds "${RESOURCE_UPLOAD_TIMEOUT_SECONDS}" 900)"
    complete_timeout="$(timeout_seconds "${RESOURCE_COMPLETE_TIMEOUT_SECONDS}" 600)"
    control_timeout="$(timeout_seconds "${RESOURCE_CONTROL_TIMEOUT_SECONDS}" 120)"
    while true; do
        if [[ "${max_per_run}" -gt 0 && "${processed}" -ge "${max_per_run}" ]]; then
            printf '资源任务：%s 本轮已处理 %s 个，达到上限 %s。\n' "${host}" "${processed}" "${max_per_run}"
            [[ "${failed}" == "0" ]]
            return $?
        fi

        reason=""
        task_id=""
        task_type=""
        upload_path=""
        output=""
        remote_cmd="bash $(sh_quote "${script}") --resource-task-claim $(sh_quote "${worker_id}") $(sh_quote "${token}")"
        response="$(run_with_optional_timeout "${control_timeout}" ssh "${control_ssh_args[@]}" "${user}@${host}" "${remote_cmd}" 2>&1)"
        claim_rc=$?
        if [[ "${claim_rc}" -ne 0 ]]; then
            if [[ "${claim_rc}" == "124" ]]; then
                response="资源任务查询超时（${control_timeout} 秒）"
            fi
            printf '资源任务查询失败：%s@%s:%s\n' "${user}" "${host}" "${port}" >&2
            [[ -n "${response}" ]] && printf '  %s\n' "$(sanitize_field "${response}")" >&2
            update_resource_stats "${endpoint_id}" "" "" "查询失败" "${response}" || true
            return 1
        fi
        protocol="$(printf '%s\n' "${response}" | grep -E '^(TASK|NO_TASK|ERROR)(\||$)' | tail -n 1)"
        case "${protocol}" in
            NO_TASK)
                if [[ "${processed}" -gt 0 ]]; then
                    printf '资源任务：%s 本轮处理 %s 个，失败 %s，已无待处理任务。\n' "${host}" "${processed}" "${failed}"
                else
                    printf '资源任务：%s 暂无任务。\n' "${host}"
                    update_resource_stats "${endpoint_id}" "" "" "无任务" "PO0 当前没有等待任务" || true
                fi
                [[ "${failed}" == "0" ]]
                return $?
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
            ((processed++))
            ((failed++))
            continue
        fi
        printf '资源任务 %s：计算 SHA-256 和文件大小...\n' "${task_id}"
        sha="$(sha256_file "${output}")" || reason="本机缺少 SHA-256 工具"
        size="$(wc -c < "${output}" | tr -d '[:space:]')"
        if [[ -n "${reason}" ]]; then
            report_resource_failure "${task_id}" "${worker_id}" "${reason}" "${host}" "${port}" "${user}" "${script}" "${token}" "${extra}"
            update_resource_stats "${endpoint_id}" "${task_id}" "${task_type}" "失败" "${reason}" || true
            rm -rf -- "${work}"
            ((processed++))
            ((failed++))
            continue
        fi
        remote_cmd="bash $(sh_quote "${script}") --resource-task-upload $(sh_quote "${task_id}") $(sh_quote "${worker_id}") $(sh_quote "${sha}") $(sh_quote "${size}") $(sh_quote "${token}")"
        printf '资源任务 %s：上传到 PO0（%s bytes，超时 %s 秒）...\n' "${task_id}" "${size}" "${upload_timeout}"
        upload_response="$(progress_cat "${output}" "${size}" | run_with_optional_timeout "${upload_timeout}" ssh "${ssh_args[@]}" "${user}@${host}" "${remote_cmd}" 2>&1)"
        upload_rc=$?
        if [[ "${upload_rc}" -ne 0 ]]; then
            if [[ "${upload_rc}" == "124" ]]; then
                reason="PO0 上传资源文件超时（${upload_timeout} 秒）"
            else
                reason="PO0 上传资源文件失败（退出码 ${upload_rc}）：${upload_response}"
            fi
            report_resource_failure "${task_id}" "${worker_id}" "${reason}" "${host}" "${port}" "${user}" "${script}" "${token}" "${extra}"
            update_resource_stats "${endpoint_id}" "${task_id}" "${task_type}" "失败" "${reason}" || true
            rm -rf -- "${work}"
            printf '%s\n' "${reason}" >&2
            ((processed++))
            ((failed++))
            continue
        fi
        if [[ "${upload_response}" != *"OK|"* ]]; then
            reason="PO0 返回了无法识别的上传响应：${upload_response}"
            report_resource_failure "${task_id}" "${worker_id}" "${reason}" "${host}" "${port}" "${user}" "${script}" "${token}" "${extra}"
            update_resource_stats "${endpoint_id}" "${task_id}" "${task_type}" "失败" "${reason}" || true
            rm -rf -- "${work}"
            printf '%s\n' "${reason}" >&2
            ((processed++))
            ((failed++))
            continue
        fi
        printf '资源任务 %s：PO0 已接收，开始校验/导入（超时 %s 秒）...\n' "${task_id}" "${complete_timeout}"
        remote_cmd="bash $(sh_quote "${script}") --resource-task-complete $(sh_quote "${task_id}") $(sh_quote "${worker_id}") $(sh_quote "${sha}") $(sh_quote "${size}") $(sh_quote "${token}")"
        complete_response="$(run_with_optional_timeout "${complete_timeout}" ssh "${control_ssh_args[@]}" "${user}@${host}" "${remote_cmd}" 2>&1)"
        complete_rc=$?
        if [[ "${complete_rc}" -ne 0 ]]; then
            if [[ "${complete_rc}" == "124" ]]; then
                reason="PO0 校验或导入超时（${complete_timeout} 秒）"
            else
                reason="PO0 校验或导入失败（退出码 ${complete_rc}）：${complete_response}"
            fi
            report_resource_failure "${task_id}" "${worker_id}" "${reason}" "${host}" "${port}" "${user}" "${script}" "${token}" "${extra}"
            update_resource_stats "${endpoint_id}" "${task_id}" "${task_type}" "失败" "${reason}" || true
            rm -rf -- "${work}"
            printf '%s\n' "${reason}" >&2
            ((processed++))
            ((failed++))
            continue
        fi
        if [[ "${complete_response}" != *"OK|"* ]]; then
            reason="PO0 返回了无法识别的完成响应：${complete_response}"
            report_resource_failure "${task_id}" "${worker_id}" "${reason}" "${host}" "${port}" "${user}" "${script}" "${token}" "${extra}"
            update_resource_stats "${endpoint_id}" "${task_id}" "${task_type}" "失败" "${reason}" || true
            rm -rf -- "${work}"
            printf '%s\n' "${reason}" >&2
            ((processed++))
            ((failed++))
            continue
        fi
        update_resource_stats "${endpoint_id}" "${task_id}" "${task_type}" "成功" "${complete_response##*OK|}" || true
        rm -rf -- "${work}"
        printf '资源任务完成：%s\n' "${complete_response##*OK|}"
        ((processed++))
    done
}

run_resource_targets() {
    local line endpoint_key script_for_key label seen=";" ok=0 fail=0 skipped=0 disabled=0 duplicate=0
    ensure_config_file || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        label="${TARGET_LABEL:-${TARGET_PO0_HOST}}"
        if [[ "${TARGET_ENABLED}" != "1" ]]; then
            ((disabled++))
            continue
        fi
        if [[ -z "${TARGET_RESOURCE_TOKEN}" ]]; then
            printf '资源任务：%s 未配置 Token，跳过。\n' "${label}"
            ((skipped++))
            continue
        fi
        script_for_key="${TARGET_PO0_SCRIPT:-${DEFAULT_PO0_SCRIPT}}"
        endpoint_key="${TARGET_PO0_USER:-root}@${TARGET_PO0_HOST}:${TARGET_PO0_PORT:-22}:${script_for_key}:${TARGET_RESOURCE_TOKEN}"
        if [[ "${seen}" == *";${endpoint_key};"* ]]; then
            printf '资源任务：%s 与前面目标使用同一 PO0/token，跳过重复轮询。\n' "${label}"
            ((duplicate++))
            continue
        fi
        seen+="${endpoint_key};"
        printf '资源任务：轮询 %s -> %s@%s:%s\n' "${label}" "${TARGET_PO0_USER:-root}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT:-22}"
        if run_resource_endpoint "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT:-22}" "${TARGET_PO0_USER:-root}" "${TARGET_PO0_SCRIPT:-${DEFAULT_PO0_SCRIPT}}" "${TARGET_RESOURCE_TOKEN}" "${TARGET_SSH_EXTRA_ARGS}"; then
            ((ok++))
        else
            ((fail++))
        fi
    done < "${CONFIG_FILE}"
    printf '资源任务轮询完成：成功/无任务 %s，失败 %s，未配置 Token 跳过 %s，停用跳过 %s，重复跳过 %s。\n' "${ok}" "${fail}" "${skipped}" "${disabled}" "${duplicate}"
    prune_resource_events "${RESOURCE_EVENTS_KEEP}" || true
    [[ "${fail}" == "0" ]]
}

run_all_client_jobs() {
    local failed=0
    run_resource_targets || failed=1
    run_config_targets || failed=1
    return "${failed}"
}

self_report_targets_env() {
    local line source ttl extra count=0
    if [[ -n "${SELF_REPORT_TARGETS}" ]]; then
        printf '%s\n' "${SELF_REPORT_TARGETS}" | tr ';' '\n'
        return 0
    fi
    ensure_config_file || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        [[ "${TARGET_ENABLED}" == "1" ]] || continue
        [[ -n "${TARGET_CLIENT_IP_TOKEN}" ]] || continue
        source="${TARGET_CLIENT_IP_SOURCE:-${SELF_REPORT_SOURCE}}"
        ttl="${TARGET_CLIENT_IP_TTL:-${SELF_REPORT_TTL_SECONDS}}"
        extra="${TARGET_REPORT_SSH_EXTRA_ARGS:-${TARGET_SSH_EXTRA_ARGS}}"
        printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
            "${source}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT:-22}" "${TARGET_PO0_USER:-root}" "${TARGET_PO0_SCRIPT:-${DEFAULT_PO0_SCRIPT}}" "${TARGET_CLIENT_IP_TOKEN}" "${ttl:-3600}" "${extra}"
        count=$((count + 1))
    done < "${CONFIG_FILE}"
    if [[ "${count}" == "0" && -n "${PO0_HOST}" && -n "${CLIENT_IP_TOKEN}" ]]; then
        printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
            "${SELF_REPORT_SOURCE}" "${PO0_HOST}" "${PO0_PORT:-22}" "${PO0_USER:-root}" "${PO0_SCRIPT:-${DEFAULT_PO0_SCRIPT}}" "${CLIENT_IP_TOKEN}" "${SELF_REPORT_TTL_SECONDS:-3600}" "${SSH_EXTRA_ARGS}"
    fi
}

has_config_self_report_target() {
    local line
    ensure_config_file || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        [[ "${TARGET_ENABLED}" == "1" ]] || continue
        [[ -n "${TARGET_PO0_HOST}" && -n "${TARGET_CLIENT_IP_TOKEN}" ]] || continue
        return 0
    done < "${CONFIG_FILE}"
    return 1
}

webauth_targets_env() {
    local line source ttl extra count=0
    if [[ -n "${WEBAUTH_TARGETS}" ]]; then
        printf '%s\n' "${WEBAUTH_TARGETS}" | tr ';' '\n'
        return 0
    fi
    ensure_config_file || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        [[ "${TARGET_ENABLED}" == "1" ]] || continue
        [[ -n "${TARGET_WEBAUTH_TOKEN}" ]] || continue
        source="${TARGET_WEBAUTH_SOURCE:-${WEBAUTH_SOURCE}}"
        ttl="${TARGET_WEBAUTH_TTL:-${WEBAUTH_TTL_SECONDS}}"
        extra="${TARGET_REPORT_SSH_EXTRA_ARGS:-${TARGET_SSH_EXTRA_ARGS}}"
        printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
            "${source}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT:-22}" "${TARGET_PO0_USER:-root}" "${TARGET_PO0_SCRIPT:-${DEFAULT_PO0_SCRIPT}}" "${TARGET_WEBAUTH_TOKEN}" "${ttl:-3600}" "${extra}"
        count=$((count + 1))
    done < "${CONFIG_FILE}"
    if [[ "${count}" == "0" && -n "${PO0_HOST}" && -n "${WEBAUTH_TOKEN}" ]]; then
        printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
            "${WEBAUTH_SOURCE}" "${PO0_HOST}" "${PO0_PORT:-22}" "${PO0_USER:-root}" "${PO0_SCRIPT:-${DEFAULT_PO0_SCRIPT}}" "${WEBAUTH_TOKEN}" "${WEBAUTH_TTL_SECONDS:-3600}" "${SSH_EXTRA_ARGS}"
    fi
}

probe_webauth_target() {
    local failed=0 response targets line source host port user script token ttl extra count=0
    have_cmd ssh || { probe_fail "缺少 ssh。"; failed=1; }
    if ! have_cmd python3 && ! have_cmd python; then
        probe_fail "缺少 python3/python，无法运行 WebAuth 本地 HTTP 服务。"
        failed=1
    fi
    targets="$(webauth_targets_env)" || return 1
    [[ -n "${targets}" ]] || {
        probe_fail "没有 WebAuth 上报目标。请配置 --po0-host/--webauth-token，或在菜单中添加 WebAuth 放行目标。"
        return 1
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="$(trim "${line}")"
        [[ -n "${line}" && ! "${line}" == \#* ]] || continue
        IFS='|' read -r source host port user script token ttl extra <<< "${line}"
        source="$(sanitize_field "${source:-${WEBAUTH_SOURCE}}")"
        host="$(sanitize_field "${host}")"
        port="$(sanitize_field "${port:-22}")"
        user="$(sanitize_field "${user:-root}")"
        script="$(sanitize_field "${script:-${DEFAULT_PO0_SCRIPT}}")"
        token="$(sanitize_field "${token}")"
        extra="$(sanitize_field "${extra:-}")"
        [[ -n "${host}" && -n "${token}" ]] || {
            probe_fail "跳过无效 WebAuth 上报目标：${line}"
            failed=1
            continue
        }
        count=$((count + 1))
        if response="$(remote_manager_call "${host}" "${port:-22}" "${user:-root}" "${script:-${DEFAULT_PO0_SCRIPT}}" "${extra}" --webauth-report-check "${source:-${WEBAUTH_SOURCE}}" "${token}" 2>&1)"; then
            probe_ok "WebAuth 目标 ${source:-${WEBAUTH_SOURCE}}@${host}:${port:-22} 权限检查通过：${response}"
        else
            probe_fail "WebAuth 目标 ${source:-${WEBAUTH_SOURCE}}@${host}:${port:-22} 权限检查失败：${response}"
            failed=1
        fi
    done < <(printf '%s\n' "${targets}")
    if [[ "${count}" == "0" ]]; then
        probe_fail "没有可用的 WebAuth 上报目标。"
        failed=1
    fi
    return "${failed}"
}

run_webauth_server() {
    local py listen_host listen_port targets
    targets="$(webauth_targets_env)" || return 1
    [[ -n "${targets}" ]] || { printf 'missing WebAuth PO0 target. Configure --po0-host/--webauth-token or WebAuth 上报目标。\n' >&2; return 1; }
    if have_cmd python3; then
        py="python3"
    elif have_cmd python; then
        py="python"
    else
        printf 'missing python3/python; cannot run WebAuth server.\n' >&2
        return 1
    fi
    listen_host="${WEBAUTH_LISTEN%:*}"
    listen_port="${WEBAUTH_LISTEN##*:}"
    [[ -n "${listen_host}" && "${listen_host}" != "${WEBAUTH_LISTEN}" ]] || listen_host="127.0.0.1"
    [[ "${listen_port}" =~ ^[0-9]+$ ]] || listen_port="8787"
    export PO0_WEBAUTH_TARGETS="${targets}"
    printf 'WebAuth server listening on %s:%s; PO0 has no HTTP listener.\n' "${listen_host}" "${listen_port}"
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
    if o[0] == 198 and 18 <= o[1] <= 19:
        return False
    return True

def parse_targets(raw):
    targets = []
    for line in (raw or "").replace(";", "\n").splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = [part.strip() for part in line.split('|')]
        while len(parts) < 8:
            parts.append('')
        source, host, port, user, script, token, ttl, extra = parts[:8]
        if not host or not token:
            continue
        targets.append({
            'source': source or 'cf-access',
            'host': host,
            'port': port or '22',
            'user': user or 'root',
            'script': script or '/root/nftables-relay-manager.sh',
            'token': token,
            'ttl': ttl or '3600',
            'extra': extra,
        })
    return targets

def warn_ignored_extra(context, reason):
    print(f"[WARN] {context}: ignored SSH extra arg ({reason}).", file=sys.stderr)

def sanitized_extra_args(extra, context):
    out = []
    has_batchmode = False
    has_connect_timeout = False
    has_strict_host = False
    has_connection_attempts = False
    has_number_prompts = False
    has_preferred_auth = False
    has_password_auth = False
    has_kbd_auth = False
    has_gssapi = False
    private_key_words = False
    private_key_warned = False
    connect_timeout = os.environ.get("PO0_SSH_CONNECT_TIMEOUT_SECONDS", "15") or "15"
    try:
        parts = shlex.split(extra or "")
    except ValueError as exc:
        warn_ignored_extra(context, f"parse error: {exc}")
        parts = []
    options_with_value = {
        "-B", "-b", "-c", "-D", "-E", "-e", "-F", "-I", "-i", "-J", "-L",
        "-l", "-m", "-O", "-o", "-P", "-Q", "-R", "-S", "-W", "-w",
    }
    option_assignments = (
        "IdentityFile=", "BatchMode=", "StrictHostKeyChecking=",
        "UserKnownHostsFile=", "HostKeyAlias=", "ProxyJump=", "ProxyCommand=",
        "ConnectTimeout=", "ConnectionAttempts=", "NumberOfPasswordPrompts=",
        "PreferredAuthentications=", "PasswordAuthentication=",
        "KbdInteractiveAuthentication=", "GSSAPIAuthentication=",
    )
    i = 0
    while i < len(parts):
        token = parts[i]
        next_token = parts[i + 1] if i + 1 < len(parts) else ""
        if private_key_words and (
            token in ("OPENSSH", "RSA", "DSA", "EC", "ECDSA", "ED25519", "PRIVATE", "KEY", "KEY-----")
            or token.endswith("KEY-----")
            or token.startswith("-----END")
        ):
            if token.endswith("KEY-----") or token.startswith("-----END"):
                private_key_words = False
            i += 1
        elif token.startswith("-----BEGIN") or token.startswith("-----END"):
            if not private_key_warned:
                warn_ignored_extra(context, "private key text is not an SSH option; save it to a file and use -i /path/key")
                private_key_warned = True
            private_key_words = True
            if token.endswith("KEY-----") or token.startswith("-----END"):
                private_key_words = False
            i += 1
        elif token == "-" or token.startswith("--"):
            warn_ignored_extra(context, "invalid option/private-key marker")
            i += 1
        elif token == "-p":
            warn_ignored_extra(context, "port belongs in the PO0 SSH port field")
            i += 2 if next_token and not next_token.startswith("-") else 1
        elif token.startswith("-p"):
            warn_ignored_extra(context, "port belongs in the PO0 SSH port field")
            i += 1
        elif token.startswith(option_assignments):
            if token.startswith("BatchMode="):
                has_batchmode = True
            elif token.startswith("ConnectTimeout="):
                has_connect_timeout = True
            elif token.startswith("StrictHostKeyChecking="):
                has_strict_host = True
            elif token.startswith("ConnectionAttempts="):
                has_connection_attempts = True
            elif token.startswith("NumberOfPasswordPrompts="):
                has_number_prompts = True
            elif token.startswith("PreferredAuthentications="):
                has_preferred_auth = True
            elif token.startswith("PasswordAuthentication="):
                has_password_auth = True
            elif token.startswith("KbdInteractiveAuthentication="):
                has_kbd_auth = True
            elif token.startswith("GSSAPIAuthentication="):
                has_gssapi = True
            out.extend(["-o", token])
            i += 1
        elif token in options_with_value:
            if not next_token or next_token.startswith("-"):
                warn_ignored_extra(context, f"missing value for {token}")
                i += 1
            else:
                if token == "-o":
                    if next_token.startswith("BatchMode="):
                        has_batchmode = True
                    elif next_token.startswith("ConnectTimeout="):
                        has_connect_timeout = True
                    elif next_token.startswith("StrictHostKeyChecking="):
                        has_strict_host = True
                    elif next_token.startswith("ConnectionAttempts="):
                        has_connection_attempts = True
                    elif next_token.startswith("NumberOfPasswordPrompts="):
                        has_number_prompts = True
                    elif next_token.startswith("PreferredAuthentications="):
                        has_preferred_auth = True
                    elif next_token.startswith("PasswordAuthentication="):
                        has_password_auth = True
                    elif next_token.startswith("KbdInteractiveAuthentication="):
                        has_kbd_auth = True
                    elif next_token.startswith("GSSAPIAuthentication="):
                        has_gssapi = True
                out.extend([token, next_token])
                i += 2
        elif token.startswith("-"):
            if token.startswith("-oBatchMode="):
                has_batchmode = True
            elif token.startswith("-oConnectTimeout="):
                has_connect_timeout = True
            elif token.startswith("-oStrictHostKeyChecking="):
                has_strict_host = True
            elif token.startswith("-oConnectionAttempts="):
                has_connection_attempts = True
            elif token.startswith("-oNumberOfPasswordPrompts="):
                has_number_prompts = True
            elif token.startswith("-oPreferredAuthentications="):
                has_preferred_auth = True
            elif token.startswith("-oPasswordAuthentication="):
                has_password_auth = True
            elif token.startswith("-oKbdInteractiveAuthentication="):
                has_kbd_auth = True
            elif token.startswith("-oGSSAPIAuthentication="):
                has_gssapi = True
            out.append(token)
            i += 1
        else:
            warn_ignored_extra(context, "bare value without an SSH option")
            i += 1
    if not has_batchmode:
        out.extend(["-o", "BatchMode=yes"])
    if not has_connect_timeout:
        out.extend(["-o", f"ConnectTimeout={connect_timeout}"])
    if not has_strict_host:
        out.extend(["-o", "StrictHostKeyChecking=accept-new"])
    if not has_connection_attempts:
        out.extend(["-o", "ConnectionAttempts=1"])
    if not has_number_prompts:
        out.extend(["-o", "NumberOfPasswordPrompts=0"])
    if not has_preferred_auth:
        out.extend(["-o", "PreferredAuthentications=publickey"])
    if not has_password_auth:
        out.extend(["-o", "PasswordAuthentication=no"])
    if not has_kbd_auth:
        out.extend(["-o", "KbdInteractiveAuthentication=no"])
    if not has_gssapi:
        out.extend(["-o", "GSSAPIAuthentication=no"])
    return out

TARGETS = parse_targets(os.environ.get('PO0_WEBAUTH_TARGETS', ''))
if not TARGETS:
    raise SystemExit('missing PO0_WEBAUTH_TARGETS')

def report_target(target, ip, identity, note):
    try:
        ttl = int(target.get('ttl') or '3600')
    except ValueError:
        ttl = 3600
    expires_at = str(int(time.time()) + max(60, ttl))
    remote = " ".join([
        "bash",
        shlex.quote(target['script']),
        "--webauth-report",
        shlex.quote(target['source']),
        shlex.quote(ip),
        shlex.quote(identity or "unknown"),
        shlex.quote(expires_at),
        shlex.quote(target['token']),
        shlex.quote(note or "lan-webauth"),
    ])
    cmd = ["ssh", "-p", target['port']]
    cmd.extend(sanitized_extra_args(target.get('extra', ''), f"WebAuth {target['user']}@{target['host']}:{target['port']}"))
    cmd.extend([f"{target['user']}@{target['host']}", remote])
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)

def report_all(ip, identity, note):
    ok = []
    failed = []
    for target in TARGETS:
        result = report_target(target, ip, identity, note)
        label = f"{target['source']}@{target['host']}"
        if result.returncode == 0:
            ok.append(label)
        else:
            failed.append(f"{label}: {result.stderr or result.stdout or result.returncode}")
    return ok, failed

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
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(f"invalid public ipv4: {ip}\n".encode())
            return
        try:
            ok, failed = report_all(ip, identity, "cf-access")
        except Exception as exc:
            self.send_response(502)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(f"report failed: {exc}\n".encode())
            return
        if failed:
            self.send_response(502)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            body = [
                "PO0 WebAuth partial/failed",
                f"ip: {ip}",
                f"identity: {identity}",
                f"ok: {len(ok)}/{len(TARGETS)}",
                "updated: " + (", ".join(ok) if ok else "none"),
                "failed: " + "; ".join(failed),
                "",
            ]
            self.wfile.write(("\n".join(body)).encode())
        else:
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            body = [
                "PO0 WebAuth OK",
                f"ip: {ip}",
                f"identity: {identity}",
                "updated: " + ", ".join(ok),
                "",
            ]
            self.wfile.write(("\n".join(body)).encode())

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

with socketserver.ThreadingTCPServer((listen_host, listen_port), Handler) as httpd:
    httpd.serve_forever()
PY
}
install_webauth_service() {
    local script_path unit target_args="" name="po0-lan-webauth.service"
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
    [[ -n "${WEBAUTH_TARGETS}" ]] && target_args=" --webauth-targets $(sh_quote "${WEBAUTH_TARGETS}")"
    cat > "${unit}" <<EOF
[Unit]
Description=PO0 LAN WebAuth client reporter
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/env bash $(sh_quote "${script_path}") --config $(sh_quote "${CONFIG_FILE}") --webauth-server --listen $(sh_quote "${WEBAUTH_LISTEN}") --po0-host $(sh_quote "${PO0_HOST}") --po0-port $(sh_quote "${PO0_PORT}") --po0-user $(sh_quote "${PO0_USER}") --po0-script $(sh_quote "${PO0_SCRIPT}") --webauth-source $(sh_quote "${WEBAUTH_SOURCE}") --webauth-token $(sh_quote "${WEBAUTH_TOKEN}") --webauth-ttl $(sh_quote "${WEBAUTH_TTL_SECONDS}")${target_args}
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
    local response failed=0 targets line source host port user script token ttl extra count=0
    have_cmd ssh || { probe_fail "缺少 ssh，无法连接 PO0。"; failed=1; }
    if have_cmd python3 || have_cmd python; then
        probe_ok "Python 可用，可运行 self-report server"
    else
        probe_fail "缺少 python3/python，无法运行 self-report server。"
        failed=1
    fi
    targets="$(self_report_targets_env)" || return 1
    [[ -n "${targets}" ]] || {
        probe_fail "没有设备自上报目标。请配置 --po0-host/--client-ip-token，或在菜单中添加设备自上报目标。"
        return 1
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="$(trim "${line}")"
        [[ -n "${line}" && ! "${line}" == \#* ]] || continue
        IFS='|' read -r source host port user script token ttl extra <<< "${line}"
        source="$(sanitize_field "${source:-${SELF_REPORT_SOURCE}}")"
        host="$(sanitize_field "${host}")"
        port="$(sanitize_field "${port:-22}")"
        user="$(sanitize_field "${user:-root}")"
        script="$(sanitize_field "${script:-${DEFAULT_PO0_SCRIPT}}")"
        token="$(sanitize_field "${token}")"
        extra="$(sanitize_field "${extra:-}")"
        [[ -n "${host}" && -n "${token}" ]] || {
            probe_fail "跳过无效设备自上报目标：${line}"
            failed=1
            continue
        }
        count=$((count + 1))
        if response="$(remote_manager_call "${host}" "${port:-22}" "${user:-root}" "${script:-${DEFAULT_PO0_SCRIPT}}" "${extra}" --client-ip-report-check "${source:-${SELF_REPORT_SOURCE}}" "${token}" 2>&1)"; then
            probe_ok "设备自上报目标 ${source:-${SELF_REPORT_SOURCE}}@${host}:${port:-22} 权限检查通过：${response}"
        else
            probe_fail "设备自上报目标 ${source:-${SELF_REPORT_SOURCE}}@${host}:${port:-22} 权限检查失败：${response}"
            failed=1
        fi
    done < <(printf '%s\n' "${targets}")
    if [[ "${count}" == "0" ]]; then
        probe_fail "没有可用的设备自上报目标。"
        failed=1
    fi
    [[ "${failed}" == "0" ]]
}

run_self_report_server() {
    local py listen_host listen_port targets
    targets="$(self_report_targets_env)" || return 1
    [[ -n "${targets}" ]] || { printf 'missing Self-report PO0 target. Configure --po0-host/--client-ip-token or 设备自上报目标。\n' >&2; return 1; }
    if have_cmd python3; then
        py="python3"
    elif have_cmd python; then
        py="python"
    else
        printf 'missing python3/python; cannot run self-report server.\n' >&2
        return 1
    fi
    listen_host="${SELF_REPORT_LISTEN%:*}"
    listen_port="${SELF_REPORT_LISTEN##*:}"
    [[ -n "${listen_host}" && "${listen_host}" != "${SELF_REPORT_LISTEN}" ]] || listen_host="127.0.0.1"
    [[ "${listen_port}" =~ ^[0-9]+$ ]] || listen_port="8788"
    export PO0_SELF_REPORT_TARGETS="${targets}" SELF_REPORT_SECRET
    printf 'Self-report server listening on %s:%s; device -> LAN Worker -> SSH -> PO0.\n' "${listen_host}" "${listen_port}"
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
    if o[0] == 198 and 18 <= o[1] <= 19:
        return False
    return True

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

def parse_targets(raw):
    targets = []
    for line in (raw or "").replace(";", "\n").splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = [part.strip() for part in line.split('|')]
        while len(parts) < 8:
            parts.append('')
        source, host, port, user, script, token, ttl, extra = parts[:8]
        if not host or not token:
            continue
        targets.append({
            'source': source or 'self-report',
            'host': host,
            'port': port or '22',
            'user': user or 'root',
            'script': script or '/root/nftables-relay-manager.sh',
            'token': token,
            'ttl': ttl or '3600',
            'extra': extra,
        })
    return targets

def warn_ignored_extra(context, reason):
    print(f"[WARN] {context}: ignored SSH extra arg ({reason}).", file=sys.stderr)

def sanitized_extra_args(extra, context):
    out = []
    has_batchmode = False
    has_connect_timeout = False
    has_strict_host = False
    has_connection_attempts = False
    has_number_prompts = False
    has_preferred_auth = False
    has_password_auth = False
    has_kbd_auth = False
    has_gssapi = False
    private_key_words = False
    private_key_warned = False
    connect_timeout = os.environ.get("PO0_SSH_CONNECT_TIMEOUT_SECONDS", "15") or "15"
    try:
        parts = shlex.split(extra or "")
    except ValueError as exc:
        warn_ignored_extra(context, f"parse error: {exc}")
        parts = []
    options_with_value = {
        "-B", "-b", "-c", "-D", "-E", "-e", "-F", "-I", "-i", "-J", "-L",
        "-l", "-m", "-O", "-o", "-P", "-Q", "-R", "-S", "-W", "-w",
    }
    option_assignments = (
        "IdentityFile=", "BatchMode=", "StrictHostKeyChecking=",
        "UserKnownHostsFile=", "HostKeyAlias=", "ProxyJump=", "ProxyCommand=",
        "ConnectTimeout=", "ConnectionAttempts=", "NumberOfPasswordPrompts=",
        "PreferredAuthentications=", "PasswordAuthentication=",
        "KbdInteractiveAuthentication=", "GSSAPIAuthentication=",
    )
    i = 0
    while i < len(parts):
        token = parts[i]
        next_token = parts[i + 1] if i + 1 < len(parts) else ""
        if private_key_words and (
            token in ("OPENSSH", "RSA", "DSA", "EC", "ECDSA", "ED25519", "PRIVATE", "KEY", "KEY-----")
            or token.endswith("KEY-----")
            or token.startswith("-----END")
        ):
            if token.endswith("KEY-----") or token.startswith("-----END"):
                private_key_words = False
            i += 1
        elif token.startswith("-----BEGIN") or token.startswith("-----END"):
            if not private_key_warned:
                warn_ignored_extra(context, "private key text is not an SSH option; save it to a file and use -i /path/key")
                private_key_warned = True
            private_key_words = True
            if token.endswith("KEY-----") or token.startswith("-----END"):
                private_key_words = False
            i += 1
        elif token == "-" or token.startswith("--"):
            warn_ignored_extra(context, "invalid option/private-key marker")
            i += 1
        elif token == "-p":
            warn_ignored_extra(context, "port belongs in the PO0 SSH port field")
            i += 2 if next_token and not next_token.startswith("-") else 1
        elif token.startswith("-p"):
            warn_ignored_extra(context, "port belongs in the PO0 SSH port field")
            i += 1
        elif token.startswith(option_assignments):
            if token.startswith("BatchMode="):
                has_batchmode = True
            elif token.startswith("ConnectTimeout="):
                has_connect_timeout = True
            elif token.startswith("StrictHostKeyChecking="):
                has_strict_host = True
            elif token.startswith("ConnectionAttempts="):
                has_connection_attempts = True
            elif token.startswith("NumberOfPasswordPrompts="):
                has_number_prompts = True
            elif token.startswith("PreferredAuthentications="):
                has_preferred_auth = True
            elif token.startswith("PasswordAuthentication="):
                has_password_auth = True
            elif token.startswith("KbdInteractiveAuthentication="):
                has_kbd_auth = True
            elif token.startswith("GSSAPIAuthentication="):
                has_gssapi = True
            out.extend(["-o", token])
            i += 1
        elif token in options_with_value:
            if not next_token or next_token.startswith("-"):
                warn_ignored_extra(context, f"missing value for {token}")
                i += 1
            else:
                if token == "-o":
                    if next_token.startswith("BatchMode="):
                        has_batchmode = True
                    elif next_token.startswith("ConnectTimeout="):
                        has_connect_timeout = True
                    elif next_token.startswith("StrictHostKeyChecking="):
                        has_strict_host = True
                    elif next_token.startswith("ConnectionAttempts="):
                        has_connection_attempts = True
                    elif next_token.startswith("NumberOfPasswordPrompts="):
                        has_number_prompts = True
                    elif next_token.startswith("PreferredAuthentications="):
                        has_preferred_auth = True
                    elif next_token.startswith("PasswordAuthentication="):
                        has_password_auth = True
                    elif next_token.startswith("KbdInteractiveAuthentication="):
                        has_kbd_auth = True
                    elif next_token.startswith("GSSAPIAuthentication="):
                        has_gssapi = True
                out.extend([token, next_token])
                i += 2
        elif token.startswith("-"):
            if token.startswith("-oBatchMode="):
                has_batchmode = True
            elif token.startswith("-oConnectTimeout="):
                has_connect_timeout = True
            elif token.startswith("-oStrictHostKeyChecking="):
                has_strict_host = True
            elif token.startswith("-oConnectionAttempts="):
                has_connection_attempts = True
            elif token.startswith("-oNumberOfPasswordPrompts="):
                has_number_prompts = True
            elif token.startswith("-oPreferredAuthentications="):
                has_preferred_auth = True
            elif token.startswith("-oPasswordAuthentication="):
                has_password_auth = True
            elif token.startswith("-oKbdInteractiveAuthentication="):
                has_kbd_auth = True
            elif token.startswith("-oGSSAPIAuthentication="):
                has_gssapi = True
            out.append(token)
            i += 1
        else:
            warn_ignored_extra(context, "bare value without an SSH option")
            i += 1
    if not has_batchmode:
        out.extend(["-o", "BatchMode=yes"])
    if not has_connect_timeout:
        out.extend(["-o", f"ConnectTimeout={connect_timeout}"])
    if not has_strict_host:
        out.extend(["-o", "StrictHostKeyChecking=accept-new"])
    if not has_connection_attempts:
        out.extend(["-o", "ConnectionAttempts=1"])
    if not has_number_prompts:
        out.extend(["-o", "NumberOfPasswordPrompts=0"])
    if not has_preferred_auth:
        out.extend(["-o", "PreferredAuthentications=publickey"])
    if not has_password_auth:
        out.extend(["-o", "PasswordAuthentication=no"])
    if not has_kbd_auth:
        out.extend(["-o", "KbdInteractiveAuthentication=no"])
    if not has_gssapi:
        out.extend(["-o", "GSSAPIAuthentication=no"])
    return out

TARGETS = parse_targets(os.environ.get('PO0_SELF_REPORT_TARGETS', ''))
if not TARGETS:
    raise SystemExit('missing PO0_SELF_REPORT_TARGETS')

def report_target(target, ip, identity, source_override):
    source = source_override or target['source']
    remote = " ".join([
        "bash",
        shlex.quote(target['script']),
        "--client-ip-report",
        shlex.quote(source),
        shlex.quote(ip),
        shlex.quote(target['token']),
        shlex.quote(identity or "self-report"),
        shlex.quote(target['ttl']),
    ])
    cmd = ["ssh", "-p", target['port']]
    cmd.extend(sanitized_extra_args(target.get('extra', ''), f"Self-report {target['user']}@{target['host']}:{target['port']}"))
    cmd.extend([f"{target['user']}@{target['host']}", remote])
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)

def report_all(ip, identity, source_override):
    ok = []
    failed = []
    for target in TARGETS:
        result = report_target(target, ip, identity, source_override)
        label = f"{source_override or target['source']}@{target['host']}"
        if result.returncode == 0:
            ok.append(label)
        else:
            failed.append(f"{label}: {result.stderr or result.stdout or result.returncode}")
    return ok, failed

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.handle_report()

    def do_POST(self):
        self.handle_report()

    def handle_report(self):
        path, params = parse_request(self)
        if path in ("/health", "/health/"):
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK\n")
            return
        if path not in ("/report", "/report/"):
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"not found\n")
            return

        secret = os.environ.get("SELF_REPORT_SECRET", "")
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
        source_override = first([params.get("source"), params.get("source_id")])
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
            ok, failed = report_all(ip, identity, source_override)
        except Exception as exc:
            self.send_response(502)
            self.end_headers()
            self.wfile.write(f"report failed: {exc}\n".encode())
            return
        if failed:
            self.send_response(502)
            self.end_headers()
            self.wfile.write((f"partial/failed {len(ok)}/{len(TARGETS)} OK; " + "; ".join(failed) + "\n").encode())
        else:
            self.send_response(200)
            self.end_headers()
            self.wfile.write((f"OK {ip}; targets={len(ok)}\n").encode())

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

with socketserver.ThreadingTCPServer((listen_host, listen_port), Handler) as httpd:
    httpd.serve_forever()
PY
}
install_self_report_service() {
    local script_path unit target_args="" fallback_args="" secret_args="" name="po0-lan-self-report.service" targets
    [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]] || {
        printf '安装 systemd 服务需要 root。\n' >&2
        return 1
    }
    command -v systemctl >/dev/null 2>&1 || {
        printf '当前系统没有 systemctl，无法安装服务。\n' >&2
        return 1
    }
    targets="$(self_report_targets_env 2>/dev/null || true)"
    if [[ -z "${targets}" ]]; then
        printf '没有可用的 Self-report PO0 目标，未安装后台服务。\n' >&2
        printf '请先在菜单里配置：Self-report 配置 / 启动 -> 目标 Token -> Self-report client-ip Token。\n' >&2
        printf '如果还没有 PO0 目标，请先用主菜单“添加 PO0 目标”。\n' >&2
        return 1
    fi
    if [[ -z "${SELF_REPORT_SECRET}" ]]; then
        printf '警告：Self-report secret 为空；访问设备上报将不校验共享密钥。建议先用菜单生成 / 修改 secret。\n' >&2
    fi
    script_path="$(ensure_persistent_script)" || return 1
    unit="/etc/systemd/system/${name}"
    if [[ -n "${SELF_REPORT_TARGETS}" ]]; then
        target_args=" --self-report-targets $(sh_quote "${SELF_REPORT_TARGETS}")"
    elif ! has_config_self_report_target; then
        fallback_args=" --po0-host $(sh_quote "${PO0_HOST}") --po0-port $(sh_quote "${PO0_PORT}") --po0-user $(sh_quote "${PO0_USER}") --po0-script $(sh_quote "${PO0_SCRIPT}") --self-report-source $(sh_quote "${SELF_REPORT_SOURCE}") --client-ip-token $(sh_quote "${CLIENT_IP_TOKEN}") --self-report-ttl $(sh_quote "${SELF_REPORT_TTL_SECONDS}")"
    fi
    [[ -n "${SELF_REPORT_SECRET}" ]] && secret_args=" --self-report-secret $(sh_quote "${SELF_REPORT_SECRET}")"
    cat > "${unit}" <<EOF
[Unit]
Description=PO0 LAN self-report receiver
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/env bash $(sh_quote "${script_path}") --config $(sh_quote "${CONFIG_FILE}") --self-report-server --self-report-listen $(sh_quote "${SELF_REPORT_LISTEN}")${secret_args}${target_args}${fallback_args}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload || return 1
    systemctl reset-failed "${name}" 2>/dev/null || true
    systemctl enable "${name}" || return 1
    systemctl restart "${name}" || return 1
    printf '已安装并启动 Self-report 服务：%s\n' "${name}"
}

normalize_self_report_https_domain() {
    local domain="$1"
    domain="$(trim "${domain}")"
    domain="${domain#http://}"
    domain="${domain#https://}"
    domain="${domain%%/*}"
    domain="${domain%%:*}"
    domain="${domain,,}"
    printf '%s\n' "${domain}"
}

validate_self_report_https_domain() {
    local domain="$1"
    [[ -n "${domain}" ]] || {
        printf '缺少 Self-report HTTPS 域名。\n' >&2
        return 1
    }
    [[ "${domain}" == *.* && "${domain}" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$ ]] || {
        printf 'Self-report HTTPS 域名格式无效：%s\n' "${domain}" >&2
        return 1
    }
    is_public_ipv4 "${domain}" && {
        printf 'Self-report HTTPS 需要公网域名，不能直接使用 IP：%s\n' "${domain}" >&2
        return 1
    }
    return 0
}

self_report_https_domain_from_caddy() {
    local line
    [[ -r "${SELF_REPORT_CADDY_SNIPPET}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="$(trim "${line}")"
        [[ -n "${line}" && "${line}" != \#* ]] || continue
        case "${line}" in
            *"{")
                line="${line%\{}"
                line="$(trim "${line}")"
                [[ -n "${line}" ]] || return 1
                printf '%s\n' "${line}"
                return 0
                ;;
        esac
    done < "${SELF_REPORT_CADDY_SNIPPET}"
    return 1
}

current_self_report_https_domain() {
    if [[ -n "${SELF_REPORT_HTTPS_DOMAIN}" ]]; then
        printf '%s\n' "${SELF_REPORT_HTTPS_DOMAIN}"
    else
        self_report_https_domain_from_caddy 2>/dev/null || true
    fi
}

ensure_caddy_installed() {
    if have_cmd caddy; then
        return 0
    fi
    [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]] || {
        printf '安装 Caddy 需要 root。请先手动安装 caddy，或用 root 重新运行菜单。\n' >&2
        return 1
    }
    if have_cmd apt-get; then
        apt-get update -y && apt-get install -y caddy
    elif have_cmd dnf; then
        dnf install -y caddy
    elif have_cmd yum; then
        yum install -y caddy
    elif have_cmd apk; then
        apk add --no-cache caddy
    else
        printf '未识别的包管理器。请先手动安装 Caddy，再重新配置 Self-report HTTPS。\n' >&2
        return 1
    fi
    have_cmd caddy || {
        printf 'Caddy 安装后仍不可用，请检查包管理器输出。\n' >&2
        return 1
    }
}

ensure_caddyfile_import() {
    local caddy_dir import_line
    caddy_dir="$(path_dirname "${CADDYFILE_PATH}")"
    mkdir -p "${caddy_dir}" "$(path_dirname "${SELF_REPORT_CADDY_SNIPPET}")" || return 1
    [[ -f "${CADDYFILE_PATH}" ]] || : > "${CADDYFILE_PATH}" || return 1
    import_line="import /etc/caddy/conf.d/*.caddy"
    if ! grep -Eq '^[[:space:]]*import[[:space:]]+/etc/caddy/conf\.d/\*\.caddy[[:space:]]*$' "${CADDYFILE_PATH}" 2>/dev/null; then
        {
            printf '\n'
            printf '# PO0 LAN Worker managed snippets\n'
            printf '%s\n' "${import_line}"
        } >> "${CADDYFILE_PATH}" || return 1
    fi
}

write_self_report_caddy_config() {
    local domain="$1" backend_host backend_port
    backend_host="${SELF_REPORT_HTTPS_BACKEND%:*}"
    backend_port="${SELF_REPORT_HTTPS_BACKEND##*:}"
    [[ -n "${backend_host}" && "${backend_host}" != "${SELF_REPORT_HTTPS_BACKEND}" ]] || backend_host="127.0.0.1"
    [[ "${backend_port}" =~ ^[0-9]+$ ]] || backend_port="8788"
    mkdir -p "$(path_dirname "${SELF_REPORT_CADDY_SNIPPET}")" || return 1
    cat > "${SELF_REPORT_CADDY_SNIPPET}" <<EOF
# Managed by po0-lan-client. Self-report HTTPS entrypoint.
${domain} {
    handle /report {
        reverse_proxy ${backend_host}:${backend_port}
    }
    handle /health {
        reverse_proxy ${backend_host}:${backend_port}
    }
    respond 404
}
EOF
}

show_self_report_https_status() {
    local domain lines name="caddy"
    domain="$(current_self_report_https_domain)"
    print_panel_section "Self-report HTTPS / Caddy 状态"
    print_panel_row "域名" "${domain:-未配置}"
    print_panel_row "公网入口" "$(if [[ -n "${domain}" ]]; then printf 'https://%s/report' "${domain}"; else printf '未配置'; fi)"
    print_panel_row "本机后端" "${SELF_REPORT_HTTPS_BACKEND}"
    print_panel_row "Caddyfile" "${CADDYFILE_PATH}"
    print_panel_row "Snippet" "${SELF_REPORT_CADDY_SNIPPET}"
    if have_cmd systemctl; then
        print_panel_row "Caddy 服务" "active=$(systemctl is-active "${name}" 2>/dev/null || true) enabled=$(systemctl is-enabled "${name}" 2>/dev/null || true)"
    else
        print_panel_row "Caddy 服务" "systemctl 不可用"
    fi
    if have_cmd caddy; then
        printf '\n'
        caddy validate --config "${CADDYFILE_PATH}" || true
    fi
    if have_cmd journalctl; then
        lines="$(prompt_default "显示最近多少行 Caddy 日志" "80")"
        if [[ "${lines}" =~ ^[0-9]+$ && "${lines}" -ge 1 && "${lines}" -le 1000 ]]; then
            printf '\n'
            journalctl -u "${name}" -n "${lines}" --no-pager -o short-iso || true
        fi
    fi
}

install_self_report_https() {
    local domain ip_csv
    domain="$(normalize_self_report_https_domain "${SELF_REPORT_HTTPS_DOMAIN}")"
    validate_self_report_https_domain "${domain}" || return 1
    if ip_csv="$(resolve_ddns_ipv4_csv "${domain}" 2>/dev/null)"; then
        printf 'DNS A 记录：%s -> %s\n' "${domain}" "${ip_csv}"
    else
        printf '警告：当前机器未解析到 %s 的公网 IPv4。请确认 DNS 已指向 LAN Worker，且 80/443 已放行。\n' "${domain}" >&2
    fi
    ensure_caddy_installed || return 1
    ensure_caddyfile_import || return 1
    write_self_report_caddy_config "${domain}" || return 1
    caddy validate --config "${CADDYFILE_PATH}" || return 1
    SELF_REPORT_HTTPS_DOMAIN="${domain}"
    SELF_REPORT_LISTEN="${SELF_REPORT_HTTPS_BACKEND}"
    install_self_report_service || return 1
    if have_cmd systemctl; then
        systemctl enable caddy || return 1
        systemctl reload caddy 2>/dev/null || systemctl restart caddy || return 1
    fi
    printf 'Self-report HTTPS 已配置：https://%s/report\n' "${domain}"
    printf '健康检查：curl -fsS https://%s/health\n' "${domain}"
    printf '注意：公网建议只放行 80/443，不建议继续放行 8788。\n'
}

self_report_service_summary() {
    local name="po0-lan-self-report.service" active enabled
    have_cmd systemctl || {
        printf 'systemctl 不可用'
        return 0
    }
    active="$(systemctl is-active "${name}" 2>/dev/null || true)"
    enabled="$(systemctl is-enabled "${name}" 2>/dev/null || true)"
    printf 'active=%s enabled=%s' "${active:-unknown}" "${enabled:-unknown}"
}

show_self_report_service_status() {
    local name="po0-lan-self-report.service"
    have_cmd systemctl || {
        printf '当前系统没有 systemctl，无法查看后台服务状态。\n' >&2
        return 1
    }
    print_panel_section "Self-report 后台服务状态"
    print_panel_row "服务" "${name}"
    print_panel_row "汇总" "$(self_report_service_summary)"
    printf '\n'
    systemctl status "${name}" --no-pager --full || true
}

show_self_report_service_logs() {
    local name="po0-lan-self-report.service" lines
    have_cmd journalctl || {
        printf '当前系统没有 journalctl，无法查看 systemd 日志。\n' >&2
        return 1
    }
    lines="$(prompt_default "显示最近多少行 Self-report 日志" "120")"
    if [[ ! "${lines}" =~ ^[0-9]+$ || "${lines}" -lt 1 || "${lines}" -gt 1000 ]]; then
        printf '日志行数必须是 1-1000。\n' >&2
        return 1
    fi
    print_panel_section "Self-report 最近日志"
    print_panel_row "服务" "${name}"
    print_panel_row "行数" "${lines}"
    printf '\n'
    journalctl -u "${name}" -n "${lines}" --no-pager -o short-iso || true
}

follow_self_report_service_logs() {
    local name="po0-lan-self-report.service"
    have_cmd journalctl || {
        printf '当前系统没有 journalctl，无法实时查看 systemd 日志。\n' >&2
        return 1
    }
    printf '正在实时查看 %s 日志；按 Ctrl+C 退出。\n' "${name}"
    journalctl -u "${name}" -f -o short-iso
}

normalize_cron_minutes() {
    local minutes="${1:-}"
    local max="${2:-1440}"
    minutes="$(trim "${minutes}")"
    [[ "${max}" =~ ^[0-9]+$ && "${max}" -ge 1 ]] || max=1440
    [[ "${minutes}" =~ ^[0-9]+$ && "${minutes}" -ge 1 && "${minutes}" -le "${max}" ]] || return 1
    printf '%s\n' "${minutes}"
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

build_worker_cron_job() {
    local minutes="$1"
    local action="$2"
    local script_path="$3"
    local log_path="$4"
    local run_cmd schedule hours
    run_cmd="bash $(sh_quote "${script_path}") --config $(sh_quote "${CONFIG_FILE}") ${action}"
    if (( minutes < 60 )); then
        schedule="*/${minutes} * * * *"
        printf '%s %s >%s 2>&1\n' "${schedule}" "${run_cmd}" "$(sh_quote "${log_path}")"
    elif (( minutes == 60 )); then
        printf '0 * * * * %s >%s 2>&1\n' "${run_cmd}" "$(sh_quote "${log_path}")"
    elif (( minutes < 1440 && minutes % 60 == 0 )); then
        hours=$((minutes / 60))
        printf '0 */%s * * * %s >%s 2>&1\n' "${hours}" "${run_cmd}" "$(sh_quote "${log_path}")"
    elif (( minutes == 1440 )); then
        printf '0 0 * * * %s >%s 2>&1\n' "${run_cmd}" "$(sh_quote "${log_path}")"
    elif (( minutes % 60 == 0 )); then
        hours=$((minutes / 60))
        printf '0 * * * * now=$(date +\%%s); if [ $((now / 3600 \%% %s)) -eq 0 ]; then %s >%s 2>&1; fi\n' "${hours}" "${run_cmd}" "$(sh_quote "${log_path}")"
    else
        printf '* * * * now=$(date +\%%s); if [ $((now / 60 \%% %s)) -eq 0 ]; then %s >%s 2>&1; fi\n' "${minutes}" "${run_cmd}" "$(sh_quote "${log_path}")"
    fi
}

print_cron_example() {
    local minutes="$1"
    local script_path resource_minutes ddns_minutes resource_label ddns_label
    if ! resource_minutes="$(normalize_cron_minutes "${minutes}" "${RESOURCE_CRON_MAX_MINUTES}")"; then
        resource_minutes="$(normalize_cron_minutes "${RESOURCE_CRON_MINUTES}" "${RESOURCE_CRON_MAX_MINUTES}" 2>/dev/null || printf '1440')"
    fi
    if ! ddns_minutes="$(normalize_cron_minutes "${minutes}" "${DDNS_CRON_MAX_MINUTES}")"; then
        ddns_minutes="$(normalize_cron_minutes "${DDNS_CRON_MINUTES}" "${DDNS_CRON_MAX_MINUTES}" 2>/dev/null || printf '5')"
    fi
    resource_label="$(cron_interval_label "${resource_minutes}")"
    ddns_label="$(cron_interval_label "${ddns_minutes}")"
    script_path="$(script_self_path)"
    printf '%s\n' \
        "本机资源任务领取示例（${resource_label}检查 PO0 pending 任务）：" \
        "$(build_worker_cron_job "${resource_minutes}" "--run-resource" "${script_path}" "/tmp/po0-lan-resource.log")" \
        "本机 DDNS resolver 示例（${ddns_label}解析并上报 DDNS）：" \
        "$(build_worker_cron_job "${ddns_minutes}" "--run-ddns" "${script_path}" "/tmp/po0-lan-ddns.log")"
}

managed_cron_job_for_action() {
    local action="$1"
    local begin end line in_block=0
    have_cmd crontab || return 1
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
        [[ "${in_block}" == "1" ]] || continue
        [[ "${line}" == *" ${action}"* || "${line}" == *" ${action} "* ]] || continue
        printf '%s\n' "${line}"
        return 0
    done < <(crontab -l 2>/dev/null || true)
    return 1
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
    if ! is_transient_script_path "${src}" && [[ -r "${src}" && "${src}" != */bash && "${src}" != */sh ]]; then
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

upgrade_self_from_raw() {
    local reopen_mode="${1:-}"
    local dest dir tmp legacy_scp_cmd legacy_scp_var old_version new_version changelog chmod_message
    old_version="${SCRIPT_VERSION}"
    dest="$(default_install_path)"
    dir="$(path_dirname "${dest}")"
    mkdir -p "${dir}" || return 1
    tmp="${dest}.tmp.$$"
    if have_cmd curl; then
        curl -fsSL "${RAW_URL}" -o "${tmp}" || {
            rm -f -- "${tmp}" 2>/dev/null || true
            return 1
        }
    elif have_cmd wget; then
        wget -qO "${tmp}" "${RAW_URL}" || {
            rm -f -- "${tmp}" 2>/dev/null || true
            return 1
        }
    else
        printf '无法更新：系统缺少 curl/wget。\n' >&2
        return 1
    fi
    legacy_scp_cmd="scp .*"
    legacy_scp_cmd+="upload_path"
    legacy_scp_var="scp"
    legacy_scp_var+="_args"
    if grep -q -- "${legacy_scp_cmd}" "${tmp}" || grep -q -- "${legacy_scp_var}" "${tmp}" || ! grep -q -- '--resource-task-upload' "${tmp}"; then
        rm -f -- "${tmp}" 2>/dev/null || true
        printf '更新文件校验失败：下载到的脚本不是 manager stdin 上传版。\n' >&2
        return 1
    fi
    new_version="$(script_file_var "${tmp}" "SCRIPT_VERSION" 2>/dev/null || true)"
    changelog="$(script_file_changelog "${tmp}" 2>/dev/null || true)"
    chmod 755 "${tmp}" 2>/dev/null || true
    mv -f "${tmp}" "${dest}" || {
        rm -f -- "${tmp}" 2>/dev/null || true
        return 1
    }
    if chmod 755 "${dest}" 2>/dev/null; then
        chmod_message="已设置执行权限：chmod 755 ${dest}"
    else
        chmod_message="警告：已更新，但自动设置执行权限失败；请手动执行 chmod 755 ${dest}"
    fi
    printf '已更新本机命令：%s\n' "${dest}"
    printf '%s\n' "${chmod_message}"
    if [[ -n "${new_version}" ]]; then
        if [[ "${new_version}" == "${old_version}" ]]; then
            printf '版本：%s（与当前执行脚本相同）\n' "${new_version}"
        else
            printf '版本：%s -> %s\n' "${old_version}" "${new_version}"
        fi
    fi
    if [[ -n "${changelog}" ]]; then
        printf '更新内容：\n%s\n' "${changelog}"
    else
        printf '更新内容：新脚本未提供更新说明；请运行 --version 查看当前状态。\n'
    fi
    if [[ "${reopen_mode}" == "--reopen-menu" ]]; then
        printf '正在重新打开新版菜单：%s --menu\n' "${dest}"
        exec "${BASH:-bash}" "${dest}" --config "${CONFIG_FILE}" --install-path "${dest}" --menu
        printf '重新打开新版脚本失败，请手动执行：%s --menu\n' "${dest}" >&2
        return 1
    fi
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

show_local_script_status() {
    local current install_path cron_summary marker_status legacy_scp_cmd legacy_scp_var
    current="$(script_source_path)"
    install_path="$(default_install_path)"
    marker_status="$(resource_upload_mode_label)"
    legacy_scp_cmd="scp .*"
    legacy_scp_cmd+="upload_path"
    legacy_scp_var="scp"
    legacy_scp_var+="_args"
    if have_cmd grep && [[ -r "${current}" ]] && { grep -q -- "${legacy_scp_cmd}" "${current}" || grep -q -- "${legacy_scp_var}" "${current}"; }; then
        marker_status="警告：当前脚本内容仍包含 legacy SCP 上传逻辑"
    fi
    print_panel_section "本机脚本"
    print_panel_row "脚本名称" "${SCRIPT_NAME}"
    print_panel_row "版本" "${SCRIPT_VERSION}"
    print_panel_row "发布日期" "${SCRIPT_RELEASE_DATE}"
    print_panel_row "当前脚本" "${current}"
    print_panel_row "默认安装路径" "${install_path}"
    print_panel_row "资源上传" "${marker_status}"
    print_panel_row "raw URL" "${RAW_URL}"
    cron_summary="$(cron_status_summary)"
    print_panel_row "本机轮询器" "${cron_summary}"
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

count_enabled_worker_targets() {
    local kind="$1"
    local line count=0
    ensure_config_file || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        [[ "${TARGET_ENABLED}" == "1" ]] || continue
        case "${kind}" in
            ddns)
                [[ "${TARGET_REPORT_MODE}" == "ddns" && -n "${TARGET_DOMAIN}" && -n "${TARGET_DDNS_RESOLVE_DOMAIN}" ]] && count=$((count + 1))
                ;;
            resource)
                [[ -n "${TARGET_RESOURCE_TOKEN}" ]] && count=$((count + 1))
                ;;
        esac
    done < "${CONFIG_FILE}"
    printf '%s\n' "${count}"
}

install_cron_interactive() {
    local ddns_count resource_count ddns_minutes="" resource_minutes="" script_path
    ensure_config_file || return 1
    print_panel_section "本机 Worker 轮询器"
    print_panel_row "资源领取" "只检查并领取 PO0 已创建的 pending 任务；不决定资源创建周期"
    print_panel_row "DDNS 上报" "只对启用 DDNS resolver 的目标执行；间隔应小于 PO0 端 DDNS 来源 TTL"
    print_panel_row "资源周期" "在 PO0 nft manager 的“内网资源更新任务”里单独设置"
    print_panel_row "DDNS TTL" "在 PO0 nft manager 的“管理源 IP 白名单 -> 管理 DDNS 来源”里添加/编辑"
    resource_count="$(count_enabled_worker_targets resource)" || return 1
    ddns_count="$(count_enabled_worker_targets ddns)" || return 1
    if (( resource_count == 0 && ddns_count == 0 )); then
        printf '没有启用的资源任务或 DDNS resolver 目标，无法安装本机轮询器。\n' >&2
        return 1
    fi
    if (( resource_count > 0 )); then
        resource_minutes="$(prompt_default "资源任务每几分钟检查一次（1-${RESOURCE_CRON_MAX_MINUTES}；只领取 PO0 已创建任务）" "${RESOURCE_CRON_MINUTES}")"
    else
        print_panel_row "资源任务" "未配置启用目标，跳过资源领取计划"
    fi
    if (( ddns_count > 0 )); then
        ddns_minutes="$(prompt_default "DDNS resolver 每几分钟上报一次（1-${DDNS_CRON_MAX_MINUTES}；应小于 PO0 端 DDNS 来源 TTL）" "${DDNS_CRON_MINUTES}")"
    else
        print_panel_row "DDNS resolver" "未配置启用目标，跳过 DDNS 上报计划"
    fi
    script_path="$(ensure_persistent_script)" || return 1
    install_worker_crons "${ddns_minutes}" "${resource_minutes}" "${script_path}" "all"
}

show_ddns_ttl_help() {
    print_panel_section "DDNS TTL 与上报间隔"
    print_panel_row "PO0 DDNS TTL" "在 PO0 nft manager 的“管理源 IP 白名单 -> 管理 DDNS 来源”里添加/编辑"
    print_panel_row "TTL 含义" "PO0 端接受上报后，DDNS 来源 IP 在白名单里的有效期"
    print_panel_row "本机间隔" "LAN Worker 只决定多久解析并上报一次；应小于 PO0 端 DDNS 来源 TTL"
    print_panel_row "查看 TTL" "在 PO0 manager 的 DDNS 来源列表里会显示 TTL=...s"
}

install_ddns_cron_interactive() {
    local ddns_count ddns_minutes script_path
    ensure_config_file || return 1
    show_ddns_ttl_help
    ddns_count="$(count_enabled_worker_targets ddns)" || return 1
    if (( ddns_count == 0 )); then
        printf '没有启用的 DDNS resolver 目标。请先在 DDNS 目标设置里添加或编辑目标。\n' >&2
        return 1
    fi
    ddns_minutes="$(prompt_default "DDNS resolver 每几分钟上报一次（1-${DDNS_CRON_MAX_MINUTES}；应小于 PO0 端 DDNS 来源 TTL）" "${DDNS_CRON_MINUTES}")"
    script_path="$(ensure_persistent_script)" || return 1
    install_worker_crons "${ddns_minutes}" "" "${script_path}" "ddns"
}

install_worker_crons() {
    local ddns_minutes="${1:-}"
    local resource_minutes="${2:-}"
    local script_path="${3:-}"
    local scope="${4:-all}"
    local ddns_count resource_count ddns_label="" resource_label="" ddns_job="" resource_job="" tmp
    local preserved_ddns=0 preserved_resource=0
    ensure_config_file || return 1
    command -v crontab >/dev/null 2>&1 || {
        printf '当前系统没有 crontab 命令。请先安装 cron，或改用 systemd timer。\n' >&2
        return 1
    }
    ddns_count="$(count_enabled_worker_targets ddns)" || return 1
    resource_count="$(count_enabled_worker_targets resource)" || return 1
    if (( ddns_count == 0 && resource_count == 0 )); then
        printf '没有启用的资源任务或 DDNS resolver 目标，无法安装本机轮询器。\n' >&2
        return 1
    fi
    [[ -n "${script_path}" ]] || script_path="$(script_self_path)"
    if (( resource_count > 0 )); then
        if [[ "${scope}" == "all" || "${scope}" == "resource" ]]; then
            if ! resource_minutes="$(normalize_cron_minutes "${resource_minutes:-${RESOURCE_CRON_MINUTES}}" "${RESOURCE_CRON_MAX_MINUTES}")"; then
                printf '资源任务分钟数无效：请输入 1-%s 的整数。\n' "${RESOURCE_CRON_MAX_MINUTES}" >&2
                return 1
            fi
            resource_label="$(cron_interval_label "${resource_minutes}")"
            resource_job="$(build_worker_cron_job "${resource_minutes}" "--run-resource" "${script_path}" "/tmp/po0-lan-resource.log")"
        elif resource_job="$(managed_cron_job_for_action "--run-resource" 2>/dev/null)"; then
            preserved_resource=1
        fi
    fi
    if (( ddns_count > 0 )); then
        if [[ "${scope}" == "all" || "${scope}" == "ddns" ]]; then
            if ! ddns_minutes="$(normalize_cron_minutes "${ddns_minutes:-${DDNS_CRON_MINUTES}}" "${DDNS_CRON_MAX_MINUTES}")"; then
                printf 'DDNS 分钟数无效：请输入 1-%s 的整数。\n' "${DDNS_CRON_MAX_MINUTES}" >&2
                return 1
            fi
            ddns_label="$(cron_interval_label "${ddns_minutes}")"
            ddns_job="$(build_worker_cron_job "${ddns_minutes}" "--run-ddns" "${script_path}" "/tmp/po0-lan-ddns.log")"
        elif ddns_job="$(managed_cron_job_for_action "--run-ddns" 2>/dev/null)"; then
            preserved_ddns=1
        fi
    fi
    [[ -n "${resource_job}${ddns_job}" ]] || {
        printf '没有可写入的本机轮询计划。\n' >&2
        return 1
    }
    tmp="${CONFIG_FILE}.cron.$$"
    {
        crontab -l 2>/dev/null | write_cron_without_managed_block || true
        printf '%s\n' "$(cron_begin_marker)"
        [[ -n "${resource_job}" ]] && printf '%s\n' "${resource_job}"
        [[ -n "${ddns_job}" ]] && printf '%s\n' "${ddns_job}"
        printf '%s\n' "$(cron_end_marker)"
    } > "${tmp}" || return 1
    crontab "${tmp}" || {
        rm -f "${tmp}" 2>/dev/null || true
        return 1
    }
    rm -f "${tmp}" 2>/dev/null || true
    if [[ -n "${resource_job}" ]]; then
        if (( preserved_resource == 1 )); then
            printf '已保留现有资源任务领取计划。\n'
        else
            printf '已安装/更新资源任务领取计划：%s检查 PO0 pending 任务。\n' "${resource_label}"
        fi
    fi
    if [[ -n "${ddns_job}" ]]; then
        if (( preserved_ddns == 1 )); then
            printf '已保留现有 DDNS resolver 上报计划。\n'
        else
            printf '已安装/更新 DDNS resolver 上报计划：%s解析并上报 DDNS。\n' "${ddns_label}"
        fi
    fi
    printf '提示：资源任务创建周期由 PO0 nft manager 控制；DDNS TTL 在 PO0 端 DDNS 来源里设置，本机只设置上报间隔。\n'
}

install_cron_minutes() {
    local minutes="$1"
    local script_path="${2:-}"
    install_worker_crons "${minutes}" "${minutes}" "${script_path}"
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
        probe_warn "已跳过连通性/权限检查，仅写入本机配置。"
    fi

    upsert_target "1" "${label}" "${DDNS_DOMAIN}" "${REPORT_KEY}" "${PO0_HOST}" "${PO0_PORT}" "${PO0_USER}" "${PO0_SCRIPT}" "${DDNS_TOKEN}" "${SSH_EXTRA_ARGS}" "${RESOURCE_TOKEN}" "${mode}" "${ddns_resolve_domain}" "${CLIENT_IP_TOKEN}" "${SELF_REPORT_SOURCE}" "${SELF_REPORT_TTL_SECONDS}" "${WEBAUTH_TOKEN}" "${WEBAUTH_SOURCE}" "${WEBAUTH_TTL_SECONDS}" "${SSH_EXTRA_ARGS}" || return 1
    chmod 600 "${CONFIG_FILE}" 2>/dev/null || true
    printf '已写入 worker 目标配置：%s\n' "${CONFIG_FILE}"

    if [[ "${INSTALL_CRON}" == "1" ]]; then
        script_path="$(ensure_persistent_script)" || return 1
        printf 'worker 脚本路径：%s\n' "${script_path}"
        install_worker_crons "${DDNS_CRON_MINUTES}" "${RESOURCE_CRON_MINUTES}" "${script_path}" || return 1
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
    printf '已删除本脚本管理的本机 Worker 轮询器。\n'
}

show_cron_status() {
    local begin end line in_block=0 found=0
    print_panel_section "本机 Worker 轮询器"
    command -v crontab >/dev/null 2>&1 || {
        print_panel_row "当前计划" "当前系统没有 crontab 命令"
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
            print_panel_row "当前计划" "${line}"
        fi
    done < <(crontab -l 2>/dev/null || true)
    [[ "${found}" == "1" ]] || print_panel_row "当前计划" "未安装本脚本管理的 Worker 轮询器"
}

show_webauth_cloudflare_guide() {
    local domain
    domain="$(prompt_default "WebAuth 域名（例如 auth.example.com）" "<AUTH_DOMAIN>")"
    printf '\n%s\n' "WebAuth / Cloudflare Access 接入"
    printf '%s\n' "链路：Browser -> Cloudflare Access -> Cloudflare Tunnel -> LAN Worker ${WEBAUTH_LISTEN} -> SSH -> PO0"
    printf '%s\n' ""
    printf '%s\n' "cloudflared ingress 配置片段："
    cat <<EOF
ingress:
  - hostname: ${domain}
    service: http://${WEBAUTH_LISTEN}
  - service: http_status:404
EOF
    printf '%s\n' ""
    printf '%s\n' "Cloudflare 控制台动作："
    printf '%s\n' "  1. 创建 Cloudflare Tunnel，并让 cloudflared 运行在 LAN Worker。"
    printf '%s\n' "  2. Public hostname 绑定 ${domain}，service 指向 http://${WEBAUTH_LISTEN}。"
    printf '%s\n' "  3. Access -> Applications -> Add application -> Self-hosted。"
    printf '%s\n' "  4. 应用域名填写 ${domain}。"
    printf '%s\n' "  5. 配置允许登录的邮箱、域名或 Access group。"
    printf '%s\n' "  6. 确认该 hostname 受 Access 保护。"
    printf '%s\n' ""
    printf '%s\n' "本地检查命令："
    printf '  cloudflared tunnel ingress validate\n'
    printf '  cloudflared tunnel ingress rule https://%s\n' "${domain}"
    printf '%s\n' ""
    printf '%s\n' "LAN Worker 启动命令："
    printf '  po0-lan-client --webauth-server --listen %s\n' "${WEBAUTH_LISTEN}"
    printf '%s\n' "PO0 不开放 HTTP；Cloudflare 只连接 LAN Worker。"
}

manage_ddns_settings_interactive() {
    local choice
    while true; do
        menu_clear_screen
        print_title "DDNS 目标 / 上报计划"
        show_ddns_ttl_help
        print_menu_section "DDNS 目标"
        print_menu_pair 1 "查看目标与统计" 2 "添加 DDNS / PO0 目标"
        print_menu_pair 3 "编辑目标" 4 "目标 Token"
        print_menu_item 5 "启用 / 停用目标"

        print_menu_section "本机上报"
        print_menu_pair 6 "安装 / 更新 DDNS 上报计划" 7 "立即执行 DDNS 上报"

        print_menu_section "退出"
        print_menu_item 0 "返回"
        print_menu_footer
        read_menu_choice_or_return choice "请选择操作 [0-7]: " || return 0
        case "${choice}" in
            1) list_targets; pause_before_return ;;
            2) add_target_interactive; pause_before_return ;;
            3) edit_target_interactive; pause_before_return ;;
            4) manage_target_tokens_interactive; pause_before_return ;;
            5) toggle_target_interactive; pause_before_return ;;
            6) install_ddns_cron_interactive; pause_before_return ;;
            7) run_config_targets; pause_before_return ;;
            0) return 0 ;;
            "") ;;
            *) printf '无效选择。\n' >&2; pause_before_return ;;
        esac
    done
}

show_self_report_settings() {
    local targets line source host port user script token ttl extra https_domain
    targets="$(self_report_targets_env 2>/dev/null || true)"
    https_domain="$(current_self_report_https_domain)"
    print_panel_section "Self-report 接收端"
    print_panel_row "监听地址" "${SELF_REPORT_LISTEN}"
    print_panel_row "HTTPS 入口" "$(if [[ -n "${https_domain}" ]]; then printf 'https://%s/report' "${https_domain}"; else printf '未配置'; fi)"
    print_panel_row "Secret" "$(mask_secret "${SELF_REPORT_SECRET}")"
    print_panel_row "默认 source" "${SELF_REPORT_SOURCE}"
    print_panel_row "默认 TTL" "${SELF_REPORT_TTL_SECONDS:-3600} 秒"
    print_panel_row "后台服务" "$(self_report_service_summary)"
    if [[ -n "${targets}" ]]; then
        print_panel_row "PO0 目标" "已配置"
        while IFS= read -r line || [[ -n "${line}" ]]; do
            [[ -n "${line}" ]] || continue
            IFS='|' read -r source host port user script token ttl extra <<< "${line}"
            print_panel_note "${source:-self-report}@${host}:${port:-22} ttl=${ttl:-3600} token=$(mask_secret "${token}")"
        done <<< "${targets}"
    else
        print_panel_row "PO0 目标" "未配置；先在主菜单添加 PO0 目标并设置 Self-report client-ip Token"
    fi
}

edit_self_report_listen_interactive() {
    SELF_REPORT_LISTEN="$(prompt_default "Self-report 本地监听地址" "${SELF_REPORT_LISTEN:-127.0.0.1:8788}")"
    [[ -n "${SELF_REPORT_LISTEN}" ]] || SELF_REPORT_LISTEN="127.0.0.1:8788"
    printf '已设置本次菜单会话监听地址：%s\n' "${SELF_REPORT_LISTEN}"
    printf '安装 / 更新后台服务后，该监听地址会写入 systemd service。\n'
}

edit_self_report_secret_interactive() {
    local generated value
    generated="$(random_secret)"
    if [[ -n "${SELF_REPORT_SECRET}" ]]; then
        printf '当前 Self-report secret：%s\n' "${SELF_REPORT_SECRET}"
        value="$(read_prompt "新的 Self-report secret [回车保留，输入 g 生成新值，输入 - 清空]: ")" || value=""
        value="$(trim "${value}")"
        case "${value}" in
            "") ;;
            g|G)
                SELF_REPORT_SECRET="${generated}"
                ;;
            -)
                SELF_REPORT_SECRET=""
                ;;
            *)
                SELF_REPORT_SECRET="${value}"
                ;;
        esac
    else
        value="$(prompt_default "Self-report secret（回车使用自动生成值）" "${generated}")"
        SELF_REPORT_SECRET="${value}"
    fi
    if [[ -n "${SELF_REPORT_SECRET}" ]]; then
        printf 'Self-report secret 已设置为：%s\n' "${SELF_REPORT_SECRET}"
        printf "Windows PowerShell 使用：\$env:PO0_SELF_REPORT_SECRET='%s'\n" "${SELF_REPORT_SECRET}"
    else
        printf 'Self-report secret 已清空；接收端将不校验访问设备 secret。\n'
    fi
}

configure_self_report_https_interactive() {
    local domain default_domain
    default_domain="$(current_self_report_https_domain)"
    domain="$(prompt_default "Self-report HTTPS 域名（DNS 已指向 LAN Worker）" "${default_domain}")"
    domain="$(normalize_self_report_https_domain "${domain}")"
    validate_self_report_https_domain "${domain}" || return 1
    SELF_REPORT_HTTPS_DOMAIN="${domain}"
    SELF_REPORT_LISTEN="${SELF_REPORT_HTTPS_BACKEND}"
    printf '将配置 HTTPS 入口：https://%s/report\n' "${domain}"
    printf 'Self-report 后端将只监听本机：%s\n' "${SELF_REPORT_LISTEN}"
    printf '请确认云安全组/防火墙已放行 TCP 80/443；公网不建议放行 8788。\n'
    if prompt_yes_no "继续安装 / 更新 Caddy HTTPS 和 Self-report 后台服务" "y"; then
        install_self_report_https
    else
        printf '已取消。\n'
    fi
}

manage_self_report_server_interactive() {
    local choice
    while true; do
        menu_clear_screen
        print_title "Self-report 配置 / 启动"
        show_self_report_settings
        print_menu_section "配置"
        print_menu_pair 1 "查看 PO0 目标" 2 "目标 Token"
        print_menu_pair 3 "Self-report source / TTL" 4 "设置监听地址"
        print_menu_item 5 "生成 / 修改 Self-report secret"

        print_menu_section "运行"
        print_menu_pair 6 "连通性检查" 7 "安装 / 更新后台服务"
        print_menu_pair 8 "查看后台服务状态" 9 "查看最近后台日志"
        print_menu_pair 10 "实时跟随后台日志" 11 "配置 HTTPS 域名 / Caddy"
        print_menu_pair 12 "查看 HTTPS / Caddy 状态日志" 13 "前台启动服务"

        print_menu_section "退出"
        print_menu_item 0 "返回"
        print_menu_footer
        read_menu_choice_or_return choice "请选择操作 [0-13]: " || return 0
        case "${choice}" in
            1) list_targets; pause_before_return ;;
            2) manage_target_tokens_interactive; pause_before_return ;;
            3) manage_target_report_ttl_interactive; pause_before_return ;;
            4) edit_self_report_listen_interactive; pause_before_return ;;
            5) edit_self_report_secret_interactive; pause_before_return ;;
            6) probe_self_report_target; pause_before_return ;;
            7) install_self_report_service; pause_before_return ;;
            8) show_self_report_service_status; pause_before_return ;;
            9) show_self_report_service_logs; pause_before_return ;;
            10) follow_self_report_service_logs ;;
            11) configure_self_report_https_interactive; pause_before_return ;;
            12) show_self_report_https_status; pause_before_return ;;
            13)
                printf '即将前台启动 Self-report 服务；运行后会占用当前终端，按 Ctrl+C 退出。\n'
                pause_before_return
                run_self_report_server
                ;;
            0) return 0 ;;
            "") ;;
            *) printf '无效选择。\n' >&2; pause_before_return ;;
        esac
    done
}

menu_loop() {
    local choice
    while true; do
        menu_clear_screen
        print_dashboard
        print_menu_section "资源任务"
        print_menu_pair 1 "资源统计" 2 "PO0 资源更新计划"
        print_menu_pair 3 "立即领取并执行资源任务" 4 "清理资源统计"

        print_menu_section "DDNS 解析上报"
        print_menu_pair 5 "上报目标与 DDNS 统计" 6 "立即执行 DDNS 上报"
        print_menu_pair 7 "DDNS 目标 / 上报计划" 8 "清空 DDNS 统计"

        print_menu_section "Self-report 自上报"
        print_menu_pair 9 "Self-report 连通性检查" 10 "Self-report 配置 / 启动"

        print_menu_section "WebAuth 放行"
        print_menu_pair 11 "WebAuth 连通性检查" 12 "启动 WebAuth 服务"
        print_menu_item 13 "WebAuth / Cloudflare Access 配置提示"

        print_menu_section "PO0 目标、SSH、Token 与 TTL"
        print_menu_pair 14 "添加 PO0 目标" 15 "编辑 PO0 目标"
        print_menu_pair 16 "SSH 私钥 / 参数" 17 "目标 Token"
        print_menu_pair 18 "Self-report / WebAuth TTL" 19 "启用 / 停用目标"
        print_menu_item 20 "删除 PO0 目标"

        print_menu_section "全局操作"
        print_menu_item 21 "执行全部任务"

        print_menu_section "维护"
        print_menu_pair 22 "安装 / 更新本机轮询器" 23 "删除本机轮询器"
        print_menu_pair 24 "查看本机轮询器状态" 25 "查看脚本版本 / 本机状态"
        print_menu_item 26 "从 GitHub 更新脚本"

        print_menu_section "退出"
        print_menu_item 0 "退出"
        print_menu_footer
        read_menu_choice_or_return choice "请选择操作 [0-26]: " || return 0
        case "${choice}" in
            1) list_resource_stats; pause_before_return ;;
            2) show_remote_resource_task_cron_status; pause_before_return ;;
            3) run_resource_targets; pause_before_return ;;
            4) clear_resource_stats_interactive; pause_before_return ;;
            5) list_targets; pause_before_return ;;
            6) run_config_targets; pause_before_return ;;
            7) manage_ddns_settings_interactive ;;
            8) clear_stats_interactive; pause_before_return ;;
            9) probe_self_report_target; pause_before_return ;;
            10) manage_self_report_server_interactive ;;
            11) probe_webauth_target; pause_before_return ;;
            12) run_webauth_server ;;
            13) show_webauth_cloudflare_guide; pause_before_return ;;
            14) add_target_interactive; pause_before_return ;;
            15) edit_target_interactive; pause_before_return ;;
            16) manage_target_ssh_interactive; [[ "$?" -eq 2 ]] || pause_before_return ;;
            17) manage_target_tokens_interactive; pause_before_return ;;
            18) manage_target_report_ttl_interactive; pause_before_return ;;
            19) toggle_target_interactive; pause_before_return ;;
            20) delete_target_interactive; pause_before_return ;;
            21) run_all_client_jobs; pause_before_return ;;
            22) install_cron_interactive; pause_before_return ;;
            23) remove_cron_interactive; pause_before_return ;;
            24) show_cron_status; pause_before_return ;;
            25) show_local_script_status; pause_before_return ;;
            26) upgrade_self_from_raw --reopen-menu || pause_before_return ;;
            0) return 0 ;;
            "") ;;
            *) printf '无效选择。\n' >&2; pause_before_return ;;
        esac
    done
}

ORIGINAL_ARGC="$#"

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
        --ddns-targets)
            require_arg_value "$@"
            DDNS_TARGETS="${2:-}"
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
        --webauth-targets)
            require_arg_value "$@"
            WEBAUTH_TARGETS="${2:-}"
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
        --self-report-targets)
            require_arg_value "$@"
            SELF_REPORT_TARGETS="${2:-}"
            shift 2
            ;;
        --self-report-https-domain)
            require_arg_value "$@"
            SELF_REPORT_HTTPS_DOMAIN="${2:-}"
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
        --wizard)
            ACTION="wizard"
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
        --run-ddns)
            ACTION="run-ddns"
            shift
            ;;
        --run-resource)
            ACTION="run-resource"
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
        --install-self-report-https)
            ACTION="install-self-report-https"
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
        --upgrade-self)
            ACTION="upgrade-self"
            shift
            ;;
        --version)
            ACTION="version"
            shift
            ;;
        --install-cron)
            INSTALL_CRON="1"
            if [[ -n "${2:-}" && "${2:-}" =~ ^[0-9]+$ ]]; then
                CRON_MINUTES="${2:-}"
                DDNS_CRON_MINUTES="${CRON_MINUTES}"
                RESOURCE_CRON_MINUTES="${CRON_MINUTES}"
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
                DDNS_CRON_MINUTES="${CRON_MINUTES}"
                RESOURCE_CRON_MINUTES="${CRON_MINUTES}"
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
    wizard)
        po0_lan_wizard
        exit $?
        ;;
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
    run-ddns)
        run_config_targets
        exit $?
        ;;
    run-resource)
        run_resource_targets
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
    install-self-report-https)
        install_self_report_https
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
    upgrade-self)
        upgrade_self_from_raw
        exit $?
        ;;
    version)
        show_local_script_status
        exit $?
        ;;
    install-cron)
        script_path="$(ensure_persistent_script)" || exit 1
        install_worker_crons "${DDNS_CRON_MINUTES}" "${RESOURCE_CRON_MINUTES}" "${script_path}"
        exit $?
        ;;
    print-cron)
        print_cron_example "${CRON_MINUTES}"
        exit $?
        ;;
esac

if [[ "${ORIGINAL_ARGC}" == "0" ]]; then
    po0_lan_wizard
    exit $?
fi

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
