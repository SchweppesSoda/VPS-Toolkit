# nftables Relay Scripts

- `nftables-relay-manager.sh`: current maintained nftables relay manager for PO0 or other dedicated relay hosts, with global relay modes, cached IP detection, source allowlists, and optional conntrack-based source IP learning.
- `tools/po0-lan-client.sh`: 内网协作客户端，负责 DDNS 上报、资源任务领取、文件回传和本机统计。
- `nftables-legacy.sh`: original legacy script preserved for compatibility and reference.
- `nftables-relay-manager-technical.md`: overall technical documentation for the current manager implementation, IPDB integration, and future roadmap.
- `tools/build-iplist-package-technical.md`: technical documentation for the offline iplist package builders and region allowlist data source.

The manager now initializes `/etc/nftables.d/po0-relay-allowlist-sets.tsv` as the forward-compatible source allowlist set schema. The current legacy allowlist behavior maps to the `default` public set, rendered as nft set `po0_src_default`; per-port sets are represented by the schema but are not enabled by default.

Source entries are normalized in `/etc/nftables.d/po0-relay-allowlist-entries.tsv` using `set_id|cidr|source_type|source_value|note|created_at|expires_at`. Existing custom CIDR entries are still supported during migration and are mirrored into `default|...|manual` entries when edited through the manager.

SSH temporary allowlist entries are stored as `default|<client-ip>/32|ssh_temp|SSH_CONNECTION|...|created_at|expires_at`. Expired entries remain in the TSV for audit context but are skipped when rebuilding the effective nftables source allowlist cache.

DDNS 来源定义在 `/etc/nftables.d/po0-relay-allowlist-sources.tsv`，格式为 `set_id|source_type|name|value|enabled|ttl_seconds|last_resolved_at|last_result`。目前 `source_type` 支持 `ddns`，`value` 是域名。推荐模式是让 iOS/Egern、内网机器或路由器先解析域名，再通过 SSH 调 PO0 的 `--ddns-report` 上报公网 IPv4；PO0 本机 DNS 解析只作为兜底。`last_result=report:<ip_csv>` 表示外部上报结果，`last_result=local:<ip_csv>` 表示 PO0 本机兜底解析结果。

Suggested usage:

```bash
bash nftables-relay-manager.sh
```

预览 / 试运行：

```bash
# 生成临时配置、打印中文摘要；如果系统有 nft，会执行 nft -c 预检。
bash nftables-relay-manager.sh --preview

# 将计划生成的 nftables 配置输出到 stdout，方便重定向或 diff。
bash nftables-relay-manager.sh --render > /tmp/po0-relay.conf
```

DDNS 来源：

```bash
# 交互菜单：
# 12) 管理源 IP 白名单
# 10) 管理 DDNS 来源
#
# 可在菜单里查看、添加、编辑、删除、启用/停用、测试解析、刷新并应用 DDNS 来源。
# 查看时会显示 PO0 端接受外部上报的统计；选项 8 可以显示 / 生成外部上报 Token。

# 非交互刷新：优先使用 TTL 内的外部上报结果，过期或没有上报时才用 PO0 本机 DNS 兜底。
bash nftables-relay-manager.sh --refresh-ddns

# 外部机器已解析好公网 IPv4 后，上报给 PO0 并立即应用白名单：
bash nftables-relay-manager.sh --ddns-report home.example.com 1.2.3.4 TOKEN
```

DDNS 外部解析上报（推荐）：

```bash
# 1. 先在 PO0 菜单里添加 DDNS 来源，例如 domain=home.example.com。
# 2. 在 PO0 菜单选项 6 生成 token。
# 3. 在负责解析 DNS 的内网 Linux/macOS/OpenWrt 机器上打开交互菜单：
bash tools/po0-lan-client.sh

# 也可以直接 SSH 调 PO0：
ssh root@10.0.0.2 'bash /root/nftables-relay-manager.sh --ddns-report home.example.com 1.2.3.4 TOKEN'
```

`tools/po0-lan-client.sh` 是内网协作客户端，打开后就是中文菜单。它可以管理目标、执行 DDNS 上报、领取资源任务、查看统计和管理 cron。一个配置文件可以放多台 PO0/VPS。

## 内网资源更新任务

PO0 可以要求内网 Linux/macOS/OpenWrt 机器构建 `iplist.tar.gz` 或下载 `qqwry.ipdb`。PO0 不会主动连接内网机器，也不会下发任意 Shell 命令；内网客户端定时通过现有 SSH 连接领取固定类型任务，完成后使用 SCP 回传文件。

PO0 端：

```text
主菜单
  12) 管理源 IP 白名单
  15) 管理内网资源更新任务
```

首次使用：

1. 在 PO0 的资源任务菜单生成任务 Token。
2. 创建 `iplist`、`qqwry.ipdb` 或“全部更新”任务。
3. 在内网机器运行 `bash tools/po0-lan-client.sh`。
4. 编辑已有 PO0 目标，把任务 Token 填入“资源任务 Token”。
5. 选择“立即领取并执行资源任务”测试。
6. 确认成功后安装/更新定时任务。

定时任务每轮会先执行 DDNS 上报，再对每台唯一 PO0 领取最多一个资源任务。一个内网客户端可以服务多台 PO0；同一台 PO0 即使配置了多个 DDNS 域名，也只会轮询一次资源队列。

资源文件：

- PO0 任务队列：`/etc/nftables.d/po0-relay-resource-tasks.tsv`
- PO0 任务 Token：`/etc/nftables.d/po0-relay-resource-task.token`
- PO0 临时收件目录：`/etc/nftables.d/po0-relay-resource-inbox`
- 内网客户端统计：配置目录下的 `resource-stats.tsv`
- IPDB 下载源：`https://raw.githubusercontent.com/nmgliangwei/qqwry.ipdb/main/qqwry.ipdb`

回传文件会校验大小和 SHA-256。`iplist.tar.gz` 还会校验目录结构、地区清单和 CIDR 文件；`qqwry.ipdb` 会校验 IPDB 元数据结构。校验或导入失败时，PO0 保留旧数据。

任务文件保留全部等待中/执行中任务和最近 500 条已完成/失败记录，不会无限增长。

iOS / Egern：

- 模块文件：`clients/egern/PO0-DDNS-Report.yaml`
- 脚本文件：`clients/egern/po0-ddns-report.js`
- 工作方式：Egern 定时用 DoH 解析 `DDNS_DOMAIN` 的 A 记录，然后通过 SSH 调 PO0 的 `--ddns-report`。
- 需要填写：`PO0_HOST`、`PO0_USER`、`PO0_PASSWORD` 或 `PO0_PRIVATE_KEY`、`DDNS_DOMAIN`、`DDNS_TOKEN`。`DDNS_NAME` 可空，默认直接用 `DDNS_DOMAIN` 上报。

传统 DDNS 更新仍然可以保留：路由器 / OpenWrt 的 `ddns-scripts`、`ddns-go`，或各 DNS 服务商 API 负责更新域名；本脚本负责把解析结果同步进 PO0 白名单。

PO0 端会在 `/etc/nftables.d/po0-relay-ddns-report-stats.tsv` 为每个 DDNS 来源保留一条外部上报统计，记录接受/拒绝次数、最近上报时间、最近 IP 和最近错误；这不是逐次追加日志。

被阻挡访问日志：

```bash
# 白名单外来源访问托管转发端口时，会以 "po0-block" 前缀限速写入内核日志。
# 采集最近的内核日志到 /etc/nftables.d/po0-relay-blocked.tsv：
bash nftables-relay-manager.sh --collect-blocked

# 自定义 journalctl --since 时间范围：
bash nftables-relay-manager.sh --collect-blocked "24 hours ago"
```

被阻挡访问日志超过 10 MiB 或 100,000 条后会自动压缩，并重新生成 `/etc/nftables.d/po0-relay-blocked-summary.tsv`。统计按来源 IP、协议、目标端口和 set id 汇总；菜单里的“查看被阻挡访问统计”会复用 IPDB 显示归属地/运营商。日志文件本身只保存 IP、协议、端口、时间和原始内核日志。

Offline iplist package:

```powershell
# Windows PowerShell / PowerShell 7
.\tools\build-iplist-package.ps1

# or specify output path
.\tools\build-iplist-package.ps1 -OutFile D:\Temp\iplist.tar.gz

# or increase parallel downloads
.\tools\build-iplist-package.ps1 -ThrottleLimit 16
```

```bash
# macOS / Linux
bash tools/build-iplist-package.sh

# or specify output path
bash tools/build-iplist-package.sh /tmp/iplist.tar.gz

# or increase parallel downloads
bash tools/build-iplist-package.sh /tmp/iplist.tar.gz 16
# alternative when using the default Desktop output
IPLIST_JOBS=16 bash tools/build-iplist-package.sh
```

By default both scripts write `iplist.tar.gz` to the current user's Desktop and use 8 parallel downloads. The package includes `docs/cncity.md` plus `data/cncity/*.txt`; `data/country/*` links from the markdown are ignored. Upload `iplist.tar.gz` to the VPS, then use the manager menu:

- `12) 管理源 IP 白名单`
- `6) 导入 / 刷新 iplist 离线包`

Source allowlists support three modes:

- Region allowlist from the offline iplist package.
- Custom allowlist from manually approved IPv4/CIDR entries.
- Region plus custom allowlist.

The optional learning service uses `conntrack` events to record public source IPs that completed bidirectional forwarded connections. Learned IPs are only candidates; the manager requires manual confirmation before adding a learned IP, `/24` candidate, or high-risk `/16` candidate to the custom allowlist. Promotion menus apply extra thresholds based on hit count and observation span, so a single successful connection is not enough to become a promoted candidate.

Default promotion thresholds:

- `/32`: at least 3 hits, or at least 2 hits observed across 10 minutes.
- `/24`: at least 2 distinct IPs in the `/24`, or at least 3 hits.
- `/16`: at least 2 distinct `/24` networks in the `/16`, or at least 3 hits; adding it requires typing `YES`.
