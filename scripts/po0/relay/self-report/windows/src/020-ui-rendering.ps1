function Set-OutputColumn {
    param([int]$Column)
    if ([Console]::IsOutputRedirected -or (Test-Path Env:NO_COLOR) -or $env:TERM -eq 'dumb') {
        Write-Host "    " -NoNewline
        return
    }
    try {
        $target = [Math]::Max(0, $Column - 1)
        if ([Console]::CursorLeft -gt $target) {
            Write-Host ""
        }
        [Console]::CursorLeft = $target
    } catch {
        Write-Host "    " -NoNewline
    }
}

function Write-Title {
    param([string]$Title)
    Write-Host ""
    Write-Host "============================================================"
    Write-Host $Title
    Write-Host "============================================================"
}

function Write-MenuItem {
    param([string]$Number, [string]$Label)
    Write-Po0UiText ("  {0,2}) {1}" -f $Number, $Label) -Color Cyan
}


function Write-PanelDivider {
    Write-Po0UiText "------------------------------------------------------------" -Color DarkYellow
}

function Write-PanelSection {
    param([string]$Title)
    Write-PanelDivider
    Write-Po0UiText $Title -Color Yellow
}

function Write-PanelRow {
    param([string]$Label, [string]$Value)
    Write-Po0UiText "  $Label" -NoNewline -Color DarkYellow
    Set-OutputColumn $PanelValueColumn
    Write-Po0UiText ": $Value" -Color DarkYellow
}

function Write-PanelNote {
    param([string]$Value)
    Write-Host "    $Value"
}

# Presentation only: use the response/cache already obtained by the reporter.
function Test-Po0UiColor {
    return (-not [Console]::IsOutputRedirected -and -not (Test-Path Env:NO_COLOR) -and $env:TERM -ne 'dumb')
}

function Write-Po0UiText {
    param([string]$Text, [string]$Color = '', [switch]$NoNewline)
    if ($Color -and (Test-Po0UiColor)) { Write-Host $Text -ForegroundColor $Color -NoNewline:$NoNewline }
    else { Write-Host $Text -NoNewline:$NoNewline }
}

function Get-Po0DisplayConfigurationId {
    try { $normalized = ConvertTo-Po0FirewallNormalizedTokens -Items @(Get-Po0FirewallTokenItems) } catch { return "" }
    $hash = [System.Security.Cryptography.SHA256]::Create()
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
    return '未知'
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

function Get-Po0DisplayWidth {
    try { if ([Console]::WindowWidth -gt 0) { return [Console]::WindowWidth } } catch {}
    return 80
}

function Write-Po0SlotRow {
    param([string]$Slot, [string]$Ip, [string]$Label, [string]$Color, [int]$Width)
    if ($Width -lt 60) {
        Write-Po0UiText "  $Slot  $Label" $Color
        Write-Po0UiText "    $Ip"
    } else {
        Write-Po0UiText ('  {0,-8} {1,-21} {2}' -f $Slot, $Ip, $Label) $Color
    }
}

function Show-Po0FirewallTable {
    param($State, [string]$Title = '上次结果（本地缓存）', [switch]$Failed)
    $accounts = @($State.Accounts)
    $width = Get-Po0DisplayWidth
    $hitSymbol = '[OK]'
    if (-not [Console]::IsOutputRedirected -and [Console]::OutputEncoding.CodePage -eq 65001 -and $env:TERM -ne 'dumb') { $hitSymbol = '✓' }
    $allowed = 0; $updated = 0; $missing = 0; $errors = 0
    foreach ($account in $accounts) {
        switch (Get-Po0DisplayOutcome $account) {
            hit { $allowed++ }
            added { $allowed++; $updated++ }
            missing { $missing++ }
            default { $errors++ }
        }
    }
    Write-Po0UiText "`nPO0 防火墙 · $Title" Cyan
    Write-Po0UiText "$allowed 个账号已放行 · 更新 $updated 个 · 未放行 $missing 个 · 失败 $errors 个"
    if ($Failed) { Write-Po0UiText '本次操作未完整完成，请查看错误提示。' Red }
    if ($accounts.Count -eq 0) { Write-Po0UiText '尚无可展示的账号结果。' }
    foreach ($account in $accounts) {
        $outcome = Get-Po0DisplayOutcome $account
        $name = (Get-OfficialAccountName $account.Index) -replace '[\x00-\x1f\x7f]', ' '
        Write-Po0UiText "`n-- $name --" Cyan
        switch ($outcome) {
            hit { Write-Po0UiText "$hitSymbol 已放行" Green }
            added { Write-Po0UiText "$hitSymbol 已放行 · 本次更新" Green }
            missing { Write-Po0UiText '未放行' Yellow }
            default { Write-Po0UiText '操作失败' Red }
        }
        $current = if ($account.CurrentIp) { [string]$account.CurrentIp } else { '未知' }
        Write-Po0UiText "当前出口 $current"
        $configured = if ($account.FixedSlot -ne '') { '固定槽位 #{0}' -f (1 + [int]$account.FixedSlot) } else { '自动分配' }
        $matches = @($account.Whitelist | Where-Object { $_.Ip -eq $account.CurrentIp } | ForEach-Object {
            if ($_.Slot -ne '') { '#{0}' -f (1 + [int]$_.Slot) } else { '槽位未知' }
        })
        $matched = if ($matches.Count) { $matches -join '、' } else { '无' }
        Write-Po0UiText "$configured · 实际命中 $matched"
        if ($account.Limit -lt 1 -or $account.Limit -gt 10 -or $account.Used -gt $account.Limit) {
            Write-Po0UiText '占用未知 · 尚无完整槽位数据'
            continue
        }
        Write-Po0UiText ('占用 {0}/{1} · 剩余 {2} 个' -f $account.Used, $account.Limit, ($account.Limit - $account.Used))
        if ($account.FixedSlot -ne '' -and [int]$account.FixedSlot -ge $account.Limit) { Write-Po0UiText '指定槽位超出账号额度，请调整固定槽位。' Red }
        if ($outcome -eq 'error') { Write-Po0UiText '以下为本次已取得的数据；操作未完成。' }
        Write-Po0UiText "`n  槽位     IP / 网段             状态"
        $unassigned = @($account.Whitelist | Where-Object { $_.Slot -eq '' })
        for ($slot = 0; $slot -lt $account.Limit; $slot++) {
            $entries = @($account.Whitelist | Where-Object { $_.Slot -ne '' -and [int]$_.Slot -eq $slot })
            $ip = '-'; $label = '空闲'; $color = ''
            if ($entries.Count) {
                $ip = [string]$entries[0].Ip; $label = '已占用'
                if ($ip -eq $account.CurrentIp) {
                    $label = '当前出口匹配'
                    if ($outcome -ne 'error' -and ($account.FixedSlot -eq '' -or [int]$account.FixedSlot -eq $slot)) {
                        $label = "$hitSymbol 当前命中"; $color = 'Green'
                    }
                }
            } elseif ($unassigned.Count) { $label = '未知（有未编号记录）' }
            Write-Po0SlotRow "#$($slot + 1)" $ip $label $color $width
        }
        foreach ($entry in $unassigned) {
            $label = '已占用'; $color = ''
            if ($entry.Ip -eq $account.CurrentIp -and $outcome -ne 'error' -and $account.FixedSlot -eq '') {
                $label = "$hitSymbol 当前命中"; $color = 'Green'
            }
            Write-Po0SlotRow '槽位未知' $entry.Ip $label $color $width
        }
    }
    Write-Po0UiText ("`n检查时间 {0}" -f (Format-Po0DisplayTime (Get-Po0DisplayProperty $State LastCheckedAt)))
}

function Show-Po0FirewallCached {
    param([switch]$Summary)
    $state = Get-Po0FirewallState
    if (-not $state) { Write-Po0UiText '上次检查：尚无本地结果。'; return }
    $identity = Get-Po0DisplayProperty $state ConfigurationId
    if (-not $identity -or $identity -ne (Get-Po0DisplayConfigurationId)) {
        Write-Po0UiText '上次检查：缓存未匹配当前账号配置，请重新查询。'
        return
    }
    if ($Summary) {
        $allowed = @($state.Accounts | Where-Object { (Get-Po0DisplayOutcome $_) -in @('hit','added') }).Count
        Write-Po0UiText ('上次检查：{0} · 已放行 {1}/{2} · 详情见“最近结果”' -f (Format-Po0DisplayTime (Get-Po0DisplayProperty $state LastCheckedAt)), $allowed, @($state.Accounts).Count)
    } else { Show-Po0FirewallTable $state }
}

function Show-Po0FirewallLive {
    param($Result, [string]$Title)
    if ($script:Po0FirewallScheduledRun -or [Console]::IsOutputRedirected) { return }
    $state = [pscustomobject]@{ Accounts = @($Result.Accounts); LastCheckedAt = Get-Po0FirewallNow }
    Show-Po0FirewallTable $state $Title -Failed:(-not $Result.Succeeded)
}
