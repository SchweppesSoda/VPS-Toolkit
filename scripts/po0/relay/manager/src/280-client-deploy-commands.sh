print_lan_worker_ddns_bootstrap_example() {
    local ddns_token="${1:-<SOURCE_TOKEN>}"
    local install_cmd
    printf -v install_cmd 'curl -fsSL %s | bash -s -- --bootstrap --po0-host <PO0_HOST> --po0-script %s --source-key <DDNS_SOURCE_KEY> --ddns-domain <DDNS_DOMAIN> --token %s --ddns-interval-seconds 3600 --install-cron' \
        "${LAN_WORKER_DOWNLOAD_URL}" "$(shell_quote "${MANAGER_INSTALL_PATH}")" "${ddns_token}"
    print_panel_section "LAN Worker DDNS 部署"
    print_panel_row "说明" "--ddns-interval-seconds 3600 设置 DDNS 默认 3600 秒上报；--install-cron 安装本机计划任务"
    print_panel_row "安装命令" "${install_cmd}"
}

print_lan_worker_resource_bootstrap_example() {
    local resource_token="${1:-<RESOURCE_TOKEN>}"
    local install_cmd probe_cmd
    printf -v install_cmd 'curl -fsSL %s | bash -s -- --bootstrap --po0-host <PO0_HOST> --po0-script %s --resource-token %s --install-cron 1440' \
        "${LAN_WORKER_DOWNLOAD_URL}" "$(shell_quote "${MANAGER_INSTALL_PATH}")" "${resource_token}"
    printf -v probe_cmd 'curl -fsSL %s | bash -s -- --probe --po0-host <PO0_HOST> --po0-script %s --resource-token %s' \
        "${LAN_WORKER_DOWNLOAD_URL}" "$(shell_quote "${MANAGER_INSTALL_PATH}")" "${resource_token}"
    print_panel_section "LAN Worker 资源任务部署"
    print_panel_row "说明" "资源创建周期在 PO0 端设置；--install-cron 1440 只安装 Worker 本机轮询器"
    print_panel_row "安装命令" "${install_cmd}"
    print_panel_row "探测命令" "${probe_cmd}"
}

deploy_token_values() {
    DEPLOY_DDNS_TOKEN="$(ddns_report_token_value 2>/dev/null || printf '<DDNS_TOKEN>')"
    DEPLOY_RESOURCE_TOKEN="$(resource_task_token_value 2>/dev/null || printf '<RESOURCE_TOKEN>')"
    DEPLOY_CLIENT_TOKEN="$(client_ip_report_token_value 2>/dev/null || printf '<CLIENT_REPORT_TOKEN>')"
    DEPLOY_SSH_TOKEN="$(ssh_report_token_value 2>/dev/null || printf '<SSH_REPORT_TOKEN>')"
    DEPLOY_WEBAUTH_TOKEN="$(webauth_report_token_value 2>/dev/null || printf '<WEBAUTH_TOKEN>')"
}

deploy_ensure_resource_token() {
    DEPLOY_RESOURCE_TOKEN="$(resource_task_token_value 2>/dev/null || printf '<RESOURCE_TOKEN>')"
}

do_show_client_deploy_index() {
    ensure_layout || return 1
    print_title "LAN Worker / 客户端 / Egern 分场景部署"
    print_panel_section "路径"
    print_panel_row "PO0 主控路径" "${MANAGER_INSTALL_PATH}"
    print_panel_row "LAN Worker 下载" "${LAN_WORKER_DOWNLOAD_URL}"
    print_panel_row "自上报 Linux/OpenWrt" "${OUTBOUND_IP_REPORTER_DOWNLOAD_URL}"
    print_panel_row "自上报 macOS" "${OUTBOUND_IP_REPORTER_MACOS_DOWNLOAD_URL}"
    print_panel_section "交互菜单"
    print_panel_row "1" "显示简短索引"
    print_panel_row "2" "PO0 主控脚本上传命令"
    print_panel_row "3" "LAN Worker 资源任务 Worker"
    print_panel_row "4" "LAN Worker DDNS 解析 Worker"
    print_panel_row "5" "LAN Worker self-report server"
    print_panel_row "6" "LAN Worker WebAuth worker"
    print_panel_row "7" "Outbound IP Report client"
    print_panel_row "8" "Egern SSH report"
    print_panel_section "CLI 示例"
    print_panel_row "资源任务" "bash nftables-relay-manager.sh --show-client-deploy-commands lan-resource"
    print_panel_row "DDNS" "bash nftables-relay-manager.sh --show-client-deploy-commands lan-ddns"
    print_panel_row "Egern" "bash nftables-relay-manager.sh --show-client-deploy-commands egern"
}

do_show_po0_manager_deploy_commands() {
    ensure_layout || return 1
    print_title "PO0 主控脚本上传"
    printf '安装路径 : %s\n' "${MANAGER_INSTALL_PATH}"
    echo ""
    echo "在 PO0 上执行下载并启动主控脚本；首次部署如需本地上传，可改用 scp 上传同一 Release asset："
    printf '  curl -fsSL %s -o %s\n' "${MANAGER_DOWNLOAD_URL}" "${MANAGER_INSTALL_PATH}"
    printf '  chmod +x %s && bash %s\n' "${MANAGER_INSTALL_PATH}" "${MANAGER_INSTALL_PATH}"
}

do_show_lan_worker_tokens() {
    ensure_layout || return 1
    deploy_token_values
    deploy_ensure_resource_token
    print_title "LAN Worker 专用 token"
    printf 'DDNS_TOKEN        : %s\n' "${DEPLOY_DDNS_TOKEN}"
    printf 'RESOURCE_TOKEN    : %s\n' "${DEPLOY_RESOURCE_TOKEN}"
    printf 'CLIENT_IP_TOKEN   : %s\n' "${DEPLOY_CLIENT_TOKEN}"
    printf 'WEBAUTH_TOKEN     : %s\n' "${DEPLOY_WEBAUTH_TOKEN}"
    printf 'SSH_REPORT_TOKEN  : %s\n' "${DEPLOY_SSH_TOKEN}"
    printf 'PO0_SCRIPT        : %s\n' "${MANAGER_INSTALL_PATH}"
    if [[ "${DEPLOY_RESOURCE_TOKEN}" == "<RESOURCE_TOKEN>" ]]; then
        warn "RESOURCE_TOKEN 尚未生成；请进入 [13] 内网资源更新任务 -> [7] 生成任务 Token。"
    fi
    echo ""
    echo "可直接复制的 LAN Worker token bundle："
    printf 'DDNS_TOKEN=%s\n' "${DEPLOY_DDNS_TOKEN}"
    printf 'RESOURCE_TOKEN=%s\n' "${DEPLOY_RESOURCE_TOKEN}"
    printf 'CLIENT_IP_TOKEN=%s\n' "${DEPLOY_CLIENT_TOKEN}"
    printf 'WEBAUTH_TOKEN=%s\n' "${DEPLOY_WEBAUTH_TOKEN}"
    printf 'PO0_SCRIPT=%s\n' "${MANAGER_INSTALL_PATH}"
    echo ""
    printf 'Token 文件：\n'
    printf '  DDNS       : %s\n' "${DDNS_REPORT_TOKEN_FILE}"
    printf '  Resource   : %s\n' "${RESOURCE_TASK_TOKEN_FILE}"
    printf '  Client IP  : %s\n' "${CLIENT_IP_REPORT_TOKEN_FILE}"
    printf '  WebAuth    : %s\n' "${WEBAUTH_REPORT_TOKEN_FILE}"
    printf '  SSH report : %s\n' "${SSH_REPORT_TOKEN_FILE}"
}

do_show_lan_resource_worker_commands() {
    local install_cmd probe_cmd
    ensure_layout || return 1
    deploy_token_values
    deploy_ensure_resource_token
    printf -v install_cmd 'curl -fsSL %s | bash -s -- --bootstrap --po0-host <PO0_HOST> --po0-script %s --resource-token %s --install-cron 1440' \
        "${LAN_WORKER_DOWNLOAD_URL}" "$(shell_quote "${MANAGER_INSTALL_PATH}")" "$(shell_quote "${DEPLOY_RESOURCE_TOKEN}")"
    printf -v probe_cmd 'curl -fsSL %s | bash -s -- --probe --po0-host <PO0_HOST> --po0-script %s --resource-token %s' \
        "${LAN_WORKER_DOWNLOAD_URL}" "$(shell_quote "${MANAGER_INSTALL_PATH}")" "$(shell_quote "${DEPLOY_RESOURCE_TOKEN}")"
    print_title "LAN Worker 资源任务 Worker"
    print_panel_section "职责"
    print_panel_row "执行位置" "LAN Worker 机器"
    print_panel_row "任务范围" "只负责轮询、领取和上传 iplist/ipdb 资源任务"
    print_panel_row "资源周期" "在 PO0 端设置：内网资源更新任务 -> 安装 / 更新 PO0 定时创建"
    print_panel_row "轮询器" "--install-cron 1440 只安装 Worker 本机轮询器，不决定资源更新频率"
    if [[ "${DEPLOY_RESOURCE_TOKEN}" == "<RESOURCE_TOKEN>" ]]; then
        print_panel_row "Token 状态" "未生成；请进入 [13] 内网资源更新任务 -> [7] 生成任务 Token"
    fi
    print_panel_section "命令"
    print_panel_row "安装命令" "${install_cmd}"
    print_panel_row "探测命令" "${probe_cmd}"
}

do_show_lan_ddns_worker_commands() {
    ensure_layout || return 1
    deploy_token_values
    print_title "LAN Worker DDNS 解析"
    echo "在 LAN Worker 机器上执行；LAN Worker 解析 DDNS 后通过 SSH 上报 PO0。"
    echo "--ddns-interval-seconds 3600 设置 DDNS 默认 3600 秒上报；--install-cron 安装本机计划任务，资源任务领取周期保持 LAN Worker 默认值。"
    echo ""
    printf '  curl -fsSL %s | bash -s -- --bootstrap --po0-host <PO0_HOST> --po0-script %s --source-key <DDNS_SOURCE_KEY> --ddns-domain <DDNS_DOMAIN> --token %s --ddns-interval-seconds 3600 --install-cron\n' \
        "${LAN_WORKER_DOWNLOAD_URL}" "$(shell_quote "${MANAGER_INSTALL_PATH}")" "$(shell_quote "${DEPLOY_DDNS_TOKEN}")"
    echo ""
    printf 'DDNS 目标行: source_key|ddns_domain|host|port|user|script|token|ssh_args\n'
    printf '  <DDNS_SOURCE_KEY>|<DDNS_DOMAIN>|<PO0_HOST>|22|root|%s|%s|\n' "${MANAGER_INSTALL_PATH}" "${DEPLOY_DDNS_TOKEN}"
    echo ""
    printf '临时合并多个目标：\n'
    printf '  po0-lan-client --run --ddns-targets "<TARGET1;TARGET2>"\n'
}

do_show_self_report_server_commands() {
    ensure_layout || return 1
    deploy_token_values
    print_title "LAN Worker self-report server"
    echo "推荐 HTTPS/Caddy 只在 LAN Worker 暴露 80/443；访问设备先报 LAN Worker，再由 LAN Worker 通过 SSH 上报 PO0。"
    echo ""
    printf '  curl -fsSL %s | bash -s -- --install-self\n' "${LAN_WORKER_DOWNLOAD_URL}"
    printf '  po0-lan-client --install-self-report-https --self-report-https-domain <SELF_REPORT_DOMAIN> --po0-host <PO0_HOST> --po0-script %s --self-report-source self-report --client-ip-token %s --self-report-secret <SELF_REPORT_SECRET>\n' \
        "$(shell_quote "${MANAGER_INSTALL_PATH}")" "$(shell_quote "${DEPLOY_CLIENT_TOKEN}")"
    echo ""
    printf 'Self-report / WebAuth 默认放行 TTL 均为 43200 秒（12 小时）。\n'
    printf 'Self-report PO0 目标行: source|host|port|user|script|token|ttl|ssh_args\n'
    printf '  self-report|<PO0_HOST>|22|root|%s|%s|43200|\n' "${MANAGER_INSTALL_PATH}" "${DEPLOY_CLIENT_TOKEN}"
    echo ""
    printf '合并多个目标行：\n'
    printf '  po0-lan-client --install-self-report-https --self-report-https-domain <SELF_REPORT_DOMAIN> --self-report-targets "<TARGET1;TARGET2>" --self-report-secret <SELF_REPORT_SECRET>\n'
}

do_show_self_report_client_commands() {
    ensure_layout || return 1
    print_title "PO0 Outbound IP Report client"
    echo "在访问设备上执行；检测设备当前出口 IPv4 后上报 LAN Worker，不直连 PO0。"
    echo ""
    echo "Linux / OpenWrt:"
    printf '  curl -fsSL %s | bash -s -- --worker-url https://<SELF_REPORT_DOMAIN>/report --source-id <CLIENT_ID> --secret <SELF_REPORT_SECRET> --interval-seconds 3600 --install-cron\n' \
        "${OUTBOUND_IP_REPORTER_DOWNLOAD_URL}"
    echo ""
    echo "macOS:"
    printf '  curl -fsSL %s | bash -s -- --worker-url https://<SELF_REPORT_DOMAIN>/report --source-id <CLIENT_ID> --secret <SELF_REPORT_SECRET> --interval-seconds 3600 --install-launchd\n' \
        "${OUTBOUND_IP_REPORTER_MACOS_DOWNLOAD_URL}"
    echo ""
    echo "Windows PowerShell:"
    printf "  \$script=\"\$env:TEMP\\po0-outbound-ip-report.ps1\"; irm -UseBasicParsing '%s' -OutFile \$script -TimeoutSec 120; powershell -ExecutionPolicy Bypass -File \$script -WorkerUrl 'https://<SELF_REPORT_DOMAIN>/report' -SourceId '<CLIENT_ID>' -Secret '<SELF_REPORT_SECRET>' -InstallTask -IntervalSeconds 3600\n" \
        "${OUTBOUND_IP_REPORTER_PS_DOWNLOAD_URL}"
}

do_show_webauth_worker_commands() {
    ensure_layout || return 1
    deploy_token_values
    print_title "LAN Worker WebAuth worker"
    echo "PO0 不开放 HTTP；建议在 LAN Worker 监听前面接 Cloudflare Access/Tunnel。"
    echo ""
    printf '  curl -fsSL %s | bash -s -- --install-self\n' "${LAN_WORKER_DOWNLOAD_URL}"
    printf '  po0-lan-client --webauth-server --listen 127.0.0.1:8787 --po0-host <PO0_HOST> --po0-script %s --webauth-source cf-access --webauth-token %s\n' \
        "$(shell_quote "${MANAGER_INSTALL_PATH}")" "$(shell_quote "${DEPLOY_WEBAUTH_TOKEN}")"
    echo ""
    printf 'WebAuth PO0 目标行: source|host|port|user|script|token|ttl|ssh_args\n'
    printf '  cf-access|<PO0_HOST>|22|root|%s|%s|43200|\n' "${MANAGER_INSTALL_PATH}" "${DEPLOY_WEBAUTH_TOKEN}"
    echo ""
    printf '合并多个目标行：\n'
    printf '  po0-lan-client --webauth-server --webauth-targets "<TARGET1;TARGET2>" --listen 127.0.0.1:8787\n'
}

do_show_egern_deploy_commands() {
    ensure_layout || return 1
    deploy_token_values
    print_title "Egern SSH report"
    echo "Egern 通过 SSH 直接向 PO0 上报当前出口 IPv4，归类为 ssh_report。"
    echo ""
    printf 'Module URL        : %s\n' "${EGERN_SSH_REPORT_MODULE_RAW_URL}"
    printf 'SSH_REPORT_TOKEN  : %s\n' "${DEPLOY_SSH_TOKEN}"
    printf 'PO0_SCRIPT        : %s\n' "${MANAGER_INSTALL_PATH}"
    echo ""
    printf 'SSH_REPORT_TARGETS row: source-id|host|port|user|script|token|identity|ttl\n'
    printf '  egern-po0|<PO0_HOST>|22|root|%s|%s|egern|43200\n' "${MANAGER_INSTALL_PATH}" "${DEPLOY_SSH_TOKEN}"
}

do_show_restricted_report_key_commands() {
    ensure_layout || return 1
    print_title "专用受限 SSH 上报 key"
    echo "在白名单菜单里安装专用受限 public key："
    echo "  管理源 IP 白名单 -> 安装 / 显示专用受限上报 key"
    echo ""
    echo "推荐 scope："
    echo "  Egern      : egern"
    echo "  LAN Worker : worker"
    echo ""
    echo "CLI:"
    printf '  bash %s --install-report-key worker "<PUBLIC_KEY_LINE>" root\n' "$(basename "$0")"
    printf '  bash %s --install-report-key egern "<PUBLIC_KEY_LINE>" root\n' "$(basename "$0")"
}

do_show_client_deploy_topic() {
    case "${1:-index}" in
        index|menu|"") do_show_client_deploy_index ;;
        po0|manager) do_show_po0_manager_deploy_commands ;;
        lan-resource|resource|worker-resource) do_show_lan_resource_worker_commands ;;
        lan-ddns|ddns|worker-ddns) do_show_lan_ddns_worker_commands ;;
        self-server|self-report-server|self-report) do_show_self_report_server_commands ;;
        self-client|client) do_show_self_report_client_commands ;;
        webauth|webauth-worker) do_show_webauth_worker_commands ;;
        egern|ssh-report) do_show_egern_deploy_commands ;;
        all|legacy) do_show_client_deploy_index ;;
        *)
            err "未知部署主题：${1}"
            do_show_client_deploy_index
            return 1
            ;;
    esac
}

do_manage_client_deploy_commands() {
    local choice
    while true; do
        menu_clear_screen
        print_title "LAN Worker / 客户端 / Egern 分场景部署"
        print_menu_section "主控与索引"
        print_menu_pair 1 "显示简短索引" 2 "PO0 主控脚本上传"
        print_menu_section "LAN Worker 侧"
        print_menu_pair 3 "资源任务 Worker" 4 "DDNS 解析 Worker"
        print_menu_pair 5 "Self-report 接收服务" 6 "WebAuth 接收服务"
        print_menu_section "访问端客户端"
        print_menu_pair 7 "Outbound IP Report 客户端" 8 "Egern SSH report"
        print_menu_section "退出"
        print_menu_item 0 "返回"
        print_menu_footer
        read_menu_choice_or_return choice "请选择操作 [0-8]: " || return
        case "${choice}" in
            1) do_show_client_deploy_index; pause_before_return ;;
            2) do_show_po0_manager_deploy_commands; pause_before_return ;;
            3) do_show_lan_resource_worker_commands; pause_before_return ;;
            4) do_show_lan_ddns_worker_commands; pause_before_return ;;
            5) do_show_self_report_server_commands; pause_before_return ;;
            6) do_show_webauth_worker_commands; pause_before_return ;;
            7) do_show_self_report_client_commands; pause_before_return ;;
            8) do_show_egern_deploy_commands; pause_before_return ;;
            0) return ;;
            *) err "无效选择。"; pause_before_return ;;
        esac
    done
}

do_show_client_deploy_commands() {
    do_show_client_deploy_topic "${1:-index}"
    return $?
}


do_worker_token_bundle() {
    local ensure_resource="${1:-}"
    local ddns_token resource_token client_token ssh_token webauth_token
    ensure_layout || return 1
    ddns_token="$(ddns_report_token_value)" || return 1
    client_token="$(client_ip_report_token_value)" || return 1
    ssh_token="$(ssh_report_token_value)" || return 1
    webauth_token="$(webauth_report_token_value)" || return 1
    if [[ "${ensure_resource}" == "--ensure-resource-token" ]]; then
        resource_token="$(resource_task_token_value 2>/dev/null || generate_resource_task_token)" || return 1
    else
        resource_token="$(resource_task_token_value 2>/dev/null || true)"
    fi
    printf 'DDNS_TOKEN=%s\n' "${ddns_token}"
    printf 'RESOURCE_TOKEN=%s\n' "${resource_token}"
    printf 'CLIENT_IP_TOKEN=%s\n' "${client_token}"
    printf 'SSH_REPORT_TOKEN=%s\n' "${ssh_token}"
    printf 'WEBAUTH_TOKEN=%s\n' "${webauth_token}"
    printf 'PO0_SCRIPT=%s\n' "${MANAGER_INSTALL_PATH}"
}

do_manage_automation_mode() {
    local choice
    ensure_layout || return
    load_settings 1
    while true; do
        menu_clear_screen
        print_title "自动白名单安全模式"
        printf '当前模式 : %s\n' "${AUTOMATION_MODE}"
        print_menu_item 1 "regular：自动来源新 IP 可直接进入白名单"
        print_menu_item 2 "attack：新自动 IP 只进入待审核，不直接放行"
        print_menu_item 3 "查看自动来源待审核 IP"
        print_menu_item 0 "返回"
        print_menu_footer
        read_menu_choice_or_return choice "请选择操作 [0-3]: " || return
        case "${choice}" in
            1) set_automation_mode regular; pause_before_return ;;
            2) set_automation_mode attack; pause_before_return ;;
            3) do_list_pending_auto_sources; pause_before_return ;;
            0) return ;;
            *) err "无效选择。"; pause_before_return ;;
        esac
        load_settings 1
    done
}

do_show_ddns_report_token() {
    local token
    ensure_layout || return 1
    token="$(ddns_report_token_value)" || return 1
    print_title "DDNS 外部上报 Token"
    printf 'Token 文件 : %s\n' "${DDNS_REPORT_TOKEN_FILE}"
    printf 'Token      : %s\n' "${token}"
    echo ""
    echo "SSH 上报示例："
    printf '  bash %s --ddns-report home 1.2.3.4 %s\n' "$(basename "$0")" "${token}"
    echo ""
    print_lan_worker_ddns_bootstrap_example "${token}" "<RESOURCE_TOKEN>"
    echo ""
    echo "说明：如果通过 SSH 只允许可信用户执行，也可以不创建/不使用 token；一旦 token 文件存在，上报命令必须携带正确 token。"
}
