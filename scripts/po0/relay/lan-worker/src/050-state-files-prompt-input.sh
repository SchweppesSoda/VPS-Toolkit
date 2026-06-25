ensure_config_file() {
    local dir
    dir="$(path_dirname "${CONFIG_FILE}")"
    if [[ ! -d "${dir}" ]]; then
        if command -v mkdir >/dev/null 2>&1; then
            mkdir -p "${dir}" || return 1
        else
            printf '配置目录不存在，且当前系统缺少 mkdir：%s\n' "${dir}" >&2
            return 1
        fi
    fi
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        {
            printf '# enabled|label|source_key(optional if resource_token)|report_key|po0_host|po0_port|po0_user|po0_script|source_token|ssh_extra_args|resource_token|report_mode|ddns_domain\n'
        } > "${CONFIG_FILE}" || return 1
        chmod 600 "${CONFIG_FILE}" 2>/dev/null || true
    fi
}

ensure_resource_stats_file() {
    local dir
    refresh_resource_stats_file
    dir="$(path_dirname "${RESOURCE_STATS_FILE}")"
    if [[ ! -d "${dir}" ]]; then
        if command -v mkdir >/dev/null 2>&1; then
            mkdir -p "${dir}" || return 1
        else
            printf '资源统计目录不存在，且当前系统缺少 mkdir：%s\n' "${dir}" >&2
            return 1
        fi
    fi
    if [[ ! -f "${RESOURCE_STATS_FILE}" ]]; then
        printf '# endpoint_id|success_count|fail_count|last_task|last_type|last_status|last_at|last_message\n' > "${RESOURCE_STATS_FILE}" || return 1
        chmod 600 "${RESOURCE_STATS_FILE}" 2>/dev/null || true
    fi
}

ensure_resource_events_file() {
    local dir
    refresh_resource_events_file
    dir="$(path_dirname "${RESOURCE_EVENTS_FILE}")"
    if [[ ! -d "${dir}" ]]; then
        if command -v mkdir >/dev/null 2>&1; then
            mkdir -p "${dir}" || return 1
        else
            printf '资源事件目录不存在，且当前系统缺少 mkdir：%s\n' "${dir}" >&2
            return 1
        fi
    fi
    if [[ ! -f "${RESOURCE_EVENTS_FILE}" ]]; then
        printf '# at|endpoint_id|task_id|task_type|status|message\n' > "${RESOURCE_EVENTS_FILE}" || return 1
        chmod 600 "${RESOURCE_EVENTS_FILE}" 2>/dev/null || true
    fi
}

ensure_stats_file() {
    local dir
    refresh_stats_file
    dir="$(path_dirname "${STATS_FILE}")"
    if [[ ! -d "${dir}" ]]; then
        if command -v mkdir >/dev/null 2>&1; then
            mkdir -p "${dir}" || return 1
        else
            printf '统计目录不存在，且当前系统缺少 mkdir：%s\n' "${dir}" >&2
            return 1
        fi
    fi
    if [[ ! -f "${STATS_FILE}" ]]; then
        {
            printf '# target_id|success_count|fail_count|last_status|last_at|last_ip_csv|last_error\n'
        } > "${STATS_FILE}" || return 1
        chmod 600 "${STATS_FILE}" 2>/dev/null || true
    fi
}

require_arg_value() {
    local option="$1"
    [[ $# -ge 2 && -n "${2:-}" ]] || {
        printf '缺少参数值：%s\n' "${option}" >&2
        exit 1
    }
}

prompt_default() {
    local prompt="$1"
    local default="$2"
    local value
    if [[ -n "${default}" ]]; then
        if ! value="$(read_prompt "${prompt} [${default}]: ")"; then
            value=""
        fi
        value="$(trim "${value}")"
        [[ -n "${value}" ]] || value="${default}"
    else
        if ! value="$(read_prompt "${prompt}: ")"; then
            value=""
        fi
        value="$(trim "${value}")"
    fi
    printf '%s\n' "${value}"
}

read_prompt() {
    local prompt="$1"
    local value
    if [[ -r /dev/tty && -w /dev/tty ]]; then
        if { printf '%s' "${prompt}" > /dev/tty && IFS= read -r value < /dev/tty; } 2>/dev/null; then
            printf '%s\n' "${value}"
            return 0
        fi
    fi
    printf '%s' "${prompt}" >&2
    IFS= read -r value || return 1
    printf '%s\n' "${value}"
}

read_menu_choice() {
    local prompt="$1"
    local choice
    choice="$(read_prompt "${prompt}")" || return 1
    printf '%s\n' "$(trim "${choice}")"
}

drain_tty_input_buffer() {
    local line
    [[ -r /dev/tty ]] || return 0
    while IFS= read -r -t 0.05 line < /dev/tty 2>/dev/null; do
        :
    done
}

read_menu_choice_or_return() {
    local __target="$1"
    local prompt="$2"
    local __choice_value
    if ! __choice_value="$(read_menu_choice "${prompt}")"; then
        printf '\n输入结束，退出当前菜单。\n'
        return 1
    fi
    printf -v "${__target}" '%s' "${__choice_value}"
}

pause_before_return() {
    read_prompt "按回车返回菜单..." >/dev/null || true
}

menu_clear_screen() {
    [[ "${MENU_CLEAR:-1}" == "0" ]] && return 0
    [[ -t 1 && -n "${TERM:-}" && "${TERM}" != "dumb" ]] || return 0
    command -v clear >/dev/null 2>&1 && clear || printf '\033[H\033[2J'
}

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local suffix value
    case "${default,,}" in
        y|yes|1|true)
            suffix="Y/n"
            default="y"
            ;;
        *)
            suffix="y/N"
            default="n"
            ;;
    esac
    while true; do
        if ! value="$(read_prompt "${prompt} [${suffix}]: ")"; then
            return 1
        fi
        value="$(trim "${value}")"
        [[ -n "${value}" ]] || value="${default}"
        case "${value,,}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) printf '请输入 y 或 n。\n' >&2 ;;
        esac
    done
}

random_secret() {
    local token=""
    if command -v openssl >/dev/null 2>&1; then
        token="$(openssl rand -hex 24 2>/dev/null || true)"
    fi
    if [[ -z "${token}" ]] && [[ -r /dev/urandom ]]; then
        token="$(od -An -N24 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
    fi
    [[ -n "${token}" ]] || token="$(date '+%s')-$RANDOM-$RANDOM-$RANDOM"
    printf '%s\n' "${token}"
}

mask_secret() {
    local value="$1"
    local len
    [[ -n "${value}" ]] || { printf '<empty>\n'; return; }
    len="${#value}"
    if (( len <= 10 )); then
        printf '***\n'
    else
        printf '%s...%s\n' "${value:0:6}" "${value: -4}"
    fi
}

safe_filename_token() {
    local value="$1"
    value="${value//[!A-Za-z0-9_.-]/_}"
    value="${value##_}"
    value="${value%%_}"
    [[ -n "${value}" ]] || value="po0"
    printf '%s\n' "${value}"
}
