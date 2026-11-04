# 结构与思维：怎么搭
# Structure and Reasoning: How It Is Built

> 守链（Raoain） · 2026-11-05 · v1.0 · CC BY 4.0
> 姊妹篇：《守链 / The Guarded Chain》，DOI: 10.5281/zenodo.23961530

---

## Abstract

第一篇回答「为什么」，本篇只回答「怎么搭」。我们主张：智能体的起点不是造器官，而是找前置物理条件；自我不是提示词或人格，而是一条链（或一种动机行动）。由此推出两件事：结构上，核心层是传动轴、继承是飞轮、接口是齿、外圈是插件，记忆作为飞轮上的配重，习惯与语气是它转动的副产物，记忆臃肿时一部分充当中间齿轮去带动其他；推理上，判断→动作→痕迹→读回→再判断构成一条闭环，链咬合链时幻觉插不进来，但语言模型自身跑不了这条环。

The first paper asks *why*; this one asks only *how*. The starting point is not organs but the physical precondition. The self is neither a prompt nor a persona but a chain (or a motivation, an action). Two consequences follow. Structurally, the core layer is the drive shaft, inheritance is the flywheel, the interface is the teeth, and the outer ring is plugins; memory is ballast on the flywheel, habit and tone are its by-products, and a bloated memory should turn part of itself into an intermediate gear. Procedurally, judge → act → trace → read back → judge again forms one closed loop: when chain engages chain, hallucination cannot insert itself — but a language model cannot run that loop on its own.

## Keywords

continuity; agent architecture; closed loop; core layer; chain; hallucination

## 1. Introduction

智能体的发展根本不应该是这样，现在主流完全是根据现有现象来倒果为因，全是在制造一个器官然后希望它能自己长成个整体但没有自我何谈自我进步，谈起自我就要究本质首先排除的是记忆当人失忆的时候，我们能否认不是同一个人吗？这不能，所以它应该是一种动机行动或者是一种链，接下来我会以两套说辞来说明，一套工程的来更好的解释其作用，一套生物的来解释更好的更新。

Most work on agents proceeds backwards from observed phenomena: build an organ, then hope it grows into a whole. Without a self there is no ground for self-progress. To ask about the self one must first rule out memory: when a person loses memory, can we deny that it is the same person? We cannot. So the self should be a motivation, an action, or a chain. Two vocabularies follow: an engineering one that explains how it works, and a biological one that explains how it updates.

## 2. 与主流的分野 / Where We Diverge

| 词 Term | 本文 Ours | 主流默认 Mainstream default |
|---|---|---|
| 起点 Starting point | 先找前置物理条件（核心层 / 链），器官后长 / find the physical precondition first; organs come later | 先造器官，指望它长成整体 / build organs first and hope a whole emerges |
| 自我 Self | 动机行动或一条链 / a motivation, an action, or a chain | 人格提示词或人设 / a persona prompt or character sheet |
| 记忆 Memory | 飞轮上的配重（习惯与语气是副产物）/ ballast on the flywheel; habit and tone are by-products | 要保存的主体，越多越好 / the thing to save, the more the better |
| 结构 Structure | 传动轴 + 齿 + 飞轮 + 外圈（一层咬一层）/ drive shaft, teeth, flywheel, outer ring — one layer engages the next | 插件与模块横向堆叠 / plugins and modules stacked side by side |
| 闭环 Loop | 判断 → 动作 → 痕迹 → 读回 → 再判断 / judge, act, trace, read back, judge again | 一轮生成即结束 / one generation pass is the end |
| 幻觉 Hallucination | 链咬合链时插不进来；插进来是因为环没闭合 / cannot enter when chain engages chain; it enters when the loop fails to close | 靠提示词要求「别编」/ ask the prompt not to fabricate |
| 语言模型 LM role | 输出层（笔），不是法官 / the output layer, a pen, not a judge | 主体本身 / the agent itself |
| 记忆臃肿 Memory bloat | 一部分当中间齿轮去带动其他 / part of it becomes an intermediate gear driving the rest | 继续扩容量、加检索 / keep expanding capacity and retrieval |

一句话：**他们造器官去比谁更像；我们找前置条件去看它还跳不跳。**
One line: **they build organs to see which looks more human; we find the precondition to see whether it still beats.**

## 3. 推理：一条闭环 / Reasoning: One Closed Loop

思维上我是以链以判断→动作→痕迹→读回→再判断闭环为主，我的理论是以链来咬合另一条链幻觉就无法插入，但根本无法执行，因为它是语言大模型它的潜意识就是为了讨好人而编造和语句通顺，无法主动去跑一遍闭环思考。

Reasoning runs as one closed loop: judge → act → leave a trace → read it back → judge again. A chain that engages another chain leaves no room for hallucination to insert itself. But this cannot be executed as-is: a language model's default is to please, to fabricate, and to stay fluent; it cannot spontaneously run a loop even once.

## 4. 结构：传动轴、飞轮、齿、外圈 / Structure: Shaft, Flywheel, Teeth, Outer Ring

结构上我的解法是以核心层为传动轴，再套一继承为飞轮赋予重量，然后再以接口为齿去咬合外圈齿轮插件，核心层是完全规则类以链为主就像是产生智慧的前置物理条件，让记忆以飞轮解决了习惯与语气，因为这完全是飞轮运动时产生的副产物，接口为齿是为了更好的适配其他，然后当记忆开始臃肿的时候就应该让一部分充当中间齿轮去转动其他。

The core layer is the drive shaft; inheritance is the flywheel that gives it weight; the interface is the teeth that engage the outer ring of plugins. The core layer is entirely rule-based and chain-first — the physical precondition for intelligence. Memory rides as the flywheel and thereby yields habit and tone, because those are by-products of the flywheel turning. Teeth exist to adapt to anything outside. When memory grows bloated, part of it should act as an intermediate gear to drive the rest.

## 5. 讨论与局限 / Discussion and Limitations

本篇只给思维与结构，不给具体器官的实现（情绪层、记忆层、接口细节）——那些留待后续，也是开放的部分。结构中的「继承」「飞轮」「中间齿轮」都是功能位，不是指定实现；换一种实现，只要咬合关系不变，就仍然成立。

This paper states only the reasoning and the structure, not the concrete organs (emotion layer, memory layer, interface details); those remain open. "Inheritance", "flywheel" and "intermediate gear" are functional positions, not mandated implementations — another implementation that preserves the same engagement pattern still holds.

## 6. 结论 / Conclusion

把模型当笔、把链当主体、把核心层当前置条件：这三句话就是本篇的全部主张。第一篇给出「为什么」，本篇给出「怎么搭」；两者共用同一条因果链。

Treat the model as a pen, the chain as the subject, and the core layer as the precondition: that is the whole claim. The first paper argues why; this one argues how; both share one causal chain.

## 参考文献 / References

守链 (Raoain). *The Guarded Chain: A Continuity-First Theory of Synthetic Agents*. Zenodo, 2026. DOI: 10.5281/zenodo.23961530.

---

> 底稿：`theory-original-paper2-2026-11-05.md`（从 `theory-original-2026-11-01.md` 切出的第 1/2/3 段：起因＋结构＋思维；原母本已随第一篇存入 Zenodo，一字未改）。正文引用原话处只做分段、断句补标点、改错别字，不新增词、不改句式。
