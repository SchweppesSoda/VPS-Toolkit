param(
    [string]$WorkerUrl = $(if ($env:PO0_LAN_WORKER_URL) { $env:PO0_LAN_WORKER_URL } else { $env:WORKER_URL }),
    [string]$SourceId = $(if ($env:PO0_SELF_REPORT_SOURCE) { $env:PO0_SELF_REPORT_SOURCE } elseif ($env:SOURCE_ID) { $env:SOURCE_ID } else { "self-report" }),
    [string]$Identity = $(if ($env:PO0_SELF_REPORT_IDENTITY) { $env:PO0_SELF_REPORT_IDENTITY } elseif ($env:IDENTITY) { $env:IDENTITY } elseif ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { "windows-self-report" }),
    [string]$Secret = $(if ($env:PO0_SELF_REPORT_SECRET) { $env:PO0_SELF_REPORT_SECRET } else { $env:SELF_REPORT_SECRET }),
    [string]$IpCheckUrl = $(if ($env:IP_CHECK_URL) { $env:IP_CHECK_URL } else { "https://ip9.com.cn/get" }),
    [string[]]$IpCheckUrls = @(),
    [switch]$InstallTask,
    [int]$Minutes = $(if ($env:PO0_SELF_REPORT_MINUTES) { [int]$env:PO0_SELF_REPORT_MINUTES } elseif ($env:MINUTES) { [int]$env:MINUTES } else { 60 }),
    [switch]$AllowHttp,
    [switch]$Menu,
    [switch]$Help
)

$ErrorActionPreference = "Stop"
$RawUrl = "https://raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0/nftables/clients/self-report/po0-outbound-ip-report.ps1"
$MaxMinutes = 10080

if ($env:INSTALL_TASK -match "^(1|true|yes)$") {
    $InstallTask = $true
}

if ($env:PO0_SELF_REPORT_MENU -match "^(1|true|yes)$") {
    $Menu = $true
}

if ($env:PO0_SELF_REPORT_ALLOW_HTTP -match "^(1|true|yes)$") {
    $AllowHttp = $true
}

if ($env:IP_CHECK_URLS -and $IpCheckUrls.Count -eq 0) {
    $IpCheckUrls = $env:IP_CHECK_URLS -split "\s*,\s*"
}

function Show-Usage {
    @"
PO0 自上报客户端（Windows PowerShell）

本脚本探测当前 Windows 设备的公网出口 IPv4，并上报到 LAN Worker 的
self-report 接收服务。访问设备不直接连接 PO0。

用法:
  `$script="`$env:TEMP\po0-outbound-ip-report.ps1"; irm -UseBasicParsing '$RawUrl' -OutFile `$script; powershell -ExecutionPolicy Bypass -File `$script
  .\po0-outbound-ip-report.ps1 -Menu
  .\po0-outbound-ip-report.ps1 -WorkerUrl https://report.example.com/report -SourceId laptop -Secret SECRET
  .\po0-outbound-ip-report.ps1 -WorkerUrl https://report.example.com/report -SourceId laptop -Secret SECRET -InstallTask -Minutes 60

参数:
  -Menu               打开交互菜单。
  -WorkerUrl URL      LAN Worker self-report HTTPS 接收地址；裸域名会自动补全。
  -AllowHttp          允许 http:// 上报；仅用于本地调试或临时旧环境。
  -SourceId ID        写入 PO0 client_ip 记录的来源 ID。
  -Identity ID        LAN Worker/PO0 日志里的设备或用户标签。默认: 计算机名。
  -Secret SECRET      可选的 LAN Worker self-report 共享密钥。
  -IpCheckUrl URL     第一个公网 IPv4 探测地址。默认: $IpCheckUrl
  -InstallTask        安装/更新 Windows 计划任务。
  -Minutes N          计划任务间隔分钟数，范围 1-$MaxMinutes。默认: 60。
                      Self-report 放行 TTL 由 LAN Worker 接收端配置，不由客户端决定。

默认公网 IPv4 探测顺序:
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
    if (-not $script:WorkerUrl) { throw "缺少 -WorkerUrl 或 PO0_LAN_WORKER_URL。" }
    $script:WorkerUrl = Normalize-WorkerUrl $script:WorkerUrl
    $uri = [System.Uri]$script:WorkerUrl
    if ($uri.Scheme -eq "https") { return }
    if ($uri.Scheme -eq "http" -and $script:AllowHttp) { return }
    if ($uri.Scheme -eq "http") {
        throw "Self-report 默认只允许 HTTPS。若仅用于本地调试或旧环境，请显式加 -AllowHttp。"
    }
    throw "LAN Worker self-report 地址必须是 https:// 地址。"
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
    $query["source"] = $SourceId
    $query["ip"] = $ip
    $query["identity"] = $Identity
    $builder.Query = $query.ToString()
    $headers = @{}
    if ($Secret) { $headers["X-PO0-Token"] = $Secret }
    Write-Host "上报当前公网出口 IPv4 $ip 到 LAN Worker：$script:WorkerUrl"
    $resp = Invoke-WebRequest -UseBasicParsing -Uri $builder.Uri.AbsoluteUri -Headers $headers -TimeoutSec 30
    $content = $resp.Content
    if ($content -is [byte[]]) {
        $content = [System.Text.Encoding]::UTF8.GetString($content)
    } elseif ($null -ne $content) {
        $content = [string]$content
    }
    Write-Output ($content.TrimEnd())
}

function Quote-TaskArg {
    param([string]$Value)
    if ($null -eq $Value) { return '""' }
    return '"' + ($Value -replace '"', '\"') + '"'
}

function Install-ScheduledReporter {
    Assert-WorkerUrl
    Assert-Minutes
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
    $taskArgList = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", (Quote-TaskArg $dest),
        "-WorkerUrl", (Quote-TaskArg $script:WorkerUrl),
        "-SourceId", (Quote-TaskArg $SourceId),
        "-Identity", (Quote-TaskArg $Identity),
        "-Secret", (Quote-TaskArg $Secret)
    )
    if ($script:AllowHttp) {
        $taskArgList += "-AllowHttp"
    }
    if ($IpCheckUrls.Count -gt 0) {
        $taskArgList += "-IpCheckUrls"
        foreach ($url in $IpCheckUrls) {
            $taskArgList += (Quote-TaskArg $url)
        }
    } else {
        $taskArgList += "-IpCheckUrl"
        $taskArgList += (Quote-TaskArg $IpCheckUrl)
    }
    $taskArgs = $taskArgList -join " "
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $taskArgs
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $script:Minutes) -RepetitionDuration (New-TimeSpan -Days 3650)
    $description = "探测当前 Windows 公网出口 IPv4，并上报到 LAN Worker。"
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Description $description -Force | Out-Null
    Write-Host "已安装计划任务：$taskName，每 $script:Minutes 分钟执行一次。"
    Write-Host "脚本路径：$dest"
}

function Get-MaskedSecret {
    param([string]$Value)
    if (-not $Value) { return "未设置" }
    if ($Value.Length -le 8) { return "***" }
    return ($Value.Substring(0, 3) + "***" + $Value.Substring($Value.Length - 3))
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

function Assert-Minutes {
    $parsed = 0
    if (-not [int]::TryParse([string]$script:Minutes, [ref]$parsed) -or $parsed -lt 1 -or $parsed -gt $script:MaxMinutes) {
        throw "计划任务间隔必须在 1-$script:MaxMinutes 分钟之间。"
    }
    $script:Minutes = $parsed
}

function Show-ClientConfig {
    Write-Host "------------------------"
    Write-Host "Self-report 客户端配置"
    Write-Host ("  LAN Worker URL : {0}" -f $(if ($script:WorkerUrl) { $script:WorkerUrl } else { "未设置" }))
    Write-Host ("  Source ID      : {0}" -f $script:SourceId)
    Write-Host ("  Identity       : {0}" -f $script:Identity)
    Write-Host ("  Secret         : {0}" -f (Get-MaskedSecret $script:Secret))
    Write-Host ("  HTTP 上报      : {0}" -f $(if ($script:AllowHttp) { "已显式允许" } else { "默认拒绝" }))
    Write-Host ("  上报间隔       : 每 {0} 分钟（安装计划任务时使用）" -f $script:Minutes)
    Write-Host "  放行 TTL       : 由 LAN Worker Self-report 目标控制，默认 3600 秒"
    if ($script:IpCheckUrls.Count -gt 0) {
        Write-Host ("  IP 探测列表    : {0}" -f ($script:IpCheckUrls -join ","))
    } else {
        Write-Host ("  首选 IP 探测   : {0}" -f $script:IpCheckUrl)
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
    $script:Minutes = Read-Default "客户端每几分钟上报一次（1-$script:MaxMinutes）" ([string]$script:Minutes)
    Assert-Minutes
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
}

function Show-ScheduledReporter {
    $taskName = "PO0 Self Report to LAN Worker"
    try {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if (-not $task) {
            Write-Host "未安装本脚本管理的计划任务。"
            return
        }
        Write-Host "已安装计划任务：$taskName"
        foreach ($trigger in $task.Triggers) {
            Write-Host ("  触发器: {0}" -f $trigger.ToString())
        }
    } catch {
        Write-Host "无法读取计划任务状态：$($_.Exception.Message)"
    }
}

function Remove-ScheduledReporter {
    $taskName = "PO0 Self Report to LAN Worker"
    try {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if (-not $task) {
            Write-Host "未安装本脚本管理的计划任务。"
            return
        }
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "已删除计划任务：$taskName"
    } catch {
        throw "删除计划任务失败：$($_.Exception.Message)"
    }
}

function Pause-Menu {
    Read-Host "按回车返回菜单" | Out-Null
}

function Invoke-InteractiveMenu {
    while ($true) {
        Show-ClientConfig
        Write-Host "------------------------"
        Write-Host "请选择操作"
        Write-Host "  1. 配置上报目标 / 间隔"
        Write-Host "  2. 立即上报一次"
        Write-Host "  3. 安装 / 更新定时上报"
        Write-Host "  4. 查看定时上报状态"
        Write-Host "  5. 删除定时上报"
        Write-Host "  6. 显示当前配置"
        Write-Host "  0. 退出"
        Write-Host "------------------------"
        $rawChoice = Read-Host "请选择操作 [0-6]"
        if ($null -eq $rawChoice) { return }
        $choice = $rawChoice.Trim()
        try {
            switch ($choice) {
                "1" { Set-ClientConfigInteractive; Pause-Menu }
                "2" {
                    if (-not $script:WorkerUrl) { Set-ClientConfigInteractive }
                    Invoke-SelfReport
                    Pause-Menu
                }
                "3" { Set-ClientConfigInteractive; Install-ScheduledReporter; Pause-Menu }
                "4" { Show-ScheduledReporter; Pause-Menu }
                "5" {
                    $confirm = Read-Host "确认删除 self-report 定时上报 [y/N]"
                    if ($null -eq $confirm) { $confirm = "" }
                    if ($confirm -match "^(y|yes)$") {
                        Remove-ScheduledReporter
                    } else {
                        Write-Host "已取消。"
                    }
                    Pause-Menu
                }
                "6" { Show-ClientConfig; Pause-Menu }
                "0" { return }
                "" {}
                default { Write-Host "无效选择。"; Pause-Menu }
            }
        } catch {
            Write-Host $_.Exception.Message
            Pause-Menu
        }
    }
}

if ($Help) {
    Show-Usage
    exit 0
}

if ($Menu -or (-not $PSBoundParameters.ContainsKey("WorkerUrl") -and -not $InstallTask -and [Environment]::UserInteractive)) {
    Invoke-InteractiveMenu
    exit 0
}

if ($InstallTask) {
    Install-ScheduledReporter
} else {
    Invoke-SelfReport
}
