#!/usr/bin/env bash
set -euo pipefail

SCRIPT_VERSION="2026.07.29+build.1"
SCRIPT_RELEASE_DATE="2026-07-29"

# CHANGELOG_BEGIN
# - managed 模式使用安全持久化路径，并在 live apply 前预检最终启动配置组合。
# - 组件只接收干净环境和白名单变量，远端脚本执行前强制 SHA256 与语法检查。
# - sidecar 刷新改为同目录原子替换，私有实例和临时文件增加权限保护。
# - 状态、防火墙渲染和单独应用防火墙时不再读取组件敏感配置。
# - Proxy Gateway Plus inventory 支持高级 QUIC mark 和策略路由意图。
# CHANGELOG_END

PROGRAM_NAME="${0##*/}"
INVENTORY_PATH=""
INVENTORY_DIR=""
COMMAND=""
TEMP_FILES=()
TEMP_DIR=""
NEW_TEMP_FILE=""
NFTABLES_MAIN_CONFIG="${PROXY_STACK_NFTABLES_MAIN_CONFIG:-/etc/nftables.conf}"
NFTABLES_POLICY_FILE="${PROXY_STACK_NFTABLES_POLICY_FILE:-/etc/nftables.d/vps-toolkit-proxy-stack.nft}"
PERSISTENCE_MAIN_BACKUP=""
PERSISTENCE_POLICY_BACKUP=""
PERSISTENCE_POLICY_EXISTED=0
PERSISTENCE_PREPARED=0
PERSISTENCE_COMMITTED=0
PERSISTENCE_RESTORE_FAILED=0
MUTATION_LOCK_FILE="/run/lock/vps-toolkit-proxy-stack.lock"
MUTATION_LOCK_FD=""
readonly COMPONENT_EXEC_PATH="/root/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
readonly COMPONENT_EXEC_HOME="/root"
readonly ARGOSBX_MANAGEMENT_PATH="/root/bin/agsbx"
readonly PDG_MANAGEMENT_PATH="/usr/local/bin/pdg"

declare -A CONFIG=()
declare -a COMPONENT_ENV=()
declare -a SERVICE_OWNERS=()
declare -a SERVICE_NAMES=()
declare -a SERVICE_PROTOCOLS=()
declare -a SERVICE_PORTS=()
declare -a SERVICE_SOURCES=()

die() {
  printf '[错误] %s\n' "$*" >&2
  exit 1
}

info() {
  printf '[信息] %s\n' "$*"
}

warn() {
  printf '[警告] %s\n' "$*" >&2
}

cleanup() {
  local original_status=$? path
  if [[ "${PERSISTENCE_PREPARED:-0}" == "1" \
      && "${PERSISTENCE_COMMITTED:-0}" == "0" ]]; then
    rollback_firewall_persistence \
      || warn "退出时未能恢复持久化 before-image，请立即人工检查 nftables 配置。"
  fi
  for path in "${TEMP_FILES[@]}"; do
    [[ -n "$path" ]] && rm -f -- "$path"
  done
  if [[ -n "${TEMP_DIR:-}" ]]; then
    rmdir -- "$TEMP_DIR" 2>/dev/null \
      || warn "临时目录未能清空，请人工检查。"
  fi
  return "$original_status"
}
trap cleanup EXIT

usage() {
  cat <<EOF
用法：
  ${PROGRAM_NAME} --inventory FILE validate
  ${PROGRAM_NAME} --inventory FILE plan
  ${PROGRAM_NAME} --inventory FILE deploy
  ${PROGRAM_NAME} --inventory FILE status
  ${PROGRAM_NAME} --inventory FILE render-firewall
  ${PROGRAM_NAME} --inventory FILE firewall-apply
  ${PROGRAM_NAME} --version
  ${PROGRAM_NAME} --changelog
  ${PROGRAM_NAME} --help

实例 inventory 只保存于部署侧，不要提交密码、Token、私钥或节点链接。
自定义防火墙持久化路径只接受不含空白或通配符的规范绝对路径。
EOF
}

show_changelog() {
  cat <<'EOF'
2026.07.29+build.1
- managed 模式使用安全持久化路径，并在 live apply 前预检最终启动配置组合。
- 组件只接收干净环境和白名单变量，远端脚本执行前强制 SHA256 与语法检查。
- sidecar 刷新改为同目录原子替换，私有实例和临时文件增加权限保护。
- 状态、防火墙渲染和单独应用防火墙时不再读取组件敏感配置。
- Proxy Gateway Plus inventory 支持高级 QUIC mark 和策略路由意图。
EOF
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

contains_control_character() {
  local value="$1"
  local LC_ALL=C
  [[ "$value" == *[[:cntrl:]]* ]]
}

contains_unsafe_argosbx_character() {
  local value="$1"
  [[ "$value" == *'"'* || "$value" == *'\'* \
    || "$value" == *'$'* || "$value" == *'`'* ]]
}

run_component_clean() {
  local -a clean_env=(
    env -i
    "PATH=${COMPONENT_EXEC_PATH}"
    "HOME=${COMPONENT_EXEC_HOME}"
  )
  [[ -z "${LANG-}" ]] || clean_env+=("LANG=${LANG}")
  [[ -z "${TERM-}" ]] || clean_env+=("TERM=${TERM}")
  "${clean_env[@]}" "$@"
}

warn_if_file_not_private() {
  local path="$1" label="$2" mode access_bits access_value
  mode="$(stat -Lc '%a' -- "$path" 2>/dev/null)" || {
    warn "无法检查${label}的访问权限；请确认只有受信任用户可读取。"
    return 0
  }
  [[ "$mode" =~ ^[0-7]{3,4}$ ]] || {
    warn "无法识别${label}的访问权限；请确认只有受信任用户可读取。"
    return 0
  }
  access_bits="${mode: -3}"
  access_value=$((8#$access_bits))
  if (( (access_value & 077) != 0 )); then
    warn "${label}可被组或其他用户访问；包含实例值或凭据时建议 chmod 600。"
  fi
}

require_private_regular_file() {
  local path="$1" label="$2" mode access_bits access_value
  [[ -f "$path" && ! -L "$path" ]] \
    || die "${label}必须是普通非 symlink 文件。"
  mode="$(stat -c '%a' -- "$path" 2>/dev/null)" \
    || die "无法检查${label}的访问权限。"
  [[ "$mode" =~ ^[0-7]{3,4}$ ]] \
    || die "无法识别${label}的访问权限。"
  access_bits="${mode: -3}"
  access_value=$((8#$access_bits))
  (( (access_value & 077) == 0 )) \
    || die "${label}包含组件实例值或凭据；请先 chmod 600。"
}

require_canonical_absolute_path() {
  local path="$1" label="$2"
  contains_control_character "$path" \
    && die "${label}路径不可包含控制字符。"
  [[ "$path" == /* ]] \
    || die "${label}必须使用规范绝对路径。"
  case "$path" in
    *//*|*/./*|*/../*|*/.|*/..)
      die "${label}必须使用不含相对路径段或重复斜杠的规范绝对路径。"
      ;;
  esac
}

require_root_owned_directory_chain() {
  local directory="$1" label="$2" mode owner access_bits access_value parent
  require_canonical_absolute_path "$directory" "${label}目录链"
  while :; do
    [[ -d "$directory" && ! -L "$directory" ]] \
      || die "${label}目录链必须是普通非 symlink 目录。"
    mode="$(stat -c '%a' -- "$directory" 2>/dev/null)" \
      || die "无法检查${label}目录权限。"
    owner="$(stat -c '%u' -- "$directory" 2>/dev/null)" \
      || die "无法检查${label}目录所有者。"
    [[ "$mode" =~ ^[0-7]{3,4}$ && "$owner" == "0" ]] \
      || die "${label}目录链必须由 root 所有。"
    access_bits="${mode: -3}"
    access_value=$((8#$access_bits))
    (( (access_value & 022) == 0 )) \
      || die "${label}目录链不可由组或其他用户写入。"
    [[ "$directory" == "/" ]] && break
    parent="$(dirname -- "$directory")"
    [[ "$parent" != "$directory" ]] \
      || die "无法验证${label}目录链。"
    directory="$parent"
  done
}

require_root_owned_creation_parent_chain() {
  local directory="$1" label="$2" parent
  require_canonical_absolute_path "$directory" "${label}目录链"
  while [[ ! -e "$directory" && ! -L "$directory" ]]; do
    parent="$(dirname -- "$directory")"
    [[ "$parent" != "$directory" ]] \
      || die "无法找到${label}的可信现有父目录。"
    directory="$parent"
  done
  require_root_owned_directory_chain "$directory" "$label"
}

require_trusted_root_owned_file() {
  local path="$1" label="$2" mode owner access_bits access_value
  require_canonical_absolute_path "$path" "$label"
  [[ -f "$path" && ! -L "$path" ]] \
    || die "${label}必须是普通非 symlink 文件。"
  mode="$(stat -c '%a' -- "$path" 2>/dev/null)" \
    || die "无法检查${label}的访问权限。"
  owner="$(stat -c '%u' -- "$path" 2>/dev/null)" \
    || die "无法检查${label}的所有者。"
  [[ "$mode" =~ ^[0-7]{3,4}$ && "$owner" == "0" ]] \
    || die "${label}必须由 root 所有。"
  access_bits="${mode: -3}"
  access_value=$((8#$access_bits))
  (( (access_value & 022) == 0 )) \
    || die "${label}不可由组或其他用户写入。"
  require_root_owned_directory_chain "$(dirname -- "$path")" "$label"
}

require_root_owned_mutation_input() {
  require_trusted_root_owned_file "$1" "变更时${2}"
}

assert_safe_root_management_entry() {
  local target="$1" label="$2"
  require_trusted_root_owned_file "$target" "$label"
  [[ -x "$target" ]] || die "${label}必须是可执行文件。"
}

assert_existing_sidecar_target() {
  assert_safe_root_management_entry "$1" "已有 sidecar 管理入口"
}

is_allowed_config_key() {
  case "$1" in
    STACK_INVENTORY_VERSION|HOST_FIREWALL_MODE|HOST_FIREWALL_POLICY|\
    HOST_FIREWALL_PERSIST|HOST_FIREWALL_ALLOW_ICMP|REMOTE_ADMIN_SERVICE|\
    SERVICES_FILE|ARGOSBX_ENABLED|ARGOSBX_SOURCE_URL|ARGOSBX_SOURCE_SHA256|\
    ARGOSBX_VARIABLES_FILE|ARGOSBX_EXISTING_ACTION|PDG_ENABLED|\
    PDG_INSTALL_URL|PDG_INSTALL_SHA256|PDG_ENV_FILE|PDG_EXISTING_ACTION|\
    SIDECAR_ENABLED|SIDECAR_SOURCE_URL|SIDECAR_SOURCE_SHA256|\
    SIDECAR_INSTALL_PATH|SIDECAR_EXISTING_ACTION|SIDECAR_RUN_MODE)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

load_inventory() {
  local raw line key value line_number=0
  [[ -n "$INVENTORY_PATH" ]] || die "必须通过 --inventory 指定实例配置。"
  [[ -f "$INVENTORY_PATH" ]] || die "找不到 inventory：${INVENTORY_PATH}"
  INVENTORY_DIR="$(cd -- "$(dirname -- "$INVENTORY_PATH")" && pwd -P)"
  case "$COMMAND" in
    deploy|firewall-apply)
      require_root_owned_mutation_input "$INVENTORY_PATH" "inventory"
      ;;
    *) warn_if_file_not_private "$INVENTORY_PATH" "inventory" ;;
  esac

  while IFS= read -r raw || [[ -n "$raw" ]]; do
    line_number=$((line_number + 1))
    line="${raw%$'\r'}"
    line="$(trim "$line")"
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" == *=* ]] \
      || die "inventory 第 ${line_number} 行不是 KEY=VALUE。"
    key="$(trim "${line%%=*}")"
    value="$(trim "${line#*=}")"
    [[ "$key" =~ ^[A-Z][A-Z0-9_]*$ ]] \
      || die "inventory 第 ${line_number} 行的 key 无效。"
    is_allowed_config_key "$key" \
      || die "inventory 包含未知 key：${key}"
    [[ -z "${CONFIG[$key]+present}" ]] \
      || die "inventory 包含重复 key：${key}"
    contains_control_character "$value" \
      && die "inventory 的 ${key} 包含控制字符。"
    CONFIG["$key"]="$value"
  done < "$INVENTORY_PATH"
}

config_default() {
  local key="$1" value="$2"
  if [[ -z "${CONFIG[$key]+present}" ]]; then
    CONFIG["$key"]="$value"
  fi
}

config_required() {
  local key="$1"
  [[ -n "${CONFIG[$key]-}" ]] || die "inventory 缺少 ${key}。"
}

validate_bool() {
  local key="$1"
  [[ "${CONFIG[$key]}" == "0" || "${CONFIG[$key]}" == "1" ]] \
    || die "${key} 只能是 0 或 1。"
}

resolve_inventory_path() {
  local value="$1"
  [[ -n "$value" ]] || return 1
  case "$value" in
    /*) printf '%s\n' "$value" ;;
    *) printf '%s/%s\n' "$INVENTORY_DIR" "$value" ;;
  esac
}

validate_https_url() {
  local key="$1" value="${CONFIG[$1]-}"
  [[ "$value" =~ ^https://[^[:space:]]+$ ]] \
    || die "${key} 必须是 https URL。"
}

validate_sha256() {
  local key="$1" value="${CONFIG[$1]-}"
  [[ "$value" =~ ^[0-9a-fA-F]{64}$ ]] \
    || die "${key} 必须填写 64 位 SHA256。"
}

apply_defaults_and_validate() {
  config_default STACK_INVENTORY_VERSION "1"
  config_default HOST_FIREWALL_MODE "managed"
  config_default HOST_FIREWALL_POLICY "drop"
  config_default HOST_FIREWALL_PERSIST "1"
  config_default HOST_FIREWALL_ALLOW_ICMP "1"
  config_default REMOTE_ADMIN_SERVICE ""
  config_default SERVICES_FILE ""

  config_default ARGOSBX_ENABLED "0"
  config_default ARGOSBX_SOURCE_URL ""
  config_default ARGOSBX_SOURCE_SHA256 ""
  config_default ARGOSBX_VARIABLES_FILE ""
  config_default ARGOSBX_EXISTING_ACTION "skip"

  config_default PDG_ENABLED "0"
  config_default PDG_INSTALL_URL ""
  config_default PDG_INSTALL_SHA256 ""
  config_default PDG_ENV_FILE ""
  config_default PDG_EXISTING_ACTION "migrate"

  config_default SIDECAR_ENABLED "0"
  config_default SIDECAR_SOURCE_URL ""
  config_default SIDECAR_SOURCE_SHA256 ""
  config_default SIDECAR_INSTALL_PATH \
    "/usr/local/sbin/vless-raw-enc-argosbx-enhancer"
  config_default SIDECAR_EXISTING_ACTION "keep"
  config_default SIDECAR_RUN_MODE "interactive"

  [[ "${CONFIG[STACK_INVENTORY_VERSION]}" == "1" ]] \
    || die "不支持的 STACK_INVENTORY_VERSION。"
  case "${CONFIG[HOST_FIREWALL_MODE]}" in
    managed|external) ;;
    *) die "HOST_FIREWALL_MODE 只能是 managed 或 external。" ;;
  esac
  case "${CONFIG[HOST_FIREWALL_POLICY]}" in
    drop|accept) ;;
    *) die "HOST_FIREWALL_POLICY 只能是 drop 或 accept。" ;;
  esac
  validate_bool HOST_FIREWALL_PERSIST
  validate_bool HOST_FIREWALL_ALLOW_ICMP
  validate_bool ARGOSBX_ENABLED
  validate_bool PDG_ENABLED
  validate_bool SIDECAR_ENABLED

  case "${CONFIG[ARGOSBX_EXISTING_ACTION]}" in
    skip|rep) ;;
    *) die "ARGOSBX_EXISTING_ACTION 只能是 skip 或 rep。" ;;
  esac
  case "${CONFIG[PDG_EXISTING_ACTION]}" in
    skip|migrate|update) ;;
    *) die "PDG_EXISTING_ACTION 只能是 skip、migrate 或 update。" ;;
  esac
  case "${CONFIG[SIDECAR_EXISTING_ACTION]}" in
    keep|refresh) ;;
    *) die "SIDECAR_EXISTING_ACTION 只能是 keep 或 refresh。" ;;
  esac
  case "${CONFIG[SIDECAR_RUN_MODE]}" in
    install-only|interactive) ;;
    *) die "SIDECAR_RUN_MODE 只能是 install-only 或 interactive。" ;;
  esac

  config_required SERVICES_FILE
  if [[ "${CONFIG[HOST_FIREWALL_MODE]}" == "managed" \
      && "${CONFIG[HOST_FIREWALL_POLICY]}" == "drop" ]]; then
    config_required REMOTE_ADMIN_SERVICE
    [[ "${CONFIG[REMOTE_ADMIN_SERVICE]}" =~ ^[A-Za-z0-9_.-]{1,48}$ ]] \
      || die "REMOTE_ADMIN_SERVICE 无效。"
  fi

  if [[ "${CONFIG[ARGOSBX_ENABLED]}" == "1" ]]; then
    config_required ARGOSBX_SOURCE_URL
    config_required ARGOSBX_SOURCE_SHA256
    config_required ARGOSBX_VARIABLES_FILE
    validate_https_url ARGOSBX_SOURCE_URL
    [[ "${CONFIG[ARGOSBX_SOURCE_URL]}" == \
      "https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh" ]] \
      || die "Argosbx 只允许使用 yonggekkk/argosbx 官方脚本 URL。"
    validate_sha256 ARGOSBX_SOURCE_SHA256
  fi
  if [[ "${CONFIG[PDG_ENABLED]}" == "1" ]]; then
    config_required PDG_INSTALL_URL
    config_required PDG_INSTALL_SHA256
    config_required PDG_ENV_FILE
    validate_https_url PDG_INSTALL_URL
    [[ "${CONFIG[PDG_INSTALL_URL]}" == \
      "https://raw.githubusercontent.com/SchweppesSoda/proxy-gateway-plus/main/install.sh" ]] \
      || die "Proxy Gateway Plus 只允许使用本项目官方 install.sh URL。"
    validate_sha256 PDG_INSTALL_SHA256
  fi
  if [[ "${CONFIG[SIDECAR_ENABLED]}" == "1" ]]; then
    config_required SIDECAR_SOURCE_URL
    config_required SIDECAR_SOURCE_SHA256
    validate_https_url SIDECAR_SOURCE_URL
    [[ "${CONFIG[SIDECAR_SOURCE_URL]}" == \
      "https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer.sh" ]] \
      || die "sidecar 只允许使用 VPS-Toolkit 官方脚本 URL。"
    validate_sha256 SIDECAR_SOURCE_SHA256
    [[ "${CONFIG[SIDECAR_INSTALL_PATH]}" == \
      "/usr/local/sbin/vless-raw-enc-argosbx-enhancer" ]] \
      || die "sidecar 只允许安装到项目标准管理路径。"
  fi
}

is_allowed_argosbx_key() {
  case "$1" in
    vlpt|vmpt|vwpt|hypt|tupt|xhpt|vxpt|anpt|sspt|arpt|sopt|nvpt|\
    xupt|xcpt|uuid|reym|cdnym|argo|agn|agk|ippz|warp|name|oap)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_allowed_pdg_key() {
  case "$1" in
    PDG_SERVER_IP|PDG_SSH_PORT|PDG_INTERNAL_CIDR|PDG_PLATFORM|\
    PDG_FIREWALL_MODE|PDG_QUIC_MODE|PDG_HIJACK_MODE|\
    PDG_HIJACK_TLS_TCP_PORTS|PDG_HIJACK_HTTP_TCP_PORTS|\
    PDG_BOT_TOKEN|PDG_ALLOWED|PDG_DOT_DOMAIN|PDG_SKIP_CERT|\
    PDG_LOWMEM|PDG_REPO_URL|PDG_QUIC_MARK|PDG_QUIC_MARK_MASK|\
    PDG_QUIC_ROUTE_TABLE|PDG_QUIC_RULE_PRIORITY)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

load_component_env() {
  local kind="$1" path="$2"
  local raw line key value line_number=0
  local -A seen=()
  COMPONENT_ENV=()
  [[ -f "$path" ]] || die "找不到 ${kind} 配置：${path}"
  require_private_regular_file "$path" "${kind} 配置"
  if [[ "$COMMAND" == "deploy" ]]; then
    require_root_owned_mutation_input "$path" "${kind} 配置"
  fi

  while IFS= read -r raw || [[ -n "$raw" ]]; do
    line_number=$((line_number + 1))
    line="${raw%$'\r'}"
    line="$(trim "$line")"
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" == *=* ]] \
      || die "${kind} 配置第 ${line_number} 行不是 KEY=VALUE。"
    key="$(trim "${line%%=*}")"
    value="$(trim "${line#*=}")"
    [[ -n "$key" && -n "$value" ]] \
      || die "${kind} 配置第 ${line_number} 行不能为空。"
    [[ -z "${seen[$key]+present}" ]] \
      || die "${kind} 配置包含重复 key：${key}"
    case "$kind" in
      argosbx)
        is_allowed_argosbx_key "$key" \
          || die "Argosbx 配置包含未知 key：${key}"
        ;;
      pdg)
        is_allowed_pdg_key "$key" \
          || die "Proxy Gateway Plus 配置包含未知 key：${key}"
        ;;
      *)
        die "内部组件类型无效。"
        ;;
    esac
    contains_control_character "$value" \
      && die "${kind} 配置的 ${key} 包含控制字符。"
    if [[ "$kind" == "argosbx" ]]; then
      case "$key" in
        vlpt|vmpt|vwpt|hypt|tupt|xhpt|vxpt|anpt|sspt|arpt|sopt|\
        nvpt|xupt|xcpt)
          [[ "$value" =~ ^(0|[1-9][0-9]{0,4})$ ]] \
            || die "Argosbx 的 ${key} 必须是十进制端口。"
          (( value >= 1 && value <= 65535 )) \
            || die "Argosbx 的 ${key} 超出端口范围。"
          ;;
        *)
          contains_unsafe_argosbx_character "$value" \
            && die "Argosbx 的 ${key} 包含可能污染上游持久配置的不安全字符。"
          ;;
      esac
    fi
    if [[ "$kind" == "pdg" && "$key" == "PDG_REPO_URL" ]]; then
      [[ "$value" == \
        "https://github.com/SchweppesSoda/proxy-gateway-plus.git" ]] \
        || die "PDG_REPO_URL 只允许本 fork 的官方 Git URL。"
    fi
    seen["$key"]=1
    COMPONENT_ENV+=("${key}=${value}")
  done < "$path"

  if [[ "$kind" == "argosbx" ]]; then
    local has_protocol=0 item
    for item in "${COMPONENT_ENV[@]}"; do
      case "${item%%=*}" in
        vlpt|vmpt|vwpt|hypt|tupt|xhpt|vxpt|anpt|sspt|arpt|sopt|\
        nvpt|xupt|xcpt)
          has_protocol=1
          ;;
      esac
    done
    [[ "$has_protocol" == "1" ]] \
      || die "Argosbx 配置至少要声明一个协议端口变量。"
  fi

  if [[ "$kind" == "pdg" ]]; then
    local firewall_value="" item
    for item in "${COMPONENT_ENV[@]}"; do
      if [[ "${item%%=*}" == "PDG_FIREWALL_MODE" ]]; then
        firewall_value="${item#*=}"
      fi
    done
    [[ "$firewall_value" == "external" ]] \
      || die "Proxy Gateway Plus 必须显式配置 PDG_FIREWALL_MODE=external。"
  fi
}

valid_source_cidr() {
  local value="$1"
  run_component_clean python3 -I - "$value" <<'PY'
import ipaddress
import sys

value = sys.argv[1]
try:
    network = ipaddress.ip_network(value, strict=True)
except ValueError:
    raise SystemExit(1)
raise SystemExit(0 if str(network) == value else 1)
PY
}

valid_ip_address() {
  local value="$1"
  run_component_clean python3 -I - "$value" <<'PY'
import ipaddress
import sys

try:
    ipaddress.ip_address(sys.argv[1])
except ValueError:
    raise SystemExit(1)
PY
}

ip_in_source_cidrs() {
  local address="$1" sources="$2"
  run_component_clean python3 -I - "$address" "$sources" <<'PY'
import ipaddress
import sys

address = ipaddress.ip_address(sys.argv[1])
networks = (ipaddress.ip_network(item.strip(), strict=True)
            for item in sys.argv[2].split(','))
raise SystemExit(0 if any(address in network for network in networks) else 1)
PY
}

validate_active_ssh_remote_admin() {
  local index client_ip client_port server_ip server_port matched=0
  local -a ssh_fields=()
  [[ "${CONFIG[HOST_FIREWALL_MODE]}" == "managed" \
      && "${CONFIG[HOST_FIREWALL_POLICY]}" == "drop" ]] || return 0
  case "$COMMAND" in
    deploy|firewall-apply) ;;
    *) return 0 ;;
  esac
  if [[ -z "${SSH_CONNECTION-}" ]]; then
    warn "未检测到当前 SSH 会话；请从控制台或恢复通道确认远程管理放行规则。"
    return 0
  fi
  contains_control_character "$SSH_CONNECTION" \
    && die "SSH_CONNECTION 格式无效，拒绝应用 drop policy。"
  read -r -a ssh_fields <<< "$SSH_CONNECTION"
  [[ "${#ssh_fields[@]}" -eq 4 ]] \
    || die "SSH_CONNECTION 必须恰有 4 个字段，拒绝应用 drop policy。"
  client_ip="${ssh_fields[0]}"
  client_port="${ssh_fields[1]}"
  server_ip="${ssh_fields[2]}"
  server_port="${ssh_fields[3]}"
  valid_ip_address "$client_ip" && valid_ip_address "$server_ip" \
    || die "SSH_CONNECTION 包含无效 IP，拒绝应用 drop policy。"
  [[ "$client_port" =~ ^(0|[1-9][0-9]{0,4})$ \
      && "$server_port" =~ ^(0|[1-9][0-9]{0,4})$ ]] \
    || die "SSH_CONNECTION 包含无效端口，拒绝应用 drop policy。"
  (( client_port >= 1 && client_port <= 65535 \
      && server_port >= 1 && server_port <= 65535 )) \
    || die "SSH_CONNECTION 端口超出范围，拒绝应用 drop policy。"

  for ((index = 0; index < ${#SERVICE_NAMES[@]}; index++)); do
    [[ "${SERVICE_OWNERS[$index]}" == "host" \
        && "${SERVICE_NAMES[$index]}" == "${CONFIG[REMOTE_ADMIN_SERVICE]}" ]] \
      || continue
    case "${SERVICE_PROTOCOLS[$index]}" in
      tcp)
        [[ "${SERVICE_PORTS[$index]}" == "$server_port" ]] || continue
        ;;
      any)
        [[ "${SERVICE_PORTS[$index]}" == "*" ]] || continue
        ;;
      *) continue ;;
    esac
    if ip_in_source_cidrs "$client_ip" "${SERVICE_SOURCES[$index]}"; then
      matched=1
      break
    fi
  done
  [[ "$matched" == "1" ]] \
    || die "当前 SSH 来源与 REMOTE_ADMIN_SERVICE 放行声明不匹配；拒绝应用 drop policy。"
}

load_services() {
  local path raw line owner name protocol port sources extra line_number=0
  local source owner_enabled line_without_tabs tab_count
  local -a source_list
  local -A rows=()
  local remote_admin_found=0
  SERVICE_OWNERS=()
  SERVICE_NAMES=()
  SERVICE_PROTOCOLS=()
  SERVICE_PORTS=()
  SERVICE_SOURCES=()

  command -v python3 >/dev/null 2>&1 \
    || die "服务清单校验需要系统 python3。"
  path="$(resolve_inventory_path "${CONFIG[SERVICES_FILE]}")"
  [[ -f "$path" ]] || die "找不到服务清单：${path}"
  case "$COMMAND" in
    deploy|firewall-apply)
      require_root_owned_mutation_input "$path" "服务清单"
      ;;
    *) warn_if_file_not_private "$path" "服务清单" ;;
  esac

  while IFS= read -r raw || [[ -n "$raw" ]]; do
    line_number=$((line_number + 1))
    line="${raw%$'\r'}"
    [[ -z "$(trim "$line")" || "$(trim "$line")" == \#* ]] && continue
    line_without_tabs="${line//$'\t'/}"
    tab_count=$((${#line} - ${#line_without_tabs}))
    (( tab_count == 4 )) \
      || die "服务清单第 ${line_number} 行必须恰有 5 个 TAB 分隔字段。"
    IFS=$'\t' read -r owner name protocol port sources extra <<< "$line"
    owner="$(trim "${owner-}")"
    name="$(trim "${name-}")"
    protocol="$(trim "${protocol-}")"
    port="$(trim "${port-}")"
    sources="$(trim "${sources-}")"
    [[ -n "$owner" && -n "$name" && -n "$protocol" && -n "$port" \
      && -n "$sources" && -z "${extra-}" ]] \
      || die "服务清单第 ${line_number} 行必须恰有 5 个 TAB 分隔字段。"
    for source in "$owner" "$name" "$protocol" "$port" "$sources"; do
      contains_control_character "$source" \
        && die "服务清单第 ${line_number} 行包含控制字符。"
    done
    owner_enabled=1
    case "$owner" in
      host) ;;
      argosbx)
        [[ "${CONFIG[ARGOSBX_ENABLED]}" == "1" ]] || owner_enabled=0
        ;;
      pdg)
        [[ "${CONFIG[PDG_ENABLED]}" == "1" ]] || owner_enabled=0
        ;;
      sidecar)
        [[ "${CONFIG[SIDECAR_ENABLED]}" == "1" ]] || owner_enabled=0
        ;;
      *)
        die "服务清单第 ${line_number} 行的组件只能是 host、argosbx、pdg 或 sidecar。"
        ;;
    esac
    [[ "$name" =~ ^[A-Za-z0-9_.-]{1,48}$ ]] \
      || die "服务清单第 ${line_number} 行的名称无效。"
    case "$protocol" in
      tcp|udp)
        [[ "$port" =~ ^(0|[1-9][0-9]{0,4})$ ]] \
          || die "服务 ${name} 的端口无效。"
        (( port >= 1 && port <= 65535 )) \
          || die "服务 ${name} 的端口超出范围。"
        ;;
      any)
        [[ "$port" == "*" ]] \
          || die "服务 ${name} 使用 any 协议时端口必须是 *。"
        ;;
      *)
        die "服务 ${name} 的协议只能是 tcp、udp 或 any。"
        ;;
    esac
    [[ -z "${rows["${owner}|${name}|${protocol}|${port}|${sources}"]+present}" ]] \
      || die "服务清单包含重复行：${name}"
    rows["${owner}|${name}|${protocol}|${port}|${sources}"]=1

    [[ "$sources" != ,* && "$sources" != *, && "$sources" != *,,* ]] \
      || die "服务 ${name} 的来源 CIDR 列表包含空项。"
    IFS=, read -r -a source_list <<< "$sources"
    [[ "${#source_list[@]}" -ge 1 ]] || die "服务 ${name} 没有来源 CIDR。"
    for source in "${source_list[@]}"; do
      source="$(trim "$source")"
      valid_source_cidr "$source" \
        || die "服务 ${name} 的来源 CIDR 无效：${source}"
    done

    [[ "$owner_enabled" == "1" ]] || continue
    SERVICE_OWNERS+=("$owner")
    SERVICE_NAMES+=("$name")
    SERVICE_PROTOCOLS+=("$protocol")
    SERVICE_PORTS+=("$port")
    SERVICE_SOURCES+=("$sources")
    if [[ "$name" == "${CONFIG[REMOTE_ADMIN_SERVICE]}" \
        && "$owner" == "host" \
        && ( "$protocol" == "tcp" || "$protocol" == "any" ) ]]; then
      remote_admin_found=1
    fi
  done < "$path"

  if [[ "${CONFIG[HOST_FIREWALL_MODE]}" == "managed" \
      && "${CONFIG[HOST_FIREWALL_POLICY]}" == "drop" ]]; then
    [[ "${#SERVICE_NAMES[@]}" -gt 0 ]] \
      || die "drop policy 下服务清单不能为空。"
    [[ "$remote_admin_found" == "1" ]] \
      || die "服务清单未声明 host tcp/any 类型的 REMOTE_ADMIN_SERVICE，拒绝应用 drop policy。"
  fi
}

firewall_persistence_targets_are_safe() {
  [[ -f "$NFTABLES_MAIN_CONFIG" && ! -L "$NFTABLES_MAIN_CONFIG" ]] \
    || return 1
  if [[ -e "$NFTABLES_POLICY_FILE" || -L "$NFTABLES_POLICY_FILE" ]]; then
    [[ -f "$NFTABLES_POLICY_FILE" && ! -L "$NFTABLES_POLICY_FILE" ]] \
      || return 1
  fi
}

validate_firewall_persistence_trust() {
  local policy_directory
  require_canonical_absolute_path \
    "$NFTABLES_MAIN_CONFIG" "nftables 主配置"
  require_canonical_absolute_path \
    "$NFTABLES_POLICY_FILE" "nftables 托管 policy"
  [[ "$NFTABLES_MAIN_CONFIG" =~ ^/[A-Za-z0-9._/-]+$ ]] \
    || die "nftables 主配置路径包含不安全字符。"
  [[ "$NFTABLES_POLICY_FILE" =~ ^/[A-Za-z0-9._/-]+$ ]] \
    || die "nftables 托管 policy 路径包含不安全字符。"
  firewall_persistence_targets_are_safe \
    || die "持久化 main/policy 必须是普通非 symlink 文件。"
  require_root_owned_mutation_input \
    "$NFTABLES_MAIN_CONFIG" "nftables 主配置"
  if [[ -e "$NFTABLES_POLICY_FILE" || -L "$NFTABLES_POLICY_FILE" ]]; then
    require_root_owned_mutation_input \
      "$NFTABLES_POLICY_FILE" "nftables 托管 policy"
  fi
  policy_directory="$(dirname -- "$NFTABLES_POLICY_FILE")"
  require_root_owned_creation_parent_chain \
    "$policy_directory" "nftables 托管 policy"
}

validate_component_files() {
  local path
  case "$COMMAND" in
    validate|plan|deploy) ;;
    *) return 0 ;;
  esac
  if [[ "${CONFIG[ARGOSBX_ENABLED]}" == "1" ]]; then
    path="$(resolve_inventory_path "${CONFIG[ARGOSBX_VARIABLES_FILE]}")"
    load_component_env argosbx "$path"
  fi
  if [[ "${CONFIG[PDG_ENABLED]}" == "1" ]]; then
    path="$(resolve_inventory_path "${CONFIG[PDG_ENV_FILE]}")"
    load_component_env pdg "$path"
  fi
}

validate_all() {
  load_inventory
  apply_defaults_and_validate
  validate_component_files
  load_services
  validate_active_ssh_remote_admin
}

new_temp_file() {
  if [[ -z "$TEMP_DIR" ]]; then
    TEMP_DIR="$(mktemp -d /tmp/vps-toolkit-proxy-stack.XXXXXX)" \
      || die "无法创建私有临时目录。"
    chmod 0700 "$TEMP_DIR" || die "无法设置私有临时目录权限。"
  fi
  NEW_TEMP_FILE="$(mktemp "${TEMP_DIR}/file.XXXXXX")" \
    || die "无法创建临时文件。"
  TEMP_FILES+=("$NEW_TEMP_FILE")
}

fetch_verified_script() {
  local url="$1" expected_sha="$2" destination="$3"
  local actual_sha
  command -v curl >/dev/null 2>&1 || die "部署需要 curl。"
  run_component_clean curl --disable \
    --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --max-redirs 3 -fsSL "$url" -o "$destination" \
    || die "下载远端脚本失败。"
  [[ -s "$destination" ]] || die "下载到的远端脚本为空。"
  [[ "$expected_sha" =~ ^[0-9a-fA-F]{64}$ ]] \
    || die "执行远端脚本前必须提供 64 位 SHA256。"
  command -v sha256sum >/dev/null 2>&1 || die "SHA256 校验需要 sha256sum。"
  actual_sha="$(sha256sum -- "$destination")" \
    || die "无法计算远端脚本 SHA256。"
  actual_sha="${actual_sha%% *}"
  [[ "${actual_sha,,}" == "${expected_sha,,}" ]] \
    || die "远端脚本 SHA256 与 inventory 不一致。"
  run_component_clean /bin/bash -n "$destination" \
    || die "下载到的远端脚本未通过 Bash 语法检查。"
  chmod 0700 "$destination" || die "无法设置远端脚本临时文件权限。"
}

deploy_argosbx() {
  local env_path temp
  local -a action=()
  [[ "${CONFIG[ARGOSBX_ENABLED]}" == "1" ]] || return 0

  if [[ -e "$ARGOSBX_MANAGEMENT_PATH" || -L "$ARGOSBX_MANAGEMENT_PATH" ]]; then
    assert_safe_root_management_entry \
      "$ARGOSBX_MANAGEMENT_PATH" "Argosbx 标准管理入口"
    case "${CONFIG[ARGOSBX_EXISTING_ACTION]}" in
      skip)
        info "Argosbx 已安装；按 inventory 保持现状。"
        return 0
        ;;
      rep)
        action=(rep)
        ;;
    esac
  fi

  env_path="$(resolve_inventory_path "${CONFIG[ARGOSBX_VARIABLES_FILE]}")"
  load_component_env argosbx "$env_path"
  new_temp_file
  temp="$NEW_TEMP_FILE"
  fetch_verified_script \
    "${CONFIG[ARGOSBX_SOURCE_URL]}" "${CONFIG[ARGOSBX_SOURCE_SHA256]}" "$temp"
  info "通过甬哥 Argosbx 原脚本部署；其后仍使用 agsbx 管理。"
  run_component_clean \
    "${COMPONENT_ENV[@]}" /bin/bash "$temp" "${action[@]}" \
    || die "Argosbx 官方部署或 rep 动作失败。"
  assert_safe_root_management_entry \
    "$ARGOSBX_MANAGEMENT_PATH" "Argosbx 标准管理入口"
}

assert_existing_pdg_external() {
  local marker="" profile_value="" profile_count=0 raw_marker="" grep_status=0
  local marker_file="/etc/privdns-gateway/firewall-mode"
  local profile_file="/etc/privdns-gateway/profile.env"

  if [[ -e "$marker_file" || -L "$marker_file" ]]; then
    require_trusted_root_owned_file \
      "$marker_file" "Proxy Gateway Plus firewall-mode 状态"
    raw_marker="$(cat -- "$marker_file")" \
      || die "无法读取 Proxy Gateway Plus firewall-mode 状态。"
    marker="$(trim "$raw_marker")"
  fi
  if [[ -e "$profile_file" || -L "$profile_file" ]]; then
    require_trusted_root_owned_file \
      "$profile_file" "Proxy Gateway Plus profile.env"
    grep_status=0
    profile_count="$(grep -c -- '^[[:space:]]*PDG_FIREWALL_MODE=' \
      "$profile_file" 2>/dev/null)" || grep_status=$?
    (( grep_status <= 1 )) \
      || die "无法读取 Proxy Gateway Plus profile.env。"
    (( profile_count <= 1 )) \
      || die "现有 Proxy Gateway Plus 存在重复防火墙模式，拒绝继续。"
    profile_value="$(sed -n \
      's/^[[:space:]]*PDG_FIREWALL_MODE=[[:space:]]*//p' \
      -- "$profile_file")" \
      || die "无法解析 Proxy Gateway Plus profile.env。"
    profile_value="$(trim "$profile_value")"
  fi
  if [[ -n "$marker" && -n "$profile_value" && "$marker" != "$profile_value" ]]; then
    die "现有 Proxy Gateway Plus 防火墙模式状态不一致，拒绝继续。"
  fi
  [[ "${marker:-$profile_value}" == "external" ]] \
    || die "现有 Proxy Gateway Plus 不是可证明的 external 模式，拒绝由本编排器接管整机 input policy。"
}

deploy_pdg() {
  local env_path temp
  [[ "${CONFIG[PDG_ENABLED]}" == "1" ]] || return 0

  if [[ -e "$PDG_MANAGEMENT_PATH" || -L "$PDG_MANAGEMENT_PATH" ]]; then
    assert_safe_root_management_entry \
      "$PDG_MANAGEMENT_PATH" "Proxy Gateway Plus 标准管理入口"
    assert_existing_pdg_external
    case "${CONFIG[PDG_EXISTING_ACTION]}" in
      skip)
        info "Proxy Gateway Plus 已安装；按 inventory 跳过维护动作。"
        ;;
      migrate)
        info "Proxy Gateway Plus 已安装；调用标准 pdg migrate 接口。"
        run_component_clean "$PDG_MANAGEMENT_PATH" migrate \
          || die "Proxy Gateway Plus migrate 动作失败。"
        assert_existing_pdg_external
        ;;
      update)
        info "Proxy Gateway Plus 已安装；调用标准 pdg update 接口。"
        run_component_clean "$PDG_MANAGEMENT_PATH" update \
          || die "Proxy Gateway Plus update 动作失败。"
        assert_existing_pdg_external
        ;;
    esac
    return 0
  fi

  env_path="$(resolve_inventory_path "${CONFIG[PDG_ENV_FILE]}")"
  load_component_env pdg "$env_path"
  new_temp_file
  temp="$NEW_TEMP_FILE"
  fetch_verified_script \
    "${CONFIG[PDG_INSTALL_URL]}" "${CONFIG[PDG_INSTALL_SHA256]}" "$temp"
  info "调用 Proxy Gateway Plus 非交互标准安装接口（external 防火墙模式）。"
  run_component_clean "${COMPONENT_ENV[@]}" \
    PDG_NONINTERACTIVE=1 \
    PDG_FIREWALL_MODE=external \
    /bin/bash "$temp" \
    || die "Proxy Gateway Plus 标准安装器执行失败。"
  assert_safe_root_management_entry \
    "$PDG_MANAGEMENT_PATH" "Proxy Gateway Plus 标准管理入口"
  assert_existing_pdg_external
}

deploy_sidecar() {
  local temp target="${CONFIG[SIDECAR_INSTALL_PATH]}"
  local directory candidate
  [[ "${CONFIG[SIDECAR_ENABLED]}" == "1" ]] || return 0

  if [[ "${CONFIG[SIDECAR_EXISTING_ACTION]}" == "keep" \
      && ( -e "$target" || -L "$target" ) ]]; then
    assert_existing_sidecar_target "$target"
    info "Xray sidecar 管理入口已存在；按 inventory 保持现有版本。"
  else
    [[ ! -d "$target" || -L "$target" ]] \
      || die "sidecar 标准管理路径是目录，拒绝覆盖。"
    require_canonical_absolute_path "$target" "sidecar 标准管理路径"
    directory="$(dirname -- "$target")"
    [[ -d "$directory" ]] || die "sidecar 标准管理目录不存在。"
    require_root_owned_directory_chain "$directory" "sidecar 标准管理路径"
    new_temp_file
    temp="$NEW_TEMP_FILE"
    fetch_verified_script \
      "${CONFIG[SIDECAR_SOURCE_URL]}" "${CONFIG[SIDECAR_SOURCE_SHA256]}" "$temp"
    candidate="$(mktemp "${directory}/.${target##*/}.candidate.XXXXXX")" \
      || die "无法创建 sidecar 同目录候选文件。"
    TEMP_FILES+=("$candidate")
    install -o root -g root -m 0755 "$temp" "$candidate" \
      || die "无法准备 sidecar 候选文件。"
    mv -fT -- "$candidate" "$target" \
      || die "无法原子安装 sidecar 管理入口。"
    assert_existing_sidecar_target "$target"
    info "已安装 Xray sidecar 既有管理入口：${target}"
  fi

  if [[ "${CONFIG[SIDECAR_RUN_MODE]}" == "interactive" ]]; then
    info "进入 sidecar 原有管理菜单；退出后才应用整机服务清单。"
    assert_existing_sidecar_target "$target"
    run_component_clean "$target" \
      || die "Xray sidecar 管理动作失败。"
  fi
}

render_firewall_definition() {
  local index source family protocol port name
  local -a source_list
  printf 'table inet vps_toolkit_proxy_stack {\n'
  printf '  chain input {\n'
  printf '    type filter hook input priority -90; policy %s;\n' \
    "${CONFIG[HOST_FIREWALL_POLICY]}"
  printf '    ct state invalid drop\n'
  printf '    ct state established,related accept\n'
  printf '    iifname "lo" accept\n'
  if [[ "${CONFIG[HOST_FIREWALL_ALLOW_ICMP]}" == "1" ]]; then
    printf '    ip protocol icmp accept\n'
    printf '    ip6 nexthdr ipv6-icmp accept\n'
  fi

  for ((index = 0; index < ${#SERVICE_NAMES[@]}; index++)); do
    name="${SERVICE_NAMES[$index]}"
    protocol="${SERVICE_PROTOCOLS[$index]}"
    port="${SERVICE_PORTS[$index]}"
    IFS=, read -r -a source_list <<< "${SERVICE_SOURCES[$index]}"
    for source in "${source_list[@]}"; do
      source="$(trim "$source")"
      if [[ "$source" == *:* ]]; then
        family="ip6"
      else
        family="ip"
      fi
      if [[ "$protocol" == "any" ]]; then
        printf '    %s saddr %s accept comment "%s"\n' \
          "$family" "$source" "$name"
      else
        printf '    %s saddr %s %s dport %s accept comment "%s"\n' \
          "$family" "$source" "$protocol" "$port" "$name"
      fi
    done
  done
  printf '  }\n'
  printf '}\n'
}

render_firewall_batch() {
  # "add" is deliberately used rather than "create": nft treats an existing
  # table as success.  The following delete therefore succeeds whether this is
  # the first load or a reload, and the final definition always starts clean.
  printf 'add table inet vps_toolkit_proxy_stack\n'
  printf 'delete table inet vps_toolkit_proxy_stack\n'
  render_firewall_definition
}

restore_file_atomically() {
  local target="$1" backup="$2" existed="$3"
  local directory candidate
  directory="$(dirname -- "$target")"
  if [[ "$existed" == "1" ]]; then
    candidate="$(mktemp "${directory}/.${target##*/}.restore.XXXXXX")" \
      || return 1
    TEMP_FILES+=("$candidate")
    cp -a -- "$backup" "$candidate" || return 1
    mv -fT -- "$candidate" "$target" || return 1
  else
    rm -f -- "$target" || return 1
  fi
}

rollback_firewall_persistence() {
  local failed=0
  if [[ -n "$PERSISTENCE_MAIN_BACKUP" ]]; then
    restore_file_atomically \
      "$NFTABLES_MAIN_CONFIG" "$PERSISTENCE_MAIN_BACKUP" "1" || failed=1
  fi
  if [[ -n "$PERSISTENCE_POLICY_BACKUP" || "$PERSISTENCE_POLICY_EXISTED" == "0" ]]; then
    restore_file_atomically \
      "$NFTABLES_POLICY_FILE" "$PERSISTENCE_POLICY_BACKUP" \
      "$PERSISTENCE_POLICY_EXISTED" || failed=1
  fi
  if [[ "$failed" == "0" ]]; then
    PERSISTENCE_PREPARED=0
    return 0
  fi
  PERSISTENCE_RESTORE_FAILED=1
  return 1
}

prepare_firewall_persistence() {
  local batch="$1"
  local policy_directory include_line policy_candidate main_candidate

  PERSISTENCE_MAIN_BACKUP=""
  PERSISTENCE_POLICY_BACKUP=""
  PERSISTENCE_POLICY_EXISTED=0
  PERSISTENCE_PREPARED=0
  PERSISTENCE_COMMITTED=0
  PERSISTENCE_RESTORE_FAILED=0
  policy_directory="$(dirname -- "$NFTABLES_POLICY_FILE")"
  include_line="include \"${NFTABLES_POLICY_FILE}\""

  validate_firewall_persistence_trust
  mkdir -p -m 0755 -- "$policy_directory" || return 1
  require_root_owned_directory_chain \
    "$policy_directory" "nftables 托管 policy"

  new_temp_file
  PERSISTENCE_MAIN_BACKUP="$NEW_TEMP_FILE"
  cp -a -- "$NFTABLES_MAIN_CONFIG" "$PERSISTENCE_MAIN_BACKUP" || return 1
  if [[ -e "$NFTABLES_POLICY_FILE" || -L "$NFTABLES_POLICY_FILE" ]]; then
    PERSISTENCE_POLICY_EXISTED=1
    new_temp_file
    PERSISTENCE_POLICY_BACKUP="$NEW_TEMP_FILE"
    cp -a -- "$NFTABLES_POLICY_FILE" "$PERSISTENCE_POLICY_BACKUP" || return 1
  fi

  policy_candidate="$(mktemp \
    "${policy_directory}/.${NFTABLES_POLICY_FILE##*/}.candidate.XXXXXX")" \
    || return 1
  TEMP_FILES+=("$policy_candidate")
  main_candidate="$(mktemp \
    "$(dirname -- "$NFTABLES_MAIN_CONFIG")/.${NFTABLES_MAIN_CONFIG##*/}.candidate.XXXXXX")" \
    || return 1
  TEMP_FILES+=("$main_candidate")

  install -m 0644 "$batch" "$policy_candidate" || return 1
  if [[ "$EUID" -eq 0 ]]; then
    chown root:root "$policy_candidate" || return 1
  fi
  cp -a -- "$NFTABLES_MAIN_CONFIG" "$main_candidate" || return 1
  if ! grep -Fqx "$include_line" "$main_candidate"; then
    printf '\n%s\n' "$include_line" >> "$main_candidate" || return 1
  fi

  validate_firewall_persistence_trust
  require_root_owned_directory_chain \
    "$policy_directory" "nftables 托管 policy"
  # Arm the EXIT rollback guard before the first target is atomically replaced.
  PERSISTENCE_PREPARED=1
  if ! mv -fT -- "$policy_candidate" "$NFTABLES_POLICY_FILE"; then
    PERSISTENCE_PREPARED=0
    return 1
  fi
  if ! mv -fT -- "$main_candidate" "$NFTABLES_MAIN_CONFIG"; then
    rollback_firewall_persistence || true
    return 1
  fi
  if ! nft -c -f "$NFTABLES_MAIN_CONFIG"; then
    rollback_firewall_persistence || true
    return 1
  fi
}

assert_no_foreign_input_base_chain() {
  local ruleset
  new_temp_file
  ruleset="$NEW_TEMP_FILE"
  nft -j list ruleset > "$ruleset" \
    || die "无法检查现有 nftables input base chain，拒绝应用 managed policy。"
  if ! run_component_clean python3 -I - "$ruleset" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    document = json.load(handle)
for item in document.get("nftables", []):
    chain = item.get("chain")
    if not isinstance(chain, dict):
        continue
    if chain.get("hook") != "input":
        continue
    if chain.get("family") == "inet" and chain.get("table") == "vps_toolkit_proxy_stack":
        continue
    raise SystemExit(1)
PY
  then
    die "检测到其它 input base chain；请先合并或移除冲突规则。"
  fi
}

apply_firewall() {
  local batch
  if [[ "${CONFIG[HOST_FIREWALL_MODE]}" == "external" ]]; then
    info "整机防火墙为 external；未修改 input policy。"
    return 0
  fi
  command -v nft >/dev/null 2>&1 || die "managed 防火墙模式需要 nft。"
  if [[ "${CONFIG[HOST_FIREWALL_PERSIST]}" == "1" ]]; then
    validate_firewall_persistence_trust
  fi
  new_temp_file
  batch="$NEW_TEMP_FILE"
  render_firewall_batch > "$batch"
  assert_no_foreign_input_base_chain
  nft -c -f "$batch" || die "生成的整机 nftables policy 未通过语法检查。"
  if [[ "${CONFIG[HOST_FIREWALL_PERSIST]}" == "1" ]]; then
    if ! prepare_firewall_persistence "$batch"; then
      if [[ "$PERSISTENCE_RESTORE_FAILED" == "1" ]]; then
        die "持久化候选安装失败且 before-image 恢复失败；未执行 live apply。"
      fi
      die "持久化候选安装失败；已保留或恢复 before-image，未执行 live apply。"
    fi
  fi
  if ! nft -f "$batch"; then
    if [[ "$PERSISTENCE_PREPARED" == "1" ]] \
        && ! rollback_firewall_persistence; then
      die "正式 nftables apply 原子失败，且持久化 before-image 恢复失败。"
    fi
    if [[ "${CONFIG[HOST_FIREWALL_PERSIST]}" == "1" ]]; then
      die "正式 nftables apply 原子失败；持久化 before-image 已恢复。"
    fi
    die "正式 nftables apply 原子失败；未修改持久化配置。"
  fi
  PERSISTENCE_COMMITTED=1
  if [[ "${CONFIG[HOST_FIREWALL_PERSIST]}" == "1" ]] \
      && command -v systemctl >/dev/null 2>&1; then
    systemctl enable nftables >/dev/null \
      || warn "policy 已应用并持久化，但 nftables 开机启用失败，请人工检查。"
  fi
  info "已按实例服务清单应用整机 input policy。"
}

show_plan() {
  local index
  printf 'Inventory: %s\n' "$INVENTORY_PATH"
  printf 'Host firewall: %s (policy %s, persist %s)\n' \
    "${CONFIG[HOST_FIREWALL_MODE]}" \
    "${CONFIG[HOST_FIREWALL_POLICY]}" \
    "${CONFIG[HOST_FIREWALL_PERSIST]}"
  printf 'Components: Argosbx=%s, Proxy Gateway Plus=%s, Xray sidecar=%s\n' \
    "${CONFIG[ARGOSBX_ENABLED]}" \
    "${CONFIG[PDG_ENABLED]}" \
    "${CONFIG[SIDECAR_ENABLED]}"
  printf 'Existing actions: Argosbx=%s, Proxy Gateway Plus=%s, Xray sidecar=%s\n' \
    "${CONFIG[ARGOSBX_EXISTING_ACTION]}" \
    "${CONFIG[PDG_EXISTING_ACTION]}" \
    "${CONFIG[SIDECAR_EXISTING_ACTION]}"
  printf 'Declared service interfaces:\n'
  for ((index = 0; index < ${#SERVICE_NAMES[@]}; index++)); do
    printf '  - %s: %s/%s from %s\n' \
      "${SERVICE_NAMES[$index]}" \
      "${SERVICE_PORTS[$index]}" \
      "${SERVICE_PROTOCOLS[$index]}" \
      "${SERVICE_SOURCES[$index]}"
  done
  printf 'Sensitive component values are intentionally omitted.\n'
}

acquire_mutation_lock() {
  command -v flock >/dev/null 2>&1 \
    || die "部署和防火墙应用需要 flock。"
  exec {MUTATION_LOCK_FD}> "$MUTATION_LOCK_FILE" \
    || die "无法打开编排锁。"
  flock -n "$MUTATION_LOCK_FD" \
    || die "另一个编排或防火墙应用正在运行。"
}

show_status() {
  local state
  if [[ "${CONFIG[ARGOSBX_ENABLED]}" == "1" ]]; then
    if [[ -e "$ARGOSBX_MANAGEMENT_PATH" || -L "$ARGOSBX_MANAGEMENT_PATH" ]]; then
      assert_safe_root_management_entry \
        "$ARGOSBX_MANAGEMENT_PATH" "Argosbx 标准管理入口"
      printf 'Argosbx: management command installed\n'
    else
      printf 'Argosbx: not detected\n'
    fi
  fi
  if [[ "${CONFIG[PDG_ENABLED]}" == "1" ]]; then
    if [[ -e "$PDG_MANAGEMENT_PATH" || -L "$PDG_MANAGEMENT_PATH" ]]; then
      assert_safe_root_management_entry \
        "$PDG_MANAGEMENT_PATH" "Proxy Gateway Plus 标准管理入口"
      assert_existing_pdg_external
      printf 'Proxy Gateway Plus: management command installed\n'
    else
      printf 'Proxy Gateway Plus: not detected\n'
    fi
  fi
  if [[ "${CONFIG[SIDECAR_ENABLED]}" == "1" ]]; then
    if [[ -e "${CONFIG[SIDECAR_INSTALL_PATH]}" \
        || -L "${CONFIG[SIDECAR_INSTALL_PATH]}" ]]; then
      assert_existing_sidecar_target "${CONFIG[SIDECAR_INSTALL_PATH]}"
      state="management command installed"
      if command -v systemctl >/dev/null 2>&1 \
          && systemctl is-active --quiet agsbx-extra-vless-raw-enc; then
        state="service active"
      fi
      printf 'Xray sidecar: %s\n' "$state"
    else
      printf 'Xray sidecar: not detected\n'
    fi
  fi
  if [[ "${CONFIG[HOST_FIREWALL_MODE]}" == "managed" ]]; then
    if command -v nft >/dev/null 2>&1 \
        && nft list table inet vps_toolkit_proxy_stack >/dev/null 2>&1; then
      printf 'Host firewall inventory: active\n'
    else
      printf 'Host firewall inventory: not active\n'
    fi
  else
    printf 'Host firewall inventory: externally managed\n'
  fi
}

parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --inventory)
        [[ "$#" -ge 2 ]] || die "--inventory 缺少路径。"
        INVENTORY_PATH="$2"
        shift 2
        ;;
      --version)
        printf '%s %s (%s)\n' "$PROGRAM_NAME" "$SCRIPT_VERSION" "$SCRIPT_RELEASE_DATE"
        exit 0
        ;;
      --changelog)
        show_changelog
        exit 0
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      validate|plan|deploy|status|render-firewall|firewall-apply)
        [[ -z "$COMMAND" ]] || die "只能指定一个命令。"
        COMMAND="$1"
        shift
        ;;
      *)
        die "未知参数：$1"
        ;;
    esac
  done
  [[ -n "$COMMAND" ]] || {
    usage >&2
    exit 2
  }
}

main() {
  parse_args "$@"
  case "$COMMAND" in
    deploy|firewall-apply)
      [[ "$EUID" -eq 0 ]] || die "${COMMAND} 必须使用 root。"
      PATH="$COMPONENT_EXEC_PATH"
      export PATH
      umask 022
      acquire_mutation_lock
      ;;
  esac
  validate_all
  case "$COMMAND" in
    validate)
      info "inventory 与组件配置校验通过。"
      ;;
    plan)
      show_plan
      ;;
    status)
      show_status
      ;;
    render-firewall)
      [[ "${CONFIG[HOST_FIREWALL_MODE]}" == "managed" ]] \
        || die "external 模式没有可渲染的整机 policy。"
      render_firewall_batch
      ;;
    firewall-apply)
      apply_firewall
      ;;
    deploy)
      deploy_argosbx
      deploy_pdg
      deploy_sidecar
      apply_firewall
      info "编排步骤已完成；请运行 status，并分别使用既有管理入口复核服务。"
      ;;
  esac
}

main "$@"
