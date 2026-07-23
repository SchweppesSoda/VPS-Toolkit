write_nft_conf() {
    local output="${1:-${NFT_CONF}}"
    local allowlist_cache="${2:-${SRC_ALLOWLIST_CACHE}}"
    local tmp
    local rule lport dip dport ip_set proto_expr comment
    local allowlist_active="0"
    local tcp_ports udp_ports
    local input_policy="accept"
    local ssh_ports_nft=""
    local relay_lan_ip_define
    make_temp_file "${output}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    load_settings
    load_rules
    load_allowlist_sets
    validate_managed_listen_ports || return 1
    if relay_lan_snat_required && ! validate_host_ipv4 "${RELAY_LAN_IP}"; then
        err "存在内网/无感内网 SNAT 规则，但中转机内网 IP 未设置。"
        return 1
    fi
    relay_lan_ip_define="${RELAY_LAN_IP:-0.0.0.0}"
    ensure_input_firewall_ready || return 1
    if [[ "${MANAGE_INPUT_FIREWALL}" == "1" ]]; then
        input_policy="drop"
        ssh_ports_nft="$(ports_to_nft_set "${SSH_PORTS}")"
    fi
    if [[ "${ENABLE_SRC_ALLOWLIST}" == "1" ]]; then
        validate_src_allowlist_ready || return 1
        build_src_allowlist_cache "${allowlist_cache}" || return 1
        allowlist_active="1"
    fi
    cat > "${tmp}" <<EOF
#!/usr/sbin/nft -f
# Managed by nftables relay manager
define RELAY_LAN_IP = ${relay_lan_ip_define}

table ip ${NAT_TABLE} {
EOF
    if [[ "${allowlist_active}" == "1" ]]; then
        write_nft_allowlist_set "${tmp}" "${allowlist_cache}" || return 1
    fi
    cat >> "${tmp}" <<EOF
    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
EOF
    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        [[ "${RULE_ENABLED}" == "1" ]] || continue
        proto_expr="$(proto_to_nft_expr "${RULE_PROTO}")"
        comment="$(escape_nft_comment "${RULE_NAME}")"
        if [[ "${allowlist_active}" == "1" ]]; then
            printf '\n        ip saddr @%s meta l4proto %s th dport %s counter dnat to %s:%s comment "%s"\n' \
                "$(default_allowlist_nft_set_name)" \
                "${proto_expr}" "${RULE_LPORT}" "${RULE_DIP}" "${RULE_DPORT}" "${comment}" >> "${tmp}"
        else
            printf '\n        meta l4proto %s th dport %s counter dnat to %s:%s comment "%s"\n' \
                "${proto_expr}" "${RULE_LPORT}" "${RULE_DIP}" "${RULE_DPORT}" "${comment}" >> "${tmp}"
        fi
    done
    cat >> "${tmp}" <<EOF
    }
EOF
    if [[ "${allowlist_active}" == "1" || "${MANAGE_INPUT_FIREWALL}" == "1" ]]; then
        tcp_ports="$(enabled_rule_ports_set tcp)"
        udp_ports="$(enabled_rule_ports_set udp)"
        cat >> "${tmp}" <<EOF

    chain input_guard {
        type filter hook input priority filter; policy ${input_policy};
EOF
        if [[ "${MANAGE_INPUT_FIREWALL}" == "1" ]]; then
            printf '        iifname "lo" counter accept comment "po0-allow-loopback"\n' >> "${tmp}"
            printf '        ct state established,related counter accept comment "po0-allow-established"\n' >> "${tmp}"
            printf '        ip protocol icmp counter accept comment "po0-allow-icmp"\n' >> "${tmp}"
            printf '        tcp dport { %s } counter accept comment "po0-allow-ssh"\n' "${ssh_ports_nft}" >> "${tmp}"
        fi
        if [[ "${allowlist_active}" == "1" ]]; then
            [[ -n "${tcp_ports}" ]] && printf '        ip saddr != @%s tcp dport { %s } limit rate 10/minute burst 20 packets log prefix "po0-block set=default proto=tcp " counter drop comment "po0-src-allowlist-tcp"\n' "$(default_allowlist_nft_set_name)" "${tcp_ports}" >> "${tmp}"
            [[ -n "${udp_ports}" ]] && printf '        ip saddr != @%s udp dport { %s } limit rate 10/minute burst 20 packets log prefix "po0-block set=default proto=udp " counter drop comment "po0-src-allowlist-udp"\n' "$(default_allowlist_nft_set_name)" "${udp_ports}" >> "${tmp}"
        fi
        cat >> "${tmp}" <<'EOF'
    }
EOF
    fi
    cat >> "${tmp}" <<EOF
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
EOF
    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        [[ "${RULE_ENABLED}" == "1" ]] || continue
        proto_expr="$(proto_to_nft_expr "${RULE_PROTO}")"
        comment="$(escape_nft_comment "${RULE_NAME}")"
        case "${RULE_SNAT_MODE}" in
            masquerade)
                printf '\n        ip daddr %s meta l4proto %s th dport %s ct status dnat counter masquerade comment "%s"\n' \
                    "${RULE_DIP}" "${proto_expr}" "${RULE_DPORT}" "${comment}" >> "${tmp}"
                ;;
            none)
                ;;
            *)
                printf '\n        ip daddr %s meta l4proto %s th dport %s ct status dnat counter snat to $RELAY_LAN_IP comment "%s"\n' \
                    "${RULE_DIP}" "${proto_expr}" "${RULE_DPORT}" "${comment}" >> "${tmp}"
                ;;
        esac
    done
    cat >> "${tmp}" <<EOF
    }
}
EOF
    if [[ "${ENABLE_MSS_CLAMP}" == "1" ]]; then
        ip_set="$(unique_dest_ip_set)"
        cat >> "${tmp}" <<EOF

table ip ${MANGLE_TABLE} {
    chain forward {
        type filter hook forward priority mangle; policy accept;
EOF
        [[ -n "${ip_set}" ]] && printf '        ip daddr { %s } tcp flags syn tcp option maxseg size set %s comment "po0-mss-clamp"\n' "${ip_set}" "${MSS_VALUE}" >> "${tmp}"
        cat >> "${tmp}" <<'EOF'
    }
}
EOF
    fi
    mv -f "${tmp}" "${output}"
}

write_managed_reload_transaction() {
    local output="$1"
    local config="${2:-${NFT_CONF}}"
    [[ -r "${config}" ]] || {
        err "relay 配置不可读：${config}。"
        return 1
    }
    {
        if nft list table ip "${NAT_TABLE}" >/dev/null 2>&1; then
            printf 'delete table ip %s\n' "${NAT_TABLE}"
        fi
        if nft list table ip "${MANGLE_TABLE}" >/dev/null 2>&1; then
            printf 'delete table ip %s\n' "${MANGLE_TABLE}"
        fi
        printf '\n'
        cat "${config}"
    } > "${output}" || {
        err "生成 nftables 原子刷新事务失败。"
        return 1
    }
}

reload_managed_rules() {
    local transaction
    make_temp_file "${NFT_CONF}.reload" || {
        err "创建 nftables 原子刷新临时文件失败。"
        return 1
    }
    transaction="${TEMP_FILE_RESULT}"
    write_managed_reload_transaction "${transaction}" "${NFT_CONF}" || {
        rm -f -- "${transaction}" 2>/dev/null || true
        return 1
    }
    nft -c -f "${transaction}" >/dev/null 2>&1 || {
        rm -f -- "${transaction}" 2>/dev/null || true
        err "relay 原子刷新事务预检失败，请检查 ${NFT_CONF}。"
        return 1
    }
    nft -f "${transaction}" || {
        rm -f -- "${transaction}" 2>/dev/null || true
        err "原子加载 ${NFT_CONF} 失败；运行中的旧托管规则保持不变。"
        return 1
    }
    rm -f -- "${transaction}" 2>/dev/null || true
}

apply_full_config() {
    nft -c -f "${MAIN_CONF}" >/dev/null 2>&1 || {
        err "主配置预检失败。"
        return 1
    }
    nft -f "${MAIN_CONF}" || {
        err "加载 ${MAIN_CONF} 失败。"
        return 1
    }
}

enable_ip_forward() {
    mkdir -p "$(dirname "${SYSCTL_CONF}")" 2>/dev/null || true
    touch "${SYSCTL_CONF}" 2>/dev/null || true
    grep -qE '^[[:space:]]*net\.ipv4\.ip_forward[[:space:]]*=' "${SYSCTL_CONF}" 2>/dev/null \
        && sed -i -E 's|^[[:space:]]*net\.ipv4\.ip_forward[[:space:]]*=.*|net.ipv4.ip_forward=1|' "${SYSCTL_CONF}" 2>/dev/null \
        || echo "net.ipv4.ip_forward=1" >> "${SYSCTL_CONF}" 2>/dev/null
    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
    sysctl -p "${SYSCTL_CONF}" >/dev/null 2>&1 || true
}

enable_bbr_fq() {
    modprobe tcp_bbr 2>/dev/null || true
    grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null || {
        warn "当前内核不支持 BBR。"
        return 0
    }
    sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1 || true
    sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1 || true
    grep -qE '^[[:space:]]*net\.core\.default_qdisc[[:space:]]*=' "${SYSCTL_CONF}" 2>/dev/null \
        && sed -i -E 's|^[[:space:]]*net\.core\.default_qdisc[[:space:]]*=.*|net.core.default_qdisc=fq|' "${SYSCTL_CONF}" 2>/dev/null \
        || echo "net.core.default_qdisc=fq" >> "${SYSCTL_CONF}" 2>/dev/null
    grep -qE '^[[:space:]]*net\.ipv4\.tcp_congestion_control[[:space:]]*=' "${SYSCTL_CONF}" 2>/dev/null \
        && sed -i -E 's|^[[:space:]]*net\.ipv4\.tcp_congestion_control[[:space:]]*=.*|net.ipv4.tcp_congestion_control=bbr|' "${SYSCTL_CONF}" 2>/dev/null \
        || echo "net.ipv4.tcp_congestion_control=bbr" >> "${SYSCTL_CONF}" 2>/dev/null
    sysctl -p "${SYSCTL_CONF}" >/dev/null 2>&1 || true
    success "已写入 BBR + fq。"
}

check_port_conflict() {
    local port="$1"
    local proto="$2"
    ensure_listen_port_allowed "${port}" "${proto}"
}

show_import_format_hint() {
    echo "导入文件支持注释行和空行，推荐使用新格式："
    echo ""
    echo "  新格式: 名称|协议|监听端口|目标IP|目标端口|启用状态|回程方式"
    echo "  字段说明:"
    echo "    - 名称: 自定义规则名称，不能重复，不能包含 |"
    echo "    - 协议: both / tcp / udp"
    echo "    - 监听端口: 不能使用保留服务端口，也不能占用本机已有服务端口"
    echo "    - 启用状态: 1=启用, 0=停用"
    echo "    - 回程方式: relay_lan / masquerade / none"
    echo ""
    echo "  示例:"
    echo "    hk-relay|both|30080|10.0.0.2|443|1|relay_lan"
    echo "    public-api|tcp|30081|203.0.113.10|443|1|masquerade"
    echo "    transparent|tcp|30082|10.0.0.3|443|0|none"
    echo ""
    echo "  兼容旧格式: 监听端口|目标IP|目标端口 或 名称|协议|监听端口|目标IP|目标端口|启用状态"
    echo "  旧格式会自动补齐为:"
    echo "    - 名称: relay-监听端口"
    echo "    - 协议: both"
    echo "    - 启用状态: 1"
    echo "    - 回程方式: 跟随当前中转模式（混合模式下默认 relay_lan）"
}

write_import_template() {
    local path="$1"
    local tmp
    make_temp_file "${path}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    cat > "${tmp}" <<'EOF'
# nftables relay import template
# 说明:
# 1. 每行一条规则，支持空行和 # 注释行
# 2. 推荐格式:
#    名称|协议|监听端口|目标IP|目标端口|启用状态|回程方式
# 3. 协议支持:
#    both / tcp / udp
# 4. 启用状态:
#    1=启用, 0=停用
# 5. 回程方式:
#    relay_lan   = 内网/无感内网，SNAT 到中转机内网 IP
#    masquerade  = 普通公网转发，SNAT 到出口网卡地址
#    none        = 不改写源地址，要求目标机有回程路由
# 6. 兼容旧格式:
#    监听端口|目标IP|目标端口
#    未写回程方式时会跟随当前中转模式（混合模式下默认 relay_lan）

# 推荐新格式示例:
hk-relay|both|30080|10.0.0.2|443|1|relay_lan
public-api|tcp|30081|203.0.113.10|443|1|masquerade
transparent|tcp|30082|10.0.0.4|443|0|none

# 兼容旧格式示例:
# 30083|10.0.0.5|80
EOF
    mv -f "${tmp}" "${path}"
}

create_import_template_interactive() {
    local path
    ensure_layout || return 1
    path="$(prompt_with_default "模板输出路径" "${EXPORT_DIR}/po0-relay-import-template.txt")"
    path="$(trim "${path}")"
    [[ -n "${path}" ]] || {
        err "模板路径不能为空。"
        return 1
    }
    mkdir -p "$(dirname "${path}")" 2>/dev/null || true
    if [[ -e "${path}" ]]; then
        confirm_yes "模板文件已存在，是否覆盖" || return 1
    fi
    write_import_template "${path}"
    success "导入模板已生成：${path}"
    printf '你可以先编辑这个模板，再回到本菜单执行导入。\n'
    TEMPLATE_OUTPUT_PATH="${path}"
}

prompt_import_mode() {
    local choice
    while true; do
        choice="$(read_prompt "导入模式 [1=追加导入, 2=覆盖现有规则]: ")" || return 1
        case "${choice}" in
            1)
                printf 'append\n'
                return 0
                ;;
            2)
                printf 'replace\n'
                return 0
                ;;
        esac
        err "无效选择。"
    done
}

load_import_rules() {
    local path="$1"
    local mode="$2"
    local line line_no=0 rule
    local candidate_id candidate_name candidate_proto candidate_lport candidate_dip candidate_dport candidate_enabled candidate_snat_mode
    IMPORTED_RULES=()

    while IFS= read -r line || [[ -n "${line}" ]]; do
        ((line_no++))
        line="${line%$'\r'}"
        line="${line#$'\ufeff'}"
        line="$(trim "${line}")"
        [[ -z "${line}" ]] && continue
        [[ "${line}" =~ ^# ]] && continue
        parse_rule_line "${line}" || {
            err "导入失败：第 ${line_no} 行格式无效。"
            return 1
        }

        parse_rule "${PARSED_RULE}"
        candidate_id="$(generate_unique_rule_id)"
        candidate_name="${RULE_NAME}"
        candidate_proto="${RULE_PROTO}"
        candidate_lport="${RULE_LPORT}"
        candidate_dip="${RULE_DIP}"
        candidate_dport="${RULE_DPORT}"
        candidate_enabled="${RULE_ENABLED}"
        candidate_snat_mode="${RULE_SNAT_MODE}"
        ensure_new_listen_port_allowed "${candidate_lport}" "${candidate_proto}" || {
            err "导入失败：监听端口 ${candidate_lport} 不可用。"
            return 1
        }
        PARSED_RULE="$(serialize_rule "${candidate_id}" "${candidate_name}" "${candidate_proto}" "${candidate_lport}" "${candidate_dip}" "${candidate_dport}" "${candidate_enabled}" "${candidate_snat_mode}")"

        for rule in "${IMPORTED_RULES[@]}"; do
            parse_rule "${rule}"
            if [[ "${RULE_NAME}" == "${candidate_name}" ]]; then
                err "导入失败：文件内存在重复规则名称。"
                return 1
            fi
            if [[ "${RULE_LPORT}" == "${candidate_lport}" ]] && protocols_overlap "${RULE_PROTO}" "${candidate_proto}"; then
                err "导入失败：文件内存在监听端口/协议冲突。"
                return 1
            fi
        done

        if [[ "${mode}" == "append" ]]; then
            rule_name_exists "${candidate_name}" && {
                err "导入失败：规则名称 ${candidate_name} 已存在。"
                return 1
            }
            rule_port_conflict_exists "${candidate_lport}" "${candidate_proto}" && {
                err "导入失败：监听端口 ${candidate_lport} 与现有规则冲突。"
                return 1
            }
        fi

        IMPORTED_RULES+=("${PARSED_RULE}")
    done < "${path}"

    [[ ${#IMPORTED_RULES[@]} -gt 0 ]] || {
        err "导入文件中没有可用规则。"
        return 1
    }
}

load_runtime_import_rules() {
    local rule
    discover_existing_rules 1 || {
        err "当前未检测到可导入的 nft 运行时规则。"
        return 1
    }
    IMPORTED_RULES=("${DISCOVERED_RULES[@]}")
    for rule in "${IMPORTED_RULES[@]}"; do
        parse_rule "${rule}"
        ensure_listen_port_allowed "${RULE_LPORT}" "${RULE_PROTO}" || return 1
    done
}

do_install() {
    print_title "安装 / 初始化 nftables"
    warn "该脚本按专用中转机思路工作，将接管 /etc/nftables.conf。"
    warn "初始化会 flush ruleset，并改写为 include /etc/nftables.d/*.conf。"
    warn_conflicts
    confirm_yes "是否继续初始化" || {
        info "已取消。"
        return
    }
    install_nftables_if_needed || return
    ensure_layout || return
    backup_takeover_files
    backup_managed_files
    load_rules
    if [[ ${#RULES[@]} -eq 0 ]] && discover_existing_rules 1; then
        warn "检测到当前系统已有 ${DISCOVERED_RULE_COUNT} 条 nft 运行时转发规则（$(rules_source_label "${DISCOVERED_RULES_SOURCE}")）。"
        RULES=("${DISCOVERED_RULES[@]}")
        print_rules_table
        RULES=()
        confirm_yes "是否在初始化时将这些规则导入为脚本托管规则" && {
            RULES=("${DISCOVERED_RULES[@]}")
            RULES_SOURCE="rules_file"
        }
    fi
    prompt_settings || return
    prompt_input_firewall_settings || return
    apply_relay_mode_to_rules
    save_settings || return
    save_rules || return
    write_main_conf || return
    write_nft_conf || return
    enable_ip_forward
    apply_full_config || return
    systemctl enable --now nftables 2>/dev/null || warn "无法自动启用 nftables 服务，请手动执行 systemctl enable --now nftables"
    success "初始化完成。"
    print_settings
}

do_list() {
    print_title "概览与规则列表"
    print_status_panel
    print_runtime_drift_hint
    print_runtime_rule_hint
    echo ""
    printf '%b源 IP 白名单%b\n' "${C_BOLD}" "${C_RESET}"
    print_src_allowlist_details
    echo ""
    print_rules_table
    pause_before_return
}

do_add() {
    local name proto lport dip dport enabled snat_mode rule default_lport
    print_title "新增转发规则"
    command -v nft &>/dev/null || {
        err "请先执行【1】安装/初始化。"
        return
    }
    settings_ready || return
    ensure_layout || return
    load_rules

    proto="$(prompt_protocol "both")" || return
    default_lport="$(choose_forward_listen_port "${proto}" || true)"
    lport="$(prompt_listen_port_value "请输入中转机监听端口" "${proto}" "${default_lport}")" || return
    rule_port_conflict_exists "${lport}" "${proto}" && {
        err "监听端口 ${lport} 与现有规则冲突。"
        return
    }
    dip="$(prompt_ip_value "请输入落地机 IP")" || return
    dport="$(prompt_port_value "请输入落地机端口" "${lport}")" || return
    snat_mode="$(select_rule_snat_mode)" || return
    prompt_relay_lan_ip_if_needed "${snat_mode}" || return
    name="$(prompt_rule_name "relay-${lport}")" || return
    enabled="$(prompt_enabled_flag "1")" || return

    echo "即将新增规则："
    printf '  - %s [%s] :%s -> %s:%s (%s)\n' \
        "${name}" "$(proto_to_label "${proto}")" "${lport}" "${dip}" "${dport}" \
        "$([[ "${enabled}" == "1" ]] && printf '启用' || printf '停用')"
    printf '  - 转发类型: %s\n' "$(snat_mode_to_label "${snat_mode}")"
    case "${snat_mode}" in
        relay_lan) printf '  - 回程源地址改写（SNAT）-> %s\n' "${RELAY_LAN_IP}" ;;
        masquerade) printf '  - 回程源地址改写（SNAT）-> 出口网卡地址（masquerade）\n' ;;
        none) printf '  - 回程源地址改写（SNAT）-> 不改写\n' ;;
    esac
    [[ "${ENABLE_MSS_CLAMP}" == "1" ]] && printf '  - TCP MSS 自动修正（MSS clamp）-> %s\n' "${MSS_VALUE}"
    confirm_yes "确认新增" || {
        info "已取消。"
        return
    }

    backup_managed_files
    rule="$(serialize_rule "$(generate_unique_rule_id)" "${name}" "${proto}" "${lport}" "${dip}" "${dport}" "${enabled}" "${snat_mode}")"
    RULES+=("${rule}")
    apply_relay_mode_to_rules
    save_settings || return
    save_rules || return
    write_nft_conf || return
    apply_or_save_notice "新增成功。" "规则已保存到托管配置。"
}

do_edit_rule() {
    local choice current rule proto lport dip dport name enabled snat_mode
    local current_id current_name current_proto current_lport current_dip current_dport current_enabled current_snat_mode
    print_title "编辑转发规则"
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
    choice="$(select_single_rule_index "${#RULES[@]}")" || {
        info "已取消。"
        return
    }

    current="${RULES[$((choice - 1))]}"
    parse_rule "${current}"
    current_id="${RULE_ID}"
    current_name="${RULE_NAME}"
    current_proto="${RULE_PROTO}"
    current_lport="${RULE_LPORT}"
    current_dip="${RULE_DIP}"
    current_dport="${RULE_DPORT}"
    current_enabled="${RULE_ENABLED}"
    current_snat_mode="${RULE_SNAT_MODE}"

    name="$(prompt_rule_name "${current_name}" "${current_id}")" || return
    proto="$(prompt_protocol "${current_proto}")" || return
    lport="$(prompt_listen_port_value "请输入中转机监听端口" "${proto}" "${current_lport}" "${current_lport}")" || return
    if rule_port_conflict_exists "${lport}" "${proto}" "${current_id}"; then
        err "监听端口 ${lport} 与现有规则冲突。"
        return
    fi
    dip="$(prompt_ip_value "请输入落地机 IP" "${current_dip}")" || return
    dport="$(prompt_port_value "请输入落地机端口" "${current_dport}")" || return
    snat_mode="$(select_rule_snat_mode "${current_snat_mode}")" || return
    prompt_relay_lan_ip_if_needed "${snat_mode}" || return
    enabled="$(prompt_enabled_flag "${current_enabled}")" || return

    rule="$(serialize_rule "${current_id}" "${name}" "${proto}" "${lport}" "${dip}" "${dport}" "${enabled}" "${snat_mode}")"
    echo "即将更新为："
    printf '  - %s\n' "$(describe_rule "${rule}")"
    confirm_yes "确认更新" || {
        info "已取消。"
        return
    }

    backup_managed_files
    RULES[$((choice - 1))]="${rule}"
    apply_relay_mode_to_rules
    save_settings || return
    save_rules || return
    write_nft_conf || return
    apply_or_save_notice "规则已更新。" "规则已保存到托管配置。"
}

do_reorder_rules() {
    local from to source_idx target_idx current i
    local -a remaining=()
    local -a reordered=()
    print_title "调整规则顺序"
    command -v nft &>/dev/null || {
        err "请先执行 [1] 安装 / 初始化。"
        return
    }
    settings_ready || return
    load_rules
    [[ ${#RULES[@]} -gt 1 ]] || {
        info "至少需要 2 条规则才能调整顺序。"
        return
    }

    print_rules_table
    from="$(select_single_rule_index "${#RULES[@]}")" || {
        info "已取消。"
        return
    }
    to="$(prompt_rule_position "${#RULES[@]}" "${from}")" || return
    if [[ "${from}" == "${to}" ]]; then
        info "规则顺序未变化。"
        return
    fi

    source_idx=$((from - 1))
    target_idx=$((to - 1))
    current="${RULES[${source_idx}]}"

    for i in "${!RULES[@]}"; do
        [[ "${i}" -eq "${source_idx}" ]] && continue
        remaining+=("${RULES[$i]}")
    done

    for ((i=0; i<=${#remaining[@]}; i++)); do
        if [[ "${i}" -eq "${target_idx}" ]]; then
            reordered+=("${current}")
        fi
        if [[ "${i}" -lt "${#remaining[@]}" ]]; then
            reordered+=("${remaining[$i]}")
        fi
    done

    echo "即将调整规则顺序："
    printf '  - %s\n' "$(describe_rule "${current}")"
    printf '  - 位置: %s -> %s\n' "${from}" "${to}"
    confirm_yes "确认调整" || {
        info "已取消。"
        return
    }

    backup_managed_files
    RULES=("${reordered[@]}")
    save_rules || return
    write_nft_conf || return
    apply_or_save_notice "规则顺序已更新。" "规则顺序已保存到托管配置。"
}
