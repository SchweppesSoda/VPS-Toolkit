function Pause-Menu {
    Read-Host "按回车返回菜单" | Out-Null
}

function Invoke-InteractiveMenu {
    while ($true) {
        Show-ClientDashboard
        Write-MenuSection "自建 PO0 · LAN Worker"
        Write-MenuItem "1" "配置自建 PO0 参数"
        Write-MenuSection "PO0 官方防火墙"
        Write-MenuPair "2" "配置官方 Token / 槽位" "3" "查看官方状态（只读）"
        Write-MenuItem "4" "清除官方 Token"
        Write-MenuSection "通用设置与手动上报"
        Write-MenuPair "5" "配置探测 / Wi-Fi 跳过" "6" "立即上报已配置通道"
        Write-MenuSection "定时上报"
        Write-MenuPair "7" "安装 / 更新定时上报" "8" "暂停 / 恢复定时上报"
        Write-MenuPair "9" "查看定时上报状态" "10" "Windows 通知 / 静默模式"
        Write-MenuItem "11" "删除定时上报"
        Write-MenuSection "查看"
        Write-MenuItem "12" "显示当前配置"
        Write-MenuSection "维护"
        Write-MenuPair "13" "从 GitHub 更新脚本" "14" "卸载本客户端"
        Write-MenuSection "退出"
        Write-MenuItem "0" "退出"
        Write-MenuDivider
        $rawChoice = Read-Host "请选择操作 [0-14]"
        if ($null -eq $rawChoice) { return }
        $choice = $rawChoice.Trim()
        try {
            switch ($choice) {
                "1" { Set-ClientConfigInteractive; Pause-Menu }
                "2" { Set-OfficialConfigInteractive; Pause-Menu }
                "3" { Show-OfficialStatusInteractive; Pause-Menu }
                "4" { Clear-OfficialConfigInteractive; Pause-Menu }
                "5" { Set-CommonConfigInteractive; Pause-Menu }
                "6" {
                    if (-not (Test-ClientConfigComplete)) { Set-ClientConfigInteractive }
                    Invoke-SelfReport -PromptForForceOnSkip
                    Pause-Menu
                }
                "7" {
                    Install-ScheduledReporterInteractive
                    Pause-Menu
                }
                "8" { Toggle-ScheduledReporterPaused; Pause-Menu }
                "9" { Show-ScheduledReporter; Pause-Menu }
                "10" { Toggle-ScheduledReporterNotify; Pause-Menu }
                "11" {
                    $confirm = Read-Host "确认删除 self-report 定时上报 [y/N]"
                    if ($null -eq $confirm) { $confirm = "" }
                    if ($confirm -match "^(y|yes)$") {
                        Remove-ScheduledReporter
                    } else {
                        Write-Host "已取消。"
                    }
                    Pause-Menu
                }
                "12" { Show-ClientConfig; Pause-Menu }
                "13" { Upgrade-SelfFromDownload -ReopenMenu }
                "14" {
                    $uninstalled = $false
                    Write-Host "卸载会删除计划任务、计划任务启动文件和本机安装脚本；配置与日志默认保留。"
                    if (Read-YesNoDefault "确认卸载 self-report 客户端" $false) {
                        $removeData = Read-YesNoDefault "是否同时删除配置文件和日志" $false
                        Uninstall-SelfReportClient -RemoveData:$removeData
                        $uninstalled = $true
                    } else {
                        Write-Host "已取消。"
                    }
                    Pause-Menu
                    if ($uninstalled) { return }
                }
                "0" { return }
                "" {}
                default { Write-Host "无效选择：请输入 0-14。"; Pause-Menu }
            }
        } catch {
            Write-SelfReportIncomplete $_.Exception.Message
            Pause-Menu
        }
    }
}
