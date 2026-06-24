ipdb_python_cmd() {
    if [[ -x "${IPDB_VENV_PYTHON}" ]]; then
        printf '%s\n' "${IPDB_VENV_PYTHON}"
        return 0
    fi
    command -v python3 2>/dev/null && return 0
    return 1
}

ipdb_lookup_ready() {
    local py
    [[ -f "${IPDB_FILE}" ]] || return 1
    py="$(ipdb_python_cmd)" || return 1
    "${py}" - "${IPDB_FILE}" <<'PY' >/dev/null 2>&1
import sys
try:
    import ipdb
    if not hasattr(ipdb, "City"):
        raise RuntimeError("ipip-ipdb parser not available")
    ipdb.City(sys.argv[1])
except Exception:
    sys.exit(1)
PY
}

ipdb_status_label() {
    local py
    if [[ ! -f "${IPDB_FILE}" ]]; then
        printf '未上传（%s）' "${IPDB_FILE}"
        return 0
    fi
    if ! py="$(ipdb_python_cmd)"; then
        printf '已上传，但缺少 python3'
        return 0
    fi
    if ! "${py}" - "${IPDB_FILE}" <<'PY' >/dev/null 2>&1
import sys
try:
    import ipdb
    if not hasattr(ipdb, "City"):
        raise RuntimeError("ipip-ipdb parser not available")
    ipdb.City(sys.argv[1])
except Exception:
    sys.exit(1)
PY
    then
        printf '已上传，但缺少 Python 包 ipip-ipdb'
        return 0
    fi
    printf '可用（%s，%s）' "${IPDB_FILE}" "${py}"
}

ipdb_lookup_ip() {
    local ip="$1"
    local ready="${2:-0}"
    local info py
    validate_ip "${ip}" || {
        printf '-'
        return 0
    }
    [[ "${ready}" == "1" ]] || {
        printf '-'
        return 0
    }
    if [[ -n "${IPDB_LOOKUP_CACHE[${ip}]+set}" ]]; then
        printf '%s' "${IPDB_LOOKUP_CACHE[${ip}]}"
        return 0
    fi
    py="$(ipdb_python_cmd)" || {
        printf '-'
        return 0
    }
    info="$(
        "${py}" - "${IPDB_FILE}" "${IPDB_LANGUAGE}" "${ip}" <<'PY' 2>/dev/null
import sys

path, lang, ip = sys.argv[1:4]

try:
    import ipdb
    db = ipdb.City(path)
    data = db.find_map(ip, lang)

    def pick(key):
        value = data.get(key, "")
        if value is None:
            return ""
        return str(value).strip()

    location = []
    for key in ("country_name", "region_name", "city_name", "district_name"):
        value = pick(key)
        if value and value not in location:
            location.append(value)

    network = []
    for key in ("isp_domain", "owner_domain"):
        value = pick(key)
        if value and value not in network:
            network.append(value)

    parts = []
    if location:
        parts.append("/".join(location))
    if network:
        parts.append(" ".join(network))
    print(" ".join(parts) if parts else "-")
except Exception:
    print("-")
PY
    )" || info="-"
    info="$(trim "${info}")"
    [[ -n "${info}" ]] || info="-"
    IPDB_LOOKUP_CACHE["${ip}"]="${info}"
    printf '%s' "${info}"
}

file_sha256_short() {
    local path="$1"
    [[ -f "${path}" ]] || {
        printf '-'
        return 0
    }
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${path}" 2>/dev/null | awk '{ print substr($1, 1, 16) }'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "${path}" 2>/dev/null | awk '{ print substr($1, 1, 16) }'
    else
        printf '-'
    fi
}

file_mtime_epoch() {
    local path="$1"
    [[ -f "${path}" ]] || {
        printf '-'
        return 0
    }
    stat -c '%Y' "${path}" 2>/dev/null || stat -f '%m' "${path}" 2>/dev/null || printf '-'
}

ipdb_snapshot_for_ip() {
    local ip="$1"
    local ready=0 info sha mtime lookup_at
    ipdb_lookup_ready && ready=1
    info="$(ipdb_lookup_ip "${ip}" "${ready}")"
    info="$(sanitize_allowlist_entry_text "${info}")"
    sha="$(file_sha256_short "${IPDB_FILE}")"
    mtime="$(file_mtime_epoch "${IPDB_FILE}")"
    lookup_at="$(utc_now_iso)"
    printf 'ipdb_sha=%s;ipdb_mtime=%s;lookup_at=%s;geo=%s\n' "${sha}" "${mtime}" "${lookup_at}" "${info:-legacy/no snapshot}"
}

reload_learning_rules_if_needed() {
    local now
    now="$(date '+%s')"
    if (( now - LEARN_RULES_RELOAD_TS >= 60 )); then
        load_settings 1
        load_rules 1
        LEARN_RULES_RELOAD_TS="${now}"
    fi
}

find_learning_rule_match() {
    local proto="$1"
    local listen_port="$2"
    local reply_src="${3:-}"
    local reply_sport="${4:-}"
    local rule
    for rule in "${RULES[@]}"; do
        parse_rule "${rule}"
        [[ "${RULE_ENABLED}" == "1" ]] || continue
        protocols_overlap "${RULE_PROTO}" "${proto}" || continue
        [[ "${RULE_LPORT}" == "${listen_port}" ]] || continue
        if [[ -n "${reply_src}" && "${reply_src}" != "${RULE_DIP}" ]]; then
            continue
        fi
        if [[ -n "${reply_sport}" && "${reply_sport}" != "${RULE_DPORT}" ]]; then
            continue
        fi
        return 0
    done
    return 1
}

append_learning_event() {
    local src_ip="$1"
    local proto="$2"
    local listen_port="$3"
    local source_port="$4"
    local ts iso current_day snapshot
    ts="$(date '+%s')"
    iso="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    current_day="${iso:0:10}"
    snapshot="$(ipdb_snapshot_for_ip "${src_ip}")"
    mkdir -p "${CONF_DIR}" || return 1
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${ts}" \
        "${iso}" \
        "${src_ip}" \
        "${proto}" \
        "${listen_port}" \
        "${source_port}" \
        "$(tsv_safe "${RULE_ID}")" \
        "$(tsv_safe "${RULE_NAME}")" \
        "${RULE_DIP}" \
        "${RULE_DPORT}" \
        "$(tsv_safe "${snapshot}")" >> "${LEARN_LOG_FILE}"
    ((LEARN_APPEND_COUNT++))
    if [[ -n "${LEARN_LAST_COMPACT_DAY}" && "${current_day}" != "${LEARN_LAST_COMPACT_DAY}" ]]; then
        LEARN_LAST_COMPACT_DAY="${current_day}"
        compact_learning_log_if_needed "daily" || true
        return 0
    fi
    [[ -n "${LEARN_LAST_COMPACT_DAY}" ]] || LEARN_LAST_COMPACT_DAY="${current_day}"
    if (( LEARN_APPEND_COUNT % LEARN_COMPACT_CHECK_INTERVAL == 0 )); then
        compact_learning_log_if_needed "auto" || true
    fi
}

update_learning_daily_ip_counts() {
    local path="$1"
    local tmp existing_daily_ip_file
    [[ -s "${path}" ]] || return 0
    mkdir -p "${CONF_DIR}" || return 1
    make_temp_file "${LEARN_DAILY_IP_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    existing_daily_ip_file="${LEARN_DAILY_IP_FILE}"
    [[ -f "${existing_daily_ip_file}" ]] || existing_daily_ip_file="/dev/null"
    awk -F '\t' '
        function add(day, ip, n, first_iso, last_iso, key) {
            if (day == "" || ip == "" || n <= 0) {
                return
            }
            key = day SUBSEP ip
            count[key] += n
            if (!(key in first) || first_iso < first[key]) {
                first[key] = first_iso
            }
            if (!(key in last) || last_iso > last[key]) {
                last[key] = last_iso
            }
        }
        FILENAME == ARGV[1] {
            if (NF >= 5 && $1 !~ /^#/) {
                add($1, $2, $3 + 0, $4, $5)
            }
            next
        }
        NF >= 10 {
            add(substr($2, 1, 10), $3, 1, $2, $2)
        }
        END {
            for (key in count) {
                split(key, part, SUBSEP)
                print part[1] "\t" part[2] "\t" count[key] "\t" first[key] "\t" last[key]
            }
        }
    ' "${existing_daily_ip_file}" "${path}" 2>/dev/null | sort -t "$(printf '\t')" -k1,1 -k2,2 > "${tmp}"
    {
        printf '%s\n' '# format: day<TAB>ip<TAB>count<TAB>first_event_iso<TAB>last_event_iso'
        cat "${tmp}"
    } > "${tmp}.with_header"
    mv -f "${tmp}.with_header" "${LEARN_DAILY_IP_FILE}"
}

learning_daily_top_values() {
    local mode="$1"
    local limit="${2:-20}"
    [[ -s "${LEARN_DAILY_IP_FILE}" ]] || return 0
    awk -F '\t' -v mode="${mode}" '
        NF >= 5 && $1 !~ /^#/ {
            day = $1
            item = $2
            if (mode == "net24") {
                split($2, o, ".")
                item = o[1] "." o[2] "." o[3] ".0/24"
            } else if (mode == "net16") {
                split($2, o, ".")
                item = o[1] "." o[2] ".0.0/16"
            }
            count[day SUBSEP item] += $3
        }
        END {
            for (key in count) {
                split(key, part, SUBSEP)
                print part[1] "\t" part[2] "\t" count[key]
            }
        }
    ' "${LEARN_DAILY_IP_FILE}" \
        | sort -t "$(printf '\t')" -k1,1 -k3,3nr \
        | awk -F '\t' -v limit="${limit}" '
            current != $1 {
                if (current != "") {
                    print current "\t" out
                }
                current = $1
                out = ""
                n = 0
            }
            n < limit {
                item = $2 "=" $3
                out = out ? out ";" item : item
                n++
            }
            END {
                if (current != "") {
                    print current "\t" out
                }
            }
        '
}

regenerate_learning_daily_summary() {
    local stats_tmp top_ip_tmp top_24_tmp top_16_tmp tmp
    [[ -s "${LEARN_DAILY_IP_FILE}" ]] || return 0
    make_temp_file "${LEARN_SUMMARY_FILE}.stats" || return 1
    stats_tmp="${TEMP_FILE_RESULT}"
    make_temp_file "${LEARN_SUMMARY_FILE}.top_ip" || return 1
    top_ip_tmp="${TEMP_FILE_RESULT}"
    make_temp_file "${LEARN_SUMMARY_FILE}.top24" || return 1
    top_24_tmp="${TEMP_FILE_RESULT}"
    make_temp_file "${LEARN_SUMMARY_FILE}.top16" || return 1
    top_16_tmp="${TEMP_FILE_RESULT}"
    make_temp_file "${LEARN_SUMMARY_FILE}" || return 1
    tmp="${TEMP_FILE_RESULT}"
    awk -F '\t' '
        NF >= 5 && $1 !~ /^#/ {
            day = $1
            ip = $2
            events[day] += $3
            if (!(day in first) || $4 < first[day]) {
                first[day] = $4
            }
            if (!(day in last) || $5 > last[day]) {
                last[day] = $5
            }
            unique_ip[day]++
            split(ip, o, ".")
            net24 = o[1] "." o[2] "." o[3] ".0/24"
            net16 = o[1] "." o[2] ".0.0/16"
            if (!seen_24[day SUBSEP net24]++) {
                unique_24[day]++
            }
            if (!seen_16[day SUBSEP net16]++) {
                unique_16[day]++
            }
        }
        END {
            for (day in events) {
                print day "\t" events[day] "\t" first[day] "\t" last[day] "\t" unique_ip[day] "\t" unique_24[day] "\t" unique_16[day]
            }
        }
    ' "${LEARN_DAILY_IP_FILE}" | sort -t "$(printf '\t')" -k1,1 > "${stats_tmp}"
    learning_daily_top_values ip 20 > "${top_ip_tmp}"
    learning_daily_top_values net24 20 > "${top_24_tmp}"
    learning_daily_top_values net16 20 > "${top_16_tmp}"
    awk -F '\t' -v updated="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" '
        FILENAME == ARGV[1] { top_ip[$1] = $2; next }
        FILENAME == ARGV[2] { top_24[$1] = $2; next }
        FILENAME == ARGV[3] { top_16[$1] = $2; next }
        {
            print $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6 "\t" $7 "\t" top_ip[$1] "\t" top_24[$1] "\t" top_16[$1] "\t" updated
        }
    ' "${top_ip_tmp}" "${top_24_tmp}" "${top_16_tmp}" "${stats_tmp}" > "${tmp}"
    {
        printf '%s\n' '# format: day<TAB>events<TAB>first_event_iso<TAB>last_event_iso<TAB>unique_ips<TAB>unique_24s<TAB>unique_16s<TAB>top_ips<TAB>top_24s<TAB>top_16s<TAB>updated_iso'
        cat "${tmp}"
    } > "${tmp}.with_header"
    mv -f "${tmp}.with_header" "${LEARN_SUMMARY_FILE}"
}

archive_learning_events() {
    local path="$1"
    [[ -s "${path}" ]] || return 0
    update_learning_daily_ip_counts "${path}" || return 1
    regenerate_learning_daily_summary || return 1
}

compact_learning_log_if_needed() {
    local reason="${1:-auto}"
    local size total overflow today archive_tmp keep_tmp archived_count
    [[ -s "${LEARN_LOG_FILE}" ]] || return 0
    size="$(learning_log_size_bytes)"
    total="$(learning_log_line_count)"
    [[ "${size}" =~ ^[0-9]+$ ]] || size=0
    [[ "${total}" =~ ^[0-9]+$ ]] || total=0
    overflow=0
    if (( total > LEARN_LOG_KEEP_LINES )); then
        overflow=$((total - LEARN_LOG_KEEP_LINES))
    elif (( size > LEARN_LOG_MAX_BYTES )); then
        overflow=$((total / 2))
    fi
    today="$(date -u '+%Y-%m-%d')"
    make_temp_file "${LEARN_LOG_FILE}.archive" || return 1
    archive_tmp="${TEMP_FILE_RESULT}"
    make_temp_file "${LEARN_LOG_FILE}.keep" || return 1
    keep_tmp="${TEMP_FILE_RESULT}"
    awk -F '\t' -v today="${today}" -v overflow="${overflow}" -v archive_path="${archive_tmp}" -v keep_path="${keep_tmp}" '
        NF >= 10 {
            event_day = substr($2, 1, 10)
            if (event_day < today || NR <= overflow) {
                print > archive_path
                next
            }
        }
        {
            print > keep_path
        }
    ' "${LEARN_LOG_FILE}" || return 1
    archived_count="$(awk 'END { print NR + 0 }' "${archive_tmp}" 2>/dev/null)"
    [[ "${archived_count}" =~ ^[0-9]+$ ]] || archived_count=0
    (( archived_count > 0 )) || {
        rm -f -- "${archive_tmp}" "${keep_tmp}" 2>/dev/null || true
        return 0
    }
    archive_learning_events "${archive_tmp}" || return 1
    mv -f "${keep_tmp}" "${LEARN_LOG_FILE}"
    rm -f -- "${archive_tmp}" 2>/dev/null || true
}

process_conntrack_event() {
    local line="$1"
    local proto=""
    local token key value
    local orig_src="" orig_dst="" orig_sport="" orig_dport=""
    local reply_src="" reply_dst="" reply_sport="" reply_dport=""
    local src_seen=0 dst_seen=0 sport_seen=0 dport_seen=0

    [[ "${line}" == *ASSURED* ]] || return 0
    if [[ "${line}" =~ (^|[[:space:]])tcp[[:space:]] ]]; then
        proto="tcp"
    elif [[ "${line}" =~ (^|[[:space:]])udp[[:space:]] ]]; then
        proto="udp"
    else
        return 0
    fi

    for token in ${line}; do
        [[ "${token}" == *=* ]] || continue
        key="${token%%=*}"
        value="${token#*=}"
        value="${value%,}"
        case "${key}" in
            src)
                if (( src_seen == 0 )); then
                    orig_src="${value}"
                elif (( src_seen == 1 )); then
                    reply_src="${value}"
                fi
                ((src_seen++))
                ;;
            dst)
                if (( dst_seen == 0 )); then
                    orig_dst="${value}"
                elif (( dst_seen == 1 )); then
                    reply_dst="${value}"
                fi
                ((dst_seen++))
                ;;
            sport)
                if (( sport_seen == 0 )); then
                    orig_sport="${value}"
                elif (( sport_seen == 1 )); then
                    reply_sport="${value}"
                fi
                ((sport_seen++))
                ;;
            dport)
                if (( dport_seen == 0 )); then
                    orig_dport="${value}"
                elif (( dport_seen == 1 )); then
                    reply_dport="${value}"
                fi
                ((dport_seen++))
                ;;
        esac
    done

    is_public_ipv4 "${orig_src}" || return 0
    validate_port "${orig_dport}" || return 0
    validate_port "${orig_sport}" || orig_sport=""
    reload_learning_rules_if_needed
    find_learning_rule_match "${proto}" "${orig_dport}" "${reply_src}" "${reply_sport}" || return 0
    append_learning_event "${orig_src}" "${proto}" "${orig_dport}" "${orig_sport}"
}

run_learning_service() {
    check_root
    ensure_layout || exit 1
    command -v conntrack &>/dev/null || {
        err "学习服务需要 conntrack，请先安装 conntrack。"
        exit 1
    }
    load_settings 1
    load_rules 1
    LEARN_RULES_RELOAD_TS="$(date '+%s')"
    compact_learning_log_if_needed "startup" || true
    LEARN_LAST_COMPACT_DAY="$(date -u '+%Y-%m-%d')"
    info "来源 IP 学习服务已启动，只记录已完成双向转发的公网来源 IP。"
    conntrack -E 2>/dev/null | while IFS= read -r line; do
        process_conntrack_event "${line}"
    done
}

current_script_path() {
    if command -v readlink &>/dev/null; then
        readlink -f "$0" 2>/dev/null && return 0
    fi
    if command -v realpath &>/dev/null; then
        realpath "$0" 2>/dev/null && return 0
    fi
    printf '%s\n' "$0"
}

shell_quote() {
    local quoted
    printf -v quoted '%q' "$1"
    printf '%s' "${quoted}"
}

is_transient_script_path() {
    local path="$1"
    [[ -n "${path}" ]] || return 0
    [[ -f "${path}" ]] || return 0
    case "${path}" in
        /dev/fd/*|/proc/*/fd/*|/tmp/*|/var/tmp/*)
            return 0
            ;;
    esac
    return 1
}

install_manager_self() {
    local target="${1:-${MANAGER_INSTALL_PATH}}"
    local source tmp
    source="$(current_script_path 2>/dev/null || true)"
    if [[ -n "${source}" && "${source}" == "${target}" && -f "${target}" ]]; then
        chmod 0755 "${target}" 2>/dev/null || true
        printf '%s\n' "${target}"
        return 0
    fi
    mkdir -p "$(dirname "${target}")" || return 1
    tmp="${target}.tmp.$$"
    if [[ -n "${source}" ]] && ! is_transient_script_path "${source}"; then
        cp -- "${source}" "${tmp}" || return 1
    else
        err "当前脚本来自 stdin/临时路径，不能可靠落盘。请先把 nftables-relay-manager.sh 上传到 ${target} 后再运行。"
        rm -f -- "${tmp}" 2>/dev/null || true
        return 1
    fi
    chmod 0755 "${tmp}" || {
        rm -f -- "${tmp}" 2>/dev/null || true
        return 1
    }
    mv -f -- "${tmp}" "${target}" || return 1
    printf '%s\n' "${target}"
}

ensure_persistent_manager_script() {
    local source
    source="$(current_script_path 2>/dev/null || true)"
    if [[ -n "${source}" ]] && ! is_transient_script_path "${source}"; then
        printf '%s\n' "${source}"
        return 0
    fi
    warn "当前主控脚本来自临时路径，安装 cron 前需要先落盘。" >&2
    install_manager_self "${MANAGER_INSTALL_PATH}"
}

write_learning_runner() {
    local script_path escaped_path tmp
    script_path="$(current_script_path)" || return 1
    printf -v escaped_path '%q' "${script_path}"
    tmp="${LEARN_RUNNER}.tmp.$$"
    mkdir -p "$(dirname "${LEARN_RUNNER}")" || return 1
    cat > "${tmp}" <<EOF
#!/usr/bin/env bash
exec /usr/bin/env bash ${escaped_path} --learn-service
EOF
    chmod 0755 "${tmp}" || return 1
    mv -f "${tmp}" "${LEARN_RUNNER}"
}

write_learning_service_unit() {
    cat > "${LEARN_SERVICE_FILE}" <<EOF
[Unit]
Description=nftables relay source IP learning service
After=network-online.target nftables.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=${LEARN_RUNNER}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

enable_learning_service() {
    command -v systemctl &>/dev/null || {
        err "系统缺少 systemctl，无法安装学习服务。"
        return 1
    }
    install_conntrack_if_needed || return 1
    write_learning_runner || return 1
    write_learning_service_unit || return 1
    systemctl daemon-reload || return 1
    systemctl enable --now "${LEARN_SERVICE_NAME}" || return 1
}

disable_learning_service() {
    command -v systemctl &>/dev/null || {
        err "系统缺少 systemctl。"
        return 1
    }
    systemctl disable --now "${LEARN_SERVICE_NAME}" 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
}
