# Official PO0 firewall reporting for the macOS self-report client.
#
# PO0_FIREWALL_TOKENS is intentionally the only setting exposed here. Each
# comma-separated item is pgnfw_<token>, optionally followed by @0..@4.
# Tokens are supplied to curl through its config stdin, never as argv.
#
# Behavior reference: https://github.com/kelenetwork/po0fw (MIT).
# This is a native VPS-Toolkit integration; it does not copy that project's
# implementation or assume a Chicksure-specific deployment.

PO0_FIREWALL_API_BASE_URL="https://124.221.69.228/api/firewall"
PO0_FIREWALL_HTTP_BODY=""
PO0_FIREWALL_HTTP_CODE=""
PO0_FIREWALL_SUCCESS_COUNT="0"
PO0_FIREWALL_FAILURE_COUNT="0"
PO0_FIREWALL_ITEM_TOKEN=""
PO0_FIREWALL_ITEM_SLOT=""
PO0_FIREWALL_ITEM_STATUS=""
PO0_FIREWALL_ITEM_CURRENT_IP=""
PO0_FIREWALL_ITEM_USED=""
PO0_FIREWALL_ITEM_LIMIT=""
PO0_FIREWALL_ITEM_WHITELIST=""
PO0_FIREWALL_STATE_RECORDS=""
PO0_FIREWALL_ADDED_COUNT="0"
PO0_REPORT_LOCK_DIR=""
PO0_REPORT_LOCK_HELD="0"
PO0_REPORT_LOCK_STALE_SECONDS="86400"

po0_firewall_normalize_tokens() {
    local raw="${1:-}"
    raw="${raw//，/,}"
    raw="${raw//；/,}"
    printf '%s' "${raw}" | tr ',;[:space:]' '\n' | awk 'NF { printf "%s%s", sep, $0; sep="," } END { printf "\n" }'
}

po0_firewall_parse_item() {
    local raw="${1:-}" token remainder slot=""
    raw="$(trim "${raw}")"
    [[ -n "${raw}" ]] || return 1
    case "${raw}" in
        *@[0-4])
            slot="${raw##*@}"
            token="${raw%@*}"
            ;;
        *@*)
            return 1
            ;;
        *)
            token="${raw}"
            ;;
    esac
    case "${token}" in
        pgnfw_*) remainder="${token#pgnfw_}" ;;
        *) return 1 ;;
    esac
    case "${remainder}" in
        ""|*[!A-Za-z0-9._~-]*) return 1 ;;
    esac
    [[ ${#remainder} -le 240 ]] || return 1
    PO0_FIREWALL_ITEM_TOKEN="${token}"
    PO0_FIREWALL_ITEM_SLOT="${slot}"
    return 0
}

po0_firewall_validate_tokens() {
    local raw rest item count=0 key seen=";"
    raw="$(po0_firewall_normalize_tokens "${PO0_FIREWALL_TOKENS:-}")"
    [[ -n "${raw}" ]] || return 0
    [[ "${raw}" != ,* && "${raw}" != *, && "${raw}" != *,,* ]] || {
        printf 'PO0 官方防火墙 token 列表包含空项。\n' >&2
        return 1
    }
    rest="${raw},"
    while [[ "${rest}" == *,* ]]; do
        item="${rest%%,*}"
        rest="${rest#*,}"
        item="$(trim "${item}")"
        [[ -n "${item}" ]] || {
            printf 'PO0 官方防火墙 token 列表包含空项。\n' >&2
            return 1
        }
        po0_firewall_parse_item "${item}" || {
            printf 'PO0 官方防火墙 token 配置无效：请使用 pgnfw_...，槽位可写为 @0 到 @4。\n' >&2
            return 1
        }
        key="${PO0_FIREWALL_ITEM_TOKEN}"
        [[ "${seen}" != *";${key};"* ]] || {
            printf 'PO0 官方防火墙 token 列表包含重复项。\n' >&2
            return 1
        }
        seen="${seen}${key};"
        count=$((count + 1))
        (( count <= 16 )) || {
            printf 'PO0 官方防火墙 token 数量超过上限（最多 16 个）。\n' >&2
            return 1
        }
    done
    return 0
}

po0_firewall_configured() {
    [[ -n "$(po0_firewall_normalize_tokens "${PO0_FIREWALL_TOKENS:-}")" ]] || return 1
    po0_firewall_validate_tokens
}

po0_firewall_token_count() {
    local raw count=0 item
    raw="$(po0_firewall_normalize_tokens "${PO0_FIREWALL_TOKENS:-}")"
    [[ -n "${raw}" ]] || { printf '0\n'; return 0; }
    raw="${raw},"
    while [[ -n "${raw}" ]]; do
        item="${raw%%,*}"
        raw="${raw#*,}"
        [[ -n "${item}" ]] || continue
        count=$((count + 1))
    done
    printf '%s\n' "${count}"
}

po0_firewall_masked_tokens() {
    local count
    count="$(po0_firewall_token_count)"
    if [[ "${count}" == "0" ]]; then
        printf '未启用（默认关闭）'
    else
        printf '已设置（%s 个，内容不显示）' "${count}"
    fi
}

po0_firewall_read_secret_prompt() {
    local prompt="$1" value="" line="" separator=""
    while true; do
        if [[ -r /dev/tty && -w /dev/tty ]] && { : < /dev/tty; } 2>/dev/null; then
            printf '%s' "${prompt}" > /dev/tty || return 1
            IFS= read -r line < /dev/tty || break
        else
            printf '%s' "${prompt}" >&2
            IFS= read -r line || break
        fi
        [[ -n "$(trim "${line}")" ]] || break
        value="${value}${separator}${line}"
        [[ "${value}" == "-" ]] && break
        separator=$'\n'
        prompt='继续输入（空行结束）: '
    done
    printf '%s\n' "${value}"
}

po0_firewall_read_tokens_interactive() {
    local input normalized previous_tokens="${PO0_FIREWALL_TOKENS:-}"
    print_panel_row "当前官方 Token" "${PO0_FIREWALL_TOKENS:-未设置}"
    printf '可用逗号、分号、空格或换行分隔。空行结束；直接空行保留，单独 - 清空。\n'
    input="$(po0_firewall_read_secret_prompt "输入官方 Token（可写 @0..4，空行结束）: ")" || return 1
    input="$(trim "${input}")"
    [[ -n "${input}" ]] || return 0
    if [[ "${input}" == "-" ]]; then
        PO0_FIREWALL_TOKENS=""
        return 0
    fi
    PO0_FIREWALL_TOKENS="$(trim "${input}")"
    po0_firewall_validate_tokens || {
        PO0_FIREWALL_TOKENS="${previous_tokens}"
        return 1
    }
    PO0_FIREWALL_TOKENS="$(po0_firewall_normalize_tokens "${PO0_FIREWALL_TOKENS}")"
}

po0_firewall_state_dir() {
    if [[ -n "${XDG_STATE_HOME:-}" ]]; then
        printf '%s/po0-outbound-ip-report\n' "${XDG_STATE_HOME}"
    elif [[ -n "${HOME:-}" ]]; then
        printf '%s/.local/state/po0-outbound-ip-report\n' "${HOME}"
    else
        printf '/tmp/po0-outbound-ip-report\n'
    fi
}

po0_firewall_state_file() {
    printf '%s/official.state\n' "$(po0_firewall_state_dir)"
}

po0_firewall_due_state_file() {
    printf '%s/official-last-due\n' "$(po0_firewall_state_dir)"
}

po0_firewall_last_attempt_at() {
    local state
    state="$(po0_firewall_state_file)"
    [[ -r "$state" ]] || return 1
    sed -n 's/^last_attempt_at=\([0-9][0-9]*\)$/\1/p' "$state" | head -n 1
}

po0_worker_due_state_file() {
    printf '%s/worker-last-attempt\n' "$(po0_firewall_state_dir)"
}

po0_firewall_now() {
    local value="${PO0_TEST_NOW:-}"
    if [[ "${value}" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$((10#${value}))"
    else
        date +%s
    fi
}

po0_firewall_read_timestamp() {
    local path="${1:-}" value=""
    [[ -r "${path}" ]] || { printf '0\n'; return 0; }
    value="$(sed -n '1p' "${path}" 2>/dev/null || true)"
    [[ "${value}" =~ ^[0-9]+$ ]] || value="0"
    printf '%s\n' "$((10#${value}))"
}

po0_firewall_write_timestamp() {
    local path="$1" dir tmp old_umask
    dir="$(path_dirname "${path}")"
    po0_firewall_secure_state_dir "${dir}" || return 1
    [[ ! -L "${path}" ]] || return 1
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
    if ! printf '%s\n' "$(po0_firewall_now)" > "${tmp}"; then
        rm -f -- "${tmp}" 2>/dev/null || true
        umask "${old_umask}"
        return 1
    fi
    if ! mv -f "${tmp}" "${path}"; then
        rm -f -- "${tmp}" 2>/dev/null || true
        umask "${old_umask}"
        return 1
    fi
    umask "${old_umask}"
    chmod 600 "${path}" 2>/dev/null || true
}

po0_firewall_secure_state_dir() {
    local dir="$1" mode owner current_uid
    case "$dir" in
        ""|/|.|/tmp|/var/tmp) return 1 ;;
    esac
    [[ "$dir" != *$'\n'* && "$dir" != *$'\r'* ]] || return 1
    [[ ! -L "$dir" ]] || return 1
    mkdir -p "$dir" 2>/dev/null || return 1
    [[ -d "$dir" && ! -L "$dir" ]] || return 1
    owner="$(stat -f '%u' "$dir" 2>/dev/null || true)"
    [[ "$owner" =~ ^[0-9]+$ ]] || owner="$(stat -c '%u' "$dir" 2>/dev/null || true)"
    current_uid="$(id -u 2>/dev/null || true)"
    [[ "$owner" =~ ^[0-9]+$ && "$current_uid" =~ ^[0-9]+$ && "$owner" == "$current_uid" ]] || return 1
    chmod 700 "$dir" 2>/dev/null || return 1
    mode="$(stat -f '%Lp' "$dir" 2>/dev/null || true)"
    [[ "$mode" =~ ^[0-9]+$ ]] || mode="$(stat -c '%a' "$dir" 2>/dev/null || true)"
    [[ "$mode" == "700" || "$mode" == "0700" ]]
}

po0_firewall_state_write() {
    local status="unknown" records="" update_attempt="0" mark_success="0"
    local state dir tmp old_umask now last_attempt last_success
    local success failure added
    [[ "$#" -ge 1 ]] && status="$1"
    [[ "$#" -ge 2 ]] && records="$2"
    [[ "$#" -ge 3 ]] && update_attempt="$3"
    [[ "$#" -ge 4 ]] && mark_success="$4"
    success="$PO0_FIREWALL_SUCCESS_COUNT"
    failure="$PO0_FIREWALL_FAILURE_COUNT"
    added="$PO0_FIREWALL_ADDED_COUNT"
    state="$(po0_firewall_state_file)"
    dir="$(path_dirname "$state")"
    po0_firewall_secure_state_dir "$dir" || return 1
    [[ ! -L "$state" ]] || return 1
    last_attempt="$(po0_firewall_last_attempt_at 2>/dev/null || true)"
    [[ "$last_attempt" =~ ^[0-9]+$ ]] || last_attempt="0"
    last_success="$(sed -n 's/^last_success_at=\([0-9][0-9]*\)$/\1/p' "$state" 2>/dev/null | head -n 1 || true)"
    [[ "$last_success" =~ ^[0-9]+$ ]] || last_success="0"
    now="$(po0_firewall_now)"
    [[ "$update_attempt" == "1" ]] && last_attempt="$now"
    [[ "$mark_success" == "1" ]] && last_success="$now"
    old_umask="$(umask)"
    umask 077
    if ! tmp="$(mktemp "$dir/.po0-official-state.XXXXXX" 2>/dev/null)"; then
        umask "$old_umask"
        return 1
    fi
    if [[ ! -f "$tmp" || -L "$tmp" ]] || ! chmod 600 "$tmp" 2>/dev/null; then
        rm -f -- "$tmp" 2>/dev/null || true
        umask "$old_umask"
        return 1
    fi
    if ! {
        printf 'last_attempt_at=%s\n' "$last_attempt"
        printf 'last_success_at=%s\n' "$last_success"
        printf 'last_checked_at=%s\n' "$now"
        printf 'last_status=%s\n' "$status"
        printf 'success_count=%s\n' "$success"
        printf 'failure_count=%s\n' "$failure"
        printf 'added_count=%s\n' "$added"
        while IFS= read -r record || [[ -n "$record" ]]; do
            [[ -n "$record" ]] && printf 'item=%s\n' "$record"
        done <<< "$records"
        true
    } > "$tmp"; then
        rm -f -- "$tmp" 2>/dev/null || true
        umask "$old_umask"
        return 1
    fi
    if ! mv -f "$tmp" "$state"; then
        rm -f -- "$tmp" 2>/dev/null || true
        umask "$old_umask"
        return 1
    fi
    umask "$old_umask"
    chmod 600 "$state" 2>/dev/null || true
    return 0
}

po0_firewall_state_summary() {
    local state last success checked status line payload ordinal item_status current whitelist used limit slot extra
    local list pair ip pair_slot details="" current_text friendly_whitelist pair_label slot_label
    state="$(po0_firewall_state_file)"
    [[ -r "$state" ]] || {
        printf '尚无官方防火墙本地状态'
        return 0
    }
    last="$(sed -n 's/^last_attempt_at=//p' "$state" | head -n 1)"
    checked="$(sed -n 's/^last_checked_at=//p' "$state" | head -n 1)"
    status="$(sed -n 's/^last_status=//p' "$state" | head -n 1)"
    success="$(sed -n 's/^success_count=//p' "$state" | head -n 1)"
    [[ "$last" =~ ^[0-9]+$ ]] || last="未知"
    [[ "$checked" =~ ^[0-9]+$ ]] || checked="未知"
    [[ "$success" =~ ^[0-9]+$ ]] || success="0"
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            item=*)
                payload="${line#item=}"
                IFS='|' read -r ordinal item_status current whitelist used limit slot extra <<< "$payload"
                [[ -z "$extra" && "$ordinal" =~ ^[1-9][0-9]*$ && "$ordinal" -le 16 ]] || continue
                case "$item_status" in hit|missing|added|error) ;; *) continue ;; esac
                [[ -z "$current" ]] || po0_firewall_json_safe_ip "$current" || continue
                [[ "$used" =~ ^[0-9]+$ && "$limit" =~ ^[1-5]$ && "$used" -le "$limit" ]] || continue
                [[ -z "$slot" || "$slot" =~ ^[0-4]$ ]] || continue
                list="$whitelist"
                friendly_whitelist=""
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
                    po0_firewall_json_safe_ip "$ip" || break
                    [[ -z "$pair_slot" || "$pair_slot" =~ ^[0-4]$ ]] || break
                    pair_label="自动"
                    [[ -n "$pair_slot" ]] && pair_label="$((10#$pair_slot + 1))"
                    [[ -n "$friendly_whitelist" ]] && friendly_whitelist="$friendly_whitelist，"
                    friendly_whitelist="$friendly_whitelist$ip（槽位 $pair_label）"
                done
                [[ -z "$list" ]] || continue
                slot_label="自动"
                [[ -n "$slot" ]] && slot_label="$((10#$slot + 1))"
                current_text="${current:-无}"
                if [[ -n "$details" ]]; then
                    details="$details；"
                fi
                details="$details$(if declare -F official_account_name >/dev/null; then official_account_name "$ordinal"; else printf "账号 %s" "$ordinal"; fi)：状态=$item_status；当前出口=$current_text；白名单=${friendly_whitelist:-无}；已用=$used/$limit；固定槽位=$slot_label"
                ;;
        esac
    done < "$state"
    printf '状态=%s；最近尝试=%s；最近检查=%s；成功=%s' "${status:-未知}" "$last" "$checked" "$success"
    [[ -n "$details" ]] && printf '；明细=%s' "$details"
}

po0_firewall_report_lock_path() {
    local base
    base="$(po0_firewall_state_dir)"
    printf '%s/.po0-outbound-ip-report.lock\n' "$base"
}

po0_firewall_report_lock_mtime() {
    local path="$1" value
    value="$(stat -f '%m' "$path" 2>/dev/null || true)"
    [[ "$value" =~ ^[0-9]+$ ]] || value="$(stat -c '%Y' "$path" 2>/dev/null || true)"
    [[ "$value" =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "$value"
}

po0_firewall_report_lock_write() {
    local lock="$1" now="$2" old_umask
    old_umask="$(umask)"
    umask 077
    if ! printf 'pid=%s\nstarted_at=%s\n' "$$" "$now" > "$lock/pid"; then
        umask "$old_umask"
        return 1
    fi
    if ! chmod 600 "$lock/pid" 2>/dev/null; then
        umask "$old_umask"
        return 1
    fi
    umask "$old_umask"
    return 0
}

po0_firewall_report_lock_release() {
    local lock="${PO0_REPORT_LOCK_DIR:-}" pid
    [[ "${PO0_REPORT_LOCK_HELD:-0}" == "1" && -n "$lock" ]] || return 0
    pid="$(sed -n 's/^pid=\([0-9][0-9]*\)$/\1/p' "$lock/pid" 2>/dev/null | head -n 1 || true)"
    if [[ "$pid" == "$$" ]]; then
        rm -f -- "$lock/pid" 2>/dev/null || true
        rmdir "$lock" 2>/dev/null || true
    fi
    PO0_REPORT_LOCK_DIR=""
    PO0_REPORT_LOCK_HELD="0"
    return 0
}

po0_firewall_report_lock_acquire() {
    local lock base now pid mtime age owner current_uid
    base="$(po0_firewall_state_dir)"
    po0_firewall_secure_state_dir "$base" || return 1
    lock="$(po0_firewall_report_lock_path)"
    if mkdir "$lock" 2>/dev/null; then
        if ! po0_firewall_report_lock_write "$lock" "$(po0_firewall_now)"; then
            rm -f -- "$lock/pid" 2>/dev/null || true
            rmdir "$lock" 2>/dev/null || true
            return 1
        fi
        PO0_REPORT_LOCK_DIR="$lock"
        PO0_REPORT_LOCK_HELD="1"
        return 0
    fi
    [[ -d "$lock" && ! -L "$lock" ]] || return 2
    owner="$(stat -f '%u' "$lock" 2>/dev/null || true)"
    [[ "$owner" =~ ^[0-9]+$ ]] || owner="$(stat -c '%u' "$lock" 2>/dev/null || true)"
    current_uid="$(id -u 2>/dev/null || true)"
    [[ "$owner" =~ ^[0-9]+$ && "$current_uid" =~ ^[0-9]+$ && "$owner" == "$current_uid" ]] || return 2
    pid="$(sed -n 's/^pid=\([0-9][0-9]*\)$/\1/p' "$lock/pid" 2>/dev/null | head -n 1 || true)"
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
        return 2
    fi
    now="$(po0_firewall_now)"
    mtime="$(po0_firewall_report_lock_mtime "$lock" 2>/dev/null || true)"
    age=""
    if [[ "$mtime" =~ ^[0-9]+$ && "$now" =~ ^[0-9]+$ && "$now" -ge "$mtime" ]]; then
        age="$((now - mtime))"
    fi
    if [[ "$pid" =~ ^[0-9]+$ || ( -n "$age" && "$age" -ge "$PO0_REPORT_LOCK_STALE_SECONDS" ) ]]; then
        rm -f -- "$lock/pid" 2>/dev/null || true
        rmdir "$lock" 2>/dev/null || true
        if mkdir "$lock" 2>/dev/null; then
            if ! po0_firewall_report_lock_write "$lock" "$now"; then
                rm -f -- "$lock/pid" 2>/dev/null || true
                rmdir "$lock" 2>/dev/null || true
                return 1
            fi
            PO0_REPORT_LOCK_DIR="$lock"
            PO0_REPORT_LOCK_HELD="1"
            return 0
        fi
    fi
    return 2
}

po0_firewall_due() {
    local now last state_file
    po0_firewall_configured || return 1
    [[ "${SCHEDULED_RUN:-0}" == "1" ]] || return 0
    [[ "${FORCE_REPORT:-0}" == "1" || "${NETWORK_CHANGED:-0}" == 1 || "${TIMER_TRIGGER:-0}" == 1 ]] && return 0
    now="$(po0_firewall_now)"
    state_file="$(po0_firewall_due_state_file)"
    [[ -r "${state_file}" ]] || return 0
    last="$(po0_firewall_read_timestamp "${state_file}")"
    (( now < last || now - last >= ${OFFICIAL_INTERVAL_SECONDS:-600} ))
}

po0_firewall_mark_due() {
    po0_firewall_write_timestamp "$(po0_firewall_due_state_file)"
}

po0_worker_due() {
    local now last interval state_file
    [[ -n "${WORKER_URL:-}" ]] || return 1
    [[ "${SCHEDULED_RUN:-0}" == "1" ]] || return 0
    [[ "${FORCE_REPORT:-0}" == "1" || "${NETWORK_CHANGED:-0}" == 1 || "${TIMER_TRIGGER:-0}" == 1 ]] && return 0
    interval="$(cron_minutes_to_seconds "${CRON_MINUTES:-60}")"
    now="$(po0_firewall_now)"
    state_file="$(po0_worker_due_state_file)"
    [[ -r "${state_file}" ]] || return 0
    last="$(po0_firewall_read_timestamp "${state_file}")"
    (( now < last || now - last >= interval ))
}

po0_worker_mark_attempt() {
    po0_firewall_write_timestamp "$(po0_worker_due_state_file)"
}

po0_worker_mark_success() {
    po0_worker_mark_attempt
}

po0_reporter_validate_config() {
    local has_worker="0" has_official="0"
    [[ -n "${WORKER_URL:-}" ]] && has_worker="1"
    po0_firewall_configured && has_official="1"
    [[ "${has_worker}" == "1" || "${has_official}" == "1" ]] || {
        printf '至少配置 LAN Worker URL 或 PO0 官方防火墙 token。\n' >&2
        return 1
    }
    if [[ "${has_worker}" == "1" ]]; then
        validate_worker_url || return 1
    fi
    if [[ -n "${PO0_FIREWALL_TOKENS:-}" ]]; then
        po0_firewall_validate_tokens || return 1
    fi
    validate_cron_minutes
}

po0_firewall_direct_request() (
    local token="$1" operation="$2" slot="${3:-}" url method escaped_url response code
    local request_dir body_file header_file curl_rc body_size header_size
    po0_firewall_parse_item "${token}${slot:+@${slot}}" || return 1
    token="${PO0_FIREWALL_ITEM_TOKEN}"
    case "${operation}" in
        status)
            [[ -z "${slot}" ]] || return 1
            method="GET"
            url="${PO0_FIREWALL_API_BASE_URL}/${token}"
            ;;
        add)
            method="POST"
            url="${PO0_FIREWALL_API_BASE_URL}/${token}/add"
            [[ -n "${slot}" ]] && url="${url}?slot=${slot}"
            ;;
        *)
            return 1
            ;;
    esac
    umask 077
    request_dir="$(mktemp -d "${TMPDIR:-/tmp}/po0-official-request.XXXXXX" 2>/dev/null)" || return 1
    trap 'rm -rf -- "${request_dir}"' EXIT
    trap 'rm -rf -- "${request_dir}"; exit 129' HUP
    trap 'rm -rf -- "${request_dir}"; exit 130' INT
    trap 'rm -rf -- "${request_dir}"; exit 143' TERM
    [[ -d "${request_dir}" && ! -L "${request_dir}" ]] || return 1
    chmod 700 "${request_dir}" 2>/dev/null || return 1
    body_file="${request_dir}/body"
    header_file="${request_dir}/headers"
    : > "${body_file}" || return 1
    : > "${header_file}" || return 1
    [[ -f "${body_file}" && ! -L "${body_file}" && -f "${header_file}" && ! -L "${header_file}" ]] || return 1
    chmod 600 "${body_file}" "${header_file}" 2>/dev/null || return 1
    escaped_url="${url//\\/\\\\}"
    escaped_url="${escaped_url//\"/\\\"}"
    if response="$({
        printf 'url = "%s"\n' "${escaped_url}"
        printf 'request = "%s"\n' "${method}"
    } | env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
        curl -4sS --noproxy '*' --proto '=https' --tlsv1.2 --connect-timeout 5 --max-time 20 \
        --retry 2 --retry-delay 2 --max-filesize 65536 --output "${body_file}" \
        --dump-header "${header_file}" --write-out '%{http_code}' --config - 2>/dev/null)"; then
        curl_rc=0
    else
        curl_rc=$?
    fi
    [[ -f "${body_file}" && ! -L "${body_file}" && -f "${header_file}" && ! -L "${header_file}" ]] || return 1
    chmod 600 "${body_file}" "${header_file}" 2>/dev/null || return 1
    body_size="$(wc -c < "${body_file}" 2>/dev/null || true)"
    header_size="$(wc -c < "${header_file}" 2>/dev/null || true)"
    [[ "${body_size}" =~ ^[0-9]+$ && "${body_size}" -le 65536 ]] || return 1
    [[ "${header_size}" =~ ^[0-9]+$ && "${header_size}" -le 16384 ]] || return 1
    [[ "${curl_rc}" == "0" && "${response}" =~ ^2[0-9][0-9]$ ]] || return 1
    code="${response}"
    response="$(cat "${body_file}")" || return 1
    PO0_FIREWALL_HTTP_CODE="${code}"
    PO0_FIREWALL_HTTP_BODY="${response}"
    printf '%s\n' "${response}"
)

#
# Do not parse this response with grep/sed.  The endpoint is outside the
# client's trust boundary and a substring parser can be fooled by nested
# objects, duplicate keys, field reordering, or bytes after the root object.
# This small recursive-descent parser is deliberately written for POSIX awk,
# which is present on stock macOS.  It rejects duplicate keys, unknown schema
# keys, malformed JSON, trailing data, and every slot type except null, the
# empty string, or a JSON integer 0..4.  It also refuses \u escapes: the
# protocol has no Unicode fields and rejecting them prevents escaped key names
# from bypassing duplicate/field checks on older awk implementations.
po0_firewall_json_parse() {
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

po0_firewall_json_compact() {
    # Kept as a compatibility helper for callers outside this fragment.  The
    # strict parser intentionally receives the original whitespace intact.
    printf '%s\n' "${1:-}"
}

po0_firewall_json_current_ip() {
    local parsed
    parsed="$(po0_firewall_json_parse "${1:-}")" || return 1
    printf '%s\n' "${parsed}" | sed -n 's/^current_ip=//p' | head -n 1
}

po0_firewall_json_limit() {
    local parsed
    parsed="$(po0_firewall_json_parse "${1:-}")" || return 1
    printf '%s\n' "${parsed}" | sed -n 's/^limit=//p' | head -n 1
}

po0_firewall_json_has_whitelist() {
    po0_firewall_json_parse "${1:-}" >/dev/null
}

po0_firewall_json_enabled() {
    local parsed
    parsed="$(po0_firewall_json_parse "${1:-}")" || return 1
    printf '%s\n' "${parsed}" | grep -Fqx 'enabled=true'
}

po0_firewall_json_validate_whitelist() {
    local parsed="${1:-}" limit="${2:-}" record payload ip slot count=0
    [[ "${limit}" =~ ^[1-5]$ ]] || return 1
    parsed="$(po0_firewall_json_parse "${parsed}")" || return 1
    while IFS= read -r record || [[ -n "${record}" ]]; do
        case "${record}" in
            entry=*)
                payload="${record#entry=}"
                ip="${payload%%|*}"
                slot="${payload#*|}"
                [[ "${payload}" == *"|"* && -n "${ip}" ]] || return 1
                po0_firewall_json_safe_ip "${ip}" || return 1
                [[ -z "${slot}" || "${slot}" =~ ^[0-4]$ ]] || return 1
                count=$((count + 1))
                ;;
        esac
    done <<< "${parsed}"
    [[ "${count}" =~ ^[0-9]+$ && "${count}" -le "${limit}" && "${count}" -le 5 ]]
}

po0_firewall_json_ip_entry() {
    local parsed record payload ip target_ip="${2:-}"
    parsed="$(po0_firewall_json_parse "${1:-}")" || return 1
    while IFS= read -r record || [[ -n "${record}" ]]; do
        case "${record}" in
            entry=*)
                payload="${record#entry=}"
                ip="${payload%%|*}"
                [[ "${ip}" == "${target_ip}" ]] && return 0
                ;;
        esac
    done <<< "${parsed}"
    return 1
}

po0_firewall_json_ip_slot_entry() {
    local parsed record payload ip slot target_ip="${2:-}" target_slot="${3:-}"
    parsed="$(po0_firewall_json_parse "${1:-}")" || return 1
    while IFS= read -r record || [[ -n "${record}" ]]; do
        case "${record}" in
            entry=*)
                payload="${record#entry=}"
                ip="${payload%%|*}"
                slot="${payload#*|}"
                [[ "${ip}" == "${target_ip}" && "${slot}" == "${target_slot}" ]] && return 0
                ;;
        esac
    done <<< "${parsed}"
    return 1
}

po0_firewall_json_safe_ip() {
    local value="${1:-}" a b c d extra octet
    case "${value}" in
        */24) value="${value%/24}" ;;
        *) return 1 ;;
    esac
    [[ "${value}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
    IFS='.' read -r a b c d extra <<< "${value}"
    [[ -z "${extra:-}" ]] || return 1
    for octet in "${a}" "${b}" "${c}" "${d}"; do
        octet="$(printf '%s\n' "${octet}" | sed 's/^0*//')"
        [[ -n "${octet}" ]] || octet="0"
        [[ "${octet}" =~ ^[0-9]{1,3}$ ]] || return 1
        case "${#octet}" in
            1|2) ;;
            3) [[ "${octet}" -le 255 ]] || return 1 ;;
            *) return 1 ;;
        esac
    done
}

po0_firewall_json_whitelist_count() {
    local parsed record payload ip count=0
    parsed="$(po0_firewall_json_parse "${1:-}")" || return 1
    while IFS= read -r record || [[ -n "${record}" ]]; do
        case "${record}" in
            entry=*)
                payload="${record#entry=}"
                ip="${payload%%|*}"
                po0_firewall_json_safe_ip "${ip}" || return 1
                count=$((count + 1))
                ;;
        esac
    done <<< "${parsed}"
    printf '%s\n' "${count}"
}

po0_firewall_json_whitelist_state() {
    local json="$1" parsed record payload ip slot out=""
    parsed="$(po0_firewall_json_parse "$json")" || return 1
    while IFS= read -r record || [[ -n "$record" ]]; do
        case "$record" in
            entry=*)
                payload="${record#entry=}"
                ip="${payload%%|*}"
                slot="${payload#*|}"
                po0_firewall_json_safe_ip "$ip" || return 1
                if [[ -n "$out" ]]; then
                    out="$out,$ip@$slot"
                else
                    out="$ip@$slot"
                fi
                ;;
        esac
    done <<< "$parsed"
    printf '%s\n' "$out"
}

po0_firewall_process_item() {
    local ordinal="$1" item="$2" mode="$3"
    local token slot marker status_json current_ip limit response response_ip response_limit slot_label
    PO0_FIREWALL_ITEM_STATUS="error"
    PO0_FIREWALL_ITEM_CURRENT_IP=""
    PO0_FIREWALL_ITEM_USED=""
    PO0_FIREWALL_ITEM_LIMIT=""
    PO0_FIREWALL_ITEM_WHITELIST=""
    po0_firewall_parse_item "${item}" || {
        printf '官方账号 %s 配置无效，已跳过。\n' "${ordinal}" >&2
        return 1
    }
    token="${PO0_FIREWALL_ITEM_TOKEN}"
    slot="${PO0_FIREWALL_ITEM_SLOT}"
    PO0_FIREWALL_ITEM_SLOT="${slot}"
    marker="官方账号 ${ordinal}"
    if declare -F official_account_name >/dev/null; then marker="$(official_account_name "$ordinal")"; fi
    slot_label=""
    if [[ -n "${slot}" ]]; then
        slot_label="$((10#${slot} + 1))"
        marker="${marker}（槽位 ${slot_label}）"
    fi
    status_json="$(po0_firewall_direct_request "${token}" status "")" || {
        printf '%s 只读检查失败，未执行加白。\n' "${marker}" >&2
        return 1
    }
    po0_firewall_json_enabled "${status_json}" || {
        printf '%s 官方状态未启用。\n' "${marker}" >&2
        return 1
    }
    current_ip="$(po0_firewall_json_current_ip "${status_json}")"
    po0_firewall_json_safe_ip "${current_ip}" || {
        printf '%s 未返回有效当前出口 IPv4。\n' "${marker}" >&2
        return 1
    }
    limit="$(po0_firewall_json_limit "${status_json}")"
    [[ "${limit}" =~ ^[1-5]$ ]] || {
        printf '%s 返回的名额无效。\n' "${marker}" >&2
        return 1
    }
    po0_firewall_json_validate_whitelist "${status_json}" "${limit}" || {
        printf '%s 白名单状态无效。\n' "${marker}" >&2
        return 1
    }
    PO0_FIREWALL_ITEM_CURRENT_IP="${current_ip}"
    PO0_FIREWALL_ITEM_LIMIT="${limit}"
    PO0_FIREWALL_ITEM_USED="$(po0_firewall_json_whitelist_count "${status_json}")" || return 1
    PO0_FIREWALL_ITEM_WHITELIST="$(po0_firewall_json_whitelist_state "${status_json}")" || return 1
    if po0_firewall_json_ip_entry "${status_json}" "${current_ip}" &&
        { [[ -z "${slot}" ]] || po0_firewall_json_ip_slot_entry "${status_json}" "${current_ip}" "${slot}"; }; then
        PO0_FIREWALL_ITEM_STATUS="hit"
        printf '%s 已在白名单：%s（名额 %s，已用 %s）。\n' "${marker}" "${current_ip}" "${limit}" "$(po0_firewall_json_whitelist_count "${status_json}")"
        return 0
    fi
    if [[ "${mode}" == "status" ]]; then
        PO0_FIREWALL_ITEM_STATUS="missing"
        printf '%s 当前未命中白名单：%s（名额 %s，仅读不加白）。\n' "${marker}" "${current_ip}" "${limit}"
        return 0
    fi
    response="$(po0_firewall_direct_request "${token}" add "${slot}")" || {
        printf '%s 加白请求失败。\n' "${marker}" >&2
        return 1
    }
    po0_firewall_json_enabled "${response}" || {
        printf '%s 加白响应未启用。\n' "${marker}" >&2
        return 1
    }
    response_ip="$(po0_firewall_json_current_ip "${response}")"
    po0_firewall_json_safe_ip "${response_ip}" || {
        printf '%s 加白响应未返回有效当前出口 IPv4。\n' "${marker}" >&2
        return 1
    }
    response_limit="$(po0_firewall_json_limit "${response}")"
    [[ "${response_limit}" =~ ^[1-5]$ ]] || {
        printf '%s 加白响应名额无效。\n' "${marker}" >&2
        return 1
    }
    po0_firewall_json_validate_whitelist "${response}" "${response_limit}" || {
        printf '%s 加白响应白名单无效。\n' "${marker}" >&2
        return 1
    }
    po0_firewall_json_ip_entry "${response}" "${response_ip}" || {
        printf '%s 加白后未确认当前出口。\n' "${marker}" >&2
        return 1
    }
    if [[ -n "${slot}" ]] && ! po0_firewall_json_ip_slot_entry "${response}" "${response_ip}" "${slot}"; then
        printf '%s 加白后槽位校验失败。\n' "${marker}" >&2
        return 1
    fi
    PO0_FIREWALL_ITEM_STATUS="added"
    PO0_FIREWALL_ITEM_CURRENT_IP="${response_ip}"
    PO0_FIREWALL_ITEM_LIMIT="${response_limit}"
    PO0_FIREWALL_ITEM_USED="$(po0_firewall_json_whitelist_count "${response}")" || return 1
    PO0_FIREWALL_ITEM_WHITELIST="$(po0_firewall_json_whitelist_state "${response}")" || return 1
    PO0_FIREWALL_ADDED_COUNT=$((PO0_FIREWALL_ADDED_COUNT + 1))
    printf '%s 已更新：%s（名额 %s，已用 %s）。\n' "${marker}" "${response_ip}" "${response_limit}" "$(po0_firewall_json_whitelist_count "${response}")"
    return 0
}
po0_firewall_state_append_item() {
    local ordinal="$1" record
    record="$ordinal|$PO0_FIREWALL_ITEM_STATUS|$PO0_FIREWALL_ITEM_CURRENT_IP|$PO0_FIREWALL_ITEM_WHITELIST|$PO0_FIREWALL_ITEM_USED|$PO0_FIREWALL_ITEM_LIMIT|$PO0_FIREWALL_ITEM_SLOT"
    if [[ -n "$PO0_FIREWALL_STATE_RECORDS" ]]; then
        PO0_FIREWALL_STATE_RECORDS="$PO0_FIREWALL_STATE_RECORDS
$record"
    else
        PO0_FIREWALL_STATE_RECORDS="$record"
    fi
}

po0_firewall_run() {
    local mode="${1:-report}" raw item ordinal=0
    PO0_FIREWALL_SUCCESS_COUNT="0"
    PO0_FIREWALL_FAILURE_COUNT="0"
    PO0_FIREWALL_ADDED_COUNT="0"
    PO0_FIREWALL_STATE_RECORDS=""
    [[ "${mode}" == "status" || "${mode}" == "report" ]] || return 1
    po0_firewall_configured || {
        printf 'PO0 官方防火墙未启用（默认关闭）。\n' >&2
        return 1
    }
    command -v curl >/dev/null 2>&1 || {
        printf '缺少 curl，无法检查 PO0 官方防火墙。\n' >&2
        return 1
    }
    raw="$(po0_firewall_normalize_tokens "${PO0_FIREWALL_TOKENS}")"
    raw="${raw},"
    while [[ -n "${raw}" ]]; do
        item="${raw%%,*}"
        raw="${raw#*,}"
        [[ -n "${item}" ]] || continue
        ordinal=$((ordinal + 1))
        if po0_firewall_process_item "${ordinal}" "${item}" "${mode}"; then
            PO0_FIREWALL_SUCCESS_COUNT=$((PO0_FIREWALL_SUCCESS_COUNT + 1))
        else
            PO0_FIREWALL_FAILURE_COUNT=$((PO0_FIREWALL_FAILURE_COUNT + 1))
        fi
        po0_firewall_state_append_item "${ordinal}"
    done
    printf '官方防火墙通道：成功 %s，失败 %s。\n' "${PO0_FIREWALL_SUCCESS_COUNT}" "${PO0_FIREWALL_FAILURE_COUNT}"
    local update_attempt="1" mark_success="0" state_rc=0
    [[ "${mode}" == "status" ]] && update_attempt="0"
    [[ "${mode}" != "status" && "${PO0_FIREWALL_FAILURE_COUNT}" == "0" ]] && mark_success="1"
    po0_firewall_state_write "${mode}" "${PO0_FIREWALL_STATE_RECORDS}" "${update_attempt}" "${mark_success}" || state_rc=1
    [[ "${PO0_FIREWALL_FAILURE_COUNT}" == "0" && "${state_rc}" == "0" ]]
}
