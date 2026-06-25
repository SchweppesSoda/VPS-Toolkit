function Get-ScheduledReporterSummary {
    try {
        $task = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
        if (-not $task) { return "未安装" }
        if ($task.State -eq "Disabled") { return "已安装，当前暂停" }
        return "已安装，状态 $($task.State)"
    } catch {
        return "无法读取"
    }
}

function Show-ClientConfig {
    Write-PanelSection "Self-report 客户端配置"
    Write-PanelRow "配置文件" $script:ConfigPath
    Write-PanelRow "保存状态" $(if (Test-Path -LiteralPath $script:ConfigPath) { "已保存" } else { "未保存" })
    Write-PanelRow "LAN Worker URL" $(if ($script:WorkerUrl) { $script:WorkerUrl } else { "未设置" })
    Write-PanelRow "Source ID" $script:SourceId
    Write-PanelRow "Identity" $script:Identity
    Write-PanelRow "Secret" (Get-MaskedSecret $script:Secret)
    Write-PanelRow "HTTP 上报" $(if ($script:AllowHttp) { "已显式允许" } else { "默认拒绝" })
    Write-PanelRow "上报间隔" ("每 {0} 秒（安装定时上报时使用）" -f (Get-IntervalSeconds))
    Write-PanelRow "Windows 通知" (Format-NotifyStatus)
    Write-PanelRow "定时暂停" $(if ($script:SchedulePaused) { "已暂停" } else { "未暂停" })
    Write-PanelRow "计划任务" (Get-ScheduledReporterSummary)
    Write-PanelRow "放行 TTL" "由 LAN Worker Self-report 目标控制，默认 43200 秒"
    if ($script:IpCheckUrls.Count -gt 0) {
        Write-PanelRow "IP 探测列表" ($script:IpCheckUrls -join ",")
    } else {
        Write-PanelRow "首选 IP 探测" $script:IpCheckUrl
    }
}

function Show-ClientDashboard {
    Write-Title "PO0 Self-report Client"
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
    Write-PanelRow "Source ID" $script:SourceId
    Write-PanelRow "Identity" $script:Identity
    Write-PanelRow "运行日志" (Get-DefaultLogPath)
    Write-PanelRow "Windows 通知" (Format-NotifyStatus)
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
    $script:SourceId = Read-Default "Source ID" $script:SourceId
    $script:Identity = Read-Default "Identity" $script:Identity
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
    Save-ClientConfig
}

function Install-ScheduledReporterInteractive {
    if (-not (Test-ClientConfigComplete)) {
        Set-ClientConfigInteractive
    } else {
        $seconds = Read-Default "定时上报每几秒执行一次（60-$($script:MaxMinutes * 60)；必须是 60 的倍数）" ([string](Get-IntervalSeconds))
        $script:Minutes = Convert-IntervalSecondsToMinutes $seconds
    }
    $script:TaskNotify = Read-YesNoDefault "自动上报完成/失败后弹出 Windows 通知" $false
    Install-ScheduledReporter
}

function Show-ScheduledReporter {
    Write-PanelSection "Self-report 定时上报"
    Write-PanelRow "配置文件" $script:ConfigPath
    Write-PanelRow "暂停状态" $(if ($script:SchedulePaused) { "已暂停（手动立即上报仍可用）" } else { "未暂停" })
    try {
        $task = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
        if (-not $task) {
            Write-PanelRow "计划任务" "未安装本脚本管理的计划任务"
            return
        }
        Write-PanelRow "计划任务" $script:TaskName
        Write-PanelRow "任务状态" ([string]$task.State)
        foreach ($trigger in $task.Triggers) {
            Write-PanelRow "触发器" ([string]$trigger)
        }
        $info = Get-ScheduledTaskInfo -TaskName $script:TaskName -ErrorAction SilentlyContinue
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
        $task = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
        if ($task) {
            if ($Paused) {
                Disable-ScheduledTask -TaskName $script:TaskName | Out-Null
            } else {
                Enable-ScheduledTask -TaskName $script:TaskName | Out-Null
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

function Remove-ScheduledReporter {
    try {
        $task = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
        if (-not $task) {
            Write-PanelRow "计划任务" "未安装本脚本管理的计划任务"
            Write-SelfReportCompleted "当前没有本脚本管理的计划任务。"
            return
        }
        Unregister-ScheduledTask -TaskName $script:TaskName -Confirm:$false
        Write-Host "已删除计划任务：$script:TaskName"
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
    $logPath = Get-DefaultLogPath
    $ok = $true

    Write-Host "卸载会删除本脚本管理的计划任务、隐藏启动器和本机安装脚本。"
    Write-Host "本机脚本：$scriptPath"
    Write-Host "隐藏启动器：$launcherPath"
    Remove-ScheduledReporter
    if (-not (Remove-SelfReportPathIfExists -Label "隐藏启动器" -Path $launcherPath)) { $ok = $false }
    if (-not (Remove-SelfReportPathIfExists -Label "本机脚本" -Path $scriptPath)) { $ok = $false }

    if ($RemoveData) {
        if (-not (Remove-SelfReportPathIfExists -Label "配置文件" -Path $script:ConfigPath)) { $ok = $false }
        if (-not (Remove-SelfReportPathIfExists -Label "日志文件" -Path $logPath)) { $ok = $false }
    } else {
        Write-Host "已保留配置文件：$script:ConfigPath"
        Write-Host "已保留日志文件：$logPath"
    }

    if (-not $ok) {
        throw "卸载已执行，但有项目删除失败。"
    }
    Write-SelfReportCompleted "卸载已完成。"
}
