# Local controls and scheduler entries are independent for each channel.
$script:OfficialIntervalSeconds = $OfficialIntervalSeconds
$script:WorkerTimerEnabled = $true
$script:OfficialTimerEnabled = $true
$script:WorkerNetworkEnabled = $true
$script:OfficialNetworkEnabled = $true
$script:WorkerAutoEnabled = $true
$script:OfficialAutoEnabled = $true
$script:WorkerName = ""
$script:Po0FirewallNames = ""

function Get-ChannelAutoLabel {
    param([ValidateSet("worker", "official")][string]$Channel)
    $enabled = if ($Channel -eq "worker") { $script:WorkerAutoEnabled } else { $script:OfficialAutoEnabled }
    if ($enabled) { return "已启用" }
    return "已停用（保留配置）"
}

function Get-OfficialAccountName {
    param([int]$Index)
    $names = @(([string]$script:Po0FirewallNames) -split '[;；\r\n]')
    if ($Index -gt 0 -and $Index -le $names.Count -and $names[$Index - 1].Trim()) { return $names[$Index - 1].Trim() }
    return "官方账号 $Index"
}

function Show-OfficialTargetNames {
    try { $count = @(Get-Po0FirewallTokenItems).Count } catch { return }
    for ($index = 1; $index -le $count; $index++) {
        Write-PanelRow "官方目标 $index" (Get-OfficialAccountName $index)
    }
}

function Toggle-ChannelAutoInteractive {
    param([ValidateSet("worker", "official")][string]$Channel)
    Set-ScheduledReporterPaused -Paused (-not (Test-ChannelAutoPaused $Channel)) -Channel $Channel
    Write-Host "自动上报：$(Get-ChannelAutoLabel $Channel)。手动上报仍可使用。"
}

function Clear-WorkerConfigInteractive {
    if (-not (Read-YesNoDefault "清除本机自建防火墙地址、密钥和目标名称（保留官方及通用设置）" $false)) { return }
    $script:WorkerUrl = ""
    $script:Secret = ""
    $script:WorkerName = ""
    $script:WorkerAutoEnabled = $false
    Save-ClientConfig
}

function Update-ChannelScheduleIfInstalled {
    param([ValidateSet('all','worker','official')][string]$Channel='all')
    Sync-ScheduledReporterTasks -Mode refresh -Channel $Channel | Out-Null
}
function Test-ChannelAutoPaused {
    param([string]$Channel)
    $enabled = if ($Channel -eq 'official') { $script:OfficialAutoEnabled } else { $script:WorkerAutoEnabled }
    return [bool]($script:SchedulePaused -or -not $enabled)
}

function Sync-OfficialAccountNames {
    param([AllowEmptyString()][string]$PreviousTokens)
    $oldNames = @(([string]$script:Po0FirewallNames) -split '[;；\r\n]')
    $oldItems = @($PreviousTokens -split '[,;，；\s]+' | Where-Object { $_ })
    $mapped = [System.Collections.Generic.Dictionary[string,string]]::new([System.StringComparer]::Ordinal)
    for ($i = 0; $i -lt $oldItems.Count; $i++) {
        if ($i -lt $oldNames.Count) { $mapped[($oldItems[$i] -split '@')[0]] = $oldNames[$i] }
    }
    $newNames = @(foreach ($item in @(Get-Po0FirewallTokenItems)) {
        if ($mapped.ContainsKey($item.Token)) { $mapped[$item.Token] } else { '' }
    })
    $script:Po0FirewallNames = $newNames -join ';'
}


function Get-ChannelIntervalLabel {
    param([string]$Channel)
    $enabled = if ($Channel -eq 'official') { $script:OfficialTimerEnabled } else { $script:WorkerTimerEnabled }
    return "$(Get-ChannelIntervalSeconds $Channel) 秒" + $(if ($enabled) { '' } else { '（暂不使用）' })
}

function Set-ChannelPeriodicInteractive {
    param([ValidateSet('worker','official')][string]$Channel)
    $enabled = if ($Channel -eq 'official') { $script:OfficialTimerEnabled } else { $script:WorkerTimerEnabled }
    $nextEnabled = Read-YesNoDefault '启用定期上报（关闭保留网络变化触发和原间隔）' $enabled
    $maximum = if ($Channel -eq 'worker') { $script:MaxMinutes * 60 } else { 86400 }
    $value = Read-Default "上报间隔（秒，60..$maximum，60 的倍数；定期关闭时暂不使用）" ([string](Get-ChannelIntervalSeconds $Channel))
    $seconds = 0
    if (-not [int]::TryParse($value,[ref]$seconds) -or $seconds -lt 60 -or $seconds -gt $maximum -or $seconds % 60) { throw '无效上报间隔。' }
    if ($Channel -eq 'official') { $script:OfficialTimerEnabled = $nextEnabled; $script:OfficialIntervalSeconds = $seconds }
    else { $script:WorkerTimerEnabled = $nextEnabled; $script:Minutes = $seconds / 60 }
    Save-ClientConfig
    Update-ChannelScheduleIfInstalled $Channel
}

function Show-ChannelConfig {
    param([string]$Channel)
    Write-PanelSection '本机配置'
    Write-PanelRow '自动上报' (Get-ChannelAutoLabel $Channel)
    Write-PanelRow '上报间隔' (Get-ChannelIntervalLabel $Channel)
    if ($Channel -eq 'official') {
        Show-OfficialTargetNames
        Write-PanelRow 'Token / 槽位' $script:Po0FirewallTokens
        Write-PanelRow '白名单有效期（TTL）' '由官方服务管理'
    } elseif (Test-ChannelConfigured worker) {
        Write-PanelRow '目标名称' $script:WorkerName
        Write-PanelRow '接收地址' $script:WorkerUrl
        Write-PanelRow '上报密钥' $script:Secret
        Write-PanelRow '来源 ID' $script:SourceId
        Write-PanelRow '备注' $script:Identity
        Write-PanelRow '白名单有效期（TTL）' '由 LAN Worker 接收端管理'
    } else { Write-PanelRow '自建防火墙' '未配置（进入保存配置填写）' }
}

function Invoke-ChannelForceInteractive {
    param([string]$Channel)
    $oldForce = $script:ForceReport
    $oldOfficialForce = $script:Po0FirewallForce
    try { $script:ForceReport = $true; $script:Po0FirewallForce = $true; Invoke-ChannelInteractive $Channel }
    finally { $script:ForceReport = $oldForce; $script:Po0FirewallForce = $oldOfficialForce }
}
