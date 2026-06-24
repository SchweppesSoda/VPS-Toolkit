do_manage_ddns_allowlist_sources() {
    local choice
    ensure_layout || return
    load_settings 1
    while true; do
        menu_clear_screen
        print_title "管理 DDNS 来源"
        printf '当前 DDNS 来源数量：%s\n' "$(allowlist_sources_count)"
        print_menu_section "查看与维护"
        print_menu_pair 1 "查看来源和统计" 2 "添加来源"
        print_menu_pair 3 "编辑来源" 4 "删除来源"
        print_menu_pair 5 "启用 / 停用来源" 6 "刷新并应用已启用来源"
        print_menu_section "Token"
        print_menu_item 7 "显示 / 生成外部上报 Token"
        print_menu_section "退出"
        print_menu_item 0 "返回"
        print_menu_footer
        read_menu_choice_or_return choice "请选择操作 [0-7]: " || return
        case "${choice}" in
            1)
                show_ddns_allowlist_sources
                pause_before_return
                ;;
            2)
                do_add_ddns_allowlist_source
                pause_before_return
                ;;
            3)
                do_edit_ddns_allowlist_source
                pause_before_return
                ;;
            4)
                do_delete_ddns_allowlist_source
                pause_before_return
                ;;
            5)
                do_toggle_ddns_allowlist_source
                pause_before_return
                ;;
            6)
                do_refresh_ddns_allowlist_sources
                pause_before_return
                ;;
            7)
                do_show_ddns_report_token
                pause_before_return
                ;;
            0)
                return
                ;;
            *)
                err "无效选择。"
                pause_before_return
                ;;
        esac
    done
}

do_collect_blocked_ips() {
    local since="${1:-1 hour ago}"
    ensure_layout || return 1
    collect_blocked_ip_logs "${since}" || return 1
    printf '被阻挡访问日志：新增 %s 条，跳过 %s 条，当前总计 %s 条\n' \
        "${BLOCK_LOG_ADDED_COUNT:-0}" \
        "${BLOCK_LOG_SKIPPED_COUNT:-0}" \
        "$(block_log_count)"
    printf '日志文件：%s\n' "${BLOCK_LOG_FILE}"
    printf '说明：日志文件保存来源 IP、协议、目标端口、阻挡时间；归属地/运营商在查看统计时通过 IPDB 实时显示。\n'
}

do_print_blocked_log_stats() {
    local row idx=1 ip proto dport set_id count first_seen last_seen ip_info
    local ipdb_ready=0
    local -a rows=()
    ensure_layout || return 1
    regenerate_block_summary || return 1
    ipdb_lookup_ready && ipdb_ready=1

    print_title "被阻挡访问统计"
    printf '日志文件   : %s（%s 条，%s）\n' \
        "${BLOCK_LOG_FILE}" "$(block_log_count)" "$(format_bytes "$(block_log_size_bytes)")"
    printf '统计文件   : %s（%s 行）\n' "${BLOCK_SUMMARY_FILE}" "$(block_summary_count)"
    printf 'IPDB 数据  : %s\n' "$(ipdb_status_label)"
    printf '说明       : 文件只保存 IP/协议/端口/时间；归属地和运营商由 IPDB 查询显示。\n'

    mapfile -t rows < <(awk -F '|' 'NF >= 7 && $1 !~ /^#/ { print }' "${BLOCK_SUMMARY_FILE}" | head -n 30)
    if [[ ${#rows[@]} -eq 0 ]]; then
        echo "  (暂无被阻挡访问记录)"
        return 0
    fi

    echo ""
    echo "Top 被阻挡来源："
    for row in "${rows[@]}"; do
        IFS='|' read -r ip proto dport set_id count first_seen last_seen <<< "${row}"
        ip_info="$(ipdb_lookup_ip "${ip}" "${ipdb_ready}")"
        printf '  [%d] %s | %s | %s/%s | 命中 %s 次\n' \
            "${idx}" "${ip}" "${ip_info}" "${proto}" "${dport}" "${count}"
        printf '      首次: %s | 最近: %s | 集合: %s\n' \
            "$(format_learn_time "${first_seen}")" "$(format_learn_time "${last_seen}")" "${set_id}"
        ((idx++))
    done
}

do_compact_block_log() {
    local before_count before_size before_summary after_count after_size after_summary
    ensure_layout || return 1
    before_count="$(block_log_count)"
    before_size="$(block_log_size_bytes)"
    before_summary="$(block_summary_count)"
    compact_block_log_if_needed "manual" || return 1
    after_count="$(block_log_count)"
    after_size="$(block_log_size_bytes)"
    after_summary="$(block_summary_count)"
    if [[ "${before_count}" == "${after_count}" && "${before_size}" == "${after_size}" && "${before_summary}" == "${after_summary}" ]]; then
        info "被阻挡访问日志尚未超过压缩阈值；统计文件已刷新。"
    else
        success "被阻挡访问日志已压缩：${before_count} 条 / $(format_bytes "${before_size}") -> ${after_count} 条 / $(format_bytes "${after_size}")；统计 ${after_summary} 行。"
    fi
}

do_clear_block_log() {
    ensure_layout || return 1
    [[ -s "${BLOCK_LOG_FILE}" ]] || {
        warn "被阻挡访问日志为空。"
        return 0
    }
    confirm_yes "确认清空被阻挡访问日志" || return 1
    write_block_log_header "${BLOCK_LOG_FILE}" || return 1
    regenerate_block_summary || return 1
    success "被阻挡访问日志已清空。"
}

do_save_allowlist_profile() {
    local name label
    if (( $(allowlist_profile_count) >= ALLOWLIST_PROFILE_MAX_COUNT )); then
        err "白名单配置档案最多保存 ${ALLOWLIST_PROFILE_MAX_COUNT} 个，请先删除不用的配置档案。"
        return 1
    fi
    label="$(read_prompt "请输入白名单配置档案显示名: ")" || return 1
    label="$(sanitize_profile_label "${label}")"
    [[ -n "${label}" ]] || {
        err "显示名不能为空。"
        return 1
    }
    name="$(generate_allowlist_profile_id)" || return 1
    save_allowlist_profile_state "${name}" 0 "${label}"
}

do_apply_allowlist_profile() {
    select_allowlist_profile || return 1
    confirm_yes "确认应用白名单配置档案 ${SELECTED_ALLOWLIST_PROFILE}" || return 1
    apply_allowlist_profile "${SELECTED_ALLOWLIST_PROFILE}" 1
}

do_restore_last_allowlist_profile() {
    allowlist_profile_exists "${ALLOWLIST_LAST_PROFILE_NAME}" || {
        err "还没有上一次白名单快照。"
        return 1
    }
    print_allowlist_profile_summary "${ALLOWLIST_LAST_PROFILE_NAME}" "last" || true
    confirm_yes "确认恢复上一次白名单快照" || return 1
    apply_allowlist_profile "${ALLOWLIST_LAST_PROFILE_NAME}" 0
}

do_delete_allowlist_profile() {
    local env_file label_file custom_file sets_file entries_file sources_file
    select_allowlist_profile || return 1
    confirm_yes "确认删除白名单配置档案 ${SELECTED_ALLOWLIST_PROFILE}" || return 1
    env_file="$(allowlist_profile_env_file "${SELECTED_ALLOWLIST_PROFILE}")"
    label_file="$(allowlist_profile_label_file "${SELECTED_ALLOWLIST_PROFILE}")"
    custom_file="$(allowlist_profile_custom_file "${SELECTED_ALLOWLIST_PROFILE}")"
    sets_file="$(allowlist_profile_sets_file "${SELECTED_ALLOWLIST_PROFILE}")"
    entries_file="$(allowlist_profile_entries_file "${SELECTED_ALLOWLIST_PROFILE}")"
    sources_file="$(allowlist_profile_sources_file "${SELECTED_ALLOWLIST_PROFILE}")"
    rm -f -- "${env_file}" "${label_file}" "${custom_file}" "${sets_file}" "${entries_file}" "${sources_file}"
    success "白名单配置档案已删除：${SELECTED_ALLOWLIST_PROFILE}"
}

do_manage_allowlist_profiles() {
    local choice
    while true; do
        menu_clear_screen
        print_title "白名单配置档案"
        show_allowlist_profiles
        echo ""
        print_menu_item 1 "保存当前白名单为配置档案"
        print_menu_item 2 "应用配置档案"
        print_menu_item 3 "恢复上一次白名单快照"
        print_menu_item 4 "删除配置档案"
        print_menu_item 0 "返回"
        print_menu_footer
        read_menu_choice_or_return choice "请选择操作 [0-4]: " || return
        case "${choice}" in
            1)
                do_save_allowlist_profile
                pause_before_return
                ;;
            2)
                do_apply_allowlist_profile
                pause_before_return
                ;;
            3)
                do_restore_last_allowlist_profile
                pause_before_return
                ;;
            4)
                do_delete_allowlist_profile
                pause_before_return
                ;;
            0)
                return
                ;;
            *)
                err "无效选择。"
                pause_before_return
                ;;
        esac
    done
}

do_add_custom_allowlist_entry() {
    local cidr note
    cidr="$(read_prompt "请输入自定义来源 IP 或 CIDR（例如 1.2.3.4 或 1.2.3.0/24）: ")" || return 1
    cidr="$(trim "${cidr}")"
    [[ -n "${cidr}" ]] || return 1
    note="$(read_prompt "备注（可空）: ")" || note=""
    save_allowlist_last_snapshot || return 1
    add_custom_allowlist_entry "${cidr}" "${note}" || return 1
    enable_allowlist_for_custom_add
    apply_src_allowlist_changes
}

do_add_ssh_temp_allowlist_entry() {
    local ip hours expires_at note
    ip="$(detect_ssh_client_ip || true)"
    [[ -n "${ip}" ]] || {
        err "未检测到当前 SSH 客户端公网 IPv4。此功能只能在 SSH 会话内使用。"
        return 1
    }
    hours="$(prompt_with_default "请输入临时放行小时数" "24")"
    hours="$(trim "${hours}")"
    [[ "${hours}" =~ ^[0-9]+$ && "${hours}" -ge 1 && "${hours}" -le 720 ]] || {
        err "临时放行小时数必须是 1-720。"
        return 1
    }
    expires_at="$(utc_after_hours_iso "${hours}")"
    note="ssh client ${ip}, expires ${expires_at}"
    printf 'SSH 来源 IP : %s/32\n' "${ip}"
    printf '过期时间    : %s\n' "${expires_at}"
    confirm_yes "确认加入 default 临时白名单" || return 1
    save_allowlist_last_snapshot || return 1
    upsert_allowlist_entry "default" "${ip}/32" "ssh_temp" "SSH_CONNECTION" "${note}" "${expires_at}" || return 1
    enable_allowlist_source_type_for_current_mode "ssh_temp" || return 1
    apply_src_allowlist_changes
}

do_delete_custom_allowlist_entry() {
    select_custom_allowlist_entry || return 1
    save_allowlist_last_snapshot || return 1
    remove_custom_allowlist_entry "${SELECTED_LEARN_CIDR}" || {
        err "删除自定义 CIDR 失败。"
        return 1
    }
    disable_src_allowlist_if_no_custom_entries
    apply_src_allowlist_changes
}

do_promote_learned_ip() {
    select_learned_ip_candidate || return 1
    save_allowlist_last_snapshot || return 1
    add_custom_allowlist_entry "${SELECTED_LEARN_CIDR}" "${SELECTED_LEARN_NOTE}" || return 1
    enable_allowlist_for_custom_add
    apply_src_allowlist_changes
}

do_promote_learned_cidr24() {
    select_learned_cidr24_candidate || return 1
    warn "${SELECTED_LEARN_CIDR} 是按学习记录推测的 /24 网段，不等于只属于你的设备。"
    confirm_yes "确认加入这个 /24 自定义白名单" || return 1
    save_allowlist_last_snapshot || return 1
    add_custom_allowlist_entry "${SELECTED_LEARN_CIDR}" "${SELECTED_LEARN_NOTE}" || return 1
    enable_allowlist_for_custom_add
    apply_src_allowlist_changes
}

do_promote_learned_cidr16() {
    select_learned_cidr16_candidate || return 1
    warn "${SELECTED_LEARN_CIDR} 是按学习记录推测的 /16 网段，可能覆盖大量同运营商出口用户。"
    warn "这不是设备级白名单，只适合作为蜂窝网络出口池的宽泛兜底。"
    confirm_strong_yes "确认加入这个 /16 自定义白名单" || return 1
    save_allowlist_last_snapshot || return 1
    add_custom_allowlist_entry "${SELECTED_LEARN_CIDR}" "${SELECTED_LEARN_NOTE}" || return 1
    enable_allowlist_for_custom_add
    apply_src_allowlist_changes
}

do_toggle_learning_service() {
    if command -v systemctl &>/dev/null && systemctl is-active --quiet "${LEARN_SERVICE_NAME}" 2>/dev/null; then
        confirm_yes "确认停止来源 IP 学习服务" || return 1
        disable_learning_service || return 1
        success "来源 IP 学习服务已停止。"
    else
        warn "学习服务只记录成功完成双向转发的来源公网 IP，不会自动放行。"
        confirm_yes "确认安装并启动来源 IP 学习服务" || return 1
        enable_learning_service || return 1
        success "来源 IP 学习服务已启动。"
    fi
}

do_clear_learning_log() {
    [[ -s "${LEARN_LOG_FILE}" ]] || {
        warn "学习日志为空。"
        return 0
    }
    confirm_yes "确认清空学习日志" || return 1
    : > "${LEARN_LOG_FILE}"
    success "学习日志已清空。"
}

do_compact_learning_log() {
    local before_count before_size after_count after_size before_snapshots after_snapshots
    before_count="$(learning_log_count)"
    before_size="$(learning_log_size_bytes)"
    before_snapshots="$(learning_summary_count)"
    compact_learning_log_if_needed "manual" || return 1
    after_count="$(learning_log_count)"
    after_size="$(learning_log_size_bytes)"
    after_snapshots="$(learning_summary_count)"
    if [[ "${before_count}" == "${after_count}" && "${before_size}" == "${after_size}" && "${before_snapshots}" == "${after_snapshots}" ]]; then
        info "学习日志尚未超过压缩阈值，无需压缩。"
    else
        success "学习日志已压缩：${before_count} 条 / $(format_bytes "${before_size}") -> ${after_count} 条 / $(format_bytes "${after_size}")；每日汇总 ${after_snapshots} 天。"
    fi
}

do_install_ipdb_parser() {
    print_title "安装 IPDB 解析依赖"
    warn "将创建专用 Python venv：${IPDB_VENV_DIR}"
    warn "将安装 Python 包：ipip-ipdb"
    IPDB_PIP_INDEX_URL="$(prompt_ipdb_pip_index)" || return 1
    info "已选择 pip 源：$(pip_index_label "${IPDB_PIP_INDEX_URL}")"
    confirm_yes "是否继续安装" || return 1
    install_ipdb_parser_dependency || return 1
    printf 'IPDB 状态 : %s\n' "$(ipdb_status_label)"
}

do_manage_region_allowlist() {
    local choice id
    while true; do
        menu_clear_screen
        print_title "地区白名单"
        echo "已选地区："
        show_selected_allowlist_regions
        echo ""
        print_menu_item 1 "添加地区"
        print_menu_item 2 "删除地区"
        print_menu_item 0 "返回"
        print_menu_footer
        read_menu_choice_or_return choice "请选择操作 [0-2]: " || return
        case "${choice}" in
            1)
                select_iplist_region_interactive || {
                    pause_before_return
                    continue
                }
                id="${SELECTED_REGION_ID}"
                save_allowlist_last_snapshot || {
                    pause_before_return
                    continue
                }
                add_allowlist_region_id "${id}" || {
                    err "添加地区失败。"
                    pause_before_return
                    continue
                }
                enable_allowlist_for_region_add
                apply_src_allowlist_changes
                pause_before_return
                ;;
            2)
                select_selected_allowlist_region || {
                    pause_before_return
                    continue
                }
                id="${SELECTED_REGION_ID}"
                save_allowlist_last_snapshot || {
                    pause_before_return
                    continue
                }
                remove_allowlist_region_id "${id}"
                disable_src_allowlist_if_no_custom_entries
                apply_src_allowlist_changes
                pause_before_return
                ;;
            0)
                return
                ;;
            *)
                err "无效选择。"
                pause_before_return
                ;;
        esac
    done
}

do_manage_custom_allowlist() {
    local choice
    while true; do
        menu_clear_screen
        print_title "自定义 CIDR 白名单"
        show_custom_allowlist_entries
        echo ""
        print_menu_item 1 "添加自定义 IP/CIDR"
        print_menu_item 2 "删除自定义 IP/CIDR"
        print_menu_item 0 "返回"
        print_menu_footer
        read_menu_choice_or_return choice "请选择操作 [0-2]: " || return
        case "${choice}" in
            1)
                do_add_custom_allowlist_entry
                pause_before_return
                ;;
            2)
                do_delete_custom_allowlist_entry
                pause_before_return
                ;;
            0)
                return
                ;;
            *)
                err "无效选择。"
                pause_before_return
                ;;
        esac
    done
}

do_print_dynamic_allowlist_cleanup_status() {
    print_title "动态来源清理 cron"
    printf '动态缓存策略：%s\n' "$(dynamic_allowlist_limits_label)"
    printf '清理 cron：\n'
    print_dynamic_allowlist_cron_summary
}

do_manage_dynamic_allowlist_maintenance() {
    local choice
    ensure_layout || return
    while true; do
        menu_clear_screen
        print_title "动态来源缓存维护"
        print_panel_section "状态"
        print_panel_row "动态来源限制" "$(dynamic_allowlist_limits_label)"
        print_panel_row "清理 cron" "$(print_dynamic_allowlist_cron_summary)"
        print_menu_section "查看与清理"
        print_menu_pair 1 "查看清理 cron" 2 "立即清理过期 / 超量 IP"
        print_menu_section "计划任务"
        print_menu_pair 3 "安装 / 更新清理 cron" 4 "删除清理 cron"
        print_menu_section "退出"
        print_menu_item 0 "返回"
        print_menu_footer
        read_menu_choice_or_return choice "请选择操作 [0-4]: " || return
        case "${choice}" in
            1)
                do_print_dynamic_allowlist_cleanup_status
                pause_before_return
                ;;
            2)
                do_cleanup_dynamic_allowlist
                pause_before_return
                ;;
            3)
                do_install_dynamic_allowlist_cleanup_cron_interactive
                pause_before_return
                ;;
            4)
                confirm_yes "确认删除动态来源清理 cron" && remove_dynamic_allowlist_cleanup_cron
                pause_before_return
                ;;
            0)
                return
                ;;
            *)
                err "无效选择。"
                pause_before_return
                ;;
        esac
    done
}

do_collect_blocked_ips_custom_since() {
    local since
    print_title "按时间范围采集被阻挡访问日志"
    echo "时间范围会传给 journalctl --since；例如 24 hours ago 或 2026-06-18 00:00:00。"
    since="$(prompt_with_default "请输入采集起点" "24 hours ago")"
    since="$(trim "${since}")"
    [[ -n "${since}" ]] || since="24 hours ago"
    do_collect_blocked_ips "${since}"
}

do_manage_blocked_log() {
    local choice
    ensure_layout || return
    while true; do
        menu_clear_screen
        print_title "被阻挡访问日志"
        printf '日志文件 : %s（%s 条，%s）\n' \
            "${BLOCK_LOG_FILE}" "$(block_log_count)" "$(format_bytes "$(block_log_size_bytes)")"
        printf '统计文件 : %s（%s 行）\n' "${BLOCK_SUMMARY_FILE}" "$(block_summary_count)"
        printf 'IPDB 数据: %s\n' "$(ipdb_status_label)"
        echo ""
        print_menu_section "查看与采集"
        print_menu_pair 1 "查看被阻挡访问统计" 2 "采集最近 1 小时日志"
        print_menu_item 3 "按自定义 since 采集日志"
        print_menu_section "日志维护"
        print_menu_pair 4 "压缩日志并刷新统计" 5 "清空日志"
        print_menu_section "退出"
        print_menu_item 0 "返回"
        print_menu_footer
        read_menu_choice_or_return choice "请选择操作 [0-5]: " || return
        case "${choice}" in
            1)
                do_print_blocked_log_stats
                pause_before_return
                ;;
            2)
                do_collect_blocked_ips "1 hour ago"
                pause_before_return
                ;;
            3)
                do_collect_blocked_ips_custom_since
                pause_before_return
                ;;
            4)
                do_compact_block_log
                pause_before_return
                ;;
            5)
                do_clear_block_log
                pause_before_return
                ;;
            0)
                return
                ;;
            *)
                err "无效选择。"
                pause_before_return
                ;;
        esac
    done
}

do_manage_learning_allowlist() {
    local choice
    while true; do
        menu_clear_screen
        print_title "来源 IP 学习与候选提升"
        printf '学习服务 : %s\n' "$(learning_service_status_label)"
        printf '学习日志 : %s（%s 条事件，%s）\n' \
            "${LEARN_LOG_FILE}" "$(learning_log_count)" "$(format_bytes "$(learning_log_size_bytes)")"
        printf '每日汇总 : %s（%s 天）\n' "${LEARN_SUMMARY_FILE}" "$(learning_summary_count)"
        printf 'IPDB 数据: %s\n' "$(ipdb_status_label)"
        echo ""
        print_menu_section "服务"
        print_menu_item 1 "启动 / 停止学习服务"
        print_menu_section "查看"
        print_menu_item 2 "查看学习记录与候选统计"
        print_menu_section "候选提升"
        print_menu_pair 3 "将学习到的单 IP 加入自定义白名单" 4 "将学习到的 /24 候选加入自定义白名单"
        print_menu_item 5 "将学习到的 /16 候选加入自定义白名单（高风险）"
        print_menu_section "日志维护"
        print_menu_pair 6 "压缩 / 归档学习日志" 7 "清空学习记录"
        print_menu_section "退出"
        print_menu_item 0 "返回"
        print_menu_footer
        read_menu_choice_or_return choice "请选择操作 [0-7]: " || return
        case "${choice}" in
            1)
                do_toggle_learning_service
                pause_before_return
                ;;
            2)
                print_learning_stats
                pause_before_return
                ;;
            3)
                do_promote_learned_ip
                pause_before_return
                ;;
            4)
                do_promote_learned_cidr24
                pause_before_return
                ;;
            5)
                do_promote_learned_cidr16
                pause_before_return
                ;;
            6)
                do_compact_learning_log
                pause_before_return
                ;;
            7)
                do_clear_learning_log
                pause_before_return
                ;;
            0)
                return
                ;;
            *)
                err "无效选择。"
                pause_before_return
                ;;
        esac
    done
}

do_manage_ipdb_tools() {
    local choice
    while true; do
        menu_clear_screen
        print_title "IPDB 数据与解析"
        printf 'IPDB 状态 : %s\n' "$(ipdb_status_label)"
        echo ""
        print_menu_item 1 "查看 IPDB 状态"
        print_menu_item 2 "安装 IPDB 解析依赖"
        print_menu_item 0 "返回"
        print_menu_footer
        read_menu_choice_or_return choice "请选择操作 [0-2]: " || return
        case "${choice}" in
            1)
                printf 'IPDB 状态 : %s\n' "$(ipdb_status_label)"
                pause_before_return
                ;;
            2)
                do_install_ipdb_parser
                pause_before_return
                ;;
            0)
                return
                ;;
            *)
                err "无效选择。"
                pause_before_return
                ;;
        esac
    done
}
