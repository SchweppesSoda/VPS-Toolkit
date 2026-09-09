# VPS-Toolkit maintenance

本仓维护公开的 PO0/VPS 运维源码。用户当前明确范围优先；保留现场验证过的协议、凭据边界和恢复路径。

## 本地工作与完成标准

- 在主目录 `main` 自主完成范围内的编辑、可逆本地生成、相关验证和提交，不在第一版后等待 review。同仓一个写入任务；仅用户要求隔离/并行时另建工作树，完成后按内容收回并清理。
- 开始核对仓库、分支、工作树、已有改动和上游。保留无关改动；需要刷新上游便 fetch，离线注明未核实并继续独立本地工作。安全时 fast-forward，分叉不重置/强推；发布前再确认目标。
- 搜索和测试从变更对象与直接消费者开始；共享契约、重命名/删除或失败证据才扩大。文档检查链接/diff，行为修改跑对应测试，通过后不无理由重复；正式发布门禁保留。
- 完成包括请求落地、相关验证/文档和范围明确的本地提交；报告限制、本地/远程及发布状态。推送、Release、部署沿用会话授权；缺少授权时先准备可审阅的本地结果，仅暂停依赖该授权的动作。
- 临时输出用 `.tmp/`；清理前核对未跟踪、忽略文件及恢复依赖，必要备份放仓库外。保留历史 tag/冻结归档，不整目录忽略共享 `.codex/` 配置。

## 按任务读取

| 范围 | 所需入口 |
| --- | --- |
| PO0 runtime、官方上报、平台/迁移行为 | [PO0 runtime 合同](docs/agent-maintenance/po0-runtime.md) 中相关条目及该客户端 README |
| PO0 资产构建、版本/更新、Release | [构建与发布合同](docs/agent-maintenance/po0-release.md)；对应 manifest/workflow |
| 交互脚本、版本输出、Shell/防火墙实现 | [脚本开发与专项验证](docs/agent-maintenance/script-development.md) 中受影响项 |
| VPS 模块 | `scripts/vps/` 对应模块 README；跨模块约定在 `scripts/vps/docs/` |
| 仅文档/指令 | 当前文档、直接链接与 diff；无需加载全部运行时合同 |

## 源码与维护边界

- `scripts/po0/` 与 `scripts/vps/` 是运行代码；`tools/` 是离线构建/检查工具。Web 工具归 `vps-toolkit-web`，不恢复本仓 web 源或 Pages。
- PO0 模块化 src 与 manifest 是源，Release 单文件与 APK 由现有构建器生成，不手改 staging。
- PO0 只保留官方上报，manager 只管理转发等已保留职责。不得从历史文档恢复自建白名单/上报；保留迁移 guard、更新镜像协议及 nftables 原子应用合同。
- 私有 ProxyConfig 归档、凭据和现场恢复资产不进入公开源码/Release。冻结 tag `archive/po0-full-20260907.1` 保留历史身份。
- 现有正式发布门禁不因本地开发验证精简而取消。文档整理不 bump 运行版本、不重新发布或部署未改脚本。

## 文档归属

根 `README.md`/`README.en.md` 维护项目入口和长期文档索引；模块 README 维护用户行为，technical/design 文档维护实现，CHANGELOG 维护历史。维护指令细节归本文件索引的合同文档，不复制到用户菜单。

修改行为时更新其主文档；新增/移动长期文档时更新直接入口和根索引。按旧文件名或变更词检查相关链接/消费者，不要求每次列全仓 Markdown。优先复用已有主文档，但允许有明确用途的独立子文档。
