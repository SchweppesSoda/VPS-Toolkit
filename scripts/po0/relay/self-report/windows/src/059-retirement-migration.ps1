function Backup-RetiredConfig {
    $path = $script:ConfigPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
    $backup = "$path.pre-retirement-v1"
    if (Test-Path -LiteralPath $backup) { return }
    if ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw '配置路径不可用于迁移。' }
    Copy-Item -LiteralPath $path -Destination $backup -ErrorAction Stop
    Set-Po0ClientConfigAcl -Path $backup
}

function Invoke-RetiredStateMigration {
    Backup-RetiredConfig
    $backup = "$($script:ConfigPath).pre-retirement-tasks-v1.json"
    if (-not (Test-Path -LiteralPath $backup)) {
        $records = @(Get-ScheduledTask | Where-Object { $_.TaskName -like 'Outbound IP Report*' -or $_.TaskName -in $script:LegacyTaskNames } | ForEach-Object {
            @{ Name = $_.TaskName; Path = $_.TaskPath; Xml = Export-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath }
        })
        Write-Po0ClientConfigAtomic -Path $backup -Json ($records | ConvertTo-Json -Depth 5)
    }
    Remove-ScheduledReporter -Channel worker
    Update-ChannelScheduleIfInstalled official
    Save-ClientConfig
    Write-Host "旧自建任务已退役；备份位置：$($script:ConfigPath).pre-retirement-v1"
}
