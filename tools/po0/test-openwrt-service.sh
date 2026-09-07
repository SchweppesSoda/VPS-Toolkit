#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
mkdir -p "$repo_root/.tmp"
work="$(mktemp -d "$repo_root/.tmp/po0-openwrt-service.XXXXXX")"
trap 'rm -rf "$work"' EXIT
src="$repo_root/packaging/openwrt/po0-outbound-ip-report/files"
mkdir -p "$work/bin"
base="$work/result"
cp "$src/usr/libexec/po0-outbound-ip-report-service" "$work/service"
sed -i -e "s|^BASE=.*|BASE='$base'|" -e "s|^UCI_RUNNER=.*|UCI_RUNNER='$work/runner'|" "$work/service"
cat > "$work/bin/uci" <<'MOCK'
#!/bin/sh
case "$*" in
 *main.enabled) printf '%s' "${TOTAL:-1}" ;;
 *main.worker_enabled) printf '%s' "${WORKER:-1}" ;;
 *main.official_enabled) printf '%s' "${OFFICIAL:-1}" ;;
 *main.interval_seconds) printf '%s' "${WORKER_INTERVAL:-3600}" ;;
 *main.official_interval_seconds) printf '%s' "${OFFICIAL_INTERVAL:-600}" ;;
 *main.worker_timer_enabled) printf '%s' "${WORKER_TIMER:-1}" ;;
 *main.official_timer_enabled) printf '%s' "${OFFICIAL_TIMER:-1}" ;;
 *main.worker_network_enabled) printf '%s' "${WORKER_NETWORK:-1}" ;;
 *main.official_network_enabled) printf '%s' "${OFFICIAL_NETWORK:-1}" ;;
 *) exit 1 ;;
esac
MOCK
cat > "$work/bin/date" <<'MOCK'
#!/bin/sh
printf '%s' "${NOW:-100}"
MOCK
cat > "$work/bin/sleep" <<'MOCK'
#!/bin/sh
printf '%s\n' "$1" >> "$WORK/sleep.log"
# Stop at the first wait: no wall-clock sleeps, sockets, or endless loops.
kill -TERM "$PPID"
MOCK
cat > "$work/runner" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> "$WORK/calls"
exit "${RUN_RC:-0}"
MOCK
chmod +x "$work/bin/"* "$work/runner"
export WORK="$work" PATH="$work/bin:$PATH"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
run() {
 : > "$work/calls"; : > "$work/sleep.log"
 sh "$work/service" "$@" > "$work/out" 2> "$work/err" && rc=0 || rc=$?
 [[ "$rc" == 0 || "$rc" == 143 || "$rc" == 7 ]] || { cat "$work/err"; fail "unexpected exit $rc"; }
}
wait_is() { [[ "$(head -n1 "$work/sleep.log")" == "$1" ]] || fail "wrong delay; expected $1"; }
called() { grep -Fqx -- "$1" "$work/calls" || fail "missing call $1"; }
not_called() { [[ ! -s "$work/calls" ]] || fail 'unexpected report'; }

run official
called '--official-only --timer-trigger'; wait_is 600
[[ "$(wc -l < "$work/calls")" == 1 ]] || fail 'official timer ran Worker'
OFFICIAL_INTERVAL=900 NOW=700 run official
not_called; wait_is 300
OFFICIAL_INTERVAL=900 NOW=1000 run official
called '--official-only --timer-trigger'; wait_is 900
WORKER_INTERVAL=60 run worker
called '--worker-only --timer-trigger'; wait_is 60
NOW=200 WORKER_INTERVAL=600 run worker
not_called; wait_is 500
# Independent timer deadlines survive an event, even with periodic reporting off.
old_timer="$(cat "$base.official.timer.state")"
NOW=1050 OFFICIAL_INTERVAL=0 run official network wan2
called '--official-only --network-changed --official-wan wan2'
grep -Fqx 'trigger=network' "$base.official.state" || fail 'event result was not recorded'
[[ "$(cat "$base.official.timer.state")" == "$old_timer" ]] || fail 'event moved timer deadline'
NOW=1100 OFFICIAL_INTERVAL=900 run official
not_called; wait_is 800
NOW=1100 OFFICIAL_INTERVAL=0 run official
not_called; [[ ! -s "$work/sleep.log" ]] || fail 'disabled timer stayed alive'
NOW=1100 WORKER_INTERVAL=0 run worker network
called '--worker-only --network-changed'
WORKER=0 run worker network
not_called
OFFICIAL=0 run official network
not_called
OFFICIAL_NETWORK=0 run official network
not_called
TOTAL=0 run worker network
not_called
TOTAL=0 run official
not_called
# Busy runs neither consume a due timer nor replace the latest useful result.
old_state="$(cat "$base.official.state")"
NOW=2000 RUN_RC=75 run official
wait_is 3
[[ "$(cat "$base.official.state")" == "$old_state" ]] || fail 'busy run replaced latest result'
[[ "$(cat "$base.official.timer.state")" == "$old_timer" ]] || fail 'busy run consumed timer'
NOW=2000 RUN_RC=7 run official
wait_is 600
grep -Fqx 'exit_code=7' "$base.official.state" || fail 'failure was not recorded'
# Upgrade seeding retains old completion/attempt semantics and paused settings.
rm -f "$base.worker.timer.state"
printf 'observed_at=100\nfinished_at=600\n' > "$base.worker.state"
NOW=700 WORKER_INTERVAL=600 run worker
not_called; wait_is 500

# An event during upgrade must not erase the legacy timer timestamp.
rm -f "$base.worker.timer.state"
NOW=750 WORKER_INTERVAL=0 run worker network
called '--worker-only --network-changed'
NOW=800 WORKER_INTERVAL=600 run worker
not_called; wait_is 400
WORKER_INTERVAL=000 run worker
not_called; [[ ! -s "$work/sleep.log" ]] || fail 'zero with leading digits enabled timer'

# Mock procd to check actual instance commands on start/reload.
cp "$src/etc/init.d/po0-outbound-ip-report" "$work/init"
touch "$work/config"
sed -i "s|^CONFIG_FILE=.*|CONFIG_FILE='$work/config'|" "$work/init"
cat > "$work/start" <<'MOCK'
#!/bin/sh
procd_open_instance() { printf 'instance=%s\n' "$1"; }
procd_set_param() { printf '%s\n' "$*"; }
procd_close_instance() { :; }
. "$WORK/init"
start_service
MOCK
sh "$work/start" > "$work/procd"
grep -Fqx 'instance=worker' "$work/procd" || fail 'Worker instance missing'
grep -Fqx 'instance=official' "$work/procd" || fail 'official instance missing'
grep -Fqx 'command /usr/libexec/po0-outbound-ip-report-service worker' "$work/procd" || fail 'Worker command not isolated'
grep -Fqx 'command /usr/libexec/po0-outbound-ip-report-service official' "$work/procd" || fail 'official command not isolated'
OFFICIAL_INTERVAL=0 sh "$work/start" > "$work/procd"
! grep -Fqx 'instance=official' "$work/procd" || fail 'zero timer registered in procd'
grep -Fqx 'instance=worker' "$work/procd" || fail 'zero official timer removed Worker'
WORKER=0 sh "$work/start" > "$work/procd"
! grep -Fqx 'instance=worker' "$work/procd" || fail 'paused Worker registered'
grep -Fqx 'instance=official' "$work/procd" || fail 'pausing Worker removed official'
TOTAL=0 sh "$work/start" > "$work/procd"
[[ ! -s "$work/procd" ]] || fail 'total switch ignored'
# Explicit timer switches preserve positive intervals and independent network events.
OFFICIAL_TIMER=0 run official
not_called; [[ ! -s "$work/sleep.log" ]] || fail 'explicit official timer switch ignored'
WORKER_TIMER=0 run worker
not_called; [[ ! -s "$work/sleep.log" ]] || fail 'explicit Worker timer switch ignored'
OFFICIAL_TIMER=0 run official network wan1
called '--official-only --network-changed --official-wan wan1'
WORKER_TIMER=0 run worker network
called '--worker-only --network-changed'
WORKER=0 NOW=9999 run official
called '--official-only --timer-trigger'
OFFICIAL_TIMER=0 sh "$work/start" > "$work/procd"
! grep -Fqx 'instance=official' "$work/procd" || fail 'explicit timer switch registered official instance'
grep -Fqx 'instance=worker' "$work/procd" || fail 'official timer switch removed Worker'
printf 'PASS: OpenWrt independent instances, optional timers, events, and migration.\n'
