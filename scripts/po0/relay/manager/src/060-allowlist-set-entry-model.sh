normalize_allowlist_set_sources() {
    local raw="${1:-region,manual,learned}"
    local source normalized out="" seen=" "

    raw="${raw//,/ }"
    raw="${raw//;/ }"
    for source in ${raw}; do
        source="$(trim "${source}")"
        source="${source,,}"
        [[ -n "${source}" ]] || continue
        case "${source}" in
            region|regions|iplist|geo)
                normalized="region"
                ;;
            manual|custom|user)
                normalized="manual"
                ;;
            learned|learn|conntrack)
                normalized="learned"
                ;;
            ssh|ssh_temp|ssh-temp)
                normalized="ssh_temp"
                ;;
            ddns|domain)
                normalized="ddns"
                ;;
            client_ip|client-ip|mobile|device_ip|device-ip)
                normalized="client_ip"
                ;;
            ssh_report|ssh-report|ssh_ip|ssh-ip|egern|egern_ssh|egern-ssh)
                normalized="ssh_report"
                ;;
            webauth|web_auth|web-auth|cf_access|cf-access|cloudflare_access|cloudflare-access)
                normalized="webauth"
                ;;
            *)
                return 1
                ;;
        esac
        [[ "${seen}" == *" ${normalized} "* ]] && continue
        seen+="${normalized} "
        if [[ -z "${out}" ]]; then
            out="${normalized}"
        else
            out+=",${normalized}"
        fi
    done
    [[ -n "${out}" ]] || out="manual,ddns,client_ip,ssh_report,webauth,learned"
    printf '%s\n' "${out}"
}

default_allowlist_set_record() {
    serialize_allowlist_set \
        "default" \
        "Default public allowlist" \
        "1" \
        "public" \
        "*" \
        "manual,ddns,client_ip,ssh_report,webauth,learned" \
        "Legacy global source allowlist mapped to the public set"
}

serialize_allowlist_set() {
    local id="$1"
    local label="$2"
    local enabled="$3"
    local scope="$4"
    local ports="$5"
    local sources="$6"
    local note="${7:-}"
    printf '%s|%s|%s|%s|%s|%s|%s\n' \
        "${id}" "${label}" "${enabled}" "${scope}" "${ports}" "${sources}" "${note}"
}

parse_allowlist_set_line() {
    local line="$1"
    local id label enabled scope ports sources note
    local -a fields=()

    PARSED_ALLOWLIST_SET=""
    ALLOWLIST_SET_ID=""
    ALLOWLIST_SET_LABEL=""
    ALLOWLIST_SET_ENABLED=""
    ALLOWLIST_SET_SCOPE=""
    ALLOWLIST_SET_PORTS=""
    ALLOWLIST_SET_SOURCES=""
    ALLOWLIST_SET_NOTE=""

    line="${line%$'\r'}"
    line="$(trim "${line}")"
    [[ -n "${line}" && ! "${line}" =~ ^# ]] || return 1

    IFS='|' read -r -a fields <<< "${line}"
    [[ ${#fields[@]} -ge 6 ]] || return 1

    id="$(trim "${fields[0]}")"
    label="$(sanitize_allowlist_set_text "${fields[1]}")"
    enabled="$(trim "${fields[2]}")"
    scope="$(normalize_allowlist_set_scope "${fields[3]}")" || return 1
    ports="$(normalize_allowlist_set_ports "${fields[4]}" "${scope}")" || return 1
    sources="$(normalize_allowlist_set_sources "${fields[5]}")" || return 1
    note=""
    if [[ ${#fields[@]} -ge 7 ]]; then
        note="$(sanitize_allowlist_set_text "${fields[6]}")"
    fi

    validate_allowlist_set_id "${id}" || return 1
    [[ "${enabled}" == "0" || "${enabled}" == "1" ]] || return 1
    [[ -n "${label}" ]] || label="${id}"

    ALLOWLIST_SET_ID="${id}"
    ALLOWLIST_SET_LABEL="${label}"
    ALLOWLIST_SET_ENABLED="${enabled}"
    ALLOWLIST_SET_SCOPE="${scope}"
    ALLOWLIST_SET_PORTS="${ports}"
    ALLOWLIST_SET_SOURCES="${sources}"
    ALLOWLIST_SET_NOTE="${note}"
    PARSED_ALLOWLIST_SET="$(serialize_allowlist_set \
        "${id}" "${label}" "${enabled}" "${scope}" "${ports}" "${sources}" "${note}")"
}

ensure_default_allowlist_set() {
    local set found_default=0
    for set in "${ALLOWLIST_SETS[@]}"; do
        parse_allowlist_set_line "${set}" || continue
        [[ "${ALLOWLIST_SET_ID}" == "default" ]] && found_default=1
    done
    if [[ "${found_default}" != "1" ]]; then
        ALLOWLIST_SETS=("$(default_allowlist_set_record)" "${ALLOWLIST_SETS[@]}")
    fi
}

write_allowlist_sets_file() {
    local path="$1"
    local set
    cat > "${path}" <<'EOF'
# Managed by nftables relay manager
# format: id|label|enabled|scope|ports|sources|note
# scope:
#   public = applies to all enabled managed relay listen ports
#   ports  = applies only to listed proto/port tokens
# ports:
#   public scope: *
#   ports scope : tcp/30001,udp/30002,both/30003
# sources:
#   region,manual,learned,ssh_temp,ddns,client_ip,ssh_report,webauth
EOF
    for set in "${ALLOWLIST_SETS[@]}"; do
        parse_allowlist_set_line "${set}" || continue
        printf '%s\n' "${PARSED_ALLOWLIST_SET}" >> "${path}"
    done
}

load_allowlist_sets() {
    local force_reload="${1:-0}"
    local line
    if [[ "${ALLOWLIST_SETS_CACHE_READY}" == "1" && "${force_reload}" != "1" ]]; then
        return 0
    fi
    ALLOWLIST_SETS=()
    if [[ -f "${ALLOWLIST_SETS_FILE}" ]]; then
        while IFS= read -r line || [[ -n "${line}" ]]; do
            parse_allowlist_set_line "${line}" || continue
            ALLOWLIST_SETS+=("${PARSED_ALLOWLIST_SET}")
        done < "${ALLOWLIST_SETS_FILE}"
    fi
    ensure_default_allowlist_set
    ALLOWLIST_SETS_CACHE_READY="1"
}

save_allowlist_sets() {
    local tmp
    mkdir -p "${CONF_DIR}" || return 1
    ensure_default_allowlist_set
    make_temp_file "${ALLOWLIST_SETS_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    write_allowlist_sets_file "${tmp}" || return 1
    mv -f "${tmp}" "${ALLOWLIST_SETS_FILE}"
    ALLOWLIST_SETS_CACHE_READY="1"
}

allowlist_set_count() {
    load_allowlist_sets
    printf '%s\n' "${#ALLOWLIST_SETS[@]}"
}

allowlist_set_count_for_file() {
    local file="$1"
    local line count=0
    [[ -f "${file}" ]] || {
        printf '0\n'
        return 0
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_set_line "${line}" || continue
        ((count++))
    done < "${file}"
    printf '%s\n' "${count}"
}

show_allowlist_sets_summary() {
    local set status scope_label ports_label sources_label
    load_allowlist_sets
    for set in "${ALLOWLIST_SETS[@]}"; do
        parse_allowlist_set_line "${set}" || continue
        if [[ "${ALLOWLIST_SET_ENABLED}" == "1" ]]; then
            status="启用"
        else
            status="停用"
        fi
        case "${ALLOWLIST_SET_SCOPE}" in
            public)
                scope_label="公共集"
                ports_label="全部托管转发端口"
                ;;
            *)
                scope_label="端口专属集"
                ports_label="${ALLOWLIST_SET_PORTS}"
                ;;
        esac
        sources_label="${ALLOWLIST_SET_SOURCES//,/ }"
        printf '  - %-16s %-4s 范围=%s 端口=%s 来源=%s\n' \
            "${ALLOWLIST_SET_ID}" "${status}" "${scope_label}" "${ports_label}" "${sources_label}"
    done
}

allowlist_set_nft_name() {
    local id="${1:-default}"
    validate_allowlist_set_id "${id}" || id="default"
    id="${id//./_}"
    id="${id//-/_}"
    printf 'po0_src_%s\n' "${id}"
}

default_allowlist_nft_set_name() {
    allowlist_set_nft_name "default"
}

normalize_allowlist_entry_source_type() {
    local value
    value="$(trim "${1:-manual}")"
    value="${value,,}"
    case "${value}" in
        region|regions|iplist|geo)
            printf 'region\n'
            ;;
        manual|custom|user)
            printf 'manual\n'
            ;;
        learned|learn|conntrack)
            printf 'learned\n'
            ;;
        ssh|ssh_temp|ssh-temp)
            printf 'ssh_temp\n'
            ;;
        ddns|domain)
            printf 'ddns\n'
            ;;
        client_ip|client-ip|mobile|device_ip|device-ip)
            printf 'client_ip\n'
            ;;
        ssh_report|ssh-report|ssh_ip|ssh-ip|egern|egern_ssh|egern-ssh)
            printf 'ssh_report\n'
            ;;
        webauth|web_auth|web-auth|cf_access|cf-access|cloudflare_access|cloudflare-access)
            printf 'webauth\n'
            ;;
        *)
            return 1
            ;;
    esac
}

allowlist_source_type_label() {
    case "$(normalize_allowlist_entry_source_type "${1:-}" 2>/dev/null || true)" in
        region) printf '地区库' ;;
        manual) printf '手动 CIDR' ;;
        learned) printf '学习提升' ;;
        ssh_temp) printf 'SSH 临时' ;;
        ddns) printf 'DDNS 上报' ;;
        client_ip) printf '客户端 IP' ;;
        ssh_report) printf 'SSH report' ;;
        webauth) printf 'WebAuth' ;;
        *) printf '%s' "${1:-unknown}" ;;
    esac
}

allowlist_sources_label() {
    local raw="${1:-}"
    local source out="" label
    raw="${raw//,/ }"
    for source in ${raw}; do
        [[ -n "${source}" ]] || continue
        label="$(allowlist_source_type_label "${source}")"
        if [[ -z "${out}" ]]; then
            out="${label}(${source})"
        else
            out+=", ${label}(${source})"
        fi
    done
    printf '%s\n' "${out:-无}"
}

sanitize_allowlist_entry_text() {
    local value="$1"
    value="${value//$'\t'/ }"
    value="${value//$'\r'/ }"
    value="${value//$'\n'/ }"
    value="${value//|//}"
    value="$(trim "${value}")"
    [[ ${#value} -le 128 ]] || value="${value:0:128}"
    printf '%s\n' "${value}"
}

serialize_allowlist_entry() {
    local set_id="$1"
    local cidr="$2"
    local source_type="$3"
    local source_value="${4:-}"
    local note="${5:-}"
    local created_at="${6:-}"
    local expires_at="${7:-}"
    printf '%s|%s|%s|%s|%s|%s|%s\n' \
        "${set_id}" "${cidr}" "${source_type}" "${source_value}" "${note}" "${created_at}" "${expires_at}"
}

parse_allowlist_entry_line() {
    local line="$1"
    local set_id cidr source_type source_value note created_at expires_at
    local -a fields=()

    PARSED_ALLOWLIST_ENTRY=""
    ALLOWLIST_ENTRY_SET_ID=""
    ALLOWLIST_ENTRY_CIDR=""
    ALLOWLIST_ENTRY_SOURCE_TYPE=""
    ALLOWLIST_ENTRY_SOURCE_VALUE=""
    ALLOWLIST_ENTRY_NOTE=""
    ALLOWLIST_ENTRY_CREATED_AT=""
    ALLOWLIST_ENTRY_EXPIRES_AT=""

    line="${line%$'\r'}"
    line="$(trim "${line}")"
    [[ -n "${line}" && ! "${line}" =~ ^# ]] || return 1

    IFS='|' read -r -a fields <<< "${line}"
    [[ ${#fields[@]} -ge 3 ]] || return 1

    set_id="$(trim "${fields[0]}")"
    cidr="$(normalize_ipv4_cidr_or_host "$(trim "${fields[1]}")")" || return 1
    source_type="$(normalize_allowlist_entry_source_type "$(trim "${fields[2]}")")" || return 1
    source_value=""
    note=""
    created_at=""
    expires_at=""
    [[ ${#fields[@]} -ge 4 ]] && source_value="$(sanitize_allowlist_entry_text "${fields[3]}")"
    [[ ${#fields[@]} -ge 5 ]] && note="$(sanitize_allowlist_entry_text "${fields[4]}")"
    [[ ${#fields[@]} -ge 6 ]] && created_at="$(sanitize_allowlist_entry_text "${fields[5]}")"
    [[ ${#fields[@]} -ge 7 ]] && expires_at="$(sanitize_allowlist_entry_text "${fields[6]}")"

    validate_allowlist_set_id "${set_id}" || return 1

    ALLOWLIST_ENTRY_SET_ID="${set_id}"
    ALLOWLIST_ENTRY_CIDR="${cidr}"
    ALLOWLIST_ENTRY_SOURCE_TYPE="${source_type}"
    ALLOWLIST_ENTRY_SOURCE_VALUE="${source_value}"
    ALLOWLIST_ENTRY_NOTE="${note}"
    ALLOWLIST_ENTRY_CREATED_AT="${created_at}"
    ALLOWLIST_ENTRY_EXPIRES_AT="${expires_at}"
    PARSED_ALLOWLIST_ENTRY="$(serialize_allowlist_entry \
        "${set_id}" "${cidr}" "${source_type}" "${source_value}" "${note}" "${created_at}" "${expires_at}")"
}

write_allowlist_entries_header() {
    local path="$1"
    cat > "${path}" <<'EOF'
# Managed by nftables relay manager
# format: set_id|cidr|source_type|source_value|note|created_at|expires_at
# source_type: region,manual,learned,ssh_temp,ddns,client_ip,ssh_report,webauth
EOF
}

ensure_allowlist_entries_file() {
    mkdir -p "${CONF_DIR}" || return 1
    if [[ ! -f "${ALLOWLIST_ENTRIES_FILE}" ]]; then
        write_allowlist_entries_header "${ALLOWLIST_ENTRIES_FILE}"
    fi
}

allowlist_entries_count() {
    local line count=0
    [[ -f "${ALLOWLIST_ENTRIES_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_entry_line "${line}" || continue
        ((count++))
    done < "${ALLOWLIST_ENTRIES_FILE}"
    printf '%s\n' "${count}"
}

allowlist_entries_count_for_set() {
    local set_id="${1:-default}"
    local line count=0
    [[ -f "${ALLOWLIST_ENTRIES_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_entry_line "${line}" || continue
        [[ "${ALLOWLIST_ENTRY_SET_ID}" == "${set_id}" ]] || continue
        ((count++))
    done < "${ALLOWLIST_ENTRIES_FILE}"
    printf '%s\n' "${count}"
}

allowlist_active_entries_count_for_set() {
    local set_id="${1:-default}"
    local line count=0
    [[ -f "${ALLOWLIST_ENTRIES_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_entry_line "${line}" || continue
        [[ "${ALLOWLIST_ENTRY_SET_ID}" == "${set_id}" ]] || continue
        allowlist_entry_is_expired "${ALLOWLIST_ENTRY_EXPIRES_AT}" && continue
        ((count++))
    done < "${ALLOWLIST_ENTRIES_FILE}"
    printf '%s\n' "${count}"
}

utc_now_iso() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

utc_after_hours_iso() {
    local hours="${1:-24}"
    [[ "${hours}" =~ ^[0-9]+$ ]] || hours="24"
    if date -u -d "+${hours} hours" '+%Y-%m-%dT%H:%M:%SZ' >/dev/null 2>&1; then
        date -u -d "+${hours} hours" '+%Y-%m-%dT%H:%M:%SZ'
    else
        utc_now_iso
    fi
}

allowlist_entry_is_expired() {
    local expires_at="$1"
    local now
    expires_at="$(sanitize_allowlist_entry_text "${expires_at}")"
    [[ -n "${expires_at}" ]] || return 1
    [[ "${expires_at}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || return 1
    now="$(utc_now_iso)"
    [[ "${expires_at}" < "${now}" || "${expires_at}" == "${now}" ]]
}

utc_after_seconds_iso() {
    local seconds="${1:-3600}"
    [[ "${seconds}" =~ ^[0-9]+$ ]] || seconds="3600"
    if date -u -d "+${seconds} seconds" '+%Y-%m-%dT%H:%M:%SZ' >/dev/null 2>&1; then
        date -u -d "+${seconds} seconds" '+%Y-%m-%dT%H:%M:%SZ'
    else
        utc_now_iso
    fi
}

utc_add_seconds_iso() {
    local iso="$1"
    local seconds="${2:-3600}"
    local epoch
    [[ "${seconds}" =~ ^[0-9]+$ ]] || seconds="3600"
    epoch="$(iso_to_epoch_utc "${iso}")" || {
        utc_after_seconds_iso "${seconds}"
        return 0
    }
    if date -u -d "@$((epoch + seconds))" '+%Y-%m-%dT%H:%M:%SZ' >/dev/null 2>&1; then
        date -u -d "@$((epoch + seconds))" '+%Y-%m-%dT%H:%M:%SZ'
    else
        utc_after_seconds_iso "${seconds}"
    fi
}

automation_mode_is_attack() {
    [[ "${AUTOMATION_MODE}" == "attack" ]]
}

auto_source_type_is_freezable() {
    case "$(normalize_allowlist_entry_source_type "${1:-}" 2>/dev/null || true)" in
        ddns|client_ip|ssh_report|webauth)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

dynamic_allowlist_source_type() {
    case "$(normalize_allowlist_entry_source_type "${1:-}" 2>/dev/null || true)" in
        ddns|client_ip|ssh_report|webauth)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

dynamic_allowlist_max_per_source() {
    local source_type="${1:-}" normalized_type value fallback="12"
    normalized_type="$(normalize_allowlist_entry_source_type "${source_type}" 2>/dev/null || true)"
    if [[ "${normalized_type}" == "ssh_report" ]]; then
        value="${SSH_REPORT_ALLOWLIST_MAX_PER_SOURCE:-12}"
    else
        value="${DYNAMIC_ALLOWLIST_MAX_PER_SOURCE:-12}"
    fi
    [[ "${value}" =~ ^[0-9]+$ ]] || value="${fallback}"
    (( value >= 1 )) || value="1"
    (( value <= 50 )) || value="50"
    printf '%s\n' "${value}"
}

dynamic_allowlist_limits_label() {
    local regular ssh_report
    regular="$(dynamic_allowlist_max_per_source ddns)"
    ssh_report="$(dynamic_allowlist_max_per_source ssh_report)"
    if [[ "${regular}" == "${ssh_report}" ]]; then
        printf '每 source-id 默认最多保留 %s 个有效 CIDR；过期条目不进入最终缓存' "${regular}"
    else
        printf 'ddns/client_ip/webauth 每 source-id 最多保留 %s 个有效 CIDR；ssh_report/Egern 每 source-id 最多保留 %s 个有效 CIDR；过期条目不进入最终缓存' \
            "${regular}" "${ssh_report}"
    fi
}

write_auto_pending_header() {
    local path="$1"
    cat > "${path}" <<'EOF'
# Managed by nftables relay manager
# format: id|created_at|source_type|source_value|cidr|note|status
EOF
}

ensure_auto_pending_file() {
    mkdir -p "${CONF_DIR}" || return 1
    if [[ ! -f "${AUTO_PENDING_FILE}" ]]; then
        write_auto_pending_header "${AUTO_PENDING_FILE}"
    fi
}

queue_pending_auto_source() {
    local source_type="$1"
    local source_value="$2"
    local cidr="$3"
    local note="${4:-}"
    local id now
    source_type="$(normalize_allowlist_entry_source_type "${source_type}")" || return 1
    source_value="$(sanitize_allowlist_entry_text "${source_value}")"
    cidr="$(normalize_ipv4_cidr_or_host "${cidr}")" || return 1
    note="$(sanitize_allowlist_entry_text "${note}")"
    ensure_auto_pending_file || return 1
    if grep -Fq "|${source_type}|${source_value}|${cidr}|" "${AUTO_PENDING_FILE}" 2>/dev/null; then
        return 0
    fi
    now="$(utc_now_iso)"
    id="pending-$(date '+%s')-${RANDOM}"
    printf '%s|%s|%s|%s|%s|%s|pending\n' \
        "${id}" "${now}" "${source_type}" "${source_value}" "${cidr}" "${note}" >> "${AUTO_PENDING_FILE}"
}

list_pending_auto_sources() {
    ensure_auto_pending_file || return 1
    awk -F '|' 'NF >= 7 && $1 !~ /^#/ && $7 == "pending" {
        printf "  - %s  %s  %s  %s  %s\n", $1, $3, $4, $5, $2
        if ($6 != "") printf "    note: %s\n", $6
    }' "${AUTO_PENDING_FILE}"
}

append_allowlist_entry() {
    local set_id="$1"
    local cidr="$2"
    local source_type="$3"
    local source_value="${4:-}"
    local note="${5:-}"
    local expires_at="${6:-}"
    local created_at line

    validate_allowlist_set_id "${set_id}" || return 1
    cidr="$(normalize_ipv4_cidr_or_host "${cidr}")" || return 1
    source_type="$(normalize_allowlist_entry_source_type "${source_type}")" || return 1
    source_value="$(sanitize_allowlist_entry_text "${source_value}")"
    note="$(sanitize_allowlist_entry_text "${note}")"
    expires_at="$(sanitize_allowlist_entry_text "${expires_at}")"
    created_at="$(utc_now_iso)"
    ensure_allowlist_entries_file || return 1

    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_entry_line "${line}" || continue
        if [[ "${ALLOWLIST_ENTRY_SET_ID}" == "${set_id}" \
            && "${ALLOWLIST_ENTRY_CIDR}" == "${cidr}" \
            && "${ALLOWLIST_ENTRY_SOURCE_TYPE}" == "${source_type}" \
            && "${ALLOWLIST_ENTRY_SOURCE_VALUE}" == "${source_value}" ]]; then
            return 0
        fi
    done < "${ALLOWLIST_ENTRIES_FILE}"

    serialize_allowlist_entry "${set_id}" "${cidr}" "${source_type}" "${source_value}" "${note}" "${created_at}" "${expires_at}" \
        >> "${ALLOWLIST_ENTRIES_FILE}"
}
