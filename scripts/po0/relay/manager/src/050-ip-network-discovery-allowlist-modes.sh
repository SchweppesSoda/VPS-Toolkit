normalize_ipv4_cidr_or_host() {
    local raw="$1"
    local ip prefix value mask network
    raw="$(trim "${raw}")"
    if validate_host_ipv4 "${raw}"; then
        printf '%s/32\n' "${raw}"
        return 0
    fi
    validate_ipv4_cidr "${raw}" || return 1
    ip="${raw%/*}"
    prefix="${raw#*/}"
    value="$(ipv4_to_int "${ip}")" || return 1
    if (( prefix == 0 )); then
        network=0
    else
        mask=$(( (0xffffffff << (32 - prefix)) & 0xffffffff ))
        network=$(( value & mask ))
    fi
    printf '%s/%s\n' "$(int_to_ipv4 "${network}")" "${prefix}"
}

cidr_prefix_length() {
    local cidr="$1"
    [[ "${cidr}" == */* ]] || return 1
    printf '%s\n' "${cidr#*/}"
}

validate_mss() {
    local value="$1"
    [[ "${value}" =~ ^[0-9]+$ ]] || return 1
    (( value >= 536 && value <= 65535 ))
}

is_private_ipv4() {
    local ip="$1"
    local o1 o2
    validate_ip "${ip}" || return 1
    IFS='.' read -r o1 o2 _ _ <<< "${ip}"
    (( o1 == 10 )) && return 0
    (( o1 == 192 && o2 == 168 )) && return 0
    (( o1 == 172 && o2 >= 16 && o2 <= 31 )) && return 0
    (( o1 == 100 && o2 >= 64 && o2 <= 127 )) && return 0
    return 1
}

is_public_ipv4() {
    local ip="$1"
    local o1 o2
    validate_ip "${ip}" || return 1
    is_private_ipv4 "${ip}" && return 1
    IFS='.' read -r o1 o2 _ _ <<< "${ip}"
    (( o1 == 0 )) && return 1
    (( o1 == 10 )) && return 1
    (( o1 == 127 )) && return 1
    (( o1 == 169 && o2 == 254 )) && return 1
    (( o1 == 198 && o2 >= 18 && o2 <= 19 )) && return 1
    (( o1 >= 224 )) && return 1
    return 0
}

extract_ipv4_from_cidr() {
    local cidr="$1"
    printf '%s\n' "${cidr%%/*}"
}

first_ipv4_from_ip_output() {
    local prefer_private="${1:-0}"
    local line cidr ip candidate=""
    while IFS= read -r line; do
        cidr="$(awk '{print $4}' <<< "${line}")"
        [[ -n "${cidr}" ]] || continue
        ip="$(extract_ipv4_from_cidr "${cidr}")"
        validate_ip "${ip}" || continue
        if [[ "${prefer_private}" == "1" ]]; then
            is_private_ipv4 "${ip}" && {
                printf '%s\n' "${ip}"
                return 0
            }
        elif [[ -z "${candidate}" ]]; then
            candidate="${ip}"
        fi
    done
    [[ -n "${candidate}" ]] && printf '%s\n' "${candidate}"
}

get_default_route_interface() {
    local iface
    iface="$(
        ip route show default 2>/dev/null | awk '
            {
                for (i = 1; i <= NF; i++) {
                    if ($i == "dev" && (i + 1) <= NF) {
                        print $(i + 1)
                        exit
                    }
                }
            }
        ' || true
    )"
    [[ -n "${iface}" ]] && printf '%s\n' "${iface}"
}

get_route_src_ipv4() {
    local target="${1:-1.1.1.1}"
    local src
    src="$(
        ip route get "${target}" 2>/dev/null | awk '
            {
                for (i = 1; i <= NF; i++) {
                    if ($i == "src" && (i + 1) <= NF) {
                        print $(i + 1)
                        exit
                    }
                }
            }
        ' || true
    )"
    validate_ip "${src}" && printf '%s\n' "${src}"
}

detect_relay_ip_from_nft_conf() {
    local value
    [[ -f "${NFT_CONF}" ]] || return 1
    value="$(
        awk '
            /^[[:space:]]*define[[:space:]]+RELAY_LAN_IP[[:space:]]*=/ {
                ip = $NF
                gsub(/[[:space:]]/, "", ip)
                print ip
                exit
            }
        ' "${NFT_CONF}" 2>/dev/null || true
    )"
    validate_ip "${value}" && printf '%s\n' "${value}"
}

detect_relay_ip_from_system() {
    local iface ip

    if command -v ip &>/dev/null; then
        iface="$(get_default_route_interface)"
        if [[ -n "${iface}" ]]; then
            ip="$(ip -4 -o addr show dev "${iface}" scope global up 2>/dev/null | first_ipv4_from_ip_output 1 || true)"
            validate_ip "${ip}" && {
                printf '%s\n' "${ip}"
                return 0
            }
        fi

        ip="$(ip -4 -o addr show scope global up 2>/dev/null | first_ipv4_from_ip_output 1 || true)"
        validate_ip "${ip}" && {
            printf '%s\n' "${ip}"
            return 0
        }

        if [[ -n "${iface}" ]]; then
            ip="$(ip -4 -o addr show dev "${iface}" scope global up 2>/dev/null | first_ipv4_from_ip_output 0 || true)"
            validate_ip "${ip}" && {
                printf '%s\n' "${ip}"
                return 0
            }
        fi

        ip="$(ip -4 -o addr show scope global up 2>/dev/null | first_ipv4_from_ip_output 0 || true)"
        validate_ip "${ip}" && {
            printf '%s\n' "${ip}"
            return 0
        }
    fi

    if command -v hostname &>/dev/null; then
        for ip in $(hostname -I 2>/dev/null); do
            validate_ip "${ip}" || continue
            if is_private_ipv4 "${ip}"; then
                printf '%s\n' "${ip}"
                return 0
            fi
        done
        for ip in $(hostname -I 2>/dev/null); do
            validate_ip "${ip}" && {
                printf '%s\n' "${ip}"
                return 0
            }
        done
    fi

    return 1
}

detect_public_ip_from_system() {
    local iface ip

    if command -v ip &>/dev/null; then
        ip="$(get_route_src_ipv4 "1.1.1.1" || true)"
        is_public_ipv4 "${ip}" && {
            printf '%s\n' "${ip}"
            return 0
        }

        iface="$(get_default_route_interface)"
        if [[ -n "${iface}" ]]; then
            ip="$(
                ip -4 -o addr show dev "${iface}" scope global up 2>/dev/null | awk '
                    {
                        split($4, a, "/")
                        print a[1]
                    }
                ' | while IFS= read -r value; do
                    [[ -n "${value}" ]] && printf '%s\n' "${value}"
                done | while IFS= read -r value; do
                    is_public_ipv4 "${value}" && {
                        printf '%s\n' "${value}"
                        break
                    }
                done
            )"
            is_public_ipv4 "${ip}" && {
                printf '%s\n' "${ip}"
                return 0
            }
        fi

        ip="$(
            ip -4 -o addr show scope global up 2>/dev/null | awk '
                {
                    split($4, a, "/")
                    print a[1]
                }
            ' | while IFS= read -r value; do
                [[ -n "${value}" ]] && printf '%s\n' "${value}"
            done | while IFS= read -r value; do
                is_public_ipv4 "${value}" && {
                    printf '%s\n' "${value}"
                    break
                }
            done
        )"
        is_public_ipv4 "${ip}" && {
            printf '%s\n' "${ip}"
            return 0
        }
    fi

    if command -v hostname &>/dev/null; then
        for ip in $(hostname -I 2>/dev/null); do
            is_public_ipv4 "${ip}" && {
                printf '%s\n' "${ip}"
                return 0
            }
        done
    fi

    return 1
}

extract_port_from_addr() {
    local addr="$1"
    addr="${addr##*:}"
    [[ "${addr}" =~ ^[0-9]+$ ]] && printf '%s\n' "${addr}"
}

detect_ssh_ports() {
    local ports=""
    local server_port line port

    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        read -r _ _ _ server_port _ <<< "${SSH_CONNECTION}"
        validate_port "${server_port}" && ports+=" ${server_port}"
    fi

    if command -v ss &>/dev/null; then
        while IFS= read -r line || [[ -n "${line}" ]]; do
            [[ "${line}" == *sshd* ]] || continue
            port="$(extract_port_from_addr "$(awk '{ print $4 }' <<< "${line}")")"
            validate_port "${port}" && ports+=" ${port}"
        done < <(ss -H -tlnp 2>/dev/null || true)

        if [[ -z "$(normalize_port_list "${ports}")" ]]; then
            local_port_in_use 22 tcp && ports+=" 22"
        fi
    fi

    if command -v sshd &>/dev/null; then
        while IFS= read -r port || [[ -n "${port}" ]]; do
            validate_port "${port}" && ports+=" ${port}"
        done < <(sshd -T 2>/dev/null | awk '$1 == "port" { print $2 }' || true)
    fi

    if [[ -f /etc/ssh/sshd_config ]]; then
        while IFS= read -r port || [[ -n "${port}" ]]; do
            validate_port "${port}" && ports+=" ${port}"
        done < <(awk 'tolower($1) == "port" && $0 !~ /^[[:space:]]*#/ { print $2 }' /etc/ssh/sshd_config 2>/dev/null || true)
    fi

    normalize_port_list "${ports}"
}

detect_ssh_client_ip() {
    local client_ip=""
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        read -r client_ip _ _ _ _ <<< "${SSH_CONNECTION}"
    fi
    is_public_ipv4 "${client_ip}" && printf '%s\n' "${client_ip}"
}

ensure_input_firewall_ready() {
    [[ "${MANAGE_INPUT_FIREWALL}" == "1" ]] || return 0
    SSH_PORTS="$(normalize_port_list "${SSH_PORTS}")"
    if [[ -z "${SSH_PORTS}" ]]; then
        SSH_PORTS="$(detect_ssh_ports || true)"
    fi
    SSH_PORTS="$(normalize_port_list "${SSH_PORTS}")"
    [[ -n "${SSH_PORTS}" ]] || {
        err "已启用托管入站防火墙，但无法探测 SSH 端口。请先在中转机参数里设置 SSH_PORTS。"
        return 1
    }
}

detect_public_ip_online() {
    local value=""
    local fetcher=""
    local py_bin=""
    local url
    local -a urls=(
        "https://api.ipify.org"
        "https://ipv4.icanhazip.com"
        "https://ifconfig.me/ip"
    )

    if command -v curl &>/dev/null; then
        fetcher="curl"
    elif command -v wget &>/dev/null; then
        fetcher="wget"
    fi

    if [[ -n "${fetcher}" ]]; then
        for url in "${urls[@]}"; do
            if [[ "${fetcher}" == "curl" ]]; then
                value="$(curl -4fsS --max-time 2 "${url}" 2>/dev/null | tr -d '[:space:]' || true)"
            else
                value="$(wget -4 -qO- --timeout=2 "${url}" 2>/dev/null | tr -d '[:space:]' || true)"
            fi
            is_public_ipv4 "${value}" && {
                printf '%s\n' "${value}"
                return 0
            }
        done
    fi

    if command -v dig &>/dev/null; then
        value="$(dig +short myip.opendns.com @resolver1.opendns.com A 2>/dev/null | awk 'NF { gsub(/"/, "", $0); print; exit }' || true)"
        is_public_ipv4 "${value}" && {
            printf '%s\n' "${value}"
            return 0
        }
        value="$(dig +short TXT o-o.myaddr.l.google.com @ns1.google.com 2>/dev/null | awk 'NF { gsub(/"/, "", $0); print; exit }' || true)"
        is_public_ipv4 "${value}" && {
            printf '%s\n' "${value}"
            return 0
        }
    fi

    if command -v nslookup &>/dev/null; then
        value="$(nslookup myip.opendns.com resolver1.opendns.com 2>/dev/null | awk '/^Address: / { print $2 }' | tail -n 1 | tr -d '[:space:]' || true)"
        is_public_ipv4 "${value}" && {
            printf '%s\n' "${value}"
            return 0
        }
    fi

    if command -v python3 &>/dev/null; then
        py_bin="python3"
    elif command -v python &>/dev/null; then
        py_bin="python"
    fi
    if [[ -n "${py_bin}" ]]; then
        value="$("${py_bin}" -c "import urllib.request; print(urllib.request.urlopen('https://api.ipify.org', timeout=2).read().decode().strip())" 2>/dev/null | tr -d '[:space:]' || true)"
        is_public_ipv4 "${value}" && {
            printf '%s\n' "${value}"
            return 0
        }
    fi

    return 1
}

relay_ip_source_label() {
    case "${RELAY_LAN_IP_SOURCE}" in
        settings)
            printf '已保存配置'
            ;;
        nft_conf)
            printf '从现有 relay 配置回读'
            ;;
        auto)
            printf '自动探测'
            ;;
        *)
            printf '未设置'
            ;;
    esac
}

rules_source_label() {
    local source_name="${1:-${RULES_SOURCE}}"
    case "${source_name}" in
        rules_file)
            printf '规则状态文件'
            ;;
        nft_conf)
            printf '现有 relay 配置回读'
            ;;
        live_table)
            printf '当前已加载 nftables 表'
            ;;
        ruleset)
            printf '完整 nft ruleset 扫描'
            ;;
        *)
            printf '未读取到规则'
            ;;
    esac
}

clear_discovery_cache() {
    DISCOVERED_RULES=()
    DISCOVERED_RULES_SOURCE="none"
    DISCOVERED_RULE_COUNT=0
    DISCOVERY_CACHE_READY="0"
}

join_with_comma() {
    local out=""
    local item
    for item in "$@"; do
        [[ -n "${item}" ]] || continue
        if [[ -z "${out}" ]]; then
            out="${item}"
        else
            out="${out}, ${item}"
        fi
    done
    printf '%s\n' "${out}"
}

normalize_region_ids() {
    local raw="$1"
    local id
    local out=""
    local seen=" "
    for id in ${raw//,/ }; do
        id="$(trim "${id}")"
        [[ -n "${id}" ]] || continue
        [[ "${id}" =~ ^[A-Za-z0-9._-]+$ ]] || continue
        [[ "${seen}" == *" ${id} "* ]] && continue
        seen+="${id} "
        if [[ -z "${out}" ]]; then
            out="${id}"
        else
            out+=" ${id}"
        fi
    done
    printf '%s\n' "${out}"
}

normalize_src_allowlist_mode() {
    local value
    value="$(trim "${1:-}")"
    value="${value,,}"
    case "${value}" in
        ""|trusted_dynamic|trusted-dynamic|dynamic|trusted|custom|manual|device|devices)
            printf 'trusted_dynamic\n'
            ;;
        manual_only|manual-only|manualonly|static|static_only|static-only)
            printf 'manual_only\n'
            ;;
        region_plus_trusted|region-plus-trusted|region_trusted|region+trusted|region_custom|custom_region|both|mixed|region+custom|custom+region)
            printf 'region_plus_trusted\n'
            ;;
        region_only|region-only|region|regions|iplist|geo)
            printf 'region_only\n'
            ;;
        custom_sources|custom-sources|sources|advanced)
            printf 'custom_sources\n'
            ;;
        *)
            return 1
            ;;
    esac
}

src_allowlist_mode_default_sources() {
    case "${1:-${SRC_ALLOWLIST_MODE}}" in
        manual_only)
            printf 'manual\n'
            ;;
        trusted_dynamic)
            printf 'manual,ddns,client_ip,ssh_report,webauth,learned\n'
            ;;
        region_plus_trusted)
            printf 'region,manual,ddns,client_ip,ssh_report,webauth,learned\n'
            ;;
        region_only)
            printf 'region\n'
            ;;
        custom_sources)
            load_allowlist_sets 2>/dev/null || true
            local set
            for set in "${ALLOWLIST_SETS[@]}"; do
                parse_allowlist_set_line "${set}" || continue
                if [[ "${ALLOWLIST_SET_ID}" == "default" ]]; then
                    printf '%s\n' "${ALLOWLIST_SET_SOURCES}"
                    return 0
                fi
            done
            printf 'manual,ddns,client_ip,ssh_report,webauth,learned\n'
            ;;
        *)
            printf 'manual,ddns,client_ip,ssh_report,webauth,learned\n'
            ;;
    esac
}

source_type_allowed_by_mode() {
    local source_type="$1"
    local mode="${2:-${SRC_ALLOWLIST_MODE}}"
    local sources source
    source_type="$(normalize_allowlist_entry_source_type "${source_type}")" || return 1
    sources="$(src_allowlist_mode_default_sources "${mode}")"
    for source in ${sources//,/ }; do
        [[ "${source}" == "${source_type}" ]] && return 0
    done
    return 1
}

sanitize_allowlist_set_text() {
    local value="$1"
    value="${value//$'\t'/ }"
    value="${value//$'\r'/ }"
    value="${value//$'\n'/ }"
    value="${value//|//}"
    value="$(trim "${value}")"
    [[ ${#value} -le 96 ]] || value="${value:0:96}"
    printf '%s\n' "${value}"
}

validate_allowlist_set_id() {
    local id="$1"
    [[ "${id}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$ ]]
}

normalize_allowlist_set_scope() {
    local value
    value="$(trim "${1:-}")"
    value="${value,,}"
    case "${value}" in
        ""|public|global|common|default|all)
            printf 'public\n'
            ;;
        ports|port|custom|per_port|per-port)
            printf 'ports\n'
            ;;
        *)
            return 1
            ;;
    esac
}

normalize_allowlist_set_ports() {
    local raw="${1:-}"
    local scope="${2:-ports}"
    local token proto port out="" seen=" "

    if [[ "${scope}" == "public" ]]; then
        printf '*\n'
        return 0
    fi

    raw="${raw//,/ }"
    raw="${raw//;/ }"
    for token in ${raw}; do
        token="$(trim "${token}")"
        [[ -n "${token}" ]] || continue
        if [[ "${token}" == */* ]]; then
            proto="${token%%/*}"
            port="${token#*/}"
        else
            proto="both"
            port="${token}"
        fi
        proto="$(normalize_proto "${proto}")" || return 1
        validate_port "${port}" || return 1
        token="${proto}/${port}"
        [[ "${seen}" == *" ${token} "* ]] && continue
        seen+="${token} "
        if [[ -z "${out}" ]]; then
            out="${token}"
        else
            out+=",${token}"
        fi
    done
    [[ -n "${out}" ]] || return 1
    printf '%s\n' "${out}"
}
