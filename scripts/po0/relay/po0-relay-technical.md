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

脚本版本统一采用 `YYYY.MM.DD+build.N` 混合版本格式；正式 PO0 Release asset 的五个脚本版本必须与 release tag 尾号一致，例如 `po0-v2026.07.01.5` 对应 `2026.07.01+build.5`。PO0 manager 的 `--version` 会像 LAN Worker 一样单独显示 build 构建标识。

常见操作：

```text
首次部署：部署与概览 -> 安装 / 初始化 nftables
新增或修改转发：转发规则 -> 新增 / 编辑规则
管理来源白名单：来源、客户端与资源 -> 源 IP 白名单
看当前状态和自检：部署与概览 -> 查看概览，或系统维护 -> 诊断 / 自检
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

如果有人访问被白名单保护的端口但没有被允许，脚本会记录“被挡住的来源 IP”。你可以在“管理源 IP 白名单 -> 被阻挡访问日志”里采集和查看统计：

```text
管理源 IP 白名单
被阻挡访问日志
查看被阻挡访问统计
采集最近 1 小时日志
按自定义 since 采集日志
压缩日志并刷新统计
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
PO0 manager HTTP 更新镜像只允许跑在 LAN Worker 上，只返回固定 manager 脚本；PO0 校验 resource token HMAC、sha256、size 和 bash -n 后才安装。

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
  动态域名。客户端或 LAN Worker 解析 DDNS 域名并通过 --ddns-report 上报；PO0 只复用 TTL 内的上报结果，不做本地 DNS 解析。

--render
  高级调试命令，只把 relay nftables 配置输出到 stdout，不应用规则。
```

## 0.2 出问题时先看哪里

如果“访问不了转发端口”，先按这个顺序看：

```text
1. 部署与概览 -> 查看概览与规则列表
2. 系统维护 -> 诊断 / 自检
3. 管理源 IP 白名单 -> 来源/IP 明细
4. 管理源 IP 白名单 -> 被阻挡访问日志 -> 采集最近 1 小时日志
5. 管理源 IP 白名单 -> 被阻挡访问日志 -> 查看被阻挡访问统计，确认自己的公网 IP 是否被挡住
```

如果“DDNS 没生效”，先确认：

```text
域名在外部 DNS 已经解析到正确公网 IP
po0-relay-allowlist-sources.tsv 里 source enabled=1
LAN Worker / 外部脚本已经通过 --ddns-report 上报
运行过“刷新 DDNS 来源”或外部上报已触发重建应用
```

下面开始是维护者和排障用的技术细节。

## 0.3 发布与构建边界

PO0 nftables 五个可执行脚本的正式发布渠道是 GitHub Release asset。旧 manager、LAN Worker 和 self-report raw URLs are disabled，不再作为兼容入口；新安装、自更新和 LAN Worker manager mirror 都应使用 Release asset 或显式 override URL。Egern canonical raw path、Egern legacy compatibility path、离线 iplist 构建器、外部 ipdb/iplist 数据源和未纳入本阶段的通用 VPS 工具 raw URL 是白名单。

`tools/po0/build-po0-assets.ps1` / `.sh` 按 `tools/po0/manifests/*.txt` 拼接 manager、LAN Worker、Linux self-report、macOS self-report 和 Windows PowerShell self-report 五个 release staging 单文件。构建必须显式控制编码和 LF：Bash/manifest/checksum 使用 UTF-8 no BOM，含中文的 Windows PowerShell `.ps1` 使用 UTF-8 BOM，避免 Windows PowerShell 5 按系统代码页解析失败。Release tag `po0-vYYYY.MM.DD.N` 上传五个脚本和 `checksums.txt`。Release workflow 先创建 draft，上传完整 asset set，下载回校验 checksum 后再 publish/latest；已存在 draft 可补齐缺失 asset，但已发布 release 只校验不修改，缺失或 checksum 不一致都必须打新 tag。CI/release 以 `tools/po0/check-po0-assets.sh` 为 authority；`tools/po0/check-po0-assets.ps1` 是 Windows 本地等价验证入口。两个检查入口都会确认本批次五个 asset 版本与预期 tag 对齐，并对三端 PO0 Outbound IP Report asset 做 SSID 本地跳过 release gate：必须有 canonical `PO0_OUTBOUND_IP_REPORT_*SSID` 环境入口、CLI/配置入口、HTTP 上报前 guard、跳过日志摘要，并禁止新增 `PO0_SELF_REPORT_*SSID` 或 `SELF_REPORT_*SSID` legacy alias。
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
/etc/nftables.d/po0-relay-dynamic-state.lock         动态来源 allowlist / 上报统计本地锁
/etc/nftables.d/po0-relay-allowlist-profiles/        白名单配置档案
```

动态来源的本地读改写使用 `flock`（系统提供时）串行化，覆盖 DDNS report/refresh、Self-report、WebAuth 和 Egern/SSH report 对 allowlist entries、DDNS sources 和 report stats 的更新。锁只包本地 TSV 读改写和临时文件原子替换，不包 SSH、HTTP 下载、交互输入或 nftables 应用。

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
/etc/nftables.d/po0-relay-resource-tasks.lock        资源任务队列本地锁
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
NODE_NAME                  本机名称 / 导出前缀，可空
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
default|Default public allowlist|1|public|*|manual,ddns,client_ip,ssh_report,webauth,learned|...
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

动态来源按 `source_type + source-id` 分组裁剪；底层 `entries.tsv` 的 `source_value` 就是 source-id。`ddns`、`client_ip`、`ssh_report`、`webauth` 每组默认最多保留最近 `12` 个有效 CIDR，`/32` 和 `/24` 都各算 1 条并共享同一个上限。过期 entries 保留作审计，但生成有效白名单缓存时跳过。`source-id` 是分组、续期和裁剪的稳定 key；`identity` 只做备注和审计。

### 3.5 白名单 sources 模型

`po0-relay-allowlist-sources.tsv`：

```text
set_id|source_type|name|value|enabled|ttl_seconds|last_resolved_at|last_result
```

当前 `po0-relay-allowlist-sources.tsv` 只保存 DDNS 来源定义：

```text
default|ddns|home|home.example.com|1|43200||
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

地区白名单数据来自 `metowolf/iplist`，构建入口固定为：

```text
https://github.com/metowolf/iplist
https://raw.githubusercontent.com/metowolf/iplist/refs/heads/master/docs/cncity.md
```

构建脚本只使用 `cncity.md` 里指向 `data/cncity/*.txt` 的链接；`data/country/*` 或其它目录会被忽略。这样生成的包只覆盖国内省市级地区白名单，和管理器菜单里的“地区白名单”语义保持一致。

离线包默认输出为 `~/Desktop/iplist.tar.gz`，包内只包含：

```text
docs/cncity.md
data/cncity/*.txt
```

导入后会在 VPS 上生成：

```text
/etc/nftables.d/po0-iplist/docs/cncity.md
/etc/nftables.d/po0-iplist/data/cncity/*.txt
/etc/nftables.d/po0-iplist/manifest.tsv
```

构建脚本：

```text
scripts/po0/nftables/tools/build-iplist-package.sh
scripts/po0/nftables/tools/build-iplist-package.ps1
```

Bash 版读取第 1 个参数作为输出路径，读取 `IPLIST_JOBS` 或第 2 个参数作为并发数，默认并发 8。它下载 `docs/cncity.md`，提取 `.txt` URL，只保留 `data/cncity/*.txt`，再用 `xargs -0 -n 4 -P` 并发下载并通过 `tar -czf` 打包。

PowerShell 版读取 `-OutFile` 和 `-ThrottleLimit`，默认并发 8；用 `Invoke-WebRequest` 下载索引，用 `Start-Job` 并发下载数据，最后调用系统 `tar` 打包。Windows 10/11 通常内置 BSD tar；如果缺失，需要先安装 tar 或使用 Bash 版本。

路径过滤逻辑：

```text
*/iplist/data/cncity/*.txt  -> data/cncity/<file>
*/data/cncity/*.txt         -> data/cncity/<file>
其它 URL                      -> 跳过
```

`manifest.tsv` 不由构建脚本写入，而是在 `nftables-relay-manager.sh` 导入包时根据 `docs/cncity.md` 重新解析生成。`build_iplist_manifest_for_dir()` 从表格列中读取地区名称和数据 URL，生成：

```text
id<TAB>地区名称<TAB>相对路径<TAB>原始 URL
```

其中 `id` 来自数据文件名去掉 `.txt` 后的值，只保留 `A-Za-z0-9._-`，其它字符替换为 `_`。地区选择菜单实际保存的就是这些 `id`。

导入入口：

```text
菜单路径：来源、客户端与资源 -> 11) 源 IP 白名单
19) 导入 / 刷新 iplist 离线包
```

导入逻辑会校验包文件和 `tar`，解压 `.tar.gz` / `.tgz` / `.tar` 到临时目录，要求包根目录存在 `docs/cncity.md`，重建 `manifest.tsv`，校验 manifest 里的每个 `data/cncity/*.txt` 都存在，成功后才原子替换当前 `/etc/nftables.d/po0-iplist`；如果替换失败，会尽量恢复旧目录。

构建脚本只下载并打包数据，不修改 nftables，也不接触 VPS 配置。真正影响放行范围的是管理器导入后再执行的白名单重建流程：

```text
build_src_allowlist_cache()
write_nft_allowlist_set()
nft -c -f 预检
reload_managed_rules 或 apply_full_config
```

因此，更新离线包后仍需要在 VPS 端导入并重新应用白名单，新的地区 CIDR 才会进入 nft set。

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
如果同一 /32 已存在，会刷新 created_at、note 和 expires_at，不保留过期旧记录
保存前创建 _last 快照
写入后如果当前模式未包含 ssh_temp，会切换为高级自选来源并保留原来源组合再追加 ssh_temp
重新 render 并应用
```

### 5.6 DDNS 来源

入口：

```text
管理源 IP 白名单 -> 动态来源与客户端 -> 管理 DDNS 来源
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
scripts/po0/relay/lan-worker/src/
scripts/po0/relay/self-report/linux/src/      (tools/po0/manifests/self-report-linux.txt)
scripts/po0/relay/self-report/macos/src/      (tools/po0/manifests/self-report-macos.txt)
scripts/po0/relay/self-report/windows/src/    (tools/po0/manifests/self-report-windows.txt)
```

`po0-lan-client.sh` 按 Debian/Linux VPS 维护，不按 OpenWrt/BusyBox 约束设计。它可以同时做 DDNS resolver 上报和资源任务轮询领取，也可以只做资源任务 Worker。DDNS resolver 上报周期和资源任务领取周期不是一回事：DDNS 间隔按 PO0 端 DDNS 来源 TTL 设置；资源任务创建周期只在 PO0 端设置，LAN Worker 本机 cron 只负责定期检查并领取 PO0 已创建的 pending 任务。同一个 managed cron block 里最多写两条计划，分别调用 `--run-ddns` 和 `--run-resource`。推荐先用交互向导；向导会通过 `ssh -o BatchMode=yes` 检查到 PO0 的密钥 SSH，密钥 SSH 可用时自动读取所需 token，写入本机目标配置，安装本机 `po0-lan-client` 命令，并按选择安装 Worker 轮询器 / systemd 服务。首次向导里的 PO0 SSH 地址一次只填一个；多个 PO0 目标后续用菜单添加：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-lan-client.sh | bash
po0-lan-client --menu
po0-lan-client --run
po0-lan-client --probe
po0-lan-client --wizard
```

SSH 认证按向导选择：系统默认 SSH 配置/agent、已有私钥路径，或粘贴专用私钥。粘贴的私钥会保存到本机配置目录并设置 600 权限。`额外 SSH 参数` 是传给 `ssh` 的选项，例如 `-J jump-host` 或 `-o StrictHostKeyChecking=accept-new`，不是私钥短语；带短语的私钥需要 `ssh-agent`。向导会自动补 `-o BatchMode=yes`，避免 cron/service 卡在交互输入。菜单里的 `PO0 目标`、`SSH 私钥 / 参数`、`目标 Token`、`Self-report / WebAuth TTL` 分开管理目标、SSH、Token 和 TTL；`资源任务` 与 `DDNS resolver` 是分开的执行入口，资源任务在前。

如果旧版本安装后没有 `po0-lan-client` 命令，可手动补装：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-lan-client.sh -o /usr/local/sbin/po0-lan-client
chmod 755 /usr/local/sbin/po0-lan-client
/usr/local/sbin/po0-lan-client --menu
```

自动化场景仍可使用公开仓库一键部署命令：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-lan-client.sh | bash -s -- --bootstrap --po0-host <PO0_HOST> --po0-script /root/nftables-relay-manager.sh --source-key home --ddns-domain home.example.com --token <DDNS_TOKEN> --resource-token <RESOURCE_TOKEN> --ddns-interval-seconds 3600 --install-cron
```

PO0 Outbound IP Report client 适合运行在访问设备上：它检测自身当前出口公网 IPv4，并通过 `https://<SELF_REPORT_DOMAIN>/report` 上报给 LAN Worker self-report server；LAN Worker 的 Caddy HTTPS 入口反代到本机后端，再通过 SSH 调 PO0。Linux/OpenWrt 客户端菜单按 `[0-9]` 管理；macOS 和 Windows 客户端因新增通知 / 静默模式开关，菜单按 `[0-10]` 管理。三个客户端的 `1) 配置并保存上报参数` 只持久写入本地配置文件，不安装定时任务；`2) 立即上报一次` 读取参数或已保存配置；`3) 安装 / 更新定时上报` 读取已保存配置并创建 cron / launchd / Windows 计划任务；`4) 暂停 / 恢复定时上报` 只影响自动任务，不影响手动立即上报。macOS 的 `6) 通知 / 静默模式` 和 Windows 的 `6) Windows 通知 / 静默模式` 会保存通知偏好，并在定时任务已安装时刷新实际 launchd / 计划任务启动参数。Linux/OpenWrt 的 `8) 从 GitHub 更新脚本` / `9) 卸载本客户端` 与 macOS、Windows 的 `9) 从 GitHub 更新脚本` / `10) 卸载本客户端` 语义一致，都会更新本机脚本或删除本脚本管理的定时任务和安装脚本；配置与日志默认保留，可在确认后一起删除。

Linux/OpenWrt 客户端未传 `--source-id` / `--identity` 时，会用 hostname + machine-id/MAC 生成默认 Source ID，并用设备名作为 Identity；显式参数、环境变量和已保存配置优先。首次进入菜单：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report.sh | bash
```

Linux/OpenWrt 首次保存默认配置并打开菜单：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report.sh | bash -s -- --save-config --menu
```

Linux/OpenWrt 非交互保存配置，不安装 cron，也不保证安装 `po0-outbound-ip-report` 命令：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report.sh | bash -s -- --worker-url https://<SELF_REPORT_DOMAIN>/report --secret <SELF_REPORT_SECRET> --save-config
```

Linux/OpenWrt 非交互立即上报一次；不传 `--worker-url` 等参数时会读取已保存配置：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report.sh | bash -s -- --worker-url https://<SELF_REPORT_DOMAIN>/report --secret <SELF_REPORT_SECRET>
```

Linux/OpenWrt 非交互安装 cron 时，默认和示例推荐每 `3600` 秒上报一次；`--interval-seconds N` 必须是 60 的倍数，旧 `--install-cron N` 兼容分钟参数仍可用。安装时会保存配置并安装本机 `po0-outbound-ip-report` 命令；cron 后续只引用配置文件，不再把 token 展开写入 cron 命令行：

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

Linux/OpenWrt 查看本脚本管理的 cron 计划：

```bash
crontab -l | sed -n '/# PO0_OUTBOUND_IP_REPORT_BEGIN/,/# PO0_OUTBOUND_IP_REPORT_END/p'
```

Linux/OpenWrt 查看脚本内置定时状态：

```bash
po0-outbound-ip-report --schedule-status
```

Linux/OpenWrt 暂停 / 恢复本脚本管理的定时上报：

```bash
po0-outbound-ip-report --pause-schedule
po0-outbound-ip-report --resume-schedule
```

macOS 客户端使用专用 Release asset，优先安装 launchd 定时任务；普通用户写 `~/Library/LaunchAgents/fr.schweppes.po0-outbound-ip-report.plist`，root 写 `/Library/LaunchDaemons/fr.schweppes.po0-outbound-ip-report.plist` 并使用 `system` launchd domain，launchd 不可用但存在 `crontab` 时回退到 cron。首次保存默认配置并打开菜单：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report-macos.sh | bash -s -- --save-config --menu
```

macOS 非交互安装 / 更新 launchd 定时上报：

```bash
curl -fsSL https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report-macos.sh | bash -s -- --worker-url https://<SELF_REPORT_DOMAIN>/report --secret <SELF_REPORT_SECRET> --interval-seconds 3600 --install-launchd
```

macOS 默认静默；`--notify` 会把通知偏好写入配置并在 launchd `ProgramArguments` 中追加 `--notify`，上报成功或失败后通过 `osascript display notification` 调用系统通知中心。通知不可用、被系统权限或专注模式抑制时只写 `/tmp/po0-outbound-ip-report.log`，不改变上报退出码。恢复静默需要用 `--no-notify --install-launchd` 或菜单通知开关刷新 launchd plist。

Linux/OpenWrt/macOS 查看最近 PO0 Outbound IP Report 定时任务输出：

```bash
tail -n 40 /tmp/po0-outbound-ip-report.log
```

Windows PowerShell 默认按普通用户安装和运行，路径在 `%LOCALAPPDATA%\PO0`；只有用管理员 PowerShell 安装时才会改用 `%ProgramData%\PO0`，日常不要混用两个权限环境。交互式运行默认进入菜单，推荐显式加 `-Menu`：

```powershell
$script="$env:TEMP\po0-outbound-ip-report.ps1"; irm -UseBasicParsing 'https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report.ps1' -OutFile $script -TimeoutSec 120; powershell -ExecutionPolicy Bypass -File $script -Menu
```

Windows 旧版曾把固定脚本写到 `po0-self-report.ps1`。新版脚本如果从旧路径启动，会先复制到 `%LOCALAPPDATA%\PO0\po0-outbound-ip-report.ps1` 或 `%ProgramData%\PO0\po0-outbound-ip-report.ps1`，再刷新已有计划任务的隐藏 launcher；菜单场景会重新打开 canonical 脚本。更新或旧路径自愈成功后会迁移默认旧配置、日志、IP 探测 state 和旧计划任务，并删除默认旧 `po0-self-report.ps1` / `po0-self-report-task.vbs` 残留。旧路径只作为迁移、漂移提示和卸载目标，不再作为默认安装入口。

Windows PowerShell 非交互保存配置，不安装计划任务，也不保证安装固定路径脚本；`-SourceId` 和 `-Identity` 推荐填设备名，避免多台设备都混到同一来源：

```powershell
$script="$env:TEMP\po0-outbound-ip-report.ps1"; irm -UseBasicParsing 'https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report.ps1' -OutFile $script -TimeoutSec 120; powershell -ExecutionPolicy Bypass -File $script -WorkerUrl "https://<SELF_REPORT_DOMAIN>/report" -SourceId $env:COMPUTERNAME -Identity $env:COMPUTERNAME -Secret "<SELF_REPORT_SECRET>" -SaveConfig
```

Windows PowerShell 非交互立即上报一次；不传 `-WorkerUrl` 等参数时会读取已保存配置。显式 `-RunOnce` 可避免交互环境下误进菜单：

```powershell
$script="$env:TEMP\po0-outbound-ip-report.ps1"; irm -UseBasicParsing 'https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report.ps1' -OutFile $script -TimeoutSec 120; powershell -ExecutionPolicy Bypass -File $script -WorkerUrl "https://<SELF_REPORT_DOMAIN>/report" -SourceId $env:COMPUTERNAME -Identity $env:COMPUTERNAME -Secret "<SELF_REPORT_SECRET>" -RunOnce
```

Windows PowerShell 非交互安装 / 更新计划任务，默认每 `3600` 秒上报一次。安装 / 更新计划任务时建议从 `$env:TEMP` 下载脚本再运行，让脚本覆盖安装到普通用户默认路径 `%LOCALAPPDATA%\PO0\po0-outbound-ip-report.ps1`。管理员安装时才会使用 `%ProgramData%\PO0\po0-outbound-ip-report.ps1`。安装时会保存配置；计划任务后续只引用配置文件，不再把 token 展开写入计划任务参数：

```powershell
$script="$env:TEMP\po0-outbound-ip-report.ps1"; irm -UseBasicParsing 'https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/po0-outbound-ip-report.ps1' -OutFile $script -TimeoutSec 120; powershell -ExecutionPolicy Bypass -File $script -WorkerUrl "https://<SELF_REPORT_DOMAIN>/report" -SourceId $env:COMPUTERNAME -Identity $env:COMPUTERNAME -Secret "<SELF_REPORT_SECRET>" -InstallTask -IntervalSeconds 3600
```

`<SELF_REPORT_SECRET>` 只替换为 secret 本身，不要带 `secret:` 或中文冒号前缀。

保存配置后，如果本机已经通过菜单更新或安装计划任务落盘了脚本，普通用户从固定路径再次运行：

```powershell
$client=Join-Path $env:LOCALAPPDATA 'PO0\po0-outbound-ip-report.ps1'; powershell -ExecutionPolicy Bypass -File $client -Menu
```

```powershell
$client=Join-Path $env:LOCALAPPDATA 'PO0\po0-outbound-ip-report.ps1'; powershell -ExecutionPolicy Bypass -File $client -RunOnce
```

```powershell
$client=Join-Path $env:LOCALAPPDATA 'PO0\po0-outbound-ip-report.ps1'; powershell -ExecutionPolicy Bypass -File $client -InstallTask -IntervalSeconds 3600
```

管理员安装时才把 `$env:LOCALAPPDATA` 改为 `$env:ProgramData`。

Windows PowerShell 查看计划任务状态、最近结果摘要和原始日志路径：

```powershell
$client=Join-Path $env:LOCALAPPDATA 'PO0\po0-outbound-ip-report.ps1'; powershell -ExecutionPolicy Bypass -File $client -ScheduleStatus
```

```powershell
Get-ScheduledTaskInfo -TaskName "PO0 Outbound IP Report to LAN Worker"
```

Windows PowerShell 暂停 / 恢复本脚本管理的定时上报：

```powershell
$client=Join-Path $env:LOCALAPPDATA 'PO0\po0-outbound-ip-report.ps1'; powershell -ExecutionPolicy Bypass -File $client -PauseSchedule
```

```powershell
$client=Join-Path $env:LOCALAPPDATA 'PO0\po0-outbound-ip-report.ps1'; powershell -ExecutionPolicy Bypass -File $client -ResumeSchedule
```

```powershell
$log="$env:LOCALAPPDATA\PO0\po0-outbound-ip-report.log"; if (-not (Test-Path -LiteralPath $log)) { $log="$env:ProgramData\PO0\po0-outbound-ip-report.log" }; Get-Content -Tail 40 -LiteralPath $log
```

Windows PowerShell 更新、查看版本或查看当前更新内容：

```powershell
$client=Join-Path $env:LOCALAPPDATA 'PO0\po0-outbound-ip-report.ps1'; powershell -ExecutionPolicy Bypass -File $client -UpgradeSelf
```

```powershell
$client=Join-Path $env:LOCALAPPDATA 'PO0\po0-outbound-ip-report.ps1'; powershell -ExecutionPolicy Bypass -File $client -Version
```

```powershell
$client=Join-Path $env:LOCALAPPDATA 'PO0\po0-outbound-ip-report.ps1'; powershell -ExecutionPolicy Bypass -File $client -Changelog
```

三个访问设备客户端都会把裸域名自动规范化为 HTTPS `/report`，并默认拒绝 `http://`；仅本地调试或临时旧环境才显式使用 `--allow-http` / `-AllowHttp`。Linux/OpenWrt/macOS 的配置文件优先级是 `--config`、`PO0_OUTBOUND_IP_REPORT_CONFIG`、legacy `PO0_SELF_REPORT_CONFIG` / `SELF_REPORT_CONFIG`、已保存配置、root 的 `/etc/po0-outbound-ip-report/settings.env`、`$XDG_CONFIG_HOME/po0-outbound-ip-report/settings.env`、`$HOME/.config/po0-outbound-ip-report/settings.env`、最后 `./po0-outbound-ip-report.env`；旧 `po0-self-report` 配置路径只作 fallback，保存时写入新路径。Windows 默认配置文件普通用户为 `%LOCALAPPDATA%\PO0\outbound-ip-report.json`，管理员为 `%ProgramData%\PO0\outbound-ip-report.json`；旧 `self-report.json` 只作 copy-forward 迁移来源。配置文件会明文保存 self-report secret，请只放在可信设备上。

SSID 跳过是访问设备客户端本地 guard，不属于 LAN Worker 或 PO0 协议。Linux/OpenWrt/macOS 的 CLI 使用 `--skip-wifi-ssid`、`--skip-wifi-ssids`、`--clear-skip-wifi-ssids` 和 `--force-report`，Windows 使用 `-SkipWifiSsids` 和 `-ForceReport`，canonical 环境变量使用 `PO0_OUTBOUND_IP_REPORT_SKIP_WIFI_SSIDS`；保存配置时 Linux/OpenWrt/macOS 写入 `SKIP_WIFI_SSIDS`，Windows 写入 `SkipWifiSsids`。列表用英文分号 `;` 分隔，解析时 trim 每一项并丢弃空项，匹配当前 SSID 时只做精确字符串比较，不支持通配符、正则、大小写折叠或子串命中。命中后客户端在调用公网 IPv4 探测和 HTTP `/report` 前结束本次自动上报，只写本地跳过状态和日志摘要；不会向 LAN Worker 上传 SSID、命中项、跳过原因或任何新 query/header，因此 LAN Worker `/report`、`--client-ip-report` 和 PO0 `entries.tsv` 数据模型都不变。读取当前 SSID 失败、设备没有 Wi-Fi、平台命令不可用或权限不足时，客户端继续正常上报，避免因为本地探测能力缺失导致动态白名单过期。交互式手动运行命中跳过规则时先询问是否强制继续；定时任务 / launchd / Task Scheduler 命中时不阻塞、不询问，只写跳过摘要。

命名迁移只处理脚本可确定的默认 legacy 路径，不做全盘扫描。Linux/OpenWrt/macOS 更新、自愈或安装定时上报时会迁移默认旧配置、旧 `/tmp/po0-self-report.log`、旧 IP 探测 state，并移除默认旧 `po0-self-report` 命令；cron/launchd 会从旧 marker / label 迁到 `PO0_OUTBOUND_IP_REPORT_*` / `fr.schweppes.po0-outbound-ip-report`，macOS 安装 launchd 前会先清旧 cron，清理失败则不加载新 launchd，避免双重上报。Windows 更新、自愈或安装计划任务时会迁移默认旧配置、日志、state 和旧计划任务；新任务注册成功后才删除旧任务，删除失败时先禁用旧任务并报错。显式 `--config` / `-ConfigPath`、`--install-path`、`-LogPath` 等自定义路径按用户自定义处理，不在自动 legacy 清理中删除。

访问设备客户端的用户可见结果行统一为 `PO0 Outbound IP Report 已完成：...` 或 `PO0 Outbound IP Report 未完成：...`。一次性上报只有在本机探测到公网 IPv4、LAN Worker HTTP 返回 2xx，且 LAN Worker 已成功代报 PO0 后才打印完成；否则保留底层错误并返回非零状态。LAN Worker 成功返回 `OK <ip>; targets=<N>; target_names=<目标列表>` 时，三个客户端都会把目标列表汇总到完成结果和定时上报状态摘要；连接旧 LAN Worker 只有 `targets=<N>` 时退回显示 `PO0 目标：N 个`。Linux/OpenWrt 和 macOS 定时任务的每次运行输出重定向到 `/tmp/po0-outbound-ip-report.log`，其中也包含同样的结果行。macOS 默认静默；显式启用通知后，成功/失败通知只是附加 UI 提示，通知失败不能影响上报结果。Windows 计划任务不会依赖一闪而过的控制台窗口；`-InstallTask` 会把 `-LogPath` 写入任务参数，管理员安装默认日志为 `%ProgramData%\PO0\po0-outbound-ip-report.log`，普通用户安装默认日志为 `%LOCALAPPDATA%\PO0\po0-outbound-ip-report.log`，运行时会记录可执行到的上报过程、LAN Worker 返回体和完成/未完成结果；参数、配置或探测阶段的早期失败只记录错误路径。Windows 的通知实际行为由计划任务/VBS launcher 是否带 `-Notify` 决定；菜单“查看定时上报状态”会解析 launcher，展示配置通知状态、任务实际通知状态和实际 `-File` 脚本目标，不一致时提示通知或旧路径漂移，同时展示计划任务上次运行结果和最近结果摘要，原始日志路径 / tail 命令仍保留用于排查细节。

Self-report / WebAuth 放行 TTL 默认均为 `43200` 秒（12 小时），由 LAN Worker 上报 PO0 时传入；客户端只控制上报频率，不控制 TTL。TTL 可以通过 `po0-lan-client --self-report-ttl <秒数>` / `--webauth-ttl <秒数>`、bootstrap 向导，或 LAN Worker 菜单 `Self-report / WebAuth TTL` 修改。Self-report / WebAuth TTL 会被限制在 `60-604800` 秒内；WebAuth 由 LAN Worker 传入 expires-at，PO0 端也会把过远的 expires-at 截到 7 天内。旧安装的本机 `settings.env` 如果仍保存旧默认 `3600` 或 `21600`，脚本加载时会迁移到新默认；各 PO0 目标行中显式写入的 TTL 不自动改写。

`--bootstrap` 会先 probe，再写入本机目标配置；如果要求安装本机 Worker 轮询器，管道运行时会自动落盘到固定路径。`--install-cron N` 是兼容参数，会把 DDNS 和资源任务两个计划都设为 `N` 分钟；不带 `N` 时，默认 DDNS 每 `3600` 秒上报、资源任务每 `1440` 分钟检查一次。推荐用 `--ddns-interval-seconds 3600` 显式设置 DDNS 上报间隔。Worker 默认调用 PO0 上的 `/root/nftables-relay-manager.sh`，也可以通过 `--po0-script` 覆盖。首次部署推荐 `--wizard`，高级维护菜单仍可管理本机 Worker 的 PO0 目标：查看、添加、编辑、删除、启用/停用，执行 DDNS 解析上报和资源任务轮询领取，并只读查看 PO0 端资源任务创建计划。一个配置文件可以放多台 PO0/VPS。

向导自动取 token 使用 PO0 端机器可读接口：

```bash
bash nftables-relay-manager.sh --worker-token-bundle
bash nftables-relay-manager.sh --worker-token-bundle --ensure-resource-token
```

该接口输出 `KEY=value`，包括 DDNS、资源任务、client-ip、SSH report、WebAuth 等 token。资源任务 token 只有在传 `--ensure-resource-token` 且文件不存在时才会生成；已有 token 不会被重置。

该 Worker 同时承担资源更新任务。目标配置末尾新增 `resource_token` 字段，旧配置没有该字段时按“未启用资源任务”处理。菜单可以直接编辑已有目标并补填 Token。

如果只需要内网 Worker 更新 `iplist` / `qqwry.ipdb`，可以只配置 `--po0-host` 和 `--resource-token`，不填写 `--ddns-domain`；这类目标会跳过 DDNS resolver，只轮询资源任务。旧参数 `--domain` 仍作为兼容别名：没有 `--ddns-domain` 时，同时作为 source key 和 DDNS 域名。

资源任务流程：

```text
PO0 菜单创建 pending 任务
内网 Worker 通过 --resource-task-claim 领取任务
Worker 构建 iplist.tar.gz 或下载 qqwry.ipdb
Worker 计算 SHA-256 和文件大小
Worker 通过 SSH 调用 --resource-task-upload，从 stdin 上传到 PO0 固定收件路径
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
bash nftables-relay-manager.sh --resource-task-upload TASK_ID WORKER_ID SHA256 SIZE TOKEN < ARTIFACT
bash nftables-relay-manager.sh --resource-task-complete TASK_ID WORKER_ID SHA256 SIZE TOKEN
bash nftables-relay-manager.sh --resource-task-fail TASK_ID WORKER_ID REASON TOKEN
bash nftables-relay-manager.sh --resource-task-ping TOKEN
```

`--resource-task-create` 和 `--install-resource-task-cron` 是 PO0 管理员入口，只创建等待领取的固定任务，不主动连接内网机器。`--resource-task-cron-status` 是只读状态接口，供 Worker 菜单显示 PO0 端创建计划。`--resource-task-ping/claim/upload/complete/fail` 主要供 Worker 调用。`--resource-task-ping` 只读检查 token；任务领取、上传和状态修改使用 `flock`（系统提供时）串行化；上传路径由 PO0 生成，客户端不能指定生产文件路径。资源任务使用独立 Token，不复用 DDNS 上报 Token。使用 PO0 专用受限 SSH 上报 key 时，`scope=worker` 允许 `--ddns-report/check`、`--client-ip-report/check`、`--webauth-report/check`、`--resource-task-ping/claim/upload/complete/fail` 和只读 `--resource-task-cron-status`，但不允许 `--ssh-ip-report`、`--resource-task-create` 或安装 PO0 端定时任务；旧 wrapper 需要用新版脚本重新安装/刷新。wrapper 仍只做受控 action 白名单和简单参数校验；`--resource-task-fail` 会把 task/worker 与最后一个 token 之间的字段合并为 reason，以兼容包含空格的失败原因，不恢复通用 `SSH_ORIGINAL_COMMAND` shell parser。资源产物通过受限 manager 命令的 stdin 上传，不依赖 SCP。

LAN Worker 本机保留两类资源任务记录：`resource-stats.tsv` 是每个 PO0 endpoint 的聚合统计，`resource-events.tsv` 是逐次查询/执行事件日志。菜单 `资源统计` 会同时展示汇总和最近事件；路径可用 `PO0_LAN_RESOURCE_STATS` / `PO0_LAN_RESOURCE_EVENTS` 覆盖。菜单 `清理资源统计` 支持清空事件日志、清空全部资源统计，或按最近 N 条裁剪事件日志；资源轮询结束后也会自动裁剪事件日志，默认保留最近 `500` 条，可用 `PO0_RESOURCE_EVENTS_KEEP` 调整。

`qqwry.ipdb` 默认下载源：

```text
https://raw.githubusercontent.com/nmgliangwei/qqwry.ipdb/main/qqwry.ipdb
```

PO0 的基础 IPDB 格式校验使用常见的 `od`、`dd`、`grep` 检查文件头、元数据长度、关键字段和数据区，不要求预先安装 Python 包。系统已有 Python 时会追加严格 JSON 元数据校验；真正查询归属地仍需要菜单中的 `ipip-ipdb` 解析依赖。

Worker 的 `resource-stats.tsv` 每个 PO0 端点只保留一行累计统计，不会按任务无限追加。PO0 的任务文件保留全部活动任务和最近 500 条终态记录，管理员可以在菜单中查看结果，或把失败/执行中的任务重新排队。

### 5.6.1 PO0 manager HTTP 更新镜像

该功能不是资源任务，也不是 PO0 HTTP 控制面。LAN Worker 运行一个本地 HTTP 后端，Caddy 把固定路径反代到本机后端。公网入口可使用域名或 IP，未写端口时默认补 `2333`；Caddy 入口统一写成 `:<port>` 端口级 HTTP 站点，使域名和直接 IP 都能命中同一反代，不依赖 Host 域名匹配：

```text
/po0-manager-update/nftables-relay-manager.sh
/po0-manager-update/health
```

LAN Worker 后端收到请求后，通过 HTTPS 固定拉取：

```text
https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download/nftables-relay-manager.sh
```

PO0 请求时不把 token 放进 URL，只发送随机 `nonce` 和 `token_id=sha256(resource_token)`。LAN Worker 用本机配置里的 resource token 匹配 `token_id`，返回脚本正文，并在响应头写入：

```text
X-PO0-Manager-Version
X-PO0-Manager-SHA256
X-PO0-Manager-Size
X-PO0-Manager-Nonce
X-PO0-Manager-HMAC
```

HMAC 消息格式固定为：

```text
nonce|sha256|size|version
```

PO0 的 `--upgrade-manager-from-lan [URL]` 只接受 HTTP URL；入口不是 HTTP 默认 80 端口时，URL 必须显式包含 `:PORT`。下载后会校验 nonce、HMAC、sha256、size、`SCRIPT_NAME`、`SCRIPT_VERSION`、`CHANGELOG_BEGIN/END` 和 `bash -n`，然后备份当前 `${MANAGER_INSTALL_PATH}`，以临时文件 + `chmod 0755` + `mv` 原子替换。更新成功后会显示版本变化和 changelog，并询问是否用更新后的脚本执行 `--refresh-report-key-wrapper`；从交互菜单进入时，结果停留后按回车会 `exec bash "${MANAGER_INSTALL_PATH}"` 重新打开新版菜单。命令行直接执行 `--upgrade-manager-from-lan` 仍只更新后退出，便于串行运行 `--version`、`--changelog` 或其它维护命令。更新不会自动应用 nftables，也不会自动跑诊断。

### 5.6.2 Egern SSH report 上报

Egern 不再承担 DDNS 解析。它只做移动设备当前出口 IPv4 上报：

```text
Egern 用 DIRECT 轮询 IP 查询接口，默认列表为 IP9/163/Bilibili/126/腾讯新闻/爱奇艺/央视/myip.ipip；脚本会记住上次起点，下次从下一个接口开始，从响应里提取当前公网 IPv4，并优先复用响应里的归属地 / 运营商信息用于状态页
Egern 通过一次性 SSH 调 PO0 --ssh-ip-report
PO0 写 entries.tsv：source_type=ssh_report
成功后重建并应用白名单
Egern 把最近状态写入 ctx.storage，Widget 读取显示
```

单 PO0 命令等价于：

```bash
bash /root/nftables-relay-manager.sh --ssh-ip-report <source-id> <ipv4> <token> [identity] [ttl] [cidr-prefix]
```

Egern / ssh-report 放行 TTL 默认 `43200` 秒（12 小时）。单 PO0 可在模块环境变量 `TTL_SECONDS` 覆盖；多个 PO0 可在 `SSH_REPORT_TARGETS` 每行最后一列分别覆盖。实际 SSH 自动上报周期由 `AUTO_REPORT_INTERVAL_SECONDS` 控制，默认 `3600` 秒，可设置 `600` 到 `86400` 秒；建议 TTL 大于自动上报周期并留出余量。模块 schedule 每 10 分钟轻量检查一次；如果 TTL 小于自动上报周期，脚本会提前续期，尽量避免过期空窗。Egern 蜂窝网络默认按 `CELLULAR_CIDR_PREFIX=24` 上报 `/24`；Wi-Fi 和未知网络固定 `/32`。

多 PO0 上报由模块环境变量 `SSH_REPORT_TARGETS` 控制，一行一个目标：

```text
source-id|host|port|user|script|token|identity|ttl
```

示例：

```text
iphone-sg|sg-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_SG|egern-iphone|43200
iphone-us|us-po0.example.com|22|root|/root/nftables-relay-manager.sh|TOKEN_FOR_US|egern-iphone|43200
```

脚本只查询一次当前 IPv4，然后按目标列表依次 SSH 上报。全部目标成功时状态为成功；部分失败时保留每个目标的成功/失败明细并发出失败通知，但不会回滚已成功的 PO0。

如果使用 PO0 专用受限 SSH 上报 key，Egern 专用 key 的 scope 应为 `egern`。wrapper 拒绝时会把不含 token 的摘要写入 `/etc/nftables.d/po0-report-key-denied.log`，也可以用 `--refresh-report-key-wrapper` 刷新 wrapper，再用 `--show-report-key-denials 80` 查看最近记录。Egern 手动执行和 Status 脚本开启 debug，SSH stderr 会写入脚本日志；长错误会分段通知。

### 5.7 高级渲染调试

入口：

```text
bash nftables-relay-manager.sh --render > /tmp/po0-relay.conf
```

`--render` 只把计划生成的 relay nftables 配置输出到 stdout，适合重定向和 diff。它不再作为普通菜单入口；日常应用规则仍通过菜单操作，脚本在应用前会自动做 nft -c 预检。

### 5.8 conntrack 学习服务

学习服务只记录成功完成双向转发的公网来源 IP，不自动放行。交互入口：

```text
管理源 IP 白名单 -> 来源 IP 学习与候选提升
启动 / 停止学习服务
查看学习记录与候选统计
将学习到的单 IP / /24 / /16 候选加入自定义白名单
压缩 / 归档学习日志
清空学习记录
```

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
管理源 IP 白名单 -> 被阻挡访问日志
查看被阻挡访问统计
采集最近 1 小时日志
按自定义 since 采集日志
压缩日志并刷新统计
清空日志
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
部署与概览
  1) 安装 / 初始化 nftables
  2) 刷新 PO0 公网 IP
  3) 查看概览与规则列表

转发规则
  4) 新增规则
  5) 编辑规则
  6) 调整顺序
  7) 启用 / 停用
  8) 删除规则
  9) 导入 / 接管现有规则
 10) 导出规则

来源、客户端与资源
 11) 源 IP 白名单
 12) 客户端部署命令
 13) 内网资源更新任务

系统维护
 14) 中转机参数
 15) 诊断 / 自检
  16) 脚本版本 / 更新
  17) 可选开启 BBR + fq
  18) 完整备份 / 导入恢复

退出
  0) 退出
```

### 7.2 非交互入口

```bash
bash nftables-relay-manager.sh --render > /tmp/po0-relay.conf
bash nftables-relay-manager.sh --refresh-ddns
bash nftables-relay-manager.sh --ddns-report-check <ddns-source-key> TOKEN
bash nftables-relay-manager.sh --ssh-ip-report <device-id> 1.2.3.4 TOKEN <identity> 43200 32
bash nftables-relay-manager.sh --client-ip-report <device-id> 1.2.3.4 TOKEN <identity> 43200
bash nftables-relay-manager.sh --webauth-report <auth-source> 1.2.3.4 <identity> 2026-06-16T12:00:00Z TOKEN
bash nftables-relay-manager.sh --resource-task-create all
bash nftables-relay-manager.sh --install-resource-task-cron all daily
bash nftables-relay-manager.sh --resource-task-ping TOKEN
bash nftables-relay-manager.sh --collect-blocked "24 hours ago"
bash nftables-relay-manager.sh --learn-service
bash nftables-relay-manager.sh --backup-export
bash nftables-relay-manager.sh --backup-import /etc/nftables.d/backups/po0-manager-full-backup-YYYYMMDD_HHMMSS.tar.gz
bash nftables-relay-manager.sh --backup-import /etc/nftables.d/backups/po0-manager-full-backup-YYYYMMDD_HHMMSS.tar.gz --restore-all
bash nftables-relay-manager.sh --upgrade-manager-from-lan http://<LAN_WORKER_IP>:2333/po0-manager-update/nftables-relay-manager.sh
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
--backup-export 导出 PO0 完整敏感备份包
--backup-import 默认恢复配置/状态文件；cron/systemd/nftables/authorized_keys 需显式 flag
--upgrade-manager-from-lan 从 LAN Worker HTTP 更新镜像拉取并校验安装 PO0 manager
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

完整备份包：

```text
manifest.env
files/conf-dir/                         /etc/nftables.d live state，排除 backups、po0-ipdb-venv、*.lock
system/nftables.conf                    /etc/nftables.conf 快照
system/sysctl.conf                      /etc/sysctl.d/99-po0-relay.conf 快照
system/resource-task-cron.managed       PO0 资源任务创建 cron block
system/dynamic-allowlist-cron.managed   动态来源清理 cron block
system/report-keys.tsv                  从 passwd/getent 用户 home 的 authorized_keys 自动发现的 po0-report:scope=... 公钥
system/nftables-relay-learn.service     学习服务 unit 快照
system/nftables-relay-learn             学习服务 runner 快照
scripts/nftables-relay-manager.sh       当前脚本快照
```

`files/conf-dir/` 会覆盖 token、规则、白名单、动态来源缓存、统计、pending 审核、资源任务状态、resource inbox、iplist/ipdb、wrapper 和拒绝日志。导入默认只恢复这部分，并在恢复后用当前脚本重新生成 `po0-report-key-wrapper`，避免旧 forced-command 逻辑复活。

显式恢复项：

```text
--restore-cron           恢复 PO0 managed cron block，优先从备份的 cron block 识别旧脚本路径，并重写为当前 manager 路径
--restore-systemd        用当前脚本重新生成/启用学习服务
--restore-nftables       恢复 /etc/nftables.conf、sysctl，并尝试 apply_full_config/systemctl enable --now nftables
--restore-report-keys    用当前 wrapper/manager 路径重建 PO0 受限 authorized_keys 条目
--restore-all            上述全部
--dry-run                只显示将恢复的路径和入口
```

LAN Worker 完整备份包包含 `targets.tsv`、`settings.env`、stats/resource-stats/resource-events、配置目录 `ssh-key-*`、目标 SSH 参数引用的 `-i`/`IdentityFile` 私钥、managed cron block、`po0-lan-self-report.service`/`po0-lan-webauth.service`/`po0-lan-manager-update.service` 快照、Self-report Caddy snippet、manager update Caddy snippet、Caddyfile 快照和脚本快照。导入默认只恢复配置/状态/密钥；`--restore-cron`、`--restore-systemd`、`--restore-caddy` 或 `--restore-all` 才恢复运行入口。恢复 LAN Worker cron 时会优先从备份的 cron block 识别旧脚本路径，并把旧配置路径和旧脚本路径重写为当前 `CONFIG_FILE` 和当前持久脚本路径。`settings.env` 保存 `SELF_REPORT_SECRET`、Self-report/WebAuth 监听、TTL、HTTPS/Caddy 路径、Manager update HTTPS/Caddy 路径、`MANAGER_UPDATE_*`、Worker ID、资源任务超时和轮询间隔，脚本升级后会先加载该文件再让 CLI 参数覆盖；旧安装没有 `settings.env` 时，会从已安装的 Self-report/WebAuth/manager update systemd unit 回填 secret、监听地址、TTL、目标、token 和 manager update 配置，再写入新的 `settings.env`。LAN Worker 对 `targets.tsv`、`settings.env`、DDNS stats、resource stats/events 的写入使用配置目录级 `.po0-lan-client.lock`；该锁文件是运行时互斥文件，不进入 backup staging，也不会从备份恢复。

备份不会导出 Egern 设备私钥、Egern app 本地配置、Cloudflare Tunnel/Access 远端配置、云安全组/防火墙规则、Caddy ACME 证书数据库、系统包安装状态，或脚本没有托管的手工配置。Egern PO0 受限 SSH 上报公钥会通过 `system/report-keys.tsv` 记录，并在 `--restore-report-keys`/`--restore-all` 下恢复。

导入规则入口可以从现有 nft 配置或运行中 ruleset 尝试提取 DNAT 规则，并转成脚本托管规则。接管前会做备份，导出入口会保存当前托管配置，便于迁移或回滚。全局设置里的 `NODE_NAME` 非空时，导出默认文件名会加此前缀，例如 `PO0XX-po0-relay-export-YYYYMMDD_HHMMSS.txt`。

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
