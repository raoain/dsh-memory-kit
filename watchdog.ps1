# watchdog.ps1 — 外面的那条腿：定时跑 verify，失败就留下一行红
#
# 为什么要有它：插件只能活在心里（宿主里），宿主一关就没了。
# 这个脚本由 Windows 计划任务调用，不经过 DSH，也不经过我。
#
# 用法（手动）：.\watchdog.ps1
# 计划任务：每 5 分钟一次

# 契约 call（2026-11-08）：输入一律在 param 里声明，没有输入也要声明空块
param()
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_root.ps1')
$Log = Join-Path $Root 'track\watchdog.jsonl'
$Red = Join-Path $Root 'track\watchdog.red'

$out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'verify.ps1') 2>&1
$code = $LASTEXITCODE
$tail = ($out | Select-Object -Last 1) -join ''
$now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

$rec = [ordered]@{
    at    = $now
    verdict = if ($code -eq 0) { '绿' } else { '红' }
    exit  = $code
    tail  = $tail
}
$line = ($rec | ConvertTo-Json -Compress)
Add-Content -LiteralPath $Log -Value $line -Encoding UTF8

if ($code -ne 0) {
    Set-Content -LiteralPath $Red -Value $now -Encoding UTF8
    Write-Host "RED $now  $tail" -ForegroundColor Red
} else {
    if (Test-Path $Red) { Remove-Item -LiteralPath $Red -Force }
    Write-Host "GREEN $now"
}
# machine-readable exit (adapter reads only this line): state 0 pass / 1 warn / 2 fail / 3 unknown
$st = 0
if ($code -eq 1) { $st = 2 } elseif ($code -ne 0) { $st = 3 }
Write-Output ("SIG " + (@{ state = $st; counts = @($code) } | ConvertTo-Json -Compress))

# 把 verify 的结果送进总线（2026-11-08）：watchdog 每 5 分钟跑一次 verify，
# 但以前输出被吞掉、总线不知道 verify 跑过 —— 于是 pulse 一直报它「饿」。
# 这里落盘 + 走 adapter，总线上记的是 verify 的真实结果（1 号器官）。
try {
    $outDir = Join-Path $Root 'track\out'
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    $outFile = Join-Path $outDir 'verify.txt'
    $out | Set-Content -LiteralPath $outFile -Encoding UTF8
    & node (Join-Path $Root 'core\adapter.mjs') 1 $outFile --exit $code 2>&1 | Out-Null
} catch {
    Write-Host ("adapter 失败：" + $_.Exception.Message) -ForegroundColor Yellow
}
