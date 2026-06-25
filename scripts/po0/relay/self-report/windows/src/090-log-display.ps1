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
        if ($normalizedLevel -notin @("OK", "ERROR", "WARN")) {
            return $null
        }
        $message = $matches["message"].Trim()
        $stampLabel = $stamp
        if ($stamp -match '^\d{4}-(\d{2}-\d{2})\s+(\d{2}:\d{2})') {
            $stampLabel = "$($matches[1]) $($matches[2])"
        }
        $kind = Get-SelfReportLogDisplayKind -Level $level
        $message = $message -replace '^Self-report 已完成：', ''
        $message = $message -replace '^Self-report 未完成：', ''
        if ($message -match '^上报当前公网出口 IPv4\s+([0-9.]+)\s+到 LAN Worker：') {
            $message = "上报公网出口 IPv4 $($matches[1]) 到 LAN Worker"
        } elseif ($kind -eq "返回" -and $message -match '^OK\s+([0-9.]+);\s*targets=([0-9]+)') {
            $message = "LAN Worker 返回 OK：$($matches[1])，targets=$($matches[2])"
        }
        return [pscustomobject]@{
            Stamp = $stampLabel
            Kind = $kind
            Message = (Limit-SelfReportLogDisplayText -Text $message)
        }
    }

    return [pscustomobject]@{
        Stamp = ""
        Kind = "日志"
        Message = (Limit-SelfReportLogDisplayText -Text $raw)
    }
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
