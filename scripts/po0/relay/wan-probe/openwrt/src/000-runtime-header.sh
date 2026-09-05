#!/bin/sh
set -u

SCRIPT_NAME="po0-wan-probe"
SCRIPT_VERSION="2026.09.05+build.8"
SCRIPT_RELEASE_DATE="2026-09-05"
# CHANGELOG_BEGIN
# - 对齐发布版本校验；功能包含本轮直连 WAN 探测、独立上报通道和本机槽位配置修复。
# - 对齐本轮双通道界面与本机槽位配置发布版本；本脚本行为未变。
# CHANGELOG_END
CONFIG_NAME="po0_wan_probe"
CONFIG_SECTION="main"
DEFAULT_ALLOWED_SOURCE="192.168.88.2"
DEFAULT_IP_CHECK_URLS="https://ip9.com.cn/get,https://myip.ipip.net/json"
ALLOWED_SOURCES=""
ALLOWED_WANS=""
IP_CHECK_URLS="${DEFAULT_IP_CHECK_URLS}"
PROBE_ENABLED="1"
