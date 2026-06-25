show_ddns_allowlist_sources() {
    local line idx=1 status
    ensure_allowlist_sources_file || return 1
    if [[ "$(allowlist_sources_count)" == "0" ]]; then
        echo "  (尚未添加 DDNS 来源)"
        return 0
    fi
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_source_line "${line}" || continue
        if [[ "${ALLOWLIST_SOURCE_ENABLED}" == "1" ]]; then
            status="启用"
        else
            status="停用"
        fi
        printf '  %2d) %-4s %-16s 域名=%s TTL=%ss 上次=%s 结果=%s\n' \
            "${idx}" "${status}" "${ALLOWLIST_SOURCE_NAME}" "${ALLOWLIST_SOURCE_VALUE}" \
            "${ALLOWLIST_SOURCE_TTL_SECONDS}" "${ALLOWLIST_SOURCE_LAST_RESOLVED_AT:-从未}" \
            "${ALLOWLIST_SOURCE_LAST_RESULT:-无}"
        print_ddns_report_stats_line "${ALLOWLIST_SOURCE_VALUE}"
        ((idx++))
    done < "${ALLOWLIST_SOURCES_FILE}"
}

select_ddns_allowlist_source() {
    local line choice idx=1
    local -a sources=()
    ensure_allowlist_sources_file || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_source_line "${line}" || continue
        sources+=("${PARSED_ALLOWLIST_SOURCE}")
    done < "${ALLOWLIST_SOURCES_FILE}"
    [[ ${#sources[@]} -gt 0 ]] || {
        err "当前没有 DDNS 来源。"
        return 1
    }
    show_ddns_allowlist_sources
    choice="$(read_prompt "请选择 DDNS 来源 [1-${#sources[@]}]: ")" || return 1
    [[ "${choice}" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= ${#sources[@]} )) || return 1
    parse_allowlist_source_line "${sources[$((choice - 1))]}"
}

append_ddns_allowlist_source() {
    local name="$1"
    local domain="$2"
    local ttl="$3"
    local enabled="$4"
    local line
    name="$(sanitize_allowlist_source_text "${name}")"
    domain="$(sanitize_allowlist_source_text "${domain}")"
    ttl="$(normalize_source_ttl_seconds "${ttl}")"
    [[ "${enabled}" == "0" || "${enabled}" == "1" ]] || enabled="1"
    [[ -n "${name}" ]] || name="${domain}"
    validate_ddns_domain "${domain}" || return 1
    ensure_allowlist_sources_file || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_source_line "${line}" || continue
        if [[ "${ALLOWLIST_SOURCE_SET_ID}" == "default" \
            && ("${ALLOWLIST_SOURCE_NAME}" == "${name}" || "${ALLOWLIST_SOURCE_VALUE}" == "${domain}") ]]; then
            err "DDNS 来源已存在：${name} / ${domain}"
            return 1
        fi
    done < "${ALLOWLIST_SOURCES_FILE}"
    serialize_allowlist_source "default" "ddns" "${name}" "${domain}" "${enabled}" "${ttl}" "" "" >> "${ALLOWLIST_SOURCES_FILE}"
}

rewrite_selected_ddns_source() {
    local old_set="$1"
    local old_name="$2"
    local old_value="$3"
    local replacement="${4:-}"
    local line tmp
    ensure_allowlist_sources_file || return 1
    make_temp_file "${ALLOWLIST_SOURCES_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    write_allowlist_sources_header "${tmp}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if parse_allowlist_source_line "${line}"; then
            if [[ "${ALLOWLIST_SOURCE_SET_ID}" == "${old_set}" \
                && "${ALLOWLIST_SOURCE_NAME}" == "${old_name}" \
                && "${ALLOWLIST_SOURCE_VALUE}" == "${old_value}" ]]; then
                [[ -n "${replacement}" ]] && printf '%s\n' "${replacement}" >> "${tmp}"
                continue
            fi
            printf '%s\n' "${PARSED_ALLOWLIST_SOURCE}" >> "${tmp}"
        elif [[ -n "$(trim "${line}")" && ! "$(trim "${line}")" =~ ^# ]]; then
            printf '%s\n' "${line}" >> "${tmp}"
        fi
    done < "${ALLOWLIST_SOURCES_FILE}"
    mv -f "${tmp}" "${ALLOWLIST_SOURCES_FILE}"
}

disable_src_allowlist_if_no_custom_entries() {
    case "${SRC_ALLOWLIST_MODE}" in
        manual_only|trusted_dynamic|custom_sources)
            custom_allowlist_has_entries || ENABLE_SRC_ALLOWLIST="0"
            ;;
        region_plus_trusted)
            [[ -n "${SRC_ALLOWLIST_REGION_IDS}" ]] || custom_allowlist_has_entries || ENABLE_SRC_ALLOWLIST="0"
            ;;
        region_only)
            [[ -n "${SRC_ALLOWLIST_REGION_IDS}" ]] || ENABLE_SRC_ALLOWLIST="0"
            ;;
    esac
}

do_add_ddns_allowlist_source() {
    local name domain ttl enabled answer
    name="$(read_prompt "请输入 DDNS 显示名（例如 home，可空）: ")" || name=""
    domain="$(read_prompt "请输入 DDNS 域名（例如 home.example.com）: ")" || return 1
    domain="$(trim "${domain}")"
    validate_ddns_domain "${domain}" || {
        err "DDNS 域名无效：${domain}"
        return 1
    }
    [[ -n "$(trim "${name}")" ]] || name="${domain}"
    ttl="$(prompt_with_default "请输入刷新 TTL 秒数（60-86400）" "43200")"
    ttl="$(normalize_source_ttl_seconds "${ttl}")"
    answer="$(read_prompt "是否启用这个 DDNS 来源 [Y/n]: ")" || answer=""
    case "${answer,,}" in
        n|no)
            enabled="0"
            ;;
        *)
            enabled="1"
            ;;
    esac
    printf '即将添加 : 名称=%s 域名=%s TTL=%ss 状态=%s\n' \
        "$(sanitize_allowlist_source_text "${name}")" "${domain}" "${ttl}" \
        "$([[ "${enabled}" == "1" ]] && printf '启用' || printf '停用')"
    confirm_yes "确认添加 DDNS 来源" || return 1
    save_allowlist_last_snapshot || return 1
    append_ddns_allowlist_source "${name}" "${domain}" "${ttl}" "${enabled}" || return 1
    if [[ "${enabled}" == "1" ]]; then
        success "DDNS 来源已添加并启用；等待 LAN Worker/路由器解析后通过 SSH 上报。"
    else
        success "DDNS 来源已添加，但尚未启用。"
    fi
}

do_delete_ddns_allowlist_source() {
    local old_set old_name old_value
    select_ddns_allowlist_source || return 1
    old_set="${ALLOWLIST_SOURCE_SET_ID}"
    old_name="${ALLOWLIST_SOURCE_NAME}"
    old_value="${ALLOWLIST_SOURCE_VALUE}"
    confirm_yes "确认删除 DDNS 来源 ${old_name} (${old_value})" || return 1
    save_allowlist_last_snapshot || return 1
    rewrite_selected_ddns_source "${old_set}" "${old_name}" "${old_value}" "" || return 1
    sync_ddns_entries_removed "${old_set}" "${old_name}" "${old_value}" || return 1
    remove_ddns_report_stats "${old_value}" || true
    [[ "${old_name}" != "${old_value}" ]] && remove_ddns_report_stats "${old_name}" || true
    disable_src_allowlist_if_no_custom_entries
    apply_src_allowlist_changes || return 1
}

do_edit_ddns_allowlist_source() {
    local old_set old_name old_value old_enabled old_ttl
    local new_name new_domain new_ttl answer new_enabled replacement line duplicate=0
    select_ddns_allowlist_source || return 1
    old_set="${ALLOWLIST_SOURCE_SET_ID}"
    old_name="${ALLOWLIST_SOURCE_NAME}"
    old_value="${ALLOWLIST_SOURCE_VALUE}"
    old_enabled="${ALLOWLIST_SOURCE_ENABLED}"
    old_ttl="${ALLOWLIST_SOURCE_TTL_SECONDS}"

    new_name="$(prompt_with_default "请输入 DDNS 显示名" "${old_name}")"
    new_domain="$(prompt_with_default "请输入 DDNS 域名" "${old_value}")"
    new_domain="$(trim "${new_domain}")"
    validate_ddns_domain "${new_domain}" || {
        err "DDNS 域名无效：${new_domain}"
        return 1
    }
    [[ -n "$(trim "${new_name}")" ]] || new_name="${new_domain}"
    new_name="$(sanitize_allowlist_source_text "${new_name}")"
    new_domain="$(sanitize_allowlist_source_text "${new_domain}")"
    new_ttl="$(prompt_with_default "请输入刷新 TTL 秒数（60-86400）" "${old_ttl}")"
    new_ttl="$(normalize_source_ttl_seconds "${new_ttl}")"
    if [[ "${old_enabled}" == "1" ]]; then
        answer="$(prompt_with_default "是否启用这个 DDNS 来源 [Y/n]" "Y")"
    else
        answer="$(prompt_with_default "是否启用这个 DDNS 来源 [y/N]" "N")"
    fi
    case "${answer,,}" in
        y|yes)
            new_enabled="1"
            ;;
        n|no)
            new_enabled="0"
            ;;
        *)
            new_enabled="${old_enabled}"
            ;;
    esac

    ensure_allowlist_sources_file || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_source_line "${line}" || continue
        if [[ "${ALLOWLIST_SOURCE_SET_ID}" == "${old_set}" \
            && "${ALLOWLIST_SOURCE_NAME}" == "${old_name}" \
            && "${ALLOWLIST_SOURCE_VALUE}" == "${old_value}" ]]; then
            continue
        fi
        if [[ "${ALLOWLIST_SOURCE_SET_ID}" == "default" \
            && ("${ALLOWLIST_SOURCE_NAME}" == "${new_name}" || "${ALLOWLIST_SOURCE_VALUE}" == "${new_domain}") ]]; then
            duplicate=1
            break
        fi
    done < "${ALLOWLIST_SOURCES_FILE}"
    [[ "${duplicate}" != "1" ]] || {
        err "DDNS 来源已存在：${new_name} / ${new_domain}"
        return 1
    }

    printf '即将修改 : %s (%s) -> %s (%s)，TTL=%ss，状态=%s\n' \
        "${old_name}" "${old_value}" "${new_name}" "${new_domain}" "${new_ttl}" \
        "$([[ "${new_enabled}" == "1" ]] && printf '启用' || printf '停用')"
    confirm_yes "确认修改 DDNS 来源" || return 1
    save_allowlist_last_snapshot || return 1
    replacement="$(serialize_allowlist_source \
        "${old_set}" \
        "ddns" \
        "${new_name}" \
        "${new_domain}" \
        "${new_enabled}" \
        "${new_ttl}" \
        "" \
        "")"
    rewrite_selected_ddns_source "${old_set}" "${old_name}" "${old_value}" "${replacement}" || return 1
    if [[ "${new_domain}" != "${old_value}" || "${new_name}" != "${old_name}" ]]; then
        sync_ddns_entries_removed "${old_set}" "${old_name}" "${old_value}" || return 1
        remove_ddns_report_stats "${old_value}" || true
        [[ "${old_name}" != "${old_value}" ]] && remove_ddns_report_stats "${old_name}" || true
    fi
    if [[ "${new_enabled}" == "1" ]]; then
        do_refresh_ddns_allowlist_sources
    else
        sync_ddns_entries_removed "${old_set}" "${new_name}" "${new_domain}" || return 1
        disable_src_allowlist_if_no_custom_entries
        apply_src_allowlist_changes || return 1
    fi
}

do_toggle_ddns_allowlist_source() {
    local old_set old_name old_value new_enabled replacement
    select_ddns_allowlist_source || return 1
    old_set="${ALLOWLIST_SOURCE_SET_ID}"
    old_name="${ALLOWLIST_SOURCE_NAME}"
    old_value="${ALLOWLIST_SOURCE_VALUE}"
    if [[ "${ALLOWLIST_SOURCE_ENABLED}" == "1" ]]; then
        new_enabled="0"
    else
        new_enabled="1"
    fi
    replacement="$(serialize_allowlist_source \
        "${ALLOWLIST_SOURCE_SET_ID}" \
        "${ALLOWLIST_SOURCE_TYPE}" \
        "${ALLOWLIST_SOURCE_NAME}" \
        "${ALLOWLIST_SOURCE_VALUE}" \
        "${new_enabled}" \
        "${ALLOWLIST_SOURCE_TTL_SECONDS}" \
        "${ALLOWLIST_SOURCE_LAST_RESOLVED_AT}" \
        "${ALLOWLIST_SOURCE_LAST_RESULT}")"
    confirm_yes "确认$([[ "${new_enabled}" == "1" ]] && printf '启用' || printf '停用') DDNS 来源 ${old_name}" || return 1
    save_allowlist_last_snapshot || return 1
    rewrite_selected_ddns_source "${old_set}" "${old_name}" "${old_value}" "${replacement}" || return 1
    if [[ "${new_enabled}" == "1" ]]; then
        do_refresh_ddns_allowlist_sources
    else
        sync_ddns_entries_removed "${old_set}" "${old_name}" "${old_value}" || return 1
        disable_src_allowlist_if_no_custom_entries
        apply_src_allowlist_changes || return 1
    fi
}
