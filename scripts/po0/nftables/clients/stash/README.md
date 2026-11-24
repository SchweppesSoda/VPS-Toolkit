# Stash PO0 防火墙

导入 [PO0-Firewall.stoverride](https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/stash/PO0-Firewall.stoverride)，或使用个人配置内嵌的同类模块。两者只启用一份。

访问 `http://po0-report.invalid/settings` 打开本机管理页。在模块 `/save-official` 的参数中填写 Token、槽位和名称，再点击“保存配置”。多个账号用逗号、分号、空格或换行分隔；槽位参数 `@0`～`@9` 对应界面 #1～#10。实际可用数量以账号返回额度为准（默认 5 个，最多 10 个），固定槽位超额时会报错且不写入。已保存的账号和槽位优先于同步参数，清除后同步参数不会自动恢复。

定期上报默认每 10 分钟，范围 60～86400 秒。关闭定期上报保留间隔；停用自动上报同时停用定期与切网触发，手动操作仍可用。Stash 5 使用 `event.script` 的 `network-changed` 事件立即核对官方白名单，定时任务每分钟在本机判断是否到期。当前出口网段直接取自官方接口响应。脚本不读取 SSID，后台依赖 VPN 扩展运行。按网络选择账号默认关闭，开启后原目标用于蜂窝，Wi-Fi 使用另填目标，槽位由用户决定。

“立即上报”和“强制上报”始终先查询，缺少覆盖才写入。“查询官方白名单”只读；“最近结果”和首页 Tile 显示缓存。Tile 同步读取缓存，显示已加白账号数、检查时间和前两个账号的名称、状态、固定槽位、占用及出口。点击进入本机管理页。

标准文件为 `PO0-Firewall.stoverride` 和 `po0-firewall.js`。旧模块 `PO0.LAN-Report.stoverride`、旧脚本 `po0-stash-report.js` 为同步兼容副本，旧本机操作 URL 继续有效。`worker-v2` 与本机存储键保持原身份。探测默认使用旧 `📡 PO0 Wi-Fi 探测` / `📡 PO0 蜂窝探测`；若主配置重命名，可在各次脚本调用的 JSON 参数中设置 `PO0_PROBE_WIFI_GROUP` / `PO0_PROBE_CELLULAR_GROUP` 为对应组名。两组必须仍有互补的网络策略；恰好一个成功才识别网络，其它结果继续跳过官方请求。源码维护只编辑标准文件，再通过 [PO0 构建入口](../../../relay/README.md#下载与构建)同步兼容副本。
