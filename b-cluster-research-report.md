# B簇调研结果：上下文工程、记忆、成本优化、推理预算

## 1. 论文发现清单（均已读摘要页或全文节选）

- A Survey of Context Engineering for LLMs (2025, arXiv:2507.13334) — 1400篇论文的分类体系，指出模型"理解强、生成弱"的不对称缺口。https://arxiv.org/abs/2507.13334
- Effective context engineering for AI agents (Anthropic, 2025-09) — 官方立场：compaction、结构化笔记、子代理三杠杆；"工具结果清除"已是平台功能（context management API），准入控制若做必须区别于此。https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- Stop Overthinking: Survey on Efficient Reasoning (2025, arXiv:2503.16419) — 高效推理三分类：模型级/输出级/输入提示级；输入级按难度控制正对应 B 簇方向。https://arxiv.org/abs/2503.16419
- The Danger of Overthinking: Reasoning-Action Dilemma (2025-02, arXiv:2502.08235) — 4018条SWE-bench轨迹：LRM系统性偏内部推理轻环境交互；仅"选低overthinking分数解"即性能+30%、成本-43%。这是"会话内信号可驱动预算控制"的最强已发表证据。https://arxiv.org/abs/2502.08235
- MEM1 (2025, arXiv:2506.15841) — RL训练agent每步压缩状态为单一memory目标，推理内存近常数。https://arxiv.org/abs/2506.15841
- Rethinking Memory in AI (2025, arXiv:2505.00675) — 记忆六操作分类。https://arxiv.org/abs/2505.00675
- CompactionRL (2026-07, arXiv:2607.05378) — RL联合优化执行与压缩摘要，GLM-4.5-Air SWE-bench +6.6pt，已进GLM-5.2训练管线。压缩"怎么学"已被大厂做掉，插件层无空间。https://arxiv.org/abs/2607.05378
- FrugalGPT (2023, arXiv:2305.05176) — LLM cascade 鼻祖。https://arxiv.org/abs/2305.05176
- FrugalEvo (2026, arXiv:2610.03675) — 强弱模型分工+缓存友好流程，按单位成本衡量（BA-AUC）。https://arxiv.org/html/2610.03675
- What If We Allocate Test-Time Compute Adaptively (2026-02, arXiv:2602.01070) — PRM引导自适应算力分配，数学域有效、高难度失效。https://arxiv.org/html/2602.01070
- ConsistencyGate (2026-07, arXiv:2607.22962) — 记忆写入时准入控制：K次自洽打分门控，防"记忆污染"。学术已占"记忆写入门控"高地，但只针对对话事实，不针对代码会话经验。https://arxiv.org/abs/2607.22962
- Memory-R1 (2025-08, arXiv:2508.19828) — RL训练Memory Manager学ADD/UPDATE/DELETE/NOOP。https://arxiv.org/abs/2508.19828
- SEDM (2025-09, arXiv:2509.09498) — 发送端"成对执行测试"准入记忆，接收端Calibrated Memory Gating按预测成功增益注入；LoCoMo +15.1 F1、省18%输入token。最接近"经验准入"的学术实现，但非coding harness。https://arxiv.org/abs/2509.09498
- MemCon / Memory as a Controlled Process (2026, arXiv:2607.13591) — 记忆操作建模为MDP，bandit在线学"何时检索/注入/遗忘"。https://arxiv.org/abs/2607.13591
- Self-Improving AI Coding Agents Through Accumulated Behavioral Rules (2026-07, arXiv:2607.13091) — 评审意见→持久行为规则闭环，35+服务生产环境，自报0%复发率。https://arxiv.org/abs/2607.13091
- SWE-Pruner (2026-01, arXiv:2601.16746) — 任务目标提示引导的0.6B代码上下文剪枝；另有 SWE-Pruner Pro (arXiv:2607.18213)。https://arxiv.org/abs/2601.16746
- Beyond Token Savings (2026-09, arXiv:2609.32961) — 35000次运行：省token不等于更快更便宜；Terminal-Bench上1/3 token的策略反而慢20-80%。压缩策略须按任务/模型/负载定制。https://arxiv.org/abs/2609.32961
- An Empirical Cost Attribution of Context-Compression Gateways (2026-08, arXiv:2609.22114) — 实测生产网关三杠杆：工具schema过滤每轮固定省21K-57K token（唯一线性稳定收益）；内容压缩每轮仅省约2%缓存前缀但按约3350·N²累计；非确定性历史膨胀代价二次增长。https://arxiv.org/abs/2609.22114
- VDAR-Router (2026-07, arXiv:2607.18098) — 难度感知检索式路由，每query级。https://arxiv.org/abs/2607.18098
- ACTS (2026-06, arXiv:2606.03965) — 控制器在thinking token预算下逐步引导冻结推理器，RL训练、预算条件奖励。https://arxiv.org/abs/2606.03965
- HARBOR (2026-04, arXiv:2604.20938) — 把harness配置开关（compaction、缓存、记忆）形式化为约束噪声贝叶斯优化。https://arxiv.org/abs/2604.20938
- Voyager (2023, arXiv:2305.16291)、Reflexion (2303.11366)、ExpeL (2308.10144) — 技能库/经验学习经典基线。

## 2. GitHub 查重结果（star为2026-10-18从repo HTML页读取）

### A. 工具结果准入控制
- KRLabsOrg/squeez（24★，活跃）：专用小模型（Qwen3.5-2B生成式/ModernBERT抽取式）按任务描述过滤工具输出，27类工具、618例评测，F1 0.80、压缩92%。已占"语义级工具输出过滤"位。限制：每条命令需给任务描述、需跑模型、不感知工具语义结构。https://github.com/KRLabsOrg/squeez
- NousResearch/hermes-agent issue #85288（Open，P3 Low，未实现）：提出per-tool结构化结果档案（bounded_matches/tail_or_head/summary模式），明确"是size cap的补充不是替代"。证明harness级准入控制在主流harness仍是待办。https://github.com/NousResearch/hermes-agent/issues/85288
- qdrddr/clear-your-tools（19★）：BM25过滤工具schema（输入侧），不是工具结果。https://github.com/qdrddr/clear-your-tools
- Ayanami1314/swe-pruner：SWE-Pruner官方仓库，面向代码上下文剪枝（学术配套）。https://github.com/Ayanami1314/swe-pruner

### B. 会话经验沉淀与验证
- auto-sop/auto-sop（0★，ELv2闭源+云服务）：hooks捕获全部交互→规则检测（N≥3证据）+LLM分析→写enforced CLAUDE.md指令。指标只有"指令触发次数、估算token节省"，无效果验证（不能证明指令减少错误复发）。商业化说明有人抢，但"验证"环节空缺。https://github.com/auto-sop/auto-sop
- bgrober/autopilot（0★）：hooks+LanceDB，session-end分析→CLAUDE.md进化。无验证。https://github.com/bgrober/autopilot
- cklxx/compound-engineering（0★）：纯prompt技能（SessionStart注入+触发词写记录），"自动学习"实为提示词约定。https://github.com/cklxx/compound-engineering
- nekocode/skill-forge（4★）：元技能，4维评估器+20例触发评测，不达标不保存。最接近"写入前验证"，但评的是skill文本质量，不是实际行为改变。含双文件信任模型防提示注入。https://github.com/nekocode/skill-forge
- shimo4228/claude-skill-learn-eval：从会话提取模式→对照会话实际发生的事→只存到未来会话真的会读到的位置；验证=会话内一致性，非前瞻效果。https://github.com/shimo4228/claude-skill-learn-eval
- Hedde/trigger_tree：本地零token遥测，测"适用的CLAUDE.md指令是否被可观察行为遵守"+文档发现度热图+CI门。全组唯一做指令效果测量的项目，但测的是"是否被遵守"，不是"是否有效"。https://github.com/Hedde/trigger_tree

### C. 难度感知路由/预算控制
- musistudio/claude-code-router（37.7k★，937 open issues）：源码与文档确认——路由=静态条件规则（request.header/body字段算子匹配）+可选Node.js脚本规则（逻辑自写）；"Subagent自动路由"靠把模型描述注入Agent/Task工具描述、让模型自己写CCR-SUBAGENT-MODEL标签。默认无任何难度感知；文档全文无"difficulty"字样。fallback仅失败重试/model-chain。https://github.com/musistudio/claude-code-router/blob/main/docs/src/content/docs/en/configuration/routing.md
- jung-wan-kim/usage-gate：按Anthropic配额用量百分比自动把子代理opus降为sonnet/haiku。信号=配额，不是难度。https://github.com/jung-wan-kim/usage-gate
- tahasiddiquii/llm-router（2★）：离线demo级难度分类路由+语义缓存，非agent harness。https://github.com/tahasiddiquii/llm-router
- tjamescouch/niki：硬性预算supervisor（超token/超时SIGTERM），无质量决策。https://github.com/tjamescouch/niki

### D. Prompt caching 友好调度
- davccavalcante/racs（npm 1.0.0，187测试，star未见）：多provider缓存指令规划器（断点位置、prompt_cache_key、Gemini cachedContent、TTL keep-warm、前缀漂移检测），纯规划不代理。刚发布，规划与执行脱节。https://github.com/davccavalcante/racs
- NousResearch/hermes-agent agent/prompt_cache_boundary.py（生产源码）：builder注册稳定前缀，LRU保存边界，断点置于scaffold与volatile tail交界。harness内实现范例，非独立插件。https://github.com/NousResearch/hermes-agent/blob/main/agent/prompt_cache_boundary.py

### E. 参考（成熟/拥挤，确认不进）
- mem0（67.4k★）、letta（25.2k★）、thedotmack/claude-mem（页面显示101.6k★，压缩+注入）、basic-memory（4.3k★）、ergut/mcp-memory-service（语义记忆+自主consolidation）——对话记忆赛道饱和，且全是"存取/检索"框架，无验证闭环。

## 3. 三分类判定表

| 方向 | 判定 | 依据 |
|---|---|---|
| 工具结果准入控制（语义级） | 已有实现但不成熟 | squeez已占语义过滤位；harness级集成（per-tool结构档案+语义分级混合、无需逐命令喂任务描述、与缓存成本联动）无成品；hermes仅停留在design issue P3 |
| 工具结果准入控制（纯结构档案） | 已有实现但不成熟 | hermes issue给出完整设计但未实现；可作squeez的免模型补充层 |
| 会话经验沉淀→CLAUDE.md/技能 | 已有实现但不成熟，"效果验证"环节空白 | auto-sop/autopilot/compound-engineering/skill-forge/learn-eval五家都在做沉淀，无一做前瞻性效果验证；trigger_tree做了遵守率但未做"规则是否有效"的因果测量；SEDM与ConsistencyGate证明学术侧已重视"写入准入"，未落地coding harness |
| 会话内难度感知模型路由/思考预算 | 真正缺少实现 | 路由项目全是静态规则或配额信号（CCR源码、usage-gate确认）；学术（VDAR、ACTS、Overthinking）证明难度信号价值但无harness落地；未找到任何项目用会话内结果信号（测试失败、反复纠错、工具报错序列）动态升降档模型或thinking budget |
| Prompt caching 友好调度 | 已有实现但不成熟 | RACS刚发布且规划/执行脱节；hermes有内部实现无独立方案；"缓存感知的工具结果排序/写入时机"未见成品 |

## 4. 值得深入的方向（按优先级）

### 4.1 会话内信号驱动的推理预算/模型升降档（最高优先，真空白）
- 创新点：不改路由规则配置，从会话流实时提取难度/失败信号——连续测试失败、同一文件反复读、工具报错序列、自我纠错循环、overthinking可计算代理（动作前推理token占比，来自2502.08235）——据此在hook/网关层动态升档模型、调thinking budget、注入"先行动"提示。Overthinking论文证明仅"选低overthinking解"即+30%性能-43%成本，但没有任何harness把该信号变成运行时控制。
- 与最近3个实现区别：CCR=用户预写静态规则（源码证实无难度概念）；usage-gate=配额阈值；llm-router=每query离线分类，无会话状态。
- 主要技术风险：①Claude Code/Codex hook能否中途换模型（CCR证明请求级可换；Anthropic原生API thinking budget可按请求调）；②信号误报：难度误判升档白花钱、降档毁任务；③模型切换即缓存失效，需与4.3联动算净收益。
- 可证伪假设：在SWE-bench-Verified子集或自建20任务集上，用"连续2次测试失败+推理token占比超阈值"触发升档，相比固定单模型，单位成本成功率提升不低于15%；若低于5%即证伪。
- 最小实验：不写产品。取ccusage式本地JSONL（或OpenCode日志）离线回放100条真实会话，标注信号点，统计"若在信号点换挡"的假想成本/成功率曲线。纯分析即可验证信号预测力。

### 4.2 经验沉淀的效果验证闭环（第二优先，验证环节空白）
- 创新点：五家竞品都停在"写入"，无人回答"这条规则到底有没有用"。做规则级A/B或影子验证：新指令进入CLAUDE.md前后，用trigger_tree式遵守率+任务级复发率（2607.13091的0%复发率指标）做因果对比；低效规则自动降级/合并，防CLAUDE.md膨胀（实测：200行CLAUDE.md使质量降至79%，拆3文件恢复96.9%，https://dev.to/yunbow/200-lines-in-claudemd-dropped-my-code-quality-to-79-splitting-into-3-files-got-it-to-969-1glm）。叠加SEDM式"成对执行测试"作为写入准入。
- 与最近3个实现区别：auto-sop只数触发次数；skill-forge评文本质量；learn-eval做会话内一致性——都不测行为改变。
- 主要技术风险：单用户样本量小，复发率统计功效低；A/B需可重放任务集；自动改CLAUDE.md有提示注入面（skill-forge双文件信任模型可借鉴）。
- 可证伪假设：经效果过滤的规则集（只留有统计证据的）在固定任务集上优于全量规则集（同等token下成功率更高）。若过滤版不优于全量，验证层无价值。
- 最小实验：手写10条候选规则，在3个小项目上各跑5次，测遵守率与错误复发，验证trigger_tree指标能否区分好/坏规则。

### 4.3 缓存感知的准入控制（合并方向，性价比来自定量证据）
- 创新点：2609.22114给出三杠杆定量：schema过滤线性稳赚（每轮21-57K）、内容压缩省2%/轮但按N²累计、误判膨胀代价二次。准入决策应联合优化"缓存破坏成本+累计重发成本+注意力污染"，而非只看当轮token。输出"该轮该不该过滤、过滤到什么档位"的决策。
- 区别：squeez不看缓存；RACS只管缓存不管内容；hermes设计不算成本模型。
- 风险：成本模型参数依赖provider定价且变化快；增量缓存（Anthropic 5min TTL）使计算复杂。
- 可证伪假设：按缓存感知模型决策过滤的会话，模拟总成本低于"全过滤"与"不过滤"两基线。若不成立，简单启发式已足够。
- 最小实验：同样离线回放，用公开定价+缓存语义模拟三种策略总账单。

## 5. 证据缺口说明
- 检索词：claude code memory、auto claude.md learning、experience distillation coding agent、agent cost controller、context pruning tool output、difficulty aware routing、reasoning effort budget、prompt caching hooks等；工具：web_search多查询（两度429后重试成功）、GitHub HTML页+raw+API（API被限流，star改从HTML页读取）。
- 未找到不等于不存在：①商业闭源压缩网关（如2609.22114提到的Paritok）查不到独立源码，其难度感知能力不可证；②"budget controller"检索命中的多为硬限制器（niki、agent-budget、shekel），若存在"质量感知预算器"应在overthinking/efficient reasoning关键词下出现，未出现，故"真空白"判定置信度中高；③GitHub API限流导致star/活跃度部分靠HTML解析，claude-mem的101.6k为页面原文但建议复核；④auto-sop/squeez的issue区未能深读（GitHub页面渲染受限），"未解决问题"基于README与设计推断而非issue证据。