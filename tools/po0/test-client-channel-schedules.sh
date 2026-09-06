#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd -P)"
mkdir -p "$repo/.tmp"
fixture_root="$(mktemp -d "$repo/.tmp/po0-channel-schedules.XXXXXX")"
trap 'case "$fixture_root" in "$repo"/.tmp/po0-*) rm -rf "$fixture_root" ;; esac' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
for platform in linux macos; do
(
    for file in "$repo/scripts/po0/relay/self-report/$platform/src/"*; do
        [[ "$file" != */990-* ]] || continue
        source "$file" || { [[ "$file" == */000-* ]] || exit 1; }
    done
    CONFIG_FILE="$fixture_root/$platform.env"
    LOG_FILE="$fixture_root/$platform.log"
    CRON_MINUTES=60; OFFICIAL_INTERVAL_SECONDS=900
    WORKER_AUTO_ENABLED=1; OFFICIAL_AUTO_ENABLED=1; SCHEDULE_PAUSED=0
    WORKER_TIMER_ENABLED=1; OFFICIAL_TIMER_ENABLED=1
    WORKER_URL='https://worker.example.test/report'; SECRET='test-secret'; PO0_FIREWALL_TOKENS='pgnfw_schedule_fixture@1'
    cron="$fixture_root/$platform.cron"; calls="$fixture_root/$platform.calls"; dest="$fixture_root/reporter"
    printf '#!/bin/bash\n' > "$dest"
    printf '17 3 * * * echo unrelated\n' > "$cron"
    crontab() { if [[ "${1:-}" == -l ]]; then cat "$cron"; else cp "$1" "$cron"; fi; }
    install_self() { printf '%s\n' "$dest"; }
    default_install_path() { printf '%s\n' "$dest"; }
    save_config_file() { :; }
    self_report_log_path() { printf '%s\n' "$fixture_root/$platform.log"; }
    sync_network_hook() { printf '%s %s\n' "$1" "$2" >> "$calls"; }
    network_event_backend() { printf none; }
    if [[ "$platform" == macos ]]; then
        launchd_supported() { return 1; }
    fi
    install_cron all >/dev/null
    [[ "$(grep -c '^# OUTBOUND_IP_REPORT_.*_BEGIN' "$cron")" == 2 ]] || fail "$platform must install two cron blocks"
    grep -q -- '--scheduled-run --worker-only' "$cron" || fail 'worker scope missing'
    grep -q -- '--scheduled-run --official-only' "$cron" || fail 'official scope missing'
    grep -q '^\*/15 .*--official-only' "$cron" || fail 'custom official interval ignored'
    ! grep -q 'test-secret\|pgnfw_' "$cron" || fail 'credentials in task'
    worker_before="$(cron_channel_block worker)"
    set_schedule_paused 1 official >/dev/null
    [[ "$(cron_channel_block worker)" == "$worker_before" ]] || fail 'pausing official modified worker'
    [[ "$(cron_status_summary official)" == *已暂停* ]] || fail 'official not paused'
    set_schedule_paused 0 official >/dev/null
    remove_cron worker >/dev/null
    ! cron_managed_block_exists worker || fail 'worker removal failed'
    cron_managed_block_exists official || fail 'worker removal removed official'
    refresh_channel_schedules all >/dev/null
    ! cron_managed_block_exists worker || fail 'refresh recreated removed worker'
    update_channel_schedule_if_installed worker >/dev/null
    ! cron_managed_block_exists worker || fail 'saving recreated removed worker'
    channel_schedules_current "$dest" || fail "$platform current schedule treated as stale"
    run_updated_script() { printf '%s\n' "$*" >> "$calls"; return "${RUN_UPDATED_STATUS:-0}"; }
    : > "$calls"
    refresh_schedule_after_script_update "$dest" >/dev/null
    [[ ! -s "$calls" ]] || fail 'current upgrade must not rewrite tasks'
    OFFICIAL_INTERVAL_SECONDS=1200
    refresh_schedule_after_script_update "$dest" >/dev/null
    grep -q -- '--refresh-schedules' "$calls" || fail 'upgrade must refresh existing channels only'
    RUN_UPDATED_STATUS=1
    refresh_schedule_after_script_update "$dest" > "$fixture_root/upgrade-warning" 2>&1
    grep -q '失败' "$fixture_root/upgrade-warning" || fail 'upgrade failure warning missing'
    RUN_UPDATED_STATUS=0
    if channel_schedules_current "$dest"; then fail 'changed interval not detected'; fi
    printf '17 3 * * * echo unrelated\n# OUTBOUND_IP_REPORT_BEGIN %s\n*/10 * * * * old-reporter\n# OUTBOUND_IP_REPORT_END %s\n' "$CONFIG_FILE" "$CONFIG_FILE" > "$cron"
    refresh_channel_schedules all >/dev/null
    [[ "$(grep -c '^# OUTBOUND_IP_REPORT_.*_BEGIN' "$cron")" == 2 ]] || fail 'shared migration did not create two tasks'
    ! grep -q old-reporter "$cron" || fail 'old shared task survived'
    grep -q 'echo unrelated' "$cron" || fail 'unrelated job removed'
    OFFICIAL_TIMER_ENABLED=0
    refresh_channel_schedules official >/dev/null
    [[ "$(cron_status_summary official)" == *已暂停* ]] || fail 'timer disable ignored'
    grep -q 'official install' "$calls" || fail 'timer disable removed network hook'
    if [[ "$platform" == macos ]]; then
        launchd_supported() { return 0; }
        launchd_plist_path() { printf '%s/%s.plist\n' "$fixture_root" "${1:-worker}"; }
        launchd_plist_path_for_label() { printf '%s/%s.plist\n' "$fixture_root" "$1"; }
        launchctl() { printf '%s\n' "$*" >> "$calls"; }
        OFFICIAL_TIMER_ENABLED=1
        install_cron all >/dev/null
        [[ -f "$fixture_root/worker.plist" && -f "$fixture_root/official.plist" ]] || fail 'two launchd tasks missing'
        grep -q 'outbound-ip-report.official' "$fixture_root/official.plist" || fail 'official launchd label'
        grep -q '<string>--official-only</string>' "$fixture_root/official.plist" || fail 'official launchd scope'
        ! cron_managed_block_exists || fail 'launchd migration retained cron'
        sync_macos_network_task official install
        grep -q -- '--watch-network' "$fixture_root/official.network.plist" || fail 'macOS network watcher not installed'
        grep -q '<key>KeepAlive</key><true/>' "$fixture_root/official.network.plist" || fail 'macOS watcher not persistent'
        ! grep -q -- '--timer-trigger' "$fixture_root/official.network.plist" || fail 'network watcher classified as timer'
        worker_before="$(cat "$fixture_root/worker.plist")"
        set_schedule_paused 1 official >/dev/null
        [[ "$(cat "$fixture_root/worker.plist")" == "$worker_before" ]] || fail 'official pause modified worker plist'
        remove_cron worker >/dev/null
        [[ ! -f "$fixture_root/worker.plist" && -f "$fixture_root/official.plist" ]] || fail 'launchd scoped removal'
        refresh_channel_schedules all >/dev/null
        [[ ! -f "$fixture_root/worker.plist" ]] || fail 'launchd refresh resurrected worker'
    fi
    printf '# OUTBOUND_IP_REPORT_BEGIN %s\n# paused=1\n# OUTBOUND_IP_REPORT_END %s\n' "$CONFIG_FILE" "$CONFIG_FILE" > "$cron"
    SCHEDULE_PAUSED=0
    refresh_channel_schedules all >/dev/null
    [[ "$SCHEDULE_PAUSED" == 1 ]] || fail 'migration resumed a paused shared task'
    SCHEDULED_RUN=1; FORCE_REPORT=0; NETWORK_CHANGED=1; TIMER_TRIGGER=0
    if [[ "$platform" == linux ]]; then official_due || fail 'network event blocked by due'; else po0_firewall_due || fail 'network event blocked by due'; fi
    NETWORK_CHANGED=0; TIMER_TRIGGER=1
    if [[ "$platform" == linux ]]; then official_due || fail 'system timer blocked by due'; else po0_firewall_due || fail 'system timer blocked by due'; fi
    printf 'PASS: %s independent scheduler install/pause/remove/migration/refresh\n' "$platform"
)
done
