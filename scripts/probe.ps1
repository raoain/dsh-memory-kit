# probe.ps1 — 探针：拿假错去试检查器，看它们是不是哑炮
#
# 为什么：2026-10-29 发现 lint 的参数同名检查从上线起就是死的——
# 正则里 $ 被当成行尾锚点，永远不匹配，它一直报「没有问题」。
# 检查器也是断言的一种（它断言「我能发现这类错误」），而这个断言从没被验证过。
#
# 做法：在临时目录里造已知的错，跑对应检查器，看它报不报。
#      全报 = 检查器活着；有一个不报 = 那个是哑炮。
#
# 用法： powershell -NoProfile -File <你的项目根>\probe.ps1
# 退出码：0 = 全部活着；1 = 有哑炮

$ErrorActionPreference = 'Continue'
$Root = (Get-Location).Path
$tmp  = Join-Path $env:TEMP ('probe-' + (Get-Date -Format 'HHmmss'))
$results = @()

function New-TempFile($name, $content) {
    if (-not (Test-Path $tmp)) { New-Item -ItemType Directory -Force -Path $tmp | Out-Null }
    $p = Join-Path $tmp $name
    [IO.File]::WriteAllText($p, $content, (New-Object Text.UTF8Encoding($true)))
    return $p
}

function Add-Probe($name, $ok, $detail) {
    $script:results += [pscustomobject]@{ Probe = $name; OK = $ok; Detail = $detail }
}

# ── 探针 1：lint 能不能抓到「参数与体内变量同名」
# 造：param([switch]$Due) 之后又 $due = ...
$p1 = New-TempFile 'shadow.ps1' "param([switch]`$Due)`r`n`$due = @()`r`nWrite-Host `$due.Count`r`n"
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'lint.ps1') -Path $tmp 2>&1 | Out-String
Add-Probe 'lint 抓参数同名' ($out -match 'shadow') $(if ($out -match 'shadow') { '报了 shadow' } else { '没报 → lint 的 shadow 检查是哑炮' })

# ── 探针 2：lint 能不能抓到 PS 5.1 不支持的三元运算符
$p2 = New-TempFile 'tern.ps1' "`$x = 1)`r`n`$y = (`$x -gt 0) ? 'a' : 'b'`r`nWrite-Host `$y`r`n"
$out2 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'lint.ps1') -Path $tmp 2>&1 | Out-String
Add-Probe 'lint 抓三元运算符' ($out2 -match 'ps51') $(if ($out2 -match 'ps51') { '报了 ps51' } else { '没报 → 三元检查是哑炮' })

# ── 探针 3：attrib 能不能抓到「说了用户说、但没引文」
$p3 = New-TempFile 'attrib.md' "用户说这个方案可行，可以发。`r`n"
$out3 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'attrib.ps1') -Path $tmp 2>&1 | Out-String
Add-Probe 'attrib 抓归因无引文' ($out3 -match '归因无引文') $(if ($out3 -match '归因无引文') { '报了无引文' } else { '没报 → attrib 是哑炮' })

# ── 探针 4：intake 对「确实存在的内容」应 PASS
$p4 = New-TempFile 'truth.md' "核心层写着：意识的根本是逻辑链。`r`n"
$out4 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'intake.ps1') -Kind file -Claim '探针：真断言' -Expect '意识的根本是逻辑链' -Loc $p4 2>&1 | Out-String
Add-Probe 'intake 放行真断言' ($out4 -match 'PASS') $(if ($out4 -match 'PASS') { 'PASS' } else { '没 PASS → intake 过严，会把真话判死' })

# ── 探针 5：intake 对「捏造的内容」应 FAIL（防假 PASS）
$out5 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'intake.ps1') -Kind file -Claim '探针：假断言' -Expect '这句话文件里一定没有zzz' -Loc $p4 2>&1 | Out-String
Add-Probe 'intake 拒绝假断言' ($out5 -match 'FAIL') $(if ($out5 -match 'FAIL') { 'FAIL' } else { '假断言被判 PASS → intake 自我印证' })

# ── 输出
Write-Host ''
Write-Host '=== 探针结果 ===' -ForegroundColor Cyan
$bad = 0
foreach ($r in $results) {
    if ($r.OK) { Write-Host ("  活着  {0}" -f $r.Probe) -ForegroundColor Green }
    else { Write-Host ("  哑炮  {0}   {1}" -f $r.Probe, $r.Detail) -ForegroundColor Red; $bad++ }
}
Write-Host ''
if ($bad -eq 0) {
    Write-Host ("{0} 个探针全部通过：检查器都能抓到对应的假错" -f $results.Count) -ForegroundColor Green
} else {
    Write-Host ("{0}/{1} 个探针失败：有检查器是哑炮" -f $bad, $results.Count) -ForegroundColor Red
}

if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
if ($bad -gt 0) { exit 1 } else { exit 0 }
