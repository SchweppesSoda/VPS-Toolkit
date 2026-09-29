# PO0 Proxy Service Scripts

这个目录保存可用于独立 VPS 或已有 argosbx 主机的代理服务增强脚本。服务部署、节点生成和本机防火墙提示放在这里；端口转发和 nftables 规则仍放在 `../nftables/`。

## 脚本

- `vless-raw-enc-argosbx-enhancer.sh`：独立 Xray 双协议管理器；可以复用 argosbx 的二进制，也可直接安装固定版本官方 Xray。不接管原 argosbx 的服务和配置。当前支持：
  - VLESS + RAW + VLESS Encryption
  - Shadowsocks 2022（由 Xray `shadowsocks` inbound 提供，TCP/UDP）

VLESS RAW ENC 的外层物理监听只有 TCP。它可以在 VLESS TCP 会话内承载 UDP 转发语义，但
这不等于主机上存在该 VLESS 端口的 UDP listener；主机防火墙只应为 VLESS 端口声明 TCP。
SS2022 会实际监听 TCP 和 UDP，防火墙需要分别声明两条规则。

协议监听端口遵循 `../../vps/docs/vps-port-firewall-summary.md`，固定在 `16384-24575` 内选择。

## 使用入口

推荐永久安装命令入口（在 PO0 主机上执行）：

```bash
tmp="$(mktemp)"
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer.sh -o "$tmp"
sudo install -m 0755 "$tmp" /usr/local/sbin/vless-raw-enc-argosbx-enhancer
rm -f "$tmp"
sudo /usr/local/sbin/vless-raw-enc-argosbx-enhancer
```

以后直接运行：

```bash
sudo /usr/local/sbin/vless-raw-enc-argosbx-enhancer
```

只临时运行、不安装命令入口：

```bash
tmp="$(mktemp)" &&
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer.sh -o "$tmp" &&
sudo bash "$tmp"
rm -f "$tmp"
```

本地仓库运行：

```bash
cd scripts/po0/proxy-services
bash vless-raw-enc-argosbx-enhancer.sh
```

首次进入建议先执行“系统预检 / 环境判断”。如果机器上已有 argosbx，脚本会优先复制 argosbx 的 Xray；如果没有 argosbx，也可以下载官方 Xray 后按 sidecar 模式直接部署。

官方下载安装路径固定到经审核的 `v26.3.27`，按检测到的架构选择内置 SHA256；下载完成后
先检查 ZIP 摘要，再只提取唯一的 `xray` 成员并核对 ELF 位数、字节序和机器架构，最后原子
替换现有文件。任一步失败都保留旧二进制，不再运行时追随 `latest`。其它明确版本必须同时
提供 `XRAY_RELEASE_TAG`（`v数字.数字.数字`）与该架构 ZIP 的 `XRAY_RELEASE_SHA256`；不
接受只有版本没有摘要的覆盖。来源会记录固定版本、资产名和摘要。

这只保护官方二次下载链路，不改变已有 argosbx、系统或手工指定本地 Xray 的信任边界。
版本历史见 [CHANGELOG](CHANGELOG.md)。修改本脚本后，上层
proxy-stack 的 `SIDECAR_SOURCE_SHA256` 也需要在后续授权部署前重新审核，不能自动沿用旧值。

## 版本与系统校时

当前脚本版本为 `2026.09.28.1`，提供无需 root 的 `--version`、`--changelog` 和 `--help`。
管理菜单按显示顺序编号；外部工具应调用管理入口，不依赖旧菜单编号模拟输入。

SS2022 的消息时间差超过 30 秒会被拒绝。安装、参数应用及手动启动/重启包含 SS2022 的
服务前，会检查持续校时条件；普通旧 AEAD 方法和仅 VLESS 配置不受这项门禁影响。只检查
端口或本机 SS 连接不能证明时间准确，因为本机客户端和服务端共享同一错误时钟。

- 预检和详细状态只读显示校时结果。检查同时要求服务运行、持久开机启用和实际同步证据。
- systemd-timesyncd 使用最近一小时内更新的 `/run/systemd/timesync/synchronized`；
  不把保存时间的 `/var/lib/systemd/timesync/clock` 当作成功同步。自定义超长轮询会被保守拒绝。
- chrony 使用有界 `chronyc waitsync`，要求剩余校正量不超过 0.5 秒；ntpd/ntpsec 检查
  leap、stratum 及 offset。systemd 和已有 OpenRC chrony/ntpd 的开机状态均可检查。
- 无法确认时不继续应用代理配置。可使用“检查 / 修复系统校时”：优先启用已有服务、保留
  原时间源；仅在没有已识别服务或未归属校时进程时，才经菜单确认在 apt/systemd 环境安装
  systemd-timesyncd，禁止包移除。启用后最多等待约一分钟，超时明确报告未同步。
- 不覆盖 chrony/ntpd，不强制改时间源，不做一次性 `date -s`，不创建定时校时脚本。
  其它 init/发行版需管理员配置支持的持续校时服务。校时属于系统，代理变更失败或卸载代理
  时不会卸载校时服务。脚本不是持续监控器，服务开启后仍需系统维护保持时间源可达。

机制依据：[SS2022](https://shadowsocks.org/doc/sip022.html)、
[systemd 同步标记](https://github.com/systemd/systemd/blob/v252/man/systemd-timesyncd.service.xml)、
[chrony waitsync](https://chrony-project.org/doc/4.6/chronyc.html)。

## 配置变更如何应用

安装 / 修复、端口、Flow、UUID、ENC、SS 方法/密钥和重写配置使用同一套应用流程：先在
仅 root 可读的目录生成状态、配置及分享链接候选，由当前 Xray 明确按 JSON 格式校验；
校验成功后才替换正式文件。分享链接随配置一起保存，写入失败也触发恢复。systemd 模式会启用开机启动
并重启 sidecar，首次安装、已停止服务和正在运行的服务都适用。pid+cron 模式先确认旧
进程退出，再启动新进程并写入 `@reboot`。因此先装 VLESS 再增加 SS，或
调整端口、Flow、密钥，会应用完整的新配置。独立“服务控制 → 启动”仍只负责启动，已
运行时不会借此重新载入配置。pid+cron 在应用前核对 PID 对应的完整 Xray 命令和配置路径；
PID 被无关进程复用或无法确认身份时拒绝应用，不会自动终止该进程。

配置生成或校验失败时，正式配置和服务状态保持原样。文件应用、服务启用、重启或启动后
存活检查失败时，安装 / 修复返回失败，不更新或展示新分享链接，并尝试恢复旧文件及原有
运行 / 停止、开机启用状态；pid+cron 还恢复变更前的 crontab。不要同时运行另一个管理器
修改同一 sidecar 或这份 crontab。

每次尝试的恢复资料位于输出所示的
`/opt/agsbx-extra/vless-raw-enc/.config-apply.XXXXXXXX/`（目录 `0700`），按执行进度保留
未应用候选、已有文件的 `*.before`、`previous-state` 和受限诊断日志。成功后保留旧资料，确认
不再需要恢复时才清理。如果提示“自动恢复未完成”，依据 `previous-state` 先停止本
sidecar，将存在的 `service.env.before`、`config.json.before` 和服务 unit 的 `.before`
放回原路径；原来不存在的文件应撤除本次新增版本。systemd 再执行 `daemon-reload`，
按记录恢复 enabled / enabled-runtime / disabled 及运行状态；pid+cron 按记录恢复
`crontab.before` 或原来的无 crontab 状态。`share.txt.before` 可用于核对原有分享内容。
这是同一次执行中的尽力恢复，不保证断电或强制杀进程时所有文件一起恢复。

节点名称和 SS 公网入口只更新状态与分享文件，不重启服务。禁用最后一个 SS 协议会写入
无监听的有效配置，停止服务并撤掉它的开机启动；重新启用需走安装 / 修复。配置语法测试
和显示现有分享链接均不重写配置。停止、启动存活检查或计划任务写入失败不再报成功。

这套恢复覆盖上述配置变更入口。此前准备 Xray core 时可能
已经安装或更换二进制；core 不在该恢复范围内，旧配置在新 core 下不能启动时会明确报告
恢复未完成。不要把“候选失败”理解为二进制完全未变。

从 argosbx 同步核心会先验证独立候选及其与当前配置的兼容性，才原子替换二进制；原来
停止的服务保持停止，原来运行的服务才重启。应用失败会尝试恢复旧核心及状态，恢复资料
位于 `bin/.core-sync.*`。这不是任意 Xray 升降级管理器，原 argosbx 的服务和文件不变。

本地回归使用合成配置与服务命令 stub，在仓库根目录运行：

```bash
python3 tools/vps/test-sidecar-config-apply.py
python3 tools/vps/test-sidecar-time-sync.py
python3 tools/vps/test-sidecar-maintenance.py
python3 tools/vps/test-sidecar-xray-download.py
bash -n scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer.sh
```

另有真实核心集成测试，必须显式提供已核验的 Xray，不会静默跳过或自行下载未知版本：

```bash
SIDECAR_XRAY_BIN=/path/to/verified/xray python3 tools/vps/test-sidecar-xray-integration.py
```

测试在临时目录生成随机认证，仅监听回环并访问本机 HTTP/UDP 回显服务，验证候选格式、
SS TCP/UDP、VLESS ENC TCP 及脚本自带连接测试。CI 单独下载经 SHA256 固定的官方版本，
不混入离线测试 job；这仍不代替设备系统服务、公网路径或长期运行验收。

防火墙自动放行保留明确的来源限制，IPv6 来源使用相应规则；命令失败会立即返回失败。
多条规则未承诺跨命令原子性，失败前已成功添加的规则需按所选系统工具检查。脚本不替代
整机防火墙规划；nftables/iptables 临时规则仍需管理员处理持久化及既有链顺序。

部署时按实际条件检查当前配置、服务进程和受影响端口。脚本只做配置校验及启动后一次
存活检查；这些结果不证明客户端认证、UDP 回程或重启后的可用性。真实协议检查有条件
再做，无法验证就记录“未验证”，不为补齐记录强行重启设备。只需端口转发时优先使用
现有转发管理能力，不必增设协议 sidecar。

分享链接、`service.env`、配置和诊断日志可能包含 UUID、密钥或完整 ENC；只在受限终端
查看，不把原文、完整 URI 或凭据摘要写入公开仓库与报告。共享验证结果只记录对象标识、
协议、端口、成功 / 失败和验证范围。

## 整机编排与接管

需要在全新机器部署、接管已有机器或按私有配置复刻甬哥 Argosbx、Proxy Gateway Plus 和
本 sidecar 时，使用
[`scripts/vps/proxy-stack/README.md`](../../vps/proxy-stack/README.md) 的上层编排入口。
该入口只调用本脚本的既有安装和管理方式，不修改本 sidecar 业务脚本；协议端口、公网来源
和整机 input policy 来自
每台机器自己的实例 inventory，不在本 sidecar 脚本中保存机器专用常量。完成上层编排后，
本 sidecar 仍使用本页管理入口独立运维。
