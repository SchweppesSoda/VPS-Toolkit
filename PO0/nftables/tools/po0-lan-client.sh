#!/usr/bin/env bash
set -uo pipefail

PO0_HOST="${PO0_HOST:-}"
PO0_PORT="${PO0_PORT:-22}"
PO0_USER="${PO0_USER:-root}"
PO0_SCRIPT="${PO0_SCRIPT:-/root/nftables-relay-manager.sh}"
DDNS_DOMAIN="${DDNS_DOMAIN:-}"
REPORT_KEY="${REPORT_KEY:-${DDNS_NAME:-}}"
DDNS_TOKEN="${DDNS_TOKEN:-}"
RESOURCE_TOKEN="${PO0_RESOURCE_TOKEN:-}"
SSH_EXTRA_ARGS="${SSH_EXTRA_ARGS:-}"
CONFIG_FILE="${PO0_LAN_CLIENT_CONFIG:-}"
STATS_FILE="${PO0_LAN_CLIENT_STATS:-}"
RESOURCE_STATS_FILE="${PO0_LAN_RESOURCE_STATS:-}"
IPDB_DOWNLOAD_URL="${PO0_IPDB_DOWNLOAD_URL:-https://raw.githubusercontent.com/nmgliangwei/qqwry.ipdb/main/qqwry.ipdb}"
WORKER_ID="${PO0_WORKER_ID:-$(hostname 2>/dev/null || printf 'po0-worker')}"
STATS_FILE_EXPLICIT="0"
ACTION=""
CRON_MINUTES="5"

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
        "用法:" \
        "  bash po0-lan-client.sh" \
        "" \
        "直接进入中文菜单，可管理 DDNS 上报和 PO0 资源更新任务。" \
        "资源任务由 PO0 创建，本机主动领取，构建/下载后通过 SCP 回传。" \
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

resolve_public_ipv4_records() {
    local domain="$1"
    local candidates="" ip out="" seen=" " line first rest found
    if command -v getent >/dev/null 2>&1; then
        while read -r first rest; do
            candidates+=" ${first}"
        done < <(getent ahostsv4 "${domain}" 2>/dev/null || true)
    fi
    if command -v dig >/dev/null 2>&1; then
        while read -r first rest; do
            candidates+=" ${first}"
        done < <(dig +short A "${domain}" 2>/dev/null || true)
    fi
    if command -v host >/dev/null 2>&1; then
        while IFS= read -r line || [[ -n "${line}" ]]; do
            for first in ${line}; do
                candidates+=" ${first}"
            done
        done < <(host -t A "${domain}" 2>/dev/null || true)
    fi
    if command -v nslookup >/dev/null 2>&1; then
        found=0
        while read -r first rest; do
            case "${first}" in
                Name:*)
                    found=1
                    ;;
                Address:*)
                    [[ "${found}" == "1" ]] && candidates+=" ${rest%% *}"
                    ;;
            esac
        done < <(nslookup -type=A "${domain}" 2>/dev/null || true)
    fi
    for ip in ${candidates}; do
        ip="$(trim "${ip}")"
        is_public_ipv4 "${ip}" || continue
        [[ "${seen}" == *" ${ip} "* ]] && continue
        seen+="${ip} "
        if [[ -z "${out}" ]]; then
            out="${ip}"
        else
            out+=",${ip}"
        fi
    done
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
            printf '# enabled|label|domain|report_key|po0_host|po0_port|po0_user|po0_script|ddns_token|ssh_extra_args|resource_token\n'
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
        IFS='|' read -r TARGET_ENABLED TARGET_LABEL TARGET_DOMAIN TARGET_REPORT_KEY TARGET_PO0_HOST TARGET_PO0_PORT TARGET_PO0_USER TARGET_PO0_SCRIPT TARGET_TOKEN TARGET_SSH_EXTRA_ARGS TARGET_RESOURCE_TOKEN <<< "${line}"
    else
        read -r TARGET_ENABLED TARGET_LABEL TARGET_DOMAIN TARGET_REPORT_KEY TARGET_PO0_HOST TARGET_PO0_PORT TARGET_PO0_USER TARGET_PO0_SCRIPT TARGET_TOKEN TARGET_SSH_EXTRA_ARGS TARGET_RESOURCE_TOKEN <<< "${line}"
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
    [[ -n "${TARGET_DOMAIN}" && -n "${TARGET_PO0_HOST}" ]] || return 1
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
    local line idx=1 status key_label target_id
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
        key_label="${TARGET_REPORT_KEY:-${TARGET_DOMAIN}}"
        target_id="$(target_id_for "${TARGET_DOMAIN}" "${key_label}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT:-22}" "${TARGET_PO0_USER:-root}")"
        printf '  %2d) %-4s %-14s 域名=%s key=%s PO0=%s@%s:%s\n' \
            "${idx}" "${status}" "${TARGET_LABEL:-未命名}" "${TARGET_DOMAIN}" "${key_label}" "${TARGET_PO0_USER:-root}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT:-22}"
        print_target_stats "${target_id}"
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
    ensure_config_file || return 1
    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
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
        "$(sanitize_field "${resource_token}")" >> "${CONFIG_FILE}"
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
    local label domain report_key po0_host po0_port po0_user po0_script token ssh_extra_args resource_token
    ensure_config_file || return 1
    printf '\n添加 DDNS 外部上报目标\n'
    domain="$(prompt_default "DDNS 域名" "${DDNS_DOMAIN}")"
    [[ -n "${domain}" ]] || { printf '域名不能为空。\n' >&2; return 1; }
    label="$(prompt_default "显示名" "${domain}")"
    report_key="$(prompt_default "PO0 匹配 key，默认直接用域名" "${domain}")"
    po0_host="$(prompt_default "PO0 SSH 地址" "${PO0_HOST}")"
    [[ -n "${po0_host}" ]] || { printf 'PO0 SSH 地址不能为空。\n' >&2; return 1; }
    po0_port="$(prompt_default "PO0 SSH 端口" "${PO0_PORT:-22}")"
    po0_user="$(prompt_default "PO0 SSH 用户" "${PO0_USER:-root}")"
    po0_script="$(prompt_default "PO0 管理脚本路径" "${PO0_SCRIPT:-/root/nftables-relay-manager.sh}")"
    token="$(prompt_default "DDNS 上报 token，可空" "${DDNS_TOKEN}")"
    resource_token="$(prompt_default "资源任务 Token，可空" "${RESOURCE_TOKEN}")"
    ssh_extra_args="$(prompt_default "额外 SSH 参数，可空" "${SSH_EXTRA_ARGS}")"
    append_target "1" "${label}" "${domain}" "${report_key}" "${po0_host}" "${po0_port}" "${po0_user}" "${po0_script}" "${token}" "${ssh_extra_args}" "${resource_token}" || return 1
    printf '已添加：%s -> %s\n' "${domain}" "${po0_host}"
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
            printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
                "${TARGET_ENABLED}" "${TARGET_LABEL}" "${TARGET_DOMAIN}" "${TARGET_REPORT_KEY}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT}" "${TARGET_PO0_USER}" "${TARGET_PO0_SCRIPT}" "${TARGET_TOKEN}" "${TARGET_SSH_EXTRA_ARGS}" "${TARGET_RESOURCE_TOKEN}" >> "${tmp}"
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
    local enabled label domain report_key po0_host po0_port po0_user po0_script token ssh_extra_args resource_token
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
            break
        fi
    done < "${CONFIG_FILE}"
    [[ -n "${domain:-}" ]] || return 1

    printf '\n编辑目标；直接回车保留当前值。\n'
    label="$(prompt_default "显示名" "${label}")"
    domain="$(prompt_default "DDNS 域名" "${domain}")"
    report_key="$(prompt_default "PO0 匹配 key" "${report_key:-${domain}}")"
    po0_host="$(prompt_default "PO0 SSH 地址" "${po0_host}")"
    po0_port="$(prompt_default "PO0 SSH 端口" "${po0_port:-22}")"
    po0_user="$(prompt_default "PO0 SSH 用户" "${po0_user:-root}")"
    po0_script="$(prompt_default "PO0 管理脚本路径" "${po0_script:-/root/nftables-relay-manager.sh}")"
    token="$(prompt_default "DDNS 上报 Token，可空" "${token}")"
    resource_token="$(prompt_default "资源任务 Token，可空" "${resource_token}")"
    ssh_extra_args="$(prompt_default "额外 SSH 参数，可空" "${ssh_extra_args}")"
    [[ -n "${domain}" && -n "${po0_host}" ]] || {
        printf '域名和 PO0 SSH 地址不能为空。\n' >&2
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
            printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
                "${enabled}" "$(sanitize_field "${label}")" "$(sanitize_field "${domain}")" "$(sanitize_field "${report_key}")" \
                "$(sanitize_field "${po0_host}")" "$(sanitize_field "${po0_port}")" "$(sanitize_field "${po0_user}")" \
                "$(sanitize_field "${po0_script}")" "$(sanitize_field "${token}")" "$(sanitize_field "${ssh_extra_args}")" \
                "$(sanitize_field "${resource_token}")" >> "${tmp}"
            continue
        fi
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${CONFIG_FILE}"
    replace_config_from_tmp "${tmp}"
    prune_stats_to_current_targets || true
    printf '已更新目标 %s。\n' "${selected}"
}

report_once() {
    local domain="$1"
    local report_key="$2"
    local po0_host="$3"
    local po0_port="$4"
    local po0_user="$5"
    local po0_script="$6"
    local token="$7"
    local ssh_extra_args="${8:-}"
    local ip_csv remote_cmd target_id
    local -a ssh_args=()
    [[ -n "${domain}" ]] || { printf '缺少 DDNS 域名。\n' >&2; return 1; }
    [[ -n "${po0_host}" ]] || { printf '缺少 PO0 SSH 地址。\n' >&2; return 1; }
    [[ -n "${report_key}" ]] || report_key="${domain}"
    [[ -n "${po0_port}" ]] || po0_port="22"
    [[ -n "${po0_user}" ]] || po0_user="root"
    [[ -n "${po0_script}" ]] || po0_script="/root/nftables-relay-manager.sh"
    target_id="$(target_id_for "${domain}" "${report_key}" "${po0_host}" "${po0_port}" "${po0_user}")"

    ip_csv="$(resolve_public_ipv4_records "${domain}")" || {
        printf '解析失败：%s 没有可用公网 IPv4。\n' "${domain}" >&2
        update_target_stats "${target_id}" "失败" "" "解析失败：没有可用公网 IPv4" || true
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

    printf '上报：%s -> %s@%s:%s，IP=%s\n' "${domain}" "${po0_user}" "${po0_host}" "${po0_port}" "${ip_csv}"
    if ! ssh "${ssh_args[@]}" "${po0_user}@${po0_host}" "${remote_cmd}"; then
        printf '上报失败：%s -> %s\n' "${domain}" "${po0_host}" >&2
        update_target_stats "${target_id}" "失败" "${ip_csv}" "SSH 或 PO0 上报命令失败" || true
        return 1
    fi
    update_target_stats "${target_id}" "成功" "${ip_csv}" "" || true
}

run_config_targets() {
    local line ok=0 fail=0 skipped=0
    ensure_config_file || return 1
    prune_stats_to_current_targets || true
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        if [[ "${TARGET_ENABLED}" != "1" ]]; then
            ((skipped++))
            continue
        fi
        if report_once "${TARGET_DOMAIN}" "${TARGET_REPORT_KEY:-${TARGET_DOMAIN}}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT}" "${TARGET_PO0_USER}" "${TARGET_PO0_SCRIPT}" "${TARGET_TOKEN}" "${TARGET_SSH_EXTRA_ARGS}"; then
            ((ok++))
        else
            ((fail++))
        fi
    done < "${CONFIG_FILE}"
    printf '上报完成：成功 %s，失败 %s，停用跳过 %s。\n' "${ok}" "${fail}" "${skipped}"
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
        if run_resource_endpoint "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT:-22}" "${TARGET_PO0_USER:-root}" "${TARGET_PO0_SCRIPT:-/root/nftables-relay-manager.sh}" "${TARGET_RESOURCE_TOKEN}" "${TARGET_SSH_EXTRA_ARGS}"; then
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

print_cron_example() {
    local minutes="$1"
    local script_path
    [[ "${minutes}" =~ ^[0-9]+$ && "${minutes}" -ge 1 && "${minutes}" -le 59 ]] || minutes="5"
    script_path="$(script_self_path)"
    printf '%s\n' \
        "cron 示例（每 ${minutes} 分钟执行 DDNS 上报并轮询资源任务）：" \
        "*/${minutes} * * * * bash $(sh_quote "${script_path}") --config $(sh_quote "${CONFIG_FILE}") --run >/tmp/po0-lan-client.log 2>&1"
}

script_self_path() {
    local script="${BASH_SOURCE[0]}"
    case "${script}" in
        /*)
            printf '%s\n' "${script}"
            ;;
        *)
            printf '%s/%s\n' "$(pwd -P)" "${script}"
            ;;
    esac
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
    local minutes script_path job tmp
    ensure_config_file || return 1
    command -v crontab >/dev/null 2>&1 || {
        printf '当前系统没有 crontab 命令。请先安装 cron，或改用 systemd timer。\n' >&2
        return 1
    }
    minutes="$(prompt_default "每几分钟上报一次（1-59）" "${CRON_MINUTES}")"
    minutes="$(trim "${minutes}")"
    [[ "${minutes}" =~ ^[0-9]+$ && "${minutes}" -ge 1 && "${minutes}" -le 59 ]] || {
        printf '分钟数无效。\n' >&2
        return 1
    }
    script_path="$(script_self_path)"
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
    printf '已安装/更新定时任务：每 %s 分钟执行 DDNS 上报和资源任务轮询。\n' "${minutes}"
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
        printf '\n%s\n' "PO0 内网协作客户端"
        printf '%s\n' "配置文件：${CONFIG_FILE}"
        printf '%s\n' "  1) 查看上报目标和统计"
        printf '%s\n' "  2) 添加上报目标"
        printf '%s\n' "  3) 编辑上报目标"
        printf '%s\n' "  4) 删除上报目标"
        printf '%s\n' "  5) 启用 / 停用上报目标"
        printf '%s\n' "  6) 立即执行 DDNS 上报"
        printf '%s\n' "  7) 立即领取并执行资源任务"
        printf '%s\n' "  8) 查看本机资源任务统计"
        printf '%s\n' "  9) 安装 / 更新定时任务"
        printf '%s\n' " 10) 删除定时任务"
        printf '%s\n' " 11) 查看定时任务状态"
        printf '%s\n' " 12) 清空本机 DDNS 上报统计"
        printf '%s\n' "  0) 退出"
        read -r -p "请选择操作 [0-12]: " choice
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
        --domain)
            require_arg_value "$@"
            DDNS_DOMAIN="${2:-}"
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
        --menu)
            ACTION="menu"
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
    print-cron)
        print_cron_example "${CRON_MINUTES}"
        exit $?
        ;;
esac

if [[ -z "${PO0_HOST}" && -z "${DDNS_DOMAIN}" ]]; then
    menu_loop
    exit $?
fi

report_once "${DDNS_DOMAIN}" "${REPORT_KEY:-${DDNS_DOMAIN}}" "${PO0_HOST}" "${PO0_PORT}" "${PO0_USER}" "${PO0_SCRIPT}" "${DDNS_TOKEN}" "${SSH_EXTRA_ARGS}"
