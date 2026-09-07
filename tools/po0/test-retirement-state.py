from pathlib import Path
import io,os,subprocess,sys,tarfile,tempfile
ROOT=Path(__file__).resolve().parents[2]
def archive(path,files,extra=None):
    with tarfile.open(path,'w:gz') as tar:
        for name,data in files.items():
            info=tarfile.TarInfo(name);raw=data.encode();info.size=len(raw);info.mode=0o600;tar.addfile(info,io.BytesIO(raw))
        if extra:tar.addfile(extra)

with tempfile.TemporaryDirectory(prefix='po0-retirement-state-',dir=ROOT/'.tmp') as directory:
    work=Path(directory)
    files={'./manifest.env':'format=po0-relay-backup-v2\n','./files/conf-dir/po0-relay.env':'NODE_NAME="restored"\nENABLE_SRC_ALLOWLIST="0"\nMANAGE_INPUT_FIREWALL="0"\n','./files/conf-dir/po0-relay.rules':'fixture-rule\n','./files/conf-dir/po0-relay.conf':'table ip po0_relay_nat {}\n','./files/conf-dir/po0-relay-resource-task.token':'paired-key\n'}
    archive(work/'manager-good.tar.gz',files)
    archive(work/'manager-missing.tar.gz',{'./manifest.env':files['./manifest.env']})
    bad=dict(files);bad['./files/conf-dir/po0-relay.env']='ENABLE_SRC_ALLOWLIST="1"\n';archive(work/'manager-protected.tar.gz',bad)
    bad=dict(files);bad['../escaped']='bad';archive(work/'manager-path.tar.gz',bad)
    link=tarfile.TarInfo('./files/conf-dir/po0-relay.rules');link.type=tarfile.SYMTYPE;link.linkname='../escaped';archive(work/'manager-link.tar.gz',files,link)
    archive(work/'worker-good.tar.gz',{'settings.env':"MANAGER_UPDATE_LISTEN='127.0.0.1:8789'\nMANAGER_UPDATE_DOMAIN='old-host'\n",'update-keys.txt':'key-a\nkey-b\n'})
    archive(work/'worker-execute.tar.gz',{'settings.env':"MANAGER_UPDATE_DOMAIN=$(touch escaped)\n",'update-keys.txt':'key-a\n'})
    archive(work/'worker-retired.tar.gz',{'settings.env':"SELF_REPORT_SECRET='retired'\n",'update-keys.txt':'key-a\n'})
    manager=r'''#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"
cd "$2"; WORK="$PWD"; ROOT="$1"; PYTHON="$3"
export PO0_CONF_DIR="$WORK/conf" PO0_MAIN_CONF="$WORK/main.conf"
while read -r part; do part="${part%$'\r'}"; [[ "$part" == *990-* || -z "$part" || "$part" == \#* ]] || source "$ROOT/$part"; done < "$ROOT/tools/po0/manifests/manager.txt"
err() { printf '%s\n' "$*" >&2; }; success() { :; }; info() { :; }
nft() { return 1; }; systemctl() { printf 'unexpected systemctl\n' >&2; return 99; }
mkdir -p "$CONF_DIR" "$BACKUP_DIR"
printf 'NODE_NAME="before"\nENABLE_SRC_ALLOWLIST="0"\nMANAGE_INPUT_FIREWALL="0"\n' > "$SETTINGS_FILE"
printf 'before rules\n' > "$RULES_FILE"; printf 'table ip po0_relay_nat {}\n' > "$NFT_CONF"
printf 'before-key\n' > "$UPDATE_TOKEN_FILE"
for bad in missing protected path link; do
 if do_full_backup_import "$WORK/manager-$bad.tar.gz" > "$WORK/result" 2>&1;then echo "accepted $bad";exit 1;fi
 grep -Fq 'NODE_NAME="before"' "$SETTINGS_FILE"; grep -Fxq before-key "$UPDATE_TOKEN_FILE"
done
PO0_FULL_RESTORE_DRY_RUN=1 do_full_backup_import "$WORK/manager-good.tar.gz" >/dev/null
grep -Fq 'NODE_NAME="before"' "$SETTINGS_FILE"
do_full_backup_import "$WORK/manager-good.tar.gz" >/dev/null
grep -Fq 'NODE_NAME="restored"' "$SETTINGS_FILE"; grep -Fxq paired-key "$UPDATE_TOKEN_FILE"
do_full_backup_export "$WORK/exported.tar.gz" >/dev/null
validate_full_backup_tar_members "$WORK/exported.tar.gz"
ENABLE_SRC_ALLOWLIST=1
if relay_retirement_guard >/dev/null 2>&1;then exit 1;fi
printf 'PASS: manager restore path/type/completeness/protection, dry run and pairing round trip.\n'
'''
    worker=r'''#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"
cd "$2"; WORK="$PWD"; ROOT="$1"; PYTHON="$3"
while read -r part; do part="${part%$'\r'}"; [[ "$part" == *990-* || -z "$part" || "$part" == \#* ]] || source "$ROOT/$part"; done < "$ROOT/tools/po0/manifests/lan-worker.txt"
python3() { "$PYTHON" "$@"; }
CONFIG_FILE="$WORK/targets.tsv"; SETTINGS_FILE="$WORK/settings.env"; UPDATE_KEYS_FILE="$WORK/update-keys.txt"
INSTALL_PATH="$WORK/client.sh"; CADDYFILE_PATH="$WORK/Caddyfile"; printf '# fixture\n' > "$SETTINGS_FILE"
script_source_path() { printf '%s' "$WORK/worker.sh"; }
crontab() { [[ "$1" == -l ]] && return 0; printf unexpected-crontab >&2; return 99; }
printf '1|name|host|user|22|key|extra|a|b|c|paired-legacy|unused\n' > "$CONFIG_FILE"
RESOURCE_TOKEN=paired-shared
persist_update_keys
grep -Fxq paired-shared "$UPDATE_KEYS_FILE";grep -Fxq paired-legacy "$UPDATE_KEYS_FILE"
: > "$UPDATE_KEYS_FILE"
[[ -z "$(manager_update_tokens_env)" ]]
for bad in execute retired;do
 if worker_backup_import "$WORK/worker-$bad.tar.gz" > "$WORK/result" 2>&1;then echo "accepted $bad";exit 1;fi
 grep -Fxq '# fixture' "$SETTINGS_FILE"; [[ ! -e "$WORK/escaped" ]]
done
worker_backup_import "$WORK/worker-good.tar.gz" > /dev/null
[[ "$MANAGER_UPDATE_DOMAIN" == old-host ]]; grep -Fxq key-b "$UPDATE_KEYS_FILE"
worker_backup_export "$WORK/worker-export.tar.gz" > /dev/null
worker_backup_import "$WORK/worker-export.tar.gz" > /dev/null
grep -Fxq key-a "$UPDATE_KEYS_FILE"
printf 'PASS: Worker key migration/clear, safe restore rejection and update backup round trip.\n'
'''
    linux_import=r'''#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"
cd "$2"; WORK="$PWD"; ROOT="$1"; PYTHON="$3"
while read -r part; do part="${part%$'\r'}"; [[ "$part" == *990-* || -z "$part" || "$part" == \#* ]] || source "$ROOT/$part"; done < "$ROOT/tools/po0/manifests/self-report-linux.txt"
python3() { "$PYTHON" "$@"; }
set -Eeuo pipefail
trap 'printf "FAIL: official migration line %s\n" "$LINENO" >&2' ERR
CONFIG_FILE="$WORK/official-settings.env"
XDG_STATE_HOME="$WORK/official-state"
INSTALL_PATH="$WORK/official-client.sh"
config_read_file() { [[ -f "$CONFIG_FILE" ]] && printf '%s' "$CONFIG_FILE"; }
self_report_completed() { :; }
mkdir -p "$WORK/worker-backup"
backup="$WORK/worker-backup"
printf "CONFIG_FILE='/fixture/worker/targets.tsv'\nPO0_FIREWALL_TOKENS='pgnfw_migration_fixture@3'\n" > "$backup/settings.env"
cat > "$backup/crontab" <<'CRON'
# PO0_LAN_CLIENT_BEGIN /another/worker/targets.tsv
*/10 * * * * bash other --run-official-firewall --scheduled-run
# PO0_LAN_CLIENT_END /another/worker/targets.tsv
# PO0_LAN_CLIENT_BEGIN /fixture/worker/targets.tsv
# paused: --run-official-firewall --scheduled-run
# PO0_LAN_CLIENT_END /fixture/worker/targets.tsv
CRON
PO0_FIREWALL_TOKENS=''; OFFICIAL_AUTO_ENABLED=1; OFFICIAL_INTERVAL_SECONDS=900
import_worker_official "$backup" >/dev/null
[[ "$PO0_FIREWALL_TOKENS" == pgnfw_migration_fixture@3 && "$OFFICIAL_AUTO_ENABLED" == 0 && "$OFFICIAL_INTERVAL_SECONDS" == 600 && "$OFFICIAL_NETWORK_ENABLED" == 0 ]]
! grep -Eq '^(WORKER_|SECRET=)' "$CONFIG_FILE"
if activate_imported_worker_official "$backup" >/dev/null 2>&1; then exit 1; fi
cron_managed_block_exists() { return 1; }
install_cron() { printf 'install %s\n' "$1" >> "$WORK/installed"; }
: > "$backup/retired"
activate_imported_worker_official "$backup" >/dev/null
[[ ! -e "$WORK/installed" ]]
# An active owned schedule is transferred only after old Worker retirement.
sed '/^# paused:/c\*/10 * * * * bash old --run-official-firewall --scheduled-run' "$backup/crontab" > "$backup/new-crontab"
mv "$backup/new-crontab" "$backup/crontab"
CONFIG_FILE="$WORK/active-settings.env"; PO0_FIREWALL_TOKENS=''; OFFICIAL_AUTO_ENABLED=1
import_worker_official "$backup" >/dev/null
[[ "$OFFICIAL_AUTO_ENABLED" == 1 ]]
activate_imported_worker_official "$backup" >/dev/null
grep -Fxq 'install official' "$WORK/installed"
# Existing matching accounts retain names, timing and explicit disabled choice.
OFFICIAL_AUTO_ENABLED=0; OFFICIAL_TIMER_ENABLED=0; OFFICIAL_NETWORK_ENABLED=1; OFFICIAL_INTERVAL_SECONDS=1234; PO0_FIREWALL_NAMES='家庭'
import_worker_official "$backup" >/dev/null
[[ "$OFFICIAL_AUTO_ENABLED:$OFFICIAL_TIMER_ENABLED:$OFFICIAL_NETWORK_ENABLED:$OFFICIAL_INTERVAL_SECONDS:$PO0_FIREWALL_NAMES" == '0:0:1:1234:家庭' ]]
PO0_FIREWALL_TOKENS='pgnfw_different@1'
if import_worker_official "$backup" >/dev/null 2>&1; then exit 1; fi
[[ "$PO0_FIREWALL_TOKENS" == pgnfw_different@1 ]]
PO0_FIREWALL_TOKENS=''; OFFICIAL_AUTO_ENABLED=0
if import_worker_official "$backup" >/dev/null 2>&1; then exit 1; fi
[[ -z "$PO0_FIREWALL_TOKENS" ]]
printf "PO0_FIREWALL_TOKENS=\$(touch escaped)\n" > "$backup/settings.env"
if import_worker_official "$backup" >/dev/null 2>&1; then exit 1; fi
[[ ! -e escaped ]]
printf 'PASS: Worker official import preserves owned schedule/disabled state, conflicts and names; no shell execution.\n'
'''
    bash='C:/Program Files/Git/bin/bash.exe' if os.name=='nt' else 'bash'
    for name,code in [('manager',manager),('worker',worker),('linux-import',linux_import)]:
        if len(sys.argv) > 1 and name != sys.argv[1]: continue
        path=work/(name+'.sh');path.write_text(code,'utf-8',newline='\n')
        result=subprocess.run([bash,path.as_posix(),ROOT.as_posix(),work.as_posix(),Path(sys.executable).as_posix()],capture_output=True,text=True,encoding='utf-8')
        if result.returncode:raise RuntimeError(name+': '+result.stdout+result.stderr)
        print(result.stdout.strip())
