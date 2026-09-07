#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
pkg="$repo_root/packaging/openwrt/po0-outbound-ip-report"
files="$pkg/files"
for file in "$files"/usr/libexec/* "$files"/usr/sbin/* "$files"/etc/init.d/* "$files"/etc/hotplug.d/iface/*; do sh -n "$file"; done
version="$(sed -n 's/^SCRIPT_VERSION="\([^"]*\)"/\1/p' "$pkg/runtime-header.sh")"
date="$(sed -n 's/^PKG_VERSION:=//p' "$pkg/Makefile")"
release="$(sed -n 's/^PKG_RELEASE:=//p' "$pkg/Makefile")"
[[ "$version" == "$date+build.$release" ]]
[[ "$(sh "$files/usr/sbin/po0-outbound-ip-report" --version)" == "po0-outbound-ip-report $version (OpenWrt APK)" ]]
grep -Fq 'PKGARCH:=all' "$pkg/Makefile"
grep -Fq '$(TOPDIR)/po0-assets' "$pkg/Makefile"
grep -Fq 'outbound-ip-report-v12' "$pkg/Makefile"
grep -Fq 'outbound-ip-report-v12' "$files/usr/share/luci/menu.d/po0-outbound-ip-report.json"
grep -Fq '$(INSTALL_CONF) ./files/etc/config/po0_outbound_ip_report' "$pkg/Makefile"
grep -Fq 'chmod 600 $(1)/etc/config/po0_outbound_ip_report' "$pkg/Makefile"
! grep -Fq '+mwan3' "$pkg/Makefile"
! grep -Eq 'option (secret|worker_|source_id|identity)' "$files/etc/config/po0_outbound_ip_report"
! grep -Eq "tab\('worker'|'worker_enabled'|'worker_url'" "$files/www/luci-static/resources/view/po0/outbound-ip-report.js"
grep -Fq "option official_interval_seconds '600'" "$files/etc/config/po0_outbound_ip_report"
for name in po0-official-firewall-request po0-official-firewall-runner; do
 for signal in HUP INT TERM; do grep -Eq "trap handle_[a-z]+ $signal" "$files/usr/libexec/$name"; done
 grep -Fq 'trap cleanup_tmp_dir EXIT' "$files/usr/libexec/$name"
done
! grep -Eq "LOCK_DIR='/tmp|/tmp/po0-outbound-ip-report.run.lock" "$files/usr/libexec/po0-outbound-ip-report-uci"
for test in test-openwrt-manual-runner.sh test-official-firewall-core.sh test-openwrt-official-adapter.sh test-openwrt-service.sh test-openwrt-hotplug.sh test-openwrt-luci-official-ui.sh test-openwrt-runtime.sh test-openwrt-reporter-migration.sh; do
 bash "$repo_root/tools/po0/$test"
done
node --check "$files/www/luci-static/resources/view/po0/outbound-ip-report.js"
node "$repo_root/tools/po0/test-openwrt-luci-result.mjs"
printf 'OpenWrt official-only APK layout and runtime checks passed.\n'
