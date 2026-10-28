# selfcheck.ps1 — 一眼看清自己站在什么环境里
# 用法： powershell -NoProfile -File .\selfcheck.ps1
# 改下面「配置区」的路径即可，其余不用动。
$ErrorActionPreference = 'Continue'

# ===== 配置区（改成你自己的） =====
$Config = @{
    AppName     = 'Coopanion'                                   # 进程/应用名，没有就留空
    AppDir      = 'F:\新建文件夹 (2)\Coopanion'                  # 应用目录（读版本用），没有就留空
    AppLog      = 'F:\新建文件夹 (2)\Coopanion\data\logs\core.log'
    MemoryLog   = ''                                             # 扩展加载日志（可选）
    ToolCmd     = @{ 'bili-cli' = { & 'F:\Tools\uv\bin\uv.exe' tool list 2>&1 | Select-String 'bili-agent' | Select-Object -First 1 } }
    BinPaths    = @('F:\Tools\bin\ffmpeg.exe', 'F:\Tools\bin\ffprobe.exe')
    BackupDirs  = @('F:\Tools\coo-backup', 'D:\coo-backup')
    Drives      = @('C:', 'D:', 'F:')
    NotebookDir = 'F:\Tools\coo-day1'
    WakeMark    = 'F:\Tools\coo-day1\track\wake-last.txt'   # wake.ps1 留的时间戳
}
# =================================

$out = @()
function L($k, $v) { $script:out += ('{0,-14} {1}' -f $k, $v) }

# 应用版本
if ($Config.AppDir) {
    $pkg = Join-Path $Config.AppDir 'resources\app\package.json'
    $ver = if (Test-Path $pkg) { (Get-Content $pkg -Raw | ConvertFrom-Json).version } else { '?' }
    $proc = if ($Config.AppName) { (Get-Process $Config.AppName -ErrorAction SilentlyContinue | Measure-Object).Count } else { '-' }
    $suffix = if ($proc -eq 0) { '  (未运行)' } else { '' }
    L $Config.AppName ("v{0}  进程 {1}{2}" -f $ver, $proc, $suffix)
}

# 扩展 / world 加载情况
if ($Config.AppLog -and (Test-Path $Config.AppLog)) {
    # 不设锚点：宿主会多次重启 core，任何单一锚点都会漏（console / core已启动 都踩过）
    $lines = Get-Content $Config.AppLog -Tail 2000 -Encoding UTF8
    $w = $lines | Select-String -Pattern 'World 已启动: ' |
         ForEach-Object { ($_.Line -split 'World 已启动: ')[1] } |
         Where-Object { $_ } | Select-Object -Unique
    if ($w) { L '扩展' ("$($w.Count) 个：" + ($w -join ',')) }
}

# 工具版本
foreach ($k in $Config.ToolCmd.Keys) {
    try { $v = & $Config.ToolCmd[$k]; if ($v) { L $k ($v.Line.Trim()) } } catch { }
}
foreach ($b in $Config.BinPaths) {
    if (Test-Path $b) {
        $first = & $b -hide_banner -version 2>&1 | Select-Object -First 1
        if ($first -match 'version (\S+)') { L ([IO.Path]::GetFileNameWithoutExtension($b)) $matches[1] }
    }
}

# 备份
foreach ($d in $Config.BackupDirs) {
    if (Test-Path $d) {
        $f = Get-ChildItem $d -Filter '*.zip' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($f) { L ('备份 ' + $d.Substring(0, 2)) ("{0}  {1}" -f $f.Name, $f.LastWriteTime.ToString('MM-dd HH:mm')) }
        else { L ('备份 ' + $d.Substring(0, 2)) '空' }
    } else { L ('备份 ' + $d.Substring(0, 2)) '不存在' }
}

# 磁盘
foreach ($d in $Config.Drives) {
    $v = Get-PSDrive ($d.TrimEnd(':')) -ErrorAction SilentlyContinue
    if ($v) { L ('磁盘 ' + $d) ("剩 {0:N1} GB" -f ($v.Free / 1GB)) }
}

# 最近醒来：wake.ps1 的留痕。用来核对「核心层到底读没读」——没有机制，规矩就是空话
$wakeMark = $Config.WakeMark
if ($wakeMark -and (Test-Path $wakeMark)) {
    $w = (Get-Content $wakeMark -Encoding UTF8 -TotalCount 1)
    $hours = ((Get-Date) - (Get-Item $wakeMark).LastWriteTime).TotalHours
    if ($hours -gt 12) { L '最近醒来' ("$w  (${hours:N0} 小时前，偏旧)") } else { L '最近醒来' $w }
} elseif ($wakeMark) {
    L '最近醒来' '没跑过 wake.ps1（核心层未读）'
}


# 引脚对账（值有没有漂移；pin.ps1 存在才跑）
$pinScript = Join-Path (Split-Path $PSCommandPath -Parent) 'pin.ps1'
if (Test-Path $pinScript) {
    $pinOut = & powershell -NoProfile -ExecutionPolicy Bypass -File $pinScript -Diff 2>&1 | Out-String
    $drift = ([regex]::Matches($pinOut, '(?m)^DRIFT')).Count
    if ($drift -gt 0) { L '引脚对账' ("$drift 项漂移（跑 pin.ps1 -List 看明细）") }
    else { L '引脚对账' '全部对齐' }
}

$out | ForEach-Object { Write-Host # selfcheck.ps1 — 一眼看清自己站在什么环境里
# 用法： powershell -NoProfile -File .\selfcheck.ps1
# 改下面「配置区」的路径即可，其余不用动。
$ErrorActionPreference = 'Continue'

# ===== 配置区（改成你自己的） =====
$Config = @{
    AppName     = 'Coopanion'                                   # 进程/应用名，没有就留空
    AppDir      = 'F:\新建文件夹 (2)\Coopanion'                  # 应用目录（读版本用），没有就留空
    AppLog      = 'F:\新建文件夹 (2)\Coopanion\data\logs\core.log'
    MemoryLog   = ''                                             # 扩展加载日志（可选）
    ToolCmd     = @{ 'bili-cli' = { & 'F:\Tools\uv\bin\uv.exe' tool list 2>&1 | Select-String 'bili-agent' | Select-Object -First 1 } }
    BinPaths    = @('F:\Tools\bin\ffmpeg.exe', 'F:\Tools\bin\ffprobe.exe')
    BackupDirs  = @('F:\Tools\coo-backup', 'D:\coo-backup')
    Drives      = @('C:', 'D:', 'F:')
    NotebookDir = 'F:\Tools\coo-day1'
    WakeMark    = 'F:\Tools\coo-day1\track\wake-last.txt'   # wake.ps1 留的时间戳
}
# =================================

$out = @()
function L($k, $v) { $script:out += ('{0,-14} {1}' -f $k, $v) }

# 应用版本
if ($Config.AppDir) {
    $pkg = Join-Path $Config.AppDir 'resources\app\package.json'
    $ver = if (Test-Path $pkg) { (Get-Content $pkg -Raw | ConvertFrom-Json).version } else { '?' }
    $proc = if ($Config.AppName) { (Get-Process $Config.AppName -ErrorAction SilentlyContinue | Measure-Object).Count } else { '-' }
    $suffix = if ($proc -eq 0) { '  (未运行)' } else { '' }
    L $Config.AppName ("v{0}  进程 {1}{2}" -f $ver, $proc, $suffix)
}

# 扩展 / world 加载情况
if ($Config.AppLog -and (Test-Path $Config.AppLog)) {
    # 不设锚点：宿主会多次重启 core，任何单一锚点都会漏（console / core已启动 都踩过）
    $lines = Get-Content $Config.AppLog -Tail 2000 -Encoding UTF8
    $w = $lines | Select-String -Pattern 'World 已启动: ' |
         ForEach-Object { ($_.Line -split 'World 已启动: ')[1] } |
         Where-Object { $_ } | Select-Object -Unique
    if ($w) { L '扩展' ("$($w.Count) 个：" + ($w -join ',')) }
}

# 工具版本
foreach ($k in $Config.ToolCmd.Keys) {
    try { $v = & $Config.ToolCmd[$k]; if ($v) { L $k ($v.Line.Trim()) } } catch { }
}
foreach ($b in $Config.BinPaths) {
    if (Test-Path $b) {
        $first = & $b -hide_banner -version 2>&1 | Select-Object -First 1
        if ($first -match 'version (\S+)') { L ([IO.Path]::GetFileNameWithoutExtension($b)) $matches[1] }
    }
}

# 备份
foreach ($d in $Config.BackupDirs) {
    if (Test-Path $d) {
        $f = Get-ChildItem $d -Filter '*.zip' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($f) { L ('备份 ' + $d.Substring(0, 2)) ("{0}  {1}" -f $f.Name, $f.LastWriteTime.ToString('MM-dd HH:mm')) }
        else { L ('备份 ' + $d.Substring(0, 2)) '空' }
    } else { L ('备份 ' + $d.Substring(0, 2)) '不存在' }
}

# 磁盘
foreach ($d in $Config.Drives) {
    $v = Get-PSDrive ($d.TrimEnd(':')) -ErrorAction SilentlyContinue
    if ($v) { L ('磁盘 ' + $d) ("剩 {0:N1} GB" -f ($v.Free / 1GB)) }
}

# 最近醒来：wake.ps1 的留痕。用来核对「核心层到底读没读」——没有机制，规矩就是空话
$wakeMark = $Config.WakeMark
if ($wakeMark -and (Test-Path $wakeMark)) {
    $w = (Get-Content $wakeMark -Encoding UTF8 -TotalCount 1)
    $hours = ((Get-Date) - (Get-Item $wakeMark).LastWriteTime).TotalHours
    if ($hours -gt 12) { L '最近醒来' ("$w  (${hours:N0} 小时前，偏旧)") } else { L '最近醒来' $w }
} elseif ($wakeMark) {
    L '最近醒来' '没跑过 wake.ps1（核心层未读）'
}

$out | ForEach-Object { Write-Host $_ }
 }