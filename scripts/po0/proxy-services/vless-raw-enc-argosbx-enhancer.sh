#!/usr/bin/env bash
set -uo pipefail

# vless-raw-enc-argosbx-enhancer.sh
# Manages an independently deployed or argosbx-reused Xray sidecar.

APP_ROOT="/opt/agsbx-extra"
BIN_DIR="${APP_ROOT}/bin"
LOG_DIR="${APP_ROOT}/logs"
BACKUP_DIR="${APP_ROOT}/backups"

FEATURE_ID="vless-raw-enc"
FEATURE_NAME="Xray 多协议 Sidecar"
VLESS_NAME="VLESS RAW ENC"
SS_NAME="Shadowsocks 2022"
FEATURE_DIR="${APP_ROOT}/${FEATURE_ID}"
ENV_FILE="${FEATURE_DIR}/service.env"
CONFIG_FILE="${FEATURE_DIR}/config.json"
SHARE_FILE="${FEATURE_DIR}/share.txt"
PID_FILE="${FEATURE_DIR}/xray.pid"
XRAY_BIN="${BIN_DIR}/xray"

SERVICE_NAME="agsbx-extra-vless-raw-enc"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
RECOMMENDED_PORT_MIN="16384"
RECOMMENDED_PORT_MAX="24575"
RECOMMENDED_PORT_RANDOM_TRIES="200"
DEFAULT_LISTEN="::"
DEFAULT_SS_METHOD="2022-blake3-aes-128-gcm"
DEFAULT_SS_NODE_NAME="SS2022-Xray"
TEST_URL="https://www.cloudflare.com/cdn-cgi/trace"

ARGOSBX_DIR=""
ARGOSBX_XRAY=""
ARGOSBX_SINGBOX=""
ARGOSBX_UUID=""
ARGOSBX_DETECTED="0"
HAS_SYSTEMD="0"

PORT=""
UUID=""
DECRYPTION=""
ENCRYPTION=""
LISTEN=""
NODE_NAME=""
FLOW=""
XRAY_SOURCE=""
CREATED_AT=""
UPDATED_AT=""

SS_ENABLED="0"
SS_PORT=""
SS_METHOD=""
SS_PASSWORD=""
SS_LISTEN=""
SS_NODE_NAME=""
SS_PUBLIC_HOST=""
SS_PUBLIC_PORT=""
SS_ALLOW_SOURCE=""

C_RESET=""
C_BOLD=""
C_DIM=""
C_GREEN=""
C_YELLOW=""
C_RED=""
C_CYAN=""

setup_colors() {
  if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
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

check_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "请使用 root 运行此脚本：sudo bash $0"
    exit 1
  fi
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

detect_init_system() {
  if command_exists systemctl && pidof systemd >/dev/null 2>&1; then
    HAS_SYSTEMD="1"
  else
    HAS_SYSTEMD="0"
  fi
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
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
    read -r -p "${prompt} [当前: ${default}]: " value
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

validate_uuid() {
  local value="$1"
  [[ "${value}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

validate_enc_value() {
  local value="$1"
  [[ -n "${value}" ]] || return 1
  [[ "${value}" != "none" ]] || return 1
  [[ "${value}" != *[[:space:]]* ]] || return 1
  [[ "${value}" == mlkem768x25519plus.* || "${value}" == *.* ]]
}

validate_no_whitespace() {
  local value="$1"
  [[ "${value}" != *[[:space:]]* ]]
}

validate_json_safe_string() {
  local value="$1"
  [[ "${value}" != *\"* && "${value}" != *\\* ]]
}

ss_supported_method() {
  case "$1" in
    2022-blake3-aes-128-gcm|2022-blake3-aes-256-gcm|2022-blake3-chacha20-poly1305|aes-128-gcm|aes-256-gcm|chacha20-poly1305|chacha20-ietf-poly1305|xchacha20-poly1305|xchacha20-ietf-poly1305)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

ss_method_key_len() {
  case "$1" in
    2022-blake3-aes-128-gcm|aes-128-gcm) echo 16 ;;
    2022-blake3-aes-256-gcm|2022-blake3-chacha20-poly1305|aes-256-gcm|chacha20-poly1305|chacha20-ietf-poly1305|xchacha20-poly1305|xchacha20-ietf-poly1305) echo 32 ;;
    *) echo 32 ;;
  esac
}

normalize_flow() {
  local value="${1:-none}"
  case "${value}" in
    ""|none|NONE|off|OFF|no|NO|0) printf 'none' ;;
    vision|VISION|xtls-rprx-vision) printf 'xtls-rprx-vision' ;;
    *) printf 'none' ;;
  esac
}

flow_label() {
  local value
  value="$(normalize_flow "${1:-none}")"
  if [[ "${value}" == "xtls-rprx-vision" ]]; then
    printf 'xtls-rprx-vision（写入 flow）'
  else
    printf 'none（不写 flow）'
  fi
}

shell_quote() {
  local value="$1"
  printf "'"
  printf '%s' "${value}" | sed "s/'/'\\\\''/g"
  printf "'"
}

now_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

safe_hostname() {
  local h
  h="$(hostname 2>/dev/null || echo vps)"
  h="$(printf '%s' "${h}" | tr -cd 'A-Za-z0-9._-')"
  printf '%s' "${h:-vps}"
}

detect_argosbx() {
  local candidate marker_count
  ARGOSBX_DIR=""
  ARGOSBX_XRAY=""
  ARGOSBX_SINGBOX=""
  ARGOSBX_UUID=""
  ARGOSBX_DETECTED="0"

  local -a candidates=()
  [[ -n "${ARGOSBX_HOME:-}" ]] && candidates+=("${ARGOSBX_HOME}")
  candidates+=("/root/agsbx" "${HOME:-/root}/agsbx")

  for candidate in /home/*/agsbx; do
    [[ -d "${candidate}" ]] && candidates+=("${candidate}")
  done

  for candidate in "${candidates[@]}"; do
    [[ -d "${candidate}" ]] || continue
    marker_count=0
    [[ -f "${candidate}/xray" ]] && marker_count=$((marker_count + 1))
    [[ -f "${candidate}/sing-box" ]] && marker_count=$((marker_count + 1))
    [[ -f "${candidate}/xr.json" ]] && marker_count=$((marker_count + 1))
    [[ -f "${candidate}/sb.json" ]] && marker_count=$((marker_count + 1))
    [[ -f "${candidate}/uuid" ]] && marker_count=$((marker_count + 1))
    [[ -f "${candidate}/jhsub.txt" ]] && marker_count=$((marker_count + 1))
    [[ -f "${candidate}/server_ip.log" ]] && marker_count=$((marker_count + 1))

    if (( marker_count > 0 )); then
      ARGOSBX_DIR="${candidate}"
      [[ -f "${candidate}/xray" ]] && ARGOSBX_XRAY="${candidate}/xray"
      [[ -f "${candidate}/sing-box" ]] && ARGOSBX_SINGBOX="${candidate}/sing-box"
      ARGOSBX_DETECTED="1"
      if [[ -f "${candidate}/uuid" ]]; then
        ARGOSBX_UUID="$(trim "$(cat "${candidate}/uuid" 2>/dev/null || true)")"
      fi
      return 0
    fi
  done

  return 1
}

load_state() {
  PORT=""
  UUID=""
  DECRYPTION=""
  ENCRYPTION=""
  LISTEN="${DEFAULT_LISTEN}"
  NODE_NAME=""
  FLOW="none"
  XRAY_SOURCE=""
  CREATED_AT=""
  UPDATED_AT=""
  SS_ENABLED="0"
  SS_PORT=""
  SS_METHOD="${DEFAULT_SS_METHOD}"
  SS_PASSWORD=""
  SS_LISTEN="${DEFAULT_LISTEN}"
  SS_NODE_NAME=""
  SS_PUBLIC_HOST=""
  SS_PUBLIC_PORT=""
  SS_ALLOW_SOURCE=""

  if [[ -f "${ENV_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${ENV_FILE}"
  fi
  FLOW="$(normalize_flow "${FLOW:-none}")"
  [[ "${SS_ENABLED:-0}" == "1" ]] || SS_ENABLED="0"
  SS_METHOD="${SS_METHOD:-${DEFAULT_SS_METHOD}}"
  SS_LISTEN="${SS_LISTEN:-${DEFAULT_LISTEN}}"
}

write_state() {
  [[ -n "${CREATED_AT}" ]] || CREATED_AT="$(now_utc)"
  UPDATED_AT="$(now_utc)"

  mkdir -p "${FEATURE_DIR}"
  {
    echo "# Generated by vless-raw-enc-argosbx-enhancer.sh. Do not edit while the manager is running."
    printf 'FEATURE_ID=%s\n' "$(shell_quote "${FEATURE_ID}")"
    printf 'PORT=%s\n' "$(shell_quote "${PORT}")"
    printf 'UUID=%s\n' "$(shell_quote "${UUID}")"
    printf 'DECRYPTION=%s\n' "$(shell_quote "${DECRYPTION}")"
    printf 'ENCRYPTION=%s\n' "$(shell_quote "${ENCRYPTION}")"
    printf 'LISTEN=%s\n' "$(shell_quote "${LISTEN:-${DEFAULT_LISTEN}}")"
    printf 'NODE_NAME=%s\n' "$(shell_quote "${NODE_NAME}")"
    printf 'FLOW=%s\n' "$(shell_quote "$(normalize_flow "${FLOW:-none}")")"
    printf 'XRAY_SOURCE=%s\n' "$(shell_quote "${XRAY_SOURCE}")"
    printf 'CREATED_AT=%s\n' "$(shell_quote "${CREATED_AT}")"
    printf 'UPDATED_AT=%s\n' "$(shell_quote "${UPDATED_AT}")"
    printf 'SS_ENABLED=%s\n' "$(shell_quote "${SS_ENABLED:-0}")"
    printf 'SS_PORT=%s\n' "$(shell_quote "${SS_PORT}")"
    printf 'SS_METHOD=%s\n' "$(shell_quote "${SS_METHOD:-${DEFAULT_SS_METHOD}}")"
    printf 'SS_PASSWORD=%s\n' "$(shell_quote "${SS_PASSWORD}")"
    printf 'SS_LISTEN=%s\n' "$(shell_quote "${SS_LISTEN:-${DEFAULT_LISTEN}}")"
    printf 'SS_NODE_NAME=%s\n' "$(shell_quote "${SS_NODE_NAME}")"
    printf 'SS_PUBLIC_HOST=%s\n' "$(shell_quote "${SS_PUBLIC_HOST}")"
    printf 'SS_PUBLIC_PORT=%s\n' "$(shell_quote "${SS_PUBLIC_PORT}")"
    printf 'SS_ALLOW_SOURCE=%s\n' "$(shell_quote "${SS_ALLOW_SOURCE}")"
  } > "${ENV_FILE}"
  chmod 600 "${ENV_FILE}" 2>/dev/null || true
}

ensure_dirs() {
  mkdir -p "${APP_ROOT}" "${BIN_DIR}" "${LOG_DIR}" "${BACKUP_DIR}" "${FEATURE_DIR}"
  chmod 700 "${FEATURE_DIR}" 2>/dev/null || true
}

service_mode_label() {
  if [[ "${HAS_SYSTEMD}" == "1" ]]; then
    printf 'systemd'
  else
    printf 'pid+cron'
  fi
}

argosbx_status_label() {
  if [[ "${ARGOSBX_DETECTED}" == "1" ]]; then
    printf '已检测到: %s (Xray: %s, Sing-box: %s)' \
      "${ARGOSBX_DIR}" \
      "$([[ -n "${ARGOSBX_XRAY}" ]] && echo "有" || echo "无")" \
      "$([[ -n "${ARGOSBX_SINGBOX}" ]] && echo "有" || echo "无")"
  else
    printf '未检测到'
  fi
}

show_preflight() {
  local os="unknown" free_kb="" human="未知" xray_version=""
  detect_argosbx >/dev/null 2>&1 || true
  detect_init_system
  load_state

  if [[ -f /etc/os-release ]]; then
    os="$(awk -F= '$1=="PRETTY_NAME" {gsub(/"/, "", $2); print $2; exit}' /etc/os-release)"
    [[ -n "${os}" ]] || os="$(awk -F= '$1=="ID" {print $2; exit}' /etc/os-release)"
  fi
  free_kb="$(df -Pk / 2>/dev/null | awk 'NR==2 {print $4}' || true)"
  if [[ "${free_kb}" =~ ^[0-9]+$ ]]; then
    human="$(awk -v kb="${free_kb}" 'BEGIN { if (kb >= 1048576) printf "%.1fG", kb / 1048576; else printf "%.0fM", kb / 1024 }')"
  fi
  if [[ -x "${XRAY_BIN}" ]]; then
    xray_version="$("${XRAY_BIN}" version 2>/dev/null | head -n 1 || true)"
  fi

  print_title "系统预检 / 环境判断"
  printf '系统: %s\n' "${os:-unknown}"
  printf '架构: %s\n' "$(uname -m 2>/dev/null || echo unknown)"
  printf 'Init: %s\n' "$(service_mode_label)"
  printf '根分区可用: %s\n' "${human}"
  printf 'Argosbx: %s\n' "$(argosbx_status_label)"
  printf 'Xray: %s\n' "${xray_version:-未安装到 ${XRAY_BIN}}"
  if command_exists curl || command_exists wget; then
    printf 'curl/wget: 可用\n'
  else
    printf 'curl/wget: 缺失\n'
  fi
  printf 'unzip: %s\n' "$(command_exists unzip && echo "可用" || echo "缺失，下载官方 Xray 时会尝试自动安装")"
  printf 'openssl: %s\n' "$(command_exists openssl && echo "可用" || echo "缺失，可用 /dev/urandom 兜底生成 SS 密钥")"
  echo ""
  if [[ "${ARGOSBX_DETECTED}" == "1" ]]; then
    info "当前适合复用部署：会优先复制 argosbx 的 Xray，再由 ${SERVICE_NAME} 独立运行新增入站。"
  else
    info "当前适合直接部署：会下载或复制 Xray 到 ${XRAY_BIN}，不依赖 argosbx。"
  fi
  warn "云厂商安全组仍需单独放行实际端口；脚本只能处理本机防火墙。"
}

service_status_label() {
  if [[ "${HAS_SYSTEMD}" == "1" ]]; then
    if systemctl is-active --quiet "${SERVICE_NAME}" 2>/dev/null; then
      printf '运行中'
    elif [[ -f "${SERVICE_FILE}" ]]; then
      printf '已安装未运行'
    else
      printf '未安装'
    fi
    return
  fi

  if process_running; then
    printf '运行中'
  elif [[ -f "${CONFIG_FILE}" ]]; then
    printf '已配置未运行'
  else
    printf '未安装'
  fi
}

process_running() {
  local pid=""
  if [[ -f "${PID_FILE}" ]]; then
    pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
    if [[ "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" 2>/dev/null; then
      return 0
    fi
  fi
  pgrep -f "${XRAY_BIN} run -config ${CONFIG_FILE}" >/dev/null 2>&1
}

print_dashboard() {
  detect_argosbx >/dev/null 2>&1 || true
  detect_init_system
  load_state

  print_title "Agsbx Extra 管理器"
  printf '根目录: %s\n' "${APP_ROOT}"
  printf '功能: %s\n' "${FEATURE_NAME}"
  printf '运行模式: %s\n' "$(service_mode_label)"
  printf 'Argosbx: %s\n' "$(argosbx_status_label)"
  printf '本服务: %s\n' "$(service_status_label)"
  printf 'Xray: %s\n' "$([[ -x "${XRAY_BIN}" ]] && echo "${XRAY_BIN}" || echo "未安装")"
  printf '%s: %s / UUID %s / Flow %s / ENC %s\n' \
    "${VLESS_NAME}" \
    "${PORT:-未设置}" \
    "$([[ -n "${UUID:-}" ]] && echo "已设置" || echo "未设置")" \
    "$(flow_label "${FLOW:-none}")" \
    "$([[ -n "${ENCRYPTION:-}" && -n "${DECRYPTION:-}" ]] && echo "已生成" || echo "未生成")"
  if [[ "${SS_ENABLED:-0}" == "1" ]]; then
    printf '%s: %s / %s / 密钥 %s\n' \
      "${SS_NAME}" \
      "${SS_PORT:-未设置}" \
      "${SS_METHOD:-${DEFAULT_SS_METHOD}}" \
      "$([[ -n "${SS_PASSWORD:-}" ]] && echo "已设置" || echo "未设置")"
  else
    printf '%s: 未启用\n' "${SS_NAME}"
  fi
  printf '配置: %s\n' "$([[ -f "${CONFIG_FILE}" ]] && echo "${CONFIG_FILE}" || echo "未生成")"
  print_divider
}

print_main_menu() {
  cat <<EOF
1. 系统预检 / 环境判断
2. 安装 / 修复 Xray core
3. 从 argosbx 同步 Xray core
4. 安装 / 修复 ${VLESS_NAME}
5. 安装 / 修复 ${SS_NAME}
6. 显示节点链接
7. 查看详细状态
8. VLESS 设置（端口 / 名称 / Flow / UUID / ENC）
9. SS2022 设置（端口 / 名称 / 方法 / 密钥）
10. 重写配置并重启
11. 启动 / 停止 / 重启服务
12. 连接测试
13. 查看日志
14. 防火墙 / 安全组提示
15. 卸载本功能
0. 退出
EOF
}

choose_free_port() {
  local port="${1:-}"
  local try
  if validate_port "${port}" && recommendable_port "${port}"; then
    printf '%s\n' "${port}"
    return 0
  fi

  for _ in $(seq 1 "${RECOMMENDED_PORT_RANDOM_TRIES}"); do
    try="$(random_recommended_port)"
    if recommendable_port "${try}"; then
      printf '%s\n' "${try}"
      return 0
    fi
  done

  for try in $(seq "${RECOMMENDED_PORT_MIN}" "${RECOMMENDED_PORT_MAX}"); do
    if recommendable_port "${try}"; then
      printf '%s\n' "${try}"
      return 0
    fi
  done

  return 1
}

random_recommended_port() {
  local min="${RECOMMENDED_PORT_MIN}"
  local max="${RECOMMENDED_PORT_MAX}"
  local span=$((max - min + 1))
  local n

  if command_exists shuf; then
    shuf -i "${min}-${max}" -n 1
    return 0
  fi

  if command_exists od && [[ -r /dev/urandom ]]; then
    n="$(od -An -N4 -tu4 /dev/urandom 2>/dev/null | tr -d '[:space:]')"
    if [[ "${n}" =~ ^[0-9]+$ ]]; then
      printf '%s\n' "$((min + (n % span)))"
      return 0
    fi
  fi

  awk -v min="${min}" -v span="${span}" 'BEGIN { srand(); print int(min + rand() * span) }'
}

recommendable_port() {
  local port="$1"
  validate_port "${port}" || return 1
  port_in_recommended_range "${port}" || return 1
  avoided_recommend_port "${port}" && return 1
  known_managed_port_owner "${port}" >/dev/null && return 1
  ! port_in_use "${port}"
}

port_in_recommended_range() {
  local port="$1"
  validate_port "${port}" || return 1
  (( port >= RECOMMENDED_PORT_MIN && port <= RECOMMENDED_PORT_MAX ))
}

avoided_recommend_port() {
  local port="$1"

  (( port <= 1024 )) && return 0
  case "${port}" in
    80|80*|443|443*|8443|9443) return 0 ;;
    20|21|22|23|25|53|110|123|143|161|389|465|587|993|995) return 0 ;;
    1433|1521|1723|2049|2375|2376|3000|3306|3389|5000|5432) return 0 ;;
    5900|6379|6443|7000|8080|8081|8088|8090|8888|9000|9090) return 0 ;;
  esac

  return 1
}

known_managed_port_owner() {
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

  if [[ -f /etc/shadowsocks-rust/config.json ]] && command_exists python3; then
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

  if [[ -f "${ENV_FILE}" ]]; then
    value="$(awk -F= '$1=="SS_PORT" {gsub(/^'\''|'\''$/, "", $2); print $2; exit}' "${ENV_FILE}" 2>/dev/null || true)"
    [[ "${value}" == "${port}" ]] && {
      printf 'agsbx-extra-ss2022:%s\n' "${ENV_FILE}"
      return 0
    }
  fi

  return 1
}

port_in_use() {
  local port="$1"
  if command_exists ss; then
    ss -H -lntup 2>/dev/null | awk -v suffix=":${port}" '
      $5 ~ suffix "$" { found=1 }
      END { exit found ? 0 : 1 }
    '
    return $?
  fi
  if command_exists lsof; then
    lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1
    return $?
  fi
  if command_exists netstat; then
    netstat -lntp 2>/dev/null | awk -v suffix=":${port}" '
      $4 ~ suffix "$" { found=1 }
      END { exit found ? 0 : 1 }
    '
    return $?
  fi
  return 1
}

port_owner() {
  local port="$1"
  if command_exists ss; then
    ss -H -lntup 2>/dev/null | awk -v suffix=":${port}" '$5 ~ suffix "$" { print }'
    return 0
  fi
  if command_exists lsof; then
    lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null
    return 0
  fi
  if command_exists netstat; then
    netstat -lntp 2>/dev/null | awk -v suffix=":${port}" '$4 ~ suffix "$" { print }'
    return 0
  fi
  printf '无法检测端口占用详情：缺少 ss/lsof/netstat。\n'
}

collect_argosbx_ports() {
  local file value
  [[ -n "${ARGOSBX_DIR}" && -d "${ARGOSBX_DIR}" ]] || return 0
  for file in "${ARGOSBX_DIR}"/port_*; do
    [[ -f "${file}" ]] || continue
    value="$(trim "$(cat "${file}" 2>/dev/null || true)")"
    validate_port "${value}" || continue
    printf '%s %s\n' "$(basename "${file}")" "${value}"
  done | sort -u
}

prompt_port() {
  local default="${1:-}"
  local current="${2:-${PORT:-}}"
  local label="${3:-${VLESS_NAME}}"
  local value owner known
  [[ -n "${default}" ]] || default="$(choose_free_port || true)"

  while true; do
    value="$(prompt_with_default "请输入 ${label} 监听端口" "${default}")"
    if ! validate_port "${value}"; then
      err "端口必须是 1-65535 的整数，且不能带前导 0。"
      continue
    fi
    if ! port_in_recommended_range "${value}"; then
      err "端口必须在 ${RECOMMENDED_PORT_MIN}-${RECOMMENDED_PORT_MAX} 范围内。"
      continue
    fi
    if [[ "${value}" != "${current}" ]]; then
      known="$(known_managed_port_owner "${value}" || true)"
      if [[ -n "${known}" ]]; then
        err "端口 ${value} 已出现在已知代理服务端口记录中：${known}"
        continue
      fi
    fi
    if [[ "${value}" != "${current}" ]] && port_in_use "${value}"; then
      owner="$(port_owner "${value}")"
      err "端口 ${value} 已被占用："
      printf '%s\n' "${owner}" >&2
      continue
    fi
    printf '%s\n' "${value}"
    return 0
  done
}

prompt_flow_mode() {
  local current choice
  current="$(normalize_flow "${1:-none}")"
  {
    echo ""
    echo "请选择 Flow 模式："
    echo "1. none（默认；VLESS ENC 不写 flow，和 TLS/Reality 无关）"
    echo "2. xtls-rprx-vision（写入 flow，需要客户端支持 Vision + VLESS ENC；不会自动开启 TLS）"
  } >&2
  read -r -p "请选择 Flow 模式 [当前: $(flow_label "${current}")，回车保留]: " choice
  case "${choice}" in
    "") printf '%s\n' "${current}" ;;
    1|none|NONE|off|OFF|no|NO|0) printf 'none\n' ;;
    2|vision|VISION|xtls-rprx-vision) printf 'xtls-rprx-vision\n' ;;
    *)
      warn "无效选择，保留当前 Flow: $(flow_label "${current}")" >&2
      printf '%s\n' "${current}"
      ;;
  esac
}

copy_xray_binary() {
  local manual_path="" system_xray=""

  if [[ -x "${XRAY_BIN}" ]]; then
    XRAY_SOURCE="${XRAY_SOURCE:-${XRAY_BIN}}"
    return 0
  fi

  detect_argosbx >/dev/null 2>&1 || true
  if [[ -n "${ARGOSBX_XRAY}" && -f "${ARGOSBX_XRAY}" ]]; then
    cp "${ARGOSBX_XRAY}" "${XRAY_BIN}" || return 1
    chmod +x "${XRAY_BIN}"
    XRAY_SOURCE="${ARGOSBX_XRAY}"
    success "已复制 argosbx Xray: ${ARGOSBX_XRAY}"
    return 0
  fi

  system_xray="$(command -v xray 2>/dev/null || true)"
  if [[ -n "${system_xray}" && -x "${system_xray}" ]]; then
    cp "${system_xray}" "${XRAY_BIN}" || return 1
    chmod +x "${XRAY_BIN}"
    XRAY_SOURCE="${system_xray}"
    success "已复制系统 Xray: ${system_xray}"
    return 0
  fi

  if [[ "${ARGOSBX_DETECTED}" == "1" ]]; then
    warn "检测到 argosbx，但当前 argosbx 目录没有 Xray，可能只安装了 Sing-box。"
  else
    info "未检测到 argosbx 的 Xray 二进制，将按直接部署模式准备 Xray。"
  fi

  if confirm_yes "是否从 XTLS/Xray-core 官方 release 下载 Xray"; then
    download_official_xray_binary && return 0
  fi

  read -r -p "请输入现有 xray 二进制路径，或直接回车退出: " manual_path
  manual_path="$(trim "${manual_path}")"
  [[ -n "${manual_path}" ]] || return 1
  if [[ ! -f "${manual_path}" ]]; then
    err "路径不存在: ${manual_path}"
    return 1
  fi
  cp "${manual_path}" "${XRAY_BIN}" || return 1
  chmod +x "${XRAY_BIN}"
  XRAY_SOURCE="${manual_path}"
  success "已复制 Xray: ${manual_path}"
}

xray_release_asset_name() {
  local machine
  machine="$(uname -m 2>/dev/null || echo unknown)"
  case "${machine}" in
    x86_64|amd64) echo "Xray-linux-64.zip" ;;
    i386|i686) echo "Xray-linux-32.zip" ;;
    aarch64|arm64) echo "Xray-linux-arm64-v8a.zip" ;;
    armv7l|armv7*) echo "Xray-linux-arm32-v7a.zip" ;;
    armv6l|armv6*) echo "Xray-linux-arm32-v6.zip" ;;
    armv5l|armv5*) echo "Xray-linux-arm32-v5.zip" ;;
    s390x) echo "Xray-linux-s390x.zip" ;;
    riscv64) echo "Xray-linux-riscv64.zip" ;;
    ppc64le) echo "Xray-linux-ppc64le.zip" ;;
    ppc64) echo "Xray-linux-ppc64.zip" ;;
    loongarch64|loong64) echo "Xray-linux-loong64.zip" ;;
    *) return 1 ;;
  esac
}

download_file() {
  local url="$1"
  local output="$2"
  if command_exists curl; then
    curl -fL --connect-timeout 15 --max-time 180 -o "${output}" "${url}"
    return $?
  fi
  if command_exists wget; then
    wget -O "${output}" "${url}"
    return $?
  fi
  err "未找到 curl 或 wget，无法下载。"
  return 1
}

ensure_unzip() {
  command_exists unzip && return 0

  warn "未找到 unzip，尝试自动安装。"
  if command_exists apt-get; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update || warn "apt-get update 失败，可能是某个可选软件源不可用；继续尝试安装 unzip。"
    apt-get install -y unzip
  elif command_exists dnf; then
    dnf install -y unzip
  elif command_exists yum; then
    yum install -y unzip
  elif command_exists apk; then
    apk add --no-cache unzip
  else
    err "未识别到可用包管理器，无法自动安装 unzip。"
    return 1
  fi

  if command_exists unzip; then
    success "unzip 已安装。"
    return 0
  fi

  err "自动安装 unzip 后仍不可用。"
  return 1
}

download_official_xray_binary() {
  local asset url tmp zip
  asset="$(xray_release_asset_name)" || {
    err "无法识别当前架构: $(uname -m 2>/dev/null || echo unknown)"
    return 1
  }

  if ! ensure_unzip; then
    err "无法解压 Xray release zip。请先手动安装 unzip，或手动指定 xray 路径。"
    return 1
  fi

  tmp="$(mktemp -d)"
  zip="${tmp}/${asset}"
  url="https://github.com/XTLS/Xray-core/releases/latest/download/${asset}"

  info "下载 ${url}"
  if ! download_file "${url}" "${zip}"; then
    rm -rf "${tmp}"
    err "下载 Xray 失败。"
    return 1
  fi

  if ! unzip -o "${zip}" -d "${tmp}/xray" >/dev/null; then
    rm -rf "${tmp}"
    err "解压 Xray 失败。"
    return 1
  fi

  if [[ ! -f "${tmp}/xray/xray" ]]; then
    rm -rf "${tmp}"
    err "release 包中未找到 xray 二进制。"
    return 1
  fi

  cp "${tmp}/xray/xray" "${XRAY_BIN}" || {
    rm -rf "${tmp}"
    return 1
  }
  chmod +x "${XRAY_BIN}"
  XRAY_SOURCE="XTLS/Xray-core latest release (${asset})"
  rm -rf "${tmp}"
  success "已安装官方 Xray 到 ${XRAY_BIN}"
}

verify_xray_binary() {
  if [[ ! -x "${XRAY_BIN}" ]]; then
    err "Xray 不存在或不可执行: ${XRAY_BIN}"
    return 1
  fi
  if ! "${XRAY_BIN}" version >/dev/null 2>&1; then
    err "Xray version 检查失败: ${XRAY_BIN}"
    return 1
  fi
  if ! "${XRAY_BIN}" uuid >/dev/null 2>&1; then
    err "Xray uuid 命令不可用。"
    return 1
  fi
  if ! "${XRAY_BIN}" vlessenc >/dev/null 2>&1; then
    err "当前 Xray 不支持 vlessenc，请使用支持 VLESS Encryption 的新版 Xray-core。"
    return 1
  fi
}

ensure_xray_core() {
  detect_argosbx >/dev/null 2>&1 || true
  detect_init_system
  ensure_dirs
  load_state

  copy_xray_binary || return 1
  if ! verify_xray_binary; then
    warn "当前 Xray 不满足 VLESS ENC 要求，或无法通过基础命令检查。"
    if confirm_yes "是否覆盖为 XTLS/Xray-core 官方 release"; then
      rm -f "${XRAY_BIN}"
      download_official_xray_binary || return 1
      verify_xray_binary || return 1
    else
      return 1
    fi
  fi
  write_state
}

install_or_repair_xray_core() {
  print_title "安装 / 修复 Xray core"
  if ensure_xray_core; then
    success "Xray core 已就绪: ${XRAY_BIN}"
    "${XRAY_BIN}" version | head -n 1 || true
  fi
}

sync_xray_from_argosbx() {
  print_title "从 argosbx 同步 Xray core"
  detect_argosbx >/dev/null 2>&1 || true
  detect_init_system
  ensure_dirs
  load_state
  if [[ -z "${ARGOSBX_XRAY}" || ! -f "${ARGOSBX_XRAY}" ]]; then
    err "未检测到 argosbx Xray，无法同步。"
    return 1
  fi
  backup_file "${XRAY_BIN}"
  cp "${ARGOSBX_XRAY}" "${XRAY_BIN}" || return 1
  chmod +x "${XRAY_BIN}"
  XRAY_SOURCE="${ARGOSBX_XRAY}"
  verify_xray_binary || return 1
  if [[ -f "${CONFIG_FILE}" ]]; then
    test_config || return 1
    restart_service || return 1
  fi
  write_state
  success "已从 argosbx 同步 Xray: ${ARGOSBX_XRAY}"
}

generate_uuid() {
  local value
  value="$("${XRAY_BIN}" uuid 2>/dev/null | head -n 1 | tr -d '\r\n')"
  if ! validate_uuid "${value}"; then
    err "生成 UUID 失败。"
    return 1
  fi
  UUID="${value}"
}

extract_vlessenc_value() {
  local key="$1"
  local file="$2"
  local value=""

  value="$(sed -nE "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]+)\".*/\1/p" "${file}" | head -n 1)"
  if [[ -z "${value}" ]]; then
    value="$(sed -nE "s/.*${key}[[:space:]]*[:=][[:space:]]*\"?([^\" ,]+).*/\1/p" "${file}" | head -n 1)"
  fi
  printf '%s' "${value}"
}

generate_vlessenc() {
  local tmp de enc
  tmp="$(mktemp)"
  if ! "${XRAY_BIN}" vlessenc > "${tmp}" 2>&1; then
    err "xray vlessenc 执行失败："
    cat "${tmp}" >&2
    rm -f "${tmp}"
    return 1
  fi

  de="$(extract_vlessenc_value "decryption" "${tmp}")"
  enc="$(extract_vlessenc_value "encryption" "${tmp}")"
  rm -f "${tmp}"

  if ! validate_enc_value "${de}" || ! validate_enc_value "${enc}"; then
    err "无法从 xray vlessenc 输出中解析 decryption/encryption。"
    return 1
  fi

  DECRYPTION="${de}"
  ENCRYPTION="${enc}"
}

generate_ss_password() {
  local method="${1:-${DEFAULT_SS_METHOD}}"
  local len
  len="$(ss_method_key_len "${method}")"

  if command_exists openssl; then
    openssl rand -base64 "${len}" | tr -d '\r\n'
    return 0
  fi
  if command_exists base64 && [[ -r /dev/urandom ]]; then
    head -c "${len}" /dev/urandom | base64 | tr -d '\r\n'
    return 0
  fi
  err "无法生成 SS 密钥：缺少 openssl/base64 或 /dev/urandom。"
  return 1
}

urlencode() {
  local value="$1"
  if command_exists python3; then
    python3 - "$value" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=""))
PY
    return 0
  fi
  printf '%s' "${value}" | sed 's/ /%20/g;s/#/%23/g;s/:/%3A/g;s/\//%2F/g;s/+/%2B/g;s/=/%3D/g'
}

base64_urlsafe_nopad() {
  local value="$1"
  if command_exists python3; then
    python3 - "$value" <<'PY'
import base64, sys
print(base64.urlsafe_b64encode(sys.argv[1].encode()).decode().rstrip("="))
PY
    return 0
  fi
  printf '%s' "${value}" | base64 | tr '+/' '-_' | tr -d '=\r\n'
}

backup_file() {
  local file="$1"
  local base
  [[ -f "${file}" ]] || return 0
  mkdir -p "${BACKUP_DIR}"
  base="$(basename "${file}")"
  cp "${file}" "${BACKUP_DIR}/${base}.$(date +%Y%m%d-%H%M%S).bak" 2>/dev/null || true
}

write_config() {
  local flow_line=""
  local vless_inbound=""
  local ss_inbound=""
  if [[ "$(normalize_flow "${FLOW:-none}")" == "xtls-rprx-vision" ]]; then
    flow_line=$',\n            "flow": "xtls-rprx-vision"'
  fi

  if [[ -n "${PORT:-}" && -n "${UUID:-}" && -n "${DECRYPTION:-}" && -n "${ENCRYPTION:-}" ]]; then
    vless_inbound=$(cat <<EOF
    {
      "tag": "${FEATURE_ID}",
      "listen": "${LISTEN:-${DEFAULT_LISTEN}}",
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}"${flow_line}
          }
        ],
        "decryption": "${DECRYPTION}"
      },
      "streamSettings": {
        "network": "raw",
        "rawSettings": {
          "acceptProxyProtocol": false,
          "header": {
            "type": "none"
          }
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "metadataOnly": false
      }
    }
EOF
)
  fi

  if [[ "${SS_ENABLED:-0}" == "1" ]]; then
    if [[ -z "${SS_PORT:-}" || -z "${SS_METHOD:-}" || -z "${SS_PASSWORD:-}" ]]; then
      err "${SS_NAME} 状态不完整，请先安装 / 修复 ${SS_NAME}。"
      return 1
    fi
    if [[ -n "${vless_inbound}" ]]; then
      ss_inbound=","
    fi
    ss_inbound=$(cat <<EOF
${ss_inbound}
    {
      "tag": "ss2022-in",
      "listen": "${SS_LISTEN:-${DEFAULT_LISTEN}}",
      "port": ${SS_PORT},
      "protocol": "shadowsocks",
      "settings": {
        "network": "tcp,udp",
        "method": "${SS_METHOD:-${DEFAULT_SS_METHOD}}",
        "password": "${SS_PASSWORD}",
        "level": 0
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "metadataOnly": false
      }
    }
EOF
)
  fi

  if [[ -z "${vless_inbound}${ss_inbound}" ]]; then
    err "没有可写入的协议配置，请先安装 VLESS 或 SS2022。"
    return 1
  fi

  backup_file "${CONFIG_FILE}"
  mkdir -p "${FEATURE_DIR}"
  cat > "${CONFIG_FILE}" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
${vless_inbound}${ss_inbound}
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}
EOF
  chmod 600 "${CONFIG_FILE}" 2>/dev/null || true
}

test_config() {
  local out="${FEATURE_DIR}/config-test.log"
  if "${XRAY_BIN}" run -test -config "${CONFIG_FILE}" > "${out}" 2>&1; then
    success "Xray 配置测试通过。"
    return 0
  fi
  if "${XRAY_BIN}" test -config "${CONFIG_FILE}" > "${out}" 2>&1; then
    success "Xray 配置测试通过。"
    return 0
  fi

  err "Xray 配置测试失败，输出如下："
  cat "${out}" >&2
  return 1
}

write_systemd_service() {
  backup_file "${SERVICE_FILE}"
  cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Agsbx Extra ${FEATURE_NAME}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${FEATURE_DIR}
ExecStart=${XRAY_BIN} run -config ${CONFIG_FILE}
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
}

install_cron_reboot() {
  local tmp
  tmp="$(mktemp)"
  crontab -l 2>/dev/null | grep -v "${CONFIG_FILE}" > "${tmp}" || true
  echo "@reboot sleep 10 && nohup ${XRAY_BIN} run -config ${CONFIG_FILE} >> ${LOG_DIR}/${FEATURE_ID}.log 2>&1 &" >> "${tmp}"
  crontab "${tmp}" >/dev/null 2>&1 || warn "写入 crontab 失败，请手动设置开机启动。"
  rm -f "${tmp}"
}

remove_cron_reboot() {
  local tmp
  tmp="$(mktemp)"
  crontab -l 2>/dev/null | grep -v "${CONFIG_FILE}" > "${tmp}" || true
  crontab "${tmp}" >/dev/null 2>&1 || true
  rm -f "${tmp}"
}

start_service() {
  if [[ "${HAS_SYSTEMD}" == "1" ]]; then
    systemctl enable --now "${SERVICE_NAME}"
    return $?
  fi

  if process_running; then
    warn "服务已经在运行。"
    return 0
  fi
  nohup "${XRAY_BIN}" run -config "${CONFIG_FILE}" >> "${LOG_DIR}/${FEATURE_ID}.log" 2>&1 &
  echo "$!" > "${PID_FILE}"
  install_cron_reboot
}

stop_service() {
  local pid=""
  if [[ "${HAS_SYSTEMD}" == "1" ]]; then
    systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
    return 0
  fi

  if [[ -f "${PID_FILE}" ]]; then
    pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
    if [[ "${pid}" =~ ^[0-9]+$ ]]; then
      kill "${pid}" 2>/dev/null || true
    fi
  fi
  pkill -f "${XRAY_BIN} run -config ${CONFIG_FILE}" 2>/dev/null || true
  rm -f "${PID_FILE}"
}

restart_service() {
  if [[ "${HAS_SYSTEMD}" == "1" ]]; then
    systemctl restart "${SERVICE_NAME}"
  else
    stop_service
    sleep 1
    start_service
  fi
}

detect_public_ip() {
  local ip=""
  if command_exists curl; then
    ip="$(curl -s4m5 https://icanhazip.com 2>/dev/null | tr -d '\r\n' || true)"
    [[ -n "${ip}" ]] || ip="$(curl -s6m5 https://icanhazip.com 2>/dev/null | tr -d '\r\n' || true)"
  fi
  if [[ -z "${ip}" ]] && command_exists wget; then
    ip="$(timeout 5 wget -4 -qO- https://icanhazip.com 2>/dev/null | tr -d '\r\n' || true)"
    [[ -n "${ip}" ]] || ip="$(timeout 5 wget -6 -qO- https://icanhazip.com 2>/dev/null | tr -d '\r\n' || true)"
  fi
  if [[ -z "${ip}" ]]; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  fi
  printf '%s' "${ip}"
}

format_host_for_share() {
  local host="$1"
  if [[ "${host}" == \[*\] ]]; then
    printf '%s' "${host}"
  elif [[ "${host}" == *:* ]]; then
    printf '[%s]' "${host}"
  else
    printf '%s' "${host}"
  fi
}

write_share_links() {
  local ip addr node raw_link tcp_link flow_query ss_host ss_port ss_node ss_userinfo ss_link
  load_state
  ip="$(detect_public_ip)"
  if [[ -z "${ip}" ]]; then
    warn "未能自动获取公网 IP，分享链接地址暂写为 YOUR_SERVER_IP。"
    addr="YOUR_SERVER_IP"
  else
    addr="$(format_host_for_share "${ip}")"
  fi

  : > "${SHARE_FILE}"

  if [[ -n "${PORT:-}" && -n "${UUID:-}" && -n "${ENCRYPTION:-}" ]]; then
    node="$(urlencode "${NODE_NAME:-vl-raw-enc-$(safe_hostname)}")"
    flow_query=""
    if [[ "$(normalize_flow "${FLOW:-none}")" == "xtls-rprx-vision" ]]; then
      flow_query="&flow=xtls-rprx-vision"
    fi
    raw_link="vless://${UUID}@${addr}:${PORT}?encryption=${ENCRYPTION}${flow_query}&security=none&type=raw#${node}"
    tcp_link="vless://${UUID}@${addr}:${PORT}?encryption=${ENCRYPTION}${flow_query}&security=none&type=tcp&headerType=none#${node}"
    {
      echo "[${VLESS_NAME}]"
      echo "${raw_link}"
      echo "${tcp_link}"
      echo ""
    } >> "${SHARE_FILE}"
  fi

  if [[ "${SS_ENABLED:-0}" == "1" && -n "${SS_PORT:-}" && -n "${SS_METHOD:-}" && -n "${SS_PASSWORD:-}" ]]; then
    ss_host="${SS_PUBLIC_HOST:-${addr}}"
    ss_host="$(format_host_for_share "${ss_host}")"
    ss_port="${SS_PUBLIC_PORT:-${SS_PORT}}"
    ss_node="$(urlencode "${SS_NODE_NAME:-${DEFAULT_SS_NODE_NAME}-$(safe_hostname)}")"
    ss_userinfo="$(base64_urlsafe_nopad "${SS_METHOD}:${SS_PASSWORD}")"
    ss_link="ss://${ss_userinfo}@${ss_host}:${ss_port}#${ss_node}"
    {
      echo "[${SS_NAME}]"
      echo "${ss_link}"
      echo ""
    } >> "${SHARE_FILE}"
  fi

  chmod 600 "${SHARE_FILE}" 2>/dev/null || true
}

ensure_ready_for_config() {
  if [[ -z "${PORT:-}" || -z "${UUID:-}" || -z "${DECRYPTION:-}" || -z "${ENCRYPTION:-}" ]]; then
    err "${VLESS_NAME} 状态不完整，请先安装 / 修复 ${VLESS_NAME}。"
    return 1
  fi
}

ensure_any_protocol_ready() {
  if [[ -n "${PORT:-}" && -n "${UUID:-}" && -n "${DECRYPTION:-}" && -n "${ENCRYPTION:-}" ]]; then
    return 0
  fi
  if [[ "${SS_ENABLED:-0}" == "1" && -n "${SS_PORT:-}" && -n "${SS_METHOD:-}" && -n "${SS_PASSWORD:-}" ]]; then
    return 0
  fi
  err "尚未启用任何完整协议，请先安装 VLESS 或 SS2022。"
  return 1
}

ensure_ss_ready() {
  if [[ "${SS_ENABLED:-0}" != "1" || -z "${SS_PORT:-}" || -z "${SS_METHOD:-}" || -z "${SS_PASSWORD:-}" ]]; then
    err "${SS_NAME} 状态不完整，请先安装 / 修复 ${SS_NAME}。"
    return 1
  fi
}

install_or_repair_vless() {
  print_title "安装 / 修复 ${VLESS_NAME}"
  detect_argosbx >/dev/null 2>&1 || true
  detect_init_system
  ensure_dirs
  load_state

  if [[ "${ARGOSBX_DETECTED}" == "1" ]]; then
    info "检测到 argosbx: ${ARGOSBX_DIR}"
    [[ -n "${ARGOSBX_XRAY}" ]] && info "Argosbx Xray: ${ARGOSBX_XRAY}" || warn "Argosbx Xray: 未安装"
    [[ -n "${ARGOSBX_SINGBOX}" ]] && info "Argosbx Sing-box: ${ARGOSBX_SINGBOX}" || warn "Argosbx Sing-box: 未安装"
  else
    info "未检测到 argosbx，将按直接部署模式准备 Xray。"
  fi

  ensure_xray_core || return 1

  if [[ -z "${PORT:-}" ]]; then
    PORT="$(prompt_port "$(choose_free_port || true)" "" "${VLESS_NAME}")"
  else
    PORT="$(prompt_port "${PORT}" "${PORT}" "${VLESS_NAME}")"
  fi
  if [[ "${SS_ENABLED:-0}" == "1" && -n "${SS_PORT:-}" && "${PORT}" == "${SS_PORT}" ]]; then
    err "VLESS 端口不能与 SS2022 端口相同: ${PORT}"
    return 1
  fi

  LISTEN="${LISTEN:-${DEFAULT_LISTEN}}"

  if [[ -z "${UUID:-}" ]]; then
    if validate_uuid "${ARGOSBX_UUID:-}" && confirm_yes "检测到 argosbx UUID，是否复用它"; then
      UUID="${ARGOSBX_UUID}"
    else
      generate_uuid || return 1
    fi
  fi

  if [[ -z "${DECRYPTION:-}" || -z "${ENCRYPTION:-}" ]]; then
    generate_vlessenc || return 1
  fi

  FLOW="$(prompt_flow_mode "${FLOW:-none}")"
  [[ -n "${NODE_NAME:-}" ]] || NODE_NAME="vl-raw-enc-$(safe_hostname)"

  write_state
  write_config
  test_config || return 1

  if [[ "${HAS_SYSTEMD}" == "1" ]]; then
    write_systemd_service
  else
    warn "未检测到 systemd，将使用 pid+cron 模式管理。"
  fi

  start_service || return 1
  write_share_links
  success "${VLESS_NAME} 安装 / 修复完成。"
  show_links
}

prompt_ss_method() {
  local current="${1:-${DEFAULT_SS_METHOD}}"
  local choice
  echo "" >&2
  echo "请选择 ${SS_NAME} 加密方法：" >&2
  echo "1. 2022-blake3-aes-128-gcm（默认，SS2022）" >&2
  echo "2. 2022-blake3-aes-256-gcm（SS2022）" >&2
  echo "3. 2022-blake3-chacha20-poly1305（SS2022）" >&2
  echo "4. aes-128-gcm（旧 AEAD）" >&2
  echo "5. aes-256-gcm（旧 AEAD）" >&2
  echo "6. chacha20-ietf-poly1305（旧 AEAD）" >&2
  read -r -p "请选择 [当前: ${current}，回车保留]: " choice
  case "${choice}" in
    "") printf '%s\n' "${current}" ;;
    1) printf '2022-blake3-aes-128-gcm\n' ;;
    2) printf '2022-blake3-aes-256-gcm\n' ;;
    3) printf '2022-blake3-chacha20-poly1305\n' ;;
    4) printf 'aes-128-gcm\n' ;;
    5) printf 'aes-256-gcm\n' ;;
    6) printf 'chacha20-ietf-poly1305\n' ;;
    *)
      if ss_supported_method "${choice}"; then
        printf '%s\n' "${choice}"
      else
        warn "无效方法，保留当前: ${current}" >&2
        printf '%s\n' "${current}"
      fi
      ;;
  esac
}

prompt_ss_public_entry() {
  local host port source
  host="$(prompt_with_default "SS 链接使用的公网 host（直连可留空自动探测）" "${SS_PUBLIC_HOST:-}")"
  port="$(prompt_with_default "SS 链接使用的公网端口（直连可留空使用本地端口）" "${SS_PUBLIC_PORT:-}")"
  source="$(prompt_with_default "防火墙允许来源 IP/CIDR（可选，仅用于提示/放行）" "${SS_ALLOW_SOURCE:-}")"
  host="$(trim "${host}")"
  port="$(trim "${port}")"
  source="$(trim "${source}")"
  if [[ -n "${port}" ]] && ! validate_port "${port}"; then
    err "公网端口无效: ${port}"
    return 1
  fi
  if [[ -n "${source}" ]] && ! validate_no_whitespace "${source}"; then
    err "来源地址不能包含空白字符: ${source}"
    return 1
  fi
  SS_PUBLIC_HOST="${host}"
  SS_PUBLIC_PORT="${port}"
  SS_ALLOW_SOURCE="${source}"
}

install_or_repair_ss() {
  local password_input
  print_title "安装 / 修复 ${SS_NAME}"
  detect_argosbx >/dev/null 2>&1 || true
  detect_init_system
  ensure_dirs
  load_state
  ensure_xray_core || return 1

  if [[ -z "${SS_PORT:-}" ]]; then
    SS_PORT="$(prompt_port "$(choose_free_port || true)" "" "${SS_NAME}")"
  else
    SS_PORT="$(prompt_port "${SS_PORT}" "${SS_PORT}" "${SS_NAME}")"
  fi
  if [[ -n "${PORT:-}" && "${SS_PORT}" == "${PORT}" ]]; then
    err "SS2022 端口不能与 VLESS 端口相同: ${SS_PORT}"
    return 1
  fi

  SS_METHOD="$(prompt_ss_method "${SS_METHOD:-${DEFAULT_SS_METHOD}}")"
  ss_supported_method "${SS_METHOD}" || {
    err "不支持的 Shadowsocks 方法: ${SS_METHOD}"
    return 1
  }

  if [[ -z "${SS_PASSWORD:-}" ]]; then
    read -r -p "请输入 SS 密钥（回车自动生成）: " password_input
    if [[ -n "${password_input}" ]]; then
      SS_PASSWORD="${password_input}"
    else
      SS_PASSWORD="$(generate_ss_password "${SS_METHOD}")" || return 1
    fi
  elif confirm_yes "是否重新生成 SS 密钥"; then
    SS_PASSWORD="$(generate_ss_password "${SS_METHOD}")" || return 1
  fi
  if [[ -z "${SS_PASSWORD:-}" ]] || ! validate_no_whitespace "${SS_PASSWORD}" || ! validate_json_safe_string "${SS_PASSWORD}"; then
    err "SS 密钥不能为空，且不能包含空白、双引号或反斜杠。"
    return 1
  fi

  SS_LISTEN="${SS_LISTEN:-${DEFAULT_LISTEN}}"
  [[ -n "${SS_NODE_NAME:-}" ]] || SS_NODE_NAME="${DEFAULT_SS_NODE_NAME}-$(safe_hostname)"
  prompt_ss_public_entry || return 1
  SS_ENABLED="1"

  write_state
  write_config
  test_config || return 1
  if [[ "${HAS_SYSTEMD}" == "1" ]]; then
    write_systemd_service
  else
    warn "未检测到 systemd，将使用 pid+cron 模式管理。"
  fi
  start_service || return 1
  write_share_links
  success "${SS_NAME} 安装 / 修复完成。"
  show_links
}

show_detail_status() {
  print_title "详细状态"
  detect_argosbx >/dev/null 2>&1 || true
  detect_init_system
  load_state

  printf '应用根目录: %s\n' "${APP_ROOT}"
  printf '功能目录: %s\n' "${FEATURE_DIR}"
  printf 'Xray路径: %s\n' "$([[ -x "${XRAY_BIN}" ]] && echo "${XRAY_BIN}" || echo "未安装")"
  printf 'Xray来源: %s\n' "${XRAY_SOURCE:-未知}"
  printf 'Argosbx目录: %s\n' "${ARGOSBX_DIR:-未检测到}"
  printf 'Argosbx Xray: %s\n' "${ARGOSBX_XRAY:-未检测到}"
  printf 'Argosbx Sing-box: %s\n' "${ARGOSBX_SINGBOX:-未检测到}"
  printf '管理模式: %s\n' "$(service_mode_label)"
  printf '服务状态: %s\n' "$(service_status_label)"
  printf '监听端口: %s\n' "${PORT:-未设置}"
  printf '监听地址: %s\n' "${LISTEN:-${DEFAULT_LISTEN}}"
  printf '节点名称: %s\n' "${NODE_NAME:-未设置}"
  printf 'Flow: %s\n' "$(flow_label "${FLOW:-none}")"
  printf 'UUID: %s\n' "${UUID:-未设置}"
  echo ""
  printf '%s: %s\n' "${SS_NAME}" "$([[ "${SS_ENABLED:-0}" == "1" ]] && echo "已启用" || echo "未启用")"
  printf 'SS监听端口: %s\n' "${SS_PORT:-未设置}"
  printf 'SS监听地址: %s\n' "${SS_LISTEN:-${DEFAULT_LISTEN}}"
  printf 'SS方法: %s\n' "${SS_METHOD:-${DEFAULT_SS_METHOD}}"
  printf 'SS节点名称: %s\n' "${SS_NODE_NAME:-未设置}"
  printf 'SS公网入口: %s:%s\n' "${SS_PUBLIC_HOST:-自动探测}" "${SS_PUBLIC_PORT:-${SS_PORT:-未设置}}"
  printf 'SS防火墙来源: %s\n' "${SS_ALLOW_SOURCE:-任意来源}"
  echo ""
  printf '配置文件: %s\n' "$([[ -f "${CONFIG_FILE}" ]] && echo "${CONFIG_FILE}" || echo "未生成")"
  printf '分享文件: %s\n' "$([[ -f "${SHARE_FILE}" ]] && echo "${SHARE_FILE}" || echo "未生成")"
  printf '创建时间: %s\n' "${CREATED_AT:-未知}"
  printf '更新时间: %s\n' "${UPDATED_AT:-未知}"

  if [[ -n "${ARGOSBX_DIR}" ]]; then
    echo ""
    echo "Argosbx 已知端口:"
    collect_argosbx_ports || true
  fi

  if [[ -n "${PORT:-}" ]] && port_in_use "${PORT}"; then
    echo ""
    echo "当前端口监听:"
    port_owner "${PORT}"
  fi
}

show_links() {
  load_state
  print_title "节点链接"
  if ! ensure_any_protocol_ready; then
    return 1
  fi
  write_share_links
  cat "${SHARE_FILE}"
  echo ""
  info "VLESS 分组第一条为 type=raw；第二条为兼容部分客户端的 type=tcp&headerType=none。SS2022 分组为 SIP002 ss:// 链接。"
}

change_port() {
  print_title "修改端口"
  load_state
  ensure_ready_for_config || return 1
  PORT="$(prompt_port "${PORT}" "${PORT}" "${VLESS_NAME}")"
  if [[ "${SS_ENABLED:-0}" == "1" && -n "${SS_PORT:-}" && "${PORT}" == "${SS_PORT}" ]]; then
    err "VLESS 端口不能与 SS2022 端口相同: ${PORT}"
    return 1
  fi
  write_state
  write_config
  test_config || return 1
  restart_service
  write_share_links
  success "端口已修改为 ${PORT}。"
}

change_node_name() {
  local value
  print_title "修改节点名称"
  load_state
  ensure_ready_for_config || return 1
  value="$(prompt_with_default "请输入节点名称" "${NODE_NAME:-vl-raw-enc-$(safe_hostname)}")"
  value="$(printf '%s' "${value}" | tr -d '\r\n#')"
  if [[ -z "${value}" ]]; then
    err "节点名称不能为空。"
    return 1
  fi
  NODE_NAME="${value}"
  write_state
  write_share_links
  success "节点名称已更新为 ${NODE_NAME}。"
}

change_flow_mode() {
  print_title "修改 Flow 模式"
  load_state
  ensure_ready_for_config || return 1
  FLOW="$(prompt_flow_mode "${FLOW:-none}")"
  write_state
  write_config
  test_config || return 1
  restart_service
  write_share_links
  success "Flow 已更新为 $(flow_label "${FLOW}")。"
}

regenerate_uuid() {
  print_title "重新生成 UUID"
  load_state
  ensure_ready_for_config || return 1
  warn "重新生成 UUID 后，旧客户端链接会失效。"
  confirm_yes "确认继续" || return 0
  generate_uuid || return 1
  write_state
  write_config
  test_config || return 1
  restart_service
  write_share_links
  success "UUID 已更新。"
}

regenerate_enc() {
  print_title "重新生成 VLESS ENC key"
  load_state
  ensure_ready_for_config || return 1
  warn "重新生成 ENC key 后，旧客户端链接会失效。"
  confirm_yes "确认继续" || return 0
  generate_vlessenc || return 1
  write_state
  write_config
  test_config || return 1
  restart_service
  write_share_links
  success "VLESS ENC key 已更新。"
}

vless_settings_menu() {
  local choice
  while true; do
    print_title "VLESS 设置"
    printf '端口: %s\n' "${PORT:-未设置}"
    printf '节点名称: %s\n' "${NODE_NAME:-未设置}"
    printf 'Flow: %s\n' "$(flow_label "${FLOW:-none}")"
    cat <<EOF
1. 修改端口
2. 修改节点名称
3. 修改 Flow 模式
4. 重新生成 UUID
5. 重新生成 VLESS ENC key
0. 返回
EOF
    read -r -p "请选择: " choice
    case "${choice}" in
      1) change_port; pause_before_return ;;
      2) change_node_name; pause_before_return ;;
      3) change_flow_mode; pause_before_return ;;
      4) regenerate_uuid; pause_before_return ;;
      5) regenerate_enc; pause_before_return ;;
      0) return 0 ;;
      *) warn "无效选择。" ;;
    esac
  done
}

change_ss_port() {
  print_title "修改 SS2022 端口"
  load_state
  ensure_ss_ready || return 1
  SS_PORT="$(prompt_port "${SS_PORT}" "${SS_PORT}" "${SS_NAME}")"
  if [[ -n "${PORT:-}" && "${SS_PORT}" == "${PORT}" ]]; then
    err "SS2022 端口不能与 VLESS 端口相同: ${SS_PORT}"
    return 1
  fi
  write_state
  write_config
  test_config || return 1
  restart_service
  write_share_links
  success "SS2022 端口已修改为 ${SS_PORT}。"
}

change_ss_node_name() {
  local value
  print_title "修改 SS2022 节点名称"
  load_state
  ensure_ss_ready || return 1
  value="$(prompt_with_default "请输入 SS2022 节点名称" "${SS_NODE_NAME:-${DEFAULT_SS_NODE_NAME}-$(safe_hostname)}")"
  value="$(printf '%s' "${value}" | tr -d '\r\n#')"
  if [[ -z "${value}" ]]; then
    err "节点名称不能为空。"
    return 1
  fi
  SS_NODE_NAME="${value}"
  write_state
  write_share_links
  success "SS2022 节点名称已更新为 ${SS_NODE_NAME}。"
}

change_ss_method() {
  print_title "修改 SS2022 加密方法"
  load_state
  ensure_ss_ready || return 1
  warn "修改加密方法会重新生成密钥，旧客户端链接会失效。"
  confirm_yes "确认继续" || return 0
  SS_METHOD="$(prompt_ss_method "${SS_METHOD:-${DEFAULT_SS_METHOD}}")"
  SS_PASSWORD="$(generate_ss_password "${SS_METHOD}")" || return 1
  write_state
  write_config
  test_config || return 1
  restart_service
  write_share_links
  success "SS2022 加密方法和密钥已更新。"
}

regenerate_ss_password() {
  print_title "重新生成 SS2022 密钥"
  load_state
  ensure_ss_ready || return 1
  warn "重新生成密钥后，旧客户端链接会失效。"
  confirm_yes "确认继续" || return 0
  SS_PASSWORD="$(generate_ss_password "${SS_METHOD:-${DEFAULT_SS_METHOD}}")" || return 1
  write_state
  write_config
  test_config || return 1
  restart_service
  write_share_links
  success "SS2022 密钥已更新。"
}

change_ss_public_entry() {
  print_title "修改 SS2022 公网入口"
  load_state
  ensure_ss_ready || return 1
  prompt_ss_public_entry || return 1
  write_state
  write_share_links
  success "SS2022 公网入口信息已更新。"
}

disable_ss() {
  print_title "禁用 SS2022"
  load_state
  ensure_ss_ready || return 1
  warn "此操作会从 Xray 配置移除 SS2022 inbound，但保留密钥和状态，之后可重新启用。"
  confirm_yes "确认禁用 SS2022" || return 0
  SS_ENABLED="0"
  write_state
  if [[ -n "${PORT:-}" && -n "${UUID:-}" && -n "${DECRYPTION:-}" && -n "${ENCRYPTION:-}" ]]; then
    write_config
    test_config || return 1
    restart_service
  else
    stop_service
    warn "当前没有其它已启用协议，服务已停止。"
  fi
  write_share_links
  success "SS2022 已禁用。"
}

ss_settings_menu() {
  local choice
  while true; do
    print_title "SS2022 设置"
    printf '状态: %s\n' "$([[ "${SS_ENABLED:-0}" == "1" ]] && echo "已启用" || echo "未启用")"
    printf '端口: %s\n' "${SS_PORT:-未设置}"
    printf '方法: %s\n' "${SS_METHOD:-${DEFAULT_SS_METHOD}}"
    printf '节点名称: %s\n' "${SS_NODE_NAME:-未设置}"
    cat <<EOF
1. 安装 / 修复 SS2022
2. 修改端口
3. 修改节点名称
4. 修改加密方法（会重置密钥）
5. 重新生成密钥
6. 修改公网入口 / 防火墙来源
7. 禁用 SS2022
0. 返回
EOF
    read -r -p "请选择: " choice
    case "${choice}" in
      1) install_or_repair_ss; pause_before_return ;;
      2) change_ss_port; pause_before_return ;;
      3) change_ss_node_name; pause_before_return ;;
      4) change_ss_method; pause_before_return ;;
      5) regenerate_ss_password; pause_before_return ;;
      6) change_ss_public_entry; pause_before_return ;;
      7) disable_ss; pause_before_return ;;
      0) return 0 ;;
      *) warn "无效选择。" ;;
    esac
  done
}

rewrite_and_restart() {
  print_title "重写配置并重启"
  load_state
  ensure_any_protocol_ready || return 1
  write_state
  write_config
  test_config || return 1
  restart_service
  write_share_links
  success "配置已重写，服务已重启。"
}

service_control_menu() {
  local choice
  while true; do
    print_title "服务控制"
    printf '当前状态: %s\n' "$(service_status_label)"
    cat <<EOF
1. 启动
2. 停止
3. 重启
4. 查看状态
0. 返回
EOF
    read -r -p "请选择: " choice
    case "${choice}" in
      1) start_service; pause_before_return ;;
      2) stop_service; pause_before_return ;;
      3) restart_service; pause_before_return ;;
      4) service_runtime_status; pause_before_return ;;
      0) return 0 ;;
      *) warn "无效选择。" ;;
    esac
  done
}

service_runtime_status() {
  if [[ "${HAS_SYSTEMD}" == "1" ]]; then
    systemctl status "${SERVICE_NAME}" --no-pager || true
  else
    if process_running; then
      success "进程运行中。"
      pgrep -af "${XRAY_BIN} run -config ${CONFIG_FILE}" || true
    else
      warn "进程未运行。"
    fi
  fi
}

next_local_test_port() {
  local port=10880
  while port_in_use "${port}"; do
    port=$((port + 1))
  done
  printf '%s\n' "${port}"
}

run_ss_xray_test() {
  local target_host="$1"
  local target_port="$2"
  local label="$3"
  local bind_port tmp_cfg tmp_log pid status
  load_state
  ensure_ss_ready || return 1
  command_exists curl || {
    err "缺少 curl，无法执行连接测试。"
    return 1
  }
  [[ -x "${XRAY_BIN}" ]] || {
    err "Xray 未安装: ${XRAY_BIN}"
    return 1
  }

  bind_port="$(next_local_test_port)"
  tmp_cfg="$(mktemp)"
  tmp_log="$(mktemp)"
  cat > "${tmp_cfg}" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "tag": "test-socks",
      "listen": "127.0.0.1",
      "port": ${bind_port},
      "protocol": "socks",
      "settings": { "udp": true }
    }
  ],
  "outbounds": [
    {
      "tag": "test-ss",
      "protocol": "shadowsocks",
      "settings": {
        "servers": [
          {
            "address": "${target_host}",
            "port": ${target_port},
            "method": "${SS_METHOD}",
            "password": "${SS_PASSWORD}"
          }
        ]
      }
    }
  ]
}
EOF

  if ! "${XRAY_BIN}" run -test -config "${tmp_cfg}" > "${tmp_log}" 2>&1; then
    err "临时 Xray 客户端配置测试失败："
    cat "${tmp_log}" >&2
    rm -f "${tmp_cfg}" "${tmp_log}"
    return 1
  fi

  "${XRAY_BIN}" run -config "${tmp_cfg}" > "${tmp_log}" 2>&1 &
  pid="$!"
  sleep 1
  if ! kill -0 "${pid}" 2>/dev/null; then
    err "临时 Xray 客户端启动失败："
    cat "${tmp_log}" >&2
    rm -f "${tmp_cfg}" "${tmp_log}"
    return 1
  fi

  curl --max-time 12 -x "socks5h://127.0.0.1:${bind_port}" "${TEST_URL}"
  status=$?
  kill "${pid}" >/dev/null 2>&1 || true
  wait "${pid}" >/dev/null 2>&1 || true
  rm -f "${tmp_cfg}" "${tmp_log}"

  if [[ "${status}" -eq 0 ]]; then
    success "${label} 测试通过。"
  else
    err "${label} 测试失败，curl exit code: ${status}"
    return 1
  fi
}

test_menu() {
  local choice host port
  while true; do
    print_title "连接测试"
    cat <<EOF
1. Xray 配置语法测试
2. SS2022 本机测试（127.0.0.1:${SS_PORT:-未设置}）
3. SS2022 公网入口测试
0. 返回
EOF
    read -r -p "请选择: " choice
    case "${choice}" in
      1)
        load_state
        ensure_any_protocol_ready && write_config && test_config
        pause_before_return
        ;;
      2)
        run_ss_xray_test "127.0.0.1" "${SS_PORT:-0}" "SS2022 本机"
        pause_before_return
        ;;
      3)
        load_state
        ensure_ss_ready || { pause_before_return; continue; }
        host="$(prompt_with_default "公网 host" "${SS_PUBLIC_HOST:-$(detect_public_ip)}")"
        port="$(prompt_with_default "公网端口" "${SS_PUBLIC_PORT:-${SS_PORT}}")"
        if validate_port "${port}"; then
          run_ss_xray_test "${host}" "${port}" "SS2022 公网入口"
        else
          err "公网端口无效: ${port}"
        fi
        pause_before_return
        ;;
      0) return 0 ;;
      *) warn "无效选择。" ;;
    esac
  done
}

show_logs() {
  print_title "日志"
  if [[ "${HAS_SYSTEMD}" == "1" ]]; then
    journalctl -u "${SERVICE_NAME}" -n 80 --no-pager || true
  else
    tail -n 80 "${LOG_DIR}/${FEATURE_ID}.log" 2>/dev/null || warn "暂无日志文件。"
  fi
}

firewall_menu() {
  local choice
  load_state
  print_title "防火墙 / 安全组"

  cat <<EOF
VLESS端口: ${PORT:-未设置}/tcp
SS2022端口: ${SS_PORT:-未设置}/tcp,udp

说明:
  这里处理的是 VPS 系统内防火墙。云厂商安全组 / 面板防火墙仍需在控制台单独放行实际端口。
  如果系统防火墙默认放行，本菜单无需执行自动放行。

1. 检查本机防火墙并显示 VLESS 建议
2. 自动尝试放行 VLESS 端口
3. 检查本机防火墙并显示 SS2022 建议
4. 自动尝试放行 SS2022 端口
0. 返回
EOF
  read -r -p "请选择: " choice
  case "${choice}" in
    1)
      [[ -n "${PORT:-}" ]] || { err "VLESS 端口未设置。"; return 1; }
      show_firewall_advice "${PORT}" "tcp" ""
      ;;
    2)
      [[ -n "${PORT:-}" ]] || { err "VLESS 端口未设置。"; return 1; }
      open_firewall_port "${PORT}" "tcp" ""
      ;;
    3)
      ensure_ss_ready || return 1
      show_firewall_advice "${SS_PORT}" "tcp,udp" "${SS_ALLOW_SOURCE:-}"
      ;;
    4)
      ensure_ss_ready || return 1
      open_firewall_port "${SS_PORT}" "tcp,udp" "${SS_ALLOW_SOURCE:-}"
      ;;
    0)
      return 0
      ;;
    *)
      warn "无效选择。"
      ;;
  esac
}

show_firewall_advice() {
  local port="$1"
  local proto="${2:-tcp}"
  local source="${3:-}"
  local nft_chain=""

  print_title "防火墙检查"
  if command_exists ufw; then
    printf 'ufw: %s\n' "$(ufw status 2>/dev/null | head -n 1 || echo "未知")"
  else
    printf 'ufw: 未安装\n'
  fi

  if command_exists firewall-cmd; then
    if firewall-cmd --state >/dev/null 2>&1; then
      printf 'firewalld: running\n'
    else
      printf 'firewalld: 未运行或不可用\n'
    fi
  else
    printf 'firewalld: 未安装\n'
  fi

  if command_exists nft; then
    nft_chain="$(detect_nft_input_chain || true)"
    if [[ -n "${nft_chain}" ]]; then
      printf 'nftables input chain: %s\n' "${nft_chain}"
    else
      printf 'nftables: 未发现现有 input hook 链\n'
    fi
  else
    printf 'nftables: 未安装\n'
  fi

  if command_exists iptables; then
    printf 'iptables INPUT policy: '
    iptables -S INPUT 2>/dev/null | awk 'NR==1 {print; found=1} END {if (!found) print "未知"}'
  else
    printf 'iptables: 未安装\n'
  fi

  cat <<EOF

常见放行命令:
  ufw allow ${port}/tcp
  firewall-cmd --permanent --add-port=${port}/tcp && firewall-cmd --reload
  iptables -I INPUT -p tcp --dport ${port} -j ACCEPT
EOF

  if [[ "${proto}" == "tcp,udp" ]]; then
    cat <<EOF
  ufw allow ${port}/udp
  firewall-cmd --permanent --add-port=${port}/udp && firewall-cmd --reload
  iptables -I INPUT -p udp --dport ${port} -j ACCEPT
EOF
  fi

  if [[ -n "${source}" ]]; then
    cat <<EOF

当前配置的允许来源: ${source}
如需限制来源，请按实际防火墙工具追加源地址条件。
EOF
  fi

  cat <<EOF

如果 VPS 面板或云厂商有安全组，还需要在控制台放行 ${port}/${proto}。
EOF
}

detect_nft_input_chain() {
  command_exists nft || return 1
  nft -a list ruleset 2>/dev/null | awk '
    /^table[[:space:]]+/ {
      family=$2
      table=$3
      next
    }
    /^[[:space:]]*chain[[:space:]]+/ {
      chain=$2
      in_chain=1
      hook_input=0
      next
    }
    in_chain && /hook[[:space:]]+input/ {
      hook_input=1
    }
    in_chain && /^[[:space:]]*}/ {
      if (hook_input && family != "" && table != "" && chain != "") {
        print family " " table " " chain
        exit
      }
      in_chain=0
      hook_input=0
    }
  '
}

open_firewall_port() {
  local port="$1"
  local proto="${2:-tcp}"
  local source="${3:-}"
  local nft_chain family table chain
  if command_exists ufw && ufw status 2>/dev/null | grep -qi active; then
    ufw allow "${port}/tcp"
    [[ "${proto}" == "tcp,udp" ]] && ufw allow "${port}/udp"
    success "已通过 ufw 放行 ${port}/${proto}。"
    return 0
  fi

  if command_exists firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port="${port}/tcp"
    [[ "${proto}" == "tcp,udp" ]] && firewall-cmd --permanent --add-port="${port}/udp"
    firewall-cmd --reload
    success "已通过 firewalld 放行 ${port}/${proto}。"
    return 0
  fi

  if command_exists nft; then
    nft_chain="$(detect_nft_input_chain || true)"
    if [[ -n "${nft_chain}" ]]; then
      read -r family table chain <<< "${nft_chain}"
      if [[ -n "${source}" ]]; then
        nft add rule "${family}" "${table}" "${chain}" ip saddr "${source}" tcp dport "${port}" accept
        [[ "${proto}" == "tcp,udp" ]] && nft add rule "${family}" "${table}" "${chain}" ip saddr "${source}" udp dport "${port}" accept
      else
        nft add rule "${family}" "${table}" "${chain}" tcp dport "${port}" accept
        [[ "${proto}" == "tcp,udp" ]] && nft add rule "${family}" "${table}" "${chain}" udp dport "${port}" accept
      fi
      success "已向 nftables ${family} ${table} ${chain} 添加 ${port}/${proto} 临时放行规则。持久化请写入系统当前 nftables 配置。"
      return 0
    fi
  fi

  if command_exists iptables; then
    if [[ -n "${source}" ]]; then
      iptables -C INPUT -p tcp -s "${source}" --dport "${port}" -j ACCEPT 2>/dev/null || \
        iptables -I INPUT -p tcp -s "${source}" --dport "${port}" -j ACCEPT
      if [[ "${proto}" == "tcp,udp" ]]; then
        iptables -C INPUT -p udp -s "${source}" --dport "${port}" -j ACCEPT 2>/dev/null || \
          iptables -I INPUT -p udp -s "${source}" --dport "${port}" -j ACCEPT
      fi
    else
      iptables -C INPUT -p tcp --dport "${port}" -j ACCEPT 2>/dev/null || \
        iptables -I INPUT -p tcp --dport "${port}" -j ACCEPT
      if [[ "${proto}" == "tcp,udp" ]]; then
        iptables -C INPUT -p udp --dport "${port}" -j ACCEPT 2>/dev/null || \
          iptables -I INPUT -p udp --dport "${port}" -j ACCEPT
      fi
    fi
    success "已通过 iptables 放行 ${port}/${proto}。持久化请使用系统对应工具保存。"
    return 0
  fi

  if command_exists nft; then
    warn "检测到 nftables，但没有找到可安全追加规则的 input hook 链。"
    warn "请先查看规则集：nft list ruleset"
    warn "如果系统默认 ACCEPT，可能无需本机放行；否则请按实际表/链手动添加 ${port}/${proto} accept。"
    return 0
  fi

  warn "未识别到可自动处理的本机防火墙。"
  warn "如果连接不通，请优先检查云厂商安全组 / VPS 面板防火墙是否放行 ${port}/${proto}。"
}

uninstall_feature() {
  print_title "卸载 ${FEATURE_NAME}"
  warn "此操作只删除 ${APP_ROOT} 下本 sidecar 文件和 ${SERVICE_NAME}.service，不会删除 /root/agsbx。"
  confirm_yes "确认卸载" || return 0

  stop_service
  if [[ "${HAS_SYSTEMD}" == "1" ]]; then
    systemctl disable "${SERVICE_NAME}" >/dev/null 2>&1 || true
    rm -f "${SERVICE_FILE}"
    systemctl daemon-reload
  else
    remove_cron_reboot
  fi

  case "${FEATURE_DIR}" in
    "${APP_ROOT}/"*) rm -rf "${FEATURE_DIR}" ;;
    *) err "安全检查失败，拒绝删除异常目录: ${FEATURE_DIR}"; return 1 ;;
  esac
  success "已卸载 ${FEATURE_NAME}。${APP_ROOT} 根目录保留，便于未来扩展。"
}

main() {
  local choice
  setup_colors
  check_root
  detect_init_system

  while true; do
    print_dashboard
    print_main_menu
    read -r -p "请选择: " choice
    case "${choice}" in
      1) show_preflight; pause_before_return ;;
      2) install_or_repair_xray_core; pause_before_return ;;
      3) sync_xray_from_argosbx; pause_before_return ;;
      4) install_or_repair_vless; pause_before_return ;;
      5) install_or_repair_ss; pause_before_return ;;
      6) show_links; pause_before_return ;;
      7) show_detail_status; pause_before_return ;;
      8) vless_settings_menu ;;
      9) ss_settings_menu ;;
      10) rewrite_and_restart; pause_before_return ;;
      11) service_control_menu ;;
      12) test_menu ;;
      13) show_logs; pause_before_return ;;
      14) firewall_menu; pause_before_return ;;
      15) uninstall_feature; pause_before_return ;;
      0) exit 0 ;;
      *) warn "无效选择。" ;;
    esac
  done
}

main "$@"
