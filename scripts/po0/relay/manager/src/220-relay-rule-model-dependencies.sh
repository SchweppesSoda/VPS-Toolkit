refresh_public_ip() {
    PUBLIC_IP="$(detect_public_ip_from_system 2>/dev/null || true)"
    if is_public_ipv4 "${PUBLIC_IP}"; then
        PUBLIC_IP_SOURCE="system"
    else
        info "本机路由或网卡未读到公网 IP，开始查询公网服务。"
        PUBLIC_IP="$(detect_public_ip_online 2>/dev/null || true)"
        if is_public_ipv4 "${PUBLIC_IP}"; then
            PUBLIC_IP_SOURCE="online"
        else
            PUBLIC_IP=""
            PUBLIC_IP_SOURCE="none"
            PUBLIC_IP_CACHE=""
            PUBLIC_IP_CACHE_SOURCE="none"
            PUBLIC_IP_PROBE_DONE="1"
            return 1
        fi
    fi
    PUBLIC_IP_CACHE="${PUBLIC_IP}"
    PUBLIC_IP_CACHE_SOURCE="${PUBLIC_IP_SOURCE}"
    PUBLIC_IP_PROBE_DONE="1"
    return 0
}

unique_loaded_rule_name() {
    local requested="$1"
    local lport="$2"
    local base candidate suffix=2

    requested="$(trim "${requested}")"
    if validate_rule_name "${requested}"; then
        base="${requested}"
    else
        base="relay-${lport}"
    fi

    candidate="${base}"
    while rule_name_exists "${candidate}"; do
        candidate="${base}-${suffix}"
        ((suffix++))
    done
    printf '%s\n' "${candidate}"
}

parse_rule_from_line() {
    local line="$1"
    local proto="both"
    local name=""
    local port=""
    local dst_ip=""
    local dst_port=""

    [[ "${line}" == *dnat* ]] || return 1

    if [[ "${line}" =~ ^[[:space:]]*tcp[[:space:]]+dport[[:space:]]+([0-9]+)[[:space:]]+dnat[[:space:]]+(ip[[:space:]]+)?to[[:space:]]+([0-9.]+):([0-9]+) ]]; then
        proto="tcp"
        port="${BASH_REMATCH[1]}"
        dst_ip="${BASH_REMATCH[3]}"
        dst_port="${BASH_REMATCH[4]}"
    elif [[ "${line}" =~ ^[[:space:]]*udp[[:space:]]+dport[[:space:]]+([0-9]+)[[:space:]]+dnat[[:space:]]+(ip[[:space:]]+)?to[[:space:]]+([0-9.]+):([0-9]+) ]]; then
        proto="udp"
        port="${BASH_REMATCH[1]}"
        dst_ip="${BASH_REMATCH[3]}"
        dst_port="${BASH_REMATCH[4]}"
    elif [[ "${line}" =~ meta[[:space:]]+l4proto[[:space:]]+\{[[:space:]]*tcp,[[:space:]]*udp[[:space:]]*\} ]]; then
        proto="both"
    elif [[ "${line}" =~ meta[[:space:]]+l4proto[[:space:]]+tcp([[:space:]]|$) ]] || [[ "${line}" =~ (^|[[:space:]])tcp[[:space:]]+dport[[:space:]]+ ]]; then
        proto="tcp"
    elif [[ "${line}" =~ meta[[:space:]]+l4proto[[:space:]]+udp([[:space:]]|$) ]] || [[ "${line}" =~ (^|[[:space:]])udp[[:space:]]+dport[[:space:]]+ ]]; then
        proto="udp"
    fi

    if [[ -z "${port}" && "${line}" =~ th[[:space:]]+dport[[:space:]]+([0-9]+) ]]; then
        port="${BASH_REMATCH[1]}"
    elif [[ -z "${port}" && "${line}" =~ (tcp|udp)[[:space:]]+dport[[:space:]]+([0-9]+) ]]; then
        port="${BASH_REMATCH[2]}"
    fi

    if [[ -z "${dst_ip}" && "${line}" =~ dnat[[:space:]]+(ip[[:space:]]+)?to[[:space:]]+([0-9.]+):([0-9]+) ]]; then
        dst_ip="${BASH_REMATCH[2]}"
        dst_port="${BASH_REMATCH[3]}"
    fi

    if [[ "${line}" =~ comment[[:space:]]+\"([^\"]+)\" ]]; then
        name="${BASH_REMATCH[1]}"
    fi

    [[ -n "${port}" && -n "${dst_ip}" && -n "${dst_port}" ]] || return 1
    printf '%s|%s|%s|%s|%s\n' "${proto}" "${port}" "${dst_ip}" "${dst_port}" "${name}"
}

append_loaded_rule() {
    local proto="$1"
    local lport="$2"
    local dip="$3"
    local dport="$4"
    local name="$5"
    local idx=0 rule merged_name

    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        if [[ "${RULE_LPORT}" == "${lport}" && "${RULE_DIP}" == "${dip}" && "${RULE_DPORT}" == "${dport}" ]]; then
            merged_name="${RULE_NAME}"
            [[ -n "${name}" ]] && merged_name="${name}"
            if [[ "${RULE_PROTO}" != "${proto}" ]]; then
                RULE_PROTO="both"
            fi
            RULE_NAME="${merged_name}"
            RULES[$idx]="$(serialize_rule "${RULE_ID}" "${RULE_NAME}" "${RULE_PROTO}" "${RULE_LPORT}" "${RULE_DIP}" "${RULE_DPORT}" "${RULE_ENABLED}" "${RULE_SNAT_MODE}")"
            return 0
        fi
        ((idx++))
    done

    name="$(unique_loaded_rule_name "${name}" "${lport}")"
    RULES+=("$(serialize_rule "$(generate_unique_rule_id)" "${name}" "${proto}" "${lport}" "${dip}" "${dport}" "1")")
}

extract_rules_from_nft_text() {
    local text="$1"
    local line parsed
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parsed="$(parse_rule_from_line "${line}" || true)"
        [[ -n "${parsed}" ]] && printf '%s\n' "${parsed}"
    done <<< "${text}"
}

load_rules_from_nft_text() {
    local text="$1"
    local source_name="$2"
    local proto lport dip dport name

    while IFS='|' read -r proto lport dip dport name; do
        [[ -n "${proto}" ]] || continue
        validate_listen_port_value "${lport}" || continue
        validate_host_ipv4 "${dip}" || continue
        validate_port "${dport}" || continue
        append_loaded_rule "${proto}" "${lport}" "${dip}" "${dport}" "${name}"
    done < <(extract_rules_from_nft_text "${text}")

    [[ ${#RULES[@]} -gt 0 ]] || return 1
    RULES_SOURCE="${source_name}"
}

load_rules_from_nft_conf() {
    local text
    [[ -f "${NFT_CONF}" ]] || return 1
    text="$(cat "${NFT_CONF}" 2>/dev/null || true)"
    [[ -n "${text}" ]] || return 1
    load_rules_from_nft_text "${text}" "nft_conf"
}

load_rules_from_live_table() {
    local text
    command -v nft &>/dev/null || return 1
    text="$(nft list table ip "${NAT_TABLE}" 2>/dev/null || true)"
    [[ -n "${text}" ]] || return 1
    load_rules_from_nft_text "${text}" "live_table"
}

extract_rules_from_ruleset_text() {
    extract_rules_from_nft_text "$1"
}

load_rules_from_ruleset() {
    local text proto lport dip dport name
    command -v nft &>/dev/null || return 1
    text="$(nft list ruleset 2>/dev/null || true)"
    [[ -n "${text}" ]] || return 1

    while IFS='|' read -r proto lport dip dport name; do
        [[ -n "${proto}" ]] || continue
        validate_listen_port_value "${lport}" || continue
        validate_host_ipv4 "${dip}" || continue
        validate_port "${dport}" || continue
        append_loaded_rule "${proto}" "${lport}" "${dip}" "${dport}" "${name}"
    done < <(extract_rules_from_ruleset_text "${text}")

    [[ ${#RULES[@]} -gt 0 ]] || return 1
    RULES_SOURCE="ruleset"
}

discover_existing_rules() {
    local force_reload="${1:-0}"
    local -a saved_rules=("${RULES[@]}")
    local saved_source="${RULES_SOURCE}"

    if [[ "${DISCOVERY_CACHE_READY}" == "1" && "${force_reload}" != "1" ]]; then
        [[ ${DISCOVERED_RULE_COUNT} -gt 0 ]]
        return
    fi

    DISCOVERED_RULES=()
    DISCOVERED_RULES_SOURCE="none"
    DISCOVERED_RULE_COUNT=0

    RULES=()
    RULES_SOURCE="none"
    if load_rules_from_nft_conf || load_rules_from_live_table || load_rules_from_ruleset; then
        DISCOVERED_RULES=("${RULES[@]}")
        DISCOVERED_RULES_SOURCE="${RULES_SOURCE}"
        DISCOVERED_RULE_COUNT=${#DISCOVERED_RULES[@]}
    fi

    RULES=("${saved_rules[@]}")
    RULES_SOURCE="${saved_source}"
    DISCOVERY_CACHE_READY="1"
    [[ ${DISCOVERED_RULE_COUNT} -gt 0 ]]
}

validate_rule_name() {
    local value="$1"
    [[ -n "${value}" ]] || return 1
    [[ ${#value} -le 48 ]] || return 1
    [[ "${value}" != *'|'* ]] || return 1
    [[ "${value}" != *$'\n'* ]] || return 1
    [[ "${value}" != *$'\r'* ]] || return 1
    [[ "${value}" == "$(trim "${value}")" ]]
}

validate_rule_id() {
    local value="$1"
    [[ -n "${value}" ]] || return 1
    [[ "${value}" =~ ^[A-Za-z0-9._-]+$ ]]
}

normalize_proto() {
    local value
    value="$(trim "${1}")"
    value="${value,,}"
    case "${value}" in
        both|all|tcp+udp|tcpudp|"")
            printf 'both\n'
            ;;
        tcp)
            printf 'tcp\n'
            ;;
        udp)
            printf 'udp\n'
            ;;
        *)
            return 1
            ;;
    esac
}

proto_to_label() {
    case "$1" in
        tcp) printf 'tcp' ;;
        udp) printf 'udp' ;;
        *) printf 'tcp+udp' ;;
    esac
}

proto_to_nft_expr() {
    case "$1" in
        tcp) printf 'tcp' ;;
        udp) printf 'udp' ;;
        *) printf '{ tcp, udp }' ;;
    esac
}

normalize_snat_mode() {
    local value
    value="$(trim "${1:-}")"
    value="${value,,}"
    case "${value}" in
        ""|1|relay|relay_lan|lan|inner|private|po0|po0_lan)
            printf 'relay_lan\n'
            ;;
        2|masq|masquerade|public|wan|egress|route)
            printf 'masquerade\n'
            ;;
        3|none|no|off|disable|disabled|keep|transparent)
            printf 'none\n'
            ;;
        *)
            return 1
            ;;
    esac
}

normalize_relay_mode() {
    local value
    value="$(trim "${1:-}")"
    value="${value,,}"
    case "${value}" in
        1|lan|relay_lan|inner|private|po0|po0_lan)
            printf 'lan\n'
            ;;
        2|public|wan|masq|masquerade|egress)
            printf 'public\n'
            ;;
        ""|3|mixed|both|hybrid|all)
            printf 'mixed\n'
            ;;
        *)
            return 1
            ;;
    esac
}

relay_mode_to_label() {
    case "$1" in
        lan)
            printf '纯内网/无感内网转发'
            ;;
        public)
            printf '公网转发'
            ;;
        *)
            printf '内网/公网混合转发'
            ;;
    esac
}

relay_mode_uses_lan() {
    [[ "${RELAY_MODE}" == "lan" || "${RELAY_MODE}" == "mixed" ]]
}

relay_mode_default_snat_mode() {
    case "${RELAY_MODE}" in
        public)
            printf 'masquerade\n'
            ;;
        *)
            printf 'relay_lan\n'
            ;;
    esac
}

snat_mode_to_label() {
    case "$1" in
        masquerade)
            printf '公网出口'
            ;;
        none)
            printf '透明转发'
            ;;
        *)
            printf '内网回源'
            ;;
    esac
}

snat_mode_to_short() {
    case "$1" in
        masquerade)
            printf '公网出口'
            ;;
        none)
            printf '透明转发'
            ;;
        *)
            printf '内网回源'
            ;;
    esac
}

protocols_overlap() {
    case "$1:$2" in
        both:*|*:both|tcp:tcp|udp:udp)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

enabled_to_label() {
    if [[ "$1" == "1" ]]; then
        printf '%b启用%b' "${C_GREEN}" "${C_RESET}"
    else
        printf '%b停用%b' "${C_DIM}" "${C_RESET}"
    fi
}

enabled_to_short() {
    if [[ "$1" == "1" ]]; then
        printf '%bON %b' "${C_GREEN}" "${C_RESET}"
    else
        printf '%bOFF%b' "${C_DIM}" "${C_RESET}"
    fi
}

generate_rule_id() {
    printf 'r%s%04d' "$(date '+%Y%m%d%H%M%S')" "$((RANDOM % 10000))"
}

rule_id_exists() {
    local id="$1"
    local rule
    for rule in "${RULES[@]}" "${IMPORTED_RULES[@]}"; do
        [[ -n "${rule}" ]] || continue
        parse_rule "${rule}"
        [[ "${RULE_ID}" == "${id}" ]] && return 0
    done
    return 1
}

generate_unique_rule_id() {
    local id attempts=0
    while (( attempts < 100 )); do
        id="$(generate_rule_id)"
        rule_id_exists "${id}" || {
            printf '%s\n' "${id}"
            return 0
        }
        ((attempts++))
    done

    while true; do
        id="r$(date '+%Y%m%d%H%M%S')${RANDOM}${RANDOM}"
        rule_id_exists "${id}" || {
            printf '%s\n' "${id}"
            return 0
        }
    done
}

serialize_rule() {
    local snat_mode="${8:-relay_lan}"
    snat_mode="$(normalize_snat_mode "${snat_mode}" 2>/dev/null || printf 'relay_lan')"
    printf '%s|%s|%s|%s|%s|%s|%s|%s' "$1" "$2" "$3" "$4" "$5" "$6" "$7" "${snat_mode}"
}

parse_rule() {
    IFS='|' read -r RULE_ID RULE_NAME RULE_PROTO RULE_LPORT RULE_DIP RULE_DPORT RULE_ENABLED RULE_SNAT_MODE _ <<< "$1"
    RULE_SNAT_MODE="$(normalize_snat_mode "${RULE_SNAT_MODE:-relay_lan}" 2>/dev/null || printf 'relay_lan')"
}

rule_name_exists() {
    local name="$1"
    local skip_id="${2-}"
    local rule
    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        [[ "${RULE_ID}" == "${skip_id}" ]] && continue
        [[ "${RULE_NAME}" == "${name}" ]] && return 0
    done
    return 1
}

rule_port_conflict_exists() {
    local listen_port="$1"
    local proto="$2"
    local skip_id="${3-}"
    local rule
    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        [[ "${RULE_ID}" == "${skip_id}" ]] && continue
        [[ "${RULE_LPORT}" == "${listen_port}" ]] || continue
        protocols_overlap "${RULE_PROTO}" "${proto}" && return 0
    done
    return 1
}

refresh_rule_counts() {
    local rule
    RULE_TOTAL=${#RULES[@]}
    RULE_ENABLED_COUNT=0
    RULE_DISABLED_COUNT=0
    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        if [[ "${RULE_ENABLED}" == "1" ]]; then
            ((RULE_ENABLED_COUNT++))
        else
            ((RULE_DISABLED_COUNT++))
        fi
    done
}

detect_pkg_manager() {
    if command -v apt-get &>/dev/null; then
        echo apt
    elif command -v dnf &>/dev/null; then
        echo dnf
    elif command -v yum &>/dev/null; then
        echo yum
    elif command -v pacman &>/dev/null; then
        echo pacman
    else
        echo unknown
    fi
}

install_nftables_if_needed() {
    local pkg_mgr
    command -v nft &>/dev/null && return 0
    pkg_mgr="$(detect_pkg_manager)"
    case "${pkg_mgr}" in
        apt) apt-get update -y && apt-get install -y nftables ;;
        dnf) dnf install -y nftables ;;
        yum) yum install -y nftables ;;
        pacman) pacman -Sy --noconfirm nftables ;;
        *)
            err "无法识别包管理器，请手动安装 nftables。"
            return 1
            ;;
    esac
    command -v nft &>/dev/null || {
        err "nftables 安装失败。"
        return 1
    }
}

install_conntrack_if_needed() {
    local pkg_mgr
    command -v conntrack &>/dev/null && return 0
    pkg_mgr="$(detect_pkg_manager)"
    case "${pkg_mgr}" in
        apt) apt-get update -y && apt-get install -y conntrack ;;
        dnf) dnf install -y conntrack-tools ;;
        yum) yum install -y conntrack-tools ;;
        pacman) pacman -Sy --noconfirm conntrack-tools ;;
        *)
            err "无法识别包管理器，请手动安装 conntrack。"
            return 1
            ;;
    esac
    command -v conntrack &>/dev/null || {
        err "conntrack 安装失败。"
        return 1
    }
}

python_venv_works() {
    local tmp
    command -v python3 &>/dev/null || return 1
    tmp="$(mktemp -d "/tmp/po0-ipdb-venv-test.XXXXXX")" || return 1
    if python3 -m venv "${tmp}" >/dev/null 2>&1 && [[ -x "${tmp}/bin/python" ]]; then
        rm -rf -- "${tmp}" 2>/dev/null || true
        return 0
    fi
    rm -rf -- "${tmp}" 2>/dev/null || true
    return 1
}

install_ipdb_python_base_if_needed() {
    local pkg_mgr
    if python_venv_works; then
        return 0
    fi
    pkg_mgr="$(detect_pkg_manager)"
    case "${pkg_mgr}" in
        apt)
            apt-get update -y && apt-get install -y python3 python3-venv python3-pip
            ;;
        dnf)
            dnf install -y python3 python3-pip
            ;;
        yum)
            yum install -y python3 python3-pip
            ;;
        pacman)
            pacman -Sy --noconfirm python python-pip
            ;;
        *)
            err "无法识别包管理器，请手动安装 python3、venv 和 pip。"
            return 1
            ;;
    esac
    command -v python3 &>/dev/null || {
        err "python3 安装失败。"
        return 1
    }
    python_venv_works || {
        err "python3 venv 仍不可用。Debian/Ubuntu 请确认已安装 python3-venv 或当前版本对应的 python3.x-venv。"
        return 1
    }
}

ipdb_venv_has_pip() {
    [[ -x "${IPDB_VENV_PYTHON}" ]] || return 1
    "${IPDB_VENV_PYTHON}" -m pip --version >/dev/null 2>&1
}

create_ipdb_venv() {
    rm -rf -- "${IPDB_VENV_DIR}" 2>/dev/null || true
    python3 -m venv "${IPDB_VENV_DIR}" || return 1
    ipdb_venv_has_pip && return 0
    "${IPDB_VENV_PYTHON}" -m ensurepip --upgrade >/dev/null 2>&1 || return 1
    ipdb_venv_has_pip
}

pip_index_label() {
    case "$1" in
        https://mirrors.cloud.tencent.com/pypi/simple) printf '腾讯云 PyPI 镜像' ;;
        https://pypi.tuna.tsinghua.edu.cn/simple) printf '清华 PyPI 镜像' ;;
        https://mirrors.aliyun.com/pypi/simple/) printf '阿里云 PyPI 镜像' ;;
        https://pypi.org/simple) printf '官方 PyPI' ;;
        *) printf '%s' "$1" ;;
    esac
}

prompt_ipdb_pip_index() {
    local choice custom
    echo "请选择 pip 安装源：" >&2
    echo "  1) 腾讯云 PyPI 镜像（推荐）" >&2
    echo "  2) 清华 PyPI 镜像" >&2
    echo "  3) 阿里云 PyPI 镜像" >&2
    echo "  4) 官方 PyPI" >&2
    echo "  5) 自定义源" >&2
    choice="$(read_prompt "请选择 [1-5，默认: 腾讯云 PyPI 镜像]: ")" || return 1
    case "${choice:-1}" in
        1) printf '%s\n' "https://mirrors.cloud.tencent.com/pypi/simple" ;;
        2) printf '%s\n' "https://pypi.tuna.tsinghua.edu.cn/simple" ;;
        3) printf '%s\n' "https://mirrors.aliyun.com/pypi/simple/" ;;
        4) printf '%s\n' "https://pypi.org/simple" ;;
        5)
            custom="$(prompt_with_default "请输入 pip simple 源 URL" "${IPDB_DEFAULT_PIP_INDEX_URL}")"
            if [[ ! "${custom}" =~ ^https?:// ]]; then
                err "pip 源 URL 必须以 http:// 或 https:// 开头。"
                return 1
            fi
            printf '%s\n' "${custom}"
            ;;
        *)
            err "无效选择。"
            return 1
            ;;
    esac
}

install_ipdb_parser_package() {
    local pip_index_url
    pip_index_url="${IPDB_PIP_INDEX_URL:-${IPDB_DEFAULT_PIP_INDEX_URL}}"
    warn "将从 $(pip_index_label "${pip_index_url}") 安装；如果该源不可达，会在超时后失败。"
    "${IPDB_VENV_PYTHON}" -m pip install \
        --disable-pip-version-check \
        --index-url "${pip_index_url}" \
        --retries 1 \
        --timeout 20 \
        --upgrade \
        ipip-ipdb
}
