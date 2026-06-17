# VPS Toolkit

[English](./README.md) | [简体中文](./README.zh-CN.md)

这是 VPS 维护脚本、PO0 中转工具和静态网页工具的源码仓库。运维脚本放在 `scripts/`，公开网站源码放在 `web/`，并同步到单独的 Pages 仓库发布。

## 目录结构

- `scripts/po0/`
  - `reinstall/`：Debian 无人值守重装工具。
  - `nftables/`：nftables 中转管理、白名单、出口 IPv4 上报、内网资源任务和离线 IP 列表构建工具。
  - `proxy-services/`：PO0 代理服务增强脚本。
- `scripts/vps/`
  - `3x-ui/`：交互式 3x-ui 节点/订阅导出工具。
  - `forwardx/`：ForwardX NAT VPS 被控机适配器，优先支持 Alpine/BusyBox。
  - `fail2ban/`：Fail2ban 安装与管理。
  - `ssh-key-only/`：SSH 仅公钥登录加固。
  - `reality_dest_finder/`：REALITY 回落域名检测。
  - `docs/`：通用 VPS 运维笔记。
- `web/`
  - `index.html`：账号根主页项目索引。
  - `vps-toolkit/`：VPS Toolkit 公开站点源码。
  - `vps-toolkit/tools/proxy-node-manager/`：浏览器版代理节点解析、清洗、分组和导出工具。
  - `vps-toolkit/tools/argosbx-argo-batch/`：浏览器版 Argosbx Argo 批量处理工具。

## 公开网站

公开站点应由 `SchweppesSoda/SchweppesSoda.github.io` 仓库发布，不从本仓库根目录发布：

- `https://schweppessoda.github.io/`
- `https://schweppessoda.github.io/vps-toolkit/`
- `https://schweppessoda.github.io/vps-toolkit/tools/proxy-node-manager/proxy_node_manager.html`
- `https://schweppessoda.github.io/vps-toolkit/tools/argosbx-argo-batch/argosbx_argo_batch.html`

GitHub Actions 会在 `main` 分支的 `web/**` 变化后，把根主页索引和 `web/vps-toolkit/` 同步到 Pages 仓库。源仓库需要把 deploy key 私钥保存为 `PAGES_DEPLOY_KEY`；目标 Pages 仓库需要添加对应公钥，并开启写权限。

不要从本仓库根目录启用 GitHub Pages，否则脚本和文档也会作为静态文件发布。

## 快速使用

执行前先检查脚本内容。需要 root 且可能交互的在线示例会先下载到临时文件再运行，这样菜单输入仍然来自终端。PO0 Debian 重装脚本故意不提供 raw 在线执行命令。

### PO0 nftables 中转管理器

推荐先上传主控脚本，再在 PO0 上运行：

```bash
scp scripts/po0/nftables/nftables-relay-manager.sh root@<PO0_HOST>:/root/nftables-relay-manager.sh
ssh root@<PO0_HOST> 'chmod +x /root/nftables-relay-manager.sh && bash /root/nftables-relay-manager.sh'
```

如果 PO0 可以访问 `raw.githubusercontent.com`，也可以直接在线拉取运行：

```bash
tmp="$(mktemp)" &&
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/nftables-relay-manager.sh -o "$tmp" &&
sudo bash "$tmp"
rm -f "$tmp"
```

### PO0 代理服务增强

在 PO0 主机上执行，用于部署 argosbx/Xray sidecar，支持 VLESS RAW ENC 和 Shadowsocks 2022：

推荐永久安装命令入口：

```bash
tmp="$(mktemp)"
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer.sh -o "$tmp"
sudo install -m 0755 "$tmp" /usr/local/sbin/vless-raw-enc-argosbx-enhancer
rm -f "$tmp"
sudo /usr/local/sbin/vless-raw-enc-argosbx-enhancer
```

以后直接运行：

```bash
sudo /usr/local/sbin/vless-raw-enc-argosbx-enhancer
```

只临时运行、不安装命令入口：

```bash
tmp="$(mktemp)" &&
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer.sh -o "$tmp" &&
sudo bash "$tmp"
rm -f "$tmp"
```

### PO0 Debian 重装

这个脚本会重装系统盘，不写 raw 在线执行命令。只从已 checkout 的仓库里运行：

```bash
cd scripts/po0/reinstall
sudo bash po0-debian-reinstall.sh
sudo bash po0-debian-reinstall.sh -port 60022
```

### PO0 内网 Worker

推荐在 LAN Worker 机器上用交互向导安装。向导可通过密钥 SSH 自动从 PO0 读取 token，写入本机配置，并安装本机 `po0-lan-client` 命令。每次向导初始化一个 PO0 目标。

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/lan-worker/po0-lan-client.sh | bash
po0-lan-client --menu
po0-lan-client --run
```

如果旧版本安装后没有 `po0-lan-client` 命令，可手动补装：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/lan-worker/po0-lan-client.sh -o /usr/local/sbin/po0-lan-client
chmod 755 /usr/local/sbin/po0-lan-client
/usr/local/sbin/po0-lan-client --menu
```

DDNS 解析上报 + `iplist/ipdb` 资源轮询领取：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/lan-worker/po0-lan-client.sh | bash -s -- --bootstrap --po0-host <PO0_HOST> --source-key <DDNS_SOURCE_KEY> --ddns-domain <DDNS_DOMAIN> --token <DDNS_TOKEN> --resource-token <RESOURCE_TOKEN> --install-cron 5
```

只做 PO0 已创建资源任务的轮询领取：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/lan-worker/po0-lan-client.sh | bash -s -- --bootstrap --po0-host <PO0_HOST> --resource-token <RESOURCE_TOKEN> --install-cron 5
```

在 LAN Worker 上启动自上报接收端：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/lan-worker/po0-lan-client.sh | bash -s -- --install-self
po0-lan-client --self-report-server --self-report-listen 127.0.0.1:8788 --po0-host <PO0_HOST> --client-ip-token <CLIENT_REPORT_TOKEN> --self-report-secret <SELF_REPORT_SECRET>
```

### 自上报客户端

Linux/OpenWrt 访问设备自上报：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/self-report/po0-outbound-ip-report.sh | bash -s -- --worker-url <LAN_WORKER_REPORT_URL> --source-id <CLIENT_ID> --secret <SELF_REPORT_SECRET> --install-cron 5
```

Windows 访问设备自上报：

```powershell
$env:PO0_LAN_WORKER_URL='<LAN_WORKER_REPORT_URL>'; $env:PO0_SELF_REPORT_SOURCE='<CLIENT_ID>'; $env:PO0_SELF_REPORT_SECRET='<SELF_REPORT_SECRET>'; $env:INSTALL_TASK='1'; $env:MINUTES='5'; irm -UseBasicParsing 'https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/self-report/po0-outbound-ip-report.ps1' | iex
```

### Egern SSH report 模块

在 Egern 内导入这个 raw URL：

```text
https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/egern/PO0-SSH-IP-Report.yaml
```

### Fail2ban 管理

```bash
tmp="$(mktemp)" &&
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/fail2ban/fail2ban.sh -o "$tmp" &&
sudo bash "$tmp" default
rm -f "$tmp"
```

### 3x-ui 节点导出

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/3x-ui/3x-ui-node-exporter.sh)
```

### ForwardX NAT VPS 被控机适配

```bash
tmp="$(mktemp)" &&
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/forwardx/forwardx-nat-agent-adapter.sh -o "$tmp" &&
sudo bash "$tmp" install --public-port 54999 --internal-port 81 --proto both
rm -f "$tmp"
```

### SSH 仅公钥登录加固

菜单式 SSH 加固：查看状态、只更新公钥，或执行完整换端口加固。

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/ssh-key-only/setup-ssh-key-only-full.sh | sudo env SSH_CONNECTION="$SSH_CONNECTION" bash
```

高级自动化仍支持 `--port`、`--add-key`、`--replace-key`：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/ssh-key-only/setup-ssh-key-only-full.sh | sudo env SSH_CONNECTION="$SSH_CONNECTION" bash -s -- --port 55022 --add-key
```

### REALITY 回落域名查找

先安装依赖，再运行检测：

```bash
sudo apt update
sudo apt install -y nmap jq dnsutils openssl curl bc
bash <(curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/reality_dest_finder/reality_dest_finder.sh)
```

单域名深度检测：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/reality_dest_finder/reality_dest_finder.sh) --check <DOMAIN>
```

### iplist 离线包构建

Bash 版：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/tools/build-iplist-package.sh | bash -s -- "${HOME}/Desktop/iplist.tar.gz" 16
```

PowerShell 版：

```powershell
$script = irm -UseBasicParsing 'https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/tools/build-iplist-package.ps1'
& ([scriptblock]::Create($script)) -OutFile "$env:USERPROFILE\Desktop\iplist.tar.gz" -ThrottleLimit 16
```

`scripts/po0/nftables/nftables-legacy.sh` 只保留给旧配置兼容，不作为新部署推荐入口。

本地开发时，可以继续从已 checkout 的 `scripts/` 目录直接运行脚本。

开发时可以直接在本地浏览器打开 `web/index.html`、`web/vps-toolkit/index.html` 或 `web/vps-toolkit/tools/` 下的 HTML 文件，不需要部署服务器。

## 安全说明

执行前必须检查脚本。重装、SSH、防火墙、nftables 和路由操作可能导致数据丢失或远程连接中断，应提前准备服务商控制台或其它恢复通道。

不要提交运行时生成的密码、Token、deploy key、私钥、节点链接、订阅、导出文件或服务器专用配置。

## 许可证

MIT
