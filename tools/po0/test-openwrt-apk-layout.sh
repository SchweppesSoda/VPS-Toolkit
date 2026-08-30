#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"

required=(
    packaging/openwrt/po0-wan-probe/Makefile
    packaging/openwrt/po0-wan-probe/files/etc/config/po0_wan_probe
    packaging/openwrt/po0-wan-probe/files/usr/libexec/po0-wan-probe-control
    packaging/openwrt/po0-outbound-ip-report/Makefile
    packaging/openwrt/po0-outbound-ip-report/runtime-manifest.txt
    packaging/openwrt/po0-outbound-ip-report/runtime-header.sh
    packaging/openwrt/po0-outbound-ip-report/runtime-dispatch.sh
    packaging/openwrt/po0-outbound-ip-report/files/etc/config/po0_outbound_ip_report
    packaging/openwrt/po0-outbound-ip-report/files/etc/init.d/po0-outbound-ip-report
    packaging/openwrt/po0-outbound-ip-report/files/usr/sbin/po0-outbound-ip-report
    packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-uci
    packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-service
    packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-control
    packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-migrate
    tools/po0/build-openwrt-reporter-runtime.sh
)

for file in "${required[@]}"; do
    [[ -s "${repo_root}/${file}" ]] || { printf 'Missing APK source file: %s\n' "${file}" >&2; exit 1; }
done

for file in \
    packaging/openwrt/po0-wan-probe/files/usr/libexec/po0-wan-probe-control \
    packaging/openwrt/po0-outbound-ip-report/files/etc/init.d/po0-outbound-ip-report \
    packaging/openwrt/po0-outbound-ip-report/files/usr/sbin/po0-outbound-ip-report \
    packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-uci \
    packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-service \
    packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-control \
    packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-migrate \
    tools/po0/build-openwrt-reporter-runtime.sh \
    tools/po0/build-po0-apks.sh; do
    sh -n "${repo_root}/${file}"
done

for package in po0-wan-probe po0-outbound-ip-report; do
    grep -Fq 'PKGARCH:=all' "${repo_root}/packaging/openwrt/${package}/Makefile"
    grep -Fq 'PKG_VERSION:=2026.08.30' "${repo_root}/packaging/openwrt/${package}/Makefile"
    grep -Fq 'PKG_RELEASE:=3' "${repo_root}/packaging/openwrt/${package}/Makefile"
    grep -Fq "$(printf '$(TOPDIR)/po0-assets')" "${repo_root}/packaging/openwrt/${package}/Makefile"
done

grep -Fq 'exec /usr/libexec/po0-outbound-ip-report-engine "$@"' \
    "${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-uci"
grep -Fq -- '--run-once)' \
    "${repo_root}/scripts/po0/relay/self-report/linux/src/990-cli-parse-dispatch.sh"

runtime_test="$(mktemp "${TMPDIR:-/tmp}/po0-openwrt-runtime.XXXXXX")"
trap 'rm -f "${runtime_test}"' EXIT
bash "${repo_root}/tools/po0/build-openwrt-reporter-runtime.sh" "${runtime_test}"
bash -n "${runtime_test}"
grep -Fq 'report_once' "${runtime_test}"
if grep -Eq 'menu_loop|install_cron|remove_cron|upgrade_self_from_download|uninstall_self_report_interactive' "${runtime_test}"; then
    printf 'OpenWrt APK runtime must not contain menu, cron, self-update, or uninstall actions.\n' >&2
    exit 1
fi

if command -v jq >/dev/null 2>&1; then
    find "${repo_root}/packaging/openwrt" -type f -name '*.json' -print0 | xargs -0 -n1 jq empty
fi
if command -v node >/dev/null 2>&1; then
    find "${repo_root}/packaging/openwrt" -type f -name '*.js' -print0 | xargs -0 -n1 node --check
    node "${repo_root}/tools/po0/test-openwrt-luci-result.mjs"
fi

grep -Fq "option secret ''" "${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/etc/config/po0_outbound_ip_report"
if rg -n 'SECRET|secret' "${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/etc/config/po0_outbound_ip_report" | grep -v "option secret ''"; then
    printf 'Default reporter UCI config must not contain a secret.\n' >&2
    exit 1
fi

printf 'OpenWrt APK layout tests passed.\n'
