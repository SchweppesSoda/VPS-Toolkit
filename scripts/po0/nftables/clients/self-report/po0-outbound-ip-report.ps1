param(
    [string]$ConfigPath = $(if ($env:PO0_SELF_REPORT_CONFIG) { $env:PO0_SELF_REPORT_CONFIG } else { "" }),
    [string]$WorkerUrl = $(if ($env:PO0_LAN_WORKER_URL) { $env:PO0_LAN_WORKER_URL } else { $env:WORKER_URL }),
    [string]$SourceId = $(if ($env:PO0_SELF_REPORT_SOURCE) { $env:PO0_SELF_REPORT_SOURCE } elseif ($env:SOURCE_ID) { $env:SOURCE_ID } elseif ($env:PO0_SELF_REPORT_IDENTITY) { $env:PO0_SELF_REPORT_IDENTITY } elseif ($env:IDENTITY) { $env:IDENTITY } elseif ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { "windows-self-report" }),
    [string]$Identity = $(if ($env:PO0_SELF_REPORT_IDENTITY) { $env:PO0_SELF_REPORT_IDENTITY } elseif ($env:IDENTITY) { $env:IDENTITY } elseif ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { "windows-self-report" }),
    [string]$Secret = $(if ($env:PO0_SELF_REPORT_SECRET) { $env:PO0_SELF_REPORT_SECRET } else { $env:SELF_REPORT_SECRET }),
    [string]$IpCheckUrl = $(if ($env:IP_CHECK_URL) { $env:IP_CHECK_URL } else { "https://ip9.com.cn/get" }),
    [string[]]$IpCheckUrls = @(),
    [switch]$InstallTask,
    [switch]$RunOnce,
    [int]$Minutes = $(if ($env:PO0_SELF_REPORT_MINUTES) { [int]$env:PO0_SELF_REPORT_MINUTES } elseif ($env:MINUTES) { [int]$env:MINUTES } else { 60 }),
    [int]$IntervalSeconds = $(if ($env:PO0_SELF_REPORT_INTERVAL_SECONDS) { [int]$env:PO0_SELF_REPORT_INTERVAL_SECONDS } elseif ($env:INTERVAL_SECONDS) { [int]$env:INTERVAL_SECONDS } else { 0 }),
    [string]$LogPath = $(if ($env:PO0_SELF_REPORT_LOG) { $env:PO0_SELF_REPORT_LOG } elseif ($env:SELF_REPORT_LOG) { $env:SELF_REPORT_LOG } else { "" }),
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
    [switch]$Help
)

$ErrorActionPreference = "Stop"
$ReleaseDownloadBaseUrl = $(if ($env:PO0_RELEASE_DOWNLOAD_BASE_URL) { $env:PO0_RELEASE_DOWNLOAD_BASE_URL } else { "https://github.com/SchweppesSoda/VPS-Toolkit/releases/latest/download" })
$DownloadUrl = $(if ($env:PO0_SELF_REPORT_PS_DOWNLOAD_URL) { $env:PO0_SELF_REPORT_PS_DOWNLOAD_URL } else { "$ReleaseDownloadBaseUrl/po0-outbound-ip-report.ps1" })
$ScriptName = "po0-self-report"
$ScriptVersion = "2026.06.24+build.1"
$ScriptReleaseDate = "2026-06-24"
# CHANGELOG_BEGIN
# - 默认安装和自更新下载源迁到 GitHub Release asset。
# - 新增 PO0_SELF_REPORT_PS_DOWNLOAD_URL 覆盖入口，便于测试和回滚。
# CHANGELOG_END
$PanelValueColumn = 24
$MenuRightColumn = 46
$MaxMinutes = 10080
$script:TaskName = "PO0 Self Report to LAN Worker"

function Test-IsAdmin {
    try {
        return ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Get-DefaultDataDir {
    if (Test-IsAdmin) {
        if ($env:ProgramData) { return (Join-Path $env:ProgramData "PO0") }
    }
    if ($env:LOCALAPPDATA) { return (Join-Path $env:LOCALAPPDATA "PO0") }
    if ($env:TEMP) { return (Join-Path $env:TEMP "PO0") }
    return "."
}

function Get-DefaultConfigPath {
    if ($script:ConfigPath) { return $script:ConfigPath }
    return (Join-Path (Get-DefaultDataDir) "self-report.json")
}

function Get-DefaultLogPath {
    if ($script:LogPath) { return $script:LogPath }
    return (Join-Path (Get-DefaultDataDir) "po0-self-report.log")
}

function Get-DefaultScriptPath {
    return (Join-Path (Get-DefaultDataDir) "po0-self-report.ps1")
}

function Get-DefaultTaskLauncherPath {
    return (Join-Path (Get-DefaultDataDir) "po0-self-report-task.vbs")
}

$script:ConfigPath = $ConfigPath
$script:ConfigPath = Get-DefaultConfigPath
$script:WorkerUrl = $WorkerUrl
$script:SourceId = $SourceId
$script:Identity = $Identity
$script:Secret = $Secret
$script:IpCheckUrl = $IpCheckUrl
$script:IpCheckUrls = @()
if ($env:IP_CHECK_URLS -and -not $PSBoundParameters.ContainsKey("IpCheckUrls")) {
    $script:IpCheckUrls = $env:IP_CHECK_URLS -split "\s*,\s*" | Where-Object { $_ }
} elseif ($IpCheckUrls) {
    $script:IpCheckUrls = @($IpCheckUrls)
}
$script:Minutes = $Minutes
$script:IntervalSeconds = $IntervalSeconds
$script:LogPath = $LogPath
$script:AllowHttp = [bool]$AllowHttp
$script:SchedulePaused = $false
$script:Notify = [bool]$Notify
$script:TaskNotify = [bool]$Notify

function Write-SelfReportLogLine {
    param(
        [string]$Level,
        [string]$Message
    )
    if (-not $script:LogPath) { return }
    try {
        $dir = Split-Path -Parent $script:LogPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"
        foreach ($line in (($Message -replace "`r", "") -split "`n")) {
            if ($line) {
                Add-Content -LiteralPath $script:LogPath -Encoding UTF8 -Value "[$stamp] [$Level] $line"
            }
        }
    } catch {}
}

function Write-SelfReportInfo {
    param([string]$Message)
    Write-Host $Message
    Write-SelfReportLogLine "INFO" $Message
}

function Write-SelfReportCompleted {
    param([string]$Message)
    Write-Host "Self-report 已完成：$Message" -ForegroundColor Green
    Write-SelfReportLogLine "OK" "Self-report 已完成：$Message"
}

function Write-SelfReportIncomplete {
    param([string]$Message)
    [Console]::Error.WriteLine("Self-report 未完成：$Message")
    Write-SelfReportLogLine "ERROR" "Self-report 未完成：$Message"
}

function Show-WindowsSelfReportNotification {
    param(
        [string]$Title,
        [string]$Message,
        [ValidateSet("Info", "Error")]
        [string]$Kind = "Info"
    )
    if (-not $script:Notify) { return }
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $notify = New-Object System.Windows.Forms.NotifyIcon
        if ($Kind -eq "Error") {
            $notify.Icon = [System.Drawing.SystemIcons]::Error
            $notify.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Error
        } else {
            $notify.Icon = [System.Drawing.SystemIcons]::Information
            $notify.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
        }
        if ($Message.Length -gt 240) {
            $Message = $Message.Substring(0, 237) + "..."
        }
        $notify.Text = "PO0 Self-report"
        $notify.BalloonTipTitle = $Title
        $notify.BalloonTipText = $Message
        $notify.Visible = $true
        $notify.ShowBalloonTip(8000)
        Start-Sleep -Seconds 6
    } catch {
        Write-SelfReportLogLine "WARN" "Windows 通知显示失败：$($_.Exception.Message)"
    } finally {
        if ($notify) {
            $notify.Dispose()
        }
    }
}

function Set-OutputColumn {
    param([int]$Column)
    if ([Console]::IsOutputRedirected) {
        Write-Host "    " -NoNewline
        return
    }
    try {
        $target = [Math]::Max(0, $Column - 1)
        if ([Console]::CursorLeft -gt $target) {
            Write-Host ""
        }
        [Console]::CursorLeft = $target
    } catch {
        Write-Host "    " -NoNewline
    }
}

function Write-MenuDivider {
    Write-Host "------------------------" -ForegroundColor Cyan
}

function Write-MenuSection {
    param([string]$Title)
    Write-MenuDivider
    Write-Host $Title -ForegroundColor Cyan
}

function Write-MenuItem {
    param([string]$Number, [string]$Label)
    Write-Host ("  {0,2}) {1}" -f $Number, $Label) -ForegroundColor Cyan
}

function Write-MenuPair {
    param(
        [string]$LeftNumber,
        [string]$LeftLabel,
        [string]$RightNumber,
        [string]$RightLabel
    )
    $left = ("  {0,2}) {1}" -f $LeftNumber, $LeftLabel)
    if ($RightNumber) {
        Write-Host $left -NoNewline -ForegroundColor Cyan
        Set-OutputColumn $MenuRightColumn
        Write-Host ("{0,2}) {1}" -f $RightNumber, $RightLabel) -ForegroundColor Cyan
    } else {
        Write-Host $left -ForegroundColor Cyan
    }
}

function Write-PanelDivider {
    Write-Host "------------------------" -ForegroundColor DarkYellow
}

function Write-PanelSection {
    param([string]$Title)
    Write-PanelDivider
    Write-Host $Title -ForegroundColor Yellow
}

function Write-PanelRow {
    param([string]$Label, [string]$Value)
    Write-Host "  $Label" -NoNewline -ForegroundColor DarkYellow
    Set-OutputColumn $PanelValueColumn
    Write-Host ": $Value" -ForegroundColor DarkYellow
}

function Write-PanelNote {
    param([string]$Value)
    Set-OutputColumn $PanelValueColumn
    Write-Host "  $Value"
}

function Load-SavedConfig {
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) { return }
    $raw = Get-Content -LiteralPath $script:ConfigPath -Raw -Encoding UTF8
    if (-not $raw.Trim()) { return }
    $cfg = $raw | ConvertFrom-Json

    if (-not $PSBoundParameters.ContainsKey("WorkerUrl") -and -not $env:PO0_LAN_WORKER_URL -and -not $env:WORKER_URL -and $cfg.WorkerUrl) {
        $script:WorkerUrl = [string]$cfg.WorkerUrl
    }
    if (-not $PSBoundParameters.ContainsKey("SourceId") -and -not $env:PO0_SELF_REPORT_SOURCE -and -not $env:SOURCE_ID -and $cfg.SourceId) {
        $script:SourceId = [string]$cfg.SourceId
    }
    if (-not $PSBoundParameters.ContainsKey("Identity") -and -not $env:PO0_SELF_REPORT_IDENTITY -and -not $env:IDENTITY -and $cfg.Identity) {
        $script:Identity = [string]$cfg.Identity
    }
    if (-not $PSBoundParameters.ContainsKey("Secret") -and -not $env:PO0_SELF_REPORT_SECRET -and -not $env:SELF_REPORT_SECRET -and $null -ne $cfg.Secret) {
        $script:Secret = [string]$cfg.Secret
    }
    if (-not $PSBoundParameters.ContainsKey("IpCheckUrl") -and -not $env:IP_CHECK_URL -and $cfg.IpCheckUrl) {
        $script:IpCheckUrl = [string]$cfg.IpCheckUrl
    }
    if (-not $PSBoundParameters.ContainsKey("IpCheckUrls") -and -not $env:IP_CHECK_URLS -and $cfg.IpCheckUrls) {
        $script:IpCheckUrls = @($cfg.IpCheckUrls | Where-Object { $_ })
    }
    if (-not $PSBoundParameters.ContainsKey("IntervalSeconds") -and -not $PSBoundParameters.ContainsKey("Minutes") -and -not $env:PO0_SELF_REPORT_INTERVAL_SECONDS -and -not $env:INTERVAL_SECONDS -and -not $env:PO0_SELF_REPORT_MINUTES -and -not $env:MINUTES -and $cfg.IntervalSeconds) {
        $script:IntervalSeconds = [int]$cfg.IntervalSeconds
    } elseif (-not $PSBoundParameters.ContainsKey("Minutes") -and -not $env:PO0_SELF_REPORT_MINUTES -and -not $env:MINUTES -and $cfg.Minutes) {
        $script:Minutes = [int]$cfg.Minutes
    }
    if (-not $PSBoundParameters.ContainsKey("LogPath") -and -not $env:PO0_SELF_REPORT_LOG -and -not $env:SELF_REPORT_LOG -and $cfg.LogPath) {
        $script:LogPath = [string]$cfg.LogPath
    }
    if (-not $PSBoundParameters.ContainsKey("AllowHttp") -and -not $env:PO0_SELF_REPORT_ALLOW_HTTP -and $null -ne $cfg.AllowHttp) {
        $script:AllowHttp = [bool]$cfg.AllowHttp
    }
    if ($null -ne $cfg.SchedulePaused) {
        $script:SchedulePaused = [bool]$cfg.SchedulePaused
    }
    if (-not $PSBoundParameters.ContainsKey("Notify") -and $null -ne $cfg.Notify) {
        $script:TaskNotify = [bool]$cfg.Notify
    }
}

function Save-ClientConfig {
    Assert-Minutes
    $dir = Split-Path -Parent $script:ConfigPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $config = [ordered]@{
        WorkerUrl = $script:WorkerUrl
        SourceId = $script:SourceId
        Identity = $script:Identity
        Secret = $script:Secret
        AllowHttp = [bool]$script:AllowHttp
        Minutes = [int]$script:Minutes
        IntervalSeconds = [int](Get-IntervalSeconds)
        IpCheckUrl = $script:IpCheckUrl
        IpCheckUrls = @($script:IpCheckUrls)
        LogPath = $script:LogPath
        SchedulePaused = [bool]$script:SchedulePaused
        Notify = [bool]$script:TaskNotify
    }
    $config | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:ConfigPath -Encoding UTF8
    Write-SelfReportCompleted "配置已保存：$script:ConfigPath"
}

function Show-Usage {
    @"
PO0 自上报客户端（Windows PowerShell）

本脚本探测当前 Windows 设备的公网出口 IPv4，并上报到 LAN Worker 的
self-report 接收服务。访问设备不直接连接 PO0。

用法:
  `$script="`$env:TEMP\po0-outbound-ip-report.ps1"; irm -UseBasicParsing '$DownloadUrl' -OutFile `$script -TimeoutSec 120; powershell -ExecutionPolicy Bypass -File `$script
  .\po0-outbound-ip-report.ps1 -Menu
  .\po0-outbound-ip-report.ps1 -Version
  .\po0-outbound-ip-report.ps1 -UpgradeSelf
  .\po0-outbound-ip-report.ps1 -RunOnce
  .\po0-outbound-ip-report.ps1 -WorkerUrl https://report.example.com/report -SourceId laptop -Secret SECRET -SaveConfig
  .\po0-outbound-ip-report.ps1 -WorkerUrl https://report.example.com/report -SourceId laptop -Secret SECRET -InstallTask -IntervalSeconds 3600

参数:
  -Menu               打开交互菜单。
  -Version            显示脚本版本、发布日期、当前路径和默认安装路径。
  -Changelog          显示当前版本更新内容。
  -UpgradeSelf        从 GitHub Release 下载并更新本机脚本；菜单内更新会自动重开新版菜单。
  -ConfigPath PATH    self-report 本地配置文件；默认管理员用 ProgramData，普通用户用 LocalAppData。
  -SaveConfig         保存当前参数到本地配置文件，不安装计划任务。
  -RunOnce            从参数或已保存配置立即上报一次，不进入交互菜单。
  -WorkerUrl URL      LAN Worker self-report HTTPS 接收地址；裸域名会自动补全。
  -AllowHttp          允许 http:// 上报；仅用于本地调试或临时旧环境。
  -SourceId ID        写入 PO0 client_ip 记录的来源 ID。默认: 计算机名。
  -Identity ID        LAN Worker/PO0 日志里的设备或用户标签。默认: 计算机名。
  -Secret SECRET      可选的 LAN Worker self-report 共享密钥。
  -IpCheckUrl URL     第一个公网 IPv4 探测地址。默认: $($script:IpCheckUrl)
  -IpCheckUrls URL[]  覆盖完整探测地址列表。
  -InstallTask        安装 / 更新 Windows 计划任务。
  -PauseSchedule      暂停计划任务；手动立即上报仍可用。
  -ResumeSchedule     恢复计划任务。
  -ScheduleStatus     查看计划任务状态。
  -IntervalSeconds N  计划任务间隔秒数，必须是 60 的倍数。默认: 3600。
  -Minutes N          兼容旧参数：计划任务间隔分钟数，范围 1-$MaxMinutes。默认: 60。
  -LogPath PATH       计划任务运行日志路径；安装计划任务时默认写到 PO0 配置目录。
  -Notify             上报完成或失败时显示 Windows 通知；安装计划任务时显式启用。
                      Self-report 放行 TTL 由 LAN Worker 接收端配置，不由客户端决定。

默认公网 IPv4 探测顺序:
  https://ip9.com.cn/get
  https://mail.163.com/fgw/mailsrv-ipdetail/detail
  https://api.live.bilibili.com/client/v1/Ip/getInfoNew
  https://ipservice.ws.126.net/locate/api/getLocByIp
  https://r.inews.qq.com/api/ip2city?otype=json
  https://data.video.iqiyi.com/v.f4v
  https://ip.apps.cntv.cn/whereis?client=json
  https://myip.ipip.net/json
"@
}

function Get-ScriptFileVersion {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return "" }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $match = [regex]::Match($raw, '(?m)^\s*\$ScriptVersion\s*=\s*"([^"]+)"')
    if ($match.Success) { return $match.Groups[1].Value }
    return ""
}

function Get-ScriptFileChangelog {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return @() }
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    $inBlock = $false
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        if ($line -match '^# CHANGELOG_BEGIN') {
            $inBlock = $true
            continue
        }
        if ($line -match '^# CHANGELOG_END') {
            $inBlock = $false
            continue
        }
        if ($inBlock) {
            $result.Add(($line -replace '^# ?', ''))
        }
    }
    return $result.ToArray()
}

function Show-ScriptVersion {
    $current = $(if ($PSCommandPath) { $PSCommandPath } else { "未知" })
    Write-Host "脚本名称：$ScriptName"
    Write-Host "版本：$ScriptVersion"
    Write-Host "发布日期：$ScriptReleaseDate"
    Write-Host "当前脚本：$current"
    Write-Host "默认安装路径：$(Get-DefaultScriptPath)"
    Write-Host "下载 URL：$DownloadUrl"
}

function Show-ScriptChangelog {
    $current = $(if ($PSCommandPath) { $PSCommandPath } else { "" })
    $lines = Get-ScriptFileChangelog -Path $current
    if ($lines.Count -gt 0) {
        $lines | ForEach-Object { Write-Host $_ }
    } else {
        Write-Host "当前脚本未提供更新内容。"
    }
}

function Normalize-WorkerUrl {
    param([string]$Value)
    if (-not $Value) { return "" }
    $value = $Value.Trim()
    if (-not $value) { return "" }
    if ($value -notmatch "^[A-Za-z][A-Za-z0-9+.-]*://") {
        $value = "https://$value"
    }
    try {
        $builder = [System.UriBuilder]::new($value)
    } catch {
        throw "LAN Worker self-report 地址无效：$Value"
    }
    if (-not $builder.Path -or $builder.Path -eq "/") {
        $builder.Path = "report"
    }
    return $builder.Uri.AbsoluteUri
}

function Assert-WorkerUrl {
    if (-not $script:WorkerUrl) { throw "缺少 -WorkerUrl 或已保存配置；请先配置并保存上报参数。" }
    $script:WorkerUrl = Normalize-WorkerUrl $script:WorkerUrl
    $uri = [System.Uri]$script:WorkerUrl
    if ($uri.Scheme -eq "https") { return }
    if ($uri.Scheme -eq "http" -and $script:AllowHttp) { return }
    if ($uri.Scheme -eq "http") {
        throw "Self-report 默认只允许 HTTPS。若仅用于本地调试或旧环境，请显式加 -AllowHttp。"
    }
    throw "LAN Worker self-report 地址必须是 https:// 地址。"
}

function Assert-Minutes {
    $parsed = 0
    if (-not [int]::TryParse([string]$script:Minutes, [ref]$parsed) -or $parsed -lt 1 -or $parsed -gt $script:MaxMinutes) {
        throw "计划任务间隔必须在 1-$script:MaxMinutes 分钟之间。"
    }
    $script:Minutes = $parsed
}

function Convert-IntervalSecondsToMinutes {
    param([object]$Seconds)
    $parsed = 0
    if (-not [int]::TryParse([string]$Seconds, [ref]$parsed)) {
        throw "计划任务间隔秒数必须是整数。"
    }
    $maxSeconds = $script:MaxMinutes * 60
    if ($parsed -lt 60 -or $parsed -gt $maxSeconds -or ($parsed % 60) -ne 0) {
        throw "计划任务间隔秒数必须在 60-$maxSeconds 秒之间，且必须是 60 的倍数。"
    }
    return [int]($parsed / 60)
}

function Apply-IntervalSeconds {
    if ($script:IntervalSeconds -and [int]$script:IntervalSeconds -gt 0) {
        $script:Minutes = Convert-IntervalSecondsToMinutes $script:IntervalSeconds
    }
}

function Get-IntervalSeconds {
    Assert-Minutes
    return [int]($script:Minutes * 60)
}

function Test-ClientConfigComplete {
    try {
        Assert-WorkerUrl
        Assert-Minutes
        return $true
    } catch {
        return $false
    }
}

function Test-PublicIPv4 {
    param([string]$Ip)
    if ($Ip -notmatch "^(\d{1,3}\.){3}\d{1,3}$") { return $false }
    $octets = $Ip.Split(".") | ForEach-Object { [int]$_ }
    if (($octets | Where-Object { $_ -lt 0 -or $_ -gt 255 }).Count -gt 0) { return $false }
    if ($octets[0] -in @(0, 10, 127)) { return $false }
    if ($octets[0] -ge 224) { return $false }
    if ($octets[0] -eq 100 -and $octets[1] -ge 64 -and $octets[1] -le 127) { return $false }
    if ($octets[0] -eq 169 -and $octets[1] -eq 254) { return $false }
    if ($octets[0] -eq 172 -and $octets[1] -ge 16 -and $octets[1] -le 31) { return $false }
    if ($octets[0] -eq 192 -and $octets[1] -eq 168) { return $false }
    if ($octets[0] -eq 198 -and $octets[1] -ge 18 -and $octets[1] -le 19) { return $false }
    return $true
}

function Get-FirstPublicIPv4FromText {
    param([string]$Text)
    foreach ($match in [regex]::Matches($Text, "\b(\d{1,3}(?:\.\d{1,3}){3})\b")) {
        $ip = $match.Groups[1].Value
        if (Test-PublicIPv4 $ip) { return $ip }
    }
    return $null
}

function Invoke-HttpNoProxy {
    param([string]$Url)
    Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.UseProxy = $false
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(20)
    try {
        return $client.GetStringAsync($Url).GetAwaiter().GetResult()
    } finally {
        $client.Dispose()
        $handler.Dispose()
    }
}

function Get-IpCheckStatePath {
    if ($env:LOCALAPPDATA) {
        return (Join-Path $env:LOCALAPPDATA "PO0\self-report-ip-check-index.txt")
    }
    if ($env:TEMP) {
        return (Join-Path $env:TEMP "po0-self-report-ip-check-index.txt")
    }
    return "po0-self-report-ip-check-index.txt"
}

function Get-IpCheckIndex {
    param([int]$Count)
    if ($Count -le 0) { return 0 }
    $path = Get-IpCheckStatePath
    try {
        if (Test-Path -LiteralPath $path) {
            $raw = (Get-Content -LiteralPath $path -Raw) -replace "[^\d]", ""
            if ($raw) { return ([int]$raw % $Count) }
        }
    } catch {}
    return 0
}

function Set-IpCheckIndex {
    param([int]$Index, [int]$Count)
    if ($Count -le 0) { return }
    $path = Get-IpCheckStatePath
    try {
        $dir = Split-Path -Parent $path
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Set-Content -LiteralPath $path -Value ([string]($Index % $Count)) -Encoding ASCII
    } catch {}
}

function Get-OutboundIPv4 {
    $urls = @()
    if ($script:IpCheckUrls.Count -gt 0) {
        $urls += $script:IpCheckUrls
    } else {
        $urls += $script:IpCheckUrl
        $urls += "https://mail.163.com/fgw/mailsrv-ipdetail/detail"
        $urls += "https://api.live.bilibili.com/client/v1/Ip/getInfoNew"
        $urls += "https://ipservice.ws.126.net/locate/api/getLocByIp"
        $urls += "https://r.inews.qq.com/api/ip2city?otype=json"
        $urls += "https://data.video.iqiyi.com/v.f4v"
        $urls += "https://ip.apps.cntv.cn/whereis?client=json"
        $urls += "https://myip.ipip.net/json"
    }
    $count = $urls.Count
    if ($count -le 0) { throw "未配置公网 IPv4 探测地址。" }
    $start = Get-IpCheckIndex -Count $count
    for ($i = 0; $i -lt $count; $i++) {
        $idx = ($start + $i) % $count
        $url = $urls[$idx]
        $cleanUrl = ($url | Out-String).Trim()
        if (-not $cleanUrl) { continue }
        try {
            $body = Invoke-HttpNoProxy -Url $cleanUrl
            $ip = Get-FirstPublicIPv4FromText -Text $body
            if ($ip) {
                Set-IpCheckIndex -Index (($idx + 1) % $count) -Count $count
                return $ip
            }
        } catch {
            Write-Verbose "公网 IPv4 探测失败 ${cleanUrl}: $($_.Exception.Message)"
        }
    }
    Set-IpCheckIndex -Index (($start + 1) % $count) -Count $count
    throw "未能探测到当前公网出口 IPv4。"
}

function Invoke-SelfReport {
    Assert-WorkerUrl
    Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
    $ip = Get-OutboundIPv4
    $builder = [System.UriBuilder]::new($script:WorkerUrl)
    $query = [System.Web.HttpUtility]::ParseQueryString($builder.Query)
    $query["source"] = $script:SourceId
    $query["ip"] = $ip
    $query["identity"] = $script:Identity
    $builder.Query = $query.ToString()
    $headers = @{}
    if ($script:Secret) { $headers["X-PO0-Token"] = $script:Secret }
    Write-SelfReportInfo "上报当前公网出口 IPv4 $ip 到 LAN Worker：$script:WorkerUrl"
    $resp = Invoke-WebRequest -UseBasicParsing -Uri $builder.Uri.AbsoluteUri -Headers $headers -TimeoutSec 30
    $content = $resp.Content
    if ($content -is [byte[]]) {
        $content = [System.Text.Encoding]::UTF8.GetString($content)
    } elseif ($null -ne $content) {
        $content = [string]$content
    }
    if ($content) {
        $trimmedContent = $content.TrimEnd()
        Write-Output $trimmedContent
        Write-SelfReportLogLine "RESPONSE" $trimmedContent
    }
    $message = "公网出口 IPv4 $ip 已被 LAN Worker 接收（HTTP $([int]$resp.StatusCode)）。"
    Write-SelfReportCompleted $message
    Show-WindowsSelfReportNotification -Title "PO0 Self-report 已完成" -Message $message -Kind "Info"
}

function Quote-TaskArg {
    param([string]$Value)
    if ($null -eq $Value) { return '""' }
    return '"' + ($Value -replace '"', '\"') + '"'
}

function ConvertTo-VbsStringLiteral {
    param([string]$Value)
    if ($null -eq $Value) { $Value = "" }
    return '"' + ($Value -replace '"', '""') + '"'
}

function Test-DownloadedScript {
    param([string]$Path)
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ($raw -notmatch 'po0-outbound-ip-report\.ps1' -or $raw -notmatch 'PO0 自上报客户端（Windows PowerShell）') {
        throw "更新文件校验失败：下载到的脚本不是 Self-report Windows PowerShell 客户端。"
    }
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors -and $errors.Count -gt 0) {
        throw "更新文件校验失败：下载到的脚本未通过 PowerShell 语法检查：$($errors[0].Message)"
    }
}

function Upgrade-SelfFromDownload {
    param([switch]$ReopenMenu)
    $dest = Get-DefaultScriptPath
    $dir = Split-Path -Parent $dest
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $tmp = Join-Path $dir (".po0-self-report.{0}.tmp" -f $PID)
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $DownloadUrl -OutFile $tmp -TimeoutSec 120
        Test-DownloadedScript -Path $tmp
        $newVersion = Get-ScriptFileVersion -Path $tmp
        $newChangelog = Get-ScriptFileChangelog -Path $tmp
        Move-Item -LiteralPath $tmp -Destination $dest -Force
        Write-Host "已更新 Self-report 客户端脚本：$dest"
        Write-Host "下载 URL：$DownloadUrl"
        if ($newVersion) {
            if ($newVersion -eq $ScriptVersion) {
                Write-Host "版本：$newVersion（与当前执行脚本相同）"
            } else {
                Write-Host "版本：$ScriptVersion -> $newVersion"
            }
        } else {
            Write-Host "版本：无法读取新脚本版本。"
        }
        if ($newChangelog.Count -gt 0) {
            Write-Host "更新内容："
            $newChangelog | ForEach-Object { Write-Host $_ }
        } else {
            Write-Host "更新内容：新脚本未提供更新说明。"
        }
        if ($ReopenMenu) {
            Read-Host "更新完成。按回车打开新版菜单" | Out-Null
            Write-Host "正在重新打开新版菜单：$dest -Menu"
            & powershell -NoProfile -ExecutionPolicy Bypass -File $dest -ConfigPath $script:ConfigPath -Menu
            exit $LASTEXITCODE
        }
    } finally {
        if (Test-Path -LiteralPath $tmp) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
}

function Install-ScheduledReporter {
    Assert-WorkerUrl
    Assert-Minutes
    $dir = Get-DefaultDataDir
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $dest = Get-DefaultScriptPath
    $script:LogPath = Get-DefaultLogPath
    Save-ClientConfig
    if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath)) {
        $sourcePath = [System.IO.Path]::GetFullPath($PSCommandPath)
        $destPath = [System.IO.Path]::GetFullPath($dest)
        if ($sourcePath -ne $destPath) {
            Copy-Item -LiteralPath $PSCommandPath -Destination $dest -Force
        }
    } else {
        Invoke-WebRequest -UseBasicParsing -Uri $DownloadUrl -OutFile $dest -TimeoutSec 120
    }
    $taskArgList = @(
        "-NoProfile",
        "-Sta",
        "-WindowStyle", "Hidden",
        "-NonInteractive",
        "-ExecutionPolicy", "Bypass",
        "-File", (Quote-TaskArg $dest),
        "-ConfigPath", (Quote-TaskArg $script:ConfigPath),
        "-LogPath", (Quote-TaskArg $script:LogPath),
        "-RunOnce"
    )
    if ($script:TaskNotify) {
        $taskArgList += "-Notify"
    }
    $taskArgs = $taskArgList -join " "
    $launcher = Get-DefaultTaskLauncherPath
    $command = "powershell.exe $taskArgs"
    $launcherContent = @(
        "Option Explicit",
        "Dim shell, command",
        "command = $(ConvertTo-VbsStringLiteral $command)",
        "Set shell = CreateObject(""WScript.Shell"")",
        "WScript.Quit shell.Run(command, 0, True)"
    )
    Set-Content -LiteralPath $launcher -Encoding Unicode -Value $launcherContent
    $action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument ("//B //Nologo " + (Quote-TaskArg $launcher))
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $script:Minutes) -RepetitionDuration (New-TimeSpan -Days 3650)
    $description = "探测当前 Windows 公网出口 IPv4，并上报到 LAN Worker。"
    Register-ScheduledTask -TaskName $script:TaskName -Action $action -Trigger $trigger -Description $description -Force | Out-Null
    if ($script:SchedulePaused) {
        Disable-ScheduledTask -TaskName $script:TaskName | Out-Null
    } else {
        Enable-ScheduledTask -TaskName $script:TaskName | Out-Null
    }
    Write-Host ("已安装计划任务：{0}，每 {1} 秒执行一次。" -f $script:TaskName, (Get-IntervalSeconds))
    Write-Host "脚本路径：$dest"
    Write-Host "隐藏启动器：$launcher"
    Write-Host "配置文件：$script:ConfigPath"
    Write-Host "运行日志：$script:LogPath"
    Write-Host "Windows 通知：$(Format-NotifyStatus)"
    if ($script:SchedulePaused) {
        Write-SelfReportCompleted "计划任务已安装 / 更新，但当前保持暂停。"
    } else {
        Write-SelfReportCompleted "计划任务已安装 / 更新：$script:TaskName；间隔：$(Get-IntervalSeconds) 秒；通知：$(Format-NotifyStatus)；脚本路径：$dest；日志路径：$script:LogPath。"
    }
}

function Get-MaskedSecret {
    param([string]$Value)
    if (-not $Value) { return "未设置" }
    if ($Value.Length -le 8) { return "***" }
    return ($Value.Substring(0, 3) + "***" + $Value.Substring($Value.Length - 3))
}

function Format-NotifyStatus {
    if ($script:TaskNotify) { return "已启用" }
    return "静默，仅写日志"
}

function Read-Default {
    param(
        [string]$Prompt,
        [string]$DefaultValue
    )
    if ($DefaultValue) {
        $value = Read-Host "$Prompt [$DefaultValue]"
        if ($null -eq $value) { return $DefaultValue }
        if (-not $value) { return $DefaultValue }
        return $value.Trim()
    }
    $value = Read-Host "$Prompt"
    if ($null -eq $value) { return "" }
    return $value.Trim()
}

function Read-YesNoDefault {
    param(
        [string]$Prompt,
        [bool]$DefaultValue
    )
    $suffix = $(if ($DefaultValue) { "[Y/n]" } else { "[y/N]" })
    while ($true) {
        $value = Read-Host "$Prompt $suffix"
        if ($null -eq $value -or -not $value.Trim()) { return $DefaultValue }
        switch -Regex ($value.Trim()) {
            '^(y|yes)$' { return $true }
            '^(n|no)$' { return $false }
            default { Write-Host "请输入 y 或 n。" }
        }
    }
}

function Read-SecretSetting {
    if ($script:Secret) {
        $value = Read-Host "Self-report secret [已设置，回车保留，输入 - 清空]"
        if ($null -eq $value) { return }
        $value = $value.Trim()
        if (-not $value) { return }
        if ($value -eq "-") {
            $script:Secret = ""
        } else {
            $script:Secret = $value
        }
    } else {
        $value = Read-Host "Self-report secret，可空"
        if ($null -eq $value) { $value = "" }
        $script:Secret = $value.Trim()
    }
}

function Format-TaskTime {
    param($Value)
    if ($Value -and $Value.Year -gt 1900) { return $Value }
    return "尚未运行"
}

function Format-TaskResult {
    param([long]$Value)
    if ($Value -eq 0) { return "0 (成功)" }
    return ("{0} (0x{0:X8})" -f $Value)
}

function Get-ScheduledReporterLogPath {
    param($Task)
    if ($script:LogPath) { return $script:LogPath }
    if (-not $Task) { return "" }
    foreach ($action in $Task.Actions) {
        $args = [string]$action.Arguments
        if ($args -match '(?i)-LogPath\s+"([^"]+)"') { return $matches[1] }
        if ($args -match '(?i)-LogPath\s+(\S+)') { return $matches[1].Trim('"') }
        $launcher = ""
        if ($args -match '(?i)"([^"]+\.vbs)"') {
            $launcher = $matches[1]
        } elseif ($args -match '(?i)(\S+\.vbs)') {
            $launcher = $matches[1].Trim('"')
        }
        if ($launcher -and (Test-Path -LiteralPath $launcher)) {
            $launcherRaw = Get-Content -LiteralPath $launcher -Raw
            if ($launcherRaw -match '(?i)-LogPath\s+""([^""]+)""') { return $matches[1] }
            if ($launcherRaw -match '(?i)-LogPath\s+(\S+)') { return $matches[1].Trim('"') }
        }
    }
    return ""
}

function Show-SelfReportLogTail {
    param(
        [string]$Path,
        [int]$Lines = 12
    )
    if (-not $Path) {
        Write-PanelRow "运行日志" "旧计划任务未配置日志；重新安装 / 更新定时上报后启用"
        return
    }
    Write-PanelRow "运行日志" $Path
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-PanelRow "最近日志" "暂无；等待计划任务运行一次，或先手动立即上报一次"
        return
    }
    Write-PanelRow "最近日志" ""
    Get-Content -LiteralPath $Path -Tail $Lines -ErrorAction SilentlyContinue | ForEach-Object {
        Write-PanelNote $_
    }
}

function Get-ScheduledReporterSummary {
    try {
        $task = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
        if (-not $task) { return "未安装" }
        if ($task.State -eq "Disabled") { return "已安装，当前暂停" }
        return "已安装，状态 $($task.State)"
    } catch {
        return "无法读取"
    }
}

function Show-ClientConfig {
    Write-PanelSection "Self-report 客户端配置"
    Write-PanelRow "配置文件" $script:ConfigPath
    Write-PanelRow "保存状态" $(if (Test-Path -LiteralPath $script:ConfigPath) { "已保存" } else { "未保存" })
    Write-PanelRow "LAN Worker URL" $(if ($script:WorkerUrl) { $script:WorkerUrl } else { "未设置" })
    Write-PanelRow "Source ID" $script:SourceId
    Write-PanelRow "Identity" $script:Identity
    Write-PanelRow "Secret" (Get-MaskedSecret $script:Secret)
    Write-PanelRow "HTTP 上报" $(if ($script:AllowHttp) { "已显式允许" } else { "默认拒绝" })
    Write-PanelRow "上报间隔" ("每 {0} 秒（安装定时上报时使用）" -f (Get-IntervalSeconds))
    Write-PanelRow "Windows 通知" (Format-NotifyStatus)
    Write-PanelRow "定时暂停" $(if ($script:SchedulePaused) { "已暂停" } else { "未暂停" })
    Write-PanelRow "计划任务" (Get-ScheduledReporterSummary)
    Write-PanelRow "放行 TTL" "由 LAN Worker Self-report 目标控制，默认 43200 秒"
    if ($script:IpCheckUrls.Count -gt 0) {
        Write-PanelRow "IP 探测列表" ($script:IpCheckUrls -join ",")
    } else {
        Write-PanelRow "首选 IP 探测" $script:IpCheckUrl
    }
}

function Set-ClientConfigInteractive {
    $script:WorkerUrl = Read-Default "LAN Worker self-report HTTPS 接收地址（域名或 https://域名/report）" $(if ($script:WorkerUrl) { $script:WorkerUrl } else { "https://report.example.com/report" })
    $script:WorkerUrl = Normalize-WorkerUrl $script:WorkerUrl
    if ($script:WorkerUrl -match "^http://" -and -not $script:AllowHttp) {
        $confirmHttp = Read-Host "检测到 http:// 地址。仅本地调试/旧环境才允许，是否继续允许 HTTP [y/N]"
        if ($confirmHttp -match "^(y|yes)$") {
            $script:AllowHttp = $true
        } else {
            throw "已拒绝 HTTP。请改用 https://域名/report。"
        }
    }
    Assert-WorkerUrl
    $script:SourceId = Read-Default "Source ID" $script:SourceId
    $script:Identity = Read-Default "Identity" $script:Identity
    Read-SecretSetting
    $seconds = Read-Default "客户端每几秒上报一次（60-$($script:MaxMinutes * 60)；必须是 60 的倍数）" ([string](Get-IntervalSeconds))
    $script:Minutes = Convert-IntervalSecondsToMinutes $seconds
    $script:IpCheckUrl = Read-Default "首选公网 IPv4 探测 URL" $script:IpCheckUrl
    $override = Read-Host "是否覆盖完整 IP 探测 URL 列表 [y/N]"
    if ($override -match "^(y|yes)$") {
        $raw = Read-Default "完整探测 URL 列表，逗号分隔" ($script:IpCheckUrls -join ",")
        if ($raw) {
            $script:IpCheckUrls = $raw -split "\s*,\s*" | Where-Object { $_ }
        } else {
            $script:IpCheckUrls = @()
        }
    }
    Save-ClientConfig
}

function Install-ScheduledReporterInteractive {
    if (-not (Test-ClientConfigComplete)) {
        Set-ClientConfigInteractive
    } else {
        $seconds = Read-Default "定时上报每几秒执行一次（60-$($script:MaxMinutes * 60)；必须是 60 的倍数）" ([string](Get-IntervalSeconds))
        $script:Minutes = Convert-IntervalSecondsToMinutes $seconds
    }
    $script:TaskNotify = Read-YesNoDefault "自动上报完成/失败后弹出 Windows 通知" $false
    Install-ScheduledReporter
}

function Show-ScheduledReporter {
    Write-PanelSection "Self-report 定时上报"
    Write-PanelRow "配置文件" $script:ConfigPath
    Write-PanelRow "暂停状态" $(if ($script:SchedulePaused) { "已暂停（手动立即上报仍可用）" } else { "未暂停" })
    try {
        $task = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
        if (-not $task) {
            Write-PanelRow "计划任务" "未安装本脚本管理的计划任务"
            return
        }
        Write-PanelRow "计划任务" $script:TaskName
        Write-PanelRow "任务状态" ([string]$task.State)
        foreach ($trigger in $task.Triggers) {
            Write-PanelRow "触发器" ([string]$trigger)
        }
        $info = Get-ScheduledTaskInfo -TaskName $script:TaskName -ErrorAction SilentlyContinue
        if ($info) {
            Write-PanelRow "上次运行" (Format-TaskTime $info.LastRunTime)
            Write-PanelRow "上次结果" (Format-TaskResult $info.LastTaskResult)
            Write-PanelRow "下次运行" (Format-TaskTime $info.NextRunTime)
        }
        Show-SelfReportLogTail -Path (Get-ScheduledReporterLogPath -Task $task)
    } catch {
        Write-PanelRow "状态读取" "失败：$($_.Exception.Message)"
    }
}

function Set-ScheduledReporterPaused {
    param([bool]$Paused)
    $script:SchedulePaused = $Paused
    Save-ClientConfig
    try {
        $task = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
        if ($task) {
            if ($Paused) {
                Disable-ScheduledTask -TaskName $script:TaskName | Out-Null
            } else {
                Enable-ScheduledTask -TaskName $script:TaskName | Out-Null
            }
        }
    } catch {
        throw "更新计划任务启停状态失败：$($_.Exception.Message)"
    }
    if ($Paused) {
        Write-SelfReportCompleted "定时上报已暂停；手动立即上报仍可用。"
    } else {
        Write-SelfReportCompleted "定时上报已恢复。"
    }
}

function Toggle-ScheduledReporterPaused {
    Set-ScheduledReporterPaused -Paused (-not $script:SchedulePaused)
}

function Remove-ScheduledReporter {
    try {
        $task = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
        if (-not $task) {
            Write-PanelRow "计划任务" "未安装本脚本管理的计划任务"
            Write-SelfReportCompleted "当前没有本脚本管理的计划任务。"
            return
        }
        Unregister-ScheduledTask -TaskName $script:TaskName -Confirm:$false
        Write-Host "已删除计划任务：$script:TaskName"
        Write-SelfReportCompleted "已删除本脚本管理的计划任务。"
    } catch {
        throw "删除计划任务失败：$($_.Exception.Message)"
    }
}

function Remove-SelfReportPathIfExists {
    param(
        [string]$Label,
        [string]$Path
    )
    if (-not $Path) { return $true }
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "${Label}不存在：$Path"
        return $true
    }
    try {
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        Write-Host "已删除${Label}：$Path"
        return $true
    } catch {
        Write-Host "删除${Label}失败：$Path；$($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Uninstall-SelfReportClient {
    param([switch]$RemoveData)

    $scriptPath = Get-DefaultScriptPath
    $launcherPath = Get-DefaultTaskLauncherPath
    $logPath = Get-DefaultLogPath
    $ok = $true

    Write-Host "卸载会删除本脚本管理的计划任务、隐藏启动器和本机安装脚本。"
    Write-Host "本机脚本：$scriptPath"
    Write-Host "隐藏启动器：$launcherPath"
    Remove-ScheduledReporter
    if (-not (Remove-SelfReportPathIfExists -Label "隐藏启动器" -Path $launcherPath)) { $ok = $false }
    if (-not (Remove-SelfReportPathIfExists -Label "本机脚本" -Path $scriptPath)) { $ok = $false }

    if ($RemoveData) {
        if (-not (Remove-SelfReportPathIfExists -Label "配置文件" -Path $script:ConfigPath)) { $ok = $false }
        if (-not (Remove-SelfReportPathIfExists -Label "日志文件" -Path $logPath)) { $ok = $false }
    } else {
        Write-Host "已保留配置文件：$script:ConfigPath"
        Write-Host "已保留日志文件：$logPath"
    }

    if (-not $ok) {
        throw "卸载已执行，但有项目删除失败。"
    }
    Write-SelfReportCompleted "卸载已完成。"
}

function Pause-Menu {
    Read-Host "按回车返回菜单" | Out-Null
}

function Invoke-InteractiveMenu {
    while ($true) {
        Show-ClientConfig
        Write-MenuSection "手动上报"
        Write-MenuPair "1" "配置并保存上报参数" "2" "立即上报一次"
        Write-MenuSection "定时上报"
        Write-MenuPair "3" "安装 / 更新定时上报" "4" "暂停 / 恢复定时上报"
        Write-MenuPair "5" "查看定时上报状态" "6" "删除定时上报"
        Write-MenuSection "查看"
        Write-MenuItem "7" "显示当前配置"
        Write-MenuSection "维护"
        Write-MenuPair "8" "从 GitHub 更新脚本" "9" "卸载本客户端"
        Write-MenuSection "退出"
        Write-MenuItem "0" "退出"
        Write-MenuDivider
        $rawChoice = Read-Host "请选择操作 [0-9]"
        if ($null -eq $rawChoice) { return }
        $choice = $rawChoice.Trim()
        try {
            switch ($choice) {
                "1" { Set-ClientConfigInteractive; Pause-Menu }
                "2" {
                    if (-not (Test-ClientConfigComplete)) { Set-ClientConfigInteractive }
                    Invoke-SelfReport
                    Pause-Menu
                }
                "3" {
                    Install-ScheduledReporterInteractive
                    Pause-Menu
                }
                "4" { Toggle-ScheduledReporterPaused; Pause-Menu }
                "5" { Show-ScheduledReporter; Pause-Menu }
                "6" {
                    $confirm = Read-Host "确认删除 self-report 定时上报 [y/N]"
                    if ($null -eq $confirm) { $confirm = "" }
                    if ($confirm -match "^(y|yes)$") {
                        Remove-ScheduledReporter
                    } else {
                        Write-Host "已取消。"
                    }
                    Pause-Menu
                }
                "7" { Show-ClientConfig; Pause-Menu }
                "8" { Upgrade-SelfFromDownload -ReopenMenu }
                "9" {
                    $uninstalled = $false
                    Write-Host "卸载会删除计划任务、隐藏启动器和本机安装脚本；配置与日志默认保留。"
                    if (Read-YesNoDefault "确认卸载 self-report 客户端" $false) {
                        $removeData = Read-YesNoDefault "是否同时删除配置文件和日志" $false
                        Uninstall-SelfReportClient -RemoveData:$removeData
                        $uninstalled = $true
                    } else {
                        Write-Host "已取消。"
                    }
                    Pause-Menu
                    if ($uninstalled) { return }
                }
                "0" { return }
                "" {}
                default { Write-Host "无效选择。"; Pause-Menu }
            }
        } catch {
            Write-SelfReportIncomplete $_.Exception.Message
            Pause-Menu
        }
    }
}

if ($env:INSTALL_TASK -match "^(1|true|yes)$") {
    $InstallTask = $true
}

if ($env:PO0_SELF_REPORT_MENU -match "^(1|true|yes)$") {
    $Menu = $true
}

if ($env:PO0_SELF_REPORT_ALLOW_HTTP -match "^(1|true|yes)$") {
    $script:AllowHttp = $true
}

if ($Version) {
    Show-ScriptVersion
    exit 0
}

if ($Changelog) {
    Show-ScriptChangelog
    exit 0
}

if ($Help) {
    Show-Usage
    exit 0
}

if ($UpgradeSelf) {
    Upgrade-SelfFromDownload
    exit 0
}

Load-SavedConfig
Apply-IntervalSeconds

try {
    if ($SaveConfig) {
        Save-ClientConfig
    } elseif ($PauseSchedule) {
        Set-ScheduledReporterPaused -Paused $true
    } elseif ($ResumeSchedule) {
        Set-ScheduledReporterPaused -Paused $false
    } elseif ($ScheduleStatus) {
        Show-ScheduledReporter
    } elseif ($RunOnce) {
        Invoke-SelfReport
    } elseif ($Menu -or (-not $PSBoundParameters.ContainsKey("WorkerUrl") -and -not $InstallTask -and -not $RunOnce -and [Environment]::UserInteractive)) {
        Invoke-InteractiveMenu
    } elseif ($InstallTask) {
        $script:TaskNotify = [bool]$Notify
        Install-ScheduledReporter
    } else {
        Invoke-SelfReport
    }
} catch {
    Write-SelfReportIncomplete $_.Exception.Message
    Show-WindowsSelfReportNotification -Title "PO0 Self-report 未完成" -Message $_.Exception.Message -Kind "Error"
    exit 1
}
