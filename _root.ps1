# _root.ps1 -- the one place that knows where this installation lives (PowerShell side)
#
# Mirror of core/root.mjs. Scripts dot-source this instead of defining their own path:
#   . (Join-Path $PSScriptRoot '_root.ps1')
#
# Why (2026-11-08): 24 scripts each defined $Root themselves, in 4 different spellings
# ($Root / $root / $ROOT / $base), and 4 of them actually pointed at a SUBDIRECTORY while
# still calling it $Root -- so the same name meant two different things.
#
# Defines:
#   $Root      installation root
#   $Notebook  $Root\notebook
#   $Track     $Root\track
#   $Core      $Root\core
#
# Order: COO_ROOT environment variable, else the directory containing this file.

# 2026-11-08: 只填空值。若调用者已经声明了 -Root（如 dep-check.ps1 的探针会传入测试目录），
# 绝不能覆盖——否则就是"参数被内部赋值覆盖"那个老坑，探针会测错对象。
# 用法：. (Join-Path $PSScriptRoot '_root.ps1')  然后直接用 $Root/$Notebook/$Track/$Core
if (-not $Root) {
    if ($env:COO_ROOT) {
        $Root = (Resolve-Path $env:COO_ROOT).Path
    } else {
        $Root = $PSScriptRoot
    }
    # 断言只管"我自己推断出来的值"。调用者显式传进来的（比如 dep-check 的探针传测试样本目录）
    # 不校验——否则测试场景会被自己人打回去（2026-11-08 实踩：探针从"报环"变成"root looks wrong"）。
    if (-not (Test-Path (Join-Path $Root 'track'))) {
        throw "root looks wrong: $Root (no track/ inside)"
    }
}

$Notebook = Join-Path $Root 'notebook'
$Track = Join-Path $Root 'track'
$Core = Join-Path $Root 'core'
