# VPS Toolkit

简体中文 | [English](./README.en.md)

这是 VPS 维护脚本和 PO0 中转工具的源码仓库。运维脚本放在 `scripts/`；静态网页工具已迁出到 [`SchweppesSoda/vps-toolkit-web`](https://github.com/SchweppesSoda/vps-toolkit-web) 并由该仓库的 GitHub Pages 发布。

## 先看哪份文档

如果只是运行或维护现有功能，优先看 README，不要从 `*-technical.md` 或 `*-design.md` 开始；那些文档只给改实现时参考。

| 你的目标 | 先看 | 说明 |
| --- | --- | --- |
| 部署或维护 PO0 nftables 中转、源 IP 白名单、LAN Worker、Self-report、WebAuth、Egern、iplist/ipdb | [`scripts/po0/relay/README.md`](./scripts/po0/relay/README.md) | PO0 中转系统的用户主文档，菜单、Token、TTL、状态文件和定时任务以它为准。 |
| 只想确认 PO0 子系统有哪些入口 | [`scripts/po0/README.md`](./scripts/po0/README.md) | PO0 层导航，不复制 nftables 细节。 |
| 重装 PO0 Debian | [`scripts/po0/reinstall/README.md`](./scripts/po0/reinstall/README.md) | 会重装系统盘；不提供 raw 在线执行命令。 |
| 部署 PO0 代理服务增强 sidecar | [`scripts/po0/proxy-services/README.md`](./scripts/po0/proxy-services/README.md) | argosbx/Xray sidecar、VLESS RAW ENC、Shadowsocks 2022。 |
| 管理普通 VPS 工具 | 下面“运行入口”索引 | SSH 加固、Fail2ban、3x-ui 导出、ForwardX、REALITY 查找分别维护在自己的目录。 |
| 使用网页工具 | 本文的“公开网站” | 页面本身就是用户入口；网页工具源码和技术文档在 `vps-toolkit-web` 仓库维护。 |
| 让 Codex / agent 继续维护仓库 | [`AGENTS.md`](./AGENTS.md) | 维护规则、文档归属、验证清单和历史踩坑。 |

## 文档索引

### 运行入口

| 文档 | 用途 |
| --- | --- |
| [`scripts/po0/README.md`](./scripts/po0/README.md) | PO0 子系统入口。 |
| [`scripts/po0/relay/README.md`](./scripts/po0/relay/README.md) | nftables 中转、LAN Worker、Self-report、WebAuth、Egern、资源任务和 IP 数据。 |
| [`scripts/po0/reinstall/README.md`](./scripts/po0/reinstall/README.md) | PO0 Debian 重装。 |
| [`scripts/po0/proxy-services/README.md`](./scripts/po0/proxy-services/README.md) | PO0 代理服务增强 sidecar。 |
| [`scripts/vps/ssh-key-only/README.md`](./scripts/vps/ssh-key-only/README.md) | SSH 仅公钥登录加固。 |
| [`scripts/vps/fail2ban/README.md`](./scripts/vps/fail2ban/README.md) | Fail2ban 安装与管理入口。 |
| [`scripts/vps/3x-ui/README.md`](./scripts/vps/3x-ui/README.md) | 3x-ui 节点/订阅导出。 |
| [`scripts/vps/forwardx/README.md`](./scripts/vps/forwardx/README.md) | ForwardX NAT VPS 被控机适配。 |
| [`scripts/vps/reality_dest_finder/README.md`](./scripts/vps/reality_dest_finder/README.md) | REALITY 回落域名查找。 |

### 专项配置

| 文档 | 用途 |
| --- | --- |
| [`scripts/po0/nftables/clients/egern/README.md`](./scripts/po0/nftables/clients/egern/README.md) | Egern 当前出口 IPv4 SSH 上报、设备 ID、Widget 和多 PO0 配置。 |
| [`scripts/vps/fail2ban/fail2ban-guide.md`](./scripts/vps/fail2ban/fail2ban-guide.md) | Fail2ban 安装、配置和使用说明。 |
| [`scripts/vps/docs/vps-port-firewall-summary.md`](./scripts/vps/docs/vps-port-firewall-summary.md) | VPS 端口段和防火墙约定。 |

### 实现维护

| 文档 | 用途 |
| --- | --- |
| [`scripts/po0/relay/CHANGELOG.md`](./scripts/po0/relay/CHANGELOG.md) | PO0 nftables 子系统版本历史。 |
| [`scripts/po0/relay/po0-relay-technical.md`](./scripts/po0/relay/po0-relay-technical.md) | nftables manager 内部实现、协议、wrapper 和状态模型。 |
| [`scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer-design.md`](./scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer-design.md) | PO0 代理服务增强脚本设计。 |
| [`scripts/vps/ssh-key-only/setup-ssh-key-only-full-technical.md`](./scripts/vps/ssh-key-only/setup-ssh-key-only-full-technical.md) | SSH 加固脚本技术设计。 |
| [`vps-toolkit-web/docs/proxy-node-manager/proxy_node_manager_technical.md`](https://github.com/SchweppesSoda/vps-toolkit-web/blob/main/docs/proxy-node-manager/proxy_node_manager_technical.md) | Proxy Node Manager 页面结构、交互和验证说明。 |
| [`vps-toolkit-web/docs/argosbx-argo-batch/argosbx_argo_batch_technical.md`](https://github.com/SchweppesSoda/vps-toolkit-web/blob/main/docs/argosbx-argo-batch/argosbx_argo_batch_technical.md) | Argosbx Argo Batch 页面结构、交互和验证说明。 |

### 维护规则

| 文档 | 用途 |
| --- | --- |
| [`AGENTS.md`](./AGENTS.md) | 给 Codex / agent 的维护规则、职责边界、验证规则和文档归属表。 |
| [`README.en.md`](./README.en.md) | 英文辅助入口。 |

## 最短入口

执行前先检查脚本内容。需要 root 且可能交互的在线示例优先下载到临时文件再运行，这样菜单输入仍来自终端。

### PO0 nftables 中转

推荐从 GitHub Release asset 下载主控脚本，再在 PO0 上运行：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/nftables-relay-manager.sh -o /root/nftables-relay-manager.sh
chmod +x /root/nftables-relay-manager.sh
bash /root/nftables-relay-manager.sh
```

### LAN Worker

在内网 Worker 机器上进入向导：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-lan-client.sh | bash
```

之后常用：

```bash
po0-lan-client --menu
```

### SSH 仅公钥登录加固

```bash
tmp="$(mktemp)"
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/ssh-key-only/setup-ssh-key-only-full.sh -o "$tmp"
sudo env SSH_CONNECTION="$SSH_CONNECTION" bash "$tmp"
rm -f "$tmp"
```

### PO0 代理服务增强

```bash
tmp="$(mktemp)"
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer.sh -o "$tmp"
sudo install -m 0755 "$tmp" /usr/local/sbin/vless-raw-enc-argosbx-enhancer
rm -f "$tmp"
sudo /usr/local/sbin/vless-raw-enc-argosbx-enhancer
```

### PO0 Debian 重装

这个脚本会重装系统盘。先读 [`scripts/po0/reinstall/README.md`](./scripts/po0/reinstall/README.md)，再上传执行：

```bash
scp scripts/po0/reinstall/po0-debian-reinstall.sh root@<PO0_HOST>:/root/po0-debian-reinstall.sh
ssh root@<PO0_HOST> 'chmod +x /root/po0-debian-reinstall.sh && bash /root/po0-debian-reinstall.sh'
```

## 目录结构

- `scripts/po0/`：PO0 或类似中转机的重装、中转、防火墙、资源任务和代理服务增强。
- `scripts/vps/`：通用 VPS 工具，每个工具目录维护自己的 README。
- `tools/`：离线构建和检查工具；PO0 Release asset 由 `tools/po0/` 按 manifest 从 manager、LAN Worker、Linux/macOS/Windows self-report 五个模块化源码树生成。
- Web 工具：源码和 GitHub Pages 发布已迁出到 [`SchweppesSoda/vps-toolkit-web`](https://github.com/SchweppesSoda/vps-toolkit-web)。

## 发布渠道

PO0 nftables 的五个可执行脚本通过 GitHub Release assets 发布：`nftables-relay-manager.sh`、`po0-lan-client.sh`、`po0-outbound-ip-report.sh`、`po0-outbound-ip-report-macos.sh`、`po0-outbound-ip-report.ps1`。构建顺序和来源以 `tools/po0/manifests/` 为准，覆盖 manager、LAN Worker、Linux/macOS/Windows self-report 五个源码树。

旧 manager、LAN Worker 和 self-report raw URLs are disabled，不再作为兼容入口；Egern canonical raw path、Egern legacy compatibility path、离线 iplist 构建器、外部 ipdb/iplist 数据源和暂未迁移的通用 VPS 工具仍按各自文档保留 raw URL。

## 公开网站

公开网页工具由 [`SchweppesSoda/vps-toolkit-web`](https://github.com/SchweppesSoda/vps-toolkit-web) 仓库的 GitHub Pages 发布：

- `https://schweppessoda.github.io/vps-toolkit-web/`
- `https://schweppessoda.github.io/vps-toolkit-web/tools/proxy-node-manager/proxy_node_manager.html`
- `https://schweppessoda.github.io/vps-toolkit-web/tools/argosbx-argo-batch/argosbx_argo_batch.html`

旧 `https://schweppessoda.github.io/vps-toolkit/` 和旧工具深链接由 `SchweppesSoda.github.io` 根 Pages 仓库保留静态跳转。本仓不再同步网页内容，也不再需要 `PAGES_DEPLOY_KEY`。

不要从本仓库根目录启用 GitHub Pages，否则脚本和文档也会作为静态文件发布。

## 安全说明

执行前必须检查脚本。重装、SSH、防火墙、nftables 和路由操作可能导致数据丢失或远程连接中断，应提前准备服务商控制台或其它恢复通道。

不要提交运行时生成的密码、Token、deploy key、私钥、节点链接、订阅、导出文件或服务器专用配置。

## 许可证

MIT
