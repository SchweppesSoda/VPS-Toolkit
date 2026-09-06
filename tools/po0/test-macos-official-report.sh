#!/usr/bin/env bash
set -euo pipefail
export REPORT_LOCK_WAIT_SECONDS=0

repo_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
src_root="$repo_root/scripts/po0/relay/self-report/macos/src"
mkdir -p "$repo_root/.tmp"
tmp_dir="$(mktemp -d "$repo_root/.tmp/po0-macos-official.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

bin_dir="$tmp_dir/bin"
state_dir="$tmp_dir/state"
home_dir="$tmp_dir/home"
temp_dir="$tmp_dir/tmp"
config_home="$tmp_dir/config-home"
curl_log="$tmp_dir/curl.log"
curl_argv_log="$tmp_dir/curl.argv.log"
order_log="$tmp_dir/order.log"
mkdir -p "$bin_dir" "$state_dir" "$home_dir" "$temp_dir" "$config_home"
export HOME="$home_dir" TMPDIR="$temp_dir" XDG_STATE_HOME="$state_dir" XDG_CONFIG_HOME="$config_home"
: > "$curl_log"
: > "$curl_argv_log"
: > "$order_log"

printf '%s\n' '#!/bin/sh' \
    'set -eu' \
    'config="$(sed -n "1,\$p")"' \
    'request="$(printf "%s\n" "$config" | sed -n "s/^request = \"\(.*\)\"$/\1/p")"' \
    'url="$(printf "%s\n" "$config" | sed -n "s/^url = \"\(.*\)\"$/\1/p")"' \
    'printf "%s\n" "$request" >> "$PO0_TEST_CURL_LOG"' \
    'printf "argv:%s\n" "$*" >> "$PO0_TEST_CURL_ARGV_LOG"' \
    'output_file=""' \
    'header_file=""' \
    'while [ "$#" -gt 0 ]; do case "$1" in --output) output_file="$2"; shift 2 ;; --dump-header) header_file="$2"; shift 2 ;; *) shift ;; esac; done' \
    'case "$PO0_TEST_SCENARIO:$request:$url" in' \
    'bad-enabled:GET:*) body='\''{"enabled":false,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[]}'\'' ;;' \
    'bad-limit:GET:*) body='\''{"enabled":true,"currentIp":"203.0.113.10/24","limit":6,"whitelist":[]}'\'' ;;' \
    'bad-whitelist:GET:*) body='\''{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[{"ip":"999.1.1.1/24","slot":9}]}'\'' ;;' \
    'normal:GET:*pgnfw_alpha*) body='\''{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[{"slot":0,"ip":"203.0.113.10/24"}]}'\'' ;;' \
    'normal:GET:*pgnfw_beta*) body='\''{"enabled":true,"currentIp":"198.51.100.20/24","limit":5,"whitelist":[{"slot":1,"ip":"192.0.2.1/24"}]}'\'' ;;' \
    'normal:POST:*pgnfw_beta*) body='\''{"enabled":true,"currentIp":"198.51.100.20/24","limit":5,"whitelist":[{"ip":"198.51.100.20/24","slot":1}]}'\'' ;;' \
    'normal:POST:*) body='\''{"enabled":true,"currentIp":"198.51.100.20/24","limit":5,"whitelist":[{"ip":"198.51.100.20/24","slot":1}]}'\'' ;;' \
    'normal:GET:*) body='\''{"enabled":true,"currentIp":"198.51.100.20/24","limit":5,"whitelist":[{"slot":1,"ip":"192.0.2.1/24"}]}'\'' ;;' \
    '*) exit 2 ;;' \
    'esac' \
    'printf "%s" "$body" > "$output_file"' \
    'printf "HTTP/1.1 200 OK\nContent-Length: %s\n\n" "$(wc -c < "$output_file")" > "$header_file"' \
    'printf "200"' > "$bin_dir/curl"
chmod 700 "$bin_dir/curl"

PATH="$bin_dir:$PATH"
export PATH PO0_TEST_CURL_LOG="$curl_log" PO0_TEST_CURL_ARGV_LOG="$curl_argv_log"
. "$src_root/010-core-string-path-config.sh"
. "$src_root/040-prompt-and-input-helpers.sh"
. "$src_root/060-worker-url-interval-state.sh"
. "$src_root/075-wifi-ssid-skip.sh"
. "$src_root/076-channel-settings.sh"
. "$src_root/078-official-firewall.sh"
. "$src_root/050-config-device-defaults.sh"

# Git Bash on Windows cannot expose POSIX directory modes on NTFS-backed
# paths. Keep the production secure-directory check unchanged; mock only that
# platform limitation so the fixture can exercise the state/lock flow here.
case "$(uname -s 2>/dev/null || printf unknown)" in
    MINGW*|MSYS*|CYGWIN*)
        po0_firewall_secure_state_dir() {
            local dir="${1:-}" owner current_uid
            case "$dir" in
                ""|/|.|/tmp|/var/tmp) return 1 ;;
            esac
            [[ "$dir" != *$'\n'* && "$dir" != *$'\r'* && ! -L "$dir" ]] || return 1
            mkdir -p "$dir" 2>/dev/null || return 1
            [[ -d "$dir" && ! -L "$dir" ]] || return 1
            owner="$(stat -c '%u' "$dir" 2>/dev/null || true)"
            current_uid="$(id -u 2>/dev/null || true)"
            [[ "$owner" =~ ^[0-9]+$ && "$current_uid" =~ ^[0-9]+$ && "$owner" == "$current_uid" ]]
        }
        ;;
esac

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}
assert_eq() {
    [[ "$1" == "$2" ]] || fail "$3 (expected [$2], got [$1])"
}
assert_file_has() {
    grep -Fq -- "$1" "$2" || fail "missing [$1] in $2"
}
assert_no_file_text() {
    [[ -f "$2" ]] || fail "missing file for secrecy assertion: $2"
    if grep -Fq -- "$1" "$2"; then
        fail "secret text escaped into $2"
    fi
}
count_log() {
    grep -c "^$1$" "$curl_log" 2>/dev/null || true
}

export XDG_STATE_HOME="$state_dir"
PO0_FIREWALL_TOKENS=$' , pgnfw_alpha；\n\tpgnfw_beta@1, '
SCHEDULED_RUN="0"
FORCE_REPORT="0"
CRON_MINUTES="60"
PO0_TEST_SCENARIO="normal"
export PO0_TEST_SCENARIO

po0_firewall_validate_tokens || fail 'valid multi-token configuration rejected'
assert_eq "$(po0_firewall_token_count)" "2" 'token count'
[[ "$(po0_firewall_masked_tokens)" != *pgnfw_* ]] || fail 'masked token display leaked token'
assert_eq "$(po0_firewall_normalize_tokens $' pgnfw_a pgnfw_b;pgnfw_c，pgnfw_d；pgnfw_e\npgnfw_f, ')" 'pgnfw_a,pgnfw_b,pgnfw_c,pgnfw_d,pgnfw_e,pgnfw_f' 'mixed token separators'
for invalid_tokens in 'pgnfw_alpha,pgnfw_alpha' 'pgnfw_alpha@0,pgnfw_alpha@0' 'pgnfw_alpha@0,pgnfw_alpha@1' 'pgnfw_alpha,pgnfw_alpha@0'; do
    PO0_FIREWALL_TOKENS="${invalid_tokens}"
    if po0_firewall_validate_tokens >/dev/null 2>&1; then
        fail "invalid token list was accepted: ${invalid_tokens}"
    fi
done
PO0_FIREWALL_TOKENS='pgnfw_alpha,pgnfw_beta@1'
escaped_json='{"enabled":true,"currentIp":"203.0.113.10\/24","limit":5,"whitelist":[{"ip":"203.0.113.10\/24","slot":0}]}'
assert_eq "$(po0_firewall_json_current_ip "$escaped_json")" "203.0.113.10/24" 'escaped currentIp parser'
po0_firewall_json_validate_whitelist "$escaped_json" "5" || fail 'escaped whitelist parser'
po0_firewall_json_ip_entry "$escaped_json" "203.0.113.10/24" || fail 'escaped IP entry parser'
po0_firewall_json_ip_slot_entry "$escaped_json" "203.0.113.10/24" "0" || fail 'escaped slot parser'
null_slot_json='{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[{"ip":"203.0.113.10/24","slot":null}]}'
po0_firewall_json_validate_whitelist "$null_slot_json" "5" || fail 'null whitelist slot was rejected'
missing_slot_json='{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[{"ip":"203.0.113.10/24"}]}'
po0_firewall_json_validate_whitelist "$missing_slot_json" "5" || fail 'missing whitelist slot was rejected'
duplicate_slot_json='{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[{"ip":"203.0.113.10/24","slot":0},{"slot":0,"ip":"198.51.100.20/24"}]}'
if po0_firewall_json_validate_whitelist "$duplicate_slot_json" "5"; then fail 'duplicate numeric whitelist slot was accepted'; fi
empty_slot_json='{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[{"slot":"","ip":"203.0.113.10/24"}]}'
po0_firewall_json_validate_whitelist "$empty_slot_json" "5" || fail 'empty-string whitelist slot was rejected'
po0_firewall_json_ip_slot_entry "$empty_slot_json" "203.0.113.10/24" "" || fail 'empty-string whitelist slot was not treated as automatic'
for invalid_json in \
    '{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[{"ip":"203.0.113.10/24","slot":"0"}]}' \
    '{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[{"ip":"203.0.113.10/24","slot":true}]}' \
    '{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[{"ip":"203.0.113.10/24","slot":5}]}' \
    '{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[{"ip":"203.0.113.10/24","slot":0.1}]}' \
    '{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[{"ip":"203.0.113.10/24","slot":0e1}]}' \
    '{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[{"ip":"203.0.113.10/24","slot":0,"slot":1}]}' \
    '{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[{"ip":"203.0.113.10/24","slot":0,"nested":{"slot":1}}]}' \
    '{"enabled":true,"currentIp":{},"limit":5,"whitelist":[]}' \
    '{"enabled":true,"currentIp":"203.0.113.10/24","limit":"5","whitelist":[]}' \
    '{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[]}'garbage; do
    if po0_firewall_json_has_whitelist "$invalid_json"; then
        fail 'adversarial or wrong-type official JSON was accepted'
    fi
done
if po0_firewall_json_safe_ip "203.0.113.10"; then fail 'plain IPv4 accepted without /24'; fi
po0_firewall_json_safe_ip "203.0.113.010/24" || fail 'decimal IPv4 octet rejected'
self_report_completed() { :; }
CONFIG_FILE="$tmp_dir/config/settings.env"
CONFIG_FILE_EXPLICIT="1"
WORKER_URL=""
SOURCE_ID="source"
IDENTITY="device"
SECRET=""
ALLOW_HTTP=""
IP_CHECK_URL="https://ip9.com.cn/get"
IP_CHECK_URLS=""
INSTALL_PATH=""
CRON_MINUTES="60"
MAX_CRON_MINUTES="10080"
SCHEDULE_PAUSED="0"
NOTIFY="0"
SKIP_WIFI_SSIDS=""
PO0_FIREWALL_TOKENS='pgnfw_persist@2'
save_config_file >/dev/null || fail 'config save failed'
config_mode="$(stat -f '%Lp' "$CONFIG_FILE" 2>/dev/null || true)"
[[ "$config_mode" =~ ^[0-9]+$ ]] || config_mode="$(stat -c '%a' "$CONFIG_FILE")"
case "$(uname -s 2>/dev/null || printf unknown)" in
    Darwin|Linux*) assert_eq "$config_mode" "600" 'config file is not mode 600' ;;
    *) [[ "$config_mode" == "600" || "$config_mode" == "644" ]] || fail 'config file mode is unexpectedly permissive' ;;
esac
PO0_FIREWALL_TOKENS=""
load_saved_config || fail 'config reload failed'
assert_eq "$PO0_FIREWALL_TOKENS" "pgnfw_persist@2" 'saved token was not reloaded'
PO0_FIREWALL_TOKENS='pgnfw_alpha,pgnfw_beta@1'
po0_firewall_run report > "$tmp_dir/report.out" 2>&1 || fail 'report run failed'
assert_eq "$PO0_FIREWALL_SUCCESS_COUNT" "2" 'report success count'
assert_eq "$PO0_FIREWALL_FAILURE_COUNT" "0" 'report failure count'
assert_eq "$(count_log GET)" "2" 'GET count'
assert_eq "$(count_log POST)" "1" 'POST count'
assert_no_file_text 'pgnfw_alpha' "$tmp_dir/report.out"
assert_no_file_text 'pgnfw_beta' "$tmp_dir/report.out"
assert_no_file_text 'pgnfw_' "$curl_argv_log"
assert_no_file_text 'pgnfw_' "$curl_log"
for state_file in "$state_dir"/po0-outbound-ip-report/*; do
    [[ -f "$state_file" ]] && assert_no_file_text 'pgnfw_' "$state_file"
done
assert_file_has '槽位 2' "$tmp_dir/report.out"
assert_no_file_text '槽位 1' "$tmp_dir/report.out"

before_post="$(count_log POST)"
set +e
po0_firewall_run status > "$tmp_dir/status.out" 2>&1
status_rc="$?"
set -e
[[ "$status_rc" == "0" ]] || fail 'valid read-only status was treated as a failure'
assert_eq "$(count_log POST)" "$before_post" 'status performed POST'
assert_file_has '仅读不加白' "$tmp_dir/status.out"

# Status refreshes account details but leaves the independent due/attempt
# clocks untouched. Its summary converts internal zero-based slots to the
# user-facing 1..5/自动 labels.
printf 'last_attempt_at=900\nlast_success_at=800\nlast_status=success\n' > "$(po0_firewall_state_file)"
printf '900\n' > "$(po0_firewall_due_state_file)"
PO0_TEST_NOW="1000"
po0_firewall_run status > "$tmp_dir/status-refresh.out" 2>&1 || fail 'status refresh failed'
assert_file_has 'last_attempt_at=900' "$(po0_firewall_state_file)"
assert_file_has 'last_checked_at=1000' "$(po0_firewall_state_file)"
assert_eq "$(po0_firewall_read_timestamp "$(po0_firewall_due_state_file)")" "900" 'status changed due clock'
summary="$(po0_firewall_state_summary)"
[[ "$summary" == *'槽位 1'* ]] || fail 'state summary did not render slot 1'
[[ "$summary" == *'固定槽位=2'* ]] || fail 'state summary did not render configured slot as 2'
[[ "$summary" != *'@0'* && "$summary" != *'@1'* ]] || fail 'state summary exposed raw internal slot encoding'
unset PO0_TEST_NOW

for scenario in bad-enabled bad-limit bad-whitelist; do
    : > "$curl_log"
    PO0_FIREWALL_TOKENS='pgnfw_alpha'
    PO0_TEST_SCENARIO="$scenario"
    set +e
    po0_firewall_run report > "$tmp_dir/$scenario.out" 2>&1
    scenario_rc="$?"
    set -e
    [[ "$scenario_rc" -ne 0 ]] || fail "$scenario was accepted"
    [[ "$(count_log POST)" == "0" ]] || fail "$scenario reached POST"
done

: > "$curl_log"
PO0_FIREWALL_TOKENS='not-a-token'
set +e
po0_firewall_run report > "$tmp_dir/invalid.out" 2>&1
invalid_rc="$?"
set -e
[[ "$invalid_rc" -ne 0 ]] || fail 'invalid token was accepted'
[[ ! -s "$curl_log" ]] || fail 'invalid token reached network'

PO0_FIREWALL_TOKENS='pgnfw_alpha'
PO0_TEST_SCENARIO="normal"
SCHEDULED_RUN="1"
PO0_TEST_NOW="1000"
rm -f "$(po0_firewall_due_state_file)" "$(po0_worker_due_state_file)"
po0_firewall_due || fail 'official due was not initially due'
po0_firewall_mark_due || fail 'official due state write failed'
PO0_TEST_NOW="1001"
if po0_firewall_due; then fail 'official due ignored 600 second gate'; fi
PO0_TEST_NOW="1601"
po0_firewall_due || fail 'official due did not reopen after 600 seconds'
rm -f "$(po0_worker_due_state_file)"
PO0_TEST_NOW="1000"
WORKER_URL='https://worker.invalid/report'
po0_worker_due || fail 'worker due was not initially due'
po0_worker_mark_attempt || fail 'worker attempt state write failed'
PO0_TEST_NOW="1001"
if po0_worker_due; then fail 'worker due ignored one-hour gate'; fi
PO0_TEST_NOW="4601"
po0_worker_due || fail 'worker due did not reopen after one hour'
assert_eq "$(po0_reporter_wakeup_minutes)" "10" 'official wakeup interval'
CRON_MINUTES="5"
assert_eq "$(po0_reporter_wakeup_minutes)" "5" 'shorter configured wakeup interval'
SCHEDULED_RUN="0"

. "$src_root/150-report-submit.sh"
self_report_completed() { :; }
self_report_incomplete() { :; }
notify_report_success() { :; }
notify_report_failure() { :; }
wifi_ssid_skip_message() { printf 'SSID skipped\n'; }
po0_firewall_run() {
    printf 'official\n' >> "$order_log"
    PO0_FIREWALL_SUCCESS_COUNT="$PO0_TEST_OFFICIAL_SUCCESS"
    PO0_FIREWALL_FAILURE_COUNT="$PO0_TEST_OFFICIAL_FAILURE"
    return "$PO0_TEST_OFFICIAL_RC"
}
report_worker_once() {
    printf 'worker\n' >> "$order_log"
    return "$PO0_TEST_WORKER_RC"
}
should_skip_wifi_ssid_report() { return 1; }
PO0_FIREWALL_TOKENS='pgnfw_alpha'
WORKER_URL='https://worker.invalid/report'
OFFICIAL_ONLY="0"
WORKER_ONLY="0"
PO0_TEST_OFFICIAL_RC="0"
PO0_TEST_OFFICIAL_SUCCESS="1"
PO0_TEST_OFFICIAL_FAILURE="0"
PO0_TEST_WORKER_RC="0"
: > "$order_log"
report_once || fail 'combined report failed'
[[ "$(tr -d '\n' < "$order_log")" == "officialworker" ]] || fail 'official did not run before Worker'

# Automatic switches do not change credentials, manual actions or the shared SSID guard.
SCHEDULED_RUN=1
FORCE_REPORT=1
WORKER_AUTO_ENABLED=0
OFFICIAL_AUTO_ENABLED=1
: > "$order_log"
report_once || fail 'paused Worker should not fail official'
[[ "$(tr -d '\n' < "$order_log")" == official ]] || fail 'Worker automatic pause was ignored'
WORKER_AUTO_ENABLED=1
OFFICIAL_AUTO_ENABLED=0
: > "$order_log"
report_once || fail 'paused official should not fail Worker'
[[ "$(tr -d '\n' < "$order_log")" == worker ]] || fail 'official automatic pause was ignored'
WORKER_AUTO_ENABLED=0
: > "$order_log"
report_once || fail 'both paused should return quietly'
[[ ! -s "$order_log" ]] || fail 'both paused ran a lane'
SCHEDULED_RUN=0
: > "$order_log"
report_once || fail 'manual run should ignore automatic pause'
[[ "$(tr -d '\n' < "$order_log")" == officialworker ]] || fail 'manual run did not use both configured lanes'
WORKER_AUTO_ENABLED=1
OFFICIAL_AUTO_ENABLED=1
FORCE_REPORT=0

: > "$order_log"
OFFICIAL_ONLY="1"
report_once || fail 'official-only report failed'
[[ "$(tr -d '\n' < "$order_log")" == "official" ]] || fail 'official-only ran another channel'

: > "$order_log"
OFFICIAL_ONLY="0"
WORKER_ONLY="1"
report_once || fail 'worker-only report failed'
[[ "$(tr -d '\n' < "$order_log")" == "worker" ]] || fail 'worker-only ran another channel'

: > "$order_log"
WORKER_ONLY="0"
should_skip_wifi_ssid_report() { WIFI_SKIP_LAST_SSID='home'; return 0; }
report_once || fail 'SSID skip failed'
[[ ! -s "$order_log" ]] || fail 'SSID skip did not skip both channels'

: > "$order_log"
should_skip_wifi_ssid_report() { return 1; }
PO0_TEST_OFFICIAL_RC="1"
PO0_TEST_OFFICIAL_SUCCESS="1"
PO0_TEST_OFFICIAL_FAILURE="1"
set +e
report_once > "$tmp_dir/partial.out" 2>&1
partial_rc="$?"
set -e
[[ "$partial_rc" -ne 0 ]] || fail 'partial success did not report failure status'

# Status-only invocations use the same whole-run lock as manual/force/scheduled
# reporting; a live owner must prevent the status lane from entering.
lock_path="$(po0_firewall_report_lock_path)"
mkdir "$lock_path"
printf 'pid=%s\nstarted_at=1000\n' "$$" > "$lock_path/pid"
OFFICIAL_STATUS_ONLY="1"
: > "$order_log"
set +e
report_once > "$tmp_dir/status-busy.out" 2>&1
status_busy_rc="$?"
set -e
[[ "$status_busy_rc" -ne 0 ]] || fail 'status-only report ignored the whole-run lock'
[[ ! -s "$order_log" ]] || fail 'status-only report entered a lane while lock was held'
rm -f "$lock_path/pid"
rmdir "$lock_path"
OFFICIAL_STATUS_ONLY="0"

if grep -Eq -- '--(po0-firewall-tokens|firewall-tokens)([ =]|$)' "$src_root/990-cli-parse-dispatch.sh"; then
    fail 'token-value CLI option remains'
fi
assert_file_has --config "$src_root/078-official-firewall.sh"
assert_file_has --noproxy "$src_root/078-official-firewall.sh"
assert_file_has --tlsv1.2 "$src_root/078-official-firewall.sh"
if grep -Fq -- ' -k' "$src_root/078-official-firewall.sh"; then fail 'TLS verification was disabled'; fi

printf 'PASS: macOS official firewall dual-channel checks passed.\n'
