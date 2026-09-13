#Requires -Version 5.1
<#
.SYNOPSIS
Download a 3x-ui export to this computer over a single SSH connection.
.EXAMPLE
./Export-3xUi.ps1 -Server my-vps -OutDir 'D:\Backups\3x-ui'
.EXAMPLE
./Export-3xUi.ps1 -Server root@203.0.113.10 -Port 2222 -OutDir 'D:\Backups\3x-ui'
.NOTES
Uses the adjacent exporter script, sent over SSH without installing it remotely.
SSH config aliases, keys, agents and interactive SSH passwords are supported.
Use -Sudo for a non-root account with passwordless sudo.
#>
[CmdletBinding()]
param(
    [string]$Server,
    [string]$OutDir,
    [ValidateRange(1, 65535)][int]$Port,
    [string]$IdentityFile,
    [string]$Address,
    [string]$Database,
    [switch]$RawOnly,
    [switch]$Sudo,
    [string]$ExporterPath,
    [switch]$Version
)

$ErrorActionPreference = 'Stop'
$ScriptVersion = '1.0.0'
if ($Version) { $ScriptVersion; return }
if (-not $ExporterPath) { $ExporterPath = Join-Path $PSScriptRoot '3x-ui-node-exporter.sh' }

function ConvertTo-ShellArgument([string]$Value) {
    return "'" + $Value.Replace("'", "'\''") + "'"
}

function ConvertTo-WindowsArgument([string]$Value) {
    # CommandLineToArgvW quoting for Windows PowerShell / .NET Framework.
    return '"' + [regex]::Replace(
        [regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1'
    ) + '"'
}

if ([string]::IsNullOrWhiteSpace($Server)) { $Server = Read-Host 'SSH server (alias or root@host)' }
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Read-Host 'Local destination directory' }
if ([string]::IsNullOrWhiteSpace($Server) -or $Server.StartsWith('-') -or $Server -match '[\s\x00-\x1f]') {
    throw 'Invalid SSH server. Use an SSH config alias or user@host.'
}
if ([string]::IsNullOrWhiteSpace($OutDir)) { throw 'A local destination directory is required.' }
if ($env:OS -ne 'Windows_NT') { throw 'This download helper requires Windows PowerShell 5.1 or PowerShell 7 on Windows.' }

$sshPath = (Get-Command ssh.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$sourcePath = (Resolve-Path -LiteralPath $ExporterPath).ProviderPath
$scriptText = [IO.File]::ReadAllText($sourcePath).Replace("`r`n", "`n")
if ($scriptText -notmatch '3XUI_EXPORT_V1') { throw 'The adjacent exporter must be version 1.2.0 or later.' }

$destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutDir)
$null = [IO.Directory]::CreateDirectory($destination)
$destination = (Resolve-Path -LiteralPath $destination).ProviderPath
$name = '3xui-node-export-{0}-{1}.zip' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$finalPath = Join-Path $destination $name
$partialPath = $finalPath + '.partial'

$remoteArgs = @('--stream')
if ($Address) { $remoteArgs += @('--addr', $Address) }
if ($Database) { $remoteArgs += @('--db', $Database) }
if ($RawOnly) { $remoteArgs += '--raw-only' }
# Read the complete script before running it, so stdin can close before the
# archive starts. This avoids duplex pipe deadlocks and preserves failure exits.
$remoteCommand = 'bash -c ' + (ConvertTo-ShellArgument 'script=$(cat) || exit; eval "$script"') + ' -- ' +
    (($remoteArgs | ForEach-Object { ConvertTo-ShellArgument $_ }) -join ' ')
if ($Sudo) { $remoteCommand = 'sudo -n ' + $remoteCommand }
$sshArgs = @('-T', '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=3')
if ($Port) { $sshArgs += @('-p', [string]$Port) }
if ($IdentityFile) { $sshArgs += @('-i', (Resolve-Path -LiteralPath $IdentityFile).ProviderPath) }
$sshArgs += @('--', $Server, $remoteCommand)

$start = New-Object Diagnostics.ProcessStartInfo
$start.FileName = $sshPath
$start.Arguments = ($sshArgs | ForEach-Object { ConvertTo-WindowsArgument $_ }) -join ' '
$start.UseShellExecute = $false
$start.RedirectStandardInput = $true
$start.RedirectStandardOutput = $true
# Inherit stderr and the console so SSH can show host-key/password prompts.
$start.StandardOutputEncoding = [Text.Encoding]::ASCII
$process = New-Object Diagnostics.Process
$process.StartInfo = $start
$file = $null
$stdin = $null
$started = $false
$ownsPartial = $false

try {
    $file = [IO.File]::Open($partialPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $ownsPartial = $true
    Write-Host "Connecting to $Server; exporting and downloading..."
    try { $started = $process.Start() }
    catch { throw "Could not start SSH at ${sshPath}: $($_.Exception.Message)" }
    if (-not $started) { throw 'Could not start SSH.' }
    # .NET Framework lacks ProcessStartInfo.StandardInputEncoding.
    $stdin = New-Object IO.StreamWriter($process.StandardInput.BaseStream, (New-Object Text.UTF8Encoding($false)))
    $stdin.Write($scriptText + "`n")
    $stdin.Close()
    $header = $process.StandardOutput.ReadLine()
    if ($null -eq $header -or $header -notmatch '^3XUI_EXPORT_V1 ([1-9][0-9]*) ([a-f0-9]{64})$') {
        throw 'No valid export received. Check the SSH error above, root/sudo access, and remote dependencies.'
    }
    $expectedSize = [long]$Matches[1]
    $expectedHash = $Matches[2]
    $received = 0L
    $complete = $false
    while ($null -ne ($line = $process.StandardOutput.ReadLine())) {
        if ($line -eq '3XUI_EXPORT_DONE') { $complete = $true; break }
        if ($line.Length -gt 65536 -or $line -notmatch '^[A-Za-z0-9+/]+={0,2}$') {
            throw 'Invalid export data received.'
        }
        $bytes = [Convert]::FromBase64String($line)
        $received += $bytes.Length
        if ($received -gt $expectedSize) { throw 'Export is larger than the declared size.' }
        $file.Write($bytes, 0, $bytes.Length)
    }
    if ($complete -and $null -ne $process.StandardOutput.ReadLine()) { throw 'Unexpected data after the export.' }
    $process.WaitForExit()
    if ($process.ExitCode -ne 0 -or -not $complete -or $received -ne $expectedSize) {
        throw 'SSH export did not finish successfully. Retry the download.'
    }
    $file.Dispose()
    $file = $null
    if ((Get-FileHash -LiteralPath $partialPath -Algorithm SHA256).Hash -ne $expectedHash) {
        throw 'SHA-256 verification failed. Retry the download.'
    }
    # File.Move never overwrites an existing backup.
    [IO.File]::Move($partialPath, $finalPath)
    $ownsPartial = $false
    Write-Host 'Download verified. Remote temporary export files cleaned up.'
    Write-Output $finalPath
}
finally {
    try {
        if ($started -and -not $process.HasExited) {
            try { $process.Kill(); $null = $process.WaitForExit(5000) }
            catch {
                if (-not $process.HasExited) { Write-Warning 'Could not stop SSH; check the connection before retrying.' }
            }
        }
    }
    finally {
        $process.Dispose()
        if ($null -ne $file) { $file.Dispose() }
        if ($ownsPartial -and [IO.File]::Exists($partialPath)) {
            [IO.File]::Delete($partialPath)
        }
    }
}
