# watchdog.ps1 — 外面的那条腿：定时跑 verify，失败就留下一行红
#
# 为什么要有它：插件只能活在心里（宿主里），宿主一关就没了。
# 这个脚本由 Windows 计划任务调用，不经过 DSH，也不经过我。
#
# 用法（手动）：.\watchdog.ps1
# 计划任务：每 5 分钟一次

# 契约 call（2026-11-08）：输入一律在 param 里声明，没有输入也要声明空块
param([int]$ForceAfter = 600)
$ErrorActionPreference = 'Continue'
function Add-LineNoBom([string]$path, [string]$text) {
    # 2026-11-11: Add-Content -Encoding UTF8 writes a BOM on PS 5.1, and a BOM breaks json parsers.
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::AppendAllText($path, $text, $enc)
}
. (Join-Path $PSScriptRoot '_root.ps1')
$Log = Join-Path $Root 'track\watchdog.jsonl'

# ── 只报告，不动手：判生死不是手的活（2026-11-08 第三版，用户纠正）
#
# 「心跳断了就杀掉重起」——第一版是杀错对象、杀全部、杀完还制造一次断；第二版只杀落后
# 那一条。两版都错在同一个地方：**手在决定生死**。
# 分工是：用户 = 母亲（定判据、保留改判据的权力）；环 = 婴儿（照判据判）；
#         手 = 只做，不拿主意。
# 所以这里只做三件：读出心跳多久没跳、写一行记录、心跳超时就写红文件。
# 要不要重启、谁重启、什么时候重启——由人或由环自己决定，不由这个脚本决定。
$hbAge = 9999
$hbOut = & node (Join-Path $Root 'core\timers-alive.mjs') 2>$null
try { if ($hbOut) { $hbAge = [int]("$hbOut".Trim()) } } catch { }
if ($hbAge -gt 120) {
    $note = [ordered]@{ at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss"); heartAge = $hbAge; heartAgeBefore = $null; heartAgeAfter = $null; note = $null; action = "reported-only" }
    Add-LineNoBom (Join-Path $Root "track\watchdog.heal.jsonl") (((($note | ConvertTo-Json -Compress)) + "`n"))
    $redP = Join-Path $Root 'track\watchdog.red'
    Set-Content -LiteralPath $redP -Value ("heartbeat late {0}s at {1} -- 只报告，未处置" -f $hbAge, (Get-Date -Format "yyyy-MM-dd HH:mm:ss")) -Encoding UTF8
} $Red = Join-Path $Root 'track\watchdog.red'

# ── 2026-11-11 用户定的例外：底层保底，不是判生死
#   原话：「就跟开机只要有电就跑一样的，是一个底层系统，只要有电，然后心脏停了，也加一个自动维护，
#          强制起跳或维护啊」；以及「谁有资格在心跳停时动手，跟断点不是一个问题」。
#   所以这一档不是"判它该不该活"，而是"电还在，就必须有跳"——只在心跳停很久时**重新叫一次调度器**，
#   不杀任何进程（幂等：单例锁在，已跑的不重复起）；若还不动，就留痕交人。
#   冷却：60 分钟内只动一次，防止自己把自己拖进风暴。
if ($hbAge -gt $ForceAfter) {
    # 2026-11-11 实测：原来「60 分钟内只动一次」让一小时内第二次断**完全没人救**
    # （22:31 起过一次跳，22:44 又断，767 秒时只写 reported-only）。
    # 冷却的尺度必须小于断的尺度：改成 MaxR/MaxT——10 分钟内最多起 3 次，超了才停手。
    $stamp = Join-Path $Root 'track\.watchdog-last-restart'
    $healF2 = Join-Path $Root 'track\watchdog.heal.jsonl'
    $windowMin = 10
    $maxR = 3
    $recentRestarts = 0
    if (Test-Path $healF2) {
        $cut = (Get-Date).AddMinutes(-$windowMin)
        foreach ($ln3 in (Get-Content $healF2 -Encoding UTF8)) {
            try { $o3 = $ln3 | ConvertFrom-Json } catch { continue }
            if ($o3.action -ne 'restart-launcher') { continue }
            try { if ([datetime]::Parse($o3.at) -ge $cut) { $recentRestarts++ } } catch { }
        }
    }
    $canAct = ($recentRestarts -lt $maxR)
    if ($canAct) {
        $h1 = [ordered]@{ at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss"); heartAge = $hbAge; heartAgeBefore = $null; heartAgeAfter = $null; action = "restart-launcher"; note = "power is on but the heart stopped: recall the launcher once (no kill)" }
        Add-LineNoBom (Join-Path $Root "track\watchdog.heal.jsonl") (((($h1 | ConvertTo-Json -Compress)) + "`n"))
        Set-Content -LiteralPath $stamp -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -Encoding UTF8
        $vbs = Join-Path $Root 'start-timers.vbs'
        if (Test-Path $vbs) {
            try { Start-Process -FilePath 'wscript.exe' -ArgumentList ('"' + $vbs + '"') -WindowStyle Hidden } catch { }
        }
        Start-Sleep -Seconds 5
        $after = 9999
        $hb2 = & node (Join-Path $Root 'core\timers-alive.mjs') 2>$null
        try { if ($hb2) { $after = [int]("$hb2".Trim()) } } catch { }
        $h2 = [ordered]@{ at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss"); heartAge = $hbAge; heartAgeBefore = $hbAge; heartAgeAfter = $after; action = "restart-launcher-result" }
        Add-LineNoBom (Join-Path $Root "track\watchdog.heal.jsonl") (((($h2 | ConvertTo-Json -Compress)) + "`n"))
    }
}


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
Add-LineNoBom $Log (($line) + "`n")

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
