#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
runner="${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-manual-runner"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/po0-manual-runner.XXXXXX")"
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
