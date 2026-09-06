is_macos() {
    [[ "$(uname -s 2>/dev/null || printf '')" == "Darwin" ]]
}

launchd_label() {
    printf 'outbound-ip-report.%s\n' "${1:-worker}"
}

legacy_launchd_labels() {
    printf '%s\n' "outbound-ip-report"
    printf '%s\n' "fr.schweppes.po0-outbound-ip-report"
    printf '%s\n' "fr.schweppes.po0-self-report"
}

legacy_launchd_label() {
    legacy_launchd_labels | tail -n 1
}

launchd_supported() {
    is_macos || return 1
    command -v launchctl >/dev/null 2>&1 || return 1
    if [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]]; then
        return 0
    fi
    [[ -n "${HOME:-}" ]]
}

launchd_plist_path() {
    local label
    label="$(launchd_label "${1:-worker}")"
    if [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]]; then
        printf '/Library/LaunchDaemons/%s.plist\n' "${label}"
    else
        printf '%s/Library/LaunchAgents/%s.plist\n' "${HOME}" "${label}"
    fi
}

launchd_plist_path_for_label() {
    local label
    label="$1"
    if [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]]; then
        printf '/Library/LaunchDaemons/%s.plist\n' "${label}"
    else
        printf '%s/Library/LaunchAgents/%s.plist\n' "${HOME}" "${label}"
    fi
}

legacy_launchd_plist_paths() {
    local label
    legacy_launchd_labels | while IFS= read -r label; do
        launchd_plist_path_for_label "${label}"
    done
}

legacy_launchd_plist_path() {
    local path first=""
    while IFS= read -r path; do
        [[ -n "${first}" ]] || first="${path}"
        if [[ -f "${path}" ]]; then
            printf '%s\n' "${path}"
            return 0
        fi
    done < <(legacy_launchd_plist_paths)
    printf '%s\n' "${first}"
}

legacy_launchd_plist_exists() {
    local path
    while IFS= read -r path; do
        [[ -f "${path}" ]] && return 0
    done < <(legacy_launchd_plist_paths)
    return 1
}

launchd_domain() {
    if [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]]; then
        printf 'system\n'
    else
        printf 'gui/%s\n' "$(id -u)"
    fi
}

xml_escape() {
    local value="$1"
    value="${value//&/&amp;}"
    value="${value//</&lt;}"
    value="${value//>/&gt;}"
    value="${value//\"/&quot;}"
    printf '%s' "${value}"
}

write_launchd_plist() {
    local plist="$1" script="$2" interval_seconds="$3" channel="${4:-worker}" log_path disabled
    log_path="$(schedule_channel_log_path "$channel")"
    if schedule_channel_paused "$channel" || ! schedule_timer_enabled "$channel"; then
        disabled="true"
    else
        disabled="false"
    fi
    {
        cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$(xml_escape "$(launchd_label "$channel")")</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$(xml_escape "${script}")</string>
        <string>--config</string>
        <string>$(xml_escape "${CONFIG_FILE}")</string>
        <string>--scheduled-run</string>
        <string>--${channel}-only</string>
        <string>--timer-trigger</string>
EOF
        if notify_enabled; then
            printf '        <string>--notify</string>\n'
        fi
        cat <<EOF
    </array>
    <key>StartInterval</key>
    <integer>${interval_seconds}</integer>
    <key>Disabled</key>
    <${disabled}/>
    <key>StandardOutPath</key>
    <string>$(xml_escape "${log_path}")</string>
    <key>StandardErrorPath</key>
    <string>$(xml_escape "${log_path}")</string>
</dict>
</plist>
EOF
    } > "${plist}"
}

launchd_unload() {
    local plist="$1" domain
    domain="$(launchd_domain)"
    launchctl bootout "${domain}" "${plist}" >/dev/null 2>&1 || launchctl unload "${plist}" >/dev/null 2>&1 || true
}

remove_legacy_launchd_if_exists() {
    local plist domain label ok=0
    launchd_supported || return 0
    domain="$(launchd_domain)"
    while IFS= read -r label; do
        plist="$(launchd_plist_path_for_label "${label}")"
        launchctl bootout "${domain}" "${plist}" >/dev/null 2>&1 || launchctl unload "${plist}" >/dev/null 2>&1 || true
        launchctl disable "${domain}/${label}" >/dev/null 2>&1 || true
        if [[ -f "${plist}" ]]; then
            rm -f "${plist}" || ok=1
            echo "已删除旧 launchd 计划：${plist}"
        fi
    done < <(legacy_launchd_labels)
    return "${ok}"
}

launchd_load() {
    local plist="$1" channel="${2:-worker}" domain label
    domain="$(launchd_domain)"; label="$(launchd_label "$channel")"
    launchctl enable "$domain/$label" >/dev/null 2>&1 || true
    launchctl bootstrap "$domain" "$plist" >/dev/null 2>&1 || launchctl load "$plist" >/dev/null 2>&1
}

launchd_interval_seconds_from_plist() {
    local plist="$1"
    awk '/<key>StartInterval<\/key>/{getline; gsub(/.*<integer>|<\/integer>.*/, ""); print; exit}' "${plist}" 2>/dev/null
}

launchd_disabled_from_plist() {
    local plist="$1" disabled
    disabled="$(awk '/<key>Disabled<\/key>/{getline; if ($0 ~ /<true\/>/) print "1"; else print "0"; exit}' "${plist}" 2>/dev/null)"
    printf '%s\n' "${disabled:-0}"
}

launchd_plist_has_scheduled_run() {
    local plist="$1"
    grep -q '<string>--scheduled-run</string>' "${plist}" 2>/dev/null
}

launchd_plist_matches_desired() {
    local plist="$1" script="$2" channel="${3:-worker}" tmp rc=0
    [[ -f "$plist" ]] || return 1
    tmp="$(mktemp "${TMPDIR:-/tmp}/po0-launchd-desired.XXXXXX")" || return 1
    write_launchd_plist "$tmp" "$script" "$(($(schedule_channel_minutes "$channel") * 60))" "$channel" && cmp -s "$plist" "$tmp" || rc=1
    rm -f "$tmp"
    return "$rc"
}

read_launchd_status_snapshot() {
    local channel="${1:-worker}" plist paused=0 disabled state consistency=ok interval
    plist="$(launchd_plist_path "$channel")"
    schedule_channel_paused "$channel" && paused=1
    [[ -f "$plist" ]] || { printf 'uninstalled||%s||ok\n' "$paused"; return; }
    disabled="$(launchd_disabled_from_plist "$plist")"
    if [[ "$disabled" == 1 ]]; then state=paused; else state=running; fi
    if [[ "$disabled" != "$paused" ]] && schedule_timer_enabled "$channel"; then consistency=drift; fi
    interval="$(interval_seconds_label "$(launchd_interval_seconds_from_plist "$plist")")"
    printf '%s|%s|%s|launchd: %s|%s\n' "$state" "$interval" "$paused" "$plist" "$consistency"
}
