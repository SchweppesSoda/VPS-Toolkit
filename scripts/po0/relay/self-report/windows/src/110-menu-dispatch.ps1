function Pause-Menu {
    Read-Host "按回车返回菜单" | Out-Null
}

function Show-ClientOverview {
    Write-Title "PO0 出口上报"
    Write-PanelRow "客户端版本" $ScriptVersion
    Write-PanelRow "配置" $(if (Test-Path -LiteralPath $script:ConfigPath) { "已保存在本机" } else { "尚未保存" })
    Write-PanelRow "自建 PO0" $(if ($script:WorkerUrl) { "$(if ($script:WorkerName) { $script:WorkerName } else { 'LAN Worker' }) · $(Get-ChannelAutoLabel worker)" } else { "未配置" })
    Write-PanelRow "官方防火墙" $(if (Test-Po0FirewallConfigured) { "$(Get-Po0FirewallTokenSummary) · $(Get-ChannelAutoLabel official)" } else { "未配置" })
    Show-OfficialTargetNames
    Write-PanelRow "自动上报计划" (Get-ScheduledReporterSummary)
    Write-PanelRow "SSID 跳过" (Format-WifiSsidPolicyList -Ssids $script:SkipWifiSsids)
}

function Set-ChannelNamesInteractive {
    param([ValidateSet('worker', 'official')][string]$Channel)
    if ($Channel -eq 'worker') {
        $script:WorkerName = Read-Default "自建目标名称（仅本机显示；- 清空）" $script:WorkerName
        if ($script:WorkerName -eq '-') { $script:WorkerName = '' }
    } else {
        $items = @(Get-Po0FirewallTokenItems)
        if ($items.Count -eq 0) { throw "请先保存官方 Token，再设置目标名称。" }
        $names = @()
        for ($index = 1; $index -le $items.Count; $index++) {
            $name = Read-Default "官方目标 $index 名称（仅本机显示；- 恢复默认）" (Get-OfficialAccountName $index)
            if ($name -match '[;；\r\n]') { throw "单个名称不能包含分号或换行。" }
            if ($name -eq '-') { $name = '' }
            $names += $name
        }
        $script:Po0FirewallNames = $names -join ';'
    }
    Save-ClientConfig
    Write-Host '目标名称已保存。'
}

function Invoke-ChannelInteractive {
    param([ValidateSet('all', 'worker', 'official')][string]$Channel)
    $oldOfficial = $script:Po0FirewallOfficialOnly
    $oldWorker = $script:Po0FirewallWorkerOnly
    $oldScheduled = $script:Po0FirewallScheduledRun
    try {
        $script:Po0FirewallOfficialOnly = $Channel -eq 'official'
        $script:Po0FirewallWorkerOnly = $Channel -eq 'worker'
        $script:Po0FirewallScheduledRun = $false
        if ($Channel -eq 'worker' -and -not $script:WorkerUrl) { throw '自建 PO0 尚未配置，请先编辑并保存参数。' }
        if ($Channel -eq 'official' -and -not (Test-Po0FirewallConfigured)) { throw '官方防火墙尚未配置，请先编辑并保存参数。' }
        if (-not (Test-ClientConfigComplete)) { throw '尚未配置上报通道，请先进入通道设置。' }
        Invoke-SelfReport -PromptForForceOnSkip
    } finally {
        $script:Po0FirewallOfficialOnly = $oldOfficial
        $script:Po0FirewallWorkerOnly = $oldWorker
        $script:Po0FirewallScheduledRun = $oldScheduled
    }
}

function Invoke-ChannelSettingsMenu {
    param([ValidateSet('worker', 'official')][string]$Channel)
    $title = $(if ($Channel -eq 'worker') { '自建 PO0' } else { '官方防火墙' })
    while ($true) {
        Write-Title "$title · 设置"
        Write-PanelRow '配置状态' $(if (($Channel -eq 'worker' -and $script:WorkerUrl) -or ($Channel -eq 'official' -and (Test-Po0FirewallConfigured))) { '已配置' } else { '未配置' })
        Write-PanelRow '自动开关' (Get-ChannelAutoLabel $Channel)
        if ($Channel -eq 'official') { Show-OfficialTargetNames }
        Write-PanelRow '上报间隔' $(if ($Channel -eq 'worker') { "$(Get-IntervalSeconds) 秒" } else { '固定 600 秒' })
        if ($Channel -eq 'worker') { Write-PanelRow '放行有效期' '由 LAN Worker 接收端管理' }
        else { Write-PanelRow '放行有效期 TTL' '由官方服务管理，接口未提供自定义 TTL' }
        Write-MenuItem '1' '编辑并保存参数'
        Write-MenuItem '2' '设置目标名称'
        Write-MenuItem '3' '启用 / 停用本通道自动上报'
        Write-MenuItem '4' '仅本通道立即上报'
        Write-MenuItem '5' '查看本通道状态'
        Write-MenuItem '6' '清除此通道保存的配置'
        Write-MenuItem '0' '返回主菜单'
        $choice = Read-Host '请选择 [0-6]'
        if ($null -eq $choice) { return }
        try {
            switch ($choice.Trim()) {
                '1' { if ($Channel -eq 'worker') { Set-ClientConfigInteractive } else { Set-OfficialConfigInteractive }; Update-ChannelScheduleIfInstalled }
                '2' { Set-ChannelNamesInteractive $Channel }
                '3' { Toggle-ChannelAutoInteractive $Channel; Update-ChannelScheduleIfInstalled }
                '4' { Invoke-ChannelInteractive $Channel }
                '5' {
                    if ($Channel -eq 'official') { Show-OfficialStatusInteractive } else {
                        Write-PanelSection '自建 PO0 · 本机状态'
                        Write-PanelRow '目标名称' $(if ($script:WorkerName) { $script:WorkerName } else { 'LAN Worker' })
                        Write-PanelRow '接收地址' $(if ($script:WorkerUrl) { $script:WorkerUrl } else { '未配置' })
                        Write-PanelRow '自动上报' (Get-ChannelAutoLabel worker)
                        Show-ScheduledReporter
                    }
                }
                '6' { if ($Channel -eq 'worker') { Clear-WorkerConfigInteractive } else { Clear-OfficialConfigInteractive }; Update-ChannelScheduleIfInstalled }
                '0' { return }
                default { Write-Host '无效选择：请输入 0-6。' }
            }
        } catch { Write-SelfReportIncomplete $_.Exception.Message }
        Pause-Menu
    }
}

function Invoke-AutomaticReportingMenu {
    while ($true) {
        Write-Title '自动上报 · 两个通道共用一个计划'
        Write-PanelRow '自建 PO0' (Get-ChannelAutoLabel worker)
        Write-PanelRow '官方防火墙' (Get-ChannelAutoLabel official)
        Write-PanelRow '计划状态' (Get-ScheduledReporterSummary)
        Write-Host '安装后自动处理两个已配置且启用的通道，各自按自己的间隔上报。'
        Write-MenuItem '1' '安装 / 更新自动上报'
        Write-MenuItem '2' '暂停 / 恢复全部自动上报'
        Write-MenuItem '3' '查看计划状态和日志'
        Write-MenuItem '4' '删除自动上报计划'
        Write-MenuItem '5' '通知 / 静默设置'
        Write-MenuItem '0' '返回主菜单'
        $choice = Read-Host '请选择 [0-5]'
        if ($null -eq $choice) { return }
        try {
            switch ($choice.Trim()) {
                '1' { Install-ScheduledReporterInteractive }
                '2' { Toggle-ScheduledReporterPaused }
                '3' { Show-ScheduledReporter }
                '4' { if (Read-YesNoDefault '删除全部自动上报计划（保留两个通道配置）' $false) { Remove-ScheduledReporter } }
                '5' { Toggle-ScheduledReporterNotify }
                '0' { return }
                default { Write-Host '无效选择：请输入 0-5。' }
            }
        } catch { Write-SelfReportIncomplete $_.Exception.Message }
        Pause-Menu
    }
}

function Invoke-ClientMaintenanceMenu {
    while ($true) {
        Write-Title '维护与诊断'
        Write-PanelRow '脚本路径' $PSCommandPath
        Write-PanelRow '配置文件' $script:ConfigPath
        Write-PanelRow '运行日志' (Get-DefaultLogPath)
        Write-MenuItem '1' '更新客户端脚本'
        Write-MenuItem '2' '卸载客户端'
        Write-MenuItem '0' '返回主菜单'
        $choice = Read-Host '请选择 [0-2]'
        if ($null -eq $choice) { return }
        switch ($choice.Trim()) {
            '1' { Upgrade-SelfFromDownload -ReopenMenu }
            '2' {
                if (Read-YesNoDefault '卸载客户端与自动上报计划' $false) {
                    $removeData = Read-YesNoDefault '同时删除本机配置和日志' $false
                    Uninstall-SelfReportClient -RemoveData:$removeData
                    $script:ClientMenuUninstalled = $true
                    Pause-Menu
                    return
                }
            }
            '0' { return }
            default { Write-Host '无效选择：请输入 0-2。' }
        }
        Pause-Menu
    }
}

function Invoke-InteractiveMenu {
    $script:ClientMenuUninstalled = $false
    while ($true) {
        Show-ClientOverview
        Write-MenuSection '通道设置'
        Write-MenuItem '1' '自建 PO0'
        Write-MenuItem '2' '官方防火墙'
        Write-MenuSection '通用操作'
        Write-MenuItem '3' '网络探测 / SSID 跳过'
        Write-MenuItem '4' '立即上报全部已配置通道'
        Write-MenuItem '5' '自动上报管理'
        Write-MenuItem '6' '查看完整保存配置'
        Write-MenuItem '7' '维护与诊断'
        Write-MenuItem '0' '退出'
        Write-MenuDivider
        $choice = Read-Host '请选择 [0-7]'
        if ($null -eq $choice) { return }
        try {
            switch ($choice.Trim()) {
                '1' { Invoke-ChannelSettingsMenu worker }
                '2' { Invoke-ChannelSettingsMenu official }
                '3' { Set-CommonConfigInteractive; Pause-Menu }
                '4' { Invoke-ChannelInteractive all; Pause-Menu }
                '5' { Invoke-AutomaticReportingMenu }
                '6' { Show-ClientConfig; Pause-Menu }
                '7' { Invoke-ClientMaintenanceMenu; if ($script:ClientMenuUninstalled) { return } }
                '0' { return }
                default { Write-Host '无效选择：请输入 0-7。'; Pause-Menu }
            }
        } catch {
            Write-SelfReportIncomplete $_.Exception.Message
            Pause-Menu
        }
    }
}
