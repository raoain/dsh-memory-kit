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
$root = ((Split-Path $PSScriptRoot -Parent))
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
$db = Join-Path $env:USERPROFILE 'Documents\deepseek-harness\default-workspace\.dsh-meow\memory.db'
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


# 10. 脚本静态检查（同名变量 / PS5.1 语法）
$lint = Join-Path $Root 'lint.ps1'
if (Test-Path $lint) {
    $lo = & powershell -NoProfile -ExecutionPolicy Bypass -File $lint -Path $Root -Quiet 2>&1 | Out-String
    $m = [regex]::Match($lo, '(\d+) 处问题')
    if ($m.Success -and [int]$m.Groups[1].Value -gt 0) { Add-Result 'WARN' '脚本 lint' ("{0} 处问题（跑 lint.ps1 看明细）" -f $m.Groups[1].Value) }
    else { Add-Result 'OK' '脚本 lint' '无问题' }
}

# 11. 未钉脚本（改了一半的自动暴露，不靠我嘴说）
$stateFile = Join-Path $Root 'state.json'
if (Test-Path $stateFile) {
    $pins = (Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json).pins.PSObject.Properties.Name
    $unpinned = Get-ChildItem $Root -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
        Where-Object { $pins -notcontains "script.$($_.Name)" } | ForEach-Object { $_.Name }
    if ($unpinned) { Add-Result 'WARN' '未钉脚本' (($unpinned -join ', ') + "（共 $($unpinned.Count) 个）") }
    else { Add-Result 'OK' '未钉脚本' '全部已钉' }
}
# 12. 流水时间戳：完整日期 + 顺序非递减
# 为什么：只写 MM-DD 时归档脚本靠猜年份；顺序不看的话，一条插进中间、或时间被改早，
# 引脚（只有 count 和哈希）根本不会响。所以这里查「格式」和「秩序」两件事。
$seqFiles = @(
    @{ Name = '档案时间戳'; Path = (Join-Path $nb '2-档案.md'); Pat = '(?m)^- 时间：(\d{4}-\d{2}-\d{2} \d{2}:\d{2})' },
    @{ Name = '工作层时间戳'; Path = (Join-Path $nb '1-工作.md'); Pat = '(?m)^- \[(\d{4}-\d{2}-\d{2} \d{2}:\d{2})\]' }
)
foreach ($sf in $seqFiles) {
    if (-not (Test-Path $sf.Path)) { Add-Result 'WARN' $sf.Name '文件不存在'; continue }
    $txt = [IO.File]::ReadAllText($sf.Path, [Text.Encoding]::UTF8)
    $ms = [regex]::Matches($txt, $sf.Pat)
    if ($ms.Count -eq 0) { Add-Result 'WARN' $sf.Name '一条都没匹配到 —— 不是"格式全对"，是文件或格式已变'; continue }
    $bad = 0; $back = $null; $prev = $null; $prevRaw = ''; $dup = 0
    foreach ($m in $ms) {
        $raw = $m.Groups[1].Value
        $d = $null
        try { $d = [datetime]::ParseExact($raw, 'yyyy-MM-dd HH:mm', $null) } catch { $bad++ }
        if ($d) {
            if ($prev -and $d -lt $prev -and -not $back) { $back = "$prevRaw → $raw" }
            if ($prev -and $d -eq $prev) { $dup++ }; $prev = $d; $prevRaw = $raw
        }
    }
    $problems = @()
    if ($bad -gt 0) { $problems += "$bad 条日期非法" }
    if ($back) { $problems += "时间倒退（$back）" }
    if ($problems.Count -gt 0) { Add-Result 'WARN' $sf.Name ("{0} 条；{1}" -f $ms.Count, ($problems -join '；')) }
    else { $d2 = "{0} 条，格式完整、顺序递增" -f $ms.Count; if ($dup -gt 0) { $d2 += "（{0} 处同分钟，合法，仅提示）" -f $dup }; Add-Result 'OK' $sf.Name $d2 }
}
# 12b. 反向检查：凡看起来是流水行，就必须是完整格式
# 为什么：只查「匹配到的那几条」会静默漏掉旧格式写入 —— 插件写 MM-DD 时，
# 序列检查和 times 哈希都看不见它，等于这条流水在机制里不存在。
$shapeChecks = @(
    @{ Name = '工作层格式'; Path = (Join-Path $nb '1-工作.md'); Pat = '(?m)^- \[(?!\d{4}-\d{2}-\d{2} \d{2}:\d{2}\]).*' },
    @{ Name = '档案格式'; Path = (Join-Path $nb '2-档案.md'); Pat = '(?m)^- 时间：(?!\d{4}-\d{2}-\d{2} \d{2}:\d{2}).*' }
)
foreach ($sc in $shapeChecks) {
    if (-not (Test-Path $sc.Path)) { continue }
    $st = [IO.File]::ReadAllText($sc.Path, [Text.Encoding]::UTF8)
    $badLines = ([regex]::Matches($st, $sc.Pat)).Count
    if ($badLines -gt 0) { Add-Result 'WARN' $sc.Name ("{0} 行是旧格式或畸形" -f $badLines) }
    else { Add-Result 'OK' $sc.Name '没有畸形行' }
}
# 12c. 档案条目年龄：超 60 天的列出来 —— 过时的记忆比没有更糟，agent 会自信地出错
$archP = Join-Path $nb '2-档案.md'
if (Test-Path $archP) {
    $atxt = [IO.File]::ReadAllText($archP, [Text.Encoding]::UTF8)
    $nowD = Get-Date
    $old = @()
    foreach ($m in [regex]::Matches($atxt, '(?m)^### (.+)\r?\n- 时间：(\d{4}-\d{2}-\d{2})')) {
        try {
            $dd = [datetime]::ParseExact($m.Groups[2].Value, 'yyyy-MM-dd', $null)
            if (($nowD - $dd).TotalDays -gt 60) { $old += $m.Groups[1].Value }
        } catch {}
    }
    if ($old.Count -gt 0) { Add-Result 'WARN' '档案复核' ("{0} 条超 60 天，如：{1}" -f $old.Count, $old[0].Substring(0, [Math]::Min(18, $old[0].Length))) }
    else { Add-Result 'OK' '档案复核' '没有超 60 天的条目' }
}
# 12d. 档案来源标签：每条根因必须标 [观察] / [推断]
$tagP = Join-Path $nb '2-档案.md'
if (Test-Path $tagP) {
    $ttxt = [IO.File]::ReadAllText($tagP, [Text.Encoding]::UTF8)
    $all = ([regex]::Matches($ttxt, '(?m)^- 根因：')).Count
    $tagged = ([regex]::Matches($ttxt, '(?m)^- 根因：\[(观察|推断|待核)\]')).Count
    if ($all -eq 0) { Add-Result 'WARN' '档案来源标签' '一条根因都没找到，检查格式' }
    elseif ($tagged -lt $all) { Add-Result 'WARN' '档案来源标签' ("{0}/{1} 条已标，缺 {2}" -f $tagged, $all, ($all - $tagged)) }
    else { Add-Result 'OK' '档案来源标签' ("{0} 条全标（观察 {1} / 推断 {2}）" -f $all, ([regex]::Matches($ttxt,'(?m)^- 根因：\[观察\]')).Count, ([regex]::Matches($ttxt,'(?m)^- 根因：\[推断\]')).Count) }
}
# 13. 本机错题本：存在，且 wake 留痕里提到它（证明真被读，不是摆设）
$localDoc = Join-Path $nb '4-本机.md'
if (-not (Test-Path $localDoc)) { Add-Result 'FAIL' '本机错题本' '4-本机.md 不存在 —— 本机陷阱无处可查' }
else {
    $mkRaw = if (Test-Path $mark) { Get-Content $mark -Raw -Encoding UTF8 } else { '' }
    if ($mkRaw -notmatch '4-本机\.md') { Add-Result 'WARN' '本机错题本' '文件在，但 wake 留痕里没有它（可能没被读）' }
    else { Add-Result 'OK' '本机错题本' ("{0} B，wake 已记录" -f (Get-Item $localDoc).Length) }
}
# 14. .ps1 必须带 UTF-8 BOM（PS 5.1 把无 BOM 的 UTF-8 当 GBK，中文乱码 + 语法报错）
$ps1s = Get-ChildItem $root -Filter '*.ps1' -File -ErrorAction SilentlyContinue
$noBom = @()
foreach ($f in $ps1s) {
    $bb = [IO.File]::ReadAllBytes($f.FullName)
    $hasB = ($bb.Length -ge 3 -and $bb[0] -eq 0xEF -and $bb[1] -eq 0xBB -and $bb[2] -eq 0xBF)
    if (-not $hasB) { $noBom += $f.Name }
}
if ($noBom.Count -gt 0) { Add-Result 'WARN' 'PS1 BOM' ("{0} 个缺 BOM：{1}（跑 fix-bom.ps1）" -f $noBom.Count, (($noBom | Select-Object -First 3) -join ', ')) }
else { Add-Result 'OK' 'PS1 BOM' ("{0} 个全带 BOM" -f $ps1s.Count) }
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
