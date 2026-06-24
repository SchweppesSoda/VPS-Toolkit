write_resource_task_cron_without_managed_block() {
    local begin end line in_block=0
    begin="$(resource_task_cron_begin_marker)"
    end="$(resource_task_cron_end_marker)"
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

normalize_resource_task_cron_schedule() {
    local raw field
    local -a fields=()
    raw="$(trim "$*")"
    [[ -n "${raw}" ]] || raw="daily"
    case "${raw}" in
        hourly)
            printf '17 * * * *\n'
            return 0
            ;;
        daily)
            printf '17 4 * * *\n'
            return 0
            ;;
        weekly)
            printf '17 4 * * 0\n'
            return 0
            ;;
        monthly)
            printf '17 4 1 * *\n'
            return 0
            ;;
        @hourly|@daily|@weekly|@monthly)
            printf '%s\n' "${raw}"
            return 0
            ;;
    esac
    read -r -a fields <<< "${raw}"
    if [[ "${#fields[@]}" -ne 5 ]]; then
        err "cron 表达式无效：请使用 hourly/daily/weekly/monthly，或 5 字段 cron 表达式。"
        return 1
    fi
    for field in "${fields[@]}"; do
        [[ "${field}" =~ ^[-A-Za-z0-9*/,]+$ ]] || {
            err "cron 字段包含不支持的字符：${field}"
            return 1
        }
    done
    printf '%s %s %s %s %s\n' "${fields[0]}" "${fields[1]}" "${fields[2]}" "${fields[3]}" "${fields[4]}"
}

resource_task_cron_status_record() {
    local begin end line in_block=0 found=0 cron_line=""
    command -v crontab >/dev/null 2>&1 || {
        printf 'unavailable|系统未安装 crontab\n'
        return 0
    }
    begin="$(resource_task_cron_begin_marker)"
    end="$(resource_task_cron_end_marker)"
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
        [[ -n "${line}" ]] || continue
        cron_line="${line}"
        found=1
    done < <(crontab -l 2>/dev/null || true)
    if [[ "${found}" == "1" ]]; then
        printf 'installed|%s\n' "${cron_line}"
    else
        printf 'missing|未安装\n'
    fi
}

print_resource_task_cron_summary() {
    local status detail
    IFS='|' read -r status detail < <(resource_task_cron_status_record)
    case "${status}" in
        installed) printf '%b已安装%b：%s\n' "${C_GREEN}" "${C_RESET}" "${detail}" ;;
        unavailable) printf '%b不可用%b：%s\n' "${C_YELLOW}" "${C_RESET}" "${detail:-系统未安装 crontab}" ;;
        *) printf '%b未安装%b\n' "${C_YELLOW}" "${C_RESET}" ;;
    esac
}

do_resource_task_cron_status_cli() {
    local status detail
    ensure_layout || return 1
    IFS='|' read -r status detail < <(resource_task_cron_status_record)
    printf 'STATUS=%s\n' "${status}"
    printf 'DETAIL=%s\n' "${detail}"
    printf 'ROLE=po0-resource-task-create-schedule\n'
}

do_show_resource_task_cron_status() {
    local status detail
    print_title "PO0 定时创建状态"
    print_panel_section "职责"
    print_panel_row "创建位置" "PO0 只定时创建 pending 任务"
    print_panel_row "执行位置" "LAN Worker 按本机轮询器领取并执行"
    print_panel_section "当前状态"
    IFS='|' read -r status detail < <(resource_task_cron_status_record)
    case "${status}" in
        installed)
            print_panel_row "状态" "${C_GREEN}已安装${C_RESET}"
            print_panel_row "cron" "${detail}"
            print_panel_row "日志" "/tmp/po0-resource-task-cron.log"
            ;;
        unavailable)
            print_panel_row "状态" "${C_YELLOW}不可用${C_RESET}"
            print_panel_row "原因" "${detail:-系统未安装 crontab}"
            ;;
        *)
            print_panel_row "状态" "${C_YELLOW}未安装${C_RESET}"
            print_panel_row "下一步" "执行 [8] 安装 / 更新 PO0 定时创建"
            ;;
    esac
}

install_resource_task_cron() {
    local type schedule script_path escaped_script escaped_type job tmp
    type="$(normalize_resource_task_create_type "${1:-all}")" || return 1
    shift || true
    schedule="$(normalize_resource_task_cron_schedule "$@")" || return 1
    ensure_resource_task_layout || return 1
    command -v crontab >/dev/null 2>&1 || {
        err "当前系统没有 crontab 命令。请先安装 cron，或改用 systemd timer 调用 --resource-task-create。"
        return 1
    }
    script_path="$(ensure_persistent_manager_script)" || return 1
    chmod 0755 "${script_path}" 2>/dev/null || true
    escaped_script="$(shell_quote "${script_path}")"
    escaped_type="$(shell_quote "${type}")"
    job="${schedule} bash ${escaped_script} --resource-task-create ${escaped_type} >/tmp/po0-resource-task-cron.log 2>&1"
    tmp="${CONF_DIR}/po0-resource-task-cron.$$"
    {
        crontab -l 2>/dev/null | write_resource_task_cron_without_managed_block || true
        printf '%s\n' "$(resource_task_cron_begin_marker)"
        printf '%s\n' "${job}"
        printf '%s\n' "$(resource_task_cron_end_marker)"
    } > "${tmp}" || return 1
    crontab "${tmp}" || {
        rm -f -- "${tmp}" 2>/dev/null || true
        return 1
    }
    rm -f -- "${tmp}" 2>/dev/null || true
    success "已安装/更新 PO0 资源任务定时创建：${type}，计划：${schedule}"
    info "Worker 会在自己的轮询周期内领取这些任务并回传资源文件。"
}

remove_resource_task_cron() {
    local tmp
    mkdir -p "${CONF_DIR}" || return 1
    command -v crontab >/dev/null 2>&1 || {
        err "当前系统没有 crontab 命令。"
        return 1
    }
    tmp="${CONF_DIR}/po0-resource-task-cron.rm.$$"
    {
        crontab -l 2>/dev/null | write_resource_task_cron_without_managed_block || true
    } > "${tmp}" || return 1
    crontab "${tmp}" || {
        rm -f -- "${tmp}" 2>/dev/null || true
        return 1
    }
    rm -f -- "${tmp}" 2>/dev/null || true
    success "已删除 PO0 资源任务定时创建 cron。"
}

dynamic_allowlist_cron_begin_marker() {
    printf '# BEGIN PO0 nftables dynamic allowlist cleanup\n'
}

dynamic_allowlist_cron_end_marker() {
    printf '# END PO0 nftables dynamic allowlist cleanup\n'
}

write_dynamic_allowlist_cron_without_managed_block() {
    local begin end line in_block=0
    begin="$(dynamic_allowlist_cron_begin_marker)"
    end="$(dynamic_allowlist_cron_end_marker)"
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

print_dynamic_allowlist_cron_summary() {
    local begin end line in_block=0 found=0
    command -v crontab >/dev/null 2>&1 || {
        printf '系统未安装 crontab\n'
        return 0
    }
    begin="$(dynamic_allowlist_cron_begin_marker)"
    end="$(dynamic_allowlist_cron_end_marker)"
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
        [[ -n "${line}" ]] || continue
        printf '%s\n' "${line}"
        found=1
    done < <(crontab -l 2>/dev/null || true)
    [[ "${found}" == "1" ]] || printf '未安装\n'
}

install_dynamic_allowlist_cleanup_cron() {
    local schedule script_path escaped_script job tmp
    schedule="$(normalize_resource_task_cron_schedule "$@")" || return 1
    ensure_layout || return 1
    command -v crontab >/dev/null 2>&1 || {
        err "当前系统没有 crontab 命令。请先安装 cron，或手动调用 --cleanup-dynamic-allowlist。"
        return 1
    }
    script_path="$(ensure_persistent_manager_script)" || return 1
    chmod 0755 "${script_path}" 2>/dev/null || true
    escaped_script="$(shell_quote "${script_path}")"
    job="${schedule} bash ${escaped_script} --cleanup-dynamic-allowlist >/tmp/po0-dynamic-allowlist-cleanup.log 2>&1"
    tmp="${CONF_DIR}/po0-dynamic-allowlist-cleanup-cron.$$"
    {
        crontab -l 2>/dev/null | write_dynamic_allowlist_cron_without_managed_block || true
        printf '%s\n' "$(dynamic_allowlist_cron_begin_marker)"
        printf '%s\n' "${job}"
        printf '%s\n' "$(dynamic_allowlist_cron_end_marker)"
    } > "${tmp}" || return 1
    crontab "${tmp}" || {
        rm -f -- "${tmp}" 2>/dev/null || true
        return 1
    }
    rm -f -- "${tmp}" 2>/dev/null || true
    success "已安装/更新动态来源清理 cron：${schedule}"
}

remove_dynamic_allowlist_cleanup_cron() {
    local tmp
    mkdir -p "${CONF_DIR}" || return 1
    command -v crontab >/dev/null 2>&1 || {
        err "当前系统没有 crontab 命令。"
        return 1
    }
    tmp="${CONF_DIR}/po0-dynamic-allowlist-cleanup-cron.rm.$$"
    {
        crontab -l 2>/dev/null | write_dynamic_allowlist_cron_without_managed_block || true
    } > "${tmp}" || return 1
    crontab "${tmp}" || {
        rm -f -- "${tmp}" 2>/dev/null || true
        return 1
    }
    rm -f -- "${tmp}" 2>/dev/null || true
    success "已删除动态来源清理 cron。"
}

do_install_dynamic_allowlist_cleanup_cron_interactive() {
    local schedule
    print_title "安装动态来源清理 cron"
    echo "计划可填：hourly、daily、weekly、monthly，或标准 5 字段 cron 表达式。默认 daily。"
    schedule="$(prompt_with_default "请输入计划" "daily")"
    install_dynamic_allowlist_cleanup_cron "${schedule}"
}

do_install_resource_task_cron_interactive() {
    local choice type schedule
    print_title "安装 PO0 资源任务定时创建"
    print_panel_section "职责"
    print_panel_row "创建位置" "只在 PO0 端创建任务"
    print_panel_row "执行位置" "LAN Worker 只按本机轮询器领取并执行已创建任务"
    print_menu_section "任务类型"
    print_menu_item 1 "iplist 地区库"
    print_menu_item 2 "qqwry.ipdb"
    print_menu_item 3 "全部更新"
    print_menu_footer
    choice="$(read_menu_choice "请选择要定时创建的任务 [1-3，默认 3]: ")" || return 1
    case "${choice:-3}" in
        1) type="iplist" ;;
        2) type="ipdb" ;;
        3) type="all" ;;
        *)
            err "无效选择。"
            return 1
            ;;
    esac
    print_panel_section "计划"
    print_panel_row "可填" "hourly、daily、weekly、monthly，或标准 5 字段 cron 表达式"
    schedule="$(prompt_with_default "请输入计划" "daily")"
    install_resource_task_cron "${type}" "${schedule}"
}

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

validate_ipdb_file() {
    local file="$1"
    local py metadata_size metadata file_size
    local b1 b2 b3 b4
    [[ -s "${file}" ]] || {
        err "IPDB 文件为空。"
        return 1
    }
    command -v od >/dev/null 2>&1 && command -v dd >/dev/null 2>&1 || {
        err "校验 qqwry.ipdb 需要 od 和 dd。"
        return 1
    }
    read -r b1 b2 b3 b4 < <(od -An -N4 -tu1 "${file}" 2>/dev/null)
    [[ "${b1:-}" =~ ^[0-9]+$ && "${b2:-}" =~ ^[0-9]+$ && "${b3:-}" =~ ^[0-9]+$ && "${b4:-}" =~ ^[0-9]+$ ]] || {
        err "IPDB 文件头无效。"
        return 1
    }
    metadata_size=$((b1 * 16777216 + b2 * 65536 + b3 * 256 + b4))
    (( metadata_size >= 32 && metadata_size <= 1048576 )) || {
        err "IPDB 元数据长度无效。"
        return 1
    }
    file_size="$(wc -c < "${file}" | tr -d '[:space:]')"
    [[ "${file_size}" =~ ^[0-9]+$ ]] && (( file_size > metadata_size + 4 )) || {
        err "IPDB 文件缺少数据区。"
        return 1
    }
    metadata="$(dd if="${file}" bs=1 skip=4 count="${metadata_size}" 2>/dev/null)" || return 1
    printf '%s' "${metadata}" | grep -q '"fields"' || { err "IPDB 元数据缺少 fields。"; return 1; }
    printf '%s' "${metadata}" | grep -q '"languages"' || { err "IPDB 元数据缺少 languages。"; return 1; }
    printf '%s' "${metadata}" | grep -q '"node_count"' || { err "IPDB 元数据缺少 node_count。"; return 1; }

    py="$(ipdb_python_cmd 2>/dev/null || true)"
    [[ -n "${py}" ]] || return 0
    "${py}" - "${file}" <<'PY' >/dev/null 2>&1
import json
import struct
import sys

path = sys.argv[1]
with open(path, "rb") as fh:
    header = fh.read(4)
    if len(header) != 4:
        raise SystemExit(1)
    metadata_size = struct.unpack(">I", header)[0]
    if metadata_size < 32 or metadata_size > 1024 * 1024:
        raise SystemExit(1)
    metadata = json.loads(fh.read(metadata_size).decode("utf-8"))
    if not isinstance(metadata.get("fields"), list):
        raise SystemExit(1)
    if "languages" not in metadata or "node_count" not in metadata:
        raise SystemExit(1)
    if fh.read(1) == b"":
        raise SystemExit(1)
PY
}

install_received_ipdb() {
    local source="$1"
    local tmp backup
    validate_ipdb_file "${source}" || return 1
    make_temp_file "${IPDB_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    cp "${source}" "${tmp}" || return 1
    validate_ipdb_file "${tmp}" || return 1
    if [[ -f "${IPDB_FILE}" ]]; then
        backup="${BACKUP_DIR}/qqwry.ipdb.$(date '+%Y%m%d_%H%M%S')"
        cp "${IPDB_FILE}" "${backup}" 2>/dev/null || true
    fi
    mv -f "${tmp}" "${IPDB_FILE}" || return 1
    chmod 600 "${IPDB_FILE}" 2>/dev/null || true
}

activate_received_iplist() {
    local package="$1"
    import_iplist_package "${package}" || return 1
    load_settings 1
    if src_allowlist_enabled; then
        build_src_allowlist_cache || return 1
        backup_managed_files
        write_nft_conf || return 1
        apply_or_save_notice "iplist 已刷新并应用。" "iplist 已刷新，托管配置已更新。" || return 1
    fi
}

upload_resource_task_artifact() {
    local task_id="$1"
    local worker="$2"
    local reported_sha="$3"
    local reported_size="$4"
    local token="$5"
    local line id type status created claimed finished task_worker artifact sha size message
    local expected_path tmp actual_sha actual_size found=0
    [[ "${task_id}" =~ ^[A-Za-z0-9._-]+$ ]] || { printf 'ERROR|任务 ID 无效\n'; return 1; }
    [[ "${worker}" =~ ^[A-Za-z0-9._:-]{1,80}$ ]] || { printf 'ERROR|worker_id 无效\n'; return 1; }
    [[ "${reported_sha}" =~ ^[A-Fa-f0-9]{64}$ ]] || { printf 'ERROR|SHA256 无效\n'; return 1; }
    [[ "${reported_size}" =~ ^[0-9]+$ ]] || { printf 'ERROR|文件大小无效\n'; return 1; }
    resource_task_token_matches "${token}" || { printf 'ERROR|Token 错误\n'; return 1; }
    command -v sha256sum >/dev/null 2>&1 || { printf 'ERROR|PO0 缺少 sha256sum\n'; return 1; }
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
    make_temp_file "${expected_path}" || {
        resource_task_unlock
        return 1
    }
    tmp="${TEMP_FILE_RESULT}"
    if ! cat > "${tmp}"; then
        rm -f -- "${tmp}" 2>/dev/null || true
        resource_task_unlock
        printf 'ERROR|接收任务文件失败\n'
        return 1
    fi
    actual_sha="$(sha256sum "${tmp}" | awk '{print $1}')"
    actual_size="$(wc -c < "${tmp}" | tr -d '[:space:]')"
    if [[ "${actual_sha}" != "${reported_sha}" || "${actual_size}" != "${reported_size}" ]]; then
        rm -f -- "${tmp}" 2>/dev/null || true
        resource_task_unlock
        printf 'ERROR|SHA256 或文件大小不匹配\n'
        return 1
    fi
    mv -f "${tmp}" "${expected_path}" || {
        rm -f -- "${tmp}" 2>/dev/null || true
        resource_task_unlock
        printf 'ERROR|保存任务文件失败\n'
        return 1
    }
    chmod 600 "${expected_path}" 2>/dev/null || true
    resource_task_unlock
    printf 'OK|资源任务文件已上传\n'
}
