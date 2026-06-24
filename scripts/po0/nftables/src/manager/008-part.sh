learned_ip_candidates() {
    [[ -s "${LEARN_LOG_FILE}" ]] || return 0
    awk -F '\t' '
        NF >= 10 {
            ip = $3
            count[ip]++
            if (!(ip in first_epoch) || $1 < first_epoch[ip]) {
                first_epoch[ip] = $1
                first_iso[ip] = $2
            }
            if (!(ip in last_epoch) || $1 > last_epoch[ip]) {
                last_epoch[ip] = $1
                last_iso[ip] = $2
            }
            key = $4 "/" $5
            if (ports[ip] == "") {
                ports[ip] = key
            } else if (index("," ports[ip] ",", "," key ",") == 0) {
                ports[ip] = ports[ip] "," key
            }
        }
        END {
            for (ip in count) {
                span = last_epoch[ip] - first_epoch[ip]
                print ip "\t" count[ip] "\t" span "\t" first_iso[ip] "\t" last_iso[ip] "\t" ports[ip]
            }
        }
    ' "${LEARN_LOG_FILE}" | sort -t "$(printf '\t')" -k2,2nr -k5,5r
}

qualified_learned_ip_candidates() {
    learned_ip_candidates | awk -F '\t' \
        -v min_hits="${LEARN_IP_MIN_HITS}" \
        -v min_span="${LEARN_IP_MIN_SPAN_SECONDS}" \
        '($2 >= min_hits) || ($2 >= 2 && $3 >= min_span)'
}

learned_cidr24_candidates() {
    [[ -s "${LEARN_LOG_FILE}" ]] || return 0
    awk -F '\t' '
        NF >= 10 {
            split($3, o, ".")
            net = o[1] "." o[2] "." o[3] ".0/24"
            total[net]++
            if (!seen[net SUBSEP $3]++) unique[net]++
            if (!(net in first_epoch) || $1 < first_epoch[net]) {
                first_epoch[net] = $1
                first_iso[net] = $2
            }
            if (!(net in last_epoch) || $1 > last_epoch[net]) {
                last_epoch[net] = $1
                last_iso[net] = $2
            }
        }
        END {
            for (net in total) {
                if (unique[net] >= 2 || total[net] >= 3) {
                    span = last_epoch[net] - first_epoch[net]
                    print net "\t" unique[net] "\t" total[net] "\t" span "\t" first_iso[net] "\t" last_iso[net]
                }
            }
        }
    ' "${LEARN_LOG_FILE}" | sort -t "$(printf '\t')" -k2,2nr -k3,3nr -k6,6r
}

qualified_learned_cidr24_candidates() {
    learned_cidr24_candidates | awk -F '\t' \
        -v min_hits="${LEARN_NET24_MIN_HITS}" \
        -v min_unique="${LEARN_NET24_MIN_UNIQUE_IPS}" \
        '($2 >= min_unique) || ($3 >= min_hits)'
}

learned_cidr16_candidates() {
    [[ -s "${LEARN_LOG_FILE}" ]] || return 0
    awk -F '\t' '
        NF >= 10 {
            split($3, o, ".")
            net = o[1] "." o[2] ".0.0/16"
            net24 = o[1] "." o[2] "." o[3] ".0/24"
            total[net]++
            if (!seen_ip[net SUBSEP $3]++) unique_ip[net]++
            if (!seen_net24[net SUBSEP net24]++) unique_24[net]++
            if (!(net in first_epoch) || $1 < first_epoch[net]) {
                first_epoch[net] = $1
                first_iso[net] = $2
            }
            if (!(net in last_epoch) || $1 > last_epoch[net]) {
                last_epoch[net] = $1
                last_iso[net] = $2
            }
        }
        END {
            for (net in total) {
                span = last_epoch[net] - first_epoch[net]
                print net "\t" unique_ip[net] "\t" unique_24[net] "\t" total[net] "\t" span "\t" first_iso[net] "\t" last_iso[net]
            }
        }
    ' "${LEARN_LOG_FILE}" | sort -t "$(printf '\t')" -k3,3nr -k2,2nr -k4,4nr -k7,7r
}

qualified_learned_cidr16_candidates() {
    learned_cidr16_candidates | awk -F '\t' \
        -v min_hits="${LEARN_NET16_MIN_HITS}" \
        -v min_unique_24="${LEARN_NET16_MIN_UNIQUE_24S}" \
        '($3 >= min_unique_24) || ($4 >= min_hits)'
}

print_learning_daily_summary() {
    local row idx=1
    local day events first last unique_ips unique_24s unique_16s top_ips top_24s top_16s updated
    local -a rows=()
    [[ -s "${LEARN_SUMMARY_FILE}" ]] || return 0
    mapfile -t rows < <(awk -F '\t' 'NF >= 11 && $1 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ { print }' "${LEARN_SUMMARY_FILE}" | tail -n 7)
    [[ ${#rows[@]} -gt 0 ]] || return 0
    echo ""
    echo "每日历史汇总（最近 7 天）："
    for row in "${rows[@]}"; do
        IFS=$'\t' read -r day events first last unique_ips unique_24s unique_16s top_ips top_24s top_16s updated <<< "${row}"
        printf '  [%d] %s | 归档 %s 条 | 来源 IP %s 个 | /24 %s 个 | /16 %s 个\n' \
            "${idx}" "${day}" "${events}" "${unique_ips}" "${unique_24s}" "${unique_16s}"
        printf '      事件时间: %s -> %s\n' "$(format_learn_time "${first}")" "$(format_learn_time "${last}")"
        [[ -n "${top_ips}" ]] && printf '      Top IP: %s\n' "${top_ips}"
        [[ -n "${top_24s}" ]] && printf '      Top /24: %s\n' "${top_24s}"
        ((idx++))
    done
}

print_learning_stats() {
    local row idx=1
    local ipdb_ready=0 ip_info
    local -a rows=()
    ipdb_lookup_ready && ipdb_ready=1
    printf '学习日志   : %s（%s 条事件，%s）\n' \
        "${LEARN_LOG_FILE}" "$(learning_log_count)" "$(format_bytes "$(learning_log_size_bytes)")"
    printf '每日汇总   : %s（%s 天）\n' "${LEARN_SUMMARY_FILE}" "$(learning_summary_count)"
    printf '自动压缩   : 跨 UTC 日期归档；或超过 %s / %s 行时保留最近 %s 行；每 %s 条做一次大小兜底检查\n' \
        "$(format_bytes "${LEARN_LOG_MAX_BYTES}")" "${LEARN_LOG_KEEP_LINES}" "${LEARN_LOG_KEEP_LINES}" \
        "${LEARN_COMPACT_CHECK_INTERVAL}"
    printf 'IPDB 数据  : %s\n' "$(ipdb_status_label)"
    if [[ ! -s "${LEARN_LOG_FILE}" ]]; then
        echo "  (暂无学习记录)"
        print_learning_daily_summary
        return 0
    fi
    echo ""
    echo "来源 IP 统计："
    mapfile -t rows < <(learned_ip_candidates | head -n 30)
    if [[ ${#rows[@]} -eq 0 ]]; then
        echo "  (暂无可用来源 IP)"
    else
        for row in "${rows[@]}"; do
            IFS=$'\t' read -r SELECTED_LEARN_CIDR count span first last ports <<< "${row}"
            ip_info="$(ipdb_lookup_ip "${SELECTED_LEARN_CIDR}" "${ipdb_ready}")"
            printf '  [%d] %s | 命中 %s 次 | 观察 %s | %s\n' \
                "${idx}" "${SELECTED_LEARN_CIDR}" "${count}" "$(format_seconds "${span}")" "${ip_info}"
            printf '      时间: %s -> %s | 中转机监听端口: %s\n' \
                "$(format_learn_time "${first}")" "$(format_learn_time "${last}")" "${ports}"
            ((idx++))
        done
    fi

    echo ""
    echo "/24 候选网段："
    idx=1
    mapfile -t rows < <(learned_cidr24_candidates | head -n 20)
    if [[ ${#rows[@]} -eq 0 ]]; then
        echo "  (暂无 /24 候选)"
    else
        for row in "${rows[@]}"; do
            IFS=$'\t' read -r cidr unique total span first last <<< "${row}"
            printf '  [%d] %s | 来源 IP %s 个 | 命中 %s 次 | 观察 %s\n' \
                "${idx}" "${cidr}" "${unique}" "${total}" "$(format_seconds "${span}")"
            printf '      时间: %s -> %s\n' "$(format_learn_time "${first}")" "$(format_learn_time "${last}")"
            ((idx++))
        done
    fi

    echo ""
    echo "/16 候选网段（高风险）："
    idx=1
    mapfile -t rows < <(learned_cidr16_candidates | head -n 20)
    if [[ ${#rows[@]} -eq 0 ]]; then
        echo "  (暂无 /16 候选)"
    else
        for row in "${rows[@]}"; do
            IFS=$'\t' read -r cidr unique unique24 total span first last <<< "${row}"
            printf '  [%d] %s | 来源 IP %s 个 | 覆盖 /24 %s 个 | 命中 %s 次 | 观察 %s\n' \
                "${idx}" "${cidr}" "${unique}" "${unique24}" "${total}" "$(format_seconds "${span}")"
            printf '      时间: %s -> %s\n' "$(format_learn_time "${first}")" "$(format_learn_time "${last}")"
            ((idx++))
        done
    fi
    print_learning_daily_summary
}

select_learned_ip_candidate() {
    local choice row ip count span first last ports
    local ipdb_ready=0 ip_info
    local -a rows=()
    SELECTED_LEARN_CIDR=""
    SELECTED_LEARN_NOTE=""
    ipdb_lookup_ready && ipdb_ready=1
    mapfile -t rows < <(qualified_learned_ip_candidates | head -n 50)
    [[ ${#rows[@]} -gt 0 ]] || {
        err "暂无达到门槛的学习 IP（至少 ${LEARN_IP_MIN_HITS} 次，或 2 次且跨度 >= $(format_seconds "${LEARN_IP_MIN_SPAN_SECONDS}")）。"
        return 1
    }
    local idx=1
    for row in "${rows[@]}"; do
        IFS=$'\t' read -r ip count span first last ports <<< "${row}"
        ip_info="$(ipdb_lookup_ip "${ip}" "${ipdb_ready}")"
        printf '  [%d] %s | 命中 %s 次 | 观察 %s | %s\n' \
            "${idx}" "${ip}" "${count}" "$(format_seconds "${span}")" "${ip_info}"
        printf '      最近: %s | 中转机监听端口: %s\n' "$(format_learn_time "${last}")" "${ports}"
        ((idx++))
    done
    choice="$(read_prompt "请选择要加入自定义白名单的 IP [1-${#rows[@]}]: ")" || return 1
    [[ "${choice}" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= ${#rows[@]} )) || return 1
    IFS=$'\t' read -r ip count span first last ports <<< "${rows[$((choice - 1))]}"
    SELECTED_LEARN_CIDR="${ip}/32"
    SELECTED_LEARN_NOTE="learned hits=${count}, span=$(format_seconds "${span}"), last=${last}, ports=${ports}"
}

select_learned_cidr24_candidate() {
    local choice row cidr unique total span first last
    local -a rows=()
    SELECTED_LEARN_CIDR=""
    SELECTED_LEARN_NOTE=""
    mapfile -t rows < <(qualified_learned_cidr24_candidates | head -n 50)
    [[ ${#rows[@]} -gt 0 ]] || {
        err "暂无达到门槛的 /24 候选（至少 ${LEARN_NET24_MIN_UNIQUE_IPS} 个 IP，或 ${LEARN_NET24_MIN_HITS} 次命中）。"
        return 1
    }
    local idx=1
    for row in "${rows[@]}"; do
        IFS=$'\t' read -r cidr unique total span first last <<< "${row}"
        printf '  [%d] %s | 来源 IP %s 个 | 命中 %s 次 | 观察 %s | 最近 %s\n' \
            "${idx}" "${cidr}" "${unique}" "${total}" "$(format_seconds "${span}")" "$(format_learn_time "${last}")"
        ((idx++))
    done
    choice="$(read_prompt "请选择要加入自定义白名单的 /24 网段 [1-${#rows[@]}]: ")" || return 1
    [[ "${choice}" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= ${#rows[@]} )) || return 1
    IFS=$'\t' read -r cidr unique total span first last <<< "${rows[$((choice - 1))]}"
    SELECTED_LEARN_CIDR="${cidr}"
    SELECTED_LEARN_NOTE="learned /24 unique=${unique}, hits=${total}, span=$(format_seconds "${span}"), last=${last}"
}

select_learned_cidr16_candidate() {
    local choice row cidr unique unique24 total span first last
    local -a rows=()
    SELECTED_LEARN_CIDR=""
    SELECTED_LEARN_NOTE=""
    mapfile -t rows < <(qualified_learned_cidr16_candidates | head -n 50)
    [[ ${#rows[@]} -gt 0 ]] || {
        err "暂无达到门槛的 /16 候选（至少 ${LEARN_NET16_MIN_UNIQUE_24S} 个 /24，或 ${LEARN_NET16_MIN_HITS} 次命中）。"
        return 1
    }
    local idx=1
    for row in "${rows[@]}"; do
        IFS=$'\t' read -r cidr unique unique24 total span first last <<< "${row}"
        printf '  [%d] %s | 来源 IP %s 个 | 覆盖 /24 %s 个 | 命中 %s 次 | 观察 %s | 最近 %s\n' \
            "${idx}" "${cidr}" "${unique}" "${unique24}" "${total}" "$(format_seconds "${span}")" "$(format_learn_time "${last}")"
        ((idx++))
    done
    choice="$(read_prompt "请选择要加入自定义白名单的 /16 网段 [1-${#rows[@]}]: ")" || return 1
    [[ "${choice}" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= ${#rows[@]} )) || return 1
    IFS=$'\t' read -r cidr unique unique24 total span first last <<< "${rows[$((choice - 1))]}"
    SELECTED_LEARN_CIDR="${cidr}"
    SELECTED_LEARN_NOTE="learned /16 unique_ip=${unique}, unique_24=${unique24}, hits=${total}, span=$(format_seconds "${span}"), last=${last}"
}

iplist_ready() {
    [[ -f "${IPLIST_DOC}" && -f "${IPLIST_MANIFEST}" ]]
}

iplist_region_record() {
    local id="$1"
    [[ -f "${IPLIST_MANIFEST}" ]] || return 1
    awk -F '\t' -v id="${id}" '$1 == id { print; exit }' "${IPLIST_MANIFEST}"
}

iplist_region_label() {
    local id="$1"
    local record name rel
    record="$(iplist_region_record "${id}" || true)"
    if [[ -n "${record}" ]]; then
        IFS=$'\t' read -r _ name rel _ <<< "${record}"
        printf '%s (%s)' "${name}" "${id}"
    else
        printf '%s (missing)' "${id}"
    fi
}

build_iplist_manifest_for_dir() {
    local root="$1"
    local doc="${root}/docs/cncity.md"
    local manifest="${root}/manifest.tsv"
    local tmp
    [[ -f "${doc}" ]] || {
        err "iplist 包缺少 docs/cncity.md。"
        return 1
    }
    make_temp_file "${manifest}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    awk -F '|' '
        function trim_value(s) {
            gsub(/^[ \t\r\n]+/, "", s)
            gsub(/[ \t\r\n]+$/, "", s)
            return s
        }
        NF >= 3 {
            name = trim_value($2)
            url = trim_value($3)
            if (name == "" || url == "" || url == "无") next
            if (url !~ /^https?:\/\// || url !~ /\.txt$/) next
            rel = url
            sub(/^.*\/iplist\//, "", rel)
            if (rel !~ /^data\/cncity\//) {
                sub(/^.*\/data\/cncity\//, "data/cncity/", rel)
            }
            if (rel !~ /^data\/cncity\//) next
            id = rel
            sub(/^.*\//, "", id)
            sub(/\.txt$/, "", id)
            gsub(/[^A-Za-z0-9._-]/, "_", id)
            print id "\t" name "\t" rel "\t" url
        }
    ' "${doc}" | sort -u > "${tmp}"
    [[ -s "${tmp}" ]] || {
        err "无法从 cncity.md 解析出地区列表。"
        return 1
    }
    while IFS=$'\t' read -r _ _ rel _; do
        [[ -f "${root}/${rel}" ]] || {
            err "iplist 包缺少数据文件：${rel}"
            return 1
        }
    done < "${tmp}"
    mv -f "${tmp}" "${manifest}"
}

import_iplist_package() {
    local package="$1"
    local tmpdir olddir ts
    package="$(trim "${package}")"
    [[ -f "${package}" ]] || {
        err "文件不存在：${package}"
        return 1
    }
    command -v tar &>/dev/null || {
        err "系统缺少 tar，无法解压 iplist 包。"
        return 1
    }
    make_temp_dir "${CONF_DIR}" "po0-iplist.import" || return 1
    tmpdir="${TEMP_DIR_RESULT}"
    case "${package}" in
        *.tar.gz|*.tgz)
            tar -xzf "${package}" -C "${tmpdir}" || return 1
            ;;
        *.tar)
            tar -xf "${package}" -C "${tmpdir}" || return 1
            ;;
        *)
            err "仅支持 .tar.gz、.tgz 或 .tar 格式。"
            return 1
            ;;
    esac
    [[ -f "${tmpdir}/docs/cncity.md" ]] || {
        err "压缩包根目录必须包含 docs/cncity.md。"
        return 1
    }
    build_iplist_manifest_for_dir "${tmpdir}" || return 1

    ts="$(date '+%Y%m%d_%H%M%S')"
    olddir="${IPLIST_DIR}.old.${ts}"
    [[ -d "${olddir}" ]] && rm -rf -- "${olddir}"
    [[ -d "${IPLIST_DIR}" ]] && mv "${IPLIST_DIR}" "${olddir}"
    mv "${tmpdir}" "${IPLIST_DIR}" || {
        [[ -d "${olddir}" ]] && mv "${olddir}" "${IPLIST_DIR}" 2>/dev/null || true
        return 1
    }
    TEMP_DIRS=("${TEMP_DIRS[@]/${tmpdir}/}")
    [[ -d "${olddir}" ]] && rm -rf -- "${olddir}"
    success "iplist 离线包已导入。"
}

resource_task_write_header() {
    local path="$1"
    cat > "${path}" <<'EOF'
# format: id|type|status|created_at|claimed_at|finished_at|worker_id|artifact_path|sha256|size|message
EOF
}

ensure_resource_task_layout() {
    mkdir -p "${CONF_DIR}" "${RESOURCE_INBOX_DIR}" || return 1
    chmod 700 "${RESOURCE_INBOX_DIR}" 2>/dev/null || true
    if [[ ! -f "${RESOURCE_TASKS_FILE}" ]]; then
        resource_task_write_header "${RESOURCE_TASKS_FILE}" || return 1
        chmod 600 "${RESOURCE_TASKS_FILE}" 2>/dev/null || true
    fi
}

resource_task_lock() {
    ensure_resource_task_layout || return 1
    exec 9>"${RESOURCE_TASK_LOCK_FILE}" || return 1
    if command -v flock >/dev/null 2>&1; then
        flock -w 15 9 || {
            err "资源任务队列正忙，请稍后重试。"
            exec 9>&-
            return 1
        }
    fi
}

resource_task_unlock() {
    if command -v flock >/dev/null 2>&1; then
        flock -u 9 2>/dev/null || true
    fi
    exec 9>&- 2>/dev/null || true
}

resource_task_token_value() {
    [[ -f "${RESOURCE_TASK_TOKEN_FILE}" ]] || return 1
    tr -d '\r\n' < "${RESOURCE_TASK_TOKEN_FILE}"
}

resource_task_token_matches() {
    local supplied="$1"
    local expected
    expected="$(resource_task_token_value 2>/dev/null || true)"
    [[ -n "${expected}" && -n "${supplied}" && "${supplied}" == "${expected}" ]]
}

resource_task_token_matches_readonly() {
    local supplied="$1"
    local expected
    [[ -s "${RESOURCE_TASK_TOKEN_FILE}" ]] || return 1
    expected="$(tr -d '[:space:]' < "${RESOURCE_TASK_TOKEN_FILE}")" || return 1
    [[ -n "${expected}" && -n "${supplied}" && "${supplied}" == "${expected}" ]]
}

do_resource_task_ping() {
    local token="${1:-}"
    if resource_task_token_matches_readonly "${token}"; then
        printf 'OK|资源任务 Token 可用\n'
        return 0
    fi
    printf 'ERROR|资源任务 Token 错误或尚未生成\n'
    return 1
}

generate_resource_task_token() {
    local token
    ensure_resource_task_layout || return 1
    if command -v openssl >/dev/null 2>&1; then
        token="$(openssl rand -hex 24 2>/dev/null || true)"
    fi
    if [[ -z "${token:-}" ]] && [[ -r /dev/urandom ]]; then
        token="$(od -An -N24 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
    fi
    [[ -n "${token:-}" ]] || {
        err "无法生成资源任务 Token。"
        return 1
    }
    printf '%s\n' "${token}" > "${RESOURCE_TASK_TOKEN_FILE}" || return 1
    chmod 600 "${RESOURCE_TASK_TOKEN_FILE}" 2>/dev/null || true
    printf '%s\n' "${token}"
}

resource_task_type_label() {
    case "$1" in
        iplist) printf 'iplist 地区库' ;;
        ipdb) printf 'qqwry.ipdb' ;;
        *) printf '%s' "$1" ;;
    esac
}

resource_task_status_label() {
    case "$1" in
        pending) printf '等待领取' ;;
        running) printf '执行中' ;;
        success) printf '成功' ;;
        failed) printf '失败' ;;
        *) printf '%s' "$1" ;;
    esac
}

resource_task_artifact_name() {
    case "$1" in
        iplist) printf 'iplist.tar.gz' ;;
        ipdb) printf 'qqwry.ipdb' ;;
        *) return 1 ;;
    esac
}

resource_task_new_id() {
    local suffix
    suffix="$(printf '%05d' "$((RANDOM % 100000))")"
    printf '%s-%s\n' "$(date -u '+%Y%m%dT%H%M%SZ')" "${suffix}"
}

resource_task_pending_id_for_type() {
    local type="$1"
    [[ -f "${RESOURCE_TASKS_FILE}" ]] || return 0
    awk -F '|' -v type="${type}" '
        NF >= 3 && $1 !~ /^#/ && $2 == type && $3 == "pending" {
            print $1
            exit
        }
    ' "${RESOURCE_TASKS_FILE}"
}

compact_resource_tasks_file() {
    local tmp
    make_temp_file "${RESOURCE_TASKS_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    awk -F '|' -v keep="${RESOURCE_TASK_HISTORY_LIMIT}" '
        BEGIN {
            print "# format: id|type|status|created_at|claimed_at|finished_at|worker_id|artifact_path|sha256|size|message"
        }
        /^#/ || NF < 3 { next }
        $3 == "pending" || $3 == "running" {
            active[++active_count] = $0
            next
        }
        {
            terminal[++terminal_count] = $0
        }
        END {
            start = terminal_count - keep + 1
            if (start < 1) start = 1
            for (i = start; i <= terminal_count; i++) print terminal[i]
            for (i = 1; i <= active_count; i++) print active[i]
        }
    ' "${RESOURCE_TASKS_FILE}" > "${tmp}" || return 1
    mv -f "${tmp}" "${RESOURCE_TASKS_FILE}"
}

create_resource_task() {
    local type="$1"
    local id now existing
    resource_task_artifact_name "${type}" >/dev/null || {
        err "不支持的资源任务类型：${type}"
        return 1
    }
    resource_task_lock || return 1
    existing="$(resource_task_pending_id_for_type "${type}" || true)"
    if [[ -n "${existing}" ]]; then
        resource_task_unlock
        warn "已经存在同类型等待领取任务：${existing}（$(resource_task_type_label "${type}")），本次不再追加。"
        return 0
    fi
    id="$(resource_task_new_id)"
    now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf '%s|%s|pending|%s|||||||等待内网机器领取\n' \
        "${id}" "${type}" "${now}" >> "${RESOURCE_TASKS_FILE}" || {
        resource_task_unlock
        return 1
    }
    compact_resource_tasks_file || {
        resource_task_unlock
        return 1
    }
    resource_task_unlock
    success "已创建任务 ${id}：$(resource_task_type_label "${type}")。"
}

delete_unfinished_resource_tasks() {
    local type="${1:-all}" line id task_type status created claimed finished worker artifact sha size message
    local tmp removed=0 inbox_path artifact_name
    type="$(normalize_resource_task_create_type "${type}")" || return 1
    resource_task_lock || return 1
    make_temp_file "${RESOURCE_TASKS_FILE}" || {
        resource_task_unlock
        return 1
    }
    tmp="${TEMP_FILE_RESULT}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ -n "${line}" && "${line}" != \#* ]]; then
            IFS='|' read -r id task_type status created claimed finished worker artifact sha size message <<< "${line}"
            if [[ ( "${status}" == "pending" || "${status}" == "running" ) && ( "${type}" == "all" || "${task_type}" == "${type}" ) ]]; then
                ((removed++))
                artifact_name="$(resource_task_artifact_name "${task_type}" 2>/dev/null || true)"
                if [[ -n "${artifact_name}" ]]; then
                    inbox_path="${RESOURCE_INBOX_DIR}/${id}.${artifact_name}"
                    [[ -e "${inbox_path}" ]] && rm -f -- "${inbox_path}" 2>/dev/null || true
                fi
                continue
            fi
        fi
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${RESOURCE_TASKS_FILE}"
    mv -f "${tmp}" "${RESOURCE_TASKS_FILE}"
    resource_task_unlock
    if [[ "${removed}" -gt 0 ]]; then
        success "已取消未完成的资源任务：${removed} 个。"
    else
        warn "没有匹配的未完成资源任务。"
    fi
}

normalize_resource_task_create_type() {
    local type
    type="$(trim "${1:-all}")"
    case "${type}" in
        iplist|ipdb)
            printf '%s\n' "${type}"
            ;;
        all|both)
            printf 'all\n'
            ;;
        *)
            err "资源任务类型无效：${type:-空}。可用值：iplist、ipdb、all。"
            return 1
            ;;
    esac
}

create_resource_tasks_for_type() {
    local type failed=0
    type="$(normalize_resource_task_create_type "${1:-all}")" || return 1
    ensure_resource_task_layout || return 1
    case "${type}" in
        iplist|ipdb)
            create_resource_task "${type}"
            ;;
        all)
            create_resource_task "iplist" || failed=1
            create_resource_task "ipdb" || failed=1
            return "${failed}"
            ;;
    esac
}

resource_task_cron_begin_marker() {
    printf '# BEGIN PO0 nftables resource task scheduler\n'
}

resource_task_cron_end_marker() {
    printf '# END PO0 nftables resource task scheduler\n'
}
