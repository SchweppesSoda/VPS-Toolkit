#!/usr/bin/env python3
"""Exercise real install/apply helpers with synthetic config and OS command stubs."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer.sh"
BASH = os.environ.get("BASH_BIN") or shutil.which("bash")

DRIVER = r'''
export PATH="/usr/bin:/bin:$PATH"
APP_ROOT="$TEST_ROOT/app"
BIN_DIR="$APP_ROOT/bin"
LOG_DIR="$APP_ROOT/logs"
BACKUP_DIR="$APP_ROOT/backups"
FEATURE_DIR="$APP_ROOT/feature"
ENV_FILE="$FEATURE_DIR/service.env"
CONFIG_FILE="$FEATURE_DIR/config.json"
SHARE_FILE="$FEATURE_DIR/share.txt"
PID_FILE="$FEATURE_DIR/xray.pid"
XRAY_BIN="$TEST_ROOT/xray"
SERVICE_FILE="$TEST_ROOT/sidecar.service"
EVENTS="$TEST_ROOT/events"
: > "$EVENTS"
RUNNING="$TEST_ROOT/running"
ENABLED="$TEST_ROOT/enabled"
CRON="$TEST_ROOT/crontab"
LOADED="$TEST_ROOT/loaded.json"
BASELINE="$TEST_ROOT/baseline.json"
LIVE_CONFIG="$CONFIG_FILE"
LIVE_ENV="$ENV_FILE"
export EVENTS BASELINE LIVE_CONFIG LIVE_ENV
ensure_dirs
printf '%s\n' "$TEST_RUNNING" > "$RUNNING"
printf '%s\n' "$TEST_ENABLED" > "$ENABLED"
event() { printf '%s\n' "$*" >> "$EVENTS"; }
candidate() { ! cmp -s "$CONFIG_FILE" "$BASELINE"; }
fake_running() { [[ "$(cat "$RUNNING")" == 1 ]]; }
launch() {
  event "launch $1"
  printf '0\n' > "$RUNNING"
  if candidate; then
    case "$TEST_FAILURE" in
      apply|restore) return 1 ;;
      exited) return 0 ;;
    esac
  elif [[ "$TEST_FAILURE" == restore ]]; then
    return 1
  fi
  cp "$CONFIG_FILE" "$LOADED" || return 1
  printf '1\n' > "$RUNNING"
}
systemctl() {
  event "systemctl $*"
  case "$1" in
    is-active) fake_running ;;
    is-enabled)
      cat "$ENABLED"
      [[ "$(cat "$ENABLED")" == enabled* ]]
      ;;
    daemon-reload)
      if [[ "$TEST_FAILURE" == daemon && ! -f "$TEST_ROOT/failed-once" ]]; then
        touch "$TEST_ROOT/failed-once"; return 1
      fi
      ;;
    enable)
      if [[ "${2:-}" == --runtime ]]; then
        printf 'enabled-runtime\n' > "$ENABLED"
      else
        printf 'enabled\n' > "$ENABLED"
      fi
      if [[ "$TEST_FAILURE" == enable && ! -f "$TEST_ROOT/failed-once" ]]; then
        touch "$TEST_ROOT/failed-once"; return 1
      fi
      if [[ "${2:-}" == --now ]] && ! fake_running; then launch start; fi
      ;;
    disable) printf 'disabled\n' > "$ENABLED" ;;
    restart) launch restart ;;
    start) launch start ;;
    stop) [[ "$TEST_FAILURE" != stop ]] || return 1; printf '0\n' > "$RUNNING" ;;
    *) echo "unexpected systemctl operation" >&2; return 99 ;;
  esac
}
crontab() {
  event "crontab $*"
  case "${1:-}" in
    -l)
      if [[ "$TEST_FAILURE" == cron_read ]]; then
        echo 'cannot read crontab' >&2; return 1
      elif [[ -f "$CRON" ]]; then
        cat "$CRON"
      else
        echo 'no crontab for fixture' >&2; return 1
      fi
      ;;
    -r)
      if [[ -f "$CRON" ]]; then rm -f "$CRON"
      else echo 'no crontab for fixture' >&2; return 1; fi
      ;;
    *)
      if [[ "$TEST_FAILURE" == cron_write && ! -f "$TEST_ROOT/failed-once" ]]; then
        touch "$TEST_ROOT/failed-once"; return 1
      fi
      cp "$1" "$CRON"
      ;;
  esac
}
# These replace only OS process primitives. Real start/stop/process_running and
# cron helpers still run; no host process or service is inspected or changed.
nohup() { launch nohup; }
kill() {
  if [[ "${1:-}" == -0 ]]; then fake_running
  else
    event "kill $*"
    [[ "$TEST_FAILURE" == stuck ]] || printf '0\n' > "$RUNNING"
  fi
}
pgrep() {
  if fake_running && [[ "$TEST_FAILURE" != reused_pid ]]; then
    if [[ -f "$PID_FILE" ]]; then cat "$PID_FILE"; else printf '12345\n'; fi
  else return 1; fi
}
ps() {
  fake_running || return 1
  if [[ "$TEST_FAILURE" == reused_pid ]]; then printf 'unrelated-worker --serve\n'
  elif [[ "$TEST_FAILURE" == unknown_pid ]]; then return 1
  else printf '%s run -config %s\n' "$XRAY_BIN" "$CONFIG_FILE"; fi
}
pkill() {
  event pkill
  [[ "$TEST_FAILURE" == stuck ]] || printf '0\n' > "$RUNNING"
}
sleep() { command sleep 0.05; }
detect_init_system() { HAS_SYSTEMD="$TEST_SYSTEMD"; }
probe_time_sync() { TIME_SYNC_DETAIL="synthetic NTP"; [[ "$TEST_FAILURE" != clock ]]; }
detect_argosbx() { ARGOSBX_DETECTED=0; return 1; }
copy_xray_binary() { XRAY_SOURCE=synthetic; }
verify_xray_binary() { return 0; }
generate_uuid() { UUID=00000000-0000-4000-8000-000000000001; }
generate_vlessenc() { DECRYPTION=synthetic.decryption; ENCRYPTION=synthetic.encryption; }
generate_ss_password() { printf 'synthetic-password\n'; }
read_prompt() { printf '\n'; }
prompt_with_default() { printf 'renamed-node\n'; }
confirm_yes() { [[ "$TEST_REKEY" == 1 ]]; }
choose_free_port() { printf '19001\n'; }
prompt_port() {
  if [[ "$TEST_FAILURE" == invalid ]]; then printf 'invalid-json\n'
  elif [[ "$3" == "$VLESS_NAME" ]]; then printf '%s\n' "$TEST_VLESS_PORT"
  else printf '%s\n' "$TEST_SS_PORT"; fi
}
prompt_flow_mode() { printf '%s\n' "$TEST_FLOW"; }
prompt_ss_method() { printf '2022-blake3-aes-128-gcm\n'; }
prompt_ss_public_entry() { SS_PUBLIC_HOST=203.0.113.10; SS_PUBLIC_PORT=""; SS_ALLOW_SOURCE=""; }
detect_public_ip() { printf '203.0.113.10'; }
curl() { echo 'unexpected network operation' >&2; return 99; }
wget() { echo 'unexpected network operation' >&2; return 99; }
command_exists() { [[ "$1" != python3 ]] && command -v "$1" >/dev/null 2>&1; }
show_links() { event show_links; }

load_state
case "$TEST_EXISTING" in
  vless|both)
    PORT=19001; generate_uuid; generate_vlessenc; NODE_NAME=synthetic-vless
    ;;
esac
case "$TEST_EXISTING" in
  ss|both)
    SS_ENABLED=1; SS_PORT=19002; SS_PASSWORD=synthetic-old-password; SS_NODE_NAME=synthetic-ss
    ;;
esac
if [[ "$TEST_EXISTING" != none ]]; then
  write_state && write_config || exit 98
  printf 'synthetic old share\n' > "$SHARE_FILE"
  cp "$CONFIG_FILE" "$BASELINE"
  cp "$CONFIG_FILE" "$LOADED"
  cp "$ENV_FILE" "$TEST_ROOT/baseline.env"
  if [[ "$TEST_SYSTEMD" == 1 ]]; then
    printf 'synthetic old unit\n' > "$SERVICE_FILE"
  else
    printf '12345\n' > "$PID_FILE"
  fi
fi
if [[ "$TEST_CRON" == 1 ]]; then
  printf '0 0 * * * unrelated-job\n' > "$CRON"
  if [[ "$TEST_EXISTING" != none ]]; then
    printf '@reboot old-start %s\n' "$CONFIG_FILE" >> "$CRON"
  fi
  cp "$CRON" "$TEST_ROOT/baseline.cron"
fi
# Inject write/rename failures at filesystem boundaries, not in apply helpers.
mktemp() {
  local path
  path="$(command mktemp "$@")" || return 1
  if [[ "$path" == *'/.config-apply.'* ]]; then
    case "$TEST_FAILURE" in
      state_write) mkdir "$path/service.env.next" ;;
      config_write) mkdir "$path/config.json.next" ;;
      share_write) mkdir "$path/share.txt.next" ;;
    esac
  fi
  printf '%s\n' "$path"
}
mv() {
  if [[ "$TEST_FAILURE" == rename && "$1" == */config.json.next ]]; then return 1; fi
  if [[ "$TEST_FAILURE" == share_rename && "$1" == */share.txt.next ]]; then return 1; fi
  command mv "$@"
}
cp() {
  if [[ "$TEST_FAILURE" == snapshot && "${*: -1}" == *.before ]]; then return 1; fi
  command cp "$@"
}
detect_init_system
case "$TEST_ACTION" in
  vless) install_or_repair_vless ;;
  ss) install_or_repair_ss ;;
  start) start_service ;;
  core) ensure_xray_core ;;
  ss_port) change_ss_port ;;
  vless_port) change_port ;;
  flow) change_flow_mode ;;
  ss_key) regenerate_ss_password ;;
  uuid) regenerate_uuid ;;
  enc) regenerate_enc ;;
  ss_name) change_ss_node_name ;;
  vless_name) change_node_name ;;
  entry) change_ss_public_entry ;;
  disable) disable_ss ;;
  rewrite) rewrite_and_restart ;;
  stop) stop_service ;;
  show) show_links ;;
  check) test_config ;;

esac
'''

XRAY_STUB = r'''#!/usr/bin/env bash
set -u
printf 'validate %s\n' "$*" >> "$EVENTS"
[[ "$1 $2 $3 $4 $5" == 'run -test -format json -config' ]] || exit 96
config="${*: -1}"
if [[ -f "$BASELINE" ]]; then
  cmp -s "$BASELINE" "$LIVE_CONFIG" && cmp -s "$TEST_ROOT/baseline.env" "$LIVE_ENV" || exit 97
else
  [[ ! -e "$LIVE_CONFIG" && ! -e "$LIVE_ENV" ]] || exit 97
fi
# Parsing is real; no real Xray binary or network call is involved.
"$TEST_PYTHON" -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$config" || {
  echo 'synthetic-sensitive-diagnostic' >&2
  exit 1
}
'''


class ConfigApply(unittest.TestCase):
    def setUp(self):
        if not BASH:
            self.fail("Bash is required (set BASH_BIN on Windows)")
        scratch = ROOT / ".tmp"
        scratch.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="sidecar-apply-", dir=scratch)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.assertEqual(self.root.resolve().parent, scratch.resolve())
        self.feature = self.root / "app/feature"
        self.config = self.feature / "config.json"
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertTrue(source.rstrip().endswith('main "$@"'))
        self.driver = self.root / "driver.sh"
        self.driver.write_text(source.rstrip().rsplit('main "$@"', 1)[0] + DRIVER,
                               encoding="utf-8", newline="\n")
        xray = self.root / "xray"
        xray.write_text(XRAY_STUB, encoding="utf-8", newline="\n")
        xray.chmod(0o700)

    def run_case(self, *, systemd=True, existing="vless", action="ss", running=True,
                 enabled="enabled", failure="", cron=True, rekey=False,
                 vless_port=19001, ss_port=19002, flow="none"):
        env = dict(os.environ, TEST_ROOT=self.root.as_posix(), TEST_SYSTEMD=str(int(systemd)),
                   TEST_EXISTING=existing, TEST_ACTION=action, TEST_RUNNING=str(int(running)),
                   TEST_ENABLED=enabled, TEST_FAILURE=failure, TEST_CRON=str(int(cron)),
                   TEST_REKEY=str(int(rekey)), TEST_FLOW=flow,
                   TEST_VLESS_PORT=str(vless_port), TEST_SS_PORT=str(ss_port),
                   TEST_PYTHON=Path(sys.executable).as_posix())
        env.pop("BASH_ENV", None)
        self.result = subprocess.run([BASH, self.driver.as_posix()], env=env,
                                     capture_output=True, text=True, encoding="utf-8", timeout=30)
        self.events = (self.root / "events").read_text(encoding="utf-8").splitlines()
        return self.result

    def assert_applied(self, protocols):
        self.assertEqual(self.result.returncode, 0, self.result.stdout + self.result.stderr)
        self.assertEqual(json.loads(self.config.read_text()),
                         json.loads((self.root / "loaded.json").read_text()))
        self.assertEqual([row["protocol"] for row in json.loads(self.config.read_text())["inbounds"]],
                         protocols)
        self.assertEqual((self.root / "running").read_text().strip(), "1")
        self.assertIn("show_links", self.events)
        self.assertIn("安装 / 修复完成", self.result.stdout)
        validate = next(i for i, event in enumerate(self.events) if event.startswith("validate "))
        launch = next(i for i, event in enumerate(self.events) if event.startswith("launch "))
        self.assertLess(validate, launch)
        if os.name != "nt":
            self.assertEqual(self.config.stat().st_mode & 0o777, 0o600)
            for directory in self.feature.glob(".config-apply.*"):
                self.assertEqual(directory.stat().st_mode & 0o777, 0o700)

    def assert_failed(self, *, existing=True, running=True, enabled="enabled", cron=None,
                      restored=True):
        output = self.result.stdout + self.result.stderr
        self.assertNotEqual(self.result.returncode, 0, output)
        self.assertNotIn("安装 / 修复完成", output)
        self.assertNotIn("配置已应用", output)
        self.assertNotIn("show_links", self.events)
        self.assertNotIn("synthetic-sensitive-diagnostic", output)
        if existing:
            self.assertEqual(self.config.read_bytes(), (self.root / "baseline.json").read_bytes())
            self.assertEqual((self.feature / "service.env").read_bytes(),
                             (self.root / "baseline.env").read_bytes())
            self.assertEqual((self.feature / "share.txt").read_text(), "synthetic old share\n")
        else:
            for path in (self.config, self.feature / "service.env", self.feature / "share.txt",
                         self.root / "sidecar.service"):
                self.assertFalse(path.exists(), path)
        if restored:
            self.assertEqual((self.root / "running").read_text().strip(), str(int(running)))
            self.assertEqual((self.root / "enabled").read_text().strip(), enabled)
            if existing and running:
                self.assertEqual((self.root / "loaded.json").read_bytes(),
                                 (self.root / "baseline.json").read_bytes())
        if cron is not None:
            self.assertEqual((self.root / "crontab").exists(), cron)
            if cron:
                self.assertEqual((self.root / "crontab").read_bytes(),
                                 (self.root / "baseline.cron").read_bytes())

    def test_first_vless_install_enables_and_starts_systemd(self):
        self.run_case(existing="none", action="vless", running=False, enabled="disabled")
        self.assert_applied(["vless"])
        self.assertEqual((self.root / "enabled").read_text().strip(), "enabled")
        self.assertIn("systemctl enable agsbx-extra-vless-raw-enc", self.events)

    def test_first_ss_install_enables_and_starts_systemd(self):
        self.run_case(existing="none", running=False, enabled="disabled")
        self.assert_applied(["shadowsocks"])

    def test_running_systemd_adds_ss_and_reloads(self):
        self.run_case()
        self.assert_applied(["vless", "shadowsocks"])
        self.assertIn("systemctl restart agsbx-extra-vless-raw-enc", self.events)

    def test_running_systemd_adds_vless_and_reloads(self):
        self.run_case(existing="ss", action="vless")
        self.assert_applied(["vless", "shadowsocks"])

    def test_systemd_repair_updates_parameters(self):
        self.run_case(existing="both", action="vless", vless_port=19003, flow="xtls-rprx-vision")
        self.assert_applied(["vless", "shadowsocks"])
        inbound = json.loads(self.config.read_text())["inbounds"][0]
        self.assertEqual(inbound["port"], 19003)
        self.assertEqual(inbound["settings"]["clients"][0]["flow"], "xtls-rprx-vision")

    def test_existing_stopped_systemd_starts_and_enables(self):
        self.run_case(running=False, enabled="disabled")
        self.assert_applied(["vless", "shadowsocks"])
        self.assertEqual((self.root / "enabled").read_text().strip(), "enabled")

    def test_invalid_candidate_keeps_live_files_and_runtime_untouched(self):
        self.run_case(failure="invalid")
        self.assert_failed()
        self.assertFalse(any(event.startswith("systemctl") for event in self.events))
        self.assertTrue(any("synthetic-sensitive-diagnostic" in path.read_text()
                            for path in self.feature.glob(".config-apply.*/config-test.log")))

    def test_first_invalid_candidate_does_not_create_live_state(self):
        self.run_case(existing="none", running=False, enabled="disabled", failure="invalid")
        self.assert_failed(existing=False, running=False, enabled="disabled")

    def test_state_writer_failure_keeps_live_files_and_runtime_untouched(self):
        self.run_case(failure="state_write")
        self.assert_failed()
        self.assertFalse(any(event.startswith(("systemctl", "validate ")) for event in self.events))

    def test_config_writer_failure_keeps_live_files_and_runtime_untouched(self):
        self.run_case(failure="config_write")
        self.assert_failed()
        self.assertFalse(any(event.startswith(("systemctl", "validate ")) for event in self.events))

    def test_snapshot_failure_prevents_application(self):
        self.run_case(failure="snapshot")
        self.assert_failed()
        self.assertFalse(any(event.startswith("launch ") for event in self.events))

    def test_partial_file_install_restores_old_state(self):
        self.run_case(failure="rename")
        self.assert_failed()

    def test_systemd_apply_failure_restores_files_runtime_and_enabled(self):
        self.run_case(failure="apply")
        self.assert_failed()
        self.assertIn("旧配置及原有服务状态已恢复", self.result.stdout)
        self.assertEqual((self.root / "sidecar.service").read_text(), "synthetic old unit\n")

    def test_systemd_zero_exit_but_inactive_is_failure(self):
        self.run_case(failure="exited")
        self.assert_failed()

    def test_systemd_enable_failure_restores_disabled_running_service(self):
        self.run_case(failure="enable", enabled="disabled")
        self.assert_failed(enabled="disabled")

    def test_systemd_daemon_reload_failure_restores_unit(self):
        self.run_case(failure="daemon")
        self.assert_failed()

    def test_systemd_runtime_enablement_is_restored(self):
        self.run_case(failure="apply", enabled="enabled-runtime")
        self.assert_failed(enabled="enabled-runtime")

    def test_first_systemd_start_failure_removes_new_files_and_enablement(self):
        self.run_case(existing="none", running=False, enabled="disabled", failure="apply")
        self.assert_failed(existing=False, running=False, enabled="disabled")

    def test_systemd_failure_keeps_previously_stopped_service_stopped(self):
        self.run_case(running=False, enabled="disabled", failure="apply")
        self.assert_failed(running=False, enabled="disabled")

    def test_restore_failure_keeps_recovery_files_and_reports_uncertainty(self):
        self.run_case(failure="restore")
        self.assert_failed(restored=False)
        self.assertIn("自动恢复未完成", self.result.stderr)
        recovery = next(self.feature.glob(".config-apply.*"))
        self.assertTrue((recovery / "config.json.before").exists())
        self.assertTrue((recovery / "previous-state").exists())

    def test_first_non_systemd_install_starts_and_creates_cron(self):
        self.run_case(systemd=False, existing="none", action="vless", running=False, cron=False)
        self.assert_applied(["vless"])
        self.assertIn("@reboot sleep 10", (self.root / "crontab").read_text())

    def test_running_non_systemd_adds_ss_and_restarts(self):
        self.run_case(systemd=False)
        self.assert_applied(["vless", "shadowsocks"])
        self.assertIn("kill 12345", self.events)
        cron = (self.root / "crontab").read_text()
        self.assertIn("unrelated-job", cron)
        self.assertEqual(cron.count("@reboot"), 1)

    def test_running_non_systemd_adds_vless_and_restarts(self):
        self.run_case(systemd=False, existing="ss", action="vless")
        self.assert_applied(["vless", "shadowsocks"])

    def test_non_systemd_repair_updates_port_and_password(self):
        self.run_case(systemd=False, existing="both", ss_port=19004, rekey=True)
        self.assert_applied(["vless", "shadowsocks"])
        inbound = json.loads(self.config.read_text())["inbounds"][1]
        self.assertEqual(inbound["port"], 19004)
        self.assertEqual(inbound["settings"]["password"], "synthetic-password")

    def test_non_systemd_invalid_config_leaves_runtime_and_cron_untouched(self):
        self.run_case(systemd=False, failure="invalid")
        self.assert_failed(cron=True)
        self.assertNotIn("pkill", self.events)

    def test_non_systemd_immediate_exit_restores_old_service_and_cron(self):
        self.run_case(systemd=False, failure="exited")
        self.assert_failed(cron=True)

    def test_non_systemd_first_start_failure_removes_new_state_and_cron(self):
        self.run_case(systemd=False, existing="none", running=False, failure="apply", cron=False)
        self.assert_failed(existing=False, running=False, cron=False)

    def test_non_systemd_cron_write_failure_restores_old_service_and_cron(self):
        self.run_case(systemd=False, failure="cron_write")
        self.assert_failed(cron=True)

    def test_first_cron_write_failure_restores_absent_crontab(self):
        self.run_case(systemd=False, existing="none", running=False, failure="cron_write", cron=False)
        self.assert_failed(existing=False, running=False, cron=False)
        self.assertIn("旧配置及原有服务状态已恢复", self.result.stdout)

    def test_non_systemd_cron_read_failure_prevents_application(self):
        self.run_case(systemd=False, failure="cron_read")
        self.assert_failed(cron=True)
        self.assertNotIn("pkill", self.events)

    def test_non_systemd_cannot_stop_old_process_refuses_new_launch(self):
        self.run_case(systemd=False, failure="stuck")
        self.assert_failed(cron=True, restored=False)
        self.assertFalse(any(event.startswith("launch ") for event in self.events))
        self.assertIn("自动恢复未完成", self.result.stderr)

    def test_non_systemd_reused_pid_is_never_killed(self):
        self.run_case(systemd=False, failure="reused_pid")
        self.assert_failed(cron=True)
        self.assertFalse(any(event.startswith(("kill ", "launch ")) for event in self.events))
        self.assertNotIn("pkill", self.events)

    def test_non_systemd_unknown_pid_identity_is_never_killed(self):
        self.run_case(systemd=False, failure="unknown_pid")
        self.assert_failed(cron=True)
        self.assertFalse(any(event.startswith(("kill ", "launch ")) for event in self.events))

    def test_independent_start_does_not_reload_running_systemd(self):
        self.run_case(action="start")
        self.assertEqual(self.result.returncode, 0)
        self.assertFalse(any(event.startswith("launch ") for event in self.events))
        self.assertIn("systemctl enable --now agsbx-extra-vless-raw-enc", self.events)

    def test_independent_start_does_not_reload_running_non_systemd(self):
        self.run_case(action="start", systemd=False)
        self.assertEqual(self.result.returncode, 0)
        self.assertFalse(any(event.startswith("launch ") for event in self.events))
        self.assertNotIn("pkill", self.events)

    def test_core_only_action_still_persists_core_source(self):
        self.run_case(action="core")
        self.assertEqual(self.result.returncode, 0)
        self.assertIn("XRAY_SOURCE='synthetic'", (self.feature / "service.env").read_text())


    def test_clock_failure_never_changes_proxy_files(self):
        self.run_case(failure="clock")
        self.assert_failed()
        self.assertFalse(any(e.startswith("launch ") for e in self.events))

    def test_share_generation_failure_keeps_old_config(self):
        self.run_case(failure="share_write")
        self.assert_failed()

    def test_share_install_failure_restores_running_config(self):
        self.run_case(failure="share_rename")
        self.assert_failed()

    def test_parameter_actions_use_candidate_and_restore_on_failure(self):
        for action in ("ss_port", "vless_port", "flow", "ss_key", "uuid", "enc", "rewrite"):
            with self.subTest(action=action):
                self.run_case(existing="both", action=action, rekey=True, failure="share_rename")
                self.assert_failed()

    def test_metadata_actions_do_not_restart_service(self):
        for action in ("ss_name", "vless_name", "entry"):
            with self.subTest(action=action):
                self.run_case(existing="both", action=action)
                self.assertEqual(self.result.returncode, 0, self.result.stdout + self.result.stderr)
                self.assertEqual(self.config.read_bytes(), (self.root / "baseline.json").read_bytes())
                self.assertFalse(any(e.startswith(("launch ", "systemctl", "validate ")) for e in self.events))

    def test_metadata_share_failure_restores_without_service_calls(self):
        self.run_case(existing="both", action="ss_name", failure="share_rename")
        self.assert_failed()
        self.assertFalse(any(e.startswith(("launch ", "systemctl")) for e in self.events))

    def test_disable_last_protocol_removes_listener_and_autostart(self):
        for systemd in (True, False):
            with self.subTest(systemd=systemd):
                self.run_case(existing="ss", action="disable", rekey=True, systemd=systemd)
                self.assertEqual(self.result.returncode, 0, self.result.stdout + self.result.stderr)
                self.assertEqual(json.loads(self.config.read_text())["inbounds"], [])
                self.assertEqual((self.root / "running").read_text().strip(), "0")
                if systemd:
                    self.assertEqual((self.root / "enabled").read_text().strip(), "disabled")
                else:
                    self.assertNotIn("@reboot", (self.root / "crontab").read_text())
                self.assertNotIn("ss://", (self.feature / "share.txt").read_text())

    def test_disable_last_protocol_failure_restores_old_service(self):
        for systemd in (True, False):
            with self.subTest(systemd=systemd):
                self.run_case(existing="ss", action="disable", rekey=True, systemd=systemd,
                              failure="share_rename")
                self.assert_failed(cron=None if systemd else True)

    def test_disable_ss_keeps_vless_running(self):
        self.run_case(existing="both", action="disable", rekey=True)
        self.assertEqual(self.result.returncode, 0, self.result.stdout + self.result.stderr)
        self.assertEqual([x["protocol"] for x in json.loads(self.config.read_text())["inbounds"]], ["vless"])
        self.assertEqual((self.root / "running").read_text().strip(), "1")

    def test_independent_stop_reports_failure(self):
        self.run_case(action="stop", failure="stop")
        self.assertNotEqual(self.result.returncode, 0)
        self.assertEqual((self.root / "running").read_text().strip(), "1")

    def test_show_and_check_are_read_only(self):
        for action in ("show", "check"):
            with self.subTest(action=action):
                self.run_case(action=action)
                self.assertEqual(self.result.returncode, 0, self.result.stdout + self.result.stderr)
                self.assertEqual(self.config.read_bytes(), (self.root / "baseline.json").read_bytes())
                self.assertEqual((self.feature / "share.txt").read_text(), "synthetic old share\n")

    def test_ss2022_uri_uses_percent_encoded_credentials(self):
        self.run_case(existing="none", running=False)
        self.assertEqual(self.result.returncode, 0, self.result.stdout + self.result.stderr)
        self.assertIn("ss://2022-blake3-aes-128-gcm:synthetic-password@", (self.feature / "share.txt").read_text())


if __name__ == "__main__":
    unittest.main(verbosity=2)
