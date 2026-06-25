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
