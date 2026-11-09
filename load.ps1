# load.ps1 — 量载荷
#
# 为什么：地基够不够，只能拿载荷说话。不量载荷就加固，就是给不承力的地方焊钢梁。
# 载荷指标（今天）：会话消息数 / 工具调用数 / 工作层新增条数 / 今天被改的脚本与文档数 / token 用量。
#
# 用法： .\load.ps1            # 量今天，追加一条到 track\载荷.jsonl
#        .\load.ps1 -Show      # 只看历史，不追加
param([switch]$Show)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_root.ps1')
$Out  = Join-Path $Root 'track\载荷.jsonl'
$Node = 'C:\Users\dummy\node.exe'
# 找 node（DSH 自带运行时）
$cands = @(
    (Join-Path $env:USERPROFILE '.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe'),
    (Join-Path $env:USERPROFILE '.dsh\dsh-runtimes\node\bin\node.exe')
)
foreach ($c in $cands) { if (Test-Path $c) { $Node = $c; break } }

$today = (Get-Date).ToString('yyyy-MM-dd')

# 1) 会话统计
$stat = $null
if ((Test-Path $Node) -and (Test-Path (Join-Path $Root 'load.mjs'))) {
    $raw = & $Node (Join-Path $Root 'load.mjs') $today 2>&1 | Out-String
    try { $stat = $raw | ConvertFrom-Json } catch { $stat = $null }
}
if (-not $stat) { $stat = [pscustomobject]@{ ok = $false; userMsgs = 0; assistantMsgs = 0; toolCalls = 0; toolResults = 0; turns = 0 } }

# 2) 工作层今天新增条数
$work = Join-Path $Root 'notebook\1-工作.md'
$workToday = 0
if (Test-Path $work) {
    $workToday = @(Get-Content $work -Encoding UTF8 | Where-Object { $_ -match ("^- \[" + $today) }).Count
}

# 3) 今天被改过的脚本与文档数
$touched = @(Get-ChildItem $Root -Recurse -Include *.ps1,*.md,*.mjs -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\trash\\' -and $_.LastWriteTime.Date -eq (Get-Date).Date }).Count

# 4) token 用量（宿主记账）
$tok = $null
$usage = Join-Path $env:USERPROFILE '.dsh\.dshw-usage.json'
if (Test-Path $usage) {
    try {
        $u = Get-Content $usage -Raw -Encoding UTF8 | ConvertFrom-Json
        $tok = $u.todayUsage
    } catch { $tok = $null }
}

$rec = [pscustomobject]@{
    date        = $today
    time        = (Get-Date).ToString('HH:mm')
    userMsgs    = [int]$stat.userMsgs
    assistantMsgs = [int]$stat.assistantMsgs
    toolCalls   = [int]$stat.toolCalls
    turns       = [int]$stat.turns
    workEntries = [int]$workToday
    filesTouched = [int]$touched
    tokens      = $tok
}

if (-not $Show) {
    if (-not (Test-Path (Split-Path $Out))) { New-Item -ItemType Directory -Force -Path (Split-Path $Out) | Out-Null }
    [IO.File]::AppendAllText($Out, ($rec | ConvertTo-Json -Compress) + "`n", (New-Object Text.UTF8Encoding($false)))
}

Write-Host ''
Write-Host ("载荷 $($rec.date) $($rec.time)") -ForegroundColor Cyan
Write-Host ("  会话消息   你的 {0} 条 / 我的 {1} 条（{2} 轮）" -f $rec.userMsgs, $rec.assistantMsgs, $rec.turns)
Write-Host ("  工具调用   {0} 次" -f $rec.toolCalls)
Write-Host ("  工作层     +{0} 条" -f $rec.workEntries)
Write-Host ("  改动文件   {0} 个（脚本/文档）" -f $rec.filesTouched)
Write-Host ("  token      {0}" -f $(if ($null -ne $rec.tokens) { $rec.tokens } else { '读不到（宿主未记）' }))

# 和历史比一比（至少两条才有意义）
if (Test-Path $Out) {
    $all = @()
    foreach ($ln in (Get-Content $Out -Encoding UTF8)) { if ($ln.Trim()) { try { $all += ($ln | ConvertFrom-Json) } catch { } } }
    if ($all.Count -ge 2) {
        $prev = $all | Where-Object { $_.date -ne $rec.date } | Select-Object -Last 5
        if ($prev.Count -gt 0) {
            $avgTool = [math]::Round((($prev | Measure-Object toolCalls -Average).Average), 1)
            $avgFile = [math]::Round((($prev | Measure-Object filesTouched -Average).Average), 1)
            Write-Host ''
            Write-Host ("  对比最近 {0} 次：工具调用均值 {1}，改动文件均值 {2}" -f $prev.Count, $avgTool, $avgFile) -ForegroundColor DarkGray
            if ($rec.toolCalls -gt $avgTool * 2) { Write-Host '  ⚠ 今天的工具调用是均值的两倍以上（高载荷）' -ForegroundColor Yellow }
            if ($rec.filesTouched -gt $avgFile * 2) { Write-Host '  ⚠ 今天改动的文件是均值的两倍以上（高载荷）' -ForegroundColor Yellow }
        }
    } else {
        Write-Host ''
        Write-Host '  （这是第 1 条记录，还没有历史可比；疲劳阈值要等几条数据）' -ForegroundColor DarkGray
    }
}

exit 0
