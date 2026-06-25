is_macos() {
    [[ "$(uname -s 2>/dev/null || printf '')" == "Darwin" ]]
}

launchd_label() {
    printf '%s\n' "fr.schweppes.po0-self-report"
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
    label="$(launchd_label)"
    if [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]]; then
        printf '/Library/LaunchDaemons/%s.plist\n' "${label}"
    else
        printf '%s/Library/LaunchAgents/%s.plist\n' "${HOME}" "${label}"
    fi
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
    local plist="$1" script="$2" interval_seconds="$3" log_path disabled
    log_path="$(self_report_log_path)"
    if schedule_paused; then
        disabled="true"
    else
        disabled="false"
    fi
    cat > "${plist}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$(xml_escape "$(launchd_label)")</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$(xml_escape "${script}")</string>
        <string>--config</string>
        <string>$(xml_escape "${CONFIG_FILE}")</string>
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
}

launchd_unload() {
    local plist="$1" domain
    domain="$(launchd_domain)"
    launchctl bootout "${domain}" "${plist}" >/dev/null 2>&1 || launchctl unload "${plist}" >/dev/null 2>&1 || true
}

launchd_load() {
    local plist="$1" domain label
    domain="$(launchd_domain)"
    label="$(launchd_label)"
    launchctl bootstrap "${domain}" "${plist}" >/dev/null 2>&1 || launchctl load "${plist}" >/dev/null 2>&1 || return 1
    launchctl enable "${domain}/${label}" >/dev/null 2>&1 || true
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

read_launchd_status_snapshot() {
    local plist interval_seconds interval="" config_paused disabled state consistency="ok"
    launchd_supported || return 1
    plist="$(launchd_plist_path)"
    config_paused="$(schedule_paused && printf '1' || printf '0')"
    [[ -f "${plist}" ]] || {
        printf 'uninstalled||%s||ok\n' "${config_paused}"
        return 0
    }
    interval_seconds="$(launchd_interval_seconds_from_plist "${plist}")"
    interval="$(interval_seconds_label "${interval_seconds}" 2>/dev/null || true)"
    disabled="$(launchd_disabled_from_plist "${plist}")"
    if [[ "${disabled}" == "1" || "${config_paused}" == "1" ]]; then
        state="paused"
    else
        state="running"
    fi
    if [[ "${state}" == "running" && "${config_paused}" == "1" ]]; then
        consistency="drift"
    elif [[ "${state}" == "paused" && "${config_paused}" != "1" && "${disabled}" == "1" ]]; then
        consistency="drift"
    fi
    printf '%s|%s|%s|launchd: %s|%s\n' "${state}" "${interval}" "${config_paused}" "${plist}" "${consistency}"
}
