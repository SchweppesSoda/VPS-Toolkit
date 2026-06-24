#!/usr/bin/env bash
set -uo pipefail

PO0_RELEASE_DOWNLOAD_BASE_URL="${PO0_RELEASE_DOWNLOAD_BASE_URL:-https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download}"
DOWNLOAD_URL="${PO0_LAN_CLIENT_DOWNLOAD_URL:-${PO0_RELEASE_DOWNLOAD_BASE_URL}/po0-lan-client.sh}"
MANAGER_DOWNLOAD_URL="${PO0_MANAGER_DOWNLOAD_URL:-${PO0_RELEASE_DOWNLOAD_BASE_URL}/nftables-relay-manager.sh}"
SCRIPT_NAME="po0-lan-worker-client"
SCRIPT_VERSION="2026.06.25+build.2"
SCRIPT_RELEASE_DATE="2026-06-25"
# CHANGELOG_BEGIN
# - Self-report server 和目标权限检查在转发到 PO0 前会规范 source / identity，避免 macOS 主机名含空格被 PO0 restricted wrapper 拆坏。
# - Self-report 502 返回正文继续保留 PO0 目标的具体失败原因，便于客户端排错。
# CHANGELOG_END
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
SETTINGS_FILE="${PO0_LAN_CLIENT_SETTINGS:-}"
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
REMOTE_MANAGER_TIMEOUT_SECONDS="${PO0_REMOTE_MANAGER_TIMEOUT_SECONDS:-30}"
REMOTE_STATUS_TIMEOUT_SECONDS="${PO0_REMOTE_STATUS_TIMEOUT_SECONDS:-8}"
SSH_CONNECT_TIMEOUT_SECONDS="${PO0_SSH_CONNECT_TIMEOUT_SECONDS:-15}"
WORKER_ID="${PO0_WORKER_ID:-$(hostname 2>/dev/null || printf 'po0-worker')}"
STATS_FILE_EXPLICIT="0"
ACTION=""
BACKUP_ARCHIVE=""
RESTORE_CRON="0"
RESTORE_SYSTEMD="0"
RESTORE_CADDY="0"
RESTORE_DRY_RUN="0"
CRON_MINUTES="60"
DDNS_CRON_MINUTES="${PO0_DDNS_CRON_MINUTES:-${DDNS_CRON_MINUTES:-60}}"
DDNS_INTERVAL_SECONDS_INPUT="${PO0_DDNS_INTERVAL_SECONDS:-${DDNS_INTERVAL_SECONDS:-}}"
DDNS_INTERVAL_SECONDS_EXPLICIT="0"
if [[ "${DDNS_INTERVAL_SECONDS_INPUT}" =~ ^[0-9]+$ && "${DDNS_INTERVAL_SECONDS_INPUT}" -ge 60 && $((10#${DDNS_INTERVAL_SECONDS_INPUT} % 60)) -eq 0 ]]; then
    DDNS_CRON_MINUTES="$((10#${DDNS_INTERVAL_SECONDS_INPUT} / 60))"
    DDNS_INTERVAL_SECONDS_EXPLICIT="1"
fi
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
WEBAUTH_TTL_SECONDS="${PO0_WEBAUTH_TTL_SECONDS:-43200}"
WEBAUTH_TARGETS="${PO0_WEBAUTH_TARGETS:-}"
SELF_REPORT_LISTEN="${PO0_SELF_REPORT_LISTEN:-127.0.0.1:8788}"
SELF_REPORT_SOURCE="${PO0_SELF_REPORT_SOURCE:-self-report}"
SELF_REPORT_SECRET="${PO0_SELF_REPORT_SECRET:-}"
SELF_REPORT_TTL_SECONDS="${PO0_SELF_REPORT_TTL_SECONDS:-43200}"
SELF_REPORT_TARGETS="${PO0_SELF_REPORT_TARGETS:-}"
SELF_REPORT_HTTPS_DOMAIN="${PO0_SELF_REPORT_HTTPS_DOMAIN:-}"
SELF_REPORT_HTTPS_BACKEND="${PO0_SELF_REPORT_HTTPS_BACKEND:-127.0.0.1:8788}"
SELF_REPORT_CADDY_SNIPPET="${PO0_SELF_REPORT_CADDY_SNIPPET:-/etc/caddy/conf.d/po0-self-report.caddy}"
MANAGER_UPDATE_LISTEN="${PO0_MANAGER_UPDATE_LISTEN:-127.0.0.1:8789}"
MANAGER_UPDATE_DOMAIN="${PO0_MANAGER_UPDATE_DOMAIN:-}"
MANAGER_UPDATE_DEFAULT_PORT="${PO0_MANAGER_UPDATE_DEFAULT_PORT:-2333}"
MANAGER_UPDATE_BACKEND="${PO0_MANAGER_UPDATE_BACKEND:-127.0.0.1:8789}"
MANAGER_UPDATE_CADDY_SNIPPET="${PO0_MANAGER_UPDATE_CADDY_SNIPPET:-/etc/caddy/conf.d/po0-manager-update.caddy}"
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
        "  bash po0-lan-client.sh --bootstrap --po0-host HOST --source-key home --ddns-domain home.example.com --token TOKEN --resource-token TOKEN --ddns-interval-seconds 3600 --install-cron" \
        "  bash po0-lan-client.sh --bootstrap --po0-host HOST --resource-token TOKEN --install-cron 1440" \
        "  curl -fsSL ${DOWNLOAD_URL} | bash -s -- --bootstrap --po0-host HOST --source-key home --ddns-domain home.example.com --token TOKEN --resource-token TOKEN --ddns-interval-seconds 3600 --install-cron" \
        "  po0-lan-client --webauth-server --listen 127.0.0.1:8787 --po0-host HOST --webauth-token TOKEN" \
        "  po0-lan-client --install-self-report-https --self-report-https-domain report.example.com --po0-host HOST --client-ip-token TOKEN --self-report-secret SECRET" \
        "  po0-lan-client --install-manager-update-http --manager-update-domain 172.81.111.68" \
        "  po0-lan-client --self-report-server --self-report-listen 127.0.0.1:8788 --po0-host HOST --client-ip-token TOKEN" \
        "" \
        "常用命令:" \
        "  --probe              只做依赖、DDNS 解析、SSH、PO0 token 连通性/权限检查，不修改 PO0 白名单。" \
        "  --bootstrap          写入本机目标配置，默认先做连通性/权限检查，再执行一次 --run。" \
        "  --install-cron [N]   安装/更新本机 Worker 轮询器；N 为兼容分钟参数，会作为资源间隔，并在未显式设置 DDNS 秒数时作为 DDNS 间隔。" \
        "                        不带 N 时，DDNS 默认 $(cron_minutes_to_seconds "${DDNS_CRON_MINUTES}") 秒，资源任务默认 ${RESOURCE_CRON_MINUTES} 分钟。" \
        "  --ddns-interval-seconds N  设置 DDNS resolver 上报间隔秒数，必须是 60 的倍数，默认 3600。" \
        "                        资源任务创建周期在 PO0 nft manager 里设置，本机只定期领取已创建任务。" \
        "                        如果目标启用了 DDNS resolver，DDNS 间隔应小于 PO0 端该 DDNS 来源 TTL。" \
        "  PO0_IPLIST_JOBS=N   iplist txt 并发下载数，默认 16，范围 1-50。" \
        "  PO0_RESOURCE_TASK_MAX_PER_RUN=N 每轮最多处理资源任务数，默认 10；0 表示不设上限。" \
        "  PO0_RESOURCE_UPLOAD_TIMEOUT_SECONDS=N 上传资源产物到 PO0 的超时秒数，默认 900；0 表示不设超时。" \
        "  PO0_RESOURCE_COMPLETE_TIMEOUT_SECONDS=N PO0 校验/导入资源产物的超时秒数，默认 600。" \
        "  PO0_REMOTE_MANAGER_TIMEOUT_SECONDS=N 默认 PO0 manager SSH 调用总超时秒数，默认 30；0 表示不设超时。" \
        "  --source-key KEY     PO0 端来源 key/名称；脚本不会解析这个值。" \
        "  --ddns-domain DOMAIN LAN Worker 要解析的 DDNS 域名；结果通过 SSH 上报 PO0。" \
        "  --install-self-report-https --self-report-https-domain DOMAIN  配置 Self-report HTTPS/Caddy，后端监听 127.0.0.1:8788。" \
        "  --install-manager-update-http --manager-update-domain HOST[:PORT]  配置 PO0 manager HTTP 更新镜像，默认公网端口 ${MANAGER_UPDATE_DEFAULT_PORT}，后端监听 127.0.0.1:8789；--manager-update-host 等价。" \
        "  --manager-update-mirror-server 启动 PO0 manager 更新镜像 HTTP 后端。" \
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
        "  --upgrade-self       从 ${DOWNLOAD_URL} 覆盖更新本机 po0-lan-client 命令，设置权限，并输出版本变化和更新内容。" \
        "  --backup-export [PATH] 导出 LAN Worker 完整备份；默认包含 Token、SSH 私钥和 SELF_REPORT_SECRET，备份包 chmod 600。" \
        "  --backup-import PATH  导入备份；默认只恢复配置、状态和密钥。" \
        "  --restore-cron       导入时恢复本机 managed cron block。" \
        "  --restore-systemd    导入时重新生成并启用 LAN Worker systemd service。" \
        "  --restore-caddy      导入时恢复 Self-report Caddy snippet 并刷新 Caddy。" \
        "  --restore-all        导入时恢复 cron、systemd service 和 Caddy snippet。" \
        "  --dry-run            配合 --backup-import 只显示将恢复的文件和入口。" \
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

normalize_report_token_shell() {
    local value="$1" fallback="${2:-self-report}" out="" ch last_dash=0
    value="$(sanitize_field "${value}")"
    if command -v tr >/dev/null 2>&1; then
        value="$(printf '%s' "${value}" | tr '[:upper:]' '[:lower:]')"
    fi
    while [[ -n "${value}" ]]; do
        ch="${value:0:1}"
        value="${value:1}"
        case "${ch}" in
            [a-z0-9._-])
                out+="${ch}"
                last_dash=0
                ;;
            *)
                if [[ "${last_dash}" != "1" ]]; then
                    out+="-"
                    last_dash=1
                fi
                ;;
        esac
    done
    while [[ "${out}" == -* ]]; do out="${out#-}"; done
    while [[ "${out}" == *- ]]; do out="${out%-}"; done
    out="${out:0:48}"
    while [[ "${out}" == *- ]]; do out="${out%-}"; done
    printf '%s\n' "${out:-${fallback}}"
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

default_settings_file() {
    if [[ -n "${SETTINGS_FILE}" ]]; then
        printf '%s\n' "${SETTINGS_FILE}"
    else
        printf '%s/settings.env\n' "$(path_dirname "${CONFIG_FILE}")"
    fi
}

refresh_settings_file() {
    [[ -n "${SETTINGS_FILE}" ]] || SETTINGS_FILE="$(default_settings_file)"
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

lan_state_lock_file() {
    printf '%s/.po0-lan-client.lock\n' "$(path_dirname "${CONFIG_FILE}")"
}

lan_state_lock() {
    local lock_file
    [[ "${LAN_STATE_LOCK_HELD:-0}" == "1" ]] && return 0
    lock_file="$(lan_state_lock_file)"
    mkdir -p "$(path_dirname "${lock_file}")" || return 1
    exec 8>"${lock_file}" || return 1
    if command -v flock >/dev/null 2>&1; then
        flock -w 15 8 || {
            printf 'LAN Worker 配置状态文件正忙，请稍后重试。\n' >&2
            exec 8>&- 2>/dev/null || true
            return 1
        }
    fi
    LAN_STATE_LOCK_HELD=1
}

lan_state_unlock() {
    [[ "${LAN_STATE_LOCK_HELD:-0}" == "1" ]] || return 0
    if command -v flock >/dev/null 2>&1; then
        flock -u 8 2>/dev/null || true
    fi
    exec 8>&- 2>/dev/null || true
    LAN_STATE_LOCK_HELD=0
}

with_lan_state_lock() {
    local rc
    if [[ "${LAN_STATE_LOCK_HELD:-0}" == "1" ]]; then
        "$@"
        return $?
    fi
    lan_state_lock || return 1
    "$@"
    rc=$?
    lan_state_unlock
    return "${rc}"
}

prime_config_paths_from_args() {
    local arg next
    while [[ $# -gt 0 ]]; do
        arg="$1"
        case "${arg}" in
            --config)
                next="${2:-}"
                [[ -n "${next}" ]] && CONFIG_FILE="${next}"
                shift 2 2>/dev/null || shift
                ;;
            --settings-file)
                next="${2:-}"
                [[ -n "${next}" ]] && SETTINGS_FILE="${next}"
                shift 2 2>/dev/null || shift
                ;;
            --config=* )
                CONFIG_FILE="${arg#--config=}"
                shift
                ;;
            --settings-file=* )
                SETTINGS_FILE="${arg#--settings-file=}"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
}

write_env_assignment() {
    local name="$1"
    local value="${2:-}"
    printf '%s=%s\n' "${name}" "$(sh_quote "${value}")"
}

save_local_settings_unlocked() {
    local dir tmp old_umask
    refresh_settings_file
    dir="$(path_dirname "${SETTINGS_FILE}")"
    mkdir -p "${dir}" || return 1
    tmp="${SETTINGS_FILE}.tmp.$$"
    old_umask="$(umask)"
    umask 077
    {
        printf '# Managed by po0-lan-client. Contains local runtime settings and secrets.\n'
        write_env_assignment "CONFIG_FILE" "${CONFIG_FILE}"
        write_env_assignment "STATS_FILE" "${STATS_FILE}"
        write_env_assignment "RESOURCE_STATS_FILE" "${RESOURCE_STATS_FILE}"
        write_env_assignment "RESOURCE_EVENTS_FILE" "${RESOURCE_EVENTS_FILE}"
        write_env_assignment "INSTALL_PATH" "${INSTALL_PATH}"
        write_env_assignment "WORKER_ID" "${WORKER_ID}"
        write_env_assignment "IPDB_DOWNLOAD_URL" "${IPDB_DOWNLOAD_URL}"
        write_env_assignment "IPLIST_JOBS" "${IPLIST_JOBS}"
        write_env_assignment "RESOURCE_TASK_MAX_PER_RUN" "${RESOURCE_TASK_MAX_PER_RUN}"
        write_env_assignment "RESOURCE_UPLOAD_TIMEOUT_SECONDS" "${RESOURCE_UPLOAD_TIMEOUT_SECONDS}"
        write_env_assignment "RESOURCE_COMPLETE_TIMEOUT_SECONDS" "${RESOURCE_COMPLETE_TIMEOUT_SECONDS}"
        write_env_assignment "RESOURCE_CONTROL_TIMEOUT_SECONDS" "${RESOURCE_CONTROL_TIMEOUT_SECONDS}"
        write_env_assignment "RESOURCE_EVENTS_KEEP" "${RESOURCE_EVENTS_KEEP}"
        write_env_assignment "REMOTE_MANAGER_TIMEOUT_SECONDS" "${REMOTE_MANAGER_TIMEOUT_SECONDS}"
        write_env_assignment "REMOTE_STATUS_TIMEOUT_SECONDS" "${REMOTE_STATUS_TIMEOUT_SECONDS}"
        write_env_assignment "SSH_CONNECT_TIMEOUT_SECONDS" "${SSH_CONNECT_TIMEOUT_SECONDS}"
        write_env_assignment "DDNS_CRON_MINUTES" "${DDNS_CRON_MINUTES}"
        write_env_assignment "DDNS_INTERVAL_SECONDS" "$((10#${DDNS_CRON_MINUTES:-60} * 60))"
        write_env_assignment "DDNS_CRON_MAX_MINUTES" "${DDNS_CRON_MAX_MINUTES}"
        write_env_assignment "RESOURCE_CRON_MINUTES" "${RESOURCE_CRON_MINUTES}"
        write_env_assignment "RESOURCE_CRON_MAX_MINUTES" "${RESOURCE_CRON_MAX_MINUTES}"
        write_env_assignment "WEBAUTH_LISTEN" "${WEBAUTH_LISTEN}"
        write_env_assignment "WEBAUTH_SOURCE" "${WEBAUTH_SOURCE}"
        write_env_assignment "WEBAUTH_TOKEN" "${WEBAUTH_TOKEN}"
        write_env_assignment "WEBAUTH_TTL_SECONDS" "${WEBAUTH_TTL_SECONDS}"
        write_env_assignment "WEBAUTH_TARGETS" "${WEBAUTH_TARGETS}"
        write_env_assignment "SELF_REPORT_LISTEN" "${SELF_REPORT_LISTEN}"
        write_env_assignment "SELF_REPORT_SOURCE" "${SELF_REPORT_SOURCE}"
        write_env_assignment "SELF_REPORT_SECRET" "${SELF_REPORT_SECRET}"
        write_env_assignment "SELF_REPORT_TTL_SECONDS" "${SELF_REPORT_TTL_SECONDS}"
        write_env_assignment "SELF_REPORT_TARGETS" "${SELF_REPORT_TARGETS}"
        write_env_assignment "SELF_REPORT_HTTPS_DOMAIN" "${SELF_REPORT_HTTPS_DOMAIN}"
        write_env_assignment "SELF_REPORT_HTTPS_BACKEND" "${SELF_REPORT_HTTPS_BACKEND}"
        write_env_assignment "SELF_REPORT_CADDY_SNIPPET" "${SELF_REPORT_CADDY_SNIPPET}"
        write_env_assignment "MANAGER_UPDATE_LISTEN" "${MANAGER_UPDATE_LISTEN}"
        write_env_assignment "MANAGER_UPDATE_DOMAIN" "${MANAGER_UPDATE_DOMAIN}"
        write_env_assignment "MANAGER_UPDATE_BACKEND" "${MANAGER_UPDATE_BACKEND}"
        write_env_assignment "MANAGER_UPDATE_CADDY_SNIPPET" "${MANAGER_UPDATE_CADDY_SNIPPET}"
        write_env_assignment "CADDYFILE_PATH" "${CADDYFILE_PATH}"
    } > "${tmp}" || {
        umask "${old_umask}"
        rm -f -- "${tmp}" 2>/dev/null || true
        return 1
    }
    umask "${old_umask}"
    replace_file_from_tmp "${tmp}" "${SETTINGS_FILE}" || return 1
    chmod 600 "${SETTINGS_FILE}" 2>/dev/null || true
}

save_local_settings() {
    with_lan_state_lock save_local_settings_unlocked "$@"
}

load_local_settings() {
    local keep_config keep_settings keep_stats keep_resource_stats keep_resource_events loaded=0
    refresh_settings_file
    keep_config="${CONFIG_FILE}"
    keep_settings="${SETTINGS_FILE}"
    keep_stats="${STATS_FILE}"
    keep_resource_stats="${RESOURCE_STATS_FILE}"
    keep_resource_events="${RESOURCE_EVENTS_FILE}"
    if [[ -r "${SETTINGS_FILE}" ]]; then
        # Local file is created by this script with chmod 600 and may contain secrets.
        # shellcheck disable=SC1090
        . "${SETTINGS_FILE}" || return 1
        loaded=1
    fi
    CONFIG_FILE="${keep_config}"
    SETTINGS_FILE="${keep_settings}"
    STATS_FILE="${keep_stats}"
    RESOURCE_STATS_FILE="${keep_resource_stats}"
    RESOURCE_EVENTS_FILE="${keep_resource_events}"
    refresh_stats_file
    refresh_resource_stats_file
    refresh_resource_events_file
    load_settings_from_installed_services "${loaded}" || true
    if [[ -n "${DDNS_INTERVAL_SECONDS:-}" ]]; then
        DDNS_CRON_MINUTES="$(normalize_interval_seconds_to_minutes "${DDNS_INTERVAL_SECONDS}" "${DDNS_CRON_MAX_MINUTES}" 2>/dev/null || printf '%s' "${DDNS_CRON_MINUTES}")"
    fi
    migrate_legacy_report_ttl_defaults
    normalize_report_ttl_settings
}

unit_exec_arg_value() {
    local unit="$1"
    local flag="$2"
    local line rest value
    [[ -r "${unit}" ]] || return 1
    line="$(grep -E '^ExecStart=' "${unit}" 2>/dev/null | tail -n 1)" || return 1
    [[ -n "${line}" ]] || return 1
    rest="${line#* ${flag} }"
    [[ "${rest}" != "${line}" ]] || return 1
    case "${rest}" in
        \'*)
            value="${rest#\'}"
            value="${value%%\'*}"
            ;;
        *)
            value="${rest%%[[:space:]]*}"
            ;;
    esac
    [[ -n "${value}" ]] || return 1
    printf '%s\n' "${value}"
}

fill_setting_from_unit_arg() {
    local loaded="$1"
    local var_name="$2"
    local unit="$3"
    local flag="$4"
    local value
    if [[ "${loaded}" == "1" && -n "${!var_name:-}" ]]; then
        return 0
    fi
    value="$(unit_exec_arg_value "${unit}" "${flag}" 2>/dev/null || true)"
    [[ -n "${value}" ]] || return 0
    printf -v "${var_name}" '%s' "${value}"
}

normalize_report_ttl_seconds() {
    local ttl="${1:-}"
    local fallback="${2:-43200}"
    [[ "${fallback}" =~ ^[0-9]+$ ]] || fallback="43200"
    [[ "${ttl}" =~ ^[0-9]+$ ]] || ttl="${fallback}"
    (( ttl >= 60 )) || ttl=60
    (( ttl <= 604800 )) || ttl=604800
    printf '%s\n' "${ttl}"
}

migrate_legacy_report_ttl_defaults() {
    [[ "${SELF_REPORT_TTL_SECONDS:-}" == "3600" ]] && SELF_REPORT_TTL_SECONDS="43200"
    case "${WEBAUTH_TTL_SECONDS:-}" in
        3600|21600) WEBAUTH_TTL_SECONDS="43200" ;;
    esac
}
