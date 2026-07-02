# PO0 nftables Changelog

本文件保存 PO0 nftables 子系统的完整版本历史。各可独立部署脚本只在脚本头部保留“当前版本更新内容”，供 `--changelog`、`--upgrade-self` 或更新完成提示在远端单文件环境中显示。

旧脚本内置 changelog 没有给每条历史记录保存完整版本号；这些条目已迁移到对应脚本的“历史迁移条目”小节。自本文件建立后，新增版本必须按脚本名和版本号记录在这里。

## po0-nftables-relay-manager

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

### 2026-07-01

- 新增 `SKIP_WIFI_SSIDS` 本地跳过 guard；定时/网络变化自动触发命中当前 Wi-Fi SSID 时，不探测公网 IP、不执行 SSH 上报、不通知，只写 Egern 本地状态/日志并保留上一轮成功状态用于 Widget。
- SSID 列表使用英文分号分隔并精确大小写匹配；读取不到 SSID、非 Wi-Fi、手动运行、状态页和 Widget 刷新都会继续上报；SSID 不上传到 PO0 或 LAN Worker，也不新增 `--ssh-ip-report` 协议字段。

### 2026-06-23

- 默认公网 IPv4 探测列表删除 12306 grip 接口，继续以 IP9 为首选并轮询其它国内接口和 `myip.ipip.net`。
- 状态页 / Widget 优先复用 IP9、163、126、myip.ipip 等 IP 查询接口返回的归属地 / 运营商信息，拿不到时才额外查询。

## po0-outbound-ip-report（Linux/OpenWrt）

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
