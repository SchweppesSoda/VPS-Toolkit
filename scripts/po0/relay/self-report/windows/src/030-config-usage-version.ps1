function Load-SavedConfig {
    $readPath = $script:ConfigPath
    $legacyConfig = Get-LegacyConfigPath
    if (-not (Test-Path -LiteralPath $readPath) -and -not $script:ConfigPathExplicit -and (Test-Path -LiteralPath $legacyConfig)) {
        $readPath = $legacyConfig
    }
    if (-not (Test-Path -LiteralPath $readPath)) { return }
    $raw = Get-Content -LiteralPath $readPath -Raw -Encoding UTF8
    if (-not $raw.Trim()) { return }
    $cfg = $raw | ConvertFrom-Json

    foreach ($channelField in @("WorkerAutoEnabled", "OfficialAutoEnabled", "WorkerTimerEnabled", "OfficialTimerEnabled", "WorkerNetworkEnabled", "OfficialNetworkEnabled", "OfficialIntervalSeconds", "WorkerName", "Po0FirewallNames")) {
        if ($channelField -eq "OfficialIntervalSeconds" -and $PSBoundParameters.ContainsKey("OfficialIntervalSeconds")) { continue }
        $channelProperty = $cfg.PSObject.Properties[$channelField]
        if ($channelProperty -and $null -ne $channelProperty.Value) {
            if ($channelField -like "*Enabled") { Set-Variable -Scope Script -Name $channelField -Value ([bool]$channelProperty.Value) }
            else { Set-Variable -Scope Script -Name $channelField -Value ([string]$channelProperty.Value) }
        }
    }
    $tokenProperty = $cfg.PSObject.Properties["PO0_FIREWALL_TOKENS"]
    if (-not $script:Po0FirewallTokensEnvironmentSet -and $tokenProperty -and $null -ne $tokenProperty.Value) {
        $script:Po0FirewallTokens = [string]$tokenProperty.Value
    }

    if (-not $PSBoundParameters.ContainsKey("WorkerUrl") -and -not $env:PO0_OUTBOUND_IP_REPORT_WORKER_URL -and -not $env:PO0_LAN_WORKER_URL -and -not $env:WORKER_URL -and $cfg.WorkerUrl) {
        $script:WorkerUrl = [string]$cfg.WorkerUrl
    }
    if (-not $PSBoundParameters.ContainsKey("SourceId") -and -not $env:PO0_OUTBOUND_IP_REPORT_SOURCE -and -not $env:PO0_SELF_REPORT_SOURCE -and -not $env:SOURCE_ID -and $cfg.SourceId) {
        $script:SourceId = [string]$cfg.SourceId
    }
    if (-not $PSBoundParameters.ContainsKey("Identity") -and -not $env:PO0_OUTBOUND_IP_REPORT_IDENTITY -and -not $env:PO0_SELF_REPORT_IDENTITY -and -not $env:IDENTITY -and $cfg.Identity) {
        $script:Identity = [string]$cfg.Identity
    }
    if (-not $PSBoundParameters.ContainsKey("Secret") -and -not $env:PO0_OUTBOUND_IP_REPORT_SECRET -and -not $env:PO0_SELF_REPORT_SECRET -and -not $env:SELF_REPORT_SECRET -and $null -ne $cfg.Secret) {
        $script:Secret = [string]$cfg.Secret
    }
    if (-not $PSBoundParameters.ContainsKey("IpCheckUrl") -and -not $env:PO0_OUTBOUND_IP_REPORT_IP_CHECK_URL -and -not $env:IP_CHECK_URL -and $cfg.IpCheckUrl) {
        $script:IpCheckUrl = [string]$cfg.IpCheckUrl
    }
    if (-not $PSBoundParameters.ContainsKey("IpCheckUrls") -and -not $env:PO0_OUTBOUND_IP_REPORT_IP_CHECK_URLS -and -not $env:IP_CHECK_URLS -and $cfg.IpCheckUrls) {
        $script:IpCheckUrls = @($cfg.IpCheckUrls | Where-Object { $_ })
    }
    if (-not $script:SkipWifiSsidsExplicit -and -not $env:PO0_OUTBOUND_IP_REPORT_SKIP_WIFI_SSIDS -and $null -ne $cfg.SkipWifiSsids) {
        $script:SkipWifiSsids = ConvertTo-WifiSsidPolicyList -Value $cfg.SkipWifiSsids
    }
    if (-not $PSBoundParameters.ContainsKey("IntervalSeconds") -and -not $PSBoundParameters.ContainsKey("Minutes") -and -not $env:PO0_OUTBOUND_IP_REPORT_INTERVAL_SECONDS -and -not $env:PO0_SELF_REPORT_INTERVAL_SECONDS -and -not $env:INTERVAL_SECONDS -and -not $env:PO0_OUTBOUND_IP_REPORT_MINUTES -and -not $env:PO0_SELF_REPORT_MINUTES -and -not $env:MINUTES -and $cfg.IntervalSeconds) {
        $script:IntervalSeconds = [int]$cfg.IntervalSeconds
    } elseif (-not $PSBoundParameters.ContainsKey("Minutes") -and -not $env:PO0_OUTBOUND_IP_REPORT_MINUTES -and -not $env:PO0_SELF_REPORT_MINUTES -and -not $env:MINUTES -and $cfg.Minutes) {
        $script:Minutes = [int]$cfg.Minutes
    }
    if (-not $PSBoundParameters.ContainsKey("LogPath") -and -not $env:PO0_OUTBOUND_IP_REPORT_LOG -and -not $env:PO0_SELF_REPORT_LOG -and -not $env:SELF_REPORT_LOG -and $cfg.LogPath) {
        $script:LogPath = [string]$cfg.LogPath
        Normalize-DefaultLogPath
    }
    if (-not $PSBoundParameters.ContainsKey("AllowHttp") -and -not $env:PO0_OUTBOUND_IP_REPORT_ALLOW_HTTP -and -not $env:PO0_SELF_REPORT_ALLOW_HTTP -and $null -ne $cfg.AllowHttp) {
        $script:AllowHttp = [bool]$cfg.AllowHttp
    }
    if ($null -ne $cfg.SchedulePaused) {
        $script:SchedulePaused = [bool]$cfg.SchedulePaused
    }
    if (-not $PSBoundParameters.ContainsKey("Notify") -and -not $PSBoundParameters.ContainsKey("NoNotify") -and $null -ne $cfg.Notify) {
        $script:TaskNotify = [bool]$cfg.Notify
    }
    if ($readPath -ne $script:ConfigPath -and -not $script:ConfigPathExplicit) {
        Save-ClientConfig
    }
}

function Normalize-DefaultLogPath {
    if (-not $script:LogPath -or $script:LogPathExplicit) { return }
    try {
        $current = [System.IO.Path]::GetFullPath($script:LogPath)
        $legacy = [System.IO.Path]::GetFullPath((Get-LegacyLogPath))
        if ([System.String]::Equals($current, $legacy, [System.StringComparison]::OrdinalIgnoreCase)) {
            $script:LogPath = ""
        }
    } catch {}
}

function Set-Po0ClientConfigAcl {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        throw "配置文件不存在，无法设置权限。"
    }
    $acl = Get-Acl -LiteralPath $Path
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($existing in @($acl.Access)) {
        [void]$acl.RemoveAccessRule($existing)
    }
    $identities = @(
        ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User,
        (New-Object -TypeName System.Security.Principal.SecurityIdentifier -ArgumentList "S-1-5-32-544"),
        (New-Object -TypeName System.Security.Principal.SecurityIdentifier -ArgumentList "S-1-5-18")
    )
    foreach ($identity in $identities) {
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList @(
            $identity,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        [void]$acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}

function Write-Po0ClientConfigAtomic {
    param(
        [string]$Path,
        [string]$Json
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $tmp = "{0}.{1}.{2}.tmp" -f $Path, $PID, ([guid]::NewGuid().ToString("N"))
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    try {
        [System.IO.File]::WriteAllText($tmp, $Json, $utf8Bom)
        Set-Po0ClientConfigAcl -Path $tmp
        Move-Item -LiteralPath $tmp -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $tmp) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
}

function Save-ClientConfig {
    Assert-Minutes
    $dir = Split-Path -Parent $script:ConfigPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $config = [ordered]@{
        WorkerAutoEnabled = [bool]$script:WorkerAutoEnabled
        OfficialAutoEnabled = [bool]$script:OfficialAutoEnabled
        OfficialIntervalSeconds = [int]$script:OfficialIntervalSeconds
        WorkerTimerEnabled = [bool]$script:WorkerTimerEnabled
        OfficialTimerEnabled = [bool]$script:OfficialTimerEnabled
        WorkerNetworkEnabled = [bool]$script:WorkerNetworkEnabled
        OfficialNetworkEnabled = [bool]$script:OfficialNetworkEnabled
        WorkerName = $script:WorkerName
        Po0FirewallNames = $script:Po0FirewallNames
        PO0_FIREWALL_TOKENS = $script:Po0FirewallTokens
        WorkerUrl = $script:WorkerUrl
        SourceId = $script:SourceId
        Identity = $script:Identity
        Secret = $script:Secret
        AllowHttp = [bool]$script:AllowHttp
        Minutes = [int]$script:Minutes
        IntervalSeconds = [int](Get-IntervalSeconds)
        IpCheckUrl = $script:IpCheckUrl
        IpCheckUrls = @($script:IpCheckUrls)
        SkipWifiSsids = @($script:SkipWifiSsids)
        LogPath = $script:LogPath
        SchedulePaused = [bool]$script:SchedulePaused
        Notify = [bool]$script:TaskNotify
    }
    $json = $config | ConvertTo-Json -Depth 4
    Write-Po0ClientConfigAtomic -Path $script:ConfigPath -Json $json
    Write-SelfReportCompleted "配置已保存：$script:ConfigPath"
}

function Show-Usage {
    @"
PO0 Outbound IP Report 客户端（Windows PowerShell）

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
  -ConfigPath PATH    本地配置文件；默认 outbound-ip-report.json，旧 self-report.json 仅作 fallback。
  -SaveConfig         保存当前参数到本地配置文件，不安装计划任务。
  -RunOnce            从参数或已保存配置立即上报一次，不进入交互菜单。
  -OfficialStatus     只读查看官方防火墙状态；GET 失败或未命中都不会执行 POST。
  -OfficialOnly       只执行官方防火墙通道；不影响已保存的 LAN Worker 配置。
  -WorkerOnly         只执行 LAN Worker 通道；跳过官方防火墙通道。
  -ClearPo0FirewallTokens 清空内存中的官方 token；与 -SaveConfig 一起使用才持久化。
                      token 只从 PO0_FIREWALL_TOKENS 环境变量、配置文件或交互菜单读取，
                      不接受任何把 token 值放入命令行的参数。
  -WorkerUrl URL      LAN Worker self-report HTTPS 接收地址；裸域名会自动补全。
  -AllowHttp          允许 http:// 上报；仅用于本地调试或临时旧环境。
  -SourceId ID        写入 PO0 client_ip 记录的来源 ID。默认: 计算机名。
  -Identity ID        LAN Worker/PO0 日志里的设备或用户标签。默认: 计算机名。
  -Secret SECRET      可选的 LAN Worker self-report 共享密钥。
  -IpCheckUrl URL     第一个公网 IPv4 探测地址。默认: $($script:IpCheckUrl)
  -IpCheckUrls URL[]  覆盖完整探测地址列表。
  -SkipWifiSsids LIST 当前 Wi-Fi SSID 命中时跳过上报；分号分隔，trim 后大小写敏感精确匹配。
                      也可用 PO0_OUTBOUND_IP_REPORT_SKIP_WIFI_SSIDS 或 JSON SkipWifiSsids 配置。
  -ForceReport        忽略 Wi-Fi SSID 跳过规则，强制探测并上报一次。
  -InstallTask        安装 / 更新 Windows 计划任务。
  -PauseSchedule      暂停计划任务；手动立即上报仍可用。
  -ResumeSchedule     恢复计划任务。
  -ScheduleStatus     查看计划任务状态。
  -ScheduleChannel all|worker|official  选择安装、启停或删除的通道，默认 all。
  -OfficialIntervalSeconds N  官方周期，默认 600 秒；60..86400 且为 60 的倍数。
  -RemoveTask         删除所选通道的定时和网络变化任务。
  -RefreshSchedules   只更新已有任务，迁移旧共享任务。
  -IntervalSeconds N  计划任务间隔秒数，必须是 60 的倍数。默认: 3600。
  -Minutes N          兼容旧参数：计划任务间隔分钟数，范围 1-$MaxMinutes。默认: 60。
  -LogPath PATH       计划任务运行日志路径；默认 po0-outbound-ip-report.log。
  -Notify             上报完成或失败时显示 Windows 通知；安装计划任务时显式启用。
  -NoNotify           显式关闭 Windows 通知 / 使用静默模式；不能与 -Notify 同时使用。
                      放行时长由 LAN Worker 接收端配置，不由客户端决定。

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

function Get-ScriptBuildLabel {
    if ($ScriptVersion -like "*+*") {
        return ($ScriptVersion -split "\+", 2)[1]
    }
    return "未标识"
}

function Show-ScriptVersion {
    $current = $(if ($PSCommandPath) { $PSCommandPath } else { "未知" })
    Write-Host "脚本名称：$ScriptName"
    Write-Host "版本：$ScriptVersion"
    Write-Host "构建标识：$(Get-ScriptBuildLabel)"
    Write-Host "发布日期：$ScriptReleaseDate"
    Write-Host "当前脚本：$current"
    Write-Host "默认安装路径：$(Get-DefaultScriptPath)"
    Write-Host "配置文件：$script:ConfigPath"
    Write-Host "运行日志：$(Get-DefaultLogPath)"
    Write-Host "计划任务：$(Get-ScheduledReporterSummary)"
    try {
        $record = Get-ScheduledReporterTaskRecord
        $task = $record.Task
        if ($task) {
            if ($record.IsLegacy) {
                Write-Host "计划任务名称状态：旧任务名 $($record.Name)；运行 -InstallTask 或 -UpgradeSelf 可迁移到 $script:TaskName。"
            }
            $notifyState = Get-ScheduledReporterNotifyState -Task $task
            if ($notifyState.ScriptPath) {
                Write-Host "计划任务脚本：$($notifyState.ScriptPath)"
                if ($notifyState.ScriptPathIsLegacy) {
                    Write-Host "计划任务脚本状态：旧 po0-self-report.ps1 路径；运行 -InstallTask 或 -UpgradeSelf 可迁移到新路径。"
                } elseif (-not $notifyState.ScriptPathExists) {
                    Write-Host "计划任务脚本状态：目标不存在；请重新运行 -InstallTask。"
                }
            } else {
                Write-Host "计划任务脚本：无法从任务动作或计划任务启动文件读取"
            }
        }
    } catch {
        Write-Host "计划任务脚本：读取失败：$($_.Exception.Message)"
    }
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
