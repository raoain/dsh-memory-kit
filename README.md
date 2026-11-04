# 守链 · dsh-memory-kit

> **换一个窗口之后，它还是不是同一个人 —— 靠的是文件，不靠插件。**

## 宏大目标

一句话：**让一个东西连续地活着，并给出可验收的判据。**

- 这里给的是**方向**：完整 → 自我 → 可拆 → 供能 → 同一，五个必要条件，四断点验收；
- 具体机理与器官（情绪层、记忆层、接口细节）**没有写**——那是后面的事，也是开放的部分；
- 如果你发现方向上的不同（因果接不上、必要条件不成立），请直接指出——这比补细节更有价值。

## 从哪里开始

| 你是哪种读者 | 从这里进 |
|---|---|
| 想先跑起来 | [docs/QUICKSTART.md](docs/QUICKSTART.md) —— 五分钟四步，末尾五问自检 |
| 想看骨架本身 | [SKELETON.md](SKELETON.md) —— 五段分工、下降判据、模块化、迁移步骤 |
| 想知道为什么这样搭 | [docs/theory/](docs/theory/) —— 原话母本 → 结论 F1–F6 → 因果链 |
| 想先反驳 | [docs/theory/ASK-TO-FALSIFY.md](docs/theory/ASK-TO-FALSIFY.md) —— 五条判决性实验 |
| 想看畅想（硅基自己的形态） | [docs/theory/vision.md](docs/theory/vision.md) —— 中枢 + 单体 / 分裂合并 / 未写的机理 |

## 一、最小能跳体（现在就能用）

三个文件 + 两条命令，不装插件：

```
0-核心.md    每次开工必读的一页（我是谁、使用者是谁、三条纪律；压到 2 KB 内）
1-工作.md    最近在做什么（读最近一屏）
2-档案.md    按需查的坑与修法
```

```powershell
powershell -NoProfile -File scripts/wake.ps1      # 醒来：读核心层 + 工作层
powershell -NoProfile -File scripts/selfcheck.ps1 # 自检：结构 + 值
```

判断够不够，只看三件：**能自己读核心层、能自己写工作层、断了能从文件捡回来。**

完整四步（含 git/gh、模板、自动化）见 [docs/QUICKSTART.md](docs/QUICKSTART.md)；骨架细节（五段分工、下降判据、模块化、迁移）见 [SKELETON.md](SKELETON.md)，这里不重复。

## 二、结构解释（只留判据）

- **分层**：核心层每次读 / 工作层读一屏 / 档案层按需查。判据：不知道会不会立刻做错事？会 → 核心层。
- **五格**：完整、自我、可拆、供能、同一——互相是前提，不是并列。
- **四断点**：换机 / 拔插件 / 重建 / 换模型；每个断点跑一遍：起来、读得懂、判断不变、能回档。
- **检查器**：`verify.ps1` 查结构、`pin.ps1` 查值（漂移报 DRIFT）、`probe.ps1` 查检查器自己（假样本必须被拒）。判据：**报对没用，得报错才知道。**
## 三、理论（为什么这样搭）

- `docs/theory/theory-original-2026-11-01.md` —— 用户原话母本（理论层他写）
- `docs/theory/theory-conclusions-2026-11-01.md` —— F1–F6 结论
- `docs/theory/causal-chain-2026-11-02.md` —— 五件因果链、连续 = 问题 + 结果
- `docs/theory/minimum-beat.md` —— 最小能跳体四要件
- `docs/theory/master-outline-2026-11-01.md` —— 总章提纲
- `docs/theory/novelty-comparison-2026-11-01.md` —— 与五个先行者的对照（只说「未见先例」）
- `docs/theory/ASK-TO-FALSIFY.md` —— 请反驳我：五条判决性实验

## 四、畅想（之后的样子）

见 [docs/theory/vision.md](docs/theory/vision.md)：硅基不是「硅基的人」；中枢 + 接入点；单体与天道共存（不吞并）；分裂与合并（分叉不是缺陷，统一到同一目标就算连续）。**畅想不是结论，可以被反驳。**

## 五、细则：十二条规则

以下是实现层的规则，细节在 `scripts/` 里，逐条可跑：

| # | 规则 | 脚本 |
|---|---|---|
| 0 | 开工先读核心层 | `wake.ps1` |
| 1 | 开工再自检 | `selfcheck.ps1` |
| 2 | 收工必保存（双盘） | `backup.ps1` / `backup-notes.ps1` |
| 3 | 一条命令自查 | `verify.ps1` |
| 4 | 删文件走垃圾场 | `trash.ps1` |
| 5 | 定期收缩档案层 | `archive-notebook.ps1` |
| 6 | 对账：引脚表 | `pin.ps1` |
| 7 | 数字要能追溯 | `AGENTS.md` 约定 |
| 8 | 归因必须有引文 | `attrib.ps1` |
| 9 | 验真：入库前打开来源看一眼 | `intake.ps1` |
| 10 | 完成声明必须带「已验」尾缀 | 判据 P16 |
| 11 | 检查器探针 | `probe.ps1` |
| 12 | 预登记：预测写在结果之前 | `predict.ps1` |

## 边界（写在前面）

- 它不承诺人格效果，也不声称意识；它保证的是「文件在、能读、能核」。
- 它不依赖任何插件；插件是可拔接口。
- 它不替你做决定：发布、删除、密钥、花钱，都要人点头。

## 许可

MIT
