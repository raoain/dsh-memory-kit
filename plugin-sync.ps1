# plugin-sync.ps1 — pull the memory plugin's data back into the body (C direction)
#
# Why (user 2026-11-22): the standard is "runs with the plugin removed", so whatever the
# plugin writes must also exist inside the body. And: "只要针对于m那个就可以了" —
# only the m plugin (meow-memory) matters here, not dsh-notebook.
#
# What: copy meow-memory's SQLite files (memory.db / -wal / -shm) from the workspace's
# .dsh-meow into track\misc\plugin-data\meow\, then append one line to
# track\misc\plugin-sync.jsonl. The JSONL export (memories.jsonl) stays the readable snapshot;
# this is the binary copy that survives the plugin being removed.
#
# usage: powershell -NoProfile -File F:\Tools\coo-day1\plugin-sync.ps1
# exit: 0 done (also when the source is absent), 1 copy failed

param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_root.ps1')

$candidates = @()
if ($env:DSH_WORKSPACE) { $candidates += (Join-Path $env:DSH_WORKSPACE '.dsh-meow') }
$candidates += 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\.dsh-meow'
$candidates += (Join-Path $env:USERPROFILE '.dsh-meow')

$src = $null
foreach ($c in $candidates) { if (Test-Path (Join-Path $c 'memory.db')) { $src = $c; break } }

$dst = Join-Path $Root 'track\misc\plugin-data\meow'
$log = Join-Path $Root 'track\misc\plugin-sync.jsonl'
$at = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

if (-not $src) {
    $line = [pscustomobject]@{ at = $at; plugin = 'meow-memory'; state = 'absent'; src = ($candidates -join ' | ');
        files = 0; bytes = 0; note = 'memory.db not found in any candidate; nothing to pull back' }
    Write-Host 'plugin-sync: meow-memory absent (no memory.db found)'
    Add-Content -Path $log -Value ($line | ConvertTo-Json -Compress) -Encoding UTF8
    exit 0
}

if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Force -Path $dst | Out-Null }

$got = @()
$bytes = 0
try {
    foreach ($name in @('memory.db', 'memory.db-wal', 'memory.db-shm')) {
        $f = Join-Path $src $name
        if (Test-Path $f) {
            Copy-Item $f (Join-Path $dst $name) -Force
            $bytes += (Get-Item $f).Length
            $got += $name
        }
    }
    $mtime = (Get-Item (Join-Path $src 'memory.db')).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
    $line = [pscustomobject]@{ at = $at; plugin = 'meow-memory'; state = 'synced'; src = $src;
        files = $got.Count; bytes = $bytes; db_mtime = $mtime;
        note = 'binary copy in body; memories.jsonl stays the readable snapshot' }
    Write-Host ('plugin-sync: meow-memory synced ' + $got.Count + ' files / ' + [math]::Round($bytes/1MB,1) + ' MB')
    Write-Host ('  src db mtime ' + $mtime)
    Add-Content -Path $log -Value ($line | ConvertTo-Json -Compress) -Encoding UTF8
    exit 0
} catch {
    $line = [pscustomobject]@{ at = $at; plugin = 'meow-memory'; state = 'failed'; src = $src;
        files = 0; bytes = 0; note = [string]$_.Exception.Message }
    Write-Host ('plugin-sync: failed -> ' + $_.Exception.Message) -ForegroundColor Red
    Add-Content -Path $log -Value ($line | ConvertTo-Json -Compress) -Encoding UTF8
    exit 1
}
