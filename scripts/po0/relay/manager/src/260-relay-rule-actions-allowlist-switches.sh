do_toggle_rules() {
    local action selection idx target updated need_relay_lan_ip=0
    print_title "启用 / 停用规则"
    command -v nft &>/dev/null || {
        err "请先执行【1】安装/初始化。"
        return
    }
    settings_ready || return
    load_rules
    [[ ${#RULES[@]} -gt 0 ]] || {
        info "当前没有转发规则。"
        return
    }

    print_rules_table
    selection="$(read_prompt "请输入规则序号，支持 1,3,5-7: ")" || return 1
    parse_selection "${selection}" "${#RULES[@]}" || {
        err "序号格式无效。"
        return
    }

    action="$(read_prompt "操作类型 [1=启用, 2=停用, 3=切换]: ")" || return 1
    case "${action}" in
        1) action="enable" ;;
        2) action="disable" ;;
        3) action="toggle" ;;
        *)
            err "无效选择。"
            return
            ;;
    esac

    for idx in "${SELECTED_INDICES[@]}"; do
        target="${RULES[$((idx - 1))]}"
        parse_rule "${target}"
        if [[ "${action}" == "enable" || ( "${action}" == "toggle" && "${RULE_ENABLED}" != "1" ) ]]; then
            ensure_new_listen_port_allowed "${RULE_LPORT}" "${RULE_PROTO}" || return
            [[ "${RULE_SNAT_MODE}" == "relay_lan" ]] && need_relay_lan_ip=1
        fi
    done
    if [[ "${need_relay_lan_ip}" == "1" ]]; then
        prompt_relay_lan_ip_if_needed "relay_lan" || return
    fi

    echo "即将处理以下规则："
    print_selected_rules
    confirm_yes "确认继续" || {
        info "已取消。"
        return
    }

    backup_managed_files
    for idx in "${SELECTED_INDICES[@]}"; do
        target="${RULES[$((idx - 1))]}"
        parse_rule "${target}"
        case "${action}" in
            enable) RULE_ENABLED="1" ;;
            disable) RULE_ENABLED="0" ;;
            toggle)
                if [[ "${RULE_ENABLED}" == "1" ]]; then
                    RULE_ENABLED="0"
                else
                    RULE_ENABLED="1"
                fi
                ;;
        esac
        updated="$(serialize_rule "${RULE_ID}" "${RULE_NAME}" "${RULE_PROTO}" "${RULE_LPORT}" "${RULE_DIP}" "${RULE_DPORT}" "${RULE_ENABLED}" "${RULE_SNAT_MODE}")"
        RULES[$((idx - 1))]="${updated}"
    done

    save_settings || return
    save_rules || return
    write_nft_conf || return
    apply_or_save_notice "规则状态已更新。" "规则状态已保存到托管配置。"
}

do_delete() {
    local selection idx
    print_title "删除转发规则"
    command -v nft &>/dev/null || {
        err "请先执行【1】安装/初始化。"
        return
    }
    settings_ready || return
    load_rules
    [[ ${#RULES[@]} -gt 0 ]] || {
        info "当前没有转发规则。"
        return
    }

    print_rules_table
    selection="$(read_prompt "请输入要删除的规则序号，支持 1,3,5-7: ")" || return 1
    parse_selection "${selection}" "${#RULES[@]}" || {
        err "序号格式无效。"
        return
    }

    echo "即将删除以下规则："
    print_selected_rules
    confirm_yes "确认删除" || {
        info "已取消。"
        return
    }

    backup_managed_files
    for idx in "${SELECTED_INDICES[@]}"; do
        unset 'RULES[$((idx - 1))]'
    done
    RULES=("${RULES[@]}")
    save_rules || return
    write_nft_conf || return
    apply_or_save_notice "规则已删除。" "规则已从托管配置删除。"
}

do_import_rules() {
    local path mode choice source_kind="file"
    local -a current_rules=()
    local -a final_rules=()
    print_title "批量导入规则"
    command -v nft &>/dev/null || {
        err "请先执行【1】安装/初始化。"
        return
    }
    settings_ready || return
    ensure_layout || return
    load_rules

    while true; do
        show_import_format_hint
        echo ""
        echo "导入助手:"
        print_menu_item 1 "直接导入规则文件"
        print_menu_item 2 "先生成导入模板"
        print_menu_item 3 "导入当前 nft 运行时规则"
        print_menu_item 0 "返回"
        print_menu_footer
        read_menu_choice_or_return choice "请选择操作 [0-3]: " || return 2
        case "${choice}" in
            1)
                mode="$(prompt_import_mode)" || return
                break
                ;;
            2)
                create_import_template_interactive || {
                    info "已取消。"
                    return
                }
                echo ""
                confirm_yes "是否继续导入刚生成的模板文件" || {
                    info "已返回上级菜单。"
                    return
                }
                path="${TEMPLATE_OUTPUT_PATH}"
                mode="$(prompt_import_mode)" || return
                break
                ;;
            3)
                source_kind="runtime"
                mode="replace"
                echo ""
                info "开始扫描当前 nft 运行时规则。"
                load_runtime_import_rules || return
                break
                ;;
            0)
                info "已取消。"
                return 2
                ;;
            *)
                err "无效选择。"
                ;;
        esac
    done

    if [[ "${source_kind}" == "file" ]]; then
        if [[ -z "${path:-}" ]]; then
            path="$(prompt_with_default "请输入导入文件路径" "${EXPORT_DIR}/po0-relay-import-template.txt")"
        fi
        path="$(trim "${path}")"
        [[ -n "${path}" && -f "${path}" ]] || {
            err "导入文件不存在。"
            return
        }

        echo ""
        info "开始检查导入文件格式与规则冲突。"
        load_import_rules "${path}" "${mode}" || return
        echo ""
        info "导入文件检查通过。"
    else
        echo ""
        info "已从 $(rules_source_label "${DISCOVERED_RULES_SOURCE}") 读取到 ${#IMPORTED_RULES[@]} 条运行时规则。"
    fi

    current_rules=("${RULES[@]}")
    RULES=("${IMPORTED_RULES[@]}")
    apply_relay_mode_to_rules
    IMPORTED_RULES=("${RULES[@]}")
    echo "即将导入 ${#IMPORTED_RULES[@]} 条规则："
    print_rules_table
    RULES=("${current_rules[@]}")
    if [[ "${mode}" == "replace" ]]; then
        final_rules=("${IMPORTED_RULES[@]}")
    else
        final_rules=("${current_rules[@]}" "${IMPORTED_RULES[@]}")
    fi
    RULES=("${final_rules[@]}")
    apply_relay_mode_to_rules
    final_rules=("${RULES[@]}")
    if relay_lan_snat_required; then
        prompt_relay_lan_ip_if_needed "relay_lan" || {
            RULES=("${current_rules[@]}")
            return
        }
    fi
    RULES=("${current_rules[@]}")

    if [[ "${source_kind}" == "runtime" ]]; then
        warn "运行时导入会用当前 nft 规则快照覆盖脚本托管规则文件。"
        info "这一步先保存为托管配置；如果当前系统还没被脚本接管，不会强行改动正在运行的 nftables。"
    elif [[ "${mode}" == "replace" ]]; then
        warn "覆盖模式会替换当前全部规则。"
    else
        info "追加模式会保留现有规则，并在通过校验后追加导入。"
    fi
    confirm_yes "确认导入" || {
        info "已取消。"
        return
    }

    backup_managed_files
    if [[ "${mode}" == "replace" ]]; then
        RULES=("${IMPORTED_RULES[@]}")
    else
        RULES+=("${IMPORTED_RULES[@]}")
    fi
    apply_relay_mode_to_rules
    save_settings || return
    save_rules || return
    write_nft_conf || return
    apply_or_save_notice "规则导入完成。" "规则已导入托管配置。"
}

do_export_rules() {
    local path tmp rule
    print_title "导出规则"
    ensure_layout || return
    load_settings
    load_rules
    [[ ${#RULES[@]} -gt 0 ]] || {
        info "当前没有转发规则。"
        return
    }

    path="$(prompt_with_default "导出文件路径" "$(export_rules_default_path)")"
    path="$(trim "${path}")"
    [[ -n "${path}" ]] || {
        err "导出路径不能为空。"
        return
    }
    if [[ -e "${path}" ]]; then
        confirm_yes "目标文件已存在，是否覆盖" || {
            info "已取消。"
            return
        }
    fi

    mkdir -p "$(dirname "${path}")" 2>/dev/null || true
    make_temp_file "${path}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    cat > "${tmp}" <<'EOF'
# nftables relay import/export file
# format: name|proto|listen_port|dest_ip|dest_port|enabled|snat_mode
# proto: both | tcp | udp
# enabled: 1=启用, 0=停用
# snat_mode: relay_lan | masquerade | none
EOF
    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        printf '%s|%s|%s|%s|%s|%s|%s\n' \
            "${RULE_NAME}" "${RULE_PROTO}" "${RULE_LPORT}" "${RULE_DIP}" "${RULE_DPORT}" "${RULE_ENABLED}" "${RULE_SNAT_MODE}" >> "${tmp}"
    done
    mv -f "${tmp}" "${path}"
    success "规则已导出到 ${path}"
}

do_diagnose() {
    print_title "诊断 / 自检"
    local nat_loaded="0"
    load_settings
    load_rules
    print_status_panel
    print_runtime_drift_hint
    print_runtime_rule_hint
    echo ""
    command -v nft &>/dev/null && info "nftables: $(nft --version 2>/dev/null)" || err "nftables: 未安装"
    [[ -f "${NFT_CONF}" ]] && nft -c -f "${NFT_CONF}" >/dev/null 2>&1 && info "relay 配置语法: 通过" || warn "relay 配置语法: 未通过或文件不存在"
    [[ -f "${MAIN_CONF}" ]] && nft -c -f "${MAIN_CONF}" >/dev/null 2>&1 && info "主配置语法: 通过" || warn "主配置语法: 未通过或文件不存在"
    if nft list table ip "${NAT_TABLE}" &>/dev/null; then
        nat_loaded="1"
        info "NAT 表已加载"
    else
        warn "NAT 表未加载"
    fi
    if [[ "${ENABLE_MSS_CLAMP}" == "1" ]]; then
        nft list table ip "${MANGLE_TABLE}" &>/dev/null && info "MSS 表已加载" || warn "MSS 表未加载"
    fi
    if [[ "${nat_loaded}" == "1" && ${#RULES[@]} -gt 0 ]]; then
        echo ""
        print_rule_counters
    fi
    warn_conflicts
    echo ""
    printf '托管文件:\n'
    printf '  - %s\n' "${MAIN_CONF}"
    printf '  - %s\n' "${NFT_CONF}"
    printf '  - %s\n' "${SETTINGS_FILE}"
    printf '  - %s\n' "${RULES_FILE}"
    printf '  - %s\n' "${SRC_ALLOWLIST_CACHE}"
    printf '  - %s\n' "${CUSTOM_SRC_ALLOWLIST_FILE}"
    printf '  - %s\n' "${ALLOWLIST_SETS_FILE}"
    printf '  - %s\n' "${ALLOWLIST_ENTRIES_FILE}"
    printf '  - %s\n' "${ALLOWLIST_SOURCES_FILE}"
    printf '  - %s\n' "${DDNS_REPORT_STATS_FILE}"
    printf '  - %s\n' "${BLOCK_LOG_FILE}"
    printf '  - %s\n' "${BLOCK_SUMMARY_FILE}"
    printf '  - %s\n' "${LEARN_LOG_FILE}"
    printf '  - %s\n' "${LEARN_SUMMARY_FILE}"
    printf '  - %s\n' "${LEARN_DAILY_IP_FILE}"
    printf '被阻挡访问日志: %s 条（统计 %s 行）\n' "$(block_log_count)" "$(block_summary_count)"
    printf '  - %s\n' "${LEARN_SERVICE_FILE}"
    printf '  - %s\n' "${IPDB_FILE}"
    printf '  - %s\n' "${IPLIST_DIR}"
    printf '  - %s\n' "${BACKUP_DIR}"
}

do_edit_settings() {
    print_title "修改中转机参数"
    command -v nft &>/dev/null || {
        err "请先执行【1】安装/初始化。"
        return
    }
    ensure_layout || return
    load_rules
    prompt_settings || return
    prompt_input_firewall_settings || return
    apply_relay_mode_to_rules
    backup_managed_files
    save_settings || return
    save_rules || return
    write_nft_conf || return
    apply_or_save_notice "中转机参数已更新。" "中转机参数已保存到托管配置。" || return
    print_settings
}

do_refresh_public_ip() {
    local ok=0
    print_title "手动刷新中转机 IP 缓存"
    ensure_layout || return
    load_settings 1
    if relay_mode_uses_lan; then
        if refresh_relay_lan_ip; then
            success "中转机内网 IP 已刷新：${RELAY_LAN_IP}"
            ok=1
        else
            warn "未能探测到中转机内网 IP。"
        fi
    fi

    if refresh_public_ip; then
        success "公网 IP 已刷新：${PUBLIC_IP}（$(public_ip_source_label)）"
        ok=1
    else
        warn "未能探测到公网 IP。"
        info "如果这是纯内网中转机，属于正常情况；也可以稍后网络稳定后再试。"
    fi
    save_settings || return
    [[ "${ok}" == "1" ]] || warn "没有刷新到可用 IP，已保留空缓存。"
    pause_before_return
}

select_iplist_region_interactive() {
    local keyword choice idx record id name rel url
    local -a matches=()
    SELECTED_REGION_ID=""
    ensure_iplist_ready || return 1
    keyword="$(read_prompt "请输入地区关键词或代码（例如 深圳 / 440300）: ")" || return 1
    keyword="$(trim "${keyword}")"
    [[ -n "${keyword}" ]] || return 1
    mapfile -t matches < <(
        awk -F '\t' -v q="${keyword}" '
            index($1, q) || index($2, q) { print }
        ' "${IPLIST_MANIFEST}" | head -n 30
    )
    [[ ${#matches[@]} -gt 0 ]] || {
        err "未找到匹配地区。"
        return 1
    }
    echo "匹配地区："
    idx=1
    for record in "${matches[@]}"; do
        IFS=$'\t' read -r id name rel url <<< "${record}"
        printf '  %2d) %s (%s)\n' "${idx}" "${name}" "${id}"
        ((idx++))
    done
    choice="$(read_prompt "请选择地区序号 [1-${#matches[@]}]: ")" || return 1
    [[ "${choice}" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= ${#matches[@]} )) || return 1
    IFS=$'\t' read -r id name rel url <<< "${matches[$((choice - 1))]}"
    SELECTED_REGION_ID="${id}"
}

select_selected_allowlist_region() {
    local choice idx id
    local -a ids=()
    SELECTED_REGION_ID=""
    for id in ${SRC_ALLOWLIST_REGION_IDS}; do
        ids+=("${id}")
    done
    [[ ${#ids[@]} -gt 0 ]] || {
        err "当前没有已选择地区。"
        return 1
    }
    idx=1
    for id in "${ids[@]}"; do
        printf '  %2d) %s\n' "${idx}" "$(iplist_region_label "${id}")"
        ((idx++))
    done
    choice="$(read_prompt "请选择要删除的地区序号 [1-${#ids[@]}]: ")" || return 1
    [[ "${choice}" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= ${#ids[@]} )) || return 1
    SELECTED_REGION_ID="${ids[$((choice - 1))]}"
}

prompt_src_allowlist_mode() {
    local choice
    while true; do
        echo "选择源 IP 限制方式："
        echo "  0) 关闭：不限制访问转发端口的来源 IP"
        echo "  1) 仅手动来源：手动 CIDR（SSH 临时需在菜单中手动开启）"
        echo "  2) 可信动态来源：手动 + DDNS + Client IP + SSH report + WebAuth + learned（不默认含 SSH 临时）"
        echo "  3) 地区 + 可信动态来源"
        echo "  4) 仅地区库"
        echo "  5) 高级自选来源组合"
        choice="$(read_prompt "请选择 [0-5，当前: $([[ "${ENABLE_SRC_ALLOWLIST}" == "1" ]] && src_allowlist_mode_to_label "${SRC_ALLOWLIST_MODE}" || printf '关闭')]: ")" || return 1
        case "${choice}" in
            0)
                ENABLE_SRC_ALLOWLIST="0"
                return 0
                ;;
            1)
                ENABLE_SRC_ALLOWLIST="1"
                SRC_ALLOWLIST_MODE="manual_only"
                return 0
                ;;
            2)
                ENABLE_SRC_ALLOWLIST="1"
                SRC_ALLOWLIST_MODE="trusted_dynamic"
                return 0
                ;;
            3)
                ENABLE_SRC_ALLOWLIST="1"
                SRC_ALLOWLIST_MODE="region_plus_trusted"
                return 0
                ;;
            4)
                ENABLE_SRC_ALLOWLIST="1"
                SRC_ALLOWLIST_MODE="region_only"
                return 0
                ;;
            5)
                ENABLE_SRC_ALLOWLIST="1"
                SRC_ALLOWLIST_MODE="custom_sources"
                configure_default_allowlist_sources_interactive || return 1
                return 0
                ;;
            "")
                return 0
                ;;
            *)
                err "无效选择。"
                ;;
        esac
    done
}

configure_default_allowlist_sources_interactive() {
    local raw normalized
    load_allowlist_sets
    raw="$(src_allowlist_mode_default_sources custom_sources)"
    echo ""
    echo "可选来源：region, manual, ssh_temp, ddns, client_ip, ssh_report, webauth, learned"
    raw="$(prompt_with_default "请输入允许的来源，逗号分隔" "${raw}")"
    normalized="$(normalize_allowlist_set_sources "${raw}")" || {
        err "来源组合无效。"
        return 1
    }
    set_default_allowlist_sources "${normalized}" || return 1
    success "高级来源组合已更新：${normalized}"
}

set_default_allowlist_sources() {
    local sources="$1"
    local set replaced=0
    local -a next=()
    sources="$(normalize_allowlist_set_sources "${sources}")" || return 1
    load_allowlist_sets
    for set in "${ALLOWLIST_SETS[@]}"; do
        parse_allowlist_set_line "${set}" || continue
        if [[ "${ALLOWLIST_SET_ID}" == "default" ]]; then
            next+=("$(serialize_allowlist_set \
                "${ALLOWLIST_SET_ID}" \
                "${ALLOWLIST_SET_LABEL}" \
                "${ALLOWLIST_SET_ENABLED}" \
                "${ALLOWLIST_SET_SCOPE}" \
                "${ALLOWLIST_SET_PORTS}" \
                "${sources}" \
                "${ALLOWLIST_SET_NOTE}")")
            replaced=1
        else
            next+=("${PARSED_ALLOWLIST_SET}")
        fi
    done
    if [[ "${replaced}" != "1" ]]; then
        next+=("$(serialize_allowlist_set "default" "Default public allowlist" "1" "public" "*" "${sources}" "Custom source-type allowlist")")
    fi
    ALLOWLIST_SETS=("${next[@]}")
    save_allowlist_sets
}

enable_allowlist_source_type_for_current_mode() {
    local source_type="$1"
    local sources source normalized
    source_type="$(normalize_allowlist_entry_source_type "${source_type}")" || return 1
    ENABLE_SRC_ALLOWLIST="1"
    sources="$(src_allowlist_mode_default_sources "${SRC_ALLOWLIST_MODE}")"
    for source in ${sources//,/ }; do
        if [[ "${source}" == "${source_type}" ]]; then
            return 0
        fi
    done
    normalized="$(normalize_allowlist_set_sources "${sources},${source_type}")" || return 1
    SRC_ALLOWLIST_MODE="custom_sources"
    set_default_allowlist_sources "${normalized}" || return 1
    info "已切换为高级自选来源，并启用 ${source_type}。"
}

do_manage_allowlist_source_switches() {
    save_allowlist_last_snapshot || return 1
    ENABLE_SRC_ALLOWLIST="1"
    SRC_ALLOWLIST_MODE="custom_sources"
    configure_default_allowlist_sources_interactive || return 1
    apply_src_allowlist_changes
}

select_custom_allowlist_entry() {
    local line choice idx=1
    local -a entries=()
    SELECTED_LEARN_CIDR=""
    [[ -f "${CUSTOM_SRC_ALLOWLIST_FILE}" ]] || {
        err "当前没有自定义 CIDR。"
        return 1
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_custom_allowlist_line "${line}" || continue
        entries+=("${CUSTOM_ALLOWLIST_CIDR}|${CUSTOM_ALLOWLIST_NOTE}")
    done < "${CUSTOM_SRC_ALLOWLIST_FILE}"
    [[ ${#entries[@]} -gt 0 ]] || {
        err "当前没有自定义 CIDR。"
        return 1
    }
    for line in "${entries[@]}"; do
        IFS='|' read -r CUSTOM_ALLOWLIST_CIDR CUSTOM_ALLOWLIST_NOTE <<< "${line}"
        if [[ -n "${CUSTOM_ALLOWLIST_NOTE}" ]]; then
            printf '  %2d) %-18s %s\n' "${idx}" "${CUSTOM_ALLOWLIST_CIDR}" "${CUSTOM_ALLOWLIST_NOTE}"
        else
            printf '  %2d) %s\n' "${idx}" "${CUSTOM_ALLOWLIST_CIDR}"
        fi
        ((idx++))
    done
    choice="$(read_prompt "请选择要删除的自定义 CIDR [1-${#entries[@]}]: ")" || return 1
    [[ "${choice}" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= ${#entries[@]} )) || return 1
    IFS='|' read -r SELECTED_LEARN_CIDR SELECTED_LEARN_NOTE <<< "${entries[$((choice - 1))]}"
}

enable_allowlist_for_region_add() {
    ENABLE_SRC_ALLOWLIST="1"
    case "${SRC_ALLOWLIST_MODE}" in
        manual_only|trusted_dynamic)
            SRC_ALLOWLIST_MODE="region_plus_trusted"
            ;;
        region_only|region_plus_trusted|custom_sources)
            ;;
        *)
            SRC_ALLOWLIST_MODE="region_only"
            ;;
    esac
}

enable_allowlist_for_custom_add() {
    ENABLE_SRC_ALLOWLIST="1"
    case "${SRC_ALLOWLIST_MODE}" in
        region_only)
            SRC_ALLOWLIST_MODE="region_plus_trusted"
            ;;
        manual_only|trusted_dynamic|region_plus_trusted|custom_sources)
            ;;
        *)
            SRC_ALLOWLIST_MODE="trusted_dynamic"
            ;;
    esac
}

apply_src_allowlist_changes() {
    backup_managed_files
    write_nft_conf || return 1
    save_settings || return 1
    apply_or_save_notice "源 IP 白名单已更新。" "源 IP 白名单已保存到托管配置。" || return 1
}

do_refresh_ddns_allowlist_sources() {
    ensure_layout || return 1
    load_settings 1
    warn "DDNS 刷新只使用 LAN Worker/路由器已经上报且仍在 TTL 内的结果；PO0 不做本地 DNS 解析，也不延长原上报 TTL。"
    backup_managed_files
    refresh_ddns_allowlist_sources || return 1
    printf 'DDNS 来源刷新：外部上报续期 %s 个，失败/无新鲜上报 %s 个，停用 %s 个\n' \
        "${DDNS_REPORTED_COUNT:-0}" "${DDNS_FAILED_COUNT:-0}" "${DDNS_DISABLED_COUNT:-0}"
    if [[ "${DDNS_REFRESHED_COUNT:-0}" -gt 0 ]]; then
        enable_allowlist_for_custom_add
        apply_src_allowlist_changes || return 1
    elif [[ "${DDNS_DISABLED_COUNT:-0}" -gt 0 ]]; then
        disable_src_allowlist_if_no_custom_entries
        apply_src_allowlist_changes || return 1
    fi
    if [[ "${DDNS_FAILED_COUNT:-0}" -gt 0 ]]; then
        warn "DDNS 刷新失败；旧的 DDNS 白名单结果已保留，不会被清空。"
        return 1
    fi
    if [[ "${DDNS_REFRESHED_COUNT:-0}" -eq 0 && "${DDNS_DISABLED_COUNT:-0}" -eq 0 ]]; then
        success "没有启用的 DDNS 来源需要刷新。"
    fi
}
