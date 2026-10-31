configure_official_interactive() {
    local previous_tokens="${PO0_FIREWALL_TOKENS}"
    print_panel_section "PO0 防火墙参数"
    printf '官方定时上报可关闭、可修改，默认 600 秒；网络变化单独触发。Token 可带 @0..9 指定槽位。\n'
    po0_firewall_read_tokens_interactive || { PO0_FIREWALL_TOKENS="${previous_tokens}"; return 1; }
    sync_official_account_names "$previous_tokens"
    save_config_file
}

clear_official_tokens_interactive() {
    prompt_yes_no "确认清除已保存的官方防火墙 token" "n" || return 0
    PO0_FIREWALL_TOKENS=""
    PO0_FIREWALL_NAMES=""
    OFFICIAL_AUTO_ENABLED=0
    save_config_file
}

show_current_config() {
    print_title 'PO0 防火墙 · 本机配置'
    show_channel_config official
    print_panel_section '网络探测与 Wi-Fi 跳过'
    print_panel_row 'IPv4 探测' "${IP_CHECK_URL:-默认}"
    print_panel_row 'SSID 跳过' "${SKIP_WIFI_SSIDS:-未设置}"
    print_panel_section '文件位置'
    print_panel_row '配置文件' "$CONFIG_FILE"
}

configure_interactive() {
    configure_official_interactive
}
configure_common_interactive() {
    print_panel_section "网络探测与 Wi-Fi 跳过"
    IP_CHECK_URL="$(prompt_default "首选公网 IPv4 探测 URL" "${IP_CHECK_URL}")"
    if prompt_yes_no "是否覆盖完整 IP 探测 URL 列表" "n"; then
        IP_CHECK_URLS="$(prompt_default "完整探测 URL 列表，逗号分隔" "${IP_CHECK_URLS}")"
    fi
    prompt_skip_wifi_ssids_interactive
    save_config_file
}

run_once_interactive() {
    local previous_force rc
    if ! config_complete; then
        configure_interactive || return 1
    fi
    if should_skip_wifi_ssid_report; then
        if prompt_yes_no "当前 Wi-Fi SSID \"${WIFI_SKIP_LAST_SSID}\" 在跳过列表中，是否强制上报本次" "n"; then
            previous_force="${FORCE_REPORT}"
            FORCE_REPORT="1"
            report_once
            rc=$?
            FORCE_REPORT="${previous_force}"
            return "${rc}"
        fi
    fi
    report_once
}

official_status_interactive() {
    local previous_status rc
    previous_status="${OFFICIAL_STATUS_ONLY}"
    OFFICIAL_STATUS_ONLY="1"
    report_once
    rc="$?"
    OFFICIAL_STATUS_ONLY="${previous_status}"
    return "${rc}"
}

install_cron_interactive() {
    local channel="${1:-all}"
    if [[ "$channel" == all ]]; then install_cron all; return $?; fi
    schedule_channel_configured "$channel" || { printf '请先在「官方账号与槽位」中保存 Token。\n'; return 1; }
    configure_channel_periodic_interactive "$channel" || return 1
    install_cron "$channel"
}

menu_loop() {
    local choice
    CLIENT_MENU_UNINSTALLED=0
    while true; do
        menu_clear_screen
        show_client_overview
        print_panel_section '上报与查询'
        print_menu_item 1 '立即上报'
        print_menu_item 2 '查询官方白名单（只读）'
        print_menu_item 3 '最近上报结果'
        print_panel_section '设置'
        print_menu_item 4 '官方账号与槽位'
        print_menu_item 5 '自动上报与计划任务'
        print_menu_item 6 '网络探测与 Wi-Fi 跳过'
        print_menu_item 7 '查看本机配置'
        print_panel_section '维护'
        print_menu_item 8 '维护与诊断'
        print_menu_item 0 '退出'
        print_menu_footer
        choice="$(read_prompt '请选择 [0-8]: ')" || return 0
        case "$(trim "$choice")" in
            1) run_channel_interactive official; pause_before_return ;;
            2) show_channel_status official; pause_before_return ;;
            3) show_recent_report_results; pause_before_return ;;
            4) official_account_menu ;;
            5) automatic_reporting_menu ;;
            6) configure_common_interactive; pause_before_return ;;
            7) show_current_config; pause_before_return ;;
            8) client_maintenance_menu; [[ "${CLIENT_MENU_UNINSTALLED:-0}" != 1 ]] || return 0 ;;
            0) return 0 ;;
            *) printf '无效选择：请输入 0-8。\n'; pause_before_return ;;
        esac
    done
}
