# vless-raw-enc-argosbx-enhancer.sh 技术文档

## 2026-09-21 官方下载边界

官方 fallback 使用固定 release tag 和各架构资产 SHA256，不跟随 `latest`。摘要通过后只把
唯一 `xray` ZIP 成员写入 `BIN_DIR` 内的普通临时文件，读取 ELF header 证明位数、字节序和
机器架构，再 `mv` 替换旧文件。其它 ZIP 成员不解压，候选检查前不 chmod/执行二进制。
已有 Xray 基础命令与 VLESS ENC 功能检查继续由 `verify_xray_binary()` 执行；摘要和 ELF
检查不等同于运行能力验证。自定义固定 tag 必须伴随该架构明确摘要，未知 tag 无默认降级。
维护证据及回退限制见 [CHANGELOG](CHANGELOG.md)。

## 定位

`vless-raw-enc-argosbx-enhancer.sh` 是 argosbx/Xray 复用增强脚本，不是完整 Xray 面板。

它只复用 argosbx 的 Xray 二进制，另起一个独立 sidecar 服务：

- sidecar service：`agsbx-extra-vless-raw-enc.service`
- sidecar config：`/opt/agsbx-extra/vless-raw-enc/config.json`
- sidecar state：`/opt/agsbx-extra/vless-raw-enc/service.env`

它不会接管、修改或重启原 argosbx 的 Xray 服务，也不会改原 argosbx 的配置文件。

## 能力边界

保留的能力：

- 检测 argosbx，并优先复制 argosbx 自带 `xray`
- 未检测到 argosbx 时，可复制系统 `xray` 或下载官方 Xray release，按 sidecar 模式直接部署
- 安装 / 修复 VLESS RAW ENC
- 安装 / 修复 Shadowsocks 2022
- 从 argosbx 手动同步 Xray core
- 生成 VLESS 和 SS2022 分享链接
- 修改协议端口、节点名和密钥
- 配置测试、服务启停、日志查看
- 本机防火墙 / 云安全组提示
- 卸载 sidecar

不做的能力：

- 不做全协议 Xray 面板
- 不接管原 argosbx Xray 服务
- 不做 cnblock / 中国大陆直连或屏蔽
- 不写全局 routing 策略或安全屏蔽策略
- 不做 doctor / smoke / export 全局诊断
- 不做任意 Xray 版本升级编排；仅对本脚本的本地核心同步提供候选验证及失败恢复
- 不做 GitHub 下载镜像兜底

这些功能适合完整 Xray 管理器，不适合“复用增强脚本”。

## 端口约定

协议端口范围遵循 `scripts/vps/docs/vps-port-firewall-summary.md`。

当前 sidecar 管理的协议入站使用 `16384-24575`：

- VLESS RAW ENC：TCP
- Shadowsocks 2022：TCP/UDP

脚本会避开：

- 本机已监听端口
- argosbx 端口记录
- 旧 shadowsocks-rust 配置端口
- 同一 sidecar 内其它协议端口

## 协议配置

### VLESS RAW ENC

VLESS inbound 使用：

- `protocol: "vless"`
- `streamSettings.network: "raw"`
- `settings.decryption` 写入服务端 VLESS ENC decryption
- 分享链接写入客户端 encryption
- 默认不写 flow，可选 `xtls-rprx-vision`

### Shadowsocks 2022

SS2022 inbound 使用 Xray 的 `shadowsocks` 协议：

- `network: "tcp,udp"`
- 默认方法：`2022-blake3-aes-128-gcm`
- 自动密钥长度按方法选择：AES-128 用 16 字节，AES-256/ChaCha20 用 32 字节
- 分享链接按 SIP002 生成 `ss://`
- 支持为分享链接单独设置公网 host/port，适合中转或端口映射

脚本不再下载或管理 shadowsocks-rust 二进制。

## Xray core 来源

优先级：

1. 已存在的 `/opt/agsbx-extra/bin/xray`
2. argosbx 目录里的 `xray`
3. 系统 PATH 里的 `xray`
4. 经版本及 SHA256 固定的官方 Xray release
5. 用户手动指定二进制路径

如果 argosbx 后续更新了自己的 Xray core，可以通过菜单“从 argosbx 同步 Xray core”手动复制到 sidecar。

## 服务管理

systemd 环境写入：

`/etc/systemd/system/agsbx-extra-vless-raw-enc.service`

非 systemd 环境使用：

- `nohup xray run -config ...`
- PID 文件
- crontab `@reboot`

所有协议参数变更使用 `apply_install_config`：先在功能目录内的私有临时
目录生成 `service.env.next`、`config.json.next` 和 `share.txt.next`，用 `run -test -format json`
显式校验后保存 before-image
及服务状态，再依次 rename 正式文件。systemd 显式 enable + restart；pid+cron 确认旧
进程停止后启动，两个分支都在启动后检查存活。安装 / 修复的 core 准备不提前写入
`service.env`；独立 core 操作仍保存来源状态。

失败时恢复旧配置、分享文件、unit 与原有运行 / 启用状态，非 systemd 还恢复 crontab；分享
候选提前生成，仅应用成功后替换当前分享文件并展示。旧资料与诊断保留在 `.config-apply.*`
中，恢复失败必须明确报告。
这是同一进程内的尽力恢复，不覆盖断电、并发管理或此前更换的 core。显示元数据走同一事务的 `metadata` 模式、不触碰服务；最后一个协议禁用走 `stop` 模式，
写无监听配置并撤掉开机启动。独立启动保持幂等，停止与重启统一核实进程身份和返回值。操作边界见 [README](README.md)。

## 持续校时与诊断边界

SS2022 的配置应用与手动启动/重启检查 `ensure_ss_time_sync`；时间服务仍由系统维护，
不嵌入 Xray service 或另造常驻监督器。探测把开机启用、运行与同步证据分开，
timesyncd 用易失同步标记的新鲜度，chrony/ntpd 用其本机查询接口，均不向外请求任意时间。
校时查询失败不等于系统时间一定错误，但不能据此通过部署门禁。默认不替换已有 NTP。

`repair_time_sync` 的包安装和启用是单独的系统动作，需交互确认；保留已有时间源，
没有已知服务时仅支持 apt/systemd 安装 timesyncd。未同步时配置应用失败，校时服务保留。
非 systemd 的实际配置与重启维护不扩展成通用系统初始化框架。

配置测试显式指定 JSON，不依据 `.next` 或临时文件名推测；测试不改正式配置。
SS 连接测试在私有临时目录创建回环客户端，通过 EXIT/信号清理进程和文件；显式排除
`NO_PROXY` 对测试的绕过。协议回归另使用固定真实 Xray，合成配置和系统命令 stub 只证明
应用/恢复流程，不能替代协议兼容性验证。

## 卸载边界

卸载只删除：

- `/opt/agsbx-extra/vless-raw-enc`
- `agsbx-extra-vless-raw-enc.service`

不会删除或修改 `/root/agsbx` 以及其它 argosbx 文件。
