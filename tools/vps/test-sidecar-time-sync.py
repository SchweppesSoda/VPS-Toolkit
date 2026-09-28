#!/usr/bin/env python3
"""Exercise time prerequisites without contacting NTP or changing host services."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer.sh'
BASH = os.environ.get('BASH_BIN') or shutil.which('bash')
DRIVER = r'''
export PATH="/usr/bin:/bin:$PATH"
HAS_SYSTEMD=1
TIME_SYNC_MARKER="$TEST_ROOT/marker"
SS_ENABLED=1
SS_METHOD="$TEST_METHOD"
EVENTS="$TEST_ROOT/events"
: > "$EVENTS"
event() { printf '%s\n' "$*" >> "$EVENTS"; }
command_exists() { case "$1" in timeout|chronyc|ntpq|apt-get) return 0;; *) command -v "$1" >/dev/null;; esac; }
detect_init_system() { HAS_SYSTEMD="$TEST_SYSTEMD"; }
systemctl() {
  case "$1" in
    is-active)
      [[ "${*: -1}" == "$TEST_ACTIVE" ]] ||
        [[ "$TEST_ALIAS" == yes && "${*: -1}" == chronyd && "$TEST_ACTIVE" == chrony ]]
      ;;
    is-enabled) [[ "$2" == "$TEST_ENABLED" ]] && echo enabled ;;
    show)
      if [[ "$4" == Id ]]; then
        if [[ "$TEST_ALIAS" == yes && "$2" == chronyd ]]; then echo chrony.service
        else echo "$2.service"; fi
      else [[ "$2" == "$TEST_INSTALLED" ]] && echo loaded; fi
      ;;
    enable)
      event "enable ${*: -1}"
      [[ "$TEST_REPAIR_FAIL" != enable ]] || return 1
      TEST_ACTIVE="${*: -1}"; TEST_ENABLED="$TEST_ACTIVE"
      [[ "$TEST_REPAIR_FAIL" != sync ]] && TEST_AGE=0
      ;;
    *) return 99 ;;
  esac
}
stat() { [[ "$TEST_AGE" != missing ]] && echo "$((10000 - TEST_AGE))"; }
date() { echo 10000; }
timeout() { shift; "$@"; }
chronyc() { event "chronyc $*"; [[ "$TEST_SYNC" == yes ]]; }
ntpq() { printf '%s\n' "$TEST_NTP_REPORT"; }
pgrep() { [[ "$TEST_UNMANAGED" == yes ]]; }
apt-get() { event "apt $*"; [[ "$TEST_REPAIR_FAIL" != apt ]]; }
confirm_yes() { event prompt; [[ "$TEST_CONSENT" == yes ]]; }
sleep() { SECONDS=$((SECONDS + 61)); }
rc-service() { [[ "$1" == "$TEST_ACTIVE" ]]; }
rc-update() { echo "$TEST_ENABLED | default"; }
case "$TEST_ACTION" in
  probe) probe_time_sync; result=$?; echo "$TIME_SYNC_DETAIL"; exit "$result" ;;
  guard) ensure_ss_time_sync ;;
  repair) repair_time_sync ;;
esac
'''

class TimeSync(unittest.TestCase):
    def run_case(self, action='probe', active='systemd-timesyncd', enabled='systemd-timesyncd',
                 installed='', age='0', method='2022-blake3-aes-128-gcm', sync='yes',
                 report='leap=00, stratum=2, offset=0.03', consent='no', failure='',
                 unmanaged='no', systemd='1', alias='no'):
        with tempfile.TemporaryDirectory(prefix='sidecar-clock-', dir=ROOT / '.tmp') as scratch:
            root = Path(scratch)
            source = SCRIPT.read_text(encoding='utf-8').rstrip().rsplit('main "$@"', 1)[0]
            driver = root / 'driver.sh'
            driver.write_text(source + DRIVER, encoding='utf-8', newline='\n')
            env = dict(os.environ, TEST_ROOT=root.as_posix(), TEST_ACTION=action,
                       TEST_ACTIVE=active, TEST_ENABLED=enabled, TEST_INSTALLED=installed,
                       TEST_AGE=age, TEST_METHOD=method, TEST_SYNC=sync, TEST_NTP_REPORT=report,
                       TEST_CONSENT=consent, TEST_REPAIR_FAIL=failure,
                       TEST_UNMANAGED=unmanaged, TEST_SYSTEMD=systemd, TEST_ALIAS=alias)
            env.pop('BASH_ENV', None)
            result = subprocess.run([BASH, driver.as_posix()], env=env, capture_output=True,
                                    text=True, encoding='utf-8', timeout=10)
            events = (root / 'events').read_text(encoding='utf-8')
            return result, events

    def test_timesync_requires_recent_evidence_and_persistent_service(self):
        for args, good in [({}, True), ({'active': ''}, False), ({'enabled': ''}, False),
                           ({'age': '3601'}, False), ({'age': '-12'}, False),
                           ({'age': 'missing'}, False)]:
            with self.subTest(args=args):
                r, e = self.run_case(**args)
                self.assertEqual(r.returncode == 0, good, r.stdout + r.stderr)
                self.assertEqual(e, '')

    def test_chrony_checks_remaining_clock_correction(self):
        for sync in ('yes', 'no'):
            r, e = self.run_case(active='chrony', enabled='chrony', sync=sync)
            self.assertEqual(r.returncode == 0, sync == 'yes', r.stdout + r.stderr)
            self.assertIn('chronyc -n waitsync 1 0.5', e)

    def test_ntpd_rejects_unsynced_or_large_offsets(self):
        for report, good in [('leap=00, stratum=2, offset=-0.3', True),
                             ('leap=11, stratum=16, offset=0', False),
                             ('leap=00, stratum=2, offset=12000', False),
                             ('leap=00, stratum=2, offset=garbage', False)]:
            r, _ = self.run_case(active='ntpsec', enabled='ntpsec', report=report)
            self.assertEqual(r.returncode == 0, good, r.stdout + r.stderr)

    def test_guard_blocks_missing_sync_without_changing_host(self):
        r, e = self.run_case(action='guard', active='', enabled='')
        self.assertNotEqual(r.returncode, 0)
        self.assertNotIn('apt ', e)
        self.assertNotIn('enable ', e)

    def test_legacy_ss_has_no_ss2022_clock_gate(self):
        r, e = self.run_case(action='guard', active='', method='aes-128-gcm')
        self.assertEqual(r.returncode, 0)
        self.assertEqual(e, '')

    def test_repair_reuses_chrony_and_retains_time_sources(self):
        r, e = self.run_case(action='repair', active='chrony', enabled='', consent='yes')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('enable chrony', e)
        self.assertNotIn('apt ', e)
        self.assertNotIn('makestep', e)

    def test_chrony_service_alias_is_not_a_second_daemon(self):
        r, e = self.run_case(action='repair', active='chrony', enabled='', consent='yes', alias='yes')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('enable chrony', e)
        self.assertNotIn('apt ', e)

    def test_repair_installs_only_when_no_provider_exists(self):
        r, e = self.run_case(action='repair', active='', enabled='', age='missing', consent='yes')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('apt install -y --no-remove --no-install-recommends systemd-timesyncd', e)
        self.assertIn('enable systemd-timesyncd', e)

    def test_repair_refuses_unmanaged_daemon(self):
        r, e = self.run_case(action='repair', active='', enabled='', unmanaged='yes', consent='yes')
        self.assertNotEqual(r.returncode, 0)
        self.assertNotIn('apt ', e)

    def test_repair_failures_are_not_reported_as_success(self):
        for failure in ('apt', 'enable', 'sync'):
            r, _ = self.run_case(action='repair', active='', enabled='', age='missing',
                                 consent='yes', failure=failure)
            self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_openrc_reuses_existing_chrony(self):
        # probe itself uses caller's init detection, just as menu/preflight do.
        r, e = self.run_case(action='repair', active='chronyd', enabled='chronyd', systemd='0')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertNotIn('apt ', e)

if __name__ == '__main__':
    (ROOT / '.tmp').mkdir(exist_ok=True)
    unittest.main(verbosity=2)
