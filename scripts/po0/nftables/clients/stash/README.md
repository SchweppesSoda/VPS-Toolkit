# Stash PO0 防火墙

导入 [PO0-Firewall.stoverride](https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/stash/PO0-Firewall.stoverride)，或使用个人配置内嵌的同类模块。两者只启用一份。

访问 `http://po0-report.invalid/settings` 打开本机管理页。在模块 `/save-official` 的参数中填写 Token、槽位和名称，再点击“保存配置”。多个账号用逗号、分号、空格或换行分隔；槽位参数 `@0`～`@4` 对应界面 #1～#5。已保存的账号和槽位优先于同步参数，清除后同步参数不会自动恢复。

定期上报默认每 10 分钟，范围 60～86400 秒。关闭定期上报保留间隔；停用自动上报同时停用定期与出口变化触发，手动操作仍可用。Stash 每分钟轮询直连出口 IPv4，没有公开 SSID 读取 API 和原生网络变化事件。按网络选择账号默认关闭，开启后原目标用于蜂窝，Wi-Fi 使用另填目标，槽位由用户决定。

“立即上报”和“强制上报”始终先查询，缺少覆盖才写入。“查询官方白名单”只读；“最近结果”和首页 Tile 显示缓存。Tile 不请求网络、不写存储、不执行迁移，点击进入本机管理页。

标准文件为 `PO0-Firewall.stoverride` 和 `po0-firewall.js`。旧模块 `PO0.LAN-Report.stoverride`、旧脚本 `po0-stash-report.js` 为同步兼容副本，旧本机操作 URL 继续有效。`worker-v2` 与本机存储键保持原身份。探测默认使用旧 `📡 PO0 Wi-Fi 探测` / `📡 PO0 蜂窝探测`；若主配置重命名，可在各次脚本调用的 JSON 参数中设置 `PO0_PROBE_WIFI_GROUP` / `PO0_PROBE_CELLULAR_GROUP` 为对应组名。两组必须仍有互补的网络策略；恰好一个成功才识别网络，其它结果继续跳过官方请求。源码维护只编辑标准文件，再通过 [PO0 构建入口](../../../relay/README.md#下载与构建)同步兼容副本。
