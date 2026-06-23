# Egern SSH IP Report

这个模块用于 Egern 设备上报“当前出口公网 IPv4”。它不解析 DDNS，也不要求 PO0 开 HTTP；Egern 先用 `DIRECT` 轮询 IP 查询接口拿到当前出口 IPv4，再通过一次 SSH 短连接执行：

```bash
bash /root/nftables-relay-manager.sh --ssh-ip-report <SSH_REPORT_SOURCE> <ipv4> <SSH_REPORT_TOKEN> [identity] [ttl] [cidr-prefix]
```

旧的 `PO0-Client-IP-Report.yaml` / `po0-client-ip-report.js` 已废弃。Egern 不再走 `--client-ip-report`，`client_ip` 只给 LAN Worker self-report server 代报访问设备 IP 使用。

## 文件

- `PO0-SSH-IP-Report.yaml`：Egern 模块，包含本机设备 ID 设置、定时、网络变化、手动执行、状态页和 Widget。
- `po0-ssh-ip-report.js`：获取当前出口 IPv4，并通过 SSH 上报 PO0。

## 导入

在 Egern 中导入模块 raw URL：

```text
https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/egern/PO0-SSH-IP-Report.yaml
```

然后在模块环境变量里填写：

- `PO0_HOST`：PO0 SSH 地址。
- `PO0_PORT`：默认 `22`。
- `PO0_USER`：默认 `root`。
- `PO0_PASSWORD` 或 `PO0_PRIVATE_KEY`：二选一，推荐专用受限私钥。
- `PO0_SCRIPT`：默认 `/root/nftables-relay-manager.sh`。
- `SSH_REPORT_SOURCE`：来源组 ID(source-id)，例如 `<device-id>`。
- `SSH_REPORT_TOKEN`：PO0 端生成的 SSH report token。
- `REPORT_IDENTITY`：默认 `egern`。
- `TTL_SECONDS`：默认 `43200` 秒（12 小时）。
- `AUTO_REPORT_INTERVAL_SECONDS`：实际 SSH 自动上报周期，默认 `3600` 秒，可设置 `600` 到 `86400` 秒；建议小于 `TTL_SECONDS` 并留出余量。
- `CELLULAR_CIDR_PREFIX`：蜂窝网络默认 `24`，按 `/24` 上报；设为 `32` 可关闭。Wi-Fi 和未知网络始终按 `/32` 上报。
- `IP_CHECK_URL` / `IP_CHECK_URLS`：公网 IPv4 查询接口；默认从 IP9 开始，失败后轮询其它国内接口和 `myip.ipip.net`。
- `POLICY`：默认 `DIRECT`，用于尽量获取当前真实出口 IP。
- `DEVICE_ID_SETUP`：只在手动运行 `保存本机设备 ID` 时读取，用于把本机设备 ID 写入 `ctx.storage`。定时/网络上报不会直接使用这个同步 env。

## 本机设备 ID

Egern 配置会通过 iCloud 同步，模块环境变量不适合直接写每台设备不同的 `source_id`。模块支持在本机 `ctx.storage` 保存设备 ID，并在上报时展开 `SSH_REPORT_TARGETS` 里的 `{device}`。

推荐设置方式不依赖浏览器 HTTP，也不需要 MITM：

1. 在模块环境变量 `DEVICE_ID_SETUP` 填入这台设备的 ID，例如 `<device-id>`。
2. 在 Egern 里手动运行 `保存本机设备 ID`。
3. 打开 `PO0 SSH 上报状态`，确认显示 `设备: <device-id>`。
4. 可选：保存后把 `DEVICE_ID_SETUP` 清空，避免以后误操作。已经写入的本机 `ctx.storage` 不受影响。

设备 ID 只能包含英文、数字、`.`、`_`、`-`。写错时重新填写 `DEVICE_ID_SETUP` 并再次运行 `保存本机设备 ID` 即可覆盖。清除本机 ID 可手动运行 `清除本机设备 ID`。

模块也保留了 HTTP request 设置入口，但 iOS/Safari 可能把手输的 HTTP 自动升级成 HTTPS，因此只作为可选兼容方式：

```text
http://po0-egern.local/set-device?id=<device-id>
http://po0-egern.local/device
http://po0-egern.local/clear-device
```

这些 URL 是普通 HTTP request 脚本拦截；如果设备会强制升 HTTPS，就使用上面的 `DEVICE_ID_SETUP` + `保存本机设备 ID` 流程。设备 ID 不会动态显示在模块设置表单里；请在 Egern 的 `PO0 SSH 上报状态` / Widget 里查看 `设备: ...`。

## 多 PO0

多个 PO0 不要重复导入模块。只导入一份，然后填写 `SSH_REPORT_TARGETS`。可以一行一个目标，也可以用逗号或分号分隔。`source_id` 和 `identity` 支持 `{device}` 占位符：

```text
source_id|host|port|user|script|token|identity|ttl
```

示例：

```text
{device}-sg|sg-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_SG|{device}-egern|43200
{device}-us|us-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_US|{device}-egern|43200
```

如果 Egern 输入框会把换行折叠成空格，建议直接用逗号：

```text
{device}-sg|sg-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_SG|{device}-egern|43200,{device}-us|us-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_US|{device}-egern|43200
```

如果当前设备 ID 是 `<device-id>`，上面的配置会上报为 `<device-id>-sg`、`<device-id>-us`。未设置设备 ID 时，`{device}` 会回退为 `egern`。

多设备必须使用不同 `source_id`，推荐保留 `{device}` 占位符或为每台设备手动设置独立 source-id。共用同一个 source-id 会共享 TTL 续期和 12 条有效 CIDR 裁剪；蜂窝 `/24` 与 Wi-Fi/未知网络 `/32` 都各算 1 条，共享同一个上限。`identity` 只用于备注和审计，不参与分组。

填写 `SSH_REPORT_TARGETS` 后，单目标字段 `PO0_HOST`、`SSH_REPORT_SOURCE`、`SSH_REPORT_TOKEN` 可以留空。多个 PO0 建议共用同一把 Egern 专用上报私钥，并在 PO0 端安装 scope=`egern` 的受限 key。

## 执行与提示

- `schedule`：每 10 分钟轻量检查一次；实际 SSH 自动上报周期由 `AUTO_REPORT_INTERVAL_SECONDS` 控制，默认 `3600` 秒。
- `network`：网络变化时触发一次。
- `generic`：在 Egern 手动执行 `PO0 SSH IP Report Now`。
- `保存本机设备 ID`：把 `DEVICE_ID_SETUP` 写入本机 `ctx.storage`，不做 SSH 上报。
- `清除本机设备 ID`：清除本机 `ctx.storage` 里的设备 ID。
- `PO0 SSH 上报状态` / `widget`：显示本机设备 ID、公网 IP、上报 CIDR、IP 归属地、运营商、自动上报周期、每个 PO0 target 的成功/失败、时间、TTL 和错误原因。归属地 / 运营商优先使用本次 IP 查询接口返回的数据，拿不到时才额外查询。

自动触发会先探测当前出口 IPv4，并按网络类型计算上报 CIDR：蜂窝默认 `/24`，Wi-Fi/未知固定 `/32`。如果本次上报 CIDR 和上次成功记录一致、PO0 target 配置未变化，并且距离上次成功还小于 `AUTO_REPORT_INTERVAL_SECONDS`，脚本会跳过 SSH 上报；因此只有蜂窝 `/24` 会出现“IP 变了但同一 CIDR，所以跳过 SSH”。该周期默认 `3600` 秒，可设置 `600` 到 `86400` 秒；模块定时任务每 10 分钟唤醒检查一次，所以实际执行精度以 10 分钟为粒度。建议 `TTL_SECONDS` 至少大于自动上报周期；如果 TTL 小于自动上报周期，脚本会提前续期，尽量避免白名单过期空窗。跨 `/24`、Wi-Fi/未知网络 IP 变化、target 配置变化（含 TTL、CIDR 前缀、脚本路径、用户、token 指纹等）、自动周期到达、手动执行和 Widget 刷新都会继续执行 SSH 上报。

手动执行成功/失败都会尽量通知；自动成功默认不通知，失败默认通知。手动执行和 Status 脚本开启 debug，SSH stderr 会写入 Egern 脚本日志；长错误会分段通知，避免只显示半截 `PO0 restricted report key denied`。

PO0 端如果使用专用受限 SSH 上报 key，Egern 专用 key 的 scope 应为 `egern`。被 wrapper 拒绝时，PO0 会把不含 token 的拒绝摘要写到：

```text
/etc/nftables.d/po0-report-key-denied.log
```

也可以在 PO0 上查看最近记录：

```bash
bash /root/nftables-relay-manager.sh --refresh-report-key-wrapper
bash /root/nftables-relay-manager.sh --show-report-key-denials 80
```
