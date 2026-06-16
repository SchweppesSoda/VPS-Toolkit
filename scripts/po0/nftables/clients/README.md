# PO0 客户端脚本

这里放运行在客户端设备或 LAN Worker 上的脚本，不放运行在 PO0 主机上的主控脚本，也不放离线构建工具。

- `lan-worker/po0-lan-client.sh`: LAN Worker，负责 DDNS 解析上报、资源任务轮询、Self-report 接收和 WebAuth 接收。
- `self-report/po0-outbound-ip-report.sh`: Linux/OpenWrt 访问设备自上报客户端，把当前公网出口 IPv4 上报到 LAN Worker。
- `self-report/po0-outbound-ip-report.ps1`: Windows 访问设备自上报客户端，把当前公网出口 IPv4 上报到 LAN Worker。
- `egern/`: Egern SSH 上报模块和配套 JavaScript 脚本。
