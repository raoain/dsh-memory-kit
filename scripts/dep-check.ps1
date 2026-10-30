# dep-check.ps1 — 结构判据：脚本之间的依赖不许成环，且叶子脚本不许被别人调
#
# 借自 kinganyi/fish 的做法（J2/J6：领域模块不得 import 主模块；J1b：导出面双向对账）：
# 判的是「结构有没有坏」，与具体内容无关，所以能自动跑。
#
# 用法： .\dep-check.ps1        （发现问题 exit 1）
param([string]$Root = (Get-Location).Path, [switch]$Verbose)

$ErrorActionPreference = 'Continue'
$enc = New-Object Text.UTF8Encoding($false)

# 根目录脚本
$scripts = @(Get-ChildItem $Root -Filter '*.ps1' -File | ForEach-Object { $_.Name })
$graph = @{}
foreach ($s in $scripts) {
    $txt = [IO.File]::ReadAllText((Join-Path $Root $s), [Text.Encoding]::UTF8)
    # 找「调用了哪个 .ps1」
    # 只认真正的调用：powershell -File x.ps1 ／ & "...x.ps1" ／ . "...x.ps1"
    $calls = @()
    foreach ($line in ($txt -split "`r?`n")) {
        if ($line.TrimStart().StartsWith('#')) { continue }
        $m1 = [regex]::Matches($line, '-File\s+["'']?([A-Za-z0-9\-$\\/\._]+\.ps1)')
        $m2 = [regex]::Matches($line, '[&\.]\s+\(?Join-Path[^)]*?["'']([A-Za-z0-9\-]+\.ps1)["'']')
        $m3 = [regex]::Matches($line, '^\s*[&\.]\s+["'']?([A-Za-z0-9\-]+\.ps1)')
        foreach ($mm in @($m1) + @($m2) + @($m3)) { if ($mm.Success) { $calls += (Split-Path $mm.Groups[1].Value -Leaf) } }
    }
    $calls = @($calls | Where-Object { $_ -ne $s } | Sort-Object -Unique)
    $graph[$s] = $calls
}

# ① 循环依赖检测（DFS）
$state = @{}   # 0=未访问 1=在栈 2=已完成
$cycles = @()
function Walk($node, $path) {
    $state[$node] = 1
    foreach ($next in $graph[$node]) {
        if (-not $graph.ContainsKey($next)) { continue }
        if ($state[$next] -eq 1) {
            $script:cycles += (($path + $node + $next) -join ' → ')
        } elseif (-not $state[$next]) {
            Walk $next ($path + $node + ',')
        }
    }
    $state[$node] = 2
}
foreach ($s in $scripts) { if (-not $state[$s]) { Walk $s '' } }

# ② 叶子判据：verify / pin / probe 是「判定者」，不许被别的脚本调用（判定者不能被被判定者调用）
$judges = @('verify.ps1','pin.ps1','probe.ps1','attrib.ps1','lint.ps1')
$violations = @()
foreach ($s in $scripts) {
    foreach ($next in $graph[$s]) {
        if ($judges -contains $next -and $s -ne 'start.ps1' -and $s -ne 'close.ps1' -and $s -ne 'log.ps1') {
            $violations += ("{0} 调用了判定者 {1}" -f $s, $next)
        }
    }
}

Write-Host ''
Write-Host ('  脚本 {0} 个；有调用的脚本 {1} 个' -f $scripts.Count, @($graph.Keys | Where-Object { $graph[$_].Count -gt 0 }).Count)
if ($Verbose) {
    foreach ($k in ($graph.Keys | Sort-Object)) {
        if ($graph[$k].Count -gt 0) { Write-Host ('    {0} → {1}' -f $k, ($graph[$k] -join ', ')) -ForegroundColor DarkGray }
    }
}
if ($cycles.Count -gt 0) {
    Write-Host '  ✘ 存在循环依赖：' -ForegroundColor Red
    $cycles | Select-Object -Unique | ForEach-Object { Write-Host ('    ' + $_) -ForegroundColor Red }
} else {
    Write-Host '  ✔ 无循环依赖' -ForegroundColor Green
}
if ($violations.Count -gt 0) {
    Write-Host '  ✘ 判定者被调用（判定者只许被 start/close/log 调）：' -ForegroundColor Red
    $violations | ForEach-Object { Write-Host ('    ' + $_) -ForegroundColor Red }
} else {
    Write-Host '  ✔ 判定者未被越权调用' -ForegroundColor Green
}

$bad = $cycles.Count + $violations.Count
exit ([int]($bad -gt 0))
