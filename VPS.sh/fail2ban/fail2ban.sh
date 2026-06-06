#!/usr/bin/env bash
set -euo pipefail

CONF_DIR="/etc/fail2ban/jail.d"
LOCAL_CONF="${CONF_DIR}/99-local-hardening.conf"
BACKUP_DIR="/etc/fail2ban/backups"

DEFAULT_BANTIME="1w"
DEFAULT_FINDTIME="10m"
DEFAULT_MAXRETRY="3"
DEFAULT_NGINX_LOGPATH="/var/log/nginx/error.log"

info() { printf '\033[32m[信息]\033[0m %s\n' "$1" >&2; }
warn() { printf '\033[33m[警告]\033[0m %s\n' "$1" >&2; }
err() { printf '\033[31m[错误]\033[0m %s\n' "$1" >&2; }

check_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "请使用 root 运行：sudo bash $0"
    exit 1
  fi
}

require_fail2ban() {
  if ! command -v fail2ban-client >/dev/null 2>&1; then
    err "Fail2ban 尚未安装，请先运行：sudo bash $0 install"
    return 1
  fi
}

confirm_yes() {
  local ans
  read -r -p "$1 [y/N]: " ans
  [[ "${ans}" =~ ^[Yy]$ ]]
}

validate_port() {
  local port="$1"
  [[ "${port}" =~ ^[0-9]+$ ]] || return 1
  [[ ! "${port}" =~ ^0[0-9] ]] || return 1
  (( port >= 1 && port <= 65535 ))
}

validate_positive_int() {
  local value="$1"
  [[ "${value}" =~ ^[1-9][0-9]*$ ]]
}

validate_absolute_path() {
  local value="$1"
  [[ "${value}" == /* ]]
}

validate_cidr_suffix() {
  local prefix="$1"
  local max="$2"
  [[ "${prefix}" =~ ^[0-9]+$ ]] || return 1
  (( prefix >= 0 && prefix <= max ))
}

validate_ipv4() {
  local ip="$1"
  local IFS='.'
  local octet
  local -a octets=()

  [[ "${ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  read -r -a octets <<< "${ip}"
  for octet in "${octets[@]}"; do
    [[ ! "${octet}" =~ ^0[0-9]+$ ]] || return 1
    (( octet >= 0 && octet <= 255 )) || return 1
  done
}

validate_ipv4_cidr() {
  local token="$1"
  local ip="${token}"
  local prefix=""

  if [[ "${token}" == */* ]]; then
    ip="${token%/*}"
    prefix="${token##*/}"
  fi

  validate_ipv4 "${ip}" || return 1
  [[ -z "${prefix}" ]] || validate_cidr_suffix "${prefix}" 32
}

validate_ipv6_cidr() {
  local token="$1"
  local ip="${token}"
  local prefix=""

  if [[ "${token}" == */* ]]; then
    ip="${token%/*}"
    prefix="${token##*/}"
  fi

  [[ "${ip}" == *:* ]] || return 1
  [[ "${ip}" =~ ^[0-9A-Fa-f:]+$ ]] || return 1
  [[ -z "${prefix}" ]] || validate_cidr_suffix "${prefix}" 128
}

validate_ip_or_cidr() {
  local token="$1"
  validate_ipv4_cidr "${token}" || validate_ipv6_cidr "${token}"
}

validate_ip_list() {
  local value="$1"
  local token

  [[ -z "${value}" ]] && return 0
  for token in ${value}; do
    validate_ip_or_cidr "${token}" || return 1
  done
}

validate_duration() {
  local value="$1"
  [[ "${value}" =~ ^[1-9][0-9]*[smhdw]$ ]]
}

prompt_validated() {
  local prompt="$1"
  local default="$2"
  local validator="$3"
  local error_msg="$4"
  local value

  while true; do
    value="$(prompt_with_default "${prompt}" "${default}")"
    if "${validator}" "${value}"; then
      printf '%s\n' "${value}"
      return 0
    fi
    err "${error_msg}"
  done
}

detect_pkg_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    echo apt
  elif command -v dnf >/dev/null 2>&1; then
    echo dnf
  elif command -v yum >/dev/null 2>&1; then
    echo yum
  elif command -v pacman >/dev/null 2>&1; then
    echo pacman
  else
    echo unknown
  fi
}

has_nginx_http_auth_filter() {
  local path
  for path in \
    /etc/fail2ban/filter.d/nginx-http-auth.conf \
    /usr/local/etc/fail2ban/filter.d/nginx-http-auth.conf; do
    [[ -f "${path}" ]] && return 0
  done
  return 1
}

detect_nginx_logpath() {
  local path=""

  if command -v nginx >/dev/null 2>&1; then
    path="$(
      nginx -T 2>/dev/null | awk '
        $1 == "error_log" {
          value = $2
          sub(/;$/, "", value)
          if (value != "stderr" && value !~ /^syslog:/) {
            print value
            exit
          }
        }
      ' || true
    )"
  fi

  if [[ -n "${path}" ]]; then
    printf '%s\n' "${path}"
    return 0
  fi

  for path in \
    /var/log/nginx/error.log \
    /var/log/openresty/error.log \
    /usr/local/nginx/logs/error.log \
    /www/wwwlogs/nginx_error.log; do
    [[ -f "${path}" ]] && printf '%s\n' "${path}" && return 0
  done

  return 1
}

install_fail2ban() {
  if command -v fail2ban-client >/dev/null 2>&1; then
    info "Fail2ban 已安装。"
    return 0
  fi

  case "$(detect_pkg_manager)" in
    apt)
      apt-get update
      apt-get install -y fail2ban
      ;;
    dnf)
      dnf install -y epel-release || true
      dnf install -y fail2ban
      ;;
    yum)
      yum install -y epel-release || true
      yum install -y fail2ban
      ;;
    pacman)
      pacman -Sy --noconfirm fail2ban
      ;;
    *)
      err "无法识别包管理器，请先手动安装 fail2ban。"
      return 1
      ;;
  esac
}

detect_ssh_port() {
  local port=""

  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    port="$(printf '%s\n' "${SSH_CONNECTION}" | awk '{print $4}')"
  fi

  if [[ -z "${port}" ]] && command -v sshd >/dev/null 2>&1; then
    port="$(sshd -T 2>/dev/null | awk '$1 == "port" {print $2; exit}' || true)"
  fi

  if [[ -z "${port}" ]] && [[ -f /etc/ssh/sshd_config ]]; then
    port="$(awk 'tolower($1) == "port" {print $2; exit}' /etc/ssh/sshd_config)"
  fi

  printf '%s\n' "${port:-22}"
}

detect_ssh_backend_lines() {
  if [[ -f /var/log/auth.log ]]; then
    printf 'logpath = /var/log/auth.log\n'
  elif [[ -f /var/log/secure ]]; then
    printf 'logpath = /var/log/secure\n'
  elif command -v journalctl >/dev/null 2>&1; then
    printf 'backend = systemd\n'
  else
    printf 'logpath = /var/log/auth.log\n'
  fi
}

current_client_ip() {
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    printf '%s\n' "${SSH_CONNECTION}" | awk '{print $1}'
  fi
}

latest_backup_file() {
  local base
  local -a matches=()

  base="$(basename "${LOCAL_CONF}")"
  shopt -s nullglob
  matches=(
    "${BACKUP_DIR}/${base}."[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9]
  )
  shopt -u nullglob

  (( ${#matches[@]} > 0 )) || return 1
  printf '%s\n' "${matches[@]}" | tail -n 1
}

prompt_ip_list() {
  local prompt="$1"
  local input

  while true; do
    input="$(prompt_with_default "${prompt}" "")"
    if validate_ip_list "${input}"; then
      printf '%s\n' "${input}"
      return 0
    fi
    err "白名单格式无效。请输入 IPv4/IPv6 或 CIDR，多个值用空格分隔。"
  done
}

backup_current_config() {
  local backup_path=""

  mkdir -p "${BACKUP_DIR}"
  if [[ -f "${LOCAL_CONF}" ]]; then
    backup_path="${BACKUP_DIR}/$(basename "${LOCAL_CONF}").$(date '+%Y%m%d_%H%M%S')"
    cp -a "${LOCAL_CONF}" "${backup_path}"
    printf '%s\n' "${backup_path}"
  fi
}

prompt_with_default() {
  local prompt="$1"
  local default="$2"
  local input
  read -r -p "${prompt} [${default}]: " input
  printf '%s\n' "${input:-${default}}"
}

print_install_hint() {
  cat >&2 <<'EOF'

接下来会生成 Fail2ban 推荐配置。
不确定怎么填时，直接回车使用方括号里的默认值即可。
推荐值说明：
  - SSH jail：开启
  - 封禁时长：1w（一周）
  - 检测窗口：10m
  - 失败次数：3
  - 白名单：自动加入当前 SSH 客户端 IP

EOF
}

print_recommended_hint() {
  cat >&2 <<'EOF'

接下来会按推荐值自动生成 Fail2ban 配置。
这个模式会自动探测 SSH 端口、当前 SSH 客户端 IP、SSH 日志来源，
如果检测到 nginx 错误日志，也会自动启用 nginx-http-auth 防护。
你只需要在最后确认一次即可。

EOF
}

build_recommended_ignoreip() {
  local client_ip
  client_ip="$(current_client_ip || true)"

  if [[ -n "${client_ip}" ]] && ! validate_ip_or_cidr "${client_ip}"; then
    warn "检测到的 SSH 客户端地址格式异常：${client_ip}，推荐模式不会自动写入白名单。"
    client_ip=""
  fi

  if [[ -n "${client_ip}" ]]; then
    info "检测到当前 SSH 客户端 IP：${client_ip}，推荐模式会自动加入白名单。"
    printf '127.0.0.1/8 ::1 %s\n' "${client_ip}" | xargs
  else
    warn "未检测到当前 SSH 客户端 IP。推荐模式只会保留本机白名单。"
    printf '127.0.0.1/8 ::1\n'
  fi
}

build_ignoreip() {
  local client_ip extra
  client_ip="$(current_client_ip || true)"

  if [[ -n "${client_ip}" ]] && ! validate_ip_or_cidr "${client_ip}"; then
    warn "检测到的 SSH 客户端地址格式异常：${client_ip}，将不会自动写入白名单。"
    client_ip=""
  fi

  if [[ -n "${client_ip}" ]]; then
    info "检测到当前 SSH 客户端 IP：${client_ip}，会自动加入白名单，避免误封。"
    extra="$(prompt_ip_list "还要额外加入哪些白名单 IP/CIDR？多个用空格分隔，留空则不加")"
    printf '127.0.0.1/8 ::1 %s %s\n' "${client_ip}" "${extra}" | xargs
  else
    warn "未检测到当前 SSH 客户端 IP。"
    extra="$(prompt_ip_list "请输入管理端白名单 IP/CIDR，多个用空格分隔，留空只保留本机")"
    if [[ -z "${extra}" ]]; then
      warn "没有额外管理 IP 白名单。远程服务器上建议至少填入你的固定管理 IP，降低误封风险。"
      if ! confirm_yes "确认只保留本机白名单"; then
        build_ignoreip
        return 0
      fi
    fi
    printf '127.0.0.1/8 ::1 %s\n' "${extra}" | xargs
  fi
}

write_config() {
  local ssh_port ignoreip bantime findtime maxretry ssh_backend nginx_logpath
  print_install_hint
  ssh_port="$(prompt_validated "SSH 端口" "$(detect_ssh_port)" validate_port "端口必须是 1-65535 的数字。")"
  bantime="$(prompt_validated "封禁时长，推荐 ${DEFAULT_BANTIME}，例如 1d/1w/12h" "${DEFAULT_BANTIME}" validate_duration "时间格式必须类似 10m、1h、1d、1w。")"
  findtime="$(prompt_validated "检测窗口，推荐 ${DEFAULT_FINDTIME}，例如 10m/1h" "${DEFAULT_FINDTIME}" validate_duration "时间格式必须类似 10m、1h、1d、1w。")"
  maxretry="$(prompt_validated "多少次失败后封禁，推荐 ${DEFAULT_MAXRETRY}" "${DEFAULT_MAXRETRY}" validate_positive_int "失败次数必须是正整数。")"
  ignoreip="$(build_ignoreip)"
  ssh_backend="$(detect_ssh_backend_lines)"
  nginx_logpath="$(choose_nginx_logpath_custom || true)"

  print_config_summary "自定义模式" "${ssh_port}" "${ignoreip}" "${bantime}" "${findtime}" "${maxretry}" "${nginx_logpath}"

  if ! confirm_yes "确认写入并重启 Fail2ban"; then
    warn "已取消，没有写入配置。"
    return 1
  fi

  persist_local_config "${ssh_port}" "${ignoreip}" "${bantime}" "${findtime}" "${maxretry}" "${ssh_backend}" "${nginx_logpath}"
}

build_nginx_block() {
  local maxretry="$1"
  local nginx_logpath="$2"
  [[ -n "${nginx_logpath}" ]] || return 0
  cat <<EOF
[nginx-http-auth]
enabled = true
port = http,https
filter = nginx-http-auth
logpath = ${nginx_logpath}
maxretry = ${maxretry}
EOF
}

print_config_summary() {
  local mode_label="$1"
  local ssh_port="$2"
  local ignoreip="$3"
  local bantime="$4"
  local findtime="$5"
  local maxretry="$6"
  local nginx_logpath="$7"

  cat >&2 <<EOF

即将按${mode_label}写入以下配置：
  SSH jail        : 启用
  SSH 端口        : ${ssh_port}
  白名单 ignoreip : ${ignoreip}
  封禁时长        : ${bantime}
  检测窗口        : ${findtime}
  失败次数        : ${maxretry}
  nginx 防护      : $([[ -n "${nginx_logpath}" ]] && echo "启用 (${nginx_logpath})" || echo "不启用")
  配置文件        : ${LOCAL_CONF}

EOF
}

persist_local_config() {
  local ssh_port="$1"
  local ignoreip="$2"
  local bantime="$3"
  local findtime="$4"
  local maxretry="$5"
  local ssh_backend="$6"
  local nginx_logpath="$7"
  local backup_path
  local nginx_block=""

  nginx_block="$(build_nginx_block "${maxretry}" "${nginx_logpath}")"
  mkdir -p "${CONF_DIR}" "${BACKUP_DIR}"
  backup_path="$(backup_current_config || true)"
  if [[ -n "${backup_path}" ]]; then
    info "已备份原配置：${backup_path}"
  fi

  cat > "${LOCAL_CONF}" <<EOF
# Managed by fail2ban.sh. Edit this file directly only if you know what you are changing.
[DEFAULT]
ignoreip = ${ignoreip}
bantime = ${bantime}
findtime = ${findtime}
maxretry = ${maxretry}

[sshd]
enabled = true
port = ${ssh_port}
filter = sshd
${ssh_backend}
maxretry = ${maxretry}
${nginx_block}
EOF

  info "已写入配置：${LOCAL_CONF}"
}

prompt_nginx_logpath() {
  prompt_validated \
    "nginx 错误日志路径" \
    "${DEFAULT_NGINX_LOGPATH}" \
    validate_absolute_path \
    "路径必须是以 / 开头的绝对路径。"
}

choose_nginx_logpath_custom() {
  local detected_logpath=""

  if ! has_nginx_http_auth_filter; then
    warn "当前系统未找到 Fail2ban 的 nginx-http-auth 过滤器，将不会启用 nginx 防护。"
    return 0
  fi

  detected_logpath="$(detect_nginx_logpath || true)"
  if [[ -n "${detected_logpath}" ]]; then
    if confirm_yes "检测到 nginx 错误日志 ${detected_logpath}，是否启用 nginx-http-auth 防护"; then
      printf '%s\n' "${detected_logpath}"
    fi
    return 0
  fi

  if confirm_yes "没有自动检测到 nginx 错误日志。是否手动写入 nginx-http-auth 防护"; then
    prompt_nginx_logpath
  fi
}

write_recommended_config() {
  local ssh_port ignoreip bantime findtime maxretry ssh_backend nginx_logpath
  print_recommended_hint
  ssh_port="$(detect_ssh_port)"
  ignoreip="$(build_recommended_ignoreip)"
  bantime="${DEFAULT_BANTIME}"
  findtime="${DEFAULT_FINDTIME}"
  maxretry="${DEFAULT_MAXRETRY}"
  ssh_backend="$(detect_ssh_backend_lines)"
  nginx_logpath=""

  if has_nginx_http_auth_filter; then
    nginx_logpath="$(detect_nginx_logpath || true)"
    if [[ -n "${nginx_logpath}" ]]; then
      info "检测到 nginx 错误日志：${nginx_logpath}，推荐模式会自动启用 nginx-http-auth 防护。"
    fi
  elif detect_nginx_logpath >/dev/null 2>&1; then
    warn "检测到 nginx 痕迹，但当前系统未找到 Fail2ban 的 nginx-http-auth 过滤器，推荐模式不会启用 nginx 防护。"
  fi

  print_config_summary "推荐模式" "${ssh_port}" "${ignoreip}" "${bantime}" "${findtime}" "${maxretry}" "${nginx_logpath}"
  if ! confirm_yes "确认按推荐值写入并重启 Fail2ban"; then
    warn "已取消，没有写入配置。"
    return 1
  fi

  persist_local_config "${ssh_port}" "${ignoreip}" "${bantime}" "${findtime}" "${maxretry}" "${ssh_backend}" "${nginx_logpath}"
}

enable_service() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable fail2ban
    fail2ban-client -t
    systemctl restart fail2ban
    systemctl --no-pager --full status fail2ban || true
  else
    service fail2ban restart
    fail2ban-client -t
  fi
}

install_and_configure() {
  install_fail2ban
  write_config || return 0
  warn "不要关闭当前 SSH 窗口。重启后请新开一个窗口测试 SSH 登录。"
  enable_service
  printf '\n'
  show_status || true
  info "完成。建议保留当前 SSH 窗口，再新开一个窗口测试登录。"
}

default_install_and_configure() {
  install_fail2ban
  write_recommended_config || return 0
  warn "不要关闭当前 SSH 窗口。重启后请新开一个窗口测试 SSH 登录。"
  enable_service
  printf '\n'
  show_status || true
  info "完成。推荐模式配置已应用。"
}

show_status() {
  require_fail2ban || return 0
  fail2ban-client status
  if fail2ban-client status sshd >/dev/null 2>&1; then
    printf '\n'
    fail2ban-client status sshd
  fi
}

unban_ip() {
  local jail ip
  require_fail2ban || return 0
  jail="$(prompt_with_default "要解封的 jail" "sshd")"
  read -r -p "要解封的 IP: " ip
  if [[ -z "${ip}" ]]; then
    err "IP 不能为空。"
    return 1
  fi
  fail2ban-client set "${jail}" unbanip "${ip}"
}

show_logs() {
  require_fail2ban || return 0
  if command -v journalctl >/dev/null 2>&1; then
    journalctl -u fail2ban -n 80 --no-pager
  elif [[ -f /var/log/fail2ban.log ]]; then
    tail -n 80 /var/log/fail2ban.log
  else
    warn "没有找到可用的 Fail2ban 日志。"
  fi
}

restart_fail2ban() {
  require_fail2ban || return 0
  fail2ban-client -t
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart fail2ban
  else
    service fail2ban restart
  fi
  info "Fail2ban 已重启。"
  show_status || true
}

restore_latest_backup() {
  local latest
  require_fail2ban || return 0

  latest="$(latest_backup_file || true)"
  if [[ -z "${latest}" ]]; then
    warn "没有找到可恢复的备份。"
    return 0
  fi

  cat >&2 <<EOF

即将恢复最近的备份：
  ${latest}
目标配置：
  ${LOCAL_CONF}

EOF

  if ! confirm_yes "确认恢复并重启 Fail2ban"; then
    warn "已取消，没有恢复配置。"
    return 0
  fi

  cp -a "${LOCAL_CONF}" "${BACKUP_DIR}/$(basename "${LOCAL_CONF}").before-restore.$(date '+%Y%m%d_%H%M%S')" 2>/dev/null || true
  cp -a "${latest}" "${LOCAL_CONF}"
  info "已从备份恢复：${latest}"
  restart_fail2ban
}

advanced_menu() {
  while true; do
    cat <<'EOF'

Fail2ban 高级模式
1) 自定义推荐配置（保留默认值，可逐项修改）
2) 查看状态
3) 解封 IP
4) 查看最近日志
5) 重启 Fail2ban
6) 恢复上一次配置备份
0) 退出
EOF
    read -r -p "请选择: " choice
    case "${choice}" in
      1) install_and_configure || true ;;
      2) show_status || true ;;
      3) unban_ip || true ;;
      4) show_logs || true ;;
      5) restart_fail2ban || true ;;
      6) restore_latest_backup || true ;;
      0) exit 0 ;;
      *) warn "无效选择。" ;;
    esac
  done
}

mode_menu() {
  while true; do
    cat <<'EOF'

Fail2ban 模式选择
1) 默认模式（一键推荐配置，自动探测，只在最后确认）
2) 高级模式（逐项自定义，含状态/解封/回滚等维护功能）
0) 退出
EOF
    read -r -p "请选择: " choice
    case "${choice}" in
      1) default_install_and_configure || true ;;
      2) advanced_menu ;;
      0) exit 0 ;;
      *) warn "无效选择。" ;;
    esac
  done
}

main() {
  check_root
  case "${1:-}" in
    install) install_and_configure ;;
    recommended|default) default_install_and_configure ;;
    advanced) advanced_menu ;;
    status) show_status ;;
    unban) unban_ip ;;
    logs) show_logs ;;
    restart) restart_fail2ban ;;
    rollback|restore) restore_latest_backup ;;
    ""|menu) mode_menu ;;
    *)
      cat <<EOF
用法:
  sudo bash $0             # 打开模式菜单
  sudo bash $0 default     # 默认模式：自动探测，一键推荐配置
  sudo bash $0 advanced    # 高级模式：进入维护/自定义菜单
  sudo bash $0 install     # 高级模式下直接进入自定义配置
  sudo bash $0 status      # 查看状态
  sudo bash $0 unban       # 解封 IP
  sudo bash $0 logs        # 查看日志
  sudo bash $0 restart     # 测试配置并重启
  sudo bash $0 rollback    # 恢复上一次配置备份
EOF
      ;;
  esac
}

main "$@"
