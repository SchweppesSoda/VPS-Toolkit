# Egern DDNS 上报客户端

这个模块在 iOS/Egern 上定时解析 DDNS 域名，并通过 SSH 将公网 IPv4 上报给 PO0 的 nftables 中转管理器。

## 文件

- `PO0-DDNS-Report.yaml`：Egern 模块定义，默认每 10 分钟执行一次。
- `po0-ddns-report.js`：解析域名并调用 PO0 `--ddns-report` 接口的脚本。

## 使用

1. 先在 PO0 的“管理 DDNS 来源”菜单中添加域名，并生成外部上报 Token。
2. 在 Egern 中导入 `PO0-DDNS-Report.yaml`。
3. 填写 `PO0_HOST`、`DDNS_DOMAIN`、`DDNS_TOKEN`，以及 SSH 密码或私钥。
4. 保持 `DDNS_NAME` 为空即可；客户端默认使用 `DDNS_DOMAIN` 作为上报标识。

推荐使用 SSH 私钥。密码、私钥和 Token 只应保存在 Egern 的模块环境变量中，不要写入仓库文件。
