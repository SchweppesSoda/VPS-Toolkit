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
    line="${line#$'\xef\xbb\xbf'}"
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

self_report_response_summary_parts() {
    local line="$1"
    line="${line%$'\r'}"
    line="${line#$'\xef\xbb\xbf'}"
    line="$(trim "${line}")"
    if [[ "${line}" =~ ^OK[[:space:]]+([0-9.]+)\;[[:space:]]*targets=([0-9]+)($|[[:space:]]) ]]; then
        printf '%s|%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
        return 0
    fi
    return 1
}

self_report_target_success_text() {
    local count="$1"
    [[ "${count}" =~ ^[0-9]+$ ]] || return 1
    (( count > 0 )) || return 1
    printf 'LAN Worker 已成功转发 %s 个 PO0 目标\n' "${count}"
}

self_report_append_target_success() {
    local message="$1"
    local count="$2"
    local target_text
    target_text="$(self_report_target_success_text "${count}" 2>/dev/null || true)"
    if [[ -z "${target_text}" || "${message}" == *"成功转发 "*" 个 PO0 目标"* ]]; then
        printf '%s\n' "${message}"
        return 0
    fi
    message="${message%$'\r'}"
    message="${message%。}"
    message="${message%.}"
    printf '%s；%s。\n' "${message}" "${target_text}"
}

self_report_append_response_target_success() {
    local message="$1"
    local response="$2"
    local line parts count
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parts="$(self_report_response_summary_parts "${line}" 2>/dev/null || true)"
        [[ -n "${parts}" ]] || continue
        count="${parts##*|}"
        self_report_append_target_success "${message}" "${count}"
        return 0
    done <<< "${response}"
    printf '%s\n' "${message}"
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
    local log_path mtime line normalized event max_events=5 i
    local pending_response_parts="" pending_target_count="" pending_target_ip=""
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
        normalized="$(normalize_self_report_log_line "${line}" 2>/dev/null || true)"
        [[ -n "${normalized}" ]] || continue
        pending_response_parts="$(self_report_response_summary_parts "${normalized}" 2>/dev/null || true)"
        if [[ -n "${pending_response_parts}" ]]; then
            pending_target_ip="${pending_response_parts%%|*}"
            pending_target_count="${pending_response_parts##*|}"
            continue
        fi
        event="$(self_report_log_event_summary "${normalized}" 2>/dev/null || true)"
        [[ -n "${event}" ]] || continue
        if [[ -n "${pending_target_count}" && "${event}" == "成功："* ]]; then
            event="成功：$(self_report_append_target_success "${event#成功：}" "${pending_target_count}")"
            pending_target_count=""
            pending_target_ip=""
        elif [[ -n "${pending_target_count}" ]]; then
            events+=("成功：LAN Worker 已成功转发 ${pending_target_count} 个 PO0 目标（公网出口 IPv4 ${pending_target_ip}）")
            pending_target_count=""
            pending_target_ip=""
        fi
        events+=("${event}")
        while (( ${#events[@]} > max_events )); do
            events=("${events[@]:1}")
        done
    done < <(tail -n 120 "${log_path}" 2>/dev/null || true)
    if [[ -n "${pending_target_count}" ]]; then
        events+=("成功：LAN Worker 已成功转发 ${pending_target_count} 个 PO0 目标（公网出口 IPv4 ${pending_target_ip}）")
        while (( ${#events[@]} > max_events )); do
            events=("${events[@]:1}")
        done
    fi
    if (( ${#events[@]} == 0 )); then
        print_panel_row "最近结果" "未发现可摘要的 self-report 结果；请查看原始日志"
        return 0
    fi
    print_panel_row "最近结果" "${events[0]}"
    for ((i = 1; i < ${#events[@]}; i++)); do
        print_panel_note "${events[$i]}"
    done
}
