#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
mkdir -p "${repo_root}/.tmp"
tmp_dir="$(mktemp -d "${repo_root}/.tmp/po0-linux-official-http.XXXXXX")"
# Keep the fake HTTP run in a private state namespace; it must never contend
# with a developer's real report lock or state.
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

assert_file_has() {
    grep -Fq -- "$1" "$2" || fail "${3:-missing '$1'}"
}

assert_file_not_has() {
    ! grep -Fq -- "$1" "$2" || fail "${3:-unexpected '$1'}"
}

# shellcheck source=/dev/null
source "${repo_root}/scripts/po0/relay/self-report/linux/src/010-core-string-path-config.sh"
# shellcheck source=/dev/null
source "${repo_root}/scripts/po0/relay/self-report/linux/src/040-prompt-and-input-helpers.sh"
# shellcheck source=/dev/null
source "${repo_root}/scripts/po0/relay/self-report/linux/src/125-official-report.sh"

# Git Bash on NTFS cannot report chmod 700 through stat.  Keep production
# checks intact and mock only that platform limitation in this local test.
case "$(uname -s 2>/dev/null || true)" in
    MINGW*|MSYS*|CYGWIN*)
        official_secure_state_dir() {
            local dir="${1:-}"
            [[ -n "${dir}" && "${dir}" != "/" && ! -L "${dir}" ]] || return 1
            mkdir -p "${dir}" 2>/dev/null || return 1
            [[ -d "${dir}" && ! -L "${dir}" ]]
        }
        ;;
esac

TOKEN_A='pgnfw_http_alpha_not_real'
TOKEN_B='pgnfw_http_beta_not_real'
PO0_FIREWALL_TOKENS="${TOKEN_A}@0,${TOKEN_B}@1"
OFFICIAL_STATE_FILE="${tmp_dir}/official.state"
TMPDIR="${tmp_dir}"
FORCE_REPORT='1'
SCHEDULED_RUN='0'
PO0_OUTBOUND_IP_REPORT_OFFICIAL_NOW='1000'
SCENARIO='baseline'
curl_argv_log="${tmp_dir}/curl-argv.log"
curl_stdin_log="${tmp_dir}/curl-stdin.log"
stdout_log="${tmp_dir}/stdout.log"
stderr_log="${tmp_dir}/stderr.log"

: > "${curl_argv_log}"
: > "${curl_stdin_log}"

# official_direct_request deliberately invokes `env ... curl ...`; these
# test-only shell shims preserve the production call shape while preventing
# every request from leaving the process.
env() {
    while [[ "${1:-}" == '-u' ]]; do
        shift 2
    done
    "${@}"
}

curl() {
    local args=("$@") cfg url method body_file header_file
    printf '%s\n' "${args[*]}" >> "${curl_argv_log}"
    cfg="$(cat)"
    printf '%s\n' "${cfg}" >> "${curl_stdin_log}"
    url="$(sed -n 's/^url = "\(.*\)"$/\1/p' <<< "${cfg}")"
    method="$(sed -n 's/^request = "\(.*\)"$/\1/p' <<< "${cfg}")"
    body_file=''
    header_file=''
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output|--dump-header)
                if [[ "$1" == '--output' ]]; then
                    body_file="${2:-}"
                else
                    header_file="${2:-}"
                fi
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    [[ -n "${url}" && -n "${method}" && -n "${body_file}" && -n "${header_file}" ]] || return 2
    : > "${body_file}"
    : > "${header_file}"
    if [[ "${SCENARIO}" == 'http-fail' && "${method}" == 'GET' ]]; then
        printf '%s\n' '{"error":"mock http failure"}' > "${body_file}"
        printf 'HTTP/1.1 503 Service Unavailable\r\n\r\n\n' > "${header_file}"
        printf '503'
        return 0
    fi
    if [[ "${SCENARIO}" == 'transport-fail' && "${method}" == 'GET' ]]; then
        printf '%s\n' '{"error":"mock transport failure"}' > "${body_file}"
        printf 'HTTP/1.1 000 Mock Failure\r\n\r\n\n' > "${header_file}"
        return 7
    fi
    case "${method}:${url}" in
        GET:*"/${TOKEN_A}")
            printf '%s\n' '{"enabled":true,"currentIp":"203.0.113.10/24","limit":5,"whitelist":[{"ip":"203.0.113.10/24","slot":0}]}' > "${body_file}"
            ;;
        GET:*"/${TOKEN_B}")
            printf '%s\n' '{"enabled":true,"currentIp":"198.51.100.20/24","limit":5,"whitelist":[{"ip":"198.51.100.20/24","slot":2}]}' > "${body_file}"
            ;;
        POST:*"/${TOKEN_B}/add?slot=1")
            if [[ "${SCENARIO}" == 'bad-post' ]]; then
                printf '%s\n' '{"enabled":true,"currentIp":"198.51.100.99/24","limit":5,"whitelist":[{"ip":"198.51.100.99/24","slot":2}]}' > "${body_file}"
            else
                printf '%s\n' '{"enabled":true,"currentIp":"198.51.100.20/24","limit":5,"whitelist":[{"ip":"198.51.100.20/24","slot":1}]}' > "${body_file}"
            fi
            ;;
        *)
            printf '%s\n' '{"error":"unexpected mock request"}' > "${body_file}"
            printf 'HTTP/1.1 500 Mock Error\r\n\r\n\n' > "${header_file}"
            printf '500'
            return 0
            ;;
    esac
    printf 'HTTP/1.1 200 OK\r\n\r\n\n' > "${header_file}"
    printf '200'
    return 0
}

official_transport_available() {
    return 0
}

run_report() {
    : > "${curl_argv_log}"
    : > "${curl_stdin_log}"
    : > "${stdout_log}"
    : > "${stderr_log}"
    rm -f -- "${OFFICIAL_STATE_FILE}"
    set +e
    official_report_once > "${stdout_log}" 2> "${stderr_log}"
    RUN_RC=$?
    set -e
}

# Happy path exercises the actual official_direct_request: only curl's stdin
# sees the token URL; argv, stdout and stderr remain secret-free.
run_report
[[ "${RUN_RC}" == '0' ]] || fail 'mock HTTP baseline report failed'
assert_file_has '-4sS' "${curl_argv_log}" 'curl did not use the IPv4/TLS request flags'
assert_file_has "${TOKEN_A}" "${curl_stdin_log}" 'token A was not supplied through curl stdin'
assert_file_has "${TOKEN_B}" "${curl_stdin_log}" 'token B was not supplied through curl stdin'
assert_file_not_has "${TOKEN_A}" "${curl_argv_log}" 'token A leaked into curl argv'
assert_file_not_has "${TOKEN_B}" "${curl_argv_log}" 'token B leaked into curl argv'
assert_file_not_has "${TOKEN_A}" "${stdout_log}" 'token A leaked into stdout'
assert_file_not_has "${TOKEN_B}" "${stderr_log}" 'token B leaked into stderr'
assert_file_not_has "${TOKEN_A}" "${OFFICIAL_STATE_FILE}" 'token A leaked into state'
assert_file_not_has "${TOKEN_B}" "${OFFICIAL_STATE_FILE}" 'token B leaked into state'

# HTTP and transport failures are hard GET failures: neither can fall back to
# POST, and the aggregate remains nonzero.
for SCENARIO in http-fail transport-fail; do
    run_report
    [[ "${RUN_RC}" -ne 0 ]] || fail "${SCENARIO} was accepted"
    if grep -Fq '/add' "${curl_stdin_log}"; then
        fail "${SCENARIO} incorrectly attempted POST"
    fi
    assert_file_not_has "${TOKEN_A}" "${curl_argv_log}" "${SCENARIO} leaked token A into argv"
    assert_file_not_has "${TOKEN_B}" "${curl_argv_log}" "${SCENARIO} leaked token B into argv"
done

# A valid GET followed by a fixed-slot POST is the only POST path; a malformed
# POST response must fail confirmation.
SCENARIO='bad-post'
run_report
[[ "${RUN_RC}" -ne 0 ]] || fail 'bad POST response was accepted'
assert_file_has '/add?slot=1' "${curl_stdin_log}" 'fixed-slot POST was not issued'
assert_file_not_has "${TOKEN_A}" "${curl_argv_log}" 'bad POST leaked token A into argv'
assert_file_not_has "${TOKEN_B}" "${curl_argv_log}" 'bad POST leaked token B into argv'

printf 'PASS: generic Linux official HTTP mock checks passed.\n'
