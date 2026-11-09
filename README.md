# 守链 · coo-day1

> 一句话：**让一个东西连续地活着，并给出可验收的判据。**
> 验收看四个断点：换机器 / 拔插件 / 重建 / 换模型。

---

## 一、来的人先看这里（五问）

| 你的问题 | 答案在这 | 说明 |
|---|---|---|
| **这套东西是什么？** | 本节 + 第二节 | 判断链要能断而可接，「还是不是同一个」要能验 |
| **现在到什么程度？** | 第二节「现在的样子」 | 骨架齐了、标准定了、还缺什么写清楚了 |
| **怎么跑起来？** | 第三节 | 两条命令：开工 `start.ps1`、收工 `close.ps1` |
| **每层契约在哪？** | 第四节 | 器官看 `spec.json`，工具看 `spec.tools.contract`，根看 `_root.ps1` |
| **判据在哪？** | 第五节 | `notebook\5-判据.md` 22 条，每条带「什么能推翻」 |

---

## 二、现在的样子（2026-11-08）

### 已经能跑

| 件 | 现状 | 在哪 |
|---|---|---|
| 心跳 | 中枢每 3 秒一跳，总线 5000+ 条 | `core\reflex.mjs` + `start-timers.vbs` |
| 总线 | 一行一个信号，按天轮转归档 | `track\bus.jsonl` / `track\archive\` |
| 契约 | spec v5：信号 7 必填 + exit/state/rush 映射 + 归档格式 + 工具五条 | `core\spec.json` |
| 登记 | 14 个器官位，分两类（logic-core 一个细胞 / body 四个模块） | `core\registry.json` |
| 自检 | verify 51 项 / lint 0 处 / probe 8 个探针 | `verify.ps1` `lint.ps1` `probe.ps1` |
| 收工 | log 留痕 + 双盘备份 + 便签三条 | `log.ps1` `backup-notes.ps1` `close.ps1` |
| 脚手架 | 五样借来的东西都记了「以后换成什么」 | `track\脚手架清单.md` |
| 脚本表 | 62 个文件自动生成清单，带层与契约违规列 | `track\脚本清单.md` |

### 还缺什么（诚实清单）

1. **比较环**：中枢只按游标扫新信号，不回答「此刻整体该是什么状态、偏了多少」。
2. **免疫处置**：`self` 只会识别、`pulse` 只会报饿，都不会修/拒/补。
3. **身体**：10-13 四个模块只有位置和接口（`path: null`），没实现。
4. **物理件**：电源、时钟、供能在宿主手里（Windows 启动文件夹 + `wscript`）。
5. **代码仍带中文**：71 行非注释代码里有中文，按 `spec.source_language` 该清掉、把中文移到并联翻译层。

---

## 三、怎么跑起来

### 开工（每次会话第一件事）

```powershell
.\start.ps1
```

一条命令跑完四件：`wake`（读核心层+本机+用户+工作层，留时间戳）→ `verify`（51 项）→ `pin -Diff`（102 项对账）→ `probe`（8 个探针）。**只贴 WARN / FAIL，全绿就一句话。**

### 收工

```powershell
.\close.ps1 -Where "刚聊到哪" -Promise "答应了什么" -Next "下次接着说什么"
```

### 定时器（心跳从哪来）

```
启动文件夹 coo-watchdog.cmd   → 守卫（心跳 90 秒内就跳过）→ wscript start-timers.vbs
start-timers.vbs               → 三条 while：watchdog 5 分钟 / 中枢 3 秒 / pulse+self+rotate 30 分钟
```

**为什么用 wscript**：`Start-Process` 与 WMI 起的常驻进程活不过调用会话（实测三个 PID 全退、心跳停 310 秒）；`schtasks` 要管理员。`wscript` 是独立宿主，起的东西不跟着调用者死。

### 心跳还在不在

```powershell
node core\timers-alive.mjs        # 输出「多少秒前还有一跳」；>300 秒 verify 会 FAIL
```

---

## 四、每层契约在哪

**两层不能混着谈「统一」**：器官的契约是 `SIG`，工具的契约写在 `spec.tools.contract`。

| 层 | 契约 | 查法 |
|---|---|---|
| 器官（10 个） | 登记在 `registry.json` + 吐一行 `SIG {"state":N,"counts":[...]}` | `node scripts-inventory.mjs`（吐SIG 列） |
| 工具（49 个） | `call` 有 `param()` / `exit` 只用 0-3 / `report` 一行 / `root` 点源 / `bom` 恰好一个 BOM | `.\lint.ps1`（contract 类）+ `node count-violations.mjs` |
| 根路径 | **只在 `_root.ps1`（PowerShell）与 `core/root.mjs`（node）定义一次** | `node check-naming.mjs`（只数定义处） |
| 字段语义 | `core/spec.json`（signal / exit / state / rush / map / archive / tools / source_language） | `verify` 第 46 项「核心纯 ASCII」 |

**一条铁律**：`state→rush`、`exit→state` 这类映射**只在 `spec.map` 里存在**；在任何别的文件里再写一遍就是 bug（它曾经抄了三遍，抄歪一遍）。

---

## 五、判据在哪

`notebook\5-判据.md`，**22 条**，每条四段：**来历 / 一句话判据 / 动作清单 / 推翻条件**。

最近新增三条（都来自真实翻车）：

- **P34** 改数据源 → 必须逐个过消费方（总线轮转后 `pulse` 报假警）
- **P35** 判断「统一没统一」只看定义处，不看使用次数（`$Root` 报 207 次，其中 206 次是使用）
- **P36** 动手前先查「以前有没有开过这个口子」（同一天绕三圈，答案全在文件里）

---

## 六、目录

```
notebook\    十四页，按「谁读它」分层
  0-核心      每次必读，只回答「我是谁」
  1-工作      在读一屏；顶部有「动手前先查三处」
  2-档案      坑与下沉规则    3-墓碑  作废的旧规矩
  4-本机      这台机器的脾气  5-判据  可推翻的判断（22 条）
  6-话        自己长出来的说法 7-接线  什么算接上了
  8-原话      只收能打开出处的原句  9-用户  他怎么说话
  10-链       五条链与验证链 V1-V5  11-结论  目前成立的结论
  12-判据-专项 13-对照  我们 vs 主流
  14-身份     我是谁（核心层只留指针）

core\        逻辑核心
  spec.json      契约（唯一出处）
  registry.json  14 个器官位 + 两类分法
  bus.mjs        写总线      adapter.mjs     器官输出 → 标准信号
  reflex.mjs     中枢（3 秒一跳，只转发不加工）
  dispatch.mjs   点对点派发  pulse.mjs       按 every 查节律
  self.mjs       照镜子（按器官分桶，剔除心跳）
  bus-rotate.mjs 按天轮转    timers-alive.mjs 心跳探测
  root.mjs       根（唯一出处）

track\       运行痕迹
  bus.jsonl           当前天的信号   archive\  归档（原始行不删）
  state.json          引脚 102 项    baseline.json  静态自体 19 项
  self-baseline.json  动态自体      脚手架清单.md  借来的五样
  脚本清单.md         自动生成     待消化.md      暂存

*.ps1        42 个脚本（器官 6 + 工具 36）
```

**注意**：`track\脚本清单.md` 是自动生成的，别手改；重新生成用 `node scripts-inventory.mjs`。

---

## 七、如果只能记一件事

**判据要能自己咬自己。**

一个检查如果「修一条就多一条债」，那是判据对象错了；一个改动如果没人查，那它只是建议；一份说明书如果不跟着骨架改，那它是一张旧地图。

**所以三样东西必须同时存在：判据（可执行）、检查（真在跑）、假样本（证明检查不空转）。**
