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
$ScriptVersion = "2026.07.01+build.4"
$ScriptReleaseDate = "2026-07-01"
# CHANGELOG_BEGIN
# - 更新和旧路径自愈后会迁移默认旧配置、日志、IP 探测状态和计划任务，并删除旧 po0-self-report.ps1 / VBS 默认残留。
# - 旧计划任务迁移会保留通知、暂停状态、Settings / Principal；删除旧任务失败时会先禁用旧任务，避免双重上报。
# - 显式 -ConfigPath / -LogPath 自定义路径在迁移和卸载清理时不会被误删。
# CHANGELOG_END
$PanelValueColumn = 24
$MenuRightColumn = 46
$MaxMinutes = 10080
$script:TaskName = "PO0 Outbound IP Report to LAN Worker"
$script:LegacyTaskName = "PO0 Self Report to LAN Worker"
