#!/usr/bin/env python3
"""Real, explicitly supplied Xray; random credentials and loopback traffic only.

Usage: SIDECAR_XRAY_BIN=/path/to/verified/xray python3 tools/vps/test-sidecar-xray-integration.py
The runner deliberately does not download or trust an arbitrary binary itself.
"""
import http.server
import json
import os
from pathlib import Path
import shutil
import socket
import struct
import subprocess
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer.sh'
BASH = os.environ.get('BASH_BIN') or shutil.which('bash')
XRAY = os.environ.get('SIDECAR_XRAY_BIN')


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def read_exact(sock, size):
    data = b''
    while len(data) < size:
        part = sock.recv(size - len(data))
        if not part:
            raise RuntimeError('unexpected socket EOF')
        data += part
    return data


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(204)
        self.end_headers()

    def log_message(self, *_):
        pass


class RealXray(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not XRAY or not Path(XRAY).is_file() or not BASH:
            raise RuntimeError('Supply BASH_BIN and a verified SIDECAR_XRAY_BIN; real tests must not silently skip')
        (ROOT / '.tmp').mkdir(exist_ok=True)
        cls.temp = tempfile.TemporaryDirectory(prefix='sidecar-real-', dir=ROOT / '.tmp')
        cls.addClassCleanup(cls.temp.cleanup)
        cls.root = Path(cls.temp.name)
        cls.http = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        cls.addClassCleanup(cls.http.server_close)
        cls.addClassCleanup(cls.http.shutdown)
        threading.Thread(target=cls.http.serve_forever, daemon=True).start()
        cls.ss_port, cls.vl_port = free_port(), free_port()
        cls.definitions = SCRIPT.read_text(encoding='utf-8').rstrip().rsplit('main "$@"', 1)[0]
        cls.driver = cls.root / 'generate.sh'
        cls.env = dict(os.environ, TEST_ROOT=cls.root.as_posix(), TEST_XRAY=Path(XRAY).resolve().as_posix(),
                       TEST_SS_PORT=str(cls.ss_port), TEST_VL_PORT=str(cls.vl_port))
        cls.env.pop('BASH_ENV', None)
        cls.setup = r'''
export PATH="/usr/bin:/bin:$PATH"
APP_ROOT="$TEST_ROOT"; FEATURE_DIR="$TEST_ROOT"; BACKUP_DIR="$TEST_ROOT/backups"
ENV_FILE="$TEST_ROOT/service.env"; CONFIG_FILE="$TEST_ROOT/config.json.next"
XRAY_BIN="$TEST_XRAY"; SHARE_FILE="$TEST_ROOT/share.txt"
mkdir -p "$BACKUP_DIR"
'''
        cls.driver.write_text(cls.definitions + cls.setup + r'''
load_state
PORT="$TEST_VL_PORT"; LISTEN=127.0.0.1
SS_PORT="$TEST_SS_PORT"; SS_LISTEN=127.0.0.1; SS_ENABLED=1
SS_PASSWORD="$(generate_ss_password)" || exit 1
generate_uuid && generate_vlessenc && write_state && write_config && test_config || exit 1
printf '%s' "$ENCRYPTION" > "$TEST_ROOT/encryption.txt"
''', encoding='utf-8', newline='\n')
        r = subprocess.run([BASH, cls.driver.as_posix()], env=cls.env, capture_output=True,
                           text=True, encoding='utf-8', timeout=30)
        if r.returncode:
            raise RuntimeError('real generated candidate failed: ' + r.stdout + r.stderr)
        cls.server_config = json.loads((cls.root / 'config.json.next').read_text())
        cls.server = cls.launch(cls.root / 'config.json.next', cls.ss_port)
        cls.addClassCleanup(cls.stop, cls.server)

    @classmethod
    def launch(cls, path, port):
        log = open(cls.root / (path.name + '.log'), 'wb')
        try:
            proc = subprocess.Popen([XRAY, 'run', '-format', 'json', '-config', str(path)],
                                    stdout=log, stderr=subprocess.STDOUT)
        finally:
            log.close()
        deadline = time.monotonic() + 6
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                raise RuntimeError('isolated Xray exited; inspect private test log')
            try:
                with socket.create_connection(('127.0.0.1', port), timeout=.1):
                    return proc
            except OSError:
                time.sleep(.05)
        cls.stop(proc)
        raise RuntimeError('isolated listener timeout')

    @staticmethod
    def stop(proc):
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=3)

    def client(self, protocol):
        port = free_port()
        if protocol == 'ss':
            settings = self.server_config['inbounds'][1]['settings']
            outbound = {'protocol': 'shadowsocks', 'settings': {'servers': [{
                'address': '127.0.0.1', 'port': self.ss_port,
                'method': settings['method'], 'password': settings['password']}]}}
        else:
            identity = self.server_config['inbounds'][0]['settings']['clients'][0]['id']
            outbound = {'protocol': 'vless', 'settings': {'vnext': [{
                'address': '127.0.0.1', 'port': self.vl_port,
                'users': [{'id': identity, 'encryption': (self.root / 'encryption.txt').read_text()}]}]},
                'streamSettings': {'network': 'raw', 'security': 'none'}}
        path = self.root / f'client-{protocol}.temporary'
        path.write_text(json.dumps({'log': {'loglevel': 'error'}, 'inbounds': [{
            'listen': '127.0.0.1', 'port': port, 'protocol': 'socks', 'settings': {'udp': True}}],
            'outbounds': [outbound]}), encoding='utf-8')
        proc = self.launch(path, port)
        self.addCleanup(self.stop, proc)
        return port

    def socks(self, port, cmd, dest_port):
        sock = socket.create_connection(('127.0.0.1', port), timeout=5)
        sock.settimeout(5)
        self.addCleanup(sock.close)
        sock.sendall(b'\x05\x01\x00')
        self.assertEqual(read_exact(sock, 2), b'\x05\x00')
        sock.sendall(b'\x05' + bytes([cmd]) + b'\x00\x01\x7f\x00\x00\x01' + struct.pack('!H', dest_port))
        head = read_exact(sock, 4)
        self.assertEqual(head[1], 0)
        if head[3] == 1:
            address = socket.inet_ntop(socket.AF_INET, read_exact(sock, 4))
        else:
            address = socket.inet_ntop(socket.AF_INET6, read_exact(sock, 16))
        bound_port = struct.unpack('!H', read_exact(sock, 2))[0]
        return sock, address, bound_port

    def test_generated_ss_and_vless_enc_tcp(self):
        for protocol in ('ss', 'vless'):
            with self.subTest(protocol=protocol):
                port = self.client(protocol)
                sock, _, _ = self.socks(port, 1, self.http.server_port)
                sock.sendall(b'GET / HTTP/1.0\r\nHost: localhost\r\n\r\n')
                self.assertIn(b'204', sock.recv(128))

    def test_generated_ss_udp_round_trip(self):
        echo = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        echo.bind(('127.0.0.1', 0))
        echo.settimeout(5)
        self.addCleanup(echo.close)
        def respond():
            data, addr = echo.recvfrom(1024)
            echo.sendto(data, addr)
        thread = threading.Thread(target=respond, daemon=True)
        thread.start()
        port = self.client('ss')
        _, address, bound = self.socks(port, 3, 0)
        udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.addCleanup(udp.close)
        udp.settimeout(5)
        packet = b'\x00\x00\x00\x01\x7f\x00\x00\x01' + struct.pack('!H', echo.getsockname()[1]) + b'sidecar-udp'
        udp.sendto(packet, (address, bound))
        data, _ = udp.recvfrom(1024)
        self.assertTrue(data.endswith(b'sidecar-udp'))
        thread.join(timeout=1)

    def test_script_connection_test_helper_uses_real_client(self):
        driver = self.root / 'connection.sh'
        driver.write_text(self.definitions + self.setup + r'''
TEST_URL="http://127.0.0.1:$TEST_HTTP_PORT/"
next_local_test_port() { printf '%s' "$TEST_SOCKS_PORT"; }
run_ss_xray_test 127.0.0.1 "$TEST_SS_PORT" synthetic
''', encoding='utf-8', newline='\n')
        r = subprocess.run([BASH, driver.as_posix()], env=dict(self.env, TEST_HTTP_PORT=str(self.http.server_port),
                           TEST_SOCKS_PORT=str(free_port())), capture_output=True, text=True, encoding='utf-8', timeout=25)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_explicit_json_accepts_candidate_while_auto_rejects(self):
        path = self.root / 'config.json.next'
        r = subprocess.run([XRAY, 'run', '-test', '-config', str(path)], capture_output=True, timeout=10)
        self.assertNotEqual(r.returncode, 0, 'review upstream behavior: auto now accepts .next')
        r = subprocess.run([XRAY, 'run', '-test', '-format', 'json', '-config', str(path)], capture_output=True, timeout=10)
        self.assertEqual(r.returncode, 0)

if __name__ == '__main__':
    unittest.main(verbosity=2)
