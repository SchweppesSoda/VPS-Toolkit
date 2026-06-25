write_nft_allowlist_set() {
    local tmp="$1"
    local cache="${2:-${SRC_ALLOWLIST_CACHE}}"
    local line set_name
    [[ -s "${cache}" ]] || return 1
    set_name="$(default_allowlist_nft_set_name)"
    cat >> "${tmp}" <<EOF
    set ${set_name} {
        type ipv4_addr
        flags interval
        auto-merge
        elements = {
EOF
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="$(trim "${line}")"
        [[ -n "${line}" ]] || continue
        printf '            %s,\n' "${line}" >> "${tmp}"
    done < "${cache}"
    cat >> "${tmp}" <<'EOF'
        }
    }

EOF
}

enabled_rule_ports_set() {
    local want_proto="$1"
    local rule port out="" seen=" "
    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        [[ "${RULE_ENABLED}" == "1" ]] || continue
        case "${want_proto}:${RULE_PROTO}" in
            tcp:tcp|tcp:both|udp:udp|udp:both)
                port="${RULE_LPORT}"
                ;;
            *)
                continue
                ;;
        esac
        [[ "${seen}" == *" ${port} "* ]] && continue
        seen+="${port} "
        if [[ -z "${out}" ]]; then
            out="${port}"
        else
            out+=", ${port}"
        fi
    done
    printf '%s\n' "${out}"
}

enabled_rule_count() {
    local rule count=0
    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        [[ "${RULE_ENABLED}" == "1" ]] || continue
        ((count++))
    done
    printf '%s\n' "${count}"
}

relay_lan_snat_required() {
    local rule
    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        [[ "${RULE_ENABLED}" == "1" ]] || continue
        [[ "${RULE_SNAT_MODE}" == "relay_lan" ]] && return 0
    done
    return 1
}

apply_relay_mode_to_rules() {
    local idx rule snat_mode
    [[ "${RELAY_MODE}" == "mixed" ]] && return 0
    snat_mode="$(relay_mode_default_snat_mode)"
    for idx in "${!RULES[@]}"; do
        rule="${RULES[$idx]}"
        parse_rule "${rule}"
        RULES[$idx]="$(serialize_rule "${RULE_ID}" "${RULE_NAME}" "${RULE_PROTO}" "${RULE_LPORT}" "${RULE_DIP}" "${RULE_DPORT}" "${RULE_ENABLED}" "${snat_mode}")"
    done
}

validate_managed_listen_ports() {
    local rule
    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        [[ "${RULE_ENABLED}" == "1" ]] || continue
        ensure_listen_port_allowed "${RULE_LPORT}" "${RULE_PROTO}" || return 1
    done
}

get_unmanaged_runtime_dnat_summary() {
    local text=""
    local current_family=""
    local current_table=""
    local line parsed key lport dip dport tables
    local -A seen_rules=()
    local -A seen_tables=()

    command -v nft &>/dev/null || return 1
    text="$(nft list ruleset 2>/dev/null || true)"
    [[ -n "${text}" ]] || return 1

    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ ^table[[:space:]]+([[:alnum:]_]+)[[:space:]]+([^[:space:]]+)[[:space:]]*\{ ]]; then
            current_family="${BASH_REMATCH[1]}"
            current_table="${BASH_REMATCH[2]}"
            continue
        fi

        parsed="$(parse_rule_from_line "${line}" || true)"
        [[ -n "${parsed}" ]] || continue
        [[ "${current_family}" == "ip" || "${current_family}" == "inet" ]] || continue
        [[ "${current_table}" == "${NAT_TABLE}" ]] && continue

        IFS='|' read -r _ lport dip dport _ <<< "${parsed}"
        key="${current_table}|${lport}|${dip}|${dport}"
        seen_rules["${key}"]=1
        seen_tables["${current_table}"]=1
    done <<< "${text}"

    [[ ${#seen_rules[@]} -gt 0 ]] || return 1
    tables="$(join_with_comma "${!seen_tables[@]}")"
    printf '%s|%s\n' "${#seen_rules[@]}" "${tables}"
}

print_runtime_drift_hint() {
    local summary count tables
    summary="$(get_unmanaged_runtime_dnat_summary || true)"
    [[ -n "${summary}" ]] || return 0
    IFS='|' read -r count tables <<< "${summary}"
    warn "发现 ${count} 条脚本未管理的 DNAT 转发规则：它们正在系统里生效，但不在本脚本的规则列表中。"
    [[ -n "${tables}" ]] && info "所在 nft 表：${tables}"
    info "常见原因：旧脚本、手动 nft 命令、其它面板或防火墙工具留下了转发规则。"
    info "处理方式：想保留就可以先不管；想交给本脚本管理，用 [9] 导入当前 nft 运行时规则；确认不要了，再用 [1] 初始化接管或手动删除对应表。"
}

public_ip_source_label() {
    case "${PUBLIC_IP_SOURCE}" in
        system)
            printf '已缓存（本机路由或网卡）'
            ;;
        online)
            printf '已缓存（公网服务查询）'
            ;;
        manual)
            printf '手动设置'
            ;;
        settings)
            printf '已缓存配置'
            ;;
        *)
            printf '未探测到'
            ;;
    esac
}

refresh_relay_lan_ip() {
    RELAY_LAN_IP="$(detect_relay_ip_from_system 2>/dev/null || true)"
    if validate_host_ipv4 "${RELAY_LAN_IP}"; then
        RELAY_LAN_IP_SOURCE="auto"
        return 0
    fi
    RELAY_LAN_IP=""
    RELAY_LAN_IP_SOURCE="none"
    return 1
}
