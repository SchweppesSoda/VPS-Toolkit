$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("po0-windows-refresh-test-{0}" -f ([guid]::NewGuid().ToString("N")))
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$utf8Bom = [System.Text.UTF8Encoding]::new($true)

New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
try {
    $composite = Join-Path $tmpRoot "windows-refresh-policy-under-test.ps1"
    $parts = @(
        "scripts\po0\relay\self-report\windows\src\000-runtime-parameters.ps1",
        "scripts\po0\relay\self-report\windows\src\010-platform-paths-logging-notification.ps1",
        "scripts\po0\relay\self-report\windows\src\070-install-upgrade-task.ps1",
        "scripts\po0\relay\self-report\windows\src\058-official-firewall.ps1"
    )
    $body = New-Object System.Collections.Generic.List[string]
    foreach ($part in $parts) {
        $path = Join-Path $repoRoot $part
        $partText = [System.IO.File]::ReadAllText($path, $utf8NoBom).TrimEnd()
        if ($part -like "*070-install-upgrade-task.ps1") {
            $partText = $partText.Replace("New-ScheduledTaskAction", "Invoke-TestNewScheduledTaskAction")
            $partText = $partText.Replace("New-ScheduledTaskTrigger", "Invoke-TestNewScheduledTaskTrigger")
            $partText = $partText.Replace("Register-ScheduledTask", "Invoke-TestRegisterScheduledTask")
            $partText = $partText.Replace("Set-ScheduledTask", "Invoke-TestSetScheduledTask")
            $partText = $partText.Replace("Enable-ScheduledTask", "Invoke-TestEnableScheduledTask")
            $partText = $partText.Replace("Disable-ScheduledTask", "Invoke-TestDisableScheduledTask")
        }
        $body.Add($partText)
    }
    $body.Add(@'
function Fail {
    param([string]$Message)
    throw "FAIL: $Message"
}

if (-not (Get-Command Test-ScheduledReporterTaskCurrent -ErrorAction SilentlyContinue)) {
    Fail "missing Test-ScheduledReporterTaskCurrent"
}

$scriptPath = Get-DefaultScriptPath
$launcherPath = Get-DefaultTaskLauncherPath
if ($script:TaskName -ne "Outbound IP Report") {
    Fail "task name should be simple"
}
if ((Split-Path -Leaf $launcherPath) -ne "po0-outbound-ip-report-task.vbs") {
    Fail "task launcher name should remain old for self-update compatibility"
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $scriptPath) | Out-Null
Set-Content -LiteralPath $scriptPath -Encoding UTF8 -Value "# test script"
Write-ScheduledReporterTaskLauncher -LauncherPath $launcherPath -ScriptPath $scriptPath | Out-Null

$task = [pscustomobject]@{
    Actions = @([pscustomobject]@{
        Arguments = "//B //Nologo " + (Quote-TaskArg $launcherPath)
    })
    State = "Ready"
}

if (-not (Test-ScheduledReporterTaskCurrent -Task $task -ScriptPath $scriptPath)) {
    Fail "current task should not require refresh"
}

$legacyTask = [pscustomobject]@{
    Actions = @([pscustomobject]@{
        Arguments = "//B //Nologo " + (Quote-TaskArg (Get-LegacyTaskLauncherPath))
    })
    State = "Ready"
}
if (Test-ScheduledReporterTaskCurrent -Task $legacyTask -ScriptPath $scriptPath) {
    Fail "legacy launcher should require refresh"
}

$script:TaskNotify = $true
Write-ScheduledReporterTaskLauncher -LauncherPath $launcherPath -ScriptPath $scriptPath | Out-Null
$script:TaskNotify = $false
if (Test-ScheduledReporterTaskCurrent -Task $task -ScriptPath $scriptPath) {
    Fail "notify drift should require refresh"
}

$script:TaskNotify = $false
Import-ScheduledReporterTaskSettings -Task $task -KeepNotifyPreference
if ($script:TaskNotify) {
    Fail "KeepNotifyPreference should not import old task notify state"
}

$script:MockRecord = [pscustomobject]@{ Task = $null; Name = ""; IsLegacy = $false }
$script:SetTaskCalled = $false
$script:RegisterTaskCalled = $false
$script:RemoveLegacyCalled = $false

function Get-ScheduledReporterTaskRecord {
    return $script:MockRecord
}

function Cleanup-LegacySelfReportArtifacts {
    param([switch]$Quiet)
    return $true
}

function Invoke-TestNewScheduledTaskAction {
    param([string]$Execute, [string]$Argument)
    return [pscustomobject]@{ Execute = $Execute; Arguments = $Argument }
}


function Invoke-TestNewScheduledTaskTrigger {
    param([switch]$Once, [datetime]$At, $RepetitionInterval, $RepetitionDuration)
    return [pscustomobject]@{ Repetition = [pscustomobject]@{ Interval = $RepetitionInterval }; StartBoundary = $At }
}
function Invoke-TestSetScheduledTask {
    param([string]$TaskName, $Action, $Trigger)
    $script:SetTaskCalled = $true
}

function Invoke-TestEnableScheduledTask {
    param([string]$TaskName)
}

function Invoke-TestDisableScheduledTask {
    param([string]$TaskName)
}

function Invoke-TestRegisterScheduledTask {
    param([string]$TaskName, $Action, $Trigger, $Settings, $Principal, $Description, [switch]$Force)
    $script:RegisterTaskCalled = $true
}

function Remove-LegacyScheduledReporterTask {
    $script:RemoveLegacyCalled = $true
    return $true
}

function Ensure-DefaultSelfReportScriptInstalled {
    return $scriptPath
}

if (-not (Get-Command Invoke-TestRegisterScheduledTask -CommandType Function -ErrorAction SilentlyContinue)) { Fail "isolated Register stub was not defined" }
if ((Update-ScheduledReporterLauncherForExistingTask) -ne "none") {
    Fail "missing task should return none"
}

$script:MockRecord = [pscustomobject]@{ Task = $task; Name = $script:TaskName; IsLegacy = $false }
$script:TaskNotify = $true
Write-ScheduledReporterTaskLauncher -LauncherPath $launcherPath -ScriptPath $scriptPath | Out-Null
if ((Update-ScheduledReporterLauncherForExistingTask) -ne "current") {
    Fail "current task should return current"
}
if ($script:SetTaskCalled -or $script:RegisterTaskCalled) {
    Fail "current task should not rewrite scheduled task"
}

$script:TaskNotify = $false
$script:SetTaskCalled = $false
if ((Update-ScheduledReporterLauncherForExistingTask) -ne "refreshed") {
    Fail "notify drift should return refreshed"
}
if (-not $script:SetTaskCalled) {
    Fail "refreshed path should call Set-ScheduledTask"
}

$script:MockRecord = [pscustomobject]@{ Task = $legacyTask; Name = $script:LegacyTaskName; IsLegacy = $true }
$script:RegisterTaskCalled = $false
$script:RemoveLegacyCalled = $false
if ((Update-ScheduledReporterLauncherForExistingTask) -ne "migrated") {
    Fail "legacy task should return migrated"
}
if (-not $script:RegisterTaskCalled -or -not $script:RemoveLegacyCalled) {
    Fail "migrated path should register new task and remove legacy task"
}

Write-Host "Windows refresh policy tests passed."
'@)
    [System.IO.File]::WriteAllText($composite, ([string]::Join("`n`n", $body) + "`n"), $utf8Bom)

    $env:LOCALAPPDATA = $tmpRoot
    & powershell -NoProfile -ExecutionPolicy Bypass -File $composite -ConfigPath (Join-Path $tmpRoot "outbound-ip-report.json") -LogPath (Join-Path $tmpRoot "po0-outbound-ip-report.log")
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
} finally {
    Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}
