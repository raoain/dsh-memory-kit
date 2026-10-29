# close.ps1 — 收工一条命令：自动记事实 + 备份
#
# 为什么：留痕积压不是记性问题是流程问题——我跑一条命令才留一条，检查器只能喊。
# 分工：**自动记事实（改了什么、发了什么、检查怎样），人工记理由（为什么改）。**
# 对应「永不停息 = 停了能自己起来，而且起来还是同一个」。
#
# 用法： powershell -NoProfile -File <你的项目根>\close.ps1 [-Text "今天的理由/结论"]
param([string]$Text = '')

$ErrorActionPreference = 'Continue'
$Root = (Get-Location).Path
$today = (Get-Date).ToString('yyyy-MM-dd')

Write-Host ''
Write-Host '=== 收工：先量，再记 ===' -ForegroundColor Cyan

# 1) 事实：检查状态
$verifyLine = ''
try {
    $vout = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'verify.ps1') 2>&1 | Out-String
    $m = [regex]::Match($vout, '\d+ 项：OK \d+[^\r\n]*')
    if ($m.Success) { $verifyLine = $m.Value.Trim() } else { $verifyLine = 'verify 没给出汇总行' }
} catch { $verifyLine = 'verify 跑不起来' }

$pinLine = ''
try {
    $pout = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'pin.ps1') -Diff 2>&1 | Out-String
    $pl = ($pout -split "`r?`n" | Where-Object { $_.Trim() }) | Select-Object -Last 1
    $pinLine = ($pl -replace '\s+', ' ').Trim()
} catch { $pinLine = 'pin 跑不起来' }

# 2) 事实：今天发了什么
$pubCount = 0
$ledger = Join-Path $Root 'track\发布台账.jsonl'
if (Test-Path $ledger) {
    foreach ($ln in (Get-Content $ledger -Encoding UTF8)) {
        if (-not $ln.Trim()) { continue }
        try {
            $o = $ln | ConvertFrom-Json
            if ($o.id -and $o.published_at -and $o.published_at.ToString().StartsWith($today)) { $pubCount++ }
        } catch { }
    }
}

# 3) 事实：核心层大小
$coreSize = 0
$coreP = Join-Path $Root 'notebook\0-核心.md'
if (Test-Path $coreP) { $coreSize = (Get-Item $coreP).Length }

Write-Host ("  检查：{0}" -f $verifyLine) -ForegroundColor Gray
Write-Host ("  引脚：{0}" -f $pinLine) -ForegroundColor Gray
Write-Host ("  今日发布：{0} 篇 ｜ 核心层 {1} B" -f $pubCount, $coreSize) -ForegroundColor Gray

# 4) 自动记一条工作层（事实 + 可选理由）
$auto = '收工（自动记事实）'
if ($Text) { if ($Text.StartsWith('收工')) { $auto = $Text } else { $auto = "收工：$Text" } }
$evid = "证: $verifyLine ｜ $pinLine ｜ 今日发布 $pubCount 篇 ｜ 核心层 $coreSize B"
try {
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'log.ps1') -Text $auto -Evid $evid 2>&1 |
        Where-Object { $_ -match '已记入|改过|上次记录' } | ForEach-Object { "  $_" }
} catch { Write-Host '  log.ps1 跑不起来' -ForegroundColor Red }

# 5) 备份（记事本 + track + 脚本，双盘）
try {
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'backup-notes.ps1') 2>&1 |
        Where-Object { $_ -match '备份 →|记事本备份完成|警告' } | ForEach-Object { "  $_" }
} catch { Write-Host '  backup-notes.ps1 跑不起来' -ForegroundColor Red }

# 6) 便签提示（便签本身在 1-工作.md 头部）
Write-Host ''
Write-Host '便签三条（写在 1-工作.md 头部）：刚聊到哪 / 答应了什么 / 下次接着说什么' -ForegroundColor Cyan
Write-Host ("完成时间：{0}" -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor DarkGray
exit 0
