normalize_manager_update_endpoint() {
    local endpoint="$1" host port
    endpoint="$(trim "${endpoint}")"
    endpoint="${endpoint#http://}"
    endpoint="${endpoint#https://}"
    endpoint="${endpoint%%/*}"
    endpoint="${endpoint%%\?*}"
    endpoint="${endpoint,,}"
    if [[ "${endpoint}" == *:* ]]; then
        host="${endpoint%:*}"
        port="${endpoint##*:}"
    else
        host="${endpoint}"
        port="${MANAGER_UPDATE_DEFAULT_PORT}"
    fi
    printf '%s:%s\n' "${host}" "${port}"
}

manager_update_endpoint_host() {
    local endpoint="$1"
    printf '%s\n' "${endpoint%:*}"
}

manager_update_endpoint_port() {
    local endpoint="$1"
    printf '%s\n' "${endpoint##*:}"
}

validate_manager_update_endpoint() {
    local endpoint="$1" host port
    host="$(manager_update_endpoint_host "${endpoint}")"
    port="$(manager_update_endpoint_port "${endpoint}")"
    [[ -n "${host}" ]] || {
        printf '缺少 PO0 manager 更新 HTTP 主机/IP。\n' >&2
        return 1
    }
    [[ "${port}" =~ ^[0-9]+$ ]] && (( 10#${port} >= 1 && 10#${port} <= 65535 )) || {
        printf 'PO0 manager 更新 HTTP 端口无效：%s\n' "${port}" >&2
        return 1
    }
    validate_ip "${host}" && return 0
    [[ "${host}" == *.* && "${host}" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$ ]] || {
        printf 'PO0 manager 更新 HTTP 主机/IP 格式无效：%s\n' "${host}" >&2
        return 1
    }
    return 0
}

manager_update_caddy_site_address() {
    local endpoint="$1" port
    port="$(manager_update_endpoint_port "${endpoint}")"
    printf ':%s\n' "${port}"
}

ensure_caddy_installed() {
    if have_cmd caddy; then
        return 0
    fi
    [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]] || {
        printf '安装 Caddy 需要 root。请先手动安装 caddy，或用 root 重新运行菜单。\n' >&2
        return 1
    }
    if have_cmd apt-get; then
        apt-get update -y && apt-get install -y caddy
    elif have_cmd dnf; then
        dnf install -y caddy
    elif have_cmd yum; then
        yum install -y caddy
    elif have_cmd apk; then
        apk add --no-cache caddy
    else
        printf '未识别的包管理器。请先手动安装 Caddy，再配置更新入口。\n' >&2
        return 1
    fi
    have_cmd caddy || {
        printf 'Caddy 安装后仍不可用，请检查包管理器输出。\n' >&2
        return 1
    }
}
