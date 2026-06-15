# 3x-ui Node Exporter

Interactive helper for exporting local 3x-ui subscription/node links and raw inbound configuration from a VPS.

The script is intended for machines you manage. It reads the local 3x-ui SQLite database, creates a snapshot, extracts `subId` values, fetches local subscription output, and writes export files with restricted permissions.

## Quick Start

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/VPS.sh/3x-ui/3x-ui-node-exporter.sh)
```

Pipe mode is also supported:

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/VPS.sh/3x-ui/3x-ui-node-exporter.sh | bash
```

## Behavior

- Runs directly as root, or restarts itself with `sudo` when needed.
- Checks for `python3`, `curl`, `base64`, `awk`, `mktemp`, `chmod`, `date`, and other basic commands.
- If dependencies are missing, asks before installing them with the detected package manager.
- Does not depend on `dialog`, `whiptail`, `gum`, or `fzf`.
- Uses Python standard library SQLite support, so the `sqlite3` command is not required.
- Defaults to `/root/3xui-node-export-YYYYMMDD-HHMMSS`.
- Does not print full node links unless you confirm in the menu or pass `--show-links`.

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
```

`--yes` is intended for non-interactive runs. It can confirm dependency installation and run the default export, but it still does not print full node links unless `--show-links` is also provided.

## Safety

The generated files contain UUIDs, passwords, private node parameters, subscription links, and other sensitive values. Do not commit or publish exports.

PostgreSQL-backed 3x-ui deployments are detected only as a missing SQLite database in this version; export support is limited to SQLite.
