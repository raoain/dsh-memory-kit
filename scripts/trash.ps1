# trash.ps1 — 垃圾场：删除改成移入 trash\YYYY-MM\，30 天后清空
#
# 为什么要有这个：物理文件删了就真没了。昨天那次「20 条档案被归档」是靠备份捞回来的，
# 但备份是整包的、笨重；日常小删除（旧稿、废 spec、试坏的封面）值得一个轻量的回收站。
#
# 用法：
#   .\trash.ps1 -Path F:\Tools\coo-day1\old.md                # 移入垃圾桶
#   .\trash.ps1 -Path F:\Tools\coo-day1\old-dir\              # 目录也行
#   .\trash.ps1 -List                                          # 看里面有什么
#   .\trash.ps1 -Empty                                         # 清掉超过 30 天的
#   .\trash.ps1 -Empty -Days 7                                 # 更积极
#   .\trash.ps1 -Restore -Name 20261028-194500_old.md          # 捞回来
param(
    [string]$Path,
    [switch]$List,
    [switch]$Empty,
    [switch]$Restore,
    [string]$Name,
    [int]$Days = 30,
    [string]$Root = 'F:\Tools\coo-day1\trash'   # ← 改成你自己的
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $Root | Out-Null

if ($List) {
    $items = Get-ChildItem $Root -Recurse -File | Where-Object { $_.Name -notlike '*.from' } | Sort-Object LastWriteTime -Descending
    if (-not $items) { Write-Host '垃圾桶是空的'; return }
    $items | Select-Object @{n='移入时间';e={$_.LastWriteTime.ToString('MM-dd HH:mm')}}, @{n='KB';e={[math]::Round($_.Length/1KB,1)}}, Name,
        @{n='原路径';e={ $f = $_.FullName + '.from'; if (Test-Path $f) { (Get-Content $f -Raw -Encoding UTF8).Trim() } else { '' } }} |
        Format-Table -AutoSize | Out-String -Width 220
    Write-Host ("共 {0} 项，{1:N1} MB" -f $items.Count, (($items | Measure-Object Length -Sum).Sum/1MB))
    return
}

if ($Empty) {
    $cut = (Get-Date).AddDays(-$Days)
    $old = Get-ChildItem $Root -Recurse -File | Where-Object { $_.LastWriteTime -lt $cut }
    if (-not $old) { Write-Host "没有超过 $Days 天的东西" -ForegroundColor DarkGray; return }
    $n = 0; $bytes = 0
    foreach ($f in $old) { $bytes += $f.Length; Remove-Item $f.FullName -Force; $n++ }
    # 清空目录
    Get-ChildItem $Root -Recurse -Directory | Where-Object { -not (Get-ChildItem $_.FullName -Force) } | Sort-Object { $_.FullName.Length } -Descending | ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
    Write-Host ("清掉 {0} 项，{1:N1} MB（阈值 {2} 天）" -f $n, ($bytes/1MB), $Days) -ForegroundColor Green
    return
}

if ($Restore) {
    if (-not $Name) { throw '需要 -Name（用 -List 查看）' }
    $hit = Get-ChildItem $Root -Recurse -File | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if (-not $hit) { throw "垃圾桶里没有 $Name" }
    # 还原到项目根（原路径记在 .from 文件里，这里只做粗还原）
    $dest = Join-Path (Split-Path (Split-Path $Root -Parent) -Parent) (($hit.Name -split '_', 2)[1])
    Copy-Item $hit.FullName $dest -Force
    Write-Host "已复制回 $dest（原文件仍在垃圾桶里）" -ForegroundColor Green
    return
}

if (-not $Path) { throw '需要 -Path，或用 -List / -Empty / -Restore' }
if (-not (Test-Path $Path)) { throw "找不到: $Path" }

$item = Get-Item $Path
$monthDir = Join-Path $Root (Get-Date -Format 'yyyy-MM')
New-Item -ItemType Directory -Force -Path $monthDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$destName = '{0}_{1}' -f $stamp, $item.Name
$dest = Join-Path $monthDir $destName

Move-Item -LiteralPath $item.FullName -Destination $dest -Force
# 记下原路径，方便还原
Set-Content -Path ($dest + '.from') -Value $item.FullName -Encoding UTF8
Write-Host ("已移入垃圾桶: {0}" -f $dest) -ForegroundColor Green
Write-Host ("原路径记在: {0}.from" -f $dest) -ForegroundColor DarkGray
