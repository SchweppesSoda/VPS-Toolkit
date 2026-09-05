# VPS Toolkit

[简体中文](./README.md) | English

This repository contains VPS maintenance scripts and PO0 relay tooling. Operational scripts live under `scripts/`; static browser tools moved to [`SchweppesSoda/vps-toolkit-web`](https://github.com/SchweppesSoda/vps-toolkit-web).

## Project Entry Points

| Use case | Start here | Maintenance status |
| --- | --- | --- |
| PO0 nftables relay, source-IP allowlists, LAN Worker, Self-report, WebAuth, Egern, Stash, Loon, or iplist/ipdb | [`scripts/po0/relay/README.md`](./scripts/po0/relay/README.md) | Core functionality, actively maintained |
| PO0 Debian reinstall | [`scripts/po0/reinstall/README.md`](./scripts/po0/reinstall/README.md) | Maintained as needed; reinstalls the system disk |
| PO0 proxy-service sidecar | [`scripts/po0/proxy-services/README.md`](./scripts/po0/proxy-services/README.md) | Maintained as needed |
| VPS proxy-stack deployment, adoption, or configuration-driven rebuild | [`scripts/vps/proxy-stack/README.md`](./scripts/vps/proxy-stack/README.md) | Inventory-driven upper-layer calls to Argosbx, Proxy Gateway Plus, and the sidecar |
| SSH public-key-only hardening | [`scripts/vps/ssh-key-only/README.md`](./scripts/vps/ssh-key-only/README.md) | General VPS tool |
| 3x-ui export or REALITY destination lookup | [3x-ui](./scripts/vps/3x-ui/README.md) / [REALITY finder](./scripts/vps/reality_dest_finder/README.md) | Independent tools, maintained as needed |
| Fail2ban or ForwardX | [Fail2ban](./scripts/vps/fail2ban/README.md) / [ForwardX](./scripts/vps/forwardx/README.md) | Low-frequency use; retained for compatibility, not default deployment paths |
| Browser tools | [Live site](https://schweppessoda.github.io/vps-toolkit-web/) / [`vps-toolkit-web` source](https://github.com/SchweppesSoda/vps-toolkit-web) | Moved out of this repository |
| Repository maintenance with Codex / agents | [`AGENTS.md`](./AGENTS.md) | Read before changing code |

Start from the relevant README for normal use. `*-technical.md` and `*-design.md` files are implementation references, not deployment entry points.

## Document Index

### User Guides

| Document | Purpose |
| --- | --- |
| [`scripts/po0/README.md`](./scripts/po0/README.md) | PO0 subsystem navigation. |
| [`scripts/po0/relay/README.md`](./scripts/po0/relay/README.md) | PO0 nftables Relay, LAN Worker, access-device reporting, and resource jobs. |
| [`scripts/po0/reinstall/README.md`](./scripts/po0/reinstall/README.md) | PO0 Debian reinstall. |
| [`scripts/po0/proxy-services/README.md`](./scripts/po0/proxy-services/README.md) | PO0 proxy-service sidecar. |
| [`scripts/vps/proxy-stack/README.md`](./scripts/vps/proxy-stack/README.md) | Fresh deployment, adoption of an existing host, or configuration-driven rebuild for Argosbx, Proxy Gateway Plus, and the sidecar. |
| [`scripts/vps/ssh-key-only/README.md`](./scripts/vps/ssh-key-only/README.md) | SSH public-key-only hardening. |
| [`scripts/vps/fail2ban/README.md`](./scripts/vps/fail2ban/README.md) | Fail2ban installation and maintenance. |
| [`scripts/vps/3x-ui/README.md`](./scripts/vps/3x-ui/README.md) | 3x-ui node and subscription export. |
| [`scripts/vps/forwardx/README.md`](./scripts/vps/forwardx/README.md) | ForwardX NAT VPS agent adapter. |
| [`scripts/vps/reality_dest_finder/README.md`](./scripts/vps/reality_dest_finder/README.md) | REALITY destination finder. |

### Clients and Focused Guides

| Document | Purpose |
| --- | --- |
| [`scripts/po0/nftables/clients/egern/README.md`](./scripts/po0/nftables/clients/egern/README.md) | Standard Egern path, device IDs, Widget, and multi-PO0 configuration. |
| [`scripts/po0/relay/egern/README.md`](./scripts/po0/relay/egern/README.md) | Historical Egern compatibility-path notes. |
| [`scripts/vps/fail2ban/fail2ban-guide.md`](./scripts/vps/fail2ban/fail2ban-guide.md) | Fail2ban configuration and usage. |
| [`scripts/vps/docs/vps-port-firewall-summary.md`](./scripts/vps/docs/vps-port-firewall-summary.md) | VPS port ranges and firewall conventions. |

### Implementation Maintenance

| Document | Purpose |
| --- | --- |
| [`scripts/po0/relay/CHANGELOG.md`](./scripts/po0/relay/CHANGELOG.md) | PO0 nftables subsystem version history. |
| [`scripts/po0/relay/po0-relay-technical.md`](./scripts/po0/relay/po0-relay-technical.md) | Manager internals, protocols, wrappers, and state model. |
| [`scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer-design.md`](./scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer-design.md) | PO0 proxy-service enhancer design. |
| [`scripts/vps/ssh-key-only/setup-ssh-key-only-full-technical.md`](./scripts/vps/ssh-key-only/setup-ssh-key-only-full-technical.md) | SSH hardening script design. |
| [`AGENTS.md`](./AGENTS.md) | Repository boundaries, maintenance rules, and validation checklist. |
| [`README.md`](./README.md) | Primary Chinese entry point. |

## Minimal Examples

Review scripts before running them. Online scripts that require root privileges and may prompt interactively should be downloaded to a temporary file before execution.

### PO0 manager

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/nftables-relay-manager.sh -o /root/nftables-relay-manager.sh
chmod +x /root/nftables-relay-manager.sh
bash /root/nftables-relay-manager.sh
```

### LAN Worker

```bash
tmp="$(mktemp)"
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-lan-client.sh -o "$tmp"
bash "$tmp"
rm -f "$tmp"
```

Then use:

```bash
po0-lan-client --menu
```

Use each tool's own README for installation, parameters, and removal instructions.

## Repository Layout

- `scripts/po0/`: PO0 reinstall, relay, firewall, client reporting, resource jobs, and proxy-service enhancement.
- `scripts/vps/`: general VPS tools and inventory-driven proxy-stack deployment, adoption, and configuration-driven rebuild; each tool directory owns its user documentation.
- `tools/po0/`: offline builds, manifests, and checks for PO0 Release assets.
- `tools/vps/`: offline focused checks for general VPS modules.
- Browser tools: source and GitHub Pages deployment live in [`vps-toolkit-web`](https://github.com/SchweppesSoda/vps-toolkit-web).

## PO0 Release Architecture and Boundaries

A PO0 release contains six independent scripts: the manager owns PO0 nftables and controlled jobs; the LAN Worker owns LAN jobs and receiver endpoints; the WAN probe only discovers OpenWrt WAN egress; and the Linux/macOS/Windows Outbound IP Report clients run on access devices. Two OpenWrt APKs carry the WAN probe and outbound reporter integrations; their UCI, procd, LuCI, and mwan3 binding are maintained only for OpenWrt and are not imposed on ordinary clients.

The official firewall is an optional, disabled-by-default second lane: GET the current egress, quota, and slot state first, then POST only when the egress is missing or a requested fixed slot does not match. Its fixed 600-second interval is independent of the existing Worker/Self-report schedules and TTLs. A local SSID skip skips both lanes; a forced report bypasses only the local due/SSID guard and never the required GET. Tokens stay in protected configuration and out of logs, arguments, and state. Only the main OpenWrt can use mwan3 to select wan1/wan2; every other endpoint uses its own default egress. Use [`scripts/po0/relay/README.md`](./scripts/po0/relay/README.md) for the user entry points and the technical document for implementation details.

## Releases and Downloads

PO0 releases are published through [GitHub Releases](https://github.com/SchweppesSoda/VPS-Toolkit/releases); the complete asset set is fixed:

- `nftables-relay-manager.sh`
- `po0-lan-client.sh`
- `po0-wan-probe.sh`
- `po0-outbound-ip-report.sh`
- `po0-outbound-ip-report-macos.sh`
- `po0-outbound-ip-report.ps1`
- `po0-wan-probe.apk`
- `po0-outbound-ip-report.apk`
- `checksums.txt`

This release uses script version `2026.09.05+build.1` and tag `po0-v2026.09.05.1`; the outbound APK is `2026.09.05-r1` and the WAN probe APK remains `2026.08.30-r5`. Legacy raw executable entry points are disabled. Egern, Stash, Loon, and independent tools not included in the Release continue to use the allowed raw paths documented by their own guides.

This repository no longer publishes GitHub Pages. Do not enable Pages from the repository root.

## Safety

Reinstall, SSH, firewall, nftables, and routing operations can cause data loss or remove remote access. Review scripts before execution and keep a provider console or another recovery channel available.

Do not commit runtime passwords, tokens, deploy keys, private keys, node links, subscriptions, exports, or server-specific configuration.

## License

MIT
