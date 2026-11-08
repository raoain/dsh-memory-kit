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

# ── 维护一条：不杀、不重起；先等它自己脱身，等不到也只动那一条（2026-11-08 第二版）
# 第一版是错的：杀 powershell（loop 是 node，杀不到）、杀全部（不是只杀卡住的）、
# 杀完重起（那一刀本身就是「断」，而断正是要避免的）。
# 而且根本不必杀：loop.mjs 每轮有 30-120 秒 deadline，卡住的子进程会被它自己杀掉继续。
# 心跳停 120 秒是「卡」，不是「死」。三档：
#   < 120 秒      不动（loop 自己的 deadline 覆盖了）
#   120..600 秒   只记录，不动手（还在 2 倍 deadline 以内）
#   > 600 秒      才动手，而且只动落后那一条（按 node 进程、按 loop 名）
$hbAge = 9999
$hbOut = & node (Join-Path $Root 'core\timers-alive.mjs') 2>$null
try { if ($hbOut) { $hbAge = [int]("$hbOut".Trim()) } } catch { }
if ($hbAge -gt 120) {
    $act = if ($hbAge -gt 600) { "acted" } else { "waiting" }
    $note = [ordered]@{ at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss"); heartAge = $hbAge; action = $act; killed = 0 }
    if ($hbAge -gt 600) {
        # 只动真正落后的那一条：找名字是 reflex 的那条 loop 的 node 进程。
        # 其它 loop（watchdog/drift/sweep）没卡，杀了就是主动制造断。
        $stuck = Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object { $_.CommandLine -like '*loop.mjs*' -and $_.CommandLine -like '*--name reflex*' }
        foreach ($sp in $stuck) {
            Stop-Process -Id $sp.ProcessId -Force -ErrorAction SilentlyContinue
            $note.killed = $note.killed + 1
            $lk = Join-Path $Root 'track\.locks\reflex.lock'
            if (Test-Path $lk) { Remove-Item $lk -Force -ErrorAction SilentlyContinue }
        }
        & wscript.exe (Join-Path $Root 'start-timers.vbs') 2>$null
    }
    # 断没断、断了多久，都写下来——断过就是断过，不许假装没断
    Add-Content -LiteralPath (Join-Path $Root "track\watchdog.heal.jsonl") -Value (($note | ConvertTo-Json -Compress)) -Encoding UTF8
}
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
