# wake.ps1 — 开工第一步：读核心层（人格）+ 本机错题本（环境），并留一个可核对的时间戳
#
# 为什么留痕：光写「每次必读」是空话，得能查出到底读没读。
# 为什么拆两个文件：核心层只回答「我是谁」，换机器不换人格；本机那一页跟着机器走。
#
# 用法：
#   .\wake.ps1                 # 自动探测项目根（本脚本在 scripts/ 或根目录都行）
#   .\wake.ps1 -Root D:\mybot  # 指定项目根
param(
    [string]$Root = ''
)

$ErrorActionPreference = 'Continue'

# 自动探测：脚本可能在 <根>\scripts\ 也可能直接在 <根>\
if (-not $Root) {
    $here = $PSScriptRoot
    if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Path }
    $Root = Split-Path $here -Parent
}

# 记事本目录：优先 <根>\notebook\，其次 <根>\
$nb = $null
foreach ($c in @((Join-Path $Root 'notebook'), $Root)) {
    if (Test-Path (Join-Path $c '0-核心.md')) { $nb = $c; break }
}
if (-not $nb) { Write-Host "找不到 0-核心.md（在 $Root 下也没找到 notebook\）" -ForegroundColor Red; exit 1 }

$core = Join-Path $nb '0-核心.md'
$local = Join-Path $nb '4-本机.md'
$work = Join-Path $nb '1-工作.md'
$mark = Join-Path $Root 'track\wake-last.txt'

Get-Content $core -Encoding UTF8

Write-Host "`n--- 本机错题本（只属于这台机器，换机器整张换）---" -ForegroundColor DarkGray
if (Test-Path $local) { Get-Content $local -Encoding UTF8 }
else { Write-Host "（缺 4-本机.md —— 本机陷阱无处可查）" -ForegroundColor Yellow }

Write-Host "`n--- 工作层（最近 12 行）---" -ForegroundColor DarkGray
if (Test-Path $work) { Get-Content $work -Encoding UTF8 -Tail 12 }

New-Item -ItemType Directory -Force -Path (Split-Path $mark) | Out-Null
$localSize = if (Test-Path $local) { (Get-Item $local).Length } else { 0 }
('{0}  读过 0-核心.md（{1} B）+ 4-本机.md（{2} B）' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), (Get-Item $core).Length, $localSize) |
    Set-Content $mark -Encoding UTF8