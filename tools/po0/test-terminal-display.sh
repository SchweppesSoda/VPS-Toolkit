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
        contains "$tmp_dir/$platform-$quota" '当前出口'
        contains "$tmp_dir/$platform-$quota" "占用 2/$quota"
        absent "$tmp_dir/$platform-$quota" $'\033'
        absent "$tmp_dir/$platform-$quota" 'pgnfw_'
    done
    records="$records
2|missing|198.51.100.25/24|192.0.2.2/24@|1|7|
3|error|||||9"
    COLUMNS=35 NO_COLOR=1 po0_display_render '上报结果' "$records" 1793341928 1 > "$tmp_dir/$platform-narrow"
    contains "$tmp_dir/$platform-narrow" '失败账号'
    contains "$tmp_dir/$platform-narrow" '未编号'
    contains "$tmp_dir/$platform-narrow" '说明：部分记录未返回槽位编号'
    contains "$tmp_dir/$platform-narrow" '本次未取得白名单'
    contains "$tmp_dir/$platform-narrow" '    203.0.113.25/24'
    absent "$tmp_dir/$platform-narrow" $'\033'
    full=''
    for (( slot=0; slot<10; slot++ )); do full="$full${full:+,}203.0.113.$((slot + 1))/24@$slot"; done
    po0_display_render '查询' "1|hit|203.0.113.10/24|$full|10|10|" 0 > "$tmp_dir/$platform-full"
    contains "$tmp_dir/$platform-full" '已放行'
    contains "$tmp_dir/$platform-full" '剩余 0 个'
    contains "$tmp_dir/$platform-full" '尚无记录'
    # Unknown slot positions do not imply empty slots.
    po0_display_render '查询' '1|hit|203.0.113.1/24|203.0.113.1/24@|1|7|' 0 > "$tmp_dir/$platform-unknown"
    absent "$tmp_dir/$platform-unknown" '空闲'
    contains "$tmp_dir/$platform-unknown" '当前出口'
    po0_display_render '查询' '1|hit|203.0.113.25/24|192.0.2.18/24@0,203.0.113.25/24@,198.51.100.42/24@|3|7|' 0 > "$tmp_dir/$platform-mixed"
    for value in '#1' '未编号' '192.0.2.18/24' '203.0.113.25/24' '198.51.100.42/24' '占用 3/7' '剩余 4 个'; do contains "$tmp_dir/$platform-mixed" "$value"; done
    for value in '#2' '#7' '空闲' '未知（' '失败 0' '更新 0'; do absent "$tmp_dir/$platform-mixed" "$value"; done
    [[ "$(grep -c '说明：' "$tmp_dir/$platform-mixed")" == 1 ]] || fail 'repeated unknown-slot explanation'
    [[ "$(po0_cell_width '槽位')" == 4 && "$(po0_cell_width "$(po0_pad_cell '未编号' 8)")" == 8 ]] || fail 'CJK alignment broken'
    [[ "$(po0_duration 1800)" == '30 分钟' ]] || fail 'duration formatting broken'
    . "$src/030-version-and-script-metadata.sh"
    (exec 4>"$tmp_dir/$platform-detail-log"; PO0_UI_LIVE=1 PO0_DISPLAY_LOG_FD=4 po0_display_detail '%s\n' 'fixture progress') > "$tmp_dir/$platform-detail-screen"
    [[ ! -s "$tmp_dir/$platform-detail-screen" ]] || fail 'duplicate progress on screen'
    contains "$tmp_dir/$platform-detail-log" 'fixture progress'
    (exec 4>"$tmp_dir/$platform-complete-log"; PO0_UI_RENDERED=1 PO0_DISPLAY_LOG_FD=4 self_report_completed 'fixture completion') > "$tmp_dir/$platform-complete-screen"
    [[ ! -s "$tmp_dir/$platform-complete-screen" ]] || fail 'duplicate completion on screen'
    contains "$tmp_dir/$platform-complete-log" 'fixture completion'
    PO0_UI_RENDERED=0 self_report_completed '本轮跳过' > "$tmp_dir/$platform-skip"
    contains "$tmp_dir/$platform-skip" '本轮跳过'
    # Cache association invalidates account reorder and fixed-slot edits without changing due.
    fixture_state_path="$tmp_dir/$platform-state"
    po0_display_state_path() { printf '%s\n' "$fixture_state_path"; }
    printf 'last_attempt_at=123\nlast_checked_at=1793341928\ndisplay_config_id=%s\nitem=%s\n' "$(po0_display_config_id)" '1|hit|203.0.113.1/24|203.0.113.1/24@9|1|10|' > "$fixture_state_path"
    before="$(cat "$fixture_state_path")"
    po0_display_cached > "$tmp_dir/$platform-cache"
    contains "$tmp_dir/$platform-cache" '上次结果 / 本地记录'
    [[ "$(cat "$fixture_state_path")" == "$before" ]] || fail 'cache view changed state'
    PO0_FIREWALL_TOKENS='pgnfw_fixture_b,pgnfw_fixture_a'
    po0_display_cached > "$tmp_dir/$platform-changed"
    contains "$tmp_dir/$platform-changed" '账号配置已更新'
    absent "$tmp_dir/$platform-changed" '#10'
    PO0_FIREWALL_TOKENS='pgnfw_fixture_a@9,pgnfw_fixture_b'
    po0_display_cached > "$tmp_dir/$platform-slot-change"
    contains "$tmp_dir/$platform-slot-change" '账号配置已更新'
    printf 'last_attempt_at=123\n' > "$fixture_state_path"
    po0_display_cached > "$tmp_dir/$platform-old"
    contains "$tmp_dir/$platform-old" '暂无新版记录'
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
    # Forced-color palette: hierarchy uses bold, informative text keeps the default
    # foreground, and bright black (90) never appears. NO_COLOR still yields plain text.
    (
        po0_color_enabled() { [[ -z "${NO_COLOR+x}" ]]; }
        unset NO_COLOR SCHEDULED_RUN
        setup_colors
        exact() { grep -Fxq -- "$2" "$1" || fail "missing line $2"; }
        out="$tmp_dir/$platform-palette"
        {
            print_title 'PO0 防火墙' 'v9.9.9'
            print_panel_section '分组标题'
            print_panel_row '行标签' '普通值'
            print_panel_note '说明文字'
            print_menu_item 1 '菜单项'
            print_menu_item 0 '返回'
        } > "$out"
        absent "$out" $'\033[90m'
        contains "$out" $'  \033[1;36mPO0 防火墙\033[0m'
        line="$(grep -F 'v9.9.9' "$out")"; line="${line##*$'\033[0m'}"
        [[ "${line// /}" == v9.9.9 ]] || fail 'version text is not default foreground'
        contains "$out" $'  \033[2m'
        exact "$out" $'  \033[1m分组标题\033[0m'
        exact "$out" "  $(po0_pad_cell '行标签' 12)普通值"
        exact "$out" '  说明文字'
        exact "$out" $'    \033[36m[1]\033[0m  菜单项'
        exact "$out" '    [0]  返回'
        label="$(po0_pad_cell '状态' 12)"
        while IFS='|' read -r value tone code; do
            line="$(print_panel_status_row '状态' "$value" ${tone:+"$tone"})"
            if [[ -z "$code" ]]; then [[ "$line" == "  $label$value" ]] || fail "status plain: $value/$tone"
            else [[ "$line" == "  $label"$'\033['"${code}m$value"$'\033[0m' ]] || fail "status tone: $value/$tone"; fi
        done <<'CASES'
运行中||32
已启用（每 10 分钟）||32
已安装 · 就绪||32
已暂停||33
未配置||33
已放行 · 等待下次检查||33
上报失败||31
已启用，但最近一次失败||31
每 600 秒||
已启用|warn|33
失败|ok|32
已启用|plain|
未配置|bogus|33
CASES
        multi='1|hit|203.0.113.25/24|192.0.2.18/24@0,203.0.113.25/24@6|2|7|
2|missing|198.51.100.25/24|192.0.2.2/24@1|1|7|
3|error|||||9'
        COLUMNS=100 po0_display_render '上报结果' "$multi" 1793341928 1 > "$out-table"
        absent "$out-table" $'\033[90m'
        for value in $'    \033[1m槽位' $'    \033[2m#2' $'\033[32m已放行' $'\033[33m未放行' $'\033[31m操作失败' $'  \033[1;36m第二账号'; do
            contains "$out-table" "$value"
        done
        exact "$out-table" '  占用 2/7  ·  剩余 5 个  ·  自动分配'
        exact "$out-table" "  $(po0_pad_cell '检查时间' 12)$(po0_display_time 1793341928)"
        NO_COLOR=1 COLUMNS=100 po0_display_render '上报结果' "$multi" 1793341928 1 > "$out-plain"
        absent "$out-plain" $'\033'
        contains "$out-plain" '    槽位'
        PO0_FIREWALL_TOKENS='pgnfw_fixture_a,pgnfw_fixture_b'
        printf 'last_checked_at=1793341928\ndisplay_config_id=%s\nitem=%s\nitem=%s\n' "$(po0_display_config_id)" \
            '1|hit|203.0.113.1/24|203.0.113.1/24@0|1|7|' '2|added|203.0.113.1/24|203.0.113.1/24@1|1|7|' > "$fixture_state_path"
        po0_display_cached summary > "$out-cache"
        contains "$out-cache" $'\033[32m'"$(po0_display_time 1793341928) · 2/2 已放行"$'\033[0m'
        printf 'item=%s\n' '3|missing|203.0.113.1/24||0|7|' >> "$fixture_state_path"
        po0_display_cached summary > "$out-cache"
        contains "$out-cache" $'\033[33m'"$(po0_display_time 1793341928) · 2/3 已放行"
        (export NO_COLOR=1; setup_colors; po0_display_cached summary; print_title 'PO0 防火墙' 'v9.9.9'
            print_panel_section '分组标题'; print_panel_status_row '状态' '上报失败'; print_menu_item 1 '菜单项') > "$out-cache-plain"
        absent "$out-cache-plain" $'\033'
        contains "$out-cache-plain" '2/3 已放行'
        PO0_FIREWALL_TOKENS='pgnfw_fixture_b'
        po0_display_cached summary > "$out-cache"
        contains "$out-cache" $'\033[33m账号配置已更新，等待下次检查'
        printf 'last_checked_at=1793341928\n' > "$fixture_state_path"
        po0_display_cached summary > "$out-cache"
        contains "$out-cache" $'\033[33m暂无新版记录，检查后显示'
    )
)
done
printf 'PASS: terminal full-slot rendering, cache identity, output modes and readable palette.\n'
