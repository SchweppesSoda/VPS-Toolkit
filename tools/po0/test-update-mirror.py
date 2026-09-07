"""Offline wire compatibility: frozen v1 peers and maintained manager/Worker.

No sockets or upstream requests are used. The actual Python Handler is invoked
with fake HTTP streams; actual Bash verifiers install only into a temporary dir.
"""
from pathlib import Path
from unittest.mock import patch
import contextlib,hashlib,hmac,io,json,os,re,shlex,subprocess,sys,tempfile

ROOT=Path(__file__).resolve().parents[2]
FIX=ROOT/'tools/po0/fixtures/update-v1'
KEY='offline-update-fixture'
NONCE='offline-nonce-12345'
URL='https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/nftables-relay-manager.sh'
BODY=b'#!/usr/bin/env bash\nSCRIPT_NAME="po0-nftables-relay-manager"\nSCRIPT_VERSION="2026.09.08+build.1"\n# CHANGELOG_BEGIN\n# fixture update\n# CHANGELOG_END\nexit 0\n'

def embedded(path): return path.read_text('utf-8').split("<<'PY'\n",1)[1].split('\nPY\n',1)[0]
class Server:
    def __init__(self,*args): pass
    def __enter__(self): return self
    def __exit__(self,*args): pass
    def serve_forever(self): pass

def handler(code):
    scope={}
    with patch.dict(os.environ,{'PO0_MANAGER_DOWNLOAD_URL':URL,'PO0_MANAGER_UPDATE_TOKENS':KEY}),patch.object(sys,'argv',['mirror','127.0.0.1','0']),patch('socketserver.ThreadingTCPServer',Server):
        exec(compile(code,'offline-mirror','exec'),scope)
    return scope

def get(scope,path,body=BODY):
    requests=[]
    def fetch(request,timeout):
        requests.append(request.full_url)
        assert request.full_url==URL and timeout==60
        return contextlib.closing(io.BytesIO(body))
    obj=scope['Handler'].__new__(scope['Handler']);obj.path=path;obj.wfile=io.BytesIO();obj.headers_out={}
    obj.send_response=lambda status:setattr(obj,'status',status)
    obj.send_header=lambda k,v:obj.headers_out.__setitem__(k,v)
    obj.end_headers=lambda:None
    with patch('urllib.request.urlopen',fetch):obj.do_GET()
    return obj.status,obj.headers_out,obj.wfile.getvalue(),requests

source=ROOT/'scripts/po0/relay'
peers={'old':(FIX/'mirror.py').read_text('utf-8'),'new':embedded(source/'lan-worker/src/130-manager-update-mirror.sh')}
urlpath='/po0-manager-update/nftables-relay-manager.sh?nonce='+NONCE+'&token_id='+hashlib.sha256(KEY.encode()).hexdigest()
with tempfile.TemporaryDirectory(prefix='po0-update-contract-',dir=ROOT/'.tmp') as temp:
    work=Path(temp);cases=[]
    for name,code in peers.items():
        scope=handler(code)
        status,headers,body,requests=get(scope,urlpath+'&url=https://arbitrary.invalid')
        assert status==200 and body==BODY and requests==[URL]
        assert headers['X-PO0-Manager-Nonce']==NONCE
        message='|'.join([NONCE,hashlib.sha256(body).hexdigest(),str(len(body)),headers['X-PO0-Manager-Version']])
        assert headers['X-PO0-Manager-HMAC']==hmac.new(KEY.encode(),message.encode(),hashlib.sha256).hexdigest()
        for path,want in [('/po0-manager-update/health',200),('/arbitrary',404),(urlpath.replace(NONCE,'x'),400),(urlpath.replace(hashlib.sha256(KEY.encode()).hexdigest(),'0'*64),403)]:
            result=get(scope,path);assert result[0]==want and not result[3]
        for invalid in [b'',b'x'*(2*1024*1024),b'#!/bin/sh\necho wrong-script\n']:
            assert get(scope,urlpath,invalid)[0]==502
        (work/f'{name}.body').write_bytes(body)
        (work/f'{name}.headers').write_text(''.join(k+': '+v+'\r\n' for k,v in headers.items()),'utf-8',newline='')
        cases.append(name)
    base=json.loads(json.dumps(headers))
    for field,value in [('Nonce','wrong-nonce'),('HMAC','0'*64),('SHA256','0'*64),('Size','1'),('Version','2000.01.01+build.1')]:
        name='bad-'+field;copy=dict(base);copy['X-PO0-Manager-'+field]=value
        (work/f'{name}.body').write_bytes(BODY)
        (work/f'{name}.headers').write_text(''.join(k+': '+v+'\r\n' for k,v in copy.items()),'utf-8',newline='')
        cases.append(name)
    # Correctly authenticated but malformed Bash is rejected before replacement.
    invalid=BODY+b'if then\n';copy=dict(base);copy['X-PO0-Manager-SHA256']=hashlib.sha256(invalid).hexdigest();copy['X-PO0-Manager-Size']=str(len(invalid))
    copy['X-PO0-Manager-HMAC']=hmac.new(KEY.encode(),'|'.join([NONCE,copy['X-PO0-Manager-SHA256'],str(len(invalid)),copy['X-PO0-Manager-Version']]).encode(),hashlib.sha256).hexdigest()
    (work/'bad-syntax.body').write_bytes(invalid);(work/'bad-syntax.headers').write_text(''.join(k+': '+v+'\r\n' for k,v in copy.items()),'utf-8',newline='');cases.append('bad-syntax')
    harness=r'''#!/usr/bin/env bash
set -uo pipefail
export PATH="/usr/bin:/bin:$PATH"
source "$1"
source "$2"
WORK="$3"; shift 3
SCRIPT_NAME=po0-nftables-relay-manager; SCRIPT_VERSION=2026.09.07+build.2
MANAGER_INSTALL_PATH="$WORK/installed.sh"; BACKUP_DIR="$WORK/backups"; mkdir -p "$BACKUP_DIR"
MANAGER_UPDATE_URL=http://fixture.invalid/po0-manager-update/nftables-relay-manager.sh
ensure_layout() { :; }; load_settings() { :; }
trim() { printf '%s' "$1"; }; err() { printf '%s\n' "$*" >&2; }
resource_task_token_value() { printf offline-update-fixture; }
manager_update_token_value() { resource_task_token_value; }
random_update_nonce() { printf offline-nonce-12345; }
make_temp_file() { TEMP_FILE_RESULT="$1.$RANDOM"; : > "$TEMP_FILE_RESULT"; }
curl() {
 local headers='' body=''
 while (( $# )); do case "$1" in -D) headers="$2";shift 2;; -o) body="$2";shift 2;; *) shift;;esac;done
 cp "$WORK/$CASE.headers" "$headers" && cp "$WORK/$CASE.body" "$body"
}
for CASE in "$@"; do
 printf 'old installed bytes\n' > "$MANAGER_INSTALL_PATH"
 if do_upgrade_manager_from_lan > "$WORK/run.log" 2>&1; then rc=0;else rc=$?;fi
 if [[ "$CASE" == bad-* ]]; then
  [[ "$rc" != 0 ]] && grep -Fxq 'old installed bytes' "$MANAGER_INSTALL_PATH" || { printf 'FAIL rejected case %s\n' "$CASE";exit 1; }
 else
  [[ "$rc" == 0 ]] && cmp "$WORK/$CASE.body" "$MANAGER_INSTALL_PATH" || { cat "$WORK/run.log";exit 1; }
 fi
done
'''
    (work/'verify.sh').write_text(harness,'utf-8',newline='\n')
    bash='C:/Program Files/Git/bin/bash.exe' if os.name=='nt' else 'bash'
    for label,helpers,verifier in [('old',FIX/'helpers.sh',FIX/'manager.sh'),('new',source/'manager/src/330-render-update-helpers.sh',source/'manager/src/340-manager-update-version.sh')]:
        run=subprocess.run([bash,(work/'verify.sh').as_posix(),helpers.as_posix(),verifier.as_posix(),work.as_posix(),*cases],capture_output=True,text=True,encoding='utf-8')
        assert run.returncode==0,label+': '+run.stdout+run.stderr
    print('PASS: old/new mirror × old/new manager; invalid nonce/HMAC/hash/size/version/syntax never replaces installed script.')
