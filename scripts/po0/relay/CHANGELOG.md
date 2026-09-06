# PO0 nftables Changelog

本文件保存 PO0 nftables 子系统的完整版本历史。各可独立部署脚本只在脚本头部保留“当前版本更新内容”，供 `--changelog`、`--upgrade-self` 或更新完成提示在远端单文件环境中显示。

旧脚本内置 changelog 没有给每条历史记录保存完整版本号；这些条目已迁移到对应脚本的“历史迁移条目”小节。自本文件建立后，新增版本必须按脚本名和版本号记录在这里。

## 2026-09-06 Egern：小组件恢复与自动开关说明

- 修复小组件遇到并发上报锁或本机存储异常时返回普通对象、无法渲染的问题；并发时显示正在上报并保留上次结果，不重复发送。
- 恢复旧小组件名称和 generic 脚本绑定，保留已有桌面组件；模块 JS URL 加入本次修复版本参数。
- 自动开关拆为明确的“启用 / 停用”，重复点击保持指定状态；执行结果说明仅影响定时 / 网络变化，配置、另一通道和手动 / 小组件刷新不受影响。

## 2026-09-06 Egern：统一目标配置与强制刷新

- 自建防火墙统一填写“上报目标”，一台或多台使用相同列表格式；移除 8 个重复单目标表单项，保留共用 SSH 认证、周期、蜂窝网段、每目标备注和 TTL，以及旧配置读取。
- 模块与操作统一命名为“PO0 防火墙上报”；保留独立保存、清除、自动开关、官方目标名称及旧动作兼容。
- 强制上报、普通上报状态页和 Widget 刷新均绕过本机间隔与 SSID 跳过，官方先 GET、缺失或槽位不符时才 POST；明确的官方只读入口仍只查询。
- 本次更新 Egern 标准 raw 模块 / 脚本和历史兼容副本，不重复发布未改动的桌面脚本或 APK。

## 2026.09.06+build.2 访问设备客户端界面与通道管理

- Windows / macOS / Linux：本机配置页和编辑入口显示完整已保存 Token / Worker 密钥；官方 Token 支持可见多行输入，空行保留、单独 `-` 清空，无效输入保留原配置。
- Windows / macOS / Linux：主菜单统一为 7 个入口，两个通道采用相同 6 项子菜单；分别设置名称、停用 / 恢复自动上报、手动上报和清除，已有计划随菜单保存更新。安装一次共用计划，各通道保持独立周期。
- Egern / Loon / Stash：本机操作按通道分组；补齐自建清除与双通道开关、官方目标名称。Stash 增加本机管理页，Worker 参数只保存一次。清除后的凭据不会因同步参数而自动恢复。
- 保留原上报协议、官方先 GET、各端原默认周期 / TTL 和网络判断差异；名称仅本机显示，SSID 能力按实际客户端接口说明。
- 六客户端官方 Token 统一支持逗号、分号、空格、换行和中文逗号/分号；固定槽位和账号去重校验保留。
- Loon：通用 SSID 名单改为可配置，命中时同时跳过自建和官方上报；Stash 公开 JS 接口缺少当前 SSID，明确目前不支持脚本内的 SSID 跳过名单。

- 本次使用 `po0-scripts-v2026.09.06.2` 独立发布五个主脚本；manager / LAN Worker 仅同步发布版本，本次不构建 APK。同步删除旧 WAN probe 的源码、包定义、桌面入口与构建 / 发布清单，修正文档残留；五个发布脚本版本统一。

- 修复 scripts 标签在 GitHub Actions 中无法通过旧映射校验的问题：检查器直接识别真实组件标签。保留未发布成功的 build.1 标签。

## 2026.09.05+build.9

- Windows / macOS / Linux：自建、官方与通用参数分别配置，菜单编号和状态同步分区；Egern 独立保存官方配置，Stash 官方 Token 集中到独立保存入口，Loon 参数表增加分组标题。

## 2026.09.05+build.8

- APK 布局门禁严格比对 Linux 源码、精简运行时和命令版本，避免重复写死发布版本；修复 build.7 因布局断言仍为 build.6 而失败。
- 同步当前发布入口文档；保留 build.6 / build.7 失败 tag，功能、outbound APK r4 和 LuCI v8 不变。

## 2026.09.05+build.7

- 同步 Bash / PowerShell 发布检查器的预期版本和 tag，修复 build.6 正式门禁因旧 build.5 默认值失败；保留失败 tag，不覆盖已有发布。
- 六个脚本与 APK 内部版本统一为 build.7，功能包含以下 build.6 修复；尚未发布的 outbound APK 包版本继续为 `2026.09.05-r4`，LuCI 资源继续为 v8。

## 2026.09.05+build.6

- OpenWrt：两个通道各自配置、手动上报和显示结果；完整 Token 可见并校验前缀，支持粘贴官方链接；自动开关不再挡住手动操作。
- OpenWrt：脱敏官方响应中正常带回的 Token，修复有效请求被误拒绝；旁路网关通过专用源地址直连探测真实 WAN IP 和官方 GET/POST，自建 LAN Worker 提交遵循 OpenClash。
- OpenWrt：探测域名通过可配置的主路由 DNS 53 端口获取真实 IPv4，移除固定服务器解析；源地址模式清理旧 HTTP 探针配置，其它部署保留兼容模式。
- OpenWrt：补齐 APK 精简运行时缺失的普通上报入口，新增生成后实际执行的离线回归。
- Stash/Loon：官方 Token 和固定槽位改用本机专用配置，避免同步参数覆盖；增加明确的本机保存、清除操作。
- Egern：补充验证同步环境不能覆盖本机官方槽位和设备 ID；Windows/macOS 固定槽位机制不变。

## po0-nftables-relay-manager

### 2026.09.05+build.5

- 对齐本轮 OpenWrt 旁路网关支持的发布版本；本脚本行为未变。

### 2026.09.05+build.4

- 修复发布包校验清单，避免整包校验失败；本脚本功能沿用 `2026.09.05+build.3`。

### 2026.09.05+build.3

- 适配非 Windows CI 的 ACL 测试隔离；本脚本功能沿用 `2026.09.05+build.2`。

### 2026.09.05+build.2

- CI 跨平台兼容性修复；本脚本功能沿用 `2026.09.05+build.1`。

### 2026.09.05+build.1

- 跟随 PO0 发布批次统一到 `2026.09.05+build.1`；manager 行为未变。

### 2026.08.30+build.5

- 跟随 PO0 发布批次对齐到 2026.08.30+build.5；本脚本无行为变化。

### 2026.08.30+build.4

- 跟随 PO0 发布批次对齐到 2026.08.30+build.4；本脚本无行为变化。

### 2026.08.30+build.1

- 跟随 PO0 发布批次对齐到 2026.08.30+build.1；本脚本无行为变化。

### 2026.08.29+build.1

- 跟随 PO0 发布批次对齐到 2026.08.29+build.1；本脚本无行为变化。

### 2026.07.23+build.1

- 托管 NAT/MANGLE 表刷新改为单个 nftables 事务：同一批次先删除当前托管表，再创建完整新表。
- 原子事务整体通过 `nft -c` 后才正式执行；预检或应用失败时不再先删除运行中的旧托管规则。

### 2026.07.22+build.2

- 上传失败返回码改为显式捕获；即使调用环境启用 `errexit`，也会继续清理临时文件并释放任务锁。
- 资源任务上传按类型新增默认大小上限：`iplist.tar.gz` 为 8 MiB，`qqwry.ipdb` 为 128 MiB；PO0 本机可以用环境变量覆盖。
- 上传正文改为严格有界接收，短输入、尾随数据、SHA-256 或长度不符均拒绝并清理临时文件。
- 上传正文期间不再持有全局资源任务锁，提交前重新确认任务状态和 Worker；现有 Worker 命令参数与任务状态保持兼容。
- 上传与完成接口统一规范化 SHA-256 大小写和文件大小前导零，避免旧调用在上传成功后无法完成任务。
- 无 `flock` 环境释放内部文件锁后不再误把当前 shell 的后续错误输出重定向到空设备。

### 2026.07.20+build.1

- `--client-ip-report` 新增可选的第六个业务参数 `cidr-prefix`，仅接受 `24` 或 `32`，省略时保持 `/32` 兼容行为。
- manager 会把上报 IPv4 归一化为对应 `/24` 或 `/32` CIDR，并在接收结果、状态统计和来源备注中记录实际 CIDR；受限 SSH wrapper 同步校验该参数。

### 2026.07.03+build.4

- 跟随 PO0 发布批次对齐到 `po0-v2026.07.03.4`；本脚本无行为变化。

### 2026.07.03+build.3

- 跟随 PO0 发布批次对齐到 `po0-v2026.07.03.3`；本脚本无行为变化。

### 2026.07.03+build.2

- 跟随 PO0 发布批次对齐到 `po0-v2026.07.03.2`；本脚本无行为变化。

### 2026.07.03+build.1

- 跟随 PO0 发布批次对齐到 `po0-v2026.07.03.1`；本脚本无行为变化。

### 2026.07.02+build.10

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.10`；本脚本无行为变化。

### 2026.07.02+build.9

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.9`；本脚本无行为变化。

### 2026.07.02+build.8

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.8`；本脚本无行为变化。

### 2026.07.02+build.7

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.7`；本脚本无行为变化。

### 2026.07.02+build.6

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.6`；本脚本无行为变化。

### 2026.07.02+build.5

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.5`；本脚本无行为变化。

### 2026.07.02+build.4

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.4`；本脚本无行为变化。

### 2026.07.02+build.3

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.3`；本脚本无行为变化。

### 2026.07.02+build.2

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.2`；本脚本无行为变化。

### 2026.07.02+build.1

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.1`；本脚本无行为变化。

### 2026.07.01+build.8

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.01.8`；本脚本无行为变化。

### 2026.07.01+build.7

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.01.7`；本脚本无行为变化。

### 2026.07.01+build.6

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.01.6`；本脚本无行为变化。

### 2026.07.01+build.5

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.01.5`；本脚本无行为变化。

### 2026.07.01+build.4

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.01.4`；访问设备客户端更新后会迁移并清理默认旧 `po0-self-report*` 残留。

### 2026.07.01+build.3

- PO0 Outbound IP Report 客户端部署命令和下载源覆盖变量改用三端统一命名。
- 发布批次对齐到 `po0-v2026.07.01.3`。

### 2026.07.01+build.2

- 修正 CLI 帮助里的 PO0 主控部署说明，避免把 Release asset 下载命令描述成本地上传。
- 移除不存在的 `--show-client-deploy-commands tokens` 示例，改为索引 topic 和 `--worker-token-bundle`。
- Egern 部署命令输出统一使用 `source-id|host|port|user|script|token|identity|ttl`。

### 2026.06.28+build.2

- 跟随 PO0 Release asset 批次对齐到 build.2；本脚本无行为变化。

### 2026.06.28+build.1

- 跟随 PO0 Release asset 批次对齐到 build.1；本脚本无行为变化。

### 2026.06.25+build.12

- 跟随 PO0 Release asset 批次对齐到 build.12；本脚本无行为变化。

### 2026.06.25+build.11

- PO0 Bash 构建 / 检查工具在 git 中补齐 executable bit，Release workflow 仍保留显式 `bash` 调用。

### 2026.06.25+build.10

- Release 检查脚本改为显式用 `bash` 调用构建器，避免 GitHub runner 受文件 executable bit 影响。

### 2026.06.25+build.9

- 源码迁入按职责拆分的 `scripts/po0/relay/manager/src/` 模块；部署示例改为 Release asset 下载，旧 manager raw path 停用。

### 2026.06.25+build.8

- PO0 Release asset 脚本版本号与 `po0-v2026.06.25.8` 对齐，避免整包 tag 与脚本 `--version` 输出混淆。

### 2026.06.25+build.2

- Self-report 客户端部署命令补充 macOS 专用脚本下载入口。
- 脚本信息区补充 macOS Self-report 下载 URL。

### 2026.06.25+build.1

- 主菜单顶部新增脚本版本、构建标识、当前脚本、安装路径、下载 URL 和关键配置路径信息，便于确认当前运行版本。

### 2026.06.24+build.1

- PO0 可部署脚本默认下载源迁到 GitHub Release asset，并保留环境变量覆盖入口。
- LAN Worker、Self-report 部署命令改用 Release 下载地址；Egern 模块 raw 地址暂作为兼容白名单保留。

### 2026.06.23+build.2

- 从菜单使用 LAN Worker HTTP 更新 PO0 manager 成功后，按回车会重新打开新版菜单；命令行直接执行 `--upgrade-manager-from-lan` 仍保持更新后退出。

### 2026.06.23+build.1

- 动态来源 allowlist、DDNS/self-report/WebAuth/Egern/SSH report 统计和 DDNS 来源状态的读改写增加本地 `flock` 锁，降低并发上报时 TSV 状态互相覆盖的风险。
- 受限 SSH wrapper 只针对 `--resource-task-fail` 修复失败原因包含空格时的参数拆分；非法 action 仍按原白名单拒绝。
- Self-report PowerShell raw 下载示例增加 `-TimeoutSec 120`，Linux/Windows 示例继续展示秒级 canonical 间隔参数。

### 2026.06.22+build.7

- 移除 `ssh_report` 同源宽网段替换策略；`/24` 和 `/32` 现在统一作为 CIDR 条目保留，按 TTL 和每 `source_type + source-id` `12` 条上限裁剪。

### 2026.06.22+build.6

- 动态来源默认按 `source_type + source-id` 每组保留 `12` 个有效 CIDR，菜单总览和“来源 / IP 明细”显示每个 source-id 的 `n/12` 用量。
- `--ssh-ip-report` 新增第 6 个可选参数 `cidr-prefix`，仅允许 `32` 或 `24`；`24` 会规范化为 `/24`，`32` 保持 `/32`。
- Egern / ssh-report 默认 TTL 调整为 `43200` 秒（12 小时），受限 SSH wrapper 同步允许并校验 `cidr-prefix`。

### 2026.06.22+build.5

- 当前版本更新内容只显示本次版本条目；完整版本历史迁移到 `scripts/po0/relay/CHANGELOG.md`，避免脚本内 changelog 越积越长。

### 历史迁移条目（来自脚本内旧 changelog，版本未逐条记录）

- 修复 `--client-ip-report` 缺少必填参数时只打印用法但继续执行的问题。
- Client IP / Self-report 直连上报默认 TTL 统一为 43200 秒（12 小时），Egern / ssh-report 仍默认 21600 秒（6 小时）。
- DDNS 来源新增/无效 TTL 默认改为 43200 秒（12 小时），保留 60-86400 秒输入范围。
- WebAuth 上报 `expires-at` 增加 7 天防御性上限，避免误配造成超长放行。
- Self-report 部署命令示例的目标行 TTL 改为 43200 秒（12 小时）。
- 从 LAN Worker HTTP 更新 manager 的交互输入增加端口提示：入口不是 80 时必须在 URL 中写明 `:端口`。
- WebAuth 放行 TTL 默认从 3600 秒调整为 21600 秒（6 小时），部署命令同步输出 21600。
- Egern / ssh-report 放行 TTL 默认从 3600 秒调整为 21600 秒（6 小时），部署命令同步输出 21600。
- Self-report / client-ip 放行 TTL 默认从 3600 秒调整为 43200 秒（12 小时）。
- 新增从 LAN Worker HTTP 更新 PO0 manager：校验 resource token HMAC、sha256、脚本语法后原子替换主控脚本。
- 脚本 `--version` 输出改为参考 LAN Worker 的版本面板，并单独显示 build 构建标识。
- 修复当前 SSH 临时放行同一 `/32` 再次加入时只命中过期旧记录、不刷新过期时间的问题。
- PO0 受限 `authorized_keys` 备份改为按 passwd/getent 扫描用户 home，避免漏掉非 `/home` 路径的上报用户。
- 修复完整备份导出指定相对路径时可能写入临时目录并随清理丢失的问题；恢复 cron 时优先从备份的 cron block 识别旧脚本路径。
- 新增 PO0 全功能备份 / 导入恢复：默认导出 token、状态、资源任务、iplist/ipdb、resource inbox、wrapper、受限 `authorized_keys` 信息和脚本快照；导入默认只恢复配置/状态文件。
- PO0 导入新增显式恢复 flag：cron、systemd/nftables、`/etc/nftables.conf`、sysctl、受限 `authorized_keys` 需明确确认或使用 `--restore-all`。
- Self-report client 部署示例曾调整为更长的默认上报间隔，匹配客户端的长间隔支持。
- Self-report 部署示例改为 HTTPS 域名/Caddy 模式，访问设备默认上报到 `https://<SELF_REPORT_DOMAIN>/report`。
- Self-report HTTP 直连示例下沉为兼容模式，不再作为默认推荐路径。
- 重排源 IP 白名单菜单：动态来源缓存维护、来源 IP 学习与候选提升、被阻挡访问日志拆成独立子菜单，减少主菜单裸露维护动作。
- 中转机参数新增“本机名称/导出前缀”，导出规则默认文件名可带 PO0XX- 这类主机前缀。
- 转发规则列表的“回程模式”改为直接显示“内网回源 / 公网出口 / 透明转发”，避免把 `relay_lan` 简写成 `lan` 造成理解成本。
- 新增 `--changelog`，用于 scp 上传更新后查看当前版本更新内容。
- 内网资源更新任务菜单新增“查看 PO0 定时创建状态”，明确 PO0 只创建 pending 任务、LAN Worker 负责领取执行。
- 脚本版本菜单改为版本信息面板，并显示当前版本更新内容。
- 状态面板和资源任务创建计划摘要增加彩色状态提示。

## po0-lan-worker-client

### 2026.09.05+build.5

- 对齐本轮 OpenWrt 旁路网关支持的发布版本；本脚本行为未变。

### 2026.09.05+build.4

- 修复发布包校验清单，避免整包校验失败；本脚本功能沿用 `2026.09.05+build.3`。

### 2026.09.05+build.3

- 适配非 Windows CI 的 ACL 测试隔离；本脚本功能沿用 `2026.09.05+build.2`。

### 2026.09.05+build.2

- CI 跨平台兼容性修复；本脚本功能沿用 `2026.09.05+build.1`。

### 2026.09.05+build.1

- 新增默认关闭的官方防火墙双通道：每个官方账号最多 5 个槽位，先 GET 读取状态，只有当前出口缺失或固定槽位不匹配时才 POST。
- 官方 token 仅保存到权限 600 的设置文件，官方尝试固定每 600 秒一次，并与 DDNS、资源任务、WebAuth 和 Self-report 的原有计划独立。
- 官方车道先执行且与原有车道分别记录结果；主 OpenWrt 才能通过 mwan3 绑定 wan1/wan2，普通 LAN Worker 继续使用本机默认出口。

### 2026.08.30+build.5

- 跟随 PO0 发布批次对齐到 2026.08.30+build.5；LAN Worker 无行为变化。

### 2026.08.30+build.4

- 跟随 PO0 发布批次对齐到 2026.08.30+build.4；LAN Worker 无行为变化。

### 2026.08.30+build.1

- 跟随 PO0 发布批次对齐到 2026.08.30+build.1；LAN Worker 无行为变化。

### 2026.08.29+build.1

- 跟随 PO0 发布批次对齐到 2026.08.29+build.1；LAN Worker 无行为变化。

### 2026.07.23+build.1

- 跟随 PO0 发布批次对齐到 `2026.07.23+build.1`；LAN Worker 无行为变化。

### 2026.07.22+build.2

- Stash HTTPS 上报不再根据客户端提交的网络类型放大到 `/24`，蜂窝、Wi-Fi 和未知网络统一按 `/32` 写入 PO0。
- Stash 客户端网络探测失败改记为 `unknown`，服务端仍强制使用 `/32`。
- Self-report 服务安装会复用已有 secret，旧自动化显式传入空 secret 时也不会覆盖已加载的值；仅在确实缺失时自动生成并保存。旧 `/report` 在 secret 为空时返回 503，不再以无鉴权模式接收上报。
- 无 `flock` 环境释放 LAN Worker 配置锁后不再误把当前 shell 的后续错误输出重定向到空设备。

### 2026.07.20+build.1

- 新增 Stash 专用 `POST /stash-report/v1` JSON 接口，复用现有 Self-report Bearer secret，并按网络类型把蜂窝地址上报为 `/24`、Wi-Fi/未知网络上报为 `/32`。
- 校验来源 ID、公网 IPv4、网络类型、时间戳和请求 ID；请求时间漂移限制为 10 分钟，同一后台进程对请求 ID 防重 10 分钟。
- Caddy 托管配置新增 Stash 路径；旧 `/report` 接口和返回格式保持兼容。
- 正式链路使用 LAN Worker；另提供默认关闭、只监听 PO0 `127.0.0.1:8790` 的 Stash SSH loopback receiver 作为备用 PoC。

### 2026.07.03+build.4

- 跟随 PO0 发布批次对齐到 `po0-v2026.07.03.4`；LAN Worker 客户端无行为变化。

### 2026.07.03+build.3

- 跟随 PO0 发布批次对齐到 `po0-v2026.07.03.3`；LAN Worker 客户端无行为变化。

### 2026.07.03+build.2

- 跟随 PO0 发布批次对齐到 `po0-v2026.07.03.2`；LAN Worker 客户端无行为变化。

### 2026.07.03+build.1

- 跟随 PO0 发布批次对齐到 `po0-v2026.07.03.1`；LAN Worker 客户端无行为变化。

### 2026.07.02+build.10

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.10`；LAN Worker 客户端无行为变化。

### 2026.07.02+build.9

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.9`；LAN Worker 客户端无行为变化。

### 2026.07.02+build.8

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.8`；LAN Worker 客户端无行为变化。

### 2026.07.02+build.7

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.7`；LAN Worker 客户端无行为变化。

### 2026.07.02+build.6

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.6`；LAN Worker 客户端无行为变化。

### 2026.07.02+build.5

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.5`；LAN Worker 客户端无行为变化。

### 2026.07.02+build.4

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.4`；LAN Worker 客户端无行为变化。

### 2026.07.02+build.3

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.3`；LAN Worker 客户端无行为变化。

### 2026.07.02+build.2

- Self-report `/report` 和 WebAuth 多 PO0 目标上报改为并发 SSH，避免慢目标耗时串行累加导致访问设备 HTTP 超时。
- HTTP 客户端提前断开时只记录简短警告，不再在 journal 中输出 BrokenPipe traceback。

### 2026.07.02+build.1

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.1`；LAN Worker `/report` 协议保持兼容，本脚本无行为变化。

### 2026.07.01+build.8

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.01.8`；LAN Worker `/report` 协议保持兼容，本脚本无行为变化。

### 2026.07.01+build.7

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.01.7`；LAN Worker `/report` 协议保持兼容，本脚本无行为变化。

### 2026.07.01+build.6

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.01.6`；LAN Worker `/report` 协议保持兼容，本脚本无行为变化。

### 2026.07.01+build.5

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.01.5`；LAN Worker `/report` 协议保持兼容，本脚本无行为变化。

### 2026.07.01+build.4

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.01.4`；LAN Worker `/report` 协议保持兼容。

### 2026.07.01+build.3

- 跟随 PO0 Release asset 批次对齐到 build.3；LAN Worker `/report` 协议保持兼容。

### 2026.07.01+build.2

- 跟随 PO0 Release asset 批次对齐到 build.2；本脚本无行为变化。

### 2026.06.28+build.2

- Self-report 接收端成功响应补充 `target_names`，便于客户端摘要显示具体 PO0 目标。

### 2026.06.28+build.1

- 跟随 PO0 Release asset 批次对齐到 build.1；本脚本无行为变化。

### 2026.06.25+build.12

- 跟随 PO0 Release asset 批次对齐到 build.12；本脚本无行为变化。

### 2026.06.25+build.11

- PO0 Bash 构建 / 检查工具在 git 中补齐 executable bit，Release workflow 仍保留显式 `bash` 调用。

### 2026.06.25+build.10

- Release 检查脚本改为显式用 `bash` 调用构建器，避免 GitHub runner 受文件 executable bit 影响。

### 2026.06.25+build.9

- 源码迁入按职责拆分的 `scripts/po0/relay/lan-worker/src/` 模块；自更新和 manager mirror 继续默认使用 Release asset，旧 LAN Worker raw path 停用。

### 2026.06.25+build.8

- PO0 Release asset 脚本版本号与 `po0-v2026.06.25.8` 对齐，避免整包 tag 与脚本 `--version` 输出混淆。

### 2026.06.25+build.2

- Self-report server 和目标权限检查在转发到 PO0 前会规范 source / identity，避免 macOS 主机名含空格被 PO0 restricted wrapper 拆坏。
- Self-report 502 返回正文继续保留 PO0 目标的具体失败原因，便于客户端排错。

### 2026.06.25+build.1

- 跟随 PO0 2026-06-25 发布刷新 LAN Worker 版本，避免 latest 更新后仍显示旧脚本版本。
- 自安装、自更新和 PO0 manager 更新镜像继续默认使用 GitHub Release asset。

### 2026.06.24+build.1

- 默认自安装、自更新和 PO0 manager 更新镜像上游迁到 GitHub Release asset。
- 新增 `PO0_LAN_CLIENT_DOWNLOAD_URL` / `PO0_MANAGER_DOWNLOAD_URL` 覆盖入口，便于测试和回滚。

### 2026.06.23+build.1

- `targets.tsv`、`settings.env`、DDNS stats、resource stats/events 的本地写入增加配置目录级 `.po0-lan-client.lock`，避免菜单保存、cron 运行和资源轮询并发覆盖本机状态。
- 默认 PO0 manager SSH 调用改为走 timeout helper，新增 `PO0_REMOTE_MANAGER_TIMEOUT_SECONDS`，默认 `30` 秒；资源上传/导入仍使用各自的长超时变量。
- 自安装和 `--upgrade-self` 的 raw 下载增加连接/总时长 timeout；备份仍只 staging 明确文件和 `ssh-key-*`，不会包含锁文件。

### 2026.06.22+build.11

- DDNS resolver 默认上报间隔调整为 `3600` 秒，新增 `--ddns-interval-seconds` / `PO0_DDNS_INTERVAL_SECONDS`，旧分钟参数继续兼容。
- WebAuth 默认放行 TTL 调整为 `43200` 秒，和 Self-report 默认 TTL 保持一致。

### 2026.06.22+build.10

- 更新内容显示只输出当前版本条目；完整版本历史迁移到 `scripts/po0/relay/CHANGELOG.md`，避免脚本内 changelog 越积越长。

### 2026.06.22+build.9

- 基础信息和 `--version` 不再显示资源上传实现细节；manager stdin 上传说明保留在资源任务文档和排错段落。
- 从菜单更新脚本成功后会先停留显示安装路径、版本变化和更新内容，按回车后再打开新版菜单。

### 历史迁移条目（来自脚本内旧 changelog，版本未逐条记录）

- Self-report 子菜单的 source / TTL 入口改为只维护 Self-report 字段，不再同时提示或修改 WebAuth 字段。
- Self-report 后台服务摘要会提示 systemd unit 中仍显式保留的 TTL 覆盖值，便于发现旧服务未刷新。
- 读取旧安装的本机 `settings.env` 时，把遗留默认 Self-report TTL 3600 迁移为 43200、WebAuth TTL 3600 迁移为 21600；目标行显式 TTL 不自动改写。
- Self-report 放行 TTL 默认改为 43200 秒（12 小时），WebAuth 默认继续保持 21600 秒（6 小时）。
- Self-report / WebAuth TTL 统一限制在 60-604800 秒，避免误配造成过短或超长放行。
- 安装 WebAuth systemd 服务前检查可用 PO0 目标，避免写入空参数后反复重启失败。
- PO0 manager HTTP 更新镜像的 Caddy 入口统一改为端口级监听，同一端口同时支持域名和直接 IP 访问。
- PO0 manager HTTP 更新镜像默认公网入口改为 2333，并支持直接使用 IP[:端口]；公网入口由 Caddy 监听端口级 HTTP 站点后反代到本机后端。
- WebAuth 放行 TTL 默认从 3600 秒调整为 21600 秒（6 小时）。
- 新增 PO0 manager HTTP 更新镜像：LAN Worker 通过 HTTPS 拉取 GitHub 脚本，并用 resource token 为 PO0 HTTP 拉取响应签名。
- 兼容旧安装：`settings.env` 不存在或字段为空时，从已安装的 Self-report/WebAuth systemd unit 回填 secret、监听地址、目标和 token，避免升级后导出空 secret。
- 修复完整备份导出指定相对路径时可能写入临时目录并随清理丢失的问题；恢复 cron 时优先从备份的 cron block 识别旧脚本路径；Caddy import 跟随当前 snippet 目录且恢复权限改为 644。
- 新增 LAN Worker 完整备份 / 导入恢复：默认导出 Token、SSH 私钥、`SELF_REPORT_SECRET` 和状态文件；导入默认只恢复配置/状态/密钥，cron、systemd、Caddy 需显式 flag 或 `--restore-all`。
- 新增本机 `settings.env` 持久化 Self-report secret、监听地址、HTTPS/Caddy、Worker ID、资源任务超时和轮询间隔，避免升级脚本后重新生成 secret。
- Self-report secret 设置完成后同时输出 Linux/macOS/OpenWrt export 和 Windows PowerShell 环境变量示例。
- 修复 Self-report HTTPS Caddy snippet 使用 `respond 404` 时被 directive order 提前执行，导致 `/health` 和 `/report` 返回 404 的问题。
- 修复 Self-report HTTPS 域名校验对合法域名静默失败，导致菜单未写入 Caddy 配置的问题。
- Self-report 新增 HTTPS 域名模式，可在菜单配置 Caddy 自动证书并将后端切到 `127.0.0.1:8788`。
- Self-report 默认监听收紧为 `127.0.0.1:8788`；公网入口默认通过 HTTPS 域名/Caddy。
- Self-report 后台服务安装/更新后强制 restart，确保旧的失败 unit 立即被新 `ExecStart` 覆盖。
- Self-report 后台服务安装时 secret 为空则省略参数，避免 systemd unit 因空参数反复重启失败。
- Self-report 后台服务安装前检查可用 PO0 目标，避免写入空参数后反复重启失败。
- Self-report 菜单新增后台服务状态、最近日志和实时日志入口。
- Self-report 主菜单入口改为配置子菜单，避免按菜单项后直接进入前台监听造成误解。
- Self-report 子菜单新增监听地址、secret 生成/修改、后台服务安装和前台启动入口。
- 资源任务本机检查间隔默认改为 1440 分钟，可设置到 10080 分钟。
- DDNS 菜单新增目标 / 上报计划入口，说明 PO0 DDNS TTL 设置位置并可直接更新本机 DDNS 上报计划。

## Egern SSH IP Report

### 2026.09.05

- 官方防火墙通道默认关闭；Egern 用 DIRECT 先 GET 查询当前出口、额度、白名单和固定槽位，仅缺失或槽位不符时才 POST，状态动作只读且不显示 token。
- SSID 命中时官方和 SSH 两条车道一起跳过；强制运行只绕过本地 due/SSID guard，仍遵守官方 GET-first。官方检查固定 600 秒，与原有 SSH 上报周期/TTL 独立，失败可部分完成。
- 指定 wan1/wan2 只属于主 OpenWrt 的 mwan3 绑定；实现参考 kelenetwork/po0fw（MIT），不绑定 Chicksure 专属服务。

### 2026-07-26

- 新增 Egern 原生 `ctx.storage` 上报配置持久化，保存 PO0 目标、SSH 认证、report token、周期、SSID guard、IP 探测和通知选项；不依赖 BoxJS/Relay，换主配置后继续使用本机保存值。
- 模块新增“保存本机 PO0 上报配置”和“清除本机 PO0 上报配置”；已有完整旧版环境变量会自动迁移，本机保存值存在后成为唯一运行时配置源。
- 未保存且环境变量不完整时，schedule/network 自动任务静默跳过，不做 HTTP/SSH/通知；手动、状态页和 Widget 提示先保存配置，使模块可安全默认启用。

### 2026-07-01

- 新增 `SKIP_WIFI_SSIDS` 本地跳过 guard；定时/网络变化自动触发命中当前 Wi-Fi SSID 时，不探测公网 IP、不执行 SSH 上报、不通知，只写 Egern 本地状态/日志并保留上一轮成功状态用于 Widget。
- SSID 列表使用英文分号分隔并精确大小写匹配；读取不到 SSID、非 Wi-Fi、手动运行、状态页和 Widget 刷新都会继续上报；SSID 不上传到 PO0 或 LAN Worker，也不新增 `--ssh-ip-report` 协议字段。

### 2026-06-23

- 默认公网 IPv4 探测列表删除 12306 grip 接口，继续以 IP9 为首选并轮询其它国内接口和 `myip.ipip.net`。
- 状态页 / Widget 优先复用 IP9、163、126、myip.ipip 等 IP 查询接口返回的归属地 / 运营商信息，拿不到时才额外查询。

## po0-wan-probe（OpenWrt）

### 2026.09.05+build.5

- 对齐本轮 OpenWrt 旁路网关支持的发布版本；本脚本行为未变。

### 2026.09.05+build.4

- 修复发布包校验清单，避免整包校验失败；本脚本功能沿用 `2026.09.05+build.3`。

### 2026.09.05+build.3

- 适配非 Windows CI 的 ACL 测试隔离；本脚本功能沿用 `2026.09.05+build.2`。

### 2026.09.05+build.2

- CI 跨平台兼容性修复；本脚本功能沿用 `2026.09.05+build.1`。

### 2026.09.05+build.1

- 跟随 PO0 发布批次对齐脚本版本；探针行为未变。
- `po0-wan-probe.apk` 继续使用 `2026.08.30-r5`，不随 outbound APK 的版本 bump。

## po0-outbound-ip-report（Linux/OpenWrt）

### 2026.09.05+build.5

- 支持在旁路 OpenWrt 通过本机源地址选择官方 WAN1、WAN2 或双 WAN；保留主路由本机 WAN 模式。

### 2026.09.05+build.4

- 修复发布包校验清单，避免整包校验失败；本脚本功能沿用 `2026.09.05+build.3`。

### 2026.09.05+build.3

- 适配非 Windows CI 的 ACL 测试隔离；本脚本功能沿用 `2026.09.05+build.2`。

### 2026.09.05+build.2

- CI 跨平台兼容性修复；本脚本功能沿用 `2026.09.05+build.1`。

### 2026.09.05+build.1

- 增加默认关闭的官方防火墙双通道：每个账号最多 5 个槽位，先 GET 读取状态，缺失或固定槽位不符才 POST；官方状态包含额度、当前出口和槽位，但不显示 token。
- 官方尝试固定每 600 秒一次，普通 LAN Worker 上报继续使用自己的计划和 TTL；官方先执行，Linux/OpenWrt 两条结果独立，允许部分失败。
- 访问设备命中 SSID 跳过列表时两条通道一起跳过；`--force-report` 只绕过本地 due/SSID guard。主 OpenWrt 才通过 mwan3 选择 wan1/wan2，普通 Linux 使用默认出口。

### 2026.08.30+build.5

- OpenWrt procd 自动任务状态新增完成时间；手动与自动上报统一记录开始时间、完成时间和退出码。
- LuCI 结果卡片改用中文 24 小时制，分别显示任务开始、任务完成、执行耗时和页面刷新时间。
- 兼容没有完成时间的旧状态记录，不伪造完成时间或耗时。

### 2026.08.30+build.4

- OpenWrt LuCI 手动测试改为后台任务加状态轮询，避免双 WAN 上报超过 20 秒触发 XHR 超时。
- 操作结果改为状态卡片，显示标题、本地更新时间、逐 WAN 结果与汇总，不再输出原始响应文本框。
- 明文 HTTP Worker 开关移到高级设置并标记为不推荐；HTTPS Worker 保持默认安全路径。
- OpenWrt APK 仍只使用 procd 调度，不安装或管理 cron。

### 2026.08.30+build.1

- 上游 OpenWrt 探针拆为独立 `po0-wan-probe.sh`，不再把完整上报客户端放入 CGI 目录。
- 新探针优先读取接口公网 IPv4，必要时才绑定对应 WAN 调用外部检测，并提供 `wan=all` 批量 JSON。
- 上报器优先消费批量结果并兼容旧文本接口；每个 WAN 继续使用独立来源 ID，部分失败继续处理其它 WAN。
- 新增 `po0-wan-probe.apk` 与 `po0-outbound-ip-report.apk` 的 UCI、procd 和 LuCI 集成。
- 探针和 LAN Worker 请求保持普通网络请求，不读取、修改或验证 Mihomo/OpenClash 配置。

### 2026.08.29+build.1

- 新增可重复的 --wan <OpenWrt逻辑接口>，可选择一条或多条 WAN，并绑定各自 l3_device 探测公网 IPv4。
- 新增 --wan all，自动枚举全部已启用的 mwan3 WAN；每条 WAN 使用独立来源 ID 分别续期。
- 多 WAN 模式会继续处理其它 WAN，并在任一 WAN 失败时返回非零状态和成功/失败汇总。
- 新增上游 OpenWrt 内网 HTTP WAN 探针模式；完整客户端可留在网关，探针只绑定各 WAN 查询并返回公网 IPv4。

### 2026.07.23+build.1

- 跟随 PO0 发布批次对齐到 `2026.07.23+build.1`；Linux/OpenWrt 客户端无行为变化。

### 2026.07.22+build.2

- 跟随 PO0 发布批次对齐到 `2026.07.22+build.2`；Linux/OpenWrt 客户端无行为变化。

### 2026.07.20+build.1

- 跟随 PO0 发布批次对齐到 `po0-v2026.07.20.1`；Linux/OpenWrt 客户端无行为变化。

### 2026.07.03+build.4

- 跟随 PO0 发布批次对齐到 `po0-v2026.07.03.4`；Linux/OpenWrt 客户端无行为变化。

### 2026.07.03+build.3

- 跟随 PO0 发布批次对齐到 `po0-v2026.07.03.3`；Linux/OpenWrt 客户端无行为变化。

### 2026.07.03+build.2

- 新安装的 cron 托管标记改为 `OUTBOUND_IP_REPORT_BEGIN` / `OUTBOUND_IP_REPORT_END`；旧 `PO0_OUTBOUND_IP_REPORT_*` 和 `PO0_SELF_REPORT_*` 标记继续识别并在更新时迁移。
- 定时上报安装输出使用更简洁的 `Outbound IP Report` 名称。

### 2026.07.03+build.1

- 自更新后先检测 cron 是否已指向标准脚本路径；没有漂移时不再重复刷新定时任务。
- 菜单和状态页清理标准路径状态、定时任务状态等用户可见文案，减少工程表达。

### 2026.07.02+build.10

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.10`；Linux/OpenWrt 客户端无行为变化。

### 2026.07.02+build.9

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.9`；Linux/OpenWrt 客户端无行为变化。

### 2026.07.02+build.8

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.8`；Linux/OpenWrt 客户端无行为变化。

### 2026.07.02+build.7

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.7`；Linux/OpenWrt 客户端无行为变化。

### 2026.07.02+build.6

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.6`；Linux/OpenWrt 客户端无行为变化。

### 2026.07.02+build.5

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.5`；Linux/OpenWrt 客户端无行为变化。

### 2026.07.02+build.4

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.4`；Linux/OpenWrt 客户端无行为变化。

### 2026.07.02+build.3

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.3`；Linux/OpenWrt 客户端无行为变化。

### 2026.07.02+build.2

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.2`；Linux/OpenWrt 客户端无行为变化。

### 2026.07.02+build.1

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.1`；Linux/OpenWrt 客户端无行为变化。

### 2026.07.01+build.8

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.01.8`；Linux/OpenWrt 客户端无行为变化。

### 2026.07.01+build.7

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.01.7`；Linux/OpenWrt 客户端无行为变化。

### 2026.07.01+build.6

- SSID 跳过列表解析不再使用 Bash 数组，避免旧 Bash + `set -u` 下触发 `items[@] unbound variable`；读取 SSID 失败仍继续上报，跳过时仍只写本地日志摘要。

### 2026.07.01+build.5

- 新增 SSID 本地跳过上报配置；命中当前 SSID 时只写本地跳过日志摘要，不上传 SSID，也不改变 LAN Worker `/report` 或 PO0 协议。
- SSID 列表用英文分号分隔并做精确匹配；读取当前 SSID 失败时继续上报；手动运行命中跳过规则时询问是否强制继续。

### 2026.07.01+build.4

- 更新和旧路径自愈后会迁移默认旧配置、旧日志、旧 IP 探测状态和旧 cron，并删除默认旧 `po0-self-report` 命令残留。
- 旧 `PO0_SELF_REPORT_*` / `SELF_REPORT_*` 环境变量和旧 CLI alias 继续兼容；显式自定义配置或安装路径不会被自动 legacy 清理误删。

### 2026.07.01+build.3

- 本机命令、默认配置、默认日志、IP 探测状态和 cron marker 统一迁移到 `po0-outbound-ip-report` / `PO0 Outbound IP Report`。
- 旧 `po0-self-report` 命令、配置、日志、状态和 env / CLI alias 仅作为 legacy 迁移入口继续识别；保存和安装默认写入 canonical 路径。
- 旧默认 `INSTALL_PATH=.../po0-self-report` 会规范化到 canonical 路径；显式自定义安装路径继续保留。
- 旧路径自愈和自更新重开新版菜单时保留旧配置 fallback，不会把新进程强制指向不存在的 canonical 配置。

### 2026.07.01+build.2

- `--help` 明确列出 self-report 配置文件优先级，包括 `XDG_CONFIG_HOME` 和当前目录兜底。

### 2026.06.28+build.2

- 上报成功摘要优先显示 LAN Worker 返回的具体 PO0 目标名。
- 连接旧 LAN Worker 时，目标摘要简化为“PO0 目标：N 个”。

### 2026.06.28+build.1

- 上报成功摘要会显示 LAN Worker 已成功转发的 PO0 目标数量。
- 定时上报状态页会从旧日志的 LAN Worker 返回体中提取 `targets=N`，并合并到对应完成结果。

### 2026.06.25+build.12

- 跟随 PO0 Release asset 批次对齐到 build.12；Linux/OpenWrt 客户端无行为变化。

### 2026.06.25+build.11

- PO0 Bash 构建 / 检查工具在 git 中补齐 executable bit，Release workflow 仍保留显式 `bash` 调用。

### 2026.06.25+build.10

- Release 检查脚本改为显式用 `bash` 调用构建器，避免 GitHub runner 受文件 executable bit 影响。

### 2026.06.25+build.9

- 源码迁入 `scripts/po0/relay/self-report/linux/src/`；自更新继续默认使用 Release asset，旧 Linux/OpenWrt self-report raw path 停用。

### 2026.06.25+build.8

- 版本号与 `po0-v2026.06.25.8` 对齐；定时上报状态页的最近结果保持短缩进摘要。

### 2026.06.25+build.7

- 定时上报状态页的最近结果改为短缩进摘要，避免日志续行被面板值列顶到过深位置；原始 cron 日志路径和 tail 命令继续保留。

### 2026.06.25+build.6

- Linux/OpenWrt 客户端恢复为 cron-only，不再包含 macOS 专用定时逻辑。
- 保留 `--save-config --menu` 组合，首次配置可保存后直接进入菜单确认；macOS 改用专用脚本。

### 2026.06.25+build.5

- 支持 `--save-config --menu` 组合，首次配置可保存后直接进入菜单确认。
- macOS 缺少 `crontab` 时，安装 / 暂停 / 删除定时上报会自动使用用户级 launchd LaunchAgent。

### 2026.06.25+build.4

- Source ID 和上报 identity 会规范成 PO0 restricted wrapper 可安全解析的无空格 token，修复 macOS 主机名含空格导致 LAN Worker 返回 502。
- 失败时保留 LAN Worker 返回正文，方便看到 PO0 wrapper 的具体拒绝原因。

### 2026.06.25+build.3

- 修复 macOS 默认 Bash 3.2 不支持 Bash 4 小写替换语法导致菜单和配置提示报错的问题，并避免依赖外部 `tr`。
- 补齐菜单首页标题 helper，避免打开 Linux/macOS self-report 菜单时报 `print_title` 缺失。

### 2026.06.25+build.1

- 菜单首页改为精简状态面板，避免不能清屏时反复堆叠完整配置块。
- 版本和菜单显示执行来源、build、配置文件、下载 URL、安装路径和定时上报短状态。
- 定时上报摘要改为解析实际 crontab 托管块；暂停 / 恢复失败时会尝试回滚配置暂停标记。

### 2026.06.24+build.1

- 默认安装和自更新下载源迁到 GitHub Release asset。
- 新增 `PO0_SELF_REPORT_DOWNLOAD_URL` 覆盖入口，便于测试和回滚。

### 2026.06.23+build.11

- 上报 LAN Worker 的 `curl` 增加 `--connect-timeout 10 --max-time 30`，raw 下载增加 `--connect-timeout 15 --max-time 120`。
- 公网 IPv4 探测的 `wget` fallback 和 raw 下载 fallback 增加 `-T` 超时，兼容 BusyBox/OpenWrt。

### 2026.06.23+build.10

- 菜单新增“卸载本客户端”，可删除本脚本管理的 cron 和本机安装脚本，并可选删除配置与日志。

### 2026.06.23+build.9

- 默认公网 IPv4 探测列表删除 12306 grip 接口，继续以 IP9 为首选并轮询其它国内接口和 `myip.ipip.net`。

### 2026.06.22+build.8

- 新增 `--interval-seconds` / `PO0_SELF_REPORT_INTERVAL_SECONDS`，默认按 `3600` 秒安装定时上报，旧分钟参数继续兼容。
- 配置文件新增 `INTERVAL_SECONDS`，菜单、状态和安装输出统一用秒显示上报间隔。

### 2026.06.22+build.7

- Linux/OpenWrt 默认从 hostname + machine-id/MAC 生成 Source ID，并用设备名作为 Identity，避免多台设备都落到 `self-report` 来源。

### 2026.06.22+build.6

- 菜单更新脚本成功后先停留显示安装路径、版本变化和更新内容，按回车后再打开新版菜单。
- 菜单“安装 / 更新定时上报”会直接提示上报间隔；状态面板统一显示“每 N 分钟”。

### 2026.06.22+build.5

- 修复从已安装路径再次安装 / 更新定时上报时，脚本复制到自身导致 cron 安装中止的问题。

### 2026.06.22+build.3

- 当前版本更新内容只显示本次版本条目；完整版本历史迁移到 `scripts/po0/relay/CHANGELOG.md`，避免脚本内 changelog 越积越长。

### 历史迁移条目（来自脚本内旧 changelog，版本未逐条记录）

- 放行 TTL 状态说明跟随 LAN Worker Self-report 默认值更新为 43200 秒。
- 修复 Self-report 客户端配置面板和菜单列对齐。
- 新增从 GitHub 更新脚本入口，并在更新后显示版本变化和更新内容。
- 新增 `--version` 和 `--changelog` 只读入口。

## po0-outbound-ip-report（macOS）

### 2026.09.05+build.5

- 对齐本轮 OpenWrt 旁路网关支持的发布版本；本脚本行为未变。

### 2026.09.05+build.4

- 修复发布包校验清单，避免整包校验失败；本脚本功能沿用 `2026.09.05+build.3`。

### 2026.09.05+build.3

- 适配非 Windows CI 的 ACL 测试隔离；本脚本功能沿用 `2026.09.05+build.2`。

### 2026.09.05+build.2

- CI 跨平台兼容性修复；本脚本功能沿用 `2026.09.05+build.1`。

### 2026.09.05+build.1

- 增加默认关闭的官方防火墙双通道；macOS 通过本机默认出口先 GET 状态，当前出口缺失或固定槽位不匹配时才 POST，官方固定 600 秒并与原有 SSH 上报周期/TTL 独立。
- 自动 SSID 命中时官方和原有上报一起跳过；`--force-report` 只绕过本地 due/SSID guard，状态页仍只读 GET，失败可保留另一车道结果。

### 2026.08.30+build.5

- 跟随 PO0 发布批次对齐到 2026.08.30+build.5；macOS 客户端无行为变化。

### 2026.08.30+build.4

- 跟随 PO0 发布批次对齐到 2026.08.30+build.4；macOS 客户端无行为变化。

### 2026.08.30+build.1

- 跟随 PO0 发布批次对齐到 2026.08.30+build.1；macOS 客户端无行为变化。

### 2026.08.29+build.1

- 跟随 PO0 发布批次对齐到 2026.08.29+build.1；macOS 客户端无行为变化。

### 2026.07.23+build.1

- 跟随 PO0 发布批次对齐到 `2026.07.23+build.1`；macOS 客户端无行为变化。

### 2026.07.22+build.2

- 跟随 PO0 发布批次对齐到 `2026.07.22+build.2`；macOS 客户端无行为变化。

### 2026.07.20+build.1

- 跟随 PO0 发布批次对齐到 `po0-v2026.07.20.1`；macOS 客户端无行为变化。

### 2026.07.03+build.4

- 跟随 PO0 发布批次对齐到 `po0-v2026.07.03.4`；macOS 客户端无行为变化。

### 2026.07.03+build.3

- 跟随 PO0 发布批次对齐到 `po0-v2026.07.03.3`；macOS 客户端无行为变化。

### 2026.07.03+build.2

- 新安装的 launchd label 改为 `outbound-ip-report`；旧 `fr.schweppes.po0-outbound-ip-report` / `fr.schweppes.po0-self-report` 继续识别并在更新时迁移。
- cron fallback 托管标记改为 `OUTBOUND_IP_REPORT_BEGIN` / `OUTBOUND_IP_REPORT_END`，定时安装输出使用更简洁的 `Outbound IP Report` 名称。

### 2026.07.03+build.1

- 自更新后先检测 launchd / cron 是否已指向标准脚本路径；没有漂移时不再重复刷新定时任务。
- 菜单和状态页清理标准路径状态、定时任务状态等用户可见文案，减少工程表达。

### 2026.07.02+build.10

- macOS Wi-Fi SSID 读取改为 Helper-only：不再调用 `networksetup`、`ipconfig`、`airport` 或 `wdutil` fallback，避免 shell 环境稳定返回 `redacted` 时浪费时间。
- 未安装或未授权 Helper 时继续 fail-open；需要读取 SSID 时通过 `--request-location-permission` 创建并授权 `PO0 Location Permission Helper.app`。

### 2026.07.02+build.9

- 进一步优化 Wi-Fi SSID 读取速度：系统命令返回 `redacted` / `<redacted>` 后直接转 `PO0 Location Permission Helper.app`，不再继续尝试较慢的非 Helper fallback。
- Helper 区分授权请求和普通探测；`--request-location-permission` 保留较长等待预算，普通 SSID 探测使用更短等待预算以减少菜单和状态页卡顿。

### 2026.07.02+build.8

- 优化 `PO0 Location Permission Helper.app` 的读取速度：已授权时在等待循环里每 0.2 秒读取一次 SSID，读到后立即返回，不再固定等完整授权兜底时间。
- Helper schema 提升后会重建旧 Helper；首次授权或重建仍可能较慢，后续已授权读取应明显更快。

### 2026.07.02+build.7

- 修复 `PO0 Location Permission Helper.app` 仍可能通过 `open` 参数传递触发 AppleScript applet 参数类型转换错误 `-1700` 的路径。
- Helper 改为从 bundle `Resources/po0-location-helper-output.path` 读取输出文件路径，输出写入改用本地 `/usr/bin/printf`，并提升 Helper schema 以强制重建旧 Helper。

### 2026.07.02+build.6

- 修复 `PO0 Location Permission Helper.app` 触发定位授权时可能出现的 AppleScript 类型转换错误 `-1700`。
- Helper AppleScript 不再把 CoreLocation/CoreWLAN 返回值硬转为 `boolean` / `integer` / `real`，输出改用 `NSString writeToFile`；Helper schema 提升后会重建旧 Helper。

### 2026.07.02+build.5

- 新增 `--delete-location-permission-helper` / `--remove-location-helper`，并在菜单维护区加入 `11) 删除定位权限 Helper`；原 `卸载本客户端` 顺延为 `12`。
- 删除 Helper 只移除本地 `PO0 Location Permission Helper.app`，不会修改 macOS 定位授权 / TCC 记录；卸载客户端时会顺带清理该 Helper。删除前会校验路径和 bundle 身份，避免误删其它目录或 app。

### 2026.07.02+build.4

- `--request-location-permission` 改为创建并打开 `PO0 Location Permission Helper.app`，由带稳定 `CFBundleIdentifier`、定位用途声明和可选 ad-hoc 签名的 Helper 触发 macOS 定位权限请求；不再依赖裸 `osascript` 或 Terminal/iTerm 出现在定位服务列表里。
- Helper 授权后会在本机通过 CoreWLAN 读取当前 Wi-Fi SSID，并作为 `--show-wifi-ssid` / SSID 跳过 guard 的 fallback；SSID 仍不上传到 LAN Worker 或 PO0，读取失败继续 fail-open。

### 2026.07.02+build.3

- Wi-Fi SSID 权限诊断统一把 `redacted` / `<redacted>` 归类为 macOS 隐私权限隐藏，不再让用户在状态和诊断说明之间看到两套口径。
- `--diagnose-wifi-ssid` 会输出可执行的定位服务设置入口；当时新增的 `--request-location-permission` 会尝试触发运行环境的定位权限弹窗，并集成到菜单 `9) Wi-Fi SSID 权限诊断`；保留 `--open-location-services` 系统设置跳转；不自动授予权限、不写 TCC、不使用 `sudo` / `tccutil`。

### 2026.07.02+build.2

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.2`；macOS 客户端无行为变化。

### 2026.07.02+build.1

- 当前 Wi-Fi SSID 探测会把 `redacted` / `<redacted>` 视为 macOS 隐私权限隐藏并 fail-open 继续上报，不再误当真实 SSID 或命中跳过列表。
- 新增 `--diagnose-wifi-ssid` 和菜单“Wi-Fi SSID 权限诊断”，提示到系统设置为当前终端或 launchd 运行环境授权定位服务；脚本不会自动获取或修改系统权限。

### 2026.07.01+build.8

- 安装 / 更新本机 `po0-outbound-ip-report` 命令后会检查安装目录是否在当前 `PATH` 中；菜单安装会询问是否写入 `~/.zprofile`，非交互安装只打印提示和可直接运行的完整路径。

### 2026.07.01+build.7

- 新增 `--show-wifi-ssid` 诊断入口，可直接显示 macOS 客户端当前读取到的 Wi-Fi SSID。
- 增强 macOS SSID 探测 fallback：除识别 Wi-Fi / AirPort hardware port 外，会尝试所有 `networksetup` 设备、常见 `en0/en1/en2`、`airport -I` 和 `wdutil info`。
- 主菜单和定时上报状态页会显示当前 Wi-Fi SSID，便于确认跳过策略是否有实际检测依据。

### 2026.07.01+build.6

- 修复 macOS 默认 Bash 3.2 + `set -u` 下，空 SSID 跳过列表可能触发 `items[@] unbound variable` 的问题；读取 SSID 失败仍继续上报，跳过时仍只写本地日志摘要。

### 2026.07.01+build.5

- 新增 SSID 本地跳过上报配置；命中当前 SSID 时只写本地跳过日志摘要，不上传 SSID，也不改变 LAN Worker `/report` 或 PO0 协议。
- SSID 列表用英文分号分隔并做精确匹配；读取当前 SSID 失败时继续上报；手动运行命中跳过规则时询问是否强制继续。

### 2026.07.01+build.4

- 更新和旧路径自愈后会迁移默认旧配置、旧日志、旧 IP 探测状态、旧 launchd / cron，并删除默认旧 `po0-self-report` 命令残留。
- 安装新 launchd 前先清理旧 cron；旧 cron 清理失败时不加载新 launchd，避免双重上报。

### 2026.07.01+build.3

- 本机命令、默认配置、默认日志、IP 探测状态和用户可见结果行统一迁移到 `po0-outbound-ip-report` / `PO0 Outbound IP Report`。
- launchd label 迁移为 `fr.schweppes.po0-outbound-ip-report`；安装新 launchd 时会卸载旧 label，并清理旧 cron block，避免双重上报。
- 旧 `po0-self-report` 命令、配置、日志、状态、launchd/cron 和 env / CLI alias 仅作为 legacy 迁移入口继续识别。
- 旧默认 `INSTALL_PATH=.../po0-self-report` 会规范化到 canonical 路径；显式自定义安装路径继续保留。

### 2026.07.01+build.2

- root 安装时明确显示 launchd plist，避免把 LaunchDaemon 误写成 LaunchAgent。
- `--help` 明确列出 self-report 配置文件优先级，包括 `XDG_CONFIG_HOME` 和当前目录兜底。

### 2026.06.28+build.2

- 上报成功摘要和成功通知优先显示 LAN Worker 返回的具体 PO0 目标名。
- 连接旧 LAN Worker 时，目标摘要简化为“PO0 目标：N 个”。

### 2026.06.28+build.1

- 上报成功摘要会显示 LAN Worker 已成功转发的 PO0 目标数量，并同步用于成功通知正文。
- 定时上报状态页会从旧日志的 LAN Worker 返回体中提取 `targets=N`，并合并到对应完成结果。

### 2026.06.25+build.12

- 新增默认静默的 macOS 通知开关，支持 `--notify` / `--no-notify` 和菜单“通知 / 静默模式”切换。
- launchd LaunchAgent 默认不带通知参数，只有显式启用通知时才在上报成功或失败后调用 macOS 通知中心；通知失败只写日志，不影响上报结果。

### 2026.06.25+build.11

- PO0 Bash 构建 / 检查工具在 git 中补齐 executable bit，Release workflow 仍保留显式 `bash` 调用。

### 2026.06.25+build.10

- Release 检查脚本改为显式用 `bash` 调用构建器，避免 GitHub runner 受文件 executable bit 影响。

### 2026.06.25+build.9

- 源码迁入 `scripts/po0/relay/self-report/macos/src/`；自更新继续默认使用 Release asset，旧 macOS self-report raw path 停用。

### 2026.06.25+build.8

- 版本号与 `po0-v2026.06.25.8` 对齐；定时上报状态页的最近结果保持短缩进摘要。

### 2026.06.25+build.2

- 定时上报状态页的最近结果改为短缩进摘要，避免日志续行被面板值列顶到过深位置；原始 launchd 日志路径和 tail 命令继续保留。

### 2026.06.25+build.1

- 新增 macOS 专用 Self-report Bash 客户端，Release asset 为 `po0-outbound-ip-report-macos.sh`。
- 定时上报使用用户级 launchd LaunchAgent；自更新默认继续拉取 macOS 专用 asset。
- 支持 `--save-config --menu` 首次保存默认配置后打开菜单，并提供 `--install-launchd` 别名。

## po0-outbound-ip-report（Windows PowerShell）

### 2026.09.05+build.5

- 对齐本轮 OpenWrt 旁路网关支持的发布版本；本脚本行为未变。

### 2026.09.05+build.4

- 修复发布包校验清单，避免整包校验失败；本脚本功能沿用 `2026.09.05+build.3`。

### 2026.09.05+build.3

- 适配非 Windows CI 的 ACL 测试隔离；本脚本功能沿用 `2026.09.05+build.2`。

### 2026.09.05+build.2

- CI 跨平台兼容性修复；本脚本功能沿用 `2026.09.05+build.1`。

### 2026.09.05+build.1

- 增加默认关闭的官方防火墙双通道；`-OfficialStatus` 只读 GET，正常运行先 GET，只有当前出口缺失或固定槽位不匹配时才 POST，账号最多 5 个槽位。
- 官方固定每 600 秒一次并与 LAN Worker 的计划/TTL 独立；SSID 命中时两条通道一起跳过，`-ForceReport` 只绕过本地 due/SSID guard，Windows 继续使用默认出口。

### 2026.08.30+build.5

- 跟随 PO0 发布批次对齐到 2026.08.30+build.5；Windows 客户端无行为变化。

### 2026.08.30+build.4

- 跟随 PO0 发布批次对齐到 2026.08.30+build.4；Windows 客户端无行为变化。

### 2026.08.30+build.1

- 跟随 PO0 发布批次对齐到 2026.08.30+build.1；Windows 客户端无行为变化。

### 2026.08.29+build.1

- 跟随 PO0 发布批次对齐到 2026.08.29+build.1；Windows 客户端无行为变化。

### 2026.07.23+build.1

- 跟随 PO0 发布批次对齐到 `2026.07.23+build.1`；Windows 客户端无行为变化。

### 2026.07.22+build.2

- 跟随 PO0 发布批次对齐到 `2026.07.22+build.2`；Windows 客户端无行为变化。

### 2026.07.20+build.1

- 跟随 PO0 发布批次对齐到 `po0-v2026.07.20.1`；Windows 客户端无行为变化。

### 2026.07.03+build.4

- Windows 更新脚本保留 `2026.07.03+build.1` 兼容校验标记，旧 build.1 可从 GitHub latest 跨过计划任务名迁移。
- 默认计划任务名继续保持 `Outbound IP Report`，旧 `PO0 Outbound IP Report to LAN Worker` 只作为迁移兼容目标识别。

### 2026.07.03+build.3

- Windows 计划任务名保持 `Outbound IP Report`，计划任务描述保持 `Report outbound IPv4.`。
- 默认计划任务启动文件保留 `po0-outbound-ip-report-task.vbs`，确保旧版 `-UpgradeSelf` 下载校验能跨版本迁移。

### 2026.07.03+build.2

- 新安装的 Windows 计划任务名改为 `Outbound IP Report`，计划任务描述改为 `Report outbound IPv4.`。
- 新安装的计划任务启动文件改为 `outbound-ip-report-task.vbs`；旧 `PO0 Outbound IP Report to LAN Worker` / `PO0 Self Report to LAN Worker` 计划任务和旧启动文件继续识别并在更新时迁移。

### 2026.07.03+build.1

- 自更新后先检测计划任务是否已指向标准脚本路径；没有漂移时不再重复刷新计划任务启动文件。
- 菜单和状态页清理标准路径状态、定时任务状态等用户可见文案，减少工程表达。

### 2026.07.02+build.10

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.10`；Windows 客户端无行为变化。

### 2026.07.02+build.9

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.9`；Windows 客户端无行为变化。

### 2026.07.02+build.8

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.8`；Windows 客户端无行为变化。

### 2026.07.02+build.7

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.7`；Windows 客户端无行为变化。

### 2026.07.02+build.6

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.6`；Windows 客户端无行为变化。

### 2026.07.02+build.5

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.5`；Windows 客户端无行为变化。

### 2026.07.02+build.4

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.4`；Windows 客户端无行为变化。

### 2026.07.02+build.3

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.3`；Windows 客户端无行为变化。

### 2026.07.02+build.2

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.2`；Windows 客户端无行为变化。

### 2026.07.02+build.1

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.02.1`；Windows 客户端无行为变化。

### 2026.07.01+build.8

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.01.8`；Windows 客户端无行为变化。

### 2026.07.01+build.7

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.01.7`；Windows 客户端无行为变化。

### 2026.07.01+build.6

- 跟随 PO0 Release asset 批次对齐到 `po0-v2026.07.01.6`；Windows 客户端无行为变化。

### 2026.07.01+build.5

- 新增 SSID 本地跳过上报配置；命中当前 SSID 时只写本地跳过日志摘要，不上传 SSID，也不改变 LAN Worker `/report` 或 PO0 协议。
- SSID 列表用英文分号分隔并做精确匹配；读取当前 SSID 失败时继续上报；手动运行命中跳过规则时询问是否强制继续。

### 2026.07.01+build.4

- 更新和旧 `po0-self-report.ps1` 路径自愈后会迁移默认旧 `self-report.json`、旧日志、旧 IP 探测状态和旧计划任务，并删除默认旧 ps1 / VBS launcher 残留。
- 旧计划任务迁移保留通知参数、暂停状态、Settings / Principal；新任务注册成功后再删除旧任务，删除失败会先禁用旧任务以避免双重上报。
- 显式 `-ConfigPath` / `-LogPath` 自定义路径在迁移和卸载清理时不会被误删。

### 2026.07.01+build.3

- 默认配置迁移为 `outbound-ip-report.json`，默认日志迁移为 `po0-outbound-ip-report.log`，默认计划任务名迁移为 `PO0 Outbound IP Report to LAN Worker`。
- 菜单、版本输出、通知标题和完成 / 未完成结果行统一显示 `PO0 Outbound IP Report`。
- 旧 `self-report.json`、旧日志、旧 `po0-self-report.ps1` / VBS launcher 和旧计划任务只作为 legacy copy-forward、迁移和卸载目标继续识别。
- 旧计划任务迁移会先读取原 action / launcher 里的 `ConfigPath`、`LogPath`、通知参数和 Disabled 状态，新任务注册成功后再删除旧任务，避免双任务。

### 2026.07.01+build.2

- Windows 默认安装脚本名改为 `po0-outbound-ip-report.ps1`，计划任务和隐藏启动器会迁移到新路径。
- `-Version` / `-ScheduleStatus` 会显示计划任务实际脚本目标，并提示旧 `po0-self-report.ps1` 任务漂移。
- 从旧 `po0-self-report.ps1` 路径启动新版脚本时，会迁移到 `po0-outbound-ip-report.ps1` 并重开 canonical 菜单。
- 旧计划任务迁移会保留 `ConfigPath`、`LogPath` 和 `Notify` / `NoNotify` 启动参数。
- 更新下载校验会拒绝仍以 `po0-self-report.ps1` 作为默认安装路径的旧 Windows asset。
- 发布批次对齐到 `po0-v2026.07.01.2`，避免 GitHub latest 继续停留在 `po0-v2026.06.28.2`。

### 2026.06.28+build.2

- 上报成功摘要优先显示 LAN Worker 返回的具体 PO0 目标名。
- 连接旧 LAN Worker 时，目标摘要简化为“PO0 目标：N 个”。

### 2026.06.28+build.1

- 上报成功摘要会显示 LAN Worker 已成功转发的 PO0 目标数量。
- 定时上报状态页会从旧日志的 LAN Worker 返回体中提取 `targets=N`，并合并到对应完成结果。

### 2026.06.25+build.12

- 新增 `-NoNotify` 显式静默参数，并在菜单中加入“Windows 通知 / 静默模式”开关。
- 配置页和计划任务状态页会同时显示配置通知状态与已安装任务实际是否带 `-Notify`，不一致时提示通知状态漂移。
- 切换通知模式时会保存配置并刷新计划任务隐藏 launcher，避免旧任务仍按残留 `-Notify` 弹通知。

### 2026.06.25+build.11

- PO0 Bash 构建 / 检查工具在 git 中补齐 executable bit，Release workflow 仍保留显式 `bash` 调用。

### 2026.06.25+build.10

- Release 检查脚本改为显式用 `bash` 调用构建器，避免 GitHub runner 受文件 executable bit 影响。

### 2026.06.25+build.9

- 源码迁入 `scripts/po0/relay/self-report/windows/src/`；自更新继续默认使用 Release asset，旧 Windows self-report raw path 停用。

### 2026.06.25+build.8

- 版本号与 `po0-v2026.06.25.8` 对齐；定时上报状态里的最近结果保持短缩进摘要。

### 2026.06.25+build.2

- 定时上报状态页的最近结果改为短缩进摘要，避免日志续行被面板值列顶到过深位置；日志文件仍保留完整原始记录。

### 2026.06.25+build.1

- 菜单首页改为精简状态面板，补充脚本版本、路径、配置文件、日志路径、通知和计划任务状态。
- 版本输出补充 build、配置文件、日志路径和计划任务状态。

### 2026.06.24+build.1

- 默认安装和自更新下载源迁到 GitHub Release asset。
- 新增 `PO0_SELF_REPORT_PS_DOWNLOAD_URL` 覆盖入口，便于测试和回滚。

### 2026.06.23+build.11

- raw 脚本下载增加 `-TimeoutSec 120`，避免安装或自更新时长期挂起；上报请求继续使用已有 `-TimeoutSec 30`。

### 2026.06.23+build.10

- 菜单新增“卸载本客户端”，可删除本脚本管理的计划任务、本机脚本和隐藏 launcher，并可选删除配置与日志。

### 2026.06.23+build.9

- Windows 计划任务默认静默运行，只写日志；菜单和 `-Notify` 可显式启用自动上报完成/失败通知。

### 2026.06.23+build.8

- 默认公网 IPv4 探测列表删除 12306 grip 接口，继续以 IP9 为首选并轮询其它国内接口和 `myip.ipip.net`。

### 2026.06.22+build.7

- 新增 `-IntervalSeconds` / `PO0_SELF_REPORT_INTERVAL_SECONDS`，默认按 `3600` 秒安装计划任务，旧 `-Minutes` 继续兼容。
- 配置 JSON 新增 `IntervalSeconds`，菜单、状态和安装输出统一用秒显示上报间隔。

### 2026.06.22+build.6

- 菜单更新脚本成功后先停留显示安装路径、版本变化和更新内容，按回车后再打开新版菜单。
- 状态面板的上报间隔文案与 Linux/OpenWrt 版统一为“每 N 分钟”。

### 2026.06.22+build.5

- 菜单“安装 / 更新定时上报”会直接提示计划任务间隔，避免反复按 3 只用旧分钟数重装任务。

### 2026.06.22+build.4

- Windows 计划任务改用隐藏 launcher 启动 PowerShell，并在自动上报成功或失败后弹出 Windows 通知。

### 2026.06.22+build.3

- 当前版本更新内容只显示本次版本条目；完整版本历史迁移到 `scripts/po0/relay/CHANGELOG.md`，避免脚本内 changelog 越积越长。

### 历史迁移条目（来自脚本内旧 changelog，版本未逐条记录）

- 放行 TTL 状态说明跟随 LAN Worker Self-report 默认值更新为 43200 秒。
- 修复 Self-report 客户端配置面板和菜单列对齐。
- 新增从 GitHub 更新脚本入口，并在更新后显示版本变化和更新内容。
- 新增 `-Version` 和 `-Changelog` 只读入口。
