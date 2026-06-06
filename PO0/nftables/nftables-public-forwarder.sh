#!/usr/bin/env bash
set -uo pipefail

# Public-port nftables forwarder for an existing VPS.
# It deliberately does not rewrite /etc/nftables.conf and never flushes ruleset.

APP_NAME="po0-public-forwarder"
CONF_DIR="/etc/nftables.d"
STATE_DIR="/etc/${APP_NAME}"
BACKUP_DIR="${STATE_DIR}/backups"
RULES_FILE="${STATE_DIR}/rules.tsv"
NFT_CONF="${CONF_DIR}/${APP_NAME}.nft"
SYSCTL_CONF="/etc/sysctl.d/99-${APP_NAME}.conf"
SERVICE_NAME="${APP_NAME}.service"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"

NAT_TABLE="po0_public_forward_nat"
FILTER_TABLE="po0_public_forward_filter"
MANGLE_TABLE="po0_public_forward_mangle"
NFT_MARK="0x70663001"

ENABLE_MSS_CLAMP="1"
MSS_VALUE="1452"

FORWARD_PORT_MIN="24576"
FORWARD_PORT_MAX="49151"
SUGGEST_PORT_RANDOM_TRIES="200"

declare -a RULES=()

C_RESET=""
C_BOLD=""
C_GREEN=""
C_YELLOW=""
C_RED=""
C_CYAN=""

setup_colors() {
  if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_RED=$'\033[31m'
    C_CYAN=$'\033[36m'
  fi
}

info() { printf '%b[信息]%b %s\n' "${C_GREEN}" "${C_RESET}" "$1"; }
warn() { printf '%b[警告]%b %s\n' "${C_YELLOW}" "${C_RESET}" "$1"; }
err() { printf '%b[错误]%b %s\n' "${C_RED}" "${C_RESET}" "$1" >&2; }
success() { printf '%b[完成]%b %s\n' "${C_GREEN}" "${C_RESET}" "$1"; }

print_divider() {
  printf '%s\n' "------------------------------------------------------------"
}

print_title() {
  echo ""
  print_divider
  printf '%b%s%b\n' "${C_BOLD}${C_CYAN}" "$1" "${C_RESET}"
  print_divider
}

pause_before_return() {
  echo ""
  read -r -p "按回车返回菜单..." _
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

check_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "请使用 root 运行：sudo bash $0"
    exit 1
  fi
}

confirm_yes() {
  local ans
  read -r -p "$1 [y/N]: " ans
  [[ "${ans}" =~ ^[Yy]$ ]]
}

prompt_with_default() {
  local prompt="$1"
  local default="${2-}"
  local value
  if [[ -n "${default}" ]]; then
    read -r -p "${prompt} [默认: ${default}]: " value
    printf '%s\n' "${value:-${default}}"
  else
    read -r -p "${prompt}: " value
    printf '%s\n' "${value}"
  fi
}

validate_port() {
  local port="$1"
  [[ "${port}" =~ ^[0-9]+$ ]] || return 1
  [[ ! "${port}" =~ ^0[0-9] ]] || return 1
  (( port >= 1 && port <= 65535 ))
}

listen_port_in_forward_range() {
  local port="$1"
  validate_port "${port}" || return 1
  (( port >= FORWARD_PORT_MIN && port <= FORWARD_PORT_MAX ))
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

validate_host_ipv4() {
  local ip="$1"
  local o1 o2
  validate_ip "${ip}" || return 1
  IFS='.' read -r o1 o2 _ _ <<< "${ip}"
  (( o1 == 0 )) && return 1
  (( o1 == 127 )) && return 1
  (( o1 == 169 && o2 == 254 )) && return 1
  (( o1 >= 224 )) && return 1
  return 0
}

validate_mss() {
  local value="$1"
  [[ "${value}" =~ ^[0-9]+$ ]] || return 1
  (( value >= 536 && value <= 65535 ))
}

proto_to_label() {
  case "$1" in
    tcp) printf 'tcp' ;;
    udp) printf 'udp' ;;
    *) printf 'tcp+udp' ;;
  esac
}

proto_to_nft_expr() {
  case "$1" in
    tcp) printf 'tcp' ;;
    udp) printf 'udp' ;;
    *) printf '{ tcp, udp }' ;;
  esac
}

normalize_proto() {
  local value
  value="$(trim "${1:-}")"
  value="${value,,}"
  case "${value}" in
    ""|1|both|all|tcp+udp|tcpudp) printf 'both\n' ;;
    2|tcp) printf 'tcp\n' ;;
    3|udp) printf 'udp\n' ;;
    *) return 1 ;;
  esac
}

sanitize_name() {
  local value="$1"
  value="$(trim "${value}")"
  value="$(printf '%s' "${value}" | tr -d '\r\n|' | sed -E 's/[[:space:]]+/ /g')"
  printf '%s' "${value:-forward}"
}

escape_nft_comment() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "${value}"
}

has_systemd() {
  has_cmd systemctl && [[ -d /run/systemd/system ]]
}

service_enabled_label() {
  local state
  has_systemd || {
    printf '不可用'
    return
  }
  state="$(systemctl is-enabled "${SERVICE_NAME}" 2>/dev/null || true)"
  [[ -n "${state}" ]] && printf '%s' "${state}" || printf '未启用'
}

detect_pkg_manager() {
  if has_cmd apt-get; then
    printf 'apt\n'
  elif has_cmd dnf; then
    printf 'dnf\n'
  elif has_cmd yum; then
    printf 'yum\n'
  elif has_cmd pacman; then
    printf 'pacman\n'
  else
    printf 'unknown\n'
  fi
}

install_nftables_if_needed() {
  local pkg_mgr
  has_cmd nft && return 0
  warn "未找到 nft 命令，需要先安装 nftables。"
  confirm_yes "是否自动安装 nftables" || return 1

  pkg_mgr="$(detect_pkg_manager)"
  case "${pkg_mgr}" in
    apt) apt-get update -y && apt-get install -y nftables ;;
    dnf) dnf install -y nftables ;;
    yum) yum install -y nftables ;;
    pacman) pacman -Sy --noconfirm nftables ;;
    *) err "无法识别包管理器，请手动安装 nftables。"; return 1 ;;
  esac

  has_cmd nft || {
    err "nftables 安装后仍无法找到 nft 命令。"
    return 1
  }
}

ensure_layout() {
  mkdir -p "${CONF_DIR}" "${STATE_DIR}" "${BACKUP_DIR}" || return 1
  [[ -f "${RULES_FILE}" ]] || : > "${RULES_FILE}"
}

backup_managed_files() {
  local ts file
  ts="$(date '+%Y%m%d_%H%M%S')"
  for file in "${RULES_FILE}" "${NFT_CONF}" "${SERVICE_FILE}"; do
    [[ -f "${file}" ]] || continue
    cp "${file}" "${BACKUP_DIR}/$(basename "${file}").${ts}.bak" 2>/dev/null || true
  done
}

load_rules() {
  local line name proto lport dip dport enabled
  RULES=()
  [[ -f "${RULES_FILE}" ]] || return 0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    [[ -z "$(trim "${line}")" ]] && continue
    [[ "${line}" =~ ^[[:space:]]*# ]] && continue
    IFS='|' read -r name proto lport dip dport enabled _ <<< "${line}"
    proto="$(normalize_proto "${proto}" 2>/dev/null || true)"
    enabled="${enabled:-1}"
    if [[ -n "${proto}" ]] && validate_port "${lport}" && validate_host_ipv4 "${dip}" && validate_port "${dport}" && [[ "${enabled}" =~ ^[01]$ ]]; then
      RULES+=("$(sanitize_name "${name}")|${proto}|${lport}|${dip}|${dport}|${enabled}")
    fi
  done < "${RULES_FILE}"
}

save_rules() {
  local tmp rule
  tmp="$(mktemp "${STATE_DIR}/rules.tsv.tmp.XXXXXX")" || return 1
  for rule in "${RULES[@]}"; do
    printf '%s\n' "${rule}" >> "${tmp}"
  done
  mv -f "${tmp}" "${RULES_FILE}"
}

parse_rule() {
  IFS='|' read -r RULE_NAME RULE_PROTO RULE_LPORT RULE_DIP RULE_DPORT RULE_ENABLED _ <<< "$1"
}

rule_conflicts() {
  local proto="$1"
  local lport="$2"
  local skip_index="${3:-}"
  local idx=0 rule current_proto current_lport
  for rule in "${RULES[@]}"; do
    idx=$((idx + 1))
    [[ "${idx}" == "${skip_index}" ]] && continue
    parse_rule "${rule}"
    current_proto="${RULE_PROTO}"
    current_lport="${RULE_LPORT}"
    [[ "${current_lport}" == "${lport}" ]] || continue
    [[ "${current_proto}" == "both" || "${proto}" == "both" || "${current_proto}" == "${proto}" ]] && return 0
  done
  return 1
}

local_port_in_use() {
  local port="$1"
  local proto="$2"
  if has_cmd ss; then
    if [[ "${proto}" == "both" || "${proto}" == "tcp" ]]; then
      ss -H -tln 2>/dev/null | awk -v port="${port}" '$4 ~ "(^|[:.])" port "$" { found=1 } END { exit found ? 0 : 1 }' && return 0
    fi
    if [[ "${proto}" == "both" || "${proto}" == "udp" ]]; then
      ss -H -uln 2>/dev/null | awk -v port="${port}" '$4 ~ "(^|[:.])" port "$" { found=1 } END { exit found ? 0 : 1 }' && return 0
    fi
  elif has_cmd lsof; then
    if [[ "${proto}" == "both" || "${proto}" == "tcp" ]]; then
      lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1 && return 0
    fi
    if [[ "${proto}" == "both" || "${proto}" == "udp" ]]; then
      lsof -nP -iUDP:"${port}" >/dev/null 2>&1 && return 0
    fi
  elif has_cmd netstat; then
    if [[ "${proto}" == "both" || "${proto}" == "tcp" ]]; then
      netstat -lnt 2>/dev/null | awk -v port="${port}" '$4 ~ "(^|[:.])" port "$" { found=1 } END { exit found ? 0 : 1 }' && return 0
    fi
    if [[ "${proto}" == "both" || "${proto}" == "udp" ]]; then
      netstat -lnu 2>/dev/null | awk -v port="${port}" '$4 ~ "(^|[:.])" port "$" { found=1 } END { exit found ? 0 : 1 }' && return 0
    fi
  fi
  return 1
}

show_local_port_owner() {
  local port="$1"
  if has_cmd ss; then
    ss -H -lntup 2>/dev/null | awk -v port="${port}" '$5 ~ "(^|[:.])" port "$" { print }' || true
  elif has_cmd lsof; then
    lsof -nP -i:"${port}" 2>/dev/null || true
  elif has_cmd netstat; then
    netstat -lntup 2>/dev/null | awk -v port="${port}" '$4 ~ "(^|[:.])" port "$" { print }' || true
  fi
}

known_service_port_in_use() {
  local port="$1"
  local file value
  for file in /root/agsbx/port_* /home/*/agsbx/port_*; do
    [[ -f "${file}" ]] || continue
    value="$(trim "$(cat "${file}" 2>/dev/null || true)")"
    [[ "${value}" == "${port}" ]] && {
      printf 'argosbx:%s\n' "${file}"
      return 0
    }
  done
  if [[ -f /opt/agsbx-extra/vless-raw-enc/service.env ]]; then
    value="$(awk -F= '$1=="PORT" {gsub(/^'\''|'\''$/, "", $2); print $2; exit}' /opt/agsbx-extra/vless-raw-enc/service.env 2>/dev/null || true)"
    [[ "${value}" == "${port}" ]] && {
      printf 'agsbx-extra-vless-raw-enc:/opt/agsbx-extra/vless-raw-enc/service.env\n'
      return 0
    }
  fi
  if [[ -f /etc/shadowsocks-rust/config.json ]] && has_cmd python3; then
    value="$(python3 - /etc/shadowsocks-rust/config.json <<'PY' 2>/dev/null || true
import json, sys
with open(sys.argv[1]) as f:
    print(json.load(f).get("server_port", ""))
PY
)"
    [[ "${value}" == "${port}" ]] && {
      printf 'ss-rust:/etc/shadowsocks-rust/config.json\n'
      return 0
    }
  fi
  return 1
}

runtime_dnat_port_in_use() {
  local port="$1"
  local proto="$2"
  has_cmd nft || return 1
  nft -a list ruleset 2>/dev/null | awk -v port="${port}" -v proto="${proto}" '
    /dnat/ && /(tcp|udp|th)[[:space:]]+dport/ && $0 ~ "(^|[^0-9])" port "([^0-9]|$)" {
      if (proto == "both" || $0 ~ "meta l4proto \\{ tcp, udp \\}" || $0 ~ "meta l4proto " proto || $0 ~ proto "[[:space:]]+dport" || $0 ~ "th[[:space:]]+dport") {
        found = 1
        print
      }
    }
    END { exit found ? 0 : 1 }
  '
}

ensure_listen_port_safe() {
  local port="$1"
  local proto="$2"
  local known
  validate_port "${port}" || {
    err "端口必须是 1-65535 的整数，且不能带前导 0。"
    return 1
  }
  listen_port_in_forward_range "${port}" || {
    err "入口端口必须在 ${FORWARD_PORT_MIN}-${FORWARD_PORT_MAX} 范围内。"
    return 1
  }
  if local_port_in_use "${port}" "${proto}"; then
    err "端口 ${port}/${proto_to_label "${proto}"} 已被本机服务监听，不能作为公网转发入口。"
    show_local_port_owner "${port}" >&2
    return 1
  fi
  known="$(known_service_port_in_use "${port}" || true)"
  if [[ -n "${known}" ]]; then
    err "端口 ${port} 出现在已知服务端口记录中：${known}"
    return 1
  fi
  if runtime_dnat_port_in_use "${port}" "${proto}" >/tmp/${APP_NAME}.dnat-check.$$ 2>/dev/null; then
    err "端口 ${port}/${proto_to_label "${proto}"} 已存在运行时 DNAT 规则，不能重复接管。"
    cat "/tmp/${APP_NAME}.dnat-check.$$" >&2
    rm -f "/tmp/${APP_NAME}.dnat-check.$$"
    return 1
  fi
  rm -f "/tmp/${APP_NAME}.dnat-check.$$" 2>/dev/null || true
}

choose_candidate_port() {
  local proto="${1:-both}"
  local port

  for _ in $(seq 1 "${SUGGEST_PORT_RANDOM_TRIES}"); do
    port="$(random_forward_port)"
    ensure_listen_port_safe "${port}" "${proto}" >/dev/null 2>&1 || continue
    rule_conflicts "${proto}" "${port}" && continue
    printf '%s\n' "${port}"
    return 0
  done

  for ((port = FORWARD_PORT_MIN; port <= FORWARD_PORT_MAX; port++)); do
    ensure_listen_port_safe "${port}" "${proto}" >/dev/null 2>&1 || continue
    rule_conflicts "${proto}" "${port}" && continue
    printf '%s\n' "${port}"
    return 0
  done

  return 1
}

random_forward_port() {
  local span=$((FORWARD_PORT_MAX - FORWARD_PORT_MIN + 1))
  local n

  if has_cmd shuf; then
    shuf -i "${FORWARD_PORT_MIN}-${FORWARD_PORT_MAX}" -n 1
    return 0
  fi

  if has_cmd od && [[ -r /dev/urandom ]]; then
    n="$(od -An -N4 -tu4 /dev/urandom 2>/dev/null | tr -d '[:space:]')"
    if [[ "${n}" =~ ^[0-9]+$ ]]; then
      printf '%s\n' "$((FORWARD_PORT_MIN + (n % span)))"
      return 0
    fi
  fi

  printf '%s\n' "$((FORWARD_PORT_MIN + (RANDOM % span)))"
}

prompt_protocol() {
  local value
  while true; do
    read -r -p "选择协议 [1=tcp+udp, 2=tcp, 3=udp，默认 1]: " value
    value="$(normalize_proto "${value:-both}" 2>/dev/null || true)"
    [[ -n "${value}" ]] && {
      printf '%s\n' "${value}"
      return 0
    }
    err "协议只能选择 1 / 2 / 3，或输入 both/tcp/udp。"
  done
}

prompt_listen_port() {
  local proto="$1"
  local default="$2"
  local value
  while true; do
    value="$(prompt_with_default "请输入公网入口端口" "${default}")"
    value="$(trim "${value}")"
    ensure_listen_port_safe "${value}" "${proto}" && {
      printf '%s\n' "${value}"
      return 0
    }
  done
}

prompt_destination_ip() {
  local value
  while true; do
    value="$(prompt_with_default "请输入目标服务器 IPv4" "")"
    value="$(trim "${value}")"
    validate_host_ipv4 "${value}" && {
      printf '%s\n' "${value}"
      return 0
    }
    err "目标 IP 无效，不能使用 0.0.0.0、127.0.0.1、169.254.x.x 或组播/保留地址。"
  done
}

prompt_destination_port() {
  local default="$1"
  local value
  while true; do
    value="$(prompt_with_default "请输入目标端口" "${default}")"
    value="$(trim "${value}")"
    validate_port "${value}" && {
      printf '%s\n' "${value}"
      return 0
    }
    err "目标端口必须是 1-65535 的整数。"
  done
}

enabled_rule_count() {
  local count=0 rule
  for rule in "${RULES[@]}"; do
    parse_rule "${rule}"
    [[ "${RULE_ENABLED}" == "1" ]] && count=$((count + 1))
  done
  printf '%s\n' "${count}"
}

write_nft_conf() {
  local tmp rule proto_expr comment
  tmp="$(mktemp "${STATE_DIR}/${APP_NAME}.nft.tmp.XXXXXX")" || return 1
  load_rules

  cat > "${tmp}" <<EOF
#!/usr/sbin/nft -f
# Managed by ${APP_NAME}. This file is safe to load without flushing ruleset.
define PO0_PUBLIC_FORWARD_MARK = ${NFT_MARK}

table ip ${NAT_TABLE} {
    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
EOF

  for rule in "${RULES[@]}"; do
    parse_rule "${rule}"
    [[ "${RULE_ENABLED}" == "1" ]] || continue
    proto_expr="$(proto_to_nft_expr "${RULE_PROTO}")"
    comment="$(escape_nft_comment "${RULE_NAME}")"
    printf '        meta l4proto %s th dport %s counter ct mark set $PO0_PUBLIC_FORWARD_MARK dnat to %s:%s comment "%s"\n' \
      "${proto_expr}" "${RULE_LPORT}" "${RULE_DIP}" "${RULE_DPORT}" "${comment}" >> "${tmp}"
  done

  cat >> "${tmp}" <<EOF
    }

    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        ct mark \$PO0_PUBLIC_FORWARD_MARK counter masquerade comment "po0-public-forward-masquerade"
    }
}

table ip ${FILTER_TABLE} {
    chain forward_guard {
        type filter hook forward priority -50; policy accept;
        ct mark \$PO0_PUBLIC_FORWARD_MARK counter accept comment "po0-public-forward-allow"
    }
}
EOF

  if [[ "${ENABLE_MSS_CLAMP}" == "1" ]]; then
    cat >> "${tmp}" <<EOF

table ip ${MANGLE_TABLE} {
    chain forward_mss {
        type filter hook forward priority mangle; policy accept;
        ct mark \$PO0_PUBLIC_FORWARD_MARK tcp flags syn tcp option maxseg size set ${MSS_VALUE} comment "po0-public-forward-mss"
    }
}
EOF
  fi

  if ! nft -c -f "${tmp}" >/dev/null 2>&1; then
    err "生成的 nft 配置语法检查失败：${tmp}"
    nft -c -f "${tmp}" >&2 || true
    return 1
  fi

  mv -f "${tmp}" "${NFT_CONF}"
}

delete_runtime_tables() {
  nft delete table ip "${NAT_TABLE}" 2>/dev/null || true
  nft delete table ip "${FILTER_TABLE}" 2>/dev/null || true
  nft delete table ip "${MANGLE_TABLE}" 2>/dev/null || true
}

apply_runtime_rules() {
  install_nftables_if_needed || return 1
  [[ -f "${NFT_CONF}" ]] || write_nft_conf || return 1
  nft -c -f "${NFT_CONF}" >/dev/null 2>&1 || {
    err "nft 配置预检失败：${NFT_CONF}"
    nft -c -f "${NFT_CONF}" >&2 || true
    return 1
  }
  delete_runtime_tables
  nft -f "${NFT_CONF}" || {
    err "加载 ${NFT_CONF} 失败。"
    return 1
  }
}

enable_ip_forward() {
  mkdir -p "$(dirname "${SYSCTL_CONF}")" 2>/dev/null || true
  touch "${SYSCTL_CONF}" 2>/dev/null || true
  if grep -qE '^[[:space:]]*net\.ipv4\.ip_forward[[:space:]]*=' "${SYSCTL_CONF}" 2>/dev/null; then
    sed -i -E 's|^[[:space:]]*net\.ipv4\.ip_forward[[:space:]]*=.*|net.ipv4.ip_forward=1|' "${SYSCTL_CONF}" 2>/dev/null || true
  else
    echo "net.ipv4.ip_forward=1" >> "${SYSCTL_CONF}" 2>/dev/null || true
  fi
  sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
  sysctl -p "${SYSCTL_CONF}" >/dev/null 2>&1 || true
}

write_systemd_service() {
  local nft_bin
  has_systemd || {
    warn "未检测到 systemd；已应用运行时规则，但不会自动创建开机加载服务。"
    return 0
  }
  nft_bin="$(command -v nft 2>/dev/null || printf '/usr/sbin/nft')"
  backup_managed_files
  cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=PO0 public nftables forwarder
After=network-online.target nftables.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=-${nft_bin} delete table ip ${NAT_TABLE}
ExecStartPre=-${nft_bin} delete table ip ${FILTER_TABLE}
ExecStartPre=-${nft_bin} delete table ip ${MANGLE_TABLE}
ExecStart=${nft_bin} -f ${NFT_CONF}
ExecStop=-${nft_bin} delete table ip ${NAT_TABLE}
ExecStop=-${nft_bin} delete table ip ${FILTER_TABLE}
ExecStop=-${nft_bin} delete table ip ${MANGLE_TABLE}

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}" >/dev/null 2>&1 || warn "无法 enable ${SERVICE_NAME}，请手动检查 systemd。"
}

install_or_apply() {
  print_title "安装 / 应用公网转发"
  install_nftables_if_needed || return 1
  ensure_layout || return 1
  load_rules
  backup_managed_files
  write_nft_conf || return 1
  enable_ip_forward
  apply_runtime_rules || return 1
  write_systemd_service || return 1
  success "已应用公网转发规则。"
  info "运行时只管理 nft 表：${NAT_TABLE}, ${FILTER_TABLE}, ${MANGLE_TABLE}"
  info "持久化配置：${NFT_CONF}"
  [[ "$(enabled_rule_count)" == "0" ]] && warn "当前没有启用的转发规则。"
}

print_rules() {
  local idx=1 rule
  load_rules
  if [[ "${#RULES[@]}" -eq 0 ]]; then
    info "当前没有规则。"
    return
  fi
  printf '%-4s %-8s %-8s %-10s %-22s %s\n' "序号" "状态" "协议" "入口端口" "目标" "名称"
  print_divider
  for rule in "${RULES[@]}"; do
    parse_rule "${rule}"
    printf '%-4s %-8s %-8s :%-9s %-22s %s\n' \
      "${idx}" \
      "$([[ "${RULE_ENABLED}" == "1" ]] && printf '启用' || printf '停用')" \
      "$(proto_to_label "${RULE_PROTO}")" \
      "${RULE_LPORT}" \
      "${RULE_DIP}:${RULE_DPORT}" \
      "${RULE_NAME}"
    idx=$((idx + 1))
  done
}

show_status() {
  print_title "状态 / 规则"
  ensure_layout || return 1
  printf '规则文件: %s\n' "${RULES_FILE}"
  printf 'nft 配置: %s\n' "${NFT_CONF}"
  printf 'systemd: %s\n' "$(service_enabled_label)"
  printf 'IPv4 转发: %s\n' "$(sysctl -n net.ipv4.ip_forward 2>/dev/null || printf '未知')"
  echo ""
  print_rules
}

add_rule() {
  local name proto lport dip dport default rule
  print_title "新增公网转发规则"
  install_nftables_if_needed || return 1
  ensure_layout || return 1
  load_rules

  read -r -p "规则名称 [默认: public-forward]: " name
  name="$(sanitize_name "${name:-public-forward}")"
  proto="$(prompt_protocol)" || return 1
  default="$(choose_candidate_port "${proto}" || true)"
  lport="$(prompt_listen_port "${proto}" "${default}")" || return 1
  rule_conflicts "${proto}" "${lport}" && {
    err "入口端口 ${lport}/${proto_to_label "${proto}"} 与现有规则冲突。"
    return 1
  }
  dip="$(prompt_destination_ip)" || return 1
  dport="$(prompt_destination_port "${lport}")" || return 1
  rule="${name}|${proto}|${lport}|${dip}|${dport}|1"

  echo ""
  echo "即将添加：$(proto_to_label "${proto}") :${lport} -> ${dip}:${dport}"
  warn "云厂商安全组 / VPS 面板防火墙仍需单独放行入口端口 ${lport}。"
  confirm_yes "确认添加并立即应用" || {
    info "已取消。"
    return 0
  }

  backup_managed_files
  RULES+=("${rule}")
  save_rules || return 1
  write_nft_conf || return 1
  enable_ip_forward
  apply_runtime_rules || return 1
  write_systemd_service || return 1
  success "规则已添加并应用。"
}

select_rule_index() {
  local choice="$1"
  [[ "${choice}" =~ ^[0-9]+$ ]] || return 1
  (( choice >= 1 && choice <= ${#RULES[@]} ))
}

delete_rule() {
  local choice target
  print_title "删除转发规则"
  install_nftables_if_needed || return 1
  ensure_layout || return 1
  load_rules
  [[ "${#RULES[@]}" -gt 0 ]] || {
    info "当前没有规则。"
    return 0
  }
  print_rules
  read -r -p "请输入要删除的序号 [0=取消]: " choice
  [[ "${choice}" == "0" || -z "${choice}" ]] && {
    info "已取消。"
    return 0
  }
  select_rule_index "${choice}" || {
    err "序号无效。"
    return 1
  }
  target="${RULES[$((choice - 1))]}"
  parse_rule "${target}"
  confirm_yes "确认删除 :${RULE_LPORT} -> ${RULE_DIP}:${RULE_DPORT}" || {
    info "已取消。"
    return 0
  }
  backup_managed_files
  unset 'RULES[$((choice - 1))]'
  RULES=("${RULES[@]}")
  save_rules || return 1
  write_nft_conf || return 1
  apply_runtime_rules || return 1
  write_systemd_service || return 1
  success "规则已删除并应用。"
}

toggle_rule() {
  local choice new_enabled
  print_title "启用 / 停用规则"
  install_nftables_if_needed || return 1
  ensure_layout || return 1
  load_rules
  [[ "${#RULES[@]}" -gt 0 ]] || {
    info "当前没有规则。"
    return 0
  }
  print_rules
  read -r -p "请输入要切换状态的序号 [0=取消]: " choice
  [[ "${choice}" == "0" || -z "${choice}" ]] && {
    info "已取消。"
    return 0
  }
  select_rule_index "${choice}" || {
    err "序号无效。"
    return 1
  }
  parse_rule "${RULES[$((choice - 1))]}"
  if [[ "${RULE_ENABLED}" == "1" ]]; then
    new_enabled="0"
  else
    ensure_listen_port_safe "${RULE_LPORT}" "${RULE_PROTO}" || return 1
    new_enabled="1"
  fi
  backup_managed_files
  RULES[$((choice - 1))]="${RULE_NAME}|${RULE_PROTO}|${RULE_LPORT}|${RULE_DIP}|${RULE_DPORT}|${new_enabled}"
  save_rules || return 1
  write_nft_conf || return 1
  apply_runtime_rules || return 1
  write_systemd_service || return 1
  success "规则状态已更新。"
}

diagnose_forward_policy() {
  has_cmd nft || return 0
  local drops
  drops="$(nft list ruleset 2>/dev/null | awk '
    /^[[:space:]]*chain[[:space:]]+/ { chain=$2; in_chain=1; text=$0; next }
    in_chain { text=text "\n" $0 }
    in_chain && /hook[[:space:]]+forward/ { has_forward=1 }
    in_chain && /^[[:space:]]*}/ {
      if (has_forward && text ~ /policy[[:space:]]+drop/) {
        print chain
      }
      in_chain=0
      has_forward=0
      text=""
    }
  ' || true)"
  if [[ -n "${drops}" ]]; then
    warn "检测到现有 forward hook 链使用 drop policy：${drops//$'\n'/, }"
    warn "本脚本已添加自己的 forward accept 链，但其它防火墙链仍可能继续丢弃流量。"
  fi
}

diagnose() {
  print_title "诊断"
  has_cmd nft && info "nftables: $(nft --version 2>/dev/null)" || warn "nftables: 未安装"
  printf 'IPv4 转发: %s\n' "$(sysctl -n net.ipv4.ip_forward 2>/dev/null || printf '未知')"
  [[ -f "${NFT_CONF}" ]] && info "配置文件存在：${NFT_CONF}" || warn "配置文件不存在：${NFT_CONF}"
  if has_cmd nft; then
    nft -c -f "${NFT_CONF}" >/dev/null 2>&1 && info "nft 配置语法：通过" || warn "nft 配置语法：未通过或配置不存在"
    nft list table ip "${NAT_TABLE}" >/dev/null 2>&1 && info "NAT 表已加载：${NAT_TABLE}" || warn "NAT 表未加载"
    nft list table ip "${FILTER_TABLE}" >/dev/null 2>&1 && info "forward 表已加载：${FILTER_TABLE}" || warn "forward 表未加载"
    diagnose_forward_policy
  fi
  echo ""
  print_rules
}

uninstall_managed_runtime() {
  print_title "卸载本脚本管理的转发表"
  warn "只会删除 ${APP_NAME} 自己的 nft 表、systemd 服务和配置文件，不会修改其它服务。"
  confirm_yes "确认卸载" || {
    info "已取消。"
    return 0
  }
  backup_managed_files
  if has_systemd; then
    systemctl disable --now "${SERVICE_NAME}" >/dev/null 2>&1 || true
    rm -f "${SERVICE_FILE}"
    systemctl daemon-reload
  fi
  if has_cmd nft; then
    delete_runtime_tables
  fi
  rm -f "${NFT_CONF}"
  success "已卸载本脚本管理的运行时规则和持久化服务。规则列表保留在 ${RULES_FILE}。"
}

main_menu() {
  local choice
  while true; do
    print_title "PO0 公网 nftables 转发"
    printf '只管理: %s / %s / %s\n' "${NAT_TABLE}" "${FILTER_TABLE}" "${MANGLE_TABLE}"
    printf '不会改写: /etc/nftables.conf\n'
    echo ""
    echo "  1) 安装 / 应用当前规则"
    echo "  2) 查看状态与规则"
    echo "  3) 新增公网转发规则"
    echo "  4) 删除转发规则"
    echo "  5) 启用 / 停用规则"
    echo "  6) 诊断 / 自检"
    echo "  7) 卸载本脚本管理的规则"
    echo "  0) 退出"
    print_divider
    read -r -p "请选择操作 [0-7]: " choice
    case "${choice}" in
      1) install_or_apply; pause_before_return ;;
      2) show_status; pause_before_return ;;
      3) add_rule; pause_before_return ;;
      4) delete_rule; pause_before_return ;;
      5) toggle_rule; pause_before_return ;;
      6) diagnose; pause_before_return ;;
      7) uninstall_managed_runtime; pause_before_return ;;
      0) exit 0 ;;
      *) err "无效选择。" ;;
    esac
  done
}

main() {
  setup_colors
  check_root
  main_menu
}

main "$@"
