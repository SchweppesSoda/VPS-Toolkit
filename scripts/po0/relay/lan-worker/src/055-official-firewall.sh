# Optional PO0 official firewall reporting for the LAN Worker host itself.
#
# This is deliberately independent from DDNS, resource, WebAuth and
# self-report.  It reports only the LAN Worker's own default-route address;
# it never reports an address on behalf of a downstream client.
#
# The only public setting is PO0_FIREWALL_TOKENS.  Values are read from the
# protected settings file/environment and are never accepted as CLI values.
# API reference: https://github.com/kelenetwork/po0fw (MIT).

PO0_FIREWALL_TOKENS="${PO0_FIREWALL_TOKENS:-}"
PO0_FIREWALL_API_BASE_URL="https://124.221.69.228/api/firewall"
PO0_FIREWALL_INTERVAL_SECONDS="600"
# Request budgets are implementation details, not user configuration.  The
# normal/manual lane gets a little more time; SSH/control preflights override
# these briefly so an unavailable official service cannot hold old work.
OFFICIAL_REQUEST_CONNECT_TIMEOUT="5"
OFFICIAL_REQUEST_MAX_TIME="20"
OFFICIAL_REQUEST_RETRY="2"
OFFICIAL_PREFLIGHT_CONNECT_TIMEOUT="2"
OFFICIAL_PREFLIGHT_MAX_TIME="5"
OFFICIAL_PREFLIGHT_RETRY="0"
OFFICIAL_STATE_FILE=""
OFFICIAL_RESULT_STATUS=""
OFFICIAL_RESULT_MESSAGE=""
OFFICIAL_RESULT_NEEDS_NOTIFY="0"
OFFICIAL_SUCCESS_COUNT="0"
OFFICIAL_FAILURE_COUNT="0"
OFFICIAL_ADDED_COUNT="0"
OFFICIAL_ITEM_STATUS=""
OFFICIAL_ITEM_CURRENT_IP=""
OFFICIAL_ITEM_LIMIT=""
OFFICIAL_ITEM_USED=""
OFFICIAL_ITEM_SLOT=""
OFFICIAL_ITEM_WHITELIST=""
OFFICIAL_STATE_RECORDS=""
OFFICIAL_RUN_LOCK_HELD="0"
OFFICIAL_RUN_LOCK_PATH=""

official_now() {
    local value="${PO0_LAN_TEST_NOW:-}"
    if [[ "${value}" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$((10#${value}))"
    else
        date +%s
    fi
}

official_state_file() {
    if [[ -n "${OFFICIAL_STATE_FILE:-}" ]]; then
        printf '%s\n' "${OFFICIAL_STATE_FILE}"
        return 0
    fi
    refresh_settings_file
    printf '%s/official-firewall.state\n' "$(path_dirname "${SETTINGS_FILE}")"
}

official_state_dir() {
    path_dirname "$(official_state_file)"
}

official_last_attempt_at() {
    local state
    state="$(official_state_file)"
    [[ -r "${state}" ]] || return 1
    sed -n 's/^last_attempt_at=\([0-9][0-9]*\)$/\1/p' "${state}" | head -n 1
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
    if (( created == 1 )); then
        chmod 700 "${dir}" 2>/dev/null || return 1
    fi
    mode="$(stat -c '%a' "${dir}" 2>/dev/null || true)"
    [[ "${mode}" =~ ^[0-7]{3,4}$ ]] || return 1
    mode="${mode: -3}"
    [[ "${mode:1:1}" != [2367] && "${mode:2:1}" != [2367] ]]
}

official_run_lock_acquire() {
    local dir lock pid lock_mtime now_epoch waited=0
    [[ "${OFFICIAL_RUN_LOCK_HELD:-0}" == "1" ]] && return 0
    dir="$(official_state_dir)"
    official_secure_state_dir "${dir}" || return 1
    lock="${dir%/}/.official-firewall.lock"
    [[ ! -L "${lock}" ]] || return 1
    while ! mkdir "${lock}" 2>/dev/null; do
        [[ -d "${lock}" && ! -L "${lock}" ]] || return 1
        pid=""
        if [[ -r "${lock}/pid" && ! -L "${lock}/pid" ]]; then
            pid="$(sed -n '1p' "${lock}/pid" 2>/dev/null || true)"
        fi
        if [[ "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" 2>/dev/null; then
            (( waited < 150 )) || return 1
            sleep 0.1
            waited=$((waited + 1))
            continue
        fi
        # A lock with a dead owner is recoverable.  An empty lock is left
        # alone briefly so a concurrent owner can finish writing its pid.  If
        # the creator crashed before publishing a pid, reclaim only an old
        # exact directory; a fresh empty directory remains protected.
        if [[ -z "${pid}" ]]; then
            lock_mtime="$(stat -c '%Y' "${lock}" 2>/dev/null || true)"
            now_epoch="$(date +%s 2>/dev/null || true)"
            if [[ "${lock_mtime}" =~ ^-?[0-9]+$ && "${now_epoch}" =~ ^[0-9]+$ ]] &&
                (( now_epoch >= lock_mtime + 1 )); then
                rmdir -- "${lock}" 2>/dev/null || true
                continue
            fi
            (( waited < 150 )) || return 1
            sleep 0.1
            waited=$((waited + 1))
            continue
        fi
        rm -f -- "${lock}/pid" 2>/dev/null || return 1
        rmdir -- "${lock}" 2>/dev/null || return 1
    done
    chmod 700 "${lock}" 2>/dev/null || {
        rmdir -- "${lock}" 2>/dev/null || true
        return 1
    }
    printf '%s\n' "$$" > "${lock}/pid" || {
        rm -f -- "${lock}/pid" 2>/dev/null || true
        rmdir -- "${lock}" 2>/dev/null || true
        return 1
    }
    chmod 600 "${lock}/pid" 2>/dev/null || {
        rm -f -- "${lock}/pid" 2>/dev/null || true
        rmdir -- "${lock}" 2>/dev/null || true
        return 1
    }
    OFFICIAL_RUN_LOCK_PATH="${lock}"
    OFFICIAL_RUN_LOCK_HELD="1"
}

official_run_lock_release() {
    local lock="${OFFICIAL_RUN_LOCK_PATH:-}" pid=""
    [[ "${OFFICIAL_RUN_LOCK_HELD:-0}" == "1" && -n "${lock}" ]] || return 0
    if [[ -r "${lock}/pid" && ! -L "${lock}/pid" ]]; then
        pid="$(sed -n '1p' "${lock}/pid" 2>/dev/null || true)"
    fi
    if [[ "${pid}" == "$$" ]]; then
        rm -f -- "${lock}/pid" 2>/dev/null || true
        rmdir -- "${lock}" 2>/dev/null || true
    fi
    OFFICIAL_RUN_LOCK_PATH=""
    OFFICIAL_RUN_LOCK_HELD="0"
}

official_due() {
    local now last
    [[ "${SCHEDULED_RUN:-0}" == "1" ]] || return 0
    [[ "${FORCE_REPORT:-0}" == "1" ]] && return 0
    now="$(official_now)"
    last="$(official_last_attempt_at 2>/dev/null || true)"
    [[ "${last}" =~ ^[0-9]+$ ]] || return 0
    (( now < last || now - last >= PO0_FIREWALL_INTERVAL_SECONDS ))
}

official_slot_display() {
    local slot="${1:-}"
    if [[ "${slot}" =~ ^[0-4]$ ]]; then
        printf '槽位 %s' "$((10#${slot} + 1))"
    else
        printf '自动槽位'
    fi
}

official_write_state() {
    local status="$1"
    local records="${2:-}"
    local now state dir tmp old_umask
    state="$(official_state_file)"
    dir="$(path_dirname "${state}")"
    official_secure_state_dir "${dir}" || return 1
    [[ ! -L "${state}" ]] || return 1
    old_umask="$(umask)"
    umask 077
    tmp="$(mktemp "${dir%/}/.po0-official-firewall-state.XXXXXX" 2>/dev/null)" || {
        umask "${old_umask}"
        return 1
    }
    if [[ ! -f "${tmp}" || -L "${tmp}" ]] || ! chmod 600 "${tmp}" 2>/dev/null; then
        rm -f -- "${tmp}" 2>/dev/null || true
        umask "${old_umask}"
        return 1
    fi
    now="$(official_now)"
    {
        printf 'last_attempt_at=%s\n' "$(official_last_attempt_at 2>/dev/null || printf '0')"
        printf 'last_status=%s\n' "${status}"
        printf 'last_checked_at=%s\n' "${now}"
        printf 'success_count=%s\n' "${OFFICIAL_SUCCESS_COUNT:-0}"
        printf 'failure_count=%s\n' "${OFFICIAL_FAILURE_COUNT:-0}"
        printf 'added_count=%s\n' "${OFFICIAL_ADDED_COUNT:-0}"
        while IFS= read -r record || [[ -n "${record}" ]]; do
            [[ -n "${record}" ]] || continue
            printf 'item=%s\n' "${record}"
        done <<< "${records}"
    } > "${tmp}" || {
        rm -f -- "${tmp}" 2>/dev/null || true
        umask "${old_umask}"
        return 1
    }
    mv -f -- "${tmp}" "${state}" || {
        rm -f -- "${tmp}" 2>/dev/null || true
        umask "${old_umask}"
        return 1
    }
    umask "${old_umask}"
    chmod 600 "${state}" 2>/dev/null || true
}

official_mark_attempt() {
    local state now dir tmp old_umask
    state="$(official_state_file)"
    dir="$(path_dirname "${state}")"
    official_secure_state_dir "${dir}" || return 1
    [[ ! -L "${state}" ]] || return 1
    old_umask="$(umask)"
    umask 077
    tmp="$(mktemp "${dir%/}/.po0-official-firewall-attempt.XXXXXX" 2>/dev/null)" || {
        umask "${old_umask}"
        return 1
    }
    now="$(official_now)"
    {
        printf 'last_attempt_at=%s\n' "${now}"
        printf 'last_status=running\n'
    } > "${tmp}" || {
        rm -f -- "${tmp}" 2>/dev/null || true
        umask "${old_umask}"
        return 1
    }
    chmod 600 "${tmp}" 2>/dev/null || true
    mv -f -- "${tmp}" "${state}" || {
        rm -f -- "${tmp}" 2>/dev/null || true
        umask "${old_umask}"
        return 1
    }
    umask "${old_umask}"
    chmod 600 "${state}" 2>/dev/null || true
}

official_validate_token() {
    local value="${1:-}"
    (( ${#value} >= 8 && ${#value} <= 246 )) || return 1
    [[ "${value}" =~ ^pgnfw_[A-Za-z0-9._~-]{1,240}$ ]]
}

official_validate_slot() {
    [[ -z "${1:-}" || "${1}" =~ ^[0-4]$ ]]
}

official_parse_token_item() {
    local value="$(trim "${1:-}")" token slot="" extra
    OFFICIAL_PARSED_TOKEN=""
    OFFICIAL_PARSED_SLOT=""
    [[ -n "${value}" ]] || return 1
    [[ "${value}" != *$'\n'* && "${value}" != *$'\r'* ]] || return 1
    if [[ "${value}" == *@* ]]; then
        token="${value%@*}"
        slot="${value##*@}"
        [[ "${value}" != *"@"*"@"* ]] || return 1
        [[ -n "${token}" && -n "${slot}" ]] || return 1
    else
        token="${value}"
    fi
    token="$(trim "${token}")"
    slot="$(trim "${slot}")"
    official_validate_token "${token}" || return 1
    official_validate_slot "${slot}" || return 1
    OFFICIAL_PARSED_TOKEN="${token}"
    OFFICIAL_PARSED_SLOT="${slot}"
}

official_validate_tokens() {
    local raw="${PO0_FIREWALL_TOKENS:-}" rest item count=0 key seen=';'
    [[ -n "$(trim "${raw}")" ]] || return 0
    [[ "${raw}" != ,* && "${raw}" != *, && "${raw}" != *,,* ]] || {
        printf '官方防火墙 token 列表包含空项。\n' >&2
        return 1
    }
    rest="${raw},"
    while [[ "${rest}" == *,* ]]; do
        item="${rest%%,*}"
        rest="${rest#*,}"
        item="$(trim "${item}")"
        [[ -n "${item}" ]] || {
            printf '官方防火墙 token 列表包含空项。\n' >&2
            return 1
        }
        official_parse_token_item "${item}" || {
            printf '官方防火墙 token 配置无效（格式应为 token 或 token@0..4）。\n' >&2
            return 1
        }
        # The LAN Worker always uses its own default route.  A token is one
        # account, not a set of independently addressable WAN bindings, so
        # reject the same account even when one item adds a different slot.
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
}

official_tokens_count() {
    local raw="${PO0_FIREWALL_TOKENS:-}" rest item count=0
    [[ -n "$(trim "${raw}")" ]] || { printf '0\n'; return 0; }
    official_validate_tokens >/dev/null 2>&1 || { printf '0\n'; return 0; }
    rest="${raw},"
    while [[ "${rest}" == *,* ]]; do
        item="${rest%%,*}"
        rest="${rest#*,}"
        [[ -n "$(trim "${item}")" ]] || continue
        count=$((count + 1))
    done
    printf '%s\n' "${count}"
}

official_channel_enabled() {
    [[ -n "$(trim "${PO0_FIREWALL_TOKENS:-}")" ]]
}

official_tokens_summary() {
    local count slot item rest slots='' seen=';' invalid=0
    [[ -n "$(trim "${PO0_FIREWALL_TOKENS:-}")" ]] || {
        printf '未启用（默认关闭）'
        return 0
    }
    count="$(official_tokens_count)"
    [[ "${count}" != "0" ]] || { printf '配置有误'; return 0; }
    rest="${PO0_FIREWALL_TOKENS:-},"
    while [[ "${rest}" == *,* ]]; do
        item="${rest%%,*}"
        rest="${rest#*,}"
        official_parse_token_item "${item}" || { invalid=1; continue; }
        slot="${OFFICIAL_PARSED_SLOT}"
        if [[ -n "${slot}" && "${seen}" != *";${slot};"* ]]; then
            seen="${seen}${slot};"
            slots="${slots}${slots:+、}$(official_slot_display "${slot}")"
        fi
    done
    (( invalid == 0 )) || { printf '配置有误'; return 0; }
    printf '已配置 %s 个（内容不显示）' "${count}"
    [[ -n "${slots}" ]] && printf '，%s' "${slots}"
}

official_read_secret_prompt() {
    local prompt="$1" value
    if [[ -r /dev/tty && -w /dev/tty ]]; then
        printf '%s' "${prompt}" > /dev/tty || return 1
        IFS= read -r -s value < /dev/tty || return 1
        printf '\n' > /dev/tty || true
    else
        IFS= read -r -s value || return 1
    fi
    printf '%s\n' "${value}"
}

official_configure_interactive() {
    local input
    print_panel_section "PO0 官方防火墙（LAN Worker 本机出口）"
    print_panel_row "当前配置" "$(official_tokens_summary)"
    print_panel_row "作用范围" "只给这台 LAN Worker 的实际默认出口加白，不替下游客户端上报"
    print_panel_row "自动周期" "每 10 分钟检查一次；失败也不会阻断原有 SSH/control"
    input="$(official_read_secret_prompt 'Token 列表（逗号分隔，可写 token@0..4；回车保留，- 清空）： ')" || return 1
    input="$(trim "${input}")"
    if [[ -n "${input}" ]]; then
        if [[ "${input}" == '-' ]]; then
            PO0_FIREWALL_TOKENS=""
        else
            PO0_FIREWALL_TOKENS="${input}"
            official_validate_tokens || return 1
        fi
        save_local_settings || return 1
        printf '已保存官方防火墙设置（token 内容不显示）。\n'
    else
        printf '保留现有官方防火墙设置。\n'
    fi
}

official_direct_request() (
    local token="$1" operation="$2" slot="${3:-}"
    local url method escaped_url request_dir body_file header_file http_code curl_rc body_size header_size
    official_validate_token "${token}" || return 1
    case "${operation}" in
        status)
            [[ -z "${slot}" ]] || return 1
            method='GET'
            url="${PO0_FIREWALL_API_BASE_URL}/${token}"
            ;;
        add)
            official_validate_slot "${slot}" || return 1
            method='POST'
            url="${PO0_FIREWALL_API_BASE_URL}/${token}/add"
            [[ -n "${slot}" ]] && url="${url}?slot=${slot}"
            ;;
        *) return 1 ;;
    esac
    umask 077
    request_dir="$(mktemp -d "${TMPDIR:-/tmp}/po0-lan-official-request.XXXXXX" 2>/dev/null)" || return 1
    trap 'rm -rf -- "${request_dir}"' EXIT
    trap 'rm -rf -- "${request_dir}"; exit 129' HUP
    trap 'rm -rf -- "${request_dir}"; exit 130' INT
    trap 'rm -rf -- "${request_dir}"; exit 143' TERM
    chmod 700 "${request_dir}" 2>/dev/null || return 1
    body_file="${request_dir}/body"
    header_file="${request_dir}/headers"
    : > "${body_file}" || return 1
    : > "${header_file}" || return 1
    chmod 600 "${body_file}" "${header_file}" 2>/dev/null || return 1
    escaped_url="${url//\\/\\\\}"
    escaped_url="${escaped_url//\"/\\\"}"
    if http_code="$(
        {
            printf 'url = "%s"\n' "${escaped_url}"
            printf 'request = "%s"\n' "${method}"
        } | env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
            curl -4sS --noproxy '*' --proto '=https' --tlsv1.2 \
            --connect-timeout "${OFFICIAL_REQUEST_CONNECT_TIMEOUT}" \
            --max-time "${OFFICIAL_REQUEST_MAX_TIME}" \
            --retry "${OFFICIAL_REQUEST_RETRY}" --retry-delay 2 --max-filesize 65536 --output "${body_file}" \
            --dump-header "${header_file}" --write-out '%{http_code}' --config - 2>/dev/null
    )"; then
        curl_rc=0
    else
        curl_rc=$?
    fi
    [[ -f "${body_file}" && ! -L "${body_file}" && -f "${header_file}" && ! -L "${header_file}" ]] || return 1
    body_size="$(wc -c < "${body_file}" 2>/dev/null || true)"
    header_size="$(wc -c < "${header_file}" 2>/dev/null || true)"
    [[ "${body_size}" =~ ^[0-9]+$ && "${header_size}" =~ ^[0-9]+$ ]] || return 1
    (( body_size <= 65536 && header_size <= 16384 )) || return 1
    (( curl_rc == 0 )) || return 1
    [[ "${http_code}" =~ ^2[0-9]{2}$ ]] || return 1
    cat "${body_file}"
)

official_json_compact() {
    local value="${1:-}"
    # Bash-only whitespace removal keeps the parser usable on small LAN
    # Worker installs and avoids a process per field while retaining the
    # strict shape checks below.
    value="${value//[[:space:]]/}"
    printf '%s\n' "${value}"
}

official_json_top_level_fields() {
    local json="${1:-}" body char field="" depth=0 in_string=0 escaped=0 i
    [[ "${json:0:1}" == '{' && "${json: -1}" == '}' ]] || return 1
    (( ${#json} >= 2 )) || return 1
    body="${json:1:${#json}-2}"
    [[ -n "${body}" ]] || return 1
    for (( i=0; i<${#body}; i++ )); do
        char="${body:i:1}"
        if (( in_string == 1 )); then
            field+="${char}"
            if (( escaped == 1 )); then
                escaped=0
            elif [[ "${char}" == "\\" ]]; then
                escaped=1
            elif [[ "${char}" == '"' ]]; then
                in_string=0
            fi
            continue
        fi
        case "${char}" in
            '"')
                in_string=1
                field+="${char}"
                ;;
            '{'|'[')
                depth=$((depth + 1))
                field+="${char}"
                ;;
            '}'|']')
                (( depth > 0 )) || return 1
                depth=$((depth - 1))
                field+="${char}"
                ;;
            ',')
                if (( depth == 0 )); then
                    [[ -n "${field}" ]] || return 1
                    printf '%s\n' "${field}"
                    field=""
                else
                    field+="${char}"
                fi
                ;;
            *)
                field+="${char}"
                ;;
        esac
    done
    (( in_string == 0 && depth == 0 )) || return 1
    [[ -n "${field}" ]] || return 1
    printf '%s\n' "${field}"
}

official_json_field_split() {
    local field="${1:-}"
    [[ "${field}" =~ ^\"([A-Za-z][A-Za-z0-9]*)\":(.*)$ ]] || return 1
    [[ -n "${BASH_REMATCH[2]}" ]] || return 1
    OFFICIAL_JSON_FIELD_KEY="${BASH_REMATCH[1]}"
    OFFICIAL_JSON_FIELD_VALUE="${BASH_REMATCH[2]}"
}

official_json_decode_ip_string() {
    local raw="${1:-}" inner char next out="" i=0
    [[ "${raw:0:1}" == '"' && "${raw: -1}" == '"' ]] || return 1
    (( ${#raw} >= 2 )) || return 1
    inner="${raw:1:${#raw}-2}"
    while (( i < ${#inner} )); do
        char="${inner:i:1}"
        if [[ "${char}" == "\\" ]]; then
            next="${inner:i:2}"
            [[ "${next}" == '\/' ]] || return 1
            out+='/'
            i=$((i + 2))
            continue
        fi
        [[ "${char}" =~ ^[0-9./]$ ]] || return 1
        out+="${char}"
        i=$((i + 1))
    done
    [[ -n "${out}" ]] || return 1
    printf '%s\n' "${out}"
}

official_json_current_ip() {
    local compact fields field count=0 value=""
    compact="$(official_json_compact "${1:-}")"
    fields="$(official_json_top_level_fields "${compact}")" || return 1
    while IFS= read -r field || [[ -n "${field}" ]]; do
        official_json_field_split "${field}" || return 1
        if [[ "${OFFICIAL_JSON_FIELD_KEY}" == currentIp ]]; then
            count=$((count + 1))
            value="$(official_json_decode_ip_string "${OFFICIAL_JSON_FIELD_VALUE}")" || return 1
        fi
    done <<< "${fields}"
    [[ "${count}" == 1 ]] || return 1
    printf '%s\n' "${value}"
}

official_json_limit() {
    local compact fields field count=0 value=""
    compact="$(official_json_compact "${1:-}")"
    fields="$(official_json_top_level_fields "${compact}")" || return 1
    while IFS= read -r field || [[ -n "${field}" ]]; do
        official_json_field_split "${field}" || return 1
        if [[ "${OFFICIAL_JSON_FIELD_KEY}" == limit ]]; then
            count=$((count + 1))
            value="${OFFICIAL_JSON_FIELD_VALUE}"
        fi
    done <<< "${fields}"
    [[ "${count}" == 1 && "${value}" =~ ^[1-5]$ ]] || return 1
    printf '%s\n' "${value}"
}

official_json_array_entries() {
    local json="${1:-}" body char entry="" depth=0 in_string=0 escaped=0 i
    [[ "${json:0:1}" == '[' && "${json: -1}" == ']' ]] || return 1
    (( ${#json} >= 2 )) || return 1
    body="${json:1:${#json}-2}"
    [[ -n "${body}" ]] || return 0
    for (( i=0; i<${#body}; i++ )); do
        char="${body:i:1}"
        if (( in_string == 1 )); then
            entry+="${char}"
            if (( escaped == 1 )); then
                escaped=0
            elif [[ "${char}" == "\\" ]]; then
                escaped=1
            elif [[ "${char}" == '"' ]]; then
                in_string=0
            fi
            continue
        fi
        case "${char}" in
            '"')
                in_string=1
                entry+="${char}"
                ;;
            '{'|'[')
                depth=$((depth + 1))
                entry+="${char}"
                ;;
            '}'|']')
                (( depth > 0 )) || return 1
                depth=$((depth - 1))
                entry+="${char}"
                ;;
            ',')
                if (( depth == 0 )); then
                    [[ -n "${entry}" ]] || return 1
                    printf '%s\n' "${entry}"
                    entry=""
                else
                    entry+="${char}"
                fi
                ;;
            *)
                entry+="${char}"
                ;;
        esac
    done
    (( in_string == 0 && depth == 0 )) || return 1
    [[ -n "${entry}" ]] || return 1
    printf '%s\n' "${entry}"
}

official_json_whitelist_body() {
    local compact fields field count=0 value=""
    compact="$(official_json_compact "${1:-}")"
    fields="$(official_json_top_level_fields "${compact}")" || return 1
    while IFS= read -r field || [[ -n "${field}" ]]; do
        official_json_field_split "${field}" || return 1
        if [[ "${OFFICIAL_JSON_FIELD_KEY}" == whitelist ]]; then
            count=$((count + 1))
            value="${OFFICIAL_JSON_FIELD_VALUE}"
        fi
    done <<< "${fields}"
    [[ "${count}" == 1 && "${value:0:1}" == '[' && "${value: -1}" == ']' ]] || return 1
    printf '%s\n' "${value:1:${#value}-2}"
}

official_json_whitelist_pairs() {
    local body entries object fields field key value ip slot ip_count slot_count
    body="$(official_json_whitelist_body "${1:-}")" || return 1
    [[ -n "${body}" ]] || return 0
    entries="$(official_json_array_entries "[${body}]")" || return 1
    while IFS= read -r object || [[ -n "${object}" ]]; do
        [[ "${object}" == \{*\} ]] || return 1
        fields="$(official_json_top_level_fields "${object}")" || return 1
        ip="" slot="" ip_count=0 slot_count=0
        while IFS= read -r field || [[ -n "${field}" ]]; do
            official_json_field_split "${field}" || return 1
            key="${OFFICIAL_JSON_FIELD_KEY}"
            value="${OFFICIAL_JSON_FIELD_VALUE}"
            case "${key}" in
                ip)
                    ip_count=$((ip_count + 1))
                    ip="$(official_json_decode_ip_string "${value}")" || return 1
                    ;;
                slot)
                    slot_count=$((slot_count + 1))
                    case "${value}" in
                        null|'""') slot="" ;;
                        [0-4]) slot="${value}" ;;
                        *) return 1 ;;
                    esac
                    ;;
                *) return 1 ;;
            esac
        done <<< "${fields}"
        [[ "${ip_count}" == 1 && "${slot_count}" == 1 ]] || return 1
        official_json_safe_ip "${ip}" || return 1
        printf '%s|%s\n' "${ip}" "${slot}"
    done <<< "${entries}"
}

official_json_safe_ip() {
    local value="${1:-}" address octet
    local -a octets=()
    [[ "${value}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/24$ ]] || return 1
    address="${value%/24}"
    IFS='.' read -r -a octets <<< "${address}"
    (( ${#octets[@]} == 4 )) || return 1
    for octet in "${octets[@]}"; do
        [[ "${octet}" =~ ^[0-9]{1,3}$ ]] || return 1
        (( 10#${octet} <= 255 )) || return 1
    done
}

official_json_whitelist_count() {
    local pairs pair_ip pair_slot count=0 seen_slots=';'
    pairs="$(official_json_whitelist_pairs "${1:-}")" || return 1
    while IFS='|' read -r pair_ip pair_slot || [[ -n "${pair_ip}" ]]; do
        [[ -n "${pair_ip}" ]] || continue
        official_json_safe_ip "${pair_ip}" || return 1
        if [[ -n "${pair_slot}" ]]; then
            [[ "${seen_slots}" != *";${pair_slot};"* ]] || return 1
            seen_slots="${seen_slots}${pair_slot};"
        fi
        count=$((count + 1))
    done <<< "${pairs}"
    printf '%s\n' "${count}"
}

official_json_key_count() {
    local fields field key="${2:-}" count=0
    fields="$(official_json_top_level_fields "${1:-}")" || {
        printf '0\n'
        return 0
    }
    while IFS= read -r field || [[ -n "${field}" ]]; do
        official_json_field_split "${field}" || continue
        [[ "${OFFICIAL_JSON_FIELD_KEY}" == "${key}" ]] && count=$((count + 1))
    done <<< "${fields}"
    printf '%s\n' "${count}"
}

official_json_keys_valid() {
    local fields field key
    fields="$(official_json_top_level_fields "${1:-}")" || return 1
    while IFS= read -r field || [[ -n "${field}" ]]; do
        official_json_field_split "${field}" || return 1
        key="${OFFICIAL_JSON_FIELD_KEY}"
        case "${key}" in
            enabled|currentIp|whitelist|limit|ip|slot) ;;
            *) return 1 ;;
        esac
    done
}

official_json_whitelist_ips() {
    local pairs pair_ip pair_slot out=""
    pairs="$(official_json_whitelist_pairs "${1:-}")" || return 1
    while IFS='|' read -r pair_ip pair_slot || [[ -n "${pair_ip}" ]]; do
        [[ -n "${pair_ip}" ]] || continue
        official_json_safe_ip "${pair_ip}" || return 1
        # Keep the server-reported slot beside each IP.  The delimiter is
        # safe because validated CIDRs contain neither comma nor @.  An empty
        # suffix means the API selected an automatic slot.
        out="${out}${out:+,}${pair_ip}@${pair_slot}"
    done <<< "${pairs}"
    printf '%s\n' "${out}"
}

official_json_ip_entry() {
    local pair_ip pair_slot pairs
    pairs="$(official_json_whitelist_pairs "${1:-}")" || return 1
    while IFS='|' read -r pair_ip pair_slot || [[ -n "${pair_ip}" ]]; do
        [[ "${pair_ip}" == "${2:-}" ]] && return 0
    done <<< "${pairs}"
    return 1
}

official_json_ip_slot_entry() {
    local pair_ip pair_slot pairs
    pairs="$(official_json_whitelist_pairs "${1:-}")" || return 1
    while IFS='|' read -r pair_ip pair_slot || [[ -n "${pair_ip}" ]]; do
        [[ "${pair_ip}" == "${2:-}" && "${pair_slot}" == "${3:-}" ]] && return 0
    done <<< "${pairs}"
    return 1
}

official_response_valid() {
    local response="${1:-}" compact fields field key value
    local current="" limit="" count="" enabled_count=0 current_count=0 whitelist_count=0 limit_count=0
    (( ${#response} <= 65536 )) || return 1
    compact="$(official_json_compact "${response}")"
    fields="$(official_json_top_level_fields "${compact}")" || return 1
    while IFS= read -r field || [[ -n "${field}" ]]; do
        official_json_field_split "${field}" || return 1
        key="${OFFICIAL_JSON_FIELD_KEY}"
        value="${OFFICIAL_JSON_FIELD_VALUE}"
        case "${key}" in
            enabled)
                enabled_count=$((enabled_count + 1))
                [[ "${value}" == true ]] || return 1
                ;;
            currentIp)
                current_count=$((current_count + 1))
                ;;
            whitelist)
                whitelist_count=$((whitelist_count + 1))
                ;;
            limit)
                limit_count=$((limit_count + 1))
                ;;
            *) return 1 ;;
        esac
    done <<< "${fields}"
    [[ "${enabled_count}" == 1 && "${current_count}" == 1 && "${whitelist_count}" == 1 && "${limit_count}" == 1 ]] || return 1
    current="$(official_json_current_ip "${response}")"
    official_json_safe_ip "${current}" || return 1
    limit="$(official_json_limit "${response}")" || return 1
    count="$(official_json_whitelist_count "${response}")" || return 1
    [[ "${count}" =~ ^[0-9]+$ && "${count}" -le "${limit}" && "${count}" -le 5 ]]
}

official_append_state_item() {
    local ordinal="$1"
    # This record is intentionally account-ordinal based.  It contains only
    # validated response data; the token itself never enters local state.
    local record="${ordinal}|${OFFICIAL_ITEM_STATUS:-error}|${OFFICIAL_ITEM_CURRENT_IP:-}|${OFFICIAL_ITEM_WHITELIST:-}|${OFFICIAL_ITEM_USED:-}|${OFFICIAL_ITEM_LIMIT:-}|${OFFICIAL_ITEM_SLOT:-}"
    OFFICIAL_STATE_RECORDS="${OFFICIAL_STATE_RECORDS}${OFFICIAL_STATE_RECORDS:+$'\n'}${record}"
}

official_report_token() {
    local token="$1" slot="${2:-}" ordinal="$3" mode="${4:-report}"
    local status_json current_ip limit response response_ip response_limit used
    local marker="官方账号 ${ordinal}"
    OFFICIAL_ITEM_STATUS='error'
    OFFICIAL_ITEM_CURRENT_IP=''
    OFFICIAL_ITEM_LIMIT=''
    OFFICIAL_ITEM_USED=''
    OFFICIAL_ITEM_SLOT="${slot}"
    OFFICIAL_ITEM_WHITELIST=''
    [[ -n "${slot}" ]] && marker="${marker}（$(official_slot_display "${slot}")）"
    status_json="$(official_direct_request "${token}" status "")" || {
        [[ "${mode}" == 'status' ]] && printf '%s：只读检查失败，未执行加白。\n' "${marker}" >&2
        return 1
    }
    official_response_valid "${status_json}" || {
        [[ "${mode}" == 'status' ]] && printf '%s：返回状态无效。\n' "${marker}" >&2
        return 1
    }
    current_ip="$(official_json_current_ip "${status_json}")"
    limit="$(official_json_limit "${status_json}")" || return 1
    used="$(official_json_whitelist_count "${status_json}")" || return 1
    OFFICIAL_ITEM_WHITELIST="$(official_json_whitelist_ips "${status_json}")" || return 1
    OFFICIAL_ITEM_CURRENT_IP="${current_ip}"
    OFFICIAL_ITEM_LIMIT="${limit}"
    OFFICIAL_ITEM_USED="${used}"
    if official_json_ip_entry "${status_json}" "${current_ip}" && {
        [[ -z "${slot}" ]] || official_json_ip_slot_entry "${status_json}" "${current_ip}" "${slot}"
    }; then
        OFFICIAL_ITEM_STATUS='hit'
        if [[ "${mode}" == 'status' ]]; then
            printf '%s：已命中 %s（%s，已用 %s/%s）。\n' "${marker}" "${current_ip}" "$(official_slot_display "${slot}")" "${used}" "${limit}"
        fi
        return 0
    fi
    if [[ "${mode}" == 'status' ]]; then
        OFFICIAL_ITEM_STATUS='missing'
        printf '%s：当前 %s 未命中（只读，不加白；已用 %s/%s）。\n' "${marker}" "${current_ip}" "${used}" "${limit}"
        return 0
    fi
    response="$(official_direct_request "${token}" add "${slot}")" || {
        printf '%s：加白失败。\n' "${marker}" >&2
        return 1
    }
    official_response_valid "${response}" || {
        printf '%s：加白响应无效。\n' "${marker}" >&2
        return 1
    }
    response_ip="$(official_json_current_ip "${response}")"
    response_limit="$(official_json_limit "${response}")" || return 1
    OFFICIAL_ITEM_WHITELIST="$(official_json_whitelist_ips "${response}")" || return 1
    official_json_ip_entry "${response}" "${response_ip}" || {
        printf '%s：加白后未确认当前出口。\n' "${marker}" >&2
        return 1
    }
    if [[ -n "${slot}" ]] && ! official_json_ip_slot_entry "${response}" "${response_ip}" "${slot}"; then
        printf '%s：加白后槽位校验失败。\n' "${marker}" >&2
        return 1
    fi
    used="$(official_json_whitelist_count "${response}")" || return 1
    OFFICIAL_ITEM_STATUS='added'
    OFFICIAL_ITEM_CURRENT_IP="${response_ip}"
    OFFICIAL_ITEM_LIMIT="${response_limit}"
    OFFICIAL_ITEM_USED="${used}"
    OFFICIAL_ADDED_COUNT=$((OFFICIAL_ADDED_COUNT + 1))
    printf '%s：已更新 %s（%s，已用 %s/%s）。\n' "${marker}" "${response_ip}" "$(official_slot_display "${slot}")" "${used}" "${response_limit}"
    return 0
}

official_run_items() {
    local mode="$1" raw item token slot ordinal=0
    OFFICIAL_SUCCESS_COUNT=0
    OFFICIAL_FAILURE_COUNT=0
    OFFICIAL_ADDED_COUNT=0
    OFFICIAL_STATE_RECORDS=''
    raw="${PO0_FIREWALL_TOKENS:-},"
    while [[ "${raw}" == *,* ]]; do
        item="${raw%%,*}"
        raw="${raw#*,}"
        [[ -n "$(trim "${item}")" ]] || continue
        official_parse_token_item "${item}" || continue
        token="${OFFICIAL_PARSED_TOKEN}"
        slot="${OFFICIAL_PARSED_SLOT}"
        ordinal=$((ordinal + 1))
        if official_report_token "${token}" "${slot}" "${ordinal}" "${mode}"; then
            OFFICIAL_SUCCESS_COUNT=$((OFFICIAL_SUCCESS_COUNT + 1))
        else
            OFFICIAL_FAILURE_COUNT=$((OFFICIAL_FAILURE_COUNT + 1))
        fi
        official_append_state_item "${ordinal}"
    done
    (( ordinal > 0 ))
}

official_status_once() {
    local rc=0 state_rc=0 lan_lock_owned=0 official_lock_owned=0
    OFFICIAL_RESULT_STATUS='disabled'
    OFFICIAL_RESULT_MESSAGE='官方防火墙未启用。'
    if ! official_channel_enabled; then
        printf '%s\n' '官方防火墙：未启用（默认关闭）。'
        return 0
    fi
    official_validate_tokens || {
        OFFICIAL_RESULT_STATUS='failed'
        OFFICIAL_RESULT_MESSAGE='官方防火墙 token 配置无效。'
        return 1
    }
    command -v curl >/dev/null 2>&1 || {
        OFFICIAL_RESULT_STATUS='failed'
        OFFICIAL_RESULT_MESSAGE='缺少 curl，无法检查官方防火墙状态。'
        printf '%s\n' "${OFFICIAL_RESULT_MESSAGE}" >&2
        return 1
    }
    if [[ "${LAN_STATE_LOCK_HELD:-0}" != "1" ]]; then
        if ! lan_state_lock; then
            OFFICIAL_RESULT_STATUS='failed'
            OFFICIAL_RESULT_MESSAGE='官方防火墙状态检查无法取得本地状态锁。'
            printf '%s\n' "${OFFICIAL_RESULT_MESSAGE}" >&2
            return 1
        fi
        lan_lock_owned=1
    fi
    if [[ "${OFFICIAL_RUN_LOCK_HELD:-0}" != "1" ]]; then
        if ! official_run_lock_acquire; then
            if (( lan_lock_owned == 1 )); then lan_state_unlock; fi
            OFFICIAL_RESULT_STATUS='failed'
            OFFICIAL_RESULT_MESSAGE='官方防火墙状态检查正在进行，请稍后重试。'
            printf '%s\n' "${OFFICIAL_RESULT_MESSAGE}" >&2
            return 1
        fi
        official_lock_owned=1
    fi
    official_run_items status || true
    [[ "${OFFICIAL_FAILURE_COUNT}" == '0' ]] || rc=1
    # A read-only status refresh may update the cached response details, but
    # must preserve last_attempt_at so it cannot make a scheduled report look
    # newly attempted.  official_write_state reads and carries that field.
    if ! official_write_state status "${OFFICIAL_STATE_RECORDS}"; then
        state_rc=1
        rc=1
    fi
    if (( official_lock_owned == 1 )); then official_run_lock_release; fi
    if (( lan_lock_owned == 1 )); then lan_state_unlock; fi
    if [[ "${state_rc}" != '0' ]]; then
        OFFICIAL_RESULT_STATUS='failed'
        OFFICIAL_RESULT_MESSAGE='官方防火墙状态已查询，但本地状态保存失败。'
    elif [[ "${rc}" == '0' ]]; then
        OFFICIAL_RESULT_STATUS='success'
        OFFICIAL_RESULT_MESSAGE="官方防火墙只读检查完成：成功 ${OFFICIAL_SUCCESS_COUNT} 条。"
    else
        OFFICIAL_RESULT_STATUS='partial'
        OFFICIAL_RESULT_MESSAGE="官方防火墙只读检查结束：成功 ${OFFICIAL_SUCCESS_COUNT} 条，失败 ${OFFICIAL_FAILURE_COUNT} 条。"
    fi
    printf '%s\n' "${OFFICIAL_RESULT_MESSAGE}" >&2
    return "${rc}"
}

official_report_once() {
    local rc=0 status lan_lock_owned=0 official_lock_owned=0
    OFFICIAL_RESULT_STATUS='disabled'
    OFFICIAL_RESULT_MESSAGE=''
    OFFICIAL_RESULT_NEEDS_NOTIFY='0'
    official_channel_enabled || return 0
    official_validate_tokens || {
        OFFICIAL_RESULT_STATUS='failed'
        OFFICIAL_RESULT_MESSAGE='官方防火墙 token 配置无效。'
        printf '%s\n' "${OFFICIAL_RESULT_MESSAGE}" >&2
        return 1
    }
    command -v curl >/dev/null 2>&1 || {
        OFFICIAL_RESULT_STATUS='failed'
        OFFICIAL_RESULT_MESSAGE='缺少 curl，无法上报官方防火墙。'
        printf '%s\n' "${OFFICIAL_RESULT_MESSAGE}" >&2
        return 1
    }
    if [[ "${LAN_STATE_LOCK_HELD:-0}" != "1" ]]; then
        if ! lan_state_lock; then
            OFFICIAL_RESULT_STATUS='failed'
            OFFICIAL_RESULT_MESSAGE='官方防火墙无法取得本地状态锁。'
            printf '%s\n' "${OFFICIAL_RESULT_MESSAGE}" >&2
            return 1
        fi
        lan_lock_owned=1
    fi
    if [[ "${OFFICIAL_RUN_LOCK_HELD:-0}" != "1" ]]; then
        if ! official_run_lock_acquire; then
            if (( lan_lock_owned == 1 )); then lan_state_unlock; fi
            OFFICIAL_RESULT_STATUS='failed'
            OFFICIAL_RESULT_MESSAGE='官方防火墙上报正在进行，请稍后重试。'
            printf '%s\n' "${OFFICIAL_RESULT_MESSAGE}" >&2
            return 1
        fi
        official_lock_owned=1
    fi
    if ! official_due; then
        OFFICIAL_RESULT_STATUS='skipped'
        if (( official_lock_owned == 1 )); then official_run_lock_release; fi
        if (( lan_lock_owned == 1 )); then lan_state_unlock; fi
        return 0
    fi
    official_mark_attempt || {
        OFFICIAL_RESULT_STATUS='failed'
        OFFICIAL_RESULT_MESSAGE='官方防火墙独立状态保存失败，未执行上报。'
        if (( official_lock_owned == 1 )); then official_run_lock_release; fi
        if (( lan_lock_owned == 1 )); then lan_state_unlock; fi
        printf '%s\n' "${OFFICIAL_RESULT_MESSAGE}" >&2
        return 1
    }
    official_run_items report || true
    if [[ "${OFFICIAL_FAILURE_COUNT}" != '0' ]]; then
        if [[ "${OFFICIAL_SUCCESS_COUNT}" != '0' ]]; then
            status='partial'
            OFFICIAL_RESULT_MESSAGE="官方防火墙上报部分完成：成功 ${OFFICIAL_SUCCESS_COUNT} 条，失败 ${OFFICIAL_FAILURE_COUNT} 条。"
            OFFICIAL_RESULT_NEEDS_NOTIFY='1'
        else
            status='failed'
            OFFICIAL_RESULT_MESSAGE="官方防火墙上报失败：${OFFICIAL_FAILURE_COUNT} 条请求未完成。"
        fi
        rc=1
    else
        status='success'
        OFFICIAL_RESULT_MESSAGE="官方防火墙上报完成：成功 ${OFFICIAL_SUCCESS_COUNT} 条。"
        [[ "${OFFICIAL_ADDED_COUNT}" == '0' ]] || OFFICIAL_RESULT_NEEDS_NOTIFY='1'
    fi
    OFFICIAL_RESULT_STATUS="${status}"
    if ! official_write_state "${status}" "${OFFICIAL_STATE_RECORDS}"; then
        OFFICIAL_RESULT_STATUS='failed'
        OFFICIAL_RESULT_MESSAGE='官方防火墙结果已处理，但独立状态保存失败。'
        rc=1
    fi
    if (( official_lock_owned == 1 )); then official_run_lock_release; fi
    if (( lan_lock_owned == 1 )); then lan_state_unlock; fi
    if [[ "${OFFICIAL_RESULT_NEEDS_NOTIFY}" == '1' || "${rc}" != '0' ]]; then
        printf '%s\n' "${OFFICIAL_RESULT_MESSAGE}" >&2
    fi
    return "${rc}"
}

# Called immediately before an existing SSH/control path.  It is intentionally
# quiet.  Callers deliberately ignore its return value so a failed optional
# lane cannot change the existing HTTP/SSH protocol or stop the old worker
# path; the non-zero result remains available to direct callers and the
# redacted state/dashboard.
official_preflight_before_ssh() {
    local old_scheduled="${SCHEDULED_RUN:-0}"
    local old_connect="${OFFICIAL_REQUEST_CONNECT_TIMEOUT}"
    local old_max="${OFFICIAL_REQUEST_MAX_TIME}"
    local old_retry="${OFFICIAL_REQUEST_RETRY}"
    # A preflight is a scheduled check even when the surrounding legacy
    # action was manual.  This keeps repeated SSH/control calls from creating
    # repeated official requests inside the 600-second window.
    SCHEDULED_RUN="1"
    OFFICIAL_REQUEST_CONNECT_TIMEOUT="${OFFICIAL_PREFLIGHT_CONNECT_TIMEOUT}"
    OFFICIAL_REQUEST_MAX_TIME="${OFFICIAL_PREFLIGHT_MAX_TIME}"
    OFFICIAL_REQUEST_RETRY="${OFFICIAL_PREFLIGHT_RETRY}"
    official_report_once >/dev/null 2>&1
    local rc=$?
    SCHEDULED_RUN="${old_scheduled}"
    OFFICIAL_REQUEST_CONNECT_TIMEOUT="${old_connect}"
    OFFICIAL_REQUEST_MAX_TIME="${old_max}"
    OFFICIAL_REQUEST_RETRY="${old_retry}"
    return "${rc}"
}

official_client_script_path() {
    local path=""
    if declare -F script_source_path >/dev/null 2>&1; then
        path="$(script_source_path 2>/dev/null || true)"
    fi
    if [[ -r "${path}" && "${path}" != */bash && "${path}" != */sh ]]; then
        printf '%s\n' "${path}"
    elif declare -F default_install_path >/dev/null 2>&1; then
        path="$(default_install_path 2>/dev/null || true)"
        [[ -r "${path}" ]] && printf '%s\n' "${path}"
    fi
}

official_prepare_python_preflight_env() {
    # These are non-sensitive paths only.  The child invokes this script with
    # --official-preflight-only and loads PO0_FIREWALL_TOKENS from settings;
    # the token is explicitly removed from the child's environment below.
    export PO0_LAN_CLIENT_PATH="$(official_client_script_path)"
    export PO0_LAN_CLIENT_CONFIG_FILE="${CONFIG_FILE}"
    export PO0_LAN_CLIENT_SETTINGS_FILE="${SETTINGS_FILE}"
}

official_state_summary() {
    local state last status checked success failure added
    local record payload ordinal item_status current whitelist used limit slot extra
    local safe_whitelist ip safe_ip_list invalid current_text slot_text entry whitelist_slot
    local -a item_lines=() ips=()
    state="$(official_state_file)"
    [[ -r "${state}" ]] || { printf '尚无官方防火墙本地状态'; return 0; }
    last="$(sed -n 's/^last_attempt_at=//p' "${state}" | head -n 1)"
    status="$(sed -n 's/^last_status=//p' "${state}" | head -n 1)"
    checked="$(sed -n 's/^last_checked_at=//p' "${state}" | head -n 1)"
    success="$(sed -n 's/^success_count=//p' "${state}" | head -n 1)"
    failure="$(sed -n 's/^failure_count=//p' "${state}" | head -n 1)"
    added="$(sed -n 's/^added_count=//p' "${state}" | head -n 1)"
    [[ "${last}" =~ ^[0-9]+$ ]] || last='未知'
    [[ "${checked}" =~ ^[0-9]+$ ]] || checked='未知'
    [[ "${success}" =~ ^[0-9]+$ ]] || success='0'
    [[ "${failure}" =~ ^[0-9]+$ ]] || failure='0'
    [[ "${added}" =~ ^[0-9]+$ ]] || added='0'
    while IFS= read -r record || [[ -n "${record}" ]]; do
        [[ "${record}" == item=* ]] || continue
        payload="${record#item=}"
        ordinal=''; item_status=''; current=''; whitelist=''; used=''; limit=''; slot=''; extra=''
        IFS='|' read -r ordinal item_status current whitelist used limit slot extra <<< "${payload}"
        [[ -z "${extra}" && "${ordinal}" =~ ^[1-9][0-9]*$ && "${ordinal}" -le 16 ]] || continue
        case "${item_status}" in hit|missing|added|error|running) ;; *) continue ;; esac
        current_text='无'
        if [[ -n "${current}" ]]; then
            official_json_safe_ip "${current}" || continue
            current_text="${current}"
        fi
        safe_whitelist=''
        if [[ -n "${whitelist}" ]]; then
            IFS=',' read -r -a ips <<< "${whitelist}"
            invalid=0
            safe_ip_list=''
            for entry in "${ips[@]}"; do
                # New records persist each server entry as IP@slot; an empty
                # suffix denotes the API's automatic slot.  Bare legacy IPs
                # are accepted as automatic-slot entries during migration.
                if [[ "${entry}" == *@* ]]; then
                    ip="${entry%@*}"
                    whitelist_slot="${entry##*@}"
                else
                    ip="${entry}"
                    whitelist_slot=""
                fi
                official_json_safe_ip "${ip}" || { invalid=1; break; }
                official_validate_slot "${whitelist_slot}" || { invalid=1; break; }
                safe_ip_list="${safe_ip_list}${safe_ip_list:+、}${ip}（${official_slot_display "${whitelist_slot}"}）"
            done
            (( invalid == 0 )) || continue
            safe_whitelist="${safe_ip_list}"
        fi
        [[ "${used}" =~ ^[0-9]+$ && "${limit}" =~ ^[1-5]$ && "${used}" -le "${limit}" ]] || continue
        official_validate_slot "${slot}" || continue
        slot_text="$(official_slot_display "${slot}")"
        item_lines+=("账号 ${ordinal}：状态=${item_status}；当前出口=${current_text}；白名单=${safe_whitelist:-无}；已用=${used}/${limit}；${slot_text}")
    done < "${state}"
    printf '状态=%s；最近尝试=%s；最近检查=%s；成功=%s；失败=%s；新增=%s' "${status:-未知}" "${last}" "${checked}" "${success}" "${failure}" "${added}"
    if (( ${#item_lines[@]} > 0 )); then
        local joined=''
        printf -v joined '%s；' "${item_lines[@]}"
        joined="${joined%;}"
        printf '；明细=%s' "${joined}"
    fi
}
