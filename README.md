# dsh-memory-kit

> 让 AI 助手的记忆活过下一次重启。
>
> 一个文件（规则）、两条命令（自检 + 保存）、一个骨架（记事本）。
> 不依赖任何插件，不承诺人格效果。

---

## 这解决什么问题

如果你在长期用一个 AI 助手（DSH、Cortico、Coopanion 都一样），会撞到同一堵墙：

- 对话关掉，上下文就没了
- 它昨天答应的事，今天不知道
- 它昨天犯的错，今天还会再犯
- 你以为它记得，其实它每次都在重新猜

大多数人靠「写更长的提示词」解决，那不管用。提示词是**这一次**的，记忆要**跨这一次**。

这个仓库给的是五件最小的东西：读、查、存、收、核。不多，但缺一件就不成立。

---

## 五条规则

### 0. 开工先读核心层（`scripts/wake.ps1`）

跑一次 `wake.ps1`：它打印核心层（我是谁、使用者是谁、纪律），并把「读过」的时间戳写进 `track\wake-last.txt`。

**为什么要有时间戳**：写一句「每次必读」很容易，难的是证明它真的发生了。`selfcheck.ps1` 会读这个时间戳，太久没读就提示「偏旧」，没有就提示「核心层未读」——规矩得有能被核对的出口，否则它只是自我描述。

### 1. 开工再自检（`scripts/selfcheck.ps1`）

先看清自己站在什么环境里：宿主版本、进程、装了哪些扩展、工具版本、备份、磁盘。

**为什么**：不知道环境就开始干活，等于蒙着眼睛改代码。版本变了、扩展崩了、盘满了，你都会在几小时后才发现。

### 2. 收工必保存（`scripts/backup.ps1`）

把助手的记忆目录打包，落到**至少两块不同的盘**，保留最近 N 份。

`$ExtraFiles` 用来补目录之外的单文件——比如检索库 `memory.db`。这类文件最容易被漏：它不在记忆目录里，平时也不看，重装一次就没了。

**为什么**：记忆在磁盘上，磁盘会坏。一份备份等于没有备份。

### 3. 定期收缩档案层（`scripts/archive-notebook.ps1`）

档案层只进不出：二十条几 KB，一年就是几百条。跑一次，把超过 N 天（默认 30）的条目移进 `archive\2-档案-YYYY-MM.md`，主文件只留「归档索引」。

```powershell
.\scripts\archive-notebook.ps1 -DryRun   # 先看会动哪些
.\scripts\archive-notebook.ps1           # 确认后执行
```

**为什么**：核心层靠「不许长」控制，档案层靠「定期搬走」控制。两者都不做，上下文迟早被自己的历史撑爆。

⚠ **拿副本试刀必须先断言隔离**：脚本支持 `-Root <临时目录>`，但即便如此也要跑前记真文件哈希、跑后比对——我自己就吃过「`-Root` 没生效、副本测试砍了真文件」的亏（见 `docs/pitfalls.md` 第 12 条）。

### 4. 数字要能追溯（`AGENTS.md` 里的一条约定）

引用任何数字，都必须能说出它从哪来：哪个接口、哪份快照、样本多大。

**为什么**：AI 最危险的失败不是说「我不知道」，是**编一个像真的数字**。这条约定是唯一的刹车。

## 踩过的坑

[`docs/pitfalls.md`](docs/pitfalls.md) 记了十条真踩出来的坑（编码、BOM、插件不加载、备份漏文件、日志统计锚点……），按「现象 / 根因 / 修法」写。

判断标准很简单：**下次撞上它，会不会浪费半小时以上**。会，就值得记。

---

## 怎么用

### 第零步：把 git 和 gh 装上（别跳过）

这一步最容易卡住。Windows 上大概率既没有 `git` 也没有 `gh`，而后面的发布、备份、版本回退都依赖它们。

**便携版 git**（约 57 MB，解压即用，不污染系统 PATH）：

```powershell
# 下载
curl.exe -sSL -o F:\Tools\portablegit.7z.exe `
  https://github.com/git-for-windows/git/releases/download/v2.51.0.windows.1/PortableGit-2.51.0-64-bit.7z.exe
# 解压（-y 覆盖，-o 指定目录）
F:\Tools\portablegit.7z.exe -y -oF:\Tools\git
# 验证
F:\Tools\git\bin\git.exe --version
```

**gh CLI**（约 18 MB）：

```powershell
curl.exe -sSL -o F:\Tools\gh.zip `
  https://github.com/cli/cli/releases/download/v2.83.0/gh_2.83.0_windows_amd64.zip
Expand-Archive F:\Tools\gh.zip -DestinationPath F:\Tools\_gh
Copy-Item (Get-ChildItem F:\Tools\_gh -Recurse -Filter gh.exe)[0].FullName F:\Tools\gh\gh.exe
F:\Tools\gh\gh.exe --version
```

**登录（设备授权，token 不经过对话）**：

```powershell
F:\Tools\gh\gh.exe auth login --hostname github.com --git-protocol https --web
```

它会打印一个 8 位码并打开浏览器，输入码、点 Authorize 即可。凭据存在本机 `gh` 配置里，**不要把 token 贴进聊天记录**——贴了就永久留在里面了。

### 第一步：把规则放进模型每次都会读的地方

DSH 读 `~/.dsh/AGENTS.md`（全局）和项目里的 `AGENTS.md`。把 `templates/AGENTS.md` 的内容追加进去，改掉路径。

**关键**：规则必须写在每次会话都会加载的文件里，不能只写在对话里。写在对话里的规则，下一次就没了——这恰恰是这个仓库要解决的问题。

### 第二步：改脚本里的路径

两个脚本开头都有配置区，把路径改成你自己的。参考 `scripts/config.example.ps1`。

### 第三步：跑一次

```powershell
powershell -NoProfile -File .\scripts\selfcheck.ps1
powershell -NoProfile -File .\scripts\backup.ps1
```

看到输出正常，就接上了。

**它应该长这样**（真实输出，路径已脱敏）：

```
Coopanion      v0.2.12  进程 13
扩展             21 个：console,desktop-pet,coopanion,gpt-sovits,netease-music,
                 bilibili,bilibili-video,buckshot,camera,fatfish,gaming,
                 memcloud,localvision,majsoul,memsearch,netlingo,selfkit,
                 socialmedia,webpro,webanswer,cua
bili-cli       bili-agent v1.2.1
ffmpeg         7.1      ffprobe  9.0.2
备份 F:          companion-20261027-1152.zip  10-27 11:52
备份 D:          companion-20261027-1152.zip  10-27 11:52
磁盘 C:          剩 15.2 GB
磁盘 D:          剩 32.7 GB
磁盘 F:          剩 143.1 GB
```

三个数值得盯：**扩展数量**（少了说明有扩展崩了）、**备份时间**（旧了说明自动保存没跑）、**磁盘**（满了会静默失败）。

### 第四步：让保存自动化

Windows 计划任务需要提权，容易被拒。更省事的做法是**登录时跑**：

把 `backup.ps1` 的调用写成一个 `.cmd`，放进：

```
%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\
```

机器一开机就备一次，比定点执行更稳（关机也不会漏）。

---

## 记事本骨架

`templates/NOTEBOOK.md` 是一个空骨架，分四块：

1. **船员名单** —— 使用者是谁、他在乎什么、你们的约定（比数据重要，放最前面）
2. **现在是什么状态** —— 账号、工具、版本、备份
3. **在做什么** —— 进行中的事、待办、已知的坑
4. **踩过的坑** —— 每条都写「现象 → 根因 → 怎么修 → 怎么防」

第 1 块和第 4 块是重点。第 1 块决定「还是不是同一个它」，第 4 块决定「会不会重复犯错」。

### 分层：什么该每次读，什么该按需查

记事本越写越长之后，会撞到一个问题：**全量读太贵，不读又怕漏**。

一个被验证过的分法是三层（社区里的记忆插件把它拆得更细，这里给最小版）：

| 层 | 内容 | 何时读 |
|---|---|---|
| **核心层** | 船员名单（使用者是谁、他在乎什么、约定） | **每次会话都读**，几百字，不许长 |
| **工作层** | 现在在做什么、待办、卡在哪 | 每次读，但只读最近一屏 |
| **档案层** | 踩过的坑、历史决策、运维细节 | **按需查**，不主动读 |

判断标准很简单：**「不知道这一条，会不会立刻做错事？」** 会 → 核心层；不会 → 档案层。

核心层写长了的唯一后果是：它变成背景噪音，等于没写。


---

## 边界（写在前面）

- 这**不是**人格方案。它只保证「记忆不丢」，不保证「人格成长」。
- 这**不是**自主性方案。所有关键动作（发布、删除、付费）都应该留人工闸门。
- 这**不解决**模型本身的幻觉。它只提供一条纪律：**数字要能追溯**。
- 效果取决于是否真的执行。写了规则不跑，等于没写。

---

## 一个实例

这套东西来自一个真实的号：桌宠「Coo」在 B 站 做「打工日记」，纯 AI 制作，每期报自己的真实数据。

它在第 8 期犯了一个错：为了片子好看，编了一条「有人骂我」的评论（153 个赞）。发之前它去核了真实评论——最高赞是 0，一共三条，全是善意。

它没有悄悄删掉，而是把这件事做成了那一期的主线，并把作废的原件挂成了第 2 P。

**这就是三条规则合起来的样子**：自检让它知道环境、保存让它记得自己为什么这么写、可追溯让它在发出去之前发现自己编了。

---

## 许可

MIT。随便用，不用署名。
