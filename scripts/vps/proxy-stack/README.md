# VPS Proxy Stack Orchestrator

这个模块是整机代理服务的上层编排入口，适用于全新部署、接管已有机器和按私有配置复刻
机器。它不复制三套项目的内部配置，而是通过每台机器自己的实例
inventory 调用各自既有入口：

- 甬哥 [`yonggekkk/argosbx`](https://github.com/yonggekkk/argosbx) 官方脚本；
- [`SchweppesSoda/proxy-gateway-plus`](https://github.com/SchweppesSoda/proxy-gateway-plus)
  的非交互 `install.sh`、`pdg migrate` 或 `pdg update`；
- 本仓库原有
  [`vless-raw-enc-argosbx-enhancer.sh`](../../po0/proxy-services/vless-raw-enc-argosbx-enhancer.sh)
  sidecar 管理入口。

现有 Argosbx、Proxy Gateway Plus 和 sidecar 脚本都保持原样。VPS Toolkit 只负责上层调用、
实例服务清单和可选的整机 input policy，不接管它们各自的协议配置或日常管理命令。完成
部署或接管后，各组件仍可按原项目入口独立运维，不需要通过编排器完成每次日常调整。

当前编排器版本：`2026.07.29+build.1`。

## 选择使用场景

| 场景 | 建议起点 | 关键约束 |
| --- | --- | --- |
| 全新部署 | 从四个示例复制一套机器私有 inventory，填写后依次运行 `validate`、`plan`、`deploy` | 审核并填写每个 enabled 组件的来源 SHA；服务端口和允许来源只来自该机 `services.tsv` |
| 已有机器接管 | 先按现状登记服务，不改变组件；首次使用 `skip` / `keep`，运行 `validate`、`plan`、`status` | enabled 组件仍须填写 SHA；确认 Proxy Gateway Plus 已是 `external` 后，再按需选择维护动作 |
| 按配置复刻 | 从仓库外的密钥管理或私有配置库交付已审核 inventory，在目标机重新校验和预览 | 复用配置意图与已审核 SHA，不把真实 IP、端口、凭据、UUID 或节点复制回本仓库 |

“复刻”是按 inventory 重建所选组件和配置意图，不是复制运行中目录，也不承诺 bit-for-bit
恢复旧软件版本。当前 Proxy Gateway Plus bootstrap 会选择执行时最新的 `v*` 发布；
Argosbx `main` 与 SHA 用于执行前内容审核。若要精确恢复旧组件版本，必须由组件自身提供
锁版接口或经过审查的归档来源，VPS Toolkit 不代替该能力。接管已有机器时不要先用 `rep`
或 `update` 猜测现状；应先使用不改组件的动作建立清单，再在维护窗口逐项切换。

## 文件

- `proxy-stack-orchestrator.sh`：`validate`、`plan`、`deploy`、`status`、防火墙渲染和显式应用入口。
- `proxy-stack.inventory.example.conf`：组件、来源和整机防火墙模式示例。
- `argosbx.example.env`：传给 Argosbx 官方脚本的白名单变量示例。
- `proxy-gateway-plus.example.env`：传给 Proxy Gateway Plus 标准安装接口的变量示例。
- `services.example.tsv`：实例服务、协议、端口和允许来源示例。

示例文件包含不可直接部署的尖括号占位符。不要在仓库中保存真实机器 IP、端口清单、
Telegram Token、用户 ID、UUID、`agk`、密钥或节点链接。

## 准备 inventory

在部署侧建立一个不进仓库的私有目录，复制四个示例文件并去掉 `.example`。下面的 `/etc`
示例应全部由 root 操作：私有目录及其目录链须由 root 所有、不是 symlink，且组和其他用户
不可写；建议目标目录使用 `root:root 0700`。两个组件 env 必须是普通非 symlink 文件并使用
`root:root 0600`。变更时主 inventory 和 `services.tsv` 也必须由 root 所有、不是 symlink，
且组和其他用户不可写；下面统一使用更严格的 `0600`。所有相对路径都以主 inventory
所在目录为基准。

```bash
sudo install -d -o root -g root -m 0700 /etc/vps-toolkit/proxy-stack
```

```bash
sudo install -o root -g root -m 0600 proxy-stack.inventory.example.conf /etc/vps-toolkit/proxy-stack/stack.conf
```

```bash
sudo install -o root -g root -m 0600 argosbx.example.env /etc/vps-toolkit/proxy-stack/argosbx.env
```

```bash
sudo install -o root -g root -m 0600 proxy-gateway-plus.example.env /etc/vps-toolkit/proxy-stack/proxy-gateway-plus.env
```

```bash
sudo install -o root -g root -m 0600 services.example.tsv /etc/vps-toolkit/proxy-stack/services.tsv
```

然后在 `stack.conf` 中把 `SERVICES_FILE`、`ARGOSBX_VARIABLES_FILE` 和 `PDG_ENV_FILE`
同步改为实例文件名，并填写各组件配置。两个 `.example.env` 故意只有注释，
`services.example.tsv` 以及三个 SHA 字段也故意使用无法通过校验的占位符；示例直接
`deploy` 必须失败，这是为了避免把说明值误认成生产配置。

配置是严格的逐行 `KEY=VALUE`，按字面解析，不执行 shell 展开；未知 key、重复 key、空的
组件值和控制字符都会拒绝。Argosbx 变量和 Proxy Gateway Plus 变量各有固定白名单，
不会 `source` 或 `eval` 实例文件。

## 先校验与预览

校验不会下载脚本、部署服务或修改防火墙：

```bash
sudo bash proxy-stack-orchestrator.sh --inventory /etc/vps-toolkit/proxy-stack/stack.conf validate
```

预览只显示组件开关和服务接口，不显示组件环境值，避免把 Token 或密钥带入终端记录：

```bash
sudo bash proxy-stack-orchestrator.sh --inventory /etc/vps-toolkit/proxy-stack/stack.conf plan
```

在 `managed` 模式还可以单独查看将要生成的 nftables 表：

```bash
sudo bash proxy-stack-orchestrator.sh --inventory /etc/vps-toolkit/proxy-stack/stack.conf render-firewall
```

该命令输出可重复载入的完整 batch：先以幂等 `add table` 声明表、再删除该表，最后写入
完整定义。runtime apply 和持久化 include 使用完全相同的 batch，不是只能首载一次的
单独 `table { ... }` 片段。

## 部署

建议从本地仓库复制编排器到新机，先人工检查，再以 root 调用：

```bash
sudo bash proxy-stack-orchestrator.sh --inventory /etc/vps-toolkit/proxy-stack/stack.conf deploy
```

执行顺序固定为 Argosbx、Proxy Gateway Plus、sidecar、整机防火墙。防火墙最后应用，避免在
远程管理服务尚未就绪时提前切断连接。三方组件没有跨项目事务或统一回滚；编排器能检测到
的失败主要是子命令非零退出、管理入口和少量边界状态，检测到后会停止，但不撤销此前已完成
的组件，也不提供深度协议健康保证。部署结束后必须分别通过 `agsbx`、`pdg`、Proxy Gateway
Plus Web / Bot 和 sidecar 原管理入口复核实际状态。

`plan` 会隐藏组件环境值，`status` 也不会主动执行可能输出节点的命令；但 `deploy` 调用的
上游脚本 stdout / stderr 不会被过滤，可能包含 UUID、节点链接或其它实例信息。只应在受信
终端部署，不要把完整输出写入公共 CI、cloud-init 或集中日志。

### Argosbx

`ARGOSBX_SOURCE_URL` 只允许官方
`https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh`。编排器先下载到
临时文件，再以 Argosbx 原生变量白名单执行，不复制、修改或重新解释其脚本参数。
`argosbx.example.env` 中列出的 key 与核心脚本白名单一致，参数含义和有效取值仍以
`yonggekkk/argosbx` 官方脚本为准。至少要在 `ARGOSBX_VARIABLES_FILE` 启用一个协议端口
变量；`agk`、UUID 和其它机器专用值只能写入私有实例文件。

已安装时：

- `ARGOSBX_EXISTING_ACTION=skip`：保持现状；
- `ARGOSBX_EXISTING_ACTION=rep`：用实例变量调用官方脚本的 `rep`。

部署后继续使用官方管理方式：

```bash
agsbx list
```

```bash
agsbx res
```

```bash
agsbx upx
```

```bash
agsbx ups
```

```bash
agsbx del
```

重置协议时，仍按 Argosbx 原方式在命令前提供变量并运行 `agsbx rep`。

### Proxy Gateway Plus

新机通过 `PDG_NONINTERACTIVE=1` 调用项目自己的 `install.sh`。实例配置必须显式写：

```text
PDG_FIREWALL_MODE=external
```

编排器也会在最终 argv 环境中强制该值，防止 Proxy Gateway Plus 接管整机 input policy。
它仍保留项目自身 source-scoped REDIRECT / TPROXY 数据面；公网服务暴露和主机 input policy
只由本模块的 services inventory 或外部管理员负责。

检测到 `/usr/local/bin/pdg` 时，根据 `PDG_EXISTING_ACTION` 调用 `skip`、`pdg migrate`
或 `pdg update`，不再覆盖执行安装器。采用已有部署前还会交叉检查 firewall mode marker 与
`profile.env`；只有可证明为 `external` 且状态一致才继续，避免叠加两个整机 input hook。
已有机器上的 `pdg update` 遵循 Proxy Gateway Plus 自身的 release 更新机制，不使用
inventory 中的 bootstrap launcher SHA 锁定其更新内容。

### VLESS RAW ENC sidecar

编排器按原 README 的永久入口方式安装
`vless-raw-enc-argosbx-enhancer`，不改 sidecar 脚本和 `/root/agsbx`：

- `SIDECAR_EXISTING_ACTION=keep`：已有入口不刷新；
- `SIDECAR_EXISTING_ACTION=refresh`：从配置来源重新安装管理入口；
- `SIDECAR_RUN_MODE=interactive`：部署时进入原管理菜单；
- `SIDECAR_RUN_MODE=install-only`：只安装管理入口，稍后人工运行。

sidecar 协议仍由原菜单安装、修复和管理。退出菜单后，编排器才会应用整机服务清单。
VLESS RAW ENC 的外层 socket 只监听 TCP；VLESS TCP 会话可以承载 UDP 转发语义，但这不会
创建同端口 UDP listener，因此 services inventory 只为 VLESS 写 TCP 行。sidecar SS2022
会实际监听 TCP 和 UDP，必须写两行。

## 服务清单与整机防火墙

`services.tsv` 每行恰好五个 TAB 分隔字段：

```text
component	name	protocol	port	source-cidrs
```

- `component`：`host`、`argosbx`、`pdg` 或 `sidecar`；关闭的组件不会渲染对应规则。
- `name`：稳定、可审计的服务名。
- `protocol`：`tcp`、`udp` 或 `any`。
- `port`：TCP/UDP 使用一个十进制端口；`any` 必须使用 `*`。
- `source-cidrs`：一个或多个 IPv4/IPv6 CIDR，多个值用英文逗号分隔。

TCP+UDP 服务必须写两行。SSH、Argosbx、sidecar、Web 管理面或未来新增服务的实际端口和来源
都只写在实例清单中；编排器没有机器专用 IP 或端口常量。
VLESS 只写物理 TCP listener，不能因为它支持 UDP 转发语义而伪造 UDP 行。只有 SS2022 等
确实同时监听 TCP/UDP 的服务才写两行。`any + *` 会允许指定来源访问主机所有协议和端口，
只适合该来源已被整机完全信任的特殊情况；常规实例应像示例一样逐 socket 最小放行。

来源 CIDR 使用系统 Python `ipaddress.ip_network(..., strict=True)` 校验，并要求输入就是
规范网络字符串。含 host bits、非规范 IPv6 或无效网络会在 `validate` 阶段拒绝。

`HOST_FIREWALL_MODE=managed` 时，编排器生成独立的
`inet vps_toolkit_proxy_stack` input hook。`drop` policy 必须声明
`REMOTE_ADMIN_SERVICE`，且清单中必须存在同名启用规则，否则 fail closed。应用流程为：

1. 从启用组件的声明生成 `add table`、`delete table` 和完整定义组成的临时 batch；
2. 拒绝当前 ruleset 中任何不属于本模块的 input base chain，再以第一次
   `nft -c -f` 预检 runtime batch；
3. `HOST_FIREWALL_PERSIST=1` 时保留 policy 与 `/etc/nftables.conf` 的 before-image，
   逐个以同目录候选文件替换 policy 和主 include，再对落盘后的最终 boot composite 执行
   第二次 `nft -c -f /etc/nftables.conf` 预检；
4. 两次预检都成功后，只执行一次正式 `nft -f`，替换 live 本模块表；
5. 正常错误和同一 Bash 进程可执行 `EXIT` cleanup 的退出路径会 best-effort 恢复
   before-image；恢复不执行第二次正式 nft apply。

before-image 与 `EXIT` guard 只是进程内 best-effort 保护，不是 crash-atomic 保证。policy
文件和 `/etc/nftables.conf` 是两个分别原子替换的文件，二者整体没有原子事务；断电或
`SIGKILL` 可能发生在两次替换之间，来不及执行 cleanup，留下不一致的启动配置。持久化
变更后仍须人工检查最终文件，并保留服务商控制台或恢复通道。

`PROXY_STACK_NFTABLES_MAIN_CONFIG` 和 `PROXY_STACK_NFTABLES_POLICY_FILE` 只用于受控的
persistence path 覆盖；它们必须是由安全字符组成的规范绝对路径，不能使用 nft
`include` glob / 通配模式。通常不要覆盖默认路径。

只重新应用整机服务清单：

```bash
sudo bash proxy-stack-orchestrator.sh --inventory /etc/vps-toolkit/proxy-stack/stack.conf firewall-apply
```

`HOST_FIREWALL_MODE=external` 时，编排器不修改 input policy。此时上层防火墙仍须根据同一实例
信息显式放行服务，不能把 Proxy Gateway Plus 的 `external` 当作默认开放。

`managed` 是排他模式：无论其它 input base chain 的 policy、priority 或规则内容是什么，
只要存在就拒绝应用。部署前必须先把所需规则合并进本模块清单或移除其它 input base
chain；编排器不会自动合并第三方防火墙。这个检查不证明服务正在监听，也不替代云厂商
安全组和上游网络策略核验。

端口分层建议见
[`scripts/vps/docs/vps-port-firewall-summary.md`](../docs/vps-port-firewall-summary.md)。

## 状态与日常管理

状态入口只显示管理命令、sidecar 服务和本模块 nftables 表是否存在，不执行 `agsbx list`
等可能输出节点链接的命令：

```bash
sudo bash proxy-stack-orchestrator.sh --inventory /etc/vps-toolkit/proxy-stack/stack.conf status
```

该状态入口是浅层存在性检查，不是三方组件的深度健康检查。

日常协议调整继续使用 `agsbx`、`pdg`、Proxy Gateway Plus 的 Web / Bot 和
`vless-raw-enc-argosbx-enhancer`；编排器不建立第二套管理面。

## 来源校验与安全边界

三个远端入口都来自实例 inventory，且必须精确匹配各项目的官方 HTTPS raw URL；sidecar
安装路径也只能是现有 README 的标准路径。可选 `PDG_REPO_URL` 只允许本 fork 的官方 Git
URL。每个 enabled 组件都必须填写对应的 64 位 SHA，即使 existing action 是 `skip` 或
`keep`；仓库示例使用无效占位符，正式实例须在维护窗口下载官方来源、人工审查内容，再把
审核所得 SHA256 写入私有 `stack.conf`。

| 字段 | SHA 证明的范围 | 不涵盖的范围 |
| --- | --- | --- |
| `ARGOSBX_SOURCE_SHA256` | 新装或 `rep` 时下载并执行的官方 `argosbx.sh` bootstrap 字节 | Argosbx 随后下载的二进制、配置来源或其它下游内容 |
| `PDG_INSTALL_SHA256` | 新装时执行的 Proxy Gateway Plus `install.sh` bootstrap launcher 字节 | 已有机器的 `pdg migrate` / `pdg update`；后者遵循 PDG 自身 release 机制 |
| `SIDECAR_SOURCE_SHA256` | 新装或 refresh 时下载的 sidecar 管理脚本字节 | sidecar 后续下载或复用的 Xray 等下游内容 |

来源更新后应重新审核并更新 SHA，不能为了通过部署而清空校验值。SHA 是执行前 attestation，
不是整个供应链锁版；VPS Toolkit 不保证组件后续下载的字节或最终软件版本。精确旧版本复刻
仍须依赖组件自身经过审查的锁版接口或归档能力。

`managed + drop` 会影响整机远程访问。首次应用前必须检查 `plan` 和 `render-firewall`，
并准备服务商控制台或其它恢复通道。存在 `SSH_CONNECTION` 时，编排器只用其来源 IP 和
服务端口核对 `REMOTE_ADMIN_SERVICE` 声明，降低明显误锁风险；这不是身份认证或授权机制，
也不证明 SSH 之后仍可达。没有 SSH 会话时只会警告后继续，因此必须从控制台或恢复通道
操作并确认规则。云厂商安全组仍需按实例实际端口单独维护。
