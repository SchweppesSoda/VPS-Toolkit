#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
mkdir -p "$repo_root/.tmp"
work="$(mktemp -d "$repo_root/.tmp/po0-openwrt-hotplug.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/run"
src="$repo_root/packaging/openwrt/po0-outbound-ip-report/files/etc/hotplug.d/iface/95-po0-outbound-ip-report"
cp "$src" "$work/hotplug"
sed -i -e "s|^RUN_DIR=.*|RUN_DIR='$work/run'|" -e "s|^SERVICE=.*|SERVICE='$work/service'|" \
 -e 's/prepare_hotplug_log || return 0/true || return 0/' -e '$s/exit 0/wait/' "$work/hotplug"
cat > "$work/bin/uci" <<'MOCK'
#!/bin/sh
case "$*" in
 *main.enabled) printf '%s' "${TOTAL:-1}" ;;
 *main.worker_enabled) printf '%s' "${WORKER:-1}" ;;
 *main.official_enabled) printf '%s' "${OFFICIAL:-1}" ;;
 *main.worker_network_enabled) printf '%s' "${WORKER_NETWORK:-1}" ;;
 *main.official_network_enabled) printf '%s' "${OFFICIAL_NETWORK:-1}" ;;
 *main.probe_mode) printf '%s' "${MODE:-local}" ;;
 *main.wans) printf '%s' "${WANS:-wan1;wan2}" ;;
 *binding1.enabled) printf 1 ;;
 *binding1.wan) printf wan1 ;;
 *binding2.enabled) printf 1 ;;
 *binding2.wan) printf wan2 ;;
 *'show po0_outbound_ip_report') printf 'po0_outbound_ip_report.binding1=official_binding\npo0_outbound_ip_report.binding2=official_binding\n' ;;
 *'get mwan3.wan1') printf interface ;;
 *'get mwan3.wan1.enabled') printf 1 ;;
 *) exit 1 ;;
esac
MOCK
cat > "$work/bin/sleep" <<'MOCK'
#!/bin/sh
exit 0
MOCK
cat > "$work/service" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> "$WORK/$1.calls"
MOCK
chmod +x "$work/bin/"* "$work/service"
export WORK="$work" PATH="$work/bin:$PATH"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
run() { : > "$work/worker.calls"; : > "$work/official.calls"; ACTION="${ACTION:-ifup}" INTERFACE="${INTERFACE:-wan1}" sh "$work/hotplug"; }
has() { grep -Fqx -- "$2" "$work/$1.calls" || fail "missing $1 event: $2"; }
empty() { [[ ! -s "$work/$1.calls" ]] || fail "unexpected $1 event"; }
run
has worker 'worker network '; has official 'official network wan1'
ACTION=ifupdate IFUPDATE_ROUTES=1 run
has worker 'worker network '; has official 'official network wan1'
ACTION=ifupdate IFUPDATE_ADDRESSES=1 run
has official 'official network wan1'
ACTION=ifupdate run
empty worker; empty official
ACTION=ifdown run
empty worker; empty official
INTERFACE=loopback MODE=source run
empty worker; empty official
WORKER_NETWORK=0 run
empty worker; has official 'official network wan1'
OFFICIAL_NETWORK=0 run
empty official; has worker 'worker network '
WORKER=0 run
empty worker; has official 'official network wan1'
TOTAL=0 run
empty worker; empty official
INTERFACE=lan run
empty worker; empty official
MODE=source INTERFACE=lan run
has worker 'worker network '; has official 'official network '
WANS=wan2 run
empty worker; has official 'official network wan1'
WANS=all run
has worker 'worker network '
WANS=all INTERFACE=lan run
empty worker; empty official
printf 'PASS: OpenWrt hotplug recovery/address/route events and channel switches.\n'
