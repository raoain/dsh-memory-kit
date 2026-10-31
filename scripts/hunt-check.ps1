# hunt-check.ps1 — 外部寻觅的准入门槛（机械校验，不看内容靠不靠谱，只看能不能打开）
#
# 为什么：靠"我自觉按格式写"没有保障。这里把门槛做成脚本——
#   候选清单每一行必须带 source（URL 或 本地 文件:行），source 打不开的直接判不合格。
# 用法：
#   .\hunt-check.ps1 -File track\寻觅-20261101.jsonl
#   .\hunt-check.ps1 -File <jsonl> -Strict     # 有不合格就 exit 1
#
# 候选行格式（jsonl，一行一条）：
#   {"claim":"一句话断言","source":"https://... 或 notebook\\0-核心.md:12","differ":"它和我们对不上的是什么"}
param(
    [Parameter(Mandatory = $true)][string]$File,
    [switch]$Strict
)

$ErrorActionPreference = 'Continue'
$Root = '<你的项目根>'
if (-not (Test-Path $File)) { Write-Host "找不到候选文件：$File" -ForegroundColor Red; exit 2 }

$ok = 0; $bad = 0; $noSrc = 0; $unreach = 0
$rows = @(Get-Content $File -Encoding UTF8 | Where-Object { $_.Trim() })
Write-Host ("  候选 {0} 条" -f $rows.Count)

foreach ($line in $rows) {
    $o = $null
    try { $o = $line | ConvertFrom-Json } catch { Write-Host "  ✘ JSON 坏了：$($line.Substring(0,[Math]::Min(40,$line.Length)))" -ForegroundColor Red; $bad++; continue }

    $claim = [string]$o.claim
    $src   = [string]$o.source
    if (-not $claim -or -not $src) {
        Write-Host ("  ✘ 缺字段（claim/source）：{0}" -f $claim.Substring(0,[Math]::Min(30,$claim.Length))) -ForegroundColor Red
        $noSrc++; $bad++; continue
    }

    $reachable = $false
    if ($src -match '^https?://') {
        try {
            $r = Invoke-WebRequest -Uri $src -Method Head -TimeoutSec 12 -UseBasicParsing -ErrorAction Stop
            $reachable = ($r.StatusCode -ge 200 -and $r.StatusCode -lt 400)
        } catch {
            # HEAD 可能被拒，再试一次 GET 的首部
            try {
                $r2 = Invoke-WebRequest -Uri $src -Method Get -TimeoutSec 15 -UseBasicParsing -ErrorAction Stop
                $reachable = ($r2.StatusCode -ge 200 -and $r2.StatusCode -lt 400)
            } catch { $reachable = $false }
        }
    } elseif ($src -match '^(.+?)(?::(\d+))?$') {
        $p = $Matches[1]; $lnNo = $Matches[2]
        $full = if ([IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $Root $p }
        if (Test-Path $full) {
            if ($lnNo) {
                $n = @(Get-Content $full -Encoding UTF8).Count
                $reachable = ([int]$lnNo -ge 1 -and [int]$lnNo -le $n)
            } else { $reachable = $true }
        }
    }

    # 禁推理词：候选只能是"从出处抄来的断言"，不许自己接一环（因为/所以/由此可见…）
    $reasonWords = '因为|所以|由此可见|因此|这说明|这意味着|综上'
    $hasReason = ($claim -match $reasonWords)
    if ($hasReason) {
        $bad++; $unreach++
        Write-Host ("  ✘ 含推理词（补链失败）  {0}" -f $claim.Substring(0,[Math]::Min(34,$claim.Length))) -ForegroundColor Yellow
        continue
    }

    if ($reachable) {
        $ok++
        Write-Host ("  ✔ 可打开  {0}  ← {1}" -f $claim.Substring(0,[Math]::Min(34,$claim.Length)), $src.Substring(0,[Math]::Min(50,$src.Length))) -ForegroundColor Green
    } else {
        $unreach++; $bad++
        Write-Host ("  ✘ 打不开  {0}  ← {1}" -f $claim.Substring(0,[Math]::Min(34,$claim.Length)), $src.Substring(0,[Math]::Min(50,$src.Length))) -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host ("  合格 {0} ／ 不合格 {1}（缺出处 {2}，打不开 {3}）" -f $ok, $bad, $noSrc, $unreach)
Write-Host '  判据：只有"可打开"的条目才允许进收敛或改文件；不合格的留在草稿里，不许被采纳。'
if ($Strict -and $bad -gt 0) { exit 1 } else { exit 0 }
