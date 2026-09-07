function Normalize-WorkerUrl {
    param([string]$Value)
    if (-not $Value) { return "" }
    $value = $Value.Trim()
    if (-not $value) { return "" }
    if ($value -notmatch "^[A-Za-z][A-Za-z0-9+.-]*://") {
        $value = "https://$value"
    }
    try {
        $builder = [System.UriBuilder]::new($value)
    } catch {
        throw "LAN Worker self-report 地址无效：$Value"
    }
    if (-not $builder.Path -or $builder.Path -eq "/") {
        $builder.Path = "report"
    }
    return $builder.Uri.AbsoluteUri
}

function Assert-WorkerUrl {
    if (-not $script:WorkerUrl) { throw "缺少 -WorkerUrl 或已保存配置；请先配置并保存上报参数。" }
    $script:WorkerUrl = Normalize-WorkerUrl $script:WorkerUrl
    $uri = [System.Uri]$script:WorkerUrl
    if ($uri.Scheme -eq "https") { return }
    if ($uri.Scheme -eq "http" -and $script:AllowHttp) { return }
    if ($uri.Scheme -eq "http") {
        throw "Self-report 默认只允许 HTTPS。若仅用于本地调试或旧环境，请显式加 -AllowHttp。"
    }
    throw "LAN Worker self-report 地址必须是 https:// 地址。"
}

function Assert-Minutes {
    $parsed = 0
    if (-not [int]::TryParse([string]$script:Minutes, [ref]$parsed) -or $parsed -lt 1 -or $parsed -gt $script:MaxMinutes) {
        throw "计划任务间隔必须在 1-$script:MaxMinutes 分钟之间。"
    }
    $script:Minutes = $parsed
}

function Convert-IntervalSecondsToMinutes {
    param([object]$Seconds)
    $parsed = 0
    if (-not [int]::TryParse([string]$Seconds, [ref]$parsed)) {
        throw "计划任务间隔秒数必须是整数。"
    }
    $maxSeconds = $script:MaxMinutes * 60
    if ($parsed -lt 60 -or $parsed -gt $maxSeconds -or ($parsed % 60) -ne 0) {
        throw "计划任务间隔秒数必须在 60-$maxSeconds 秒之间，且必须是 60 的倍数。"
    }
    return [int]($parsed / 60)
}

function Apply-IntervalSeconds {
    if ($script:IntervalSeconds -and [int]$script:IntervalSeconds -gt 0) {
        $script:Minutes = Convert-IntervalSecondsToMinutes $script:IntervalSeconds
    }
}

function Get-IntervalSeconds {
    Assert-Minutes
    return [int]($script:Minutes * 60)
}

function Test-ClientConfigComplete {
    if (-not $script:Po0FirewallWorkerOnly -and (Test-Po0FirewallConfigured)) { return $true }
    if ($script:Po0FirewallOfficialOnly) { return $false }
    try {
        if ($script:WorkerUrl) {
            Assert-WorkerUrl
        } elseif (-not (Test-Po0FirewallConfigured)) {
            throw "没有配置可执行的上报通道。"
        }
        Assert-Minutes
        return $true
    } catch {
        return $false
    }
}
