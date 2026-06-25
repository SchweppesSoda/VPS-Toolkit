upsert_allowlist_entry() {
    local set_id="$1"
    local cidr="$2"
    local source_type="$3"
    local source_value="${4:-}"
    local note="${5:-}"
    local expires_at="${6:-}"
    local created_at line tmp replaced=0

    validate_allowlist_set_id "${set_id}" || return 1
    cidr="$(normalize_ipv4_cidr_or_host "${cidr}")" || return 1
    source_type="$(normalize_allowlist_entry_source_type "${source_type}")" || return 1
    source_value="$(sanitize_allowlist_entry_text "${source_value}")"
    note="$(sanitize_allowlist_entry_text "${note}")"
    expires_at="$(sanitize_allowlist_entry_text "${expires_at}")"
    created_at="$(utc_now_iso)"
    ensure_allowlist_entries_file || return 1
    make_temp_file "${ALLOWLIST_ENTRIES_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    write_allowlist_entries_header "${tmp}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if parse_allowlist_entry_line "${line}"; then
            if [[ "${ALLOWLIST_ENTRY_SET_ID}" == "${set_id}" \
                && "${ALLOWLIST_ENTRY_CIDR}" == "${cidr}" \
                && "${ALLOWLIST_ENTRY_SOURCE_TYPE}" == "${source_type}" \
                && "${ALLOWLIST_ENTRY_SOURCE_VALUE}" == "${source_value}" ]]; then
                if [[ "${replaced}" != "1" ]]; then
                    serialize_allowlist_entry "${set_id}" "${cidr}" "${source_type}" "${source_value}" "${note}" "${created_at}" "${expires_at}" \
                        >> "${tmp}"
                    replaced=1
                fi
                continue
            fi
            printf '%s\n' "${PARSED_ALLOWLIST_ENTRY}" >> "${tmp}"
        elif [[ -n "$(trim "${line}")" && ! "$(trim "${line}")" =~ ^# ]]; then
            printf '%s\n' "${line}" >> "${tmp}"
        fi
    done < "${ALLOWLIST_ENTRIES_FILE}"
    if [[ "${replaced}" != "1" ]]; then
        serialize_allowlist_entry "${set_id}" "${cidr}" "${source_type}" "${source_value}" "${note}" "${created_at}" "${expires_at}" \
            >> "${tmp}"
    fi
    mv -f "${tmp}" "${ALLOWLIST_ENTRIES_FILE}"
}

remove_allowlist_entries_for_cidr() {
    local set_id="$1"
    local cidr="$2"
    local line tmp removed=0
    validate_allowlist_set_id "${set_id}" || return 1
    cidr="$(normalize_ipv4_cidr_or_host "${cidr}")" || return 1
    [[ -f "${ALLOWLIST_ENTRIES_FILE}" ]] || return 0
    make_temp_file "${ALLOWLIST_ENTRIES_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    write_allowlist_entries_header "${tmp}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if parse_allowlist_entry_line "${line}"; then
            if [[ "${ALLOWLIST_ENTRY_SET_ID}" == "${set_id}" && "${ALLOWLIST_ENTRY_CIDR}" == "${cidr}" ]]; then
                removed=1
                continue
            fi
            printf '%s\n' "${PARSED_ALLOWLIST_ENTRY}" >> "${tmp}"
        elif [[ -n "$(trim "${line}")" && ! "$(trim "${line}")" =~ ^# ]]; then
            printf '%s\n' "${line}" >> "${tmp}"
        fi
    done < "${ALLOWLIST_ENTRIES_FILE}"
    mv -f "${tmp}" "${ALLOWLIST_ENTRIES_FILE}"
    [[ "${removed}" == "1" ]] || return 0
}

append_allowlist_entries_to_cache() {
    local set_id="${1:-default}"
    local tmp="$2"
    local line count=0
    [[ -f "${ALLOWLIST_ENTRIES_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_entry_line "${line}" || continue
        [[ "${ALLOWLIST_ENTRY_SET_ID}" == "${set_id}" ]] || continue
        source_type_allowed_by_mode "${ALLOWLIST_ENTRY_SOURCE_TYPE}" "${SRC_ALLOWLIST_MODE}" || continue
        allowlist_entry_is_expired "${ALLOWLIST_ENTRY_EXPIRES_AT}" && continue
        printf '%s\n' "${ALLOWLIST_ENTRY_CIDR}" >> "${tmp}"
        ((count++))
    done < "${ALLOWLIST_ENTRIES_FILE}"
    printf '%s\n' "${count}"
}

allowlist_active_entries_count_for_mode() {
    local set_id="${1:-default}"
    local line count=0
    [[ -f "${ALLOWLIST_ENTRIES_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_entry_line "${line}" || continue
        [[ "${ALLOWLIST_ENTRY_SET_ID}" == "${set_id}" ]] || continue
        source_type_allowed_by_mode "${ALLOWLIST_ENTRY_SOURCE_TYPE}" "${SRC_ALLOWLIST_MODE}" || continue
        allowlist_entry_is_expired "${ALLOWLIST_ENTRY_EXPIRES_AT}" && continue
        ((count++))
    done < "${ALLOWLIST_ENTRIES_FILE}"
    printf '%s\n' "${count}"
}

write_allowlist_sources_header() {
    local path="$1"
    cat > "${path}" <<'EOF'
# Managed by nftables relay manager
# format: set_id|source_type|name|value|enabled|ttl_seconds|last_resolved_at|last_result
# source_type: ddns
# last_result: report:<ip_csv> for external reports, local:<ip_csv> for legacy compatibility, or ERROR ...
EOF
}

ensure_allowlist_sources_file() {
    mkdir -p "${CONF_DIR}" || return 1
    if [[ ! -f "${ALLOWLIST_SOURCES_FILE}" ]]; then
        write_allowlist_sources_header "${ALLOWLIST_SOURCES_FILE}"
    fi
}

sanitize_allowlist_source_text() {
    local value="$1"
    value="${value//$'\t'/ }"
    value="${value//$'\r'/ }"
    value="${value//$'\n'/ }"
    value="${value//|//}"
    value="$(trim "${value}")"
    [[ ${#value} -le 128 ]] || value="${value:0:128}"
    printf '%s\n' "${value}"
}

validate_ddns_domain() {
    local value="$1"
    [[ ${#value} -ge 1 && ${#value} -le 253 ]] || return 1
    [[ "${value}" =~ ^[A-Za-z0-9.-]+$ ]] || return 1
    [[ "${value}" == *.* ]] || return 1
    [[ ! "${value}" == .* && ! "${value}" == *. ]] || return 1
}

normalize_source_ttl_seconds() {
    local ttl="${1:-43200}"
    [[ "${ttl}" =~ ^[0-9]+$ ]] || ttl="43200"
    (( ttl >= 60 )) || ttl=60
    (( ttl <= 86400 )) || ttl=86400
    printf '%s\n' "${ttl}"
}

serialize_allowlist_source() {
    local set_id="$1"
    local source_type="$2"
    local name="$3"
    local value="$4"
    local enabled="$5"
    local ttl_seconds="$6"
    local last_resolved_at="${7:-}"
    local last_result="${8:-}"
    printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
        "${set_id}" "${source_type}" "${name}" "${value}" "${enabled}" "${ttl_seconds}" "${last_resolved_at}" "${last_result}"
}

parse_allowlist_source_line() {
    local line="$1"
    local set_id source_type name value enabled ttl_seconds last_resolved_at last_result
    local -a fields=()

    PARSED_ALLOWLIST_SOURCE=""
    ALLOWLIST_SOURCE_SET_ID=""
    ALLOWLIST_SOURCE_TYPE=""
    ALLOWLIST_SOURCE_NAME=""
    ALLOWLIST_SOURCE_VALUE=""
    ALLOWLIST_SOURCE_ENABLED=""
    ALLOWLIST_SOURCE_TTL_SECONDS=""
    ALLOWLIST_SOURCE_LAST_RESOLVED_AT=""
    ALLOWLIST_SOURCE_LAST_RESULT=""

    line="${line%$'\r'}"
    line="$(trim "${line}")"
    [[ -n "${line}" && ! "${line}" =~ ^# ]] || return 1

    IFS='|' read -r -a fields <<< "${line}"
    [[ ${#fields[@]} -ge 6 ]] || return 1

    set_id="$(trim "${fields[0]}")"
    source_type="$(normalize_allowlist_entry_source_type "$(trim "${fields[1]}")")" || return 1
    name="$(sanitize_allowlist_source_text "${fields[2]}")"
    value="$(sanitize_allowlist_source_text "${fields[3]}")"
    enabled="$(trim "${fields[4]}")"
    ttl_seconds="$(normalize_source_ttl_seconds "${fields[5]}")"
    last_resolved_at=""
    last_result=""
    [[ ${#fields[@]} -ge 7 ]] && last_resolved_at="$(sanitize_allowlist_source_text "${fields[6]}")"
    [[ ${#fields[@]} -ge 8 ]] && last_result="$(sanitize_allowlist_source_text "${fields[7]}")"

    validate_allowlist_set_id "${set_id}" || return 1
    [[ "${source_type}" == "ddns" ]] || return 1
    [[ -n "${name}" ]] || name="${value}"
    validate_ddns_domain "${value}" || return 1
    [[ "${enabled}" == "0" || "${enabled}" == "1" ]] || return 1

    ALLOWLIST_SOURCE_SET_ID="${set_id}"
    ALLOWLIST_SOURCE_TYPE="${source_type}"
    ALLOWLIST_SOURCE_NAME="${name}"
    ALLOWLIST_SOURCE_VALUE="${value}"
    ALLOWLIST_SOURCE_ENABLED="${enabled}"
    ALLOWLIST_SOURCE_TTL_SECONDS="${ttl_seconds}"
    ALLOWLIST_SOURCE_LAST_RESOLVED_AT="${last_resolved_at}"
    ALLOWLIST_SOURCE_LAST_RESULT="${last_result}"
    PARSED_ALLOWLIST_SOURCE="$(serialize_allowlist_source \
        "${set_id}" "${source_type}" "${name}" "${value}" "${enabled}" "${ttl_seconds}" "${last_resolved_at}" "${last_result}")"
}

allowlist_sources_count() {
    local line count=0
    [[ -f "${ALLOWLIST_SOURCES_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_source_line "${line}" || continue
        ((count++))
    done < "${ALLOWLIST_SOURCES_FILE}"
    printf '%s\n' "${count}"
}

join_csv() {
    local item out=""
    for item in "$@"; do
        if [[ -z "${out}" ]]; then
            out="${item}"
        else
            out+=",${item}"
        fi
    done
    printf '%s\n' "${out}"
}

normalize_public_ipv4_csv() {
    local raw="$1"
    local token out="" seen=" "
    raw="${raw//,/ }"
    raw="${raw//;/ }"
    for token in ${raw}; do
        token="$(trim "${token}")"
        is_public_ipv4 "${token}" || continue
        [[ "${seen}" == *" ${token} "* ]] && continue
        seen+="${token} "
        if [[ -z "${out}" ]]; then
            out="${token}"
        else
            out+=",${token}"
        fi
    done
    [[ -n "${out}" ]] || return 1
    printf '%s\n' "${out}"
}

print_ipv4_csv_lines() {
    local csv="$1"
    local token
    csv="${csv//,/ }"
    for token in ${csv}; do
        token="$(trim "${token}")"
        is_public_ipv4 "${token}" && printf '%s\n' "${token}"
    done
}

ddns_result_public_ipv4_csv() {
    local result="$1"
    result="$(sanitize_allowlist_source_text "${result}")"
    case "${result}" in
        report:*)
            result="${result#report:}"
            ;;
        local:*)
            result="${result#local:}"
            ;;
        ERROR*|"")
            return 1
            ;;
    esac
    normalize_public_ipv4_csv "${result}"
}

iso_to_epoch_utc() {
    local iso="$1"
    [[ "${iso}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || return 1
    date -u -d "${iso}" '+%s' 2>/dev/null
}

ddns_report_is_fresh() {
    local resolved_at="$1"
    local ttl="$2"
    local result="$3"
    local resolved_epoch now age
    [[ "${result}" == report:* ]] || return 1
    ttl="$(normalize_source_ttl_seconds "${ttl}")"
    resolved_epoch="$(iso_to_epoch_utc "${resolved_at}")" || return 1
    now="$(date -u '+%s')"
    age=$((now - resolved_epoch))
    (( age >= 0 && age <= ttl ))
}

reported_ddns_ipv4_records() {
    local resolved_at="$1"
    local ttl="$2"
    local result="$3"
    local csv
    ddns_report_is_fresh "${resolved_at}" "${ttl}" "${result}" || return 1
    csv="$(ddns_result_public_ipv4_csv "${result}")" || return 1
    print_ipv4_csv_lines "${csv}"
}

replace_allowlist_entries_for_source_with_expiry_unlocked() {
    local set_id="$1"
    local source_type="$2"
    local source_value="$3"
    local note="$4"
    local expires_at="${5:-}"
    shift 5
    local cidr line tmp created_at normalized_type normalized_value normalized_note existing_seen=" " skipped=0 added=0
    local dynamic_mode=0 max_keep selected selected_count best_idx best_created idx found_idx
    local -a dynamic_cidrs=()
    local -a dynamic_notes=()
    local -a dynamic_created=()
    local -a dynamic_expires=()
    validate_allowlist_set_id "${set_id}" || return 1
    normalized_type="$(normalize_allowlist_entry_source_type "${source_type}")" || return 1
    normalized_value="$(sanitize_allowlist_entry_text "${source_value}")"
    normalized_note="$(sanitize_allowlist_entry_text "${note}")"
    expires_at="$(sanitize_allowlist_entry_text "${expires_at}")"
    dynamic_allowlist_source_type "${normalized_type}" && dynamic_mode=1
    ensure_allowlist_entries_file || return 1
    make_temp_file "${ALLOWLIST_ENTRIES_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    write_allowlist_entries_header "${tmp}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if parse_allowlist_entry_line "${line}"; then
            if [[ "${ALLOWLIST_ENTRY_SET_ID}" == "${set_id}" \
                && "${ALLOWLIST_ENTRY_SOURCE_TYPE}" == "${normalized_type}" \
                && "${ALLOWLIST_ENTRY_SOURCE_VALUE}" == "${normalized_value}" ]]; then
                if [[ "${dynamic_mode}" == "1" ]]; then
                    allowlist_entry_is_expired "${ALLOWLIST_ENTRY_EXPIRES_AT}" && continue
                    existing_seen+="${ALLOWLIST_ENTRY_CIDR} "
                    dynamic_cidrs+=("${ALLOWLIST_ENTRY_CIDR}")
                    dynamic_notes+=("${ALLOWLIST_ENTRY_NOTE}")
                    dynamic_created+=("${ALLOWLIST_ENTRY_CREATED_AT}")
                    dynamic_expires+=("${ALLOWLIST_ENTRY_EXPIRES_AT}")
                else
                    existing_seen+="${ALLOWLIST_ENTRY_CIDR} "
                fi
                continue
            fi
            printf '%s\n' "${PARSED_ALLOWLIST_ENTRY}" >> "${tmp}"
        elif [[ -n "$(trim "${line}")" && ! "$(trim "${line}")" =~ ^# ]]; then
            printf '%s\n' "${line}" >> "${tmp}"
        fi
    done < "${ALLOWLIST_ENTRIES_FILE}"
    created_at="$(utc_now_iso)"
    if [[ "${dynamic_mode}" == "1" ]]; then
        for cidr in "$@"; do
            cidr="$(normalize_ipv4_cidr_or_host "${cidr}")" || return 1
            if automation_mode_is_attack && auto_source_type_is_freezable "${normalized_type}" && [[ "${existing_seen}" != *" ${cidr} "* ]]; then
                queue_pending_auto_source "${normalized_type}" "${normalized_value}" "${cidr}" "${normalized_note}" || true
                ((skipped++))
                continue
            fi
            found_idx=-1
            for idx in "${!dynamic_cidrs[@]}"; do
                if [[ "${dynamic_cidrs[$idx]}" == "${cidr}" ]]; then
                    found_idx="${idx}"
                    break
                fi
            done
            if (( found_idx >= 0 )); then
                dynamic_notes[$found_idx]="${normalized_note}"
                dynamic_created[$found_idx]="${created_at}"
                dynamic_expires[$found_idx]="${expires_at}"
            else
                dynamic_cidrs+=("${cidr}")
                dynamic_notes+=("${normalized_note}")
                dynamic_created+=("${created_at}")
                dynamic_expires+=("${expires_at}")
            fi
            existing_seen+="${cidr} "
            ((added++))
        done
        max_keep="$(dynamic_allowlist_max_per_source "${normalized_type}")"
        selected=" "
        selected_count=0
        while (( selected_count < max_keep )); do
            best_idx=-1
            best_created=""
            for idx in "${!dynamic_cidrs[@]}"; do
                [[ "${selected}" == *" ${idx} "* ]] && continue
                [[ -n "${dynamic_cidrs[$idx]}" ]] || continue
                allowlist_entry_is_expired "${dynamic_expires[$idx]}" && continue
                if (( best_idx < 0 )) || [[ "${dynamic_created[$idx]}" > "${best_created}" ]]; then
                    best_idx="${idx}"
                    best_created="${dynamic_created[$idx]}"
                fi
            done
            (( best_idx >= 0 )) || break
            serialize_allowlist_entry "${set_id}" "${dynamic_cidrs[$best_idx]}" "${normalized_type}" "${normalized_value}" "${dynamic_notes[$best_idx]}" "${dynamic_created[$best_idx]}" "${dynamic_expires[$best_idx]}" \
                >> "${tmp}"
            selected+="${best_idx} "
            ((selected_count++))
        done
    else
        for cidr in "$@"; do
            cidr="$(normalize_ipv4_cidr_or_host "${cidr}")" || return 1
            if automation_mode_is_attack && auto_source_type_is_freezable "${normalized_type}" && [[ "${existing_seen}" != *" ${cidr} "* ]]; then
                queue_pending_auto_source "${normalized_type}" "${normalized_value}" "${cidr}" "${normalized_note}" || true
                ((skipped++))
                continue
            fi
            serialize_allowlist_entry "${set_id}" "${cidr}" "${normalized_type}" "${normalized_value}" "${normalized_note}" "${created_at}" "${expires_at}" \
                >> "${tmp}"
            ((added++))
        done
    fi
    mv -f "${tmp}" "${ALLOWLIST_ENTRIES_FILE}"
    DYNAMIC_REPORT_ADDED_COUNT="${added}"
    DYNAMIC_REPORT_PENDING_COUNT="${skipped}"
}

replace_allowlist_entries_for_source_with_expiry() {
    with_dynamic_state_lock replace_allowlist_entries_for_source_with_expiry_unlocked "$@"
}

replace_allowlist_entries_for_source() {
    local set_id="$1"
    local source_type="$2"
    local source_value="$3"
    local note="$4"
    shift 4
    replace_allowlist_entries_for_source_with_expiry "${set_id}" "${source_type}" "${source_value}" "${note}" "" "$@"
}

cleanup_dynamic_allowlist_entries_unlocked() {
    local line tmp dynamic_tmp sorted_tmp created key record count max_keep source_type
    local removed_expired=0 trimmed=0 kept_dynamic=0 kept_static=0
    declare -A group_counts=()
    ensure_allowlist_entries_file || return 1
    make_temp_file "${ALLOWLIST_ENTRIES_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    make_temp_file "${ALLOWLIST_ENTRIES_FILE}.dynamic" || return 1
    dynamic_tmp="${TEMP_FILE_RESULT}"
    make_temp_file "${ALLOWLIST_ENTRIES_FILE}.sorted" || return 1
    sorted_tmp="${TEMP_FILE_RESULT}"
    write_allowlist_entries_header "${tmp}"
    : > "${dynamic_tmp}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if parse_allowlist_entry_line "${line}"; then
            if dynamic_allowlist_source_type "${ALLOWLIST_ENTRY_SOURCE_TYPE}"; then
                if allowlist_entry_is_expired "${ALLOWLIST_ENTRY_EXPIRES_AT}"; then
                    ((removed_expired++))
                    continue
                fi
                created="${ALLOWLIST_ENTRY_CREATED_AT:-0000-00-00T00:00:00Z}"
                key="${ALLOWLIST_ENTRY_SOURCE_TYPE}|${ALLOWLIST_ENTRY_SOURCE_VALUE}"
                printf '%s\t%s\t%s\n' "${created}" "${key}" "${PARSED_ALLOWLIST_ENTRY}" >> "${dynamic_tmp}"
            else
                printf '%s\n' "${PARSED_ALLOWLIST_ENTRY}" >> "${tmp}"
                ((kept_static++))
            fi
        elif [[ -n "$(trim "${line}")" && ! "$(trim "${line}")" =~ ^# ]]; then
            printf '%s\n' "${line}" >> "${tmp}"
        fi
    done < "${ALLOWLIST_ENTRIES_FILE}"
    sort -r "${dynamic_tmp}" > "${sorted_tmp}"
    while IFS=$'\t' read -r created key record || [[ -n "${record:-}" ]]; do
        [[ -n "${record:-}" ]] || continue
        source_type="${key%%|*}"
        max_keep="$(dynamic_allowlist_max_per_source "${source_type}")"
        count="${group_counts[$key]:-0}"
        if (( count < max_keep )); then
            printf '%s\n' "${record}" >> "${tmp}"
            group_counts[$key]=$((count + 1))
            ((kept_dynamic++))
        else
            ((trimmed++))
        fi
    done < "${sorted_tmp}"
    mv -f "${tmp}" "${ALLOWLIST_ENTRIES_FILE}"
    printf '动态来源清理完成：保留动态 %s 条，保留静态 %s 条，删除过期 %s 条，裁剪超量 %s 条；%s。\n' \
        "${kept_dynamic}" "${kept_static}" "${removed_expired}" "${trimmed}" "$(dynamic_allowlist_limits_label)"
}

cleanup_dynamic_allowlist_entries() {
    with_dynamic_state_lock cleanup_dynamic_allowlist_entries_unlocked "$@"
}

do_cleanup_dynamic_allowlist() {
    ensure_layout || return 1
    load_settings 1
    cleanup_dynamic_allowlist_entries || return 1
    if src_allowlist_enabled; then
        write_nft_conf || return 1
        save_settings || return 1
        apply_or_save_notice "动态来源清理已应用。" "动态来源清理已保存到托管配置。"
    fi
}

remove_allowlist_entries_for_source_unlocked() {
    local set_id="$1"
    local source_type="$2"
    local source_value="$3"
    local line tmp normalized_type normalized_value
    validate_allowlist_set_id "${set_id}" || return 1
    normalized_type="$(normalize_allowlist_entry_source_type "${source_type}")" || return 1
    normalized_value="$(sanitize_allowlist_entry_text "${source_value}")"
    ensure_allowlist_entries_file || return 1
    make_temp_file "${ALLOWLIST_ENTRIES_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    write_allowlist_entries_header "${tmp}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if parse_allowlist_entry_line "${line}"; then
            if [[ "${ALLOWLIST_ENTRY_SET_ID}" == "${set_id}" \
                && "${ALLOWLIST_ENTRY_SOURCE_TYPE}" == "${normalized_type}" \
                && "${ALLOWLIST_ENTRY_SOURCE_VALUE}" == "${normalized_value}" ]]; then
                continue
            fi
            printf '%s\n' "${PARSED_ALLOWLIST_ENTRY}" >> "${tmp}"
        elif [[ -n "$(trim "${line}")" && ! "$(trim "${line}")" =~ ^# ]]; then
            printf '%s\n' "${line}" >> "${tmp}"
        fi
    done < "${ALLOWLIST_ENTRIES_FILE}"
    mv -f "${tmp}" "${ALLOWLIST_ENTRIES_FILE}"
}

remove_allowlist_entries_for_source() {
    with_dynamic_state_lock remove_allowlist_entries_for_source_unlocked "$@"
}

sync_ddns_entries_removed() {
    local set_id="$1"
    local name="$2"
    local value="$3"
    remove_allowlist_entries_for_source "${set_id}" "ddns" "${value}" || return 1
    if [[ "${name}" != "${value}" ]]; then
        remove_allowlist_entries_for_source "${set_id}" "ddns" "${name}" || return 1
    fi
}

ensure_ddns_report_token() {
    local token
    mkdir -p "${CONF_DIR}" || return 1
    if [[ ! -s "${DDNS_REPORT_TOKEN_FILE}" ]]; then
        if command -v openssl &>/dev/null; then
            token="$(openssl rand -hex 24 2>/dev/null || true)"
        fi
        if [[ -z "${token:-}" ]]; then
            token="$(date '+%s')-$RANDOM-$RANDOM-$RANDOM"
        fi
        printf '%s\n' "${token}" > "${DDNS_REPORT_TOKEN_FILE}" || return 1
        chmod 600 "${DDNS_REPORT_TOKEN_FILE}" 2>/dev/null || true
    fi
}

ddns_report_token_value() {
    ensure_ddns_report_token || return 1
    tr -d '[:space:]' < "${DDNS_REPORT_TOKEN_FILE}"
}

validate_ddns_report_token() {
    local provided="${1:-}"
    local expected
    [[ -f "${DDNS_REPORT_TOKEN_FILE}" ]] || return 0
    expected="$(ddns_report_token_value)" || return 1
    [[ -n "${expected}" && "${provided}" == "${expected}" ]]
}

validate_ddns_report_token_readonly() {
    local provided="${1:-}"
    local expected
    [[ -s "${DDNS_REPORT_TOKEN_FILE}" ]] || return 0
    expected="$(tr -d '[:space:]' < "${DDNS_REPORT_TOKEN_FILE}")" || return 1
    [[ -n "${expected}" && "${provided}" == "${expected}" ]]
}

ensure_token_file() {
    local path="$1"
    local token=""
    mkdir -p "${CONF_DIR}" || return 1
    if [[ ! -s "${path}" ]]; then
        if command -v openssl &>/dev/null; then
            token="$(openssl rand -hex 24 2>/dev/null || true)"
        fi
        if [[ -z "${token}" ]]; then
            token="$(date '+%s')-$RANDOM-$RANDOM-$RANDOM"
        fi
        printf '%s\n' "${token}" > "${path}" || return 1
        chmod 600 "${path}" 2>/dev/null || true
    fi
}

token_file_value() {
    local path="$1"
    ensure_token_file "${path}" || return 1
    tr -d '[:space:]' < "${path}"
}

token_file_matches() {
    local path="$1"
    local provided="${2:-}"
    local expected
    [[ -s "${path}" ]] || return 0
    expected="$(tr -d '[:space:]' < "${path}")" || return 1
    [[ -n "${expected}" && "${provided}" == "${expected}" ]]
}

client_ip_report_token_value() {
    token_file_value "${CLIENT_IP_REPORT_TOKEN_FILE}"
}

validate_client_ip_report_token() {
    token_file_matches "${CLIENT_IP_REPORT_TOKEN_FILE}" "${1:-}"
}

ssh_report_token_value() {
    token_file_value "${SSH_REPORT_TOKEN_FILE}"
}

validate_ssh_report_token() {
    token_file_matches "${SSH_REPORT_TOKEN_FILE}" "${1:-}"
}

webauth_report_token_value() {
    token_file_value "${WEBAUTH_REPORT_TOKEN_FILE}"
}

validate_webauth_report_token() {
    token_file_matches "${WEBAUTH_REPORT_TOKEN_FILE}" "${1:-}"
}

write_ddns_report_stats_header() {
    local path="$1"
    cat > "${path}" <<'EOF'
# Managed by nftables relay manager
# format: key|accepted_count|rejected_count|last_status|last_at|last_ips|last_error
EOF
}
