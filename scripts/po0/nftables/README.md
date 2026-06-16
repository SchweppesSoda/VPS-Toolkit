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

LAN Worker 命令在内网 Worker 机器上执行，不在 PO0 上执行。DDNS 解析上报 + 资源任务轮询：

推荐先用交互向导。向导会检查到 PO0 的密钥 SSH；密钥 SSH 可用时，会自动调用 PO0 主控读取所需 token，然后写入本机配置并按选择安装 cron / systemd 服务：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/tools/po0-lan-client.sh | bash
```

也可以显式进入向导：

```bash
po0-lan-client --wizard
```

如果要用于自动化，仍可直接传参数：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/tools/po0-lan-client.sh | bash -s -- --bootstrap --po0-host <PO0_HOST> --po0-script /root/nftables-relay-manager.sh --source-key <DDNS_SOURCE_KEY> --ddns-domain <DDNS_DOMAIN> --token <DDNS_TOKEN> --resource-token <RESOURCE_TOKEN> --install-cron 5
```

LAN Worker：只做 `iplist/ipdb` 资源任务：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/tools/po0-lan-client.sh | bash -s -- --bootstrap --po0-host <PO0_HOST> --po0-script /root/nftables-relay-manager.sh --resource-token <RESOURCE_TOKEN> --install-cron 5
```

Linux/OpenWrt Self-report client：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/tools/po0-outbound-ip-report.sh | bash -s -- --worker-url <LAN_WORKER_REPORT_URL> --source-id <CLIENT_ID> --secret <SELF_REPORT_SECRET> --install-cron 5
```

Windows Self-report client：

```powershell
$env:PO0_LAN_WORKER_URL='<LAN_WORKER_REPORT_URL>'; $env:PO0_SELF_REPORT_SOURCE='<CLIENT_ID>'; $env:PO0_SELF_REPORT_SECRET='<SELF_REPORT_SECRET>'; $env:INSTALL_TASK='1'; $env:MINUTES='5'; irm -UseBasicParsing 'https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/tools/po0-outbound-ip-report.ps1' | iex
```

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
管理源 IP 白名单 -> 管理动态来源开关（高级自选来源）
```

可组合的来源：

```text
manual, ssh_temp, ddns, client_ip, ssh_report, webauth, learned, region
```

动态来源缓存策略：
- `ddns`、`client_ip`、`ssh_report`、`webauth` 按 `source_type + source_value` 分组。
- 每个来源默认最多保留最近 5 个有效 IP。
- 已存在 IP 再次上报会刷新时间和过期时间，不重复新增。
- 过期条目不会进入最终 nftables 白名单缓存。

手动清理和安装清理 cron：

```bash
bash /root/nftables-relay-manager.sh --cleanup-dynamic-allowlist
bash /root/nftables-relay-manager.sh --install-dynamic-allowlist-cleanup-cron daily
```

## DDNS Resolver 上报

推荐流程：

1. PO0 端在“管理源 IP 白名单 -> 管理 DDNS 来源”里添加域名并生成 DDNS token。
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

首次部署推荐运行 `po0-lan-client --wizard`。长期维护可进入 `po0-lan-client --menu`，在“上报目标”里查看、编辑、删除、启停；底层仍保存到本机配置文件，旧配置继续兼容。

PO0 不做本地 DDNS 解析。`--refresh-ddns` 只会把已经由 LAN Worker/路由器上报、且仍在 TTL 内的结果重建/应用；它不会延长原上报 TTL：

```bash
bash /root/nftables-relay-manager.sh --refresh-ddns
```

## LAN Worker 资源任务

PO0 端创建资源任务：

```bash
bash /root/nftables-relay-manager.sh --resource-task-create all
bash /root/nftables-relay-manager.sh --install-resource-task-cron all daily
```

LAN Worker 端定时领取任务、下载/构建文件，再用 SCP 回传 PO0。固定任务白名单只有：

```text
iplist
ipdb
```

Worker 管道运行且需要 cron 或服务时，会自动落盘到：

```text
root:     /usr/local/sbin/po0-lan-client
non-root: ~/.local/bin/po0-lan-client
```

配置里旧的 `PO0_SCRIPT=/root/nftables-relay-manager.sh` 继续兼容。

## LAN Worker Self-report

Self-report 用于“访问设备自己检测当前出口 IPv4，然后报给 LAN Worker”。PO0 仍然不开放 HTTP，LAN Worker 通过 SSH 调 PO0 的 `--client-ip-report`：

```text
访问设备 self-report client -> LAN Worker HTTP -> SSH -> PO0 --client-ip-report
```

LAN Worker 启动接收端：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/tools/po0-lan-client.sh | bash -s -- --install-self
po0-lan-client --self-report-server --self-report-listen 127.0.0.1:8788 --po0-host <PO0_HOST> --po0-script /root/nftables-relay-manager.sh --self-report-source self-report --client-ip-token <CLIENT_REPORT_TOKEN> --self-report-secret <SELF_REPORT_SECRET>
```

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
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/tools/po0-outbound-ip-report.sh | bash -s -- --worker-url <LAN_WORKER_REPORT_URL> --source-id <CLIENT_ID> --secret <SELF_REPORT_SECRET> --install-cron 5
```

Windows：

```powershell
$env:PO0_LAN_WORKER_URL='<LAN_WORKER_REPORT_URL>'; $env:PO0_SELF_REPORT_SOURCE='<CLIENT_ID>'; $env:PO0_SELF_REPORT_SECRET='<SELF_REPORT_SECRET>'; $env:INSTALL_TASK='1'; $env:MINUTES='5'; irm -UseBasicParsing 'https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/tools/po0-outbound-ip-report.ps1' | iex
```

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
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/tools/po0-lan-client.sh | bash -s -- --install-self
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
