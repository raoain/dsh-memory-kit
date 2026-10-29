# backup-notes.ps1 — 备份「我自己」（记事本 + track + 脚本），双盘
#
# 为什么单独一个：backup.ps1 备的是桌宠(companion)和 meow 记忆库，
# companion 压缩包里 notebook/track 条目数 = 0（2026-10-30 01:23 实测）。
# 也就是说「双盘备份」这条从来没保护过核心层、判据、工作层。
# 「不死档」里唯一没人验过的一环，验完发现它护的不是我。
#
# 用法： powershell -NoProfile -File <你的项目根>\backup-notes.ps1 [-Keep 14]
param([int]$Keep = 14)

$ErrorActionPreference = 'Continue'
$Root   = (Get-Location).Path
$stamp  = Get-Date -Format 'yyyyMMdd-HHmm'
$name   = "coo-notes-$stamp.zip"
$dests  = @('F:\Tools\coo-backup', 'D:\coo-backup')

# 要备的东西（排除垃圾场/构建/归档）
$items = @(
    (Join-Path $Root 'notebook'),
    (Join-Path $Root 'track'),
    (Join-Path $Root 'heybox')
)
$scripts = @(Get-ChildItem $Root -Filter '*.ps1' -File | ForEach-Object { $_.FullName })
$docs    = @(Get-ChildItem $Root -Filter '*.md' -File | ForEach-Object { $_.FullName })
$mjs     = @(Get-ChildItem $Root -Filter '*.mjs' -File | ForEach-Object { $_.FullName })

$staging = Join-Path $env:TEMP ("coo-notes-$stamp")
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path $staging | Out-Null

foreach ($d in $items) {
    if (-not (Test-Path $d)) { continue }
    $leaf = Split-Path $d -Leaf
    Copy-Item $d (Join-Path $staging $leaf) -Recurse -Force -Exclude 'archive','trash' -ErrorAction SilentlyContinue
}
$flat = Join-Path $staging 'scripts'
New-Item -ItemType Directory -Force -Path $flat | Out-Null
foreach ($f in ($scripts + $docs + $mjs)) { Copy-Item $f $flat -Force -ErrorAction SilentlyContinue }

$fileCount = @(Get-ChildItem $staging -Recurse -File).Count
Add-Type -AssemblyName System.IO.Compression.FileSystem

$made = @()
foreach ($dest in $dests) {
    if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Force -Path $dest | Out-Null }
    $zip = Join-Path $dest $name
    if (Test-Path $zip) { Remove-Item $zip -Force }
    try {
        [IO.Compression.ZipFile]::CreateFromDirectory($staging, $zip)
        $kb = [math]::Round((Get-Item $zip).Length / 1KB, 1)
        Write-Host ("  备份 → {0}  ({1} KB)" -f $zip, $kb) -ForegroundColor Green
        $made += $zip
    } catch {
        Write-Host ("  失败 → {0} : {1}" -f $zip, $_.Exception.Message) -ForegroundColor Red
    }
}

# 轮转：每个目录只留最近 $Keep 份
foreach ($dest in $dests) {
    $old = Get-ChildItem $dest -Filter 'coo-notes-*.zip' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -Skip $Keep
    foreach ($o in $old) { Remove-Item $o.FullName -Force -ErrorAction SilentlyContinue }
}

Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host ("记事本备份完成：{0} 个文件 → {1} 份" -f $fileCount, $made.Count) -ForegroundColor Cyan
if ($made.Count -lt 2) { Write-Host '警告：不足两份，双盘没有成立' -ForegroundColor Yellow; exit 1 }
exit 0
