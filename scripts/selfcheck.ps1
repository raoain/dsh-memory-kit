# selfcheck.ps1
# 用法：见本文件末尾或 README.md —— 无参数直接跑；参数见下方 param 块
# selfcheck.ps1 — Coo 自己的体检
# 一眼看清：宿主版本、桌宠状态、工具版本、备份、磁盘
$ErrorActionPreference = 'Continue'
$out = @()
function L($k, $v) { $script:out += ('{0,-14} {1}' -f $k, $v) }

# 宿主
$dshVer = Get-Content '<应用安装目录>\version' -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
$dshVerText = if ($dshVer) { "$dshVer".Trim() } else { '' }
L 'DSH' ("v$dshVerText" + $(if ($dshVerText) { ' (nightly)' } else { ' 读不到' }))

# 桌宠
$cooExe = '<应用安装目录>\Coopanion\Coopanion.exe'
$cooVer = if (Test-Path '<应用安装目录>\Coopanion\resources\app\package.json') {
    (Get-Content '<应用安装目录>\Coopanion\resources\app\package.json' -Raw -Encoding UTF8 | ConvertFrom-Json).version
} else { '?' }
$cooProc = (Get-Process Coopanion -ErrorAction SilentlyContinue | Measure-Object).Count
L 'Coopanion' ("v$cooVer  进程 $cooProc" + $(if ($cooProc -eq 0) { '  (未运行)' } else { '' }))

# 桌宠的 world
$log = '<应用安装目录>\Coopanion\data\logs\core.log'
if (Test-Path $log) {
    # 不设锚点：core 会多次重启，任何单一锚点都会漏。整段取「World 已启动」去重即可
    $lines = Get-Content $log -Tail 2000 -Encoding UTF8
    $w = $lines | Select-String -Pattern 'World 已启动: ' |
         ForEach-Object { ($_.Line -split 'World 已启动: ')[1] } |
         Where-Object { $_ } | Select-Object -Unique
    if ($w) { L 'World' ("$($w.Count) 个：" + ($w -join ',')) }
}

# 工具
$biliVer = (& '<uv路径>' tool list 2>&1 | Select-String -Pattern 'bili-agent' | Select-Object -First 1)
if ($biliVer) { L 'bili-cli' $biliVer.Line.Trim() }
$ff = & '<ffmpeg路径>' -hide_banner -version 2>&1 | Select-Object -First 1
if ($ff -match 'version (\S+)') { L 'ffmpeg' $matches[1] }
$fp = & '<ffprobe路径>' -hide_banner -version 2>&1 | Select-Object -First 1
if ($fp -match 'version (\S+)') { L 'ffprobe' $matches[1] }

# 备份
foreach ($d in '<备份盘A>\coo-backup', '<备份盘B>\coo-backup') {
    if (Test-Path $d) {
        $f = Get-ChildItem $d -Filter '*.zip' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        L ('备份 ' + $d.Substring(0, 2)) ("{0}  {1}" -f $f.Name, $f.LastWriteTime.ToString('MM-dd HH:mm'))
    }
}

# 磁盘
foreach ($d in 'C:', 'D:', 'F:') {
    $v = Get-PSDrive ($d.TrimEnd(':')) -ErrorAction SilentlyContinue
    if ($v) { L ('磁盘 ' + $d) ("剩 {0:N1} GB" -f ($v.Free / 1GB)) }
}

# 今天的片子
$today = Get-ChildItem '<你的项目根>\track\own' -Filter '*.json' -ErrorAction SilentlyContinue |
         Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($today) { L '最近快照' ($today.Name + '  ' + $today.LastWriteTime.ToString('MM-dd HH:mm')) }

# 最近醒来：wake.ps1 的留痕，用来核对「核心层到底读没读」
$wakeMark = '<你的项目根>\track\wake-last.txt'
if (Test-Path $wakeMark) {
    $w = (Get-Content $wakeMark -Encoding UTF8 -TotalCount 1)
    $stale = ((Get-Date) - (Get-Item $wakeMark).LastWriteTime).TotalHours
    if ($stale -gt 12) { L '最近醒来' ("$w  (${stale:N0} 小时前，偏旧)") } else { L '最近醒来' $w }
} else {
    L '最近醒来' '没跑过 wake.ps1（核心层未读）'
}

$out | ForEach-Object { Write-Host $_ }

# 引脚对账（值有没有漂移）
$pinScript = Join-Path (Split-Path $PSCommandPath -Parent) 'pin.ps1'
if (Test-Path $pinScript) {
    $pinOut = & powershell -NoProfile -ExecutionPolicy Bypass -File $pinScript -Diff 2>&1 | Out-String
    $drift = ([regex]::Matches($pinOut, '(?m)^DRIFT')).Count
    if ($drift -gt 0) { L '引脚对账' ("$drift 项漂移（跑 pin.ps1 -List 看明细）") }
    else { L '引脚对账' '全部对齐' }
} else { L '引脚对账' 'pin.ps1 不存在' }

$out | ForEach-Object { Write-Host $_ }