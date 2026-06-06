# vless-raw-enc-argosbx-enhancer.sh 技术文档

## 定位

`vless-raw-enc-argosbx-enhancer.sh` 是 argosbx/Xray 复用增强脚本，不是完整 Xray 面板。

它只复用 argosbx 的 Xray 二进制，另起一个独立 sidecar 服务：

- sidecar service：`agsbx-extra-vless-raw-enc.service`
- sidecar config：`/opt/agsbx-extra/vless-raw-enc/config.json`
- sidecar state：`/opt/agsbx-extra/vless-raw-enc/service.env`

它不会接管、修改或重启原 argosbx 的 Xray 服务，也不会改原 argosbx 的配置文件。

## 能力边界

保留的能力：

- 检测 argosbx，并优先复制 argosbx 自带 `xray`
- 未检测到 argosbx 时，可复制系统 `xray` 或下载官方 Xray release，按 sidecar 模式直接部署
- 安装 / 修复 VLESS RAW ENC
- 安装 / 修复 Shadowsocks 2022
- 从 argosbx 手动同步 Xray core
- 生成 VLESS 和 SS2022 分享链接
- 修改协议端口、节点名和密钥
- 配置测试、服务启停、日志查看
- 本机防火墙 / 云安全组提示
- 卸载 sidecar

不做的能力：

- 不做全协议 Xray 面板
- 不接管原 argosbx Xray 服务
- 不做 cnblock / 中国大陆直连或屏蔽
- 不写全局 routing 策略或安全屏蔽策略
- 不做 doctor / smoke / export 全局诊断
- 不做 Xray 指定版本升级和失败回滚
- 不做 GitHub 下载镜像兜底

这些功能适合完整 Xray 管理器，不适合“复用增强脚本”。

## 端口约定

协议端口范围遵循 `VPS.sh/docs/vps-port-firewall-summary.md`。

当前 sidecar 管理的协议入站使用 `16384-24575`：

- VLESS RAW ENC：TCP
- Shadowsocks 2022：TCP/UDP

脚本会避开：

- 本机已监听端口
- argosbx 端口记录
- 旧 shadowsocks-rust 配置端口
- 同一 sidecar 内其它协议端口

## 协议配置

### VLESS RAW ENC

VLESS inbound 使用：

- `protocol: "vless"`
- `streamSettings.network: "raw"`
- `settings.decryption` 写入服务端 VLESS ENC decryption
- 分享链接写入客户端 encryption
- 默认不写 flow，可选 `xtls-rprx-vision`

### Shadowsocks 2022

SS2022 inbound 使用 Xray 的 `shadowsocks` 协议：

- `network: "tcp,udp"`
- 默认方法：`2022-blake3-aes-128-gcm`
- 自动密钥长度按方法选择：AES-128 用 16 字节，AES-256/ChaCha20 用 32 字节
- 分享链接按 SIP002 生成 `ss://`
- 支持为分享链接单独设置公网 host/port，适合中转或端口映射

脚本不再下载或管理 shadowsocks-rust 二进制。

## Xray core 来源

优先级：

1. 已存在的 `/opt/agsbx-extra/bin/xray`
2. argosbx 目录里的 `xray`
3. 系统 PATH 里的 `xray`
4. 官方 Xray latest release
5. 用户手动指定二进制路径

如果 argosbx 后续更新了自己的 Xray core，可以通过菜单“从 argosbx 同步 Xray core”手动复制到 sidecar。

## 服务管理

systemd 环境写入：

`/etc/systemd/system/agsbx-extra-vless-raw-enc.service`

非 systemd 环境使用：

- `nohup xray run -config ...`
- PID 文件
- crontab `@reboot`

配置改写后会先执行 Xray 配置测试，通过后再重启 sidecar。

## 卸载边界

卸载只删除：

- `/opt/agsbx-extra/vless-raw-enc`
- `agsbx-extra-vless-raw-enc.service`

不会删除或修改 `/root/agsbx` 以及其它 argosbx 文件。
