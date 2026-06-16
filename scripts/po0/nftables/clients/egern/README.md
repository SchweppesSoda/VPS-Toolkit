# Egern Client IP 上报

这个模块用于手机、平板等 Egern 设备上报“当前出口 IPv4”。它不解析 DDNS，也不要求 PO0 开 HTTP；Egern 先用 `DIRECT` 访问 `IP_CHECK_URL` 获取当前公网 IPv4，再通过一次性 SSH 调 PO0：

```bash
bash /root/nftables-relay-manager.sh --client-ip-report <REPORT_NAME> <ipv4> <REPORT_TOKEN> <identity> <ttl>
```

## 文件

- `PO0-Client-IP-Report.yaml`：Egern 模块，包含定时、网络变化触发、手动执行和 Widget。
- `po0-client-ip-report.js`：获取当前出口 IPv4，并通过 SSH 上报 PO0。
- `po0-client-ip-widget.js`：读取 `ctx.storage` 中的最近状态，显示成功 IP、时间、TTL、失败原因等。

旧的 `PO0-DDNS-Report.yaml` / `po0-ddns-report.js` 已删除，不再保留兼容 wrapper。

## 导入

在 Egern 中导入模块 raw URL：

```text
https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/egern/PO0-Client-IP-Report.yaml
```

然后在模块环境变量里填写：

- `PO0_HOST`：PO0 SSH 地址。
- `PO0_PORT`：默认 `22`。
- `PO0_USER`：默认 `root`。
- `PO0_PASSWORD` 或 `PO0_PRIVATE_KEY`：二选一，推荐私钥。
- `PO0_SCRIPT`：默认 `/root/nftables-relay-manager.sh`。
- `REPORT_NAME`：来源 ID，例如 `iphone`、`ipad-cellular`。
- `REPORT_TOKEN`：PO0 端生成的 Client IP 上报 token。
- `TTL_SECONDS`：默认 `3600`。
- `IP_CHECK_URL`：默认 `https://ip9.com.cn/get`；脚本会 fallback 到 `https://myip.ipip.net/json`、`http://ip-api.com/json/?lang=zh-CN`、`api.ipify.org` 等接口。
- `POLICY`：默认 `DIRECT`，用于确保查到的是当前设备真实出口 IP，而不是代理落地 IP。

## 多 PO0 上报

如果要把同一个当前出口 IPv4 同时上报到两个或多个 PO0，填写 `PO0_TARGETS`。一行一个目标：

```text
source|host|port|user|script|token|identity|ttl
```

示例：

```text
iphone-sg|sg-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_SG|egern-iphone|3600
iphone-us|us-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_US|egern-iphone|3600
```

填写 `PO0_TARGETS` 后，`PO0_HOST`、`REPORT_NAME`、`REPORT_TOKEN` 这些单目标字段可以留空。SSH 密码或私钥默认复用全局 `PO0_PASSWORD` / `PO0_PRIVATE_KEY`；多个 PO0 建议共用同一把专用上报私钥，并在服务器端限制该 key 只能执行主控脚本。

不要在 Egern 里重复导入两份 `PO0-Client-IP-Report.yaml` 来分别上报两个 PO0。那样也能发出 SSH，但会重复查 IP、重复跑定时任务，而且 Widget 的 `ctx.storage` 最近状态会互相覆盖。正确做法是只导入一份模块，把每个 PO0 生成的目标行合并到同一个 `PO0_TARGETS`。

## 执行与提示

- `schedule`：默认每 10 分钟自动上报一次。
- `network`：网络变化时触发一次。
- `generic`：在 Egern 手动执行 `PO0 Client IP Report Now`。
- `widget`：显示最近一次成功/失败状态。

手动执行成功或失败都会尽量通知；自动成功默认不通知，失败默认通知。
