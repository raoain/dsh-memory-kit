# log.ps1 — 记一条工作层，自动附上「自上次记录以来改过哪些文件」
#
# 为什么：X→M 这条接缝太宽（覆盖所有改动），逐条堵不可能。
# 需要一个组件替我记得改了什么 —— 否则就会「改了 57 个文件，只记了 12 条」。
#
# 用法：
#   .\log.ps1 -Text "做了什么" [-Evid "证: 命令输出/哈希"]
#   .\log.ps1 -Text "做了什么" -NoFiles     # 不附文件清单
param(
    [Parameter(Mandatory = $true)][string]$Text,
    [string]$Evid = '',
    [switch]$NoFiles
)

$ErrorActionPreference = 'Continue'
$Root = (Get-Location).Path
$Work = Join-Path $Root 'notebook\1-工作.md'
$enc  = New-Object Text.UTF8Encoding($false)

if (-not (Test-Path $Work)) { Write-Host "找不到工作层：$Work" -ForegroundColor Red; exit 1 }

# 1) 找上一次记录的时间
$lastTime = $null
foreach ($ln in (Get-Content $Work -Encoding UTF8)) {
    $m = [regex]::Match($ln, '^- \[(\d{4}-\d{2}-\d{2} \d{2}:\d{2})\]')
    if ($m.Success) { $lastTime = [datetime]::Parse($m.Groups[1].Value) }
}
if (-not $lastTime) { $lastTime = (Get-Date).AddHours(-2) }

# 2) 找那之后改过的文件（跳过垃圾场与构建产物）
$changed = @()
if (-not $NoFiles) {
    $changed = @(Get-ChildItem $Root -Recurse -Include *.ps1,*.md,*.mjs,*.json,*.jsonl -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -notmatch '\\trash\\|\\build\\|\\archive\\|\\audio' -and
            $_.LastWriteTime -gt $lastTime
        } |
        Sort-Object LastWriteTime |
        ForEach-Object { $_.Name })
    $changed = @($changed | Select-Object -Unique)
}

# 3) 组装条目
$now = Get-Date -Format 'yyyy-MM-dd HH:mm'
$line = "- [$now] $Text"
if (-not $NoFiles -and $changed.Count -gt 0) {
    $show = $changed
    if ($show.Count -gt 8) { $show = $show[0..7] }
    $more = if ($changed.Count -gt 8) { " 等 $($changed.Count) 个" } else { '' }
    $line += " ｜ 改过：$($show -join '、')$more"
}
if ($Evid) { $line += " ｜ $Evid" }

# 4) 追加（带 BOM，与工作层一致）
$existing = [IO.File]::ReadAllText($Work, [Text.Encoding]::UTF8)
$head = ""
[IO.File]::AppendAllText($Work, $head + $line + "`r`n", $enc)

Write-Host ''
Write-Host '已记入工作层：' -ForegroundColor Green
Write-Host ("  " + $line)
Write-Host ("  上次记录：{0}；本轮改了 {1} 个文件" -f $lastTime.ToString('yyyy-MM-dd HH:mm'), $changed.Count) -ForegroundColor DarkGray
