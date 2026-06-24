# VPS Toolkit

[简体中文](./README.md) | English

Source repository for VPS maintenance scripts and PO0 relay tooling. Operational scripts live under `scripts/`; static browser tools moved to [`SchweppesSoda/vps-toolkit-web`](https://github.com/SchweppesSoda/vps-toolkit-web) and are published by that repository's GitHub Pages site.

## Which Doc To Read

For running or maintaining existing behavior, start from README files. Do not start from `*-technical.md` or `*-design.md`; those are implementation references for code changes.

| Goal | Start here | Notes |
| --- | --- | --- |
| Deploy or maintain PO0 nftables relay, source-IP allowlists, LAN Worker, Self-report, WebAuth, Egern, or iplist/ipdb | [`scripts/po0/nftables/README.md`](./scripts/po0/nftables/README.md) | Main user guide for the PO0 relay system. Menus, tokens, TTLs, state files, and timers are documented there. |
| See the PO0 subsystem entry points | [`scripts/po0/README.md`](./scripts/po0/README.md) | PO0-level navigation without duplicating nftables details. |
| Reinstall PO0 Debian | [`scripts/po0/reinstall/README.md`](./scripts/po0/reinstall/README.md) | Destructive disk reinstall; no raw online execution command is documented. |
| Deploy the PO0 proxy-service sidecar | [`scripts/po0/proxy-services/README.md`](./scripts/po0/proxy-services/README.md) | argosbx/Xray sidecar, VLESS RAW ENC, and Shadowsocks 2022. |
| Use general VPS tools | See the “Runbooks” index below | SSH hardening, Fail2ban, 3x-ui export, ForwardX, and REALITY finder each live in their own directory. |
| Use browser tools | See “Public Website” below | The page itself is the user entry point; browser-tool source and technical docs are maintained in `vps-toolkit-web`. |
| Continue maintenance with Codex / agents | [`AGENTS.md`](./AGENTS.md) | Maintenance rules, document ownership, validation checklist, and historical pitfalls. |

## Document Index

### Runbooks

| Doc | Purpose |
| --- | --- |
| [`scripts/po0/README.md`](./scripts/po0/README.md) | PO0 subsystem entry point. |
| [`scripts/po0/nftables/README.md`](./scripts/po0/nftables/README.md) | nftables relay, LAN Worker, Self-report, WebAuth, Egern, resource tasks, and IP data. |
| [`scripts/po0/reinstall/README.md`](./scripts/po0/reinstall/README.md) | PO0 Debian reinstall. |
| [`scripts/po0/proxy-services/README.md`](./scripts/po0/proxy-services/README.md) | PO0 proxy-service sidecar. |
| [`scripts/vps/ssh-key-only/README.md`](./scripts/vps/ssh-key-only/README.md) | SSH public-key-only hardening. |
| [`scripts/vps/fail2ban/README.md`](./scripts/vps/fail2ban/README.md) | Fail2ban installation and management entry point. |
| [`scripts/vps/3x-ui/README.md`](./scripts/vps/3x-ui/README.md) | 3x-ui node/subscription export. |
| [`scripts/vps/forwardx/README.md`](./scripts/vps/forwardx/README.md) | ForwardX NAT VPS agent adapter. |
| [`scripts/vps/reality_dest_finder/README.md`](./scripts/vps/reality_dest_finder/README.md) | REALITY destination finder. |

### Focused Configuration

| Doc | Purpose |
| --- | --- |
| [`scripts/po0/nftables/clients/egern/README.md`](./scripts/po0/nftables/clients/egern/README.md) | Egern outbound IPv4 SSH reporting, device ID, Widget, and multi-PO0 behavior. |
| [`scripts/vps/fail2ban/fail2ban-guide.md`](./scripts/vps/fail2ban/fail2ban-guide.md) | Fail2ban installation, configuration, and usage. |
| [`scripts/vps/docs/vps-port-firewall-summary.md`](./scripts/vps/docs/vps-port-firewall-summary.md) | VPS port ranges and firewall conventions. |

### Implementation Maintenance

| Doc | Purpose |
| --- | --- |
| [`scripts/po0/nftables/CHANGELOG.md`](./scripts/po0/nftables/CHANGELOG.md) | PO0 nftables subsystem version history. |
| [`scripts/po0/nftables/nftables-relay-manager-technical.md`](./scripts/po0/nftables/nftables-relay-manager-technical.md) | nftables manager internals, protocol, wrapper, and state model. |
| [`scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer-design.md`](./scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer-design.md) | PO0 proxy-service enhancer design. |
| [`scripts/vps/ssh-key-only/setup-ssh-key-only-full-technical.md`](./scripts/vps/ssh-key-only/setup-ssh-key-only-full-technical.md) | SSH hardening script technical design. |
| [`vps-toolkit-web/docs/proxy-node-manager/proxy_node_manager_technical.md`](https://github.com/SchweppesSoda/vps-toolkit-web/blob/main/docs/proxy-node-manager/proxy_node_manager_technical.md) | Proxy Node Manager layout, interaction, and validation notes. |
| [`vps-toolkit-web/docs/argosbx-argo-batch/argosbx_argo_batch_technical.md`](https://github.com/SchweppesSoda/vps-toolkit-web/blob/main/docs/argosbx-argo-batch/argosbx_argo_batch_technical.md) | Argosbx Argo Batch layout, interaction, and validation notes. |

### Maintenance Rules

| Doc | Purpose |
| --- | --- |
| [`AGENTS.md`](./AGENTS.md) | Maintenance rules, responsibility boundaries, validation rules, and document ownership for Codex / agents. |
| [`README.md`](./README.md) | Default Chinese entry point. |

## Quick Entry Points

Review scripts before running them. Root-level online examples that need root and may prompt interactively download to a temporary file first so menu input still comes from your terminal.

### PO0 nftables relay

Recommended: upload the manager from this checkout, then run it on PO0.

```bash
scp scripts/po0/nftables/nftables-relay-manager.sh root@<PO0_HOST>:/root/nftables-relay-manager.sh
ssh root@<PO0_HOST> 'chmod +x /root/nftables-relay-manager.sh && bash /root/nftables-relay-manager.sh'
```

### LAN Worker

Run the wizard on the LAN Worker host:

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-lan-client.sh | bash
```

Then use:

```bash
po0-lan-client --menu
```

### SSH key-only hardening

```bash
tmp="$(mktemp)"
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/ssh-key-only/setup-ssh-key-only-full.sh -o "$tmp"
sudo env SSH_CONNECTION="$SSH_CONNECTION" bash "$tmp"
rm -f "$tmp"
```

### PO0 proxy-service sidecar

```bash
tmp="$(mktemp)"
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer.sh -o "$tmp"
sudo install -m 0755 "$tmp" /usr/local/sbin/vless-raw-enc-argosbx-enhancer
rm -f "$tmp"
sudo /usr/local/sbin/vless-raw-enc-argosbx-enhancer
```

### PO0 Debian reinstall

This script reinstalls the system disk. Read [`scripts/po0/reinstall/README.md`](./scripts/po0/reinstall/README.md), then upload and run it:

```bash
scp scripts/po0/reinstall/po0-debian-reinstall.sh root@<PO0_HOST>:/root/po0-debian-reinstall.sh
ssh root@<PO0_HOST> 'chmod +x /root/po0-debian-reinstall.sh && bash /root/po0-debian-reinstall.sh'
```

## Layout

- `scripts/po0/`: PO0 or relay-host reinstall, nftables relay, allowlists, resource jobs, and proxy-service enhancement.
- `scripts/vps/`: general VPS tools; each tool directory owns its README.
- `tools/`: offline build and check tooling; PO0 Release assets are built by `tools/po0/` from modular source under `scripts/po0/nftables/src/`.
- Web tools: source and GitHub Pages deployment moved to [`SchweppesSoda/vps-toolkit-web`](https://github.com/SchweppesSoda/vps-toolkit-web).

## Release Channels

The four executable PO0 nftables scripts are published as GitHub Release assets: `nftables-relay-manager.sh`, `po0-lan-client.sh`, `po0-outbound-ip-report.sh`, and `po0-outbound-ip-report.ps1`. Old `raw.githubusercontent.com` paths are legacy compatibility entry points for already-deployed scripts to migrate to release-aware versions. Egern files, external ipdb/iplist sources, and general VPS tools that are not part of this phase may still keep their documented raw URLs.

## Public Website

The public browser tools are published by [`SchweppesSoda/vps-toolkit-web`](https://github.com/SchweppesSoda/vps-toolkit-web) through GitHub Pages:

- `https://schweppessoda.github.io/vps-toolkit-web/`
- `https://schweppessoda.github.io/vps-toolkit-web/tools/proxy-node-manager/proxy_node_manager.html`
- `https://schweppessoda.github.io/vps-toolkit-web/tools/argosbx-argo-batch/argosbx_argo_batch.html`

The legacy `https://schweppessoda.github.io/vps-toolkit/` path and old tool deep links are static redirects maintained in the `SchweppesSoda.github.io` root Pages repository. This repository no longer syncs web content and no longer needs `PAGES_DEPLOY_KEY`.

Do not enable GitHub Pages from this repository root. That would publish scripts and documentation as static files.

## Safety

Review scripts before running them. Reinstall, SSH, firewall, nftables, and routing operations can remove remote access or destroy data. Keep a provider console or other recovery channel available.

Do not commit runtime-generated passwords, tokens, deploy keys, private keys, node links, subscriptions, exports, or server-specific configuration.

## License

MIT
