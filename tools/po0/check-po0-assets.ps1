param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if (-not $OutputDir) {
    $OutputDir = Join-Path $RepoRoot ".tmp/po0-check-assets"
}

$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function ConvertTo-RepoRelativePath {
    param([string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $repoPrefix = $RepoRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside repository: $Path"
    }
    return $full.Substring($repoPrefix.Length).Replace("\", "/")
}

function Get-ManifestEntries {
    param([string]$ManifestPath)
    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        throw "Manifest not found: $ManifestPath"
    }
    $entries = New-Object System.Collections.Generic.List[string]
    foreach ($line in [System.IO.File]::ReadAllLines((Resolve-Path $ManifestPath), $Utf8NoBom)) {
        $entry = $line.Trim()
        if (-not $entry -or $entry.StartsWith("#")) {
            continue
        }
        $entries.Add($entry)
    }
    return $entries.ToArray()
}

function Test-ManifestCoverage {
    param(
        [string]$Name,
        [string]$ManifestPath,
        [string]$SourceDir,
        [string]$Filter = "*.sh"
    )
    Write-Host "Checking manifest coverage: $Name"
    if (-not (Test-Path -LiteralPath $SourceDir)) {
        throw "Source directory not found for ${Name}: $SourceDir"
    }

    $entries = Get-ManifestEntries -ManifestPath $ManifestPath
    if ($entries.Count -eq 0) {
        throw "Manifest has no entries for ${Name}: $ManifestPath"
    }

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($entry in $entries) {
        if (-not $seen.Add($entry)) {
            throw "Duplicate manifest entry in ${Name}: $entry"
        }
        $entryPath = Join-Path $RepoRoot $entry
        if (-not (Test-Path -LiteralPath $entryPath)) {
            throw "Manifest entry does not exist in ${Name}: $entry"
        }
    }

    $sourceParts = Get-ChildItem -LiteralPath $SourceDir -Filter $Filter -File |
        ForEach-Object { ConvertTo-RepoRelativePath -Path $_.FullName } |
        Sort-Object

    foreach ($part in $sourceParts) {
        if (-not $seen.Contains($part)) {
            throw "Source part is missing from manifest ${Name}: $part"
        }
    }

    $sourceRel = (ConvertTo-RepoRelativePath -Path $SourceDir).TrimEnd("/") + "/"
    foreach ($entry in $entries) {
        if (-not $entry.StartsWith($sourceRel, [System.StringComparison]::Ordinal)) {
            throw "Manifest entry for ${Name} is outside expected source directory: $entry"
        }
    }
}

Test-ManifestCoverage `
    -Name "manager" `
    -ManifestPath (Join-Path $RepoRoot "tools/po0/manifests/manager.txt") `
    -SourceDir (Join-Path $RepoRoot "scripts/po0/relay/manager/src")

Test-ManifestCoverage `
    -Name "lan-worker" `
    -ManifestPath (Join-Path $RepoRoot "tools/po0/manifests/lan-worker.txt") `
    -SourceDir (Join-Path $RepoRoot "scripts/po0/relay/lan-worker/src")

Test-ManifestCoverage `
    -Name "self-report-linux" `
    -ManifestPath (Join-Path $RepoRoot "tools/po0/manifests/self-report-linux.txt") `
    -SourceDir (Join-Path $RepoRoot "scripts/po0/relay/self-report/linux/src")

Test-ManifestCoverage `
    -Name "self-report-macos" `
    -ManifestPath (Join-Path $RepoRoot "tools/po0/manifests/self-report-macos.txt") `
    -SourceDir (Join-Path $RepoRoot "scripts/po0/relay/self-report/macos/src")

Test-ManifestCoverage `
    -Name "self-report-windows" `
    -ManifestPath (Join-Path $RepoRoot "tools/po0/manifests/self-report-windows.txt") `
    -SourceDir (Join-Path $RepoRoot "scripts/po0/relay/self-report/windows/src") `
    -Filter "*.ps1"

& (Join-Path $PSScriptRoot "build-po0-assets.ps1") -OutputDir $OutputDir

function Get-BashCommand {
    $bash = Get-Command bash -ErrorAction SilentlyContinue
    if ($bash) { return $bash.Source }
    $gitBash = "C:\Program Files\Git\bin\bash.exe"
    if (Test-Path -LiteralPath $gitBash) { return $gitBash }
    return ""
}

function ConvertTo-BashPath {
    param([string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full -match '^([A-Za-z]):\\(.*)$') {
        $drive = $Matches[1].ToLowerInvariant()
        $rest = $Matches[2].Replace('\', '/')
        return "/${drive}/${rest}"
    }
    return $full.Replace('\', '/')
}

function Invoke-Checked {
    param(
        [string]$FileName,
        [string[]]$Arguments
    )
    $path = Join-Path $OutputDir $FileName
    Write-Host "Checking $FileName $($Arguments -join ' ')"
    $powershell = (Get-Process -Id $PID).Path
    $invokeArgs = @("-NoProfile")
    if ($PSVersionTable.PSEdition -eq "Desktop" -or ($IsWindows -eq $true)) {
        $invokeArgs += @("-ExecutionPolicy", "Bypass")
    }
    $invokeArgs += @("-File", $path)
    $invokeArgs += $Arguments
    & $powershell @invokeArgs | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: $FileName $($Arguments -join ' ')"
    }
}

function Invoke-BashChecked {
    param(
        [string]$FileName,
        [string[]]$Arguments
    )
    $bash = Get-BashCommand
    if (-not $bash) {
        Write-Warning "bash not found; skipping Bash runtime check for $FileName"
        return
    }
    $path = Join-Path $OutputDir $FileName
    $bashPath = ConvertTo-BashPath -Path $path
    Write-Host "Checking bash $FileName $($Arguments -join ' ')"
    & $bash $bashPath @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: bash $FileName $($Arguments -join ' ')"
    }
}

function Invoke-BashSyntax {
    param([string]$FileName)
    $bash = Get-BashCommand
    if (-not $bash) {
        Write-Warning "bash not found; skipping bash -n for $FileName"
        return
    }
    $path = Join-Path $OutputDir $FileName
    $bashPath = ConvertTo-BashPath -Path $path
    Write-Host "Checking bash -n $FileName"
    & $bash -n $bashPath
    if ($LASTEXITCODE -ne 0) {
        throw "bash -n failed: $FileName"
    }
}

function Test-PowerShellSyntax {
    param([string]$FileName)
    $path = Join-Path $OutputDir $FileName
    Write-Host "Checking PowerShell parser $FileName"
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors -and $errors.Count -gt 0) {
        $errors | ForEach-Object { Write-Error $_.Message }
        throw "PowerShell parser failed: $FileName"
    }
}

Invoke-BashSyntax "nftables-relay-manager.sh"
Invoke-BashSyntax "po0-lan-client.sh"
Invoke-BashSyntax "po0-outbound-ip-report.sh"
Invoke-BashSyntax "po0-outbound-ip-report-macos.sh"
Test-PowerShellSyntax "po0-outbound-ip-report.ps1"

Invoke-BashChecked "nftables-relay-manager.sh" @("--version")
Invoke-BashChecked "nftables-relay-manager.sh" @("--changelog")
Invoke-BashChecked "po0-lan-client.sh" @("--version")
Invoke-BashChecked "po0-outbound-ip-report.sh" @("--version")
Invoke-BashChecked "po0-outbound-ip-report.sh" @("--changelog")
Invoke-BashChecked "po0-outbound-ip-report-macos.sh" @("--version")
Invoke-BashChecked "po0-outbound-ip-report-macos.sh" @("--changelog")

Invoke-Checked "po0-outbound-ip-report.ps1" @("-Version")
Invoke-Checked "po0-outbound-ip-report.ps1" @("-Changelog")

Write-Host "PO0 asset checks passed."
