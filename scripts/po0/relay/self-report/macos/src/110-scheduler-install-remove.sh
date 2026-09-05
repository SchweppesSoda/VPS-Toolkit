schedule_backend() {
    if launchd_supported; then
        printf 'launchd\n'
    elif command -v crontab >/dev/null 2>&1; then
        printf 'cron\n'
    else
        printf 'none\n'
    fi
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

install_launchd() {
    local script plist dir interval_seconds
    po0_reporter_validate_config || { self_report_incomplete "上报通道或间隔配置无效，未安装 launchd 计划。"; return 1; }
    save_config_file || { self_report_incomplete "配置保存失败，未安装 launchd 计划。"; return 1; }
    launchd_supported || {
        echo "当前系统不支持 launchd 安装。" >&2
        self_report_incomplete "缺少 crontab，且当前环境不是可用的 macOS launchd。"
        return 1
    }
    script="$(install_self)" || { self_report_incomplete "脚本落盘失败，未安装 launchd 计划。"; return 1; }
    plist="$(launchd_plist_path)"
    dir="$(path_dirname "${plist}")"
    mkdir -p "${dir}" || { self_report_incomplete "macOS 定时任务配置目录创建失败：${dir}"; return 1; }
    remove_legacy_launchd_if_exists || {
        self_report_incomplete "旧 launchd 计划删除失败，未安装新计划。"
        return 1
    }
    interval_seconds="$(po0_reporter_wakeup_seconds)"
    write_launchd_plist "${plist}" "${script}" "${interval_seconds}" || {
        self_report_incomplete "macOS 定时任务配置文件写入失败：${plist}"
        return 1
    }
    chmod 644 "${plist}" 2>/dev/null || true
    if [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]]; then
        chown root:wheel "${plist}" 2>/dev/null || true
    fi
    if command -v crontab >/dev/null 2>&1 && cron_managed_block_exists; then
        if remove_cron_backend >/dev/null 2>&1; then
            echo "已清理旧 cron 定时上报，避免与 launchd 双重上报。"
        else
            rm -f "${plist}" 2>/dev/null || true
            self_report_incomplete "旧 cron 定时上报清理失败，未加载新 launchd，避免双重上报；请手动删除旧定时任务配置后重试。"
            return 1
        fi
    fi
    launchd_unload "${plist}"
    if ! schedule_paused; then
        launchd_load "${plist}" || {
            self_report_incomplete "launchd 加载失败，已写入 plist：${plist}"
            return 1
        }
    fi
    echo "已安装 Outbound IP Report launchd 计划：每 ${interval_seconds} 秒唤醒检查，各通道按独立 due 上报。"
    echo "macOS 定时任务配置文件：${plist}"
    echo "脚本路径：${script}"
    echo "配置文件：${CONFIG_FILE}"
    echo "通知模式：$(notify_status_label)"
    if schedule_paused; then
        self_report_completed "定时上报已安装 / 更新，但当前保持暂停。"
    else
        self_report_completed "定时上报已安装 / 更新，每 ${interval_seconds} 秒唤醒检查。"
    fi
}

install_cron_backend() {
    local script job tmp run_cmd
    po0_reporter_validate_config || { self_report_incomplete "上报通道或间隔配置无效，未安装 cron。"; return 1; }
    save_config_file || { self_report_incomplete "配置保存失败，未安装 cron。"; return 1; }
    command -v crontab >/dev/null 2>&1 || {
        echo "未找到 crontab 命令。" >&2
        self_report_incomplete "缺少 crontab，未安装 cron。"
        return 1
    }
    script="$(install_self)" || { self_report_incomplete "脚本落盘失败，未安装 cron。"; return 1; }
    run_cmd="bash $(sh_quote "${script}") --config $(sh_quote "${CONFIG_FILE}") --scheduled-run"
    if notify_enabled; then
        run_cmd="${run_cmd} --notify"
    fi
    run_cmd="${run_cmd} >$(sh_quote "$(self_report_log_path)") 2>&1"
    job="$(build_cron_job "$(po0_reporter_wakeup_minutes)" "${run_cmd}")"
    if schedule_paused; then
        job="# ${job}"
    fi
    tmp="/tmp/po0-outbound-ip-report-cron.$$"
    {
        crontab -l 2>/dev/null | write_cron_without_managed_block
        cron_begin_marker
        printf '# paused=%s\n' "$(schedule_paused && printf '1' || printf '0')"
        printf '# interval_minutes=%s\n' "$(po0_reporter_wakeup_minutes)"
        echo "${job}"
        cron_end_marker
    } > "${tmp}" || { self_report_incomplete "写入临时 cron 配置失败。"; return 1; }
    crontab "${tmp}" || {
        rm -f "${tmp}" 2>/dev/null || true
        self_report_incomplete "crontab 写入失败，未安装 cron。"
        return 1
    }
    rm -f "${tmp}" 2>/dev/null || true
    echo "已安装 Outbound IP Report cron：每 $(po0_reporter_wakeup_seconds) 秒唤醒检查，各通道按独立 due 上报。"
    echo "脚本路径：${script}"
    echo "配置文件：${CONFIG_FILE}"
    echo "通知模式：$(notify_status_label)"
    if schedule_paused; then
        self_report_completed "定时上报已安装 / 更新，但当前保持暂停。"
    else
        self_report_completed "定时上报已安装 / 更新，每 $(po0_reporter_wakeup_seconds) 秒唤醒检查。"
    fi
}

install_cron() {
    case "$(schedule_backend)" in
        cron) install_cron_backend ;;
        launchd) install_launchd ;;
        *)
            echo "未找到 crontab 命令。" >&2
            self_report_incomplete "缺少 crontab，且当前环境不是可用的 macOS launchd。"
            return 1
            ;;
    esac
}

remove_launchd() {
    local plist
    launchd_supported || return 1
    plist="$(launchd_plist_path)"
    if [[ -f "${plist}" ]]; then
        launchd_unload "${plist}"
        rm -f "${plist}" || {
        self_report_incomplete "删除 macOS 定时任务配置文件失败：${plist}"
            return 1
        }
        echo "已删除本脚本管理的 self-report launchd 计划：${plist}"
    else
        echo "未发现本脚本管理的 self-report launchd 计划。"
    fi
}

remove_cron_backend() {
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
}

remove_cron() {
    local did=0 errors=0
    if command -v crontab >/dev/null 2>&1; then
        remove_cron_backend || errors=1
        did=1
    fi
    if launchd_supported && [[ -f "$(launchd_plist_path)" ]]; then
        remove_launchd || errors=1
        did=1
    fi
    if launchd_supported && legacy_launchd_plist_exists; then
        remove_legacy_launchd_if_exists || errors=1
        did=1
    fi
    if [[ "${did}" != "1" ]]; then
        echo "未发现可删除的 self-report 定时上报。"
    fi
    if [[ "${errors}" == "1" ]]; then
        self_report_incomplete "定时上报删除未完全成功。"
        return 1
    fi
    self_report_completed "已删除本脚本管理的定时上报。"
}
