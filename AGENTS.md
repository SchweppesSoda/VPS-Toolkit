# AGENTS.md

本文件给后续维护本仓库的 Codex / agent 使用。改代码前先读相关 README 和技术文档；如果本文件与用户当前明确要求冲突，以用户当前要求为准，但不要忽略这里记录的历史踩坑。

## 主分支与任务收尾（2026-09-07 用户约定）

- 本仓长期只保留 `main`，日常在本仓主目录工作。同一仓库同时只允许一个任务写入；只读检查可以并行。
- 开始前核对实际仓库、分支、工作树、未提交改动和远程状态。发现主目录落后或有遗留改动时，先辨认并妥善收尾，不能把旧代码当成最新状态，也不能默认另建分支绕开问题。
- 只有用户明确要求并行或隔离时才建立临时分支/工作树；记录用途及归属，完成后把已验证的改动收回主目录 `main`，再清理临时分支和工作树。不要把一个仓库的工作树建在另一个仓库目录中。
- 已合入、cherry-pick 或重做的改动要按内容核对；被新需求取代的旧实现不重新合入。清理前同时检查未提交、未跟踪和忽略文件，必要备份放在仓库外，并报告恢复位置。
- 已完成的代码应在本地 `main` 留下范围明确的提交；推送和 Release 按用户已有授权执行。结束时说明本地/远程提交、是否已发布和仍有的未完成工作，不把“某个临时目录改完”当成整个仓库收尾完成。
- `main` 是源码主线，Release tag 是已发布版本记录；只保留一个分支不意味着删除 tag 或历史提交。测试/构建输出仍使用 `.tmp/`，不把它当作长期源码存放处。

## 仓库结构

- `scripts/po0/`：PO0 相关脚本，包括转发主控、LAN 更新镜像、七端官方上报、重装和代理增强。
- `scripts/vps/`：通用 VPS 工具，包括 inventory 驱动的代理栈部署、已有机器接管与按配置复刻、SSH 加固、Fail2ban、3x-ui、ForwardX、REALITY finder。
- Web 静态工具已迁出到 `SchweppesSoda/vps-toolkit-web`；本仓不再维护 `web/`，也不要从本仓根目录启用 GitHub Pages。
- `tools/` 只放离线构建工具。`tools/po0/` 维护 PO0 Release 发布文件构建、manifest 和检查脚本；运行在客户端、Worker 或访问设备上的脚本应放到对应 `scripts/po0/relay/*/src/` 或明确的客户端目录。
- PO0 Release 脚本由 `tools/po0/build-po0-assets.ps1` / `.sh` 按 `tools/po0/manifests/` 生成；manifest 覆盖 manager、LAN Worker、Linux self-report、macOS self-report、Windows self-report 五个模块化源码树。OpenWrt APK 由 25.12 SDK 使用 `packaging/openwrt/` 定义构建。

## PO0 职责边界（2026-09-08）

- 用户已全面弃用自建防火墙。manager 只管理转发、NAT/SNAT/MSS、可选 BBR、诊断、备份及鉴权更新；不得恢复 input/source 白名单、DDNS、SSH/HTTP 接收、WebAuth、学习与 iplist/ipdb 任务。
- LAN Worker 只提供固定 manager 脚本更新镜像。PO0 无法直连 GitHub，必须保持现有 HTTP 路径、nonce/HMAC、密钥与服务入口；上游使用固定 GitHub Release HTTPS 资产，不能成为任意 URL 代理。
- 原 Worker 官方账号显式迁移至同机 Linux 官方单文件客户端（也可在具备依赖的 OpenWrt 上运行），保持本机正常路由/OpenClash 行为。不得静默改成 APK WAN 源地址绑定，不得丢失账号或建立重复任务。
- 七端只保留官方上报。先 GET、必要时 POST；Egern 同 /24 共用既有槽位，403 只复查一次。只读不 POST、不推进 due；Token、槽位、名称、间隔、停用与网络触发选择必须保留。
- 主 OpenWrt 用 mwan3 指定 WAN；旁路 OpenWrt 绑定专用源地址，真实 DNS 按本机 probe_dns_server（默认 192.168.88.1）解析。指定 WAN/地址失败不回退。其它端保持原网络行为。官方 Token 不进入日志、通知、命令参数和运行状态；主动打开的本机编辑页按用户要求显示完整已保存 Token。
- 支持 SSID 的客户端采用本地 guard，读取失败继续；Stash 没有公开 SSID API，出口变化依靠轮询。强制仅绕过本机条件，仍先 GET。Egern/Stash/Loon 按网络选择默认关闭，开启后原目标为蜂窝、另填目标为 Wi-Fi，用户槽位不变。
- manager 的迁移 guard 必须拒绝仍有旧保护的配置/运行表，不得静默削弱保护。托管 NAT/MANGLE 的删除与新表定义在同一 batch，先 nft -c，正式阶段只一次 nft -f，不 flush ruleset。
- 旧版资产固定 tag/非 Latest Release `archive/po0-full-20260907.1`；历史不是维护分支，不把归档功能带回 main。最小旧协议测试夹具仅供测试，不参与安装。私有 ProxyConfig 的归档不得进入公开仓库/Release。

## 发布与构建

- PO0 正式下载源是 GitHub Release：五个脚本 `nftables-relay-manager.sh`、`po0-lan-client.sh`、`po0-outbound-ip-report.sh`、`po0-outbound-ip-report-macos.sh`、`po0-outbound-ip-report.ps1`，一个 APK `po0-outbound-ip-report.apk`，以及覆盖全部资产的 `checksums.txt`。
- `Self-report` 仅作为已退役功能的历史兼容名；三端访问设备客户端的默认命令、脚本文件、配置和日志统一使用 `po0-outbound-ip-report*` / `PO0 Outbound IP Report`，系统调度器可见名称、launchd label 和 cron marker 使用不带 `PO0` 的 `Outbound IP Report` / `outbound-ip-report` / `OUTBOUND_IP_REPORT_*`。旧 `po0-self-report*` 和旧 `PO0` 调度器名称只做 legacy 配置读取、旧路径自愈迁移、旧任务清理、旧 env / CLI alias 和历史说明；更新或自愈成功后应迁移并删除默认旧名残留，不再保留默认旧命令 shim。
- 三端访问设备客户端的 SSID 跳过只允许作为本地 guard：命中时本机跳过并写日志摘要，不上传 SSID，不新增 LAN Worker `/report` 或 PO0 协议字段；SSID 列表用英文分号分隔并精确匹配；读取失败必须继续正常上报；手动运行命中时询问是否强制继续；不要为 SSID 新增 `PO0_SELF_REPORT_*` 或 `SELF_REPORT_*` legacy alias。
- macOS 访问设备客户端必须兼容系统自带 Bash 3.2；在 `set -u` 环境下不要用空 Bash 数组解析可选列表，例如 `local -a items` / `read -r -a items` / `"${items[@]}"`，SSID 列表解析应使用 Bash 3.2 安全的字符串循环，并保留对应 release gate。
- macOS 当前 Wi-Fi SSID 读取遇到 `redacted` / `<redacted>` 时应按系统隐私权限隐藏处理，必须 fail-open 继续上报；允许提供 `--show-wifi-ssid` / `--diagnose-wifi-ssid` / `--request-location-permission` / `--delete-location-permission-helper` / `--open-location-services` 这类本地诊断、用户授权指引、Helper App CoreLocation 授权请求、本地 Helper 删除和系统设置跳转。macOS 26+ 不要依赖 Terminal/iTerm 出现在定位服务列表里；`--request-location-permission` 应使用带稳定 bundle id、定位用途声明和可选 ad-hoc 签名的 `PO0 Location Permission Helper.app` 触发授权，并由 Helper 在本机通过 CoreWLAN 读取 SSID 后返回给脚本；删除 Helper 只移除本地 app，不能修改 macOS 定位授权 / TCC 记录；不静默授予或修改定位服务 / TCC 权限，不运行 `sudo`、不运行 `tccutil`、不保存提权凭据、不写 TCC 数据库。
- 按用户要求，PO0 可以选择分开发布：`po0-scripts-vYYYY.MM.DD.N` 只发布五个主脚本与 `checksums.txt`，不运行 APK SDK；`po0-apk-vYYYY.MM.DD.N` 只发布 `po0-outbound-ip-report.apk` 与 `checksums.txt`，始终 `latest=false`；`po0-vYYYY.MM.DD.N` 保留整包发布。组件流程显式选择上述资产，不携带旧 WAN probe。
- 创建脚本或整包 Release tag 前，本次脚本资产的内部版本必须统一为 `YYYY.MM.DD+build.N`，日期和尾号与所选 tag 一致；同步 Bash / PowerShell checker 的预期脚本版本和规范 `po0-vYYYY.MM.DD.N` tag，并执行两个实际版本检查函数。APK 组件独立发布时不要求同步或发布桌面脚本。APK 布局门禁核对自身源码、生成运行时和启动命令的版本，不再要求与桌面脚本版本相同。
- Release workflow 由上述三种 tag 选择发布范围，失败后用 GitHub Actions rerun；不覆盖已有 tag。脚本组件 tag 的日期和尾号必须与脚本版本一致，检查器内部将 scripts tag 规范化为同版本 `po0-v` tag，不尝试在工作流中覆盖 GitHub 只读的 `GITHUB_REF*` 环境变量；APK tag 独立编号，沿用 APK 自身包版本。
- 用户要求脚本 `commit and push` 或希望可更新到新版时，验证并 push `main` 后默认创建 `po0-scripts-vYYYY.MM.DD.N` tag；仅 APK 变更使用 `po0-apk-vYYYY.MM.DD.N`，明确要求整包时才用 `po0-vYYYY.MM.DD.N`。发布流程或文档变更本身不要求重复发布未变的脚本。
- 每种 Release 都按本次选定范围 draft 原子发布：完整上传相应资产及精确覆盖它们的 `checksums.txt`，回下载校验通过后再公开。已存在 draft 只允许补齐缺失 asset；已有资产 checksum 不同、或正式 release 缺资产时必须失败并用新 tag，禁止覆盖正式资产。
- Latest 供脚本安装 / 自更新使用，只允许脚本或整包 release 更新；旧版本晚完成不能让 Latest 倒退。APK 使用独立 tag 的版本化下载地址，不使用 `releases/latest/download/*.apk`。
- 旧 manager、LAN Worker 和 self-report raw URL 已禁用，不再作为兼容入口；不要重新新增这些 raw 可执行脚本路径。Egern 标准 raw 路径是 `scripts/po0/nftables/clients/egern/`；`scripts/po0/relay/egern/` 只作为历史兼容路径暂时保留，不能作为新安装推荐入口。
- Egern YAML/JS、Loon LPX/JS、Stash 客户端脚本和未纳入本阶段的通用 VPS 脚本 raw 下载源是白名单；PO0 五个可执行脚本的新安装、自更新和 manager mirror 上游应使用 Release 发布文件。raw URL 检查应使用精确路径白名单，不能用 `reinstall` 等宽泛子串放行。
- Linux/OpenWrt、macOS、Windows 三端访问设备客户端自更新后，应先检测 cron / launchd / Windows 计划任务是否已指向标准脚本路径；只有入口漂移、缺失或迁移旧任务时才刷新，不要每次自更新都无条件重写定时入口。
- 模块化后优先修改 `scripts/po0/relay/manager/src/`、`scripts/po0/relay/lan-worker/src/`、`scripts/po0/relay/self-report/` 和对应 manifest；不要手改由构建器生成的 Release staging 单文件。`tools/po0/check-po0-assets.sh` 是 CI/release authority；`tools/po0/check-po0-assets.ps1` 是 Windows 本地等价检查入口，二者都必须确认 manifest 覆盖、raw URL 策略、Egern legacy sync、Windows 标准安装路径、版本/tag 对齐、三端 SSID 本地跳过 guard，以及 macOS `--show-wifi-ssid` / `--diagnose-wifi-ssid` / `--request-location-permission` / `--delete-location-permission-helper` / `--open-location-services` 诊断入口、Helper App 定位授权 / CoreWLAN fallback、安全删除 Helper、无裸 `osascript` 授权 helper。
- Windows 上运行 `tools/po0/check-po0-assets.ps1` 时，Bash 子检查应优先使用 Git Bash；不要误用 Windows 自带 WSL `bash.exe` stub。Bash 入口调用 `pwsh` 检查 Windows 脚本时，要先把 Git Bash/MSYS 路径转换成 Windows 路径，避免 `/d/Users/...` 被 `pwsh` 解析成 `D:\d\Users\...`。
- `tools/po0/build-po0-assets.ps1` 的输出目录只能位于仓库内 `.tmp/po0-*`，因为构建前会递归清空输出目录。
- Bash / PowerShell PO0 checker 的本地默认构建目录必须相互隔离；Release workflow 需要显式传入固定 `.tmp/po0-check-assets`，因为后续发布步骤从该目录读取资产。checker 新接入的专项测试也必须使用仓库 `.tmp/` 下的唯一临时目录，避免并行门禁互相清理。
- `.github/workflows/po0-check.yml` 的路径过滤必须覆盖整个 `scripts/po0/nftables/clients/**` 和已接入门禁的 `scripts/po0/reinstall/**`，不能退回只监听 Egern。
- 构建器必须显式控制编码和 LF：Bash/manifest/checksum 使用 UTF-8 no BOM；含中文的 Windows PowerShell `.ps1` 使用 UTF-8 BOM，避免 Windows PowerShell 5 按系统代码页解析失败。

- OpenWrt APK 仅有 official procd 实例；官方 timer/network 开关独立，事件不移动定期截止点。升级保留总开关、官方凭据/停用和周期，不加载通用 Linux cron 安装入口。APK 修改运行 `test-openwrt-apk-layout.sh`。

## 官方客户端界面与迁移

- Windows/macOS/Linux 主菜单编号与语义对齐，只展示官方与必要通用设置。旧任务名称仅用于识别/清理；不能显示退役自建面板。保存只更新已存在的官方计划，不因保存而创建计划。
- 手机本机配置优先，清除保留停用记录，旧同步参数不能复活。首次迁移先保存原始配置/状态快照，后续不覆盖备份。旧动作返回明确退役结果，不运行另一个动作。
- Egern 只注册一个“PO0 防火墙上报状态”组件，按尺寸显示官方名称/槽位/占用/IP/时间；手动状态与 Widget 强制检查，后台遵守 SSID/开关/due。Stash Tile 同步只读缓存，不请求、不写入、不迁移；点击进入本机管理页。
- 桌面/API/迁移测试必须使用临时配置与模拟请求，不访问真实官方 API，不操作设备计划/服务。

## 交互脚本规则

- 支持 `curl | bash` 的交互脚本必须优先从 `/dev/tty` 读取人机输入。
- 不新增裸 `read -p`；优先使用脚本里已有的 prompt helper。
- 菜单改动必须同步显示编号、分组顺序、输入范围、无效选择提示和 `case` 分支。
- 编号可以重排，但必须按视觉顺序递增，不能为了少改 `case` 保留跳号旧编号。
- 用户可见菜单、状态页、帮助和更新结果里避免使用工程内部表达；不要把英文标准路径、启动器、cron 托管块、配置漂移等内部术语直接暴露给用户，优先使用“标准路径 / 标准安装路径”“计划任务启动文件”“托管片段”“状态提示 / 配置提示”等中文表达。
- 查看类和一次性动作结束后要保留返回暂停，避免输出被菜单刷新冲掉。
- 粘贴私钥等多行输入后要注意输入缓冲，不让残留内容进入主菜单。

## 文档同步

- 全仓 Markdown 分层：根 `README.md` 是中文主入口，`README.en.md` 是英文辅助入口；根 README 必须维护全仓长期 Markdown 索引，但只放项目入口、文档归属、目录结构、最短示例和安全提醒，不在上层 README 复制下层细节；目录级 `README.md` 放该模块用户入口；`*-technical.md` / `*-design.md` 只放实现细节。
- 旧中文根 README 文件已删除，不再新增或引用；需要中文入口时统一指向根 `README.md`。
- 全仓文档归属：
  - `README.md`：中文项目入口、全仓文档索引、目录结构、最短示例和安全提醒。
  - `README.en.md`：英文辅助入口，内容跟随 `README.md` 的入口结构和文档索引。
  - `AGENTS.md`：维护规则、职责边界、验证规则和文档归属表。
  - `scripts/po0/README.md`：PO0 子系统入口，只链接到子模块主文档。
  - `scripts/po0/*/README.md`：PO0 子模块用户入口；复杂实现才允许一个配套 technical/design 文档。
  - `scripts/po0/relay/CHANGELOG.md`：PO0 nftables 子系统版本历史；脚本内只保留当前版本更新内容。
  - `scripts/vps/*/README.md`：VPS 工具用户入口；跨模块约定放 `scripts/vps/docs/*.md`，复杂实现才允许一个 `*-technical.md` 或 `*-guide.md`。
  - Web 工具文档：已迁出到 `SchweppesSoda/vps-toolkit-web`，本仓根 README 只保留外部入口链接。
- 新增、删除、重命名任何长期维护 `.md` 时，必须同步根 `README.md` 的文档索引；如保留英文入口，也同步 `README.en.md`。
- 修改 Web 工具 UI 时，在 `SchweppesSoda/vps-toolkit-web` 仓库内阅读对应 `docs/*_technical.md`，并按该仓库自己的 `AGENTS.md` 验证；不要在本仓新增 Web 源码或技术文档。
- `scripts/po0/relay/` 只保留四类 PO0 relay 长期维护 Markdown：用户主文档 `README.md`、版本历史 `CHANGELOG.md`、实现主文档 `po0-relay-technical.md`、Egern 历史兼容 README。Egern 标准路径专属文档维护在 `scripts/po0/nftables/clients/egern/README.md`。
- nftables 用户行为、菜单、命令示例、默认值、TTL、Token、状态文件和定时任务只更新 `scripts/po0/relay/README.md`；版本历史只更新 `scripts/po0/relay/CHANGELOG.md`；实现细节、协议、wrapper、兼容规则和内部状态模型只更新 technical 文档；Egern 专属导入、设备 ID、Widget 和多 PO0 行为只更新 Egern README。
- 不随手新增 `.md`。新增文档前先判断是否能放入现有主文档；除非是独立模块且长期维护，否则不要制造碎片文档。短命令笔记、目录清单、临时排错记录应并入现有 README 或删除。
- 改菜单名、默认值、TTL、Token、状态文件或定时任务后，必须用 `rg` 扫旧词，避免文档与代码脱节。
- 修改文档结构时，必须用 `rg --files -g '*.md'` 查看全仓 Markdown 清单，并用旧文件名检索确认被删除文档名与旧链接已清理；旧中文根 README 的检查命令是 `rg "README\\.zh-CN\\.md"`。
- 重要边界、维护流程、验证规则发生变化时，也要同步本文件。
- PO0 Debian reinstall 不写 raw 在线执行命令。
- 需要 root 且交互的在线示例优先下载到临时文件再运行。
- 不把多个脚本命令塞在一个代码块里；按脚本和场景拆分。

## 验证清单

- Shell 改动至少跑 `bash -n` 和 `git diff --check`。
- 修改任何带版本输出的交互脚本、客户端脚本或安装脚本的用户可见行为、菜单、CLI 输出、定时任务或部署命令后，必须同步该脚本自己的版本号变量（如 `SCRIPT_VERSION`、`SCRIPT_RELEASE_DATE` 等）；不只限于 nftables manager。
- 同一功能同时影响 PO0 manager、LAN Worker client、self-report、VPS 工具等多个脚本时，逐个判断并同步受影响脚本的版本号；有 `--version` 的必须用对应脚本的 `--version` 确认输出。
- 带自更新或部署确认需求的版本化脚本应维护脚本内 `CHANGELOG_BEGIN` / `CHANGELOG_END` 当前版本更新内容块；每次 bump 版本时同步写清用户可见变化，不写内部流水账，不把历史条目累积在脚本里。完整版本历史写入对应模块的 `CHANGELOG.md`。
- 自更新入口（如 `--upgrade-self`）成功输出应说明安装路径、版本变化和更新内容；不要只输出内部实现标记。
- 没有自更新入口、依赖 `scp` 上传的脚本（如 PO0 nftables manager）应提供 `--changelog` 或等价只读入口，供上传后确认当前版本更新内容。
- 菜单改动要检查编号、范围、提示和 `case` 一致；能渲染主菜单时，至少输入 `0` 验证可退出。
- 涉及 Bash helper、`set -u`、stdin 或 SSH 调用时，要做运行时回归，不只跑 `bash -n`。
- 涉及 `reload_managed_rules` 或 nftables 应用链路时，必须运行 `tools/po0/test-manager-nft-atomic-reload.sh`，确认预检失败不进入应用、正式刷新只有一个 batch、可选托管表缺失时不生成无效删除。
- 涉及 PowerShell、JavaScript、YAML 或网页工具时，按对应技术文档里的检查方式补验证。
- 修改 `scripts/vps/proxy-stack/` 的实例解析、组件调用或防火墙渲染后，必须运行
  `tools/vps/test-proxy-stack-orchestrator.sh`。`managed` 必须拒绝任何其它 input base chain；
  持久化路径先对 runtime batch 执行一次 `nft -c`，安装两个候选文件后再对最终 boot
  composite 执行一次 `nft -c`，然后且只能执行一次正式 `nft -f`。before-image / EXIT
  guard 只提供同一进程内 best-effort 恢复，两个持久化文件整体不具备断电或 `SIGKILL`
  crash-atomic 保证。Proxy Gateway Plus 必须保持 `external` 防火墙模式，不修改三方组件
  的业务脚本或建立第二套日常管理入口。

## 提交规则

- 改代码前先确认当前分支与远程上游一致：执行 `git fetch --tags --prune` 后查看 `git status --short --branch` 或 `git rev-list --left-right --count HEAD...@{u}`；本地落后时先 `git pull --ff-only`，分叉时先停下来确认处理方式。
- 提交前再次确认本地与远程上游的 ahead/behind 状态，避免基于过期代码提交；如远程已有新提交，优先 fast-forward 更新并重新验证本次改动。
- 提交前检查 staged 范围，避免混入无关改动。
- 如果工作区已有用户或其它线程留下的改动，不要回滚；只提交本次相关文件。
- Push 前确认远端和分支，尤其是 `origin/main`。
