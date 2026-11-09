# backup.ps1 — Coo 记忆备份
# 把 Coopanion 的记忆工作区打包到 F:\Tools\coo-backup\，保留最近 N 份。
# 用法： .\backup.ps1            （保留 7 份）
#        .\backup.ps1 -Keep 14
param([int]$Keep = 7)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_root.ps1')
$src = 'F:\新建文件夹 (2)\Coopanion\data\home\companion'
$dst = 'F:\Tools\coo-backup'

if (-not (Test-Path $src)) { throw "找不到记忆目录: $src" }
New-Item -ItemType Directory -Force -Path $dst | Out-Null

$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$zip = Join-Path $dst "companion-$stamp.zip"

$ok = $false
for ($try = 1; $try -le 3; $try++) {
    try {
        Compress-Archive -Path (Join-Path $src '*') -DestinationPath $zip -CompressionLevel Optimal -Force
        $ok = $true; break
    } catch {
        if ($try -eq 3) { throw }
        Write-Host "  备份第 $try 次失败（源文件在变），2 秒后重试" -ForegroundColor Yellow
        Start-Sleep -Seconds 2
    }
}

$files = Get-ChildItem $dst -Filter 'companion-*.zip' | Sort-Object LastWriteTime -Descending
$files | Select-Object -Skip $Keep | ForEach-Object {
    Remove-Item $_.FullName -Force
}

# 第二份：换一块盘，防整盘损坏
$dst2 = 'D:\coo-backup'
New-Item -ItemType Directory -Force -Path $dst2 | Out-Null
$zip2 = Join-Path $dst2 (Split-Path $zip -Leaf)
Copy-Item $zip $zip2 -Force
$files2 = Get-ChildItem $dst2 -Filter 'companion-*.zip' | Sort-Object LastWriteTime -Descending
$files2 | Select-Object -Skip $Keep | ForEach-Object { Remove-Item $_.FullName -Force }

# 第三份：meow-memory 的检索库（在工作区里，不在 companion 目录下，早先一直漏备）
$meow = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\.dsh-meow\memory.db'
if (Test-Path $meow) {
    $mName = "meow-memory-$stamp.db"
    $mj1 = Join-Path $dst $mName
    $mj2 = Join-Path $dst2 $mName
    # WAL 模式：最新写入在 memory.db-wal 里，主库要 checkpoint 才合并。
    # 只拷 memory.db = 备份到的是旧快照，所以三个文件必须一起拷、一起还原。
    $meowSet = @($meow, "$meow-wal", "$meow-shm")
    $copied = $false
    for ($try = 1; $try -le 3; $try++) {
        try {
            foreach ($m in $meowSet) {
                if (-not (Test-Path $m)) { continue }
                $suffix = $m.Substring($meow.Length)
                Copy-Item $m ($mj1 + $suffix) -Force
                Copy-Item $m ($mj2 + $suffix) -Force
            }
            $copied = $true; break
        }
        catch { Start-Sleep -Seconds 2 }
    }
    if ($copied) {
        foreach ($d in @($dst, $dst2)) {
            Get-ChildItem $d -Filter 'meow-memory-*.db' | Sort-Object LastWriteTime -Descending |
                Select-Object -Skip $Keep | Remove-Item -Force
        }
        Write-Host ("meow 记忆库: {0}（各留 {1} 份）" -f $mName, $Keep) -ForegroundColor DarkGray
    } else {
        Write-Host 'meow 记忆库备份失败：文件被占用' -ForegroundColor Yellow
    }
}

$size = (Get-Item $zip).Length / 1MB
Write-Host ("备份: {0} + {1}  ({2:N1} MB, 各留 {3} 份)" -f $zip, $zip2, $size, $Keep) -ForegroundColor Green
# 第四份：自己的记忆索引（mem.mjs 导出），不依赖插件也能还原
$index = (Join-Path $Root 'memories.jsonl')
if (Test-Path $index) {
    $iName = "meow-index-$stamp.jsonl"
    foreach ($d in @($dst, $dst2)) {
        Copy-Item $index (Join-Path $d $iName) -Force
        Get-ChildItem $d -Filter 'meow-index-*.jsonl' | Sort-Object LastWriteTime -Descending |
            Select-Object -Skip $Keep | Remove-Item -Force
    }
    Write-Host ("自己的索引: {0}（{1:N1} KB，各留 {2} 份）" -f $iName, ((Get-Item $index).Length/1KB), $Keep) -ForegroundColor DarkGray
}
# machine-readable exit (adapter reads only this line): state 0 pass / 1 warn / 2 fail / 3 unknown
$sigState = 0
if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) { $sigState = 2 }
if ($sigState -eq 0 -and (Get-Variable -Name 'Failed' -ErrorAction SilentlyContinue) -and $Failed) { $sigState = 2 }
$sigLine = "SIG " + (@{ state = $sigState; counts = @($sigState) } | ConvertTo-Json -Compress)
Write-Output $sigLine
# 2026-11-09: 投递这一半。器官跑完了，但没人把它的 SIG 送进总线 —— 中枢因此把它当成
# "48 小时没上报"，尽管它每天真的在跑。这里照 watchdog 对 verify 的做法，自己走一次适配器。
# 失败不改变备份结果本身。
try {
    $outDir = Join-Path $Root 'track\out'
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    $outFile = Join-Path $outDir '5.txt'
    $sigLine | Out-File -FilePath $outFile -Encoding utf8
    & node (Join-Path $Root 'core\adapter.mjs') 5 $outFile --exit $sigState 2>&1 | Out-Null
} catch {
    Write-Host ("adapter 失败：" + $_.Exception.Message) -ForegroundColor Yellow
}
