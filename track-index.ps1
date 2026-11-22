# track-index.ps1 — 生成「区册」：把 track 里的文件按区登记，供收工时归档与查找
#
# 为什么要它：track 下 281 个文件混在一层，收工时"今天的结果放哪"没有落点。
# 2026-11-22 用户定：分三区（本体理论 / 术语 / 杂项），每天收工把当天结果分纳归档，并更新索引。
#
# 用法： powershell -NoProfile -File F:\Tools\coo-day1\track-index.ps1
# 产物： track\区册\文件区册.md （自动生成，不手改）
# 退出码：0 = 生成成功

param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_root.ps1')

$Track = Join-Path $Root 'track'
$OutDir = Join-Path $Track '区册'
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }

# 分类规则：**先看目录（落点），再看文件名**（2026-11-22 用户定：以后新东西直接存到对应分区）
$dirZones = @{
    'theory' = 'A-本体理论'
    'terms'  = 'B-术语'
    'misc'   = 'C-杂项'
}

# 文件名规则（旧文件都还在 track 根，靠它归类）
$rules = @(
    @{ Zone = 'A-本体理论'; Pattern = '理论|摊账律|缴费篇|熵的代价|公式结果账|个体成长篇|意识通用论|天道篇|逻辑图|树挂载表|数学-链|齿轮论|必要的阶梯|the-ladder|大计划|完工清单|存续|跳跃|反推' },
    @{ Zone = 'B-术语';     Pattern = '术语|说法|区册|6-话|对照' },
    @{ Zone = 'C-杂项';     Pattern = '.*' }
)

function Get-Zone([string]$relPath, [string]$name) {
    $first = ($relPath -split '[\\/]')[0]
    if ($dirZones.ContainsKey($first)) { return $dirZones[$first] }
    foreach ($r in $rules) { if ($name -match $r.Pattern) { return $r.Zone } }
    return 'C-杂项'
}

$files = Get-ChildItem $Track -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notlike "*$([IO.Path]::DirectorySeparatorChar)区册$([IO.Path]::DirectorySeparatorChar)*" } |
    Where-Object { $_.FullName -notlike "*$([IO.Path]::DirectorySeparatorChar)archive$([IO.Path]::DirectorySeparatorChar)*" } |
    Where-Object { $_.FullName -notlike "*$([IO.Path]::DirectorySeparatorChar)tmp$([IO.Path]::DirectorySeparatorChar)*" }

$rows = foreach ($f in $files) {
    $rel = $f.FullName.Substring($Track.Length + 1)
    $zone = Get-Zone $rel $f.Name
    $lines = if ($f.Extension -in '.md', '.txt') { @(Get-Content $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue).Count } else { '' }
    [pscustomobject]@{ Zone = $zone; Rel = $rel; Lines = $lines; Bytes = $f.Length; Day = $f.LastWriteTime.ToString('MM-dd') }
}

$sb = New-Object Text.StringBuilder
[void]$sb.AppendLine('# 文件区册（自动生成，不手改）')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("> 生成时间：$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))｜共 $($rows.Count) 个文件")
[void]$sb.AppendLine('> 分区：**A-本体理论**（根、式子、账本、母本、论证稿）／**B-术语**（说法与对照）／**C-杂项**（其余）。`archive\`、`tmp\`、`区册\` 不进表。')
[void]$sb.AppendLine('> 用法：收工时把当天新增文件归到对应区（在本文末"今日新增"段登记），并跑一次本脚本刷新。')

foreach ($zone in @('A-本体理论', 'B-术语', 'C-杂项')) {
    $zr = @($rows | Where-Object { $_.Zone -eq $zone } | Sort-Object Rel)
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("## $zone（$($zr.Count) 个）")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| 文件 | 行 | 字节 | 改于 |')
    [void]$sb.AppendLine('|---|---|---|---|')
    foreach ($r in $zr) {
        $lb = if ($r.Lines -eq '') { '-' } else { $r.Lines }
        [void]$sb.AppendLine("| ``$($r.Rel)`` | $lb | $($r.Bytes) | $($r.Day) |")
    }
}

$outPath = Join-Path $OutDir '文件区册.md'
[IO.File]::WriteAllText($outPath, $sb.ToString(), (New-Object Text.UTF8Encoding($false)))

$byZone = $rows | Group-Object Zone | ForEach-Object { "$($_.Name)=$($_.Count)" }
Write-Host ("区册已生成: {0}" -f $outPath)
Write-Host ("  分区: {0}" -f ($byZone -join ' / '))
exit 0
