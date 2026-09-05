#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
tmp_dir="$(mktemp -d "${repo_root}/.tmp/po0-linux-official-cli.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

asset_dir="${tmp_dir}/asset"
mkdir -p "${asset_dir}"
"${repo_root}/tools/po0/build-po0-assets.sh" "${asset_dir}" >/dev/null

# An official status check must reach the official lane even when stale or
# malformed optional Worker settings are present.  The invalid token makes the
# official lane fail before transport, so this fixture never calls a network
# endpoint.
set +e
output="$(
    env \
        "PO0_OUTBOUND_IP_REPORT_CONFIG=${tmp_dir}/settings.env" \
        'PO0_FIREWALL_TOKENS=not-a-token' \
        'PO0_OUTBOUND_IP_REPORT_WANS=bad?' \
        'PO0_OUTBOUND_IP_REPORT_ROUTER_PROBE_URL=not-a-url' \
        'PO0_OUTBOUND_IP_REPORT_INTERVAL_SECONDS=not-an-interval' \
        bash "${asset_dir}/po0-outbound-ip-report.sh" --official-status 2>&1
)"
rc=$?
set -e

[[ "${rc}" == "1" ]] || fail "official status returned unexpected rc ${rc}"
[[ "${output}" == *"官方防火墙 token 配置无效"* ]] || fail "official status did not reach official validation"
[[ "${output}" != *"上游路由器 WAN 探针 URL 无效"* ]] || fail "official status was blocked by Worker router validation"
[[ "${output}" != *"上报间隔秒数无效"* ]] || fail "official status was blocked by Worker interval validation"

printf 'PASS: Linux official status remains independent from Worker validation.\n'
