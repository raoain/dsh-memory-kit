# archive-notebook.ps1 — 档案层收缩：把老条目移进月度归档，主文件只留索引
#
# 为什么要有这个：档案层只进不出。二十条 7 KB，一年就是几百条 ——
# 上下文还没撑爆，人先被淹没。收缩要做成机制，不能靠手动搬。
#
# 用法：
#   .\archive-notebook.ps1                       # 30 天前的条目移入 archive\
#   .\archive-notebook.ps1 -Days 7               # 更激进
#   .\archive-notebook.ps1 -DryRun               # 只看会动哪些，不写文件
#   .\archive-notebook.ps1 -Root D:\tmp\nb -Days -1   # 拿副本试刀
#
# ⚠ 拿副本试刀前必须断言隔离：先记真文件哈希，跑完比对。
#   参数名与脚本内变量不得同名——PowerShell 不区分大小写，会被覆盖。
param(
    [int]$Days = 30,
    [switch]$DryRun,
    [string]$Root = 'F:\Tools\coo-day1\notebook',   # ← 改成你自己的记事本目录
    [string]$File = '2-档案.md'                       # 档案层文件名
)

$ErrorActionPreference = 'Stop'
$Target  = Join-Path $Root $File
$ArchDir = Join-Path $Root 'archive'

if (-not (Test-Path $Target)) { throw "找不到档案层: $Target" }
New-Item -ItemType Directory -Force -Path $ArchDir | Out-Null

$today = (Get-Date).Date   # 只用日期，避免时分秒参与比较
$lines = [IO.File]::ReadAllLines($Target, [Text.Encoding]::UTF8)

$firstIdx = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^###\s') { $firstIdx = $i; break }
}
if ($firstIdx -lt 0) { Write-Host '没有条目，不用归档'; return }

$header = $lines[0..($firstIdx - 1)]
$body   = $lines[$firstIdx..($lines.Count - 1)]

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

$keep = @(); $move = @()
foreach ($b in $blocks) {
    $text = $b -join "`n"
    $age = 0
    $m = [regex]::Match($text, '时间：\s*(\d{2})-(\d{2})')
    if ($m.Success) {
        $mm = [int]$m.Groups[1].Value
        $dd = [int]$m.Groups[2].Value
        try {
            $d = [datetime]::new($today.Year, $mm, $dd)
            if ($d -gt $today) { $d = [datetime]::new($today.Year - 1, $mm, $dd) }  # 跨年
            $age = ($today - $d).TotalDays
            if ($age -lt 0) { $age = 0 }
        } catch { $age = 0 }
    }
    if ($age -gt $Days) { $move += ,$b } else { $keep += ,$b }
}

if ($move.Count -eq 0) { Write-Host ("没有超过 {0} 天的条目，不用归档" -f $Days) -ForegroundColor DarkGray; return }

$groups = @{}
foreach ($b in $move) {
    $text = $b -join "`n"
    $m = [regex]::Match($text, '时间：\s*(\d{2})-(\d{2})')
    $mm = if ($m.Success) { [int]$m.Groups[1].Value } else { $today.Month }
    $ym = $today.Year
    if ($mm -gt $today.Month) { $ym = $today.Year - 1 }
    $key = "{0:D4}-{1:D2}" -f $ym, $mm
    if (-not $groups.ContainsKey($key)) { $groups[$key] = @() }
    $groups[$key] += ,$b
}

foreach ($k in $groups.Keys) {
    $f = Join-Path $ArchDir (([IO.Path]::GetFileNameWithoutExtension($File)) + "-{0}.md" -f $k)
    if ($DryRun) {
        Write-Host ("[dry-run] 会归档 {0} 条 -> {1}" -f $groups[$k].Count, $f) -ForegroundColor Yellow
        continue
    }
    $chunk = ($groups[$k] | ForEach-Object { $_ -join "`n" }) -join "`n`n"
    if (Test-Path $f) {
        Add-Content -Path $f -Value ("`n" + $chunk) -Encoding UTF8
    } else {
        $head = "# 档案层归档 · $k`n`n> 从主档案移出的条目，按需查。`n"
        [IO.File]::WriteAllText($f, $head + "`n" + $chunk, (New-Object Text.UTF8Encoding($true)))
    }
    Write-Host ("归档 {0} 条 -> {1}" -f $groups[$k].Count, $f) -ForegroundColor Green
}

if ($DryRun) { Write-Host '（dry-run，未写入任何文件）'; return }

$idx = @('', '## 归档索引', '')
foreach ($k in ($groups.Keys | Sort-Object -Descending)) {
    $idx += ("- {0}：{1} 条 → archive\{2}-{0}.md" -f $k, $groups[$k].Count, ([IO.Path]::GetFileNameWithoutExtension($File)))
}
$newText = (($header -join "`n").TrimEnd()) + "`n`n" + (($keep | ForEach-Object { $_ -join "`n" }) -join "`n`n") + "`n" + ($idx -join "`n") + "`n"
[IO.File]::WriteAllText($Target, $newText, (New-Object Text.UTF8Encoding($true)))
Write-Host ("主文件收缩完成：移出 {0} 条，剩 {1} 条" -f $move.Count, $keep.Count) -ForegroundColor Green
