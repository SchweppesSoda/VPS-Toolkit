# PO0 runtime and client contracts

仅在修改 PO0 行为、客户端或迁移时读取相关条目。普通文档/发布元数据修改不执行设备动作。

## PO0 职责边界

- 用户已全面弃用自建防火墙。manager 只管理转发、NAT/SNAT/MSS、可选 BBR、诊断、备份及鉴权更新；不得恢复 input/source 白名单、DDNS、SSH/HTTP 接收、WebAuth、学习与 iplist/ipdb 任务。
- LAN Worker 只提供固定 manager 脚本更新镜像。PO0 无法直连 GitHub，必须保持现有 HTTP 路径、nonce/HMAC、密钥与服务入口；上游使用固定 GitHub Release HTTPS 资产，不能成为任意 URL 代理。
- 原 Worker 官方账号显式迁移至同机 Linux 官方单文件客户端（也可在具备依赖的 OpenWrt 上运行），保持本机正常路由/OpenClash 行为。不得静默改成 APK WAN 源地址绑定，不得丢失账号或建立重复任务。
- 七端只保留官方上报。先 GET、必要时 POST；Egern 同 /24 共用既有槽位，403 只复查一次。只读不 POST、不推进 due；Token、槽位、名称、间隔、停用与网络触发选择必须保留。
- 主 OpenWrt 用 mwan3 指定 WAN；旁路 OpenWrt 绑定专用源地址，真实 DNS 按本机 probe_dns_server（默认 192.168.88.1）解析。指定 WAN/地址失败不回退。其它端保持原网络行为。官方 Token 不进入日志、通知、命令参数和运行状态；主动打开的本机编辑页按用户要求显示完整已保存 Token。
- 支持 SSID 的客户端采用本地 guard，读取失败继续；Stash 没有公开 SSID API，出口变化依靠轮询。强制仅绕过本机条件，仍先 GET。Egern/Stash/Loon 按网络选择默认关闭，开启后原目标为蜂窝、另填目标为 Wi-Fi，用户槽位不变。
- manager 的迁移 guard 必须拒绝仍有旧保护的配置/运行表，不得静默削弱保护。托管 NAT/MANGLE 的删除与新表定义在同一 batch，先 nft -c，正式阶段只一次 nft -f，不 flush ruleset。
- 旧版资产固定 tag/非 Latest Release `archive/po0-full-20260907.1`；历史不是维护分支，不把归档功能带回 main。最小旧协议测试夹具仅供测试，不参与安装。私有 ProxyConfig 的归档不得进入公开仓库/Release。

## 平台合同

- 三端访问设备客户端的 SSID 跳过只允许作为本地 guard：命中时本机跳过并写日志摘要，不上传 SSID，不新增 LAN Worker `/report` 或 PO0 协议字段；SSID 列表用英文分号分隔并精确匹配；读取失败必须继续正常上报；手动运行命中时询问是否强制继续；不要为 SSID 新增 `PO0_SELF_REPORT_*` 或 `SELF_REPORT_*` legacy alias。
- macOS 访问设备客户端必须兼容系统自带 Bash 3.2；在 `set -u` 环境下不要用空 Bash 数组解析可选列表，例如 `local -a items` / `read -r -a items` / `"${items[@]}"`，SSID 列表解析应使用 Bash 3.2 安全的字符串循环，并保留对应 release gate。
- macOS 当前 Wi-Fi SSID 读取遇到 `redacted` / `<redacted>` 时应按系统隐私权限隐藏处理，必须 fail-open 继续上报；允许提供 `--show-wifi-ssid` / `--diagnose-wifi-ssid` / `--request-location-permission` / `--delete-location-permission-helper` / `--open-location-services` 这类本地诊断、用户授权指引、Helper App CoreLocation 授权请求、本地 Helper 删除和系统设置跳转。macOS 26+ 不要依赖 Terminal/iTerm 出现在定位服务列表里；`--request-location-permission` 应使用带稳定 bundle id、定位用途声明和可选 ad-hoc 签名的 `PO0 Location Permission Helper.app` 触发授权，并由 Helper 在本机通过 CoreWLAN 读取 SSID 后返回给脚本；删除 Helper 只移除本地 app，不能修改 macOS 定位授权 / TCC 记录；不静默授予或修改定位服务 / TCC 权限，不运行 `sudo`、不运行 `tccutil`、不保存提权凭据、不写 TCC 数据库。
- Linux/OpenWrt、macOS、Windows 三端访问设备客户端自更新后，应先检测 cron / launchd / Windows 计划任务是否已指向标准脚本路径；只有入口漂移、缺失或迁移旧任务时才刷新，不要每次自更新都无条件重写定时入口。
- OpenWrt APK 仅有 official procd 实例；官方 timer/network 开关独立，事件不移动定期截止点。升级保留总开关、官方凭据/停用和周期，不加载通用 Linux cron 安装入口。APK 修改运行 `test-openwrt-apk-layout.sh`。

## 官方客户端界面与迁移

- Windows/macOS/Linux 主菜单编号与语义对齐，只展示官方与必要通用设置。旧任务名称仅用于识别/清理；不能显示退役自建面板。保存只更新已存在的官方计划，不因保存而创建计划。
- 手机本机配置优先，清除保留停用记录，旧同步参数不能复活。首次迁移先保存原始配置/状态快照，后续不覆盖备份。旧动作返回明确退役结果，不运行另一个动作。
- Egern 只注册一个“PO0 防火墙上报状态”组件，按尺寸显示官方名称/槽位/占用/IP/时间；手动状态与 Widget 可绕过定期间隔，但必须遵守 SSID 跳过；仅明确的手动强制上报可绕过 SSID。只读查询不 POST，后台遵守 SSID/开关/due。Stash Tile 同步只读缓存，不请求、不写入、不迁移；点击进入本机管理页。
- 桌面/API/迁移测试必须使用临时配置与模拟请求，不访问真实官方 API，不操作设备计划/服务。
