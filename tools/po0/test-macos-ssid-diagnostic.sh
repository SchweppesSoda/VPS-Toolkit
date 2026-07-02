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
PO0_OUTBOUND_IP_REPORT_MACOS_HELPER_DIR="${tmp_root}/helper-root"

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

cat > "${mock_bin}/osacompile" <<'MOCK'
#!/usr/bin/env bash
out=""
source_file=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o)
            out="$2"
            shift 2
            ;;
        *)
            source_file="$1"
            shift
            ;;
    esac
done
[[ -n "${out}" && -n "${source_file}" ]] || exit 2
mkdir -p "${out}/Contents/MacOS"
printf '#!/usr/bin/env bash\n' > "${out}/Contents/MacOS/applet"
chmod +x "${out}/Contents/MacOS/applet"
cp "${source_file}" "${out}/Contents/script.applescript"
cat > "${out}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict></dict></plist>
PLIST
MOCK
chmod +x "${mock_bin}/osacompile"
cat > "${mock_bin}/open" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "\$*" > "${tmp_root}/helper-open.args"
app_path=""
for arg in "\$@"; do
    case "\${arg}" in
        *"PO0 Location Permission Helper.app") app_path="\${arg}" ;;
    esac
done
[[ -n "\${app_path}" ]] || exit 2
request_path="\${app_path}/Contents/Resources/po0-location-helper-output.path"
[[ -f "\${request_path}" ]] || exit 3
out_path="\$(cat "\${request_path}")"
[[ -n "\${out_path}" ]] || exit 4
printf '%s\n' "status=requested" "ssid=CafeNet" > "\${out_path}"
MOCK
chmod +x "${mock_bin}/open"
if ! output="$(request_macos_location_permission 2>&1)"; then
    fail "requesting Location Services permission failed: ${output}"
fi
helper_app="$(macos_location_permission_helper_app_path)"
[[ -d "${helper_app}" ]] || fail "permission request did not build helper app"
grep -Fq "NSLocationWhenInUseUsageDescription" "${helper_app}/Contents/Info.plist" || fail "helper app Info.plist lacks location usage description"
grep -Fq "NSLocationUsageDescription" "${helper_app}/Contents/Info.plist" || fail "helper app Info.plist lacks macOS location usage description"
grep -Fq "CFBundleIdentifier" "${helper_app}/Contents/Info.plist" || fail "helper app Info.plist lacks stable bundle identifier"
grep -Fq "CFBundleExecutable" "${helper_app}/Contents/Info.plist" || fail "helper app Info.plist lacks bundle executable"
grep -Fq "CFBundlePackageType" "${helper_app}/Contents/Info.plist" || fail "helper app Info.plist lacks package type"
grep -Fq "PO0HelperSchemaVersion" "${helper_app}/Contents/Info.plist" || fail "helper app Info.plist lacks schema version"
[[ -x "${helper_app}/Contents/MacOS/applet" ]] || fail "helper app lacks executable applet"
grep -Fq "CoreLocation" "${helper_app}/Contents/script.applescript" || fail "helper app did not load CoreLocation"
grep -Fq "CoreWLAN" "${helper_app}/Contents/script.applescript" || fail "helper app did not load CoreWLAN"
grep -Fq "requestWhenInUseAuthorization" "${helper_app}/Contents/script.applescript" || fail "helper app did not ask for when-in-use authorization"
if grep -Fq 'on run argv' "${helper_app}/Contents/script.applescript"; then
    fail "helper app must not depend on AppleScript applet argv coercion"
fi
grep -Fq 'path to resource "po0-location-helper-output.path"' "${helper_app}/Contents/script.applescript" || fail "helper app should read output path from bundled resource"
if grep -Eq 'as (boolean|integer|real)' "${helper_app}/Contents/script.applescript"; then
    fail "helper app must not coerce AppleScriptObjC values with as boolean/integer/real"
fi
if grep -Fq 'write theText to fileRef as' "${helper_app}/Contents/script.applescript"; then
    fail "helper app must not write output with AppleEvent utf8 class coercion"
fi
if grep -Fq 'writeToFile:outputPath' "${helper_app}/Contents/script.applescript"; then
    fail "helper app must not write output through AppleScriptObjC NSError bridging"
fi
grep -Fq '/usr/bin/printf %s' "${helper_app}/Contents/script.applescript" || fail "helper app should write output through shell printf"
grep -Fq 'repeat 40 times' "${helper_app}/Contents/script.applescript" || fail "helper app should wait without NSDate numeric coercion"
grep -Fq 'on currentWifiSsid()' "${helper_app}/Contents/script.applescript" || fail "helper app should centralize CoreWLAN SSID reads"
grep -Fq 'set ssidValue to my currentWifiSsid()' "${helper_app}/Contents/script.applescript" || fail "helper app should poll SSID during the wait loop"
grep -Fq 'exit repeat' "${helper_app}/Contents/script.applescript" || fail "helper app should exit the wait loop as soon as SSID is available"
grep -Fq "PO0 Location Permission Helper.app" "${tmp_root}/helper-open.args" || fail "permission request did not open helper app"
if grep -Fq -- '--args' "${tmp_root}/helper-open.args"; then
    fail "permission request must not pass output path through open --args"
fi
printf '%s\n' "${output}" | grep -Fq "已尝试触发 macOS 定位权限请求" || fail "permission request did not report prompt attempt"
printf '%s\n' "${output}" | grep -Fq "PO0 Location Permission Helper" || fail "permission request did not tell user which helper app to allow"

printf 'keep\n' > "${PO0_OUTBOUND_IP_REPORT_MACOS_HELPER_DIR}/keep.txt"
printf 'outside\n' > "${tmp_root}/outside-keep.txt"
if ! output="$(remove_macos_location_permission_helper_app 2>&1)"; then
    fail "removing Location Permission Helper failed: ${output}"
fi
[[ ! -e "${helper_app}" ]] || fail "Location Permission Helper app still exists after removal"
[[ -f "${PO0_OUTBOUND_IP_REPORT_MACOS_HELPER_DIR}/keep.txt" ]] || fail "helper removal deleted unrelated helper-root file"
[[ -f "${tmp_root}/outside-keep.txt" ]] || fail "helper removal deleted unrelated outside file"
printf '%s\n' "${output}" | grep -Fq "已删除 PO0 Location Permission Helper" || fail "helper removal did not report deletion"
printf '%s\n' "${output}" | grep -Fq "不会修改 macOS 定位授权记录" || fail "helper removal did not explain TCC permissions are untouched"
if ! output="$(remove_macos_location_permission_helper_app 2>&1)"; then
    fail "removing missing Location Permission Helper should be idempotent: ${output}"
fi
printf '%s\n' "${output}" | grep -Fq "不存在" || fail "helper removal did not report missing helper"

mkdir -p "${helper_app}/Contents"
cat > "${helper_app}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>example.other.helper</string></dict></plist>
PLIST
if output="$(remove_macos_location_permission_helper_app 2>&1)"; then
    fail "helper removal deleted a bundle without the PO0 helper identity: ${output}"
fi
[[ -d "${helper_app}" ]] || fail "helper removal removed wrong-identity bundle"
rm -rf "${helper_app}"

if ! output="$(request_macos_location_permission 2>&1)"; then
    fail "requesting Location Services permission after helper removal failed: ${output}"
fi
[[ -d "${helper_app}" ]] || fail "permission request did not rebuild helper app after removal"

cat > "${mock_bin}/open" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "\$*" > "${tmp_root}/helper-open.args"
app_path=""
for arg in "\$@"; do
    case "\${arg}" in
        *"PO0 Location Permission Helper.app") app_path="\${arg}" ;;
    esac
done
[[ -n "\${app_path}" ]] || exit 2
request_path="\${app_path}/Contents/Resources/po0-location-helper-output.path"
[[ -f "\${request_path}" ]] || exit 3
out_path="\$(cat "\${request_path}")"
[[ -n "\${out_path}" ]] || exit 4
printf '%s\n' "status=requested" "ssid=redacted" > "\${out_path}"
MOCK
chmod +x "${mock_bin}/open"
if ! output="$(request_macos_location_permission 2>&1)"; then
    fail "requesting Location Services permission with redacted helper SSID failed: ${output}"
fi
if printf '%s\n' "${output}" | grep -Fq "Helper 当前读取到的 Wi-Fi SSID"; then
    fail "permission request printed redacted helper SSID as a real SSID"
fi

cat > "${mock_bin}/open" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "\$*" > "${tmp_root}/helper-open.args"
app_path=""
for arg in "\$@"; do
    case "\${arg}" in
        *"PO0 Location Permission Helper.app") app_path="\${arg}" ;;
    esac
done
[[ -n "\${app_path}" ]] || exit 2
request_path="\${app_path}/Contents/Resources/po0-location-helper-output.path"
[[ -f "\${request_path}" ]] || exit 3
out_path="\$(cat "\${request_path}")"
[[ -n "\${out_path}" ]] || exit 4
printf '%s\n' "status=requested" "ssid=CafeNet" > "\${out_path}"
MOCK
chmod +x "${mock_bin}/open"
rm -f "${tmp_root}/helper-open.args"
prompt_yes_no() {
    return 0
}
if ! output="$(show_wifi_ssid_permission_help_interactive 2>&1)"; then
    fail "interactive permission help failed: ${output}"
fi
[[ -s "${tmp_root}/helper-open.args" ]] || fail "interactive menu help did not request Location Services permission"
ssid="$(macos_location_helper_wifi_ssid 2>/dev/null)" || fail "helper app SSID fallback did not return SSID"
[[ "${ssid}" == "CafeNet" ]] || fail "unexpected helper app SSID: ${ssid}"
rm -f "${mock_bin}/osacompile" "${mock_bin}/open"

write_mock_networksetup "none"
rm -f "${mock_bin}/wdutil"
ssid="$(current_wifi_ssid 2>/dev/null)" || fail "networksetup real SSID named none was rejected"
[[ "${ssid}" == "none" ]] || fail "unexpected networksetup SSID: ${ssid}"
rm -f "${mock_bin}/networksetup"

write_mock_wdutil "CafeNet"
ssid="$(current_wifi_ssid 2>/dev/null)" || fail "real wdutil SSID was not accepted"
[[ "${ssid}" == "CafeNet" ]] || fail "unexpected SSID: ${ssid}"

printf 'macOS SSID diagnostic tests passed.\n'
