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
# pwsh 7.5+ keeps an empty variable after SetEnvironmentVariable(name, $null); remove it instead.
function Set-FixtureNoColor($Value) { if ($null -eq $Value) { Remove-Item Env:NO_COLOR -ErrorAction SilentlyContinue } else { $env:NO_COLOR = $Value } }
function Invoke-Po0OfficialHttpRequest { throw 'renderer attempted HTTP' }
function Get-Po0DisplayWidth { return 100 }
# Captured information records carry Write-Host colors out of band, but inline bold SGR would
# enter the captured text whenever this test runs on a real VT console. Plain-text captures pin
# bold off; the palette regression at the end drives the real helper explicitly.
$script:RealUiBold = ${function:Test-Po0UiBold}
function Test-Po0UiBold { return $false }
$script:Po0FirewallTokens = 'pgnfw_fixture_a,pgnfw_fixture_b'
$script:Po0FirewallNames = '很长的中文账号名称以及 Office Wi-Fi;第二账号;失败账号'
foreach ($quota in @(5,7,10)) {
    $entries = @([pscustomobject]@{Ip='192.0.2.18/24';Slot='0'}, [pscustomobject]@{Ip='203.0.113.25/24';Slot=[string]($quota-1)})
    $account = New-Po0FirewallAccountState -Index 1 -CurrentIp '203.0.113.25/24' -Limit $quota -Entries $entries -Status ok
    $state = [pscustomobject]@{Accounts=@($account); LastCheckedAt=1793341928; ConfigurationId=Get-Po0DisplayConfigurationId}
    $text = Capture { Show-Po0FirewallTable $state '只读查询' }
    1..$quota | ForEach-Object { Assert-Contains $text "#$_" }
    Assert-Contains $text '203.0.113.25/24'
    Assert-Contains $text '当前出口'
    Assert-Contains $text "占用 2/$quota"
    Assert-Absent $text ([string][char]27)
    Assert-Absent $text 'pgnfw_'
}
$unknown = New-Po0FirewallAccountState -Index 2 -CurrentIp '198.51.100.25/24' -Limit 7 -Entries @([pscustomobject]@{Ip='192.0.2.2/24';Slot=''}) -Status ok
$failed = New-Po0FirewallAccountState -Index 3 -FixedSlot '9'
$state.Accounts = @($account, $unknown, $failed)
function Get-Po0DisplayWidth { return 35 }
$text = Capture { Show-Po0FirewallTable $state '上报结果' -Failed }
foreach ($value in @('失败账号','未编号','本次未取得白名单','      203.0.113.25/24','未放行','操作失败')) { Assert-Contains $text $value }
$entries = @(0..9 | ForEach-Object { [pscustomobject]@{Ip="203.0.113.$($_+1)/24";Slot=[string]$_} })
$account = New-Po0FirewallAccountState -Index 1 -CurrentIp '203.0.113.10/24' -Limit 10 -Entries $entries -Status ok
$state.Accounts = @($account)
$state.LastCheckedAt = 0
$text = Capture { Show-Po0FirewallTable $state }
Assert-Contains $text '已放行'
Assert-Contains $text '剩余 0 个'
Assert-Contains $text '尚无记录'
$unknown.CurrentIp = '192.0.2.2/24'
$state.Accounts = @($unknown)
$text = Capture { Show-Po0FirewallTable $state }
Assert-Absent $text '空闲'
Assert-Contains $text '当前出口'
$script:FixtureState = $state
function Get-Po0FirewallState { return $script:FixtureState }
$text = Capture { Show-Po0FirewallCached }
Assert-Contains $text '上次结果 / 本地记录'
$script:Po0FirewallTokens = 'pgnfw_fixture_b,pgnfw_fixture_a'
$text = Capture { Show-Po0FirewallCached }
Assert-Contains $text '账号配置已更新'
$script:Po0FirewallTokens = 'pgnfw_fixture_a@9,pgnfw_fixture_b'
$text = Capture { Show-Po0FirewallCached }
Assert-Contains $text '账号配置已更新'
$script:FixtureState = [pscustomobject]@{Accounts=@($account);LastOfficialAttempt=123}
$text = Capture { Show-Po0FirewallCached }
Assert-Contains $text '暂无新版记录'
$savedColor = [Environment]::GetEnvironmentVariable('NO_COLOR')
${function:Test-Po0UiBold} = $script:RealUiBold
try {
    $env:NO_COLOR='1'
    if (Test-Po0UiColor) { throw 'NO_COLOR ignored' }
    if (Test-Po0UiBold) { throw 'NO_COLOR ignored for bold' }
    $text = Capture { Write-MenuItem 0 '退出'; Show-Po0FirewallTable $state }
    Assert-Absent $text ([string][char]27)
} finally {
    Set-FixtureNoColor $savedColor
    function script:Test-Po0UiBold { return $false }
}
$script:Po0FirewallScheduledRun=$true
$result = [pscustomobject]@{Accounts=@($account);Succeeded=$true}
$text = Capture { Show-Po0FirewallLive $result '后台' }
if ($text.Trim()) { throw 'background rendered table' }
Write-Host 'PASS: Windows terminal full-slot rendering, cache identity and output modes.'

# The real-world response shape has numbered and unnumbered records together.
# Do not multiply it into a table of phantom positions; retain every IP exactly once per account.
function Get-Po0DisplayWidth { return 80 }
$mixed = New-Po0FirewallAccountState -Index 1 -CurrentIp '203.0.113.25/24' -Limit 7 -Status ok -Entries @(
    [pscustomobject]@{Slot='0';Ip='192.0.2.18/24'},[pscustomobject]@{Slot='';Ip='203.0.113.25/24'},[pscustomobject]@{Slot='';Ip='198.51.100.42/24'})
$state.Accounts=@($mixed)
$text=Capture { Show-Po0FirewallTable $state }
foreach($value in @('#1','未编号','192.0.2.18/24','203.0.113.25/24','198.51.100.42/24','占用 3/7','剩余 4 个')) { Assert-Contains $text $value }
foreach($value in @('#2','#7','空闲','未知（','失败 0','更新 0')) { Assert-Absent $text $value }
if (($text.Split(@('说明：'),[StringSplitOptions]::None)).Count -ne 2) { throw 'unknown-slot explanation repeated' }
if ((Get-Po0CellWidth '槽位') -ne 4 -or (Get-Po0CellWidth (Format-Po0Cell '未编号' 8)) -ne 8) { throw 'CJK alignment broken' }
if ((Format-Po0Duration 1800) -ne '30 分钟') { throw 'duration formatting broken' }
# Verify the actual interactive report path removes duplicate successes, retains errors,
# and still records its completion in the plain-text log.
. ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $src '010-platform-paths-logging-notification.ps1'), [Text.Encoding]::UTF8)))
function Test-Po0RichOutput { return $true }
function Write-SelfReportLogLine { param($Level,$Message) $script:LogMessages += $Message }
$script:LogMessages=@()
$script:Po0FirewallScheduledRun=$false
$script:Po0UiRendered=$false
$result=[pscustomobject]@{Accounts=@($mixed);Succeeded=$true}
$text=Capture { Show-Po0FirewallLive $result '上报结果'; Write-SelfReportCompleted '检查完成。' }
Assert-Absent $text '已完成：'
if ($script:LogMessages.Count -ne 1) { throw 'completion log was lost' }
$script:Po0UiRendered=$false
$text=Capture { Write-SelfReportCompleted '本轮跳过。' }
Assert-Contains $text '本轮跳过'
Write-Host 'PASS: sparse responses, CJK alignment, readable intervals and single completion.'

# Forced-color palette: record Write-Host colors directly instead of relying on a console.
# Hierarchy uses bold; informative text keeps the default foreground; DarkGray is divider-only.
$esc = [string][char]27
$script:HostWrites = New-Object System.Collections.Generic.List[object]
function Write-Host {
    param([Parameter(Position = 0)]$Object = '', $ForegroundColor = $null, [switch]$NoNewline)
    $script:HostWrites.Add([pscustomobject]@{ Text = [string]$Object; Color = [string]$ForegroundColor })
}
function Test-Po0UiColor { return (-not (Test-Path Env:NO_COLOR)) }
function Get-HostWrite([string]$Needle) {
    $match = @($script:HostWrites | Where-Object { $_.Text.Trim() -eq $Needle })
    if (-not $match.Count) { $match = @($script:HostWrites | Where-Object { $_.Text.Contains($Needle) }) }
    if (-not $match.Count) { throw "No write: $Needle" }
    return $match[0]
}
function Assert-WriteColor([string]$Needle, [string]$Color) {
    $actual = (Get-HostWrite $Needle).Color
    if ($actual -ne $Color) { throw "Color for ${Needle}: expected '$Color', got '$actual'" }
}
function Assert-ReadablePalette {
    foreach ($write in $script:HostWrites) {
        if ($write.Color -eq 'DarkGray' -and $write.Text.Trim() -notmatch '^[─-]+$') { throw "DarkGray text: $($write.Text)" }
        if ($write.Color -in @('White', 'Gray')) { throw "Forced $($write.Color): $($write.Text)" }
    }
}
# The caller's NO_COLOR is process-local here; clear it so forced-color assertions are real.
$savedColor = [Environment]::GetEnvironmentVariable('NO_COLOR')
Set-FixtureNoColor $null
function Test-Po0UiBold { return (Test-Po0UiColor) }
$script:HostWrites.Clear()
Write-Title 'PO0 防火墙' 'v9.9.9'
Write-PanelSection '分组标题'
Write-PanelRow '行标签' '普通值'
Write-PanelNote '说明文字'
Write-MenuItem 1 '菜单项'
Write-MenuItem 0 '返回'
Assert-ReadablePalette
Assert-WriteColor 'PO0 防火墙' 'Cyan'
Assert-WriteColor 'v9.9.9' ''
if ((Get-HostWrite '分组标题').Text -ne "$esc[1m  分组标题$esc[0m") { throw 'section title is not bold' }
Assert-WriteColor '分组标题' ''
Assert-WriteColor '行标签' ''
Assert-WriteColor '普通值' ''
Assert-WriteColor '说明文字' ''
Assert-WriteColor '[1]' 'Cyan'
Assert-WriteColor '[0]' ''
if (@($script:HostWrites | Where-Object { $_.Color -eq 'DarkGray' }).Count -ne 1) { throw 'divider lost its decoration' }
# Without VT support the section title falls back to the default foreground, never a color.
$script:HostWrites.Clear()
function Test-Po0UiBold { return $false }
Write-PanelSection '分组标题'
if ((Get-HostWrite '分组标题').Text -ne '  分组标题') { throw 'section fallback emitted control codes' }
Assert-WriteColor '分组标题' ''
$cases = @(
    @('运行中', '', 'Green'), @('已启用（每 10 分钟）', '', 'Green'), @('已安装 · 就绪', '', 'Green'),
    @('已暂停', '', 'Yellow'), @('未配置', '', 'Yellow'), @('已放行 · 等待下次检查', '', 'Yellow'),
    @('上报失败', '', 'Red'), @('已启用，但最近一次失败', '', 'Red'), @('每 600 秒', '', ''),
    @('已启用', 'warn', 'Yellow'), @('失败', 'ok', 'Green'), @('已启用', 'plain', ''), @('未配置', 'bogus', 'Yellow'))
foreach ($case in $cases) {
    $script:HostWrites.Clear()
    if ($case[1]) { Write-PanelStatusRow '状态' $case[0] $case[1] } else { Write-PanelStatusRow -Label '状态' -Value $case[0] }
    if ($script:HostWrites[0].Text -ne (Format-Po0PanelLabel '状态')) { throw "status row layout changed: $($case[0])" }
    if ($script:HostWrites[1].Text -ne $case[0] -or $script:HostWrites[1].Color -ne $case[2]) { throw "status tone: $($case[0])/$($case[1])" }
}
function Get-Po0DisplayWidth { return 100 }
function Test-Po0UiBold { return (Test-Po0UiColor) }
$hit = New-Po0FirewallAccountState -Index 1 -CurrentIp '203.0.113.25/24' -Limit 7 -Status ok -Entries @(
    [pscustomobject]@{Ip='192.0.2.18/24';Slot='0'}, [pscustomobject]@{Ip='203.0.113.25/24';Slot='6'})
$miss = New-Po0FirewallAccountState -Index 2 -CurrentIp '198.51.100.25/24' -Limit 7 -Status ok -Entries @([pscustomobject]@{Ip='192.0.2.2/24';Slot='1'})
$fail = New-Po0FirewallAccountState -Index 3 -FixedSlot '9'
$palette = [pscustomobject]@{Accounts=@($hit, $miss, $fail); LastCheckedAt=1793341928; ConfigurationId=''}
$script:HostWrites.Clear()
Show-Po0FirewallTable $palette '上报结果' -Failed
Assert-ReadablePalette
$header = Get-HostWrite '槽位'
if (-not $header.Text.StartsWith("$esc[1m") -or $header.Color) { throw 'slot header is not bold default text' }
Assert-WriteColor '空闲' ''
Assert-WriteColor '已放行' 'Green'
Assert-WriteColor '未放行' 'Yellow'
Assert-WriteColor '操作失败' 'Red'
Assert-WriteColor '第二账号' 'Cyan'
Assert-WriteColor '检查时间' ''
Assert-WriteColor '占用 2/7' ''
$script:Po0FirewallTokens = 'pgnfw_fixture_a,pgnfw_fixture_b'
$script:FixtureState = [pscustomobject]@{Accounts=@($hit); LastCheckedAt=1793341928; ConfigurationId=(Get-Po0DisplayConfigurationId)}
$script:HostWrites.Clear(); Show-Po0FirewallCached -Summary
Assert-WriteColor '1/1 已放行' 'Green'
$script:FixtureState.Accounts = @($hit, $miss)
$script:HostWrites.Clear(); Show-Po0FirewallCached -Summary
Assert-WriteColor '1/2 已放行' 'Yellow'
$script:Po0FirewallTokens = 'pgnfw_fixture_b'
$script:HostWrites.Clear(); Show-Po0FirewallCached -Summary
Assert-WriteColor '账号配置已更新，等待下次检查' 'Yellow'
$script:FixtureState = [pscustomobject]@{Accounts=@($hit)}
$script:HostWrites.Clear(); Show-Po0FirewallCached -Summary
Assert-WriteColor '暂无新版记录，检查后显示' 'Yellow'
# The real bold helper must also honor NO_COLOR through the color gate.
${function:Test-Po0UiBold} = $script:RealUiBold
try {
    $env:NO_COLOR = '1'
    $script:HostWrites.Clear()
    Write-Title 'PO0 防火墙' 'v9.9.9'; Write-PanelSection '分组标题'; Write-PanelStatusRow '状态' '上报失败'; Write-MenuItem 1 '菜单项'
    Show-Po0FirewallTable $palette '上报结果' -Failed
    foreach ($write in $script:HostWrites) {
        if ($write.Color -or $write.Text.Contains($esc)) { throw "NO_COLOR output styled: $($write.Text)" }
    }
} finally { Set-FixtureNoColor $savedColor }
Remove-Item function:Write-Host
Write-Host 'PASS: readable palette, status tones and NO_COLOR plain text.'
