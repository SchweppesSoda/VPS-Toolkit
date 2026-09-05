#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
service_src="$repo_root/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-service"
fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

[ -s "$service_src" ] || {
	printf 'FAIL: OpenWrt service is missing.\n' >&2
	exit 1
}

tmp_dir="$(mktemp -d "$repo_root/.tmp/po0-openwrt-service.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM
bin_dir="$tmp_dir/bin"
base="$tmp_dir/runtime"
service="$tmp_dir/service"
runner="$tmp_dir/runner"
runner_log="$tmp_dir/runner.log"
sleep_log="$tmp_dir/sleep.log"
real_sleep="$(command -v sleep)"
mkdir -p "$bin_dir"
cp "$service_src" "$service"

sed -i \
	-e "s|^BASE=.*|BASE='$base'|" \
	-e "s|^UCI_RUNNER=.*|UCI_RUNNER='$runner'|" \
	"$service"

cat > "$bin_dir/uci" <<'EOF'
#!/bin/sh
set -eu
while [ "$#" -gt 0 ] && [ "$1" = '-q' ]; do
	shift
done
[ "$1" = 'get' ] || exit 1
case "$2" in
	po0_outbound_ip_report.main.enabled) printf '%s\n' "${PO0_TEST_OVERALL_ENABLED:-1}" ;;
	po0_outbound_ip_report.main.worker_enabled) printf '%s\n' "${PO0_TEST_WORKER_ENABLED:-0}" ;;
	po0_outbound_ip_report.main.official_enabled) printf '%s\n' "${PO0_TEST_OFFICIAL_ENABLED:-1}" ;;
	po0_outbound_ip_report.main.interval_seconds) printf '%s\n' "${PO0_TEST_INTERVAL_SECONDS:-3600}" ;;
	*) exit 1 ;;
esac
EOF

cat > "$bin_dir/date" <<'EOF'
#!/bin/sh
printf '%s\n' "${PO0_TEST_NOW:-100}"
EOF

cat > "$runner" <<'EOF'
#!/bin/sh
set -eu
case "${1:-}" in
	--official-only) printf 'official\n' >> "$PO0_TEST_RUNNER_LOG" ;;
	--worker-only) printf 'worker\n' >> "$PO0_TEST_RUNNER_LOG" ;;
	*) printf 'unknown\n' >> "$PO0_TEST_RUNNER_LOG" ;;
esac
exit "${PO0_TEST_RUNNER_RC:-0}"
EOF

chmod 0700 "$bin_dir/uci" "$bin_dir/date" "$runner" "$service"
: > "$runner_log"
cat > "$bin_dir/sleep" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "${1:-}" >> "$PO0_TEST_SLEEP_LOG"
"$PO0_TEST_REAL_SLEEP" 1
EOF
chmod 0700 "$bin_dir/sleep"

run_service() {
	set +e
	# Git Bash on Windows can spend several seconds starting the shell and its
	# command substitutions. Keep this bounded, but leave enough room for the
	# service to reach its first mocked sleep on that platform.
	env \
		"PATH=$bin_dir:$PATH" \
		"PO0_TEST_RUNNER_LOG=$runner_log" \
		"PO0_TEST_RUNNER_RC=${PO0_TEST_RUNNER_RC:-0}" \
		"PO0_TEST_SLEEP_LOG=$sleep_log" \
		"PO0_TEST_REAL_SLEEP=$real_sleep" \
		"PO0_TEST_NOW=${PO0_TEST_NOW:-100}" \
		"PO0_TEST_OVERALL_ENABLED=${PO0_TEST_OVERALL_ENABLED:-1}" \
		"PO0_TEST_OFFICIAL_ENABLED=${PO0_TEST_OFFICIAL_ENABLED:-1}" \
		"PO0_TEST_WORKER_ENABLED=${PO0_TEST_WORKER_ENABLED:-0}" \
		"PO0_TEST_INTERVAL_SECONDS=${PO0_TEST_INTERVAL_SECONDS:-3600}" \
		timeout 10s sh "$service" > "$tmp_dir/stdout" 2> "$tmp_dir/stderr"
	run_rc=$?
	set -e
}

assert_first_sleep() {
	expected="$1"
	actual="$(sed -n '1p' "$sleep_log")"
	[ "$actual" = "$expected" ] ||
		fail "expected next wakeup ${expected}s, got ${actual:-none}s"
}

# With only the official lane enabled, its first attempt is due and the next
# wakeup is the fixed 600-second official interval. The Worker remains idle.
rm -f "$base.official.state" "$base.worker.state"
: > "$runner_log"
: > "$sleep_log"
run_service
grep -Fqx 'official' "$runner_log" ||
	fail 'initial official lane was not due'
if grep -Fq 'worker' "$runner_log"; then
	fail 'disabled Worker lane unexpectedly ran'
fi
assert_first_sleep 600
grep -Fqx 'observed_at=100' "$base.official.state" ||
	fail 'official state did not retain the attempt start timestamp'
grep -Fqx 'finished_at=100' "$base.official.state" ||
	fail 'official state did not record completion'

# A shorter Worker interval wins the next-wakeup calculation, while official
# still runs first and keeps its independent 600-second due clock.
rm -f "$base.official.state" "$base.worker.state"
: > "$runner_log"
: > "$sleep_log"
PO0_TEST_WORKER_ENABLED=1 PO0_TEST_INTERVAL_SECONDS=60 run_service
grep -Fqx 'official' "$runner_log" || fail 'official lane did not run before Worker'
grep -Fqx 'worker' "$runner_log" || fail 'enabled Worker lane did not run'
first_runner="$(sed -n '1p' "$runner_log")"
[ "$first_runner" = 'official' ] || fail 'official lane did not run first'
assert_first_sleep 60

# Failure still records the attempt start and waits a full official interval;
# using finished_at would make a slow request shift this deadline.
rm -f "$base.official.state" "$base.worker.state"
: > "$runner_log"
: > "$sleep_log"
PO0_TEST_RUNNER_RC=7 run_service
grep -Fqx 'official' "$runner_log" || fail 'failed official lane was not attempted'
grep -Fqx 'exit_code=7' "$base.official.state" || fail 'official failure code was not saved'
grep -Fqx 'observed_at=100' "$base.official.state" || fail 'failed official attempt timestamp was not saved'
assert_first_sleep 600

# At now=700, observed_at=100 is due for the official 600-second lane while
# finished_at=600 is not. This locks the official scheduler to attempt time.
printf 'observed_at=100\nfinished_at=600\n' > "$base.official.state"
: > "$runner_log"
: > "$sleep_log"
PO0_TEST_NOW=700 run_service
grep -Fqx 'official' "$runner_log" ||
	fail 'official due incorrectly used finished_at'
assert_first_sleep 600

# Worker scheduling retains its existing completion-time semantics. With a
# 600-second interval, observed_at=100 is due at now=700 but finished_at=600
# is not, so no Worker run is allowed.
rm -f "$base.official.state"
printf 'observed_at=100\nfinished_at=600\n' > "$base.worker.state"
: > "$runner_log"
: > "$sleep_log"
PO0_TEST_NOW=700 \
	PO0_TEST_OVERALL_ENABLED=1 \
	PO0_TEST_OFFICIAL_ENABLED=0 \
	PO0_TEST_WORKER_ENABLED=1 \
	PO0_TEST_INTERVAL_SECONDS=600 \
	run_service
[ ! -s "$runner_log" ] || fail 'Worker due incorrectly used observed_at'
assert_first_sleep 500

# The total switch belongs to automatic service execution: disabled procd
# exits immediately without invoking either lane or sleeping.
rm -f "$base.official.state" "$base.worker.state"
: > "$runner_log"
: > "$sleep_log"
PO0_TEST_OVERALL_ENABLED=0 run_service
[ ! -s "$runner_log" ] || fail 'disabled automatic service ran a lane'
[ ! -s "$sleep_log" ] || fail 'disabled automatic service slept instead of exiting'

if grep -Eq '^[[:space:]]*sleep[[:space:]]+15([[:space:]]|$)' "$service"; then
	fail 'service still uses fixed 15-second sleep'
fi

printf 'PASS: OpenWrt service due scheduling and lane-order checks passed.\n'
