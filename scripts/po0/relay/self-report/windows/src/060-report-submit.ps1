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

function Invoke-SelfReport {
    param([switch]$PromptForForceOnSkip)
    Assert-WorkerUrl
    if (-not $script:ForceReport) {
        $wifiState = Get-WifiSsidPolicyState
        if ($wifiState.Enabled -and -not $wifiState.ReadSucceeded) {
            Write-SelfReportLogLine "WARN" "Wi-Fi SSID 读取失败，按 fail-open 继续上报：$($wifiState.Error)"
        } elseif ($wifiState.Matched) {
            if ($PromptForForceOnSkip) {
                Write-Host "当前 Wi-Fi SSID `"$($wifiState.MatchedSsid)`" 命中跳过上报规则。"
                if (Read-YesNoDefault "是否强制上报一次" $false) {
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
    Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
    $ip = Get-OutboundIPv4
    $builder = [System.UriBuilder]::new($script:WorkerUrl)
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
        Write-Output $trimmedContent
        Write-SelfReportLogLine "RESPONSE" $trimmedContent
        $responseSummary = Get-SelfReportResponseSummary -Content $trimmedContent
    }
    $message = "公网出口 IPv4 $ip 已被 LAN Worker 接收（HTTP $([int]$resp.StatusCode)）"
    $targetSummary = Format-SelfReportTargetSuccessSummary -ResponseSummary $responseSummary
    if ($targetSummary) {
        $message = "$message；$targetSummary"
    }
    $message = "$message。"
    Write-SelfReportCompleted $message
    Show-WindowsSelfReportNotification -Title "PO0 Outbound IP Report 已完成" -Message $message -Kind "Info"
}
