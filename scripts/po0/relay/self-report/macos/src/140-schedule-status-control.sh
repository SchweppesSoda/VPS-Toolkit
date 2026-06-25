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

read_cron_status_snapshot() {
    local line in_block=0 found=0 active_job="" paused_job="" metadata_interval="" job=""
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
            "# PO0_SELF_REPORT_BEGIN"*) in_block=1; found=1; continue ;;
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
        if launchd_supported && [[ -f "$(launchd_plist_path)" ]]; then
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
    printf '%s|%s|%s|%s|%s\n' "${state}" "${interval}" "${config_paused}" "${job}" "${consistency}"
}

cron_state_label() {
    case "$1" in
        running) printf '运行中' ;;
        paused) printf '已暂停' ;;
        uninstalled) printf '未安装' ;;
        unavailable) printf '不可用（缺少 crontab，且当前环境不能使用 macOS launchd）' ;;
        invalid) printf '异常：cron block 无任务' ;;
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
            [[ "${consistency}" == "drift" ]] && summary="${summary}（与配置暂停标记不一致）"
            printf '%s' "${summary}"
            ;;
        *)
            cron_state_label "${state}"
            ;;
    esac
}

show_cron_status() {
    local state interval config_paused job consistency
    IFS='|' read -r state interval config_paused job consistency < <(read_cron_status_snapshot)
    print_panel_section "Self-report 定时上报"
    print_panel_row "配置文件" "${CONFIG_FILE}"
    print_panel_row "保存状态" "$([[ -f "${CONFIG_FILE}" ]] && printf '已保存' || printf '未保存')"
    print_panel_row "配置暂停标记" "$(schedule_paused && printf '已暂停（手动立即上报仍可用）' || printf '未暂停')"
    print_panel_row "通知模式" "$(notify_status_label)"
    print_panel_row "实际状态" "$(cron_state_label "${state}")"
    if [[ -n "${interval}" ]]; then
        print_panel_row "计划间隔" "${interval}"
    elif [[ "${state}" == "running" || "${state}" == "paused" ]]; then
        print_panel_row "计划间隔" "已安装，未识别间隔"
    fi
    if [[ "${consistency}" == "drift" ]]; then
        print_panel_row "一致性" "不一致，执行安装 / 更新定时上报可刷新"
    elif [[ "${state}" == "running" || "${state}" == "paused" ]]; then
        print_panel_row "一致性" "一致"
    fi
    [[ -n "${job}" ]] && print_panel_row "当前命令" "${job}"
    show_recent_self_report_log
}

set_schedule_paused() {
    local value="$1" had_schedule=0 previous_paused="${SCHEDULE_PAUSED}"
    if cron_managed_block_exists; then
        had_schedule=1
    elif launchd_supported && [[ -f "$(launchd_plist_path)" ]]; then
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
    elif launchd_supported && [[ -f "$(launchd_plist_path)" ]]; then
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
