schedule_channel_label() {
    case "$1" in worker) printf '自建 PO0' ;; official) printf '官方防火墙' ;; *) return 1 ;; esac
}

schedule_channel_configured() {
    case "$1" in worker) [[ -n "${WORKER_URL:-}" && -n "${SECRET:-}" ]] ;; official) [[ -n "${PO0_FIREWALL_TOKENS:-}" ]] ;; *) return 1 ;; esac
}

schedule_channel_validate() {
    local seconds="${OFFICIAL_INTERVAL_SECONDS:-600}"
    if [[ "$1" == official ]] && { [[ ! "$seconds" =~ ^[0-9]+$ ]] || (( seconds < 60 || seconds > 86400 || seconds % 60 != 0 )); }; then printf '官方周期须为 60..86400 秒且为 60 的倍数。\n' >&2; return 1; fi
    schedule_channel_configured "$1" || { printf '%s尚未配置。\n' "$(schedule_channel_label "$1")" >&2; return 1; }
    if [[ "$1" == worker ]]; then
        validate_cron_minutes && validate_worker_url
    elif declare -F official_validate_tokens >/dev/null; then
        official_validate_tokens
    else
        po0_firewall_validate_tokens
    fi
}

schedule_channel_minutes() {
    case "$1" in worker) printf '%s' "$CRON_MINUTES" ;; official) printf '%s' "$((${OFFICIAL_INTERVAL_SECONDS:-600} / 60))" ;; *) return 1 ;; esac
}

schedule_channel_paused() {
    schedule_paused || ! channel_auto_enabled "$1"
}

schedule_channel_log_path() {
    local path
    path="$(self_report_log_path)"
    case "$path" in *."$1".log) printf '%s' "$path" ;; *) printf '%s.%s.log' "${path%.log}" "$1" ;; esac
}

cron_begin_marker() { printf '# OUTBOUND_IP_REPORT_%s_BEGIN %s\n' "$(printf '%s' "${1:-worker}" | tr '[:lower:]' '[:upper:]')" "$CONFIG_FILE"; }
cron_end_marker() { printf '# OUTBOUND_IP_REPORT_%s_END %s\n' "$(printf '%s' "${1:-worker}" | tr '[:lower:]' '[:upper:]')" "$CONFIG_FILE"; }

cron_channel_block() {
    local begin end
    begin="$(cron_begin_marker "$1")"; end="$(cron_end_marker "$1")"
    crontab -l 2>/dev/null | awk -v begin="$begin" -v end="$end" '$0 == begin {inside=1} inside {print} $0 == end {inside=0}'
}

legacy_cron_block_exists() {
    crontab -l 2>/dev/null | awk -v cfg="$CONFIG_FILE" '
        $0 == "# OUTBOUND_IP_REPORT_BEGIN " cfg || $0 == "# PO0_OUTBOUND_IP_REPORT_BEGIN " cfg || $0 == "# PO0_SELF_REPORT_BEGIN " cfg {found=1}
        END {exit !found}'
}

cron_managed_block_exists() {
    local channel="${1:-all}"
    if [[ "$channel" == all ]]; then
        legacy_cron_block_exists || cron_managed_block_exists worker || cron_managed_block_exists official
    else
        [[ -n "$(cron_channel_block "$channel")" ]]
    fi
}

# Remove only this config's selected blocks. Other channels and user jobs survive.
write_cron_without_managed_block() {
    local worker="${1:-1}" official="${2:-1}" legacy="${3:-1}"
    awk -v cfg="$CONFIG_FILE" -v worker="$worker" -v official="$official" -v legacy="$legacy" '
        (worker && $0 == "# OUTBOUND_IP_REPORT_WORKER_BEGIN " cfg) ||
        (official && $0 == "# OUTBOUND_IP_REPORT_OFFICIAL_BEGIN " cfg) ||
        (legacy && ($0 == "# OUTBOUND_IP_REPORT_BEGIN " cfg || $0 == "# PO0_OUTBOUND_IP_REPORT_BEGIN " cfg || $0 == "# PO0_SELF_REPORT_BEGIN " cfg)) {skip=1; next}
        skip && $0 ~ /^# (OUTBOUND_IP_REPORT(_WORKER|_OFFICIAL)?|PO0_OUTBOUND_IP_REPORT|PO0_SELF_REPORT)_END / {skip=0; next}
        !skip {print}'
}

channel_expected_cron_job() {
    local script="$1" channel="$2" run_cmd
    run_cmd="bash $(sh_quote "$script") --config $(sh_quote "$CONFIG_FILE") --scheduled-run --${channel}-only --timer-trigger"
    if declare -F notify_enabled >/dev/null && notify_enabled; then run_cmd="$run_cmd --notify"; fi
    run_cmd="$run_cmd >$(sh_quote "$(schedule_channel_log_path "$channel")") 2>&1"
    build_cron_job "$(schedule_channel_minutes "$channel")" "$run_cmd"
}

write_channel_cron_block() {
    local script="$1" channel="$2" job paused=0
    { schedule_channel_paused "$channel" || ! schedule_timer_enabled "$channel"; } && paused=1
    job="$(channel_expected_cron_job "$script" "$channel")" || return 1
    cron_begin_marker "$channel"
    printf '# channel=%s\n# paused=%s\n# interval_minutes=%s\n' "$channel" "$paused" "$(schedule_channel_minutes "$channel")"
    if [[ "$paused" == 1 ]]; then printf '# %s\n' "$job"; else printf '%s\n' "$job"; fi
    cron_end_marker "$channel"
}

# Stage both channels together when migrating a shared cron; commit once.
apply_channel_cron() {
    local action="$1" target="${2:-all}" script="${3:-}" channel selected legacy=0 tmp old
    local worker_change=0 official_change=0 worker_write=0 official_write=0 change put any=0
    case "$target" in all|worker|official) ;; *) return 1 ;; esac
    command -v crontab >/dev/null 2>&1 || return 1
    legacy_cron_block_exists && legacy=1
    if [[ "$legacy" == 1 && "$action" == refresh ]] && legacy_schedule_paused; then SCHEDULE_PAUSED=1; save_config_file || return 1; fi
    for channel in worker official; do
        change=0; put=0; selected=0
        [[ "$target" == all || "$target" == "$channel" ]] && selected=1
        if [[ "$selected" == 1 ]]; then
            case "$action" in
                install) change=1; if schedule_channel_configured "$channel"; then put=1; elif [[ "$target" != all ]]; then schedule_channel_validate "$channel"; return 1; fi ;;
                refresh) if cron_managed_block_exists "$channel" || [[ "$legacy" == 1 ]]; then change=1; schedule_channel_configured "$channel" && put=1; fi ;;
                remove) change=1 ;;
                *) return 1 ;;
            esac
        elif [[ "$legacy" == 1 ]] && ! cron_managed_block_exists "$channel"; then
            change=1; schedule_channel_configured "$channel" && put=1
        fi
        if [[ "$put" == 1 ]]; then schedule_channel_validate "$channel" || return 1; any=1; fi
        if [[ "$channel" == worker ]]; then worker_change="$change"; worker_write="$put"; else official_change="$change"; official_write="$put"; fi
    done
    if [[ "$action" == install && "$any" == 0 ]]; then printf '没有已配置的上报通道。\n' >&2; return 1; fi
    if [[ "$any" == 1 && -z "$script" ]]; then script="$(install_self)" || return 1; fi
    tmp="$(mktemp "${TMPDIR:-/tmp}/po0-outbound-ip-report-cron.XXXXXX")" || return 1
    old="$(crontab -l 2>/dev/null || true)"
    {
        printf '%s\n' "$old" | write_cron_without_managed_block "$worker_change" "$official_change" 1
        if [[ "$worker_write" == 1 ]]; then write_channel_cron_block "$script" worker; fi
        if [[ "$official_write" == 1 ]]; then write_channel_cron_block "$script" official; fi
    } > "$tmp" || { rm -f "$tmp"; return 1; }
    crontab "$tmp" || { rm -f "$tmp"; return 1; }
    rm -f "$tmp"
    local lane
    for lane in worker official; do
        if [[ "$target" == all || "$target" == "$lane" || "$legacy" == 1 ]]; then
            if cron_managed_block_exists "$lane"; then sync_network_hook "$lane" install || return 1; else sync_network_hook "$lane" remove || return 1; fi
        fi
    done
}

build_cron_job() {
    local minutes="$1"
    local run_cmd="$2"
    local schedule hours
    if (( minutes < 60 && 60 % minutes == 0 )); then
        schedule="*/${minutes} * * * *"
        printf '%s %s\n' "${schedule}" "${run_cmd}"
    elif (( minutes == 60 )); then
        printf '0 * * * * %s\n' "${run_cmd}"
    elif (( minutes < 1440 && minutes % 60 == 0 && 1440 % minutes == 0 )); then
        hours=$((minutes / 60))
        printf '0 */%s * * * %s\n' "${hours}" "${run_cmd}"
    elif (( minutes == 1440 )); then
        printf '0 0 * * * %s\n' "${run_cmd}"
    elif (( minutes % 60 == 0 )); then
        hours=$((minutes / 60))
        printf '0 * * * * now=$(date +\\%%s); if [ $((now / 3600 \\%% %s)) -eq 0 ]; then %s; fi\n' "${hours}" "${run_cmd}"
    else
        printf '* * * * now=$(date +\\%%s); if [ $((now / 60 \\%% %s)) -eq 0 ]; then %s; fi\n' "${minutes}" "${run_cmd}"
    fi
}

schedule_timer_enabled() {
    local value="${WORKER_TIMER_ENABLED:-1}"
    [[ "$1" != official ]] || value="${OFFICIAL_TIMER_ENABLED:-1}"
    case "$value" in 0|false|no|off) return 1 ;; *) return 0 ;; esac
}

network_event_backend() {
    if declare -F is_macos >/dev/null && is_macos && command -v scutil >/dev/null 2>&1; then printf 'scutil'; return; fi
    if [[ "${EUID:-$(id -u)}" == 0 && -d /etc/NetworkManager/dispatcher.d ]] && command -v nmcli >/dev/null 2>&1; then printf 'NetworkManager'; return; fi
    if [[ "${EUID:-$(id -u)}" == 0 && -d /etc/hotplug.d/iface ]] && command -v ubus >/dev/null 2>&1; then printf 'OpenWrt'; return; fi
    printf 'none'
}

schedule_network_enabled() {
    local value="${WORKER_NETWORK_ENABLED:-1}"
    [[ "$1" != official ]] || value="${OFFICIAL_NETWORK_ENABLED:-1}"
    case "$value" in 0|false|no|off) return 1 ;; *) return 0 ;; esac
}

network_hook_paths() {
    printf '/etc/NetworkManager/dispatcher.d/90-outbound-ip-report-%s\n' "$1"
    printf '/etc/hotplug.d/iface/90-outbound-ip-report-%s\n' "$1"
}

sync_network_hook() {
    local channel="$1" action="${2:-install}" backend path script
    backend="$(network_event_backend)"
    if [[ "$backend" == scutil ]]; then sync_macos_network_task "$channel" "$action"; return; fi
    if [[ "$action" == remove ]]; then
        while IFS= read -r path; do
            if [[ -f "$path" ]] && grep -Fq '# Outbound IP Report managed network hook' "$path"; then rm -f "$path" || return 1; fi
        done < <(network_hook_paths "$channel")
        return 0
    fi
    [[ "$backend" != none ]] || return 0
    if ! schedule_network_enabled "$channel" || ! schedule_channel_configured "$channel"; then sync_network_hook "$channel" remove; return; fi
    script="$(default_install_path)"
    if [[ "$backend" == NetworkManager ]]; then path="/etc/NetworkManager/dispatcher.d/90-outbound-ip-report-$channel"; else path="/etc/hotplug.d/iface/90-outbound-ip-report-$channel"; fi
    if [[ -f "$path" ]] && ! grep -Fq '# Outbound IP Report managed network hook' "$path"; then printf '网络事件文件已被其它程序占用，未覆盖。\n' >&2; return 1; fi
    {
        printf '#!/bin/sh\n# Outbound IP Report managed network hook\n'
        printf 'case "${2:-${ACTION:-}}" in up|dhcp4-change|connectivity-change|ifup|ifupdate) ;; *) exit 0 ;; esac\n'
        printf 'exec /bin/bash %s --config %s --scheduled-run --network-changed --%s-only >>%s 2>&1\n' "$(sh_quote "$script")" "$(sh_quote "$CONFIG_FILE")" "$channel" "$(sh_quote "$(schedule_channel_log_path "$channel")")"
    } > "$path" || return 1
    chmod 700 "$path"
}

watch_network_changes() {
    local channel script changed
    channel="${REPORT_MODE:-all}"
    [[ "${OFFICIAL_ONLY:-0}" != 1 ]] || channel=official
    [[ "${WORKER_ONLY:-0}" != 1 ]] || channel=worker
    case "$channel" in worker|official) ;; *) printf '网络监听必须选择一个通道。\n' >&2; return 1 ;; esac
    [[ "$(network_event_backend)" == scutil ]] || return 1
    script="$(default_install_path)"
    while true; do
        changed="$(printf 'n.add State:/Network/Global/IPv4\nn.add State:/Network/Global/IPv6\nn.add State:/Network/Interface/.*/IPv4 pattern\nn.wait\nn.changes\nquit\n' | scutil)" || return 1
        [[ "$changed" == *changedKey* ]] || return 1
        sleep 2
        bash "$script" --config "$CONFIG_FILE" --scheduled-run --network-changed "--$channel-only" >>"$(schedule_channel_log_path "$channel")" 2>&1 || true
    done
}
