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

```bash
# PO0 nftables 中转管理器：先上传，再在 PO0 上运行
scp scripts/po0/nftables/nftables-relay-manager.sh root@<PO0_HOST>:/root/nftables-relay-manager.sh
ssh root@<PO0_HOST> 'chmod +x /root/nftables-relay-manager.sh && bash /root/nftables-relay-manager.sh'

# PO0 内网 Worker：推荐在 LAN Worker 机器上用交互向导安装
# 向导可通过密钥 SSH 自动从 PO0 读取 token，写入本机配置，并安装本机 po0-lan-client 命令
# 每次向导初始化一个 PO0 目标；多个 PO0 后续用 po0-lan-client --menu 添加
# SSH 认证按向导选择：系统默认 SSH、私钥路径、或粘贴专用私钥；粘贴的私钥会保存为 600 权限文件
# “额外 SSH 参数”是 ssh 选项，不是私钥短语；带短语的私钥需要 ssh-agent
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/lan-worker/po0-lan-client.sh | bash
po0-lan-client --menu
po0-lan-client --run

# 如果旧版本安装后没有 po0-lan-client 命令，可手动补装
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/lan-worker/po0-lan-client.sh -o /usr/local/sbin/po0-lan-client
chmod 755 /usr/local/sbin/po0-lan-client
/usr/local/sbin/po0-lan-client --menu

# PO0 内网 Worker：在 LAN Worker 机器上执行，DDNS 解析上报 + iplist/ipdb 资源轮询
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/lan-worker/po0-lan-client.sh | bash -s -- --bootstrap --po0-host <PO0_HOST> --source-key <DDNS_SOURCE_KEY> --ddns-domain <DDNS_DOMAIN> --token <DDNS_TOKEN> --resource-token <RESOURCE_TOKEN> --install-cron 5

# PO0 内网 Worker：在 LAN Worker 机器上执行，只做资源轮询
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/lan-worker/po0-lan-client.sh | bash -s -- --bootstrap --po0-host <PO0_HOST> --resource-token <RESOURCE_TOKEN> --install-cron 5

# PO0 内网 Worker：在 LAN Worker 机器上执行，自上报接收端，HTTP 只跑在 LAN Worker
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/lan-worker/po0-lan-client.sh | bash -s -- --install-self
po0-lan-client --self-report-server --self-report-listen 127.0.0.1:8788 --po0-host <PO0_HOST> --client-ip-token <CLIENT_REPORT_TOKEN> --self-report-secret <SELF_REPORT_SECRET>

# Egern SSH report 模块（在 Egern 内导入）
https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/egern/PO0-SSH-IP-Report.yaml

# Linux/OpenWrt 自上报客户端：检测自身出口 IPv4 后报给 LAN Worker
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/self-report/po0-outbound-ip-report.sh | bash -s -- --worker-url <LAN_WORKER_REPORT_URL> --source-id <CLIENT_ID> --secret <SELF_REPORT_SECRET> --install-cron 5

# Fail2ban 管理
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/fail2ban/fail2ban.sh | sudo bash -s -- default

# 3x-ui 节点导出
bash <(curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/3x-ui/3x-ui-node-exporter.sh)

# ForwardX NAT VPS 被控机适配
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/forwardx/forwardx-nat-agent-adapter.sh | sudo bash -s -- install --public-port 54999 --internal-port 81 --proto both

# SSH 仅公钥登录加固
# 菜单式 SSH 加固：查看状态、只更新公钥，或执行完整换端口加固
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/ssh-key-only/setup-ssh-key-only-full.sh | sudo env SSH_CONNECTION="$SSH_CONNECTION" bash
# 高级自动化仍支持 --port、--add-key、--replace-key
```

Windows 自上报客户端：

```powershell
$env:PO0_LAN_WORKER_URL='<LAN_WORKER_REPORT_URL>'; $env:PO0_SELF_REPORT_SOURCE='<CLIENT_ID>'; $env:PO0_SELF_REPORT_SECRET='<SELF_REPORT_SECRET>'; $env:INSTALL_TASK='1'; $env:MINUTES='5'; irm -UseBasicParsing 'https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/self-report/po0-outbound-ip-report.ps1' | iex
```

本地开发时，可以继续从已 checkout 的 `scripts/` 目录直接运行脚本。

开发时可以直接在本地浏览器打开 `web/index.html`、`web/vps-toolkit/index.html` 或 `web/vps-toolkit/tools/` 下的 HTML 文件，不需要部署服务器。

## 安全说明

执行前必须检查脚本。重装、SSH、防火墙、nftables 和路由操作可能导致数据丢失或远程连接中断，应提前准备服务商控制台或其它恢复通道。

不要提交运行时生成的密码、Token、deploy key、私钥、节点链接、订阅、导出文件或服务器专用配置。

## 许可证

MIT
