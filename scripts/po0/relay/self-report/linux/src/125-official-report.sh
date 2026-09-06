# PO0 official firewall reporting for ordinary Linux clients.
#
# This lane deliberately has one small user-facing setting:
#
#   PO0_FIREWALL_TOKENS='pgnfw_xxx@0,pgnfw_yyy@1'
#
# The comma-separated entries are official tokens.  The optional @0..@4
# suffix pins the current IP to a fixed whitelist slot.  Tokens are read from
# the protected settings file/environment, never from a command-line option.
# OpenWrt multi-WAN uses its package-owned target/binding runner instead; this
# generic lane always uses the host's normal default route.
# Behavior reference: https://github.com/kelenetwork/po0fw (MIT).
# This is a native VPS-Toolkit integration; it does not copy that project's
# implementation or assume a Chicksure-specific deployment.

PO0_FIREWALL_TOKENS="${PO0_FIREWALL_TOKENS:-}"
# The generic Linux lane uses a fixed ten-minute interval.  The state path is
# internal; tests may assign OFFICIAL_STATE_FILE after sourcing this file.
OFFICIAL_STATE_FILE=""
OFFICIAL_API_BASE="https://124.221.69.228/api/firewall"
REPORT_MODE="${REPORT_MODE:-${PO0_OUTBOUND_IP_REPORT_MODE:-all}}"
OFFICIAL_RESULT_MESSAGE=""
OFFICIAL_RESULT_STATUS=""
OFFICIAL_RESULT_NEEDS_NOTIFY="0"
OFFICIAL_ITEM_STATUS="error"
OFFICIAL_ITEM_CURRENT_IP=""
OFFICIAL_ITEM_USED=""
OFFICIAL_ITEM_LIMIT=""
OFFICIAL_ITEM_WHITELIST=""
OFFICIAL_ITEM_SLOT=""
OFFICIAL_STATE_RECORDS=""
OFFICIAL_ADDED_COUNT="0"

official_state_file() {
    if [[ -n "${OFFICIAL_STATE_FILE:-}" ]]; then
        printf '%s\n' "${OFFICIAL_STATE_FILE}"
    elif [[ -n "${XDG_STATE_HOME:-}" ]]; then
        printf '%s\n' "${XDG_STATE_HOME}/po0-outbound-ip-report/official.state"
    elif [[ -n "${HOME:-}" ]]; then
        printf '%s\n' "${HOME}/.local/state/po0-outbound-ip-report/official.state"
    else
        printf '%s\n' "${TMPDIR:-/tmp}/po0-outbound-ip-report-$(id -u 2>/dev/null || printf 0)/official.state"
    fi
}

official_secure_state_dir() {
    local dir="${1:-}" mode owner current_uid created=0
    case "${dir}" in
        ""|/|.|/tmp|/var/tmp) return 1 ;;
    esac
    [[ "${dir}" != *$'\n'* && "${dir}" != *$'\r'* ]] || return 1
    [[ ! -L "${dir}" ]] || return 1
    if [[ ! -e "${dir}" ]]; then
        mkdir -p "${dir}" 2>/dev/null || return 1
        created=1
    fi
    [[ -d "${dir}" && ! -L "${dir}" ]] || return 1
    owner="$(stat -c '%u' "${dir}" 2>/dev/null || true)"
    current_uid="$(id -u 2>/dev/null || true)"
    [[ "${owner}" =~ ^[0-9]+$ && "${current_uid}" =~ ^[0-9]+$ && "${owner}" == "${current_uid}" ]] || return 1
    # Only directories created by this lane are chmodded.  A pre-existing
    # custom parent (for example /etc or a user-selected state directory) is
    # never rewritten; it must already be non-group/world-writable instead.
    if (( created == 1 )); then
        chmod 700 "${dir}" 2>/dev/null || return 1
    fi
    mode="$(stat -c '%a' "${dir}" 2>/dev/null || true)"
    [[ "${mode}" =~ ^[0-7]{3,4}$ ]] || return 1
    mode="${mode: -3}"
    [[ "${mode:1:1}" != [2467] && "${mode:2:1}" != [2467] ]] || return 1
}

official_now() {
    local value="${PO0_OUTBOUND_IP_REPORT_OFFICIAL_NOW:-}"
    if [[ "${value}" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$((10#${value}))"
    else
        date +%s
    fi
}

# The generated CLI sources the saved settings after this file's top-level
# defaults have run. Keep legacy/hand-edited OFFICIAL_* assignments from
# turning into a public configuration surface: only tests may assign the
# internal state path after sourcing this fragment.
official_reset_internal_settings() {
    OFFICIAL_STATE_FILE=""
    OFFICIAL_API_BASE="https://124.221.69.228/api/firewall"
}

official_interval_seconds() { printf '%s\n' "${OFFICIAL_INTERVAL_SECONDS:-600}"; }

official_interval_minutes() {
    local seconds
    seconds="$(official_interval_seconds)"
    if (( seconds % 60 == 0 )); then
        printf '%s\n' "$((seconds / 60))"
    else
        # The independent state gate still enforces the exact seconds.  A
        # one-minute wake-up is the least surprising cron fallback.
        printf '1\n'
    fi
}

official_last_attempt_at() {
    local state
    state="$(official_state_file)"
    [[ -r "${state}" ]] || return 1
    sed -n 's/^last_attempt_at=\([0-9][0-9]*\)$/\1/p' "${state}" | head -n 1
}

official_due() {
    local now last interval
    # Only an internal scheduled wake-up is subject to the last-attempt gate.
    # Manual runs always perform the safe GET-first decision.
    [[ "${SCHEDULED_RUN:-0}" == "1" ]] || return 0
    [[ "${FORCE_REPORT:-0}" == "1" || "${NETWORK_CHANGED:-0}" == 1 || "${TIMER_TRIGGER:-0}" == 1 ]] && return 0
    interval="$(official_interval_seconds)"
    last="$(official_last_attempt_at 2>/dev/null || true)"
    [[ "${last}" =~ ^[0-9]+$ ]] || return 0
    now="$(official_now)"
    (( now < last || now - last >= interval ))
}

official_write_state() {
    local status="$1" include_success="${2:-0}"
    local state dir tmp old_umask now
    state="$(official_state_file)"
    dir="$(dirname "${state}")"
    official_secure_state_dir "${dir}" || return 1
    [[ ! -L "${state}" ]] || return 1
    now="$(official_now)"
    old_umask="$(umask)"
    umask 077
    # mktemp creates the replacement in the state file's directory with an
    # exclusive name.  Do not use a predictable ${state}.tmp.$$ path: a
    # pre-created symlink in a shared /tmp directory could redirect the write.
    if ! tmp="$(mktemp "${dir%/}/.po0-official-state.XXXXXX" 2>/dev/null)"; then
        umask "${old_umask}"
        return 1
    fi
    if [[ ! -f "${tmp}" || -L "${tmp}" ]] || ! chmod 600 "${tmp}" 2>/dev/null; then
        rm -f -- "${tmp}" 2>/dev/null || true
        umask "${old_umask}"
        return 1
    fi
    if ! {
        printf 'last_attempt_at=%s\n' "${now}"
        printf 'last_status=%s\n' "${status}"
        if [[ "${include_success}" == "1" ]]; then
            printf 'last_success_at=%s\n' "${now}"
        fi
    } > "${tmp}"; then
        rm -f -- "${tmp}" 2>/dev/null || true
        umask "${old_umask}"
        return 1
    fi
    if ! mv -f "${tmp}" "${state}"; then
        rm -f -- "${tmp}" 2>/dev/null || true
        umask "${old_umask}"
        return 1
    fi
    umask "${old_umask}"
    chmod 600 "${state}" 2>/dev/null || true
    return 0
}

official_write_state_v2() {
    local status="$1" records="${2:-}" include_success="${3:-0}" update_attempt="${4:-1}"
    local state dir tmp old_umask now last_attempt last_success old_records
    local success failure added
    state="$(official_state_file)"
    dir="$(dirname "${state}")"
    official_secure_state_dir "${dir}" || return 1
    [[ ! -L "${state}" ]] || return 1
    last_attempt="$(official_last_attempt_at 2>/dev/null || true)"
    [[ "${last_attempt}" =~ ^[0-9]+$ ]] || last_attempt="0"
    last_success="$(sed -n 's/^last_success_at=\([0-9][0-9]*\)$/\1/p' "${state}" 2>/dev/null | head -n 1 || true)"
    [[ "${last_success}" =~ ^[0-9]+$ ]] || last_success="0"
    old_records="$(sed -n 's/^item=//p' "${state}" 2>/dev/null || true)"
    [[ -n "${records}" ]] || records="${old_records}"
    now="$(official_now)"
    [[ "${update_attempt}" == "1" ]] && last_attempt="${now}"
    [[ "${include_success}" == "1" ]] && last_success="${now}"
    success="${OFFICIAL_RESULT_SUCCESS_COUNT:-0}"
    failure="${OFFICIAL_RESULT_FAILURE_COUNT:-0}"
    added="${OFFICIAL_ADDED_COUNT:-0}"
    old_umask="$(umask)"
    umask 077
    if ! tmp="$(mktemp "${dir%/}/.po0-official-state.XXXXXX" 2>/dev/null)"; then
        umask "${old_umask}"
        return 1
    fi
    if [[ ! -f "${tmp}" || -L "${tmp}" ]] || ! chmod 600 "${tmp}" 2>/dev/null; then
        rm -f -- "${tmp}" 2>/dev/null || true
        umask "${old_umask}"
        return 1
    fi
    if ! {
        printf 'last_attempt_at=%s\n' "${last_attempt}"
        [[ "${last_success}" =~ ^[1-9][0-9]*$ ]] && printf 'last_success_at=%s\n' "${last_success}"
        printf 'last_checked_at=%s\n' "${now}"
        printf 'last_status=%s\n' "${status}"
        printf 'success_count=%s\n' "${success}"
        printf 'failure_count=%s\n' "${failure}"
        printf 'added_count=%s\n' "${added}"
        while IFS= read -r record || [[ -n "${record}" ]]; do
            [[ -n "${record}" ]] && printf 'item=%s\n' "${record}"
        done <<< "${records}"
        true
    } > "${tmp}"; then
        rm -f -- "${tmp}" 2>/dev/null || true
        umask "${old_umask}"
        return 1
    fi
    if ! mv -f "${tmp}" "${state}"; then
        rm -f -- "${tmp}" 2>/dev/null || true
        umask "${old_umask}"
        return 1
    fi
    umask "${old_umask}"
    chmod 600 "${state}" 2>/dev/null || true
    return 0
}

official_mark_attempt() {
    official_write_state_v2 attempted "" 0 1
}

official_mark_failure() {
    official_write_state_v2 failed "$OFFICIAL_STATE_RECORDS" 0 1
}

official_mark_partial() {
    official_write_state_v2 partial "$OFFICIAL_STATE_RECORDS" 0 1
}

official_mark_success() {
    official_write_state_v2 success "$OFFICIAL_STATE_RECORDS" 1 1
}

official_normalize_tokens() {
    local raw="${1:-}"
    raw="${raw//，/,}"
    raw="${raw//；/,}"
    printf '%s' "${raw}" | tr ',;[:space:]' '\n' | awk 'NF { printf "%s%s", sep, $0; sep="," } END { printf "\n" }'
}

official_validate_token() {
    local value="${1:-}"
    # Keep the token usable as one URL path component and safe in diagnostics.
    (( ${#value} >= 7 && ${#value} <= 246 )) || return 1
    [[ "${value}" =~ ^pgnfw_[A-Za-z0-9._~-]{1,240}$ ]]
}

official_validate_slot() {
    [[ -z "${1:-}" || "${1}" =~ ^[0-4]$ ]]
}

official_parse_token_item() {
    local value="$(trim "${1:-}")" extra
    OFFICIAL_PARSED_TOKEN=""
    OFFICIAL_PARSED_SLOT=""
    [[ -n "${value}" ]] || return 1
    [[ "${value}" != *$'\n'* && "${value}" != *$'\r'* ]] || return 1
    IFS='@' read -r OFFICIAL_PARSED_TOKEN OFFICIAL_PARSED_SLOT extra <<< "${value}"
    [[ -z "${extra:-}" ]] || return 1
    OFFICIAL_PARSED_TOKEN="$(trim "${OFFICIAL_PARSED_TOKEN}")"
    OFFICIAL_PARSED_SLOT="$(trim "${OFFICIAL_PARSED_SLOT:-}")"
    official_validate_token "${OFFICIAL_PARSED_TOKEN}" || return 1
    official_validate_slot "${OFFICIAL_PARSED_SLOT}" || return 1
    return 0
}

official_tokens_count() {
    local raw="$(official_normalize_tokens "${PO0_FIREWALL_TOKENS:-}")" item count=0
    [[ -n "${raw}" ]] || { printf '0\n'; return 0; }
    raw="${raw},"
    while [[ "${raw}" == *,* ]]; do
        item="${raw%%,*}"
        raw="${raw#*,}"
        [[ -n "$(trim "${item}")" ]] || continue
        count=$((count + 1))
    done
    printf '%s\n' "${count}"
}

official_channel_enabled() {
    [[ "$(official_tokens_count)" -gt 0 ]]
}

official_validate_tokens() {
    local raw="$(official_normalize_tokens "${PO0_FIREWALL_TOKENS:-}")" item count=0 key seen=";"
    [[ -n "${raw}" ]] || return 1
    raw="${raw},"
    while [[ "${raw}" == *,* ]]; do
        item="${raw%%,*}"
        raw="${raw#*,}"
        item="$(trim "${item}")"
        [[ -n "${item}" ]] || continue
        official_parse_token_item "${item}" || {
            printf '官方防火墙 token 配置无效（格式应为 token 或 token@0..4）。\n' >&2
            return 1
        }
        key="${OFFICIAL_PARSED_TOKEN}"
        [[ "${seen}" != *";${key};"* ]] || {
            printf '官方防火墙 token 列表包含重复项。\n' >&2
            return 1
        }
        seen="${seen}${key};"
        count=$((count + 1))
        (( count <= 16 )) || {
            printf '官方防火墙 token 数量超过上限（最多 16 个）。\n' >&2
            return 1
        }
    done
    return 0
}

official_tokens_summary() {
    local raw item count=0 invalid=0 slot slots="" seen_slots=";"
    raw="$(official_normalize_tokens "${PO0_FIREWALL_TOKENS:-}")"
    [[ -n "${raw}" ]] || { printf '未配置'; return 0; }
    raw="${raw},"
    while [[ "${raw}" == *,* ]]; do
        item="${raw%%,*}"
        raw="${raw#*,}"
        item="$(trim "${item}")"
        [[ -n "${item}" ]] || { invalid=1; continue; }
        if ! official_parse_token_item "${item}"; then
            invalid=1
            continue
        fi
        count=$((count + 1))
        slot="${OFFICIAL_PARSED_SLOT}"
        if [[ -n "${slot}" && "${seen_slots}" != *";${slot};"* ]]; then
            seen_slots="${seen_slots}${slot};"
            slots="${slots}${slots:+、}${slot}"
        fi
    done
    if (( invalid > 0 )); then
        if (( count > 0 )); then
            printf '配置有误（已识别 %s 个）' "${count}"
        else
            printf '配置有误'
        fi
        return 0
    fi
    printf '已配置 %s 个' "${count}"
    [[ -n "${slots}" ]] && printf '（固定槽位 %s）' "${slots}"
}

official_validate_api_base() {
    [[ "${OFFICIAL_API_BASE:-}" == "https://124.221.69.228/api/firewall" ]]
}

official_normalize_api_base() {
    printf '%s\n' "https://124.221.69.228/api/firewall"
}

official_direct_request() (
    local token="$1" operation="$2" slot="${3:-}"
    local url method escaped_url request_dir body_file header_file
    local http_code curl_rc body_size header_size
    official_validate_token "${token}" || return 1
    official_validate_api_base || return 1
    case "${operation}" in
        status)
            [[ -z "${slot}" ]] || return 1
            method="GET"
            url="$(official_normalize_api_base)/${token}"
            ;;
        add)
            official_validate_slot "${slot}" || return 1
            method="POST"
            url="$(official_normalize_api_base)/${token}/add"
            [[ -n "${slot}" ]] && url="${url}?slot=${slot}"
            ;;
        *) return 1 ;;
    esac
    umask 077
    request_dir="$(mktemp -d "${TMPDIR:-/tmp}/po0-official-request.XXXXXX" 2>/dev/null)" || {
        printf 'official request temporary storage is unavailable.\n' >&2
        return 1
    }
    trap 'rm -rf -- "${request_dir}"' EXIT
    trap 'rm -rf -- "${request_dir}"; exit 129' HUP
    trap 'rm -rf -- "${request_dir}"; exit 130' INT
    trap 'rm -rf -- "${request_dir}"; exit 143' TERM
    chmod 700 "${request_dir}" 2>/dev/null || return 1
    [[ -d "${request_dir}" && ! -L "${request_dir}" ]] || return 1
    body_file="${request_dir}/body"
    header_file="${request_dir}/headers"
    : > "${body_file}" || return 1
    : > "${header_file}" || return 1
    chmod 600 "${body_file}" "${header_file}" 2>/dev/null || return 1
    [[ -f "${body_file}" && ! -L "${body_file}" && -f "${header_file}" && ! -L "${header_file}" ]] || return 1
    escaped_url="${url//\\/\\\\}"
    escaped_url="${escaped_url//\"/\\\"}"
    # The token is supplied to curl through stdin rather than argv.  Use the
    # official reference endpoint over IPv4/TLS and do not inherit proxies.
    if http_code="$({
        printf 'url = "%s"\n' "${escaped_url}"
        printf 'request = "%s"\n' "${method}"
    } | env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
        curl -4sS --noproxy '*' --proto '=https' --connect-timeout 5 --max-time 20 \
        --retry 2 --retry-delay 2 --max-filesize 65536 --output "${body_file}" --dump-header "${header_file}" \
        --write-out '%{http_code}' --config - 2>/dev/null)"; then
        curl_rc=0
    else
        curl_rc=$?
    fi
    [[ -f "${body_file}" && ! -L "${body_file}" && -f "${header_file}" && ! -L "${header_file}" ]] || {
        printf 'official request response storage is invalid.\n' >&2
        return 1
    }
    chmod 600 "${body_file}" "${header_file}" 2>/dev/null || return 1
    body_size="$(wc -c < "${body_file}" 2>/dev/null || true)"
    header_size="$(wc -c < "${header_file}" 2>/dev/null || true)"
    [[ "${body_size}" =~ ^[0-9]+$ && "${header_size}" =~ ^[0-9]+$ ]] || {
        printf 'official request response size is invalid.\n' >&2
        return 1
    }
    (( body_size <= 65536 )) || {
        printf 'official response body exceeded the 64K limit.\n' >&2
        return 1
    }
    (( header_size <= 16384 )) || {
        printf 'official response headers exceeded the 16K limit.\n' >&2
        return 1
    }
    (( curl_rc == 0 )) || {
        printf 'official request failed (curl exit %s).\n' "${curl_rc}" >&2
        return 1
    }
    [[ "${http_code}" =~ ^2[0-9]{2}$ ]] || {
        printf 'official request failed (HTTP %s).\n' "${http_code:-unknown}" >&2
        return 1
    }
    cat "${body_file}"
)

official_json_compact() {
    # Kept as a compatibility helper.  Response validation must receive the
    # original whitespace so the structured parser can reject trailing data.
    printf '%s\n' "${1:-}"
}

#
# The official endpoint is outside the client's trust boundary.  A substring
# parser can be fooled by nested objects, duplicate keys, field reordering, or
# bytes after the root object.  This recursive-descent parser is deliberately
# written for POSIX awk, which is available on the supported Linux targets.
# It rejects duplicate keys, unknown schema keys, malformed JSON, trailing
# data, and every slot type except null, the empty string, or a JSON integer
# 0..4.  It also refuses \u escapes: this protocol has no Unicode fields and
# rejecting them prevents escaped key names from bypassing field checks.
official_json_parse() {
    local json="${1:-}"
    (( ${#json} <= 65536 )) || return 1
    printf '%s' "${json}" | awk '
function fail() { exit 1 }
function ws(    c) {
    while (pos <= src_len) {
        c = substr(src, pos, 1)
        if (c ~ /[ \t\r\n]/) pos++
        else break
    }
}
function expect(ch) {
    ws()
    if (substr(src, pos, 1) != ch) fail()
    pos++
}
function parse_string(    c, esc, out) {
    ws()
    if (substr(src, pos, 1) != "\"") fail()
    pos++
    out = ""
    while (pos <= src_len) {
        c = substr(src, pos, 1)
        pos++
        if (c == "\"") {
            P_TYPE = "string"
            P_VALUE = out
            return out
        }
        if (c ~ /[\001-\037]/) fail()
        if (c == "\\") {
            if (pos > src_len) fail()
            esc = substr(src, pos, 1)
            pos++
            if (esc == "\"" || esc == "\\" || esc == "/") out = out esc
            else fail()
        } else {
            out = out c
        }
    }
    fail()
}
function parse_number(    start, c) {
    ws()
    start = pos
    if (substr(src, pos, 1) == "-") {
        pos++
        if (substr(src, pos, 1) !~ /[0-9]/) fail()
    }
    if (substr(src, pos, 1) == "0") {
        pos++
        if (substr(src, pos, 1) ~ /[0-9]/) fail()
    } else if (substr(src, pos, 1) ~ /[1-9]/) {
        while (substr(src, pos, 1) ~ /[0-9]/) pos++
    } else {
        fail()
    }
    if (substr(src, pos, 1) == ".") {
        pos++
        if (substr(src, pos, 1) !~ /[0-9]/) fail()
        while (substr(src, pos, 1) ~ /[0-9]/) pos++
    }
    c = substr(src, pos, 1)
    if (c == "e" || c == "E") {
        pos++
        c = substr(src, pos, 1)
        if (c == "+" || c == "-") pos++
        if (substr(src, pos, 1) !~ /[0-9]/) fail()
        while (substr(src, pos, 1) ~ /[0-9]/) pos++
    }
    P_TYPE = "number"
    P_VALUE = substr(src, start, pos - start)
    return P_VALUE
}
function parse_value(depth, context,    c) {
    if (depth > 32) fail()
    ws()
    c = substr(src, pos, 1)
    if (c == "{") {
        parse_object(depth, context)
        P_TYPE = "object"
        P_VALUE = ""
    } else if (c == "[") {
        parse_array(depth, context)
        P_TYPE = "array"
        P_VALUE = ""
    } else if (c == "\"") {
        parse_string()
    } else if (c == "-" || c ~ /[0-9]/) {
        parse_number()
    } else if (substr(src, pos, 4) == "true") {
        pos += 4
        P_TYPE = "true"
        P_VALUE = "true"
    } else if (substr(src, pos, 5) == "false") {
        pos += 5
        P_TYPE = "false"
        P_VALUE = "false"
    } else if (substr(src, pos, 4) == "null") {
        pos += 4
        P_TYPE = "null"
        P_VALUE = ""
    } else {
        fail()
    }
}
function parse_array(depth, context,    count, c) {
    expect("[")
    count = 0
    ws()
    if (substr(src, pos, 1) == "]") {
        pos++
        if (context == "whitelist") root_whitelist_count = 0
        return
    }
    while (1) {
        if (context == "whitelist") parse_value(depth + 1, "entry")
        else parse_value(depth + 1, "generic")
        if (context == "whitelist" && P_TYPE != "object") fail()
        count++
        ws()
        c = substr(src, pos, 1)
        if (c == "]") {
            pos++
            break
        }
        if (c != ",") fail()
        pos++
        ws()
        if (substr(src, pos, 1) == "]") fail()
    }
    if (context == "whitelist") {
        if (count > 5) fail()
        root_whitelist_count = count
    }
}
function parse_object(depth, context,    scope, key, c, value_type, value, has_ip, ip, slot, has_slot) {
    expect("{")
    scope = ++object_count
    ws()
    if (substr(src, pos, 1) == "}") {
        pos++
        if (context == "entry") fail()
        return
    }
    while (1) {
        key = parse_string()
        if (seen[scope SUBSEP key]) fail()
        seen[scope SUBSEP key] = 1
        expect(":")
        parse_value(depth + 1, (context == "root" && key == "whitelist") ? "whitelist" : "generic")
        value_type = P_TYPE
        value = P_VALUE

        if (context == "root") {
            if (key == "enabled") {
                if (value_type != "true") fail()
                root_enabled = 1
            } else if (key == "currentIp") {
                if (value_type != "string") fail()
                root_current_ip = value
            } else if (key == "limit") {
                if (value_type != "number" || value !~ /^[1-5]$/) fail()
                root_limit = value + 0
            } else if (key == "whitelist") {
                if (value_type != "array") fail()
                root_whitelist = 1
            } else {
                fail()
            }
        } else if (context == "entry") {
            if (key == "ip") {
                if (value_type != "string") fail()
                has_ip = 1
                ip = value
            } else if (key == "slot") {
                has_slot = 1
                if (value_type == "null") slot = ""
                else if (value_type == "string" && value == "") slot = ""
                else if (value_type == "number" && value ~ /^[0-4]$/) slot = value
                else fail()
            } else {
                fail()
            }
        }

        ws()
        c = substr(src, pos, 1)
        if (c == "}") {
            pos++
            break
        }
        if (c != ",") fail()
        pos++
        ws()
        if (substr(src, pos, 1) == "}") fail()
    }
    if (context == "entry") {
        if (!has_ip) fail()
        entry_count++
        entry_ip[entry_count] = ip
        entry_slot[entry_count] = (has_slot ? slot : "")
        if (entry_slot[entry_count] != "") {
            if (used_slot[entry_slot[entry_count]]) fail()
            used_slot[entry_slot[entry_count]] = 1
        }
    }
}
BEGIN {
    src = ""
    while ((getline line) > 0) src = src line "\n"
    src_len = length(src)
    pos = 1
    parse_value(0, "root")
    if (P_TYPE != "object") fail()
    ws()
    if (pos <= src_len) fail()
    if (!root_enabled || !root_whitelist || root_current_ip == "" || root_limit == 0) fail()
    print "enabled=true"
    print "current_ip=" root_current_ip
    print "limit=" root_limit
    print "count=" (root_whitelist_count + 0)
    for (i = 1; i <= entry_count; i++) print "entry=" entry_ip[i] "|" entry_slot[i]
}
'
}

official_json_current_ip() {
    local parsed
    parsed="$(official_json_parse "${1:-}")" || return 1
    printf '%s\n' "${parsed}" | sed -n 's/^current_ip=//p' | head -n 1
}

official_json_limit() {
    local parsed
    parsed="$(official_json_parse "${1:-}")" || return 1
    printf '%s\n' "${parsed}" | sed -n 's/^limit=//p' | head -n 1
}

official_json_has_whitelist() {
    official_json_parse "${1:-}" >/dev/null
}

official_json_enabled() {
    local parsed
    parsed="$(official_json_parse "${1:-}")" || return 1
    printf '%s\n' "${parsed}" | grep -Fqx 'enabled=true'
}

official_json_whitelist_pairs() {
    local parsed record payload ip slot
    parsed="$(official_json_parse "${1:-}")" || return 1
    while IFS= read -r record || [[ -n "${record}" ]]; do
        case "${record}" in
            entry=*)
                payload="${record#entry=}"
                ip="${payload%%|*}"
                slot="${payload#*|}"
                [[ "${payload}" == *"|"* && -n "${ip}" ]] || return 1
                printf '%s|%s\n' "${ip}" "${slot}"
                ;;
        esac
    done <<< "${parsed}"
}

official_json_ip_entry() {
    local json="$1" ip="$2" pairs pair_ip pair_slot
    pairs="$(official_json_whitelist_pairs "${json}")" || return 1
    while IFS='|' read -r pair_ip pair_slot; do
        [[ -n "${pair_ip}" && "${pair_ip}" == "${ip}" ]] && return 0
    done <<< "${pairs}"
    return 1
}

official_json_ip_slot_entry() {
    local json="$1" ip="$2" slot="$3" pairs pair_ip pair_slot
    pairs="$(official_json_whitelist_pairs "${json}")" || return 1
    while IFS='|' read -r pair_ip pair_slot; do
        [[ -n "${pair_ip}" && "${pair_ip}" == "${ip}" && "${pair_slot}" == "${slot}" ]] && return 0
    done <<< "${pairs}"
    return 1
}

official_json_safe_ip() {
    local value="${1:-}" address octet
    local -a octets=()
    [[ "${value}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/24$ ]] || return 1
    address="${value%/24}"
    IFS='.' read -r -a octets <<< "${address}"
    (( ${#octets[@]} == 4 )) || return 1
    for octet in "${octets[@]}"; do
        (( 10#${octet} <= 255 )) || return 1
    done
}

official_json_whitelist_count() {
    local parsed record payload ip count=0
    parsed="$(official_json_parse "${1:-}")" || return 1
    while IFS= read -r record || [[ -n "${record}" ]]; do
        case "${record}" in
            entry=*)
                payload="${record#entry=}"
                ip="${payload%%|*}"
                official_json_safe_ip "${ip}" || return 1
                count=$((count + 1))
                ;;
        esac
    done <<< "${parsed}"
    printf '%s\n' "${count}"
}

official_json_whitelist_state() {
    local parsed record payload ip slot out=""
    parsed="$(official_json_parse "${1:-}")" || return 1
    while IFS= read -r record || [[ -n "${record}" ]]; do
        case "${record}" in
            entry=*)
                payload="${record#entry=}"
                ip="${payload%%|*}"
                slot="${payload#*|}"
                official_json_safe_ip "${ip}" || return 1
                if [[ -n "${out}" ]]; then
                    out="${out},${ip}@${slot}"
                else
                    out="${ip}@${slot}"
                fi
                ;;
        esac
    done <<< "${parsed}"
    printf '%s\n' "${out}"
}

official_response_valid() {
    local response="${1:-}" current limit count
    official_json_parse "${response}" >/dev/null || return 1
    current="$(official_json_current_ip "${response}")" || return 1
    official_json_safe_ip "${current}" || return 1
    limit="$(official_json_limit "${response}")" || return 1
    count="$(official_json_whitelist_count "${response}")" || return 1
    [[ "${count}" =~ ^[0-9]+$ ]] || return 1
    (( count <= limit && count <= 5 ))
}

official_transport_available() {
    command -v curl >/dev/null 2>&1
}

official_report_token() {
    local token="$1" slot="${2:-}" ordinal="$3" mode="${4:-report}"
    local status_json current_ip limit response response_ip response_limit slot_text slot_label
    OFFICIAL_ITEM_STATUS="error"
    OFFICIAL_ITEM_CURRENT_IP=""
    OFFICIAL_ITEM_USED=""
    OFFICIAL_ITEM_LIMIT=""
    OFFICIAL_ITEM_WHITELIST=""
    OFFICIAL_ITEM_SLOT="$slot"
    local marker="官方账号 ${ordinal}"
    if declare -F official_account_name >/dev/null; then marker="$(official_account_name "$ordinal")"; fi
    slot_label=""
    if [[ -n "${slot}" ]]; then
        slot_label="$((10#${slot} + 1))"
        marker="${marker}（槽位 ${slot_label}）"
    fi
    status_json="$(official_direct_request "${token}" status "")" || {
        printf '%s 只读检查失败，未执行加白。\n' "${marker}" >&2
        return 1
    }
    official_response_valid "${status_json}" || {
        printf '%s 返回的只读状态无效。\n' "${marker}" >&2
        return 1
    }
    current_ip="$(official_json_current_ip "${status_json}")"
    official_json_safe_ip "${current_ip}" || {
        printf '%s 未返回有效当前出口。\n' "${marker}" >&2
        return 1
    }
    limit="$(official_json_limit "${status_json}")" || return 1
    OFFICIAL_ITEM_CURRENT_IP="$current_ip"
    OFFICIAL_ITEM_LIMIT="$limit"
    OFFICIAL_ITEM_USED="$(official_json_whitelist_count "$status_json")" || return 1
    OFFICIAL_ITEM_WHITELIST="$(official_json_whitelist_state "$status_json")" || return 1
    if official_json_ip_entry "${status_json}" "${current_ip}" && {
        [[ -z "${slot}" ]] || official_json_ip_slot_entry "${status_json}" "${current_ip}" "${slot}"
    }; then
        OFFICIAL_ITEM_STATUS="hit"
        if [[ "${mode}" == "status" ]]; then
            printf '%s 已在白名单：%s（名额 %s）。\n' "${marker}" "${current_ip}" "${limit}" >&2
        fi
        return 0
    fi
    [[ "${mode}" == "status" ]] && {
        OFFICIAL_ITEM_STATUS="missing"
        printf '%s 当前未命中白名单：%s（名额 %s）。\n' "${marker}" "${current_ip}" "${limit}" >&2
        # A valid GET with a missing current IP is a normal read-only result;
        # only transport, protocol, or configuration errors fail status.
        return 0
    }
    response="$(official_direct_request "${token}" add "${slot}")" || {
        printf '%s 加白请求失败。\n' "${marker}" >&2
        return 1
    }
    official_response_valid "${response}" || {
        printf '%s 加白响应无效。\n' "${marker}" >&2
        return 1
    }
    response_ip="$(official_json_current_ip "${response}")"
    official_json_safe_ip "${response_ip}" || {
        printf '%s 加白响应未返回有效当前出口。\n' "${marker}" >&2
        return 1
    }
    response_limit="$(official_json_limit "${response}")" || return 1
    OFFICIAL_ITEM_STATUS="added"
    OFFICIAL_ITEM_CURRENT_IP="${response_ip}"
    OFFICIAL_ITEM_LIMIT="${response_limit}"
    OFFICIAL_ITEM_USED="$(official_json_whitelist_count "${response}")" || return 1
    OFFICIAL_ITEM_WHITELIST="$(official_json_whitelist_state "${response}")" || return 1
    OFFICIAL_ADDED_COUNT=$((OFFICIAL_ADDED_COUNT + 1))
    official_json_ip_entry "${response}" "${response_ip}" || {
        printf '%s 加白后未确认当前出口。\n' "${marker}" >&2
        return 1
    }
    if [[ -n "${slot}" ]] && ! official_json_ip_slot_entry "${response}" "${response_ip}" "${slot}"; then
        printf '%s 加白后槽位校验失败。\n' "${marker}" >&2
        return 1
    fi
    slot_text=""
    [[ -n "${slot}" ]] && slot_text="，槽位 ${slot_label}"
    OFFICIAL_RESULT_NEEDS_NOTIFY="1"
    printf '%s 已更新：%s（名额 %s%s）。\n' "${marker}" "${response_ip}" "${limit}" "${slot_text}" >&2
    return 0
}

official_state_append_item() {
    local ordinal="$1" record
    record="$ordinal|$OFFICIAL_ITEM_STATUS|$OFFICIAL_ITEM_CURRENT_IP|$OFFICIAL_ITEM_WHITELIST|$OFFICIAL_ITEM_USED|$OFFICIAL_ITEM_LIMIT|$OFFICIAL_ITEM_SLOT"
    if [[ -n "$OFFICIAL_STATE_RECORDS" ]]; then
        OFFICIAL_STATE_RECORDS="$OFFICIAL_STATE_RECORDS
$record"
    else
        OFFICIAL_STATE_RECORDS="$record"
    fi
}

official_state_summary() {
    local state status last checked line payload ordinal item_status current whitelist used limit slot extra
    local list pair ip pair_slot friendly pair_label slot_label current_text details=""
    state="$(official_state_file)"
    [[ -r "$state" ]] || {
        printf '尚无官方防火墙本地状态'
        return 0
    }
    status="$(sed -n 's/^last_status=//p' "$state" | head -n 1)"
    last="$(sed -n 's/^last_attempt_at=//p' "$state" | head -n 1)"
    checked="$(sed -n 's/^last_checked_at=//p' "$state" | head -n 1)"
    [[ "$last" =~ ^[0-9]+$ ]] || last="未知"
    [[ "$checked" =~ ^[0-9]+$ ]] || checked="未知"
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            item=*)
                payload="${line#item=}"
                IFS='|' read -r ordinal item_status current whitelist used limit slot extra <<< "$payload"
                [[ -z "$extra" && "$ordinal" =~ ^[1-9][0-9]*$ && "$ordinal" -le 16 ]] || continue
                case "$item_status" in hit|missing|added|error) ;; *) continue ;; esac
                [[ -z "$current" ]] || official_json_safe_ip "$current" || continue
                [[ "$used" =~ ^[0-9]+$ && "$limit" =~ ^[1-5]$ && "$used" -le "$limit" ]] || continue
                [[ -z "$slot" || "$slot" =~ ^[0-4]$ ]] || continue
                list="$whitelist"
                friendly=""
                while [[ -n "$list" ]]; do
                    if [[ "$list" == *,* ]]; then
                        pair="${list%%,*}"
                        list="${list#*,}"
                    else
                        pair="$list"
                        list=""
                    fi
                    [[ "$pair" == *"@"* ]] || break
                    ip="${pair%@*}"
                    pair_slot="${pair##*@}"
                    official_json_safe_ip "$ip" || break
                    [[ -z "$pair_slot" || "$pair_slot" =~ ^[0-4]$ ]] || break
                    pair_label="自动"
                    [[ -n "$pair_slot" ]] && pair_label="$((10#$pair_slot + 1))"
                    [[ -n "$friendly" ]] && friendly="$friendly，"
                    friendly="$friendly$ip（槽位 $pair_label）"
                done
                [[ -z "$list" ]] || continue
                current_text="${current:-无}"
                slot_label="自动"
                [[ -n "$slot" ]] && slot_label="$((10#$slot + 1))"
                [[ -n "$details" ]] && details="$details；"
                details="$details$(if declare -F official_account_name >/dev/null; then official_account_name "$ordinal"; else printf "账号 %s" "$ordinal"; fi)：状态=$item_status；当前出口=$current_text；白名单=${friendly:-无}；已用=$used/$limit；固定槽位=$slot_label"
                ;;
        esac
    done < "$state"
    printf '状态=%s；最近尝试=%s；最近检查=%s' "${status:-未知}" "$last" "$checked"
    [[ -n "$details" ]] && printf '；明细=%s' "$details"
}

official_status_state_flush() {
    local status="$1" success="$2" failure="$3"
    OFFICIAL_RESULT_SUCCESS_COUNT="$success"
    OFFICIAL_RESULT_FAILURE_COUNT="$failure"
    official_write_state_v2 "$status" "$OFFICIAL_STATE_RECORDS" 0 0
}

official_status_once_inner() {
    local raw item token slot ordinal=0 success=0 failure=0
    OFFICIAL_STATE_RECORDS=""
    OFFICIAL_ADDED_COUNT="0"
    OFFICIAL_RESULT_SUCCESS_COUNT="0"
    OFFICIAL_RESULT_FAILURE_COUNT="0"
    OFFICIAL_RESULT_MESSAGE=""
    OFFICIAL_RESULT_STATUS=""
    OFFICIAL_RESULT_NEEDS_NOTIFY="0"
    official_channel_enabled || {
        OFFICIAL_RESULT_MESSAGE="官方防火墙未启用。"
        OFFICIAL_RESULT_STATUS="disabled"
        printf '%s\n' "${OFFICIAL_RESULT_MESSAGE}"
        return 1
    }
    official_validate_tokens || {
        OFFICIAL_RESULT_MESSAGE="官方防火墙 token 配置无效。"
        OFFICIAL_RESULT_STATUS="failed"
        return 1
    }
    official_transport_available || {
        OFFICIAL_RESULT_MESSAGE="缺少 curl，无法检查官方防火墙状态。"
        OFFICIAL_RESULT_STATUS="failed"
        printf '%s\n' "${OFFICIAL_RESULT_MESSAGE}" >&2
        return 1
    }
    raw="$(official_normalize_tokens "${PO0_FIREWALL_TOKENS}")"
    raw="${raw},"
    while [[ "${raw}" == *,* ]]; do
        item="${raw%%,*}"
        raw="${raw#*,}"
        official_parse_token_item "${item}" || continue
        token="${OFFICIAL_PARSED_TOKEN}"
        slot="${OFFICIAL_PARSED_SLOT}"
        ordinal=$((ordinal + 1))
        if official_report_token "${token}" "${slot}" "${ordinal}" status; then
            success=$((success + 1))
            OFFICIAL_RESULT_SUCCESS_COUNT="$success"
        else
            failure=$((failure + 1))
            OFFICIAL_RESULT_FAILURE_COUNT="$failure"
        fi
        official_state_append_item "$ordinal"
    done
    if (( failure > 0 )); then
        OFFICIAL_RESULT_MESSAGE="官方防火墙只读检查结束：成功 ${success} 条，失败 ${failure} 条。"
        OFFICIAL_RESULT_STATUS="partial"
        if ! official_status_state_flush "$OFFICIAL_RESULT_STATUS" "$success" "$failure"; then
            OFFICIAL_RESULT_MESSAGE="官方防火墙只读检查结束，但本地状态保存失败。"
            OFFICIAL_RESULT_STATUS="failed"
        fi
        printf '%s\n' "${OFFICIAL_RESULT_MESSAGE}" >&2
        return 1
    fi
    OFFICIAL_RESULT_MESSAGE="官方防火墙只读检查完成：成功 ${success} 条。"
    OFFICIAL_RESULT_STATUS="success"
    if ! official_status_state_flush "$OFFICIAL_RESULT_STATUS" "$success" "$failure"; then
        OFFICIAL_RESULT_MESSAGE="官方防火墙只读检查完成，但本地状态保存失败。"
        OFFICIAL_RESULT_STATUS="failed"
    fi
    printf '%s\n' "${OFFICIAL_RESULT_MESSAGE}"
    [[ "${OFFICIAL_RESULT_STATUS}" == "success" ]]
}

official_report_once() {
    local raw item token slot ordinal=0 success=0 failure=0
    OFFICIAL_STATE_RECORDS=""
    OFFICIAL_ADDED_COUNT="0"
    OFFICIAL_RESULT_SUCCESS_COUNT="0"
    OFFICIAL_RESULT_FAILURE_COUNT="0"
    OFFICIAL_RESULT_MESSAGE=""
    OFFICIAL_RESULT_STATUS=""
    OFFICIAL_RESULT_NEEDS_NOTIFY="0"
    official_channel_enabled || return 0
    official_validate_tokens || {
        OFFICIAL_RESULT_MESSAGE="官方防火墙 token 配置无效。"
        OFFICIAL_RESULT_STATUS="failed"
        printf '%s\n' "${OFFICIAL_RESULT_MESSAGE}" >&2
        return 1
    }
    if ! official_due; then
        OFFICIAL_RESULT_STATUS="skipped"
        return 0
    fi
    official_mark_attempt || {
        OFFICIAL_RESULT_MESSAGE="官方防火墙独立状态保存失败，未执行上报。"
        OFFICIAL_RESULT_STATUS="failed"
        printf '%s\n' "${OFFICIAL_RESULT_MESSAGE}" >&2
        return 1
    }
    official_transport_available || {
        OFFICIAL_RESULT_MESSAGE="缺少 curl，无法上报官方防火墙。"
        OFFICIAL_RESULT_STATUS="failed"
        official_mark_failure >/dev/null 2>&1 || true
        printf '%s\n' "${OFFICIAL_RESULT_MESSAGE}" >&2
        return 1
    }
    raw="$(official_normalize_tokens "${PO0_FIREWALL_TOKENS}")"
    raw="${raw},"
    while [[ "${raw}" == *,* ]]; do
        item="${raw%%,*}"
        raw="${raw#*,}"
        official_parse_token_item "${item}" || continue
        token="${OFFICIAL_PARSED_TOKEN}"
        slot="${OFFICIAL_PARSED_SLOT}"
        ordinal=$((ordinal + 1))
        if official_report_token "${token}" "${slot}" "${ordinal}" report; then
            success=$((success + 1))
            OFFICIAL_RESULT_SUCCESS_COUNT="$success"
        else
            failure=$((failure + 1))
            OFFICIAL_RESULT_FAILURE_COUNT="$failure"
        fi
        official_state_append_item "$ordinal"
    done
    if (( ordinal == 0 )); then
        OFFICIAL_RESULT_MESSAGE="官方防火墙没有可执行的 token。"
        OFFICIAL_RESULT_STATUS="failed"
        official_mark_failure >/dev/null 2>&1 || true
        return 1
    fi
    if (( failure > 0 )); then
        if (( success > 0 )); then
            OFFICIAL_RESULT_MESSAGE="官方防火墙上报结束：成功 ${success} 条，失败 ${failure} 条（部分成功）。"
            OFFICIAL_RESULT_STATUS="partial"
            official_mark_partial >/dev/null 2>&1 || {
                OFFICIAL_RESULT_MESSAGE="官方防火墙部分上报完成，但独立状态保存失败。"
                OFFICIAL_RESULT_STATUS="failed"
                printf '%s\n' "${OFFICIAL_RESULT_MESSAGE}" >&2
                return 1
            }
        else
            OFFICIAL_RESULT_MESSAGE="官方防火墙上报失败：${failure} 条请求均未完成。"
            OFFICIAL_RESULT_STATUS="failed"
            official_mark_failure >/dev/null 2>&1 || {
                OFFICIAL_RESULT_MESSAGE="官方防火墙上报失败，独立状态保存失败。"
                OFFICIAL_RESULT_STATUS="failed"
                printf '%s\n' "${OFFICIAL_RESULT_MESSAGE}" >&2
                return 1
            }
        fi
        printf '%s\n' "${OFFICIAL_RESULT_MESSAGE}" >&2
        return 1
    fi
    official_mark_success || {
        OFFICIAL_RESULT_MESSAGE="官方防火墙上报成功，但独立状态保存失败。"
        OFFICIAL_RESULT_STATUS="failed"
        printf '%s\n' "${OFFICIAL_RESULT_MESSAGE}" >&2
        return 1
    }
    OFFICIAL_RESULT_MESSAGE="官方防火墙上报完成：成功 ${success} 条。"
    OFFICIAL_RESULT_STATUS="success"
    return 0
}

official_status_once() {
    local lock_rc result
    if ! declare -F report_run_lock_acquire >/dev/null 2>&1; then
        official_status_once_inner
        return "$?"
    fi
    report_run_lock_acquire
    lock_rc="$?"
    if [[ "$lock_rc" == "2" ]]; then
        OFFICIAL_RESULT_MESSAGE="已有另一项上报或状态检查正在进行，本次未重复执行。"
        OFFICIAL_RESULT_STATUS="busy"
        printf '%s\n' "$OFFICIAL_RESULT_MESSAGE" >&2
        return 1
    fi
    if [[ "$lock_rc" != "0" ]]; then
        OFFICIAL_RESULT_MESSAGE="无法建立上报互斥状态，本次未执行。"
        OFFICIAL_RESULT_STATUS="failed"
        printf '%s\n' "$OFFICIAL_RESULT_MESSAGE" >&2
        return 1
    fi
    official_status_once_inner
    result="$?"
    report_run_lock_release >/dev/null 2>&1 || true
    return "$result"
}
