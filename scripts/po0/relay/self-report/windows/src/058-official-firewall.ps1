
# PO0 official firewall channel for the Windows self-report client.
#
# The channel is disabled unless PO0_FIREWALL_TOKENS is present in the
# permission-controlled JSON configuration or the environment. Tokens never
# appear in command-line arguments, logs, notifications, or status state.
#
# API behavior follows kelenetwork/po0fw: read status first, then add only
# when the current /24 is missing (or is in a different requested fixed slot).

$script:Po0FirewallApiBaseUrl = "https://124.221.69.228/api/firewall"
# Official interval is loaded from local channel settings.
$script:Po0FirewallTokensEnvironmentSet = [bool](Get-Item -LiteralPath "Env:PO0_FIREWALL_TOKENS" -ErrorAction SilentlyContinue)
if ($script:Po0FirewallTokensEnvironmentSet) {
    $script:Po0FirewallTokens = [string]$env:PO0_FIREWALL_TOKENS
} else {
    $script:Po0FirewallTokens = ""
}
$script:Po0FirewallScheduledRun = [bool]($ScheduledRun -or $NetworkChanged)
$script:Po0FirewallStatusOnly = [bool]$OfficialStatus
$script:Po0FirewallOfficialOnly = [bool]$OfficialOnly
$script:Po0FirewallWorkerOnly = [bool]$WorkerOnly
$script:Po0FirewallForce = [bool]$ForceReport
$script:Po0FirewallLastResult = $null

function Get-Po0FirewallTokenItems {
    param(
        [AllowEmptyString()]
        [string]$Value = $script:Po0FirewallTokens
    )
    if ($null -eq $Value) { $Value = "" }
    if (-not $Value.Trim()) { return @() }
    $parts = @($Value -split "[,;，；\s]+" | Where-Object { $_ })
    $items = New-Object System.Collections.Generic.List[object]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($part in $parts) {
        $item = ([string]$part).Trim()
        if (-not $item) {
            throw "PO0 官方防火墙 token 列表包含空项。"
        }

        $token = $item
        $slot = ""
        $at = $item.IndexOf("@")
        if ($at -ge 0) {
            if ($at -le 0 -or $item.IndexOf("@", $at + 1) -ge 0) {
                throw "PO0 官方防火墙 token 配置无效。"
            }
            $token = $item.Substring(0, $at)
            $slot = $item.Substring($at + 1)
            if ($slot -notmatch "^[0-4]$") {
                throw "PO0 官方防火墙 token 配置无效。"
            }
        }
        if ($token -notmatch "^pgnfw_[A-Za-z0-9._~-]{1,240}$") {
            throw "PO0 官方防火墙 token 配置无效。"
        }
        # A token identifies one official account; slot hints are not separate accounts.
        $key = $token
        if (-not $seen.Add($key)) {
            throw "PO0 官方防火墙 token 列表包含重复项。"
        }
        if ($items.Count -ge 16) {
            throw "PO0 官方防火墙 token 数量超过上限。"
        }
        $items.Add([pscustomobject]@{
            Token = $token
            Slot = $slot
            ConfiguredItem = $item
        })
    }
    return $items.ToArray()
}

function ConvertTo-Po0FirewallNormalizedTokens {
    param([object[]]$Items)
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Items)) {
        $value = [string]$item.Token
        if ($item.Slot) { $value = "{0}@{1}" -f $value, $item.Slot }
        $parts.Add($value)
    }
    return ($parts -join ",")
}

function Assert-Po0FirewallTokens {
    param([switch]$AllowEmpty)
    $items = @(Get-Po0FirewallTokenItems)
    if (-not $AllowEmpty -and $items.Count -eq 0) {
        throw "PO0 官方防火墙未启用（默认关闭）。"
    }
    return $items
}

function Test-Po0FirewallConfigured {
    try {
        if (-not $script:Po0FirewallTokens -or -not ([string]$script:Po0FirewallTokens).Trim()) {
            return $false
        }
        return (@(Get-Po0FirewallTokenItems).Count -gt 0)
    } catch {
        # Keep an invalid non-empty value visible as configured so report mode
        # can return a safe configuration error instead of silently disabling it.
        return ([bool]([string]$script:Po0FirewallTokens).Trim())
    }
}

function Get-Po0FirewallTokenSummary {
    try {
        $items = @(Get-Po0FirewallTokenItems)
    } catch {
        return "配置有误，请进入参数页检查"
    }
    if ($items.Count -eq 0) { return "未启用（默认关闭）" }
    return "已配置 $($items.Count) 个账号"
}

function Read-Po0FirewallTokensInteractive {
    Write-PanelRow "当前官方 Token" $(if ($script:Po0FirewallTokens) { $script:Po0FirewallTokens } else { "未设置" })
    Write-Host "可用逗号、分号、空格或换行分隔，槽位写 @0..4。空行结束；直接空行保留，单独 - 清空。"
    $tokenLines = New-Object System.Collections.Generic.List[string]
    while ($true) {
        $tokenLine = Read-Host -Prompt "输入官方 Token（空行结束）"
        if ($null -eq $tokenLine -or -not $tokenLine.Trim()) { break }
        $tokenLines.Add($tokenLine.Trim())
        if ($tokenLines.Count -eq 1 -and $tokenLines[0] -eq "-") { break }
    }
    if ($tokenLines.Count -eq 0) { return }
    $tokenInput = $tokenLines -join "`n"
    if ($tokenInput -eq "-") {
        $script:Po0FirewallTokens = ""
        return
    }
    $items = @(Get-Po0FirewallTokenItems -Value $tokenInput)
    $script:Po0FirewallTokens = ConvertTo-Po0FirewallNormalizedTokens -Items $items
}

function Get-Po0FirewallNow {
    $testValue = [string]$env:PO0_TEST_NOW
    $now = [int64]0
    if ($testValue -and [int64]::TryParse($testValue, [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$now) -and $now -ge 0) {
        return $now
    }
    $epoch = [DateTime]::SpecifyKind([DateTime]"1970-01-01T00:00:00", [DateTimeKind]::Utc)
    return [int64]([DateTime]::UtcNow - $epoch).TotalSeconds
}

function Get-Po0FirewallStatePath {
    return (Join-Path (Get-DefaultDataDir) "official-firewall-state.json")
}

function Get-Po0WorkerDueStatePath {
    return (Join-Path (Get-DefaultDataDir) "worker-last-attempt.txt")
}

function Get-Po0FirewallState {
    $path = Get-Po0FirewallStatePath
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        if (-not $raw.Trim()) { return $null }
        return ($raw | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Get-Po0TimestampFromValue {
    param($Value)
    $parsed = [int64]0
    if ($null -ne $Value -and [int64]::TryParse([string]$Value, [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsed) -and $parsed -ge 0) {
        return $parsed
    }
    return [int64]0
}

function Write-Po0TextAtomic {
    param(
        [string]$Path,
        [string]$Value
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $tmp = "{0}.{1}.{2}.tmp" -f $Path, $PID, ([guid]::NewGuid().ToString("N"))
    try {
        Set-Content -LiteralPath $tmp -Value $Value -Encoding ASCII
        Move-Item -LiteralPath $tmp -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $tmp) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
}

function Write-Po0FirewallState {
    param(
        [object[]]$Accounts,
        [Int64]$LastOfficialAttempt
    )
    $safeAccounts = @()
    foreach ($account in @($Accounts)) {
        if ($null -eq $account) { continue }
        $safeAccounts += [pscustomobject]@{
            Index = [int]$account.Index
            FixedSlot = [string]$account.FixedSlot
            CurrentIp = [string]$account.CurrentIp
            Limit = [int]$account.Limit
            Used = [int]$account.Used
            Whitelist = @($account.Whitelist)
            Status = [string]$account.Status
        }
    }
    $payload = [ordered]@{
        LastOfficialAttempt = [Int64]$LastOfficialAttempt
        Accounts = @($safeAccounts)
    }
    $json = $payload | ConvertTo-Json -Depth 6
    Write-Po0TextAtomic -Path (Get-Po0FirewallStatePath) -Value $json
}

function Mark-Po0FirewallAttempt {
    $state = Get-Po0FirewallState
    $accounts = @()
    if ($state) {
        $accounts = @($state.Accounts)
    }
    Write-Po0FirewallState -Accounts $accounts -LastOfficialAttempt (Get-Po0FirewallNow)
}

function Get-Po0FirewallLastAttempt {
    $state = Get-Po0FirewallState
    if (-not $state) { return [int64]0 }
    return (Get-Po0TimestampFromValue $state.LastOfficialAttempt)
}

function Test-Po0FirewallDue {
    if (-not (Test-Po0FirewallConfigured)) { return $false }
    if (-not $script:Po0FirewallScheduledRun -or $script:Po0FirewallForce -or $NetworkChanged -or $TimerTrigger) { return $true }
    $now = Get-Po0FirewallNow
    $last = Get-Po0FirewallLastAttempt
    if ($last -le 0) { return $true }
    if ($now -lt $last) { return $true }
    return (($now - $last) -ge [int64]$script:OfficialIntervalSeconds)
}

function Get-Po0WorkerLastAttempt {
    $path = Get-Po0WorkerDueStatePath
    if (-not (Test-Path -LiteralPath $path)) { return [int64]0 }
    try {
        return (Get-Po0TimestampFromValue (Get-Content -LiteralPath $path -Raw -Encoding ASCII))
    } catch {
        return [int64]0
    }
}

function Test-Po0WorkerDue {
    if (-not $script:WorkerUrl) { return $false }
    if (-not $script:Po0FirewallScheduledRun -or $script:Po0FirewallForce -or $NetworkChanged -or $TimerTrigger) { return $true }
    $now = Get-Po0FirewallNow
    $last = Get-Po0WorkerLastAttempt
    if ($last -le 0) { return $true }
    if ($now -lt $last) { return $true }
    return (($now - $last) -ge [int64](Get-IntervalSeconds))
}

function Mark-Po0WorkerAttempt {
    Write-Po0TextAtomic -Path (Get-Po0WorkerDueStatePath) -Value ([string](Get-Po0FirewallNow))
}

function Assert-Po0ReportConfig {
    $hasWorker = [bool]$script:WorkerUrl -and -not $script:Po0FirewallOfficialOnly
    $hasOfficial = (Test-Po0FirewallConfigured) -and -not $script:Po0FirewallWorkerOnly
    if (-not $hasWorker -and -not $hasOfficial) {
        throw "没有配置可执行的上报通道。"
    }
    if ($hasWorker) { Assert-WorkerUrl }
    Assert-Minutes
}

function Invoke-Po0OfficialHttpRequest {
    param(
        [ValidateSet("GET", "POST")]
        [string]$Method,
        [string]$Token,
        [string]$Slot = ""
    )
    $handler = $null
    $client = $null
    $request = $null
    $response = $null
    $stream = $null
    $memory = $null
    $oldProtocol = $null
    $protocolChanged = $false
    try {
        $requestItem = [string]$Token
        if ($Slot) { $requestItem = "{0}@{1}" -f $Token, $Slot }
        $items = @(Get-Po0FirewallTokenItems -Value $requestItem)
        if ($items.Count -ne 1) { throw "invalid" }
        $safeToken = $items[0].Token
        $url = "{0}/{1}" -f $script:Po0FirewallApiBaseUrl, $safeToken
        if ($Method -eq "POST") {
            $url = "$url/add"
            if ($Slot) { $url = "$url?slot=$Slot" }
        }

        Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
        $handler = New-Object System.Net.Http.HttpClientHandler
        $handler.UseProxy = $false
        $handler.Proxy = $null
        $handler.AllowAutoRedirect = $false
        $handler.UseCookies = $false
        $handler.CheckCertificateRevocationList = $true
        $client = New-Object -TypeName System.Net.Http.HttpClient -ArgumentList $handler
        $client.Timeout = [TimeSpan]::FromSeconds(20)
        $request = New-Object System.Net.Http.HttpRequestMessage
        if ($Method -eq "GET") {
            $request.Method = [System.Net.Http.HttpMethod]::Get
        } else {
            $request.Method = [System.Net.Http.HttpMethod]::Post
        }
        $request.RequestUri = [Uri]$url

        $oldProtocol = [Net.ServicePointManager]::SecurityProtocol
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $protocolChanged = $true
            $response = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
            $contentLength = $response.Content.Headers.ContentLength
            if ($null -ne $contentLength -and [int64]$contentLength -gt 65536) { throw "large" }
            $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
            $memory = New-Object System.IO.MemoryStream
            $buffer = New-Object byte[] 8192
            while ($true) {
                $read = $stream.Read($buffer, 0, $buffer.Length)
                if ($read -le 0) { break }
                if (($memory.Length + $read) -gt 65536) { throw "large" }
                $memory.Write($buffer, 0, $read)
            }
            $body = [Text.Encoding]::UTF8.GetString($memory.ToArray())
            $statusCode = [int]$response.StatusCode
            if ($statusCode -lt 200 -or $statusCode -ge 300) { throw "status" }
            return [pscustomobject]@{
                StatusCode = $statusCode
                Body = [string]$body
            }
        } finally {
            if ($stream) { $stream.Dispose() }
            if ($memory) { $memory.Dispose() }
            if ($protocolChanged) {
                [Net.ServicePointManager]::SecurityProtocol = $oldProtocol
            }
            if ($response) { $response.Dispose() }
        }
    } catch {
        throw "官方防火墙请求失败。"
    } finally {
        if ($request) { $request.Dispose() }
        if ($client) { $client.Dispose() }
        if ($handler) { $handler.Dispose() }
    }
}
function Test-Po0FirewallValidIp24 {
    param([string]$Value)
    if ($null -eq $Value -or $Value -notmatch "^([0-9]{1,3}\.){3}[0-9]{1,3}/24$") {
        return $false
    }
    $address = $Value.Substring(0, $Value.Length - 3)
    foreach ($octet in $address.Split(".")) {
        $number = 0
        if (-not [int]::TryParse($octet, [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
            return $false
        }
        if ($number -lt 0 -or $number -gt 255) { return $false }
    }
    return $true
}

function Get-Po0FirewallJsonObject {
    param([string]$Body)
    if ($null -eq $Body -or -not $Body.Trim()) { throw "empty" }
    try {
        $object = $Body | ConvertFrom-Json
    } catch {
        throw "invalid"
    }
    if ($null -eq $object -or $object -is [string]) { throw "invalid" }
    return $object
}

function ConvertTo-Po0InvariantText {
    param($Value)
    if ($null -eq $Value) { return "" }
    if ($Value -is [bool]) { return ([string]$Value) }
    try {
        return $Value.ToString([Globalization.CultureInfo]::InvariantCulture)
    } catch {
        return ([string]$Value)
    }
}

function Test-Po0FirewallJsonInteger {
    param($Value)
    if ($null -eq $Value -or $Value -is [bool]) { return $false }
    return ($Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or $Value -is [int64] -or $Value -is [uint64] -or $Value -is [decimal])
}
function ConvertFrom-Po0FirewallResponse {
    param([string]$Body)
    $object = Get-Po0FirewallJsonObject -Body $Body
    $enabledProperty = $object.PSObject.Properties["enabled"]
    if ($null -eq $enabledProperty -or -not ($enabledProperty.Value -is [bool]) -or -not [bool]$enabledProperty.Value) {
        throw "enabled"
    }
    $currentProperty = $object.PSObject.Properties["currentIp"]
    if ($null -eq $currentProperty -or -not (Test-Po0FirewallValidIp24 -Value ([string]$currentProperty.Value))) {
        throw "current"
    }
    $limitProperty = $object.PSObject.Properties["limit"]
    $limitValue = $null
    if ($limitProperty) { $limitValue = $limitProperty.Value }
    if (-not $limitProperty -or -not (Test-Po0FirewallJsonInteger -Value $limitValue)) {
        throw "limit"
    }
    $limit = [int]$limitValue
    if ($limit -lt 1 -or $limit -gt 5) { throw "limit" }

    $whitelistProperty = $object.PSObject.Properties["whitelist"]
    if ($null -eq $whitelistProperty -or $null -eq $whitelistProperty.Value) {
        throw "whitelist"
    }
    if ($whitelistProperty.Value -is [string]) { throw "whitelist" }
    $entries = @($whitelistProperty.Value)
    if ($entries.Count -gt 5 -or $entries.Count -gt $limit) { throw "whitelist" }
    $seenSlots = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $normalized = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $entries) {
        if ($null -eq $entry -or $entry -is [string]) { throw "whitelist" }
        $ipProperty = $entry.PSObject.Properties["ip"]
        if ($null -eq $ipProperty -or -not (Test-Po0FirewallValidIp24 -Value ([string]$ipProperty.Value))) {
            throw "whitelist"
        }
        $slot = ""
        $slotProperty = $entry.PSObject.Properties["slot"]
        if ($slotProperty -and $null -ne $slotProperty.Value) {
            if ($slotProperty.Value -is [string]) {
                $slotText = [string]$slotProperty.Value
                if ($slotText -ne "") { throw "slot" }
            } elseif (Test-Po0FirewallJsonInteger -Value $slotProperty.Value) {
                $slotNumber = [int]$slotProperty.Value
                if ($slotNumber -lt 0 -or $slotNumber -gt 4) { throw "slot" }
                $slotText = [string]$slotNumber
            } else {
                throw "slot"
            }
            $slot = $slotText
            if ($slot -and -not $seenSlots.Add($slot)) { throw "slot" }
        }
        $normalized.Add([pscustomobject]@{
            Ip = [string]$ipProperty.Value
            Slot = $slot
        })
    }
    return [pscustomobject]@{
        Object = $object
        Enabled = $true
        CurrentIp = [string]$currentProperty.Value
        Limit = $limit
        Entries = @($normalized.ToArray())
    }
}

function Test-Po0FirewallEntryMatches {
    param(
        $Response,
        [string]$Ip,
        [string]$FixedSlot = ""
    )
    foreach ($entry in @($Response.Entries)) {
        if ([string]$entry.Ip -ne $Ip) { continue }
        if (-not $FixedSlot -or [string]$entry.Slot -eq $FixedSlot) {
            return $true
        }
    }
    return $false
}

function Format-Po0FirewallSlotLabel {
    param([string]$Slot)
    $number = 0
    if ($Slot -and [int]::TryParse($Slot, [ref]$number) -and $number -ge 0 -and $number -le 4) {
        return [string]($number + 1)
    }
    return [string]$Slot
}
function New-Po0FirewallAccountState {
    param(
        [int]$Index,
        [string]$FixedSlot = "",
        [string]$CurrentIp = "",
        [int]$Limit = 0,
        [object[]]$Entries = @(),
        [string]$Status = "failed"
    )
    $safeEntries = @()
    foreach ($entry in @($Entries)) {
        $safeEntries += [pscustomobject]@{
            Ip = [string]$entry.Ip
            Slot = [string]$entry.Slot
        }
    }
    return [pscustomobject]@{
        Index = $Index
        FixedSlot = $FixedSlot
        CurrentIp = $CurrentIp
        Limit = $Limit
        Used = $safeEntries.Count
        Whitelist = @($safeEntries)
        Status = $Status
    }
}

function Invoke-Po0FirewallItem {
    param(
        $Item,
        [int]$Index,
        [ValidateSet("status", "report")]
        [string]$Mode = "report"
    )
    $accountState = New-Po0FirewallAccountState -Index $Index -FixedSlot ([string]$Item.Slot)
    $marker = Get-OfficialAccountName $Index
    if ($Item.Slot) { $marker = "$marker（槽位 $(Format-Po0FirewallSlotLabel -Slot ([string]$Item.Slot))）" }
    try {
        $statusResponse = Invoke-Po0OfficialHttpRequest -Method GET -Token ([string]$Item.Token)
        $status = ConvertFrom-Po0FirewallResponse -Body ([string]$statusResponse.Body)
        $accountState = New-Po0FirewallAccountState -Index $Index -FixedSlot ([string]$Item.Slot) -CurrentIp $status.CurrentIp -Limit $status.Limit -Entries $status.Entries -Status "ok"
        $hit = Test-Po0FirewallEntryMatches -Response $status -Ip $status.CurrentIp -FixedSlot ([string]$Item.Slot)
        if ($hit) {
            return [pscustomobject]@{
                Succeeded = $true
                Added = $false
                State = $accountState
                Message = "$marker 已在白名单：$($status.CurrentIp)（名额 $($status.Limit)，已用 $($status.Entries.Count)）。"
            }
        }
        if ($Mode -eq "status") {
            return [pscustomobject]@{
                Succeeded = $true
                Added = $false
                State = $accountState
                Message = "$marker 当前未命中白名单：$($status.CurrentIp)（名额 $($status.Limit)，仅读不加白）。"
            }
        }

        $postResponse = Invoke-Po0OfficialHttpRequest -Method POST -Token ([string]$Item.Token) -Slot ([string]$Item.Slot)
        $post = ConvertFrom-Po0FirewallResponse -Body ([string]$postResponse.Body)
        if (-not (Test-Po0FirewallEntryMatches -Response $post -Ip $post.CurrentIp -FixedSlot ([string]$Item.Slot))) {
            throw "confirmation"
        }
        $accountState = New-Po0FirewallAccountState -Index $Index -FixedSlot ([string]$Item.Slot) -CurrentIp $post.CurrentIp -Limit $post.Limit -Entries $post.Entries -Status "updated"
        return [pscustomobject]@{
            Succeeded = $true
            Added = $true
            State = $accountState
            Message = "$marker 已更新：$($post.CurrentIp)（名额 $($post.Limit)，已用 $($post.Entries.Count)）。"
        }
    } catch {
        return [pscustomobject]@{
            Succeeded = $false
            Added = $false
            State = $accountState
            Message = "$marker 只读检查或加白失败。"
        }
    }
}

function Invoke-Po0FirewallReport {
    param(
        [ValidateSet("status", "report")]
        [string]$Mode = "report"
    )
    $result = [ordered]@{
        Channel = "official"
        Configured = $false
        Succeeded = $true
        ExitCode = 0
        Status = "disabled"
        SuccessCount = 0
        FailureCount = 0
        NewEntryCount = 0
        NeedsNotify = $false
        Skipped = $false
        Message = "PO0 官方防火墙未启用（默认关闭）。"
        Accounts = @()
    }
    if (-not (Test-Po0FirewallConfigured)) {
        return [pscustomobject]$result
    }
    $result.Configured = $true
    try {
        $items = @(Assert-Po0FirewallTokens)
    } catch {
        $result.Succeeded = $false
        $result.ExitCode = 1
        $result.Status = "failed"
        $result.Message = "PO0 官方防火墙 token 配置无效。"
        return [pscustomobject]$result
    }
    if ($Mode -eq "report" -and $script:Po0FirewallScheduledRun -and -not $script:Po0FirewallForce -and -not (Test-Po0FirewallDue)) {
        $result.Status = "skipped"
        $result.Skipped = $true
        $result.Message = "PO0 官方防火墙本次未到期。"
        return [pscustomobject]$result
    }
    if ($Mode -eq "report") {
        try {
            Mark-Po0FirewallAttempt
        } catch {
            $result.Succeeded = $false
            $result.ExitCode = 1
            $result.Status = "failed"
            $result.Message = "PO0 官方防火墙独立状态保存失败。"
            return [pscustomobject]$result
        }
    }
    $states = New-Object System.Collections.Generic.List[object]
    $success = 0
    $failure = 0
    $added = 0
    $index = 0
    foreach ($item in $items) {
        $index++
        $itemResult = Invoke-Po0FirewallItem -Item $item -Index $index -Mode $Mode
        $states.Add($itemResult.State)
        if ($itemResult.Succeeded) {
            $success++
            if ($itemResult.Added) { $added++ }
        } else {
            $failure++
        }
        Write-Host $itemResult.Message
    }
    $result.SuccessCount = $success
    $result.FailureCount = $failure
    $result.NewEntryCount = $added
    $result.NeedsNotify = ($added -gt 0)
    $result.Accounts = @($states.ToArray())
    if ($Mode -eq "report") {
        try {
            Write-Po0FirewallState -Accounts $result.Accounts -LastOfficialAttempt (Get-Po0FirewallNow)
        } catch {
            $result.Succeeded = $false
            $result.ExitCode = 1
            $result.Status = "failed"
            $result.Message = "PO0 官方防火墙状态保存失败。"
            return [pscustomobject]$result
        }
    }
    if ($Mode -eq "status") {
        try {
            $lastAttempt = Get-Po0FirewallLastAttempt
            Write-Po0FirewallState -Accounts $result.Accounts -LastOfficialAttempt $lastAttempt
        } catch {
            $result.Succeeded = $false
            $result.ExitCode = 1
            $result.Status = "failed"
            $result.Message = "PO0 官方防火墙只读状态保存失败。"
            return [pscustomobject]$result
        }
    }
    if ($failure -gt 0) {
        $result.Succeeded = $false
        $result.ExitCode = 1
        $result.Status = if ($success -gt 0) { "partial" } else { "failed" }
        if ($success -gt 0) {
            $result.Message = "PO0 官方防火墙上报部分完成：成功 $success 条，失败 $failure 条。"
        } else {
            $result.Message = "PO0 官方防火墙上报失败：$failure 条请求未完成。"
        }
    } elseif ($Mode -eq "status") {
        $result.Status = "success"
        $result.Message = "PO0 官方防火墙只读检查完成：成功 $success 条。"
    } else {
        $result.Status = "success"
        $result.Message = "PO0 官方防火墙上报完成：成功 $success 条。"
    }
    return [pscustomobject]$result
}

function Get-Po0FirewallDashboardSummary {
    if (-not (Test-Po0FirewallConfigured)) { return "未启用（默认关闭）" }
    $state = Get-Po0FirewallState
    if (-not $state -or $null -eq $state.Accounts) { return "已启用，尚无本地状态" }
    $rows = New-Object System.Collections.Generic.List[string]
    foreach ($account in @($state.Accounts)) {
        $fixedSlot = Format-Po0FirewallSlotLabel -Slot ([string]$account.FixedSlot)
        $fixed = if ($fixedSlot) { "，固定槽位 $fixedSlot" } else { "" }
        $rows.Add(("账号 {0}：当前 {1}；白名单 {2}/{3}{4}" -f $account.Index, $account.CurrentIp, $account.Used, $account.Limit, $fixed))
    }
    if ($rows.Count -eq 0) { return "已启用，尚无本地状态" }
    return ($rows -join "；")
}

function Get-Po0FirewallDueSummary {
    if (-not (Test-Po0FirewallConfigured)) { return "未启用（默认关闭）" }
    if (Test-Po0FirewallDue) { return "已到期" }
    return "未到期（每 10 分钟独立检查）"
}

function Enter-Po0SelfReportMutex {
    $names = @(
        "Global\PO0-Outbound-IP-Report"
        "Local\PO0-Outbound-IP-Report"
    )
    foreach ($name in $names) {
        $mutex = $null
        $createdNew = $false
        try {
            $mutex = New-Object System.Threading.Mutex($false, $name, [ref]$createdNew)
        } catch {
            if ($name.StartsWith("Global\", [System.StringComparison]::Ordinal)) {
                continue
            }
            throw "无法创建 PO0 上报并发锁。"
        }
        $acquired = $false
        try {
            try {
                $acquired = $mutex.WaitOne($(if ($script:Po0FirewallScheduledRun) { 120000 } else { 0 }))
            } catch [System.Threading.AbandonedMutexException] {
                $acquired = $true
            }
        } catch {
            try { $mutex.Dispose() } catch {}
            throw "无法取得 PO0 上报并发锁。"
        }
        if ($acquired) {
            return $mutex
        }
        try { $mutex.Dispose() } catch {}
        throw "已有另一个 PO0 上报正在运行。"
    }
    throw "无法创建 PO0 上报并发锁。"
}

function Exit-Po0SelfReportMutex {
    param($Mutex)
    if ($null -eq $Mutex) { return }
    try { $Mutex.ReleaseMutex() } catch {}
    try { $Mutex.Dispose() } catch {}
}

function Get-Po0FirewallWakeIntervalMinutes {
    $minutes = 0
    try { $minutes = [int]$script:Minutes } catch {}
    if ($minutes -lt 1) { $minutes = 10 }
    if (-not (Test-Po0FirewallConfigured)) { return $minutes }
    if ($minutes -gt 10) { return 10 }
    return $minutes
}
