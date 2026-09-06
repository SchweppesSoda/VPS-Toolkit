#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/po0-linux-multi-wan-test.XXXXXX")"
export HOME="${tmp_dir}/home"
export XDG_STATE_HOME="${tmp_dir}/state"
export XDG_RUNTIME_DIR="${tmp_dir}/runtime"
trap 'rm -rf -- "${tmp_dir}"' EXIT
call_log="${tmp_dir}/calls.log"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

# shellcheck source=/dev/null
source "${repo_root}/scripts/po0/relay/self-report/linux/src/010-core-string-path-config.sh"
# shellcheck source=/dev/null
source "${repo_root}/scripts/po0/relay/self-report/linux/src/040-prompt-and-input-helpers.sh"
# shellcheck source=/dev/null
source "${repo_root}/scripts/po0/relay/self-report/linux/src/050-config-device-defaults.sh"
# shellcheck source=/dev/null
source "${repo_root}/scripts/po0/relay/self-report/linux/src/060-worker-url-interval-state.sh"
# shellcheck source=/dev/null
source "${repo_root}/scripts/po0/relay/self-report/linux/src/070-outbound-ip-detection.sh"
eval "$(declare -f list_enabled_mwan3_wans | sed '1s/list_enabled_mwan3_wans/list_enabled_mwan3_wans_impl/')"
# shellcheck source=/dev/null
source "${repo_root}/scripts/po0/relay/self-report/linux/src/130-report-submit.sh"

uci() {
    case "$*" in
        "-q show mwan3")
            printf '%s\n' 'mwan3.wan1=interface' 'mwan3.wan2=interface'
            ;;
        "-q get mwan3.wan1.enabled") printf '1\n' ;;
        "-q get mwan3.wan2.enabled") printf '0\n' ;;
        *) return 1 ;;
    esac
}
ubus() { return 0; }
[[ "$(list_enabled_mwan3_wans_impl)" == "wan1" ]] || fail "--wan all should ignore disabled mwan3 interfaces"

list_enabled_mwan3_wans() {
    printf '%s\n' wan1 wan2
}

openwrt_wan_l3_device() {
    case "$1" in
        wan1) printf 'pppoe-wan1\n' ;;
        wan2) printf 'pppoe-wan2\n' ;;
        *) return 1 ;;
    esac
}

detect_outbound_ipv4() {
    printf 'detect:%s\n' "${1:-}" >> "${call_log}"
    case "${1:-}" in
        pppoe-wan1|192.168.88.2) printf '203.0.113.11\n' ;;
        pppoe-wan2|192.168.88.3)
            [[ "${FAIL_WAN2:-0}" == "1" ]] && return 1
            printf '198.51.100.22\n'
            ;;
        "") printf '192.0.2.33\n' ;;
        *) return 1 ;;
    esac
}

curl() {
    local arg source="" ip=""
    for arg in "$@"; do
        case "${arg}" in
            source=*) source="${arg#source=}" ;;
            ip=*) ip="${arg#ip=}" ;;
        esac
    done
    printf 'submit:%s:%s\n' "${source}" "${ip}" >> "${call_log}"
    printf 'OK %s; targets=1; target_names=test\n200\n' "${ip}"
}

validate_worker_url() { return 0; }
skip_report_for_wifi_ssid_if_needed() { return 1; }
self_report_append_response_target_success() { printf '%s\n' "$1"; }
self_report_completed() { printf 'DONE:%s\n' "$1"; }
self_report_incomplete() { printf 'FAILED:%s\n' "$1" >&2; }

WORKER_URL="https://report.example.com/report"
SOURCE_ID="router"
IDENTITY="router"
SECRET=""

WANS="saved"
WANS_CLI_SEEN="0"
append_wan_selection_value "wan1"
append_wan_selection_value "wan2"
[[ "${WANS}" == "wan1;wan2" ]] || fail "first CLI --wan should replace saved selection and repeated values should append"

: > "${call_log}"
WANS=""
report_once >/dev/null
grep -Fxq 'detect:' "${call_log}" || fail "default mode should not bind a WAN device"
grep -Fxq 'submit:router:192.0.2.33' "${call_log}" || fail "default mode should preserve the base source ID"

: > "${call_log}"
WANS="wan2"
report_once >/dev/null
grep -Fxq 'detect:pppoe-wan2' "${call_log}" || fail "selected WAN should use its l3_device"
grep -Fxq 'submit:router-wan2:198.51.100.22' "${call_log}" || fail "selected WAN should use a scoped source ID"

: > "${call_log}"
WANS="all"
report_once >/dev/null
grep -Fxq 'submit:router-wan1:203.0.113.11' "${call_log}" || fail "--wan all should submit wan1"
grep -Fxq 'submit:router-wan2:198.51.100.22' "${call_log}" || fail "--wan all should submit wan2"

: > "${call_log}"
FAIL_WAN2="1"
if report_once >/dev/null 2>&1; then
    fail "partial multi-WAN failure should return nonzero"
fi
grep -Fxq 'submit:router-wan1:203.0.113.11' "${call_log}" || fail "wan1 should still submit when wan2 detection fails"
if grep -q '^submit:router-wan2:' "${call_log}"; then
    fail "failed WAN should not be submitted"
fi

# Source-address mode works on a gateway without local WAN interfaces or HTTP probe.
FAIL_WAN2=0
PO0_OUTBOUND_IP_REPORT_PROBE_MODE=source
PO0_OUTBOUND_IP_REPORT_SOURCE_WAN1=192.168.88.2
PO0_OUTBOUND_IP_REPORT_SOURCE_WAN2=192.168.88.3
ip() {
 printf '%s\n' '3: br-lan inet 192.168.88.2/24' '3: br-lan inet 192.168.88.3/32'
}
: > "$call_log"
WANS=all
report_once >/dev/null
grep -Fxq 'detect:192.168.88.2' "$call_log" || fail 'gateway WAN1 did not bind its source'
grep -Fxq 'detect:192.168.88.3' "$call_log" || fail 'gateway WAN2 did not bind its source'
! grep -q '^router-detect:' "$call_log" || fail 'gateway still used upstream HTTP probe'
WANS=wan2
PO0_OUTBOUND_IP_REPORT_SOURCE_WAN2=192.168.88.99
: > "$call_log"
if report_once >/dev/null 2>&1; then fail 'unassigned gateway source was accepted'; fi
[ ! -s "$call_log" ] || fail 'invalid source fell back to another route'

printf 'Linux/OpenWrt multi-WAN report tests passed.\n'
