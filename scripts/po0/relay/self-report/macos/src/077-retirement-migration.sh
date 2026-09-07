retirement_backup() {
    local source backup
    source="$(config_read_file 2>/dev/null || true)"
    [[ -n "$source" && -f "$source" ]] || return 0
    backup="${source}.pre-retirement-v1"
    [[ -e "$backup" ]] && return 0
    [[ ! -L "$source" && ! -L "$backup" ]] || return 1
    (umask 077; cp -p "$source" "$backup" && chmod 600 "$backup") || return 1
}

migrate_retired_state() {
    retirement_backup || { printf '无法备份旧配置，迁移已暂停。\n' >&2; return 1; }
    local backup="${CONFIG_FILE}.pre-retirement-crontab-v1"
    if command -v crontab >/dev/null 2>&1 && [[ ! -e "$backup" ]]; then
        (umask 077; crontab -l > "$backup" 2>/dev/null || true)
    fi
    # Existing official jobs retain their enabled state and timing. The generic
    # scheduler still recognizes retired task names solely for safe removal.
    remove_cron worker || return 1
    refresh_channel_schedules official || return 1
    save_config_file || return 1
    printf '自建任务已退役；官方设置保留。旧配置：%s.pre-retirement-v1\n' "$CONFIG_FILE"
}
