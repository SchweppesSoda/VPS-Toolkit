finish_resource_task() {
    local task_id="$1"
    local worker="$2"
    local reported_sha="$3"
    local reported_size="$4"
    local token="$5"
    local line id type status created claimed finished task_worker artifact sha size message
    local tmp now expected_path actual_sha actual_size result_message found=0 ok=0
    [[ "${task_id}" =~ ^[A-Za-z0-9._-]+$ ]] || { printf 'ERROR|任务 ID 无效\n'; return 1; }
    [[ "${worker}" =~ ^[A-Za-z0-9._:-]{1,80}$ ]] || { printf 'ERROR|worker_id 无效\n'; return 1; }
    resource_task_token_matches "${token}" || { printf 'ERROR|Token 错误\n'; return 1; }
    resource_task_lock || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -n "${line}" && "${line}" != \#* ]] || continue
        IFS='|' read -r id type status created claimed finished task_worker artifact sha size message <<< "${line}"
        if [[ "${id}" == "${task_id}" ]]; then
            found=1
            [[ "${status}" == "running" && "${task_worker}" == "${worker}" ]] || {
                resource_task_unlock
                printf 'ERROR|任务状态或领取机器不匹配\n'
                return 1
            }
            break
        fi
    done < "${RESOURCE_TASKS_FILE}"
    [[ "${found}" == "1" ]] || {
        resource_task_unlock
        printf 'ERROR|任务不存在\n'
        return 1
    }
    expected_path="${RESOURCE_INBOX_DIR}/${task_id}.$(resource_task_artifact_name "${type}")"
    [[ -f "${expected_path}" ]] || {
        resource_task_unlock
        printf 'ERROR|尚未收到任务文件\n'
        return 1
    }
    command -v sha256sum >/dev/null 2>&1 || {
        resource_task_unlock
        printf 'ERROR|PO0 缺少 sha256sum\n'
        return 1
    }
    actual_sha="$(sha256sum "${expected_path}" | awk '{print $1}')"
    actual_size="$(wc -c < "${expected_path}" | tr -d '[:space:]')"
    if [[ "${actual_sha}" != "${reported_sha}" || "${actual_size}" != "${reported_size}" ]]; then
        resource_task_unlock
        printf 'ERROR|SHA256 或文件大小不匹配\n'
        return 1
    fi
    case "${type}" in
        iplist)
            if activate_received_iplist "${expected_path}" >/dev/null; then
                ok=1
                result_message="iplist 已校验、导入并按当前白名单状态应用"
            else
                result_message="iplist 校验或导入失败，旧数据已保留"
            fi
            ;;
        ipdb)
            if install_received_ipdb "${expected_path}"; then
                ok=1
                result_message="qqwry.ipdb 已校验并替换"
            else
                result_message="qqwry.ipdb 格式校验或安装失败，旧数据已保留"
            fi
            ;;
    esac
    now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    make_temp_file "${RESOURCE_TASKS_FILE}" || {
        resource_task_unlock
        return 1
    }
    tmp="${TEMP_FILE_RESULT}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ -n "${line}" && "${line}" != \#* ]]; then
            IFS='|' read -r id type status created claimed finished task_worker artifact sha size message <<< "${line}"
            if [[ "${id}" == "${task_id}" ]]; then
                if [[ "${ok}" == "1" ]]; then
                    status="success"
                else
                    status="failed"
                fi
                printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
                    "${id}" "${type}" "${status}" "${created}" "${claimed}" "${now}" "${task_worker}" \
                    "${expected_path}" "${actual_sha}" "${actual_size}" "$(tsv_safe "${result_message}")" >> "${tmp}"
                continue
            fi
        fi
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${RESOURCE_TASKS_FILE}"
    mv -f "${tmp}" "${RESOURCE_TASKS_FILE}"
    compact_resource_tasks_file || {
        resource_task_unlock
        return 1
    }
    [[ "${ok}" == "1" ]] && rm -f -- "${expected_path}" 2>/dev/null || true
    resource_task_unlock
    if [[ "${ok}" == "1" ]]; then
        printf 'OK|%s\n' "${result_message}"
        return 0
    fi
    printf 'ERROR|%s\n' "${result_message}"
    return 1
}

fail_resource_task() {
    local task_id="$1"
    local worker="$2"
    local reason="$3"
    local token="$4"
    local line id type status created claimed finished task_worker artifact sha size message
    local tmp now found=0
    [[ "${task_id}" =~ ^[A-Za-z0-9._-]+$ ]] || { printf 'ERROR|任务 ID 无效\n'; return 1; }
    resource_task_token_matches "${token}" || { printf 'ERROR|Token 错误\n'; return 1; }
    reason="$(tsv_safe "${reason}")"
    resource_task_lock || return 1
    make_temp_file "${RESOURCE_TASKS_FILE}" || {
        resource_task_unlock
        return 1
    }
    tmp="${TEMP_FILE_RESULT}"
    now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ -n "${line}" && "${line}" != \#* ]]; then
            IFS='|' read -r id type status created claimed finished task_worker artifact sha size message <<< "${line}"
            if [[ "${id}" == "${task_id}" && "${status}" == "running" && "${task_worker}" == "${worker}" ]]; then
                found=1
                printf '%s|%s|failed|%s|%s|%s|%s||||%s\n' \
                    "${id}" "${type}" "${created}" "${claimed}" "${now}" "${task_worker}" "${reason:-内网机器执行失败}" >> "${tmp}"
                continue
            fi
        fi
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${RESOURCE_TASKS_FILE}"
    mv -f "${tmp}" "${RESOURCE_TASKS_FILE}"
    compact_resource_tasks_file || {
        resource_task_unlock
        return 1
    }
    resource_task_unlock
    [[ "${found}" == "1" ]] || { printf 'ERROR|任务状态或领取机器不匹配\n'; return 1; }
    printf 'OK|失败原因已记录\n'
}

retry_resource_tasks() {
    local line id type status created claimed finished worker artifact sha size message tmp count=0 skipped=0
    declare -A pending_seen=()
    ensure_resource_task_layout || return 1
    resource_task_lock || return 1
    make_temp_file "${RESOURCE_TASKS_FILE}" || {
        resource_task_unlock
        return 1
    }
    tmp="${TEMP_FILE_RESULT}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ -n "${line}" && "${line}" != \#* ]]; then
            IFS='|' read -r id type status created claimed finished worker artifact sha size message <<< "${line}"
            if [[ "${status}" == "pending" ]]; then
                pending_seen["${type}"]=1
            fi
            if [[ "${status}" == "failed" || "${status}" == "running" ]]; then
                if [[ "${pending_seen[${type}]:-0}" == "1" ]]; then
                    ((skipped++))
                    printf '%s\n' "${line}" >> "${tmp}"
                    continue
                fi
                pending_seen["${type}"]=1
                ((count++))
                printf '%s|%s|pending|%s|||||||手动重新排队\n' "${id}" "${type}" "${created}" >> "${tmp}"
                continue
            fi
        fi
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${RESOURCE_TASKS_FILE}"
    mv -f "${tmp}" "${RESOURCE_TASKS_FILE}"
    compact_resource_tasks_file || {
        resource_task_unlock
        return 1
    }
    resource_task_unlock
    success "已将 ${count} 个失败或执行中的任务重新排队。"
    [[ "${skipped}" -eq 0 ]] || warn "已跳过 ${skipped} 个同类型重复任务，避免堆积多个 pending。"
}
