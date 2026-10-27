# 踩过的坑（脱敏版）

这些坑都是真踩出来的，按「现象 / 根因 / 修法」记。凡是能复现的，都写了怎么复现。

判断一个坑值不值得记：**下次撞上它，我会不会浪费半小时以上**。会，就写下来。

---

## 1. 中文文件读出来是乱码，看着像文件损坏

**现象**：`Get-Content` 读出来是 `鏍稿績灞?`、`姣忔閱掓潵`，`ConvertFrom-Json` 报「应为 `:` 或 `}`」。

**根因**：PowerShell 5.1 对**没有 BOM** 的 UTF-8 文件默认按 GBK(936) 解码。文件本身是好的。

**修法**：

```powershell
Get-Content $p -Raw -Encoding UTF8
[IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
```

**先验字节，再动手改文件** —— 用严格解码器，抛异常才是真坏：

```powershell
$dec = [Text.Encoding]::GetEncoding('utf-8',
    [Text.EncoderFallback]::ExceptionFallback,
    [Text.DecoderFallback]::ExceptionFallback)
$dec.GetString([IO.File]::ReadAllBytes($p))
```

**为什么危险**：误判成「文件损坏」之后，人会去重写文件、甚至重装。我因此浪费过一整天。

---

## 2. 编辑工具会吃掉 BOM，`.ps1` 直接语法崩

**现象**：`powershell -File xxx.ps1` 报一串 `Unexpected token` / `Missing closing ')'`，报错里的中文是乱码。

**根因**：多数编辑/写文件接口按无 BOM 的 UTF-8 写。脚本丢了 BOM，PS 5.1 就按 ANSI 解析，中文全碎，语法跟着崩。

**修法**：改完 `.ps1` 立刻补回 BOM 再跑一次。

```powershell
$p = '<你的脚本>.ps1'
$t = [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
if ($t[0] -eq [char]0xFEFF) { $t = $t.Substring(1) }
[IO.File]::WriteAllBytes($p, (New-Object Text.UTF8Encoding($true)).GetPreamble() + [Text.Encoding]::UTF8.GetBytes($t))
```

**识别法**：报错里中文是乱码 + 一堆 token 错误 = BOM 丢了，**不是语法写错**，别去改代码。

---

## 3. 插件装了不等于会加载

**现象**：依赖装好了、`node_modules` 也在，但工具就是不出现，且**没有任何报错**。

**根因**：宿主只挂载配置文件里 `bundles` 列出的插件；只写进依赖列表不算。

**修法**：排查顺序

1. 配置里的 `bundles` 有没有它
2. `node_modules` 里有没有链接/实体
3. 入口导出形状（具名 `apply` 与 `default` 两种都提供，宿主两种都认）

---

## 4. 把 git 仓库链进 node_modules，`.git` 会被弄坏

**现象**：仓库 HEAD/config 消失，只剩空的 `objects/`、`refs/`。

**根因**：包管理器处理本地路径依赖时，会穿过 junction / 链接操作目标目录。

**修法**：

- 用 `file:` 安装，不要用 `link:`
- 源码仓库和 `node_modules` 保持**物理分离**
- 随时保证远端有备份 —— 就是靠远端救回的提交

---

## 5. 启动 Electron 程序，它静默退出、退出码 0、没有日志

**现象**：双击能开，脚本里 `Start-Process` 启动就立刻退出，日志一行不写。

**根因**：如果父进程本身是 Electron（很多 IDE/桌面应用都是），环境里可能带着 `ELECTRON_RUN_AS_NODE=1`。子进程继承后**退化成纯 Node**，只跑 Node 逻辑，不开窗口。

**修法**：启动前清掉该变量。

```powershell
Remove-Item Env:\ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue
```

**判断法**：`--version` 输出的是 Node 版本而不是应用版本，就说明它退化成了 Node。

---

## 6. 同一目录的两个路径字符串，包管理器不认

**现象**：`ERR_PNPM_UNEXPECTED_STORE`，说依赖来自另一个 store 位置。

**根因**：目录是 junction / 符号链接，两个路径指向同一份数据，但包管理器按**路径字符串**判断，认为 store 变了。

**修法**：用和安装时**完全相同**的路径字符串启动，不必重装依赖。

---

## 7. 备份只覆盖「目录」，漏了目录之外的单文件

**现象**：重装后，文件夹里的东西都在，但检索库、密钥文件全没了。

**根因**：备份脚本只打包一个目录，而关键单文件在它的兄弟目录里。这类文件平时不看，最容易漏。

**修法**：备份脚本加一个「额外单文件」列表，跟目录一起轮转、一起落两块盘。

---

## 8. 重装只换程序，不还原数据目录

**现象**：程序回来了，记忆是空的。

**根因**：安装器只覆盖程序目录；数据目录通常在别处（用户目录 / 程序旁的 `data`），安装器不碰，也不会帮你还原。

**修法**：重装后**主动**从备份解压回数据目录，并清掉过期的实例锁文件（否则新进程会以为自己已在运行而退出）。

---

## 9. 日志统计不要用「某一行」当锚点

**现象**：自检报的扩展数量时多时少。

**根因**：日志里启动标记会重复出现多次（每次重启都有一条）。拿最后一次当锚点，会漏掉它之前启动的；拿第一条当锚点，会混进上一次的。

**修法**：不设锚点，整段取匹配项按名字去重。

---

## 10. `git push` 被重置，但 API 能用

**现象**：`git push` 报 `Recv failure: Connection was reset`，fetch 也一样。

**根因**：网络对 443 的 git 流量不稳定，但带 token 的 API 请求正常。

**修法**：用 CLI 的 API 能力逐文件提交，或直接用 git data API（blob → tree → commit → ref）做**一个**完整提交，别散成一堆碎提交。

注意：用 API 传 `.ps1` 时要 `encoding=base64` 原样传字节，否则 BOM 会丢（见第 2 条）。
