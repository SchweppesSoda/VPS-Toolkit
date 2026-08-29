# 3x-ui Node Exporter

Interactive helper for exporting local 3x-ui subscription/node links and raw inbound configuration from a VPS.

The script is intended for machines you manage. It reads the local 3x-ui SQLite database, creates a snapshot, extracts `subId` values, fetches local subscription output, and writes export files with restricted permissions.

## Quick Start

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
