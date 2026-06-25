read_prompt() {
    local prompt="$1"
    local value
    if [[ -r /dev/tty && -w /dev/tty ]]; then
        if { printf '%s' "${prompt}" > /dev/tty && IFS= read -r value < /dev/tty; } 2>/dev/null; then
            printf '%s\n' "${value}"
            return 0
        fi
    fi
    printf '%s' "${prompt}" >&2
    IFS= read -r value || return 1
    printf '%s\n' "${value}"
}

read_menu_choice() {
    local prompt="$1"
    local choice
    choice="$(read_prompt "${prompt}")" || return 1
    printf '%s\n' "$(trim "${choice}")"
}

read_menu_choice_or_return() {
    local __target="$1"
    local prompt="$2"
    local __choice_value
    if ! __choice_value="$(read_menu_choice "${prompt}")"; then
        printf '\n输入结束，退出当前菜单。\n'
        return 1
    fi
    printf -v "${__target}" '%s' "${__choice_value}"
}

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "${value}"
}

validate_node_name() {
    local value="$1"
    [[ -z "${value}" ]] && return 0
    [[ ${#value} -le 32 ]] || return 1
    [[ "${value}" =~ ^[A-Za-z0-9._-]+$ ]]
}

export_rules_default_path() {
    local prefix=""
    validate_node_name "${NODE_NAME}" || NODE_NAME=""
    [[ -n "${NODE_NAME}" ]] && prefix="${NODE_NAME}-"
    printf '%s/%spo0-relay-export-%s.txt\n' "${EXPORT_DIR}" "${prefix}" "$(date '+%Y%m%d_%H%M%S')"
}

check_root() {
    if [[ ${EUID} -ne 0 ]]; then
        err "请使用 root 运行此脚本。"
        exit 1
    fi
}

confirm_yes() {
    local ans
    ans="$(read_prompt "$1 [y/N]: ")" || return 1
    [[ "${ans}" =~ ^[Yy]$ ]]
}

confirm_strong_yes() {
    local ans
    ans="$(read_prompt "$1（输入 YES 确认）: ")" || return 1
    [[ "${ans}" == "YES" ]]
}

prompt_with_default() {
    local prompt="$1"
    local default="${2-}"
    local value
    if [[ -n "${default}" ]]; then
        value="$(read_prompt "${prompt} [当前: ${default}]: ")" || value=""
        printf '%s\n' "${value:-${default}}"
    else
        value="$(read_prompt "${prompt}: ")" || value=""
        printf '%s\n' "${value}"
    fi
}

pause_before_return() {
    echo ""
    read_prompt "按回车返回菜单..." >/dev/null || true
}

validate_port() {
    local port="$1"
    [[ "${port}" =~ ^[0-9]+$ ]] || return 1
    [[ ! "${port}" =~ ^0[0-9] ]] || return 1
    (( port >= 1 && port <= 65535 ))
}

normalize_port_list() {
    local raw="$1"
    local port
    local out=""
    local seen=" "
    for port in ${raw//,/ }; do
        port="$(trim "${port}")"
        validate_port "${port}" || continue
        [[ "${seen}" == *" ${port} "* ]] && continue
        seen+="${port} "
        if [[ -z "${out}" ]]; then
            out="${port}"
        else
            out+=" ${port}"
        fi
    done
    printf '%s\n' "${out}"
}

ports_to_nft_set() {
    local out=""
    local port
    for port in $1; do
        if [[ -z "${out}" ]]; then
            out="${port}"
        else
            out+=", ${port}"
        fi
    done
    printf '%s\n' "${out}"
}

is_blocked_listen_port() {
    local port="$1"
    local blocked
    for blocked in ${BLOCKED_LISTEN_PORTS}; do
        [[ "${port}" == "${blocked}" ]] && return 0
    done
    return 1
}

validate_listen_port_value() {
    local port="$1"
    validate_port "${port}" || return 1
    is_blocked_listen_port "${port}" && return 1
    return 0
}

listen_port_in_forward_range() {
    local port="$1"
    validate_port "${port}" || return 1
    (( port >= FORWARD_PORT_MIN && port <= FORWARD_PORT_MAX ))
}

local_port_in_use() {
    local port="$1"
    local proto="$2"
    command -v ss &>/dev/null || return 1

    if [[ "${proto}" == "both" || "${proto}" == "tcp" ]]; then
        ss -H -tln 2>/dev/null | awk '{ print $4 }' | grep -Eq "(^|[^0-9])${port}$" && return 0
    fi
    if [[ "${proto}" == "both" || "${proto}" == "udp" ]]; then
        ss -H -uln 2>/dev/null | awk '{ print $4 }' | grep -Eq "(^|[^0-9])${port}$" && return 0
    fi
    return 1
}

ensure_listen_port_allowed() {
    local port="$1"
    local proto="$2"
    validate_port "${port}" || {
        err "监听端口无效：${port}"
        return 1
    }
    if is_blocked_listen_port "${port}"; then
        err "监听端口 ${port} 属于保留服务端口，不允许作为转发入口。"
        return 1
    fi
    if local_port_in_use "${port}" "${proto}"; then
        err "监听端口 ${port} 已被本机其它服务占用，不允许作为转发入口。"
        return 1
    fi
    return 0
}

ensure_new_listen_port_allowed() {
    local port="$1"
    local proto="$2"
    ensure_listen_port_allowed "${port}" "${proto}" || return 1
    if ! listen_port_in_forward_range "${port}"; then
        err "监听端口必须在 ${FORWARD_PORT_MIN}-${FORWARD_PORT_MAX} 范围内。"
        return 1
    fi
    return 0
}

validate_ip() {
    local ip="$1"
    local IFS='.'
    local octet
    local -a octets=()
    [[ "${ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    [[ ! "${ip}" =~ (^|\.)0[0-9] ]] || return 1
    read -r -a octets <<< "${ip}"
    for octet in "${octets[@]}"; do
        (( octet >= 0 && octet <= 255 )) || return 1
    done
}

validate_host_ipv4() {
    local ip="$1"
    local o1 o2 o3 o4
    validate_ip "${ip}" || return 1
    IFS='.' read -r o1 o2 o3 o4 <<< "${ip}"
    (( o1 == 0 )) && return 1
    (( o1 == 127 )) && return 1
    (( o1 == 169 && o2 == 254 )) && return 1
    (( o1 >= 224 )) && return 1
    (( o1 == 255 && o2 == 255 && o3 == 255 && o4 == 255 )) && return 1
    return 0
}

validate_ipv4_cidr() {
    local cidr="$1"
    local ip prefix
    [[ "${cidr}" == */* ]] || return 1
    ip="${cidr%/*}"
    prefix="${cidr#*/}"
    validate_ip "${ip}" || return 1
    [[ "${prefix}" =~ ^[0-9]+$ ]] || return 1
    (( prefix >= 0 && prefix <= 32 ))
}

ipv4_to_int() {
    local ip="$1"
    local o1 o2 o3 o4
    validate_ip "${ip}" || return 1
    IFS='.' read -r o1 o2 o3 o4 <<< "${ip}"
    printf '%u\n' "$(( (o1 << 24) + (o2 << 16) + (o3 << 8) + o4 ))"
}

int_to_ipv4() {
    local value="$1"
    printf '%u.%u.%u.%u\n' \
        "$(( (value >> 24) & 255 ))" \
        "$(( (value >> 16) & 255 ))" \
        "$(( (value >> 8) & 255 ))" \
        "$(( value & 255 ))"
}
