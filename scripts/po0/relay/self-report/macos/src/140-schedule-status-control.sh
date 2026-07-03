cron_job_has_schedule() {
    local line="$1" minute hour day month weekday rest
    read -r minute hour day month weekday rest <<< "${line}"
    [[ -n "${minute:-}" && -n "${hour:-}" && -n "${day:-}" && -n "${month:-}" && -n "${weekday:-}" ]]
}

cron_job_interval_label() {
    local line="$1" minute hour day month weekday rest
    read -r minute hour day month weekday rest <<< "${line}"
    if [[ "${line}" =~ now[[:space:]]*/[[:space:]]*60[[:space:]]*\\%[[:space:]]*([0-9]+) ]]; then
        cron_interval_label_from_minutes "${BASH_REMATCH[1]}"
        return $?
    fi
    if [[ "${line}" =~ now[[:space:]]*/[[:space:]]*3600[[:space:]]*\\%[[:space:]]*([0-9]+) ]]; then
        cron_interval_label_from_minutes "$((10#${BASH_REMATCH[1]} * 60))"
        return $?
    fi
    if [[ "${minute:-}" =~ ^\*/([0-9]+)$ && "${hour:-}" == "*" ]]; then
        cron_interval_label_from_minutes "${BASH_REMATCH[1]}"
    elif [[ "${minute:-}" == "0" && "${hour:-}" == "*" && "${day:-}" == "*" && "${month:-}" == "*" && "${weekday:-}" == "*" ]]; then
        cron_interval_label_from_minutes 60
    elif [[ "${minute:-}" == "0" && "${hour:-}" =~ ^\*/([0-9]+)$ && "${day:-}" == "*" && "${month:-}" == "*" && "${weekday:-}" == "*" ]]; then
        cron_interval_label_from_minutes "$((10#${BASH_REMATCH[1]} * 60))"
    elif [[ "${minute:-}" == "0" && "${hour:-}" == "0" && "${day:-}" == "*" && "${month:-}" == "*" && "${weekday:-}" == "*" ]]; then
        cron_interval_label_from_minutes 1440
    else
        return 1
    fi
}

cron_job_has_scheduled_run_flag() {
    local line="$1"
    [[ "${line}" == *"--scheduled-run"* ]]
}

read_cron_status_snapshot() {
    local line in_block=0 found=0 legacy_block=0 active_job="" paused_job="" metadata_interval="" job=""
    local state interval="" config_paused consistency="ok"
    config_paused="$(schedule_paused && printf '1' || printf '0')"
    if ! command -v crontab >/dev/null 2>&1; then
        if launchd_supported; then
            read_launchd_status_snapshot
            return 0
        fi
        printf 'unavailable||%s||ok\n' "${config_paused}"
        return 0
    fi
    while IFS= read -r line || [[ -n "${line}" ]]; do
        case "${line}" in
            "# OUTBOUND_IP_REPORT_BEGIN"*) in_block=1; found=1; legacy_block=0; continue ;;
            "# OUTBOUND_IP_REPORT_END"*) in_block=0; continue ;;
            "# PO0_OUTBOUND_IP_REPORT_BEGIN"*) in_block=1; found=1; legacy_block=1; continue ;;
            "# PO0_OUTBOUND_IP_REPORT_END"*) in_block=0; continue ;;
            "# PO0_SELF_REPORT_BEGIN"*) in_block=1; found=1; legacy_block=1; continue ;;
            "# PO0_SELF_REPORT_END"*) in_block=0; continue ;;
        esac
        [[ "${in_block}" == "1" ]] || continue
        case "${line}" in
            "# interval_minutes="*)
                metadata_interval="${line#"# interval_minutes="}"
                ;;
            "# paused="*|"")
                ;;
            \#*)
                job="${line#\#}"
                job="${job# }"
                if cron_job_has_schedule "${job}"; then
                    paused_job="${job}"
                fi
                ;;
            *)
                if cron_job_has_schedule "${line}"; then
                    active_job="${line}"
                fi
                ;;
        esac
    done < <(crontab -l 2>/dev/null || true)

    if [[ "${found}" != "1" ]]; then
        if launchd_supported && { [[ -f "$(launchd_plist_path)" ]] || legacy_launchd_plist_exists; }; then
            read_launchd_status_snapshot
            return 0
        fi
        printf 'uninstalled||%s||ok\n' "${config_paused}"
        return 0
    fi
    if [[ -n "${active_job}" ]]; then
        state="running"
        job="${active_job}"
    elif [[ -n "${paused_job}" ]]; then
        state="paused"
        job="${paused_job}"
    else
        printf 'invalid||%s||ok\n' "${config_paused}"
        return 0
    fi

    if ! interval="$(cron_interval_label_from_minutes "${metadata_interval}" 2>/dev/null)"; then
        interval="$(cron_job_interval_label "${job}" 2>/dev/null || true)"
    fi
    if [[ "${state}" == "running" && "${config_paused}" == "1" ]]; then
        consistency="drift"
    elif [[ "${state}" == "paused" && "${config_paused}" != "1" ]]; then
        consistency="drift"
    fi
    if [[ "${job}" == *"po0-self-report"* || "${legacy_block}" == "1" ]]; then
        consistency="legacy"
    elif ! cron_job_has_scheduled_run_flag "${job}"; then
        if [[ "${consistency}" == "ok" ]]; then
            consistency="stale-scheduled-run"
        else
            consistency="${consistency},stale-scheduled-run"
        fi
    fi
    printf '%s|%s|%s|%s|%s\n' "${state}" "${interval}" "${config_paused}" "${job}" "${consistency}"
}

cron_state_label() {
    case "$1" in
        running) printf '运行中' ;;
        paused) printf '已暂停' ;;
        uninstalled) printf '未安装' ;;
        unavailable) printf '不可用（缺少 crontab，且当前环境不能使用 macOS launchd）' ;;
        invalid) printf '异常：定时任务配置不完整' ;;
        *) printf '未知' ;;
    esac
}

cron_status_summary() {
    local state interval config_paused job consistency summary
    IFS='|' read -r state interval config_paused job consistency < <(read_cron_status_snapshot)
    case "${state}" in
        running|paused)
            summary="$(cron_state_label "${state}")"
            [[ -n "${interval}" ]] && summary="${summary}，${interval}"
            [[ "${consistency}" == *"drift"* ]] && summary="${summary}（与配置暂停标记不一致）"
            [[ "${consistency}" == *"stale-scheduled-run"* ]] && summary="${summary}（旧版定时任务缺少自动运行标记，需刷新）"
            [[ "${consistency}" == *"legacy"* ]] && summary="${summary}（旧命令，需刷新）"
            printf '%s' "${summary}"
            ;;
        *)
            cron_state_label "${state}"
            ;;
    esac
}

macos_expected_cron_job() {
    local script="$1" run_cmd
    run_cmd="bash $(sh_quote "${script}") --config $(sh_quote "${CONFIG_FILE}") --scheduled-run"
    if notify_enabled; then
        run_cmd="${run_cmd} --notify"
    fi
    run_cmd="${run_cmd} >$(sh_quote "$(self_report_log_path)") 2>&1"
    build_cron_job "${CRON_MINUTES}" "${run_cmd}"
}

macos_cron_refresh_current() {
    local script="$1" state interval config_paused job consistency expected_job expected_paused expected_state
    IFS='|' read -r state interval config_paused job consistency < <(read_cron_status_snapshot)
    [[ "${state}" == "running" || "${state}" == "paused" ]] || return 1
    [[ "${consistency}" == "ok" ]] || return 1
    [[ "${job}" != launchd:* ]] || return 1
    expected_job="$(macos_expected_cron_job "${script}")"
    [[ "${job}" == "${expected_job}" ]] || return 1
    expected_paused="$(schedule_paused && printf '1' || printf '0')"
    [[ "${config_paused}" == "${expected_paused}" ]] || return 1
    if schedule_paused; then
        expected_state="paused"
    else
        expected_state="running"
    fi
    [[ "${state}" == "${expected_state}" ]] || return 1
}

macos_launchd_refresh_current() {
    local script="$1" plist state interval config_paused job consistency expected_paused expected_state
    launchd_supported || return 1
    plist="$(launchd_plist_path)"
    [[ -f "${plist}" ]] || return 1
    ! legacy_launchd_plist_exists || return 1
    if command -v crontab >/dev/null 2>&1 && cron_managed_block_exists; then
        return 1
    fi
    IFS='|' read -r state interval config_paused job consistency < <(read_launchd_status_snapshot)
    [[ "${state}" == "running" || "${state}" == "paused" ]] || return 1
    [[ "${consistency}" == "ok" ]] || return 1
    expected_paused="$(schedule_paused && printf '1' || printf '0')"
    [[ "${config_paused}" == "${expected_paused}" ]] || return 1
    if schedule_paused; then
        expected_state="paused"
    else
        expected_state="running"
    fi
    [[ "${state}" == "${expected_state}" ]] || return 1
    launchd_plist_matches_desired "${plist}" "${script}"
}

macos_schedule_refresh_current() {
    local script="$1"
    if launchd_supported && { [[ -f "$(launchd_plist_path)" ]] || legacy_launchd_plist_exists; }; then
        macos_launchd_refresh_current "${script}"
        return $?
    fi
    if command -v crontab >/dev/null 2>&1 && cron_managed_block_exists; then
        macos_cron_refresh_current "${script}"
        return $?
    fi
    return 1
}

show_cron_status() {
    local state interval config_paused job consistency
    IFS='|' read -r state interval config_paused job consistency < <(read_cron_status_snapshot)
    print_panel_section "PO0 Outbound IP Report 定时上报"
    print_panel_row "配置文件" "${CONFIG_FILE}"
    print_panel_row "保存状态" "$([[ -f "${CONFIG_FILE}" ]] && printf '已保存' || printf '未保存')"
    print_panel_row "配置暂停标记" "$(schedule_paused && printf '已暂停（手动立即上报仍可用）' || printf '未暂停')"
    print_panel_row "通知模式" "$(notify_status_label)"
    print_panel_row "跳过 Wi-Fi SSID" "$(skip_wifi_ssids_label)"
    print_panel_row "当前 Wi-Fi SSID" "$(current_wifi_ssid_label)"
    print_panel_row "实际状态" "$(cron_state_label "${state}")"
    if [[ -n "${interval}" ]]; then
        print_panel_row "计划间隔" "${interval}"
    elif [[ "${state}" == "running" || "${state}" == "paused" ]]; then
        print_panel_row "计划间隔" "已安装，未识别间隔"
    fi
    if [[ "${consistency}" == *"stale-scheduled-run"* ]]; then
        print_panel_row "状态提示" "旧版定时任务缺少自动运行标记，执行安装 / 更新定时上报可刷新"
    elif [[ "${consistency}" == *"drift"* ]]; then
        print_panel_row "状态提示" "定时任务暂停状态与配置不一致，执行安装 / 更新定时上报可修复"
    elif [[ "${consistency}" == *"legacy"* ]]; then
        print_panel_row "状态提示" "旧版定时上报仍在使用 po0-self-report，执行安装 / 更新定时上报可迁移"
    fi
    [[ -n "${job}" ]] && print_panel_row "当前命令" "${job}"
    show_recent_self_report_log
}

set_schedule_paused() {
    local value="$1" had_schedule=0 previous_paused="${SCHEDULE_PAUSED}"
    if cron_managed_block_exists; then
        had_schedule=1
    elif launchd_supported && { [[ -f "$(launchd_plist_path)" ]] || legacy_launchd_plist_exists; }; then
        had_schedule=1
    fi
    SCHEDULE_PAUSED="${value}"
    save_config_file || return 1
    if [[ "${had_schedule}" == "1" ]]; then
        if ! install_cron; then
            SCHEDULE_PAUSED="${previous_paused}"
            save_config_file >/dev/null 2>&1 || true
            self_report_incomplete "定时上报暂停状态未同步，已尝试恢复配置标记。"
            return 1
        fi
    fi
    if schedule_paused; then
        if [[ "${had_schedule}" == "1" ]]; then
            self_report_completed "定时上报已暂停；手动立即上报仍可用。"
        else
            self_report_completed "已记录暂停标记；当前未安装定时上报，安装后会按此状态写入。"
        fi
    else
        if [[ "${had_schedule}" == "1" ]]; then
            self_report_completed "定时上报已恢复。"
        else
            self_report_completed "已记录恢复标记；当前未安装定时上报，安装后会按此状态写入。"
        fi
    fi
}

toggle_schedule_interactive() {
    if schedule_paused; then
        set_schedule_paused "0"
    else
        set_schedule_paused "1"
    fi
}

set_notify_enabled() {
    local value="$1" had_schedule=0 previous_notify="${NOTIFY}"
    if cron_managed_block_exists; then
        had_schedule=1
    elif launchd_supported && { [[ -f "$(launchd_plist_path)" ]] || legacy_launchd_plist_exists; }; then
        had_schedule=1
    fi
    NOTIFY="${value}"
    save_config_file || return 1
    if [[ "${had_schedule}" == "1" ]]; then
        if ! install_cron; then
            NOTIFY="${previous_notify}"
            save_config_file >/dev/null 2>&1 || true
            self_report_incomplete "通知配置未同步到定时上报，已尝试恢复配置。"
            return 1
        fi
    fi
    if notify_enabled; then
        if [[ "${had_schedule}" == "1" ]]; then
            self_report_completed "已启用 macOS 通知，并刷新定时上报。"
        else
            self_report_completed "已启用 macOS 通知；当前未安装定时上报。"
        fi
    else
        if [[ "${had_schedule}" == "1" ]]; then
            self_report_completed "已切换为静默模式，并刷新定时上报。"
        else
            self_report_completed "已切换为静默模式；当前未安装定时上报。"
        fi
    fi
}

toggle_notify_interactive() {
    if notify_enabled; then
        set_notify_enabled "0"
    else
        set_notify_enabled "1"
    fi
}
