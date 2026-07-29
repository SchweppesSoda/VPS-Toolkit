# PO0 Proxy Service Scripts

这个目录保存 PO0 主机上的代理服务增强脚本。服务部署、节点生成和本机防火墙提示放在这里；端口转发和 nftables 规则仍放在 `../nftables/`。

## 脚本

- `vless-raw-enc-argosbx-enhancer.sh`：面向 argosbx 的 Xray 复用增强脚本。它复用 argosbx 的 Xray 二进制，另起一个独立 sidecar 服务，不接管原 argosbx 的 Xray 服务和配置。当前支持：
  - VLESS + RAW + VLESS Encryption
  - Shadowsocks 2022（由 Xray `shadowsocks` inbound 提供，TCP/UDP）

VLESS RAW ENC 的外层物理监听只有 TCP。它可以在 VLESS TCP 会话内承载 UDP 转发语义，但
这不等于主机上存在该 VLESS 端口的 UDP listener；主机防火墙只应为 VLESS 端口声明 TCP。
SS2022 会实际监听 TCP 和 UDP，防火墙需要分别声明两条规则。

协议监听端口遵循 `../../vps/docs/vps-port-firewall-summary.md`，固定在 `16384-24575` 内选择。

## 使用入口

推荐永久安装命令入口（在 PO0 主机上执行）：

```bash
tmp="$(mktemp)"
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer.sh -o "$tmp"
sudo install -m 0755 "$tmp" /usr/local/sbin/vless-raw-enc-argosbx-enhancer
rm -f "$tmp"
sudo /usr/local/sbin/vless-raw-enc-argosbx-enhancer
```

以后直接运行：

```bash
sudo /usr/local/sbin/vless-raw-enc-argosbx-enhancer
```

只临时运行、不安装命令入口：

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

## 整机编排与接管

需要在全新机器部署、接管已有机器或按私有配置复刻甬哥 Argosbx、Proxy Gateway Plus 和
本 sidecar 时，使用
[`scripts/vps/proxy-stack/README.md`](../../vps/proxy-stack/README.md) 的上层编排入口。
该入口只调用本脚本的既有安装和管理方式，不修改本 sidecar 业务脚本；协议端口、公网来源
和整机 input policy 来自
每台机器自己的实例 inventory，不在本 sidecar 脚本中保存机器专用常量。完成上层编排后，
本 sidecar 仍使用本页管理入口独立运维。
