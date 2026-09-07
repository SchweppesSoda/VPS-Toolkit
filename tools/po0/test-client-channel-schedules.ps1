$ErrorActionPreference='Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$testRoot = Join-Path $repo ('.tmp/po0-windows-channel-schedules-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    $sourceDir=Join-Path $repo 'scripts/po0/relay/self-report/windows/src'
    $parts=Get-ChildItem -LiteralPath $sourceDir -Filter '*.ps1' | Where-Object Name -NotLike '990-*' | Sort-Object Name
    $composite=Join-Path $testRoot 'functions.ps1'
    $body=($parts | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"
    [IO.File]::WriteAllText($composite,$body,[Text.UTF8Encoding]::new($true))
    . $composite
    $script:Tasks=@{}; $script:Calls=[Collections.Generic.List[string]]::new()
    $script:TestDir=$testRoot
    function Get-DefaultDataDir { return $script:TestDir }
    function Get-DefaultScriptPath { return Join-Path $script:TestDir 'po0-outbound-ip-report.ps1' }
    function Get-DefaultLogPath { return Join-Path $script:TestDir 'report.log' }
    function Save-ClientConfig {}
    function Assert-WorkerUrl {}
    function Assert-Minutes {}
    function Test-WindowsNetworkWatchSupported { return $true }
    function Get-ScheduledTask { param($TaskName,$ErrorAction) return $script:Tasks[$TaskName] }
    function Get-ScheduledTaskInfo { param($TaskName,$ErrorAction) return $null }
    function New-ScheduledTaskAction { param($Execute,$Argument) return [pscustomobject]@{Execute=$Execute;Arguments=$Argument} }
    function New-ScheduledTaskTrigger { param([switch]$Once,$At,$RepetitionInterval,$RepetitionDuration,[switch]$AtLogOn) return [pscustomobject]@{RepetitionInterval=$RepetitionInterval;AtLogOn=[bool]$AtLogOn} }
    function New-ScheduledTaskSettingsSet { param($ExecutionTimeLimit,$MultipleInstances,[switch]$AllowStartIfOnBatteries,[switch]$DontStopIfGoingOnBatteries) return [pscustomobject]@{} }
    function Register-ScheduledTask {
        param($TaskName,$Action,$Trigger,$Description,$Settings,$Principal,[switch]$Force)
        if ($script:FailTaskName -and $TaskName -eq $script:FailTaskName) { throw 'fixture registration failure' }
        $script:Calls.Add('register '+$TaskName)
        $script:Tasks[$TaskName]=[pscustomobject]@{TaskName=$TaskName;Actions=@($Action);Triggers=@($Trigger);State='Ready';Settings=$Settings;Principal=$Principal}
    }
    function Disable-ScheduledTask { param($TaskName,$ErrorAction) $script:Tasks[$TaskName].State='Disabled'; $script:Calls.Add('disable '+$TaskName) }
    function Enable-ScheduledTask { param($TaskName,$ErrorAction) $script:Tasks[$TaskName].State='Ready'; $script:Calls.Add('enable '+$TaskName) }
    function Start-ScheduledTask { param($TaskName) $script:Calls.Add('start '+$TaskName) }
    function Stop-ScheduledTask { param($TaskName,$ErrorAction) $script:Calls.Add('stop '+$TaskName) }
    function Unregister-ScheduledTask { param($TaskName,$Confirm,$ErrorAction) $script:Tasks.Remove($TaskName); $script:Calls.Add('remove '+$TaskName) }
    function Assert-Test { param($Value,$Message) if (-not $Value) { throw "FAIL: $Message" } }
    $script:ConfigPath=Join-Path $testRoot 'settings.json'; $script:LogPath=Get-DefaultLogPath
    $script:WorkerUrl='https://worker.example.test/report'; $script:Secret='dummy-secret'; $script:Po0FirewallTokens='pgnfw_schedule_fixture@1'
    $script:Minutes=60; $script:OfficialIntervalSeconds=900; $script:SchedulePaused=$false; $script:TaskNotify=$false
    $script:WorkerAutoEnabled=$true; $script:OfficialAutoEnabled=$true; $script:WorkerTimerEnabled=$true; $script:OfficialTimerEnabled=$true
    $script:WorkerNetworkEnabled=$true; $script:OfficialNetworkEnabled=$true
    Set-Content -LiteralPath (Get-DefaultScriptPath) -Value '# test script'
    Sync-ScheduledReporterTasks -Mode install | Out-Null
    Assert-Test ($script:Tasks.Count -eq 4) 'two independent timers and two network watchers'
    $worker=Get-ChannelTaskName worker; $official=Get-ChannelTaskName official
    Assert-Test ($script:Tasks[$official].Triggers[0].RepetitionInterval.TotalSeconds -eq 900) 'custom official timer'
    $command=Get-ScheduledReporterLauncherCommand (Get-ChannelTaskLauncherPath official)
    Assert-Test ($command -match '-OfficialOnly' -and $command -notmatch '-WorkerOnly') 'official command scope'
    Assert-Test ($command -notmatch 'dummy-secret|pgnfw_') 'credentials excluded from task'
    $workerBefore=$script:Tasks[$worker] | ConvertTo-Json -Depth 8
    Set-ScheduledReporterPaused -Paused $true -Channel official | Out-Null
    Assert-Test ($script:Tasks[$official].State -eq 'Disabled') 'official pause'
    Assert-Test (($script:Tasks[$worker] | ConvertTo-Json -Depth 8) -eq $workerBefore) 'official pause keeps worker task'
    Assert-Test ($script:Tasks[(Get-NetworkReporterTaskName official)].State -eq 'Disabled') 'official watcher pause'
    Set-ScheduledReporterPaused -Paused $false -Channel official | Out-Null
    $script:Calls.Clear()
    Sync-ScheduledReporterTasks -Mode refresh | Out-Null
    Assert-Test ($script:Calls.Count -eq 0) 'current tasks must not refresh'
    Remove-ScheduledReporter -Channel worker
    Assert-Test (-not $script:Tasks.ContainsKey($worker) -and $script:Tasks.ContainsKey($official)) 'scoped removal'
    Assert-Test (-not $script:Tasks.ContainsKey((Get-NetworkReporterTaskName worker))) 'watcher removed with channel'
    Sync-ScheduledReporterTasks -Mode refresh | Out-Null
    Assert-Test (-not $script:Tasks.ContainsKey($worker)) 'refresh cannot recreate removed channel'
    $script:Tasks.Clear()
    $script:Tasks[$script:TaskName]=[pscustomobject]@{TaskName=$script:TaskName;Actions=@();Triggers=@();State='Ready';Settings=$null;Principal=$null}
    Sync-ScheduledReporterTasks -Mode refresh | Out-Null
    Assert-Test (-not $script:Tasks.ContainsKey($script:TaskName) -and $script:Tasks.ContainsKey($worker) -and $script:Tasks.ContainsKey($official)) 'shared task migration'
    $script:OfficialTimerEnabled=$false
    Sync-ScheduledReporterTasks -Mode refresh -Channel official | Out-Null
    Assert-Test ($script:Tasks[$official].State -eq 'Disabled' -and $script:Tasks[(Get-NetworkReporterTaskName official)].State -ne 'Disabled') 'timer disabled independently of network event'
    $script:OfficialTimerEnabled=$true
    $script:TaskNotify=$true
    Assert-Test (-not (Test-ScheduledReporterTaskCurrent -Task $script:Tasks[$official] -ScriptPath (Get-DefaultScriptPath) -Channel official)) 'notify drift detected'
    Sync-ScheduledReporterTasks -Mode refresh | Out-Null
    Assert-Test ((Get-ScheduledReporterLauncherCommand (Get-ChannelTaskLauncherPath official)) -match '-Notify') 'notify refreshed in scoped launcher'
    $script:Tasks.Clear()
    $script:Tasks[$script:TaskName]=[pscustomobject]@{TaskName=$script:TaskName;Actions=@();Triggers=@();State='Disabled';Settings=$null;Principal=$null}
    Sync-ScheduledReporterTasks -Mode refresh | Out-Null
    Assert-Test ($script:Tasks[$worker].State -eq 'Disabled' -and $script:Tasks[$official].State -eq 'Disabled') 'legacy pause preserved'
    # A removed timer can leave an orphan watcher; channel deletion still cleans it.
    $script:Tasks.Remove($worker)
    Remove-ScheduledReporter -Channel worker
    Assert-Test (-not $script:Tasks.ContainsKey((Get-NetworkReporterTaskName worker))) 'orphan watcher removal'
    $script:Tasks.Clear(); $script:SchedulePaused=$false
    $script:Tasks[$script:TaskName]=[pscustomobject]@{TaskName=$script:TaskName;Actions=@();Triggers=@();State='Ready';Settings=$null;Principal=$null}
    $script:FailTaskName=$official
    $failed=$false
    try { Sync-ScheduledReporterTasks -Mode refresh | Out-Null } catch { $failed=$true }
    Assert-Test ($failed -and $script:Tasks.ContainsKey($script:TaskName) -and -not $script:Tasks.ContainsKey($worker) -and -not $script:Tasks.ContainsKey($official)) 'failed migration preserves legacy and rolls back replacements'
    $script:FailTaskName=''
    # The periodic editor preserves a disabled channel's interval without installing tasks.
    $script:Tasks.Clear(); $script:Calls.Clear()
    function Read-YesNoDefault { param($Prompt,$Default) return $false }
    function Read-Default { param($Prompt,$Default) return $Default }
    $script:Minutes=90; $script:OfficialIntervalSeconds=900
    $script:WorkerTimerEnabled=$true; $script:OfficialTimerEnabled=$true
    Set-ChannelPeriodicInteractive official
    Assert-Test (-not $script:OfficialTimerEnabled -and $script:OfficialIntervalSeconds -eq 900 -and $script:Minutes -eq 90 -and $script:WorkerTimerEnabled) 'periodic editor preserves other channel and stored interval'
    Assert-Test ((Get-ChannelIntervalLabel official) -match '暂不使用') 'disabled periodic interval label'
    Set-ChannelPeriodicInteractive worker
    Assert-Test (-not $script:WorkerTimerEnabled -and $script:Minutes -eq 90 -and $script:OfficialIntervalSeconds -eq 900) 'Worker periodic editor keeps official interval'
    Assert-Test ($script:Tasks.Count -eq 0 -and $script:Calls.Count -eq 0) 'saving periodic settings must not install tasks'
    $script:Po0FirewallScheduledRun=$true; $TimerTrigger=$false; $NetworkChanged=$false
    function Get-Po0FirewallLastAttempt { return 1000 }
    function Get-Po0FirewallNow { return 1600 }
    $script:OfficialIntervalSeconds=900
    Assert-Test (-not (Test-Po0FirewallDue)) 'legacy due respects custom interval'
    $NetworkChanged=$true
    Assert-Test (Test-Po0FirewallDue) 'network event immediately checks'
    $NetworkChanged=$false; $TimerTrigger=$true
    Assert-Test (Test-Po0FirewallDue) 'independent system timer is not suppressed by a recent network report'
    Write-Host 'PASS: Windows independent timers, network watchers, pause/remove/migration and refresh'
} finally {
    $resolved=[IO.Path]::GetFullPath($testRoot)
    if (-not $resolved.StartsWith([IO.Path]::GetFullPath((Join-Path $repo '.tmp/po0-windows-channel-schedules-')),[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test cleanup path' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
