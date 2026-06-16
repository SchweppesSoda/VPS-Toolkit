# SSH Key Only Hardening

这个目录保存 SSH 公钥登录加固相关资产：

- `setup-ssh-key-only-full.sh`：菜单式 SSH 登录加固工具，可查看 SSH/nft 状态、只新增或替换登录公钥，或执行完整的换端口 + 公钥认证加固。
- `setup-ssh-key-only-full-technical.md`：脚本技术设计说明。

脚本写入的是 `authorized_keys` 里的登录公钥。私钥应保存在本地机器，不要粘贴到 VPS 或脚本里。

建议入口：

```bash
# 菜单式入口：可选择查看状态、只更新公钥，或执行完整换端口加固
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/ssh-key-only/setup-ssh-key-only-full.sh | sudo env SSH_CONNECTION="$SSH_CONNECTION" bash
```

菜单选项：

- 查看当前 SSH / nft 状态（只读）。
- 只安装 / 更新登录公钥，不修改 SSH 端口、`sshd_config` 或 nftables。
- 完整加固：安装公钥、切换 SSH 高位端口、在新端口强制公钥认证，并同步 nftables。

公钥写入默认行为：

- `authorized_keys` 不存在或为空：直接新增本次输入的公钥。
- `authorized_keys` 已有登录公钥：询问“新增保留旧 key”还是“备份后替换”。
- 如果检测到 PO0 受限上报 key，选择替换前会提示会删除 Egern / LAN Worker 的受限上报能力。

高级 / 自动化入口仍然保留：

```bash
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
