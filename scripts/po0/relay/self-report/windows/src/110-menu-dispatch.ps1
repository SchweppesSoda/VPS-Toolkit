function Pause-Menu {
    Read-Host "按回车返回菜单" | Out-Null
}

function Invoke-InteractiveMenu {
    while ($true) {
        Show-ClientDashboard
        Write-MenuSection "手动上报"
        Write-MenuPair "1" "配置并保存上报参数" "2" "立即上报一次"
        Write-MenuSection "定时上报"
        Write-MenuPair "3" "安装 / 更新定时上报" "4" "暂停 / 恢复定时上报"
        Write-MenuPair "5" "查看定时上报状态" "6" "删除定时上报"
        Write-MenuSection "查看"
        Write-MenuItem "7" "显示当前配置"
        Write-MenuSection "维护"
        Write-MenuPair "8" "从 GitHub 更新脚本" "9" "卸载本客户端"
        Write-MenuSection "退出"
        Write-MenuItem "0" "退出"
        Write-MenuDivider
        $rawChoice = Read-Host "请选择操作 [0-9]"
        if ($null -eq $rawChoice) { return }
        $choice = $rawChoice.Trim()
        try {
            switch ($choice) {
                "1" { Set-ClientConfigInteractive; Pause-Menu }
                "2" {
                    if (-not (Test-ClientConfigComplete)) { Set-ClientConfigInteractive }
                    Invoke-SelfReport
                    Pause-Menu
                }
                "3" {
                    Install-ScheduledReporterInteractive
                    Pause-Menu
                }
                "4" { Toggle-ScheduledReporterPaused; Pause-Menu }
                "5" { Show-ScheduledReporter; Pause-Menu }
                "6" {
                    $confirm = Read-Host "确认删除 self-report 定时上报 [y/N]"
                    if ($null -eq $confirm) { $confirm = "" }
                    if ($confirm -match "^(y|yes)$") {
                        Remove-ScheduledReporter
                    } else {
                        Write-Host "已取消。"
                    }
                    Pause-Menu
                }
                "7" { Show-ClientConfig; Pause-Menu }
                "8" { Upgrade-SelfFromDownload -ReopenMenu }
                "9" {
                    $uninstalled = $false
                    Write-Host "卸载会删除计划任务、隐藏启动器和本机安装脚本；配置与日志默认保留。"
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
                default { Write-Host "无效选择。"; Pause-Menu }
            }
        } catch {
            Write-SelfReportIncomplete $_.Exception.Message
            Pause-Menu
        }
    }
}
