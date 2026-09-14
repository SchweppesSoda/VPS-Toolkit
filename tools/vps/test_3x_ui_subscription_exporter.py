import base64
import importlib.util
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/vps/3x-ui/3x-ui-subscription-exporter.py'
spec = importlib.util.spec_from_file_location('producer', SCRIPT)
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
NODE = 'vless://test-client@nodes.example.com:443?security=tls#Test'


class ProducerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'panel.db'
        self.db = sqlite3.connect(self.path)
        self.addCleanup(self.db.close)
        self.db.executescript('CREATE TABLE settings (key TEXT,value TEXT); CREATE TABLE inbounds (id INTEGER,enable INTEGER,protocol TEXT,settings TEXT);')
        self.db.executemany('INSERT INTO settings VALUES (?,?)', [('subEnable','true'),('subPort','2096')])
        self.client = {'id':'test-client','enable':True,'subId':'private-group'}
        self.put([self.client])
        self.config = {'database':str(self.path),'address':'nodes.example.com','clientIds':['test-client']}

    def put(self, clients):
        self.db.execute('DELETE FROM inbounds')
        self.db.execute('INSERT INTO inbounds VALUES (1,1,?,?)', ('vless',json.dumps({'clients':clients})))
        self.db.commit()

    def test_native_links_preserved_and_no_files_created(self):
        before = self.path.read_bytes()
        result = p.export(self.config, lambda *args: [NODE])
        self.assertEqual(result['links'], NODE+'\n')
        self.assertEqual(result['nodeCount'],1)
        self.assertEqual(result['expectedGroups'],result['successfulGroups'])
        self.assertEqual(self.path.read_bytes(),before)
        self.assertEqual([x.name for x in Path(self.temp.name).iterdir()],['panel.db'])

    def test_snapshot_survives_live_change_during_fetch(self):
        def fetch(*args):
            self.put([])
            return [NODE]
        self.assertEqual(p.export(self.config,fetch)['nodeCount'],1)

    def test_partial_group_rejected(self):
        self.put([self.client,{'id':'second','subId':'other'}])
        self.config['clientIds'].append('second')
        def fetch(port,path,*args):
            if path.endswith('other'):
                raise p.ExportError('fetch')
            return [NODE]
        with self.assertRaisesRegex(p.ExportError,'fetch'):
            p.export(self.config,fetch)

    def test_other_client_in_shared_group_rejected(self):
        self.put([self.client,{'id':'unrelated','subId':'private-group'}])
        with self.assertRaisesRegex(p.ExportError,'selection'):
            p.export(self.config,lambda *args:[NODE])

    def test_disabled_missing_expired_and_empty_fail(self):
        for clients in [[],[{**self.client,'enable':False}],[{**self.client,'expiryTime':1}],[{**self.client,'subId':''}]]:
            with self.subTest(clients=clients):
                self.put(clients)
                with self.assertRaises(p.ExportError):
                    p.export(self.config,lambda *args:[NODE])

    def test_removed_member_can_reduce_nonempty_subscription(self):
        self.config['clientIds'].append('removed')
        self.assertEqual(p.export(self.config,lambda *args:[NODE])['nodeCount'],1)

    def test_mismatched_native_output_rejected(self):
        for lines in [[],[NODE.replace('test-client','unrelated')],[NODE,NODE+'extra']]:
            with self.assertRaises(p.ExportError):
                p.export(self.config,lambda *args:lines)

    def test_base64_and_bad_response_bounds(self):
        self.assertEqual(p.normalize(base64.b64encode((NODE+'\n').encode())),[NODE])
        for raw in [b'',b'<html>Error</html>',b'{}',b'a'*(p.MAX_LINKS+1),b'http://bad',NODE.replace('nodes.example.com','127.0.0.1').encode(),(NODE+' bad').encode()]:
            with self.assertRaises(p.ExportError): p.normalize(raw)

    def test_failure_cli_has_no_secret_or_partial_stdout(self):
        result = subprocess.run([sys.executable,str(SCRIPT)],input=json.dumps({'secret':'must-not-appear'}).encode(),capture_output=True)
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(result.stdout,b'')
        self.assertEqual(result.stderr.replace(b'\r\n',b'\n'),b'3XUI_EXPORT_ERROR config\n')


if __name__ == '__main__': unittest.main()
