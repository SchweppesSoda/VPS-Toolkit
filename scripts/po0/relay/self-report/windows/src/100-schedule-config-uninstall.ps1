function Get-ScheduledReporterSummary {
    param([ValidateSet('all','worker','official')][string]$Channel='official')
    if ($Channel -eq 'all') { return (Get-ScheduledReporterSummary official) }
    try {
        $record = Get-ScheduledReporterTaskRecord -Channel $Channel
        if (-not $record.Task) { if ((Get-LegacyReporterRecord).Task) { return '旧共享任务，待迁移' }; return '未安装' }
        $label = if ($record.Task.State -eq 'Disabled') { '已暂停' } else { [string]$record.Task.State }
        return "$label；周期 $(Get-ChannelIntervalSeconds $Channel) 秒"
    } catch { return '无法读取' }
}

function Get-CurrentScheduledReporterNotifyState {
    try {
        $record = Get-ScheduledReporterTaskRecord
        return (Get-ScheduledReporterNotifyState -Task $record.Task)
    } catch {
        return [pscustomobject]@{
            Installed = $false
            LauncherPath = ""
            LauncherExists = $false
            ScriptPath = ""
            ScriptPathExists = $false
            ScriptPathIsLegacy = $false
            ActualNotify = $null
            HasNotify = $false
            HasNoNotify = $false
            IsUnknown = $true
        }
    }
}

function Write-NotifyStatusRows {
    param($NotifyState)
    if (-not $NotifyState) {
        $NotifyState = Get-CurrentScheduledReporterNotifyState
    }
    Write-PanelRow "Windows 通知（配置）" (Format-NotifyStatus)
    Write-PanelRow "Windows 通知（任务）" (Format-TaskNotifyStatus -NotifyState $NotifyState)
    $drift = Format-NotifyDriftStatus -NotifyState $NotifyState
    if ($drift) {
        Write-PanelRow "通知状态漂移" $drift
    }
}

function Show-ClientConfig {
    Show-ChannelConfig official
    Write-PanelRow 'SSID 跳过' ($script:SkipWifiSsids -join ';')
    Write-PanelRow '配置文件' $script:ConfigPath
}


function Set-CommonConfigInteractive {
    Write-PanelSection "通用设置 · 本机探测与 Wi-Fi 跳过"
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
    Read-WifiSsidPolicySetting
    Save-ClientConfig
}

function Set-OfficialConfigInteractive {
    Write-PanelSection "PO0 官方防火墙参数"
    Write-Host "官方定时上报可关闭、可修改，默认 600 秒；网络变化单独触发。Token 可带 @0..4 指定槽位；逗号、分号、空格或换行均可分隔。"
    $previousTokens = $script:Po0FirewallTokens
    Read-Po0FirewallTokensInteractive
    Sync-OfficialAccountNames $previousTokens
    Save-ClientConfig
}

function Clear-OfficialConfigInteractive {
    if (Read-YesNoDefault "确认清除已保存的官方防火墙 Token" $false) {
        $script:Po0FirewallTokens = ""
        $script:Po0FirewallNames = ""
        $script:OfficialAutoEnabled = $false
        Save-ClientConfig
    }
}

function Show-OfficialStatusInteractive {
    $previous = $script:Po0FirewallStatusOnly
    try {
        $script:Po0FirewallStatusOnly = $true
        Invoke-SelfReport
    } finally {
        $script:Po0FirewallStatusOnly = $previous
    }
}

function Install-ScheduledReporterInteractive {
    param([ValidateSet('all','worker','official')][string]$Channel='all')
    if ($Channel -eq 'all') { Install-ScheduledReporter -Channel all; return }
    if (-not (Test-ChannelConfigured $Channel)) { throw '请先保存本通道参数。' }
    Set-ChannelPeriodicInteractive $Channel
    Install-ScheduledReporter -Channel $Channel
}

function Show-ScheduledReporter {
    param([ValidateSet('all','worker','official')][string]$Channel=$ScheduleChannel)
    foreach ($lane in @('worker','official')) {
        if ($Channel -ne 'all' -and $Channel -ne $lane) { continue }
        Write-PanelSection $(if ($lane -eq 'worker') { '自建防火墙 · 定时任务' } else { '官方防火墙 · 定时任务' })
        $networkTask = Get-ScheduledTask -TaskName (Get-NetworkReporterTaskName $lane) -ErrorAction SilentlyContinue
        Write-PanelRow '网络变化监听' $(if (-not (Test-WindowsNetworkWatchSupported)) { '当前环境不可用，跳过检测' } elseif (-not $networkTask) { '未安装' } elseif ($networkTask.State -eq 'Disabled') { '已暂停' } else { '已启用' })
        Write-PanelRow '任务名称' (Get-ChannelTaskName $lane)
        Write-PanelRow '实际状态' (Get-ScheduledReporterSummary $lane)
        $record = Get-ScheduledReporterTaskRecord -Channel $lane
        if ($record.Task) {
            $state = Get-ScheduledReporterNotifyState -Task $record.Task
            Write-NotifyStatusRows -NotifyState $state
            $info = Get-ScheduledTaskInfo -TaskName $record.Name -ErrorAction SilentlyContinue
            if ($info) { Write-PanelRow '上次运行' (Format-TaskTime $info.LastRunTime); Write-PanelRow '上次结果' (Format-TaskResult $info.LastTaskResult) }
        }
        Write-PanelRow '运行日志' (Get-ChannelLogPath $lane)
        Show-SelfReportLogTail -Path (Get-ChannelLogPath $lane)
    }
}

function Set-ExistingReporterTaskState {
    param([string]$TaskName, [bool]$Disabled, [bool]$Network, [bool]$RunNetwork=$true)
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    if (($task.State -eq 'Disabled') -ne $Disabled) {
        if ($Disabled) { Disable-ScheduledTask -TaskName $TaskName -ErrorAction Stop | Out-Null }
        else { Enable-ScheduledTask -TaskName $TaskName -ErrorAction Stop | Out-Null }
    }
    if ($Network) {
        if ($Disabled) { Stop-ScheduledTask -TaskName $TaskName -ErrorAction Stop }
        elseif ($RunNetwork -and $task.State -ne 'Running') { Start-ScheduledTask -TaskName $TaskName -ErrorAction Stop }
    }
}

function Set-ScheduledReporterPaused {
    param([bool]$Paused, [ValidateSet('all','worker','official')][string]$Channel=$ScheduleChannel)
    if ((Get-LegacyReporterRecord).Task) { Sync-ScheduledReporterTasks -Mode refresh | Out-Null }
    $previousPaused = $script:SchedulePaused
    $previousWorker = $script:WorkerAutoEnabled
    $previousOfficial = $script:OfficialAutoEnabled
    $configExisted = Test-Path -LiteralPath $script:ConfigPath
    $previousJson = if ($configExisted) { [IO.File]::ReadAllText($script:ConfigPath) } else { $null }
    $saved = $false
    $changedTasks = [Collections.Generic.List[object]]::new()
    $operation = '保存自动上报开关'
    try {
        if ($Channel -eq 'all') { $script:SchedulePaused = $Paused }
        else {
            if ($script:SchedulePaused) { $script:WorkerAutoEnabled=$false; $script:OfficialAutoEnabled=$false; $script:SchedulePaused=$false }
            if ($Channel -eq 'worker') { $script:WorkerAutoEnabled = -not $Paused } else { $script:OfficialAutoEnabled = -not $Paused }
        }
        # Watchers reload this file; persist quietly before enabling any task.
        Save-ClientConfig -Quiet
        $saved = $true
        foreach ($lane in @('worker','official')) {
            if ($Channel -ne 'all' -and $Channel -ne $lane) { continue }
            foreach ($network in @($false,$true)) {
                $name = if ($network) { Get-NetworkReporterTaskName $lane } else { Get-ChannelTaskName $lane }
                $operation = "更新任务「$name」的自动状态"
                try { $task = Get-ScheduledTask -TaskName $name -ErrorAction Stop }
                catch {
                    if ($_.FullyQualifiedErrorId -like 'CmdletizationQuery_NotFound_TaskName*') { continue }
                    throw
                }
                if (-not $task) { continue }
                $disabled = Test-ChannelPaused $lane
                if ($network) {
                    $networkEnabled = if ($lane -eq 'official') { $script:OfficialNetworkEnabled } else { $script:WorkerNetworkEnabled }
                    $disabled = (Test-ChannelAutoPaused $lane) -or -not $networkEnabled
                }
                if (-not (Test-ChannelConfigured $lane)) { $disabled = $true }
                $wasDisabled = $task.State -eq 'Disabled'
                $wasRunning = $task.State -eq 'Running'
                if ($wasDisabled -eq $disabled -and (-not $network -or $disabled -or $wasRunning)) { continue }
                $changedTasks.Add([pscustomobject]@{ Name=$name; Disabled=$wasDisabled; Network=$network; Running=$wasRunning })
                Set-ExistingReporterTaskState -TaskName $name -Disabled $disabled -Network $network
            }
        }
    } catch {
        $failure = $_
        $script:SchedulePaused = $previousPaused
        $script:WorkerAutoEnabled = $previousWorker
        $script:OfficialAutoEnabled = $previousOfficial
        $restoreFailed = $false
        if ($saved) {
            try {
                if ($configExisted) { Write-Po0ClientConfigAtomic -Path $script:ConfigPath -Json $previousJson }
                else { Remove-Item -LiteralPath $script:ConfigPath -Force -ErrorAction Stop }
            } catch { $restoreFailed = $true }
        }
        for ($index = $changedTasks.Count - 1; $index -ge 0; $index--) {
            $before = $changedTasks[$index]
            try {
                $current = Get-ScheduledTask -TaskName $before.Name -ErrorAction Stop
                if (($current.State -eq 'Disabled') -eq $before.Disabled -and (-not $before.Network -or (($current.State -eq 'Running') -eq $before.Running))) { continue }
                Set-ExistingReporterTaskState -TaskName $before.Name -Disabled $before.Disabled -Network $before.Network -RunNetwork $before.Running
            } catch { $restoreFailed = $true }
        }
        $reason = 'Windows 未能完成此操作。'
        if (($failure.Exception.HResult -band 0xffff) -eq 5 -or $failure.Exception.Message -match '拒绝访问|access.*denied') {
            $reason = '权限不足；请使用安装任务时的 Windows 账号和权限，并继续指定当前配置文件重试。'
        }
        $restore = if ($restoreFailed) { '部分原状态未能恢复，请查看所选通道的任务状态和配置。' } else { '已恢复原自动开关和任务启停状态。' }
        throw "${operation}失败：$reason $restore"
    }
    Write-SelfReportCompleted '所选通道自动状态已更新；手动上报仍可使用。'
}

function Toggle-ScheduledReporterPaused {
    param([string]$Channel='all')
    if ($Channel -eq 'all') { Set-ScheduledReporterPaused -Paused (-not $script:SchedulePaused) -Channel all }
    else { Set-ScheduledReporterPaused -Paused (-not (Test-ChannelAutoPaused $Channel)) -Channel $Channel }
}

function Remove-ScheduledReporter {
    param([ValidateSet('all','worker','official')][string]$Channel=$ScheduleChannel)
    Sync-ScheduledReporterTasks -Mode remove -Channel $Channel | Out-Null
    Write-SelfReportCompleted '已删除所选通道任务，保存配置保留。'
}

function Remove-SelfReportPathIfExists {
    param(
        [string]$Label,
        [string]$Path
    )
    if (-not $Path) { return $true }
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "${Label}不存在：$Path"
        return $true
    }
    try {
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        Write-Host "已删除${Label}：$Path"
        return $true
    } catch {
        Write-Host "删除${Label}失败：$Path；$($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Uninstall-SelfReportClient {
    param([switch]$RemoveData)

    $scriptPath = Get-DefaultScriptPath
    $launcherPath = Get-DefaultTaskLauncherPath
    $legacyScriptPath = Get-LegacyScriptPath
    $legacyLauncherPath = Get-LegacyTaskLauncherPath
    $logPath = Get-DefaultLogPath
    $legacyConfigPath = Get-LegacyConfigPath
    $legacyLogPath = Get-LegacyLogPath
    $ok = $true

    Write-Host "卸载会删除本脚本管理的计划任务、计划任务启动文件和本机安装脚本。"
    Write-Host "本机脚本：$scriptPath"
    Write-Host "计划任务启动文件：$launcherPath"
    Write-Host "旧本机脚本：$legacyScriptPath"
    Write-Host "旧计划任务启动文件：$legacyLauncherPath"
    Remove-ScheduledReporter -Channel all
    if (-not (Remove-SelfReportPathIfExists -Label "计划任务启动文件" -Path $launcherPath)) { $ok = $false }
    if (-not (Remove-SelfReportPathIfExists -Label "本机脚本" -Path $scriptPath)) { $ok = $false }
    if ($legacyLauncherPath -ne $launcherPath) {
        if (-not (Remove-SelfReportPathIfExists -Label "旧计划任务启动文件" -Path $legacyLauncherPath)) { $ok = $false }
    }
    if ($legacyScriptPath -ne $scriptPath) {
        if (-not (Remove-SelfReportPathIfExists -Label "旧本机脚本" -Path $legacyScriptPath)) { $ok = $false }
    }

    if ($RemoveData) {
        if ($script:ConfigPathExplicit) {
            Write-Host "已保留显式配置文件：$script:ConfigPath"
        } elseif (-not (Remove-SelfReportPathIfExists -Label "配置文件" -Path $script:ConfigPath)) { $ok = $false }
        if ($legacyConfigPath -ne $script:ConfigPath) {
            if (-not (Remove-SelfReportPathIfExists -Label "旧配置文件" -Path $legacyConfigPath)) { $ok = $false }
        }
        if ($script:LogPathExplicit) {
            Write-Host "已保留显式日志文件：$logPath"
        } elseif (-not (Remove-SelfReportPathIfExists -Label "日志文件" -Path $logPath)) { $ok = $false }
        if ($legacyLogPath -ne $logPath) {
            if (-not (Remove-SelfReportPathIfExists -Label "旧日志文件" -Path $legacyLogPath)) { $ok = $false }
        }
        if (-not (Remove-SelfReportPathIfExists -Label "官方防火墙状态" -Path (Get-Po0FirewallStatePath))) { $ok = $false }
        if (-not (Remove-SelfReportPathIfExists -Label "LAN Worker due 状态" -Path (Get-Po0WorkerDueStatePath))) { $ok = $false }
        if (-not (Remove-SelfReportPathIfExists -Label "IP 探测状态" -Path (Get-IpCheckStatePath))) { $ok = $false }
        if (-not (Remove-SelfReportPathIfExists -Label "旧 IP 探测状态" -Path (Get-LegacyIpCheckStatePath))) { $ok = $false }
    } else {
        Write-Host "已保留配置文件：$script:ConfigPath"
        Write-Host "已保留日志文件：$logPath"
    }

    if (-not $ok) {
        throw "卸载已执行，但有项目删除失败。"
    }
    Write-SelfReportCompleted "卸载已完成。"
}
