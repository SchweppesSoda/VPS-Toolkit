install_ipdb_parser_dependency() {
    ensure_layout || return 1
    install_ipdb_python_base_if_needed || return 1
    if ! ipdb_venv_has_pip; then
        if [[ -x "${IPDB_VENV_PYTHON}" ]]; then
            warn "检测到旧的 IPDB venv 缺少 pip，将删除并重建。"
        fi
        if ! create_ipdb_venv; then
            warn "首次创建 IPDB 专用 venv 失败，尝试重新安装 Python venv 组件后重试。"
            install_ipdb_python_base_if_needed || return 1
            create_ipdb_venv || {
                err "创建 IPDB 专用 Python venv 失败：${IPDB_VENV_DIR}"
                err "如果仍看到 No module named pip，请手动安装 python3-venv 或 python3.x-venv 后重试。"
                return 1
            }
        fi
    fi
    install_ipdb_parser_package || {
        err "安装 ipip-ipdb 失败。"
        err "如果当前 pip 源不可达，请重新运行安装入口并选择其它镜像源或自定义源。"
        return 1
    }
    if ! "${IPDB_VENV_PYTHON}" - <<'PY' >/dev/null 2>&1
import ipdb
assert hasattr(ipdb, "City")
PY
    then
        err "ipip-ipdb 安装后仍无法导入。"
        return 1
    fi
    success "IPDB 解析依赖已安装到 ${IPDB_VENV_DIR}。"
}

warn_conflicts() {
    local found=0
    if systemctl is-active --quiet firewalld 2>/dev/null; then
        warn "检测到 firewalld 正在运行，托管式 nftables 中转脚本不建议与其混用。"
        found=1
    fi
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -qw active; then
        warn "检测到 UFW 正在运行，托管式 nftables 中转脚本不建议与其混用。"
        found=1
    fi
    (( found == 1 )) && warn "如继续初始化，将由 nftables 独占接管这台中转机。"
}

ensure_layout() {
    mkdir -p "${CONF_DIR}" "${BACKUP_DIR}" "${EXPORT_DIR}" "${ALLOWLIST_PROFILE_DIR}" "${RESOURCE_INBOX_DIR}" || return 1
    [[ -f "${SETTINGS_FILE}" ]] || save_settings
    [[ -f "${RULES_FILE}" ]] || save_rules
    [[ -f "${ALLOWLIST_SETS_FILE}" ]] || save_allowlist_sets
    [[ -f "${ALLOWLIST_ENTRIES_FILE}" ]] || ensure_allowlist_entries_file
    [[ -f "${ALLOWLIST_SOURCES_FILE}" ]] || ensure_allowlist_sources_file
    [[ -f "${BLOCK_LOG_FILE}" ]] || ensure_block_log_file
    [[ -f "${BLOCK_SUMMARY_FILE}" ]] || regenerate_block_summary
    [[ -f "${AUTO_PENDING_FILE}" ]] || ensure_auto_pending_file
    [[ -f "${CLIENT_IP_REPORT_STATS_FILE}" ]] || ensure_generic_report_stats_file "${CLIENT_IP_REPORT_STATS_FILE}"
    [[ -f "${SSH_REPORT_STATS_FILE}" ]] || ensure_generic_report_stats_file "${SSH_REPORT_STATS_FILE}"
    [[ -f "${WEBAUTH_REPORT_STATS_FILE}" ]] || ensure_generic_report_stats_file "${WEBAUTH_REPORT_STATS_FILE}"
    [[ -f "${RESOURCE_TASKS_FILE}" ]] || resource_task_write_header "${RESOURCE_TASKS_FILE}"
}

manager_controls_main_conf() {
    [[ -f "${MAIN_CONF}" ]] || return 1
    [[ -f "${NFT_CONF}" ]] || return 1
    grep -Fq 'include "/etc/nftables.d/*.conf"' "${MAIN_CONF}" 2>/dev/null
}

apply_or_save_notice() {
    local applied_msg="$1"
    local saved_msg="$2"
    if manager_controls_main_conf; then
        reload_managed_rules || return 1
        success "${applied_msg}"
    else
        success "${saved_msg}"
        info "当前运行中的 nftables 尚未由脚本接管；执行 [1] 安装 / 初始化 nftables 后，托管配置才会统一接管并生效。"
    fi
}

backup_takeover_files() {
    local ts file
    ts="$(date '+%Y%m%d_%H%M%S')"
    [[ -f "${MAIN_CONF}" ]] && mv "${MAIN_CONF}" "${MAIN_CONF}.bak.${ts}" 2>/dev/null || true
    for file in "${CONF_DIR}"/*.conf; do
        [[ -f "${file}" ]] || continue
        mv "${file}" "${file}.bak.${ts}" 2>/dev/null || true
    done
}

backup_managed_files() {
    local ts file
    ts="$(date '+%Y%m%d_%H%M%S')"
    for file in "${NFT_CONF}" "${SETTINGS_FILE}" "${RULES_FILE}" "${SRC_ALLOWLIST_CACHE}" "${CUSTOM_SRC_ALLOWLIST_FILE}" "${ALLOWLIST_SETS_FILE}" "${ALLOWLIST_ENTRIES_FILE}" "${ALLOWLIST_SOURCES_FILE}" "${DDNS_REPORT_STATS_FILE}" "${CLIENT_IP_REPORT_STATS_FILE}" "${SSH_REPORT_STATS_FILE}" "${WEBAUTH_REPORT_STATS_FILE}" "${AUTO_PENDING_FILE}" "${BLOCK_LOG_FILE}" "${BLOCK_SUMMARY_FILE}"; do
        [[ -f "${file}" ]] && cp "${file}" "${BACKUP_DIR}/$(basename "${file}").${ts}" 2>/dev/null || true
    done
}

unquote_setting_value() {
    local value="$1"
    value="$(trim "${value}")"
    if [[ "${value}" =~ ^\".*\"$ ]]; then
        value="${value:1:${#value}-2}"
    elif [[ "${value}" =~ ^\'.*\'$ ]]; then
        value="${value:1:${#value}-2}"
    fi
    printf '%s\n' "${value}"
}

read_settings_file() {
    local line key raw_value value
    [[ -f "${SETTINGS_FILE}" ]] || return 0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        line="$(trim "${line}")"
        [[ -z "${line}" ]] && continue
        [[ "${line}" =~ ^# ]] && continue
        [[ "${line}" == *=* ]] || continue
        key="$(trim "${line%%=*}")"
        raw_value="${line#*=}"
        value="$(unquote_setting_value "${raw_value}")"
        case "${key}" in
            NODE_NAME)
                NODE_NAME="${value}"
                ;;
            RELAY_MODE)
                RELAY_MODE="${value}"
                ;;
            RELAY_LAN_IP)
                RELAY_LAN_IP="${value}"
                ;;
            PUBLIC_IP)
                PUBLIC_IP="${value}"
                ;;
            PUBLIC_IP_SOURCE)
                PUBLIC_IP_SOURCE="${value}"
                ;;
            ENABLE_MSS_CLAMP)
                ENABLE_MSS_CLAMP="${value}"
                ;;
            MSS_VALUE)
                MSS_VALUE="${value}"
                ;;
            MANAGE_INPUT_FIREWALL)
                MANAGE_INPUT_FIREWALL="${value}"
                ;;
            SSH_PORTS)
                SSH_PORTS="${value}"
                ;;
            ENABLE_SRC_ALLOWLIST)
                ENABLE_SRC_ALLOWLIST="${value}"
                ;;
            SRC_ALLOWLIST_MODE)
                SRC_ALLOWLIST_MODE="${value}"
                ;;
            SRC_ALLOWLIST_REGION_IDS)
                SRC_ALLOWLIST_REGION_IDS="${value}"
                ;;
            AUTOMATION_MODE)
                AUTOMATION_MODE="${value}"
                ;;
            MANAGER_UPDATE_URL)
                MANAGER_UPDATE_URL="${value}"
                ;;
        esac
    done < "${SETTINGS_FILE}"
}

load_settings() {
    local force_reload="${1:-0}"
    if [[ "${SETTINGS_CACHE_READY}" == "1" && "${force_reload}" != "1" ]]; then
        return 0
    fi
    NODE_NAME=""
    RELAY_MODE="mixed"
    RELAY_LAN_IP=""
    PUBLIC_IP=""
    PUBLIC_IP_CACHE=""
    PUBLIC_IP_CACHE_SOURCE="none"
    ENABLE_MSS_CLAMP="1"
    MSS_VALUE="1452"
    MANAGE_INPUT_FIREWALL="1"
    SSH_PORTS=""
    ENABLE_SRC_ALLOWLIST="0"
    SRC_ALLOWLIST_MODE="trusted_dynamic"
    SRC_ALLOWLIST_REGION_IDS=""
    AUTOMATION_MODE="regular"
    MANAGER_UPDATE_URL=""
    RELAY_LAN_IP_SOURCE="none"
    PUBLIC_IP_SOURCE="none"
    read_settings_file
    validate_node_name "${NODE_NAME}" || NODE_NAME=""
    RELAY_MODE="$(normalize_relay_mode "${RELAY_MODE}" 2>/dev/null || printf 'mixed')"
    if validate_host_ipv4 "${RELAY_LAN_IP}"; then
        RELAY_LAN_IP_SOURCE="settings"
    fi
    if is_public_ipv4 "${PUBLIC_IP}"; then
        case "${PUBLIC_IP_SOURCE}" in
            system|online|manual)
                ;;
            *)
                PUBLIC_IP_SOURCE="settings"
                ;;
        esac
        PUBLIC_IP_CACHE="${PUBLIC_IP}"
        PUBLIC_IP_CACHE_SOURCE="${PUBLIC_IP_SOURCE}"
    else
        PUBLIC_IP=""
        PUBLIC_IP_SOURCE="none"
    fi
    [[ "${ENABLE_MSS_CLAMP}" == "0" || "${ENABLE_MSS_CLAMP}" == "1" ]] || ENABLE_MSS_CLAMP="1"
    validate_mss "${MSS_VALUE}" || MSS_VALUE="1452"
    [[ "${MANAGE_INPUT_FIREWALL}" == "0" || "${MANAGE_INPUT_FIREWALL}" == "1" ]] || MANAGE_INPUT_FIREWALL="1"
    SSH_PORTS="$(normalize_port_list "${SSH_PORTS}")"
    if [[ "${MANAGE_INPUT_FIREWALL}" == "1" && -z "${SSH_PORTS}" ]]; then
        SSH_PORTS="$(detect_ssh_ports || true)"
    fi
    SSH_PORTS="$(normalize_port_list "${SSH_PORTS}")"
    [[ "${ENABLE_SRC_ALLOWLIST}" == "0" || "${ENABLE_SRC_ALLOWLIST}" == "1" ]] || ENABLE_SRC_ALLOWLIST="0"
    SRC_ALLOWLIST_MODE="$(normalize_src_allowlist_mode "${SRC_ALLOWLIST_MODE}" 2>/dev/null || printf 'trusted_dynamic')"
    SRC_ALLOWLIST_REGION_IDS="$(normalize_region_ids "${SRC_ALLOWLIST_REGION_IDS}")"
    case "${AUTOMATION_MODE}" in
        regular|attack) ;;
        *) AUTOMATION_MODE="regular" ;;
    esac
    SETTINGS_CACHE_READY="1"
}

save_settings() {
    local tmp
    make_temp_file "${SETTINGS_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    validate_node_name "${NODE_NAME}" || NODE_NAME=""
    RELAY_MODE="$(normalize_relay_mode "${RELAY_MODE}" 2>/dev/null || printf 'mixed')"
    if validate_host_ipv4 "${RELAY_LAN_IP}"; then
        RELAY_LAN_IP_SOURCE="settings"
    else
        RELAY_LAN_IP=""
        RELAY_LAN_IP_SOURCE="none"
    fi
    if ! is_public_ipv4 "${PUBLIC_IP}"; then
        PUBLIC_IP=""
        PUBLIC_IP_SOURCE="none"
    fi
    SRC_ALLOWLIST_MODE="$(normalize_src_allowlist_mode "${SRC_ALLOWLIST_MODE}" 2>/dev/null || printf 'trusted_dynamic')"
    case "${AUTOMATION_MODE}" in
        regular|attack) ;;
        *) AUTOMATION_MODE="regular" ;;
    esac
    cat > "${tmp}" <<EOF
NODE_NAME="${NODE_NAME}"
RELAY_MODE="${RELAY_MODE}"
RELAY_LAN_IP="${RELAY_LAN_IP}"
PUBLIC_IP="${PUBLIC_IP}"
PUBLIC_IP_SOURCE="${PUBLIC_IP_SOURCE}"
ENABLE_MSS_CLAMP="${ENABLE_MSS_CLAMP}"
MSS_VALUE="${MSS_VALUE}"
MANAGE_INPUT_FIREWALL="${MANAGE_INPUT_FIREWALL}"
SSH_PORTS="${SSH_PORTS}"
ENABLE_SRC_ALLOWLIST="${ENABLE_SRC_ALLOWLIST}"
SRC_ALLOWLIST_MODE="${SRC_ALLOWLIST_MODE}"
SRC_ALLOWLIST_REGION_IDS="${SRC_ALLOWLIST_REGION_IDS}"
AUTOMATION_MODE="${AUTOMATION_MODE}"
MANAGER_UPDATE_URL="${MANAGER_UPDATE_URL}"
EOF
    mv -f "${tmp}" "${SETTINGS_FILE}"
    SETTINGS_CACHE_READY="1"
}

parse_rule_line() {
    local line="$1"
    local rid name proto lport dip dport enabled snat_mode
    local -a fields=()

    IFS='|' read -r -a fields <<< "${line}"
    case "${#fields[@]}" in
        3)
            rid="$(generate_unique_rule_id)"
            lport="$(trim "${fields[0]}")"
            dip="$(trim "${fields[1]}")"
            dport="$(trim "${fields[2]}")"
            proto="both"
            name="relay-${lport}"
            enabled="1"
            snat_mode="$(relay_mode_default_snat_mode)"
            ;;
        6)
            rid="$(generate_unique_rule_id)"
            name="$(trim "${fields[0]}")"
            proto="$(trim "${fields[1]}")"
            lport="$(trim "${fields[2]}")"
            dip="$(trim "${fields[3]}")"
            dport="$(trim "${fields[4]}")"
            enabled="$(trim "${fields[5]}")"
            snat_mode="$(relay_mode_default_snat_mode)"
            ;;
        7)
            if normalize_proto "$(trim "${fields[1]}")" >/dev/null 2>&1 \
                && validate_port "$(trim "${fields[2]}")" \
                && validate_host_ipv4 "$(trim "${fields[3]}")" \
                && validate_port "$(trim "${fields[4]}")" \
                && [[ "$(trim "${fields[5]}")" =~ ^[01]$ ]] \
                && normalize_snat_mode "$(trim "${fields[6]}")" >/dev/null 2>&1; then
                rid="$(generate_unique_rule_id)"
                name="$(trim "${fields[0]}")"
                proto="$(trim "${fields[1]}")"
                lport="$(trim "${fields[2]}")"
                dip="$(trim "${fields[3]}")"
                dport="$(trim "${fields[4]}")"
                enabled="$(trim "${fields[5]}")"
                snat_mode="$(trim "${fields[6]}")"
            else
                rid="$(trim "${fields[0]}")"
                name="$(trim "${fields[1]}")"
                proto="$(trim "${fields[2]}")"
                lport="$(trim "${fields[3]}")"
                dip="$(trim "${fields[4]}")"
                dport="$(trim "${fields[5]}")"
                enabled="$(trim "${fields[6]}")"
                snat_mode="relay_lan"
            fi
            ;;
        8)
            rid="$(trim "${fields[0]}")"
            name="$(trim "${fields[1]}")"
            proto="$(trim "${fields[2]}")"
            lport="$(trim "${fields[3]}")"
            dip="$(trim "${fields[4]}")"
            dport="$(trim "${fields[5]}")"
            enabled="$(trim "${fields[6]}")"
            snat_mode="$(trim "${fields[7]}")"
            ;;
        *)
            return 1
            ;;
    esac

    [[ -n "${rid}" ]] || rid="$(generate_unique_rule_id)"
    if ! validate_rule_id "${rid}" || rule_id_exists "${rid}"; then
        rid="$(generate_unique_rule_id)"
    fi
    proto="$(normalize_proto "${proto}")" || return 1
    [[ "${enabled}" == "0" || "${enabled}" == "1" ]] || return 1
    validate_rule_name "${name}" || return 1
    validate_listen_port_value "${lport}" || return 1
    validate_host_ipv4 "${dip}" || return 1
    validate_port "${dport}" || return 1
    snat_mode="$(normalize_snat_mode "${snat_mode}")" || return 1

    PARSED_RULE="$(serialize_rule "${rid}" "${name}" "${proto}" "${lport}" "${dip}" "${dport}" "${enabled}" "${snat_mode}")"
}

load_rules() {
    local force_reload="${1:-0}"
    local line
    if [[ "${RULES_CACHE_READY}" == "1" && "${force_reload}" != "1" ]]; then
        return 0
    fi
    RULES=()
    RULES_SOURCE="none"
    if [[ -f "${RULES_FILE}" ]]; then
        while IFS= read -r line || [[ -n "${line}" ]]; do
            line="${line%$'\r'}"
            line="${line#$'\ufeff'}"
            line="$(trim "${line}")"
            [[ -z "${line}" ]] && continue
            [[ "${line}" =~ ^# ]] && continue
            parse_rule_line "${line}" || continue
            RULES+=("${PARSED_RULE}")
        done < "${RULES_FILE}"
    fi
    if [[ ${#RULES[@]} -gt 0 ]]; then
        RULES_SOURCE="rules_file"
        RULES_CACHE_READY="1"
        return 0
    fi
    RULES_CACHE_READY="1"
}

save_rules() {
    local tmp
    local rule
    make_temp_file "${RULES_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    cat > "${tmp}" <<'EOF'
# Managed by nftables relay manager
# format: id|name|proto|listen_port|dest_ip|dest_port|enabled|snat_mode
EOF
    for rule in "${RULES[@]}"; do
        printf '%s\n' "${rule}" >> "${tmp}"
    done
    mv -f "${tmp}" "${RULES_FILE}"
    RULES_SOURCE="rules_file"
    RULES_CACHE_READY="1"
    clear_discovery_cache
}

settings_ready() {
    load_settings
    load_rules
    if ! relay_lan_snat_required; then
        return 0
    fi
    validate_host_ipv4 "${RELAY_LAN_IP}" || {
        err "当前存在内网/无感内网 SNAT 规则，但中转机内网 IP 尚未设置。请先执行 [14] 中转机参数。"
        return 1
    }
}

print_runtime_rule_hint() {
    [[ ${#RULES[@]} -eq 0 ]] || return 0
    discover_existing_rules || return 0
    printf '  现有 nft 规则 : %s 条（%s）\n' \
        "${DISCOVERED_RULE_COUNT}" \
        "$(rules_source_label "${DISCOVERED_RULES_SOURCE}")"
    printf '               可用 [1] 初始化接管或 [9] 导入托管配置。\n'
}

print_settings() {
    load_settings
    load_rules
    printf '本机名称    : %s\n' "${NODE_NAME:-未设置（导出不加前缀）}"
    printf '中转模式    : %s\n' "$(relay_mode_to_label "${RELAY_MODE}")"
    if validate_host_ipv4 "${RELAY_LAN_IP}"; then
        printf '中转机内网 IP : %s (%s)\n' "${RELAY_LAN_IP}" "$(relay_ip_source_label)"
    else
        printf '中转机内网 IP : 未设置\n'
    fi
    if is_public_ipv4 "${PUBLIC_IP}"; then
        printf '公网 IP     : %s (%s)\n' "${PUBLIC_IP}" "$(public_ip_source_label)"
    else
        printf '公网 IP     : 未探测到（可用菜单 [2] 手动刷新）\n'
    fi
    if [[ ${#RULES[@]} -gt 0 && "${RULES_SOURCE}" != "rules_file" ]]; then
        printf '规则来源    : %s\n' "$(rules_source_label)"
    fi
    if [[ "${ENABLE_MSS_CLAMP}" == "1" ]]; then
        printf 'MSS 修正    : 开启 (%s)\n' "${MSS_VALUE}"
    else
        printf 'MSS 修正    : 关闭\n'
    fi
    if [[ "${MANAGE_INPUT_FIREWALL}" == "1" ]]; then
        printf '入站防火墙 : 接管（SSH: %s，其它未托管端口默认 drop）\n' "${SSH_PORTS:-未探测}"
    else
        printf '入站防火墙 : 不接管\n'
    fi
    if src_allowlist_enabled; then
        printf '源 IP 白名单 : 开启（%s，地区 %s / 自定义 %s）\n' \
            "$(src_allowlist_mode_to_label "${SRC_ALLOWLIST_MODE}")" \
            "$(src_allowlist_region_count)" \
            "$(custom_allowlist_count)"
    elif [[ "${ENABLE_SRC_ALLOWLIST}" == "1" ]]; then
        printf '源 IP 白名单 : 配置不完整（%s）\n' "$(src_allowlist_mode_to_label "${SRC_ALLOWLIST_MODE}")"
    else
        printf '源 IP 白名单 : 关闭\n'
    fi
    printf '学习服务    : %s\n' "$(learning_service_status_label)"
}

print_status_panel() {
    local nft_status ip_forward_status runtime_drift_summary runtime_drift_count runtime_drift_tables
    runtime_drift_count=""
    runtime_drift_tables=""
    load_settings
    load_rules
    refresh_rule_counts
    runtime_drift_summary="$(get_unmanaged_runtime_dnat_summary || true)"
    if [[ -n "${runtime_drift_summary}" ]]; then
        IFS='|' read -r runtime_drift_count runtime_drift_tables <<< "${runtime_drift_summary}"
    fi

    if command -v nft &>/dev/null; then
        nft_status="${C_GREEN}已安装${C_RESET}"
    else
        nft_status="${C_YELLOW}未安装${C_RESET}"
    fi

    if [[ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" == "1" ]]; then
        ip_forward_status="${C_GREEN}已开启${C_RESET}"
    else
        ip_forward_status="${C_YELLOW}未开启${C_RESET}"
    fi

    print_panel_section "系统状态"
    print_panel_row "nftables" "${nft_status}"
    print_panel_row "IPv4 转发" "${ip_forward_status}"
    if manager_controls_main_conf; then
        print_panel_row "接管状态" "${C_GREEN}已接管${C_RESET}"
    else
        print_panel_row "接管状态" "${C_YELLOW}未接管（仅管理配置文件）${C_RESET}"
    fi

    print_panel_section "网络与转发"
    print_panel_row "中转模式" "$(relay_mode_to_label "${RELAY_MODE}")"
    if validate_host_ipv4 "${RELAY_LAN_IP}"; then
        print_panel_row "中转机内网 IP" "${RELAY_LAN_IP}"
        if [[ "${RELAY_LAN_IP_SOURCE}" != "settings" ]]; then
            print_panel_note "$(relay_ip_source_label)"
        fi
    else
        print_panel_row "中转机内网 IP" "未设置"
    fi
    if is_public_ipv4 "${PUBLIC_IP}"; then
        print_panel_row "公网 IP" "${PUBLIC_IP}"
        print_panel_note "$(public_ip_source_label)"
    else
        print_panel_row "公网 IP" "未探测到（可用 [2] 手动刷新）"
    fi
    if [[ ${RULE_TOTAL} -gt 0 && "${RULES_SOURCE}" != "rules_file" ]]; then
        print_panel_row "规则来源" "$(rules_source_label)"
    fi
    if [[ "${ENABLE_MSS_CLAMP}" == "1" ]]; then
        print_panel_row "MSS 修正" "开启 (${MSS_VALUE})"
    else
        print_panel_row "MSS 修正" "关闭"
    fi

    print_panel_section "安全与来源"
    if [[ "${MANAGE_INPUT_FIREWALL}" == "1" ]]; then
        print_panel_row "入站防火墙" "接管（SSH: ${SSH_PORTS:-未探测}，其它未托管端口默认 drop）"
    else
        print_panel_row "入站防火墙" "不接管"
    fi
    if src_allowlist_enabled; then
        print_panel_row "源 IP 白名单" "开启（$(src_allowlist_mode_to_label "${SRC_ALLOWLIST_MODE}")，地区 $(src_allowlist_region_count) / 自定义 $(custom_allowlist_count)）"
    elif [[ "${ENABLE_SRC_ALLOWLIST}" == "1" ]]; then
        print_panel_row "源 IP 白名单" "配置不完整（$(src_allowlist_mode_to_label "${SRC_ALLOWLIST_MODE}")）"
    else
        print_panel_row "源 IP 白名单" "关闭"
    fi

    print_panel_section "运行数据"
    print_panel_row "学习服务" "$(learning_service_status_label)（$(learning_log_count) 条记录，$(format_bytes "$(learning_log_size_bytes)")；每日汇总 $(learning_summary_count) 天）"
    print_panel_row "规则总数" "${RULE_TOTAL}（启用 ${RULE_ENABLED_COUNT} / 停用 ${RULE_DISABLED_COUNT}）"
    if [[ -n "${runtime_drift_count}" ]]; then
        print_panel_row "额外生效规则" "${runtime_drift_count} 条脚本未管理的 DNAT 转发"
        [[ -n "${runtime_drift_tables}" ]] && print_panel_note "所在 nft 表: ${runtime_drift_tables}"
        print_panel_note "说明: 这些规则正在生效，但修改脚本列表不会影响它们"
    fi
}

prompt_relay_mode() {
    local current="${1:-mixed}"
    local choice
    current="$(normalize_relay_mode "${current}" 2>/dev/null || printf 'mixed')"
    while true; do
        echo "选择中转机使用场景：" >&2
        echo "  1) 纯内网/无感内网转发：默认使用内网回源" >&2
        echo "  2) 公网转发：默认使用公网出口" >&2
        echo "  3) 内网/公网混合转发：新增规则时逐条选择" >&2
        choice="$(read_prompt "请选择转发模式 [1=纯内网/无感内网转发, 2=公网转发, 3=内网/公网混合转发；当前: $(relay_mode_to_label "${current}")]: ")" || return 1
        choice="$(trim "${choice}")"
        case "${choice,,}" in
            "")
                printf '%s\n' "${current}"
                return 0
                ;;
            1|lan|relay_lan|inner|private|po0|po0_lan)
                printf 'lan\n'
                return 0
                ;;
            2|public|wan|masq|masquerade|egress)
                printf 'public\n'
                return 0
                ;;
            3|mixed|both|hybrid|all)
                printf 'mixed\n'
                return 0
                ;;
        esac
        err "使用场景只能选择 1 / 2 / 3。"
    done
}

refresh_cached_ips_for_mode() {
    if relay_mode_uses_lan && ! validate_host_ipv4 "${RELAY_LAN_IP}"; then
        if refresh_relay_lan_ip; then
            info "已自动探测并缓存中转机内网 IP：${RELAY_LAN_IP}"
        else
            warn "未能自动探测到中转机内网 IP。"
        fi
    fi

    if ! is_public_ipv4 "${PUBLIC_IP}"; then
        if refresh_public_ip; then
            info "已自动探测并缓存公网 IP：${PUBLIC_IP}"
        else
            warn "未能自动探测到公网 IP。"
        fi
    fi
    return 0
}
