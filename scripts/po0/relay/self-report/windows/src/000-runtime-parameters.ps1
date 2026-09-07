param(
    [string]$ConfigPath = $(if ($env:PO0_OUTBOUND_IP_REPORT_CONFIG) { $env:PO0_OUTBOUND_IP_REPORT_CONFIG } elseif ($env:PO0_SELF_REPORT_CONFIG) { $env:PO0_SELF_REPORT_CONFIG } else { "" }),
    [string]$WorkerUrl = $(if ($env:PO0_OUTBOUND_IP_REPORT_WORKER_URL) { $env:PO0_OUTBOUND_IP_REPORT_WORKER_URL } elseif ($env:PO0_LAN_WORKER_URL) { $env:PO0_LAN_WORKER_URL } else { $env:WORKER_URL }),
    [string]$SourceId = $(if ($env:PO0_OUTBOUND_IP_REPORT_SOURCE) { $env:PO0_OUTBOUND_IP_REPORT_SOURCE } elseif ($env:PO0_SELF_REPORT_SOURCE) { $env:PO0_SELF_REPORT_SOURCE } elseif ($env:SOURCE_ID) { $env:SOURCE_ID } elseif ($env:PO0_OUTBOUND_IP_REPORT_IDENTITY) { $env:PO0_OUTBOUND_IP_REPORT_IDENTITY } elseif ($env:PO0_SELF_REPORT_IDENTITY) { $env:PO0_SELF_REPORT_IDENTITY } elseif ($env:IDENTITY) { $env:IDENTITY } elseif ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { "windows-outbound-ip-report" }),
    [string]$Identity = $(if ($env:PO0_OUTBOUND_IP_REPORT_IDENTITY) { $env:PO0_OUTBOUND_IP_REPORT_IDENTITY } elseif ($env:PO0_SELF_REPORT_IDENTITY) { $env:PO0_SELF_REPORT_IDENTITY } elseif ($env:IDENTITY) { $env:IDENTITY } elseif ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { "windows-outbound-ip-report" }),
    [string]$Secret = $(if ($env:PO0_OUTBOUND_IP_REPORT_SECRET) { $env:PO0_OUTBOUND_IP_REPORT_SECRET } elseif ($env:PO0_SELF_REPORT_SECRET) { $env:PO0_SELF_REPORT_SECRET } else { $env:SELF_REPORT_SECRET }),
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
    [ValidateSet("all","worker","official")][string]$ScheduleChannel = "all",
    [switch]$RunOnce,
    [ValidateRange(60,86400)][int]$OfficialIntervalSeconds = 600,
    [int]$Minutes = $(if ($env:PO0_OUTBOUND_IP_REPORT_MINUTES) { [int]$env:PO0_OUTBOUND_IP_REPORT_MINUTES } elseif ($env:PO0_SELF_REPORT_MINUTES) { [int]$env:PO0_SELF_REPORT_MINUTES } elseif ($env:MINUTES) { [int]$env:MINUTES } else { 60 }),
    [int]$IntervalSeconds = $(if ($env:PO0_OUTBOUND_IP_REPORT_INTERVAL_SECONDS) { [int]$env:PO0_OUTBOUND_IP_REPORT_INTERVAL_SECONDS } elseif ($env:PO0_SELF_REPORT_INTERVAL_SECONDS) { [int]$env:PO0_SELF_REPORT_INTERVAL_SECONDS } elseif ($env:INTERVAL_SECONDS) { [int]$env:INTERVAL_SECONDS } else { 0 }),
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
$ScriptVersion = "2026.09.07+build.1"
$ScriptReleaseDate = "2026-09-07"
# CHANGELOG_BEGIN
# - 七端统一“自动上报、启用定期上报、上报间隔、白名单有效期（TTL）”定义。
# - 自建和官方独立保存、启停和运行；停用或清除自建不影响官方。
# - 三端菜单独立设置定期开关并保留间隔；保存和本机查看不触发上报，保存只更新已有任务。
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
