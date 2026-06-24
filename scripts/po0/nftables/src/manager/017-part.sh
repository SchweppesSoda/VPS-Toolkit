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
    print_panel_row "7" "Self-report client"
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
    echo "在本地机器执行上传，然后登录 PO0 启动主控脚本："
    printf '  scp scripts/po0/nftables/nftables-relay-manager.sh root@<PO0_HOST>:%s\n' "${MANAGER_INSTALL_PATH}"
    printf '  ssh root@<PO0_HOST> "chmod +x %s && bash %s"\n' "${MANAGER_INSTALL_PATH}" "${MANAGER_INSTALL_PATH}"
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
    print_title "Self-report client"
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
    printf 'SSH_REPORT_TARGETS row: source_id|host|port|user|script|token|identity|ttl\n'
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
        print_menu_pair 7 "Self-report 客户端" 8 "Egern SSH report"
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

show_ddns_allowlist_sources() {
    local line idx=1 status
    ensure_allowlist_sources_file || return 1
    if [[ "$(allowlist_sources_count)" == "0" ]]; then
        echo "  (尚未添加 DDNS 来源)"
        return 0
    fi
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_source_line "${line}" || continue
        if [[ "${ALLOWLIST_SOURCE_ENABLED}" == "1" ]]; then
            status="启用"
        else
            status="停用"
        fi
        printf '  %2d) %-4s %-16s 域名=%s TTL=%ss 上次=%s 结果=%s\n' \
            "${idx}" "${status}" "${ALLOWLIST_SOURCE_NAME}" "${ALLOWLIST_SOURCE_VALUE}" \
            "${ALLOWLIST_SOURCE_TTL_SECONDS}" "${ALLOWLIST_SOURCE_LAST_RESOLVED_AT:-从未}" \
            "${ALLOWLIST_SOURCE_LAST_RESULT:-无}"
        print_ddns_report_stats_line "${ALLOWLIST_SOURCE_VALUE}"
        ((idx++))
    done < "${ALLOWLIST_SOURCES_FILE}"
}

select_ddns_allowlist_source() {
    local line choice idx=1
    local -a sources=()
    ensure_allowlist_sources_file || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_source_line "${line}" || continue
        sources+=("${PARSED_ALLOWLIST_SOURCE}")
    done < "${ALLOWLIST_SOURCES_FILE}"
    [[ ${#sources[@]} -gt 0 ]] || {
        err "当前没有 DDNS 来源。"
        return 1
    }
    show_ddns_allowlist_sources
    choice="$(read_prompt "请选择 DDNS 来源 [1-${#sources[@]}]: ")" || return 1
    [[ "${choice}" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= ${#sources[@]} )) || return 1
    parse_allowlist_source_line "${sources[$((choice - 1))]}"
}

append_ddns_allowlist_source() {
    local name="$1"
    local domain="$2"
    local ttl="$3"
    local enabled="$4"
    local line
    name="$(sanitize_allowlist_source_text "${name}")"
    domain="$(sanitize_allowlist_source_text "${domain}")"
    ttl="$(normalize_source_ttl_seconds "${ttl}")"
    [[ "${enabled}" == "0" || "${enabled}" == "1" ]] || enabled="1"
    [[ -n "${name}" ]] || name="${domain}"
    validate_ddns_domain "${domain}" || return 1
    ensure_allowlist_sources_file || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_source_line "${line}" || continue
        if [[ "${ALLOWLIST_SOURCE_SET_ID}" == "default" \
            && ("${ALLOWLIST_SOURCE_NAME}" == "${name}" || "${ALLOWLIST_SOURCE_VALUE}" == "${domain}") ]]; then
            err "DDNS 来源已存在：${name} / ${domain}"
            return 1
        fi
    done < "${ALLOWLIST_SOURCES_FILE}"
    serialize_allowlist_source "default" "ddns" "${name}" "${domain}" "${enabled}" "${ttl}" "" "" >> "${ALLOWLIST_SOURCES_FILE}"
}

rewrite_selected_ddns_source() {
    local old_set="$1"
    local old_name="$2"
    local old_value="$3"
    local replacement="${4:-}"
    local line tmp
    ensure_allowlist_sources_file || return 1
    make_temp_file "${ALLOWLIST_SOURCES_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    write_allowlist_sources_header "${tmp}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if parse_allowlist_source_line "${line}"; then
            if [[ "${ALLOWLIST_SOURCE_SET_ID}" == "${old_set}" \
                && "${ALLOWLIST_SOURCE_NAME}" == "${old_name}" \
                && "${ALLOWLIST_SOURCE_VALUE}" == "${old_value}" ]]; then
                [[ -n "${replacement}" ]] && printf '%s\n' "${replacement}" >> "${tmp}"
                continue
            fi
            printf '%s\n' "${PARSED_ALLOWLIST_SOURCE}" >> "${tmp}"
        elif [[ -n "$(trim "${line}")" && ! "$(trim "${line}")" =~ ^# ]]; then
            printf '%s\n' "${line}" >> "${tmp}"
        fi
    done < "${ALLOWLIST_SOURCES_FILE}"
    mv -f "${tmp}" "${ALLOWLIST_SOURCES_FILE}"
}

disable_src_allowlist_if_no_custom_entries() {
    case "${SRC_ALLOWLIST_MODE}" in
        manual_only|trusted_dynamic|custom_sources)
            custom_allowlist_has_entries || ENABLE_SRC_ALLOWLIST="0"
            ;;
        region_plus_trusted)
            [[ -n "${SRC_ALLOWLIST_REGION_IDS}" ]] || custom_allowlist_has_entries || ENABLE_SRC_ALLOWLIST="0"
            ;;
        region_only)
            [[ -n "${SRC_ALLOWLIST_REGION_IDS}" ]] || ENABLE_SRC_ALLOWLIST="0"
            ;;
    esac
}

do_add_ddns_allowlist_source() {
    local name domain ttl enabled answer
    name="$(read_prompt "请输入 DDNS 显示名（例如 home，可空）: ")" || name=""
    domain="$(read_prompt "请输入 DDNS 域名（例如 home.example.com）: ")" || return 1
    domain="$(trim "${domain}")"
    validate_ddns_domain "${domain}" || {
        err "DDNS 域名无效：${domain}"
        return 1
    }
    [[ -n "$(trim "${name}")" ]] || name="${domain}"
    ttl="$(prompt_with_default "请输入刷新 TTL 秒数（60-86400）" "43200")"
    ttl="$(normalize_source_ttl_seconds "${ttl}")"
    answer="$(read_prompt "是否启用这个 DDNS 来源 [Y/n]: ")" || answer=""
    case "${answer,,}" in
        n|no)
            enabled="0"
            ;;
        *)
            enabled="1"
            ;;
    esac
    printf '即将添加 : 名称=%s 域名=%s TTL=%ss 状态=%s\n' \
        "$(sanitize_allowlist_source_text "${name}")" "${domain}" "${ttl}" \
        "$([[ "${enabled}" == "1" ]] && printf '启用' || printf '停用')"
    confirm_yes "确认添加 DDNS 来源" || return 1
    save_allowlist_last_snapshot || return 1
    append_ddns_allowlist_source "${name}" "${domain}" "${ttl}" "${enabled}" || return 1
    if [[ "${enabled}" == "1" ]]; then
        success "DDNS 来源已添加并启用；等待 LAN Worker/路由器解析后通过 SSH 上报。"
    else
        success "DDNS 来源已添加，但尚未启用。"
    fi
}

do_delete_ddns_allowlist_source() {
    local old_set old_name old_value
    select_ddns_allowlist_source || return 1
    old_set="${ALLOWLIST_SOURCE_SET_ID}"
    old_name="${ALLOWLIST_SOURCE_NAME}"
    old_value="${ALLOWLIST_SOURCE_VALUE}"
    confirm_yes "确认删除 DDNS 来源 ${old_name} (${old_value})" || return 1
    save_allowlist_last_snapshot || return 1
    rewrite_selected_ddns_source "${old_set}" "${old_name}" "${old_value}" "" || return 1
    sync_ddns_entries_removed "${old_set}" "${old_name}" "${old_value}" || return 1
    remove_ddns_report_stats "${old_value}" || true
    [[ "${old_name}" != "${old_value}" ]] && remove_ddns_report_stats "${old_name}" || true
    disable_src_allowlist_if_no_custom_entries
    apply_src_allowlist_changes || return 1
}

do_edit_ddns_allowlist_source() {
    local old_set old_name old_value old_enabled old_ttl
    local new_name new_domain new_ttl answer new_enabled replacement line duplicate=0
    select_ddns_allowlist_source || return 1
    old_set="${ALLOWLIST_SOURCE_SET_ID}"
    old_name="${ALLOWLIST_SOURCE_NAME}"
    old_value="${ALLOWLIST_SOURCE_VALUE}"
    old_enabled="${ALLOWLIST_SOURCE_ENABLED}"
    old_ttl="${ALLOWLIST_SOURCE_TTL_SECONDS}"

    new_name="$(prompt_with_default "请输入 DDNS 显示名" "${old_name}")"
    new_domain="$(prompt_with_default "请输入 DDNS 域名" "${old_value}")"
    new_domain="$(trim "${new_domain}")"
    validate_ddns_domain "${new_domain}" || {
        err "DDNS 域名无效：${new_domain}"
        return 1
    }
    [[ -n "$(trim "${new_name}")" ]] || new_name="${new_domain}"
    new_name="$(sanitize_allowlist_source_text "${new_name}")"
    new_domain="$(sanitize_allowlist_source_text "${new_domain}")"
    new_ttl="$(prompt_with_default "请输入刷新 TTL 秒数（60-86400）" "${old_ttl}")"
    new_ttl="$(normalize_source_ttl_seconds "${new_ttl}")"
    if [[ "${old_enabled}" == "1" ]]; then
        answer="$(prompt_with_default "是否启用这个 DDNS 来源 [Y/n]" "Y")"
    else
        answer="$(prompt_with_default "是否启用这个 DDNS 来源 [y/N]" "N")"
    fi
    case "${answer,,}" in
        y|yes)
            new_enabled="1"
            ;;
        n|no)
            new_enabled="0"
            ;;
        *)
            new_enabled="${old_enabled}"
            ;;
    esac

    ensure_allowlist_sources_file || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_source_line "${line}" || continue
        if [[ "${ALLOWLIST_SOURCE_SET_ID}" == "${old_set}" \
            && "${ALLOWLIST_SOURCE_NAME}" == "${old_name}" \
            && "${ALLOWLIST_SOURCE_VALUE}" == "${old_value}" ]]; then
            continue
        fi
        if [[ "${ALLOWLIST_SOURCE_SET_ID}" == "default" \
            && ("${ALLOWLIST_SOURCE_NAME}" == "${new_name}" || "${ALLOWLIST_SOURCE_VALUE}" == "${new_domain}") ]]; then
            duplicate=1
            break
        fi
    done < "${ALLOWLIST_SOURCES_FILE}"
    [[ "${duplicate}" != "1" ]] || {
        err "DDNS 来源已存在：${new_name} / ${new_domain}"
        return 1
    }

    printf '即将修改 : %s (%s) -> %s (%s)，TTL=%ss，状态=%s\n' \
        "${old_name}" "${old_value}" "${new_name}" "${new_domain}" "${new_ttl}" \
        "$([[ "${new_enabled}" == "1" ]] && printf '启用' || printf '停用')"
    confirm_yes "确认修改 DDNS 来源" || return 1
    save_allowlist_last_snapshot || return 1
    replacement="$(serialize_allowlist_source \
        "${old_set}" \
        "ddns" \
        "${new_name}" \
        "${new_domain}" \
        "${new_enabled}" \
        "${new_ttl}" \
        "" \
        "")"
    rewrite_selected_ddns_source "${old_set}" "${old_name}" "${old_value}" "${replacement}" || return 1
    if [[ "${new_domain}" != "${old_value}" || "${new_name}" != "${old_name}" ]]; then
        sync_ddns_entries_removed "${old_set}" "${old_name}" "${old_value}" || return 1
        remove_ddns_report_stats "${old_value}" || true
        [[ "${old_name}" != "${old_value}" ]] && remove_ddns_report_stats "${old_name}" || true
    fi
    if [[ "${new_enabled}" == "1" ]]; then
        do_refresh_ddns_allowlist_sources
    else
        sync_ddns_entries_removed "${old_set}" "${new_name}" "${new_domain}" || return 1
        disable_src_allowlist_if_no_custom_entries
        apply_src_allowlist_changes || return 1
    fi
}

do_toggle_ddns_allowlist_source() {
    local old_set old_name old_value new_enabled replacement
    select_ddns_allowlist_source || return 1
    old_set="${ALLOWLIST_SOURCE_SET_ID}"
    old_name="${ALLOWLIST_SOURCE_NAME}"
    old_value="${ALLOWLIST_SOURCE_VALUE}"
    if [[ "${ALLOWLIST_SOURCE_ENABLED}" == "1" ]]; then
        new_enabled="0"
    else
        new_enabled="1"
    fi
    replacement="$(serialize_allowlist_source \
        "${ALLOWLIST_SOURCE_SET_ID}" \
        "${ALLOWLIST_SOURCE_TYPE}" \
        "${ALLOWLIST_SOURCE_NAME}" \
        "${ALLOWLIST_SOURCE_VALUE}" \
        "${new_enabled}" \
        "${ALLOWLIST_SOURCE_TTL_SECONDS}" \
        "${ALLOWLIST_SOURCE_LAST_RESOLVED_AT}" \
        "${ALLOWLIST_SOURCE_LAST_RESULT}")"
    confirm_yes "确认$([[ "${new_enabled}" == "1" ]] && printf '启用' || printf '停用') DDNS 来源 ${old_name}" || return 1
    save_allowlist_last_snapshot || return 1
    rewrite_selected_ddns_source "${old_set}" "${old_name}" "${old_value}" "${replacement}" || return 1
    if [[ "${new_enabled}" == "1" ]]; then
        do_refresh_ddns_allowlist_sources
    else
        sync_ddns_entries_removed "${old_set}" "${old_name}" "${old_value}" || return 1
        disable_src_allowlist_if_no_custom_entries
        apply_src_allowlist_changes || return 1
    fi
}
