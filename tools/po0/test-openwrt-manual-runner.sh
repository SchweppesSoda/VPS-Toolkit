#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
runner="${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-manual-runner"
mkdir -p "${repo_root}/.tmp"
tmp_dir="$(mktemp -d "${repo_root}/.tmp/po0-manual-runner.XXXXXX")"
case "$tmp_dir" in "$repo_root"/.tmp/po0-manual-runner.*) ;; *) exit 1 ;; esac
trap 'rm -rf "${tmp_dir}"' EXIT

state_file="${tmp_dir}/state"
log_file="${tmp_dir}/log"
pid_file="${tmp_dir}/pid"

printf 'status=running\nobserved_at=1700000000\n' > "${state_file}"
PO0_MANUAL_STATE_FILE="${state_file}" \
PO0_MANUAL_LOG_FILE="${log_file}" \
PO0_MANUAL_PID_FILE="${pid_file}" \
PO0_MANUAL_REPORT_COMMAND=/bin/echo \
    sh "${runner}" --force-report

grep -Fqx 'status=finished' "${state_file}"
grep -Fqx 'observed_at=1700000000' "${state_file}"
grep -Fqx 'exit_code=0' "${state_file}"
grep -Fqx -- '--worker-report --force-report' "${log_file}"

printf 'status=running\nobserved_at=1700000001\n' > "${state_file}"
PO0_MANUAL_STATE_FILE="${state_file}" \
PO0_MANUAL_LOG_FILE="${log_file}" \
PO0_MANUAL_PID_FILE="${pid_file}" \
PO0_MANUAL_REPORT_COMMAND=/bin/false \
    sh "${runner}"

grep -Fqx 'status=finished' "${state_file}"
grep -Fqx 'observed_at=1700000001' "${state_file}"
grep -Fqx 'exit_code=1' "${state_file}"

PO0_MANUAL_STATE_FILE="${state_file}" \
PO0_MANUAL_LOG_FILE="${log_file}" \
PO0_MANUAL_PID_FILE="${pid_file}" \
PO0_MANUAL_REPORT_COMMAND=/bin/echo \
    sh "${runner}" official

grep -Fqx 'lane=official' "${state_file}"
grep -Fqx -- '--official-report' "${log_file}"

printf 'OpenWrt asynchronous manual runner tests passed.\n'

# Clear actions modify only the selected channel; use a fake UCI and init script.
mkdir -p "$tmp_dir/bin"
export PO0_TEST_UCI="$tmp_dir/uci-data"
export PO0_TEST_RELOAD="$tmp_dir/reload-log"
cat > "$tmp_dir/bin/uci" <<'MOCK'
#!/bin/sh
[ "$1" != -q ] || shift
command="$1"; key="${2:-}"
case "$command" in
 show) cat "$PO0_TEST_UCI" ;;
 set|delete)
  field="${key%%=*}"
  awk -F= -v key="$field" '$1 != key && index($1,key ".") != 1' "$PO0_TEST_UCI" > "$PO0_TEST_UCI.next"
  [ "$command" != set ] || printf '%s\n' "$key" >> "$PO0_TEST_UCI.next"
  mv "$PO0_TEST_UCI.next" "$PO0_TEST_UCI" ;;
 commit) : ;;
 *) exit 2 ;;
esac
MOCK
cat > "$tmp_dir/bin/init" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> "$PO0_TEST_RELOAD"
MOCK
chmod +x "$tmp_dir/bin/uci" "$tmp_dir/bin/init"
export PATH="$tmp_dir/bin:$PATH"
control="$repo_root/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-control"
sed "s|/etc/init.d/po0-outbound-ip-report|$tmp_dir/bin/init|g" "$control" > "$tmp_dir/control"
cat > "$tmp_dir/original" <<'DATA'
po0_outbound_ip_report.main=reporter
po0_outbound_ip_report.main.enabled=1
po0_outbound_ip_report.main.worker_enabled=1
po0_outbound_ip_report.main.worker_url=https://worker.invalid/report
po0_outbound_ip_report.main.secret=worker-fixture
po0_outbound_ip_report.main.worker_name=worker-name
po0_outbound_ip_report.main.source_id=stable-source
po0_outbound_ip_report.main.interval_seconds=5400
po0_outbound_ip_report.main.worker_timer_enabled=0
po0_outbound_ip_report.main.official_enabled=1
po0_outbound_ip_report.main.official_interval_seconds=900
po0_outbound_ip_report.account=official_target
po0_outbound_ip_report.account.token=pgnfw_fixture
po0_outbound_ip_report.binding=official_binding
po0_outbound_ip_report.binding.target=account
po0_outbound_ip_report.binding.slot=3
DATA
cp "$tmp_dir/original" "$PO0_TEST_UCI"
sh "$tmp_dir/control" worker-clear > /dev/null
if grep -Eq '^po0_outbound_ip_report.main.(worker_url|secret|worker_name)=' "$PO0_TEST_UCI"; then exit 1; fi
grep -Fqx 'po0_outbound_ip_report.main.worker_enabled=0' "$PO0_TEST_UCI"
for pattern in 'main.official_' 'account' 'binding' 'main.source_id' 'main.interval_seconds' 'main.worker_timer_enabled'; do
 diff <(grep -F "po0_outbound_ip_report.$pattern" "$tmp_dir/original") <(grep -F "po0_outbound_ip_report.$pattern" "$PO0_TEST_UCI")
done
cp "$tmp_dir/original" "$PO0_TEST_UCI"
sh "$tmp_dir/control" official-clear > /dev/null
if grep -Eq '^po0_outbound_ip_report.(account|binding)(=|\.)' "$PO0_TEST_UCI"; then exit 1; fi
grep -Fqx 'po0_outbound_ip_report.main.official_enabled=0' "$PO0_TEST_UCI"
diff <(grep -E 'main.(worker_[^=]*|secret|source_id|interval_seconds|enabled)=' "$tmp_dir/original") <(grep -E 'main.(worker_[^=]*|secret|source_id|interval_seconds|enabled)=' "$PO0_TEST_UCI")
[[ "$(cat "$PO0_TEST_RELOAD")" == $'reload\nreload' ]]
printf 'OpenWrt independent clear configuration tests passed.\n'
