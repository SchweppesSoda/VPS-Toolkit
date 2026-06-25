show_self_report_https_status() {
    local domain lines name="caddy"
    domain="$(current_self_report_https_domain)"
    print_panel_section "Self-report HTTPS / Caddy 状态"
    print_panel_row "域名" "${domain:-未配置}"
    print_panel_row "公网入口" "$(if [[ -n "${domain}" ]]; then printf 'https://%s/report' "${domain}"; else printf '未配置'; fi)"
    print_panel_row "本机后端" "${SELF_REPORT_HTTPS_BACKEND}"
    print_panel_row "Caddyfile" "${CADDYFILE_PATH}"
    print_panel_row "Snippet" "${SELF_REPORT_CADDY_SNIPPET}"
    if have_cmd systemctl; then
        print_panel_row "Caddy 服务" "active=$(systemctl is-active "${name}" 2>/dev/null || true) enabled=$(systemctl is-enabled "${name}" 2>/dev/null || true)"
    else
        print_panel_row "Caddy 服务" "systemctl 不可用"
    fi
    if have_cmd caddy; then
        printf '\n'
        caddy validate --config "${CADDYFILE_PATH}" || true
    fi
    if have_cmd journalctl; then
        lines="$(prompt_default "显示最近多少行 Caddy 日志" "80")"
        if [[ "${lines}" =~ ^[0-9]+$ && "${lines}" -ge 1 && "${lines}" -le 1000 ]]; then
            printf '\n'
            journalctl -u "${name}" -n "${lines}" --no-pager -o short-iso || true
        fi
    fi
}

install_self_report_https() {
    local domain ip_csv
    domain="$(normalize_self_report_https_domain "${SELF_REPORT_HTTPS_DOMAIN}")"
    validate_self_report_https_domain "${domain}" || return 1
    if ip_csv="$(resolve_ddns_ipv4_csv "${domain}" 2>/dev/null)"; then
        printf 'DNS A 记录：%s -> %s\n' "${domain}" "${ip_csv}"
    else
        printf '警告：当前机器未解析到 %s 的公网 IPv4。请确认 DNS 已指向 LAN Worker，且 80/443 已放行。\n' "${domain}" >&2
    fi
    ensure_caddy_installed || return 1
    ensure_caddyfile_import || return 1
    write_self_report_caddy_config "${domain}" || return 1
    caddy validate --config "${CADDYFILE_PATH}" || return 1
    SELF_REPORT_HTTPS_DOMAIN="${domain}"
    SELF_REPORT_LISTEN="${SELF_REPORT_HTTPS_BACKEND}"
    save_local_settings || return 1
    install_self_report_service || return 1
    if have_cmd systemctl; then
        systemctl enable caddy || return 1
        systemctl reload caddy 2>/dev/null || systemctl restart caddy || return 1
    fi
    printf 'Self-report HTTPS 已配置：https://%s/report\n' "${domain}"
    printf '健康检查：curl -fsS https://%s/health\n' "${domain}"
    printf '注意：公网建议只放行 80/443，不建议继续放行 8788。\n'
}
