# Egern SSH IP Report

这个模块用于 Egern 设备上报“当前出口公网 IPv4”。它不解析 DDNS，也不要求 PO0 开 HTTP；Egern 先用 `DIRECT` 轮询 IP 查询接口拿到当前出口 IPv4，再通过一次 SSH 短连接执行：

```bash
bash /root/nftables-relay-manager.sh --ssh-ip-report <SSH_REPORT_SOURCE> <ipv4> <SSH_REPORT_TOKEN> <identity> <ttl>
```

旧的 `PO0-Client-IP-Report.yaml` / `po0-client-ip-report.js` 已废弃。Egern 不再走 `--client-ip-report`，`client_ip` 只给 LAN Worker self-report server 代报访问设备 IP 使用。

## 文件

- `PO0-SSH-IP-Report.yaml`：Egern 模块，包含定时、网络变化、手动执行和 Widget。
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
- `SSH_REPORT_SOURCE`：来源 ID，例如 `iphone`、`ipad-cellular`。
- `SSH_REPORT_TOKEN`：PO0 端生成的 SSH report token。
- `REPORT_IDENTITY`：默认 `egern`。
- `TTL_SECONDS`：默认 `3600`。
- `IP_CHECK_URL` / `IP_CHECK_URLS`：公网 IPv4 查询接口；默认从 IP9 和国内接口轮询。
- `POLICY`：默认 `DIRECT`，用于尽量获取当前真实出口 IP。

## 多 PO0

多个 PO0 不要重复导入模块。只导入一份，然后填写 `SSH_REPORT_TARGETS`。可以一行一个目标，也可以用逗号或分号分隔：

```text
source_id|host|port|user|script|token|identity|ttl
```

示例：

```text
iphone-sg|sg-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_SG|egern-iphone|3600
iphone-us|us-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_US|egern-iphone|3600
```

如果 Egern 输入框会把换行折叠成空格，建议直接用逗号：

```text
iphone-sg|sg-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_SG|egern-iphone|3600,iphone-us|us-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_US|egern-iphone|3600
```

填写 `SSH_REPORT_TARGETS` 后，单目标字段 `PO0_HOST`、`SSH_REPORT_SOURCE`、`SSH_REPORT_TOKEN` 可以留空。多个 PO0 建议共用同一把 Egern 专用上报私钥，并在 PO0 端安装 scope=`egern` 的受限 key。

## 执行与提示

- `schedule`：默认每 10 分钟自动上报一次。
- `network`：网络变化时触发一次。
- `generic`：在 Egern 手动执行 `PO0 SSH IP Report Now`。
- `widget`：点击系统“更新小组件”会立即执行一次上报，并显示每个 PO0 target 的成功/失败、IP、时间、TTL 和错误原因。

手动执行成功/失败都会尽量通知；自动成功默认不通知，失败默认通知。
