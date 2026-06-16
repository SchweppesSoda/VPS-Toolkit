# Fail2ban 安装与使用终极笔记

本文档旨在提供一个在主流 Linux 服务器（如 CentOS/RHEL、Debian/Ubuntu）上安装、配置与管理 **Fail2ban** 的完整指南。

Fail2ban 是一个开源入侵防御系统，通过监控日志文件检测恶意行为模式（如暴力破解、扫描），并自动调用防火墙封禁攻击 IP，提高服务器安全性。([blog.wlens.top](https://blog.wlens.top/posts/fail2ban-%E5%AE%89%E8%A3%85%E4%B8%8E%E4%BD%BF%E7%94%A8%E7%BB%88%E6%9E%81%E7%AC%94%E8%AE%B0/?utm_source=chatgpt.com))

---

## 目录

1. 安装 Fail2ban
2. 基础配置
3. 定制监狱（Jails）
4. 规则与过滤器（Filters）
5. 管理与常用命令
6. 典型场景配置
7. 进阶提示

---

## 1. 安装 Fail2ban

Fail2ban 通常已包含于大部分 Linux 发行版的软件源中，可通过包管理器直接安装。([zhuanlan.zhihu.com](https://zhuanlan.zhihu.com/p/608465251?utm_source=chatgpt.com))

### 在 CentOS / RHEL 系统上

```bash
sudo yum install -y epel-release
sudo yum install -y fail2ban
```

### 在 Debian / Ubuntu 系统上

```bash
sudo apt update
sudo apt install -y fail2ban
```

### 启动并开机自启

```bash
sudo systemctl start fail2ban
sudo systemctl enable fail2ban
```

检查状态：

```bash
sudo systemctl status fail2ban
```

---

## 2. 基础配置

Fail2ban 的核心配置文件是：

```text
/etc/fail2ban/jail.conf
```

**不要直接修改这个文件**，应复制为本地配置：

```bash
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
```

然后编辑：

```bash
sudo nano /etc/fail2ban/jail.local
```

本地配置优先级高于原始配置，这样升级软件不会覆盖你的自定义设置。([blog.wlens.top](https://blog.wlens.top/posts/fail2ban-%E5%AE%89%E8%A3%85%E4%B8%8E%E4%BD%BF%E7%94%A8%E7%BB%88%E6%9E%81%E7%AC%94%E8%AE%B0/?utm_source=chatgpt.com))

---

## 3. 核心通用配置项

Fail2ban 默认配置如下：

```ini
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1
bantime  = 1d           # 封禁时长
findtime = 10m          # 检测窗口
maxretry = 5            # 最大失败次数
action   = %(action_)s  # 默认封禁动作
```

解释：

- **ignoreip**：永不封禁白名单 IP
- **bantime**：封禁时间，可用单位：s/m/h/d/w
- **findtime**：统计失败次数的时间窗口
- **maxretry**：在 findtime 内允许失败次数（超过则封禁）
- **action**：执行动作（通常是更新防火墙规则）([blog.itwray.com](https://blog.itwray.com/2024/09/23/fail2ban-use/index.html?utm_source=chatgpt.com))

### 推荐默认配置

如果只是给 VPS 做 SSH 防爆破，建议优先使用仓库里的脚本默认模式：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/fail2ban/fail2ban.sh | sudo bash -s -- default
```

脚本会把配置写到：

```text
/etc/fail2ban/jail.d/99-local-hardening.conf
```

脚本推荐值如下，不确定就一路回车，最后确认写入：

```ini
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1 198.51.100.9
# 脚本会自动把当前 SSH 客户端 IP 加入白名单
bantime  = 1w
findtime = 10m
maxretry = 3

[sshd]
enabled = true
port    = 2222
# 脚本会自动检测当前 SSH 端口
filter  = sshd
# 脚本会自动检测 /var/log/auth.log、/var/log/secure，
# 如果都没有，则自动改用 systemd backend
maxretry = 3
```

这套默认值的取向是：SSH 输错 3 次就封一周，同时自动白名单当前管理 IP，降低误封自己的风险。

默认模式还会做两件事：

- 自动探测当前 SSH 端口、当前 SSH 客户端 IP、SSH 日志来源。
- 如果检测到 nginx 错误日志，并且系统存在 `nginx-http-auth` 过滤器，就自动启用 nginx 防护并写入检测到的真实日志路径。

如果你想保留这些推荐值，但逐项手动改，可以用高级模式下的自定义配置：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/fail2ban/fail2ban.sh | sudo bash -s -- install
```

如果你想从菜单里选，脚本现在会先给你两个入口：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/fail2ban/fail2ban.sh | sudo bash -s --
```

- 默认模式：一键推荐配置，自动探测，只在最后确认。
- 高级模式：逐项自定义，外加状态、解封、日志、重启、回滚这些维护功能。

如果脚本写入后需要回滚到上一次配置：

```bash
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/fail2ban/fail2ban.sh | sudo bash -s -- rollback
```

---

## 4. 定制监狱（Jails）

监狱是 Fail2ban 的基本模块，每个 jail 负责一种服务/场景：

### 典型 SSH 监狱

```ini
[sshd]
enabled = true
port    = ssh
filter  = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime  = 1w
```

说明：

- 启用对 SSH 登录失败的监控
- 3 次失败则封禁，一周内禁止访问服务器 SSH

---

## 5. 过滤器（Filters）基础

Fail2ban 通过过滤器文件分析日志模式（定义在 `/etc/fail2ban/filter.d/`）：

例如 `sshd.conf` 过滤器会匹配 ssh 登录失败的日志。

你也可以自定义过滤器用于 nginx、数据库、web 访问等检测。([blog.wlens.top](https://blog.wlens.top/posts/fail2ban-%E5%AE%89%E8%A3%85%E4%B8%8E%E4%BD%BF%E7%94%A8%E7%BB%88%E6%9E%81%E7%AC%94%E8%AE%B0/?utm_source=chatgpt.com))

---

## 6. 管理与常用命令

查看当前活动监狱：

```bash
sudo fail2ban-client status
```

查看某个监狱细节：

```bash
sudo fail2ban-client status sshd
```

手动解封 IP：

```bash
sudo fail2ban-client set sshd unbanip <IP地址>
```

重启 Fail2ban：

```bash
sudo systemctl restart fail2ban
```

---

## 7. 典型场景配置示例

### 7.1 防 SSH 暴力破解

在 `jail.local` 中添加：

```ini
[sshd]
enabled  = true
port     = 22
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 3
bantime  = 1w
```

---

### 7.2 保护 Web 服务（如 nginx）

```ini
[nginx-http-auth]
enabled = true
port    = http,https
filter  = nginx-http-auth
logpath = /var/log/nginx/error.log
maxretry = 3
```

上述配置会监听 nginx 错误日志中 HTTP 认证失败的条目，并封禁频繁触发的 IP。([blog.wlens.top](https://blog.wlens.top/posts/fail2ban-%E5%AE%89%E8%A3%85%E4%B8%8E%E4%BD%BF%E7%94%A8%E7%BB%88%E6%9E%81%E7%AC%94%E8%AE%B0/?utm_source=chatgpt.com))

---

## 8. 进阶提示

- **不要误封自己**：确保 `ignoreip` 包含管理 IP
- **日志路径**：各系统日志路径可能不同（Ubuntu 通常 `/var/log/auth.log`，CentOS 通常 `/var/log/secure`）
- **测试规则**：修改配置后先重启 Fail2ban 并查看状态确认没有报错
- **邮件通知**：可以配置发送邮件，当触发封禁时报警

---

## 结语

Fail2ban 是服务端防御工具中非常实用的一环，它通过分析日志自动响应异常访问行为，从而减轻人工监控压力、增强服务器安全性。

按上面方法配置后，你的服务器将具备初级自动防护能力，并且能针对不同服务灵活扩展规则。([blog.wlens.top](https://blog.wlens.top/posts/fail2ban-%E5%AE%89%E8%A3%85%E4%B8%8E%E4%BD%BF%E7%94%A8%E7%BB%88%E6%9E%81%E7%AC%94%E8%AE%B0/?utm_source=chatgpt.com))
