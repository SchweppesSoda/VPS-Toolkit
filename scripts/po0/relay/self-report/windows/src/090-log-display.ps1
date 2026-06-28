function Get-ScheduledReporterLogPath {
    param($Task)
    if ($script:LogPath) { return $script:LogPath }
    if (-not $Task) { return "" }
    foreach ($action in $Task.Actions) {
        $args = [string]$action.Arguments
        if ($args -match '(?i)-LogPath\s+"([^"]+)"') { return $matches[1] }
        if ($args -match '(?i)-LogPath\s+(\S+)') { return $matches[1].Trim('"') }
        $launcher = ""
        if ($args -match '(?i)"([^"]+\.vbs)"') {
            $launcher = $matches[1]
        } elseif ($args -match '(?i)(\S+\.vbs)') {
            $launcher = $matches[1].Trim('"')
        }
        if ($launcher -and (Test-Path -LiteralPath $launcher)) {
            $launcherRaw = Get-Content -LiteralPath $launcher -Raw
            if ($launcherRaw -match '(?i)-LogPath\s+""([^""]+)""') { return $matches[1] }
            if ($launcherRaw -match '(?i)-LogPath\s+(\S+)') { return $matches[1].Trim('"') }
        }
    }
    return ""
}

function Get-SelfReportLogDisplayKind {
    param([string]$Level)
    $normalized = ""
    if ($Level) { $normalized = $Level.Trim().ToUpperInvariant() }
    switch ($normalized) {
        "OK" { return "完成" }
        "ERROR" { return "失败" }
        "WARN" { return "警告" }
        "INFO" { return "信息" }
        "RESPONSE" { return "返回" }
        default {
            if ($normalized) { return $normalized }
            return "日志"
        }
    }
}

function Limit-SelfReportLogDisplayText {
    param(
        [string]$Text,
        [int]$MaxLength = 160
    )
    $value = ""
    if ($null -ne $Text) { $value = $Text.Trim() }
    if ($value.Length -le $MaxLength) { return $value }
    if ($MaxLength -le 3) { return $value.Substring(0, $MaxLength) }
    return ($value.Substring(0, $MaxLength - 3) + "...")
}

function Convert-SelfReportLogLineForDisplay {
    param([string]$Line)
    if (-not $Line) { return $null }
    $raw = $Line.Trim()
    if (-not $raw) { return $null }

    if ($raw -match '^\[(?<stamp>[^\]]+)\]\s+\[(?<level>[^\]]+)\]\s*(?<message>.*)$') {
        $stamp = $matches["stamp"].Trim()
        $level = $matches["level"].Trim()
        $normalizedLevel = $level.ToUpperInvariant()
        if ($normalizedLevel -notin @("OK", "ERROR", "WARN", "RESPONSE")) {
            return $null
        }
        $message = $matches["message"].Trim()
        $stampLabel = $stamp
        if ($stamp -match '^\d{4}-(\d{2}-\d{2})\s+(\d{2}:\d{2})') {
            $stampLabel = "$($matches[1]) $($matches[2])"
        }
        $kind = Get-SelfReportLogDisplayKind -Level $level
        $targetCount = 0
        $responseIp = ""
        $targetNames = @()
        $message = $message -replace '^Self-report 已完成：', ''
        $message = $message -replace '^Self-report 未完成：', ''
        if ($message -match '^上报当前公网出口 IPv4\s+([0-9.]+)\s+到 LAN Worker：') {
            $message = "上报公网出口 IPv4 $($matches[1]) 到 LAN Worker"
        } elseif ($kind -eq "返回") {
            $responseSummary = Get-SelfReportResponseSummary -Content $message
            if ($responseSummary) {
                $targetCount = [int]$responseSummary.TargetCount
                $responseIp = [string]$responseSummary.Ip
                $targetNames = @($responseSummary.TargetNames | Where-Object { $_ })
                $targetSummary = Format-SelfReportTargetSuccessSummary -ResponseSummary $responseSummary
                if ($targetSummary) {
                    $message = "$targetSummary（公网出口 IPv4 $responseIp）"
                }
            }
        }
        return [pscustomobject]@{
            Stamp = $stampLabel
            Kind = $kind
            Message = (Limit-SelfReportLogDisplayText -Text $message)
            Level = $normalizedLevel
            TargetCount = $targetCount
            ResponseIp = $responseIp
            TargetNames = $targetNames
        }
    }

    return [pscustomobject]@{
        Stamp = ""
        Kind = "日志"
        Message = (Limit-SelfReportLogDisplayText -Text $raw)
        Level = ""
        TargetCount = 0
        ResponseIp = ""
        TargetNames = @()
    }
}

function Merge-SelfReportResponseSummaries {
    param($Entries)
    $displayEntries = New-Object System.Collections.Generic.List[object]
    $pendingResponse = $null
    foreach ($entry in $Entries) {
        if ($entry.Level -eq "RESPONSE" -and $entry.TargetCount -gt 0) {
            if ($pendingResponse) {
                [void]$displayEntries.Add($pendingResponse)
            }
            $pendingResponse = $entry
            continue
        }
        if ($entry.Level -eq "OK" -and $pendingResponse) {
            if ($entry.Message -notmatch 'PO0 目标：') {
                $message = $entry.Message -replace '。$', ''
                $targetSummary = Format-SelfReportTargetSuccessSummary -ResponseSummary $pendingResponse
                if ($targetSummary) {
                    $entry.Message = "$message；$targetSummary。"
                }
            }
            $pendingResponse = $null
        } elseif ($pendingResponse) {
            [void]$displayEntries.Add($pendingResponse)
            $pendingResponse = $null
        }
        [void]$displayEntries.Add($entry)
    }
    if ($pendingResponse) {
        [void]$displayEntries.Add($pendingResponse)
    }
    return $displayEntries.ToArray()
}

function Show-SelfReportLogTail {
    param(
        [string]$Path,
        [int]$Lines = 12
    )
    if (-not $Path) {
        Write-PanelRow "运行日志" "旧计划任务未配置日志；重新安装 / 更新定时上报后启用"
        return
    }
    Write-PanelRow "运行日志" $Path
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-PanelRow "最近日志" "暂无；等待计划任务运行一次，或先手动立即上报一次"
        return
    }
    Write-PanelRow "最近结果" "摘要；原始日志仍保留完整记录"
    $entries = @(Get-Content -LiteralPath $Path -Tail $Lines -ErrorAction SilentlyContinue | ForEach-Object {
        Convert-SelfReportLogLineForDisplay -Line $_
    } | Where-Object { $_ })
    if ($entries.Count -eq 0) {
        Write-PanelNote "(日志文件为空)"
        return
    }
    $entries = @(Merge-SelfReportResponseSummaries -Entries $entries)
    $previousStamp = ""
    foreach ($entry in $entries) {
        if ($entry.Stamp) {
            $stamp = $entry.Stamp
            if ($stamp -eq $previousStamp) {
                $stamp = "           "
            } else {
                $previousStamp = $entry.Stamp
            }
            Write-PanelNote ("{0}  {1}  {2}" -f $stamp, $entry.Kind, $entry.Message)
        } else {
            Write-PanelNote ("{0}  {1}" -f $entry.Kind, $entry.Message)
        }
    }
}
