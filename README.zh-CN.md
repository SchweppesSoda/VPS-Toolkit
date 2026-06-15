# VPS Toolkit

[English](./README.md) | [简体中文](./README.zh-CN.md)

这是 VPS 维护脚本、PO0 中转工具和静态网页工具的源码仓库。运维脚本放在 `scripts/`，公开网站源码放在 `web/`，并同步到单独的 Pages 仓库发布。

## 目录结构

- `scripts/po0/`
  - `reinstall/`：Debian 无人值守重装工具。
  - `nftables/`：nftables 中转管理、白名单、DDNS 上报、内网资源任务和离线 IP 列表构建工具。
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

```bash
# PO0 nftables 中转管理器
bash scripts/po0/nftables/nftables-relay-manager.sh

# PO0 内网协作客户端
bash scripts/po0/nftables/tools/po0-lan-client.sh

# Fail2ban 管理
sudo bash scripts/vps/fail2ban/fail2ban.sh

# 3x-ui 节点导出
bash <(curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/3x-ui/3x-ui-node-exporter.sh)

# ForwardX NAT VPS 被控机适配
bash scripts/vps/forwardx/forwardx-nat-agent-adapter.sh install --public-port 54999 --internal-port 81 --proto both

# SSH 仅公钥登录加固
sudo bash scripts/vps/ssh-key-only/setup-ssh-key-only-full.sh
```

开发时可以直接在本地浏览器打开 `web/index.html`、`web/vps-toolkit/index.html` 或 `web/vps-toolkit/tools/` 下的 HTML 文件，不需要部署服务器。

## 安全说明

执行前必须检查脚本。重装、SSH、防火墙、nftables 和路由操作可能导致数据丢失或远程连接中断，应提前准备服务商控制台或其它恢复通道。

不要提交运行时生成的密码、Token、deploy key、私钥、节点链接、订阅、导出文件或服务器专用配置。

## 许可证

MIT
