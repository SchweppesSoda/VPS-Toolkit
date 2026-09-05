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
    local line in_block=0 found=0 legacy_block=0 active_job="" paused_job="" metadata_interval="" job=""
    local state interval="" config_paused consistency="ok"
    config_paused="$(schedule_paused && printf '1' || printf '0')"
    if ! command -v crontab >/dev/null 2>&1; then
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
    fi
    printf '%s|%s|%s|%s|%s\n' "${state}" "${interval}" "${config_paused}" "${job}" "${consistency}"
}

cron_state_label() {
    case "$1" in
        running) printf '运行中' ;;
        paused) printf '已暂停' ;;
        uninstalled) printf '未安装' ;;
        unavailable) printf '不可用（缺少 crontab）' ;;
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
            [[ "${consistency}" == "drift" ]] && summary="${summary}（与配置暂停标记不一致）"
            [[ "${consistency}" == "legacy" ]] && summary="${summary}（旧命令，需刷新）"
            printf '%s' "${summary}"
            ;;
        *)
            cron_state_label "${state}"
            ;;
    esac
}

linux_expected_cron_job() {
    local script="$1" run_cmd wake_minutes official_minutes
    local worker_requested=0 official_requested=0
    wake_minutes="${CRON_MINUTES}"
    run_cmd="bash $(sh_quote "${script}") --config $(sh_quote "${CONFIG_FILE}")"
    if worker_channel_requested; then
        worker_requested=1
    fi
    if declare -F official_channel_enabled >/dev/null 2>&1 && official_channel_enabled; then
        official_requested=1
    fi
    if (( official_requested == 1 )); then
        official_minutes="$(official_interval_minutes)"
        if (( worker_requested == 1 && CRON_MINUTES < official_minutes )); then
            wake_minutes="${CRON_MINUTES}"
        else
            wake_minutes="${official_minutes}"
        fi
        run_cmd="${run_cmd} --scheduled-run"
    fi
    run_cmd="${run_cmd} >$(sh_quote "$(self_report_log_path)") 2>&1"
    build_cron_job "${wake_minutes}" "${run_cmd}"
}

linux_schedule_refresh_current() {
    local script="$1" state interval config_paused job consistency expected_job expected_paused expected_state
    IFS='|' read -r state interval config_paused job consistency < <(read_cron_status_snapshot)
    [[ "${state}" == "running" || "${state}" == "paused" ]] || return 1
    [[ "${consistency}" == "ok" ]] || return 1
    expected_job="$(linux_expected_cron_job "${script}")"
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

show_cron_status() {
    local state interval config_paused job consistency
    IFS='|' read -r state interval config_paused job consistency < <(read_cron_status_snapshot)
    print_panel_section "PO0 Outbound IP Report 定时上报"
    print_panel_row "配置文件" "${CONFIG_FILE}"
    print_panel_row "保存状态" "$([[ -f "${CONFIG_FILE}" ]] && printf '已保存' || printf '未保存')"
    print_panel_row "配置暂停标记" "$(schedule_paused && printf '已暂停（手动立即上报仍可用）' || printf '未暂停')"
    print_panel_row "实际状态" "$(cron_state_label "${state}")"
    if [[ -n "${interval}" ]]; then
        print_panel_row "计划间隔" "${interval}"
    elif [[ "${state}" == "running" || "${state}" == "paused" ]]; then
        print_panel_row "计划间隔" "已安装，未识别间隔"
    fi
    if [[ "${consistency}" == "drift" ]]; then
        print_panel_row "状态提示" "定时任务暂停状态与配置不一致，执行安装 / 更新定时上报可修复"
    elif [[ "${consistency}" == "legacy" ]]; then
        print_panel_row "状态提示" "旧版定时任务仍在使用 po0-self-report，执行安装 / 更新定时上报可迁移"
    fi
    print_panel_row "官方状态" "$(official_state_summary)"
    [[ -n "${job}" ]] && print_panel_row "当前命令" "${job}"
    show_recent_self_report_log
}

set_schedule_paused() {
    local value="$1" had_cron=0 previous_paused="${SCHEDULE_PAUSED}"
    if command -v crontab >/dev/null 2>&1 && cron_managed_block_exists; then
        had_cron=1
    fi
    SCHEDULE_PAUSED="${value}"
    save_config_file || return 1
    if [[ "${had_cron}" == "1" ]]; then
        if ! install_cron; then
            SCHEDULE_PAUSED="${previous_paused}"
            save_config_file >/dev/null 2>&1 || true
            self_report_incomplete "定时上报暂停状态未同步，已尝试恢复配置标记。"
            return 1
        fi
    fi
    if schedule_paused; then
        if [[ "${had_cron}" == "1" ]]; then
            self_report_completed "定时上报已暂停；手动立即上报仍可用。"
        else
            self_report_completed "已记录暂停标记；当前未安装定时上报，安装后会按此状态写入。"
        fi
    else
        if [[ "${had_cron}" == "1" ]]; then
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
