if ($env:INSTALL_TASK -match "^(1|true|yes)$") {
    $InstallTask = $true
}

if ($env:PO0_OUTBOUND_IP_REPORT_MENU -match "^(1|true|yes)$" -or $env:PO0_SELF_REPORT_MENU -match "^(1|true|yes)$") {
    $Menu = $true
}

if ($env:PO0_OUTBOUND_IP_REPORT_ALLOW_HTTP -match "^(1|true|yes)$" -or $env:PO0_SELF_REPORT_ALLOW_HTTP -match "^(1|true|yes)$") {
    $script:AllowHttp = $true
}

$legacyPathShouldOpenMenu = [bool](
    $Menu -or (
        -not $Version -and
        -not $Changelog -and
        -not $Help -and
        -not $UpgradeSelf -and
        -not $SaveConfig -and
        -not $PauseSchedule -and
        -not $ResumeSchedule -and
        -not $ScheduleStatus -and
        -not $RunOnce -and
        -not $OfficialStatus -and
        -not $OfficialOnly -and
        -not $WorkerOnly -and
        -not $InstallTask -and
        -not $RemoveTask -and
        -not $RefreshSchedules -and
        -not $WatchNetwork -and
        -not ($PSBoundParameters.ContainsKey("WorkerUrl")) -and
        [Environment]::UserInteractive
    )
)
Invoke-LegacyPathSelfHeal -ReopenMenu:$legacyPathShouldOpenMenu | Out-Null

if ($Version) {
    Show-ScriptVersion
    exit 0
}

if ($Changelog) {
    Show-ScriptChangelog
    exit 0
}

if ($Help) {
    Show-Usage
    exit 0
}

if ($UpgradeSelf) {
    try {
        if ($Notify -and $NoNotify) {
            throw "-Notify 与 -NoNotify 不能同时使用。"
        }
        Load-SavedConfig
        if ($Notify) {
            $script:TaskNotify = $true
            $script:Notify = $true
        } elseif ($NoNotify) {
            $script:TaskNotify = $false
            $script:Notify = $false
        }
        Upgrade-SelfFromDownload
        exit 0
    } catch {
        Write-SelfReportIncomplete $_.Exception.Message
        Show-WindowsSelfReportNotification -Title "PO0 Outbound IP Report 未完成" -Message $_.Exception.Message -Kind "Error"
        exit 1
    }
}

try {
    if ($Notify -and $NoNotify) {
        throw "-Notify 与 -NoNotify 不能同时使用。"
    }

    if (-not $ScheduledRun -and -not $NetworkChanged -and -not $WatchNetwork) {
        $legacySettings = Get-LegacyReporterRecord
        if ($legacySettings.Task) { Import-ScheduledReporterTaskSettings -Task $legacySettings.Task -KeepNotifyPreference }
    }
    Load-SavedConfig
    if ($ClearPo0FirewallTokens) {
        $script:Po0FirewallTokens = ""
    }
    if ($OfficialStatus -and ($OfficialOnly -or $WorkerOnly)) {
        throw "-OfficialStatus 不能与 -OfficialOnly / -WorkerOnly 同时使用。"
    }
    if ($Notify) {
        $script:TaskNotify = $true
        $script:Notify = $true
    } elseif ($NoNotify) {
        $script:TaskNotify = $false
        $script:Notify = $false
    }
    Apply-IntervalSeconds

    if ($SaveConfig) {
        Save-ClientConfig
    } elseif ($WatchNetwork) {
        Watch-ReporterNetwork
    } elseif ($RefreshSchedules) {
        Update-ScheduledReporterLauncherForExistingTask | Out-Null
    } elseif ($RemoveTask) {
        Remove-ScheduledReporter
    } elseif ($PauseSchedule) {
        Set-ScheduledReporterPaused -Paused $true
    } elseif ($ResumeSchedule) {
        Set-ScheduledReporterPaused -Paused $false
    } elseif ($ScheduleStatus) {
        Show-ScheduledReporter
    } elseif ($OfficialStatus -or $OfficialOnly -or $WorkerOnly -or $RunOnce) {
        Invoke-SelfReport
    } elseif ($Menu -or (-not $PSBoundParameters.ContainsKey("WorkerUrl") -and -not $InstallTask -and -not $RunOnce -and -not $OfficialStatus -and -not $OfficialOnly -and -not $WorkerOnly -and [Environment]::UserInteractive)) {
        Invoke-InteractiveMenu
    } elseif ($InstallTask) {
        Install-ScheduledReporter
    } else {
        Invoke-SelfReport
    }
} catch {
    Write-SelfReportIncomplete $_.Exception.Message
    Show-WindowsSelfReportNotification -Title "PO0 Outbound IP Report 未完成" -Message $_.Exception.Message -Kind "Error"
    exit 1
}
