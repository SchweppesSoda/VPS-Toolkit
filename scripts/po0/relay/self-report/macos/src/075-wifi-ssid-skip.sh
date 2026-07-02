normalize_wifi_ssid_skip_list() {
    local raw="$1" rest item out=""
    rest="${raw};"
    while [[ -n "${rest}" ]]; do
        item="${rest%%;*}"
        rest="${rest#*;}"
        item="$(trim "${item}")"
        [[ -n "${item}" ]] || continue
        if [[ -n "${out}" ]]; then
            out="${out};${item}"
        else
            out="${item}"
        fi
    done
    printf '%s' "${out}"
}

append_skip_wifi_ssid() {
    local ssid="$1"
    ssid="$(trim "${ssid}")"
    [[ -n "${ssid}" ]] || return 0
    if [[ -n "${SKIP_WIFI_SSIDS}" ]]; then
        SKIP_WIFI_SSIDS="${SKIP_WIFI_SSIDS};${ssid}"
    else
        SKIP_WIFI_SSIDS="${ssid}"
    fi
    SKIP_WIFI_SSIDS="$(normalize_wifi_ssid_skip_list "${SKIP_WIFI_SSIDS}")"
}

skip_wifi_ssids_label() {
    local list
    list="$(normalize_wifi_ssid_skip_list "${SKIP_WIFI_SSIDS:-}")"
    if [[ -n "${list}" ]]; then
        printf '%s\n' "${list}"
    else
        printf '未设置\n'
    fi
}

wifi_ssid_read_failure_label() {
    case "${WIFI_SSID_LAST_ERROR:-}" in
        privacy)
            printf '读取失败或被 macOS 隐私权限隐藏（fail-open）\n'
            ;;
        *)
            printf '读取失败或未连接（fail-open）\n'
            ;;
    esac
}

accepted_wifi_ssid_value() {
    local ssid lowered
    ssid="$(trim "${1:-}")"
    lowered="$(to_lower "${ssid}")"
    case "${lowered}" in
        ""|"<none>")
            return 1
            ;;
        "<redacted>"|"redacted")
            return 2
            ;;
    esac
    printf '%s\n' "${ssid}"
}

capture_wifi_ssid_probe() {
    local ssid rc
    WIFI_SSID_PROBE_VALUE=""
    rc=0
    ssid="$("$@" 2>/dev/null)" || rc=$?
    if [[ "${rc}" == "0" && -n "${ssid}" ]]; then
        WIFI_SSID_LAST_ERROR=""
        WIFI_SSID_PROBE_VALUE="${ssid}"
        return 0
    fi
    if [[ "${rc}" == "2" ]]; then
        WIFI_SSID_LAST_ERROR="privacy"
    fi
    return 1
}

macos_location_services_settings_url() {
    printf '%s\n' "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
}

macos_location_services_settings_command() {
    printf '%s\n' 'open "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"'
}

open_macos_location_services_settings() {
    local url
    url="$(macos_location_services_settings_url)"
    if command -v open >/dev/null 2>&1; then
        if open "${url}"; then
            printf '已请求打开 macOS 定位服务设置。\n'
            return 0
        fi
        printf '打开 macOS 定位服务设置失败，请手动执行：%s\n' "$(macos_location_services_settings_command)" >&2
        return 1
    fi
    printf '未找到 macOS open 命令，请手动执行：%s\n' "$(macos_location_services_settings_command)" >&2
    return 1
}

macos_location_permission_helper_root() {
    if [[ -n "${PO0_OUTBOUND_IP_REPORT_MACOS_HELPER_DIR:-}" ]]; then
        printf '%s\n' "${PO0_OUTBOUND_IP_REPORT_MACOS_HELPER_DIR}"
    else
        [[ -n "${HOME:-}" ]] || return 1
        printf '%s\n' "${HOME}/Library/Application Support/PO0"
    fi
}

macos_location_permission_helper_app_path() {
    local root
    root="$(macos_location_permission_helper_root)" || return 1
    printf '%s\n' "${root}/PO0 Location Permission Helper.app"
}

validate_macos_location_permission_helper_app_path() {
    local app_dir="$1" root physical logical
    [[ -n "${app_dir}" ]] || return 1
    case "${app_dir}" in
        /*) ;;
        *) return 1 ;;
    esac
    case "${app_dir}" in
        *$'\n'*|*"/../"*|*"/./"*|*"/..") return 1 ;;
    esac
    case "${app_dir}" in
        *"/PO0 Location Permission Helper.app") ;;
        *) return 1 ;;
    esac
    root="${app_dir%/PO0 Location Permission Helper.app}"
    [[ -n "${root}" && "${root}" != "${app_dir}" ]] || return 1
    case "${root}" in
        "/"|"/Applications"|"/Library"|"/System"|"/usr"|"/bin"|"/sbin"|"/private"|"/tmp"|"/var"|"/Users")
            return 1
            ;;
    esac
    if [[ -n "${HOME:-}" && "${root}" == "${HOME}" ]]; then
        return 1
    fi
    if [[ -e "${root}" ]]; then
        [[ ! -L "${root}" ]] || return 1
        physical="$(cd -P "${root}" 2>/dev/null && pwd -P)" || return 1
        logical="$(cd "${root}" 2>/dev/null && pwd)" || return 1
        [[ "${physical}" == "${logical}" ]] || return 1
    fi
    return 0
}

macos_location_permission_helper_schema_version() {
    printf '2026.07.02.4\n'
}

write_macos_location_permission_helper_source() {
    local script_file="$1"
    cat > "${script_file}" <<'APPLESCRIPT'
use framework "CoreLocation"
use framework "CoreWLAN"
use framework "Foundation"
use scripting additions

property locationManager : missing value

on writeText(theText, outputPath)
    set fileRef to missing value
    try
        set fileRef to open for access (POSIX file outputPath) with write permission
        set eof of fileRef to 0
        write theText to fileRef as «class utf8»
        close access fileRef
    on error
        try
            if fileRef is not missing value then close access fileRef
        end try
    end try
end writeText

on run argv
    set outputPath to ""
    if (count of argv) > 0 then set outputPath to item 1 of argv
    set ssidValue to ""
    set statusValue to "requested"
    if ((current application's CLLocationManager's locationServicesEnabled()) as boolean) is false then
        error "macOS Location Services is disabled."
    end if
    set locationManager to current application's CLLocationManager's alloc()'s init()
    locationManager's requestWhenInUseAuthorization()
    locationManager's startUpdatingLocation()
    set deadline to current application's NSDate's dateWithTimeIntervalSinceNow:8
    repeat while ((deadline's timeIntervalSinceNow()) as real) > 0
        current application's NSRunLoop's currentRunLoop()'s runUntilDate:(current application's NSDate's dateWithTimeIntervalSinceNow:0.2)
    end repeat
    try
        set statusObject to current application's CLLocationManager's authorizationStatus()
        set statusValue to (statusObject as integer) as text
    end try
    try
        set wifiClient to current application's CWWiFiClient's sharedWiFiClient()
        set wifiInterface to wifiClient's interface()
        if wifiInterface is not missing value then
            set ssidObject to wifiInterface's ssid()
            if ssidObject is not missing value then set ssidValue to ssidObject as text
        end if
    end try
    locationManager's stopUpdatingLocation()
    if outputPath is not "" then my writeText("status=" & statusValue & linefeed & "ssid=" & ssidValue & linefeed, outputPath)
    return statusValue
end run
APPLESCRIPT
}

write_macos_location_permission_helper_plist() {
    local plist="$1" schema_version
    schema_version="$(macos_location_permission_helper_schema_version)"
    cat > "${plist}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>fr.schweppes.po0.location-permission-helper</string>
    <key>CFBundleExecutable</key>
    <string>applet</string>
    <key>CFBundleName</key>
    <string>PO0 Location Permission Helper</string>
    <key>CFBundleDisplayName</key>
    <string>PO0 Location Permission Helper</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>${schema_version}</string>
    <key>PO0HelperSchemaVersion</key>
    <string>${schema_version}</string>
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>PO0 uses location permission only so macOS allows this helper to read the current Wi-Fi SSID for local skip rules.</string>
    <key>NSLocationUsageDescription</key>
    <string>PO0 uses location permission only so macOS allows this helper to read the current Wi-Fi SSID for local skip rules.</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST
}

macos_location_permission_helper_app_is_current() {
    local app_dir="$1" plist schema_version
    plist="${app_dir}/Contents/Info.plist"
    schema_version="$(macos_location_permission_helper_schema_version)"
    [[ -d "${app_dir}" && -f "${plist}" ]] || return 1
    [[ -x "${app_dir}/Contents/MacOS/applet" ]] || return 1
    grep -Fq 'fr.schweppes.po0.location-permission-helper' "${plist}" || return 1
    grep -Fq 'CFBundleExecutable' "${plist}" || return 1
    grep -Fq 'CFBundlePackageType' "${plist}" || return 1
    grep -Fq 'NSLocationUsageDescription' "${plist}" || return 1
    grep -Fq 'NSLocationWhenInUseUsageDescription' "${plist}" || return 1
    grep -Fq 'PO0HelperSchemaVersion' "${plist}" || return 1
    grep -Fq "<string>${schema_version}</string>" "${plist}" || return 1
}

macos_location_permission_helper_app_has_po0_identity() {
    local app_dir="$1" plist
    plist="${app_dir}/Contents/Info.plist"
    [[ -d "${app_dir}" && ! -L "${app_dir}" && -f "${plist}" ]] || return 1
    grep -Fq 'fr.schweppes.po0.location-permission-helper' "${plist}" || return 1
    grep -Fq 'PO0HelperSchemaVersion' "${plist}" || return 1
}

create_macos_location_helper_output_file() {
    local output_dir output_file
    output_dir="$(mktemp -d "${TMPDIR:-/tmp}/po0-location-helper.XXXXXX")" || return 1
    chmod 700 "${output_dir}" 2>/dev/null || true
    output_file="${output_dir}/output.env"
    : > "${output_file}" || {
        rmdir "${output_dir}" 2>/dev/null || true
        return 1
    }
    chmod 600 "${output_file}" 2>/dev/null || true
    printf '%s\n' "${output_file}"
}

cleanup_macos_location_helper_output_file() {
    local output_file="$1" output_dir
    [[ -n "${output_file}" ]] || return 0
    output_dir="${output_file%/*}"
    case "${output_dir}" in
        */po0-location-helper.*)
            rm -f "${output_file}" 2>/dev/null || true
            rmdir "${output_dir}" 2>/dev/null || true
            ;;
        *)
            rm -f "${output_file}" 2>/dev/null || true
            ;;
    esac
}

ensure_macos_location_permission_helper_app() {
    local app_dir root script_file plist rc
    command -v osacompile >/dev/null 2>&1 || return 127
    root="$(macos_location_permission_helper_root)" || return 1
    app_dir="$(macos_location_permission_helper_app_path)" || return 1
    validate_macos_location_permission_helper_app_path "${app_dir}" || return 1
    if macos_location_permission_helper_app_is_current "${app_dir}"; then
        printf '%s\n' "${app_dir}"
        return 0
    fi
    mkdir -p "${root}" || return 1
    script_file="${root}/po0-location-permission-helper.applescript"
    write_macos_location_permission_helper_source "${script_file}" || return 1
    if [[ -e "${app_dir}" || -L "${app_dir}" ]]; then
        macos_location_permission_helper_app_has_po0_identity "${app_dir}" || {
            rm -f "${script_file}" 2>/dev/null || true
            printf '拒绝替换不符合 PO0 Helper 身份的路径：%s\n' "${app_dir}" >&2
            return 1
        }
    fi
    rm -rf -- "${app_dir}" 2>/dev/null || true
    rc=0
    osacompile -o "${app_dir}" "${script_file}" >/dev/null 2>&1 || rc=$?
    rm -f "${script_file}" 2>/dev/null || true
    [[ "${rc}" == "0" ]] || return "${rc}"
    plist="${app_dir}/Contents/Info.plist"
    [[ -d "${app_dir}/Contents" ]] || mkdir -p "${app_dir}/Contents" || return 1
    write_macos_location_permission_helper_plist "${plist}" || return 1
    if command -v codesign >/dev/null 2>&1; then
        codesign --force --deep --sign - "${app_dir}" >/dev/null 2>&1 || true
    fi
    printf '%s\n' "${app_dir}"
}

remove_macos_location_permission_helper_app() {
    local app_dir
    app_dir="$(macos_location_permission_helper_app_path)" || {
        printf '无法确定 PO0 Location Permission Helper 路径。\n' >&2
        return 1
    }
    validate_macos_location_permission_helper_app_path "${app_dir}" || {
        printf '拒绝删除不符合预期的 Helper 路径：%s\n' "${app_dir}" >&2
        return 1
    }
    if [[ -e "${app_dir}" || -L "${app_dir}" ]]; then
        macos_location_permission_helper_app_has_po0_identity "${app_dir}" || {
            printf '拒绝删除不符合 PO0 Helper 身份的路径：%s\n' "${app_dir}" >&2
            return 1
        }
        if rm -rf -- "${app_dir}"; then
            printf '已删除 PO0 Location Permission Helper：%s\n' "${app_dir}"
        else
            printf '删除 PO0 Location Permission Helper 失败：%s\n' "${app_dir}" >&2
            return 1
        fi
    else
        printf 'PO0 Location Permission Helper 不存在：%s\n' "${app_dir}"
    fi
    printf '注意：删除 Helper 只移除本地 app 文件，不会修改 macOS 定位授权记录；如需撤销授权，请到系统设置 > 隐私与安全性 > 定位服务 中处理。\n'
}

remove_macos_location_permission_helper_app_interactive() {
    local app_dir
    app_dir="$(macos_location_permission_helper_app_path)" || {
        printf '无法确定 PO0 Location Permission Helper 路径。\n' >&2
        return 1
    }
    printf '将删除 PO0 Location Permission Helper：%s\n' "${app_dir}"
    printf '此操作不会修改 macOS 定位授权记录，也不会写入 TCC 数据库。\n'
    if ! prompt_yes_no "确认删除 PO0 Location Permission Helper" "n"; then
        printf '已取消。\n'
        return 2
    fi
    remove_macos_location_permission_helper_app
}

macos_location_helper_wifi_ssid() {
    local app_dir output_file output ssid rc line
    app_dir="$(macos_location_permission_helper_app_path)" || return 1
    [[ -d "${app_dir}" ]] || return 1
    command -v open >/dev/null 2>&1 || return 1
    output_file="$(create_macos_location_helper_output_file)" || return 1
    rc=0
    open -W -n "${app_dir}" --args "${output_file}" >/dev/null 2>&1 || rc=$?
    if [[ "${rc}" != "0" ]]; then
        cleanup_macos_location_helper_output_file "${output_file}"
        return "${rc}"
    fi
    output="$(cat "${output_file}" 2>/dev/null || true)"
    cleanup_macos_location_helper_output_file "${output_file}"
    ssid=""
    while IFS= read -r line || [[ -n "${line}" ]]; do
        case "${line}" in
            ssid=*)
                ssid="${line#ssid=}"
                break
                ;;
        esac
    done <<< "${output}"
    accepted_wifi_ssid_value "${ssid}"
}

request_macos_location_permission() {
    local app_dir output_file output rc ssid accepted_ssid line
    printf '将创建并打开 PO0 Location Permission Helper 来触发 macOS 定位权限请求。\n'
    printf '如果系统弹窗出现，请允许 PO0 Location Permission Helper 访问位置。\n'
    printf '本操作不会自动授予权限，不会运行 sudo，不会调用 tccutil，不会写入 TCC 数据库。\n'
    rc=0
    app_dir="$(ensure_macos_location_permission_helper_app 2>&1)" || rc=$?
    if [[ "${rc}" != "0" ]]; then
        if [[ "${rc}" == "127" ]]; then
            printf '未找到 osacompile，无法生成 macOS 定位权限 Helper App。\n' >&2
        else
            printf '生成 macOS 定位权限 Helper App 失败：%s\n' "${app_dir:-osacompile 返回失败。}" >&2
        fi
        printf '请确认系统包含 /usr/bin/osacompile，然后重试 --request-location-permission；也可手动执行：%s\n' "$(macos_location_services_settings_command)" >&2
        return 1
    fi
    output_file="$(create_macos_location_helper_output_file)" || return 1
    rc=0
    open -W -n "${app_dir}" --args "${output_file}" >/dev/null 2>&1 || rc=$?
    output="$(cat "${output_file}" 2>/dev/null || true)"
    cleanup_macos_location_helper_output_file "${output_file}"
    if [[ "${rc}" == "0" ]]; then
        printf '已尝试触发 macOS 定位权限请求。\n'
        ssid=""
        while IFS= read -r line || [[ -n "${line}" ]]; do
            case "${line}" in
                ssid=*) ssid="${line#ssid=}" ;;
            esac
        done <<< "${output}"
        accepted_ssid="$(accepted_wifi_ssid_value "${ssid}" 2>/dev/null || true)"
        if [[ -n "${accepted_ssid}" ]]; then
            printf 'Helper 当前读取到的 Wi-Fi SSID：%s\n' "${accepted_ssid}"
        fi
        printf '请打开定位服务设置确认 PO0 Location Permission Helper 是否已经出现在列表中：%s\n' "$(macos_location_services_settings_command)"
        printf '授权后请重新运行 --show-wifi-ssid 验证 SSID 是否可读。\n'
        return 0
    fi
    printf '打开 PO0 Location Permission Helper 未完成：%s\n' "${output:-open 返回失败。}" >&2
    printf '请确认 macOS 定位服务已开启，然后重试 --request-location-permission；也可手动执行：%s\n' "$(macos_location_services_settings_command)" >&2
    return 1
}

print_wifi_ssid_permission_guidance() {
    printf '%s\n' \
        "权限说明：macOS 可能把 Wi-Fi SSID/BSSID 作为定位相关信息保护。" \
        "Location Services：当前状态显示“macOS 隐私权限隐藏”时，通常是系统把 redacted/<redacted> 占位符返回给网络命令；本脚本已将其归类为读取失败，不会当作真实 SSID。" \
        "触发授权弹窗：po0-outbound-ip-report --request-location-permission（会创建并打开 PO0 Location Permission Helper）" \
        "打开定位服务设置：$(macos_location_services_settings_command)" \
        "在 系统设置 > 隐私与安全性 > 定位服务 中允许 PO0 Location Permission Helper 访问位置。" \
        "如果列表里没有 Terminal/iTerm，这是正常限制；macOS 26+ 更可靠的授权主体是带用途声明的 Helper App。" \
        "授权后 Helper 会在本机读取 Wi-Fi SSID；shell、LAN Worker 和 PO0 协议不会接收 SSID。" \
        "launchd 后台任务和手动 Terminal/iTerm 可能是不同运行环境；授权后请重新运行 --show-wifi-ssid 验证。" \
        "no auto-grant：本脚本只做诊断和提示，不会自动授予 macOS 隐私权限。" \
        "本脚本不会自动获取或修改系统权限，不会写入 TCC 数据库，不会使用 sudo 缓存凭据。" \
        "读取不到 SSID 时仍会 fail-open 继续正常上报。"
}

wifi_hardware_device() {
    command -v networksetup >/dev/null 2>&1 || return 1
    networksetup -listallhardwareports 2>/dev/null | awk '
        /^Hardware Port: / {
            port=$0
            sub(/^Hardware Port: /, "", port)
            wifi=(port == "Wi-Fi" || port == "AirPort")
            next
        }
        wifi && /^Device: / {
            sub(/^Device: /, "")
            print
            exit
        }
    '
}

networksetup_all_devices() {
    command -v networksetup >/dev/null 2>&1 || return 1
    networksetup -listallhardwareports 2>/dev/null | awk '
        /^Device:[[:space:]]*/ {
            sub(/^Device:[[:space:]]*/, "")
            if ($0 != "") {
                print
            }
        }
    '
}

networksetup_wifi_ssid() {
    local device="$1" output ssid
    [[ -n "${device}" ]] || return 1
    command -v networksetup >/dev/null 2>&1 || return 1
    output="$(networksetup -getairportnetwork "${device}" 2>/dev/null || true)"
    output="${output%$'\r'}"
    case "${output}" in
        *"not associated"*|*"Not associated"*|*"not a Wi-Fi interface"*|*"not a Wi-Fi device"*|*"not an AirPort interface"*|"")
            return 1
            ;;
    esac
    [[ "${output}" == *:* ]] || return 1
    ssid="${output#*:}"
    accepted_wifi_ssid_value "${ssid}"
}

networksetup_any_wifi_ssid() {
    local device ssid seen=";" rc
    while IFS= read -r device || [[ -n "${device}" ]]; do
        device="$(trim "${device}")"
        [[ -n "${device}" ]] || continue
        case "${seen}" in
            *";${device};"*) continue ;;
        esac
        seen="${seen}${device};"
        rc=0
        ssid="$(networksetup_wifi_ssid "${device}" 2>/dev/null)" || rc=$?
        if [[ "${rc}" == "0" && -n "${ssid}" ]]; then
            printf '%s\n' "${ssid}"
            return 0
        fi
        [[ "${rc}" == "2" ]] && return 2
    done < <(networksetup_all_devices)
    return 1
}

networksetup_common_wifi_ssid() {
    local device ssid rc
    for device in en0 en1 en2; do
        rc=0
        ssid="$(networksetup_wifi_ssid "${device}" 2>/dev/null)" || rc=$?
        if [[ "${rc}" == "0" && -n "${ssid}" ]]; then
            printf '%s\n' "${ssid}"
            return 0
        fi
        [[ "${rc}" == "2" ]] && return 2
    done
    return 1
}

ipconfig_wifi_ssid() {
    local device="$1" ssid
    [[ -n "${device}" ]] || return 1
    command -v ipconfig >/dev/null 2>&1 || return 1
    ssid="$(ipconfig getsummary "${device}" 2>/dev/null | awk '
        /^[[:space:]]*SSID[[:space:]]*:/ {
            line=$0
            sub(/^[^:]*:[[:space:]]*/, "", line)
            print line
            exit
        }
    ')"
    accepted_wifi_ssid_value "${ssid}"
}

airport_command_path() {
    if command -v airport >/dev/null 2>&1; then
        command -v airport
        return 0
    fi
    if [[ -x "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport" ]]; then
        printf '%s\n' "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"
        return 0
    fi
    return 1
}

airport_wifi_ssid() {
    local airport ssid
    airport="$(airport_command_path 2>/dev/null || true)"
    [[ -n "${airport}" ]] || return 1
    ssid="$("${airport}" -I 2>/dev/null | awk '
        /^[[:space:]]*SSID[[:space:]]*:/ {
            line=$0
            sub(/^[^:]*:[[:space:]]*/, "", line)
            print line
            exit
        }
    ')"
    accepted_wifi_ssid_value "${ssid}"
}

wdutil_wifi_ssid() {
    local ssid
    command -v wdutil >/dev/null 2>&1 || return 1
    ssid="$(wdutil info 2>/dev/null | awk '
        /^[[:space:]]*SSID[[:space:]]*:/ {
            line=$0
            sub(/^[^:]*:[[:space:]]*/, "", line)
            print line
            exit
        }
    ')"
    case "$(to_lower "$(trim "${ssid}")")" in
        none)
            return 1
            ;;
    esac
    accepted_wifi_ssid_value "${ssid}"
}

current_wifi_ssid() {
    local device
    WIFI_SSID_LAST_ERROR=""
    WIFI_SSID_PROBE_VALUE=""
    device="$(wifi_hardware_device 2>/dev/null || true)"
    if [[ -n "${device}" ]]; then
        if capture_wifi_ssid_probe networksetup_wifi_ssid "${device}"; then
            printf '%s\n' "${WIFI_SSID_PROBE_VALUE}"
            return 0
        fi
        if capture_wifi_ssid_probe ipconfig_wifi_ssid "${device}"; then
            printf '%s\n' "${WIFI_SSID_PROBE_VALUE}"
            return 0
        fi
    fi
    if capture_wifi_ssid_probe networksetup_any_wifi_ssid; then
        printf '%s\n' "${WIFI_SSID_PROBE_VALUE}"
        return 0
    fi
    if capture_wifi_ssid_probe networksetup_common_wifi_ssid; then
        printf '%s\n' "${WIFI_SSID_PROBE_VALUE}"
        return 0
    fi
    if capture_wifi_ssid_probe airport_wifi_ssid; then
        printf '%s\n' "${WIFI_SSID_PROBE_VALUE}"
        return 0
    fi
    if capture_wifi_ssid_probe wdutil_wifi_ssid; then
        printf '%s\n' "${WIFI_SSID_PROBE_VALUE}"
        return 0
    fi
    if capture_wifi_ssid_probe macos_location_helper_wifi_ssid; then
        printf '%s\n' "${WIFI_SSID_PROBE_VALUE}"
        return 0
    fi
    return 1
}

current_wifi_ssid_label() {
    if current_wifi_ssid >/dev/null 2>&1; then
        printf '%s\n' "${WIFI_SSID_PROBE_VALUE}"
    else
        wifi_ssid_read_failure_label
    fi
}

show_current_wifi_ssid_once() {
    if current_wifi_ssid >/dev/null 2>&1; then
        printf '当前 Wi-Fi SSID：%s\n' "${WIFI_SSID_PROBE_VALUE}"
        return 0
    fi
    printf '当前 Wi-Fi SSID：%s\n' "$(wifi_ssid_read_failure_label)"
    return 1
}

show_wifi_ssid_permission_help() {
    if current_wifi_ssid >/dev/null 2>&1; then
        printf '当前 Wi-Fi SSID：%s\n\n' "${WIFI_SSID_PROBE_VALUE}"
    else
        printf '当前 Wi-Fi SSID：%s\n\n' "$(wifi_ssid_read_failure_label)"
    fi
    print_wifi_ssid_permission_guidance
}

show_wifi_ssid_permission_help_interactive() {
    show_wifi_ssid_permission_help
    printf '\n'
    if prompt_yes_no "是否现在尝试触发 macOS 定位权限请求" "y"; then
        request_macos_location_permission
    else
        printf '已跳过定位权限请求。\n'
    fi
}

wifi_ssid_in_skip_list() {
    local ssid="$1" list="${2:-${SKIP_WIFI_SSIDS:-}}" rest item
    list="$(normalize_wifi_ssid_skip_list "${list}")"
    [[ -n "${ssid}" && -n "${list}" ]] || return 1
    rest="${list};"
    while [[ -n "${rest}" ]]; do
        item="${rest%%;*}"
        rest="${rest#*;}"
        item="$(trim "${item}")"
        [[ -n "${item}" ]] || continue
        [[ "${item}" == "${ssid}" ]] && return 0
    done
    return 1
}

force_report_enabled() {
    case "$(to_lower "${FORCE_REPORT:-0}")" in
        1|true|yes|y|on|enabled) return 0 ;;
        *) return 1 ;;
    esac
}

should_skip_wifi_ssid_report() {
    local list ssid
    force_report_enabled && return 1
    list="$(normalize_wifi_ssid_skip_list "${SKIP_WIFI_SSIDS:-}")"
    [[ -n "${list}" ]] || return 1
    current_wifi_ssid >/dev/null 2>&1 || return 1
    ssid="${WIFI_SSID_PROBE_VALUE:-}"
    [[ -n "${ssid}" ]] || return 1
    if wifi_ssid_in_skip_list "${ssid}" "${list}"; then
        WIFI_SKIP_LAST_SSID="${ssid}"
        return 0
    fi
    return 1
}

wifi_ssid_skip_message() {
    local ssid="${1:-${WIFI_SKIP_LAST_SSID:-}}"
    if [[ -n "${ssid}" ]]; then
        printf '已跳过：当前 Wi-Fi SSID "%s" 命中跳过列表。' "${ssid}"
    else
        printf '已跳过：当前 Wi-Fi SSID 命中跳过列表。'
    fi
}

prompt_skip_wifi_ssids_interactive() {
    local input
    SKIP_WIFI_SSIDS="$(normalize_wifi_ssid_skip_list "${SKIP_WIFI_SSIDS:-}")"
    if [[ -n "${SKIP_WIFI_SSIDS}" ]]; then
        input="$(read_prompt "跳过上报的 Wi-Fi SSID（分号 ; 分隔，精确大小写匹配；回车保留，输入 - 清空）[${SKIP_WIFI_SSIDS}]: ")" || input=""
        input="$(trim "${input}")"
        case "${input}" in
            "") ;;
            "-") SKIP_WIFI_SSIDS="" ;;
            *) SKIP_WIFI_SSIDS="$(normalize_wifi_ssid_skip_list "${input}")" ;;
        esac
    else
        input="$(read_prompt "跳过上报的 Wi-Fi SSID（分号 ; 分隔，留空不跳过）: ")" || input=""
        SKIP_WIFI_SSIDS="$(normalize_wifi_ssid_skip_list "${input}")"
    fi
}
