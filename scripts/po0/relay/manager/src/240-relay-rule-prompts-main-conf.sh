prompt_settings() {
    local input ans relay_ip_prompt input_lower
    load_settings
    while true; do
        if [[ -n "${NODE_NAME}" ]]; then
            input="$(read_prompt "本机名称 / 导出前缀 [当前: ${NODE_NAME}，回车保留，输入 - 清空]: ")" || input=""
            input="$(trim "${input}")"
            [[ -n "${input}" ]] || input="${NODE_NAME}"
            [[ "${input}" == "-" ]] && input=""
        else
            input="$(read_prompt "本机名称 / 导出前缀（例如 PO0XX，回车不设置）: ")" || input=""
            input="$(trim "${input}")"
        fi
        validate_node_name "${input}" && {
            NODE_NAME="${input}"
            break
        }
        err "本机名称只能使用字母、数字、点、下划线、短横线，最长 32 个字符。"
    done
    RELAY_MODE="$(prompt_relay_mode "${RELAY_MODE}")" || return
    refresh_cached_ips_for_mode || true
    if [[ "${RELAY_LAN_IP_SOURCE}" == "auto" ]]; then
        info "已自动探测到内网 IP：${RELAY_LAN_IP}"
    elif [[ "${RELAY_LAN_IP_SOURCE}" == "nft_conf" ]]; then
        info "已从现有 relay 配置回读到内网 IP：${RELAY_LAN_IP}"
    fi
    if relay_mode_uses_lan; then
        while true; do
            if [[ "${RELAY_MODE}" == "lan" ]]; then
                if validate_host_ipv4 "${RELAY_LAN_IP}"; then
                    relay_ip_prompt="请输入中转机内网 IP（回车保留，输入 auto 或 none 自动探测）"
                else
                    relay_ip_prompt="请输入中转机内网 IP（必填，输入 auto 或 none 自动探测）"
                fi
            elif validate_host_ipv4 "${RELAY_LAN_IP}"; then
                relay_ip_prompt="请输入中转机内网 IP（回车保留，输入 auto 自动探测，输入 none 清空/跳过）"
            else
                relay_ip_prompt="请输入中转机内网 IP（回车或 none 跳过，输入 auto 自动探测）"
            fi
            input="$(prompt_with_default "${relay_ip_prompt}" "${RELAY_LAN_IP}")"
            input="$(trim "${input}")"
            input_lower="${input,,}"
            if [[ "${input_lower}" == "auto" || "${input_lower}" == "detect" || "${input_lower}" == "refresh" || ( "${RELAY_MODE}" == "lan" && ( -z "${input}" || "${input_lower}" == "none" ) ) ]]; then
                if refresh_relay_lan_ip; then
                    info "已自动探测并使用中转机内网 IP：${RELAY_LAN_IP}"
                    break
                fi
                if [[ "${RELAY_MODE}" == "lan" ]]; then
                    err "自动探测中转机内网 IP 失败；纯内网/无感内网模式必须手动输入有效内网 IP。"
                    continue
                fi
                warn "自动探测中转机内网 IP 失败，已跳过内网 IP。"
                RELAY_LAN_IP=""
                RELAY_LAN_IP_SOURCE="none"
                break
            fi
            if [[ -z "${input}" || "${input_lower}" == "none" ]]; then
                if [[ "${RELAY_MODE}" == "lan" ]]; then
                    err "纯内网/无感内网模式必须设置中转机内网 IP；可输入 auto 自动探测，或手动输入有效内网 IP。"
                    continue
                fi
                RELAY_LAN_IP=""
                RELAY_LAN_IP_SOURCE="none"
                break
            fi
            validate_host_ipv4 "${input}" && {
                RELAY_LAN_IP="${input}"
                RELAY_LAN_IP_SOURCE="settings"
                break
            }
            err "IP 地址无效，不能使用 0.0.0.0、127.0.0.1、169.254.x.x 或组播/保留地址。"
        done
    else
        RELAY_LAN_IP=""
        RELAY_LAN_IP_SOURCE="none"
    fi
    if [[ "${ENABLE_MSS_CLAMP}" == "1" ]]; then
        ans="$(read_prompt "是否保留 MSS 修正（默认开启）[Y/n]: ")" || ans=""
        [[ "${ans}" =~ ^[Nn]$ ]] && {
            ENABLE_MSS_CLAMP="0"
            return 0
        }
    else
        ans="$(read_prompt "是否开启 MSS 修正 [y/N]: ")" || ans=""
        [[ "${ans}" =~ ^[Yy]$ ]] || {
            ENABLE_MSS_CLAMP="0"
            return 0
        }
    fi
    ENABLE_MSS_CLAMP="1"
    while true; do
        input="$(prompt_with_default "请输入 MSS 值" "${MSS_VALUE}")"
        validate_mss "${input}" && {
            MSS_VALUE="${input}"
            return 0
        }
        err "MSS 值无效，请输入 536-65535。"
    done
}

prompt_input_firewall_settings() {
    local ans input
    SSH_PORTS="$(normalize_port_list "${SSH_PORTS}")"
    [[ -n "${SSH_PORTS}" ]] || SSH_PORTS="$(detect_ssh_ports || true)"
    SSH_PORTS="$(normalize_port_list "${SSH_PORTS}")"

    if [[ "${MANAGE_INPUT_FIREWALL}" == "1" ]]; then
        ans="$(read_prompt "是否接管入站防火墙（保留 SSH，其它未托管端口默认 drop）[Y/n]: ")" || ans=""
        [[ "${ans}" =~ ^[Nn]$ ]] && MANAGE_INPUT_FIREWALL="0" || MANAGE_INPUT_FIREWALL="1"
    else
        ans="$(read_prompt "是否接管入站防火墙（保留 SSH，其它未托管端口默认 drop）[y/N]: ")" || ans=""
        [[ "${ans}" =~ ^[Yy]$ ]] && MANAGE_INPUT_FIREWALL="1" || MANAGE_INPUT_FIREWALL="0"
    fi

    if [[ "${MANAGE_INPUT_FIREWALL}" == "1" ]]; then
        while true; do
            input="$(prompt_with_default "请输入 SSH 端口，多个用空格或逗号分隔" "${SSH_PORTS}")"
            input="$(normalize_port_list "${input}")"
            [[ -n "${input}" ]] && {
                SSH_PORTS="${input}"
                return 0
            }
            err "SSH 端口不能为空，否则默认 drop 入站会导致无法登录。"
        done
    fi
}

prompt_protocol() {
    local current="${1:-both}"
    local choice
    while true; do
        choice="$(read_prompt "选择协议 [1=tcp+udp, 2=tcp, 3=udp，当前: $(proto_to_label "${current}")] : ")" || return 1
        choice="$(trim "${choice}")"
        case "${choice,,}" in
            "" )
                printf '%s\n' "${current}"
                return 0
                ;;
            1|both|all|tcp+udp|tcpudp)
                printf 'both\n'
                return 0
                ;;
            2|tcp)
                printf 'tcp\n'
                return 0
                ;;
            3|udp)
                printf 'udp\n'
                return 0
                ;;
        esac
        err "协议只能选择 1 / 2 / 3，或直接输入 tcp、udp、both。"
    done
}

prompt_snat_mode() {
    local current="${1:-relay_lan}"
    local choice
    current="$(normalize_snat_mode "${current}" 2>/dev/null || printf 'relay_lan')"
    while true; do
        echo "选择这条规则的回程模式：" >&2
        echo "  1) 内网回源：适合内网/无感内网目标" >&2
        echo "  2) 公网出口：适合普通公网目标" >&2
        echo "  3) 透明转发：保留客户端真实来源，要求目标机已有回程路由" >&2
        choice="$(read_prompt "请选择回程模式 [1=内网回源, 2=公网出口, 3=透明转发；当前: $(snat_mode_to_label "${current}")]: ")" || return 1
        choice="$(trim "${choice}")"
        case "${choice,,}" in
            "")
                printf '%s\n' "${current}"
                return 0
                ;;
            1|relay|relay_lan|lan|inner|private|po0|po0_lan)
                printf 'relay_lan\n'
                return 0
                ;;
            2|masq|masquerade|public|wan|egress|route)
                printf 'masquerade\n'
                return 0
                ;;
            3|none|no|off|keep|transparent)
                warn "透明转发不会改写来源地址，目标机必须已有正确回程路由；大多数中转场景不需要它。" >&2
                confirm_yes "确认使用透明转发" || continue
                printf 'none\n'
                return 0
                ;;
        esac
        err "回程方式只能选择 1 / 2 / 3。"
    done
}

select_rule_snat_mode() {
    local current="${1:-}"
    if [[ "${RELAY_MODE}" == "mixed" ]]; then
        [[ -n "${current}" ]] || current="$(relay_mode_default_snat_mode)"
        prompt_snat_mode "${current}"
    else
        relay_mode_default_snat_mode
    fi
}

prompt_relay_lan_ip_if_needed() {
    local snat_mode="$1"
    local input input_lower
    [[ "${snat_mode}" == "relay_lan" ]] || return 0
    validate_host_ipv4 "${RELAY_LAN_IP}" && return 0

    warn "内网/无感内网 SNAT 模式需要中转机内网 IP。"
    if refresh_relay_lan_ip; then
        info "已自动探测并使用中转机内网 IP：${RELAY_LAN_IP}"
        return 0
    fi
    warn "自动探测中转机内网 IP 失败，请手动输入。"
    while true; do
        input="$(prompt_with_default "请输入中转机内网 IP（输入 auto 或 none 重新自动探测）" "${RELAY_LAN_IP}")"
        input="$(trim "${input}")"
        input_lower="${input,,}"
        if [[ -z "${input}" || "${input_lower}" == "auto" || "${input_lower}" == "none" || "${input_lower}" == "detect" || "${input_lower}" == "refresh" ]]; then
            if refresh_relay_lan_ip; then
                info "已自动探测并使用中转机内网 IP：${RELAY_LAN_IP}"
                return 0
            fi
            err "自动探测中转机内网 IP 失败；请手动输入有效内网 IP。"
            continue
        fi
        validate_host_ipv4 "${input}" && {
            RELAY_LAN_IP="${input}"
            RELAY_LAN_IP_SOURCE="settings"
            return 0
        }
        err "IP 地址无效，不能使用 0.0.0.0、127.0.0.1、169.254.x.x 或组播/保留地址。"
    done
}

prompt_enabled_flag() {
    local current="${1:-1}"
    local choice
    while true; do
        choice="$(read_prompt "规则状态 [1=启用, 2=停用，当前: $([[ "${current}" == "1" ]] && printf '启用' || printf '停用')] : ")" || return 1
        choice="$(trim "${choice}")"
        case "${choice}" in
            "")
                printf '%s\n' "${current}"
                return 0
                ;;
            1|on|ON|enable|ENABLE)
                printf '1\n'
                return 0
                ;;
            2|off|OFF|disable|DISABLE)
                printf '0\n'
                return 0
                ;;
        esac
        err "状态只能选择 1 或 2。"
    done
}

prompt_rule_name() {
    local default="$1"
    local skip_id="${2-}"
    local input
    while true; do
        input="$(prompt_with_default "规则名称" "${default}")"
        input="$(trim "${input}")"
        validate_rule_name "${input}" || {
            err "规则名称不能为空，不能包含 |，长度不能超过 48 个字符。"
            continue
        }
        rule_name_exists "${input}" "${skip_id}" && {
            err "规则名称已存在，请换一个。"
            continue
        }
        printf '%s\n' "${input}"
        return 0
    done
}

prompt_port_value() {
    local prompt="$1"
    local default="${2-}"
    local input
    while true; do
        input="$(prompt_with_default "${prompt}" "${default}")"
        input="$(trim "${input}")"
        validate_port "${input}" && {
            printf '%s\n' "${input}"
            return 0
        }
        err "端口无效。"
    done
}

prompt_listen_port_value() {
    local prompt="$1"
    local proto="$2"
    local default="${3-}"
    local allow_existing="${4-}"
    local input
    while true; do
        input="$(prompt_with_default "${prompt}" "${default}")"
        input="$(trim "${input}")"
        ensure_listen_port_allowed "${input}" "${proto}" || continue
        if [[ -n "${allow_existing}" && "${input}" == "${allow_existing}" ]]; then
            printf '%s\n' "${input}"
            return 0
        fi
        listen_port_in_forward_range "${input}" && {
            printf '%s\n' "${input}"
            return 0
        }
        err "监听端口必须在 ${FORWARD_PORT_MIN}-${FORWARD_PORT_MAX} 范围内；既有旧规则保持原端口时可继续兼容。"
    done
}

random_forward_listen_port() {
    local span=$((FORWARD_PORT_MAX - FORWARD_PORT_MIN + 1))
    local n

    if command -v shuf &>/dev/null; then
        shuf -i "${FORWARD_PORT_MIN}-${FORWARD_PORT_MAX}" -n 1
        return 0
    fi

    if command -v od &>/dev/null && [[ -r /dev/urandom ]]; then
        n="$(od -An -N4 -tu4 /dev/urandom 2>/dev/null | tr -d '[:space:]')"
        if [[ "${n}" =~ ^[0-9]+$ ]]; then
            printf '%s\n' "$((FORWARD_PORT_MIN + (n % span)))"
            return 0
        fi
    fi

    printf '%s\n' "$((FORWARD_PORT_MIN + (RANDOM % span)))"
}

choose_forward_listen_port() {
    local proto="${1:-both}"
    local port

    for _ in $(seq 1 "${FORWARD_PORT_RANDOM_TRIES}"); do
        port="$(random_forward_listen_port)"
        ensure_new_listen_port_allowed "${port}" "${proto}" >/dev/null 2>&1 || continue
        rule_port_conflict_exists "${port}" "${proto}" && continue
        printf '%s\n' "${port}"
        return 0
    done

    for ((port = FORWARD_PORT_MIN; port <= FORWARD_PORT_MAX; port++)); do
        ensure_new_listen_port_allowed "${port}" "${proto}" >/dev/null 2>&1 || continue
        rule_port_conflict_exists "${port}" "${proto}" && continue
        printf '%s\n' "${port}"
        return 0
    done

    return 1
}

prompt_ip_value() {
    local prompt="$1"
    local default="${2-}"
    local input
    while true; do
        input="$(prompt_with_default "${prompt}" "${default}")"
        input="$(trim "${input}")"
        validate_host_ipv4 "${input}" && {
            printf '%s\n' "${input}"
            return 0
        }
        err "IP 地址无效，不能使用 0.0.0.0、127.0.0.1、169.254.x.x 或组播/保留地址。"
    done
}

describe_rule() {
    parse_rule "$1"
    printf '%s [%s] :%s -> %s:%s (%s, %s)' \
        "${RULE_NAME}" \
        "$(proto_to_label "${RULE_PROTO}")" \
        "${RULE_LPORT}" \
        "${RULE_DIP}" \
        "${RULE_DPORT}" \
        "$([[ "${RULE_ENABLED}" == "1" ]] && printf '启用' || printf '停用')" \
        "$(snat_mode_to_label "${RULE_SNAT_MODE}")"
}

print_rule_line() {
    local idx="$1"
    parse_rule "$2"
    printf '%-4s %-8b %-10s :%-8s %-21s %-12s %s\n' \
        "${idx}." \
        "$(enabled_to_short "${RULE_ENABLED}")" \
        "$(proto_to_label "${RULE_PROTO}")" \
        "${RULE_LPORT}" \
        "${RULE_DIP}:${RULE_DPORT}" \
        "$(snat_mode_to_short "${RULE_SNAT_MODE}")" \
        "${RULE_NAME}"
}

print_rules_table() {
    local idx=1
    local rule
    refresh_rule_counts
    if [[ ${#RULES[@]} -eq 0 ]]; then
        info "当前没有转发规则。"
        return 0
    fi
    printf '%b%-4s %-8s %-10s %-10s %-21s %-12s %s%b\n' \
        "${C_BOLD}" "#" "状态" "协议" "监听端口" "目标地址" "回程模式" "规则名称" "${C_RESET}"
    print_divider
    for rule in "${RULES[@]}"; do
        print_rule_line "${idx}" "${rule}"
        ((idx++))
    done
}

select_single_rule_index() {
    local max="$1"
    local choice
    while true; do
        choice="$(read_prompt "请输入规则序号 [1-${max}, 0 取消]: ")" || return 1
        choice="$(trim "${choice}")"
        if [[ -z "${choice}" || "${choice}" == "0" ]]; then
            return 1
        fi
        if [[ "${choice}" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= max )); then
            printf '%s\n' "${choice}"
            return 0
        fi
        err "规则序号无效。"
    done
}

prompt_rule_position() {
    local max="$1"
    local default="${2-}"
    local choice
    while true; do
        choice="$(prompt_with_default "请输入目标位置 [1-${max}]" "${default}")"
        choice="$(trim "${choice}")"
        if [[ "${choice}" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= max )); then
            printf '%s\n' "${choice}"
            return 0
        fi
        err "目标位置无效。"
    done
}

declare -a SELECTED_INDICES=()

parse_selection() {
    local raw="$1"
    local max="$2"
    local token start end i
    local -a tokens=()
    local -A seen=()

    raw="${raw// /}"
    [[ -n "${raw}" ]] || return 1

    SELECTED_INDICES=()
    IFS=',' read -r -a tokens <<< "${raw}"
    for token in "${tokens[@]}"; do
        [[ -n "${token}" ]] || return 1
        if [[ "${token}" =~ ^[0-9]+-[0-9]+$ ]]; then
            start="${token%-*}"
            end="${token#*-}"
            (( start >= 1 && end >= start && end <= max )) || return 1
            for ((i=start; i<=end; i++)); do
                if [[ -z "${seen[$i]+x}" ]]; then
                    SELECTED_INDICES+=("${i}")
                    seen[$i]=1
                fi
            done
        elif [[ "${token}" =~ ^[0-9]+$ ]]; then
            (( token >= 1 && token <= max )) || return 1
            if [[ -z "${seen[$token]+x}" ]]; then
                SELECTED_INDICES+=("${token}")
                seen[$token]=1
            fi
        else
            return 1
        fi
    done

    [[ ${#SELECTED_INDICES[@]} -gt 0 ]]
}

print_selected_rules() {
    local idx
    for idx in "${SELECTED_INDICES[@]}"; do
        printf '  - %s\n' "$(describe_rule "${RULES[$((idx - 1))]}")"
    done
}

unique_dest_ip_set() {
    local seen=" "
    local out=""
    local rule
    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        [[ "${RULE_ENABLED}" == "1" ]] || continue
        [[ "${RULE_PROTO}" == "udp" ]] && continue
        if [[ "${seen}" != *" ${RULE_DIP} "* ]]; then
            [[ -n "${out}" ]] && out+=", "
            out+="${RULE_DIP}"
            seen+=" ${RULE_DIP} "
        fi
    done
    printf '%s' "${out}"
}

print_rule_counters() {
    local nft_text line current_chain name packets bytes
    local packets_value bytes_value
    local -A rule_packets=()
    local -A rule_bytes=()
    local rule

    command -v nft &>/dev/null || return 0
    nft_text="$(nft list table ip "${NAT_TABLE}" 2>/dev/null || true)"
    [[ -n "${nft_text}" ]] || {
        warn "当前未读取到 NAT 表规则计数。"
        return 0
    }

    current_chain=""
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ chain[[:space:]]+([A-Za-z0-9_-]+)[[:space:]]+\{ ]]; then
            current_chain="${BASH_REMATCH[1]}"
            continue
        fi
        [[ "${current_chain}" == "prerouting" ]] || continue
        [[ "${line}" =~ comment[[:space:]]+\"([^\"]+)\" ]] || continue
        name="${BASH_REMATCH[1]}"
        packets_value=0
        bytes_value=0
        if [[ "${line}" =~ counter[[:space:]]+packets[[:space:]]+([0-9]+)[[:space:]]+bytes[[:space:]]+([0-9]+) ]]; then
            packets_value="${BASH_REMATCH[1]}"
            bytes_value="${BASH_REMATCH[2]}"
        fi
        rule_packets["${name}"]="${packets_value}"
        rule_bytes["${name}"]="${bytes_value}"
    done <<< "${nft_text}"

    echo "规则命中计数:"
    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        packets="${rule_packets[${RULE_NAME}]:-0}"
        bytes="${rule_bytes[${RULE_NAME}]:-0}"
        printf '  - %-20s packets=%s bytes=%s\n' "${RULE_NAME}" "${packets}" "${bytes}"
    done
}

escape_nft_comment() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '%s' "${value}"
}

write_main_conf() {
    local tmp
    make_temp_file "${MAIN_CONF}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    cat > "${tmp}" <<'EOF'
#!/usr/sbin/nft -f
flush ruleset
include "/etc/nftables.d/*.conf"
EOF
    mv -f "${tmp}" "${MAIN_CONF}"
}
