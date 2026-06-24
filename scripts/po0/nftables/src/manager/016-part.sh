do_report_ddns_allowlist_source() {
    local key="${1:-}"
    local ips="${2:-}"
    local token="${3:-}"
    [[ -n "${key}" && -n "${ips}" ]] || {
        err "用法：--ddns-report <source-key> <公网IPv4[,公网IPv4...]> [token]"
        return 1
    }
    ensure_layout || return 1
    load_settings 1
    report_ddns_allowlist_source "${key}" "${ips}" "${token}" || return 1
    enable_allowlist_for_custom_add
    apply_src_allowlist_changes || return 1
    printf 'DDNS 上报已接收：%s (%s) -> %s\n' \
        "${DDNS_REPORT_NAME:-${key}}" "${DDNS_REPORT_DOMAIN:-${key}}" "${DDNS_REPORT_IPS:-${ips}}"
}

do_report_client_ip_source() {
    local source_id="${1:-}"
    local ip="${2:-}"
    local token="${3:-}"
    local identity="${4:-}"
    local ttl="${5:-43200}"
    [[ -n "${source_id}" && -n "${ip}" ]] || {
        err "用法：--client-ip-report <source-id> <ipv4> <token> [identity] [ttl]"
        return 1
    }
    ensure_layout || return 1
    load_settings 1
    report_client_ip_source "${source_id}" "${ip}" "${token}" "${identity}" "${ttl}" || return 1
    enable_allowlist_for_custom_add
    apply_src_allowlist_changes || return 1
    if [[ "${DYNAMIC_REPORT_PENDING_COUNT:-0}" -gt 0 ]]; then
        printf '客户端 IP 已记录为待审核（attack mode）：%s -> %s\n' "${CLIENT_IP_REPORT_SOURCE:-${source_id}}" "${CLIENT_IP_REPORT_IP:-${ip}}"
    else
        printf '客户端 IP 上报已接收：%s -> %s，TTL %ss\n' "${CLIENT_IP_REPORT_SOURCE:-${source_id}}" "${CLIENT_IP_REPORT_IP:-${ip}}" "${CLIENT_IP_REPORT_TTL:-${ttl}}"
    fi
}

do_check_client_ip_report_source() {
    local source_id="${1:-}"
    local token="${2:-}"
    source_id="$(sanitize_allowlist_source_text "$(trim "${source_id}")")"
    [[ -n "${source_id}" ]] || {
        printf 'ERROR|缺少客户端来源 ID\n'
        return 1
    }
    validate_client_ip_report_token "${token}" || {
        printf 'ERROR|客户端 IP 上报 token 无效\n'
        return 1
    }
    printf 'OK|客户端 IP 来源可上报：%s\n' "${source_id}"
}

do_report_ssh_ip_source() {
    local source_id="${1:-}"
    local ip="${2:-}"
    local token="${3:-}"
    local identity="${4:-}"
    local ttl="${5:-43200}"
    local cidr_prefix="${6:-32}"
    [[ -n "${source_id}" && -n "${ip}" ]] || {
        err "用法：--ssh-ip-report <source-id> <ipv4> <token> [identity] [ttl] [cidr-prefix]"
        return 1
    }
    ensure_layout || return 1
    load_settings 1
    report_ssh_ip_source "${source_id}" "${ip}" "${token}" "${identity}" "${ttl}" "${cidr_prefix}" || return 1
    enable_allowlist_for_custom_add
    apply_src_allowlist_changes || return 1
    if [[ "${DYNAMIC_REPORT_PENDING_COUNT:-0}" -gt 0 ]]; then
        printf 'SSH report IP 已记录为待审核（attack mode）：%s -> %s\n' "${SSH_REPORT_SOURCE:-${source_id}}" "${SSH_REPORT_IP:-${ip}}"
    else
        printf 'SSH report 已接收：%s -> %s，CIDR %s，TTL %ss\n' "${SSH_REPORT_SOURCE:-${source_id}}" "${SSH_REPORT_IP:-${ip}}" "${SSH_REPORT_CIDR:-${ip}/32}" "${SSH_REPORT_TTL:-${ttl}}"
    fi
}

do_check_ssh_ip_report_source() {
    local source_id="${1:-}"
    local token="${2:-}"
    source_id="$(sanitize_allowlist_source_text "$(trim "${source_id}")")"
    [[ -n "${source_id}" ]] || {
        printf 'ERROR|missing ssh report source id\n'
        return 1
    }
    validate_ssh_report_token "${token}" || {
        printf 'ERROR|invalid ssh report token\n'
        return 1
    }
    printf 'OK|ssh report source can report: %s\n' "${source_id}"
}

do_report_webauth_source() {
    local source_id="${1:-}"
    local ip="${2:-}"
    local identity="${3:-}"
    local expires_at="${4:-}"
    local token="${5:-}"
    local note="${6:-}"
    [[ -n "${source_id}" && -n "${ip}" && -n "${identity}" && -n "${expires_at}" ]] || {
        err "用法：--webauth-report <source-id> <ipv4> <identity> <expires-at> <token> [note]"
        return 1
    }
    ensure_layout || return 1
    load_settings 1
    report_webauth_source "${source_id}" "${ip}" "${identity}" "${expires_at}" "${token}" "${note}" || return 1
    enable_allowlist_for_custom_add
    apply_src_allowlist_changes || return 1
    if [[ "${DYNAMIC_REPORT_PENDING_COUNT:-0}" -gt 0 ]]; then
        printf 'WebAuth IP 已记录为待审核（attack mode）：%s -> %s identity=%s\n' "${WEBAUTH_REPORT_SOURCE:-${source_id}}" "${WEBAUTH_REPORT_IP:-${ip}}" "${WEBAUTH_REPORT_IDENTITY:-${identity}}"
    else
        printf 'WebAuth 上报已接收：%s -> %s identity=%s expires=%s\n' "${WEBAUTH_REPORT_SOURCE:-${source_id}}" "${WEBAUTH_REPORT_IP:-${ip}}" "${WEBAUTH_REPORT_IDENTITY:-${identity}}" "${WEBAUTH_REPORT_EXPIRES_AT:-${expires_at}}"
    fi
}

do_check_webauth_report_source() {
    local source_id="${1:-}"
    local token="${2:-}"
    source_id="$(sanitize_allowlist_source_text "$(trim "${source_id}")")"
    [[ -n "${source_id}" ]] || {
        printf 'ERROR|缺少 WebAuth 来源 ID\n'
        return 1
    }
    validate_webauth_report_token "${token}" || {
        printf 'ERROR|WebAuth 上报 token 无效\n'
        return 1
    }
    printf 'OK|WebAuth 来源可上报：%s\n' "${source_id}"
}

do_show_client_ip_report_token() {
    local token
    ensure_layout || return 1
    token="$(client_ip_report_token_value)" || return 1
    print_title "Client IP / 自上报 Token"
    printf 'Token 文件 : %s\n' "${CLIENT_IP_REPORT_TOKEN_FILE}"
    printf 'Token      : %s\n' "${token}"
    echo ""
    echo "PO0 接收命令（SSH only；通常由 LAN Worker 自动执行）："
    printf '  bash %s --client-ip-report self-report 1.2.3.4 %s lan-worker 43200\n' "$(basename "$0")" "${token}"
    echo ""
    echo "LAN Worker self-report server（推荐 HTTPS/Caddy；PO0 不开放 HTTP）："
    printf '  po0-lan-client --install-self-report-https --self-report-https-domain <SELF_REPORT_DOMAIN> --po0-host <PO0_HOST> --po0-script %s --self-report-source self-report --client-ip-token %s --self-report-secret <SELF_REPORT_SECRET>\n' \
        "$(shell_quote "${MANAGER_INSTALL_PATH}")" "$(shell_quote "${token}")"
    echo ""
    echo "Linux / OpenWrt 自上报 client（访问设备 -> LAN Worker）："
    printf '  curl -fsSL %s | bash -s -- --worker-url https://<SELF_REPORT_DOMAIN>/report --source-id <CLIENT_ID> --secret <SELF_REPORT_SECRET> --interval-seconds 3600 --install-cron\n' \
        "${OUTBOUND_IP_REPORTER_DOWNLOAD_URL}"
    echo ""
    echo "Windows PowerShell 自上报 client（访问设备 -> LAN Worker）："
    printf "  \$script=\"\$env:TEMP\\po0-outbound-ip-report.ps1\"; irm -UseBasicParsing '%s' -OutFile \$script -TimeoutSec 120; powershell -ExecutionPolicy Bypass -File \$script -WorkerUrl 'https://<SELF_REPORT_DOMAIN>/report' -SourceId '<CLIENT_ID>' -Secret '<SELF_REPORT_SECRET>' -InstallTask -IntervalSeconds 3600\n" \
        "${OUTBOUND_IP_REPORTER_PS_DOWNLOAD_URL}"
}

normalize_report_key_scope() {
    case "$(trim "${1:-}")" in
        egern|ssh_report|ssh-report) printf 'egern\n' ;;
        worker|lan|lan-worker) printf 'worker\n' ;;
        all|both|"") printf 'all\n' ;;
        *) printf 'all\n' ;;
    esac
}

report_key_scope_allows() {
    case "$(normalize_report_key_scope "${1:-}")" in
        egern) printf '%s\n' '--ssh-ip-report --ssh-ip-report-check' ;;
        worker) printf '%s\n' '--ddns-report --ddns-report-check --client-ip-report --client-ip-report-check --webauth-report --webauth-report-check --resource-task-ping --resource-task-claim --resource-task-upload --resource-task-complete --resource-task-fail --resource-task-cron-status' ;;
        *) printf '%s\n' '--ssh-ip-report --ssh-ip-report-check --ddns-report --ddns-report-check --client-ip-report --client-ip-report-check --webauth-report --webauth-report-check --resource-task-ping --resource-task-claim --resource-task-upload --resource-task-complete --resource-task-fail --resource-task-cron-status' ;;
    esac
}

report_key_user_home() {
    local user="${1:-root}"
    if command -v getent >/dev/null 2>&1; then
        getent passwd "${user}" | awk -F: '{print $6; exit}'
        return
    fi
    awk -F: -v user="${user}" '$1 == user {print $6; exit}' /etc/passwd
}

report_key_auth_file() {
    local user="${1:-root}" home
    home="$(report_key_user_home "${user}")"
    [[ -n "${home}" ]] || return 1
    printf '%s/.ssh/authorized_keys\n' "${home}"
}

report_key_public_part() {
    local line="$1" token key_type=""
    for token in ${line}; do
        case "${token}" in
            ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521)
                key_type="${token}"
                continue
                ;;
        esac
        if [[ -n "${key_type}" ]]; then
            printf '%s %s\n' "${key_type}" "${token}"
            return 0
        fi
    done
    return 1
}

report_key_fingerprint() {
    local public_part="$1" tmp fp
    if ! command -v ssh-keygen >/dev/null 2>&1; then
        printf 'ssh-keygen unavailable\n'
        return 0
    fi
    make_temp_file "${CONF_DIR}/po0-report-key.pub" || return 1
    tmp="${TEMP_FILE_RESULT}"
    printf '%s\n' "${public_part}" > "${tmp}"
    fp="$(ssh-keygen -lf "${tmp}" 2>/dev/null || true)"
    printf '%s\n' "${fp:-unparseable}"
}

ensure_report_key_wrapper() {
    mkdir -p "$(dirname "${REPORT_KEY_WRAPPER_PATH}")" || return 1
    cat > "${REPORT_KEY_WRAPPER_PATH}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
scope="${1:-all}"
manager="${2:-/root/nftables-relay-manager.sh}"
orig="${SSH_ORIGINAL_COMMAND:-}"
deny_log="/etc/nftables.d/po0-report-key-denied.log"
first=""
second=""
third=""
rest=""
action=""
declare -a args=()

log_deny() {
    local reason="$*" now conn argc
    now="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date 2>/dev/null || printf 'unknown')"
    conn="${SSH_CONNECTION:-unknown}"
    argc="${#args[@]}"
    printf '%s scope=%s reason=%s action=%s first=%s second=%s third=%s argc=%s conn=%s\n' \
        "${now}" "${scope}" "${reason}" "${action:-unknown}" "${first:-unknown}" "${second:-unknown}" "${third:-unknown}" "${argc}" "${conn}" >> "${deny_log}" 2>/dev/null || true
}

deny() { log_deny "$*"; printf 'PO0 restricted report key denied: %s\n' "$*" >&2; exit 126; }

is_public_ipv4() {
    [[ "${1:-}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    local IFS=. o o1 o2 o3 o4
    read -r o1 o2 o3 o4 <<< "$1"
    for o in "$o1" "$o2" "$o3" "$o4"; do
        [[ "$o" =~ ^[0-9]+$ ]] || return 1
        (( o >= 0 && o <= 255 )) || return 1
    done
    (( o1 == 0 || o1 == 10 || o1 == 127 || o1 >= 224 )) && return 1
    (( o1 == 100 && o2 >= 64 && o2 <= 127 )) && return 1
    (( o1 == 169 && o2 == 254 )) && return 1
    (( o1 == 172 && o2 >= 16 && o2 <= 31 )) && return 1
    (( o1 == 192 && o2 == 168 )) && return 1
    (( o1 == 198 && o2 >= 18 && o2 <= 19 )) && return 1
    return 0
}

allow_action() {
    local action="$1"
    case "${scope}" in
        egern) [[ "${action}" == "--ssh-ip-report" || "${action}" == "--ssh-ip-report-check" ]] ;;
        worker)
            case "${action}" in
                --ddns-report|--ddns-report-check|--client-ip-report|--client-ip-report-check|--webauth-report|--webauth-report-check|--resource-task-ping|--resource-task-claim|--resource-task-upload|--resource-task-complete|--resource-task-fail|--resource-task-cron-status) return 0 ;;
                *) return 1 ;;
            esac
            ;;
        all)
            case "${action}" in
                --ssh-ip-report|--ssh-ip-report-check|--ddns-report|--ddns-report-check|--client-ip-report|--client-ip-report-check|--webauth-report|--webauth-report-check|--resource-task-ping|--resource-task-claim|--resource-task-upload|--resource-task-complete|--resource-task-fail|--resource-task-cron-status) return 0 ;;
                *) return 1 ;;
            esac
            ;;
        *) return 1 ;;
    esac
}

normalize_resource_task_fail_args() {
    [[ "${action}" == "--resource-task-fail" ]] || return 0
    [[ "${#args[@]}" -gt 4 ]] || return 0
    local token reason
    local -a reason_parts=()
    token="${args[$((${#args[@]} - 1))]}"
    reason_parts=("${args[@]:2:$((${#args[@]} - 3))}")
    reason="${reason_parts[*]}"
    args=("${args[0]}" "${args[1]}" "${reason}" "${token}")
}

[[ -n "${orig}" ]] || deny "empty command"
clean="${orig//\'/}"
clean="${clean//\"/}"
read -r first second third rest <<< "${clean}"
if [[ "${first}" == "bash" || "${first}" == "/bin/bash" || "${first}" == "/usr/bin/bash" ]]; then
    [[ "${second}" == "${manager}" ]] || deny "unexpected manager path"
    action="${third}"
    read -r -a args <<< "${rest:-}"
elif [[ "${first}" == "${manager}" ]]; then
    action="${second}"
    read -r -a args <<< "${third:-} ${rest:-}"
else
    deny "unexpected command"
fi
allow_action "${action}" || deny "action ${action} not allowed for scope ${scope}"
normalize_resource_task_fail_args
case "${action}" in
    --ssh-ip-report)
        [[ "${#args[@]}" -ge 3 ]] || deny "${action} needs source ip token"
        is_public_ipv4 "${args[1]}" || deny "invalid public IPv4"
        [[ "${#args[@]}" -lt 5 || "${args[4]}" =~ ^[0-9]+$ ]] || deny "invalid ttl"
        [[ "${#args[@]}" -lt 6 || "${args[5]}" == "24" || "${args[5]}" == "32" ]] || deny "invalid cidr prefix"
        ;;
    --client-ip-report)
        [[ "${#args[@]}" -ge 3 ]] || deny "${action} needs source ip token"
        is_public_ipv4 "${args[1]}" || deny "invalid public IPv4"
        [[ "${#args[@]}" -lt 5 || "${args[4]}" =~ ^[0-9]+$ ]] || deny "invalid ttl"
        ;;
    --ddns-report) [[ "${#args[@]}" -ge 2 ]] || deny "${action} needs source ips" ;;
    --webauth-report)
        [[ "${#args[@]}" -ge 5 ]] || deny "${action} needs source ip identity expires token"
        is_public_ipv4 "${args[1]}" || deny "invalid public IPv4"
        ;;
    --ssh-ip-report-check|--client-ip-report-check|--ddns-report-check|--webauth-report-check)
        [[ "${#args[@]}" -ge 1 ]] || deny "${action} needs source"
        ;;
    --resource-task-ping)
        [[ "${#args[@]}" -ge 1 ]] || deny "${action} needs token"
        ;;
    --resource-task-claim)
        [[ "${#args[@]}" -ge 2 ]] || deny "${action} needs worker token"
        [[ "${args[0]}" =~ ^[A-Za-z0-9._:-]{1,80}$ ]] || deny "invalid worker_id"
        ;;
    --resource-task-complete)
        [[ "${#args[@]}" -ge 5 ]] || deny "${action} needs task worker sha size token"
        [[ "${args[0]}" =~ ^[A-Za-z0-9._-]+$ ]] || deny "invalid task_id"
        [[ "${args[1]}" =~ ^[A-Za-z0-9._:-]{1,80}$ ]] || deny "invalid worker_id"
        [[ "${args[2]}" =~ ^[A-Fa-f0-9]{64}$ ]] || deny "invalid sha256"
        [[ "${args[3]}" =~ ^[0-9]+$ ]] || deny "invalid size"
        ;;
    --resource-task-upload)
        [[ "${#args[@]}" -ge 5 ]] || deny "${action} needs task worker sha size token"
        [[ "${args[0]}" =~ ^[A-Za-z0-9._-]+$ ]] || deny "invalid task_id"
        [[ "${args[1]}" =~ ^[A-Za-z0-9._:-]{1,80}$ ]] || deny "invalid worker_id"
        [[ "${args[2]}" =~ ^[A-Fa-f0-9]{64}$ ]] || deny "invalid sha256"
        [[ "${args[3]}" =~ ^[0-9]+$ ]] || deny "invalid size"
        ;;
    --resource-task-fail)
        [[ "${#args[@]}" -ge 4 ]] || deny "${action} needs task worker reason token"
        [[ "${args[0]}" =~ ^[A-Za-z0-9._-]+$ ]] || deny "invalid task_id"
        [[ "${args[1]}" =~ ^[A-Za-z0-9._:-]{1,80}$ ]] || deny "invalid worker_id"
        ;;
esac
exec bash "${manager}" "${action}" "${args[@]}"
EOF
    chmod 700 "${REPORT_KEY_WRAPPER_PATH}" || return 1
}

report_key_restricted_options() {
    local scope
    scope="$(normalize_report_key_scope "${1:-all}")"
    printf 'restrict,no-pty,no-agent-forwarding,no-X11-forwarding,no-port-forwarding,command="%s %s %s"' \
        "${REPORT_KEY_WRAPPER_PATH}" "${scope}" "${MANAGER_INSTALL_PATH}"
}

show_report_keys_for_user() {
    local user="${1:-root}" auth line idx=1 public_part fp scope category
    auth="$(report_key_auth_file "${user}")" || { err "无法确定 ${user} 的 authorized_keys 路径。"; return 1; }
    printf '用户: %s\n' "${user}"
    printf 'authorized_keys: %s\n' "${auth}"
    printf '拒绝日志: %s\n' "${REPORT_KEY_DENY_LOG}"
    [[ -f "${auth}" ]] || { printf '  (文件不存在)\n'; return 0; }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="$(trim "${line}")"
        [[ -n "${line}" && ! "${line}" =~ ^# ]] || continue
        public_part="$(report_key_public_part "${line}" || true)"
        [[ -n "${public_part}" ]] || continue
        fp="$(report_key_fingerprint "${public_part}")"
        if [[ "${line}" == *"po0-report:scope="* ]]; then
            scope="${line#*po0-report:scope=}"
            scope="${scope%%,*}"
            category="PO0 受限上报 key"
        elif [[ "${line}" == *"command="* || "${line}" == restrict,* ]]; then
            scope="-"; category="其它 forced-command/restricted key"
        else
            scope="-"; category="普通登录 key"
        fi
        printf '  %2d) %s\n' "${idx}" "${category}"
        printf '      fingerprint: %s\n' "${fp}"
        printf '      scope      : %s\n' "${scope}"
        [[ "${category}" == "PO0 受限上报 key" ]] && printf '      allowed    : %s\n      wrapper    : %s\n' "$(report_key_scope_allows "${scope}")" "${REPORT_KEY_WRAPPER_PATH}"
        ((idx++))
    done < "${auth}"
}

show_report_key_denials() {
    local limit="${1:-50}"
    [[ "${limit}" =~ ^[0-9]+$ && "${limit}" -gt 0 ]] || limit=50
    printf 'PO0 受限上报 key 拒绝日志：%s\n' "${REPORT_KEY_DENY_LOG}"
    if [[ ! -s "${REPORT_KEY_DENY_LOG}" ]]; then
        printf '  (暂无拒绝记录)\n'
        return 0
    fi
    tail -n "${limit}" "${REPORT_KEY_DENY_LOG}" 2>/dev/null || cat "${REPORT_KEY_DENY_LOG}"
}

install_report_public_key() {
    local user="$1" scope="$2" pubkey="$3" auth ssh_dir group public_part blob existing line options comment tmp converted=0
    scope="$(normalize_report_key_scope "${scope}")"
    auth="$(report_key_auth_file "${user}")" || return 1
    ssh_dir="$(dirname "${auth}")"
    public_part="$(report_key_public_part "${pubkey}")" || { err "请输入 OpenSSH public key，不要粘贴私钥。"; return 1; }
    blob="${public_part#* }"
    ensure_report_key_wrapper || return 1
    mkdir -p "${ssh_dir}" || return 1
    chmod 700 "${ssh_dir}" 2>/dev/null || true
    touch "${auth}" || return 1
    chmod 600 "${auth}" 2>/dev/null || true
    group="$(id -gn "${user}" 2>/dev/null || printf '%s' "${user}")"
    chown "${user}:${group}" "${ssh_dir}" "${auth}" 2>/dev/null || true
    options="$(report_key_restricted_options "${scope}")"
    comment="po0-report:scope=${scope},script=${MANAGER_INSTALL_PATH},created=$(utc_now_iso)"
    line="${options} ${public_part} ${comment}"
    if grep -Fq "${blob}" "${auth}" 2>/dev/null; then
        printf '检测到相同公钥已存在，将把匹配行转换/更新为 PO0 受限上报 key。\n'
        make_temp_file "${auth}" || return 1
        tmp="${TEMP_FILE_RESULT}"
        while IFS= read -r existing || [[ -n "${existing}" ]]; do
            if [[ "${existing}" == *"${blob}"* && "${converted}" == "0" ]]; then
                printf '%s\n' "${line}" >> "${tmp}"
                converted=1
            else
                printf '%s\n' "${existing}" >> "${tmp}"
            fi
        done < "${auth}"
        mv -f "${tmp}" "${auth}"
    else
        printf '%s\n' "${line}" >> "${auth}"
    fi
    chmod 600 "${auth}" 2>/dev/null || true
    printf '已安装 PO0 受限上报 key：user=%s scope=%s\n' "${user}" "${scope}"
}

do_manage_report_keys() {
    local choice user scope pubkey
    ensure_layout || return
    while true; do
        menu_clear_screen
        print_title "专用受限上报 key"
        print_menu_section "查看"
        print_menu_pair 1 "显示已有 key 分类" 2 "查看拒绝日志"
        print_menu_section "维护"
        print_menu_pair 3 "新增 / 转换 public key" 4 "刷新 wrapper"
        print_menu_section "退出"
        print_menu_item 0 "返回"
        print_menu_footer
        read_menu_choice_or_return choice "请选择操作 [0-4]: " || return
        case "${choice}" in
            1) user="$(prompt_with_default "系统用户" "root")"; show_report_keys_for_user "${user}"; pause_before_return ;;
            2) show_report_key_denials 80; pause_before_return ;;
            3)
                user="$(prompt_with_default "系统用户" "root")"
                scope="$(prompt_with_default "scope: egern / worker / all" "egern")"
                pubkey="$(read_prompt "请粘贴 public key（.pub 内容），不要粘贴私钥：")" || return
                install_report_public_key "${user}" "${scope}" "${pubkey}"
                pause_before_return
                ;;
            4) ensure_report_key_wrapper && success "已刷新 wrapper：${REPORT_KEY_WRAPPER_PATH}"; pause_before_return ;;
            0) return ;;
            *) err "无效选择。"; pause_before_return ;;
        esac
    done
}

do_show_report_keys_cli() {
    ensure_layout || return 1
    show_report_keys_for_user "${1:-root}"
}

do_show_report_key_denials_cli() {
    ensure_layout || return 1
    show_report_key_denials "${1:-50}"
}

do_refresh_report_key_wrapper_cli() {
    ensure_layout || return 1
    ensure_report_key_wrapper || return 1
    printf '已刷新 PO0 受限上报 key wrapper：%s\n' "${REPORT_KEY_WRAPPER_PATH}"
}

do_install_report_key_cli() {
    local scope="${1:-}" pubkey="${2:-}" user="${3:-root}"
    [[ -n "${scope}" && -n "${pubkey}" ]] || { err "用法：--install-report-key <egern|worker|all> '<public-key-line>' [user]"; return 1; }
    ensure_layout || return 1
    install_report_public_key "${user}" "${scope}" "${pubkey}"
}

do_show_ssh_report_token() {
    local token
    ensure_layout || return 1
    token="$(ssh_report_token_value)" || return 1
    print_title "Egern / SSH report Token"
    printf 'Token file : %s\n' "${SSH_REPORT_TOKEN_FILE}"
    printf 'Token      : %s\n' "${token}"
    echo ""
    echo "PO0 SSH-only report command:"
    printf '  bash %s --ssh-ip-report iphone 1.2.3.4 %s egern 43200 32\n' "$(basename "$0")" "${token}"
    echo ""
    echo "Egern module:"
    printf '  Module URL: %s\n' "${EGERN_SSH_REPORT_MODULE_RAW_URL}"
    printf '  SSH_REPORT_TOKEN=%s\n' "${token}"
    printf '  PO0_SCRIPT=%s\n' "${MANAGER_INSTALL_PATH}"
    echo ""
    echo "Multiple PO0: import one Egern module and merge all target rows into SSH_REPORT_TARGETS."
    printf '  SSH_REPORT_TARGETS row: source_id|host|port|user|script|token|identity|ttl\n'
    printf '    egern-po0|<PO0_HOST>|22|root|%s|%s|egern|43200\n' "${MANAGER_INSTALL_PATH}" "${token}"
}

do_show_webauth_report_token() {
    local token
    ensure_layout || return 1
    token="$(webauth_report_token_value)" || return 1
    print_title "LAN Worker WebAuth 上报 Token"
    printf 'Token 文件 : %s\n' "${WEBAUTH_REPORT_TOKEN_FILE}"
    printf 'Token      : %s\n' "${token}"
    echo ""
    echo "WebAuth 上报示例（由 LAN Worker 通过 SSH 调用）："
    printf '  bash %s --webauth-report cf-access 1.2.3.4 user@example.com %s %s\n' \
        "$(basename "$0")" "$(utc_after_seconds_iso 43200)" "${token}"
}

set_automation_mode() {
    local mode="${1:-}"
    case "${mode}" in
        regular|normal|off)
            AUTOMATION_MODE="regular"
            ;;
        attack|on|freeze)
            AUTOMATION_MODE="attack"
            ;;
        *)
            err "自动白名单安全模式无效：${mode:-空}。可用值：regular、attack。"
            return 1
            ;;
    esac
    ensure_layout || return 1
    load_settings 1
    case "${mode}" in
        regular|normal|off) AUTOMATION_MODE="regular" ;;
        attack|on|freeze) AUTOMATION_MODE="attack" ;;
    esac
    save_settings || return 1
    success "自动白名单安全模式已切换为：${AUTOMATION_MODE}"
}

do_list_pending_auto_sources() {
    ensure_layout || return 1
    print_title "自动来源待审核 IP"
    if [[ ! -s "${AUTO_PENDING_FILE}" ]]; then
        echo "  (暂无待审核自动来源 IP)"
        return 0
    fi
    list_pending_auto_sources
}

do_compat_check() {
    print_title "兼容性检查"
    load_settings 1
    load_rules 1
    load_allowlist_sets 1
    printf '设置文件     : %s\n' "$([[ -f "${SETTINGS_FILE}" ]] && printf 'OK' || printf 'missing')"
    printf '规则文件     : %s 条\n' "${#RULES[@]}"
    printf '白名单模式   : %s (%s)\n' "${SRC_ALLOWLIST_MODE}" "$(src_allowlist_mode_to_label "${SRC_ALLOWLIST_MODE}")"
    printf '允许来源     : %s\n' "$(src_allowlist_mode_default_sources "${SRC_ALLOWLIST_MODE}")"
    printf '旧 custom 文件: %s 条\n' "$(custom_allowlist_count)"
    printf 'entries      : %s 条\n' "$(allowlist_entries_count)"
    printf 'DDNS sources : %s 个\n' "$(allowlist_sources_count)"
    printf '自动白名单安全模式 : %s\n' "${AUTOMATION_MODE}"
    success "兼容性检查完成；未修改任何文件。"
}

do_cleanup_legacy() {
    local mode="${1:---dry-run}"
    local ts
    print_title "清理旧文件"
    case "${mode}" in
        --dry-run|"")
            echo "dry-run：只列出候选，不删除文件。"
            ;;
        --apply)
            ts="$(date '+%Y%m%d_%H%M%S')"
            mkdir -p "${BACKUP_DIR}/legacy-cleanup-${ts}" || return 1
            echo "apply：本版本只执行安全备份和说明，不删除 live state。"
            ;;
        *)
            err "用法：--cleanup-legacy --dry-run|--apply"
            return 1
            ;;
    esac
    echo "保留 live state：规则、白名单、token、DDNS sources、资源任务、日志。"
    echo "可人工检查的旧路径候选："
    printf '  - %s\n' "/usr/local/sbin/nftables-relay-manager"
    printf '  - %s\n' "${CUSTOM_SRC_ALLOWLIST_FILE}（旧 custom 兼容文件，仍参与迁移，不建议删除）"
    success "清理检查完成。"
}

do_check_ddns_report_source() {
    local key="${1:-}"
    local token="${2:-}"
    local line found=0 disabled=0
    key="$(sanitize_allowlist_source_text "$(trim "${key}")")"
    [[ -n "${key}" ]] || {
        printf 'ERROR|缺少 DDNS 来源名称或域名\n'
        return 1
    }
    validate_ddns_report_token_readonly "${token}" || {
        printf 'ERROR|DDNS 外部上报 token 无效\n'
        return 1
    }
    [[ -f "${ALLOWLIST_SOURCES_FILE}" ]] || {
        printf 'ERROR|尚未配置 DDNS 来源\n'
        return 1
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        parse_allowlist_source_line "${line}" || continue
        [[ "${ALLOWLIST_SOURCE_TYPE}" == "ddns" ]] || continue
        if [[ "${ALLOWLIST_SOURCE_NAME}" == "${key}" || "${ALLOWLIST_SOURCE_VALUE}" == "${key}" ]]; then
            found=1
            if [[ "${ALLOWLIST_SOURCE_ENABLED}" != "1" ]]; then
                disabled=1
            fi
            break
        fi
    done < "${ALLOWLIST_SOURCES_FILE}"
    [[ "${found}" == "1" ]] || {
        printf 'ERROR|未找到 DDNS 来源：%s\n' "${key}"
        return 1
    }
    [[ "${disabled}" != "1" ]] || {
        printf 'ERROR|DDNS 来源已停用：%s\n' "${key}"
        return 1
    }
    printf 'OK|DDNS 来源可上报：%s -> %s\n' "${ALLOWLIST_SOURCE_NAME}" "${ALLOWLIST_SOURCE_VALUE}"
}
