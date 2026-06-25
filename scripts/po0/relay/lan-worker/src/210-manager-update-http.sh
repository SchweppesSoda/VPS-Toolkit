write_manager_update_caddy_config() {
    local endpoint="$1" backend_host backend_port site_address
    backend_host="${MANAGER_UPDATE_BACKEND%:*}"
    backend_port="${MANAGER_UPDATE_BACKEND##*:}"
    [[ -n "${backend_host}" && "${backend_host}" != "${MANAGER_UPDATE_BACKEND}" ]] || backend_host="127.0.0.1"
    [[ "${backend_port}" =~ ^[0-9]+$ ]] || backend_port="8789"
    site_address="$(manager_update_caddy_site_address "${endpoint}")"
    mkdir -p "$(path_dirname "${MANAGER_UPDATE_CADDY_SNIPPET}")" || return 1
    cat > "${MANAGER_UPDATE_CADDY_SNIPPET}" <<EOF
# Managed by po0-lan-client. HTTP-only PO0 manager update mirror.
${site_address} {
    route {
        handle /po0-manager-update/nftables-relay-manager.sh {
            reverse_proxy ${backend_host}:${backend_port}
        }
        handle /po0-manager-update/health {
            reverse_proxy ${backend_host}:${backend_port}
        }
        respond 404
    }
}
EOF
}

manager_update_service_summary() {
    local name="po0-lan-manager-update.service" active enabled
    have_cmd systemctl || {
        printf 'systemctl 不可用'
        return 0
    }
    active="$(systemctl is-active "${name}" 2>/dev/null || true)"
    enabled="$(systemctl is-enabled "${name}" 2>/dev/null || true)"
    printf 'active=%s enabled=%s' "${active:-unknown}" "${enabled:-unknown}"
}

show_manager_update_http_status() {
    local name="caddy" token_count
    token_count="$(manager_update_tokens_env | awk 'NF { count++ } END { print count + 0 }')"
    print_panel_section "PO0 manager HTTP 更新镜像"
    print_panel_row "HTTP 主机/IP" "${MANAGER_UPDATE_DOMAIN:-未配置}"
    print_panel_row "公网入口" "$(if [[ -n "${MANAGER_UPDATE_DOMAIN}" ]]; then printf 'http://%s/po0-manager-update/nftables-relay-manager.sh' "${MANAGER_UPDATE_DOMAIN}"; else printf '未配置'; fi)"
    print_panel_row "本机监听" "${MANAGER_UPDATE_LISTEN}"
    print_panel_row "Caddy 后端" "${MANAGER_UPDATE_BACKEND}"
    print_panel_row "Caddy snippet" "${MANAGER_UPDATE_CADDY_SNIPPET}"
    print_panel_row "可用 token" "${token_count} 个 resource token"
    print_panel_row "镜像服务" "$(manager_update_service_summary)"
    if have_cmd systemctl; then
        print_panel_row "Caddy 服务" "active=$(systemctl is-active "${name}" 2>/dev/null || true) enabled=$(systemctl is-enabled "${name}" 2>/dev/null || true)"
    fi
    if have_cmd caddy; then
        printf '\n'
        caddy validate --config "${CADDYFILE_PATH}" || true
    fi
}

install_manager_update_mirror_service() {
    local script_path unit name="po0-lan-manager-update.service" tokens
    [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]] || {
        printf '安装 systemd 服务需要 root。\n' >&2
        return 1
    }
    command -v systemctl >/dev/null 2>&1 || {
        printf '当前系统没有 systemctl，无法安装服务。\n' >&2
        return 1
    }
    tokens="$(manager_update_tokens_env)" || return 1
    [[ -n "${tokens}" ]] || {
        printf '没有可用的 resource token，无法安装 manager 更新镜像服务。\n' >&2
        return 1
    }
    script_path="$(ensure_persistent_script)" || return 1
    save_local_settings || return 1
    unit="/etc/systemd/system/${name}"
    cat > "${unit}" <<EOF
[Unit]
Description=PO0 manager HTTP update mirror
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/env bash $(sh_quote "${script_path}") --config $(sh_quote "${CONFIG_FILE}") --manager-update-mirror-server --manager-update-listen $(sh_quote "${MANAGER_UPDATE_LISTEN}")
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload || return 1
    systemctl reset-failed "${name}" 2>/dev/null || true
    systemctl enable "${name}" || return 1
    systemctl restart "${name}" || return 1
    printf '已安装并启动 PO0 manager 更新镜像服务：%s\n' "${name}"
}

install_manager_update_http() {
    local endpoint host ip_csv
    endpoint="$(normalize_manager_update_endpoint "${MANAGER_UPDATE_DOMAIN}")"
    validate_manager_update_endpoint "${endpoint}" || return 1
    host="$(manager_update_endpoint_host "${endpoint}")"
    if validate_ip "${host}"; then
        printf 'HTTP 入口使用 IP：%s\n' "${endpoint}"
    elif ip_csv="$(resolve_ddns_ipv4_csv "${host}" 2>/dev/null)"; then
        printf 'DNS A 记录：%s -> %s\n' "${host}" "${ip_csv}"
    else
        printf '警告：当前机器未解析到 %s 的公网 IPv4。请确认 DNS 已指向 LAN Worker，且 %s 端口已放行。\n' "${host}" "$(manager_update_endpoint_port "${endpoint}")" >&2
    fi
    ensure_caddy_installed || return 1
    ensure_caddyfile_import || return 1
    write_manager_update_caddy_config "${endpoint}" || return 1
    caddy validate --config "${CADDYFILE_PATH}" || return 1
    MANAGER_UPDATE_DOMAIN="${endpoint}"
    save_local_settings || return 1
    install_manager_update_mirror_service || return 1
    if have_cmd systemctl; then
        systemctl enable caddy || return 1
        systemctl reload caddy 2>/dev/null || systemctl restart caddy || return 1
    fi
    printf 'PO0 manager HTTP 更新镜像已配置：http://%s/po0-manager-update/nftables-relay-manager.sh\n' "${endpoint}"
    printf '健康检查：curl -fsS http://%s/po0-manager-update/health\n' "${endpoint}"
    printf '注意：该入口按要求使用 HTTP；请限制可访问来源或使用防火墙保护 %s 端口。\n' "$(manager_update_endpoint_port "${endpoint}")"
}

edit_manager_update_http_settings() {
    MANAGER_UPDATE_DOMAIN="$(prompt_default "PO0 manager 更新 HTTP 主机/IP[:端口]" "${MANAGER_UPDATE_DOMAIN}")"
    MANAGER_UPDATE_DOMAIN="$(normalize_manager_update_endpoint "${MANAGER_UPDATE_DOMAIN}")"
    validate_manager_update_endpoint "${MANAGER_UPDATE_DOMAIN}" || return 1
    MANAGER_UPDATE_LISTEN="$(prompt_default "本机镜像服务监听地址" "${MANAGER_UPDATE_LISTEN:-127.0.0.1:8789}")"
    [[ -n "${MANAGER_UPDATE_LISTEN}" ]] || MANAGER_UPDATE_LISTEN="127.0.0.1:8789"
    MANAGER_UPDATE_BACKEND="$(prompt_default "Caddy 反代后端" "${MANAGER_UPDATE_BACKEND:-127.0.0.1:8789}")"
    [[ -n "${MANAGER_UPDATE_BACKEND}" ]] || MANAGER_UPDATE_BACKEND="127.0.0.1:8789"
    MANAGER_UPDATE_CADDY_SNIPPET="$(prompt_default "Caddy snippet 路径" "${MANAGER_UPDATE_CADDY_SNIPPET:-/etc/caddy/conf.d/po0-manager-update.caddy}")"
    save_local_settings || return 1
    printf '已保存 PO0 manager 更新镜像设置：%s\n' "${SETTINGS_FILE}"
}

manage_manager_update_http_interactive() {
    local choice
    while true; do
        menu_clear_screen
        print_title "PO0 manager 更新镜像"
        show_manager_update_http_status
        print_menu_section "操作"
        print_menu_pair 1 "查看状态 / 日志" 2 "配置入口与监听"
        print_menu_pair 3 "安装 / 更新 HTTP 入口" 4 "前台启动镜像服务"
        print_menu_item 0 "返回"
        print_menu_footer
        read_menu_choice_or_return choice "请选择操作 [0-4]: " || return 0
        case "${choice}" in
            1) show_manager_update_http_status; pause_before_return ;;
            2) edit_manager_update_http_settings; pause_before_return ;;
            3) install_manager_update_http; pause_before_return ;;
            4) run_manager_update_mirror_server ;;
            0) return 0 ;;
            "") ;;
            *) printf '无效选择。\n' >&2; pause_before_return ;;
        esac
    done
}
