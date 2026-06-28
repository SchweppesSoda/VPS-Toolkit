function Get-SelfReportResponseSummary {
    param([string]$Content)
    if ($null -eq $Content) { return $null }
    foreach ($line in (([string]$Content -replace "`r", "") -split "`n")) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^OK\s+([0-9]{1,3}(?:\.[0-9]{1,3}){3});\s*targets=([0-9]+)\b') {
            return [pscustomobject]@{
                Ip = $matches[1]
                TargetCount = [int]$matches[2]
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
    return ("LAN Worker 已成功转发 {0} 个 PO0 目标" -f $count)
}

function Invoke-SelfReport {
    Assert-WorkerUrl
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
    Show-WindowsSelfReportNotification -Title "PO0 Self-report 已完成" -Message $message -Kind "Info"
}
