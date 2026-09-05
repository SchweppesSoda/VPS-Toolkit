#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
helper_src="${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-official-firewall-request"
runner_src="${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-official-firewall-runner"

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	exit 1
}

[[ -r "${helper_src}" ]] || fail 'official firewall request helper is missing'
[[ -r "${runner_src}" ]] || fail 'official firewall runner is missing'

mkdir -p "${repo_root}/.tmp"
tmp_dir="$(mktemp -d "${repo_root}/.tmp/po0-official-firewall-core.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT HUP INT TERM

bin_dir="${tmp_dir}/bin"
helper="${tmp_dir}/helper"
runner="${tmp_dir}/runner"
config_file="${tmp_dir}/config"
stdout_file="${tmp_dir}/stdout"
stderr_file="${tmp_dir}/stderr"
curl_log="${tmp_dir}/curl.log"
curl_argv_log="${tmp_dir}/curl-argv.log"
mwan_log="${tmp_dir}/mwan.log"
jsonfilter_log="${tmp_dir}/jsonfilter.log"

mkdir -p "${bin_dir}"
cp "${helper_src}" "${helper}"
cp "${runner_src}" "${runner}"
sed -i.tmp \
	-e "s|^HELPER=.*|HELPER='${helper}'|" \
	-e "s|^MWAN3=.*|MWAN3='${bin_dir}/mwan3'|" \
	-e "s|^CONFIG_FILE=.*|CONFIG_FILE='${config_file}'|" \
	"${runner}"
rm -f "${runner}.tmp"
printf '%s\n' '# isolated test configuration' > "${config_file}"
chmod 0700 "${helper}" "${runner}"

cat > "${bin_dir}/uci" <<'MOCK'
#!/bin/sh
set -eu

if [ "${1:-}" = '-q' ]; then
	shift
fi

command="${1:-}"
case "${command}" in
show)
	printf '%s\n' 'po0_outbound_ip_report.binding1=official_binding'
	if [ "${PO0_TEST_MULTI:-0}" = '1' ]; then
		printf '%s\n' 'po0_outbound_ip_report.binding2=official_binding'
	fi
	exit 0
	;;
get)
	key="${2:-}"
	case "${key}" in
	po0_outbound_ip_report.binding1)
		printf '%s\n' 'official_binding'
		;;
	po0_outbound_ip_report.binding1.target)
		printf '%s\n' 'target1'
		;;
	po0_outbound_ip_report.binding1.label)
		printf '%s\n' 'Official test binding'
		;;
	po0_outbound_ip_report.binding1.wan)
		printf '%s\n' 'wan1'
		;;
	po0_outbound_ip_report.binding1.slot)
		printf '%s\n' "${PO0_TEST_SLOT:-}"
		;;
	po0_outbound_ip_report.binding1.enabled)
		printf '%s\n' "${PO0_TEST_BINDING_ENABLED:-1}"
		;;
	po0_outbound_ip_report.binding2)
		printf '%s\n' 'official_binding'
		;;
	po0_outbound_ip_report.binding2.target)
		printf '%s\n' 'target1'
		;;
	po0_outbound_ip_report.binding2.label)
		printf '%s\n' 'Official test binding 2'
		;;
	po0_outbound_ip_report.binding2.wan)
		printf '%s\n' 'wan2'
		;;
	po0_outbound_ip_report.binding2.slot)
		printf '%s\n' '1'
		;;
	po0_outbound_ip_report.binding2.enabled)
		printf '%s\n' "${PO0_TEST_BINDING_ENABLED:-1}"
		;;
	po0_outbound_ip_report.target1)
		printf '%s\n' 'official_target'
		;;
	po0_outbound_ip_report.target1.label)
		printf '%s\n' 'Official test target'
		;;
	po0_outbound_ip_report.target1.enabled)
		printf '%s\n' "${PO0_TEST_TARGET_ENABLED:-1}"
		;;
	po0_outbound_ip_report.target1.token)
		printf '%s\n' "${PO0_TEST_TOKEN:-}"
		;;
	*)
		exit 1
		;;
	esac
	;;
*)
	exit 1
	;;
esac
MOCK

cat > "${bin_dir}/jsonfilter" <<'MOCK'
#!/bin/sh
set -eu

expr="${2:-}"
payload="$(cat)"
printf '%s\n' "${expr}" >> "${PO0_TEST_JSONFILTER_LOG:?}"

indexed_value() {
	key="$1"
	index="$2"
	case "${key}" in
	ip)
		printf '%s\n' "${payload}" |
			tr '{' '\n' |
			sed -n 's/.*"ip"[[:space:]]*:[[:space:]]*"\([^"\\]*\)".*/\1/p' |
			sed -n "$((index + 1))p"
		;;
	slot)
		printf '%s\n' "${payload}" |
			tr '{' '\n' |
			sed -n 's/.*"slot"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' |
			sed -n "$((index + 1))p"
		;;
	*)
		return 1
		;;
	esac
}

if [ "${expr}" = '@.enabled' ]; then
	printf '%s\n' "${payload}" |
		sed -n 's/.*"enabled"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p'
elif [ "${expr}" = '@.currentIp' ]; then
	printf '%s\n' "${payload}" |
		sed -n 's/.*"currentIp"[[:space:]]*:[[:space:]]*"\([^"\\]*\)".*/\1/p'
elif [ "${expr}" = '@.limit' ]; then
	printf '%s\n' "${payload}" |
		sed -n 's/.*"limit"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p'
elif [ "${expr}" = '@["whitelist"]' ] && [ "${1:-}" = '-t' ]; then
	case "${PO0_TEST_SCENARIO:-}" in
	missing-whitelist|nested-whitelist)
		exit 1
		;;
	whitelist-object)
		printf 'object\n'
		;;
	*)
		printf 'array\n'
		;;
	esac
elif [ "${expr}" = '@.whitelist[*].ip' ]; then
	printf '%s\n' "${payload}" |
		tr '{' '\n' |
		sed -n 's/.*"ip"[[:space:]]*:[[:space:]]*"\([^"\\]*\)".*/\1/p'
elif printf '%s\n' "${expr}" | grep -Eq '^@\.whitelist\[[0-9]+\]\.ip$'; then
	index="$(printf '%s\n' "${expr}" | sed -n 's/^@\.whitelist\[\([0-9][0-9]*\)\]\.ip$/\1/p')"
	indexed_value ip "${index}"
elif printf '%s\n' "${expr}" | grep -Eq '^@\.whitelist\[[0-9]+\]\.slot$'; then
	index="$(printf '%s\n' "${expr}" | sed -n 's/^@\.whitelist\[\([0-9][0-9]*\)\]\.slot$/\1/p')"
	indexed_value slot "${index}"
else
	exit 1
fi
MOCK

cat > "${bin_dir}/curl" <<'MOCK'
#!/bin/sh
set -eu

config="$(cat)"
printf '%s\n' "$@" >> "$PO0_TEST_CURL_ARGV_LOG"
request="$(printf '%s\n' "${config}" | sed -n 's/^request = "\(.*\)"$/\1/p')"
[ -n "${request}" ] || exit 2
printf '%s\n' "${request}" >> "${PO0_TEST_CURL_LOG:?}"

output_file=''
header_file=''
while [ "$#" -gt 0 ]; do
	case "$1" in
	--output)
		output_file="${2:-}"
		shift 2
		;;
	--dump-header)
		header_file="${2:-}"
		shift 2
		;;
	*)
		shift
		;;
	esac
done

emit() {
	[ -n "${output_file}" ] && printf '%s' "$1" > "${output_file}"
	[ -n "${header_file}" ] && : > "${header_file}"
	printf '%s' "$2"
}

emit_sensitive() {
	body="$1"
	[ -n "${output_file}" ] && printf '%s' "${body}" > "${output_file}"
	[ -n "${header_file}" ] && printf 'HTTP/1.1 200 Mock\r\nAuthorization: Bearer %s\r\nLocation: https://124.221.69.228/api/firewall/%s\r\n\r\n' "${PO0_TEST_TOKEN:-redacted}" "${PO0_TEST_TOKEN:-redacted}" > "${header_file}"
	printf '200'
}

healthy='{"enabled":true,"currentIp":"203.0.113.0/24","limit":5,"whitelist":[{"ip":"203.0.113.0/24","slot":0}]}'
missing='{"enabled":true,"currentIp":"203.0.113.0/24","limit":5,"whitelist":[{"ip":"198.51.100.0/24","slot":1}]}'
scenario="${PO0_TEST_SCENARIO:-healthy}"

case "${scenario}" in
get-fail)
	if [ "${request}" = 'GET' ]; then
		emit '{"error":"upstream unavailable"}' 503
	else
		emit "${healthy}" 200
	fi
	;;
not-whitelisted)
	if [ "${request}" = 'GET' ]; then
		emit "${missing}" 200
	else
		emit "${healthy}" 200
	fi
	;;
slot-mismatch)
	if [ "${request}" = 'GET' ]; then
		emit '{"enabled":true,"currentIp":"203.0.113.0/24","limit":5,"whitelist":[{"ip":"203.0.113.0/24","slot":1}]}' 200
	else
		emit "${healthy}" 200
	fi
	;;
bad-limit)
	emit '{"enabled":true,"currentIp":"203.0.113.0/24","limit":6,"whitelist":[{"ip":"203.0.113.0/24","slot":0}]}' 200
	;;
bad-slot)
	emit '{"enabled":true,"currentIp":"203.0.113.0/24","limit":5,"whitelist":[{"ip":"203.0.113.0/24","slot":5}]}' 200
	;;
duplicate-response-slot)
	emit '{"enabled":true,"currentIp":"203.0.113.0/24","limit":5,"whitelist":[{"ip":"203.0.113.0/24","slot":0},{"ip":"198.51.100.0/24","slot":0}]}' 200
	;;
null-slot)
	emit '{"enabled":true,"currentIp":"203.0.113.0/24","limit":5,"whitelist":[{"ip":"203.0.113.0/24","slot":null}]}' 200
	;;
missing-whitelist)
	emit '{"enabled":true,"currentIp":"203.0.113.0/24","limit":5}' 200
	;;
nested-whitelist)
	emit '{"enabled":true,"currentIp":"203.0.113.0/24","limit":5,"meta":{"whitelist":[]}}' 200
	;;
whitelist-object)
	emit '{"enabled":true,"currentIp":"203.0.113.0/24","limit":5,"whitelist":{}}' 200
	;;
http-error)
	emit '{"error":"upstream failure"}' 502
	;;
bad-json)
	emit "{\"broken\":\"${PO0_TEST_TOKEN:-redacted}\"" 200
	;;
curl-stderr-token)
	printf 'curl diagnostic token=%s\n' "${PO0_TEST_TOKEN:-redacted}" >&2
	emit "${healthy}" 200
	;;
curl-echo-sensitive)
	emit_sensitive "{\"enabled\":true,\"currentIp\":\"203.0.113.0/24\",\"limit\":5,\"whitelist\":[],\"echo\":\"${PO0_TEST_TOKEN:-redacted}\",\"url\":\"https://124.221.69.228/api/firewall/${PO0_TEST_TOKEN:-redacted}\"}"
	;;
oversize)
	oversized="$(awk 'BEGIN { for (i = 0; i < 65537; i++) printf "x" }')"
	emit "${oversized}" 200
	;;
transport-error)
	exit 7
	;;
healthy|*)
	emit "${healthy}" 200
	;;
esac
MOCK

cat > "${bin_dir}/mwan3" <<'MOCK'
#!/bin/sh
set -eu

[ "${1:-}" = 'use' ] || exit 2
wan="${2:-}"
helper="${3:-}"
target="${4:-}"
action="${5:-}"
slot="${6:-}"
[ -n "${wan}" ] && [ -n "${helper}" ] && [ -n "${target}" ] && [ -n "${action}" ] || exit 2
printf '%s\n' "${*}" >> "${PO0_TEST_MWAN_LOG:?}"

if [ "${action}" = 'status' ]; then
	if "${helper}" "${target}" status; then
		helper_rc=0
	else
		helper_rc=$?
	fi
else
	if [ -n "${slot}" ]; then
		if "${helper}" "${target}" add "${slot}"; then
			helper_rc=0
		else
			helper_rc=$?
		fi
	else
		if "${helper}" "${target}" add; then
			helper_rc=0
		else
			helper_rc=$?
		fi
	fi
fi
[ "${PO0_TEST_FAIL_WAN:-}" = "${wan}" ] && exit 9
exit "${helper_rc}"
MOCK

chmod 0700 "${bin_dir}/uci" "${bin_dir}/jsonfilter" "${bin_dir}/curl" "${bin_dir}/mwan3"

token='pgnfw_blackbox_token_should_not_escape'
target_enabled='1'
binding_enabled='1'
binding_slot='0'
multi_bindings='0'
fail_wan=''
LAST_RC=0
export PO0_TEST_CURL_ARGV_LOG="$curl_argv_log"

reset_logs() {
	: > "$curl_argv_log"
: > "${curl_log}"
: > "${mwan_log}"
: > "${jsonfilter_log}"
: > "${stdout_file}"
: > "${stderr_file}"
}

run_runner() {
	local scenario="$1"
	shift
	reset_logs
	set +e
	env \
		"PATH=${bin_dir}:${PATH}" \
		"PO0_TEST_SCENARIO=${scenario}" \
		"PO0_TEST_CURL_LOG=${curl_log}" \
		"PO0_TEST_MWAN_LOG=${mwan_log}" \
		"PO0_TEST_JSONFILTER_LOG=${jsonfilter_log}" \
		"PO0_TEST_TARGET_ENABLED=${target_enabled}" \
		"PO0_TEST_MULTI=${multi_bindings}" \
		"PO0_TEST_FAIL_WAN=${fail_wan}" \
	"PO0_TEST_BINDING_ENABLED=${binding_enabled}" \
	"PO0_TEST_SLOT=${binding_slot}" \
	"PO0_TEST_TOKEN=${token}" \
	sh "${runner}" "$@" >"${stdout_file}" 2>"${stderr_file}"
	LAST_RC=$?
	set -e
}

run_helper() {
	local scenario="$1"
	shift
	reset_logs
	set +e
	env \
		"PATH=${bin_dir}:${PATH}" \
		"PO0_TEST_SCENARIO=${scenario}" \
		"PO0_TEST_CURL_LOG=${curl_log}" \
		"PO0_TEST_MWAN_LOG=${mwan_log}" \
		"PO0_TEST_JSONFILTER_LOG=${jsonfilter_log}" \
		"PO0_TEST_TARGET_ENABLED=${target_enabled}" \
		"PO0_TEST_MULTI=${multi_bindings}" \
		"PO0_TEST_FAIL_WAN=${fail_wan}" \
		"PO0_TEST_BINDING_ENABLED=${binding_enabled}" \
		"PO0_TEST_SLOT=${binding_slot}" \
		"PO0_TEST_TOKEN=${token}" \
		sh "${helper}" "$@" >"${stdout_file}" 2>"${stderr_file}"
	LAST_RC=$?
	set -e
}

assert_rc() {
	[ "${LAST_RC}" -eq "$1" ] ||
		fail "$2 (expected rc $1, got ${LAST_RC})"
}

assert_stdout_line() {
	grep -Fqx -- "$1" "${stdout_file}" ||
		fail "stdout is missing expected line: $1"
}

assert_stdout_has() {
	grep -Fq -- "$1" "${stdout_file}" ||
		fail "stdout is missing expected text: $1"
}

assert_stdout_empty() {
	[ ! -s "${stdout_file}" ] ||
		fail 'stdout unexpectedly contains a response body'
}

assert_stderr_has() {
	grep -Fq -- "$1" "${stderr_file}" ||
		fail "stderr is missing expected text: $1"
}

assert_no_token() {
	if [ -n "${token}" ] &&
		{ grep -Fq -- "${token}" "${stdout_file}" ||
			grep -Fq -- "${token}" "${stderr_file}" ||
			grep -Fq -- "${token}" "${mwan_log}"; }; then
		fail 'official token escaped through stdout/stderr/mwan argv'
	fi
	assert_no_token_in_curl_argv
}

assert_no_token_in_curl_argv() {
	if [ -n "$token" ] && grep -Fq -- "$token" "$curl_argv_log"; then
		fail 'official token escaped through curl argv'
	fi
}

assert_curl_sequence() {
	local expected="$1"
	local actual
	actual="$(tr '\n' ' ' < "${curl_log}" | sed 's/[[:space:]]*$//')"
	[ "${actual}" = "${expected}" ] ||
		fail "unexpected curl sequence (expected '${expected}', got '${actual}')"
}

assert_mwan_sequence() {
	local expected="$1"
	local actual
	actual="$(awk '{print $5}' "${mwan_log}" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
	[ "${actual}" = "${expected}" ] ||
		fail "unexpected mwan3 sequence (expected '${expected}', got '${actual}')"
}

assert_no_requests() {
	[ ! -s "${curl_log}" ] || fail 'unexpected curl request'
	[ ! -s "${mwan_log}" ] || fail 'unexpected mwan3 invocation'
}

run_root_whitelist_cases() {
	# The required whitelist field must be the root array, not merely a
	# nested object with the same key. These status reads fail closed and
	# never POST.
	for scenario in missing-whitelist nested-whitelist whitelist-object; do
		run_runner "${scenario}" status binding1
		assert_rc 1 "${scenario} response was accepted"
		assert_stdout_line 'entry_status=error'
		assert_curl_sequence 'GET'
		assert_mwan_sequence 'status'
		assert_no_token
	done
}

run_helper_sensitive_case() {
	# The helper must reject an upstream body/header that reflects the
	# credential, Authorization marker, or request URL before returning it.
	run_helper curl-echo-sensitive target1 status
	assert_rc 1 'sensitive reflected response was accepted'
	assert_stdout_empty
	assert_stderr_has 'sensitive request data'
	assert_curl_sequence 'GET'
	assert_no_token
	if grep -Eiq 'authorization|https://124\\.221\\.69\\.228/api/firewall' "${stdout_file}" "${stderr_file}"; then
		fail 'sensitive response marker escaped through helper output'
	fi
}

if [ "${PO0_TEST_ONLY:-}" = 'root-whitelist' ]; then
	run_root_whitelist_cases
	printf 'PASS: OpenWrt root whitelist type checks passed.\n'
	exit 0
fi

if [ "${PO0_TEST_ONLY:-}" = 'helper-sensitive' ]; then
	run_helper_sensitive_case
	printf 'PASS: OpenWrt helper response redaction checks passed.\n'
	exit 0
fi

# A healthy 200 response is read-only and is rendered as already_present.
run_runner healthy status binding1
assert_rc 0 'healthy status failed'
assert_stdout_line 'entry_status=already_present'
assert_stdout_line 'entry_current_ip=203.0.113.0/24'
assert_stdout_line 'entry_used=1'
assert_stdout_line 'entry_limit=5'
assert_curl_sequence 'GET'
assert_mwan_sequence 'status'
assert_no_token

# Disabled targets must short-circuit before mwan3/curl.
target_enabled='0'
run_runner healthy status binding1
assert_rc 0 'disabled target status failed'
assert_stdout_line 'entry_status=disabled'
assert_no_requests
assert_no_token
target_enabled='1'

# A 200 response whose current IP is absent from the whitelist is still
# read-only for status and must never trigger the add endpoint. It is a normal
# status result so LuCI can display the current IP and 3/5 state.
run_runner not-whitelisted status binding1
assert_rc 0 'missing whitelist status failed'
assert_stdout_line 'entry_status=missing'
assert_stdout_line 'entry_current_ip=203.0.113.0/24'
assert_stdout_line 'entry_whitelist=198.51.100.0/24'
assert_stdout_line 'entry_used=1'
assert_stdout_line 'entry_limit=5'
assert_curl_sequence 'GET'
assert_mwan_sequence 'status'
assert_no_token

# Report must not POST when the read-only check already confirms the IP.
run_runner healthy report binding1
assert_rc 0 'already-whitelisted report failed'
assert_stdout_line 'entry_status=already_present'
assert_curl_sequence 'GET'
assert_mwan_sequence 'status'
assert_no_token

# Explicit report may perform the status GET followed by one POST/add.
run_runner not-whitelisted report binding1
assert_rc 0 'missing whitelist report failed'
assert_stdout_line 'entry_status=success'
assert_curl_sequence 'GET POST'
assert_mwan_sequence 'status add'
assert_no_token

# A fixed-slot mismatch is not a hit: GET is followed by POST to that slot.
binding_slot='0'
run_runner slot-mismatch report binding1
assert_rc 0 'fixed-slot mismatch report failed'
assert_stdout_line 'entry_status=success'
assert_curl_sequence 'GET POST'
assert_mwan_sequence 'status add'
assert_no_token

# All configured WANs are processed in order, and one failure does not stop
# the next binding; the overall result is partial (rc 1).
multi_bindings='1'
fail_wan='wan2'
binding_slot=''
run_runner not-whitelisted report
assert_rc 1 'partial multi-WAN report did not fail overall'
assert_stdout_line 'entry_wan=wan1'
assert_stdout_line 'entry_wan=wan2'
assert_curl_sequence 'GET POST GET'
assert_mwan_sequence 'status add status'
assert_no_token

# Hotplug/manual filtering must process only the selected logical WAN.
fail_wan=''
run_runner healthy status --official-wan wan2
assert_rc 0 'WAN-filtered status failed'
assert_stdout_line 'entry_wan=wan2'
if grep -Fq 'entry_wan=wan1' "$stdout_file"; then
	fail 'WAN filter processed an unselected binding'
fi
assert_curl_sequence 'GET'
assert_mwan_sequence 'status'
assert_no_token
multi_bindings='0'

# A failed status GET is not permission to fall back to POST.
run_runner get-fail status binding1
assert_rc 1 'status GET failure did not fail'
assert_stdout_line 'entry_status=error'
assert_curl_sequence 'GET'
assert_mwan_sequence 'status'
assert_no_token

# A failed read-only check in report mode is fail-closed: never POST.
run_runner get-fail report binding1
assert_rc 1 'report GET failure did not fail'
assert_stdout_line 'entry_status=error'
assert_curl_sequence 'GET'
assert_mwan_sequence 'status'
assert_no_token

# An invalid 2xx body must not be copied to output (the fake body contains the
# token deliberately); it is a protocol error and remains read-only.
run_runner bad-json status binding1
assert_rc 1 'bad JSON was accepted'
assert_stdout_line 'entry_status=error'
assert_curl_sequence 'GET'
assert_mwan_sequence 'status'
assert_no_token

# The upstream may omit a slot or return JSON null for an unpinned entry;
# this remains a valid status response when no fixed slot is configured.
binding_slot=''
run_runner null-slot status binding1
assert_rc 0 'null whitelist slot was rejected'
assert_stdout_line 'entry_status=already_present'
assert_curl_sequence 'GET'
assert_mwan_sequence 'status'
assert_no_token

run_root_whitelist_cases

# A response with an invalid capacity or whitelist slot is a protocol error;
# report mode remains fail-closed after GET and never falls back to POST.
for scenario in bad-limit bad-slot duplicate-response-slot; do
	run_runner "${scenario}" report binding1
	assert_rc 1 "${scenario} response was accepted"
	assert_stdout_line 'entry_status=error'
	assert_curl_sequence 'GET'
	assert_mwan_sequence 'status'
	assert_no_token
done

# Non-2xx responses are surfaced by the helper as a failure without echoing
# the response body or token.
run_helper http-error target1 status
assert_rc 1 'non-2xx helper response was accepted'
assert_stdout_empty
assert_stderr_has 'official request failed'
assert_curl_sequence 'GET'
assert_no_token

# Curl diagnostics can contain the token-bearing URL, but the helper suppresses
# curl stderr and exposes only a redacted generic result.
run_helper curl-stderr-token target1 status
assert_rc 0 'curl diagnostic stderr made a healthy request fail'
assert_stdout_has '"enabled":true'
assert_no_token

# A response/header that reflects the credential or request URL is rejected
# before the helper can copy it to stdout; the caller sees only a generic
# failure and no sensitive response text.
run_helper_sensitive_case

# The helper rejects bodies larger than the fixed response limit before
# returning them to the caller.
run_helper oversize target1 status
assert_rc 1 'oversized helper response was accepted'
assert_stdout_empty
assert_stderr_has 'body exceeded the limit'
assert_no_token

# The helper accepts only backend slots 0..4. Every valid slot reaches POST.
for slot in 0 1 2 3 4; do
	binding_slot="${slot}"
	run_helper healthy target1 add "${slot}"
	assert_rc 0 "valid slot ${slot} was rejected"
	assert_curl_sequence 'POST'
	assert_no_token
done

# Empty is also valid for add; status never accepts a slot argument.
binding_slot=''
run_helper healthy target1 add
assert_rc 0 'empty add slot was rejected'
assert_curl_sequence 'POST'
assert_no_token

run_helper healthy target1 status 0
assert_rc 1 'status accepted an unexpected slot'
assert_no_requests
assert_no_token

# Out-of-range and malformed slots fail before any network request.
for slot in 5 -1 x; do
	run_helper healthy target1 add "${slot}"
	assert_rc 1 "invalid slot ${slot} reached helper"
	assert_no_requests
	assert_no_token
done

# The package runner applies the same slot boundary to configured bindings.
binding_slot='5'
run_runner healthy status binding1
assert_rc 1 'runner accepted an out-of-range configured slot'
assert_stdout_line 'entry_status=error'
assert_no_requests
assert_no_token

# The ordinary Linux lane has its own mock boundary.  Keep it separate from
# the OpenWrt helper/runner fixtures above: Linux calls curl directly and must
# prove the response/status/temporary-file contract without real networking.
official_linux_src="${repo_root}/scripts/po0/relay/self-report/linux/src/125-official-report.sh"
[[ -r "${official_linux_src}" ]] || fail 'Linux official report core is missing'
linux_dir="${tmp_dir}/linux-core"
linux_bin="${linux_dir}/bin"
linux_requests="${linux_dir}/requests"
linux_state_dir="${linux_dir}/state"
linux_run_state="${linux_state_dir}/official.state"
linux_entry="${linux_dir}/entry"
linux_stdout="${linux_dir}/stdout"
linux_stderr="${linux_dir}/stderr"
linux_request_log="${linux_dir}/requests.log"
linux_argv_log="${linux_dir}/argv.log"
linux_token='pgnfw_linux_mock_token~v1.2'
linux_state="${linux_state_dir}/official.state"
linux_platform="$(uname -s 2>/dev/null || printf 'unknown')"
mkdir -p "${linux_bin}" "${linux_requests}" "${linux_state_dir}"

cat > "${linux_entry}" <<'ENTRY'
#!/usr/bin/env bash
set -uo pipefail

trim() {
	local value="${1:-}"
	value="${value#"${value%%[![:space:]]*}"}"
	value="${value%"${value##*[![:space:]]}"}"
	printf '%s' "${value}"
}

to_lower() {
	printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'
}

max_interval_seconds() {
	printf '604800\n'
}

PO0_FIREWALL_TOKENS="${PO0_TEST_TOKENS:?}"
OFFICIAL_STATE_FILE="${PO0_TEST_STATE_FILE:?}"
OFFICIAL_INTERVAL_SECONDS='600'
FORCE_REPORT='1'
source "${PO0_TEST_OFFICIAL_SRC:?}"
OFFICIAL_STATE_FILE="${PO0_TEST_STATE_FILE:?}"

case "${PO0_TEST_ACTION:?}" in
	status) official_status_once ;;
	report) official_report_once ;;
	*) exit 2 ;;
esac
ENTRY

cat > "${linux_bin}/curl" <<'MOCK'
#!/bin/sh
set -eu

config="$(cat)"
request="$(printf '%s\n' "${config}" | sed -n 's/^request = "\(.*\)"$/\1/p')"
[ -n "${request}" ] || exit 2
printf '%s\n' "${request}" >> "${PO0_TEST_LINUX_REQUEST_LOG:?}"
printf '%s\n' "$*" >> "${PO0_TEST_LINUX_ARGV_LOG:?}"

output_file=''
header_file=''
while [ "$#" -gt 0 ]; do
	case "$1" in
	--output)
		output_file="${2:-}"
		shift 2
		;;
	--dump-header)
		header_file="${2:-}"
		shift 2
		;;
	*)
		shift
		;;
	esac
done

emit() {
	body="$1"
	code="$2"
	[ -n "${output_file}" ] && printf '%s' "${body}" > "${output_file}"
	[ -n "${header_file}" ] && printf 'HTTP/1.1 %s Mock\r\n\r\n' "${code}" > "${header_file}"
	printf '%s' "${code}"
}

healthy='{"enabled":true,"currentIp":"203.0.113.0/24","limit":5,"whitelist":[{"ip":"203.0.113.0/24","slot":0}]}'
missing='{"enabled":true,"currentIp":"203.0.113.0/24","limit":5,"whitelist":[{"ip":"198.51.100.0/24","slot":1}]}'
forged='{"enabled":true,"currentIp":"203.0.113.0/24","limit":5,"meta":{"ip":"203.0.113.0/24"},"whitelist":[{"ip":"198.51.100.0/24","slot":1}]}'
escaped_null='{"enabled":true,"currentIp":"203.0.113.0\/24","limit":5,"whitelist":[{"ip":"203.0.113.0\/24","slot":null}]}'
bad_ip='{"enabled":true,"currentIp":"203.0.113.0/24","limit":5,"whitelist":[{"ip":"999.999.999.0/24","slot":1}]}'
scenario="${PO0_TEST_LINUX_SCENARIO:-healthy}"

case "${scenario}" in
	non2xx)
		emit '{"error":"upstream failure"}' 503
		;;
	oversize-body)
		oversized="$(awk 'BEGIN { for (i = 0; i < 65537; i++) printf "x" }')"
		emit "${oversized}" 200
		;;
	oversize-header)
		[ -n "${output_file}" ] && printf '%s' "${healthy}" > "${output_file}"
		awk 'BEGIN { for (i = 0; i < 16385; i++) printf "h" }' > "${header_file}"
		printf '200'
		;;
	forged-ip)
		emit "${forged}" 200
		;;
	bad-whitelist-ip)
		emit "${bad_ip}" 200
		;;
	escaped-null)
		emit "${escaped_null}" 200
		;;
	stderr-token)
		printf 'mock curl diagnostic token=%s\n' "${PO0_TEST_LINUX_TOKEN:?}" >&2
		emit "${healthy}" 200
		;;
	not-whitelisted)
		if [ "${request}" = 'GET' ]; then
			emit "${missing}" 200
		else
			emit "${healthy}" 200
		fi
		;;
	healthy|*)
		emit "${healthy}" 200
		;;
esac
MOCK
chmod 0700 "${linux_entry}" "${linux_bin}/curl"

LAST_LINUX_RC=0
run_linux() {
	local scenario="$1" action="$2" run_state="${linux_run_state}"
	if [ "${run_state}" = "${linux_state}" ]; then
		rm -rf "${linux_state_dir}"
		mkdir -p "${linux_state_dir}"
	else
		rm -f "${run_state}"
	fi
	: > "${linux_request_log}"
	: > "${linux_argv_log}"
	: > "${linux_stdout}"
	: > "${linux_stderr}"
	set +e
	env \
		"PATH=${linux_bin}:${PATH}" \
		"TMPDIR=${linux_requests}" \
		"PO0_TEST_LINUX_SCENARIO=${scenario}" \
		"PO0_TEST_LINUX_TOKEN=${linux_token}" \
		"PO0_TEST_LINUX_REQUEST_LOG=${linux_request_log}" \
		"PO0_TEST_LINUX_ARGV_LOG=${linux_argv_log}" \
		"PO0_TEST_OFFICIAL_SRC=${official_linux_src}" \
		"PO0_TEST_TOKENS=${linux_token}" \
		"PO0_TEST_STATE_FILE=${run_state}" \
		"PO0_TEST_ACTION=${action}" \
		"PO0_OUTBOUND_IP_REPORT_OFFICIAL_NOW=1700000000" \
		bash "${linux_entry}" > "${linux_stdout}" 2> "${linux_stderr}"
	LAST_LINUX_RC=$?
	set -e
}

assert_linux_rc() {
	[ "${LAST_LINUX_RC}" -eq "$1" ] ||
		fail "$2 (expected rc $1, got ${LAST_LINUX_RC})"
}

assert_linux_stdout_has() {
	grep -Fq -- "$1" "${linux_stdout}" ||
		fail "Linux stdout is missing expected text: $1"
}

assert_linux_stderr_has() {
	grep -Fq -- "$1" "${linux_stderr}" ||
		fail "Linux stderr is missing expected text: $1"
}

assert_linux_requests() {
	local expected="$1" actual
	actual="$(tr '\n' ' ' < "${linux_request_log}" | sed 's/[[:space:]]*$//')"
	[ "${actual}" = "${expected}" ] ||
		fail "unexpected Linux request sequence (expected '${expected}', got '${actual}')"
}

assert_linux_no_token() {
	for file in "${linux_stdout}" "${linux_stderr}" "${linux_argv_log}"; do
		if grep -Fq -- "${linux_token}" "${file}"; then
			fail 'Linux official token escaped through output or curl argv'
		fi
	done
}

assert_linux_temp_clean() {
	[ -z "$(find "${linux_requests}" -mindepth 1 -maxdepth 1 -print -quit)" ] ||
		fail 'Linux request temporary directory was not cleaned up'
}

if [ "${PO0_TEST_ONLY:-}" = 'linux-forged' ]; then
	# An IP-looking field outside the strict response schema must not be treated
	# as a whitelist hit; the response is rejected before any state is saved.
	run_linux forged-ip status
	assert_linux_rc 1 'out-of-array forged IP response was accepted'
	assert_linux_requests 'GET'
	assert_linux_stderr_has '状态无效'
	assert_linux_no_token
	assert_linux_temp_clean
	printf 'PASS: Linux out-of-array IP check passed.\n'
	exit 0
fi

# A healthy 2xx response is accepted; the token is not present in curl argv
# even though the mock writes the entire argv for inspection.
run_linux healthy status
assert_linux_rc 0 'healthy Linux status failed'
assert_linux_stdout_has '官方防火墙只读检查完成'
assert_linux_requests 'GET'
assert_linux_no_token
assert_linux_temp_clean

# Explicit HTTP status validation rejects non-2xx without falling through to
# an add request or exposing the response body.
run_linux non2xx status
assert_linux_rc 1 'non-2xx Linux response was accepted'
assert_linux_requests 'GET'
assert_linux_stderr_has 'HTTP 503'
assert_linux_no_token
assert_linux_temp_clean

# Body and header limits are enforced after curl writes to private 0600 files.
run_linux oversize-body status
assert_linux_rc 1 'oversized Linux body was accepted'
assert_linux_requests 'GET'
assert_linux_stderr_has '64K limit'
assert_linux_no_token
assert_linux_temp_clean

run_linux oversize-header status
assert_linux_rc 1 'oversized Linux headers were accepted'
assert_linux_requests 'GET'
assert_linux_stderr_has '16K limit'
assert_linux_no_token
assert_linux_temp_clean

# A same-looking IP outside the whitelist array is outside the strict
# response schema and must not count as a hit.
run_linux forged-ip status
assert_linux_rc 1 'out-of-array forged IP response was accepted'
assert_linux_requests 'GET'
assert_linux_stderr_has '状态无效'
assert_linux_no_token
assert_linux_temp_clean

# Every whitelist IP is strict IPv4 /24; invalid entries fail the protocol
# validation before any add operation.
run_linux bad-whitelist-ip status
assert_linux_rc 1 'invalid whitelist IPv4 was accepted'
assert_linux_requests 'GET'
assert_linux_stderr_has '状态无效'
assert_linux_no_token
assert_linux_temp_clean

# Upstream-compatible escaped slashes and null slots remain valid when no slot
# pin was requested.
run_linux escaped-null status
assert_linux_rc 0 'escaped-slash/null-slot response failed'
assert_linux_requests 'GET'
assert_linux_no_token
assert_linux_temp_clean

# Curl stderr is suppressed at the direct-request boundary; this fixture puts
# the token in that diagnostic and verifies it never reaches the caller.
run_linux stderr-token status
assert_linux_rc 0 'curl stderr token fixture failed'
assert_linux_requests 'GET'
assert_linux_no_token
assert_linux_temp_clean

# Report mode may perform GET then POST, and the state replacement is private,
# atomic, and cleaned up rather than using a predictable state.tmp.$$ path.
run_linux not-whitelisted report
assert_linux_rc 0 'Linux report mode failed to add missing IP'
assert_linux_requests 'GET POST'
assert_linux_no_token
assert_linux_temp_clean
state_mode="$(stat -c '%a' "${linux_state}" 2>/dev/null || true)"
if [[ "${linux_platform}" != MINGW* && "${linux_platform}" != MSYS* ]]; then
	[ "${state_mode}" = '600' ] || fail "Linux state file mode is ${state_mode}, expected 600"
fi
[ -z "$(find "${linux_state_dir}" -maxdepth 1 -name '.po0-official-state.*' -print -quit)" ] ||
	fail 'Linux state temporary file was not cleaned up'
grep -Fq -- 'mktemp "${dir%/}/.po0-official-state.XXXXXX"' "${official_linux_src}" ||
	fail 'Linux state writer is missing same-directory mktemp'
if grep -Fq -- 'tmp="${state}.tmp.$$"' "${official_linux_src}"; then
	fail 'Linux state writer still uses predictable state.tmp.$$'
fi
custom_state_dir="${linux_dir}/existing-custom-state"
custom_state="${custom_state_dir}/official.state"
mkdir -p "${custom_state_dir}"
chmod 750 "${custom_state_dir}"
custom_state_mode_before="$(stat -c '%a' "${custom_state_dir}" 2>/dev/null || true)"
linux_run_state="${custom_state}"
run_linux healthy report
assert_linux_rc 0 'Linux report rejected a safe existing custom state parent'
assert_linux_requests 'GET'
custom_state_mode_after="$(stat -c '%a' "${custom_state_dir}" 2>/dev/null || true)"
[ "${custom_state_mode_after}" = "${custom_state_mode_before}" ] ||
	fail 'Linux state writer changed permissions on an existing custom parent'
linux_run_state="${linux_state}"
default_state="$(env -u HOME -u XDG_STATE_HOME -u OFFICIAL_STATE_FILE -u PO0_OUTBOUND_IP_REPORT_OFFICIAL_STATE_FILE -u TMPDIR \
	bash -c 'trim(){ printf "%s" "$1"; }; source "$1"; official_state_file' bash "${official_linux_src}")"
default_state_dir="$(dirname "${default_state}")"
[ "${default_state_dir}" != '/tmp' ] || fail 'Linux default state/lock directory is the shared /tmp'
grep -Fq -- '--max-filesize 65536' "${official_linux_src}" ||
	fail 'Linux direct request is missing curl transfer-size cap'
grep -Fq -- 'Behavior reference: https://github.com/kelenetwork/po0fw (MIT).' "${official_linux_src}" ||
	fail 'Linux core is missing the upstream behavior reference'
grep -Fq -- 'trap '\''rm -rf -- "${request_dir}"'\'' EXIT' "${official_linux_src}" ||
	fail 'Linux direct request is missing EXIT cleanup trap'
grep -Fq -- 'trap '\''rm -rf -- "${request_dir}"; exit 129'\'' HUP' "${official_linux_src}" ||
	fail 'Linux direct request is missing HUP exit trap'
grep -Fq -- 'trap '\''rm -rf -- "${request_dir}"; exit 130'\'' INT' "${official_linux_src}" ||
	fail 'Linux direct request is missing INT exit trap'
grep -Fq -- 'trap '\''rm -rf -- "${request_dir}"; exit 143'\'' TERM' "${official_linux_src}" ||
	fail 'Linux direct request is missing TERM exit trap'
if grep -Fq -- 'trap '\''rm -rf -- "${request_dir}"'\'' EXIT HUP INT TERM' "${official_linux_src}"; then
	fail 'Linux direct request still combines cleanup and signal traps'
fi

printf 'PASS: official firewall helper/runner black-box checks passed.\n'
