apply_launchd_schedules() {
    local action="$1" target="${2:-all}" channel selected legacy=0 script='' plist todo='' remove='' stage
    case "$target" in worker|official|all) ;; *) return 1 ;; esac
    launchd_supported || return 1
    legacy_schedule_exists && legacy=1
    if [[ "$legacy" == 1 && "$action" == refresh ]] && legacy_schedule_paused; then SCHEDULE_PAUSED=1; save_config_file || return 1; fi
    for channel in worker official; do
        selected=0
        [[ "$target" == all || "$target" == "$channel" ]] && selected=1
        if [[ "$selected" == 1 ]]; then
            case "$action" in
                install) if schedule_channel_configured "$channel"; then todo="$todo $channel"; elif [[ "$target" != all ]]; then schedule_channel_validate "$channel"; return 1; fi ;;
                refresh) if channel_schedule_exists "$channel" || [[ "$legacy" == 1 ]]; then if schedule_channel_configured "$channel"; then todo="$todo $channel"; else remove="$remove $channel"; fi; fi ;;
                remove) remove="$remove $channel" ;;
                *) return 1 ;;
            esac
        elif [[ "$legacy" == 1 ]] && ! channel_schedule_exists "$channel" && schedule_channel_configured "$channel"; then
            todo="$todo $channel"
        fi
    done
    if [[ "$action" == install && -z "$todo" ]]; then printf '没有已配置的上报通道。\n' >&2; return 1; fi
    for channel in $todo; do schedule_channel_validate "$channel" || return 1; done
    if [[ -n "$todo" ]]; then script="$(install_self)" || return 1; fi
    stage="$(mktemp -d "${TMPDIR:-/tmp}/po0-launchd-stage.XXXXXX")" || return 1
    for channel in $todo; do
        if ! write_launchd_plist "$stage/$channel.plist" "$script" "$(($(schedule_channel_minutes "$channel") * 60))" "$channel"; then rm -f "$stage"/*.plist; rmdir "$stage"; return 1; fi
    done
    # Prepare every new file before retiring the shared task.
    if [[ "$legacy" == 1 ]]; then
        remove_legacy_launchd_if_exists || { rm -f "$stage"/*.plist; rmdir "$stage"; return 1; }
        if legacy_cron_block_exists; then apply_channel_cron remove all || return 1; fi
    fi
    for channel in $remove; do
        sync_network_hook "$channel" remove || return 1
        if cron_managed_block_exists "$channel"; then apply_channel_cron remove "$channel" || return 1; fi
        plist="$(launchd_plist_path "$channel")"
        if [[ -f "$plist" ]]; then launchd_unload "$plist"; rm -f "$plist" || return 1; fi
    done
    for channel in $todo; do
        # Only retire this channel's previous cron, never the sibling's task.
        if cron_managed_block_exists "$channel"; then apply_channel_cron remove "$channel" || return 1; fi
        plist="$(launchd_plist_path "$channel")"
        mkdir -p "$(path_dirname "$plist")" || return 1
        launchd_unload "$plist"
        mv -f "$stage/$channel.plist" "$plist" || return 1
        chmod 644 "$plist" || return 1
        sync_network_hook "$channel" install || return 1
        if ! schedule_channel_paused "$channel" && schedule_timer_enabled "$channel"; then launchd_load "$plist" "$channel" || return 1; fi
    done
    rmdir "$stage"
}

install_cron() {
    local channel="${1:-${SCHEDULE_CHANNEL:-all}}"
    save_config_file || return 1
    if launchd_supported; then apply_launchd_schedules install "$channel"; else apply_channel_cron install "$channel"; fi || return 1
    self_report_completed '各通道的定时任务已分别安装。'
    show_cron_status "$channel"
}

install_launchd() { install_cron "${1:-${SCHEDULE_CHANNEL:-all}}"; }
install_cron_backend() { apply_channel_cron install "${1:-all}"; }
remove_cron_backend() { apply_channel_cron remove "${1:-all}"; }
remove_launchd() { apply_launchd_schedules remove "${1:-all}"; }

remove_cron() {
    local channel="${1:-${SCHEDULE_CHANNEL:-all}}"
    if launchd_supported; then apply_launchd_schedules remove "$channel"; else apply_channel_cron remove "$channel"; fi || return 1
    self_report_completed '已删除所选通道任务，保存配置保留。'
}

sync_macos_network_task() {
    local channel="$1" action="$2" plist script label disabled=false
    label="$(launchd_label "$channel.network")"
    plist="$(launchd_plist_path "$channel.network")"
    if [[ "$action" == remove ]] || ! schedule_network_enabled "$channel"; then
        if [[ -f "$plist" ]]; then launchd_unload "$plist"; rm -f "$plist" || return 1; fi
        return 0
    fi
    script="$(default_install_path)"
    if schedule_channel_paused "$channel"; then disabled=true; fi
    mkdir -p "$(path_dirname "$plist")" || return 1
    launchd_unload "$plist"
    cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$(xml_escape "$label")</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$(xml_escape "$script")</string><string>--config</string><string>$(xml_escape "$CONFIG_FILE")</string><string>--watch-network</string><string>--$channel-only</string></array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><true/>
<key>ThrottleInterval</key><integer>10</integer>
<key>Disabled</key><$disabled/>
<key>StandardOutPath</key><string>$(xml_escape "$(schedule_channel_log_path "$channel")")</string>
<key>StandardErrorPath</key><string>$(xml_escape "$(schedule_channel_log_path "$channel")")</string>
</dict></plist>
EOF
    chmod 644 "$plist" || return 1
    if [[ "$disabled" == false ]]; then launchd_load "$plist" "$channel.network" || return 1; fi
}
