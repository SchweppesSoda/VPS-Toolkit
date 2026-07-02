usage() {
    printf '%s\n' \
        "PO0 Outbound IP Report 客户端（macOS）" \
        "" \
        "本脚本探测当前设备的公网出口 IPv4，并上报到 LAN Worker 的 self-report" \
        "接收服务。访问设备不直接连接 PO0。Self-report 放行 TTL 由 LAN Worker" \
        "接收端配置，不由客户端决定。" \
        "" \
        "用法:" \
        "  curl -fsSL ${DOWNLOAD_URL} | bash" \
        "  bash po0-outbound-ip-report-macos.sh --menu" \
        "  bash po0-outbound-ip-report-macos.sh --version" \
        "  bash po0-outbound-ip-report-macos.sh --upgrade-self" \
        "  curl -fsSL ${DOWNLOAD_URL} | bash -s -- --save-config --menu" \
        "  bash po0-outbound-ip-report-macos.sh --worker-url https://report.example.com/report --secret SECRET --save-config" \
        "  curl -fsSL ${DOWNLOAD_URL} | bash -s -- --worker-url https://report.example.com/report --secret SECRET --interval-seconds 3600 --install-launchd" \
        "" \
        "参数:" \
        "  --menu                打开交互菜单。" \
        "  --version             显示脚本版本、发布日期、当前路径和默认安装路径。" \
        "  --changelog           显示当前版本更新内容。" \
        "  --show-wifi-ssid      显示当前 Wi-Fi SSID 探测结果后退出。" \
        "  --diagnose-wifi-ssid  显示当前 Wi-Fi SSID 探测结果和 macOS 定位权限诊断后退出。" \
        "  --open-location-services 打开 macOS 定位服务设置后退出；只做跳转，不修改系统权限。" \
        "  --request-location-permission 尝试触发当前终端 App 的 macOS 定位权限弹窗后退出。" \
        "  --upgrade-self        从 GitHub Release 下载并更新本机脚本；菜单内更新会自动重开新版菜单。" \
        "  --config PATH         本地配置文件；优先级：--config / PO0_OUTBOUND_IP_REPORT_CONFIG / PO0_SELF_REPORT_CONFIG 或 SELF_REPORT_CONFIG / root 的 /etc/po0-outbound-ip-report/settings.env / XDG_CONFIG_HOME / ~/.config / ./po0-outbound-ip-report.env；旧 po0-self-report 配置仅作 fallback。" \
        "  --save-config         保存当前参数到本地配置文件；可与 --menu 组合为首次保存后打开菜单。" \
        "  --worker-url URL      LAN Worker self-report HTTPS 接收地址，例如 https://report.example.com/report；裸域名会自动补全。" \
        "  --allow-http          允许 http:// 上报；仅用于本地调试或临时旧环境。" \
        "  --notify              启用 macOS 原生通知；保存配置或安装 launchd 时会持久化。" \
        "  --no-notify           切换为静默模式；这是默认行为。" \
        "  --skip-wifi-ssid SSID 按当前 Wi-Fi SSID 跳过上报；可重复传入，精确大小写匹配。" \
        "  --skip-wifi-ssids LIST 按当前 Wi-Fi SSID 跳过上报；多个 SSID 用分号 ; 分隔。" \
        "  --clear-skip-wifi-ssids 清空已保存或环境传入的 Wi-Fi SSID 跳过列表。" \
        "  --force-report        即使当前 Wi-Fi SSID 命中跳过列表，也强制上报本次。" \
        "  --source-id ID        写入 PO0 client_ip 记录的来源 ID；默认由 hostname + machine-id/MAC 生成: ${SOURCE_ID}" \
        "  --identity ID         LAN Worker/PO0 日志里的设备或用户标签；默认使用设备名: ${IDENTITY}" \
        "  --secret SECRET       可选的 LAN Worker self-report 共享密钥。" \
        "  --ip-check-url URL    第一个公网 IPv4 探测地址。默认: ${IP_CHECK_URL}" \
        "  --ip-check-urls CSV   覆盖完整探测地址列表，多个 URL 用逗号分隔。" \
        "  --install-launchd [N] 安装 / 更新 macOS launchd 定时上报；不带 N 时默认 3600 秒。" \
        "  --install-cron [N]    兼容旧参数，等同 --install-launchd；N 为兼容分钟参数。" \
        "  --pause-schedule      暂停本脚本管理的定时上报；手动立即上报仍可用。" \
        "  --resume-schedule     恢复本脚本管理的定时上报。" \
        "  --schedule-status     查看本脚本管理的定时上报状态。" \
        "  --interval-seconds N  设置 launchd 上报间隔秒数，必须是 60 的倍数，默认 3600。" \
        "  --minutes N           兼容旧参数：设置定时上报间隔分钟数，范围 1-${MAX_CRON_MINUTES}。" \
        "" \
        "默认公网 IPv4 探测顺序:" \
        "  https://ip9.com.cn/get" \
        "  https://mail.163.com/fgw/mailsrv-ipdetail/detail" \
        "  https://api.live.bilibili.com/client/v1/Ip/getInfoNew" \
        "  https://ipservice.ws.126.net/locate/api/getLocByIp" \
        "  https://r.inews.qq.com/api/ip2city?otype=json" \
        "  https://data.video.iqiyi.com/v.f4v" \
        "  https://ip.apps.cntv.cn/whereis?client=json" \
        "  https://myip.ipip.net/json"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --menu)
                SHOW_MENU="1"
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
            --show-wifi-ssid)
                SHOW_WIFI_SSID="1"
                shift
                ;;
            --diagnose-wifi-ssid)
                SHOW_WIFI_SSID_DIAGNOSTIC="1"
                shift
                ;;
            --open-location-services|--open-location-settings|--open-location-services-settings)
                OPEN_LOCATION_SERVICES_SETTINGS="1"
                shift
                ;;
            --request-location-permission|--request-location-services|--setup-location-services)
                REQUEST_LOCATION_PERMISSION="1"
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
                WORKER_URL="${2:-}"
                shift 2
                ;;
            --allow-http)
                ALLOW_HTTP="1"
                shift
                ;;
            --notify)
                if [[ "${NOTIFY_ARG}" == "0" ]]; then
                    echo "--notify 与 --no-notify 不能同时使用。" >&2
                    exit 1
                fi
                NOTIFY_ARG="1"
                NOTIFY="1"
                shift
                ;;
            --no-notify)
                if [[ "${NOTIFY_ARG}" == "1" ]]; then
                    echo "--notify 与 --no-notify 不能同时使用。" >&2
                    exit 1
                fi
                NOTIFY_ARG="0"
                NOTIFY="0"
                shift
                ;;
            --skip-wifi-ssid)
                append_skip_wifi_ssid "${2:-}"
                shift 2
                ;;
            --skip-wifi-ssid=*)
                append_skip_wifi_ssid "${1#--skip-wifi-ssid=}"
                shift
                ;;
            --skip-wifi-ssids)
                SKIP_WIFI_SSIDS="$(normalize_wifi_ssid_skip_list "${2:-}")"
                shift 2
                ;;
            --skip-wifi-ssids=*)
                SKIP_WIFI_SSIDS="$(normalize_wifi_ssid_skip_list "${1#--skip-wifi-ssids=}")"
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
            --scheduled-run)
                SCHEDULED_RUN="1"
                shift
                ;;
            --source-id)
                SOURCE_ID="${2:-}"
                SOURCE_ID_EXPLICIT="1"
                shift 2
                ;;
            --identity)
                IDENTITY="${2:-}"
                IDENTITY_EXPLICIT="1"
                shift 2
                ;;
            --secret|--self-report-secret)
                SECRET="${2:-}"
                shift 2
                ;;
            --ip-check-url)
                IP_CHECK_URL="${2:-}"
                shift 2
                ;;
            --ip-check-urls)
                IP_CHECK_URLS="${2:-}"
                shift 2
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
            --install-cron|--install-launchd)
                INSTALL_CRON="1"
                if [[ "${2:-}" =~ ^[0-9]+$ ]]; then
                    CRON_MINUTES="${2:-}"
                    INTERVAL_SECONDS=""
                    shift 2
                else
                    shift
                fi
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
                echo "不再支持直接向 PO0 自上报。请使用 --worker-url 上报到 LAN Worker。" >&2
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
normalize_legacy_default_install_path
if [[ "${SHOW_VERSION}" != "1" && "${SHOW_CHANGELOG}" != "1" && "${SHOW_WIFI_SSID}" != "1" && "${SHOW_WIFI_SSID_DIAGNOSTIC}" != "1" && "${OPEN_LOCATION_SERVICES_SETTINGS}" != "1" && "${REQUEST_LOCATION_PERMISSION}" != "1" && "${UPGRADE_SELF}" != "1" ]]; then
    apply_interval_seconds_override || exit 1
fi
apply_device_defaults
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
elif [[ "${SHOW_WIFI_SSID}" == "1" ]]; then
    show_current_wifi_ssid_once
elif [[ "${SHOW_WIFI_SSID_DIAGNOSTIC}" == "1" ]]; then
    show_wifi_ssid_permission_help
elif [[ "${OPEN_LOCATION_SERVICES_SETTINGS}" == "1" ]]; then
    open_macos_location_services_settings
elif [[ "${REQUEST_LOCATION_PERMISSION}" == "1" ]]; then
    request_macos_location_permission
elif [[ "${UPGRADE_SELF}" == "1" ]]; then
    upgrade_self_from_download
elif [[ "${SAVE_CONFIG}" == "1" && "${SHOW_MENU}" == "1" ]]; then
    save_config_file || exit 1
    menu_loop
elif [[ "${SAVE_CONFIG}" == "1" ]]; then
    save_config_file
elif [[ "${PAUSE_SCHEDULE}" == "1" ]]; then
    set_schedule_paused "1"
elif [[ "${RESUME_SCHEDULE}" == "1" ]]; then
    set_schedule_paused "0"
elif [[ "${SHOW_SCHEDULE_STATUS}" == "1" ]]; then
    show_cron_status
elif [[ "${SHOW_MENU}" == "1" || ( "${HAD_ARGS}" == "0" && -r /dev/tty && -w /dev/tty ) ]]; then
    menu_loop
elif [[ "${INSTALL_CRON}" == "1" ]]; then
    install_cron
else
    report_once
fi
