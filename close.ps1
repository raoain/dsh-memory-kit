# close.ps1 — 收工一条命令：自动记事实 + 备份
#
# 为什么：留痕积压不是记性问题是流程问题——我跑一条命令才留一条，检查器只能喊。
# 分工：**自动记事实（改了什么、发了什么、检查怎样），人工记理由（为什么改）。**
# 对应「永不停息 = 停了能自己起来，而且起来还是同一个」。
#
# 用法： powershell -NoProfile -File F:\Tools\coo-day1\close.ps1 [-Text "今天的理由/结论"]
param([string]$Text = '', [string]$Where = '', [string]$Promise = '', [string]$Next = '')

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_root.ps1')
$today = (Get-Date).ToString('yyyy-MM-dd')

Write-Host ''
Write-Host '=== 收工：先量，再记 ===' -ForegroundColor Cyan

# 1) 事实：检查状态
$verifyLine = ''
try {
    $vout = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'verify.ps1') 2>&1 | Out-String
    $m = [regex]::Match($vout, '\d+ 项：OK \d+[^\r\n]*')
    if ($m.Success) { $verifyFirst = $m.Value.Trim() } else { $verifyFirst = 'verify 没给出汇总行' }
} catch { $verifyFirst = 'verify 跑不起来' }

$pinLine = ''
try {
    $pout = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'pin.ps1') -Diff 2>&1 | Out-String
    $pl = ($pout -split "`r?`n" | Where-Object { $_.Trim() }) | Select-Object -Last 1
    $pinLine = ($pl -replace '\s+', ' ').Trim()
    # 漂移必须显式报痛：列明细，不许静默重钉
    $pinDrift = @($pout -split [Environment]::NewLine | Where-Object { $_ -match '^DRIFT' })
    if ($pinDrift.Count -gt 0) { $pinLine = $pinLine + ' ｜ 漂移明细: ' + ($pinDrift -join ' ; ') }
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

Write-Host ("  检查：{0}" -f $verifyFirst) -ForegroundColor Gray
Write-Host ("  引脚：{0}" -f $pinLine) -ForegroundColor Gray
Write-Host ("  今日发布：{0} 篇 ｜ 核心层 {1} B" -f $pubCount, $coreSize) -ForegroundColor Gray

# 收工自查：便签三条 + 「说了没做」

# 写便签（收工的一部分）：三条都给才写，否则提示
if ($Where -and $Promise -and $Next) {
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'sticky.ps1') -Where $Where -Promise $Promise -Next $Next | Out-Null
    Write-Host '  便签：已写入三条' -ForegroundColor Gray
} else {
    $stickyUpd = '' 
    if (Test-Path (Join-Path $Root 'state.json')) { $st = Get-Content (Join-Path $Root 'state.json') -Raw | ConvertFrom-Json; $stickyUpd = [string]$st.pins.'sticky.updated' }
    if ($stickyUpd -ne $today) { Write-Host '  便签：不是今天写的 → 收工要带 -Where/-Promise/-Next' -ForegroundColor Yellow }
}
$stickyP = Join-Path $Root 'notebook\1-工作.md'
$stickyTxt = if (Test-Path $stickyP) { [IO.File]::ReadAllText($stickyP, [Text.Encoding]::UTF8) } else { '' }
$stickyFilled = (@('刚聊到哪','答应了什么','下次接着说什么') | Where-Object { $stickyTxt -match ("\*\*" + $_ + "\*\*：\S") }).Count
Write-Host ("  收工自查：便签 {0}/3 ｜ 今天的「应该做」都落条目了吗（待消化/大计划/便签）" -f $stickyFilled) -ForegroundColor Yellow

# 4) 自动记一条工作层（事实 + 可选理由）
$auto = '收工（自动记事实）'
if ($Text) { if ($Text.StartsWith('收工')) { $auto = $Text } else { $auto = "收工：$Text" } }
# 2026-11-12 用户：「close.ps1 先跑 verify，再写 log，所以上面有检查有屁用」
# 原顺序让「改动留痕比」在收工那一刻必然是红的（log 还没写）。所以 log 之后再复查一次，
# 报出去的数字用复查那次；第一次的值只留给 log 的证。
$evid = "证: $verifyFirst ｜ $pinLine ｜ 今日发布 $pubCount 篇 ｜ 核心层 $coreSize B"
try {
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'log.ps1') -Text $auto -Evid $evid 2>&1 |
        Where-Object { $_ -match '已记入|改过|上次记录' } | ForEach-Object { "  $_" }
} catch { Write-Host '  log.ps1 跑不起来' -ForegroundColor Red }

# 4b) log 之后复查一次 verify：这一次才代表收工时的真实状态
$verifyAfter = $null
try {
    $vout2 = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'verify.ps1')
    $outText2 = ($vout2 | Out-String)
    $m2 = [regex]::Match($outText2, '(?m)^\s*\d+\s*项：.*$')
    if ($m2.Success) { $verifyAfter = $m2.Value.Trim() }
} catch { }
if ($verifyAfter) {
    Write-Host ("  检查（log 后复查）：{0}" -f $verifyAfter) -ForegroundColor Gray
} else {
    Write-Host '  检查（log 后复查）：没跑起来' -ForegroundColor Yellow
}

# 5) 备份（记事本 + track + 脚本，双盘）
try {
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'backup-notes.ps1') 2>&1 |
        Where-Object { $_ -match '备份 →|记事本备份完成|警告' } | ForEach-Object { "  $_" }
} catch { Write-Host '  backup-notes.ps1 跑不起来' -ForegroundColor Red }

# 5b) 分纳归档 + 刷新索引（2026-11-22 用户定：每天收工把今天的结果分纳归档，再加索引）
#     区册：track\区册\文件区册.md（A-本体理论 / B-术语 / C-杂项），由 track-index.ps1 生成，不手改。
try {
    $idxOut = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'track-index.ps1') 2>&1
    $idxLine = ($idxOut | Where-Object { $_ -match '区册已生成|分区:' }) -join ' ｜ '
    if ($idxLine) { Write-Host ("  区册：{0}" -f $idxLine) -ForegroundColor Gray }
    else { Write-Host '  区册：生成没回话（看 track-index.ps1）' -ForegroundColor Yellow }
} catch { Write-Host '  track-index.ps1 跑不起来' -ForegroundColor Red }

# 5c) 刷新压缩总纲里的数字（2026-11-22 用户：那个压缩你每次收工也得改得同时更新）
#     只刷可机的部分（更新时间/账行数节数/verify 汇总/区划分区数）；结论部分手写，改了要人定。
try {
    $gOut = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'guide-update.ps1') 2>&1
    $gLine = ($gOut | Where-Object { $_ -match 'guide-update:|结果账 \*\*' }) -join ' ｜ '
    if ($gLine) { Write-Host ("  总纲：{0}" -f $gLine) -ForegroundColor Gray }
    else { Write-Host '  总纲：刷新没回话（看 guide-update.ps1）' -ForegroundColor Yellow }
} catch { Write-Host '  guide-update.ps1 跑不起来' -ForegroundColor Red }

# 5d) 插件数据回拉本体（2026-11-22 用户：C 方向，插件 -> 本机；标准是「去掉插件也能运行」，
#     所以插件写的东西本体里必须有记录，哪怕插件以后没了）
try {
    $pOut = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'plugin-sync.ps1') 2>&1
    $pLine = ($pOut | Where-Object { $_ -match 'plugin-sync:' }) -join ' ｜ '
    if ($pLine) { Write-Host ("  插件：{0}" -f $pLine) -ForegroundColor Gray }
    else { Write-Host '  插件：回拉没回话（看 plugin-sync.ps1）' -ForegroundColor Yellow }
} catch { Write-Host '  plugin-sync.ps1 跑不起来' -ForegroundColor Red }

# 6) 便签提示（便签本身在 1-工作.md 头部）
Write-Host ''
Write-Host '便签三条（写在 1-工作.md 头部）：刚聊到哪 / 答应了什么 / 下次接着说什么' -ForegroundColor Cyan
Write-Host ("完成时间：{0}" -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor DarkGray
exit 0
