restore_systemd_from_stage() {
    local work="$1" restored=0
    if [[ "${RESTORE_DRY_RUN}" == "1" ]]; then
        printf '[dry-run] regenerate LAN Worker systemd services from restored settings\n'
        return 0
    fi
    if [[ -f "${work}/system/po0-lan-self-report.service" ]]; then
        install_self_report_service || return 1
        restored=1
    fi
    if [[ -f "${work}/system/po0-lan-webauth.service" ]]; then
        install_webauth_service || return 1
        restored=1
    fi
    if [[ -f "${work}/system/po0-lan-manager-update.service" ]]; then
        install_manager_update_mirror_service || return 1
        restored=1
    fi
    [[ "${restored}" == "1" ]] || printf '备份包没有 LAN Worker systemd service 快照。\n'
}

lan_backup_import() {
    local archive="$1" work local_status
    [[ -n "${archive}" ]] || { printf '缺少备份包路径。\n' >&2; return 1; }
    [[ -r "${archive}" ]] || { printf '无法读取备份包：%s\n' "${archive}" >&2; return 1; }
    have_cmd tar || { printf '缺少 tar，无法导入备份包。\n' >&2; return 1; }
    validate_backup_tar_members "${archive}" || return 1
    work="$(mktemp -d "${TMPDIR:-/tmp}/po0-lan-restore.XXXXXX")" || return 1
    chmod 700 "${work}" 2>/dev/null || true
    tar -xzf "${archive}" -C "${work}" || {
        rm -rf "${work}" 2>/dev/null || true
        return 1
    }
    [[ -f "${work}/manifest.env" ]] || {
        rm -rf "${work}" 2>/dev/null || true
        printf '备份包缺少 manifest.env。\n' >&2
        return 1
    }
    local_status=0
    if lan_state_lock; then
        restore_file_from_stage "${work}/files/config/targets.tsv" "${CONFIG_FILE}" 600 || local_status=1
        restore_file_from_stage "${work}/files/config/settings.env" "${SETTINGS_FILE}" 600 || local_status=1
        restore_file_from_stage "${work}/files/state/stats.tsv" "${STATS_FILE}" 600 || local_status=1
        restore_file_from_stage "${work}/files/state/resource-stats.tsv" "${RESOURCE_STATS_FILE}" 600 || local_status=1
        restore_file_from_stage "${work}/files/state/resource-events.tsv" "${RESOURCE_EVENTS_FILE}" 600 || local_status=1
        lan_state_unlock
    else
        local_status=1
    fi
    restore_config_ssh_keys_from_stage "${work}" || local_status=1
    restore_identity_files_from_stage "${work}" || local_status=1
    if [[ "${local_status}" == "0" && "${RESTORE_DRY_RUN}" != "1" ]]; then
        load_local_settings || local_status=1
    fi
    if [[ "${RESTORE_CRON}" == "1" ]]; then
        restore_managed_cron_from_stage "${work}" || local_status=1
    fi
    if [[ "${RESTORE_CADDY}" == "1" ]]; then
        restore_caddy_from_stage "${work}" || local_status=1
    fi
    if [[ "${RESTORE_SYSTEMD}" == "1" ]]; then
        restore_systemd_from_stage "${work}" || local_status=1
    fi
    rm -rf "${work}" 2>/dev/null || true
    [[ "${local_status}" == "0" ]] || return 1
    if [[ "${RESTORE_DRY_RUN}" == "1" ]]; then
        printf 'LAN Worker 备份 dry-run 完成，未写入文件：%s\n' "${archive}"
    else
        printf 'LAN Worker 备份已导入：%s\n' "${archive}"
    fi
    if [[ "${RESTORE_CRON}${RESTORE_SYSTEMD}${RESTORE_CADDY}" == "000" ]]; then
        printf '默认仅恢复配置、状态和密钥；cron/systemd/Caddy 未恢复。需要时加 --restore-cron、--restore-systemd、--restore-caddy 或 --restore-all。\n'
    fi
}

backup_restore_interactive() {
    local choice path flags
    print_menu_section "LAN Worker 备份 / 恢复"
    print_menu_item 1 "导出完整备份"
    print_menu_item 2 "导入：只恢复配置、状态和密钥"
    print_menu_item 3 "导入：恢复全部（含 cron/systemd/Caddy）"
    print_menu_item 0 "返回"
    print_menu_footer
    read_menu_choice_or_return choice "请选择操作 [0-3]: " || return 0
    case "${choice}" in
        1)
            path="$(prompt_default "备份输出路径" "$(lan_backup_default_path)")"
            lan_backup_export "${path}"
            ;;
        2)
            path="$(prompt_default "备份包路径" "")"
            [[ -n "${path}" ]] || return 0
            RESTORE_CRON="0" RESTORE_SYSTEMD="0" RESTORE_CADDY="0"
            lan_backup_import "${path}"
            ;;
        3)
            path="$(prompt_default "备份包路径" "")"
            [[ -n "${path}" ]] || return 0
            printf '即将恢复 cron、systemd service 和 Caddy snippet；这会修改本机运行入口。\n'
            prompt_yes_no "确认继续" "n" || return 0
            RESTORE_CRON="1" RESTORE_SYSTEMD="1" RESTORE_CADDY="1"
            lan_backup_import "${path}"
            ;;
        0)
            return 0
            ;;
        *)
            printf '无效选择。\n' >&2
            return 1
            ;;
    esac
}

show_webauth_cloudflare_guide() {
    local domain
    domain="$(prompt_default "WebAuth 域名（例如 auth.example.com）" "<AUTH_DOMAIN>")"
    printf '\n%s\n' "WebAuth / Cloudflare Access 接入"
    printf '%s\n' "链路：Browser -> Cloudflare Access -> Cloudflare Tunnel -> LAN Worker ${WEBAUTH_LISTEN} -> SSH -> PO0"
    printf '%s\n' ""
    printf '%s\n' "cloudflared ingress 配置片段："
    cat <<EOF
ingress:
  - hostname: ${domain}
    service: http://${WEBAUTH_LISTEN}
  - service: http_status:404
EOF
    printf '%s\n' ""
    printf '%s\n' "Cloudflare 控制台动作："
    printf '%s\n' "  1. 创建 Cloudflare Tunnel，并让 cloudflared 运行在 LAN Worker。"
    printf '%s\n' "  2. Public hostname 绑定 ${domain}，service 指向 http://${WEBAUTH_LISTEN}。"
    printf '%s\n' "  3. Access -> Applications -> Add application -> Self-hosted。"
    printf '%s\n' "  4. 应用域名填写 ${domain}。"
    printf '%s\n' "  5. 配置允许登录的邮箱、域名或 Access group。"
    printf '%s\n' "  6. 确认该 hostname 受 Access 保护。"
    printf '%s\n' ""
    printf '%s\n' "本地检查命令："
    printf '  cloudflared tunnel ingress validate\n'
    printf '  cloudflared tunnel ingress rule https://%s\n' "${domain}"
    printf '%s\n' ""
    printf '%s\n' "LAN Worker 启动命令："
    printf '  po0-lan-client --webauth-server --listen %s\n' "${WEBAUTH_LISTEN}"
    printf '%s\n' "PO0 不开放 HTTP；Cloudflare 只连接 LAN Worker。"
}

manage_ddns_settings_interactive() {
    local choice
    while true; do
        menu_clear_screen
        print_title "DDNS 目标 / 上报计划"
        show_ddns_ttl_help
        print_menu_section "DDNS 目标"
        print_menu_pair 1 "查看目标与统计" 2 "添加 DDNS / PO0 目标"
        print_menu_pair 3 "编辑目标" 4 "目标 Token"
        print_menu_item 5 "启用 / 停用目标"

        print_menu_section "本机上报"
        print_menu_pair 6 "安装 / 更新 DDNS 上报计划" 7 "立即执行 DDNS 上报"

        print_menu_section "退出"
        print_menu_item 0 "返回"
        print_menu_footer
        read_menu_choice_or_return choice "请选择操作 [0-7]: " || return 0
        case "${choice}" in
            1) list_targets; pause_before_return ;;
            2) add_target_interactive; pause_before_return ;;
            3) edit_target_interactive; pause_before_return ;;
            4) manage_target_tokens_interactive; pause_before_return ;;
            5) toggle_target_interactive; pause_before_return ;;
            6) install_ddns_cron_interactive; pause_before_return ;;
            7) run_config_targets; pause_before_return ;;
            0) return 0 ;;
            "") ;;
            *) printf '无效选择。\n' >&2; pause_before_return ;;
        esac
    done
}

show_self_report_settings() {
    local targets line source host port user script token ttl extra https_domain
    targets="$(self_report_targets_env 2>/dev/null || true)"
    https_domain="$(current_self_report_https_domain)"
    print_panel_section "Self-report 接收端"
    print_panel_row "监听地址" "${SELF_REPORT_LISTEN}"
    print_panel_row "HTTPS 入口" "$(if [[ -n "${https_domain}" ]]; then printf 'https://%s/report' "${https_domain}"; else printf '未配置'; fi)"
    print_panel_row "Secret" "$(mask_secret "${SELF_REPORT_SECRET}")"
    print_panel_row "默认 source" "${SELF_REPORT_SOURCE}"
    print_panel_row "默认 TTL" "${SELF_REPORT_TTL_SECONDS:-43200} 秒"
    print_panel_row "后台服务" "$(self_report_service_summary)"
    if [[ -n "${targets}" ]]; then
        print_panel_row "PO0 目标" "已配置"
        while IFS= read -r line || [[ -n "${line}" ]]; do
            [[ -n "${line}" ]] || continue
            IFS='|' read -r source host port user script token ttl extra <<< "${line}"
            print_panel_note "${source:-self-report}@${host}:${port:-22} ttl=${ttl:-43200} token=$(mask_secret "${token}")"
        done <<< "${targets}"
    else
        print_panel_row "PO0 目标" "未配置；先在主菜单添加 PO0 目标并设置 Self-report client-ip Token"
    fi
}

edit_self_report_listen_interactive() {
    SELF_REPORT_LISTEN="$(prompt_default "Self-report 本地监听地址" "${SELF_REPORT_LISTEN:-127.0.0.1:8788}")"
    [[ -n "${SELF_REPORT_LISTEN}" ]] || SELF_REPORT_LISTEN="127.0.0.1:8788"
    save_local_settings || return 1
    printf '已设置本次菜单会话监听地址：%s\n' "${SELF_REPORT_LISTEN}"
    printf '已保存本机设置：%s\n' "${SETTINGS_FILE}"
    printf '安装 / 更新后台服务后，该监听地址会写入 systemd service。\n'
}

edit_self_report_secret_interactive() {
    local generated value
    generated="$(random_secret)"
    if [[ -n "${SELF_REPORT_SECRET}" ]]; then
        printf '当前 Self-report secret：%s\n' "${SELF_REPORT_SECRET}"
        value="$(read_prompt "新的 Self-report secret [回车保留，输入 g 生成新值，输入 - 清空]: ")" || value=""
        value="$(trim "${value}")"
        case "${value}" in
            "") ;;
            g|G)
                SELF_REPORT_SECRET="${generated}"
                ;;
            -)
                SELF_REPORT_SECRET=""
                ;;
            *)
                SELF_REPORT_SECRET="${value}"
                ;;
        esac
    else
        value="$(prompt_default "Self-report secret（回车使用自动生成值）" "${generated}")"
        SELF_REPORT_SECRET="${value}"
    fi
    if [[ -n "${SELF_REPORT_SECRET}" ]]; then
        printf 'Self-report secret 已设置为：%s\n' "${SELF_REPORT_SECRET}"
        printf 'Linux/macOS/OpenWrt 使用：export PO0_SELF_REPORT_SECRET=%s\n' "$(sh_quote "${SELF_REPORT_SECRET}")"
        printf 'Windows PowerShell 使用：$env:PO0_SELF_REPORT_SECRET=%s\n' "$(ps_quote "${SELF_REPORT_SECRET}")"
    else
        printf 'Self-report secret 已清空；接收端将不校验访问设备 secret。\n'
    fi
    save_local_settings || return 1
    printf '已保存本机设置：%s\n' "${SETTINGS_FILE}"
}

configure_self_report_https_interactive() {
    local domain default_domain
    default_domain="$(current_self_report_https_domain)"
    domain="$(prompt_default "Self-report HTTPS 域名（DNS 已指向 LAN Worker）" "${default_domain}")"
    domain="$(normalize_self_report_https_domain "${domain}")"
    validate_self_report_https_domain "${domain}" || return 1
    SELF_REPORT_HTTPS_DOMAIN="${domain}"
    SELF_REPORT_LISTEN="${SELF_REPORT_HTTPS_BACKEND}"
    save_local_settings || return 1
    printf '将配置 HTTPS 入口：https://%s/report\n' "${domain}"
    printf 'Self-report 后端将只监听本机：%s\n' "${SELF_REPORT_LISTEN}"
    printf '请确认云安全组/防火墙已放行 TCP 80/443；公网不建议放行 8788。\n'
    if prompt_yes_no "继续安装 / 更新 Caddy HTTPS 和 Self-report 后台服务" "y"; then
        install_self_report_https
    else
        printf '已取消。\n'
    fi
}

manage_self_report_server_interactive() {
    local choice
    while true; do
        menu_clear_screen
        print_title "Self-report 配置 / 启动"
        show_self_report_settings
        print_menu_section "配置"
        print_menu_pair 1 "查看 PO0 目标" 2 "目标 Token"
        print_menu_pair 3 "Self-report source / TTL" 4 "设置监听地址"
        print_menu_item 5 "生成 / 修改 Self-report secret"

        print_menu_section "运行"
        print_menu_pair 6 "连通性检查" 7 "安装 / 更新后台服务"
        print_menu_pair 8 "查看后台服务状态" 9 "查看最近后台日志"
        print_menu_pair 10 "实时跟随后台日志" 11 "配置 HTTPS 域名 / Caddy"
        print_menu_pair 12 "查看 HTTPS / Caddy 状态日志" 13 "前台启动服务"

        print_menu_section "退出"
        print_menu_item 0 "返回"
        print_menu_footer
        read_menu_choice_or_return choice "请选择操作 [0-13]: " || return 0
        case "${choice}" in
            1) list_targets; pause_before_return ;;
            2) manage_target_tokens_interactive; pause_before_return ;;
            3) manage_target_self_report_ttl_interactive; pause_before_return ;;
            4) edit_self_report_listen_interactive; pause_before_return ;;
            5) edit_self_report_secret_interactive; pause_before_return ;;
            6) probe_self_report_target; pause_before_return ;;
            7) install_self_report_service; pause_before_return ;;
            8) show_self_report_service_status; pause_before_return ;;
            9) show_self_report_service_logs; pause_before_return ;;
            10) follow_self_report_service_logs ;;
            11) configure_self_report_https_interactive; pause_before_return ;;
            12) show_self_report_https_status; pause_before_return ;;
            13)
                printf '即将前台启动 Self-report 服务；运行后会占用当前终端，按 Ctrl+C 退出。\n'
                pause_before_return
                run_self_report_server
                ;;
            0) return 0 ;;
            "") ;;
            *) printf '无效选择。\n' >&2; pause_before_return ;;
        esac
    done
}
