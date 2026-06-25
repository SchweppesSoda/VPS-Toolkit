self_report_log_path() {
    printf '%s\n' "/tmp/po0-self-report.log"
}

log_file_mtime_label() {
    local path="$1" value
    value="$(stat -c '%y' "${path}" 2>/dev/null || true)"
    if [[ -n "${value}" ]]; then
        printf '%s\n' "${value%%.*}"
        return 0
    fi
    value="$(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "${path}" 2>/dev/null || true)"
    [[ -n "${value}" ]] || return 1
    printf '%s\n' "${value}"
}

normalize_self_report_log_line() {
    local line="$1"
    line="${line%$'\r'}"
    line="$(trim "${line}")"
    [[ -n "${line}" ]] || return 1
    if [[ "${line}" =~ ^\[[^]]+\][[:space:]]+\[[^]]+\][[:space:]]+(.*)$ ]]; then
        line="${BASH_REMATCH[1]}"
    elif [[ "${line}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[T[:space:]][0-9:.+Z-]+[[:space:]]+\[?[A-Za-z]+\]?[[:space:]:-]+(.*)$ ]]; then
        line="${BASH_REMATCH[1]}"
    elif [[ "${line}" =~ ^\[[A-Za-z]+\][[:space:]]+(.*)$ ]]; then
        line="${BASH_REMATCH[1]}"
    elif [[ "${line}" =~ ^(INFO|WARN|WARNING|ERROR|DEBUG)[[:space:]:-]+(.*)$ ]]; then
        line="${BASH_REMATCH[2]}"
    fi
    line="$(trim "${line}")"
    [[ -n "${line}" ]] || return 1
    printf '%s\n' "${line}"
}

self_report_log_event_summary() {
    local line="$1"
    line="$(normalize_self_report_log_line "${line}")" || return 1
    case "${line}" in
        "Self-report 已完成："*)
            printf '成功：%s\n' "${line#Self-report 已完成：}"
            ;;
        "Self-report 未完成："*)
            printf '失败：%s\n' "${line#Self-report 未完成：}"
            ;;
        *"未能探测到当前公网出口 IPv4"*)
            printf '探测失败：未能探测到当前公网出口 IPv4\n'
            ;;
        curl:\ *|*"curl exit "*)
            printf '网络错误：%s\n' "${line}"
            ;;
        *)
            return 1
            ;;
    esac
}

show_recent_self_report_log() {
    local log_path mtime line event max_events=5 i
    local events=()
    log_path="$(self_report_log_path)"
    print_panel_section "最近日志"
    print_panel_row "原始日志" "${log_path}"
    print_panel_row "查看原文" "tail -n 40 ${log_path}"
    if [[ ! -e "${log_path}" ]]; then
        print_panel_row "最近结果" "暂无日志"
        return 0
    fi
    if [[ ! -s "${log_path}" ]]; then
        print_panel_row "最近结果" "日志为空"
        return 0
    fi
    mtime="$(log_file_mtime_label "${log_path}" 2>/dev/null || true)"
    [[ -n "${mtime}" ]] && print_panel_row "最后更新" "${mtime}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        event="$(self_report_log_event_summary "${line}" 2>/dev/null || true)"
        [[ -n "${event}" ]] || continue
        events+=("${event}")
        if (( ${#events[@]} > max_events )); then
            events=("${events[@]:1}")
        fi
    done < <(tail -n 120 "${log_path}" 2>/dev/null || true)
    if (( ${#events[@]} == 0 )); then
        print_panel_row "最近结果" "未发现可摘要的 self-report 结果；请查看原始日志"
        return 0
    fi
    print_panel_row "最近结果" "${events[0]}"
    for ((i = 1; i < ${#events[@]}; i++)); do
        print_panel_note "${events[$i]}"
    done
}
