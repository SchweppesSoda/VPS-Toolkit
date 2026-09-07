#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
work="$(mktemp -d "$repo_root/.tmp/po0-retired-runtime.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
bash "$repo_root/tools/po0/build-openwrt-reporter-runtime.sh" "$work/engine"
cat > "$work/adapter" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> "$CALLS"
MOCK
chmod +x "$work/adapter"
sed -i "s|/usr/libexec/po0-outbound-ip-report-uci|$work/adapter|g" "$work/engine"
export CALLS="$work/calls"
sh "$work/engine" --worker-only > /dev/null
[[ ! -e "$CALLS" ]]
sh "$work/engine" --official-status
grep -Fqx -- '--official-only --official-status' "$CALLS"
[[ $(wc -l < "$CALLS") == 1 ]]
! grep -Eq 'curl|WORKER_URL|source_id|install_cron' "$work/engine"
printf 'PASS: OpenWrt compatibility entry is official-only; retired actions are inert.\n'
