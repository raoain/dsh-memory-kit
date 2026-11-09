# snap.ps1 — 每次改完留一个版本点，失败了能翻回来
#
# 为什么要有它（2026-11-08）：drift.mjs 一天写了三版（瞬时 → 窗口 → 窗口+阈值），
# 每版整文件覆盖，前两版的错误只留在工作层几句话里，回不去。备份（zip / trash）不是
# 版本历史：它只能回到「某个 zip 的时刻」，不能回到「第 47 行那版」。
#
# 判据：「改了很多」和「留下了可回退的历史」是两件事。
#
# 用法：
#   .\snap.ps1 -Why "加了比较环的阈值"     留一个版本点
#   .\snap.ps1 -Log                       看最近 10 个版本点
#   .\snap.ps1 -Back -Steps 1             回到上一个版本点（工作区也一起回）
#
# 只提交，不推远端。总线/引脚/备份/垃圾场按 .gitignore 排除——版本历史记的是代码与文档。

param(
    [string]$Why,
    [switch]$Log,
    [switch]$Back,
    [int]$Steps = 1
)

. (Join-Path $PSScriptRoot '_root.ps1')
$ErrorActionPreference = 'Stop'
$git = 'F:\Tools\git\cmd\git.exe'
if (-not (Test-Path $git)) {
    $c = Get-Command git -ErrorAction SilentlyContinue
    if (-not $c) { Write-Host "找不到 git" -ForegroundColor Red; exit 2 }
    $git = $c.Source
}

if ($Log) {
    & $git -C $Root log --oneline -10
    exit 0
}

if ($Back) {
    $target = "HEAD~$Steps"
    Write-Host "回到 $target：" -ForegroundColor Yellow
    & $git -C $Root log --oneline -1 $target
    & $git -C $Root reset --hard $target
    Write-Host "已回退（工作区也回到那个点）" -ForegroundColor Green
    exit 0
}

if (-not $Why) {
    Write-Host "要留版本点必须说清为什么：.\snap.ps1 -Why ""改了什么""" -ForegroundColor Yellow
    exit 1
}

# 原生命令的 stderr（git 的 CRLF 警告）会被 $ErrorActionPreference=Stop 当成致命错误，
# 所以从这里到下面对 git 的调用全部改用 Continue——文件操作仍然 Stop。
$ErrorActionPreference = 'Continue'
& $git -C $Root add -A 2>&1 | Out-Null
$changed = (@(& $git -C $Root diff --cached --name-only 2>&1) | Measure-Object).Count
if ($changed -eq 0) {
    Write-Host "没有改动，不建空版本点" -ForegroundColor DarkGray
    exit 0
}
$msg = "$(Get-Date -Format 'yyyy-MM-dd HH:mm') $Why"
& $git -C $Root -c user.name=shoulian -c user.email=shoulian@local commit -q -m $msg 2>&1 | Out-Null
$sha = (@(& $git -C $Root rev-parse --short HEAD 2>&1))[0]
Write-Host ("版本点 {0}：{1} 个文件 —— {2}" -f $sha, $changed, $Why) -ForegroundColor Green
exit 0
