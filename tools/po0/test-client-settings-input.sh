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
        grep -Fq '上报密钥=worker-visible-fixture' "$test_dir/view-$platform"
        grep -Fq '官方 Token=pgnfw_visible_fixture@3' "$test_dir/view-$platform"
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
        [[ "$WORKER_AUTO_ENABLED" == 0 && "$OFFICIAL_AUTO_ENABLED" == 1 && "$WORKER_NAME" == '家用接收端' ]]
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
        configure_channel_periodic_interactive worker > /dev/null
        [[ "$CRON_MINUTES" == 90 && "$WORKER_TIMER_ENABLED" == 0 && "$OFFICIAL_INTERVAL_SECONDS" == 900 && "$OFFICIAL_TIMER_ENABLED" == 0 ]]
        prompt_yes_no() { return 0; }
        configure_channel_periodic_interactive official > /dev/null
        [[ "$OFFICIAL_TIMER_ENABLED" == 1 && "$WORKER_TIMER_ENABLED" == 0 ]]
        prompt_yes_no() { return 0; }
        save_config_file() { real_save_config_file; }
        clear_worker_config_interactive > /dev/null
        [[ -z "$WORKER_URL" && -z "$SECRET" && -z "$WORKER_NAME" ]]
        [[ "$PO0_FIREWALL_TOKENS" == 'pgnfw_second@2,pgnfw_first@0' && "$PO0_FIREWALL_NAMES" == '家庭;First office' ]]
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
        # Read each menu through the actual dispatcher without installing or reporting.
        printf '1\n0\n2\n0\n5\n0\n7\n0\n0\n' > "$test_dir/menu-input"
        exec 9< "$test_dir/menu-input"
        read_prompt() { local line; IFS= read -r line <&9 || return 1; printf '%s' "$line"; }
        menu_clear_screen() { :; }
        cron_status_summary() { printf '未安装'; }
        menu_loop > "$test_dir/menu-$platform"
        exec 9<&-
        grep -Fq '保存配置（编辑参数）' "$test_dir/menu-$platform"
        grep -Fq '清除本通道配置' "$test_dir/menu-$platform"
        grep -Fq '维护与诊断' "$test_dir/menu-$platform"
        printf 'PASS: %s local settings visibility, multiline save, invalid input retention and clear\n' "$platform"
    )
done
