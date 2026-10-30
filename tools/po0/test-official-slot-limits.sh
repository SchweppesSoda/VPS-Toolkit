#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
mkdir -p "$repo_root/.tmp"
tmp_dir="$(mktemp -d "$repo_root/.tmp/po0-slot-limits.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
trim() { local value="${1:-}"; value="${value#"${value%%[![:space:]]*}"}"; value="${value%"${value##*[![:space:]]}"}"; printf '%s' "$value"; }
to_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
mock_request() {
 printf '%s|%s\n' "$2" "${3:-}" >> "$tmp_dir/requests"
 if [[ "$2" == status ]]; then printf '%s' "$get_payload"; else printf '%s' "$post_payload"; fi
}
check_requests() { [[ "$(tr '\n' ' ' < "$tmp_dir/requests")" == "$1" ]] || fail "$client request sequence: $1"; }
for client in "${1:-linux}"; do
 case "$client" in
  linux)
   source "$repo_root/scripts/po0/relay/self-report/linux/src/125-official-report.sh"
   parse=official_json_parse
   official_direct_request() { mock_request "$@"; }
   run_item() { official_report_token pgnfw_slot_fixture "$slot" 1 "$1"; }
   parse_token() { official_parse_token_item "$1"; }
   ;;
  macos)
   source "$repo_root/scripts/po0/relay/self-report/macos/src/078-official-firewall.sh"
   parse=po0_firewall_json_parse
   po0_firewall_direct_request() { mock_request "$@"; }
   run_item() { po0_firewall_process_item 1 "pgnfw_slot_fixture@$slot" "$1"; }
   parse_token() { po0_firewall_parse_item "$1"; }
   ;;
  *) fail 'unsupported client' ;;
 esac
 for capacity in 1 5 6 7 8 9 10; do
  slot="$((capacity - 1))"
  parse_token "pgnfw_slot_fixture@$slot" || fail "$client expanded token rejected"
  post_payload="{\"enabled\":true,\"currentIp\":\"203.0.113.0/24\",\"limit\":$capacity,\"whitelist\":[{\"ip\":\"203.0.113.0/24\",\"slot\":$slot}]}"
  "$parse" "$post_payload" >/dev/null || fail "$client expanded response rejected at limit $capacity"
  get_payload="$post_payload"
  : > "$tmp_dir/requests"
  run_item report >"$tmp_dir/stdout" 2>"$tmp_dir/stderr" || fail "$client expanded GET hit rejected"
  check_requests 'status| '
  get_payload="{\"enabled\":true,\"currentIp\":\"203.0.113.0/24\",\"limit\":$capacity,\"whitelist\":[]}"
  : > "$tmp_dir/requests"
  run_item status >"$tmp_dir/stdout" 2>"$tmp_dir/stderr" || fail "$client read-only missing failed"
  check_requests 'status| '
  : > "$tmp_dir/requests"
  run_item report >"$tmp_dir/stdout" 2>"$tmp_dir/stderr" || fail "$client expanded POST failed"
  check_requests "status| add|$slot "
  ! grep -Fq pgnfw_ "$tmp_dir/stdout" "$tmp_dir/stderr" || fail "$client token leaked"
 done
 for capacity in 6 10; do
  entries=''; index=0
  while (( index < capacity )); do
   entries="$entries${entries:+,}{\"ip\":\"192.0.2.$index/24\",\"slot\":$index}"
   index=$((index+1))
  done
  payload="{\"enabled\":true,\"currentIp\":\"203.0.113.0/24\",\"limit\":$capacity,\"whitelist\":[$entries]}"
  "$parse" "$payload" >/dev/null || fail "$client complete expanded whitelist rejected"
 done
 for pair in '5|5' '6|9'; do
  capacity="${pair%|*}"; slot="${pair#*|}"
  get_payload="{\"enabled\":true,\"currentIp\":\"203.0.113.0/24\",\"limit\":$capacity,\"whitelist\":[]}"
  : > "$tmp_dir/requests"
  if run_item report >"$tmp_dir/stdout" 2>"$tmp_dir/stderr"; then fail "$client out-of-quota fixed slot accepted"; fi
  check_requests 'status| '
  grep -Fq '指定槽位超出账号额度' "$tmp_dir/stderr" || fail "$client quota error missing"
 done
 for invalid_limit in 0 11 5.5 '"6"' null; do
  payload="{\"enabled\":true,\"currentIp\":\"203.0.113.0/24\",\"limit\":$invalid_limit,\"whitelist\":[]}"
  if "$parse" "$payload" >/dev/null; then fail "$client invalid limit accepted"; fi
 done
 for invalid_slot in 6 10 -1 0.5 '"5"' true; do
  payload="{\"enabled\":true,\"currentIp\":\"203.0.113.0/24\",\"limit\":6,\"whitelist\":[{\"ip\":\"203.0.113.0/24\",\"slot\":$invalid_slot}]}"
  if "$parse" "$payload" >/dev/null; then fail "$client invalid response slot accepted"; fi
 done
 payload='{"enabled":true,"currentIp":"203.0.113.0/24","limit":1,"whitelist":[{"ip":"203.0.113.0/24"},{"ip":"198.51.100.0/24"}]}'
 if "$parse" "$payload" >/dev/null; then fail "$client excessive whitelist accepted"; fi
 printf 'PASS: %s expanded official slot quota and GET/POST checks.\n' "$client"
done
