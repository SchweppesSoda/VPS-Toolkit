show_current_config() {
    print_panel_section "PO0 Outbound IP Report 客户端配置"
    print_panel_row "配置文件" "${CONFIG_FILE}"
    print_panel_row "保存状态" "$([[ -f "${CONFIG_FILE}" ]] && printf '已保存' || printf '未保存')"
    print_panel_row "LAN Worker URL" "${WORKER_URL:-未设置}"
    print_panel_row "来源 ID" "${SOURCE_ID:-未设置}"
    print_panel_row "设备备注" "${IDENTITY:-未设置}"
    print_panel_row "WAN 上报范围" "$(wan_selection_display)"
    print_panel_row "上游路由 WAN 探针" "${ROUTER_PROBE_URL:-不使用}"
    print_panel_row "上报密钥" "$(mask_secret "${SECRET}")"
    print_panel_row "HTTP 上报" "$(if http_allowed; then printf '已显式允许'; else printf '默认拒绝'; fi)"
    print_panel_row "跳过 Wi-Fi SSID" "$(wifi_ssid_skip_list_display)"
    print_panel_row "上报间隔" "$(cron_minutes_to_seconds "${CRON_MINUTES}") 秒（安装定时上报时使用）"
    print_panel_row "定时暂停" "$(schedule_paused && printf '已暂停' || printf '未暂停')"
    print_panel_row "放行时长" "由 LAN Worker 接收端控制，默认 43200 秒"
    if [[ -n "${IP_CHECK_URLS}" ]]; then
        print_panel_row "IP 探测列表" "${IP_CHECK_URLS}"
    else
        print_panel_row "首选 IP 探测" "${IP_CHECK_URL}"
    fi
}

show_menu_dashboard() {
    print_title "PO0 Outbound IP Report Client"
    print_panel_section "脚本信息"
    print_panel_row "脚本名称" "${SCRIPT_NAME}"
    print_panel_row "版本" "${SCRIPT_VERSION}"
    print_panel_row "构建标识" "$(script_build_label)"
    print_panel_row "发布日期" "${SCRIPT_RELEASE_DATE}"
    print_panel_row "执行来源" "$(current_script_path)"
    print_panel_row "默认安装路径" "$(default_install_path)"
    print_panel_row "下载 URL" "${DOWNLOAD_URL}"

    print_panel_section "当前状态"
    print_panel_row "配置文件" "${CONFIG_FILE}"
    print_panel_row "保存状态" "$([[ -f "${CONFIG_FILE}" ]] && printf '已保存' || printf '未保存')"
    print_panel_row "LAN Worker URL" "${WORKER_URL:-未设置}"
    print_panel_row "来源 ID" "${SOURCE_ID:-未设置}"
    print_panel_row "设备备注" "${IDENTITY:-未设置}"
    print_panel_row "WAN 上报范围" "$(wan_selection_display)"
    print_panel_row "上游路由 WAN 探针" "${ROUTER_PROBE_URL:-不使用}"
    print_panel_row "跳过 Wi-Fi SSID" "$(wifi_ssid_skip_list_display)"
    print_panel_row "定时上报" "$(cron_status_summary)"
    print_panel_row "上报间隔" "$(cron_minutes_to_seconds "${CRON_MINUTES}") 秒（安装定时上报时使用）"
}

configure_interactive() {
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
    ROUTER_PROBE_URL="$(prompt_default "上游 OpenWrt 内网 WAN 探针 URL（留空在本机探测）" "${ROUTER_PROBE_URL}")"
    ROUTER_PROBE_URL="$(normalize_router_probe_url "${ROUTER_PROBE_URL}")"
    validate_router_probe_url || return 1
    cron_seconds="$(prompt_default "客户端每几秒上报一次（60-$(max_interval_seconds)；必须是 60 的倍数）" "$(cron_minutes_to_seconds "${CRON_MINUTES}")")"
    CRON_MINUTES="$(normalize_interval_seconds_to_minutes "${cron_seconds}" "${MAX_CRON_MINUTES}")" || {
        printf '上报间隔秒数无效：请输入 60-%s 且为 60 倍数的整数。\n' "$(max_interval_seconds)" >&2
        return 1
    }
    IP_CHECK_URL="$(prompt_default "首选公网 IPv4 探测 URL" "${IP_CHECK_URL}")"
    if prompt_yes_no "是否覆盖完整 IP 探测 URL 列表" "n"; then
        IP_CHECK_URLS="$(prompt_default "完整探测 URL 列表，逗号分隔" "${IP_CHECK_URLS}")"
    fi
    wan_default="${WANS}"
    [[ -n "${ROUTER_PROBE_URL}" && -z "${wan_default}" ]] && wan_default="all"
    WANS="$(prompt_default "OpenWrt WAN 逻辑接口（分号 ; 分隔；all 表示全部 mwan3 WAN；留空按默认路由）" "${wan_default}")"
    WANS="$(normalize_wan_selection_list "${WANS}")"
    validate_wan_selection || return 1
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
    local cron_seconds
    if ! config_complete; then
        configure_interactive || return 1
    else
        cron_seconds="$(prompt_default "定时上报每几秒执行一次（60-$(max_interval_seconds)；必须是 60 的倍数）" "$(cron_minutes_to_seconds "${CRON_MINUTES}")")"
        CRON_MINUTES="$(normalize_interval_seconds_to_minutes "${cron_seconds}" "${MAX_CRON_MINUTES}")" || {
            printf '上报间隔秒数无效：请输入 60-%s 且为 60 倍数的整数。\n' "$(max_interval_seconds)" >&2
            return 1
        }
    fi
    install_cron
}

menu_loop() {
    local choice rc
    while true; do
        menu_clear_screen
        show_menu_dashboard
        print_menu_section "手动上报"
        print_menu_pair 1 "配置并保存上报参数" 2 "立即上报一次"
        print_menu_section "定时上报"
        print_menu_pair 3 "安装 / 更新定时上报" 4 "暂停 / 恢复定时上报"
        print_menu_pair 5 "查看定时上报状态" 6 "删除定时上报"
        print_menu_section "查看"
        print_menu_item 7 "显示当前配置"
        print_menu_section "维护"
        print_menu_pair 8 "从 GitHub 更新脚本" 9 "卸载本客户端"
        print_menu_section "退出"
        print_menu_item 0 "退出"
        print_menu_footer
        choice="$(read_prompt "请选择操作 [0-9]: ")" || return 0
        choice="$(trim "${choice}")"
        case "${choice}" in
            1) configure_interactive; pause_before_return ;;
            2) run_once_interactive; pause_before_return ;;
            3) install_cron_interactive; pause_before_return ;;
            4) toggle_schedule_interactive; pause_before_return ;;
            5) show_cron_status; pause_before_return ;;
            6)
                if prompt_yes_no "确认删除 PO0 Outbound IP Report 定时上报" "n"; then
                    remove_cron
                else
                    echo "已取消。"
                fi
                pause_before_return
                ;;
            7) show_current_config; pause_before_return ;;
            8) upgrade_self_from_download --reopen-menu || pause_before_return ;;
            9)
                uninstall_self_report_interactive
                rc=$?
                pause_before_return
                [[ "${rc}" == "0" ]] && return 0
                ;;
            0) return 0 ;;
            "") ;;
            *) printf '无效选择。\n' >&2; pause_before_return ;;
        esac
    done
}
