import base64
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import urllib.parse

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/vps/xray/xray-subscription-exporter.py'
spec = importlib.util.spec_from_file_location('xray_producer', SCRIPT)
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
# RFC 7748 section 6.1 Alice X25519 key pair; entirely synthetic public fixture.
PRIVATE = base64.urlsafe_b64encode(bytes.fromhex('77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a')).decode().rstrip('=')
PUBLIC = 'hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo'
IDS = [f'{n:08x}-1111-4111-8111-111111111111' for n in range(1, 7)]


def fixture():
    return {'inbounds': [
        {'tag': '公网 / Reality#1', 'port': 19033, 'protocol': 'vless',
         'settings': {'decryption': 'none', 'clients': [{'id': x, 'flow': 'xtls-rprx-vision', 'email': 'user', 'level': 0} for x in IDS]},
         'streamSettings': {'network': 'tcp', 'security': 'reality',
                            'realitySettings': {'privateKey': PRIVATE, 'publicKey': PUBLIC, 'dest': 'example.com:443',
                                                'serverNames': ['z.example.com', 'example.com'],
                                                'shortIds': ['', '1122', '0123456789abcdef']}}},
        {'listen': '127.0.0.1', 'port': 39000, 'protocol': 'tunnel', 'settings': {'address': '127.0.0.1'}}]}


class ProducerTests(unittest.TestCase):
    def setUp(self):
        if os.name == 'nt':
            # Windows fstat exposes ctime as last-write while lstat exposes
            # creation time. Production is Linux; keep its stricter contract.
            signature = patch.object(p, 'file_signature', lambda x: (x.st_dev, x.st_ino, x.st_size, x.st_mtime_ns))
            signature.start()
            self.addCleanup(signature.stop)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'config.json'
        self.document = fixture()
        self.write()
        self.config = {'schemaVersion': 2, 'selection': 'all-public-clients', 'configPath': '/synthetic/config.json',
                       'address': 'nodes.example.com', 'fingerprint': 'chrome', 'namePrefix': 'DMIT PRO 中文 & #'}

    def write(self):
        self.path.write_text(json.dumps(self.document), encoding='utf-8')

    def export(self, derive=lambda _: PUBLIC):
        reader = p.read_snapshot
        with patch.object(p, 'read_snapshot', side_effect=lambda _: reader(self.path)):
            return p.export(self.config, derive)

    def fails(self, category='selection'):
        self.write()
        with self.assertRaisesRegex(p.ExportError, '^' + category + '$'):
            self.export()

    def test_all_six_new_clients_loopback_excluded_and_envelope(self):
        before = self.path.read_bytes()
        result = self.export()
        lines = p.normalize(result['links'].encode())
        self.assertEqual(result['schemaVersion'], 1)
        self.assertEqual(result['nodeCount'], 6)
        self.assertEqual(result['expectedGroups'], 1)
        self.assertEqual(result['successfulGroups'], 1)
        self.assertEqual(result['bytes'], len(result['links'].encode()))
        self.assertEqual(result['sha256'], hashlib.sha256(result['links'].encode()).hexdigest())
        self.assertEqual([p.node_parameters(x)['uuid'] for x in lines], IDS)
        self.assertEqual(self.path.read_bytes(), before)
        self.assertEqual([x.name for x in self.path.parent.iterdir()], ['config.json'])

    def test_parameter_encoding_and_deterministic_multi_sni_sid(self):
        lines = self.export()['links'].splitlines()
        for index, line in enumerate(lines, 1):
            data = p.node_parameters(line)
            self.assertEqual({x: data[x] for x in ['flow', 'sni', 'pbk', 'sid', 'fp', 'type', 'security', 'encryption']},
                             {'flow': 'xtls-rprx-vision', 'sni': 'example.com', 'pbk': PUBLIC, 'sid': '0123456789abcdef',
                              'fp': 'chrome', 'type': 'tcp', 'security': 'reality', 'encryption': 'none'})
            name = urllib.parse.unquote(urllib.parse.urlsplit(line).fragment)
            label = hashlib.sha256(IDS[index-1].encode()).hexdigest()[:12]
            self.assertEqual(name, f'DMIT PRO 中文 & # 公网 / Reality#1:19033 client-{label}')
            self.assertNotIn(' ', line)
            self.assertIn('%23', line)
        original = self.export()['links']
        self.document['inbounds'].reverse()
        public = self.document['inbounds'][1]
        public['settings']['clients'].reverse()
        public['streamSettings']['realitySettings']['serverNames'].reverse()
        public['streamSettings']['realitySettings']['shortIds'].reverse()
        self.write()
        self.assertEqual(self.export()['links'], original)
        self.assertEqual(p.normalize(base64.b64encode(original.encode())), original.splitlines())

    def test_raw_alias_and_absent_transport_default_are_equivalent(self):
        expected = self.export()['links']
        stream = self.document['inbounds'][0]['streamSettings']
        for variant in [{'method': 'raw'}, {'network': 'raw'}, {'network': 'tcp', 'method': 'raw'}, {}]:
            stream.pop('network', None); stream.pop('method', None)
            stream.update(variant)
            self.write()
            self.assertEqual(self.export()['links'], expected)

    def test_names_of_remaining_clients_survive_member_removal(self):
        expected = {p.node_parameters(x)['uuid']: x for x in self.export()['links'].splitlines()}
        self.document['inbounds'][0]['settings']['clients'].pop(0)
        self.write()
        self.assertEqual(self.export()['links'].splitlines(), [expected[x] for x in IDS[1:]])

    def test_internal_addresses_sockets_and_management_tag_excluded(self):
        for listen in ['::1', '::ffff:127.0.0.1', '10.0.0.1', '192.168.1.1', '/run/xray.sock', '@xray', 'localhost']:
            self.document['inbounds'][1]['listen'] = listen
            self.write()
            self.assertEqual(self.export()['nodeCount'], 6)
        self.document['api'] = {'tag': 'api'}
        self.document['inbounds'][1].update(tag='api', listen='0.0.0.0')
        self.write()
        self.assertEqual(self.export()['nodeCount'], 6)

    def test_unsupported_public_inbound_fails_whole_selection(self):
        self.document['inbounds'][1]['listen'] = '0.0.0.0'
        self.fails()
        self.document = fixture()
        original = copy.deepcopy(self.document['inbounds'][0]['streamSettings'])
        for change in [{'network': 'ws'}, {'method': 'xhttp'}, {'network': 'tcp', 'method': 'grpc'},
                       {'security': 'tls'}, {'tcpSettings': {'header': {'type': 'http'}}},
                       {'rawSettings': {'header': {'type': 'http'}}}, {'finalmask': {'udp': []}}]:
            with self.subTest(change=change):
                self.document['inbounds'][0]['streamSettings'] = {**original, **change}
                self.fails()
        self.document = fixture()
        self.document['inbounds'][0]['settings']['decryption'] = 'mlkem768x25519plus.native.600s.key'
        self.fails()
        self.document = fixture()
        self.document['inbounds'][0]['settings']['clients'][0]['encryption'] = 'mlkem'
        self.fails()

    def test_empty_invalid_duplicate_and_non_vision_clients_fail(self):
        for clients in [[], [{}], [{'id': 'bad'}], [{'id': IDS[0], 'flow': 'other'}],
                        [{'id': IDS[0]}, {'id': IDS[0]}], [{'id': '00000000-0000-0000-0000-000000000000'}]]:
            with self.subTest(clients=clients):
                self.document = fixture()
                self.document['inbounds'][0]['settings']['clients'] = clients
                self.fails()
        self.document = {'inbounds': [fixture()['inbounds'][1]]}
        self.fails()

    def test_missing_bad_or_mismatched_reality_parameters_fail(self):
        for key, value, category in [('privateKey', None, 'key-derivation'), ('privateKey', 'x'*43+'=', 'key-derivation'),
                                      ('publicKey', 'x'*43, 'key-derivation'), ('serverNames', [], 'selection'),
                                      ('serverNames', ['*.example.com'], 'selection'), ('serverNames', ['ok.com', 123], 'selection'),
                                      ('shortIds', [], 'selection'), ('shortIds', ['1'], 'selection'),
                                      ('shortIds', ['z1'], 'selection'), ('shortIds', ['01'*9], 'selection'),
                                      ('mldsa65Seed', 'unsupported', 'selection')]:
            with self.subTest(key=key, value=value):
                self.document = fixture()
                self.document['inbounds'][0]['streamSettings']['realitySettings'][key] = value
                self.fails(category)
        self.document = fixture()
        self.document['inbounds'][0]['streamSettings']['realitySettings']['shortIds'] = ['']
        self.write()
        self.assertEqual(p.node_parameters(self.export()['links'].splitlines()[0])['sid'], '')

    def test_read_change_and_atomic_replacement_even_with_same_bytes_fail(self):
        original = self.path.read_bytes()
        def mutate(_):
            self.path.write_bytes(original + b' ')
            return PUBLIC
        with self.assertRaisesRegex(p.ExportError, 'xray-config'):
            self.export(mutate)
        self.write()
        def replace(_):
            replacement = self.path.with_name('replacement')
            replacement.write_bytes(self.path.read_bytes())
            os.replace(replacement, self.path)
            return PUBLIC
        with self.assertRaisesRegex(p.ExportError, 'xray-config'):
            self.export(replace)

    def test_duplicate_keys_bad_json_and_oversized_file_fail(self):
        for raw in [b'{"inbounds":[],"inbounds":[]}', b'{"inbounds":NaN}', b'{bad', b'a'*(p.MAX_CONFIG+1)]:
            with self.subTest(size=len(raw)):
                self.path.write_bytes(raw)
                with self.assertRaisesRegex(p.ExportError, 'xray-config'):
                    self.export()

    def test_old_schema_and_invalid_configuration_fail_before_read(self):
        for config in [{'database': '/etc/x-ui/x-ui.db', 'clientIds': ['old'], 'address': 'nodes.example.com'},
                       {**self.config, 'clientIds': IDS}, {**self.config, 'selection': 'some-clients'},
                       {**self.config, 'configPath': '/a/../b'}, {**self.config, 'address': '127.0.0.1'},
                       {**self.config, 'address': '0.0.0.0'}, {**self.config, 'fingerprint': 'unknown'}]:
            with self.subTest(config=config), patch.object(p, 'read_snapshot') as read:
                with self.assertRaisesRegex(p.ExportError, 'config'):
                    p.export(config)
                read.assert_not_called()

    def test_uri_integrity_rejects_missing_duplicate_and_wrong_parameters(self):
        line = self.export()['links'].splitlines()[0]
        for bad in [line.replace('pbk='+PUBLIC, 'pbk=bad'), line.replace('flow=xtls-rprx-vision', 'flow=other'),
                    line.replace('security=reality', 'security=tls'), line.replace('sni=example.com&', ''),
                    line.replace('#', '&sid=01#'), line.replace('nodes.example.com', '127.0.0.1')]:
            with self.assertRaises(p.ExportError):
                p.normalize(bad.encode())
        with self.assertRaises(p.ExportError): p.normalize((line+'\n'+line+'\n').encode())

    def test_failure_cli_has_no_secret_or_partial_stdout(self):
        secret = 'must-not-appear'
        result = subprocess.run([sys.executable, '-I', '-B', str(SCRIPT)],
                                input=json.dumps({'privateKey': secret}).encode(), capture_output=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, b'')
        self.assertEqual(result.stderr.replace(b'\r\n', b'\n'), b'XRAY_EXPORT_ERROR config\n')


@unittest.skipUnless(os.name == 'posix' and Path(p.OPENSSL).is_file(), 'trusted Linux OpenSSL required')
class OpenSSLTests(unittest.TestCase):
    def test_rfc7748_key_via_stdin_der_and_no_artifacts(self):
        self.assertEqual(p.derive_public_key(PRIVATE), PUBLIC)

    def test_wrong_der_and_secret_stderr_are_redacted(self):
        # A real trusted executable remains fixed; malformed keys fail before
        # process creation. The strict SPKI prefix is independently exercised.
        for key in ['', 'private-secret', PRIVATE+'=', 'x'*43]:
            with patch.object(p.subprocess, 'Popen') as popen:
                with self.assertRaisesRegex(p.ExportError, 'key-derivation'):
                    p.derive_public_key(key)
                popen.assert_not_called()
        with patch.object(p, 'SPKI_PREFIX', b'invalid-DER'):
            with self.assertRaisesRegex(p.ExportError, 'key-derivation'):
                p.derive_public_key(PRIVATE)

    def test_cli_success_and_unsupported_partial_has_empty_stdout(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'config.json'
            config = {'schemaVersion': 2, 'selection': 'all-public-clients', 'configPath': str(path), 'address': 'nodes.example.com'}
            data = fixture()
            path.write_text(json.dumps(data))
            success = subprocess.run([sys.executable, '-I', '-B', str(SCRIPT)], input=json.dumps(config).encode(), capture_output=True)
            self.assertEqual(success.returncode, 0)
            self.assertEqual(json.loads(success.stdout)['nodeCount'], 6)
            data['inbounds'][1]['listen'] = '0.0.0.0'
            path.write_text(json.dumps(data))
            failure = subprocess.run([sys.executable, '-I', '-B', str(SCRIPT)], input=json.dumps(config).encode(), capture_output=True)
            self.assertEqual(failure.returncode, 1)
            self.assertEqual(failure.stdout, b'')
            self.assertEqual(failure.stderr, b'XRAY_EXPORT_ERROR selection\n')


if __name__ == '__main__': unittest.main()
