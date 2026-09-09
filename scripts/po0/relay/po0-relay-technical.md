# PO0 精简版实现边界

当前源码以 `2026.09.08+build.1` 为起点，完整旧实现见固定 tag `archive/po0-full-20260907.1`。测试中 `tools/po0/fixtures/update-v1/` 仅保留旧更新协议的最小对端，供兼容性回归，不参与构建或安装。

## 转发管理器

配置仍在 `/etc/nftables.d/`：`po0-relay.env`、`po0-relay.rules`、`po0-relay.conf`。`po0-relay-resource-task.token` 这个历史文件名继续保存更新密钥，避免配对失效。

规则模型、转发端口检查、SNAT、MSS、BBR、诊断及交互 helper 保留。渲染只写 `po0_relay_nat` 和可选 `po0_relay_mangle`，不创建来源集合或 input chain，不执行 `flush ruleset`。删除旧托管表与创建新表合成一个 batch，先 `nft -c`，正式阶段只调用一次 `nft -f`。主配置只追加托管 include。

迁移 guard 同时检查旧开关、持久化 nft 文件与运行中的托管 NAT 表。保护仍启用时停止，不把有过滤的转发静默变成无限制转发。迁移先压缩备份，再移除已识别的旧 crontab 块/学习服务，并把退役状态移入 `backups/retired-state/`；保留转发文件与更新 Token，不应用 nftables。

新版备份采用 `po0-relay-backup-v2`；恢复在解包前限制成员路径和普通文件类型，再检查保护状态。恢复只落盘，后续应用是独立动作。旧完整备份在归档版中恢复。

## Worker 与更新协议

Worker 仅保留配置、更新镜像、Caddy/服务安装、自更新、备份和迁移。现有 HTTP 服务名、后端监听参数与 Caddy 更新片段不变。更新密钥从 `update-keys.txt` 读取；文件尚不存在时才允许从旧 `RESOURCE_TOKEN` 与启用目标第 11 列迁移。空密钥文件表示明确清空，不能回退复活。

请求路径固定 `/po0-manager-update/nftables-relay-manager.sh`，查询含随机 nonce 和密钥 SHA-256 标识。响应返回脚本字节、版本、SHA-256、大小、原 nonce，以及：

```text
HMAC-SHA256(key, nonce + "|" + sha256 + "|" + size + "|" + version)
```

manager 核对所有响应头、实际大小与摘要、HMAC、脚本身份、changelog、内嵌版本及 `bash -n` 后，才备份并替换当前脚本。Worker 上游固定为 GitHub Latest manager HTTPS 资产，限制响应大小，不输出上游异常细节。

旧 Worker 配置先冻结到 `pre-retirement-v1/`。同机官方导入使用 Python `shlex` 解析数据，不执行旧设置；配置冲突停止。导入、旧任务退役、新任务激活依次执行，各步骤有收据；旧任务停止前不会创建重复官方计划。

## 官方客户端

三端桌面保持原有配置/安装路径、官方 GET-first 请求引擎及日志脱敏。只读状态不消耗定期 due，自动开关与凭据分开。迁移入口清理旧自建任务，配置写入前备份原件，保留官方计划与停用选择。

OpenWrt APK 使用独立的 POSIX shell 官方 runner/request；不再打包通用 Linux 自建引擎。历史 engine 路径仅转交 UCI 适配器。UCI/procd/hotplug 只有官方实例，手动与查询仍可在自动总开关关闭时运行。真实 DNS 解析、WAN/源地址绑定、无故障回退、限长响应和互斥处理保持原有行为。

Egern / Stash / Loon 保持 Token、槽位及按网络选择的本机保存契约。新活动状态只含官方字段，原配置与状态另存不可覆盖快照。旧动作返回退役结果；缓存 Tile 无副作用。Stash 原 provider 标识中的 `worker-v2` 只是脚本执行身份，继续保留以避免缓存绑定变化。

Egern SSID guard 覆盖所有普通上报入口，包括状态组件与 Widget 刷新；只允许非 Widget 的明确手动强制入口绕过。匹配前从当前模块参数读取跳过列表，使用 ctx.device.wifi.ssid；命中后不进入官方请求引擎，只保存本机跳过提示，官方结果和 due 保持不变。只读查询仍允许 GET，绝不 POST。

## 验证与发布

两种 checker 保持 manifest 全覆盖、编码/换行、精确资产清单、raw URL 策略、版本/tag、Egern 兼容副本、标准路径和 SSID/定位 helper 检查。专项回归覆盖官方请求错误/槽位/锁、调度、手机存储迁移、APK UCI/服务/LuCI、nft 原子应用，以及新旧更新镜像协议。测试不访问真实官方 API，不操作实际设备。

五脚本与 APK 按组件 tag 独立发布，全部资产校验完成后公开。主线只使用 `main`；固定归档和历史 Release 不随精简删除。
