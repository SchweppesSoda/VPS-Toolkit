#requires -Version 5.1

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$sourceRoot = "scripts/po0/relay/self-report/windows/src"
$runningOnWindows = ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT)
$partNames = @(
    "000-runtime-parameters.ps1"
    "010-platform-paths-logging-notification.ps1"
    "020-ui-rendering.ps1"
    "030-config-usage-version.ps1"
    "040-worker-url-interval-validation.ps1"
    "050-outbound-ip-detection.ps1"
    "055-wifi-ssid-policy.ps1"
    "057-channel-settings.ps1"
    "058-official-firewall.ps1"
    "060-report-submit.ps1"
    "070-install-upgrade-task.ps1"
    "080-menu-input-formatting.ps1"
    "090-log-display.ps1"
    "100-schedule-config-uninstall.ps1"
    "110-menu-dispatch.ps1"
)
$tmpRoot = Join-Path (Join-Path $repoRoot ".tmp") ("po0-windows-official.{0}" -f ([guid]::NewGuid().ToString("N")))
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$tokenA = "pgnfw_alpha"
$tokenB = "pgnfw_beta"
$tokenMarker = "$tokenA,$tokenB"
$configPath = Join-Path $tmpRoot "outbound-ip-report.json"
$logPath = Join-Path $tmpRoot "report.log"
$compositePath = Join-Path $tmpRoot "assembled.ps1"
$script:SavedEnvironment = @{}
$script:EnvironmentNames = @(
    "PO0_FIREWALL_TOKENS"
    "PO0_TEST_NOW"
    "PO0_TEST_SCENARIO"
    "LOCALAPPDATA"
    "ProgramData"
    "TEMP"
    "TMP"
    "USERPROFILE"
)
foreach ($name in $script:EnvironmentNames) {
    $entry = Get-Item -LiteralPath ("Env:{0}" -f $name) -ErrorAction SilentlyContinue
    if ($entry) {
        $script:SavedEnvironment[$name] = [string]$entry.Value
    }
}
$env:PO0_FIREWALL_TOKENS = $tokenMarker
$env:PO0_TEST_NOW = "1000"
$env:PO0_TEST_SCENARIO = "hit"
$env:LOCALAPPDATA = $tmpRoot
$env:ProgramData = Join-Path $tmpRoot "program-data"
$env:TEMP = $tmpRoot
$env:TMP = $tmpRoot
$env:USERPROFILE = $tmpRoot

function Fail-Test {
    param([string]$Message)
    throw $Message
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { Fail-Test $Message }
}

function Assert-False {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { Fail-Test $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ([string]$Expected -ne [string]$Actual) {
        Fail-Test ("{0}; expected [{1}], actual [{2}]" -f $Message, $Expected, $Actual)
    }
}

function Assert-Throws {
    param([scriptblock]$Script, [string]$Message)
    $thrown = $false
    try {
        & $Script
    } catch {
        $thrown = $true
    }
    if (-not $thrown) { Fail-Test $Message }
}

function Assert-PowerShellParses {
    param([string]$Path, [string]$Message)
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors -and $errors.Count -gt 0) {
        Fail-Test $Message
    }
}

function Remove-TestState {
    foreach ($path in @(
        (Get-Po0FirewallStatePath)
        (Get-Po0WorkerDueStatePath)
        $configPath
        $logPath
    )) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
    $script:MockMethods = New-Object System.Collections.Generic.List[string]
    $script:MockRequestTokens = New-Object System.Collections.Generic.List[string]
    $script:RunOrder = New-Object System.Collections.Generic.List[string]
    $script:MockWorkerFail = $false
    $script:MockSsidMatched = $false
}

function Set-TestClock {
    param([int64]$Now)
    $env:PO0_TEST_NOW = [string]$Now
}

function New-MockEntry {
    param([string]$Ip, [object]$Slot = $null)
    return [pscustomobject]@{
        ip = $Ip
        slot = $Slot
    }
}

function New-MockBody {
    param(
        [string]$CurrentIp = "198.51.100.7/24",
        [object[]]$Entries = @(),
        [object]$Limit = 5,
        [bool]$Enabled = $true
    )
    $payload = [ordered]@{
        enabled = $Enabled
        currentIp = $CurrentIp
        limit = $Limit
        whitelist = @($Entries)
    }
    return ($payload | ConvertTo-Json -Compress -Depth 6)
}

function Set-TestMode {
    param(
        [string]$Scenario = "hit",
        [string]$Tokens = $tokenA,
        [bool]$Scheduled = $false,
        [bool]$Force = $false,
        [bool]$StatusOnly = $false,
        [bool]$OfficialOnly = $false,
        [bool]$WorkerOnly = $false,
        [string]$Worker = ""
    )
    Remove-TestState
    $script:MockScenario = $Scenario
    $script:Po0FirewallTokens = $Tokens
    $script:Po0FirewallScheduledRun = $Scheduled
    $script:Po0FirewallForce = $Force
    $script:Po0FirewallStatusOnly = $StatusOnly
    $script:Po0FirewallOfficialOnly = $OfficialOnly
    $script:Po0FirewallWorkerOnly = $WorkerOnly
    $script:WorkerUrl = $Worker
    $script:Minutes = 60
    $script:IntervalSeconds = 0
    $script:SkipWifiSsids = @()
    $script:LogPath = $logPath
    $script:AllowHttp = $false
    $script:MockSsidMatched = $false
    $env:PO0_TEST_SCENARIO = $Scenario
    Set-TestClock 1000
}

function Mock-OfficialRequest {
    param(
        [string]$Method,
        [string]$Token,
        [string]$Slot = ""
    )
    [void]$script:MockMethods.Add($Method)
    [void]$script:MockRequestTokens.Add($Token)
    [void]$script:RunOrder.Add("official")
    if ($script:MockScenario -eq "get-failure") {
        throw "mock get failure"
    }
    if ($script:MockScenario -eq "partial-official" -and $Token -eq $tokenB) {
        throw "mock partial failure"
    }
    if ($Method -eq "GET") {
        if ($script:MockScenario -eq "hit") {
            return [pscustomobject]@{ StatusCode = 200; Body = (New-MockBody -Entries @((New-MockEntry -Ip "198.51.100.7/24"))) }
        }
        if ($script:MockScenario -eq "fixed-hit") {
            return [pscustomobject]@{ StatusCode = 200; Body = (New-MockBody -Entries @((New-MockEntry -Ip "198.51.100.7/24" -Slot 0))) }
        }
        if ($script:MockScenario -eq "wrong-slot") {
            return [pscustomobject]@{ StatusCode = 200; Body = (New-MockBody -Entries @((New-MockEntry -Ip "198.51.100.7/24" -Slot 1))) }
        }
        if ($script:MockScenario -eq "ordered") {
            if ($Token -eq $tokenA) {
                return [pscustomobject]@{ StatusCode = 200; Body = (New-MockBody -Entries @((New-MockEntry -Ip "203.0.113.2/24"))) }
            }
            return [pscustomobject]@{ StatusCode = 200; Body = (New-MockBody -Entries @((New-MockEntry -Ip "198.51.100.7/24"))) }
        }
        if ($script:MockScenario -eq "empty-slot") {
            return [pscustomobject]@{ StatusCode = 200; Body = (New-MockBody -Entries @((New-MockEntry -Ip "198.51.100.7/24" -Slot ""))) }
        }
        if ($script:MockScenario -eq "null-slot") {
            return [pscustomobject]@{ StatusCode = 200; Body = (New-MockBody -Entries @((New-MockEntry -Ip "198.51.100.7/24" -Slot $null))) }
        }
        if ($script:MockScenario -eq "bad-enabled") {
            return [pscustomobject]@{ StatusCode = 200; Body = (New-MockBody -Enabled $false -Entries @()) }
        }
        if ($script:MockScenario -eq "bad-limit") {
            return [pscustomobject]@{ StatusCode = 200; Body = (New-MockBody -Limit "5" -Entries @()) }
        }
        if ($script:MockScenario -eq "bad-whitelist") {
            return [pscustomobject]@{ StatusCode = 200; Body = (New-MockBody -CurrentIp "198.51.100.7" -Entries @()) }
        }
        if ($script:MockScenario -eq "duplicate-slots") {
            return [pscustomobject]@{ StatusCode = 200; Body = (New-MockBody -Entries @(
                (New-MockEntry -Ip "198.51.100.7/24" -Slot 0)
                (New-MockEntry -Ip "203.0.113.2/24" -Slot 0)
            )) }
        }
        if ($script:MockScenario -eq "status-missing" -or $script:MockScenario -eq "missing" -or $script:MockScenario -eq "bad-post") {
            return [pscustomobject]@{ StatusCode = 200; Body = (New-MockBody -Entries @((New-MockEntry -Ip "203.0.113.2/24"))) }
        }
        return [pscustomobject]@{ StatusCode = 200; Body = (New-MockBody -Entries @((New-MockEntry -Ip "198.51.100.7/24"))) }
    }

    if ($script:MockScenario -eq "bad-post") {
        return [pscustomobject]@{ StatusCode = 200; Body = (New-MockBody -Entries @((New-MockEntry -Ip "203.0.113.2/24"))) }
    }
    $postSlot = $null
    if ($Slot) { $postSlot = [int]$Slot }
    return [pscustomobject]@{ StatusCode = 200; Body = (New-MockBody -Entries @((New-MockEntry -Ip "198.51.100.7/24" -Slot $postSlot))) }
}

function Mock-WorkerRequest {
    [void]$script:RunOrder.Add("worker")
    if ($script:MockWorkerFail) { throw "mock worker failure" }
    return [pscustomobject]@{
        Succeeded = $true
        Ip = "198.51.100.7"
        Message = "worker mock ok"
    }
}

function Get-MockWifiState {
    if ($script:MockSsidMatched) {
        return [pscustomobject]@{
            Enabled = $true
            ReadSucceeded = $true
            Matched = $true
            MatchedSsid = "Office"
            Error = ""
        }
    }
    return [pscustomobject]@{
        Enabled = $true
        ReadSucceeded = $true
        Matched = $false
        MatchedSsid = ""
        Error = ""
    }
}

try {
    $sourceTexts = New-Object System.Collections.Generic.List[string]
    $sourcePaths = New-Object System.Collections.Generic.List[string]
    foreach ($partName in $partNames) {
        $sourcePath = Join-Path (Join-Path $repoRoot $sourceRoot) $partName
        Assert-True (Test-Path -LiteralPath $sourcePath) ("Missing Windows source: {0}" -f $partName)
        $parseCopy = Join-Path $tmpRoot ("parse-{0}" -f $partName)
        $sourceText = [System.IO.File]::ReadAllText($sourcePath, $utf8NoBom)
        [System.IO.File]::WriteAllText($parseCopy, $sourceText, $utf8Bom)
        Assert-PowerShellParses -Path $parseCopy -Message ("PowerShell syntax failed: {0}" -f $partName)
        Remove-Item -LiteralPath $parseCopy -Force
        [void]$sourceTexts.Add($sourceText.TrimEnd())
        [void]$sourcePaths.Add($sourcePath)
    }
    $compositeText = [string]::Join(([string][char]10 + [string][char]10), $sourceTexts.ToArray())
    [System.IO.File]::WriteAllText($compositePath, $compositeText + [string][char]10, $utf8Bom)
    Assert-PowerShellParses -Path $compositePath -Message "Assembled Windows asset failed PowerShell parsing."

    $officialSource = [System.IO.File]::ReadAllText((Join-Path (Join-Path $repoRoot $sourceRoot) "058-official-firewall.ps1"), $utf8NoBom)
    $allSource = [string]::Join(([string][char]10), $sourceTexts.ToArray())
    Assert-True ($officialSource.Contains("https://124.221.69.228/api/firewall")) "Official API endpoint changed."
    Assert-True ($officialSource.Contains('UseProxy = $false')) "Official HTTP client must disable proxy."
    Assert-True ($officialSource.Contains("ResponseHeadersRead")) "Official HTTP response must be bounded/streamed."
    Assert-True ($officialSource.Contains("ContentLength")) "Official HTTP content length must be bounded."
    Assert-True ($officialSource.Contains("Tls12")) "Official HTTP must require TLS 1.2."
    Assert-True ($officialSource.Contains("Enter-Po0SelfReportMutex")) "Whole-run mutex entry is missing."
    Assert-True ($officialSource.Contains("SetAccessRuleProtection") -or $allSource.Contains("SetAccessRuleProtection")) "Config ACL protection is missing."
    $runtimeSource = [System.IO.File]::ReadAllText((Join-Path (Join-Path $repoRoot $sourceRoot) "000-runtime-parameters.ps1"), $utf8NoBom)
    Assert-False ($runtimeSource -match '(?im)^\s*\[(?!switch\])[^\r\n]*\]\s*\$[A-Za-z0-9_]*Tokens?\b') "Token-value CLI parameter must not exist."
    $usageSource = [System.IO.File]::ReadAllText((Join-Path (Join-Path $repoRoot $sourceRoot) "030-config-usage-version.ps1"), $utf8NoBom)
    Assert-False ($usageSource -match "(?i)(--po0-firewall-tokens|--firewall-tokens|-Po0FirewallTokens)\s+\S") "Help must not expose token-value CLI."
    $taskSource = [System.IO.File]::ReadAllText((Join-Path (Join-Path $repoRoot $sourceRoot) "070-install-upgrade-task.ps1"), $utf8NoBom)
    Assert-True ($taskSource.Contains("-ScheduledRun")) "Scheduled task must mark scheduled runs."
    Assert-False ($taskSource -match "(?i)(Po0FirewallTokens|PO0_FIREWALL_TOKENS).*(taskArgList|ArgumentList)") "Scheduled task argv must not contain tokens."
    $manifest = [System.IO.File]::ReadAllText((Join-Path $repoRoot "tools/po0/manifests/self-report-windows.txt"), $utf8NoBom)
    Assert-True ($manifest.Contains("058-official-firewall.ps1")) "Windows manifest must include the official channel."

    . $compositePath -ConfigPath $configPath -WorkerUrl "https://worker.invalid/report" -Minutes 60 -LogPath $logPath -RunOnce
    if (-not $runningOnWindows) {
        $script:MockClientConfigAclCallCount = 0
        function Set-Po0ClientConfigAcl {
            param([string]$Path)
            Assert-True (Test-Path -LiteralPath $Path) "Config ACL mock must receive an existing temporary file."
            $script:MockClientConfigAclCallCount++
        }
    }
    function Test-IsAdmin { return $false }
    function Write-SelfReportLogLine { param($Level, $Message) }
    function Write-SelfReportInfo { param([string]$Message) }
    function Write-SelfReportCompleted { param([string]$Message) }
    function Write-SelfReportIncomplete { param([string]$Message) }
    function Show-WindowsSelfReportNotification { param($Title, $Message, $Kind) }
    function Write-SelfReportSkippedForWifiSsid { param($State) }
    function Get-OutboundIPv4 { return "198.51.100.7" }
    function Get-WifiSsidPolicyState { return (Get-MockWifiState) }
    function Invoke-Po0OfficialHttpRequest { param($Method, $Token, $Slot = ""); return (Mock-OfficialRequest -Method $Method -Token $Token -Slot $Slot) }
    function Invoke-WorkerSelfReportCore { return (Mock-WorkerRequest) }
    function Enter-Po0SelfReportMutex { $script:MutexEnterCount++; return [pscustomobject]@{ Held = $true } }
    function Exit-Po0SelfReportMutex { param($Mutex); $script:MutexExitCount++ }
    $script:MutexEnterCount = 0
    $script:MutexExitCount = 0

    Assert-True ($null -ne (Get-Command Invoke-SelfReport -CommandType Function)) "Assembled asset did not expose Invoke-SelfReport."
    Set-TestMode -Scenario "hit" -Tokens $tokenA -Worker "" -Scheduled $false
    $savedSecretForInputTest = $script:Secret
    $script:Secret = "worker-visible-fixture"
    $script:Po0FirewallTokens = "pgnfw_visible_fixture@3"
    $script:VisibleRows = New-Object System.Collections.Generic.List[string]
    function Write-PanelRow { param($Label, $Value); $script:VisibleRows.Add("$Label=$Value") }
    function Format-CurrentWifiSsidStatus { return "Fixture Wi-Fi" }
    Show-ClientConfig
    Assert-True (($script:VisibleRows -join "`n").Contains("worker-visible-fixture")) "Local configuration must show the saved Worker secret."
    Assert-True (($script:VisibleRows -join "`n").Contains("pgnfw_visible_fixture@3")) "Local configuration must show the full official token and slot."
    $script:InputLines = New-Object System.Collections.Generic.Queue[string]
    foreach ($line in @("pgnfw_input_a@0 pgnfw_input_b@1", "pgnfw_input_c@4", "")) { $script:InputLines.Enqueue($line) }
    function Read-Host { param($Prompt); return $script:InputLines.Dequeue() }
    Read-Po0FirewallTokensInteractive
    Assert-Equal "pgnfw_input_a@0,pgnfw_input_b@1,pgnfw_input_c@4" $script:Po0FirewallTokens "Visible multiline input must preserve every account and slot."
    $script:InputLines.Enqueue("bad-token")
    $script:InputLines.Enqueue("")
    Assert-Throws { Read-Po0FirewallTokensInteractive } "Invalid input must fail."
    Assert-Equal "pgnfw_input_a@0,pgnfw_input_b@1,pgnfw_input_c@4" $script:Po0FirewallTokens "Invalid input must retain saved tokens."
    $script:InputLines.Enqueue("-")
    Read-Po0FirewallTokensInteractive
    Assert-Equal "" $script:Po0FirewallTokens "A single dash must clear tokens."
    $script:Secret = $savedSecretForInputTest
    $mixedItems = @(Get-Po0FirewallTokenItems -Value " ,pgnfw_a@0 pgnfw_b@1`npgnfw_c@2; pgnfw_d@3，pgnfw_e@4；pgnfw_f, ")
    Assert-Equal 6 $mixedItems.Count "All token separators must be accepted."
    Assert-Equal "pgnfw_a@0,pgnfw_b@1,pgnfw_c@2,pgnfw_d@3,pgnfw_e@4,pgnfw_f" (ConvertTo-Po0FirewallNormalizedTokens -Items $mixedItems) "Normalized values and slots must survive."
    Set-TestMode -Scenario "hit" -Tokens $tokenA -Worker "" -Scheduled $false
    Invoke-SelfReport
    Assert-True ($script:MutexEnterCount -gt 0) "RunOnce flow did not reach the top-level report wrapper."
    Assert-Equal $script:MutexEnterCount $script:MutexExitCount "Report mutex cleanup must run in finally."

    Set-TestMode -Scenario "hit" -Tokens $tokenA -Worker ""
    $result = Invoke-Po0FirewallReport -Mode "report"
    Assert-True $result.Succeeded "GET hit should succeed."
    Assert-Equal 1 @($script:MockMethods).Count "GET hit should issue one request."
    Assert-False (@($script:MockMethods) -contains "POST") "GET hit must not POST."

    Set-TestMode -Scenario "missing" -Tokens $tokenA -Worker ""
    $result = Invoke-Po0FirewallReport -Mode "report"
    Assert-True $result.Succeeded "Missing current /24 should be added."
    Assert-Equal 2 @($script:MockMethods).Count "Missing current /24 should GET then POST."
    Assert-Equal "GET" $script:MockMethods[0] "Missing flow must GET first."
    Assert-Equal "POST" $script:MockMethods[1] "Missing flow must POST second."

    Set-TestMode -Scenario "fixed-hit" -Tokens "$tokenA@0"
    $result = Invoke-Po0FirewallReport -Mode "report"
    Assert-True $result.Succeeded "Fixed-slot hit should succeed."
    Assert-False (@($script:MockMethods) -contains "POST") "Fixed-slot hit must not POST."

    Set-TestMode -Scenario "wrong-slot" -Tokens "$tokenA@0"
    $result = Invoke-Po0FirewallReport -Mode "report"
    Assert-True $result.Succeeded "Wrong fixed slot should be repaired."
    Assert-Equal 2 @($script:MockMethods).Count "Wrong fixed slot should GET then POST."

    foreach ($scenario in @("bad-enabled", "bad-limit", "bad-whitelist", "duplicate-slots")) {
        Set-TestMode -Scenario $scenario -Tokens $tokenA
        $result = Invoke-Po0FirewallReport -Mode "report"
        Assert-False $result.Succeeded ("Invalid {0} response must fail." -f $scenario)
        Assert-Equal 1 @($script:MockMethods).Count ("Invalid {0} response should only GET." -f $scenario)
        Assert-False (@($script:MockMethods) -contains "POST") ("Invalid {0} response must not POST." -f $scenario)
    }

    Set-TestMode -Scenario "empty-slot" -Tokens $tokenA
    $result = Invoke-Po0FirewallReport -Mode "report"
    Assert-True $result.Succeeded "Empty response slot should be accepted."
    Set-TestMode -Scenario "null-slot" -Tokens $tokenA
    $result = Invoke-Po0FirewallReport -Mode "report"
    Assert-True $result.Succeeded "Null response slot should be accepted."

    Set-TestMode -Scenario "bad-post" -Tokens $tokenA
    $result = Invoke-Po0FirewallReport -Mode "report"
    Assert-False $result.Succeeded "Unconfirmed POST must fail."
    Assert-Equal 2 @($script:MockMethods).Count "Bad POST should still be GET then POST."

    Set-TestMode -Scenario "ordered" -Tokens "$tokenA,$tokenB"
    $result = Invoke-Po0FirewallReport -Mode "report"
    Assert-True $result.Succeeded "Ordered accounts should complete."
    Assert-Equal 3 @($script:MockMethods).Count "Ordered account requests count."
    Assert-Equal $tokenA $script:MockRequestTokens[0] "First account must execute first."
    Assert-Equal $tokenA $script:MockRequestTokens[1] "First account POST must stay with first token."
    Assert-Equal $tokenB $script:MockRequestTokens[2] "Second account must execute after first."

    foreach ($badTokenValue in @(
        "$tokenA,$tokenA"
        "$tokenA@0,$tokenA@0"
        "$tokenA@0,$tokenA@1"
        "$tokenA,$tokenA@0"
        "$tokenA@5"
        "$tokenA@0@1"
    )) {
        Assert-Throws { Get-Po0FirewallTokenItems -Value $badTokenValue } ("Malformed token list accepted: {0}" -f $badTokenValue)
    }
    $goodItems = @(Get-Po0FirewallTokenItems -Value "$tokenA@0,$tokenB@4")
    Assert-Equal 2 $goodItems.Count "Valid token slots should parse."

    Set-TestMode -Scenario "partial-official" -Tokens "$tokenA,$tokenB"
    $result = Invoke-Po0FirewallReport -Mode "report"
    Assert-False $result.Succeeded "Partial official result must be nonzero."
    Assert-Equal "partial" $result.Status "Partial official status."
    Assert-Equal 1 $result.SuccessCount "Partial official success count."
    Assert-Equal 1 $result.FailureCount "Partial official failure count."

    Set-TestMode -Scenario "hit" -Tokens $tokenA -Worker "https://worker.invalid/report" -Scheduled $true
    Set-TestClock 1000
    Mark-Po0FirewallAttempt
    Set-TestClock 1100
    Assert-False (Test-Po0FirewallDue) "Official due must be independent and fixed at 600 seconds."
    Set-TestClock 1600
    Assert-True (Test-Po0FirewallDue) "Official must be due at 600 seconds."
    Set-TestClock 900
    Assert-True (Test-Po0FirewallDue) "Clock rollback must be treated as due."
    Set-TestClock 1000
    Mark-Po0WorkerAttempt
    Set-TestClock 1100
    Assert-False (Test-Po0WorkerDue) "Worker must keep its own due state."
    Set-TestClock 4600
    Assert-True (Test-Po0WorkerDue) "Worker must use its configured hourly due."

    Set-TestMode -Scenario "hit" -Tokens $tokenA
    $script:Minutes = 60
    Assert-Equal 10 (Get-Po0FirewallWakeIntervalMinutes) "Official config must wake at most every ten minutes."
    $script:Minutes = 5
    Assert-Equal 5 (Get-Po0FirewallWakeIntervalMinutes) "Short configured Worker interval must be preserved."
    $script:Po0FirewallTokens = ""
    Assert-Equal 5 (Get-Po0FirewallWakeIntervalMinutes) "Unconfigured official lane must not change Worker wake interval."

    $script:Po0FirewallTokens = $tokenA
    $script:Minutes = 10
    $isoTask = [pscustomobject]@{
        Triggers = @(
            [pscustomobject]@{
                Repetition = [pscustomobject]@{ Interval = "PT10M" }
            }
        )
    }
    Assert-True (Test-ScheduledReporterTaskWakeInterval -Task $isoTask) "CIM ISO8601 PT10M interval should be accepted."
    $taskArgs = @(Get-ScheduledReporterTaskArgumentList -ScriptPath (Join-Path $tmpRoot "po0.ps1"))
    Assert-True ($taskArgs -contains "-RunOnce") "Scheduled task must pass RunOnce."
    Assert-True ($taskArgs -contains "-ScheduledRun") "Scheduled task must pass ScheduledRun."
    Assert-False (($taskArgs -join " ") -match [regex]::Escape($tokenMarker)) "Scheduled task arguments must not contain tokens."

    Set-TestMode -Scenario "hit" -Tokens $tokenA -Worker "https://worker.invalid/report"
    $script:SkipWifiSsids = @("Office")
    $script:MockSsidMatched = $true
    Invoke-SelfReport
    Assert-Equal 0 @($script:MockMethods).Count "SSID skip must skip official GET."
    Assert-False (@($script:RunOrder) -contains "worker") "SSID skip must skip Worker too."

    Set-TestMode -Scenario "hit" -Tokens $tokenA -Worker "https://worker.invalid/report" -Force $true
    $script:SkipWifiSsids = @("Office")
    $script:MockSsidMatched = $true
    Invoke-SelfReport
    Assert-Equal 1 @($script:MockMethods).Count "Forced run must execute official lane."
    Assert-Equal "official" $script:RunOrder[0] "Official lane must run first."
    Assert-Equal "worker" $script:RunOrder[1] "Worker lane must run second."

    Set-TestMode -Scenario "hit" -Tokens $tokenA -Worker "http://bad.invalid" -OfficialOnly $true
    Invoke-SelfReport
    Assert-False (@($script:RunOrder) -contains "worker") "OfficialOnly must not execute Worker."

    Set-TestMode -Scenario "hit" -Tokens "invalid," -Worker "https://worker.invalid/report" -WorkerOnly $true
    Invoke-SelfReport
    Assert-Equal 0 @($script:MockMethods).Count "WorkerOnly must not execute official."
    Assert-Equal "worker" $script:RunOrder[0] "WorkerOnly must execute Worker."

    Set-TestMode -Scenario "hit" -Tokens $tokenA -Worker "https://worker.invalid/report" -Force $true
    $script:MockWorkerFail = $true
    Assert-Throws { Invoke-SelfReport } "Partial Worker failure must return nonzero."
    Assert-Equal "official" $script:RunOrder[0] "Partial run must execute official first."
    Assert-Equal "worker" $script:RunOrder[1] "Partial run must still execute Worker."

    Set-TestMode -Scenario "hit" -Tokens $tokenA -Scheduled $true
    Set-TestClock 500
    Mark-Po0FirewallAttempt
    Set-TestMode -Scenario "status-missing" -Tokens $tokenA -StatusOnly $true
    Set-TestClock 600
    Write-Po0FirewallState -Accounts @([pscustomobject]@{
        Index = 1
        FixedSlot = ""
        CurrentIp = "198.51.100.7/24"
        Limit = 5
        Used = 1
        Whitelist = @()
        Status = "ok"
    }) -LastOfficialAttempt 500
    Invoke-SelfReport
    Assert-Equal 1 @($script:MockMethods).Count "Status must issue one GET."
    Assert-False (@($script:MockMethods) -contains "POST") "Status must never POST."
    $statusState = Get-Po0FirewallState
    Assert-Equal 500 $statusState.LastOfficialAttempt "Status must preserve official due timestamp."
    Assert-True (@($statusState.Accounts).Count -gt 0) "Status must save sanitized Accounts."
    $statusText = Get-Content -LiteralPath (Get-Po0FirewallStatePath) -Raw -Encoding UTF8
    Assert-False ($statusText.Contains($tokenMarker)) "Token must not enter state."
    $stateText = $statusText

    # Each automatic lane can stop independently without affecting manual runs.
    foreach ($enabled in @(@($false, $true), @($true, $false), @($false, $false))) {
        Set-TestMode -Scenario "hit" -Tokens $tokenA -Worker "https://worker.invalid/report" -Scheduled $true -Force $true
        $script:WorkerAutoEnabled = $enabled[0]
        $script:OfficialAutoEnabled = $enabled[1]
        Invoke-SelfReport
        Assert-Equal ([bool]$enabled[0]) ([bool](@($script:RunOrder) -contains 'worker')) 'Worker automatic switch was ignored.'
        Assert-Equal ([bool]$enabled[1]) ([bool](@($script:RunOrder) -contains 'official')) 'Official automatic switch was ignored.'
        Assert-Equal $tokenA $script:Po0FirewallTokens 'Pausing must retain the Token.'
    }
    Set-TestMode -Scenario "hit" -Tokens $tokenA -Worker "https://worker.invalid/report" -Scheduled $false -Force $true
    $script:WorkerAutoEnabled = $false
    $script:OfficialAutoEnabled = $false
    Invoke-ChannelInteractive worker
    Assert-Equal 'worker' ($script:RunOrder -join ',') 'Manual Worker-only must ignore automatic pause.'
    Assert-False $script:Po0FirewallWorkerOnly 'Menu must restore one-shot channel selection.'
    $script:Po0FirewallTokens = 'pgnfw_beta@3,pgnfw_alpha@0'
    $script:Po0FirewallNames = '家庭;Office Wi-Fi'
    Sync-OfficialAccountNames 'pgnfw_alpha,pgnfw_beta'
    Assert-Equal 'Office Wi-Fi;家庭' $script:Po0FirewallNames 'Names must follow accounts across reorder and slot changes.'
    $script:WorkerName = '测试接收端'
    Save-ClientConfig
    $script:WorkerAutoEnabled = $true
    $script:OfficialAutoEnabled = $true
    $script:WorkerName = ''
    Load-SavedConfig
    Assert-False $script:WorkerAutoEnabled 'Worker pause must survive reload.'
    Assert-False $script:OfficialAutoEnabled 'Official pause must survive reload.'
    Assert-Equal '测试接收端' $script:WorkerName 'Name must survive reload.'
    $script:WorkerAutoEnabled = $true
    $script:OfficialAutoEnabled = $true

    Set-TestMode -Scenario "hit" -Tokens $tokenA
    $script:ConfigPath = $configPath
    if (-not $runningOnWindows) { $script:MockClientConfigAclCallCount = 0 }
    Save-ClientConfig
    Assert-True (Test-Path -LiteralPath $configPath) "Config must be written."
    $configText = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
    Assert-True ($configText.Contains($tokenA)) "Configured token must be persisted in config."
    if ($runningOnWindows) {
        $configAcl = Get-Acl -LiteralPath $configPath
        Assert-True ([bool]$configAcl.AreAccessRulesProtected) "Token-bearing config ACL must disable inheritance."
        $configRules = @($configAcl.Access | ForEach-Object { [string]$_.IdentityReference.Value })
        Assert-True (@($configRules | Where-Object { $_ -match "S-1-5-18" -or $_ -match "SYSTEM" }).Count -gt 0) "Config ACL must retain SYSTEM."
        Assert-True (@($configRules | Where-Object { $_ -match "S-1-5-32-544" -or $_ -match "Administrators" }).Count -gt 0) "Config ACL must retain Administrators."
    }
    if (-not $runningOnWindows) {
        Assert-Equal 1 $script:MockClientConfigAclCallCount "Config ACL mock should be called once."
    }

    Assert-False ((Test-Path -LiteralPath $logPath) -and (Get-Content -LiteralPath $logPath -Raw -ErrorAction SilentlyContinue).Contains($tokenA)) "Token must not enter log."

    Write-Host "Windows official firewall mock tests passed."
} catch {
    Write-Host $_.ScriptStackTrace
    Write-Error $_.Exception.Message
    exit 1
} finally {
    foreach ($name in $script:EnvironmentNames) {
        if ($script:SavedEnvironment.ContainsKey($name)) {
            Set-Item -LiteralPath ("Env:{0}" -f $name) -Value $script:SavedEnvironment[$name]
        } else {
            Remove-Item -LiteralPath ("Env:{0}" -f $name) -ErrorAction SilentlyContinue
        }
    }
    if (Test-Path -LiteralPath $tmpRoot) {
        Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}














