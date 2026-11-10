# wake.ps1 — 开工第一步：读核心层（人格）+ 本机错题本（环境），并留一个可核对的时间戳
# 为什么要留痕：光写「每次必读」是空话，得能查出到底读没读。
# 为什么拆成两个文件：核心层只回答「我是谁」，换机器不换人格；本机那一页跟着机器走，整张换掉。
# 契约 call（2026-11-08）：输入一律在 param 里声明，没有输入也要声明空块
# 用法：.\wake.ps1（无参数；读三页并写 wake-last.txt 时间戳）
param()
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_root.ps1')
$core = Join-Path $Notebook '0-核心.md'
$local = Join-Path $Notebook '4-本机.md'
$user = Join-Path $Notebook '9-用户.md'
$work = Join-Path $Notebook '1-工作.md'
$mark = Join-Path $Track 'wake-last.txt'

if (-not (Test-Path $core)) { Write-Host "找不到核心层: $core" -ForegroundColor Red; exit 1 }

Get-Content $core -Encoding UTF8

Write-Host "`n--- 本机错题本（只属于这台机器，换机器整张换）---" -ForegroundColor DarkGray
if (Test-Path $local) { Get-Content $local -Encoding UTF8 }
else { Write-Host "（缺 4-本机.md —— 本机陷阱无处可查）" -ForegroundColor Yellow }

Write-Host "`n--- 用户层（他怎么说话：读法，不是身份）---" -ForegroundColor DarkGray
if (Test-Path $user) { Get-Content $user -Encoding UTF8 }
else { Write-Host "（缺 9-用户.md —— 短消息怎么读无处可查）" -ForegroundColor Yellow }

Write-Host "`n--- 加加急·已停派的（要重新想个做法，想到再派下来）---" -ForegroundColor DarkGray
# 2026-11-10：arbiter 到 critical 会停派并写 escalate.jsonl；这里把它们摆出来，等人或大脑接手。
$esc = Join-Path $Track 'escalate.jsonl'
if (Test-Path $esc) {
    $lines = @(Get-Content $esc -Encoding UTF8 | Where-Object { $_.Trim() -ne "" })
    if ($lines.Count -gt 0) {
        Write-Host ("  已停派 {0} 件（最近 5 条，等新做法）：" -f $lines.Count)
        $lines | Select-Object -Last 5 | ForEach-Object { Write-Host ("  - " + $_) }
    } else { Write-Host "  （空）" }
} else { Write-Host "  （还没有 escalate.jsonl）" }

Write-Host "`n--- 记忆区·工作区（上一轮还握在手里的，必读；细节再看 track\workspace.json）---" -ForegroundColor DarkGray
# 2026-11-10 用户：「让他读就行了，这个是他环的一部分，这个是必跑的」。
# 工作区是环上一轮握在手里的那几件，开机不读就等于每轮从零开始。
$ws = Join-Path $Track 'workspace.json'
if (Test-Path $ws) {
    try {
        $w = Get-Content $ws -Encoding UTF8 -Raw | ConvertFrom-Json
        if ($w.items -and $w.items.Count -gt 0) {
            Write-Host ("  第 {0} 轮握着 {1}/{2} 件：" -f $w.round, $w.items.Count, $w.cap)
            foreach ($it in $w.items) { Write-Host ("  - {0}（握着 {1} 轮，{2}）" -f $it.id, $it.held_rounds, $it.kind) }
        } else { Write-Host "  （空：上一轮没有东西留在手上）" }
    } catch { Write-Host "（workspace.json 读不动）" -ForegroundColor Yellow }
} else { Write-Host "  （还没有 workspace.json：mind 没跑过）" -ForegroundColor Yellow }

Write-Host "`n--- 工作层（顶部指路块 + 最近 12 条）---" -ForegroundColor DarkGray
if (Test-Path $work) {
    Get-Content $work -Encoding UTF8 -TotalCount 18
    Write-Host "  ......" -ForegroundColor DarkGray
    Get-Content $work -Encoding UTF8 -Tail 12
}

New-Item -ItemType Directory -Force -Path (Split-Path $mark) | Out-Null
$localSize = if (Test-Path $local) { (Get-Item $local).Length } else { 0 }
$userSize = if (Test-Path $user) { (Get-Item $user).Length } else { 0 }
('{0}  读过 0-核心.md（{1} B）+ 4-本机.md（{2} B）+ 9-用户.md（{3} B）' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), (Get-Item $core).Length, $localSize, $userSize) |
    Set-Content $mark -Encoding UTF8

Write-Host "读取顺序：中心(0-核心) → 辅助按需（当前拍对应页）；接口：读完要能用到下一步。" -ForegroundColor DarkGray
