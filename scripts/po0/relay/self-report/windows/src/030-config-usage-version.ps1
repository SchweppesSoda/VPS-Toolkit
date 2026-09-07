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

    foreach ($channelField in @("OfficialAutoEnabled", "OfficialTimerEnabled", "OfficialNetworkEnabled", "OfficialIntervalSeconds", "Po0FirewallNames")) {
        if ($channelField -eq "OfficialIntervalSeconds" -and $PSBoundParameters.ContainsKey("OfficialIntervalSeconds")) { continue }
        $channelProperty = $cfg.PSObject.Properties[$channelField]
        if ($channelProperty -and $null -ne $channelProperty.Value) {
            if ($channelField -like "*Enabled") { Set-Variable -Scope Script -Name $channelField -Value ([string]$channelProperty.Value -notmatch "^(?i:0|false|off|no)$") }
            else { Set-Variable -Scope Script -Name $channelField -Value ([string]$channelProperty.Value) }
        }
    }
    $tokenProperty = $cfg.PSObject.Properties["PO0_FIREWALL_TOKENS"]
    if (-not $script:Po0FirewallTokensEnvironmentSet -and $tokenProperty -and $null -ne $tokenProperty.Value) {
        $script:Po0FirewallTokens = [string]$tokenProperty.Value
    }

    if (-not $PSBoundParameters.ContainsKey("IpCheckUrl") -and -not $env:PO0_OUTBOUND_IP_REPORT_IP_CHECK_URL -and -not $env:IP_CHECK_URL -and $cfg.PSObject.Properties["IpCheckUrl"] -and $cfg.IpCheckUrl) {
        $script:IpCheckUrl = [string]$cfg.IpCheckUrl
    }
    if (-not $PSBoundParameters.ContainsKey("IpCheckUrls") -and -not $env:PO0_OUTBOUND_IP_REPORT_IP_CHECK_URLS -and -not $env:IP_CHECK_URLS -and $cfg.PSObject.Properties["IpCheckUrls"] -and $cfg.IpCheckUrls) {
        $script:IpCheckUrls = @($cfg.IpCheckUrls | Where-Object { $_ })
    }
    if (-not $script:SkipWifiSsidsExplicit -and -not $env:PO0_OUTBOUND_IP_REPORT_SKIP_WIFI_SSIDS -and $cfg.PSObject.Properties["SkipWifiSsids"] -and $null -ne $cfg.SkipWifiSsids) {
        $script:SkipWifiSsids = ConvertTo-WifiSsidPolicyList -Value $cfg.SkipWifiSsids
    }
    if (-not $PSBoundParameters.ContainsKey("LogPath") -and -not $env:PO0_OUTBOUND_IP_REPORT_LOG -and -not $env:PO0_SELF_REPORT_LOG -and -not $env:SELF_REPORT_LOG -and $cfg.PSObject.Properties["LogPath"] -and $cfg.LogPath) {
        $script:LogPath = [string]$cfg.LogPath
        Normalize-DefaultLogPath
    }
    if ($cfg.PSObject.Properties["SchedulePaused"] -and $null -ne $cfg.SchedulePaused) {
        $script:SchedulePaused = [bool]$cfg.SchedulePaused
    }
    if (-not $PSBoundParameters.ContainsKey("Notify") -and -not $PSBoundParameters.ContainsKey("NoNotify") -and $cfg.PSObject.Properties["Notify"] -and $null -ne $cfg.Notify) {
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
    param([switch]$Quiet)
    Backup-RetiredConfig
    $dir = Split-Path -Parent $script:ConfigPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $config = [ordered]@{
        OfficialAutoEnabled = [bool]$script:OfficialAutoEnabled
        OfficialIntervalSeconds = [int]$script:OfficialIntervalSeconds
        OfficialTimerEnabled = [bool]$script:OfficialTimerEnabled
        OfficialNetworkEnabled = [bool]$script:OfficialNetworkEnabled
        Po0FirewallNames = $script:Po0FirewallNames
        PO0_FIREWALL_TOKENS = $script:Po0FirewallTokens
        IpCheckUrl = $script:IpCheckUrl
        IpCheckUrls = @($script:IpCheckUrls)
        SkipWifiSsids = @($script:SkipWifiSsids)
        LogPath = $script:LogPath
        SchedulePaused = [bool]$script:SchedulePaused
        Notify = [bool]$script:TaskNotify
    }
    $json = $config | ConvertTo-Json -Depth 4
    Write-Po0ClientConfigAtomic -Path $script:ConfigPath -Json $json
    if (-not $Quiet) { Write-SelfReportCompleted "配置已保存：$script:ConfigPath" }
}

function Show-Usage {
    Write-Host @'
PO0 官方防火墙客户端（Windows）
-Menu / -Version / -Changelog / -UpgradeSelf
-ConfigPath PATH / -SaveConfig / -RunOnce / -OfficialOnly
-OfficialStatus：只读查询 / -ClearPo0FirewallTokens
-SkipWifiSsids LIST / -ForceReport
-OfficialIntervalSeconds N / -InstallTask / -RefreshSchedules
-PauseSchedule / -ResumeSchedule / -ScheduleStatus / -RemoveTask
-MigrateRetiredState：备份旧配置与任务，再清理自建任务，保留官方设置。
Token、槽位及名称在本机配置页编辑和保存，不通过命令行传递。
'@
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
