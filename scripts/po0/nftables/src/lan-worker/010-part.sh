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

self_report_service_summary() {
    local name="po0-lan-self-report.service" unit="/etc/systemd/system/po0-lan-self-report.service" active enabled unit_ttl current_ttl
    have_cmd systemctl || {
        printf 'systemctl 不可用'
        return 0
    }
    active="$(systemctl is-active "${name}" 2>/dev/null || true)"
    enabled="$(systemctl is-enabled "${name}" 2>/dev/null || true)"
    printf 'active=%s enabled=%s' "${active:-unknown}" "${enabled:-unknown}"
    unit_ttl="$(unit_exec_arg_value "${unit}" "--self-report-ttl" 2>/dev/null || true)"
    current_ttl="$(normalize_report_ttl_seconds "${SELF_REPORT_TTL_SECONDS:-43200}" 43200)"
    if [[ -n "${unit_ttl}" ]]; then
        unit_ttl="$(normalize_report_ttl_seconds "${unit_ttl}" "${current_ttl}")"
        if [[ "${unit_ttl}" != "${current_ttl}" ]]; then
            printf ' unit-ttl=%s' "${unit_ttl}"
            [[ "${unit_ttl}" == "3600" ]] && printf '（旧默认；安装/更新服务后刷新）'
        fi
    fi
}

show_self_report_service_status() {
    local name="po0-lan-self-report.service"
    have_cmd systemctl || {
        printf '当前系统没有 systemctl，无法查看后台服务状态。\n' >&2
        return 1
    }
    print_panel_section "Self-report 后台服务状态"
    print_panel_row "服务" "${name}"
    print_panel_row "汇总" "$(self_report_service_summary)"
    printf '\n'
    systemctl status "${name}" --no-pager --full || true
}

show_self_report_service_logs() {
    local name="po0-lan-self-report.service" lines
    have_cmd journalctl || {
        printf '当前系统没有 journalctl，无法查看 systemd 日志。\n' >&2
        return 1
    }
    lines="$(prompt_default "显示最近多少行 Self-report 日志" "120")"
    if [[ ! "${lines}" =~ ^[0-9]+$ || "${lines}" -lt 1 || "${lines}" -gt 1000 ]]; then
        printf '日志行数必须是 1-1000。\n' >&2
        return 1
    fi
    print_panel_section "Self-report 最近日志"
    print_panel_row "服务" "${name}"
    print_panel_row "行数" "${lines}"
    printf '\n'
    journalctl -u "${name}" -n "${lines}" --no-pager -o short-iso || true
}

follow_self_report_service_logs() {
    local name="po0-lan-self-report.service"
    have_cmd journalctl || {
        printf '当前系统没有 journalctl，无法实时查看 systemd 日志。\n' >&2
        return 1
    }
    printf '正在实时查看 %s 日志；按 Ctrl+C 退出。\n' "${name}"
    journalctl -u "${name}" -f -o short-iso
}

normalize_cron_minutes() {
    local minutes="${1:-}"
    local max="${2:-1440}"
    minutes="$(trim "${minutes}")"
    [[ "${max}" =~ ^[0-9]+$ && "${max}" -ge 1 ]] || max=1440
    [[ "${minutes}" =~ ^[0-9]+$ && "${minutes}" -ge 1 && "${minutes}" -le "${max}" ]] || return 1
    printf '%s\n' "${minutes}"
}

normalize_interval_seconds_to_minutes() {
    local seconds="${1:-}"
    local max_minutes="${2:-1440}"
    local max_seconds
    seconds="$(trim "${seconds}")"
    [[ "${max_minutes}" =~ ^[0-9]+$ && "${max_minutes}" -ge 1 ]] || max_minutes=1440
    max_seconds=$((max_minutes * 60))
    [[ "${seconds}" =~ ^[0-9]+$ ]] || return 1
    (( seconds >= 60 && seconds <= max_seconds )) || return 1
    (( seconds % 60 == 0 )) || return 1
    printf '%s\n' "$((seconds / 60))"
}

cron_minutes_to_seconds() {
    local minutes="${1:-}"
    [[ "${minutes}" =~ ^[0-9]+$ && "${minutes}" -ge 1 ]] || minutes=60
    printf '%s\n' "$((10#${minutes} * 60))"
}

cron_interval_label() {
    local minutes="$1"
    if (( minutes == 1440 )); then
        printf '每天'
    elif (( minutes > 1440 && minutes % 1440 == 0 )); then
        printf '每 %s 天' "$((minutes / 1440))"
    elif (( minutes == 60 )); then
        printf '每小时'
    elif (( minutes > 60 && minutes % 60 == 0 )); then
        printf '每 %s 小时' "$((minutes / 60))"
    else
        printf '每 %s 分钟' "${minutes}"
    fi
}

build_worker_cron_job() {
    local minutes="$1"
    local action="$2"
    local script_path="$3"
    local log_path="$4"
    local run_cmd schedule hours
    run_cmd="bash $(sh_quote "${script_path}") --config $(sh_quote "${CONFIG_FILE}") ${action}"
    if (( minutes < 60 )); then
        schedule="*/${minutes} * * * *"
        printf '%s %s >%s 2>&1\n' "${schedule}" "${run_cmd}" "$(sh_quote "${log_path}")"
    elif (( minutes == 60 )); then
        printf '0 * * * * %s >%s 2>&1\n' "${run_cmd}" "$(sh_quote "${log_path}")"
    elif (( minutes < 1440 && minutes % 60 == 0 )); then
        hours=$((minutes / 60))
        printf '0 */%s * * * %s >%s 2>&1\n' "${hours}" "${run_cmd}" "$(sh_quote "${log_path}")"
    elif (( minutes == 1440 )); then
        printf '0 0 * * * %s >%s 2>&1\n' "${run_cmd}" "$(sh_quote "${log_path}")"
    elif (( minutes % 60 == 0 )); then
        hours=$((minutes / 60))
        printf '0 * * * * now=$(date +\%%s); if [ $((now / 3600 \%% %s)) -eq 0 ]; then %s >%s 2>&1; fi\n' "${hours}" "${run_cmd}" "$(sh_quote "${log_path}")"
    else
        printf '* * * * now=$(date +\%%s); if [ $((now / 60 \%% %s)) -eq 0 ]; then %s >%s 2>&1; fi\n' "${minutes}" "${run_cmd}" "$(sh_quote "${log_path}")"
    fi
}

print_cron_example() {
    local requested_ddns_minutes="${1:-}"
    local requested_resource_minutes="${2:-}"
    local script_path resource_minutes ddns_minutes resource_label ddns_label
    if ! resource_minutes="$(normalize_cron_minutes "${requested_resource_minutes:-${RESOURCE_CRON_MINUTES}}" "${RESOURCE_CRON_MAX_MINUTES}")"; then
        resource_minutes="$(normalize_cron_minutes "${RESOURCE_CRON_MINUTES}" "${RESOURCE_CRON_MAX_MINUTES}" 2>/dev/null || printf '1440')"
    fi
    if ! ddns_minutes="$(normalize_cron_minutes "${requested_ddns_minutes:-${DDNS_CRON_MINUTES}}" "${DDNS_CRON_MAX_MINUTES}")"; then
        ddns_minutes="$(normalize_cron_minutes "${DDNS_CRON_MINUTES}" "${DDNS_CRON_MAX_MINUTES}" 2>/dev/null || printf '60')"
    fi
    resource_label="$(cron_interval_label "${resource_minutes}")"
    ddns_label="$(cron_minutes_to_seconds "${ddns_minutes}") 秒"
    script_path="$(script_self_path)"
    printf '%s\n' \
        "本机资源任务领取示例（${resource_label}检查 PO0 pending 任务）：" \
        "$(build_worker_cron_job "${resource_minutes}" "--run-resource" "${script_path}" "/tmp/po0-lan-resource.log")" \
        "本机 DDNS resolver 示例（${ddns_label}解析并上报 DDNS）：" \
        "$(build_worker_cron_job "${ddns_minutes}" "--run-ddns" "${script_path}" "/tmp/po0-lan-ddns.log")"
}

managed_cron_job_for_action() {
    local action="$1"
    local begin end line in_block=0
    have_cmd crontab || return 1
    begin="$(cron_begin_marker)"
    end="$(cron_end_marker)"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" == "${begin}" ]]; then
            in_block=1
            continue
        fi
        if [[ "${line}" == "${end}" ]]; then
            in_block=0
            continue
        fi
        [[ "${in_block}" == "1" ]] || continue
        [[ "${line}" == *" ${action}"* || "${line}" == *" ${action} "* ]] || continue
        printf '%s\n' "${line}"
        return 0
    done < <(crontab -l 2>/dev/null || true)
    return 1
}

default_install_path() {
    if [[ -n "${INSTALL_PATH}" ]]; then
        printf '%s\n' "${INSTALL_PATH}"
    elif [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]]; then
        printf '%s\n' "/usr/local/sbin/po0-lan-client"
    elif [[ -n "${HOME:-}" ]]; then
        printf '%s\n' "${HOME}/.local/bin/po0-lan-client"
    else
        printf '%s\n' "./po0-lan-client"
    fi
}

script_source_path() {
    local script="${BASH_SOURCE[0]}"
    if [[ "${script}" != */* ]]; then
        script="$(command -v "${script}" 2>/dev/null || printf '%s' "${script}")"
    fi
    case "${script}" in
        /*)
            printf '%s\n' "${script}"
            ;;
        *)
            printf '%s/%s\n' "$(pwd -P)" "${script}"
            ;;
    esac
}

is_transient_script_path() {
    case "$1" in
        /dev/fd/*|/proc/self/fd/*|/proc/*/fd/*|/dev/stdin|*/bash|*/sh)
            return 0
            ;;
    esac
    [[ -r "$1" ]] || return 0
    return 1
}

script_self_path() {
    local script
    script="$(script_source_path)"
    if ! is_transient_script_path "${script}"; then
        printf '%s\n' "${script}"
        return 0
    fi
    default_install_path
}

install_self() {
    local src dest dir
    src="$(script_source_path)"
    dest="$(default_install_path)"
    dir="$(path_dirname "${dest}")"
    mkdir -p "${dir}" || return 1
    if ! is_transient_script_path "${src}" && [[ -r "${src}" && "${src}" != */bash && "${src}" != */sh ]]; then
        if [[ -e "${dest}" ]] && [[ "${src}" -ef "${dest}" ]]; then
            :
        else
            cp "${src}" "${dest}" || return 1
        fi
    elif have_cmd curl; then
        curl -fsSL --connect-timeout 15 --max-time 180 "${DOWNLOAD_URL}" -o "${dest}" || return 1
    elif have_cmd wget; then
        wget -q --timeout=180 -O "${dest}" "${DOWNLOAD_URL}" || return 1
    else
        printf '无法落盘：当前脚本不可复制，且系统缺少 curl/wget。\n' >&2
        return 1
    fi
    chmod 755 "${dest}" 2>/dev/null || true
    printf '%s\n' "${dest}"
}

upgrade_self_from_download() {
    local reopen_mode="${1:-}"
    local dest dir tmp legacy_scp_cmd legacy_scp_var old_version new_version changelog chmod_message
    old_version="${SCRIPT_VERSION}"
    dest="$(default_install_path)"
    dir="$(path_dirname "${dest}")"
    mkdir -p "${dir}" || return 1
    tmp="${dest}.tmp.$$"
    if have_cmd curl; then
        curl -fsSL --connect-timeout 15 --max-time 180 "${DOWNLOAD_URL}" -o "${tmp}" || {
            rm -f -- "${tmp}" 2>/dev/null || true
            return 1
        }
    elif have_cmd wget; then
        wget -q --timeout=180 -O "${tmp}" "${DOWNLOAD_URL}" || {
            rm -f -- "${tmp}" 2>/dev/null || true
            return 1
        }
    else
        printf '无法更新：系统缺少 curl/wget。\n' >&2
        return 1
    fi
    legacy_scp_cmd="scp .*"
    legacy_scp_cmd+="upload_path"
    legacy_scp_var="scp"
    legacy_scp_var+="_args"
    if grep -q -- "${legacy_scp_cmd}" "${tmp}" || grep -q -- "${legacy_scp_var}" "${tmp}" || ! grep -q -- '--resource-task-upload' "${tmp}"; then
        rm -f -- "${tmp}" 2>/dev/null || true
        printf '更新文件校验失败：下载到的脚本不是 manager stdin 上传版。\n' >&2
        return 1
    fi
    new_version="$(script_file_var "${tmp}" "SCRIPT_VERSION" 2>/dev/null || true)"
    changelog="$(script_file_changelog "${tmp}" 2>/dev/null || true)"
    chmod 755 "${tmp}" 2>/dev/null || true
    mv -f "${tmp}" "${dest}" || {
        rm -f -- "${tmp}" 2>/dev/null || true
        return 1
    }
    if chmod 755 "${dest}" 2>/dev/null; then
        chmod_message="已设置执行权限：chmod 755 ${dest}"
    else
        chmod_message="警告：已更新，但自动设置执行权限失败；请手动执行 chmod 755 ${dest}"
    fi
    printf '已更新本机命令：%s\n' "${dest}"
    printf '%s\n' "${chmod_message}"
    if [[ -n "${new_version}" ]]; then
        if [[ "${new_version}" == "${old_version}" ]]; then
            printf '版本：%s（与当前执行脚本相同）\n' "${new_version}"
        else
            printf '版本：%s -> %s\n' "${old_version}" "${new_version}"
        fi
    fi
    if [[ -n "${changelog}" ]]; then
        printf '更新内容：\n%s\n' "${changelog}"
    else
        printf '更新内容：新脚本未提供更新说明；请运行 --version 查看当前状态。\n'
    fi
    if [[ "${reopen_mode}" == "--reopen-menu" ]]; then
        read_prompt "更新完成。按回车打开新版菜单..." >/dev/null || true
        printf '正在重新打开新版菜单：%s --menu\n' "${dest}"
        exec "${BASH:-bash}" "${dest}" --config "${CONFIG_FILE}" --install-path "${dest}" --menu
        printf '重新打开新版脚本失败，请手动执行：%s --menu\n' "${dest}" >&2
        return 1
    fi
}

ensure_persistent_script() {
    local script
    script="$(script_source_path)"
    if ! is_transient_script_path "${script}"; then
        printf '%s\n' "${script}"
        return 0
    fi
    install_self
}

show_local_script_status() {
    local current install_path cron_summary
    current="$(script_source_path)"
    install_path="$(default_install_path)"
    print_panel_section "本机脚本"
    print_panel_row "脚本名称" "${SCRIPT_NAME}"
    print_panel_row "版本" "${SCRIPT_VERSION}"
    print_panel_row "发布日期" "${SCRIPT_RELEASE_DATE}"
    print_panel_row "当前脚本" "${current}"
    print_panel_row "默认安装路径" "${install_path}"
    print_panel_row "下载 URL" "${DOWNLOAD_URL}"
    cron_summary="$(cron_status_summary)"
    print_panel_row "本机轮询器" "${cron_summary}"
}

cron_begin_marker() {
    printf '# PO0_LAN_CLIENT_BEGIN %s\n' "${CONFIG_FILE}"
}

cron_end_marker() {
    printf '# PO0_LAN_CLIENT_END %s\n' "${CONFIG_FILE}"
}

write_cron_without_managed_block() {
    local begin end line in_block=0
    begin="$(cron_begin_marker)"
    end="$(cron_end_marker)"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" == "${begin}" ]]; then
            in_block=1
            continue
        fi
        if [[ "${line}" == "${end}" ]]; then
            in_block=0
            continue
        fi
        [[ "${in_block}" == "1" ]] && continue
        printf '%s\n' "${line}"
    done
}

count_enabled_worker_targets() {
    local kind="$1"
    local line count=0
    ensure_config_file || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        [[ "${TARGET_ENABLED}" == "1" ]] || continue
        case "${kind}" in
            ddns)
                [[ "${TARGET_REPORT_MODE}" == "ddns" && -n "${TARGET_DOMAIN}" && -n "${TARGET_DDNS_RESOLVE_DOMAIN}" ]] && count=$((count + 1))
                ;;
            resource)
                [[ -n "${TARGET_RESOURCE_TOKEN}" ]] && count=$((count + 1))
                ;;
        esac
    done < "${CONFIG_FILE}"
    printf '%s\n' "${count}"
}
