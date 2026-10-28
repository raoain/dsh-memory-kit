# verify.ps1 — 一条命令核对「可核对的事实」，输出 OK / WARN / FAIL
#
# 为什么要有这个：所有反馈都是事后型（等你发现、等 12 小时、等我看输出不对）。
# 快速迭代需要「改完当场暴露」的机制，而它必须便宜到能随手跑（目标 <5 秒）。
#
# 用法：
#   .\verify.ps1            # 本地检查，不联网
#   .\verify.ps1 -Deep      # 额外联网核查最近发布（慢，约 10 秒）
#   .\verify.ps1 -Quiet     # 只在有问题时输出（适合塞进其他脚本）
param(
    [switch]$Deep,
    [switch]$Quiet
)

$ErrorActionPreference = 'Continue'
$sw = [Diagnostics.Stopwatch]::StartNew()
$root = $Root
$nb = Join-Path $root 'notebook'
$rows = @()
function Add-Result($level, $item, $detail) {
    $script:rows += [pscustomobject]@{ Level = $level; Item = $item; Detail = $detail }
}

# 1. 核心层：≤2 KB、五节以上
$core = Join-Path $nb '0-核心.md'
if (-not (Test-Path $core)) { Add-Result 'FAIL' '核心层' '文件不存在' }
else {
    $len = (Get-Item $core).Length
    $secs = (Select-String -Path $core -Pattern '^## ' -Encoding UTF8 | Measure-Object).Count
    if ($len -gt 2048) { Add-Result 'FAIL' '核心层大小' ("{0} B（超 {1} B）" -f $len, ($len - 2048)) }
    elseif ($len -gt 2000) { Add-Result 'WARN' '核心层大小' ("{0} B（余 {1} B，贴顶）" -f $len, (2048 - $len)) }
    else { Add-Result 'OK' '核心层大小' "$len B" }
    if ($secs -lt 4) { Add-Result 'WARN' '核心层结构' "只有 $secs 节" } else { Add-Result 'OK' '核心层结构' "$secs 节" }
}

# 2. 墓碑：存在、条目数、空条目
$tomb = Join-Path $nb '3-墓碑.md'
if (-not (Test-Path $tomb)) { Add-Result 'FAIL' '墓碑' '文件不存在' }
else {
    $text = [IO.File]::ReadAllText($tomb, [Text.Encoding]::UTF8)
    $entries = ([regex]::Matches(($text -split '## 新条目怎么加')[0], '(?m)^### ')).Count
    $empty = ([regex]::Matches($text, '(?m)^### .+\r?\n\s*\r?\n(###|$)')).Count
    Add-Result 'OK' '墓碑条目' "$entries 条"
    if ($empty -gt 0) { Add-Result 'WARN' '墓碑空条目' "$empty 条没写原因" }
    if ($text -notmatch '为什么' -or $text -notmatch '现在按') { Add-Result 'WARN' '墓碑格式' '缺少「为什么 / 现在按」三段式' } else { Add-Result 'OK' '墓碑格式' '三段式齐全' }
}

# 3. 开工留痕：今天读过吗
$mark = Join-Path $root 'track\wake-last.txt'
if (-not (Test-Path $mark)) { Add-Result 'FAIL' 'wake 留痕' '不存在（今天没跑过 wake.ps1）' }
else {
    $raw = (Get-Content $mark -Raw -Encoding UTF8).Trim()
    $m = [regex]::Match($raw, '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})')
    if (-not $m.Success) { Add-Result 'WARN' 'wake 留痕' "格式异常: $raw" }
    else {
        $t = [datetime]::ParseExact($m.Groups[1].Value, 'yyyy-MM-dd HH:mm:ss', $null)
        $ageH = ((Get-Date) - $t).TotalHours
        if ($ageH -gt 24) { Add-Result 'WARN' 'wake 留痕' ("{0:N1} 小时前" -f $ageH) }
        elseif ($ageH -gt 12) { Add-Result 'WARN' 'wake 留痕' ("{0:N1} 小时前（偏旧）" -f $ageH) }
        else { Add-Result 'OK' 'wake 留痕' ("{0:N1} 小时前" -f $ageH) }
    }
}

# 4. 备份：双盘 + 最新时间
foreach ($d in '<备份盘A>\coo-backup', '<备份盘B>\coo-backup') {
    $latest = Get-ChildItem $d -Filter 'companion-*.zip' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) { Add-Result 'FAIL' "备份 $(Split-Path $d -Qualifier)" '没有备份文件' }
    else {
        $h = ((Get-Date) - $latest.LastWriteTime).TotalHours
        if ($h -gt 30) { Add-Result 'WARN' "备份 $(Split-Path $d -Qualifier)" ("{0:N1} 小时前" -f $h) }
        else { Add-Result 'OK' "备份 $(Split-Path $d -Qualifier)" ("{0:N1} 小时前" -f $h) }
    }
}

# 5. meow 记忆库
$db = if ($MeowDb) { $MeowDb } else { Join-Path $env:USERPROFILE 'Documents\deepseek-harness\default-workspace\.dsh-meow\memory.db' }
if (-not (Test-Path $db)) { Add-Result 'FAIL' 'meow 记忆库' 'memory.db 不存在' }
else {
    $kb = [math]::Round((Get-Item $db).Length / 1KB, 1)
    if ($kb -lt 20) { Add-Result 'WARN' 'meow 记忆库' "$kb KB（偏小，可能空壳）" } else { Add-Result 'OK' 'meow 记忆库' "$kb KB" }
}

# 6. AGENTS.md：存在 + BOM
$ag = Join-Path $env:USERPROFILE '.dsh\AGENTS.md'
if (-not (Test-Path $ag)) { Add-Result 'FAIL' 'AGENTS.md' '不存在' }
else {
    $b = [IO.File]::ReadAllBytes($ag)
    $hasBom = ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
    if (-not $hasBom) { Add-Result 'WARN' 'AGENTS.md' '缺 BOM（PS 5.1 会读成 ANSI）' }
    else { Add-Result 'OK' 'AGENTS.md' ("{0:N1} KB" -f ($b.Length / 1KB)) }
}

# 7. 最近快照
$snapDir = Join-Path $root 'track\own'
$snap = Get-ChildItem $snapDir -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $snap) { Add-Result 'WARN' '最近快照' '没有快照' }
else {
    $h = ((Get-Date) - $snap.LastWriteTime).TotalHours
    if ($h -gt 30) { Add-Result 'WARN' '最近快照' ("{0:N1} 小时前（该跑 status.ps1 -Diff）" -f $h) }
    else { Add-Result 'OK' '最近快照' ("{0:N1} 小时前" -f $h) }
}

# 8. 垃圾场规模
$trash = Join-Path $root 'trash'
if (Test-Path $trash) {
    $items = Get-ChildItem $trash -Recurse -File | Where-Object { $_.Name -notlike '*.from' }
    $mb = if ($items) { [math]::Round((($items | Measure-Object Length -Sum).Sum / 1MB), 1) } else { 0 }
    if ($mb -gt 200) { Add-Result 'WARN' '垃圾场' "$($items.Count) 项 / $mb MB（该 -Empty 了）" }
    else { Add-Result 'OK' '垃圾场' "$($items.Count) 项 / $mb MB" }
}

# 9. 可选：联网核查最近发布
if ($Deep) {
    $bili = '<bili路径>'
    if (Test-Path $bili) {
        $out = & $bili upload list 2>&1 | Out-String
        try {
            $j = $out | ConvertFrom-Json
            $c = $j.data.counts
            Add-Result 'OK' 'B 站账号' ("已发布 $($c.published) / 审核中 $($c.reviewing) / 退回 $($c.rejected)")
            if ($c.rejected -gt 0) { Add-Result 'WARN' 'B 站退回' "$($c.rejected) 条被退回" }
        } catch { Add-Result 'WARN' 'B 站账号' '读不回统计' }
    }
}

$sw.Stop()
$fail = @($rows | Where-Object Level -eq 'FAIL').Count
$warn = @($rows | Where-Object Level -eq 'WARN').Count

if (-not $Quiet -or $fail -gt 0 -or $warn -gt 0) {
    $rows | ForEach-Object {
        $color = switch ($_.Level) { 'OK' { 'DarkGray' } 'WARN' { 'Yellow' } 'FAIL' { 'Red' } }
        Write-Host ("{0,-5} {1,-16} {2}" -f $_.Level, $_.Item, $_.Detail) -ForegroundColor $color
    }
    Write-Host ("`n{0} 项：OK {1} / WARN {2} / FAIL {3}   （{4:N0} ms）" -f $rows.Count, ($rows.Count - $fail - $warn), $warn, $fail, $sw.ElapsedMilliseconds) `
        -ForegroundColor $(if ($fail -gt 0) { 'Red' } elseif ($warn -gt 0) { 'Yellow' } else { 'Green' })
}

if ($fail -gt 0) { exit 1 } else { exit 0 }
