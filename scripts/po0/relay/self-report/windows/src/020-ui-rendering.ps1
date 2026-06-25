function Set-OutputColumn {
    param([int]$Column)
    if ([Console]::IsOutputRedirected) {
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
    Write-Host "========================"
    Write-Host $Title
    Write-Host "========================"
}

function Write-MenuDivider {
    Write-Host "------------------------" -ForegroundColor Cyan
}

function Write-MenuSection {
    param([string]$Title)
    Write-MenuDivider
    Write-Host $Title -ForegroundColor Cyan
}

function Write-MenuItem {
    param([string]$Number, [string]$Label)
    Write-Host ("  {0,2}) {1}" -f $Number, $Label) -ForegroundColor Cyan
}

function Write-MenuPair {
    param(
        [string]$LeftNumber,
        [string]$LeftLabel,
        [string]$RightNumber,
        [string]$RightLabel
    )
    $left = ("  {0,2}) {1}" -f $LeftNumber, $LeftLabel)
    if ($RightNumber) {
        Write-Host $left -NoNewline -ForegroundColor Cyan
        Set-OutputColumn $MenuRightColumn
        Write-Host ("{0,2}) {1}" -f $RightNumber, $RightLabel) -ForegroundColor Cyan
    } else {
        Write-Host $left -ForegroundColor Cyan
    }
}

function Write-PanelDivider {
    Write-Host "------------------------" -ForegroundColor DarkYellow
}

function Write-PanelSection {
    param([string]$Title)
    Write-PanelDivider
    Write-Host $Title -ForegroundColor Yellow
}

function Write-PanelRow {
    param([string]$Label, [string]$Value)
    Write-Host "  $Label" -NoNewline -ForegroundColor DarkYellow
    Set-OutputColumn $PanelValueColumn
    Write-Host ": $Value" -ForegroundColor DarkYellow
}

function Write-PanelNote {
    param([string]$Value)
    Write-Host "    $Value"
}
