# fore.ps1 — 强制「先推再查」：不填预期与理由，它不给你数字
#
# 为什么（2026-10-30 用户要求两遍未落地）：
#   AI 的链可以整条悬空——直接查数、看到什么算什么，永远不知道基数错了。
#   人的链强制连着世界，推错会挨打；AI 只能靠机制把「推」放在「查」前面。
# 所以这个脚本的顺序写死：先要 -Expect 与 -Why，再量，再比对。少一个参数它不出数。
#
# 用法：
#   .\fore.ps1 -Target scripts -Expect 34 -Why "基线33+claim1"
#   .\fore.ps1 -Target core    -Expect 1313 -Range 0 -Why "定名后未改"
#   .\fore.ps1 -List                 # 看历史命中率
param(
    [ValidateSet('scripts','pages','criteria','ledger','core','conclusions','sayings','archive','tracks','verifycount')]
    [string]$Target,
    [string]$Expect,
    [int]$Range = 0,
    [string]$Why,
    [switch]$List
)

$ErrorActionPreference = 'Continue'
$Root = (Get-Location).Path
$Log  = Join-Path $Root 'track\预测数据.jsonl'
$enc  = New-Object Text.UTF8Encoding($false)
$nb   = Join-Path $Root 'notebook'

function Measure-Target($t) {
    switch ($t) {
        'scripts'     { return @(Get-ChildItem $Root -Filter '*.ps1' -File).Count }
        'pages'       { return @(Get-ChildItem $nb -Filter '*.md' -File).Count }
        'criteria'    { return (@(Select-String -Path (Join-Path $nb '5-判据.md') -Pattern '^## P\d' -Encoding UTF8).Count) + (@(Select-String -Path (Join-Path $nb '12-判据-专项.md') -Pattern '^## P\d' -Encoding UTF8).Count) }
        'ledger'      { return @(Get-Content (Join-Path $Root 'track\发布台账.jsonl') -Encoding UTF8 | Where-Object { $_.Trim() }).Count }
        'core'        { return (Get-Item (Join-Path $nb '0-核心.md')).Length }
        'conclusions' { return @(Select-String -Path (Join-Path $nb '11-结论.md') -Pattern '^## C\d' -Encoding UTF8).Count }
        'sayings'     { return @(Select-String -Path (Join-Path $nb '11-结论.md') -Pattern '^### S\d' -Encoding UTF8).Count }
        'archive'     { return @(Select-String -Path (Join-Path $nb '2-档案.md') -Pattern '^### ' -Encoding UTF8).Count }
        'tracks'      { return @(Get-ChildItem (Join-Path $Root 'track') -File).Count }
        'verifycount' { return @(Select-String -Path (Join-Path $Root 'verify.ps1') -Pattern "Add-Result '" -Encoding UTF8).Count }
        default       { return $null }
    }
}

if ($List) {
    if (-not (Test-Path $Log)) { Write-Host '还没有预测记录'; exit 0 }
    $rs = @(); foreach ($l in (Get-Content $Log -Encoding UTF8)) { if ($l.Trim()) { try { $rs += ($l | ConvertFrom-Json) } catch { } } }
    $hit = @($rs | Where-Object { $_.hit }).Count
    Write-Host ("共 {0} 条预测，命中 {1} 条（{2}%）" -f $rs.Count, $hit, $(if ($rs.Count) { [math]::Round(100*$hit/$rs.Count) } else { 0 })) -ForegroundColor Cyan
    foreach ($r in ($rs | Select-Object -Last 10)) {
        Write-Host ("  {0}  {1,-12} 预期 {2} 实测 {3} {4}" -f $r.time, $r.target, $r.expect, $r.actual, $(if ($r.hit) { '命中' } else { '偏差' })) -ForegroundColor $(if ($r.hit) { 'Green' } else { 'Yellow' })
    }
    exit 0
}

# 强制：三个参数缺一不给数
if (-not $Target -or -not $Expect -or -not $Why) {
    Write-Host '必须先给预测，才给数字。' -ForegroundColor Yellow
    Write-Host '  用法： .\fore.ps1 -Target scripts -Expect 34 -Why "基线33+claim1" [-Range 0]'
    Write-Host '  目标： scripts pages criteria ledger core conclusions sayings archive tracks verifycount'
    exit 1
}

$expNum = 0
if (-not [int]::TryParse($Expect, [ref]$expNum)) { Write-Host "预期必须是整数：$Expect" -ForegroundColor Red; exit 1 }

# 顺序写死：先落预测 → 再量 → 再比
$stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
$actual = Measure-Target $Target
$diff = $actual - $expNum
$hit = ([math]::Abs($diff) -le $Range)

$rec = [pscustomobject]@{
    time   = $stamp
    target = $Target
    expect = $expNum
    range  = $Range
    actual = $actual
    diff   = $diff
    why    = $Why
    hit    = $hit
}
[IO.File]::AppendAllText($Log, ($rec | ConvertTo-Json -Compress) + "`n", $enc)

Write-Host ''
Write-Host ("预期 {0}（±{1}）  实测 {2}  差 {3}" -f $expNum, $Range, $actual, $diff) -ForegroundColor $(if ($hit) { 'Green' } else { 'Yellow' })
Write-Host ("  理由：{0}" -f $Why) -ForegroundColor DarkGray
if (-not $hit) {
    Write-Host '  偏差 → 顺着追：先查基数（我假设什么是旧的？），再查测法（量的是什么？）' -ForegroundColor Yellow
}
Write-Host ("  已记入 track\预测数据.jsonl（第 {0} 条）" -f (@(Get-Content $Log -Encoding UTF8 | Where-Object { $_.Trim() }).Count)) -ForegroundColor DarkGray
exit 0
