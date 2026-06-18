# PO0 nftables Relay / LAN Worker

这里是 PO0 nftables 中转管理器、LAN Worker、Egern 当前出口 IP 上报和 self-report client 的文档。

核心边界：

- PO0 不开放 HTTP / WebAuth / Secret URL。
- PO0 不做本地 DDNS 解析；`--refresh-ddns` 只按外部已上报且仍在 TTL 内的 DDNS 结果重建/应用，不延长原上报 TTL。
- LAN Worker 负责 DDNS 解析上报、`iplist/ipdb` 资源任务、WebAuth Client、Self-report 接收端。
- Egern 负责移动设备当前出口 IPv4 上报，不再解析 DDNS。
- 资源任务只允许 `iplist`、`ipdb`，不支持任意远程 shell。

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

查看 PO0 主控当前版本更新内容：

```bash
ssh root@<PO0_HOST> 'bash /root/nftables-relay-manager.sh --changelog'
```

LAN Worker 命令在内网 Worker 机器上执行，不在 PO0 上执行。DDNS 解析上报 + 资源任务轮询领取：

推荐先用交互向导。向导会检查到 PO0 的密钥 SSH；密钥 SSH 可用时，会自动调用 PO0 主控读取所需 token，然后写入本机配置、安装本机 `po0-lan-client` 命令，并按选择安装本机 Worker 轮询器 / systemd 服务。首次向导里的 PO0 SSH 地址一次只填一个；多个 PO0 目标后续进入菜单添加：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/lan-worker/po0-lan-client.sh | bash
```

SSH 认证按向导选择：系统默认 SSH 配置/agent、已有私钥路径，或粘贴专用私钥。粘贴的私钥会保存到本机配置目录并设置 600 权限。`额外 SSH 参数` 是传给 `ssh` 的选项，例如 `-J jump-host` 或 `-o StrictHostKeyChecking=accept-new`，不是私钥短语；带短语的私钥需要 `ssh-agent`。菜单里的 `DDNS 解析上报 -> DDNS 目标 / 上报计划` 管理 DDNS 目标和本机上报间隔；`PO0 目标`、`SSH 私钥 / 参数`、`目标 Token`、`Self-report / WebAuth TTL` 分开管理目标、SSH、Token 和自上报/WebAuth TTL；`资源统计 / PO0 创建计划` 只读显示 PO0 端资源任务创建 cron，Worker 本机只安装轮询器领取 pending 任务。

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

Linux/OpenWrt Self-report client：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/self-report/po0-outbound-ip-report.sh | bash
```

Linux/OpenWrt Self-report client 非交互安装，每 15 分钟上报一次：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/self-report/po0-outbound-ip-report.sh | bash -s -- --worker-url <LAN_WORKER_REPORT_URL> --source-id <CLIENT_ID> --secret <SELF_REPORT_SECRET> --install-cron 15
```

Windows Self-report client：

```powershell
$env:PO0_LAN_WORKER_URL='<LAN_WORKER_REPORT_URL>'; $env:PO0_SELF_REPORT_SOURCE='<CLIENT_ID>'; $env:PO0_SELF_REPORT_SECRET='<SELF_REPORT_SECRET>'; $env:INSTALL_TASK='1'; $env:MINUTES='15'; irm -UseBasicParsing 'https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/self-report/po0-outbound-ip-report.ps1' | iex
```

PowerShell 客户端下载后也支持 `-Menu`，使用 `irm | iex` 时可设置 `$env:PO0_SELF_REPORT_MENU='1'` 进入菜单。

Egern 模块 raw URL：

```text
https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/egern/PO0-SSH-IP-Report.yaml
```

## PO0 主控菜单

主菜单按功能分组：

- 基础操作：安装、手动刷新 PO0 公网 IP 缓存、查看 Dashboard。
- 规则管理：新增、编辑、排序、启停、删除、导入、导出转发规则。
- 访问来源 / 白名单 / 客户端：源 IP 白名单、LAN Worker/客户端/Egern 部署命令、内网资源更新任务。
- 系统维护：中转参数、自检、BBR。

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

LAN Worker 里 `--source-key` 只是 PO0 DDNS 来源 key/名称，用来匹配 PO0 来源表；`--ddns-domain` 才是真正要解析的 DDNS 域名。旧参数 `--domain` 仍作为兼容别名：没有 `--ddns-domain` 时，同时作为 source key 和 DDNS 域名。

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

新版自检应显示 `版本` 为 `2026.06.18+build.6` 或更新，`资源上传` 为“通过 PO0 manager stdin 上传资源产物（不使用 SCP）”，不再调用 `scp`。

`--upgrade-self` 更新成功后会输出安装路径、权限设置结果、版本变化和新脚本内置的更新内容；具体状态再用 `--version` 查看。从菜单里选择“从 GitHub 更新脚本”时，更新成功后会自动设置最终安装路径的执行权限，并重新打开新版菜单。命令行直接执行 `--upgrade-self` 仍会更新后退出，方便继续串行执行 `--version` 或 `--install-cron`。

如果 LAN Worker 查询 PO0 创建计划时出现 `--resource-task-cron-status not allowed for scope worker`，说明 PO0 上的专用受限 SSH wrapper 还没刷新到新版；在 PO0 上用新版 manager 执行 `--refresh-report-key-wrapper` 即可。这个报错只影响创建计划只读查询，不影响 pending 资源任务领取、上传和完成。

配置里旧的 `PO0_SCRIPT=/root/nftables-relay-manager.sh` 继续兼容。

## LAN Worker Self-report

Self-report 用于“访问设备自己检测当前出口 IPv4，然后报给 LAN Worker”。PO0 仍然不开放 HTTP，LAN Worker 通过 SSH 调 PO0 的 `--client-ip-report`：

```text
访问设备 self-report client -> LAN Worker HTTP -> SSH -> PO0 --client-ip-report
```

LAN Worker 启动接收端：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/lan-worker/po0-lan-client.sh | bash -s -- --install-self
po0-lan-client --self-report-server --self-report-listen 127.0.0.1:8788 --po0-host <PO0_HOST> --po0-script /root/nftables-relay-manager.sh --self-report-source self-report --client-ip-token <CLIENT_REPORT_TOKEN> --self-report-secret <SELF_REPORT_SECRET>
```

Self-report 放行 TTL 默认 `3600` 秒，由 LAN Worker 上报 PO0 时传入；可以在启动接收端时加 `--self-report-ttl <秒数>`，也可以在 LAN Worker 菜单 `PO0 目标、SSH、Token 与 TTL -> Self-report / WebAuth TTL` 里修改目标覆盖值。访问设备客户端只决定“多久上报一次”，不决定 TTL。

多个 PO0 用“设备自上报目标”合并到同一个 LAN Worker：

```text
source|host|port|user|script|token|ttl|ssh_args
self-report|sg-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_SG|3600|
self-report|us-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_US|3600|
```

```bash
po0-lan-client --self-report-server --self-report-listen 127.0.0.1:8788 --self-report-targets 'self-report|sg-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_SG|3600|;self-report|us-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_US|3600|' --self-report-secret <SELF_REPORT_SECRET>
```

访问设备定时自上报：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/self-report/po0-outbound-ip-report.sh | bash
```

也可以非交互安装 cron，默认和示例推荐每 15 分钟上报一次；`--install-cron N` 的 `N` 可在 1-59 分钟内调整：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/self-report/po0-outbound-ip-report.sh | bash -s -- --worker-url <LAN_WORKER_REPORT_URL> --source-id <CLIENT_ID> --secret <SELF_REPORT_SECRET> --install-cron 15
```

Windows：

```powershell
$env:PO0_LAN_WORKER_URL='<LAN_WORKER_REPORT_URL>'; $env:PO0_SELF_REPORT_SOURCE='<CLIENT_ID>'; $env:PO0_SELF_REPORT_SECRET='<SELF_REPORT_SECRET>'; $env:INSTALL_TASK='1'; $env:MINUTES='15'; irm -UseBasicParsing 'https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/self-report/po0-outbound-ip-report.ps1' | iex
```

PowerShell 客户端下载后也支持 `-Menu`，使用 `irm | iex` 时可设置 `$env:PO0_SELF_REPORT_MENU='1'` 进入菜单。

self-report client 查询公网 IPv4 会按默认列表轮询：`https://ip9.com.cn/get`、163 邮箱、Bilibili、126、腾讯新闻、爱奇艺、央视、12306、`https://myip.ipip.net/json`。脚本会记住上次使用位置，下次从下一个接口开始；默认不再使用 `ip-api`、`ipify`、`icanhazip`、`ifconfig.co`。

## Egern 当前出口 IP 上报

Egern 模块不是 DDNS 模块。它的逻辑是：

1. 用 `DIRECT` 轮询 IP 查询接口获取手机当前出口 IPv4，默认列表从 `https://ip9.com.cn/get` 开始，后续是国内接口和 `myip.ipip.net`。
2. 通过一次性 SSH 调 PO0：

```bash
bash /root/nftables-relay-manager.sh --ssh-ip-report <source-id> <ipv4> <token> <identity> <ttl>
```

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
iphone-sg|sg-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_SG|egern-iphone|3600
iphone-us|us-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_US|egern-iphone|3600
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
po0-lan-client --webauth-server --listen 127.0.0.1:8787 --webauth-targets 'cf-access|sg-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_SG|3600|;cf-access|us-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_US|3600|'
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

iplist 离线包可在本地构建，再到 PO0 主控菜单 `系统维护 -> 管理源 IP 白名单 -> 导入 / 刷新 iplist 离线包` 导入。

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
