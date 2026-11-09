# notebook.ps1 — 四个动词，不是四个配置项
# 醒来 wake   干活 work   遇坑 pit   收工 close
#
# 用法：
#   .\notebook.ps1 wake                看核心层（每次醒来必读）
#   .\notebook.ps1 work "在做的事"      追加到工作层
#   .\notebook.ps1 pit "现象|根因|修法"  追加到档案层（踩坑）
#   .\notebook.ps1 close               更新工作层时间 + 快照 + 备份
param(
    [Parameter(Mandatory = $true)][ValidateSet('wake', 'work', 'pit', 'close')][string]$Action,
    [string]$Text
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_root.ps1')
$Core = Join-Path $Notebook '0-核心.md'
$Work = Join-Path $Notebook '1-工作.md'
$File = Join-Path $Notebook '2-档案.md'

New-Item -ItemType Directory -Force -Path $Notebook | Out-Null
$now = Get-Date -Format 'yyyy-MM-dd HH:mm'

function Add-Line($path, $text) {
    if (Test-Path $path) {
        $raw = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
        if ($raw.Length -gt 0 -and -not $raw.EndsWith("`n")) { $text = "`r`n" + $text }
    }
    Add-Content $path $text -Encoding UTF8
}


switch ($Action) {
    'wake' {
        # 只读核心 + 工作层最近一屏
        if (Test-Path $Core) { Get-Content $Core -Encoding UTF8 }
        Write-Host "`n--- 工作层（最近 20 行）---" -ForegroundColor DarkGray
        if (Test-Path $Work) { Get-Content $Work -Encoding UTF8 -Tail 20 }
    }
    'work' {
        if (-not $Text) { throw '需要 -Text' }
        Add-Line $Work ("- [{0}] {1}" -f $now, $Text)
        Write-Host "工作层 +1" -ForegroundColor Green
    }
    'pit' {
        if (-not $Text) { throw '需要 -Text（格式：现象|根因|修法）' }
        $p = $Text -split '\|'
        $entry = @"

### $($p[0])
- 时间：$now
- 根因：$(if($p.Count -gt 1){$p[1]}else{'待补'})
- 修法：$(if($p.Count -gt 2){$p[2]}else{'待补'})
"@
        Add-Line $File $entry
        Write-Host "档案层 +1" -ForegroundColor Green
    }
    'close' {
        & (Join-Path $Root 'status.ps1') 2>&1 | Select-Object -Last 1 | Out-Null
        & (Join-Path $Root 'backup.ps1') 2>&1
        Add-Line $Work ("- [{0}] 收工" -f $now)
        Write-Host '收工：快照 + 备份已落盘' -ForegroundColor Green
    }
}
