#!/usr/bin/env bash
set -uo pipefail

CONF_DIR="/etc/nftables.d"
MAIN_CONF="/etc/nftables.conf"
NFT_CONF="${CONF_DIR}/po0-relay.conf"
SETTINGS_FILE="${CONF_DIR}/po0-relay.env"
RULES_FILE="${CONF_DIR}/po0-relay.rules"
BACKUP_DIR="${CONF_DIR}/backups"
SYSCTL_CONF="/etc/sysctl.d/99-po0-relay.conf"

NAT_TABLE="po0_relay_nat"
MANGLE_TABLE="po0_relay_mangle"

RELAY_LAN_IP=""
ENABLE_MSS_CLAMP="1"
MSS_VALUE="1452"
declare -a RULES=()

C_RESET=""
C_BOLD=""
C_GREEN=""
C_YELLOW=""
C_RED=""
C_CYAN=""
C_PANEL=""

setup_colors() {
    if [[ -t 1 ]]; then
        C_RESET=$'\033[0m'
        C_BOLD=$'\033[1m'
        C_GREEN=$'\033[32m'
        C_YELLOW=$'\033[33m'
        C_RED=$'\033[31m'
        C_CYAN=$'\033[96m'
        C_PANEL=$'\033[38;5;208m'
    fi
}

setup_colors

info() { printf '%b[信息]%b %s\n' "${C_GREEN}" "${C_RESET}" "$1"; }
warn() { printf '%b[警告]%b %s\n' "${C_YELLOW}" "${C_RESET}" "$1"; }
err() { printf '%b[错误]%b %s\n' "${C_RED}" "${C_RESET}" "$1"; }

print_menu_divider() {
    printf '%b%s%b\n' "${C_CYAN}" "------------------------" "${C_RESET}"
}

print_menu_section() {
    print_menu_divider
    printf '%b%s%b\n' "${C_BOLD}${C_CYAN}" "$1" "${C_RESET}"
}

print_menu_item() {
    local number="$1"
    local label="$2"
    printf '  %b%2s%b) %s\n' "${C_CYAN}" "${number}" "${C_RESET}" "${label}"
}

print_menu_footer() {
    print_menu_divider
}

menu_clear_screen() {
    [[ "${MENU_CLEAR:-1}" == "0" ]] && return 0
    [[ -t 1 && -n "${TERM:-}" && "${TERM}" != "dumb" ]] || return 0
    command -v clear >/dev/null 2>&1 && clear || printf '\033[H\033[2J'
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

pause_before_return() {
    local _
    echo ""
    read_prompt "按回车返回菜单..." >/dev/null || true
}

check_root() {
    if [[ ${EUID} -ne 0 ]]; then
        err "请使用 root 运行此脚本。"
        exit 1
    fi
}

confirm_yes() {
    local ans
    ans="$(read_prompt "$1 [y/N]: ")" || return 1
    [[ "$ans" =~ ^[Yy]$ ]]
}

validate_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] || return 1
    [[ ! "$port" =~ ^0[0-9] ]] || return 1
    (( port >= 1 && port <= 65535 ))
}

validate_ip() {
    local ip="$1"
    local IFS='.'
    local octet
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    [[ ! "$ip" =~ (^|\.)0[0-9] ]] || return 1
    read -ra octets <<< "$ip"
    for octet in "${octets[@]}"; do
        (( octet <= 255 )) || return 1
    done
}

validate_mss() {
    local value="$1"
    [[ "$value" =~ ^[0-9]+$ ]] || return 1
    (( value >= 536 && value <= 65535 ))
}

detect_pkg_manager() {
    if command -v apt-get &>/dev/null; then
        echo apt
    elif command -v dnf &>/dev/null; then
        echo dnf
    elif command -v yum &>/dev/null; then
        echo yum
    elif command -v pacman &>/dev/null; then
        echo pacman
    else
        echo unknown
    fi
}

install_nftables_if_needed() {
    local pkg_mgr
    command -v nft &>/dev/null && return 0
    pkg_mgr=$(detect_pkg_manager)
    case "$pkg_mgr" in
        apt) apt-get update -y && apt-get install -y nftables ;;
        dnf) dnf install -y nftables ;;
        yum) yum install -y nftables ;;
        pacman) pacman -Sy --noconfirm nftables ;;
        *) err "无法识别包管理器，请手动安装 nftables。"; return 1 ;;
    esac
    command -v nft &>/dev/null || { err "nftables 安装失败。"; return 1; }
}

warn_conflicts() {
    local found=0
    if systemctl is-active --quiet firewalld 2>/dev/null; then
        warn "检测到 firewalld 正在运行，PO0 专用中转脚本不与其混用。"
        found=1
    fi
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -qw active; then
        warn "检测到 UFW 正在运行，PO0 专用中转脚本不与其混用。"
        found=1
    fi
    (( found == 1 )) && warn "如继续初始化，将由 nftables 独占接管这台中转机。"
}

ensure_layout() {
    mkdir -p "${CONF_DIR}" "${BACKUP_DIR}" || return 1
    [[ -f "${SETTINGS_FILE}" ]] || save_settings
    [[ -f "${RULES_FILE}" ]] || save_rules
}

backup_takeover_files() {
    local ts file
    ts=$(date '+%Y%m%d_%H%M%S')
    [[ -f "${MAIN_CONF}" ]] && mv "${MAIN_CONF}" "${MAIN_CONF}.bak.${ts}" 2>/dev/null || true
    for file in "${CONF_DIR}"/*.conf; do
        [[ -f "$file" ]] || continue
        mv "$file" "${file}.bak.${ts}" 2>/dev/null || true
    done
}

backup_managed_files() {
    local ts file
    ts=$(date '+%Y%m%d_%H%M%S')
    for file in "${NFT_CONF}" "${SETTINGS_FILE}" "${RULES_FILE}"; do
        [[ -f "$file" ]] && cp "$file" "${BACKUP_DIR}/$(basename "$file").${ts}" 2>/dev/null || true
    done
}

load_settings() {
    RELAY_LAN_IP=""
    ENABLE_MSS_CLAMP="1"
    MSS_VALUE="1452"
    if [[ -f "${SETTINGS_FILE}" ]]; then
        # shellcheck disable=SC1090
        source "${SETTINGS_FILE}"
    fi
    [[ "${ENABLE_MSS_CLAMP}" == "0" || "${ENABLE_MSS_CLAMP}" == "1" ]] || ENABLE_MSS_CLAMP="1"
    validate_mss "${MSS_VALUE}" || MSS_VALUE="1452"
}

save_settings() {
    local tmp="${SETTINGS_FILE}.tmp.$$"
    cat > "${tmp}" <<EOF
RELAY_LAN_IP="${RELAY_LAN_IP}"
ENABLE_MSS_CLAMP="${ENABLE_MSS_CLAMP}"
MSS_VALUE="${MSS_VALUE}"
EOF
    mv -f "${tmp}" "${SETTINGS_FILE}"
}

load_rules() {
    local lport dip dport
    RULES=()
    [[ -f "${RULES_FILE}" ]] || return 0
    while IFS='|' read -r lport dip dport; do
        [[ -z "${lport}" ]] && continue
        [[ "${lport}" =~ ^# ]] && continue
        validate_port "${lport}" && validate_ip "${dip}" && validate_port "${dport}" || continue
        RULES+=("${lport}|${dip}|${dport}")
    done < "${RULES_FILE}"
}

save_rules() {
    local tmp="${RULES_FILE}.tmp.$$"
    local rule lport dip dport
    : > "${tmp}"
    for rule in "${RULES[@]}"; do
        IFS='|' read -r lport dip dport <<< "${rule}"
        printf '%s|%s|%s\n' "${lport}" "${dip}" "${dport}" >> "${tmp}"
    done
    mv -f "${tmp}" "${RULES_FILE}"
}

settings_ready() {
    load_settings
    validate_ip "${RELAY_LAN_IP}" || {
        err "PO0 内网 IP 尚未设置，请先执行【1】安装/初始化或【7】修改 PO0 参数。"
        return 1
    }
}

print_settings() {
    load_settings
    printf "PO0 内网 IP : %s\n" "${RELAY_LAN_IP:-未设置}"
    if [[ "${ENABLE_MSS_CLAMP}" == "1" ]]; then
        printf "MSS 修正    : 开启 (%s)\n" "${MSS_VALUE}"
    else
        printf "MSS 修正    : 关闭\n"
    fi
}

prompt_settings() {
    local input ans
    load_settings
    while true; do
        input="$(read_prompt "请输入 PO0 内网 IP${RELAY_LAN_IP:+ [当前: ${RELAY_LAN_IP}]}: ")" || input=""
        input="${input:-${RELAY_LAN_IP}}"
        validate_ip "${input}" && { RELAY_LAN_IP="${input}"; break; }
        err "IP 地址格式无效。"
    done
    if [[ "${ENABLE_MSS_CLAMP}" == "1" ]]; then
        ans="$(read_prompt "是否保留 MSS 修正 (默认开启)？[Y/n]: ")" || ans=""
        [[ "${ans}" =~ ^[Nn]$ ]] && { ENABLE_MSS_CLAMP="0"; return 0; }
    else
        ans="$(read_prompt "是否开启 MSS 修正？[y/N]: ")" || ans=""
        [[ "${ans}" =~ ^[Yy]$ ]] || { ENABLE_MSS_CLAMP="0"; return 0; }
    fi
    ENABLE_MSS_CLAMP="1"
    while true; do
        input="$(read_prompt "请输入 MSS 值 [当前: ${MSS_VALUE}]: ")" || input=""
        input="${input:-${MSS_VALUE}}"
        validate_mss "${input}" && { MSS_VALUE="${input}"; return 0; }
        err "MSS 值无效，请输入 536-65535。"
    done
}

unique_dest_ip_set() {
    local seen=" " out="" rule _lport dip _dport
    for rule in "${RULES[@]}"; do
        IFS='|' read -r _lport dip _dport <<< "${rule}"
        if [[ "${seen}" != *" ${dip} "* ]]; then
            [[ -n "${out}" ]] && out+=", "
            out+="${dip}"
            seen+=" ${dip} "
        fi
    done
    printf '%s' "${out}"
}

write_main_conf() {
    cat > "${MAIN_CONF}" <<'EOF'
#!/usr/sbin/nft -f
flush ruleset
include "/etc/nftables.d/*.conf"
EOF
}

write_nft_conf() {
    local tmp="${NFT_CONF}.tmp.$$" rule lport dip dport ip_set
    load_settings
    load_rules
    cat > "${tmp}" <<EOF
#!/usr/sbin/nft -f
define RELAY_LAN_IP = ${RELAY_LAN_IP}

table ip ${NAT_TABLE} {
    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
EOF
    for rule in "${RULES[@]}"; do
        IFS='|' read -r lport dip dport <<< "${rule}"
        printf '\n        meta l4proto { tcp, udp } th dport %s dnat to %s:%s\n' "${lport}" "${dip}" "${dport}" >> "${tmp}"
    done
    cat >> "${tmp}" <<EOF
    }
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
EOF
    for rule in "${RULES[@]}"; do
        IFS='|' read -r lport dip dport <<< "${rule}"
        printf '\n        ip daddr %s meta l4proto { tcp, udp } th dport %s snat to $RELAY_LAN_IP\n' "${dip}" "${dport}" >> "${tmp}"
    done
    cat >> "${tmp}" <<EOF
    }
}
EOF
    if [[ "${ENABLE_MSS_CLAMP}" == "1" ]]; then
        ip_set="$(unique_dest_ip_set)"
        cat >> "${tmp}" <<EOF

table ip ${MANGLE_TABLE} {
    chain forward {
        type filter hook forward priority mangle; policy accept;
EOF
        [[ -n "${ip_set}" ]] && printf '        ip daddr { %s } tcp flags syn tcp option maxseg size set %s\n' "${ip_set}" "${MSS_VALUE}" >> "${tmp}"
        cat >> "${tmp}" <<'EOF'
    }
}
EOF
    fi
    mv -f "${tmp}" "${NFT_CONF}"
}

reload_managed_rules() {
    nft -c -f "${NFT_CONF}" >/dev/null 2>&1 || { err "配置预检失败，请检查 ${NFT_CONF}。"; return 1; }
    nft delete table ip "${NAT_TABLE}" 2>/dev/null || true
    nft delete table ip "${MANGLE_TABLE}" 2>/dev/null || true
    nft -f "${NFT_CONF}" || { err "加载 ${NFT_CONF} 失败。"; return 1; }
}

apply_full_config() {
    nft -c -f "${MAIN_CONF}" >/dev/null 2>&1 || { err "主配置预检失败。"; return 1; }
    nft -f "${MAIN_CONF}" || { err "加载 ${MAIN_CONF} 失败。"; return 1; }
}

enable_ip_forward() {
    mkdir -p "$(dirname "${SYSCTL_CONF}")" 2>/dev/null || true
    touch "${SYSCTL_CONF}" 2>/dev/null || true
    grep -qE '^[[:space:]]*net\.ipv4\.ip_forward[[:space:]]*=' "${SYSCTL_CONF}" 2>/dev/null \
        && sed -i -E 's|^[[:space:]]*net\.ipv4\.ip_forward[[:space:]]*=.*|net.ipv4.ip_forward=1|' "${SYSCTL_CONF}" 2>/dev/null \
        || echo "net.ipv4.ip_forward=1" >> "${SYSCTL_CONF}" 2>/dev/null
    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
    sysctl -p "${SYSCTL_CONF}" >/dev/null 2>&1 || true
}

enable_bbr_fq() {
    modprobe tcp_bbr 2>/dev/null || true
    grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null || { warn "当前内核不支持 BBR。"; return 0; }
    sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1 || true
    sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1 || true
    grep -qE '^[[:space:]]*net\.core\.default_qdisc[[:space:]]*=' "${SYSCTL_CONF}" 2>/dev/null \
        && sed -i -E 's|^[[:space:]]*net\.core\.default_qdisc[[:space:]]*=.*|net.core.default_qdisc=fq|' "${SYSCTL_CONF}" 2>/dev/null \
        || echo "net.core.default_qdisc=fq" >> "${SYSCTL_CONF}" 2>/dev/null
    grep -qE '^[[:space:]]*net\.ipv4\.tcp_congestion_control[[:space:]]*=' "${SYSCTL_CONF}" 2>/dev/null \
        && sed -i -E 's|^[[:space:]]*net\.ipv4\.tcp_congestion_control[[:space:]]*=.*|net.ipv4.tcp_congestion_control=bbr|' "${SYSCTL_CONF}" 2>/dev/null \
        || echo "net.ipv4.tcp_congestion_control=bbr" >> "${SYSCTL_CONF}" 2>/dev/null
    sysctl -p "${SYSCTL_CONF}" >/dev/null 2>&1 || true
    info "已写入 BBR + fq。"
}

check_port_conflict() {
    local port="$1" conflict=""
    ss -tlnp 2>/dev/null | grep -qE ":${port}\b" && conflict="TCP"
    if ss -ulnp 2>/dev/null | grep -qE ":${port}\b"; then
        [[ -n "${conflict}" ]] && conflict="TCP+UDP" || conflict="UDP"
    fi
    if [[ -n "${conflict}" ]]; then
        warn "端口 ${port} 已被本机其他服务占用（${conflict}）。"
        confirm_yes "是否仍然继续添加" || return 1
    fi
}

do_install() {
    echo ""
    warn "该脚本按 PO0 专用中转机思路工作，将接管 /etc/nftables.conf。"
    warn "初始化会 flush ruleset，并改写为 include /etc/nftables.d/*.conf。"
    warn_conflicts
    confirm_yes "是否继续初始化" || { info "已取消。"; return; }
    install_nftables_if_needed || return
    ensure_layout || return
    backup_takeover_files
    backup_managed_files
    load_rules
    prompt_settings || return
    save_settings || return
    save_rules || return
    write_main_conf
    write_nft_conf
    enable_ip_forward
    apply_full_config || return
    systemctl enable --now nftables 2>/dev/null || warn "无法自动启用 nftables 服务，请手动执行 systemctl enable --now nftables"
    info "初始化完成。"
    print_settings
}

do_list() {
    local idx=1 rule lport dip dport
    echo ""
    settings_ready || return
    load_rules
    print_settings
    echo ""
    if [[ ${#RULES[@]} -eq 0 ]]; then
        info "当前没有转发规则。"
        return
    fi
    printf "\n\033[1m%-6s %-10s %-10s    %-22s\033[0m\n" "序号" "协议" "监听端口" "目标地址"
    echo "──────────────────────────────────────────────────────"
    for rule in "${RULES[@]}"; do
        IFS='|' read -r lport dip dport <<< "${rule}"
        printf "%-6s %-10s %-10s -> %-22s\n" "${idx}" "tcp+udp" "${lport}" "${dip}:${dport}"
        ((idx++))
    done
}

do_add() {
    local lport dip dport confirm current rule
    echo ""
    command -v nft &>/dev/null || { err "请先执行【1】安装/初始化。"; return; }
    settings_ready || return
    ensure_layout || return
    load_rules
    while true; do lport="$(read_prompt "请输入 PO0 监听端口: ")" || return; validate_port "${lport}" && break; err "端口无效。"; done
    for rule in "${RULES[@]}"; do IFS='|' read -r current _ _ <<< "${rule}"; [[ "${current}" == "${lport}" ]] && { err "端口 ${lport} 已存在规则。"; return; }; done
    check_port_conflict "${lport}" || { info "已取消。"; return; }
    while true; do dip="$(read_prompt "请输入落地机 IP: ")" || return; validate_ip "${dip}" && break; err "IP 无效。"; done
    while true; do dport="$(read_prompt "请输入落地机端口 [默认: ${lport}]: ")" || return; dport="${dport:-${lport}}"; validate_port "${dport}" && break; err "端口无效。"; done
    echo "即将添加 :${lport} -> ${dip}:${dport}，SNAT -> ${RELAY_LAN_IP}"
    [[ "${ENABLE_MSS_CLAMP}" == "1" ]] && echo "MSS 修正 -> ${MSS_VALUE}"
    confirm="$(read_prompt "确认添加？[Y/n]: ")" || confirm=""
    [[ "${confirm}" =~ ^[Nn]$ ]] && { info "已取消。"; return; }
    backup_managed_files
    RULES+=("${lport}|${dip}|${dport}")
    save_rules || return
    write_nft_conf
    reload_managed_rules && info "添加成功。"
}

do_delete() {
    local idx=1 choice confirm target rule lport dip dport
    echo ""
    command -v nft &>/dev/null || { err "请先执行【1】安装/初始化。"; return; }
    settings_ready || return
    load_rules
    [[ ${#RULES[@]} -gt 0 ]] || { info "当前没有转发规则。"; return; }
    for rule in "${RULES[@]}"; do IFS='|' read -r lport dip dport <<< "${rule}"; printf "%2s) :%s -> %s:%s\n" "${idx}" "${lport}" "${dip}" "${dport}"; ((idx++)); done
    choice="$(read_prompt "请输入要删除的序号 (0 取消): ")" || return
    [[ -z "${choice}" || "${choice}" == "0" ]] && { info "已取消。"; return; }
    [[ "${choice}" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#RULES[@]} )) || { err "序号无效。"; return; }
    target="${RULES[$((choice - 1))]}"
    IFS='|' read -r lport dip dport <<< "${target}"
    confirm="$(read_prompt "确认删除 :${lport} -> ${dip}:${dport}？[Y/n]: ")" || confirm=""
    [[ "${confirm}" =~ ^[Nn]$ ]] && { info "已取消。"; return; }
    backup_managed_files
    unset 'RULES[$((choice - 1))]'
    RULES=("${RULES[@]}")
    save_rules || return
    write_nft_conf
    reload_managed_rules && info "删除成功。"
}

do_clear_all() {
    echo ""
    command -v nft &>/dev/null || { err "请先执行【1】安装/初始化。"; return; }
    settings_ready || return
    load_rules
    [[ ${#RULES[@]} -gt 0 ]] || { info "当前没有转发规则。"; return; }
    warn "即将清空全部 ${#RULES[@]} 条转发规则。"
    confirm_yes "确认清空" || { info "已取消。"; return; }
    backup_managed_files
    RULES=()
    save_rules || return
    write_nft_conf
    reload_managed_rules && info "已清空全部规则。"
}

do_diagnose() {
    echo ""
    echo "========================================"
    echo "           诊断 / 自检"
    echo "========================================"
    command -v nft &>/dev/null && info "nftables: $(nft --version 2>/dev/null)" || err "nftables: 未安装"
    [[ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" == "1" ]] && info "IPv4 转发: 已开启" || warn "IPv4 转发: 未开启"
    print_settings
    warn_conflicts
    [[ -f "${NFT_CONF}" ]] && nft -c -f "${NFT_CONF}" >/dev/null 2>&1 && info "relay 配置语法: 通过" || warn "relay 配置语法: 未通过或文件不存在"
    nft list table ip "${NAT_TABLE}" &>/dev/null && info "NAT 表已加载" || warn "NAT 表未加载"
    if [[ "${ENABLE_MSS_CLAMP}" == "1" ]]; then
        nft list table ip "${MANGLE_TABLE}" &>/dev/null && info "MSS 表已加载" || warn "MSS 表未加载"
    fi
}

do_edit_settings() {
    echo ""
    command -v nft &>/dev/null || { err "请先执行【1】安装/初始化。"; return; }
    ensure_layout || return
    load_rules
    prompt_settings || return
    backup_managed_files
    save_settings || return
    write_nft_conf
    reload_managed_rules && { info "PO0 参数已更新。"; print_settings; }
}

do_enable_bbr() {
    echo ""
    warn "纯 nftables 内核转发本身并不依赖 BBR，此项仅作可选优化。"
    confirm_yes "是否继续开启 BBR + fq" || { info "已取消。"; return; }
    enable_bbr_fq
}

main_menu() {
    local choice
    while true; do
        menu_clear_screen
        print_menu_section "PO0 nftables relay manager"
        print_menu_item 1 "安装 / 初始化 nftables"
        print_menu_item 2 "查看当前配置与转发"
        print_menu_item 3 "新增端口转发"
        print_menu_item 4 "删除端口转发"
        print_menu_item 5 "一键清空所有转发"
        print_menu_section "维护"
        print_menu_item 6 "诊断 / 自检"
        print_menu_item 7 "修改 PO0 参数"
        print_menu_item 8 "可选开启 BBR + fq"
        print_menu_footer
        print_menu_item 0 "退出"
        print_menu_footer
        choice="$(read_prompt "请选择操作 [0-8]: ")" || exit 0
        case "${choice}" in
            1) do_install; pause_before_return ;;
            2) do_list; pause_before_return ;;
            3) do_add; pause_before_return ;;
            4) do_delete; pause_before_return ;;
            5) do_clear_all; pause_before_return ;;
            6) do_diagnose; pause_before_return ;;
            7) do_edit_settings; pause_before_return ;;
            8) do_enable_bbr; pause_before_return ;;
            0) info "再见。"; exit 0 ;;
            *) err "无效选择，请输入 0-8。"; pause_before_return ;;
        esac
    done
}

check_root
main_menu
