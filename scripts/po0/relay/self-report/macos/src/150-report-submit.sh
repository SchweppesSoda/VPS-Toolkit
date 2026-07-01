notification_log_failure() {
    local message="$1" log_path log_dir
    log_path="$(self_report_log_path)"
    log_dir="$(path_dirname "${log_path}")"
    [[ -n "${log_dir}" ]] && mkdir -p "${log_dir}" 2>/dev/null || true
    printf '通知失败：%s\n' "${message}" >> "${log_path}" 2>/dev/null || true
}

applescript_quote() {
    local value="$1"
    value="${value//$'\r'/ }"
    value="${value//$'\n'/ }"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "${value}"
}

send_macos_notification() {
    local title="$1" message="$2" script output
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
    local message="$1"
    send_macos_notification "PO0 Outbound IP Report 成功" "${message}"
}

notify_report_failure() {
    local message="$1"
    send_macos_notification "PO0 Outbound IP Report 失败" "${message}"
}

report_once() {
    local ip response curl_rc report_source report_identity curl_args=() http_code success_message
    if should_skip_wifi_ssid_report; then
        self_report_completed "$(wifi_ssid_skip_message "${WIFI_SKIP_LAST_SSID:-}")"
        return 0
    fi
    validate_worker_url || { self_report_incomplete "LAN Worker URL 未通过检查。"; notify_report_failure "LAN Worker URL 未通过检查。"; return 1; }
    command -v curl >/dev/null 2>&1 || {
        echo "缺少 curl，无法上报到 LAN Worker。" >&2
        self_report_incomplete "缺少 curl，无法发起上报。"
        notify_report_failure "缺少 curl，无法发起上报。"
        return 1
    }
    ip="$(detect_outbound_ipv4)" || {
        echo "未能探测到当前公网出口 IPv4。" >&2
        self_report_incomplete "未能探测到当前公网出口 IPv4。"
        notify_report_failure "未能探测到当前公网出口 IPv4。"
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
            success_message="$(self_report_append_response_target_success "公网出口 IPv4 ${ip} 已被 LAN Worker 接收。" "${response}")"
            self_report_completed "${success_message}"
            notify_report_success "${success_message}"
        else
            [[ -n "${response}" ]] && printf '%s\n' "${response}" >&2
            self_report_incomplete "LAN Worker 未确认本次上报（HTTP ${http_code}）。"
            notify_report_failure "LAN Worker 未确认本次上报（HTTP ${http_code}）。"
            return 1
        fi
    else
        curl_rc=$?
        [[ -n "${response}" ]] && printf '%s\n' "${response}" >&2
        self_report_incomplete "LAN Worker 未确认本次上报（curl exit ${curl_rc}）。"
        notify_report_failure "LAN Worker 未确认本次上报（curl exit ${curl_rc}）。"
        return "${curl_rc}"
    fi
}
