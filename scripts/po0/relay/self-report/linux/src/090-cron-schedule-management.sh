cron_begin_marker() {
    printf '# OUTBOUND_IP_REPORT_BEGIN %s\n' "${CONFIG_FILE}"
}

cron_end_marker() {
    printf '# OUTBOUND_IP_REPORT_END %s\n' "${CONFIG_FILE}"
}

write_cron_without_managed_block() {
    awk '
        /# OUTBOUND_IP_REPORT_BEGIN/ || /# PO0_OUTBOUND_IP_REPORT_BEGIN/ || /# PO0_SELF_REPORT_BEGIN/ {skip=1; next}
        /# OUTBOUND_IP_REPORT_END/ || /# PO0_OUTBOUND_IP_REPORT_END/ || /# PO0_SELF_REPORT_END/ {skip=0; next}
        !skip {print}
    '
}

cron_managed_block_exists() {
    crontab -l 2>/dev/null | grep -Eq '^# (OUTBOUND_IP_REPORT|PO0_OUTBOUND_IP_REPORT|PO0_SELF_REPORT)_BEGIN'
}

build_cron_job() {
    local minutes="$1"
    local run_cmd="$2"
    local schedule hours
    if (( minutes < 60 )); then
        schedule="*/${minutes} * * * *"
        printf '%s %s\n' "${schedule}" "${run_cmd}"
    elif (( minutes == 60 )); then
        printf '0 * * * * %s\n' "${run_cmd}"
    elif (( minutes < 1440 && minutes % 60 == 0 )); then
        hours=$((minutes / 60))
        printf '0 */%s * * * %s\n' "${hours}" "${run_cmd}"
    elif (( minutes == 1440 )); then
        printf '0 0 * * * %s\n' "${run_cmd}"
    elif (( minutes % 60 == 0 )); then
        hours=$((minutes / 60))
        printf '0 * * * * now=$(date +\\%%s); if [ $((now / 3600 \\%% %s)) -eq 0 ]; then %s; fi\n' "${hours}" "${run_cmd}"
    else
        printf '* * * * now=$(date +\\%%s); if [ $((now / 60 \\%% %s)) -eq 0 ]; then %s; fi\n' "${minutes}" "${run_cmd}"
    fi
}

install_cron() {
    local script job tmp run_cmd wake_minutes official_minutes
    local worker_requested=0 official_requested=0
    wake_minutes="${CRON_MINUTES}"
    official_minutes=""
    validate_cron_minutes || { self_report_incomplete "上报间隔配置无效，未安装 cron。"; return 1; }
    if worker_channel_requested; then
        worker_requested=1
        validate_worker_url || { self_report_incomplete "LAN Worker URL 未通过检查，未安装 cron。"; return 1; }
    fi
    if declare -F official_channel_enabled >/dev/null 2>&1 && official_channel_enabled; then
        official_requested=1
        official_validate_tokens || { self_report_incomplete "官方防火墙 token 配置未通过检查，未安装 cron。"; return 1; }
    fi
    (( worker_requested == 1 || official_requested == 1 )) || {
        self_report_incomplete "未启用任何上报通道，未安装 cron。"
        return 1
    }
    save_config_file || { self_report_incomplete "配置保存失败，未安装 cron。"; return 1; }
    command -v crontab >/dev/null 2>&1 || {
        echo "未找到 crontab 命令。" >&2
        self_report_incomplete "缺少 crontab，未安装 cron。"
        return 1
    }
    script="$(install_self)" || { self_report_incomplete "脚本落盘失败，未安装 cron。"; return 1; }
    if (( official_requested == 1 )); then
        official_minutes="$(official_interval_minutes)"
        if (( worker_requested == 1 && CRON_MINUTES < official_minutes )); then
            wake_minutes="${CRON_MINUTES}"
        else
            wake_minutes="${official_minutes}"
        fi
    fi
    run_cmd="bash $(sh_quote "${script}") --config $(sh_quote "${CONFIG_FILE}")"
    if (( official_requested == 1 )); then
        # The single scheduled entry runs the wrapper in normal mode.  The
        # wrapper executes official first and lets each lane apply its own
        # due gate; putting options after redirection would make them shell
        # arguments, so append the flag before the log redirection.
        run_cmd="${run_cmd} --scheduled-run"
    fi
    run_cmd="${run_cmd} >$(sh_quote "$(self_report_log_path)") 2>&1"
    job="$(build_cron_job "${wake_minutes}" "${run_cmd}")"
    if schedule_paused; then
        job="# ${job}"
    fi
    tmp="/tmp/po0-outbound-ip-report-cron.$$"
    {
        crontab -l 2>/dev/null | write_cron_without_managed_block
        cron_begin_marker
        printf '# paused=%s\n' "$(schedule_paused && printf '1' || printf '0')"
        printf '# interval_minutes=%s\n' "${wake_minutes}"
        (( official_requested == 1 )) && printf '# official_interval_minutes=%s\n' "${official_minutes}"
        (( worker_requested == 1 && official_requested == 1 )) && printf '# worker_interval_minutes=%s\n' "${CRON_MINUTES}"
        echo "${job}"
        cron_end_marker
    } > "${tmp}" || { self_report_incomplete "写入临时 cron 配置失败。"; return 1; }
    crontab "${tmp}" || {
        rm -f "${tmp}" 2>/dev/null || true
        self_report_incomplete "crontab 写入失败，未安装 cron。"
        return 1
    }
    rm -f "${tmp}" 2>/dev/null || true
    if (( worker_requested == 1 && official_requested == 1 )); then
        echo "已安装 Outbound IP Report cron：每 $(cron_minutes_to_seconds "${wake_minutes}") 秒唤醒；LAN Worker 到期后每 $(cron_minutes_to_seconds "${CRON_MINUTES}") 秒，官方防火墙每 $(official_interval_seconds) 秒。"
    elif (( official_requested == 1 )); then
        echo "已安装 Outbound IP Report cron：每 $(official_interval_seconds) 秒唤醒官方防火墙。"
    else
        echo "已安装 Outbound IP Report cron：每 $(cron_minutes_to_seconds "${CRON_MINUTES}") 秒上报一次。"
    fi
    echo "脚本路径：${script}"
    echo "配置文件：${CONFIG_FILE}"
    if schedule_paused; then
        self_report_completed "定时上报已安装 / 更新，但当前保持暂停。"
    else
        if (( worker_requested == 1 && official_requested == 1 )); then
            self_report_completed "定时上报已安装 / 更新：单一唤醒入口按各自 due 状态执行，官方通道先于 LAN Worker。"
        elif (( official_requested == 1 )); then
            self_report_completed "定时上报已安装 / 更新：官方防火墙按 $(official_interval_seconds) 秒独立间隔执行。"
        else
            self_report_completed "定时上报已安装 / 更新，每 $(cron_minutes_to_seconds "${CRON_MINUTES}") 秒执行一次。"
        fi
    fi
}

remove_cron() {
    local tmp
    command -v crontab >/dev/null 2>&1 || {
        echo "未找到 crontab 命令。" >&2
        self_report_incomplete "缺少 crontab，未删除 cron。"
        return 1
    }
    if command -v mktemp >/dev/null 2>&1; then
        tmp="$(mktemp "${TMPDIR:-/tmp}/po0-outbound-ip-report-cron.XXXXXX")" || return 1
    else
        tmp="${TMPDIR:-/tmp}/po0-outbound-ip-report-cron.$$"
    fi
    crontab -l 2>/dev/null | write_cron_without_managed_block > "${tmp}" || true
    crontab "${tmp}" || {
        rm -f "${tmp}" 2>/dev/null || true
        self_report_incomplete "crontab 写入失败，未删除 cron。"
        return 1
    }
    rm -f "${tmp}" 2>/dev/null || true
    echo "已删除本脚本管理的 PO0 Outbound IP Report cron。"
    self_report_completed "已删除本脚本管理的定时上报。"
}
