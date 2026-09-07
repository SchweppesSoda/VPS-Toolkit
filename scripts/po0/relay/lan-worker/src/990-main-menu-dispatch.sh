usage() {
    cat <<'EOF'
PO0 更新 Worker
  --menu                              打开菜单
  --version / --changelog              版本及更新内容
  --configure-update-keys              保存与 PO0 配对的更新密钥
  --install-manager-update-http        安装 / 更新 HTTP 镜像服务
  --manager-update-mirror-server       前台运行镜像
  --manager-update-status              查看更新服务
  --upgrade-self                      从 Release 更新本机脚本
  --backup-export [文件]               备份更新配置
  --backup-import 文件                 恢复新版更新配置，不启动服务
  --migrate-retired-state              备份并停止旧接收与轮询任务
  --migrate-official 客户端路径         将旧官方配置迁到同机新版客户端
  --config / --settings-file           沿用原本机配置位置
自建上报、WebAuth、DDNS 白名单及资源队列已退役。
EOF
}

menu_loop() {
    local choice reporter
    while true; do
        menu_clear_screen
        print_title "PO0 更新 Worker"
        print_panel_row "版本" "${SCRIPT_VERSION}"
        print_panel_row "更新密钥" "$(manager_update_tokens_env | awk 'NF { n++ } END { print n+0 }') 个"
        print_panel_row "更新入口" "${MANAGER_UPDATE_DOMAIN:-未配置}"
        print_menu_pair 1 "服务状态" 2 "入口 / 监听设置"
        print_menu_pair 3 "更新密钥" 4 "安装 / 更新镜像服务"
        print_menu_pair 5 "更新 Worker 脚本" 6 "备份配置"
        print_menu_pair 7 "迁移旧后台功能" 8 "迁移官方上报到客户端"
        print_menu_item 9 "恢复更新配置"
        print_menu_item 0 "退出"
        read_menu_choice_or_return choice "请选择 [0-9]: " || return
        case "${choice}" in
            0) return ;;
            1) show_manager_update_http_status ;;
            2) edit_manager_update_http_settings ;;
            3) configure_update_keys ;;
            4) install_manager_update_http ;;
            5) upgrade_self_from_download --reopen-menu ;;
            6) worker_backup_export ;;
            7) migrate_worker_retired_state ;;
            8) reporter="$(read_prompt '新版官方客户端路径: ')" && migrate_worker_official "${reporter}" ;;
            9) reporter="$(read_prompt '新版备份路径: ')" && worker_backup_import "$reporter" ;;
            *) printf '请选择 0-9。\n' ;;
        esac
        pause_before_return
    done
}

CONFIG_FILE="$(default_config_file)"
prime_config_paths_from_args "$@"
refresh_settings_file
load_local_settings || { printf '读取本机设置失败。\n' >&2; exit 1; }
setup_colors
ACTION=menu
ACTION_ARG=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --config|--settings-file) require_arg_value "$@" || exit 2; shift 2 ;;
        --config=*|--settings-file=*) shift ;;
        --install-path) require_arg_value "$@" || exit 2; INSTALL_PATH="$2"; shift 2 ;;
        --manager-update-domain) require_arg_value "$@" || exit 2; MANAGER_UPDATE_DOMAIN="$2"; shift 2 ;;
        --manager-update-listen) require_arg_value "$@" || exit 2; MANAGER_UPDATE_LISTEN="$2"; shift 2 ;;
        --manager-update-backend) require_arg_value "$@" || exit 2; MANAGER_UPDATE_BACKEND="$2"; shift 2 ;;
        --manager-update-caddy-snippet) require_arg_value "$@" || exit 2; MANAGER_UPDATE_CADDY_SNIPPET="$2"; shift 2 ;;
        --caddyfile) require_arg_value "$@" || exit 2; CADDYFILE_PATH="$2"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        --version|-V) printf '%s %s\n' "${SCRIPT_NAME}" "${SCRIPT_VERSION}"; exit 0 ;;
        --changelog) script_file_changelog "$(script_source_path)"; exit $? ;;
        --menu) ACTION=menu; shift ;;
        --configure-update-keys|--install-manager-update-http|--manager-update-mirror-server|--manager-update-status|--upgrade-self|--migrate-retired-state) ACTION="${1#--}"; shift ;;
        --migrate-official) require_arg_value "$@" || exit 2; ACTION=migrate-official; ACTION_ARG="$2"; shift 2 ;;
        --backup-import) require_arg_value "$@" || exit 2; ACTION=backup-import; ACTION_ARG="$2"; shift 2 ;;
        --backup-export) ACTION=backup-export; shift; if [[ -n "${1:-}" && "$1" != --* ]]; then ACTION_ARG="$1"; shift; fi ;;
        *) printf '此动作已退役或无效；使用 --help 查看新版命令。\n' >&2; exit 2 ;;
    esac
done
case "${ACTION}" in
    menu) menu_loop ;;
    configure-update-keys) configure_update_keys ;;
    install-manager-update-http) install_manager_update_http ;;
    manager-update-mirror-server) run_manager_update_mirror_server ;;
    manager-update-status) show_manager_update_http_status ;;
    upgrade-self) upgrade_self_from_download ;;
    migrate-retired-state) migrate_worker_retired_state ;;
    migrate-official) migrate_worker_official "${ACTION_ARG}" ;;
    backup-import) worker_backup_import "${ACTION_ARG}" ;;
    backup-export) worker_backup_export "${ACTION_ARG}" ;;
esac
