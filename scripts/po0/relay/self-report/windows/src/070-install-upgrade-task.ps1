function Quote-TaskArg {
    param([string]$Value)
    if ($null -eq $Value) { return '""' }
    return '"' + ($Value -replace '"', '\"') + '"'
}

function ConvertTo-VbsStringLiteral {
    param([string]$Value)
    if ($null -eq $Value) { $Value = "" }
    return '"' + ($Value -replace '"', '""') + '"'
}

function Test-CommandLineSwitchPresent {
    param(
        [string]$CommandLine,
        [string]$SwitchName
    )
    if (-not $CommandLine -or -not $SwitchName) { return $false }
    $pattern = '(?i)(^|\s)-' + [regex]::Escape($SwitchName) + '($|\s)'
    return [regex]::IsMatch($CommandLine, $pattern)
}

function Get-CommandLineFileArgument {
    param([string]$CommandLine)
    if (-not $CommandLine) { return "" }
    if ($CommandLine -match '(?i)(^|\s)-File\s+"([^"]+)"') {
        return $matches[2]
    }
    if ($CommandLine -match '(?i)(^|\s)-File\s+(\S+)') {
        return $matches[2].Trim('"')
    }
    return ""
}

function Get-CommandLineSwitchArgument {
    param(
        [string]$CommandLine,
        [string]$SwitchName
    )
    if (-not $CommandLine -or -not $SwitchName) { return "" }
    $escaped = [regex]::Escape($SwitchName)
    $quoted = [regex]::Match($CommandLine, '(?i)(^|\s)-' + $escaped + '\s+"([^"]*)"')
    if ($quoted.Success) {
        return $quoted.Groups[2].Value
    }
    $plain = [regex]::Match($CommandLine, '(?i)(^|\s)-' + $escaped + '\s+(\S+)')
    if ($plain.Success) {
        return $plain.Groups[2].Value.Trim('"')
    }
    return ""
}

function Ensure-DefaultSelfReportScriptInstalled {
    $dest = Get-DefaultScriptPath
    if (Test-Path -LiteralPath $dest) { return $dest }

    $dir = Split-Path -Parent $dest
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath)) {
        Copy-Item -LiteralPath $PSCommandPath -Destination $dest -Force
        return $dest
    }

    $legacy = Get-LegacyScriptPath
    if ($legacy -and (Test-Path -LiteralPath $legacy)) {
        Copy-Item -LiteralPath $legacy -Destination $dest -Force
        return $dest
    }

    throw "找不到默认安装脚本：$dest。请先运行 -InstallTask 或 -UpgradeSelf。"
}

function Get-ScheduledReporterTaskArgumentList {
    param([string]$ScriptPath)
    $taskArgList = @(
        "-NoProfile",
        "-Sta",
        "-WindowStyle", "Hidden",
        "-NonInteractive",
        "-ExecutionPolicy", "Bypass",
        "-File", (Quote-TaskArg $ScriptPath),
        "-ConfigPath", (Quote-TaskArg $script:ConfigPath),
        "-LogPath", (Quote-TaskArg $script:LogPath),
        "-RunOnce"
    )
    if ($script:TaskNotify) {
        $taskArgList += "-Notify"
    } else {
        $taskArgList += "-NoNotify"
    }
    return $taskArgList
}

function Get-ScheduledReporterTaskCommand {
    param([string]$ScriptPath)
    return ("powershell.exe " + ((Get-ScheduledReporterTaskArgumentList -ScriptPath $ScriptPath) -join " "))
}

function Write-ScheduledReporterTaskLauncher {
    param(
        [string]$LauncherPath = $(Get-DefaultTaskLauncherPath),
        [string]$ScriptPath = $(Get-DefaultScriptPath)
    )
    $launcherDir = Split-Path -Parent $LauncherPath
    if ($launcherDir -and -not (Test-Path -LiteralPath $launcherDir)) {
        New-Item -ItemType Directory -Path $launcherDir -Force | Out-Null
    }
    $command = Get-ScheduledReporterTaskCommand -ScriptPath $ScriptPath
    $launcherContent = @(
        "Option Explicit",
        "Dim shell, command",
        "command = $(ConvertTo-VbsStringLiteral $command)",
        "Set shell = CreateObject(""WScript.Shell"")",
        "WScript.Quit shell.Run(command, 0, True)"
    )
    Set-Content -LiteralPath $LauncherPath -Encoding Unicode -Value $launcherContent
    return $LauncherPath
}

function Get-ScheduledReporterLauncherPath {
    param($Task)
    if (-not $Task) { return "" }
    foreach ($action in $Task.Actions) {
        $args = [string]$action.Arguments
        if ($args -match '(?i)"([^"]+\.vbs)"') {
            return $matches[1]
        }
        if ($args -match '(?i)(\S+\.vbs)') {
            return $matches[1].Trim('"')
        }
    }
    return ""
}

function Get-ScheduledReporterLauncherCommand {
    param([string]$LauncherPath)
    if (-not $LauncherPath -or -not (Test-Path -LiteralPath $LauncherPath)) { return "" }
    $launcherRaw = Get-Content -LiteralPath $LauncherPath -Raw
    $match = [regex]::Match($launcherRaw, '(?im)^\s*command\s*=\s*"((?:[^"]|"")*)"')
    if ($match.Success) {
        return ($match.Groups[1].Value -replace '""', '"')
    }
    return $launcherRaw
}

function Get-ScheduledReporterNotifyState {
    param($Task)
    $state = [pscustomobject]@{
        Installed = [bool]$Task
        LauncherPath = ""
        LauncherExists = $false
        ScriptPath = ""
        ScriptPathExists = $false
        ScriptPathIsLegacy = $false
        ActualNotify = $null
        HasNotify = $false
        HasNoNotify = $false
        IsUnknown = $true
    }
    if (-not $Task) {
        return $state
    }

    $commandTexts = New-Object System.Collections.Generic.List[string]
    $launcher = Get-ScheduledReporterLauncherPath -Task $Task
    if ($launcher) {
        $state.LauncherPath = $launcher
        $state.LauncherExists = Test-Path -LiteralPath $launcher
        $launcherCommand = Get-ScheduledReporterLauncherCommand -LauncherPath $launcher
        if ($launcherCommand) {
            $commandTexts.Add($launcherCommand)
            $scriptPath = Get-CommandLineFileArgument -CommandLine $launcherCommand
            if ($scriptPath -and -not $state.ScriptPath) {
                $state.ScriptPath = $scriptPath
            }
        }
    }
    foreach ($action in $Task.Actions) {
        $args = [string]$action.Arguments
        if ($args -match '(?i)(powershell(\.exe)?|pwsh(\.exe)?|-File\s+)') {
            $commandTexts.Add($args)
            $scriptPath = Get-CommandLineFileArgument -CommandLine $args
            if ($scriptPath -and -not $state.ScriptPath) {
                $state.ScriptPath = $scriptPath
            }
        }
    }

    if ($state.ScriptPath) {
        $state.ScriptPathExists = Test-Path -LiteralPath $state.ScriptPath
        $state.ScriptPathIsLegacy = Test-LegacySelfReportScriptPath -Path $state.ScriptPath
    }

    if ($commandTexts.Count -gt 0) {
        foreach ($commandText in $commandTexts) {
            if (Test-CommandLineSwitchPresent -CommandLine $commandText -SwitchName "Notify") {
                $state.HasNotify = $true
            }
            if (Test-CommandLineSwitchPresent -CommandLine $commandText -SwitchName "NoNotify") {
                $state.HasNoNotify = $true
            }
        }
        $state.IsUnknown = $false
        $state.ActualNotify = [bool]($state.HasNotify -and -not $state.HasNoNotify)
    }
    return $state
}

function Get-ScheduledReporterTaskRecord {
    try {
        $task = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
        if ($task) {
            return [pscustomobject]@{ Task = $task; Name = $script:TaskName; IsLegacy = $false }
        }
        foreach ($legacyName in $script:LegacyTaskNames) {
            $legacyTask = Get-ScheduledTask -TaskName $legacyName -ErrorAction SilentlyContinue
            if ($legacyTask) {
                return [pscustomobject]@{ Task = $legacyTask; Name = $legacyName; IsLegacy = $true }
            }
        }
    } catch {}
    return [pscustomobject]@{ Task = $null; Name = ""; IsLegacy = $false }
}

function Format-LegacyScheduledReporterTaskNames {
    return ($script:LegacyTaskNames -join ", ")
}

function Test-ScheduledReporterTaskCurrent {
    param(
        $Task,
        [string]$ScriptPath = $(Get-DefaultScriptPath)
    )
    if (-not $Task) { return $false }
    $launcher = Get-ScheduledReporterLauncherPath -Task $Task
    if (-not (Test-SamePath $launcher (Get-DefaultTaskLauncherPath))) { return $false }
    if (-not (Test-Path -LiteralPath $launcher)) { return $false }
    $launcherCommand = Get-ScheduledReporterLauncherCommand -LauncherPath $launcher
    if (-not $launcherCommand) { return $false }
    $expectedCommand = Get-ScheduledReporterTaskCommand -ScriptPath $ScriptPath
    if (-not [System.String]::Equals($launcherCommand, $expectedCommand, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }
    $notifyState = Get-ScheduledReporterNotifyState -Task $Task
    if ($notifyState.ScriptPathIsLegacy) { return $false }
    if (-not (Test-SamePath $notifyState.ScriptPath $ScriptPath)) { return $false }
    if ($notifyState.IsUnknown) { return $false }
    if ([bool]$notifyState.ActualNotify -ne [bool]$script:TaskNotify) { return $false }
    return $true
}

function Normalize-DefaultConfigPath {
    if (-not $script:ConfigPath -or $script:ConfigPathExplicit) { return }
    try {
        $current = [System.IO.Path]::GetFullPath($script:ConfigPath)
        $legacy = [System.IO.Path]::GetFullPath((Get-LegacyConfigPath))
        if ([System.String]::Equals($current, $legacy, [System.StringComparison]::OrdinalIgnoreCase)) {
            $script:ConfigPath = ""
            $script:ConfigPath = Get-DefaultConfigPath
        }
    } catch {}
}

function Import-ScheduledReporterTaskSettings {
    param(
        $Task,
        [switch]$KeepNotifyPreference
    )
    if (-not $Task) { return }
    $commandTexts = New-Object System.Collections.Generic.List[string]
    $oldLauncher = Get-ScheduledReporterLauncherPath -Task $Task
    if ($oldLauncher) {
        $oldLauncherCommand = Get-ScheduledReporterLauncherCommand -LauncherPath $oldLauncher
        if ($oldLauncherCommand) {
            $commandTexts.Add($oldLauncherCommand)
        }
    }
    foreach ($action in $Task.Actions) {
        $args = [string]$action.Arguments
        if ($args) {
            $commandTexts.Add($args)
        }
    }
    foreach ($commandText in $commandTexts) {
        $existingConfig = Get-CommandLineSwitchArgument -CommandLine $commandText -SwitchName "ConfigPath"
        if ($existingConfig -and -not $script:ConfigPathExplicit) {
            $script:ConfigPath = $existingConfig
            Normalize-DefaultConfigPath
        }
        $existingLog = Get-CommandLineSwitchArgument -CommandLine $commandText -SwitchName "LogPath"
        if ($existingLog -and -not $script:LogPathExplicit) {
            $script:LogPath = $existingLog
            Normalize-DefaultLogPath
        }
        if (-not $KeepNotifyPreference) {
            if (Test-CommandLineSwitchPresent -CommandLine $commandText -SwitchName "Notify") {
                $script:TaskNotify = $true
            }
            if (Test-CommandLineSwitchPresent -CommandLine $commandText -SwitchName "NoNotify") {
                $script:TaskNotify = $false
            }
        }
    }
    if ($Task.State -eq "Disabled") {
        $script:SchedulePaused = $true
    }
}

function Remove-LegacyScheduledReporterTask {
    param([switch]$Quiet)
    $ok = $true
    try {
        foreach ($legacyName in $script:LegacyTaskNames) {
            $legacyTask = Get-ScheduledTask -TaskName $legacyName -ErrorAction SilentlyContinue
            if (-not $legacyTask) { continue }
            try {
                Unregister-ScheduledTask -TaskName $legacyName -Confirm:$false -ErrorAction Stop
                if (-not $Quiet) { Write-Host "已删除旧计划任务：$legacyName" }
            } catch {
                try {
                    Disable-ScheduledTask -TaskName $legacyName -ErrorAction SilentlyContinue | Out-Null
                } catch {}
                if (-not $Quiet) {
                    Write-Host "删除旧计划任务失败，已尝试禁用旧任务以避免双重上报：$legacyName：$($_.Exception.Message)" -ForegroundColor Yellow
                }
                $ok = $false
            }
        }
        return $ok
    } catch {
        if (-not $Quiet) {
            Write-Host "删除旧计划任务失败：$($_.Exception.Message)" -ForegroundColor Yellow
        }
        return $false
    }
}

function Update-ScheduledReporterLauncherForExistingTask {
    $record = Get-ScheduledReporterTaskRecord
    $task = $record.Task
    if (-not $task) { return "none" }
    $scriptPath = Ensure-DefaultSelfReportScriptInstalled
    Import-ScheduledReporterTaskSettings -Task $task -KeepNotifyPreference
    Cleanup-LegacySelfReportArtifacts -Quiet | Out-Null
    if (-not $script:LogPath) {
        $script:LogPath = Get-DefaultLogPath
    }
    if (-not $record.IsLegacy -and (Test-ScheduledReporterTaskCurrent -Task $task -ScriptPath $scriptPath)) {
        return "current"
    }
    $launcher = Get-DefaultTaskLauncherPath
    Write-ScheduledReporterTaskLauncher -LauncherPath $launcher -ScriptPath $scriptPath | Out-Null
    $action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument ("//B //Nologo " + (Quote-TaskArg $launcher))
    if ($record.IsLegacy) {
        $description = "Report outbound IPv4."
        $registerParams = @{
            TaskName = $script:TaskName
            Action = $action
            Trigger = $task.Triggers
            Description = $description
            Force = $true
        }
        if ($task.Settings) { $registerParams.Settings = $task.Settings }
        if ($task.Principal) { $registerParams.Principal = $task.Principal }
        Register-ScheduledTask @registerParams | Out-Null
        if ($script:SchedulePaused) {
            Disable-ScheduledTask -TaskName $script:TaskName | Out-Null
        } else {
            Enable-ScheduledTask -TaskName $script:TaskName | Out-Null
        }
        if (-not (Remove-LegacyScheduledReporterTask)) {
            throw "旧计划任务删除失败，已尝试禁用旧任务；请检查计划任务：$(Format-LegacyScheduledReporterTaskNames)"
        }
        return "migrated"
    } else {
        Set-ScheduledTask -TaskName $script:TaskName -Action $action | Out-Null
        return "refreshed"
    }
}

function Write-ScheduledReporterRefreshResult {
    param(
        [string]$Result,
        [string]$ScriptPath
    )
    switch ($Result) {
        "current" { Write-Host "计划任务已指向标准脚本路径，未刷新：$ScriptPath" }
        "refreshed" { Write-Host "已刷新计划任务启动文件和脚本路径：$ScriptPath" }
        "migrated" { Write-Host "已迁移旧计划任务并指向标准脚本路径：$ScriptPath" }
        default {}
    }
}

function Test-SamePath {
    param(
        [string]$Left,
        [string]$Right
    )
    if (-not $Left -or -not $Right) { return $false }
    try {
        $leftFull = [System.IO.Path]::GetFullPath($Left)
        $rightFull = [System.IO.Path]::GetFullPath($Right)
        return [System.String]::Equals($leftFull, $rightFull, [System.StringComparison]::OrdinalIgnoreCase)
    } catch {
        return [System.String]::Equals($Left, $Right, [System.StringComparison]::OrdinalIgnoreCase)
    }
}

function Move-DefaultLegacyFileToCanonical {
    param(
        [string]$Label,
        [string]$LegacyPath,
        [string]$CanonicalPath,
        [switch]$Quiet
    )
    if (-not $LegacyPath -or -not $CanonicalPath -or (Test-SamePath $LegacyPath $CanonicalPath)) { return $true }
    if (-not (Test-Path -LiteralPath $LegacyPath)) { return $true }
    try {
        $dir = Split-Path -Parent $CanonicalPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        if (-not (Test-Path -LiteralPath $CanonicalPath)) {
            Move-Item -LiteralPath $LegacyPath -Destination $CanonicalPath -Force
            if (-not $Quiet) { Write-Host "已迁移${Label}：$LegacyPath -> $CanonicalPath" }
        } else {
            Remove-Item -LiteralPath $LegacyPath -Force
            if (-not $Quiet) { Write-Host "已删除旧${Label}：$LegacyPath" }
        }
        return $true
    } catch {
        if (-not $Quiet) { Write-Host "迁移/删除旧${Label}失败：$LegacyPath：$($_.Exception.Message)" -ForegroundColor Yellow }
        return $false
    }
}

function Merge-DefaultLegacyLogToCanonical {
    param([switch]$Quiet)
    $legacyPath = Get-LegacyLogPath
    $canonicalPath = Get-DefaultLogPath
    if ($script:LogPathExplicit -or (Test-SamePath $legacyPath $canonicalPath)) { return $true }
    if (-not (Test-Path -LiteralPath $legacyPath)) { return $true }
    try {
        $dir = Split-Path -Parent $canonicalPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        if (-not (Test-Path -LiteralPath $canonicalPath)) {
            Move-Item -LiteralPath $legacyPath -Destination $canonicalPath -Force
        } else {
            $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"
            Add-Content -LiteralPath $canonicalPath -Encoding UTF8 -Value ""
            Add-Content -LiteralPath $canonicalPath -Encoding UTF8 -Value "# migrated from $legacyPath at $stamp"
            Get-Content -LiteralPath $legacyPath -Encoding UTF8 | Add-Content -LiteralPath $canonicalPath -Encoding UTF8
            Remove-Item -LiteralPath $legacyPath -Force
        }
        if (-not $Quiet) { Write-Host "已迁移旧日志：$legacyPath -> $canonicalPath" }
        return $true
    } catch {
        if (-not $Quiet) { Write-Host "迁移/删除旧日志失败：$legacyPath：$($_.Exception.Message)" -ForegroundColor Yellow }
        return $false
    }
}

function Remove-DefaultLegacyPath {
    param(
        [string]$Label,
        [string]$Path,
        [string]$CanonicalPath = "",
        [switch]$Quiet
    )
    if (-not $Path -or (Test-SamePath $Path $CanonicalPath)) { return $true }
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    try {
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (-not $Quiet) { Write-Host "已删除旧${Label}：$Path" }
        return $true
    } catch {
        if (-not $Quiet) { Write-Host "删除旧${Label}失败：$Path：$($_.Exception.Message)" -ForegroundColor Yellow }
        return $false
    }
}

function Cleanup-LegacySelfReportArtifacts {
    param([switch]$Quiet)
    $ok = $true
    if (-not $script:ConfigPathExplicit) {
        if (-not (Move-DefaultLegacyFileToCanonical -Label "配置文件" -LegacyPath (Get-LegacyConfigPath) -CanonicalPath (Get-DefaultConfigPath) -Quiet:$Quiet)) { $ok = $false }
    }
    if (-not (Merge-DefaultLegacyLogToCanonical -Quiet:$Quiet)) { $ok = $false }
    if (-not (Move-DefaultLegacyFileToCanonical -Label "IP 探测状态" -LegacyPath (Get-LegacyIpCheckStatePath) -CanonicalPath (Get-IpCheckStatePath) -Quiet:$Quiet)) { $ok = $false }

    $legacyTaskStillExists = $false
    try {
        $newTask = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
        if ($newTask) {
            if (-not (Remove-LegacyScheduledReporterTask -Quiet:$Quiet)) { $ok = $false }
        }
        foreach ($legacyName in $script:LegacyTaskNames) {
            if (Get-ScheduledTask -TaskName $legacyName -ErrorAction SilentlyContinue) {
                $legacyTaskStillExists = $true
                break
            }
        }
    } catch {}

    if (-not $legacyTaskStillExists) {
        foreach ($legacyLauncherPath in (Get-LegacyTaskLauncherPaths)) {
            if (-not (Remove-DefaultLegacyPath -Label "计划任务启动文件" -Path $legacyLauncherPath -CanonicalPath (Get-DefaultTaskLauncherPath) -Quiet:$Quiet)) { $ok = $false }
        }
        if (-not (Remove-DefaultLegacyPath -Label "本机脚本" -Path (Get-LegacyScriptPath) -CanonicalPath (Get-DefaultScriptPath) -Quiet:$Quiet)) { $ok = $false }
    } elseif (-not $Quiet) {
        Write-Host "旧计划任务仍存在，暂不删除旧脚本/启动器，避免破坏仍在使用的任务。" -ForegroundColor Yellow
    }
    return $ok
}

function Invoke-CanonicalSelfReportMenu {
    param([string]$ScriptPath)
    $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $ScriptPath)
    if ($script:ConfigPathExplicit) {
        $args += @("-ConfigPath", $script:ConfigPath)
    }
    $args += "-Menu"
    & powershell @args
}

function Invoke-LegacyPathSelfHeal {
    param([switch]$ReopenMenu)
    if (-not (Test-CurrentScriptPathIsLegacy)) { return $false }
    if (-not $PSCommandPath -or -not (Test-Path -LiteralPath $PSCommandPath)) { return $false }

    $dest = Get-DefaultScriptPath
    $current = [System.IO.Path]::GetFullPath($PSCommandPath)
    $destFull = [System.IO.Path]::GetFullPath($dest)
    if ([System.String]::Equals($current, $destFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    $dir = Split-Path -Parent $dest
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Copy-Item -LiteralPath $PSCommandPath -Destination $dest -Force
    Write-Host "已迁移 Windows PO0 Outbound IP Report 客户端脚本到标准安装路径：$dest"

    try {
        $refreshResult = Update-ScheduledReporterLauncherForExistingTask
        Write-ScheduledReporterRefreshResult -Result $refreshResult -ScriptPath $dest
    } catch {
        Write-Host "刷新计划任务启动文件失败：$($_.Exception.Message)" -ForegroundColor Yellow
    }
    Cleanup-LegacySelfReportArtifacts | Out-Null

    if ($ReopenMenu) {
        Write-Host "正在从标准安装路径重新打开新版菜单：$dest -Menu"
        Invoke-CanonicalSelfReportMenu -ScriptPath $dest
        exit $LASTEXITCODE
    }
    return $true
}

function Test-DownloadedScript {
    param([string]$Path)
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ($raw -notmatch 'po0-outbound-ip-report\.ps1' -or $raw -notmatch 'PO0 自上报客户端（Windows PowerShell）') {
        throw "更新文件校验失败：下载到的脚本不是 Self-report Windows PowerShell 客户端。"
    }
    $scriptName = [regex]::Match($raw, '(?m)^\s*\$ScriptName\s*=\s*"([^"]+)"')
    if (-not $scriptName.Success -or $scriptName.Groups[1].Value -ne "po0-outbound-ip-report") {
        throw "更新文件校验失败：下载脚本未声明标准脚本名称 po0-outbound-ip-report。"
    }
    $defaultScript = [regex]::Match($raw, '(?ms)^function Get-DefaultScriptPath \{.*?^}')
    if (-not $defaultScript.Success -or $defaultScript.Value -notmatch 'po0-outbound-ip-report\.ps1' -or $defaultScript.Value -match 'po0-self-report\.ps1') {
        throw "更新文件校验失败：下载脚本默认安装路径不是 po0-outbound-ip-report.ps1。"
    }
    $defaultLauncher = [regex]::Match($raw, '(?ms)^function Get-DefaultTaskLauncherPath \{.*?^}')
    if (-not $defaultLauncher.Success -or $defaultLauncher.Value -notmatch 'outbound-ip-report-task\.vbs' -or $defaultLauncher.Value -match 'po0-(outbound-ip-report|self-report)-task\.vbs') {
        throw "更新文件校验失败：下载脚本默认计划任务启动文件不是 outbound-ip-report-task.vbs。"
    }
    $defaultConfig = [regex]::Match($raw, '(?ms)^function Get-DefaultConfigPath \{.*?^}')
    if (-not $defaultConfig.Success -or $defaultConfig.Value -notmatch 'outbound-ip-report\.json' -or $defaultConfig.Value -match 'self-report\.json') {
        throw "更新文件校验失败：下载脚本默认配置文件不是 outbound-ip-report.json。"
    }
    $defaultLog = [regex]::Match($raw, '(?ms)^function Get-DefaultLogPath \{.*?^}')
    if (-not $defaultLog.Success -or $defaultLog.Value -notmatch 'po0-outbound-ip-report\.log' -or $defaultLog.Value -match 'po0-self-report\.log') {
        throw "更新文件校验失败：下载脚本默认日志文件不是 po0-outbound-ip-report.log。"
    }
    if ($raw -notmatch '\$script:TaskName = "Outbound IP Report"') {
        throw "更新文件校验失败：下载脚本默认计划任务名不是 Outbound IP Report。"
    }
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors -and $errors.Count -gt 0) {
        throw "更新文件校验失败：下载到的脚本未通过 PowerShell 语法检查：$($errors[0].Message)"
    }
}

function Upgrade-SelfFromDownload {
    param([switch]$ReopenMenu)
    $dest = Get-DefaultScriptPath
    $dir = Split-Path -Parent $dest
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $tmp = Join-Path $dir (".po0-outbound-ip-report.{0}.tmp" -f $PID)
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $DownloadUrl -OutFile $tmp -TimeoutSec 120
        Test-DownloadedScript -Path $tmp
        $newVersion = Get-ScriptFileVersion -Path $tmp
        $newChangelog = Get-ScriptFileChangelog -Path $tmp
        Move-Item -LiteralPath $tmp -Destination $dest -Force
        Write-Host "已更新 PO0 Outbound IP Report 客户端脚本：$dest"
        Write-Host "下载 URL：$DownloadUrl"
        if ($newVersion) {
            if ($newVersion -eq $ScriptVersion) {
                Write-Host "版本：$newVersion（与当前执行脚本相同）"
            } else {
                Write-Host "版本：$ScriptVersion -> $newVersion"
            }
        } else {
            Write-Host "版本：无法读取新脚本版本。"
        }
        if ($newChangelog.Count -gt 0) {
            Write-Host "更新内容："
            $newChangelog | ForEach-Object { Write-Host $_ }
        } else {
            Write-Host "更新内容：新脚本未提供更新说明。"
        }
        try {
            $refreshResult = Update-ScheduledReporterLauncherForExistingTask
            Write-ScheduledReporterRefreshResult -Result $refreshResult -ScriptPath $dest
        } catch {
            Write-Host "刷新计划任务启动文件失败：$($_.Exception.Message)" -ForegroundColor Yellow
        }
        Cleanup-LegacySelfReportArtifacts | Out-Null
        if ($ReopenMenu) {
            Read-Host "更新完成。按回车打开新版菜单" | Out-Null
            Write-Host "正在重新打开新版菜单：$dest -Menu"
            Invoke-CanonicalSelfReportMenu -ScriptPath $dest
            exit $LASTEXITCODE
        }
    } finally {
        if (Test-Path -LiteralPath $tmp) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
}

function Install-ScheduledReporter {
    $existingRecord = Get-ScheduledReporterTaskRecord
    if ($existingRecord.Task) {
        Import-ScheduledReporterTaskSettings -Task $existingRecord.Task
        Load-SavedConfig
    }
    Assert-WorkerUrl
    Assert-Minutes
    $dir = Get-DefaultDataDir
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $dest = Get-DefaultScriptPath
    if (-not $script:LogPath) {
        $script:LogPath = Get-DefaultLogPath
    } else {
        Normalize-DefaultLogPath
        if (-not $script:LogPath) {
            $script:LogPath = Get-DefaultLogPath
        }
    }
    Save-ClientConfig
    if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath)) {
        $sourcePath = [System.IO.Path]::GetFullPath($PSCommandPath)
        $destPath = [System.IO.Path]::GetFullPath($dest)
        if ($sourcePath -ne $destPath) {
            Copy-Item -LiteralPath $PSCommandPath -Destination $dest -Force
        }
    } else {
        Invoke-WebRequest -UseBasicParsing -Uri $DownloadUrl -OutFile $dest -TimeoutSec 120
    }
    $launcher = Get-DefaultTaskLauncherPath
    Write-ScheduledReporterTaskLauncher -LauncherPath $launcher -ScriptPath $dest | Out-Null
    $action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument ("//B //Nologo " + (Quote-TaskArg $launcher))
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $script:Minutes) -RepetitionDuration (New-TimeSpan -Days 3650)
    $description = "Report outbound IPv4."
    $registerParams = @{
        TaskName = $script:TaskName
        Action = $action
        Trigger = $trigger
        Description = $description
        Force = $true
    }
    if ($existingRecord.Task -and $existingRecord.Task.Settings) { $registerParams.Settings = $existingRecord.Task.Settings }
    if ($existingRecord.Task -and $existingRecord.Task.Principal) { $registerParams.Principal = $existingRecord.Task.Principal }
    Register-ScheduledTask @registerParams | Out-Null
    if ($script:SchedulePaused) {
        Disable-ScheduledTask -TaskName $script:TaskName | Out-Null
    } else {
        Enable-ScheduledTask -TaskName $script:TaskName | Out-Null
    }
    if ($existingRecord.IsLegacy) {
        if (-not (Remove-LegacyScheduledReporterTask)) {
            throw "旧计划任务删除失败，已尝试禁用旧任务；请检查计划任务：$(Format-LegacyScheduledReporterTaskNames)"
        }
    }
    Cleanup-LegacySelfReportArtifacts | Out-Null
    Write-Host ("已安装计划任务：{0}，每 {1} 秒执行一次。" -f $script:TaskName, (Get-IntervalSeconds))
    Write-Host "脚本路径：$dest"
    Write-Host "计划任务启动文件：$launcher"
    Write-Host "配置文件：$script:ConfigPath"
    Write-Host "运行日志：$script:LogPath"
    Write-Host "Windows 通知：$(Format-NotifyStatus)"
    if ($script:SchedulePaused) {
        Write-SelfReportCompleted "计划任务已安装 / 更新，但当前保持暂停。"
    } else {
        Write-SelfReportCompleted "计划任务已安装 / 更新：$script:TaskName；间隔：$(Get-IntervalSeconds) 秒；通知：$(Format-NotifyStatus)；脚本路径：$dest；日志路径：$script:LogPath。"
    }
}
