param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if (-not $OutputDir) {
    $OutputDir = Join-Path $RepoRoot ".tmp/po0-check-assets-powershell"
}

$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$ExpectedPo0Version = if ($env:PO0_EXPECTED_ASSET_VERSION) { $env:PO0_EXPECTED_ASSET_VERSION } else { "2026.09.06+build.2" }
$ExpectedPo0ReleaseDate = if ($env:PO0_EXPECTED_RELEASE_DATE) { $env:PO0_EXPECTED_RELEASE_DATE } else { "2026-09-06" }
$ExpectedPo0ReleaseTag = if ($env:PO0_EXPECTED_RELEASE_TAG) { $env:PO0_EXPECTED_RELEASE_TAG } else { "po0-v2026.09.06.2" }

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
        "scripts/po0/nftables/clients/loon/PO0.LAN-Report.lpx",
        "scripts/po0/nftables/clients/loon/po0-loon-report.js",
        "scripts/po0/nftables/clients/stash/po0-stash-report.js",
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

function Test-EgernSsidGuard {
    Write-Host "Checking Egern SSID local guard"
    $yaml = Join-Path $RepoRoot "scripts/po0/nftables/clients/egern/PO0-SSH-IP-Report.yaml"
    $js = Join-Path $RepoRoot "scripts/po0/nftables/clients/egern/po0-ssh-ip-report.js"
    $legacyYaml = Join-Path $RepoRoot "scripts/po0/relay/egern/PO0-SSH-IP-Report.yaml"
    $legacyJs = Join-Path $RepoRoot "scripts/po0/relay/egern/po0-ssh-ip-report.js"
    $yamlRaw = Get-Content -LiteralPath $yaml -Raw -Encoding UTF8
    $jsRaw = Get-Content -LiteralPath $js -Raw -Encoding UTF8
    if ($yamlRaw -notmatch '(?m)^\s+SKIP_WIFI_SSIDS:') {
        throw "Egern YAML lacks SKIP_WIFI_SSIDS env configuration."
    }
    foreach ($action in @("保存本机 PO0 自建防火墙配置", "保存本机 PO0 官方防火墙配置", "清除本机全部 PO0 上报配置")) {
        if (-not $yamlRaw.Contains($action)) {
            throw "Egern YAML lacks native storage action: $action"
        }
    }
    foreach ($token in @("normalizeSsidSkipList", "currentWifiSsidFromNetwork", "ssidSkipDecision", "isAutomaticReportRun")) {
        if (-not $jsRaw.Contains($token)) {
            throw "Egern JS lacks $token."
        }
    }
    foreach ($token in @(
        "CONFIG_STORAGE_KEY",
        "persistableEnvValues",
        "reportConfigSaveCandidate",
        "storedReportConfig",
        "handleReportConfigSaveScript",
        "handleReportConfigClearScript",
        "skipType: 'missing-config'"
    )) {
        if (-not $jsRaw.Contains($token)) {
            throw "Egern JS lacks native storage implementation token: $token"
        }
    }
    if (-not $jsRaw.Contains("skipType: 'wifi-ssid'")) {
        throw "Egern JS lacks wifi-ssid skipped state marker."
    }
    if (-not $jsRaw.Contains("skipReason:")) {
        throw "Egern JS lacks local skip/no-upload state wording."
    }
    foreach ($path in @($yaml, $js, $legacyYaml, $legacyJs)) {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        if ($raw -match 'PO0_SELF_REPORT_[A-Z0-9_]*SSID|SELF_REPORT_[A-Z0-9_]*SSID') {
            throw "Egern SSID guard must not define legacy self-report SSID aliases: $path"
        }
    }
    $defaultFn = [regex]::Match($jsRaw, '(?ms)^async function runEgernReportUnlocked\(ctx\) \{.*?^export default async function')
    if (-not $defaultFn.Success) {
        throw "Egern default report flow was not found."
    }
    $guard = $defaultFn.Value.IndexOf("ssidSkipDecision(ctx, env, network)", [System.StringComparison]::Ordinal)
    $detect = $defaultFn.Value.IndexOf("detectCurrentIPv4WithFallback(ctx, env, policy)", [System.StringComparison]::Ordinal)
    if ($guard -lt 0) {
        throw "Egern JS lacks SSID guard inside default report flow."
    }
    if ($detect -lt 0) {
        throw "Egern JS IPv4 detection call not found in default report flow."
    }
    if ($guard -ge $detect) {
        throw "Egern SSID guard must run before public IPv4 detection."
    }
    $reportFn = [regex]::Match($jsRaw, '(?ms)^async function reportToPO0\(.*?^}')
    if (-not $reportFn.Success) {
        throw "Egern reportToPO0 function was not found."
    }
    if ($reportFn.Value -match '(?i)ssid') {
        throw "Egern reportToPO0 must not pass SSID through SSH report args."
    }
}

function Test-EgernOfficialChannel {
    Write-Host "Checking Egern official firewall channel"
    $yaml = Join-Path $RepoRoot "scripts/po0/nftables/clients/egern/PO0-SSH-IP-Report.yaml"
    $js = Join-Path $RepoRoot "scripts/po0/nftables/clients/egern/po0-ssh-ip-report.js"
    $yamlRaw = Get-Content -LiteralPath $yaml -Raw -Encoding UTF8
    $jsRaw = Get-Content -LiteralPath $js -Raw -Encoding UTF8
    foreach ($marker in @(
        "PO0_FIREWALL_TOKENS:",
        "PO0 官方防火墙状态（只读）"
    )) {
        if (-not $yamlRaw.Contains($marker)) {
            throw "Egern YAML lacks official firewall marker: $marker"
        }
    }
    foreach ($marker in @(
        "OFFICIAL_FIREWALL_INTERVAL_SECONDS = 600",
        "OFFICIAL_FIREWALL_API_BASE",
        "parseOfficialTokens",
        "officialDirectRequest",
        "officialDisplaySlot",
        "runOfficialFirewall",
        "policy: 'DIRECT'",
        "isOfficialStatusRun"
    )) {
        if (-not $jsRaw.Contains($marker)) {
            throw "Egern JS lacks official firewall contract marker: $marker"
        }
    }
    $defaultFn = [regex]::Match($jsRaw, '(?ms)^async function runEgernReportUnlocked\(ctx\) \{.*?^export default async function')
    if (-not $defaultFn.Success) {
        throw "Egern default report flow was not found."
    }
    $officialOffset = $defaultFn.Value.IndexOf("runOfficialFirewall(ctx, env", [System.StringComparison]::Ordinal)
    $workerOffset = $defaultFn.Value.IndexOf("reportToPO0(ctx, env, target, ip)", [System.StringComparison]::Ordinal)
    if ($officialOffset -lt 0 -or $workerOffset -lt 0 -or $officialOffset -ge $workerOffset) {
        throw "Egern official firewall lane must run before the existing SSH lane."
    }
}

function Test-LanWorkerOfficialChannel {
    Write-Host "Checking LAN Worker official firewall channel"
    $sourcePath = Join-Path $RepoRoot "scripts/po0/relay/lan-worker/src/055-official-firewall.sh"
    $dispatchPath = Join-Path $RepoRoot "scripts/po0/relay/lan-worker/src/990-main-menu-dispatch.sh"
    $sourceRaw = Get-Content -LiteralPath $sourcePath -Raw -Encoding UTF8
    $dispatchRaw = Get-Content -LiteralPath $dispatchPath -Raw -Encoding UTF8
    foreach ($marker in @(
        "PO0_FIREWALL_TOKENS",
        'PO0_FIREWALL_API_BASE_URL="https://124.221.69.228/api/firewall"',
        'PO0_FIREWALL_INTERVAL_SECONDS="600"',
        "official_run_lock_acquire",
        "official_response_valid",
        "official_direct_request",
        'request = "%s"'
    )) {
        if (-not $sourceRaw.Contains($marker)) {
            throw "LAN Worker official firewall source lacks contract marker: $marker"
        }
    }
    foreach ($marker in @(
        "--official-firewall-status",
        "--run-official-firewall",
        "--scheduled-run"
    )) {
        if (-not $dispatchRaw.Contains($marker)) {
            throw "LAN Worker dispatch lacks official firewall action marker: $marker"
        }
    }
    foreach ($name in @("160-webauth-server.sh", "180-self-report-server.sh")) {
        $servicePath = Join-Path $RepoRoot "scripts/po0/relay/lan-worker/src/$name"
        $serviceRaw = Get-Content -LiteralPath $servicePath -Raw -Encoding UTF8
        if (-not $serviceRaw.Contains("env -u PO0_FIREWALL_TOKENS")) {
            throw "LAN Worker Python service leaks PO0_FIREWALL_TOKENS to its child: $name"
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
    $defaultConfig = [regex]::Match($raw, '(?ms)^function Get-DefaultConfigPath \{.*?^}')
    $defaultLog = [regex]::Match($raw, '(?ms)^function Get-DefaultLogPath \{.*?^}')
    $defaultState = [regex]::Match($raw, '(?ms)^function Get-IpCheckStatePath \{.*?^}')
    if (-not $defaultConfig.Success -or $defaultConfig.Value -notmatch 'outbound-ip-report\.json' -or $defaultConfig.Value -match 'self-report\.json') {
        throw "Windows self-report default config path is not canonical."
    }
    if (-not $defaultLog.Success -or $defaultLog.Value -notmatch 'po0-outbound-ip-report\.log' -or $defaultLog.Value -match 'po0-self-report\.log') {
        throw "Windows self-report default log path is not canonical."
    }
    if (-not $defaultState.Success -or $defaultState.Value -notmatch 'outbound-ip-report-ip-check-index\.txt' -or $defaultState.Value -match 'self-report-ip-check-index\.txt') {
        throw "Windows self-report IP check state path is not canonical."
    }
    if ($raw -notmatch '\$script:TaskName = "Outbound IP Report"') {
        throw "Windows self-report task name is not canonical."
    }
    if ($raw -notmatch '\$script:TaskName = "PO0 Outbound IP Report to LAN Worker"') {
        throw "Windows self-report asset lacks build.1 upgrade compatibility marker."
    }
    if ($raw -notmatch 'PO0_OUTBOUND_IP_REPORT_CONFIG') {
        throw "Windows self-report asset lacks canonical env aliases."
    }
    if ($raw -notmatch 'Cleanup-LegacySelfReportArtifacts') {
        throw "Windows self-report asset lacks legacy artifact cleanup."
    }
    if ($raw -notmatch 'Remove-LegacyScheduledReporterTask') {
        throw "Windows self-report asset lacks robust legacy scheduled task cleanup."
    }
    if ($raw -notmatch '"-NoNotify"') {
        throw "Windows self-report scheduled task does not preserve explicit -NoNotify."
    }
}

function Test-UnixOutboundIpReportCanonicalPath {
    param(
        [string]$FileName,
        [string]$Platform
    )
    $path = Join-Path $OutputDir $FileName
    $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    if ($raw -notmatch '(?m)^SCRIPT_NAME="po0-outbound-ip-report"') {
        throw "$Platform script name is not canonical."
    }
    $install = [regex]::Match($raw, '(?ms)^default_install_path\(\) \{.*?^}')
    $canonicalInstall = [regex]::Match($raw, '(?ms)^canonical_install_path\(\) \{.*?^}')
    $config = [regex]::Match($raw, '(?ms)^canonical_config_file\(\) \{.*?^}')
    $log = [regex]::Match($raw, '(?ms)^self_report_log_path\(\) \{.*?^}')
    $state = [regex]::Match($raw, '(?ms)^ip_check_state_file\(\) \{.*?^}')
    if (-not $install.Success -or $install.Value -match 'po0-self-report' -or -not $canonicalInstall.Success -or $canonicalInstall.Value -notmatch 'po0-outbound-ip-report' -or $canonicalInstall.Value -match 'po0-self-report') {
        throw "$Platform default install path is not canonical."
    }
    if (-not $config.Success -or $config.Value -notmatch 'po0-outbound-ip-report' -or $config.Value -match 'po0-self-report') {
        throw "$Platform default config path is not canonical."
    }
    if (-not $log.Success -or $log.Value -notmatch 'po0-outbound-ip-report\.log' -or $log.Value -match 'po0-self-report\.log') {
        throw "$Platform default log path is not canonical."
    }
    if (-not $state.Success -or $state.Value -notmatch 'po0-outbound-ip-report' -or $state.Value -match 'po0-self-report') {
        throw "$Platform IP check state path is not canonical."
    }
    if ($raw -notmatch 'OUTBOUND_IP_REPORT_BEGIN') {
        throw "$Platform cron marker is not canonical."
    }
    if ($raw -notmatch 'PO0_OUTBOUND_IP_REPORT_CONFIG') {
        throw "$Platform asset lacks canonical env aliases."
    }
    if ($raw -match 'write_legacy_command_shim' -or $raw -match 'ln -s "\$\{dest\}" "\$\{legacy\}"') {
        throw "$Platform still creates a legacy po0-self-report command shim."
    }
    if ($raw -notmatch 'cleanup_legacy_self_report_artifacts') {
        throw "$Platform lacks legacy artifact cleanup after upgrade/self-heal."
    }
}

function Test-MacOsLaunchdCanonicalPath {
    $path = Join-Path $OutputDir "po0-outbound-ip-report-macos.sh"
    $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $label = [regex]::Match($raw, '(?ms)^launchd_label\(\) \{.*?^}')
    if (-not $label.Success -or $label.Value -notmatch 'outbound-ip-report' -or $label.Value -match 'fr\.schweppes\.po0-(outbound-ip-report|self-report)') {
        throw "macOS launchd label is not canonical."
    }
}

function Test-LegacyNameAllowlist {
    $assets = @(
        "po0-outbound-ip-report.sh",
        "po0-outbound-ip-report-macos.sh",
        "po0-outbound-ip-report.ps1"
    )
    $legacyPattern = 'po0-self-report|PO0_SELF_REPORT|SELF_REPORT_|PO0 Self Report|PO0 Outbound IP Report to LAN Worker|Self-report 已完成|Self-report 未完成|self-report\.json|po0-self-report\.log|fr\.schweppes\.po0-self-report|fr\.schweppes\.po0-outbound-ip-report|PO0_SELF_REPORT_BEGIN|PO0_SELF_REPORT_END|PO0_OUTBOUND_IP_REPORT_BEGIN|PO0_OUTBOUND_IP_REPORT_END'
    $allowedContext = '(?i:legacy|compat|fallback|alias|migrat|cleanup|old|previous|PreviousTaskName|PreviousTaskLauncherPath|write_cron_without_managed_block|Test-DownloadedScript|defaultScript\.Value|defaultLauncher\.Value|defaultLog\.Value)|旧|兼容|迁移|回退|别名|历史|Get-Legacy|legacy_|LegacyTaskName|旧版|校验失败|grep -q|Self-report 已完成|Self-report 未完成|PO0_SELF_REPORT|SELF_REPORT_'
    foreach ($asset in $assets) {
        $path = Join-Path $OutputDir $asset
        $lines = Get-Content -LiteralPath $path -Encoding UTF8
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -notmatch $legacyPattern) { continue }
            $start = [Math]::Max(0, $i - 10)
            $end = [Math]::Min($lines.Count - 1, $i + 10)
            $context = ($lines[$start..$end] -join "`n")
            if ($context -notmatch $allowedContext) {
                throw "$asset contains legacy name outside migration/compat context at line $($i + 1): $($lines[$i])"
            }
        }
    }
}

function Test-NoNewLegacySsidAliases {
    foreach ($asset in @(
        "po0-outbound-ip-report.sh",
        "po0-outbound-ip-report-macos.sh",
        "po0-outbound-ip-report.ps1"
    )) {
        $path = Join-Path $OutputDir $asset
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        if ($raw -match 'PO0_SELF_REPORT_[A-Z0-9_]*SSID|SELF_REPORT_[A-Z0-9_]*SSID') {
            throw "$asset defines a new legacy self-report SSID alias; use PO0_OUTBOUND_IP_REPORT_* only."
        }
    }
}

function Test-UnixSsidGuard {
    param(
        [string]$FileName,
        [string]$Platform
    )
    $path = Join-Path $OutputDir $FileName
    $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    if ($raw -notmatch 'PO0_OUTBOUND_IP_REPORT_[A-Z0-9_]*SSID') {
        throw "$Platform asset lacks canonical SSID environment configuration."
    }
    if ($raw -notmatch '--[a-z0-9-]*ssid[a-z0-9-]*') {
        throw "$Platform asset lacks SSID CLI configuration."
    }
    if ($raw -notmatch '(?im)(^|[^A-Z0-9_])([A-Z0-9_]*SSID[A-Z0-9_]*)=') {
        throw "$Platform asset lacks persisted SSID configuration variable."
    }
    if ($raw -notmatch '(?is)(ssid.{0,160}(skip|skipped|跳过)|(skip|skipped|跳过).{0,160}ssid)') {
        throw "$Platform asset lacks SSID skip result wording."
    }
    if ($raw -notmatch '(?is)(ssid.{0,160}(summary|log|摘要|日志)|(summary|log|摘要|日志).{0,160}ssid)' -and $raw -notmatch 'self_report_log_event_summary|show_recent_self_report_log') {
        throw "$Platform asset lacks SSID skip log/status summary wording."
    }
    if ($raw -notmatch '(?is)(ssid.{0,160}(continue|continued|fail|failed|failure|error|unavailable|读取失败|继续上报)|(continue|continued|fail|failed|failure|error|unavailable|读取失败|继续上报).{0,160}ssid)' -and $raw -notmatch 'current_wifi_ssid\s+2>/dev/null\s+\|\|\s+true') {
        throw "$Platform asset does not state that SSID read failure continues reporting."
    }
    if ($raw -match 'local -a items=|read -r -a items') {
        throw "$Platform asset must not parse SSID lists with Bash arrays; macOS Bash 3.2 + set -u treats empty arrays as unbound."
    }
    $fn = [regex]::Match($raw, '(?ms)^report_once(?:_inner)?\(\) \{.*?(?=^[A-Za-z_][A-Za-z0-9_]*\(\) \{|\z)')
    if (-not $fn.Success) {
        throw "$Platform report_once function was not found."
    }
    $guard = [regex]::Match($fn.Value, '(?is)ssid.{0,160}(skip|guard|allow|match|local|跳过|匹配|本地)|(skip|guard|allow|match|local|跳过|匹配|本地).{0,160}ssid')
    $worker = [regex]::Match($fn.Value, '(?m)^\s*(?:worker_report_once|report_worker_once)\b')
    $workerFn = [regex]::Match($raw, '(?ms)^(?:worker_report_once|report_worker_once)\(\) \{.*?(?=^[A-Za-z_][A-Za-z0-9_]*\(\) \{|\z)')
    $http = [regex]::Match($workerFn.Value, 'curl "\$\{curl_args\[@\]\}"')
    if (-not $guard.Success) {
        throw "$Platform asset lacks an SSID guard inside report_once."
    }
    if (-not $worker.Success) {
        throw "$Platform asset report worker call was not found."
    }
    if ($guard.Index -ge $worker.Index) {
        throw "$Platform asset SSID guard must run before report worker submission."
    }
    if (-not $http.Success) {
        throw "$Platform asset HTTP submit point was not found in the report worker."
    }
}

function Test-MacOsWifiSsidDiagnostic {
    $path = Join-Path $OutputDir "po0-outbound-ip-report-macos.sh"
    $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    if ($raw -notmatch '--show-wifi-ssid') {
        throw "macOS asset lacks --show-wifi-ssid diagnostic CLI."
    }
    if ($raw -notmatch '--diagnose-wifi-ssid') {
        throw "macOS asset lacks --diagnose-wifi-ssid permission diagnostic CLI."
    }
    if ($raw -notmatch '--open-location-services') {
        throw "macOS asset lacks --open-location-services settings shortcut CLI."
    }
    if ($raw -notmatch '--request-location-permission') {
        throw "macOS asset lacks --request-location-permission authorization prompt CLI."
    }
    if ($raw -notmatch '--delete-location-permission-helper' -or $raw -notmatch '--remove-location-helper') {
        throw "macOS asset lacks Location Permission Helper deletion CLI."
    }
    if ($raw -notmatch 'show_current_wifi_ssid_once\(\)') {
        throw "macOS asset lacks explicit current Wi-Fi SSID diagnostic function."
    }
    if ($raw -notmatch 'show_wifi_ssid_permission_help\(\)') {
        throw "macOS asset lacks Wi-Fi SSID permission diagnostic helper."
    }
    if ($raw -notmatch 'show_wifi_ssid_permission_help_interactive\(\)') {
        throw "macOS asset lacks interactive Wi-Fi SSID permission menu helper."
    }
    if ($raw -notmatch 'request_macos_location_permission\(\)' -or $raw -notmatch 'ensure_macos_location_permission_helper_app\(\)' -or $raw -notmatch 'macos_location_helper_wifi_ssid\(\)') {
        throw "macOS asset lacks Location Services authorization request helper."
    }
    if ($raw -notmatch 'client_maintenance_menu\(\)' -or $raw -notmatch 'max_choice=4' -or $raw -notmatch '请选择 \[0-\$max_choice\]' -or $raw -notmatch '7\) client_maintenance_menu;' -or $raw -notmatch '3\).*then show_wifi_ssid_permission_help_interactive;' -or $raw -notmatch '4\).*then remove_macos_location_permission_helper_app_interactive;') {
        throw "macOS asset lacks Wi-Fi SSID diagnostic menu/range/case wiring."
    }
    if ($raw -notmatch 'remove_macos_location_permission_helper_app\(\)' -or $raw -notmatch 'remove_macos_location_permission_helper_app_interactive\(\)') {
        throw "macOS asset lacks Location Permission Helper removal helpers."
    }
    if ($raw -notmatch 'accepted_wifi_ssid_value\(\)') {
        throw "macOS asset lacks centralized Wi-Fi SSID value filter."
    }
    if ($raw -notmatch '<redacted>' -or $raw -notmatch 'redacted') {
        throw "macOS asset must reject redacted Wi-Fi SSID placeholders."
    }
    if ($raw -notmatch 'WIFI_SSID_LAST_ERROR="privacy"') {
        throw "macOS asset must record privacy-hidden Wi-Fi SSID state."
    }
    if ($raw -notmatch 'open "x-apple\.systempreferences:com\.apple\.preference\.security\?Privacy_LocationServices"') {
        throw "macOS asset must print an exact Location Services open command."
    }
    if ($raw -notmatch 'CoreLocation' -or $raw -notmatch 'requestWhenInUseAuthorization') {
        throw "macOS asset must include a CoreLocation permission request path."
    }
    if ($raw -notmatch 'CoreWLAN' -or $raw -notmatch 'macos_location_helper_wifi_ssid\(\)') {
        throw "macOS asset must let the Location Permission Helper read Wi-Fi SSID in-process."
    }
    if ($raw -match 'networksetup_wifi_ssid\(\)|networksetup_any_wifi_ssid\(\)|networksetup_common_wifi_ssid\(\)|ipconfig_wifi_ssid\(\)|airport_wifi_ssid\(\)|wdutil_wifi_ssid\(\)') {
        throw "macOS asset must not keep shell command Wi-Fi SSID fallback functions; use Helper-only probing."
    }
    if ($raw -match 'on run argv') {
        throw "macOS helper AppleScript must not depend on AppleScript applet argv coercion."
    }
    if ($raw -notmatch 'path to resource "po0-location-helper-output\.path"') {
        throw "macOS helper AppleScript should read output path from bundled resource."
    }
    if ($raw -notmatch 'path to resource "po0-location-helper-mode\.txt"') {
        throw "macOS helper AppleScript should read request mode from bundled resource."
    }
    if ($raw -notmatch 'macos_location_helper_request_file\(\)' -or $raw -notmatch 'write_macos_location_helper_request_file\(\)') {
        throw "macOS helper IPC must use managed request file helpers."
    }
    if ($raw -match 'open -W -n "\$\{app_dir\}" --args') {
        throw "macOS helper launcher must not pass output path through open --args."
    }
    if ($raw -match 'as (boolean|integer|real)') {
        throw "macOS helper AppleScript must not coerce AppleScriptObjC values with as boolean/integer/real."
    }
    if ($raw -match 'write theText to fileRef as') {
        throw "macOS helper AppleScript must not write output with AppleEvent utf8 class coercion."
    }
    if ($raw -match 'writeToFile:outputPath') {
        throw "macOS helper AppleScript must not write output through AppleScriptObjC NSError bridging."
    }
    if ($raw -notmatch '/usr/bin/printf %s') {
        throw "macOS helper AppleScript should write output through shell printf."
    }
    if ($raw -notmatch 'pollWifiSsid\(40\)' -or $raw -notmatch 'pollWifiSsid\(10\)') {
        throw "macOS helper AppleScript should use separate request/probe wait budgets."
    }
    if ($raw -notmatch 'on currentWifiSsid\(\)' -or $raw -notmatch 'set foundSsid to my currentWifiSsid\(\)' -or $raw -notmatch 'exit repeat') {
        throw "macOS helper AppleScript should poll CoreWLAN and exit the wait loop as soon as SSID is available."
    }
    if ($raw -notmatch 'PO0 Location Permission Helper\.app' -or $raw -notmatch 'osacompile') {
        throw "macOS asset must build and open a stable Location Permission Helper app."
    }
    if ($raw -notmatch 'CFBundleIdentifier' -or $raw -notmatch 'CFBundleExecutable' -or $raw -notmatch 'CFBundlePackageType' -or $raw -notmatch 'PO0HelperSchemaVersion' -or $raw -notmatch 'NSLocationUsageDescription' -or $raw -notmatch 'NSLocationWhenInUseUsageDescription') {
        throw "macOS helper app must include stable bundle identity, launch keys, and location usage descriptions."
    }
    if ($raw -notmatch 'macos_location_permission_helper_app_is_current\(\)') {
        throw "macOS helper app generation must be idempotent for current helper schema."
    }
    if ($raw -notmatch 'macos_location_permission_helper_app_has_po0_identity\(\)' -or $raw -notmatch 'validate_macos_location_permission_helper_app_path\(\)') {
        throw "macOS helper app deletion must validate path and PO0 helper identity before recursive removal."
    }
    if ($raw -notmatch 'create_macos_location_helper_output_file\(\)' -or $raw -notmatch 'cleanup_macos_location_helper_output_file\(\)') {
        throw "macOS helper output path must use managed temp file helpers."
    }
    if ($raw -notmatch 'codesign --force --deep --sign -') {
        throw "macOS helper app should be ad-hoc signed when codesign is available."
    }
    if ($raw -match 'run_macos_location_permission_request_osascript\(\)') {
        throw "macOS asset must not keep the old bare osascript Location Services request helper."
    }
    if ($raw -match '如果看到 redacted') {
        throw "macOS asset must not ask users to look for raw redacted after classifying it as privacy-hidden."
    }
    if ($raw -notmatch 'Location Services') {
        throw "macOS asset lacks Location Services/privacy diagnostic guidance."
    }
    if ($raw -notmatch 'no auto-grant' -or $raw -notmatch 'sudo' -or $raw -notmatch 'TCC') {
        throw "macOS asset must state that it does not auto-grant system permissions."
    }
    $currentWifi = [regex]::Match($raw, '(?ms)^current_wifi_ssid\(\) \{.*?^}')
    if (-not $currentWifi.Success) {
        throw "macOS asset lacks current_wifi_ssid body."
    }
    if ($currentWifi.Value -notmatch 'capture_wifi_ssid_probe macos_location_helper_wifi_ssid') {
        throw "macOS current_wifi_ssid must use the Location Permission Helper as its only probe."
    }
    if ($currentWifi.Value -match 'networksetup|ipconfig|airport|wdutil') {
        throw "macOS current_wifi_ssid must not call shell command Wi-Fi SSID fallbacks."
    }
    foreach ($fnName in @("accepted_wifi_ssid_value", "print_wifi_ssid_permission_guidance", "show_wifi_ssid_permission_help", "show_wifi_ssid_permission_help_interactive", "open_macos_location_services_settings")) {
        $pattern = "(?ms)^" + [regex]::Escape($fnName) + "\(\) \{.*?^}"
        $fn = [regex]::Match($raw, $pattern)
        if (-not $fn.Success) {
            throw "macOS asset lacks $fnName body."
        }
        if ($fn.Value -match '(?m)^\s*(sudo|tccutil|sqlite3|osascript)\s') {
            throw "macOS Wi-Fi SSID diagnostic must not run sudo/tccutil/sqlite3/osascript auto-grant commands in $fnName."
        }
    }
    foreach ($fnName in @("request_macos_location_permission", "ensure_macos_location_permission_helper_app", "macos_location_helper_wifi_ssid", "remove_macos_location_permission_helper_app", "remove_macos_location_permission_helper_app_interactive")) {
        $pattern = "(?ms)^" + [regex]::Escape($fnName) + "\(\) \{.*?^}"
        $fn = [regex]::Match($raw, $pattern)
        if (-not $fn.Success) {
            throw "macOS asset lacks $fnName body."
        }
        if ($fn.Value -match '(?m)^\s*(sudo|tccutil|sqlite3)\s') {
            throw "macOS Wi-Fi SSID permission request must not run sudo/tccutil/sqlite3 commands in $fnName."
        }
    }
    $removeFn = [regex]::Match($raw, '(?ms)^remove_macos_location_permission_helper_app\(\) \{.*?^}')
    if (-not $removeFn.Success) {
        throw "macOS asset lacks remove_macos_location_permission_helper_app body."
    }
    if ($removeFn.Value -notmatch [regex]::Escape('validate_macos_location_permission_helper_app_path "${app_dir}"')) {
        throw "macOS helper removal must validate the computed helper path."
    }
    if ($removeFn.Value -notmatch [regex]::Escape('macos_location_permission_helper_app_has_po0_identity "${app_dir}"')) {
        throw "macOS helper removal must verify PO0 helper bundle identity."
    }
    if ($removeFn.Value -notmatch [regex]::Escape('rm -rf -- "${app_dir}"')) {
        throw "macOS helper removal must recursively remove only the validated helper app path."
    }
    if ($removeFn.Value -match 'rm -rf[^\r\n]*(root|HOME|PO0_OUTBOUND_IP_REPORT_MACOS_HELPER_DIR|app_dir%|\*)') {
        throw "macOS helper removal must not recursively delete helper root, HOME, parent directories, or globs."
    }
}

function Test-WindowsSsidGuard {
    $path = Join-Path $OutputDir "po0-outbound-ip-report.ps1"
    $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    if ($raw -notmatch 'PO0_OUTBOUND_IP_REPORT_[A-Z0-9_]*SSID') {
        throw "Windows asset lacks canonical SSID environment configuration."
    }
    if ($raw -notmatch '(?im)^\s*\[[^\r\n]+\]\s*\$[A-Za-z0-9_]*Ssid[A-Za-z0-9_]*') {
        throw "Windows asset lacks SSID CLI parameter configuration."
    }
    if ($raw -notmatch '(?i)(\$cfg\.[A-Za-z0-9_]*Ssid[A-Za-z0-9_]*|[A-Za-z0-9_]*Ssid[A-Za-z0-9_]*\s*=)') {
        throw "Windows asset lacks persisted SSID configuration."
    }
    if ($raw -notmatch '(?is)(ssid.{0,160}(skip|skipped|跳过)|(skip|skipped|跳过).{0,160}ssid)') {
        throw "Windows asset lacks SSID skip result wording."
    }
    if ($raw -notmatch '(?is)(ssid.{0,160}(summary|log|摘要|日志)|(summary|log|摘要|日志).{0,160}ssid)') {
        throw "Windows asset lacks SSID skip log/status summary wording."
    }
    if ($raw -notmatch '(?is)(ssid.{0,160}(continue|continued|fail|failed|failure|error|unavailable|读取失败|继续上报)|(continue|continued|fail|failed|failure|error|unavailable|读取失败|继续上报).{0,160}ssid)') {
        throw "Windows asset does not state that SSID read failure continues reporting."
    }
    $fn = [regex]::Match($raw, '(?ms)^function Invoke-SelfReportCore\s*\{.*?(?=^function\s+[A-Za-z_][A-Za-z0-9_-]*\s*\{|\z)')
    if (-not $fn.Success) {
        throw "Windows Invoke-SelfReportCore function was not found."
    }
    $guard = [regex]::Match($fn.Value, '(?is)ssid.{0,160}(skip|guard|allow|match|local|跳过|匹配|本地)|(skip|guard|allow|match|local|跳过|匹配|本地).{0,160}ssid')
    $http = [regex]::Match($fn.Value, 'Invoke-WorkerSelfReportCore')
    if (-not $guard.Success) {
        throw "Windows asset lacks an SSID guard inside Invoke-SelfReportCore."
    }
    if (-not $http.Success) {
        throw "Windows asset Worker submit delegation point was not found."
    }
    if ($guard.Index -ge $http.Index) {
        throw "Windows asset SSID guard must run before Worker submit delegation."
    }
}

function Test-OutboundIpReportSsidGuards {
    Test-UnixSsidGuard -FileName "po0-outbound-ip-report.sh" -Platform "Linux/OpenWrt"
    Test-UnixSsidGuard -FileName "po0-outbound-ip-report-macos.sh" -Platform "macOS"
    Test-MacOsWifiSsidDiagnostic
    Test-WindowsSsidGuard
    Test-NoNewLegacySsidAliases
}

function Get-AssetVersion {
    param([string]$FileName)
    $raw = Get-Content -LiteralPath (Join-Path $OutputDir $FileName) -Raw -Encoding UTF8
    if ($FileName.EndsWith(".ps1")) {
        $match = [regex]::Match($raw, '(?m)^\$ScriptVersion\s*=\s*"([^"]+)"')
    } else {
        $match = [regex]::Match($raw, '(?m)^SCRIPT_VERSION="([^"]+)"')
    }
    if (-not $match.Success) { throw "Could not read version from $FileName" }
    return $match.Groups[1].Value
}

function Get-AssetReleaseDate {
    param([string]$FileName)
    $raw = Get-Content -LiteralPath (Join-Path $OutputDir $FileName) -Raw -Encoding UTF8
    if ($FileName.EndsWith(".ps1")) {
        $match = [regex]::Match($raw, '(?m)^\$ScriptReleaseDate\s*=\s*"([^"]+)"')
    } else {
        $match = [regex]::Match($raw, '(?m)^SCRIPT_RELEASE_DATE="([^"]+)"')
    }
    if (-not $match.Success) { throw "Could not read release date from $FileName" }
    return $match.Groups[1].Value
}

function Test-AssetChangelogNotEmpty {
    param([string]$FileName)
    $raw = Get-Content -LiteralPath (Join-Path $OutputDir $FileName) -Raw -Encoding UTF8
    $match = [regex]::Match($raw, '(?ms)^# CHANGELOG_BEGIN\s*(.*?)^# CHANGELOG_END')
    if (-not $match.Success -or -not (($match.Groups[1].Value -replace '(?m)^# ?', '').Trim())) {
        throw "$FileName changelog block is empty."
    }
}

function Test-VersionsConsistent {
    $assets = @(
        "nftables-relay-manager.sh",
        "po0-lan-client.sh",
        "po0-outbound-ip-report.sh",
        "po0-outbound-ip-report-macos.sh",
        "po0-outbound-ip-report.ps1"
    )
    $expected = $ExpectedPo0Version
    foreach ($asset in $assets) {
        $version = Get-AssetVersion -FileName $asset
        if ($version -ne $expected) {
            throw "$asset version $version does not match $expected"
        }
        $date = Get-AssetReleaseDate -FileName $asset
        if ($date -ne $ExpectedPo0ReleaseDate) {
            throw "$asset release date $date is unexpected"
        }
        Test-AssetChangelogNotEmpty -FileName $asset
    }
}

function Test-AssetInventory {
    $expected = @(
        "checksums.txt",
        "nftables-relay-manager.sh",
        "po0-lan-client.sh",
        "po0-outbound-ip-report-macos.sh",
        "po0-outbound-ip-report.ps1",
        "po0-outbound-ip-report.sh"
    ) | Sort-Object
    $actual = Get-ChildItem -LiteralPath $OutputDir -File | ForEach-Object Name | Sort-Object
    if (($expected -join "`n") -ne ($actual -join "`n")) {
        throw "Unexpected PO0 asset inventory. Actual: $($actual -join ', ')"
    }
    $checksumPath = Join-Path $OutputDir "checksums.txt"
    $checksumNames = Get-Content -LiteralPath $checksumPath -Encoding UTF8 |
        ForEach-Object { ($_ -split '\s+', 2)[1] } |
        Sort-Object
    $expectedAssets = $expected | Where-Object { $_ -ne "checksums.txt" }
    if (($checksumNames -join "`n") -ne ($expectedAssets -join "`n")) {
        throw "checksums.txt does not cover the exact asset set."
    }
    foreach ($line in Get-Content -LiteralPath $checksumPath -Encoding UTF8) {
        if ($line -notmatch '^([0-9a-fA-F]{64})\s+(.+)$') {
            throw "Malformed checksum line: $line"
        }
        $expectedHash = $matches[1].ToLowerInvariant()
        $name = $matches[2]
        $assetPath = Join-Path $OutputDir $name
        if (-not (Test-Path -LiteralPath $assetPath)) {
            throw "checksums.txt references missing asset: $name"
        }
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $assetPath).Hash.ToLowerInvariant()
        if ($actualHash -ne $expectedHash) {
            throw "Checksum mismatch for $name"
        }
    }
}

function Test-VersionsMatchTag {
    $tag = $env:GITHUB_REF_NAME
    if (-not $tag) { return }
    if ($env:GITHUB_REF_TYPE -eq "branch" -or $env:GITHUB_REF -like "refs/heads/*") { return }
    $tag = $tag -replace '^po0-scripts-v', 'po0-v'
    if ($tag -ne $ExpectedPo0ReleaseTag) {
        throw "GITHUB_REF_NAME $tag does not match expected PO0 release tag $ExpectedPo0ReleaseTag"
    }
    $match = [regex]::Match($tag, '^po0-v([0-9]{4}\.[0-9]{2}\.[0-9]{2})\.([0-9]+)$')
    if (-not $match.Success) {
        throw "GITHUB_REF_NAME is set but is not a PO0 release tag: $tag"
    }
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
Test-EgernSsidGuard
Test-EgernOfficialChannel
Test-LanWorkerOfficialChannel

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
Test-AssetInventory
Test-WindowsCanonicalPath
Test-UnixOutboundIpReportCanonicalPath -FileName "po0-outbound-ip-report.sh" -Platform "Linux/OpenWrt"
Test-UnixOutboundIpReportCanonicalPath -FileName "po0-outbound-ip-report-macos.sh" -Platform "macOS"
Test-MacOsLaunchdCanonicalPath
Test-LegacyNameAllowlist
Test-OutboundIpReportSsidGuards
Test-VersionsConsistent
Test-VersionsMatchTag

function Get-BashCommand {
    if ($env:OS -eq "Windows_NT" -or $IsWindows -eq $true) {
        $gitBashCandidates = @(
            "C:\Program Files\Git\bin\bash.exe",
            "C:\Program Files (x86)\Git\bin\bash.exe",
            (Join-Path $env:LOCALAPPDATA "Programs\Git\bin\bash.exe")
        )
        foreach ($candidate in $gitBashCandidates) {
            if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
        }

        $bashCandidates = @(Get-Command bash -All -ErrorAction SilentlyContinue)
        foreach ($candidate in $bashCandidates) {
            if ($candidate.Source -and $candidate.Source -notlike "$env:WINDIR\System32\bash.exe") {
                return $candidate.Source
            }
        }
        return ""
    }

    $bash = Get-Command bash -ErrorAction SilentlyContinue
    if ($bash) { return $bash.Source }
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

function Invoke-BashToolScript {
    param([string]$RelativePath)
    $bash = Get-BashCommand
    if (-not $bash) {
        Write-Warning "bash not found; skipping Bash tool test $RelativePath"
        return
    }
    $path = Join-Path $RepoRoot $RelativePath
    $bashPath = ConvertTo-BashPath -Path $path
    Write-Host "Checking bash $RelativePath"
    & $bash $bashPath | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: bash $RelativePath"
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

Write-Host "Checking node tools/po0/test-egern-ssid-guard.mjs"
& node (Join-Path $RepoRoot "tools/po0/test-egern-ssid-guard.mjs") | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "Command failed: node tools/po0/test-egern-ssid-guard.mjs"
}
Write-Host "Checking node tools/po0/test-egern-official-report.mjs"
& node (Join-Path $RepoRoot "tools/po0/test-egern-official-report.mjs") | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "Command failed: node tools/po0/test-egern-official-report.mjs"
}
Invoke-BashToolScript "tools/po0/test-macos-ssid-diagnostic.sh"
Invoke-BashToolScript "tools/po0/test-macos-official-report.sh"
Invoke-BashToolScript "tools/po0/test-self-report-refresh-policy.sh"
Invoke-BashToolScript "tools/po0/test-linux-multi-wan-report.sh"
Invoke-BashToolScript "tools/po0/test-linux-official-http.sh"
Invoke-BashToolScript "tools/po0/test-linux-official-report.sh"
Invoke-BashToolScript "tools/po0/test-linux-official-cli.sh"
Invoke-BashToolScript "tools/po0/test-client-settings-input.sh"
Invoke-BashToolScript "tools/po0/test-lan-worker-official-report.sh"
Invoke-BashToolScript "tools/po0/test-official-firewall-core.sh"
Invoke-BashToolScript "tools/po0/test-openwrt-official-adapter.sh"
Invoke-BashToolScript "tools/po0/test-openwrt-service.sh"
Invoke-BashToolScript "tools/po0/test-openwrt-luci-official-ui.sh"
Invoke-BashToolScript "tools/po0/test-openwrt-apk-layout.sh"
Invoke-BashToolScript "tools/po0/test-lan-worker-stash-report.sh"
Invoke-BashToolScript "tools/po0/test-manager-client-ip-cidr-prefix.sh"
Invoke-BashToolScript "tools/po0/test-manager-nft-atomic-reload.sh"
Invoke-BashToolScript "tools/po0/test-manager-resource-upload.sh"
Invoke-BashToolScript "tools/po0/test-debian-reinstall-grub.sh"
& node (Join-Path $RepoRoot "tools/po0/test-release-version-tags.mjs") | Out-Host
if ($LASTEXITCODE -ne 0) { throw "Release version tag checks failed." }
Write-Host "Checking node tools/po0/test-loon-report.js"
& node (Join-Path $RepoRoot "tools/po0/test-loon-report.js") | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "Command failed: node tools/po0/test-loon-report.js"
}
Write-Host "Checking node tools/po0/test-stash-report.js"
& node (Join-Path $RepoRoot "tools/po0/test-stash-report.js") | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "Command failed: node tools/po0/test-stash-report.js"
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

Write-Host "Checking PowerShell tools/po0/test-windows-refresh-policy.ps1"
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoRoot "tools/po0/test-windows-refresh-policy.ps1") | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "Command failed: tools/po0/test-windows-refresh-policy.ps1"
}
Write-Host "Checking PowerShell tools/po0/test-windows-official-report.ps1"
$windowsOfficialTest = Join-Path $RepoRoot "tools/po0/test-windows-official-report.ps1"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $windowsOfficialTest | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "Command failed: tools/po0/test-windows-official-report.ps1"
}

Write-Host "PO0 asset checks passed."
