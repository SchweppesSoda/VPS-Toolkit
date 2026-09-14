# 3x-ui Node Exporter

Interactive helper for exporting local 3x-ui subscription/node links and raw inbound configuration from a VPS.

The script is intended for machines you manage. It reads the local 3x-ui SQLite database, creates a snapshot, extracts `subId` values, fetches local subscription output, and writes export files with restricted permissions.

## Quick Start

### Daily SSH subscription collection

[`3x-ui-subscription-exporter.py`](3x-ui-subscription-exporter.py) is the
non-interactive producer for a collector such as Sub-Store infrastructure.
It reads a SQLite snapshot and native subscription responses in memory, then
returns one bounded JSON envelope. It does not install files, packages or tasks
on the VPS. The existing SSH identity and host-key checking are retained.

The initial producer supports VLESS, VMess and Trojan client identities; other
protocols fail closed. A private `clientIds` selection is required. Empty,
incomplete or mismatched native output fails without publishing a partial result.
See the [transport and cleanup contract](SSH_SUBSCRIPTION_DESIGN.md).

### Download directly to Windows over SSH

Run the local helper in **Windows PowerShell 5.1 or PowerShell 7**, using an SSH
config alias or `root@host` and your desired local directory:

```powershell
& 'D:\GitRepo\VPS-Toolkit\scripts\vps\3x-ui\Export-3xUi.ps1' -Server my-vps -OutDir 'D:\Backups\3x-ui'
```

Replace the repository path if your checkout is elsewhere. The helper uses the
adjacent `3x-ui-node-exporter.sh`; keep both files together. With no arguments,
it prompts for the SSH server and local destination. Nothing needs to be
installed in advance on the VPS besides the export dependencies below.

- One SSH connection exports, transfers a ZIP, and cleans remote temporary files.
- Uses your normal OpenSSH config, agent, key or SSH password; with key login,
  no additional export/download confirmation is required.
- Verifies the size and SHA-256 before saving the final ZIP. Interrupted or
  failed downloads remove the local `.partial` file; existing backups are kept.
- Creates the requested directory if needed and prints the full downloaded path.
- Requires root access; `-Sudo` supports accounts with passwordless sudo. Missing
  remote dependencies are reported without installing packages automatically.
- The original 3x-ui database is read through a snapshot and is not modified.

Custom SSH port/key, public node address, and database location:

```powershell
& .\Export-3xUi.ps1 -Server root@203.0.113.10 -Port 2222 -IdentityFile "$HOME\.ssh\id_ed25519" -OutDir 'D:\Backups\3x-ui' -Address nodes.example.com -Database /etc/x-ui/x-ui.db
& .\Export-3xUi.ps1 -Server my-vps -Sudo -RawOnly -OutDir 'D:\Backups\3x-ui'
```

These commands run on your computer, before entering an interactive VPS shell.
The ZIP contains `links.txt` and the other files listed below; it is not
automatically unpacked. Local files inherit the destination directory's Windows
permissions, so choose a private directory. The remote cleanup limitations in
[Safety](#safety) also apply to SSH downloads.

If Windows blocks local scripts, invoke the same command with a process-only
execution policy override (no permanent policy change):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'D:\GitRepo\VPS-Toolkit\scripts\vps\3x-ui\Export-3xUi.ps1' -Server my-vps -OutDir 'D:\Backups\3x-ui'
```

### Export from an interactive VPS shell

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/3x-ui/3x-ui-node-exporter.sh)
```

Pipe mode is also supported:

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/3x-ui/3x-ui-node-exporter.sh | bash
```

## Behavior

- Runs directly as root, or restarts itself with `sudo` when needed.
- Checks for `python3`, `curl`, `base64`, `awk`, `mktemp`, `chmod`, `date`, and other basic commands.
- If dependencies are missing, asks before installing them with the detected package manager.
- Does not depend on `dialog`, `whiptail`, `gum`, or `fzf`.
- Uses Python standard library SQLite support, so the `sqlite3` command is not required.
- Defaults to `/root/3xui-node-export-YYYYMMDD-HHMMSS`.
- Does not print full node links unless you confirm in the menu or pass `--show-links`.
- Provides a self-destruct export mode that keeps the bundle on the VPS for at most 15 minutes and then removes files created by that run.

## Output Files

- `links.txt`: deduplicated node/subscription links.
- `links.raw`: raw subscription responses grouped by `subId`.
- `raw_inbounds.json`: parsed inbound records from the database.
- `subids.txt`: extracted subscription IDs.
- `env.sh`: detected subscription host/port/path.
- `curl-errors.log`: subscription request errors.
- `x-ui.snapshot.db`: SQLite snapshot used for export.

The output directory is set to `700`, and generated files are set to `600`.

## Options

```bash
bash 3x-ui-node-exporter.sh --addr example.com
bash 3x-ui-node-exporter.sh --raw-only
bash 3x-ui-node-exporter.sh --db /etc/x-ui/x-ui.db --out /root/export --yes
bash 3x-ui-node-exporter.sh --show-links
bash 3x-ui-node-exporter.sh --self-destruct
bash 3x-ui-node-exporter.sh --version
```

`--yes` is intended for non-interactive runs. It can confirm dependency installation and run the default export, but it still does not print full node links unless `--show-links` is also provided.

`--self-destruct` can be combined with `--addr`, `--db`, or `--raw-only`. It cannot be combined with `--out`, `--show-links`, or `--yes` because the temporary download window requires an interactive terminal and must not expose links in terminal scrollback.

`--stream` is used by the local SSH download helper. It sends a framed Base64 ZIP
on stdout, sends progress to stderr, and confirms completion only after remote
cleanup. Do not run it directly in an interactive terminal. It supports `--addr`,
`--db`, and `--raw-only`, but rejects `--self-destruct`, `--out`, `--show-links`, and
`--yes`. It requires root and existing dependencies; it does not prompt or install
packages. `Export-3xUi.ps1 -Version` prints the local helper version.

## Self-destruct Export

Run the script after logging in to the VPS and choose `4) 临时导出并自动清理`, or invoke the mode directly without saving the script:

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/3x-ui/3x-ui-node-exporter.sh | bash -s -- --self-destruct
```

The script creates a root-only random session directory, builds one ZIP, deletes the unpacked snapshot and intermediate files, and displays the temporary ZIP path and SHA-256. It then waits for up to 15 minutes.

From another terminal on Linux or macOS, replace the host and path with the values shown by the script:

```bash
scp 'root@VPS_ADDRESS:/tmp/3xui-self-destruct.EXAMPLE/3xui-node-export-YYYYMMDD-HHMMSS.zip' .
```

Verify the downloaded file on Linux:

```bash
sha256sum ./3xui-node-export-YYYYMMDD-HHMMSS.zip
```

Verify it on macOS:

```bash
shasum -a 256 ./3xui-node-export-YYYYMMDD-HHMMSS.zip
```

From Windows PowerShell, download and verify it with:

```powershell
scp 'root@VPS_ADDRESS:/tmp/3xui-self-destruct.EXAMPLE/3xui-node-export-YYYYMMDD-HHMMSS.zip' .
Get-FileHash .\3xui-node-export-YYYYMMDD-HHMMSS.zip -Algorithm SHA256
```

Return to the first VPS terminal and press Enter after the download. The script also cleans the session on timeout, terminal disconnect, `INT`, `TERM`, or normal exit. If the script was launched from an on-disk file, it separately shows that exact file path and accepts `DELETE` to remove only that script file and exit; pressing Enter keeps it. Pipe/process-substitution launches have no script file to remove.

## Safety

The generated files contain UUIDs, passwords, private node parameters, subscription links, and other sensitive values. Do not commit or publish exports.

Self-destruct mode removes only files created by the current export. It does not modify shell history, terminal scrollback, system audit or network logs, filesystem snapshots, or the original 3x-ui database. Dependencies installed after a separate confirmation and their package-manager records are not reverted. Cleanup cannot be guaranteed after `SIGKILL`, a kernel crash, or power loss because the process cannot execute its cleanup handler in those cases. The ZIP is not password-protected; use SSH/SFTP for transfer and protect the downloaded copy.

PostgreSQL-backed 3x-ui deployments are detected only as a missing SQLite database in this version; export support is limited to SQLite.

## Development checks

Version history: [CHANGELOG.md](./CHANGELOG.md).

Planned unattended integration: [SSH subscription export contract](./SSH_SUBSCRIPTION_DESIGN.md)
(design only; its new CLI mode is not yet available).

Run the export/cleanup regression suite with Bash and Python 3:

```bash
bash -n scripts/vps/3x-ui/3x-ui-node-exporter.sh
bash tools/vps/test-3x-ui-node-exporter-self-destruct.sh
```

On Windows, run the native pipe/download regression suite with Windows PowerShell
5.1, Git Bash, and Python 3. It also tests PowerShell 7 when installed:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/vps/test-3x-ui-download.ps1 -PythonPath 'C:\Path\To\python.exe'
```

Both suites use disposable local fixtures; the Windows suite substitutes SSH and
does not connect to a real VPS.
