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
    [[ "$stamp" =~ ^[1-9][0-9]*$ ]] || { printf '尚无记录'; return; }
    date -d "@$stamp" '+%Y-%m-%d %H:%M:%S' 2>/dev/null ||
        date -r "$stamp" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf '尚无记录'
}

po0_display_ip_valid() {
    if declare -F official_json_safe_ip >/dev/null; then official_json_safe_ip "$1";
    else po0_firewall_json_safe_ip "$1"; fi
}

po0_display_slot_row() {
    local slot="$1" ip="$2" label="$3" color="${4:-}"
    if (( PO0_UI_WIDTH < 52 )); then
        printf '    %b%s  %s%b\n      %s\n' "$color" "$slot" "$label" "$C_RESET" "$ip"
    else
        printf '    %b%s%s%s%b\n' "$color" "$(po0_pad_cell "$slot" 8)" "$(po0_pad_cell "$ip" 23)" "$label" "$C_RESET"
    fi
}

po0_display_account() {
    local ordinal="$1" outcome="$2" current="$3" list="$4" used="$5" limit="$6" fixed="$7"
    local pair ip slot remaining unknown=0 occupied='' valid=1 n label color matched=0
    local configured badge badge_color
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
        if [[ -z "$slot" ]]; then unknown=$((unknown + 1)); else occupied="$occupied|$slot:$ip|"; fi
        if [[ "$ip" == "$current" && ( -z "$fixed" || "$fixed" == "$slot" ) ]]; then matched=1; fi
    done
    badge='未放行'; badge_color="$C_YELLOW"
    if [[ "$outcome" == error ]]; then badge='操作失败'; badge_color="$C_RED"
    elif (( matched == 1 )); then
        badge='已放行'; badge_color="$C_GREEN"
        [[ "$outcome" != added ]] || badge="$badge · 已更新"
    fi
    printf '\n'
    po0_heading "$(po0_display_safe_text "$(official_account_name "$ordinal")")" "$badge" "$badge_color"
    configured='自动分配'; [[ -z "$fixed" ]] || configured="固定 #$((10#$fixed + 1))"
    [[ -n "$PO0_UI_COMMON_IP" || -z "$current" ]] || print_panel_row '当前出口' "$current"
    if (( valid == 0 )); then print_panel_note "$configured · 本次未取得白名单，请稍后重试。"; return 0; fi
    print_panel_note "占用 $used/$limit  ·  剩余 $((limit - used)) 个  ·  $configured"
    if [[ -n "$fixed" ]] && (( 10#$fixed >= limit )); then printf '  %b指定槽位超出账号额度，请调整固定槽位。%b\n' "$C_RED" "$C_RESET"; fi
    [[ "$outcome" != error ]] || print_panel_note '以下为本次已取得的数据，操作未完成。'
    printf '\n'
    if (( PO0_UI_WIDTH >= 52 )); then po0_display_slot_row '槽位' 'IP / 网段' '状态' "$C_BOLD"; fi
    n=0
    while (( n < limit )); do
        ip='-' label='空闲' color="$C_DIM"
        if [[ "$occupied" == *"|$n:"* ]]; then
            ip="${occupied#*|$n:}"; ip="${ip%%|*}"; label='已记录'; color=''
            if [[ "$ip" == "$current" ]]; then
                label='出口匹配'
                if [[ "$outcome" != error && ( -z "$fixed" || "$fixed" == "$n" ) ]]; then label="$PO0_UI_HIT 当前出口"; color="$C_GREEN"; fi
            fi
        elif (( unknown > 0 )); then n=$((n+1)); continue; fi
        po0_display_slot_row "#$((n + 1))" "$ip" "$label" "$color"
        n=$((n + 1))
    done
    remaining="$list"
    while [[ -n "$remaining" ]]; do
        pair="${remaining%%,*}"
        if [[ "$remaining" == *,* ]]; then remaining="${remaining#*,}"; else remaining=''; fi
        [[ "$pair" == *@ ]] || continue
        ip="${pair%@*}"; label='已记录'; color=''
        if [[ "$ip" == "$current" ]]; then
            label='出口匹配'
            if [[ "$outcome" != error && -z "$fixed" ]]; then label="$PO0_UI_HIT 当前出口"; color="$C_GREEN"; fi
        fi
        po0_display_slot_row '未编号' "$ip" "$label" "$color"
    done
    (( unknown == 0 )) || PO0_UI_UNKNOWN=1
    return 0
}

po0_display_render() {
    local title="$1" records="$2" checked="$3" rc="${4:-0}"
    local ordinal outcome current list used limit fixed extra allowed=0 updated=0 failed=0 missing=0 total=0 summary color
    local PO0_UI_WIDTH PO0_UI_HIT='*' PO0_UI_UNKNOWN=0 PO0_UI_COMMON_IP='' first_ip=1
    # Local colors prevent rich output on fd 3 from contaminating subsequent log output.
    local C_RESET C_BOLD C_DIM C_GREEN C_YELLOW C_RED C_CYAN C_PANEL C_TITLE C_SECTION C_KEY
    setup_colors
    PO0_UI_WIDTH="$(po0_terminal_width)"
    if [[ -t 1 && "${TERM:-dumb}" != dumb ]]; then
        case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in *UTF-8*|*utf8*|*utf-8*) PO0_UI_HIT='●' ;; esac
    fi
    while IFS='|' read -r ordinal outcome current list used limit fixed extra; do
        [[ -n "$ordinal" ]] || continue
        total=$((total+1))
        case "$outcome" in hit) allowed=$((allowed+1)) ;; added) allowed=$((allowed+1)); updated=$((updated+1)) ;;
            missing) missing=$((missing+1)) ;; *) failed=$((failed+1)) ;; esac
        if (( first_ip )); then PO0_UI_COMMON_IP="$current"; first_ip=0
        elif [[ "$PO0_UI_COMMON_IP" != "$current" ]]; then PO0_UI_COMMON_IP=''; fi
    done <<< "$records"
    print_title "PO0 防火墙 / $title"
    summary="$allowed/$total 个账号已放行"; color="$C_GREEN"
    if (( updated )); then summary="$summary  ·  已更新 $updated 个"
    elif (( allowed > 0 && failed == 0 && missing == 0 )); then summary="$summary  ·  无需更新"; fi
    if (( missing )); then summary="$summary  ·  $missing 个未放行"; color="$C_YELLOW"; fi
    if (( failed )); then summary="$summary  ·  $failed 个失败"; color="$C_YELLOW"; fi
    printf '  %b%s%b\n' "$color" "$summary" "$C_RESET"
    [[ -z "$PO0_UI_COMMON_IP" ]] || print_panel_row '当前出口' "$PO0_UI_COMMON_IP"
    if [[ "$rc" != 0 && "$failed" == 0 ]]; then print_panel_note '操作尚未完整完成，请查看错误提示。'; fi
    [[ -n "$records" ]] || print_panel_note '尚无可展示的账号结果。'
    while IFS='|' read -r ordinal outcome current list used limit fixed extra; do
        [[ -n "$ordinal" && -z "$extra" ]] || continue
        po0_display_account "$ordinal" "$outcome" "$current" "$list" "$used" "$limit" "$fixed"
    done <<< "$records"
    printf '\n'
    (( PO0_UI_UNKNOWN == 0 )) || print_panel_note '说明：部分记录未返回槽位编号，已列出全部 IP。'
    print_panel_row '检查时间' "$(po0_display_time "$checked")"
    printf '\n'
}

po0_display_cached() {
    local mode="${1:-full}" state config_id cached_id records checked
    state="$(po0_display_state_path)"
    cached_id=''; [[ ! -r "$state" ]] || cached_id="$(sed -n 's/^display_config_id=//p' "$state" | head -n 1)"
    if [[ -z "$cached_id" ]]; then print_panel_status_row '最近检查' '暂无新版记录，检查后显示' warn; return 0; fi
    config_id="$(po0_display_config_id)"
    if [[ -z "$config_id" || "$config_id" != "$cached_id" ]]; then
        print_panel_status_row '最近检查' '账号配置已更新，等待下次检查' warn; return 0
    fi
    checked="$(sed -n 's/^last_checked_at=//p' "$state" | head -n 1)"
    records="$(sed -n 's/^item=//p' "$state")"
    if [[ "$mode" == summary ]]; then
        local total=0 allowed=0 record status tone
        while IFS= read -r record; do
            [[ -n "$record" ]] || continue
            total=$((total + 1)); status="${record#*|}"; status="${status%%|*}"
            case "$status" in hit|added) allowed=$((allowed + 1)) ;; esac
        done <<< "$records"
        tone=warn; (( total == 0 || allowed != total )) || tone=ok
        print_panel_status_row '最近检查' "$(po0_display_time "$checked") · $allowed/$total 已放行" "$tone"
    else
        po0_display_render '上次结果 / 本地记录' "$records" "$checked"
    fi
}

po0_display_is_live() {
    [[ "${SCHEDULED_RUN:-0}" != 1 ]] && { [[ "${PO0_DISPLAY_FD:-}" == 3 && -t 3 ]] || [[ -t 1 ]]; }
}

# Redundant progress belongs in the menu log, not above the result table.
po0_display_detail() {
    if [[ "${PO0_UI_LIVE:-0}" == 1 ]]; then
        if [[ "${PO0_DISPLAY_LOG_FD:-}" == 4 ]]; then printf "$@" >&4; fi
    else printf "$@"; fi
    return 0
}

po0_display_live() {
    po0_display_is_live || return 0
    if [[ "${PO0_DISPLAY_FD:-}" == 3 && -t 3 ]]; then po0_display_render "$@" >&3
    else po0_display_render "$@"; fi
    PO0_UI_RENDERED=1
    return 0
}
