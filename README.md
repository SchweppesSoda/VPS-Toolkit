# VPS Toolkit

简体中文 | [English](./README.en.md)

这是 VPS 维护脚本和 PO0 中转工具的源码仓库。运维脚本位于 `scripts/`；静态网页工具已经迁至 [`SchweppesSoda/vps-toolkit-web`](https://github.com/SchweppesSoda/vps-toolkit-web)。

## 项目入口

| 使用场景 | 入口 | 维护状态 |
| --- | --- | --- |
| PO0 nftables 中转、源 IP 白名单、LAN Worker、Self-report、WebAuth、Egern、Stash、Loon、iplist/ipdb | [`scripts/po0/relay/README.md`](./scripts/po0/relay/README.md) | 核心功能，持续维护 |
| PO0 Debian 重装 | [`scripts/po0/reinstall/README.md`](./scripts/po0/reinstall/README.md) | 按需维护；会重装系统盘 |
| PO0 代理服务增强 sidecar | [`scripts/po0/proxy-services/README.md`](./scripts/po0/proxy-services/README.md) | 按需维护 |
| VPS 代理栈部署、接管与复刻 | [`scripts/vps/proxy-stack/README.md`](./scripts/vps/proxy-stack/README.md) | Inventory 驱动；上层调用 Argosbx、Proxy Gateway Plus 和 sidecar |
| SSH 仅公钥登录加固 | [`scripts/vps/ssh-key-only/README.md`](./scripts/vps/ssh-key-only/README.md) | 通用 VPS 工具 |
| 3x-ui 导出、REALITY 回落域名查找 | [3x-ui](./scripts/vps/3x-ui/README.md) / [REALITY finder](./scripts/vps/reality_dest_finder/README.md) | 独立工具，按需维护 |
| Fail2ban、ForwardX | [Fail2ban](./scripts/vps/fail2ban/README.md) / [ForwardX](./scripts/vps/forwardx/README.md) | 低频使用；保留兼容，不作为默认部署入口 |
| 网页工具 | [在线入口](https://schweppessoda.github.io/vps-toolkit-web/) / [`vps-toolkit-web` 源码](https://github.com/SchweppesSoda/vps-toolkit-web) | 已迁出本仓库 |
| Codex / agent 仓库维护规则 | [`AGENTS.md`](./AGENTS.md) | 改代码前必读 |

日常使用从对应 README 开始。`*-technical.md` 和 `*-design.md` 只用于修改实现，不是部署入口。

## 文档索引

### 用户入口

| 文档 | 用途 |
| --- | --- |
| [`scripts/po0/README.md`](./scripts/po0/README.md) | PO0 子系统导航。 |
| [`scripts/po0/relay/README.md`](./scripts/po0/relay/README.md) | PO0 nftables Relay、LAN Worker、访问设备上报和资源任务。 |
| [`scripts/po0/reinstall/README.md`](./scripts/po0/reinstall/README.md) | PO0 Debian 重装。 |
| [`scripts/po0/proxy-services/README.md`](./scripts/po0/proxy-services/README.md) | PO0 代理服务增强 sidecar。 |
| [`scripts/vps/proxy-stack/README.md`](./scripts/vps/proxy-stack/README.md) | Argosbx、Proxy Gateway Plus、sidecar 的全新部署、已有机器接管和按配置复刻。 |
| [`scripts/vps/ssh-key-only/README.md`](./scripts/vps/ssh-key-only/README.md) | SSH 仅公钥登录加固。 |
| [`scripts/vps/fail2ban/README.md`](./scripts/vps/fail2ban/README.md) | Fail2ban 安装与维护。 |
| [`scripts/vps/3x-ui/README.md`](./scripts/vps/3x-ui/README.md) | 3x-ui 节点和订阅导出。 |
| [`scripts/vps/forwardx/README.md`](./scripts/vps/forwardx/README.md) | ForwardX NAT VPS 被控机适配。 |
| [`scripts/vps/reality_dest_finder/README.md`](./scripts/vps/reality_dest_finder/README.md) | REALITY 回落域名查找。 |

### 客户端与专项说明

| 文档 | 用途 |
| --- | --- |
| [`scripts/po0/nftables/clients/egern/README.md`](./scripts/po0/nftables/clients/egern/README.md) | Egern 标准客户端路径、设备 ID、Widget 和多 PO0 配置。 |
| [`scripts/po0/relay/egern/README.md`](./scripts/po0/relay/egern/README.md) | Egern 历史兼容路径说明。 |
| [`scripts/vps/fail2ban/fail2ban-guide.md`](./scripts/vps/fail2ban/fail2ban-guide.md) | Fail2ban 配置与使用说明。 |
| [`scripts/vps/docs/vps-port-firewall-summary.md`](./scripts/vps/docs/vps-port-firewall-summary.md) | VPS 端口段和防火墙约定。 |

### 实现维护

| 文档 | 用途 |
| --- | --- |
| [`scripts/po0/relay/CHANGELOG.md`](./scripts/po0/relay/CHANGELOG.md) | PO0 nftables 子系统版本历史。 |
| [`scripts/po0/relay/po0-relay-technical.md`](./scripts/po0/relay/po0-relay-technical.md) | manager 内部实现、协议、wrapper 和状态模型。 |
| [`scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer-design.md`](./scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer-design.md) | PO0 代理服务增强脚本设计。 |
| [`scripts/vps/ssh-key-only/setup-ssh-key-only-full-technical.md`](./scripts/vps/ssh-key-only/setup-ssh-key-only-full-technical.md) | SSH 加固脚本技术设计。 |
| [`AGENTS.md`](./AGENTS.md) | 仓库职责边界、维护规则和验证清单。 |
| [`README.en.md`](./README.en.md) | 英文辅助入口。 |

## 最短示例

执行前先检查脚本内容。需要 root 且可能交互的在线脚本，应先下载到临时文件再运行。

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

后续使用：

```bash
po0-lan-client --menu
```

其它工具的安装、参数和卸载方式以各自 README 为准。

## 目录结构

- `scripts/po0/`：PO0 重装、中转、防火墙、客户端上报、资源任务和代理服务增强。
- `scripts/vps/`：通用 VPS 工具和 inventory 驱动的代理栈部署、接管与复刻；每个工具目录维护自己的用户文档。
- `tools/po0/`：PO0 Release 发布文件的离线构建、manifest 和检查工具。
- `tools/vps/`：通用 VPS 模块的离线专项检查。
- Web 工具：源码和 GitHub Pages 发布均在 [`vps-toolkit-web`](https://github.com/SchweppesSoda/vps-toolkit-web)。

## PO0 发布架构与边界

PO0 正式发布由六个独立脚本组成：manager 负责 PO0 nftables 与受控任务，LAN Worker 负责内网任务/接收端，WAN probe 只负责 OpenWrt WAN 出口探测，Linux/macOS/Windows Outbound IP Report 运行在访问设备。两个 OpenWrt APK 分别承载 WAN probe 和 outbound 上报器；APK 的 UCI、procd、LuCI 与 mwan3 绑定只在 OpenWrt 端维护，不把主路由行为扩散到普通客户端。

官方防火墙是默认关闭的独立第二车道：先 GET 查看当前出口、额度和槽位，缺失或固定槽位不匹配时才 POST；官方固定 600 秒，和原有 Worker / Self-report 的计划与 TTL 独立。SSID 本地跳过会同时跳过两条车道；强制上报只绕过本地 due/SSID guard，仍不能绕过 GET。token 只进权限受限配置，不进日志、参数或状态；主 OpenWrt 才能用 mwan3 指定 wan1/wan2，其它端使用各自默认出口。用户入口和实现细节以 [`scripts/po0/relay/README.md`](./scripts/po0/relay/README.md) 与 technical 文档为准。

## 发布与下载

PO0 正式版本通过 [GitHub Releases](https://github.com/SchweppesSoda/VPS-Toolkit/releases) 发布；完整资产固定为：

- `nftables-relay-manager.sh`
- `po0-lan-client.sh`
- `po0-wan-probe.sh`
- `po0-outbound-ip-report.sh`
- `po0-outbound-ip-report-macos.sh`
- `po0-outbound-ip-report.ps1`
- `po0-wan-probe.apk`
- `po0-outbound-ip-report.apk`
- `checksums.txt`

本轮脚本版本为 `2026.09.05+build.8`，tag 为 `po0-v2026.09.05.8`；outbound APK 为 `2026.09.05-r4`，WAN probe APK 继续为 `2026.08.30-r5`。旧版 raw 可执行入口已禁用；Egern、Stash、Loon 和未纳入 Release 的独立工具仍按各自文档使用允许的 raw 路径。

本仓库不再发布 GitHub Pages，也不应从仓库根目录启用 Pages。

## 安全说明

重装、SSH、防火墙、nftables 和路由操作可能导致数据丢失或远程连接中断。执行前应检查脚本，并准备服务商控制台或其它恢复通道。

不要提交运行时密码、Token、deploy key、私钥、节点链接、订阅、导出文件或服务器专用配置。

## 许可证

MIT
