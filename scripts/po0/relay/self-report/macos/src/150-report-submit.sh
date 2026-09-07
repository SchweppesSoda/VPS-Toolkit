notification_log_failure() {
    local message="${1}" log_path log_dir
    log_path="$(self_report_log_path)"
    log_dir="$(path_dirname "${log_path}")"
    [[ -n "${log_dir}" ]] && mkdir -p "${log_dir}" 2>/dev/null || true
    printf '通知失败：%s\n' "${message}" >> "${log_path}" 2>/dev/null || true
}

applescript_quote() {
    local value="${1}"
    value="${value//$'\r'/ }"
    value="${value//$'\n'/ }"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "${value}"
}

send_macos_notification() {
    local title="${1}" message="${2}" script output
    notify_enabled || return 0
    is_macos || { notification_log_failure "当前系统不是 macOS，未发送通知。"; return 0; }
    command -v osascript >/dev/null 2>&1 || {
        notification_log_failure "未找到 osascript，未发送通知。"
        return 0
    }
    script="display notification $(applescript_quote "${message}") with title $(applescript_quote "${title}")"
    if ! output="$(osascript -e "${script}" 2>&1)"; then
        output="$(trim "${output}")"
        [[ -n "${output}" ]] || output="osascript 返回失败。"
        notification_log_failure "${output}"
    fi
    return 0
}

notify_report_success() {
    local message="${1}"
    send_macos_notification "PO0 Outbound IP Report 成功" "${message}"
}

notify_report_failure() {
    local message="${1}"
    send_macos_notification "PO0 Outbound IP Report 失败" "${message}"
}

report_once_inner() {
    [[ "${WORKER_ONLY:-0}" != 1 ]] || { printf '自建上报已退役。\n'; return 0; }
    if [[ "${OFFICIAL_STATUS_ONLY:-0}" == 1 ]]; then po0_firewall_run status; return $?; fi
    if [[ "${SCHEDULED_RUN:-0}" == 1 ]]; then
        schedule_paused && return 0
        channel_auto_enabled official || return 0
        if [[ "${NETWORK_CHANGED:-0}" == 1 ]]; then
            case "${OFFICIAL_NETWORK_ENABLED:-1}" in 0|false|no|off) return 0 ;; esac
        else
            case "${OFFICIAL_TIMER_ENABLED:-1}" in 0|false|no|off) return 0 ;; esac
        fi
    fi
    [[ -n "${PO0_FIREWALL_TOKENS:-}" ]] || { self_report_completed '尚未配置官方上报目标，本轮跳过。'; return 0; }
    if should_skip_wifi_ssid_report; then self_report_completed "$(wifi_ssid_skip_message "${WIFI_SKIP_LAST_SSID:-}")"; return 0; fi
    if [[ "${SCHEDULED_RUN:-0}" == 1 ]] && ! po0_firewall_due; then return 0; fi
    local official_rc=0
    po0_firewall_run report || official_rc=$?
    po0_firewall_mark_due >/dev/null 2>&1 || true
    if [[ "$official_rc" == 0 ]]; then
        self_report_completed '官方防火墙检查完成。'; notify_report_success '官方防火墙检查完成。'
    else
        self_report_incomplete '官方防火墙操作未完成。'; notify_report_failure '官方防火墙操作未完成。'
    fi
    return "$official_rc"
}

report_once() {
    local lock_rc result
    po0_firewall_report_lock_acquire
    lock_rc="$?"
    local wait_count=0
    while [[ "$lock_rc" == 2 && "${SCHEDULED_RUN:-0}" == 1 && "$wait_count" -lt "${REPORT_LOCK_WAIT_SECONDS:-120}" ]]; do
        sleep 1
        po0_firewall_report_lock_acquire
        lock_rc=$?
        wait_count=$((wait_count + 1))
    done
    if [[ "$lock_rc" == "2" ]]; then
        self_report_incomplete "已有另一项上报或状态检查正在进行，本次未重复执行。"
        return 1
    fi
    if [[ "$lock_rc" != "0" ]]; then
        self_report_incomplete "无法建立上报互斥状态，本次未执行。"
        return 1
    fi
    report_once_inner
    result="$?"
    po0_firewall_report_lock_release >/dev/null 2>&1 || true
    return "$result"
}
