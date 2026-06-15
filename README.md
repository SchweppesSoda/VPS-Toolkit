# VPS Toolkit

[English](./README.md) | [简体中文](./README.zh-CN.md)

Source repository for VPS maintenance scripts, PO0 relay tooling, and static browser tools. Operational scripts live under `scripts/`; the public website source lives under `web/` and is synced to a separate Pages repository.

## Layout

- `scripts/po0/`
  - `reinstall/`: Debian unattended reinstall tooling.
  - `nftables/`: nftables relay manager, allowlists, DDNS reporting, resource jobs, and offline IP-list builders.
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
# PO0 nftables relay manager
bash scripts/po0/nftables/nftables-relay-manager.sh

# PO0 LAN collaboration client
bash scripts/po0/nftables/tools/po0-lan-client.sh

# Fail2ban helper
sudo bash scripts/vps/fail2ban/fail2ban.sh

# 3x-ui node exporter
bash <(curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/3x-ui/3x-ui-node-exporter.sh)

# ForwardX NAT VPS agent adapter
bash scripts/vps/forwardx/forwardx-nat-agent-adapter.sh install --public-port 54999 --internal-port 81 --proto both

# SSH key-only hardening
sudo bash scripts/vps/ssh-key-only/setup-ssh-key-only-full.sh
```

Open `web/index.html`, `web/vps-toolkit/index.html`, or the files under `web/vps-toolkit/tools/` directly in a browser while developing. They do not require a server.

## Safety

Review scripts before running them. Reinstall, SSH, firewall, nftables, and routing operations can remove remote access or destroy data. Keep a provider console or other recovery channel available.

Do not commit runtime-generated passwords, tokens, deploy keys, private keys, node links, subscriptions, exports, or server-specific configuration.

## License

MIT
