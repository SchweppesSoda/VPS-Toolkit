param(
    [string]$ConfigPath = $(if ($env:PO0_OUTBOUND_IP_REPORT_CONFIG) { $env:PO0_OUTBOUND_IP_REPORT_CONFIG } elseif ($env:PO0_SELF_REPORT_CONFIG) { $env:PO0_SELF_REPORT_CONFIG } else { "" }),
    [string]$WorkerUrl = $(if ($env:PO0_OUTBOUND_IP_REPORT_WORKER_URL) { $env:PO0_OUTBOUND_IP_REPORT_WORKER_URL } elseif ($env:PO0_LAN_WORKER_URL) { $env:PO0_LAN_WORKER_URL } else { $env:WORKER_URL }),
    [string]$SourceId = $(if ($env:PO0_OUTBOUND_IP_REPORT_SOURCE) { $env:PO0_OUTBOUND_IP_REPORT_SOURCE } elseif ($env:PO0_SELF_REPORT_SOURCE) { $env:PO0_SELF_REPORT_SOURCE } elseif ($env:SOURCE_ID) { $env:SOURCE_ID } elseif ($env:PO0_OUTBOUND_IP_REPORT_IDENTITY) { $env:PO0_OUTBOUND_IP_REPORT_IDENTITY } elseif ($env:PO0_SELF_REPORT_IDENTITY) { $env:PO0_SELF_REPORT_IDENTITY } elseif ($env:IDENTITY) { $env:IDENTITY } elseif ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { "windows-outbound-ip-report" }),
    [string]$Identity = $(if ($env:PO0_OUTBOUND_IP_REPORT_IDENTITY) { $env:PO0_OUTBOUND_IP_REPORT_IDENTITY } elseif ($env:PO0_SELF_REPORT_IDENTITY) { $env:PO0_SELF_REPORT_IDENTITY } elseif ($env:IDENTITY) { $env:IDENTITY } elseif ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { "windows-outbound-ip-report" }),
    [string]$Secret = $(if ($env:PO0_OUTBOUND_IP_REPORT_SECRET) { $env:PO0_OUTBOUND_IP_REPORT_SECRET } elseif ($env:PO0_SELF_REPORT_SECRET) { $env:PO0_SELF_REPORT_SECRET } else { $env:SELF_REPORT_SECRET }),
    [string]$IpCheckUrl = $(if ($env:PO0_OUTBOUND_IP_REPORT_IP_CHECK_URL) { $env:PO0_OUTBOUND_IP_REPORT_IP_CHECK_URL } elseif ($env:IP_CHECK_URL) { $env:IP_CHECK_URL } else { "https://ip9.com.cn/get" }),
    [string[]]$IpCheckUrls = @(),
    [switch]$InstallTask,
    [switch]$RunOnce,
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
$ScriptVersion = "2026.07.01+build.3"
$ScriptReleaseDate = "2026-07-01"
# CHANGELOG_BEGIN
# - 默认配置、日志和计划任务迁移到 po0-outbound-ip-report 命名。
# - 旧 po0-self-report.ps1、旧配置、旧日志和旧计划任务作为 legacy 兼容入口自动迁移。
# - 新增 PO0_OUTBOUND_IP_REPORT_* 环境变量别名，旧 PO0_SELF_REPORT_* 继续兼容。
# CHANGELOG_END
$PanelValueColumn = 24
$MenuRightColumn = 46
$MaxMinutes = 10080
$script:TaskName = "PO0 Outbound IP Report to LAN Worker"
$script:LegacyTaskName = "PO0 Self Report to LAN Worker"
