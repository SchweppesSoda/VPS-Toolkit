# SSH Key Only Hardening

这个目录保存 SSH 公钥登录加固相关资产：

- `setup-ssh-key-only-full.sh`：为指定用户写入 SSH 公钥，切换随机 SSH 端口，并强制新端口使用公钥认证。
- `setup-ssh-key-only-full-technical.md`：脚本技术设计说明。

建议入口：

```bash
sudo bash scripts/vps/ssh-key-only/setup-ssh-key-only-full.sh
```

