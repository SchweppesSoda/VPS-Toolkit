param(
    [string]$WorkerUrl = $(if ($env:PO0_LAN_WORKER_URL) { $env:PO0_LAN_WORKER_URL } else { $env:WORKER_URL }),
    [string]$SourceId = $(if ($env:PO0_SELF_REPORT_SOURCE) { $env:PO0_SELF_REPORT_SOURCE } elseif ($env:SOURCE_ID) { $env:SOURCE_ID } else { "self-report" }),
    [string]$Identity = $(if ($env:PO0_SELF_REPORT_IDENTITY) { $env:PO0_SELF_REPORT_IDENTITY } elseif ($env:IDENTITY) { $env:IDENTITY } elseif ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { "windows-self-report" }),
    [string]$Secret = $(if ($env:PO0_SELF_REPORT_SECRET) { $env:PO0_SELF_REPORT_SECRET } else { $env:SELF_REPORT_SECRET }),
    [string]$IpCheckUrl = $(if ($env:IP_CHECK_URL) { $env:IP_CHECK_URL } else { "https://ip9.com.cn/get" }),
    [string[]]$IpCheckUrls = @(),
    [switch]$InstallTask,
    [int]$Minutes = $(if ($env:MINUTES) { [int]$env:MINUTES } else { 5 }),
    [switch]$Help
)

$ErrorActionPreference = "Stop"
$RawUrl = "https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/tools/po0-outbound-ip-report.ps1"

if ($env:INSTALL_TASK -match "^(1|true|yes)$") {
    $InstallTask = $true
}

if ($env:IP_CHECK_URLS -and $IpCheckUrls.Count -eq 0) {
    $IpCheckUrls = $env:IP_CHECK_URLS -split "\s*,\s*"
}

function Show-Usage {
    @"
PO0 self-report client (Windows PowerShell)

Detects this device's current outbound public IPv4 and reports it to a LAN Worker
self-report server. It does not connect to PO0 directly.

Usage:
  .\po0-outbound-ip-report.ps1 -WorkerUrl https://worker.example.com/report -SourceId laptop -Secret SECRET
  `$env:PO0_LAN_WORKER_URL='https://worker.example.com/report'; `$env:PO0_SELF_REPORT_SECRET='SECRET'; irm -UseBasicParsing '$RawUrl' | iex
  `$env:PO0_LAN_WORKER_URL='https://worker.example.com/report'; `$env:PO0_SELF_REPORT_SECRET='SECRET'; `$env:INSTALL_TASK='1'; `$env:MINUTES='5'; irm -UseBasicParsing '$RawUrl' | iex

Options:
  -WorkerUrl URL      LAN Worker self-report URL.
  -SourceId ID        Identity shown in LAN Worker/PO0 logs.
  -Identity ID        Client identity. Default: computer name.
  -Secret SECRET      Optional LAN Worker self-report shared secret.
  -IpCheckUrl URL     First URL used to detect this device's current outbound IPv4.
                      Default: $IpCheckUrl
  -InstallTask        Install/update a Windows scheduled task.
  -Minutes N          Scheduled interval. Default: 5.

Default IP check order:
  https://ip9.com.cn/get
  https://mail.163.com/fgw/mailsrv-ipdetail/detail
  https://api.live.bilibili.com/client/v1/Ip/getInfoNew
  https://ipservice.ws.126.net/locate/api/getLocByIp
  https://r.inews.qq.com/api/ip2city?otype=json
  https://data.video.iqiyi.com/v.f4v
  https://ip.apps.cntv.cn/whereis?client=json
  https://exservice.12306.cn/excater/bonree/grip
  https://myip.ipip.net/json
"@
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
    if ($IpCheckUrls.Count -gt 0) {
        $urls += $IpCheckUrls
    } else {
        $urls += $IpCheckUrl
        $urls += "https://mail.163.com/fgw/mailsrv-ipdetail/detail"
        $urls += "https://api.live.bilibili.com/client/v1/Ip/getInfoNew"
        $urls += "https://ipservice.ws.126.net/locate/api/getLocByIp"
        $urls += "https://r.inews.qq.com/api/ip2city?otype=json"
        $urls += "https://data.video.iqiyi.com/v.f4v"
        $urls += "https://ip.apps.cntv.cn/whereis?client=json"
        $urls += "https://exservice.12306.cn/excater/bonree/grip"
        $urls += "https://myip.ipip.net/json"
    }
    $count = $urls.Count
    if ($count -le 0) { throw "No IP check URLs configured." }
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
            Write-Verbose "IP check failed for ${cleanUrl}: $($_.Exception.Message)"
        }
    }
    Set-IpCheckIndex -Index (($start + 1) % $count) -Count $count
    throw "Could not detect current outbound public IPv4."
}

function Invoke-SelfReport {
    if (-not $WorkerUrl) { throw "Missing -WorkerUrl or PO0_LAN_WORKER_URL." }
    Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
    $ip = Get-OutboundIPv4
    $builder = [System.UriBuilder]::new($WorkerUrl)
    $query = [System.Web.HttpUtility]::ParseQueryString($builder.Query)
    $query["source"] = $SourceId
    $query["ip"] = $ip
    $query["identity"] = $Identity
    if ($Secret) { $query["token"] = $Secret }
    $builder.Query = $query.ToString()
    Write-Host "Report current outbound IPv4 $ip to LAN Worker $WorkerUrl"
    $resp = Invoke-WebRequest -UseBasicParsing -Uri $builder.Uri.AbsoluteUri -TimeoutSec 30
    Write-Output $resp.Content
}

function Quote-TaskArg {
    param([string]$Value)
    if ($null -eq $Value) { return '""' }
    return '"' + ($Value -replace '"', '\"') + '"'
}

function Install-ScheduledReporter {
    if ($Minutes -lt 1 -or $Minutes -gt 59) { throw "-Minutes must be 1-59." }
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $dir = if ($isAdmin) { Join-Path $env:ProgramData "PO0" } else { Join-Path $env:LOCALAPPDATA "PO0" }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $dest = Join-Path $dir "po0-self-report.ps1"
    if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath)) {
        Copy-Item -LiteralPath $PSCommandPath -Destination $dest -Force
    } else {
        Invoke-WebRequest -UseBasicParsing -Uri $RawUrl -OutFile $dest
    }
    $taskName = "PO0 Self Report to LAN Worker"
    $taskArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", (Quote-TaskArg $dest),
        "-WorkerUrl", (Quote-TaskArg $WorkerUrl),
        "-SourceId", (Quote-TaskArg $SourceId),
        "-Identity", (Quote-TaskArg $Identity),
        "-Secret", (Quote-TaskArg $Secret),
        "-IpCheckUrl", (Quote-TaskArg $IpCheckUrl)
    ) -join " "
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $taskArgs
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $Minutes) -RepetitionDuration (New-TimeSpan -Days 3650)
    $description = "Detect current Windows outbound public IPv4 and report it to LAN Worker."
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Description $description -Force | Out-Null
    Write-Host "Installed scheduled task: $taskName, every $Minutes minutes."
    Write-Host "Script path: $dest"
}

if ($Help) {
    Show-Usage
    exit 0
}

if ($InstallTask) {
    Install-ScheduledReporter
} else {
    Invoke-SelfReport
}
