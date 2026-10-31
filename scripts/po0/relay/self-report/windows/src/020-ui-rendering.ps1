$script:Po0UiRendered = $false

function Get-Po0CellWidth {
    param([string]$Text)
    $width = 0
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $code = [char]::ConvertToUtf32($Text, $i)
        if ($code -gt 65535) { $i++ }
        $category = [Globalization.CharUnicodeInfo]::GetUnicodeCategory([char]::ConvertFromUtf32($code), 0)
        if ($category -in @([Globalization.UnicodeCategory]::NonSpacingMark, [Globalization.UnicodeCategory]::Format)) { continue }
        if (($code -ge 0x1100 -and $code -le 0x115f) -or ($code -ge 0x2e80 -and $code -le 0xa4cf) -or ($code -ge 0xac00 -and $code -le 0xd7a3) -or ($code -ge 0xf900 -and $code -le 0xfaff) -or ($code -ge 0xfe10 -and $code -le 0xfe6f) -or ($code -ge 0xff01 -and $code -le 0xff60) -or ($code -ge 0xffe0 -and $code -le 0xffe6) -or $code -ge 0x1f300) { $width += 2 } else { $width++ }
    }
    return $width
}

function Format-Po0Cell {
    param([string]$Text, [int]$Width)
    return $Text + (' ' * [Math]::Max(0, $Width - (Get-Po0CellWidth $Text)))
}

function Test-Po0UiColor {
    return (-not $script:Po0FirewallScheduledRun -and -not [Console]::IsOutputRedirected -and -not (Test-Path Env:NO_COLOR) -and $env:TERM -ne 'dumb')
}

function Test-Po0RichOutput {
    return (-not $script:Po0FirewallScheduledRun -and -not [Console]::IsOutputRedirected)
}

# Palette must stay readable on PS 5.1 blue, Windows Terminal dark and light schemes.
# Hierarchy uses bold and spacing; DarkGray is reserved for divider lines, and White or
# Gray are never forced because they vanish on light backgrounds. Write-Host has no bold,
# so bold uses an inline SGR only when colors are on and the host renders VT sequences.
function Test-Po0UiBold {
    if (-not (Test-Po0UiColor)) { return $false }
    try { return [bool]$Host.UI.SupportsVirtualTerminal } catch { return $false }
}

function Write-Po0UiText {
    param([string]$Text, [string]$Color = '', [switch]$NoNewline, [switch]$Bold)
    if ($Bold -and $Text -and (Test-Po0UiBold)) { $Text = '{0}[1m{1}{0}[0m' -f [char]27, $Text }
    if ($Color -and (Test-Po0UiColor)) { Write-Host $Text -ForegroundColor $Color -NoNewline:$NoNewline }
    else { Write-Host $Text -NoNewline:$NoNewline }
}

function Get-Po0DisplayWidth {
    try { if ([Console]::WindowWidth -gt 0) { return [Console]::WindowWidth } } catch {}
    return 80
}

function Write-PanelDivider {
    $width = [Math]::Max(12, [Math]::Min(72, (Get-Po0DisplayWidth) - 4))
    $line = if ([Console]::IsOutputRedirected -or $env:TERM -eq 'dumb') { '-' } else { '─' }
    Write-Po0UiText ('  ' + ($line * $width)) DarkGray
}

function Write-Po0Heading {
    param([string]$Name, [string]$Status = '', [string]$StatusColor = '')
    $width = [Math]::Min(72, (Get-Po0DisplayWidth) - 4)
    $left = '  ' + ($Name -replace '[\x00-\x1f\x7f]', ' ')
    $gap = $width - (Get-Po0CellWidth $Name) - (Get-Po0CellWidth $Status)
    if ($Status -and $gap -ge 3) {
        Write-Po0UiText ($left + (' ' * $gap)) Cyan -NoNewline
        Write-Po0UiText $Status $StatusColor
    } else {
        Write-Po0UiText $left Cyan
        if ($Status) { Write-Po0UiText ('  ' + $Status) $StatusColor }
    }
}

function Write-Title {
    param([string]$Title, [string]$Hint = '')
    Write-Po0UiText ''
    Write-Po0Heading $Title $Hint
    Write-PanelDivider
}

function Write-MenuItem {
    param([string]$Number, [string]$Label)
    Write-Po0UiText ("    [{0}]  " -f $Number) $(if ($Number -eq '0') { '' } else { 'Cyan' }) -NoNewline
    Write-Po0UiText $Label
}

function Write-PanelSection {
    param([string]$Title)
    Write-Po0UiText ''
    Write-Po0UiText "  $Title" -Bold
}

function Format-Po0PanelLabel {
    param([string]$Label)
    return '  ' + (Format-Po0Cell $Label ([Math]::Max(12, (Get-Po0CellWidth $Label) + 2)))
}

function Write-PanelRow {
    param([string]$Label, [string]$Value)
    Write-Po0UiText (Format-Po0PanelLabel $Label) -NoNewline
    Write-Po0UiText $Value
}

# Keyword tone for status values; priority error > warn > ok > plain.
function Get-Po0StatusTone {
    param([string]$Value)
    if (-not $Value) { return 'plain' }
    $tones = [ordered]@{
        error = @('异常', '失败', '无法', '错误', '无效')
        warn = @('已停用', '已暂停', '未安装', '未配置', '暂不使用', '已关闭', '待迁移', '不一致', '等待', '未放行', '暂无', '状态未知')
        ok = @('已启用', '运行中', '已配置', '已放行', '就绪', '已安装')
    }
    foreach ($tone in $tones.Keys) {
        foreach ($word in $tones[$tone]) { if ($Value.Contains($word)) { return $tone } }
    }
    return 'plain'
}

function Get-Po0ToneColor {
    param([string]$Tone)
    switch ($Tone) { 'ok' { return 'Green' } 'warn' { return 'Yellow' } 'error' { return 'Red' } }
    return ''
}

# Write-PanelRow layout with a semantic value color; -Tone ok|warn|error|plain overrides keywords.
function Write-PanelStatusRow {
    param([string]$Label, [string]$Value, [string]$Tone = '')
    if ($Tone -notin @('ok', 'warn', 'error', 'plain')) { $Tone = Get-Po0StatusTone $Value }
    Write-Po0UiText (Format-Po0PanelLabel $Label) -NoNewline
    Write-Po0UiText $Value (Get-Po0ToneColor $Tone)
}

function Set-OutputColumn { param([int]$Column) Write-Po0UiText '  ' -NoNewline }
function Write-PanelNote { param([string]$Value) Write-Po0UiText "  $Value" }

function Format-Po0Duration {
    param([int]$Seconds)
    $parts = @()
    if ($Seconds -ge 3600) { $parts += ('{0} 小时' -f [math]::Floor($Seconds / 3600)); $Seconds %= 3600 }
    if ($Seconds -ge 60) { $parts += ('{0} 分钟' -f [math]::Floor($Seconds / 60)); $Seconds %= 60 }
    if ($Seconds -gt 0 -or $parts.Count -eq 0) { $parts += "$Seconds 秒" }
    return $parts -join ' '
}

function Get-Po0DisplayConfigurationId {
    try { $normalized = ConvertTo-Po0FirewallNormalizedTokens -Items @(Get-Po0FirewallTokenItems) } catch { return '' }
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($normalized)))).Replace('-', '').ToLowerInvariant() }
    finally { $hash.Dispose() }
}

function Get-Po0DisplayProperty {
    param($Object, [string]$Name, $Default = '')
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $Default
}

function Format-Po0DisplayTime {
    param($Stamp)
    $number = 0L
    if ([long]::TryParse([string]$Stamp, [ref]$number) -and $number -gt 0) {
        try { return [DateTimeOffset]::FromUnixTimeSeconds($number).LocalDateTime.ToString('yyyy-MM-dd HH:mm:ss') } catch {}
    }
    return '尚无记录'
}

function Get-Po0DisplayOutcome {
    param($Account)
    if ($Account.Status -notin @('ok', 'updated')) { return 'error' }
    foreach ($entry in @($Account.Whitelist)) {
        if ($entry.Ip -eq $Account.CurrentIp -and (-not $Account.FixedSlot -or $entry.Slot -eq $Account.FixedSlot)) {
            if ($Account.Status -eq 'updated') { return 'added' }
            return 'hit'
        }
    }
    return 'missing'
}

function Write-Po0SlotRow {
    param([string]$Slot, [string]$Ip, [string]$Label, [string]$Color = '', [int]$Width = 80, [switch]$Bold)
    if ($Width -lt 52) {
        Write-Po0UiText "    $Slot  $Label" $Color -Bold:$Bold
        Write-Po0UiText "      $Ip"
    } else {
        Write-Po0UiText ('    ' + (Format-Po0Cell $Slot 8) + (Format-Po0Cell $Ip 23) + $Label) $Color -Bold:$Bold
    }
}

function Show-Po0FirewallTable {
    param($State, [string]$Title = '最近结果', [switch]$Failed)
    $accounts = @($State.Accounts)
    $width = Get-Po0DisplayWidth
    $mark = if (-not [Console]::IsOutputRedirected -and $env:TERM -ne 'dumb') { '●' } else { '*' }
    $allowed = 0; $updated = 0; $missing = 0; $errors = 0; $hasUnknown = $false
    foreach ($account in $accounts) {
        switch (Get-Po0DisplayOutcome $account) {
            hit { $allowed++ }
            added { $allowed++; $updated++ }
            missing { $missing++ }
            default { $errors++ }
        }
    }
    Write-Title "PO0 防火墙 / $Title"
    $summary = "$allowed/$($accounts.Count) 个账号已放行"
    if ($updated) { $summary += "  ·  已更新 $updated 个" }
    elseif ($allowed -gt 0 -and $errors -eq 0 -and $missing -eq 0) { $summary += '  ·  无需更新' }
    if ($missing) { $summary += "  ·  $missing 个未放行" }
    if ($errors) { $summary += "  ·  $errors 个失败" }
    Write-Po0UiText "  $summary" $(if ($errors -or $Failed) { 'Yellow' } elseif ($missing) { 'Yellow' } else { 'Green' })
    $ips = @($accounts | ForEach-Object CurrentIp | Where-Object { $_ } | Select-Object -Unique)
    $commonIp = if ($ips.Count -eq 1) { [string]$ips[0] } else { '' }
    if (@($accounts | Where-Object { -not $_.CurrentIp }).Count) { $commonIp = '' }
    if ($commonIp) { Write-PanelRow '当前出口' $commonIp }
    if ($Failed -and $errors -eq 0) { Write-PanelNote '操作尚未完整完成，请查看错误提示。' }
    if (-not $accounts.Count) { Write-PanelNote '尚无可展示的账号结果。' }
    foreach ($account in $accounts) {
        $outcome = Get-Po0DisplayOutcome $account
        $badge = switch ($outcome) { hit { '已放行' }; added { '已放行 · 已更新' }; missing { '未放行' }; default { '操作失败' } }
        $color = switch ($outcome) { hit { 'Green' }; added { 'Green' }; missing { 'Yellow' }; default { 'Red' } }
        Write-Po0UiText ''
        Write-Po0Heading (Get-OfficialAccountName $account.Index) $badge $color
        $configured = if ($account.FixedSlot -ne '') { '固定 #{0}' -f (1 + [int]$account.FixedSlot) } else { '自动分配' }
        if (-not $commonIp -and $account.CurrentIp) { Write-PanelRow '当前出口' $account.CurrentIp }
        if ($account.Limit -lt 1 -or $account.Limit -gt 10 -or $account.Used -gt $account.Limit) {
            Write-PanelNote "$configured · 本次未取得白名单，请稍后重试。"
            continue
        }
        Write-PanelNote ('占用 {0}/{1}  ·  剩余 {2} 个  ·  {3}' -f $account.Used, $account.Limit, ($account.Limit - $account.Used), $configured)
        if ($account.FixedSlot -ne '' -and [int]$account.FixedSlot -ge $account.Limit) { Write-Po0UiText '  指定槽位超出账号额度，请调整固定槽位。' Red }
        if ($outcome -eq 'error') { Write-PanelNote '以下为本次已取得的数据，操作未完成。' }
        Write-Po0UiText ''
        if ($width -ge 52) { Write-Po0SlotRow '槽位' 'IP / 网段' '状态' '' $width -Bold }
        $unassigned = @($account.Whitelist | Where-Object { $_.Slot -eq '' })
        $rows = @()
        if ($unassigned.Count) {
            $hasUnknown = $true
            $rows = @($account.Whitelist | Where-Object { $_.Slot -ne '' } | Sort-Object { [int]$_.Slot }) + $unassigned
        } else {
            for ($slot = 0; $slot -lt $account.Limit; $slot++) {
                $entries = @($account.Whitelist | Where-Object { $_.Slot -ne '' -and [int]$_.Slot -eq $slot })
                if ($entries.Count) { $rows += $entries[0] } else { $rows += [pscustomobject]@{Slot=[string]$slot;Ip=''} }
            }
        }
        foreach ($entry in $rows) {
            $slotLabel = if ($entry.Slot -eq '') { '未编号' } else { '#{0}' -f (1 + [int]$entry.Slot) }
            $ip = if ($entry.Ip) { [string]$entry.Ip } else { '-' }
            $label = if ($entry.Ip) { '已记录' } else { '空闲' }; $rowColor = ''
            if ($entry.Ip -and $entry.Ip -eq $account.CurrentIp) {
                $label = '出口匹配'
                if ($outcome -ne 'error' -and ($account.FixedSlot -eq '' -or $entry.Slot -eq $account.FixedSlot)) { $label = "$mark 当前出口"; $rowColor = 'Green' }
            }
            Write-Po0SlotRow $slotLabel $ip $label $rowColor $width
        }
    }
    Write-Po0UiText ''
    if ($hasUnknown) { Write-PanelNote '说明：部分记录未返回槽位编号，已列出全部 IP。' }
    Write-PanelRow '检查时间' (Format-Po0DisplayTime (Get-Po0DisplayProperty $State LastCheckedAt))
    Write-Po0UiText ''
}

function Show-Po0FirewallCached {
    param([switch]$Summary)
    $state = Get-Po0FirewallState
    $identity = Get-Po0DisplayProperty $state ConfigurationId
    $note = ''
    if (-not $state -or -not $identity) { $note = '暂无新版记录，检查后显示' }
    elseif ($identity -ne (Get-Po0DisplayConfigurationId)) { $note = '账号配置已更新，等待下次检查' }
    if ($note) { Write-PanelStatusRow '最近检查' $note warn; return }
    if ($Summary) {
        $allowed = @($state.Accounts | Where-Object { (Get-Po0DisplayOutcome $_) -in @('hit','added') }).Count
        $total = @($state.Accounts).Count
        $tone = if ($total -gt 0 -and $allowed -eq $total) { 'ok' } else { 'warn' }
        Write-PanelStatusRow '最近检查' ('{0} · {1}/{2} 已放行' -f (Format-Po0DisplayTime (Get-Po0DisplayProperty $state LastCheckedAt)), $allowed, $total) $tone
    } else { Show-Po0FirewallTable $state '上次结果 / 本地记录' }
}

function Show-Po0FirewallLive {
    param($Result, [string]$Title)
    if (-not (Test-Po0RichOutput)) { return }
    $state = [pscustomobject]@{ Accounts = @($Result.Accounts); LastCheckedAt = Get-Po0FirewallNow }
    Show-Po0FirewallTable $state $Title -Failed:(-not $Result.Succeeded)
    $script:Po0UiRendered = $true
}
