po0_lan_wizard() {
    local key_path extra ssh_response ssh_ok=0
    local use_resource=0 use_ddns=0 use_self_report=0 use_webauth=0
    local label install_periodic=0 ddns_cron_minutes resource_cron_minutes run_now=0 script_path
    local generated_secret

    print_title "PO0 LAN Worker 安装向导"
    printf '此向导会把 token 明文保存到本机配置文件：%s\n' "${CONFIG_FILE}"
    printf 'PO0 自动取 token 需要当前机器已经可以通过密钥 SSH 登录 PO0。\n\n'

    PO0_HOST="$(prompt_default "PO0 SSH 地址" "${PO0_HOST}")"
    [[ -n "${PO0_HOST}" ]] || { printf 'PO0 SSH 地址不能为空。\n' >&2; return 1; }
    PO0_PORT="$(prompt_default "PO0 SSH 端口" "${PO0_PORT:-22}")"
    PO0_USER="$(prompt_default "PO0 SSH 用户" "${PO0_USER:-root}")"
    PO0_SCRIPT="$(prompt_default "PO0 管理脚本路径" "${PO0_SCRIPT:-${DEFAULT_PO0_SCRIPT}}")"
    print_menu_section "SSH 认证方式"
    print_menu_item 1 "使用系统默认 SSH 配置 / agent"
    print_menu_item 2 "填写私钥文件路径"
    print_menu_item 3 "粘贴私钥并保存到本机"
    print_menu_footer
    case "$(prompt_default "请选择" "1")" in
        2)
            key_path="$(prompt_ssh_key_path_or_paste "SSH 私钥路径（路径不要含空格）" "" "${PO0_HOST}" "${PO0_PORT}" "${PO0_USER}")"
            ;;
        3)
            key_path="$(save_pasted_ssh_key "${PO0_HOST}" "${PO0_PORT}" "${PO0_USER}")" || return 1
            printf '[OK] 已保存 SSH 私钥：%s\n' "${key_path}"
            ;;
        *)
            key_path=""
            ;;
    esac
    extra="$(prompt_ssh_extra_args "额外 SSH 参数，可空（不是私钥短语；例如 -J jump-host 或 -o StrictHostKeyChecking=accept-new）" "${SSH_EXTRA_ARGS}" "${PO0_HOST}" "${PO0_PORT}" "${PO0_USER}")" || return 1
    SSH_EXTRA_ARGS="$(build_batchmode_ssh_extra_args "${key_path}" "${extra}")" || return 1

    printf '\n检查密钥 SSH 和 PO0 管理脚本...\n'
    if ssh_response="$(remote_manager_call "${PO0_HOST}" "${PO0_PORT}" "${PO0_USER}" "${PO0_SCRIPT}" "${SSH_EXTRA_ARGS}" --help 2>&1)"; then
        ssh_ok=1
        printf '[OK] SSH 可用：%s@%s:%s\n' "${PO0_USER}" "${PO0_HOST}" "${PO0_PORT}"
    else
        printf '[WARN] 密钥 SSH 检查失败：%s\n' "${ssh_response}" >&2
        print_host_key_failure_help "${PO0_HOST}" "${PO0_PORT}" "${PO0_USER}" "${ssh_response}"
        printf '可以继续手动粘贴 token 并保存配置，但不要安装本机 Worker 轮询器或 service，直到免密 SSH 可用。\n' >&2
    fi

    print_menu_section "本机角色"
    prompt_yes_no "启用资源任务 Worker（领取 PO0 的 iplist/ipdb 更新任务）" "y" && use_resource=1
    prompt_yes_no "启用 DDNS resolver（本机解析 DDNS 后 SSH 上报 PO0）" "y" && use_ddns=1
    prompt_yes_no "启用 Self-report server 目标配置（访问设备先报本机，再由本机报 PO0）" "n" && use_self_report=1
    prompt_yes_no "启用 WebAuth server 目标配置（本机接收认证入口，再由本机报 PO0）" "n" && use_webauth=1

    if (( use_resource == 0 && use_ddns == 0 && use_self_report == 0 && use_webauth == 0 )); then
        printf '至少需要选择一个角色。\n' >&2
        return 1
    fi

    if (( ssh_ok == 1 )); then
        if fetch_worker_token_bundle "${use_resource}" 2>/dev/null; then
            printf '[OK] 已从 PO0 自动读取所需 token。\n'
        else
            printf '[WARN] SSH 可用，但未能自动读取 token；稍后请手动粘贴需要的 token。\n' >&2
        fi
    fi

    if (( use_ddns == 1 )); then
        REPORT_MODE="ddns"
        DDNS_RESOLVE_DOMAIN="$(prompt_default "LAN Worker 要解析的 DDNS 域名" "${DDNS_RESOLVE_DOMAIN:-${DDNS_DOMAIN}}")"
        [[ -n "${DDNS_RESOLVE_DOMAIN}" ]] || { printf 'DDNS resolver 必须填写 DDNS 域名。\n' >&2; return 1; }
        DDNS_DOMAIN="$(prompt_default "PO0 来源 key（默认同 DDNS 域名）" "${DDNS_DOMAIN:-${DDNS_RESOLVE_DOMAIN}}")"
        REPORT_KEY="$(prompt_default "PO0 匹配 key（默认同来源 key）" "${REPORT_KEY:-${DDNS_DOMAIN}}")"
        DDNS_TOKEN="$(prompt_default "DDNS 来源上报 token" "${DDNS_TOKEN}")"
        [[ -n "${DDNS_TOKEN}" ]] || { printf 'DDNS resolver 需要 DDNS token。\n' >&2; return 1; }
    else
        REPORT_MODE="none"
        DDNS_DOMAIN=""
        REPORT_KEY=""
        DDNS_RESOLVE_DOMAIN=""
    fi

    if (( use_resource == 1 )); then
        RESOURCE_TOKEN="$(prompt_default "资源任务 Token" "${RESOURCE_TOKEN}")"
        [[ -n "${RESOURCE_TOKEN}" ]] || { printf '资源任务 Worker 需要 resource token。\n' >&2; return 1; }
    else
        RESOURCE_TOKEN=""
    fi

    if (( use_self_report == 1 )); then
        CLIENT_IP_TOKEN="$(prompt_default "Client IP 上报 token" "${CLIENT_IP_TOKEN}")"
        [[ -n "${CLIENT_IP_TOKEN}" ]] || { printf 'Self-report 需要 client-ip token。\n' >&2; return 1; }
        SELF_REPORT_SOURCE="$(prompt_default "Self-report source id" "${SELF_REPORT_SOURCE:-self-report}")"
        if prompt_yes_no "使用 Self-report HTTPS 域名 / Caddy（推荐；DNS 需已指向本机）" "y"; then
            SELF_REPORT_HTTPS_DOMAIN="$(prompt_default "Self-report HTTPS 域名" "${SELF_REPORT_HTTPS_DOMAIN}")"
            SELF_REPORT_HTTPS_DOMAIN="$(normalize_self_report_https_domain "${SELF_REPORT_HTTPS_DOMAIN}")"
            validate_self_report_https_domain "${SELF_REPORT_HTTPS_DOMAIN}" || return 1
            SELF_REPORT_LISTEN="${SELF_REPORT_HTTPS_BACKEND}"
        else
            SELF_REPORT_LISTEN="$(prompt_default "Self-report 本地监听地址（HTTP 直连，不推荐公网暴露）" "${SELF_REPORT_LISTEN:-127.0.0.1:8788}")"
        fi
        generated_secret="$(random_secret)"
        SELF_REPORT_SECRET="$(prompt_default "Self-report secret（访问设备上报 LAN Worker 用）" "${SELF_REPORT_SECRET:-${generated_secret}}")"
        SELF_REPORT_TTL_SECONDS="$(prompt_default "Self-report 白名单有效期（TTL，秒）" "${SELF_REPORT_TTL_SECONDS:-43200}")"
        SELF_REPORT_TTL_SECONDS="$(normalize_report_ttl_seconds "${SELF_REPORT_TTL_SECONDS}" 43200)"
    else
        CLIENT_IP_TOKEN=""
    fi

    if (( use_webauth == 1 )); then
        WEBAUTH_TOKEN="$(prompt_default "WebAuth 上报 token" "${WEBAUTH_TOKEN}")"
        [[ -n "${WEBAUTH_TOKEN}" ]] || { printf 'WebAuth 需要 webauth token。\n' >&2; return 1; }
        WEBAUTH_SOURCE="$(prompt_default "WebAuth source id" "${WEBAUTH_SOURCE:-cf-access}")"
        WEBAUTH_LISTEN="$(prompt_default "WebAuth 本地监听地址" "${WEBAUTH_LISTEN:-127.0.0.1:8787}")"
        WEBAUTH_TTL_SECONDS="$(prompt_default "WebAuth 白名单有效期（TTL，秒）" "${WEBAUTH_TTL_SECONDS:-43200}")"
        WEBAUTH_TTL_SECONDS="$(normalize_report_ttl_seconds "${WEBAUTH_TTL_SECONDS}" 43200)"
    else
        WEBAUTH_TOKEN=""
    fi

    label="$(prompt_default "显示名" "${BOOTSTRAP_LABEL:-${DDNS_DOMAIN:-resource-${PO0_HOST}}}")"
    upsert_target "1" "${label}" "${DDNS_DOMAIN}" "${REPORT_KEY}" "${PO0_HOST}" "${PO0_PORT}" "${PO0_USER}" "${PO0_SCRIPT}" "${DDNS_TOKEN}" "${SSH_EXTRA_ARGS}" "${RESOURCE_TOKEN}" "${REPORT_MODE}" "${DDNS_RESOLVE_DOMAIN}" "${CLIENT_IP_TOKEN}" "${SELF_REPORT_SOURCE}" "${SELF_REPORT_TTL_SECONDS}" "${WEBAUTH_TOKEN}" "${WEBAUTH_SOURCE}" "${WEBAUTH_TTL_SECONDS}" "${SSH_EXTRA_ARGS}" || return 1
    chmod 600 "${CONFIG_FILE}" 2>/dev/null || true
    save_local_settings || return 1
    printf '\n[OK] 已写入配置：%s\n' "${CONFIG_FILE}"
    printf '[OK] 已写入本机设置：%s\n' "${SETTINGS_FILE}"
    script_path="$(ensure_persistent_script)" || return 1
    printf '[OK] 已安装本机命令：%s\n' "${script_path}"

    if (( ssh_ok == 1 )); then
        if (( use_ddns == 1 || use_resource == 1 )); then
            probe_worker_target || printf '[WARN] DDNS/资源任务连通性/权限检查未全部通过，请按上方错误修正后再安装本机 Worker 轮询器。\n' >&2
        fi
        (( use_self_report == 1 )) && probe_self_report_target || true
        (( use_webauth == 1 )) && probe_webauth_target || true
    fi

    if (( use_ddns == 1 || use_resource == 1 )); then
        if (( ssh_ok == 1 )); then
            if prompt_yes_no "安装/更新本机 Worker 轮询器（资源创建周期在 PO0 设置）" "y"; then
                install_periodic=1
                if (( use_resource == 1 )); then
                    resource_cron_minutes="$(prompt_default "资源任务每几分钟检查一次（1-${RESOURCE_CRON_MAX_MINUTES}；只领取 PO0 已创建任务）" "${RESOURCE_CRON_MINUTES}")"
                fi
                if (( use_ddns == 1 )); then
                    ddns_cron_seconds="$(prompt_default "DDNS resolver 每几秒上报一次（60-$((DDNS_CRON_MAX_MINUTES * 60))；必须是 60 的倍数）" "$(cron_minutes_to_seconds "${DDNS_CRON_MINUTES}")")"
                    ddns_cron_minutes="$(normalize_interval_seconds_to_minutes "${ddns_cron_seconds}" "${DDNS_CRON_MAX_MINUTES}")" || {
                        printf 'DDNS 上报间隔秒数无效：请输入 60-%s 且为 60 倍数的整数。\n' "$((DDNS_CRON_MAX_MINUTES * 60))" >&2
                        return 1
                    }
                fi
                install_worker_crons "${ddns_cron_minutes:-}" "${resource_cron_minutes:-}" "${script_path}" || return 1
            fi
            prompt_yes_no "现在立即执行一次 DDNS 上报/资源任务轮询" "y" && run_now=1
            (( run_now == 1 )) && run_all_client_jobs
        else
            printf '[WARN] 跳过本机 Worker 轮询器安装：免密 SSH 未通过。\n' >&2
        fi
    fi

    if (( use_self_report == 1 )); then
        if [[ -n "${SELF_REPORT_HTTPS_DOMAIN}" ]]; then
            if prompt_yes_no "安装/更新 Self-report HTTPS/Caddy 和后台服务" "y"; then
                install_self_report_https || return 1
            else
                printf 'Self-report HTTPS 手动安装命令：po0-lan-client --install-self-report-https --self-report-https-domain %s\n' "${SELF_REPORT_HTTPS_DOMAIN}"
            fi
        elif prompt_yes_no "安装/更新 systemd Self-report server 服务（HTTP 直连模式）" "n"; then
            install_self_report_service || return 1
        else
            printf 'Self-report 手动启动命令：po0-lan-client --self-report-server --self-report-listen %s\n' "${SELF_REPORT_LISTEN}"
        fi
    fi

    if (( use_webauth == 1 )); then
        if prompt_yes_no "安装/更新 systemd WebAuth server 服务" "n"; then
            install_webauth_service || return 1
        else
            printf 'WebAuth 手动启动命令：po0-lan-client --webauth-server --listen %s\n' "${WEBAUTH_LISTEN}"
        fi
    fi

    print_title "安装摘要"
    printf '  PO0: %s@%s:%s\n' "${PO0_USER}" "${PO0_HOST}" "${PO0_PORT}"
    printf '  SSH 参数: %s\n' "${SSH_EXTRA_ARGS}"
    printf '  DDNS token: %s\n' "$(mask_secret "${DDNS_TOKEN}")"
    printf '  Resource token: %s\n' "$(mask_secret "${RESOURCE_TOKEN}")"
    printf '  Client IP token: %s\n' "$(mask_secret "${CLIENT_IP_TOKEN}")"
    printf '  WebAuth token: %s\n' "$(mask_secret "${WEBAUTH_TOKEN}")"
    (( install_periodic == 1 )) && printf '  本机 Worker 轮询器: 已安装\n'
    printf '完成。\n'
}

probe_ok() {
    printf '%b[OK]%b %s\n' "${C_GREEN}" "${C_RESET}" "$1"
}

probe_warn() {
    printf '%b[WARN]%b %s\n' "${C_YELLOW}" "${C_RESET}" "$1" >&2
}

probe_fail() {
    printf '%b[FAIL]%b %s\n' "${C_RED}" "${C_RESET}" "$1" >&2
}

probe_client_dependencies() {
    local failed=0
    have_cmd ssh || { probe_fail "缺少 ssh，无法连接 PO0。"; failed=1; }
    if [[ -n "${RESOURCE_TOKEN}" ]]; then
        have_cmd tar || { probe_fail "缺少 tar，无法构建/解包 iplist 资源。"; failed=1; }
        have_cmd grep || { probe_fail "缺少 grep，无法解析 iplist 清单。"; failed=1; }
        have_cmd sort || { probe_fail "缺少 sort，无法整理 iplist 清单。"; failed=1; }
        have_cmd wc || { probe_fail "缺少 wc，无法计算资源文件大小。"; failed=1; }
        if ! have_cmd sha256sum && ! have_cmd shasum; then
            probe_fail "缺少 sha256sum 或 shasum，无法计算资源文件 SHA-256。"
            failed=1
        fi
        if ! have_cmd curl && ! have_cmd wget; then
            probe_fail "缺少 curl 或 wget，无法下载资源文件。"
            failed=1
        fi
        if ! have_cmd xargs; then
            probe_warn "缺少 xargs，iplist txt 下载会退回逐个下载。"
        elif ! xargs_supports_parallel; then
            probe_warn "当前 xargs 不支持并发参数，iplist txt 下载会退回逐个下载。"
        fi
    fi
    if [[ -n "${DDNS_RESOLVE_DOMAIN}" || "${REPORT_MODE}" == "ddns" ]]; then
        if ! have_cmd getent && ! have_cmd dig && ! have_cmd host && ! have_cmd nslookup; then
            probe_fail "缺少 getent/dig/host/nslookup，无法解析 DDNS 域名。"
            failed=1
        fi
    fi
    [[ "${failed}" == "0" ]] && probe_ok "本机依赖检查通过"
    return "${failed}"
}

probe_worker_target() {
    local failed=0 ip_csv response key mode resolve_domain
    key="${REPORT_KEY:-${DDNS_DOMAIN}}"
    mode="$(normalize_report_mode "${REPORT_MODE}")"
    [[ "${mode}" == "auto" && -n "${DDNS_RESOLVE_DOMAIN}" ]] && mode="ddns"
    [[ "${mode}" == "auto" ]] && mode="none"
    resolve_domain="${DDNS_RESOLVE_DOMAIN}"
    [[ -n "${PO0_HOST}" ]] || { probe_fail "缺少 --po0-host。"; return 1; }
    [[ -n "${PO0_PORT}" ]] || PO0_PORT="22"
    [[ -n "${PO0_USER}" ]] || PO0_USER="root"
    [[ -n "${PO0_SCRIPT}" ]] || PO0_SCRIPT="${DEFAULT_PO0_SCRIPT}"
    probe_client_dependencies || failed=1

    if [[ "${mode}" == "ddns" && -n "${resolve_domain}" ]]; then
        if ip_csv="$(resolve_ddns_ipv4_csv "${resolve_domain}")"; then
            probe_ok "DDNS 解析结果：${resolve_domain} -> ${ip_csv}；将作为 ${key} 上报"
        else
            probe_fail "无法解析 DDNS 域名的公网 A 记录：${resolve_domain}"
            failed=1
        fi
    else
        probe_warn "未配置 DDNS resolver，将只检测 PO0 连接和资源任务。"
    fi

    if response="$(remote_manager_call "${PO0_HOST}" "${PO0_PORT}" "${PO0_USER}" "${PO0_SCRIPT}" "${SSH_EXTRA_ARGS}" --help 2>&1)"; then
        probe_ok "SSH 可达，PO0 管理脚本可调用：${PO0_USER}@${PO0_HOST}:${PO0_PORT}"
    else
        probe_fail "SSH 或 PO0 管理脚本检查失败：${response}"
        failed=1
    fi

    if [[ "${mode}" == "ddns" && -n "${DDNS_DOMAIN}" ]]; then
        if response="$(remote_manager_call "${PO0_HOST}" "${PO0_PORT}" "${PO0_USER}" "${PO0_SCRIPT}" "${SSH_EXTRA_ARGS}" --ddns-report-check "${key}" "${DDNS_TOKEN}" 2>&1)"; then
            probe_ok "DDNS 上报权限检查通过：${response}"
        else
            probe_fail "DDNS 上报权限检查失败：${response}"
            failed=1
        fi
    fi

    if [[ -n "${RESOURCE_TOKEN}" ]]; then
        if response="$(remote_manager_call "${PO0_HOST}" "${PO0_PORT}" "${PO0_USER}" "${PO0_SCRIPT}" "${SSH_EXTRA_ARGS}" --resource-task-ping "${RESOURCE_TOKEN}" 2>&1)"; then
            probe_ok "资源任务权限检查通过：${response}"
        else
            probe_fail "资源任务权限检查失败：${response}"
            failed=1
        fi
    else
        probe_warn "未配置资源任务 Token。"
    fi

    [[ "${failed}" == "0" ]]
}

run_config_targets() {
    local line ok=0 fail=0 skipped=0 no_ddns=0
    if [[ -n "${DDNS_TARGETS}" ]]; then
        run_ddns_target_lines "${DDNS_TARGETS}"
        return $?
    fi
    ensure_config_file || return 1
    prune_stats_to_current_targets || true
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        if [[ "${TARGET_ENABLED}" != "1" ]]; then
            ((skipped++))
            continue
        fi
        if [[ "${TARGET_REPORT_MODE}" != "ddns" || -z "${TARGET_DOMAIN}" || -z "${TARGET_DDNS_RESOLVE_DOMAIN}" ]]; then
            ((no_ddns++))
            continue
        fi
        if report_once "${TARGET_DOMAIN}" "${TARGET_REPORT_KEY:-${TARGET_DOMAIN}}" "${TARGET_DDNS_RESOLVE_DOMAIN}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT}" "${TARGET_PO0_USER}" "${TARGET_PO0_SCRIPT}" "${TARGET_TOKEN}" "${TARGET_SSH_EXTRA_ARGS}"; then
            ((ok++))
        else
            ((fail++))
        fi
    done < "${CONFIG_FILE}"
    printf 'DDNS resolver 上报完成：成功 %s，失败 %s，停用跳过 %s，无 DDNS 任务跳过 %s。\n' "${ok}" "${fail}" "${skipped}" "${no_ddns}"
    [[ "${fail}" == "0" ]]
}

resource_endpoint_id_for() {
    printf '%s,%s,%s\n' \
        "$(sanitize_field "$1")" \
        "$(sanitize_field "${2:-22}")" \
        "$(sanitize_field "${3:-root}")"
}

resource_endpoint_label() {
    local endpoint_id="$1"
    local host port user line label=""
    IFS=',' read -r host port user <<< "${endpoint_id}"
    host="${host:-}"
    port="${port:-22}"
    user="${user:-root}"
    if [[ -f "${CONFIG_FILE}" ]]; then
        while IFS= read -r line || [[ -n "${line}" ]]; do
            parse_target_line "${line}" || continue
            [[ -n "${TARGET_RESOURCE_TOKEN}" ]] || continue
            if [[ "${TARGET_PO0_HOST}" == "${host}" && "${TARGET_PO0_PORT:-22}" == "${port}" && "${TARGET_PO0_USER:-root}" == "${user}" ]]; then
                label="${TARGET_LABEL:-${TARGET_PO0_HOST}}"
                break
            fi
        done < "${CONFIG_FILE}"
    fi
    if [[ -n "${label}" ]]; then
        printf '%s (%s@%s:%s)\n' "${label}" "${user}" "${host}" "${port}"
    elif [[ -n "${host}" ]]; then
        printf '%s@%s:%s\n' "${user}" "${host}" "${port}"
    else
        printf '%s\n' "${endpoint_id}"
    fi
}

resource_success_rate() {
    local success="${1:-0}" fail="${2:-0}" total
    [[ "${success}" =~ ^[0-9]+$ ]] || success=0
    [[ "${fail}" =~ ^[0-9]+$ ]] || fail=0
    total=$((success + fail))
    if (( total == 0 )); then
        printf 'n/a'
    else
        printf '%s%%' "$(((success * 100) / total))"
    fi
}

short_text() {
    local value="$1"
    local max="${2:-180}"
    if [[ "${#value}" -gt "${max}" ]]; then
        printf '%s...\n' "${value:0:max}"
    else
        printf '%s\n' "${value}"
    fi
}

append_resource_event_unlocked() {
    local at="$1" endpoint_id="$2" task_id="$3" task_type="$4" status="$5" message="$6"
    ensure_resource_events_file || return 1
    printf '%s|%s|%s|%s|%s|%s\n' \
        "${at}" \
        "$(sanitize_field "${endpoint_id}")" \
        "$(sanitize_field "${task_id:-无}")" \
        "$(sanitize_field "${task_type:-无}")" \
        "$(sanitize_field "${status}")" \
        "$(sanitize_field "${message}")" >> "${RESOURCE_EVENTS_FILE}"
}

append_resource_event() {
    with_lan_state_lock append_resource_event_unlocked "$@"
}

update_resource_stats_unlocked() {
    local endpoint_id="$1" task_id="$2" task_type="$3" status="$4" message="$5"
    local tmp line id success fail last_task last_type last_status last_at last_message found=0 now
    ensure_resource_stats_file || return 1
    now="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf 'unknown')"
    tmp="${RESOURCE_STATS_FILE}.tmp.$$"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ -z "$(trim "${line}")" || "$(trim "${line}")" == \#* ]]; then
            printf '%s\n' "${line}" >> "${tmp}"
            continue
        fi
        IFS='|' read -r id success fail last_task last_type last_status last_at last_message <<< "${line}"
        if [[ "${id}" == "${endpoint_id}" ]]; then
            found=1
            [[ "${success}" =~ ^[0-9]+$ ]] || success=0
            [[ "${fail}" =~ ^[0-9]+$ ]] || fail=0
            case "${status}" in
                成功) ((success++)) ;;
                无任务) ;;
                *) ((fail++)) ;;
            esac
            printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
                "${endpoint_id}" "${success}" "${fail}" "${task_id:-无}" "${task_type:-无}" "${status}" "${now}" "$(sanitize_field "${message}")" >> "${tmp}"
            continue
        fi
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${RESOURCE_STATS_FILE}"
    if [[ "${found}" == "0" ]]; then
        success=0
        fail=0
        case "${status}" in
            成功) success=1 ;;
            无任务) ;;
            *) fail=1 ;;
        esac
        printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
            "${endpoint_id}" "${success}" "${fail}" "${task_id:-无}" "${task_type:-无}" "${status}" "${now}" "$(sanitize_field "${message}")" >> "${tmp}"
    fi
    replace_file_from_tmp "${tmp}" "${RESOURCE_STATS_FILE}" || return 1
    append_resource_event "${now}" "${endpoint_id}" "${task_id:-无}" "${task_type:-无}" "${status}" "${message}" || true
}

update_resource_stats() {
    with_lan_state_lock update_resource_stats_unlocked "$@"
}

list_resource_stats() {
    local line endpoint success fail task type status at message count=0 label total rate summary
    ensure_resource_stats_file || return 1
    ensure_resource_events_file || true
    print_panel_section "资源任务汇总"
    print_panel_row "聚合统计" "${RESOURCE_STATS_FILE}"
    print_panel_row "事件日志" "${RESOURCE_EVENTS_FILE}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -n "$(trim "${line}")" && "$(trim "${line}")" != \#* ]] || continue
        IFS='|' read -r endpoint success fail task type status at message <<< "${line}"
        ((count++))
        [[ "${success}" =~ ^[0-9]+$ ]] || success=0
        [[ "${fail}" =~ ^[0-9]+$ ]] || fail=0
        total=$((success + fail))
        rate="$(resource_success_rate "${success}" "${fail}")"
        label="$(resource_endpoint_label "${endpoint}")"
        summary="状态=${status:-未知} 最近=${at:-未知} 成功=${success} 失败=${fail} 成功率=${rate}"
        [[ "${total}" == "0" ]] && summary+="（尚无成功/失败任务）"
        print_panel_row "${label}" "${summary}"
        print_panel_note "任务=${task:-无}/${type:-无}；$(short_text "${message:-无消息}" 160)"
    done < "${RESOURCE_STATS_FILE}"
    [[ "${count}" -gt 0 ]] || print_panel_row "记录" "尚无资源任务记录"
    list_recent_resource_events 12
}

list_recent_resource_events() {
    local limit="${1:-12}" line total start i
    local at endpoint task type status message label detail
    local -a events=()
    ensure_resource_events_file || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -n "$(trim "${line}")" && "$(trim "${line}")" != \#* ]] || continue
        events+=("${line}")
    done < "${RESOURCE_EVENTS_FILE}"
    print_panel_section "最近资源任务事件"
    total="${#events[@]}"
    if (( total == 0 )); then
        print_panel_row "记录" "尚无事件日志"
        return 0
    fi
    [[ "${limit}" =~ ^[0-9]+$ && "${limit}" -gt 0 ]] || limit=12
    if (( total > limit )); then
        start=$((total - limit))
    else
        start=0
    fi
    for ((i = start; i < total; i++)); do
        IFS='|' read -r at endpoint task type status message <<< "${events[$i]}"
        label="$(resource_endpoint_label "${endpoint}")"
        detail="${label}；状态=${status:-未知}；任务=${task:-无}/${type:-无}"
        print_panel_row "${at:-未知}" "${detail}"
        [[ -n "${message}" ]] && print_panel_note "$(short_text "${message}" 180)"
    done
}

resource_events_keep_count() {
    local keep="${1:-${RESOURCE_EVENTS_KEEP}}"
    [[ "${keep}" =~ ^[0-9]+$ ]] || keep=500
    printf '%s\n' "${keep}"
}

prune_resource_events_unlocked() {
    local keep="${1:-${RESOURCE_EVENTS_KEEP}}" line total start i tmp
    local -a events=()
    keep="$(resource_events_keep_count "${keep}")"
    ensure_resource_events_file || return 1
    (( keep > 0 )) || return 0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -n "$(trim "${line}")" && "$(trim "${line}")" != \#* ]] || continue
        events+=("${line}")
    done < "${RESOURCE_EVENTS_FILE}"
    total="${#events[@]}"
    (( total > keep )) || return 0
    start=$((total - keep))
    tmp="${RESOURCE_EVENTS_FILE}.tmp.$$"
    printf '# at|endpoint_id|task_id|task_type|status|message\n' > "${tmp}" || return 1
    for ((i = start; i < total; i++)); do
        printf '%s\n' "${events[$i]}" >> "${tmp}"
    done
    replace_file_from_tmp "${tmp}" "${RESOURCE_EVENTS_FILE}"
}

prune_resource_events() {
    with_lan_state_lock prune_resource_events_unlocked "$@"
}

clear_resource_stats_interactive() {
    local choice keep tmp_stats tmp_events
    ensure_resource_stats_file || return 1
    ensure_resource_events_file || return 1
    print_panel_section "清理资源任务统计"
    print_panel_row "聚合统计" "${RESOURCE_STATS_FILE}"
    print_panel_row "事件日志" "${RESOURCE_EVENTS_FILE}"
    print_panel_row "自动裁剪" "每次资源轮询后保留最近 ${RESOURCE_EVENTS_KEEP} 条事件；设 PO0_RESOURCE_EVENTS_KEEP 可调整"
    printf '%s\n' "  1) 清空资源事件日志"
    printf '%s\n' "  2) 清空聚合统计和事件日志"
    printf '%s\n' "  3) 裁剪事件日志，只保留最近 N 条"
    printf '%s\n' "  0) 取消"
    choice="$(read_prompt "请选择清理方式 [0-3]: ")" || {
        printf '\n输入结束，取消清理。\n'
        return 0
    }
    choice="$(trim "${choice}")"
    case "${choice}" in
        1)
            if prompt_yes_no "确认清空资源事件日志" "n"; then
                tmp_events="${RESOURCE_EVENTS_FILE}.tmp.$$"
                printf '# at|endpoint_id|task_id|task_type|status|message\n' > "${tmp_events}" || return 1
                replace_file_from_tmp "${tmp_events}" "${RESOURCE_EVENTS_FILE}" || return 1
                chmod 600 "${RESOURCE_EVENTS_FILE}" 2>/dev/null || true
                printf '已清空资源事件日志。\n'
            else
                printf '已取消。\n'
            fi
            ;;
        2)
            if prompt_yes_no "确认清空资源聚合统计和事件日志" "n"; then
                tmp_stats="${RESOURCE_STATS_FILE}.tmp.$$"
                tmp_events="${RESOURCE_EVENTS_FILE}.tmp.$$"
                printf '# endpoint_id|success_count|fail_count|last_task|last_type|last_status|last_at|last_message\n' > "${tmp_stats}" || return 1
                printf '# at|endpoint_id|task_id|task_type|status|message\n' > "${tmp_events}" || return 1
                lan_state_lock || return 1
                replace_file_from_tmp "${tmp_stats}" "${RESOURCE_STATS_FILE}" || {
                    lan_state_unlock
                    return 1
                }
                replace_file_from_tmp "${tmp_events}" "${RESOURCE_EVENTS_FILE}" || {
                    lan_state_unlock
                    return 1
                }
                lan_state_unlock
                chmod 600 "${RESOURCE_STATS_FILE}" "${RESOURCE_EVENTS_FILE}" 2>/dev/null || true
                printf '已清空资源聚合统计和事件日志。\n'
            else
                printf '已取消。\n'
            fi
            ;;
        3)
            keep="$(prompt_default "保留最近多少条事件" "${RESOURCE_EVENTS_KEEP}")"
            keep="$(resource_events_keep_count "${keep}")"
            prune_resource_events "${keep}" || return 1
            printf '已裁剪资源事件日志，保留最近 %s 条。\n' "${keep}"
            ;;
        0|"")
            printf '已取消。\n'
            ;;
        *)
            printf '无效选择。\n' >&2
            return 1
            ;;
    esac
}

fetch_to_file() {
    local url="$1" output="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 --connect-timeout 15 --max-time 180 "${url}" -o "${output}"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=180 "${url}" -O "${output}"
    else
        printf '系统缺少 curl 或 wget。\n' >&2
        return 1
    fi
}
