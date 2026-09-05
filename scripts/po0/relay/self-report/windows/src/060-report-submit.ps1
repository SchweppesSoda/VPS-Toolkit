function Get-SelfReportResponseSummary {
    param([string]$Content)
    if ($null -eq $Content) { return $null }
    foreach ($line in (([string]$Content -replace "`r", "") -split "`n")) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^OK\s+([0-9]{1,3}(?:\.[0-9]{1,3}){3});\s*targets=([0-9]+)\b') {
            $responseIp = $matches[1]
            $targetCount = [int]$matches[2]
            $targetNames = @()
            if ($trimmed -match ';\s*target_names=([^;]+)') {
                $targetNames = @($matches[1] -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            }
            return [pscustomobject]@{
                Ip = $responseIp
                TargetCount = $targetCount
                TargetNames = $targetNames
            }
        }
    }
    return $null
}

function Format-SelfReportTargetSuccessSummary {
    param($ResponseSummary)
    if (-not $ResponseSummary) { return "" }
    $count = [int]$ResponseSummary.TargetCount
    if ($count -le 0) { return "" }
    $targetNames = @($ResponseSummary.TargetNames | Where-Object { $_ })
    if ($targetNames.Count -gt 0) {
        return ("PO0 目标：{0}" -f ($targetNames -join "、"))
    }
    return ("PO0 目标：{0} 个" -f $count)
}

function Invoke-WorkerSelfReportCore {
    Assert-WorkerUrl
    $ip = Get-OutboundIPv4
    Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
    $builder = New-Object System.UriBuilder -ArgumentList $script:WorkerUrl
    $query = [System.Web.HttpUtility]::ParseQueryString($builder.Query)
    $query["source"] = $script:SourceId
    $query["ip"] = $ip
    $query["identity"] = $script:Identity
    $builder.Query = $query.ToString()
    $headers = @{}
    if ($script:Secret) { $headers["X-PO0-Token"] = $script:Secret }
    Write-SelfReportInfo "上报当前公网出口 IPv4 $ip 到 LAN Worker：$script:WorkerUrl"
    $resp = Invoke-WebRequest -UseBasicParsing -Uri $builder.Uri.AbsoluteUri -Headers $headers -TimeoutSec 30
    $content = $resp.Content
    $responseSummary = $null
    if ($content -is [byte[]]) {
        $content = [System.Text.Encoding]::UTF8.GetString($content)
    } elseif ($null -ne $content) {
        $content = [string]$content
    }
    if ($content) {
        $trimmedContent = $content.TrimEnd()
        Write-Host $trimmedContent
        Write-SelfReportLogLine "RESPONSE" $trimmedContent
        $responseSummary = Get-SelfReportResponseSummary -Content $trimmedContent
    }
    $message = "公网出口 IPv4 $ip 已被 LAN Worker 接收（HTTP $([int]$resp.StatusCode)）"
    $targetSummary = Format-SelfReportTargetSuccessSummary -ResponseSummary $responseSummary
    if ($targetSummary) {
        $message = "$message；$targetSummary"
    }
    $message = "$message。"
    return [pscustomobject]@{
        Succeeded = $true
        Ip = $ip
        Message = $message
    }
}

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
    $workerActive = (-not $script:Po0FirewallOfficialOnly) -and [bool]$script:WorkerUrl
    if (-not $officialActive -and -not $workerActive) {
        throw "没有配置可执行的上报通道。"
    }
    if ($officialActive -and $script:Po0FirewallOfficialOnly -and -not (Test-Po0FirewallConfigured)) {
        throw "PO0 官方防火墙未启用（默认关闭）。"
    }
    if ($workerActive) {
        Assert-WorkerUrl
    }
    Assert-Minutes

    $successCount = 0
    $failureCount = 0
    $skippedCount = 0
    $officialResult = $null
    $workerResult = $null

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

    if ($workerActive) {
        $workerDue = (-not $script:Po0FirewallScheduledRun) -or $forceThisRun -or (Test-Po0WorkerDue)
        if ($workerDue) {
            try {
                Mark-Po0WorkerAttempt
                $workerResult = Invoke-WorkerSelfReportCore
                if ($workerResult.Succeeded) {
                    $successCount++
                } else {
                    $failureCount++
                }
            } catch {
                $failureCount++
                $workerResult = [pscustomobject]@{
                    Succeeded = $false
                    Ip = ""
                    Message = "LAN Worker 通道失败。"
                }
                Write-SelfReportLogLine "ERROR" "LAN Worker 通道失败。"
            }
        } else {
            $skippedCount++
        }
    }

    $messages = New-Object System.Collections.Generic.List[string]
    if ($officialResult -and $officialResult.Message) {
        $messages.Add([string]$officialResult.Message)
    }
    if ($workerResult -and $workerResult.Message) {
        $messages.Add([string]$workerResult.Message)
    }

    if ($failureCount -gt 0) {
        if ($successCount -gt 0) {
            $summary = "官方防火墙与 LAN Worker 上报部分完成；成功 $successCount 路，失败 $failureCount 路。"
        } else {
            $summary = "官方防火墙与 LAN Worker 上报均未完成。"
        }
        if ($messages.Count -gt 0) {
            $summary = "$summary $($messages -join "；")"
        }
        throw $summary
    }
    if ($successCount -eq 0 -and $skippedCount -gt 0) {
        Write-SelfReportCompleted "本次定时唤醒没有到达通道 due，未发起请求。"
        return
    }

    if ($officialActive -and $workerActive) {
        $completed = "官方防火墙与 LAN Worker 上报均已完成。"
    } elseif ($officialActive) {
        $completed = "官方防火墙上报已完成。"
    } else {
        $completed = "LAN Worker 上报已完成。"
    }
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
