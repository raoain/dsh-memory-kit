# enable-cua.ps1
# 用法：见本文件末尾或 README.md —— 无参数直接跑；参数见下方 param 块
# enable-cua.ps1 — 等 Coopanion 的 WebUI 起来后，用接口启用 cua
# 原因：cua 的 world id 是空字符串，启动时配置对不上，所以每次启动后要手动启用一次。
param([int]$TimeoutSec = 90)

$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '_root.ps1')
$port = 17788
$deadline = (Get-Date).AddSeconds($TimeoutSec)
$ok = $false

while ((Get-Date) -lt $deadline) {
    $r = & curl.exe -sS -o NUL -w "%{http_code}" --max-time 3 "http://127.0.0.1:$port/" 2>$null
    if ($r -eq '200') { $ok = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $ok) { exit 1 }

$tmp = Join-Path $env:TEMP 'cua-activation.json'
[IO.File]::WriteAllText($tmp, '{"id":"cua","enabled":true}', (New-Object System.Text.ASCIIEncoding))
$resp = & curl.exe -sS --max-time 20 -X POST "http://127.0.0.1:$port/api/worlds/activation" `
    -H "Content-Type: application/json" --data-binary "@$tmp" 2>$null

$log = (Join-Path $Track 'cua-enable.log')
$line = ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), ($resp -join ' '))
Add-Content -Path $log -Value $line -Encoding UTF8
