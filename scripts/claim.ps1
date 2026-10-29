# claim.ps1 — 一句话落盘：任何结论/规则，一条命令就写进该去的文件
#
# 为什么（2026-10-30）：我说过「这句我记在脑子里」——正是今晚反复批判的错误。
# 不写进文件，下次就照旧的做。靠自觉一定会漏，所以把「写」变成一条命令。
# 与 log.ps1 的分工：log 记「做了什么」（流水）；claim 记「想清楚了什么」（结论/规则/偏好）。
#
# 用法：
#   .\claim.ps1 -Text "他说不对=理论不一致" -To 9-用户
#   .\claim.ps1 -Text "拖了就算没做" -To 5-判据 -Why "今晚三次拖账"
#   .\claim.ps1 -Text "试探性想法" -To 待消化
param(
    [Parameter(Mandatory = $true)][string]$Text,
    [ValidateSet('0-核心','1-工作','2-档案','3-墓碑','4-本机','5-判据','6-话','7-接线','8-原话','9-用户','10-链','11-结论','12-判据-专项','13-对照','待消化','大计划')]
    [string]$To = '9-用户',
    [string]$Why = ''
)

$ErrorActionPreference = 'Continue'
$Root = (Get-Location).Path
$enc  = New-Object Text.UTF8Encoding($false)
$nb   = Join-Path $Root 'notebook'

# 目标文件
if ($To -eq '待消化') { $path = Join-Path $Root 'track\待消化.md' }
elseif ($To -eq '大计划') { $path = Join-Path $Root 'track\大计划.md' }
else { $path = Join-Path $nb ($To + '.md') }

if (-not (Test-Path $path)) { Write-Host "目标不存在：$path" -ForegroundColor Red; exit 1 }

$before = (Get-Item $path).Length
$stamp  = (Get-Date).ToString('yyyy-MM-dd HH:mm')

# 组装一行（沿用各页已有的条目格式：- **标题**：正文）
if ($To -eq '待消化') {
    $line = "- [$stamp] $Text" + $(if ($Why) { " ｜ 为什么：$Why" } else { '' }) + " ｜ 来源：claim.ps1 ｜ 嚼过 0 次 ｜ 卡在：未处理"
} else {
    $line = "- **$stamp** $Text" + $(if ($Why) { "（$Why）" } else { '' })
}

[IO.File]::AppendAllText($path, "`r`n" + $line + "`r`n", $enc)
$after = (Get-Item $path).Length

Write-Host ''
Write-Host '已落盘：' -ForegroundColor Green
Write-Host ("  " + $line)
Write-Host ("  目标 {0}  字节 {1} → {2}（+{3}）" -f (Split-Path $path -Leaf), $before, $after, ($after - $before)) -ForegroundColor DarkGray

# 落盘后立刻对账（写文件必须能被读到）
$readBack = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
if (-not $readBack.Contains($Text.Substring(0, [Math]::Min(12, $Text.Length)))) {
    Write-Host '  警告：回读找不到刚写的内容' -ForegroundColor Red
    exit 1
}
Write-Host '  回读确认：内容在里面' -ForegroundColor DarkGray
exit 0
