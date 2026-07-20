print_script_info_panel() {
    local script_path
    script_path="$(current_script_path 2>/dev/null || true)"
    print_panel_section "脚本信息"
    print_panel_row "脚本名称" "${SCRIPT_NAME}"
    print_panel_row "版本" "${SCRIPT_VERSION}"
    print_panel_row "构建标识" "$(script_build_label)"
    print_panel_row "发布日期" "${SCRIPT_RELEASE_DATE}"
    print_panel_row "当前脚本" "${script_path:-unknown}"
    print_panel_row "安装路径" "${MANAGER_INSTALL_PATH}"
    print_panel_row "下载 URL" "${MANAGER_DOWNLOAD_URL}"
    print_panel_row "配置目录" "${CONF_DIR}"
    print_panel_row "设置文件" "${SETTINGS_FILE}"
    print_panel_row "规则文件" "${RULES_FILE}"
}

main_menu() {
    local choice
    while true; do
        menu_clear_screen
        print_title "nftables relay manager"
        print_script_info_panel
        print_status_panel
        print_runtime_rule_hint
        print_recommended_operations
        print_menu_section "部署与概览"
        print_menu_pair 1 "安装 / 初始化 nftables" 2 "刷新 PO0 公网 IP"
        print_menu_item 3 "查看概览与规则列表"
        print_menu_section "转发规则"
        print_menu_pair 4 "新增规则" 5 "编辑规则"
        print_menu_pair 6 "调整顺序" 7 "启用 / 停用"
        print_menu_pair 8 "删除规则" 9 "导入 / 接管现有规则"
        print_menu_item 10 "导出规则"
        print_menu_section "来源、客户端与资源"
        print_menu_pair 11 "源 IP 白名单" 12 "客户端部署命令"
        print_menu_item 13 "内网资源更新任务"
        print_menu_section "系统维护"
        print_menu_pair 14 "中转机参数" 15 "诊断 / 自检"
        print_menu_pair 16 "脚本版本 / 更新" 17 "可选开启 BBR + fq"
        print_menu_item 18 "完整备份 / 导入恢复"
        print_menu_section "退出"
        print_menu_item 0 "退出"
        print_menu_footer
        read_menu_choice_or_return choice "请选择操作 [0-18]: " || exit 0
        case "${choice}" in
            1) do_install; pause_before_return ;;
            2) do_refresh_public_ip ;;
            3) do_list ;;
            4) do_add; pause_before_return ;;
            5) do_edit_rule; pause_before_return ;;
            6) do_reorder_rules; pause_before_return ;;
            7) do_toggle_rules; pause_before_return ;;
            8) do_delete; pause_before_return ;;
            9) do_import_rules; [[ "$?" -eq 2 ]] || pause_before_return ;;
            10) do_export_rules; pause_before_return ;;
            11) do_manage_src_allowlist ;;
            12) do_manage_client_deploy_commands ;;
            13) do_manage_resource_tasks ;;
            14) do_edit_settings; pause_before_return ;;
            15) do_diagnose; pause_before_return ;;
            16) do_manage_version_update ;;
            17) do_enable_bbr; pause_before_return ;;
            18) do_full_backup_restore_interactive; pause_before_return ;;
            0)
                info "再见。"
                exit 0
                ;;
            *)
                err "无效选择，请输入 0-18。"
                pause_before_return
                ;;
        esac
    done
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    print_cli_usage
    exit 0
fi
if [[ "${1:-}" == "--version" || "${1:-}" == "-V" ]]; then
    do_show_version
    exit 0
fi
if [[ "${1:-}" == "--changelog" || "${1:-}" == "--changes" ]]; then
    do_show_changelog
    exit 0
fi

check_root
case "${1:-}" in
    --learn-service)
        run_learning_service
        exit $?
        ;;
    --render)
        do_render
        exit $?
        ;;
    --backup-export)
        if [[ -n "${2:-}" && "${2:-}" != --* ]]; then
            do_full_backup_export "${2:-}"
        else
            do_full_backup_export
        fi
        exit $?
        ;;
    --backup-import)
        do_full_backup_import "${@:2}"
        exit $?
        ;;
    --upgrade-manager-from-lan)
        if [[ -n "${2:-}" && "${2:-}" != --* ]]; then
            do_upgrade_manager_from_lan "${2:-}"
        else
            do_upgrade_manager_from_lan
        fi
        exit $?
        ;;
    --refresh-ddns)
        do_refresh_ddns_allowlist_sources
        exit $?
        ;;
    --outbound-ip-report|--ddns-report)
        do_report_ddns_allowlist_source "${2:-}" "${3:-}" "${4:-}"
        exit $?
        ;;
    --outbound-ip-report-check|--ddns-report-check)
        do_check_ddns_report_source "${2:-}" "${3:-}"
        exit $?
        ;;
    --client-ip-report)
        do_report_client_ip_source "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}" "${7:-}"
        exit $?
        ;;
    --client-ip-report-check)
        do_check_client_ip_report_source "${2:-}" "${3:-}"
        exit $?
        ;;
    --ssh-ip-report)
        do_report_ssh_ip_source "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}" "${7:-}"
        exit $?
        ;;
    --ssh-ip-report-check)
        do_check_ssh_ip_report_source "${2:-}" "${3:-}"
        exit $?
        ;;
    --webauth-report)
        do_report_webauth_source "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}" "${7:-}"
        exit $?
        ;;
    --webauth-report-check)
        do_check_webauth_report_source "${2:-}" "${3:-}"
        exit $?
        ;;
    --automation-mode)
        set_automation_mode "${2:-}"
        exit $?
        ;;
    --pending-auto-sources)
        do_list_pending_auto_sources
        exit $?
        ;;
    --cleanup-dynamic-allowlist)
        do_cleanup_dynamic_allowlist
        exit $?
        ;;
    --install-dynamic-allowlist-cleanup-cron)
        install_dynamic_allowlist_cleanup_cron "${@:2}"
        exit $?
        ;;
    --remove-dynamic-allowlist-cleanup-cron)
        remove_dynamic_allowlist_cleanup_cron
        exit $?
        ;;
    --show-client-deploy-commands)
        do_show_client_deploy_commands "${2:-index}"
        exit $?
        ;;
    --worker-token-bundle)
        do_worker_token_bundle "${2:-}"
        exit $?
        ;;
    --show-report-keys)
        do_show_report_keys_cli "${2:-root}"
        exit $?
        ;;
    --show-report-key-denials)
        do_show_report_key_denials_cli "${2:-50}"
        exit $?
        ;;
    --refresh-report-key-wrapper)
        do_refresh_report_key_wrapper_cli
        exit $?
        ;;
    --install-report-key)
        do_install_report_key_cli "${2:-}" "${3:-}" "${4:-root}"
        exit $?
        ;;
    --compat-check)
        do_compat_check
        exit $?
        ;;
    --cleanup-legacy)
        do_cleanup_legacy "${2:---dry-run}"
        exit $?
        ;;
    --resource-task-create)
        create_resource_tasks_for_type "${2:-all}"
        exit $?
        ;;
    --install-resource-task-cron)
        install_resource_task_cron "${2:-all}" "${@:3}"
        exit $?
        ;;
    --remove-resource-task-cron)
        remove_resource_task_cron
        exit $?
        ;;
    --resource-task-cron-status)
        do_resource_task_cron_status_cli
        exit $?
        ;;
    --resource-task-ping)
        do_resource_task_ping "${2:-}"
        exit $?
        ;;
    --resource-task-claim)
        claim_resource_task "${2:-}" "${3:-}"
        exit $?
        ;;
    --resource-task-upload)
        upload_resource_task_artifact "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}"
        exit $?
        ;;
    --resource-task-complete)
        finish_resource_task "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}"
        exit $?
        ;;
    --resource-task-fail)
        fail_resource_task "${2:-}" "${3:-}" "${4:-}" "${5:-}"
        exit $?
        ;;
    --collect-blocked)
        do_collect_blocked_ips "${2:-1 hour ago}"
        exit $?
        ;;
    "")
        main_menu
        ;;
    *)
        print_cli_usage >&2
        exit 2
        ;;
esac
