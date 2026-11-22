# guide-update.ps1 — refresh the numbers inside the compressed outline (总纲-压缩版)
#
# Why: the outline is the single entry for a new window, so its numbers go stale the
# moment work continues. 2026-11-22 user: "那个压缩你每次收工也得改得同时更新".
#
# What it does: rewrites ONLY machine-checkable spots (update time, ledger lines/sections,
# verify totals, zone counts). Written conclusions are NOT auto-edited — they need a human
# decision, and the script says so when it cannot find a spot.
#
# usage: powershell -NoProfile -File F:\Tools\coo-day1\guide-update.ps1
# exit: 0 wrote / unchanged, 2 outline missing

param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_root.ps1')

$outline = Join-Path $Root 'track\theory\总纲-压缩版-20261122.md'
if (-not (Test-Path $outline)) {
    Write-Host 'guide-update: outline not found -> ' $outline -ForegroundColor Yellow
    exit 2
}

$text = [IO.File]::ReadAllText($outline, [Text.Encoding]::UTF8)
$before = $text

# 1) ledger lines / sections
$ledger = Join-Path $Root 'track\theory\公式结果账-20261120.md'
$ledgerLine = ''
if (Test-Path $ledger) {
    $lt = [IO.File]::ReadAllText($ledger, [Text.Encoding]::UTF8)
    $lines = ($lt -split "`n").Count
    $sects = ([regex]::Matches($lt, '(?m)^## ')).Count
    $ledgerLine = "结果账 **$lines 行 / $sects 节**"
    $text = [regex]::Replace($text, '结果账 \*\*\d+ 行 / \d+ 节\*\*', $ledgerLine)
}

# 2) verify totals (51 项：OK 49 / SOFT 2 / WARN 0 / FAIL 0)
$vsum = & (Join-Path $Root 'verify.ps1') *>&1 | Select-String -Pattern '^\s*\d+ 项：' | Select-Object -Last 1
if ($vsum) {
    $m = [regex]::Match([string]$vsum.Line, '(\d+) 项：OK (\d+) / SOFT (\d+)[^/]*/ WARN (\d+) / FAIL (\d+)')
    if ($m.Success) {
        $newV = "``verify`` " + $m.Groups[1].Value + " 项 → **OK " + $m.Groups[2].Value + " / SOFT " + $m.Groups[3].Value + " / WARN " + $m.Groups[4].Value + " / FAIL " + $m.Groups[5].Value + "**"
        # 宽松匹配：旧值可能缺 WARN 段（手写时少写），用 [^*]* 整段吞掉再重写，保证格式统一
        $pat = '(?m)^(- \*\*工程\*\*：)`verify` \d+ 项 → \*\*[^*]*\*\*'
        $text = [regex]::Replace($text, $pat, ('$1' + $newV))
    }
}

# 3) zone counts (A / B / C)
$idx = Join-Path $Root 'track-index.ps1'
if (Test-Path $idx) {
    $z = & powershell -NoProfile -ExecutionPolicy Bypass -File $idx *>&1 | Select-String -Pattern '分区:'
    if ($z) {
        $zm = [regex]::Match([string]$z.Line, 'A-本体理论=(\d+) / B-术语=(\d+) / C-杂项=(\d+)')
        if ($zm.Success) {
            $newZ = "A" + $zm.Groups[1].Value + " / B" + $zm.Groups[2].Value + " / C" + $zm.Groups[3].Value
            $text = [regex]::Replace($text, 'A\d+ / B\d+ / C\d+', $newZ)
            $text = [regex]::Replace($text, '（A\d+/B\d+/C\d+', "（$newZ")
        }
    }
}

# 4) update stamp
$stamp = '> 更新：' + (Get-Date).ToString('yyyy-MM-dd HH:mm') + '（`guide-update.ps1` 自动刷新数字；结论部分手写，改了要人定）'
if ($text -match '(?m)^> 更新：.*$') { $text = [regex]::Replace($text, '(?m)^> 更新：.*$', $stamp) }
else { $text = $text -replace '(?s)^(# [^\n]*\n)', "`$1`n$stamp`n" }

if ($text -ne $before) {
    [IO.File]::WriteAllText($outline, $text, (New-Object Text.UTF8Encoding($false)))
    Write-Host ('guide-update: written ' + $outline)
    if ($ledgerLine) { Write-Host ('  ' + $ledgerLine) }
} else {
    Write-Host 'guide-update: nothing changed'
}
exit 0
