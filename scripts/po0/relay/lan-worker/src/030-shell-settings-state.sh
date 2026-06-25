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
