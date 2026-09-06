function Get-MaskedSecret {
    param([string]$Value)
    if (-not $Value) { return "未设置" }
    if ($Value.Length -le 8) { return "***" }
    return ($Value.Substring(0, 3) + "***" + $Value.Substring($Value.Length - 3))
}

function Format-NotifyStatus {
    if ($script:TaskNotify) { return "已启用" }
    return "静默，仅写日志"
}

function Format-TaskNotifyStatus {
    param($NotifyState)
    if (-not $NotifyState -or -not $NotifyState.Installed) { return "未安装" }
    if ($NotifyState.IsUnknown) { return "未知；无法解析计划任务启动器" }
    if ($NotifyState.ActualNotify) { return "已启用（计划任务带 -Notify）" }
    if ($NotifyState.HasNoNotify) { return "静默（计划任务带 -NoNotify）" }
    return "静默（计划任务未带 -Notify）"
}

function Format-NotifyDriftStatus {
    param($NotifyState)
    if (-not $NotifyState -or -not $NotifyState.Installed -or $NotifyState.IsUnknown) { return "" }
    if ([bool]$script:TaskNotify -eq [bool]$NotifyState.ActualNotify) { return "" }
    return ("漂移：配置为 {0}，实际计划任务为 {1}" -f (Format-NotifyStatus), (Format-TaskNotifyStatus -NotifyState $NotifyState))
}

function Read-Default {
    param(
        [string]$Prompt,
        [string]$DefaultValue
    )
    if ($DefaultValue) {
        $value = Read-Host "$Prompt [$DefaultValue]"
        if ($null -eq $value) { return $DefaultValue }
        if (-not $value) { return $DefaultValue }
        return $value.Trim()
    }
    $value = Read-Host "$Prompt"
    if ($null -eq $value) { return "" }
    return $value.Trim()
}

function Read-YesNoDefault {
    param(
        [string]$Prompt,
        [bool]$DefaultValue
    )
    $suffix = $(if ($DefaultValue) { "[Y/n]" } else { "[y/N]" })
    while ($true) {
        $value = Read-Host "$Prompt $suffix"
        if ($null -eq $value -or -not $value.Trim()) { return $DefaultValue }
        switch -Regex ($value.Trim()) {
            '^(y|yes)$' { return $true }
            '^(n|no)$' { return $false }
            default { Write-Host "请输入 y 或 n。" }
        }
    }
}

function Read-SecretSetting {
    Write-PanelRow "当前上报密钥" $(if ($script:Secret) { $script:Secret } else { "未设置" })
    if ($script:Secret) {
        $value = Read-Host "Self-report secret [已设置，回车保留，输入 - 清空]"
        if ($null -eq $value) { return }
        $value = $value.Trim()
        if (-not $value) { return }
        if ($value -eq "-") {
            $script:Secret = ""
        } else {
            $script:Secret = $value
        }
    } else {
        $value = Read-Host "Self-report secret，可空"
        if ($null -eq $value) { $value = "" }
        $script:Secret = $value.Trim()
    }
}

function Format-TaskTime {
    param($Value)
    if ($Value -and $Value.Year -gt 1900) { return $Value }
    return "尚未运行"
}

function Format-TaskResult {
    param([long]$Value)
    if ($Value -eq 0) { return "0 (成功)" }
    return ("{0} (0x{0:X8})" -f $Value)
}
