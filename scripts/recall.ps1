# recall.ps1 — 记一条「这次判断依据的是哪条痕迹」（补 C12 的 ⑤ 读回）
#
# 为什么：⑤ 读回是环上唯一没有检查器的一环。
# 我经常说不出「这次判断依据的是 1-工作.md 第几行」——说不出，就等于没有真的读回。
# 修法：把「依据」变成必填，且**当场打开验一次**；打不开就不许记进去（格式强制）。
#
# 用法：
#   .\recall.ps1 -Claim "判断一句话" -Src "notebook\11-结论.md:120"
#   .\recall.ps1 -List
param(
    [string]$Claim,
    [string]$Src,
    [string]$Evid = '',
    [switch]$List
)

$ErrorActionPreference = 'Continue'
$Root = (Get-Location).Path
$Out  = Join-Path $Root 'track\读回.jsonl'
$enc  = New-Object Text.UTF8Encoding($false)

function Show-List {
    if (-not (Test-Path $Out)) { Write-Host '还没有记录' ; return }
    $n = 0
    foreach ($ln in (Get-Content $Out -Encoding UTF8)) {
        if (-not $ln.Trim()) { continue }
        $n++
        try { $o = $ln | ConvertFrom-Json } catch { continue }
        Write-Host ("{0,2}. {1}  {2}" -f $n, $o.time, $o.claim) -ForegroundColor Gray
        Write-Host ("    依据：{0}" -f $o.src) -ForegroundColor DarkGray
    }
    Write-Host ("`n共 $n 条") -ForegroundColor Cyan
}

if ($List) { Show-List; exit 0 }

if (-not $Claim -or -not $Src) {
    Write-Host '用法： .\recall.ps1 -Claim "判断" -Src "相对路径:行号" [-Evid "证:…"]' -ForegroundColor Yellow
    Write-Host '       .\recall.ps1 -List'
    exit 1
}

# 依据必须能打开：文件存在 + 行号在范围内
$parts = $Src -split ':'
if ($parts.Count -lt 2) {
    Write-Host "依据格式不对：要写成 路径:行号（现在是 $Src）" -ForegroundColor Red
    exit 1
}
$rel  = $parts[0]
$line = 0
if (-not [int]::TryParse($parts[1], [ref]$line)) {
    Write-Host "行号不是数字：$($parts[1])" -ForegroundColor Red
    exit 1
}
$full = Join-Path $Root $rel
if (-not (Test-Path $full)) {
    Write-Host "依据打不开：文件不存在 $full" -ForegroundColor Red
    exit 1
}
$content = @(Get-Content $full -Encoding UTF8)
if ($line -lt 1 -or $line -gt $content.Count) {
    Write-Host "依据打不开：行号 $line 超出范围（该文件共 $($content.Count) 行）" -ForegroundColor Red
    exit 1
}
$thatLine = $content[$line - 1]

$rec = [pscustomobject]@{
    time  = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    claim = $Claim
    src   = $Src
    quote = $thatLine.Trim()
    evid  = $Evid
}
[IO.File]::AppendAllText($Out, ($rec | ConvertTo-Json -Compress) + "`n", $enc)

Write-Host ''
Write-Host '已记入 读回记录：' -ForegroundColor Green
Write-Host ("  判断：{0}" -f $rec.claim)
Write-Host ("  依据：{0}" -f $rec.src) -ForegroundColor DarkGray
Write-Host ("  原文：{0}" -f $rec.quote) -ForegroundColor DarkGray
exit 0
