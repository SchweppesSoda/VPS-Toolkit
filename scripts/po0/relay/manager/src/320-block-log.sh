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
