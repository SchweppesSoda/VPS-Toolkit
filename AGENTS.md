# AGENTS.md

本文件给后续维护本仓库的 Codex / agent 使用。改代码前先读相关 README 和技术文档；如果本文件与用户当前明确要求冲突，以用户当前要求为准，但不要忽略这里记录的历史踩坑。

## 仓库结构

- `scripts/po0/`：PO0 相关脚本，包括 nftables 主控、LAN Worker、Egern、自上报、重装和代理增强。
- `scripts/vps/`：通用 VPS 工具，包括 SSH 加固、Fail2ban、3x-ui、ForwardX、REALITY finder。
- `web/`：静态网页工具源码。公开站点由独立 Pages 仓库发布，不要从本仓库根目录启用 GitHub Pages。
- `tools/` 只放离线构建工具。运行在客户端、Worker 或访问设备上的脚本应放到对应 `clients/` 目录。

## PO0 职责边界

- `scripts/po0/nftables/nftables-relay-manager.sh` 运行在 PO0，负责 nftables、白名单、资源任务创建、restricted key wrapper 和资源导入。
- `scripts/po0/nftables/clients/lan-worker/po0-lan-client.sh` 运行在 LAN Worker，负责轮询领取任务、DDNS、自上报接收、WebAuth 接收和本机轮询器。
- Egern 模块只做当前出口 IPv4 的 SSH report，不做 DDNS。
- Self-report 客户端上报到 LAN Worker，再由 LAN Worker SSH 到 PO0。
- PO0 manager 推荐本地 `scp` 上传更新；LAN Worker client 才使用 `po0-lan-client --upgrade-self`。

## 交互脚本规则

- 支持 `curl | bash` 的交互脚本必须优先从 `/dev/tty` 读取人机输入。
- 不新增裸 `read -p`；优先使用脚本里已有的 prompt helper。
- 菜单改动必须同步显示编号、分组顺序、输入范围、无效选择提示和 `case` 分支。
- 编号可以重排，但必须按视觉顺序递增，不能为了少改 `case` 保留跳号旧编号。
- 查看类和一次性动作结束后要保留返回暂停，避免输出被菜单刷新冲掉。
- 粘贴私钥等多行输入后要注意输入缓冲，不让残留内容进入主菜单。

## SSH 与资源任务

- PO0 负责创建资源任务和导入结果；LAN Worker 负责轮询、领取、下载和上传结果。
- 受限 key / wrapper 改动要同时考虑刷新入口和拒绝日志，不能只改脚本正文。
- 资源上传通过 PO0 manager 的受控 stdin 上传路径，不回退到 SCP。
- SSH 参数处理要集中复用 helper，不能各调用点各自拆参数。

## 文档同步

- 根 README、中文 README、模块 README、技术文档按影响范围同步。
- 重要边界、维护流程、验证规则发生变化时，也要同步本文件。
- PO0 Debian reinstall 不写 raw 在线执行命令。
- 需要 root 且交互的在线示例优先下载到临时文件再运行。
- 不把多个脚本命令塞在一个代码块里；按脚本和场景拆分。

## 验证清单

- Shell 改动至少跑 `bash -n` 和 `git diff --check`。
- 菜单改动要检查编号、范围、提示和 `case` 一致；能渲染主菜单时，至少输入 `0` 验证可退出。
- 涉及 Bash helper、`set -u`、stdin 或 SSH 调用时，要做运行时回归，不只跑 `bash -n`。
- 涉及 PowerShell、JavaScript、YAML 或网页工具时，按对应技术文档里的检查方式补验证。

## 提交规则

- 提交前检查 staged 范围，避免混入无关改动。
- 如果工作区已有用户或其它线程留下的改动，不要回滚；只提交本次相关文件。
- Push 前确认远端和分支，尤其是 `origin/main`。
