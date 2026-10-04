param(
    [string]$ConfigPath = $(if ($env:PO0_OUTBOUND_IP_REPORT_CONFIG) { $env:PO0_OUTBOUND_IP_REPORT_CONFIG } elseif ($env:PO0_SELF_REPORT_CONFIG) { $env:PO0_SELF_REPORT_CONFIG } else { "" }),
    [string]$WorkerUrl = "",
    [string]$SourceId = "",
    [string]$Identity = "",
    [string]$Secret = "",
    [string]$IpCheckUrl = $(if ($env:PO0_OUTBOUND_IP_REPORT_IP_CHECK_URL) { $env:PO0_OUTBOUND_IP_REPORT_IP_CHECK_URL } elseif ($env:IP_CHECK_URL) { $env:IP_CHECK_URL } else { "https://ip9.com.cn/get" }),
    [string[]]$IpCheckUrls = @(),
    [string[]]$SkipWifiSsids = @(),
    [switch]$ForceReport,
    [switch]$OfficialStatus,
    [Alias("OfficialReport")]
    [switch]$OfficialOnly,
    [switch]$WorkerOnly,
    [switch]$ScheduledRun,
    [switch]$ClearPo0FirewallTokens,
    [switch]$InstallTask,
    [switch]$RemoveTask,
    [switch]$RefreshSchedules,
    [switch]$TimerTrigger,
    [switch]$NetworkChanged,
    [switch]$WatchNetwork,
    [ValidateSet("all","worker","official")][string]$ScheduleChannel = "official",
    [switch]$RunOnce,
    [switch]$MigrateRetiredState,
    [ValidateRange(60,86400)][int]$OfficialIntervalSeconds = 600,
    [int]$Minutes = 10,
    [int]$IntervalSeconds = 0,
    [string]$LogPath = $(if ($env:PO0_OUTBOUND_IP_REPORT_LOG) { $env:PO0_OUTBOUND_IP_REPORT_LOG } elseif ($env:PO0_SELF_REPORT_LOG) { $env:PO0_SELF_REPORT_LOG } elseif ($env:SELF_REPORT_LOG) { $env:SELF_REPORT_LOG } else { "" }),
    [switch]$AllowHttp,
    [switch]$SaveConfig,
    [switch]$PauseSchedule,
    [switch]$ResumeSchedule,
    [switch]$ScheduleStatus,
    [switch]$Menu,
    [switch]$UpgradeSelf,
    [switch]$Version,
    [switch]$Changelog,
    [switch]$Notify,
    [switch]$NoNotify,
    [switch]$Help
)

$ErrorActionPreference = "Stop"
$ReleaseDownloadBaseUrl = $(if ($env:PO0_RELEASE_DOWNLOAD_BASE_URL) { $env:PO0_RELEASE_DOWNLOAD_BASE_URL } else { "https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download" })
$DownloadUrl = $(if ($env:PO0_OUTBOUND_IP_REPORT_PS_DOWNLOAD_URL) { $env:PO0_OUTBOUND_IP_REPORT_PS_DOWNLOAD_URL } elseif ($env:PO0_SELF_REPORT_PS_DOWNLOAD_URL) { $env:PO0_SELF_REPORT_PS_DOWNLOAD_URL } else { "$ReleaseDownloadBaseUrl/po0-outbound-ip-report.ps1" })
$ScriptName = "po0-outbound-ip-report"
$ScriptVersion = "2026.10.04+build.1"
$ScriptReleaseDate = "2026-10-04"
# CHANGELOG_BEGIN
# - 界面、通知和输出统一为 PO0 防火墙，保留现有账号、槽位和任务。
# - 官方请求、定期与网络触发、停用及升级行为保持兼容。
# CHANGELOG_END
$PanelValueColumn = 24
$MenuRightColumn = 46
$MaxMinutes = 10080
$script:TaskName = "Outbound IP Report"
# Compatibility marker for 2026.07.03+build.1 UpgradeSelf validation; do not execute as an assignment:
# $script:TaskName = "PO0 Outbound IP Report to LAN Worker"
$script:PreviousTaskName = "PO0 Outbound IP Report to LAN Worker"
$script:LegacyTaskName = "PO0 Self Report to LAN Worker"
$script:LegacyTaskNames = @($script:PreviousTaskName, $script:LegacyTaskName)
