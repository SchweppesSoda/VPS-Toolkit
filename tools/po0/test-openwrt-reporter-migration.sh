#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
work="$(mktemp -d "$repo_root/.tmp/po0-retired-uci.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
for mode in source router local; do
 (
  config_path="$work/$mode.config"; backup_path="$work/$mode.backup"
  printf 'private original UCI fixture\n' > "$config_path"
  sed -e "s|^config=.*|config='$config_path'|" -e "s|^backup=.*|backup='$backup_path'|" "$repo_root/packaging/openwrt/po0-outbound-ip-report/files/usr/libexec/po0-outbound-ip-report-migrate" > "$work/$mode.migrate"
  declare -A settings=( [enabled]=0 [worker_enabled]=1 [official_enabled]=0 [official_timer_enabled]=0 [official_interval_seconds]=1800 [probe_mode]="$mode" [probe_dns_server]=192.168.88.9 [router_probe_url]='http://retired.invalid' [direct_probe_resolve]='old:443:1.1.1.1' [official_source_wan1]=192.168.88.250 [worker_url]='https://retired.invalid/report' [secret]='fixture-secret' )
  uci() {
   [[ "${1:-}" != -q ]] || shift
   local action="$1" key="${2:-}"
   key="${key#po0_outbound_ip_report.main.}"
   case "$action" in
    get) [[ -v "settings[$key]" ]] || return 1; printf '%s\n' "${settings[$key]}";;
    delete) unset 'settings[$key]';;
    commit) :;;
    *) return 1;;
   esac
  }
  source "$work/$mode.migrate"
  cmp "$config_path" "$backup_path/config"
  [[ ! -v settings[worker_url] && ! -v settings[secret] && ! -v settings[worker_enabled] ]]
  [[ "${settings[enabled]}:${settings[official_enabled]}:${settings[official_timer_enabled]}:${settings[official_interval_seconds]}" == '0:0:0:1800' ]]
  [[ "${settings[official_source_wan1]}" == 192.168.88.250 && "${settings[probe_dns_server]}" == 192.168.88.9 ]]
  [[ "$mode" != source || ! -v settings[router_probe_url] ]]
  printf 'new live config\n' > "$config_path"
  source "$work/$mode.migrate"
  grep -Fqx 'private original UCI fixture' "$backup_path/config"
  [[ -f "$backup_path/completed" ]]
 )
done
printf 'PASS: UCI retirement preserves disabled choices, interval, DNS/source mapping and immutable backup.\n'
