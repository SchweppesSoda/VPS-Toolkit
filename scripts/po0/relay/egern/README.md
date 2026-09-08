# Egern SSH IP Report Legacy Compatibility

`scripts/po0/relay/egern/` 只作为旧 raw URL 兼容路径保留，当前新安装和文档入口使用 canonical 路径：

```text
scripts/po0/nftables/clients/egern/
```

请阅读[现行 Egern 文档](../../nftables/clients/egern/README.md)。文件名中的 SSH 仅用于兼容旧导入地址；当前内容只提供官方上报，不再启用 SSH/Worker 自建接收。

兼容路径下的 `PO0-SSH-IP-Report.yaml` 和 `po0-ssh-ip-report.js` 必须与 canonical 文件保持同步；检查器会按 LF 归一化比较这两个文件。不要把本目录作为新安装推荐入口。
