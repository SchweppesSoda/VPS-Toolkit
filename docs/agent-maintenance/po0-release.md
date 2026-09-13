# PO0 build and release contracts

仅在构建器、资产、版本化脚本或发布任务涉及下列条目时读取。完整 checker 是正式发布门禁；局部开发按影响选择专项检查，不为纯文档改动构建 APK 或重发脚本。

- PO0 正式下载源是 GitHub Release：五个脚本 `nftables-relay-manager.sh`、`po0-lan-client.sh`、`po0-outbound-ip-report.sh`、`po0-outbound-ip-report-macos.sh`、`po0-outbound-ip-report.ps1`，一个 APK `po0-outbound-ip-report.apk`，以及覆盖全部资产的 `checksums.txt`。
- `Self-report` 仅作为已退役功能的历史兼容名；三端访问设备客户端的默认命令、脚本文件、配置和日志统一使用 `po0-outbound-ip-report*` / `PO0 Outbound IP Report`，系统调度器可见名称、launchd label 和 cron marker 使用不带 `PO0` 的 `Outbound IP Report` / `outbound-ip-report` / `OUTBOUND_IP_REPORT_*`。旧 `po0-self-report*` 和旧 `PO0` 调度器名称只做 legacy 配置读取、旧路径自愈迁移、旧任务清理、旧 env / CLI alias 和历史说明；更新或自愈成功后应迁移并删除默认旧名残留，不再保留默认旧命令 shim。
- 按用户要求，PO0 可以选择分开发布：`po0-scripts-vYYYY.MM.DD.N` 只发布五个主脚本与 `checksums.txt`，不运行 APK SDK；`po0-apk-vYYYY.MM.DD.N` 只发布 `po0-outbound-ip-report.apk` 与 `checksums.txt`，始终 `latest=false`；`po0-vYYYY.MM.DD.N` 保留整包发布。组件流程显式选择上述资产，不携带旧 WAN probe。
- 创建脚本或整包 Release tag 前，本次脚本资产的内部版本必须统一为 `YYYY.MM.DD+build.N`，日期和尾号与所选 tag 一致；同步 Bash / PowerShell checker 的预期脚本版本和规范 `po0-vYYYY.MM.DD.N` tag，并执行两个实际版本检查函数。APK 组件独立发布时不要求同步或发布桌面脚本。APK 布局门禁核对自身源码、生成运行时和启动命令的版本，不再要求与桌面脚本版本相同。
- Release workflow 由上述三种 tag 选择发布范围，失败后用 GitHub Actions rerun；不覆盖已有 tag。脚本组件 tag 的日期和尾号必须与脚本版本一致，检查器内部将 scripts tag 规范化为同版本 `po0-v` tag，不尝试在工作流中覆盖 GitHub 只读的 `GITHUB_REF*` 环境变量；APK tag 独立编号，沿用 APK 自身包版本。
- 用户要求脚本 `commit and push` 或希望可更新到新版时，验证并 push `main` 后默认创建 `po0-scripts-vYYYY.MM.DD.N` tag；仅 APK 变更使用 `po0-apk-vYYYY.MM.DD.N`，明确要求整包时才用 `po0-vYYYY.MM.DD.N`。发布流程或文档变更本身不要求重复发布未变的脚本。
- 每种 Release 都按本次选定范围 draft 原子发布：完整上传相应资产及精确覆盖它们的 `checksums.txt`，回下载校验通过后再公开。已存在 draft 只允许补齐缺失 asset；已有资产 checksum 不同、或正式 release 缺资产时必须失败并用新 tag，禁止覆盖正式资产。完整正式 Release 的只读重跑只回下载校验每个资产一次；不完整的正式 Release 在下载前拒绝。
- Latest 供脚本安装 / 自更新使用，只允许脚本或整包 release 更新；旧版本晚完成不能让 Latest 倒退。APK 使用独立 tag 的版本化下载地址，不使用 `releases/latest/download/*.apk`。
- 两个 PO0 Release workflow 共用固定 `po0-release-publish` 并发组，覆盖 Latest 读取至公开发布，不能按 tag 拆锁。使用 `queue: max` 保留等待中的发布，最多 100 个，超过上限需重跑；不取消正在发布的任务。参见 [GitHub concurrency](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency)。
- 旧 manager、LAN Worker 和 self-report raw URL 已禁用，不再作为兼容入口；不要重新新增这些 raw 可执行脚本路径。Egern 标准 raw 路径是 `scripts/po0/nftables/clients/egern/`；`scripts/po0/relay/egern/` 只作为历史兼容路径暂时保留，不能作为新安装推荐入口。
- Egern YAML/JS、Loon LPX/JS、Stash 客户端脚本和未纳入本阶段的通用 VPS 脚本 raw 下载源是白名单；PO0 五个可执行脚本的新安装、自更新和 manager mirror 上游应使用 Release 发布文件。raw URL 检查应使用精确路径白名单，不能用 `reinstall` 等宽泛子串放行。
- 模块化后优先修改 `scripts/po0/relay/manager/src/`、`scripts/po0/relay/lan-worker/src/`、`scripts/po0/relay/self-report/` 和对应 manifest；不要手改由构建器生成的 Release staging 单文件。`tools/po0/check-po0-assets.sh` 是 CI/release authority；`tools/po0/check-po0-assets.ps1` 是 Windows 本地等价检查入口，二者都必须确认 manifest 覆盖、raw URL 策略、Egern legacy sync、Windows 标准安装路径、版本/tag 对齐、三端 SSID 本地跳过 guard，以及 macOS `--show-wifi-ssid` / `--diagnose-wifi-ssid` / `--request-location-permission` / `--delete-location-permission-helper` / `--open-location-services` 诊断入口、Helper App 定位授权 / CoreWLAN fallback、安全删除 Helper、无裸 `osascript` 授权 helper。
- Windows 上运行 `tools/po0/check-po0-assets.ps1` 时，Bash 子检查应优先使用 Git Bash；不要误用 Windows 自带 WSL `bash.exe` stub。Bash 入口调用 `pwsh` 检查 Windows 脚本时，要先把 Git Bash/MSYS 路径转换成 Windows 路径，避免 `/d/Users/...` 被 `pwsh` 解析成 `D:\d\Users\...`。
- `tools/po0/build-po0-assets.ps1` 的输出目录只能位于仓库内 `.tmp/po0-*`，因为构建前会递归清空输出目录。
- Bash / PowerShell PO0 checker 的本地默认构建目录必须相互隔离；Release workflow 需要显式传入固定 `.tmp/po0-check-assets`，因为后续发布步骤从该目录读取资产。checker 新接入的专项测试也必须使用仓库 `.tmp/` 下的唯一临时目录，避免并行门禁互相清理。
- `.github/workflows/po0-check.yml` 的路径过滤必须覆盖整个 `scripts/po0/nftables/clients/**` 和已接入门禁的 `scripts/po0/reinstall/**`，不能退回只监听 Egern。
- 构建器必须显式控制编码和 LF：Bash/manifest/checksum 使用 UTF-8 no BOM；含中文的 Windows PowerShell `.ps1` 使用 UTF-8 BOM，避免 Windows PowerShell 5 按系统代码页解析失败。
