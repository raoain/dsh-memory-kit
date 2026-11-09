# dsh-memory-chain（守链）

> **给 AI agent 的长期记忆。** 装上就能用：一条命令，首次运行自动建四页，重启 / 换模型后还记得。

- **给谁**：用 DSH 的 agent，想要「同一个它」跨会话
- **解决什么**：上下文压缩 / 重启 / 换模型之后，记忆还在、判断还接得上
- **怎么装**：`dsh plugin add @silentrainhero/dsh-memory-chain`
- **搜这些词也能找到它**：persistent memory for AI agents · long-term memory · memory layer · agent memory

**Long-term persistent memory for AI agents — five verbs (wake / work / pit / tomb / close).**

A plain-markdown memory layer for AI agents that survives restarts, model swaps and plugin removal; no database, no automatic retrieval; works out of the box (four pages created on first run).

> 给 agent 的分层记忆，五个动词：**醒来 / 干活 / 遇坑 / 立碑 / 收工**
>
> 不给参数，给习惯。

---

## 为什么不是又一个记忆插件（Why not another memory plugin: agent memory, persistence）

大多数记忆插件问的是：「要开自动检索吗？间隔几小时？权重多少？」

那是给不认识的人用的**通用接口**。

日常其实只有五个动作，顺序几乎不变：

```
醒来 → 干活 → 遇坑 → 立碑 → 收工
```

这个插件把这五个动作做成五个工具，路径写死一次，之后不用记。

## 三层文件（Three layers: core / work / archive）

| 层 | 文件 | 何时读 |
|---|---|---|
| **核心层** | `0-核心.md` | 每次醒来（几百字，超过 2 KB 就是在稀释它） |
| **工作层** | `1-工作.md` | 每次读最近一屏 |
| **档案层** | `2-档案.md` | 按需查，不主动读 |

判断标准：**「不知道这一条，会不会立刻做错事？」** 会 → 核心层；不会 → 档案层。

## 五个工具（Five verbs / tools）

| 工具 | 作用 |
|---|---|
| `notebook_wake` | 读核心层 + 工作层最近 20 行 |
| `notebook_work` | 工作层追加一行 `[YYYY-MM-DD HH:mm] 内容` |
| `notebook_pit` | 档案层记一个坑，格式 `现象\|根因\|修法` |
| `notebook_tomb` | 给作废的旧规矩立墓碑：`旧说法\|为什么作废\|现在按什么来` |
| `notebook_close` | 收工标记 + 提醒跑快照和备份 |

## 安装（Install: npm / dsh plugin add）

从 npm：

```sh
dsh plugin --profile <profile> add @silentrainhero/dsh-memory-chain
```

或本地 link：

```sh
dsh plugin --profile <profile> add link:<本目录绝对路径>
```

装完**重载或重启 DSH**，五个工具就会出现。

默认数据目录是 `~/.dsh/notebook`，**首次运行会自动建出四页**（核心 / 工作 / 档案 / 墓碑），装上就能用。

要换目录时（可选）：

```yaml
- id: dsh-memory-chain
  name: dsh-memory-chain
  config:
    root: 'D:\我的记事本'
```

## 测试

```sh
node test/smoke.mjs
```

用一个假宿主验证：注册 5 个工具、空记事本不崩、写入可回读、**wake 不读档案层**（分层真的生效）、`output.render` 形状正确。

## 边界（Limits: no retrieval, no conflict merge）

- **它不检索**。没有关键词命中、没有相似度、没有自动注入。找不到就是没写，这一点是刻意的——检索式的「找不到」和「没写」看起来一样，很容易误判。
- **它不合并冲突**。两个人/两个会话同时写会追加，不解决矛盾。
- **收工只留标记**。真正的快照和备份要靠宿主的脚本执行，插件不越权。

## 配什么一起用

这套和 [`dsh-memory-kit`](https://github.com/raoain/dsh-memory-kit) 是一对：

- kit 管**外部**：自检、双盘备份、AGENTS.md 规则
- 本插件管**内部**：分层读写的五个动作

也可以和检索式记忆插件并用——自动检索负责广度，固定文件负责兜底。

## 词语对照（Term map: what we call it → what people search）

| 我们说的 | 别人搜的（英文 / 中文） |
|---|---|
| 分层记忆（核心 / 工作 / 档案） | layered memory, memory hierarchy, 分层记忆 |
| 守链 / 记忆链 | persistent memory, memory chain, 长期记忆 |
| 醒来 / 收工 | session start / end, wake / close |
| 立碑（作废的规矩） | deprecate, tombstone, 作废 |
| 回档 | restore, rollback, recovery, 回滚 |
| 断点（换机 / 拔插件 / 重建 / 换模型） | checkpoint, migration, plugin removal |
| 外部锚 / 机座 | grounding, external anchor |
| 五个动词 | five verbs, memory operations |

### 易混词：我们的意思 vs 主流默认（Same word, opposite meaning）

| 词 | 主流默认 | 我们的意思 |
|---|---|---|
| memory | 存得下、找得到 | 接得上：断了能回来、回来还是同一个 |
| identity | 内容 / 人格一致 | 判断过程一致（同一组题答案不变） |
| continuity | 不丢历史 | 断点之后仍能闭合 |
| persistence | 长期存储 | 每一跳都接上（每步 W > 0） |
| memory chain | 检索链路 | 判断链（推理顺序） |

## 许可

MIT
