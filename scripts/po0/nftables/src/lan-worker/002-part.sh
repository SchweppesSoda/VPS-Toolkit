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

is_private_key_begin_line() {
    case "$1" in
        -----BEGIN\ *PRIVATE\ KEY-----) return 0 ;;
        *) return 1 ;;
    esac
}

is_private_key_end_line() {
    case "$1" in
        -----END\ *PRIVATE\ KEY-----) return 0 ;;
        *) return 1 ;;
    esac
}

read_private_key_from_first_line() {
    local line="$1"
    local key="" seen_begin=0 seen_end=0
    while true; do
        line="${line%$'\r'}"
        if [[ -z "${line}" && "${seen_begin}" == "0" ]]; then
            printf '未读取到私钥内容。\n' >&2
            return 1
        fi
        key+="${line}"$'\n'
        if is_private_key_begin_line "${line}"; then
            seen_begin=1
        fi
        if is_private_key_end_line "${line}"; then
            seen_end=1
            break
        fi
        if [[ -r /dev/tty && -w /dev/tty ]]; then
            IFS= read -r line < /dev/tty || return 1
        else
            IFS= read -r line || return 1
        fi
    done
    [[ "${seen_begin}" == "1" && "${seen_end}" == "1" ]] || {
        printf '私钥内容不完整。\n' >&2
        return 1
    }
    printf '%s' "${key}"
}

validate_ssh_private_key_file() {
    local path="$1"
    command -v ssh-keygen >/dev/null 2>&1 || return 0
    ssh-keygen -y -f "${path}" >/dev/null 2>&1
}

read_private_key_paste() {
    local line key
    if [[ -w /dev/tty ]]; then
        printf '请粘贴 SSH 私钥，粘贴到 END ... PRIVATE KEY 行后会自动结束；空输入取消。\n' > /dev/tty
    else
        printf '请粘贴 SSH 私钥，粘贴到 END ... PRIVATE KEY 行后会自动结束；空输入取消。\n' >&2
    fi
    if [[ -r /dev/tty && -w /dev/tty ]]; then
        IFS= read -r line < /dev/tty || return 1
    else
        IFS= read -r line || return 1
    fi
    if key="$(read_private_key_from_first_line "${line}")"; then
        drain_tty_input_buffer
        printf '%s' "${key}"
        return 0
    fi
    drain_tty_input_buffer
    return 1
}

save_ssh_key_content() {
    local host="$1"
    local port="$2"
    local user="$3"
    local key="$4"
    local dir key_path host_token port_token user_token old_umask backup_path=""
    ensure_config_file || return 1
    dir="$(path_dirname "${CONFIG_FILE}")"
    host_token="$(safe_filename_token "${host}")"
    port_token="$(safe_filename_token "${port:-22}")"
    user_token="$(safe_filename_token "${user:-root}")"
    key_path="${dir}/ssh-key-${user_token}-${host_token}-${port_token}"
    if [[ -e "${key_path}" ]]; then
        prompt_yes_no "私钥文件已存在，是否覆盖：${key_path}" "n" || return 1
        backup_path="${key_path}.bak.$$"
        cp -p "${key_path}" "${backup_path}" 2>/dev/null || backup_path=""
    fi
    old_umask="$(umask)"
    umask 077
    printf '%s\n' "${key}" > "${key_path}" || {
        umask "${old_umask}"
        [[ -n "${backup_path}" ]] && mv -f "${backup_path}" "${key_path}" 2>/dev/null || true
        return 1
    }
    umask "${old_umask}"
    chmod 600 "${key_path}" 2>/dev/null || true
    if ! validate_ssh_private_key_file "${key_path}"; then
        if [[ -n "${backup_path}" && -f "${backup_path}" ]]; then
            mv -f "${backup_path}" "${key_path}" 2>/dev/null || true
        else
            rm -f -- "${key_path}" 2>/dev/null || true
        fi
        printf 'SSH 私钥保存后校验失败，未使用这次粘贴内容。请确认粘贴的是完整 OpenSSH 私钥，或改用 1Password 导出到文件后填写路径。\n' >&2
        return 1
    fi
    [[ -n "${backup_path}" ]] && rm -f -- "${backup_path}" 2>/dev/null || true
    printf '%s\n' "${key_path}"
}

save_pasted_ssh_key() {
    local host="$1"
    local port="$2"
    local user="$3"
    local key
    key="$(read_private_key_paste)" || return 1
    save_ssh_key_content "${host}" "${port}" "${user}" "${key}"
}

prompt_ssh_key_path_or_paste() {
    local prompt="$1"
    local default="$2"
    local host="$3"
    local port="$4"
    local user="$5"
    local value key
    value="$(prompt_default "${prompt}" "${default}")"
    if is_private_key_begin_line "${value}"; then
        printf '[WARN] 检测到你把私钥内容粘贴到了“路径”输入框，正在继续读取剩余私钥内容并保存。\n' >&2
        key="$(read_private_key_from_first_line "${value}")" || { drain_tty_input_buffer; return 1; }
        drain_tty_input_buffer
        save_ssh_key_content "${host}" "${port}" "${user}" "${key}"
        return 0
    fi
    printf '%s\n' "${value}"
}

ssh_extra_without_private_key_text() {
    local extra="$1"
    local -a parts=()
    local out="" token private_key_words=0
    local i
    [[ -n "${extra}" ]] || { printf '\n'; return 0; }
    read -r -a parts <<< "${extra}"
    for ((i = 0; i < ${#parts[@]}; i++)); do
        token="${parts[$i]}"
        if [[ "${private_key_words}" == "1" ]]; then
            case "${token}" in
                OPENSSH|RSA|DSA|EC|ECDSA|ED25519|PRIVATE|KEY|KEY-----|*KEY-----|-----END*)
                    [[ "${token}" == *KEY----- || "${token}" == -----END* ]] && private_key_words=0
                    continue
                    ;;
            esac
        fi
        case "${token}" in
            -----BEGIN*|-----END*)
                private_key_words=1
                [[ "${token}" == *KEY----- || "${token}" == -----END* ]] && private_key_words=0
                continue
                ;;
        esac
        out="${out:+${out} }${token}"
    done
    printf '%s\n' "${out}"
}

prompt_ssh_extra_args() {
    local prompt="$1"
    local default="$2"
    local host="$3"
    local port="$4"
    local user="$5"
    local value raw key key_path cleaned used_default=0
    if [[ -n "${default}" ]]; then
        raw="$(read_prompt "${prompt} [${default}]: ")" || raw=""
        raw="$(trim "${raw}")"
        if [[ -n "${raw}" ]]; then
            value="${raw}"
        else
            value="${default}"
            used_default=1
        fi
    else
        raw="$(read_prompt "${prompt}: ")" || raw=""
        value="$(trim "${raw}")"
    fi
    if [[ "${used_default}" == "0" ]] && is_private_key_begin_line "${value}"; then
        printf '[WARN] 检测到你把私钥内容粘贴到了“额外 SSH 参数”输入框，正在保存为私钥文件。\n' >&2
        key="$(read_private_key_from_first_line "${value}")" || { drain_tty_input_buffer; return 1; }
        drain_tty_input_buffer
        key_path="$(save_ssh_key_content "${host}" "${port}" "${user}" "${key}")" || return 1
        cleaned="$(ssh_extra_without_identity "${default}")"
        ssh_extra_with_identity "${cleaned}" "${key_path}"
        return 0
    fi
    case "${value}" in
        *"-----BEGIN "*"PRIVATE KEY-----"*|*"-----END "*"PRIVATE KEY-----"*)
            if [[ "${used_default}" == "1" ]]; then
                printf '[WARN] 清理旧配置中残留的私钥正文片段；请使用 -i /path/key 引用私钥文件。\n' >&2
                ssh_extra_without_private_key_text "${value}"
                return 0
            fi
            printf '额外 SSH 参数不能填写私钥正文；请选择“粘贴私钥并保存到本机”，或先保存私钥文件后填写 -i /path/key。\n' >&2
            return 1
            ;;
    esac
    printf '%s\n' "${value}"
}
