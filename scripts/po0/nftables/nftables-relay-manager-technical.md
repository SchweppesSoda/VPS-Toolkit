# nftables relay manager 说明与技术文档

本文先用普通语言说明 `nftables-relay-manager.sh` 是做什么的、平时怎么用、遇到问题怎么看；后半部分再记录技术结构、文件格式和 roadmap。非技术读者可以先读第 0 章到第 2 章，维护脚本或排查细节时再看后面的技术章节。

## 0. 先给非技术读者的版本

一句话：这个脚本是在 PO0 中转机上管理“哪些端口转发到哪里，以及哪些来源 IP 可以访问这些转发端口”的工具。

可以把它理解成一个中转机管家：

```text
转发规则：告诉中转机，外面访问哪个端口，要转到内网或目标机器的哪个地址。
白名单：告诉中转机，哪些来源 IP 被允许访问这些转发端口。
动态来源：家里宽带、手机网络、当前 SSH 登录地址这类会变化的来源 IP。
渲染检查：脚本应用前会先生成临时 nftables 配置并执行 nft -c 检查。
日志：记录哪些来源 IP 被白名单挡掉，方便以后判断要不要放行。
```

日常最常用的是交互菜单：

```bash
bash nftables-relay-manager.sh
```

常见操作：

```text
首次部署：基础操作 -> 安装 / 初始化 nftables
新增或修改转发：规则管理 -> 新增 / 编辑转发规则
管理来源白名单：系统维护 -> 管理源 IP 白名单
看当前状态和自检：基础操作 -> 查看概览，或系统维护 -> 诊断 / 自检
高级调试渲染：bash nftables-relay-manager.sh --render > /tmp/po0-relay.conf
```

如果你只是想“让我当前 SSH 这个公网 IP 临时能访问转发端口”，进入：

```text
管理源 IP 白名单
从当前 SSH 来源临时加入 default /32
```

如果你用 DDNS，比如 `home.example.com` 永远指向家里的公网 IP，流程是：

```text
客户端或路由器负责更新 DNS
推荐由 LAN Worker、路由器、OpenWrt、NAS 或 Windows/Linux 小脚本解析 DDNS 域名
外部机器通过 SSH 调 PO0 的 --ddns-report 上报解析出的公网 A 记录
PO0 本机默认不做 DDNS 解析
成功后把得到的公网 IP 写入白名单
```

如果有人访问被白名单保护的端口但没有被允许，脚本会记录“被挡住的来源 IP”。你可以在“管理源 IP 白名单”里采集和查看统计：

```text
管理源 IP 白名单
采集被阻挡访问日志
查看被阻挡访问统计
压缩被阻挡访问日志
```

最重要的安全原则：

```text
不要手动乱改 /etc/nftables.d 里的生成文件，尽量通过菜单操作。
重建应用时脚本会先生成临时配置并执行 nft -c 检查。
DDNS 或动态来源解析失败时，脚本会保留旧结果，不会立刻清空白名单。
DDNS 外部上报建议使用菜单生成的 token；如果 token 文件存在，上报命令必须携带正确 token。
学习服务只给候选建议，不会自动放行陌生 IP。
Egern SSH report 和 WebAuth 已实现，但都通过 SSH 调 PO0；PO0 不开放 HTTP / WebAuth / Secret URL。
WebAuth 的 HTTP 入口只允许跑在 LAN Worker 上，推荐前置 Cloudflare Access/Tunnel。

资源更新采用另一套“PO0 任务队列 + 内网 Worker 主动领取”协议，不属于 URL 白名单上报。PO0 只允许 `iplist` 和 `ipdb` 两种固定任务，不能通过该接口发送任意 Shell 命令。
```

## 0.1 你看到的几个词是什么意思

```text
PO0
  这里指运行这个脚本的中转机。

nftables
  Linux 的防火墙和转发规则系统。你不需要手写 nftables 规则，脚本会生成。

DNAT / 转发
  外面访问 PO0 的某个端口，PO0 把流量转到目标机器。

SNAT / 回写
  让目标机器回包时能正确回到 PO0，再由 PO0 回给访问者。

源 IP 白名单
  只有这些来源 IP 能访问托管转发端口。

/32
  单个 IPv4 地址。例如 1.2.3.4/32 就是只放行 1.2.3.4。

DDNS
  动态域名。家里公网 IP 变化时，客户端先更新域名，PO0 再解析域名得到新 IP。

--render
  高级调试命令，只把 relay nftables 配置输出到 stdout，不应用规则。
```

## 0.2 出问题时先看哪里

如果“访问不了转发端口”，先按这个顺序看：

```text
1. 基础操作 -> 查看概览与规则列表
2. 系统维护 -> 诊断 / 自检
3. 管理源 IP 白名单 -> 来源/IP 明细
4. 管理源 IP 白名单 -> 采集被阻挡访问日志
5. 管理源 IP 白名单 -> 查看被阻挡访问统计，确认自己的公网 IP 是否被挡住
```

如果“DDNS 没生效”，先确认：

```text
域名在外部 DNS 已经解析到正确公网 IP
po0-relay-allowlist-sources.tsv 里 source enabled=1
LAN Worker / 外部脚本已经通过 --ddns-report 上报
运行过“刷新 DDNS 来源”或外部上报已触发重建应用
```

下面开始是维护者和排障用的技术细节。

## 1. 定位与边界

`nftables-relay-manager.sh` 是面向 PO0 或其它专用中转机场景的交互式 Bash 管理脚本。它集中管理：

这一章回答“这个脚本负责什么、不负责什么”。普通使用者只需要知道：它只应该管自己生成的转发和白名单规则，不应该顺手接管你机器上的所有网络配置。

```text
托管转发规则
SNAT / masquerade / 无回写模式
可选入站防火墙接管
源 IP 白名单
地区 iplist 离线包
自定义、SSH 临时、DDNS 等来源渠道
conntrack 学习候选
IPDB 辅助查询
blocked 来源日志
```

安全边界：

```text
只托管自己生成的 nftables 表和配置文件
修改规则前做端口、IP、CIDR 和 nft 语法校验
学习到的来源 IP 只作为候选，不自动放行
源白名单动态来源失败时保留旧结果，避免误锁
高风险 /16 候选加入白名单时需要输入 YES
```

脚本仍以交互菜单为主。少量非交互参数用于 systemd runner、重定向渲染、上报入口和定时维护。

## 2. 文件与状态

固定工作目录：`/etc/nftables.d`。

这一章列的是脚本的“账本”和“输出文件”。一般不要手动编辑这些文件，除非你明确知道自己在做什么；日常操作优先走菜单。

### 2.1 nftables 与全局配置

```text
/etc/nftables.conf                         主 nftables 配置
/etc/nftables.d/po0-relay.conf             脚本生成的 relay nftables 规则
/etc/nftables.d/po0-relay.env              全局设置
/etc/nftables.d/po0-relay.rules            托管转发规则
/etc/nftables.d/backups/                   备份和导出
```

脚本生成两个 nft 表：

```text
table ip po0_relay_nat
table ip po0_relay_mangle
```

`po0_relay_nat` 负责 DNAT、SNAT/masquerade、源 IP 过滤和可选入站防火墙；`po0_relay_mangle` 负责可选 MSS clamp。

### 2.2 白名单状态文件

```text
/etc/nftables.d/po0-relay-src-allowlist.txt          生成后的源 IP 白名单缓存
/etc/nftables.d/po0-relay-custom-src-allowlist.txt   旧自定义源 IP 白名单，继续兼容
/etc/nftables.d/po0-relay-allowlist-sets.tsv         白名单 set 定义
/etc/nftables.d/po0-relay-allowlist-entries.tsv      标准化来源条目
/etc/nftables.d/po0-relay-allowlist-sources.tsv      DDNS 等动态来源定义
/etc/nftables.d/po0-relay-allowlist-profiles/        白名单配置档案
```

### 2.3 学习、日志与辅助数据

```text
/etc/nftables.d/po0-relay-learn.tsv                  conntrack 学习日志
/etc/nftables.d/po0-relay-learn-summary.tsv          学习每日汇总
/etc/nftables.d/po0-relay-learn-daily-ip.tsv         学习每日 IP 聚合
/etc/nftables.d/po0-relay-blocked.tsv                被源白名单阻挡的来源记录
/etc/nftables.d/po0-relay-blocked-summary.tsv        被阻挡来源汇总
/etc/nftables.d/po0-iplist/                          地区白名单离线包
/etc/nftables.d/qqwry.ipdb                           可选 IPDB 数据库
/etc/nftables.d/po0-relay-resource-tasks.tsv         内网资源更新任务和结果
/etc/nftables.d/po0-relay-resource-task.token        资源任务专用 Token
/etc/nftables.d/po0-relay-resource-inbox/            资源回传临时收件目录
/etc/nftables.d/po0-ipdb-venv/                       可选 IPDB Python venv
/usr/local/sbin/nftables-relay-learn                 学习服务 runner
/etc/systemd/system/nftables-relay-learn.service     学习服务 unit
```

## 3. 核心配置模型

这一章解释脚本内部怎么记住配置。可以把它理解成几张表：一张记全局设置，一张记转发规则，一张记白名单集合，一张记具体来源 IP。

### 3.1 全局设置

`po0-relay.env` 保存：

```text
RELAY_MODE                 lan / public / mixed
RELAY_LAN_IP               中转机内网 IP
ENABLE_MSS_CLAMP           是否启用 MSS clamp
MSS_VALUE                  MSS 值，默认 1452
MANAGE_INPUT_FIREWALL      是否接管入站防火墙
SSH_PORTS                  SSH 例外端口
ENABLE_SRC_ALLOWLIST       是否启用源 IP 白名单
SRC_ALLOWLIST_MODE         manual_only / trusted_dynamic / region_plus_trusted / region_only / custom_sources
SRC_ALLOWLIST_REGION_IDS   已选地区 ID
AUTOMATION_MODE            regular / attack
PUBLIC_IP                  公网 IP 缓存
```

### 3.2 托管转发规则

`po0-relay.rules` 每行保存一条规则：

```text
id|name|proto|listen_port|dest_ip|dest_port|enabled|snat_mode
```

字段含义：

```text
proto       tcp / udp / both
snat_mode   relay_lan / masquerade / none
```

### 3.3 白名单 set 模型

`po0-relay-allowlist-sets.tsv`：

```text
id|label|enabled|scope|ports|sources|note
```

当前实际渲染只启用 `default` public set：

```text
default|Default public allowlist|1|public|*|region,manual,learned|...
```

渲染为 nft set：

```text
po0_src_default
```

端口专属 set 的 schema 已保留，默认关闭，尚未接入 UI 和按端口绑定渲染。

### 3.4 白名单 entries 模型

`po0-relay-allowlist-entries.tsv`：

```text
set_id|cidr|source_type|source_value|note|created_at|expires_at
```

支持的 `source_type`：

```text
manual
region
learned
ssh_temp
ddns
client_ip
ssh_report
webauth
```

当前已进入实际生成链路的来源：

```text
manual       菜单添加的手动 CIDR，同时继续兼容旧 custom 文件
ssh_temp     当前 SSH 来源临时 /32，默认不参与 trusted_dynamic，只作为手动救急
ddns         LAN Worker / 外部解析 DDNS 后上报的结果
client_ip    LAN Worker self-report server 代报访问设备 IP
ssh_report   Egern / 直接 SSH 上报当前出口 IPv4
webauth      LAN Worker WebAuth 验证后上报的访问设备 IP
region       旧地区白名单文件直接进入缓存，不逐条写 entries
```

过期 entries 保留作审计，但生成有效白名单缓存时跳过。

### 3.5 白名单 sources 模型

`po0-relay-allowlist-sources.tsv`：

```text
set_id|source_type|name|value|enabled|ttl_seconds|last_resolved_at|last_result
```

当前 `po0-relay-allowlist-sources.tsv` 只保存 DDNS 来源定义：

```text
default|ddns|home|home.example.com|1|300||
```

`last_result` 的含义：

```text
report:<ip_csv>      LAN Worker、路由器、OpenWrt、NAS 或 Windows/Linux 小脚本解析 DDNS 后，通过 --ddns-report 上报
local:<ip_csv>       旧版本兼容记录；新版本不再主动做 PO0 本机 DNS 解析
ERROR resolve_failed 本次没有拿到可用公网 IPv4
```

DDNS 来源可以通过菜单添加、删除、启用/停用、刷新应用和生成外部上报 token。外部上报成功时会立即把公网 IPv4 写为 `ddns` entries，并重建应用白名单；刷新时只复用 TTL 内的 `report:` 结果，不再由 PO0 本机解析域名。失败时保留旧 entries，不清空已生效结果。停用或删除 DDNS 来源时，会同步移除它对应的旧 `ddns` entries。

## 4. 渲染与应用链路

这一章解释“点菜单之后，脚本怎么把你的选择变成真正生效的防火墙规则”。核心思想是：先读取配置，生成临时规则，检查通过，再应用。

### 4.1 交互主流程

```text
main_menu
  -> do_install / do_add / do_edit_rule / do_delete / do_import_rules
  -> save_settings / save_rules
  -> write_nft_conf
  -> nft -c -f 预检
  -> reload_managed_rules 或 apply_full_config
```

### 4.2 配置渲染

`write_nft_conf()` 是核心渲染函数：

```text
load_settings
load_rules
load_allowlist_sets
validate_managed_listen_ports
ensure_input_firewall_ready
build_src_allowlist_cache（白名单开启时）
write_nft_allowlist_set
写 DNAT / SNAT / input_guard / mangle
```

现在 `write_nft_conf` 和 `build_src_allowlist_cache` 支持可选输出路径。`--render` 可以把计划生成的 relay nftables 配置输出到 stdout，用于高级调试或 diff，不触碰真实配置。

### 4.3 源白名单生成

白名单缓存生成顺序：

```text
1. region_only / region_plus_trusted / custom_sources 且来源包含 region：读取 iplist 离线包的地区 CIDR。
2. manual_only / trusted_dynamic / region_plus_trusted / custom_sources：读取 entries.tsv 中 default set 的未过期条目。
3. custom_sources 按 default set 的 sources 字段过滤 manual、ssh_temp、ddns、client_ip、ssh_report、webauth、learned、region 等来源。
4. 旧 custom 文件继续兼容，按 manual 来源参与迁移。
5. sort -u 去重。
6. 原子替换 po0-relay-src-allowlist.txt。
```

失败条件：

```text
仅地区库模式未选择地区
引用的地区文件缺失
地区文件存在非法 CIDR
仅手动/可信动态/高级自选模式没有任何有效 CIDR
地区 + 可信动态来源既没地区也没可信来源 CIDR
最终缓存为空
```

失败时不会继续 render / reload。

### 4.4 nft 规则行为

DNAT 前会按白名单判断来源：

```text
ip saddr @po0_src_default ... dnat ...
```

可选 `input_guard` 会对托管监听端口添加白名单外 drop，并记录 block 日志：

```text
ip saddr != @po0_src_default tcp dport { ... } limit rate 10/minute burst 20 packets log prefix "po0-block set=default proto=tcp " counter drop
ip saddr != @po0_src_default udp dport { ... } limit rate 10/minute burst 20 packets log prefix "po0-block set=default proto=udp " counter drop
```

## 5. 功能模块

这一章按功能解释脚本。普通读者可以只看自己关心的模块，例如 SSH 临时来源、DDNS、Egern SSH report、被阻挡访问日志。

### 5.1 中转模式和 SNAT

三种中转模式：

```text
lan      默认 relay_lan
public   默认 masquerade
mixed    每条规则单独选择
```

SNAT 模式：

```text
relay_lan     snat to RELAY_LAN_IP，目标机能看到中转机内网 IP
masquerade    内核选择出口地址
none          不回写，要求目标侧路由能回到源
```

### 5.2 入站防火墙

`MANAGE_INPUT_FIREWALL=1` 时，`input_guard` 策略为 drop，并默认放行：

```text
lo
established,related
icmp
SSH_PORTS
```

SSH 端口自动检测来源：

```text
当前 SSH_CLIENT / SSH_CONNECTION
sshd -T
/etc/ssh/sshd_config
默认 22
```

源 IP 白名单开启时，托管转发端口还会受到 `po0_src_default` 保护。

### 5.3 地区白名单与离线包

地区数据来自：

```text
https://github.com/metowolf/iplist
https://raw.githubusercontent.com/metowolf/iplist/refs/heads/master/docs/cncity.md
```

离线包只包含：

```text
docs/cncity.md
data/cncity/*.txt
```

构建脚本：

```text
tools/build-iplist-package.sh
tools/build-iplist-package.ps1
```

导入逻辑会解包、重建 `manifest.tsv`、校验数据文件和 CIDR，成功后才替换当前 `/etc/nftables.d/po0-iplist`。

### 5.4 自定义白名单与旧文件兼容

旧文件仍支持：

```text
/etc/nftables.d/po0-relay-custom-src-allowlist.txt
CIDR|备注
```

菜单新增手动 CIDR 时：

```text
写旧 custom 文件
同步写 default|CIDR|manual 到 entries.tsv
```

删除手动 CIDR 时也会删除 matching default entries，迁移期两边共同参与生成缓存，最终 `sort -u` 去重。

### 5.5 SSH 临时来源

入口：

```text
管理源 IP 白名单
从当前 SSH 来源临时加入 default /32
```

行为：

```text
从 SSH_CONNECTION 读取客户端公网 IPv4
只加入 /32，不自动放大到 /24
默认过期 24 小时，可输入 1-720 小时
写 entries.tsv：source_type=ssh_temp，source_value=SSH_CONNECTION
保存前创建 _last 快照
写入后如果当前模式未包含 ssh_temp，会切换为高级自选来源并保留原来源组合再追加 ssh_temp
重新 render 并应用
```

### 5.6 DDNS 来源

入口：

```text
管理源 IP 白名单 -> 管理 DDNS 来源
查看 DDNS 来源和上报统计
添加 / 编辑 / 删除 / 启用 / 停用 DDNS 来源
刷新并应用已启用 DDNS 来源
显示 / 生成外部上报 Token
```

非交互命令：

```bash
bash nftables-relay-manager.sh --refresh-ddns
bash nftables-relay-manager.sh --ddns-report home.example.com 1.2.3.4,5.6.7.8 TOKEN
bash nftables-relay-manager.sh --ddns-report-check home.example.com TOKEN
```

外部解析上报逻辑：

```text
外部机器负责解析 DDNS 域名
外部机器通过 SSH 调 PO0：--ddns-report <source-key> <公网IPv4[,公网IPv4...]> [token]
只接受公网 IPv4
成功后替换该 set_id + ddns + 域名 对应 entries
last_result 写入 report:<ip_csv>
更新 /etc/nftables.d/po0-relay-ddns-report-stats.tsv 统计
立即重建并应用白名单
```

PO0 端上报统计：

```text
/etc/nftables.d/po0-relay-ddns-report-stats.tsv
key|accepted_count|rejected_count|last_status|last_at|last_ips|last_error
```

该文件不是逐次追加日志；每个 DDNS 来源最多一条统计记录。菜单里的“查看 DDNS 来源和上报统计”会显示接受/拒绝次数、最近时间、最近 IP 和最近错误。删除或编辑 DDNS 来源时，旧域名对应的统计会同步清理。

刷新逻辑：

```text
读取 enabled=1 的 ddns source
如果 last_result 是 TTL 内的 report:<ip_csv>，使用外部上报结果
否则标记为本次没有可用上报结果；PO0 不主动解析 DDNS
只接受公网 IPv4
成功后替换该 set_id + ddns + 域名 对应 entries
外部结果写 report:<ip_csv>；local:<ip_csv> 只作为旧版本兼容记录读取
失败时保留旧 entries
停用或删除来源时移除对应旧 entries
刷新或移除后重建并应用白名单
```

客户端实现：

```text
scripts/po0/nftables/tools/po0-lan-client.sh
scripts/po0/nftables/tools/po0-outbound-ip-report.sh
scripts/po0/nftables/tools/po0-outbound-ip-report.ps1
```

`po0-lan-client.sh` 适合 Linux/macOS/OpenWrt 内网机器。它可以同时做 DDNS resolver 上报和资源任务轮询，也可以只做资源任务。公开仓库一键部署命令：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/tools/po0-lan-client.sh | bash -s -- --bootstrap --po0-host <PO0_HOST> --po0-script /root/nftables-relay-manager.sh --source-key home --ddns-domain home.example.com --token <DDNS_TOKEN> --resource-token <RESOURCE_TOKEN> --install-cron 5
```

Self-report client 适合运行在访问设备上：它检测自身当前出口公网 IPv4，并上报给 LAN Worker self-report server；LAN Worker 再通过 SSH 调 PO0：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/tools/po0-outbound-ip-report.sh | bash -s -- --worker-url <LAN_WORKER_REPORT_URL> --source-id <CLIENT_ID> --secret <SELF_REPORT_SECRET> --install-cron 5
```

Windows PowerShell 版本检测本机当前出口公网 IPv4 并上报 LAN Worker：

```powershell
$env:PO0_LAN_WORKER_URL='<LAN_WORKER_REPORT_URL>'; $env:PO0_SELF_REPORT_SOURCE='<CLIENT_ID>'; $env:PO0_SELF_REPORT_SECRET='<SELF_REPORT_SECRET>'; $env:INSTALL_TASK='1'; $env:MINUTES='5'; irm -UseBasicParsing 'https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/tools/po0-outbound-ip-report.ps1' | iex
```

`--bootstrap` 会先 probe，再写入本机目标配置；如果要求安装 cron，管道运行时会自动落盘到固定路径。Worker 默认调用 PO0 上的 `/root/nftables-relay-manager.sh`，也可以通过 `--po0-script` 覆盖。菜单仍可管理本机 Worker 的 PO0 目标：查看、添加、编辑、删除、启用/停用，执行 DDNS 解析上报和资源任务轮询，并管理 cron。一个配置文件可以放多台 PO0/VPS。

该 Worker 同时承担资源更新任务。目标配置末尾新增 `resource_token` 字段，旧配置没有该字段时按“未启用资源任务”处理。菜单可以直接编辑已有目标并补填 Token。

如果只需要内网 Worker 更新 `iplist` / `qqwry.ipdb`，可以只配置 `--po0-host` 和 `--resource-token`，不填写 `--ddns-domain`；这类目标会跳过 DDNS resolver，只轮询资源任务。旧参数 `--domain` 仍作为兼容别名：没有 `--ddns-domain` 时，同时作为 source key 和 DDNS 域名。

资源任务流程：

```text
PO0 菜单创建 pending 任务
内网 Worker 通过 --resource-task-claim 领取任务
Worker 构建 iplist.tar.gz 或下载 qqwry.ipdb
Worker 计算 SHA-256 和文件大小
Worker 通过 SCP 上传到 PO0 返回的固定收件路径
Worker 调用 --resource-task-complete
PO0 校验、原子导入并把任务标记为 success/failed
```

PO0 非交互接口：

```bash
bash nftables-relay-manager.sh --resource-task-create iplist
bash nftables-relay-manager.sh --resource-task-create ipdb
bash nftables-relay-manager.sh --resource-task-create all
bash nftables-relay-manager.sh --install-resource-task-cron all daily
bash nftables-relay-manager.sh --remove-resource-task-cron
bash nftables-relay-manager.sh --resource-task-claim WORKER_ID TOKEN
bash nftables-relay-manager.sh --resource-task-complete TASK_ID WORKER_ID SHA256 SIZE TOKEN
bash nftables-relay-manager.sh --resource-task-fail TASK_ID WORKER_ID REASON TOKEN
bash nftables-relay-manager.sh --resource-task-ping TOKEN
```

`--resource-task-create` 和 `--install-resource-task-cron` 是 PO0 管理员入口，只创建等待领取的固定任务，不主动连接内网机器。`--resource-task-ping/claim/complete/fail` 主要供 Worker 调用。`--resource-task-ping` 只读检查 token；任务领取和状态修改使用 `flock`（系统提供时）串行化；上传路径由 PO0 生成，客户端不能指定生产文件路径。资源任务使用独立 Token，不复用 DDNS 上报 Token。

`qqwry.ipdb` 默认下载源：

```text
https://raw.githubusercontent.com/nmgliangwei/qqwry.ipdb/main/qqwry.ipdb
```

PO0 的基础 IPDB 格式校验使用常见的 `od`、`dd`、`grep` 检查文件头、元数据长度、关键字段和数据区，不要求预先安装 Python 包。系统已有 Python 时会追加严格 JSON 元数据校验；真正查询归属地仍需要菜单中的 `ipip-ipdb` 解析依赖。

Worker 的 `resource-stats.tsv` 每个 PO0 端点只保留一行累计统计，不会按任务无限追加。PO0 的任务文件保留全部活动任务和最近 500 条终态记录，管理员可以在菜单中查看结果，或把失败/执行中的任务重新排队。

### 5.6.1 Egern SSH report 上报

Egern 不再承担 DDNS 解析。它只做移动设备当前出口 IPv4 上报：

```text
Egern 用 DIRECT 轮询 IP 查询接口，默认列表为 IP9/163/Bilibili/126/腾讯新闻/爱奇艺/央视/12306/myip.ipip；脚本会记住上次起点，下次从下一个接口开始，从响应里提取当前公网 IPv4
Egern 通过一次性 SSH 调 PO0 --ssh-ip-report
PO0 写 entries.tsv：source_type=ssh_report
成功后重建并应用白名单
Egern 把最近状态写入 ctx.storage，Widget 读取显示
```

单 PO0 命令等价于：

```bash
bash /root/nftables-relay-manager.sh --ssh-ip-report <source-id> <ipv4> <token> <identity> <ttl>
```

多 PO0 上报由模块环境变量 `SSH_REPORT_TARGETS` 控制，一行一个目标：

```text
source|host|port|user|script|token|identity|ttl
```

示例：

```text
iphone-sg|sg-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_SG|egern-iphone|3600
iphone-us|us-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_US|egern-iphone|3600
```

脚本只查询一次当前 IPv4，然后按目标列表依次 SSH 上报。全部目标成功时状态为成功；部分失败时保留每个目标的成功/失败明细并发出失败通知，但不会回滚已成功的 PO0。

### 5.7 高级渲染调试

入口：

```text
bash nftables-relay-manager.sh --render > /tmp/po0-relay.conf
```

`--render` 只把计划生成的 relay nftables 配置输出到 stdout，适合重定向和 diff。它不再作为普通菜单入口；日常应用规则仍通过菜单操作，脚本在应用前会自动做 nft -c 预检。

### 5.8 conntrack 学习服务

学习服务只记录成功完成双向转发的公网来源 IP，不自动放行。

安装文件：

```text
/usr/local/sbin/nftables-relay-learn
/etc/systemd/system/nftables-relay-learn.service
```

采集命令：

```bash
conntrack -E
```

学习日志字段：

```text
epoch<TAB>iso_time<TAB>source_ip<TAB>proto<TAB>listen_port<TAB>source_port<TAB>rule_id<TAB>rule_name<TAB>dest_ip<TAB>dest_port
```

默认提升阈值：

```text
/32：至少 3 hits，或至少 2 hits 且观察跨度 >= 10 分钟
/24：至少 2 个不同 IP，或至少 3 hits
/16：至少 2 个不同 /24，或至少 3 hits，加入时必须输入 YES
```

学习日志有大小/行数控制，并生成每日汇总：

```text
LEARN_LOG_MAX_BYTES=52428800
LEARN_LOG_KEEP_LINES=500000
```

### 5.9 源 IP 白名单阻挡日志

白名单外来源访问托管端口时，nft 先写 kernel log，再 drop。采集入口：

```text
管理源 IP 白名单
采集被阻挡访问日志
查看被阻挡访问统计
压缩被阻挡访问日志
清空被阻挡访问日志
```

非交互命令：

```bash
bash nftables-relay-manager.sh --collect-blocked
bash nftables-relay-manager.sh --collect-blocked "24 hours ago"
```

记录文件：

```text
/etc/nftables.d/po0-relay-blocked.tsv
observed_at|src_ip|proto|dport|set_id|raw
```

汇总文件：

```text
/etc/nftables.d/po0-relay-blocked-summary.tsv
src_ip|proto|dport|set_id|count|first_seen|last_seen
```

清理策略：

```text
BLOCK_LOG_MAX_BYTES=10485760
BLOCK_LOG_KEEP_LINES=100000
```

每次采集后自动 compact 并重新生成 summary。超过行数时丢弃最旧记录；超过大小阈值时保留后一半记录。

### 5.10 IPDB 辅助查询

IPDB 是可选能力。脚本使用 `/etc/nftables.d/qqwry.ipdb` 和专用 venv：

```text
/etc/nftables.d/qqwry.ipdb
/etc/nftables.d/po0-ipdb-venv/
```

状态可能是：

```text
未上传
已上传，但缺少 python3
已上传，但缺少 Python 包 ipip-ipdb
可用
```

## 6. 白名单 profile 与兼容性

profile 目录：

```text
/etc/nftables.d/po0-relay-allowlist-profiles/
```

每个用户 profile：

```text
<id>.env
<id>.label.txt
<id>.custom.txt
<id>.sets.tsv
<id>.entries.tsv
<id>.sources.tsv
```

兼容策略：

```text
旧 profile 没有 .sets.tsv：恢复 default public set
旧 profile 没有 .entries.tsv：清空 entries 为表头，不保留当前动态来源
旧 profile 没有 .sources.tsv：清空 sources 为表头，不保留当前 DDNS 来源
旧 custom 文件继续恢复并参与白名单生成
```

应用 profile 前会保存 `_last` 快照，便于撤回。

## 7. 菜单与非交互入口

### 7.1 主菜单

```text
基础操作
  1) 安装 / 初始化 nftables
  2) 手动刷新中转机 IP 缓存
  3) 查看概览与规则列表

规则管理
  4) 新增转发规则
  5) 编辑转发规则
  6) 调整规则顺序
  7) 启用 / 停用规则
  8) 删除转发规则
  9) 导入规则 / 接管现有 nft 规则
 10) 导出规则

系统维护
 11) 修改中转机参数
 12) 管理源 IP 白名单
 13) 诊断 / 自检
 14) 可选开启 BBR + fq
```

### 7.2 非交互入口

```bash
bash nftables-relay-manager.sh --render > /tmp/po0-relay.conf
bash nftables-relay-manager.sh --refresh-ddns
bash nftables-relay-manager.sh --ddns-report-check home.example.com TOKEN
bash nftables-relay-manager.sh --ssh-ip-report iphone 1.2.3.4 TOKEN egern 3600
bash nftables-relay-manager.sh --client-ip-report self-report 1.2.3.4 TOKEN lan-worker 3600
bash nftables-relay-manager.sh --webauth-report webauth 1.2.3.4 user@example.com 2026-06-16T12:00:00Z TOKEN
bash nftables-relay-manager.sh --resource-task-create all
bash nftables-relay-manager.sh --install-resource-task-cron all daily
bash nftables-relay-manager.sh --resource-task-ping TOKEN
bash nftables-relay-manager.sh --collect-blocked "24 hours ago"
bash nftables-relay-manager.sh --learn-service
```

定位：

```text
--learn-service  systemd runner 使用
--render         输出到 stdout，天然适合重定向，不放进交互流程
--refresh-ddns   刷新 DDNS 来源入口的 cron/systemd timer 形式
--ssh-ip-report  Egern / 直接 SSH 上报当前出口 IPv4，写 ssh_report
--client-ip-report LAN Worker self-report server 代报访问设备 IP，写 client_ip
--webauth-report LAN Worker WebAuth 验证后上报访问设备 IP，写 webauth
--resource-task-create 创建一次 iplist/ipdb/all 资源任务
--install-resource-task-cron 安装 PO0 端定时创建资源任务的 cron
--collect-blocked 采集阻挡日志入口的 cron/systemd timer 形式
```

## 8. 诊断、备份与接管

诊断菜单检查：

```text
nftables 是否安装
IPv4 forwarding 是否开启
当前配置文件是否能通过 nft -c -f
托管规则数量和启用状态
源 IP 白名单状态
学习服务状态
blocked 日志数量和 summary 行数
是否存在脚本未管理但正在生效的 DNAT 规则
```

备份覆盖：

```text
po0-relay.conf
po0-relay.env
po0-relay.rules
po0-relay-src-allowlist.txt
po0-relay-custom-src-allowlist.txt
po0-relay-allowlist-sets.tsv
po0-relay-allowlist-entries.tsv
po0-relay-allowlist-sources.tsv
po0-relay-blocked.tsv
po0-relay-blocked-summary.tsv
```

导入规则入口可以从现有 nft 配置或运行中 ruleset 尝试提取 DNAT 规则，并转成脚本托管规则。接管前会做备份，导出入口会保存当前托管配置，便于迁移或回滚。

## 9. 当前实现状态

```text
白名单 set 配置格式：已实现
po0_src_default 公共集渲染：已实现
entries.tsv 标准来源模型：已实现
旧 custom 文件兼容并镜像 manual entries：已实现
SSH 当前来源临时 /32：已实现
DDNS 来源菜单和刷新应用：已实现
DDNS 外部解析上报：已实现
Egern SSH report 当前出口 IPv4 上报：已实现，支持单 PO0 和多 PO0
LAN Worker WebAuth 上报：已实现，HTTP 入口只跑在 LAN Worker
attack mode 自动来源冻结：已实现
兼容检查与 legacy 清理入口：已实现
源白名单 block 日志、清理和 summary：已实现
PO0 HTTP / Secret URL 控制面：不实现
高级学习模式：Pending
一个 PO0 控制另一个 PO0：Pending
```

## 10. Roadmap

### 10.1 PO0 HTTP / Secret URL 控制面（不实现）

PO0 不开放普通 HTTP/HTTPS 控制面，也不实现“打开隐藏链接就把当前 IP 加白”的 Secret URL。对应需求改为两条安全路径：

```text
移动设备：Egern SSH report 通过 SSH 调 --ssh-ip-report
浏览器认证：Cloudflare Access -> cloudflared tunnel -> LAN Worker WebAuth -> SSH 调 --webauth-report
```

仍不落地的内容：

```text
PO0 上直接监听 HTTP/WebAuth
PO0 上提供 Secret URL
让公网客户端通过 HTTP 直接改 PO0 白名单
```

保留目标：

```text
可信设备动态维护严格 /32
PO0 只接受 SSH/本地命令入口
source_type=client_ip / ssh_report / webauth
ssh_report 只用于 Egern / 直接 SSH 上报
更新 nftables 前必须 render + nft -c
失败不能清空旧有效来源
```

### 10.2 高级学习模式（Pending）

目标是在基础 `ASSURED + 次数 + 观察跨度` 之外，结合连接持续时间、包数和字节数判断来源 IP 是否更可信。仍然不自动放行，只用于提高候选质量。

前提：

```text
net.netfilter.nf_conntrack_acct=1
```

建议新增日志：

```text
/etc/nftables.d/po0-relay-learn-effective.tsv
```

候选提升可以优先使用 effective 日志；高级模式关闭时继续读取基础日志。

### 10.3 通过一个 PO0 控制另一个 PO0（Pending）

目标是在两台 PO0 内网互通时，让一台 PO0 通过另一台 PO0 的内网 IP 执行白名单 profile 同步和应用。

推荐边界：

```text
以 profile 包为同步边界
scp 上传 profile 包
ssh 调用被控方非交互导入/应用入口
被控方本地完成 nft -c 和 reload
失败不覆盖当前白名单
操作写入审计日志
```

不建议直接远程拼接修改命令。
