write_env_assignment() {
    local name="$1"
    local value="$2"
    printf '%s=%s\n' "${name}" "$(sh_quote "${value}")"
}

load_saved_config() {
    local read_file
    read_file="$(config_read_file 2>/dev/null || true)"
    [[ -n "${read_file}" && -r "${read_file}" ]] || return 0
    # This file is created by this script with chmod 600 and may contain secrets.
    # shellcheck disable=SC1090
    . "${read_file}" || return 1
    normalize_legacy_default_install_path
}

apply_env_overrides() {
    [[ -n "${PO0_LAN_WORKER_URL+x}" ]] && WORKER_URL="${PO0_LAN_WORKER_URL}"
    [[ -n "${PO0_OUTBOUND_IP_REPORT_WORKER_URL+x}" ]] && WORKER_URL="${PO0_OUTBOUND_IP_REPORT_WORKER_URL}"
    [[ -n "${ENV_WORKER_URL}" ]] && WORKER_URL="${ENV_WORKER_URL}"
    if [[ -n "${PO0_OUTBOUND_IP_REPORT_SOURCE+x}" ]]; then
        SOURCE_ID="${PO0_OUTBOUND_IP_REPORT_SOURCE}"
        SOURCE_ID_EXPLICIT="1"
    fi
    if [[ -n "${PO0_SELF_REPORT_SOURCE+x}" ]]; then
        SOURCE_ID="${PO0_SELF_REPORT_SOURCE}"
        SOURCE_ID_EXPLICIT="1"
    fi
    if [[ -n "${ENV_SOURCE_ID}" ]]; then
        SOURCE_ID="${ENV_SOURCE_ID}"
        SOURCE_ID_EXPLICIT="1"
    fi
    if [[ -n "${PO0_OUTBOUND_IP_REPORT_IDENTITY+x}" ]]; then
        IDENTITY="${PO0_OUTBOUND_IP_REPORT_IDENTITY}"
        IDENTITY_EXPLICIT="1"
    fi
    if [[ -n "${PO0_SELF_REPORT_IDENTITY+x}" ]]; then
        IDENTITY="${PO0_SELF_REPORT_IDENTITY}"
        IDENTITY_EXPLICIT="1"
    fi
    if [[ -n "${ENV_IDENTITY}" ]]; then
        IDENTITY="${ENV_IDENTITY}"
        IDENTITY_EXPLICIT="1"
    fi
    [[ -n "${PO0_OUTBOUND_IP_REPORT_SECRET+x}" ]] && SECRET="${PO0_OUTBOUND_IP_REPORT_SECRET}"
    [[ -n "${PO0_SELF_REPORT_SECRET+x}" ]] && SECRET="${PO0_SELF_REPORT_SECRET}"
    [[ -n "${SELF_REPORT_SECRET+x}" ]] && SECRET="${SELF_REPORT_SECRET}"
    [[ -n "${PO0_OUTBOUND_IP_REPORT_ALLOW_HTTP+x}" ]] && ALLOW_HTTP="${PO0_OUTBOUND_IP_REPORT_ALLOW_HTTP}"
    [[ -n "${PO0_SELF_REPORT_ALLOW_HTTP+x}" ]] && ALLOW_HTTP="${PO0_SELF_REPORT_ALLOW_HTTP}"
    [[ -n "${ENV_ALLOW_HTTP}" ]] && ALLOW_HTTP="${ENV_ALLOW_HTTP}"
    [[ -n "${PO0_OUTBOUND_IP_REPORT_IP_CHECK_URL+x}" ]] && IP_CHECK_URL="${PO0_OUTBOUND_IP_REPORT_IP_CHECK_URL}"
    [[ -n "${ENV_IP_CHECK_URL}" ]] && IP_CHECK_URL="${ENV_IP_CHECK_URL}"
    [[ -n "${PO0_OUTBOUND_IP_REPORT_IP_CHECK_URLS+x}" ]] && IP_CHECK_URLS="${PO0_OUTBOUND_IP_REPORT_IP_CHECK_URLS}"
    [[ -n "${ENV_IP_CHECK_URLS}" ]] && IP_CHECK_URLS="${ENV_IP_CHECK_URLS}"
    [[ -n "${PO0_OUTBOUND_IP_REPORT_WANS+x}" ]] && WANS="${PO0_OUTBOUND_IP_REPORT_WANS}"
    [[ -n "${PO0_OUTBOUND_IP_REPORT_WORKER_ENABLED+x}" ]] && WORKER_ENABLED="${PO0_OUTBOUND_IP_REPORT_WORKER_ENABLED}"
    if [[ "${ENV_FIREWALL_TOKENS_SET:-0}" == "1" ]]; then
        PO0_FIREWALL_TOKENS="${ENV_FIREWALL_TOKENS}"
    fi
    [[ -n "${ENV_WORKER_ENABLED}" ]] && WORKER_ENABLED="${ENV_WORKER_ENABLED}"
    [[ -n "${PO0_OUTBOUND_IP_REPORT_SKIP_WIFI_SSIDS+x}" ]] && SKIP_WIFI_SSIDS="${PO0_OUTBOUND_IP_REPORT_SKIP_WIFI_SSIDS}"
    [[ -n "${ENV_SKIP_WIFI_SSIDS}" ]] && SKIP_WIFI_SSIDS="${ENV_SKIP_WIFI_SSIDS}"
    if [[ -n "${PO0_OUTBOUND_IP_REPORT_INSTALL_PATH+x}" ]]; then
        INSTALL_PATH="${PO0_OUTBOUND_IP_REPORT_INSTALL_PATH}"
        INSTALL_PATH_EXPLICIT="1"
    fi
    [[ -n "${PO0_SELF_REPORT_INSTALL_PATH+x}" ]] && INSTALL_PATH="${PO0_SELF_REPORT_INSTALL_PATH}"
    [[ -n "${PO0_SELF_REPORT_INSTALL_PATH+x}" ]] && INSTALL_PATH_EXPLICIT="1"
    [[ -n "${ENV_INSTALL_PATH}" ]] && INSTALL_PATH="${ENV_INSTALL_PATH}" && INSTALL_PATH_EXPLICIT="1"
    [[ -n "${PO0_OUTBOUND_IP_REPORT_MINUTES+x}" ]] && CRON_MINUTES="${PO0_OUTBOUND_IP_REPORT_MINUTES}"
    [[ -n "${PO0_SELF_REPORT_MINUTES+x}" ]] && CRON_MINUTES="${PO0_SELF_REPORT_MINUTES}"
    [[ -n "${ENV_MINUTES}" ]] && CRON_MINUTES="${ENV_MINUTES}"
    [[ -n "${PO0_OUTBOUND_IP_REPORT_INTERVAL_SECONDS+x}" ]] && INTERVAL_SECONDS="${PO0_OUTBOUND_IP_REPORT_INTERVAL_SECONDS}"
    [[ -n "${PO0_SELF_REPORT_INTERVAL_SECONDS+x}" ]] && INTERVAL_SECONDS="${PO0_SELF_REPORT_INTERVAL_SECONDS}"
    [[ -n "${ENV_INTERVAL_SECONDS}" ]] && INTERVAL_SECONDS="${ENV_INTERVAL_SECONDS}"
    [[ -n "${PO0_OUTBOUND_IP_REPORT_MAX_MINUTES+x}" ]] && MAX_CRON_MINUTES="${PO0_OUTBOUND_IP_REPORT_MAX_MINUTES}"
    [[ -n "${PO0_SELF_REPORT_MAX_MINUTES+x}" ]] && MAX_CRON_MINUTES="${PO0_SELF_REPORT_MAX_MINUTES}"
    [[ -n "${PO0_OUTBOUND_IP_REPORT_PAUSED+x}" ]] && SCHEDULE_PAUSED="${PO0_OUTBOUND_IP_REPORT_PAUSED}"
    [[ -n "${PO0_SELF_REPORT_PAUSED+x}" ]] && SCHEDULE_PAUSED="${PO0_SELF_REPORT_PAUSED}"
    # Canonical aliases win when both old and new environment variables are present.
    [[ -n "${PO0_OUTBOUND_IP_REPORT_WORKER_URL+x}" ]] && WORKER_URL="${PO0_OUTBOUND_IP_REPORT_WORKER_URL}"
    if [[ -n "${PO0_OUTBOUND_IP_REPORT_SOURCE+x}" ]]; then
        SOURCE_ID="${PO0_OUTBOUND_IP_REPORT_SOURCE}"
        SOURCE_ID_EXPLICIT="1"
    fi
    if [[ -n "${PO0_OUTBOUND_IP_REPORT_IDENTITY+x}" ]]; then
        IDENTITY="${PO0_OUTBOUND_IP_REPORT_IDENTITY}"
        IDENTITY_EXPLICIT="1"
    fi
    [[ -n "${PO0_OUTBOUND_IP_REPORT_SECRET+x}" ]] && SECRET="${PO0_OUTBOUND_IP_REPORT_SECRET}"
    [[ -n "${PO0_OUTBOUND_IP_REPORT_ALLOW_HTTP+x}" ]] && ALLOW_HTTP="${PO0_OUTBOUND_IP_REPORT_ALLOW_HTTP}"
    [[ -n "${PO0_OUTBOUND_IP_REPORT_IP_CHECK_URL+x}" ]] && IP_CHECK_URL="${PO0_OUTBOUND_IP_REPORT_IP_CHECK_URL}"
    [[ -n "${PO0_OUTBOUND_IP_REPORT_IP_CHECK_URLS+x}" ]] && IP_CHECK_URLS="${PO0_OUTBOUND_IP_REPORT_IP_CHECK_URLS}"
    [[ -n "${PO0_OUTBOUND_IP_REPORT_WANS+x}" ]] && WANS="${PO0_OUTBOUND_IP_REPORT_WANS}"
    [[ -n "${PO0_OUTBOUND_IP_REPORT_WORKER_ENABLED+x}" ]] && WORKER_ENABLED="${PO0_OUTBOUND_IP_REPORT_WORKER_ENABLED}"
    [[ -n "${PO0_OUTBOUND_IP_REPORT_SKIP_WIFI_SSIDS+x}" ]] && SKIP_WIFI_SSIDS="${PO0_OUTBOUND_IP_REPORT_SKIP_WIFI_SSIDS}"
    if [[ -n "${PO0_OUTBOUND_IP_REPORT_INSTALL_PATH+x}" ]]; then
        INSTALL_PATH="${PO0_OUTBOUND_IP_REPORT_INSTALL_PATH}"
        INSTALL_PATH_EXPLICIT="1"
    fi
    [[ -n "${PO0_OUTBOUND_IP_REPORT_MINUTES+x}" ]] && CRON_MINUTES="${PO0_OUTBOUND_IP_REPORT_MINUTES}"
    [[ -n "${PO0_OUTBOUND_IP_REPORT_INTERVAL_SECONDS+x}" ]] && INTERVAL_SECONDS="${PO0_OUTBOUND_IP_REPORT_INTERVAL_SECONDS}"
    [[ -n "${PO0_OUTBOUND_IP_REPORT_MAX_MINUTES+x}" ]] && MAX_CRON_MINUTES="${PO0_OUTBOUND_IP_REPORT_MAX_MINUTES}"
    [[ -n "${PO0_OUTBOUND_IP_REPORT_PAUSED+x}" ]] && SCHEDULE_PAUSED="${PO0_OUTBOUND_IP_REPORT_PAUSED}"
    WANS="$(normalize_wan_selection_list "${WANS:-}")"
    SKIP_WIFI_SSIDS="$(normalize_wifi_ssid_skip_list "${SKIP_WIFI_SSIDS:-}")"
    normalize_legacy_default_install_path
}

normalize_legacy_default_install_path() {
    [[ -n "${INSTALL_PATH:-}" ]] || return 0
    case "${INSTALL_PATH}" in
        "/usr/local/sbin/po0-self-report"|"${HOME:-}/.local/bin/po0-self-report"|"./po0-self-report")
            INSTALL_PATH=""
            ;;
    esac
}

sanitize_device_id_part() {
    local value="$1" out="" ch i
    value="$(trim "${value}")"
    value="$(to_lower "${value}")"
    for ((i = 0; i < ${#value}; i++)); do
        ch="${value:i:1}"
        case "${ch}" in
            [a-z0-9._-])
                out+="${ch}"
                ;;
            *)
                [[ "${out}" == *- ]] || out+="-"
                ;;
        esac
    done
    while [[ "${out}" == -* ]]; do out="${out#-}"; done
    while [[ "${out}" == *- ]]; do out="${out%-}"; done
    [[ -n "${out}" ]] || return 1
    [[ ${#out} -le 48 ]] || out="${out:0:48}"
    while [[ "${out}" == *- ]]; do out="${out%-}"; done
    printf '%s\n' "${out}"
}

normalize_report_token() {
    local value="$1" fallback="${2:-self-report}" normalized
    normalized="$(sanitize_device_id_part "${value}" 2>/dev/null || true)"
    if [[ -n "${normalized}" ]]; then
        printf '%s\n' "${normalized}"
    else
        printf '%s\n' "${fallback}"
    fi
}

default_device_hostname() {
    local value
    value="$(hostname 2>/dev/null || true)"
    value="$(trim "${value}")"
    case "$(to_lower "${value}")" in
        ""|"(none)"|"localhost"|"localhost.localdomain")
            value=""
            ;;
    esac
    if [[ -z "${value}" && -r /proc/sys/kernel/hostname ]]; then
        IFS= read -r value < /proc/sys/kernel/hostname || value=""
        value="$(trim "${value}")"
    fi
    [[ -n "${value}" ]] || value="linux-device"
    printf '%s\n' "${value}"
}

default_machine_id_part() {
    local path value
    for path in /etc/machine-id /var/lib/dbus/machine-id; do
        [[ -r "${path}" ]] || continue
        IFS= read -r value < "${path}" || value=""
        value="$(trim "${value}")"
        value="${value//-/}"
        value="$(to_lower "${value}")"
        [[ "${value}" =~ ^[0-9a-f]+$ ]] || continue
        if [[ ${#value} -ge 8 ]]; then
            printf '%s\n' "${value:0:16}"
            return 0
        fi
    done
    return 1
}

default_mac_id_part() {
    local path iface value
    for path in /sys/class/net/*/address; do
        [[ -r "${path}" ]] || continue
        iface="${path%/address}"
        iface="${iface##*/}"
        [[ "${iface}" == "lo" ]] && continue
        IFS= read -r value < "${path}" || value=""
        value="$(trim "${value}")"
        value="${value//:/}"
        value="$(to_lower "${value}")"
        [[ ${#value} -eq 12 ]] || continue
        [[ "${value}" =~ ^[0-9a-f]+$ ]] || continue
        [[ "${value}" =~ ^0+$ ]] && continue
        printf '%s\n' "${value}"
        return 0
    done
    return 1
}

default_source_id() {
    local host host_part id_part
    host="$(default_device_hostname)"
    host_part="$(sanitize_device_id_part "${host}" 2>/dev/null || true)"
    [[ -n "${host_part}" ]] || host_part="linux-device"
    id_part="$(default_machine_id_part 2>/dev/null || default_mac_id_part 2>/dev/null || true)"
    if [[ -n "${id_part}" ]]; then
        printf '%s-%s\n' "${host_part}" "${id_part}"
    else
        printf '%s\n' "${host_part}"
    fi
}

apply_device_defaults() {
    if [[ "${IDENTITY_EXPLICIT}" != "1" ]]; then
        case "${IDENTITY}" in
            ""|"self-report"|"linux-self-report")
                IDENTITY="$(default_device_hostname)"
                ;;
        esac
    fi
    if [[ "${SOURCE_ID_EXPLICIT}" != "1" ]]; then
        case "${SOURCE_ID}" in
            ""|"self-report"|"linux-self-report")
                SOURCE_ID="$(default_source_id)"
                ;;
        esac
    fi
    SOURCE_ID="$(normalize_report_token "${SOURCE_ID}" "$(default_source_id)")"
}

save_config_file() {
    local dir tmp old_umask
    validate_cron_minutes || return 1
    WANS="$(normalize_wan_selection_list "${WANS:-}")"
    validate_wan_selection || return 1
    if declare -F official_channel_enabled >/dev/null 2>&1 && official_channel_enabled; then
        official_validate_tokens || return 1
    fi
    SKIP_WIFI_SSIDS="$(normalize_wifi_ssid_skip_list "${SKIP_WIFI_SSIDS:-}")"
    dir="$(path_dirname "${CONFIG_FILE}")"
    mkdir -p "${dir}" || return 1
    tmp="${CONFIG_FILE}.tmp.$$"
    old_umask="$(umask)"
    umask 077
    {
        printf '# PO0 self-report client settings. This file may contain secrets.\n'
        write_env_assignment "WORKER_AUTO_ENABLED" "${WORKER_AUTO_ENABLED:-1}"
        write_env_assignment "OFFICIAL_AUTO_ENABLED" "${OFFICIAL_AUTO_ENABLED:-1}"
        write_env_assignment "WORKER_NAME" "${WORKER_NAME:-}"
        write_env_assignment "PO0_FIREWALL_NAMES" "${PO0_FIREWALL_NAMES:-}"
        write_env_assignment "WORKER_URL" "${WORKER_URL}"
        write_env_assignment "SOURCE_ID" "${SOURCE_ID}"
        write_env_assignment "IDENTITY" "${IDENTITY}"
        write_env_assignment "SECRET" "${SECRET}"
        write_env_assignment "ALLOW_HTTP" "${ALLOW_HTTP}"
        write_env_assignment "IP_CHECK_URL" "${IP_CHECK_URL}"
        write_env_assignment "IP_CHECK_URLS" "${IP_CHECK_URLS}"
        write_env_assignment "WANS" "${WANS}"
        write_env_assignment "WORKER_ENABLED" "${WORKER_ENABLED:-}"
        write_env_assignment "PO0_FIREWALL_TOKENS" "${PO0_FIREWALL_TOKENS:-}"
        write_env_assignment "SKIP_WIFI_SSIDS" "${SKIP_WIFI_SSIDS}"
        write_env_assignment "INSTALL_PATH" "${INSTALL_PATH}"
        write_env_assignment "CRON_MINUTES" "${CRON_MINUTES}"
        write_env_assignment "INTERVAL_SECONDS" "$((10#${CRON_MINUTES:-60} * 60))"
        write_env_assignment "MAX_CRON_MINUTES" "${MAX_CRON_MINUTES}"
        write_env_assignment "SCHEDULE_PAUSED" "${SCHEDULE_PAUSED}"
    } > "${tmp}" || {
        umask "${old_umask}"
        rm -f "${tmp}" 2>/dev/null || true
        return 1
    }
    umask "${old_umask}"
    mv -f "${tmp}" "${CONFIG_FILE}" || return 1
    chmod 600 "${CONFIG_FILE}" 2>/dev/null || true
    self_report_completed "配置已保存：${CONFIG_FILE}"
}
