#requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$src = Join-Path $repoRoot 'scripts/po0/relay/self-report/windows/src'
foreach ($part in @('000-runtime-parameters.ps1','020-ui-rendering.ps1','057-channel-settings.ps1','058-official-firewall.ps1')) {
    # Source fragments are UTF-8; the release builder supplies the PS 5.1 BOM.
    . ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $src $part), [Text.Encoding]::UTF8)))
}
$ErrorActionPreference = 'Stop'
function Assert-Contains([string]$Text, [string]$Value) { if (-not $Text.Contains($Value)) { throw "Missing: $Value" } }
function Assert-Absent([string]$Text, [string]$Value) { if ($Text.Contains($Value)) { throw "Unexpected: $Value" } }
function Capture([scriptblock]$Action) { return (& $Action 6>&1 | Out-String -Width 300) }
function Invoke-Po0OfficialHttpRequest { throw 'renderer attempted HTTP' }
function Get-Po0DisplayWidth { return 100 }
$script:Po0FirewallTokens = 'pgnfw_fixture_a,pgnfw_fixture_b'
$script:Po0FirewallNames = '很长的中文账号名称以及 Office Wi-Fi;第二账号;失败账号'
foreach ($quota in @(5,7,10)) {
    $entries = @([pscustomobject]@{Ip='192.0.2.18/24';Slot='0'}, [pscustomobject]@{Ip='203.0.113.25/24';Slot=[string]($quota-1)})
    $account = New-Po0FirewallAccountState -Index 1 -CurrentIp '203.0.113.25/24' -Limit $quota -Entries $entries -Status ok
    $state = [pscustomobject]@{Accounts=@($account); LastCheckedAt=1793341928; ConfigurationId=Get-Po0DisplayConfigurationId}
    $text = Capture { Show-Po0FirewallTable $state '只读查询' }
    1..$quota | ForEach-Object { Assert-Contains $text "#$_" }
    Assert-Contains $text '203.0.113.25/24'
    Assert-Contains $text '当前命中'
    Assert-Contains $text "占用 2/$quota"
    Assert-Absent $text ([string][char]27)
    Assert-Absent $text 'pgnfw_'
}
$unknown = New-Po0FirewallAccountState -Index 2 -CurrentIp '198.51.100.25/24' -Limit 7 -Entries @([pscustomobject]@{Ip='192.0.2.2/24';Slot=''}) -Status ok
$failed = New-Po0FirewallAccountState -Index 3 -FixedSlot '9'
$state.Accounts = @($account, $unknown, $failed)
function Get-Po0DisplayWidth { return 35 }
$text = Capture { Show-Po0FirewallTable $state '上报结果' -Failed }
foreach ($value in @('失败账号','槽位未知','未知（有未编号记录）','占用未知','    203.0.113.25/24','未放行','操作失败')) { Assert-Contains $text $value }
$entries = @(0..9 | ForEach-Object { [pscustomobject]@{Ip="203.0.113.$($_+1)/24";Slot=[string]$_} })
$account = New-Po0FirewallAccountState -Index 1 -CurrentIp '203.0.113.10/24' -Limit 10 -Entries $entries -Status ok
$state.Accounts = @($account)
$state.LastCheckedAt = 0
$text = Capture { Show-Po0FirewallTable $state }
Assert-Contains $text '已放行'
Assert-Contains $text '剩余 0 个'
Assert-Contains $text '检查时间 未知'
$unknown.CurrentIp = '192.0.2.2/24'
$state.Accounts = @($unknown)
$text = Capture { Show-Po0FirewallTable $state }
Assert-Absent $text '空闲'
Assert-Contains $text '当前命中'
$script:FixtureState = $state
function Get-Po0FirewallState { return $script:FixtureState }
$text = Capture { Show-Po0FirewallCached }
Assert-Contains $text '上次结果（本地缓存）'
$script:Po0FirewallTokens = 'pgnfw_fixture_b,pgnfw_fixture_a'
$text = Capture { Show-Po0FirewallCached }
Assert-Contains $text '缓存未匹配'
$script:Po0FirewallTokens = 'pgnfw_fixture_a@9,pgnfw_fixture_b'
$text = Capture { Show-Po0FirewallCached }
Assert-Contains $text '缓存未匹配'
$script:FixtureState = [pscustomobject]@{Accounts=@($account);LastOfficialAttempt=123}
$text = Capture { Show-Po0FirewallCached }
Assert-Contains $text '缓存未匹配'
$savedColor = [Environment]::GetEnvironmentVariable('NO_COLOR')
try {
    $env:NO_COLOR='1'
    if (Test-Po0UiColor) { throw 'NO_COLOR ignored' }
    $text = Capture { Write-MenuItem 0 '退出'; Show-Po0FirewallTable $state }
    Assert-Absent $text ([string][char]27)
} finally { [Environment]::SetEnvironmentVariable('NO_COLOR', $savedColor) }
$script:Po0FirewallScheduledRun=$true
$result = [pscustomobject]@{Accounts=@($account);Succeeded=$true}
$text = Capture { Show-Po0FirewallLive $result '后台' }
if ($text.Trim()) { throw 'background rendered table' }
Write-Host 'PASS: Windows terminal full-slot rendering, cache identity and output modes.'
