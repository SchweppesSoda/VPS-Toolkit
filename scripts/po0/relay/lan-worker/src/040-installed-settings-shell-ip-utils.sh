normalize_report_ttl_settings() {
    SELF_REPORT_TTL_SECONDS="$(normalize_report_ttl_seconds "${SELF_REPORT_TTL_SECONDS}" 43200)"
    WEBAUTH_TTL_SECONDS="$(normalize_report_ttl_seconds "${WEBAUTH_TTL_SECONDS}" 43200)"
}

load_settings_from_installed_services() {
    local loaded="${1:-0}"
    local self_unit="/etc/systemd/system/po0-lan-self-report.service"
    local webauth_unit="/etc/systemd/system/po0-lan-webauth.service"
    local manager_update_unit="/etc/systemd/system/po0-lan-manager-update.service"
    fill_setting_from_unit_arg "${loaded}" SELF_REPORT_LISTEN "${self_unit}" "--self-report-listen"
    fill_setting_from_unit_arg "${loaded}" SELF_REPORT_SECRET "${self_unit}" "--self-report-secret"
    fill_setting_from_unit_arg "${loaded}" SELF_REPORT_SOURCE "${self_unit}" "--self-report-source"
    fill_setting_from_unit_arg "${loaded}" SELF_REPORT_TTL_SECONDS "${self_unit}" "--self-report-ttl"
    fill_setting_from_unit_arg "${loaded}" SELF_REPORT_TARGETS "${self_unit}" "--self-report-targets"
    fill_setting_from_unit_arg "${loaded}" PO0_HOST "${self_unit}" "--po0-host"
    fill_setting_from_unit_arg "${loaded}" PO0_PORT "${self_unit}" "--po0-port"
    fill_setting_from_unit_arg "${loaded}" PO0_USER "${self_unit}" "--po0-user"
    fill_setting_from_unit_arg "${loaded}" PO0_SCRIPT "${self_unit}" "--po0-script"
    fill_setting_from_unit_arg "${loaded}" CLIENT_IP_TOKEN "${self_unit}" "--client-ip-token"
    fill_setting_from_unit_arg "${loaded}" WEBAUTH_LISTEN "${webauth_unit}" "--listen"
    fill_setting_from_unit_arg "${loaded}" WEBAUTH_SOURCE "${webauth_unit}" "--webauth-source"
    fill_setting_from_unit_arg "${loaded}" WEBAUTH_TOKEN "${webauth_unit}" "--webauth-token"
    fill_setting_from_unit_arg "${loaded}" WEBAUTH_TTL_SECONDS "${webauth_unit}" "--webauth-ttl"
    fill_setting_from_unit_arg "${loaded}" WEBAUTH_TARGETS "${webauth_unit}" "--webauth-targets"
    fill_setting_from_unit_arg "${loaded}" MANAGER_UPDATE_LISTEN "${manager_update_unit}" "--manager-update-listen"
}

sh_quote() {
    local value="$1"
    value="${value//\'/\'\\\'\'}"
    printf "'%s'" "${value}"
}

ps_quote() {
    local value="$1" quote="'"
    value="${value//${quote}/${quote}${quote}}"
    printf "'%s'" "${value}"
}

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

validate_ip() {
    local ip="$1"
    local IFS='.'
    local octet
    local -a octets=()
    [[ "${ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    [[ ! "${ip}" =~ (^|\.)0[0-9] ]] || return 1
    read -r -a octets <<< "${ip}"
    for octet in "${octets[@]}"; do
        (( octet >= 0 && octet <= 255 )) || return 1
    done
}

is_public_ipv4() {
    local ip="$1"
    local o1 o2
    validate_ip "${ip}" || return 1
    IFS='.' read -r o1 o2 _ _ <<< "${ip}"
    (( o1 == 0 )) && return 1
    (( o1 == 10 )) && return 1
    (( o1 == 127 )) && return 1
    (( o1 == 169 && o2 == 254 )) && return 1
    (( o1 == 172 && o2 >= 16 && o2 <= 31 )) && return 1
    (( o1 == 192 && o2 == 168 )) && return 1
    (( o1 == 100 && o2 >= 64 && o2 <= 127 )) && return 1
    (( o1 == 198 && o2 >= 18 && o2 <= 19 )) && return 1
    (( o1 >= 224 )) && return 1
    return 0
}

extract_first_public_ipv4() {
    local text="$1" ip
    while IFS= read -r ip; do
        ip="$(trim "${ip}")"
        is_public_ipv4 "${ip}" || continue
        printf '%s\n' "${ip}"
        return 0
    done < <(printf '%s\n' "${text}" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' || true)
    return 1
}

extract_public_ipv4_csv() {
    local text="$1" ip csv="" seen=","
    while IFS= read -r ip; do
        ip="$(trim "${ip}")"
        is_public_ipv4 "${ip}" || continue
        case "${seen}" in
            *,"${ip}",*) continue ;;
        esac
        seen+="${ip},"
        if [[ -n "${csv}" ]]; then
            csv+=",${ip}"
        else
            csv="${ip}"
        fi
    done < <(printf '%s\n' "${text}" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' || true)
    [[ -n "${csv}" ]] || return 1
    printf '%s\n' "${csv}"
}

normalize_report_mode() {
    local mode
    mode="$(trim "${1:-}")"
    case "${mode}" in
        ""|auto)
            printf 'auto\n'
            ;;
        ddns|ddns-resolver|resolver)
            printf 'ddns\n'
            ;;
        none|resource|resource-only|off)
            printf 'none\n'
            ;;
        *)
            printf 'auto\n'
            ;;
    esac
}

resolve_ddns_ipv4_csv() {
    local domain="$1" raw="" out=""
    domain="$(trim "${domain}")"
    [[ -n "${domain}" ]] || return 1
    if have_cmd getent; then
        raw+="$(getent ahostsv4 "${domain}" 2>/dev/null || true)"$'\n'
    fi
    if have_cmd dig; then
        raw+="$(dig +short A "${domain}" 2>/dev/null || true)"$'\n'
    fi
    if have_cmd host; then
        raw+="$(host -t A "${domain}" 2>/dev/null || true)"$'\n'
    fi
    if have_cmd nslookup; then
        raw+="$(nslookup -type=A "${domain}" 2>/dev/null || true)"$'\n'
    fi
    out="$(extract_public_ipv4_csv "${raw}" 2>/dev/null || true)"
    [[ -n "${out}" ]] || return 1
    printf '%s\n' "${out}"
}
