function Test-PublicIPv4 {
    param([string]$Ip)
    if ($Ip -notmatch "^(\d{1,3}\.){3}\d{1,3}$") { return $false }
    $octets = $Ip.Split(".") | ForEach-Object { [int]$_ }
    if (($octets | Where-Object { $_ -lt 0 -or $_ -gt 255 }).Count -gt 0) { return $false }
    if ($octets[0] -in @(0, 10, 127)) { return $false }
    if ($octets[0] -ge 224) { return $false }
    if ($octets[0] -eq 100 -and $octets[1] -ge 64 -and $octets[1] -le 127) { return $false }
    if ($octets[0] -eq 169 -and $octets[1] -eq 254) { return $false }
    if ($octets[0] -eq 172 -and $octets[1] -ge 16 -and $octets[1] -le 31) { return $false }
    if ($octets[0] -eq 192 -and $octets[1] -eq 168) { return $false }
    if ($octets[0] -eq 198 -and $octets[1] -ge 18 -and $octets[1] -le 19) { return $false }
    return $true
}

function Get-FirstPublicIPv4FromText {
    param([string]$Text)
    foreach ($match in [regex]::Matches($Text, "\b(\d{1,3}(?:\.\d{1,3}){3})\b")) {
        $ip = $match.Groups[1].Value
        if (Test-PublicIPv4 $ip) { return $ip }
    }
    return $null
}

function Invoke-HttpNoProxy {
    param([string]$Url)
    Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.UseProxy = $false
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(20)
    try {
        return $client.GetStringAsync($Url).GetAwaiter().GetResult()
    } finally {
        $client.Dispose()
        $handler.Dispose()
    }
}

function Get-IpCheckStatePath {
    if ($env:LOCALAPPDATA) {
        return (Join-Path $env:LOCALAPPDATA "PO0\self-report-ip-check-index.txt")
    }
    if ($env:TEMP) {
        return (Join-Path $env:TEMP "po0-self-report-ip-check-index.txt")
    }
    return "po0-self-report-ip-check-index.txt"
}

function Get-IpCheckIndex {
    param([int]$Count)
    if ($Count -le 0) { return 0 }
    $path = Get-IpCheckStatePath
    try {
        if (Test-Path -LiteralPath $path) {
            $raw = (Get-Content -LiteralPath $path -Raw) -replace "[^\d]", ""
            if ($raw) { return ([int]$raw % $Count) }
        }
    } catch {}
    return 0
}

function Set-IpCheckIndex {
    param([int]$Index, [int]$Count)
    if ($Count -le 0) { return }
    $path = Get-IpCheckStatePath
    try {
        $dir = Split-Path -Parent $path
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Set-Content -LiteralPath $path -Value ([string]($Index % $Count)) -Encoding ASCII
    } catch {}
}

function Get-OutboundIPv4 {
    $urls = @()
    if ($script:IpCheckUrls.Count -gt 0) {
        $urls += $script:IpCheckUrls
    } else {
        $urls += $script:IpCheckUrl
        $urls += "https://mail.163.com/fgw/mailsrv-ipdetail/detail"
        $urls += "https://api.live.bilibili.com/client/v1/Ip/getInfoNew"
        $urls += "https://ipservice.ws.126.net/locate/api/getLocByIp"
        $urls += "https://r.inews.qq.com/api/ip2city?otype=json"
        $urls += "https://data.video.iqiyi.com/v.f4v"
        $urls += "https://ip.apps.cntv.cn/whereis?client=json"
        $urls += "https://myip.ipip.net/json"
    }
    $count = $urls.Count
    if ($count -le 0) { throw "未配置公网 IPv4 探测地址。" }
    $start = Get-IpCheckIndex -Count $count
    for ($i = 0; $i -lt $count; $i++) {
        $idx = ($start + $i) % $count
        $url = $urls[$idx]
        $cleanUrl = ($url | Out-String).Trim()
        if (-not $cleanUrl) { continue }
        try {
            $body = Invoke-HttpNoProxy -Url $cleanUrl
            $ip = Get-FirstPublicIPv4FromText -Text $body
            if ($ip) {
                Set-IpCheckIndex -Index (($idx + 1) % $count) -Count $count
                return $ip
            }
        } catch {
            Write-Verbose "公网 IPv4 探测失败 ${cleanUrl}: $($_.Exception.Message)"
        }
    }
    Set-IpCheckIndex -Index (($start + 1) % $count) -Count $count
    throw "未能探测到当前公网出口 IPv4。"
}
