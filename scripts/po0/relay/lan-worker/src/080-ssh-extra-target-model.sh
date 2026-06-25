ssh_extra_identity_path() {
    local extra="$1"
    local -a parts=()
    local i token next
    [[ -n "${extra}" ]] || return 1
    read -r -a parts <<< "${extra}"
    for ((i = 0; i < ${#parts[@]}; i++)); do
        token="${parts[$i]}"
        next="${parts[$((i + 1))]:-}"
        case "${token}" in
            -i)
                [[ -n "${next}" ]] && { printf '%s\n' "${next}"; return 0; }
                ;;
            -i?*)
                printf '%s\n' "${token#-i}"
                return 0
                ;;
            IdentityFile=*)
                printf '%s\n' "${token#IdentityFile=}"
                return 0
                ;;
            -o)
                case "${next}" in
                    IdentityFile=*)
                        printf '%s\n' "${next#IdentityFile=}"
                        return 0
                        ;;
                esac
                ;;
            -oIdentityFile=*)
                printf '%s\n' "${token#-oIdentityFile=}"
                return 0
                ;;
        esac
    done
    return 1
}

ssh_extra_without_identity() {
    local extra="$1"
    local -a parts=()
    local out="" token next private_key_words=0
    local i skip_next=0
    [[ -n "${extra}" ]] || { printf '\n'; return 0; }
    read -r -a parts <<< "${extra}"
    for ((i = 0; i < ${#parts[@]}; i++)); do
        if [[ "${skip_next}" == "1" ]]; then
            skip_next=0
            continue
        fi
        token="${parts[$i]}"
        next="${parts[$((i + 1))]:-}"
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
            -i)
                skip_next=1
                continue
                ;;
            -i?*|IdentityFile=*|-oIdentityFile=*)
                continue
                ;;
            -o)
                case "${next}" in
                    IdentityFile=*)
                        skip_next=1
                        continue
                        ;;
                esac
                ;;
        esac
        out="${out:+${out} }${token}"
    done
    printf '%s\n' "${out}"
}

ssh_extra_with_identity() {
    local extra="$1"
    local key_path="$2"
    local out
    out="$(ssh_extra_without_identity "${extra}")"
    key_path="$(trim "${key_path}")"
    if [[ -n "${key_path}" ]]; then
        out="-i ${key_path}${out:+ ${out}}"
    fi
    printf '%s\n' "${out}"
}

ssh_extra_warn_ignored() {
    local context="$1"
    local reason="$2"
    printf '[WARN] %s: ignored SSH extra arg (%s).\n' "${context:-SSH extra args}" "${reason}" >&2
}

sanitize_ssh_extra_args() {
    local extra="$1"
    local context="${2:-SSH extra args}"
    local -a parts=()
    local token next
    local i
    local has_batchmode=0 has_connect_timeout=0 has_strict_host=0 connect_timeout
    local has_connection_attempts=0 has_number_prompts=0 has_preferred_auth=0 has_password_auth=0 has_kbd_auth=0 has_gssapi=0
    local private_key_words=0 private_key_warned=0
    SSH_EXTRA_ARGV=()
    connect_timeout="$(timeout_seconds "${SSH_CONNECT_TIMEOUT_SECONDS}" 15)"
    if [[ -n "${extra}" ]]; then
        read -r -a parts <<< "${extra}"
    fi
    for ((i = 0; i < ${#parts[@]}; i++)); do
        token="${parts[$i]}"
        next="${parts[$((i + 1))]:-}"
        [[ -n "${token}" ]] || continue
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
                if [[ "${private_key_warned}" == "0" ]]; then
                    ssh_extra_warn_ignored "${context}" "private key text is not an SSH option; save it to a file and use -i /path/key"
                    private_key_warned=1
                fi
                private_key_words=1
                [[ "${token}" == *KEY----- || "${token}" == -----END* ]] && private_key_words=0
                continue
                ;;
            -|--*)
                ssh_extra_warn_ignored "${context}" "invalid option/private-key marker"
                continue
                ;;
            -p)
                ssh_extra_warn_ignored "${context}" "port belongs in the PO0 SSH port field"
                if [[ -n "${next}" && "${next}" != -* ]]; then
                    ((i++))
                fi
                continue
                ;;
            -p?*)
                ssh_extra_warn_ignored "${context}" "port belongs in the PO0 SSH port field"
                continue
                ;;
            BatchMode=*)
                has_batchmode=1
                SSH_EXTRA_ARGV+=(-o "${token}")
                continue
                ;;
            ConnectTimeout=*)
                has_connect_timeout=1
                SSH_EXTRA_ARGV+=(-o "${token}")
                continue
                ;;
            StrictHostKeyChecking=*)
                has_strict_host=1
                SSH_EXTRA_ARGV+=(-o "${token}")
                continue
                ;;
            ConnectionAttempts=*)
                has_connection_attempts=1
                SSH_EXTRA_ARGV+=(-o "${token}")
                continue
                ;;
            NumberOfPasswordPrompts=*)
                has_number_prompts=1
                SSH_EXTRA_ARGV+=(-o "${token}")
                continue
                ;;
            PreferredAuthentications=*)
                has_preferred_auth=1
                SSH_EXTRA_ARGV+=(-o "${token}")
                continue
                ;;
            PasswordAuthentication=*)
                has_password_auth=1
                SSH_EXTRA_ARGV+=(-o "${token}")
                continue
                ;;
            KbdInteractiveAuthentication=*)
                has_kbd_auth=1
                SSH_EXTRA_ARGV+=(-o "${token}")
                continue
                ;;
            GSSAPIAuthentication=*)
                has_gssapi=1
                SSH_EXTRA_ARGV+=(-o "${token}")
                continue
                ;;
            IdentityFile=*|UserKnownHostsFile=*|HostKeyAlias=*|ProxyJump=*|ProxyCommand=*)
                SSH_EXTRA_ARGV+=(-o "${token}")
                continue
                ;;
            -oBatchMode=*)
                has_batchmode=1
                SSH_EXTRA_ARGV+=("${token}")
                continue
                ;;
            -oConnectTimeout=*)
                has_connect_timeout=1
                SSH_EXTRA_ARGV+=("${token}")
                continue
                ;;
            -oStrictHostKeyChecking=*)
                has_strict_host=1
                SSH_EXTRA_ARGV+=("${token}")
                continue
                ;;
            -oConnectionAttempts=*)
                has_connection_attempts=1
                SSH_EXTRA_ARGV+=("${token}")
                continue
                ;;
            -oNumberOfPasswordPrompts=*)
                has_number_prompts=1
                SSH_EXTRA_ARGV+=("${token}")
                continue
                ;;
            -oPreferredAuthentications=*)
                has_preferred_auth=1
                SSH_EXTRA_ARGV+=("${token}")
                continue
                ;;
            -oPasswordAuthentication=*)
                has_password_auth=1
                SSH_EXTRA_ARGV+=("${token}")
                continue
                ;;
            -oKbdInteractiveAuthentication=*)
                has_kbd_auth=1
                SSH_EXTRA_ARGV+=("${token}")
                continue
                ;;
            -oGSSAPIAuthentication=*)
                has_gssapi=1
                SSH_EXTRA_ARGV+=("${token}")
                continue
                ;;
        esac
        case "${token}" in
            -B|-b|-c|-D|-E|-e|-F|-I|-i|-J|-L|-l|-m|-O|-o|-P|-Q|-R|-S|-W|-w)
                if [[ -z "${next}" || "${next}" == -* ]]; then
                    ssh_extra_warn_ignored "${context}" "missing value for ${token}"
                    continue
                fi
                if [[ "${token}" == "-o" ]]; then
                    case "${next}" in
                        BatchMode=*) has_batchmode=1 ;;
                        ConnectTimeout=*) has_connect_timeout=1 ;;
                        StrictHostKeyChecking=*) has_strict_host=1 ;;
                        ConnectionAttempts=*) has_connection_attempts=1 ;;
                        NumberOfPasswordPrompts=*) has_number_prompts=1 ;;
                        PreferredAuthentications=*) has_preferred_auth=1 ;;
                        PasswordAuthentication=*) has_password_auth=1 ;;
                        KbdInteractiveAuthentication=*) has_kbd_auth=1 ;;
                        GSSAPIAuthentication=*) has_gssapi=1 ;;
                    esac
                fi
                SSH_EXTRA_ARGV+=("${token}" "${next}")
                ((i++))
                ;;
            -*)
                SSH_EXTRA_ARGV+=("${token}")
                ;;
            *)
                ssh_extra_warn_ignored "${context}" "bare value without an SSH option"
                ;;
        esac
    done
    [[ "${has_batchmode}" == "1" ]] || SSH_EXTRA_ARGV+=(-o BatchMode=yes)
    [[ "${has_connect_timeout}" == "1" ]] || SSH_EXTRA_ARGV+=(-o "ConnectTimeout=${connect_timeout}")
    [[ "${has_strict_host}" == "1" ]] || SSH_EXTRA_ARGV+=(-o StrictHostKeyChecking=accept-new)
    [[ "${has_connection_attempts}" == "1" ]] || SSH_EXTRA_ARGV+=(-o ConnectionAttempts=1)
    [[ "${has_number_prompts}" == "1" ]] || SSH_EXTRA_ARGV+=(-o NumberOfPasswordPrompts=0)
    [[ "${has_preferred_auth}" == "1" ]] || SSH_EXTRA_ARGV+=(-o PreferredAuthentications=publickey)
    [[ "${has_password_auth}" == "1" ]] || SSH_EXTRA_ARGV+=(-o PasswordAuthentication=no)
    [[ "${has_kbd_auth}" == "1" ]] || SSH_EXTRA_ARGV+=(-o KbdInteractiveAuthentication=no)
    [[ "${has_gssapi}" == "1" ]] || SSH_EXTRA_ARGV+=(-o GSSAPIAuthentication=no)
}

build_batchmode_ssh_extra_args() {
    local key_path="$1"
    local extra="$2"
    local out="" raw_extra
    key_path="$(trim "${key_path}")"
    extra="$(trim "${extra}")"
    raw_extra="${extra}"
    extra="$(ssh_extra_without_private_key_text "${extra}")"
    if [[ "${raw_extra}" != "${extra}" ]]; then
        printf '[WARN] 已忽略额外 SSH 参数中的私钥正文片段；私钥必须保存为文件并通过 -i /path/key 引用。\n' >&2
    fi
    if [[ -n "${key_path}" ]]; then
        case "${key_path}" in
            *" "*)
                printf '当前 ssh extra args 解析不支持带空格的私钥路径，请改用不含空格的路径或手动填写 --ssh-extra-args。\n' >&2
                return 1
                ;;
        esac
        extra="$(ssh_extra_without_identity "${extra}")"
        out="-i ${key_path}"
    fi
    [[ -n "${extra}" ]] && out="${out:+${out} }${extra}"
    case " ${out} " in
        *" BatchMode=yes "*|*" BatchMode yes "*)
            ;;
        *)
            out="${out:+${out} }-o BatchMode=yes"
            ;;
    esac
    case " ${out} " in
        *" StrictHostKeyChecking="*|*" StrictHostKeyChecking "*)
            ;;
        *)
            out="${out:+${out} }-o StrictHostKeyChecking=accept-new"
            ;;
    esac
    printf '%s\n' "${out}"
}

print_host_key_failure_help() {
    local host="$1"
    local port="$2"
    local user="$3"
    local extra="$4"
    local key_path
    [[ "${extra}" == *"Host key verification failed"* ]] || return 0
    key_path="$(ssh_extra_identity_path "${SSH_EXTRA_ARGS}" 2>/dev/null || true)"
    printf '\n[提示] SSH 主机指纹校验失败。\n' >&2
    printf '如果这是第一次连接该 PO0，重新运行新版向导会自动使用 StrictHostKeyChecking=accept-new。\n' >&2
    printf '你也可以先手动确认并写入 known_hosts：\n' >&2
    if [[ -n "${key_path}" ]]; then
        printf '  ssh -i %s -p %s %s@%s true\n' "${key_path}" "${port:-22}" "${user:-root}" "${host}" >&2
    else
        printf '  ssh -p %s %s@%s true\n' "${port:-22}" "${user:-root}" "${host}" >&2
    fi
    printf '如果提示 REMOTE HOST IDENTIFICATION HAS CHANGED，先确认 PO0 主机确实是你的机器，再清理旧指纹：\n' >&2
    printf '  ssh-keygen -R "[%s]:%s"\n' "${host}" "${port:-22}" >&2
}

parse_target_line() {
    local line="$1"
    line="$(trim "${line}")"
    [[ -n "${line}" ]] || return 1
    case "${line}" in
        \#*)
            return 1
            ;;
    esac
    if [[ "${line}" == *"|"* ]]; then
        IFS='|' read -r TARGET_ENABLED TARGET_LABEL TARGET_DOMAIN TARGET_REPORT_KEY TARGET_PO0_HOST TARGET_PO0_PORT TARGET_PO0_USER TARGET_PO0_SCRIPT TARGET_TOKEN TARGET_SSH_EXTRA_ARGS TARGET_RESOURCE_TOKEN TARGET_REPORT_MODE TARGET_DDNS_RESOLVE_DOMAIN TARGET_CLIENT_IP_TOKEN TARGET_CLIENT_IP_SOURCE TARGET_CLIENT_IP_TTL TARGET_WEBAUTH_TOKEN TARGET_WEBAUTH_SOURCE TARGET_WEBAUTH_TTL TARGET_REPORT_SSH_EXTRA_ARGS <<< "${line}"
    else
        # Legacy whitespace configs had no resource_token column; keep all
        # remaining words in ssh_extra_args for backward compatibility.
        read -r TARGET_ENABLED TARGET_LABEL TARGET_DOMAIN TARGET_REPORT_KEY TARGET_PO0_HOST TARGET_PO0_PORT TARGET_PO0_USER TARGET_PO0_SCRIPT TARGET_TOKEN TARGET_SSH_EXTRA_ARGS <<< "${line}"
        TARGET_RESOURCE_TOKEN=""
        TARGET_REPORT_MODE=""
        TARGET_DDNS_RESOLVE_DOMAIN=""
        TARGET_CLIENT_IP_TOKEN=""
        TARGET_CLIENT_IP_SOURCE=""
        TARGET_CLIENT_IP_TTL=""
        TARGET_WEBAUTH_TOKEN=""
        TARGET_WEBAUTH_SOURCE=""
        TARGET_WEBAUTH_TTL=""
        TARGET_REPORT_SSH_EXTRA_ARGS=""
    fi
    TARGET_ENABLED="$(sanitize_field "${TARGET_ENABLED}")"
    TARGET_LABEL="$(sanitize_field "${TARGET_LABEL}")"
    TARGET_DOMAIN="$(sanitize_field "${TARGET_DOMAIN}")"
    TARGET_REPORT_KEY="$(sanitize_field "${TARGET_REPORT_KEY}")"
    TARGET_PO0_HOST="$(sanitize_field "${TARGET_PO0_HOST}")"
    TARGET_PO0_PORT="$(sanitize_field "${TARGET_PO0_PORT}")"
    TARGET_PO0_USER="$(sanitize_field "${TARGET_PO0_USER}")"
    TARGET_PO0_SCRIPT="$(sanitize_field "${TARGET_PO0_SCRIPT}")"
    TARGET_TOKEN="$(sanitize_field "${TARGET_TOKEN}")"
    TARGET_SSH_EXTRA_ARGS="$(sanitize_field "${TARGET_SSH_EXTRA_ARGS}")"
    TARGET_RESOURCE_TOKEN="$(sanitize_field "${TARGET_RESOURCE_TOKEN:-}")"
    TARGET_REPORT_MODE="$(normalize_report_mode "${TARGET_REPORT_MODE:-}")"
    TARGET_DDNS_RESOLVE_DOMAIN="$(sanitize_field "${TARGET_DDNS_RESOLVE_DOMAIN:-}")"
    TARGET_CLIENT_IP_TOKEN="$(sanitize_field "${TARGET_CLIENT_IP_TOKEN:-}")"
    TARGET_CLIENT_IP_SOURCE="$(sanitize_field "${TARGET_CLIENT_IP_SOURCE:-}")"
    TARGET_CLIENT_IP_TTL="$(sanitize_field "${TARGET_CLIENT_IP_TTL:-}")"
    TARGET_WEBAUTH_TOKEN="$(sanitize_field "${TARGET_WEBAUTH_TOKEN:-}")"
    TARGET_WEBAUTH_SOURCE="$(sanitize_field "${TARGET_WEBAUTH_SOURCE:-}")"
    TARGET_WEBAUTH_TTL="$(sanitize_field "${TARGET_WEBAUTH_TTL:-}")"
    TARGET_REPORT_SSH_EXTRA_ARGS="$(sanitize_field "${TARGET_REPORT_SSH_EXTRA_ARGS:-}")"
    if [[ "${TARGET_REPORT_MODE}" == "auto" ]]; then
        if [[ -n "${TARGET_DOMAIN}" ]]; then
            TARGET_REPORT_MODE="ddns"
            [[ -n "${TARGET_DDNS_RESOLVE_DOMAIN}" ]] || TARGET_DDNS_RESOLVE_DOMAIN="${TARGET_DOMAIN}"
        else
            TARGET_REPORT_MODE="none"
        fi
    fi
    if [[ "${TARGET_REPORT_MODE}" == "ddns" && -z "${TARGET_DDNS_RESOLVE_DOMAIN}" ]]; then
        TARGET_DDNS_RESOLVE_DOMAIN="${TARGET_DOMAIN}"
    fi
    [[ -n "${TARGET_PO0_HOST}" ]] || return 1
    [[ -n "${TARGET_DOMAIN}" || -n "${TARGET_RESOURCE_TOKEN}" || -n "${TARGET_CLIENT_IP_TOKEN}" || -n "${TARGET_WEBAUTH_TOKEN}" ]] || return 1
}

target_line_count() {
    local line count=0
    [[ -f "${CONFIG_FILE}" ]] || {
        printf '0\n'
        return 0
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        count=$((count + 1))
    done < "${CONFIG_FILE}"
    printf '%s\n' "${count}"
}

list_targets() {
    local line idx=1 status key_label target_id domain_label mode_label
    ensure_config_file || return 1
    prune_stats_to_current_targets || true
    printf '配置文件：%s\n' "${CONFIG_FILE}"
    refresh_stats_file
    printf '统计文件：%s\n' "${STATS_FILE}"
    if [[ "$(target_line_count)" == "0" ]]; then
        printf '  (尚未添加上报目标)\n'
        return 0
    fi
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        [[ "${TARGET_ENABLED}" == "1" ]] && status="启用" || status="停用"
        domain_label="${TARGET_DOMAIN:-资源-only}"
        key_label="${TARGET_REPORT_KEY:-${TARGET_DOMAIN:-无}}"
        mode_label="${TARGET_REPORT_MODE:-none}"
        target_id="$(target_id_for "${TARGET_DOMAIN}" "${key_label}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT:-22}" "${TARGET_PO0_USER:-root}")"
        printf '  %2d) %-4s %-14s 类型=%s PO0=%s@%s:%s\n' \
            "${idx}" "${status}" "${TARGET_LABEL:-未命名}" "$(target_kind_summary)" "${TARGET_PO0_USER:-root}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT:-22}"
        if [[ "${TARGET_REPORT_MODE}" == "ddns" ]]; then
            printf '      来源 key：%s；PO0 匹配 key：%s\n' "${domain_label}" "${key_label}"
            printf '      DDNS 域名：%s\n' "${TARGET_DDNS_RESOLVE_DOMAIN:-${TARGET_DOMAIN}}"
            print_target_stats "${target_id}"
        fi
        [[ -n "${TARGET_CLIENT_IP_TOKEN}" ]] && printf '      设备自上报：source=%s ttl=%s\n' "${TARGET_CLIENT_IP_SOURCE:-${SELF_REPORT_SOURCE}}" "${TARGET_CLIENT_IP_TTL:-${SELF_REPORT_TTL_SECONDS}}"
        [[ -n "${TARGET_WEBAUTH_TOKEN}" ]] && printf '      WebAuth 放行：source=%s ttl=%s\n' "${TARGET_WEBAUTH_SOURCE:-${WEBAUTH_SOURCE}}" "${TARGET_WEBAUTH_TTL:-${WEBAUTH_TTL_SECONDS}}"
        if [[ -n "${TARGET_RESOURCE_TOKEN}" ]]; then
            printf '      资源任务：已配置 Token\n'
        else
            printf '      资源任务：未配置\n'
        fi
        ((idx++))
    done < "${CONFIG_FILE}"
}

target_id_is_current() {
    local needle="$1"
    local line key_label current_id
    [[ -f "${CONFIG_FILE}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_target_line "${line}" || continue
        key_label="${TARGET_REPORT_KEY:-${TARGET_DOMAIN}}"
        current_id="$(target_id_for "${TARGET_DOMAIN}" "${key_label}" "${TARGET_PO0_HOST}" "${TARGET_PO0_PORT:-22}" "${TARGET_PO0_USER:-root}")"
        [[ "${current_id}" == "${needle}" ]] && return 0
    done < "${CONFIG_FILE}"
    return 1
}

prune_stats_to_current_targets_unlocked() {
    local line id rest tmp
    ensure_config_file || return 1
    ensure_stats_file || return 1
    tmp="${STATS_FILE}.tmp.$$"
    printf '# target_id|success_count|fail_count|last_status|last_at|last_ip_csv|last_error\n' > "${tmp}" || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="$(trim "${line}")"
        [[ -n "${line}" && ! "${line}" == \#* ]] || continue
        IFS='|' read -r id rest <<< "${line}"
        target_id_is_current "${id}" || continue
        printf '%s\n' "${line}" >> "${tmp}"
    done < "${STATS_FILE}"
    replace_file_from_tmp "${tmp}" "${STATS_FILE}"
}

prune_stats_to_current_targets() {
    with_lan_state_lock prune_stats_to_current_targets_unlocked "$@"
}

clear_stats_interactive() {
    local answer tmp
    ensure_stats_file || return 1
    if ! answer="$(read_prompt "确认清空本机上报统计 [y/N]: ")"; then
        printf '\n输入结束，取消清空。\n'
        return 0
    fi
    answer="$(trim "${answer}")"
    case "${answer,,}" in
        y|yes)
            tmp="${STATS_FILE}.tmp.$$"
            {
                printf '# target_id|success_count|fail_count|last_status|last_at|last_ip_csv|last_error\n'
            } > "${tmp}" || return 1
            replace_file_from_tmp "${tmp}" "${STATS_FILE}" || return 1
            chmod 600 "${STATS_FILE}" 2>/dev/null || true
            printf '已清空本机上报统计。\n'
            ;;
        *)
            printf '已取消。\n'
            ;;
    esac
}

append_target_unlocked() {
    local enabled="$1"
    local label="$2"
    local domain="$3"
    local report_key="$4"
    local po0_host="$5"
    local po0_port="$6"
    local po0_user="$7"
    local po0_script="$8"
    local token="$9"
    local ssh_extra_args="${10:-}"
    local resource_token="${11:-}"
    local report_mode="${12:-auto}"
    local ddns_resolve_domain="${13:-}"
    local client_ip_token="${14:-}"
    local client_ip_source="${15:-}"
    local client_ip_ttl="${16:-}"
    local webauth_token="${17:-}"
    local webauth_source="${18:-}"
    local webauth_ttl="${19:-}"
    local report_ssh_extra_args="${20:-}"
    ensure_config_file || return 1
    ssh_extra_args="$(ssh_extra_without_private_key_text "${ssh_extra_args}")"
    report_ssh_extra_args="$(ssh_extra_without_private_key_text "${report_ssh_extra_args}")"
    report_mode="$(normalize_report_mode "${report_mode}")"
    if [[ "${report_mode}" == "auto" ]]; then
        [[ -n "${ddns_resolve_domain:-${domain}}" ]] && report_mode="ddns" || report_mode="none"
    fi
    [[ -n "${ddns_resolve_domain}" ]] || ddns_resolve_domain="${domain}"
    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
        "$(sanitize_field "${enabled}")" \
        "$(sanitize_field "${label}")" \
        "$(sanitize_field "${domain}")" \
        "$(sanitize_field "${report_key}")" \
        "$(sanitize_field "${po0_host}")" \
        "$(sanitize_field "${po0_port}")" \
        "$(sanitize_field "${po0_user}")" \
        "$(sanitize_field "${po0_script}")" \
        "$(sanitize_field "${token}")" \
        "$(sanitize_field "${ssh_extra_args}")" \
        "$(sanitize_field "${resource_token}")" \
        "$(sanitize_field "${report_mode}")" \
        "$(sanitize_field "${ddns_resolve_domain}")" \
        "$(sanitize_field "${client_ip_token}")" \
        "$(sanitize_field "${client_ip_source}")" \
        "$(sanitize_field "${client_ip_ttl}")" \
        "$(sanitize_field "${webauth_token}")" \
        "$(sanitize_field "${webauth_source}")" \
        "$(sanitize_field "${webauth_ttl}")" \
        "$(sanitize_field "${report_ssh_extra_args}")" >> "${CONFIG_FILE}"
}
