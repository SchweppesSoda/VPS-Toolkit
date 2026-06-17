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

Review scripts before running them. Root-level interactive online examples download to a temporary file before running so menu prompts still read from your terminal. The PO0 Debian reinstall script is intentionally not documented as a raw online execution command.

### PO0 nftables relay manager

Recommended: upload the manager first, then run it on PO0.

```bash
scp scripts/po0/nftables/nftables-relay-manager.sh root@<PO0_HOST>:/root/nftables-relay-manager.sh
ssh root@<PO0_HOST> 'chmod +x /root/nftables-relay-manager.sh && bash /root/nftables-relay-manager.sh'
```

Check the installed manager version on PO0:

```bash
ssh root@<PO0_HOST> 'bash /root/nftables-relay-manager.sh --version'
```

If the PO0 host can reach `raw.githubusercontent.com`, you can run it directly:

```bash
tmp="$(mktemp)" &&
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/nftables-relay-manager.sh -o "$tmp" &&
sudo bash "$tmp"
rm -f "$tmp"
```

### PO0 proxy-service enhancer

Run on the PO0 host to deploy the argosbx/Xray sidecar for VLESS RAW ENC and Shadowsocks 2022:

Recommended persistent command install:

```bash
tmp="$(mktemp)"
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer.sh -o "$tmp"
sudo install -m 0755 "$tmp" /usr/local/sbin/vless-raw-enc-argosbx-enhancer
rm -f "$tmp"
sudo /usr/local/sbin/vless-raw-enc-argosbx-enhancer
```

Later runs:

```bash
sudo /usr/local/sbin/vless-raw-enc-argosbx-enhancer
```

One-shot run without installing the command:

```bash
tmp="$(mktemp)" &&
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer.sh -o "$tmp" &&
sudo bash "$tmp"
rm -f "$tmp"
```

### PO0 Debian reinstall

No raw online execution command is provided for this destructive reinstall script. Recommended: upload the reinstall script first, then run it on PO0.

```bash
scp scripts/po0/reinstall/po0-debian-reinstall.sh root@<PO0_HOST>:/root/po0-debian-reinstall.sh
ssh root@<PO0_HOST> 'chmod +x /root/po0-debian-reinstall.sh && bash /root/po0-debian-reinstall.sh'
ssh root@<PO0_HOST> 'bash /root/po0-debian-reinstall.sh -port 60022'
```

### PO0 LAN Worker

Recommended interactive setup on the LAN Worker host. The wizard can fetch tokens over key-based SSH to PO0, write local config, and install the local `po0-lan-client` command. One wizard run configures one PO0 target.

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/lan-worker/po0-lan-client.sh | bash
po0-lan-client --menu
po0-lan-client --run
```

Check the installed LAN Worker client version:

```bash
po0-lan-client --version
```

If an older install did not create `po0-lan-client`, install the command manually:

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/lan-worker/po0-lan-client.sh -o /usr/local/sbin/po0-lan-client
chmod 755 /usr/local/sbin/po0-lan-client
/usr/local/sbin/po0-lan-client --menu
```

DDNS resolver + `iplist/ipdb` resource task polling:

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/lan-worker/po0-lan-client.sh | bash -s -- --bootstrap --po0-host <PO0_HOST> --source-key <DDNS_SOURCE_KEY> --ddns-domain <DDNS_DOMAIN> --token <DDNS_TOKEN> --resource-token <RESOURCE_TOKEN> --install-cron 5
```

Only poll and claim PO0-created resource tasks:

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/lan-worker/po0-lan-client.sh | bash -s -- --bootstrap --po0-host <PO0_HOST> --resource-token <RESOURCE_TOKEN> --install-cron 5
```

Self-report receiver on the LAN Worker:

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/lan-worker/po0-lan-client.sh | bash -s -- --install-self
po0-lan-client --self-report-server --self-report-listen 127.0.0.1:8788 --po0-host <PO0_HOST> --client-ip-token <CLIENT_REPORT_TOKEN> --self-report-secret <SELF_REPORT_SECRET>
```

### Self-report clients

Linux/OpenWrt access-device client:

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/self-report/po0-outbound-ip-report.sh | bash -s -- --worker-url <LAN_WORKER_REPORT_URL> --source-id <CLIENT_ID> --secret <SELF_REPORT_SECRET> --install-cron 5
```

Windows access-device client:

```powershell
$env:PO0_LAN_WORKER_URL='<LAN_WORKER_REPORT_URL>'; $env:PO0_SELF_REPORT_SOURCE='<CLIENT_ID>'; $env:PO0_SELF_REPORT_SECRET='<SELF_REPORT_SECRET>'; $env:INSTALL_TASK='1'; $env:MINUTES='5'; irm -UseBasicParsing 'https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/self-report/po0-outbound-ip-report.ps1' | iex
```

### Egern SSH report module

Import this raw URL in Egern:

```text
https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/egern/PO0-SSH-IP-Report.yaml
```

### Fail2ban helper

```bash
tmp="$(mktemp)" &&
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/fail2ban/fail2ban.sh -o "$tmp" &&
sudo bash "$tmp" default
rm -f "$tmp"
```

### 3x-ui node exporter

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/3x-ui/3x-ui-node-exporter.sh)
```

### ForwardX NAT VPS agent adapter

```bash
tmp="$(mktemp)" &&
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/forwardx/forwardx-nat-agent-adapter.sh -o "$tmp" &&
sudo bash "$tmp" install --public-port 54999 --internal-port 81 --proto both
rm -f "$tmp"
```

### SSH key-only hardening

Menu-driven SSH hardening: status check, key-only update, or full port/key hardening.

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/ssh-key-only/setup-ssh-key-only-full.sh | sudo env SSH_CONNECTION="$SSH_CONNECTION" bash
```

Advanced automation still supports `--port`, `--add-key`, and `--replace-key`:

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/ssh-key-only/setup-ssh-key-only-full.sh | sudo env SSH_CONNECTION="$SSH_CONNECTION" bash -s -- --port 55022 --add-key
```

### REALITY destination finder

Install dependencies first, then run the finder:

```bash
sudo apt update
sudo apt install -y nmap jq dnsutils openssl curl bc
bash <(curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/reality_dest_finder/reality_dest_finder.sh)
```

Single-domain deep check:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/reality_dest_finder/reality_dest_finder.sh) --check <DOMAIN>
```

### iplist offline package builder

Bash builder:

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/tools/build-iplist-package.sh | bash -s -- "${HOME}/Desktop/iplist.tar.gz" 16
```

PowerShell builder:

```powershell
$script = irm -UseBasicParsing 'https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/tools/build-iplist-package.ps1'
& ([scriptblock]::Create($script)) -OutFile "$env:USERPROFILE\Desktop\iplist.tar.gz" -ThrottleLimit 16
```

`scripts/po0/nftables/nftables-legacy.sh` is kept for compatibility with older setups and is not the recommended new entry point.

For local development, run the same scripts from the checked-out `scripts/` tree.

Open `web/index.html`, `web/vps-toolkit/index.html`, or the files under `web/vps-toolkit/tools/` directly in a browser while developing. They do not require a server.

## Safety

Review scripts before running them. Reinstall, SSH, firewall, nftables, and routing operations can remove remote access or destroy data. Keep a provider console or other recovery channel available.

Do not commit runtime-generated passwords, tokens, deploy keys, private keys, node links, subscriptions, exports, or server-specific configuration.

## License

MIT
