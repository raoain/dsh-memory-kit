# meow-toggle.ps1 — 记忆插件的开关（为「拔插件 24 小时」实验准备）
#
# 为什么：要验「少了插件我会不会死」，就得能安全地关掉、再安全地打开。
# 改的是 profile 的 cordis.patch.yml，每次改前自动备份到 track\。
#
# 用法：
#   .\meow-toggle.ps1 -Status   # 看当前状态（默认动作）
#   .\meow-toggle.ps1 -Off      # 关闭 meow-memory（改 yml + 提示如何立即生效）
#   .\meow-toggle.ps1 -On       # 从最近备份恢复
#   .\meow-toggle.ps1 -List     # 列出所有备份
param(
    [switch]$Status,
    [switch]$Off,
    [switch]$On,
    [switch]$List
)
. (Join-Path $PSScriptRoot '_root.ps1')

$ErrorActionPreference = 'Stop'
$prof = Join-Path $env:USERPROFILE '.dsh\profiles\desktop'
$yml  = Join-Path $prof 'cordis.patch.yml'
$track = $Track
if (-not (Test-Path $yml)) { throw "找不到 profile 配置: $yml" }
New-Item -ItemType Directory -Force -Path $track | Out-Null

function Read-Yml { [IO.File]::ReadAllText($yml, [Text.Encoding]::UTF8) }

function Save-Yml($text) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $bak = Join-Path $track "profile-patch-$stamp.yml"
    Copy-Item $yml $bak -Force
    [IO.File]::WriteAllText($yml, $text, (New-Object Text.UTF8Encoding($false)))
    Write-Host ("已备份: " + $bak) -ForegroundColor DarkGray
}

# 在「- id: meow-memory」这一块里，把 disabled 设成目标值
function Set-MeowDisabled($want) {
    $lines = (Read-Yml) -split "`r?`n"
    $inBlock = $false
    $done = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^-\s*id:\s*meow-memory\s*$') { $inBlock = $true; continue }
        if ($inBlock) {
            if ($lines[$i] -match '^-\s*id:') { break }   # 进入下一个插件块
            if ($lines[$i] -match '^\s*disabled:\s*(true|false)\s*$') {
                $lines[$i] = '  disabled: ' + $want
                $done = $true
                break
            }
        }
    }
    if (-not $done) { throw "在 meow-memory 块里没找到 disabled 行" }
    return ($lines -join "`r`n")
}

function Get-MeowDisabled {
    $lines = (Read-Yml) -split "`r?`n"
    $inBlock = $false
    foreach ($ln in $lines) {
        if ($ln -match '^-\s*id:\s*meow-memory\s*$') { $inBlock = $true; continue }
        if ($inBlock) {
            if ($ln -match '^-\s*id:') { break }
            if ($ln -match '^\s*disabled:\s*(true|false)\s*$') { return $Matches[1] }
        }
    }
    return 'unknown'
}

if ($List) {
    Get-ChildItem $track -Filter 'profile-patch-*.yml' | Sort-Object Name -Descending | Select-Object -First 10 |
        ForEach-Object { "  " + $_.Name + "  (" + $_.Length + " B, " + $_.LastWriteTime.ToString('MM-dd HH:mm') + ")" }
    return
}

if ($Off) {
    $t = Set-MeowDisabled 'true'
    Save-Yml $t
    Write-Host "meow-memory 已标记 disabled: true" -ForegroundColor Yellow
    Write-Host "让它立即生效（二选一）：" -ForegroundColor Cyan
    Write-Host "  plugin_manager set_plugin target=include:meow-memory enabled=false" -ForegroundColor Gray
    Write-Host "  或重启 DSH" -ForegroundColor Gray
    return
}

if ($On) {
    # 只认「关之前自动存的那份」：排除 -before-restore / -prerestore，否则会把
    # 恢复动作自己存的改前副本当成目标，恢复个寂寞（2026-10-29 03:44 栽过）
    $latest = Get-ChildItem $track -Filter 'profile-patch-*.yml' |
        Where-Object { $_.Name -notlike '*-before-restore*' } |
        Sort-Object Name -Descending | Select-Object -First 1
    if (-not $latest) { throw "没有找到备份，无法恢复" }
    # 覆盖前先把当前状态另存（名字不进上面的筛选，避免下次又被当成目标）
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Copy-Item $yml (Join-Path $track "profile-prerestore-$stamp.yml") -Force
    Copy-Item $latest.FullName $yml -Force
    Write-Host ("已从备份恢复: " + $latest.Name) -ForegroundColor Green
    $now = Get-MeowDisabled
    if ($now -ne 'false') { throw "恢复后 disabled=$now，不是 false —— 备份 ($($latest.Name)) 本身可能就是关着的那份" }
    Write-Host "核对通过：disabled=false" -ForegroundColor Green
    Write-Host "让它立即生效：plugin_manager set_plugin target=include:meow-memory enabled=true" -ForegroundColor Cyan
    return
}

# 默认：状态
$dis = Get-MeowDisabled
$db = Join-Path $env:USERPROFILE 'Documents\deepseek-harness\default-workspace\.dsh-meow\memory.db'
$dbInfo = if (Test-Path $db) { "{0:N0} KB" -f ((Get-Item $db).Length / 1KB) } else { '不存在' }
$state = if ($dis -eq 'false') { '启用' } else { '禁用' }
Write-Host ("meow-memory: {0}（yml disabled={1}）" -f $state, $dis) -ForegroundColor $(if ($dis -eq 'false') { 'Green' } else { 'Yellow' })
Write-Host ("记忆库: " + $dbInfo) -ForegroundColor DarkGray
$n = (Get-ChildItem $track -Filter 'profile-patch-*.yml' | Measure-Object).Count
Write-Host ("备份: {0} 份（-List 看明细）" -f $n) -ForegroundColor DarkGray
