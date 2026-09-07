print_script_info_panel() {
    print_panel_row "脚本版本" "${SCRIPT_VERSION}"
    print_panel_row "更新方式" "LAN Worker"
}

main_menu() {
    local choice
    while true; do
        menu_clear_screen
        print_title "PO0 转发管理"
        print_script_info_panel
        print_status_panel
        print_menu_section "转发"
        print_menu_pair 1 "安装 / 应用转发" 2 "刷新中转机 IP"
        print_menu_pair 3 "查看规则" 4 "新增规则"
        print_menu_pair 5 "编辑规则" 6 "调整顺序"
        print_menu_pair 7 "启用 / 停用" 8 "删除规则"
        print_menu_pair 9 "导入规则" 10 "导出规则"
        print_menu_section "维护"
        print_menu_pair 11 "中转参数" 12 "诊断 / 自检"
        print_menu_pair 13 "版本 / Worker 更新" 14 "可选开启 BBR + fq"
        print_menu_pair 15 "备份 / 恢复" 16 "更新密钥"
        print_menu_pair 17 "旧版迁移检查" 18 "迁移旧后台功能"
        print_menu_item 0 "退出"
        read_menu_choice_or_return choice "请选择 [0-18]: " || return
        case "${choice}" in
            0) return ;;
            1) do_install ;;
            2) do_refresh_public_ip ;;
            3) do_list ;;
            4) do_add ;;
            5) do_edit_rule ;;
            6) do_reorder_rules ;;
            7) do_toggle_rules ;;
            8) do_delete ;;
            9) do_import_rules ;;
            10) do_export_rules ;;
            11) do_edit_settings ;;
            12) do_diagnose ;;
            13) do_manage_version_update ;;
            14) enable_bbr_fq ;;
            15) do_full_backup_restore_interactive ;;
            16) configure_update_key ;;
            17) manager_migration_check ;;
            18) migrate_retired_manager_state ;;
            *) err "请选择 0-18。" ;;
        esac
        pause_before_return
    done
}

case "${1:-}" in
    --help|-h) print_cli_usage; exit 0 ;;
    --version|-V) do_show_version; exit 0 ;;
    --changelog|--changes) do_show_changelog; exit 0 ;;
esac
check_root
case "${1:-}" in
    --render) do_render ;;
    --backup-export) do_full_backup_export "${2:-}" ;;
    --backup-import) do_full_backup_import "${2:-}" ;;
    --upgrade-manager-from-lan) do_upgrade_manager_from_lan "${2:-}" ;;
    --configure-update-key) configure_update_key ;;
    --migration-check|--compat-check) manager_migration_check ;;
    --migrate-retired-state) migrate_retired_manager_state ;;
    --cleanup-legacy) if [[ "${2:---dry-run}" == '--apply' ]]; then migrate_retired_manager_state; else manager_migration_check; fi ;;
    "") main_menu ;;
    *) err "此动作已退役或无效；使用 --help 查看新版命令。"; exit 2 ;;
esac
