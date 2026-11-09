# track.ps1 — 同类账号追踪
# 按账号抓最近投稿，存快照，便于隔天对比。
# 用法： .\track.ps1            （抓一次，写 snapshots\yyyy-MM-dd.json）
#        .\track.ps1 -Diff      （与上一份快照对比，输出播放增量）
param([switch]$Diff)

$ErrorActionPreference = 'Continue'
$env:BILI_CLI_HOME = 'F:\Tools\bili-cli'
$BILI = 'F:\Tools\uv\bin\bili.exe'
. (Join-Path $PSScriptRoot '_root.ps1')
New-Item -ItemType Directory -Force -Path "$Track\snapshots" | Out-Null

$accounts = @(
    @{ mid = 630922438;           name = '小肥鱼在打工' },
    @{ mid = 1974177535;          name = '大肥鱼今天打工' },
    @{ mid = 3546663962544716;    name = '鲸鱼惠大肥鱼' },
    @{ mid = 3546723840429018;    name = 'DeepSeek鲸鱼娘本人' },
    @{ mid = 1946000628;          name = '祥子的哦鲸鲸' },
    @{ mid = 1066381591;          name = '小小鲸运营日记' },
    @{ mid = 94782782;            name = '酷可mc' },
    @{ mid = 570592;              name = '真誠最高' },
    @{ mid = 522322575;           name = '点燃篝火的Anrry' },
    @{ mid = 3747573030456892;    name = 'DeepSeek鲸鱼娘在运营' },
    @{ mid = 387076073;           name = '超金属爆裂' },
    @{ mid = 30584746;            name = '星落落_oi' }
)

$rows = @()
foreach ($a in $accounts) {
    $raw = & $BILI user videos $a.mid 2>&1 | Out-String
    try { $j = $raw | ConvertFrom-Json } catch { continue }
    if (-not $j.ok) { Write-Host ("跳过 {0}: {1}" -f $a.name, $j.error.message); continue }
    $items = @($j.data.items) | Sort-Object pubdate -Descending | Select-Object -First 5
    foreach ($v in $items) {
        $rows += [pscustomobject]@{
            account = $a.name
            mid     = $a.mid
            bvid    = $v.bvid
            title   = $v.title
            play    = $v.play
            like    = $v.like
            length  = $v.length
            pubdate = $v.pubdate
        }
    }
    Write-Host ("{0}: {1} 条" -f $a.name, $items.Count)
    Start-Sleep -Milliseconds 300
}

$stamp = Get-Date -Format 'yyyy-MM-dd'
$file = Join-Path $Track "snapshots\$stamp.json"
[IO.File]::WriteAllText($file, ($rows | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("快照: {0}  ({1} 条)" -f $file, $rows.Count) -ForegroundColor Green

if ($Diff) {
    $prev = Get-ChildItem "$Track\snapshots\*.json" | Where-Object { $_.Name -ne "$stamp.json" } |
            Sort-Object Name -Descending | Select-Object -First 1
    if (-not $prev) { Write-Host '没有上一份快照，无法对比'; return }
    $old = Get-Content $prev.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    $map = @{}
    foreach ($o in $old) { $map[$o.bvid] = [double]$o.play }
    Write-Host ("对比基准: {0}" -f $prev.Name)
    foreach ($r in $rows) {
        if ($map.ContainsKey($r.bvid)) {
            $delta = [double]$r.play - $map[$r.bvid]
            if ($delta -gt 0) { Write-Host ("  +{0,7:N0}  {1}  {2}" -f $delta, $r.account, $r.title) }
        } else {
            Write-Host ("  NEW       {0}  {1}" -f $r.account, $r.title)
        }
    }
}
