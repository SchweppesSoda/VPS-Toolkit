report_once() {
    local ip response curl_rc report_source report_identity curl_args=() http_code success_message
    validate_worker_url || { self_report_incomplete "LAN Worker URL 未通过检查。"; return 1; }
    command -v curl >/dev/null 2>&1 || {
        echo "缺少 curl，无法上报到 LAN Worker。" >&2
        self_report_incomplete "缺少 curl，无法发起上报。"
        return 1
    }
    ip="$(detect_outbound_ipv4)" || {
        echo "未能探测到当前公网出口 IPv4。" >&2
        self_report_incomplete "未能探测到当前公网出口 IPv4。"
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
        else
            [[ -n "${response}" ]] && printf '%s\n' "${response}" >&2
            self_report_incomplete "LAN Worker 未确认本次上报（HTTP ${http_code}）。"
            return 1
        fi
    else
        curl_rc=$?
        [[ -n "${response}" ]] && printf '%s\n' "${response}" >&2
        self_report_incomplete "LAN Worker 未确认本次上报（curl exit ${curl_rc}）。"
        return "${curl_rc}"
    fi
}
