#!/usr/bin/env python3
"""Isolated regressions for core synchronization and firewall command construction."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer.sh'
BASH = os.environ.get('BASH_BIN') or shutil.which('bash')
SETUP = r'''
export PATH="/usr/bin:/bin:$PATH"
APP_ROOT="$TEST_ROOT/app"; BIN_DIR="$APP_ROOT/bin"; LOG_DIR="$APP_ROOT/logs"
BACKUP_DIR="$APP_ROOT/backups"; FEATURE_DIR="$APP_ROOT/feature"
ENV_FILE="$FEATURE_DIR/service.env"; CONFIG_FILE="$FEATURE_DIR/config.json"
XRAY_BIN="$BIN_DIR/xray"; ARGOSBX_XRAY="$TEST_ROOT/argosbx-xray"
ensure_dirs
printf old-core > "$XRAY_BIN"
printf new-core > "$ARGOSBX_XRAY"
printf config > "$CONFIG_FILE"
EVENTS="$TEST_ROOT/events"; : > "$EVENTS"
event() { printf '%s\n' "$*" >> "$EVENTS"; }
load_state() { SS_ENABLED=0; }
write_state() { echo "$XRAY_SOURCE" > "$ENV_FILE"; }
write_state
cp "$ENV_FILE" "$TEST_ROOT/env-before"
detect_init_system() { HAS_SYSTEMD=1; }
detect_argosbx() { return 0; }
service_is_running() { [[ "$TEST_RUNNING" == yes ]]; }
verify_xray_binary() {
  event verify
  [[ "$(cat "$XRAY_BIN")" == old-core ]] || return 95
  [[ "$TEST_FAILURE" != verify ]]
}
test_config() { event config-check; [[ "$TEST_FAILURE" != config ]]; }
restart_service() {
  event "restart $(cat "$XRAY_BIN")"
  [[ "$TEST_FAILURE" != restart || "$(cat "$XRAY_BIN")" == old-core ]]
}
command_exists() {
  case "$1" in
    ufw) [[ "$TEST_BACKEND" == ufw ]] ;;
    firewall-cmd) [[ "$TEST_BACKEND" == firewalld ]] ;;
    nft) [[ "$TEST_BACKEND" == nft ]] ;;
    iptables|ip6tables) [[ "$TEST_BACKEND" == iptables ]] ;;
    *) command -v "$1" >/dev/null ;;
  esac
}
ufw() {
  if [[ "$1" == status ]]; then echo "Status: $TEST_UFW_STATE"; return 0; fi
  event "ufw $*"; [[ "$TEST_FAILURE" != firewall ]]
}
firewall-cmd() {
  [[ "$1" != --state ]] || return 0
  event "firewall-cmd $*"; [[ "$TEST_FAILURE" != firewall ]]
}
detect_nft_input_chain() { echo 'inet filter input'; }
nft() { event "nft $*"; [[ "$TEST_FAILURE" != firewall ]]; }
iptables() { [[ "$1" != -C ]] || return 1; event "iptables $*"; [[ "$TEST_FAILURE" != firewall ]]; }
ip6tables() { [[ "$1" != -C ]] || return 1; event "ip6tables $*"; [[ "$TEST_FAILURE" != firewall ]]; }
case "$TEST_ACTION" in
  core) sync_xray_from_argosbx ;;
  firewall) open_firewall_port 19321 "$TEST_PROTO" "$TEST_SOURCE" ;;
  encode) urlencode '名称 &x=%/:+=' ;;
  menu)
    check_root() { :; }
    systemctl() { return 1; }
    read_prompt() { echo 0; }
    MENU_CLEAR=0
    main
    ;;

esac
'''
class Maintenance(unittest.TestCase):
    def run_case(self, action='core', failure='', running='yes', backend='',
                 source='192.0.2.0/24', proto='tcp,udp', ufw_state='active'):
        with tempfile.TemporaryDirectory(prefix='sidecar-maint-', dir=ROOT / '.tmp') as tmp:
            root=Path(tmp)
            definitions=SCRIPT.read_text(encoding='utf-8').rstrip().rsplit('main "$@"',1)[0]
            driver=root/'driver.sh'
            driver.write_text(definitions+SETUP,encoding='utf-8',newline='\n')
            env=dict(os.environ,TEST_ROOT=root.as_posix(),TEST_ACTION=action,TEST_FAILURE=failure,
                     TEST_RUNNING=running,TEST_BACKEND=backend,TEST_SOURCE=source,
                     TEST_PROTO=proto,TEST_UFW_STATE=ufw_state)
            env.pop('BASH_ENV',None)
            r=subprocess.run([BASH,driver.as_posix()],env=env,capture_output=True,text=True,encoding='utf-8',timeout=15)
            return r,(root/'events').read_text(),(root/'app/bin/xray').read_text()

    def test_core_is_validated_before_swap(self):
        r,e,core=self.run_case()
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        self.assertEqual(core,'new-core')
        self.assertEqual(e.splitlines(),['verify','config-check','restart new-core'])

    def test_bad_candidate_retains_original_core_without_restart(self):
        for failure in ('verify','config'):
            r,e,core=self.run_case(failure=failure)
            self.assertNotEqual(r.returncode,0)
            self.assertEqual(core,'old-core')
            self.assertNotIn('restart',e)

    def test_restart_failure_restores_and_restarts_original_core(self):
        r,e,core=self.run_case(failure='restart')
        self.assertNotEqual(r.returncode,0)
        self.assertEqual(core,'old-core')
        self.assertIn('restart old-core',e)

    def test_sync_does_not_start_stopped_service(self):
        r,e,core=self.run_case(running='no')
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        self.assertEqual(core,'new-core')
        self.assertNotIn('restart',e)

    def test_firewall_source_preserved_on_all_backends(self):
        for backend in ('ufw','firewalld','nft','iptables'):
            for source in ('192.0.2.0/24','2001:db8::/64'):
                with self.subTest(backend=backend,source=source):
                    r,e,_=self.run_case(action='firewall',backend=backend,source=source)
                    self.assertEqual(r.returncode,0,r.stdout+r.stderr)
                    rules=[x for x in e.splitlines() if '19321' in x]
                    self.assertEqual(len(rules),2,e)
                    self.assertTrue(all(source in x for x in rules),e)
                    if source.startswith('2001') and backend=='iptables':
                        self.assertTrue(all(x.startswith('ip6tables') for x in rules))

    def test_firewall_failures_never_report_success(self):
        for backend in ('ufw','firewalld','nft','iptables'):
            r,e,_=self.run_case(action='firewall',backend=backend,failure='firewall')
            self.assertNotEqual(r.returncode,0)
            self.assertNotIn('[完成]',r.stdout)

    def test_inactive_ufw_is_not_mistaken_for_active(self):
        r,e,_=self.run_case(action='firewall',backend='ufw',ufw_state='inactive')
        self.assertNotIn('ufw allow',e)

    def test_source_cannot_inject_rich_rule_syntax(self):
        r,e,_=self.run_case(action='firewall',backend='firewalld',source='x" accept')
        self.assertNotEqual(r.returncode,0)
        self.assertEqual(e,'')

    def test_tcp_only_nft_rule_does_not_fail_optional_udp_branch(self):
        r,e,_=self.run_case(action='firewall',backend='nft',proto='tcp')
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        self.assertEqual(len(e.splitlines()),1)

    def test_main_menu_is_sequential_and_exits(self):
        import re
        r, _, _ = self.run_case(action='menu')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        numbers = [int(x) for x in re.findall(r'^\s+(\d+)\)', r.stdout, flags=re.M)]
        self.assertEqual(numbers, list(range(1, 17)) + [0])
        self.assertIn('2026.09.28.1', r.stdout)

    def test_uri_encoding_is_utf8_and_reserved_characters_are_escaped(self):
        from urllib.parse import quote
        r,_,_=self.run_case(action='encode')
        self.assertEqual(r.returncode,0)
        self.assertEqual(r.stdout,quote('名称 &x=%/:+=',safe=''))

if __name__=='__main__':
    (ROOT/'.tmp').mkdir(exist_ok=True)
    unittest.main(verbosity=2)
