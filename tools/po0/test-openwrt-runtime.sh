#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
work="$(mktemp -d "${repo_root}/.tmp/po0-runtime-test.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin" "$work/home"
if [[ -n "${PO0_TEST_RUNTIME_ENGINE:-}" ]]; then
 cp "$PO0_TEST_RUNTIME_ENGINE" "$work/engine"
else
 bash "$repo_root/tools/po0/build-openwrt-reporter-runtime.sh" "$work/engine"
fi
cat > "$work/bin/ip" <<'MOCK'
#!/bin/sh
printf '2: br-lan inet 192.168.88.250/24 scope global br-lan\n2: br-lan inet 192.168.88.251/32 scope global br-lan\n'
MOCK
cat > "$work/bin/curl" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> "$CURL_LOG"
case "$*" in
 *https://worker.invalid/report*)
  case "$*" in *--interface*|*--resolve*|*--noproxy*) exit 23;; esac; printf 'OK 198.51.100.22; targets=1\n200';;
 *https://probe.invalid/get*)
  case "$*" in *'--resolve probe.invalid:443:203.0.113.40,203.0.113.41'*) :;; *) exit 24;; esac
  case "$*" in *'--interface 192.168.88.250'*) printf '203.0.113.11';;
   *'--interface 192.168.88.251'*) printf '198.51.100.22';;
   *) exit 21;; esac;;
 *) exit 22;;
esac
MOCK
cat > "$work/bin/nslookup" <<'MOCK'
#!/bin/sh
[ "$*" = '-type=A probe.invalid 192.168.88.1' ] || exit 31
printf 'Server: 192.168.88.1\nAddress: 192.168.88.1#53\n\n'
case "${DNS_CASE:-good}" in
 timeout) exit 1;;
 server_only) exit 0;;
 fake) printf 'Name: probe.invalid\nAddress: 198.18.2.104\n';;
 private) printf 'Name: probe.invalid\nAddress: 192.168.88.2\n';;
 mixed) printf 'Name: probe.invalid\nAddress: 203.0.113.40\nAddress: 198.19.1.2\n';;
 *) printf 'Non-authoritative answer:\nprobe.invalid canonical name = cdn.invalid.\nName: cdn.invalid\nAddress: 203.0.113.40\nName: cdn.invalid\nAddress 2: 203.0.113.41 cdn.invalid\n';;
esac
MOCK
cat > "$work/bin/stat" <<'MOCK'
#!/bin/sh
exit 99
MOCK
chmod +x "$work/bin/"*
export PATH="$work/bin:$PATH" HOME="$work/home" XDG_STATE_HOME="$work/state" XDG_RUNTIME_DIR="$work/runtime"
export CURL_LOG="$work/curl.log"
export PO0_OUTBOUND_IP_REPORT_PROBE_DNS_SERVER=192.168.88.1
export PO0_OUTBOUND_IP_REPORT_WORKER_URL=https://worker.invalid/report
export PO0_OUTBOUND_IP_REPORT_WANS=all PO0_OUTBOUND_IP_REPORT_PROBE_MODE=source
export PO0_OUTBOUND_IP_REPORT_SOURCE_WAN1=192.168.88.250 PO0_OUTBOUND_IP_REPORT_SOURCE_WAN2=192.168.88.251
export PO0_OUTBOUND_IP_REPORT_IP_CHECK_URLS=https://probe.invalid/get
for attempt in 1 2; do
 bash "$work/engine" > "$work/output" 2>&1 || { cat "$work/output"; exit 1; }
 grep -Fq '成功 2 条，失败 0 条' "$work/output"
 ! grep -Eq 'command not found|unbound variable' "$work/output"
done
for DNS_CASE in timeout server_only fake private mixed; do
 export DNS_CASE
 : > "$CURL_LOG"
 if bash "$work/engine" > "$work/output" 2>&1; then
  printf 'Invalid DNS case accepted: %s\n' "$DNS_CASE" >&2; exit 1
 fi
 grep -Fq '真实 DNS 解析失败' "$work/output"
 [ ! -s "$CURL_LOG" ] || { printf 'DNS failure reached curl.\n' >&2; exit 1; }
done
unset DNS_CASE
printf 'OpenWrt generated Worker runtime tests passed.\n'
