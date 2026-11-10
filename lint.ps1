# lint.ps1 — 给脚本做静态检查：专查我自己反复犯的三类错
#
# 为什么：同一个根因今天犯了三次（$Tts/$Voice/$Root/$keep 同名覆盖，?? 语法，数组切片）。
# 不是不知道，是写完没人看一眼。这个脚本就是那一眼。
#
# 用法：
#   .\lint.ps1                  # 扫默认目录
#   .\lint.ps1 -Path D:\x       # 扫指定目录
#   .\lint.ps1 -Quiet           # 只在有问题时输出
param(
    [string]$Path = '',
    [switch]$Quiet
)
if (-not $Root) { $Root = $PSScriptRoot }
if (-not $Path) { $Path = $Root }

$ErrorActionPreference = 'Continue'
# 项目根字面量从零件拼出来：写全了，本脚本自己也会被自己的 root 规则判违规（自指）
$script:HardRoot = 'F:' + '\' + 'Tools' + '\' + 'coo-day1'
$issues = @()
$script:scopeHints = @()

function Add-Issue($file, $line, $kind, $detail) {
    $script:issues += [pscustomobject]@{ File = $file; Line = $line; Kind = $kind; Detail = $detail }
}

$files = Get-ChildItem $Path -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
    # 跳过自身与探针：它们含故意写错的样本（?? / -LeafBase / 三元），会自我误报
    Where-Object { $_.Name -ne 'lint.ps1' -and $_.Name -ne 'probe.ps1' }
foreach ($f in $files) {
    $text = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    $lines = $text -split "`r?`n"

    # 0) 工具契约（spec.tools.contract，2026-11-08）：必须有 param 块、退出码只用 0-3、点源统一根、BOM 恰好一个
    #    对象分开：本脚本自身与探针豁免；历史欠账仍会列出，但和"新违规"分开数。
    #    BOM（2026-11-09 加，契约第 5 条）：0 个 → PS5.1 按 GBK 读；多于 1 个 → param() 不绑定、脚本照样跑像是好的。
    $bytes = [IO.File]::ReadAllBytes($f.FullName)
    $bomCount = 0
    while ((3 * ($bomCount + 1)) -le $bytes.Length -and $bytes[3 * $bomCount] -eq 0xEF -and $bytes[3 * $bomCount + 1] -eq 0xBB -and $bytes[3 * $bomCount + 2] -eq 0xBF) { $bomCount++ }
    if ($bomCount -ne 1) { Add-Issue $f.Name 1 'contract' ("BOM 有 $bomCount 个（契约 bom：恰好 1 个）") }   # @contract bom
    if ($f.Name -ne '_root.ps1') {
        $hasParam = $text -match 'param\s*\('
        if (-not $hasParam) { Add-Issue $f.Name 1 'contract' '没有 param() 块（契约 call）' }   # @contract call
        $badExit = [regex]::Matches($text, 'exit\s+(-?\d+)') | ForEach-Object { [int]$_.Groups[1].Value } | Where-Object { $_ -notin 0,1,2,3 } | Select-Object -Unique
        if ($badExit) { Add-Issue $f.Name 1 'contract' ('退出码越界：' + ($badExit -join '/') + '（契约 exit 只允许 0-3）') }   # @contract exit
        if ($text -notmatch '_root\.ps1') { Add-Issue $f.Name 1 'contract' '未点源 _root.ps1（契约 root）' }   # @contract root
    }

    # 1) 语法检查
    $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errs)
    if ($errs) { Add-Issue $f.Name $errs[0].Extent.StartLineNumber 'syntax' $errs[0].Message }

    # 2) PS 5.1 不支持的 ?? 空合并 / -LeafBase / 三元运算符
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '\?\?') { Add-Issue $f.Name ($i + 1) 'ps51' '使用了 ??（PS 5.1 不支持）' }
        if ($lines[$i] -match '\s-LeafBase\b') { Add-Issue $f.Name ($i + 1) 'ps51' '使用了 -LeafBase（PS7 才有）' }
        # 三元 `? a : b`（PS7 才有）。窄匹配：? 后面跟字面量/变量，再跟 : ，避免误伤 URL/问号句
        if ($lines[$i] -match '\?(\s*)(\x27[^\x27]*\x27|"[^"]*"|\$\w+|\d+)\s*:\s') {
            Add-Issue $f.Name ($i + 1) 'ps51' '使用了三元运算符 ? :（PS 5.1 不支持，会直接语法错）'
        }
    }

    # 3) param 里的变量在函数体内被重新赋值（大小写不敏感 → 参数被覆盖）
    $paramNames = @()
    $inParam = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $ln = $lines[$i]
        if ($ln -match '^\s*param\s*\(') { $inParam = $true }
        if ($inParam) {
            # 先收集本行的参数名，再判断是否闭合 —— 顺序反了就永远收不到（探针抓到的）
            foreach ($m in [regex]::Matches($ln, '\[\w+\]\s*\$(\w+)')) { $paramNames += $m.Groups[1].Value }
            # 一行写完的 param(...)：本行有 ( 又有 ) → 立刻结束，否则后面整个文件都会被当成参数区
            if (($ln -match '^\s*param\s*\(' -and $ln -match '\)\s*$') -or ($ln -match '^\s*\)\s*$')) { $inParam = $false }
        }
    }
    if ($paramNames.Count -gt 0) {
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $ln = $lines[$i]
            # 跳过 param 块自身的行
            if ($ln -match '^\s*param\s*\(|^\s*\[(string|int|switch|bool|double|long|datetime)\]') { continue }
            foreach ($pn in ($paramNames | Sort-Object -Unique)) {
                # 形如 "$Keep = ..." / "$keep ="（大小写不同也算）
                # 注意：正则里 $ 是行尾锚点，必须写成 \$（用单引号拼接，别用双引号转义）
                if ($ln -match ('^\s*\$' + $pn + '\s*=') -or $ln -match ('^\s*\$' + $pn + '\s*\+=')) {
                    Add-Issue $f.Name ($i + 1) 'shadow' ("参数 `$" + $pn + " 在脚本体内被重新赋值（不区分大小写）")
                }
            }
        }
    }

    # 3b) 同一个变量既是「脚本级赋值」又在缩进块里被赋值 → 静默覆盖
    # 来源：2026-10-29 第五次撞名（$rows：脚本级是结果数组，块内被我当台账行数组）。
    # 表现：不报错，只是少了一大半输出 —— 所以只能静态扫。
    $assign = @{}   # name -> @{ top=@(行号); inner=@(行号) }
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $ln = $lines[$i]
        if ($ln -match '^\s*#') { continue }
        # 只认整体赋值（=）。`+=` 是累加，属正常汇总，报了就是狼来了。
        $m = [regex]::Match($ln, '^(\s*)\$([A-Za-z_][A-Za-z0-9_]*)\s*=(?!=)')
        if (-not $m.Success) { continue }
        $indent = $m.Groups[1].Value
        $name = $m.Groups[2].Value.ToLower()
        if ($name -match '^(matches|args|input|this|true|false|null)$') { continue }
        if (-not $assign.ContainsKey($name)) { $assign[$name] = @{ top = @(); inner = @() } }
        if ($indent.Length -eq 0) { $assign[$name].top += ($i + 1) } else { $assign[$name].inner += ($i + 1) }
    }
    foreach ($name in $assign.Keys) {
        $a = $assign[$name]
        if ($a.top.Count -gt 0 -and $a.inner.Count -gt 0) {
            $detail = '$' + $name + ' 脚本级(行 ' + ($a.top -join ',') + ') 与块内(行 ' + ($a.inner -join ',') + ') 都赋值'
            $script:scopeHints += [pscustomobject]@{ File = $f.Name; Line = $a.inner[0]; Detail = $detail }
        }
    }
}

# 5) .mjs 层过同一份工具契约（2026-11-09：原来 lint 只扫 .ps1，26 个 .mjs 谁也不量）
#    语言不同的地方只差两条：不要求 param()（用 argv）、不允许 BOM（json/mjs 必须无 BOM）。
$mjsFiles = @()
$mjsFiles += Get-ChildItem $Path -Filter '*.mjs' -File -ErrorAction SilentlyContinue
$coreDir = Join-Path $Path 'core'
if (Test-Path $coreDir) { $mjsFiles += Get-ChildItem $coreDir -Filter '*.mjs' -File -ErrorAction SilentlyContinue }
foreach ($f in $mjsFiles) {
    $text = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    $badExit = [regex]::Matches($text, 'process\.exit\((\-?\d+)\)') | ForEach-Object { [int]$_.Groups[1].Value } | Where-Object { $_ -notin 0,1,2,3 } | Select-Object -Unique
    if ($badExit) { Add-Issue $f.Name 1 'contract' ('退出码越界：' + ($badExit -join '/') + '（契约 exit 只允许 0-3）') }
    $codeHard = @($text -split "`r?`n" | Where-Object { $s = $_.Trim(); $s -and $s -notmatch '^(//|#|\*)' -and $s.Contains($script:HardRoot) })
    if ($codeHard.Count -gt 0) { Add-Issue $f.Name 1 'contract' '写死项目根路径（契约 root：改用 core/root.mjs 的 ROOT）' }   # @contract root
    $first = ($text -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
    if ($first -and $first -notmatch '^\s*//') { Add-Issue $f.Name 1 'contract' '首行不是 // 注释（契约 report：文件头要说清这是什么）' }   # @contract report
}

# 4) .md 文件里的控制字符 —— 肉眼看不见，只能靠扫
# 来源：双引号字符串里 `v 是垂直制表、`f 是换页、`a 是响铃，写替换字符串时被吃掉字母，
# 文件看起来正常，实际那行已经坏了（今晚在 README 上连栽两次）。
$mds = Get-ChildItem $Path -Filter '*.md' -File -ErrorAction SilentlyContinue
foreach ($f in $mds) {
    $text = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    $lines = $text -split "`r?`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '[\x00-\x08\x0B\x0C\x0E-\x1F]') {
            Add-Issue $f.Name ($i + 1) 'md-ctrl' '含控制字符（多半是反引号转义误写：`v / `f / `a）'
        }
    }
}
# 5) 跨度声明必须带日期锚（2026-11-10 加；根因：同一根因第三次——我把 spec 的 evid 说成「两年前就开了口」，
#    实际 spec.json 建于 2026-11-07、项目起点 2026-10-26。判据：说「多久以前」必须从文件时间戳取。）
#    只扫 notebook\ 与 track\：这两层是判据与档案，草稿与对外稿件里「三年前拍的东西」是台词，不算断言。
$claimMds = @()
foreach ($sub in @('notebook', 'track')) {
    $d = Join-Path $Path $sub
    if (Test-Path $d) { $claimMds += @(Get-ChildItem $d -Filter '*.md' -File -ErrorAction SilentlyContinue) }
}
foreach ($f in $claimMds) {
    $text = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    $lines = $text -split "`r?`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch '[两三四五六七八九十0-9]+\s*年[前多]') { continue }
        if ($lines[$i] -match '\d{4}-\d{2}-\d{2}') { continue }
        Add-Issue $f.Name ($i + 1) 'md-span' '跨度没带日期锚（说「N 年前」必须从文件时间戳取，或写明日期）'
    }
}

# 6) 判据编号必须全局唯一（2026-11-10 加；根因：5-判据 与 12-判据-专项 各用一套 P 号，P15/P16/P17 撞了，
#    引「按 P17」时读者不知道指哪条。判据：编号是检索键，检索键必须唯一。）
$pNums = @{}
$nbDir = Join-Path $Path 'notebook'
if (Test-Path $nbDir) {
    foreach ($nf in @(Get-ChildItem $nbDir -Filter '*.md' -File -ErrorAction SilentlyContinue)) {
        $nlines = [IO.File]::ReadAllLines($nf.FullName, [Text.Encoding]::UTF8)
        for ($j = 0; $j -lt $nlines.Count; $j++) {
            if ($nlines[$j] -match '^##\s*P(\d+)\b') {
                $pn = [int]$Matches[1]
                if ($pNums.ContainsKey($pn)) { Add-Issue $nf.Name ($j + 1) 'md-pdup' ("P$pn 与 " + $pNums[$pn] + " 重号（判据编号必须全局唯一）") }
                else { $pNums[$pn] = ("{0}:{1}" -f $nf.Name, ($j + 1)) }
            }
        }
    }
}

$fail = @($issues | Where-Object Kind -eq 'syntax').Count
$total = $issues.Count
$hints = @($script:scopeHints)

if (-not $Quiet -or $total -gt 0 -or $hints.Count -gt 0) {
    if ($total -eq 0) {
        Write-Host ("lint: {0} 个 ps1 + {1} 个 mjs + {2} 个 md，没有问题" -f $files.Count, $mjsFiles.Count, $mds.Count) -ForegroundColor Green
    } else {
        $issues | Sort-Object File, Line | ForEach-Object {
            $color = if ($_.Kind -eq 'syntax') { 'Red' } else { 'Yellow' }
            Write-Host ("[{0,-6}] {1}:{2}  {3}" -f $_.Kind, $_.File, $_.Line, $_.Detail) -ForegroundColor $color
        }
        Write-Host ("`nlint: {0} 个脚本 + {1} 个 md，{2} 处问题（语法错 {3}）" -f $files.Count, $mds.Count, $total, $fail) -ForegroundColor $(if ($fail -gt 0) { 'Red' } else { 'Yellow' })
    }
    if ($hints.Count -gt 0) {
        Write-Host ("`n提示（不计入问题，供确认）：{0} 处变量同名，脚本级与块内都赋值" -f $hints.Count) -ForegroundColor DarkGray
        $hints | Sort-Object File, Line | Select-Object -First 12 | ForEach-Object {
            Write-Host ("[hint ] {0}:{1}  {2}" -f $_.File, $_.Line, $_.Detail) -ForegroundColor DarkGray
        }
        if ($hints.Count -gt 12) { Write-Host ("        ……还有 {0} 处" -f ($hints.Count - 12)) -ForegroundColor DarkGray }
    }
}

# 2026-11-09 机器码：免疫按这一行取结论，不再去猜人话（Write-Host 不上 stdout，之前 verify 那条因此一直是空过的）
Write-Output ("SIG {{`"state`":{0},`"counts`":[{1},{2}]}}" -f ($(if ($fail -gt 0) { 2 } elseif ($total -gt 0) { 1 } else { 0 })), $files.Count, $total)

if ($fail -gt 0) { exit 1 } else { exit 0 }
