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

write_block_log_header() {
    local path="$1"
    cat > "${path}" <<'EOF'
# Managed by nftables relay manager
# format: observed_at|src_ip|proto|dport|set_id|raw|ipdb_snapshot
EOF
}

ensure_block_log_file() {
    mkdir -p "${CONF_DIR}" || return 1
    if [[ ! -f "${BLOCK_LOG_FILE}" ]]; then
        write_block_log_header "${BLOCK_LOG_FILE}"
    fi
}

write_block_summary_header() {
    local path="$1"
    cat > "${path}" <<'EOF'
# Managed by nftables relay manager
# format: src_ip|proto|dport|set_id|count|first_seen|last_seen
EOF
}

sanitize_block_log_text() {
    local value="$1"
    value="${value//$'\t'/ }"
    value="${value//$'\r'/ }"
    value="${value//$'\n'/ }"
    value="${value//|//}"
    value="$(trim "${value}")"
    [[ ${#value} -le 512 ]] || value="${value:0:512}"
    printf '%s\n' "${value}"
}

parse_block_log_line() {
    local line="$1"
    BLOCK_LOG_SRC_IP=""
    BLOCK_LOG_PROTO=""
    BLOCK_LOG_DPORT=""
    BLOCK_LOG_SET_ID="default"
    BLOCK_LOG_RAW="$(sanitize_block_log_text "${line}")"
    [[ "${line}" == *"po0-block "* ]] || return 1
    if [[ "${line}" =~ SRC=([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) ]]; then
        BLOCK_LOG_SRC_IP="${BASH_REMATCH[1]}"
    fi
    if [[ "${line}" =~ DPT=([0-9]+) ]]; then
        BLOCK_LOG_DPORT="${BASH_REMATCH[1]}"
    fi
    if [[ "${line}" =~ PROTO=([A-Za-z0-9]+) ]]; then
        BLOCK_LOG_PROTO="${BASH_REMATCH[1],,}"
    fi
    if [[ "${line}" =~ po0-block[[:space:]][^[:space:]]*set=([A-Za-z0-9._-]+) ]]; then
        BLOCK_LOG_SET_ID="${BASH_REMATCH[1]}"
    fi
    if [[ "${line}" =~ po0-block[[:space:]].*proto=([A-Za-z0-9]+) ]]; then
        BLOCK_LOG_PROTO="${BASH_REMATCH[1],,}"
    fi
    validate_host_ipv4 "${BLOCK_LOG_SRC_IP}" || return 1
    validate_port "${BLOCK_LOG_DPORT}" || return 1
    [[ "${BLOCK_LOG_PROTO}" == "tcp" || "${BLOCK_LOG_PROTO}" == "udp" ]] || return 1
}

read_block_log_lines() {
    local since="${1:-1 hour ago}"
    if command -v journalctl &>/dev/null; then
        journalctl -k --no-pager --since "${since}" 2>/dev/null | grep -F 'po0-block ' || true
    elif command -v dmesg &>/dev/null; then
        dmesg 2>/dev/null | grep -F 'po0-block ' || true
    fi
}

collect_blocked_ip_logs() {
    local since="${1:-1 hour ago}"
    local line observed_at snapshot added=0 skipped=0
    ensure_block_log_file || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_block_log_line "${line}" || {
            ((skipped++))
            continue
        }
        if grep -Fq "|${BLOCK_LOG_RAW}" "${BLOCK_LOG_FILE}" 2>/dev/null; then
            ((skipped++))
            continue
        fi
        observed_at="$(utc_now_iso)"
        snapshot="$(ipdb_snapshot_for_ip "${BLOCK_LOG_SRC_IP}")"
        snapshot="$(sanitize_block_log_text "${snapshot}")"
        printf '%s|%s|%s|%s|%s|%s|%s\n' \
            "${observed_at}" \
            "${BLOCK_LOG_SRC_IP}" \
            "${BLOCK_LOG_PROTO}" \
            "${BLOCK_LOG_DPORT}" \
            "${BLOCK_LOG_SET_ID}" \
            "${BLOCK_LOG_RAW}" \
            "${snapshot}" >> "${BLOCK_LOG_FILE}"
        ((added++))
    done < <(read_block_log_lines "${since}")
    BLOCK_LOG_ADDED_COUNT="${added}"
    BLOCK_LOG_SKIPPED_COUNT="${skipped}"
    compact_block_log_if_needed "collect" || return 1
}

block_log_count() {
    local line count=0
    [[ -f "${BLOCK_LOG_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="$(trim "${line}")"
        [[ -n "${line}" && ! "${line}" =~ ^# ]] || continue
        ((count++))
    done < "${BLOCK_LOG_FILE}"
    printf '%s\n' "${count}"
}

block_log_line_count() {
    [[ -f "${BLOCK_LOG_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    wc -l < "${BLOCK_LOG_FILE}" 2>/dev/null | tr -d '[:space:]'
}

block_log_size_bytes() {
    [[ -f "${BLOCK_LOG_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    wc -c < "${BLOCK_LOG_FILE}" 2>/dev/null | tr -d '[:space:]'
}

block_summary_count() {
    [[ -f "${BLOCK_SUMMARY_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    awk -F '|' 'NF >= 7 && $1 !~ /^#/ { count++ } END { print count + 0 }' "${BLOCK_SUMMARY_FILE}" 2>/dev/null
}

regenerate_block_summary() {
    local tmp
    ensure_block_log_file || return 1
    make_temp_file "${BLOCK_SUMMARY_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    write_block_summary_header "${tmp}"
    awk -F '|' '
        NF >= 6 && $1 !~ /^#/ {
            key = $2 "|" $3 "|" $4 "|" $5
            count[key]++
            if (!(key in first) || $1 < first[key]) first[key] = $1
            if (!(key in last) || $1 > last[key]) last[key] = $1
        }
        END {
            for (key in count) {
                print key "|" count[key] "|" first[key] "|" last[key]
            }
        }
    ' "${BLOCK_LOG_FILE}" | sort -t '|' -k5,5nr -k1,1 >> "${tmp}"
    mv -f "${tmp}" "${BLOCK_SUMMARY_FILE}"
}

compact_block_log_if_needed() {
    local reason="${1:-auto}"
    local size total data_lines overflow tmp
    ensure_block_log_file || return 1
    size="$(block_log_size_bytes)"
    total="$(block_log_line_count)"
    [[ "${size}" =~ ^[0-9]+$ ]] || size=0
    [[ "${total}" =~ ^[0-9]+$ ]] || total=0
    data_lines="$(block_log_count)"
    [[ "${data_lines}" =~ ^[0-9]+$ ]] || data_lines=0
    overflow=0
    if (( data_lines > BLOCK_LOG_KEEP_LINES )); then
        overflow=$((data_lines - BLOCK_LOG_KEEP_LINES))
    elif (( size > BLOCK_LOG_MAX_BYTES )); then
        overflow=$((data_lines / 2))
    fi
    if (( overflow > 0 )); then
        make_temp_file "${BLOCK_LOG_FILE}.compact" || return 1
        tmp="${TEMP_FILE_RESULT}"
        write_block_log_header "${tmp}"
        awk -F '|' -v overflow="${overflow}" '
            $1 ~ /^#/ { next }
            {
                data_seen++
                if (data_seen <= overflow) next
                print
            }
        ' "${BLOCK_LOG_FILE}" >> "${tmp}"
        mv -f "${tmp}" "${BLOCK_LOG_FILE}"
    fi
    regenerate_block_summary || return 1
}

do_render() {
    local render_dir render_conf render_cache
    make_temp_dir "${TMPDIR:-/tmp}" "po0-relay-render" || return 1
    render_dir="${TEMP_DIR_RESULT}"
    render_conf="${render_dir}/po0-relay.conf"
    render_cache="${render_dir}/po0-relay-src-allowlist.txt"
    write_nft_conf "${render_conf}" "${render_cache}" || return 1
    cat "${render_conf}"
}

script_changelog_lines() {
    local file="${1:-}"
    local line in_block=0 found=0
    [[ -r "${file}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" == "# CHANGELOG_BEGIN" ]]; then
            in_block=1
            continue
        fi
        if [[ "${line}" == "# CHANGELOG_END" ]]; then
            break
        fi
        [[ "${in_block}" == "1" ]] || continue
        line="${line#\# }"
        line="${line#\#}"
        line="$(trim "${line}")"
        [[ -n "${line}" ]] || continue
        found=1
        printf '%s\n' "${line}"
    done < "${file}"
    [[ "${found}" == "1" ]]
}

script_file_var() {
    local file="$1"
    local name="$2"
    local line value
    [[ -r "${file}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ "${line}" == "${name}="* ]] || continue
        value="${line#*=}"
        value="${value%\"}"
        value="${value#\"}"
        printf '%s\n' "${value}"
        return 0
    done < "${file}"
    return 1
}

sha256_file_full() {
    local file="$1"
    command -v sha256sum >/dev/null 2>&1 || return 1
    sha256sum "${file}" 2>/dev/null | awk '{ print $1 }'
}

sha256_string() {
    local value="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "${value}" | sha256sum | awk '{ print $1 }'
    elif command -v openssl >/dev/null 2>&1; then
        printf '%s' "${value}" | openssl dgst -sha256 2>/dev/null | awk '{ print $NF }'
    else
        return 1
    fi
}

hmac_sha256_hex() {
    local key="$1"
    local message="$2"
    local py
    if command -v openssl >/dev/null 2>&1; then
        printf '%s' "${message}" | openssl dgst -sha256 -hmac "${key}" 2>/dev/null | awk '{ print $NF }'
        return 0
    fi
    if command -v python3 >/dev/null 2>&1; then
        py="python3"
    elif command -v python >/dev/null 2>&1; then
        py="python"
    else
        return 1
    fi
    HMAC_KEY="${key}" HMAC_MESSAGE="${message}" "${py}" - <<'PY'
import hashlib
import hmac
import os
print(hmac.new(os.environ["HMAC_KEY"].encode(), os.environ["HMAC_MESSAGE"].encode(), hashlib.sha256).hexdigest())
PY
}

random_update_nonce() {
    local nonce
    if command -v openssl >/dev/null 2>&1; then
        nonce="$(openssl rand -hex 16 2>/dev/null || true)"
    fi
    if [[ -z "${nonce:-}" && -r /dev/urandom ]]; then
        nonce="$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
    fi
    [[ -n "${nonce:-}" ]] || nonce="$(date -u '+%Y%m%dT%H%M%SZ')-$RANDOM"
    printf '%s\n' "${nonce}"
}

normalize_manager_update_url() {
    local url="$1"
    url="$(trim "${url}")"
    [[ -n "${url}" ]] || return 1
    case "${url}" in
        http://*|https://*) ;;
        *) url="http://${url}" ;;
    esac
    case "${url}" in
        http://*) ;;
        https://*)
            err "PO0 到 LAN Worker 的 manager 更新入口必须使用 HTTP，不允许 HTTPS：${url}"
            return 1
            ;;
        *)
            err "manager 更新 URL 必须使用 http://"
            return 1
            ;;
    esac
    case "${url}" in
        *\?*)
            err "manager 更新 URL 不需要查询参数；脚本会自动追加 nonce 和 token_id。"
            return 1
            ;;
    esac
    case "${url}" in
        */po0-manager-update/nftables-relay-manager.sh)
            ;;
        */)
            url="${url}po0-manager-update/nftables-relay-manager.sh"
            ;;
        *)
            url="${url}/po0-manager-update/nftables-relay-manager.sh"
            ;;
    esac
    printf '%s\n' "${url}"
}
