# PO0 工具

这个目录保存 PO0 或类似中转机的部署与维护工具。这里仅提供子系统导航；部署命令、菜单、Token、TTL、状态文件、客户端配置和定时任务以对应模块 README 为准。

## 模块入口

| 目标 | 用户主文档 | 说明 |
| --- | --- | --- |
| 管理 nftables 中转、源 IP 白名单、LAN Worker、Self-report、WebAuth、Egern、Stash、Loon、iplist/ipdb | [`relay/README.md`](./relay/README.md) | PO0 中转系统的主入口；客户端入口、发布渠道、版本历史和实现文档均从这里继续进入。 |
| 重装 PO0 Debian | [`reinstall/README.md`](./reinstall/README.md) | 会重装系统盘，执行前必须单独确认并准备恢复通道。 |
| 部署代理服务增强 sidecar | [`proxy-services/README.md`](./proxy-services/README.md) | argosbx/Xray sidecar、VLESS RAW ENC 和 Shadowsocks 2022。 |

运行在 PO0、LAN Worker 或访问设备上的组件职责不同，不要仅按目录名猜测部署位置。进入对应主文档后，先看其“阅读路线”或“部署”部分。

`tools/po0/` 是 Release 发布文件的离线构建与检查工具，不是 PO0 或 LAN Worker 上的运行入口。

## 安全说明

PO0 重装、SSH、防火墙、nftables 和转发操作都可能导致数据丢失或远程连接中断。执行前应检查脚本，并准备服务商控制台或其它恢复通道。

仓库不保存运行时密码、Token、私钥、节点配置或服务器专用导出文件。
