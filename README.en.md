# VPS Toolkit

[简体中文](./README.md) | English

This repository contains VPS maintenance scripts and PO0 relay tooling. Operational scripts live under `scripts/`; static browser tools moved to [`SchweppesSoda/vps-toolkit-web`](https://github.com/SchweppesSoda/vps-toolkit-web).

## Project Entry Points

| Use case | Start here | Maintenance status |
| --- | --- | --- |
| PO0 forwarding, LAN update mirror and seven official reporting clients | [`scripts/po0/relay/README.md`](./scripts/po0/relay/README.md) | Core functionality, actively maintained |
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
| [`scripts/po0/relay/README.md`](./scripts/po0/relay/README.md) | PO0 forwarding, LAN update mirror, and seven official reporting clients. |
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

- `scripts/po0/`: PO0 reinstall, forwarding, LAN update mirror, official reporting, and proxy-service enhancement.
- `scripts/vps/`: general VPS tools and inventory-driven proxy-stack deployment, adoption, and configuration-driven rebuild; each tool directory owns its user documentation.
- `tools/po0/`: offline builds, manifests, and checks for PO0 Release assets.
- `tools/vps/`: offline focused checks for general VPS modules.
- Browser tools: source and GitHub Pages deployment live in [`vps-toolkit-web`](https://github.com/SchweppesSoda/vps-toolkit-web).

## PO0 Release Architecture and Boundaries

PO0 now contains a forwarding manager, a LAN update mirror, Linux/macOS/Windows official reporters, the official OpenWrt APK, and Egern/Stash/Loon modules. The self-hosted firewall, receivers, DDNS/WebAuth, learning and resource jobs have retired. Complete old assets are frozen in the non-Latest `archive/po0-full-20260907.1` Release.

PO0 still obtains manager updates over LAN HTTP with nonce/HMAC verification. Official reporters preserve GET-first behavior, tokens, slots, names, timers, disabled choices and their existing routing. Migration saves local backups first. See the [PO0 guide](scripts/po0/relay/README.md) for migration and archive restoration.

## Releases and Downloads

PO0 releases are published through [GitHub Releases](https://github.com/SchweppesSoda/VPS-Toolkit/releases); full releases contain the following assets; scripts and APKs can also be published separately:

- `nftables-relay-manager.sh`
- `po0-lan-client.sh`
- `po0-outbound-ip-report.sh`
- `po0-outbound-ip-report-macos.sh`
- `po0-outbound-ip-report.ps1`
- `po0-outbound-ip-report.apk`
- `checksums.txt`

Scripts and APKs can be released separately; see the [release scope guide](scripts/po0/relay/README.md#选择发布范围). Scripts use Latest, while APK downloads use their own versioned release URLs. Legacy raw executable entry points are disabled. Egern, Stash, Loon, and independent tools not included in the Release continue to use the allowed raw paths documented by their own guides.

This repository no longer publishes GitHub Pages. Do not enable Pages from the repository root.

## Safety

Reinstall, SSH, firewall, nftables, and routing operations can cause data loss or remove remote access. Review scripts before execution and keep a provider console or another recovery channel available.

Do not commit runtime passwords, tokens, deploy keys, private keys, node links, subscriptions, exports, or server-specific configuration.

## License

MIT

## Cross-repository maintenance and local output

- This repository maintains operational source on `main`; see [AGENTS.md](./AGENTS.md) for commit and release rules. `tools/po0/` generates PO0 assets for the existing release gates. Documentation cleanup does not require another script release.
- [proxy-gateway-plus](https://github.com/SchweppesSoda/proxy-gateway-plus) owns the gateway implementation; `scripts/vps/proxy-stack/` orchestrates it without copying its business logic.
- [CustomRules](https://github.com/SchweppesSoda/CustomRules) owns public rules and general client modules. PO0 official modules remain here. [proxy-vps-skills](https://github.com/SchweppesSoda/proxy-vps-skills) owns configuration maintenance workflows and audits.
- [vps-toolkit-web](https://github.com/SchweppesSoda/vps-toolkit-web) owns static tools and Pages. Device configuration, deployment records and recovery material stay in their private repositories.
- `.tmp/` holds build, test and download output. Verify provenance and checksums before archiving; keep field backups and durable recovery material outside the repository. Historical compatibility filenames do not mean retired features are supported.

- Task-specific agent contracts — [PO0 runtime / clients](docs/agent-maintenance/po0-runtime.md)

- Task-specific agent contracts — [PO0 build / release](docs/agent-maintenance/po0-release.md)

- Task-specific agent contracts — [Script development / validation](docs/agent-maintenance/script-development.md)
