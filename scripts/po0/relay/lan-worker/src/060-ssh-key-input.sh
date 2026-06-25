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
