#!/usr/bin/env python3
"""Exercise downloader/verification with synthetic ZIPs and stubbed commands."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import warnings
import zipfile

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer.sh"
BASH = os.environ.get("BASH_BIN") or shutil.which("bash")


class XrayDownload(unittest.TestCase):
    def setUp(self):
        if not BASH:
            self.fail("Bash is required (set BASH_BIN on Windows)")
        self.temp = tempfile.TemporaryDirectory(prefix="sidecar-xray-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.binary = self.bin / "xray"
        self.binary.write_bytes(b"synthetic previous binary")
        source = SCRIPT.read_text(encoding="utf-8")
        assert source.rstrip().endswith('main "$@"'), "entrypoint changed; review test isolation"
        # Definitions only: do not enter the manager/root/menu/install flow.
        definitions = source.rstrip().rsplit('main "$@"', 1)[0]
        if os.name == "nt":
            # Git Bash cannot mark a synthetic ELF executable on NTFS. Commands
            # remain stubbed; the real POSIX -x check is exercised only on Linux.
            assert definitions.count('[[ ! -x "$binary" ]]') == 1
            definitions = definitions.replace('[[ ! -x "$binary" ]]', '[[ ! -f "$binary" ]]')
        self.driver = self.root / "driver.sh"
        self.driver.write_text(definitions + '''
export PATH="/usr/bin:/bin:$PATH"
BIN_DIR="$TEST_BIN_DIR"
XRAY_BIN="$BIN_DIR/xray"
uname() { printf '%s\\n' "$TEST_ARCH"; }
ensure_unzip() { command -v unzip >/dev/null; }
download_file() {
  printf '%s\\n' "$1" > "$TEST_DOWNLOAD_URL"
  [[ "${TEST_DOWNLOAD_FAIL:-0}" == 0 ]] || return 1
  cp -- "$TEST_ARCHIVE" "$2"
}
curl() { echo 'unexpected network operation' >&2; return 99; }
wget() { echo 'unexpected network operation' >&2; return 99; }
xray_binary_command() {
  [[ "$1" == "$BIN_DIR"/.xray-candidate.* ]] || return 98
  [[ "$(cat "$XRAY_BIN")" == 'synthetic previous binary' ]] || return 97
  printf '%s\\n' "$2" >> "$TEST_PROBES"
  [[ "${TEST_PROBE_FAIL:-}" != "$2" ]] || return 1
  if [[ "$2" == version ]]; then printf 'Xray %s (Xray, Penetrates Everything.)\\n' "${TEST_REPORTED_VERSION}"; fi
}
download_official_xray_binary || exit $?
printf '%s\\n' "$XRAY_SOURCE"
''', encoding="utf-8", newline="\n")

    def elf(self, cls=2, endian=1, machine=62):
        data = bytearray(64)
        data[:7] = b"\x7fELF" + bytes([cls, endian, 1])
        data[18:20] = machine.to_bytes(2, "little" if endian == 1 else "big")
        return bytes(data)

    def archive(self, data=None, *, duplicate=False, traversal=False):
        path = self.root / "fixture.zip"
        data = self.elf() if data is None else data
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("xray", data)
            if duplicate:
                with warnings.catch_warnings():
                    warnings.simplefilter("ignore", UserWarning)
                    archive.writestr("xray", data)
            if traversal:
                archive.writestr("../../MUST_NOT_EXTRACT", "synthetic")
        return path, hashlib.sha256(path.read_bytes()).hexdigest(), data

    def run_download(self, *, arch="x86_64", tag="v26.3.27", sha=None, archive=None, fail=False, probe_fail="", reported=None):
        self.binary.write_bytes(b"synthetic previous binary")
        (self.root / "probes").unlink(missing_ok=True)
        if archive is None:
            archive, valid_sha, _ = self.archive()
        else:
            valid_sha = hashlib.sha256(archive.read_bytes()).hexdigest()
        env = dict(os.environ, TEST_BIN_DIR=self.bin.as_posix(), TEST_ARCH=arch,
                   TEST_DOWNLOAD_URL=(self.root / "download-url").as_posix(),
                   TEST_ARCHIVE=archive.as_posix(), XRAY_RELEASE_TAG=tag,
                   XRAY_RELEASE_SHA256=valid_sha if sha is None else sha,
                   TEST_DOWNLOAD_FAIL="1" if fail else "0",
                   TEST_PROBES=(self.root / "probes").as_posix(), TEST_PROBE_FAIL=probe_fail,
                   TEST_REPORTED_VERSION=reported if reported is not None else tag.removeprefix("v"))
        env.pop("BASH_ENV", None)
        return subprocess.run([BASH, self.driver.as_posix()], env=env, capture_output=True, text=True)

    def assert_preserved(self, result):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.binary.read_bytes(), b"synthetic previous binary")
        self.assertEqual(list(self.bin.glob(".xray-candidate.*")), [])

    def test_pinned_download_checks_then_probes_candidate_before_replacing(self):
        archive, _, data = self.archive()
        result = self.run_download(archive=archive)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.binary.read_bytes(), data)
        url = (self.root / "download-url").read_text().strip()
        self.assertEqual(url, "https://github.com/XTLS/Xray-core/releases/download/v26.3.27/Xray-linux-64.zip")
        self.assertIn("sha256:", result.stdout)
        self.assertNotIn("latest", result.stdout)
        self.assertEqual((self.root / "probes").read_text().splitlines(), ["version", "uuid", "vlessenc"])

    def test_bad_checksum_preserves_previous_binary(self):
        self.assert_preserved(self.run_download(sha="0" * 64))
        self.assertFalse((self.root / "probes").exists())

    def test_wrong_reported_version_preserves_previous_binary(self):
        for report in ("26.3.28", "", "v26.3.27"):
            self.assert_preserved(self.run_download(reported=report))
            self.assertEqual((self.root / "probes").read_text().splitlines(), ["version"])

    def test_candidate_command_failures_preserve_previous_binary(self):
        for command in ("version", "uuid", "vlessenc"):
            self.assert_preserved(self.run_download(probe_fail=command))
            self.assertEqual((self.root / "probes").read_text().splitlines()[-1], command)

    def test_custom_version_requires_valid_explicit_hash(self):
        self.assert_preserved(self.run_download(tag="v99.1.2", sha=""))
        self.assertFalse((self.root / "download-url").exists())
        self.assert_preserved(self.run_download(tag="v99.1.2", sha="invalid"))
        self.assertEqual(self.run_download(tag="v99.1.2").returncode, 0)
        self.assertIn("/v99.1.2/", (self.root / "download-url").read_text())

    def test_latest_and_unsafe_tags_fail_before_download(self):
        for tag in ("latest", "../../bad", "v26.3.27?extra", "v26.3.27/evil"):
            with self.subTest(tag=tag):
                self.assert_preserved(self.run_download(tag=tag))
                self.assertFalse((self.root / "download-url").exists())

    def test_supported_elf_architectures_and_unknown_architecture(self):
        for arch, cls, endian, machine in (
                ("x86_64", 2, 1, 62), ("i686", 1, 1, 3), ("aarch64", 2, 1, 183),
                ("armv5l", 1, 1, 40), ("armv6l", 1, 1, 40), ("armv7l", 1, 1, 40),
                ("s390x", 2, 2, 22), ("riscv64", 2, 1, 243), ("ppc64le", 2, 1, 21),
                ("ppc64", 2, 2, 21), ("loongarch64", 2, 1, 258)):
            with self.subTest(arch=arch):
                archive, _, data = self.archive(self.elf(cls, endian, machine))
                result = self.run_download(arch=arch, archive=archive)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(self.binary.read_bytes(), data)
        self.binary.write_bytes(b"synthetic previous binary")
        self.assert_preserved(self.run_download(arch="unknown"))

    def test_wrong_architecture_endian_and_non_elf_are_rejected(self):
        for data in (self.elf(machine=183), self.elf(cls=1), self.elf(endian=2), b"#!/bin/sh\nexit 0", b"\x7fELF"):
            archive, _, _ = self.archive(data)
            self.assert_preserved(self.run_download(archive=archive))
            self.assertFalse((self.root / "probes").exists())

    def test_duplicate_member_rejected_and_unrelated_paths_not_extracted(self):
        archive, _, _ = self.archive(duplicate=True)
        self.assert_preserved(self.run_download(archive=archive))
        archive, _, _ = self.archive(traversal=True)
        result = self.run_download(archive=archive)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.root / "MUST_NOT_EXTRACT").exists())

    def test_network_failure_keeps_previous_binary(self):
        self.assert_preserved(self.run_download(fail=True))

    def test_default_pin_table_covers_existing_architecture_mapping(self):
        source = SCRIPT.read_text(encoding="utf-8")
        # All 11 existing architecture selections need a default reviewed digest.
        import re
        selector = source.split("xray_release_asset_name() {", 1)[1].split("\n}\n", 1)[0]
        assets = set(re.findall(r'echo "(Xray-linux[^" ]+\.zip)"', selector))
        pins = source.split("xray_release_sha256() {", 1)[1].split("\n}\n", 1)[0]
        pairs = dict(re.findall(r'(Xray-linux[^ )]+\.zip)\) echo ([a-f0-9]{64})', pins))
        self.assertEqual(assets, set(pairs))
        self.assertEqual(len(pairs), 11)


if __name__ == "__main__":
    unittest.main(verbosity=2)
