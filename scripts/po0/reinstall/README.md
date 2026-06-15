# PO0 Debian 重装

`po0-debian-reinstall.sh` 用于在 PO0 或腾讯云等 VPS 上，通过 Debian Installer 和 preseed 无人值守重装 Debian 12。

## 来源与差异

本脚本基于 [`vpsbuy/po0`](https://github.com/vpsbuy/po0) 仓库的
[`po0dd.sh`](https://github.com/vpsbuy/po0/blob/main/po0dd.sh) 修改。

当前版本不是上游脚本的原样副本。它保留了 Debian 12、腾讯镜像、`-passwd`、
`-port`、preseed 和 GRUB 启动安装等核心流程，并增加了系统盘反查、腾讯镜像
自动回退、密码哈希写入、依赖安装保护和一次性 GRUB 启动等增强。

## 使用

```bash
cd scripts/po0/reinstall

# 自动生成 root 密码，SSH 使用 22 端口
bash po0-debian-reinstall.sh

# 指定密码或 SSH 端口
bash po0-debian-reinstall.sh -passwd 'YourStrongPassword' -port 60022
```

## 风险

- 脚本会重装系统盘并清除原有数据。
- 执行前确认系统盘识别结果、网络环境和镜像可访问性。
- 建议保留服务商 VNC 或控制台访问能力。
- 不建议把真实密码写入命令历史；更稳妥的做法是让脚本自动生成密码。
