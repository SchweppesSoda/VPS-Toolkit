param(
    [string]$OutFile = (Join-Path ([Environment]::GetFolderPath("Desktop")) "iplist.tar.gz"),
    [int]$ThrottleLimit = 8
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

if ($ThrottleLimit -lt 1) {
    throw "ThrottleLimit must be greater than 0"
}

$DocUrl = "https://raw.githubusercontent.com/metowolf/iplist/refs/heads/master/docs/cncity.md"
$OutFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
$WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ("po0-iplist-" + [System.Guid]::NewGuid().ToString("N"))

function Get-RelativeDataPath {
    param([string]$Url)

    if ($Url -match "/iplist/(data/cncity/.+\.txt)$") {
        return $Matches[1]
    }
    if ($Url -match "/(data/cncity/.+\.txt)$") {
        return $Matches[1]
    }
    return $null
}

try {
    New-Item -ItemType Directory -Path (Join-Path $WorkDir "docs") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $WorkDir "data") -Force | Out-Null

    $DocPath = Join-Path $WorkDir "docs/cncity.md"
    Invoke-WebRequest -UseBasicParsing -Uri $DocUrl -OutFile $DocPath

    $DocText = Get-Content -LiteralPath $DocPath -Raw
    $Urls = [regex]::Matches($DocText, "https?://[^|\s]+\.txt") |
        ForEach-Object { $_.Value } |
        Sort-Object -Unique

    if (-not $Urls -or $Urls.Count -eq 0) {
        throw "No data URLs found in cncity.md"
    }

    $Downloads = @()
    $Index = 0
    foreach ($Url in $Urls) {
        $Index++
        $RelPath = Get-RelativeDataPath $Url
        if (-not $RelPath) {
            Write-Warning "Skip unsupported URL: $Url"
            continue
        }

        $Target = Join-Path $WorkDir ($RelPath -replace "/", [System.IO.Path]::DirectorySeparatorChar)
        $Downloads += [pscustomobject]@{
            Index = $Downloads.Count + 1
            Url = $Url
            RelPath = $RelPath
            Target = $Target
        }
    }

    if ($Downloads.Count -eq 0) {
        throw "No supported data/cncity URLs found in cncity.md"
    }

    $Total = $Downloads.Count
    $Jobs = @()
    $Failures = New-Object System.Collections.Generic.List[string]
    foreach ($Download in $Downloads) {
        while (($Jobs | Where-Object { $_.State -eq "Running" }).Count -ge $ThrottleLimit) {
            $Done = Wait-Job -Job $Jobs -Any
            $JobErrors = $null
            Receive-Job -Job $Done -ErrorAction SilentlyContinue -ErrorVariable JobErrors | ForEach-Object { Write-Host $_ }
            if ($Done.State -ne "Completed") {
                $Failures.Add("Download job failed for $($Done.Name): $($Done.State)")
            }
            if ($JobErrors) {
                $Failures.Add(($JobErrors | ForEach-Object { $_.ToString() }) -join "`n")
            }
            Remove-Job -Job $Done -Force
            $Jobs = @($Jobs | Where-Object { $_.Id -ne $Done.Id })
        }

        $Jobs += Start-Job -Name $Download.RelPath -ArgumentList $Download.Url, $Download.Target, $Download.Index, $Total, $Download.RelPath -ScriptBlock {
            param($Url, $Target, $Index, $Total, $RelPath)
            $ErrorActionPreference = "Stop"
            $ProgressPreference = "SilentlyContinue"
            New-Item -ItemType Directory -Path (Split-Path -Parent $Target) -Force | Out-Null
            Write-Output ("[{0}/{1}] {2}" -f $Index, $Total, $RelPath)
            Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Target
        }
    }

    while ($Jobs.Count -gt 0) {
        $Done = Wait-Job -Job $Jobs -Any
        $JobErrors = $null
        Receive-Job -Job $Done -ErrorAction SilentlyContinue -ErrorVariable JobErrors | ForEach-Object { Write-Host $_ }
        if ($Done.State -ne "Completed") {
            $Failures.Add("Download job failed for $($Done.Name): $($Done.State)")
        }
        if ($JobErrors) {
            $Failures.Add(($JobErrors | ForEach-Object { $_.ToString() }) -join "`n")
        }
        Remove-Job -Job $Done -Force
        $Jobs = @($Jobs | Where-Object { $_.Id -ne $Done.Id })
    }

    if ($Failures.Count -gt 0) {
        throw ("One or more downloads failed:`n" + ($Failures -join "`n"))
    }

    if (Test-Path -LiteralPath $OutFile) {
        Remove-Item -LiteralPath $OutFile -Force
    }
    Push-Location $WorkDir
    try {
        & tar -czf $OutFile docs data
        if ($LASTEXITCODE -ne 0) {
            throw "tar failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }

    Write-Host "Created: $OutFile"
}
finally {
    if (Test-Path -LiteralPath $WorkDir) {
        Remove-Item -LiteralPath $WorkDir -Recurse -Force
    }
}
