report_resource_failure() {
    local task_id="$1" worker_id="$2" reason="$3" host="$4" port="$5" user="$6" script="$7" token="$8" extra="$9"
    local remote_cmd
    local -a ssh_args=(-n -p "${port}")
    sanitize_ssh_extra_args "${extra}" "resource fail ${user}@${host}:${port}"
    ssh_args+=("${SSH_EXTRA_ARGV[@]}")
    remote_cmd="bash $(sh_quote "${script}") --resource-task-fail $(sh_quote "${task_id}") $(sh_quote "${worker_id}") $(sh_quote "${reason}") $(sh_quote "${token}")"
    run_with_optional_timeout "$(timeout_seconds "${RESOURCE_CONTROL_TIMEOUT_SECONDS}" 120)" ssh "${ssh_args[@]}" "${user}@${host}" "${remote_cmd}" >/dev/null 2>&1 || true
}

timeout_seconds() {
    local value="${1:-}" fallback="${2:-0}"
    [[ "${value}" =~ ^[0-9]+$ ]] || value="${fallback}"
    printf '%s\n' "${value}"
}

run_with_optional_timeout() {
    local seconds="$1"
    shift
    if [[ "${seconds}" -gt 0 ]] && command -v timeout >/dev/null 2>&1; then
        timeout "${seconds}" "$@"
    else
        "$@"
    fi
}

resource_task_max_per_run() {
    local max="${RESOURCE_TASK_MAX_PER_RUN:-10}"
    [[ "${max}" =~ ^[0-9]+$ ]] || max=10
    (( max <= 100 )) || max=100
    printf '%s\n' "${max}"
}

run_resource_endpoint() {
    local host="$1" port="$2" user="$3" script="$4" token="$5" extra="$6"
    local worker_id endpoint_id remote_cmd response protocol task_id task_type upload_path work output sha size upload_response complete_response reason
    local processed=0 failed=0 max_per_run upload_timeout complete_timeout control_timeout upload_rc complete_rc claim_rc
    local -a ssh_args=(-p "${port}")
    local -a control_ssh_args=(-n -p "${port}")
    worker_id="$(sanitize_field "${WORKER_ID}")"
    worker_id="${worker_id// /_}"
    endpoint_id="$(resource_endpoint_id_for "${host}" "${port}" "${user}")"
    sanitize_ssh_extra_args "${extra}" "resource ${user}@${host}:${port}"
    ssh_args+=("${SSH_EXTRA_ARGV[@]}")
    control_ssh_args+=("${SSH_EXTRA_ARGV[@]}")
    max_per_run="$(resource_task_max_per_run)"
    upload_timeout="$(timeout_seconds "${RESOURCE_UPLOAD_TIMEOUT_SECONDS}" 900)"
    complete_timeout="$(timeout_seconds "${RESOURCE_COMPLETE_TIMEOUT_SECONDS}" 600)"
    control_timeout="$(timeout_seconds "${RESOURCE_CONTROL_TIMEOUT_SECONDS}" 120)"
    while true; do
        if [[ "${max_per_run}" -gt 0 && "${processed}" -ge "${max_per_run}" ]]; then
            printf '资源任务：%s 本轮已处理 %s 个，达到上限 %s。\n' "${host}" "${processed}" "${max_per_run}"
            [[ "${failed}" == "0" ]]
            return $?
        fi

        reason=""
        task_id=""
        task_type=""
        upload_path=""
        output=""
        remote_cmd="bash $(sh_quote "${script}") --resource-task-claim $(sh_quote "${worker_id}") $(sh_quote "${token}")"
        response="$(run_with_optional_timeout "${control_timeout}" ssh "${control_ssh_args[@]}" "${user}@${host}" "${remote_cmd}" 2>&1)"
        claim_rc=$?
        if [[ "${claim_rc}" -ne 0 ]]; then
            if [[ "${claim_rc}" == "124" ]]; then
                response="资源任务查询超时（${control_timeout} 秒）"
            fi
            printf '资源任务查询失败：%s@%s:%s\n' "${user}" "${host}" "${port}" >&2
            [[ -n "${response}" ]] && printf '  %s\n' "$(sanitize_field "${response}")" >&2
            update_resource_stats "${endpoint_id}" "" "" "查询失败" "${response}" || true
            return 1
        fi
        protocol="$(printf '%s\n' "${response}" | grep -E '^(TASK|NO_TASK|ERROR)(\||$)' | tail -n 1)"
        case "${protocol}" in
            NO_TASK)
                if [[ "${processed}" -gt 0 ]]; then
                    printf '资源任务：%s 本轮处理 %s 个，失败 %s，已无待处理任务。\n' "${host}" "${processed}" "${failed}"
                else
                    printf '资源任务：%s 暂无任务。\n' "${host}"
                    update_resource_stats "${endpoint_id}" "" "" "无任务" "PO0 当前没有等待任务" || true
                fi
                [[ "${failed}" == "0" ]]
                return $?
                ;;
            ERROR\|*)
                printf '资源任务查询被拒绝：%s\n' "${protocol#ERROR|}" >&2
                update_resource_stats "${endpoint_id}" "" "" "查询失败" "${protocol#ERROR|}" || true
                return 1
                ;;
            TASK\|*)
                IFS='|' read -r _ task_id task_type upload_path <<< "${protocol}"
                ;;
            *)
                printf 'PO0 返回了无法识别的任务响应：%s\n' "${response}" >&2
                update_resource_stats "${endpoint_id}" "" "" "查询失败" "无法识别 PO0 响应" || true
                return 1
                ;;
        esac

        work="$(mktemp -d "${TMPDIR:-/tmp}/po0-resource-task.XXXXXX")" || return 1
        case "${task_type}" in
            iplist)
                output="${work}/iplist.tar.gz"
                printf '执行资源任务 %s：构建 iplist.tar.gz\n' "${task_id}"
                build_iplist_resource "${output}" || reason="构建 iplist.tar.gz 失败"
                ;;
            ipdb)
                output="${work}/qqwry.ipdb"
                printf '执行资源任务 %s：下载 qqwry.ipdb\n' "${task_id}"
                fetch_to_file "${IPDB_DOWNLOAD_URL}" "${output}" || reason="下载 qqwry.ipdb 失败"
                if [[ -z "${reason}" ]]; then
                    size="$(wc -c < "${output}" | tr -d '[:space:]')"
                    [[ "${size}" =~ ^[0-9]+$ && "${size}" -ge 102400 ]] || reason="qqwry.ipdb 文件过小"
                fi
                ;;
            *)
                reason="PO0 下发了不支持的任务类型"
                ;;
        esac
        if [[ -n "${reason}" ]]; then
            report_resource_failure "${task_id}" "${worker_id}" "${reason}" "${host}" "${port}" "${user}" "${script}" "${token}" "${extra}"
            update_resource_stats "${endpoint_id}" "${task_id}" "${task_type}" "失败" "${reason}" || true
            rm -rf -- "${work}"
            ((processed++))
            ((failed++))
            continue
        fi
        printf '资源任务 %s：计算 SHA-256 和文件大小...\n' "${task_id}"
        sha="$(sha256_file "${output}")" || reason="本机缺少 SHA-256 工具"
        size="$(wc -c < "${output}" | tr -d '[:space:]')"
        if [[ -n "${reason}" ]]; then
            report_resource_failure "${task_id}" "${worker_id}" "${reason}" "${host}" "${port}" "${user}" "${script}" "${token}" "${extra}"
            update_resource_stats "${endpoint_id}" "${task_id}" "${task_type}" "失败" "${reason}" || true
            rm -rf -- "${work}"
            ((processed++))
            ((failed++))
            continue
        fi
        remote_cmd="bash $(sh_quote "${script}") --resource-task-upload $(sh_quote "${task_id}") $(sh_quote "${worker_id}") $(sh_quote "${sha}") $(sh_quote "${size}") $(sh_quote "${token}")"
        printf '资源任务 %s：上传到 PO0（%s bytes，超时 %s 秒）...\n' "${task_id}" "${size}" "${upload_timeout}"
        upload_response="$(progress_cat "${output}" "${size}" | run_with_optional_timeout "${upload_timeout}" ssh "${ssh_args[@]}" "${user}@${host}" "${remote_cmd}" 2>&1)"
        upload_rc=$?
        if [[ "${upload_rc}" -ne 0 ]]; then
            if [[ "${upload_rc}" == "124" ]]; then
                reason="PO0 上传资源文件超时（${upload_timeout} 秒）"
            else
                reason="PO0 上传资源文件失败（退出码 ${upload_rc}）：${upload_response}"
            fi
            report_resource_failure "${task_id}" "${worker_id}" "${reason}" "${host}" "${port}" "${user}" "${script}" "${token}" "${extra}"
            update_resource_stats "${endpoint_id}" "${task_id}" "${task_type}" "失败" "${reason}" || true
            rm -rf -- "${work}"
            printf '%s\n' "${reason}" >&2
            ((processed++))
            ((failed++))
            continue
        fi
        if [[ "${upload_response}" != *"OK|"* ]]; then
            reason="PO0 返回了无法识别的上传响应：${upload_response}"
            report_resource_failure "${task_id}" "${worker_id}" "${reason}" "${host}" "${port}" "${user}" "${script}" "${token}" "${extra}"
            update_resource_stats "${endpoint_id}" "${task_id}" "${task_type}" "失败" "${reason}" || true
            rm -rf -- "${work}"
            printf '%s\n' "${reason}" >&2
            ((processed++))
            ((failed++))
            continue
        fi
        printf '资源任务 %s：PO0 已接收，开始校验/导入（超时 %s 秒）...\n' "${task_id}" "${complete_timeout}"
        remote_cmd="bash $(sh_quote "${script}") --resource-task-complete $(sh_quote "${task_id}") $(sh_quote "${worker_id}") $(sh_quote "${sha}") $(sh_quote "${size}") $(sh_quote "${token}")"
        complete_response="$(run_with_optional_timeout "${complete_timeout}" ssh "${control_ssh_args[@]}" "${user}@${host}" "${remote_cmd}" 2>&1)"
        complete_rc=$?
        if [[ "${complete_rc}" -ne 0 ]]; then
            if [[ "${complete_rc}" == "124" ]]; then
                reason="PO0 校验或导入超时（${complete_timeout} 秒）"
            else
                reason="PO0 校验或导入失败（退出码 ${complete_rc}）：${complete_response}"
            fi
            report_resource_failure "${task_id}" "${worker_id}" "${reason}" "${host}" "${port}" "${user}" "${script}" "${token}" "${extra}"
            update_resource_stats "${endpoint_id}" "${task_id}" "${task_type}" "失败" "${reason}" || true
            rm -rf -- "${work}"
            printf '%s\n' "${reason}" >&2
            ((processed++))
            ((failed++))
            continue
        fi
        if [[ "${complete_response}" != *"OK|"* ]]; then
            reason="PO0 返回了无法识别的完成响应：${complete_response}"
            report_resource_failure "${task_id}" "${worker_id}" "${reason}" "${host}" "${port}" "${user}" "${script}" "${token}" "${extra}"
            update_resource_stats "${endpoint_id}" "${task_id}" "${task_type}" "失败" "${reason}" || true
            rm -rf -- "${work}"
            printf '%s\n' "${reason}" >&2
            ((processed++))
            ((failed++))
            continue
        fi
        update_resource_stats "${endpoint_id}" "${task_id}" "${task_type}" "成功" "${complete_response##*OK|}" || true
        rm -rf -- "${work}"
        printf '资源任务完成：%s\n' "${complete_response##*OK|}"
        ((processed++))
    done
}

run_resource_targets() {
    local line endpoint_key script_for_key label seen=";" ok=0 fail=0 skipped=0 disabled=0 duplicate=0
    ensure_config_file || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        label="${TARGET_LABEL:-${TARGET_PO0_HOST}}"
        if [[ "${TARGET_ENABLED}" != "1" ]]; then
            ((disabled++))
            continue
        fi
        if [[ -z "${TARGET_RESOURCE_TOKEN}" ]]; then
            printf '资源任务：%s 未配置 Token，跳过。\n' "${label}"
            ((skipped++))
            continue
        fi
        script_for_key="${TARGET_PO0_SCRIPT:-${DEFAULT_PO0_SCRIPT}}"
        endpoint_key="${TARGET_PO0_USER:-root}@${TARGET_PO0_HOST}:${TARGET_PO0_PORT:-22}:${script_for_key}:${TARGET_RESOURCE_TOKEN}"
        if [[ "${seen}" == *";${endpoint_key};"* ]]; then
            printf '资源任务：%s 与前面目标使用同一 PO0/token，跳过重复轮询。\n' "${label}"
            ((duplicate++))
            continue
        fi
        seen+="${endpoint_key};"
        printf '资源任务：轮询 %s -> %s@%s:%s\n' "${label}" "${TARGET_PO0_USER:-root}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT:-22}"
        if run_resource_endpoint "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT:-22}" "${TARGET_PO0_USER:-root}" "${TARGET_PO0_SCRIPT:-${DEFAULT_PO0_SCRIPT}}" "${TARGET_RESOURCE_TOKEN}" "${TARGET_SSH_EXTRA_ARGS}"; then
            ((ok++))
        else
            ((fail++))
        fi
    done < "${CONFIG_FILE}"
    printf '资源任务轮询完成：成功/无任务 %s，失败 %s，未配置 Token 跳过 %s，停用跳过 %s，重复跳过 %s。\n' "${ok}" "${fail}" "${skipped}" "${disabled}" "${duplicate}"
    prune_resource_events "${RESOURCE_EVENTS_KEEP}" || true
    [[ "${fail}" == "0" ]]
}

run_all_client_jobs() {
    local failed=0
    run_resource_targets || failed=1
    run_config_targets || failed=1
    return "${failed}"
}
