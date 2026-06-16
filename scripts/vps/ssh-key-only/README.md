# SSH Key Only Hardening

这个目录保存 SSH 公钥登录加固相关资产：

- `setup-ssh-key-only-full.sh`：为指定用户写入 SSH 公钥，切换随机或指定 SSH 新端口，并强制新端口使用公钥认证。
- `setup-ssh-key-only-full-technical.md`：脚本技术设计说明。

建议入口：

```bash
# 随机选择 49152-65535 内的新端口
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/ssh-key-only/setup-ssh-key-only-full.sh | sudo env SSH_CONNECTION="$SSH_CONNECTION" bash -s --

# 指定 49152-65535 内的新端口
curl -fsSL https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/vps/ssh-key-only/setup-ssh-key-only-full.sh | sudo env SSH_CONNECTION="$SSH_CONNECTION" bash -s -- --port 55022
```

