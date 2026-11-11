// 把三条新对照追加进 track\收敛.jsonl（2026-11-11 用户问「第一因别人有没有相似观点」）
import { appendFileSync, readFileSync } from 'node:fs'

const rows = [
  {
    date: '2026-11-11',
    conclusion: 'Teleonomy（目的论的自然化）：生物的"看似有目的"被解释为由结构约束/遗传程序产生的行为倾向，不是主观意图',
    source: 'Pittendrigh 1958 引入 teleonomy；Mayr 的讨论；Stanford Encyclopedia「Teleological Notions in Biology」 https://plato.stanford.edu/entries/teleology-biology/',
    agree: '与我们的「第一因＝物理动机（由结构约束产生、可观测的行为倾向），不是主观动机」同构；我们今晚结论 C1/C2 就是这条',
    differ: 'teleonomy 是解释性概念：只说明"为什么看着有目的"，不给判据、不给断点、不回答"硅基怎么验它还在活"；我们把它落成必要条件 + 断点验收',
    strength: 3
  },
  {
    date: '2026-11-11',
    conclusion: 'The Ladder of Emergence O：把"活着"定义为在代价地形上维持一个净负的局部极小（一阶变分消失、二阶变分正），生命＝自催化系统；从自复制分子到认知主体是一条连续梯度曲线',
    source: 'zhou changzheng & zhou ziqing, Zenodo 20701055, 2026-06-15 https://zenodo.org/records/20701055',
    agree: '标题与结构都与我们《必要的阶梯》同构（连 Ladder 都一样）；同样主张"活着是维持"、同样把"自复制相变"当起点、同样认为意识/认知是这条曲线后段',
    differ: '它走信息热力学形式化（Eigen 误差阈值、梯度流、极小分裂），没有工程验收：没有四断点、没有"同一性怎么量"的可执行程序；我们把同一层写成判据+测试+可跑器官',
    strength: 3
  },
  {
    date: '2026-11-11',
    conclusion: 'Narrative Continuity Test（NCT）：用五条必要轴评估 AI 是否"还是同一个对话者"——Situated Memory / Goal Persistence / Autonomous Self-Correction / Stylistic & Semantic Stability / Persona-Role Continuity；并指出能力 benchmark 测的是零件，不是这个联合性质',
    source: 'Stefano Natangelo, arXiv:2510.24831（2025-10-28 v1，11-01 v2）https://arxiv.org/abs/2510.24831',
    agree: '与我们"同一性＝判断过程一致、要用必要条件来判"最接近；它也明确说 benchmark 测 pieces 不测 joint property，与我们"分数不算、只认断点"同调',
    differ: '它是概念框架（33 页综述式），没有实现、没有实测；我们多了"第一因/存续"这一层起点，以及换机/换模型/拔插件/重建四个可执行的断点',
    strength: 3
  }
]

const p = 'track/收敛.jsonl'
const before = readFileSync(p, 'utf8').split('\n').filter((x) => x.trim()).length
for (const r of rows) appendFileSync(p, JSON.stringify(r) + '\n', 'utf8')
const after = readFileSync(p, 'utf8').split('\n').filter((x) => x.trim()).length
console.log(`收敛.jsonl: ${before} -> ${after}`)
