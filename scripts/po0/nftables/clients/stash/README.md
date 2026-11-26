# Stash PO0 防火墙

导入 [PO0-Firewall.stoverride](https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/stash/PO0-Firewall.stoverride)，或使用个人配置内嵌的同类模块。两者只启用一份。

访问 `http://po0-report.invalid/settings` 打开本机管理页。在 `/save-official` 参数中填写账号，点击“保存配置”。账号可写成 `Token@0|名称`，多条用分号或换行分隔；旧版裸 Token 列表和独立名称参数仍可用。@0～@9 对应界面 #1～#10，超出账号实际额度时报错。已保存的账号和槽位优先于同步参数，清除后同步参数不会自动恢复。

Stash 5 切网立即检查，每分钟判断定时任务是否到期，默认间隔 600 秒，可调至 60～86400 秒。关闭定期检查仍响应切网；停用自动上报后仍可手动操作。后台依赖 VPN 扩展运行。

Stash 5 通过本机 `GET /diagnosis/network` 读取网络类型和 SSID。默认所有网络使用 `PO0_FIREWALL_TOKENS`。将 `OFFICIAL_NETWORK_TARGETS_ENABLED` 设为 true 后，蜂窝使用原账号，Wi-Fi 使用 `PO0_FIREWALL_WIFI_TOKENS`，分别保留各自槽位。分网时无法确认网络类型会跳过。

在 `SKIP_WIFI_SSIDS` 中用英文分号分隔多个名称，区分大小写、完整匹配。命中时自动和普通手动上报都跳过；读不到 SSID 时继续按网络类型处理。SSID 仅用于本机匹配。

“强制上报”绕过 SSID 名单。每个账号先 GET，出口网段取自官方响应。查询和写入均按 [Stash 脚本接口](https://stash.wiki/script/syntax-and-interface) 指定 DIRECT 直连。同一 /24 已在任一槽位放行就结束，缺少覆盖才 POST。POST 返回 403 时只 GET 复查一次。新增放行及检查失败默认通知，普通命中静默；`NOTIFY_SUCCESS` 和 `NOTIFY_FAILURE` 控制手动成功与失败通知。

在「首页 → 第三方服务」或长按节点后的「代理信息」中，「PO0 防火墙 · 本机」均显示这台设备的官方白名单结果。分母是此次检查的账号数。只有部分账号放行时，概览会列出失败或未放行的账号数。遇到跳过的 Wi-Fi、无法识别分网或自动上报已停用时，先显示原因，再标出上次结果及其网络和时间。[Stash 面板文档](https://stash.wiki/script/tile)

点开面板进入本机结果页 `/recent`。每个账号列出官方出口、实际命中或共用的槽位，以及已占用和可用的容量。官方记录都有槽号时，槽位条按 #1 起编号；含自动槽位或旧缓存只有占用数时，槽位条只显示数量。失败账号显示本次错误。打开或刷新概览、结果页和设置页只读本机缓存。点“查询官方白名单”才发起官方 GET。

标准文件为 `PO0-Firewall.stoverride` 和 `po0-firewall.js`。旧模块 `PO0.LAN-Report.stoverride`、旧脚本 `po0-stash-report.js` 为同步兼容副本，旧本机操作 URL 继续有效。`worker-v2` 与本机存储键保持原身份。缺少本机网络接口的旧客户端仅在启用分网时通过 204 探测选账号，默认使用旧 `📡 PO0 Wi-Fi 探测` / `📡 PO0 蜂窝探测`；若主配置重命名，可在各次脚本调用的 JSON 参数中设置 `PO0_PROBE_WIFI_GROUP` / `PO0_PROBE_CELLULAR_GROUP` 为对应组名。两组必须仍有互补的网络策略；恰好一个成功才识别网络，其它结果继续跳过官方请求。

概览的状态判断维护在标准脚本的 `panelOverview`。在仓库根目录运行 `node tools/po0/sync-po0-client-compat.mjs --write` 将它内嵌到离线面板，并同步旧文件名。使用 `--check` 核对结果。[PO0 构建入口](../../../relay/README.md#下载与构建)
