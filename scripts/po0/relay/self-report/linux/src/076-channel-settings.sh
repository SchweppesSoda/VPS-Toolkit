# Local channel controls. Missing values preserve existing automatic reporting.
WORKER_TIMER_ENABLED="${WORKER_TIMER_ENABLED:-1}"
OFFICIAL_TIMER_ENABLED="${OFFICIAL_TIMER_ENABLED:-1}"
WORKER_NETWORK_ENABLED="${WORKER_NETWORK_ENABLED:-1}"
OFFICIAL_NETWORK_ENABLED="${OFFICIAL_NETWORK_ENABLED:-1}"
OFFICIAL_INTERVAL_SECONDS="${OFFICIAL_INTERVAL_SECONDS:-600}"
WORKER_AUTO_ENABLED="${WORKER_AUTO_ENABLED:-1}"
OFFICIAL_AUTO_ENABLED="${OFFICIAL_AUTO_ENABLED:-1}"
WORKER_NAME="${WORKER_NAME:-}"
PO0_FIREWALL_NAMES="${PO0_FIREWALL_NAMES:-}"

channel_auto_enabled() {
    local value
    case "$1" in
        worker) value="${WORKER_AUTO_ENABLED:-1}" ;;
        official) value="${OFFICIAL_AUTO_ENABLED:-1}" ;;
        *) return 1 ;;
    esac
    case "$value" in 0|false|no|off) return 1 ;; *) return 0 ;; esac
}

channel_auto_label() {
    if channel_auto_enabled "$1"; then printf '已启用'; else printf '已停用（保留配置）'; fi
}

official_account_name() {
    local ordinal="$1" names="${PO0_FIREWALL_NAMES:-}" current=1 name
    names="${names//$'\r'/}"
    names="${names//$'\n'/;}"
    names="${names//；/;}"
    names="${names};"
    while [[ "$names" == *';'* ]]; do
        name="${names%%;*}"
        names="${names#*;}"
        if [[ "$current" == "$ordinal" ]]; then
            name="$(trim "$name")"
            [[ -z "$name" ]] || { printf '%s' "$name"; return 0; }
            break
        fi
        current=$((current + 1))
    done
    printf '官方账号 %s' "$ordinal"
}

print_official_target_names() {
    local count=0 index=1
    if declare -F official_tokens_count >/dev/null; then count="$(official_tokens_count)"; else count="$(po0_firewall_token_count)"; fi
    while (( index <= count )); do
        print_panel_row "账号 $index" "$(official_account_name "$index")"
        index=$((index + 1))
    done
}

set_channel_names_interactive() {
    local channel="$1" name raw count=0 index=1 names=''
        if declare -F official_tokens_count >/dev/null; then count="$(official_tokens_count)"; else count="$(po0_firewall_token_count)"; fi
        [[ "$count" -gt 0 ]] || { printf '请先在「官方账号与槽位」中保存 Token，再设置账号名称。\n'; return 1; }
        printf '按当前 Token 的顺序逐个设置名称；名称只在本机显示，输入 - 恢复默认名称。\n'
        while (( index <= count )); do
            name="$(prompt_default "账号 ${index} 名称" "$(official_account_name "$index")")" || return 1
            case "$name" in *';'*|*'；'*|*$'\n'*|*$'\r'*) printf '单个名称不能包含分号或换行。\n' >&2; return 1 ;; esac
            [[ "$index" == 1 ]] || names="$names;"
            [[ "$name" != - ]] || name=""
            names="$names$name"
            index=$((index + 1))
        done
        PO0_FIREWALL_NAMES="$names"
    save_config_file
}

run_channel_interactive() {
    local channel="$1" rc old_mode="${REPORT_MODE:-all}" old_official="${OFFICIAL_ONLY:-0}" old_worker="${WORKER_ONLY:-0}" old_scheduled="${SCHEDULED_RUN:-0}"
    REPORT_MODE="$channel"
    OFFICIAL_ONLY=0
    WORKER_ONLY=0
    SCHEDULED_RUN=0
    [[ "$channel" != official ]] || OFFICIAL_ONLY=1
    [[ "$channel" != worker ]] || WORKER_ONLY=1
    if [[ "$channel" == official && -z "${PO0_FIREWALL_TOKENS:-}" ]] || [[ "$channel" == worker && -z "${WORKER_URL:-}" ]]; then
        printf "尚未保存官方账号，请先在「官方账号与槽位」中保存 Token。\n"
        rc=1
    elif ! config_complete; then
        printf "本机配置不完整，请先检查「官方账号与槽位」。\n"
        rc=1
    else
        local result_log
        result_log="$(schedule_channel_log_path "$channel")"
        if [[ -L "$result_log" ]]; then
            printf '上报日志路径无效。\n' >&2
            rc=1
        else
            (umask 077; exec 3>&1 4>>"$result_log"; (setup_colors; PO0_DISPLAY_FD=3 PO0_DISPLAY_LOG_FD=4 run_once_interactive) 2>&1 | tee -a "$result_log"; exit "${PIPESTATUS[0]}")
            rc=$?
        fi
    fi
    REPORT_MODE="$old_mode"
    OFFICIAL_ONLY="$old_official"
    WORKER_ONLY="$old_worker"
    SCHEDULED_RUN="$old_scheduled"
    return "$rc"
}

show_recent_report_results() {
    po0_display_cached
    show_recent_self_report_log "$(schedule_channel_log_path official)"
}

show_channel_status() {
    if declare -F official_status_interactive >/dev/null; then official_status_interactive; else official_status_once; fi
}


channel_interval_label() {
    printf '%s 秒' "$(($(schedule_channel_minutes "$1") * 60))"
    schedule_timer_enabled "$1" || printf '（暂不使用）'
}

channel_periodic_label() {
    local interval
    interval="$(po0_duration "$(( $(schedule_channel_minutes "$1") * 60 ))")"
    if schedule_timer_enabled "$1"; then printf '每 %s' "$interval"; else printf '已关闭（保留间隔 %s）' "$interval"; fi
}

configure_channel_periodic_interactive() {
    local enabled=0 default=n seconds
    schedule_timer_enabled official && default=y
    if prompt_yes_no '启用定期上报（关闭保留网络变化触发和原间隔）' "$default"; then enabled=1; fi
    seconds="$(prompt_default '上报间隔（秒，60..86400，60 的倍数）' "${OFFICIAL_INTERVAL_SECONDS:-600}")" || return 1
    [[ "$seconds" =~ ^[0-9]+$ ]] && (( seconds >= 60 && seconds <= 86400 && seconds % 60 == 0 )) || { printf '无效上报间隔。\n'; return 1; }
    OFFICIAL_TIMER_ENABLED="$enabled"; OFFICIAL_INTERVAL_SECONDS="$seconds"
    save_config_file && update_channel_schedule_if_installed official
}

show_channel_config() {
    print_panel_section '官方账号'
    print_official_target_names
    print_panel_row 'Token / 槽位' "${PO0_FIREWALL_TOKENS:-未配置}"
    print_panel_section '自动上报'
    print_panel_status_row '自动上报' "$(channel_auto_label official)"
    print_panel_status_row '定期上报' "$(channel_periodic_label official)"
}

# Account settings only; reporting and query actions live in the main menu.
official_account_menu() {
    local choice
    while true; do
        menu_clear_screen
        print_title 'PO0 防火墙 · 官方账号与槽位'
        print_panel_status_row '配置状态' "$(schedule_channel_configured official && printf '已配置' || printf '未配置')"
        print_official_target_names
        printf '\n'
        print_menu_item 1 '编辑 Token 与槽位'
        print_menu_item 2 '设置账号名称'
        print_menu_item 3 '清除官方账号'
        print_menu_item 0 '返回主菜单'
        choice="$(read_prompt '请选择 [0-3]: ')" || return 0
        case "$(trim "$choice")" in
            1) configure_official_interactive && update_channel_schedule_if_installed official ;;
            2) set_channel_names_interactive official ;;
            3) clear_official_tokens_interactive && update_channel_schedule_if_installed official ;;
            0) return 0 ;;
            *) printf '无效选择：请输入 0-3。\n' ;;
        esac
        pause_before_return
    done
}

# One place for the switch, interval and scheduler task of automatic reports.
automatic_reporting_menu() {
    local choice
    while true; do
        menu_clear_screen
        print_title 'PO0 防火墙 · 自动上报与计划任务'
        print_panel_status_row '自动上报' "$(channel_auto_label official)"
        print_panel_status_row '定期上报' "$(channel_periodic_label official)"
        print_panel_status_row '计划任务' "$(cron_status_summary official)"
        printf '\n'
        print_menu_item 1 '安装 / 更新计划任务'
        print_menu_item 2 '暂停 / 恢复自动上报'
        print_menu_item 3 '定期上报开关与间隔'
        print_menu_item 4 '查看计划任务状态与日志'
        print_menu_item 5 '删除计划任务'
        print_menu_item 0 '返回主菜单'
        choice="$(read_prompt '请选择 [0-5]: ')" || return 0
        case "$(trim "$choice")" in
            1) install_cron_interactive official ;;
            2) toggle_schedule_interactive official ;;
            3) configure_channel_periodic_interactive official ;;
            4) show_cron_status official ;;
            5) if prompt_yes_no '删除计划任务（账号与设置保留）' n; then remove_cron official; fi ;;
            0) return 0 ;;
            *) printf '无效选择：请输入 0-5。\n' ;;
        esac
        pause_before_return
    done
}

client_maintenance_menu() {
    local choice rc max_choice=3
    declare -F show_wifi_ssid_permission_help_interactive >/dev/null && max_choice=5
    while true; do
        menu_clear_screen
        print_title '维护与诊断'
        print_panel_row '客户端版本' "$SCRIPT_VERSION"
        print_panel_row '当前脚本' "$(current_script_path)"
        print_panel_row '安装位置' "$(default_install_path)"
        print_panel_row '配置文件' "$CONFIG_FILE"
        print_panel_row '日志位置' "$(self_report_log_path)"
        print_panel_section '客户端'
        print_menu_item 1 '更新客户端脚本'
        print_menu_item 2 '迁移旧版自建配置与任务'
        print_menu_item 3 '卸载客户端'
        if declare -F show_wifi_ssid_permission_help_interactive >/dev/null; then
            print_panel_section 'Wi-Fi 定位权限'
            print_menu_item 4 'Wi-Fi SSID 权限诊断'
            print_menu_item 5 '删除定位权限 Helper'
        fi
        printf '\n'
        print_menu_item 0 '返回主菜单'
        choice="$(read_prompt "请选择 [0-$max_choice]: ")" || return 0
        case "$(trim "$choice")" in
            1) upgrade_self_from_download --reopen-menu ;;
            2) migrate_retired_state ;;
            3) uninstall_self_report_interactive; rc=$?; [[ "$rc" != 0 ]] || { CLIENT_MENU_UNINSTALLED=1; return 0; } ;;
            4) if declare -F show_wifi_ssid_permission_help_interactive >/dev/null; then show_wifi_ssid_permission_help_interactive; else printf '无效选择：请输入 0-%s。\n' "$max_choice"; fi ;;
            5) if declare -F remove_macos_location_permission_helper_app_interactive >/dev/null; then remove_macos_location_permission_helper_app_interactive; else printf '无效选择：请输入 0-%s。\n' "$max_choice"; fi ;;
            0) return 0 ;;
            *) printf "无效选择：请输入 0-%s。\n" "$max_choice" ;;
        esac
        pause_before_return
    done
}

show_client_overview() {
    print_title 'PO0 防火墙' "$SCRIPT_VERSION"
    print_panel_status_row '自动上报' "$(channel_auto_label official)"
    print_panel_status_row '定期上报' "$(channel_periodic_label official)"
    print_panel_status_row '计划任务' "$(cron_status_summary official)"
    print_official_target_names
    po0_display_cached summary
}

# Preserve labels by account identity when tokens are reordered or slots change.
sync_official_account_names() {
    local old_tokens="$1" new_tokens old_item new_item old_index label result='' separator=''
    if declare -F official_normalize_tokens >/dev/null; then
        old_tokens="$(official_normalize_tokens "$old_tokens")"
        new_tokens="$(official_normalize_tokens "${PO0_FIREWALL_TOKENS:-}")"
    else
        old_tokens="$(po0_firewall_normalize_tokens "$old_tokens")"
        new_tokens="$(po0_firewall_normalize_tokens "${PO0_FIREWALL_TOKENS:-}")"
    fi
    while [[ -n "$new_tokens" ]]; do
        new_item="${new_tokens%%,*}"
        if [[ "$new_tokens" == *','* ]]; then new_tokens="${new_tokens#*,}"; else new_tokens=''; fi
        local remaining="$old_tokens"
        old_index=1
        label=''
        while [[ -n "$remaining" ]]; do
            old_item="${remaining%%,*}"
            if [[ "$remaining" == *','* ]]; then remaining="${remaining#*,}"; else remaining=''; fi
            if [[ "${old_item%%@*}" == "${new_item%%@*}" ]]; then
                label="$(official_account_name "$old_index")"
                break
            fi
            old_index=$((old_index + 1))
        done
        result="$result$separator$label"
        separator=';'
    done
    PO0_FIREWALL_NAMES="$result"
}
