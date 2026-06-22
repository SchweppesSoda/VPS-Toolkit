# PO0 nftables Relay / LAN Worker

这里是 PO0 nftables 中转管理器、LAN Worker、Egern 当前出口 IP 上报和 self-report client 的文档。

完整版本历史维护在 [`CHANGELOG.md`](./CHANGELOG.md)。各独立部署脚本的 `--changelog` 或更新完成提示只显示当前版本更新内容，避免远端单文件脚本长期累积历史。

核心边界：

- PO0 不开放 HTTP / WebAuth / Secret URL。
- PO0 不做本地 DDNS 解析；`--refresh-ddns` 只按外部已上报且仍在 TTL 内的 DDNS 结果重建/应用，不延长原上报 TTL。
- LAN Worker 负责 DDNS 解析上报、`iplist/ipdb` 资源任务、WebAuth Client、Self-report 接收端。
- LAN Worker 可选提供 PO0 manager HTTP 更新镜像；只代理固定 manager 脚本，PO0 用 resource token HMAC 校验后才替换本机脚本。
- Egern 负责移动设备当前出口 IPv4 上报，不再解析 DDNS。
- 资源任务只允许 `iplist`、`ipdb`，不支持任意远程 shell。

## 阅读路线

如果只是部署或日常维护，先看本文件，不需要先读 `nftables-relay-manager-technical.md`。技术文档只给维护实现、wrapper、协议和内部状态模型时使用。

| 你要做什么 | 看这里 |
| --- | --- |
| 首次部署 PO0 主控或 LAN Worker | “部署命令” |
| 找 PO0 主菜单功能分组、导出/导入、版本和 token bundle | “PO0 主控菜单”、“完整备份与导入恢复” |
| 管理源 IP 白名单、DDNS、动态来源、attack mode | “源 IP 白名单模式”、“DDNS Resolver 上报”、“attack mode” |
| 让内网机器领取 iplist/ipdb 资源任务 | “LAN Worker 资源任务” |
| 让 PO0 从 LAN Worker 一键拉取更新 manager | “PO0 manager HTTP 更新镜像” |
| 让访问设备自上报当前出口 IPv4 | “LAN Worker Self-report” |
| 配置 Egern 当前出口 IPv4 SSH 上报 | “Egern 当前出口 IP 上报”，以及 [`clients/egern/README.md`](./clients/egern/README.md) |
| 配置 Cloudflare Access / WebAuth 放行 | “LAN Worker WebAuth” |
| 构建或导入离线 IP 数据 | “IP 数据源” |
| 清理旧文件或检查兼容性 | “兼容与清理” |

## 部署命令

PO0 主控脚本不依赖 HTTPS 拉取。先从本地仓库上传到 PO0，再运行：

```bash
scp scripts/po0/nftables/nftables-relay-manager.sh root@<PO0_HOST>:/root/nftables-relay-manager.sh
ssh root@<PO0_HOST> 'chmod +x /root/nftables-relay-manager.sh && bash /root/nftables-relay-manager.sh'
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

LAN Worker 命令在内网 Worker 机器上执行，不在 PO0 上执行。DDNS 解析上报 + 资源任务轮询领取：

推荐先用交互向导。向导会检查到 PO0 的密钥 SSH；密钥 SSH 可用时，会自动调用 PO0 主控读取所需 token，然后写入本机配置、安装本机 `po0-lan-client` 命令，并按选择安装本机 Worker 轮询器 / systemd 服务。首次向导里的 PO0 SSH 地址一次只填一个；多个 PO0 目标后续进入菜单添加：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/lan-worker/po0-lan-client.sh | bash
```

SSH 认证按向导选择：系统默认 SSH 配置/agent、已有私钥路径，或粘贴专用私钥。粘贴的私钥会保存到本机配置目录并设置 600 权限。`额外 SSH 参数` 是传给 `ssh` 的选项，例如 `-J jump-host` 或 `-o StrictHostKeyChecking=accept-new`，不是私钥短语；带短语的私钥需要 `ssh-agent`。菜单里的 `DDNS 解析上报 -> DDNS 目标 / 上报计划` 管理 DDNS 目标和本机上报间隔；`PO0 目标`、`SSH 私钥 / 参数`、`目标 Token`、`Self-report TTL / WebAuth TTL` 分开管理目标、SSH、Token 和自上报/WebAuth TTL；`资源统计 / PO0 创建计划` 只读显示 PO0 端资源任务创建 cron，Worker 本机只安装轮询器领取 pending 任务。

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

PO0 主控和 LAN Worker 脚本统一使用 `YYYY.MM.DD+build.N` 混合版本格式；同一天再次发布时递增 `build.N`，例如 `2026.06.18+build.2`。

更新 LAN Worker 上已安装的 client：

```bash
po0-lan-client --upgrade-self
po0-lan-client --version
```

## PO0 manager HTTP 更新镜像

这个功能用于“日常只登录 PO0，也能从 LAN Worker 拉取新版 manager”。先在 LAN Worker 上配置一次 HTTP-only 更新镜像；LAN Worker 到 GitHub raw 使用 HTTPS，PO0 到 LAN Worker 按显式 HTTP URL 拉取。该入口只服务固定路径 `/po0-manager-update/nftables-relay-manager.sh`，不是任意 URL 代理，也不是 PO0 HTTP 控制面。

LAN Worker 上配置镜像公网主机/IP。未写端口时默认使用 `2333`，也可以显式传入 `HOST:PORT`；Caddy 入口按端口监听，同一端口既可用域名访问，也可直接用 IP 访问：

```bash
po0-lan-client --install-manager-update-http --manager-update-domain <LAN_WORKER_IP>
```

PO0 上拉取更新：

```bash
bash /root/nftables-relay-manager.sh --upgrade-manager-from-lan http://<LAN_WORKER_IP>:2333/po0-manager-update/nftables-relay-manager.sh
```

也可以在 PO0 主菜单进入 `脚本版本 / 更新 -> 从 LAN Worker HTTP 更新 manager`，第一次输入 URL 后会保存到 PO0 设置文件；如果入口不是 HTTP 默认 80 端口，必须在 URL 中写明 `:PORT`，例如 `:2333`。更新时 PO0 会读取本机 resource token，向 LAN Worker 发送随机 nonce 和 `token_id`，下载后校验 HMAC、SHA-256、size、脚本标识、changelog 和 `bash -n`；通过后备份旧脚本并原子替换。更新成功后会询问是否刷新受限 SSH wrapper，不会自动应用 nftables，也不会自动运行诊断。

也可以显式进入向导：

```bash
po0-lan-client --wizard
```

如果旧版本安装后没有 `po0-lan-client` 命令，可手动补装：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/lan-worker/po0-lan-client.sh -o /usr/local/sbin/po0-lan-client
chmod 755 /usr/local/sbin/po0-lan-client
/usr/local/sbin/po0-lan-client --menu
```

如果要用于自动化，仍可直接传参数：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/lan-worker/po0-lan-client.sh | bash -s -- --bootstrap --po0-host <PO0_HOST> --po0-script /root/nftables-relay-manager.sh --source-key <DDNS_SOURCE_KEY> --ddns-domain <DDNS_DOMAIN> --token <DDNS_TOKEN> --resource-token <RESOURCE_TOKEN> --install-cron 5
```

LAN Worker：只做 `iplist/ipdb` 资源任务：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/lan-worker/po0-lan-client.sh | bash -s -- --bootstrap --po0-host <PO0_HOST> --po0-script /root/nftables-relay-manager.sh --resource-token <RESOURCE_TOKEN> --install-cron 1440
```

`--install-cron` 是安装 Worker 本机计划任务。DDNS resolver 上报和资源任务领取是两条不同计划：DDNS 间隔在 LAN Worker 本机设置，应小于 PO0 端 DDNS 来源 TTL；这个 TTL 在 PO0 主控的 `管理源 IP 白名单 -> 动态来源与客户端 -> 管理 DDNS 来源` 添加/编辑来源时设置。资源任务只负责发现并领取 PO0 已创建的 pending 任务，默认每 `1440` 分钟检查一次，交互菜单可设为 `1-10080` 分钟。资源任务的创建周期在 PO0 主控的 `内网资源更新任务 -> 安装 / 更新 PO0 定时创建` 中设置。

兼容旧用法时，`--install-cron N` 会把 DDNS 和资源任务两个计划都设为 `N` 分钟；不带 `N` 时，LAN Worker 默认 DDNS 每 5 分钟上报、资源任务每 1440 分钟检查一次。

Linux/OpenWrt Self-report client（交互式无参数运行默认进入菜单；菜单里的“配置并保存上报参数”会写入本地配置文件）：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/self-report/po0-outbound-ip-report.sh | bash
```

菜单里的 `8) 从 GitHub 更新脚本` 会更新本机 `po0-self-report` 命令并重新打开新版菜单。命令行也可直接更新、查看版本或查看当前更新内容：

```bash
po0-self-report --upgrade-self
```

```bash
po0-self-report --version
```

```bash
po0-self-report --changelog
```

Linux/OpenWrt Self-report client 非交互安装，默认每 60 分钟上报一次；安装时会同步保存本地配置：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/self-report/po0-outbound-ip-report.sh | bash -s -- --worker-url https://<SELF_REPORT_DOMAIN>/report --source-id <CLIENT_ID> --secret <SELF_REPORT_SECRET> --install-cron 60
```

Windows Self-report client（交互式无参数运行默认进入菜单；PowerShell 推荐先下载到临时路径再执行，也可显式加 `-Menu`；菜单里的“配置并保存上报参数”会写入本地配置文件）：

```powershell
$script="$env:TEMP\po0-outbound-ip-report.ps1"; irm -UseBasicParsing 'https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/self-report/po0-outbound-ip-report.ps1' -OutFile $script; powershell -ExecutionPolicy Bypass -File $script -Menu
```

菜单里的 `8) 从 GitHub 更新脚本` 会更新本机 `po0-self-report.ps1` 并重新打开新版菜单。命令行也可直接更新、查看版本或查看当前更新内容；普通用户默认脚本路径在 `%LOCALAPPDATA%\PO0\po0-self-report.ps1`，管理员默认脚本路径在 `%ProgramData%\PO0\po0-self-report.ps1`：

```powershell
$script="$env:TEMP\po0-outbound-ip-report.ps1"; irm -UseBasicParsing 'https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/self-report/po0-outbound-ip-report.ps1' -OutFile $script; powershell -ExecutionPolicy Bypass -File $script -UpgradeSelf
```

以后从本机固定路径打开菜单：

```powershell
$client=Join-Path $env:LOCALAPPDATA 'PO0\po0-self-report.ps1'; powershell -ExecutionPolicy Bypass -File $client -Menu
```

```powershell
$client=Join-Path $env:LOCALAPPDATA 'PO0\po0-self-report.ps1'; powershell -ExecutionPolicy Bypass -File $client -Version
```

```powershell
$client=Join-Path $env:LOCALAPPDATA 'PO0\po0-self-report.ps1'; powershell -ExecutionPolicy Bypass -File $client -Changelog
```

Windows Self-report client 非交互安装 / 更新计划任务，默认每 60 分钟上报一次；安装时会同步保存本地配置。`-SourceId` 和 `-Identity` 推荐填设备名，`-Secret` 只填纯 token，不要带 `secret:` 或中文冒号前缀：

```powershell
$script="$env:TEMP\po0-outbound-ip-report.ps1"; irm -UseBasicParsing 'https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/self-report/po0-outbound-ip-report.ps1' -OutFile $script; powershell -ExecutionPolicy Bypass -File $script -WorkerUrl "https://<SELF_REPORT_DOMAIN>/report" -SourceId $env:COMPUTERNAME -Identity $env:COMPUTERNAME -Secret "<SELF_REPORT_SECRET>" -InstallTask -Minutes 60
```

PowerShell 客户端也支持显式 `-Menu` 和 `-RunOnce`；非交互一次性上报时去掉 `-InstallTask -Minutes 60`，或显式使用 `-RunOnce`。

Egern 模块 raw URL：

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

这个命令会输出资源 Worker、DDNS resolver Worker、Self-report server/client、WebAuth Worker、Egern 模块 URL 和对应 token 示例。

LAN Worker 向导使用的机器可读 token bundle：

```bash
bash /root/nftables-relay-manager.sh --worker-token-bundle
bash /root/nftables-relay-manager.sh --worker-token-bundle --ensure-resource-token
```

`--worker-token-bundle` 输出 `KEY=value`，供 LAN Worker 通过 SSH 读取。只有带 `--ensure-resource-token` 时，才会在资源任务 token 不存在时自动生成；已有 token 不会被重置。

## 完整备份与导入恢复

PO0 manager 和 LAN Worker 都支持完整备份。默认导出是敏感全量包，会包含 Token、状态文件、资源任务、SSH 相关密钥/公钥信息和脚本快照；导出后脚本会强制尝试 `chmod 600` 备份包。

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

也可以分开恢复：`--restore-cron` 恢复 PO0 managed cron，并优先按备份里的 cron block 识别旧脚本路径后重写为当前 manager 路径；`--restore-systemd` 重新生成学习服务，`--restore-nftables` 恢复 `/etc/nftables.conf`/sysctl 并尝试应用 nftables，`--restore-report-keys` 恢复 PO0 受限 `authorized_keys` 条目。恢复受限 key 时不会照搬旧 forced command，而是用当前脚本路径和当前 wrapper 重新生成。

LAN Worker 导出：

```bash
po0-lan-client --backup-export
```

LAN Worker 导入默认只恢复目标配置、统计/事件、本机 `settings.env`、配置目录里的 `ssh-key-*` 和目标 SSH 参数引用的 `-i`/`IdentityFile` 私钥；不会默认改本机 cron、systemd service 或 Caddy：

```bash
po0-lan-client --backup-import ~/.config/po0-lan-client/backups/po0-lan-client-backup-YYYYMMDD_HHMMSS.tar.gz
```

需要恢复运行入口时显式添加 `--restore-cron`、`--restore-systemd`、`--restore-caddy`，或直接使用 `--restore-all`；恢复 cron 时会优先按备份里的 cron block 识别旧脚本路径，并把脚本路径和配置路径重写为当前 LAN Worker 路径。LAN Worker 会把 `SELF_REPORT_SECRET`、Self-report/WebAuth 监听、TTL、HTTPS/Caddy 路径、Worker ID、资源任务超时和轮询间隔持久写入配置目录下的 `settings.env`，升级脚本后会复用已有 secret 和 TTL 设置，不会因为脚本更新而重新生成 secret；如果是旧安装还没有 `settings.env`，导出前会尽量从已安装的 Self-report/WebAuth systemd unit 回填 secret、监听地址、TTL、目标和 token。

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
- `ddns`、`client_ip`、`ssh_report`、`webauth` 按 `source_type + source_value` 分组。
- `ddns`、`client_ip`、`webauth` 每个来源默认最多保留最近 5 个有效 IP；`ssh_report` / Egern 每个来源默认最多保留最近 10 个有效 IP。
- 已存在 IP 再次上报会刷新时间和过期时间，不重复新增。
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

首次部署推荐运行 `po0-lan-client --wizard`。长期维护可进入 `po0-lan-client --menu`，在 `DDNS 解析上报 -> DDNS 目标 / 上报计划` 里查看或编辑 DDNS 目标、安装/更新 DDNS 本机上报计划，并查看 PO0 DDNS TTL 设置位置；也可以分别在 `PO0 目标`、`SSH 私钥 / 参数`、`目标 Token`、`Self-report TTL / WebAuth TTL` 里查看、编辑、删除、启停 PO0 目标，并管理目标 SSH 私钥、SSH 参数、Token 和自上报/WebAuth TTL；底层仍保存到本机配置文件，旧配置继续兼容。

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

同一轮资源轮询会持续领取 pending 任务，直到 PO0 返回无任务或达到本轮上限。默认上限是 `PO0_RESOURCE_TASK_MAX_PER_RUN=10`，设为 `0` 表示不设上限。`iplist` 的 txt 数据文件默认并发下载，默认 `PO0_IPLIST_JOBS=16`，可调范围 `1-50`。资源下载后会通过 SSH stdin 上传到 PO0，上传默认超时 `PO0_RESOURCE_UPLOAD_TIMEOUT_SECONDS=900`，PO0 校验/导入默认超时 `PO0_RESOURCE_COMPLETE_TIMEOUT_SECONDS=600`。

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

## LAN Worker Self-report

Self-report 用于“访问设备自己检测当前出口 IPv4，然后报给 LAN Worker”。PO0 仍然不开放 HTTP，LAN Worker 通过 SSH 调 PO0 的 `--client-ip-report`：

```text
访问设备 self-report client -> LAN Worker HTTPS/Caddy -> 本机 self-report 后端 -> SSH -> PO0 --client-ip-report
```

LAN Worker 启动接收端推荐走菜单：

```bash
po0-lan-client --menu
```

进入 `Self-report 自上报 -> Self-report 配置 / 启动` 后，可以查看 PO0 目标、维护 `Self-report client-ip Token`、设置 source/TTL、设置监听地址、生成/修改 `Self-report secret`，并安装/更新后台服务。推荐使用“配置 HTTPS 域名 / Caddy”：输入已经解析到 LAN Worker 的域名后，脚本会配置 Caddy 自动证书和续期，并把 self-report 后端改为只监听 `127.0.0.1:8788`；访问设备上报到 `https://<SELF_REPORT_DOMAIN>/report`。请务必设置 `Self-report secret`，并用服务器防火墙或云安全组放行 TCP `80/443`，不建议公网继续放行 `8788`。菜单里的“前台启动服务”会占用当前终端，适合临时测试，按 `Ctrl+C` 退出。

同一个 Self-report 子菜单也可以查看 `po0-lan-self-report.service` 的后台服务状态、最近 journal 日志、实时日志，以及 HTTPS/Caddy 状态和最近 Caddy 日志；实时日志同样按 `Ctrl+C` 退出。

安装后台服务前至少要有一个启用的 PO0 目标，并且该目标已填写 `Self-report client-ip Token`。如果状态里看到 `--po0-host` 或 `--client-ip-token` 为空，说明旧版菜单曾写入空 service；在菜单补齐目标 Token 和 secret 后重新执行“安装 / 更新后台服务”或“配置 HTTPS 域名 / Caddy”即可覆盖。已安装过旧版 `0.0.0.0:8788` HTTP 直连 service 的机器，启用 HTTPS 后需要重新执行“配置 HTTPS 域名 / Caddy”，让 systemd unit 切换到 `127.0.0.1:8788`。

命令行启动接收端：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/lan-worker/po0-lan-client.sh | bash -s -- --install-self
po0-lan-client --install-self-report-https --self-report-https-domain <SELF_REPORT_DOMAIN> --po0-host <PO0_HOST> --po0-script /root/nftables-relay-manager.sh --self-report-source self-report --client-ip-token <CLIENT_REPORT_TOKEN> --self-report-secret <SELF_REPORT_SECRET>
```

Self-report 放行 TTL 默认 `43200` 秒（12 小时），WebAuth 放行 TTL 默认 `21600` 秒（6 小时），由 LAN Worker 上报 PO0 时传入；可以在启动接收端时加 `--self-report-ttl <秒数>` / `--webauth-ttl <秒数>`，也可以在 LAN Worker 菜单 `PO0 目标、SSH、Token 与 TTL -> Self-report TTL / WebAuth TTL` 里修改目标覆盖值。访问设备客户端只决定“多久上报一次”，不决定 TTL。Self-report / WebAuth TTL 会被限制在 `60-604800` 秒内。升级旧安装时，本机 `settings.env` 里恰好等于旧默认 `3600` 的 Self-report / WebAuth 默认 TTL 会在脚本加载时迁移到新默认；目标行里显式写的 TTL 不自动改写。

多个 PO0 用“设备自上报目标”合并到同一个 LAN Worker：

```text
source|host|port|user|script|token|ttl|ssh_args
self-report|sg-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_SG|43200|
self-report|us-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_US|43200|
```

```bash
po0-lan-client --install-self-report-https --self-report-https-domain <SELF_REPORT_DOMAIN> --self-report-targets 'self-report|sg-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_SG|43200|;self-report|us-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_US|43200|' --self-report-secret <SELF_REPORT_SECRET>
```

访问设备定时自上报；Linux/OpenWrt 交互式无参数运行默认进入菜单。菜单里的“配置并保存上报参数”只写本地配置文件，不安装 cron；“安装 / 更新定时上报”读取已保存配置并写入 cron；“暂停 / 恢复定时上报”只影响自动 cron，手动“立即上报一次”仍可用：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/self-report/po0-outbound-ip-report.sh | bash
```

Linux/OpenWrt 非交互保存配置，不安装 cron：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/self-report/po0-outbound-ip-report.sh | bash -s -- --worker-url https://<SELF_REPORT_DOMAIN>/report --source-id <CLIENT_ID> --secret <SELF_REPORT_SECRET> --save-config
```

Linux/OpenWrt 非交互立即上报一次；如果没有传 `--worker-url` 等参数，会读取已保存配置：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/self-report/po0-outbound-ip-report.sh | bash -s -- --worker-url https://<SELF_REPORT_DOMAIN>/report --source-id <CLIENT_ID> --secret <SELF_REPORT_SECRET>
```

Linux/OpenWrt 非交互安装 / 更新 cron，默认和示例推荐每 60 分钟上报一次；`--install-cron N` 的 `N` 可在 1-10080 分钟内调整。安装时会保存配置；cron 后续只引用配置文件，不再把 token 展开写入 cron 命令行：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/self-report/po0-outbound-ip-report.sh | bash -s -- --worker-url https://<SELF_REPORT_DOMAIN>/report --source-id <CLIENT_ID> --secret <SELF_REPORT_SECRET> --install-cron 60
```

Linux/OpenWrt 查看本脚本管理的 cron 计划：

```bash
crontab -l | sed -n '/# PO0_SELF_REPORT_BEGIN/,/# PO0_SELF_REPORT_END/p'
```

Linux/OpenWrt 暂停或恢复本脚本管理的定时上报；暂停只影响自动 cron，不影响手动立即上报：

```bash
po0-self-report --pause-schedule
```

```bash
po0-self-report --resume-schedule
```

Linux/OpenWrt 查看最近 self-report 日志：

```bash
tail -n 40 /tmp/po0-self-report.log
```

Windows PowerShell 交互式运行，默认进入菜单；推荐显式加 `-Menu`。菜单里的“配置并保存上报参数”只写本地配置文件，不安装计划任务；“安装 / 更新定时上报”会提示计划任务间隔，保存后写入计划任务；“暂停 / 恢复定时上报”只影响自动计划任务，手动“立即上报一次”仍可用：

```powershell
$script="$env:TEMP\po0-outbound-ip-report.ps1"; irm -UseBasicParsing 'https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/self-report/po0-outbound-ip-report.ps1' -OutFile $script; powershell -ExecutionPolicy Bypass -File $script -Menu
```

Windows PowerShell 非交互保存配置，不安装计划任务；`-SourceId` 和 `-Identity` 推荐填设备名，避免多台设备都混到 `self-report` 来源下：

```powershell
$script="$env:TEMP\po0-outbound-ip-report.ps1"; irm -UseBasicParsing 'https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/self-report/po0-outbound-ip-report.ps1' -OutFile $script; powershell -ExecutionPolicy Bypass -File $script -WorkerUrl "https://<SELF_REPORT_DOMAIN>/report" -SourceId $env:COMPUTERNAME -Identity $env:COMPUTERNAME -Secret "<SELF_REPORT_SECRET>" -SaveConfig
```

Windows PowerShell 非交互立即上报一次；如果没有传 `-WorkerUrl` 等参数，会读取已保存配置：

```powershell
$script="$env:TEMP\po0-outbound-ip-report.ps1"; irm -UseBasicParsing 'https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/self-report/po0-outbound-ip-report.ps1' -OutFile $script; powershell -ExecutionPolicy Bypass -File $script -WorkerUrl "https://<SELF_REPORT_DOMAIN>/report" -SourceId $env:COMPUTERNAME -Identity $env:COMPUTERNAME -Secret "<SELF_REPORT_SECRET>"
```

Windows PowerShell 非交互安装 / 更新计划任务，默认每 60 分钟上报一次。安装 / 更新计划任务时建议从 `$env:TEMP` 下载脚本再运行，让脚本覆盖安装到 `%LOCALAPPDATA%\PO0\po0-self-report.ps1` 或 `%ProgramData%\PO0\po0-self-report.ps1`。安装时会保存配置；计划任务后续只引用配置文件，不再把 token 展开写入计划任务参数。计划任务通过隐藏 launcher 启动 PowerShell，不弹出 CMD/PowerShell 窗口；自动上报成功或失败后会弹出 Windows 通知并继续写日志。若系统通知被关闭或没有登录桌面会话，结果仍会写入日志：

```powershell
$script="$env:TEMP\po0-outbound-ip-report.ps1"; irm -UseBasicParsing 'https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/self-report/po0-outbound-ip-report.ps1' -OutFile $script; powershell -ExecutionPolicy Bypass -File $script -WorkerUrl "https://<SELF_REPORT_DOMAIN>/report" -SourceId $env:COMPUTERNAME -Identity $env:COMPUTERNAME -Secret "<SELF_REPORT_SECRET>" -InstallTask -Minutes 60
```

`<SELF_REPORT_SECRET>` 只替换为 secret 本身，例如 `daf80...ce94`；不要写成 `secret:daf80...` 或 `secret：daf80...`。

Windows PowerShell 查看计划任务状态和最近日志：

```powershell
Get-ScheduledTaskInfo -TaskName "PO0 Self Report to LAN Worker"
```

Windows PowerShell 暂停或恢复本脚本管理的定时上报；暂停只影响自动计划任务，不影响手动立即上报。管理员安装时脚本默认在 `%ProgramData%\PO0\po0-self-report.ps1`，普通用户安装时默认在 `%LOCALAPPDATA%\PO0\po0-self-report.ps1`：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\PO0\po0-self-report.ps1" -PauseSchedule
```

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\PO0\po0-self-report.ps1" -ResumeSchedule
```

```powershell
$log="$env:LOCALAPPDATA\PO0\po0-self-report.log"; if (-not (Test-Path -LiteralPath $log)) { $log="$env:ProgramData\PO0\po0-self-report.log" }; Get-Content -Tail 40 -LiteralPath $log
```

PowerShell 客户端也支持显式 `-Menu`；两个客户端默认拒绝 `http://`；只有本地调试或临时旧环境才显式使用 `--allow-http` / `-AllowHttp`。Linux/OpenWrt 默认配置文件 root 为 `/etc/po0-self-report/settings.env`，普通用户为 `~/.config/po0-self-report/settings.env`；Windows 默认配置文件管理员为 `%ProgramData%\PO0\self-report.json`，普通用户为 `%LOCALAPPDATA%\PO0\self-report.json`。配置文件会明文保存 self-report secret，请只放在可信设备上。

访问设备客户端的一次性上报会以明确状态行结束：成功时显示 `Self-report 已完成：...`，并保留 LAN Worker 返回的 `OK <ip>; targets=<N>`；URL 校验、公网 IPv4 探测、HTTP 请求或 LAN Worker -> PO0 上报链路失败时显示 `Self-report 未完成：...` 并以非零状态退出。Linux/OpenWrt cron 每次运行的完整输出写到 `/tmp/po0-self-report.log`。Windows 计划任务不会弹出可见 CMD/PowerShell 窗口；安装 / 更新计划任务时会生成隐藏 launcher，并把每次运行的开始、LAN Worker 返回和完成/未完成结果写到日志，管理员安装默认在 `%ProgramData%\PO0\po0-self-report.log`，普通用户安装默认在 `%LOCALAPPDATA%\PO0\po0-self-report.log`；自动上报完成或失败会弹 Windows 通知，通知不可用时仍以日志为准，菜单里的“查看定时上报状态”会显示上次运行结果和最近日志。

self-report client 查询公网 IPv4 会按默认列表轮询：`https://ip9.com.cn/get`、163 邮箱、Bilibili、126、腾讯新闻、爱奇艺、央视、12306、`https://myip.ipip.net/json`。脚本会记住上次使用位置，下次从下一个接口开始；默认不再使用 `ip-api`、`ipify`、`icanhazip`、`ifconfig.co`。

## Egern 当前出口 IP 上报

Egern 模块不是 DDNS 模块。它的逻辑是：

1. 用 `DIRECT` 轮询 IP 查询接口获取手机当前出口 IPv4，默认列表从 `https://ip9.com.cn/get` 开始，后续是国内接口和 `myip.ipip.net`。
2. 通过一次性 SSH 调 PO0：

```bash
bash /root/nftables-relay-manager.sh --ssh-ip-report <source-id> <ipv4> <token> <identity> <ttl>
```

Egern 放行 TTL 默认 `21600` 秒（6 小时）。单 PO0 可在模块环境变量 `TTL_SECONDS` 覆盖；多个 PO0 可在 `SSH_REPORT_TARGETS` 每行最后一列分别覆盖。实际 SSH 自动上报周期由 `AUTO_REPORT_INTERVAL_SECONDS` 控制，默认 `3600` 秒，可设置 `600` 到 `86400` 秒；建议让 TTL 至少大于自动上报周期并留出余量。模块 schedule 每 10 分钟轻量检查一次；如果 TTL 小于自动上报周期，脚本会提前续期，尽量避免过期空窗。

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

- `schedule`：默认每 10 分钟上报。
- `network`：网络变化时上报。
- `generic`：手动立即上报。
- `widget`：查看最近成功 IP、时间、TTL、失败原因、网络类型、PO0 host。

Egern 可以向多个 PO0 上报同一个当前出口 IPv4。模块环境变量 `SSH_REPORT_TARGETS` 可以一行一个目标，也可以用逗号或分号分隔多个目标：

```text
source|host|port|user|script|token|identity|ttl
```

示例：

```text
iphone-sg|sg-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_SG|egern-iphone|21600
iphone-us|us-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_US|egern-iphone|21600
```

如果 Egern 输入框会把换行折叠成空格，建议直接用逗号连接多个目标。

不填 `SSH_REPORT_TARGETS` 时，模块按单目标 `PO0_HOST`、`SSH_REPORT_SOURCE`、`SSH_REPORT_TOKEN` 运行。旧 Egern Client IP 模块不再保留兼容。

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
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/lan-worker/po0-lan-client.sh | bash -s -- --install-self
po0-lan-client --webauth-server --listen 127.0.0.1:8787 --po0-host <PO0_HOST> --po0-script /root/nftables-relay-manager.sh --webauth-source cf-access --webauth-token <WEBAUTH_TOKEN>
```

多个 PO0 同样使用“WebAuth 放行目标”：

```bash
po0-lan-client --webauth-server --listen 127.0.0.1:8787 --webauth-targets 'cf-access|sg-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_SG|21600|;cf-access|us-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_US|21600|'
```

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

iplist 离线包可在本地构建，再到 PO0 主控菜单 `来源、客户端与资源 -> 源 IP 白名单 -> 导入 / 刷新 iplist 离线包` 导入。

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
