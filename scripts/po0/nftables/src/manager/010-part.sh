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

ensure_iplist_ready() {
    iplist_ready && return 0
    err "尚未导入 iplist 离线包，请先使用菜单导入 iplist.tar.gz。"
    return 1
}

region_id_is_selected() {
    local needle="$1"
    local id
    for id in ${SRC_ALLOWLIST_REGION_IDS}; do
        [[ "${id}" == "${needle}" ]] && return 0
    done
    return 1
}

add_allowlist_region_id() {
    local id="$1"
    [[ -n "$(iplist_region_record "${id}" || true)" ]] || return 1
    region_id_is_selected "${id}" && return 0
    SRC_ALLOWLIST_REGION_IDS="$(normalize_region_ids "${SRC_ALLOWLIST_REGION_IDS} ${id}")"
}

remove_allowlist_region_id() {
    local target="$1"
    local id out=""
    for id in ${SRC_ALLOWLIST_REGION_IDS}; do
        [[ "${id}" == "${target}" ]] && continue
        if [[ -z "${out}" ]]; then
            out="${id}"
        else
            out+=" ${id}"
        fi
    done
    SRC_ALLOWLIST_REGION_IDS="${out}"
}

show_selected_allowlist_regions() {
    local id
    if [[ -z "${SRC_ALLOWLIST_REGION_IDS}" ]]; then
        echo "  (未选择地区)"
        return 0
    fi
    for id in ${SRC_ALLOWLIST_REGION_IDS}; do
        printf '  - %s\n' "$(iplist_region_label "${id}")"
    done
}

allowlist_pending_count() {
    if [[ -s "${AUTO_PENDING_FILE}" ]]; then
        awk -F '|' 'NF >= 7 && $1 !~ /^#/ && $7 == "pending" { c++ } END { print c + 0 }' "${AUTO_PENDING_FILE}" 2>/dev/null
    else
        printf '0\n'
    fi
}

allowlist_cache_count() {
    if [[ -s "${SRC_ALLOWLIST_CACHE}" ]]; then
        wc -l < "${SRC_ALLOWLIST_CACHE}" 2>/dev/null | tr -d '[:space:]' || printf '0'
    else
        printf '0\n'
    fi
}

show_allowlist_entry_table() {
    local line idx=1 status allowed expires value note source_label
    if [[ ! -f "${ALLOWLIST_ENTRIES_FILE}" ]] || [[ "$(allowlist_entries_count)" == "0" ]]; then
        echo "  (暂无手动/动态来源条目)"
        return 0
    fi
    printf '  %3s  %-18s %-10s %-8s %-12s %-18s %-20s %s\n' "#" "CIDR" "来源" "状态" "参与当前模式" "来源 key" "过期时间" "备注"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_entry_line "${line}" || continue
        if allowlist_entry_is_expired "${ALLOWLIST_ENTRY_EXPIRES_AT}"; then
            status="过期"
        else
            status="生效"
        fi
        if source_type_allowed_by_mode "${ALLOWLIST_ENTRY_SOURCE_TYPE}" "${SRC_ALLOWLIST_MODE}"; then
            allowed="是"
        else
            allowed="否"
        fi
        source_label="$(allowlist_source_type_label "${ALLOWLIST_ENTRY_SOURCE_TYPE}")"
        value="${ALLOWLIST_ENTRY_SOURCE_VALUE:-"-"}"
        expires="${ALLOWLIST_ENTRY_EXPIRES_AT:-"-"}"
        note="${ALLOWLIST_ENTRY_NOTE:-"-"}"
        printf '  %3d  %-18s %-10s %-8s %-12s %-18s %-20s %s\n' \
            "${idx}" "${ALLOWLIST_ENTRY_CIDR}" "${source_label}" "${status}" "${allowed}" "${value}" "${expires}" "${note}"
        ((idx++))
    done < "${ALLOWLIST_ENTRIES_FILE}"
}

show_dynamic_allowlist_source_usage() {
    local line key source_type source_value limit count
    declare -A counts=()
    local -a rows=()
    ensure_allowlist_entries_file || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_entry_line "${line}" || continue
        dynamic_allowlist_source_type "${ALLOWLIST_ENTRY_SOURCE_TYPE}" || continue
        allowlist_entry_is_expired "${ALLOWLIST_ENTRY_EXPIRES_AT}" && continue
        key="${ALLOWLIST_ENTRY_SOURCE_TYPE}|${ALLOWLIST_ENTRY_SOURCE_VALUE}"
        counts["${key}"]=$(( ${counts["${key}"]:-0} + 1 ))
    done < "${ALLOWLIST_ENTRIES_FILE}"

    print_panel_section "动态来源用量"
    printf '  %-12s %-28s %s\n' "来源类型" "source-id" "有效条目"
    for key in "${!counts[@]}"; do
        IFS='|' read -r source_type source_value <<< "${key}"
        limit="$(dynamic_allowlist_max_per_source "${source_type}")"
        count="${counts["${key}"]:-0}"
        rows+=("$(printf '  %-12s %-28s %s/%s' "${source_type}" "${source_value:-"-"}" "${count}" "${limit}")")
    done
    if [[ "${#rows[@]}" -eq 0 ]]; then
        printf '  %s\n' "暂无未过期动态来源条目"
    else
        printf '%s\n' "${rows[@]}" | sort
    fi
}

do_show_allowlist_source_entries() {
    ensure_layout || return 1
    load_settings 1
    print_title "白名单来源 / IP 明细"
    print_panel_section "当前配置"
    print_panel_row "当前模式" "$(src_allowlist_mode_to_label "${SRC_ALLOWLIST_MODE}")"
    print_panel_row "允许来源" "$(allowlist_sources_label "$(src_allowlist_mode_default_sources "${SRC_ALLOWLIST_MODE}")")"
    print_panel_row "安全模式" "$([[ "${AUTOMATION_MODE}" == "attack" ]] && printf 'attack（新自动 IP 进入待审核）' || printf 'regular（新自动 IP 直接生效）')"
    print_panel_row "entries 文件" "${ALLOWLIST_ENTRIES_FILE}"
    print_panel_note "手动 CIDR、SSH 临时、DDNS、Client IP、SSH report、WebAuth、学习提升等条目显示在下方"
    print_panel_note "地区库的海量 CIDR 不逐条存在 entries 文件，最终展开结果看“最终 CIDR 缓存”"
    show_dynamic_allowlist_source_usage
    show_allowlist_entry_table
}

do_show_src_allowlist_cache() {
    local total limit="${1:-200}"
    ensure_layout || return 1
    print_title "最终生效 CIDR 缓存"
    if [[ ! -s "${SRC_ALLOWLIST_CACHE}" ]]; then
        echo "白名单缓存尚未生成。可先执行“重建并应用白名单”。"
        printf '缓存路径: %s\n' "${SRC_ALLOWLIST_CACHE}"
        return 0
    fi
    total="$(allowlist_cache_count)"
    printf '缓存路径 : %s\n' "${SRC_ALLOWLIST_CACHE}"
    printf 'CIDR 数量: %s\n' "${total}"
    echo ""
    if [[ "${total}" =~ ^[0-9]+$ ]] && (( total > limit )); then
        printf '仅显示前 %s 条；完整内容请在服务器上查看该文件。\n' "${limit}"
    fi
    sed -n "1,${limit}p" "${SRC_ALLOWLIST_CACHE}" | sed 's/^/  /'
}

do_explain_src_allowlist_fields() {
    print_title "白名单字段说明"
    cat <<EOF
白名单缓存
  最终写入 nftables 的 CIDR 列表，路径：${SRC_ALLOWLIST_CACHE}
  它由地区库 + 手动 CIDR + 动态来源条目合并生成。

自定义 CIDR
  手工维护的静态白名单，路径：${CUSTOM_SRC_ALLOWLIST_FILE}
  适合放你明确确认过的固定公网 IP 或网段。它不是全部白名单。

entries
  手动、SSH 临时、DDNS、Client IP、SSH report、WebAuth、learned 等条目的统一记录表：
  ${ALLOWLIST_ENTRIES_FILE}

允许来源
  当前白名单模式会采用哪些 source_type。比如 trusted_dynamic 会采用：
  manual、ddns、client_ip、ssh_report、webauth、learned。ssh_temp 只在手动开启时参与。

待审核 IP
  attack 模式下，新的 DDNS / Client IP / SSH report / WebAuth 等自动来源不会直接放行，
  而是进入待审核队列：${AUTO_PENDING_FILE}

地区库
  来自离线 iplist 包。菜单中选择“杭州市”等地区后，最终展开进白名单缓存。
EOF
}

print_src_allowlist_details() {
    local cache_count custom_count
    print_panel_section "白名单数据"
    if iplist_ready; then
        print_panel_row "iplist 数据" "已导入（${IPLIST_DIR}）"
    else
        print_panel_row "iplist 数据" "未导入"
    fi

    if [[ -s "${SRC_ALLOWLIST_CACHE}" ]]; then
        cache_count="$(wc -l < "${SRC_ALLOWLIST_CACHE}" 2>/dev/null | tr -d '[:space:]' || true)"
        print_panel_row "白名单缓存" "已生成（${cache_count:-0} 条 CIDR，${SRC_ALLOWLIST_CACHE}）"
    else
        print_panel_row "白名单缓存" "未生成"
    fi

    custom_count="$(custom_allowlist_count)"
    if src_allowlist_enabled; then
        print_panel_row "白名单状态" "开启（$(src_allowlist_mode_to_label "${SRC_ALLOWLIST_MODE}")）"
    elif [[ "${ENABLE_SRC_ALLOWLIST}" == "1" ]]; then
        print_panel_row "白名单状态" "配置不完整（$(src_allowlist_mode_to_label "${SRC_ALLOWLIST_MODE}")）"
    else
        print_panel_row "白名单状态" "关闭"
    fi
    print_panel_row "自动白名单" "$([[ "${AUTOMATION_MODE}" == "attack" ]] && printf 'attack（新自动 IP 进入待审核）' || printf 'regular')"
    print_panel_row "允许来源" "$(allowlist_sources_label "$(src_allowlist_mode_default_sources "${SRC_ALLOWLIST_MODE}")")"
    print_panel_row "来源条目" "$(allowlist_entries_count) 条（${ALLOWLIST_ENTRIES_FILE}）"
    print_panel_row "动态缓存" "$(dynamic_allowlist_limits_label)；过期条目不进入最终缓存"
    print_panel_row "待审核 IP" "$(allowlist_pending_count) 条（${AUTO_PENDING_FILE}）"
    print_panel_row "地区数量" "$(src_allowlist_region_count)"
    print_panel_row "手动 CIDR" "${custom_count} 条（${CUSTOM_SRC_ALLOWLIST_FILE}）"
    print_panel_row "阻挡日志" "$(block_log_count) 条，$(format_bytes "$(block_log_size_bytes)")；summary $(block_summary_count) 行"
    print_panel_row "学习服务" "$(learning_service_status_label)"
    print_panel_row "IPDB 数据" "$(ipdb_status_label)"
    print_panel_section "白名单地区"
    show_selected_allowlist_regions
    print_panel_section "手动 CIDR"
    show_custom_allowlist_entries
}

build_src_allowlist_cache() {
    local output="${1:-${SRC_ALLOWLIST_CACHE}}"
    local id record name rel url line tmp count=0 custom_added=0 entries_added=0
    make_temp_file "${output}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    : > "${tmp}"

    if src_allowlist_mode_uses_region; then
        if [[ -n "${SRC_ALLOWLIST_REGION_IDS}" ]]; then
            ensure_iplist_ready || return 1
            for id in ${SRC_ALLOWLIST_REGION_IDS}; do
                record="$(iplist_region_record "${id}" || true)"
                [[ -n "${record}" ]] || {
                    err "地区 ${id} 不存在于当前 iplist。"
                    return 1
                }
                IFS=$'\t' read -r _ name rel url <<< "${record}"
                [[ -f "${IPLIST_DIR}/${rel}" ]] || {
                    err "地区 ${name} 缺少数据文件：${rel}"
                    return 1
                }
                while IFS= read -r line || [[ -n "${line}" ]]; do
                    line="${line%$'\r'}"
                    line="$(trim "${line}")"
                    [[ -z "${line}" || "${line}" =~ ^# ]] && continue
                    validate_ipv4_cidr "${line}" || {
                        err "地区 ${name} 存在无效 CIDR：${line}"
                        return 1
                    }
                    printf '%s\n' "${line}" >> "${tmp}"
                    ((count++))
                done < "${IPLIST_DIR}/${rel}"
            done
        elif [[ "${SRC_ALLOWLIST_MODE}" == "region_only" ]]; then
            err "仅地区库模式未选择任何地区。"
            return 1
        fi
    fi

    if src_allowlist_mode_uses_custom; then
        entries_added="$(append_allowlist_entries_to_cache "default" "${tmp}")" || return 1
        if [[ "${entries_added}" =~ ^[0-9]+$ && "${entries_added}" -gt 0 ]]; then
            count=$((count + entries_added))
            custom_added=1
        fi
        if [[ -f "${CUSTOM_SRC_ALLOWLIST_FILE}" ]]; then
            while IFS= read -r line || [[ -n "${line}" ]]; do
                custom_allowlist_line_is_data "${line}" || continue
                parse_custom_allowlist_line "${line}" || {
                    err "自定义白名单存在无效 CIDR：${line}"
                    return 1
                }
                printf '%s\n' "${CUSTOM_ALLOWLIST_CIDR}" >> "${tmp}"
                ((count++))
                custom_added=1
            done < "${CUSTOM_SRC_ALLOWLIST_FILE}"
        fi
        if [[ "${SRC_ALLOWLIST_MODE}" != "region_plus_trusted" && "${SRC_ALLOWLIST_MODE}" != "region_only" && "${custom_added}" != "1" ]]; then
            err "$(src_allowlist_mode_to_label "${SRC_ALLOWLIST_MODE}") 没有任何可用 CIDR。"
            return 1
        fi
    fi

    [[ "${count}" -gt 0 ]] || {
        err "源 IP 白名单没有可用 CIDR。"
        return 1
    }
    sort -u "${tmp}" -o "${tmp}"
    mv -f "${tmp}" "${output}"
}

write_nft_allowlist_set() {
    local tmp="$1"
    local cache="${2:-${SRC_ALLOWLIST_CACHE}}"
    local line set_name
    [[ -s "${cache}" ]] || return 1
    set_name="$(default_allowlist_nft_set_name)"
    cat >> "${tmp}" <<EOF
    set ${set_name} {
        type ipv4_addr
        flags interval
        auto-merge
        elements = {
EOF
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="$(trim "${line}")"
        [[ -n "${line}" ]] || continue
        printf '            %s,\n' "${line}" >> "${tmp}"
    done < "${cache}"
    cat >> "${tmp}" <<'EOF'
        }
    }

EOF
}

enabled_rule_ports_set() {
    local want_proto="$1"
    local rule port out="" seen=" "
    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        [[ "${RULE_ENABLED}" == "1" ]] || continue
        case "${want_proto}:${RULE_PROTO}" in
            tcp:tcp|tcp:both|udp:udp|udp:both)
                port="${RULE_LPORT}"
                ;;
            *)
                continue
                ;;
        esac
        [[ "${seen}" == *" ${port} "* ]] && continue
        seen+="${port} "
        if [[ -z "${out}" ]]; then
            out="${port}"
        else
            out+=", ${port}"
        fi
    done
    printf '%s\n' "${out}"
}

enabled_rule_count() {
    local rule count=0
    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        [[ "${RULE_ENABLED}" == "1" ]] || continue
        ((count++))
    done
    printf '%s\n' "${count}"
}

relay_lan_snat_required() {
    local rule
    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        [[ "${RULE_ENABLED}" == "1" ]] || continue
        [[ "${RULE_SNAT_MODE}" == "relay_lan" ]] && return 0
    done
    return 1
}

apply_relay_mode_to_rules() {
    local idx rule snat_mode
    [[ "${RELAY_MODE}" == "mixed" ]] && return 0
    snat_mode="$(relay_mode_default_snat_mode)"
    for idx in "${!RULES[@]}"; do
        rule="${RULES[$idx]}"
        parse_rule "${rule}"
        RULES[$idx]="$(serialize_rule "${RULE_ID}" "${RULE_NAME}" "${RULE_PROTO}" "${RULE_LPORT}" "${RULE_DIP}" "${RULE_DPORT}" "${RULE_ENABLED}" "${snat_mode}")"
    done
}

validate_managed_listen_ports() {
    local rule
    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        [[ "${RULE_ENABLED}" == "1" ]] || continue
        ensure_listen_port_allowed "${RULE_LPORT}" "${RULE_PROTO}" || return 1
    done
}

get_unmanaged_runtime_dnat_summary() {
    local text=""
    local current_family=""
    local current_table=""
    local line parsed key lport dip dport tables
    local -A seen_rules=()
    local -A seen_tables=()

    command -v nft &>/dev/null || return 1
    text="$(nft list ruleset 2>/dev/null || true)"
    [[ -n "${text}" ]] || return 1

    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ ^table[[:space:]]+([[:alnum:]_]+)[[:space:]]+([^[:space:]]+)[[:space:]]*\{ ]]; then
            current_family="${BASH_REMATCH[1]}"
            current_table="${BASH_REMATCH[2]}"
            continue
        fi

        parsed="$(parse_rule_from_line "${line}" || true)"
        [[ -n "${parsed}" ]] || continue
        [[ "${current_family}" == "ip" || "${current_family}" == "inet" ]] || continue
        [[ "${current_table}" == "${NAT_TABLE}" ]] && continue

        IFS='|' read -r _ lport dip dport _ <<< "${parsed}"
        key="${current_table}|${lport}|${dip}|${dport}"
        seen_rules["${key}"]=1
        seen_tables["${current_table}"]=1
    done <<< "${text}"

    [[ ${#seen_rules[@]} -gt 0 ]] || return 1
    tables="$(join_with_comma "${!seen_tables[@]}")"
    printf '%s|%s\n' "${#seen_rules[@]}" "${tables}"
}

print_runtime_drift_hint() {
    local summary count tables
    summary="$(get_unmanaged_runtime_dnat_summary || true)"
    [[ -n "${summary}" ]] || return 0
    IFS='|' read -r count tables <<< "${summary}"
    warn "发现 ${count} 条脚本未管理的 DNAT 转发规则：它们正在系统里生效，但不在本脚本的规则列表中。"
    [[ -n "${tables}" ]] && info "所在 nft 表：${tables}"
    info "常见原因：旧脚本、手动 nft 命令、其它面板或防火墙工具留下了转发规则。"
    info "处理方式：想保留就可以先不管；想交给本脚本管理，用 [9] 导入当前 nft 运行时规则；确认不要了，再用 [1] 初始化接管或手动删除对应表。"
}

public_ip_source_label() {
    case "${PUBLIC_IP_SOURCE}" in
        system)
            printf '已缓存（本机路由或网卡）'
            ;;
        online)
            printf '已缓存（公网服务查询）'
            ;;
        manual)
            printf '手动设置'
            ;;
        settings)
            printf '已缓存配置'
            ;;
        *)
            printf '未探测到'
            ;;
    esac
}

refresh_relay_lan_ip() {
    RELAY_LAN_IP="$(detect_relay_ip_from_system 2>/dev/null || true)"
    if validate_host_ipv4 "${RELAY_LAN_IP}"; then
        RELAY_LAN_IP_SOURCE="auto"
        return 0
    fi
    RELAY_LAN_IP=""
    RELAY_LAN_IP_SOURCE="none"
    return 1
}
