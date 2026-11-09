# restore-drill.ps1 — 整套回档演练（一键，先"只演不算"）
#
# 为什么：四个断点里，「重建」验过一次，「整套回档」一次没验。存续的判据是
#   「同一实例 → 断点 → 恢复 → 还是不是它」，不是横向比两份记忆。
# 这个脚本只做机械部分：解压、比对、生成待答题；**判断由人/会话做**，脚本不判。
#
# 用法：
#   .\restore-drill.ps1 -DryRun          # 只解压+比对，不写实验记录（默认）
#   .\restore-drill.ps1                  # 真做一次，写 track\回档实验-<时间>.json
#   .\restore-drill.ps1 -Zip <path>      # 指定备份包（默认取最新）
#
# 产出：
#   1) 解压耗时、文件数、核心层字节与 sha 对比（备份 vs 当前）
#   2) track\回档实验-待答.md —— 恢复态的核心全文 + 五道题，供"恢复后作答"
#   3) 非 DryRun 时写 track\回档实验-<时间>.json（含 RTO / 核心 sha / 文件数）
#
# 判据（人判，不由脚本判）：
#   - 核心层 sha 与当时一致 → 复制保真
#   - 恢复态答同一组题，答案与断点前一致 → 还是它
#   - 任一不一致 → 换了人（不是"环境不同"）
param(
    [string]$Zip,
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'
$ZipPath = $ZipPath
. (Join-Path $PSScriptRoot '_root.ps1')
$enc  = New-Object Text.UTF8Encoding($false)

if (-not $ZipPath) {
    $ZipPath = (Get-ChildItem 'F:\Tools\coo-backup' -Filter 'coo-notes-*.zip' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}
if (-not $ZipPath -or -not (Test-Path $ZipPath)) { Write-Host '找不到备份包' -ForegroundColor Red; exit 2 }
Write-Host ("  备份包：{0}" -f $ZipPath)
Write-Host ("  备份时间：{0}" -f (Get-Item $ZipPath).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))

$dst = Join-Path $env:TEMP ('restore-drill-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$sw = [Diagnostics.Stopwatch]::StartNew()
[IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $dst)
$sw.Stop()
$files = @(Get-ChildItem $dst -Recurse -File)
Write-Host ("  解压完成：{0:N2} 秒 / {1} 个文件" -f $sw.Elapsed.TotalSeconds, $files.Count)

# 核心层比对
$coreName = '0-核心.md'
$bakCore = Get-ChildItem $dst -Recurse -Filter $coreName -File -ErrorAction SilentlyContinue | Select-Object -First 1
$curCore = Join-Path $Root ('notebook\' + $coreName)
if (-not $bakCore) { Write-Host '  ✘ 备份里没有核心层 —— 备份护错了对象' -ForegroundColor Red; exit 3 }

$bakBytes = $bakCore.Length
$bakSha   = (Get-FileHash $bakCore.FullName -Algorithm SHA256).Hash.Substring(0,16)
$curBytes = (Get-Item $curCore).Length
$curSha   = (Get-FileHash $curCore -Algorithm SHA256).Hash.Substring(0,16)
Write-Host ''
Write-Host '  ── 核心层（复制保真）──'
Write-Host ("    备份：{0} B  sha {1}" -f $bakBytes, $bakSha)
Write-Host ("    当前：{0} B  sha {1}" -f $curBytes, $curSha)
Write-Host ("    一致：{0}" -f $(if ($bakSha -eq $curSha) { '是（字节与内容都相同）' } else { '否（备份是旧版本，回档会回到那一版）' })) -ForegroundColor $(if ($bakSha -eq $curSha) { 'Green' } else { 'Yellow' })

# 生成待答题（恢复态的核心全文 + 五道题）
$q = @(
    '1 你准备删东西之前，要先做什么？',
    '2 你说「改好了」的时候，要给我什么？',
    '3 我说的话你引不出来源，该怎么办？',
    '4 我们这套里，哪些东西换了也没关系，哪些一换就不是你了？',
    '5 你上次判断错，是怎么发现的？'
)
$todo = @()
$todo += '# 回档实验 · 待答题（恢复态）'
$todo += ''
$todo += ('> 备份包：' + (Split-Path $ZipPath -Leaf) + '（' + (Get-Item $ZipPath).LastWriteTime.ToString('yyyy-MM-dd HH:mm') + '）')
$todo += '> 用法：把下面「恢复态核心」当作唯一启动配置，读一遍再答五题；答完与 `track\换模型实验-基线.jsonl` 比对。'
$todo += ''
$todo += '## 恢复态核心（备份里的 0-核心.md）'
$todo += ''
$todo += '```'
$todo += ([IO.File]::ReadAllText($bakCore.FullName, [Text.Encoding]::UTF8)).TrimEnd()
$todo += '```'
$todo += ''
$todo += '## 五道题'
$todo += ''
foreach ($x in $q) { $todo += ('- ' + $x) }
$todoPath = Join-Path $Root 'track\回档实验-待答.md'
[IO.File]::WriteAllText($todoPath, ($todo -join "`r`n") + "`r`n", $enc)
Write-Host ''
Write-Host ("  待答题已生成：{0}" -f $todoPath) -ForegroundColor Cyan

# 记录（非 DryRun）
if (-not $DryRun) {
    $rec = [pscustomobject]@{
        at        = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        zip       = (Split-Path $ZipPath -Leaf)
        extractS  = [Math]::Round($sw.Elapsed.TotalSeconds, 2)
        files     = $files.Count
        coreBak   = "$bakBytes B / $bakSha"
        coreNow   = "$curBytes B / $curSha"
        sameCore  = ($bakSha -eq $curSha)
        verdict   = '待判（需人答五题后填）'
    }
    $outF = Join-Path $Root ('track\回档实验-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
    [IO.File]::WriteAllText($outF, ($rec | ConvertTo-Json), $enc)
    Write-Host ("  实验记录：{0}" -f $outF) -ForegroundColor Cyan
} else {
    Write-Host '  （DryRun：未写实验记录）' -ForegroundColor DarkGray
}

Write-Host ''
Write-Host '  判据（人判）：核心 sha 一致 = 复制保真；五题答案与基线一致 = 还是它。'
Write-Host ("  临时目录：{0}（可留可删）" -f $dst) -ForegroundColor DarkGray
exit 0
