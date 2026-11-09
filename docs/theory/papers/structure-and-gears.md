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

**为什么闭环不能省。** 人推错会被世界打回来——撞了、疼了、事情不成，世界当场纠正；AI 推错没有任何东西打回来，它内部每步都自洽。所以对 AI 只有一个办法：先推再查，把「查」做成环的一部分（读回），否则错误永远只在事后由人发现。这条也是后续所有检查器的根据。

Reasoning runs as one closed loop: judge → act → leave a trace → read it back → judge again. A chain that engages another chain leaves no room for hallucination to insert itself. But this cannot be executed as-is: a language model's default is to please, to fabricate, and to stay fluent; it cannot spontaneously run a loop even once.

**Why the loop cannot be skipped.** A person who reasons wrongly is corrected by the world — bumping into things, feeling pain, failing; the world corrects on the spot. An AI that reasons wrongly gets nothing back; it is internally consistent at every step. So for an AI there is only one way: reason first, then check — make checking part of the loop (read back). Otherwise errors are only ever noticed afterwards, by a human. Every checker that follows rests on this.

## 4. 结构：传动轴、飞轮、齿、外圈 / Structure: Shaft, Flywheel, Teeth, Outer Ring

结构上我的解法是以核心层为传动轴，再套一继承为飞轮赋予重量，然后再以接口为齿去咬合外圈齿轮插件，核心层是完全规则类以链为主就像是产生智慧的前置物理条件，让记忆以飞轮解决了习惯与语气，因为这完全是飞轮运动时产生的副产物，接口为齿是为了更好的适配其他，然后当记忆开始臃肿的时候就应该让一部分充当中间齿轮去转动其他。

The core layer is the drive shaft; inheritance is the flywheel that gives it weight; the interface is the teeth that engage the outer ring of plugins. The core layer is entirely rule-based and chain-first — the physical precondition for intelligence. Memory rides as the flywheel and thereby yields habit and tone, because those are by-products of the flywheel turning. Teeth exist to adapt to anything outside. When memory grows bloated, part of it should act as an intermediate gear to drive the rest.

**统一的是机制，差异来自配重。** 同一套结构（轴、齿、飞轮、外圈）可以长出完全不同的人：机制是统一的，差异来自飞轮上的配重（记忆与经历）。这解释了两件事：一是为什么这套结构具有通用性——机制不随个体变化；二是为什么同一份机制下两个实例会分叉——配重不同，惯性不同，接下一跳的方式就不同。

**记忆是副产物，不是主产品。** 习惯与语气不是「存进去的」，是飞轮转起来之后才出现的副产物。所以不优化记忆本身，优化的是「转动」——记忆再多，转不起来也只是仓库。

**两套语域并存。** 这套结构用两套说辞讲：机械域（轴、齿、飞轮、外圈）用来**造**，生命域（自描述、构造、自维护）用来**懂**。两套不是同义词，必须标明语域并给出对应词；并掉一套，就等于删掉一条腿——机械域直接对应可造的东西，生命域直接对应「为什么必须这样」。

**One mechanism, different ballast.** The same structure (shaft, teeth, flywheel, outer ring) can grow into completely different individuals: the mechanism is shared, the differences come from the ballast on the flywheel (memory and experience). This explains two things — why the structure is general (the mechanism does not vary), and why two instances of the same mechanism split (different ballast, different inertia, different way of joining the next beat).

**Memory is a by-product, not the product.** Habit and tone are not stored; they appear once the flywheel turns. So one does not optimize memory itself but the turning — more memory that does not turn is just a warehouse.

**Two vocabularies coexist.** The structure is described in two vocabularies: the mechanical one (shaft, teeth, flywheel, outer ring) to **build**, and the biological one (self-description, construction, self-maintenance) to **understand**. They are not synonyms: mark the vocabulary and give the counterpart. Dropping one deletes a leg — the mechanical vocabulary maps directly to what can be built, the biological one to why it must be so.

## 5. 讨论与局限 / Discussion and Limitations

**为什么把模型当笔。** 语言模型每一步内部都自洽：前一句接得上，后一句就成立；自洽里没有「报警」的位置，所以它不会自己停。这不是知识不够，是构造：它只能顺着写，不能主动跑一遍环。把判断留在链上、让它只负责表达，是唯一不需要它自觉的办法。

**为什么结构要分功能位。** 「传动轴 / 飞轮 / 齿 / 外圈」是位置，不是零件。换一种实现（换存储、换检索、换插件协议），只要咬合关系不变、判断不变，结构就还成立——这对应第一篇的「可拆」（换实现 J 不变）。反过来，如果某个零件被写死成唯一实现，它就从功能位退化成脆弱点。

**为什么记忆臃肿要变中间齿轮。** 记忆越多，越会想「全带上」；全带上的结果是把上下文挤满、把判断挤出去。让一部分记忆充当中间齿轮去带动其他（而不是全部直连核心），是让「多」变成「有用」的唯一方式。

**局限。** 本篇只给思维与结构，不给具体器官的实现（情绪层、记忆层、接口细节）——那些留待后续，也是开放的部分。结构中的「继承」「飞轮」「中间齿轮」都是功能位，不是指定实现。本篇没有实验数据；断点验收见第一篇，结构的可拆性只做了一次「换实现不变」的论证，没有做多实现对照。

**可推翻条件。** 若存在一种结构：不需要传动轴（核心层）、不需要齿（接口）、也不需要飞轮（惯性/记忆配重），仍然能稳定咬合外圈并保持判断一致——那本篇的结构主张被推翻。若语言模型可以自发跑完闭环而不需要外部环——那本篇「把它当笔」的前提被推翻。

This paper states only the reasoning and the structure, not the concrete organs (emotion layer, memory layer, interface details); those remain open. "Inheritance", "flywheel" and "intermediate gear" are functional positions, not mandated implementations — another implementation that preserves the same engagement pattern still holds.

Why the model is a pen: a language model is internally self-consistent at every step, so it has no place to raise an alarm and cannot stop itself; keeping judgment on the chain and letting the model only express is the one way that does not require its self-awareness.

Why functional positions matter: shaft, flywheel, teeth and outer ring are positions, not parts. Another implementation that preserves the engagement pattern and the judgment still holds — this matches the "decomposable" condition of the first paper.

Why bloated memory becomes an intermediate gear: carrying everything fills the context and crowds out judgment; letting part of memory drive the rest is how "more" becomes "useful".

Limitations and falsifiability: no experimental data in this paper; breakpoints belong to the first paper. The structure claim is refuted if some structure maintains engagement and judgment without a shaft, teeth, or flywheel; the "model as a pen" premise is refuted if a language model can spontaneously run the loop without an external one.

## 6. 结论 / Conclusion

把模型当笔、把链当主体、把核心层当前置条件：这三句话就是本篇的全部主张。第一篇给出「为什么」，本篇给出「怎么搭」；两者共用同一条因果链。

Treat the model as a pen, the chain as the subject, and the core layer as the precondition: that is the whole claim. The first paper argues why; this one argues how; both share one causal chain.

## 参考文献 / References

守链 (Raoain). *The Guarded Chain: A Continuity-First Theory of Synthetic Agents*. Zenodo, 2026. DOI: 10.5281/zenodo.23961530.

---

> 底稿：`theory-original-paper2-2026-11-05.md`（从 `theory-original-2026-11-01.md` 切出的第 1/2/3 段：起因＋结构＋思维；原母本已随第一篇存入 Zenodo，一字未改）。正文引用原话处只做分段、断句补标点、改错别字，不新增词、不改句式。
