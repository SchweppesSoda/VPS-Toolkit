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

function Test-RawReferences {
    Write-Host "Checking PO0 raw URL references"
    $scanRoots = @(
        (Join-Path $RepoRoot "scripts/po0"),
        (Join-Path $RepoRoot "README.md"),
        (Join-Path $RepoRoot "README.en.md"),
        (Join-Path $RepoRoot "AGENTS.md")
    )
    $allowed = @(
        "scripts/po0/nftables/clients/egern/PO0-SSH-IP-Report.yaml",
        "scripts/po0/nftables/clients/egern/po0-ssh-ip-report.js",
        "scripts/po0/relay/egern/PO0-SSH-IP-Report.yaml",
        "scripts/po0/relay/egern/po0-ssh-ip-report.js",
        "scripts/po0/nftables/tools/build-iplist-package.sh",
        "scripts/po0/nftables/tools/build-iplist-package.ps1",
        "scripts/po0/proxy-services/vless-raw-enc-argosbx-enhancer.sh"
    )
    $unexpected = New-Object System.Collections.Generic.List[string]
    $files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    foreach ($root in $scanRoots) {
        if (Test-Path -LiteralPath $root -PathType Container) {
            Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object { $files.Add($_) }
        } elseif (Test-Path -LiteralPath $root -PathType Leaf) {
            $files.Add((Get-Item -LiteralPath $root))
        }
    }
    foreach ($file in $files) {
        $lineNumber = 0
        foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
            $lineNumber++
            if ($line -notlike "*raw.githubusercontent.com/SchweppesSoda/VPS-Toolkit/main/scripts/po0*") {
                continue
            }
            $isAllowed = $false
            foreach ($path in $allowed) {
                if ($line -like "*$path*") {
                    $isAllowed = $true
                    break
                }
            }
            if (-not $isAllowed) {
                $unexpected.Add("${file}:${lineNumber}: $line")
            }
        }
    }
    if ($unexpected.Count -gt 0) {
        $unexpected | ForEach-Object { Write-Error $_ }
        throw "Unexpected PO0 raw URL reference found."
    }
}

function Test-EgernCompatibilitySync {
    Write-Host "Checking Egern legacy compatibility copy"
    foreach ($name in @("PO0-SSH-IP-Report.yaml", "po0-ssh-ip-report.js")) {
        $canonical = Join-Path $RepoRoot "scripts/po0/nftables/clients/egern/$name"
        $legacy = Join-Path $RepoRoot "scripts/po0/relay/egern/$name"
        if (-not (Test-Path -LiteralPath $canonical)) {
            throw "Canonical Egern file missing: $canonical"
        }
        if (-not (Test-Path -LiteralPath $legacy)) {
            throw "Legacy Egern compatibility file missing: $legacy"
        }
        $canonicalText = [System.IO.File]::ReadAllText($canonical).Replace("`r`n", "`n").Replace("`r", "`n")
        $legacyText = [System.IO.File]::ReadAllText($legacy).Replace("`r`n", "`n").Replace("`r", "`n")
        if ($canonicalText -ne $legacyText) {
            throw "Legacy Egern compatibility file differs from canonical after LF normalization: $name"
        }
    }
}

function Test-WindowsCanonicalPath {
    $asset = Join-Path $OutputDir "po0-outbound-ip-report.ps1"
    Write-Host "Checking Windows canonical install path"
    $raw = Get-Content -LiteralPath $asset -Raw -Encoding UTF8
    if ($raw -notmatch 'po0-outbound-ip-report\.ps1') {
        throw "Windows self-report asset does not mention canonical po0-outbound-ip-report.ps1 path."
    }
    $scriptName = [regex]::Match($raw, '(?m)^\s*\$ScriptName\s*=\s*"([^"]+)"')
    if (-not $scriptName.Success -or $scriptName.Groups[1].Value -ne "po0-outbound-ip-report") {
        throw "Windows self-report script name is not canonical."
    }
    $defaultScript = [regex]::Match($raw, '(?ms)^function Get-DefaultScriptPath \{.*?^}')
    $defaultLauncher = [regex]::Match($raw, '(?ms)^function Get-DefaultTaskLauncherPath \{.*?^}')
    if (-not $defaultScript.Success -or $defaultScript.Value -notmatch 'po0-outbound-ip-report\.ps1' -or $defaultScript.Value -match 'po0-self-report\.ps1') {
        throw "Windows self-report default script path is not canonical."
    }
    if (-not $defaultLauncher.Success -or $defaultLauncher.Value -notmatch 'po0-outbound-ip-report-task\.vbs' -or $defaultLauncher.Value -match 'po0-self-report-task\.vbs') {
        throw "Windows self-report default launcher path is not canonical."
    }
}

function Test-VersionsMatchTag {
    $tag = $env:GITHUB_REF_NAME
    if (-not $tag) { return }
    $match = [regex]::Match($tag, '^po0-v([0-9]{4}\.[0-9]{2}\.[0-9]{2})\.([0-9]+)$')
    if (-not $match.Success) { return }
    $expected = "$($match.Groups[1].Value)+build.$($match.Groups[2].Value)"

    foreach ($asset in @(
        "nftables-relay-manager.sh",
        "po0-lan-client.sh",
        "po0-outbound-ip-report.sh",
        "po0-outbound-ip-report-macos.sh"
    )) {
        $path = Join-Path $OutputDir $asset
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        $version = [regex]::Match($raw, '(?m)^SCRIPT_VERSION="([^"]+)"')
        if (-not $version.Success -or $version.Groups[1].Value -ne $expected) {
            throw "$asset version $($version.Groups[1].Value) does not match tag $tag"
        }
    }

    $psAsset = Join-Path $OutputDir "po0-outbound-ip-report.ps1"
    $psRaw = Get-Content -LiteralPath $psAsset -Raw -Encoding UTF8
    $psVersion = [regex]::Match($psRaw, '(?m)^\$ScriptVersion\s*=\s*"([^"]+)"')
    if (-not $psVersion.Success -or $psVersion.Groups[1].Value -ne $expected) {
        throw "po0-outbound-ip-report.ps1 version $($psVersion.Groups[1].Value) does not match tag $tag"
    }
}

Test-RawReferences
Test-EgernCompatibilitySync

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
Test-WindowsCanonicalPath
Test-VersionsMatchTag

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
