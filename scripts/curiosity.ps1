# curiosity.ps1 — 外置的「主动性」：自己找缺口，挑一件做
#
# 为什么：语言模型没有内在驱动，不会好奇。能做的只有把「该做什么」做成外部检测——
# 就像痛觉不是感情，是传感器 + 阈值。
# 判据：一次主动行为必须产出「文件里的改变 + 可验结果」，否则不算主动，只算想了想。
#
# 用法：
#   .\curiosity.ps1            列出当前缺口（按可做性排序）
#   .\curiosity.ps1 -Pick      只输出「今天最该自己做的那一件」
param([switch]$Pick)

$ErrorActionPreference = 'Continue'
$Root = (Get-Location).Path

$gaps = @()

# ① 待消化里「卡在」不是"已完成"的
$pend = Join-Path $Root 'track\待消化.md'
if (Test-Path $pend) {
    foreach ($ln in (Get-Content $pend -Encoding UTF8)) {
        if ($ln -notmatch '^- \[2026') { continue }
        if ($ln -match '已完成|已落地|完成 10-30') { continue }
        $t = ($ln -replace '^- \[[^\]]*\]\s*','')
        $stuck = ''
        if ($t -match '卡在[:：]\s*(.+)$') { $stuck = $Matches[1].Trim() }
        $gaps += [pscustomobject]@{ 源='待消化'; 内容=$t.Substring(0,[Math]::Min(60,$t.Length)); 阻力=$stuck; 可做=($stuck -match '要不要|未处理|怎么|值多少') }
    }
}

# ② 结论层里「仅文档 / 未落地」的
$concl = Join-Path $Root 'notebook\11-结论.md'
if (Test-Path $concl) {
    $c = [IO.File]::ReadAllText($concl,[Text.Encoding]::UTF8)
    foreach ($m in [regex]::Matches($c,'(?m)^\|\s*(C\d+[^|]*)\|\s*([^|]*)\|\s*(仅文档|部分)[^|]*\|')) {
        $gaps += [pscustomobject]@{ 源='结论落地索引'; 内容=$m.Groups[1].Value.Trim(); 阻力=$m.Groups[3].Value; 可做=$true }
    }
}

# ③ 已知盲区（写死三条，来自最近教训）
$gaps += [pscustomobject]@{ 源='已知盲区'; 内容='dep-check 不覆盖变量传参调用'; 阻力='要运行时追踪'; 可做=$false }
$gaps += [pscustomobject]@{ 源='已知盲区'; 内容='术语黑名单只扫 post*.md'; 阻力='论证稿术语未管'; 可做=$true }

Write-Host ''
Write-Host ("  缺口 {0} 条" -f $gaps.Count)
$i = 0
foreach ($g in ($gaps | Sort-Object 可做 -Descending)) {
    $i++
    Write-Host ("  {0}. [{1}] {2}" -f $i, $g.源, $g.内容) -ForegroundColor $(if($g.可做){'Yellow'}else{'DarkGray'})
    if (-not $firstTxt -and $g.可做) { $firstTxt = [string]$g.内容; $firstSrc = [string]$g.源 }
    if ($g.阻力) { Write-Host ("     阻力：{0}" -f $g.阻力) -ForegroundColor DarkGray }
}

$doable = @($gaps | Where-Object { $_.可做 })
if ($Pick.IsPresent) {
    if ($doable.Count -eq 0) { Write-Host '  没有可自己做的（都需要人定或需外部条件）' -ForegroundColor Red; exit 1 }
    Write-Host ''
    Write-Host ('  今天自己做的：' + $firstTxt) -ForegroundColor Cyan
    Write-Host ('  来源：' + $firstSrc) -ForegroundColor DarkGray
    Write-Host '  做完必须留下：文件改动 + 可验结果（否则不算主动）' -ForegroundColor DarkGray
}
