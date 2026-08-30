#!/bin/sh
set -u

SCRIPT_NAME="po0-wan-probe"
SCRIPT_VERSION="2026.08.30+build.3"
SCRIPT_RELEASE_DATE="2026-08-30"
# CHANGELOG_BEGIN
# - 修复 OpenWrt /lib/functions.sh 与 nounset 不兼容导致探针启动失败。
# - 新增独立 OpenWrt mwan3 WAN 探针、来源 IP 白名单、接口公网地址优先检测和批量 JSON 接口。
# - 探针不包含 LAN Worker 密钥、上报逻辑或调度器，可由 po0-wan-probe APK 独立安装。
# CHANGELOG_END
CONFIG_NAME="po0_wan_probe"
CONFIG_SECTION="main"
DEFAULT_ALLOWED_SOURCE="192.168.88.2"
DEFAULT_IP_CHECK_URLS="https://ip9.com.cn/get,https://myip.ipip.net/json"
ALLOWED_SOURCES=""
ALLOWED_WANS=""
IP_CHECK_URLS="${DEFAULT_IP_CHECK_URLS}"
PROBE_ENABLED="1"
