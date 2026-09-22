# Sidecar 维护记录

## 2026-09-22 — T08 本地补丁应用

用户明确允许 VPS-Toolkit 应用现有补丁。本轮在原 `main` 应用此前隔离候选，
基线 `c62b807b9f10c15f74f907001cfa5c795d979c9e`；应用前逐项核对业务文件与候选
SHA256，保留已有提交。与 T10 文案分别形成 scoped 本地提交，未 push、发布或部署。

本次复跑 11 项合成 ZIP/命令 stub 回归及 shell 语法检查；没有执行真实核心或安装器。
Windows 首次使用默认 GBK 解码导致测试错误，保留日志，显式 `python -X utf8` 后重跑；
没有修改断言。Windows 的合成 `-x` 到 `-f` 测试替换仍不证明 Linux 执行权限。

T08 原方案把“错版本零执行”写得过宽：发布身份、摘要或架构不符零执行；通过信任
校验后的自报版本不符允许一次版本探针，随后拒装保旧。不声称原无条件字面已满足，
也不将摘要匹配当作上游安全证明。Linux CI、真实更新及服务兼容仍未验证。

## 2026-09-21 — T08 复核：候选功能验收后才替换

独立复核发现初版在 SHA/ELF 通过后就替换旧核心，后续 version/uuid/vlessenc
失败仍可能失去旧文件。现有 `verify_xray_binary` 接受候选路径和预期 tag，下载器在
同目录候选上先验证 version 输出对应固定版本，再验证 uuid/vlessenc；全部通过才
原子替换。下载/摘要/架构失败仍不会执行候选，版本或功能不符时旧核心字节保持不变。

11 项合成 ZIP/命令 stub 回归通过，包括错误版本和三个命令分别失败。测试对真实
probe 调用边界进行替换，未执行下载二进制；Windows 下仅将测试副本的 POSIX `-x`
前提替换为 `-f`，真实权限检查由 Linux CI 执行。本轮未运行 Linux CI 或生产服务。
功能命令成功不保证实际配置/流量兼容，部署后的验证、旧配置与核心恢复资料仍需保留。

## 2026-09-21 — T08 官方 Xray 下载校验（仅本地，未部署）

基线 `VPS-Toolkit/main c77998f0b20292e86ea588aec86ea52d2c3c04e3`。上层 proxy-stack 已校验
sidecar 管理脚本，但该脚本随后直接获取 `releases/latest/download`，未核对摘要即复制并
运行 Xray。因此上层 SHA 不能证明最终执行的二进制版本。

官方路径现固定到 `v26.3.27`，为既有 11 种架构资产内置 ZIP SHA256。摘要来自本次读取的
[XTLS 官方 Release 元数据](https://api.github.com/repos/XTLS/Xray-core/releases/tags/v26.3.27)，
对应 [v26.3.27 Release](https://github.com/XTLS/Xray-core/releases/tag/v26.3.27)。只读取元数据，
未下载、安装或执行真实候选。固定摘要保护已审阅字节的一致性，不声称能够独立证明上游未
被攻陷，也不等同于功能或漏洞验证。

下载器先核对固定 tag、架构映射与 SHA256，再流式提取唯一 `xray` 成员、核对 ELF class/
endianness/machine，最后同目录原子替换；其它成员完全不落盘。下载失败、摘要不符、架构
不符、成员重复等均保留旧文件。原 fallback 覆盖前先 `rm` 旧文件的步骤已移除。

对于审阅后需要使用的其它版本，沿用明确版本+摘要的轻量机制：必须同时指定
`XRAY_RELEASE_TAG` 与本机架构 ZIP 的 `XRAY_RELEASE_SHA256`。未增加常驻服务、安装器或
运维框架。现有本地/argosbx 二进制复用路径继续由管理员控制；它们不是本次远端下载校验
覆盖范围。脚本此前没有版本输出/自更新版本变量，本次不新增发布号或触发 PO0 资产生成。

离线验证：`python3 tools/vps/test-sidecar-xray-download.py` 的 9 项测试通过，含 11 架构正例、
错误架构/字节序/非 ELF、坏摘要、无 pin 自定义版本、latest/危险 tag、重复成员、无关越界
成员不解压、下载失败保留旧文件；全部使用合成 ZIP 和模拟下载，未运行候选二进制。
脚本 `bash -n`、Python AST、文档链接和 diff 检查通过。本机 Windows + Git Bash，未做
Linux 实机、Xray 命令、服务启停或真实流量测试。

后续发布/部署需要单独授权：先核对目标 Xray 功能/兼容性，再更新私有 inventory 的
`SIDECAR_SOURCE_SHA256`。本轮不替换已有安装、不更新任何远端管理入口或 inventory。
本地可撤销该 scoped commit；未来部署若功能检查失败，仍需要受保护的旧二进制/配置作为
恢复材料。下载前校验只能保证上述候选安全检查成功前保留旧文件，不能替代部署后的服务
验收与恢复。旧脚本会重新启用 latest 无摘要下载，不应不经审查直接降回该下载行为。
