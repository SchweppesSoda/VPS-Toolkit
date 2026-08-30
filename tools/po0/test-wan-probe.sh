#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
mkdir -p "${repo_root}/.tmp"
tmp_dir="$(mktemp -d "${repo_root}/.tmp/po0-wan-probe-test.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT
asset_dir="${tmp_dir}/assets"
mock_bin="${tmp_dir}/bin"
mkdir -p "${mock_bin}"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

bash "${repo_root}/tools/po0/build-po0-assets.sh" "${asset_dir}" >/dev/null

cat > "${mock_bin}/uci" <<'MOCK'
#!/bin/sh
case "$*" in
    '-q show mwan3') printf '%s\n' 'mwan3.wan1=interface' 'mwan3.wan2=interface' ;;
    '-q get mwan3.wan1.enabled'|'-q get mwan3.wan2.enabled') printf '1\n' ;;
    *) exit 1 ;;
esac
MOCK

cat > "${mock_bin}/ubus" <<'MOCK'
#!/bin/sh
case "$2" in
    network.interface.wan1) printf '%s\n' '{"up":true,"l3_device":"pppoe-wan1","ipv4-address":[{"address":"203.0.113.11"}]}' ;;
    network.interface.wan2) printf '%s\n' '{"up":true,"l3_device":"pppoe-wan2","ipv4-address":[{"address":"10.0.0.2"}]}' ;;
    *) exit 1 ;;
esac
MOCK

cat > "${mock_bin}/jsonfilter" <<'MOCK'
#!/bin/sh
input="$(cat)"
expr="${2:-}"
case "${expr}" in
    '@.up') printf 'true\n' ;;
    '@.l3_device')
        case "${input}" in *pppoe-wan1*) printf 'pppoe-wan1\n' ;; *) printf 'pppoe-wan2\n' ;; esac
        ;;
    '@["ipv4-address"][0].address')
        case "${input}" in *203.0.113.11*) printf '203.0.113.11\n' ;; *) printf '10.0.0.2\n' ;; esac
        ;;
    *) exit 1 ;;
esac
MOCK

cat > "${mock_bin}/curl" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> "${PO0_TEST_CURL_LOG}"
printf '198.51.100.22\n'
MOCK
chmod +x "${mock_bin}"/*

run_probe() {
    PATH="${mock_bin}:${PATH}" PO0_TEST_CURL_LOG="${tmp_dir}/curl.log" \
        REQUEST_METHOD="${1}" REMOTE_ADDR="${2}" QUERY_STRING="${3}" \
        sh "${asset_dir}/po0-wan-probe.sh"
}

output="$(run_probe GET 192.168.88.2 'wan=list')"
grep -Fq $'wan1\nwan2' <<< "${output}" || fail 'list should contain both enabled WANs'

: > "${tmp_dir}/curl.log"
output="$(run_probe GET 192.168.88.2 'wan=wan1')"
grep -Fq '203.0.113.11' <<< "${output}" || fail 'wan1 should use its assigned public address'
[[ ! -s "${tmp_dir}/curl.log" ]] || fail 'public interface address should not call an external detector'

output="$(run_probe GET 192.168.88.2 'wan=wan2')"
grep -Fq '198.51.100.22' <<< "${output}" || fail 'private interface address should fall back to external detection'
grep -Fq -- '--interface pppoe-wan2' "${tmp_dir}/curl.log" || fail 'external detection should bind wan2 l3_device'

output="$(run_probe GET 192.168.88.2 'wan=all')"
grep -Fq 'Content-Type: application/json' <<< "${output}" || fail 'wan=all should return JSON'
grep -Fq '"name":"wan1"' <<< "${output}" || fail 'batch JSON should contain wan1'
grep -Fq '"name":"wan2"' <<< "${output}" || fail 'batch JSON should contain wan2'

output="$(run_probe GET 192.168.88.99 'wan=list')"
grep -Fq 'Status: 403 Forbidden' <<< "${output}" || fail 'unexpected source should be forbidden'
output="$(run_probe POST 192.168.88.2 'wan=list')"
grep -Fq 'Status: 405 Method Not Allowed' <<< "${output}" || fail 'non-GET request should be rejected'
output="$(run_probe GET 192.168.88.2 'wan=bad%20wan')"
grep -Fq 'Status: 400 Bad Request' <<< "${output}" || fail 'invalid WAN should be rejected'

printf 'OpenWrt WAN probe tests passed.\n'
