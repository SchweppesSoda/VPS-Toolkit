# Egern PO0 官方防火墙

导入标准模块 [PO0-SSH-IP-Report.yaml](https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/egern/PO0-SSH-IP-Report.yaml)。文件名和脚本路径保留用于原订阅升级；从 `20260908-official-only-v1` 起只提供官方上报，不再发起 SSH 或自建请求。

## 本机配置

在模块参数填写官方目标并执行保存。目标支持 `Token@槽位|名称`，多目标可用分号或换行分隔。槽位填写 `0..4` 或留空；名称仅用于显示。Token 留空时可仅更新名称。已有本机目标优先，参数同步不会覆盖保存的 Token 或槽位；明确清空后保留停用记录。

首次运行将原配置和状态保存为本机 `:pre-retirement-v1` 快照，再移除活动自建字段。快照不覆盖。旧自建动作只显示退役提示，不触发官方请求。

按网络选择默认关闭。启用后原目标用于蜂窝，Wi-Fi 使用另填目标；两套目标和名称保存在本机。定期间隔、定期开关、网络选择及 SSID 跳过读取当前模块参数。`OFFICIAL_INTERVAL_SECONDS` 默认 600 秒；旧第三列 interval/TTL 写法只解析兼容，不再决定上报频率。

## 操作与小组件

“PO0 防火墙上报状态”是唯一状态小组件，也可手动上报并刷新。小尺寸显示前两个账号，中尺寸三个，大尺寸六个；显示名称、槽位、名额占用、当前 IP、时间与本机 SSID。更多账号保留在配置总览。界面不再预留自建区域或 TTL。

“查询官方白名单”为只读入口，不 POST，也不推进下次定期检查时间。后台定时与网络变化按开关和各账号 due 分别判断；命中 SSID 跳过规则时不发请求。手动状态/Widget 刷新强制检查，读取不到 SSID 时继续。

官方请求沿用 DIRECT、GET-first 行为。同 `/24` 已被其它槽位覆盖时显示共用，不重复占槽；配置槽位保留供新网段使用。POST 403 后只重查一次，GET 失败不尝试 POST。Token 和密码不进入日志、通知或小组件。

## 旧版与验证

完整 SSH/自建模块及文档保存在 [固定归档 Release](https://github.com/SchweppesSoda/VPS-Toolkit/releases/tag/archive/po0-full-20260907.1)。`scripts/po0/relay/egern/` 下的历史导入副本继续与标准 YAML/JS 同步。

离线回归入口：`node tools/po0/test-egern-official-report.mjs`。整体迁移见 [PO0 README](../../../relay/README.md)。
