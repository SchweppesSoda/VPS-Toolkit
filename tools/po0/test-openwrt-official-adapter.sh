#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
adapter_src="${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-uci"
[[ -s "${adapter_src}" ]] || {
    printf 'FAIL: OpenWrt official adapter is missing.\n' >&2
    exit 1
}

tmp_dir="$(mktemp -d "${repo_root}/.tmp/po0-openwrt-adapter.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT HUP INT TERM
bin_dir="${tmp_dir}/bin"
run_dir="${tmp_dir}/run"
config_file="${tmp_dir}/config"
adapter="${tmp_dir}/adapter"
runner="${tmp_dir}/runner"
engine="${tmp_dir}/engine"
helper="${tmp_dir}/helper"
stdout_log="${tmp_dir}/stdout.log"
stderr_log="${tmp_dir}/stderr.log"
runner_log="${tmp_dir}/runner.log"
mkdir -p "${bin_dir}" "${run_dir}"
: > "${config_file}"
: > "${runner_log}"
cp "${adapter_src}" "${adapter}"

# Stage the current adapter with only its privileged paths redirected into the
# test fixture.  The real run lock is retained; only its root-only directory
# ownership check is bypassed because this test runs as an unprivileged user.
sed -i \
    -e "s|^CONFIG_FILE=.*|CONFIG_FILE='${config_file}'|" \
    -e "s|^ENGINE=.*|ENGINE='${engine}'|" \
    -e "s|^HELPER=.*|HELPER='${helper}'|" \
    -e "s|^OFFICIAL_RUNNER=.*|OFFICIAL_RUNNER='${runner}'|" \
    -e "s|^RUN_DIR=.*|RUN_DIR='${run_dir}'|" \
    -e 's/if ! ensure_run_dir; then/if false; then/' \
    "${adapter}"

cat > "${bin_dir}/uci" <<'EOF'
#!/bin/sh
set -eu
while [ "$#" -gt 0 ] && [ "$1" = '-q' ]; do
    shift
done
command="$1"
shift
case "$command" in
    show)
        case "$PO0_TEST_SCENARIO" in
            unique|duplicate-wan|duplicate-slot|both|disabled|malicious-target|malicious-wan|malicious-label|malicious-token)
                printf '%s\n' \
                    'po0_outbound_ip_report.binding1=official_binding' \
                    'po0_outbound_ip_report.binding2=official_binding'
                ;;
            too-many)
                i=1
                while [ "$i" -le 6 ]; do
                    printf 'po0_outbound_ip_report.binding%s=official_binding\n' "$i"
                    i=$((i + 1))
                done
                ;;
            *)
                exit 2
                ;;
        esac
        ;;
    get)
        key="$1"
        case "$key" in
            po0_outbound_ip_report.main.enabled)
                if [ "$PO0_TEST_SCENARIO" = 'disabled' ]; then
                    printf '0\n'
                else
                    printf '1\n'
                fi
                ;;
            po0_outbound_ip_report.main.worker_enabled)
                if [ "$PO0_TEST_SCENARIO" = 'both' ]; then
                    printf '1\n'
                else
                    printf '0\n'
                fi
                ;;
            po0_outbound_ip_report.main.official_enabled) printf '1\n' ;;
            po0_outbound_ip_report.main.wans) printf 'all\n' ;;
            po0_outbound_ip_report.binding1|po0_outbound_ip_report.binding2) printf 'official_binding\n' ;;
            po0_outbound_ip_report.binding1.enabled|po0_outbound_ip_report.binding2.enabled) printf '1\n' ;;
            po0_outbound_ip_report.binding1.target)
                if [ "$PO0_TEST_SCENARIO" = 'malicious-target' ]; then
                    printf 'target;bad\n'
                else
                    printf 'target1\n'
                fi
                ;;
            po0_outbound_ip_report.binding2.target|po0_outbound_ip_report.binding[3-6].target) printf 'target1\n' ;;
            po0_outbound_ip_report.binding1.wan)
                if [ "$PO0_TEST_SCENARIO" = 'malicious-wan' ]; then
                    printf 'wan;bad\n'
                else
                    printf 'wan1\n'
                fi
                ;;
            po0_outbound_ip_report.binding[3-6].wan)
                index="$(printf '%s\n' "$key" | sed -n 's/.*binding\([3-6]\)\.wan/\1/p')"
                printf 'wan%s\n' "$index"
                ;;
            po0_outbound_ip_report.binding2.wan)
                if [ "$PO0_TEST_SCENARIO" = 'duplicate-wan' ]; then
                    printf 'wan1\n'
                else
                    printf 'wan2\n'
                fi
                ;;
            po0_outbound_ip_report.binding1.slot) printf '0\n' ;;
            po0_outbound_ip_report.binding[3-6].slot) printf '\n' ;;
            po0_outbound_ip_report.binding2.slot)
                if [ "$PO0_TEST_SCENARIO" = 'duplicate-slot' ]; then
                    printf '0\n'
                else
                    printf '1\n'
                fi
                ;;
            po0_outbound_ip_report.target1) printf 'official_target\n' ;;
            po0_outbound_ip_report.target1.enabled) printf '1\n' ;;
            po0_outbound_ip_report.target1.token)
                if [ "$PO0_TEST_SCENARIO" = 'malicious-token' ]; then
                    printf 'pgnfw_good;bad\n'
                else
                    printf 'pgnfw_adapter_not_real\n'
                fi
                ;;
            po0_outbound_ip_report.target1.label)
                if [ "$PO0_TEST_SCENARIO" = 'malicious-label' ]; then
                    printf 'Label;bad\n'
                else
                    printf 'Target one\n'
                fi
                ;;
            *) exit 1 ;;
        esac
        ;;
    *)
        exit 2
        ;;
esac
EOF

cat > "${runner}" <<'EOF'
#!/bin/sh
set -eu
printf 'official\n' >> "$PO0_TEST_RUNNER_LOG"
printf 'args=%s\n' "$*" >> "$PO0_TEST_RUNNER_LOG"
exit "$PO0_TEST_RUNNER_RC"
EOF

cat > "${engine}" <<'EOF'
#!/bin/sh
printf 'worker\n' >> "$PO0_TEST_RUNNER_LOG"
exit 0
EOF

cat > "${helper}" <<'EOF'
#!/bin/sh
exit 0
EOF

chmod 0700 "${bin_dir}/uci" "${adapter}" "${runner}" "${engine}" "${helper}"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_eq() {
    [[ "$1" == "$2" ]] || fail "$3 (expected '$1', got '$2')"
}

assert_file_has() {
    grep -Fq -- "$1" "$2" || fail "${3:-missing expected text '$1'}"
}

assert_file_not_has() {
    ! grep -Fq -- "$1" "$2" || fail "${3:-unexpected text '$1'}"
}

run_adapter() {
    local scenario="$1"
    local runner_rc="${2:-0}"
    local action="${3:---official-report}"
    : > "${stdout_log}"
    : > "${stderr_log}"
    : > "${runner_log}"
    rm -rf "${run_dir}"
    mkdir -p "${run_dir}"
    set +e
    if [ "$scenario" = 'both' ]; then
        PO0_TEST_SCENARIO="${scenario}" \
            PO0_TEST_RUNNER_RC="${runner_rc}" \
            PO0_TEST_RUNNER_LOG="${runner_log}" \
            PATH="${bin_dir}:${PATH}" \
            sh "${adapter}" >"${stdout_log}" 2>"${stderr_log}"
    else
        PO0_TEST_SCENARIO="${scenario}" \
            PO0_TEST_RUNNER_RC="${runner_rc}" \
            PO0_TEST_RUNNER_LOG="${runner_log}" \
            PATH="${bin_dir}:${PATH}" \
            sh "${adapter}" "${action}" >"${stdout_log}" 2>"${stderr_log}"
    fi
    RUN_RC=$?
    set -e
}

run_manual_disabled_cases() {
    run_adapter disabled 0 --official-report
    assert_eq '0' "$RUN_RC" 'manual report failed while automatic service was disabled'
    assert_file_has 'official' "$runner_log" 'manual report did not dispatch official runner'
    assert_file_has 'args=report' "$runner_log" 'manual report action was not preserved'
    run_adapter disabled 0 --official-status
    assert_eq '0' "$RUN_RC" 'manual status failed while automatic service was disabled'
    assert_file_has 'official' "$runner_log" 'manual status did not dispatch official runner'
    assert_file_has 'args=status' "$runner_log" 'manual status action was not preserved'
    run_adapter disabled 0 --force-report
    assert_eq '0' "$RUN_RC" 'manual force report failed while automatic service was disabled'
    assert_file_has 'official' "$runner_log" 'manual force report did not dispatch official runner'
    assert_file_has 'args=report' "$runner_log" 'manual force report action was not preserved'
}

if [ "${PO0_TEST_ONLY:-}" = 'manual-disabled' ]; then
    run_manual_disabled_cases
    printf 'PASS: OpenWrt manual disabled-switch checks passed.\n'
    exit 0
fi

# A unique two-WAN configuration reaches the runner once after the adapter
# validates every binding. The runner reads the UCI sections independently.
run_adapter unique
assert_eq '0' "${RUN_RC}" 'unique official bindings were rejected'
assert_file_has 'args=report' "${runner_log}" 'official runner was not invoked'
assert_file_not_has 'pgnfw_' "${runner_log}" 'official token leaked into runner invocation'
assert_file_not_has 'invalid_configuration' "${stderr_log}" 'unique bindings were marked invalid'

# The adapter must fail closed on duplicate target/WAN configuration and must
# not invoke the official runner with a partial list.
run_adapter duplicate-wan
assert_eq '1' "${RUN_RC}" 'duplicate target/WAN binding was accepted'
assert_file_has 'Duplicate official target/WAN binding: target1|wan1.' "${stderr_log}" 'duplicate target/WAN diagnostic missing'
assert_file_has 'official_status=invalid_configuration' "${stderr_log}" 'duplicate target/WAN did not fail closed'
[[ ! -s "${runner_log}" ]] || fail 'duplicate target/WAN still invoked official runner'
assert_file_not_has 'pgnfw_' "${stdout_log}" 'token leaked on duplicate target/WAN'
assert_file_not_has 'pgnfw_' "${stderr_log}" 'token leaked in duplicate target/WAN diagnostic'

# A target may use multiple WANs, but one backend slot cannot be configured
# twice for that target.
run_adapter duplicate-slot
assert_eq '1' "${RUN_RC}" 'duplicate target/slot binding was accepted'
assert_file_has 'Duplicate official target/slot binding: target1|0.' "${stderr_log}" 'duplicate target/slot diagnostic missing'
assert_file_has 'official_status=invalid_configuration' "${stderr_log}" 'duplicate target/slot did not fail closed'
[[ ! -s "${runner_log}" ]] || fail 'duplicate target/slot still invoked official runner'
assert_file_not_has 'pgnfw_' "${stdout_log}" 'token leaked on duplicate target/slot'
assert_file_not_has 'pgnfw_' "${stderr_log}" 'token leaked in duplicate target/slot diagnostic'

run_adapter too-many
assert_eq '1' "$RUN_RC" 'more than five bindings for one target were accepted'
assert_file_has 'cannot have more than 5 enabled bindings' "$stderr_log" 'max five-binding diagnostic missing'
assert_file_has 'official_status=invalid_configuration' "$stderr_log" 'max five-binding configuration did not fail closed'
[[ ! -s "$runner_log" ]] || fail 'max five-binding configuration still invoked official runner'
assert_file_not_has 'pgnfw_' "$stdout_log" 'token leaked on max five-binding configuration'
assert_file_not_has 'pgnfw_' "$stderr_log" 'token leaked in max five-binding diagnostic'

# When both lanes are enabled, official dispatch is completed before Worker
# dispatch, while each lane remains independently observable.
run_adapter both
assert_eq '0' "$RUN_RC" 'dual-channel adapter run failed'
first_line="$(sed -n '1p' "$runner_log")"
assert_eq 'official' "$first_line" 'official lane did not run first'
assert_file_has 'worker' "$runner_log" 'Worker lane did not run after official lane'
assert_file_not_has 'pgnfw_' "$runner_log" 'dual-channel runner log contains token'

# main.enabled only gates procd/hotplug automation. LuCI manual report and
# read-only status still run through the adapter when the service is stopped.
run_manual_disabled_cases

# Malformed target, WAN, label, or token values are rejected before dispatch.
for scenario in malicious-target malicious-wan malicious-label malicious-token; do
    run_adapter "$scenario"
    assert_eq '1' "$RUN_RC" "$scenario was accepted"
    assert_file_has 'official_status=invalid_configuration' "$stderr_log" "$scenario did not fail closed"
    [[ ! -s "$runner_log" ]] || fail "$scenario still invoked official runner"
    assert_file_not_has 'pgnfw_' "$stdout_log" "$scenario leaked token to stdout"
    assert_file_not_has 'pgnfw_' "$stderr_log" "$scenario leaked token to stderr"
done

printf 'PASS: OpenWrt official adapter mock checks passed.\n'
