#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# Source only the UCI upgrade block: never touch host /etc or migrate real files.
upgrade_block="$(sed -n '/^changed=0/,/^chmod 600/p' "$repo_root/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-migrate" | sed '$d')"
for mode in source router local; do
 (
  declare -A settings=(
   [worker_enabled]=1 [official_enabled]=0 [probe_mode]="$mode"
   [router_probe_url]='http://192.168.88.1/cgi-bin/po0-wan-probe'
   [direct_probe_resolve]='ip9.com.cn:443:103.217.192.99'
   [official_source_wan1]='192.168.88.250' [official_source_wan2]='192.168.88.251'
   [worker_url]='https://worker.invalid/report' [secret]='fixture-secret'
  )
  commits=0
  uci() {
   [[ "${1:-}" != -q ]] || shift
   local action="$1" key="${2:-}" value
   key="${key#po0_outbound_ip_report.main.}"
   case "$action" in
    get) [[ -v "settings[$key]" ]] || return 1; printf '%s\n' "${settings[$key]}";;
    set) value="${key#*=}"; key="${key%%=*}"; settings[$key]="$value";;
    delete) unset 'settings[$key]';;
    commit) commits=$((commits + 1));;
    *) return 1;;
   esac
  }
  eval "$upgrade_block"$'\ntrue'
  if [[ "$mode" == source ]]; then
   [[ ! -v settings[router_probe_url] && ! -v settings[direct_probe_resolve] ]]
   [[ "${settings[probe_dns_server]}" == 192.168.88.1 && "$commits" == 1 ]]
   settings[probe_dns_server]=192.168.88.9
  else
   [[ -v settings[router_probe_url] && -v settings[direct_probe_resolve] && "$commits" == 0 ]]
  fi
  [[ "${settings[worker_url]}" == https://worker.invalid/report && "${settings[secret]}" == fixture-secret ]]
  [[ "${settings[official_source_wan1]}" == 192.168.88.250 && "${settings[official_source_wan2]}" == 192.168.88.251 ]]
  before="$commits"
  eval "$upgrade_block"$'\ntrue'
  [[ "$commits" == "$before" ]]
  [[ "$mode" != source || "${settings[probe_dns_server]}" == 192.168.88.9 ]]
 )
done
printf 'OpenWrt reporter source-mode migration tests passed.\n'
