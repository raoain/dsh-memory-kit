# predict.ps1 — 预登记：在结果出来之前写下预测与判定标准
#
# 为什么：事后解释永远成立。只有「出事之前写下的预测」才有资格叫检验，
# 因为它没法被当场修改。没有这个，我们所有的「反正又对上了」都只是自证。
#
# 用法：
#   .\predict.ps1 -Add -Claim "改标题能把播放救起来" -Expect "48 小时内播放 > 0" -Falsifier "48 小时仍是 0" -By "2026-10-31 21:00"
#   .\predict.ps1 -List                 # 全部预测（含逾期）
#   .\predict.ps1 -Due                  # 只列到期待判的
#   .\predict.ps1 -Verdict <id> -Result 成立|推翻  -Evid "实际读到的数"
# 文件：track\预测.jsonl（一行一条，append-only）
param(
    [switch]$Add,
    [switch]$List,
    [switch]$Due,
    [string]$Claim,
    [string]$Expect,
    [string]$Falsifier,
    [string]$By,
    [string]$Verdict,
    [ValidateSet('成立','部分','推翻','未判','')][string]$Result = '',
    [string]$Evid = ''
)

$Root   = (Get-Location).Path
$File   = Join-Path $Root 'track\预测.jsonl'
$enc    = New-Object Text.UTF8Encoding($false)
if (-not (Test-Path (Split-Path $File))) { New-Item -ItemType Directory -Force -Path (Split-Path $File) | Out-Null }

function Read-Preds {
    $out = @()
    if (Test-Path $File) {
        foreach ($ln in (Get-Content $File -Encoding UTF8)) {
            if (-not $ln.Trim()) { continue }
            try { $out += ($ln | ConvertFrom-Json) } catch { }
        }
    }
    return $out
}

if ($Add) {
    if (-not $Claim -or -not $Expect -or -not $Falsifier -or -not $By) {
        Write-Host '需要 -Claim -Expect -Falsifier -By 四个都填' -ForegroundColor Red; exit 2
    }
    $rec = [pscustomobject]@{
        id        = 'p' + (Get-Date -Format 'MMddHHmmss') + (Get-Random -Minimum 10 -Maximum 99)
        claim     = $Claim          # 我在预测什么
        expect    = $Expect         # 预期结果
        falsifier = $Falsifier      # 什么结果算这条判据错了
        by        = $By             # 判定截止时间
        created   = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        result    = '未判'
        evid      = ''
        judged_at = ''
    }
    [IO.File]::AppendAllText($File, ($rec | ConvertTo-Json -Compress) + "`n", $enc)
    Write-Host ("已登记预测 {0}" -f $rec.id) -ForegroundColor Green
    Write-Host ("  预期：{0}" -f $Expect)
    Write-Host ("  算它错：{0}" -f $Falsifier)
    Write-Host ("  截止：{0}" -f $By)
    return
}

if ($Verdict) {
    $all = Read-Preds
    $hit = $all | Where-Object { $_.id -eq $Verdict }
    if (-not $hit) { Write-Host "找不到预测 $Verdict" -ForegroundColor Red; exit 2 }
    $hit.result = $Result
    $hit.evid = $Evid
    $hit.judged_at = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    $lines = $all | ForEach-Object { $_ | ConvertTo-Json -Compress }
    [IO.File]::WriteAllText($File, ($lines -join "`n") + "`n", $enc)
    Write-Host ("已判定 {0} → {1}" -f $Verdict, $Result) -ForegroundColor Green
    if ($Evid) { Write-Host ("  证据：{0}" -f $Evid) }
    return
}

$all = Read-Preds
$now = Get-Date
$dueList = @($all | Where-Object { $_.result -eq '未判' -and $_.by -and ([datetime]::Parse($_.by) -lt $now) })

if ($Due) {
    if ($dueList.Count -eq 0) { Write-Host '没有到期待判的预测' -ForegroundColor Green; exit 0 }
    foreach ($d in $dueList) { Write-Host ("[逾期] {0}  {1}  （截止 {2}）" -f $d.id, $d.claim, $d.by) -ForegroundColor Yellow }
    exit 0
}

if ($List -or (-not $Due)) {
    if ($all.Count -eq 0) { Write-Host '还没有任何预测（这就是「没让他保证」）' -ForegroundColor Yellow; exit 0 }
    foreach ($d in $all) {
        $flag = if ($d.result -eq '未判') { '未判' } else { $d.result }
        Write-Host ("{0,-14} {1,-4} 截止 {2,-16} {3}" -f $d.id, $flag, $d.by, $d.claim)
    }
    exit 0
}
