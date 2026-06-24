src_allowlist_enabled() {
    [[ "${ENABLE_SRC_ALLOWLIST}" == "1" ]] || return 1
    case "${SRC_ALLOWLIST_MODE}" in
        manual_only|trusted_dynamic|custom_sources)
            custom_allowlist_has_entries
            ;;
        region_plus_trusted)
            [[ -n "${SRC_ALLOWLIST_REGION_IDS}" ]] || custom_allowlist_has_entries
            ;;
        region_only)
            [[ -n "${SRC_ALLOWLIST_REGION_IDS}" ]]
            ;;
        *)
            custom_allowlist_has_entries
            ;;
    esac
}

validate_src_allowlist_ready() {
    [[ "${ENABLE_SRC_ALLOWLIST}" == "1" ]] || return 0
    case "${SRC_ALLOWLIST_MODE}" in
        manual_only|trusted_dynamic|custom_sources)
            custom_allowlist_has_entries || {
                err "$(src_allowlist_mode_to_label "${SRC_ALLOWLIST_MODE}") 没有任何可用 CIDR。"
                return 1
            }
            ;;
        region_plus_trusted)
            [[ -n "${SRC_ALLOWLIST_REGION_IDS}" ]] || custom_allowlist_has_entries || {
                err "地区 + 可信动态来源模式没有任何地区或可信来源 CIDR。"
                return 1
            }
            ;;
        region_only)
            [[ -n "${SRC_ALLOWLIST_REGION_IDS}" ]] || {
                err "仅地区库模式未选择任何地区。"
                return 1
            }
            ;;
        *)
            custom_allowlist_has_entries || {
                err "白名单没有任何可用 CIDR。"
                return 1
            }
            ;;
    esac
}

src_allowlist_region_count() {
    local count=0 id
    for id in ${SRC_ALLOWLIST_REGION_IDS}; do
        [[ -n "${id}" ]] && ((count++))
    done
    printf '%s\n' "${count}"
}

sanitize_custom_note() {
    local note="$1"
    note="${note//$'\t'/ }"
    note="${note//$'\r'/ }"
    note="${note//$'\n'/ }"
    note="${note//|//}"
    note="$(trim "${note}")"
    [[ ${#note} -le 80 ]] || note="${note:0:80}"
    printf '%s\n' "${note}"
}

custom_allowlist_line_is_data() {
    local line="$1"
    line="${line%$'\r'}"
    line="$(trim "${line}")"
    [[ -n "${line}" && ! "${line}" =~ ^# ]]
}

parse_custom_allowlist_line() {
    local line="$1"
    local cidr note
    CUSTOM_ALLOWLIST_CIDR=""
    CUSTOM_ALLOWLIST_NOTE=""
    custom_allowlist_line_is_data "${line}" || return 1
    line="${line%$'\r'}"
    line="$(trim "${line}")"
    cidr="${line%%|*}"
    if [[ "${line}" == *"|"* ]]; then
        note="${line#*|}"
    else
        note=""
    fi
    cidr="$(normalize_ipv4_cidr_or_host "${cidr}")" || return 1
    CUSTOM_ALLOWLIST_CIDR="${cidr}"
    CUSTOM_ALLOWLIST_NOTE="$(sanitize_custom_note "${note}")"
}

custom_allowlist_count() {
    local line count=0
    [[ -f "${CUSTOM_SRC_ALLOWLIST_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_custom_allowlist_line "${line}" || continue
        ((count++))
    done < "${CUSTOM_SRC_ALLOWLIST_FILE}"
    printf '%s\n' "${count}"
}

custom_allowlist_count_for_file() {
    local file="$1"
    local line count=0
    [[ -f "${file}" ]] || {
        printf '0\n'
        return 0
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_custom_allowlist_line "${line}" || continue
        ((count++))
    done < "${file}"
    printf '%s\n' "${count}"
}

custom_allowlist_has_entries() {
    [[ "$(custom_allowlist_count)" -gt 0 || "$(allowlist_active_entries_count_for_mode default)" -gt 0 ]]
}

custom_allowlist_contains_cidr() {
    local target="$1"
    local line
    target="$(normalize_ipv4_cidr_or_host "${target}")" || return 1
    [[ -f "${CUSTOM_SRC_ALLOWLIST_FILE}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_custom_allowlist_line "${line}" || continue
        [[ "${CUSTOM_ALLOWLIST_CIDR}" == "${target}" ]] && return 0
    done < "${CUSTOM_SRC_ALLOWLIST_FILE}"
    return 1
}

add_custom_allowlist_entry() {
    local cidr="$1"
    local note="${2:-}"
    local prefix
    cidr="$(normalize_ipv4_cidr_or_host "${cidr}")" || {
        err "CIDR/IP 无效：${cidr}"
        return 1
    }
    note="$(sanitize_custom_note "${note}")"
    custom_allowlist_contains_cidr "${cidr}" && {
        warn "自定义白名单已存在：${cidr}"
        return 0
    }
    mkdir -p "${CONF_DIR}" || return 1
    if [[ ! -f "${CUSTOM_SRC_ALLOWLIST_FILE}" ]]; then
        cat > "${CUSTOM_SRC_ALLOWLIST_FILE}" <<'EOF'
# format: cidr_or_ip|note
# examples:
# 203.0.113.10|home router, observed manually
# 203.0.113.0/24|home ISP candidate, confirm before using
EOF
    fi
    if [[ -n "${note}" ]]; then
        printf '%s|%s\n' "${cidr}" "${note}" >> "${CUSTOM_SRC_ALLOWLIST_FILE}"
    else
        printf '%s\n' "${cidr}" >> "${CUSTOM_SRC_ALLOWLIST_FILE}"
    fi
    append_allowlist_entry "default" "${cidr}" "manual" "" "${note}" "" || return 1
    prefix="$(cidr_prefix_length "${cidr}")"
    if (( prefix < 24 )); then
        warn "已加入较宽网段 ${cidr}；建议确认它确实只覆盖可信来源。"
    fi
}

remove_custom_allowlist_entry() {
    local target="$1"
    local line tmp removed=0
    target="$(normalize_ipv4_cidr_or_host "${target}")" || return 1
    [[ -f "${CUSTOM_SRC_ALLOWLIST_FILE}" ]] || return 1
    make_temp_file "${CUSTOM_SRC_ALLOWLIST_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if parse_custom_allowlist_line "${line}" && [[ "${CUSTOM_ALLOWLIST_CIDR}" == "${target}" ]]; then
            removed=1
            continue
        fi
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${CUSTOM_SRC_ALLOWLIST_FILE}"
    mv -f "${tmp}" "${CUSTOM_SRC_ALLOWLIST_FILE}"
    remove_allowlist_entries_for_cidr "default" "${target}" || true
    [[ "${removed}" == "1" ]]
}

show_custom_allowlist_entries() {
    local line idx=1
    if [[ ! -f "${CUSTOM_SRC_ALLOWLIST_FILE}" ]] || ! custom_allowlist_has_entries; then
        echo "  (未添加自定义 CIDR)"
        return 0
    fi
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_custom_allowlist_line "${line}" || continue
        if [[ -n "${CUSTOM_ALLOWLIST_NOTE}" ]]; then
            printf '  %2d) %-18s %s\n' "${idx}" "${CUSTOM_ALLOWLIST_CIDR}" "${CUSTOM_ALLOWLIST_NOTE}"
        else
            printf '  %2d) %s\n' "${idx}" "${CUSTOM_ALLOWLIST_CIDR}"
        fi
        ((idx++))
    done < "${CUSTOM_SRC_ALLOWLIST_FILE}"
}

validate_allowlist_profile_name() {
    local name="$1"
    [[ "${name}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || {
        err "配置档案名称只能使用字母、数字、点、下划线、短横线，且必须以字母或数字开头，最长 64 个字符。"
        return 1
    }
}

sanitize_profile_label() {
    local label="$1"
    label="${label//$'\t'/ }"
    label="${label//$'\r'/ }"
    label="${label//$'\n'/ }"
    label="$(trim "${label}")"
    [[ ${#label} -le 80 ]] || label="${label:0:80}"
    printf '%s\n' "${label}"
}

generate_allowlist_profile_id() {
    local id
    while true; do
        if command -v uuidgen >/dev/null 2>&1; then
            id="$(uuidgen 2>/dev/null || true)"
        elif [[ -r /proc/sys/kernel/random/uuid ]]; then
            IFS= read -r id < /proc/sys/kernel/random/uuid || id=""
        else
            id="$(date -u '+%Y%m%d%H%M%S')-${RANDOM}-${RANDOM}"
        fi
        id="p-${id,,}"
        validate_allowlist_profile_name "${id}" >/dev/null 2>&1 || continue
        allowlist_profile_exists "${id}" || {
            printf '%s\n' "${id}"
            return 0
        }
    done
}

allowlist_profile_env_file() {
    local name="$1"
    printf '%s/%s.env\n' "${ALLOWLIST_PROFILE_DIR}" "${name}"
}

allowlist_profile_label_file() {
    local name="$1"
    printf '%s/%s.label.txt\n' "${ALLOWLIST_PROFILE_DIR}" "${name}"
}

allowlist_profile_custom_file() {
    local name="$1"
    printf '%s/%s.custom.txt\n' "${ALLOWLIST_PROFILE_DIR}" "${name}"
}

allowlist_profile_sets_file() {
    local name="$1"
    printf '%s/%s.sets.tsv\n' "${ALLOWLIST_PROFILE_DIR}" "${name}"
}

allowlist_profile_entries_file() {
    local name="$1"
    printf '%s/%s.entries.tsv\n' "${ALLOWLIST_PROFILE_DIR}" "${name}"
}

allowlist_profile_sources_file() {
    local name="$1"
    printf '%s/%s.sources.tsv\n' "${ALLOWLIST_PROFILE_DIR}" "${name}"
}

allowlist_profile_exists() {
    local name="$1"
    [[ -f "$(allowlist_profile_env_file "${name}")" ]]
}

allowlist_profile_count() {
    local file name count=0
    [[ -d "${ALLOWLIST_PROFILE_DIR}" ]] || {
        printf '0\n'
        return 0
    }
    for file in "${ALLOWLIST_PROFILE_DIR}"/*.env; do
        [[ -f "${file}" ]] || continue
        name="$(basename "${file}" .env)"
        [[ "${name}" == "${ALLOWLIST_LAST_PROFILE_NAME}" ]] && continue
        ((count++))
    done
    printf '%s\n' "${count}"
}

save_allowlist_profile_state() {
    local name="$1"
    local quiet="${2:-0}"
    local label="${3:-}"
    local env_file label_file custom_file sets_file entries_file sources_file tmp saved_at
    mkdir -p "${ALLOWLIST_PROFILE_DIR}" || return 1
    env_file="$(allowlist_profile_env_file "${name}")"
    label_file="$(allowlist_profile_label_file "${name}")"
    custom_file="$(allowlist_profile_custom_file "${name}")"
    sets_file="$(allowlist_profile_sets_file "${name}")"
    entries_file="$(allowlist_profile_entries_file "${name}")"
    sources_file="$(allowlist_profile_sources_file "${name}")"
    saved_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    label="$(sanitize_profile_label "${label}")"
    ENABLE_SRC_ALLOWLIST="$([[ "${ENABLE_SRC_ALLOWLIST}" == "1" ]] && printf '1' || printf '0')"
    SRC_ALLOWLIST_MODE="$(normalize_src_allowlist_mode "${SRC_ALLOWLIST_MODE}" 2>/dev/null || printf 'trusted_dynamic')"
    SRC_ALLOWLIST_REGION_IDS="$(normalize_region_ids "${SRC_ALLOWLIST_REGION_IDS}")"
    load_allowlist_sets

    make_temp_file "${env_file}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    cat > "${tmp}" <<EOF
PROFILE_FORMAT_VERSION="1"
PROFILE_SAVED_AT="${saved_at}"
ENABLE_SRC_ALLOWLIST="${ENABLE_SRC_ALLOWLIST}"
SRC_ALLOWLIST_MODE="${SRC_ALLOWLIST_MODE}"
SRC_ALLOWLIST_REGION_IDS="${SRC_ALLOWLIST_REGION_IDS}"
EOF
    mv -f "${tmp}" "${env_file}"

    make_temp_file "${label_file}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    printf '%s\n' "${label}" > "${tmp}"
    mv -f "${tmp}" "${label_file}"

    make_temp_file "${custom_file}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    if [[ -f "${CUSTOM_SRC_ALLOWLIST_FILE}" ]]; then
        cp -- "${CUSTOM_SRC_ALLOWLIST_FILE}" "${tmp}" || return 1
    else
        cat > "${tmp}" <<'EOF'
# format: cidr_or_ip|note
EOF
    fi
    mv -f "${tmp}" "${custom_file}"

    make_temp_file "${sets_file}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    write_allowlist_sets_file "${tmp}" || return 1
    mv -f "${tmp}" "${sets_file}"

    make_temp_file "${entries_file}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    if [[ -f "${ALLOWLIST_ENTRIES_FILE}" ]]; then
        cp -- "${ALLOWLIST_ENTRIES_FILE}" "${tmp}" || return 1
    else
        write_allowlist_entries_header "${tmp}"
    fi
    mv -f "${tmp}" "${entries_file}"

    make_temp_file "${sources_file}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    if [[ -f "${ALLOWLIST_SOURCES_FILE}" ]]; then
        cp -- "${ALLOWLIST_SOURCES_FILE}" "${tmp}" || return 1
    else
        write_allowlist_sources_header "${tmp}"
    fi
    mv -f "${tmp}" "${sources_file}"
    [[ "${quiet}" == "1" ]] || success "白名单配置档案已保存：${label:-${name}}"
}

save_allowlist_last_snapshot() {
    save_allowlist_profile_state "${ALLOWLIST_LAST_PROFILE_NAME}" 1 ""
}

read_allowlist_profile_metadata() {
    local name="$1"
    local env_file label_file line key raw_value value
    PROFILE_ENABLE_SRC_ALLOWLIST=""
    PROFILE_SRC_ALLOWLIST_MODE=""
    PROFILE_SRC_ALLOWLIST_REGION_IDS=""
    PROFILE_SAVED_AT=""
    PROFILE_LABEL=""
    env_file="$(allowlist_profile_env_file "${name}")"
    label_file="$(allowlist_profile_label_file "${name}")"
    [[ -f "${env_file}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        line="$(trim "${line}")"
        [[ -z "${line}" || "${line}" =~ ^# || "${line}" != *=* ]] && continue
        key="$(trim "${line%%=*}")"
        raw_value="${line#*=}"
        value="$(unquote_setting_value "${raw_value}")"
        case "${key}" in
            PROFILE_LABEL)
                PROFILE_LABEL="$(sanitize_profile_label "${value}")"
                ;;
            PROFILE_SAVED_AT)
                PROFILE_SAVED_AT="${value}"
                ;;
            ENABLE_SRC_ALLOWLIST)
                PROFILE_ENABLE_SRC_ALLOWLIST="${value}"
                ;;
            SRC_ALLOWLIST_MODE)
                PROFILE_SRC_ALLOWLIST_MODE="${value}"
                ;;
            SRC_ALLOWLIST_REGION_IDS)
                PROFILE_SRC_ALLOWLIST_REGION_IDS="${value}"
                ;;
        esac
    done < "${env_file}"
    if [[ -f "${label_file}" ]]; then
        IFS= read -r line < "${label_file}" || line=""
        PROFILE_LABEL="$(sanitize_profile_label "${line}")"
    fi
    [[ "${PROFILE_ENABLE_SRC_ALLOWLIST}" == "0" || "${PROFILE_ENABLE_SRC_ALLOWLIST}" == "1" ]] || PROFILE_ENABLE_SRC_ALLOWLIST="0"
    PROFILE_SRC_ALLOWLIST_MODE="$(normalize_src_allowlist_mode "${PROFILE_SRC_ALLOWLIST_MODE}" 2>/dev/null || printf 'trusted_dynamic')"
    PROFILE_SRC_ALLOWLIST_REGION_IDS="$(normalize_region_ids "${PROFILE_SRC_ALLOWLIST_REGION_IDS}")"
}

print_allowlist_profile_summary() {
    local name="$1"
    local display_name="${2:-$1}"
    local custom_file custom_count status_label saved_label
    read_allowlist_profile_metadata "${name}" || return 1
    if [[ -n "${PROFILE_LABEL}" && "${name}" != "${ALLOWLIST_LAST_PROFILE_NAME}" ]]; then
        display_name="${PROFILE_LABEL} (${name})"
    fi
    custom_file="$(allowlist_profile_custom_file "${name}")"
    custom_count="$(custom_allowlist_count_for_file "${custom_file}")"
    if [[ "${PROFILE_ENABLE_SRC_ALLOWLIST}" == "1" ]]; then
        status_label="$(src_allowlist_mode_to_label "${PROFILE_SRC_ALLOWLIST_MODE}")"
    else
        status_label="关闭"
    fi
    saved_label="${PROFILE_SAVED_AT:-未知时间}"
    printf '  - %-18s %s，地区 %s / 自定义 %s，保存于 %s\n' \
        "${display_name}" \
        "${status_label}" \
        "$(printf '%s\n' "${PROFILE_SRC_ALLOWLIST_REGION_IDS}" | wc -w | tr -d '[:space:]')" \
        "${custom_count}" \
        "${saved_label}"
}

show_allowlist_profiles() {
    local file name found=0
    if [[ ! -d "${ALLOWLIST_PROFILE_DIR}" ]]; then
        echo "  (未保存白名单配置档案)"
        return 0
    fi
    for file in "${ALLOWLIST_PROFILE_DIR}"/*.env; do
        [[ -f "${file}" ]] || continue
        name="$(basename "${file}" .env)"
        [[ "${name}" == "${ALLOWLIST_LAST_PROFILE_NAME}" ]] && continue
        print_allowlist_profile_summary "${name}" || continue
        found=1
    done
    [[ "${found}" == "1" ]] || echo "  (未保存白名单配置档案)"
    if allowlist_profile_exists "${ALLOWLIST_LAST_PROFILE_NAME}"; then
        echo "上一次快照:"
        print_allowlist_profile_summary "${ALLOWLIST_LAST_PROFILE_NAME}" "last" || true
    fi
}

select_allowlist_profile() {
    local file name choice idx=1 summary
    local -a names=()
    SELECTED_ALLOWLIST_PROFILE=""
    [[ -d "${ALLOWLIST_PROFILE_DIR}" ]] || {
        err "当前没有白名单配置档案。"
        return 1
    }
    for file in "${ALLOWLIST_PROFILE_DIR}"/*.env; do
        [[ -f "${file}" ]] || continue
        name="$(basename "${file}" .env)"
        [[ "${name}" == "${ALLOWLIST_LAST_PROFILE_NAME}" ]] && continue
        names+=("${name}")
    done
    [[ ${#names[@]} -gt 0 ]] || {
        err "当前没有白名单配置档案。"
        return 1
    }
    for name in "${names[@]}"; do
        summary="$(print_allowlist_profile_summary "${name}")"
        summary="${summary#  - }"
        printf '  %2d) %s\n' "${idx}" "${summary}"
        ((idx++))
    done
    choice="$(read_prompt "请选择配置档案 [1-${#names[@]}]: ")" || return 1
    [[ "${choice}" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= ${#names[@]} )) || return 1
    SELECTED_ALLOWLIST_PROFILE="${names[$((choice - 1))]}"
}

apply_allowlist_profile() {
    local name="$1"
    local save_last="${2:-1}"
    local custom_file sets_file entries_file sources_file tmp
    read_allowlist_profile_metadata "${name}" || {
        err "配置档案不存在：${name}"
        return 1
    }
    if [[ "${save_last}" == "1" ]]; then
        save_allowlist_last_snapshot || return 1
    fi
    ENABLE_SRC_ALLOWLIST="${PROFILE_ENABLE_SRC_ALLOWLIST}"
    SRC_ALLOWLIST_MODE="${PROFILE_SRC_ALLOWLIST_MODE}"
    SRC_ALLOWLIST_REGION_IDS="${PROFILE_SRC_ALLOWLIST_REGION_IDS}"
    SETTINGS_CACHE_READY="1"
    custom_file="$(allowlist_profile_custom_file "${name}")"
    make_temp_file "${CUSTOM_SRC_ALLOWLIST_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    if [[ -f "${custom_file}" ]]; then
        cp -- "${custom_file}" "${tmp}" || return 1
    else
        cat > "${tmp}" <<'EOF'
# format: cidr_or_ip|note
EOF
    fi
    mv -f "${tmp}" "${CUSTOM_SRC_ALLOWLIST_FILE}"

    sets_file="$(allowlist_profile_sets_file "${name}")"
    if [[ -f "${sets_file}" ]]; then
        make_temp_file "${ALLOWLIST_SETS_FILE}" || return 1
        tmp="${TEMP_FILE_RESULT}"
        cp -- "${sets_file}" "${tmp}" || return 1
        mv -f "${tmp}" "${ALLOWLIST_SETS_FILE}"
        ALLOWLIST_SETS_CACHE_READY="0"
        load_allowlist_sets 1
    else
        ALLOWLIST_SETS=("$(default_allowlist_set_record)")
        ALLOWLIST_SETS_CACHE_READY="1"
        save_allowlist_sets || return 1
    fi

    entries_file="$(allowlist_profile_entries_file "${name}")"
    if [[ -f "${entries_file}" ]]; then
        make_temp_file "${ALLOWLIST_ENTRIES_FILE}" || return 1
        tmp="${TEMP_FILE_RESULT}"
        cp -- "${entries_file}" "${tmp}" || return 1
        mv -f "${tmp}" "${ALLOWLIST_ENTRIES_FILE}"
    else
        make_temp_file "${ALLOWLIST_ENTRIES_FILE}" || return 1
        tmp="${TEMP_FILE_RESULT}"
        write_allowlist_entries_header "${tmp}"
        mv -f "${tmp}" "${ALLOWLIST_ENTRIES_FILE}"
    fi

    sources_file="$(allowlist_profile_sources_file "${name}")"
    if [[ -f "${sources_file}" ]]; then
        make_temp_file "${ALLOWLIST_SOURCES_FILE}" || return 1
        tmp="${TEMP_FILE_RESULT}"
        cp -- "${sources_file}" "${tmp}" || return 1
        mv -f "${tmp}" "${ALLOWLIST_SOURCES_FILE}"
    else
        make_temp_file "${ALLOWLIST_SOURCES_FILE}" || return 1
        tmp="${TEMP_FILE_RESULT}"
        write_allowlist_sources_header "${tmp}"
        mv -f "${tmp}" "${ALLOWLIST_SOURCES_FILE}"
    fi

    apply_src_allowlist_changes
}

learning_service_status_label() {
    if ! command -v systemctl &>/dev/null; then
        printf '不可用（无 systemctl）'
        return 0
    fi
    if systemctl is-active --quiet "${LEARN_SERVICE_NAME}" 2>/dev/null; then
        printf '运行中'
    elif systemctl is-enabled --quiet "${LEARN_SERVICE_NAME}" 2>/dev/null; then
        printf '已安装，未运行'
    elif [[ -f "${LEARN_SERVICE_FILE}" ]]; then
        printf '已安装，未启用'
    else
        printf '未安装'
    fi
}

learning_log_count() {
    [[ -f "${LEARN_LOG_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    awk -F '\t' 'NF >= 10 { count++ } END { print count + 0 }' "${LEARN_LOG_FILE}" 2>/dev/null
}

learning_summary_count() {
    [[ -f "${LEARN_SUMMARY_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    awk -F '\t' 'NF >= 11 && $1 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ { count++ } END { print count + 0 }' "${LEARN_SUMMARY_FILE}" 2>/dev/null
}

learning_log_line_count() {
    [[ -f "${LEARN_LOG_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    wc -l < "${LEARN_LOG_FILE}" 2>/dev/null | tr -d '[:space:]'
}

learning_log_size_bytes() {
    [[ -f "${LEARN_LOG_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    wc -c < "${LEARN_LOG_FILE}" 2>/dev/null | tr -d '[:space:]'
}

format_bytes() {
    local bytes="$1"
    [[ "${bytes}" =~ ^[0-9]+$ ]] || bytes=0
    if (( bytes >= 1048576 )); then
        printf '%s MiB' "$(((bytes + 524288) / 1048576))"
    elif (( bytes >= 1024 )); then
        printf '%s KiB' "$(((bytes + 512) / 1024))"
    else
        printf '%s B' "${bytes}"
    fi
}

format_seconds() {
    local seconds="$1"
    [[ "${seconds}" =~ ^[0-9]+$ ]] || seconds=0
    if (( seconds >= 86400 )); then
        printf '%sd%02sh' "$((seconds / 86400))" "$(((seconds % 86400) / 3600))"
    elif (( seconds >= 3600 )); then
        printf '%sh%02sm' "$((seconds / 3600))" "$(((seconds % 3600) / 60))"
    elif (( seconds >= 60 )); then
        printf '%sm%02ss' "$((seconds / 60))" "$((seconds % 60))"
    else
        printf '%ss' "${seconds}"
    fi
}

format_learn_time() {
    local iso="$1"
    iso="${iso%Z}"
    iso="${iso/T/ }"
    printf '%s UTC' "${iso}"
}

tsv_safe() {
    local value="$1"
    value="${value//$'\t'/ }"
    value="${value//$'\r'/ }"
    value="${value//$'\n'/ }"
    printf '%s\n' "${value}"
}
