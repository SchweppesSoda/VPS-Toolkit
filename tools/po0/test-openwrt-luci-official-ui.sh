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

rg -Fq "'require uci';" "${ui}" || fail "LuCI view does not load UCI"
rg -Fq "form.TableSection, 'official_target'" "${ui}" || fail "official target table is missing"
rg -Fq "form.TableSection, 'official_binding'" "${ui}" || fail "official binding table is missing"
rg -Fq "'worker_enabled'" "${ui}" || fail "independent Worker switch is missing"
rg -Fq "'official_enabled'" "${ui}" || fail "official switch is missing"
rg -Fq "官方自动通道固定每 600 秒检查一次" "${ui}" || fail "official fixed interval explanation is missing"
if rg -Fq "official_interval_seconds" "${ui}"; then
	fail "LuCI must not expose a free-form official interval"
fi
rg -Fq "String(slot - 1)" "${ui}" || fail "UI does not map slot 1-5 to backend slot 0-4"
rg -Fq "'official-status'" "${ui}" || fail "read-only official status action is missing"
rg -Fq "'official-report'" "${ui}" || fail "explicit official report action is missing"
rg -Fq "o.cfgvalue = function()" "${ui}" || fail "official token field may echo a saved token"
rg -Fq "不会显示已保存内容" "${ui}" || fail "official token redaction explanation is missing"
rg -Fq "pgnfw[_-][A-Za-z0-9._~-]+" "${ui}" || fail "official token redaction does not cover the full token character set"
rg -Fq "主路由的 PO0 官方 WAN 绑定不套用 SSID 跳过" "${ui}" || fail "SSID scope explanation is missing"
rg -Fq "PO0 官方防火墙状态" "${ui}" || fail "official status table heading is missing"
rg -Fq "status === 'missing'" "${ui}" || fail "normal missing status is not rendered as a distinct state"
rg -Fq "当前出口尚未加白" "${ui}" || fail "missing status summary is missing"

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
