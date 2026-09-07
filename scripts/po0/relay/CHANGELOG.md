# PO0 变更记录

## 2026.09.08+build.1 / OpenWrt 2026.09.08-r1

- manager 精简为转发管理，保留 NAT/SNAT/MSS、BBR、诊断、备份与鉴权更新；迁移检查阻止静默移除仍在使用的保护。
- LAN Worker 精简为固定脚本更新镜像，保留现有 HTTP 配对和服务入口；原官方账号显式迁移至同机官方客户端。
- Windows、macOS、Linux、OpenWrt、Egern、Stash、Loon 只保留官方上报；清理自建界面、请求引擎和旧任务，迁移保留账号、槽位、名称、停用选择与网络行为。
- Stash 首页使用只读缓存 Tile；Egern 小组件全部空间用于官方状态；Loon 管理页移除自建入口。
- 旧接收器、DDNS、WebAuth、来源学习、iplist/ipdb 构建与任务退出主线。协议回归保留最小旧对端测试夹具。

## 固定旧版归档

此前全部变更记录、完整源码、五个脚本和 APK 保存在 [archive/po0-full-20260907.1](https://github.com/SchweppesSoda/VPS-Toolkit/releases/tag/archive/po0-full-20260907.1)。归档基于提交 `30936db`，不承接新功能，始终非 Latest。恢复前核对随附 manifest、校验文件与 RESTORE.md。
