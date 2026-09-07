#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ui="${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/www/luci-static/resources/view/po0/outbound-ip-report.js"
menu="${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/usr/share/luci/menu.d/po0-outbound-ip-report.json"
acl="${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/usr/share/rpcd/acl.d/po0-outbound-ip-report.json"

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	exit 1
}

[[ -r "${ui}" ]] || fail "LuCI view is missing"
[[ -r "${menu}" ]] || fail "LuCI menu is missing"
[[ -r "${acl}" ]] || fail "LuCI ACL is missing"

grep -Fq "'require uci';" "${ui}" || fail "LuCI view does not load UCI"
grep -Fq "form.TableSection, 'official_target'" "${ui}" || fail "official target table is missing"
grep -Fq "form.TableSection, 'official_binding'" "${ui}" || fail "official binding table is missing"
grep -Fq "'worker_enabled'" "${ui}" || fail "independent Worker switch is missing"
grep -Fq "'official_enabled'" "${ui}" || fail "official switch is missing"
grep -Fq "'official_source_' + wan" "${ui}" || fail "gateway WAN source settings are missing"
for key in official_interval_seconds worker_network_enabled official_network_enabled worker_timer_enabled official_timer_enabled; do
	grep -Fq "$key" "${ui}" || fail "independent trigger setting is missing: $key"
done
grep -Fq "String(slot - 1)" "${ui}" || fail "UI does not map slot 1-5 to backend slot 0-4"
grep -Fq "'official-status'" "${ui}" || fail "read-only official status action is missing"
grep -Fq "channel + '-report'" "${ui}" || fail "explicit official report action is missing"
grep -Fq "pgnfw[_-][A-Za-z0-9._~-]+" "${ui}" || fail "official token redaction does not cover the full token character set"
grep -Fq "PO0 官方防火墙状态" "${ui}" || fail "official status table heading is missing"
grep -Fq "status === 'missing'" "${ui}" || fail "normal missing status is not rendered as a distinct state"
grep -Fq "当前出口尚未加白" "${ui}" || fail "missing status summary is missing"

grep -Fq "o.password = false" "${ui}" || fail "tokens must be visible in configuration"
grep -Fq "s.tab('worker'" "${ui}" || fail "Worker channel tab is missing"
grep -Fq "s.tab('official'" "${ui}" || fail "official channel tab is missing"
grep -Fq "保存配置" "${ui}" || fail "consistent save/report action is missing"
grep -Fq "必须包含 pgnfw_ 前缀" "${ui}" || fail "full token explanation is missing"

grep -Fq "'probe_dns_server'" "${ui}" || fail "real DNS server setting is missing"
grep -Fq "o.default = '192.168.88.1'" "${ui}" || fail "probe DNS default must use the upstream router"
grep -Fq "'192.168.88.250' : '192.168.88.251'" "${ui}" || fail "dedicated WAN source examples are missing"
grep -Fq "提交使用本机正常网络，遵循 OpenClash 规则" "${ui}" || fail "Worker submission routing explanation is missing"
if grep -Eq 'direct_probe_resolve|103\.217\.192\.99' "${ui}"; then
    fail "LuCI must not restore static probe server resolution"
fi


if command -v node >/dev/null 2>&1; then
	node --check "${ui}"
	node - "${ui}" <<'NODE'
const fs = require('fs');
const source = fs.readFileSync(process.argv[2], 'utf8');
if (!source.includes('pgnfw[_-][A-Za-z0-9._~-]+'))
  throw new Error('full official token character set is not covered');
const mask = /pgnfw[_-][A-Za-z0-9._~-]+/gi;
for (const token of ['pgnfw_a.b~c-9', 'PGNFW_x.y~z']) {
  if (token.replace(mask, '[已隐藏]') !== '[已隐藏]')
    throw new Error(`token was not fully masked: ${token}`);
}
NODE
fi

if command -v node >/dev/null 2>&1; then
node - "${menu}" "${acl}" <<'NODE'
const fs = require('fs');
for (const file of process.argv.slice(2)) {
  JSON.parse(fs.readFileSync(file, 'utf8'));
}
NODE
fi

printf 'PASS: OpenWrt LuCI official firewall UI checks passed.\n'
