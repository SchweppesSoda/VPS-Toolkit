param(
    [string]$OutputDir = "",
    [switch]$NoChecksum
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if (-not $OutputDir) {
    $OutputDir = Join-Path $RepoRoot ".tmp/po0-assets"
}
if ([System.IO.Path]::IsPathRooted($OutputDir)) {
    $OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
} else {
    $OutputDir = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $OutputDir))
}
$repoPrefix = $RepoRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
if ($OutputDir -eq $RepoRoot -or -not $OutputDir.StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputDir must be inside the repository and must not be the repository root: $OutputDir"
}
$tmpRoot = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot ".tmp"))
$tmpPo0Prefix = (Join-Path $tmpRoot "po0-")
if (-not $OutputDir.StartsWith($tmpPo0Prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputDir must be inside the repository .tmp directory and start with 'po0-': $OutputDir"
}

$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$Utf8Bom = [System.Text.UTF8Encoding]::new($true)

function Read-Utf8Lf {
    param([string]$Path)
    $resolved = (Resolve-Path $Path).Path
    $text = [System.IO.File]::ReadAllText($resolved, $Utf8NoBom)
    $text = $text -replace "`r`n", "`n"
    $text = $text -replace "`r", "`n"
    return $text
}

function Write-Utf8Lf {
    param(
        [string]$Path,
        [string]$Text,
        [switch]$Bom
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $normalized = $Text -replace "`r`n", "`n"
    $normalized = $normalized -replace "`r", "`n"
    if (-not $normalized.EndsWith("`n")) {
        $normalized += "`n"
    }
    $encoding = $(if ($Bom) { $Utf8Bom } else { $Utf8NoBom })
    [System.IO.File]::WriteAllText($Path, $normalized, $encoding)
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
    if ($entries.Count -eq 0) {
        throw "Manifest has no entries: $ManifestPath"
    }
    return $entries.ToArray()
}

function Join-Manifest {
    param(
        [string]$ManifestPath,
        [string]$OutputPath,
        [switch]$RequireShebang,
        [switch]$Bom
    )
    $parts = New-Object System.Collections.Generic.List[string]
    $index = 0
    foreach ($entry in (Get-ManifestEntries -ManifestPath $ManifestPath)) {
        $sourcePath = Join-Path $RepoRoot $entry
        if (-not (Test-Path -LiteralPath $sourcePath)) {
            throw "Manifest entry not found: $entry"
        }
        $text = Read-Utf8Lf -Path $sourcePath
        if ($index -gt 0 -and $text.StartsWith("#!")) {
            $text = $text -replace "\A#![^\n]*\n", ""
        }
        $parts.Add($text.TrimEnd("`n"))
        $index++
    }
    $combined = [string]::Join("`n`n", $parts)
    if ($RequireShebang -and -not $combined.StartsWith("#!")) {
        throw "Built shell asset must start with a shebang: $OutputPath"
    }
    Write-Utf8Lf -Path $OutputPath -Text $combined -Bom:$Bom
}

function Write-Checksums {
    param([string]$Dir)
    $lines = New-Object System.Collections.Generic.List[string]
    Get-ChildItem -LiteralPath $Dir -File |
        Where-Object { $_.Name -ne "checksums.txt" } |
        Sort-Object Name |
        ForEach-Object {
            $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
            $lines.Add("${hash}  $($_.Name)")
        }
    Write-Utf8Lf -Path (Join-Path $Dir "checksums.txt") -Text ([string]::Join("`n", $lines))
}

if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

Join-Manifest `
    -ManifestPath (Join-Path $RepoRoot "tools/po0/manifests/manager.txt") `
    -OutputPath (Join-Path $OutputDir "nftables-relay-manager.sh") `
    -RequireShebang

Join-Manifest `
    -ManifestPath (Join-Path $RepoRoot "tools/po0/manifests/lan-worker.txt") `
    -OutputPath (Join-Path $OutputDir "po0-lan-client.sh") `
    -RequireShebang

Join-Manifest `
    -ManifestPath (Join-Path $RepoRoot "tools/po0/manifests/wan-probe-openwrt.txt") `
    -OutputPath (Join-Path $OutputDir "po0-wan-probe.sh") `
    -RequireShebang

Join-Manifest `
    -ManifestPath (Join-Path $RepoRoot "tools/po0/manifests/self-report-linux.txt") `
    -OutputPath (Join-Path $OutputDir "po0-outbound-ip-report.sh") `
    -RequireShebang

Join-Manifest `
    -ManifestPath (Join-Path $RepoRoot "tools/po0/manifests/self-report-macos.txt") `
    -OutputPath (Join-Path $OutputDir "po0-outbound-ip-report-macos.sh") `
    -RequireShebang

Join-Manifest `
    -ManifestPath (Join-Path $RepoRoot "tools/po0/manifests/self-report-windows.txt") `
    -OutputPath (Join-Path $OutputDir "po0-outbound-ip-report.ps1") `
    -Bom

if (-not $NoChecksum) {
    Write-Checksums -Dir $OutputDir
}

Write-Host "Built PO0 assets in $OutputDir"
