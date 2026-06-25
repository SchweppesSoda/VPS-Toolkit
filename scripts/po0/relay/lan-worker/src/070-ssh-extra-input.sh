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
