# PO0 工具

这个目录保存 PO0 或类似中转机的部署与维护工具。这里是 PO0 子系统导航；具体菜单、Token、TTL、状态文件和定时任务以各子目录 README 为准。

## 先看哪份文档

| 目标 | 文档 | 说明 |
| --- | --- | --- |
| 管理 nftables 中转、源 IP 白名单、LAN Worker、Self-report、WebAuth、Egern、iplist/ipdb | [`relay/README.md`](./relay/README.md) | PO0 中转系统用户主文档。 |
| 查看 PO0 nftables 子系统版本历史 | [`relay/CHANGELOG.md`](./relay/CHANGELOG.md) | 完整历史在仓库文档中维护；远端单脚本只显示当前版本更新内容。 |
| 重装 Debian | [`reinstall/README.md`](./reinstall/README.md) | 会重装系统盘，执行前必须单独确认。 |
| 部署代理服务增强 sidecar | [`proxy-services/README.md`](./proxy-services/README.md) | argosbx/Xray sidecar、VLESS RAW ENC、Shadowsocks 2022。 |

Egern 专属配置和 nftables 实现文档从 `relay/README.md` 继续进入，避免 PO0 层入口重复展开细节。

## 常用入口

### PO0 nftables 中转

推荐从 GitHub Release asset 下载主控脚本，再在 PO0 上运行：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/nftables-relay-manager.sh -o /root/nftables-relay-manager.sh
chmod +x /root/nftables-relay-manager.sh
bash /root/nftables-relay-manager.sh
```

检查已安装版本和当前更新内容：

```bash
ssh root@<PO0_HOST> 'bash /root/nftables-relay-manager.sh --version'
ssh root@<PO0_HOST> 'bash /root/nftables-relay-manager.sh --changelog'
```

### LAN Worker

LAN Worker 命令在内网 Worker 机器上执行，不在 PO0 上执行。首次部署推荐进入向导：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-lan-client.sh | bash
```

向导会写入本机配置，并安装 `po0-lan-client` 命令。之后常用：

```bash
po0-lan-client --menu
po0-lan-client --run
po0-lan-client --probe
```

### PO0 Debian 重装

这个脚本会重装系统盘。不要直接复制未知在线命令；先读 [`reinstall/README.md`](./reinstall/README.md)，再上传脚本执行。

```bash
scp scripts/po0/reinstall/po0-debian-reinstall.sh root@<PO0_HOST>:/root/po0-debian-reinstall.sh
ssh root@<PO0_HOST> 'chmod +x /root/po0-debian-reinstall.sh && bash /root/po0-debian-reinstall.sh'
```

### PO0 代理服务增强

```bash
tmp="$(mktemp)"
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer.sh -o "$tmp"
sudo install -m 0755 "$tmp" /usr/local/sbin/vless-raw-enc-argosbx-enhancer
rm -f "$tmp"
sudo /usr/local/sbin/vless-raw-enc-argosbx-enhancer
```

## 发布渠道

PO0 nftables 五个可执行脚本的新安装、自更新和 LAN Worker manager 更新镜像默认使用 GitHub Release asset。五个 asset 由 `tools/po0/manifests/` 按 manifest 从 manager、LAN Worker、Linux/macOS/Windows self-report 五个源码树生成。旧 manager、LAN Worker 和 self-report raw URLs are disabled，不再作为兼容入口。Egern canonical raw path、Egern legacy compatibility path、离线 iplist 构建器、外部 ipdb/iplist 数据源和其它 PO0/VPS 工具若未纳入 Release，仍以各自 README 为准。

## 安全说明

- 仓库只保存脚本和示例，不应提交运行时生成的密码、Token、私钥或节点配置。
- `nftables` 客户端配置会保存 Token，应仅放在可信机器并限制文件权限。
- 重装、SSH、防火墙和转发脚本都可能影响远程连接，执行前应确保有 VNC、控制台或其它恢复通道。
