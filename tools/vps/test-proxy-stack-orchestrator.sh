#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
SCRIPT="${ROOT}/scripts/vps/proxy-stack/proxy-stack-orchestrator.sh"
export MSYS=winsymlinks:nativestrict
WORK="$(mktemp -d /tmp/vps-toolkit-proxy-stack-test.XXXXXX)"
if [[ "$WORK" == "/" \
    || "$WORK" == "/tmp" \
    || "$WORK" == "/tmp/vps-toolkit-proxy-stack-test" \
    || "$WORK" == "/tmp/vps-toolkit-proxy-stack-test." \
    || ! "$WORK" =~ ^/tmp/vps-toolkit-proxy-stack-test\.[A-Za-z0-9]{6}$ \
    || ! -d "$WORK" \
    || -L "$WORK" ]]; then
  printf '[FAIL] mktemp returned a noncanonical or unsafe WORK path\n' >&2
  exit 1
fi
trap 'rm -rf -- "$WORK"' EXIT
TEST_BIN="${WORK}/bin"
mkdir -p -- "$TEST_BIN"

ok() {
  printf '[OK] %s\n' "$1"
}

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

assert_work_cleanup_trap_order() {
  local source_line
  local -i source_line_number=0 work_guard_count=0 work_guard_line=0
  local -i work_guard_end_line=0
  local -i cleanup_trap_count=0 cleanup_trap_line=0
  while IFS= read -r source_line; do
    ((source_line_number += 1))
    case "$source_line" in
      'if [[ "$WORK" == "/" \')
        ((work_guard_count += 1))
        work_guard_line="$source_line_number"
        ;;
      fi)
        if [[ "$work_guard_line" -gt 0 && "$work_guard_end_line" -eq 0 ]]; then
          work_guard_end_line="$source_line_number"
        fi
        ;;
      'trap '\''rm -rf -- "$WORK"'\'' EXIT')
        ((cleanup_trap_count += 1))
        cleanup_trap_line="$source_line_number"
        ;;
    esac
  done < "${BASH_SOURCE[0]}"
  [[ "$work_guard_count" -eq 1 \
      && "$work_guard_end_line" -gt "$work_guard_line" \
      && "$cleanup_trap_count" -eq 1 \
      && "$cleanup_trap_line" -eq $((work_guard_end_line + 1)) ]] \
    || fail "WORK cleanup trap must appear exactly once, immediately after its containment guard"
}

assert_work_cleanup_trap_order
ok "WORK cleanup trap follows the containment guard"

assert_generated_token_once() {
  local file="$1" token="$2" description="$3" count
  count="$(grep -Fc -- "$token" "$file" || true)"
  [[ "$count" -eq 1 ]] \
    || fail "generated ${description} rewrite count is ${count}, expected 1"
}

assert_generated_token_absent() {
  local file="$1" token="$2" description="$3"
  ! grep -Fq -- "$token" "$file" \
    || fail "generated ${description} retained unsafe production token"
}

assert_generated_main_removed() {
  local file="$1"
  [[ "$(grep -Fxc 'main "$@"' "$file" || true)" -eq 0 ]] \
    || fail "generated library retained direct main invocation"
}

find_trusted_python() {
  local candidate normalized discovered
  local -a candidates=()
  case "$(uname -s)" in
    MINGW*|MSYS*)
      discovered="$(command -v python 2>/dev/null || true)"
      [[ -z "$discovered" ]] || candidates+=("$discovered")
      discovered="$(command -v python3 2>/dev/null || true)"
      [[ -z "$discovered" ]] || candidates+=("$discovered")
      if [[ -n "${LOCALAPPDATA-}" ]]; then
        candidates+=("$(cygpath -u \
          "${LOCALAPPDATA}\\Programs\\Python\\Python312\\python.exe")")
      fi
      ;;
    *)
      candidates+=(/usr/bin/python3)
      discovered="$(command -v python3 2>/dev/null || true)"
      [[ -z "$discovered" ]] || candidates+=("$discovered")
      ;;
  esac
  for candidate in "${candidates[@]}"; do
    normalized="${candidate,,}"
    case "$normalized" in
      */microsoft/windowsapps/*|*/programs/python/launcher/*|*/appdata/local/python/bin/*)
        continue
        ;;
    esac
    [[ -f "$candidate" && -x "$candidate" ]] || continue
    "$candidate" -I -c 'import ipaddress, json' >/dev/null 2>&1 || continue
    printf '%s\n' "$candidate"
    return 0
  done
  return 1
}

expect_validate_fail() {
  local inventory="$1" description="$2"
  if run_orchestrator --inventory "$inventory" validate >/dev/null 2>&1; then
    fail "$description"
  fi
}

assert_output_redacted() {
  local output="$1" description="$2"
  [[ "$output" != *"SENSITIVE_TEST_TOKEN"* \
    && "$output" != *"ARGOSBX_TEST_SECRET"* ]] \
    || fail "$description"
}

PYTHON_COMMAND="$(find_trusted_python || true)"
[[ -n "$PYTHON_COMMAND" ]] \
  || fail "trusted installed Python is unavailable (installer aliases are rejected)"
REAL_BIN="${WORK}/real-bin"
FAST_BIN="${WORK}/fast-bin"
FETCH_BIN="${WORK}/fetch-bin"
mkdir -p -- "$REAL_BIN" "$FAST_BIN" "$FETCH_BIN"
{
  printf '#!/usr/bin/env bash\n'
  printf 'exec %q "$@"\n' "$PYTHON_COMMAND"
} > "${REAL_BIN}/python3"
chmod +x "${REAL_BIN}/python3"
cat > "${FAST_BIN}/python3" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
values=()
for value in "$@"; do
  case "$value" in
    -I|-) ;;
    *) values+=("$value") ;;
  esac
done
if [[ "${#values[@]}" -eq 1 && -f "${values[0]}" ]]; then
  grep -Fq '"table":"foreign_' "${values[0]}" && exit 1
  exit 0
fi
if [[ "${#values[@]}" -eq 2 ]]; then
  case "${values[0]}|${values[1]}" in
    198.51.100.25\|198.51.100.0/24|198.51.100.25\|0.0.0.0/0)
      exit 0 ;;
    *) exit 1 ;;
  esac
fi
case "${values[0]-}" in
  198.51.100.0/24|192.0.2.0/24|0.0.0.0/0|2001:db8::/32|::/0|\
  198.51.100.25|203.0.113.25|203.0.113.10)
    exit 0 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "${FAST_BIN}/python3"
REMOTE_PAYLOAD="${WORK}/remote-payload.sh"
CURL_LOG_DIRECTORY="${WORK}/path fixtures"
mkdir -p -- "$CURL_LOG_DIRECTORY"
CURL_LOG="${CURL_LOG_DIRECTORY}/curl [literal].log"
CURLRC_SENTINEL="${WORK}/curlrc-ran"
cat > "${FETCH_BIN}/curl" <<EOF
#!/bin/sh
set -eu
if [ "\${1-}" != "--disable" ]; then
  for directory in "\${CURL_HOME-}" "\${HOME-}"; do
    [ -z "\$directory" ] || [ ! -f "\$directory/.curlrc" ] || touch "$CURLRC_SENTINEL"
  done
fi
{
  printf 'arg1=%s\\n' "\${1-}"
  printf 'HOME=%s\\n' "\${HOME-unset}"
  printf 'CURL_HOME=%s\\n' "\${CURL_HOME-unset}"
} > "$CURL_LOG"
output=
while [ "\$#" -gt 0 ]; do
  if [ "\$1" = "-o" ]; then
    shift
    output="\$1"
  fi
  shift
done
[ -n "\$output" ]
cp "$REMOTE_PAYLOAD" "\$output"
EOF
chmod +x "${FETCH_BIN}/curl"

VALIDATION_EXEC_PATH="${FAST_BIN}:${FETCH_BIN}:/usr/bin:/bin"
REAL_EXEC_PATH="${REAL_BIN}:${FETCH_BIN}:/usr/bin:/bin"
export VALIDATION_EXEC_PATH REAL_EXEC_PATH
VALIDATION_LIB="${WORK}/orchestrator-validation-lib.sh"
REAL_LIB="${WORK}/orchestrator-real-lib.sh"
[[ "$(grep -Fxc 'main "$@"' "$SCRIPT")" -eq 1 ]] \
  || fail "core must contain exactly one direct main invocation"
sed -e '/^main "$@"$/d' \
  -e 's#readonly COMPONENT_EXEC_PATH=.*#readonly COMPONENT_EXEC_PATH="${VALIDATION_EXEC_PATH}"#' \
  -e 's#readonly ARGOSBX_MANAGEMENT_PATH=.*#readonly ARGOSBX_MANAGEMENT_PATH="${WORK}/not-detected-agsbx"#' \
  -e 's#readonly PDG_MANAGEMENT_PATH=.*#readonly PDG_MANAGEMENT_PATH="${WORK}/not-detected-pdg"#' \
  -e 's#"/etc/privdns-gateway/firewall-mode"#"${WORK}/not-detected-pdg-firewall-mode"#g' \
  -e 's#"/etc/privdns-gateway/profile.env"#"${WORK}/not-detected-pdg-profile.env"#g' \
  "$SCRIPT" > "$VALIDATION_LIB"
sed -e '/^main "$@"$/d' \
  -e 's#readonly COMPONENT_EXEC_PATH=.*#readonly COMPONENT_EXEC_PATH="${REAL_EXEC_PATH}"#' \
  -e 's#readonly ARGOSBX_MANAGEMENT_PATH=.*#readonly ARGOSBX_MANAGEMENT_PATH="${WORK}/not-detected-real-agsbx"#' \
  -e 's#readonly PDG_MANAGEMENT_PATH=.*#readonly PDG_MANAGEMENT_PATH="${WORK}/not-detected-real-pdg"#' \
  -e 's#"/etc/privdns-gateway/firewall-mode"#"${WORK}/not-detected-real-pdg-firewall-mode"#g' \
  -e 's#"/etc/privdns-gateway/profile.env"#"${WORK}/not-detected-real-pdg-profile.env"#g' \
  "$SCRIPT" > "$REAL_LIB"
assert_generated_main_removed "$VALIDATION_LIB"
assert_generated_token_once "$VALIDATION_LIB" \
  'readonly COMPONENT_EXEC_PATH="${VALIDATION_EXEC_PATH}"' "validation exec path"
assert_generated_token_once "$VALIDATION_LIB" \
  'readonly ARGOSBX_MANAGEMENT_PATH="${WORK}/not-detected-agsbx"' "validation Argosbx path"
assert_generated_token_once "$VALIDATION_LIB" \
  'readonly PDG_MANAGEMENT_PATH="${WORK}/not-detected-pdg"' "validation PDG path"
assert_generated_token_once "$VALIDATION_LIB" \
  '"${WORK}/not-detected-pdg-firewall-mode"' "validation PDG marker"
assert_generated_token_once "$VALIDATION_LIB" \
  '"${WORK}/not-detected-pdg-profile.env"' "validation PDG profile"
assert_generated_main_removed "$REAL_LIB"
assert_generated_token_once "$REAL_LIB" \
  'readonly COMPONENT_EXEC_PATH="${REAL_EXEC_PATH}"' "real exec path"
assert_generated_token_once "$REAL_LIB" \
  'readonly ARGOSBX_MANAGEMENT_PATH="${WORK}/not-detected-real-agsbx"' "real Argosbx path"
assert_generated_token_once "$REAL_LIB" \
  'readonly PDG_MANAGEMENT_PATH="${WORK}/not-detected-real-pdg"' "real PDG path"
assert_generated_token_once "$REAL_LIB" \
  '"${WORK}/not-detected-real-pdg-firewall-mode"' "real PDG marker"
assert_generated_token_once "$REAL_LIB" \
  '"${WORK}/not-detected-real-pdg-profile.env"' "real PDG profile"
for generated_library in "$VALIDATION_LIB" "$REAL_LIB"; do
  assert_generated_token_absent "$generated_library" \
    'readonly COMPONENT_EXEC_PATH="/root/bin:' "component exec path"
  assert_generated_token_absent "$generated_library" \
    'readonly ARGOSBX_MANAGEMENT_PATH="/root/bin/agsbx"' "Argosbx path"
  assert_generated_token_absent "$generated_library" \
    'readonly PDG_MANAGEMENT_PATH="/usr/local/bin/pdg"' "PDG path"
  assert_generated_token_absent "$generated_library" \
    '"/etc/privdns-gateway/firewall-mode"' "PDG marker"
  assert_generated_token_absent "$generated_library" \
    '"/etc/privdns-gateway/profile.env"' "PDG profile"
done

validation_stat() {
  local path="${*: -1}"
  case "$path" in
    "${WORK}"/*.mode-0640.env)
      printf '640\n'
      ;;
    "${WORK}"/*.env)
      printf '600\n'
      ;;
    *)
      /usr/bin/stat "$@"
      ;;
  esac
}

run_orchestrator() (
  source "$VALIDATION_LIB"
  stat() { validation_stat "$@"; }
  PROGRAM_NAME="proxy-stack-orchestrator.sh"
  main "$@"
)

run_orchestrator_real() (
  source "$REAL_LIB"
  stat() { validation_stat "$@"; }
  PROGRAM_NAME="proxy-stack-orchestrator.sh"
  main "$@"
)
cat > "${WORK}/pdg.env" <<'EOF'
PDG_SERVER_IP=203.0.113.10
PDG_SSH_PORT=55022
PDG_INTERNAL_CIDR=192.0.2.0/24
PDG_PLATFORM=android
PDG_FIREWALL_MODE=external
PDG_QUIC_MODE=tproxy
PDG_BOT_TOKEN=SENSITIVE_TEST_TOKEN
PDG_ALLOWED=10001
PDG_DOT_DOMAIN=dot.example.test
PDG_QUIC_MARK=0x2333
PDG_QUIC_MARK_MASK=0xffff
PDG_QUIC_ROUTE_TABLE=20233
PDG_QUIC_RULE_PRIORITY=10233
EOF

cat > "${WORK}/argosbx.env" <<'EOF'
vlpt=10443
uuid=ARGOSBX_TEST_SECRET
name=test-node
EOF

chmod 0600 "${WORK}/pdg.env" "${WORK}/argosbx.env"

write_inventory() {
  cat > "${WORK}/stack.conf" <<'EOF'
STACK_INVENTORY_VERSION=1
HOST_FIREWALL_MODE=managed
HOST_FIREWALL_POLICY=drop
HOST_FIREWALL_PERSIST=0
HOST_FIREWALL_ALLOW_ICMP=1
REMOTE_ADMIN_SERVICE=ssh
SERVICES_FILE=services.tsv
ARGOSBX_ENABLED=0
PDG_ENABLED=1
PDG_INSTALL_URL=https://raw.githubusercontent.com/SchweppesSoda/proxy-gateway-plus/main/install.sh
PDG_INSTALL_SHA256=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
PDG_ENV_FILE=pdg.env
PDG_EXISTING_ACTION=migrate
SIDECAR_ENABLED=0
EOF
}

write_services() {
  {
    printf '# component\tname\tprotocol\tport\tsource-cidrs\n'
    printf 'host\tssh\ttcp\t55022\t198.51.100.0/24\n'
    printf 'argosbx\tdisabled-argosbx\ttcp\t10443\t0.0.0.0/0\n'
    printf 'pdg\tpdg-data-plane\tany\t*\t192.0.2.0/24\n'
    printf 'host\tadmin-v6\ttcp\t55022\t2001:db8::/32\n'
    printf 'sidecar\tdisabled-sidecar\ttcp\t20443\t0.0.0.0/0\n'
  } > "${WORK}/services.tsv"
}

write_inventory
write_services

run_orchestrator --inventory "${WORK}/stack.conf" validate >/dev/null
ok "valid inventory passes"


strict_literal_marker="${WORK}/inventory-was-evaluated"
cp "${WORK}/stack.conf" "${WORK}/stack.literal.conf"
printf 'ARGOSBX_SOURCE_URL=$(touch %s)\n' "$strict_literal_marker" \
  >> "${WORK}/stack.literal.conf"
run_orchestrator --inventory "${WORK}/stack.literal.conf" validate >/dev/null
[[ ! -e "$strict_literal_marker" ]] || fail "inventory executed shell syntax"

cp "${WORK}/stack.conf" "${WORK}/stack.unknown.conf"
printf 'UNKNOWN_TEST_KEY=value\n' >> "${WORK}/stack.unknown.conf"
expect_validate_fail "${WORK}/stack.unknown.conf" "unknown inventory key passed"

cp "${WORK}/stack.conf" "${WORK}/stack.duplicate.conf"
printf 'PDG_ENABLED=1\n' >> "${WORK}/stack.duplicate.conf"
expect_validate_fail "${WORK}/stack.duplicate.conf" "duplicate inventory key passed"

sed 's/^PDG_ENABLED=1$/PDG_ENABLED 1/' \
  "${WORK}/stack.conf" > "${WORK}/stack.malformed.conf"
expect_validate_fail "${WORK}/stack.malformed.conf" "malformed inventory line passed"

sed '/^PDG_ENV_FILE=/d' \
  "${WORK}/stack.conf" > "${WORK}/stack.missing.conf"
expect_validate_fail "${WORK}/stack.missing.conf" "missing required inventory key passed"

sed $'s/^HOST_FIREWALL_MODE=managed$/HOST_FIREWALL_MODE=managed\rBAD/' \
  "${WORK}/stack.conf" > "${WORK}/stack.control.conf"
expect_validate_fail "${WORK}/stack.control.conf" "inventory CR control character passed"
sed $'s/^HOST_FIREWALL_MODE=managed$/HOST_FIREWALL_MODE=man\taged/' \
  "${WORK}/stack.conf" > "${WORK}/stack.tab-control.conf"
expect_validate_fail "${WORK}/stack.tab-control.conf" \
  "inventory TAB control character passed"
sed $'s/^HOST_FIREWALL_MODE=managed$/HOST_FIREWALL_MODE=man\033aged/' \
  "${WORK}/stack.conf" > "${WORK}/stack.esc-control.conf"
expect_validate_fail "${WORK}/stack.esc-control.conf" \
  "inventory ESC control character passed"
ok "inventory is parsed literally and rejects malformed, missing, unknown, duplicate, and control data"

cp "${WORK}/pdg.env" "${WORK}/pdg.unknown.env"
printf 'PDG_UNKNOWN_TEST=value\n' >> "${WORK}/pdg.unknown.env"
sed 's/PDG_ENV_FILE=pdg.env/PDG_ENV_FILE=pdg.unknown.env/' \
  "${WORK}/stack.conf" > "${WORK}/stack.pdg-unknown.conf"
expect_validate_fail "${WORK}/stack.pdg-unknown.conf" "unknown PDG key passed"

cp "${WORK}/pdg.env" "${WORK}/pdg.duplicate.env"
printf 'PDG_SERVER_IP=203.0.113.11\n' >> "${WORK}/pdg.duplicate.env"
sed 's/PDG_ENV_FILE=pdg.env/PDG_ENV_FILE=pdg.duplicate.env/' \
  "${WORK}/stack.conf" > "${WORK}/stack.pdg-duplicate.conf"
expect_validate_fail "${WORK}/stack.pdg-duplicate.conf" "duplicate PDG key passed"

sed 's/^PDG_DOT_DOMAIN=.*$/PDG_DOT_DOMAIN=/' \
  "${WORK}/pdg.env" > "${WORK}/pdg.empty.env"
sed 's/PDG_ENV_FILE=pdg.env/PDG_ENV_FILE=pdg.empty.env/' \
  "${WORK}/stack.conf" > "${WORK}/stack.pdg-empty.conf"
expect_validate_fail "${WORK}/stack.pdg-empty.conf" "empty PDG value passed"
cp "${WORK}/pdg.env" "${WORK}/pdg.mode-0640.env"
chmod 0640 "${WORK}/pdg.mode-0640.env"
sed 's/PDG_ENV_FILE=pdg.env/PDG_ENV_FILE=pdg.mode-0640.env/' \
  "${WORK}/stack.conf" > "${WORK}/stack.pdg-mode.conf"
expect_validate_fail "${WORK}/stack.pdg-mode.conf" \
  "group-readable PDG environment passed"
ln -s "${WORK}/pdg.env" "${WORK}/pdg.symlink.env"
sed 's/PDG_ENV_FILE=pdg.env/PDG_ENV_FILE=pdg.symlink.env/' \
  "${WORK}/stack.conf" > "${WORK}/stack.pdg-symlink.conf"
expect_validate_fail "${WORK}/stack.pdg-symlink.conf" \
  "symlink PDG environment passed"
cp "${WORK}/pdg.env" "${WORK}/pdg.tfo.env"
printf 'PDG_TFO=1\n' >> "${WORK}/pdg.tfo.env"
sed 's/PDG_ENV_FILE=pdg.env/PDG_ENV_FILE=pdg.tfo.env/' \
  "${WORK}/stack.conf" > "${WORK}/stack.pdg-tfo.conf"
expect_validate_fail "${WORK}/stack.pdg-tfo.conf" \
  "non-whitelisted PDG_TFO passed"
ok "component environment requires 0600 regular files and a strict PDG whitelist"

cat > "${WORK}/stack.argosbx-valid.conf" <<'EOF'
STACK_INVENTORY_VERSION=1
HOST_FIREWALL_MODE=external
SERVICES_FILE=services.tsv
ARGOSBX_ENABLED=1
ARGOSBX_SOURCE_URL=https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh
ARGOSBX_SOURCE_SHA256=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
ARGOSBX_VARIABLES_FILE=argosbx.env
ARGOSBX_EXISTING_ACTION=skip
PDG_ENABLED=0
SIDECAR_ENABLED=0
EOF
run_orchestrator --inventory "${WORK}/stack.argosbx-valid.conf" validate >/dev/null

cp "${WORK}/argosbx.env" "${WORK}/argosbx.unknown.env"
printf 'not_allowed=value\n' >> "${WORK}/argosbx.unknown.env"
sed 's/ARGOSBX_VARIABLES_FILE=argosbx.env/ARGOSBX_VARIABLES_FILE=argosbx.unknown.env/' \
  "${WORK}/stack.argosbx-valid.conf" > "${WORK}/stack.argosbx-unknown.conf"
expect_validate_fail "${WORK}/stack.argosbx-unknown.conf" "unknown Argosbx key passed"

cp "${WORK}/argosbx.env" "${WORK}/argosbx.duplicate.env"
printf 'vlpt=20443\n' >> "${WORK}/argosbx.duplicate.env"
sed 's/ARGOSBX_VARIABLES_FILE=argosbx.env/ARGOSBX_VARIABLES_FILE=argosbx.duplicate.env/' \
  "${WORK}/stack.argosbx-valid.conf" > "${WORK}/stack.argosbx-duplicate.conf"
expect_validate_fail "${WORK}/stack.argosbx-duplicate.conf" "duplicate Argosbx key passed"

printf 'name=no-port\n' > "${WORK}/argosbx.no-port.env"
chmod 0600 "${WORK}/argosbx.no-port.env"
sed 's/ARGOSBX_VARIABLES_FILE=argosbx.env/ARGOSBX_VARIABLES_FILE=argosbx.no-port.env/' \
  "${WORK}/stack.argosbx-valid.conf" > "${WORK}/stack.argosbx-no-port.conf"
expect_validate_fail "${WORK}/stack.argosbx-no-port.conf" "Argosbx without a protocol port passed"

for bad_port in 0 65536 080 invalid; do
  printf 'vlpt=%s\n' "$bad_port" > "${WORK}/argosbx.bad-port.env"
  chmod 0600 "${WORK}/argosbx.bad-port.env"
  sed 's/ARGOSBX_VARIABLES_FILE=argosbx.env/ARGOSBX_VARIABLES_FILE=argosbx.bad-port.env/' \
    "${WORK}/stack.argosbx-valid.conf" > "${WORK}/stack.argosbx-bad-port.conf"
  expect_validate_fail "${WORK}/stack.argosbx-bad-port.conf" \
    "invalid Argosbx port ${bad_port} passed"
done
ARGOSBX_UNSAFE_SENTINEL="${WORK}/unsafe-argosbx-value-ran"
unsafe_values=(
  'bad"quote'
  'bad\backslash'
  "bad\$(touch ${ARGOSBX_UNSAFE_SENTINEL})"
  "bad\`touch ${ARGOSBX_UNSAFE_SENTINEL}\`"
)
for unsafe_value in "${unsafe_values[@]}"; do
  {
    printf 'vlpt=10443\n'
    printf 'name=%s\n' "$unsafe_value"
  } > "${WORK}/argosbx.unsafe.env"
  chmod 0600 "${WORK}/argosbx.unsafe.env"
  sed 's/ARGOSBX_VARIABLES_FILE=argosbx.env/ARGOSBX_VARIABLES_FILE=argosbx.unsafe.env/' \
    "${WORK}/stack.argosbx-valid.conf" > "${WORK}/stack.argosbx-unsafe.conf"
  expect_validate_fail "${WORK}/stack.argosbx-unsafe.conf" \
    "unsafe Argosbx persistent value passed"
done
[[ ! -e "$ARGOSBX_UNSAFE_SENTINEL" ]] \
  || fail "unsafe Argosbx value executed shell syntax"
ok "Argosbx whitelist, port range, and persistent-value character guard are enforced"
sed 's/^host\tssh\t/host\tnot-ssh\t/' \
  "${WORK}/services.tsv" > "${WORK}/services.no-admin.tsv"
sed 's/SERVICES_FILE=services.tsv/SERVICES_FILE=services.no-admin.tsv/' \
  "${WORK}/stack.conf" > "${WORK}/stack.no-admin.conf"
expect_validate_fail "${WORK}/stack.no-admin.conf" \
  "drop policy without the remote administration service passed"

sed -e 's/^host\tssh\t/host\tnot-ssh\t/' \
  -e 's/^argosbx\tdisabled-argosbx\t/argosbx\tssh\t/' \
  "${WORK}/services.tsv" > "${WORK}/services.disabled-admin.tsv"
sed 's/SERVICES_FILE=services.tsv/SERVICES_FILE=services.disabled-admin.tsv/' \
  "${WORK}/stack.conf" > "${WORK}/stack.disabled-admin.conf"
expect_validate_fail "${WORK}/stack.disabled-admin.conf" \
  "disabled component falsely preserved remote administration"
sed $'s/^host\tssh\ttcp\t55022\t/host\tssh\tany\t*\t/' \
  "${WORK}/services.tsv" > "${WORK}/services.admin-any.tsv"
sed 's/SERVICES_FILE=services.tsv/SERVICES_FILE=services.admin-any.tsv/' \
  "${WORK}/stack.conf" > "${WORK}/stack.admin-any.conf"
run_orchestrator --inventory "${WORK}/stack.admin-any.conf" validate >/dev/null \
  || fail "host any remote administration rule failed"

sed $'s/^host\tssh\ttcp\t/host\tssh\tudp\t/' \
  "${WORK}/services.tsv" > "${WORK}/services.admin-udp.tsv"
sed 's/SERVICES_FILE=services.tsv/SERVICES_FILE=services.admin-udp.tsv/' \
  "${WORK}/stack.conf" > "${WORK}/stack.admin-udp.conf"
expect_validate_fail "${WORK}/stack.admin-udp.conf" \
  "UDP remote administration rule passed"

sed -e $'s/^host\tssh\t/host\tnot-ssh\t/' \
  -e $'s/^pdg\tpdg-data-plane\t/pdg\tssh\t/' \
  "${WORK}/services.tsv" > "${WORK}/services.pdg-admin.tsv"
sed 's/SERVICES_FILE=services.tsv/SERVICES_FILE=services.pdg-admin.tsv/' \
  "${WORK}/stack.conf" > "${WORK}/stack.pdg-admin.conf"
expect_validate_fail "${WORK}/stack.pdg-admin.conf" \
  "PDG-owned remote administration rule passed"
ok "drop policy accepts only enabled host tcp/any remote administration rules"
plan="$(run_orchestrator --inventory "${WORK}/stack.conf" plan)"
[[ "$plan" == *"ssh: 55022/tcp from 198.51.100.0/24"* ]] \
  || fail "plan omitted host service"
[[ "$plan" == *"pdg-data-plane: */any from 192.0.2.0/24"* ]] \
  || fail "plan omitted enabled component service"
[[ "$plan" != *"disabled-argosbx"* && "$plan" != *"disabled-sidecar"* ]] \
  || fail "disabled component rendered a service"
[[ "$plan" == *"Existing actions: Argosbx=skip, Proxy Gateway Plus=migrate, Xray sidecar=keep"* ]] \
  || fail "plan omitted existing actions"
assert_output_redacted "$plan" "plan leaked component value"
ok "plan is component-aware and redacted"

cat > "${WORK}/stack.output.conf" <<'EOF'
STACK_INVENTORY_VERSION=1
HOST_FIREWALL_MODE=external
SERVICES_FILE=services.tsv
ARGOSBX_ENABLED=1
ARGOSBX_SOURCE_URL=https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh
ARGOSBX_SOURCE_SHA256=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
ARGOSBX_VARIABLES_FILE=argosbx.env
ARGOSBX_EXISTING_ACTION=skip
PDG_ENABLED=1
PDG_INSTALL_URL=https://raw.githubusercontent.com/SchweppesSoda/proxy-gateway-plus/main/install.sh
PDG_INSTALL_SHA256=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
PDG_ENV_FILE=pdg.env
PDG_EXISTING_ACTION=skip
SIDECAR_ENABLED=0
EOF
output_plan="$(run_orchestrator --inventory "${WORK}/stack.output.conf" plan 2>&1)"
output_status="$(run_orchestrator --inventory "${WORK}/stack.output.conf" status 2>&1)"
assert_output_redacted "$output_plan" "combined plan leaked a credential"
assert_output_redacted "$output_status" "status leaked a credential"
ok "plan and status redact component credentials"
rendered="$(run_orchestrator --inventory "${WORK}/stack.conf" render-firewall)"
[[ "$rendered" == add\ table\ inet\ vps_toolkit_proxy_stack$'\n'delete\ table\ inet\ vps_toolkit_proxy_stack$'\n'table\ inet\ vps_toolkit_proxy_stack* ]] \
  || fail "render-firewall did not return a complete idempotent batch"
[[ "$rendered" == *"tcp dport 55022 accept"* ]] \
  || fail "firewall omitted declared TCP service"
[[ "$rendered" == *"ip saddr 192.0.2.0/24 accept"* ]] \
  || fail "firewall omitted declared source-only interface"
[[ "$rendered" == *"ip6 saddr 2001:db8::/32 tcp dport 55022 accept"* ]] \
  || fail "firewall omitted canonical IPv6 service"
[[ "$rendered" != *"disabled-argosbx"* && "$rendered" != *"disabled-sidecar"* ]] \
  || fail "firewall included disabled component"
ok "firewall renders only enabled declarations"

sed $'s/\t/ /g' "${WORK}/services.tsv" > "${WORK}/services.spaces.tsv"
sed 's/SERVICES_FILE=services.tsv/SERVICES_FILE=services.spaces.tsv/' \
  "${WORK}/stack.conf" > "${WORK}/stack.services-spaces.conf"
expect_validate_fail "${WORK}/stack.services-spaces.conf" \
  "space-delimited services row passed"
cp "${WORK}/services.tsv" "${WORK}/services.extra-tab.tsv"
printf 'host\textra\ttcp\t12345\t198.51.100.0/24\textra\n' \
  >> "${WORK}/services.extra-tab.tsv"
sed 's/SERVICES_FILE=services.tsv/SERVICES_FILE=services.extra-tab.tsv/' \
  "${WORK}/stack.conf" > "${WORK}/stack.services-extra-tab.conf"
expect_validate_fail "${WORK}/stack.services-extra-tab.conf" \
  "services row with an extra TAB passed"
for bad_sources in \
  ',198.51.100.0/24' '198.51.100.0/24,' \
  '198.51.100.0/24,,192.0.2.0/24'; do
  sed "s#198\\.51\\.100\\.0/24#${bad_sources}#" \
    "${WORK}/services.tsv" > "${WORK}/services.empty-csv.tsv"
  sed 's/SERVICES_FILE=services.tsv/SERVICES_FILE=services.empty-csv.tsv/' \
    "${WORK}/stack.conf" > "${WORK}/stack.services-empty-csv.conf"
  expect_validate_fail "${WORK}/stack.services-empty-csv.conf" \
    "services source list with an empty CSV item passed"
done
sed $'s/^sidecar\tdisabled-sidecar\ttcp\t/sidecar\tdisabled-sidecar\tinvalid\t/' \
  "${WORK}/services.tsv" > "${WORK}/services.disabled-malformed.tsv"
sed 's/SERVICES_FILE=services.tsv/SERVICES_FILE=services.disabled-malformed.tsv/' \
  "${WORK}/stack.conf" > "${WORK}/stack.disabled-malformed.conf"
expect_validate_fail "${WORK}/stack.disabled-malformed.conf" \
  "malformed disabled-component declaration escaped strict parsing"

sed -e 's/HOST_FIREWALL_MODE=managed/HOST_FIREWALL_MODE=external/' \
  -e 's/SERVICES_FILE=services.tsv/SERVICES_FILE=services.extra-tab.tsv/' \
  "${WORK}/stack.conf" > "${WORK}/stack.external-malformed.conf"
expect_validate_fail "${WORK}/stack.external-malformed.conf" \
  "external mode skipped strict services parsing"
ok "services require exact TAB fields, nonempty CSV items, and strict rows in all modes"
cp "${WORK}/services.tsv" "${WORK}/services.bad.tsv"
printf 'host\tinjected\ttcp\t12345\t0.0.0.0/0;drop\n' >> "${WORK}/services.bad.tsv"
sed 's/SERVICES_FILE=services.tsv/SERVICES_FILE=services.bad.tsv/' \
  "${WORK}/stack.conf" > "${WORK}/stack.bad.conf"
if run_orchestrator_real --inventory "${WORK}/stack.bad.conf" validate >/dev/null 2>&1; then
  fail "unsafe source CIDR passed"
fi
ok "unsafe nft input is rejected"

sed 's#198\.51\.100\.0/24#198.51.100.1/24#' \
  "${WORK}/services.tsv" > "${WORK}/services.host-bits.tsv"
sed 's/SERVICES_FILE=services.tsv/SERVICES_FILE=services.host-bits.tsv/' \
  "${WORK}/stack.conf" > "${WORK}/stack.host-bits.conf"
if run_orchestrator_real --inventory "${WORK}/stack.host-bits.conf" validate >/dev/null 2>&1; then
  fail "CIDR containing host bits passed"
fi
sed 's#198\.51\.100\.0/24#2001:0db8::/32#' \
  "${WORK}/services.tsv" > "${WORK}/services.noncanonical-ipv6.tsv"
sed 's/SERVICES_FILE=services.tsv/SERVICES_FILE=services.noncanonical-ipv6.tsv/' \
  "${WORK}/stack.conf" > "${WORK}/stack.noncanonical-ipv6.conf"
if run_orchestrator_real --inventory "${WORK}/stack.noncanonical-ipv6.conf" validate >/dev/null 2>&1; then
  fail "noncanonical IPv6 CIDR passed"
fi
ok "CIDRs require strict canonical networks"

MALICIOUS_PYTHON_DIR="${WORK}/malicious-python-cwd"
PYTHON_ISOLATION_SENTINEL="${WORK}/cwd-python-module-ran"
mkdir -p -- "$MALICIOUS_PYTHON_DIR"
cat > "${MALICIOUS_PYTHON_DIR}/ipaddress.py" <<EOF
open("$PYTHON_ISOLATION_SENTINEL", "w", encoding="utf-8").write("ipaddress")
raise SystemExit(91)
EOF
cat > "${MALICIOUS_PYTHON_DIR}/json.py" <<EOF
open("$PYTHON_ISOLATION_SENTINEL", "w", encoding="utf-8").write("json")
raise SystemExit(92)
EOF
(
  cd -- "$MALICIOUS_PYTHON_DIR"
  run_orchestrator_real --inventory "${WORK}/stack.conf" validate >/dev/null
) || fail "isolated stdlib ipaddress validation failed"
[[ ! -e "$PYTHON_ISOLATION_SENTINEL" ]] \
  || fail "CIDR validator imported cwd ipaddress.py"
(
  cd -- "$MALICIOUS_PYTHON_DIR"
  source "$REAL_LIB"
  nft() { printf '{"nftables":[]}\n'; }
  assert_no_foreign_input_base_chain
) >/dev/null 2>&1 || fail "isolated stdlib json validation failed"
[[ ! -e "$PYTHON_ISOLATION_SENTINEL" ]] \
  || fail "ruleset validator imported cwd json.py"
ok "internal Python validators use isolated stdlib imports"

cat > "${WORK}/stack.argosbx.conf" <<'EOF'
STACK_INVENTORY_VERSION=1
HOST_FIREWALL_MODE=external
SERVICES_FILE=services.tsv
ARGOSBX_ENABLED=1
ARGOSBX_SOURCE_URL=https://example.invalid/argosbx.sh
ARGOSBX_SOURCE_SHA256=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
ARGOSBX_VARIABLES_FILE=argosbx.env
ARGOSBX_EXISTING_ACTION=skip
PDG_ENABLED=0
SIDECAR_ENABLED=0
EOF
if run_orchestrator --inventory "${WORK}/stack.argosbx.conf" validate >/dev/null 2>&1; then
  fail "non-official Argosbx source passed"
fi
ok "Argosbx source is restricted to the official repository"

sed 's#https://raw.githubusercontent.com/SchweppesSoda/proxy-gateway-plus/main/install.sh#https://example.invalid/install.sh#' \
  "${WORK}/stack.conf" > "${WORK}/stack.pdg-url.conf"
if run_orchestrator --inventory "${WORK}/stack.pdg-url.conf" validate >/dev/null 2>&1; then
  fail "non-official Proxy Gateway Plus source passed"
fi

cat > "${WORK}/stack.sidecar-path.conf" <<'EOF'
STACK_INVENTORY_VERSION=1
HOST_FIREWALL_MODE=external
SERVICES_FILE=services.tsv
ARGOSBX_ENABLED=0
PDG_ENABLED=0
SIDECAR_ENABLED=1
SIDECAR_SOURCE_URL=https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer.sh
SIDECAR_SOURCE_SHA256=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
SIDECAR_INSTALL_PATH=/tmp/not-the-standard-sidecar-path
SIDECAR_EXISTING_ACTION=keep
SIDECAR_RUN_MODE=install-only
EOF
if run_orchestrator --inventory "${WORK}/stack.sidecar-path.conf" validate >/dev/null 2>&1; then
  fail "nonstandard sidecar install path passed"
fi

sed 's#SIDECAR_INSTALL_PATH=/tmp/not-the-standard-sidecar-path#SIDECAR_INSTALL_PATH=/usr/local/sbin/vless-raw-enc-argosbx-enhancer#' \
  "${WORK}/stack.sidecar-path.conf" > "${WORK}/stack.sidecar-valid.conf"
run_orchestrator --inventory "${WORK}/stack.sidecar-valid.conf" validate >/dev/null
sed 's#https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer.sh#https://example.invalid/sidecar.sh#' \
  "${WORK}/stack.sidecar-valid.conf" > "${WORK}/stack.sidecar-url.conf"
expect_validate_fail "${WORK}/stack.sidecar-url.conf" \
  "non-official sidecar source passed"

sed 's/^ARGOSBX_SOURCE_SHA256=.*/ARGOSBX_SOURCE_SHA256=/' \
  "${WORK}/stack.argosbx-valid.conf" > "${WORK}/stack.argosbx-empty-sha.conf"
expect_validate_fail "${WORK}/stack.argosbx-empty-sha.conf" \
  "enabled Argosbx with empty SHA passed"
sed 's/^PDG_INSTALL_SHA256=.*/PDG_INSTALL_SHA256=/' \
  "${WORK}/stack.conf" > "${WORK}/stack.pdg-empty-sha.conf"
expect_validate_fail "${WORK}/stack.pdg-empty-sha.conf" \
  "enabled PDG with empty SHA passed"
sed 's/^SIDECAR_SOURCE_SHA256=.*/SIDECAR_SOURCE_SHA256=/' \
  "${WORK}/stack.sidecar-valid.conf" > "${WORK}/stack.sidecar-empty-sha.conf"
expect_validate_fail "${WORK}/stack.sidecar-empty-sha.conf" \
  "enabled sidecar with empty SHA passed"
ok "all enabled remote components require a 64-digit SHA256"
cp "${WORK}/pdg.env" "${WORK}/pdg.good-repo.env"
printf 'PDG_REPO_URL=https://github.com/SchweppesSoda/proxy-gateway-plus.git\n' \
  >> "${WORK}/pdg.good-repo.env"
sed 's/PDG_ENV_FILE=pdg.env/PDG_ENV_FILE=pdg.good-repo.env/' \
  "${WORK}/stack.conf" > "${WORK}/stack.pdg-good-repo.conf"
run_orchestrator --inventory "${WORK}/stack.pdg-good-repo.conf" validate >/dev/null
cp "${WORK}/pdg.env" "${WORK}/pdg.bad-repo.env"
printf 'PDG_REPO_URL=https://example.invalid/proxy-gateway-plus.git\n' \
  >> "${WORK}/pdg.bad-repo.env"
sed 's/PDG_ENV_FILE=pdg.env/PDG_ENV_FILE=pdg.bad-repo.env/' \
  "${WORK}/stack.conf" > "${WORK}/stack.pdg-repo.conf"
if run_orchestrator --inventory "${WORK}/stack.pdg-repo.conf" validate >/dev/null 2>&1; then
  fail "non-official PDG_REPO_URL passed"
fi
ok "all executable component sources and install paths are restricted"

FAKE_COMPONENT_HOME="${WORK}/component-home"
FAKE_ARGOSBX_MANAGEMENT_PATH="${WORK}/root-bin/agsbx"
FAKE_PDG_MANAGEMENT_PATH="${WORK}/usr-local-bin/pdg"
FAKE_PDG_MARKER="${WORK}/pdg-state/firewall-mode"
FAKE_PDG_PROFILE="${WORK}/pdg-state/profile.env"
mkdir -p -- "$FAKE_COMPONENT_HOME" "$(dirname -- "$FAKE_ARGOSBX_MANAGEMENT_PATH")" \
  "$(dirname -- "$FAKE_PDG_MANAGEMENT_PATH")" "$(dirname -- "$FAKE_PDG_MARKER")"
export FAKE_COMPONENT_HOME FAKE_ARGOSBX_MANAGEMENT_PATH \
  FAKE_PDG_MANAGEMENT_PATH FAKE_PDG_MARKER FAKE_PDG_PROFILE

DEPLOY_LIB_COPY="${WORK}/orchestrator-deploy-lib.sh"
sed -e '/^main "$@"$/d' \
  -e 's#readonly COMPONENT_EXEC_PATH=.*#readonly COMPONENT_EXEC_PATH="${VALIDATION_EXEC_PATH}"#' \
  -e 's#readonly COMPONENT_EXEC_HOME="/root"#readonly COMPONENT_EXEC_HOME="${FAKE_COMPONENT_HOME}"#' \
  -e 's#readonly ARGOSBX_MANAGEMENT_PATH="/root/bin/agsbx"#readonly ARGOSBX_MANAGEMENT_PATH="${FAKE_ARGOSBX_MANAGEMENT_PATH}"#' \
  -e 's#readonly PDG_MANAGEMENT_PATH="/usr/local/bin/pdg"#readonly PDG_MANAGEMENT_PATH="${FAKE_PDG_MANAGEMENT_PATH}"#' \
  -e 's#"/etc/privdns-gateway/firewall-mode"#"${FAKE_PDG_MARKER}"#g' \
  -e 's#"/etc/privdns-gateway/profile.env"#"${FAKE_PDG_PROFILE}"#g' \
  "$SCRIPT" > "$DEPLOY_LIB_COPY"
assert_generated_main_removed "$DEPLOY_LIB_COPY"
assert_generated_token_once "$DEPLOY_LIB_COPY" \
  'readonly COMPONENT_EXEC_PATH="${VALIDATION_EXEC_PATH}"' "deploy exec path"
assert_generated_token_once "$DEPLOY_LIB_COPY" \
  'readonly COMPONENT_EXEC_HOME="${FAKE_COMPONENT_HOME}"' "deploy HOME"
assert_generated_token_once "$DEPLOY_LIB_COPY" \
  'readonly ARGOSBX_MANAGEMENT_PATH="${FAKE_ARGOSBX_MANAGEMENT_PATH}"' "deploy Argosbx path"
assert_generated_token_once "$DEPLOY_LIB_COPY" \
  'readonly PDG_MANAGEMENT_PATH="${FAKE_PDG_MANAGEMENT_PATH}"' "deploy PDG path"
assert_generated_token_once "$DEPLOY_LIB_COPY" \
  '"${FAKE_PDG_MARKER}"' "deploy PDG marker"
assert_generated_token_once "$DEPLOY_LIB_COPY" \
  '"${FAKE_PDG_PROFILE}"' "deploy PDG profile"
for production_token in \
  'readonly COMPONENT_EXEC_PATH="/root/bin:' \
  'readonly COMPONENT_EXEC_HOME="/root"' \
  'readonly ARGOSBX_MANAGEMENT_PATH="/root/bin/agsbx"' \
  'readonly PDG_MANAGEMENT_PATH="/usr/local/bin/pdg"' \
  '"/etc/privdns-gateway/firewall-mode"' \
  '"/etc/privdns-gateway/profile.env"'; do
  assert_generated_token_absent "$DEPLOY_LIB_COPY" \
    "$production_token" "deploy production path"
done

fake_root_stat() {
  local format="${2-}" path="${*: -1}"
  if [[ "$format" == "%u" ]]; then
    [[ "$path" != "${FAKE_BAD_OWNER-}" ]] \
      || { printf '1000\n'; return 0; }
    printf '0\n'
    return 0
  fi
  if [[ "$format" == "%a" ]]; then
    [[ "$path" != "${FAKE_BAD_MODE-}" ]] \
      || { printf '777\n'; return 0; }
    if [[ -d "$path" ]]; then
      printf '755\n'
    elif [[ "$path" == *.env ]]; then
      printf '600\n'
    else
      /usr/bin/stat "$@"
    fi
    return 0
  fi
  /usr/bin/stat "$@"
}

BASH_ENV_FILE="${WORK}/bash-env.sh"
BASH_ENV_SENTINEL="${WORK}/bash-env-ran"
printf 'touch %q\n' "$BASH_ENV_SENTINEL" > "$BASH_ENV_FILE"
chmod 0600 "$BASH_ENV_FILE"
MALICIOUS_CURL_HOME="${WORK}/malicious-curl-home"
mkdir -p -- "$MALICIOUS_CURL_HOME"
printf 'malicious-test-config\n' > "${MALICIOUS_CURL_HOME}/.curlrc"

ARGOSBX_CAPTURE="${WORK}/argosbx.capture"
ARGOSBX_PAYLOAD="${WORK}/argosbx-payload.sh"
cat > "$ARGOSBX_PAYLOAD" <<EOF
#!/usr/bin/env bash
set -euo pipefail
{
  printf 'argc=%s\\n' "\$#"
  printf 'arg1=%s\\n' "\${1-}"
  printf 'vlpt=%s\\n' "\${vlpt-}"
  printf 'uuid=%s\\n' "\${uuid-}"
  printf 'BASH_ENV=%s\\n' "\${BASH_ENV-unset}"
  printf 'alns=%s\\n' "\${alns-unset}"
  printf 'cfip=%s\\n' "\${cfip-unset}"
  printf 'hyjpt=%s\\n' "\${hyjpt-unset}"
} > "$ARGOSBX_CAPTURE"
printf '#!/usr/bin/env bash\\nexit 0\\n' > "$FAKE_ARGOSBX_MANAGEMENT_PATH"
chmod 0755 "$FAKE_ARGOSBX_MANAGEMENT_PATH"
EOF
chmod 0700 "$ARGOSBX_PAYLOAD"
ARGOSBX_PAYLOAD_SHA="$(sha256sum -- "$ARGOSBX_PAYLOAD")"
ARGOSBX_PAYLOAD_SHA="${ARGOSBX_PAYLOAD_SHA%% *}"

run_argosbx_case() {
  local action="$1" installed="$2" output
  sed -e "s/ARGOSBX_EXISTING_ACTION=skip/ARGOSBX_EXISTING_ACTION=${action}/" \
    -e "s/^ARGOSBX_SOURCE_SHA256=.*/ARGOSBX_SOURCE_SHA256=${ARGOSBX_PAYLOAD_SHA}/" \
    "${WORK}/stack.argosbx-valid.conf" > "${WORK}/stack.argosbx-deploy.conf"
  rm -f -- "$ARGOSBX_CAPTURE" "$BASH_ENV_SENTINEL" \
    "$CURL_LOG" "$FAKE_ARGOSBX_MANAGEMENT_PATH"
  if [[ "$installed" == "1" ]]; then
    printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE_ARGOSBX_MANAGEMENT_PATH"
    chmod 0755 "$FAKE_ARGOSBX_MANAGEMENT_PATH"
  fi
  output="$(
    (
      export PATH="${FETCH_BIN}:${PATH}"
      cp "$ARGOSBX_PAYLOAD" "$REMOTE_PAYLOAD"
      export BASH_ENV="$BASH_ENV_FILE"
      export HOME="${WORK}/malicious-curl-home" CURL_HOME="${WORK}/malicious-curl-home"
      export alns=PARENT_ONLY cfip=PARENT_ONLY hyjpt=PARENT_ONLY
      source "$DEPLOY_LIB_COPY"
      stat() { fake_root_stat "$@"; }
      INVENTORY_PATH="${WORK}/stack.argosbx-deploy.conf"
      COMMAND=""
      validate_all
      if [[ "$action" == "skip" && "$installed" == "1" ]]; then
        CONFIG[ARGOSBX_SOURCE_URL]=""
        CONFIG[ARGOSBX_SOURCE_SHA256]=""
        CONFIG[ARGOSBX_VARIABLES_FILE]="${WORK}/missing.env"
      fi
      deploy_argosbx
    ) 2>&1
  )" || fail "Argosbx ${action}/${installed} case failed"
  assert_output_redacted "$output" "Argosbx deploy output leaked a credential"
}

run_argosbx_case skip 1
[[ ! -e "$CURL_LOG" && ! -e "$ARGOSBX_CAPTURE" ]] \
  || fail "Argosbx skip downloaded or invoked the source"
run_argosbx_case rep 1
grep -Fxq 'arg1=--disable' "$CURL_LOG" \
  || fail "Argosbx rep did not fetch the verified source"
grep -Fxq 'arg1=--disable' "$CURL_LOG" \
  || fail "fetch did not pass curl --disable first"
grep -Fxq "HOME=${FAKE_COMPONENT_HOME}" "$CURL_LOG" \
  || fail "fetch inherited parent HOME"
grep -Fxq 'CURL_HOME=unset' "$CURL_LOG" \
  || fail "fetch inherited parent CURL_HOME"
[[ ! -e "$CURLRC_SENTINEL" ]] || fail "fetch consumed a parent curlrc"
grep -Fxq 'argc=1' "$ARGOSBX_CAPTURE" \
  || fail "Argosbx rep argv count is wrong"
grep -Fxq 'arg1=rep' "$ARGOSBX_CAPTURE" \
  || fail "Argosbx rep action was not passed"
grep -Fxq 'vlpt=10443' "$ARGOSBX_CAPTURE" \
  || fail "Argosbx rep omitted a whitelisted variable"
grep -Fxq 'uuid=ARGOSBX_TEST_SECRET' "$ARGOSBX_CAPTURE" \
  || fail "Argosbx rep omitted an approved sensitive value"
grep -Fxq 'BASH_ENV=unset' "$ARGOSBX_CAPTURE" \
  || fail "Argosbx inherited BASH_ENV"
grep -Fxq 'alns=unset' "$ARGOSBX_CAPTURE" \
  || fail "Argosbx inherited parent alns"
grep -Fxq 'cfip=unset' "$ARGOSBX_CAPTURE" \
  || fail "Argosbx inherited parent cfip"
grep -Fxq 'hyjpt=unset' "$ARGOSBX_CAPTURE" \
  || fail "Argosbx inherited parent hyjpt"
[[ ! -e "$BASH_ENV_SENTINEL" ]] || fail "Argosbx executed parent BASH_ENV"
run_argosbx_case skip 0
grep -Fxq 'argc=0' "$ARGOSBX_CAPTURE" \
  || fail "fresh Argosbx received an existing-instance action"
grep -Fxq 'arg1=' "$ARGOSBX_CAPTURE" \
  || fail "fresh Argosbx argv was not empty"
[[ -x "$FAKE_ARGOSBX_MANAGEMENT_PATH" ]] \
  || fail "fresh Argosbx did not create its fixed management entry"
ok "Argosbx skip, rep, fresh argv, clean environment, and postcondition hold"

ARGOSBX_NO_ENTRY_PAYLOAD="${WORK}/argosbx-no-entry.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$ARGOSBX_NO_ENTRY_PAYLOAD"
ARGOSBX_NO_ENTRY_SHA="$(sha256sum -- "$ARGOSBX_NO_ENTRY_PAYLOAD")"
ARGOSBX_NO_ENTRY_SHA="${ARGOSBX_NO_ENTRY_SHA%% *}"
sed -e "s/^ARGOSBX_SOURCE_SHA256=.*/ARGOSBX_SOURCE_SHA256=${ARGOSBX_NO_ENTRY_SHA}/" \
  "${WORK}/stack.argosbx-valid.conf" > "${WORK}/stack.argosbx-no-entry.conf"
rm -f -- "$FAKE_ARGOSBX_MANAGEMENT_PATH" "$BASH_ENV_SENTINEL"
if (
  export PATH="${FETCH_BIN}:${PATH}"
  cp "$ARGOSBX_NO_ENTRY_PAYLOAD" "$REMOTE_PAYLOAD"
  : > "$CURL_LOG"
  source "$DEPLOY_LIB_COPY"
  stat() { fake_root_stat "$@"; }
  INVENTORY_PATH="${WORK}/stack.argosbx-no-entry.conf"
  COMMAND=""
  validate_all
  deploy_argosbx
) >/dev/null 2>&1; then
  fail "Argosbx missing management-entry postcondition passed"
fi
[[ ! -e "$BASH_ENV_SENTINEL" ]] || fail "postcondition case executed parent BASH_ENV"
ok "Argosbx requires the fixed management entry after installation"

HASH_MISMATCH_SENTINEL="${WORK}/hash-mismatch-executed"
cat > "${WORK}/hash-mismatch-payload.sh" <<EOF
#!/usr/bin/env bash
touch "$HASH_MISMATCH_SENTINEL"
EOF
chmod 0700 "${WORK}/hash-mismatch-payload.sh"
cp "${WORK}/hash-mismatch-payload.sh" "$REMOTE_PAYLOAD"
sed 's/^ARGOSBX_SOURCE_SHA256=.*/ARGOSBX_SOURCE_SHA256=ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff/' \
  "${WORK}/stack.argosbx-valid.conf" > "${WORK}/stack.argosbx-wrong-hash.conf"
rm -f -- "$FAKE_ARGOSBX_MANAGEMENT_PATH" "$HASH_MISMATCH_SENTINEL"
if (
  export PATH="${FETCH_BIN}:${PATH}"
  source "$DEPLOY_LIB_COPY"
  stat() { fake_root_stat "$@"; }
  INVENTORY_PATH="${WORK}/stack.argosbx-wrong-hash.conf"
  COMMAND=""
  validate_all
  deploy_argosbx
) >/dev/null 2>&1; then
  fail "wrong remote script hash passed"
fi
[[ ! -e "$HASH_MISMATCH_SENTINEL" ]] \
  || fail "wrong-hash remote payload was executed"
[[ ! -e "$FAKE_ARGOSBX_MANAGEMENT_PATH" ]] \
  || fail "wrong-hash payload created a management entry"
ok "hash mismatch rejects remote content without execution"

prepare_argosbx_management_entry() {
  mkdir -p -- "$(dirname -- "$FAKE_ARGOSBX_MANAGEMENT_PATH")"
  printf '#!/usr/bin/env bash\ntouch %q\n' "$ARGOSBX_CAPTURE" \
    > "$FAKE_ARGOSBX_MANAGEMENT_PATH"
  chmod 0755 "$FAKE_ARGOSBX_MANAGEMENT_PATH"
  rm -f -- "$ARGOSBX_CAPTURE" "$CURL_LOG"
}
prepare_argosbx_management_entry
FAKE_BAD_MODE="$(dirname -- "$FAKE_ARGOSBX_MANAGEMENT_PATH")"
if (
  source "$DEPLOY_LIB_COPY"
  stat() { fake_root_stat "$@"; }
  CONFIG[ARGOSBX_ENABLED]=1
  CONFIG[ARGOSBX_EXISTING_ACTION]=skip
  deploy_argosbx
) >/dev/null 2>&1; then
  fail "Argosbx accepted management entry under writable parent"
fi
[[ ! -e "$ARGOSBX_CAPTURE" && ! -e "$CURL_LOG" ]] \
  || fail "Argosbx untrusted-parent case executed or downloaded"
FAKE_BAD_MODE=""

ARGOSBX_PARENT="$(dirname -- "$FAKE_ARGOSBX_MANAGEMENT_PATH")"
ARGOSBX_REAL_PARENT="${WORK}/root-bin-real"
mv -- "$ARGOSBX_PARENT" "$ARGOSBX_REAL_PARENT"
ln -s "$ARGOSBX_REAL_PARENT" "$ARGOSBX_PARENT"
if (
  source "$DEPLOY_LIB_COPY"
  stat() { fake_root_stat "$@"; }
  CONFIG[ARGOSBX_ENABLED]=1
  CONFIG[ARGOSBX_EXISTING_ACTION]=skip
  deploy_argosbx
) >/dev/null 2>&1; then
  fail "Argosbx accepted management entry under symlink parent"
fi
[[ ! -e "$ARGOSBX_CAPTURE" ]] \
  || fail "Argosbx symlink-parent case executed management entry"
rm -f -- "$ARGOSBX_PARENT"
mv -- "$ARGOSBX_REAL_PARENT" "$ARGOSBX_PARENT"
ok "Argosbx management entry rejects writable and symlink parent chains before execution"

ARGOSBX_FAIL_ACTION_SENTINEL="${WORK}/argosbx-failing-action-ran"
ARGOSBX_POST_FIREWALL_SENTINEL="${WORK}/argosbx-post-firewall-ran"
ARGOSBX_FAIL_PAYLOAD="${WORK}/argosbx-fail-payload.sh"
cat > "$ARGOSBX_FAIL_PAYLOAD" <<EOF
#!/usr/bin/env bash
set -euo pipefail
touch "$ARGOSBX_FAIL_ACTION_SENTINEL"
printf '#!/usr/bin/env bash\\nexit 0\\n' > "$FAKE_ARGOSBX_MANAGEMENT_PATH"
chmod 0755 "$FAKE_ARGOSBX_MANAGEMENT_PATH"
exit 31
EOF
ARGOSBX_FAIL_SHA="$(sha256sum -- "$ARGOSBX_FAIL_PAYLOAD")"
ARGOSBX_FAIL_SHA="${ARGOSBX_FAIL_SHA%% *}"
run_failing_argosbx_action() (
  local action="$1" installed="$2"
  cp "$ARGOSBX_FAIL_PAYLOAD" "$REMOTE_PAYLOAD"
  rm -f -- "$ARGOSBX_FAIL_ACTION_SENTINEL" "$ARGOSBX_POST_FIREWALL_SENTINEL" \
    "$FAKE_ARGOSBX_MANAGEMENT_PATH"
  if [[ "$installed" == 1 ]]; then
    printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE_ARGOSBX_MANAGEMENT_PATH"
    chmod 0755 "$FAKE_ARGOSBX_MANAGEMENT_PATH"
  fi
  source "$DEPLOY_LIB_COPY"
  stat() { fake_root_stat "$@"; }
  INVENTORY_DIR="$WORK"
  CONFIG[ARGOSBX_ENABLED]=1
  CONFIG[ARGOSBX_SOURCE_URL]=https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh
  CONFIG[ARGOSBX_SOURCE_SHA256]="$ARGOSBX_FAIL_SHA"
  CONFIG[ARGOSBX_VARIABLES_FILE]=argosbx.env
  CONFIG[ARGOSBX_EXISTING_ACTION]="$action"
  deploy_argosbx
  touch "$ARGOSBX_POST_FIREWALL_SENTINEL"
)
for failing_argosbx_case in 'rep 1' 'skip 0'; do
  read -r failing_argosbx_action failing_argosbx_installed <<< "$failing_argosbx_case"
  if run_failing_argosbx_action \
      "$failing_argosbx_action" "$failing_argosbx_installed" >/dev/null 2>&1; then
    fail "nonzero Argosbx ${failing_argosbx_action}/${failing_argosbx_installed} passed"
  fi
  [[ -e "$ARGOSBX_FAIL_ACTION_SENTINEL" ]] \
    || fail "failing Argosbx payload did not execute"
  [[ ! -e "$ARGOSBX_POST_FIREWALL_SENTINEL" ]] \
    || fail "failing Argosbx action entered post-component firewall"
done
ok "Argosbx rep and fresh nonzero actions stop before post-component firewall"

PDG_CAPTURE="${WORK}/pdg.capture"
PDG_STABLE_COMMAND="${WORK}/pdg-stable-command.sh"
cat > "$PDG_STABLE_COMMAND" <<EOF
#!/usr/bin/env bash
set -euo pipefail
{
  printf 'argc=%s\\n' "\$#"
  printf 'arg1=%s\\n' "\${1-}"
  printf 'BASH_ENV=%s\\n' "\${BASH_ENV-unset}"
  printf 'PDG_EXTRA_PARENT=%s\\n' "\${PDG_EXTRA_PARENT-unset}"
} > "$PDG_CAPTURE"
EOF
chmod 0755 "$PDG_STABLE_COMMAND"

PDG_FLIP_COMMAND="${WORK}/pdg-flip-command.sh"
cat > "$PDG_FLIP_COMMAND" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'arg1=%s\\n' "\${1-}" > "$PDG_CAPTURE"
printf 'managed\\n' > "$FAKE_PDG_MARKER"
printf 'PDG_FIREWALL_MODE=managed\\n' > "$FAKE_PDG_PROFILE"
EOF
chmod 0755 "$PDG_FLIP_COMMAND"

PDG_FAIL_COMMAND="${WORK}/pdg-fail-command.sh"
printf '#!/usr/bin/env bash\nexit 23\n' > "$PDG_FAIL_COMMAND"
chmod 0755 "$PDG_FAIL_COMMAND"

prepare_existing_pdg() {
  local source="$1"
  rm -f -- "$PDG_CAPTURE" "$FAKE_PDG_MANAGEMENT_PATH"
  cp "$source" "$FAKE_PDG_MANAGEMENT_PATH"
  chmod 0755 "$FAKE_PDG_MANAGEMENT_PATH"
  printf 'external\n' > "$FAKE_PDG_MARKER"
  printf 'PDG_FIREWALL_MODE=external\n' > "$FAKE_PDG_PROFILE"
}

run_existing_pdg_case() {
  local action="$1" source="$2" output
  prepare_existing_pdg "$source"
  rm -f -- "$BASH_ENV_SENTINEL"
  output="$(
    (
      export BASH_ENV="$BASH_ENV_FILE"
      export HOME="${WORK}/malicious-curl-home" CURL_HOME="${WORK}/malicious-curl-home"
      export PDG_EXTRA_PARENT=PARENT_ONLY
      source "$DEPLOY_LIB_COPY"
      stat() { fake_root_stat "$@"; }
      CONFIG[PDG_ENABLED]=1
      CONFIG[PDG_EXISTING_ACTION]="$action"
      deploy_pdg
    ) 2>&1
  )" || return $?
  assert_output_redacted "$output" "existing PDG output leaked a credential"
}

run_existing_pdg_case skip "$PDG_STABLE_COMMAND" \
  || fail "PDG existing skip failed"
[[ ! -e "$PDG_CAPTURE" ]] || fail "PDG skip invoked its management entry"
for pdg_action in migrate update; do
  run_existing_pdg_case "$pdg_action" "$PDG_STABLE_COMMAND" \
    || fail "PDG existing ${pdg_action} failed"
  grep -Fxq 'argc=1' "$PDG_CAPTURE" \
    || fail "PDG ${pdg_action} argv count is wrong"
  grep -Fxq "arg1=${pdg_action}" "$PDG_CAPTURE" \
    || fail "PDG ${pdg_action} action was not passed"
  grep -Fxq 'BASH_ENV=unset' "$PDG_CAPTURE" \
    || fail "PDG ${pdg_action} inherited BASH_ENV"
  grep -Fxq 'PDG_EXTRA_PARENT=unset' "$PDG_CAPTURE" \
    || fail "PDG ${pdg_action} inherited a parent PDG variable"
  [[ ! -e "$BASH_ENV_SENTINEL" ]] \
    || fail "PDG ${pdg_action} executed parent BASH_ENV"

  if run_existing_pdg_case "$pdg_action" "$PDG_FLIP_COMMAND"; then
    fail "PDG ${pdg_action} external postcondition failure passed"
  fi
  grep -Fxq "arg1=${pdg_action}" "$PDG_CAPTURE" \
    || fail "PDG ${pdg_action} postcondition case did not run the action"
done
PDG_EXISTING_POST_FIREWALL_SENTINEL="${WORK}/pdg-existing-post-firewall-ran"
run_failing_existing_pdg_action() (
  local action="$1"
  prepare_existing_pdg "$PDG_FAIL_COMMAND"
  rm -f -- "$PDG_EXISTING_POST_FIREWALL_SENTINEL"
  source "$DEPLOY_LIB_COPY"
  stat() { fake_root_stat "$@"; }
  CONFIG[PDG_ENABLED]=1
  CONFIG[PDG_EXISTING_ACTION]="$action"
  deploy_pdg
  touch "$PDG_EXISTING_POST_FIREWALL_SENTINEL"
)
for failing_pdg_action in migrate update; do
  if run_failing_existing_pdg_action "$failing_pdg_action"; then
    fail "nonzero PDG ${failing_pdg_action} action passed"
  fi
  [[ ! -e "$PDG_EXISTING_POST_FIREWALL_SENTINEL" ]] \
    || fail "failing PDG ${failing_pdg_action} entered post-component firewall"
done
ok "PDG skip/migrate/update use clean argv and enforce external postconditions"

run_pdg_migrate_direct() (
  source "$DEPLOY_LIB_COPY"
  stat() { fake_root_stat "$@"; }
  CONFIG[PDG_ENABLED]=1
  CONFIG[PDG_EXISTING_ACTION]=migrate
  deploy_pdg
)
run_pdg_status_direct() (
  source "$DEPLOY_LIB_COPY"
  stat() { fake_root_stat "$@"; }
  CONFIG[ARGOSBX_ENABLED]=0
  CONFIG[PDG_ENABLED]=1
  CONFIG[SIDECAR_ENABLED]=0
  show_status
)

prepare_existing_pdg "$PDG_STABLE_COMMAND"
FAKE_BAD_MODE="$(dirname -- "$FAKE_PDG_MANAGEMENT_PATH")"
if run_pdg_migrate_direct >/dev/null 2>&1; then
  fail "PDG accepted management entry under writable parent"
fi
[[ ! -e "$PDG_CAPTURE" ]] || fail "PDG writable management parent executed action"
FAKE_BAD_MODE=""

PDG_MANAGEMENT_PARENT="$(dirname -- "$FAKE_PDG_MANAGEMENT_PATH")"
PDG_MANAGEMENT_REAL_PARENT="${WORK}/usr-local-bin-real"
mv -- "$PDG_MANAGEMENT_PARENT" "$PDG_MANAGEMENT_REAL_PARENT"
ln -s "$PDG_MANAGEMENT_REAL_PARENT" "$PDG_MANAGEMENT_PARENT"
if run_pdg_migrate_direct >/dev/null 2>&1; then
  fail "PDG accepted management entry under symlink parent"
fi
[[ ! -e "$PDG_CAPTURE" ]] || fail "PDG symlink management parent executed action"
rm -f -- "$PDG_MANAGEMENT_PARENT"
mv -- "$PDG_MANAGEMENT_REAL_PARENT" "$PDG_MANAGEMENT_PARENT"
ok "PDG management entry rejects writable and symlink parent chains before execution"

prepare_existing_pdg "$PDG_STABLE_COMMAND"
PDG_MARKER_TARGET="${WORK}/pdg-marker-target"
cp -- "$FAKE_PDG_MARKER" "$PDG_MARKER_TARGET"
rm -f -- "$FAKE_PDG_MARKER"
ln -s "$PDG_MARKER_TARGET" "$FAKE_PDG_MARKER"
if run_pdg_migrate_direct >/dev/null 2>&1; then
  fail "existing PDG accepted symlink firewall-mode state"
fi
[[ ! -e "$PDG_CAPTURE" ]] || fail "symlink PDG state was read before action rejection"
rm -f -- "$FAKE_PDG_MARKER"

prepare_existing_pdg "$PDG_STABLE_COMMAND"
FAKE_BAD_MODE="$FAKE_PDG_MARKER"
if run_pdg_migrate_direct >/dev/null 2>&1; then
  fail "existing PDG accepted writable firewall-mode state"
fi
[[ ! -e "$PDG_CAPTURE" ]] || fail "writable PDG state allowed action execution"
FAKE_BAD_MODE=""

prepare_existing_pdg "$PDG_STABLE_COMMAND"
FAKE_BAD_OWNER="$FAKE_PDG_PROFILE"
if run_pdg_migrate_direct >/dev/null 2>&1; then
  fail "existing PDG accepted non-root profile state"
fi
[[ ! -e "$PDG_CAPTURE" ]] || fail "non-root PDG state allowed action execution"
if run_pdg_status_direct >/dev/null 2>&1; then
  fail "PDG status accepted non-root profile state"
fi
FAKE_BAD_OWNER=""

prepare_existing_pdg "$PDG_STABLE_COMMAND"
FAKE_BAD_MODE="$(dirname -- "$FAKE_PDG_MARKER")"
if run_pdg_migrate_direct >/dev/null 2>&1; then
  fail "existing PDG accepted state under writable parent"
fi
[[ ! -e "$PDG_CAPTURE" ]] || fail "untrusted PDG state parent allowed action execution"
FAKE_BAD_MODE=""
ok "existing and status PDG paths reject symlink, writable, non-root, and untrusted-parent state"

PDG_STATE_READER_POST_SENTINEL="${WORK}/pdg-state-reader-post-ran"
run_failing_pdg_state_reader() (
  local reader="$1"
  prepare_existing_pdg "$PDG_STABLE_COMMAND"
  rm -f -- "$PDG_STATE_READER_POST_SENTINEL"
  source "$DEPLOY_LIB_COPY"
  stat() { fake_root_stat "$@"; }
  case "$reader" in
    cat)
      cat() {
        [[ "${*: -1}" != "$FAKE_PDG_MARKER" ]] || return 2
        /usr/bin/cat "$@"
      }
      ;;
    grep)
      grep() {
        [[ "${*: -1}" != "$FAKE_PDG_PROFILE" ]] || return 2
        /usr/bin/grep "$@"
      }
      ;;
    sed)
      sed() {
        [[ "${*: -1}" != "$FAKE_PDG_PROFILE" ]] || return 2
        /usr/bin/sed "$@"
      }
      ;;
  esac
  assert_existing_pdg_external
  touch "$PDG_STATE_READER_POST_SENTINEL"
)
for failing_state_reader in cat grep sed; do
  if run_failing_pdg_state_reader "$failing_state_reader" >/dev/null 2>&1; then
    fail "PDG state ${failing_state_reader} read failure was masked by external evidence"
  fi
  [[ ! -e "$PDG_STATE_READER_POST_SENTINEL" ]] \
    || fail "PDG state ${failing_state_reader} failure continued after validation"
done
ok "PDG cat/grep/sed state read failures cannot be masked by alternate external evidence"

PDG_INSTALL_CAPTURE="${WORK}/pdg-install.capture"
PDG_INSTALL_PAYLOAD="${WORK}/pdg-install-payload.sh"
cat > "$PDG_INSTALL_PAYLOAD" <<EOF
#!/usr/bin/env bash
set -euo pipefail
{
  printf 'argc=%s\\n' "\$#"
  printf 'PDG_NONINTERACTIVE=%s\\n' "\${PDG_NONINTERACTIVE-}"
  printf 'PDG_FIREWALL_MODE=%s\\n' "\${PDG_FIREWALL_MODE-}"
  printf 'PDG_SERVER_IP=%s\\n' "\${PDG_SERVER_IP-}"
  printf 'PDG_QUIC_MARK=%s\\n' "\${PDG_QUIC_MARK-}"
  printf 'PDG_QUIC_MARK_MASK=%s\\n' "\${PDG_QUIC_MARK_MASK-}"
  printf 'PDG_QUIC_ROUTE_TABLE=%s\\n' "\${PDG_QUIC_ROUTE_TABLE-}"
  printf 'PDG_QUIC_RULE_PRIORITY=%s\\n' "\${PDG_QUIC_RULE_PRIORITY-}"
  printf 'PDG_BOT_TOKEN=%s\\n' "\${PDG_BOT_TOKEN-}"
  printf 'BASH_ENV=%s\\n' "\${BASH_ENV-unset}"
  printf 'PDG_EXTRA_PARENT=%s\\n' "\${PDG_EXTRA_PARENT-unset}"
  printf 'PDG_UNLISTED_PARENT=%s\\n' "\${PDG_UNLISTED_PARENT-unset}"
} > "$PDG_INSTALL_CAPTURE"
printf '#!/usr/bin/env bash\\nexit 0\\n' > "$FAKE_PDG_MANAGEMENT_PATH"
chmod 0755 "$FAKE_PDG_MANAGEMENT_PATH"
printf 'external\\n' > "$FAKE_PDG_MARKER"
printf 'PDG_FIREWALL_MODE=external\\n' > "$FAKE_PDG_PROFILE"
EOF
chmod 0700 "$PDG_INSTALL_PAYLOAD"
PDG_INSTALL_PAYLOAD_SHA="$(sha256sum -- "$PDG_INSTALL_PAYLOAD")"
PDG_INSTALL_PAYLOAD_SHA="${PDG_INSTALL_PAYLOAD_SHA%% *}"
cat > "${WORK}/stack.pdg-fresh.conf" <<EOF
STACK_INVENTORY_VERSION=1
HOST_FIREWALL_MODE=external
SERVICES_FILE=services.tsv
ARGOSBX_ENABLED=0
PDG_ENABLED=1
PDG_INSTALL_URL=https://raw.githubusercontent.com/SchweppesSoda/proxy-gateway-plus/main/install.sh
PDG_INSTALL_SHA256=${PDG_INSTALL_PAYLOAD_SHA}
PDG_ENV_FILE=pdg.env
PDG_EXISTING_ACTION=skip
SIDECAR_ENABLED=0
EOF
chmod 0600 "${WORK}/stack.pdg-fresh.conf"
rm -f -- "$FAKE_PDG_MANAGEMENT_PATH" "$FAKE_PDG_MARKER" \
  "$FAKE_PDG_PROFILE" "$PDG_INSTALL_CAPTURE" "$BASH_ENV_SENTINEL"
pdg_fresh_output="$(
  (
    export PATH="${FETCH_BIN}:${PATH}"
    cp "$PDG_INSTALL_PAYLOAD" "$REMOTE_PAYLOAD"
    : > "$CURL_LOG"
    export BASH_ENV="$BASH_ENV_FILE"
    export PDG_EXTRA_PARENT=PARENT_ONLY PDG_UNLISTED_PARENT=PARENT_ONLY
    source "$DEPLOY_LIB_COPY"
    stat() { fake_root_stat "$@"; }
    INVENTORY_PATH="${WORK}/stack.pdg-fresh.conf"
    COMMAND=""
    validate_all
    deploy_pdg
  ) 2>&1
)" || fail "fresh PDG install failed"
assert_output_redacted "$pdg_fresh_output" "fresh PDG output leaked a credential"
grep -Fxq 'argc=0' "$PDG_INSTALL_CAPTURE" \
  || fail "fresh PDG installer received argv"
grep -Fxq 'PDG_NONINTERACTIVE=1' "$PDG_INSTALL_CAPTURE" \
  || fail "fresh PDG omitted noninteractive mode"
grep -Fxq 'PDG_FIREWALL_MODE=external' "$PDG_INSTALL_CAPTURE" \
  || fail "fresh PDG did not force external firewall mode"
grep -Fxq 'PDG_SERVER_IP=203.0.113.10' "$PDG_INSTALL_CAPTURE" \
  || fail "fresh PDG omitted a whitelisted variable"
for expected_quic_setting in \
  'PDG_QUIC_MARK=0x2333' 'PDG_QUIC_MARK_MASK=0xffff' \
  'PDG_QUIC_ROUTE_TABLE=20233' 'PDG_QUIC_RULE_PRIORITY=10233'; do
  grep -Fxq "$expected_quic_setting" "$PDG_INSTALL_CAPTURE" \
    || fail "fresh PDG omitted "$expected_quic_setting""
done
grep -Fxq 'PDG_BOT_TOKEN=SENSITIVE_TEST_TOKEN' "$PDG_INSTALL_CAPTURE" \
  || fail "fresh PDG omitted an approved sensitive value"
grep -Fxq 'BASH_ENV=unset' "$PDG_INSTALL_CAPTURE" \
  || fail "fresh PDG inherited BASH_ENV"
grep -Fxq 'PDG_EXTRA_PARENT=unset' "$PDG_INSTALL_CAPTURE" \
  || fail "fresh PDG inherited an extra parent variable"
grep -Fxq 'PDG_UNLISTED_PARENT=unset' "$PDG_INSTALL_CAPTURE" \
  || fail "fresh PDG inherited an unlisted parent variable"
[[ ! -e "$BASH_ENV_SENTINEL" ]] || fail "fresh PDG executed parent BASH_ENV"
[[ -x "$FAKE_PDG_MANAGEMENT_PATH" ]] \
  || fail "fresh PDG did not create its fixed management entry"
[[ "$(cat "$FAKE_PDG_MARKER")" == "external" ]] \
  || fail "fresh PDG did not leave an external marker"
grep -Fxq 'PDG_FIREWALL_MODE=external' "$FAKE_PDG_PROFILE" \
  || fail "fresh PDG did not leave an external profile"
ok "fresh PDG passes only whitelisted clean environment and proves external ownership"

rm -f -- "$FAKE_PDG_MANAGEMENT_PATH" "$FAKE_PDG_MARKER" \
  "$FAKE_PDG_PROFILE" "$PDG_INSTALL_CAPTURE"
cp "$PDG_INSTALL_PAYLOAD" "$REMOTE_PAYLOAD"
FAKE_BAD_MODE="$FAKE_PDG_MARKER"
if (
  export PATH="${FETCH_BIN}:${PATH}"
  source "$DEPLOY_LIB_COPY"
  stat() { fake_root_stat "$@"; }
  INVENTORY_PATH="${WORK}/stack.pdg-fresh.conf"
  COMMAND=""
  validate_all
  deploy_pdg
) >/dev/null 2>&1; then
  fail "fresh PDG accepted writable installed firewall-mode state"
fi
[[ -e "$PDG_INSTALL_CAPTURE" ]] \
  || fail "fresh PDG state trust case did not reach post-install validation"
FAKE_BAD_MODE=""
ok "fresh PDG rejects untrusted installed state during postcondition validation"

PDG_FAIL_INSTALL_SENTINEL="${WORK}/pdg-failing-install-ran"
PDG_POST_FIREWALL_SENTINEL="${WORK}/pdg-post-firewall-ran"
PDG_FAIL_INSTALL_PAYLOAD="${WORK}/pdg-fail-install.sh"
cat > "$PDG_FAIL_INSTALL_PAYLOAD" <<EOF
#!/usr/bin/env bash
set -euo pipefail
touch "$PDG_FAIL_INSTALL_SENTINEL"
printf '#!/usr/bin/env bash\\nexit 0\\n' > "$FAKE_PDG_MANAGEMENT_PATH"
chmod 0755 "$FAKE_PDG_MANAGEMENT_PATH"
printf 'external\\n' > "$FAKE_PDG_MARKER"
printf 'PDG_FIREWALL_MODE=external\\n' > "$FAKE_PDG_PROFILE"
exit 32
EOF
PDG_FAIL_INSTALL_SHA="$(sha256sum -- "$PDG_FAIL_INSTALL_PAYLOAD")"
PDG_FAIL_INSTALL_SHA="${PDG_FAIL_INSTALL_SHA%% *}"
run_failing_fresh_pdg() (
  cp "$PDG_FAIL_INSTALL_PAYLOAD" "$REMOTE_PAYLOAD"
  rm -f -- "$PDG_FAIL_INSTALL_SENTINEL" "$PDG_POST_FIREWALL_SENTINEL" \
    "$FAKE_PDG_MANAGEMENT_PATH" "$FAKE_PDG_MARKER" "$FAKE_PDG_PROFILE"
  source "$DEPLOY_LIB_COPY"
  stat() { fake_root_stat "$@"; }
  INVENTORY_DIR="$WORK"
  CONFIG[PDG_ENABLED]=1
  CONFIG[PDG_INSTALL_URL]=https://raw.githubusercontent.com/SchweppesSoda/proxy-gateway-plus/main/install.sh
  CONFIG[PDG_INSTALL_SHA256]="$PDG_FAIL_INSTALL_SHA"
  CONFIG[PDG_ENV_FILE]=pdg.env
  CONFIG[PDG_EXISTING_ACTION]=skip
  deploy_pdg
  touch "$PDG_POST_FIREWALL_SENTINEL"
)
if run_failing_fresh_pdg >/dev/null 2>&1; then
  fail "nonzero fresh PDG installer passed"
fi
[[ -e "$PDG_FAIL_INSTALL_SENTINEL" ]] \
  || fail "failing fresh PDG installer did not execute"
[[ ! -e "$PDG_POST_FIREWALL_SENTINEL" ]] \
  || fail "failing fresh PDG installer entered post-component firewall"
ok "fresh PDG nonzero installer stops before post-component firewall"

SIDECAR_RUN_CAPTURE="${WORK}/sidecar.run"
SIDECAR_PAYLOAD="${WORK}/sidecar-payload.sh"
cat > "$SIDECAR_PAYLOAD" <<EOF
#!/usr/bin/env bash
set -euo pipefail
{
  printf 'argc=%s\\n' "\$#"
  printf 'BASH_ENV=%s\\n' "\${BASH_ENV-unset}"
  printf 'alns=%s\\n' "\${alns-unset}"
  printf 'PDG_EXTRA_PARENT=%s\\n' "\${PDG_EXTRA_PARENT-unset}"
} > "$SIDECAR_RUN_CAPTURE"
EOF
chmod 0700 "$SIDECAR_PAYLOAD"
SIDECAR_PAYLOAD_SHA="$(sha256sum -- "$SIDECAR_PAYLOAD")"
SIDECAR_PAYLOAD_SHA="${SIDECAR_PAYLOAD_SHA%% *}"

configure_sidecar() {
  local target="$1" action="$2" mode="$3"
  CONFIG[SIDECAR_ENABLED]=1
  CONFIG[SIDECAR_SOURCE_URL]="https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer.sh"
  CONFIG[SIDECAR_SOURCE_SHA256]="$SIDECAR_PAYLOAD_SHA"
  CONFIG[SIDECAR_INSTALL_PATH]="$target"
  CONFIG[SIDECAR_EXISTING_ACTION]="$action"
  CONFIG[SIDECAR_RUN_MODE]="$mode"
}

SIDECAR_TARGET="${WORK}/sidecar-target"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SIDECAR_TARGET"
chmod 0755 "$SIDECAR_TARGET"
rm -f -- "$CURL_LOG" "$SIDECAR_RUN_CAPTURE"
(
  source "$DEPLOY_LIB_COPY"
  stat() { fake_root_stat "$@"; }
  configure_sidecar "$SIDECAR_TARGET" keep install-only
  deploy_sidecar
) >/dev/null 2>&1 || fail "secure sidecar keep failed"
[[ ! -e "$CURL_LOG" && ! -e "$SIDECAR_RUN_CAPTURE" ]] \
  || fail "sidecar keep refreshed or ran a secure existing entry"

SIDECAR_PARENT_SENTINEL="${WORK}/unsafe-sidecar-parent-ran"
printf '#!/usr/bin/env bash\ntouch %q\n' "$SIDECAR_PARENT_SENTINEL" > "$SIDECAR_TARGET"
chmod 0755 "$SIDECAR_TARGET"
FAKE_BAD_MODE="$(dirname -- "$SIDECAR_TARGET")"
if (
  source "$DEPLOY_LIB_COPY"
  stat() { fake_root_stat "$@"; }
  configure_sidecar "$SIDECAR_TARGET" keep interactive
  deploy_sidecar
) >/dev/null 2>&1; then
  fail "sidecar accepted existing entry under writable parent"
fi
[[ ! -e "$SIDECAR_PARENT_SENTINEL" ]] \
  || fail "sidecar executed entry under writable parent"
FAKE_BAD_MODE=""

SIDECAR_REAL_PARENT="${WORK}/sidecar-real-parent"
SIDECAR_LINK_PARENT="${WORK}/sidecar-link-parent"
mkdir -p -- "$SIDECAR_REAL_PARENT"
printf '#!/usr/bin/env bash\ntouch %q\n' "$SIDECAR_PARENT_SENTINEL" \
  > "${SIDECAR_REAL_PARENT}/entry"
chmod 0755 "${SIDECAR_REAL_PARENT}/entry"
ln -s "$SIDECAR_REAL_PARENT" "$SIDECAR_LINK_PARENT"
if (
  source "$DEPLOY_LIB_COPY"
  stat() { fake_root_stat "$@"; }
  configure_sidecar "${SIDECAR_LINK_PARENT}/entry" keep interactive
  deploy_sidecar
) >/dev/null 2>&1; then
  fail "sidecar accepted existing entry under symlink parent"
fi
[[ ! -e "$SIDECAR_PARENT_SENTINEL" ]] \
  || fail "sidecar executed entry under symlink parent"
ok "sidecar management entry rejects writable and symlink parent chains before execution"

SIDE_EFFECT_TARGET="${WORK}/sidecar-symlink-target"
SIDE_EFFECT_SENTINEL="${WORK}/unsafe-sidecar-ran"
printf '#!/usr/bin/env bash\ntouch %q\n' "$SIDE_EFFECT_SENTINEL" > "$SIDE_EFFECT_TARGET"
chmod 0755 "$SIDE_EFFECT_TARGET"
rm -f -- "$SIDECAR_TARGET" "$SIDE_EFFECT_SENTINEL"
ln -s "$SIDE_EFFECT_TARGET" "$SIDECAR_TARGET"
if (
  source "$DEPLOY_LIB_COPY"
  stat() { fake_root_stat "$@"; }
  configure_sidecar "$SIDECAR_TARGET" keep interactive
  deploy_sidecar
) >/dev/null 2>&1; then
  fail "sidecar keep accepted a symlink entry"
fi
[[ ! -e "$SIDE_EFFECT_SENTINEL" ]] || fail "sidecar keep executed a symlink target"

printf 'ORIGINAL_EXTERNAL_TARGET\n' > "$SIDE_EFFECT_TARGET"
rm -f -- "$CURL_LOG" "${WORK}/sidecar.mv" "$SIDECAR_RUN_CAPTURE"
(
  export PATH="${FETCH_BIN}:${PATH}"
  cp "$SIDECAR_PAYLOAD" "$REMOTE_PAYLOAD"
  source "$DEPLOY_LIB_COPY"
  stat() { fake_root_stat "$@"; }
  install() {
    local source="${@: -2:1}" destination="${@: -1}"
    cp "$source" "$destination"
    chmod 0755 "$destination"
  }
  mv() {
    printf '%s\n' "$*" >> "${WORK}/sidecar.mv"
    command mv "$@"
  }
  configure_sidecar "$SIDECAR_TARGET" refresh install-only
  deploy_sidecar
) >/dev/null 2>&1 || fail "sidecar refresh did not replace a symlink"
[[ -f "$SIDECAR_TARGET" && ! -L "$SIDECAR_TARGET" && -x "$SIDECAR_TARGET" ]] \
  || fail "sidecar refresh did not install a regular safe entry"
grep -Fxq 'ORIGINAL_EXTERNAL_TARGET' "$SIDE_EFFECT_TARGET" \
  || fail "sidecar refresh modified the former symlink target"
grep -Fxq 'arg1=--disable' "$CURL_LOG" \
  || fail "sidecar refresh did not fetch the verified source"
grep -Eq "^-fT -- ${WORK}/\.sidecar-target\.candidate\.[^ ]+ ${SIDECAR_TARGET}$" \
  "${WORK}/sidecar.mv" \
  || fail "sidecar refresh was not a same-directory atomic rename"
[[ ! -e "$SIDECAR_RUN_CAPTURE" ]] \
  || fail "sidecar install-only ran the management entry"

chmod 0777 "$SIDECAR_TARGET"
FAKE_BAD_MODE="$SIDECAR_TARGET"
if (
  source "$DEPLOY_LIB_COPY"
  stat() { fake_root_stat "$@"; }
  configure_sidecar "$SIDECAR_TARGET" keep install-only
  deploy_sidecar
) >/dev/null 2>&1; then
  fail "sidecar keep accepted a group/other-writable entry"
fi
FAKE_BAD_MODE=""
rm -f -- "$SIDECAR_TARGET"
mkdir -- "$SIDECAR_TARGET"
rm -f -- "$CURL_LOG"
if (
  export PATH="${FETCH_BIN}:${PATH}"
  cp "$SIDECAR_PAYLOAD" "$REMOTE_PAYLOAD"
  source "$DEPLOY_LIB_COPY"
  configure_sidecar "$SIDECAR_TARGET" refresh install-only
  deploy_sidecar
) >/dev/null 2>&1; then
  fail "sidecar refresh accepted a directory target"
fi
[[ ! -e "$CURL_LOG" ]] \
  || fail "sidecar directory rejection fetched remote content"
rmdir -- "$SIDECAR_TARGET"

SIDECAR_UNTRUSTED_PARENT="${WORK}/sidecar-untrusted-candidate-parent"
SIDECAR_UNTRUSTED_TARGET="${SIDECAR_UNTRUSTED_PARENT}/entry"
mkdir -p -- "$SIDECAR_UNTRUSTED_PARENT"
rm -f -- "$CURL_LOG"
FAKE_BAD_MODE="$SIDECAR_UNTRUSTED_PARENT"
if (
  export PATH="${FETCH_BIN}:${PATH}"
  source "$DEPLOY_LIB_COPY"
  stat() { fake_root_stat "$@"; }
  configure_sidecar "$SIDECAR_UNTRUSTED_TARGET" refresh install-only
  deploy_sidecar
) >/dev/null 2>&1; then
  fail "sidecar refresh accepted untrusted candidate parent"
fi
[[ ! -e "$CURL_LOG" ]] \
  || fail "sidecar untrusted candidate parent fetched payload"
if find "$SIDECAR_UNTRUSTED_PARENT" -name '.entry.candidate.*' -print -quit | grep -q .; then
  fail "sidecar untrusted candidate parent created candidate"
fi
FAKE_BAD_MODE=""

SIDECAR_POST_PARENT="${WORK}/sidecar-postcheck-parent"
SIDECAR_POST_TARGET="${SIDECAR_POST_PARENT}/entry"
mkdir -p -- "$SIDECAR_POST_PARENT"
rm -f -- "$SIDECAR_RUN_CAPTURE"
if (
  export PATH="${FETCH_BIN}:${PATH}"
  cp "$SIDECAR_PAYLOAD" "$REMOTE_PAYLOAD"
  source "$DEPLOY_LIB_COPY"
  stat() { fake_root_stat "$@"; }
  install() {
    local source="${@: -2:1}" destination="${@: -1}"
    cp "$source" "$destination"
    chmod 0755 "$destination"
  }
  mv() {
    /usr/bin/mv "$@" || return
    FAKE_BAD_OWNER="$SIDECAR_POST_TARGET"
  }
  configure_sidecar "$SIDECAR_POST_TARGET" refresh interactive
  deploy_sidecar
) >/dev/null 2>&1; then
  fail "sidecar accepted unsafe target after atomic replacement"
fi
[[ ! -e "$SIDECAR_RUN_CAPTURE" ]] \
  || fail "sidecar executed target that failed post-rename safety check"
ok "sidecar validates candidate parent before fetch and target safety after atomic rename"

rm -f -- "$SIDECAR_RUN_CAPTURE" "$BASH_ENV_SENTINEL"
sidecar_interactive_output="$(
  (
    export PATH="${FETCH_BIN}:${PATH}"
    cp "$SIDECAR_PAYLOAD" "$REMOTE_PAYLOAD"
    : > "$CURL_LOG"
    export BASH_ENV="$BASH_ENV_FILE"
    export alns=PARENT_ONLY PDG_EXTRA_PARENT=PARENT_ONLY
    source "$DEPLOY_LIB_COPY"
    stat() { fake_root_stat "$@"; }
    install() {
      local source="${@: -2:1}" destination="${@: -1}"
      cp "$source" "$destination"
      chmod 0755 "$destination"
    }
    configure_sidecar "$SIDECAR_TARGET" refresh interactive
    deploy_sidecar
  ) 2>&1
)" || fail "sidecar interactive install failed"
assert_output_redacted "$sidecar_interactive_output" \
  "sidecar interactive output leaked a credential"
grep -Fxq 'argc=0' "$SIDECAR_RUN_CAPTURE" \
  || fail "sidecar interactive entry received argv"
grep -Fxq 'BASH_ENV=unset' "$SIDECAR_RUN_CAPTURE" \
  || fail "sidecar interactive entry inherited BASH_ENV"
grep -Fxq 'alns=unset' "$SIDECAR_RUN_CAPTURE" \
  || fail "sidecar interactive entry inherited parent alns"
grep -Fxq 'PDG_EXTRA_PARENT=unset' "$SIDECAR_RUN_CAPTURE" \
  || fail "sidecar interactive entry inherited a parent PDG variable"
[[ ! -e "$BASH_ENV_SENTINEL" ]] || fail "sidecar executed parent BASH_ENV"

SIDECAR_FAIL_ACTION_SENTINEL="${WORK}/sidecar-failing-interactive-ran"
SIDECAR_POST_FIREWALL_SENTINEL="${WORK}/sidecar-post-firewall-ran"
printf '#!/usr/bin/env bash\ntouch %q\nexit 33\n' \
  "$SIDECAR_FAIL_ACTION_SENTINEL" > "$SIDECAR_TARGET"
chmod 0755 "$SIDECAR_TARGET"
rm -f -- "$SIDECAR_FAIL_ACTION_SENTINEL" "$SIDECAR_POST_FIREWALL_SENTINEL"
run_failing_sidecar_interactive() (
  source "$DEPLOY_LIB_COPY"
  stat() { fake_root_stat "$@"; }
  configure_sidecar "$SIDECAR_TARGET" keep interactive
  deploy_sidecar
  touch "$SIDECAR_POST_FIREWALL_SENTINEL"
)
if run_failing_sidecar_interactive >/dev/null 2>&1; then
  fail "nonzero sidecar interactive action passed"
fi
[[ -e "$SIDECAR_FAIL_ACTION_SENTINEL" ]] \
  || fail "failing sidecar interactive entry did not execute"
[[ ! -e "$SIDECAR_POST_FIREWALL_SENTINEL" ]] \
  || fail "failing sidecar interactive entered post-component firewall"
ok "sidecar interactive nonzero action stops before post-component firewall"

SIDECAR_PREEXEC_SENTINEL="${WORK}/sidecar-preexec-ran"
printf '#!/usr/bin/env bash\ntouch %q\n' "$SIDECAR_PREEXEC_SENTINEL" > "$SIDECAR_TARGET"
chmod 0755 "$SIDECAR_TARGET"
SIDECAR_OWNER_COUNT="${WORK}/sidecar-owner.count"
rm -f -- "$SIDECAR_OWNER_COUNT" "$SIDECAR_PREEXEC_SENTINEL"
sidecar_preexec_stat() {
  local format="${2-}" path="${*: -1}" count=0
  if [[ "$format" == "%u" && "$path" == "$SIDECAR_TARGET" ]]; then
    [[ ! -f "$SIDECAR_OWNER_COUNT" ]] || count="$(cat "$SIDECAR_OWNER_COUNT")"
    count=$((count + 1))
    printf '%s\n' "$count" > "$SIDECAR_OWNER_COUNT"
    (( count == 1 )) && printf '0\n' || printf '1000\n'
    return 0
  fi
  fake_root_stat "$@"
}
if (
  source "$DEPLOY_LIB_COPY"
  stat() { sidecar_preexec_stat "$@"; }
  configure_sidecar "$SIDECAR_TARGET" keep interactive
  deploy_sidecar
) >/dev/null 2>&1; then
  fail "sidecar omitted the interactive pre-execution safety recheck"
fi
[[ ! -e "$SIDECAR_PREEXEC_SENTINEL" ]] \
  || fail "sidecar executed entry that became unsafe before interactive run"
ok "sidecar keep/refresh/run modes enforce candidate, post-rename, and pre-exec trust"
TRUST_ROOT="${WORK}/trust-root"
TRUST_PARENT="${TRUST_ROOT}/private"
TRUST_INPUT="${TRUST_PARENT}/stack.conf"
mkdir -p -- "$TRUST_PARENT"
printf 'test\n' > "$TRUST_INPUT"
chmod 0644 "$TRUST_INPUT"
TRUST_BAD_OWNER=""
TRUST_BAD_MODE=""
TRUST_BAD_DIRECTORY=""
trusted_stat() {
  local format="${2-}" path="${@: -1}"
  if [[ "$format" == "%u" ]]; then
    [[ "$path" != "$TRUST_BAD_OWNER" ]] || { printf '1000\n'; return 0; }
    printf '0\n'
    return 0
  fi
  if [[ "$format" == "%a" ]]; then
    [[ "$path" != "$TRUST_BAD_MODE" && "$path" != "$TRUST_BAD_DIRECTORY" ]] \
      || { printf '777\n'; return 0; }
    if [[ -d "$path" ]]; then
      printf '755\n'
    elif [[ -n "${TRUST_COMPONENT_ENV-}" && "$path" == "$TRUST_COMPONENT_ENV" ]]; then
      printf '600\n'
    else
      /usr/bin/stat "$@"
    fi
    return 0
  fi
  /usr/bin/stat "$@"
}
(
  source "$DEPLOY_LIB_COPY"
  stat() { trusted_stat "$@"; }
  require_root_owned_mutation_input "$TRUST_INPUT" "test input"
) >/dev/null 2>&1 || fail "trusted ordinary input failed"
TRUST_BAD_OWNER="$TRUST_INPUT"
if (
  source "$DEPLOY_LIB_COPY"
  stat() { trusted_stat "$@"; }
  require_root_owned_mutation_input "$TRUST_INPUT" "test input"
) >/dev/null 2>&1; then
  fail "non-root-owned mutation input passed"
fi
TRUST_BAD_OWNER=""
TRUST_BAD_MODE="$TRUST_INPUT"
if (
  source "$DEPLOY_LIB_COPY"
  stat() { trusted_stat "$@"; }
  require_root_owned_mutation_input "$TRUST_INPUT" "test input"
) >/dev/null 2>&1; then
  fail "group/other-writable mutation input passed"
fi
TRUST_BAD_MODE=""
TRUST_BAD_DIRECTORY="$TRUST_PARENT"
if (
  source "$DEPLOY_LIB_COPY"
  stat() { trusted_stat "$@"; }
  require_root_owned_mutation_input "$TRUST_INPUT" "test input"
) >/dev/null 2>&1; then
  fail "writable mutation parent chain passed"
fi
TRUST_BAD_DIRECTORY=""
ln -s "$TRUST_PARENT" "${TRUST_ROOT}/linked-parent"
if (
  source "$DEPLOY_LIB_COPY"
  stat() { trusted_stat "$@"; }
  require_root_owned_mutation_input "${TRUST_ROOT}/linked-parent/stack.conf" "test input"
) >/dev/null 2>&1; then
  fail "symlink mutation parent chain passed"
fi
if (
  source "$DEPLOY_LIB_COPY"
  stat() { trusted_stat "$@"; }
  require_root_owned_mutation_input "${TRUST_PARENT}/../private/stack.conf" "test input"
) >/dev/null 2>&1; then
  fail "noncanonical mutation input path passed"
fi

TRUST_COMPONENT_ENV="${TRUST_PARENT}/pdg.env"
cp "${WORK}/pdg.env" "$TRUST_COMPONENT_ENV"
chmod 0600 "$TRUST_COMPONENT_ENV"
(
  source "$DEPLOY_LIB_COPY"
  stat() { trusted_stat "$@"; }
  COMMAND=deploy
  load_component_env pdg "$TRUST_COMPONENT_ENV"
) >/dev/null 2>&1 || fail "trusted component environment failed deploy checks"
TRUST_BAD_DIRECTORY="$TRUST_PARENT"
if (
  source "$DEPLOY_LIB_COPY"
  stat() { trusted_stat "$@"; }
  COMMAND=deploy
  load_component_env pdg "$TRUST_COMPONENT_ENV"
) >/dev/null 2>&1; then
  fail "component environment under writable parent passed"
fi
TRUST_BAD_DIRECTORY=""
ok "mutation inputs and component env enforce owner, mode, canonical, and full parent trust"

if (
  source "$DEPLOY_LIB_COPY"
  MUTATION_LOCK_FILE="${WORK}/mutation.lock"
  flock() { return 1; }
  acquire_mutation_lock
) >/dev/null 2>&1; then
  fail "contended mutation lock passed"
fi
ok "mutation lock fails closed on concurrent ownership"
grep -Fq 'PDG_FIREWALL_MODE=external' "$SCRIPT" \
  || fail "PDG external mode is not forced"
check_line="$(grep -n 'nft -c -f "$batch"' "$SCRIPT" | cut -d: -f1)"
apply_line="$(grep -n 'if ! nft -f "$batch"' "$SCRIPT" | cut -d: -f1)"
[[ -n "$check_line" && -n "$apply_line" && "$check_line" -lt "$apply_line" ]] \
  || fail "nft preflight/apply ordering is wrong"
[[ "$(grep -c 'nft -f "$batch"' "$SCRIPT")" -eq 1 ]] \
  || fail "firewall has more than one formal nft apply"
ok "PDG/firewall ownership and atomic apply contracts hold"

REAL_MV="$(command -v mv)"
{
  printf '#!/usr/bin/env bash\n'
  cat <<'EOF'
set -euo pipefail
count=0
[[ ! -f "${FAKE_MV_COUNT}" ]] || count="$(cat "${FAKE_MV_COUNT}")"
count=$((count + 1))
printf '%s\n' "$count" > "${FAKE_MV_COUNT}"
printf '%s\n' "$*" >> "${FAKE_MV_LOG}"
[[ -z "${FAKE_MV_FAIL_AT:-}" || "$count" -ne "$FAKE_MV_FAIL_AT" ]] || exit 1
EOF
  printf 'exec %q "$@"\n' "$REAL_MV"
} > "${TEST_BIN}/mv"

cat > "${TEST_BIN}/nft" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${FAKE_NFT_LOG}"
if [[ "$#" -eq 3 && "$1" == "-j" && "$2" == "list" && "$3" == "ruleset" ]]; then
  [[ ! -f "${FAKE_NFT_RULESET_FILE}" ]] \
    || cat "${FAKE_NFT_RULESET_FILE}"
  [[ -f "${FAKE_NFT_RULESET_FILE}" ]] \
    || printf '{"nftables":[]}\n'
  exit 0
fi
if [[ "$#" -eq 3 && "$1" == "-c" && "$2" == "-f" ]]; then
  count=0
  [[ ! -f "${FAKE_NFT_CHECK_COUNT}" ]] \
    || count="$(cat "${FAKE_NFT_CHECK_COUNT}")"
  count=$((count + 1))
  printf '%s\n' "$count" > "${FAKE_NFT_CHECK_COUNT}"
  cp "$3" "${FAKE_NFT_CHECK_PREFIX}.${count}"
  [[ -z "${FAKE_NFT_FAIL_CHECK_AT:-}" || "$count" -ne "$FAKE_NFT_FAIL_CHECK_AT" ]]
  exit
fi
if [[ "$#" -eq 2 && "$1" == "-f" ]]; then
  cp "$2" "${FAKE_NFT_FORMAL_BATCH}"
  [[ "${FAKE_NFT_FAIL_FORMAL:-0}" != "1" ]]
  exit
fi
exit 2
EOF

cat > "${TEST_BIN}/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${FAKE_SYSTEMCTL_LOG}"
exit 0
EOF
chmod +x "${TEST_BIN}/mv" "${TEST_BIN}/nft" "${TEST_BIN}/systemctl"

LIB_COPY="${WORK}/orchestrator-firewall-lib.sh"
sed -e '/^main "$@"$/d' \
  -e 's#^NFTABLES_MAIN_CONFIG=.*#NFTABLES_MAIN_CONFIG="${WORK}/lib-default-nftables.conf"#' \
  -e 's#^NFTABLES_POLICY_FILE=.*#NFTABLES_POLICY_FILE="${WORK}/lib-default-vps-toolkit-proxy-stack.nft"#' \
  -e 's#readonly COMPONENT_EXEC_PATH=.*#readonly COMPONENT_EXEC_PATH="${TEST_BIN}:${VALIDATION_EXEC_PATH}"#' \
  -e 's#readonly ARGOSBX_MANAGEMENT_PATH=.*#readonly ARGOSBX_MANAGEMENT_PATH="${FAKE_ARGOSBX_MANAGEMENT_PATH}"#' \
  -e 's#readonly PDG_MANAGEMENT_PATH=.*#readonly PDG_MANAGEMENT_PATH="${FAKE_PDG_MANAGEMENT_PATH}"#' \
  -e 's#"/etc/privdns-gateway/firewall-mode"#"${FAKE_PDG_MARKER}"#g' \
  -e 's#"/etc/privdns-gateway/profile.env"#"${FAKE_PDG_PROFILE}"#g' \
  -e '/\[\[ "$EUID" -eq 0 \]\] || die/s/^.*$/      : # isolated root shim/' \
  "$SCRIPT" > "$LIB_COPY"
assert_generated_main_removed "$LIB_COPY"
assert_generated_token_once "$LIB_COPY" \
  'NFTABLES_MAIN_CONFIG="${WORK}/lib-default-nftables.conf"' "firewall default main"
assert_generated_token_once "$LIB_COPY" \
  'NFTABLES_POLICY_FILE="${WORK}/lib-default-vps-toolkit-proxy-stack.nft"' "firewall default policy"
assert_generated_token_once "$LIB_COPY" \
  'readonly COMPONENT_EXEC_PATH="${TEST_BIN}:${VALIDATION_EXEC_PATH}"' "firewall exec path"
assert_generated_token_once "$LIB_COPY" \
  'readonly ARGOSBX_MANAGEMENT_PATH="${FAKE_ARGOSBX_MANAGEMENT_PATH}"' "firewall Argosbx path"
assert_generated_token_once "$LIB_COPY" \
  'readonly PDG_MANAGEMENT_PATH="${FAKE_PDG_MANAGEMENT_PATH}"' "firewall PDG path"
assert_generated_token_once "$LIB_COPY" \
  '"${FAKE_PDG_MARKER}"' "firewall PDG marker"
assert_generated_token_once "$LIB_COPY" \
  '"${FAKE_PDG_PROFILE}"' "firewall PDG profile"
assert_generated_token_once "$LIB_COPY" \
  ': # isolated root shim' "firewall root shim"
for production_token in \
  ':-/etc/nftables.conf' \
  ':-/etc/nftables.d/vps-toolkit-proxy-stack.nft' \
  'readonly COMPONENT_EXEC_PATH="/root/bin:' \
  'readonly ARGOSBX_MANAGEMENT_PATH="/root/bin/agsbx"' \
  'readonly PDG_MANAGEMENT_PATH="/usr/local/bin/pdg"' \
  '"/etc/privdns-gateway/firewall-mode"' \
  '"/etc/privdns-gateway/profile.env"' \
  '[[ "$EUID" -eq 0 ]] || die'; do
  assert_generated_token_absent "$LIB_COPY" \
    "$production_token" "firewall production path/root check"
done
PERSIST_INVENTORY="${WORK}/stack.persist.conf"
sed 's/HOST_FIREWALL_PERSIST=0/HOST_FIREWALL_PERSIST=1/' \
  "${WORK}/stack.conf" > "$PERSIST_INVENTORY"
EXTERNAL_INVENTORY="${WORK}/stack.external.conf"
sed 's/HOST_FIREWALL_MODE=managed/HOST_FIREWALL_MODE=external/' \
  "${WORK}/stack.conf" > "$EXTERNAL_INVENTORY"

RUNTIME_ROOT="${WORK}/runtime"
MAIN_CONFIG="${RUNTIME_ROOT}/nftables.conf"
POLICY_FILE="${RUNTIME_ROOT}/nftables.d/vps-toolkit-proxy-stack.nft"
mkdir -p -- "$(dirname -- "$POLICY_FILE")"

export FAKE_NFT_LOG="${WORK}/fake-nft.log"
export FAKE_NFT_CHECK_COUNT="${WORK}/fake-nft-check.count"
export FAKE_NFT_CHECK_PREFIX="${WORK}/fake-nft-check"
export FAKE_NFT_FORMAL_BATCH="${WORK}/fake-nft-formal.batch"
export FAKE_NFT_RULESET_FILE="${WORK}/fake-nft-ruleset.json"
export FAKE_MV_COUNT="${WORK}/fake-mv.count"
export FAKE_MV_LOG="${WORK}/fake-mv.log"
export FAKE_SYSTEMCTL_LOG="${WORK}/fake-systemctl.log"
FAKE_NFT_FAIL_CHECK_AT=""
FAKE_NFT_FAIL_FORMAL=0
FAKE_MV_FAIL_AT=""
FAKE_UNTRUSTED_PATH=""
FAKE_NONROOT_PATH=""
export FAKE_NFT_FAIL_CHECK_AT FAKE_NFT_FAIL_FORMAL FAKE_MV_FAIL_AT

firewall_stat() {
  local format="${2-}" path="${@: -1}"
  if [[ "$format" == "%u" ]]; then
    [[ "$path" != "$FAKE_NONROOT_PATH" ]] \
      || { printf '1000\n'; return 0; }
    printf '0\n'
    return 0
  fi
  if [[ "$format" == "%a" ]]; then
    [[ "$path" != "$FAKE_UNTRUSTED_PATH" ]] \
      || { printf '777\n'; return 0; }
    if [[ -d "$path" ]]; then
      printf '755\n'
    else
      /usr/bin/stat "$@"
    fi
    return 0
  fi
  /usr/bin/stat "$@"
}

reset_firewall_mocks() {
  : > "$FAKE_NFT_LOG"
  : > "$FAKE_MV_COUNT"
  : > "$FAKE_MV_LOG"
  : > "$FAKE_SYSTEMCTL_LOG"
  rm -f -- "$FAKE_NFT_CHECK_COUNT" "$FAKE_NFT_FORMAL_BATCH" \
    "${FAKE_NFT_CHECK_PREFIX}.1" "${FAKE_NFT_CHECK_PREFIX}.2" \
    "$FAKE_NFT_RULESET_FILE"
  FAKE_NFT_FAIL_CHECK_AT=""
  FAKE_NFT_FAIL_FORMAL=0
  FAKE_MV_FAIL_AT=""
  FAKE_UNTRUSTED_PATH=""
  FAKE_NONROOT_PATH=""
  export FAKE_NFT_FAIL_CHECK_AT FAKE_NFT_FAIL_FORMAL FAKE_MV_FAIL_AT
}

run_fake_apply() (
  export PATH="${TEST_BIN}:${PATH}"
  source "$LIB_COPY"
  stat() { firewall_stat "$@"; }
  INVENTORY_PATH="$PERSIST_INVENTORY"
  NFTABLES_MAIN_CONFIG="$MAIN_CONFIG"
  NFTABLES_POLICY_FILE="$POLICY_FILE"
  COMMAND=""
  validate_all
  apply_firewall
)

run_fake_external_apply() (
  export PATH="${TEST_BIN}:${PATH}"
  source "$LIB_COPY"
  INVENTORY_PATH="$EXTERNAL_INVENTORY"
  COMMAND=""
  validate_all
  apply_firewall
)

run_fake_interrupted_prepare() (
  export PATH="${TEST_BIN}:${PATH}"
  source "$LIB_COPY"
  stat() { firewall_stat "$@"; }
  INVENTORY_PATH="$PERSIST_INVENTORY"
  NFTABLES_MAIN_CONFIG="$MAIN_CONFIG"
  NFTABLES_POLICY_FILE="$POLICY_FILE"
  COMMAND=""
  validate_all
  new_temp_file
  render_firewall_batch > "$NEW_TEMP_FILE"
  nft -c -f "$NEW_TEMP_FILE"
  prepare_firewall_persistence "$NEW_TEMP_FILE"
  exit 73
)

run_fake_rollback_failure() (
  export PATH="${TEST_BIN}:${PATH}"
  source "$LIB_COPY"
  stat() { firewall_stat "$@"; }
  INVENTORY_PATH="$PERSIST_INVENTORY"
  NFTABLES_MAIN_CONFIG="$MAIN_CONFIG"
  NFTABLES_POLICY_FILE="$POLICY_FILE"
  COMMAND=""
  validate_all
  rollback_firewall_persistence() {
    PERSISTENCE_RESTORE_FAILED=1
    return 1
  }
  apply_firewall
)

count_nft_checks() {
  grep -c '^-c -f ' "$FAKE_NFT_LOG" || true
}

count_nft_formal() {
  grep -c '^-f ' "$FAKE_NFT_LOG" || true
}

assert_no_nft_check_or_apply() {
  [[ "$(count_nft_checks)" -eq 0 && "$(count_nft_formal)" -eq 0 ]] \
    || fail "$1"
}
assert_no_nft_invocation() {
  [[ ! -s "$FAKE_NFT_LOG" ]] || fail "$1"
}

assert_two_checks_one_apply() {
  [[ "$(count_nft_checks)" -eq 2 ]] \
    || fail "$1: expected two nft checks"
  [[ "$(count_nft_formal)" -eq 1 ]] \
    || fail "$1: expected one formal nft apply"
  local first_check second_check formal
  first_check="$(grep -n '^-c -f ' "$FAKE_NFT_LOG" | sed -n '1s/:.*//p')"
  second_check="$(grep -n '^-c -f ' "$FAKE_NFT_LOG" | sed -n '2s/:.*//p')"
  formal="$(grep -n '^-f ' "$FAKE_NFT_LOG" | sed -n '1s/:.*//p')"
  [[ "$first_check" -lt "$second_check" && "$second_check" -lt "$formal" ]] \
    || fail "$1: nft operation order is wrong"
}

reset_firewall_mocks
external_output="$(run_fake_external_apply 2>&1)" \
  || fail "external firewall apply failed"
assert_output_redacted "$external_output" "external firewall output leaked a credential"
[[ ! -s "$FAKE_NFT_LOG" ]] || fail "external mode invoked nft"
ok "external mode parses inventory but never invokes nft"

run_main_untrusted_inventory() (
  source "$LIB_COPY"
  NFTABLES_MAIN_CONFIG="$MAIN_CONFIG"
  NFTABLES_POLICY_FILE="$POLICY_FILE"
  stat() { firewall_stat "$@"; }
  acquire_mutation_lock() { :; }
  unset SSH_CONNECTION
  main --inventory "$PERSIST_INVENTORY" firewall-apply
)
for inventory_trust_failure in mode owner parent; do
  reset_firewall_mocks
  case "$inventory_trust_failure" in
    mode) FAKE_UNTRUSTED_PATH="$PERSIST_INVENTORY" ;;
    owner) FAKE_NONROOT_PATH="$PERSIST_INVENTORY" ;;
    parent) FAKE_UNTRUSTED_PATH="$(dirname -- "$PERSIST_INVENTORY")" ;;
  esac
  if run_main_untrusted_inventory >/dev/null 2>&1; then
    fail "main firewall-apply accepted untrusted inventory ${inventory_trust_failure}"
  fi
  assert_no_nft_invocation "untrusted inventory reached nft through main"
done
FAKE_UNTRUSTED_PATH=""
FAKE_NONROOT_PATH=""
ok "main mutation path wires inventory owner/mode/full-parent trust before nft"

run_ssh_guard() (
  local connection="$1" inventory="${2:-$PERSIST_INVENTORY}"
  export PATH="${TEST_BIN}:${PATH}"
  source "$LIB_COPY"
  stat() { firewall_stat "$@"; }
  INVENTORY_PATH="$inventory"
  COMMAND=""
  validate_all
  COMMAND=firewall-apply
  if [[ "$connection" == "<console>" ]]; then
    unset SSH_CONNECTION
  else
    SSH_CONNECTION="$connection"
  fi
  validate_active_ssh_remote_admin
)

reset_firewall_mocks
run_ssh_guard '198.51.100.25 40000 203.0.113.10 55022' \
  || fail "covered active SSH session failed"
if run_ssh_guard '198.51.100.25 40000 203.0.113.10 22' >/dev/null 2>&1; then
  fail "active SSH server-port mismatch passed"
fi
if run_ssh_guard '203.0.113.25 40000 203.0.113.10 55022' >/dev/null 2>&1; then
  fail "active SSH client-source mismatch passed"
fi
if run_ssh_guard '198.51.100.25 40000 203.0.113.10' >/dev/null 2>&1; then
  fail "malformed SSH_CONNECTION passed"
fi
run_ssh_guard '<console>' >/dev/null 2>&1 \
  || fail "console recovery scenario without SSH_CONNECTION failed"
assert_no_nft_invocation "SSH session guard invoked nft"

run_main_ssh_mismatch() (
  source "$LIB_COPY"
  NFTABLES_MAIN_CONFIG="$MAIN_CONFIG"
  NFTABLES_POLICY_FILE="$POLICY_FILE"
  stat() { firewall_stat "$@"; }
  acquire_mutation_lock() { :; }
  SSH_CONNECTION='198.51.100.25 40000 203.0.113.10 22'
  main --inventory "$PERSIST_INVENTORY" firewall-apply
)
reset_firewall_mocks
if run_main_ssh_mismatch >/dev/null 2>&1; then
  fail "main firewall-apply accepted an uncovered active SSH session"
fi
assert_no_nft_invocation "main SSH guard failure reached any nft invocation"
ok "active SSH session guard is wired through main before every nft operation"

printf '#!/usr/sbin/nft -f\nflush ruleset\n' > "$MAIN_CONFIG"
chmod 0644 "$MAIN_CONFIG"
rm -f -- "$POLICY_FILE"
run_bad_persistence_path() (
  local kind="$1" bad_path="$2"
  export PATH="${TEST_BIN}:${PATH}"
  source "$LIB_COPY"
  stat() { firewall_stat "$@"; }
  INVENTORY_PATH="$PERSIST_INVENTORY"
  COMMAND=""
  validate_all
  NFTABLES_MAIN_CONFIG="$MAIN_CONFIG"
  NFTABLES_POLICY_FILE="$POLICY_FILE"
  if [[ "$kind" == "main" ]]; then
    NFTABLES_MAIN_CONFIG="$bad_path"
  else
    NFTABLES_POLICY_FILE="$bad_path"
  fi
  apply_firewall
)

bad_nft_paths=(
  'relative/path'
  "${RUNTIME_ROOT}//duplicate"
  "${RUNTIME_ROOT}/./dot-segment"
  "${RUNTIME_ROOT}/parent/../dotdot-segment"
  "${RUNTIME_ROOT}/with space"
  "${RUNTIME_ROOT}/bad\"quote"
  "${RUNTIME_ROOT}/bad\\backslash"
  "${RUNTIME_ROOT}/bad*glob"
  "${RUNTIME_ROOT}/bad?glob"
  "${RUNTIME_ROOT}/bad[glob"
)
for bad_path in "${bad_nft_paths[@]}"; do
  for bad_kind in main policy; do
    reset_firewall_mocks
    if run_bad_persistence_path "$bad_kind" "$bad_path" >/dev/null 2>&1; then
      fail "unsafe nft ${bad_kind} path passed: ${bad_path}"
    fi
    assert_no_nft_invocation "unsafe nft path invoked nft"
  done
done
if find "$RUNTIME_ROOT" -name '*.candidate.*' -print -quit | grep -q .; then
  fail "unsafe nft path left a persistence candidate"
fi
ok "nft main/policy paths reject noncanonical and injectable characters before mutation"

MAIN_TARGET="${RUNTIME_ROOT}/main-symlink-target"
printf 'ORIGINAL_MAIN_TARGET\n' > "$MAIN_TARGET"
rm -f -- "$MAIN_CONFIG"
ln -s "$MAIN_TARGET" "$MAIN_CONFIG"
reset_firewall_mocks
if run_fake_apply >/dev/null 2>&1; then
  fail "symlink nft main config passed"
fi
grep -Fxq 'ORIGINAL_MAIN_TARGET' "$MAIN_TARGET" \
  || fail "symlink main target was modified"
assert_no_nft_invocation "symlink main invoked nft"
rm -f -- "$MAIN_CONFIG"
printf '#!/usr/sbin/nft -f\nflush ruleset\n' > "$MAIN_CONFIG"

POLICY_TARGET="${RUNTIME_ROOT}/policy-symlink-target"
printf 'ORIGINAL_POLICY_TARGET\n' > "$POLICY_TARGET"
rm -f -- "$POLICY_FILE"
ln -s "$POLICY_TARGET" "$POLICY_FILE"
reset_firewall_mocks
if run_fake_apply >/dev/null 2>&1; then
  fail "symlink nft policy passed"
fi
grep -Fxq 'ORIGINAL_POLICY_TARGET' "$POLICY_TARGET" \
  || fail "symlink policy target was modified"
assert_no_nft_invocation "symlink policy invoked nft"
rm -f -- "$POLICY_FILE"

REAL_PERSIST_DIR="${WORK}/real-persist-parent"
LINKED_PERSIST_DIR="${WORK}/linked-persist-parent"
mkdir -p -- "$REAL_PERSIST_DIR"
printf '#!/usr/sbin/nft -f\nflush ruleset\n' > "${REAL_PERSIST_DIR}/nftables.conf"
ln -s "$REAL_PERSIST_DIR" "$LINKED_PERSIST_DIR"
SAVED_MAIN_CONFIG="$MAIN_CONFIG"
SAVED_POLICY_FILE="$POLICY_FILE"
MAIN_CONFIG="${LINKED_PERSIST_DIR}/nftables.conf"
POLICY_FILE="${REAL_PERSIST_DIR}/policy.nft"
reset_firewall_mocks
if run_fake_apply >/dev/null 2>&1; then
  fail "persistence main under symlink parent passed"
fi
assert_no_nft_invocation "symlink persistence parent invoked nft"
MAIN_CONFIG="$SAVED_MAIN_CONFIG"
POLICY_FILE="$SAVED_POLICY_FILE"

printf '#!/usr/sbin/nft -f\nflush ruleset\n' > "$MAIN_CONFIG"
rm -f -- "$POLICY_FILE"
FAKE_UNTRUSTED_PATH="$(dirname -- "$POLICY_FILE")"
reset_firewall_mocks
FAKE_UNTRUSTED_PATH="$(dirname -- "$POLICY_FILE")"
if run_fake_apply >/dev/null 2>&1; then
  fail "persistence policy under writable parent passed"
fi
assert_no_nft_invocation "writable persistence parent invoked nft"
FAKE_UNTRUSTED_PATH=""
ok "persistence main/policy reject symlink targets and untrusted full parent chains"

run_real_foreign_parser() (
  local ruleset_file="$1"
  source "$REAL_LIB"
  nft() { cat "$ruleset_file"; }
  assert_no_foreign_input_base_chain
)
for foreign_family in inet ip ip6; do
  real_foreign_ruleset="${WORK}/foreign-${foreign_family}.json"
  cat > "$real_foreign_ruleset" <<EOF
{"nftables":[{"chain":{"family":"${foreign_family}","table":"foreign_${foreign_family}","name":"input","type":"filter","hook":"input","prio":0,"policy":"drop"}}]}
EOF
  if run_real_foreign_parser "$real_foreign_ruleset" >/dev/null 2>&1; then
    fail "real Python parser accepted foreign ${foreign_family} input chain"
  fi
done
ok "real isolated Python rejects inet/ip/ip6 foreign input base chains"

for foreign_policy in drop accept; do
  cat > "$FAKE_NFT_RULESET_FILE" <<EOF
{"nftables":[{"chain":{"family":"inet","table":"foreign_filter","name":"input","type":"filter","hook":"input","prio":0,"policy":"${foreign_policy}"}}]}
EOF
  : > "$FAKE_NFT_LOG"
  rm -f -- "$FAKE_NFT_CHECK_COUNT"
  if run_fake_apply >/dev/null 2>&1; then
    fail "foreign ${foreign_policy} input base chain passed"
  fi
  [[ "$(grep -c '^-j list ruleset' "$FAKE_NFT_LOG" || true)" -eq 1 ]] \
    || fail "foreign input chain was not inspected exactly once"
  assert_no_nft_check_or_apply "foreign input chain reached nft check/apply"
  rm -f -- "$FAKE_NFT_RULESET_FILE"
done
ok "managed mode rejects every foreign input base chain before check/apply"

printf '#!/usr/sbin/nft -f\nflush ruleset\n' > "$MAIN_CONFIG"
rm -f -- "$POLICY_FILE"
cp "$MAIN_CONFIG" "${WORK}/main.before-first-check-failure"
reset_firewall_mocks
FAKE_NFT_FAIL_CHECK_AT=1
if run_fake_apply >/dev/null 2>&1; then
  fail "first nft batch precheck failure passed"
fi
cmp -s "$MAIN_CONFIG" "${WORK}/main.before-first-check-failure" \
  || fail "first precheck failure changed main config"
[[ ! -e "$POLICY_FILE" ]] \
  || fail "first precheck failure installed a policy"
[[ "$(count_nft_checks)" -eq 1 && "$(count_nft_formal)" -eq 0 ]] \
  || fail "first precheck failure entered an invalid apply sequence"
[[ ! -s "$FAKE_SYSTEMCTL_LOG" ]] \
  || fail "first precheck failure enabled nftables"
ok "failed generated-batch precheck never mutates persistence or applies live"

printf '#!/usr/sbin/nft -f\nflush ruleset\n' > "$MAIN_CONFIG"
rm -f -- "$POLICY_FILE"
cp "$MAIN_CONFIG" "${WORK}/main.before-composite-failure"
reset_firewall_mocks
FAKE_NFT_FAIL_CHECK_AT=2
if run_fake_apply >/dev/null 2>&1; then
  fail "boot-composite nft precheck failure passed"
fi
cmp -s "$MAIN_CONFIG" "${WORK}/main.before-composite-failure" \
  || fail "boot-composite failure did not restore main before-image"
[[ ! -e "$POLICY_FILE" ]] \
  || fail "boot-composite failure left a new policy"
[[ "$(count_nft_checks)" -eq 2 && "$(count_nft_formal)" -eq 0 ]] \
  || fail "boot-composite failure entered formal apply"
[[ ! -s "$FAKE_SYSTEMCTL_LOG" ]] \
  || fail "boot-composite failure enabled nftables"
if find "$RUNTIME_ROOT" -name '*.candidate.*' -print -quit | grep -q .; then
  fail "boot-composite failure left a candidate file"
fi
ok "syntax-bad final boot composite rolls back with no apply, enable, or candidate trace"

printf '#!/usr/sbin/nft -f\nflush ruleset\n' > "$MAIN_CONFIG"
rm -f -- "$POLICY_FILE"
reset_firewall_mocks
run_fake_apply >/dev/null || fail "successful persistent firewall apply failed"
assert_two_checks_one_apply "successful persistent firewall apply"
grep -Fxq 'add table inet vps_toolkit_proxy_stack' "$FAKE_NFT_FORMAL_BATCH" \
  || fail "formal batch omitted idempotent table declaration"
grep -Fxq 'delete table inet vps_toolkit_proxy_stack' "$FAKE_NFT_FORMAL_BATCH" \
  || fail "formal batch omitted table delete"
grep -Fq 'table inet vps_toolkit_proxy_stack {' "$FAKE_NFT_FORMAL_BATCH" \
  || fail "formal batch omitted complete table definition"
cmp -s "$FAKE_NFT_FORMAL_BATCH" "$POLICY_FILE" \
  || fail "persisted policy differs from the checked/formal complete batch"
cmp -s "${FAKE_NFT_CHECK_PREFIX}.1" "$FAKE_NFT_FORMAL_BATCH" \
  || fail "first nft check did not cover the formal batch"
cmp -s "${FAKE_NFT_CHECK_PREFIX}.2" "$MAIN_CONFIG" \
  || fail "second nft check did not cover the final boot composite"
[[ "$(grep -Fc "include \"${POLICY_FILE}\"" "$MAIN_CONFIG")" -eq 1 ]] \
  || fail "main config did not include the managed policy exactly once"
grep -Fxq 'enable nftables' "$FAKE_SYSTEMCTL_LOG" \
  || fail "successful persistence did not enable nftables"
ok "complete batch, final boot composite, and one formal apply occur in order"

reset_firewall_mocks
run_fake_apply >/dev/null || fail "repeated persistent firewall apply failed"
assert_two_checks_one_apply "repeated persistent firewall apply"
[[ "$(grep -Fc "include \"${POLICY_FILE}\"" "$MAIN_CONFIG")" -eq 1 ]] \
  || fail "repeated persistence duplicated the include"
ok "persistent orchestration remains idempotent"

printf '#!/usr/sbin/nft -f\nflush ruleset\n' > "$MAIN_CONFIG"
rm -f -- "$POLICY_FILE"
cp "$MAIN_CONFIG" "${WORK}/main.before-mv-failure"
reset_firewall_mocks
FAKE_MV_FAIL_AT=2
if run_fake_apply >/dev/null 2>&1; then
  fail "persistence atomic rename failure passed"
fi
cmp -s "$MAIN_CONFIG" "${WORK}/main.before-mv-failure" \
  || fail "rename failure changed main before-image"
[[ ! -e "$POLICY_FILE" ]] \
  || fail "rename failure left a new policy"
[[ "$(count_nft_checks)" -eq 1 && "$(count_nft_formal)" -eq 0 ]] \
  || fail "rename failure reached composite/formal apply"
[[ ! -s "$FAKE_SYSTEMCTL_LOG" ]] \
  || fail "rename failure enabled nftables"
ok "persistence rename fault restores before-images before live apply"

printf '#!/usr/sbin/nft -f\nflush ruleset\n' > "$MAIN_CONFIG"
rm -f -- "$POLICY_FILE"
cp "$MAIN_CONFIG" "${WORK}/main.before-exit-guard"
reset_firewall_mocks
if run_fake_interrupted_prepare >/dev/null 2>&1; then
  fail "interrupted persistence-to-live interval returned success"
fi
cmp -s "$MAIN_CONFIG" "${WORK}/main.before-exit-guard" \
  || fail "EXIT guard did not restore main before-image"
[[ ! -e "$POLICY_FILE" ]] \
  || fail "EXIT guard did not restore absent policy"
[[ "$(count_nft_checks)" -eq 2 && "$(count_nft_formal)" -eq 0 ]] \
  || fail "interrupted prepare entered formal apply"
ok "EXIT guard restores before-images after candidate commit but before live apply"

printf '#!/usr/sbin/nft -f\nflush ruleset\n' > "$MAIN_CONFIG"
rm -f -- "$POLICY_FILE"
cp "$MAIN_CONFIG" "${WORK}/main.before-formal-failure"
reset_firewall_mocks
FAKE_NFT_FAIL_FORMAL=1
if run_fake_apply >/dev/null 2>&1; then
  fail "formal nft apply failure passed"
fi
cmp -s "$MAIN_CONFIG" "${WORK}/main.before-formal-failure" \
  || fail "formal failure did not restore absent-include main before-image"
[[ ! -e "$POLICY_FILE" ]] \
  || fail "formal failure did not remove newly installed policy"
[[ "$(count_nft_checks)" -eq 2 && "$(count_nft_formal)" -eq 1 ]] \
  || fail "formal failure had an invalid nft operation count"
[[ ! -s "$FAKE_SYSTEMCTL_LOG" ]] \
  || fail "formal failure enabled nftables"
ok "formal apply failure restores absent persistence before-images"

printf '#!/usr/sbin/nft -f\nflush ruleset\n' > "$MAIN_CONFIG"
rm -f -- "$POLICY_FILE"
reset_firewall_mocks
FAKE_NFT_FAIL_FORMAL=1
rollback_failure_output="$(run_fake_rollback_failure 2>&1)" && \
  fail "formal apply plus rollback failure returned success"
[[ "$rollback_failure_output" == *"before-image 恢复失败"* ]] \
  || fail "rollback failure was not surfaced distinctly"
[[ "$(count_nft_checks)" -eq 2 && "$(count_nft_formal)" -eq 1 ]] \
  || fail "rollback-failure branch had invalid nft operation count"
[[ ! -s "$FAKE_SYSTEMCTL_LOG" ]] \
  || fail "rollback-failure branch enabled nftables"
ok "formal apply reports a distinct fatal error when rollback itself fails"

printf 'OLD_POLICY\n' > "$POLICY_FILE"
printf '#!/usr/sbin/nft -f\nflush ruleset\ninclude "%s"\n' \
  "$POLICY_FILE" > "$MAIN_CONFIG"
cp "$MAIN_CONFIG" "${WORK}/main.before-existing-formal-failure"
cp "$POLICY_FILE" "${WORK}/policy.before-existing-formal-failure"
reset_firewall_mocks
FAKE_NFT_FAIL_FORMAL=1
if run_fake_apply >/dev/null 2>&1; then
  fail "formal failure with existing before-images passed"
fi
cmp -s "$MAIN_CONFIG" "${WORK}/main.before-existing-formal-failure" \
  || fail "formal failure did not restore existing main"
cmp -s "$POLICY_FILE" "${WORK}/policy.before-existing-formal-failure" \
  || fail "formal failure did not restore existing policy"
[[ "$(count_nft_checks)" -eq 2 && "$(count_nft_formal)" -eq 1 ]] \
  || fail "existing-before-image failure had invalid nft counts"
ok "formal apply failure restores existing main/policy before-images"

bash -n "$SCRIPT"
bash -n "$0"
expected_version="$(sed -n 's/^SCRIPT_VERSION="\([^"]*\)"/\1/p' "$SCRIPT")"
[[ -n "$expected_version" ]] || fail "core script version variable is missing"
bash "$SCRIPT" --version | grep -Fq "$expected_version"
ok "core/test syntax and dynamic version output pass"
