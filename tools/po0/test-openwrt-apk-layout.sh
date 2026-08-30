#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"

required=(
    packaging/openwrt/po0-wan-probe/Makefile
    packaging/openwrt/po0-wan-probe/files/etc/config/po0_wan_probe
    packaging/openwrt/po0-wan-probe/files/usr/libexec/po0-wan-probe-control
    packaging/openwrt/po0-outbound-ip-report/Makefile
    packaging/openwrt/po0-outbound-ip-report/files/etc/config/po0_outbound_ip_report
    packaging/openwrt/po0-outbound-ip-report/files/etc/init.d/po0-outbound-ip-report
    packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-uci
    packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-service
    packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-control
    packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-migrate
)

for file in "${required[@]}"; do
    [[ -s "${repo_root}/${file}" ]] || { printf 'Missing APK source file: %s\n' "${file}" >&2; exit 1; }
done

for file in \
    packaging/openwrt/po0-wan-probe/files/usr/libexec/po0-wan-probe-control \
    packaging/openwrt/po0-outbound-ip-report/files/etc/init.d/po0-outbound-ip-report \
    packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-uci \
    packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-service \
    packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-control \
    packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-migrate \
    tools/po0/build-po0-apks.sh; do
    sh -n "${repo_root}/${file}"
done

for package in po0-wan-probe po0-outbound-ip-report; do
    grep -Fq 'PKGARCH:=all' "${repo_root}/packaging/openwrt/${package}/Makefile"
    grep -Fq 'PKG_VERSION:=2026.08.30' "${repo_root}/packaging/openwrt/${package}/Makefile"
    grep -Fq 'PKG_RELEASE:=1' "${repo_root}/packaging/openwrt/${package}/Makefile"
    grep -Fq "$(printf '$(TOPDIR)/po0-assets')" "${repo_root}/packaging/openwrt/${package}/Makefile"
done

if command -v jq >/dev/null 2>&1; then
    find "${repo_root}/packaging/openwrt" -type f -name '*.json' -print0 | xargs -0 -n1 jq empty
fi
if command -v node >/dev/null 2>&1; then
    find "${repo_root}/packaging/openwrt" -type f -name '*.js' -print0 | xargs -0 -n1 node --check
fi

grep -Fq "option secret ''" "${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/etc/config/po0_outbound_ip_report"
if rg -n 'SECRET|secret' "${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/etc/config/po0_outbound_ip_report" | grep -v "option secret ''"; then
    printf 'Default reporter UCI config must not contain a secret.\n' >&2
    exit 1
fi

printf 'OpenWrt APK layout tests passed.\n'
