normalize_self_report_https_domain() {
    local domain="$1"
    domain="$(trim "${domain}")"
    domain="${domain#http://}"
    domain="${domain#https://}"
    domain="${domain%%/*}"
    domain="${domain%%:*}"
    domain="${domain,,}"
    printf '%s\n' "${domain}"
}

validate_self_report_https_domain() {
    local domain="$1"
    [[ -n "${domain}" ]] || {
        printf '缺少 Self-report HTTPS 域名。\n' >&2
        return 1
    }
    [[ "${domain}" == *.* && "${domain}" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$ ]] || {
        printf 'Self-report HTTPS 域名格式无效：%s\n' "${domain}" >&2
        return 1
    }
    is_public_ipv4 "${domain}" && {
        printf 'Self-report HTTPS 需要公网域名，不能直接使用 IP：%s\n' "${domain}" >&2
        return 1
    }
    return 0
}

self_report_https_domain_from_caddy() {
    local line
    [[ -r "${SELF_REPORT_CADDY_SNIPPET}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="$(trim "${line}")"
        [[ -n "${line}" && "${line}" != \#* ]] || continue
        case "${line}" in
            *"{")
                line="${line%\{}"
                line="$(trim "${line}")"
                [[ -n "${line}" ]] || return 1
                printf '%s\n' "${line}"
                return 0
                ;;
        esac
    done < "${SELF_REPORT_CADDY_SNIPPET}"
    return 1
}

current_self_report_https_domain() {
    if [[ -n "${SELF_REPORT_HTTPS_DOMAIN}" ]]; then
        printf '%s\n' "${SELF_REPORT_HTTPS_DOMAIN}"
    else
        self_report_https_domain_from_caddy 2>/dev/null || true
    fi
}

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
        printf '未识别的包管理器。请先手动安装 Caddy，再重新配置 Self-report HTTPS。\n' >&2
        return 1
    fi
    have_cmd caddy || {
        printf 'Caddy 安装后仍不可用，请检查包管理器输出。\n' >&2
        return 1
    }
}

ensure_caddyfile_import() {
    local caddy_dir snippet_dir manager_snippet_dir import_line manager_import_line
    caddy_dir="$(path_dirname "${CADDYFILE_PATH}")"
    snippet_dir="$(path_dirname "${SELF_REPORT_CADDY_SNIPPET}")"
    manager_snippet_dir="$(path_dirname "${MANAGER_UPDATE_CADDY_SNIPPET}")"
    mkdir -p "${caddy_dir}" "${snippet_dir}" "${manager_snippet_dir}" || return 1
    [[ -f "${CADDYFILE_PATH}" ]] || : > "${CADDYFILE_PATH}" || return 1
    import_line="import ${snippet_dir%/}/*.caddy"
    if ! awk '{$1=$1; print}' "${CADDYFILE_PATH}" 2>/dev/null | grep -Fxq "${import_line}"; then
        {
            printf '\n'
            printf '# PO0 LAN Worker managed snippets\n'
            printf '%s\n' "${import_line}"
        } >> "${CADDYFILE_PATH}" || return 1
    fi
    manager_import_line="import ${manager_snippet_dir%/}/*.caddy"
    if [[ "${manager_import_line}" != "${import_line}" ]] \
        && ! awk '{$1=$1; print}' "${CADDYFILE_PATH}" 2>/dev/null | grep -Fxq "${manager_import_line}"; then
        printf '%s\n' "${manager_import_line}" >> "${CADDYFILE_PATH}" || return 1
    fi
}

write_self_report_caddy_config() {
    local domain="$1" backend_host backend_port
    backend_host="${SELF_REPORT_HTTPS_BACKEND%:*}"
    backend_port="${SELF_REPORT_HTTPS_BACKEND##*:}"
    [[ -n "${backend_host}" && "${backend_host}" != "${SELF_REPORT_HTTPS_BACKEND}" ]] || backend_host="127.0.0.1"
    [[ "${backend_port}" =~ ^[0-9]+$ ]] || backend_port="8788"
    mkdir -p "$(path_dirname "${SELF_REPORT_CADDY_SNIPPET}")" || return 1
    cat > "${SELF_REPORT_CADDY_SNIPPET}" <<EOF
# Managed by po0-lan-client. Self-report HTTPS entrypoint.
${domain} {
    handle /report {
        reverse_proxy ${backend_host}:${backend_port}
    }
    handle /health {
        reverse_proxy ${backend_host}:${backend_port}
    }
    respond 404
}
EOF
}
