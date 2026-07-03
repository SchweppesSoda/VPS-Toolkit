function Get-ScheduledReporterSummary {
    try {
        $record = Get-ScheduledReporterTaskRecord
        $task = $record.Task
        if (-not $task) { return "未安装" }
        $prefix = $(if ($record.IsLegacy) { "旧计划任务，" } else { "" })
        if ($task.State -eq "Disabled") { return "${prefix}已安装，当前暂停" }
        return "${prefix}已安装，状态 $($task.State)"
    } catch {
        return "无法读取"
    }
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
    Write-PanelSection "PO0 Outbound IP Report 客户端配置"
    Write-PanelRow "配置文件" $script:ConfigPath
    Write-PanelRow "保存状态" $(if (Test-Path -LiteralPath $script:ConfigPath) { "已保存" } else { "未保存" })
    Write-PanelRow "LAN Worker URL" $(if ($script:WorkerUrl) { $script:WorkerUrl } else { "未设置" })
    Write-PanelRow "来源 ID" $script:SourceId
    Write-PanelRow "设备备注" $script:Identity
    Write-PanelRow "上报密钥" (Get-MaskedSecret $script:Secret)
    Write-PanelRow "HTTP 上报" $(if ($script:AllowHttp) { "已显式允许" } else { "默认拒绝" })
    Write-PanelRow "上报间隔" ("每 {0} 秒（安装定时上报时使用）" -f (Get-IntervalSeconds))
    Write-PanelRow "跳过 Wi-Fi SSID" (Format-WifiSsidPolicyList -Ssids $script:SkipWifiSsids)
    Write-PanelRow "当前 Wi-Fi SSID" (Format-CurrentWifiSsidStatus)
    Write-NotifyStatusRows
    Write-PanelRow "定时暂停" $(if ($script:SchedulePaused) { "已暂停" } else { "未暂停" })
    Write-PanelRow "计划任务" (Get-ScheduledReporterSummary)
    Write-PanelRow "放行时长" "由 LAN Worker 接收端控制，默认 43200 秒"
    if ($script:IpCheckUrls.Count -gt 0) {
        Write-PanelRow "IP 探测列表" ($script:IpCheckUrls -join ",")
    } else {
        Write-PanelRow "首选 IP 探测" $script:IpCheckUrl
    }
}

function Show-ClientDashboard {
    Write-Title "PO0 Outbound IP Report Client"
    Write-PanelSection "脚本信息"
    Write-PanelRow "脚本名称" $ScriptName
    Write-PanelRow "版本" $ScriptVersion
    Write-PanelRow "构建标识" (Get-ScriptBuildLabel)
    Write-PanelRow "发布日期" $ScriptReleaseDate
    Write-PanelRow "当前脚本" $(if ($PSCommandPath) { $PSCommandPath } else { "未知" })
    Write-PanelRow "默认安装路径" (Get-DefaultScriptPath)
    Write-PanelRow "下载 URL" $DownloadUrl

    Write-PanelSection "当前状态"
    Write-PanelRow "配置文件" $script:ConfigPath
    Write-PanelRow "保存状态" $(if (Test-Path -LiteralPath $script:ConfigPath) { "已保存" } else { "未保存" })
    Write-PanelRow "LAN Worker URL" $(if ($script:WorkerUrl) { $script:WorkerUrl } else { "未设置" })
    Write-PanelRow "来源 ID" $script:SourceId
    Write-PanelRow "设备备注" $script:Identity
    Write-PanelRow "运行日志" (Get-DefaultLogPath)
    Write-PanelRow "跳过 Wi-Fi SSID" (Format-WifiSsidPolicyList -Ssids $script:SkipWifiSsids)
    Write-PanelRow "当前 Wi-Fi SSID" (Format-CurrentWifiSsidStatus)
    Write-NotifyStatusRows
    Write-PanelRow "计划任务" (Get-ScheduledReporterSummary)
    Write-PanelRow "上报间隔" ("每 {0} 秒（安装计划任务时使用）" -f (Get-IntervalSeconds))
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
    $script:SourceId = Read-Default "来源 ID" $script:SourceId
    $script:Identity = Read-Default "设备备注" $script:Identity
    Read-SecretSetting
    $seconds = Read-Default "客户端每几秒上报一次（60-$($script:MaxMinutes * 60)；必须是 60 的倍数）" ([string](Get-IntervalSeconds))
    $script:Minutes = Convert-IntervalSecondsToMinutes $seconds
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

function Install-ScheduledReporterInteractive {
    if (-not (Test-ClientConfigComplete)) {
        Set-ClientConfigInteractive
    } else {
        $seconds = Read-Default "定时上报每几秒执行一次（60-$($script:MaxMinutes * 60)；必须是 60 的倍数）" ([string](Get-IntervalSeconds))
        $script:Minutes = Convert-IntervalSecondsToMinutes $seconds
    }
    $script:TaskNotify = Read-YesNoDefault "自动上报完成/失败后弹出 Windows 通知" $script:TaskNotify
    Install-ScheduledReporter
}

function Show-ScheduledReporter {
    Write-PanelSection "PO0 Outbound IP Report 定时上报"
    Write-PanelRow "配置文件" $script:ConfigPath
    Write-PanelRow "暂停状态" $(if ($script:SchedulePaused) { "已暂停（手动立即上报仍可用）" } else { "未暂停" })
    Write-PanelRow "跳过 Wi-Fi SSID" (Format-WifiSsidPolicyList -Ssids $script:SkipWifiSsids)
    Write-PanelRow "当前 Wi-Fi SSID" (Format-CurrentWifiSsidStatus)
    try {
        $record = Get-ScheduledReporterTaskRecord
        $task = $record.Task
        if (-not $task) {
            Write-PanelRow "计划任务" "未安装本脚本管理的计划任务"
            Write-NotifyStatusRows -NotifyState (Get-ScheduledReporterNotifyState -Task $null)
            return
        }
        $notifyState = Get-ScheduledReporterNotifyState -Task $task
        Write-PanelRow "计划任务" $(if ($record.IsLegacy) { "$($record.Name)（旧名，运行安装 / 更新可迁移）" } else { $script:TaskName })
        Write-PanelRow "任务状态" ([string]$task.State)
        Write-NotifyStatusRows -NotifyState $notifyState
        if ($notifyState.LauncherPath) {
            Write-PanelRow "计划任务启动文件" $notifyState.LauncherPath
        }
        if ($notifyState.ScriptPath) {
            Write-PanelRow "计划任务脚本" $notifyState.ScriptPath
            if ($notifyState.ScriptPathIsLegacy) {
                Write-PanelRow "脚本路径状态" "旧 po0-self-report.ps1 路径；运行 -InstallTask 或 -UpgradeSelf 迁移"
            } elseif (-not $notifyState.ScriptPathExists) {
                Write-PanelRow "脚本路径状态" "目标不存在；请重新运行 -InstallTask"
            } else {
                Write-PanelRow "脚本路径状态" "已指向标准安装脚本"
            }
        } else {
            Write-PanelRow "计划任务脚本" "无法从任务动作或计划任务启动文件读取"
        }
        foreach ($trigger in $task.Triggers) {
            Write-PanelRow "触发器" ([string]$trigger)
        }
        $info = Get-ScheduledTaskInfo -TaskName $record.Name -ErrorAction SilentlyContinue
        if ($info) {
            Write-PanelRow "上次运行" (Format-TaskTime $info.LastRunTime)
            Write-PanelRow "上次结果" (Format-TaskResult $info.LastTaskResult)
            Write-PanelRow "下次运行" (Format-TaskTime $info.NextRunTime)
        }
        Show-SelfReportLogTail -Path (Get-ScheduledReporterLogPath -Task $task)
    } catch {
        Write-PanelRow "状态读取" "失败：$($_.Exception.Message)"
    }
}

function Set-ScheduledReporterPaused {
    param([bool]$Paused)
    $script:SchedulePaused = $Paused
    Save-ClientConfig
    try {
        $record = Get-ScheduledReporterTaskRecord
        $task = $record.Task
        if ($task) {
            if ($Paused) {
                Disable-ScheduledTask -TaskName $record.Name | Out-Null
            } else {
                Enable-ScheduledTask -TaskName $record.Name | Out-Null
            }
        }
    } catch {
        throw "更新计划任务启停状态失败：$($_.Exception.Message)"
    }
    if ($Paused) {
        Write-SelfReportCompleted "定时上报已暂停；手动立即上报仍可用。"
    } else {
        Write-SelfReportCompleted "定时上报已恢复。"
    }
}

function Toggle-ScheduledReporterPaused {
    Set-ScheduledReporterPaused -Paused (-not $script:SchedulePaused)
}

function Set-ScheduledReporterNotify {
    param([bool]$Enabled)
    $script:TaskNotify = $Enabled
    Save-ClientConfig
    try {
        $updated = Update-ScheduledReporterLauncherForExistingTask
    } catch {
        throw "重写计划任务启动文件失败：$($_.Exception.Message)"
    }
    if ($updated -and $updated -ne "none") {
        Write-SelfReportCompleted "Windows 通知模式已更新为：$(Format-NotifyStatus)；计划任务启动文件已同步。"
    } else {
        Write-SelfReportCompleted "Windows 通知模式已更新为：$(Format-NotifyStatus)；当前未安装计划任务。"
    }
}

function Toggle-ScheduledReporterNotify {
    Set-ScheduledReporterNotify -Enabled (-not $script:TaskNotify)
}

function Remove-ScheduledReporter {
    try {
        $record = Get-ScheduledReporterTaskRecord
        $task = $record.Task
        if (-not $task) {
            Write-PanelRow "计划任务" "未安装本脚本管理的计划任务"
            Write-SelfReportCompleted "当前没有本脚本管理的计划任务。"
            return
        }
        Unregister-ScheduledTask -TaskName $record.Name -Confirm:$false
        Write-Host "已删除计划任务：$($record.Name)"
        if (-not $record.IsLegacy) {
            if (-not (Remove-LegacyScheduledReporterTask)) {
                throw "旧计划任务删除失败，已尝试禁用旧任务；请检查计划任务：$script:LegacyTaskName"
            }
        }
        Write-SelfReportCompleted "已删除本脚本管理的计划任务。"
    } catch {
        throw "删除计划任务失败：$($_.Exception.Message)"
    }
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
    Remove-ScheduledReporter
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
