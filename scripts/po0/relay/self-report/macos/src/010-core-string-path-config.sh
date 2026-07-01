trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "${value}"
}

sh_quote() {
    local value="$1"
    value="${value//\'/\'\\\'\'}"
    printf "'%s'" "${value}"
}

path_dirname() {
    local path="$1"
    case "${path}" in
        */*) printf '%s\n' "${path%/*}" ;;
        *) printf '.\n' ;;
    esac
}

canonical_config_file() {
    if [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]]; then
        printf '%s\n' "/etc/po0-outbound-ip-report/settings.env"
    elif [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
        printf '%s\n' "${XDG_CONFIG_HOME}/po0-outbound-ip-report/settings.env"
    elif [[ -n "${HOME:-}" ]]; then
        printf '%s\n' "${HOME}/.config/po0-outbound-ip-report/settings.env"
    else
        printf '%s\n' "./po0-outbound-ip-report.env"
    fi
}

legacy_config_file() {
    if [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]]; then
        printf '%s\n' "/etc/po0-self-report/settings.env"
    elif [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
        printf '%s\n' "${XDG_CONFIG_HOME}/po0-self-report/settings.env"
    elif [[ -n "${HOME:-}" ]]; then
        printf '%s\n' "${HOME}/.config/po0-self-report/settings.env"
    else
        printf '%s\n' "./po0-self-report.env"
    fi
}

default_config_file() {
    if [[ -n "${CONFIG_FILE}" && "${CONFIG_FILE_EXPLICIT}" == "1" ]]; then
        printf '%s\n' "${CONFIG_FILE}"
    else
        canonical_config_file
    fi
}

config_read_file() {
    local legacy
    if [[ -r "${CONFIG_FILE}" ]]; then
        printf '%s\n' "${CONFIG_FILE}"
        return 0
    fi
    [[ "${CONFIG_FILE_EXPLICIT}" == "1" ]] && return 1
    legacy="$(legacy_config_file)"
    if [[ -r "${legacy}" ]]; then
        printf '%s\n' "${legacy}"
        return 0
    fi
    return 1
}

prime_config_path_from_args() {
    local arg next
    while [[ $# -gt 0 ]]; do
        arg="$1"
        case "${arg}" in
            --config)
                next="${2:-}"
                if [[ -n "${next}" ]]; then
                    CONFIG_FILE="${next}"
                    CONFIG_FILE_EXPLICIT="1"
                fi
                shift 2 2>/dev/null || shift
                ;;
            --config=*)
                CONFIG_FILE="${arg#--config=}"
                CONFIG_FILE_EXPLICIT="1"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
}
