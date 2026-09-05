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
    packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-manual-runner
    packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-migrate
    packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-official-firewall-request
    packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-official-firewall-runner
    packaging/openwrt/po0-outbound-ip-report/files/etc/hotplug.d/iface/95-po0-outbound-ip-report
    tools/po0/build-openwrt-reporter-runtime.sh
    tools/po0/test-openwrt-manual-runner.sh
    tools/po0/test-official-firewall-core.sh
    tools/po0/test-openwrt-official-adapter.sh
    tools/po0/test-openwrt-service.sh
    tools/po0/test-openwrt-luci-official-ui.sh
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
    packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-manual-runner \
    packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-migrate \
    packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-official-firewall-request \
    packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-official-firewall-runner \
    packaging/openwrt/po0-outbound-ip-report/files/etc/hotplug.d/iface/95-po0-outbound-ip-report \
    tools/po0/build-openwrt-reporter-runtime.sh \
    tools/po0/test-openwrt-manual-runner.sh \
    tools/po0/build-po0-apks.sh; do
    sh -n "${repo_root}/${file}"
done
bash -n "${repo_root}/tools/po0/test-official-firewall-core.sh"
bash -n "${repo_root}/tools/po0/test-openwrt-official-adapter.sh"
bash -n "${repo_root}/tools/po0/test-openwrt-service.sh"
bash -n "${repo_root}/tools/po0/test-openwrt-luci-official-ui.sh"

bash "${repo_root}/tools/po0/test-openwrt-manual-runner.sh"
bash "${repo_root}/tools/po0/test-official-firewall-core.sh"
bash "${repo_root}/tools/po0/test-openwrt-official-adapter.sh"
bash "${repo_root}/tools/po0/test-openwrt-service.sh"
bash "${repo_root}/tools/po0/test-openwrt-luci-official-ui.sh"

for package in po0-wan-probe; do
    grep -Fq 'PKGARCH:=all' "${repo_root}/packaging/openwrt/${package}/Makefile"
    grep -Fq 'PKG_VERSION:=2026.08.30' "${repo_root}/packaging/openwrt/${package}/Makefile"
    grep -Fq 'PKG_RELEASE:=5' "${repo_root}/packaging/openwrt/${package}/Makefile"
    grep -Fq "$(printf '$(TOPDIR)/po0-assets')" "${repo_root}/packaging/openwrt/${package}/Makefile"
done

for package in po0-outbound-ip-report; do
    grep -Fq 'PKGARCH:=all' "${repo_root}/packaging/openwrt/${package}/Makefile"
    grep -Fq 'PKG_VERSION:=2026.09.05' "${repo_root}/packaging/openwrt/${package}/Makefile"
    grep -Fq 'PKG_RELEASE:=1' "${repo_root}/packaging/openwrt/${package}/Makefile"
    grep -Fq "$(printf '$(TOPDIR)/po0-assets')" "${repo_root}/packaging/openwrt/${package}/Makefile"
    grep -Fq 'SCRIPT_VERSION="2026.09.05+build.2"' \
        "${repo_root}/packaging/openwrt/${package}/runtime-header.sh"
    grep -Fq 'po0-outbound-ip-report 2026.09.05+build.2 (OpenWrt APK)' \
        "${repo_root}/packaging/openwrt/${package}/files/usr/sbin/po0-outbound-ip-report"
done

grep -Fq "ENGINE='/usr/libexec/po0-outbound-ip-report-engine'" \
    "${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-uci"
grep -Fq "OFFICIAL_RUNNER='/usr/libexec/po0-official-firewall-runner'" \
    "${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-uci"
grep -Fq -- '--official-wan' \
    "${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-uci"
grep -Fq 'test-start)' \
    "${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-control"
grep -Fq 'test-status)' \
    "${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-control"
grep -Fq 'start-stop-daemon -S -b' \
    "${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-control"
grep -Fq "printf 'finished_at=%s" \
    "${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-service"
grep -Fq 'po0-outbound-ip-report-manual-runner' \
    "${repo_root}/packaging/openwrt/po0-outbound-ip-report/Makefile"
grep -Fq '$(INSTALL_CONF) ./files/etc/config/po0_outbound_ip_report' \
    "${repo_root}/packaging/openwrt/po0-outbound-ip-report/Makefile"
grep -Fq "chmod 600 \"\$CONFIG_FILE\"" \
    "${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/etc/init.d/po0-outbound-ip-report"
grep -Fq 'chmod 600 /etc/config/po0_outbound_ip_report' \
    "${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-migrate"
grep -Fq "RUN_DIR='/var/run/po0-outbound-ip-report'" \
    "${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-uci"
grep -Fq '[ "${#1}" -le 64 ]' \
    "${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-uci"
grep -Fq '[ "${#remainder}" -le 240 ]' \
    "${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-uci"
grep -Fq "RUN_DIR='/var/run/po0-outbound-ip-report'" \
    "${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/etc/hotplug.d/iface/95-po0-outbound-ip-report"
for file in \
    packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-official-firewall-request \
    packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-official-firewall-runner; do
    grep -Fq 'trap cleanup_tmp_dir EXIT' "${repo_root}/${file}"
    grep -Fq 'trap handle_hup HUP' "${repo_root}/${file}"
    grep -Fq 'trap handle_int INT' "${repo_root}/${file}"
    grep -Fq 'trap handle_term TERM' "${repo_root}/${file}"
    if rg -n "trap 'rm -rf" "${repo_root}/${file}"; then
        printf 'OpenWrt official cleanup must not continue after a caught signal.\n' >&2
        exit 1
    fi
done
grep -Fq "LOCK_HELD='0'" \
    "${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-uci"
grep -Fq 'trap cleanup_run_lock EXIT' \
    "${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-uci"
grep -Fq 'trap handle_lock_hup HUP' \
    "${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-uci"
grep -Fq 'trap handle_lock_int INT' \
    "${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-uci"
grep -Fq 'trap handle_lock_term TERM' \
    "${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-uci"
if rg -n "trap 'rm -f .*LOCK_DIR" \
    "${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-uci"; then
    printf 'OpenWrt UCI lock must use signal handlers that exit after cleanup.\n' >&2
    exit 1
fi
if rg -n "LOCK_DIR='/tmp|/tmp/po0-outbound-ip-report.run.lock|>>/tmp/po0-outbound-ip-report-hotplug.log" \
    "${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-uci" \
    "${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/etc/hotplug.d/iface/95-po0-outbound-ip-report"; then
    printf 'OpenWrt official runtime must not use pre-creatable /tmp locks or logs.\n' >&2
    exit 1
fi
grep -Fq 'outbound-ip-report-v6' \
    "${repo_root}/packaging/openwrt/po0-outbound-ip-report/Makefile"
grep -Fq 'po0/outbound-ip-report-v6' \
    "${repo_root}/packaging/openwrt/po0-outbound-ip-report/files/usr/share/luci/menu.d/po0-outbound-ip-report.json"
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

grep -Fq '+mwan3' "$repo_root/packaging/openwrt/po0-outbound-ip-report/Makefile"
grep -Fq 'official firewall whitelist' "$repo_root/packaging/openwrt/po0-outbound-ip-report/Makefile"
grep -Fq 'chmod 600 $(1)/etc/config/po0_outbound_ip_report' "$repo_root/packaging/openwrt/po0-outbound-ip-report/Makefile"
grep -Fq '"$now" -lt "$last"' "$repo_root/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-service"
grep -Fq 'head -c 65536' "$repo_root/packaging/openwrt/po0-outbound-ip-report/files/etc/hotplug.d/iface/95-po0-outbound-ip-report"
grep -Fq -- '-eq 75' "$repo_root/packaging/openwrt/po0-outbound-ip-report/files/etc/hotplug.d/iface/95-po0-outbound-ip-report"
grep -Fq 'main.enabled controls the procd service' "$repo_root/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-uci"
grep -Fq 'safe_label()' "$repo_root/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-uci"
grep -Fq "jsonfilter -t '@[\"whitelist\"]'" "$repo_root/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-official-firewall-runner"
grep -Fq "OFFICIAL_INTERVAL='600'" "$repo_root/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-service"
if rg -n 'official_interval_seconds' \
    "$repo_root/packaging/openwrt/po0-outbound-ip-report/files/etc/config/po0_outbound_ip_report" \
    "$repo_root/packaging/openwrt/po0-outbound-ip-report/files/www/luci-static/resources/view/po0/outbound-ip-report.js" \
    "$repo_root/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-service"; then
    printf 'Official interval must remain a fixed service constant, not a free-form setting.\n' >&2
    exit 1
fi

printf 'OpenWrt APK layout tests passed.\n'
