do_cancel_unfinished_resource_tasks_interactive() {
    local choice type
    print_panel_section "取消未完成任务"
    print_panel_row "范围" "等待领取 / 执行中"
    print_menu_item 1 "iplist 地区库"
    print_menu_item 2 "qqwry.ipdb"
    print_menu_item 3 "全部未完成任务"
    print_menu_item 0 "取消"
    print_menu_footer
    choice="$(read_menu_choice "请选择取消范围 [0-3]: ")" || return 1
    case "${choice}" in
        1) type="iplist" ;;
        2) type="ipdb" ;;
        3) type="all" ;;
        0) info "已取消。"; return 0 ;;
        *) err "无效选择。"; return 1 ;;
    esac
    confirm_yes "确认取消 ${type} 的未完成资源任务" || return 1
    delete_unfinished_resource_tasks "${type}"
}

print_resource_data_overview() {
    print_panel_section "资源数据"
    if iplist_ready; then
        print_panel_row "iplist 数据" "已导入"
        print_panel_row "iplist 目录" "${IPLIST_DIR}"
        print_panel_row "iplist 索引" "${IPLIST_MANIFEST}"
    else
        print_panel_row "iplist 数据" "未导入"
        print_panel_row "iplist 目录" "${IPLIST_DIR}"
    fi
    if [[ -s "${IPDB_FILE}" ]]; then
        print_panel_row "IPDB 文件" "已导入（${IPDB_FILE}）"
    else
        print_panel_row "IPDB 文件" "未导入（${IPDB_FILE}）"
    fi
    print_panel_row "IPDB 下载源" "${IPDB_DOWNLOAD_URL}"
}

do_manage_resource_tasks() {
    local choice token
    ensure_layout || return
    while true; do
        menu_clear_screen
        print_title "内网资源更新任务"
        print_resource_data_overview
        print_panel_section "任务状态"
        print_panel_row "职责说明" "PO0 端定时创建任务；LAN Worker 定期轮询、领取、执行并回传结果"
        if token="$(resource_task_token_value 2>/dev/null)"; then
            print_panel_row "任务 Token" "${token}"
        else
            print_panel_row "任务 Token" "未生成（执行 [7] 生成任务 Token）"
        fi
        print_panel_row "PO0 定时创建" "$(print_resource_task_cron_summary)"
        if [[ -n "${token:-}" ]]; then
            print_lan_worker_resource_bootstrap_example "${token}"
        fi
        print_menu_section "查看与创建"
        print_menu_pair 1 "查看任务和结果" 2 "创建 iplist 更新任务"
        print_menu_pair 3 "创建 qqwry.ipdb 更新任务" 4 "创建全部更新任务"
        print_menu_section "队列维护"
        print_menu_pair 5 "重新排队失败 / 执行中任务" 6 "取消未完成任务"
        print_menu_section "Token 与 PO0 定时创建"
        print_menu_pair 7 "任务 Token（显示/生成/重置）" 8 "安装 / 更新 PO0 定时创建"
        print_menu_pair 9 "查看 PO0 定时创建状态" 10 "删除 PO0 定时创建"
        print_menu_section "退出"
        print_menu_item 0 "返回"
        print_menu_footer
        read_menu_choice_or_return choice "请选择操作 [0-10]: " || return
        case "${choice}" in
            1)
                list_resource_tasks
                pause_before_return
                ;;
            2)
                create_resource_task "iplist"
                pause_before_return
                ;;
            3)
                create_resource_task "ipdb"
                pause_before_return
                ;;
            4)
                create_resource_task "iplist"
                create_resource_task "ipdb"
                pause_before_return
                ;;
            5)
                if confirm_yes "确认重新排队所有失败或执行中的任务"; then
                    retry_resource_tasks
                else
                    info "已取消重新排队。"
                fi
                pause_before_return
                ;;
            6)
                do_cancel_unfinished_resource_tasks_interactive
                pause_before_return
                ;;
            7)
                do_show_or_create_resource_task_token
                pause_before_return
                ;;
            8)
                do_install_resource_task_cron_interactive
                pause_before_return
                ;;
            9)
                do_show_resource_task_cron_status
                pause_before_return
                ;;
            10)
                if confirm_yes "确认删除 PO0 资源任务定时创建 cron"; then
                    remove_resource_task_cron
                else
                    info "已取消删除 PO0 定时创建。"
                fi
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

do_import_iplist_package() {
    local path
    print_title "导入 / 刷新 iplist 离线包"
    ensure_layout || return
    load_settings 1
    path="$(prompt_with_default "请输入 iplist 离线包路径" "/root/iplist.tar.gz")"
    path="$(trim "${path}")"
    import_iplist_package "${path}" || {
        pause_before_return
        return
    }
    if src_allowlist_enabled; then
        build_src_allowlist_cache || {
            pause_before_return
            return
        }
        backup_managed_files
        write_nft_conf || {
            pause_before_return
            return
        }
        apply_or_save_notice "iplist 已刷新并应用。" "iplist 已刷新，托管配置已更新。"
    fi
    pause_before_return
}

do_manage_src_allowlist() {
    local choice
    ensure_layout || return
    load_settings 1
    while true; do
        menu_clear_screen
        print_title "管理源 IP 白名单"
        print_src_allowlist_details
        print_menu_section "查看与确认"
        print_menu_pair 1 "字段说明" 2 "来源 / IP 明细"
        print_menu_item 3 "最终生效 CIDR 缓存"
        print_menu_section "策略与手动来源"
        print_menu_pair 4 "设置源 IP 限制方式" 5 "管理地区白名单"
        print_menu_pair 6 "管理手动 CIDR" 7 "当前 SSH 临时放行"
        print_menu_section "动态来源与客户端"
        print_menu_pair 8 "动态来源开关" 9 "管理 DDNS 来源"
        print_menu_pair 10 "Client IP / Self-report Token" 11 "Egern / SSH report Token"
        print_menu_pair 12 "WebAuth 上报 Token" 13 "专用受限 SSH 上报 key"
        print_menu_item 14 "自动来源安全模式 / pending IP"
        print_menu_section "自动学习、清理与排障"
        print_menu_pair 15 "动态来源缓存维护" 16 "来源 IP 学习与候选提升"
        print_menu_item 17 "被阻挡访问日志"
        print_menu_section "数据与资源"
        print_menu_pair 18 "IPDB 数据与解析" 19 "导入 / 刷新 iplist 离线包"
        print_menu_pair 20 "重建并应用白名单" 21 "管理白名单配置档案"
        print_menu_item 22 "管理内网资源更新任务"
        print_menu_section "退出"
        print_menu_item 0 "返回"
        print_menu_footer
        read_menu_choice_or_return choice "请选择操作 [0-22]: " || return
        case "${choice}" in
            1)
                do_explain_src_allowlist_fields
                pause_before_return
                ;;
            2)
                do_show_allowlist_source_entries
                pause_before_return
                ;;
            3)
                do_show_src_allowlist_cache
                pause_before_return
                ;;
            4)
                save_allowlist_last_snapshot || {
                    pause_before_return
                    continue
                }
                prompt_src_allowlist_mode || {
                    pause_before_return
                    continue
                }
                apply_src_allowlist_changes
                pause_before_return
                ;;
            5)
                do_manage_region_allowlist
                ;;
            6)
                do_manage_custom_allowlist
                ;;
            7)
                do_add_ssh_temp_allowlist_entry
                pause_before_return
                ;;
            8)
                do_manage_allowlist_source_switches
                pause_before_return
                ;;
            9)
                do_manage_ddns_allowlist_sources
                ;;
            10)
                do_show_client_ip_report_token
                pause_before_return
                ;;
            11)
                do_show_ssh_report_token
                pause_before_return
                ;;
            12)
                do_show_webauth_report_token
                pause_before_return
                ;;
            13)
                do_manage_report_keys
                ;;
            14)
                do_manage_automation_mode
                ;;
            15)
                do_manage_dynamic_allowlist_maintenance
                ;;
            16)
                do_manage_learning_allowlist
                ;;
            17)
                do_manage_blocked_log
                ;;
            18)
                do_manage_ipdb_tools
                ;;
            19)
                do_import_iplist_package
                pause_before_return
                ;;
            20)
                src_allowlist_enabled || {
                    err "白名单未开启，或当前模式没有可用 CIDR。"
                    pause_before_return
                    continue
                }
                apply_src_allowlist_changes
                pause_before_return
                ;;
            21)
                do_manage_allowlist_profiles
                ;;
            22)
                do_manage_resource_tasks
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
do_enable_bbr() {
    print_title "可选开启 BBR + fq"
    warn "纯 nftables 内核转发本身并不依赖 BBR，此项仅作可选优化。"
    confirm_yes "是否继续开启 BBR + fq" || {
        info "已取消。"
        return
    }
    enable_bbr_fq
}

print_recommended_operations() {
    print_panel_section "推荐操作"
    print_panel_action "首次部署" "安装/初始化 -> 新增或导入转发规则 -> 管理源 IP 白名单 -> 诊断/自检"
    print_panel_action "日常维护" "查看概览与规则列表；按需新增/编辑规则；管理源 IP 白名单"
    print_panel_action "白名单收紧" "管理源 IP 白名单 -> 来源 IP 学习与候选提升 -> 将学习到的单 IP 加入自定义白名单"
    print_panel_action "安全基线" "保持入站防火墙接管开启；SSH 端口会自动例外放行"
    echo ""
}

count_file_lines() {
    local file="$1"
    [[ -s "${file}" ]] || {
        printf '0\n'
        return 0
    }
    wc -l < "${file}" 2>/dev/null | tr -d '[:space:]'
}
