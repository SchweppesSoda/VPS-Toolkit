#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
tmp_root="${repo_root}/.tmp"
mkdir -p "${tmp_root}"
tmp_dir="$(mktemp -d "${tmp_root}/po0-lan-official-test.XXXXXX")"
cleanup_test_tmp() {
    rm -rf -- "${tmp_dir}"
}
trap cleanup_test_tmp EXIT
export HOME="${tmp_dir}/home"
export XDG_CONFIG_HOME="${tmp_dir}/xdg-config"
export XDG_STATE_HOME="${tmp_dir}/xdg-state"
export TMPDIR="${tmp_dir}/runtime"
mkdir -p "${HOME}" "${XDG_CONFIG_HOME}" "${XDG_STATE_HOME}" "${TMPDIR}"

progress() {
    printf '[LAN official test] %s\n' "$*"
}

progress 'building LAN Worker asset'
bash_bin="$(command -v bash)"
if command -v cygpath >/dev/null 2>&1; then
    bash_win_bin="$(cygpath -w "${bash_bin}" 2>/dev/null || true)"
else
    bash_win_bin="${bash_bin}"
fi
[[ -n "${bash_win_bin}" ]] || bash_win_bin="${bash_bin}"
asset_dir="${tmp_dir}/assets"
asset="${asset_dir}/po0-lan-client.sh"
build_lan_asset() {
    local manifest="${repo_root}/tools/po0/manifests/lan-worker.txt"
    local entry source content index=0
    mkdir -p "${asset_dir}"
    : > "${asset}"
    while IFS= read -r entry; do
        entry="$(printf '%s' "${entry}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        [[ -n "${entry}" && "${entry}" != \#* ]] || continue
        source="${repo_root}/${entry}"
        [[ -f "${source}" ]] || return 1
        content="$(perl -0pe 's/\A\xEF\xBB\xBF//; s/\r\n?/\n/g; s/\n+\z//' < "${source}")" || return 1
        if (( index > 0 )); then
            content="$(printf '%s' "${content}" | perl -0pe 's/\A#![^\n]*\n//')" || return 1
            printf '\n\n' >> "${asset}"
        fi
        printf '%s' "${content}" >> "${asset}"
        index=$((index + 1))
    done < <(awk '{ sub(/\r$/, ""); print }' "${manifest}")
    (( index > 0 )) || return 1
    printf '\n' >> "${asset}"
    head -n 1 "${asset}" | grep -q '^#!'
}
build_lan_asset
progress 'asset built; preparing isolated mock commands'

fake_bin="${tmp_dir}/bin"
config_dir="${tmp_dir}/config"
home_dir="${tmp_dir}/home"
runtime_dir="${tmp_dir}/runtime"
mkdir -p "${fake_bin}" "${config_dir}" "${home_dir}" "${runtime_dir}"
config_file="${config_dir}/targets.tsv"
settings_file="${config_dir}/settings.env"
empty_settings_file="${config_dir}/empty-settings.env"
curl_log="${tmp_dir}/curl.log"
ssh_log="${tmp_dir}/ssh.log"
order_log="${tmp_dir}/order.log"
cron_in="${tmp_dir}/cron.in"
cron_out="${tmp_dir}/cron.out"
output_file="${tmp_dir}/output"
error_file="${tmp_dir}/error"
state_file="${config_dir}/official-firewall.state"
: > "${curl_log}"
: > "${ssh_log}"
: > "${order_log}"
: > "${cron_in}"

cat > "${fake_bin}/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
set -u
log="${PO0_TEST_CURL_LOG:?}"
order="${PO0_TEST_ORDER_LOG:?}"
output=""
headers=""
previous=""
for arg in "$@"; do
    case "${previous}" in
        --output) output="${arg}" ;;
        --dump-header) headers="${arg}" ;;
    esac
    previous="${arg}"
done
config="$(cat)"
method="$(printf '%s\n' "${config}" | sed -n 's/^request = "\([A-Z]*\)"$/\1/p')"
printf 'argv:' >> "${log}"
printf ' <%s>' "$@" >> "${log}"
printf '\nstdin=%s\n' "${config}" >> "${log}"
printf 'proxy=%s|%s|%s|%s|%s|%s\n' "${http_proxy-}" "${https_proxy-}" "${all_proxy-}" "${HTTP_PROXY-}" "${HTTPS_PROXY-}" "${ALL_PROXY-}" >> "${log}"
printf 'curl\n' >> "${order}"
scenario="${PO0_TEST_SCENARIO:-missing}"
if [[ "${scenario}" == slow ]]; then
    sleep 1
    scenario="missing"
fi
if [[ "${scenario}" == partial && "${config}" == *pgnfw_test_beta* ]]; then
    : > "${output}" 2>/dev/null || true
    : > "${headers}" 2>/dev/null || true
    exit 7
fi
if [[ "${scenario}" == fail ]]; then
    : > "${output}" 2>/dev/null || true
    : > "${headers}" 2>/dev/null || true
    exit 7
fi
body='{"enabled":true,"currentIp":"203.0.113.9/24","whitelist":[],"limit":5}'
case "${scenario}" in
    hit)
        body='{"enabled":true,"currentIp":"203.0.113.9/24","whitelist":[{"ip":"203.0.113.9/24","slot":0}],"limit":5}'
        ;;
    missing)
        if [[ "${method}" == POST ]]; then
            body='{"enabled":true,"currentIp":"203.0.113.9/24","whitelist":[{"ip":"203.0.113.9/24","slot":0}],"limit":5}'
        fi
        ;;
    partial)
        if [[ "${method}" == POST ]]; then
            body='{"enabled":true,"currentIp":"203.0.113.9/24","whitelist":[{"ip":"203.0.113.9/24","slot":0}],"limit":5}'
        fi
        ;;
    fieldorder)
        body='{"limit":5,"whitelist":[{"slot":null,"ip":"203.0.113.9/24"}],"currentIp":"203.0.113.9/24","enabled":true}'
        ;;
    escaped)
        body='{"enabled":true,"currentIp":"203.0.113.9\/24","whitelist":[{"ip":"203.0.113.9\/24","slot":""}],"limit":5}'
        ;;
    wrongslot)
        body='{"enabled":true,"currentIp":"203.0.113.9/24","whitelist":[{"ip":"203.0.113.9/24","slot":1}],"limit":5}'
        ;;
    duplicate)
        body='{"enabled":true,"currentIp":"203.0.113.9/24","whitelist":[{"ip":"203.0.113.9/24","slot":0},{"ip":"198.51.100.8/24","slot":0}],"limit":5}'
        ;;
    malformed)
        body='not-json'
        ;;
    trailing)
        body='{"enabled":true,"currentIp":"203.0.113.9/24","whitelist":[],"limit":5}garbage'
        ;;
    badslot)
        body='{"enabled":true,"currentIp":"203.0.113.9/24","whitelist":[{"ip":"203.0.113.9/24","slot":5}],"limit":5}'
        ;;
    badtypes)
        body='{"enabled":"true","currentIp":203,"whitelist":[],"limit":0}'
        ;;
    badlimit)
        body='{"enabled":true,"currentIp":"203.0.113.9/24","whitelist":[],"limit":6}'
        ;;
    *)
        body='{"enabled":true,"currentIp":"203.0.113.9/24","whitelist":[],"limit":5}'
        ;;
esac
printf 'HTTP/1.1 200 OK\n' > "${headers}"
printf '%s' "${body}" > "${output}"
printf '200'
FAKE_CURL
chmod 700 "${fake_bin}/curl"

cat > "${fake_bin}/ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -u
printf 'ssh\n' >> "${PO0_TEST_ORDER_LOG:?}"
printf 'ssh argv:' >> "${PO0_TEST_SSH_LOG:?}"
printf ' <%s>' "$@" >> "${PO0_TEST_SSH_LOG}"
printf '\n' >> "${PO0_TEST_SSH_LOG}"
exit 0
FAKE_SSH
chmod 700 "${fake_bin}/ssh"
# Native Windows Python resolves subprocess commands through PATHEXT, so its
# shutil.which("ssh") does not see the extensionless POSIX fixture above.
# Keep the POSIX fixture for Bash and add a .cmd bridge for the Python handler.
cat > "${fake_bin}/ssh.cmd" <<'FAKE_SSH_CMD'
@echo off
"%PO0_TEST_BASH_WIN_BIN%" "%~dp0ssh" %*
FAKE_SSH_CMD
chmod 700 "${fake_bin}/ssh.cmd"

cat > "${fake_bin}/getent" <<'FAKE_GETENT'
#!/usr/bin/env bash
printf '8.8.8.8 STREAM example.test\n'
FAKE_GETENT
chmod 700 "${fake_bin}/getent"

cat > "${fake_bin}/crontab" <<'FAKE_CRONTAB'
#!/usr/bin/env bash
set -u
if [[ "${1:-}" == -l ]]; then
    cat "${PO0_TEST_CRON_IN:?}"
    exit 0
fi
cat "${1:?}" > "${PO0_TEST_CRON_OUT:?}"
exit 0
FAKE_CRONTAB
chmod 700 "${fake_bin}/crontab"

# Git for Windows may expose a Microsoft Store python3 alias that exits
# immediately instead of running Python.  Prefer a genuinely runnable
# interpreter when one is available; if only `python` is runnable, provide a
# test-local python3 shim so the asset follows its normal preference order.
test_python=""
test_python_name=""
for candidate in python3 python; do
    candidate_path="$(command -v "${candidate}" 2>/dev/null || true)"
    if [[ -n "${candidate_path}" ]] && "${candidate_path}" -c 'import sys' >/dev/null 2>&1; then
        test_python="${candidate_path}"
        test_python_name="${candidate}"
        break
    fi
done
if [[ -n "${test_python}" && "${test_python_name}" != python3 ]]; then
    cat > "${fake_bin}/python3" <<'FAKE_PYTHON3'
#!/usr/bin/env bash
exec "${PO0_TEST_PYTHON:?}" "$@"
FAKE_PYTHON3
    chmod 700 "${fake_bin}/python3"
fi

cat > "${config_file}" <<'CONFIG'
# enabled|label|source_key|report_key|po0_host|po0_port|po0_user|po0_script|source_token|ssh_extra_args|resource_token|report_mode|ddns_domain
1|test|test|test|po0.example|22|root|/root/nftables-relay-manager.sh|worker-token|||ddns|example.test
CONFIG
chmod 600 "${config_file}"

write_settings() {
    local official_tokens="${1:-}"
    local target_config="${2:-${config_file}}"
    {
        printf "CONFIG_FILE=%q\n" "${target_config}"
        printf "PO0_FIREWALL_TOKENS=%q\n" "${official_tokens}"
        printf "DDNS_CRON_MINUTES='60'\n"
        printf "RESOURCE_CRON_MINUTES='1440'\n"
    } > "${settings_file}"
    chmod 600 "${settings_file}"
}

write_empty_settings() {
    {
        printf "CONFIG_FILE=%q\n" "${config_file}"
        printf "PO0_FIREWALL_TOKENS=''\n"
    } > "${settings_file}"
    chmod 600 "${settings_file}"
}

scenario="missing"
now="1000"
run_asset_for_scenario() {
    local run_scenario="$1"
    shift
    if command -v timeout >/dev/null 2>&1; then
        # Git for Windows can spend several seconds starting each Bash
        # process; keep every case bounded without making the concurrency
        # lock test fail merely because the host is under load.
        env \
            HOME="${home_dir}" \
            XDG_CONFIG_HOME="${tmp_dir}/xdg-config" \
            XDG_STATE_HOME="${tmp_dir}/xdg-state" \
            TMPDIR="${runtime_dir}" \
            PATH="${fake_bin}:${PATH}" \
            PO0_TEST_SCENARIO="${run_scenario}" \
            PO0_TEST_CURL_LOG="${curl_log}" \
            PO0_TEST_SSH_LOG="${ssh_log}" \
            PO0_TEST_ORDER_LOG="${order_log}" \
            PO0_TEST_CRON_IN="${cron_in}" \
            PO0_TEST_CRON_OUT="${cron_out}" \
            PO0_TEST_PYTHON="${test_python}" \
            PO0_TEST_BASH_WIN_BIN="${bash_win_bin}" \
            PO0_LAN_TEST_NOW="${now}" \
            timeout 60s "${bash_bin}" "${asset}" --config "${config_file}" --settings-file "${settings_file}" "$@"
    else
        env \
            HOME="${home_dir}" \
            XDG_CONFIG_HOME="${tmp_dir}/xdg-config" \
            XDG_STATE_HOME="${tmp_dir}/xdg-state" \
            TMPDIR="${runtime_dir}" \
            PATH="${fake_bin}:${PATH}" \
            PO0_TEST_SCENARIO="${run_scenario}" \
            PO0_TEST_CURL_LOG="${curl_log}" \
            PO0_TEST_SSH_LOG="${ssh_log}" \
            PO0_TEST_ORDER_LOG="${order_log}" \
            PO0_TEST_CRON_IN="${cron_in}" \
            PO0_TEST_CRON_OUT="${cron_out}" \
            PO0_TEST_PYTHON="${test_python}" \
            PO0_TEST_BASH_WIN_BIN="${bash_win_bin}" \
            PO0_LAN_TEST_NOW="${now}" \
            "${bash_bin}" "${asset}" --config "${config_file}" --settings-file "${settings_file}" "$@"
    fi
}
run_asset() {
    run_asset_for_scenario "${scenario}" "$@"
}

run_capture() {
    set +e
    run_asset "$@" > "${output_file}" 2> "${error_file}"
    test_rc=$?
    set -e
    return "${test_rc}"
}

assert_contains() {
    local file="$1" value="$2"
    grep -Fq -- "${value}" "${file}" || {
        printf 'Expected %s to contain: %s\n' "${file}" "${value}" >&2
        exit 1
    }
}

assert_not_contains() {
    local file="$1" value="$2"
    if grep -Fq -- "${value}" "${file}"; then
        printf 'Expected %s not to contain secret/value: %s\n' "${file}" "${value}" >&2
        exit 1
    fi
}

assert_eq() {
    local expected="$1" actual="$2" message="$3"
    [[ "${expected}" == "${actual}" ]] || {
        printf '%s (expected=%s got=%s)\n' "${message}" "${expected}" "${actual}" >&2
        exit 1
    }
}

count_lines() {
    local pattern="$1" file="$2"
    grep -c -- "${pattern}" "${file}" 2>/dev/null || true
}

run_scheduler_lock_case() {
    # One scheduled request holds the shared LAN Worker lock while curl is
    # slow; a concurrent scheduler must wait and then skip rather than
    # duplicate a GET.  Keep both child diagnostics available on failure so a
    # platform-specific lock/timing regression is actionable.
    write_settings 'pgnfw_test_alpha'
    scenario=slow
    now=5000
    rm -f -- "${state_file}"
    rm -rf -- "${config_dir}/.official-firewall.lock"
    : > "${curl_log}"
    run_asset --run-official-firewall --scheduled-run > "${tmp_dir}/concurrent-a.out" 2> "${tmp_dir}/concurrent-a.err" &
    pid_a=$!
    sleep 0.1
    run_asset --run-official-firewall --scheduled-run > "${tmp_dir}/concurrent-b.out" 2> "${tmp_dir}/concurrent-b.err" &
    pid_b=$!
    set +e
    wait "${pid_a}"
    rc_a=$?
    wait "${pid_b}"
    rc_b=$?
    set -e
    if [[ "${rc_a}" != 0 || "${rc_b}" != 0 ]]; then
        printf 'scheduler lock diagnostics: rc_a=%s rc_b=%s\n' "${rc_a}" "${rc_b}" >&2
        printf '%s\n' '--- concurrent-a.out'; cat "${tmp_dir}/concurrent-a.out" >&2 || true
        printf '%s\n' '--- concurrent-a.err'; cat "${tmp_dir}/concurrent-a.err" >&2 || true
        printf '%s\n' '--- concurrent-b.out'; cat "${tmp_dir}/concurrent-b.out" >&2 || true
        printf '%s\n' '--- concurrent-b.err'; cat "${tmp_dir}/concurrent-b.err" >&2 || true
        printf '%s\n' '--- lock/state files'; find "${config_dir}" -maxdepth 2 -name '*official*' -o -name '*.lock' -print >&2 || true
    fi
    assert_eq 0 "${rc_a}" 'first scheduled run should finish'
    assert_eq 0 "${rc_b}" 'second scheduled run should finish'
    assert_eq 1 "$(count_lines 'request = "GET"' "${curl_log}")" 'concurrent scheduled runs must share due state'
}

if [[ "${PO0_TEST_ONLY:-}" == lock ]]; then
    run_scheduler_lock_case
    printf 'PASS: LAN scheduler lock case passed.\n'
    exit 0
fi

write_settings 'pgnfw_test_alpha@0'
rm -f -- "${state_file}"
: > "${curl_log}"; : > "${ssh_log}"; : > "${order_log}"

progress 'GET failure, hit, missing, and fixed-slot cases'
scenario=fail
if run_capture --run-official-firewall; then
    printf 'GET failure should return non-zero.\n' >&2
    exit 1
fi
assert_eq 0 "$(count_lines 'request = "POST"' "${curl_log}")" 'GET failure must not POST'
assert_contains "${curl_log}" 'pgnfw_test_alpha'
assert_not_contains "${output_file}" 'pgnfw_test_alpha'
assert_not_contains "${error_file}" 'pgnfw_test_alpha'
assert_not_contains "${curl_log}" '<pgnfw_test_alpha@0>'
assert_contains "${curl_log}" 'proxy=|||||'

scenario=hit
: > "${curl_log}"; : > "${error_file}"; : > "${output_file}"
if ! run_capture --run-official-firewall; then
    printf 'hit should succeed.\n' >&2
    exit 1
fi
assert_eq 0 "$(count_lines 'request = "POST"' "${curl_log}")" 'existing whitelist hit must not POST'

scenario=missing
: > "${curl_log}"; : > "${output_file}"; : > "${error_file}"
if ! run_capture --run-official-firewall; then
    printf 'missing then add should succeed.\n' >&2
    exit 1
fi
assert_eq 1 "$(count_lines 'request = "GET"' "${curl_log}")" 'one token should GET'
assert_eq 1 "$(count_lines 'request = "POST"' "${curl_log}")" 'one missing token should POST'
assert_contains "${output_file}" '已更新'
assert_not_contains "${output_file}" 'pgnfw_test_alpha'

scenario=wrongslot
: > "${curl_log}"; : > "${output_file}"; : > "${error_file}"
if run_capture --run-official-firewall; then
    printf 'wrong fixed slot should fail.\n' >&2
    exit 1
fi
assert_eq 1 "$(count_lines 'request = "POST"' "${curl_log}")" 'wrong fixed slot should POST once'
assert_contains "${error_file}" '槽位 1'
for scenario in malformed duplicate trailing badslot badtypes badlimit; do
    : > "${curl_log}"; : > "${output_file}"; : > "${error_file}"
    if run_capture --run-official-firewall; then
        printf '%s response should fail validation.\n' "${scenario}" >&2
        exit 1
    fi
    assert_eq 0 "$(count_lines 'request = "POST"' "${curl_log}")" "${scenario} must not POST"
done

# Field order, escaped CIDR slashes and an explicitly empty/null slot are all
# valid response forms.  A status refresh is read-only and persists the safe
# response details without changing the previous attempt timestamp.
progress 'strict response parser and read-only state cases'
write_settings 'pgnfw_test_alpha'
scenario=fieldorder
now=1200
: > "${curl_log}"; : > "${output_file}"; : > "${error_file}"
if ! run_capture --official-firewall-status; then
    printf 'field-order/null-slot status should succeed.\n' >&2
    exit 1
fi
assert_eq 0 "$(count_lines 'request = "POST"' "${curl_log}")" 'status must not POST for field-order response'
assert_contains "${state_file}" 'item=1|hit|203.0.113.9/24|203.0.113.9/24@|1|5|'

scenario=escaped
: > "${curl_log}"; : > "${output_file}"; : > "${error_file}"
if ! run_capture --official-firewall-status; then
    printf 'escaped CIDR status should succeed.\n' >&2
    exit 1
fi
assert_eq 0 "$(count_lines 'request = "POST"' "${curl_log}")" 'escaped status must not POST'
assert_contains "${state_file}" '203.0.113.9/24@'

write_settings 'pgnfw_test_alpha@0'
printf 'last_attempt_at=1234\nlast_status=success\n' > "${state_file}"
chmod 600 "${state_file}"
scenario=missing
now=1300
: > "${curl_log}"; : > "${output_file}"; : > "${error_file}"
if ! run_capture --official-firewall-status; then
    printf 'valid missing read-only status should return zero.\n' >&2
    exit 1
fi
assert_eq 0 "$(count_lines 'request = "POST"' "${curl_log}")" 'status must not POST'
assert_contains "${output_file}" '只读，不加白'
assert_not_contains "${output_file}" 'pgnfw_test_alpha'
assert_not_contains "${error_file}" 'pgnfw_test_alpha'
assert_contains "${state_file}" 'last_attempt_at=1234'
assert_contains "${state_file}" 'item=1|missing|203.0.113.9/24||0|5|0'

# Strict CSV parsing fails closed before any request.  Empty entries,
# duplicate items, repeated @, and slots outside 0..4 are rejected.
progress 'strict token CSV cases'
scenario=hit
for invalid_tokens in \
    'pgnfw_test_alpha,' \
    ',pgnfw_test_alpha' \
    'pgnfw_test_alpha,,pgnfw_test_beta' \
    'pgnfw_test_alpha@0@1' \
    'pgnfw_test_alpha@5' \
    'pgnfw_test_alpha,pgnfw_test_alpha' \
    'pgnfw_test_alpha@0,pgnfw_test_alpha@1' \
    'pgnfw_test_alpha,pgnfw_test_alpha@0' \
    'not-a-token'; do
    write_settings "${invalid_tokens}"
    : > "${curl_log}"; : > "${output_file}"; : > "${error_file}"
    if run_capture --run-official-firewall; then
        printf 'invalid token list unexpectedly succeeded: %s\n' "${invalid_tokens}" >&2
        exit 1
    fi
    assert_eq 0 "$(count_lines 'request = "GET"' "${curl_log}")" 'invalid token list must not GET'
    assert_not_contains "${output_file}" 'pgnfw_test_alpha'
    assert_not_contains "${error_file}" 'pgnfw_test_alpha'
done

# Two accounts run in one round; a failure in one must not prevent the other
# account from being attempted, and the aggregate result is partial/non-zero.
progress 'partial-account case'
write_settings 'pgnfw_test_alpha@0,pgnfw_test_beta'
scenario=partial
now=1500
rm -f -- "${state_file}"
: > "${curl_log}"; : > "${output_file}"; : > "${error_file}"
if run_capture --run-official-firewall; then
    printf 'partial official round should return non-zero.\n' >&2
    exit 1
fi
assert_eq 2 "$(count_lines 'request = "GET"' "${curl_log}")" 'partial round must continue to second account'
assert_eq 1 "$(count_lines 'request = "POST"' "${curl_log}")" 'successful missing account should POST once'
assert_contains "${state_file}" 'last_status=partial'
assert_not_contains "${output_file}" 'pgnfw_test_alpha'
assert_not_contains "${error_file}" 'pgnfw_test_beta'

# Scheduled invocations use the independent last-attempt gate; a manual
# invocation at the same timestamp still performs its GET-first check.
progress 'independent due and scheduler lock cases'
scenario=hit
now=2000
printf 'last_attempt_at=2000\nlast_status=success\n' > "${state_file}"
chmod 600 "${state_file}"
: > "${curl_log}"
if ! run_capture --run-official-firewall --scheduled-run; then
    printf 'scheduled due skip should succeed.\n' >&2
    exit 1
fi
assert_eq 0 "$(count_lines 'request = "GET"' "${curl_log}")" 'scheduled run inside interval must skip'
if ! run_capture --run-official-firewall; then
    printf 'manual run must still GET.\n' >&2
    exit 1
fi
[[ "$(count_lines 'request = "GET"' "${curl_log}")" -gt 0 ]] || {
    printf 'manual run did not GET despite due gate.\n' >&2
    exit 1
}
now=1000
: > "${curl_log}"
if ! run_capture --run-official-firewall --scheduled-run; then
    printf 'clock rollback should make scheduled lane due.\n' >&2
    exit 1
fi
[[ "$(count_lines 'request = "GET"' "${curl_log}")" -gt 0 ]] || {
    printf 'clock rollback did not reopen due gate.\n' >&2
    exit 1
}

# A crash between mkdir and pid publication leaves an empty lock directory.
# An old empty directory is safe to reclaim, while the actual request still
# performs the normal GET-first path.
write_settings 'pgnfw_test_alpha'
scenario=hit
now=4500
rm -f -- "${state_file}"
rm -rf -- "${config_dir}/.official-firewall.lock"
mkdir "${config_dir}/.official-firewall.lock"
touch -t 197001010000 "${config_dir}/.official-firewall.lock"
: > "${curl_log}"
if ! run_capture --run-official-firewall --scheduled-run; then
    printf 'stale empty official lock should be reclaimed.\n' >&2
    exit 1
fi
assert_eq 1 "$(count_lines 'request = "GET"' "${curl_log}")" 'stale empty lock must permit one GET'
assert_eq 0 "$(count_lines 'request = "POST"' "${curl_log}")" 'stale empty lock hit must not POST'
if [[ -e "${config_dir}/.official-firewall.lock" ]]; then
    printf 'official lock was not released after stale-empty recovery.\n' >&2
    exit 1
fi

# One scheduled request holds the shared LAN Worker lock while curl is slow;
# a concurrent scheduler must wait and then skip rather than duplicate a GET.
run_scheduler_lock_case

# A failed official preflight never prevents the old DDNS SSH path.
progress 'legacy SSH preflight compatibility'
scenario=fail
now=7000
: > "${curl_log}"; : > "${ssh_log}"; : > "${order_log}"
if run_capture --run-ddns --ddns-targets 'source|example.test|po0.example|22|root|/root/nftables-relay-manager.sh|worker-token|'; then
    :
fi
assert_contains "${ssh_log}" 'ssh'
assert_contains "${curl_log}" '<--connect-timeout> <2>'
assert_contains "${curl_log}" '<--max-time> <5>'
assert_contains "${curl_log}" '<--retry> <0>'

# Self-report's long-lived Python handler runs the official preflight before
# its existing SSH report, while the HTTP response remains the old protocol.
if [[ -n "${test_python}" ]]; then
progress 'long-lived self-report preflight ordering'
scenario=hit
now=8000
: > "${curl_log}"; : > "${ssh_log}"; : > "${order_log}"
# Keep parallel CI/agent runs from sharing the old 1,000-port bucket.  The
# shell PID is unique for the lifetime of this test process; spreading it over
# a 20,000-port range makes accidental collisions with another run unlikely.
port=$((20000 + ($$ % 20000)))
run_asset --self-report-server --self-report-listen "127.0.0.1:${port}" \
    --self-report-targets 'self|po0.example|22|root|/root/nftables-relay-manager.sh|worker-token|43200|' \
    --self-report-secret server-secret > "${tmp_dir}/server.out" 2> "${tmp_dir}/server.err" &
server_pid=$!
cleanup_server() { kill "${server_pid}" 2>/dev/null || true; wait "${server_pid}" 2>/dev/null || true; }
trap 'cleanup_server; cleanup_test_tmp' EXIT
for _ in $(seq 1 40); do
    if "${bash_bin}" -c "</dev/tcp/127.0.0.1/${port}" 2>/dev/null; then break; fi
    sleep 0.1
done
"${test_python}" - "${port}" <<'PY'
import sys
import urllib.request
port = int(sys.argv[1])
url = f"http://127.0.0.1:{port}/report?token=server-secret&ip=8.8.8.8&source=self"
# The handler invokes a bounded preflight child before the legacy SSH path.
# Native Windows Python can spend several seconds spawning the MSYS Bash asset;
# keep the client bound below the full child safety timeout without making the
# test fail on process-start overhead.
with urllib.request.urlopen(url, timeout=30) as response:
    body = response.read().decode("utf-8")
assert response.status == 200, body
assert body.startswith("OK 8.8.8.8;"), body
PY
cleanup_server
server_pid=""
first_order="$(sed -n '1p' "${order_log}")"
second_order="$(sed -n '2p' "${order_log}")"
assert_eq curl "${first_order}" 'Python handler must preflight official channel first'
assert_eq ssh "${second_order}" 'Python handler must preserve SSH after preflight'
assert_eq 1 "$(count_lines 'request = "GET"' "${curl_log}")" \
    'one HTTP report must perform exactly one official GET'
assert_eq 0 "$(count_lines 'request = "POST"' "${curl_log}")" \
    'a hit must not perform an official POST'
assert_eq 1 "$(count_lines '^curl$' "${order_log}")" \
    'one HTTP report must invoke exactly one official preflight'
assert_eq 1 "$(count_lines '^ssh$' "${order_log}")" \
    'one HTTP report must invoke exactly one legacy SSH report'
else
    progress 'self-report ordering skipped: no runnable Python interpreter'
fi

# Official-only cron is installable without a DDNS/resource target, while a
# no-token configuration does not add any new official command.
progress 'official-only cron installation'
printf '# existing\n' > "${cron_in}"
write_settings 'pgnfw_test_alpha@0'
printf '# empty targets\n' > "${config_file}"
: > "${cron_out}"
if ! run_capture --install-cron; then
    printf 'official-only cron installation should succeed.\n' >&2
    exit 1
fi
assert_contains "${cron_out}" '--run-official-firewall --scheduled-run'
assert_contains "${cron_out}" '*/10'
write_empty_settings
: > "${cron_out}"
if run_capture --install-cron; then
    printf 'no-token/no-target cron installation should fail without changing old behavior.\n' >&2
fi
if [[ -s "${cron_out}" ]]; then
    printf 'no-token cron installer unexpectedly wrote a plan.\n' >&2
    exit 1
fi

printf 'LAN Worker official firewall tests passed.\n'
