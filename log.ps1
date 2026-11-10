# log.ps1 — 记一条工作层，自动附上「自上次记录以来改过哪些文件」
#
# 为什么：X→M 这条接缝太宽（覆盖所有改动），逐条堵不可能。
# 需要一个组件替我记得改了什么 —— 否则就会「改了 57 个文件，只记了 12 条」。
#
# 用法：
#   .\log.ps1 -Text "做了什么" [-Evid "证: 命令输出/哈希"]
#   .\log.ps1 -Text "做了什么" -NoFiles     # 不附文件清单
param(
    [Parameter(Mandatory = $true)][string]$Text,
    [string]$Evid = '',
    [switch]$NoFiles
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_root.ps1')
$Work = Join-Path $Root 'notebook\1-工作.md'
$enc  = New-Object Text.UTF8Encoding($false)

if (-not (Test-Path $Work)) { Write-Host "找不到工作层：$Work" -ForegroundColor Red; exit 1 }
# 入口拦截（2026-10-30）：-Evid 必须是可核形式，否则拒绝写入
if ($Evid) {
    $EvidCheck = $false
    if ($Evid -match '项：|\d+\s*项|OK |字节|条|第\s*\d+(\s*-\s*\d+)?\s*行') { $EvidCheck = $true }
    if (-not $EvidCheck -and $Evid -match '([A-Za-z0-9_\-\\/\.]+\.(md|ps1|jsonl|json|mjs|txt))') {
        foreach ($mm in [regex]::Matches($Evid,'([A-Za-z0-9_\-\\/\.]+\.(md|ps1|jsonl|json|mjs|txt))')) {
            if (Test-Path (Join-Path $Root $mm.Groups[1].Value)) { $EvidCheck = $true }
        }
    }
    # 2026-11-10（用户纠正：证要转成数字/英文，不是放宽检查器去收中文）：
    # 页名用 dir+prefix 指（page:notebook/0- 或 page:notebook/0-:26），全程 ASCII，可定位、可数行。
    if (-not $EvidCheck -and $Evid -match 'page:\s*([A-Za-z0-9_\-/]+)/([A-Za-z0-9_\-]+)(?::(?:L)?(\d+))?') {
        $eDir = $Matches[1]; $ePfx = $Matches[2]; $eLine = $Matches[3]
        $eDirPath = Join-Path $Root $eDir
        if (Test-Path $eDirPath) {
            $eHit = @(Get-ChildItem $eDirPath -Filter ("{0}*" -f $ePfx) -File -ErrorAction SilentlyContinue)
            if ($eHit.Count -gt 0) {
                $EvidCheck = $true
                if ($eLine) {
                    $eCount = @(Get-Content $eHit[0].FullName -Encoding UTF8).Count
                    if ([int]$eLine -gt $eCount) { $EvidCheck = $false }
                }
            }
        }
    }
    # 2026-11-10 第二版（用户：遵守标准然后上个翻译层）：页号是数字（core/pages.json，纯 ASCII），
    # 页名（中文）放翻译层 core/locales/zh.json 的 page.<id>。程序只认数字，中文不进口。
    if (-not $EvidCheck -and $Evid -match 'page:\s*(\d{3,})(?::(?:L)?(\d+))?') {
        $eId = [int]$Matches[1]; $eLine2 = $Matches[2]
        $pagesPath = Join-Path $Root 'core\pages.json'
        if (Test-Path $pagesPath) {
            $pg = [IO.File]::ReadAllText($pagesPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
            if (@($pg.ids) -contains $eId) {
                $zhPath2 = Join-Path $Root 'core\locales\zh.json'
                if (Test-Path $zhPath2) {
                    $zhObj = [IO.File]::ReadAllText($zhPath2, [Text.Encoding]::UTF8) | ConvertFrom-Json
                    $rel = $zhObj.("page.$eId")
                    if ($rel) {
                        $full = Join-Path $Root $rel
                        if (Test-Path $full) {
                            $EvidCheck = $true
                            if ($eLine2) {
                                $cnt2 = @(Get-Content $full -Encoding UTF8).Count
                                if ([int]$eLine2 -gt $cnt2) { $EvidCheck = $false }
                            }
                        }
                    }
                }
            }
        }
    }
    if (-not $EvidCheck) {
        Write-Host ''
        Write-Host '拒绝写入：证不可核。' -ForegroundColor Red
        Write-Host ('  现在给的是：' + $Evid) -ForegroundColor Yellow
        Write-Host '  可核形式（只用数字与英文）：verify 50 项 OK 50 ／ page:101 ／ page:101:136 ／ page:notebook/0-:26 ｜ 第 12-14 行' -ForegroundColor Yellow
        exit 1
    }
}

# 1) 找上一次记录的时间
$lastTime = $null
foreach ($ln in (Get-Content $Work -Encoding UTF8)) {
    $m = [regex]::Match($ln, '^- \[(\d{4}-\d{2}-\d{2} \d{2}:\d{2})\]')
    if ($m.Success) { $lastTime = [datetime]::Parse($m.Groups[1].Value) }
}
if (-not $lastTime) { $lastTime = (Get-Date).AddHours(-2) }

# 2) 找那之后改过的文件（跳过垃圾场与构建产物）
$changed = @()
if (-not $NoFiles) {
    $changed = @(Get-ChildItem $Root -Recurse -Include *.ps1,*.md,*.mjs,*.json,*.jsonl -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -notmatch '\\trash\\|\\build\\|\\archive\\|\\audio' -and
            $_.LastWriteTime -gt $lastTime
        } |
        Sort-Object LastWriteTime |
        ForEach-Object { $_.Name })
    $changed = @($changed | Select-Object -Unique)
}

# 3) 组装条目
$now = Get-Date -Format 'yyyy-MM-dd HH:mm'
$line = "- [$now] $Text"
if (-not $NoFiles -and $changed.Count -gt 0) {
    $show = $changed
    if ($show.Count -gt 8) { $show = $show[0..7] }
    $more = if ($changed.Count -gt 8) { " 等 $($changed.Count) 个" } else { '' }
    $line += " ｜ 改过：$($show -join '、')$more"
}
if ($Evid) { $line += " ｜ $Evid" }

# 4) 追加（带 BOM，与工作层一致）
$existing = [IO.File]::ReadAllText($Work, [Text.Encoding]::UTF8)
$head = ""
[IO.File]::AppendAllText($Work, $head + $line + "`r`n", $enc)

Write-Host ''
Write-Host '已记入工作层：' -ForegroundColor Green
Write-Host ("  " + $line)
Write-Host ("  上次记录：{0}；本轮改了 {1} 个文件" -f $lastTime.ToString('yyyy-MM-dd HH:mm'), $changed.Count) -ForegroundColor DarkGray
# machine-readable exit (adapter reads only this line): state 0 pass / 1 warn / 2 fail / 3 unknown
$sigState = 0
if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) { $sigState = 2 }
if ($sigState -eq 0 -and (Get-Variable -Name 'Failed' -ErrorAction SilentlyContinue) -and $Failed) { $sigState = 2 }
Write-Output ("SIG " + (@{ state = $sigState; counts = @($sigState) } | ConvertTo-Json -Compress))
