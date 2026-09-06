# Egern SSH IP Report

这个模块用于 Egern 设备上报“当前出口公网 IPv4”。它不解析 DDNS，也不要求 PO0 开 HTTP；同一轮执行时，Egern 先通过 `DIRECT` 直连 PO0 官方防火墙做只读检查，必要时固定槽位加白，再按原流程通过 SSH 短连接上报 PO0/LAN Worker。

```bash
bash /root/nftables-relay-manager.sh --ssh-ip-report <SSH_REPORT_SOURCE> <ipv4> <SSH_REPORT_TOKEN> [identity] [ttl] [cidr-prefix]
```

旧的 `PO0-Client-IP-Report.yaml` / `po0-client-ip-report.js` 已废弃。Egern 不再走 `--client-ip-report`，`client_ip` 只给 LAN Worker self-report server 代报访问设备 IP 使用。

## 文件

- `PO0-SSH-IP-Report.yaml`：Egern 模块，包含本机设备 ID 设置、定时、网络变化、手动执行、状态页和 Widget。
- `po0-ssh-ip-report.js`：负责官方防火墙直连、当前出口 IPv4 获取、SSH 上报和状态 Widget。

## 导入

在 Egern 中导入模块 raw URL：

```text
https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/egern/PO0-SSH-IP-Report.yaml
```

参数表按【自建 PO0】【官方防火墙】【通用】连续分组显示；SSH Token、TTL 和自动上报周期属于自建通道，官方 Token / 槽位单独配置，官方周期固定为 600 秒。SSID、IP 探测和通知放在通用区域。

在模块环境变量里填写：

- `PO0_HOST`：PO0 SSH 地址。
- `PO0_PORT`：默认 `22`。
- `PO0_USER`：默认 `root`。
- `PO0_PASSWORD` 或 `PO0_PRIVATE_KEY`：二选一，推荐专用受限私钥。
- `PO0_SCRIPT`：默认 `/root/nftables-relay-manager.sh`。
- `SSH_REPORT_SOURCE`：来源组 ID(source-id)，例如 `<device-id>`。
- `SSH_REPORT_TOKEN`：PO0 端生成的 SSH report token。
- `PO0_FIREWALL_TOKENS`：可选，默认关闭。多个官方账号可用逗号、分号、空格或换行分隔（兼容中文逗号、分号），格式为 `pgnfw_...` 或 `pgnfw_...@0` 到 `@4`；同一 token 即使指定不同槽位也只能配置一次，以避免并发竞态。Egern 直接使用 `DIRECT` 请求固定官方 API；正常上报先执行 GET，当前出口缺失或槽位不对时才 POST 加白；只读状态永不 POST。配置/API 槽位从 `0` 到 `4`，界面显示为用户可读的第 `1` 到 `5` 槽。
- `REPORT_IDENTITY`：默认 `egern`。
- `TTL_SECONDS`：默认 `43200` 秒（12 小时）。
- `AUTO_REPORT_INTERVAL_SECONDS`：实际 SSH 自动上报周期，默认 `3600` 秒，可设置 `600` 到 `86400` 秒；建议小于 `TTL_SECONDS` 并留出余量。
- `CELLULAR_CIDR_PREFIX`：蜂窝网络默认 `24`，按 `/24` 上报；设为 `32` 可关闭。Wi-Fi 和未知网络始终按 `/32` 上报。
- `SKIP_WIFI_SSIDS`：可选。仅对 `schedule` / `network` 自动触发生效；当前 Wi-Fi SSID 命中后，本机跳过本次公网 IP 探测、SSH 和官方上报。多个 SSID 用英文分号 `;` 分隔，精确大小写匹配；读取不到 SSID 时继续正常上报。手动运行、状态页和 Widget 刷新会强制继续上报。SSID 只写入 Egern 本地状态 / 日志，不上传到 PO0 或 LAN Worker。
- `IP_CHECK_URL` / `IP_CHECK_URLS`：公网 IPv4 查询接口；默认从 IP9 开始，失败后轮询其它国内接口和 `myip.ipip.net`。
- `POLICY`：默认 `DIRECT`，用于尽量获取当前真实出口 IP。
- `DEVICE_ID_SETUP`：只在手动运行 `保存本机设备 ID` 时读取，用于把本机设备 ID 写入 `ctx.storage`。定时/网络上报不会直接使用这个同步 env。

## 双通道操作

模块操作按通用、自建 PO0、官方防火墙、本机维护、自动触发分组。先运行“查看本机上报设置”，可以看到两边配置 / 自动开关、名称、周期和共享 SSID 名单，此操作不联网。

- 自建：“保存本机自建 PO0 / 通用设置”、“切换自建 PO0 自动上报”、“仅自建 PO0 立即上报”、“清除本机自建 PO0 配置”。
- 官方：“保存本机 PO0 官方防火墙配置”、“切换官方防火墙自动上报”、“仅官方防火墙立即上报”、只读状态、清除 Token。
- 原来的“立即上报”和 schedule / network 保留；自动触发只运行已配置且自动开关开启的通道。停用保留参数，手动和原有状态 / Widget 行为不受自动开关影响。

PO0_FIREWALL_NAMES 给官方目标设置本机显示名称，与 Token 顺序对应，用分号或换行分隔，名字可以包含空格。空白保留已保存名称，单独 - 清空名称；只改 Token 顺序或槽位时，名称跟随相同账号。自建多目标原有来源 ID / identity 显示和 TTL 覆盖保持不变，名称不会改变官方协议。

清除一个通道保留另一通道及公共 SSID 等设置；清除全部保留设备 ID。清除操作会留下本机停用记录，同步模块参数不会在下一次定时执行时重新恢复旧凭据。重新填写并保存后，用“切换…自动上报”恢复该通道。官方固定 600 秒且无客户端 TTL 参数；自建 TTL 和自动上报周期仍分别设置。

## 本机上报配置持久化

模块使用 Egern 原生 `ctx.storage` 保存 SSH/官方上报配置，不依赖 BoxJS、Relay 或其它常驻服务。保存内容包括 PO0 目标、SSH 密码/私钥/口令、report token、`PO0_FIREWALL_TOKENS`、周期、SSID guard、IP 探测和通知选项；官方最近状态和 SSH 最近状态分开保存，运行状态不保存官方 token；`DEVICE_ID_SETUP` 不在其中，本机设备 ID 继续使用独立 storage。

首次启用或从旧版迁移时：

1. 先保留当前配置里已经填好的模块环境变量，并刷新 PO0 模块/脚本。
2. 自建 SSH 和通用参数填写后，手动运行 `保存本机自建 PO0 / 通用设置`；官方 Token / 槽位填写后，单独运行 `保存本机 PO0 官方防火墙配置`。两个保存动作均只写本机配置，不发起网络请求，且不会覆盖另一通道的已保存参数。
3. 打开 `PO0 SSH 上报状态`，确认上报正常。
4. 此后可以更换 Egern 主配置；新配置里不需要重新填写这些字段。

如果脚本首次运行时尚无本机保存值，但现有环境变量已经完整可用，脚本也会自动写入一次本机 storage，兼容旧配置迁移。一旦本机保存值存在，定时、网络变化、立即上报、状态页和 Widget 都以 storage 为准；新配置里的空值、schema 默认值或其它模块环境变量不会在后台覆盖它。需要修改时，在模块环境变量里填写新值并主动运行 `保存本机自建 PO0 / 通用设置`，未填写的字段会保留旧值。为防止换配置后出现的 schema 默认值误覆盖自定义旧值，默认值不会覆盖不同的已保存值；确实要恢复某字段默认值时，可先运行 `清除本机自建 PO0 配置`，再重新填写并保存，最后恢复自建自动上报；无需删除官方配置。

尚未保存且环境变量不完整时，schedule/network 自动任务会静默跳过，不探测公网 IP、不连接 SSH、也不通知；立即上报、状态页和 Widget 会提示先保存配置。因此模块可以安全地默认启用。`清除本机全部 PO0 上报配置` 会同时清除最近上报状态，但保留本机设备 ID。

密码、私钥和 Token 会以字符串形式保存在 Egern 本机持久化 storage，不写入本仓库，也不通过 PO0/LAN Worker 上传。删除 Egern、清除其应用数据或主动运行清除脚本后需要重新保存；不要把 Egern storage 当作凭据备份。

官方固定槽位也属于本机已保存配置。另一台设备同步来的 `PO0_FIREWALL_TOKENS`（包括 `@槽位`）不会在定时、网络变化或普通手动上报时覆盖它；只有再次运行“保存本机 PO0 官方防火墙配置”才会更新。不同设备应自行选择不同的官方槽位，`{device}` 只用于自建上报身份，不负责分配官方槽位。

## 本机设备 ID

Egern 配置会通过 iCloud 同步，模块环境变量不适合直接写每台设备不同的 `source-id`。模块支持在本机 `ctx.storage` 保存设备 ID，并在上报时展开 `SSH_REPORT_TARGETS` 里的 `{device}`。

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

多个 PO0 不要重复导入模块。只导入一份，然后填写 `SSH_REPORT_TARGETS`。可以一行一个目标，也可以用逗号、分号或空格分隔。第一列是 `source-id`，会映射到脚本里的 `SSH_REPORT_SOURCE`；`source-id` 和 `identity` 支持 `{device}` 占位符：

```text
source-id|host|port|user|script|token|identity|ttl
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

多设备必须使用不同 `source-id`，推荐保留 `{device}` 占位符或为每台设备手动设置独立 source-id。共用同一个 source-id 会共享 TTL 续期和 12 条有效 CIDR 裁剪；蜂窝 `/24` 与 Wi-Fi/未知网络 `/32` 都各算 1 条，共享同一个上限。`identity` 只用于备注和审计，不参与分组。

填写 `SSH_REPORT_TARGETS` 后，单目标字段 `PO0_HOST`、`SSH_REPORT_SOURCE`、`SSH_REPORT_TOKEN` 可以留空。多个 PO0 建议共用同一把 Egern 专用上报私钥，并在 PO0 端安装 scope=`egern` 的受限 key。

## 执行与提示

- `schedule`：每 10 分钟轻量检查一次；实际 SSH 自动上报周期由 `AUTO_REPORT_INTERVAL_SECONDS` 控制，默认 `3600` 秒。
- `network`：网络变化时触发一次。
- `generic`：在 Egern 手动执行 `PO0 SSH IP Report Now`。
- `PO0 官方防火墙状态（只读）`：逐个账号用 `DIRECT` 发 GET，显示当前出口、白名单、已用名额/总名额和固定槽位；当前出口未命中时只显示 `missing`，不会 POST。
- `保存本机自建 PO0 / 通用设置`：校验当前模块环境变量并保存到本机 `ctx.storage`，不探测 IP、不做 SSH 上报。
- `清除本机全部 PO0 上报配置`：清除本机上报配置和最近状态，保留本机设备 ID。
- `保存本机设备 ID`：把 `DEVICE_ID_SETUP` 写入本机 `ctx.storage`，不做 SSH 上报。
- `清除本机设备 ID`：清除本机 `ctx.storage` 里的设备 ID。
- `PO0 SSH 上报状态` / `widget`：显示本机设备 ID、公网 IP、上报 CIDR、IP 归属地、运营商、自动上报周期、每个 PO0 target 的成功/失败，以及官方防火墙各账号的当前出口、白名单、`已用/上限`、当前命中条目和固定槽位。状态/Widget 的官方检查始终只读；归属地 / 运营商优先使用本次 IP 查询接口返回的数据，拿不到时才额外查询。

自动触发会先校验已配置的通道，再读取当前 Wi-Fi SSID；如果 `SKIP_WIFI_SSIDS` 命中，脚本只写本地跳过状态，官方和 SSH 两条通道都不探测/不上报/不通知，并优先保留上一轮成功状态供 Widget 查看。SSID 读取失败会 fail-open 继续正常上报。未命中 SSID guard 时，官方通道先按固定 `600` 秒独立 due 检查，GET 成功且命中时保持安静，缺失或固定槽位不符才 POST；官方失败仍会继续执行 SSH 通道。随后 SSH 通道按既有 CIDR、`AUTO_REPORT_INTERVAL_SECONDS` 和 TTL 判断；两条通道的 due 状态互不影响。指定 WAN/多 WAN 的官方绑定属于主 OpenWrt 配置，Egern 只使用本机当前 `DIRECT` 出口。

手动执行成功/失败都会尽量通知；自动成功默认不通知，失败、部分完成或官方新增占位时才通知。官方 token 不写入日志、通知、最近状态或错误摘要；手动执行和 Status 脚本开启 debug，SSH stderr 会写入 Egern 脚本日志；长错误会分段通知，避免只显示半截 `PO0 restricted report key denied`。

PO0 端如果使用专用受限 SSH 上报 key，Egern 专用 key 的 scope 应为 `egern`。被 wrapper 拒绝时，PO0 会把不含 token 的拒绝摘要写到：

```text
/etc/nftables.d/po0-report-key-denied.log
```

也可以在 PO0 上查看最近记录：

```bash
bash /root/nftables-relay-manager.sh --refresh-report-key-wrapper
bash /root/nftables-relay-manager.sh --show-report-key-denials 80
```
