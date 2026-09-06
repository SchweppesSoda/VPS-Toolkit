channel_schedule_exists() {
    local channel="$1"
    cron_managed_block_exists "$channel" && return 0
    if declare -F launchd_supported >/dev/null && launchd_supported; then [[ -f "$(launchd_plist_path "$channel")" ]] && return 0; fi
    return 1
}

legacy_schedule_exists() {
    legacy_cron_block_exists && return 0
    if declare -F launchd_supported >/dev/null && launchd_supported; then legacy_launchd_plist_exists && return 0; fi
    return 1
}

read_cron_status_snapshot() {
    local channel="${1:-worker}" block line job='' state=uninstalled minutes='' paused=0 consistency=ok
    { schedule_channel_paused "$channel" || ! schedule_timer_enabled "$channel"; } && paused=1
    block="$(cron_channel_block "$channel")"
    if [[ -z "$block" ]]; then
        if declare -F launchd_supported >/dev/null && launchd_supported && [[ -f "$(launchd_plist_path "$channel")" ]]; then
            read_launchd_status_snapshot "$channel"; return
        fi
        if legacy_schedule_exists; then printf 'legacy||%s||legacy\n' "$paused"; else printf 'uninstalled||%s||ok\n' "$paused"; fi
        return
    fi
    state=invalid
    while IFS= read -r line; do
        case "$line" in
            '# interval_minutes='*) minutes="${line#*=}" ;;
            '# '*"--${channel}-only"*) job="${line#\# }"; state=paused ;;
            *"--${channel}-only"*) job="$line"; state=running ;;
        esac
    done <<< "$block"
    if [[ "$state" == running && "$paused" == 1 || "$state" == paused && "$paused" == 0 ]]; then consistency=drift; fi
    printf '%s|%s|%s|%s|%s\n' "$state" "$(cron_interval_label_from_minutes "$minutes" 2>/dev/null || true)" "$paused" "$job" "$consistency"
}

cron_state_label() {
    case "$1" in running) printf '运行中' ;; paused) printf '已暂停' ;; uninstalled) printf '未安装' ;; legacy) printf '旧共享任务，待迁移' ;; *) printf '异常：任务配置不完整' ;; esac
}

cron_status_summary() {
    local channel="${1:-all}" state interval paused job consistency
    if [[ "$channel" == all ]]; then
        printf '自建：%s；官方：%s' "$(cron_status_summary worker)" "$(cron_status_summary official)"; return
    fi
    IFS='|' read -r state interval paused job consistency < <(read_cron_status_snapshot "$channel")
    cron_state_label "$state"
    [[ -z "$interval" ]] || printf '，%s' "$interval"
    [[ "$consistency" != drift ]] || printf '（与保存设置不一致，需更新任务）'
    return 0
}

network_event_label() {
    if ! schedule_network_enabled "$1"; then printf '已关闭'; return; fi
    case "$(network_event_backend)" in
        none) printf '当前环境不可用，跳过检测' ;;
        *) if ! channel_schedule_exists "$1"; then printf '可用，尚未安装'; elif schedule_channel_paused "$1"; then printf '已暂停'; else printf '已启用'; fi ;;
    esac
}

show_cron_status() {
    local target="${1:-${SCHEDULE_CHANNEL:-all}}" channel state interval paused job consistency log
    for channel in worker official; do
        [[ "$target" == all || "$target" == "$channel" ]] || continue
        print_panel_section "$(schedule_channel_label "$channel") · 定时任务"
        print_panel_row '网络变化检测' "$(network_event_label "$channel")"
        print_panel_row '实际状态' "$(cron_status_summary "$channel")"
        print_panel_row '计划间隔' "$(($(schedule_channel_minutes "$channel") * 60)) 秒"
        log="$(schedule_channel_log_path "$channel")"
        print_panel_row '运行日志' "$log"
        if [[ -f "$log" ]]; then tail -n 8 "$log"; fi
    done
}

refresh_channel_schedules() {
    local target="${1:-all}"
    if declare -F launchd_supported >/dev/null && launchd_supported; then
        apply_launchd_schedules refresh "$target"
    else
        apply_channel_cron refresh "$target"
    fi
}

update_channel_schedule_if_installed() {
    local channel="${1:-all}"
    if [[ "$channel" == all ]] || channel_schedule_exists "$channel" || legacy_schedule_exists; then
        refresh_channel_schedules "$channel" || return 1
    fi
    return 0
}

legacy_schedule_paused() {
    local paused path
    if schedule_paused; then return 0; fi
    paused="$(crontab -l 2>/dev/null | awk -v cfg="$CONFIG_FILE" '
        $0 == "# OUTBOUND_IP_REPORT_BEGIN " cfg || $0 == "# PO0_OUTBOUND_IP_REPORT_BEGIN " cfg || $0 == "# PO0_SELF_REPORT_BEGIN " cfg {inside=1}
        inside && $0 == "# paused=1" {found=1}
        inside && /_END / {inside=0}
        END {print found+0}')"
    [[ "$paused" == 1 ]] && return 0
    if declare -F legacy_launchd_plist_exists >/dev/null && legacy_launchd_plist_exists; then
        path="$(legacy_launchd_plist_path)"
        [[ "$(launchd_disabled_from_plist "$path")" == 1 ]] && return 0
    fi
    return 1
}

set_schedule_paused() {
    local value="$1" channel="${2:-${SCHEDULE_CHANNEL:-all}}" old_paused="$SCHEDULE_PAUSED" old_worker="$WORKER_AUTO_ENABLED" old_official="$OFFICIAL_AUTO_ENABLED"
    if legacy_schedule_exists; then refresh_channel_schedules all || return 1; fi
    if [[ "$channel" == all ]]; then
        SCHEDULE_PAUSED="$value"
    else
        if schedule_paused; then WORKER_AUTO_ENABLED=0; OFFICIAL_AUTO_ENABLED=0; SCHEDULE_PAUSED=0; fi
        if [[ "$channel" == worker ]]; then WORKER_AUTO_ENABLED=$((1 - value)); else OFFICIAL_AUTO_ENABLED=$((1 - value)); fi
    fi
    if ! save_config_file || ! refresh_channel_schedules "$channel"; then
        SCHEDULE_PAUSED="$old_paused"; WORKER_AUTO_ENABLED="$old_worker"; OFFICIAL_AUTO_ENABLED="$old_official"
        save_config_file >/dev/null 2>&1 || true
        return 1
    fi
    printf '已%s%s自动上报；手动上报仍可使用。\n' "$([[ "$value" == 1 ]] && printf '暂停' || printf '恢复')" "$([[ "$channel" == all ]] && printf '全部' || schedule_channel_label "$channel")"
}

toggle_schedule_interactive() {
    local channel="${1:-all}" value=1
    if [[ "$channel" == all ]]; then schedule_paused && value=0; else schedule_channel_paused "$channel" && value=0; fi
    set_schedule_paused "$value" "$channel"
}

channel_schedules_current() {
    local script="$1" channel any=0 state interval paused job consistency expected
    legacy_schedule_exists && return 1
    for channel in worker official; do
        channel_schedule_exists "$channel" || continue
        any=1
        schedule_channel_configured "$channel" || return 1
        IFS='|' read -r state interval paused job consistency < <(read_cron_status_snapshot "$channel")
        [[ "$consistency" == ok && ( "$state" == running || "$state" == paused ) ]] || return 1
        if [[ "$job" == launchd:* ]]; then
            launchd_plist_matches_desired "$(launchd_plist_path "$channel")" "$script" "$channel" || return 1
        else
            expected="$(channel_expected_cron_job "$script" "$channel")"
            [[ "$job" == "$expected" ]] || return 1
        fi
    done
    [[ "$any" == 1 ]]
}

linux_expected_cron_job() { channel_expected_cron_job "$1" "${2:-worker}"; }
linux_schedule_refresh_current() { channel_schedules_current "$1"; }
macos_expected_cron_job() { channel_expected_cron_job "$1" "${2:-worker}"; }
macos_cron_refresh_current() { channel_schedules_current "$1"; }
macos_launchd_refresh_current() { channel_schedules_current "$1"; }
macos_schedule_refresh_current() { channel_schedules_current "$1"; }

set_notify_enabled() {
    local previous="$NOTIFY"
    NOTIFY="$1"
    if ! save_config_file || ! refresh_channel_schedules all; then NOTIFY="$previous"; save_config_file >/dev/null 2>&1 || true; return 1; fi
    self_report_completed '通知设置已保存，已安装的两项任务分别更新。'
}

toggle_notify_interactive() {
    if notify_enabled; then set_notify_enabled 0; else set_notify_enabled 1; fi
}
