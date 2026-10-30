# Shared terminal presentation; embedded in both single-file clients by manifest.
# No requests, scheduler writes, or credentials belong in this layer.
po0_display_config_id() {
    local normalized
    if declare -F official_normalize_tokens >/dev/null; then
        normalized="$(official_normalize_tokens "${PO0_FIREWALL_TOKENS:-}")"
    else
        normalized="$(po0_firewall_normalize_tokens "${PO0_FIREWALL_TOKENS:-}")"
    fi
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$normalized" | sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        printf '%s' "$normalized" | shasum -a 256 | awk '{print $1}'
    fi
}

po0_display_state_path() {
    if declare -F official_state_file >/dev/null; then official_state_file; else po0_firewall_state_file; fi
}

po0_display_safe_text() {
    printf '%s' "$*" | tr '\r\n\t' '   ' | tr -d '\000-\037\177'
}

po0_display_time() {
    local stamp="${1:-}"
    [[ "$stamp" =~ ^[1-9][0-9]*$ ]] || { printf '未知'; return; }
    date -d "@$stamp" '+%Y-%m-%d %H:%M:%S' 2>/dev/null ||
        date -r "$stamp" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf '未知'
}

po0_display_ip_valid() {
    if declare -F official_json_safe_ip >/dev/null; then official_json_safe_ip "$1";
    else po0_firewall_json_safe_ip "$1"; fi
}

po0_display_style() {
    PO0_UI_RESET='' PO0_UI_GREEN='' PO0_UI_RED='' PO0_UI_YELLOW='' PO0_UI_CYAN=''
    PO0_UI_HIT='[OK]' PO0_UI_EMPTY='-'
    if [[ -t 1 && "${TERM:-dumb}" != dumb ]]; then
        if [[ -z "${NO_COLOR+x}" ]]; then
            PO0_UI_RESET=$'\033[0m' PO0_UI_GREEN=$'\033[32m' PO0_UI_RED=$'\033[31m'
            PO0_UI_YELLOW=$'\033[33m' PO0_UI_CYAN=$'\033[36m'
        fi
        case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in *UTF-8*|*utf8*|*utf-8*) PO0_UI_HIT='✓'; PO0_UI_EMPTY='—' ;; esac
    fi
    PO0_UI_WIDTH="${COLUMNS:-}"
    if [[ ! "$PO0_UI_WIDTH" =~ ^[1-9][0-9]*$ ]]; then
        PO0_UI_WIDTH="$(tput cols 2>/dev/null || true)"
    fi
    [[ "$PO0_UI_WIDTH" =~ ^[1-9][0-9]*$ ]] || PO0_UI_WIDTH=80
}

po0_display_slot_row() {
    local slot="$1" ip="$2" label="$3" color="${4:-}"
    if (( PO0_UI_WIDTH < 60 )); then
        printf '  %b%s  %s%b\n    %s\n' "$color" "$slot" "$label" "$PO0_UI_RESET" "$ip"
    else
        printf '  %b%-8s %-21s %s%b\n' "$color" "$slot" "$ip" "$label" "$PO0_UI_RESET"
    fi
}

po0_display_account() {
    local ordinal="$1" outcome="$2" current="$3" list="$4" used="$5" limit="$6" fixed="$7"
    local pair ip slot remaining unknown=0 hit='' occupied='' valid=1 n label color matched=0
    local nameslot badge badge_color
    [[ "$ordinal" =~ ^[1-9][0-9]*$ ]] || return 0
    case "$outcome" in hit|added|missing|error) ;; *) outcome=error ;; esac
    [[ "$limit" =~ ^([1-9]|10)$ && "$used" =~ ^[0-9]+$ ]] && (( used <= limit )) || valid=0
    [[ -z "$current" ]] || po0_display_ip_valid "$current" || current=''
    [[ -z "$fixed" || "$fixed" =~ ^[0-9]$ ]] || fixed=''
    remaining="$list"
    while [[ -n "$remaining" ]]; do
        pair="${remaining%%,*}"
        if [[ "$remaining" == *,* ]]; then remaining="${remaining#*,}"; else remaining=''; fi
        [[ "$pair" == *@* ]] || { valid=0; continue; }
        ip="${pair%@*}" slot="${pair##*@}"
        po0_display_ip_valid "$ip" || { valid=0; continue; }
        [[ -z "$slot" || "$slot" =~ ^[0-9]$ ]] || { valid=0; continue; }
        if [[ -z "$slot" ]]; then unknown=$((unknown + 1));
        else occupied="$occupied|$slot:$ip|"; fi
        if [[ "$ip" == "$current" ]]; then
            nameslot='槽位未知'; [[ -z "$slot" ]] || nameslot="#$((10#$slot + 1))"
            [[ -z "$hit" ]] || hit="$hit、"
            hit="$hit$nameslot"
            [[ -z "$fixed" || "$fixed" == "$slot" ]] && matched=1
        fi
    done
    badge='未放行'; badge_color="$PO0_UI_YELLOW"
    if [[ "$outcome" == error ]]; then badge='操作失败'; badge_color="$PO0_UI_RED"
    elif (( matched == 1 )); then
        badge="$PO0_UI_HIT 已放行"; badge_color="$PO0_UI_GREEN"
        [[ "$outcome" != added ]] || badge="$badge · 本次更新"
    fi
    printf '\n%b-- %s --%b\n' "$PO0_UI_CYAN" "$(po0_display_safe_text "$(official_account_name "$ordinal")")" "$PO0_UI_RESET"
    printf '%b%s%b\n' "$badge_color" "$badge" "$PO0_UI_RESET"
    printf '当前出口 %s\n' "${current:-未知}"
    nameslot='自动分配'; [[ -z "$fixed" ]] || nameslot="固定槽位 #$((10#$fixed + 1))"
    printf '%s · 实际命中 %s\n' "$nameslot" "${hit:-无}"
    if (( valid == 0 )); then printf '占用未知 · 尚无完整槽位数据\n'; return 0; fi
    printf '占用 %s/%s · 剩余 %s 个\n' "$used" "$limit" "$((limit - used))"
    if [[ -n "$fixed" ]] && (( 10#$fixed >= limit )); then printf '指定槽位超出账号额度，请调整固定槽位。\n'; fi
    [[ "$outcome" != error ]] || printf '以下为本次已取得的数据；操作未完成。\n'
    printf '\n  槽位     IP / 网段             状态\n'
    n=0
    while (( n < limit )); do
        ip="$PO0_UI_EMPTY" label='空闲' color=''
        if [[ "$occupied" == *"|$n:"* ]]; then
            ip="${occupied#*|$n:}"; ip="${ip%%|*}"; label='已占用'
            if [[ "$ip" == "$current" ]]; then
                label='当前出口匹配'
                if [[ "$outcome" != error && ( -z "$fixed" || "$fixed" == "$n" ) ]]; then
                    label="$PO0_UI_HIT 当前命中"; color="$PO0_UI_GREEN"
                fi
            fi
        elif (( unknown > 0 )); then label='未知（有未编号记录）'; fi
        po0_display_slot_row "#$((n + 1))" "$ip" "$label" "$color"
        n=$((n + 1))
    done
    remaining="$list"
    while [[ -n "$remaining" ]]; do
        pair="${remaining%%,*}"
        if [[ "$remaining" == *,* ]]; then remaining="${remaining#*,}"; else remaining=''; fi
        [[ "$pair" == *@ ]] || continue
        ip="${pair%@*}"; label='已占用'; color=''
        if [[ "$ip" == "$current" && "$outcome" != error && -z "$fixed" ]]; then
            label="$PO0_UI_HIT 当前命中"; color="$PO0_UI_GREEN"
        fi
        po0_display_slot_row '槽位未知' "$ip" "$label" "$color"
    done
}

po0_display_render() {
    local title="$1" records="$2" checked="$3" rc="${4:-0}"
    local ordinal outcome current list used limit fixed extra allowed=0 updated=0 failed=0 missing=0
    po0_display_style
    printf '\n%bPO0 防火墙 · %s%b\n' "$PO0_UI_CYAN" "$title" "$PO0_UI_RESET"
    while IFS='|' read -r ordinal outcome current list used limit fixed extra; do
        [[ -n "$ordinal" ]] || continue
        case "$outcome" in hit) allowed=$((allowed + 1)) ;; added) allowed=$((allowed + 1)); updated=$((updated + 1)) ;;
            missing) missing=$((missing + 1)) ;; *) failed=$((failed + 1)) ;; esac
    done <<< "$records"
    printf '%s 个账号已放行 · 更新 %s 个 · 未放行 %s 个 · 失败 %s 个\n' "$allowed" "$updated" "$missing" "$failed"
    [[ "$rc" == 0 ]] || printf '%b本次操作未完整完成，请查看错误提示。%b\n' "$PO0_UI_RED" "$PO0_UI_RESET"
    [[ -n "$records" ]] || printf '尚无可展示的账号结果。\n'
    while IFS='|' read -r ordinal outcome current list used limit fixed extra; do
        [[ -n "$ordinal" && -z "$extra" ]] || continue
        po0_display_account "$ordinal" "$outcome" "$current" "$list" "$used" "$limit" "$fixed"
    done <<< "$records"
    printf '\n检查时间 %s\n' "$(po0_display_time "$checked")"
}

po0_display_cached() {
    local mode="${1:-full}" state config_id cached_id records checked
    state="$(po0_display_state_path)"
    [[ -r "$state" ]] || { printf '上次检查：尚无本地结果。\n'; return 0; }
    config_id="$(po0_display_config_id)"
    cached_id="$(sed -n 's/^display_config_id=//p' "$state" | head -n 1)"
    if [[ -z "$config_id" || "$config_id" != "$cached_id" ]]; then
        printf '上次检查：缓存未匹配当前账号配置，请重新查询。\n'; return 0
    fi
    checked="$(sed -n 's/^last_checked_at=//p' "$state" | head -n 1)"
    records="$(sed -n 's/^item=//p' "$state")"
    if [[ "$mode" == summary ]]; then
        local total=0 allowed=0 record status
        while IFS= read -r record; do
            [[ -n "$record" ]] || continue
            total=$((total + 1)); status="${record#*|}"; status="${status%%|*}"
            case "$status" in hit|added) allowed=$((allowed + 1)) ;; esac
        done <<< "$records"
        printf '上次检查：%s · 已放行 %s/%s · 详情见“最近结果”\n' "$(po0_display_time "$checked")" "$allowed" "$total"
    else
        po0_display_render '上次结果（本地缓存）' "$records" "$checked"
    fi
}

po0_display_live() {
    [[ "${SCHEDULED_RUN:-0}" != 1 ]] || return 0
    if [[ "${PO0_DISPLAY_FD:-}" == 3 ]] && [[ -t 3 ]]; then
        po0_display_render "$@" >&3
    elif [[ -t 1 ]]; then
        po0_display_render "$@"
    fi
    return 0
}
