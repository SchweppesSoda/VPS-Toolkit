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
    return (Join-Path (Get-DefaultDataDir) "outbound-ip-report.json")
}

function Get-LegacyConfigPath {
    return (Join-Path (Get-DefaultDataDir) "self-report.json")
}

function Get-DefaultLogPath {
    if ($script:LogPath) { return $script:LogPath }
    return (Join-Path (Get-DefaultDataDir) "po0-outbound-ip-report.log")
}

function Get-LegacyLogPath {
    return (Join-Path (Get-DefaultDataDir) "po0-self-report.log")
}

function Get-DefaultScriptPath {
    return (Join-Path (Get-DefaultDataDir) "po0-outbound-ip-report.ps1")
}

function Get-DefaultTaskLauncherPath {
    return (Join-Path (Get-DefaultDataDir) "po0-outbound-ip-report-task.vbs")
}

function Get-LegacyScriptPath {
    return (Join-Path (Get-DefaultDataDir) "po0-self-report.ps1")
}

function Get-LegacyTaskLauncherPath {
    return (Join-Path (Get-DefaultDataDir) "po0-self-report-task.vbs")
}

function Test-LegacySelfReportScriptPath {
    param([string]$Path)
    if (-not $Path) { return $false }
    return ([System.IO.Path]::GetFileName($Path) -ieq "po0-self-report.ps1")
}

function Test-CurrentScriptPathIsLegacy {
    if (-not $PSCommandPath) { return $false }
    if (Test-LegacySelfReportScriptPath -Path $PSCommandPath) { return $true }
    try {
        $current = [System.IO.Path]::GetFullPath($PSCommandPath)
        $legacy = [System.IO.Path]::GetFullPath((Get-LegacyScriptPath))
        return [System.String]::Equals($current, $legacy, [System.StringComparison]::OrdinalIgnoreCase)
    } catch {
        return $false
    }
}

$script:ConfigPath = $ConfigPath
$script:ConfigPathExplicit = [bool]$ConfigPath
$script:ConfigPath = Get-DefaultConfigPath
$script:WorkerUrl = $WorkerUrl
$script:SourceId = $SourceId
$script:Identity = $Identity
$script:Secret = $Secret
$script:IpCheckUrl = $IpCheckUrl
$script:IpCheckUrls = @()
if ($env:PO0_OUTBOUND_IP_REPORT_IP_CHECK_URLS -and -not $PSBoundParameters.ContainsKey("IpCheckUrls")) {
    $script:IpCheckUrls = $env:PO0_OUTBOUND_IP_REPORT_IP_CHECK_URLS -split "\s*,\s*" | Where-Object { $_ }
} elseif ($env:IP_CHECK_URLS -and -not $PSBoundParameters.ContainsKey("IpCheckUrls")) {
    $script:IpCheckUrls = $env:IP_CHECK_URLS -split "\s*,\s*" | Where-Object { $_ }
} elseif ($IpCheckUrls) {
    $script:IpCheckUrls = @($IpCheckUrls)
}
$script:Minutes = $Minutes
$script:IntervalSeconds = $IntervalSeconds
$script:LogPath = $LogPath
$script:LogPathExplicit = [bool]$LogPath
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
    Write-Host "PO0 Outbound IP Report 已完成：$Message" -ForegroundColor Green
    Write-SelfReportLogLine "OK" "PO0 Outbound IP Report 已完成：$Message"
}

function Write-SelfReportIncomplete {
    param([string]$Message)
    [Console]::Error.WriteLine("PO0 Outbound IP Report 未完成：$Message")
    Write-SelfReportLogLine "ERROR" "PO0 Outbound IP Report 未完成：$Message"
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
        $notify.Text = "PO0 Outbound IP Report"
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
