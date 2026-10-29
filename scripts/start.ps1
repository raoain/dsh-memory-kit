# start.ps1 — 开工一条命令：wake + verify + pin + probe
#
# 为什么要有它：2026-10-29 晚上，wake 留痕停在 21:20，之后两小时我一直在干活却没再跑过。
# 原因不是忘，是「开工三件」分散成三条命令，每条都要我记得。
# 结构性修法：把四条捏成一条 —— 漏跑的机会从四次降到一次。
#
# 用法： powershell -NoProfile -File <你的项目根>\start.ps1

$ErrorActionPreference = 'Continue'
$Root = (Get-Location).Path
$t0 = Get-Date

function Step($name, $file, $extra) {
    Write-Host ("`n=== {0} ===" -f $name) -ForegroundColor Cyan
    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $Root $file))
    if ($extra) { $args += $extra }
    & powershell @args 2>&1 | ForEach-Object { $_ }
}

Step 'wake（读三页 + 留痕）' 'wake.ps1' $null
Step 'verify（结构检查）' 'verify.ps1' $null
Step 'pin（值与哈希对账）' 'pin.ps1' '-Diff'
Step 'probe（检查器探针）' 'probe.ps1' $null

$sec = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
Write-Host ("`n=== 开工检查完成：{0} 秒 ===" -f $sec) -ForegroundColor Green
Write-Host ("留痕时间：{0}" -f (Get-Content (Join-Path $Root 'track\wake-last.txt') -Encoding UTF8))
