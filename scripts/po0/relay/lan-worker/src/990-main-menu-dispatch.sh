menu_loop() {
    local choice
    while true; do
        menu_clear_screen
        print_dashboard
        print_menu_section "资源任务"
        print_menu_pair 1 "资源统计" 2 "PO0 资源更新计划"
        print_menu_pair 3 "立即领取并执行资源任务" 4 "清理资源统计"

        print_menu_section "DDNS 解析上报"
        print_menu_pair 5 "上报目标与 DDNS 统计" 6 "立即执行 DDNS 上报"
        print_menu_pair 7 "DDNS 目标 / 上报计划" 8 "清空 DDNS 统计"

        print_menu_section "Self-report 自上报"
        print_menu_pair 9 "Self-report 连通性检查" 10 "Self-report 配置 / 启动"

        print_menu_section "WebAuth 放行"
        print_menu_pair 11 "WebAuth 连通性检查" 12 "启动 WebAuth 服务"
        print_menu_item 13 "WebAuth / Cloudflare Access 配置提示"

        print_menu_section "PO0 目标、SSH、Token 与 TTL"
        print_menu_pair 14 "添加 PO0 目标" 15 "编辑 PO0 目标"
        print_menu_pair 16 "SSH 私钥 / 参数" 17 "目标 Token"
        print_menu_pair 18 "Self-report / WebAuth 白名单有效期（TTL）" 19 "启用 / 停用目标"
        print_menu_item 20 "删除 PO0 目标"

        print_menu_section "全局操作"
        print_menu_item 21 "执行全部任务"

        print_menu_section "本机官方防火墙"
        print_menu_pair 29 "配置官方防火墙 token" 30 "只读查看官方防火墙状态"

        print_menu_section "维护"
        print_menu_pair 22 "安装 / 更新本机轮询器" 23 "删除本机轮询器"
        print_menu_pair 24 "查看本机轮询器状态" 25 "查看脚本版本 / 本机状态"
        print_menu_pair 26 "从 GitHub 更新脚本" 27 "备份 / 导入恢复"
        print_menu_item 28 "PO0 manager 更新镜像"

        print_menu_section "退出"
        print_menu_item 0 "退出"
        print_menu_footer
        read_menu_choice_or_return choice "请选择操作 [0-30]: " || return 0
        case "${choice}" in
            1) list_resource_stats; pause_before_return ;;
            2) show_remote_resource_task_cron_status; pause_before_return ;;
            3) run_resource_targets; pause_before_return ;;
            4) clear_resource_stats_interactive; pause_before_return ;;
            5) list_targets; pause_before_return ;;
            6) run_config_targets; pause_before_return ;;
            7) manage_ddns_settings_interactive ;;
            8) clear_stats_interactive; pause_before_return ;;
            9) probe_self_report_target; pause_before_return ;;
            10) manage_self_report_server_interactive ;;
            11) probe_webauth_target; pause_before_return ;;
            12) run_webauth_server ;;
            13) show_webauth_cloudflare_guide; pause_before_return ;;
            14) add_target_interactive; pause_before_return ;;
            15) edit_target_interactive; pause_before_return ;;
            16) manage_target_ssh_interactive; [[ "$?" -eq 2 ]] || pause_before_return ;;
            17) manage_target_tokens_interactive; pause_before_return ;;
            18) manage_target_report_ttl_interactive; pause_before_return ;;
            19) toggle_target_interactive; pause_before_return ;;
            20) delete_target_interactive; pause_before_return ;;
            21) run_all_client_jobs; pause_before_return ;;
            29) official_configure_interactive; pause_before_return ;;
            30) official_status_once; pause_before_return ;;
            22) install_cron_interactive; pause_before_return ;;
            23) remove_cron_interactive; pause_before_return ;;
            24) show_cron_status; pause_before_return ;;
            25) show_local_script_status; pause_before_return ;;
            26) upgrade_self_from_download --reopen-menu || pause_before_return ;;
            27) backup_restore_interactive; pause_before_return ;;
            28) manage_manager_update_http_interactive ;;
            0) return 0 ;;
            "") ;;
            *) printf '无效选择。\n' >&2; pause_before_return ;;
        esac
    done
}

prime_config_paths_from_args "$@"
refresh_settings_file
load_local_settings || {
    printf '加载本机设置失败：%s\n' "${SETTINGS_FILE}" >&2
    exit 1
}

ORIGINAL_ARGC="$#"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)
            require_arg_value "$@"
            CONFIG_FILE="${2:-}"
            refresh_settings_file
            shift 2
            ;;
        --settings-file)
            require_arg_value "$@"
            SETTINGS_FILE="${2:-}"
            shift 2
            ;;
        --po0-host)
            require_arg_value "$@"
            PO0_HOST="${2:-}"
            shift 2
            ;;
        --po0-port)
            require_arg_value "$@"
            PO0_PORT="${2:-}"
            shift 2
            ;;
        --po0-user)
            require_arg_value "$@"
            PO0_USER="${2:-}"
            shift 2
            ;;
        --po0-script)
            require_arg_value "$@"
            PO0_SCRIPT="${2:-}"
            shift 2
            ;;
        --source-key|--source)
            require_arg_value "$@"
            DDNS_DOMAIN="${2:-}"
            shift 2
            ;;
        --ddns-domain|--resolve-domain)
            require_arg_value "$@"
            DDNS_RESOLVE_DOMAIN="${2:-}"
            [[ -n "${REPORT_MODE}" ]] || REPORT_MODE="ddns"
            shift 2
            ;;
        --ddns-targets)
            require_arg_value "$@"
            DDNS_TARGETS="${2:-}"
            shift 2
            ;;
        --ddns-interval-seconds)
            require_arg_value "$@"
            DDNS_CRON_MINUTES="$(normalize_interval_seconds_to_minutes "${2:-}" "${DDNS_CRON_MAX_MINUTES}")" || {
                printf 'DDNS 上报间隔秒数无效：请输入 60-%s 且为 60 倍数的整数。\n' "$((DDNS_CRON_MAX_MINUTES * 60))" >&2
                exit 1
            }
            DDNS_INTERVAL_SECONDS_EXPLICIT="1"
            shift 2
            ;;
        --report-mode)
            require_arg_value "$@"
            REPORT_MODE="${2:-}"
            shift 2
            ;;
        --domain)
            require_arg_value "$@"
            DDNS_DOMAIN="${2:-}"
            [[ -n "${DDNS_RESOLVE_DOMAIN}" ]] || DDNS_RESOLVE_DOMAIN="${2:-}"
            [[ -n "${REPORT_MODE}" ]] || REPORT_MODE="ddns"
            shift 2
            ;;
        --key)
            require_arg_value "$@"
            REPORT_KEY="${2:-}"
            shift 2
            ;;
        --name)
            require_arg_value "$@"
            REPORT_KEY="${2:-}"
            shift 2
            ;;
        --token)
            require_arg_value "$@"
            DDNS_TOKEN="${2:-}"
            shift 2
            ;;
        --resource-token)
            require_arg_value "$@"
            RESOURCE_TOKEN="${2:-}"
            shift 2
            ;;
        --ssh-extra-args)
            require_arg_value "$@"
            SSH_EXTRA_ARGS="${2:-}"
            shift 2
            ;;
        --install-path)
            require_arg_value "$@"
            INSTALL_PATH="${2:-}"
            shift 2
            ;;
        --worker-id)
            require_arg_value "$@"
            WORKER_ID="${2:-}"
            shift 2
            ;;
        --listen)
            require_arg_value "$@"
            WEBAUTH_LISTEN="${2:-}"
            shift 2
            ;;
        --webauth-source)
            require_arg_value "$@"
            WEBAUTH_SOURCE="${2:-}"
            shift 2
            ;;
        --webauth-token)
            require_arg_value "$@"
            WEBAUTH_TOKEN="${2:-}"
            shift 2
            ;;
        --webauth-ttl)
            require_arg_value "$@"
            WEBAUTH_TTL_SECONDS="${2:-}"
            shift 2
            ;;
        --webauth-targets)
            require_arg_value "$@"
            WEBAUTH_TARGETS="${2:-}"
            shift 2
            ;;
        --self-report-listen)
            require_arg_value "$@"
            SELF_REPORT_LISTEN="${2:-}"
            shift 2
            ;;
        --self-report-source)
            require_arg_value "$@"
            SELF_REPORT_SOURCE="${2:-}"
            shift 2
            ;;
        --self-report-secret)
            require_arg_value "$@"
            # Keep an already loaded secret when legacy automation expands an
            # unset variable to an explicit empty argument. A genuinely new
            # install remains empty here and generates its secret at install.
            if [[ -n "${2:-}" || -z "${SELF_REPORT_SECRET}" ]]; then
                SELF_REPORT_SECRET="${2:-}"
            fi
            shift 2
            ;;
        --client-ip-token|--self-report-token)
            require_arg_value "$@"
            CLIENT_IP_TOKEN="${2:-}"
            shift 2
            ;;
        --self-report-ttl)
            require_arg_value "$@"
            SELF_REPORT_TTL_SECONDS="${2:-}"
            shift 2
            ;;
        --self-report-targets)
            require_arg_value "$@"
            SELF_REPORT_TARGETS="${2:-}"
            shift 2
            ;;
        --self-report-https-domain)
            require_arg_value "$@"
            SELF_REPORT_HTTPS_DOMAIN="${2:-}"
            shift 2
            ;;
        --manager-update-listen)
            require_arg_value "$@"
            MANAGER_UPDATE_LISTEN="${2:-}"
            shift 2
            ;;
        --manager-update-domain|--manager-update-host)
            require_arg_value "$@"
            MANAGER_UPDATE_DOMAIN="${2:-}"
            shift 2
            ;;
        --manager-update-backend)
            require_arg_value "$@"
            MANAGER_UPDATE_BACKEND="${2:-}"
            shift 2
            ;;
        --manager-update-caddy-snippet)
            require_arg_value "$@"
            MANAGER_UPDATE_CADDY_SNIPPET="${2:-}"
            shift 2
            ;;
        --label)
            require_arg_value "$@"
            BOOTSTRAP_LABEL="${2:-}"
            shift 2
            ;;
        --menu)
            ACTION="menu"
            shift
            ;;
        --wizard)
            ACTION="wizard"
            shift
            ;;
        --probe)
            ACTION="probe"
            shift
            ;;
        --bootstrap)
            ACTION="bootstrap"
            shift
            ;;
        --list)
            ACTION="list"
            shift
            ;;
        --add)
            ACTION="add"
            shift
            ;;
        --delete)
            ACTION="delete"
            shift
            ;;
        --toggle)
            ACTION="toggle"
            shift
            ;;
        --run)
            ACTION="run"
            shift
            ;;
        --run-ddns)
            ACTION="run-ddns"
            shift
            ;;
        --run-resource)
            ACTION="run-resource"
            shift
            ;;
        --run-official-firewall)
            ACTION="official-firewall"
            shift
            ;;
        --official-firewall-status)
            ACTION="official-firewall-status"
            shift
            ;;
        --official-preflight-only)
            ACTION="official-preflight"
            shift
            ;;
        --scheduled-run)
            SCHEDULED_RUN="1"
            shift
            ;;
        --force|--force-report)
            FORCE_REPORT="1"
            shift
            ;;
        --webauth-server)
            ACTION="webauth-server"
            shift
            ;;
        --self-report-server)
            ACTION="self-report-server"
            shift
            ;;
        --self-report-probe)
            ACTION="self-report-probe"
            shift
            ;;
        --install-self-report-service)
            ACTION="install-self-report-service"
            shift
            ;;
        --install-self-report-https)
            ACTION="install-self-report-https"
            shift
            ;;
        --manager-update-mirror-server)
            ACTION="manager-update-mirror-server"
            shift
            ;;
        --install-manager-update-http)
            ACTION="install-manager-update-http"
            shift
            ;;
        --install-webauth-service)
            ACTION="install-webauth-service"
            shift
            ;;
        --webauth-probe)
            ACTION="webauth-probe"
            shift
            ;;
        --install-self)
            ACTION="install-self"
            shift
            ;;
        --upgrade-self)
            ACTION="upgrade-self"
            shift
            ;;
        --backup-export)
            ACTION="backup-export"
            if [[ -n "${2:-}" && "${2:-}" != --* ]]; then
                BACKUP_ARCHIVE="${2:-}"
                shift 2
            else
                shift
            fi
            ;;
        --backup-import)
            ACTION="backup-import"
            require_arg_value "$@"
            BACKUP_ARCHIVE="${2:-}"
            shift 2
            ;;
        --restore-cron)
            RESTORE_CRON="1"
            shift
            ;;
        --restore-systemd)
            RESTORE_SYSTEMD="1"
            shift
            ;;
        --restore-caddy)
            RESTORE_CADDY="1"
            shift
            ;;
        --restore-all)
            RESTORE_CRON="1"
            RESTORE_SYSTEMD="1"
            RESTORE_CADDY="1"
            shift
            ;;
        --dry-run)
            RESTORE_DRY_RUN="1"
            shift
            ;;
        --version)
            ACTION="version"
            shift
            ;;
        --install-cron)
            INSTALL_CRON="1"
            if [[ -n "${2:-}" && "${2:-}" =~ ^[0-9]+$ ]]; then
                CRON_MINUTES="${2:-}"
                [[ "${DDNS_INTERVAL_SECONDS_EXPLICIT}" == "1" ]] || DDNS_CRON_MINUTES="${CRON_MINUTES}"
                RESOURCE_CRON_MINUTES="${CRON_MINUTES}"
                shift 2
            else
                shift
            fi
            if [[ -z "${ACTION}" ]]; then
                ACTION="install-cron"
            fi
            ;;
        --no-cron)
            INSTALL_CRON="0"
            shift
            ;;
        --no-run)
            BOOTSTRAP_RUN="0"
            shift
            ;;
        --no-probe)
            BOOTSTRAP_PROBE="0"
            shift
            ;;
        --print-cron)
            ACTION="print-cron"
            if [[ -n "${2:-}" && "${2:-}" =~ ^[0-9]+$ ]]; then
                CRON_MINUTES="${2:-}"
                [[ "${DDNS_INTERVAL_SECONDS_EXPLICIT}" == "1" ]] || DDNS_CRON_MINUTES="${CRON_MINUTES}"
                RESOURCE_CRON_MINUTES="${CRON_MINUTES}"
                shift 2
            else
                shift
            fi
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            printf '未知参数：%s\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

normalize_report_ttl_settings

case "${ACTION}" in
    wizard)
        po0_lan_wizard
        exit $?
        ;;
    menu)
        menu_loop
        exit $?
        ;;
    probe)
        probe_worker_target
        exit $?
        ;;
    bootstrap)
        bootstrap_worker
        exit $?
        ;;
    list)
        list_targets
        exit $?
        ;;
    add)
        add_target_interactive
        exit $?
        ;;
    delete)
        delete_target_interactive
        exit $?
        ;;
    toggle)
        toggle_target_interactive
        exit $?
        ;;
    run)
        run_all_client_jobs
        exit $?
        ;;
    run-ddns)
        run_config_targets
        exit $?
        ;;
    run-resource)
        run_resource_targets
        exit $?
        ;;
    official-firewall)
        official_report_once
        exit $?
        ;;
    official-firewall-status)
        official_status_once
        exit $?
        ;;
    official-preflight)
        official_report_once
        exit $?
        ;;
    webauth-server)
        run_webauth_server
        exit $?
        ;;
    self-report-server)
        run_self_report_server
        exit $?
        ;;
    install-webauth-service)
        install_webauth_service
        exit $?
        ;;
    install-self-report-service)
        install_self_report_service
        exit $?
        ;;
    install-self-report-https)
        install_self_report_https
        exit $?
        ;;
    manager-update-mirror-server)
        run_manager_update_mirror_server
        exit $?
        ;;
    install-manager-update-http)
        install_manager_update_http
        exit $?
        ;;
    webauth-probe)
        probe_webauth_target
        exit $?
        ;;
    self-report-probe)
        probe_self_report_target
        exit $?
        ;;
    install-self)
        install_self
        exit $?
        ;;
    upgrade-self)
        upgrade_self_from_download
        exit $?
        ;;
    backup-export)
        lan_backup_export "${BACKUP_ARCHIVE}"
        exit $?
        ;;
    backup-import)
        lan_backup_import "${BACKUP_ARCHIVE}"
        exit $?
        ;;
    version)
        show_local_script_status
        exit $?
        ;;
    install-cron)
        script_path="$(ensure_persistent_script)" || exit 1
        install_worker_crons "${DDNS_CRON_MINUTES}" "${RESOURCE_CRON_MINUTES}" "${script_path}"
        exit $?
        ;;
    print-cron)
        print_cron_example "${DDNS_CRON_MINUTES}" "${RESOURCE_CRON_MINUTES}"
        exit $?
        ;;
esac

if [[ "${ORIGINAL_ARGC}" == "0" ]]; then
    po0_lan_wizard
    exit $?
fi

if [[ -z "${PO0_HOST}" && -z "${DDNS_DOMAIN}" ]]; then
    menu_loop
    exit $?
fi

if [[ -z "${DDNS_DOMAIN}" ]]; then
    printf 'DDNS 解析上报需要 --source-key/--domain；只做资源任务请使用 --bootstrap 或 --run。\n' >&2
    exit 1
fi

if [[ -z "${DDNS_RESOLVE_DOMAIN}" ]]; then
    printf 'DDNS 解析上报需要 --ddns-domain；旧参数 --domain 会同时作为 source key 和 DDNS 域名。\n' >&2
    exit 1
fi
report_once "${DDNS_DOMAIN}" "${REPORT_KEY:-${DDNS_DOMAIN}}" "${DDNS_RESOLVE_DOMAIN}" "${PO0_HOST}" "${PO0_PORT}" "${PO0_USER}" "${PO0_SCRIPT}" "${DDNS_TOKEN}" "${SSH_EXTRA_ARGS}"
