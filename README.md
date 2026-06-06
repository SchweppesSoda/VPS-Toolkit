# VPS Toolkit

[English](./README.md) | [简体中文](./README.zh-CN.md)

Public scripts and browser tools for VPS maintenance, PO0 relay hosts, nftables forwarding, SSH hardening, Fail2ban, REALITY destination discovery, and proxy-node processing.

## Layout

- `PO0/`
  - `reinstall/`: Debian unattended reinstall tooling.
  - `nftables/`: nftables relay manager, allowlists, DDNS reporting, resource jobs, and offline IP-list builders.
  - `proxy-services/`: PO0 proxy-service enhancement scripts.
- `VPS.sh/`
  - `fail2ban/`: interactive Fail2ban installation and management.
  - `ssh-key-only/`: SSH public-key-only hardening.
  - `reality_dest_finder/`: REALITY fallback-domain discovery.
  - `docs/`: shared VPS operational notes.
- `Tools/`
  - `argosbx-argo-batch/`: local Argosbx Argo batch processor.
  - `proxy-node-manager/`: local proxy-node parser, cleaner, grouper, and exporter.

## Quick Start

```bash
# PO0 nftables relay manager
bash PO0/nftables/nftables-relay-manager.sh

# PO0 LAN collaboration client
bash PO0/nftables/tools/po0-lan-client.sh

# Fail2ban helper
sudo bash VPS.sh/fail2ban/fail2ban.sh

# SSH key-only hardening
sudo bash VPS.sh/ssh-key-only/setup-ssh-key-only-full.sh
```

The HTML tools run locally in a browser and do not require a server.

## Safety

Review scripts before running them. Reinstall, SSH, firewall, nftables, and routing operations can remove remote access or destroy data. Keep a provider console or other recovery channel available.

Do not commit runtime-generated passwords, tokens, private keys, node links, subscriptions, exports, or server-specific configuration.

## License

MIT
