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
    [string]$Path = ((Split-Path $PSScriptRoot -Parent)),
    [switch]$Quiet
)

$ErrorActionPreference = 'Continue'
$issues = @()

function Add-Issue($file, $line, $kind, $detail) {
    $script:issues += [pscustomobject]@{ File = $file; Line = $line; Kind = $kind; Detail = $detail }
}

$files = Get-ChildItem $Path -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
    # 跳过自身：它自己就含 ?? 与 -LeafBase 的正则字面量，会误报
    Where-Object { $_.Name -ne 'lint.ps1' }
foreach ($f in $files) {
    $text = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    $lines = $text -split "`r?`n"

    # 1) 语法检查
    $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errs)
    if ($errs) { Add-Issue $f.Name $errs[0].Extent.StartLineNumber 'syntax' $errs[0].Message }

    # 2) PS 5.1 不支持的 ?? 空合并
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '\?\?') { Add-Issue $f.Name ($i + 1) 'ps51' '使用了 ??（PS 5.1 不支持）' }
        if ($lines[$i] -match '\s-LeafBase\b') { Add-Issue $f.Name ($i + 1) 'ps51' '使用了 -LeafBase（PS7 才有）' }
    }

    # 3) param 里的变量在函数体内被重新赋值（大小写不敏感 → 参数被覆盖）
    $paramNames = @()
    $inParam = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $ln = $lines[$i]
        if ($ln -match '^\s*param\s*\(') { $inParam = $true }
        if ($inParam) {
            foreach ($m in [regex]::Matches($ln, '\[\w+\]\s*\$(\w+)')) { $paramNames += $m.Groups[1].Value }
            if ($ln -match '^\s*\)\s*$') { $inParam = $false }
        }
    }
    if ($paramNames.Count -gt 0) {
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $ln = $lines[$i]
            # 跳过 param 块自身的行
            if ($ln -match '^\s*param\s*\(|^\s*\[(string|int|switch|bool|double|long|datetime)\]') { continue }
            foreach ($pn in ($paramNames | Sort-Object -Unique)) {
                # 形如 "$Keep = ..." / "$keep ="（大小写不同也算）
                if ($ln -match ("^\s*`$" + $pn + "\s*=") -or $ln -match ("^\s*`$" + $pn + "\s*\+=")) {
                    Add-Issue $f.Name ($i + 1) 'shadow' ("参数 `$" + $pn + " 在脚本体内被重新赋值（不区分大小写）")
                }
            }
        }
    }
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
$fail = @($issues | Where-Object Kind -eq 'syntax').Count
$total = $issues.Count

if (-not $Quiet -or $total -gt 0) {
    if ($total -eq 0) {
        Write-Host ("lint: {0} 个脚本 + {1} 个 md，没有问题" -f $files.Count, $mds.Count) -ForegroundColor Green
    } else {
        $issues | Sort-Object File, Line | ForEach-Object {
            $color = if ($_.Kind -eq 'syntax') { 'Red' } else { 'Yellow' }
            Write-Host ("[{0,-6}] {1}:{2}  {3}" -f $_.Kind, $_.File, $_.Line, $_.Detail) -ForegroundColor $color
        }
        Write-Host ("`nlint: {0} 个脚本 + {1} 个 md，{2} 处问题（语法错 {3}）" -f $files.Count, $mds.Count, $total, $fail) -ForegroundColor $(if ($fail -gt 0) { 'Red' } else { 'Yellow' })
    }
}

if ($fail -gt 0) { exit 1 } else { exit 0 }
