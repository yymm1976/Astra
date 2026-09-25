# Astra 审查报告核验与新审查报告（第二轮 · GLM-5.3-Flash）

> 状态：历史审查，仅适用于文中审查时的源码；当前入口及已纠正结论见 [文档索引](README.md)。条目未逐项标为当前缺陷，也不表示全部已经解决。

**审查者**：GLM-5.3-Flash（ZCode 只读审查）
**日期**：2026-09-20
**性质**：只读。**本次未修改任何代码文件**，仅新增本报告。
**任务**：① 对 Qoder、Hunyuan 两份审查报告（`2026-09-20-qoder-full-review.md`、`2026-09-20-hunyuan-full-review.md`）逐条核验真实性、权衡修复必要性；② 输出一份**新的**独立审查报告（非对本轮 GLM 第一轮报告 `2026-09-20-glm53flash-full-review.md` 的修改），含三方对账与新发现。
**方法**：两份报告逐条回溯源码（Read 直读 + grep 调用者计数 + 数值手算复算）+ 参考包源码交叉取证（`_analysis/Solas Shader V2.2b`、`_analysis/iris-runtime`）+ 补读三方均未覆盖的模块（godrays/wind/reference_light/stars/water_bloom/bloom_capture/composite4/composite1）。

---

## 0. 总判断

1. **两份外部报告的总质量都很高，且与 GLM 第一轮高度互补**。三方合计 60+ 条 finding 中，逐条核验后**真实率约 92%**：Qoder 39 条中 33 条完全成立、3 条部分成立、1 条表述错误、2 条与既往已裁决项重合；Hunyuan 的独有主张（A1/A2/A4/A6/A9/§12）全部或大部分成立，其中两条（A1 水下重复 tonemap、§12.2 composite4 性能黑洞）是**三方中价值最高的单项发现**，且都是 GLM 第一轮漏掉的。
2. **三方在水下两个专项上的根因结论互相独立收敛于同一组事实**（光束方向门、采样覆盖、光谱绿蓝序、深度封顶、无 in-scatter），且全部经我复算成立。三份报告可以合并为一份修复工单。
3. **发现一处三方共同依赖却从未实证的前提**（sunAngle 约定），本轮用 Solas 参考源码钉死——结论：前提成立，三份报告的相关分析全部有效（§1）。
4. **一处三方共同误读**：Qoder 与 Hunyuan 都把"`deferred` 无条件启用"当作对蓝图的偏离；`design.md:493`（SC-34-F1）已明文把"三维度 deferred 常开"记录为现行决议——这不是偏离，是蓝图已承认的现状。
5. **本轮新发现 2 条**（§6）：`diffuse.glsl:358` 的 shadowFade 注释把正午/晨昏写反（且自相矛盾）；以及由此揭示的历史 bug 诊断存疑。

---

## 1. 前提核验：sunAngle 约定（三份报告共同依赖的未证事实）

三方在水下光束上的分析都假设 **`astraSolasTimeBrightness` 在正午 = 1、晨昏 = 0**，但没有任何一方给出 `sunAngle` 约定的证据（该值经 `frac(sunAngle-0.0333)` 重映射，若约定相反则"正午光束恒零"的结论整体翻盘）。本轮取证：

- Solas 原作 `shaders.properties:92-101` 含完全相同的重映射（Astra 即移植自它）；
- Solas `lib/atmosphere/volumetricLight.glsl:86`：`vlColor = mix(pow(lightCol, 0.85), lightCol * newSkyColor, timeBrightness)` —— `newSkyColor` 是**白天天空色**，即 `timeBrightness` 必须在**正午**取峰，否则体积光在正午呈夜色、在午夜呈昼色，物理荒谬；
- 该重映射的输出峰在 `TimeAngle=0.25`，手算对应输入 `sunAngle=0.25`。

**结论（高置信）**：Iris/OptiFine 的 `sunAngle` 约定为 **0=日出、0.25=正午、0.5=日落、0.75=午夜**，因此 `astraSolasTimeBrightness` 正午=1、晨昏=0。**三份报告的光束分析前提全部成立**。建议花 5 分钟实机验证一次（正午看 `vlVisibility` 非零、日落为零）后把该约定写进 `shaders.properties:296` 的注释——这是一个被三方引用却无人注明出处的语义。

---

## 2. Qoder 报告逐条核验

判定口径：**成立**（证据复核一致）/ **部分成立**（核心成立但有错误成分）/ **不成立** / **既往项**（与 09-13 审计或 GLM 第一轮重合，注明）。"必要性"按本包语境分级：必修 / 应修 / 可缓 / 不建议动。

| # | 核验结果 | 证据要点 | 必要性权衡 |
|---|---|---|---|
| F-01 | **成立，且比 GLM 第一轮更完整** | `lit.fsh:362` 写的是 colortex5（water pass 的 `gl_FragData[1]`）✓；`water_state.fsh:19` 恒跳过 ✓；三条注释伪断言 ✓。**Qoder 的增量**：`shaders.properties:54-56` 的 `blend...colortex5=SRC_ALPHA...` 在 src.a=0 时连 **colortex5.rgb 一起丢**——即 SC-39 这一行摧毁的不只是有效性标志，而是整张水面高度图。GLM 第一轮低估了爆炸半径，予以采纳修正 | **必修**（三方共识、最高优先） |
| F-02 | **部分成立：前提未决性真实存在，后果为条件性** | "deferred 先于半透明"（design.md:90）与"手部在半透明后绘制"（vanilla 顺序）确实不可同时成立；但 Iris 对 hand 阶段与 deferred 的精确相对顺序**无法离线定论**，Qoder 自己也承认并只给出探针方案 ✓ 诚实。其 (a)(b) 后果（colortex4 滞后一帧）是条件推断；(c)(d) 中"天空回填用 depthtex0"在 deferred 先于半透明的既定前提下不成立（deferred 时半透明尚未画，天空像素仍为远平面） | **应修（先探针后动代码）**——一次 in-game 图案写入实验即可定论，Qoder 给的实验设计正确 |
| F-03 | **成立**（=GLM 第一轮 R-E） | 正午 `time=1` → `mix(0.25+0.25VoL, 0.45VoL, 1)=0.45VoL`，向下视线 `VoL=0` → visibility 精确为 0 ✓（约定已由 §1 钉死） | **必修**（用户点名需求的主因之一） |
| F-04 | **成立** | 衰减链各环节量级复核一致；`:29-35` 注释宣称"参考实现不做硬跳过"而 `:100` 就是硬跳过——又一例"注释↔代码相反" ✓ | **必修**（并入光束工单） |
| F-05 | **成立**（=GLM 第一轮 R-A，数值表复核一致） | BALANCED `c_G(0.06)<c_B(0.10)` → G/B 单调升到 1.9，深水极限为绿 ✓；+1 偏移与 16 格封顶 ✓；COLD 档确实存在蓝轨迹 ✓ | **必修**（用户点名需求的主因） |
| F-06 | **成立**（=GLM 第一轮 R-C） | 空气侧无 in-scatter，且被 `absorption.glsl:55-57` 注释明令禁止 ✓ | **必修**（同上；须先改蓝图分工再改代码） |
| F-07 | **部分成立，其中"UB"主张不成立** | ①"同一 pass 读写 colortex0 是 UB"——**错**：Iris 对 colortex0/1 等主缓冲做逐 pass 双缓冲翻转，composite 读到的总是本 pass 之前的版本，这正是全包水面/合成链依赖的机制（09-13 审计 §12.9 已核对"flip 由引擎按写入才翻转管理"）；②`:23` 的 `clamp(color,0,1)` 确实截掉水下 HDR 高光——成立，但这是注释声明的 Solas 域仿真取舍；③"光束加在雾后不被消光"是有效的观感批评 | ②③ **可缓**（归入光束重标定工单一起做）；① 撤回 |
| F-08 | **成立（本轮最重要的一条新发现）** | 复算 `m(t)=(1-t)(0.30+0.32t)+t = 0.30+1.02t−0.32t²`：`t∈(0,1)` 全程 <1——**所谓"透光"项只会变暗**；且乘法在 `visibility≈0`（被遮挡）时恒为 0，`sss.glsl:106-112` 注释承诺的"被遮挡的树冠保留一份直射光"在数学上不可达（抬地板需要加法/max，乘法做不到）。净效果：2026-09-16 项 B"朝阳方向有亮边"的实现方向反了，背光树叶比向阳树叶更暗 | **必修**——这是上一轮明确验收的特性被做反，与 SC-39 的"注释↔代码相反"同型 |
| F-09 | **成立（数值两端点我均复核）** | `fog_morning_air_weight`：谷底（mist=1.28）→ `mix(0.62,0.22,1)=0.22`，文档说谷底应为 0.62——**反了**；Y>150（mist=0.96）→ 0.62，文档说应为 0.22——**反了**。且 `scene.glsl:150` 的二次映射 `mix(0.22,0.62,weight)` 使净晨雾量山顶(0.468)>谷底(0.308)，与注释"0.62 at the valley floor, 0.22 above Y=150"完全相反。表 1.05@Y100 vs 代码 1.115、0.70@Y200 vs 代码 0.96 亦不符 ✓ | **必修**（一行反转或按表重写插值） |
| F-10 | **成立**（=GLM 第一轮 F1 的链路描述 + `shaders.properties:45-46` 注释"Water state also supplies terrain lighting/caustics"确为假 ✓） | 同 F-01 | 并入 F-01 |
| F-11 | **成立但属既往已裁决项** | 四处 `fade=1.0` ✓（=T11）；09-13 §13.3 已明确"保留可读的来源结构"不采纳 | **可缓**——Qoder 建议重开（接真实曲线或删除）；必要性取决于是否要远水面 LOD，建议维持搁置但把决定记录在代码旁 |
| F-12 | **成立，影响面需限定** | colortex1 尺寸由水下光束决定、godrays 共用 ✓；但 GODRAYS 仅 ULTRA 档默认开，"4× 成本"只影响 ULTRA 用户 | **可缓** |
| F-13 | **成立** | `water_shafts_resolve` 的 `rayLength` 形参确实从未使用 ✓；SC-33"距离加权重建"未实现 ✓（与 GLM 第一轮 §2 引用 design.md:292 一致） | **应修**（并入光束工单 Step 4） |
| F-14 | **部分成立，实际影响近零，且有一处行号错误** | divergent 流内隐式 LOD 模式在 `deferred.fsh:36,45,51` 属实 ✓；但所涉目标（depthtex0/colortex0）**均未开 mipmap**，隐式导数对无 mip 纹理无实际后果——规范洁癖而非缺陷；`end_sky_buffer.fsh:63` **行号不存在**（文件仅 34 行），实际同类模式在 `:22-29` | **可缓**（P3 卫生） |
| F-15 | **成立（与 GLM 第一轮 F2 互补，两个缺陷都真）** | Qoder 指出 `mix` 权重因子在函数调用外——`puddle_reflection()` 无条件求值 ✓；GLM 第一轮指出天空清屏 alpha=1.0 让该门对"半透明贴天空"像素放行 ✓。**两条独立成立，需合并修复** | **必修**（性能收益最直接的一项） |
| F-16 | **成立，但定性为注释过度承诺** | 涟漪振幅 ∝ puddle、`rippled` 又读同一法线 → 非独立信号 ✓；但作为第二个单调门它仍锐化阈值（≈puddle²），非功能错误 | **可缓**（改注释或换独立信号源） |
| F-17 | **成立**（=GLM 第一轮 §5 雨天行） | — | **应修**（性能工单） |
| F-18 | **成立**（=T7，既往已裁决"不采纳自动守卫"） | Hunyuan A7 给出了更好的处置：不改代码，补注释说明 | **可缓**（照 A7 办） |
| F-19 | **成立（GLM 第一轮漏掉）** | `caustics.glsl:37` 的 `#endif` 提前闭合守卫，文件其余 ~80 行（含全部几何焦散函数）不受保护；文件尾无收尾 `#endif` ✓。当前各编译单元恰好单次 include 所以能编译——一个双 include 就重定义 | **应修**（一行移动，零风险） |
| F-20 | **成立**（=N8 既往项；SUN_MOON_DISCS 确为零引用 token） | 09-13 §13.3 已裁决保留 | 维持搁置 |
| F-21 | **成立**（=GLM 第一轮 F6 子项） | `lit.fsh:371` 死写 ✓ | 并入清理提交 |
| F-22 | **成立（GLM 第一轮漏掉）** | 下界天空：`sky.fsh:142`（skybasic 写 astra_sky）+ `deferred.fsh:165`（deferred 覆盖重算）——每下界天空像素算两遍，前者整个被覆盖 ✓ | **应修**（一行 `discard` 或让 skybasic 在下界走黑路径，参照末地的 `sky.fsh:128-131` 先例） |
| F-23 | **成立，但有正当理由** | `world-1/shadow.vsh:1` 确为 `#version 430` ✓；根因是 `imageAtomicMax`（体素光写入）要求 GLSL 420+——**这不是错误而是必需**，缺的只是一个"为什么用 430"的注释 | **可缓**（补注释即可） |
| F-27 | **部分成立，严重度存疑** | 代码事实 ✓：End 分支抢占 `#elif` 链，`VIGNETTE`/`DITHERING` 选项在末地失效；但这是注释声明的 void 保护（"attenuated at black to preserve the void"），与 T4"末地强制 bloom"同类——属**未文档化的选项语义覆盖**，而 Qoder 将其定为"控制项无效"P1。GLM 判 **Minor**：值很小（0.08 暗角、半 LSB 抖动）、有注释、且设计上末地天空本就是特调 | **可缓**（把 End 例外写进选项注释，或将 End 分支改为叠加式） |
| F-28 | **成立（GLM 第一轮漏掉）** | grep 坐实：`biomeTemperatureSmooth`/`biomeHumiditySmooth` 每帧在 properties 求值、`uniforms.glsl:30-31` 声明，**全树零消费者**；`fog.glsl:225-226` "already temporally smoothed on the CPU" 注释失实——生物群系雾色跳变平滑从未生效 ✓ | **应修**（接线或删两个 uniform + 改注释） |
| F-29 | **成立**（=GLM 第一轮 F6 子项，Qoder 补了显存数字 ~3.9MB/张 ✓） | — | 并入清理提交 |
| F-30 | **成立（GLM 第一轮漏掉）** | 逐项比对：67 个选项中 66 个默认值与 BALANCED 一致，**唯独 `SSS_STRENGTH` 默认 100 vs profile 60** ✓；"raw defaults = BALANCED" 基线声明不成立 ✓。其建议的 check_pack 规则合理 | **应修**（对齐默认值或改注释；规则可并入工具化清单） |
| F-31 | **大部分已可闭环** | `_analysis/iris-runtime/ShadowRenderer.txt:134-135` 确有 `getEntityShadowDistanceMul()` → `entityShadowDistanceMultiplier` 字段（09-13 §13.1 引用的工件真实存在）；比值表算术双方均复核无误 ✓。剩余未证的只是"乘 renderMul 的完整调用链"——该 txt 是字节码摘录，字段使用点可进一步 grep 确认 | **可缓**（补一次源码 grep + 实机一次即可完全关闭） |
| F-32 | **成立** | grep 坐实：`sunrise`/`moonrise` 两 CPU uniform 每帧求值（各含 pow 链）但 GLSL 侧零消费者（仅 uniforms 声明与注释提及）✓ | **应修**（删两处 properties 行 + 声明；或恢复消费） |
| F-33 | **成立** | `lib/noise.glsl` 三函数零外部调用 ✓；`noisetex` 无任何绑定指令（Iris 内建别名也没有消费者）✓；`textures/noise.png` 随包发布但无人采样 ✓。`settings.glsl:221`/`uniforms.glsl:44` 两处描述与实际绑定关系不符 ✓ | **应修**（清理提交；顺带解释 `noiseTextureResolution` const 是否还有存在意义） |
| F-34 | **成立** | 复算 `asin(-0.156)=-8.97°`、`asin(0.242)=+14.0°` ✓；"±4°" 只是两个拐点 ✓ | 并入清理提交 |
| F-35 | **成立** | `colors.glsl:44` "default 5 = 0.05" 双重错误：默认是 8；且 5×0.001=0.005 非 0.05（注释下一行的算式本身是对的）✓ | 并入清理提交 |
| F-36 | **成立** | `pow100` 实为 15 次乘（pow64 内部重算 pow32）✓；残留字面整数 `pow` 清单（fog:127,210 / end_system:28,29 / bloom_resolve:9——`pow(bloom, vec3(8.0))` 确认 ✓）与 GLM 第一轮 F5 同类 | 并入 pow 迁移收尾 |
| F-37 | **成立** | `THIRD-PARTY.md:40`（旧 entity 公式）、`:86`（`smooth(71, rainStrength, 3, 3)` vs 实际 `..., 3, 0.8)`）、缺 `pow.glsl` 行——三处 grep 坐实 ✓；且 check_pack #8 只匹配文件头所以漏检的分析成立 | **应修**（台账即发布闸门，漂移会污染发布决策） |
| F-38 | **不成立（表述说反了）** | `#ifndef R11F_G11F_B10F const int ... = 0` 的 `=0` 分支恰是**常态求值路径**（宿主不定义宏时，GLSL 侧 const 就取这个 0），"从不参与求值"说反；守卫本身有真实用途（宿主以宏提供 token 时避免重定义） | 不采纳 |
| F-39 | **成立**（Qoder 自己已降 P3，合理） | `srgb_decode` 无负钳位、依赖调用方 ✓ | 并入清理提交（函数内钳位） |

**对 Qoder 报告的总体评价**：证据纪律极好（每条带行号、复算表、调用者计数；§9 主动剔除了自己无法闭环的子报告条目）。两点系统性偏差：一是把 2 条"注释声明的刻意设计"（F-07 的域仿真、F-27 的 void 保护）按缺陷定级，低估了"取舍已声明"与"断言失实"的区别；二是对 Iris 引擎机制（flip 双缓冲）缺一次核对导致 F-07①误报。

---

## 3. Hunyuan 报告逐条核验

| # | 核验结果 | 证据要点 | 必要性权衡 |
|---|---|---|---|
| A1 | **成立（三方中价值最高的单项发现之一，GLM 第一轮漏掉）** | `final.fsh:88` 无条件执行完整 `exposure→tonemap→srgb`，`:90` 水下整体覆盖 ✓。**注意其成立机理**：分支是动态的，编译器**不能**做死存储消除，水下像素确实白付整套 Uchimura（多次 pow）+ sRGB ✓。修复方案（三元二选一）行为等价 ✓ | **必修**（一行重构，零风险） |
| A2 | **成立（7 处全部 grep 坐实）** | `README.md:5` "水下≈Steadfast、水面≈Solas"确与 SC-24 相反 ✓；`:20` "零 compute" vs 10 csh ✓；`:39` "仅 8 个可达/lit-final 未接线" vs 实测 52/54 ✓；`:24` 分级 112/115/104 vs 100/100/102 ✓；`:31/:33` 影距/软化值 ✓。README 是唯一面向用户的发布物，第 1 条会让验收得出相反结论 | **必修**（提交前重写） |
| A3 | **成立**（=GLM 第一轮 P3 / Qoder 工作区提示） | 计数口径差异（39+26 vs 74 vs 42 tracked）不影响实质：核心文件全部未提交 ✓ | **必修**（三方一致的第一优先） |
| B1 | **大体成立（四衰减点中三个半完全成立）** | ①方向因子互斥 ✓（=F-03，姿态表数值复核一致）；②采样只覆盖到 ~18.6 格 ✓（源码注释自认"about 17 blocks, not 40"）；③内切圆剔除 21.5% ✓（π/4；补充：接收端 `shadowmap.glsl:76` 对主世界也用 radial 惯例，故此处是"与末地方形分支不一致"而非孤例）；④glare 竞争——**结构成立、数值成立**：经 §1 钉死约定后，正午 `shadowFade=1` 且 `timeBrightness=1` 同时成立，其 8.7× 雾放大与 10.4% 光束占比的最坏行有效（GLM 核验中曾怀疑两曲线反相，经约定确认同相）| **必修**（并入光束工单；SC-33"移除角向亮晕"确实只做了一半的判断准确） |
| B2 | **成立（对 GLM 第一轮的重要补充）** | 谱序结论与我一致 ✓；其增量："**效果已存在于 WATER_COLD 档**"（15 格归一化色相 (0,0.10,0.90)）——把问题从"没实现"精确定位为"默认档谱序相反 + 用户无从知晓"，其"把三档观感写进 lang"的零成本建议很好 | **必修**（同 F-05/06 合并工单） |
| A4 | **成立**（=GLM 第一轮 F3 / 同一漏网导数） | — | **必修**（一行） |
| A5 | **成立** | docs/ 最新为 09-16，09-17 两轮（含 SC-39 三次返工的教训）只存在于未提交的 session-log ✓ | **应修**（补一篇 09-17 归档文档） |
| A6 | **成立（8 处逐一坐实）** | grep 结果与清单完全一致 ✓；`design.md:175` 明文"global 不 include 其他 global"而校验器不覆盖 ✓。"受控演进、无环、需回填决议或收敛目录"的判断准确 | **应修**（更新决议文字即可，无需改代码） |
| A7 | **成立**（=T7；处置建议优于 09-13 的"不采纳"——补注释而非加守卫 ✓） | — | **可缓** |
| A8 | **成立**（=N8 既往项） | — | 维持搁置 |
| A9 | **部分成立，归因有误** | `end_blackhole.glsl:76` 的 `dFdx` 分支确实可活 ✓；**但归因到 sky.fsh 错了**——末地 skybasic 在 `sky.fsh:128-131` 提前 `return vec4(0)`，从不调用 astra_sky；真实活路径是 lit.fsh 的末地**冰面/水面回退**（罕见场景）→ 实际影响比声称的小得多 | **可缓**（改注释或传参） |
| A10/A11/A12 | **成立** | design.md §12 停在 09-07 ✓（GLM 第一轮直读过）；"零 compute"边界 vs 10 csh ✓；docs 53 份 ✓ | **应修**（文档回填批次） |
| §4 回溯核验表（N1..T10 全 ✅） | **与 GLM 第一轮核验完全一致** | 14 项逐条对上 ✓——"该项目修复记录可信"的结论可采纳 | — |
| §9 排除表 | **合理** | 11 条排除均与源码一致（抽查 `light_shafts` 无 SHADOWS 守卫一条：整段确在 `ASTRA_SHAFT_MARCH_PASS` 内 ✓） | — |
| §12.2 composite4 | **成立（三方最大单项性能发现，GLM 第一轮完全漏掉）** | `water_bloom.fsh:5` `colortex0MipmapEnabled=true` 恒开 ✓（主 HDR 缓冲每帧生成 mip 链 + ~33% 显存，只服务一个非水下即 discard 的 pass）；colortex7 无 size 声明 → 全分辨率 ✓；`getBloomTile` 6×6 × 4 tile = 144 tap（padding 窗口内最坏值）✓；非水下全屏 discard 仍全量调度 ✓。其"分辨率失配"根因判断（Solas 原作跑在低分辨率 tile 上）准确 | **必修（性能第一优先）**——`size.buffer.colortex7=0.25` 是一行低风险改动 |
| §12.3 composite3 | **成立** | 非水下时确为全屏纯拷贝 ✓（`water_composite.fsh` 读 colortex0 → 原样写回）。注意其"并入 final"建议与 composite4 的采集顺序耦合（水下 bloom 采集的是合成后场景），标中等风险正确 | **应修**（先做注释声明，合并移到中风险批次） |
| §12.4 composite2 写 0 | **成立** | BALANCED（!GODRAYS + 光束开）非水下全屏写 0，且被 colortex1=1.0 放大到全分辨率 ✓ | **应修**（colortex1 降 0.5 同时缓解此项与 B1 采样） |
| §12.5 deferred 恒开 | **部分成立** | 代码事实 ✓，但两份报告都漏了 `design.md:493`（SC-34-F1）已明文记录"ASTRA_SCENE_COPY 与三维度 deferred 已在接手时常开，当前继续如此"——**这是已记录的决议，不是未登记偏离**；"用户关掉三项水效果后仍跑"的浪费主张仍成立 | **可缓**（条件化是合理演进，但须先改决议） |
| §12.6/12.7 | **成立**（=GLM 第一轮 §5/Qoder F-17 重合 + 雨天纹理清单增量） | — | 并入性能工单 |
| §12.9 执行顺序 | **合理，予以采纳** | colortex7 → colortex1 0.5x → deferred 条件化 → 拿首个帧率基线，再动中风险项——与 GLM 第一轮"先补基线"的结论一致且更具体 | 采纳为性能工单主线 |

**对 Hunyuan 报告的总体评价**：数值复现纪律最好（两张色相表、姿态表、往返误差全部可复算），§4 的历史修复回溯与 §9 排除表显著降低了重复排查成本；A1 与 §12.2 两条是实打实的增量。偏差：A9 归因错误、§12.5 漏看 design.md:493、个别计数口径（39+26）与其余两方不一致但不影响结论。

---

## 4. 与 GLM 第一轮报告的对账

**维持有效**：F2（天空清屏 alpha 门控漏洞——与 Qoder F-15 构成同一缺陷的两面，合并修复）、F3（=A4）、F4（夜色失色方向）、F5（pow 残留，位置清单以 Qoder 更精确）、F6（死资源清单，以 Qoder F-21/29/33/35/37 更完整）、F7（水下 tonemap 选项失效）、S1/S2（varying 与 SKY_MODE 蓝图偏离——两份外部报告均未覆盖）、§8（水体专项根因）与 §9（性能建议）的主体。

**第一轮的两处修正（由外部报告触发）**：
1. **F1 爆炸半径低估**：只写了 colortex5.a 失效，漏了 blend `SRC_ALPHA` 使 rgb 一并丢失（Qoder F-01 补全）——严重度维持 Important，但修复紧迫性上调。
2. **漏掉两条高价值发现**：A1（水下重复 tonemap）与 §12.2（composite4 + colortex0 恒开 mipmap）——均已在第一轮应覆盖的 final/water_bloom 链上，属于第一轮的覆盖缺口，如实记录。

**第一轮的独有贡献（两份外部报告均未覆盖）**：S1 varying 接口偏离、S2 默认天空翻转未登记、水下 TONEMAP 失效未文档化、`water_composite` 域仿真的取舍分析、性能建议中的"天空求值进 LUT"（第一梯队）。

---

## 5. 三方共识分层（置信度即修复优先级）

**三方或两方独立收敛（置信度最高，直接进必修）**：
1. colortex5.a 写错缓冲 + blend 连带 rgb（GLM-F1 + Qoder-F01/F10 + Hunyuan §9 间接）；
2. 水下光束方向门正午恒零（GLM-R-E + Qoder-F03 + Hunyuan-B1①，前提已经 §1 钉死）；
3. 默认水型谱序绿<蓝 → 深水不可能变蓝 + 深度封顶 + 无 in-scatter（三方，含 COLD 反证）；
4. SC-39 积水门控双缺陷（GLM-F2 天空 alpha + Qoder-F15 无条件求值）；
5. 末地石分支内导数（GLM-F3 + Hunyuan-A4）；
6. 工作区未提交（三方）、README 失实（Hunyuan，GLM 抽查复核）、`pow.glsl` 残留 pow（GLM-F5 + Qoder-F36）、astraRipple3（GLM + Qoder）。

**单方独有、经本轮核验成立（按报告来源补入工单）**：Qoder——F-08（SSS 变暗）、F-09（晨雾反向）、F-19（caustics 守卫）、F-22（下界双算天空）、F-28（biome 平滑死链）、F-30（SSS 默认值）、F-32/F-33/F-34/F-35/F-37；Hunyuan——A1（重复 tonemap）、A2（README）、A5（09-17 无归档）、A6（8 处 global→global）、§12.2（composite4）、§12.4（composite2 写 0）、B2 的 lang 建议；GLM——S1/S2/F4/F7/天空 LUT 建议。

**经核验不成立或撤回**：Qoder F-07①（同缓冲读写 UB——Iris flip）、F-38（守卫语义说反）；Hunyuan A9 的 sky.fsh 归因、§12.5 的"未登记偏离"定性（design.md:493 已记录）。

---

## 6. 本轮新发现

**N-1（Minor，注释错误 + 历史诊断存疑）`diffuse.glsl:358-360` 的 shadowFade 注释把正午与晨昏写反，且自相矛盾。**
注释称 astraSolasShadowFade"evaluates to ZERO at noon (1 at sunrise/sunset, 0 at sunAngle 0.5)"。按 §1 钉死的约定（sunAngle 0.25=正午）：`shadowFade(0.25)=1`、其零点在 sunAngle∈{0, 0.5, 1} 即日出/日落——**正午恰是 1**。且注释内部自相矛盾（"1 at sunrise/sunset"与"0 at sunAngle 0.5"在 0.5=日落 的约定下互斥）。连带影响：该注释是历史修复（"正午直射光被清零导致平蓝"）的诊断依据——若 fade 正午=1，那次故障的归因存疑（现行修复按太阳高度门控本身仍正确）。建议据实改写注释；顺带在 `shaders.properties:296-305` 的 Solas uniform 段补一行 sunAngle 约定注释（§1 的产出）。

**N-2（流程）三份报告各自的"未证前提"应集中清账。**
本轮实际钉死了 sunAngle 约定（§1）；仍悬而未决的清单：① hand 与 deferred 的真实相对顺序（Qoder F-02 的探针）；② entityShadowDistanceMul 的完整乘链（Qoder F-31 剩余半环，`ShadowRenderer.txt` 可 grep 闭环）；③ 跨驱动编译（三方均列）。建议把这四项做成一张 `qa/open-premises.md` 台账，逐项记录"结论 + 证据位置"，防止下一轮审查重复悬置。

---

## 7. 统一修复清单（三方 + 两轮 GLM 合并，按必要性权衡排序）

**第一批 · 必修（正确性与用户点名需求，全部小改动）**
1. `lit.fsh:362` 删除 + `properties:54-56` colortex5 blend 改 `off`（F-01 完整版）+ 删三条伪注释；
2. 光束工单：方向门解耦（F-03/B1①，用 refractSun 或 HG 相位）→ 采样分布铺满 maxDist（B1②）→ 圆形判据改方形（B1③）→ 重标定衰减链与 glare（F-04/B1④）→ resolve 距离加权（F-13）；
3. 水色工单：默认档谱序对调或深度插值谱（F-05/B2）→ 深度上限放宽（F-05）→ 受控 in-scatter + deepFallback 改水体色（F-06/GLM §8）→ 三档观感写进 lang（B2）→ 先改 `design.md:79` 分工；
4. `final.fsh:88-91` 三元重构（A1）；
5. F-08 透光乘子改为只加不减；F-09 晨雾端点反转；
6. F-15 + GLM-F2 合并修复（门内求值 + 天空 alpha 处理）；
7. A4/`lit.fsh:231` 足迹提出分支。

**第二批 · 必修（流程与发布物）**
8. 按主题拆 2–3 次提交（三方一致第 1 优先）；9. 重写 README（至少先改三对标方向）；10. `qa/benchmarks.md` 填首个实测基线；11. 补 09-17 归档文档（A5）+ `qa/open-premises.md`（N-2）。

**第三批 · 应修（性能，按 Hunyuan §12.9 + GLM §9 合并）**
12. `size.buffer.colortex7=0.25`（一行）→ 13. colortex1 降 0.5 → 14. deferred 条件化（先改 design.md:493 决议）→ 15. 天空求值 LUT/早退（GLM 第一梯队，预期为最大 ALU 项）→ 16. 阴影混合 PCF 转正（GLM/Qoder 各自提出，需等价性对拍）→ 17. rainy_air / 云 march / 水下 march 降采样。

**第四批 · 记录与清理（一次提交）**
18. F-19/F-21/F-22/F-23（补注释）/F-27（写明例外）/F-28/F-30/F-32/F-33/F-34/F-35/F-36/F-37/F-39、A6（决议回填）/A10/A11/A12、GLM-F6/F7/S1/S2 的注释与登记。

**工具化（Hunyuan §7.3 与 Qoder §7.2 殊途同归，建议合并落地）**：check_pack 增两条规则——① screen 上的选项必须有 settings.glsl 之外的消费点（挡 F-20/F-28/F-32 类）；② 收集 `colortexNFormat` 声明，对无 alpha 通道格式的 `.a` 写入直接 FAIL（挡 SC-39 那一整类"编造的格式断言"）。

---

## 附录：本轮核验方法与边界

- **每条 finding 都回到源码行号复核**；数值类（谱序表、姿态表、G/B 比、衰减链、pow100 乘数、晨昏角度）全部手算复算；调用者计数用 grep 交叉（biomeSmooth/sunrise/moonrise/noise 函数/shadow_water_depth/water_volume_state/ripple3）。
- **sunAngle 约定**经 Solas 参考源码语义钉死（§1），仍建议一次 5 分钟实机确认后写入注释。
- **未覆盖**：实机画面与帧率（三方共同边界）；Iris 引擎 hand/deferred 顺序的最终定论（F-02 探针）；27 个 compute 程序逐行；`_analysis/` 其余参照包。
- 本报告与三份既有报告互为补充：**核验裁决以本报告 §2/§3 为准**，修复工单以本报告 §7 为准。
