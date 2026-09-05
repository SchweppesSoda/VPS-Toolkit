upsert_target() {
    local enabled="$1"
    local label="$2"
    local domain="$3"
    local report_key="$4"
    local po0_host="$5"
    local po0_port="$6"
    local po0_user="$7"
    local po0_script="$8"
    local token="$9"
    local ssh_extra_args="${10:-}"
    local resource_token="${11:-}"
    local report_mode="${12:-auto}"
    local ddns_resolve_domain="${13:-}"
    local client_ip_token="${14:-}"
    local client_ip_source="${15:-}"
    local client_ip_ttl="${16:-}"
    local webauth_token="${17:-}"
    local webauth_source="${18:-}"
    local webauth_ttl="${19:-}"
    local report_ssh_extra_args="${20:-}"
    local tmp line found=0
    ensure_config_file || return 1
    ssh_extra_args="$(ssh_extra_without_private_key_text "${ssh_extra_args}")"
    report_ssh_extra_args="$(ssh_extra_without_private_key_text "${report_ssh_extra_args}")"
    report_mode="$(normalize_report_mode "${report_mode}")"
    if [[ "${report_mode}" == "auto" ]]; then
        [[ -n "${ddns_resolve_domain:-${domain}}" ]] && report_mode="ddns" || report_mode="none"
    fi
    [[ -n "${ddns_resolve_domain}" ]] || ddns_resolve_domain="${domain}"
    tmp="${CONFIG_FILE}.tmp.$$"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if parse_target_line "${line}"; then
            if [[ "${TARGET_DOMAIN}" == "${domain}" \
                && "${TARGET_REPORT_KEY:-${TARGET_DOMAIN}}" == "${report_key:-${domain}}" \
                && "${TARGET_PO0_HOST}" == "${po0_host}" \
                && "${TARGET_PO0_PORT:-22}" == "${po0_port:-22}" \
                && "${TARGET_PO0_USER:-root}" == "${po0_user:-root}" ]]; then
                found=1
                printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
                    "$(sanitize_field "${enabled}")" \
                    "$(sanitize_field "${label}")" \
                    "$(sanitize_field "${domain}")" \
                    "$(sanitize_field "${report_key:-${domain}}")" \
                    "$(sanitize_field "${po0_host}")" \
                    "$(sanitize_field "${po0_port:-22}")" \
                    "$(sanitize_field "${po0_user:-root}")" \
                    "$(sanitize_field "${po0_script:-${DEFAULT_PO0_SCRIPT}}")" \
                    "$(sanitize_field "${token}")" \
                    "$(sanitize_field "${ssh_extra_args}")" \
                    "$(sanitize_field "${resource_token}")" \
                    "$(sanitize_field "${report_mode}")" \
                    "$(sanitize_field "${ddns_resolve_domain}")" \
                    "$(sanitize_field "${client_ip_token}")" \
                    "$(sanitize_field "${client_ip_source}")" \
                    "$(sanitize_field "${client_ip_ttl}")" \
                    "$(sanitize_field "${webauth_token}")" \
                    "$(sanitize_field "${webauth_source}")" \
                    "$(sanitize_field "${webauth_ttl}")" \
                    "$(sanitize_field "${report_ssh_extra_args}")" >> "${tmp}"
                continue
            fi
        fi
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${CONFIG_FILE}"
    if [[ "${found}" != "1" ]]; then
        printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
            "$(sanitize_field "${enabled}")" \
            "$(sanitize_field "${label}")" \
            "$(sanitize_field "${domain}")" \
            "$(sanitize_field "${report_key:-${domain}}")" \
            "$(sanitize_field "${po0_host}")" \
            "$(sanitize_field "${po0_port:-22}")" \
            "$(sanitize_field "${po0_user:-root}")" \
            "$(sanitize_field "${po0_script:-${DEFAULT_PO0_SCRIPT}}")" \
            "$(sanitize_field "${token}")" \
            "$(sanitize_field "${ssh_extra_args}")" \
            "$(sanitize_field "${resource_token}")" \
            "$(sanitize_field "${report_mode}")" \
            "$(sanitize_field "${ddns_resolve_domain}")" \
            "$(sanitize_field "${client_ip_token}")" \
            "$(sanitize_field "${client_ip_source}")" \
            "$(sanitize_field "${client_ip_ttl}")" \
            "$(sanitize_field "${webauth_token}")" \
            "$(sanitize_field "${webauth_source}")" \
            "$(sanitize_field "${webauth_ttl}")" \
            "$(sanitize_field "${report_ssh_extra_args}")" >> "${tmp}"
    fi
    replace_config_from_tmp "${tmp}"
}

append_target() {
    with_lan_state_lock append_target_unlocked "$@"
}

replace_file_from_tmp_unlocked() {
    local tmp="$1"
    local target="$2"
    local line
    if command -v mv >/dev/null 2>&1; then
        mv -f "${tmp}" "${target}"
        return $?
    fi
    : > "${target}" || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        printf '%s\n' "${line}" >> "${target}"
    done < "${tmp}"
    rm -f "${tmp}" 2>/dev/null || true
}

replace_file_from_tmp() {
    with_lan_state_lock replace_file_from_tmp_unlocked "$@"
}

replace_config_from_tmp() {
    replace_file_from_tmp "$1" "${CONFIG_FILE}"
}

target_id_for() {
    local domain="$1"
    local report_key="$2"
    local po0_host="$3"
    local po0_port="$4"
    local po0_user="$5"
    printf '%s,%s,%s,%s,%s\n' \
        "$(sanitize_field "${domain}")" \
        "$(sanitize_field "${report_key:-${domain}}")" \
        "$(sanitize_field "${po0_host}")" \
        "$(sanitize_field "${po0_port:-22}")" \
        "$(sanitize_field "${po0_user:-root}")"
}

load_target_stats() {
    local target_id="$1"
    local line id success fail last_status last_at last_ip_csv last_error
    STAT_SUCCESS="0"
    STAT_FAIL="0"
    STAT_LAST_STATUS=""
    STAT_LAST_AT=""
    STAT_LAST_IP_CSV=""
    STAT_LAST_ERROR=""
    [[ -f "${STATS_FILE}" ]] || return 0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -n "$(trim "${line}")" && ! "$(trim "${line}")" =~ ^# ]] || continue
        IFS='|' read -r id success fail last_status last_at last_ip_csv last_error <<< "${line}"
        if [[ "${id}" == "${target_id}" ]]; then
            STAT_SUCCESS="${success:-0}"
            STAT_FAIL="${fail:-0}"
            STAT_LAST_STATUS="${last_status:-}"
            STAT_LAST_AT="${last_at:-}"
            STAT_LAST_IP_CSV="${last_ip_csv:-}"
            STAT_LAST_ERROR="${last_error:-}"
            return 0
        fi
    done < "${STATS_FILE}"
}

print_target_stats() {
    local target_id="$1"
    ensure_stats_file || return 1
    load_target_stats "${target_id}"
    if [[ -z "${STAT_LAST_STATUS}" ]]; then
        printf '      统计：尚无上报记录\n'
        return 0
    fi
    [[ "${STAT_LAST_IP_CSV}" == "无" ]] && STAT_LAST_IP_CSV=""
    [[ "${STAT_LAST_ERROR}" == "无" ]] && STAT_LAST_ERROR=""
    printf '      统计：成功=%s 失败=%s 上次=%s 状态=%s IP=%s\n' \
        "${STAT_SUCCESS}" "${STAT_FAIL}" "${STAT_LAST_AT:-未知}" "${STAT_LAST_STATUS}" "${STAT_LAST_IP_CSV:-无}"
    if [[ -n "${STAT_LAST_ERROR}" ]]; then
        printf '      错误：%s\n' "${STAT_LAST_ERROR}"
    fi
}

target_kind_summary() {
    local kinds=""
    if [[ "${TARGET_REPORT_MODE}" == "ddns" && -n "${TARGET_DOMAIN}" && -n "${TARGET_DDNS_RESOLVE_DOMAIN}" ]]; then
        kinds="DDNS 上报"
    fi
    if [[ -n "${TARGET_CLIENT_IP_TOKEN}" ]]; then
        [[ -n "${kinds}" ]] && kinds+=", "
        kinds+="设备自上报"
    fi
    if [[ -n "${TARGET_WEBAUTH_TOKEN}" ]]; then
        [[ -n "${kinds}" ]] && kinds+=", "
        kinds+="WebAuth 放行"
    fi
    if [[ -n "${TARGET_RESOURCE_TOKEN}" ]]; then
        [[ -n "${kinds}" ]] && kinds+=", "
        kinds+="资源任务"
    fi
    printf '%s\n' "${kinds:-未配置任务}"
}

dashboard_stat_totals() {
    local line id success fail last_status last_at last_ip_csv last_error
    DASH_SUCCESS_TOTAL=0
    DASH_FAIL_TOTAL=0
    DASH_LAST_STATUS=""
    DASH_LAST_AT=""
    DASH_LAST_IP_CSV=""
    DASH_LAST_ERROR=""
    [[ -f "${STATS_FILE}" ]] || return 0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="$(trim "${line}")"
        [[ -n "${line}" && ! "${line}" =~ ^# ]] || continue
        IFS='|' read -r id success fail last_status last_at last_ip_csv last_error <<< "${line}"
        [[ "${success}" =~ ^[0-9]+$ ]] || success=0
        [[ "${fail}" =~ ^[0-9]+$ ]] || fail=0
        DASH_SUCCESS_TOTAL=$((DASH_SUCCESS_TOTAL + success))
        DASH_FAIL_TOTAL=$((DASH_FAIL_TOTAL + fail))
        if [[ -n "${last_at}" && ( -z "${DASH_LAST_AT}" || "${last_at}" > "${DASH_LAST_AT}" ) ]]; then
            DASH_LAST_STATUS="${last_status}"
            DASH_LAST_AT="${last_at}"
            DASH_LAST_IP_CSV="${last_ip_csv}"
            DASH_LAST_ERROR="${last_error}"
        fi
    done < "${STATS_FILE}"
}

cron_status_summary() {
    local begin end line in_block=0 found=0 cron_line="" count=0
    begin="$(cron_begin_marker)"
    end="$(cron_end_marker)"
    if ! have_cmd crontab; then
        printf 'crontab 不可用'
        return 0
    fi
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" == "${begin}" ]]; then
            in_block=1
            found=1
            continue
        fi
        if [[ "${line}" == "${end}" ]]; then
            in_block=0
            continue
        fi
        if [[ "${in_block}" == "1" ]]; then
            [[ -n "${line}" ]] || continue
            count=$((count + 1))
            if [[ -z "${cron_line}" ]]; then
                cron_line="${line}"
            else
                cron_line="${cron_line} ; ${line}"
            fi
        fi
    done < <(crontab -l 2>/dev/null || true)
    if [[ "${found}" == "1" ]]; then
        printf '已安装 %s 条：%s' "${count}" "${cron_line:-本脚本管理的 Worker 轮询器}"
    else
        printf '未安装'
    fi
}

remote_resource_task_cron_status() {
    local host="$1"
    local port="$2"
    local user="$3"
    local script="$4"
    local extra="$5"
    local response line key value status="unknown" detail="未读取到 PO0 状态"
    local timeout rc
    timeout="$(timeout_seconds "${REMOTE_STATUS_TIMEOUT_SECONDS}" 8)"
    response="$(remote_manager_call_timeout "${timeout}" "${host}" "${port}" "${user}" "${script}" "${extra}" --resource-task-cron-status 2>&1)"
    rc=$?
    if [[ "${rc}" -ne 0 ]]; then
        if [[ "${rc}" == "124" ]]; then
            response="远端查询超时（${timeout} 秒）"
        elif [[ "${response}" == *"action --resource-task-cron-status not allowed for scope worker"* ]]; then
            response="PO0 受限 SSH wrapper 未刷新；请在 PO0 上执行：bash ${script} --refresh-report-key-wrapper"
        fi
        printf '查询失败|%s\n' "$(sanitize_field "${response}")"
        return 1
    fi
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ "${line}" == *=* ]] || continue
        key="${line%%=*}"
        value="${line#*=}"
        case "${key}" in
            STATUS) status="${value}" ;;
            DETAIL) detail="${value}" ;;
        esac
    done <<< "${response}"
    case "${status}" in
        installed) printf '已安装|%s\n' "${detail}" ;;
        missing) printf '未安装|PO0 尚未设置资源任务定时创建\n' ;;
        unavailable) printf '不可用|%s\n' "${detail}" ;;
        *) printf '未知|%s\n' "${detail}" ;;
    esac
}

show_remote_resource_task_cron_status() {
    local line any=0 status detail label
    ensure_config_file || return 1
    print_panel_section "PO0 资源更新计划"
    print_panel_row "读取模式" "只读"
    print_panel_row "说明" "显示 PO0 何时自动生成 iplist/ipdb 更新任务；本机 Worker 只领取并执行"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        [[ "${TARGET_ENABLED}" == "1" && -n "${TARGET_RESOURCE_TOKEN}" ]] || continue
        any=1
        label="${TARGET_LABEL:-${TARGET_PO0_HOST}}"
        if IFS='|' read -r status detail < <(remote_resource_task_cron_status \
            "${TARGET_PO0_HOST}" \
            "${TARGET_PO0_PORT:-22}" \
            "${TARGET_PO0_USER:-root}" \
            "${TARGET_PO0_SCRIPT:-${DEFAULT_PO0_SCRIPT}}" \
            "${TARGET_SSH_EXTRA_ARGS}"); then
            print_panel_row "${label}" "${status} - ${detail}"
        else
            print_panel_row "${label}" "${status:-查询失败} - ${detail:-无法连接 PO0}"
        fi
    done < "${CONFIG_FILE}"
    [[ "${any}" == "1" ]] || print_panel_row "目标" "没有启用的资源任务目标"
}

print_dashboard() {
    local line total=0 enabled=0 ddns=0 resource=0 self_report=0 webauth=0 disabled=0
    ensure_config_file || return 1
    refresh_stats_file
    refresh_resource_stats_file
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        total=$((total + 1))
        if [[ "${TARGET_ENABLED}" == "1" ]]; then
            enabled=$((enabled + 1))
        else
            disabled=$((disabled + 1))
        fi
        [[ "${TARGET_REPORT_MODE}" == "ddns" && -n "${TARGET_DOMAIN}" && -n "${TARGET_DDNS_RESOLVE_DOMAIN}" ]] && ddns=$((ddns + 1))
        [[ -n "${TARGET_RESOURCE_TOKEN}" ]] && resource=$((resource + 1))
        [[ -n "${TARGET_CLIENT_IP_TOKEN}" ]] && self_report=$((self_report + 1))
        [[ -n "${TARGET_WEBAUTH_TOKEN}" ]] && webauth=$((webauth + 1))
    done < "${CONFIG_FILE}"
    dashboard_stat_totals
    print_title "PO0 内网 Worker"
    print_panel_section "基础信息"
    print_panel_row "脚本名称" "${SCRIPT_NAME}"
    print_panel_row "当前脚本" "$(script_source_path)"
    print_panel_row "版本" "${SCRIPT_VERSION}"
    print_panel_row "发布日期" "${SCRIPT_RELEASE_DATE}"
    print_panel_row "配置文件" "${CONFIG_FILE}"
    print_panel_row "统计文件" "${STATS_FILE}"
    print_panel_row "资源统计" "${RESOURCE_STATS_FILE}"
    print_panel_row "资源事件" "${RESOURCE_EVENTS_FILE:-$(path_dirname "${CONFIG_FILE}")/resource-events.tsv}"
    print_panel_row "Worker ID" "${WORKER_ID}"

    print_panel_section "目标概览"
    print_panel_row "目标数量" "总计 ${total}，启用 ${enabled}，停用 ${disabled}"
    print_panel_row "资源任务" "${resource} 个目标（PO0 创建计划，本机只轮询领取）"
    print_panel_row "DDNS 上报" "${ddns} 个目标"
    print_panel_row "自上报" "${self_report} 个目标，监听 ${SELF_REPORT_LISTEN}"
    print_panel_row "WebAuth" "${webauth} 个目标，监听 ${WEBAUTH_LISTEN}"
    print_panel_row "本机轮询器" "$(cron_status_summary)"

    print_panel_section "本机官方防火墙"
    print_panel_row "配置" "$(official_tokens_summary)"
    print_panel_row "最近状态" "$(official_state_summary)"
    print_panel_row "出口范围" "只上报本机默认路由，不替下游客户端上报"

    print_panel_section "最近 DDNS 统计"
    print_panel_row "汇总" "成功=${DASH_SUCCESS_TOTAL} 失败=${DASH_FAIL_TOTAL} 最近=${DASH_LAST_AT:-无} 状态=${DASH_LAST_STATUS:-无} IP=${DASH_LAST_IP_CSV:-无}"
    [[ -n "${DASH_LAST_ERROR}" && "${DASH_LAST_ERROR}" != "无" ]] && print_panel_row "最近错误" "${DASH_LAST_ERROR}"

    print_panel_section "链路提示"
    print_panel_action "WebAuth" "Cloudflare Access/Tunnel -> LAN Worker -> SSH -> PO0"
}

update_target_stats_unlocked() {
    local target_id="$1"
    local status="$2"
    local ip_csv="$3"
    local error="$4"
    local tmp line id success fail last_status last_at last_ip_csv last_error found=0 now stored_ip stored_error
    ensure_stats_file || return 1
    now="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf 'unknown')"
    stored_ip="$(sanitize_field "${ip_csv}")"
    stored_error="$(sanitize_field "${error}")"
    [[ -n "${stored_ip}" ]] || stored_ip="无"
    [[ -n "${stored_error}" ]] || stored_error="无"
    tmp="${STATS_FILE}.tmp.$$"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ -z "$(trim "${line}")" || "$(trim "${line}")" =~ ^# ]]; then
            printf '%s\n' "${line}" >> "${tmp}"
            continue
        fi
        IFS='|' read -r id success fail last_status last_at last_ip_csv last_error <<< "${line}"
        if [[ "${id}" == "${target_id}" ]]; then
            found=1
            [[ "${success}" =~ ^[0-9]+$ ]] || success=0
            [[ "${fail}" =~ ^[0-9]+$ ]] || fail=0
            if [[ "${status}" == "成功" ]]; then
                ((success++))
            else
                ((fail++))
            fi
            printf '%s|%s|%s|%s|%s|%s|%s\n' \
                "${target_id}" "${success}" "${fail}" "${status}" "${now}" "${stored_ip}" "${stored_error}" >> "${tmp}"
            continue
        fi
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${STATS_FILE}"
    if [[ "${found}" != "1" ]]; then
        success=0
        fail=0
        if [[ "${status}" == "成功" ]]; then
            success=1
        else
            fail=1
        fi
        printf '%s|%s|%s|%s|%s|%s|%s\n' \
            "${target_id}" "${success}" "${fail}" "${status}" "${now}" "${stored_ip}" "${stored_error}" >> "${tmp}"
    fi
    replace_file_from_tmp "${tmp}" "${STATS_FILE}"
}

update_target_stats() {
    with_lan_state_lock update_target_stats_unlocked "$@"
}

add_target_interactive() {
    local label domain report_key po0_host po0_port po0_user po0_script token ssh_extra_args resource_token report_mode ddns_resolve_domain
    ensure_config_file || return 1
    printf '\n添加 PO0 Worker 目标\n'
    report_mode="$(prompt_default "上报模式：ddns 或 none" "${REPORT_MODE:-ddns}")"
    report_mode="$(normalize_report_mode "${report_mode}")"
    [[ "${report_mode}" == "auto" ]] && report_mode="ddns"
    if [[ "${report_mode}" == "ddns" ]]; then
        ddns_resolve_domain="$(prompt_default "LAN Worker 要解析的 DDNS 域名" "${DDNS_RESOLVE_DOMAIN:-${DDNS_DOMAIN}}")"
        domain="$(prompt_default "PO0 来源 key，默认同 DDNS 域名" "${DDNS_DOMAIN:-${ddns_resolve_domain}}")"
    else
        ddns_resolve_domain=""
        domain="$(prompt_default "PO0 来源 key，可空（只做资源任务时留空）" "${DDNS_DOMAIN}")"
    fi
    po0_host="$(prompt_default "PO0 SSH 地址" "${PO0_HOST}")"
    [[ -n "${po0_host}" ]] || { printf 'PO0 SSH 地址不能为空。\n' >&2; return 1; }
    po0_port="$(prompt_default "PO0 SSH 端口" "${PO0_PORT:-22}")"
    po0_user="$(prompt_default "PO0 SSH 用户" "${PO0_USER:-root}")"
    po0_script="$(prompt_default "PO0 管理脚本路径" "${PO0_SCRIPT:-${DEFAULT_PO0_SCRIPT}}")"
    token="$(prompt_default "DDNS 来源上报 token，可空" "${DDNS_TOKEN}")"
    resource_token="$(prompt_default "资源任务 Token，可空" "${RESOURCE_TOKEN}")"
    [[ -n "${domain}" || -n "${resource_token}" ]] || {
        printf 'PO0 来源 key 和资源任务 Token 不能同时为空。\n' >&2
        return 1
    }
    [[ "${report_mode}" != "ddns" || -n "${ddns_resolve_domain}" ]] || {
        printf 'DDNS resolver 模式必须填写 --ddns-domain。\n' >&2
        return 1
    }
    label="$(prompt_default "显示名" "${domain:-resource-${po0_host}}")"
    if [[ -n "${domain}" ]]; then
        report_key="$(prompt_default "PO0 匹配 key，默认直接用来源 key" "${domain}")"
    else
        report_key=""
    fi
    ssh_extra_args="$(prompt_ssh_extra_args "额外 SSH 参数，可空（不是私钥短语；例如 -J jump-host 或 -o StrictHostKeyChecking=accept-new）" "${SSH_EXTRA_ARGS}" "${po0_host}" "${po0_port}" "${po0_user}")" || return 1
    append_target "1" "${label}" "${domain}" "${report_key}" "${po0_host}" "${po0_port}" "${po0_user}" "${po0_script}" "${token}" "${ssh_extra_args}" "${resource_token}" "${report_mode}" "${ddns_resolve_domain}" || return 1
    printf '已添加：%s -> %s\n' "${domain:-资源-only}" "${po0_host}"
}

rewrite_targets_by_index_unlocked() {
    local selected="$1"
    local mode="$2"
    local line idx=0 tmp
    ensure_config_file || return 1
    tmp="${CONFIG_FILE}.tmp.$$"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if ! parse_target_line "${line}"; then
            printf '%s\n' "${line}" >> "${tmp}"
            continue
        fi
        idx=$((idx + 1))
        if [[ "${idx}" == "${selected}" ]]; then
            if [[ "${mode}" == "delete" ]]; then
                continue
            fi
            [[ "${TARGET_ENABLED}" == "1" ]] && TARGET_ENABLED="0" || TARGET_ENABLED="1"
            printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
                "${TARGET_ENABLED}" "${TARGET_LABEL}" "${TARGET_DOMAIN}" "${TARGET_REPORT_KEY}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT}" "${TARGET_PO0_USER}" "${TARGET_PO0_SCRIPT}" "${TARGET_TOKEN}" "${TARGET_SSH_EXTRA_ARGS}" "${TARGET_RESOURCE_TOKEN}" "${TARGET_REPORT_MODE}" "${TARGET_DDNS_RESOLVE_DOMAIN}" "${TARGET_CLIENT_IP_TOKEN}" "${TARGET_CLIENT_IP_SOURCE}" "${TARGET_CLIENT_IP_TTL}" "${TARGET_WEBAUTH_TOKEN}" "${TARGET_WEBAUTH_SOURCE}" "${TARGET_WEBAUTH_TTL}" "${TARGET_REPORT_SSH_EXTRA_ARGS}" >> "${tmp}"
            continue
        fi
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${CONFIG_FILE}"
    replace_config_from_tmp "${tmp}"
}

rewrite_targets_by_index() {
    with_lan_state_lock rewrite_targets_by_index_unlocked "$@"
}

SELECTED_TARGET_INDEX=""

select_target_index() {
    local count choice
    count="$(target_line_count)"
    [[ "${count}" != "0" ]] || {
        printf '当前没有上报目标。\n' >&2
        return 1
    }
    list_targets
    if ! choice="$(read_prompt "请选择目标 [1-${count}]: ")"; then
        printf '\n输入结束，取消选择。\n'
        return 1
    fi
    choice="$(trim "${choice}")"
    [[ "${choice}" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= count )) || return 1
    SELECTED_TARGET_INDEX="${choice}"
}

delete_target_interactive() {
    local idx
    select_target_index || return 1
    idx="${SELECTED_TARGET_INDEX}"
    rewrite_targets_by_index "${idx}" "delete" || return 1
    prune_stats_to_current_targets || true
    printf '已删除目标 %s。\n' "${idx}"
}

toggle_target_interactive() {
    local idx
    select_target_index || return 1
    idx="${SELECTED_TARGET_INDEX}"
    rewrite_targets_by_index "${idx}" "toggle" || return 1
    printf '已切换目标 %s 的启用状态。\n' "${idx}"
}
