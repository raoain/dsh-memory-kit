# sticky.ps1 — 便签：收工三行（刚聊到哪 / 答应了什么 / 下次接着说什么）
#
# 为什么：便签一直只是「口头规矩」，工作层还是流水账。
# 现在做成机制：覆盖式写固定区块，旧便签自动归档到 archive\便签-YYYY-MM.md。
#
# 用法：
#   .\sticky.ps1 -Where "在改 work-shrink.ps1" -Promise "明天给 AGENTS 瘦身" -Next "开工先跑 wake + pin"
#   .\sticky.ps1 -Show          # 只看当前便签
param(
    [string]$Where,
    [string]$Promise,
    [string]$Next,
    [switch]$Show,
    [string]$Root = $Notebook
)
. (Join-Path $PSScriptRoot '_root.ps1')

$ErrorActionPreference = 'Stop'
$work = Join-Path $Root '1-工作.md'
$archDir = Join-Path $Root 'archive'
if (-not (Test-Path $work)) { throw "找不到工作层: $work" }

$lines = [IO.File]::ReadAllLines($work, [Text.Encoding]::UTF8)
$startTag = '<!-- sticky:start -->'
$endTag   = '<!-- sticky:end -->'
$si = -1; $ei = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].Trim() -eq $startTag) { $si = $i }
    if ($lines[$i].Trim() -eq $endTag) { $ei = $i; break }
}

function Render($w, $p, $n) {
    @(
        '<!-- sticky:start -->',
        '## 便签',
        '',
        ("**刚聊到哪**：{0}" -f $(if ($w) { $w } else { '—' })),
        ("**答应了什么**：{0}" -f $(if ($p) { $p } else { '—' })),
        ("**下次接着说什么**：{0}" -f $(if ($n) { $n } else { '—' })),
        '',
        ('_更新：{0}_' -f (Get-Date -Format 'yyyy-MM-dd HH:mm')),
        '<!-- sticky:end -->'
    )
}

if ($Show) {
    if ($si -ge 0 -and $ei -gt $si) { $lines[$si..$ei] | ForEach-Object { Write-Host $_ } }
    else { Write-Host '还没有便签（跑一次 -Where/-Promise/-Next）' -ForegroundColor Yellow }
    return
}

if (-not $Where -and -not $Promise -and -not $Next) {
    throw '需要 -Where / -Promise / -Next 至少一个（或用 -Show 查看）'
}

# 旧便签归档
if ($si -ge 0 -and $ei -gt $si) {
    $old = $lines[($si + 1)..($ei - 1)] -join "`n"
    if ($old.Trim()) {
        New-Item -ItemType Directory -Force -Path $archDir | Out-Null
        $af = Join-Path $archDir ('便签-{0}.md' -f (Get-Date -Format 'yyyy-MM'))
        $entry = "`n### " + (Get-Date -Format 'yyyy-MM-dd HH:mm') + "`n" + $old.Trim() + "`n"
        [IO.File]::AppendAllText($af, $entry, (New-Object Text.UTF8Encoding($false)))
    }
}

$block = Render $Where $Promise $Next

if ($si -ge 0 -and $ei -gt $si) {
    $before = if ($si -gt 0) { $lines[0..($si - 1)] } else { @() }
    $after  = if ($ei + 1 -lt $lines.Count) { $lines[($ei + 1)..($lines.Count - 1)] } else { @() }
    $new = @($before) + $block + @($after)
} else {
    # 没有便签块：插在标题后的第一段
    $insertAt = 0
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^# ') { $insertAt = $i + 1; break } }
    $new = @($lines[0..$insertAt]) + @('') + $block + @('') + @($lines[($insertAt + 1)..($lines.Count - 1)])
}

[IO.File]::WriteAllText($work, (($new -join "`n").TrimEnd()) + "`n", (New-Object Text.UTF8Encoding($true)))
Write-Host '便签已更新（旧条已归档）' -ForegroundColor Green
