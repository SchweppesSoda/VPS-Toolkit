# setup-ssh-key-only-full.sh 技术文档

## 定位

`setup-ssh-key-only-full.sh` 是一个 SSH 登录加固脚本。它在当前 SSH 会话内运行，为指定系统用户写入 OpenSSH 公钥，然后把 sshd 切换到一个随机高位端口，并在新端口上强制使用公钥认证。

脚本同时处理 nftables 端口放行和旧端口收口，但它不负责云厂商安全组。云控制台或 VPS 面板里的端口放行仍需要人工处理。

## 设计目标

- 避免继续暴露常见 SSH 端口。
- 确保目标账号具备可用公钥后，再切换 sshd 配置。
- 通过 `sshd -t` 和 `sshd -T` 校验配置，降低锁死 SSH 的风险。
- 先放行新端口，再 reload/restart sshd，最后处理旧端口。
- 失败时恢复 `sshd_config` 备份，并尽量撤销本次新增的 nft 规则。
- 保留当前 SSH 会话，让用户在新终端验证新端口后再关闭旧会话。

## 前置条件

脚本要求：

- 以 root 身份运行。
- 在已有 SSH 会话中运行，因为它依赖 `SSH_CONNECTION` 判断当前服务端 SSH 端口。
- 系统存在 `/etc/ssh/sshd_config`。
- 系统可找到 `sshd`，优先使用 `command -v sshd`，其次尝试 `/usr/sbin/sshd`。

如果缺少 `nft` 或找不到可操作的 nftables input hook 链，脚本不会直接中断，而是展示风险并要求用户确认是否继续只修改 sshd。

## 端口选择策略

脚本内置了多个分散的小范围端口池：

```text
23117-23479
26743-27189
35831-36277
41657-42019
48791-49237
56329-56791
```

它会随机选择一个范围，再在范围内随机取端口。排除端口包括 `80`、`443`、`8080`、`8443`、`8000`、`1080`。选择时还会跳过当前 SSH 端口，并用 `ss`、`lsof` 或 `netstat` 检查本机 TCP 监听占用。

最多尝试 300 次。若无法找到可用端口，脚本中止。

## 账号和公钥处理

脚本交互式要求用户输入目标系统账号和 OpenSSH 公钥：

1. 通过 `id <user>` 确认账号存在。
2. 通过 `getent passwd` 或 `/etc/passwd` 获取 home 目录。
3. 创建或修正 `~/.ssh` 和 `authorized_keys` 权限。
4. 校验公钥前缀是否像标准 OpenSSH 公钥。
5. 如果 `authorized_keys` 已存在内容，询问是否替换旧公钥。

权限处理如下：

- `.ssh` 使用 `700`。
- `authorized_keys` 使用 `600`。
- owner/group 设为目标用户及其主组。

如果选择替换旧公钥，脚本先备份 `authorized_keys`，再只保留本次输入的公钥。否则会去重追加。

## sshd_config 重写模型

脚本使用两组标记块管理自身写入内容：

- 全局端口块：`SETUP_SSH_KEY_ONLY_FULL GLOBAL`
- Match 块：`SETUP_SSH_KEY_ONLY_FULL MATCH`

同时兼容清理旧版本可能留下的 `KEY_ONLY_PORT_<port>` 标记块。

重写策略由 `write_sshd_config_for_new_port` 完成：

- 删除原文件中未注释的 `Port` 行。
- 删除脚本自身旧标记块。
- 在第一个 `Match` 块之前插入新的全局 `Port <new_port>`。
- 在文件末尾追加 `Match LocalPort <new_port>`。

追加的 Match 块强制：

```text
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
AuthenticationMethods publickey
PermitRootLogin prohibit-password
```

这意味着新端口只允许公钥认证。`PermitRootLogin prohibit-password` 保留 root 公钥登录能力，但禁止 root 密码登录。

## 配置校验和回滚

脚本在改写前备份：

```text
/etc/ssh/sshd_config.bak.<timestamp>
```

改写后执行：

- `sshd -t`：语法检查。
- `sshd -T`：读取生效配置，确认新端口出现在 effective ports 中。

如果语法检查失败，或 `sshd -T` 没看到新端口，脚本会恢复备份并退出。

如果 reload/restart SSH 服务失败，脚本也会恢复备份，尝试重新加载 SSH，并删除本次刚添加的新端口 nft accept 规则。

## nftables 处理

脚本优先检测现有 nftables input hook 链：

```bash
nft -a list ruleset
```

找到后记录 family/table/chain，用于新旧端口规则处理。若没有找到 input hook 链，脚本准备创建专用链：

```text
table inet setup_ssh_key_only
chain input { type filter hook input priority -50; policy accept; }
```

端口变更顺序是：

1. 在 reload sshd 前，确认或插入新端口 TCP accept 规则。
2. reload/restart sshd 成功后，删除旧端口的简单 accept 规则。
3. 为旧端口添加 `ct state new tcp dport <old_port> drop`，阻断旧端口新连接。

脚本会检测复杂集合/范围规则中是否仍包含旧端口，并提示用户手动检查。它不会自动解析和重写复杂 nft set 或范围规则。

## SSH 服务重载策略

`reload_ssh_service` 依次尝试：

- `systemctl reload ssh`
- `systemctl reload sshd`
- `service ssh reload`
- `service sshd reload`
- `systemctl restart ssh`
- `systemctl restart sshd`
- `service ssh restart`
- `service sshd restart`

成功后记录实际服务名和动作，供输出展示。这样可以兼容 Debian/Ubuntu 常用的 `ssh` 服务名和 RHEL/CentOS 常用的 `sshd` 服务名。

## 输出和验证建议

脚本最后输出：

- 旧 SSH 端口。
- 新 SSH 端口。
- 目标账号。
- 新端口登录命令。
- 密码登录失败测试命令。
- 手动回滚命令。

用户必须保留当前 SSH 会话，再开新终端测试：

```bash
ssh -p <new_port> <user>@YOUR_VPS_IP
```

并测试密码登录应失败：

```bash
ssh -p <new_port> -o PreferredAuthentications=password -o PubkeyAuthentication=no <user>@YOUR_VPS_IP
```

确认新端口和公钥登录可用后，再关闭旧会话。

## 风险和边界

- 云厂商安全组不由脚本处理。新端口如果没在控制台放行，外部仍可能无法连接。
- nftables 规则默认是运行时规则，重启后是否保留取决于系统的 nftables 持久化配置。
- 如果 sshd 通过 `Include` 引入额外 `Port`，脚本会提示 `sshd -T` 中仍存在旧端口，但不会自动改写 Include 文件。
- 如果当前系统使用非 nftables 防火墙，脚本不会自动处理 iptables、ufw 或 firewalld。
- 脚本会改写 `/etc/ssh/sshd_config` 主文件，虽然有备份和校验，但仍应在稳定 SSH 会话中操作。

## 设计取舍

脚本选择“当前会话内原子化推进”：先准备公钥，再选择新端口，再备份和改写 sshd 配置，再放行新端口，最后重载服务并收口旧端口。这个顺序的重点是降低锁死风险。

它没有尝试做完整防火墙持久化，也没有跨文件重写所有 sshd Include 配置。原因是这些行为和发行版、镜像、面板环境强相关，自动化过度反而更容易造成不可预期结果。

