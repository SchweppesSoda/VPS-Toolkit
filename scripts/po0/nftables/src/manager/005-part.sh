write_generic_report_stats_header() {
    local path="$1"
    cat > "${path}" <<'EOF'
# Managed by nftables relay manager
# format: key|accepted_count|rejected_count|last_status|last_at|last_ips|last_error
EOF
}

ensure_generic_report_stats_file() {
    local path="$1"
    mkdir -p "${CONF_DIR}" || return 1
    if [[ ! -f "${path}" ]]; then
        write_generic_report_stats_header "${path}"
    fi
}

update_generic_report_stats_unlocked() {
    local path="$1"
    local key="$2"
    local status="$3"
    local ips="${4:-}"
    local error="${5:-}"
    local line tmp stat_key accepted rejected last_status last_at last_ips last_error found=0 now
    key="$(sanitize_allowlist_source_text "${key}")"
    [[ -n "${key}" ]] || key="unknown"
    ips="$(sanitize_allowlist_source_text "${ips:-无}")"
    error="$(sanitize_allowlist_source_text "${error:-无}")"
    [[ -n "${ips}" ]] || ips="无"
    [[ -n "${error}" ]] || error="无"
    now="$(utc_now_iso)"
    ensure_generic_report_stats_file "${path}" || return 1
    make_temp_file "${path}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    write_generic_report_stats_header "${tmp}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        line="$(trim "${line}")"
        [[ -n "${line}" && ! "${line}" =~ ^# ]] || continue
        IFS='|' read -r stat_key accepted rejected last_status last_at last_ips last_error <<< "${line}"
        stat_key="$(sanitize_allowlist_source_text "${stat_key}")"
        [[ -n "${stat_key}" ]] || continue
        [[ "${accepted}" =~ ^[0-9]+$ ]] || accepted=0
        [[ "${rejected}" =~ ^[0-9]+$ ]] || rejected=0
        if [[ "${stat_key}" == "${key}" ]]; then
            found=1
            if [[ "${status}" == "accepted" ]]; then
                accepted=$((accepted + 1))
            else
                rejected=$((rejected + 1))
            fi
            printf '%s|%s|%s|%s|%s|%s|%s\n' \
                "${key}" "${accepted}" "${rejected}" "${status}" "${now}" "${ips}" "${error}" >> "${tmp}"
            continue
        fi
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${path}"
    if [[ "${found}" != "1" ]]; then
        accepted=0
        rejected=0
        if [[ "${status}" == "accepted" ]]; then
            accepted=1
        else
            rejected=1
        fi
        printf '%s|%s|%s|%s|%s|%s|%s\n' \
            "${key}" "${accepted}" "${rejected}" "${status}" "${now}" "${ips}" "${error}" >> "${tmp}"
    fi
    mv -f "${tmp}" "${path}"
}

update_generic_report_stats() {
    with_dynamic_state_lock update_generic_report_stats_unlocked "$@"
}

load_generic_report_stats() {
    local path="$1"
    local key="$2"
    local line stat_key accepted rejected last_status last_at last_ips last_error
    REPORT_STAT_ACCEPTED="0"
    REPORT_STAT_REJECTED="0"
    REPORT_STAT_LAST_STATUS=""
    REPORT_STAT_LAST_AT=""
    REPORT_STAT_LAST_IPS=""
    REPORT_STAT_LAST_ERROR=""
    key="$(sanitize_allowlist_source_text "${key}")"
    [[ -f "${path}" ]] || return 0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        line="$(trim "${line}")"
        [[ -n "${line}" && ! "${line}" =~ ^# ]] || continue
        IFS='|' read -r stat_key accepted rejected last_status last_at last_ips last_error <<< "${line}"
        stat_key="$(sanitize_allowlist_source_text "${stat_key}")"
        if [[ "${stat_key}" == "${key}" ]]; then
            REPORT_STAT_ACCEPTED="${accepted:-0}"
            REPORT_STAT_REJECTED="${rejected:-0}"
            REPORT_STAT_LAST_STATUS="${last_status:-}"
            REPORT_STAT_LAST_AT="${last_at:-}"
            REPORT_STAT_LAST_IPS="${last_ips:-}"
            REPORT_STAT_LAST_ERROR="${last_error:-}"
            return 0
        fi
    done < "${path}"
}

ensure_ddns_report_stats_file() {
    mkdir -p "${CONF_DIR}" || return 1
    if [[ ! -f "${DDNS_REPORT_STATS_FILE}" ]]; then
        write_ddns_report_stats_header "${DDNS_REPORT_STATS_FILE}"
    fi
}

update_ddns_report_stats_unlocked() {
    local key="$1"
    local status="$2"
    local ips="${3:-}"
    local error="${4:-}"
    local line tmp stat_key accepted rejected last_status last_at last_ips last_error found=0 now
    key="$(sanitize_allowlist_source_text "${key}")"
    [[ -n "${key}" ]] || key="unknown"
    ips="$(sanitize_allowlist_source_text "${ips:-无}")"
    error="$(sanitize_allowlist_source_text "${error:-无}")"
    [[ -n "${ips}" ]] || ips="无"
    [[ -n "${error}" ]] || error="无"
    now="$(utc_now_iso)"
    ensure_ddns_report_stats_file || return 1
    make_temp_file "${DDNS_REPORT_STATS_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    write_ddns_report_stats_header "${tmp}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        line="$(trim "${line}")"
        [[ -n "${line}" && ! "${line}" =~ ^# ]] || continue
        IFS='|' read -r stat_key accepted rejected last_status last_at last_ips last_error <<< "${line}"
        stat_key="$(sanitize_allowlist_source_text "${stat_key}")"
        [[ -n "${stat_key}" ]] || continue
        [[ "${accepted}" =~ ^[0-9]+$ ]] || accepted=0
        [[ "${rejected}" =~ ^[0-9]+$ ]] || rejected=0
        if [[ "${stat_key}" == "${key}" ]]; then
            found=1
            if [[ "${status}" == "accepted" ]]; then
                accepted=$((accepted + 1))
            else
                rejected=$((rejected + 1))
            fi
            printf '%s|%s|%s|%s|%s|%s|%s\n' \
                "${key}" "${accepted}" "${rejected}" "${status}" "${now}" "${ips}" "${error}" >> "${tmp}"
            continue
        fi
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${DDNS_REPORT_STATS_FILE}"
    if [[ "${found}" != "1" ]]; then
        accepted=0
        rejected=0
        if [[ "${status}" == "accepted" ]]; then
            accepted=1
        else
            rejected=1
        fi
        printf '%s|%s|%s|%s|%s|%s|%s\n' \
            "${key}" "${accepted}" "${rejected}" "${status}" "${now}" "${ips}" "${error}" >> "${tmp}"
    fi
    mv -f "${tmp}" "${DDNS_REPORT_STATS_FILE}"
}

update_ddns_report_stats() {
    with_dynamic_state_lock update_ddns_report_stats_unlocked "$@"
}

load_ddns_report_stats() {
    local key="$1"
    local line stat_key accepted rejected last_status last_at last_ips last_error
    DDNS_STAT_ACCEPTED="0"
    DDNS_STAT_REJECTED="0"
    DDNS_STAT_LAST_STATUS=""
    DDNS_STAT_LAST_AT=""
    DDNS_STAT_LAST_IPS=""
    DDNS_STAT_LAST_ERROR=""
    key="$(sanitize_allowlist_source_text "${key}")"
    [[ -f "${DDNS_REPORT_STATS_FILE}" ]] || return 0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        line="$(trim "${line}")"
        [[ -n "${line}" && ! "${line}" =~ ^# ]] || continue
        IFS='|' read -r stat_key accepted rejected last_status last_at last_ips last_error <<< "${line}"
        stat_key="$(sanitize_allowlist_source_text "${stat_key}")"
        if [[ "${stat_key}" == "${key}" ]]; then
            DDNS_STAT_ACCEPTED="${accepted:-0}"
            DDNS_STAT_REJECTED="${rejected:-0}"
            DDNS_STAT_LAST_STATUS="${last_status:-}"
            DDNS_STAT_LAST_AT="${last_at:-}"
            DDNS_STAT_LAST_IPS="${last_ips:-}"
            DDNS_STAT_LAST_ERROR="${last_error:-}"
            return 0
        fi
    done < "${DDNS_REPORT_STATS_FILE}"
}

print_ddns_report_stats_line() {
    local key="$1"
    local status_label
    load_ddns_report_stats "${key}"
    if [[ -z "${DDNS_STAT_LAST_STATUS}" ]]; then
        printf '      外部上报统计：尚无记录\n'
        return 0
    fi
    case "${DDNS_STAT_LAST_STATUS}" in
        accepted)
            status_label="接受"
            ;;
        rejected)
            status_label="拒绝"
            ;;
        *)
            status_label="${DDNS_STAT_LAST_STATUS}"
            ;;
    esac
    printf '      外部上报统计：接受=%s 拒绝=%s 最近=%s 状态=%s IP=%s\n' \
        "${DDNS_STAT_ACCEPTED}" "${DDNS_STAT_REJECTED}" "${DDNS_STAT_LAST_AT:-未知}" \
        "${status_label}" "${DDNS_STAT_LAST_IPS:-无}"
    if [[ -n "${DDNS_STAT_LAST_ERROR}" && "${DDNS_STAT_LAST_ERROR}" != "无" ]]; then
        printf '      最近错误：%s\n' "${DDNS_STAT_LAST_ERROR}"
    fi
}

remove_ddns_report_stats_unlocked() {
    local key="$1"
    local line stat_key tmp
    key="$(sanitize_allowlist_source_text "${key}")"
    [[ -f "${DDNS_REPORT_STATS_FILE}" ]] || return 0
    make_temp_file "${DDNS_REPORT_STATS_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    write_ddns_report_stats_header "${tmp}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        line="$(trim "${line}")"
        [[ -n "${line}" && ! "${line}" =~ ^# ]] || continue
        IFS='|' read -r stat_key _ <<< "${line}"
        stat_key="$(sanitize_allowlist_source_text "${stat_key}")"
        [[ "${stat_key}" == "${key}" ]] && continue
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${DDNS_REPORT_STATS_FILE}"
    mv -f "${tmp}" "${DDNS_REPORT_STATS_FILE}"
}

remove_ddns_report_stats() {
    with_dynamic_state_lock remove_ddns_report_stats_unlocked "$@"
}

normalize_client_ttl_seconds() {
    local ttl="${1:-}"
    local fallback="${2:-43200}"
    [[ "${fallback}" =~ ^[0-9]+$ ]] || fallback="43200"
    [[ "${ttl}" =~ ^[0-9]+$ ]] || ttl="${fallback}"
    (( ttl >= 60 )) || ttl=60
    (( ttl <= 604800 )) || ttl=604800
    printf '%s\n' "${ttl}"
}

normalize_ssh_report_cidr_prefix() {
    local prefix="${1:-32}"
    [[ -n "${prefix}" ]] || prefix="32"
    [[ "${prefix}" =~ ^[0-9]+$ ]] || return 1
    case "${prefix}" in
        24|32)
            printf '%s\n' "${prefix}"
            ;;
        *)
            return 1
            ;;
    esac
}

ssh_report_cidr_for_ip_prefix() {
    local ip="$1"
    local prefix="${2:-32}"
    local cidr
    is_public_ipv4 "${ip}" || return 1
    prefix="$(normalize_ssh_report_cidr_prefix "${prefix}")" || return 1
    cidr="$(normalize_ipv4_cidr_or_host "${ip}/${prefix}")" || return 1
    printf '%s\n' "${cidr}"
}

normalize_report_expires_at() {
    local value="${1:-}"
    local parsed max_expires_at
    value="$(sanitize_allowlist_entry_text "${value}")"
    if [[ "${value}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
        parsed="${value}"
    elif [[ "${value}" =~ ^[0-9]+$ ]]; then
        parsed="$(date -u -d "@${value}" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true)"
    fi
    [[ -n "${parsed:-}" ]] || parsed="$(utc_after_seconds_iso 43200)"
    max_expires_at="$(utc_after_seconds_iso 604800)"
    if [[ "${parsed}" > "${max_expires_at}" ]]; then
        printf '%s\n' "${max_expires_at}"
    else
        printf '%s\n' "${parsed}"
    fi
}

report_client_ip_source_unlocked() {
    local source_id="$1"
    local ip="$2"
    local token="$3"
    local identity="${4:-}"
    local ttl="${5:-43200}"
    local expires_at note cidr
    source_id="$(sanitize_allowlist_source_text "${source_id}")"
    identity="$(sanitize_allowlist_source_text "${identity}")"
    [[ -n "${source_id}" ]] || {
        update_generic_report_stats "${CLIENT_IP_REPORT_STATS_FILE}" "unknown" "rejected" "${ip}" "missing_source_id" || true
        err "缺少客户端来源 ID。"
        return 1
    }
    is_public_ipv4 "${ip}" || {
        update_generic_report_stats "${CLIENT_IP_REPORT_STATS_FILE}" "${source_id}" "rejected" "${ip}" "invalid_public_ipv4" || true
        err "客户端上报 IP 无效：${ip}"
        return 1
    }
    validate_client_ip_report_token "${token}" || {
        update_generic_report_stats "${CLIENT_IP_REPORT_STATS_FILE}" "${source_id}" "rejected" "${ip}" "invalid_token" || true
        err "客户端 IP 上报 token 无效。"
        return 1
    }
    ttl="$(normalize_client_ttl_seconds "${ttl}" 43200)"
    expires_at="$(utc_after_seconds_iso "${ttl}")"
    cidr="${ip}/32"
    note="client_ip ${source_id}"
    [[ -n "${identity}" ]] && note="${note} identity=${identity}"
    note="${note} ttl=${ttl} $(ipdb_snapshot_for_ip "${ip}")"
    replace_allowlist_entries_for_source_with_expiry "default" "client_ip" "${source_id}" "${note}" "${expires_at}" "${cidr}" || return 1
    update_generic_report_stats "${CLIENT_IP_REPORT_STATS_FILE}" "${source_id}" "accepted" "${ip}" "pending=${DYNAMIC_REPORT_PENDING_COUNT:-0}" || true
    CLIENT_IP_REPORT_SOURCE="${source_id}"
    CLIENT_IP_REPORT_IP="${ip}"
    CLIENT_IP_REPORT_IDENTITY="${identity}"
    CLIENT_IP_REPORT_TTL="${ttl}"
}

report_client_ip_source() {
    with_dynamic_state_lock report_client_ip_source_unlocked "$@"
}

report_ssh_ip_source_unlocked() {
    local source_id="$1"
    local ip="$2"
    local token="$3"
    local identity="${4:-}"
    local ttl="${5:-43200}"
    local cidr_prefix="${6:-32}"
    local raw_cidr_prefix
    local expires_at note cidr
    source_id="$(sanitize_allowlist_source_text "${source_id}")"
    identity="$(sanitize_allowlist_source_text "${identity}")"
    [[ -n "${source_id}" ]] || {
        update_generic_report_stats "${SSH_REPORT_STATS_FILE}" "unknown" "rejected" "${ip}" "missing_source_id" || true
        err "missing ssh report source id"
        return 1
    }
    is_public_ipv4 "${ip}" || {
        update_generic_report_stats "${SSH_REPORT_STATS_FILE}" "${source_id}" "rejected" "${ip}" "invalid_public_ipv4" || true
        err "invalid ssh report public IPv4: ${ip}"
        return 1
    }
    validate_ssh_report_token "${token}" || {
        update_generic_report_stats "${SSH_REPORT_STATS_FILE}" "${source_id}" "rejected" "${ip}" "invalid_token" || true
        err "invalid ssh report token"
        return 1
    }
    ttl="$(normalize_client_ttl_seconds "${ttl}" 43200)"
    raw_cidr_prefix="${cidr_prefix}"
    cidr_prefix="$(normalize_ssh_report_cidr_prefix "${cidr_prefix}")" || {
        update_generic_report_stats "${SSH_REPORT_STATS_FILE}" "${source_id}" "rejected" "${ip}" "invalid_cidr_prefix" || true
        err "invalid ssh report cidr prefix: ${raw_cidr_prefix:-}"
        return 1
    }
    expires_at="$(utc_after_seconds_iso "${ttl}")"
    cidr="$(ssh_report_cidr_for_ip_prefix "${ip}" "${cidr_prefix}")" || {
        update_generic_report_stats "${SSH_REPORT_STATS_FILE}" "${source_id}" "rejected" "${ip}" "invalid_cidr" || true
        err "invalid ssh report CIDR: ${ip}/${cidr_prefix}"
        return 1
    }
    note="ssh_report ${source_id}"
    [[ -n "${identity}" ]] && note="${note} identity=${identity}"
    note="${note} ttl=${ttl} prefix=${cidr_prefix} $(ipdb_snapshot_for_ip "${ip}")"
    replace_allowlist_entries_for_source_with_expiry "default" "ssh_report" "${source_id}" "${note}" "${expires_at}" "${cidr}" || return 1
    update_generic_report_stats "${SSH_REPORT_STATS_FILE}" "${source_id}" "accepted" "${ip}" "cidr=${cidr} pending=${DYNAMIC_REPORT_PENDING_COUNT:-0}" || true
    SSH_REPORT_SOURCE="${source_id}"
    SSH_REPORT_IP="${ip}"
    SSH_REPORT_CIDR="${cidr}"
    SSH_REPORT_CIDR_PREFIX="${cidr_prefix}"
    SSH_REPORT_IDENTITY="${identity}"
    SSH_REPORT_TTL="${ttl}"
}

report_ssh_ip_source() {
    with_dynamic_state_lock report_ssh_ip_source_unlocked "$@"
}

report_webauth_source_unlocked() {
    local source_id="$1"
    local ip="$2"
    local identity="$3"
    local expires_at="$4"
    local token="$5"
    local note_extra="${6:-}"
    local note cidr
    source_id="$(sanitize_allowlist_source_text "${source_id}")"
    identity="$(sanitize_allowlist_source_text "${identity}")"
    note_extra="$(sanitize_allowlist_source_text "${note_extra}")"
    [[ -n "${source_id}" && -n "${identity}" ]] || {
        update_generic_report_stats "${WEBAUTH_REPORT_STATS_FILE}" "${source_id:-unknown}" "rejected" "${ip}" "missing_source_or_identity" || true
        err "缺少 WebAuth 来源 ID 或身份。"
        return 1
    }
    is_public_ipv4 "${ip}" || {
        update_generic_report_stats "${WEBAUTH_REPORT_STATS_FILE}" "${source_id}" "rejected" "${ip}" "invalid_public_ipv4" || true
        err "WebAuth 上报 IP 无效：${ip}"
        return 1
    }
    validate_webauth_report_token "${token}" || {
        update_generic_report_stats "${WEBAUTH_REPORT_STATS_FILE}" "${source_id}" "rejected" "${ip}" "invalid_token" || true
        err "WebAuth 上报 token 无效。"
        return 1
    }
    expires_at="$(normalize_report_expires_at "${expires_at}")"
    cidr="${ip}/32"
    note="webauth ${source_id} identity=${identity}"
    [[ -n "${note_extra}" ]] && note="${note} ${note_extra}"
    note="${note} $(ipdb_snapshot_for_ip "${ip}")"
    replace_allowlist_entries_for_source_with_expiry "default" "webauth" "${source_id}" "${note}" "${expires_at}" "${cidr}" || return 1
    update_generic_report_stats "${WEBAUTH_REPORT_STATS_FILE}" "${source_id}" "accepted" "${ip}" "pending=${DYNAMIC_REPORT_PENDING_COUNT:-0}" || true
    WEBAUTH_REPORT_SOURCE="${source_id}"
    WEBAUTH_REPORT_IP="${ip}"
    WEBAUTH_REPORT_IDENTITY="${identity}"
    WEBAUTH_REPORT_EXPIRES_AT="${expires_at}"
}

report_webauth_source() {
    with_dynamic_state_lock report_webauth_source_unlocked "$@"
}

report_ddns_allowlist_source_unlocked() {
    local key="$1"
    local raw_ips="$2"
    local token="${3:-}"
    local csv line tmp now replacement note cidr expires_at found=0 disabled=0 disabled_stat_key=""
    local -a cidrs=()

    key="$(sanitize_allowlist_source_text "${key}")"
    csv="$(normalize_public_ipv4_csv "${raw_ips}")" || {
        err "外部上报 DDNS 结果无效：没有可用公网 IPv4。"
        update_ddns_report_stats "${key}" "rejected" "无" "invalid_public_ipv4" || true
        return 1
    }
    validate_ddns_report_token "${token}" || {
        err "DDNS 外部上报 token 无效。"
        update_ddns_report_stats "${key}" "rejected" "${csv}" "invalid_token" || true
        return 1
    }
    ensure_allowlist_sources_file || return 1
    ensure_allowlist_entries_file || return 1
    make_temp_file "${ALLOWLIST_SOURCES_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    write_allowlist_sources_header "${tmp}"

    while IFS= read -r line || [[ -n "${line}" ]]; do
        if parse_allowlist_source_line "${line}"; then
            if [[ "${ALLOWLIST_SOURCE_NAME}" == "${key}" || "${ALLOWLIST_SOURCE_VALUE}" == "${key}" ]]; then
                found=1
                if [[ "${ALLOWLIST_SOURCE_ENABLED}" != "1" ]]; then
                    disabled=1
                    disabled_stat_key="${ALLOWLIST_SOURCE_VALUE}"
                    printf '%s\n' "${PARSED_ALLOWLIST_SOURCE}" >> "${tmp}"
                    continue
                fi
                now="$(utc_now_iso)"
                cidrs=()
                while IFS= read -r cidr; do
                    cidrs+=("${cidr}/32")
                done < <(print_ipv4_csv_lines "${csv}")
                expires_at="$(utc_after_seconds_iso "${ALLOWLIST_SOURCE_TTL_SECONDS}")"
                note="ddns report ${ALLOWLIST_SOURCE_NAME} ${ALLOWLIST_SOURCE_VALUE} $(ipdb_snapshot_for_ip "${cidrs[0]%/32}")"
                replace_allowlist_entries_for_source_with_expiry \
                    "${ALLOWLIST_SOURCE_SET_ID}" \
                    "ddns" \
                    "${ALLOWLIST_SOURCE_VALUE}" \
                    "${note}" \
                    "${expires_at}" \
                    "${cidrs[@]}" || return 1
                if [[ "${ALLOWLIST_SOURCE_NAME}" != "${ALLOWLIST_SOURCE_VALUE}" ]]; then
                    remove_allowlist_entries_for_source "${ALLOWLIST_SOURCE_SET_ID}" "ddns" "${ALLOWLIST_SOURCE_NAME}" || return 1
                fi
                replacement="$(serialize_allowlist_source \
                    "${ALLOWLIST_SOURCE_SET_ID}" \
                    "${ALLOWLIST_SOURCE_TYPE}" \
                    "${ALLOWLIST_SOURCE_NAME}" \
                    "${ALLOWLIST_SOURCE_VALUE}" \
                    "${ALLOWLIST_SOURCE_ENABLED}" \
                    "${ALLOWLIST_SOURCE_TTL_SECONDS}" \
                    "${now}" \
                    "report:${csv}")"
                printf '%s\n' "${replacement}" >> "${tmp}"
                DDNS_REPORT_NAME="${ALLOWLIST_SOURCE_NAME}"
                DDNS_REPORT_DOMAIN="${ALLOWLIST_SOURCE_VALUE}"
                DDNS_REPORT_IPS="${csv}"
                continue
            fi
            printf '%s\n' "${PARSED_ALLOWLIST_SOURCE}" >> "${tmp}"
        elif [[ -n "$(trim "${line}")" && ! "$(trim "${line}")" =~ ^# ]]; then
            printf '%s\n' "${line}" >> "${tmp}"
        fi
    done < "${ALLOWLIST_SOURCES_FILE}"

    if [[ "${found}" != "1" ]]; then
        err "未找到 DDNS 来源：${key}。请先在菜单里添加。"
        update_ddns_report_stats "${key}" "rejected" "${csv}" "source_not_found" || true
        return 1
    fi
    if [[ "${disabled}" == "1" ]]; then
        err "DDNS 来源已停用：${key}。请先启用。"
        update_ddns_report_stats "${disabled_stat_key:-${key}}" "rejected" "${csv}" "source_disabled" || true
        return 1
    fi
    mv -f "${tmp}" "${ALLOWLIST_SOURCES_FILE}"
    update_ddns_report_stats "${DDNS_REPORT_DOMAIN:-${key}}" "accepted" "${csv}" "无" || true
}

report_ddns_allowlist_source() {
    with_dynamic_state_lock report_ddns_allowlist_source_unlocked "$@"
}

refresh_ddns_allowlist_sources_unlocked() {
    local line tmp result ips_csv cidr note expires_at reported=0 failed=0 disabled=0
    local -a ips=()
    local -a cidrs=()
    ensure_allowlist_sources_file || return 1
    ensure_allowlist_entries_file || return 1
    make_temp_file "${ALLOWLIST_SOURCES_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    write_allowlist_sources_header "${tmp}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if ! parse_allowlist_source_line "${line}"; then
            if [[ -n "$(trim "${line}")" && ! "$(trim "${line}")" =~ ^# ]]; then
                printf '%s\n' "${line}" >> "${tmp}"
            fi
            continue
        fi
        if [[ "${ALLOWLIST_SOURCE_ENABLED}" != "1" ]]; then
            ((disabled++))
            sync_ddns_entries_removed "${ALLOWLIST_SOURCE_SET_ID}" "${ALLOWLIST_SOURCE_NAME}" "${ALLOWLIST_SOURCE_VALUE}" || return 1
            printf '%s\n' "${PARSED_ALLOWLIST_SOURCE}" >> "${tmp}"
            continue
        fi
        mapfile -t ips < <(reported_ddns_ipv4_records \
            "${ALLOWLIST_SOURCE_LAST_RESOLVED_AT}" \
            "${ALLOWLIST_SOURCE_TTL_SECONDS}" \
            "${ALLOWLIST_SOURCE_LAST_RESULT}" || true)
        if [[ ${#ips[@]} -gt 0 ]]; then
            cidrs=()
            for cidr in "${ips[@]}"; do
                cidrs+=("${cidr}/32")
            done
            expires_at="$(utc_add_seconds_iso "${ALLOWLIST_SOURCE_LAST_RESOLVED_AT}" "${ALLOWLIST_SOURCE_TTL_SECONDS}")"
            note="ddns report ${ALLOWLIST_SOURCE_NAME} ${ALLOWLIST_SOURCE_VALUE} $(ipdb_snapshot_for_ip "${cidrs[0]%/32}")"
            replace_allowlist_entries_for_source_with_expiry \
                "${ALLOWLIST_SOURCE_SET_ID}" \
                "ddns" \
                "${ALLOWLIST_SOURCE_VALUE}" \
                "${note}" \
                "${expires_at}" \
                "${cidrs[@]}" || return 1
            if [[ "${ALLOWLIST_SOURCE_NAME}" != "${ALLOWLIST_SOURCE_VALUE}" ]]; then
                remove_allowlist_entries_for_source "${ALLOWLIST_SOURCE_SET_ID}" "ddns" "${ALLOWLIST_SOURCE_NAME}" || return 1
            fi
            ips_csv="$(join_csv "${ips[@]}")"
            result="report:${ips_csv}"
            ((reported++))
        else
            result="${ALLOWLIST_SOURCE_LAST_RESULT}"
            ((failed++))
        fi
        printf '%s\n' "$(serialize_allowlist_source \
            "${ALLOWLIST_SOURCE_SET_ID}" \
            "${ALLOWLIST_SOURCE_TYPE}" \
            "${ALLOWLIST_SOURCE_NAME}" \
            "${ALLOWLIST_SOURCE_VALUE}" \
            "${ALLOWLIST_SOURCE_ENABLED}" \
            "${ALLOWLIST_SOURCE_TTL_SECONDS}" \
            "${ALLOWLIST_SOURCE_LAST_RESOLVED_AT}" \
            "${result}")" >> "${tmp}"
    done < "${ALLOWLIST_SOURCES_FILE}"
    mv -f "${tmp}" "${ALLOWLIST_SOURCES_FILE}"
    DDNS_REPORTED_COUNT="${reported}"
    DDNS_LOCAL_COUNT="0"
    DDNS_REFRESHED_COUNT="${reported}"
    DDNS_FAILED_COUNT="${failed}"
    DDNS_DISABLED_COUNT="${disabled}"
}

refresh_ddns_allowlist_sources() {
    with_dynamic_state_lock refresh_ddns_allowlist_sources_unlocked "$@"
}

src_allowlist_mode_to_label() {
    case "$1" in
        manual_only)
            printf '仅手动来源'
            ;;
        trusted_dynamic)
            printf '可信动态来源'
            ;;
        region_plus_trusted)
            printf '地区 + 可信动态来源'
            ;;
        region_only)
            printf '仅地区库'
            ;;
        custom_sources)
            printf '高级自选来源'
            ;;
        *)
            printf '可信动态来源'
            ;;
    esac
}

src_allowlist_mode_uses_region() {
    [[ "${SRC_ALLOWLIST_MODE}" == "region_only" || "${SRC_ALLOWLIST_MODE}" == "region_plus_trusted" ]]
}

src_allowlist_mode_uses_custom() {
    [[ "${SRC_ALLOWLIST_MODE}" != "region_only" ]]
}
