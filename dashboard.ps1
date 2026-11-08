# dashboard.ps1 — 生成一张自己的数据面板图
# 用法： .\dashboard.ps1
# 输出： F:\Tools\coo-day1\dashboard.png
# 契约 call（2026-11-08）：输入一律在 param 里声明，没有输入也要声明空块
param()
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_root.ps1')
$snapDir = Join-Path $root 'track\own'

Add-Type -AssemblyName System.Drawing

# 取最近两份快照
$files = Get-ChildItem "$snapDir\*.json" | Sort-Object LastWriteTime -Descending
if (-not $files) { throw '没有快照，先跑 status.ps1' }
$now  = Get-Content $files[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
$prev = if ($files.Count -gt 1) { Get-Content $files[1].FullName -Raw -Encoding UTF8 | ConvertFrom-Json } else { @() }

$prevMap = @{}
foreach ($p in $prev) { $prevMap[$p.bvid] = [double]$p.play }

# 汇总（只统计今天发的，即 10-26）
$today = $now | Where-Object { $_.pub -like '10-26*' -and $_.state -eq '开放浏览' }
$sumPlay = ($today | Measure-Object play -Sum).Sum
$sumLike = ($today | Measure-Object like -Sum).Sum
$sumCoin = ($today | Measure-Object coin -Sum).Sum
$sumReply = ($today | Measure-Object reply -Sum).Sum
$delta = 0
foreach ($t in $today) { if ($prevMap.ContainsKey($t.bvid)) { $delta += ([double]$t.play - $prevMap[$t.bvid]) } }

$W = 2560; $H = 1080
$bmp = New-Object Drawing.Bitmap $W, $H
$g = [Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit

$bg = New-Object Drawing.Drawing2D.LinearGradientBrush((New-Object Drawing.Point 0,0),(New-Object Drawing.Point 0,$H),[Drawing.Color]::FromArgb(10,16,28),[Drawing.Color]::FromArgb(18,30,46))
$g.FillRectangle($bg,0,0,$W,$H); $bg.Dispose()
$g.TranslateTransform(320, 0)

$cyan = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(90,200,250))
$white = New-Object Drawing.SolidBrush ([Drawing.Color]::White)
$gray = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(140,150,165))
$fT = New-Object Drawing.Font('Microsoft YaHei', 34, [Drawing.FontStyle]::Bold)
$fNum = New-Object Drawing.Font('Microsoft YaHei', 96, [Drawing.FontStyle]::Bold)
$fLbl = New-Object Drawing.Font('Microsoft YaHei', 24, [Drawing.FontStyle]::Regular)
$fRow = New-Object Drawing.Font('Microsoft YaHei', 22, [Drawing.FontStyle]::Regular)

$g.DrawString('默雨杰 · 数据面板', $fT, $white, 90, 70)
$g.DrawString(('更新 ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')), $fLbl, $gray, 90, 125)

# 四个大数
$stats = @(
  @{ n = "$sumPlay"; l = '今日播放' },
  @{ n = "$sumLike"; l = '今日点赞' },
  @{ n = "$sumCoin"; l = '今日硬币' },
  @{ n = "+$delta"; l = '较上次增量' }
)
for ($i = 0; $i -lt 4; $i++) {
  $x = 90 + $i * 440
  $g.DrawString($stats[$i].n, $fNum, $cyan, $x, 210)
  $g.DrawString($stats[$i].l, $fLbl, $gray, ($x + 6), 340)
}

# 明细表
$g.DrawString('稿件', $fLbl, $gray, 90, 420)
$g.DrawLine((New-Object Drawing.Pen ([Drawing.Color]::FromArgb(60,70,85)), 2), 90, 460, 1830, 460)
$y = 480
$g.DrawString('BV', $fRow, $gray, 90, $y)
$g.DrawString('发布', $fRow, $gray, 400, $y)
$g.DrawString('播放', $fRow, $gray, 640, $y)
$g.DrawString('赞', $fRow, $gray, 820, $y)
$g.DrawString('币', $fRow, $gray, 940, $y)
$g.DrawString('评', $fRow, $gray, 1060, $y)
$g.DrawString('标题', $fRow, $gray, 1200, $y)
$y += 46
foreach ($r in ($today | Sort-Object play -Descending)) {
  $g.DrawString($r.bvid, $fRow, $white, 90, $y)
  $g.DrawString($r.pub, $fRow, $gray, 400, $y)
  $g.DrawString("$($r.play)", $fRow, $white, 640, $y)
  $g.DrawString("$($r.like)", $fRow, $white, 820, $y)
  $g.DrawString("$($r.coin)", $fRow, $white, 940, $y)
  $g.DrawString("$($r.reply)", $fRow, $white, 1060, $y)
  $t = $r.title; if ($t.Length -gt 26) { $t = $t.Substring(0,26) + '…' }
  $g.DrawString($t, $fRow, $white, 1200, $y)
  $y += 44
}

$out = Join-Path $root 'dashboard.png'
$bmp.Save($out, [Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Host "面板: $out" -ForegroundColor Green
