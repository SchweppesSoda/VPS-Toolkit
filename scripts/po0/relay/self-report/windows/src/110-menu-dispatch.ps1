function Pause-Menu {
    Read-Host "按回车返回菜单" | Out-Null
}

function Show-RecentReportResults {
    Show-Po0FirewallCached
    Write-PanelSection '近期运行记录'
    Show-SelfReportLogTail -Path (Get-ChannelLogPath official)
}

function Show-ClientOverview {
    Write-Title 'PO0 防火墙' $ScriptVersion
    Write-PanelStatusRow '自动上报' (Get-ChannelAutoLabel official)
    Write-PanelStatusRow '定期上报' (Get-ChannelPeriodicLabel official)
    Write-PanelStatusRow '计划任务' ((Get-ScheduledReporterSummary official) -replace '；周期 .*$', '')
    Show-OfficialTargetNames
    Show-Po0FirewallCached -Summary
}

function Set-ChannelNamesInteractive {
    param([ValidateSet('worker', 'official')][string]$Channel)
        $items = @(Get-Po0FirewallTokenItems)
        if ($items.Count -eq 0) { throw "请先在「官方账号与槽位」中保存 Token，再设置账号名称。" }
        $names = @()
        for ($index = 1; $index -le $items.Count; $index++) {
            $name = Read-Default "账号 $index 名称（仅本机显示；- 恢复默认）" (Get-OfficialAccountName $index)
            if ($name -match '[;；\r\n]') { throw "单个名称不能包含分号或换行。" }
            if ($name -eq '-') { $name = '' }
            $names += $name
        }
        $script:Po0FirewallNames = $names -join ';'
    Save-ClientConfig
    Write-Host '账号名称已保存。'
}

function Invoke-ChannelInteractive {
    param([ValidateSet('all', 'worker', 'official')][string]$Channel)
    $oldOfficial = $script:Po0FirewallOfficialOnly
    $oldWorker = $script:Po0FirewallWorkerOnly
    $oldScheduled = $script:Po0FirewallScheduledRun
    $oldLogPath = $script:LogPath
    try {
        if ($Channel -ne 'all') { $script:LogPath = Get-ChannelLogPath $Channel }
        $script:Po0FirewallOfficialOnly = $Channel -eq 'official'
        $script:Po0FirewallWorkerOnly = $Channel -eq 'worker'
        $script:Po0FirewallScheduledRun = $false
        if ($Channel -eq 'worker' -and -not $script:WorkerUrl) { throw '自建防火墙尚未配置，请先编辑并保存参数。' }
        if ($Channel -eq 'official' -and -not (Test-Po0FirewallConfigured)) { throw '尚未保存官方账号，请先在「官方账号与槽位」中保存 Token。' }
        if (-not (Test-ClientConfigComplete)) { throw '本机配置不完整，请先检查「官方账号与槽位」。' }
        Invoke-SelfReport -PromptForForceOnSkip
    } catch {
        Write-SelfReportLogLine 'ERROR' '手动上报未完成。'
        throw
    } finally {
        $script:LogPath = $oldLogPath
        $script:Po0FirewallOfficialOnly = $oldOfficial
        $script:Po0FirewallWorkerOnly = $oldWorker
        $script:Po0FirewallScheduledRun = $oldScheduled
    }
}

# Account settings only; reporting and query actions live in the main menu.
function Invoke-OfficialAccountMenu {
    while ($true) {
        Write-Title 'PO0 防火墙 · 官方账号与槽位'
        Write-PanelStatusRow '配置状态' $(if (Test-ChannelConfigured official) { '已配置' } else { '未配置' })
        Show-OfficialTargetNames
        Write-Po0UiText ''
        Write-MenuItem '1' '编辑 Token 与槽位'
        Write-MenuItem '2' '设置账号名称'
        Write-MenuItem '3' '清除官方账号'
        Write-MenuItem '0' '返回主菜单'
        $choice = Read-Host '请选择 [0-3]'
        if ($null -eq $choice) { return }
        try {
            switch ($choice.Trim()) {
                '1' { Set-OfficialConfigInteractive; Update-ChannelScheduleIfInstalled official }
                '2' { Set-ChannelNamesInteractive official }
                '3' { Clear-OfficialConfigInteractive; Update-ChannelScheduleIfInstalled official }
                '0' { return }
                default { throw '无效选择：请输入 0-3。' }
            }
        } catch { Write-Po0UiText $_.Exception.Message -Color Red }
        Pause-Menu
    }
}

# One place for the switch, interval and scheduler task of automatic reports.
function Invoke-AutomaticReportingMenu {
    while ($true) {
        Write-Title 'PO0 防火墙 · 自动上报与计划任务'
        Write-PanelStatusRow '自动上报' (Get-ChannelAutoLabel official)
        Write-PanelStatusRow '定期上报' (Get-ChannelPeriodicLabel official)
        Write-PanelStatusRow '计划任务' (Get-ScheduledReporterSummary official)
        Write-Po0UiText ''
        Write-MenuItem '1' '安装 / 更新计划任务'
        Write-MenuItem '2' '暂停 / 恢复自动上报'
        Write-MenuItem '3' '定期上报开关与间隔'
        Write-MenuItem '4' '查看计划任务状态与日志'
        Write-MenuItem '5' '删除计划任务'
        Write-MenuItem '0' '返回主菜单'
        $choice = Read-Host '请选择 [0-5]'
        if ($null -eq $choice) { return }
        try {
            switch ($choice.Trim()) {
                '1' { Install-ScheduledReporterInteractive -Channel official }
                '2' { Toggle-ScheduledReporterPaused -Channel official }
                '3' { Set-ChannelPeriodicInteractive official }
                '4' { Show-ScheduledReporter -Channel official }
                '5' { if (Read-YesNoDefault '删除计划任务（账号与设置保留）' $false) { Remove-ScheduledReporter -Channel official; Save-ClientConfig } }
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
        Write-PanelRow '客户端版本' $ScriptVersion
        Write-PanelRow '脚本路径' $PSCommandPath
        Write-PanelRow '配置文件' $script:ConfigPath
        Write-PanelRow '运行日志' (Get-DefaultLogPath)
        Write-Po0UiText ''
        Write-MenuItem '1' '更新客户端脚本'
        Write-MenuItem '2' '迁移旧版自建配置与任务'
        Write-MenuItem '3' '卸载客户端'
        Write-MenuItem '0' '返回主菜单'
        $choice = Read-Host '请选择 [0-3]'
        if ($null -eq $choice) { return }
        switch ($choice.Trim()) {
            '1' { Upgrade-SelfFromDownload -ReopenMenu }
            '2' { Invoke-RetiredStateMigration }
            '3' {
                if (Read-YesNoDefault '卸载客户端与自动上报计划' $false) {
                    $removeData = Read-YesNoDefault '同时删除本机配置和日志' $false
                    Uninstall-SelfReportClient -RemoveData:$removeData
                    $script:ClientMenuUninstalled = $true
                    Pause-Menu
                    return
                }
            }
            '0' { return }
            default { Write-Host '无效选择：请输入 0-3。' }
        }
        Pause-Menu
    }
}

function Invoke-InteractiveMenu {
    $script:ClientMenuUninstalled = $false
    while ($true) {
        Show-ClientOverview
        Write-PanelSection '上报与查询'
        Write-MenuItem '1' '立即上报'
        Write-MenuItem '2' '查询官方白名单（只读）'
        Write-MenuItem '3' '最近上报结果'
        Write-PanelSection '设置'
        Write-MenuItem '4' '官方账号与槽位'
        Write-MenuItem '5' '自动上报与计划任务'
        Write-MenuItem '6' '网络探测与 Wi-Fi 跳过'
        Write-MenuItem '7' '查看本机配置'
        Write-PanelSection '维护'
        Write-MenuItem '8' '维护与诊断'
        Write-MenuItem '0' '退出'
        $choice = Read-Host '请选择 [0-8]'
        if ($null -eq $choice) { return }
        try {
            switch ($choice.Trim()) {
                '1' { Invoke-ChannelInteractive official; Pause-Menu }
                '2' { Show-OfficialStatusInteractive; Pause-Menu }
                '3' { Show-RecentReportResults; Pause-Menu }
                '4' { Invoke-OfficialAccountMenu }
                '5' { Invoke-AutomaticReportingMenu }
                '6' { Set-CommonConfigInteractive; Pause-Menu }
                '7' { Show-ClientConfig; Pause-Menu }
                '8' { Invoke-ClientMaintenanceMenu; if ($script:ClientMenuUninstalled) { return } }
                '0' { return }
                default { Write-Host '无效选择：请输入 0-8。'; Pause-Menu }
            }
        } catch { Write-SelfReportIncomplete $_.Exception.Message; Pause-Menu }
    }
}
