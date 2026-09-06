usage() {
    printf '%s\n' \
        "PO0 Outbound IP Report 客户端（Linux/OpenWrt）" \
        "" \
        "本脚本探测当前设备的公网出口 IPv4，并上报到 LAN Worker 的 self-report" \
        "接收服务。访问设备不直接连接 PO0。放行时长由 LAN Worker" \
        "接收端配置，不由客户端决定。" \
        "" \
        "用法:" \
        "  curl -fsSL ${DOWNLOAD_URL} | bash" \
        "  bash po0-outbound-ip-report.sh --menu" \
        "  bash po0-outbound-ip-report.sh --version" \
        "  bash po0-outbound-ip-report.sh --run-once" \
        "  bash po0-outbound-ip-report.sh --upgrade-self" \
        "  curl -fsSL ${DOWNLOAD_URL} | bash -s -- --save-config --menu" \
        "  bash po0-outbound-ip-report.sh --worker-url https://report.example.com/report --secret SECRET --save-config" \
        "  curl -fsSL ${DOWNLOAD_URL} | bash -s -- --worker-url https://report.example.com/report --secret SECRET --interval-seconds 3600 --install-cron" \
        "" \
        "参数:" \
        "  --menu                打开交互菜单。" \
        "  --run-once            非交互执行一次上报；供 procd、cron 和其它调度器使用。" \
        "  --version             显示脚本版本、发布日期、当前路径和默认安装路径。" \
        "  --changelog           显示当前版本更新内容。" \
        "  --upgrade-self        从 GitHub Release 下载并更新本机脚本；菜单内更新会自动重开新版菜单。" \
        "  --config PATH         本地配置文件；优先级：--config / PO0_OUTBOUND_IP_REPORT_CONFIG / PO0_SELF_REPORT_CONFIG 或 SELF_REPORT_CONFIG / root 的 /etc/po0-outbound-ip-report/settings.env / XDG_CONFIG_HOME / ~/.config / ./po0-outbound-ip-report.env；旧 po0-self-report 配置仅作 fallback。" \
        "  --save-config         保存当前参数到本地配置文件，不安装 cron；可与 --menu 组合为首次保存后打开菜单。" \
        "  --worker-url URL      LAN Worker self-report HTTPS 接收地址，例如 https://report.example.com/report；裸域名会自动补全。" \
        "  --allow-http          允许 http:// 上报；仅用于本地调试或临时旧环境。" \
        "  --source-id ID        写入 PO0 client_ip 记录的来源 ID；默认由 hostname + machine-id/MAC 生成: ${SOURCE_ID}" \
        "  --identity ID         LAN Worker/PO0 日志里的设备或用户标签；默认使用设备名: ${IDENTITY}" \
        "  --secret SECRET       可选的 LAN Worker self-report 共享密钥。" \
        "  --ip-check-url URL    第一个公网 IPv4 探测地址。默认: ${IP_CHECK_URL}" \
        "  --ip-check-urls CSV   覆盖完整探测地址列表，多个 URL 用逗号分隔。" \
        "  --wan NAME            OpenWrt 逻辑 WAN 接口；可重复，分别绑定接口探测和上报。" \
        "  --wan all             上报全部已启用的 mwan3 WAN；每条 WAN 使用独立来源 ID。" \
        "  --clear-wans          清空 WAN 选择，恢复按默认路由只上报一个出口。" \
        "  普通 Linux 官方 token 通过权限 600 的 settings.env 中 PO0_FIREWALL_TOKENS 配置，格式为 token@0..4，可用逗号分隔；不从命令行读取。" \
        "  普通 Linux 官方通道固定使用本机默认出口；指定 WAN / 多 WAN 的官方上报由主 OpenWrt 官方绑定配置负责。" \
        "  --official-status      只读检查 PO0 官方防火墙；绝不执行加白。" \
        "  --clear-official-tokens 清空并保存官方 token，关闭该通道。" \
        "  --worker-only       只执行现有 LAN Worker 通道（供独立调度使用）。" \
        "  --official-only     只执行官方防火墙通道（供独立调度使用）。" \
        "  --skip-wifi-ssid SSID 按 Wi-Fi SSID 跳过上报；可重复，匹配大小写敏感。" \
        "  --skip-wifi-ssids LIST 覆盖跳过上报的 Wi-Fi SSID 列表，多个 SSID 用分号 ; 分隔。" \
        "  --clear-skip-wifi-ssids 清空已保存/已加载的 Wi-Fi SSID 跳过列表。" \
        "  --force-report        忽略 Wi-Fi SSID 跳过列表，强制执行本次上报。" \
        "  --install-cron [N]    安装 / 更新 cron；N 为兼容分钟参数，不带 N 时默认 3600 秒。" \
        "  --pause-schedule      暂停本脚本管理的定时上报；手动立即上报仍可用。" \
        "  --resume-schedule     恢复本脚本管理的定时上报。" \
        "  --schedule-status     查看本脚本管理的定时上报状态。" \
        "  --interval-seconds N  设置 cron 上报间隔秒数，必须是 60 的倍数，默认 3600。" \
        "  --minutes N           兼容旧参数：设置 cron 上报间隔分钟数，范围 1-${MAX_CRON_MINUTES}。" \
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
            --run-once)
                RUN_ONCE="1"
                shift
                ;;
            --worker-only)
                REPORT_MODE="worker"
                shift
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
                WORKER_URL="${2:-}"
                shift 2
                ;;
            --allow-http)
                ALLOW_HTTP="1"
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
            --wan)
                append_wan_selection_value "${2:-}"
                shift 2
                ;;
            --wan=*)
                append_wan_selection_value "${1#--wan=}"
                shift
                ;;
            --clear-wans)
                WANS=""
                WANS_CLI_SEEN="1"
                shift
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
