self_report_service_summary() {
    local name="po0-lan-self-report.service" unit="/etc/systemd/system/po0-lan-self-report.service" active enabled unit_ttl current_ttl
    have_cmd systemctl || {
        printf 'systemctl 不可用'
        return 0
    }
    active="$(systemctl is-active "${name}" 2>/dev/null || true)"
    enabled="$(systemctl is-enabled "${name}" 2>/dev/null || true)"
    printf 'active=%s enabled=%s' "${active:-unknown}" "${enabled:-unknown}"
    unit_ttl="$(unit_exec_arg_value "${unit}" "--self-report-ttl" 2>/dev/null || true)"
    current_ttl="$(normalize_report_ttl_seconds "${SELF_REPORT_TTL_SECONDS:-43200}" 43200)"
    if [[ -n "${unit_ttl}" ]]; then
        unit_ttl="$(normalize_report_ttl_seconds "${unit_ttl}" "${current_ttl}")"
        if [[ "${unit_ttl}" != "${current_ttl}" ]]; then
            printf ' unit-ttl=%s' "${unit_ttl}"
            [[ "${unit_ttl}" == "3600" ]] && printf '（旧默认；安装/更新服务后刷新）'
        fi
    fi
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
