#!/usr/bin/env bash
set -euo pipefail

# 为指定账户安装 SSH 公钥，将 sshd 切换到随机或指定端口，并同步迁移 nftables 端口规则。

SSHD_CONFIG="/etc/ssh/sshd_config"
# 使用 IANA 动态/私有高位端口区间，并在其中随机挑选空闲端口。
SSH_PORT_RANGES=(
  49152-65535
)
EXCLUDED_PORTS=(80 443 8080 8443 8000 1080)

GLOBAL_BEGIN="# >>> SETUP_SSH_KEY_ONLY_FULL GLOBAL BEGIN"
GLOBAL_END="# <<< SETUP_SSH_KEY_ONLY_FULL GLOBAL END"
MATCH_BEGIN="# >>> SETUP_SSH_KEY_ONLY_FULL MATCH BEGIN"
MATCH_END="# <<< SETUP_SSH_KEY_ONLY_FULL MATCH END"
LEGACY_BEGIN_RE="^# >>> KEY_ONLY_PORT_[0-9]+ BEGIN$"
LEGACY_END_RE="^# <<< KEY_ONLY_PORT_[0-9]+ END$"
NFT_COMMENT_PREFIX="setup-ssh-key-only"
NFT_MANAGED_FAMILY="inet"
NFT_MANAGED_TABLE="setup_ssh_key_only"
NFT_MANAGED_CHAIN="input"

SSH_SERVICE_NAME=""
SSH_SERVICE_ACTION=""
NFT_FAMILY=""
NFT_TABLE=""
NFT_CHAIN=""
NFT_ADDED_NEW_RULE=0
REPLACE_AUTH_KEYS=0
NFT_AVAILABLE=0
NFT_CREATED_MANAGED_CHAIN=0
NFT_NEEDS_MANAGED_CHAIN=0
PORT_SELECTION_MODE="random"
REQUESTED_NEW_PORT=""
RANDOM_REQUESTED=0

info() {
  printf '%s\n' "$*"
}

warn() {
  printf '警告：%s\n' "$*" >&2
}

die() {
  printf '错误：%s\n' "$*" >&2
  exit 1
}

section() {
  printf '\n========== %s ==========\n' "$*"
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

is_valid_port() {
  local port="$1"
  [[ "${port}" =~ ^[0-9]+$ ]] || return 1
  (( port >= 1 && port <= 65535 ))
}

is_allowed_new_ssh_port() {
  local port="$1"
  local range min max

  is_valid_port "${port}" || return 1

  for range in "${SSH_PORT_RANGES[@]}"; do
    min="${range%-*}"
    max="${range#*-}"
    if (( port >= min && port <= max )); then
      return 0
    fi
  done

  return 1
}

is_excluded_port() {
  local port="$1"
  local excluded

  for excluded in "${EXCLUDED_PORTS[@]}"; do
    [[ "${port}" == "${excluded}" ]] && return 0
  done

  return 1
}

get_user_home() {
  local user="$1"

  if has_cmd getent; then
    getent passwd "${user}" | cut -d: -f6
    return
  fi

  awk -F: -v user="${user}" '$1 == user {print $6; exit}' /etc/passwd
}

get_user_group() {
  id -gn "$1"
}

find_sshd_bin() {
  if has_cmd sshd; then
    command -v sshd
    return
  fi

  if [[ -x /usr/sbin/sshd ]]; then
    printf '%s\n' /usr/sbin/sshd
    return
  fi

  return 1
}

reload_ssh_service() {
  local action svc

  SSH_SERVICE_NAME=""
  SSH_SERVICE_ACTION=""

  for action in reload restart; do
    if has_cmd systemctl; then
      for svc in ssh sshd; do
        if systemctl "${action}" "${svc}" >/dev/null 2>&1; then
          SSH_SERVICE_NAME="${svc}"
          SSH_SERVICE_ACTION="${action}"
          return 0
        fi
      done
    fi

    if has_cmd service; then
      for svc in ssh sshd; do
        if service "${svc}" "${action}" >/dev/null 2>&1; then
          SSH_SERVICE_NAME="${svc}"
          SSH_SERVICE_ACTION="${action}"
          return 0
        fi
      done
    fi
  done

  return 1
}

port_in_use() {
  local port="$1"

  if has_cmd ss; then
    ss -H -lnt 2>/dev/null | awk -v port="${port}" '
      {
        local_addr = $4
        if (local_addr ~ "(^|[:.])" port "$") {
          found = 1
        }
      }
      END { exit found ? 0 : 1 }
    '
    return
  fi

  if has_cmd lsof; then
    lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1
    return
  fi

  if has_cmd netstat; then
    netstat -lnt 2>/dev/null | awk -v port="${port}" '
      $4 ~ "(^|[:.])" port "$" { found = 1 }
      END { exit found ? 0 : 1 }
    '
    return
  fi

  return 1
}

show_port_owner() {
  local port="$1"

  if has_cmd ss; then
    ss -H -lntp 2>/dev/null | awk -v port="${port}" '$4 ~ "(^|[:.])" port "$" {print}'
    return
  fi

  if has_cmd lsof; then
    lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null || true
    return
  fi

  if has_cmd netstat; then
    netstat -lntp 2>/dev/null | awk -v port="${port}" '$4 ~ "(^|[:.])" port "$" {print}'
    return
  fi
}

can_check_listening_ports() {
  has_cmd ss || has_cmd lsof || has_cmd netstat
}

usage() {
  cat <<EOF
Usage:
  setup-ssh-key-only-full.sh [--random]
  setup-ssh-key-only-full.sh --port <port>
  setup-ssh-key-only-full.sh --help

Options:
  --random        Randomly choose a new SSH port from: ${SSH_PORT_RANGES[*]}
  -p, --port     Use a specific new SSH port from: ${SSH_PORT_RANGES[*]}
  -h, --help     Show this help.

Remote pipe example:
  curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/ssh-key-only/setup-ssh-key-only-full.sh | sudo env SSH_CONNECTION="\$SSH_CONNECTION" bash -s -- --port 55022

The current SSH session port may be outside this range, but the new SSH port
must follow scripts/vps/docs/vps-port-firewall-summary.md.
EOF
}

parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --random)
        if [[ "${PORT_SELECTION_MODE}" == "custom" ]]; then
          die "--random 不能与 --port 同时使用。"
        fi
        PORT_SELECTION_MODE="random"
        RANDOM_REQUESTED=1
        shift
        ;;
      -p|--port)
        if [[ "${PORT_SELECTION_MODE}" == "custom" ]]; then
          die "只能指定一次 --port。"
        fi
        if [[ "${RANDOM_REQUESTED}" -eq 1 ]]; then
          die "--port 不能与 --random 同时使用。"
        fi
        if [[ "$#" -lt 2 || -z "${2:-}" || "${2:-}" == --* ]]; then
          die "--port 需要端口值。"
        fi
        REQUESTED_NEW_PORT="$2"
        PORT_SELECTION_MODE="custom"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "未知参数：$1。使用 --help 查看用法。"
        ;;
    esac
  done
}

random_range_candidate() {
  if has_cmd shuf; then
    printf '%s\n' "${SSH_PORT_RANGES[@]}" | shuf -n 1
    return
  fi

  printf '%s\n' "${SSH_PORT_RANGES[$((RANDOM % ${#SSH_PORT_RANGES[@]}))]}"
}

random_port_candidate() {
  local range min max span

  range="$(random_range_candidate)"
  min="${range%-*}"
  max="${range#*-}"
  span="$((max - min + 1))"

  if has_cmd shuf; then
    shuf -i "${min}-${max}" -n 1
    return
  fi

  if has_cmd od && [[ -r /dev/urandom ]]; then
    od -An -N2 -tu2 /dev/urandom | awk \
      -v min="${min}" \
      -v span="${span}" \
      '{print min + ($1 % span)}'
    return
  fi

  printf '%s\n' "$((min + (RANDOM % span)))"
}

choose_random_port() {
  local current_port="$1"
  local port attempt

  for ((attempt = 1; attempt <= 300; attempt++)); do
    port="$(random_port_candidate)"
    is_allowed_new_ssh_port "${port}" || continue
    is_excluded_port "${port}" && continue
    [[ "${port}" == "${current_port}" ]] && continue
    port_in_use "${port}" && continue
    printf '%s\n' "${port}"
    return 0
  done

  return 1
}

validate_new_port_candidate() {
  local port="$1"
  local current_port="$2"
  local label="$3"

  if ! is_allowed_new_ssh_port "${port}"; then
    die "${label} ${port} 不在允许的 SSH 新端口范围内：${SSH_PORT_RANGES[*]}。"
  fi
  if is_excluded_port "${port}"; then
    die "${label} ${port} 属于排除端口：${EXCLUDED_PORTS[*]}。"
  fi
  if [[ "${port}" == "${current_port}" ]]; then
    die "${label} ${port} 不能与当前 SSH 端口相同。"
  fi

  if can_check_listening_ports; then
    if port_in_use "${port}"; then
      warn "${label} ${port} 已被本机服务监听，当前占用信息如下："
      show_port_owner "${port}"
      die "端口占用检查失败，请选择其他端口。"
    else
      info "端口占用检查：${port}/tcp 当前未被本机服务监听。"
    fi
  else
    warn "未找到 ss/lsof/netstat，无法检查 ${port}/tcp 是否被本机服务监听。"
  fi
}

detect_nft_input_chain() {
  has_cmd nft || return 1

  nft -a list ruleset 2>/dev/null | awk '
    /^table[[:space:]]+/ {
      family = $2
      table = $3
      next
    }
    /^[[:space:]]*chain[[:space:]]+/ {
      chain = $2
      in_chain = 1
      next
    }
    in_chain && /type[[:space:]]+filter[[:space:]].*hook[[:space:]]+input/ {
      print family, table, chain
      exit
    }
    in_chain && /^[[:space:]]*}/ {
      in_chain = 0
    }
  '
}

ensure_managed_nft_input_chain() {
  if ! nft list table "${NFT_MANAGED_FAMILY}" "${NFT_MANAGED_TABLE}" >/dev/null 2>&1; then
    nft add table "${NFT_MANAGED_FAMILY}" "${NFT_MANAGED_TABLE}" || return 1
  fi

  if ! nft list chain "${NFT_MANAGED_FAMILY}" "${NFT_MANAGED_TABLE}" "${NFT_MANAGED_CHAIN}" >/dev/null 2>&1; then
    nft add chain "${NFT_MANAGED_FAMILY}" "${NFT_MANAGED_TABLE}" "${NFT_MANAGED_CHAIN}" \
      "{ type filter hook input priority -50; policy accept; }" || return 1
    NFT_CREATED_MANAGED_CHAIN=1
  fi

  NFT_FAMILY="${NFT_MANAGED_FAMILY}"
  NFT_TABLE="${NFT_MANAGED_TABLE}"
  NFT_CHAIN="${NFT_MANAGED_CHAIN}"
  NFT_AVAILABLE=1
  info "已创建/使用脚本专用 nft input 链：${NFT_FAMILY} ${NFT_TABLE} ${NFT_CHAIN}"
  return 0
}

nft_port_is_open() {
  local family="$1"
  local table="$2"
  local chain="$3"
  local port="$4"

  nft -a list chain "${family}" "${table}" "${chain}" 2>/dev/null | awk -v port="${port}" '
    BEGIN {
      port_re = "(^|[^0-9])" port "([^0-9]|$)"
      single_re = "(tcp|th)[[:space:]]+dport[[:space:]]+" port "([^0-9]|$)"
      set_re = "(tcp|th)[[:space:]]+dport[[:space:]]+\\{"
    }

    function strip_rule_meta(line) {
      sub(/[[:space:]]+# handle [0-9]+$/, "", line)
      sub(/[[:space:]]+comment ".*"$/, "", line)
      return line
    }

    function rule_has_port(rule) {
      return rule ~ single_re || (rule ~ set_re && rule ~ port_re)
    }

    /accept/ {
      rule = strip_rule_meta($0)
      if (rule_has_port(rule)) {
        found = 1
      }
    }
    END { exit found ? 0 : 1 }
  '
}

setup_nft_context() {
  local nft_chain

  if ! has_cmd nft; then
    warn "未找到 nft 命令，将跳过 nftables 变更。"
    NFT_AVAILABLE=0
    return 1
  fi

  nft_chain="$(detect_nft_input_chain || true)"
  if [[ -z "${nft_chain}" ]]; then
    warn "已安装 nft，但没有找到现成的 input hook 链。"
    warn "确认后将创建脚本专用 nft 链：${NFT_MANAGED_FAMILY} ${NFT_MANAGED_TABLE} ${NFT_MANAGED_CHAIN}"
    NFT_FAMILY="${NFT_MANAGED_FAMILY}"
    NFT_TABLE="${NFT_MANAGED_TABLE}"
    NFT_CHAIN="${NFT_MANAGED_CHAIN}"
    NFT_AVAILABLE=1
    NFT_NEEDS_MANAGED_CHAIN=1
    return 0
  fi

  read -r NFT_FAMILY NFT_TABLE NFT_CHAIN <<< "${nft_chain}"
  NFT_AVAILABLE=1
  info "检测到 nft input 链：${NFT_FAMILY} ${NFT_TABLE} ${NFT_CHAIN}"
}

open_new_nft_port_if_needed() {
  local port="$1"

  [[ -n "${NFT_FAMILY}" ]] || return 0

  if nft_port_is_open "${NFT_FAMILY}" "${NFT_TABLE}" "${NFT_CHAIN}" "${port}"; then
    info "nft 已经存在 TCP ${port} 的 accept 规则。"
    return 0
  fi

  if nft insert rule "${NFT_FAMILY}" "${NFT_TABLE}" "${NFT_CHAIN}" \
    tcp dport "${port}" counter accept comment "\"${NFT_COMMENT_PREFIX}:${port}\""; then
    NFT_ADDED_NEW_RULE=1
    info "已添加 nft 放行规则：TCP ${port}。"
  else
    return 1
  fi
}

collect_nft_delete_handles_for_port() {
  local family="$1"
  local table="$2"
  local chain="$3"
  local port="$4"

  nft -a list chain "${family}" "${table}" "${chain}" 2>/dev/null | awk \
    -v port="${port}" \
    -v comment="${NFT_COMMENT_PREFIX}:${port}" '
    BEGIN {
      single_re = "(tcp|th)[[:space:]]+dport[[:space:]]+" port "([^0-9]|$)"
    }

    function strip_rule_meta(line) {
      sub(/[[:space:]]+# handle [0-9]+$/, "", line)
      sub(/[[:space:]]+comment ".*"$/, "", line)
      return line
    }

    /# handle / && /accept/ && /(tcp|th)[[:space:]]+dport/ {
      rule = strip_rule_meta($0)
      if ($0 ~ "comment \"" comment "\"") {
        print $NF
        next
      }

      if (rule ~ single_re) {
        print $NF
      }
    }
  '
}

nft_has_complex_accept_rule_for_port() {
  local family="$1"
  local table="$2"
  local chain="$3"
  local port="$4"

  nft -a list chain "${family}" "${table}" "${chain}" 2>/dev/null | awk -v port="${port}" '
    BEGIN {
      port_re = "(^|[^0-9])" port "([^0-9]|$)"
      set_re = "(tcp|th)[[:space:]]+dport[[:space:]]+\\{"
    }

    function strip_rule_meta(line) {
      sub(/[[:space:]]+# handle [0-9]+$/, "", line)
      sub(/[[:space:]]+comment ".*"$/, "", line)
      return line
    }

    /accept/ {
      rule = strip_rule_meta($0)
      if (rule ~ set_re && rule ~ port_re) {
        found = 1
      }
    }
    END { exit found ? 0 : 1 }
  '
}

nft_old_port_drop_exists() {
  local family="$1"
  local table="$2"
  local chain="$3"
  local port="$4"

  nft -a list chain "${family}" "${table}" "${chain}" 2>/dev/null | awk \
    -v port="${port}" \
    -v comment="${NFT_COMMENT_PREFIX}:old:${port}" '
    /drop/ && /(tcp|th)[[:space:]]+dport/ && $0 ~ "(^|[^0-9])" port "([^0-9]|$)" {
      if ($0 ~ "comment \"" comment "\"") {
        found = 1
      }
    }
    END { exit found ? 0 : 1 }
  '
}

add_old_nft_drop_rule_if_needed() {
  local old_port="$1"

  [[ -n "${NFT_FAMILY}" ]] || return 0

  if nft_old_port_drop_exists "${NFT_FAMILY}" "${NFT_TABLE}" "${NFT_CHAIN}" "${old_port}"; then
    info "nft 已存在旧端口 TCP ${old_port} 的新连接 drop 规则。"
    return 0
  fi

  if nft insert rule "${NFT_FAMILY}" "${NFT_TABLE}" "${NFT_CHAIN}" \
    ct state new tcp dport "${old_port}" counter drop comment "\"${NFT_COMMENT_PREFIX}:old:${old_port}\""; then
    info "已添加 nft 旧端口阻断规则：仅阻断 TCP ${old_port} 的新连接。"
  else
    warn "添加旧端口 TCP ${old_port} 的 nft drop 规则失败，请手动检查。"
    return 1
  fi
}

delete_nft_handles() {
  local family="$1"
  local table="$2"
  local chain="$3"
  local handles="$4"
  local handle
  local count=0

  [[ -n "${handles}" ]] || return 1

  while read -r handle; do
    [[ -z "${handle}" ]] && continue
    if nft delete rule "${family}" "${table}" "${chain}" handle "${handle}"; then
      count=$((count + 1))
    else
      warn "删除 nft 规则 handle ${handle} 失败，位置：${family} ${table} ${chain}。"
    fi
  done <<< "${handles}"

  [[ "${count}" -gt 0 ]]
}

remove_added_new_nft_rule() {
  local new_port="$1"
  local handles

  [[ "${NFT_ADDED_NEW_RULE}" -eq 1 ]] || return 0
  [[ -n "${NFT_FAMILY}" ]] || return 0

  handles="$(collect_nft_delete_handles_for_port "${NFT_FAMILY}" "${NFT_TABLE}" "${NFT_CHAIN}" "${new_port}" || true)"
  if delete_nft_handles "${NFT_FAMILY}" "${NFT_TABLE}" "${NFT_CHAIN}" "${handles}"; then
    warn "回滚时已删除刚添加的 TCP ${new_port} nft 规则。"
  fi
}

close_old_nft_port() {
  local old_port="$1"
  local handles

  [[ -n "${NFT_FAMILY}" ]] || return 0

  handles="$(collect_nft_delete_handles_for_port "${NFT_FAMILY}" "${NFT_TABLE}" "${NFT_CHAIN}" "${old_port}" || true)"
  if delete_nft_handles "${NFT_FAMILY}" "${NFT_TABLE}" "${NFT_CHAIN}" "${handles}"; then
    info "已删除旧端口 TCP ${old_port} 的 nft accept 规则。"
  else
    warn "没有找到旧端口 TCP ${old_port} 的简单 nft accept 规则。"
  fi

  if nft_has_complex_accept_rule_for_port "${NFT_FAMILY}" "${NFT_TABLE}" "${NFT_CHAIN}" "${old_port}"; then
    warn "旧端口 ${old_port} 还出现在 nft 集合/范围规则里，请手动检查：nft -a list chain ${NFT_FAMILY} ${NFT_TABLE} ${NFT_CHAIN}"
  fi

  add_old_nft_drop_rule_if_needed "${old_port}" || true
}

write_sshd_config_for_new_port() {
  local new_port="$1"
  local tmp_file="$2"

  awk \
    -v new_port="${new_port}" \
    -v global_begin="${GLOBAL_BEGIN}" \
    -v global_end="${GLOBAL_END}" \
    -v match_begin="${MATCH_BEGIN}" \
    -v match_end="${MATCH_END}" \
    -v legacy_begin_re="${LEGACY_BEGIN_RE}" \
    -v legacy_end_re="${LEGACY_END_RE}" '
    function print_global_block() {
      if (global_printed) {
        return
      }

      print ""
      print global_begin
      print "Port " new_port
      print global_end
      global_printed = 1
    }

    BEGIN {
      skip = 0
      in_match = 0
      global_printed = 0
    }

    $0 == global_begin || $0 == match_begin || $0 ~ legacy_begin_re {
      skip = 1
      next
    }

    $0 == global_end || $0 == match_end || $0 ~ legacy_end_re {
      skip = 0
      next
    }

    skip {
      next
    }

    /^[[:space:]]*Match[[:space:]]+/ && !in_match {
      print_global_block()
      in_match = 1
    }

    !in_match && /^[[:space:]]*Port[[:space:]]+/ {
      next
    }

    {
      print
    }

    END {
      print_global_block()
      print ""
      print match_begin
      print "Match LocalPort " new_port
      print "    PubkeyAuthentication yes"
      print "    PasswordAuthentication no"
      print "    KbdInteractiveAuthentication no"
      print "    ChallengeResponseAuthentication no"
      print "    AuthenticationMethods publickey"
      print "    PermitRootLogin prohibit-password"
      print match_end
    }
  ' "${SSHD_CONFIG}" > "${tmp_file}"
}

show_effective_ports() {
  local sshd_bin="$1"

  "${sshd_bin}" -T 2>/dev/null | awk '$1 == "port" {print $2}' | sort -n -u | xargs 2>/dev/null || true
}

show_sshd_config_port_lines() {
  if [[ ! -f "${SSHD_CONFIG}" ]]; then
    info "未找到 ${SSHD_CONFIG}"
    return
  fi

  local lines
  lines="$(grep -nE '^[[:space:]]*(Port|Include|Match)[[:space:]]+' "${SSHD_CONFIG}" 2>/dev/null || true)"
  if [[ -n "${lines}" ]]; then
    printf '%s\n' "${lines}"
  else
    info "${SSHD_CONFIG} 里没有未注释的 Port / Include / Match 行。"
  fi
}

show_ssh_listeners() {
  if has_cmd ss; then
    ss -lntp 2>/dev/null | awk 'NR == 1 || /sshd|ssh/'
    return
  fi

  if has_cmd netstat; then
    netstat -lntp 2>/dev/null | awk 'NR == 1 || /sshd|ssh/'
    return
  fi

  info "未找到 ss/netstat，无法展示监听端口。"
}

show_ssh_services() {
  local svc state

  if ! has_cmd systemctl; then
    info "未找到 systemctl，跳过服务状态展示。"
    return
  fi

  for svc in ssh sshd; do
    state="$(systemctl is-active "${svc}" 2>/dev/null || true)"
    if [[ -n "${state}" && "${state}" != "unknown" ]]; then
      printf '%s: %s\n' "${svc}" "${state}"
    fi
  done
}

show_nft_port_rules() {
  local port="$1"

  if [[ -z "${NFT_FAMILY}" ]]; then
    info "未检测到可操作的 nft input 链。"
    return
  fi

  local rules
  rules="$(nft -a list chain "${NFT_FAMILY}" "${NFT_TABLE}" "${NFT_CHAIN}" 2>/dev/null \
    | awk -v port="${port}" '/(tcp|th)[[:space:]]+dport/ && $0 ~ "(^|[^0-9])" port "([^0-9]|$)" {print}' || true)"
  if [[ -n "${rules}" ]]; then
    printf '%s\n' "${rules}"
  else
    info "没有看到当前端口 ${port} 的 nft dport 规则。"
  fi
}

show_existing_ssh_state() {
  local current_port="$1"
  local sshd_bin="$2"
  local effective_ports

  section "当前 SSH 会话"
  info "SSH_CONNECTION: ${SSH_CONNECTION}"
  info "当前登录使用的服务端端口：${current_port}"
  info "当前执行用户：$(id -un) (uid=$(id -u))"

  section "已有 sshd 配置"
  info "配置文件：${SSHD_CONFIG}"
  info "sshd 可执行文件：${sshd_bin}"
  effective_ports="$(show_effective_ports "${sshd_bin}")"
  if [[ -n "${effective_ports}" ]]; then
    info "sshd -T 生效端口：${effective_ports}"
  else
    warn "无法通过 sshd -T 读取生效端口。"
  fi
  info "sshd_config 中未注释的 Port / Include / Match："
  show_sshd_config_port_lines

  section "已有 SSH 监听"
  show_ssh_services
  show_ssh_listeners

  section "当前端口的 nft 情况"
  if [[ -n "${NFT_FAMILY}" ]]; then
    info "nft input 链：${NFT_FAMILY} ${NFT_TABLE} ${NFT_CHAIN}"
    if [[ "${NFT_NEEDS_MANAGED_CHAIN}" -eq 1 ]]; then
      info "说明：这是脚本计划创建的专用链，当前尚未创建。"
    fi
  fi
  show_nft_port_rules "${current_port}"
}

show_account_state() {
  local user="$1"
  local key_count=0

  section "账户情况"
  info "目标账户：${user}"
  info "家目录：${USER_HOME}"
  info "主组：${USER_GROUP}"
  info ".ssh 目录：${SSH_DIR}"
  info "authorized_keys：${AUTH_KEYS}"

  if [[ -d "${SSH_DIR}" ]]; then
    info ".ssh 权限：$(stat -c '%a %U:%G' "${SSH_DIR}" 2>/dev/null || echo '无法读取')"
  else
    info ".ssh 目录：不存在，稍后会创建。"
  fi

  if [[ -f "${AUTH_KEYS}" ]]; then
    key_count="$(grep -cE '^(ssh-|ecdsa-sha2-)' "${AUTH_KEYS}" 2>/dev/null || true)"
    info "现有公钥数量：${key_count}"
    info "现有公钥指纹："
    if has_cmd ssh-keygen; then
      ssh-keygen -lf "${AUTH_KEYS}" 2>/dev/null || info "无法解析 authorized_keys 指纹。"
    else
      info "未找到 ssh-keygen，无法展示指纹。"
    fi
  else
    info "authorized_keys：不存在，稍后会创建。"
  fi
}

confirm_continue() {
  local answer

  printf '确认继续修改 sshd 和 nft？请输入 yes 继续：'
  read -r answer
  case "${answer}" in
    yes|YES|Yes|y|Y) ;;
    *) die "已取消，未修改 sshd/nft。" ;;
  esac
}

confirm_continue_without_nft() {
  local answer

  warn "当前没有可操作的 nft，脚本无法自动放行新端口，也无法从 nft 里关闭旧端口。"
  warn "从当前监听看，旧端口会随着 sshd 切换端口而停止监听；如果云厂商安全组限制端口，请先在控制台放行新端口。"
  printf '是否继续只修改 sshd 端口并跳过 nft 变更？请输入 yes 继续：'
  read -r answer
  case "${answer}" in
    yes|YES|Yes|y|Y) ;;
    *) die "已取消，未修改 sshd/nft。" ;;
  esac
}

prompt_replace_authorized_keys() {
  local answer

  if [[ ! -s "${AUTH_KEYS}" ]]; then
    REPLACE_AUTH_KEYS=0
    return
  fi

  info ""
  warn "检测到 ${AUTH_KEYS} 已存在公钥。"
  info "如果选择删除旧公钥，脚本会备份原文件，然后只保留这次输入的新公钥。"
  printf '是否删除原来的公钥，只保留这次输入的新公钥？请输入 yes 删除，直接回车则保留：'
  read -r answer

  if [[ "${answer}" == "yes" ]]; then
    REPLACE_AUTH_KEYS=1
  else
    REPLACE_AUTH_KEYS=0
  fi
}

need_root_and_ssh_session() {
  if [[ "$(id -u)" -ne 0 ]]; then
    die "请使用 root 运行此脚本。"
  fi

  if [[ -z "${SSH_CONNECTION:-}" ]]; then
    die "请在现有 SSH 会话里运行，这样才能识别当前 SSH 端口。"
  fi
}

prompt_for_user_and_key() {
  printf '请输入要允许 SSH 密钥登录的账户名，例如 root：'
  read -r SSH_USER

  [[ -n "${SSH_USER}" ]] || die "账户名不能为空。"
  id "${SSH_USER}" >/dev/null 2>&1 || die "账户不存在：${SSH_USER}"

  USER_HOME="$(get_user_home "${SSH_USER}")"
  USER_GROUP="$(get_user_group "${SSH_USER}")"

  [[ -n "${USER_HOME}" && -d "${USER_HOME}" ]] || die "无法确定 ${SSH_USER} 的家目录。"
  [[ -n "${USER_GROUP}" ]] || die "无法确定 ${SSH_USER} 的主组。"

  SSH_DIR="${USER_HOME}/.ssh"
  AUTH_KEYS="${SSH_DIR}/authorized_keys"

  show_account_state "${SSH_USER}"

  info ""
  info "请粘贴 SSH 公钥，单行输入，然后回车："
  read -r PUBKEY
  [[ -n "${PUBKEY}" ]] || die "公钥不能为空。"

  case "${PUBKEY}" in
    ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-nistp256\ *|ecdsa-sha2-nistp384\ *|ecdsa-sha2-nistp521\ *)
      ;;
    *)
      warn "这看起来不像标准 OpenSSH 公钥。"
      warn "请粘贴 .pub 文件内容，不要粘贴私钥。"
      printf '如果仍要继续，请输入 yes：'
      read -r FORCE_CONTINUE
      case "${FORCE_CONTINUE}" in
        yes|YES|Yes|y|Y) ;;
        *) die "已取消。" ;;
      esac
      ;;
  esac

  prompt_replace_authorized_keys
}

install_public_key() {
  mkdir -p "${SSH_DIR}"
  chmod 700 "${SSH_DIR}"
  chown "${SSH_USER}:${USER_GROUP}" "${SSH_DIR}"

  touch "${AUTH_KEYS}"
  chmod 600 "${AUTH_KEYS}"
  chown "${SSH_USER}:${USER_GROUP}" "${AUTH_KEYS}"

  if [[ "${REPLACE_AUTH_KEYS}" -eq 1 ]]; then
    local key_backup
    key_backup="${AUTH_KEYS}.bak.$(date +%F-%H%M%S)"
    cp "${AUTH_KEYS}" "${key_backup}"
    printf '%s\n' "${PUBKEY}" > "${AUTH_KEYS}"
    chmod 600 "${AUTH_KEYS}"
    chown "${SSH_USER}:${USER_GROUP}" "${AUTH_KEYS}"
    info "已备份原 authorized_keys 到：${key_backup}"
    info "已删除旧公钥，并只保留本次输入的新公钥。"
    return
  fi

  if grep -Fqx "${PUBKEY}" "${AUTH_KEYS}" 2>/dev/null; then
    info "公钥已存在于 ${AUTH_KEYS}，跳过追加。"
  else
    printf '%s\n' "${PUBKEY}" >> "${AUTH_KEYS}"
    info "公钥已写入 ${AUTH_KEYS}。"
  fi
}

main() {
  local current_port new_port sshd_bin backup_path tmp_file effective_ports
  local skip_nft=0

  parse_args "$@"
  need_root_and_ssh_session

  current_port="$(printf '%s\n' "${SSH_CONNECTION}" | awk '{print $4}')"
  is_valid_port "${current_port}" || die "无法从 SSH_CONNECTION 识别当前 SSH 服务端端口。"

  sshd_bin="$(find_sshd_bin)" || die "未找到 sshd。"
  [[ -f "${SSHD_CONFIG}" ]] || die "未找到 ${SSHD_CONFIG}。"

  setup_nft_context || true
  show_existing_ssh_state "${current_port}" "${sshd_bin}"
  if [[ "${NFT_AVAILABLE}" -eq 0 ]]; then
    skip_nft=1
  fi

  if [[ "${PORT_SELECTION_MODE}" == "custom" ]]; then
    new_port="${REQUESTED_NEW_PORT}"
  else
    new_port="$(choose_random_port "${current_port}")" || die "无法选择可用的随机端口。"
  fi

  section "本次计划"
  info "当前 SSH 端口：${current_port}"
  info "SSH 新端口允许范围：${SSH_PORT_RANGES[*]}"
  if [[ "${PORT_SELECTION_MODE}" == "custom" ]]; then
    info "准备切换到的自定义 SSH 新端口：${new_port}"
    validate_new_port_candidate "${new_port}" "${current_port}" "自定义端口"
  else
    info "准备切换到的新随机端口：${new_port}"
    validate_new_port_candidate "${new_port}" "${current_port}" "随机端口"
  fi
  info "排除端口：${EXCLUDED_PORTS[*]}"

  prompt_for_user_and_key

  section "即将执行的动作"
  info "1. 为 ${SSH_USER} 写入/确认 SSH 公钥。"
  info "2. 备份 ${SSHD_CONFIG}。"
  info "3. 将 sshd 监听端口改为 ${new_port}，并只允许该端口使用公钥登录。"
  if [[ "${skip_nft}" -eq 1 ]]; then
    info "4. 当前没有可操作的 nft，将跳过 nft 端口变更。"
    info "5. sshd 重载成功后，旧端口会因为 sshd 不再监听而关闭。"
  else
    if [[ "${NFT_NEEDS_MANAGED_CHAIN}" -eq 1 ]]; then
      info "4. 将创建脚本专用 nft input 链，并会先放行 ${new_port}/tcp。"
    else
      info "4. 如果 nft 未放行 ${new_port}/tcp，则先放行新端口。"
    fi
    info "5. sshd 重载成功后，删除旧端口 ${current_port}/tcp 的简单 nft accept 规则，并阻断旧端口新连接。"
  fi
  info "请不要关闭当前 SSH 窗口。成功后再新开终端测试新端口。"
  if [[ "${skip_nft}" -eq 1 ]]; then
    confirm_continue_without_nft
  else
    confirm_continue
  fi

  install_public_key

  backup_path="/etc/ssh/sshd_config.bak.$(date +%F-%H%M%S)"
  tmp_file="$(mktemp)"

  cp "${SSHD_CONFIG}" "${backup_path}"
  info "已备份 sshd_config 到：${backup_path}"

  write_sshd_config_for_new_port "${new_port}" "${tmp_file}"
  cat "${tmp_file}" > "${SSHD_CONFIG}"
  rm -f "${tmp_file}"

  if "${sshd_bin}" -t; then
    info "sshd 配置语法检查通过。"
  else
    warn "sshd 配置语法检查失败，正在恢复备份。"
    cp "${backup_path}" "${SSHD_CONFIG}"
    exit 1
  fi

  effective_ports="$(show_effective_ports "${sshd_bin}")"
  if [[ -n "${effective_ports}" ]]; then
    info "重写配置后的 sshd -T 生效端口：${effective_ports}"
    if ! grep -Eq "(^|[[:space:]])${new_port}($|[[:space:]])" <<< "${effective_ports}"; then
      warn "sshd -T 里没有看到新端口，正在恢复备份。"
      cp "${backup_path}" "${SSHD_CONFIG}"
      exit 1
    fi
    if grep -Eq "(^|[[:space:]])${current_port}($|[[:space:]])" <<< "${effective_ports}"; then
      warn "sshd -T 里仍能看到旧端口，可能来自 Include 文件；脚本仍会尝试关闭旧端口 nft 规则。"
    fi
  fi

  if [[ "${skip_nft}" -eq 0 ]]; then
    if [[ "${NFT_NEEDS_MANAGED_CHAIN}" -eq 1 ]]; then
      if ! ensure_managed_nft_input_chain; then
        warn "创建脚本专用 nft 链失败，正在恢复 sshd_config。"
        cp "${backup_path}" "${SSHD_CONFIG}"
        exit 1
      fi
    fi

    if ! open_new_nft_port_if_needed "${new_port}"; then
      warn "放行新 nft 端口失败，正在恢复 sshd_config。"
      cp "${backup_path}" "${SSHD_CONFIG}"
      exit 1
    fi
  else
    warn "已跳过 nft 新端口放行。"
  fi

  info "正在重载 SSH 服务..."
  if reload_ssh_service; then
    info "SSH 服务 ${SSH_SERVICE_ACTION} 成功，服务名：${SSH_SERVICE_NAME}。"
  else
    warn "SSH 服务重载/重启失败，正在恢复 sshd_config。"
    cp "${backup_path}" "${SSHD_CONFIG}"
    reload_ssh_service >/dev/null 2>&1 || true
    remove_added_new_nft_rule "${new_port}"
    exit 1
  fi

  if [[ "${skip_nft}" -eq 0 ]]; then
    close_old_nft_port "${current_port}"
  else
    warn "已跳过 nft 旧端口关闭。"
  fi

  if port_in_use "${new_port}"; then
    info "已确认新端口 ${new_port} 有 TCP 监听。"
  else
    warn "未能确认 ${new_port} 有 TCP 监听。请保持当前 SSH 会话，并谨慎测试。"
  fi

  info ""
  info "=========================================="
  info "配置完成。"
  info "旧 SSH 端口：${current_port}"
  info "新 SSH 端口：${new_port}"
  info "目标账户：${SSH_USER}"
  info ""
  info "不要关闭当前 SSH 窗口。请在本地新开终端测试："
  info "ssh -p ${new_port} ${SSH_USER}@YOUR_VPS_IP"
  info ""
  info "纯密码登录应该失败："
  info "ssh -p ${new_port} -o PreferredAuthentications=password -o PubkeyAuthentication=no ${SSH_USER}@YOUR_VPS_IP"
  info ""
  info "如需回滚："
  info "cp ${backup_path} ${SSHD_CONFIG}"
  info "systemctl restart ssh || systemctl restart sshd"
  if [[ "${skip_nft}" -eq 0 ]]; then
    info "提示：本脚本添加的 nft 规则是运行时规则；如需重启后保留，请按当前系统方式持久化 nftables。"
  fi
  info "=========================================="
}

main "$@"
