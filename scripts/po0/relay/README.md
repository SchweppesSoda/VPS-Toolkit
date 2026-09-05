# PO0 nftables Relay / LAN Worker

这里是 PO0 nftables 中转管理器、LAN Worker、Egern 当前出口 IP 上报和 PO0 Outbound IP Report client 的文档。

完整版本历史维护在 [`CHANGELOG.md`](./CHANGELOG.md)。各独立部署脚本的 `--changelog` 或更新完成提示只显示当前版本更新内容，避免远端单文件脚本长期累积历史。

核心边界：

- PO0 不开放 HTTP / WebAuth / Secret URL。
- PO0 不做本地 DDNS 解析；`--refresh-ddns` 只按外部已上报且仍在 TTL 内的 DDNS 结果重建/应用，不延长原上报 TTL。
- LAN Worker 负责 DDNS 解析上报、`iplist/ipdb` 资源任务、WebAuth Client、Self-report 接收端。
- LAN Worker 可选提供 PO0 manager HTTP 更新镜像；只代理固定 manager 脚本，PO0 用 resource token HMAC 校验后才替换本机脚本。
- Egern 负责移动设备当前出口 IPv4 上报，不再解析 DDNS。
- 资源任务只允许 `iplist`、`ipdb`，不支持任意远程 shell。
- PO0 托管 NAT/MANGLE 表刷新会先预检完整事务，再用单个 nftables 批次原子替换；事务失败时保留运行中的旧托管规则。

## 阅读路线

如果只是部署或日常维护，先看本文件，不需要先读 `po0-relay-technical.md`。技术文档只给维护实现、wrapper、协议和内部状态模型时使用。

| 你要做什么 | 看这里 |
| --- | --- |
| 首次部署 PO0 主控或 LAN Worker | “部署命令” |
| 找 PO0 主菜单功能分组、导出/导入、版本和 token bundle | “PO0 主控菜单”、“完整备份与导入恢复” |
| 管理源 IP 白名单、DDNS、动态来源、attack mode | “源 IP 白名单模式”、“DDNS Resolver 上报”、“attack mode” |
| 让内网机器领取 iplist/ipdb 资源任务 | “LAN Worker 资源任务” |
| 让 PO0 从 LAN Worker 一键拉取更新 manager | “PO0 manager HTTP 更新镜像” |
| 让 Linux/OpenWrt、macOS、Windows、Stash 或 Loon 自上报当前出口 IPv4 | “LAN Worker Self-report” |
| 配置 Egern 当前出口 IPv4 SSH 上报 | “Egern 当前出口 IP 上报”，以及 [`nftables/clients/egern/README.md`](../nftables/clients/egern/README.md) |
| 配置 Cloudflare Access / WebAuth 放行 | “LAN Worker WebAuth” |
| 构建或导入离线 IP 数据 | “IP 数据源” |
| 清理旧文件或检查兼容性 | “兼容与清理” |

## 发布渠道

PO0 nftables 六个可执行脚本和两个 OpenWrt APK 的正式发布资产统一放在 GitHub Release：

- `https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/nftables-relay-manager.sh`
- `https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-lan-client.sh`
- `https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-wan-probe.sh`
- `https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report.sh`
- `https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report-macos.sh`
- `https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report.ps1`
- `po0-wan-probe.apk`（OpenWrt WAN probe）
- `po0-outbound-ip-report.apk`（OpenWrt 上报器）
- `checksums.txt`（上述全部发布资产的 SHA-256）

旧 manager、LAN Worker 和 self-report raw URL 已禁用，不再作为兼容入口。Egern 标准 raw 路径、Stash/Loon 客户端资产、Egern 历史兼容路径、离线 iplist 构建器、外部 ipdb/iplist 数据源和未纳入本阶段的通用 VPS 工具 raw URL 仍是白名单。

如需测试或回滚下载源，可临时设置 `PO0_MANAGER_DOWNLOAD_URL`、`PO0_LAN_CLIENT_DOWNLOAD_URL`、`PO0_OUTBOUND_IP_REPORT_DOWNLOAD_URL`、`PO0_OUTBOUND_IP_REPORT_MACOS_DOWNLOAD_URL`、`PO0_OUTBOUND_IP_REPORT_PS_DOWNLOAD_URL`；旧 `PO0_SELF_REPORT_*` 下载源变量仍作为 legacy alias 接受。这些覆盖值不会写入配置文件。

## 部署命令

PO0 主控脚本推荐直接从 GitHub Release 发布文件下载到 PO0 后运行：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/nftables-relay-manager.sh -o /root/nftables-relay-manager.sh
chmod +x /root/nftables-relay-manager.sh
bash /root/nftables-relay-manager.sh
```

检查 PO0 上已安装的主控脚本版本：

```bash
ssh root@<PO0_HOST> 'bash /root/nftables-relay-manager.sh --version'
```

`--version` 会显示版本、build 构建标识、发布日期、当前脚本路径和默认安装路径。

查看 PO0 主控当前版本更新内容：

```bash
ssh root@<PO0_HOST> 'bash /root/nftables-relay-manager.sh --changelog'
```

LAN Worker 命令在内网 Worker 机器上执行，不在 PO0 上执行。PO0 manager 和 LAN Worker 当前按 Debian/Linux VPS 维护；OpenWrt/BusyBox 兼容只属于访问设备上的 Linux/OpenWrt PO0 Outbound IP Report client。DDNS 解析上报 + 资源任务轮询领取：

推荐先用交互向导。向导会检查到 PO0 的密钥 SSH；密钥 SSH 可用时，会自动调用 PO0 主控读取所需 token，然后写入本机配置、安装本机 `po0-lan-client` 命令，并按选择安装本机 Worker 轮询器 / systemd 服务。首次向导里的 PO0 SSH 地址一次只填一个；多个 PO0 目标后续进入菜单添加：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-lan-client.sh | bash
```

SSH 认证按向导选择：系统默认 SSH 配置/agent、已有私钥路径，或粘贴专用私钥。粘贴的私钥会保存到本机配置目录并设置 600 权限。`额外 SSH 参数` 是传给 `ssh` 的选项，例如 `-J jump-host` 或 `-o StrictHostKeyChecking=accept-new`，不是私钥短语；带短语的私钥需要 `ssh-agent`。菜单里的 `DDNS 解析上报 -> DDNS 目标 / 上报计划` 管理 DDNS 目标和本机上报间隔；`PO0 目标`、`SSH 私钥 / 参数`、`目标 Token`、`Self-report / WebAuth TTL` 分开管理目标、SSH、Token 和自上报/WebAuth TTL；`PO0 资源更新计划` 只读显示 PO0 端资源任务创建 cron，Worker 本机只安装轮询器领取 pending 任务。

初始化后常用本地命令：

```bash
po0-lan-client --menu
po0-lan-client --run
po0-lan-client --probe
```

检查 LAN Worker 上已安装的 client 版本：

```bash
po0-lan-client --version
```

PO0 nftables 子系统内带 `SCRIPT_VERSION`、`--version` / `--changelog` 或自更新提示的六个可独立部署脚本（PO0 manager、LAN Worker、WAN probe、三端 PO0 Outbound IP Report）统一使用 `YYYY.MM.DD+build.N` 混合版本格式。本轮脚本版本为 `2026.09.05+build.2`。两个 OpenWrt APK 另有各自的包版本：本轮 outbound 为 `2026.09.05-r1`，WAN probe 继续为 `2026.08.30-r5`。正式 PO0 Release 发布文件的脚本内部版本必须与 release tag 尾号一致：`po0-vYYYY.MM.DD.N` 对应 `YYYY.MM.DD+build.N`，例如 `po0-v2026.07.01.7` 对应 `2026.07.01+build.7`。完整历史写在 [`CHANGELOG.md`](CHANGELOG.md)。

更新 LAN Worker 上已安装的 client：

```bash
po0-lan-client --upgrade-self
po0-lan-client --version
```

## PO0 manager HTTP 更新镜像

这个功能用于“日常只登录 PO0，也能从 LAN Worker 拉取新版 manager”。先在 LAN Worker 上配置一次 HTTP-only 更新镜像；LAN Worker 到 GitHub Release 发布文件使用 HTTPS，PO0 到 LAN Worker 按显式 HTTP URL 拉取。该入口只服务固定路径 `/po0-manager-update/nftables-relay-manager.sh`，不是任意 URL 代理，也不是 PO0 HTTP 控制面。

LAN Worker 上配置镜像公网主机/IP。未写端口时默认使用 `2333`，也可以显式传入 `HOST:PORT`；Caddy 入口按端口监听，同一端口既可用域名访问，也可直接用 IP 访问：

```bash
po0-lan-client --install-manager-update-http --manager-update-host <LAN_WORKER_IP>
```

`--manager-update-domain HOST[:PORT]` 是历史兼容参数，仍可继续使用；新文档示例优先写 `--manager-update-host HOST[:PORT]`。

PO0 上拉取更新：

```bash
bash /root/nftables-relay-manager.sh --upgrade-manager-from-lan http://<LAN_WORKER_IP>:2333/po0-manager-update/nftables-relay-manager.sh
```

也可以在 PO0 主菜单进入 `脚本版本 / 更新 -> 从 LAN Worker HTTP 更新 manager`，第一次输入 URL 后会保存到 PO0 设置文件；如果入口不是 HTTP 默认 80 端口，必须在 URL 中写明 `:PORT`，例如 `:2333`。更新时 PO0 会读取本机 resource token，向 LAN Worker 发送随机 nonce 和 `token_id`，下载后校验 HMAC、SHA-256、size、脚本标识、changelog 和 `bash -n`；通过后备份旧脚本并原子替换。更新成功后会询问是否刷新受限 SSH wrapper；从菜单更新时，停留显示结果后按回车会重新打开新版菜单。命令行直接执行 `--upgrade-manager-from-lan` 仍会更新后退出，方便继续串行执行其它命令。更新不会自动应用 nftables，也不会自动运行诊断。

也可以显式进入向导：

```bash
po0-lan-client --wizard
```

如果旧版本安装后没有 `po0-lan-client` 命令，可手动补装：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-lan-client.sh -o /usr/local/sbin/po0-lan-client
chmod 755 /usr/local/sbin/po0-lan-client
/usr/local/sbin/po0-lan-client --menu
```

如果要用于自动化，仍可直接传参数：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-lan-client.sh | bash -s -- --bootstrap --po0-host <PO0_HOST> --po0-script /root/nftables-relay-manager.sh --source-key <DDNS_SOURCE_KEY> --ddns-domain <DDNS_DOMAIN> --token <DDNS_TOKEN> --resource-token <RESOURCE_TOKEN> --ddns-interval-seconds 3600 --install-cron
```

LAN Worker：只做 `iplist/ipdb` 资源任务：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-lan-client.sh | bash -s -- --bootstrap --po0-host <PO0_HOST> --po0-script /root/nftables-relay-manager.sh --resource-token <RESOURCE_TOKEN> --install-cron 1440
```

`--install-cron` 是安装 Worker 本机计划任务。DDNS resolver 上报和资源任务领取是两条不同计划：DDNS 间隔在 LAN Worker 本机设置，应小于 PO0 端 DDNS 来源 TTL；这个 TTL 在 PO0 主控的 `管理源 IP 白名单 -> 动态来源与客户端 -> 管理 DDNS 来源` 添加/编辑来源时设置。资源任务只负责发现并领取 PO0 已创建的 pending 任务，默认每 `1440` 分钟检查一次，交互菜单可设为 `1-10080` 分钟。资源任务的创建周期在 PO0 主控的 `内网资源更新任务 -> 安装 / 更新 PO0 定时创建` 中设置。

兼容旧用法时，`--install-cron N` 会把 DDNS 和资源任务两个计划都设为 `N` 分钟；不带 `N` 时，LAN Worker 默认 DDNS 每 `3600` 秒上报、资源任务每 `1440` 分钟检查一次。推荐用 `--ddns-interval-seconds 3600` 显式设置 DDNS 上报间隔，资源任务领取计划仍按分钟设置。

Linux / OpenWrt PO0 Outbound IP Report client：

首次交互式运行默认进入菜单。菜单里的 `1) 配置并保存上报参数` 只写本地配置文件，不安装 cron，也不保证安装 `po0-outbound-ip-report` 命令；`3) 安装 / 更新定时上报` 会保存配置、安装本机脚本并写入 cron；`8) 从 GitHub 更新脚本` 会更新本机 `po0-outbound-ip-report` 命令并重新打开新版菜单；`9) 卸载本客户端` 会删除本脚本管理的 cron 和本机安装脚本，配置文件与日志默认保留，也可在确认后一起删除。

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report.sh | bash
```

首次保存默认配置并打开菜单，不需要先在命令行写域名和 secret；进菜单后用 `1) 配置并保存上报参数` 填写或修改：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report.sh | bash -s -- --save-config --menu
```

非交互保存配置，不安装 cron；未传 `--source-id` / `--identity` 时，客户端会用 hostname + machine-id/MAC 生成默认 Source ID，并用设备名作为 Identity：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report.sh | bash -s -- --worker-url https://<SELF_REPORT_DOMAIN>/report --secret <SELF_REPORT_SECRET> --save-config
```

保存配置后，如果本机已经通过菜单更新或安装 cron 落盘了 `po0-outbound-ip-report` 命令，可以直接复用已保存配置：

```bash
po0-outbound-ip-report --menu
```

```bash
po0-outbound-ip-report
```

```bash
po0-outbound-ip-report --install-cron
```

安装 / 更新 cron，默认每 `3600` 秒上报一次；安装时会同步保存配置，之后 cron 只引用配置文件，不把 token 展开写入 cron 命令行：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report.sh | bash -s -- --worker-url https://<SELF_REPORT_DOMAIN>/report --secret <SELF_REPORT_SECRET> --interval-seconds 3600 --install-cron
```

macOS PO0 Outbound IP Report client 使用专用脚本和 launchd，不复用 Linux/OpenWrt cron 脚本。首次保存默认配置并打开菜单：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report-macos.sh | bash -s -- --save-config --menu
```

macOS 非交互安装 / 更新 launchd 定时上报：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report-macos.sh | bash -s -- --worker-url https://<SELF_REPORT_DOMAIN>/report --secret <SELF_REPORT_SECRET> --interval-seconds 3600 --install-launchd
```

macOS 默认静默，只写 `/tmp/po0-outbound-ip-report.log`。如需上报成功或失败后弹 macOS 通知，安装或保存配置时显式加 `--notify`；要恢复静默可用 `--no-notify --install-launchd` 刷新计划，或在菜单“通知 / 静默模式”里切换。

命令行也可直接更新、查看版本或查看当前更新内容：

```bash
po0-outbound-ip-report --upgrade-self
```

```bash
po0-outbound-ip-report --version
```

```bash
po0-outbound-ip-report --changelog
```

Windows PowerShell PO0 Outbound IP Report client：

首次交互式运行默认进入菜单，推荐显式加 `-Menu`。菜单里的 `1) 配置并保存上报参数` 只写本地配置文件，不安装计划任务；`3) 安装 / 更新定时上报` 会保存配置、安装本机脚本并写入计划任务；`6) Windows 通知 / 静默模式` 会保存通知偏好，并在计划任务已安装时同步计划任务启动文件；`9) 从 GitHub 更新脚本` 会更新本机 `po0-outbound-ip-report.ps1` 并重新打开新版菜单；`10) 卸载本客户端` 会删除本脚本管理的计划任务、计划任务启动文件和本机安装脚本，配置文件与日志默认保留，也可在确认后一起删除。

```powershell
$script = "$env:TEMP\po0-outbound-ip-report.ps1"
Invoke-WebRequest -UseBasicParsing 'https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report.ps1' -OutFile $script -TimeoutSec 120
powershell -ExecutionPolicy Bypass -File $script -Menu
```

非交互保存配置，不安装计划任务；普通用户默认配置和脚本路径在 `%LOCALAPPDATA%\PO0`，管理员运行时会改用 `%ProgramData%\PO0\po0-outbound-ip-report.ps1`，不要混用两个权限环境：

```powershell
$script = "$env:TEMP\po0-outbound-ip-report.ps1"
Invoke-WebRequest -UseBasicParsing 'https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report.ps1' -OutFile $script -TimeoutSec 120
powershell -ExecutionPolicy Bypass -File $script -WorkerUrl "https://<SELF_REPORT_DOMAIN>/report" -SourceId $env:COMPUTERNAME -Identity $env:COMPUTERNAME -Secret "<SELF_REPORT_SECRET>" -SaveConfig
```

`-SourceId` 是 PO0 端分组、续期和裁剪用的稳定 key；`-Identity` 只做备注和审计。多台设备不要共用同一个 `SourceId`。

保存配置后，如果本机已经通过菜单更新或安装计划任务落盘了脚本，普通用户从固定路径再次运行。

打开交互菜单：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\PO0\po0-outbound-ip-report.ps1" -Menu
```

立即按已保存配置上报一次：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\PO0\po0-outbound-ip-report.ps1" -RunOnce
```

保存配置并安装 / 更新计划任务：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\PO0\po0-outbound-ip-report.ps1" -InstallTask -IntervalSeconds 3600
```

管理员安装时才把 `$env:LOCALAPPDATA` 改为 `$env:ProgramData`。

查看计划任务状态和最近日志摘要：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\PO0\po0-outbound-ip-report.ps1" -ScheduleStatus
```

从 GitHub Release 发布文件更新本机脚本：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\PO0\po0-outbound-ip-report.ps1" -UpgradeSelf
```

查看当前脚本版本：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\PO0\po0-outbound-ip-report.ps1" -Version
```

查看当前版本更新内容：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\PO0\po0-outbound-ip-report.ps1" -Changelog
```

Windows 非交互安装 / 更新计划任务时，默认每 `3600` 秒上报一次且静默只写日志；安装时会保存本地配置。`-SourceId` 和 `-Identity` 推荐填设备名，`-Secret` 只填纯 token，不要带 `secret:` 或中文冒号前缀；如需自动上报后弹 Windows 通知，额外加 `-Notify`；要显式恢复静默可用 `-NoNotify` 或菜单“Windows 通知 / 静默模式”切换：

```powershell
$script = "$env:TEMP\po0-outbound-ip-report.ps1"
Invoke-WebRequest -UseBasicParsing 'https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report.ps1' -OutFile $script -TimeoutSec 120
powershell -ExecutionPolicy Bypass -File $script -WorkerUrl "https://<SELF_REPORT_DOMAIN>/report" -SourceId $env:COMPUTERNAME -Identity $env:COMPUTERNAME -Secret "<SELF_REPORT_SECRET>" -InstallTask -IntervalSeconds 3600
```

Egern 模块 下载 URL：

```text
https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/egern/PO0-SSH-IP-Report.yaml
```

## PO0 主控菜单

主菜单按功能分组：

- 部署与概览：安装、刷新 PO0 公网 IP、查看 Dashboard。
- 转发规则：新增、编辑、排序、启停、删除、导入、导出转发规则。
- 来源、客户端与资源：源 IP 白名单、LAN Worker/客户端/Egern 部署命令、内网资源更新任务。
- 系统维护：中转参数、自检、脚本版本、BBR、完整备份 / 导入恢复。

`中转机参数` 里可以设置本机名称 / 导出前缀，例如 `PO0XX`、`PO0YY`。设置后，导出规则默认文件名会变成 `PO0XX-po0-relay-export-YYYYMMDD_HHMMSS.txt`；留空则继续使用旧的 `po0-relay-export-YYYYMMDD_HHMMSS.txt`。

客户端部署命令可由主控自动生成：

```bash
bash /root/nftables-relay-manager.sh --show-client-deploy-commands
```

不带 topic 时，这个命令只输出可用 topic 索引。按需指定 `lan-resource`、`lan-ddns`、`self-server`、`self-client`、`webauth` 或 `egern` 才会输出对应部署命令和 token 示例。

LAN Worker 向导使用的机器可读 token bundle：

```bash
bash /root/nftables-relay-manager.sh --worker-token-bundle
bash /root/nftables-relay-manager.sh --worker-token-bundle --ensure-resource-token
```

`--worker-token-bundle` 输出 `KEY=value`，供 LAN Worker 通过 SSH 读取。只有带 `--ensure-resource-token` 时，才会在资源任务 token 不存在时自动生成；已有 token 不会被重置。

## 完整备份与导入恢复

PO0 manager 和 LAN Worker 都支持完整备份。默认导出是敏感全量包，会包含 Token、状态文件、资源任务、SSH 相关密钥/公钥信息和脚本快照；导出后脚本会强制尝试 `chmod 600` 备份包。运行时锁文件（如 `*.lock`、`.po0-lan-client.lock`）不属于可迁移状态，不会纳入新备份。

PO0 导出：

```bash
bash /root/nftables-relay-manager.sh --backup-export
```

PO0 导入默认只恢复 `/etc/nftables.d` 下的配置、Token、状态、iplist/ipdb、resource inbox 等 live state，并用当前脚本重新生成受限 SSH wrapper；不会默认改 cron、systemd/nftables service、`/etc/nftables.conf`、sysctl 或 `authorized_keys`：

```bash
bash /root/nftables-relay-manager.sh --backup-import /etc/nftables.d/backups/po0-manager-full-backup-YYYYMMDD_HHMMSS.tar.gz
```

灾难恢复时显式恢复全部入口：

```bash
bash /root/nftables-relay-manager.sh --backup-import /etc/nftables.d/backups/po0-manager-full-backup-YYYYMMDD_HHMMSS.tar.gz --restore-all
```

也可以分开恢复：`--restore-cron` 恢复 PO0 管理的 cron，并优先按备份里的托管片段识别旧脚本路径后重写为当前 manager 路径；`--restore-systemd` 重新生成学习服务，`--restore-nftables` 恢复 `/etc/nftables.conf`/sysctl 并尝试应用 nftables，`--restore-report-keys` 恢复 PO0 受限 `authorized_keys` 条目。恢复受限 key 时不会照搬旧 forced command，而是用当前脚本路径和当前 wrapper 重新生成。

LAN Worker 导出：

```bash
po0-lan-client --backup-export
```

LAN Worker 导入默认只恢复目标配置、统计/事件、本机 `settings.env`、配置目录里的 `ssh-key-*` 和目标 SSH 参数引用的 `-i`/`IdentityFile` 私钥；不会默认改本机 cron、systemd service 或 Caddy：

```bash
po0-lan-client --backup-import ~/.config/po0-lan-client/backups/po0-lan-client-backup-YYYYMMDD_HHMMSS.tar.gz
```

需要恢复运行入口时显式添加 `--restore-cron`、`--restore-systemd`、`--restore-caddy`，或直接使用 `--restore-all`；恢复 cron 时会优先按备份里的托管片段识别旧脚本路径，并把脚本路径和配置路径重写为当前 LAN Worker 路径。LAN Worker 会把 `SELF_REPORT_SECRET`、Self-report/WebAuth 监听、TTL、HTTPS/Caddy 路径、Worker ID、资源任务超时和轮询间隔持久写入配置目录下的 `settings.env`，升级脚本后会复用已有 secret 和 TTL 设置，不会因为脚本更新而重新生成 secret；如果是旧安装还没有 `settings.env`，导出前会尽量从已安装的 Self-report/WebAuth systemd unit 回填 secret、监听地址、TTL、目标和 token。

Egern 的 PO0 受限 SSH 上报公钥会随 PO0 备份记录，并可通过 `--restore-report-keys` 或 `--restore-all` 恢复；Egern 设备上的私钥和 Egern app 本地配置不在 PO0/LAN Worker 管辖范围内，不会导出。DDNS、Self-report、WebAuth、Egern SSH report、resource task 等 Token 都在 PO0 或 LAN Worker 配置/状态文件内，会随默认完整备份导出和恢复。

## 源 IP 白名单模式

新安装默认模式是 `trusted_dynamic`。旧配置会自动映射：

```text
region        -> region_only
custom        -> trusted_dynamic
region_custom -> region_plus_trusted
```

可选模式：

```text
manual_only           仅手动 CIDR（SSH 临时需在菜单中手动开启）
trusted_dynamic       手动 + DDNS + Client IP + SSH report + WebAuth + learned（SSH 临时需手动开启）
region_plus_trusted   地区库 + trusted_dynamic
region_only           仅地区库
custom_sources        高级自选来源组合
```

如果不想把所有动态来源都打开，选择 `custom_sources`，或在菜单里进入：

```text
管理源 IP 白名单 -> 动态来源开关（高级自选来源）
```

可组合的来源：

```text
manual, ssh_temp, ddns, client_ip, ssh_report, webauth, learned, region
```

动态来源缓存策略：
- `ddns`、`client_ip`、`ssh_report`、`webauth` 按 `source_type + source-id` 分组；底层状态文件里的 `source_value` 就是这个 source-id。
- 每个 `source_type + source-id` 默认最多保留 `12` 个有效 CIDR；`/32` 和 `/24` 都各算 1 条，共享同一个 `12` 条上限；菜单的“来源 / IP 明细”会按 source-id 显示 `n/12` 用量。
- `source-id` 是分组、续期和裁剪的稳定 key；`identity` 只做备注和审计，多设备必须使用不同 `source-id`。
- 已存在 CIDR 再次上报会刷新时间和过期时间，不重复新增。
- `ssh_temp` 当前 SSH 临时放行再次加入同一 `/32` 时会刷新时间和过期时间，不复用过期旧记录。
- 过期条目不会进入最终 nftables 白名单缓存。

手动清理和安装清理 cron：

```bash
bash /root/nftables-relay-manager.sh --cleanup-dynamic-allowlist
bash /root/nftables-relay-manager.sh --install-dynamic-allowlist-cleanup-cron daily
```

交互菜单里，动态来源缓存维护、来源 IP 学习和被阻挡访问排障已拆分：

```text
管理源 IP 白名单 -> 动态来源缓存维护
管理源 IP 白名单 -> 来源 IP 学习与候选提升
管理源 IP 白名单 -> 被阻挡访问日志
```

## DDNS Resolver 上报

推荐流程：

1. PO0 端在“管理源 IP 白名单 -> 动态来源与客户端 -> 管理 DDNS 来源”里添加域名并生成 DDNS token。
2. LAN Worker、路由器、OpenWrt、NAS 或 Windows/Linux 小脚本解析这个 DDNS 域名的公网 A 记录。
3. 解析结果通过 SSH 调 PO0：

```bash
bash /root/nftables-relay-manager.sh --ddns-report <source-key> <ipv4[,ipv4...]> <token>
```

只读检查：

```bash
bash /root/nftables-relay-manager.sh --ddns-report-check <source-key> <token>
```

LAN Worker 里 `--source-key` 只是 PO0 DDNS 来源 key/名称，用来匹配 PO0 来源表；`--ddns-domain` 才是真正要解析的 DDNS 域名。旧参数 `--domain` 仍作为兼容别名：没有 `--ddns-domain` 时，同时作为 source key 和 DDNS 域名。PO0 新增 DDNS 来源默认 TTL 为 `43200` 秒（12 小时），可在 `60-86400` 秒内调整；LAN Worker 的 DDNS 上报间隔应明显小于这个 TTL。

多个 PO0 或多个域名推荐先整理成“DDNS 上报目标”：

```text
source_key|ddns_domain|host|port|user|script|token|ssh_args
home-sg|home.example.com|sg-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_SG|
home-us|home.example.com|us-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_US|
office-sg|office.example.com|sg-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_OFFICE_SG|
```

临时执行可以直接传目标行：

```bash
po0-lan-client --run --ddns-targets 'home-sg|home.example.com|sg-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_SG|;home-us|home.example.com|us-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_US|'
```

首次部署推荐运行 `po0-lan-client --wizard`。长期维护可进入 `po0-lan-client --menu`，在 `DDNS 解析上报 -> DDNS 目标 / 上报计划` 里查看或编辑 DDNS 目标、安装/更新 DDNS 本机上报计划，并查看 PO0 DDNS TTL 设置位置；也可以分别在 `PO0 目标`、`SSH 私钥 / 参数`、`目标 Token`、`Self-report / WebAuth TTL` 里查看、编辑、删除、启停 PO0 目标，并管理目标 SSH 私钥、SSH 参数、Token 和自上报/WebAuth TTL；底层仍保存到本机配置文件，旧配置继续兼容。

PO0 不做本地 DDNS 解析。`--refresh-ddns` 只会把已经由 LAN Worker/路由器上报、且仍在 TTL 内的结果重建/应用；它不会延长原上报 TTL：

```bash
bash /root/nftables-relay-manager.sh --refresh-ddns
```

## LAN Worker 资源任务

PO0 端创建资源任务。这里决定资源任务“多久创建一次”：

```bash
bash /root/nftables-relay-manager.sh --resource-task-create all
bash /root/nftables-relay-manager.sh --install-resource-task-cron all daily
```

LAN Worker 端只轮询领取 PO0 已创建的 pending 任务、下载/构建文件，再通过 SSH 调 PO0 manager 上传回 PO0。固定任务白名单只有：

```text
iplist
ipdb
```

同一轮资源轮询会持续领取 pending 任务，直到 PO0 返回无任务或达到本轮上限。默认上限是 `PO0_RESOURCE_TASK_MAX_PER_RUN=10`，设为 `0` 表示不设上限。`iplist` 的 txt 数据文件默认并发下载，默认 `PO0_IPLIST_JOBS=16`，可调范围 `1-50`。资源下载后会通过 SSH stdin 上传到 PO0，上传默认超时 `PO0_RESOURCE_UPLOAD_TIMEOUT_SECONDS=900`，PO0 校验/导入默认超时 `PO0_RESOURCE_COMPLETE_TIMEOUT_SECONDS=600`。PO0 接收端默认最多接收 8 MiB 的 `iplist.tar.gz` 和 128 MiB 的 `qqwry.ipdb`；如本地数据源确实更大，可在 PO0 运行 manager 时分别用 `PO0_RESOURCE_IPLIST_MAX_BYTES`、`PO0_RESOURCE_IPDB_MAX_BYTES` 覆盖为正整数的字节数。声明大小超限、配置值无效、正文短于声明长度或带有尾随数据时都会拒绝上传且不保留临时文件；现有 `--resource-task-upload TASK_ID WORKER_ID SHA256 SIZE TOKEN` 调用方式不变。

LAN Worker 菜单 `资源统计` 会显示资源任务聚合统计和最近事件日志。默认聚合统计写入配置目录下的 `resource-stats.tsv`，逐次事件写入 `resource-events.tsv`；可分别用 `PO0_LAN_RESOURCE_STATS` 和 `PO0_LAN_RESOURCE_EVENTS` 覆盖路径。菜单 `清理资源统计` 可手动清空事件日志、清空全部资源统计，或只保留最近 N 条事件。每次资源轮询后会自动裁剪事件日志，默认保留最近 `500` 条，可用 `PO0_RESOURCE_EVENTS_KEEP` 调整；聚合统计不会自动清空。

如果 LAN Worker 使用 PO0 端“专用受限 SSH 上报 key”，请使用 `scope=worker` 并确保 PO0 端 wrapper 已由新版脚本重新安装/刷新。`worker` scope 只允许上报和资源任务 Worker 动作：`--resource-task-ping/claim/upload/complete/fail` 以及只读 `--resource-task-cron-status`，不允许创建资源任务或安装 PO0 端 cron。资源产物通过 manager stdin 上传，不需要 SCP 权限。

Worker 交互向导、管道运行且需要本机轮询器或服务时，会自动落盘到：

```text
root:     /usr/local/sbin/po0-lan-client
non-root: ~/.local/bin/po0-lan-client
```

如果资源轮询仍输出 `scp: Connection closed`，说明实际运行的 LAN Worker 脚本仍是旧的 SCP 上传版，或 cron 仍指向旧路径。先在 LAN Worker 上执行：

```bash
/usr/local/sbin/po0-lan-client --version
/usr/local/sbin/po0-lan-client --upgrade-self
/usr/local/sbin/po0-lan-client --install-cron
```

新版自检应显示 `版本` 为 `2026.06.18+build.6` 或更新；资源轮询不再调用 `scp`，资源产物通过 PO0 manager stdin 上传。

`--upgrade-self` 更新成功后会输出安装路径、权限设置结果、版本变化和新脚本内置的更新内容；具体状态再用 `--version` 查看。从菜单里选择“从 GitHub 更新脚本”时，更新成功后会自动设置最终安装路径的执行权限，停留显示更新结果，按回车后再打开新版菜单。命令行直接执行 `--upgrade-self` 仍会更新后退出，方便继续串行执行 `--version` 或 `--install-cron`。

如果 LAN Worker 查询 PO0 创建计划时出现 `--resource-task-cron-status not allowed for scope worker`，说明 PO0 上的专用受限 SSH wrapper 还没刷新到新版；在 PO0 上用新版 manager 执行 `--refresh-report-key-wrapper` 即可。这个报错只影响创建计划只读查询，不影响 pending 资源任务领取、上传和完成。

配置里旧的 `PO0_SCRIPT=/root/nftables-relay-manager.sh` 继续兼容。

## LAN Worker 本机官方防火墙上报

LAN Worker 可以另外给“运行它的这台机器”的实际默认出口加白。它不代替访问设备、手机或下游客户端上报，也不使用 DDNS、Self-report、WebAuth 的 TTL 或 token。

默认关闭。进入 `po0-lan-client --menu`，选择 `29) 配置官方防火墙 token`，输入逗号分隔的官方 token；也可以写固定槽位，例如：

```text
pgnfw_example_a,pgnfw_example_b@0
```

每个官方账号最多有 5 个槽位；`@0` 到 `@4` 是官方接口的内部槽位编号，界面显示为槽位 1 到 5。即使写成不同槽位，同一 token 也只允许配置一次，以避免并发竞态。列表会严格拒绝空项、重复项、错误格式和超过 16 个 token。token 只保存到配置目录下的 600 权限 `settings.env`，不会进入 cron/systemd 参数、进程参数、日志、通知或本地状态。

查看状态时使用：

```bash
po0-lan-client --official-firewall-status
```

这是只读查询；当前出口还没有命中时只显示 `missing`，不会加白。真正上报使用 `po0-lan-client --run-official-firewall`，每个 token 都先 GET，只有当前出口缺失或固定槽位不匹配时才 POST。自动计划每 10 分钟唤醒一次，但官方通道自己的最近尝试时间固定为 600 秒；旧的 LAN Worker / Self-report 车道仍按自己的计划（通常约 1 小时）和 TTL 工作，互不挪用；一条失败也不会让另一条停止。

安装本机轮询器时，即使没有 DDNS 或资源任务目标，只要已经配置官方 token，也会单独安装官方防火墙计划：

```bash
po0-lan-client --install-cron
```

官方请求由 LAN Worker 直接通过本机默认路由访问固定 HTTPS 接口。需要指定某条 WAN 时，请在主 OpenWrt 的官方 WAN 绑定配置中完成；通用 LAN Worker 不会假装把默认路由当成指定 WAN。

访问设备客户端在同一轮总是先执行官方车道，再执行原有车道；两边各自记录结果，任一边失败不会取消另一边，因此可以报告“部分完成”。如果当前 Wi-Fi SSID 命中本机跳过列表，两条车道会一起跳过；`--force-report` 只绕过本机的 due/SSID 判断，仍不能跳过官方 GET-first 规则。官方状态摘要（各端支持的状态页或 Widget）只显示状态、已用/上限额度、当前出口和槽位，不显示 token；定时任务默认保持安静，手动、失败或部分完成时才按客户端设置通知。

除主 OpenWrt 的官方绑定外，Linux、macOS、Windows、Egern 和普通 LAN Worker 都使用本机默认出口（Egern 为 `DIRECT`）。只有主 OpenWrt 可以在官方绑定里用 `mwan3` 明确选择 `wan1` 或 `wan2`；未指定或其它设备不会伪造指定 WAN，也不在失败时偷偷切换出口。实现参考 [kelenetwork/po0fw](https://github.com/kelenetwork/po0fw)（MIT），不是 Chicksure 专属协议。

### 各端最短配置入口

- LAN Worker：`po0-lan-client --menu` → `29) 配置官方防火墙 token`；只读用 `po0-lan-client --official-firewall-status`，运行用 `po0-lan-client --run-official-firewall`。
- Linux / OpenWrt 访问设备：在 `po0-outbound-ip-report --menu` 保存 `PO0_FIREWALL_TOKENS`，或交互设置后用 `--official-status` / `--official-only`；主 OpenWrt 的 WAN 选择由 APK/LuCI 的官方绑定交给 `mwan3`。
- macOS：`po0-outbound-ip-report-macos.sh --save-config --menu` 保存 token，查询用 `--official-status`，独立运行用 `--official-only`；请求走本机默认出口。
- Windows：`po0-outbound-ip-report.ps1 -Menu` 进入菜单并在其中配置保存 token，查询用 `-OfficialStatus`，独立运行用 `-OfficialOnly`；计划任务仍按 Windows 默认出口。
- Egern / 移动端：在标准 Egern YAML 的 `PO0_FIREWALL_TOKENS` 配置项保存 token，动作 `PO0 官方防火墙状态（只读）` 查看；自动上报使用 `DIRECT`，SSID guard 和通知在 Egern 本机配置。
- 主 OpenWrt APK：LuCI 的 `PO0 Outbound IP Report` 页面配置官方 token、开关和官方 WAN 绑定；需要选出口时只填 `wan1` 或 `wan2`，由 `mwan3` 执行。

## LAN Worker Self-report

Self-report 用于“访问设备自己检测当前出口 IPv4，然后报给 LAN Worker”。PO0 仍然不开放 HTTP，LAN Worker 通过 SSH 调 PO0 的 `--client-ip-report`：

```text
访问设备 PO0 Outbound IP Report client -> LAN Worker HTTPS/Caddy -> 本机 self-report 后端 -> SSH -> PO0 --client-ip-report
```

LAN Worker 启动接收端推荐走菜单：

```bash
po0-lan-client --menu
```

进入 `Self-report 自上报 -> Self-report 配置 / 启动` 后，可以查看 PO0 目标、维护 `Self-report client-ip Token`、设置 source/TTL、设置监听地址、生成/修改 `Self-report secret`，并安装/更新后台服务。安装或更新服务会原样复用已有 secret；只有尚未配置时才自动生成一次并保存到本机设置，生成后需要把该值同步到访问设备。`/report` 和 Stash 接口都要求 secret，底层检测到空值时会拒绝上报。推荐使用“配置 HTTPS 域名 / Caddy”：输入已经解析到 LAN Worker 的域名后，脚本会配置 Caddy 自动证书和续期，并把 self-report 后端改为只监听 `127.0.0.1:8788`；访问设备上报到 `https://<SELF_REPORT_DOMAIN>/report`。请用服务器防火墙或云安全组放行 TCP `80/443`，不建议公网继续放行 `8788`。菜单里的“前台启动服务”会占用当前终端，适合临时测试，按 `Ctrl+C` 退出。

Stash 使用同一套 HTTPS 域名、后台服务、PO0 目标和 `Self-report secret`，专用入口为 `POST https://<SELF_REPORT_DOMAIN>/stash-report/v1`。请求必须在 `Authorization: Bearer <SELF_REPORT_SECRET>` 中携带 secret，并提交 JSON 字段 `source_id`、`ip`、`network`、`observed_at`、`request_id`；LAN Worker 对 Stash 的蜂窝、Wi-Fi 和未知网络统一按 `/32` 上报，客户端网络探测失败也不会扩大放行范围。`observed_at` 支持 Unix 秒或带时区的 ISO-8601 时间，和 LAN Worker 当前时间相差不能超过 10 分钟；同一后台进程会把已接收的 `request_id` 保留 10 分钟并拒绝重复请求。成功响应会给出 PO0 实际接收的 `accepted_cidr`、接收/过期时间和各目标结果。旧 `/report` 入口、参数和文本响应不变。已有 LAN Worker 升级脚本后，需要再执行一次菜单里的“配置 HTTPS 域名 / Caddy”，让它重写 Caddy snippet 并重启 Self-report 后台服务，新入口才会生效。

正式方案是 `Stash -> HTTPS LAN Worker /stash-report/v1 -> SSH -> PO0 --client-ip-report`。Stash 脚本和可导入的正式 override 位于 `scripts/po0/nftables/clients/stash/po0-stash-report.js` 与 `PO0.LAN-Report.stoverride`。仓库另带默认关闭的 `PO0.SSH-Report.PoC.stoverride`：`Stash SSH proxy -> PO0 127.0.0.1:8790 receiver -> --ssh-ip-report`；备用 receiver 只监听 PO0 loopback，不经过 LAN Worker，也不应把 `8790` 暴露到公网。

Loon 客户端使用公开 Raw 资产：主插件为 [`PO0.LAN-Report.lpx`](../nftables/clients/loon/PO0.LAN-Report.lpx)，插件再加载同目录的 [`po0-loon-report.js`](../nftables/clients/loon/po0-loon-report.js)。Worker URL 和 Token 只在 Loon 的插件输入中设置，不写入仓库。

备用 receiver 在 PO0 上的安装示例：

```bash
install -D -m 0755 scripts/po0/nftables/clients/stash/po0-stash-loopback-receiver.py /usr/local/libexec/po0-stash-loopback-receiver.py
install -D -m 0644 scripts/po0/nftables/clients/stash/po0-stash-loopback-receiver.service /etc/systemd/system/po0-stash-loopback-receiver.service
install -D -m 0600 scripts/po0/nftables/clients/stash/stash-loopback-receiver.env.example /etc/po0/stash-loopback-receiver.env
# 编辑 /etc/po0/stash-loopback-receiver.env，填写独立 receiver Bearer、SSH report token 和 manager 路径。
systemctl daemon-reload
systemctl enable --now po0-stash-loopback-receiver.service
curl -fsS http://127.0.0.1:8790/health
```

Stash 登录 PO0 应使用专用 SSH 用户和密钥，只允许本地转发到 `127.0.0.1:8790`；不要给该 key 普通 shell、任意端口转发或 manager forced-command 权限。receiver 自己校验 Bearer 后，才用本机环境文件中的 token 调 manager。

同一个 Self-report 子菜单也可以查看 `po0-lan-self-report.service` 的后台服务状态、最近 journal 日志、实时日志，以及 HTTPS/Caddy 状态和最近 Caddy 日志；实时日志同样按 `Ctrl+C` 退出。

安装后台服务前至少要有一个启用的 PO0 目标，并且该目标已填写 `Self-report client-ip Token`。如果状态里看到 `--po0-host` 或 `--client-ip-token` 为空，说明旧版菜单曾写入空 service；在菜单补齐目标 Token 和 secret 后重新执行“安装 / 更新后台服务”或“配置 HTTPS 域名 / Caddy”即可覆盖。已安装过旧版 `0.0.0.0:8788` HTTP 直连 service 的机器，启用 HTTPS 后需要重新执行“配置 HTTPS 域名 / Caddy”，让 systemd unit 切换到 `127.0.0.1:8788`。

命令行启动接收端：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-lan-client.sh | bash -s -- --install-self
po0-lan-client --install-self-report-https --self-report-https-domain <SELF_REPORT_DOMAIN> --po0-host <PO0_HOST> --po0-script /root/nftables-relay-manager.sh --self-report-source self-report --client-ip-token <CLIENT_REPORT_TOKEN> --self-report-secret <SELF_REPORT_SECRET>
```

Self-report / WebAuth 放行 TTL 默认均为 `43200` 秒（12 小时），由 LAN Worker 上报 PO0 时传入；可以在启动接收端时加 `--self-report-ttl <秒数>` / `--webauth-ttl <秒数>`，也可以在 LAN Worker 菜单 `PO0 目标、SSH、Token 与 TTL -> Self-report / WebAuth TTL` 里修改目标覆盖值。访问设备客户端只决定“多久上报一次”，不决定 TTL。Self-report / WebAuth TTL 会被限制在 `60-604800` 秒内。升级旧安装时，本机 `settings.env` 里恰好等于旧默认 `3600` 或 `21600` 的默认 TTL 会在脚本加载时迁移到新默认；目标行里显式写的 TTL 不自动改写。

PO0 manager 的 `--client-ip-report` 最后一个可选参数可以指定 `24` 或 `32`，省略时继续按 `/32` 处理。该参数保留给受控调用方使用；当前 Stash HTTPS 上报固定传入 `32`，不再根据客户端网络判断扩大网段。PO0 会把地址归一化为实际网段后写入 `client_ip` 白名单，并继续按同一个 `source-id` 做续期和数量裁剪。

同一轮 Self-report / WebAuth 上报如果配置了多个 PO0 目标，LAN Worker 会并发 SSH 到各目标；全部目标成功才返回成功，任一目标失败或超时会返回 502，并在正文保留各目标明细。这样慢 PO0 不会把多个目标耗时串行累加到访问设备的 HTTP 超时窗口里。

多个 PO0 用“设备自上报目标”合并到同一个 LAN Worker：

```text
source|host|port|user|script|token|ttl|ssh_args
self-report|sg-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_SG|43200|
self-report|us-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_US|43200|
```

```bash
po0-lan-client --install-self-report-https --self-report-https-domain <SELF_REPORT_DOMAIN> --self-report-targets 'self-report|sg-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_SG|43200|;self-report|us-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_US|43200|' --self-report-secret <SELF_REPORT_SECRET>
```

### Linux / OpenWrt PO0 Outbound IP Report client

访问设备定时自上报。交互式无参数运行默认进入菜单；菜单里的 `1) 配置并保存上报参数` 只写本地配置文件，不安装 cron，也不保证安装 `po0-outbound-ip-report` 命令；`2) 立即上报一次` 会读取参数或已保存配置；`3) 安装 / 更新定时上报` 会保存配置、安装本机脚本并写入 cron；`4) 暂停 / 恢复定时上报` 只影响自动 cron，手动立即上报仍可用；`8) 从 GitHub 更新脚本` 会更新本机 `po0-outbound-ip-report` 命令并重新打开新版菜单；`9) 卸载本客户端` 会删除本脚本管理的 cron 和本机安装脚本，配置文件与 `/tmp/po0-outbound-ip-report.log` 默认保留，可选择一起删除。

OpenWrt 多 WAN 可以重复传入 `--wan <逻辑接口>` 选择一条或多条出口，例如 `--wan wan1 --wan wan2`；`--wan all` 会枚举全部已启用的 mwan3 WAN。客户端从 ubus 读取每条逻辑 WAN 的 `l3_device`，绑定该设备查询公网 IPv4，再分别调用 LAN Worker。每条 WAN 的来源 ID 会自动追加接口名，例如基础来源 `router-88-1` 会生成 `router-88-1-wan1` 和 `router-88-1-wan2`，确保两条记录独立续期。某一条 WAN 失败时其它 WAN 仍继续上报，整轮最终返回非零并显示成功/失败数量。留空或使用 `--clear-wans` 时保持旧行为，只按默认路由探测和上报一个出口。

对于“上游 OpenWrt 负责双 WAN、下游网关负责上报”的拓扑，完整客户端留在下游网关，并配置 `--router-probe-url http://<上游路由器>/cgi-bin/po0-wan-probe --wan all`。上游只安装独立 `po0-wan-probe.sh` 或 `po0-wan-probe.apk`：它按 UCI 来源 IP/WAN 白名单读取已启用的 mwan3 接口，优先返回接口自身公网 IPv4，必要时才绑定该 WAN 调用外部检测；`wan=all` 一次返回所有 WAN 的 JSON。探针不连接 LAN Worker、不持有上报 secret，也不运行调度器。下游可安装 `po0-outbound-ip-report.apk`，通过 LuCI 配置 Worker、探针和 WAN 选择，并由 procd 定时运行。两类 HTTP 请求都遵循设备现有网络配置，脚本不管理 Mihomo/OpenClash。

首次进入菜单：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report.sh | bash
```

首次保存默认配置并打开菜单，不需要先在命令行写域名和 secret；进菜单后用 `1) 配置并保存上报参数` 填写或修改。未传 `--source-id` / `--identity` 时，客户端会用 hostname + machine-id/MAC 生成默认 Source ID，并用设备名作为 Identity；需要固定自定义 ID 时再显式添加 `--source-id <CLIENT_ID>`：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report.sh | bash -s -- --save-config --menu
```

非交互保存配置，不安装 cron：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report.sh | bash -s -- --worker-url https://<SELF_REPORT_DOMAIN>/report --secret <SELF_REPORT_SECRET> --save-config
```

非交互立即上报一次；如果没有传 `--worker-url` 等参数，会读取已保存配置：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report.sh | bash -s -- --worker-url https://<SELF_REPORT_DOMAIN>/report --secret <SELF_REPORT_SECRET>
```

非交互安装 / 更新 cron，默认和示例推荐每 `3600` 秒上报一次；`--interval-seconds N` 是标准参数，旧 `--install-cron N` 的分钟写法仍兼容。安装时会保存配置并安装本机 `po0-outbound-ip-report` 命令；cron 后续只引用配置文件，不再把 token 展开写入 cron 命令行：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report.sh | bash -s -- --worker-url https://<SELF_REPORT_DOMAIN>/report --secret <SELF_REPORT_SECRET> --interval-seconds 3600 --install-cron
```

保存配置后，如果本机已经通过菜单更新或安装 cron 落盘了 `po0-outbound-ip-report` 命令，可直接复用已保存配置：

```bash
po0-outbound-ip-report --menu
```

```bash
po0-outbound-ip-report
```

```bash
po0-outbound-ip-report --install-cron
```

查看本脚本管理的 cron 计划：

```bash
crontab -l | sed -n '/# OUTBOUND_IP_REPORT_BEGIN/,/# OUTBOUND_IP_REPORT_END/p'
```

也可以用脚本内置状态入口：

```bash
po0-outbound-ip-report --schedule-status
```

状态入口会显示本脚本管理的计划状态、原始日志路径和最近结果摘要；完整原始日志仍用下面的 `tail` 命令查看。

暂停或恢复本脚本管理的定时上报；暂停只影响自动 cron，不影响手动立即上报：

```bash
po0-outbound-ip-report --pause-schedule
```

```bash
po0-outbound-ip-report --resume-schedule
```

查看最近 PO0 Outbound IP Report 日志：

```bash
tail -n 40 /tmp/po0-outbound-ip-report.log
```

更新、查看版本或查看当前更新内容：

```bash
po0-outbound-ip-report --upgrade-self
```

```bash
po0-outbound-ip-report --version
```

```bash
po0-outbound-ip-report --changelog
```

### macOS PO0 Outbound IP Report client

macOS 使用专用 Bash 脚本和用户级 launchd LaunchAgent，不复用 Linux/OpenWrt cron 脚本。`3) 安装 / 更新定时上报` 会保存配置、安装本机脚本，并写入 `~/Library/LaunchAgents/outbound-ip-report.plist`；`6) 通知 / 静默模式` 可切换自动上报完成 / 失败后的 macOS 通知。

菜单 `9) Wi-Fi SSID 权限诊断` 会显示当前 SSID 读取状态，并可创建 / 打开 `PO0 Location Permission Helper.app` 触发 macOS 定位权限请求；菜单 `11) 删除定位权限 Helper` 只删除本地 Helper app，不修改 macOS 定位授权记录。`12) 卸载本客户端` 会删除本脚本管理的定时上报、本机安装脚本和 Helper app。

macOS 系统自带 Bash 通常是 3.2，客户端会保持 Bash 3.2 兼容，不要求额外安装新版 Bash。`2026.07.01+build.6` 修复过 SSID 跳过列表在 Bash 3.2 + `set -u` 下可能出现的 `items[@]: unbound variable`；如果看到这类报错，先从 GitHub Release 更新到 build.6 或更新版本。

检查 macOS 客户端当前能读取到的 Wi-Fi SSID：

```bash
po0-outbound-ip-report --show-wifi-ssid
```

如果结果显示“读取失败或被 macOS 隐私权限隐藏（fail-open）”，说明底层网络命令可能返回了 `redacted` / `<redacted>` 隐私占位符，当前运行环境或 PO0 Helper 没有拿到系统允许的定位相关信息访问权；客户端会按 fail-open 继续正常上报，不会把占位符当成真实 SSID。查看授权说明：

```bash
po0-outbound-ip-report --diagnose-wifi-ssid
```

如果 Terminal/iTerm 不在定位服务列表里，运行一次授权请求。脚本会生成带稳定 bundle id、定位用途声明和可选 ad-hoc 签名的 `PO0 Location Permission Helper.app`，并用 `open` 打开它；macOS 弹窗出现时请选择允许 Helper 访问位置：

```bash
po0-outbound-ip-report --request-location-permission
```

只删除本地 Helper app：

```bash
po0-outbound-ip-report --delete-location-permission-helper
```

诊断输出也会打印可直接执行的定位服务设置入口；需要时可以让脚本打开设置页：

```bash
po0-outbound-ip-report --open-location-services
```

授权后 Helper 会在本机通过 CoreWLAN 读取当前 Wi-Fi SSID，作为 `--show-wifi-ssid` 和 SSID 跳过 guard 的 fallback。脚本不会写 TCC 数据库，也不会用 `sudo` / `tccutil` 伪造授权；如果 Helper 被拒绝、未出现弹窗或无法读取 SSID，客户端只会继续 fail-open 上报。删除 Helper 只移除本地 app 文件；如需撤销系统定位授权，请到 系统设置 > 隐私与安全性 > 定位服务 中处理。

首次保存默认配置并打开菜单：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report-macos.sh | bash -s -- --save-config --menu
```

非交互保存配置：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report-macos.sh | bash -s -- --worker-url https://<SELF_REPORT_DOMAIN>/report --secret <SELF_REPORT_SECRET> --save-config
```

非交互安装 / 更新 launchd 定时上报：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report-macos.sh | bash -s -- --worker-url https://<SELF_REPORT_DOMAIN>/report --secret <SELF_REPORT_SECRET> --interval-seconds 3600 --install-launchd
```

默认静默安装，不弹通知，只写 `/tmp/po0-outbound-ip-report.log`。如需自动上报成功或失败后弹 macOS 通知，安装或保存配置时加 `--notify`：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report-macos.sh | bash -s -- --worker-url https://<SELF_REPORT_DOMAIN>/report --secret <SELF_REPORT_SECRET> --interval-seconds 3600 --notify --install-launchd
```

恢复静默：

```bash
po0-outbound-ip-report --no-notify --install-launchd
```

安装后复用本机命令：

普通用户默认安装到 `~/.local/bin/po0-outbound-ip-report`。如果安装后当前终端的 `PATH` 不包含 `~/.local/bin`，菜单里的“安装 / 更新定时上报”和“从 GitHub 更新脚本”会询问是否写入 `~/.zprofile`；非交互安装只打印提示和可直接运行的完整路径，不自动修改 shell 配置。root 安装默认路径为 `/usr/local/sbin/po0-outbound-ip-report`，脚本只提示，不自动改全局 PATH。

```bash
po0-outbound-ip-report --menu
```

```bash
po0-outbound-ip-report --install-launchd
```

```bash
po0-outbound-ip-report --schedule-status
```

状态入口会显示 launchd / cron 计划状态、通知模式、原始日志路径和最近结果摘要；完整原始日志仍用 `tail -n 40 /tmp/po0-outbound-ip-report.log` 查看。macOS 通知依赖当前用户图形会话、系统通知权限和专注模式；通知不可用时只写日志，不影响上报结果。

查看 launchd 状态：

```bash
launchctl print gui/$(id -u)/outbound-ip-report
```

更新、查看版本或查看当前更新内容：

```bash
po0-outbound-ip-report --upgrade-self
```

```bash
po0-outbound-ip-report --version
```

```bash
po0-outbound-ip-report --changelog
```

### Windows PowerShell PO0 Outbound IP Report client

Windows 默认按普通用户安装和运行，路径在 `%LOCALAPPDATA%\PO0\po0-outbound-ip-report.ps1`。只有用管理员 PowerShell 安装时才会改用 `%ProgramData%\PO0\po0-outbound-ip-report.ps1`；管理员路径可以作为兜底检查，但日常不要混用两个权限环境。

旧版曾把 Windows 本机脚本写到 `po0-self-report.ps1`。新版从旧路径启动时会迁移到 `po0-outbound-ip-report.ps1` 并刷新计划任务；更新或自愈完成后会把默认旧配置、旧日志、旧 IP 探测状态、旧计划任务启动文件和旧计划任务迁到新命名并删除旧默认残留。旧路径只作为兼容迁移和卸载目标，不再作为新安装入口。

交互式运行默认进入菜单，推荐显式加 `-Menu`。菜单里的 `1) 配置并保存上报参数` 只写本地配置文件，不安装计划任务；`2) 立即上报一次` 会读取参数或已保存配置；`3) 安装 / 更新定时上报` 会保存配置、安装本机脚本并写入计划任务；`4) 暂停 / 恢复定时上报` 只影响自动计划任务，手动立即上报仍可用；`6) Windows 通知 / 静默模式` 会保存通知偏好，并在计划任务已安装时同步计划任务启动文件；`9) 从 GitHub 更新脚本` 会更新本机 `po0-outbound-ip-report.ps1` 并重新打开新版菜单；`10) 卸载本客户端` 会删除本脚本管理的计划任务、计划任务启动文件和本机安装脚本，配置文件与日志默认保留，可选择一起删除。

首次运行时先下载到临时文件，再打开菜单：

```powershell
$script = "$env:TEMP\po0-outbound-ip-report.ps1"
Invoke-WebRequest -UseBasicParsing 'https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report.ps1' -OutFile $script -TimeoutSec 120
powershell -ExecutionPolicy Bypass -File $script -Menu
```

非交互保存配置，不安装计划任务；`-SourceId` 是 PO0 端分组、续期和裁剪用的稳定 key，`-Identity` 只做备注和审计。多台设备不要共用同一个 `SourceId`：

```powershell
$script = "$env:TEMP\po0-outbound-ip-report.ps1"
Invoke-WebRequest -UseBasicParsing 'https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report.ps1' -OutFile $script -TimeoutSec 120
powershell -ExecutionPolicy Bypass -File $script -WorkerUrl "https://<SELF_REPORT_DOMAIN>/report" -SourceId $env:COMPUTERNAME -Identity $env:COMPUTERNAME -Secret "<SELF_REPORT_SECRET>" -SaveConfig
```

非交互立即上报一次；如果没有传 `-WorkerUrl` 等参数，会读取已保存配置。显式 `-RunOnce` 可避免交互环境下误进菜单：

```powershell
$script = "$env:TEMP\po0-outbound-ip-report.ps1"
Invoke-WebRequest -UseBasicParsing 'https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report.ps1' -OutFile $script -TimeoutSec 120
powershell -ExecutionPolicy Bypass -File $script -WorkerUrl "https://<SELF_REPORT_DOMAIN>/report" -SourceId $env:COMPUTERNAME -Identity $env:COMPUTERNAME -Secret "<SELF_REPORT_SECRET>" -RunOnce
```

非交互安装 / 更新计划任务，默认每 `3600` 秒上报一次。安装 / 更新计划任务时建议从 `$env:TEMP` 下载脚本再运行，让脚本覆盖安装到普通用户默认路径 `%LOCALAPPDATA%\PO0\po0-outbound-ip-report.ps1`。管理员 PowerShell 安装时会改用 `%ProgramData%\PO0\po0-outbound-ip-report.ps1`。安装时会保存配置；计划任务后续只引用配置文件，不再把 token 展开写入计划任务参数。计划任务通过启动文件调用 PowerShell，不弹出 CMD/PowerShell 窗口；默认静默只写日志，不弹 Windows 通知。如需自动上报成功或失败后弹 Windows 通知，安装计划任务时额外加 `-Notify`，或在菜单“Windows 通知 / 静默模式”里启用通知：

```powershell
$script = "$env:TEMP\po0-outbound-ip-report.ps1"
Invoke-WebRequest -UseBasicParsing 'https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report.ps1' -OutFile $script -TimeoutSec 120
powershell -ExecutionPolicy Bypass -File $script -WorkerUrl "https://<SELF_REPORT_DOMAIN>/report" -SourceId $env:COMPUTERNAME -Identity $env:COMPUTERNAME -Secret "<SELF_REPORT_SECRET>" -InstallTask -IntervalSeconds 3600
```

显式恢复静默并刷新已安装计划任务：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\PO0\po0-outbound-ip-report.ps1" -NoNotify -InstallTask -IntervalSeconds 3600
```

`<SELF_REPORT_SECRET>` 只替换为 secret 本身，例如 `daf80...ce94`；不要写成 `secret:daf80...` 或 `secret：daf80...`。

保存配置后，如果本机已经通过菜单更新或安装计划任务落盘了脚本，普通用户从固定路径再次运行。

打开交互菜单：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\PO0\po0-outbound-ip-report.ps1" -Menu
```

立即按已保存配置上报一次：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\PO0\po0-outbound-ip-report.ps1" -RunOnce
```

保存配置并安装 / 更新计划任务：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\PO0\po0-outbound-ip-report.ps1" -InstallTask -IntervalSeconds 3600
```

管理员安装时才把 `$env:LOCALAPPDATA` 改为 `$env:ProgramData`。

查看计划任务状态和最近日志摘要；状态页会同时显示配置里的通知偏好、已安装计划任务实际是否带 `-Notify`、实际 `-File` 脚本目标，不一致时提示通知状态或旧路径漂移：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\PO0\po0-outbound-ip-report.ps1" -ScheduleStatus
```

也可以直接看 Windows 计划任务：

```powershell
Get-ScheduledTaskInfo -TaskName "Outbound IP Report"
```

暂停或恢复本脚本管理的定时上报；暂停只影响自动计划任务，不影响手动立即上报：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\PO0\po0-outbound-ip-report.ps1" -PauseSchedule
```

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\PO0\po0-outbound-ip-report.ps1" -ResumeSchedule
```

查看最近日志：

```powershell
$log = "$env:LOCALAPPDATA\PO0\po0-outbound-ip-report.log"
if (-not (Test-Path -LiteralPath $log)) {
    $log = "$env:ProgramData\PO0\po0-outbound-ip-report.log"
}
Get-Content -Tail 40 -LiteralPath $log
```

从 GitHub Release 发布文件更新本机脚本：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\PO0\po0-outbound-ip-report.ps1" -UpgradeSelf
```

查看当前脚本版本：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\PO0\po0-outbound-ip-report.ps1" -Version
```

查看当前版本更新内容：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\PO0\po0-outbound-ip-report.ps1" -Changelog
```

### PO0 Outbound IP Report client 共同说明

三个客户端默认拒绝 `http://`；只有本地调试或临时旧环境才显式使用 `--allow-http` / `-AllowHttp`。Linux/OpenWrt/macOS 默认配置文件 root 为 `/etc/po0-outbound-ip-report/settings.env`，普通用户为 `~/.config/po0-outbound-ip-report/settings.env`；Windows 默认配置文件普通用户为 `%LOCALAPPDATA%\PO0\outbound-ip-report.json`，管理员为 `%ProgramData%\PO0\outbound-ip-report.json`。优先级为 CLI > `PO0_OUTBOUND_IP_REPORT_*` > legacy `PO0_SELF_REPORT_*` / `SELF_REPORT_*` > 已保存配置 > 默认值；旧 `po0-self-report` 配置只作 fallback，保存时写入新路径。配置文件会明文保存 self-report secret，请只放在可信设备上。

三个客户端支持按当前 Wi-Fi SSID 在本地跳过上报。Linux/OpenWrt 和 macOS 使用 `--skip-wifi-ssid SSID`（可重复）、`--skip-wifi-ssids "SSID1;SSID2"`、`--clear-skip-wifi-ssids` 和 `--force-report`，也可用 `PO0_OUTBOUND_IP_REPORT_SKIP_WIFI_SSIDS`；macOS 还可用 `--show-wifi-ssid` 直接检查当前读取结果，用 `--diagnose-wifi-ssid` 查看 macOS 定位服务 / 隐私权限诊断，用 `--request-location-permission` 创建并打开 `PO0 Location Permission Helper.app` 触发定位权限弹窗并让 Helper 在本机读取 SSID，用 `--delete-location-permission-helper` 只删除本地 Helper app，或用 `--open-location-services` 打开定位服务设置页。Windows 使用 `-SkipWifiSsids "SSID1;SSID2"`、`-ForceReport` 和同名环境变量；保存配置后会写入本机配置文件。SSID 列表用英文分号 `;` 分隔，匹配时只做去首尾空白后的精确匹配，不做通配、正则或子串匹配。命中时客户端只在本机日志 / 状态摘要里记录“因 SSID 跳过”，不会把 SSID、跳过原因或任何新字段上传到 LAN Worker，也不改变 LAN Worker `/report` 或 PO0 上报协议。读取当前 SSID 失败时按安全兼容原则继续正常上报。macOS 底层命令返回 `redacted` / `<redacted>` 时会按“读取失败或被 macOS 隐私权限隐藏（fail-open）”显示并提示用户授权 PO0 Helper；脚本不会自动获取或修改系统权限，不会使用 `sudo`、`tccutil` 或写入 TCC 数据库。手动运行命中跳过规则时会先询问是否强制继续；定时任务命中时直接本地跳过并写日志。

更新脚本、从旧 `po0-self-report*` 路径自愈启动，或安装 / 更新定时上报时，客户端会清理脚本自己能确定的默认旧名残留：Linux/OpenWrt/macOS 会迁移默认旧配置、旧 `/tmp/po0-self-report.log`、旧 IP 探测 state，并移除默认旧命令；macOS 还会迁移 legacy launchd / cron；Windows 会迁移默认旧 `self-report.json`、旧日志、旧 state、旧计划任务、旧 `po0-self-report.ps1` 和旧计划任务启动文件。显式传入的自定义 `--config` / `-ConfigPath`、`--install-path`、`-LogPath` 等路径不会被当成默认残留误删。

访问设备客户端的一次性上报会以明确状态行结束：成功时显示 `PO0 Outbound IP Report 已完成：...`，并保留 LAN Worker 返回的 `OK <ip>; targets=<N>; target_names=<目标列表>`；客户端摘要优先显示具体 PO0 目标名，连接旧 LAN Worker 时退回显示 `PO0 目标：N 个`。URL 校验、公网 IPv4 探测、HTTP 请求或 LAN Worker -> PO0 上报链路失败时显示 `PO0 Outbound IP Report 未完成：...` 并以非零状态退出。Linux/OpenWrt 和 macOS 定时任务每次运行的完整输出写到 `/tmp/po0-outbound-ip-report.log`；macOS 默认不弹通知，显式启用通知后会调用系统通知中心，通知失败仍只写日志。Windows 计划任务不会弹出可见 CMD/PowerShell 窗口；安装 / 更新计划任务时会生成计划任务启动文件，并把每次运行的开始、LAN Worker 返回和完成/未完成结果写到日志，管理员安装默认在 `%ProgramData%\PO0\po0-outbound-ip-report.log`，普通用户安装默认在 `%LOCALAPPDATA%\PO0\po0-outbound-ip-report.log`；自动上报默认不弹 Windows 通知，只写日志。显式启用通知时，自动上报完成或失败会弹 Windows 通知，通知不可用时仍以日志为准；菜单里的“查看定时上报状态”只显示最近结果摘要，会从 LAN Worker 返回体汇总 PO0 目标，并给出原始日志路径 / tail 命令用于排查细节，同时会提示配置通知状态和计划任务实际通知状态是否漂移。

PO0 Outbound IP Report client 查询公网 IPv4 会按默认列表轮询：`https://ip9.com.cn/get`、163 邮箱、Bilibili、126、腾讯新闻、爱奇艺、央视、`https://myip.ipip.net/json`。脚本会记住上次使用位置，下次从下一个接口开始；默认不再使用 `ip-api`、`ipify`、`icanhazip`、`ifconfig.co`，也不再使用 12306 grip 接口。

## Egern 当前出口 IP 上报

Egern 模块不是 DDNS 模块。它的逻辑是：

1. 用 `DIRECT` 轮询 IP 查询接口获取手机当前出口 IPv4，默认列表从 `https://ip9.com.cn/get` 开始，后续是国内接口和 `myip.ipip.net`；状态页会优先复用这些接口返回的归属地 / 运营商信息，只有拿不到时才退回额外查询。
2. 通过一次性 SSH 调 PO0：

```bash
bash /root/nftables-relay-manager.sh --ssh-ip-report <source-id> <ipv4> <token> [identity] [ttl] [cidr-prefix]
```

Egern 放行 TTL 默认 `43200` 秒（12 小时）。单 PO0 可在模块环境变量 `TTL_SECONDS` 覆盖；多个 PO0 可在 `SSH_REPORT_TARGETS` 每行最后一列分别覆盖。实际 SSH 自动上报周期由 `AUTO_REPORT_INTERVAL_SECONDS` 控制，默认 `3600` 秒，可设置 `600` 到 `86400` 秒；建议让 TTL 至少大于自动上报周期并留出余量。模块 schedule 每 10 分钟轻量检查一次；如果 TTL 小于自动上报周期，脚本会提前续期，尽量避免过期空窗。Egern 蜂窝网络默认按 `CELLULAR_CIDR_PREFIX=24` 上报 `/24`，同一 `/24` 内 IP 跳动时自动触发会跳过 SSH；Wi-Fi 和未知网络固定 `/32`，出口 IP 变化就会重新上报。把 `CELLULAR_CIDR_PREFIX` 设为 `32` 可关闭蜂窝 `/24`。可选 `SKIP_WIFI_SSIDS` 只对定时/网络变化自动触发生效；当前 Wi-Fi SSID 精确命中分号分隔列表时，本机跳过本次公网 IP 探测和 SSH 上报，只写 Egern 本地状态/日志，不上传 SSID，也不改 PO0 或 LAN Worker 协议。读取不到 SSID 时继续上报；手动运行、状态页和 Widget 刷新会强制继续上报。

只读检查：

```bash
bash /root/nftables-relay-manager.sh --ssh-ip-report-check <source-id> <token>
```

如果使用 PO0 专用受限 SSH 上报 key，Egern 专用 key 的 scope 应为 `egern`。wrapper 拒绝时，PO0 会记录不含 token 的摘要：

```bash
bash /root/nftables-relay-manager.sh --refresh-report-key-wrapper
bash /root/nftables-relay-manager.sh --show-report-key-denials 80
```

模块提供：

- `schedule`：每 10 分钟轻量检查一次；实际 SSH 自动上报周期由 `AUTO_REPORT_INTERVAL_SECONDS` 控制，默认 `3600` 秒。
- `network`：网络变化时上报。
- `generic`：手动立即上报。
- `widget`：查看最近成功 IP、时间、TTL、失败原因、网络类型、PO0 host。

Egern 可以向多个 PO0 上报同一个当前出口 IPv4。模块环境变量 `SSH_REPORT_TARGETS` 可以一行一个目标，也可以用逗号或分号分隔多个目标：

```text
source-id|host|port|user|script|token|identity|ttl
```

示例：

```text
iphone-sg|sg-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_SG|egern-iphone|43200
iphone-us|us-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_US|egern-iphone|43200
```

如果 Egern 输入框会把换行折叠成空格，建议直接用逗号连接多个目标。

不填 `SSH_REPORT_TARGETS` 时，模块按单目标 `PO0_HOST`、`SSH_REPORT_SOURCE`、`SSH_REPORT_TOKEN` 运行；目标行第一列 `source-id` 会映射到 `SSH_REPORT_SOURCE`。旧 Egern Client IP 模块不再保留兼容；`scripts/po0/relay/egern/` 仅保留旧 raw URL 兼容路径，新安装使用 `scripts/po0/nftables/clients/egern/`。

不要为两个 PO0 重复导入两份 Egern 模块。正确做法是只导入一份模块，把两个 PO0 生成的目标行合并到同一个 `SSH_REPORT_TARGETS`，这样只查一次当前出口 IPv4，Widget 也能显示同一轮上报里每个 PO0 的成功/失败。

## LAN Worker WebAuth

WebAuth 只运行在 LAN Worker 上，PO0 不开放 HTTP。推荐结构：

```text
Browser -> Cloudflare Access -> cloudflared tunnel -> LAN Worker 127.0.0.1:8787 -> SSH -> PO0
```

Self-report 和 WebAuth 的区别：

```text
Self-report：访问设备主动把自己的出口 IP 报给 LAN Worker。
WebAuth：用户打开 Cloudflare Access 保护的网页，登录后 LAN Worker 根据 Cloudflare 请求头放行这个访问 IP。
```

LAN Worker 启动 WebAuth 本地服务：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-lan-client.sh | bash -s -- --install-self
po0-lan-client --webauth-server --listen 127.0.0.1:8787 --po0-host <PO0_HOST> --po0-script /root/nftables-relay-manager.sh --webauth-source cf-access --webauth-token <WEBAUTH_TOKEN>
```

多个 PO0 同样使用“WebAuth 放行目标”：

```bash
po0-lan-client --webauth-server --listen 127.0.0.1:8787 --webauth-targets 'cf-access|sg-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_SG|43200|;cf-access|us-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_US|43200|'
```

多目标 WebAuth 与 Self-report 一样并发上报 PO0；返回成功代表所有目标已更新，502 代表至少一个目标失败。

PO0 接收的仍是 SSH 命令：

```bash
bash /root/nftables-relay-manager.sh --webauth-report <source-id> <ipv4> <identity> <expires-at> <token> [note]
```

Cloudflare Tunnel ingress 示例，运行在 LAN Worker：

```yaml
ingress:
  - hostname: auth.example.com
    service: http://127.0.0.1:8787
  - service: http_status:404
```

Cloudflare 控制台动作：

1. 创建 Cloudflare Tunnel，并让 `cloudflared` 运行在 LAN Worker。
2. Public hostname 绑定 `auth.example.com`，service 指向 `http://127.0.0.1:8787`。
3. Access -> Applications -> Add application -> Self-hosted。
4. 应用域名填写同一个 `auth.example.com`。
5. 配置允许登录的邮箱、域名或 Access group。
6. 确认该 hostname 受 Access 保护。

本地检查命令：

```bash
cloudflared tunnel ingress validate
cloudflared tunnel ingress rule https://auth.example.com
```

LAN Worker 会优先读取 `CF-Connecting-IP` 作为访问 IP，读取 `Cf-Access-Authenticated-User-Email` 或 `CF-Access-Authenticated-User-Email` 作为身份。浏览器页面会返回成功、部分成功或失败，以及已上报到哪些 PO0。

## attack mode

`attack mode` 用于白名单被异常访问冲击时冻结自动新增：

```bash
bash /root/nftables-relay-manager.sh --automation-mode attack
bash /root/nftables-relay-manager.sh --pending-auto-sources
```

效果：

- 新的 DDNS / Client IP / SSH report / WebAuth 自动 IP 进入待审核列表，不直接放行。
- 已有有效 IP 如果仍被同一来源上报，可以续期。
- 手动白名单和 SSH 临时白名单继续按菜单操作生效。

恢复常规模式：

```bash
bash /root/nftables-relay-manager.sh --automation-mode regular
```

## IP 数据源

当前有两类 IP 数据：

- 地区白名单 CIDR：来自 `metowolf/iplist` 的 `docs/cncity.md` 和 `data/cncity/*.txt`，用于 nftables 实际放行地区网段。
- IPDB 归属查询：默认下载 `nmgliangwei/qqwry.ipdb`，用于学习记录、阻挡记录、Client IP/WebAuth/DDNS 记录的当时归属快照。

iplist 离线包可在本地构建，再到 PO0 主控菜单 `来源、客户端与资源 -> 11) 源 IP 白名单 -> 19) 导入 / 刷新 iplist 离线包` 导入。

Bash 版：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/tools/build-iplist-package.sh | bash -s -- "${HOME}/Desktop/iplist.tar.gz" 16
```

PowerShell 版：

```powershell
$script = irm -UseBasicParsing 'https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/tools/build-iplist-package.ps1'
& ([scriptblock]::Create($script)) -OutFile "$env:USERPROFILE\Desktop\iplist.tar.gz" -ThrottleLimit 16
```

学习/阻挡/动态来源记录写入时会保存当时 IPDB 快照；旧记录没有快照时会按 legacy/no snapshot 处理，不会重写历史归属。

## 兼容与清理

只读兼容检查：

```bash
bash /root/nftables-relay-manager.sh --compat-check
```

旧文件清理 dry-run：

```bash
bash /root/nftables-relay-manager.sh --cleanup-legacy --dry-run
```

应用清理：

```bash
bash /root/nftables-relay-manager.sh --cleanup-legacy --apply
```

清理会先备份，不删除规则、白名单、token、任务状态等 live state。
