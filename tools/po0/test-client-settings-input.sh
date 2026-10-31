#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
mkdir -p "$repo_root/.tmp"
test_dir="$(mktemp -d "$repo_root/.tmp/po0-client-settings.XXXXXX")"
test_dir="$(cd "$test_dir" && pwd -P)"
case "$test_dir" in "$repo_root"/.tmp/po0-client-settings.*) ;; *) exit 1 ;; esac
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
for platform in linux macos; do
    (
        set +e
        while IFS= read -r entry; do
            entry="${entry%$'\r'}"
            case "$entry" in ''|\#*|*/990-*) continue ;; esac
            . "$repo_root/$entry"
        done < "$repo_root/tools/po0/manifests/self-report-$platform.txt"
        set -Eeuo pipefail
        trap 'printf "FAIL: settings test line %s\n" "$LINENO" >&2' ERR
        CONFIG_FILE="$test_dir/settings-$platform.env"
        XDG_STATE_HOME="$test_dir/state-$platform"
        PO0_FIREWALL_TOKENS='pgnfw_visible_fixture@3'
        SECRET='worker-visible-fixture'
        print_panel_section() { :; }
        print_panel_row() { printf '%s=%s\n' "$1" "$2"; }
        eval "$(declare -f save_config_file | sed '1s/save_config_file/real_save_config_file/')"
        save_config_file() { printf '%s\n' "$PO0_FIREWALL_TOKENS" > "$CONFIG_FILE"; }
        current_wifi_ssid_label() { printf 'Fixture Wi-Fi'; }
        show_current_config > "$test_dir/view-$platform"
        ! grep -Fq '上报密钥=worker-visible-fixture' "$test_dir/view-$platform"
        grep -Fq 'Token / 槽位=pgnfw_visible_fixture@3' "$test_dir/view-$platform"
        if ! { : < /dev/tty; } 2>/dev/null; then
            reader=official_read_secret_prompt
            [[ "$platform" != macos ]] || reader=po0_firewall_read_secret_prompt
            entered="$("$reader" 'Fixture input: ' <<< $'pgnfw_a@0 pgnfw_b@1\npgnfw_c@4\n' 2> "$test_dir/prompt-$platform")"
            [[ "$entered" == $'pgnfw_a@0 pgnfw_b@1\npgnfw_c@4' ]]
        fi
        # Stub the terminal reader only; exercise the real edit/validate/save path.
        official_read_secret_prompt() { printf '%s' "$fixture_input"; }
        po0_firewall_read_secret_prompt() { printf '%s' "$fixture_input"; }
        fixture_input=$'pgnfw_a@0 pgnfw_b@1\npgnfw_c@4；pgnfw_d,'
        configure_official_interactive > "$test_dir/edit-$platform"
        [[ "$PO0_FIREWALL_TOKENS" == 'pgnfw_a@0,pgnfw_b@1,pgnfw_c@4,pgnfw_d' ]]
        grep -Fq '当前官方 Token=pgnfw_visible_fixture@3' "$test_dir/edit-$platform"
        [[ "$(cat "$CONFIG_FILE")" == "$PO0_FIREWALL_TOKENS" ]]
        fixture_input='bad-token'
        if configure_official_interactive > /dev/null 2>&1; then exit 1; fi
        [[ "$PO0_FIREWALL_TOKENS" == 'pgnfw_a@0,pgnfw_b@1,pgnfw_c@4,pgnfw_d' ]]
        fixture_input=''
        configure_official_interactive > /dev/null
        [[ "$PO0_FIREWALL_TOKENS" == 'pgnfw_a@0,pgnfw_b@1,pgnfw_c@4,pgnfw_d' ]]
        fixture_input='-'
        configure_official_interactive > /dev/null
        [[ -z "$PO0_FIREWALL_TOKENS" && -z "$(cat "$CONFIG_FILE")" ]]
        # Real persistence and account-label identity, independent of UI input stubs.
        PO0_FIREWALL_TOKENS='pgnfw_second@2,pgnfw_first@0'
        PO0_FIREWALL_NAMES='First office;家庭'
        sync_official_account_names 'pgnfw_first,pgnfw_second'
        [[ "$PO0_FIREWALL_NAMES" == '家庭;First office' ]]
        WORKER_URL='https://worker.invalid/report'
        WORKER_NAME='家用接收端'
        WORKER_AUTO_ENABLED=0
        OFFICIAL_AUTO_ENABLED=1
        real_save_config_file > /dev/null
        WORKER_AUTO_ENABLED=1
        OFFICIAL_AUTO_ENABLED=0
        WORKER_NAME=''
        . "$CONFIG_FILE"
        [[ "$OFFICIAL_AUTO_ENABLED" == 1 ]]
        ! grep -Eq "^(WORKER_|SECRET=)" "$CONFIG_FILE"
        # The new periodic editor keeps stored intervals and updates only existing tasks.
        schedule_updates=''
        update_channel_schedule_if_installed() { schedule_updates="$schedule_updates $1"; }
        prompt_yes_no() { return 1; }
        prompt_default() { printf '%s' "$2"; }
        OFFICIAL_INTERVAL_SECONDS=900
        OFFICIAL_TIMER_ENABLED=1
        WORKER_TIMER_ENABLED=1
        CRON_MINUTES=90
        configure_channel_periodic_interactive official > /dev/null
        [[ "$OFFICIAL_INTERVAL_SECONDS" == 900 && "$OFFICIAL_TIMER_ENABLED" == 0 && "$CRON_MINUTES" == 90 && "$WORKER_TIMER_ENABLED" == 1 ]]
        [[ "$schedule_updates" == ' official' && "$(channel_interval_label official)" == *暂不使用* ]]
        prompt_yes_no() { return 0; }
        configure_channel_periodic_interactive official > /dev/null
        [[ "$OFFICIAL_TIMER_ENABLED" == 1 ]]
        prompt_yes_no() { return 0; }
        save_config_file() { real_save_config_file; }
        SECRET='worker-fixture'
        clear_official_tokens_interactive > /dev/null
        [[ -z "$PO0_FIREWALL_TOKENS" && -z "$PO0_FIREWALL_NAMES" && "$OFFICIAL_AUTO_ENABLED" == 0 && "$SECRET" == worker-fixture ]]
        # Manual reports must be visible in the selected channel's recent results.
        PO0_FIREWALL_TOKENS='pgnfw_recent_fixture@1'
        self_report_log_path() { printf '%s/report.log' "$test_dir"; }
        run_once_interactive() { printf 'manual-%s-result\n' "$REPORT_MODE"; }
        run_channel_interactive official > /dev/null
        grep -Fq 'manual-official-result' "$(schedule_channel_log_path official)"
        [[ ! -e "$(schedule_channel_log_path worker)" ]]
        for brand in 'PO0 防火墙' 'PO0 Outbound IP Report'; do
            [[ "$(self_report_log_event_summary "$brand 已完成：检查完成")" == '成功：检查完成' ]]
            [[ "$(self_report_log_event_summary "$brand 未完成：网络失败")" == '失败：网络失败' ]]
            [[ "$(self_report_log_event_summary "$brand 已完成：已跳过：Wi-Fi")" == '跳过：Wi-Fi' ]]
        done
        # Read each menu through the actual dispatcher without installing or reporting.
        recent_views=0 recent_logs=0 recent_pauses=0
        po0_display_cached() { [[ "${1:-}" == summary ]] || recent_views=$((recent_views+1)); }
        show_recent_self_report_log() { [[ "$1" == "$(schedule_channel_log_path official)" ]]; recent_logs=$((recent_logs+1)); }
        pause_before_return() { recent_pauses=$((recent_pauses+1)); }
        official_direct_request() { exit 99; }
        po0_firewall_direct_request() { exit 99; }
        # Visit account, automatic-report and maintenance submenus, then recent results.
        printf '4\n0\n5\n0\n8\n0\n3\n0\n' > "$test_dir/menu-input"

        exec 9< "$test_dir/menu-input"
        read_prompt() { local line; printf '%s
' "$1" >> "$test_dir/prompts-$platform"; IFS= read -r line <&9 || return 1; printf '%s' "$line"; }
        menu_clear_screen() { :; }
        cron_status_summary() { printf '未安装'; }
        menu_loop > "$test_dir/menu-$platform"
        exec 9<&-
        [[ "$recent_views" == 1 && "$recent_logs" == 1 && "$recent_pauses" == 1 ]]
        grep -Fq '[3]  最近上报结果' "$test_dir/menu-$platform"
        grep -Fxq '请选择 [0-8]: ' "$test_dir/prompts-$platform"
        grep -Fxq '请选择 [0-3]: ' "$test_dir/prompts-$platform"
        grep -Fxq '请选择 [0-5]: ' "$test_dir/prompts-$platform"
        grep -Fq 'PO0 防火墙' "$test_dir/menu-$platform"
        grep -Fq '编辑 Token 与槽位' "$test_dir/menu-$platform"
        grep -Fq '清除官方账号' "$test_dir/menu-$platform"
        grep -Fq '删除计划任务' "$test_dir/menu-$platform"
        grep -Fq '迁移旧版自建配置与任务' "$test_dir/menu-$platform"
        grep -Fq '维护与诊断' "$test_dir/menu-$platform"
        # Each action is reachable once: no report/query/force entries inside settings.
        [[ "$(grep -c '立即上报' "$test_dir/menu-$platform")" == "$(grep -c '\[1\]  立即上报' "$test_dir/menu-$platform")" ]]
        [[ "$(grep -c '查看本机配置' "$test_dir/menu-$platform")" == "$(grep -c '\[7\]  查看本机配置' "$test_dir/menu-$platform")" ]]
        ! grep -Eq '强制上报|本通道|查看最近结果' "$test_dir/menu-$platform"
        menu_actions=''
        run_channel_interactive() { menu_actions="$menu_actions report"; }
        show_channel_status() { menu_actions="$menu_actions query"; }
        configure_common_interactive() { menu_actions="$menu_actions network"; }
        show_current_config() { menu_actions="$menu_actions config"; }
        printf '1\n2\n6\n7\n9\n0\n' > "$test_dir/actions-input"
        exec 9< "$test_dir/actions-input"
        menu_loop > "$test_dir/actions-menu-$platform"
        exec 9<&-
        [[ "$menu_actions" == ' report query network config' ]]
        grep -Fq '无效选择：请输入 0-8。' "$test_dir/actions-menu-$platform"
        schedule_actions=''
        install_cron_interactive() { schedule_actions="$schedule_actions install"; }
        toggle_schedule_interactive() { schedule_actions="$schedule_actions toggle"; }
        configure_channel_periodic_interactive() { schedule_actions="$schedule_actions periodic"; }
        show_cron_status() { schedule_actions="$schedule_actions status"; }
        update_channel_schedule_if_installed() { schedule_actions="$schedule_actions refresh"; }
        printf '1\n2\n3\n4\n6\n0\n' > "$test_dir/schedule-input"
        exec 9< "$test_dir/schedule-input"
        automatic_reporting_menu > "$test_dir/schedule-menu-$platform"
        exec 9<&-
        # Pausing refreshes tasks itself; the menu must not add a second refresh.
        [[ "$schedule_actions" == ' install toggle periodic status' ]]
        grep -Fq '无效选择：请输入 0-5。' "$test_dir/schedule-menu-$platform"
        account_actions=''
        configure_official_interactive() { account_actions="$account_actions edit"; }
        set_channel_names_interactive() { account_actions="$account_actions names"; }
        clear_official_tokens_interactive() { account_actions="$account_actions clear"; }
        update_channel_schedule_if_installed() { account_actions="$account_actions refresh"; }
        printf '1\n2\n3\n0\n' > "$test_dir/account-input"
        exec 9< "$test_dir/account-input"
        official_account_menu > "$test_dir/account-menu-$platform"
        exec 9<&-
        [[ "$account_actions" == ' edit refresh names clear refresh' ]]
        maintenance_actions=''
        upgrade_self_from_download() { maintenance_actions="$maintenance_actions upgrade"; }
        migrate_retired_state() { maintenance_actions="$maintenance_actions migrate"; }
        uninstall_self_report_interactive() { maintenance_actions="$maintenance_actions uninstall"; }
        printf '1\n2\n3\n' > "$test_dir/maintenance-input"
        exec 9< "$test_dir/maintenance-input"
        client_maintenance_menu > "$test_dir/maintenance-menu-$platform"
        exec 9<&-
        # A completed uninstall leaves the maintenance menu and tells the main menu to exit.
        [[ "$maintenance_actions" == ' upgrade migrate uninstall' && "$CLIENT_MENU_UNINSTALLED" == 1 ]]
        if [[ "$platform" == macos ]]; then
            grep -Fq '[5]  删除定位权限 Helper' "$test_dir/maintenance-menu-$platform"
            [[ "$(tail -n 1 "$test_dir/prompts-$platform")" == '请选择 [0-5]: ' ]]
        else
            ! grep -Fq 'Wi-Fi SSID 权限诊断' "$test_dir/maintenance-menu-$platform"
            [[ "$(tail -n 1 "$test_dir/prompts-$platform")" == '请选择 [0-3]: ' ]]
        fi

        printf 'PASS: %s local settings visibility, multiline save, invalid input retention and clear\n' "$platform"
    )
done
