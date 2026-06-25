self_report_targets_env() {
    local line source ttl extra count=0
    if [[ -n "${SELF_REPORT_TARGETS}" ]]; then
        printf '%s\n' "${SELF_REPORT_TARGETS}" | tr ';' '\n'
        return 0
    fi
    ensure_config_file || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        [[ "${TARGET_ENABLED}" == "1" ]] || continue
        [[ -n "${TARGET_CLIENT_IP_TOKEN}" ]] || continue
        source="${TARGET_CLIENT_IP_SOURCE:-${SELF_REPORT_SOURCE}}"
        ttl="$(normalize_report_ttl_seconds "${TARGET_CLIENT_IP_TTL:-${SELF_REPORT_TTL_SECONDS}}" "${SELF_REPORT_TTL_SECONDS:-43200}")"
        extra="${TARGET_REPORT_SSH_EXTRA_ARGS:-${TARGET_SSH_EXTRA_ARGS}}"
        printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
            "${source}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT:-22}" "${TARGET_PO0_USER:-root}" "${TARGET_PO0_SCRIPT:-${DEFAULT_PO0_SCRIPT}}" "${TARGET_CLIENT_IP_TOKEN}" "${ttl:-43200}" "${extra}"
        count=$((count + 1))
    done < "${CONFIG_FILE}"
    if [[ "${count}" == "0" && -n "${PO0_HOST}" && -n "${CLIENT_IP_TOKEN}" ]]; then
        printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
            "${SELF_REPORT_SOURCE}" "${PO0_HOST}" "${PO0_PORT:-22}" "${PO0_USER:-root}" "${PO0_SCRIPT:-${DEFAULT_PO0_SCRIPT}}" "${CLIENT_IP_TOKEN}" "$(normalize_report_ttl_seconds "${SELF_REPORT_TTL_SECONDS}" 43200)" "${SSH_EXTRA_ARGS}"
    fi
}

has_config_self_report_target() {
    local line
    ensure_config_file || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        [[ "${TARGET_ENABLED}" == "1" ]] || continue
        [[ -n "${TARGET_PO0_HOST}" && -n "${TARGET_CLIENT_IP_TOKEN}" ]] || continue
        return 0
    done < "${CONFIG_FILE}"
    return 1
}

webauth_targets_env() {
    local line source ttl extra count=0
    if [[ -n "${WEBAUTH_TARGETS}" ]]; then
        printf '%s\n' "${WEBAUTH_TARGETS}" | tr ';' '\n'
        return 0
    fi
    ensure_config_file || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        [[ "${TARGET_ENABLED}" == "1" ]] || continue
        [[ -n "${TARGET_WEBAUTH_TOKEN}" ]] || continue
        source="${TARGET_WEBAUTH_SOURCE:-${WEBAUTH_SOURCE}}"
        ttl="$(normalize_report_ttl_seconds "${TARGET_WEBAUTH_TTL:-${WEBAUTH_TTL_SECONDS}}" "${WEBAUTH_TTL_SECONDS:-43200}")"
        extra="${TARGET_REPORT_SSH_EXTRA_ARGS:-${TARGET_SSH_EXTRA_ARGS}}"
        printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
            "${source}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT:-22}" "${TARGET_PO0_USER:-root}" "${TARGET_PO0_SCRIPT:-${DEFAULT_PO0_SCRIPT}}" "${TARGET_WEBAUTH_TOKEN}" "${ttl:-43200}" "${extra}"
        count=$((count + 1))
    done < "${CONFIG_FILE}"
    if [[ "${count}" == "0" && -n "${PO0_HOST}" && -n "${WEBAUTH_TOKEN}" ]]; then
        printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
            "${WEBAUTH_SOURCE}" "${PO0_HOST}" "${PO0_PORT:-22}" "${PO0_USER:-root}" "${PO0_SCRIPT:-${DEFAULT_PO0_SCRIPT}}" "${WEBAUTH_TOKEN}" "$(normalize_report_ttl_seconds "${WEBAUTH_TTL_SECONDS}" 43200)" "${SSH_EXTRA_ARGS}"
    fi
}
