

function Invoke-SelfReportCore {
    param([switch]$PromptForForceOnSkip)

    if ($script:Po0FirewallStatusOnly) {
        if ($script:Po0FirewallOfficialOnly -or $script:Po0FirewallWorkerOnly) {
            throw "-OfficialStatus 不能与 -OfficialOnly / -WorkerOnly 同时使用。"
        }
        $statusResult = Invoke-Po0FirewallReport -Mode "status"
        if ($statusResult.Message) { Write-Host $statusResult.Message }
        if (-not $statusResult.Succeeded) {
            throw $statusResult.Message
        }
        return
    }

    if ($script:Po0FirewallOfficialOnly -and $script:Po0FirewallWorkerOnly) {
        throw "-OfficialOnly 与 -WorkerOnly 不能同时使用。"
    }

    if ($script:Po0FirewallWorkerOnly) { Write-Host '自建上报已退役。'; return }
    $forceThisRun = [bool]$script:Po0FirewallForce
    if (-not $forceThisRun) {
        $wifiState = Get-WifiSsidPolicyState
        if ($wifiState.Enabled -and -not $wifiState.ReadSucceeded) {
            Write-SelfReportLogLine "WARN" "Wi-Fi SSID 读取失败，按 fail-open 继续上报：$($wifiState.Error)"
        } elseif ($wifiState.Matched) {
            if ($PromptForForceOnSkip) {
                Write-Host ("当前 Wi-Fi SSID ""{0}"" 命中跳过上报规则。" -f $wifiState.MatchedSsid)
                if (Read-YesNoDefault "是否强制上报一次" $false) {
                    $forceThisRun = $true
                    Write-SelfReportLogLine "INFO" "手动菜单已确认强制上报，忽略 Wi-Fi SSID 跳过规则：$($wifiState.MatchedSsid)"
                } else {
                    Write-SelfReportSkippedForWifiSsid -State $wifiState
                    return
                }
            } else {
                Write-SelfReportSkippedForWifiSsid -State $wifiState
                return
            }
        }
    }

    $officialActive = (-not $script:Po0FirewallWorkerOnly) -and (Test-Po0FirewallConfigured)
    if ($script:Po0FirewallScheduledRun) {
        if ($script:SchedulePaused) { return }
        $officialActive = $officialActive -and $script:OfficialAutoEnabled
        if ($NetworkChanged) {
            $officialActive = $officialActive -and $script:OfficialNetworkEnabled
        } else {
            $officialActive = $officialActive -and $script:OfficialTimerEnabled
        }
        if (-not $officialActive) {
            Write-SelfReportCompleted "自动上报通道均已停用，本轮跳过。"
            return
        }
    }
    if (-not $officialActive) {
        throw "没有配置可执行的上报通道。"
    }
    if ($officialActive -and $script:Po0FirewallOfficialOnly -and -not (Test-Po0FirewallConfigured)) {
        throw "PO0 官方防火墙未启用（默认关闭）。"
    }

    $successCount = 0
    $failureCount = 0
    $skippedCount = 0
    $officialResult = $null

    if ($officialActive) {
        $officialDue = (-not $script:Po0FirewallScheduledRun) -or $forceThisRun -or (Test-Po0FirewallDue)
        if ($officialDue) {
            $officialResult = Invoke-Po0FirewallReport -Mode "report"
            if ($officialResult.Succeeded) {
                $successCount++
            } else {
                $failureCount++
            }
        } else {
            $skippedCount++
        }
    }

    $messages = New-Object System.Collections.Generic.List[string]
    if ($officialResult -and $officialResult.Message) {
        $messages.Add([string]$officialResult.Message)
    }

    if ($failureCount -gt 0) {
        if ($successCount -gt 0) {
            $summary = "官方账号检查部分完成；成功 $successCount 路，失败 $failureCount 路。"
        } else {
            $summary = "官方防火墙操作未完成。"
        }
        if ($messages.Count -gt 0) {
            $summary = "$summary $($messages -join "；")"
        }
        throw $summary
    }
    if ($successCount -eq 0 -and $skippedCount -gt 0) {
        Write-SelfReportCompleted "本次定时唤醒未到上报间隔，未发起请求。"
        return
    }

    $completed = "官方防火墙检查完成。"
    if ($messages.Count -gt 0) {
        $completed = "$completed $($messages -join "；")"
    }
    Write-SelfReportCompleted $completed


    if ($officialResult -and $officialResult.NeedsNotify) {
        Show-WindowsSelfReportNotification -Title "PO0 官方防火墙状态已更新" -Message "官方防火墙白名单状态已更新。" -Kind "Info"
    }
}

function Invoke-SelfReport {
    param([switch]$PromptForForceOnSkip)

    $runMutex = $null
    try {
        $runMutex = Enter-Po0SelfReportMutex
        Invoke-SelfReportCore -PromptForForceOnSkip:$PromptForForceOnSkip
    } finally {
        Exit-Po0SelfReportMutex -Mutex $runMutex
    }
}
