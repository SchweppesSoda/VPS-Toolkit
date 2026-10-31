official_read_secret_prompt() {
    local prompt="$1" value="" line="" separator=""
    while true; do
        if [[ -r /dev/tty && -w /dev/tty ]] && { : < /dev/tty; } 2>/dev/null; then
            printf '%s' "${prompt}" > /dev/tty || return 1
            IFS= read -r line < /dev/tty || break
        else
            printf '%s' "${prompt}" >&2
            IFS= read -r line || break
        fi
        [[ -n "$(trim "${line}")" ]] || break
        value="${value}${separator}${line}"
        [[ "${value}" == "-" ]] && break
        separator=$'\n'
        prompt='继续输入（空行结束）: '
    done
    printf '%s\n' "${value}"
}

configure_official_interactive() {
    local token_input previous_tokens="${PO0_FIREWALL_TOKENS:-}"
    print_panel_section "PO0 防火墙参数"
    print_panel_row "当前官方 Token" "${PO0_FIREWALL_TOKENS:-未设置}"
    printf '官方定时上报可关闭、可修改，默认 600 秒；网络变化单独触发。可用逗号、分号、空格或换行分隔，槽位写 @0..9。空行结束；直接空行保留，单独 - 清空。\n'
    token_input="$(official_read_secret_prompt '输入官方 Token（空行结束）: ')" || return 1
    token_input="$(trim "${token_input}")"
    case "${token_input}" in
        "") return 0 ;;
        "-") PO0_FIREWALL_TOKENS="" ;;
        *) PO0_FIREWALL_TOKENS="${token_input}" ;;
    esac
    PO0_FIREWALL_TOKENS="$(official_normalize_tokens "${PO0_FIREWALL_TOKENS}")"
    if [[ -n "${PO0_FIREWALL_TOKENS}" ]]; then
        official_validate_tokens || { PO0_FIREWALL_TOKENS="${previous_tokens}"; return 1; }
    fi
    sync_official_account_names "$previous_tokens"
    save_config_file
}

clear_official_tokens_interactive() {
    if ! official_channel_enabled; then
        printf '官方防火墙当前未配置 token。\n'
        return 0
    fi
    if ! prompt_yes_no "确认清除已保存的官方防火墙 token" "n"; then
        echo '已取消。'
        return 0
    fi
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
    SKIP_WIFI_SSIDS="$(prompt_default "跳过上报的 Wi-Fi SSID 列表（分号 ; 分隔，留空表示不跳过）" "$(normalize_wifi_ssid_skip_list "${SKIP_WIFI_SSIDS:-}")")"
    SKIP_WIFI_SSIDS="$(normalize_wifi_ssid_skip_list "${SKIP_WIFI_SSIDS:-}")"
    save_config_file
}

run_once_interactive() {
    local rc previous_force skip_ssid
    if ! config_complete; then
        configure_interactive || return 1
    fi
    skip_ssid="$(wifi_ssid_report_skip_match 2>/dev/null || true)"
    if [[ -n "${skip_ssid}" ]] && ! force_report_enabled; then
        if prompt_yes_no "当前 Wi-Fi SSID \"${skip_ssid}\" 在跳过列表中，是否强制上报一次" "n"; then
            previous_force="${FORCE_REPORT:-}"
            FORCE_REPORT="1"
            report_once
            rc=$?
            FORCE_REPORT="${previous_force}"
            return "${rc}"
        fi
    fi
    report_once
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
