#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
EXPORTER="${REPO_ROOT}/scripts/vps/3x-ui/3x-ui-node-exporter.sh"
TMP_BASE="${REPO_ROOT}/.tmp"
TEST_ROOT=""

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

ok() {
  printf '[OK] %s\n' "$1"
}

cleanup() {
  [[ -n "${TEST_ROOT}" ]] || return 0
  case "${TEST_ROOT}" in
    "${TMP_BASE}"/3xui-self-destruct-test.*)
      rm -rf -- "${TEST_ROOT}"
      ;;
    *)
      printf '[WARN] refused unsafe test cleanup path: %s\n' "${TEST_ROOT}" >&2
      ;;
  esac
}

mkdir -p "${TMP_BASE}"
TEST_ROOT="$(mktemp -d "${TMP_BASE}/3xui-self-destruct-test.XXXXXXXX")"
trap cleanup EXIT

if ! command -v python3 >/dev/null 2>&1; then
  [[ -n "${PYTHON_BIN:-}" && -x "${PYTHON_BIN}" ]] || {
    fail "python3 is required (or set PYTHON_BIN to a Python 3 executable)"
  }
  python3() {
    "${PYTHON_BIN}" "$@"
  }
fi

XUI_EXPORTER_SOURCE_ONLY="1"
# shellcheck source=/dev/null
. "${EXPORTER}"
setup_colors

[[ "${SCRIPT_VERSION}" == "1.1.0" ]] || fail "unexpected exporter version"
[[ "$(bash "${EXPORTER}" --version)" == "1.1.0" ]] || fail "--version output mismatch"
help_output="$(bash "${EXPORTER}" --help)"
grep -Fq -- "--self-destruct" <<<"${help_output}" || fail "--help is missing self-destruct mode"
grep -Fq -- "--version" <<<"${help_output}" || fail "--help is missing --version"
if bash "${EXPORTER}" --self-destruct --yes >"${TEST_ROOT}/conflict.log" 2>&1; then
  fail "--self-destruct --yes must be rejected"
fi
if bash "${EXPORTER}" --self-destruct --out "${TEST_ROOT}/unsafe" >>"${TEST_ROOT}/conflict.log" 2>&1; then
  fail "--self-destruct --out must be rejected"
fi
if bash "${EXPORTER}" --self-destruct --show-links >>"${TEST_ROOT}/conflict.log" 2>&1; then
  fail "--self-destruct --show-links must be rejected"
fi
ok "version and CLI conflict validation"

DB_OVERRIDE="${TEST_ROOT}/x-ui.db"
python3 - "${DB_OVERRIDE}" <<'PY'
import json
import sqlite3
import sys

db = sqlite3.connect(sys.argv[1])
db.execute("CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)")
db.executemany(
    "INSERT INTO settings(key, value) VALUES (?, ?)",
    [
        ("subPort", "2096"),
        ("subPath", "/sub/"),
        ("subDomain", "nodes.example.test"),
    ],
)
db.execute("CREATE TABLE inbounds (id INTEGER PRIMARY KEY, settings TEXT, stream_settings TEXT)")
db.execute(
    "INSERT INTO inbounds(id, settings, stream_settings) VALUES (?, ?, ?)",
    (
        1,
        json.dumps({"clients": [{"id": "uuid-test", "subId": "sub-test"}]}),
        json.dumps({"network": "tcp"}),
    ),
)
db.commit()
db.close()
PY

normal_out="${TEST_ROOT}/normal-export"
run_export "1" "0" "${normal_out}" "0" >"${TEST_ROOT}/normal.log"
for name in x-ui.snapshot.db raw_inbounds.json subids.txt env.sh links.raw links.txt curl-errors.log; do
  [[ -f "${normal_out}/${name}" ]] || fail "normal export is missing ${name}"
done
grep -Fxq "sub-test" "${normal_out}/subids.txt" || fail "normal export subId mismatch"
ok "normal raw-only export remains functional"

mkdir -p "${TEST_ROOT}/sessions"
TMPDIR="${TEST_ROOT}/sessions"
export TMPDIR
prepare_self_destruct_session
session="${SELF_DESTRUCT_SESSION_DIR}"
data_dir="${session}/data"
archive="${session}/3xui-node-export-test.zip"
run_export "1" "0" "${data_dir}" "0" >"${TEST_ROOT}/self-destruct.log"
create_self_destruct_archive "${data_dir}" "${archive}"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    ok "POSIX permission assertions deferred to Linux (Windows ACL-backed filesystem)"
    ;;
  *)
    [[ "$(stat -c '%a' "${session}")" == "700" ]] || fail "session directory mode is not 700"
    [[ "$(stat -c '%a' "${archive}")" == "600" ]] || fail "archive mode is not 600"
    ;;
esac

metadata="$(read_archive_metadata "${archive}")"
archive_size="${metadata%%$'\n'*}"
archive_sha256="${metadata#*$'\n'}"
python3 - "${archive}" "${archive_size}" "${archive_sha256}" <<'PY'
import hashlib
import json
import sqlite3
import sys
import tempfile
import zipfile
from pathlib import Path

archive = Path(sys.argv[1])
expected_size = int(sys.argv[2])
expected_sha256 = sys.argv[3]
expected_files = {
    "curl-errors.log",
    "env.sh",
    "links.raw",
    "links.txt",
    "raw_inbounds.json",
    "subids.txt",
    "x-ui.snapshot.db",
}

assert archive.stat().st_size == expected_size
assert hashlib.sha256(archive.read_bytes()).hexdigest() == expected_sha256
with zipfile.ZipFile(archive) as bundle:
    assert set(bundle.namelist()) == expected_files
    assert bundle.read("subids.txt").decode().strip() == "sub-test"
    raw = json.loads(bundle.read("raw_inbounds.json"))
    assert raw[0]["settings_parsed"]["clients"][0]["id"] == "uuid-test"
    with tempfile.TemporaryDirectory() as tmp:
        bundle.extract("x-ui.snapshot.db", tmp)
        con = sqlite3.connect(str(Path(tmp) / "x-ui.snapshot.db"))
        assert con.execute("SELECT COUNT(*) FROM inbounds").fetchone()[0] == 1
        con.close()
PY
ok "ZIP contents, SQLite snapshot, size, SHA-256, and permissions"

remove_self_destruct_staging
[[ ! -e "${data_dir}" ]] || fail "unpacked staging directory was not removed"
[[ -f "${archive}" ]] || fail "archive did not remain during the download window"
[[ "$(find "${session}" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" == "1" ]] || {
  fail "download window must retain only the ZIP"
}
finalize_self_destruct_cleanup
[[ ! -e "${session}" ]] || fail "confirmed cleanup left the session directory"
cleanup_self_destruct_session
ok "staging removal and idempotent confirmed cleanup"

prepare_self_destruct_session
empty_session="${SELF_DESTRUCT_SESSION_DIR}"
if create_self_destruct_archive "${empty_session}/data" "${empty_session}/empty.zip" \
  >"${TEST_ROOT}/empty-archive.log" 2>&1; then
  fail "empty staging directory unexpectedly produced an archive"
fi
finalize_self_destruct_cleanup
[[ ! -e "${empty_session}" ]] || fail "ZIP failure path left a session directory"
ok "ZIP creation failure cleanup"

prepare_self_destruct_session
failed_session="${SELF_DESTRUCT_SESSION_DIR}"
saved_db_override="${DB_OVERRIDE}"
DB_OVERRIDE="${TEST_ROOT}/missing.db"
if run_export "1" "0" "${failed_session}/data" "0" >"${TEST_ROOT}/db-failure.log" 2>&1; then
  fail "missing database unexpectedly exported"
fi
DB_OVERRIDE="${saved_db_override}"
finalize_self_destruct_cleanup
[[ ! -e "${failed_session}" ]] || fail "database failure path left a session directory"
ok "database failure cleanup"

signal_root="${TEST_ROOT}/signal-sessions"
mkdir -p "${signal_root}"
for signal_code in 129 143; do
  set +e
  XUI_EXPORTER_SOURCE_ONLY=1 TMPDIR="${signal_root}" bash -c '
    set -uo pipefail
    . "$1"
    setup_colors
    prepare_self_destruct_session
    : > "${SELF_DESTRUCT_SESSION_DIR}/signal-test"
    handle_self_destruct_signal "$2"
  ' _ "${EXPORTER}" "${signal_code}" >"${TEST_ROOT}/signal-${signal_code}.log" 2>&1
  status=$?
  set -e
  [[ "${status}" -eq "${signal_code}" ]] || fail "signal handler returned ${status}, expected ${signal_code}"
  if find "${signal_root}" -mindepth 1 -maxdepth 1 | grep -q .; then
    fail "signal cleanup left a session directory"
  fi
done
ok "HUP and TERM cleanup handlers"

confirmed_input="${TEST_ROOT}/confirmed-input"
printf '\n' >"${confirmed_input}"
has_tty() { return 0; }
self_destruct_input_path() { printf '%s\n' "${confirmed_input}"; }
SELF_DESTRUCT_TIMEOUT_SECONDS="5"
wait_for_self_destruct_download >"${TEST_ROOT}/confirmed-wait.log" 2>&1
grep -Fq "已收到清理确认" "${TEST_ROOT}/confirmed-wait.log" || fail "Enter confirmation was not detected"

timeout_fifo="${TEST_ROOT}/timeout-input"
mkfifo "${timeout_fifo}"
self_destruct_input_path() { printf '%s\n' "${timeout_fifo}"; }
SELF_DESTRUCT_TIMEOUT_SECONDS="1"
{ sleep 3; } >"${timeout_fifo}" &
fifo_writer=$!
started="$(date +%s)"
wait_for_self_destruct_download >"${TEST_ROOT}/timeout-wait.log" 2>&1
elapsed=$(( $(date +%s) - started ))
wait "${fifo_writer}"
((elapsed >= 1 && elapsed < 3)) || fail "download wait did not time out near one second"
grep -Fq "等待时间已到" "${TEST_ROOT}/timeout-wait.log" || fail "timeout message missing"
ok "Enter confirmation and timeout behavior"

# Reload the original helpers, then replace only the terminal wait and script-file prompt.
. "${EXPORTER}"
setup_colors
DB_OVERRIDE="${TEST_ROOT}/x-ui.db"
TMPDIR="${TEST_ROOT}/sessions"
SELF_DESTRUCT_TIMEOUT_SECONDS="900"
has_tty() { return 0; }
wait_for_self_destruct_download() {
  [[ -f "${SELF_DESTRUCT_ARCHIVE}" ]] || fail "integrated download window has no ZIP"
  [[ ! -e "${SELF_DESTRUCT_SESSION_DIR}/data" ]] || fail "integrated download window retained staging files"
}
maybe_delete_script_source() { :; }
run_self_destruct_export "1" >"${TEST_ROOT}/integrated.log"
if find "${TMPDIR}" -mindepth 1 -maxdepth 1 | grep -q .; then
  fail "integrated self-destruct run left a session directory"
fi
grep -Fq "本次临时导出目录、ZIP、数据库快照和中间文件已清理" \
  "${TEST_ROOT}/integrated.log" || fail "integrated cleanup summary missing"
ok "integrated self-destruct export and cleanup"

. "${EXPORTER}"
setup_colors
source_keep="${TEST_ROOT}/keep-script.sh"
source_delete="${TEST_ROOT}/delete-script.sh"
printf '#!/usr/bin/env bash\n' >"${source_keep}"
printf '#!/usr/bin/env bash\n' >"${source_delete}"
script_source_path() { printf '%s\n' "${source_keep}"; }
read_tty() { printf '\n'; }
maybe_delete_script_source >"${TEST_ROOT}/keep-script.log"
[[ -f "${source_keep}" ]] || fail "script was deleted without confirmation"
script_source_path() { printf '%s\n' "${source_delete}"; }
read_tty() { printf '%s\n' "DELETE"; }
maybe_delete_script_source >"${TEST_ROOT}/delete-script.log"
[[ ! -e "${source_delete}" ]] || fail "confirmed script deletion did not remove the file"
[[ "${SCRIPT_SOURCE_DELETED}" == "1" ]] || fail "confirmed script deletion did not request menu exit"
script_source_path() { printf '%s\n' "/dev/fd/63"; }
maybe_delete_script_source >"${TEST_ROOT}/pipe-script.log"
grep -Fq "没有脚本文件需要删除" "${TEST_ROOT}/pipe-script.log" || fail "pipe launch was not recognized"
ok "script file keep, delete, and pipe-launch behavior"

menu_output="$(
  XUI_EXPORTER_SOURCE_ONLY=1 MENU_CLEAR=0 bash -c '
    . "$1"
    ensure_root() { :; }
    ensure_dependencies() { :; }
    read_tty() { printf "0\n"; }
    main
  ' _ "${EXPORTER}"
)"
grep -Fq "临时导出并自动清理" <<<"${menu_output}" || fail "self-destruct menu item missing"
grep -Fq 'read_tty "请选择操作 [0-6]: "' "${EXPORTER}" || fail "menu range is not 0-6"
ok "menu numbering and exit path"

cleanup
TEST_ROOT=""
trap - EXIT
printf '3x-ui self-destruct tests passed.\n'
