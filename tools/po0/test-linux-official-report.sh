#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
mkdir -p "${repo_root}/.tmp"
tmp_dir="$(mktemp -d "${repo_root}/.tmp/po0-linux-official.XXXXXX")"
# Keep this test entirely inside its own user-state namespace. In particular,
# never inspect or create the developer's real package lock while a test run is
# being debugged in parallel with another agent.
export HOME="${tmp_dir}/home"
export XDG_STATE_HOME="${tmp_dir}/state"
export XDG_RUNTIME_DIR="${tmp_dir}/runtime"
cleanup() {
    rm -rf -- "${tmp_dir}" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_eq() {
    local expected="$1" actual="$2" message="$3"
    [[ "${actual}" == "${expected}" ]] || fail "${message} (expected '${expected}', got '${actual}')"
}

assert_file_eq() {
    local expected="$1" file="$2" actual
    actual="$(tr '\n' ' ' < "${file}" | sed 's/[[:space:]]*$//')"
    expected="$(printf '%s' "${expected}" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    [[ "${actual}" == "${expected}" ]] || fail "${3:-unexpected file contents} (expected '${expected}', got '${actual}')"
}

assert_file_has() {
    grep -Fqx -- "$1" "$2" || fail "${3:-missing expected line '$1'}"
}

assert_file_not_has() {
    ! grep -Fq -- "$1" "$2" || fail "${3:-unexpected sensitive text '$1'}"
}

# shellcheck source=/dev/null
source "${repo_root}/scripts/po0/relay/self-report/linux/src/010-core-string-path-config.sh"
# shellcheck source=/dev/null
source "${repo_root}/scripts/po0/relay/self-report/linux/src/040-prompt-and-input-helpers.sh"
# shellcheck source=/dev/null
source "${repo_root}/scripts/po0/relay/self-report/linux/src/060-worker-url-interval-state.sh"
# shellcheck source=/dev/null
source "${repo_root}/scripts/po0/relay/self-report/linux/src/125-official-report.sh"
# shellcheck source=/dev/null
source "${repo_root}/scripts/po0/relay/self-report/linux/src/130-report-submit.sh"

# Git Bash on Windows does not expose POSIX mode bits through stat.  Keep the
# production secure-directory checks intact and mock only that platform fact
# for this local-only test; Linux CI exercises the real mode check.
case "$(uname -s 2>/dev/null || true)" in
    MINGW*|MSYS*|CYGWIN*)
        official_secure_state_dir() {
            local dir="${1:-}"
            [[ -n "${dir}" && "${dir}" != "/" && ! -L "${dir}" ]] || return 1
            mkdir -p "${dir}" 2>/dev/null || return 1
            [[ -d "${dir}" && ! -L "${dir}" ]]
        }
        # Git Bash on Windows does not apply chmod mode bits to NTFS-backed
        # paths.  Keep the production owner/mode checks intact and inject a
        # private test lock path so wrapper ordering can still be exercised.
        report_run_lock_path() {
            local dir="${tmp_dir}/test-lock"
            mkdir -p "${dir}" 2>/dev/null || return 1
            printf '%s/.po0-outbound-ip-report.lock\n' "${dir}"
        }
        ;;
esac

TOKEN_A='pgnfw_test_alpha_not_real'
TOKEN_B='pgnfw_test_beta_not_real'
TOKEN_C='pgnfw_test_gamma_not_real'
PO0_FIREWALL_TOKENS="${TOKEN_A}@0,${TOKEN_B}@1"
OFFICIAL_STATE_FILE="${tmp_dir}/official.state"
FORCE_REPORT='1'
PO0_OUTBOUND_IP_REPORT_OFFICIAL_NOW='1000'
SCENARIO='baseline'
request_log="${tmp_dir}/requests.log"
order_log="${tmp_dir}/order.log"
stdout_log="${tmp_dir}/stdout.log"
stderr_log="${tmp_dir}/stderr.log"
: > "${request_log}"
: > "${order_log}"

official_transport_available() {
    return 0
}

official_direct_request() {
    local token="$1" action="$2" slot="${3:-}" id
    case "${token}" in
        "${TOKEN_A}") id='a' ;;
        "${TOKEN_B}") id='b' ;;
        "${TOKEN_C}") id='c' ;;
        *) return 1 ;;
    esac
    printf '%s|%s|%s\n' "${id}" "${action}" "${slot}" >> "${request_log}"
    printf 'official|%s|%s|%s\n' "${id}" "${action}" "${slot}" >> "${order_log}"
    if [[ "${SCENARIO}" == 'get-fail-b' && "${id}" == 'b' && "${action}" == 'status' ]]; then
        return 1
    fi
    if [[ "${SCENARIO}" == 'get-fail-a' && "${id}" == 'a' && "${action}" == 'status' ]]; then
        return 1
    fi
    if [[ "${SCENARIO}" == 'get-fail-all' && "${action}" == 'status' ]]; then
        return 1
    fi
    if [[ "${SCENARIO}" == 'status-missing' && "${action}" == 'status' ]]; then
        printf '%s\n' '{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[]}'
        return 0
    fi
    if [[ "${SCENARIO}" == 'duplicate-slot' && "${id}" == 'a' && "${action}" == 'status' ]]; then
        printf '%s\n' '{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[{"ip":"203.0.113.10/24","slot":0},{"ip":"198.51.100.10/24","slot":0}]}'
        return 0
    fi
    if [[ "${SCENARIO}" == 'bad-post' && "${id}" == 'b' && "${action}" == 'add' ]]; then
        printf '%s\n' '{"enabled":true,"currentIp":"198.51.100.99/24","limit":5,"whitelist":[{"ip":"198.51.100.99/24","slot":2}]}'
        return 0
    fi
    case "${id}:${action}" in
        a:status)
            printf '%s\n' '{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[{"ip":"203.0.113.10/24","slot":0}]}'
            ;;
        b:status)
            printf '%s\n' '{"enabled":true,"currentIp":"198.51.100.20/24","limit":5,"whitelist":[{"ip":"198.51.100.20/24","slot":2}]}'
            ;;
        b:add)
            printf '%s\n' '{"enabled":true,"currentIp":"198.51.100.20/24","limit":5,"whitelist":[{"ip":"198.51.100.20/24","slot":1}]}'
            ;;
        c:status)
            printf '%s\n' '{"enabled":true,"currentIp":"192.0.2.30/24","limit":5,"whitelist":[{"ip":"192.0.2.30/24","slot":3}]}'
            ;;
        *) return 1 ;;
    esac
}

run_report() {
    : > "${request_log}"
    : > "${order_log}"
    rm -f "${OFFICIAL_STATE_FILE}"
    set +e
    official_report_once > "${stdout_log}" 2> "${stderr_log}"
    RUN_RC=$?
    set -e
}

run_report_keep_state() {
    : > "${request_log}"
    : > "${order_log}"
    set +e
    official_report_once > "${stdout_log}" 2> "${stderr_log}"
    RUN_RC=$?
    set -e
}

run_status() {
    : > "${request_log}"
    : > "${order_log}"
    set +e
    official_status_once > "${stdout_log}" 2> "${stderr_log}"
    RUN_RC=$?
    set -e
}

# Existing whitelist entry: GET only. Missing entry: GET followed by the
# fixed-slot POST. Both entries use the normal default route in this generic
# client and are processed serially.
SCENARIO='baseline'
run_report
assert_eq '0' "${RUN_RC}" 'baseline official report failed'
assert_file_eq 'a|status| b|status| b|add|1' "${request_log}" 'GET/POST sequence changed'
assert_file_has 'official|a|status|' "${order_log}"
assert_file_has 'official|b|status|' "${order_log}"
assert_file_has 'official|b|add|1' "${order_log}"
[[ -r "${OFFICIAL_STATE_FILE}" ]] || fail 'successful official report did not write state'
assert_file_has 'last_attempt_at=1000' "${OFFICIAL_STATE_FILE}" 'successful report did not record attempt time'
assert_file_has 'last_status=success' "${OFFICIAL_STATE_FILE}"
assert_file_has 'last_success_at=1000' "${OFFICIAL_STATE_FILE}" 'successful report did not record success time'
grep -Fq -- '官方账号 2（槽位 2）' "${stderr_log}" || fail 'fixed slot was not rendered as user-facing slot 2'
assert_file_not_has '官方账号 2（槽位 1）' "${stderr_log}" 'raw zero-based fixed slot leaked into report output'

# A fixed-slot hit must not POST; a wrong slot must POST and validate the POST
# response's own currentIp/slot rather than reusing the old GET response.
SCENARIO='baseline'
run_report
assert_file_eq 'a|status| b|status| b|add|1' "${request_log}" 'fixed-slot hit should remain GET-only'
SCENARIO='bad-post'
run_report
[[ "${RUN_RC}" -ne 0 ]] || fail 'bad POST confirmation was accepted'
assert_file_eq 'a|status| b|status| b|add|1' "${request_log}" 'bad POST sequence changed'

# A failed read-only GET is a hard failure and must never fall back to POST.
SCENARIO='get-fail-b'
run_report
[[ "${RUN_RC}" -ne 0 ]] || fail 'GET failure was accepted'
assert_file_eq 'a|status| b|status|' "${request_log}" 'GET failure incorrectly triggered POST'

# One failed token must not stop later tokens; the aggregate is partial.
PO0_FIREWALL_TOKENS=" ,${TOKEN_A}@0 ;"$'\n\t'"${TOKEN_B}@1，${TOKEN_C}@3； "
SCENARIO='get-fail-b'
run_report
[[ "${RUN_RC}" -ne 0 ]] || fail 'partial report returned success'
[[ "${OFFICIAL_RESULT_STATUS}" == 'partial' ]] || fail 'partial result status was not retained'
assert_file_eq 'a|status| b|status| c|status|' "${request_log}" 'partial report did not continue after failure'
assert_file_has 'last_attempt_at=1000' "${OFFICIAL_STATE_FILE}" 'partial report did not record attempt time'
assert_file_has 'last_status=partial' "${OFFICIAL_STATE_FILE}" 'partial report did not record partial status'
assert_file_not_has 'last_success_at=' "${OFFICIAL_STATE_FILE}" 'partial report incorrectly recorded success time'
assert_file_not_has "${TOKEN_A}" "${request_log}" 'token A escaped request log'
assert_file_not_has "${TOKEN_B}" "${request_log}" 'token B escaped request log'
assert_file_not_has "${TOKEN_C}" "${request_log}" 'token C escaped request log'

# --official-status is read-only: a failed GET is reported as failure and still
# never calls add.
PO0_FIREWALL_TOKENS="${TOKEN_A}@0,${TOKEN_B}@1"
SCENARIO='get-fail-b'
run_status
[[ "${RUN_RC}" -ne 0 ]] || fail 'status GET failure returned success'
assert_file_eq 'a|status| b|status|' "${request_log}" 'status mode performed a POST'
assert_file_not_has "${TOKEN_A}" "${stdout_log}"
assert_file_not_has "${TOKEN_B}" "${stderr_log}"

# A valid read-only response whose current IP is not listed is a normal
# missing result: it is reported as such, returns success, and never POSTs.
SCENARIO='status-missing'
run_status
assert_eq '0' "${RUN_RC}" 'status missing result returned failure'
assert_file_eq 'a|status| b|status|' "${request_log}" 'status missing performed an add'
assert_file_not_has '/add' "${request_log}" 'status missing performed a POST'

# A response cannot assign the same non-null numeric slot to two entries.
PO0_FIREWALL_TOKENS="${TOKEN_A}@0"
SCENARIO='duplicate-slot'
run_report
[[ "${RUN_RC}" -ne 0 ]] || fail 'duplicate whitelist slot was accepted'
assert_file_eq 'a|status|' "${request_log}" 'duplicate whitelist slot triggered an unexpected request'
assert_file_not_has '/add' "${request_log}" 'duplicate whitelist slot triggered a POST'

# The official response accepts automatic slots as null or an empty string,
# while rejecting string numerics, booleans, out-of-range values, and numeric
# spellings that are not strict JSON integers.
empty_slot_json='{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[{"slot":"","ip":"203.0.113.10/24"}]}'
official_json_whitelist_count "${empty_slot_json}" >/dev/null || fail 'empty-string whitelist slot was rejected'
null_slot_json='{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[{"slot":null,"ip":"203.0.113.10/24"}]}'
official_json_whitelist_count "${null_slot_json}" >/dev/null || fail 'null whitelist slot was rejected'
for invalid_slot_json in \
    '{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[{"ip":"203.0.113.10/24","slot":"0"}]}' \
    '{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[{"ip":"203.0.113.10/24","slot":true}]}' \
    '{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[{"ip":"203.0.113.10/24","slot":5}]}' \
    '{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[{"ip":"203.0.113.10/24","slot":0.1}]}' \
    '{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[{"ip":"203.0.113.10/24","slot":0e1}]}'; do
    if official_json_whitelist_count "${invalid_slot_json}" >/dev/null; then
        fail 'non-integer or out-of-range whitelist slot was accepted'
    fi
done

# The parser must not accept a substring that merely contains the expected
# fields.  Field order is arbitrary, but duplicate or unknown keys, nested
# schema lookalikes, wrong types, and trailing bytes all fail closed.
reordered_json='{"whitelist":[{"slot":"","ip":"203.0.113.10/24"}],"limit":5,"currentIp":"203.0.113.10/24","enabled":true}'
official_response_valid "${reordered_json}" || fail 'field-order variation was rejected'
for malicious_json in \
    '{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[]} trailing' \
    '{"enabled":true,"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[]}' \
    '{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[],"extra":null}' \
    '{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[{"ip":"203.0.113.10/24","slot":"","extra":false}]}' \
    '{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[{"ip":"203.0.113.10/24","ip":"198.51.100.10/24","slot":""}]}' \
    '{"enabled":true,"currentIp":{"value":"203.0.113.10/24"},"limit":5,"whitelist":[]}' \
    '{"enabled":true,"currentIp":"203.0.113.10/24","limit":"5","whitelist":[]}' \
    '{"enabled":1,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[]}' \
    '{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":{"0":{"ip":"203.0.113.10/24"}}}' \
    '{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[{"ip":{"value":"203.0.113.10/24"}}]}'; do
    if official_response_valid "${malicious_json}"; then
        fail 'malformed, nested, duplicate, unknown, or trailing JSON was accepted'
    fi
done

# Read-only status refreshes sanitized account state but must preserve the
# independent report due-state, even when one of the status checks fails.
PO0_FIREWALL_TOKENS="${TOKEN_A}@0,${TOKEN_B}@1"
printf 'last_attempt_at=900\nlast_status=partial\n' > "${OFFICIAL_STATE_FILE}"
SCENARIO='get-fail-b'
run_status
[[ "${RUN_RC}" -ne 0 ]] || fail 'status partial result returned success'
assert_file_has 'last_attempt_at=900' "${OFFICIAL_STATE_FILE}" 'status-only check changed due-state'
assert_file_has 'last_checked_at=1000' "${OFFICIAL_STATE_FILE}" 'status-only check did not refresh checked time'
assert_file_has 'last_status=partial' "${OFFICIAL_STATE_FILE}" 'status-only check did not retain aggregate status'
assert_file_has 'item=1|hit|203.0.113.10/24|203.0.113.10/24@0|1|5|0' "${OFFICIAL_STATE_FILE}" 'status-only check did not save sanitized hit state'
assert_file_has 'item=2|error|||||1' "${OFFICIAL_STATE_FILE}" 'status-only check did not save sanitized failure state'
assert_file_not_has "${TOKEN_A}" "${OFFICIAL_STATE_FILE}" 'status-only state leaked token A'
assert_file_not_has "${TOKEN_B}" "${OFFICIAL_STATE_FILE}" 'status-only state leaked token B'

# An all-failed report still records the attempt and enters the same due gate;
# FORCE_REPORT only bypasses this local gate.
SCENARIO='get-fail-all'
run_report
[[ "${RUN_RC}" -ne 0 ]] || fail 'all-failed report returned success'
[[ "${OFFICIAL_RESULT_STATUS}" == 'failed' ]] || fail 'all-failed result status was not failed'
assert_file_has 'last_attempt_at=1000' "${OFFICIAL_STATE_FILE}" 'failed report did not record attempt time'
assert_file_has 'last_status=failed' "${OFFICIAL_STATE_FILE}" 'failed report did not record failed status'
assert_file_not_has 'last_success_at=' "${OFFICIAL_STATE_FILE}" 'failed report incorrectly recorded success time'
FORCE_REPORT='0'
SCENARIO='baseline'
PO0_OUTBOUND_IP_REPORT_OFFICIAL_NOW='1100'
SCHEDULED_RUN='1'
run_report_keep_state
assert_eq '0' "${RUN_RC}" 'failed report due gate returned failure'
[[ "${OFFICIAL_RESULT_STATUS}" == 'skipped' ]] || fail 'failed report due gate was not skipped'
[[ ! -s "${request_log}" ]] || fail 'failed report due gate performed a request'
FORCE_REPORT='1'
SCHEDULED_RUN='0'

# Due state is independent from Worker state and suppresses official calls;
# FORCE_REPORT only bypasses this local gate.
printf 'last_attempt_at=1000\nlast_success_at=1000\nlast_status=success\n' > "${OFFICIAL_STATE_FILE}"
PO0_OUTBOUND_IP_REPORT_OFFICIAL_NOW='1100'
FORCE_REPORT='0'
SCHEDULED_RUN='1'
SCENARIO='baseline'
run_report_keep_state
assert_eq '0' "${RUN_RC}" 'not-due report failed'
[[ "${OFFICIAL_RESULT_STATUS}" == 'skipped' ]] || fail 'not-due status was not skipped'
[[ ! -s "${request_log}" ]] || fail 'not-due report performed a request'
FORCE_REPORT='1'
SCHEDULED_RUN='0'

# Manual runs do not inherit the scheduler's due gate. Even with a recent
# last-attempt timestamp, a manual report still performs the safe GET-first
# decision (and only then POSTs when the slot is missing).
printf 'last_attempt_at=1000\nlast_success_at=1000\nlast_status=success\n' > "${OFFICIAL_STATE_FILE}"
PO0_OUTBOUND_IP_REPORT_OFFICIAL_NOW='1100'
FORCE_REPORT='0'
SCHEDULED_RUN='0'
SCENARIO='baseline'
run_report_keep_state
assert_eq '0' "${RUN_RC}" 'manual report was incorrectly due-gated'
assert_file_eq 'a|status| b|status| b|add|1' "${request_log}" 'manual report did not perform GET-first check'
FORCE_REPORT='1'
unset PO0_OUTBOUND_IP_REPORT_OFFICIAL_NOW

# The cron has one wake-up, but each lane keeps its own last-attempt clock:
# official is due every 600 seconds and Worker remains hourly. Manual calls
# are always due and are not coupled to either scheduler clock.
mkdir -p "$(dirname "$(worker_state_file)")"
printf 'last_attempt_at=1000\nlast_status=success\n' > "$(worker_state_file)"
printf 'last_attempt_at=1000\nlast_status=success\n' > "${OFFICIAL_STATE_FILE}"
SCHEDULED_RUN='1'
FORCE_REPORT='0'
PO0_OUTBOUND_IP_REPORT_OFFICIAL_NOW='1100'
if official_due; then fail 'official lane ignored its 600-second scheduled due gate'; fi
if worker_due; then fail 'Worker lane followed the ten-minute official wake-up'; fi
PO0_OUTBOUND_IP_REPORT_OFFICIAL_NOW='1700'
if ! official_due; then fail 'official lane did not become due after 600 seconds'; fi
if worker_due; then fail 'Worker lane became due before its hourly interval'; fi
PO0_OUTBOUND_IP_REPORT_OFFICIAL_NOW='4700'
if ! official_due || ! worker_due; then fail 'independent lanes did not become due at their own intervals'; fi
SCHEDULED_RUN='0'
PO0_OUTBOUND_IP_REPORT_OFFICIAL_NOW='1100'
if ! official_due || ! worker_due; then fail 'manual run was incorrectly due-gated'; fi
FORCE_REPORT='1'
unset PO0_OUTBOUND_IP_REPORT_OFFICIAL_NOW

# Malformed/ambiguous values fail closed without exposing their contents.
for bad_tokens in \
    'pgnfw_bad;$(touch /tmp/po0-test-owned)' \
    "${TOKEN_A}@5" \
    "${TOKEN_A}@0,${TOKEN_A}@0" \
    "${TOKEN_A}@0,${TOKEN_A}@1" \
    "${TOKEN_A},${TOKEN_A}@0"; do
    PO0_FIREWALL_TOKENS="${bad_tokens}"
    official_validate_tokens >/dev/null 2> "${stderr_log}" && fail 'malformed token configuration was accepted'
    assert_file_not_has 'pgnfw_' "${stderr_log}" 'malformed token escaped diagnostics'
done

# Wrapper ordering, independent return codes, and SSID guard.
PO0_FIREWALL_TOKENS="${TOKEN_A}@0"
SCENARIO='baseline'
WORKER_ENABLED='1'
WORKER_URL='https://worker.invalid/report'
SECRET=''
WANS=''
SOURCE_ID='test-device'
IDENTITY='test-device'
skip_report_for_wifi_ssid_if_needed() { return 1; }
normalize_wan_selection_list() { printf '%s\n' "$1"; }
validate_wan_selection() { return 0; }
resolve_report_wans() { printf '__default__\n'; }
detect_outbound_ipv4() { printf '192.0.2.10\n'; }
default_source_id() { printf 'test-device\n'; }
normalize_report_token() { printf '%s\n' "$1"; }
self_report_completed() { :; }
self_report_incomplete() { :; }
self_report_append_response_target_success() { printf '%s\n' "$1"; }
report_detail_enabled() { return 1; }
curl() {
    printf 'worker\n' >> "${order_log}"
    printf 'OK\n200\n'
}

# The run lock is package-owned runtime state.  A custom official state file
# must not make the runner chmod or otherwise mutate its parent directory.
(
    # Do not let this assertion-only subshell inherit the test's global
    # cleanup trap and remove the parent fixture directory on exit.
    trap - EXIT HUP INT TERM
    unset XDG_RUNTIME_DIR XDG_STATE_HOME
    HOME="${tmp_dir}/lock-home"
    OFFICIAL_STATE_FILE="${tmp_dir}/sensitive-parent/custom.state"
    lock_path="$(report_run_lock_path)"
    [[ "${lock_path}" != "${tmp_dir}/sensitive-parent/"* ]] || fail 'run lock followed custom official state path'
    case "$(uname -s 2>/dev/null || true)" in
        MINGW*|MSYS*|CYGWIN*) expected_lock="${tmp_dir}/test-lock/.po0-outbound-ip-report.lock" ;;
        *) expected_lock="${tmp_dir}/lock-home/.local/state/po0-outbound-ip-report/.po0-outbound-ip-report.lock" ;;
    esac
    [[ "${lock_path}" == "${expected_lock}" ]] || fail "run lock did not use package-owned state directory (got '${lock_path}')"
    lock_dir="$(dirname "${lock_path}")"
    [[ -d "${lock_dir}" ]] || fail 'run lock directory was not created'
    case "$(uname -s 2>/dev/null || true)" in
        MINGW*|MSYS*|CYGWIN*) ;;
        *)
            lock_owner="$(stat -c '%u' "${lock_dir}" 2>/dev/null || true)"
            lock_uid="$(id -u 2>/dev/null || true)"
            [[ "${lock_owner}" == "${lock_uid}" ]] || fail 'run lock directory owner is not current uid'
            lock_mode="$(stat -c '%a' "${lock_dir}" 2>/dev/null || true)"
            [[ "${lock_mode}" == '700' ]] || fail 'run lock directory mode is not 700'
            ;;
    esac
)

run_wrapper() {
    : > "${order_log}"
    set +e
    report_once > "${stdout_log}" 2> "${stderr_log}"
    RUN_RC=$?
    set -e
}
run_wrapper
assert_eq '0' "${RUN_RC}" 'combined wrapper failed'
assert_file_eq 'official|a|status| worker' "${order_log}" 'official lane was not executed before Worker'

# Automatic switches are independent of credentials and of manual report selection.
SCHEDULED_RUN=1
FORCE_REPORT=1
WORKER_AUTO_ENABLED=0
OFFICIAL_AUTO_ENABLED=1
run_wrapper
assert_eq '0' "$RUN_RC" 'paused Worker should not fail official'
assert_file_eq 'official|a|status|' "$order_log" 'Worker automatic pause was ignored'
WORKER_AUTO_ENABLED=1
OFFICIAL_AUTO_ENABLED=0
run_wrapper
assert_eq '0' "$RUN_RC" 'paused official should not fail Worker'
assert_file_eq 'worker' "$order_log" 'official automatic pause was ignored'
WORKER_AUTO_ENABLED=0
run_wrapper
assert_eq '0' "$RUN_RC" 'both paused should return quietly'
[[ ! -s "$order_log" ]] || fail 'both paused ran a lane'
SCHEDULED_RUN=0
run_wrapper
assert_file_eq 'official|a|status| worker' "$order_log" 'manual run must ignore automatic pauses'
WORKER_AUTO_ENABLED=1
OFFICIAL_AUTO_ENABLED=1
FORCE_REPORT=0

SCENARIO='get-fail-a'
run_wrapper
[[ "${RUN_RC}" -ne 0 ]] || fail 'combined wrapper hid official failure'
assert_file_has 'worker' "${order_log}" 'Worker was skipped after official failure'

# A second scheduled/manual process must not enter either lane while the
# package-owned run lock is held by a live process.
skip_report_for_wifi_ssid_if_needed() { return 1; }
lock_path="$(report_run_lock_path)"
mkdir -p "${lock_path}"
printf '%s\n' "$$" > "${lock_path}/pid"
run_wrapper
assert_eq '0' "${RUN_RC}" 'concurrent wrapper did not skip cleanly'
[[ ! -s "${order_log}" ]] || fail 'concurrent wrapper entered a lane despite the lock'
rm -f -- "${lock_path}/pid"
rmdir -- "${lock_path}" 2>/dev/null || true

skip_report_for_wifi_ssid_if_needed() {
    : > "${order_log}"
    return 0
}
SCENARIO='baseline'
run_wrapper
assert_eq '0' "${RUN_RC}" 'SSID skip did not return success'
[[ ! -s "${order_log}" ]] || fail 'SSID skip did not stop both lanes'

printf 'PASS: generic Linux official firewall core mock checks passed.\n'
