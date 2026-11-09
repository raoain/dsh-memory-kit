# free-c.ps1
# 用法：见本文件末尾或 README.md —— 无参数直接跑；参数见下方 param 块
# free-c.ps1 — 腾 C 盘（需要管理员）
# 做三件事：关休眠、页面文件挪到 D 盘、清 NVIDIA 安装缓存
# 契约 call（2026-11-08）：输入一律在 param 里声明，没有输入也要声明空块
param()
. (Join-Path $PSScriptRoot '_root.ps1')
$ErrorActionPreference = 'Continue'

function Head($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
$before = (Get-PSDrive C).Free

Head '1. 关休眠（释放 hiberfil.sys）'
& powercfg.exe /h off 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Host '  已关闭休眠' -ForegroundColor Green } else { Write-Host '  失败（可能被策略锁）' -ForegroundColor Yellow }

Head '2. 页面文件挪到 D 盘'
$cs = Get-CimInstance Win32_ComputerSystem
if ($cs.AutomaticManagedPagefile) {
    Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $false } -ErrorAction SilentlyContinue
    Write-Host '  已关闭「自动管理页面文件」'
}
$reg = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
$cur = (Get-ItemProperty $reg -Name PagingFiles -ErrorAction SilentlyContinue).PagingFiles
Write-Host ("  当前: " + ($cur -join ' | '))
Set-ItemProperty $reg -Name PagingFiles -Value @('D:\pagefile.sys 8192 16384') -Type MultiString
Write-Host '  已设为 D:\pagefile.sys (8–16 GB)，重启后生效' -ForegroundColor Green

Head '3. 清 NVIDIA 安装缓存'
$nv = 0
foreach ($p in 'C:\ProgramData\NVIDIA Corporation\Downloader', 'C:\ProgramData\NVIDIA Corporation\Installer2', 'C:\ProgramData\NVIDIA') {
    if (Test-Path $p) {
        $s = (Get-ChildItem $p -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $p)) { $nv += $s; Write-Host ("  已删 {0}  ({1:N0} MB)" -f $p, ($s / 1MB)) }
        else { Write-Host ("  跳过 {0}（占用中）" -f $p) -ForegroundColor Yellow }
    }
}

$after = (Get-PSDrive C).Free
Head '结果'
Write-Host ("  本次释放: {0:N2} GB" -f (($after - $before) / 1GB)) -ForegroundColor Green
Write-Host ("  C 盘现在剩: {0:N2} GB" -f ($after / 1GB)) -ForegroundColor Green
Write-Host '  重启后会再释放约 7.5 GB（旧 pagefile 那时才删掉）' -ForegroundColor Yellow
Write-Host ''
Read-Host '按回车关闭'
