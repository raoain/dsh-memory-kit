# fix-bom.ps1 — 给缺 BOM 的 .ps1 补回 UTF-8 BOM
#
# 为什么：edit/write 改文件会吃掉 BOM，而 PS 5.1 对无 BOM 的 UTF-8 默认按 GBK 解，
# 中文变乱码、语法直接报 ParserError。与其每次记住「改完手动补」，不如让命令扫一遍。
#
# 用法：
#   .\fix-bom.ps1              # 扫本项目根（不递归）
#   .\fix-bom.ps1 -Recurse     # 递归子目录
#   .\fix-bom.ps1 -DryRun      # 只看会补哪些
#   .\fix-bom.ps1 -Root D:\tmp # 指定别的目录（拿副本试刀时用）
param(
    [switch]$Recurse,
    [switch]$DryRun,
    [string]$Root = ((Split-Path $PSScriptRoot -Parent))
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Root)) { throw "找不到目录: $Root" }

$files = if ($Recurse) { Get-ChildItem $Root -Filter '*.ps1' -File -Recurse } else { Get-ChildItem $Root -Filter '*.ps1' -File }
$fixed = 0; $ok = 0; $bad = @()
foreach ($f in $files) {
    $bytes = [IO.File]::ReadAllBytes($f.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $ok++; continue }

    # 先确认字节是合法 UTF-8 再补；是 GBK 的话补 BOM 只会更乱，跳过并报出来
    try {
        $dec = [Text.Encoding]::GetEncoding('utf-8',
            [Text.EncoderFallback]::ExceptionFallback,
            [Text.DecoderFallback]::ExceptionFallback)
        $null = $dec.GetString($bytes)
    } catch {
        $bad += $f.Name
        continue
    }

    if (-not $DryRun) {
        $text = [Text.Encoding]::UTF8.GetString($bytes)
        [IO.File]::WriteAllBytes($f.FullName, (New-Object Text.UTF8Encoding($true)).GetPreamble() + [Text.Encoding]::UTF8.GetBytes($text))
        Write-Host ("补 BOM: " + $f.Name) -ForegroundColor Yellow
    }
    $fixed++
}

$tail = if ($DryRun) { '（dry-run，未写文件）' } else { '' }
Write-Host ("扫描 {0} 个 .ps1：已带 BOM {1} / 补上 {2} / 非 UTF-8 跳过 {3} {4}" -f $files.Count, $ok, $fixed, $bad.Count, $tail) -ForegroundColor Green
if ($bad.Count -gt 0) { Write-Host ("非 UTF-8，没动：" + ($bad -join ', ')) -ForegroundColor Red; exit 1 }