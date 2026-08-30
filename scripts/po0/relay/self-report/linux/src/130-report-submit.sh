report_detail_output_enabled() {
    if declare -F report_detail_enabled >/dev/null 2>&1; then
        report_detail_enabled
    else
        return 0
    fi
}

report_once() {
    local wan_targets wan l3_device ip response curl_rc report_source report_identity
    local http_code success_message label total=0 success_count=0 failure_count=0
    local curl_args=()
    validate_worker_url || { self_report_incomplete "LAN Worker URL 未通过检查。"; return 1; }
    validate_router_probe_url || { self_report_incomplete "上游路由器 WAN 探针 URL 未通过检查。"; return 1; }
    if skip_report_for_wifi_ssid_if_needed; then
        return 0
    fi
    command -v curl >/dev/null 2>&1 || {
        echo "缺少 curl，无法上报到 LAN Worker。" >&2
        self_report_incomplete "缺少 curl，无法发起上报。"
        return 1
    }
    WANS="$(normalize_wan_selection_list "${WANS:-}")"
    validate_wan_selection || {
        self_report_incomplete "WAN 选择配置无效。"
        return 1
    }
    prepare_router_probe_batch
    wan_targets="$(resolve_report_wans)" || {
        if [[ -n "${ROUTER_PROBE_URL}" ]]; then
            self_report_incomplete "上游路由器探针没有返回可用 WAN。"
        else
            self_report_incomplete "--wan all 需要 OpenWrt、ubus、uci 和至少一个已启用的 mwan3 WAN。"
        fi
        return 1
    }
    while IFS= read -r wan; do
        [[ -n "${wan}" ]] || continue
        total=$((total + 1))
        if [[ "${wan}" == "__default__" ]]; then
            wan=""
            l3_device=""
            label="当前默认路由"
            report_source="$(normalize_report_token "${SOURCE_ID}" "$(default_source_id)")"
            report_identity="$(normalize_report_token "${IDENTITY}" "${report_source}")"
        else
            if [[ -n "${ROUTER_PROBE_URL}" ]]; then
                l3_device=""
                label="上游路由器 WAN ${wan}"
            else
                l3_device="$(openwrt_wan_l3_device "${wan}")" || {
                    printf 'OpenWrt WAN %s 不存在、未启用或没有可用的三层设备。\n' "${wan}" >&2
                    failure_count=$((failure_count + 1))
                    continue
                }
                label="WAN ${wan}（${l3_device}）"
            fi
            report_source="$(wan_scoped_report_token "${SOURCE_ID}" "${wan}" "$(default_source_id)")"
            report_identity="$(wan_scoped_report_token "${IDENTITY}" "${wan}" "${report_source}")"
        fi
        if [[ -n "${ROUTER_PROBE_URL}" && -n "${wan}" ]]; then
            ip="$(detect_outbound_ipv4_via_router "${wan}")"
        else
            ip="$(detect_outbound_ipv4 "${l3_device}")"
        fi || {
            printf '未能通过%s探测到公网出口 IPv4。\n' "${label}" >&2
            failure_count=$((failure_count + 1))
            continue
        }
        report_detail_output_enabled && echo "上报${label}的公网出口 IPv4 ${ip} 到 LAN Worker：${WORKER_URL}"
        curl_args=(-sS --get --connect-timeout 10 --max-time 30)
        if [[ -n "${SECRET}" ]]; then
            curl_args+=(-H "X-PO0-Token: ${SECRET}")
        fi
        curl_args+=(--data-urlencode "source=${report_source}")
        curl_args+=(--data-urlencode "ip=${ip}")
        curl_args+=(--data-urlencode "identity=${report_identity}")
        curl_args+=(-w $'\n%{http_code}')
        curl_args+=("${WORKER_URL}")
        response=""
        if response="$(curl "${curl_args[@]}")"; then
            http_code="${response##*$'\n'}"
            response="${response%$'\n'*}"
            if [[ "${http_code}" == 2* ]]; then
                if [[ -n "${response}" ]] && report_detail_output_enabled; then printf '%s\n' "${response}"; fi
                success_message="$(self_report_append_response_target_success "${label}的公网出口 IPv4 ${ip} 已被 LAN Worker 接收。" "${response}")"
                self_report_completed "${success_message}"
                success_count=$((success_count + 1))
            else
                if [[ -n "${response}" ]] && report_detail_output_enabled; then printf '%s\n' "${response}" >&2; fi
                self_report_incomplete "${label}的上报未被 LAN Worker 确认（HTTP ${http_code}）。"
                failure_count=$((failure_count + 1))
            fi
        else
            curl_rc=$?
            if [[ -n "${response}" ]] && report_detail_output_enabled; then printf '%s\n' "${response}" >&2; fi
            self_report_incomplete "${label}的上报未被 LAN Worker 确认（curl exit ${curl_rc}）。"
            failure_count=$((failure_count + 1))
        fi
    done <<< "${wan_targets}"
    if (( total == 0 )); then
        self_report_incomplete "没有找到需要上报的 WAN。"
        return 1
    fi
    if (( failure_count > 0 )); then
        self_report_incomplete "WAN 上报结束：成功 ${success_count} 条，失败 ${failure_count} 条。"
        return 1
    fi
    if [[ -n "${WANS}" ]]; then
        self_report_completed "WAN 上报结束：成功 ${success_count} 条，失败 0 条。"
    fi
}
