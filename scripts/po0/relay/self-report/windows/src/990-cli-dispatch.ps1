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
        -not $InstallTask -and
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

    Load-SavedConfig
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
    } elseif ($PauseSchedule) {
        Set-ScheduledReporterPaused -Paused $true
    } elseif ($ResumeSchedule) {
        Set-ScheduledReporterPaused -Paused $false
    } elseif ($ScheduleStatus) {
        Show-ScheduledReporter
    } elseif ($RunOnce) {
        Invoke-SelfReport
    } elseif ($Menu -or (-not $PSBoundParameters.ContainsKey("WorkerUrl") -and -not $InstallTask -and -not $RunOnce -and [Environment]::UserInteractive)) {
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
