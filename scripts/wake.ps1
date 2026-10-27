# wake.ps1 — 开工第一步：读核心层，并留一个可核对的时间戳
#
# 为什么留痕：只写「每次必读」是空话。时间戳能被 selfcheck.ps1 查出来，
# 跳过这一步就会露馅。
#
# 用法： powershell -NoProfile -File .\wake.ps1

# ===== 配置区（改成你自己的） =====
$CoreFile = 'F:\Tools\coo-day1\notebook\0-核心.md'   # 每次必读的那页
$WorkFile = 'F:\Tools\coo-day1\notebook\1-工作.md'   # 在做什么，取最近几行
$WorkTail = 12                                        # 工作层显示行数
$MarkFile = 'F:\Tools\coo-day1\track\wake-last.txt'  # 时间戳落点（selfcheck 读它）
# =================================

$ErrorActionPreference = 'Continue'

if (-not (Test-Path $CoreFile)) { Write-Host "找不到核心层: $CoreFile" -ForegroundColor Red; exit 1 }

Get-Content $CoreFile -Encoding UTF8
if ($WorkFile -and (Test-Path $WorkFile)) {
    Write-Host "`n--- 工作层（最近 $WorkTail 行）---" -ForegroundColor DarkGray
    Get-Content $WorkFile -Encoding UTF8 -Tail $WorkTail
}

New-Item -ItemType Directory -Force -Path (Split-Path $MarkFile) | Out-Null
('{0}  读过 {1}（{2} B）' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), (Split-Path $CoreFile -Leaf), (Get-Item $CoreFile).Length) |
    Set-Content $MarkFile -Encoding UTF8
