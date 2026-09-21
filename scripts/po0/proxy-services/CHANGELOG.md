# Sidecar 维护记录

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
