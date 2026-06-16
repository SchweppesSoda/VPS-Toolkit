# SSH Key Only Hardening

这个目录保存 SSH 公钥登录加固相关资产：

- `setup-ssh-key-only-full.sh`：为指定用户新增或替换 SSH 登录公钥，切换随机或指定 SSH 新端口，并强制新端口使用公钥认证。
- `setup-ssh-key-only-full-technical.md`：脚本技术设计说明。

脚本写入的是 `authorized_keys` 里的登录公钥。私钥应保存在本地机器，不要粘贴到 VPS 或脚本里。

建议入口：

```bash
# 随机选择 49152-65535 内的新端口
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/ssh-key-only/setup-ssh-key-only-full.sh | sudo env SSH_CONNECTION="$SSH_CONNECTION" bash -s --

# 指定 49152-65535 内的新端口
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/ssh-key-only/setup-ssh-key-only-full.sh | sudo env SSH_CONNECTION="$SSH_CONNECTION" bash -s -- --port 55022

# 明确新增公钥，保留 authorized_keys 里的旧公钥
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/ssh-key-only/setup-ssh-key-only-full.sh | sudo env SSH_CONNECTION="$SSH_CONNECTION" bash -s -- --port 55022 --add-key

# 明确替换公钥，备份 authorized_keys 后只保留本次输入的公钥
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/ssh-key-only/setup-ssh-key-only-full.sh | sudo env SSH_CONNECTION="$SSH_CONNECTION" bash -s -- --port 55022 --replace-key
```


## PO0 受限上报 key 兼容

`setup-ssh-key-only-full.sh` 会读取 `authorized_keys` 并分类显示：普通登录 key、PO0 受限上报 key、其它 forced-command/restricted key。PO0 受限上报 key 通常由 `nftables-relay-manager.sh` 安装，备注形如 `po0-report:scope=egern` 或 `po0-report:scope=worker`。

使用 `--add-key` 会保留这些受限 key。使用 `--replace-key` 会备份并替换整个 `authorized_keys`，如果检测到 PO0 受限上报 key，脚本会先警告；替换后需要回到 PO0 主控脚本重新安装受限上报 key。