# 文档入口与时效

当前用户功能入口为 [Astra README](../Astra/README.md)，选项和调度以 `Astra/shaders/lib/settings.glsl`、`Astra/shaders/shaders.properties` 为准。本文状态更新于 2026-10-04。

## 活跃文档

| 文档 | 适用范围 / 当前状态 |
|---|---|
| [10-04 各模块性能开销收尾](2026-10-04-module-performance-final-pass.md) | 16 个着色器文件的重复求值、无贡献采样与关闭选项读取裁减；覆盖当前渲染模块，保留原画质参数和主要采样预算 |
| [10-04 审查接续修复](2026-10-04-review-followup-fixes.md) | 共用 Iris 选项解析、四档补漏、入口分层、跨维度格式声明、过期工具停用、许可与表达式来源台账更新；保留现有渲染效果参数 |
| [10-04 主世界 144 FPS 与画面修复](2026-10-04-overworld-144-and-visual-fixes.md) | 主世界云遮挡调度、空气场景读写与水下光色共享；光束远处噪点、云轮廓、银河及下界暗部／岩浆调整，144 FPS 尚未确认 |
| [10-04 各模块性能审查接续](2026-10-04-module-performance-followup.md) | 水体介质与视深度复用、零贡献云与阴影工作裁减、历史状态读取及下界彩光优化；保留当前主要画质预算，逐模块记录开销与边界 |
| [10-04 第四批性能选择与实现](2026-10-04-batch4-selected-optimizations.md) | 反射 Z/W 与命中深度复用、水下备用雾与天空窗口无贡献读取裁减；记录全部候选取舍及 Iris 默认值等报告纠正 |
| [10-04 夜空群星选择优化](2026-10-04-nightsky-selected-optimizations.md) | 星空跟随日月、平滑相邻星点、轻微冷暖闪烁与五档密度；复用 CPU 天体与可见性计算，记录报告纠正及开销边界 |
| [10-04 水下亮度与全项目模块审查](2026-10-04-full-module-review.md) | 普通水体曝光轻微降低，补齐薄水层的曝光／AO／体积雾／天空／FXAA 衔接，减少水面阴影材质读取；记录各模块结论及现存边界 |
| [10-03 第三批调研选择与实现](2026-10-03-batch3-selected-optimizations.md) | 远处植被风场、完整 TAA 遮罩 gather 与云白天调色 CPU 化；纠正报告中的重复项与漏角点，保留花草投影及水体效果 |
| [10-03 花草投影与浅水／流水衔接](2026-10-03-plant-shadows-and-water-sheets.md) | 用户报告上一版同场景稳定约 100 帧；恢复植物投影，淡青浅水与流水、竖直面轻微反光及薄水层颜色衔接 |
| [10-03 连续水色、浅水焦散与岸上开销](2026-10-03-shore-water-and-performance.md) | 连续深度曲线、浅水体积及中性弱焦散；针对沙滩树林裁减阴影／反射重复工作，100 帧目标待新画面确认 |
| [10-03 水体三处收尾调整](2026-10-03-water-final-polish.md) | 用户认可既有水体；增加轻微距离扩散、透明浅水到青蓝深水过渡，修复水下雨滴过滤条件 |
| [10-03 光束波动与头顶菲涅尔环](2026-10-03-underwater-optical-motion-and-window.md) | 参照 ITT 的逐步波面查询、相位与全反射窗口；共用光学波场并复用水面阴影缓存，新动态画面待用户观察 |
| [10-03 水下风格调整](2026-10-03-underwater-itt-style.md) | 按用户三张截图处理雾量、暗部、青色水体、光束明暗与焦散；短距离积分与波纹聚光场已写入代码，新画面待用户观察 |
| [10-03 首次轻雾调整](2026-10-03-underwater-light-haze.md) | 历史参数与初次方案；用户认为雾感不足，已由上一行的五项调整接续 |
| [10-03 自主实机核查与性能修正](2026-10-03-live-performance-inspection.md) | 实际操纵主世界／下界／末地、贡献分屏定位水下反射细纹、修复 Iris 数值启停条件；列出当前截图、正式改动及尚存画面边界 |
| [10-02 各模块性能接续与报告处理](2026-10-02-module-performance-refinements.md) | 植被时间相位、水波共享查询、光束投影与零贡献裁减；修复焦散、选项守卫，采用直接体素传播，逐项说明独立报告中的真实问题与误判 |
| [10-02 未提交改动独立审查](2026-10-02-uncommitted-changes-review.md) | 对当时工作区的独立意见；当前处理及 F-2 / F-5 等纠正见上一行，不将报告建议直接作为执行指令 |
| [10-02 性能批次代码审查](2026-10-02-perf-batch-code-review.md) | 从 main 到工作区的多轮变更意见；现存问题的处理、FXAA 算术与资源比较范围纠正见模块性能接续记录 |
| [10-02 第二批实施记录](2026-10-02-batch2-implementation.md) | 时间跳变停止沿用旧历史、体积雾齐次投影复用及粗糙天空反射等改动 |
| [10-02 各模块性能开销审查与修复](2026-10-02-module-performance-review.md) | 地形、植被、阴影、水体、天空、体雾、下界、末地、AO 与抗锯齿的开销裁减；接续补齐不投影顶点提前退出、水下法线过滤、体素零值加载、历史拒绝和显示深度复用；保持当前画质预算 |
| [10-02 项目源码审查与性能修复](2026-10-02-project-performance-fixes.md) | 零强度 Bloom 调度、晨雾权重修正、对称天光查询合并，以及云历史、体积雾、水体和下界反射的无贡献工作裁减 |
| [10-02 二十包 SUMMARY 优化实施](2026-10-02-summary-optimizations.md) | CPU 抖动 / 云影锚点 / 雨湿参数、效果阶段关闭、Bloom 分档、短射线体积雾、实体投影、手持光、TAA 中心可信度及可选夜间蓝移；附 Top10 对照 |
| [10-02 Steadfast 调研后的优化实施](2026-10-02-steadfast-optimizations.md) | 主世界 CPU 天空计算、闲置缓冲裁减、AO 紧凑存储、水体质量档位、云历史开关和性能档阴影覆盖；记录开销与画面取舍 |
| [10-02 Steadfast 0.8.0 专项调研](2026-10-02-steadfast-performance-study.md) | 用户指定本地包的带宽、CPU 预计算、阴影及水体预算；作者已知缺陷与数值风险分列；随后采用部分见上一行 |
| [10-02 视频参考光影逐包分析](2026-10-02-shader-reference-performance.md) | 14 款光影的下载来源、源码性能机制、适用性及已采用改动；Derivative 维护分支与 IterationT 镜像分别注明 |
| [10-02 颜色与性能设置](2026-10-02-colour-and-quality-options.md) | Mellow 风格的独立调色组织、四种颜色方案、66 个 RGB 通道，以及阴影 / 云 / 体积雾 / 水反射质量档位和云历史开关 |
| [10-01 性能审查与雨天粒子修复](2026-10-01-performance-review.md) | 主世界调色、雨雾、积水与云缓冲优化；雨滴溅落粒子入口及颜色过滤边界；另含水下光束、TAA、下界反射与末地天空的改动 |
| [10-01 项目源码审查与修复](2026-10-01-project-review-fixes.md) | 云与反射历史及滤波、方向性天光 AO、体积雾与手持物、水面、水下 Bloom、Darkness 及体素材质身份修复；当前源码结论与画面边界 |
| [10-01 下界岩反射实现](2026-10-01-complementary-netherrack-reflection.md) | 参考链路、独立历史与后续光照调整；现行代码还需结合本次源码修复记录阅读 |
| [09-26 ITT 设计落地与持续待办](2026-09-26-itt32-initial-implementation.md) | 唯一状态总表；第 6 节记录 H1、标量 AO、植被运动的实际代码及剩余 R1–R6；R4/R5 未完成范围同时见下一行提示词文件 |
| [09-27 下一批 Agent 提示词](2026-09-27-next-agent-task-prompts.md) | R1–R6 完整提示词；R4/R5 未完成范围以此文件为准；含共享文件顺序、资源归属与中断接续要求 |
| [09-28 水体材质与光照](2026-09-28-water-material-lighting.md) | 当前批次报告：水面缺失、末地石质感、下界反射与照明等两轮修复及复核批注 |
| [09-28 下界/水下参考借用调研](2026-09-28-nether-underwater-borrow-study.md) | 第三轮修复的参考对照报告：Complementary 下界氛围与反光、Solas 水下链路的机制与 file:line、逐症状移植清单；不含代码改动 |
| [09-29 实机反馈根因调研](2026-09-29-runtime-feedback-study.md) | 第三轮实机复测（水下过暗/光束不可见/下界反射/过红过亮）的根因调研：变暗项清单与水面数据缺失检验、反射的几何门限推演、过红贡献分解与回退顺序；硬约束"不得加强发光体"在案 |
| [09-30 实机反馈调研二](2026-09-30-blur-glow-disk-study.md) | 数据链修复后复测（水下远景糊/下界岩镜面感/吸积盘棉絮感）的根因调研：糊=参考同款雾幕+glare 放大器、"发光感 vs 镜面感"的三体系差距表、吸积盘低频纹理+零时域的分辨率瓶颈与三条提升路径 |

## docs/handoffs/

15 份任务交接账本：各任务唯一进度账本，未完成事项以文件内「未完成/接续位置」为准。

- 专项研究四份：S1-sh9、S2-volume-integral、S3-voxel-grid、S4-foliage-time
- 轮次实施六份：R1-bent-normal、R2-overworld-volume、R3-voxel-layout、R4-entity-motion、R5-water-temporal、R6-cloud-temporal
- 主题交接五份：end、nether、sky-clouds、terrain-foliage、ui-language

## docs/archive/

已关闭轮次共 14 份（另含 parallel-development/）。带日期文档描述当时源码，其结论不自动适用当前版本，也不是新的执行指令；旧的数量、参数、缺陷清单不能直接拿来修改当前实现。

| 文档 | 一句话说明 |
|---|---|
| [09-27 TAA/FXAA 批次审查](archive/2026-09-27-taa-fxaa-batch-review.md) | 对 A1–A3、B1–B3、T1–T3 批次的独立审查；Important 项已修复，判定改后可过 |
| [09-27 Agent 任务提示词](archive/2026-09-27-agent-task-prompts.md) | S1–S4 原任务范围与提示词；四项已交付并经源码复核，S2/S4 已补正 |
| [09-27 新参考批次深度调研](archive/2026-09-27-new-refs-batch-study.md) | 10 包技术索引；AO、体积雾、云反射、曝光与 SH9 推断须结合[持续待办](2026-09-26-itt32-initial-implementation.md)「2. 前序已完成」的 A3/B1 行更正阅读 |
| [09-26 ITT 3.2 深入设计调研](archive/2026-09-26-itt32-design-study.md) | 对照当前 Astra 的借鉴优先级、接入成本与源码依据；包含全量调研汇总的关键更正 |
| [09-26 工作区参考光影全景调研](archive/2026-09-26-workspace-packs-survey.md) | 34 参考包档案（Complementary 系、09-24 批、性能批次、低配 16 包）+ 跨包借鉴优先级 + 许可边界 + 纠错 |
| [09-26 全量源码审查续篇](archive/2026-09-26-project-review-followup.md) | 焦散动态范围、介质遮挡、物品材质映射、选项与工具入口修复 |
| [09-26 全项目审查与修复](archive/2026-09-26-project-review.md) | 当日较早一轮的已实施修复与结论范围 |
| [09-26 全量审查与调研汇总](archive/2026-09-26-full-review-and-research.md) | 历史汇总；ITT 黑洞、阴影成本、水面时序等结论须结合 [深入调研更正](archive/2026-09-26-itt32-design-study.md#6-对用户指定汇总的关键更正) 阅读 |
| [交接处理记录](archive/2026-09-24-handoff-resolution.md) | 已实施改动的记录；观感待办不代表已经解决 |
| [低配优化记录](archive/2026-09-25-low-end-optimization.md) | 已实施优化及适用边界，不作固定 FPS 承诺 |
| [跨包调研后续](archive/2026-09-25-survey-followup.md) | 对调研指标的纠正与已采用的改动 |
| [09-25 全量审查](archive/2026-09-25-full-audit.md) | F-1/F-3/F-5/F-6 已处理，F-4 为工具误报且已修，F-2 不成立；不能作为当前缺陷清单 |
| [参考包批次登记与 Codex 提示词](archive/2026-09-24-codex-refs-prompt.md) | 参考包批次登记与 Codex 提示词；属材料登记，非执行指令 |
| [低配参考集第 3 轮调研](archive/2026-09-25-low-end-shaders-round3.md) | 低配参考集第 3 轮调研；结论只描述当时样本 |
| [17 包横向普查](archive/2026-09-25-lowend-cross-pack-survey.md) | 低配包横向普查；描述当时样本，不构成当前结论 |
| archive/parallel-development/ | 09-23 时代五条并行任务线的早期开发提示词与公共边界（end、nether、sky-clouds、terrain-foliage、ui-language，另含 preambles），已由 docs/handoffs/ 同名交接账本取代 |

## docs/images/

历史截图与设计图像（末地黑洞／喷流／环带、涟漪翻书及后续盘面设计 PNG）。同目录原始 `.npy` 数据保留本地，正式 PNG 纳入版本控制。

## 需要避免沿用的推断

- 三个画质档加 NO_SHADOWS 是四个预设；`WATER_CHARACTER` 的三种水色与预设数量无关。
- 只有 BALANCED 与源码默认值逐项一致，四档之间的差异是刻意设计。
- 默认编译命令选择三档；270 次链接不是四档覆盖。
- 仓库有历史游戏截图，“从未出过游戏画面”不成立；历史截图也不能证明当前源码的观感。
- 连续十二行没有相同文本，不能推出没有改编或没有遗漏来源；出处仍按文件及表达式记录。
- pass 存在性已由 `check_dimension_gating()` 处理，无需为同一判断另加一份实现。

本次入库的 09-21 至 09-23 日志与 JSON 保留原始内容，属于历史材料；归档不把其中的参数、通过声明或待办转成当前结论。

## 其他入口与悬空说明

- [工作区入口](../README.md)、[参考调研入口](../shader_research/README.md)、[开发输出说明](../qa/README.md)：源码、报告与本地材料的位置及版本控制范围。
- [引擎前提](../qa/open-premises.md)：P-2 的距离乘链已有引擎依据；游戏观感与其他驱动情况独立记录。
- [工具配置](../qa/tools/README.md)：本机路径配置、参考文件获取及退出状态。
- 2026-09-26 已清理 09-06 ~ 09-24 的 50 份历史轮次报告入 git 历史，其中 2026-09-24-reference-analysis.md 与 2026-09-11-iterationt-optimization-review.md 在文中被提及时属删除记录，非断链；其结论仍需对照当前实现判定。
