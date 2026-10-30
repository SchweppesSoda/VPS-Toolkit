#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
mkdir -p "$repo_root/.tmp"
tmp_dir="$(mktemp -d "$repo_root/.tmp/po0-terminal-display.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
contains() { grep -Fq -- "$2" "$1" || fail "missing $2"; }
absent() { if grep -Fq -- "$2" "$1"; then fail "unexpected $2"; fi; }
cmp "$repo_root/scripts/po0/relay/self-report/linux/src/025-official-display.sh" "$repo_root/scripts/po0/relay/self-report/macos/src/025-official-display.sh"

for platform in linux macos; do
(
    src="$repo_root/scripts/po0/relay/self-report/$platform/src"
    . "$src/010-core-string-path-config.sh"
    . "$src/020-ui-rendering.sh"
    . "$src/076-channel-settings.sh"
    . "$src/025-official-display.sh"
    if [[ "$platform" == linux ]]; then . "$src/125-official-report.sh"; else . "$src/078-official-firewall.sh"; fi
    # Requests and clocks are test-local. None of these tests uses real credentials.
    official_direct_request() { fail 'renderer attempted a request'; }
    po0_firewall_direct_request() { fail 'renderer attempted a request'; }
    PO0_FIREWALL_TOKENS='pgnfw_fixture_a,pgnfw_fixture_b'
    PO0_FIREWALL_NAMES='很长的中文账号名称以及 Office Wi-Fi;第二账号;失败账号'
    for quota in 5 7 10; do
        last=$((quota - 1))
        records="1|hit|203.0.113.25/24|192.0.2.18/24@0,203.0.113.25/24@$last|2|$quota|"
        COLUMNS=100 po0_display_render '只读查询' "$records" 1793341928 > "$tmp_dir/$platform-$quota"
        for (( slot=1; slot<=quota; slot++ )); do contains "$tmp_dir/$platform-$quota" "#$slot"; done
        contains "$tmp_dir/$platform-$quota" '203.0.113.25/24'
        contains "$tmp_dir/$platform-$quota" '当前命中'
        contains "$tmp_dir/$platform-$quota" "占用 2/$quota"
        absent "$tmp_dir/$platform-$quota" $'\033'
        absent "$tmp_dir/$platform-$quota" 'pgnfw_'
    done
    records="$records
2|missing|198.51.100.25/24|192.0.2.2/24@|1|7|
3|error|||||9"
    COLUMNS=35 NO_COLOR=1 po0_display_render '上报结果' "$records" 1793341928 1 > "$tmp_dir/$platform-narrow"
    contains "$tmp_dir/$platform-narrow" '失败账号'
    contains "$tmp_dir/$platform-narrow" '槽位未知'
    contains "$tmp_dir/$platform-narrow" '未知（有未编号记录）'
    contains "$tmp_dir/$platform-narrow" '占用未知'
    contains "$tmp_dir/$platform-narrow" '    203.0.113.25/24'
    absent "$tmp_dir/$platform-narrow" $'\033'
    full=''
    for (( slot=0; slot<10; slot++ )); do full="$full${full:+,}203.0.113.$((slot + 1))/24@$slot"; done
    po0_display_render '查询' "1|hit|203.0.113.10/24|$full|10|10|" 0 > "$tmp_dir/$platform-full"
    contains "$tmp_dir/$platform-full" '已放行'
    contains "$tmp_dir/$platform-full" '剩余 0 个'
    contains "$tmp_dir/$platform-full" '检查时间 未知'
    # Unknown slot positions do not imply empty slots.
    po0_display_render '查询' '1|hit|203.0.113.1/24|203.0.113.1/24@|1|7|' 0 > "$tmp_dir/$platform-unknown"
    absent "$tmp_dir/$platform-unknown" '空闲'
    contains "$tmp_dir/$platform-unknown" '当前命中'
    # Cache association invalidates account reorder and fixed-slot edits without changing due.
    fixture_state_path="$tmp_dir/$platform-state"
    po0_display_state_path() { printf '%s\n' "$fixture_state_path"; }
    printf 'last_attempt_at=123\nlast_checked_at=1793341928\ndisplay_config_id=%s\nitem=%s\n' "$(po0_display_config_id)" '1|hit|203.0.113.1/24|203.0.113.1/24@9|1|10|' > "$fixture_state_path"
    before="$(cat "$fixture_state_path")"
    po0_display_cached > "$tmp_dir/$platform-cache"
    contains "$tmp_dir/$platform-cache" '上次结果（本地缓存）'
    [[ "$(cat "$fixture_state_path")" == "$before" ]] || fail 'cache view changed state'
    PO0_FIREWALL_TOKENS='pgnfw_fixture_b,pgnfw_fixture_a'
    po0_display_cached > "$tmp_dir/$platform-changed"
    contains "$tmp_dir/$platform-changed" '缓存未匹配'
    absent "$tmp_dir/$platform-changed" '#10'
    PO0_FIREWALL_TOKENS='pgnfw_fixture_a@9,pgnfw_fixture_b'
    po0_display_cached > "$tmp_dir/$platform-slot-change"
    contains "$tmp_dir/$platform-slot-change" '缓存未匹配'
    printf 'last_attempt_at=123\n' > "$fixture_state_path"
    po0_display_cached > "$tmp_dir/$platform-old"
    contains "$tmp_dir/$platform-old" '缓存未匹配'
    # A real read-only run saves a new checked timestamp and identity, never due.
    official_state_file() { printf '%s\n' "$fixture_state_path"; }
    po0_firewall_state_file() { printf '%s\n' "$fixture_state_path"; }
    official_secure_state_dir() { mkdir -p "$1"; }
    po0_firewall_secure_state_dir() { mkdir -p "$1"; }
    official_now() { printf '1793341928'; }
    po0_firewall_now() { printf '1793341928'; }
    request_log="$tmp_dir/$platform-requests"
    official_direct_request() {
        printf '%s\n' "$2" >> "$request_log"
        [[ "$2" == status ]] || return 1
        printf '%s\n' '{"enabled":true,"currentIp":"203.0.113.25/24","limit":10,"whitelist":[{"ip":"203.0.113.25/24","slot":9}]}'
    }
    po0_firewall_direct_request() { official_direct_request "$@"; }
    PO0_FIREWALL_TOKENS='pgnfw_fixture_a@9'
    if [[ "$platform" == linux ]]; then official_status_once_inner > "$tmp_dir/$platform-status" 2>&1;
    else po0_firewall_run status > "$tmp_dir/$platform-status" 2>&1; fi
    [[ "$(cat "$request_log")" == status ]] || fail 'read-only request count changed'
    contains "$fixture_state_path" 'last_attempt_at=123'
    contains "$fixture_state_path" 'last_checked_at=1793341928'
    contains "$fixture_state_path" "display_config_id=$(po0_display_config_id)"
    po0_display_cached > "$tmp_dir/$platform-fresh"
    contains "$tmp_dir/$platform-fresh" '#10'
    contains "$tmp_dir/$platform-fresh" '已放行'
    # Colors initialized before entering tee must not escape into its log.
    config_complete() { return 0; }
    schedule_channel_log_path() { printf '%s\n' "$tmp_dir/$platform-menu-log"; }
    run_once_interactive() { printf '%bfixture completion%b\n' "$C_GREEN" "$C_RESET"; }
    C_GREEN=$'\033[32m'; C_RESET=$'\033[0m'
    run_channel_interactive official > "$tmp_dir/$platform-menu-output"
    absent "$tmp_dir/$platform-menu-log" $'\033'
    SCHEDULED_RUN=1 po0_display_live '后台' "$records" 0 > "$tmp_dir/$platform-background"
    [[ ! -s "$tmp_dir/$platform-background" ]] || fail 'background rendered table'
    SCHEDULED_RUN=0 po0_display_live '重定向' "$records" 0 > "$tmp_dir/$platform-redirected"
    [[ ! -s "$tmp_dir/$platform-redirected" ]] || fail 'redirected live output rendered table'
)
done
printf 'PASS: terminal full-slot rendering, cache identity and output modes.\n'
