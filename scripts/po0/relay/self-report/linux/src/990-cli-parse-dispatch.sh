usage() {
    printf '%s\n' 'PO0 官方防火墙客户端' \
        'Token、名称与槽位在本机权限 600 的配置文件保存；菜单可编辑。' \
        '--menu / --version / --changelog / --upgrade-self' \
        '--config PATH / --save-config / --run-once / --official-only' \
        '--official-status（只读）/ --clear-official-tokens' \
        '--skip-wifi-ssids LIST / --clear-skip-wifi-ssids / --force-report' \
        '--official-interval-seconds N / --install-cron / --refresh-schedules' \
        '--pause-schedule / --resume-schedule / --schedule-status / --remove-cron' \
        '--migrate-retired-state：先备份，清理本脚本的旧自建任务，保留官方设置。'
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --migrate-retired-state) MIGRATE_RETIRED_STATE=1; shift ;;
            --import-worker-official) [[ $# -ge 2 && -n "${2:-}" ]] || { printf "缺少迁移目录。\n" >&2; exit 2; }; IMPORT_WORKER_OFFICIAL="$2"; shift 2 ;;
            --activate-worker-official) [[ $# -ge 2 && -n "${2:-}" ]] || { printf "缺少迁移目录。\n" >&2; exit 2; }; ACTIVATE_WORKER_OFFICIAL="$2"; shift 2 ;;
            --menu)
                SHOW_MENU="1"
                shift
                ;;
            --run-once)
                RUN_ONCE="1"
                shift
                ;;
            --worker-only)
                printf '自建上报已退役。\n'; exit 0
                ;;
            --official-only)
                REPORT_MODE="official"
                shift
                ;;
            --version)
                SHOW_VERSION="1"
                shift
                ;;
            --changelog)
                SHOW_CHANGELOG="1"
                shift
                ;;
            --upgrade-self)
                UPGRADE_SELF="1"
                shift
                ;;
            --config)
                CONFIG_FILE="${2:-}"
                CONFIG_FILE_EXPLICIT="1"
                shift 2
                ;;
            --config=*)
                CONFIG_FILE="${1#--config=}"
                CONFIG_FILE_EXPLICIT="1"
                shift
                ;;
            --save-config)
                SAVE_CONFIG="1"
                shift
                ;;
            --worker-url|--lan-worker-url)
                printf '自建参数已退役，请使用官方配置。\n' >&2; exit 2
                ;;
            --allow-http)
                printf '自建参数已退役。\n' >&2; exit 2
                ;;
            --source-id)
                printf '自建参数已退役。\n' >&2; exit 2
                ;;
            --identity)
                printf '自建参数已退役。\n' >&2; exit 2
                ;;
            --secret|--self-report-secret)
                printf '自建参数已退役。\n' >&2; exit 2
                ;;
            --ip-check-url)
                IP_CHECK_URL="${2:-}"
                shift 2
                ;;
            --ip-check-urls)
                IP_CHECK_URLS="${2:-}"
                shift 2
                ;;
            --wan)
                printf '自建参数已退役。\n' >&2; exit 2
                ;;
            --wan=*)
                printf '自建参数已退役。\n' >&2; exit 2
                ;;
            --clear-wans)
                printf '自建参数已退役。\n' >&2; exit 2
                ;;
            --official-status)
                SHOW_OFFICIAL_STATUS="1"
                shift
                ;;
            --scheduled-run)
                SCHEDULED_RUN="1"
                shift
                ;;
            --clear-official-tokens|--official-disable)
                PO0_FIREWALL_TOKENS=""
                CLEAR_OFFICIAL_TOKENS="1"
                shift
                ;;
            --skip-wifi-ssid)
                append_wifi_ssid_skip_value "${2:-}"
                shift 2
                ;;
            --skip-wifi-ssid=*)
                append_wifi_ssid_skip_value "${1#--skip-wifi-ssid=}"
                shift
                ;;
            --skip-wifi-ssids)
                SKIP_WIFI_SSIDS="${2:-}"
                shift 2
                ;;
            --skip-wifi-ssids=*)
                SKIP_WIFI_SSIDS="${1#--skip-wifi-ssids=}"
                shift
                ;;
            --clear-skip-wifi-ssids)
                SKIP_WIFI_SSIDS=""
                shift
                ;;
            --force-report)
                FORCE_REPORT="1"
                shift
                ;;
            --install-path)
                INSTALL_PATH="${2:-}"
                INSTALL_PATH_EXPLICIT="1"
                shift 2
                ;;
            --minutes|--cron-minutes)
                CRON_MINUTES="${2:-}"
                INTERVAL_SECONDS=""
                shift 2
                ;;
            --interval-seconds)
                INTERVAL_SECONDS="${2:-}"
                shift 2
                ;;
            --install-cron)
                INSTALL_CRON="1"
                if [[ "${2:-}" =~ ^[0-9]+$ ]]; then
                    CRON_MINUTES="${2:-}"
                    INTERVAL_SECONDS=""
                    shift 2
                else
                    shift
                fi
                ;;
            --official-interval-seconds)
                [[ "${2:-}" =~ ^[0-9]+$ ]] && (( $2 >= 60 && $2 <= 86400 && $2 % 60 == 0 )) || { echo '官方周期无效。' >&2; exit 1; }
                OFFICIAL_INTERVAL_SECONDS="$2"; shift 2 ;;
            --timer-trigger)
                TIMER_TRIGGER="1"; SCHEDULED_RUN="1"; shift ;;
            --watch-network)
                WATCH_NETWORK=1; shift ;;
            --network-changed)
                NETWORK_CHANGED=1; SCHEDULED_RUN=1; shift ;;
            --schedule-channel)
                [[ $# -ge 2 ]] || { echo '缺少任务通道。' >&2; exit 1; }
                SCHEDULE_CHANNEL="$2"
                case "$SCHEDULE_CHANNEL" in all|worker|official) ;; *) echo '任务通道仅支持 worker / official / all。' >&2; exit 1 ;; esac
                shift 2
                ;;
            --remove-cron|--remove-launchd)
                REMOVE_SCHEDULES="1"
                shift
                ;;
            --refresh-schedules)
                REFRESH_SCHEDULES="1"
                shift
                ;;
            --pause-schedule)
                PAUSE_SCHEDULE="1"
                shift
                ;;
            --resume-schedule)
                RESUME_SCHEDULE="1"
                shift
                ;;
            --schedule-status)
                SHOW_SCHEDULE_STATUS="1"
                shift
                ;;
            --po0-host|--po0-script|--source-key|--domain|--token)
                echo "不再支持直接向 PO0 自上报。请使用官方防火墙配置。" >&2
                exit 1
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                echo "未知参数：$1" >&2
                usage >&2
                exit 1
                ;;
        esac
    done
}

prime_config_path_from_args "$@"
CONFIG_FILE="$(default_config_file)"
load_saved_config
apply_env_overrides
apply_device_defaults
parse_args "$@"
REPORT_MODE=official
OFFICIAL_ONLY=0
[[ "${OFFICIAL_STATUS_ONLY:-0}" == 1 ]] || OFFICIAL_ONLY=1
WORKER_ONLY=0
WORKER_URL=""
SECRET=""
WORKER_ENABLED=0
WORKER_AUTO_ENABLED=0
WORKER_TIMER_ENABLED=0
WORKER_NETWORK_ENABLED=0
WANS=""
CRON_MINUTES=10
INTERVAL_SECONDS=""
SCHEDULE_CHANNEL="${SCHEDULE_CHANNEL:-official}"
if [[ -n "${IMPORT_WORKER_OFFICIAL:-}" ]]; then import_worker_official "$IMPORT_WORKER_OFFICIAL"; exit $?; fi
if [[ -n "${ACTIVATE_WORKER_OFFICIAL:-}" ]]; then activate_imported_worker_official "$ACTIVATE_WORKER_OFFICIAL"; exit $?; fi
if [[ "${MIGRATE_RETIRED_STATE:-0}" == 1 ]]; then migrate_retired_state; exit $?; fi
WANS="$(normalize_wan_selection_list "${WANS:-}")"
SKIP_WIFI_SSIDS="$(normalize_wifi_ssid_skip_list "${SKIP_WIFI_SSIDS:-}")"
normalize_legacy_default_install_path
if [[ "${SHOW_VERSION}" != "1" && "${SHOW_CHANGELOG}" != "1" && "${UPGRADE_SELF}" != "1" ]]; then
    # Official-only/status operations must remain independent from the
    # optional LAN Worker lane. In particular, an old malformed Worker
    # interval or WAN setting must not block a read-only official
    # check or an official-only scheduled invocation.
    if [[ "${SHOW_OFFICIAL_STATUS}" != "1" && "${REPORT_MODE}" != "official" ]]; then
        validate_wan_selection || exit 1
        apply_interval_seconds_override || exit 1
    fi
fi
apply_device_defaults
if declare -F official_reset_internal_settings >/dev/null 2>&1; then
    official_reset_internal_settings
fi
CONFIG_FILE="$(default_config_file)"
legacy_reopen_menu="0"
if [[ "${SHOW_MENU}" == "1" || ( "${HAD_ARGS}" == "0" && -r /dev/tty && -w /dev/tty ) ]]; then
    legacy_reopen_menu="1"
fi
invoke_legacy_path_self_heal "${legacy_reopen_menu}" || true

if [[ "${SHOW_VERSION}" == "1" ]]; then
    show_version
elif [[ "${SHOW_CHANGELOG}" == "1" ]]; then
    show_changelog
elif [[ "${UPGRADE_SELF}" == "1" ]]; then
    upgrade_self_from_download
elif [[ "${SAVE_CONFIG}" == "1" && "${SHOW_MENU}" == "1" ]]; then
    save_config_file || exit 1
    menu_loop
elif [[ "${SAVE_CONFIG}" == "1" ]]; then
    save_config_file
elif [[ "${CLEAR_OFFICIAL_TOKENS}" == "1" ]]; then
    save_config_file || exit 1
elif [[ "${WATCH_NETWORK:-0}" == "1" ]]; then
    watch_network_changes
elif [[ "${REMOVE_SCHEDULES:-0}" == "1" ]]; then
    remove_cron "${SCHEDULE_CHANNEL:-all}"
elif [[ "${REFRESH_SCHEDULES:-0}" == "1" ]]; then
    refresh_channel_schedules "${SCHEDULE_CHANNEL:-all}"
elif [[ "${PAUSE_SCHEDULE}" == "1" ]]; then
    set_schedule_paused "1"
elif [[ "${RESUME_SCHEDULE}" == "1" ]]; then
    set_schedule_paused "0"
elif [[ "${SHOW_SCHEDULE_STATUS}" == "1" ]]; then
    show_cron_status
elif [[ "${SHOW_OFFICIAL_STATUS}" == "1" ]]; then
    official_status_once
elif [[ "${RUN_ONCE}" == "1" ]]; then
    report_once
elif [[ "${SHOW_MENU}" == "1" || ( "${HAD_ARGS}" == "0" && -r /dev/tty && -w /dev/tty ) ]]; then
    menu_loop
elif [[ "${INSTALL_CRON}" == "1" ]]; then
    install_cron
else
    report_once
fi
