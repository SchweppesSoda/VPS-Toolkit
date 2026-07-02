#!/usr/bin/env bash
set -euo pipefail

PATH="/usr/bin:/bin:${PATH:-}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"

# shellcheck source=/dev/null
source "${repo_root}/scripts/po0/relay/self-report/macos/src/010-core-string-path-config.sh"
# shellcheck source=/dev/null
source "${repo_root}/scripts/po0/relay/self-report/macos/src/040-prompt-and-input-helpers.sh"
# shellcheck source=/dev/null
source "${repo_root}/scripts/po0/relay/self-report/macos/src/075-wifi-ssid-skip.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/po0-macos-ssid-test.XXXXXX")"
trap 'rm -rf "${tmp_root}"' EXIT

mock_bin="${tmp_root}/bin"
mkdir -p "${mock_bin}"
PATH="${mock_bin}:/usr/bin:/bin"

write_mock_wdutil() {
    local ssid="$1"
    cat > "${mock_bin}/wdutil" <<MOCK
#!/usr/bin/env bash
printf '%s\n' 'Wi-Fi:'
printf '%s\n' '    SSID: ${ssid}'
MOCK
    chmod +x "${mock_bin}/wdutil"
}

write_mock_networksetup() {
    local ssid="$1"
    cat > "${mock_bin}/networksetup" <<MOCK
#!/usr/bin/env bash
case "\${1:-}" in
    -listallhardwareports)
        printf '%s\n' 'Hardware Port: Wi-Fi'
        printf '%s\n' 'Device: en0'
        ;;
    -getairportnetwork)
        printf '%s\n' 'Current Wi-Fi Network: ${ssid}'
        ;;
    *)
        exit 1
        ;;
esac
MOCK
    chmod +x "${mock_bin}/networksetup"
}

SKIP_WIFI_SSIDS=""
FORCE_REPORT="0"
WIFI_SKIP_LAST_SSID=""
WIFI_SSID_LAST_ERROR=""

write_mock_networksetup "redacted"
rm -f "${mock_bin}/wdutil"
if current_wifi_ssid >"${tmp_root}/ssid.out" 2>/dev/null; then
    fail "networksetup redacted output must not be accepted as SSID: $(cat "${tmp_root}/ssid.out")"
fi
[[ "${WIFI_SSID_LAST_ERROR:-}" == "privacy" ]] || fail "networksetup redacted did not set privacy error"

write_mock_networksetup "<redacted>"
if current_wifi_ssid >"${tmp_root}/ssid.out" 2>/dev/null; then
    fail "networksetup <redacted> output must not be accepted as SSID: $(cat "${tmp_root}/ssid.out")"
fi
[[ "${WIFI_SSID_LAST_ERROR:-}" == "privacy" ]] || fail "networksetup <redacted> did not set privacy error"
rm -f "${mock_bin}/networksetup"

airport_wifi_ssid() {
    return 1
}

write_mock_wdutil "<redacted>"
if current_wifi_ssid >"${tmp_root}/ssid.out" 2>/dev/null; then
    fail "redacted wdutil output must not be accepted as SSID: $(cat "${tmp_root}/ssid.out")"
fi
[[ "${WIFI_SSID_LAST_ERROR:-}" == "privacy" ]] || fail "redacted SSID did not set privacy error"

if output="$(show_current_wifi_ssid_once 2>&1)"; then
    fail "--show-wifi-ssid should fail-open when SSID is redacted: ${output}"
fi
printf '%s\n' "${output}" | grep -Fq "macOS 隐私权限隐藏" || fail "redacted diagnostic did not mention macOS privacy"

SKIP_WIFI_SSIDS="<redacted>;redacted"
if should_skip_wifi_ssid_report; then
    fail "redacted placeholder must not match skip list"
fi

if ! output="$(show_wifi_ssid_permission_help 2>&1)"; then
    fail "permission help failed: ${output}"
fi
printf '%s\n' "${output}" | grep -Fq "不会自动获取或修改系统权限" || fail "permission help did not state no auto-grant"
printf '%s\n' "${output}" | grep -Fq "no auto-grant" || fail "permission help did not include ASCII no-auto-grant marker"
printf '%s\n' "${output}" | grep -Fq "Location Services" || fail "permission help did not include ASCII Location Services marker"
printf '%s\n' "${output}" | grep -Fq "定位服务" || fail "permission help did not mention Location Services"
printf '%s\n' "${output}" | grep -Fq "po0-outbound-ip-report --request-location-permission" || fail "permission help did not print permission request command"
printf '%s\n' "${output}" | grep -Fq 'open "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"' || fail "permission help did not print Location Services open command"
printf '%s\n' "${output}" | grep -Fq "如果列表里没有 Terminal/iTerm" || fail "permission help did not explain missing Terminal/iTerm entry"
if printf '%s\n' "${output}" | grep -Fq "如果看到 redacted"; then
    fail "permission help should not expose raw redacted wording after classifying it as privacy-hidden"
fi

cat > "${mock_bin}/open" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "\$*" > "${tmp_root}/open.args"
MOCK
chmod +x "${mock_bin}/open"
if ! output="$(open_macos_location_services_settings 2>&1)"; then
    fail "opening Location Services settings failed: ${output}"
fi
printf '%s\n' "${output}" | grep -Fq "已请求打开 macOS 定位服务设置" || fail "open helper did not report Location Services settings launch"
[[ "$(cat "${tmp_root}/open.args")" == "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices" ]] || fail "open helper used unexpected settings URL: $(cat "${tmp_root}/open.args")"
rm -f "${mock_bin}/open"

cat > "${mock_bin}/osascript" <<MOCK
#!/usr/bin/env bash
cat > "${tmp_root}/osascript.stdin"
printf '%s\n' "requested"
MOCK
chmod +x "${mock_bin}/osascript"
if ! output="$(request_macos_location_permission 2>&1)"; then
    fail "requesting Location Services permission failed: ${output}"
fi
grep -Fq "CoreLocation" "${tmp_root}/osascript.stdin" || fail "permission request did not load CoreLocation"
grep -Fq "requestWhenInUseAuthorization" "${tmp_root}/osascript.stdin" || fail "permission request did not ask for when-in-use authorization"
printf '%s\n' "${output}" | grep -Fq "已尝试触发 macOS 定位权限请求" || fail "permission request did not report prompt attempt"
printf '%s\n' "${output}" | grep -Fq "Terminal/iTerm" || fail "permission request did not tell user which terminal app to allow"

rm -f "${tmp_root}/osascript.stdin"
prompt_yes_no() {
    return 0
}
if ! output="$(show_wifi_ssid_permission_help_interactive 2>&1)"; then
    fail "interactive permission help failed: ${output}"
fi
[[ -s "${tmp_root}/osascript.stdin" ]] || fail "interactive menu help did not request Location Services permission"
rm -f "${mock_bin}/osascript"

write_mock_networksetup "none"
rm -f "${mock_bin}/wdutil"
ssid="$(current_wifi_ssid 2>/dev/null)" || fail "networksetup real SSID named none was rejected"
[[ "${ssid}" == "none" ]] || fail "unexpected networksetup SSID: ${ssid}"
rm -f "${mock_bin}/networksetup"

write_mock_wdutil "CafeNet"
ssid="$(current_wifi_ssid 2>/dev/null)" || fail "real wdutil SSID was not accepted"
[[ "${ssid}" == "CafeNet" ]] || fail "unexpected SSID: ${ssid}"

printf 'macOS SSID diagnostic tests passed.\n'
