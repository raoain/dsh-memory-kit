# archive-notebook.ps1 — 档案层收缩：把老条目移进月度归档，主文件只留索引
#
# 为什么要有这个：2-档案.md 只进不出。今天 20 条 7.7 KB，一年就是几百条 ——
# 上下文还没撑爆，人先被淹没。收缩要做成机制，不能靠手动搬。
#
# 用法：
#   .\archive-notebook.ps1            # 30 天前的条目移入 archive\
#   .\archive-notebook.ps1 -Days 7    # 更激进
#   .\archive-notebook.ps1 -DryRun    # 只看会动哪些，不写文件
#   .\archive-notebook.ps1 -Root D:\tmp\nb -Days -1   # 拿副本试刀，别动真文件
param(
    [int]$Days = 30,
    [switch]$DryRun,
    [string]$Root = $Notebook
)
. (Join-Path $PSScriptRoot '_root.ps1')

$ErrorActionPreference = 'Stop'

# 解析条目日期。优先完整日期 YYYY-MM-DD；
# 兼容 2026-10-28 之前的旧条目（MM-DD，年份只能猜，猜错就会误归档）。
# 解析不出来返回 $null —— 调用方必须当「不动它」处理，不能当 0 天处理。
function Get-EntryDate($text) {
    $m = [regex]::Match($text, '时间：\s*(\d{4})-(\d{2})-(\d{2})')
    if ($m.Success) {
        try { return [datetime]::new([int]$m.Groups[1].Value, [int]$m.Groups[2].Value, [int]$m.Groups[3].Value) }
        catch { return $null }
    }
    $m = [regex]::Match($text, '时间：\s*(\d{2})-(\d{2})')
    if ($m.Success) {
        $mm = [int]$m.Groups[1].Value
        $dd = [int]$m.Groups[2].Value
        try {
            $d = [datetime]::new((Get-Date).Year, $mm, $dd)
            if ($d -gt (Get-Date).Date) { $d = [datetime]::new((Get-Date).Year - 1, $mm, $dd) }
            return $d
        } catch { return $null }
    }
    return $null
}

$Target = Join-Path $Root '2-档案.md'
$ArchDir = Join-Path $Root 'archive'

if (-not (Test-Path $Target)) { throw "找不到档案层: $Target" }
New-Item -ItemType Directory -Force -Path $ArchDir | Out-Null

$now = (Get-Date).Date   # 只用日期，避免时分秒参与比较
$lines = [IO.File]::ReadAllLines($Target, [Text.Encoding]::UTF8)

# 找到第一个条目标题（### 开头），前面的是文件头
$firstIdx = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^###\s') { $firstIdx = $i; break }
}
if ($firstIdx -lt 0) { Write-Host '没有条目，不用归档'; return }

$header = $lines[0..($firstIdx - 1)]
$body = $lines[$firstIdx..($lines.Count - 1)]

# 按 ### 切块
$blocks = @()
$cur = $null
foreach ($ln in $body) {
    if ($ln -match '^###\s') {
        if ($cur) { $blocks += ,$cur }
        $cur = @($ln)
    } elseif ($cur) {
        $cur += $ln
    }
}
if ($cur) { $blocks += ,$cur }

$keep = @()
$move = @()
$noDate = @()
foreach ($b in $blocks) {
    $text = $b -join "`n"
    $d = Get-EntryDate $text
    if ($null -eq $d) {
        # 日期算不出来就留在主文件 —— 宁可多留，也不能因为算错而被莫名归档
        $noDate += ,$b
        $keep += ,$b
        continue
    }
    $age = ($now - $d).TotalDays
    if ($age -lt 0) { $age = 0 }
    if ($age -gt $Days) { $move += ,$b } else { $keep += ,$b }
}

if ($noDate.Count -gt 0) {
    Write-Host ("WARN  {0} 条解析不出时间，已保留在主文件：" -f $noDate.Count) -ForegroundColor Yellow
    foreach ($b in $noDate) { Write-Host ("      " + $b[0]) -ForegroundColor DarkGray }
}

if ($move.Count -eq 0) {
    Write-Host ("没有超过 {0} 天的条目，不用归档" -f $Days) -ForegroundColor DarkGray
    return
}

# 按月分组写入 archive\2-档案-YYYY-MM.md
$groups = @{}
foreach ($b in $move) {
    $text = $b -join "`n"
    $d = Get-EntryDate $text
    $key = if ($d) { $d.ToString('yyyy-MM') } else { $now.ToString('yyyy-MM') }
    if (-not $groups.ContainsKey($key)) { $groups[$key] = @() }
    $groups[$key] += ,$b
}

foreach ($k in $groups.Keys) {
    $f = Join-Path $ArchDir ("2-档案-{0}.md" -f $k)
    if ($DryRun) {
        Write-Host ("[dry-run] 会归档 {0} 条 -> {1}" -f $groups[$k].Count, $f) -ForegroundColor Yellow
        continue
    }
    $chunk = ($groups[$k] | ForEach-Object { $_ -join "`n" }) -join "`n`n"
    if (Test-Path $f) {
        Add-Content -Path $f -Value ("`n" + $chunk) -Encoding UTF8
    } else {
        $head = "# 档案层归档 · $k`n`n> 从 2-档案.md 移出的条目，按需查。`n"
        [IO.File]::WriteAllText($f, $head + "`n" + $chunk, (New-Object Text.UTF8Encoding($true)))
    }
    Write-Host ("归档 {0} 条 -> {1}" -f $groups[$k].Count, $f) -ForegroundColor Green
}

if ($DryRun) { Write-Host '（dry-run，未写入任何文件）'; return }

# 主文件：保留头部 + 未过期条目 + 归档索引
$idxLines = @('', '## 归档索引', '')
foreach ($k in ($groups.Keys | Sort-Object -Descending)) {
    $idxLines += ("- {0}：{1} 条 → archive\2-档案-{0}.md" -f $k, $groups[$k].Count)
}
$newText = (($header -join "`n").TrimEnd()) + "`n`n" + (($keep | ForEach-Object { $_ -join "`n" }) -join "`n`n") + "`n" + ($idxLines -join "`n") + "`n"
[IO.File]::WriteAllText($Target, $newText, (New-Object Text.UTF8Encoding($true)))
Write-Host ("主文件收缩完成：移出 {0} 条，剩 {1} 条" -f $move.Count, $keep.Count) -ForegroundColor Green
