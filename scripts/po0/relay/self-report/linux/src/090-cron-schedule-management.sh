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
    local script job tmp run_cmd
    validate_cron_minutes || { self_report_incomplete "上报间隔配置无效，未安装 cron。"; return 1; }
    validate_worker_url || { self_report_incomplete "LAN Worker URL 未通过检查，未安装 cron。"; return 1; }
    save_config_file || { self_report_incomplete "配置保存失败，未安装 cron。"; return 1; }
    command -v crontab >/dev/null 2>&1 || {
        echo "未找到 crontab 命令。" >&2
        self_report_incomplete "缺少 crontab，未安装 cron。"
        return 1
    }
    script="$(install_self)" || { self_report_incomplete "脚本落盘失败，未安装 cron。"; return 1; }
    run_cmd="bash $(sh_quote "${script}") --config $(sh_quote "${CONFIG_FILE}") >$(sh_quote "$(self_report_log_path)") 2>&1"
    job="$(build_cron_job "${CRON_MINUTES}" "${run_cmd}")"
    if schedule_paused; then
        job="# ${job}"
    fi
    tmp="/tmp/po0-outbound-ip-report-cron.$$"
    {
        crontab -l 2>/dev/null | write_cron_without_managed_block
        cron_begin_marker
        printf '# paused=%s\n' "$(schedule_paused && printf '1' || printf '0')"
        printf '# interval_minutes=%s\n' "${CRON_MINUTES}"
        echo "${job}"
        cron_end_marker
    } > "${tmp}" || { self_report_incomplete "写入临时 cron 配置失败。"; return 1; }
    crontab "${tmp}" || {
        rm -f "${tmp}" 2>/dev/null || true
        self_report_incomplete "crontab 写入失败，未安装 cron。"
        return 1
    }
    rm -f "${tmp}" 2>/dev/null || true
    echo "已安装 Outbound IP Report cron：每 $(cron_minutes_to_seconds "${CRON_MINUTES}") 秒上报一次。"
    echo "脚本路径：${script}"
    echo "配置文件：${CONFIG_FILE}"
    if schedule_paused; then
        self_report_completed "定时上报已安装 / 更新，但当前保持暂停。"
    else
        self_report_completed "定时上报已安装 / 更新，每 $(cron_minutes_to_seconds "${CRON_MINUTES}") 秒执行一次。"
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
