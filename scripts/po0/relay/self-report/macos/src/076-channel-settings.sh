# Local channel controls. Missing values preserve existing automatic reporting.
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

toggle_channel_auto_interactive() {
    local channel="$1" value=1 label='自建 PO0'
    [[ "$channel" != official ]] || label='官方防火墙'
    channel_auto_enabled "$channel" && value=0
    if [[ "$channel" == worker ]]; then WORKER_AUTO_ENABLED="$value"; else OFFICIAL_AUTO_ENABLED="$value"; fi
    save_config_file || return 1
    printf '%s自动上报：%s。手动上报仍可使用。\n' "$label" "$(channel_auto_label "$channel")"
}

clear_worker_config_interactive() {
    prompt_yes_no '清除本机自建 PO0 地址、密钥和目标名称（保留官方及通用设置）' n || return 0
    WORKER_URL=''
    SECRET=''
    WORKER_NAME=''
    WORKER_AUTO_ENABLED=0
    save_config_file
}

set_channel_names_interactive() {
    local channel="$1" name raw count=0 index=1 names=''
    if [[ "$channel" == worker ]]; then
        name="$(prompt_default '自建上报目标名称（仅本机显示）' "${WORKER_NAME:-LAN Worker}")" || return 1
        [[ "$name" != - ]] || name=""
        WORKER_NAME="$name"
    else
        if declare -F official_tokens_count >/dev/null; then count="$(official_tokens_count)"; else count="$(po0_firewall_token_count)"; fi
        [[ "$count" -gt 0 ]] || { printf '请先保存官方 Token，再设置对应目标名称。\n'; return 1; }
        printf '按当前 Token 的顺序逐个设置名称；名称只在本机显示。\n'
        while (( index <= count )); do
            name="$(prompt_default "官方目标 ${index} 名称" "$(official_account_name "$index")")" || return 1
            case "$name" in *';'*|*'；'*|*$'\n'*|*$'\r'*) printf '单个名称不能包含分号或换行。\n' >&2; return 1 ;; esac
            [[ "$index" == 1 ]] || names="$names;"
            [[ "$name" != - ]] || name=""
            names="$names$name"
            index=$((index + 1))
        done
        PO0_FIREWALL_NAMES="$names"
    fi
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
        printf "此通道尚未配置，请先编辑并保存参数。\n"
        rc=1
    elif ! config_complete; then
        printf "尚未配置上报通道，请先进入通道设置。\n"
        rc=1
    else
        run_once_interactive
        rc=$?
    fi
    REPORT_MODE="$old_mode"
    OFFICIAL_ONLY="$old_official"
    WORKER_ONLY="$old_worker"
    SCHEDULED_RUN="$old_scheduled"
    return "$rc"
}

show_channel_status() {
    if [[ "$1" == official ]]; then
        if declare -F official_status_interactive >/dev/null; then official_status_interactive; else official_status_once; fi
    else
        print_panel_section '自建 PO0 · 本机状态'
        print_panel_row '目标名称' "${WORKER_NAME:-LAN Worker}"
        print_panel_row '接收地址' "${WORKER_URL:-未配置}"
        print_panel_row '自动上报' "$(channel_auto_label worker)"
        print_panel_row '上报间隔' "$(cron_minutes_to_seconds "$CRON_MINUTES") 秒"
        print_panel_row '放行有效期 TTL' '由 LAN Worker 接收端设置，默认 43200 秒'
        print_panel_row '设备备注' "${IDENTITY:-未设置}"
        print_panel_row '定时任务' "$(cron_status_summary)"
    fi
}

channel_settings_menu() {
    local channel="$1" choice title='自建 PO0'
    [[ "$channel" != official ]] || title='官方防火墙'
    while true; do
        menu_clear_screen
        print_title "$title · 设置"
        print_panel_row '配置状态' "$(if [[ "$channel" == official ]]; then [[ -n "${PO0_FIREWALL_TOKENS:-}" ]] && printf "已配置" || printf "未配置"; else [[ -n "${WORKER_URL:-}" ]] && printf "已配置" || printf "未配置"; fi)"
        print_panel_row '自动上报' "$(channel_auto_label "$channel")"
        if [[ "$channel" == official ]]; then
            print_panel_row '检查间隔' '固定 600 秒'
            print_panel_row '放行有效期 TTL' '由官方服务管理，接口未提供自定义 TTL'
        else
            print_panel_row '上报间隔' "$(cron_minutes_to_seconds "$CRON_MINUTES") 秒"
            print_panel_row '放行有效期 TTL' '由 LAN Worker 接收端设置，默认 43200 秒'
        fi
        print_menu_item 1 '编辑并保存参数'
        print_menu_item 2 '设置目标名称'
        print_menu_item 3 '启用 / 停用本通道自动上报'
        print_menu_item 4 '仅本通道立即上报'
        print_menu_item 5 '查看本通道状态'
        print_menu_item 6 '清除此通道保存的配置'
        print_menu_item 0 '返回主菜单'
        choice="$(read_prompt '请选择 [0-6]: ')" || return 0
        case "$(trim "$choice")" in
            1) if [[ "$channel" == worker ]]; then configure_interactive && update_channel_schedule_if_installed; else configure_official_interactive && update_channel_schedule_if_installed; fi ;;
            2) set_channel_names_interactive "$channel" ;;
            3) toggle_channel_auto_interactive "$channel" && update_channel_schedule_if_installed ;;
            4) run_channel_interactive "$channel" ;;
            5) show_channel_status "$channel" ;;
            6) if [[ "$channel" == worker ]]; then clear_worker_config_interactive && update_channel_schedule_if_installed; else clear_official_tokens_interactive && update_channel_schedule_if_installed; fi ;;
            0) return 0 ;;
            *) printf '无效选择：请输入 0-6。\n' ;;
        esac
        pause_before_return
    done
}

automatic_reporting_menu() {
    local choice max_choice=4
    declare -F toggle_notify_interactive >/dev/null && max_choice=5
    while true; do
        menu_clear_screen
        print_title '自动上报 · 两个通道共用一个计划'
        print_panel_row '自建 PO0' "$(channel_auto_label worker)"
        print_panel_row '官方防火墙' "$(channel_auto_label official)"
        print_panel_row '计划状态' "$(cron_status_summary)"
        printf "安装后自动处理两个已配置且启用的通道，各自按自己的间隔上报。\n"
        print_menu_item 1 '安装 / 更新自动上报'
        print_menu_item 2 '暂停 / 恢复全部自动上报'
        print_menu_item 3 '查看计划状态和日志'
        print_menu_item 4 '删除自动上报计划'
        if declare -F toggle_notify_interactive >/dev/null; then print_menu_item 5 '通知 / 静默设置'; fi
        print_menu_item 0 '返回主菜单'
        choice="$(read_prompt "请选择 [0-$max_choice]: ")" || return 0
        case "$(trim "$choice")" in
            1) install_cron_interactive ;;
            2) toggle_schedule_interactive ;;
            3) show_cron_status ;;
            4) if prompt_yes_no '删除全部自动上报计划（保留两个通道的配置）' n; then remove_cron; fi ;;
            5) if declare -F toggle_notify_interactive >/dev/null; then toggle_notify_interactive; else printf '此系统的自动上报结果记录在本机日志中。\n'; fi ;;
            0) return 0 ;;
            *) printf "无效选择：请输入 0-%s。\n" "$max_choice" ;;
        esac
        pause_before_return
    done
}

client_maintenance_menu() {
    local choice rc max_choice=2
    declare -F show_wifi_ssid_permission_help_interactive >/dev/null && max_choice=4
    while true; do
        menu_clear_screen
        print_title '维护与诊断'
        print_panel_row '客户端版本' "$SCRIPT_VERSION"
        print_panel_row '当前脚本' "$(current_script_path)"
        print_panel_row '安装位置' "$(default_install_path)"
        print_panel_row '配置文件' "$CONFIG_FILE"
        print_panel_row '日志位置' "$(self_report_log_path)"
        print_menu_item 1 '更新客户端脚本'
        print_menu_item 2 '卸载客户端'
        if declare -F show_wifi_ssid_permission_help_interactive >/dev/null; then
            print_menu_item 3 'Wi-Fi SSID 权限诊断'
            print_menu_item 4 '删除定位权限 Helper'
        fi
        print_menu_item 0 '返回主菜单'
        choice="$(read_prompt "请选择 [0-$max_choice]: ")" || return 0
        case "$(trim "$choice")" in
            1) upgrade_self_from_download --reopen-menu ;;
            2) uninstall_self_report_interactive; rc=$?; [[ "$rc" != 0 ]] || { CLIENT_MENU_UNINSTALLED=1; return 0; } ;;
            3) if declare -F show_wifi_ssid_permission_help_interactive >/dev/null; then show_wifi_ssid_permission_help_interactive; else printf '此选项仅适用于 macOS。\n'; fi ;;
            4) if declare -F remove_macos_location_permission_helper_app_interactive >/dev/null; then remove_macos_location_permission_helper_app_interactive; else printf '此选项仅适用于 macOS。\n'; fi ;;
            0) return 0 ;;
            *) printf "无效选择：请输入 0-%s。\n" "$max_choice" ;;
        esac
        pause_before_return
    done
}

show_client_overview() {
    local count=0
    if declare -F official_tokens_count >/dev/null; then count="$(official_tokens_count)"; else count="$(po0_firewall_token_count)"; fi
    print_title 'PO0 出口上报'
    print_panel_row '客户端版本' "$SCRIPT_VERSION"
    print_panel_row '自建 PO0' "${WORKER_NAME:-LAN Worker} · $([[ -n "${WORKER_URL:-}" ]] && channel_auto_label worker || printf '未配置')"
    print_panel_row '官方防火墙' "$([[ "$count" -gt 0 ]] && printf "%s 个目标 · %s" "$count" "$(channel_auto_label official)" || printf "未配置")"
    print_panel_row '自动上报计划' "$(cron_status_summary)"
    if declare -F wifi_ssid_skip_list_display >/dev/null; then
        print_panel_row 'SSID 跳过' "$(wifi_ssid_skip_list_display)"
    else
        print_panel_row 'SSID 跳过' "$(skip_wifi_ssids_label)"
    fi
    print_panel_row '配置' "$([[ -f "$CONFIG_FILE" ]] && printf "已保存在本机" || printf "尚未保存")"
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

update_channel_schedule_if_installed() {
    config_complete || return 0
    if cron_managed_block_exists; then
        install_cron
    elif declare -F launchd_supported >/dev/null && launchd_supported && { [[ -f "$(launchd_plist_path)" ]] || legacy_launchd_plist_exists; }; then
        install_cron
    fi
}
