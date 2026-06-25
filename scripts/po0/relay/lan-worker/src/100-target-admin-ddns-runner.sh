edit_target_interactive() {
    local selected line idx=0 tmp local_status
    local enabled label domain report_key po0_host po0_port po0_user po0_script token ssh_extra_args resource_token report_mode ddns_resolve_domain
    local client_ip_token client_ip_source client_ip_ttl webauth_token webauth_source webauth_ttl report_ssh_extra_args
    select_target_index || return 1
    selected="${SELECTED_TARGET_INDEX}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        ((idx++))
        if [[ "${idx}" == "${selected}" ]]; then
            enabled="${TARGET_ENABLED}"
            label="${TARGET_LABEL}"
            domain="${TARGET_DOMAIN}"
            report_key="${TARGET_REPORT_KEY}"
            po0_host="${TARGET_PO0_HOST}"
            po0_port="${TARGET_PO0_PORT}"
            po0_user="${TARGET_PO0_USER}"
            po0_script="${TARGET_PO0_SCRIPT}"
            token="${TARGET_TOKEN}"
            ssh_extra_args="${TARGET_SSH_EXTRA_ARGS}"
            resource_token="${TARGET_RESOURCE_TOKEN}"
            report_mode="${TARGET_REPORT_MODE}"
            ddns_resolve_domain="${TARGET_DDNS_RESOLVE_DOMAIN}"
            client_ip_token="${TARGET_CLIENT_IP_TOKEN}"
            client_ip_source="${TARGET_CLIENT_IP_SOURCE}"
            client_ip_ttl="${TARGET_CLIENT_IP_TTL}"
            webauth_token="${TARGET_WEBAUTH_TOKEN}"
            webauth_source="${TARGET_WEBAUTH_SOURCE}"
            webauth_ttl="${TARGET_WEBAUTH_TTL}"
            report_ssh_extra_args="${TARGET_REPORT_SSH_EXTRA_ARGS}"
            break
        fi
    done < "${CONFIG_FILE}"
    [[ -n "${po0_host:-}" ]] || return 1

    printf '\n编辑目标；直接回车保留当前值。\n'
    label="$(prompt_default "显示名" "${label}")"
    report_mode="$(prompt_default "上报模式：ddns 或 none" "${report_mode:-ddns}")"
    report_mode="$(normalize_report_mode "${report_mode}")"
    [[ "${report_mode}" == "auto" ]] && report_mode="ddns"
    if [[ "${report_mode}" == "ddns" ]]; then
        ddns_resolve_domain="$(prompt_default "LAN Worker 要解析的 DDNS 域名" "${ddns_resolve_domain:-${domain}}")"
        domain="$(prompt_default "PO0 来源 key，默认同 DDNS 域名" "${domain:-${ddns_resolve_domain}}")"
    else
        ddns_resolve_domain=""
        domain="$(prompt_default "PO0 来源 key，可空（只做资源任务时留空）" "${domain}")"
    fi
    report_key="$(prompt_default "PO0 匹配 key" "${report_key:-${domain}}")"
    po0_host="$(prompt_default "PO0 SSH 地址" "${po0_host}")"
    po0_port="$(prompt_default "PO0 SSH 端口" "${po0_port:-22}")"
    po0_user="$(prompt_default "PO0 SSH 用户" "${po0_user:-root}")"
    po0_script="$(prompt_default "PO0 管理脚本路径" "${po0_script:-${DEFAULT_PO0_SCRIPT}}")"
    token="$(prompt_default "DDNS 来源上报 Token，可空" "${token}")"
    resource_token="$(prompt_default "资源任务 Token，可空" "${resource_token}")"
    ssh_extra_args="$(prompt_ssh_extra_args "额外 SSH 参数，可空（不是私钥短语；例如 -J jump-host 或 -o StrictHostKeyChecking=accept-new）" "${ssh_extra_args}" "${po0_host}" "${po0_port}" "${po0_user}")" || return 1
    [[ -n "${domain}" ]] || report_key=""
    [[ -n "${po0_host}" && ( -n "${domain}" || -n "${resource_token}" ) ]] || {
        printf 'PO0 SSH 地址不能为空；PO0 来源 key 和资源任务 Token 不能同时为空。\n' >&2
        return 1
    }
    [[ "${report_mode}" != "ddns" || -n "${ddns_resolve_domain}" ]] || {
        printf 'DDNS resolver 模式必须填写 DDNS 域名。\n' >&2
        return 1
    }
    ssh_extra_args="$(ssh_extra_without_private_key_text "${ssh_extra_args}")"
    report_ssh_extra_args="$(ssh_extra_without_private_key_text "${report_ssh_extra_args}")"

    lan_state_lock || return 1
    tmp="${CONFIG_FILE}.tmp.$$"
    idx=0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if ! parse_target_line "${line}"; then
            printf '%s\n' "${line}" >> "${tmp}"
            continue
        fi
        ((idx++))
        if [[ "${idx}" == "${selected}" ]]; then
            printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
                "${enabled}" "$(sanitize_field "${label}")" "$(sanitize_field "${domain}")" "$(sanitize_field "${report_key}")" \
                "$(sanitize_field "${po0_host}")" "$(sanitize_field "${po0_port}")" "$(sanitize_field "${po0_user}")" \
                "$(sanitize_field "${po0_script}")" "$(sanitize_field "${token}")" "$(sanitize_field "${ssh_extra_args}")" \
                "$(sanitize_field "${resource_token}")" "$(sanitize_field "${report_mode}")" "$(sanitize_field "${ddns_resolve_domain}")" \
                "$(sanitize_field "${client_ip_token}")" "$(sanitize_field "${client_ip_source}")" "$(sanitize_field "${client_ip_ttl}")" \
                "$(sanitize_field "${webauth_token}")" "$(sanitize_field "${webauth_source}")" "$(sanitize_field "${webauth_ttl}")" \
                "$(sanitize_field "${report_ssh_extra_args}")" >> "${tmp}"
            continue
        fi
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${CONFIG_FILE}"
    replace_config_from_tmp "${tmp}"
    local_status=$?
    lan_state_unlock
    [[ "${local_status}" == "0" ]] || return "${local_status}"
    prune_stats_to_current_targets || true
    printf '已更新目标 %s。\n' "${selected}"
}

update_target_ssh_args_by_index_unlocked() {
    local selected="$1"
    local new_extra="$2"
    local old_extra="$3"
    local update_report_extra="${4:-0}"
    local line idx=0 tmp
    ensure_config_file || return 1
    tmp="${CONFIG_FILE}.tmp.$$"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if ! parse_target_line "${line}"; then
            printf '%s\n' "${line}" >> "${tmp}"
            continue
        fi
        ((idx++))
        if [[ "${idx}" == "${selected}" ]]; then
            TARGET_SSH_EXTRA_ARGS="$(sanitize_field "$(ssh_extra_without_private_key_text "${new_extra}")")"
            if [[ "${update_report_extra}" == "1" || -z "${TARGET_REPORT_SSH_EXTRA_ARGS}" || "${TARGET_REPORT_SSH_EXTRA_ARGS}" == "${old_extra}" ]]; then
                TARGET_REPORT_SSH_EXTRA_ARGS="${TARGET_SSH_EXTRA_ARGS}"
            else
                TARGET_REPORT_SSH_EXTRA_ARGS="$(sanitize_field "$(ssh_extra_without_private_key_text "${TARGET_REPORT_SSH_EXTRA_ARGS}")")"
            fi
        fi
        printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
            "${TARGET_ENABLED}" "${TARGET_LABEL}" "${TARGET_DOMAIN}" "${TARGET_REPORT_KEY}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT}" "${TARGET_PO0_USER}" "${TARGET_PO0_SCRIPT}" "${TARGET_TOKEN}" "${TARGET_SSH_EXTRA_ARGS}" "${TARGET_RESOURCE_TOKEN}" "${TARGET_REPORT_MODE}" "${TARGET_DDNS_RESOLVE_DOMAIN}" "${TARGET_CLIENT_IP_TOKEN}" "${TARGET_CLIENT_IP_SOURCE}" "${TARGET_CLIENT_IP_TTL}" "${TARGET_WEBAUTH_TOKEN}" "${TARGET_WEBAUTH_SOURCE}" "${TARGET_WEBAUTH_TTL}" "${TARGET_REPORT_SSH_EXTRA_ARGS}" >> "${tmp}"
    done < "${CONFIG_FILE}"
    replace_config_from_tmp "${tmp}"
}

update_target_ssh_args_by_index() {
    with_lan_state_lock update_target_ssh_args_by_index_unlocked "$@"
}

manage_target_ssh_interactive() {
    local selected line idx=0 choice key_path new_key_path extra old_extra new_extra current_report_extra update_report_extra=0
    local po0_host po0_port po0_user
    select_target_index || return 1
    selected="${SELECTED_TARGET_INDEX}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        ((idx++))
        if [[ "${idx}" == "${selected}" ]]; then
            po0_host="${TARGET_PO0_HOST}"
            po0_port="${TARGET_PO0_PORT:-22}"
            po0_user="${TARGET_PO0_USER:-root}"
            extra="${TARGET_SSH_EXTRA_ARGS}"
            current_report_extra="${TARGET_REPORT_SSH_EXTRA_ARGS}"
            break
        fi
    done < "${CONFIG_FILE}"
    [[ -n "${po0_host:-}" ]] || return 1
    old_extra="${extra}"
    key_path="$(ssh_extra_identity_path "${extra}" 2>/dev/null || true)"

    while true; do
        menu_clear_screen
        printf '\n目标 SSH 连接配置：%s@%s:%s\n' "${po0_user}" "${po0_host}" "${po0_port}"
        printf '当前私钥路径：%s\n' "${key_path:-未单独指定，使用系统默认 SSH 配置/agent}"
        printf '当前额外 SSH 参数：%s\n' "${extra:-无}"
        if [[ -n "${current_report_extra}" && "${current_report_extra}" != "${extra}" ]]; then
            printf 'Self-report/WebAuth 上报 SSH 参数覆盖：%s\n' "${current_report_extra}"
        fi
        print_menu_item 1 "设置 / 更换私钥路径"
        print_menu_item 2 "粘贴私钥并保存到本机"
        print_menu_item 3 "清除私钥路径（保留其它 SSH 参数）"
        print_menu_item 4 "编辑额外 SSH 参数（不是私钥短语）"
        print_menu_item 0 "返回"
        print_menu_footer
        read_menu_choice_or_return choice "请选择操作 [0-4]: " || return 2
        case "${choice}" in
            1)
                new_key_path="$(prompt_ssh_key_path_or_paste "SSH 私钥路径（路径不要含空格；如要粘贴私钥请选 2）" "${key_path}" "${po0_host}" "${po0_port}" "${po0_user}")"
                new_extra="$(ssh_extra_with_identity "${extra}" "${new_key_path}")"
                break
                ;;
            2)
                new_key_path="$(save_pasted_ssh_key "${po0_host}" "${po0_port}" "${po0_user}")" || return 1
                printf '[OK] 已保存 SSH 私钥：%s\n' "${new_key_path}"
                new_extra="$(ssh_extra_with_identity "${extra}" "${new_key_path}")"
                break
                ;;
            3)
                new_extra="$(ssh_extra_without_identity "${extra}")"
                break
                ;;
            4)
                new_extra="$(prompt_ssh_extra_args "额外 SSH 参数，例如 -J jump-host 或 -o StrictHostKeyChecking=accept-new" "${extra}" "${po0_host}" "${po0_port}" "${po0_user}")" || return 1
                break
                ;;
            0)
                return 2
                ;;
            "")
                ;;
            *)
                printf '无效选择。\n' >&2
                pause_before_return
                ;;
        esac
    done
    if [[ -n "${current_report_extra}" && "${current_report_extra}" != "${old_extra}" ]]; then
        prompt_yes_no "Self-report/WebAuth 上报 SSH 参数有单独覆盖，是否同步更新" "n" && update_report_extra=1
    fi
    update_target_ssh_args_by_index "${selected}" "${new_extra}" "${old_extra}" "${update_report_extra}" || return 1
    printf '已更新目标 %s 的 SSH 连接配置。\n' "${selected}"
}

update_target_tokens_by_index_unlocked() {
    local selected="$1"
    local ddns_token="$2"
    local resource_token="$3"
    local client_ip_token="$4"
    local webauth_token="$5"
    local line idx=0 tmp
    ensure_config_file || return 1
    tmp="${CONFIG_FILE}.tmp.$$"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if ! parse_target_line "${line}"; then
            printf '%s\n' "${line}" >> "${tmp}"
            continue
        fi
        ((idx++))
        if [[ "${idx}" == "${selected}" ]]; then
            TARGET_TOKEN="$(sanitize_field "${ddns_token}")"
            TARGET_RESOURCE_TOKEN="$(sanitize_field "${resource_token}")"
            TARGET_CLIENT_IP_TOKEN="$(sanitize_field "${client_ip_token}")"
            TARGET_WEBAUTH_TOKEN="$(sanitize_field "${webauth_token}")"
        fi
        printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
            "${TARGET_ENABLED}" "${TARGET_LABEL}" "${TARGET_DOMAIN}" "${TARGET_REPORT_KEY}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT}" "${TARGET_PO0_USER}" "${TARGET_PO0_SCRIPT}" "${TARGET_TOKEN}" "${TARGET_SSH_EXTRA_ARGS}" "${TARGET_RESOURCE_TOKEN}" "${TARGET_REPORT_MODE}" "${TARGET_DDNS_RESOLVE_DOMAIN}" "${TARGET_CLIENT_IP_TOKEN}" "${TARGET_CLIENT_IP_SOURCE}" "${TARGET_CLIENT_IP_TTL}" "${TARGET_WEBAUTH_TOKEN}" "${TARGET_WEBAUTH_SOURCE}" "${TARGET_WEBAUTH_TTL}" "${TARGET_REPORT_SSH_EXTRA_ARGS}" >> "${tmp}"
    done < "${CONFIG_FILE}"
    replace_config_from_tmp "${tmp}"
}

update_target_tokens_by_index() {
    with_lan_state_lock update_target_tokens_by_index_unlocked "$@"
}

manage_target_tokens_interactive() {
    local selected line idx=0
    local ddns_token resource_token client_ip_token webauth_token
    select_target_index || return 1
    selected="${SELECTED_TARGET_INDEX}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        ((idx++))
        if [[ "${idx}" == "${selected}" ]]; then
            ddns_token="${TARGET_TOKEN}"
            resource_token="${TARGET_RESOURCE_TOKEN}"
            client_ip_token="${TARGET_CLIENT_IP_TOKEN}"
            webauth_token="${TARGET_WEBAUTH_TOKEN}"
            break
        fi
    done < "${CONFIG_FILE}"
    printf '\n目标 Token 维护；直接回车保留当前值，输入 - 可清空。\n'
    ddns_token="$(prompt_default "DDNS 来源上报 Token" "${ddns_token}")"
    resource_token="$(prompt_default "资源任务 Token" "${resource_token}")"
    client_ip_token="$(prompt_default "Self-report client-ip Token" "${client_ip_token}")"
    webauth_token="$(prompt_default "WebAuth Token" "${webauth_token}")"
    [[ "${ddns_token}" == "-" ]] && ddns_token=""
    [[ "${resource_token}" == "-" ]] && resource_token=""
    [[ "${client_ip_token}" == "-" ]] && client_ip_token=""
    [[ "${webauth_token}" == "-" ]] && webauth_token=""
    update_target_tokens_by_index "${selected}" "${ddns_token}" "${resource_token}" "${client_ip_token}" "${webauth_token}" || return 1
    printf '已更新目标 %s 的 Token。\n' "${selected}"
}

update_target_report_ttl_by_index_unlocked() {
    local selected="$1"
    local client_ip_source="$2"
    local client_ip_ttl="$3"
    local webauth_source="$4"
    local webauth_ttl="$5"
    local line idx=0 tmp
    ensure_config_file || return 1
    tmp="${CONFIG_FILE}.tmp.$$"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if ! parse_target_line "${line}"; then
            printf '%s\n' "${line}" >> "${tmp}"
            continue
        fi
        ((idx++))
        if [[ "${idx}" == "${selected}" ]]; then
            TARGET_CLIENT_IP_SOURCE="$(sanitize_field "${client_ip_source}")"
            TARGET_CLIENT_IP_TTL="$(sanitize_field "${client_ip_ttl}")"
            TARGET_WEBAUTH_SOURCE="$(sanitize_field "${webauth_source}")"
            TARGET_WEBAUTH_TTL="$(sanitize_field "${webauth_ttl}")"
        fi
        printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
            "${TARGET_ENABLED}" "${TARGET_LABEL}" "${TARGET_DOMAIN}" "${TARGET_REPORT_KEY}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT}" "${TARGET_PO0_USER}" "${TARGET_PO0_SCRIPT}" "${TARGET_TOKEN}" "${TARGET_SSH_EXTRA_ARGS}" "${TARGET_RESOURCE_TOKEN}" "${TARGET_REPORT_MODE}" "${TARGET_DDNS_RESOLVE_DOMAIN}" "${TARGET_CLIENT_IP_TOKEN}" "${TARGET_CLIENT_IP_SOURCE}" "${TARGET_CLIENT_IP_TTL}" "${TARGET_WEBAUTH_TOKEN}" "${TARGET_WEBAUTH_SOURCE}" "${TARGET_WEBAUTH_TTL}" "${TARGET_REPORT_SSH_EXTRA_ARGS}" >> "${tmp}"
    done < "${CONFIG_FILE}"
    replace_config_from_tmp "${tmp}"
}

update_target_report_ttl_by_index() {
    with_lan_state_lock update_target_report_ttl_by_index_unlocked "$@"
}

update_target_self_report_ttl_by_index_unlocked() {
    local selected="$1"
    local client_ip_source="$2"
    local client_ip_ttl="$3"
    local line idx=0 tmp
    ensure_config_file || return 1
    tmp="${CONFIG_FILE}.tmp.$$"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if ! parse_target_line "${line}"; then
            printf '%s\n' "${line}" >> "${tmp}"
            continue
        fi
        ((idx++))
        if [[ "${idx}" == "${selected}" ]]; then
            TARGET_CLIENT_IP_SOURCE="$(sanitize_field "${client_ip_source}")"
            TARGET_CLIENT_IP_TTL="$(sanitize_field "${client_ip_ttl}")"
        fi
        printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
            "${TARGET_ENABLED}" "${TARGET_LABEL}" "${TARGET_DOMAIN}" "${TARGET_REPORT_KEY}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT}" "${TARGET_PO0_USER}" "${TARGET_PO0_SCRIPT}" "${TARGET_TOKEN}" "${TARGET_SSH_EXTRA_ARGS}" "${TARGET_RESOURCE_TOKEN}" "${TARGET_REPORT_MODE}" "${TARGET_DDNS_RESOLVE_DOMAIN}" "${TARGET_CLIENT_IP_TOKEN}" "${TARGET_CLIENT_IP_SOURCE}" "${TARGET_CLIENT_IP_TTL}" "${TARGET_WEBAUTH_TOKEN}" "${TARGET_WEBAUTH_SOURCE}" "${TARGET_WEBAUTH_TTL}" "${TARGET_REPORT_SSH_EXTRA_ARGS}" >> "${tmp}"
    done < "${CONFIG_FILE}"
    replace_config_from_tmp "${tmp}"
}

update_target_self_report_ttl_by_index() {
    with_lan_state_lock update_target_self_report_ttl_by_index_unlocked "$@"
}

manage_target_self_report_ttl_interactive() {
    local selected line idx=0
    local client_ip_source client_ip_ttl
    select_target_index || return 1
    selected="${SELECTED_TARGET_INDEX}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        ((idx++))
        if [[ "${idx}" == "${selected}" ]]; then
            client_ip_source="${TARGET_CLIENT_IP_SOURCE}"
            client_ip_ttl="${TARGET_CLIENT_IP_TTL}"
            break
        fi
    done < "${CONFIG_FILE}"
    printf '\nSelf-report source 与 TTL 维护；直接回车保留当前值，输入 - 可清空目标覆盖。\n'
    client_ip_source="$(prompt_default "Self-report source id" "${client_ip_source:-${SELF_REPORT_SOURCE}}")"
    client_ip_ttl="$(prompt_default "Self-report 放行 TTL 秒数" "${client_ip_ttl:-${SELF_REPORT_TTL_SECONDS:-43200}}")"
    [[ "${client_ip_source}" == "-" ]] && client_ip_source=""
    [[ "${client_ip_ttl}" == "-" ]] && client_ip_ttl=""
    if [[ -n "${client_ip_ttl}" && ! "${client_ip_ttl}" =~ ^[0-9]+$ ]]; then
        printf 'Self-report TTL 必须是秒数，或输入 - 清空目标覆盖。\n' >&2
        return 1
    fi
    [[ -n "${client_ip_ttl}" ]] && client_ip_ttl="$(normalize_report_ttl_seconds "${client_ip_ttl}" "${SELF_REPORT_TTL_SECONDS:-43200}")"
    update_target_self_report_ttl_by_index "${selected}" "${client_ip_source}" "${client_ip_ttl}" || return 1
    printf '已更新目标 %s 的 Self-report source 与 TTL。\n' "${selected}"
}

manage_target_report_ttl_interactive() {
    local selected line idx=0
    local client_ip_source client_ip_ttl webauth_source webauth_ttl
    select_target_index || return 1
    selected="${SELECTED_TARGET_INDEX}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        ((idx++))
        if [[ "${idx}" == "${selected}" ]]; then
            client_ip_source="${TARGET_CLIENT_IP_SOURCE}"
            client_ip_ttl="${TARGET_CLIENT_IP_TTL}"
            webauth_source="${TARGET_WEBAUTH_SOURCE}"
            webauth_ttl="${TARGET_WEBAUTH_TTL}"
            break
        fi
    done < "${CONFIG_FILE}"
    printf '\nSelf-report / WebAuth source 与 TTL 维护；直接回车保留当前值，输入 - 可清空目标覆盖。\n'
    client_ip_source="$(prompt_default "Self-report source id" "${client_ip_source:-${SELF_REPORT_SOURCE}}")"
    client_ip_ttl="$(prompt_default "Self-report 放行 TTL 秒数" "${client_ip_ttl:-${SELF_REPORT_TTL_SECONDS:-43200}}")"
    webauth_source="$(prompt_default "WebAuth source id" "${webauth_source:-${WEBAUTH_SOURCE}}")"
    webauth_ttl="$(prompt_default "WebAuth 放行 TTL 秒数" "${webauth_ttl:-${WEBAUTH_TTL_SECONDS:-43200}}")"
    [[ "${client_ip_source}" == "-" ]] && client_ip_source=""
    [[ "${client_ip_ttl}" == "-" ]] && client_ip_ttl=""
    [[ "${webauth_source}" == "-" ]] && webauth_source=""
    [[ "${webauth_ttl}" == "-" ]] && webauth_ttl=""
    if [[ -n "${client_ip_ttl}" && ! "${client_ip_ttl}" =~ ^[0-9]+$ ]]; then
        printf 'Self-report TTL 必须是秒数，或输入 - 清空目标覆盖。\n' >&2
        return 1
    fi
    if [[ -n "${webauth_ttl}" && ! "${webauth_ttl}" =~ ^[0-9]+$ ]]; then
        printf 'WebAuth TTL 必须是秒数，或输入 - 清空目标覆盖。\n' >&2
        return 1
    fi
    [[ -n "${client_ip_ttl}" ]] && client_ip_ttl="$(normalize_report_ttl_seconds "${client_ip_ttl}" "${SELF_REPORT_TTL_SECONDS:-43200}")"
    [[ -n "${webauth_ttl}" ]] && webauth_ttl="$(normalize_report_ttl_seconds "${webauth_ttl}" "${WEBAUTH_TTL_SECONDS:-43200}")"
    update_target_report_ttl_by_index "${selected}" "${client_ip_source}" "${client_ip_ttl}" "${webauth_source}" "${webauth_ttl}" || return 1
    printf '已更新目标 %s 的 Self-report / WebAuth source 与 TTL。\n' "${selected}"
}

report_once() {
    local source_key="$1"
    local report_key="$2"
    local resolve_domain="$3"
    local po0_host="$4"
    local po0_port="$5"
    local po0_user="$6"
    local po0_script="$7"
    local token="$8"
    local ssh_extra_args="${9:-}"
    local ip_csv remote_cmd target_id
    local -a ssh_args=()
    [[ -n "${source_key}" ]] || { printf '缺少 PO0 来源 key。\n' >&2; return 1; }
    [[ -n "${resolve_domain}" ]] || { printf '缺少要解析的 DDNS 域名。\n' >&2; return 1; }
    [[ -n "${po0_host}" ]] || { printf '缺少 PO0 SSH 地址。\n' >&2; return 1; }
    [[ -n "${report_key}" ]] || report_key="${source_key}"
    [[ -n "${po0_port}" ]] || po0_port="22"
    [[ -n "${po0_user}" ]] || po0_user="root"
    [[ -n "${po0_script}" ]] || po0_script="${DEFAULT_PO0_SCRIPT}"
    target_id="$(target_id_for "${source_key}" "${report_key}" "${po0_host}" "${po0_port}" "${po0_user}")"

    ip_csv="$(resolve_ddns_ipv4_csv "${resolve_domain}")" || {
        printf '解析失败：无法解析 DDNS 域名的公网 A 记录：%s\n' "${resolve_domain}" >&2
        update_target_stats "${target_id}" "失败" "" "解析失败：无法解析 DDNS 域名 ${resolve_domain}" || true
        return 1
    }

    remote_cmd="bash $(sh_quote "${po0_script}") --ddns-report $(sh_quote "${report_key}") $(sh_quote "${ip_csv}")"
    if [[ -n "${token}" ]]; then
        remote_cmd+=" $(sh_quote "${token}")"
    fi

    ssh_args+=(-n -p "${po0_port}")
    sanitize_ssh_extra_args "${ssh_extra_args}" "DDNS ${source_key}@${po0_host}:${po0_port}"
    ssh_args+=("${SSH_EXTRA_ARGV[@]}")

    printf '上报：DDNS %s -> %s -> %s@%s:%s，来源=%s\n' "${resolve_domain}" "${ip_csv}" "${po0_user}" "${po0_host}" "${po0_port}" "${report_key}"
    if ! ssh "${ssh_args[@]}" "${po0_user}@${po0_host}" "${remote_cmd}"; then
        printf '上报失败：%s -> %s\n' "${source_key}" "${po0_host}" >&2
        update_target_stats "${target_id}" "失败" "${ip_csv}" "SSH 或 PO0 上报命令失败" || true
        return 1
    fi
    update_target_stats "${target_id}" "成功" "${ip_csv}" "" || true
}

run_ddns_target_lines() {
    local raw="$1" line source_key resolve_domain host port user script token extra ok=0 fail=0 skipped=0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="$(trim "${line}")"
        [[ -n "${line}" && ! "${line}" == \#* ]] || continue
        IFS='|' read -r source_key resolve_domain host port user script token extra <<< "${line}"
        source_key="$(sanitize_field "${source_key}")"
        resolve_domain="$(sanitize_field "${resolve_domain}")"
        host="$(sanitize_field "${host}")"
        port="$(sanitize_field "${port:-22}")"
        user="$(sanitize_field "${user:-root}")"
        script="$(sanitize_field "${script:-${DEFAULT_PO0_SCRIPT}}")"
        token="$(sanitize_field "${token}")"
        extra="$(sanitize_field "${extra:-}")"
        if [[ -z "${source_key}" || -z "${resolve_domain}" || -z "${host}" ]]; then
            printf '跳过无效 DDNS 上报目标：%s\n' "${line}" >&2
            skipped=$((skipped + 1))
            continue
        fi
        if report_once "${source_key}" "${source_key}" "${resolve_domain}" "${host}" "${port:-22}" "${user:-root}" "${script:-${DEFAULT_PO0_SCRIPT}}" "${token}" "${extra}"; then
            ok=$((ok + 1))
        else
            fail=$((fail + 1))
        fi
    done < <(printf '%s\n' "${raw}" | tr ';' '\n')
    printf 'DDNS 临时上报目标执行完成：成功 %s，失败 %s，跳过 %s。\n' "${ok}" "${fail}" "${skipped}"
    [[ "${fail}" == "0" ]]
}

remote_manager_call() {
    local host="$1"
    local port="$2"
    local user="$3"
    local script="$4"
    local extra="$5"
    shift 5
    remote_manager_call_timeout "$(timeout_seconds "${REMOTE_MANAGER_TIMEOUT_SECONDS}" 30)" "${host}" "${port}" "${user}" "${script}" "${extra}" "$@"
}

remote_manager_call_timeout() {
    local seconds="$1"
    local host="$2"
    local port="$3"
    local user="$4"
    local script="$5"
    local extra="$6"
    shift 6
    local remote_cmd arg
    local -a ssh_args=(-n -p "${port:-22}")
    [[ -n "${user}" ]] || user="root"
    [[ -n "${script}" ]] || script="${DEFAULT_PO0_SCRIPT}"
    sanitize_ssh_extra_args "${extra}" "PO0 manager ${user}@${host}:${port:-22}"
    ssh_args+=("${SSH_EXTRA_ARGV[@]}")
    remote_cmd="bash $(sh_quote "${script}")"
    for arg in "$@"; do
        remote_cmd+=" $(sh_quote "${arg}")"
    done
    run_with_optional_timeout "$(timeout_seconds "${seconds}" 8)" ssh "${ssh_args[@]}" "${user}@${host}" "${remote_cmd}"
}

fetch_worker_token_bundle() {
    local ensure_resource="${1:-0}"
    local response line key value
    if [[ "${ensure_resource}" == "1" ]]; then
        response="$(remote_manager_call "${PO0_HOST}" "${PO0_PORT}" "${PO0_USER}" "${PO0_SCRIPT}" "${SSH_EXTRA_ARGS}" --worker-token-bundle --ensure-resource-token)" || return 1
    else
        response="$(remote_manager_call "${PO0_HOST}" "${PO0_PORT}" "${PO0_USER}" "${PO0_SCRIPT}" "${SSH_EXTRA_ARGS}" --worker-token-bundle)" || return 1
    fi
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ "${line}" == *=* ]] || continue
        key="${line%%=*}"
        value="${line#*=}"
        case "${key}" in
            DDNS_TOKEN) DDNS_TOKEN="${value}" ;;
            RESOURCE_TOKEN) RESOURCE_TOKEN="${value}" ;;
            CLIENT_IP_TOKEN) CLIENT_IP_TOKEN="${value}" ;;
            WEBAUTH_TOKEN) WEBAUTH_TOKEN="${value}" ;;
        esac
    done <<< "${response}"
}
