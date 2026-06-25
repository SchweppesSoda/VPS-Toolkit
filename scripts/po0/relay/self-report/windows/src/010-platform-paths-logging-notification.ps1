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
