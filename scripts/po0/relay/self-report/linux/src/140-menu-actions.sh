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
    print_panel_section "PO0 官方防火墙参数"
    print_panel_row "当前官方 Token" "${PO0_FIREWALL_TOKENS:-未设置}"
    printf '官方定时上报可关闭、可修改，默认 600 秒；网络变化单独触发。可用逗号、分号、空格或换行分隔，槽位写 @0..4。空行结束；直接空行保留，单独 - 清空。\n'
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
    print_panel_section "PO0 Outbound IP Report 客户端配置"
    print_panel_row "配置文件" "${CONFIG_FILE}"
    print_panel_row "保存状态" "$([[ -f "${CONFIG_FILE}" ]] && printf '已保存' || printf '未保存')"
    print_panel_section "自建防火墙 · LAN Worker"
    print_panel_row "目标名称" "${WORKER_NAME:-LAN Worker}"
    print_panel_row "自建自动上报" "$(channel_auto_label worker)"
    print_panel_row "LAN Worker URL" "${WORKER_URL:-未设置}"
    print_panel_row "来源 ID" "${SOURCE_ID:-未设置}"
    print_panel_row "设备备注" "${IDENTITY:-未设置}"
    print_panel_row "WAN 上报范围" "$(wan_selection_display)"
    print_panel_row "上报密钥" "${SECRET:-未设置}"
    print_panel_row "HTTP 上报" "$(if http_allowed; then printf '已显式允许'; else printf '默认拒绝'; fi)"
    print_panel_row "放行时长" "由 LAN Worker 接收端管理"
    print_panel_row "自建上报间隔" "$(cron_minutes_to_seconds "${CRON_MINUTES}") 秒（安装定时上报时使用）"
    print_panel_section "PO0 官方防火墙"
    print_panel_row "官方目标名称" "${PO0_FIREWALL_NAMES:-未设置，按账号编号显示}"
    print_panel_row "官方自动上报" "$(channel_auto_label official)"
    print_panel_row "官方 Token" "${PO0_FIREWALL_TOKENS:-未设置}"
    print_panel_row "官方状态" "$(official_state_summary)"
    print_panel_row "官方检查周期" "${OFFICIAL_INTERVAL_SECONDS:-600} 秒（可关闭）"
    print_panel_section "通用设置与定时任务"
    print_panel_row "跳过 Wi-Fi SSID" "$(wifi_ssid_skip_list_display)"
    print_panel_row "定时暂停" "$(schedule_paused && printf '已暂停' || printf '未暂停')"
    if [[ -n "${IP_CHECK_URLS}" ]]; then
        print_panel_row "IP 探测列表" "${IP_CHECK_URLS}"
    else
        print_panel_row "首选 IP 探测" "${IP_CHECK_URL}"
    fi
}

configure_interactive() {
    print_panel_section "自建防火墙 · LAN Worker 参数"
    local secret_input cron_seconds wan_default
    WORKER_URL="$(prompt_default "LAN Worker self-report HTTPS 接收地址（域名或 https://域名/report）" "${WORKER_URL:-https://report.example.com/report}")"
    WORKER_URL="$(normalize_worker_url "${WORKER_URL}")"
    if [[ "${WORKER_URL}" == http://* ]] && ! http_allowed; then
        if prompt_yes_no "检测到 http:// 地址。仅本地调试/旧环境才允许，是否继续允许 HTTP" "n"; then
            ALLOW_HTTP="1"
        else
            printf '已拒绝 HTTP。请改用 https://域名/report。\n' >&2
            return 1
        fi
    fi
    validate_worker_url || return 1
    SOURCE_ID="$(prompt_default "来源 ID" "${SOURCE_ID:-$(default_source_id)}")"
    IDENTITY="$(prompt_default "设备备注" "${IDENTITY}")"
    print_panel_row "当前上报密钥" "${SECRET:-未设置}"
    if [[ -n "${SECRET}" ]]; then
        secret_input="$(read_prompt "Self-report secret [已设置，回车保留，输入 - 清空]: ")" || secret_input=""
        secret_input="$(trim "${secret_input}")"
        case "${secret_input}" in
            "") ;;
            "-") SECRET="" ;;
            *) SECRET="${secret_input}" ;;
        esac
    else
        SECRET="$(prompt_default "Self-report secret，可空" "")"
    fi
    cron_seconds="$(prompt_default "自建防火墙上报间隔（秒）（60-$(max_interval_seconds)；必须是 60 的倍数）" "$(cron_minutes_to_seconds "${CRON_MINUTES}")")"
    CRON_MINUTES="$(normalize_interval_seconds_to_minutes "${cron_seconds}" "${MAX_CRON_MINUTES}")" || {
        printf '上报间隔秒数无效：请输入 60-%s 且为 60 倍数的整数。\n' "$(max_interval_seconds)" >&2
        return 1
    }
    wan_default="${WANS}"
    WANS="$(prompt_default "OpenWrt WAN 逻辑接口（分号 ; 分隔；all 表示全部本机 mwan3 WAN；留空按默认路由）" "${wan_default}")"
    WANS="$(normalize_wan_selection_list "${WANS}")"
    validate_wan_selection || return 1
    save_config_file
}

configure_common_interactive() {
    print_panel_section "通用设置 · 本机探测与 Wi-Fi 跳过"
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
    schedule_channel_configured "$channel" || { printf '请先保存本通道参数。\n'; return 1; }
    configure_channel_periodic_interactive "$channel" || return 1
    install_cron "$channel"
}

menu_loop() {
    if legacy_schedule_exists; then refresh_channel_schedules all || printf '旧任务迁移失败，请查看自动上报状态。\n' >&2; fi
    local choice
    CLIENT_MENU_UNINSTALLED=0
    while true; do
        menu_clear_screen
        show_client_overview
        print_menu_section "通道设置"
        print_menu_item 1 "自建防火墙"
        print_menu_item 2 "官方防火墙"
        print_menu_section "通用操作"
        print_menu_item 3 "网络探测 / SSID 跳过"
        print_menu_item 4 "立即上报全部已配置通道"
        print_menu_item 5 "自动上报管理"
        print_menu_item 6 "查看本机配置"
        print_menu_item 7 "维护与诊断"
        print_menu_item 0 "退出"
        print_menu_footer
        choice="$(read_prompt "请选择 [0-7]: ")" || return 0
        case "$(trim "${choice}")" in
            1) channel_settings_menu worker ;;
            2) channel_settings_menu official ;;
            3) configure_common_interactive; pause_before_return ;;
            4) run_channel_interactive all; pause_before_return ;;
            5) automatic_reporting_menu ;;
            6) show_current_config; pause_before_return ;;
            7) client_maintenance_menu; [[ "${CLIENT_MENU_UNINSTALLED:-0}" != 1 ]] || return 0 ;;
            0) return 0 ;;
            *) printf '无效选择：请输入 0-7。\n'; pause_before_return ;;
        esac
    done
}
