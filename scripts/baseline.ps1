# baseline.ps1 — 自我集：把「我健康时的样子」拍下来，之后偏离就报
#
# 为什么（2026-10-30）：免疫系统只学「正常」，因为异常无穷而正常有限。
# 我们原来的做法反了：手写 40 条「什么算错」，从没定义「正常长什么样」。
# 而且设定点只能自己测——主流的数值一个都抄不了（机制可借，量级不可借）。
#
# 用法：
#   .\baseline.ps1 -Snap     拍快照（自己健康时跑，覆盖旧基线）
#   .\baseline.ps1           比对（默认），偏离就报
param([switch]$Snap)

$ErrorActionPreference = 'Continue'
$Root = (Get-Location).Path
$Out  = Join-Path $Root 'track\baseline.json'
$nb   = Join-Path $Root 'notebook'
$enc  = New-Object Text.UTF8Encoding($false)

function Measure-State {
    $s = [ordered]@{}
    # 关键页字节
    foreach ($f in @('0-核心.md','9-用户.md','11-结论.md','5-判据.md','12-判据-专项.md','6-话.md','13-对照.md')) {
        $p = Join-Path $nb $f
        if (Test-Path $p) { $s["bytes:$f"] = (Get-Item $p).Length }
    }
    # 条目数
    $cnt = {
        param($path, $pat)
        if (-not (Test-Path $path)) { return 0 }
        return @(Select-String -Path $path -Pattern $pat -Encoding UTF8).Count
    }
    $s['判据条数']   = (& $cnt (Join-Path $nb '5-判据.md') '^## P\d')
    $s['专项条数']   = (& $cnt (Join-Path $nb '12-判据-专项.md') '^## P\d')
    $s['结论条数']   = (& $cnt (Join-Path $nb '11-结论.md') '^## C\d')
    $s['说法条数']   = (& $cnt (Join-Path $nb '11-结论.md') '^### S\d')
    $s['档案条数']   = (& $cnt (Join-Path $nb '2-档案.md') '^### ')
    $s['页数']       = @(Get-ChildItem $nb -Filter '*.md' -File).Count
    $s['脚本数']     = @(Get-ChildItem $Root -Filter '*.ps1' -File).Count
    $s['grep样本数'] = 0
    foreach ($jf in @('track\收敛.jsonl','track\读回.jsonl','track\发布台账.jsonl','track\待消化.md')) {
        $p = Join-Path $Root $jf
        if (Test-Path $p) { $s[$jf] = @(Get-Content $p -Encoding UTF8 | Where-Object { $_.Trim() }).Count }
    }
    return $s
}

$now = Measure-State

if ($Snap) {
    $obj = [pscustomobject]@{
        snapAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        note   = '自我集：正常时的样子（由 baseline.ps1 -Snap 采集）'
        state  = $now
    }
    [IO.File]::WriteAllText($Out, ($obj | ConvertTo-Json -Depth 5), $enc)
    Write-Host ''
    Write-Host ('基线已拍下：{0}   共 {1} 个指标' -f $obj.snapAt, $now.Count) -ForegroundColor Green
    foreach ($k in $now.Keys) { Write-Host ("  {0,-22} {1}" -f $k, $now[$k]) -ForegroundColor DarkGray }
    exit 0
}

# 比对
if (-not (Test-Path $Out)) {
    Write-Host '还没有基线 → 先跑 baseline.ps1 -Snap' -ForegroundColor Yellow
    exit 1
}
$base = Get-Content $Out -Raw -Encoding UTF8 | ConvertFrom-Json
$baseState = $base.state
$diffs = @()
foreach ($k in $baseState.PSObject.Properties.Name) {
    $oldV = $baseState.$k
    if (-not $now.Contains($k)) { $diffs += ("{0} 基线 {1} → 现在 消失" -f $k, $oldV); continue }
    $newV = $now[$k]
    if ($oldV -ne $newV) { $diffs += ("{0} 基线 {1} → 现在 {2}" -f $k, $oldV, $newV) }
}
Write-Host ''
Write-Host ('基线：{0}' -f $base.snapAt) -ForegroundColor Cyan
if ($diffs.Count -eq 0) {
    Write-Host '  没有任何偏离（和健康时一模一样）' -ForegroundColor Green
} else {
    Write-Host ('  偏离 {0} 项：' -f $diffs.Count) -ForegroundColor Yellow
    foreach ($d in $diffs) { Write-Host ('    ' + $d) -ForegroundColor Yellow }
}
exit 0
