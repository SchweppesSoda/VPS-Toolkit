# Script development

仅对受影响脚本及直接共享调用者应用下列要求；文档/注释不触发运行时门禁。测试使用隔离配置和模拟请求，不接触真实官方 API、设备计划或服务。通过相关检查后，只有新修改、失败或未决风险才扩大或重跑。

## 交互

- PO0 Debian reinstall 不给出 raw 在线执行示例；需要 root 且交互的在线脚本，先下载到临时文件再运行。
- 支持 `curl | bash` 的交互脚本必须优先从 `/dev/tty` 读取人机输入。
- 不新增裸 `read -p`；优先使用脚本里已有的 prompt helper。
- 菜单改动必须同步显示编号、分组顺序、输入范围、无效选择提示和 `case` 分支。
- 编号可以重排，但必须按视觉顺序递增，不能为了少改 `case` 保留跳号旧编号。
- 用户可见菜单、状态页、帮助和更新结果里避免使用工程内部表达；不要把英文标准路径、启动器、cron 托管块、配置漂移等内部术语直接暴露给用户，优先使用“标准路径 / 标准安装路径”“计划任务启动文件”“托管片段”“状态提示 / 配置提示”等中文表达。
- 查看类和一次性动作结束后要保留返回暂停，避免输出被菜单刷新冲掉。
- 粘贴私钥等多行输入后要注意输入缓冲，不让残留内容进入主菜单。

## 版本和专项检查

- Shell 改动至少跑 `bash -n` 和 `git diff --check`。
- 修改任何带版本输出的交互脚本、客户端脚本或安装脚本的用户可见行为、菜单、CLI 输出、定时任务或部署命令后，必须同步该脚本自己的版本号变量（如 `SCRIPT_VERSION`、`SCRIPT_RELEASE_DATE` 等）；不只限于 nftables manager。
- 同一功能同时影响 PO0 manager、LAN Worker client、self-report、VPS 工具等多个脚本时，逐个判断并同步受影响脚本的版本号；有 `--version` 的必须用对应脚本的 `--version` 确认输出。
- 带自更新或部署确认需求的版本化脚本应维护脚本内 `CHANGELOG_BEGIN` / `CHANGELOG_END` 当前版本更新内容块；每次 bump 版本时同步写清用户可见变化，不写内部流水账，不把历史条目累积在脚本里。完整版本历史写入对应模块的 `CHANGELOG.md`。
- 自更新入口（如 `--upgrade-self`）成功输出应说明安装路径、版本变化和更新内容；不要只输出内部实现标记。
- 没有自更新入口、依赖 `scp` 上传的脚本（如 PO0 nftables manager）应提供 `--changelog` 或等价只读入口，供上传后确认当前版本更新内容。
- 菜单改动要检查编号、范围、提示和 `case` 一致；能渲染主菜单时，至少输入 `0` 验证可退出。
- 涉及 Bash helper、`set -u`、stdin 或 SSH 调用时，要做运行时回归，不只跑 `bash -n`。
- 涉及 `reload_managed_rules` 或 nftables 应用链路时，必须运行 `tools/po0/test-manager-nft-atomic-reload.sh`，确认预检失败不进入应用、正式刷新只有一个 batch、可选托管表缺失时不生成无效删除。
- 涉及 PowerShell、JavaScript、YAML 或网页工具时，按对应技术文档里的检查方式补验证。
- 修改 `scripts/vps/proxy-stack/` 的实例解析、组件调用或防火墙渲染后，必须运行
  `tools/vps/test-proxy-stack-orchestrator.sh`。`managed` 必须拒绝任何其它 input base chain；
  持久化路径先对 runtime batch 执行一次 `nft -c`，安装两个候选文件后再对最终 boot
  composite 执行一次 `nft -c`，然后且只能执行一次正式 `nft -f`。before-image / EXIT
  guard 只提供同一进程内 best-effort 恢复，两个持久化文件整体不具备断电或 `SIGKILL`
  crash-atomic 保证。Proxy Gateway Plus 必须保持 `external` 防火墙模式，不修改三方组件
  的业务脚本或建立第二套日常管理入口。
