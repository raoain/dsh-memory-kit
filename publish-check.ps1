param(
  [Parameter(Mandatory=$true)][string]$Path
)
# 发布前自检：对外体例不合规的痕迹，一律拦下
. (Join-Path $PSScriptRoot '_root.ps1')
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Path)) { Write-Host "FAIL 文件不存在: $Path"; exit 2 }
$lines = @(Get-Content $Path -Encoding UTF8)
$bad = @()
$rules = @(
  @{ name='待填';        pat='待填' },
  @{ name='摘要进正文';  pat='^##\s*摘要|^\*\*摘要\*\*' },
  @{ name='自证标记';    pat='\[读自' },
  @{ name='草稿字样';    pat='草稿' },
  @{ name='arXiv编号';   pat='\b\d{4}\.\d{4,5}\b' },
  @{ name='TODO/待做';   pat='TODO|待做|下一版' },
  @{ name='断号小节';    pat='^###\s*\d+\.\d+\s' }
)
for ($i=0; $i -lt $lines.Count; $i++) {
  foreach ($r in $rules) {
    if ($lines[$i] -match $r.pat) { $bad += ("{0} 行{1}: {2}" -f $r.name, ($i+1), $lines[$i].Trim()) }
  }
}
Write-Host ("文件: {0} / {1} 行 / {2} 字节" -f (Split-Path $Path -Leaf), $lines.Count, (Get-Item $Path).Length)
if ($bad.Count -eq 0) {
  Write-Host "PASS 未发现对外体例违规痕迹"
  exit 0
}
Write-Host ("FAIL {0} 处：" -f $bad.Count)
$bad | ForEach-Object { Write-Host ("  - " + $_) }
exit 2
