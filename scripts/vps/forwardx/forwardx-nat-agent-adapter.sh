#!/usr/bin/env bash
set -uo pipefail

APP_NAME="forwardx-nat-adapter"

STATE_DIR="${FXNAT_STATE_DIR:-/etc/forwardx-nat-adapter}"
BIN_DIR="${FXNAT_BIN_DIR:-/usr/local/bin}"
LOG_DIR="${FXNAT_LOG_DIR:-/var/log/forwardx-agent}"
AGENT_BIN="${FXNAT_AGENT_BIN:-/usr/local/bin/forwardx-agent}"
AGENT_CONF="${FXNAT_AGENT_CONF:-/etc/forwardx-agent/config.json}"
CRONTAB_FILE="${FXNAT_CRONTAB_FILE:-/etc/crontabs/root}"

INSTALL_COMMAND_FILE="${STATE_DIR}/forwardx-install-command.sh"
MAPPINGS_FILE="${STATE_DIR}/mappings.tsv"

AGENT_START_SCRIPT="${BIN_DIR}/forwardx-agent-start.sh"
AGENT_STOP_SCRIPT="${BIN_DIR}/forwardx-agent-stop.sh"
AGENT_RESTART_SCRIPT="${BIN_DIR}/forwardx-agent-restart.sh"
AGENT_STATUS_SCRIPT="${BIN_DIR}/forwardx-agent-status.sh"

CRON_BEGIN="# BEGIN forwardx-nat-adapter"
CRON_END="# END forwardx-nat-adapter"

C_RESET=""
C_GREEN=""
C_YELLOW=""
C_RED=""

setup_colors() {
  if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_RED=$'\033[31m'
  fi
}

info() { printf '%b[info]%b %s\n' "${C_GREEN}" "${C_RESET}" "$1"; }
warn() { printf '%b[warn]%b %s\n' "${C_YELLOW}" "${C_RESET}" "$1" >&2; }
err() { printf '%b[error]%b %s\n' "${C_RED}" "${C_RESET}" "$1" >&2; }
die() { err "$1"; exit "${2:-1}"; }

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

usage() {
  cat <<'EOF'
Usage:
  forwardx-nat-agent-adapter.sh install --public-port <port> --internal-port <port> [--proto both|tcp|udp] [--command-file <path>] [--note <text>]
  forwardx-nat-agent-adapter.sh diagnose [--public-port <port> --internal-port <port>] [--proto both|tcp|udp]
  forwardx-nat-agent-adapter.sh --help

Purpose:
  Wrap the ForwardX agent install command for NAT VPS hosts, especially
  Alpine/BusyBox systems without systemd.

Important NAT rule:
  Configure the provider panel first, for example:
    public 54999 -> VPS internal 81

  In the ForwardX panel, use the VPS internal port:
    ForwardX listen/entry port = 81

  External users still connect to:
    provider public IP:54999

The script does not log in to the provider panel and does not create provider
port mappings. It records the mapping locally and keeps the ForwardX agent
running with BusyBox crond.
EOF
}

require_root() {
  local uid="${EUID:-}"
  if [[ -z "${uid}" ]] && has_cmd id; then
    uid="$(id -u)"
  fi
  [[ "${uid}" == "0" ]] || die "install must be run as root on the NAT VPS." 1
}

validate_port() {
  local port="$1"
  [[ "${port}" =~ ^[0-9]+$ ]] || return 1
  [[ ! "${port}" =~ ^0[0-9] ]] || return 1
  (( port >= 1 && port <= 65535 ))
}

normalize_proto() {
  local value
  value="$(trim "${1:-both}")"
  value="${value,,}"
  case "${value}" in
    ""|both|all|tcp+udp) printf 'both\n' ;;
    tcp) printf 'tcp\n' ;;
    udp) printf 'udp\n' ;;
    *) return 1 ;;
  esac
}

sanitize_note() {
  local value="$1"
  value="${value//$'\r'/ }"
  value="${value//$'\n'/ }"
  value="${value//|/ }"
  value="$(trim "${value}")"
  printf '%s' "${value}"
}

ensure_layout() {
  mkdir -p "${STATE_DIR}" "${BIN_DIR}" "${LOG_DIR}" || return 1
  chmod 700 "${STATE_DIR}" 2>/dev/null || true
}

install_alpine_dependencies() {
  if has_cmd apk; then
    info "Installing Alpine dependencies when missing."
    apk add --no-cache bash curl ca-certificates iptables iproute2 procps busybox-extras || {
      warn "apk dependency installation failed; continuing because some packages may already exist."
    }
    return 0
  fi

  warn "apk was not found. This first version targets Alpine/BusyBox; skipping package installation."
}

read_stdin_all() {
  local input
  input="$(cat)"
  printf '%s' "${input}"
}

save_install_command() {
  local command_file="$1"
  local command_content=""

  ensure_layout || die "failed to create ${STATE_DIR}."

  if [[ -n "${command_file}" ]]; then
    [[ -r "${command_file}" ]] || die "command file is not readable: ${command_file}"
    tr -d '\r' < "${command_file}" > "${INSTALL_COMMAND_FILE}" || die "failed to save install command."
  else
    if [[ -t 0 ]]; then
      info "Paste the full ForwardX agent install command, then press Enter."
      IFS= read -r command_content || die "failed to read ForwardX install command."
    else
      command_content="$(read_stdin_all)"
    fi
    command_content="${command_content//$'\r'/}"
    command_content="$(trim "${command_content}")"
    [[ -n "${command_content}" ]] || die "ForwardX install command is empty. Use --command-file for non-interactive runs."
    {
      printf '%s\n' '#!/usr/bin/env bash'
      printf '%s\n' 'set -o pipefail'
      printf '%s\n' "${command_content}"
    } > "${INSTALL_COMMAND_FILE}" || die "failed to save install command."
  fi

  chmod 600 "${INSTALL_COMMAND_FILE}" 2>/dev/null || true
}

agent_files_present() {
  [[ -x "${AGENT_BIN}" && -f "${AGENT_CONF}" ]]
}

run_forwardx_install_command() {
  info "Running saved ForwardX agent install command."
  if bash "${INSTALL_COMMAND_FILE}"; then
    info "ForwardX install command completed."
    return 0
  fi

  local rc=$?
  if agent_files_present; then
    warn "ForwardX install command exited with ${rc}, but agent binary and config exist. This is common on Alpine when the official script reaches systemctl."
    return 0
  fi

  die "ForwardX install command failed before creating ${AGENT_BIN} and ${AGENT_CONF}." "${rc}"
}

register_agent_if_possible() {
  agent_files_present || {
    warn "agent binary or config is missing; skipping register step."
    return 0
  }

  info "Registering ForwardX agent if required."
  "${AGENT_BIN}" -config "${AGENT_CONF}" -register >/dev/null 2>&1 || {
    warn "agent register command failed or was already registered; continuing."
  }
}

write_agent_helper_scripts() {
  ensure_layout || die "failed to create runtime directories."

  cat > "${AGENT_START_SCRIPT}" <<EOF
#!/bin/sh
LOG="${LOG_DIR}/agent.log"
BIN="${AGENT_BIN}"
CONF="${AGENT_CONF}"

mkdir -p "${LOG_DIR}"

[ -x "\$BIN" ] || {
  echo "\$(date '+%F %T') missing \$BIN" >> "\$LOG"
  exit 1
}

[ -f "\$CONF" ] || {
  echo "\$(date '+%F %T') missing \$CONF" >> "\$LOG"
  exit 1
}

if command -v pidof >/dev/null 2>&1 && pidof forwardx-agent >/dev/null 2>&1; then
  exit 0
fi

if command -v pgrep >/dev/null 2>&1 && pgrep -x forwardx-agent >/dev/null 2>&1; then
  exit 0
fi

"\$BIN" -config "\$CONF" >> "\$LOG" 2>&1 &
EOF

  cat > "${AGENT_STOP_SCRIPT}" <<'EOF'
#!/bin/sh
pkill forwardx-agent 2>/dev/null || true
EOF

  cat > "${AGENT_RESTART_SCRIPT}" <<EOF
#!/bin/sh
"${AGENT_STOP_SCRIPT}"
sleep 2
"${AGENT_START_SCRIPT}"
EOF

  cat > "${AGENT_STATUS_SCRIPT}" <<EOF
#!/bin/sh
echo "== ForwardX agent process =="
ps -ef 2>/dev/null | grep '[f]orwardx-agent' || echo "forwardx-agent not running"

echo
echo "== Agent files =="
ls -l "${AGENT_BIN}" "${AGENT_CONF}" 2>/dev/null || true

echo
echo "== NAT adapter mappings =="
cat "${MAPPINGS_FILE}" 2>/dev/null || echo "mapping file not found"

echo
echo "== BusyBox crontab =="
cat "${CRONTAB_FILE}" 2>/dev/null || echo "crontab file not found"

echo
echo "== Recent agent log =="
tail -n 80 "${LOG_DIR}/agent.log" 2>/dev/null || echo "agent log not found"
EOF

  chmod +x "${AGENT_START_SCRIPT}" "${AGENT_STOP_SCRIPT}" "${AGENT_RESTART_SCRIPT}" "${AGENT_STATUS_SCRIPT}" 2>/dev/null || true
}

remove_managed_cron_block() {
  local source_file="$1"
  awk -v begin="${CRON_BEGIN}" -v end="${CRON_END}" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    skip != 1 { print }
  ' "${source_file}" 2>/dev/null || true
}

write_cron_block() {
  local tmp crontab_dir
  crontab_dir="$(dirname "${CRONTAB_FILE}")"
  mkdir -p "${crontab_dir}" || die "failed to create ${crontab_dir}."
  touch "${CRONTAB_FILE}" || die "failed to touch ${CRONTAB_FILE}."

  tmp="$(mktemp "${crontab_dir}/root.forwardx.tmp.XXXXXX")" || die "failed to create temp crontab."
  remove_managed_cron_block "${CRONTAB_FILE}" > "${tmp}"
  {
    printf '\n%s\n' "${CRON_BEGIN}"
    printf '%s\n' "@reboot ${AGENT_START_SCRIPT}"
    printf '%s\n' "* * * * * ${AGENT_START_SCRIPT}"
    printf '%s\n' "${CRON_END}"
  } >> "${tmp}"

  mv -f "${tmp}" "${CRONTAB_FILE}" || die "failed to update ${CRONTAB_FILE}."
  chmod 600 "${CRONTAB_FILE}" 2>/dev/null || true
}

ensure_crond_running() {
  if has_cmd pidof && pidof crond >/dev/null 2>&1; then
    info "crond is already running."
    return 0
  fi

  if has_cmd pgrep && pgrep -x crond >/dev/null 2>&1; then
    info "crond is already running."
    return 0
  fi

  if has_cmd crond; then
    info "Starting BusyBox crond."
    crond -c "$(dirname "${CRONTAB_FILE}")" >/dev/null 2>&1 || warn "failed to start crond; reboot/start it from your provider console if needed."
  else
    warn "crond was not found. Install BusyBox crond or run ${AGENT_START_SCRIPT} manually after reboot."
  fi
}

upsert_mapping() {
  local public_port="$1"
  local internal_port="$2"
  local proto="$3"
  local note="$4"
  local tmp line p i pr

  ensure_layout || die "failed to create ${STATE_DIR}."
  note="$(sanitize_note "${note}")"

  tmp="$(mktemp "${STATE_DIR}/mappings.tsv.tmp.XXXXXX")" || die "failed to create temp mapping file."
  if [[ -f "${MAPPINGS_FILE}" ]]; then
    while IFS= read -r line || [[ -n "${line}" ]]; do
      [[ -n "$(trim "${line}")" ]] || continue
      IFS='|' read -r p i pr _ <<< "${line}"
      if [[ "${p}" == "${public_port}" && "${i}" == "${internal_port}" && "${pr}" == "${proto}" ]]; then
        continue
      fi
      printf '%s\n' "${line}" >> "${tmp}"
    done < "${MAPPINGS_FILE}"
  fi

  printf '%s|%s|%s|%s\n' "${public_port}" "${internal_port}" "${proto}" "${note}" >> "${tmp}"
  mv -f "${tmp}" "${MAPPINGS_FILE}" || die "failed to update ${MAPPINGS_FILE}."
  chmod 600 "${MAPPINGS_FILE}" 2>/dev/null || true
}

start_agent() {
  "${AGENT_START_SCRIPT}" || warn "failed to start ForwardX agent; run ${AGENT_STATUS_SCRIPT} for details."
}

print_install_summary() {
  local public_port="$1"
  local internal_port="$2"
  local proto="$3"

  cat <<EOF

ForwardX NAT adapter completed.

Provider panel mapping:
  public port ${public_port}/${proto} -> this VPS internal port ${internal_port}/${proto}

ForwardX panel rule:
  use listen/entry port ${internal_port}

External clients:
  connect to provider public IP:${public_port}

Saved files:
  install command: ${INSTALL_COMMAND_FILE}
  mappings:        ${MAPPINGS_FILE}
  agent status:    ${AGENT_STATUS_SCRIPT}

EOF
}

parse_install_args() {
  INSTALL_PUBLIC_PORT=""
  INSTALL_INTERNAL_PORT=""
  INSTALL_PROTO="both"
  INSTALL_COMMAND_SOURCE=""
  INSTALL_NOTE=""

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --public-port)
        INSTALL_PUBLIC_PORT="${2:-}"
        shift 2
        ;;
      --internal-port)
        INSTALL_INTERNAL_PORT="${2:-}"
        shift 2
        ;;
      --proto)
        INSTALL_PROTO="$(normalize_proto "${2:-}" 2>/dev/null || true)"
        shift 2
        ;;
      --command-file)
        INSTALL_COMMAND_SOURCE="${2:-}"
        shift 2
        ;;
      --note)
        INSTALL_NOTE="${2:-}"
        shift 2
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        die "unknown install option: $1" 2
        ;;
    esac
  done

  validate_port "${INSTALL_PUBLIC_PORT}" || die "--public-port must be a valid 1-65535 port." 2
  validate_port "${INSTALL_INTERNAL_PORT}" || die "--internal-port must be a valid 1-65535 port." 2
  [[ -n "${INSTALL_PROTO}" ]] || die "--proto must be both, tcp, or udp." 2
  [[ -n "${INSTALL_NOTE}" ]] || INSTALL_NOTE="ForwardX panel must use internal port ${INSTALL_INTERNAL_PORT}; public access uses ${INSTALL_PUBLIC_PORT}."
}

do_install() {
  parse_install_args "$@"
  require_root
  ensure_layout || die "failed to create adapter directories."
  install_alpine_dependencies
  save_install_command "${INSTALL_COMMAND_SOURCE}"
  run_forwardx_install_command
  register_agent_if_possible
  write_agent_helper_scripts
  write_cron_block
  ensure_crond_running
  upsert_mapping "${INSTALL_PUBLIC_PORT}" "${INSTALL_INTERNAL_PORT}" "${INSTALL_PROTO}" "${INSTALL_NOTE}"
  start_agent
  print_install_summary "${INSTALL_PUBLIC_PORT}" "${INSTALL_INTERNAL_PORT}" "${INSTALL_PROTO}"
}

process_running_label() {
  local name="$1"
  if has_cmd pgrep && pgrep -x "${name}" >/dev/null 2>&1; then
    printf 'running'
  elif has_cmd pidof && pidof "${name}" >/dev/null 2>&1; then
    printf 'running'
  else
    printf 'not running'
  fi
}

port_mentions_iptables() {
  local port="$1"
  has_cmd iptables || return 1
  iptables -t nat -vnL PREROUTING --line-numbers 2>/dev/null | grep -E "dpt:${port}([^0-9]|$)" || true
}

port_mentions_nft() {
  local port="$1"
  has_cmd nft || return 1
  nft list ruleset 2>/dev/null | grep -E "(dport|th dport)[[:space:]]+${port}([^0-9]|$)" || true
}

diagnose_one_mapping() {
  local public_port="$1"
  local internal_port="$2"
  local proto="$3"
  local public_hits internal_hits

  printf '\n== Mapping %s/%s -> internal %s/%s ==\n' "${public_port}" "${proto}" "${internal_port}" "${proto}"
  printf 'ForwardX panel listen/entry port should be: %s\n' "${internal_port}"
  printf 'External clients should use public port: %s\n' "${public_port}"

  public_hits="$(port_mentions_iptables "${public_port}")"
  internal_hits="$(port_mentions_iptables "${internal_port}")"
  if [[ -n "${public_hits}${internal_hits}" ]]; then
    printf '\niptables PREROUTING mentions:\n'
    [[ -n "${internal_hits}" ]] && printf '%s\n' "${internal_hits}"
    [[ -n "${public_hits}" ]] && printf '%s\n' "${public_hits}"
  fi

  public_hits="$(port_mentions_nft "${public_port}")"
  internal_hits="$(port_mentions_nft "${internal_port}")"
  if [[ -n "${public_hits}${internal_hits}" ]]; then
    printf '\nnftables mentions:\n'
    [[ -n "${internal_hits}" ]] && printf '%s\n' "${internal_hits}"
    [[ -n "${public_hits}" ]] && printf '%s\n' "${public_hits}"
  fi

  if [[ "${public_port}" != "${internal_port}" ]]; then
    if [[ -n "$(port_mentions_iptables "${public_port}")$(port_mentions_nft "${public_port}")" && -z "$(port_mentions_iptables "${internal_port}")$(port_mentions_nft "${internal_port}")" ]]; then
      warn "rules mention public port ${public_port} but not internal port ${internal_port}; ForwardX may be configured with the wrong NAT port."
    fi
  fi
}

parse_diagnose_args() {
  DIAG_PUBLIC_PORT=""
  DIAG_INTERNAL_PORT=""
  DIAG_PROTO="both"

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --public-port)
        DIAG_PUBLIC_PORT="${2:-}"
        shift 2
        ;;
      --internal-port)
        DIAG_INTERNAL_PORT="${2:-}"
        shift 2
        ;;
      --proto)
        DIAG_PROTO="$(normalize_proto "${2:-}" 2>/dev/null || true)"
        shift 2
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        die "unknown diagnose option: $1" 2
        ;;
    esac
  done

  if [[ -n "${DIAG_PUBLIC_PORT}${DIAG_INTERNAL_PORT}" ]]; then
    validate_port "${DIAG_PUBLIC_PORT}" || die "--public-port must be a valid 1-65535 port." 2
    validate_port "${DIAG_INTERNAL_PORT}" || die "--internal-port must be a valid 1-65535 port." 2
  fi
  [[ -n "${DIAG_PROTO}" ]] || die "--proto must be both, tcp, or udp." 2
}

do_diagnose() {
  local line public_port internal_port proto note
  parse_diagnose_args "$@"

  printf '== ForwardX NAT adapter diagnose ==\n'
  printf 'state dir: %s\n' "${STATE_DIR}"
  printf 'agent binary: %s\n' "${AGENT_BIN}"
  printf 'agent config: %s\n' "${AGENT_CONF}"
  printf 'agent process: %s\n' "$(process_running_label forwardx-agent)"
  printf 'crond process: %s\n' "$(process_running_label crond)"

  [[ -x "${AGENT_BIN}" ]] || warn "agent binary is missing or not executable: ${AGENT_BIN}"
  [[ -f "${AGENT_CONF}" ]] || warn "agent config is missing: ${AGENT_CONF}"

  if [[ -f "${CRONTAB_FILE}" ]]; then
    if grep -Fqx "${CRON_BEGIN}" "${CRONTAB_FILE}" 2>/dev/null; then
      printf 'cron block: installed in %s\n' "${CRONTAB_FILE}"
    else
      warn "cron block was not found in ${CRONTAB_FILE}."
    fi
  else
    warn "crontab file not found: ${CRONTAB_FILE}"
  fi

  if [[ -n "${DIAG_PUBLIC_PORT}${DIAG_INTERNAL_PORT}" ]]; then
    diagnose_one_mapping "${DIAG_PUBLIC_PORT}" "${DIAG_INTERNAL_PORT}" "${DIAG_PROTO}"
    return 0
  fi

  if [[ ! -f "${MAPPINGS_FILE}" ]]; then
    warn "mapping file not found: ${MAPPINGS_FILE}"
    warn "run install with --public-port and --internal-port, or diagnose with both options."
    return 0
  fi

  printf '\n== Saved mappings ==\n'
  cat "${MAPPINGS_FILE}"

  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -n "$(trim "${line}")" ]] || continue
    IFS='|' read -r public_port internal_port proto note <<< "${line}"
    if validate_port "${public_port}" && validate_port "${internal_port}"; then
      diagnose_one_mapping "${public_port}" "${internal_port}" "${proto:-both}"
    else
      warn "invalid mapping line: ${line}"
    fi
  done < "${MAPPINGS_FILE}"
}

main() {
  setup_colors
  case "${1:-}" in
    install)
      shift
      do_install "$@"
      ;;
    diagnose)
      shift
      do_diagnose "$@"
      ;;
    --help|-h|help)
      usage
      ;;
    "")
      usage
      exit 2
      ;;
    *)
      die "unknown command: $1" 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
