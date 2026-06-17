# PO0 Proxy Service Scripts

这个目录保存 PO0 主机上的代理服务增强脚本。服务部署、节点生成和本机防火墙提示放在这里；端口转发和 nftables 规则仍放在 `../nftables/`。

## 脚本

- `vless-raw-enc-argosbx-enhancer.sh`：面向 argosbx 的 Xray 复用增强脚本。它复用 argosbx 的 Xray 二进制，另起一个独立 sidecar 服务，不接管原 argosbx 的 Xray 服务和配置。当前支持：
  - VLESS + RAW + VLESS Encryption
  - Shadowsocks 2022（由 Xray `shadowsocks` inbound 提供，TCP/UDP）

协议监听端口遵循 `../../vps/docs/vps-port-firewall-summary.md`，固定在 `16384-24575` 内选择。

## 使用入口

在线拉取运行（在 PO0 主机上执行）：

```bash
tmp="$(mktemp)" &&
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer.sh -o "$tmp" &&
sudo bash "$tmp"
rm -f "$tmp"
```

本地仓库运行：

```bash
cd scripts/po0/proxy-services
bash vless-raw-enc-argosbx-enhancer.sh
```

首次进入建议先执行“系统预检 / 环境判断”。如果机器上已有 argosbx，脚本会优先复制 argosbx 的 Xray；如果没有 argosbx，也可以下载官方 Xray 后按 sidecar 模式直接部署。
