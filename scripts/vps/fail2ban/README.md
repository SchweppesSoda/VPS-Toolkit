# Fail2ban Scripts

维护状态：低频按需维护。已有部署可以继续使用；新环境不把它作为本仓库的默认安全基线，是否安装应结合发行版、防火墙和现有登录防护单独判断。

这个目录保存 Fail2ban 相关资产：

- `fail2ban.sh`：菜单式 Fail2ban 安装、配置和维护脚本。
- `fail2ban-guide.md`：Fail2ban 安装与使用说明。

建议入口：

```bash
tmp="$(mktemp)"
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/fail2ban/fail2ban.sh -o "$tmp"
sudo bash "$tmp" default
rm -f "$tmp"
```

需要逐项配置和维护菜单时，把 `default` 改成 `advanced`。脚本会先在临时配置副本中运行 Fail2ban 检查，通过后再原子替换正式配置；启用或重启失败时会尝试恢复原配置。
