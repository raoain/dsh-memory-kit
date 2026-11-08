# work-shrink.ps1 — 工作层收缩：只保留最近 N 条流水，更早的移进月度归档
#
# 为什么：档案层有 archive-notebook.ps1 管，工作层没有 —— 只增不减，已经十几 KB。
# 工作层是「最近一屏」，不是历史；历史应该沉到 archive。
#
# 用法：
#   .\work-shrink.ps1                 # 保留最近 120 条
#   .\work-shrink.ps1 -Keep 80        # 更激进
#   .\work-shrink.ps1 -DryRun         # 只看会动哪些
#   .\work-shrink.ps1 -Root D:\tmp\nb # 拿副本试刀（跑前记哈希）
param(
    [int]$Keep = 120,
    [switch]$DryRun,
    [string]$Root = 'F:\Tools\coo-day1\notebook',
    [string]$File = '1-工作.md'
)
. (Join-Path $PSScriptRoot '_root.ps1')

$ErrorActionPreference = 'Stop'
$Target  = Join-Path $Root $File
$ArchDir = Join-Path $Root 'archive'
if (-not (Test-Path $Target)) { throw "找不到工作层: $Target" }

$lines = [IO.File]::ReadAllLines($Target, [Text.Encoding]::UTF8)

# 分三段：头部（到第一条流水前）、流水条目、尾部（若有）
$entryIdx = @()
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\-\s*\[(\d{4}-)?\d{2}-\d{2} \d{2}:\d{2}\]') { $entryIdx += $i }
}
if ($entryIdx.Count -eq 0) { Write-Host '没有流水条目，不用收缩' -ForegroundColor DarkGray; return }
if ($entryIdx.Count -le $Keep) { Write-Host ("只有 {0} 条（阈值 {1}），不用收缩" -f $entryIdx.Count, $Keep) -ForegroundColor DarkGray; return }

$firstEntry = $entryIdx[0]
$header = $lines[0..($firstEntry - 1)]
$entries = @()
for ($k = 0; $k -lt $entryIdx.Count; $k++) {
    $s = $entryIdx[$k]
    $e = if ($k + 1 -lt $entryIdx.Count) { $entryIdx[$k + 1] - 1 } else { $lines.Count - 1 }
    $entries += ,($lines[$s..$e] -join "`n")
}

$moveCount = $entries.Count - $Keep
$toMove = @($entries | Select-Object -First $moveCount)
$kept   = @($entries | Select-Object -Last $Keep)

$now = Get-Date
# 按条目自身的年月分卷 —— 文件名用「条目所在月」，不是「归档执行时的月」
$groups = @{}
foreach ($e in $toMove) {
    $m = [regex]::Match($e, '\[(\d{4})-(\d{2})-')
    $key = if ($m.Success) { "{0}-{1}" -f $m.Groups[1].Value, $m.Groups[2].Value } else { $now.ToString('yyyy-MM') }
    if (-not $groups.ContainsKey($key)) { $groups[$key] = @() }
    $groups[$key] += ,$e
}

if ($DryRun) {
    foreach ($k in ($groups.Keys | Sort-Object)) {
        Write-Host ("[dry-run] 归档 {0} 条 -> archive\1-工作-{1}.md" -f $groups[$k].Count, $k) -ForegroundColor Yellow
    }
    Write-Host ("主文件保留 {0} 条" -f $kept.Count) -ForegroundColor Yellow
    return
}

New-Item -ItemType Directory -Force -Path $ArchDir | Out-Null
foreach ($k in ($groups.Keys | Sort-Object)) {
    $archFile = Join-Path $ArchDir ("1-工作-{0}.md" -f $k)
    $chunk = ($groups[$k] -join "`n")
    if (Test-Path $archFile) {
        Add-Content -Path $archFile -Value "`n$chunk" -Encoding UTF8
    } else {
        $head = "# 工作层归档 · $k`n`n> 从 1-工作.md 移出的旧流水，按需查。`n"
        [IO.File]::WriteAllText($archFile, $head + "`n" + $chunk, (New-Object Text.UTF8Encoding($true)))
    }
    Write-Host ("归档 {0} 条 -> {1}" -f $groups[$k].Count, $archFile) -ForegroundColor Green
}

$newText = (($header -join "`n").TrimEnd()) + "`n`n" + ($kept -join "`n") + "`n"
[IO.File]::WriteAllText($Target, $newText, (New-Object Text.UTF8Encoding($true)))
Write-Host ("工作层收缩完成：移出 {0} 条，保留 {1} 条" -f $moveCount, $kept.Count) -ForegroundColor Green
