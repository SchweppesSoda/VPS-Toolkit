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

import_worker_official() {
    local dir="${1:-}" tokens imported active=0 current="${PO0_FIREWALL_TOKENS:-}"
    [[ -d "$dir" && -f "$dir/settings.env" && ! -L "$dir/settings.env" ]] || { printf '缺少 Worker 迁移备份。\n' >&2; return 1; }
    # Parse shell-quoted data without executing the saved Worker configuration.
    imported="$(python3 - "$dir/settings.env" "$dir/crontab" <<'PY'
import pathlib, re, shlex, sys
try:
    values = {}
    for line in pathlib.Path(sys.argv[1]).read_text(encoding='utf-8').splitlines():
        if line.startswith(('PO0_FIREWALL_TOKENS=', 'CONFIG_FILE=')):
            fields = shlex.split(line, comments=True)
            if len(fields) != 1: raise ValueError()
            key, value = fields[0].split('=', 1)
            if key in values or any(c in value for c in '\r\n\0'): raise ValueError()
            values[key] = value
    config = values.get('CONFIG_FILE', '')
    active = False
    owned = False
    cron = pathlib.Path(sys.argv[2])
    if config and cron.is_file():
        for line in cron.read_text(encoding='utf-8').splitlines():
            if line == '# PO0_LAN_CLIENT_BEGIN ' + config: owned = True; continue
            if line == '# PO0_LAN_CLIENT_END ' + config: owned = False; continue
            if owned and line.strip() and not line.lstrip().startswith('#'):
                if '--run-official-firewall' in line and '--scheduled-run' in line: active = True
        if owned: raise ValueError()
    print('1' if active else '0')
    print(values.get('PO0_FIREWALL_TOKENS', ''))
except Exception:
    sys.stderr.write('无法解析 Worker 官方配置。\n'); sys.exit(1)
PY
    )" || return 1
    imported="${imported//$'\r'/}"
    active="${imported%%$'\n'*}"
    tokens="${imported#*$'\n'}"
    [[ -n "$tokens" ]] || { printf '旧 Worker 未配置官方 Token。\n'; return 1; }
    PO0_FIREWALL_TOKENS="$tokens"
    official_validate_tokens || { PO0_FIREWALL_TOKENS="$current"; return 1; }
    if [[ -n "$current" && "$current" != "$tokens" ]]; then
        PO0_FIREWALL_TOKENS="$current"
        printf '目标客户端已有不同官方配置；迁移已停止，未覆盖。\n' >&2; return 1
    fi
    if [[ -z "$current" ]] && ! channel_auto_enabled official; then
        PO0_FIREWALL_TOKENS="$current"
        printf '目标客户端已明确停用并清除官方配置；请使用独立配置路径迁移。\n' >&2; return 1
    fi
    if [[ -z "$current" ]]; then
        OFFICIAL_AUTO_ENABLED="$active"
        OFFICIAL_TIMER_ENABLED=1
        OFFICIAL_NETWORK_ENABLED=0
        OFFICIAL_INTERVAL_SECONDS=600
    fi
    save_config_file || return 1
    (umask 077; printf '%s\n' "$CONFIG_FILE" > "$dir/official-client-config") || return 1
    printf '官方配置已导入本机；旧 Worker 停止后再启用原有定时计划。\n'
}

activate_imported_worker_official() {
    local dir="${1:-}"
    [[ -f "$dir/retired" && -f "$dir/official-client-config" ]] || { printf '旧 Worker 尚未退役，未启用新任务。\n' >&2; return 1; }
    [[ "$(cat "$dir/official-client-config")" == "$CONFIG_FILE" ]] || return 1
    if channel_auto_enabled official && ! cron_managed_block_exists official; then
        install_cron official || return 1
    fi
    printf '同机官方客户端迁移完成；网络出口仍使用本机正常路由。\n'
}
