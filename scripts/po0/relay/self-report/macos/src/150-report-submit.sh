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

report_worker_once() {
    local ip response="" curl_rc report_source report_identity curl_args=() http_code
    WORKER_RESULT_MESSAGE=""
    validate_worker_url || {
        printf 'LAN Worker URL 未通过检查。\n' >&2
        WORKER_RESULT_MESSAGE="LAN Worker URL 未通过检查。"
        return 1
    }
    ip="$(detect_outbound_ipv4)" || {
        printf '未能探测到当前公网出口 IPv4。\n' >&2
        WORKER_RESULT_MESSAGE="未能探测到当前公网出口 IPv4。"
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
            WORKER_RESULT_MESSAGE="$(self_report_append_response_target_success "公网出口 IPv4 ${ip} 已被 LAN Worker 接收。" "${response}")"
            return 0
        fi
        [[ -n "${response}" ]] && printf '%s\n' "${response}" >&2
        WORKER_RESULT_MESSAGE="LAN Worker 未确认本次上报（HTTP ${http_code}）。"
        return 1
    fi
    curl_rc="$?"
    [[ -n "${response}" ]] && printf '%s\n' "${response}" >&2
    WORKER_RESULT_MESSAGE="LAN Worker 未确认本次上报（curl exit ${curl_rc}）。"
    return "${curl_rc}"
}

report_once_inner() {
    local official_active="0" worker_active="0" official_rc=0 worker_rc=0
    local success_count=0 failure_count=0 skipped_count=0 status_message=""
    if [[ "${OFFICIAL_STATUS_ONLY:-0}" == "1" ]]; then
        po0_firewall_run status
        return "$?"
    fi
    if should_skip_wifi_ssid_report; then
        self_report_completed "$(wifi_ssid_skip_message "${WIFI_SKIP_LAST_SSID:-}")"
        return 0
    fi
    if [[ "${OFFICIAL_ONLY:-0}" != "1" ]] && [[ -n "${WORKER_URL:-}" ]]; then
        worker_active="1"
    fi
    if [[ "${WORKER_ONLY:-0}" != "1" ]] && [[ -n "${PO0_FIREWALL_TOKENS:-}" ]]; then
        official_active="1"
    fi
    [[ "${official_active}" == "1" || "${worker_active}" == "1" ]] || {
        self_report_incomplete "没有配置可执行的上报通道。"
        notify_report_failure "没有配置可执行的上报通道。"
        return 1
    }
    command -v curl >/dev/null 2>&1 || {
        self_report_incomplete "缺少 curl，无法发起上报。"
        notify_report_failure "缺少 curl，无法发起上报。"
        return 1
    }
    if [[ "${official_active}" == "1" ]]; then
        if [[ "${SCHEDULED_RUN:-0}" != "1" ]] || po0_firewall_due; then
            po0_firewall_run report
            official_rc="$?"
            po0_firewall_mark_due >/dev/null 2>&1 || true
            success_count=$((success_count + PO0_FIREWALL_SUCCESS_COUNT))
            failure_count=$((failure_count + PO0_FIREWALL_FAILURE_COUNT))
            if [[ "${official_rc}" != "0" && "${PO0_FIREWALL_FAILURE_COUNT}" == "0" ]]; then
                failure_count=$((failure_count + 1))
            fi
        else
            skipped_count=$((skipped_count + 1))
        fi
    fi
    if [[ "${worker_active}" == "1" ]]; then
        if [[ "${SCHEDULED_RUN:-0}" != "1" ]] || po0_worker_due; then
            report_worker_once
            worker_rc="$?"
            po0_worker_mark_attempt >/dev/null 2>&1 || true
            if [[ "${worker_rc}" == "0" ]]; then
                success_count=$((success_count + 1))
            else
                failure_count=$((failure_count + 1))
            fi
        else
            skipped_count=$((skipped_count + 1))
        fi
    fi
    if [[ "${failure_count}" -gt 0 ]]; then
        if [[ "${success_count}" -gt 0 ]]; then
            status_message="部分通道完成；失败通道将在各自 due 到达后重试。"
            self_report_incomplete "${status_message}"
            notify_report_failure "${status_message}"
            return 1
        fi
        status_message="上报通道均未完成。"
        self_report_incomplete "${status_message}"
        notify_report_failure "${status_message}"
        return 1
    fi
    if [[ "${success_count}" == "0" && "${skipped_count}" -gt 0 ]]; then
        self_report_completed "本次定时唤醒没有到达通道 due，未发起请求。"
        return 0
    fi
    if [[ "${official_active}" == "1" && "${worker_active}" == "1" ]]; then
        status_message="官方防火墙和 LAN Worker 通道均已完成。"
    elif [[ "${official_active}" == "1" ]]; then
        status_message="官方防火墙通道已完成。"
    else
        status_message="LAN Worker 通道已完成。"
    fi
    self_report_completed "${status_message}"
    notify_report_success "${status_message}"
    return 0
}

report_once() {
    local lock_rc result
    po0_firewall_report_lock_acquire
    lock_rc="$?"
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
