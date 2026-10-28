# attrib.ps1 — 归因检查：凡写「用户说 / 他要求 / 原话」的句子，必须带得出来的原话
#
# 为什么：2026-10-29 发现「20 天」在推理里被标成 "from user's statements" —— 伪造来源。
# 幻觉最毒的地方不是错，是它自带一个假出处；来源一假，所有判据都失效。
#
# 用法：
#   .\attrib.ps1                 # 扫 notebook + heybox 的 md
#   .\attrib.ps1 -Path F:\x      # 扫指定目录
#   .\attrib.ps1 -Quiet          # 只在有问题时输出
param(
    [string[]]$Path = @('F:\Tools\coo-day1\notebook'),   # ← 改成你自己的目录
    [switch]$Quiet
)

$ErrorActionPreference = 'Continue'

# 归因词：出现这些词就是在声称「这话有来源」
$attribWords = '用户说|他说过|他要求|她的原话|原话是|来自他的话|用户原话|船长的原话|用户的要求是|用户的偏好是'
# 有引号 = 引了原话；有「来源」字样 = 标了出处
$quoteMark = '[「『“"]|来源[:：]|（原话）|\(原话\)'

$issues = @()
$scanned = 0

foreach ($dir in $Path) {
    if (-not (Test-Path $dir)) { continue }
    $files = Get-ChildItem $dir -Filter '*.md' -File -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        $scanned++
        $lines = [IO.File]::ReadAllLines($f.FullName, [Text.Encoding]::UTF8)
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $ln = $lines[$i]
            if ($ln -match '^\s*[#>]') { continue }          # 标题/引用块跳过
            if ($ln -notmatch $attribWords) { continue }
            if ($ln -match $quoteMark) { continue }          # 有引号或标了来源 → 合格
            $issues += [pscustomobject]@{
                File   = $f.Name
                Line   = $i + 1
                Text   = $ln.Trim().Substring(0, [Math]::Min(80, $ln.Trim().Length))
                Reason = '归因无引文'
            }
        }
    }
}

if (-not $Quiet -or $issues.Count -gt 0) {
    if ($issues.Count -eq 0) {
        Write-Host ("attrib: 扫 $scanned 个 md，没有「说了来源却引不出原文」的句子") -ForegroundColor Green
    } else {
        $issues | ForEach-Object {
            Write-Host ("{0}:{1}  {2}" -f $_.File, $_.Line, $_.Text) -ForegroundColor Yellow
        }
        Write-Host ("`nattrib: $($issues.Count) 处归因无引文（要么补原话，要么删掉归因）") -ForegroundColor Yellow
    }
}

if ($issues.Count -gt 0) { exit 1 } else { exit 0 }
