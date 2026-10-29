# core-snapshot.ps1 — 核心层版本链
#
# 为什么：核心层被改过，但没有「从哪一版长到哪一版」的证据。
# 只靠 rules-log 能证明「改过」，证明不了「同一个我只是一直在修订」。
#
# 用法：
#   .\core-snapshot.ps1 -Why "把本机陷阱移进 4-本机，核心只答我是谁"
#   内容与当前 0-核心.md 完全相同的快照会被跳过（按 sha256 判断）。
param(
    [Parameter(Mandatory = $true)][string]$Why
)

$Root   = (Get-Location).Path   # ← 改成你的项目根
$core   = Join-Path $Root 'notebook\0-核心.md'
$arch   = Join-Path $Root 'notebook\archive'
$enc    = New-Object Text.UTF8Encoding($false)

if (-not (Test-Path $core)) { Write-Host '找不到 0-核心.md' -ForegroundColor Red; exit 1 }
if (-not (Test-Path $arch)) { New-Item -ItemType Directory -Path $arch -Force | Out-Null }

$bytes = [IO.File]::ReadAllBytes($core)
$text  = [Text.Encoding]::UTF8.GetString($bytes)
if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
$sha   = (Get-FileHash $core -Algorithm SHA256).Hash
$short = $sha.Substring(0, 16)
$size  = $bytes.Length

# 已有快照（按 sha 去重）
$existing = Get-ChildItem $arch -Filter '0-核心-v*.md' -ErrorAction SilentlyContinue
foreach ($f in $existing) {
    $first = (Get-Content $f.FullName -Encoding UTF8 -TotalCount 6) -join "`n"
    if ($first -match [regex]::Escape($short)) {
        Write-Host ("跳过：已有相同内容快照 {0}" -f $f.Name) -ForegroundColor Yellow
        exit 0
    }
}

# 版本号 = 现有最大 vN + 1
$maxV = 0
foreach ($f in $existing) {
    $m = [regex]::Match($f.Name, '0-核心-v(\d+)-')
    if ($m.Success -and [int]$m.Groups[1].Value -gt $maxV) { $maxV = [int]$m.Groups[1].Value }
}
$v = $maxV + 1
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$name  = "0-核心-v{0}-{1}.md" -f $v, $stamp
$path  = Join-Path $arch $name

$head = @"
<!-- 核心层快照 V$v
     时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm')
     大小：$size B
     sha256：$short
     为什么改：$Why
     说明：本文件是 0-核心.md 的逐字副本，只多这一段注释。 -->
"@

[IO.File]::WriteAllText($path, $head + "`r`n" + $text, $enc)

Write-Host ("已建 V{0}：{1}" -f $v, $name) -ForegroundColor Green
Write-Host ("  大小 {0} B，sha {1}" -f $size, $short)
Write-Host ("  为什么改：{0}" -f $Why)
Write-Host ("  版本总数：{0}" -f ($maxV + 1))
