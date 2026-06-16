# VPS Toolkit

[English](./README.md) | [简体中文](./README.zh-CN.md)

Source repository for VPS maintenance scripts, PO0 relay tooling, and static browser tools. Operational scripts live under `scripts/`; the public website source lives under `web/` and is synced to a separate Pages repository.

## Layout

- `scripts/po0/`
  - `reinstall/`: Debian unattended reinstall tooling.
  - `nftables/`: nftables relay manager, allowlists, outbound IPv4 reporting, resource jobs, and offline IP-list builders.
  - `proxy-services/`: PO0 proxy-service enhancement scripts.
- `scripts/vps/`
  - `3x-ui/`: interactive 3x-ui node/subscription exporter.
  - `forwardx/`: ForwardX NAT VPS agent adapter for Alpine/BusyBox hosts.
  - `fail2ban/`: interactive Fail2ban installation and management.
  - `ssh-key-only/`: SSH public-key-only hardening.
  - `reality_dest_finder/`: REALITY fallback-domain discovery.
  - `docs/`: shared VPS operational notes.
- `web/`
  - `index.html`: account-level project index.
  - `vps-toolkit/`: VPS Toolkit public site source.
  - `vps-toolkit/tools/proxy-node-manager/`: browser-based proxy-node parser, cleaner, grouper, and exporter.
  - `vps-toolkit/tools/argosbx-argo-batch/`: browser-based Argosbx Argo batch processor.

## Public Website

The public site is intended to be served from `SchweppesSoda/SchweppesSoda.github.io`, not from this repository root:

- `https://schweppessoda.github.io/`
- `https://schweppessoda.github.io/vps-toolkit/`
- `https://schweppessoda.github.io/vps-toolkit/tools/proxy-node-manager/proxy_node_manager.html`
- `https://schweppessoda.github.io/vps-toolkit/tools/argosbx-argo-batch/argosbx_argo_batch.html`

GitHub Actions syncs the root project index and `web/vps-toolkit/` to the Pages repository when `web/**` changes on `main`. The source repository must store the private deploy key as `PAGES_DEPLOY_KEY`; the target Pages repository must have the matching public key added as a write-enabled deploy key.

Do not enable GitHub Pages from this repository root. That would publish scripts and documentation as static files.

## Quick Start

```bash
# PO0 nftables relay manager: interactive, no persistence
bash <(curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/nftables-relay-manager.sh)

# PO0 nftables relay manager: GitHub raw acceleration for PO0 hosts that cannot reach GitHub
PO0_RAW_BASE_URL='https://gh-proxy.com/https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main' bash -c 'curl -fsSL "$PO0_RAW_BASE_URL/scripts/po0/nftables/nftables-relay-manager.sh" | bash'

# PO0 nftables relay manager: persist to the legacy-compatible path
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/nftables-relay-manager.sh -o /root/nftables-relay-manager.sh
chmod +x /root/nftables-relay-manager.sh
bash /root/nftables-relay-manager.sh

# PO0 nftables relay manager: accelerated persist command
PO0_RAW_BASE_URL='https://gh-proxy.com/https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main' bash -c 'curl -fsSL "$PO0_RAW_BASE_URL/scripts/po0/nftables/nftables-relay-manager.sh" -o /root/nftables-relay-manager.sh && chmod +x /root/nftables-relay-manager.sh && bash /root/nftables-relay-manager.sh'

# If gh-proxy.com is unavailable, replace PO0_RAW_BASE_URL with another GitHub raw proxy base.

# PO0 LAN Worker: DDNS resolver + iplist/ipdb resource polling
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/tools/po0-lan-client.sh | bash -s -- --bootstrap --po0-host <PO0_HOST> --source-key <DDNS_SOURCE_KEY> --ddns-domain <DDNS_DOMAIN> --token <DDNS_TOKEN> --resource-token <RESOURCE_TOKEN> --install-cron 5

# PO0 LAN Worker: resource polling only
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/tools/po0-lan-client.sh | bash -s -- --bootstrap --po0-host <PO0_HOST> --resource-token <RESOURCE_TOKEN> --install-cron 5

# PO0 LAN Worker: self-report receiver, HTTP runs only on the LAN Worker
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/tools/po0-lan-client.sh | bash -s -- --install-self
po0-lan-client --self-report-server --self-report-listen 127.0.0.1:8788 --po0-host <PO0_HOST> --client-ip-token <CLIENT_REPORT_TOKEN> --self-report-secret <SELF_REPORT_SECRET>

# Linux/OpenWrt self-report client: report current outbound IPv4 to LAN Worker
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/tools/po0-outbound-ip-report.sh | bash -s -- --worker-url <LAN_WORKER_REPORT_URL> --source-id <CLIENT_ID> --secret <SELF_REPORT_SECRET> --install-cron 5

# Fail2ban helper
sudo bash scripts/vps/fail2ban/fail2ban.sh

# 3x-ui node exporter
bash <(curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/3x-ui/3x-ui-node-exporter.sh)

# ForwardX NAT VPS agent adapter
bash scripts/vps/forwardx/forwardx-nat-agent-adapter.sh install --public-port 54999 --internal-port 81 --proto both

# SSH key-only hardening
sudo bash scripts/vps/ssh-key-only/setup-ssh-key-only-full.sh
```

Windows self-report client:

```powershell
$env:PO0_LAN_WORKER_URL='<LAN_WORKER_REPORT_URL>'; $env:PO0_SELF_REPORT_SOURCE='<CLIENT_ID>'; $env:PO0_SELF_REPORT_SECRET='<SELF_REPORT_SECRET>'; $env:INSTALL_TASK='1'; $env:MINUTES='5'; irm -UseBasicParsing 'https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/tools/po0-outbound-ip-report.ps1' | iex
```

For local development, run the same scripts from the checked-out `scripts/` tree.

Open `web/index.html`, `web/vps-toolkit/index.html`, or the files under `web/vps-toolkit/tools/` directly in a browser while developing. They do not require a server.

## Safety

Review scripts before running them. Reinstall, SSH, firewall, nftables, and routing operations can remove remote access or destroy data. Keep a provider console or other recovery channel available.

Do not commit runtime-generated passwords, tokens, deploy keys, private keys, node links, subscriptions, exports, or server-specific configuration.

## License

MIT
