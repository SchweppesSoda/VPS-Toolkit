# PO0 Debian 重装

`po0-debian-reinstall.sh` 用于在 PO0 或腾讯云等 VPS 上，通过 Debian Installer 和 preseed 无人值守重装 Debian 12。

## 来源与差异

本脚本基于 [`vpsbuy/po0`](https://github.com/vpsbuy/po0) 仓库的
[`po0dd.sh`](https://github.com/vpsbuy/po0/blob/main/po0dd.sh) 修改。

当前版本不是上游脚本的原样副本。它保留了 Debian 12、腾讯镜像、`-passwd`、
`-port`、preseed 和 GRUB 启动安装等核心流程，并增加了系统盘反查、腾讯镜像
自动回退、密码哈希写入、依赖安装保护和一次性 GRUB 启动等增强。

当前脚本版本为 `2026.07.22+build.2`。本版修正了两项启动参数问题：

- `DISABLE_IPV6=false` 时不再写入 `ipv6.disable=1`；保持 `true` 时仍禁用安装过程 IPv6。
- 自动识别独立 `/boot`：独立分区使用 GRUB 视角的 `/debian-autoinstall/...`，非独立分区继续使用 `/boot/debian-autoinstall/...`。

## 设计边界

脚本仍按 PO0 特殊重装环境的既定设计，通过 HTTP 从腾讯镜像下载 Debian Installer 的 kernel/initrd，且不增加签名或哈希校验。本版没有改变下载源、协议或校验策略。

上传后可以先用 `bash po0-debian-reinstall.sh --version` 和 `bash po0-debian-reinstall.sh --changelog` 确认脚本版本及当前改动；这两个入口只读，不会进入磁盘检测或重装流程。

## 使用

推荐先上传重装脚本，再在 PO0 上运行：

```bash
scp scripts/po0/reinstall/po0-debian-reinstall.sh root@<PO0_HOST>:/root/po0-debian-reinstall.sh

# 自动生成 root 密码，SSH 使用 22 端口
ssh root@<PO0_HOST> 'chmod +x /root/po0-debian-reinstall.sh && bash /root/po0-debian-reinstall.sh'

# 指定密码或 SSH 端口
ssh root@<PO0_HOST> 'bash /root/po0-debian-reinstall.sh -passwd "YourStrongPassword" -port 60022'
```

## 风险

- 脚本会重装系统盘并清除原有数据。
- 执行前确认系统盘识别结果、网络环境和镜像可访问性。
- 建议保留服务商 VNC 或控制台访问能力。
- 不建议把真实密码写入命令历史；更稳妥的做法是让脚本自动生成密码。
