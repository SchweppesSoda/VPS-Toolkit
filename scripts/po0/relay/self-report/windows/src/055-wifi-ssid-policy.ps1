function ConvertTo-WifiSsidPolicyList {
    param([AllowNull()]$Value)
    $items = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Value) { return @() }
    foreach ($entry in @($Value)) {
        if ($null -eq $entry) { continue }
        foreach ($part in ([string]$entry -split ";")) {
            $trimmed = $part.Trim()
            if ($trimmed) {
                $items.Add($trimmed)
            }
        }
    }
    return $items.ToArray()
}

function Format-WifiSsidPolicyList {
    param([string[]]$Ssids)
    $items = @($Ssids | Where-Object { $_ })
    if ($items.Count -le 0) { return "未配置" }
    return ($items -join "; ")
}

function Get-CurrentWifiSsids {
    $items = New-Object System.Collections.Generic.List[string]
    try {
        $output = & netsh wlan show interfaces 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw (($output | Out-String).Trim())
        }
        foreach ($line in @($output)) {
            $text = [string]$line
            if ($text -match '^\s*SSID\s*:\s*(.*)$') {
                $ssid = $matches[1].Trim()
                if ($ssid) {
                    $items.Add($ssid)
                }
            }
        }
        return [pscustomobject]@{
            Succeeded = $true
            Ssids = @($items.ToArray())
            Error = ""
        }
    } catch {
        return [pscustomobject]@{
            Succeeded = $false
            Ssids = @()
            Error = $_.Exception.Message
        }
    }
}

function Get-WifiSsidPolicyState {
    $skipSsids = @($script:SkipWifiSsids | Where-Object { $_ })
    $current = Get-CurrentWifiSsids
    $matchedSsid = ""
    if ($current.Succeeded -and $skipSsids.Count -gt 0) {
        foreach ($ssid in @($current.Ssids)) {
            foreach ($skipSsid in $skipSsids) {
                if ([System.String]::Equals($ssid, $skipSsid, [System.StringComparison]::Ordinal)) {
                    $matchedSsid = $ssid
                    break
                }
            }
            if ($matchedSsid) { break }
        }
    }
    return [pscustomobject]@{
        Enabled = ($skipSsids.Count -gt 0)
        SkipWifiSsids = @($skipSsids)
        ReadSucceeded = [bool]$current.Succeeded
        CurrentSsids = @($current.Ssids)
        Error = [string]$current.Error
        Matched = [bool]$matchedSsid
        MatchedSsid = $matchedSsid
    }
}

function Format-CurrentWifiSsidStatus {
    $state = Get-WifiSsidPolicyState
    if (-not $state.ReadSucceeded) {
        return "读取失败，按 fail-open 继续上报：$($state.Error)"
    }
    if ($state.CurrentSsids.Count -le 0) {
        return "未连接或未读取到 SSID"
    }
    if ($state.Matched) {
        return (($state.CurrentSsids -join "; ") + "（命中跳过规则）")
    }
    return ($state.CurrentSsids -join "; ")
}

function Read-WifiSsidPolicySetting {
    $current = Format-WifiSsidPolicyList -Ssids $script:SkipWifiSsids
    if ($script:SkipWifiSsids.Count -gt 0) {
        $value = Read-Host "命中后跳过上报的 Wi-Fi SSID（分号分隔，回车保留，输入 - 清空） [$current]"
        if ($null -eq $value -or -not $value.Trim()) { return }
        if ($value.Trim() -eq "-") {
            $script:SkipWifiSsids = @()
        } else {
            $script:SkipWifiSsids = ConvertTo-WifiSsidPolicyList -Value $value
        }
    } else {
        $value = Read-Host "命中后跳过上报的 Wi-Fi SSID（分号分隔，可空）"
        if ($null -eq $value) { $value = "" }
        $script:SkipWifiSsids = ConvertTo-WifiSsidPolicyList -Value $value
    }
}

function Write-SelfReportSkippedForWifiSsid {
    param($State)
    $message = "已跳过：当前 Wi-Fi SSID `"$($State.MatchedSsid)`" 命中跳过规则；未探测公网 IP，未上报。"
    Write-Host "PO0 Outbound IP Report $message" -ForegroundColor Yellow
    Write-SelfReportLogLine "SKIP" "PO0 Outbound IP Report $message"
}

$script:SkipWifiSsidsExplicit = [bool]$PSBoundParameters.ContainsKey("SkipWifiSsids")
if ($script:SkipWifiSsidsExplicit) {
    $script:SkipWifiSsids = ConvertTo-WifiSsidPolicyList -Value $SkipWifiSsids
} elseif ($env:PO0_OUTBOUND_IP_REPORT_SKIP_WIFI_SSIDS) {
    $script:SkipWifiSsids = ConvertTo-WifiSsidPolicyList -Value $env:PO0_OUTBOUND_IP_REPORT_SKIP_WIFI_SSIDS
} else {
    $script:SkipWifiSsids = @()
}
$script:ForceReport = [bool]$ForceReport
