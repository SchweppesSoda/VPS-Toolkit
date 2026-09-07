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

worker_channel_requested() {
    case "$(to_lower "${WORKER_ENABLED:-}")" in
        0|false|no|off) return 1 ;;
        1|true|yes|on|y) return 0 ;;
        *) [[ -n "${WORKER_URL:-}" ]] ;;
    esac
}

config_complete() {
    # A configured official channel is usable independently of Worker validation.
    if [[ "${WORKER_ONLY:-0}" != 1 && -n "${PO0_FIREWALL_TOKENS:-}" ]]; then return 0; fi
    [[ "${OFFICIAL_ONLY:-0}" != 1 ]] || return 1
    local worker_requested=0 official_requested=0
    if worker_channel_requested; then
        worker_requested=1
        validate_worker_url >/dev/null 2>&1 || return 1
    fi
    if declare -F official_channel_enabled >/dev/null 2>&1 && official_channel_enabled; then
        official_requested=1
        official_validate_tokens >/dev/null 2>&1 || return 1
    fi
    (( worker_requested == 1 || official_requested == 1 )) || return 1
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
