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
    if (-not (Read-YesNoDefault "清除本机自建 PO0 地址、密钥和目标名称（保留官方及通用设置）" $false)) { return }
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
