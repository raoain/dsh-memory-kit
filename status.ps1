# status.ps1 — 自己的号每日快照
# 用法： .\status.ps1        抓一次并存档
#        .\status.ps1 -Diff  和上一份比，输出播放增量
param([switch]$Diff)

$ErrorActionPreference = 'Continue'
$env:BILI_CLI_HOME = 'F:\Tools\bili-cli'
$BILI = 'F:\Tools\uv\bin\bili.exe'
. (Join-Path $PSScriptRoot '_root.ps1')
$OwnDir = Join-Path $Track 'own'
New-Item -ItemType Directory -Force -Path $OwnDir | Out-Null

# 1) 账号
$u = (& $BILI user info 504093562 2>&1 | Out-String) | ConvertFrom-Json
if ($u.ok) {
    Write-Host ("账号：{0}   粉丝 {1}   关注 {2}   总播放 {3}" -f `
        $u.data.name, $u.data.fans, $u.data.following, $u.data.total_views) -ForegroundColor Cyan
}

# 2) 稿件（upload list 自带 stat，不用逐条查详情）
$list = (& $BILI upload list 2>&1 | Out-String) | ConvertFrom-Json
$rows = @()
if ($list.ok) {
    foreach ($v in @($list.data.items)) {
        $rows += [pscustomobject]@{
            bvid  = $v.bvid
            title = $v.title
            state = $v.state_desc
            pub   = if ($v.publish_time) { $v.publish_time.Substring(5,11) } else { '' }
            play  = [double]$v.stat.view
            like  = [double]$v.stat.like
            reply = [double]$v.stat.reply
            coin  = [double]$v.stat.coin
            fav   = [double]$v.stat.favorite
        }
    }
}

$rows | Sort-Object play -Descending | ForEach-Object {
    [pscustomobject]@{
        BV   = $_.bvid
        状态 = $_.state
        发布 = $_.pub
        播放 = $_.play
        赞   = $_.like
        评   = $_.reply
        币   = $_.coin
    }
} | Format-Table -AutoSize | Out-String -Width 200 | Write-Host

$stamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
$file = Join-Path $OwnDir "$stamp.json"
[IO.File]::WriteAllText($file, ($rows | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("快照: {0}" -f $file) -ForegroundColor DarkGray

if ($Diff) {
    $prev = Get-ChildItem "$OwnDir\*.json" | Where-Object { $_.Name -ne "$stamp.json" } |
            Sort-Object Name -Descending | Select-Object -First 1
    if (-not $prev) { Write-Host '没有上一份快照'; return }
    $old = Get-Content $prev.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    $map = @{}
    foreach ($o in $old) { $map[$o.bvid] = [double]$o.play }
    Write-Host ("对比基准: {0}" -f $prev.Name) -ForegroundColor DarkGray
    foreach ($r in $rows) {
        if ($map.ContainsKey($r.bvid)) {
            $d = $r.play - $map[$r.bvid]
            if ($d -gt 0) { Write-Host ("  +{0,6:N0}  {1}  {2}" -f $d, $r.bvid, $r.title) }
        } else {
            Write-Host ("  NEW      {0}  {1}" -f $r.bvid, $r.title)
        }
    }
}
# machine-readable exit (adapter reads only this line): state 0 pass / 1 warn / 2 fail / 3 unknown
$sigState = 0
if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) { $sigState = 2 }
if ($sigState -eq 0 -and (Get-Variable -Name 'Failed' -ErrorAction SilentlyContinue) -and $Failed) { $sigState = 2 }
Write-Output ("SIG " + (@{ state = $sigState; counts = @($sigState) } | ConvertTo-Json -Compress))
