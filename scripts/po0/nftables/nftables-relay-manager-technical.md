# nftables relay manager 说明与技术文档

本文先用普通语言说明 `nftables-relay-manager.sh` 是做什么的、平时怎么用、遇到问题怎么看；后半部分再记录技术结构、文件格式和 roadmap。非技术读者可以先读第 0 章到第 2 章，维护脚本或排查细节时再看后面的技术章节。

## 0. 先给非技术读者的版本

一句话：这个脚本是在 PO0 中转机上管理“哪些端口转发到哪里，以及哪些来源 IP 可以访问这些转发端口”的工具。

可以把它理解成一个中转机管家：

```text
转发规则：告诉中转机，外面访问哪个端口，要转到内网或目标机器的哪个地址。
白名单：告诉中转机，哪些来源 IP 被允许访问这些转发端口。
动态来源：家里宽带、手机网络、当前 SSH 登录地址这类会变化的来源 IP。
预览检查：真正应用前，先看脚本准备生成什么规则，避免把自己锁在外面。
日志：记录哪些来源 IP 被白名单挡掉，方便以后判断要不要放行。
```

日常最常用的是交互菜单：

```bash
bash nftables-relay-manager.sh
```

常见操作：

```text
首次部署：1) 安装 / 初始化 nftables
新增或修改转发：4) / 5)
管理来源白名单：12)
看当前状态和自检：3) 或 13)
应用前预览：15)
```

如果你只是想“让我当前 SSH 这个公网 IP 临时能访问转发端口”，进入：

```text
12) 管理源 IP 白名单
9) 从当前 SSH 来源临时加入 default /32
```

如果你用 DDNS，比如 `home.example.com` 永远指向家里的公网 IP，流程是：

```text
客户端或路由器负责更新 DNS
推荐由 iOS/Egern、内网机器或路由器解析这个域名
外部机器通过 SSH 调 PO0 的 --ddns-report 上报解析结果
PO0 本机解析只作为兜底
成功后把得到的公网 IP 写入白名单
```

如果有人访问被白名单保护的端口但没有被允许，脚本会记录“被挡住的来源 IP”。你可以在白名单菜单里采集和查看统计：

```text
12) 管理源 IP 白名单
11) 采集被阻挡访问日志
12) 查看被阻挡访问统计
13) 压缩被阻挡访问日志
```

最重要的安全原则：

```text
不要手动乱改 /etc/nftables.d 里的生成文件，尽量通过菜单操作。
启用白名单前先用“预览 / 试运行”看一眼。
DDNS 或动态来源解析失败时，脚本会保留旧结果，不会立刻清空白名单。
DDNS 外部上报建议使用菜单生成的 token；如果 token 文件存在，上报命令必须携带正确 token。
学习服务只给候选建议，不会自动放行陌生 IP。
URL / 设备上报还没实现，先不要按 HTTP 接口那种思路部署。

资源更新采用另一套“PO0 任务队列 + 内网客户端主动领取”协议，不属于 URL 白名单上报。PO0 只允许 `iplist` 和 `ipdb` 两种固定任务，不能通过该接口发送任意 Shell 命令。
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

预览 / 试运行
  只预览和检查，不真正应用规则。
```

## 0.2 出问题时先看哪里

如果“访问不了转发端口”，先按这个顺序看：

```text
1. 主菜单 3) 查看概览与规则列表
2. 主菜单 15) 预览 / 试运行
3. 主菜单 13) 诊断 / 自检
4. 白名单菜单 11) 采集被阻挡访问日志
5. 白名单菜单 12) 查看被阻挡访问统计，确认自己的公网 IP 是否被挡住
```

如果“DDNS 没生效”，先确认：

```text
域名在外部 DNS 已经解析到正确公网 IP
po0-relay-allowlist-sources.tsv 里 source enabled=1
运行过“刷新 DDNS 来源”
“预览 / 试运行”里能看到 DDNS 条目进入白名单
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

脚本仍以交互菜单为主。少量非交互参数用于 systemd runner、预览、重定向渲染和定时维护。

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
SRC_ALLOWLIST_MODE         region / custom / region_custom
SRC_ALLOWLIST_REGION_IDS   已选地区 ID
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
url_report
```

当前已进入实际生成链路的来源：

```text
manual       菜单添加的手动 CIDR，同时继续兼容旧 custom 文件
ssh_temp     当前 SSH 来源临时 /32
ddns         DDNS 来源刷新结果
region       旧地区白名单文件直接进入缓存，不逐条写 entries
```

过期 entries 保留作审计，但生成有效白名单缓存时跳过。

### 3.5 白名单 sources 模型

`po0-relay-allowlist-sources.tsv`：

```text
set_id|source_type|name|value|enabled|ttl_seconds|last_resolved_at|last_result
```

当前 `source_type` 支持 `ddns`：

```text
default|ddns|home|home.example.com|1|300||
```

`last_result` 的含义：

```text
report:<ip_csv>      iOS/Egern、内网机器或路由器解析后，通过 --ddns-report 上报
local:<ip_csv>       PO0 本机 DNS 兜底解析
ERROR resolve_failed 本次没有拿到可用公网 IPv4
```

DDNS 来源可以通过菜单添加、删除、启用/停用、测试解析、刷新应用和生成外部上报 token。外部上报成功时会立即把公网 IPv4 写为 `ddns` entries，并重建应用白名单；刷新时优先复用 TTL 内的 `report:` 结果，过期或没有外部上报时才用 PO0 本机 DNS 兜底。失败时保留旧 entries，不清空已生效结果。停用或删除 DDNS 来源时，会同步移除它对应的旧 `ddns` entries。

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

现在 `write_nft_conf` 和 `build_src_allowlist_cache` 支持可选输出路径，因此 `--preview` / `--render` 可以写临时文件而不触碰真实配置。

### 4.3 源白名单生成

白名单缓存生成顺序：

```text
1. region 或 region_custom：读取 iplist 离线包的地区 CIDR。
2. custom 或 region_custom：读取 entries.tsv 中 default set 的未过期条目。
3. custom 或 region_custom：继续读取旧 custom 文件。
4. sort -u 去重。
5. 原子替换 po0-relay-src-allowlist.txt。
```

失败条件：

```text
地区模式未选择地区
引用的地区文件缺失
地区文件存在非法 CIDR
custom 模式下没有任何有效 CIDR
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

这一章按功能解释脚本。普通读者可以只看自己关心的模块，例如 SSH 临时来源、DDNS、预览 / 试运行、被阻挡访问日志。

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
主菜单 12) 管理源 IP 白名单
9) 从当前 SSH 来源临时加入 default /32
```

行为：

```text
从 SSH_CONNECTION 读取客户端公网 IPv4
只加入 /32，不自动放大到 /24
默认过期 24 小时，可输入 1-720 小时
写 entries.tsv：source_type=ssh_temp，source_value=SSH_CONNECTION
保存前创建 _last 快照
写入后自动启用 custom 或 region_custom 白名单路径
重新 render 并应用
```

### 5.6 DDNS 来源

入口：

```text
主菜单 12) 管理源 IP 白名单
10) 管理 DDNS 来源
 1) 查看 DDNS 来源和上报统计
 2) 添加 DDNS 来源
 3) 编辑 DDNS 来源
 4) 删除 DDNS 来源
 5) 启用 / 停用 DDNS 来源
 6) 测试解析 DDNS 来源
 7) 刷新并应用已启用 DDNS 来源
 8) 显示 / 生成外部上报 Token
```

非交互命令：

```bash
bash nftables-relay-manager.sh --refresh-ddns
bash nftables-relay-manager.sh --ddns-report home.example.com 1.2.3.4,5.6.7.8 TOKEN
```

外部解析上报逻辑：

```text
外部机器负责解析 DDNS 域名
外部机器通过 SSH 调 PO0：--ddns-report <名称或域名> <公网IPv4[,公网IPv4...]> [token]
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
如果 last_result 是 TTL 内的 report:<ip_csv>，优先使用外部上报结果
否则 PO0 本机解析 A 记录作为兜底
只接受公网 IPv4
成功后替换该 set_id + ddns + 域名 对应 entries
外部结果写 report:<ip_csv>，本机兜底写 local:<ip_csv>
失败时保留旧 entries
停用或删除来源时移除对应旧 entries
刷新或移除后重建并应用白名单
```

客户端实现：

```text
clients/egern/PO0-DDNS-Report.yaml
clients/egern/po0-ddns-report.js
scripts/po0/nftables/tools/po0-lan-client.sh
```

Egern 方案在 iOS 上定时用 DoH 解析域名，然后通过 Egern 的 SSH API 调 PO0。`DDNS_NAME` 可空，默认直接用 `DDNS_DOMAIN` 作为 PO0 的 `--ddns-report` key。

通用内网协作客户端 `po0-lan-client.sh` 适合 Linux/macOS/OpenWrt 机器。它默认直接用域名作为上报 key，不需要额外 `DDNS_NAME`。直接运行脚本会进入中文菜单：

```bash
bash tools/po0-lan-client.sh
```

菜单会管理本机客户端的 PO0 目标：查看、添加、编辑、删除、启用/停用，执行 DDNS 上报和资源任务轮询，并管理 cron。一个配置文件可以放多台 PO0/VPS。

该客户端同时承担资源更新 worker。目标配置末尾新增 `resource_token` 字段，旧配置没有该字段时按“未启用资源任务”处理。菜单可以直接编辑已有目标并补填 Token。

资源任务流程：

```text
PO0 菜单创建 pending 任务
内网客户端通过 --resource-task-claim 领取任务
客户端构建 iplist.tar.gz 或下载 qqwry.ipdb
客户端计算 SHA-256 和文件大小
客户端通过 SCP 上传到 PO0 返回的固定收件路径
客户端调用 --resource-task-complete
PO0 校验、原子导入并把任务标记为 success/failed
```

PO0 非交互接口：

```bash
bash nftables-relay-manager.sh --resource-task-claim WORKER_ID TOKEN
bash nftables-relay-manager.sh --resource-task-complete TASK_ID WORKER_ID SHA256 SIZE TOKEN
bash nftables-relay-manager.sh --resource-task-fail TASK_ID WORKER_ID REASON TOKEN
```

这些接口主要供客户端调用。任务领取和状态修改使用 `flock`（系统提供时）串行化；上传路径由 PO0 生成，客户端不能指定生产文件路径。资源任务使用独立 Token，不复用 DDNS 上报 Token。

`qqwry.ipdb` 默认下载源：

```text
https://raw.githubusercontent.com/nmgliangwei/qqwry.ipdb/main/qqwry.ipdb
```

PO0 的基础 IPDB 格式校验使用常见的 `od`、`dd`、`grep` 检查文件头、元数据长度、关键字段和数据区，不要求预先安装 Python 包。系统已有 Python 时会追加严格 JSON 元数据校验；真正查询归属地仍需要菜单中的 `ipip-ipdb` 解析依赖。

客户端的 `resource-stats.tsv` 每个 PO0 端点只保留一行累计统计，不会按任务无限追加。PO0 的任务文件保留全部活动任务和最近 500 条终态记录，管理员可以在菜单中查看结果，或把失败/执行中的任务重新排队。

### 5.7 预览 / 试运行

入口：

```text
主菜单 15) 预览 / 试运行
bash nftables-relay-manager.sh --preview
bash nftables-relay-manager.sh --render > /tmp/po0-relay.conf
```

`--preview` 输出：

```text
托管规则数量
中转模式和入站防火墙状态
白名单模式
sets 摘要
sources 摘要
entries 来源统计
渲染临时文件路径
allowlist cache CIDR 数量
nft -c 结果（系统有 nft 时）
```

`--render` 只把计划生成的 relay nftables 配置输出到 stdout，适合重定向和 diff。

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
主菜单 12) 管理源 IP 白名单
11) 采集被阻挡访问日志
12) 查看被阻挡访问统计
13) 压缩被阻挡访问日志
14) 清空被阻挡访问日志
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
 15) 预览 / 试运行
```

### 7.2 非交互入口

```bash
bash nftables-relay-manager.sh --preview
bash nftables-relay-manager.sh --render > /tmp/po0-relay.conf
bash nftables-relay-manager.sh --refresh-ddns
bash nftables-relay-manager.sh --collect-blocked "24 hours ago"
bash nftables-relay-manager.sh --learn-service
```

定位：

```text
--learn-service  systemd runner 使用
--render         输出到 stdout，天然适合重定向，不放进交互流程
--preview        主菜单已有入口，参数形式适合自动化检查
--refresh-ddns   白名单菜单已有入口，参数形式适合 cron/systemd timer
--collect-blocked 白名单菜单已有入口，参数形式适合 cron/systemd timer
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
预览 / 试运行：已实现
DDNS 来源菜单和刷新应用：已实现
DDNS 外部解析上报：已实现
源白名单 block 日志、清理和 summary：已实现
URL / 设备上报：Pending
高级学习模式：Pending
一个 PO0 控制另一个 PO0：Pending
```

## 10. Roadmap

### 10.1 URL / 设备上报动态 /32 白名单（Pending）

该功能暂不实现。最新约束：不能按普通 HTTP/HTTPS 控制面设计；更合适的方向是经过 PO0 对端的 RFC/返回通道完成，让 PO0 从该返回路径识别可信设备当前公网 IPv4，最好不要依赖普通 http / tls 流量返回。

需要重新设计：

```text
PO0 对端 RFC/返回通道的具体协议形态
如何从返回通道可靠获得设备公网 IPv4
如何认证设备身份，同时避免暴露普通 HTTP/TLS 控制接口
如何写入 entries.tsv 的 url_report 来源
是否需要 token、一次性挑战、时间窗口或签名
失败时是否保留旧 url_report entries
上报成功后立即 reload 还是批量延迟 reload
如何在预览 / 试运行中展示待更新设备和将生成的 /32
```

保留目标：

```text
可信设备动态维护严格 /32
服务端不接受客户端提交的 IP 字段
source_type=url_report
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
