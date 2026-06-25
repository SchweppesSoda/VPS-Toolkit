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

default_config_file() {
    if [[ -n "${CONFIG_FILE}" ]]; then
        printf '%s\n' "${CONFIG_FILE}"
    elif [[ "${EUID:-$(id -u 2>/dev/null || printf 1)}" -eq 0 ]]; then
        printf '%s\n' "/etc/po0-self-report/settings.env"
    elif [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
        printf '%s\n' "${XDG_CONFIG_HOME}/po0-self-report/settings.env"
    elif [[ -n "${HOME:-}" ]]; then
        printf '%s\n' "${HOME}/.config/po0-self-report/settings.env"
    else
        printf '%s\n' "./po0-self-report.env"
    fi
}

prime_config_path_from_args() {
    local arg next
    while [[ $# -gt 0 ]]; do
        arg="$1"
        case "${arg}" in
            --config)
                next="${2:-}"
                [[ -n "${next}" ]] && CONFIG_FILE="${next}"
                shift 2 2>/dev/null || shift
                ;;
            --config=*)
                CONFIG_FILE="${arg#--config=}"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
}
