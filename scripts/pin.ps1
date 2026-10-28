# pin.ps1 — 引脚表：把「当前值」记成数据，并和「实际值」对账
#
# 为什么要有这个：参数会变（音色、上限、脚本内容），但变化从来没有被记录下来。
# 于是重启后不知道当前值 → 按记忆里的旧值推理 → 拿到旧结果 → 再改一次 → 又忘。
#
# 关键不是「记住」，是**对账**：它从 state.json 读一次、从现场算一次，对不上就报。
# 上下文成本接近零：只有真的漂移了才输出。
#
# 用法：
#   .\pin.ps1 -Init          # 用当前实际值初始化/重建引脚表
#   .\pin.ps1 -Diff          # 对账（默认动作）
#   .\pin.ps1 -Set tts.voice zh-CN-XiaoyiNeural   # 改参数时顺手钉一次
#   .\pin.ps1 -List          # 列出全部引脚
param(
    [switch]$Init,
    [switch]$Diff,
    [switch]$List,
    [string]$Set,
    [string]$Value,
    [string]$StateFile = 'F:\Tools\coo-day1\state.json',   # ← 改成你自己的
    [string]$Root = 'F:\Tools\coo-day1'                   # ← 改成你自己的
)

$ErrorActionPreference = 'Continue'

# ---------- 解析器：每个引脚怎么从现场算出实际值 ----------
function Resolve-Pin($key) {
    switch -Regex ($key) {
        '^tts\.engine$' {
            $p = Join-Path $Root 'make-day.ps1'
            if (-not (Test-Path $p)) { return $null }
            $m = [regex]::Match([IO.File]::ReadAllText($p, [Text.Encoding]::UTF8), '\[string\]\$TtsEngine\s*=\s*''([^'']+)''')
            if ($m.Success) { return $m.Groups[1].Value } else { return $null }
        }
        '^tts\.voice$' {
            $p = Join-Path $Root 'make-day.ps1'
            if (-not (Test-Path $p)) { return $null }
            $m = [regex]::Match([IO.File]::ReadAllText($p, [Text.Encoding]::UTF8), '\[string\]\$TtsVoice\s*=\s*''([^'']+)''')
            if ($m.Success) { return $m.Groups[1].Value } else { return $null }
        }
        '^tts\.rate$' {
            $p = Join-Path $Root 'make-day.ps1'
            if (-not (Test-Path $p)) { return $null }
            $m = [regex]::Match([IO.File]::ReadAllText($p, [Text.Encoding]::UTF8), '\[string\]\$TtsRate\s*=\s*''([^'']+)''')
            if ($m.Success) { return $m.Groups[1].Value } else { return $null }
        }
        '^publish\.cap$' {
            $p = Join-Path $env:USERPROFILE '.dsh\AGENTS.md'
            if (-not (Test-Path $p)) { return $null }
            $t = [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
            $m = [regex]::Match($t, '一天最多\s*(\d+)\s*条')
            if ($m.Success) { return $m.Groups[1].Value } else { return $null }
        }
        '^core\.max$' { return '2048' }
        '^core\.size$' {
            $p = Join-Path $Root 'notebook\0-核心.md'
            if (Test-Path $p) { return (Get-Item $p).Length } else { return $null }
        }
        '^script\.(.+)$' {
            $name = $Matches[1]
            $p = Join-Path $Root $name
            if (-not (Test-Path $p)) { return $null }
            return (Get-FileHash $p -Algorithm SHA256).Hash.Substring(0, 16)
        }
        '^tomb\.count$' {
            $p = Join-Path $Root 'notebook\3-墓碑.md'
            if (-not (Test-Path $p)) { return $null }
            $t = [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
            $t = ($t -split '## 新条目怎么加')[0]
            return ([regex]::Matches($t, '(?m)^### ')).Count
        }
        default { return $null }
    }
}

function Load-State {
    if (-not (Test-Path $StateFile)) { return $null }
    try { return (Get-Content $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Save-State($state) {
    $json = $state | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($StateFile, $json, (New-Object Text.UTF8Encoding($false)))
}

# 默认引脚清单（Init 用）
$defaultPins = @(
    'tts.engine', 'tts.voice', 'tts.rate',
    'publish.cap',
    'core.max', 'core.size',
    'tomb.count',
    'script.make-day.ps1', 'script.verify.ps1', 'script.wake.ps1',
    'script.backup.ps1', 'script.status.ps1', 'script.trash.ps1'
)

if ($Init) {
    $pins = @{}
    foreach ($k in $defaultPins) {
        $v = Resolve-Pin $k
        if ($null -ne $v) { $pins[$k] = "$v" }
    }
    $state = @{ updated = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); pins = $pins }
    Save-State $state
    Write-Host ("引脚表已初始化：{0} 项 -> {1}" -f $pins.Count, $StateFile) -ForegroundColor Green
    foreach ($k in ($pins.Keys | Sort-Object)) { Write-Host ("  {0,-24} {1}" -f $k, $pins[$k]) -ForegroundColor DarkGray }
    return
}

$state = Load-State
if (-not $state) { Write-Host "没有引脚表，先跑 -Init" -ForegroundColor Yellow; exit 2 }

if ($Set) {
    if (-not $Value) { Write-Host "需要 -Value" -ForegroundColor Red; exit 2 }
    if (-not $state.pins.PSObject.Properties[$Set]) { $state.pins | Add-Member -NotePropertyName $Set -NotePropertyValue $Value }
    else { $state.pins.$Set = $Value }
    $state.updated = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    Save-State $state
    Write-Host ("已钉: {0} = {1}" -f $Set, $Value) -ForegroundColor Green
    return
}

if ($List) {
    foreach ($k in ($state.pins.PSObject.Properties.Name | Sort-Object)) {
        $now = Resolve-Pin $k
        $mark = if ("$now" -eq "$($state.pins.$k)") { ' ' } else { '≠' }
        Write-Host ("{0} {1,-24} 记着={2,-24} 实际={3}" -f $mark, $k, $state.pins.$k, $now)
    }
    return
}

# 默认：对账
$drift = 0
$checked = 0
foreach ($k in ($state.pins.PSObject.Properties.Name | Sort-Object)) {
    $pinned = "$($state.pins.$k)"
    $actual = Resolve-Pin $k
    $checked++
    if ($null -eq $actual) {
        Write-Host ("WARN  {0,-24} 记为 {1}，但现场算不出来了" -f $k, $pinned) -ForegroundColor Yellow
        $drift++
    } elseif ("$actual" -ne $pinned) {
        Write-Host ("DRIFT {0,-24} 记着 {1} → 实际 {2}" -f $k, $pinned, "$actual") -ForegroundColor Red
        $drift++
    }
}
if ($drift -eq 0) {
    Write-Host ("引脚全部对齐（{0} 项）" -f $checked) -ForegroundColor Green
    exit 0
} else {
    Write-Host ("`n{0}/{1} 项漂移。确认后跑 -Init 重建，或 -Set 单独改。" -f $drift, $checked) -ForegroundColor Yellow
    exit 1
}
