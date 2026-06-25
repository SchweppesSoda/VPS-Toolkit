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
