list_resource_tasks() {
    local line id type status created claimed finished worker artifact sha size message count=0
    ensure_resource_task_layout || return 1
    print_panel_section "资源任务队列"
    print_panel_row "任务文件" "${RESOURCE_TASKS_FILE}"
    print_panel_row "收件目录" "${RESOURCE_INBOX_DIR}"
    if resource_task_token_value >/dev/null 2>&1; then
        print_panel_row "Worker Token" "已生成（菜单 [7] 可显示部署命令或重置）"
    else
        print_panel_row "Worker Token" "未生成（先执行菜单 [7] 生成任务 Token）"
    fi
    print_panel_section "任务列表"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -n "${line}" && "${line}" != \#* ]] || continue
        IFS='|' read -r id type status created claimed finished worker artifact sha size message <<< "${line}"
        ((count++))
        printf '  %2d) %s  %-10s %-8s 创建=%s\n' \
            "${count}" "${id}" "$(resource_task_type_label "${type}")" "$(resource_task_status_label "${status}")" "${created:-未知}"
        [[ -n "${worker}" ]] && printf '      worker=%s 领取=%s 完成=%s\n' "${worker}" "${claimed:-未知}" "${finished:-未完成}"
        [[ -n "${artifact}" ]] && printf '      文件=%s 大小=%s SHA256=%s\n' "${artifact}" "${size:-未知}" "${sha:-未知}"
        [[ -n "${message}" ]] && printf '      结果=%s\n' "${message}"
    done < "${RESOURCE_TASKS_FILE}"
    [[ "${count}" -gt 0 ]] || print_panel_row "记录" "暂无任务"
}

do_show_or_create_resource_task_token() {
    local token
    if token="$(resource_task_token_value 2>/dev/null)"; then
        print_panel_section "资源任务 Token"
        print_panel_row "状态" "已生成"
        print_panel_row "Token" "${token}"
        print_lan_worker_resource_bootstrap_example "${token}"
        if confirm_yes "是否重置任务 Token（旧 Worker Token 将立即失效）"; then
            token="$(generate_resource_task_token)" || return 1
            success "新任务 Token：${token}"
            print_lan_worker_resource_bootstrap_example "${token}"
        else
            info "已保留现有任务 Token。"
        fi
        return 0
    fi

    warn "资源任务 Token 尚未生成；LAN Worker 需要这个 Token 才能领取任务。"
    if confirm_yes "是否现在生成任务 Token"; then
        token="$(generate_resource_task_token)" || return 1
        success "任务 Token：${token}"
        print_lan_worker_resource_bootstrap_example "${token}"
    else
        info "已取消生成任务 Token。"
    fi
}

claim_resource_task() {
    local worker="$1"
    local token="$2"
    local line id type status created claimed finished old_worker artifact sha size message
    local tmp now upload_path found=0
    worker="$(tsv_safe "$(trim "${worker}")")"
    [[ "${worker}" =~ ^[A-Za-z0-9._:-]{1,80}$ ]] || {
        printf 'ERROR|worker_id 无效\n'
        return 1
    }
    resource_task_token_matches "${token}" || {
        printf 'ERROR|Token 错误\n'
        return 1
    }
    resource_task_lock || return 1
    make_temp_file "${RESOURCE_TASKS_FILE}" || {
        resource_task_unlock
        return 1
    }
    tmp="${TEMP_FILE_RESULT}"
    now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${found}" == "0" && -n "${line}" && "${line}" != \#* ]]; then
            IFS='|' read -r id type status created claimed finished old_worker artifact sha size message <<< "${line}"
            if [[ "${status}" == "pending" ]]; then
                found=1
                upload_path="${RESOURCE_INBOX_DIR}/${id}.$(resource_task_artifact_name "${type}")"
                printf '%s|%s|running|%s|%s||%s||||已由内网机器领取\n' \
                    "${id}" "${type}" "${created}" "${now}" "${worker}" >> "${tmp}"
                continue
            fi
        fi
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${RESOURCE_TASKS_FILE}"
    mv -f "${tmp}" "${RESOURCE_TASKS_FILE}"
    resource_task_unlock
    if [[ "${found}" == "1" ]]; then
        printf 'TASK|%s|%s|%s\n' "${id}" "${type}" "${upload_path}"
    else
        printf 'NO_TASK\n'
    fi
}
