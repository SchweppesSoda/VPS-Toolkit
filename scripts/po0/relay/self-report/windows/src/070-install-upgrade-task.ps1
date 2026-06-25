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
        }
    }
    foreach ($action in $Task.Actions) {
        $args = [string]$action.Arguments
        if ($args -match '(?i)(powershell(\.exe)?|pwsh(\.exe)?|-File\s+)') {
            $commandTexts.Add($args)
        }
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

function Update-ScheduledReporterLauncherForExistingTask {
    $task = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
    if (-not $task) { return $false }
    $launcher = Get-ScheduledReporterLauncherPath -Task $task
    if (-not $launcher) {
        Install-ScheduledReporter
        return $true
    }
    Write-ScheduledReporterTaskLauncher -LauncherPath $launcher -ScriptPath (Get-DefaultScriptPath) | Out-Null
    return $true
}

function Test-DownloadedScript {
    param([string]$Path)
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ($raw -notmatch 'po0-outbound-ip-report\.ps1' -or $raw -notmatch 'PO0 自上报客户端（Windows PowerShell）') {
        throw "更新文件校验失败：下载到的脚本不是 Self-report Windows PowerShell 客户端。"
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
    $tmp = Join-Path $dir (".po0-self-report.{0}.tmp" -f $PID)
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $DownloadUrl -OutFile $tmp -TimeoutSec 120
        Test-DownloadedScript -Path $tmp
        $newVersion = Get-ScriptFileVersion -Path $tmp
        $newChangelog = Get-ScriptFileChangelog -Path $tmp
        Move-Item -LiteralPath $tmp -Destination $dest -Force
        Write-Host "已更新 Self-report 客户端脚本：$dest"
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
        if ($ReopenMenu) {
            Read-Host "更新完成。按回车打开新版菜单" | Out-Null
            Write-Host "正在重新打开新版菜单：$dest -Menu"
            & powershell -NoProfile -ExecutionPolicy Bypass -File $dest -ConfigPath $script:ConfigPath -Menu
            exit $LASTEXITCODE
        }
    } finally {
        if (Test-Path -LiteralPath $tmp) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
}

function Install-ScheduledReporter {
    Assert-WorkerUrl
    Assert-Minutes
    $dir = Get-DefaultDataDir
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $dest = Get-DefaultScriptPath
    $script:LogPath = Get-DefaultLogPath
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
    $description = "探测当前 Windows 公网出口 IPv4，并上报到 LAN Worker。"
    Register-ScheduledTask -TaskName $script:TaskName -Action $action -Trigger $trigger -Description $description -Force | Out-Null
    if ($script:SchedulePaused) {
        Disable-ScheduledTask -TaskName $script:TaskName | Out-Null
    } else {
        Enable-ScheduledTask -TaskName $script:TaskName | Out-Null
    }
    Write-Host ("已安装计划任务：{0}，每 {1} 秒执行一次。" -f $script:TaskName, (Get-IntervalSeconds))
    Write-Host "脚本路径：$dest"
    Write-Host "隐藏启动器：$launcher"
    Write-Host "配置文件：$script:ConfigPath"
    Write-Host "运行日志：$script:LogPath"
    Write-Host "Windows 通知：$(Format-NotifyStatus)"
    if ($script:SchedulePaused) {
        Write-SelfReportCompleted "计划任务已安装 / 更新，但当前保持暂停。"
    } else {
        Write-SelfReportCompleted "计划任务已安装 / 更新：$script:TaskName；间隔：$(Get-IntervalSeconds) 秒；通知：$(Format-NotifyStatus)；脚本路径：$dest；日志路径：$script:LogPath。"
    }
}
