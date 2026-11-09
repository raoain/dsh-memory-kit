# push-kit.ps1 — 把 dsh-memory-kit 推到你的 GitHub
# 用法：
#   .\push-kit.ps1 -Token "github_pat_xxx"
#   .\push-kit.ps1 -Token "github_pat_xxx" -RepoName "dsh-memory-kit" -Private
#
# token 只需 Fine-grained + Contents: Read and write（+ Administration: Read and write 才能自动建仓库）
# 不想给 Administration 权限？先在网页建好空仓库，再用 -SkipCreate 跳过建仓库步骤。

param(
    [Parameter(Mandatory = $true)][string]$Token,
    [string]$RepoName = 'dsh-memory-kit',
    [switch]$Private,
    [switch]$SkipCreate
)
. (Join-Path $PSScriptRoot '_root.ps1')

$ErrorActionPreference = 'Stop'
$git = 'F:\Tools\git\bin\git.exe'
$dir = 'F:\Tools\dsh-memory-kit'
$api = 'https://api.github.com'
$headers = @{
    Authorization          = "Bearer $Token"
    Accept                 = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent'           = 'dsh-memory-kit'
}

if (-not (Test-Path $git)) { throw "找不到 git: $git" }
if (-not (Test-Path $dir)) { throw "找不到仓库目录: $dir" }

# 1. 确认身份
Write-Host '→ 验证 token…' -ForegroundColor Cyan
$me = Invoke-RestMethod -Uri "$api/user" -Headers $headers -Method Get
Write-Host ("  已登录: " + $me.login) -ForegroundColor Green
$owner = $me.login

# 2. 建仓库
if (-not $SkipCreate) {
    Write-Host '→ 创建仓库…' -ForegroundColor Cyan
    $body = @{
        name        = $RepoName
        description = '让 AI 助手的记忆活过下一次重启：自检 / 备份 / 记事本骨架'
        private     = [bool]$Private
        has_issues  = $true
        has_wiki    = $false
    } | ConvertTo-Json
    try {
        $repo = Invoke-RestMethod -Uri "$api/user/repos" -Headers $headers -Method Post -Body $body -ContentType 'application/json'
        Write-Host ("  已创建: " + $repo.html_url) -ForegroundColor Green
    } catch {
        $msg = $_.ErrorDetails.Message
        if ($msg -match 'already exists') { Write-Host '  仓库已存在，直接推' -ForegroundColor Yellow }
        else { throw "建仓库失败: $msg" }
    }
}

# 3. 推
Write-Host '→ 推送…' -ForegroundColor Cyan
$remote = "https://$owner`:$Token@github.com/$owner/$RepoName.git"
Push-Location $dir
try {
    & $git remote remove origin 2>$null | Out-Null
    & $git remote add origin $remote
    & $git push -u origin main 2>&1 | ForEach-Object { Write-Host "  $_" }
} finally {
    Pop-Location
    # 立刻把 token 从 remote 里摘掉，别留在 .git/config
    & $git remote set-url origin "https://github.com/$owner/$RepoName.git" 2>$null
    Write-Host '  已把 token 从 .git/config 移除' -ForegroundColor Green
}

Write-Host ''
Write-Host ("完成: https://github.com/{0}/{1}" -f $owner, $RepoName) -ForegroundColor Green
Write-Host '记得去 https://github.com/settings/tokens 撤掉这个 token' -ForegroundColor Yellow
