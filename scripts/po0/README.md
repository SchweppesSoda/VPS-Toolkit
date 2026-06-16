# PO0 工具

这个目录集中保存 PO0 或类似中转机的部署与维护工具，并按职责拆分：

- `reinstall/`：操作系统重装脚本。
- `nftables/`：端口转发、源 IP 白名单、DDNS 上报和内网资源更新。
- `proxy-services/`：代理服务与现有服务的增强脚本。

## 常用入口

### 重装 Debian

```bash
cd scripts/po0/reinstall
bash po0-debian-reinstall.sh
```

该操作会重装系统盘。运行前必须阅读 [`reinstall/README.md`](./reinstall/README.md)。

### 管理 nftables 中转

```bash
cd scripts/po0/nftables
bash nftables-relay-manager.sh
```

详细功能和客户端使用方式见 [`nftables/README.md`](./nftables/README.md)。

LAN Worker 首次部署推荐在内网机器上直接使用 raw 脚本管道进入交互向导：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/lan-worker/po0-lan-client.sh | bash
```

向导会写入本机配置，并安装 `po0-lan-client` 命令。之后常用：

```bash
po0-lan-client --menu
po0-lan-client --run
po0-lan-client --probe
```

初始化时 PO0 SSH 地址一次只填一个；多个 PO0 目标后续进入 `po0-lan-client --menu` 添加。
SSH 认证按向导选择：系统默认 SSH 配置/agent、已有私钥路径，或粘贴专用私钥。粘贴的私钥会保存到本机配置目录并设置 600 权限。
“额外 SSH 参数”是传给 `ssh` 的选项，例如 `-J jump-host` 或 `-o StrictHostKeyChecking=accept-new`，不是私钥短语；带短语的私钥需要 `ssh-agent`。
菜单里的 `PO0 目标 / SSH / Token` 用于添加、编辑、启停 PO0 目标，并管理目标 SSH 私钥和 Token；`资源统计 / PO0 创建计划` 只读展示 PO0 端资源任务定时创建状态。资源任务创建周期在 PO0 nft manager 设置，LAN Worker 本机只安装轮询器来领取 pending 任务。

如果旧版本安装后没有 `po0-lan-client` 命令，可手动补装：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/lan-worker/po0-lan-client.sh -o /usr/local/sbin/po0-lan-client
chmod 755 /usr/local/sbin/po0-lan-client
/usr/local/sbin/po0-lan-client --menu
```

### 管理代理服务增强

```bash
cd scripts/po0/proxy-services
bash vless-raw-enc-argosbx-enhancer.sh
```

详细说明见 [`proxy-services/README.md`](./proxy-services/README.md)。

## 安全说明

- 仓库只保存脚本和示例，不应提交运行时生成的密码、Token、私钥或节点配置。
- `nftables` 客户端配置会保存 Token，应仅放在可信机器并限制文件权限。
- 重装、SSH、防火墙和转发脚本都可能影响远程连接，执行前应确保有 VNC、控制台或其它恢复通道。
