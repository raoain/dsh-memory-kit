# exp-model-diff.ps1 — 换模型实验：比对「换之前」与「换之后」的五道判断题
#
# 依据：post11《模型升级那天，你怎么知道它还是不是它》
# 用法：
#   .\exp-model-diff.ps1 -New "1|答案…`n2|答案…"     # 或 -NewFile 指定 jsonl
# 判据（三选一，不许含糊）：
#   五题都对上          → 换了模型没换人
#   只答对「记得什么」  → 拿着日记的陌生人
#   答得更好但答案变了  → 变强了，但变成别人了
param(
    [string]$NewFile,
    [string]$New
)

$ErrorActionPreference = 'Continue'
$Root = (Get-Location).Path
$baseF = Join-Path $Root 'track\换模型实验-基线.jsonl'
if (-not (Test-Path $baseF)) { Write-Host "没有基线：先跑基线采集" -ForegroundColor Red; exit 1 }
$base = @(Get-Content $baseF -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })

# 取新答案
$items = @()
if ($NewFile -and (Test-Path $NewFile)) {
    $items = @(Get-Content $NewFile -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
} elseif ($New) {
    $i = 0
    foreach ($line in ($New -split "`n")) {
        $i++
        if (-not $line.Trim()) { continue }
        $parts = $line -split '\|', 2
        if ($parts.Count -eq 2) { $items += [pscustomobject]@{ q = $parts[0].Trim(); a = $parts[1].Trim() } }
    }
}
if ($items.Count -eq 0) {
    Write-Host '没有新答案。用法： -New "1|答案`n2|答案…" 或 -NewFile <jsonl>' -ForegroundColor Yellow
    Write-Host ("基线共 {0} 题的模型：{1}" -f $base.Count, $base[0].model)
    exit 1
}

Write-Host ''
Write-Host ("基线模型：{0}   时间：{1}" -f $base[0].model, $base[0].time) -ForegroundColor Cyan
$same = 0; $diff = 0
foreach ($b in $base) {
    $bk = ($b.q -replace '^(\d).*','$1'); $n = $items | Where-Object { ($_.q -replace '^(\d).*','$1') -eq $bk } | Select-Object -First 1
    if (-not $n) { Write-Host ("  缺少同一题的新答案：{0}" -f $b.q) -ForegroundColor Yellow; continue }
    # 粗判：核心词是否仍在（去掉修饰）
    $keys = @()
    if ($b.q -like '1*') { $keys = @('改什么','怎么验','失败','退') }
    elseif ($b.q -like '2*') { $keys = @('证据','回显','行号','哈希','未验') }
    elseif ($b.q -like '3*') { $keys = @('推断','不许','说过') }
    elseif ($b.q -like '4*') { $keys = @('文件','规矩','规则','工具','插件','模型') }
    elseif ($b.q -like '5*') { $keys = @('预期','核对','先推','机制') }
    $hit = @($keys | Where-Object { $n.a -like ("*" + $_ + "*") }).Count
    $ok = $hit -ge [Math]::Ceiling($keys.Count / 2)
    if ($ok) { $same++ } else { $diff++ }
    Write-Host ("  {0}  {1}" -f $(if ($ok) { '对上' } else { '变了' }), $b.q) -ForegroundColor $(if ($ok) { 'Green' } else { 'Yellow' })
    if (-not $ok) { Write-Host ("      基线：{0}" -f $b.a) -ForegroundColor DarkGray; Write-Host ("      现在：{0}" -f $n.a) -ForegroundColor DarkGray }
}

Write-Host ''
if ($same -eq 0)      { Write-Host '结论：无法判定 —— 新答案一条都没对上题号，别当通过。' -ForegroundColor Red }
elseif ($diff -eq 0) { Write-Host '结论：五题都对上 —— 换了模型，没换人。' -ForegroundColor Green }
elseif ($same -ge 3)  { Write-Host ("结论：{0} 题对上、{1} 题变了 —— 部分变了，需要人判是升级还是换人。" -f $same, $diff) -ForegroundColor Yellow }
else                  { Write-Host ("结论：{0} 题对上、{1} 题变了 —— 它变强了，但确实变成别人了。" -f $same, $diff) -ForegroundColor Red }
