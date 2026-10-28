# claude-subagent-routing

[English](README.md) | **中文** | [日本語](README.ja.md)

> **2026-10-28 起是 v2**：默认主线程自己干，只按上下文、只在三种情况下派子 agent。[改了什么、为什么改 ↓](#v2) 标 **v1** 的各节（2026-07-09 → 10-27）作为数据和方法论保留。

Claude Code 子 agent 的静态模型路由：一张策略表、两个钉死模型的 agent、一个 deny hook（逻辑约 15 行）。没有分类器、没有代理层、没有框架——外加 26 天单人生产实测（n=1）。

对 Claude Code 这个角落还不熟？一口气版本：Claude Code 干活时会悄悄雇一些帮手 AI——*子 agent*——去做搜代码、批量改文件这类边角活。默认情况下，每个帮手都按你主会话的模型计费。主模型贵，就等于拿高级工程师的时薪付实习生的活，而且屏幕上什么都不会提示。这个 repo 把实习生的活钉到实习生价位的模型上，并在失误面前加一道闸。你的用法不变；账单变。

<a id="v2"></a>
## v2（2026-10-28）：默认主线程自己干，按上下文才派

**现在的规则**：主线程自己干。只有三种情况才自动派子 agent，派时当场钉死模型档：

| 情况 | 长什么样 | Agent · 档位 |
|---|---|---|
| 1. 独立视角 | 冷读、画像 / persona 审计、盲评、review | `judge`——冷读、单文件审、文案审显式标 sonnet；多源综合和架构 / 跨文件 review 走它钉死的 opus |
| 2. 并行扇出 | ≥3 路互不依赖、每路回紧凑结果（分路调研、分块打标） | 整批同一档，派之前先定档 |
| 3. 大批量机械活 | spec 一两句说得清、产出远大于 spec、不需要主线程上下文（批量改名、格式整理、分块打标、搬运） | `worker`——纯体力活显式标 haiku |

**不派**：和主线程上下文强耦合的实现活——刚讨论完方案就改代码、改原型。**拿不准**：小活主线程直接干；大活先问用户一句，带上倾向。需要 shell 或大范围搜索的只读侦察交给内置 Explore agent 并标 haiku；`scout` 归档。

「小活直接干、大活才问」取代了最初的提案「拿不准都问」：拿不准时留在主线程，最坏只是一段产出贵一倍，打断用户更贵。规则特意写成可对照的清单——v1 的轻 / 重判断分流交给裁量时漂过（同一批调研被拆成两档派）。

**为什么改**

- **触发**：Anthropic〈[Building agents: when to fold subagents into your main agent loop](https://claude.com/resources/articles/building-agents-when-to-fold-subagents-into-your-main-agent-loop)〉（Diane Sarkis，2026-10-22）。核心论点：按问题类型拆 agent 会像传话游戏一样失真，该按上下文拆。子 agent 只在三种情况下站得住：需要验证 / 独立视角、并行扇出、防主线程上下文被撑爆。文章不讲大小模型路由，下面的价格账是我自己的。
- **价差缩了。** v1 设计时主线程跑 Fable（$10/$50，Sonnet 的 5 倍）；现在主线程是 Opus 5.5（$4/$20，Sonnet 的 2 倍）。外包机械活的省钱空间少了一半多，交接成本——写 spec、子 agent 从零读上下文、主线程复核——一分没少。
- **v1 的账只算了一边。** 42 天少烧的 48%（$1,166）只算了子 agent 单价，交接、复核、返工都没算，质量也一直没有客观仪表（见下文「已知开口」）。
- **策略段越堆越像 Frankenprompt（缝合怪 prompt）**——档位表、例外、带日期的教训全塞在一节里。

**v1 派发数据说了什么**（近 21 个活跃日共 691 次派发，按关键词粗分，类别有重叠）：冷读 / 画像 / 视觉审 ~287、盲评 / review ~108、多源调研 ~77——本来就是按上下文拆的，保留。`worker` ~102：约一半是分块批量（合理），另一半是主线程讨论完方案再交出去的实现活（`Implement twostep v2`、`Rebuild flow mock`）——正是文章说的按类型拆。`scout`：17 次。

**沿用 v1 的**：hook 照样打回没标 model 的派发，`judge` 照样在 frontmatter 钉 opus，便宜档砸一次照样直接升一档——绝不同档重试。

**本 repo 的改动**：[策略段](policy/claude-md-block.md)重写（v1 留在 [policy/claude-md-block-v1.md](policy/claude-md-block-v1.md)）；[`worker`](agents/worker.md) 收窄到大批量机械活；`scout` 移到 [agents/archive/](agents/archive/scout.md)；[hook](hooks/agent-model-guard.sh) 的拒绝信息改成先问「该不该派」再给路由。

**v2 给方法论加的一条**：算总账——主线程加子 agent 加返工——不只看子 agent 单价。

**复测（2026-11-11 前后）**：同一套 jq 口径，这次**主线程和子 agent 合算一本账**，再加返工次数（升档重派 + 主线程修子 agent 产出），和 v1 的 8/12–8/19 窗口对比。总账变贵且返工没降，就回退 `worker` 那条。

**v1 账单**（7/3–8/3：6 天路由前基线 + 26 天系统运行——497M 子 agent token，单用户混合真实负载；细账见[审计命令](audit/audit-commands.md)）：

| 指标 | 路由前 (7/3–7/8) | 钉档期 (7/9–7/15) | 加固期 (7/16–8/3) |
|---|---|---|---|
| 单位成本，$ / 百万 token | 3.98 | 1.94 | **1.31** |
| 前沿模型（Fable）占子 agent token 比例 | 41.5% | 29% | **0.28%**（19 天 7 个 assistant turn，全部来自点名派发） |
| `scout` 单次平均输出 | — | 282 tok | 167 tok（`effort: low`，−41%） |

**这个 repo 适合谁**：你的 Claude Code 主线程跑 Opus 或 Fable，且日常有活派给子 agent——在我的加固期窗口里，子 agent 占总输入输出流量约 15%，落在哪个模型上就按哪个计费。主线程本来就只用 Sonnet 的话，star 收藏方法就好，省不了几个钱。装之前先花 30 秒看自己的模型构成：[audit §2](audit/audit-commands.md) 一条命令粘贴即可。

累计：比旧配比少烧约 **$1,100**——实际 $882 vs 反事实 $1,978（497M token × 基线单价 $3.98；数量级参考，不是发票）。单用户、订阅额度按 API 牌价折算，质量只有自述：26 天日常使用我感觉不出和全程单模型的区别。其余细账——当期价格、cache 系数、分母里到底装了什么——全放在[审计命令](audit/audit-commands.md)旁边，每个数字都能拿你自己磁盘上的转录重跑。

## 没人审计的那个默认值

Claude Code 的子 agent 在 agent 定义没钉模型、派发时也没显式传 `model` 的情况下，会继承会话模型。主线程是 Sonnet 时这个默认无害；主线程是 Opus 或 Fable 时，每一次「帮我 grep 一下」的扇出都按前沿模型价格计费。

这不是小众抱怨。[anthropics/claude-code#27665](https://github.com/anthropics/claude-code/issues/27665) 记录了一位 Max 订阅用户 17 天 **93.8% 的 token 走了 Opus（按牌价 $1,246）**，因为默认管线里没有任何向下分流的机制——而这个 issue 提的第一条补救恰好就是本 repo 的主题：别让子 agent 默认继承昂贵的会话模型。截至 2026-08-03，issue 开放中，无官方回应。

我自己的版本：路由表 7 月 9 日上线，留了一个软肋——判断档写的是「继承主线程」，写这条规则时主线程还是 Opus。而那时我的日常主力已经换成 Fable 5（$10/$50——Opus 的 2 倍）。没有报错，没有警告。第 6 天的首次验收审计发现，Fable 子 agent 占了该窗口 **31% 的子 agent token、73% 的子 agent 支出**——比完全未路由的基线（41.5%，表中路由前一列）低，但仍是最大的单项，全靠一条过时假设撑着。当天：判断档钉死显式 opus，hook 上线。（表中钉档期的 29% 是整整 7 天的均值——第 7 天已在钉死之后，把均值拉到了第 6 天审计的 31% 以下。）

## Prior art，诚实版

这个细分赛道有真项目。但我哪里都没找到的东西：生产环境数字。

| 项目 | 是什么 | 强制机制 | 额外分类器 | 公开实测 |
|---|---|---|---|---|
| [pilotfish](https://github.com/Nanako0129/pilotfish) | 8 个角色 agent，frontmatter 钉模型，编排策略 | 无——纯劝导；README 自述安装不保证委派 | 无 | 引用厂商 benchmark，非自测生产数据 |
| [oh-my-claudecode](https://github.com/yeachan-heo/oh-my-claudecode) | 大型多 agent 编排套件 | 未见文档化 | 无 | 宣称省 30–50%；未找到数据 |
| [claude-model-router-hook](https://github.com/tzachbon/claude-model-router-hook) | 3 个 hook；给 prompt 分类、改写派发 | 改写 spawn 参数 | 关键词启发式 + 可选 Haiku 兜底 | 无 |
| [claude-model-router](https://github.com/junoseong/claude-model-router) | API 路由器 + 一个 deny 式 Claude Code hook | Deny + 重派 | LLM（Haiku）分类器 | 合成 1000 prompt 成本模型 + 17 条实测 |
| 审计工具（[ccost](https://github.com/toolsu/ccost)、[token-dashboard](https://github.com/nateherkai/token-dashboard) 等） | 本地转录成本分析 | — | — | 只量支出；不知道你的策略 |

*调研于 2026-08-03，基于各项目公开 README——时点性结论；欢迎开 issue 纠错。*

所以：框架层路由但不强制，hook 层强制但带分类器，审计层测量但不路由。这个 repo 是缺失的那个组合——**策略 + 强制 + 测量，无分类器**——外加账单。

## v1 系统本体：三层防线 × 二维路由

*v1，2026-07-09 → 10-27。现行策略是 [v2](#v2)；下面是被它取代的按角色路由，也是上面账单量的那套。*

**第一层——路由表**（[policy/claude-md-block-v1.md](policy/claude-md-block-v1.md)），粘进 `CLAUDE.md`：

| 活的类型 | Agent | 模型 | Effort |
|---|---|---|---|
| 只读侦察（扫/搜/读/汇总） | [`scout`](agents/archive/scout.md)（v2 已归档） | haiku | low |
| 机械执行（方案已定，只差动手） | [`worker`](agents/worker.md) | sonnet | medium |
| 判断（review / 设计 / 调研） | [`judge`](agents/judge.md) | opus（钉死） | 会话 |

模型钉在 agent frontmatter（agent 文件顶部的设置块）里，没人想着这张表时它也在生效。第二个维度比看上去重要：仅 `effort: low` 一项就把 scout 的输出 token 砍了 41%，侦察类活感知不到质量损失。

**第二层——判断档内分流，由编排者自己做。** 轻判断（单文件 review、文案审、二选一）派 `judge` 时显式降档 sonnet；重判断（架构、跨文件 review、开放式设计）直接吃 `judge` 的默认 opus；拿不准就不标——现在不标也稳稳落在 opus。这就是系统里的「动态路由」部分，且完全不需要基建——见下文。

**第三层——机械闸**（[hooks/agent-model-guard.sh](hooks/agent-model-guard.sh)）——一个 PreToolUse hook，即 Claude Code 在放行工具调用之前先跑的一段脚本。Claude 雇帮手时没说用哪个模型，hook 就把请求**打回**，拒绝信息里附上路由表；Claude 带上模型重发。规则防习惯，闸防失误。

让便宜档保持诚实的升级规则：便宜档砸一次，直接升一档重派。绝不同档重试。

## 安装（v2）

三个文件、一条 settings 配置、一段策略文本。在本 repo 的 clone 里执行（hook 依赖 `jq`——先 `command -v jq` 确认）：

```bash
mkdir -p ~/.claude/agents ~/.claude/hooks
cp agents/worker.md agents/judge.md ~/.claude/agents/
cp hooks/agent-model-guard.sh ~/.claude/hooks/ && chmod +x ~/.claude/hooks/agent-model-guard.sh
```

`~/.claude/settings.json` 里——**已有 `hooks.PreToolUse` 数组的话请合并进去，别整文件覆盖**：

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Agent",
        "hooks": [{ "type": "command", "command": "bash \"$HOME/.claude/hooks/agent-model-guard.sh\"", "timeout": 5 }]
      }
    ]
  }
}
```

（`command` 里写绝对路径是实战验证过的形态；`timeout` 保证 hook 卡死也不会拖住派发。）

然后把 [policy/claude-md-block.md](policy/claude-md-block.md) 的策略段粘进你的 `CLAUDE.md`。`effort` frontmatter 键见[官方 sub-agents 文档](https://code.claude.com/docs/en/sub-agents)。

省你提 issue 的几条注意：

- **装完重启 Claude Code**——agent 定义在会话启动时加载。
- **`CLAUDE_CODE_SUBAGENT_MODEL` 保持不设**——它会全局覆盖 frontmatter，静默废掉所有钉死。
- **从 v1 升级：** 重新拷 `worker.md`、hook 和策略段。`scout` 留着（hook 仍放行它）或删掉都行——v2 的侦察走 Explore 并显式标 haiku。
- **Agent 名按项目优先解析。** 项目里定义了自己的 `worker`/`judge` 会盖过 `~/.claude/agents/`。保持这几个名字在你环境里唯一；自己加钉死 agent 的话，同步扩 hook 的放行名单（`scout|worker|judge|fork`）。
- **Hook 校验的是派发请求，不是最终解析出的模型。** 它焊死的是「忘了标」这个失误面——在我的测量里这就是泄漏的全部——不是所有想得到的配置错误。

冒烟测试：任意会话里，让 Claude 派一个**不带** model 的 general-purpose 子 agent。预期：派发被 deny，拒绝理由里是路由表，Claude 带上模型重新派发。测试于 Claude Code 2.1.210，2026 年 8 月。一直不 deny：查 `jq` 装没装、settings.json 里的脚本路径能不能解析、matcher 是否精确为 `Agent`——hook 的 payload schema 会随版本漂移，离 2.1.210 太远就对照 changelog。deny 了但 Claude 不重派，那是模型的服从性问题，不是 hook 的。失败模式有意设计为开放：hook 自己崩了会报错、派发照常进行——最坏情况就是回到默认行为，不会把会话搞死。

安装到此为止。没有守护进程、没有代理、没有 npm。

## 装完之后：日常会变什么（v2）

你跟 Claude 说话的方式一点不变。照常提需求，策略段替你判断到底要不要派：

- 「retry 逻辑定义在哪？」→ 主线程自己搜。要扫一大片代码库才答得出，就派 Explore 并标 haiku，带回 file:line。
- 「按我们刚定的方案实现」→ 主线程。上下文都在它那，交出去等于再讲一遍。
- 「把这个重命名全仓套一遍」→ `worker`——Sonnet（纯体力活标 haiku），一句话 spec，不做设计决定。
- 「好好 review 一下这个 diff」→ `judge`——frontmatter 已钉 opus；冷读和轻量 review 显式标 sonnet。
- 「把这四家竞品调研一遍」→ 四个 `judge` 并行，整批同一档。

想手动点名也随时可以：「让 judge 冷读一遍」「让 worker 按 spec 改」——agent 名会变成你和 Claude 之间的共用词汇。

闸门触发时，转录里长这样——是打回重来，不是报错：

> agent-model-guard: this Agent call has no model and would silently inherit the main-thread model. First check whether it should be delegated at all (default: the main thread does it). If it should, re-issue per the routing table: independent perspective → judge (opus pinned; tag sonnet for cold reads), large-batch mechanical work → worker, recon → Explore with model haiku. …

Claude 读完，要么自己干，要么带上模型重新派发，活照常干。大多数时候你会发现它*从不*触发——这正是目的。

每月一次（或改完配置之后），重跑 [audit §2](audit/audit-commands.md) 看两个数：前沿模型在子 agent token 里的占比（除非你点名，应该 ≈0）、模型构成有没有往你预期的方向走。v2 起再加跑 [§5](audit/audit-commands.md)——子 agent 占全部流量的比例：现在要问的是总账，不只是子 agent 那一块。

## 方法论（v1——我会再做一遍的部分）

1. **审计默认值。** 每个「继承/默认」行为都藏着一条环境一变就静默失效的假设。省钱的第一刀不是换便宜模型，是找出正在静默生效的昂贵默认值。
2. **钉死胜过裁量。** 这些钱是靠删掉决定省下来的，不是靠做出更好的决定。需要人记得的规则不是规则。
3. **拿闸兜失误。** Prompt 级规则（CLAUDE.md）可靠但软。十几行 hook 把「忘了标」这个失误面直接焊死。
4. **用数据闭环。** 上线前定好指标（单位成本、泄漏次数、模型占比），用同一套命令定期复测，反直觉信号先拆解再下结论。例：sonnet 单次平均输出中途跳涨——不是 effort 档失效，是轻判断任务进入 sonnet 车道改变了构成。先拆人群，再怪旋钮。

## 刻意没做的东西

- **不做分类器。** 上表两个 hook 路由器都加了一个（关键词启发式或额外的 Haiku 调用）来判断任务难度。但编排者*自己写的任务 prompt*——它本来就知道这活是侦察、机械还是判断。静态路由加编排者自己的档位分流已捕获全部价值；分类器重复了一次已经免费发生的判断，还添了一个误分类面。
- **不做改写式强制。** Deny-重派让编排者留在环路里，与其他 hook 组合安全；用 `updatedInput` 改写 spawn 参数在多 hook 同时触发时合并顺序无文档（router-hook 项目自己的 README 承认这一点）。收敛证据：junoseong 的 deny 式 hook 在测试任务上量到 **25.3k → 11.4k token**。
- **不加更细档位。** 加固之后，剩余空间就是捡硬币。每加一档都在为几美分的收益增加分类负担和误路由面。
- **不做跨厂商代理。** [claude-code-router](https://github.com/musistudio/claude-code-router) 这类工具解决的是另一个问题（换后端）。本系统留在单一厂商单一订阅内——这正是上面数字干净的原因。

## 更新（2026-08-09，v1）：最后一个靠纪律撑着的档也钉死了

上面路由表的判断行，原本写的是「general-purpose + 记得标 opus」——三行里唯一靠派单纪律（外加 hook 兜底）而不是钉死定义撑着的一档。暴露它的是一次移植：把这套策略搬到第二个 CLI（Codex Desktop，三个原生 custom-agent TOML）。移植版把每个角色——连通用 fallback 都算上——全部钉进了配置，两边一对比，这处不对称就藏不住了。于是修法反哺回来：[`judge`](agents/judge.md) 在 frontmatter 里钉死 opus，轻判断变成同一个 agent 显式降档 sonnet，hook 放行名单多了一个名字。方法论第 2 条「钉死胜过自觉」，现在对三行全部成立。

## 更新（2026-08-11，v1）：又过了 8 天，用量涨到 6.3 倍

26 天 n=1 最容易被质疑的一点是：会不会刚好那段时间活少。后来并不少——接下来 8 天（8/4–8/11）子 agent 派发从每天 87 个 assistant turn 涨到 **545 个，6.3 倍用量**，路由稳住了。Fable **零泄漏**。这个窗口的 volume-held 反事实：实际 $52.24，按路由前配比要 $108.75（−52%），按加固期配比 $54.20——**只差 3.6%**。最后这个数才是真结论：系统已经到顶，剩下的是捡硬币。

这个窗口里有一个数字是陷阱，与其埋掉不如摊开讲。表头单位成本又降了——$1.31 → **$0.79/M token**——而这里面几乎没有路由的功劳。cache read 占 token 比从 84.2% 涨到 91.5%，而 cache read 按 0.1× 计价，分母被灌大了。剥掉 cache，纯路由口径反而朝*反*方向走：$12.01 → $14.07/M in+out token——因为 output 占 in+out 从 74.9% 涨到 92.8%，而 output 单价是 5 倍。路由没变，变的是对话形态。**永远两个一起读**——[§3](audit/audit-commands.md) 是你花了多少，[§2](audit/audit-commands.md) 是路由做了什么。

这个窗口改变的最后一件事是视角。那 8 天里子 agent 占 in+out token 流量的 21%，却只占 **10% 的支出**（$4,200 里的 $413）——这两个数之间的差距本身就是路由在生效。剩下 90% 在主线程，那里用旗舰模型是有意的选择，不是没人审计的默认值。这就是诚实的天花板：这个 repo 让派出去的活变便宜，至于你自己用什么，它管不着。

## 已知开口（v1）

- **路由省钱 ≠ 委派省钱。** 上面每一个数字量的都是*子 agent 跑在哪个模型上*，不是「派出去」比「自己干」更省。这两件事可能指向相反方向：另一个 CLI 上的配对 A/B 实测发现，一个旗舰 root 加一个便宜的 explorer 子 agent，总账比 root 自己干**贵 8%**——子 agent 确实便宜，但 root 从没停止重做同样的活。这个 repo 不声称委派本身划算，它声称的是：既然你要派，就别按旗舰价派。[Audit §6](audit/audit-commands.md) 能在你已有的转录上抓出这个失败模式，不用跑 A/B（我这边：压缩比 85:1，重新探索率 2.9%）。
- **Workflow 内的 `agent()` 调用绕过 Agent hook**（PreToolUse 对它们不触发）。只有策略文本软约束。实测泄漏：19 天 7 次 ≈ $6——不值得建闸。
- **`fork` agent 有意放行**——继承就是它的语义；model 参数是 no-op。
- **2026-08-11 已复测**（原先是关于 opus 档占比的开放问题）：opus 占子 agent in+out token **31.7%**、占子 agent 支出 **47.9%**，低于加固期的 35.1% / 54.2%。轻判断分流在起作用，只是慢。留个记录：这条原先引的「约 52%」几乎可以肯定是把支出口径记成了 token 口径——所以从这里起两个数分开写。
- **9 月复测**：Sonnet 首发价（$2/$10）于 **2026-08-31 结束** → $3/$15（[已在官方 pricing 页确认](https://platform.claude.com/docs/en/about-claude/pricing)，无延期）。按 8/4–8/11 窗口重算是**子 agent 支出 +26%**，不是最初估的约 20%，单位成本会落到 $0.99 附近。这是牌价变动，不是路由退化。
- 模型别名（`opus`、`sonnet`、`haiku`）向前解析：运行中途 `opus` 别名解析到了同价的新版 Opus——这里是免费升级，但需要确定性就钉具体模型 ID。

## License

[MIT](LICENSE) · 提问与纠错请开 issue。X 上找我：[@vinentW789](https://x.com/vinentW789)。
