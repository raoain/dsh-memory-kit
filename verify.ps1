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

$script:ImmuneJsonCache = $null
# 2026-11-09 用户：「他跑一次，后面给结果，自己分别去取就行了」——免疫整轮只跑一次，各检查项查缓存
function Get-ImmuneJson {
    if ($null -eq $script:ImmuneJsonCache) {
        $script:ImmuneJsonCache = (& node (Join-Path $Root 'core\immunity.mjs') --json 2>$null) -join ''
    }
    return $script:ImmuneJsonCache
}
$ErrorActionPreference = 'Continue'
$sw = [Diagnostics.Stopwatch]::StartNew()
. (Join-Path $PSScriptRoot '_root.ps1')
$nb = Join-Path $root 'notebook'

# 命令覆盖（2026-11-07）：器官自治优先——照常跑；只在下一次运行前扫一眼自己的邮箱。
# 命令只限三样：1 跳过 / 2 强制重跑 / 3 降级。没有命令时行为与以前完全一致。
$cmdRun = 0
$cmdArg = 0
$cmdBox = Join-Path $root 'track\in\1.jsonl'
if (Test-Path $cmdBox) {
    $cmdLast = Get-Content $cmdBox -Encoding UTF8 | Where-Object { $_.Trim() } | Select-Object -Last 1
    if ($cmdLast) {
        try {
            $o = $cmdLast | ConvertFrom-Json
            $cmdRun = [int]$o.cmd
            if ($o.arg) { $cmdArg = [int]$o.arg }
        } catch {}
        Move-Item $cmdBox ($cmdBox + '.done') -Force
    }
}
if ($cmdRun -eq 1) {
    Write-Host 'SKIP 收到跳过命令，本次不检查（命令覆盖自治）'
    Write-Output ('SIG ' + (@{ state = 3; counts = @(0,0,0,0) } | ConvertTo-Json -Compress))
    exit 0
}
# 2 强制重跑：verify 每次都是真跑，无需处理；3 降级：verify 只报不改，无降级语义。

$rows = @()
$script:checkSeq = 0
function Add-Result($level, $item, $detail) {
    # 每项一个稳定编号（按调用顺序发号），让总线能引用「第几项挂了」
    $script:checkSeq++
    $script:rows += [pscustomobject]@{ Id = $script:checkSeq; Level = $level; Item = $item; Detail = $detail }
}

# 1. 核心层：≤2 KB、五节以上
$core = Join-Path $nb '0-核心.md'
if (-not (Test-Path $core)) { Add-Result 'FAIL' '核心层' '文件不存在' }
else {
    # 1a. 核心层大小/节数（2026-11-09 移交免疫：上限与节数在 spec.pages.core，判定是 core-page）
    $pageRow = $null
    try {
        $pageJson = (Get-ImmuneJson)
        $pageRow = @(($pageJson | ConvertFrom-Json).rows | Where-Object { $_.id -eq 'core-page' })[0]
    } catch { $pageRow = $null }
    if (-not $pageRow) {
        Add-Result 'WARN' '核心层大小' '免疫没给出 core-page（检查器没跑起来？）'
    } elseif (-not $pageRow.ok) {
        Add-Result 'FAIL' '核心层大小' $pageRow.detail
    } else {
        Add-Result 'OK' '核心层大小' $pageRow.detail
    }
}

# 2. 墓碑（2026-11-09 移交免疫：规则在 spec.pages.tombstone，判定是 tombstone）
$tombRow = $null
try {
    $tombJson = (Get-ImmuneJson)
    $tombRow = @(($tombJson | ConvertFrom-Json).rows | Where-Object { $_.id -eq 'tombstone' })[0]
} catch { $tombRow = $null }
if (-not $tombRow) {
    Add-Result 'WARN' '墓碑' '免疫没给出 tombstone（检查器没跑起来？）'
} elseif (-not $tombRow.ok) {
    Add-Result 'WARN' '墓碑' $tombRow.detail
} else {
    Add-Result 'OK' '墓碑' $tombRow.detail
}

# 3. 开工留痕（2026-11-09 移交免疫：规则在 spec.reminders.wake_mark，判定是 wake-fresh）
$wakeRow = $null
try {
    $wakeJson = (Get-ImmuneJson)
    $wakeRow = @(($wakeJson | ConvertFrom-Json).rows | Where-Object { $_.id -eq 'wake-fresh' })[0]
} catch { $wakeRow = $null }
if (-not $wakeRow) {
    Add-Result 'WARN' 'wake 留痕' '免疫没给出 wake-fresh（检查器没跑起来？）'
} elseif (-not $wakeRow.ok) {
    Add-Result 'WARN' 'wake 留痕' $wakeRow.detail
} else {
    Add-Result 'OK' 'wake 留痕' $wakeRow.detail
}

# 4. 备份：双盘 + 最新时间
foreach ($d in 'F:\Tools\coo-backup', 'D:\coo-backup') {
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
    if (-not $hasBom) { Add-Result 'WARN' 'AGENTS.md' '缺 BOM → PS 5.1 按 ANSI 读，中文会乱码；跑 fix-bom.ps1' }
    else { Add-Result 'OK' 'AGENTS.md' ("{0:N1} KB" -f ($b.Length / 1KB)) }
}

# 7. 最近快照
$snapDir = Join-Path $root 'track\own'
# 7. 最近快照（2026-11-09 移交免疫：规则在 spec.reminders.snapshot，判定是 snapshot-fresh）
$snapRow = $null
try {
    $snapJson = (Get-ImmuneJson)
    $snapRow = @(($snapJson | ConvertFrom-Json).rows | Where-Object { $_.id -eq 'snapshot-fresh' })[0]
} catch { $snapRow = $null }
if (-not $snapRow) {
    Add-Result 'WARN' '最近快照' '免疫没给出 snapshot-fresh（检查器没跑起来？）'
} elseif (-not $snapRow.ok) {
    Add-Result 'WARN' '最近快照' $snapRow.detail
} else {
    Add-Result 'OK' '最近快照' $snapRow.detail
}

# 8. 垃圾场规模（2026-11-09 移交免疫：规则在 spec.reminders.trash，判定是 trash-size）
$trashRow = $null
try {
    $trashJson = (Get-ImmuneJson)
    $trashRow = @(($trashJson | ConvertFrom-Json).rows | Where-Object { $_.id -eq 'trash-size' })[0]
} catch { $trashRow = $null }
if (-not $trashRow) {
    Add-Result 'WARN' '垃圾场' '免疫没给出 trash-size（检查器没跑起来？）'
} elseif (-not $trashRow.ok) {
    Add-Result 'WARN' '垃圾场' $trashRow.detail
} else {
    Add-Result 'OK' '垃圾场' $trashRow.detail
}

# 9. 可选：联网核查最近发布
if ($Deep) {
    $bili = 'F:\Tools\uv\bin\bili.exe'
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


# 10. 脚本静态检查（2026-11-09 移交免疫：规则在 spec.tools.lint，判定是 ps1-lint）
$lintRow = $null
try {
    $lintJson = (Get-ImmuneJson)
    $lintRow = @(($lintJson | ConvertFrom-Json).rows | Where-Object { $_.id -eq 'ps1-lint' })[0]
} catch { $lintRow = $null }
if (-not $lintRow) {
    Add-Result 'WARN' '脚本 lint' '免疫没给出 ps1-lint（检查器没跑起来？）'
} elseif (-not $lintRow.ok) {
    Add-Result 'WARN' '脚本 lint' $lintRow.detail
} else {
    Add-Result 'OK' '脚本 lint' $lintRow.detail
}

# 11. 未钉脚本（2026-11-09 移交免疫：判定在 core/immunity.mjs 的 pins-cover-scripts）
$pinRow = $null
try {
    $pinJson = (Get-ImmuneJson)
    $pinRow = @(($pinJson | ConvertFrom-Json).rows | Where-Object { $_.id -eq 'pins-cover-scripts' })[0]
} catch { $pinRow = $null }
if (-not $pinRow) {
    Add-Result 'WARN' '未钉脚本' '免疫没给出 pins-cover-scripts（检查器没跑起来？）'
} elseif (-not $pinRow.ok) {
    Add-Result 'WARN' '未钉脚本' $pinRow.detail
} else {
    Add-Result 'OK' '未钉脚本' $pinRow.detail
}
# 12. 流水时间戳（2026-11-09 移交免疫：格式/顺序在 spec.pages.timeline，判定是 timeline-order）
$timeRow = $null
try {
    $timeJson = (Get-ImmuneJson)
    $timeRow = @(($timeJson | ConvertFrom-Json).rows | Where-Object { $_.id -eq 'timeline-order' })[0]
} catch { $timeRow = $null }
if (-not $timeRow) {
    Add-Result 'WARN' '流水时间戳' '免疫没给出 timeline-order（检查器没跑起来？）'
} elseif (-not $timeRow.ok) {
    Add-Result 'WARN' '流水时间戳' $timeRow.detail
} else {
    Add-Result 'OK' '流水时间戳' $timeRow.detail
}
# 12b. 反向检查：凡看起来是流水行，就必须是完整格式
# 为什么：只查「匹配到的那几条」会静默漏掉旧格式写入 —— 插件写 MM-DD 时，
# 序列检查和 times 哈希都看不见它，等于这条流水在机制里不存在。
$shapeChecks = @(
    @{ Name = '工作层行内合并'; Path = (Join-Path $nb '1-工作.md'); Pat = '(?m)^- \[[^\r\n]*- \[\d{2}-\d{2} \d{2}:\d{2}\]' },    @{ Name = '工作层格式'; Path = (Join-Path $nb '1-工作.md'); Pat = '(?m)^- \[(?!\d{4}-\d{2}-\d{2} \d{2}:\d{2}\]).*' },
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
    # wake 留痕路径在本项自己的作用域里重算一次（原 $mark 随第 3 项移交免疫被删掉了）
    $mark = Join-Path $root 'track\wake-last.txt'
    $mkRaw = if (Test-Path $mark) { Get-Content $mark -Raw -Encoding UTF8 } else { '' }
    if ($mkRaw -notmatch '4-本机\.md') { Add-Result 'WARN' '本机错题本' '文件在，但 wake 留痕里没有它（可能没被读）' }
    else { Add-Result 'OK' '本机错题本' ("{0} B，wake 已记录" -f (Get-Item $localDoc).Length) }
}
# 14. .ps1 必须带 UTF-8 BOM（2026-11-09 移交免疫：标准与判定都在 core/immunity.mjs 的 ps1-bom）
$bomRow = $null
try {
    $bomJson = (Get-ImmuneJson)
    $bomRow = @(($bomJson | ConvertFrom-Json).rows | Where-Object { $_.id -eq 'ps1-bom' })[0]
} catch { $bomRow = $null }
if (-not $bomRow) {
    Add-Result 'WARN' 'PS1 BOM' '免疫没给出 ps1-bom（检查器没跑起来？）'
} elseif (-not $bomRow.ok) {
    Add-Result 'WARN' 'PS1 BOM' $bomRow.detail
} else {
    Add-Result 'OK' 'PS1 BOM' $bomRow.detail
}

# 13. 归因检查（说了「用户说」却引不出原话）
$attrib = Join-Path $Root 'attrib.ps1'
if (Test-Path $attrib) {
    $ao = & powershell -NoProfile -ExecutionPolicy Bypass -File $attrib -Quiet 2>&1 | Out-String
    $m = [regex]::Match($ao, '(\d+) 处归因无引文')
    if ($m.Success -and [int]$m.Groups[1].Value -gt 0) { Add-Result 'WARN' '归因检查' ("{0} 处无引文（跑 attrib.ps1 看明细）" -f $m.Groups[1].Value) }
    else { Add-Result 'OK' '归因检查' '无无引文归因' }
}

# 24. intake 自检：验真工具本身会不会假 PASS
$intake = Join-Path $Root 'intake.ps1'
if (Test-Path $intake) {
    # 故意给一条已知不存在的断言；期望 FAIL（exit 1）。若它说 PASS，就是工具坏了。
    $probe = "zzz-不存在-自检占位-zzz"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $intake -Kind file -Claim '自检负样本' -Expect $probe -Loc 'notebook\0-核心.md' *> $null
    if ($LASTEXITCODE -eq 0) {
        Add-Result 'WARN' 'intake 自检' '负样本被判 PASS（验真工具在自我印证）'
    } else {
        Add-Result 'OK' 'intake 自检' '负样本被正确拒绝'
    }
}

# 25. 今日发布配额（按 published_at 字段算，不按行内日期模糊匹配）
$ledger = Join-Path $Root 'track\发布台账.jsonl'
if (Test-Path $ledger) {
    $today = (Get-Date).ToString('yyyy-MM-dd')
    $ledgerRows = @()
    foreach ($ln in (Get-Content $ledger -Encoding UTF8 | Where-Object { $_.Trim() })) {
        try { $ledgerRows += ($ln | ConvertFrom-Json) } catch { }
    }
    # 草稿（没有 link_id）不算发布，不进配额；只有真发出去的才算
    # 草稿/废弃/未发 不算发布（2026-11-01 修：小黑盒-02 草稿行没有 published_at，导致配额永远算不出）
    $published = @($ledgerRows | Where-Object { $_.id -and ($_.no -notmatch '草稿|废弃|未发|draft') })
    $nulls = @($published | Where-Object { -not $_.published_at }).Count
    $todayRows = @($published | Where-Object { $_.published_at -and $_.published_at.ToString().StartsWith($today) })
    $byPlat = @{}
    foreach ($r in $todayRows) { $k = [string]$r.platform; $byPlat[$k] = 1 + [int]$byPlat[$k] }
    $bili = [int]$byPlat['bilibili']
    $heybox = [int]$byPlat['heybox']
    $desc = "B站 $bili 条 / 小黑盒 $heybox 条"
    # 历史 1 条（小黑盒-02）发布时间当时只到「07:2x」，不编，允许 1 条未知；超过 1 条才算判据失效
    if ($nulls -gt 1) {
        Add-Result 'WARN' '今日配额' ("$desc → 有 $nulls 条 published_at 缺失，配额算不出；发前手查台账")
    } elseif ($bili -gt 2) {
        Add-Result 'WARN' '今日配额' ("$desc → B 站已超 2 条上限，今天不许再发")
    } else {
        Add-Result 'OK' '今日配额' $desc
    }
}

# 26. 检查器自检：verify 自己该有多少项
# 为什么：2026-10-29 $rows 被覆盖，verify 只输出 6 项却「没报错」——因为「应该有多少项」没有预期。
# 判据 P15：「没报错」只说明处在②，不说明对；所以这里给检查器本身写一个预期。

# 27. 完成声明有框：工作层里说「完成/修好/发完」的条目，必须带「证:」尾缀
# 判据 P16：说完成必须带已验证据；DNA 式做法 = 前缀「验:」+ 尾缀「证:」。
$work = Join-Path $Root 'notebook\1-工作.md'
if (Test-Path $work) {
    $claimWords = '完成|修好|已发|发完|已改|改好了|跑通了|全绿'
    $bad = @()
    foreach ($ln in (Get-Content $work -Encoding UTF8)) {
        if ($ln -notmatch '^- \[') { continue }
        if ($ln -notmatch $claimWords) { continue }
        if ($ln -notmatch '证[:：]') { $bad += ("无证:" + $ln.Substring(0,[Math]::Min(40,$ln.Length))); continue }
        # 判「不可伪造的痕迹」：证: 后面必须是一个能打开的东西（路径存在 / 命令名 / verify 回显行）
        $evid = ($ln -split '证[:：]',2)[1]
        if (-not $evid) { $bad += ("证为空:" + $ln.Substring(0,[Math]::Min(30,$ln.Length))); continue }
        $evidTxt = $evid.Trim()
        $okEvid = $false
        # ① 像路径：存在
        foreach ($m in [regex]::Matches($evidTxt, '([A-Za-z0-9_\-\\/\.]+\.(md|ps1|jsonl|json|mjs|txt))')) {
            $cand = $m.Groups[1].Value
            if ((Test-Path (Join-Path $Root $cand)) -or (Test-Path $cand)) { $okEvid = $true }
        }
        # ② 像回显：含「项：」或「OK」或数字+单位
        if (-not $okEvid -and $evidTxt -match '项：|\d+\s*项|OK |ms|字节|条|B\b') { $okEvid = $true }
        # ③ 像「第 N 行 / 第 N-M 行」
        if (-not $okEvid -and $evidTxt -match '第\s*\d+(\s*-\s*\d+)?\s*行') { $okEvid = $true }
        # ④ 像命令名
        if (-not $okEvid -and $evidTxt -match '[a-z\-]+\.(ps1|mjs)') { $okEvid = $true }
        if (-not $okEvid) { $bad += ("证不可核:" + $ln.Substring(0,[Math]::Min(30,$ln.Length))) }
    }
    $today = (Get-Date).ToString('yyyy-MM-dd')
    $badToday = @($bad | Where-Object { $_ -match $today })
    if ($badToday.Count -gt 0) {
        Add-Result 'WARN' '完成声明有框' ("今天新增 $($badToday.Count) 条证不合格；历史欠账共 $($bad.Count) 条，2026-11-15 清零")
    } elseif ($bad.Count -gt 0) {
        Add-Result 'OK' '完成声明有框' ("今日新增全部合格；历史欠账 $($bad.Count) 条，11-15 清零")
    } else {
        Add-Result 'OK' '完成声明有框' '说完成的条目都带证'
    }

}
# 28. 预登记：到期待判的预测必须有人判，否则「检验」成了空话
$predFile = Join-Path $Root 'track\预测.jsonl'
if (Test-Path $predFile) {
    $now = Get-Date
    $unjudged = @()
    $totalPred = 0
    foreach ($ln in (Get-Content $predFile -Encoding UTF8)) {
        if (-not $ln.Trim()) { continue }
        try { $o = $ln | ConvertFrom-Json } catch { continue }
        $totalPred++
        if ($o.result -eq '未判' -and $o.by -and ([datetime]::Parse($o.by) -lt $now)) { $unjudged += $o }
    }
    if ($unjudged.Count -gt 0) {
        Add-Result 'WARN' '预登记' ("$($unjudged.Count)/$totalPred 条预测已逾期未判（跑 predict.ps1 -Verdict）")
    } else {
        Add-Result 'OK' '预登记' ("$totalPred 条预测，无逾期未判")
    }
}

# 29. 待消化积压：超 7 天没动的素材，要么反刍要么删
$stage = Join-Path $Root 'track\待消化.md'
if (Test-Path $stage) {
    $old = @()
    $total = 0
    foreach ($ln in (Get-Content $stage -Encoding UTF8)) {
        if ($ln -notmatch '^- \[(\d{4}-\d{2}-\d{2})\]') { continue }
        $total++
        $d = [datetime]::Parse($Matches[1])
        if (((Get-Date) - $d).TotalDays -gt 7) { $old += $Matches[1] }
    }
    if ($old.Count -gt 0) {
        Add-Result 'WARN' '待消化' ("$total 条里 $($old.Count) 条超过 7 天没动 → 反刍或删")
    } else {
        Add-Result 'OK' '待消化' ("$total 条，无积压")
    }
}

# 30. 接缝表完整：五链两两共十接缝，漏了就是漏了一条道
$seamFile = Join-Path $Root 'track\接缝.md'
if (Test-Path $seamFile) {
    $n = @(Select-String -Path $seamFile -Pattern '^\| \d+ \|' -Encoding UTF8).Count
    if ($n -lt 10) { Add-Result 'WARN' '接缝表' ("只有 $n 条接缝（五链两两应有 10 条）→ 有一条道没人管") }
    else { Add-Result 'OK' '接缝表' "$n 条接缝" }
}

# 31. 改动留痕比：今天改了 N 个文件，却只记了 M 条 —— 说明 X→M 接缝断了
$workF = Join-Path $Root 'notebook\1-工作.md'
if (Test-Path $workF) {
    $today2 = (Get-Date).ToString('yyyy-MM-dd')
    $mCount = @(Get-Content $workF -Encoding UTF8 | Where-Object { $_ -match ("^- \[" + $today2) }).Count
    $fCount = @(Get-ChildItem $Root -Recurse -Include *.ps1,*.md,*.mjs,*.jsonl -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\trash\\' -and $_.LastWriteTime.Date -eq (Get-Date).Date }).Count
    # 正确指标：自「上一条工作层记录」之后还改过几个文件没记（一条记录可覆盖几十个文件）
    $lastT = $null
    foreach ($ln in (Get-Content $workF -Encoding UTF8)) {
        $mm = [regex]::Match($ln, '^- \[(\d{4}-\d{2}-\d{2} \d{2}:\d{2})\]')
        if ($mm.Success) { $lastT = [datetime]::Parse($mm.Groups[1].Value) }
    }
    if (-not $lastT) { $lastT = (Get-Date).AddHours(-2) }
    $unlogged = @(Get-ChildItem $Root -Recurse -Include *.ps1,*.md,*.mjs,*.json,*.jsonl -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\trash\\|\\build\\|\\archive\\|\\audio|\\out\\|\\align\\|\\mind\\' -and $_.Name -notmatch '^(warn-streak|state|baseline|预测数据|wake-last|1-工作|self-baseline|\.reflex-|\.dispatch-|bus\.jsonl|align\.jsonl|memories\.jsonl|\.probe-last|免疫表|脚本清单|center|events\.jsonl|watchdog\.jsonl|\.source-language|\.bus\.before-discharge|\.consolidate-cursor|drift-pending|drift-streak|drift-raw|\.arbiter|dispatch\.jsonl|brain\.jsonl|nucleus)' -and $_.LastWriteTime -gt $lastT }).Count
    if ($unlogged -gt 3) {
        Add-Result 'WARN' '改动留痕比' ("上次记录（{0}）之后又改了 {1} 个文件没记 → 跑 log.ps1" -f $lastT.ToString('HH:mm'), $unlogged)
    } else {
        Add-Result 'OK' '改动留痕比' ("未留痕改动 {0} 个（上次记录 {1}）" -f $unlogged, $lastT.ToString('HH:mm'))
    }
}

# 32. 术语黑名单：给「人读」的稿子不许出现内部术语
$heybox = Join-Path $Root 'heybox'
if (Test-Path $heybox) {
    $bad = @('判据','接缝','哑炮','探针','预登记','同一性','连续性','反智','效度','留痕','引脚')
    $hits = @()
    foreach ($f2 in (Get-ChildItem $heybox -Filter '*.md' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'post*' })) {
        $txt2 = [IO.File]::ReadAllText($f2.FullName, [Text.Encoding]::UTF8)
        if ($txt2 -notmatch '给人读') { continue }
        foreach ($w in $bad) {
            if ($txt2.Contains($w)) { $hits += ("{0}:{1}" -f $f2.Name, $w) }
        }
    }
    # 论证稿（论文-*.md）：只查「内部工程词」，放行用户的原词（同一性 / 连续性）
    $innerTerms = @('判据','接缝','哑炮','探针','预登记','留痕','引脚','反智','效度')
    foreach ($f3 in (Get-ChildItem $heybox -Filter '论文-*.md' -File -ErrorAction SilentlyContinue)) {
        $txt3 = [IO.File]::ReadAllText($f3.FullName, [Text.Encoding]::UTF8)
        foreach ($w in $innerTerms) {
            if ($txt3.Contains($w)) { $hits += ("{0}:{1}(论证稿)" -f $f3.Name, $w) }
        }
    }
    if ($hits.Count -gt 0) {
        Add-Result 'WARN' '术语黑名单' ("给人读的稿里有 $($hits.Count) 处术语：$($hits -join ', ')")
    } else {
        Add-Result 'OK' '术语黑名单' '给人读的稿无术语（入口稿全查，论证稿只查内部工程词）'
    }
}

# 33. 载荷表：量过没有、最后一条是啥时候的（否则它就是个孤儿文件）
$loadF = Join-Path $Root 'track\载荷.jsonl'
if (Test-Path $loadF) {
    $recs = @()
    foreach ($ln in (Get-Content $loadF -Encoding UTF8)) {
        if (-not $ln.Trim()) { continue }
        try { $recs += ($ln | ConvertFrom-Json) } catch { }
    }
    if ($recs.Count -eq 0) {
        Add-Result 'WARN' '载荷表' '文件在但一条记录都解析不出来 → 格式坏了'
    } else {
        $lastRec = $recs[-1]
        $lastDate = [datetime]::Parse($lastRec.date)
        $daysAgo = ((Get-Date).Date - $lastDate.Date).Days
        $desc = "最近一次 {0}（工具 {1} 次 / 改文件 {2} 个 / token {3}）" -f $lastRec.date, $lastRec.toolCalls, $lastRec.filesTouched, $lastRec.tokens
        if ($daysAgo -gt 3) {
            Add-Result 'WARN' '载荷表' ("$($recs.Count) 条记录，但最近一次是 $daysAgo 天前 → 跑 load.ps1")
        } else {
            Add-Result 'OK' '载荷表' ("$($recs.Count) 条；$desc")
        }
    }
}

# 34. 读回记录（C12 的 ⑤）：判断必须能指到依据，且依据现在打得开
$recallF = Join-Path $Root 'track\读回.jsonl'
if (-not (Test-Path $recallF)) {
    Add-Result 'WARN' '读回记录' '一条都没有 → ⑤ 读回这环是空的（说不出判断依据）'
} else {
    $rr = @()
    foreach ($ln2 in (Get-Content $recallF -Encoding UTF8)) {
        if (-not $ln2.Trim()) { continue }
        try { $rr += ($ln2 | ConvertFrom-Json) } catch { }
    }
    if ($rr.Count -eq 0) {
        Add-Result 'WARN' '读回记录' '文件在但解析不出来'
    } else {
        $broken = @()
        foreach ($r2 in ($rr | Select-Object -Last 3)) {
            $sp = ($r2.src -split ':')
            if ($sp.Count -lt 2) { $broken += $r2.src; continue }
            $fp = Join-Path $Root $sp[0]
            if (-not (Test-Path $fp)) { $broken += $r2.src; continue }
            $ln = 0
            if (-not [int]::TryParse($sp[1], [ref]$ln)) { $broken += $r2.src; continue }
            $cnt = (Get-Content $fp -Encoding UTF8 | Measure-Object).Count
            if ($ln -lt 1 -or $ln -gt $cnt) { $broken += $r2.src }
        }
        $lastT = [datetime]::Parse($rr[-1].time)
        $ageH = ((Get-Date) - $lastT).TotalHours
        if ($broken.Count -gt 0) {
            Add-Result 'WARN' '读回记录' ("$($rr.Count) 条，但有 $($broken.Count) 条依据已打不开：$($broken -join ', ')")
        } elseif ($ageH -gt 72) {
            Add-Result 'WARN' '读回记录' ("$($rr.Count) 条，最近一次 {0:N0} 小时前 → 太久没记判断依据" -f $ageH)
        } else {
            Add-Result 'OK' '读回记录' ("$($rr.Count) 条，最近的依据都能打开（最近一条 {0:N0} 小时前）" -f $ageH)
        }
    }
}

# 35. 发布依据链（把 ② 和 ⑤ 钉在一起）：每条发布，发之前半小时内必须有「读回」记录
$recallP = Join-Path $Root 'track\读回.jsonl'
$ledgerP = Join-Path $Root 'track\发布台账.jsonl'
if ((Test-Path $recallP) -and (Test-Path $ledgerP)) {
    $recs2 = @()
    foreach ($ln3 in (Get-Content $recallP -Encoding UTF8)) {
        if (-not $ln3.Trim()) { continue }
        try { $recs2 += ($ln3 | ConvertFrom-Json) } catch { }
    }
    $pubs = @()
    foreach ($ln4 in (Get-Content $ledgerP -Encoding UTF8)) {
        if (-not $ln4.Trim()) { continue }
        try {
            $o2 = $ln4 | ConvertFrom-Json
            if ($o2.id -and $o2.published_at) { $pubs += $o2 }
        } catch { }
    }
    $pubs = @($pubs | Sort-Object { [datetime]::Parse($_.published_at) })
    $bare = @()
    foreach ($pb in ($pubs | Select-Object -Last 3)) {
        $pt = [datetime]::Parse($pb.published_at)
        $hit = @($recs2 | Where-Object {
            $rt = [datetime]::Parse($_.time)
            $rt -le $pt -and ($pt - $rt).TotalMinutes -le 30
        })
        if ($hit.Count -eq 0) { $bare += $pb.no }
    }
    if ($bare.Count -gt 0) {
        Add-Result 'WARN' '发布依据链' ("最近 3 条发布里 $($bare.Count) 条发前没有「读回」记录 → 那几条的依据没留痕（$($bare -join ', ')）")
    } else {
        Add-Result 'OK' '发布依据链' '最近 3 条发布都有发前依据记录'
    }
}

# 36. 取真通道（C13）：能不能读到外界。读不到要明说，不许用猜补
$chans = @()
# 通道一：时钟
try {
    $nowProbe = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $chans += "时钟 OK($nowProbe)"
} catch { $chans += '时钟 断' }
# 通道二：文件系统（核心层可读）
try {
    $cp = Join-Path $Root 'notebook\0-核心.md'
    $nul = @(Get-Content $cp -Encoding UTF8).Count
    if ($nul -gt 0) { $chans += "文件 OK($nul 行)" } else { $chans += '文件 空' }
} catch { $chans += '文件 断' }
# 通道三：平台接口（只在 -Deep 时试，省时间与限额）
if ($Deep) {
    $biliPath = 'F:\Tools\uv\bin\bili.exe'
    if (Test-Path $biliPath) {
        try {
            $raw = & $biliPath me show 2>&1 | Out-String
            if ($raw -match '"ok":\s*true') { $chans += 'B站接口 OK' } else { $chans += 'B站接口 断' }
        } catch { $chans += 'B站接口 断' }
    } else { $chans += 'B站接口 无命令' }
}
$broken = @($chans | Where-Object { $_ -match '断|空' })
if ($broken.Count -gt 0) {
    Add-Result 'FAIL' '取真通道' ("有通道读不到：$($chans -join ' / ') → 此刻不许用猜测补")
} else {
    Add-Result 'OK' '取真通道' ($chans -join ' / ')
}

# 37. 环位标注：每一页都要写清「咬在环的哪一拍 + 读完能干什么」
$nbDir = Join-Path $Root 'notebook'
if (Test-Path $nbDir) {
    $noTag = @()
    foreach ($pg in (Get-ChildItem $nbDir -Filter '*.md' -File -ErrorAction SilentlyContinue)) {
        $head = @(Get-Content $pg.FullName -Encoding UTF8 -TotalCount 6) -join "`n"
        if ($head -notmatch '心脏|供能层|飞轮|中心齿轮|拍[①②③④⑤]') { $noTag += $pg.Name }
        elseif ($head -notmatch '接口：') { $noTag += ($pg.Name + '(缺接口)') }
    }
    if ($noTag.Count -gt 0) {
        Add-Result 'WARN' '环位标注' ("$($noTag.Count) 页没咬在环上：$($noTag -join ', ')")
    } else {
        Add-Result 'OK' '环位标注' '每页都写了环位与接口'
    }
}

# 38. 轴不装货：核心层不许出现「承重件」（他的偏好 / 本机 / 原话），那些属 9-用户 与 4-本机
$coreP = Join-Path $Root 'notebook\0-核心.md'
if (Test-Path $coreP) {
    $coreTxt = [IO.File]::ReadAllText($coreP, [Text.Encoding]::UTF8)
    # 2026-11-09：核心层改成目录页后，「指向某页」的行是接口不是承重件——含箭头或反引号文件名的行不计
    $bodyTxt = (($coreTxt -split "`r?`n") | Where-Object { $_ -notmatch '→' -and $_ -notmatch '`[^`]+\.md`' }) -join "`n"
    $heavy = @('船长是谁', '船长要的', '他讨厌', '这台机器', '原话')
    $found = @()
    foreach ($hw in $heavy) { if ($bodyTxt.Contains($hw)) { $found += $hw } }
    if ($found.Count -gt 0) {
        Add-Result 'WARN' '轴不装货' ("核心层里出现了承重件：$($found -join '、') → 挪到 9-用户 / 4-本机 / 8-原话")
    } else {
        Add-Result 'OK' '轴不装货' '核心层只有发动机与目录指针'
    }
}

# 39. 术语引用：6-话 里定义的每个说法，必须在别处被用过（否则就是 Dictionary DDD）
$wordsP = Join-Path $Root 'notebook\6-话.md'
if (Test-Path $wordsP) {
    $wt = Get-Content $wordsP -Encoding UTF8
    $terms = @()
    foreach ($ln in $wt) {
        $mm2 = [regex]::Match($ln, '^##\s+(.+?)(（|\(|$)')
        if ($mm2.Success) {
            $nm = $mm2.Groups[1].Value.Trim()
            if ($nm.Length -ge 2) { $terms += $nm }
        }
    }
    $others = @()
    foreach ($d in @((Join-Path $Root 'notebook'), (Join-Path $Root 'track'))) {
        if (-not (Test-Path $d)) { continue }
        foreach ($ff in (Get-ChildItem $d -Filter '*.md' -File -ErrorAction SilentlyContinue)) {
            if ($ff.Name -eq '6-话.md') { continue }
            $others += [IO.File]::ReadAllText($ff.FullName, [Text.Encoding]::UTF8)
        }
    }
    $allText = $others -join "`n"
    $unused = @()
    foreach ($tm in $terms) {
        if (-not $allText.Contains($tm)) { $unused += $tm }
    }
    if ($unused.Count -gt 0) {
        Add-Result 'WARN' '术语引用' ("$($unused.Count)/$($terms.Count) 个说法只在 6-话 里定义、别处没人用 → $($unused -join '、')")
    } else {
        Add-Result 'OK' '术语引用' ("$($terms.Count) 个说法都被别处引用过")
    }
}

# 40. 无主语引用：稿件里不许「据说/有研究表明/众所周知/科学证明」这类不指名的引用
$heyboxD = Join-Path $Root 'heybox'
if (Test-Path $heyboxD) {
    $vague = @('据说','有研究表明','研究表明','研究发现','众所周知','科学证明','科学家发现','数据显示')
    $hits2 = @()
    foreach ($f3 in (Get-ChildItem $heyboxD -Filter '*.md' -File -ErrorAction SilentlyContinue)) {
        $lines3 = Get-Content $f3.FullName -Encoding UTF8
        $ln3 = 0
        foreach ($txt3 in $lines3) {
            $ln3++
            foreach ($vg in $vague) {
                if ($txt3.Contains($vg)) { $hits2 += ("{0}:L{1}「{2}」" -f $f3.Name, $ln3, $vg) }
            }
        }
    }
    if ($hits2.Count -gt 0) {
        Add-Result 'WARN' '无主语引用' ("$($hits2.Count) 处不指名来源：$((($hits2 | Select-Object -First 3) -join '; ')) → 要么指出谁的研究，要么删")
    } else {
        Add-Result 'OK' '无主语引用' '稿件里没有不指名的引用'
    }
}

# 41. 自我集（2026-11-09 移交免疫：规则在 spec.liveness.self_set，判定是 self-set，含年龄与偏离）
$selfRow = $null
try {
    $selfJson = (Get-ImmuneJson)
    $selfRow = @(($selfJson | ConvertFrom-Json).rows | Where-Object { $_.id -eq 'self-set' })[0]
} catch { $selfRow = $null }
if (-not $selfRow) {
    Add-Result 'WARN' '自我集' '免疫没给出 self-set（检查器没跑起来？）'
} elseif (-not $selfRow.ok) {
    Add-Result 'WARN' '自我集' $selfRow.detail
} else {
    Add-Result 'OK' '自我集' $selfRow.detail
}


# 42. 必跑不问：这条规则曾被纠五次，必须留在核心层与 AGENTS 里（防被悄悄删掉）
$coreP2 = Join-Path $Root 'notebook\0-核心.md'
$agentsP = Join-Path $env:USERPROFILE '.dsh\AGENTS.md'
$hasCore = $false; $hasAgents = $false
if (Test-Path $coreP2) { $hasCore = ([IO.File]::ReadAllText($coreP2, [Text.Encoding]::UTF8)).Contains('必跑的不问') }
if (Test-Path $agentsP) { $hasAgents = ([IO.File]::ReadAllText($agentsP, [Text.Encoding]::UTF8)).Contains('必跑的不问') }
if (-not $hasCore -or -not $hasAgents) {
    Add-Result 'FAIL' '必跑不问' ("核心层:{0} / AGENTS:{1} → 这条被纠过五次，不许丢" -f $(if($hasCore){'有'}else{'缺'}), $(if($hasAgents){'有'}else{'缺'}))
} else {
    Add-Result 'OK' '必跑不问' '核心层与 AGENTS 都有这条'
}

# 43. 冻结（frozen）：不是 0、不是缺失，而是「文件还在但几天没动」
# 依据：Prometheus 把 healthy zero / missing / frozen 当三种状态分别告警；我们只有前两种。
$workP = Join-Path $nb '1-工作.md'
$runP  = Join-Path $Root 'track\运行记录.txt'
$frozen = @()
foreach ($pair in @(@('工作层',$workP,2), @('运行记录',$runP,2))) {
    $nm = $pair[0]; $pp = $pair[1]; $limitH = $pair[2]
    if (Test-Path $pp) {
        $h = ((Get-Date) - (Get-Item $pp).LastWriteTime).TotalHours
        if ($h -gt $limitH) { $frozen += ("{0} {1:N1} 小时没动" -f $nm, $h) }
    } else { $frozen += ("{0} 不存在" -f $nm) }
}
if ($frozen.Count -gt 0) {
    Add-Result 'WARN' '冻结' ($frozen -join '；') + " → 文件在但没动静（不是 0，是卡住）"
} else {
    Add-Result 'OK' '冻结' '工作层与运行记录 2 小时内都有动静'
}

# 44. 模型配置：换了模型就该做换模型实验（否则"变了"没人知道）
$ymlP = Join-Path $env:USERPROFILE '.dsh\profiles\desktop\cordis.patch.yml'
$baseP = Join-Path $Root 'track\换模型实验-基线.jsonl'
if (Test-Path $ymlP) {
    $ymlTxt = [IO.File]::ReadAllText($ymlP, [Text.Encoding]::UTF8)
    $mm = [regex]::Match($ymlTxt, 'provider:\s*(\S+)\s*\r?\n\s*model:\s*(\S+)')
    $curModel = if ($mm.Success) { $mm.Groups[2].Value } else { '?' }
    $baseModel = '?'
    if (Test-Path $baseP) {
        $bl = @(Get-Content $baseP -Encoding UTF8 | Where-Object { $_.Trim() } | Select-Object -First 1)
        if ($bl.Count -gt 0) { $baseModel = (($bl[0] | ConvertFrom-Json).model) }
    }
    if ($baseModel -eq '?') {
        Add-Result 'WARN' '模型配置' ("当前 model={0}，但没有基线 → 跑实验：exp-model-diff.ps1" -f $curModel)
    } elseif ($curModel -ne $baseModel) {
        Add-Result 'FAIL' '模型配置' ("模型已变：基线 {0} → 现在 {1} → 必须跑换模型实验（exp-model-diff.ps1）" -f $baseModel, $curModel)
    } else {
        Add-Result 'OK' '模型配置' ("model={0}，与基线一致" -f $curModel)
    }
} else {
    Add-Result 'WARN' '模型配置' '读不到 cordis.patch.yml'
}

# 45. 比喻层级：AGENTS 与术语对照都必须有这条（混层是本项目最容易复发的一类）
$agentsP2 = Join-Path $env:USERPROFILE '.dsh\AGENTS.md'
$glossP = Join-Path $Root 'track\术语对照.md'
$hasA = $false; $hasG = $false
if (Test-Path $agentsP2) { $hasA = ([IO.File]::ReadAllText($agentsP2, [Text.Encoding]::UTF8)).Contains('比喻词必须标层级') }
if (Test-Path $glossP)  { $hasG = ([IO.File]::ReadAllText($glossP, [Text.Encoding]::UTF8)).Contains('比喻的三个层级') }
if (-not $hasA -or -not $hasG) {
    Add-Result 'FAIL' '比喻层级' ("AGENTS:{0} / 术语对照:{1} → 这条丢了会重演「心脏=记忆还是核心层」" -f $(if($hasA){'有'}else{'缺'}), $(if($hasG){'有'}else{'缺'}))
} else {
    Add-Result 'OK' '比喻层级' 'AGENTS 与术语对照都有三层级规定'
}

# 46. 框架冻结：AGENTS 条数 ≤ 20、verify 项数 ≤ 46（防悄悄膨胀）
$agP = Join-Path $env:USERPROFILE '.dsh\AGENTS.md'
$ruleCnt = 0
if (Test-Path $agP) { $ruleCnt = ([regex]::Matches(([IO.File]::ReadAllText($agP,[Text.Encoding]::UTF8)),'(?m)^(\d+)\. \*\*')).Count }
if ($ruleCnt -gt 20) {
    Add-Result 'WARN' '框架冻结' ("AGENTS 已 {0} 条（冻结上限 20）→ 新增前先删一条，或先给检查" -f $ruleCnt)
} else {
    Add-Result 'OK' '框架冻结' ("AGENTS {0} 条（上限 20）；框架冻结中" -f $ruleCnt)
}
# 46. 核心纯 ASCII（2026-11-09 移交给免疫）：verify 不再自己扫一遍，
# 改成问 core/immunity.mjs 要 core-data-ascii 那一条的结论——标准在 spec，判在免疫。
$asciiRow = $null
try {
    $immJson = (Get-ImmuneJson)
    $immObj = $immJson | ConvertFrom-Json
    $asciiRow = @($immObj.rows | Where-Object { $_.id -eq 'core-data-ascii' })[0]
} catch { $asciiRow = $null }
if (-not $asciiRow) {
    Add-Result 'WARN' '核心纯 ASCII' '免疫没给出 core-data-ascii（检查器没跑起来？）'
} elseif (-not $asciiRow.ok) {
    Add-Result 'FAIL' '核心纯 ASCII' $asciiRow.detail
} else {
    Add-Result 'OK' '核心纯 ASCII' $asciiRow.detail
}

# 47. 器官清单（2026-11-09 移交免疫：判定在 core/immunity.mjs 的 organ-path）
$organRow = $null
try {
    $organJson = (Get-ImmuneJson)
    $organRow = @(($organJson | ConvertFrom-Json).rows | Where-Object { $_.id -eq 'organ-path' })[0]
} catch { $organRow = $null }
if (-not $organRow) {
    Add-Result 'WARN' '器官清单' '免疫没给出 organ-path（检查器没跑起来？）'
} elseif (-not $organRow.ok) {
    Add-Result 'FAIL' '器官清单' $organRow.detail
} else {
    Add-Result 'OK' '器官清单' $organRow.detail
}

# 48. 心跳还活着：最近一条 src7 距今不超过 5 分钟
# 为什么：心跳停过两次没人知道（2026-11-08 停 59 秒与 310 秒），当时 verify 全绿。
$hbAge = 9999
$hbOut = & node (Join-Path $Root 'core\timers-alive.mjs') 2>$null
if ($hbOut) { [void][int]::TryParse(("$hbOut".Trim()), [ref]$hbAge) }

# 阈值从 spec.expect 读，不写死（2026-11-08 实测：断了 103 秒它报 OK，因为写死 300 秒）。
# 心跳期望 = interval_ms * tolerance = 9000 ms = 9 秒。
$hbLimitSec = 9
try {
    $specJ = Get-Content (Join-Path $Root 'core\spec.json') -Encoding UTF8 -Raw | ConvertFrom-Json
    $hbLimitSec = [math]::Round($specJ.expect.heartbeat.interval_ms * $specJ.expect.heartbeat.tolerance / 1000)
} catch { }
if ($hbLimitSec -lt 3) { $hbLimitSec = 9 }if ($hbAge -eq 9999) { Add-Result 'FAIL' '心跳活着' '读不到心跳（timers-alive.mjs 无输出）' }
elseif ($hbAge -gt $hbLimitSec) { Add-Result 'FAIL' '心跳活着' ("心跳已停 {0} 秒（上限 {1} 秒，来自 spec.expect.heartbeat）" -f $hbAge, $hbLimitSec) }
else { Add-Result 'OK' '心跳活着' ("{0} 秒前还有一跳" -f $hbAge) }

# 49. 唯一根定义（2026-11-09 移交免疫：规则在 spec.liveness.roots，判定是 roots-unique）
$rootRow = $null
try {
    $rootJson = (Get-ImmuneJson)
    $rootRow = @(($rootJson | ConvertFrom-Json).rows | Where-Object { $_.id -eq 'roots-unique' })[0]
} catch { $rootRow = $null }
if (-not $rootRow) {
    Add-Result 'WARN' '唯一根定义' '免疫没给出 roots-unique（检查器没跑起来？）'
} elseif (-not $rootRow.ok) {
    Add-Result 'FAIL' '唯一根定义' $rootRow.detail
} else {
    Add-Result 'OK' '唯一根定义' $rootRow.detail
}

# 50. 定时器三件（2026-11-09 移交免疫：规则在 spec.liveness.timers，判定是 timers-present）
$timerRow = $null
try {
    $timerJson = (Get-ImmuneJson)
    $timerRow = @(($timerJson | ConvertFrom-Json).rows | Where-Object { $_.id -eq 'timers-present' })[0]
} catch { $timerRow = $null }
if (-not $timerRow) {
    Add-Result 'WARN' '定时器三件' '免疫没给出 timers-present（检查器没跑起来？）'
} elseif (-not $timerRow.ok) {
    Add-Result 'FAIL' '定时器三件' $timerRow.detail
} else {
    Add-Result 'OK' '定时器三件' $timerRow.detail
}

# 51. 探针报到（死信开关）：probe 跑完会写 track\.probe-last.json。
# 为什么：探针自己没探针，但它一定会"报到"——不报到就是没跑，数字不对就是有哑炮。
# 检查器之间不互跑（自指又慢），只查对方的新鲜度与结论。
$stampP = Join-Path $Root 'track\.probe-last.json'
if (-not (Test-Path $stampP)) {
    Add-Result 'FAIL' '探针报到' 'track\.probe-last.json 不存在（probe 从未跑过）'
} else {
    try {
        $sr = Get-Content $stampP -Encoding UTF8 -Raw | ConvertFrom-Json
        $ageH = ((Get-Date) - [DateTime]::Parse($sr.at)).TotalHours
        if ($sr.ok -ne $true) {
            Add-Result 'FAIL' '探针报到' ("上次探针有哑炮：{0}/{1} 通过" -f $sr.passed, $sr.total)
        } elseif ($ageH -gt 24) {
            Add-Result 'WARN' '探针报到' ("报到已过期 {0:N1} 小时（probe 该跑一次）" -f $ageH)
        } else {
            Add-Result 'OK' '探针报到' ("{0}/{1} 通过，{2:N1} 小时前报到" -f $sr.passed, $sr.total, $ageH)
        }
    } catch { Add-Result 'WARN' '探针报到' '报到文件解析失败' }
}
# 52. 协议纯 ASCII：写进总线的字段值与 json 数据文件不许有非 ASCII（spec.source_language）
# 为什么：规则写进 spec 只是纸面，没有任何东西查它，它明天就会被忘掉。
# 口径只查协议层——注释、console、中文文件名、中文语料、给人看的报错都不算。
$langOut = & node (Join-Path $Root 'check-source-language.mjs') 2>$null
if ($LASTEXITCODE -eq 0) {
    Add-Result 'OK' '协议纯 ASCII' 'json / bus / emit 参数全 ASCII'
} elseif ($langOut) {
    Add-Result 'FAIL' '协议纯 ASCII' (($langOut | Select-Object -First 1))
} else {
    Add-Result 'WARN' '协议纯 ASCII' 'check-source-language.mjs 跑不起来'
}
$checksBefore = $rows.Count
# 口径：expectedChecks = 总项数 − 1（自检这一项自己不计入）
# 2026-11-09：核心层大小与核心层结构合并成一项（交给免疫 core-page），总项数 53 → 52
$expectedChecks = 49
if ($checksBefore -lt $expectedChecks) {
    Add-Result 'FAIL' '检查器自检' ("只跑了 $checksBefore 项 / 预期 $expectedChecks 项 —— 有检查被跳过或结果被覆盖")
} elseif ($checksBefore -gt $expectedChecks) {
    Add-Result 'WARN' '检查器自检' ("跑了 $checksBefore 项 / 预期 $expectedChecks 项 —— 加了检查项但没更新预期常量")
} else {
    Add-Result 'OK' '检查器自检' ("$checksBefore 项（预期 $expectedChecks）")
}

$sw.Stop()

# ── 容差分级（2026-10-29 定）────────────────────────────────────────────
# 为什么：29 项全按 100% 判 → 天天违规 → WARN 变背景噪音，报警失效。
# 分级：硬 = 0 容忍（必须修）；软 = 允许 N 个（在预算内算通过，超了才 WARN）；提示 = 只记录不进计数。
# 容差到期（2026-10-30 定）：生死档的历史欠账只许「限期麻醉」，到期自动归零。
# 理由：容差等于止痛药；不分期的 allow 会让系统永远觉得自己没病（最安静的死法）。
$ToleranceExpiry = @{
    '完成声明有框' = '2026-11-15'   # 历史 12 条，限期清理
    '今日配额'     = '2026-11-01'   # 数据缺口，须补 published_at
    '发布依据链'   = '2026-11-01'   # 生死档：发布前必须有读回记录
    '无主语引用'   = '2026-11-01'   # 生死档：不许不指名的引用
    '术语引用'     = '2026-12-01'   # 生活档：说法可以慢慢用起来
}
$Tolerance = @{
    '完成声明有框' = @{ level = 'soft'; allow = 14; why = '历史 14 条不补（2026-11-15 必须清零）；新条目必须带可核的证，当天不合格当天修' }
    '今日配额'     = @{ level = 'soft'; allow = 1;  why = '台账有 1 条 published_at 缺失，发前手查' }
    '待消化'       = @{ level = 'soft'; allow = 0;  why = '积压必须清，0 容忍' }
    '发布依据链'   = @{ level = 'soft'; allow = 3;  why = '今晚两条发布前没记读回；此后必须记' }
    '术语引用'     = @{ level = 'soft'; allow = 3;  why = '新起的说法允许暂时没人引用' }
    '无主语引用'   = @{ level = 'soft'; allow = 2;  why = '已有稿件里的历史写法' }
    '自我集'       = @{ level = 'soft'; allow = 5;  why = '偏离 5 项以内算正常生长' }
}
foreach ($r in $rows) {
    if ($r.Level -ne 'WARN') { continue }
    $rule = $Tolerance[$r.Item]
    if (-not $rule) { continue }
    if ($rule.level -eq 'hint') { $r.Level = 'HINT'; continue }
    if ($rule.level -eq 'soft') {
        # 到期后 allow 归零（历史欠账不再被容忍）
        $exp = $ToleranceExpiry[$r.Item]
        if ($exp -and (Get-Date) -ge [datetime]::Parse($exp)) { $rule.allow = 0; $rule.why = "容差已于 $exp 到期" }
        # 从 Detail 里抠出第一个数字，和预算比
        # 只认「计数」位置的数字：发现 N 条 / 有 N 条 / N 条里 M 条 / N 个
        $n = 1
        foreach ($pat in @('发现 (\d+) 条', '有 (\d+) 条', '(\d+) 条里', '(\d+) 个')) {
            $m = [regex]::Match($r.Detail, $pat)
            if ($m.Success) { $n = [int]$m.Groups[1].Value; break }
        }
        # 「超上限 / 超了 / 逾期未判」这类属于硬违规，不许被容差吞掉
        if ($r.Detail -match '超 2 条|超上限|逾期未判|FAIL') { continue }
        if ($n -le $rule.allow) {
            $r.Level = 'SOFT'
            $r.Detail = $r.Detail + "（容差内 $n/$($rule.allow)：$($rule.why)）"
        }
    }
}

# ── WARN 不许挂着：同一项连续出现 3 次 → 升级为 FAIL（必须处理）─────────────
# 依据：用户 2026-10-30「我会痛，这种落差使我必须去改」——痛了不改 = 慢性病。
$streakF = Join-Path $Root 'track\warn-streak.json'
$streak = @{}
if (Test-Path $streakF) {
    try {
        $sj = Get-Content $streakF -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($pp in $sj.PSObject.Properties) { $streak[$pp.Name] = [int]$pp.Value }
    } catch { $streak = @{} }
}
$nowWarn = @($rows | Where-Object { $_.Level -eq 'WARN' } | ForEach-Object { $_.Item })
$newStreak = @{}
foreach ($it in $nowWarn) {
    $c = 1
    if ($streak.ContainsKey($it)) { $c = $streak[$it] + 1 }
    $newStreak[$it] = $c
    if ($c -ge 3) {
        $target = $rows | Where-Object { $_.Item -eq $it -and $_.Level -eq 'WARN' } | Select-Object -First 1
        if ($target) {
            $target.Level = 'FAIL'
            $target.Detail = "连续 $c 次未处理 → 必须处理。（原：$($target.Detail)）"
        }
    }
}
$obj = [pscustomobject]$newStreak
[IO.File]::WriteAllText($streakF, ($obj | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))

$fail  = @($rows | Where-Object Level -eq 'FAIL').Count
$warn  = @($rows | Where-Object Level -eq 'WARN').Count
$soft  = @($rows | Where-Object Level -eq 'SOFT').Count
$hint  = @($rows | Where-Object Level -eq 'HINT').Count
$okCnt = @($rows | Where-Object Level -eq 'OK').Count

if (-not $Quiet -or $fail -gt 0 -or $warn -gt 0) {
    $rows | ForEach-Object {
        $color = switch ($_.Level) {
            'OK'   { 'DarkGray' }
            'SOFT' { 'DarkYellow' }
            'HINT' { 'DarkGray' }
            'WARN' { 'Yellow' }
            'FAIL' { 'Red' }
        }
        Write-Host ("{0,3} {1,-5} {2,-16} {3}" -f $_.Id, $_.Level, $_.Item, $_.Detail) -ForegroundColor $color
    }
    Write-Host ("`n{0} 项：OK {1} / SOFT {2}（容差内） / WARN {3} / FAIL {4}   （{5:N0} ms）" -f $rows.Count, $okCnt, $soft, $warn, $fail, $sw.ElapsedMilliseconds) `
        -ForegroundColor $(if ($fail -gt 0) { 'Red' } elseif ($warn -gt 0) { 'Yellow' } else { 'Green' })
}


# 运行留痕：让「我刚才在跑什么」可被看见（只落盘，不占上下文）
$runLog = Join-Path $Root 'track\运行记录.txt'
$sum = ("{0}  verify  {1} 项：OK {2} / SOFT {3} / WARN {4} / FAIL {5}" -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $rows.Count, $okCnt, $soft, $warn, $fail)
[IO.File]::AppendAllText($runLog, $sum + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))

# 新标准（2026-11-07）：吐一行 SIG，由 core/adapter.mjs 统一转成总线信号。
# 不再自己直连 bus.mjs —— 六个器官走同一条路，换实现只改器官。
$st = 0; if ($fail -gt 0) { $st = 2 } elseif ($warn -gt 0) { $st = 1 }
Write-Output ("SIG " + (@{ state = $st; counts = @($rows.Count, $okCnt, $warn, $fail) } | ConvertTo-Json -Compress))

if ($fail -gt 0) { exit 1 } else { exit 0 }
