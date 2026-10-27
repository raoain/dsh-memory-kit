# backup.ps1 — 把助手的记忆打包，落到两块盘
# 用法： powershell -NoProfile -File .\backup.ps1
#        powershell -NoProfile -File .\backup.ps1 -Keep 14
param([int]$Keep = 7)

# ===== 配置区（改成你自己的） =====
$Source   = 'F:\新建文件夹 (2)\Coopanion\data\home\companion'   # 要备份的记忆目录
$DestA    = 'F:\Tools\coo-backup'                                # 第一块盘
$DestB    = 'D:\coo-backup'                                      # 第二块盘（留空则只备一份）
$Prefix   = 'companion'
$ExtraFiles = @()   # 额外的单文件，不属于上面目录但同样会丢，例如：
                    #   'C:\Users\你\...\memory.db'   检索库
                    #   'C:\Users\你\...\providers\deepseek\.env'   密钥（想清楚再放）
# =================================

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Source)) { throw "找不到记忆目录: $Source" }

$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$name  = "$Prefix-$stamp.zip"
New-Item -ItemType Directory -Force -Path $DestA | Out-Null
$zip = Join-Path $DestA $name

Compress-Archive -Path (Join-Path $Source '*') -DestinationPath $zip -CompressionLevel Optimal -Force

# 轮转
Get-ChildItem $DestA -Filter "$Prefix-*.zip" | Sort-Object LastWriteTime -Descending |
    Select-Object -Skip $Keep | ForEach-Object { Remove-Item $_.FullName -Force }

# 第二份
$msg = "备份: $zip"
if ($DestB) {
    New-Item -ItemType Directory -Force -Path $DestB | Out-Null
    Copy-Item $zip (Join-Path $DestB $name) -Force
    Get-ChildItem $DestB -Filter "$Prefix-*.zip" | Sort-Object LastWriteTime -Descending |
        Select-Object -Skip $Keep | ForEach-Object { Remove-Item $_.FullName -Force }
    $msg += " + " + (Join-Path $DestB $name)
}

# 额外的单文件：跟着同一套轮转，落两块盘
foreach ($ef in $ExtraFiles) {
    if (-not $ef) { continue }
    if (-not (Test-Path $ef)) { Write-Host "跳过（不存在）: $ef" -ForegroundColor Yellow; continue }
    $base = [IO.Path]::GetFileNameWithoutExtension($ef)
    $ext  = [IO.Path]::GetExtension($ef)
    $fn   = "$base-$stamp$ext"
    Copy-Item $ef (Join-Path $DestA $fn) -Force
    if ($DestB) { Copy-Item $ef (Join-Path $DestB $fn) -Force }
    foreach ($d in @($DestA, $DestB)) {
        if (-not $d) { continue }
        Get-ChildItem $d -Filter "$base-*$ext" | Sort-Object LastWriteTime -Descending |
            Select-Object -Skip $Keep | ForEach-Object { Remove-Item $_.FullName -Force }
    }
    Write-Host ("  附加: {0}" -f $fn) -ForegroundColor DarkGray
}

$size = (Get-Item $zip).Length / 1MB
Write-Host ("{0}  ({1:N1} MB, 各留 {2} 份)" -f $msg, $size, $Keep) -ForegroundColor Green
