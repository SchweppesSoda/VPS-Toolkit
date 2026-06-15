# VPS Toolkit

[English](./README.md) | [简体中文](./README.zh-CN.md)

这是一个公开的 VPS 与 PO0 工具仓库，包含系统维护、nftables 中转、SSH 加固、Fail2ban、REALITY 回落域名检测和代理节点处理工具。

## 目录结构

- `PO0/`
  - `reinstall/`：Debian 无人值守重装工具。
  - `nftables/`：nftables 中转管理、白名单、DDNS 上报、内网资源任务和离线 IP 列表构建工具。
  - `proxy-services/`：PO0 代理服务增强脚本。
- `VPS.sh/`
  - `3x-ui/`：交互式 3x-ui 节点/订阅导出工具。
  - `fail2ban/`：Fail2ban 安装与管理。
  - `ssh-key-only/`：SSH 仅公钥登录加固。
  - `reality_dest_finder/`：REALITY 回落域名检测。
  - `docs/`：通用 VPS 运维笔记。
- `Tools/`
  - `argosbx-argo-batch/`：本地 Argosbx Argo 批量处理工具。
  - `proxy-node-manager/`：本地代理节点解析、清洗、分组和导出工具。

## 快速使用

```bash
# PO0 nftables 中转管理器
bash PO0/nftables/nftables-relay-manager.sh

# PO0 内网协作客户端
bash PO0/nftables/tools/po0-lan-client.sh

# Fail2ban 管理
sudo bash VPS.sh/fail2ban/fail2ban.sh

# 3x-ui 节点导出
bash <(curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/VPS.sh/3x-ui/3x-ui-node-exporter.sh)

# SSH 仅公钥登录加固
sudo bash VPS.sh/ssh-key-only/setup-ssh-key-only-full.sh
```

`Tools/` 下的 HTML 工具可以直接在本地浏览器打开，不需要部署服务器。

## 安全说明

执行前必须检查脚本。重装、SSH、防火墙、nftables 和路由操作可能导致数据丢失或远程连接中断，应提前准备服务商控制台或其它恢复通道。

不要提交运行时生成的密码、Token、私钥、节点链接、订阅、导出文件或服务器专用配置。

## 许可证

MIT
