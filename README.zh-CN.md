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

检查 PO0 上已安装的主控脚本版本：

```bash
ssh root@<PO0_HOST> 'bash /root/nftables-relay-manager.sh --version'
```

PO0 主控和 LAN Worker 脚本统一使用 `YYYY.MM.DD+build.N` 混合版本格式；同一天再次发布时递增 `build.N`，例如 `2026.06.18+build.2`。

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

这个脚本会重装系统盘，不写 raw 在线执行命令。推荐先上传重装脚本，再在 PO0 上运行：

```bash
scp scripts/po0/reinstall/po0-debian-reinstall.sh root@<PO0_HOST>:/root/po0-debian-reinstall.sh
ssh root@<PO0_HOST> 'chmod +x /root/po0-debian-reinstall.sh && bash /root/po0-debian-reinstall.sh'
ssh root@<PO0_HOST> 'bash /root/po0-debian-reinstall.sh -port 60022'
```

### PO0 内网 Worker 与客户端

LAN Worker、DDNS 上报、PO0 已创建资源任务领取、Self-report 和 WebAuth 推荐先在 LAN Worker 机器上进入交互向导：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/lan-worker/po0-lan-client.sh | bash
po0-lan-client --menu
```

LAN Worker、Self-report、WebAuth、Egern 和 iplist 离线包的详细用法集中维护在 [`scripts/po0/nftables/README.md`](./scripts/po0/nftables/README.md)。Egern 专属配置另见 [`clients/egern/README.md`](./scripts/po0/nftables/clients/egern/README.md)。

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

构建脚本位于 `scripts/po0/nftables/tools/`。使用方式和导入行为集中维护在 [`scripts/po0/nftables/README.md`](./scripts/po0/nftables/README.md)，实现细节见 [`nftables-relay-manager-technical.md`](./scripts/po0/nftables/nftables-relay-manager-technical.md)。

`scripts/po0/nftables/nftables-legacy.sh` 只保留给旧配置兼容，不作为新部署推荐入口。

本地开发时，可以继续从已 checkout 的 `scripts/` 目录直接运行脚本。

开发时可以直接在本地浏览器打开 `web/index.html`、`web/vps-toolkit/index.html` 或 `web/vps-toolkit/tools/` 下的 HTML 文件，不需要部署服务器。

## 安全说明

执行前必须检查脚本。重装、SSH、防火墙、nftables 和路由操作可能导致数据丢失或远程连接中断，应提前准备服务商控制台或其它恢复通道。

不要提交运行时生成的密码、Token、deploy key、私钥、节点链接、订阅、导出文件或服务器专用配置。

## 许可证

MIT
