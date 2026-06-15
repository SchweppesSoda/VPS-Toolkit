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
