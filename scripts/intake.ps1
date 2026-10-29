# intake.ps1 — 入库前验一次来源（最小版）
#
# 为什么：幻觉的形态是「有一句话，但没人能打开它的出处」。
# 这个脚本唯一的职责就是：逼它打开。
#
# 用法：
#   .\intake.ps1 -Kind file -Claim "核心层 1794 字节" -Expect "1794" -Loc "notebook\0-核心.md"
#   .\intake.ps1 -Kind user -Claim "用户说过「随时记得保存」" -Expect "随时记得保存"
#
# 结果三选一：
#   PASS  来源找到，且包含所声称的内容     → 发 evid 令牌，允许入库
#   FAIL  来源找到，但内容不符             → 拒绝，并输出实际内容
#   NONE  来源不存在 / 打不开 / 日志里没有  → 降级为「不知道」或「估算」
#
# 注意：Kind=user 只搜会话日志里的 user/message 记录 —— 不搜我自己的话，
# 否则「我编一句用户说 X，再搜 X」会自我印证。
param(
    [Parameter(Mandatory = $true)][ValidateSet('file', 'user')][string]$Kind,
    [Parameter(Mandatory = $true)][string]$Claim,
    [Parameter(Mandatory = $true)][string]$Expect,
    [string]$Loc = '',
    [int]$MaxHits = 3
)

$Root = (Get-Location).Path   # ← 改成你的项目根
$Node = 'C:\Users\Administrator\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe'

function Fail($why, $actual = '') {
    Write-Host ''
    Write-Host ("NONE  {0}" -f $Claim) -ForegroundColor Yellow
    Write-Host ("      原因：{0}" -f $why)
    if ($actual) { Write-Host ("      实际：{0}" -f $actual) }
    exit 2
}

if ($Kind -eq 'file') {
    if (-not $Loc) { Fail 'Kind=file 必须给 -Loc（相对项目根的路径）' }
    $path = if ([IO.Path]::IsPathRooted($Loc)) { $Loc } else { Join-Path $Root $Loc }
    if (-not (Test-Path $path)) { Fail ("文件不存在：{0}" -f $path) }
    $text = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }

    if ($text.Contains($Expect)) {
        # 找出所在行，作为可复现指针
        $lines = $text -split "`r?`n"
        $hitLine = 0; $shown = ''
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i].Contains($Expect)) { $hitLine = $i + 1; $shown = $lines[$i].Trim(); break }
        }
        $sha = (Get-FileHash $path -Algorithm SHA256).Hash.Substring(0, 8)
        Write-Host ''
        Write-Host ("PASS  {0}" -f $Claim) -ForegroundColor Green
        Write-Host ("      evid:file:{0}:L{1}:{2}" -f (Split-Path $path -Leaf), $hitLine, $sha)
        Write-Host ("      原文：{0}" -f $shown)
        exit 0
    } else {
        # 内容不符：把含数字/关键词的第一行拿出来当反证
        $lines = $text -split "`r?`n"
        $near = ($lines | Where-Object { $_ -match [regex]::Escape(($Expect -replace '\d', '')) } | Select-Object -First 1)
        Write-Host ''
        Write-Host ("FAIL  {0}" -f $Claim) -ForegroundColor Red
        Write-Host ("      文件里找不到「{0}」" -f $Expect)
        if ($near) { Write-Host ("      相近内容：{0}" -f $near.Trim()) }
        exit 1
    }
}

if ($Kind -eq 'user') {
    if (-not (Test-Path $Node)) { Fail '找不到 node 运行时' }
    $js = Join-Path $Root 'logsearch.mjs'
    if (-not (Test-Path $js)) { Fail '找不到 logsearch.mjs' }
    $raw = & $Node $js $Expect $MaxHits 2>&1 | Out-String
    $j = $null
    try { $j = $raw | ConvertFrom-Json } catch { Fail '日志搜索输出无法解析' $raw.Substring(0, [Math]::Min(200, $raw.Length)) }

    if ($j.hitCount -gt 0) {
        $h = $j.hits[0]
        Write-Host ''
        Write-Host ("PASS  {0}" -f $Claim) -ForegroundColor Green
        Write-Host ("      evid:user:{0}:{1}" -f $h.session.Substring(0, [Math]::Min(16, $h.session.Length)), $h.time)
        Write-Host ("      日志原文：…{0}…" -f $h.snippet)
        exit 0
    } else {
        Write-Host ''
        Write-Host ("FAIL  {0}" -f $Claim) -ForegroundColor Red
        Write-Host ("      扫了 {0} 个会话文件，用户消息里没有「{1}」" -f $j.scanned, $Expect)
        Write-Host '      注意：这只证明「日志里没有」，不证明「他没说过」（可能说过但没打字）'
        exit 1
    }
}
