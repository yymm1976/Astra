# Astra 全量代码审查报告（GLM-5.3-Flash）

> 状态：历史审查，仅适用于文中审查时的源码；当前入口及已纠正结论见 [文档索引](README.md)。条目未逐项标为当前缺陷，也不表示全部已经解决。

**审查者**：GLM-5.3-Flash（ZCode 只读审查）
**日期**：2026-09-20（同日补充：§8 水体专项复盘——水下光束与浅→深色彩过渡为何未实现；§9 整体性能优化建议）
**审查基线**：工作区 = 提交 `7e3f51c` + 42 个文件的未提交改动（含 2026-09-16/17 视觉体验轮、SC-39 两轮修正与性能轮的全部内容）
**性质**：只读审查。**本次未修改任何代码文件**，仅新增本报告。
**方法**：蓝图（`.specs/astra-shader/design.md`）与三轮历史审计（`docs/2026-09-13-astra-full-audit.md`）、会话日志逐条对读；核心管线与全部功能模块逐文件人工审读；`check_pack.py`（0 FAIL / 1 WARN / 10 PASS）与 `cost_census.py` 实跑佐证；三维度入口壳 diff、缓冲写读矩阵、选项消费图、pow 负底数/死代码/导数控制流等全树模式扫描。
**未做的事**：无游戏内验证。**所有画面与帧率结论均不在本报告范围内**（与项目自身各轮审计同一边界）。

---

## 0. 总体结论

| 维度 | 评级 | 说明 |
|---|---|---|
| 架构纪律 | **良好** | lib/global/program 三层职责清晰且被校验器强制；三维度壳经 diff 验证仅差 DIMENSION 宏 |
| 构建健康度 | **良好** | `qa/glsl-audit-fixes.log`：267 linked / 0 failed / 27 compute；check_pack 实跑 0 FAIL / 1 WARN |
| 代码质量 | **良好偏上** | 注释-证据密度远超同类项目；历史审计 11 项修复全部验证落地；本轮仍发现 1 处缓冲契约破坏 |
| 蓝图一致性 | **中上** | 渲染路线/pass 链/选项规模/维度特调与 design.md 一致；2 处偏离未在蓝图登记（§3） |
| 性能 | **中上** | 无"必挂"级热点回归；结构性优化（烘焙/降分辨率/早退）扎实；剩余风险集中在护栏缺失 |
| 顽固问题 | **3 项未解** | 行为护栏缺失、实机验证积压、42 文件未提交（§4） |

**结论：需修复（0 Critical / 2 Important / 5 Minor）后提交。**
两个 Important 都集中在 2026-09-17 SC-39 积水反射改造的缓冲通道选择上：功能今天"碰巧"没有可见故障，但一个是**对已文档化缓冲契约的静默破坏（且伴失实注释）**，另一个让雨天部分像素为被丢弃的结果支付全价射线步进。这正是项目自己在 SC-39 复盘里写下的失效模式——"注释描述了意图、代码做了别的事"——第三次出现。

---

## 1. 架构评估

实测确认以下结构性事实（本次审查的正面结论）：

1. **三层分层严格成立。** `lib/`（声明）→ `global/`（实现）→ `program/`（编排）无反向依赖；`check_pack #4` 实跑确认 182 个编译入口全部可达 `lib/settings.glsl`、无悬挂 include、无未注册模块（唯一 WARN 是已知有主的 Voxy C5）。
2. **三维度入口壳一致。** 对 `gbuffers_water` / `gbuffers_terrain` 等 40 对壳做 root ↔ `world1/` ↔ `world-1/` diff，差异**仅有 `#define DIMENSION_*` 一行**，无漏改实例（历史 N5 的结构风险仍在，但本轮未发现实际漂移）。
3. **维度管线分叉自洽。** 末地的 `deferred`（0.75 分辨率天空烘焙 → colortex9）与 `deferred1`（介质施加 + 全分辨率星场合成 + colortex0/4 写出）顺序成立；下界走共享 `program/deferred.fsh` + `DIMENSION_NETHER` 分支；水体状态链、compute 体素光链（9 步 ping-pong）与文档描述一致。
4. **选项注册表单一来源且双向一致。** 67 项选项在 `shaders.properties` ↔ `lib/settings.glsl` ↔ 双语 lang 三方一致（check_pack #2/#3 PASS）。历史 N1"假控件"已修复：`ENTITY_SHADOW_DISTANCE` 现经 8×5 字面量表真实驱动 `entityShadowDistanceMul`，抽查 `64/32 → 0.3333`、`256/96 → 0.25` 等组合，公式 = 实体距离 ÷（影距 × 1.5），与 §13.1 核实的 Iris 实际算式吻合。
5. **来源台账机器可查。** 48 条台账 ↔ 文件头 ↔ 授权规则三方核对 PASS（check_pack #8）。

---

## 2. Standards Findings

严重度定义沿用项目审计惯例：Critical = 崩溃/数据丢失；Important = 逻辑错误、契约破坏、需求偏离；Minor = 低风险缺陷、清理项。

### [Important] F1 — SC-39 积水掩码覆盖了 colortex5.a 的"水面有效性"标志，且注释断言失实

**位置**：`Astra/shaders/program/lit.fsh:362`（写入）；`Astra/shaders/program/water_state.fsh:19`（被破坏的读者）；`design.md:85`（契约定义）
**证据**：
- `lit.fsh:354-356` 在水体 pass 中向 `gl_FragData[1]`（即 **colortex5**，RENDERTARGETS `0,5`）写入 `vec4(高度RG, 天空光B, 1.0)`——`.a=1.0` 是 design.md §2.3 明文定义的"**A 有效性**"标志。
- SC-39 追加的 `lit.fsh:362`：`gl_FragData[1].a = material == 0u ? clamp(puddle, 0.0, 1.0) : 0.0;`。水体 pass 的 `puddle` 恒为 0（其计算块被 `#if defined ASTRA_TERRAIN && !defined ASTRA_TRANSLUCENT` 排除），水材质 `material==1u` 走 else 分支也是 0——**colortex5.a 从此对所有片元输出 0**。
- 唯一消费者 `water_state.fsh:19` 以 `if (data.a < 0.5) continue;` 读取该标志：20×12 网格搜索因此**永远失败**，"从可见水面选最近局部界面"（design.md §2.3）的行为整体失效。
- 注释（`lit.fsh:357-358`）声称 "`.a` held a constant 1.0 **with no consumer**"——该断言与 `water_state.fsh:19` 及 design.md 直接矛盾；同注释中"translucents and weather: 0, via the else-branch below"描述的分支也不存在（translucent pass 的 RENDERTARGETS 只有 `0`，根本不写 colortex3）。

**影响**：当前爆炸半径有限——`colortex6` 的唯一外部读者就是 `water_state.fsh` 自身的"保留上一帧"回退（全树 grep 证实无其他消费者），所以**今天没有可直接观察的画面故障**；水下场景由 `water_state.fsh:42-50` 的阴影图回退部分兜底。但这是对已文档化缓冲契约的静默破坏：任何按设计恢复 colortex6 消费者（设计原意是地形照明/焦散消费）的改动都会拿到"地上全零、水下只有阴影回退"的垃圾数据。且它带着一条声称安全的错误注释合入——与 SC-39 两轮自审总结的失效模式完全同型。

**建议**：删除 `lit.fsh:362` 这行，恢复 `gl_FragData[1].a` 的有效性语义（水面 1.0 / 其余 0.0）。若目的确实是防止水面像素继承地下积水的反射，应在 deferred 侧解决（例如要求 `depthtex0 == depthtex1`，或对 colortex3.a 附加"该像素是水面"的排除位），而不是写进 colortex5。

### [Important] F2 — deferred 积水反射门控不防"天空清屏 alpha=1.0"，雨天雨丝像素为被丢弃的结果支付全价射线步进

**位置**：`Astra/shaders/program/deferred.fsh:134-148`；`Astra/shaders/lib/settings.glsl:357`（清屏色）；`Astra/shaders/lib/encoding.glsl:35-43`（解码推导）
**证据**：
- 门控 `standingWater > 0.15` 读的是 colortex3.a。所有不透明写手都会覆写 `.a`（地形/实体/手，`lit.fsh:371-374`），**但天空像素没有任何写手**，colortex3 保持清屏值 `vec4(0.498, 0.0, 0.0, 1.0)`——alpha=1.0。
- 半透明几何覆盖天空的像素（雨丝、粒子、信标光柱——它们的 RENDERTARGETS 均只有 `0`，不写 colortex3）满足 `depth < 0.999999`（depthtex0 含透明层）且 `(lightData & 128u)==0`（127），于是 `standingWater = 1.0` 通过门控。
- 通过后 `mix(source, puddle_reflection(...), weight)` 中的函数调用**无条件求值**：最多 96 步深度采样 + 6 步细化（`deferred.fsh:32-68`）。混入权重由 `upFacing` 归零——天空像素 colortex3.gb=(0,0)，`decode_unit_vector(vec2(-1,-1))` 精确解出 (0,0,-1)，`n.y=0` → `smoothstep(0.55,0.92,0)=0`——**结果被乘零丢弃，但 96 步照跑**。
- 平衡/极致档默认开启 `SCREENSPACE_REFLECTIONS`，雨幕通常覆盖可观屏占比，每个存活雨丝像素最多 ~108 次深度读取全部浪费。

**影响**：无画面错误（权重为 0），纯性能浪费 + 门控语义漏洞；与 F1 同源——SC-39 把"是否积水"寄托在"每个不透明写手都写 0"的约定上，没有处理"没人写的天空"这一默认值。

**建议**（任选其一，均为小改）：天空像素的 colortex3 清屏 alpha 改为 0（`settings.glsl:357`，需同步核对 `.r=127` 的 skylight 语义不受影响）；或门控追加 `(lightData & 127u) > 0`；或将 `puddle_reflection` 的调用移入 `weight > 0.001` 的分支。

### [Minor] F3 — 末地石分支在非均匀控制流内取 dFdx/dFdy（N9/T6 同类问题回潮）

**位置**：`Astra/shaders/program/lit.fsh:231`（`material == 11u` 分支内）
**证据**：`float footprint = max(length(dFdx(texcoord)), length(dFdy(texcoord))) * 256.0;` 位于 `#ifdef DIMENSION_END` + `if (material == 11u)` 之内。`material` 是 flat uint，分支按图元一致，但相邻不同材质图元的 quad 内 helper invocation 分歧时导数未定义（规范语义）。表现：末地石远处 gloss 收敛值在材质边界可能跳变。
**影响**：低（视觉细节、仅末地）。本轮 T6 的修复（涟漪足迹在 `lit.fsh:44-48` 提前到 alpha 丢弃之前）证明团队已掌握正确做法，此处是漏网的一处。
**建议**：把 `footprint` 提到 material 分支之外计算（与 `lit.fsh:46-47` 的 rippleFootprint 同位）。

### [Minor] F4 — night_desaturation 与"背光面跳过"的假 visibility=1.0 冲突，夜间背光面获得最大失色

**位置**：`Astra/shaders/global/lighting/diffuse.glsl:342-346`（facingAway → `visibility = vec3(1.0)`）；`:340-341`（注释）；`:236-242` 与 `:447-451`（消费者）
**证据**：假 1.0 的注释理由是"every consumer multiplies it by a facing term that is zero here"——但 `night_desaturation()` **不乘任何朝向项**，直接取 `lit = dot(visibility, luma权重)`。于是夜间背光面 `lit=1.0`，失色量达到满幅 `0.20 × night × skyLight × localAttenuation`；而朝向月亮但被遮挡的面 `lit` 只有夜色填充抬升后的约 `0.4·skyLight²`。方向反了：文件头与会话日志（2026-09-16 A 项）明文意图是"**背光面不失色**"。
**影响**：幅度受限（强度系数 0.20、再乘天光与局部光衰减），属夜间色调 nuance，非可见缺陷级；但它是又一条"注释意图 ≠ 代码行为"。
**建议**：跳过阴影采样时传一个"未采样"标记（如 `-1` 或独立 bool），让 `night_desaturation` 对背光面按遮挡处理（lit 取 0 或跳过失色）。

### [Minor] F5 — `lib/pow.glsl` 的新约定迁移不完整：仍有 23 处字面整数指数走 `pow()`

**位置**：全树 `pow(x, <整数字面量>)` 共 23 处。代表例：`global/atmosphere/fog.glsl:127`（`pow(fragDistance, 3.0)`，每个受雾像素）、`lib/twilight.glsl:46-51`（3.0/24.0/180.0/1400.0，晨昏天空像素）、`program/lit.fsh:240,242`（24.0/5.0，末地石）、`global/dimension/end_system.glsl:28-29`（8.0，星野）。
**证据**：`lib/pow.glsl:31` 自定规则为"literal integer exponent -> these helpers; anything else -> pow()"，且文件头声明 pow(字面整数) 在各厂商均为超越函数展开、不会折叠。SC-39 性能轮只迁移了部分调用点（blocklight/sss/sky_gradient 已用 `pow4/square/cube`，验证一致）。
**影响**：非缺陷，是约定漂移 + 遗漏优化；fog/twilight 属每像素路径，收益可观。所有这 23 处底数均已核对非负，无正确性问题。
**建议**：按 `lib/pow.glsl` 的验证流程（对拍 Python 精确值）补齐这批迁移；或在该文件头改口"新代码才要求"，避免规则与现实脱节。

### [Minor] F6 — 死资源与死代码（一次提交可清完）

| 项 | 位置 | 说明 |
|---|---|---|
| astraRipple3 注册+声明但零采样 | `shaders.properties:326`、`lib/uniforms.glsl:41` | 全树无采样点；properties 注释"layers 2 and 3 fade in"与实现（仅用 1/2 两层）不符；128×7680 纹理每张约 3.7 MB 白占显存。要么接线，要么删除注册 |
| `dither2` 形参未使用 | `global/dimension/nether_volume.glsl:55` | `astra_bliss_fog(viewPos, 0.5, 0.5)` 的第二实参无消费者 |
| `#ifndef ReflectedFog` 恒真残留 | `global/dimension/nether_volume.glsl:120` | Bliss 移植残留（与已清除的 N4 同源），现状等价于 hazeDensity 恒 ×0.65，应删宏留下常数并注释 |
| `end_sky()` 的 `voidTint`/`time` 形参未使用 | `global/dimension/end.glsl:16`；调用点 `program/scene.glsl:43` | 还在传 `end_void_tint(cameraPosition.y)` 与 `frameTimeCounter`，函数体内均未消费 |
| surfaceWet 死存储 | `program/lit.fsh:371`（写入 .b→.a 后被 `:374` 覆写） | `surfaceWet` 变量本身仍用于变暗（`:182`），仅这条 `.a` 写入无效；顺带 `:358-361` 注释关于"carries the opaque terrain's value"的断言在 water pass 中不成立（puddle 恒 0） |

**建议**：合并为一次清理提交；每项都是机械删除/改注释，无行为变化（astraRipple3 的取舍除外，需先决定是否真要第三层涟漪）。

### [Minor] F7 — 水下时 TONEMAP_OPERATOR 四档选项整体失效，且未向用户说明

**位置**：`Astra/shaders/program/final.fsh:90`；`Astra/shaders/lib/solas_water.glsl:114-121`；`Astra/shaders/lib/settings.glsl:173-174`
**证据**：`isEyeInWater == 1` 时 displayColor 改走 `solas_water_display(apply_exposure(hdr))`——Solas 固定 tonemap 曲线 + gamma 编码，`apply_tonemap()`（Uchimura/AgX/ACES/Reinhard-Jodie）被完全旁路。这是 Solas 域适配的有意设计（`solas_water.glsl:104-105` 注释可证），但 TONEMAP_OPERATOR 的 GUI 注释没有任何"水下例外"说明。
**建议**：在 `settings.glsl` 该选项注释与双语 lang 中补一句"水下始终使用 Solas 曲线"；或在 `final.fsh` 加一行说明性注释。

---

## 3. Spec（与蓝图的一致性）

**需求遗漏：未发现。** design.md §4 "v1 基础盘"的功能矩阵（光照/天空/水/后处理/下界/末地）逐项对到了实现；下界（体素光 compute 链、独立雾/天空/光照）与末地（黑洞测地线、A/B 环、73 天体、两段式天空）超出基础盘的部分均有专门设计文档与用户需求背书，不属 scope creep。

**受控偏离（有记录，不阻塞）**：
- 渲染路线从"deferred 仅水效果开启"改为"ASTRA_SCENE_COPY 恒开"——已由 SC-34-F1 决议覆盖旧条文（design.md:493）。
- 末地环食节奏、黑洞"阴影内星场"表述——§4.3 已记录为受控变更/设计书自身错误。
- 三档 profile 的具体数值（SHADOW_SOFTNESS=8 而非 16 等）随视觉轮演进，shaders.properties 即为记录。

**未登记的偏离（建议补记，均 Minor）**：

| # | 偏离 | 蓝图原文 vs 实现 |
|---|---|---|
| S1 | **varying 接口被实质突破** | design.md:205 冻结 varying 预算为 9 标量并明文"无位置/切线/**shadowPos** varying"；实际 `lit.vsh:22-23` 传递 `cameraRelativePosition`(3) + `surfaceShadowPosition`(3)，加基础 9 标量共 15，water pass 另加 10（切线系 4 + 视向量 3 + 距离 1... 实际 3+3+3+1）。逐顶点预投影在性能上是合理权衡，但 `lit.vsh:1` 仍自称"varying contract is frozen in design 3.2"，蓝图侧无任何决议推翻原文 |
| S2 | **默认天空翻转** | design.md:249："Minishita 迷你物理大气"为设计、渐变为"备选"；实际 `SKY_MODE` 默认 1 = Complementary 渐变移植（`settings.glsl:80`，三档 profile 均为 1），翻转未在 design.md 或 escalations 登记 |

**Spec 轴的边界**：design.md §8 的验收标准 1/2/3/4/6/7（双版本编译、4050 帧率、三对标目视、zh_CN 全覆盖、Voxy）中，除"编译零错误"有证据外，**其余全部依赖实机，当前无任何一项有修改后的画面/帧率证据**——这不是本报告能替项目关闭的项，见 §4-P2。

---

## 4. 顽固问题（跨轮次持续存在）

| # | 问题 | 状态与证据 |
|---|---|---|
| P1 | **行为护栏缺失（原 R1）** | 末地 GPU 挂起的根因（每像素代价无自动化检查）至今未补：`cost_census.py` 在 §13.2 改造为"诚实的循环源码清单"，明确自述"Fetch sites are lexical, NOT fetches/pixel"——它是审读定位工具，不是护栏。§13.3 决定不将其接入 check_pack（理由：无配置预处理/调用图/计时的工具不能当保证）。决定本身自洽，但**"新增循环必须报告上界"仍纯靠自觉**，同类风险敞口原样存在 |
| P2 | **实机验证积压持续滚雪球** | 会话日志显示 2026-09-12 之后每一轮（晨昏联动、Complementary 重调、09-15 反馈轮、09-16 视觉体验轮、SC-39 两轮、性能轮）全部以"未取得修改后的游戏画面与帧率，不宣称画面结论"收尾。改动一层叠一层地落在未经视觉确认的基线上，一旦实机出图，归因难度随层数上升。历史审计 §10.2 同一建议至今未执行 |
| P3 | **工作区卫生（原 R7 恶化）** | 未提交改动已从审计时的 27 项涨到 **42 个文件**（含 SC-39 全部修复、`lib/pow.glsl` 新文件、两份研究文档）。历史审计"尽快提交或明确丢弃"未执行；误回滚将同时丢失两轮关键修复 |
| P4 | **跨驱动验证缺失** | 全部 267 项编译证据来自同一台 RTX 4050 + NVIDIA 572.83。N2/T1 类可移植性问题虽已修正（本轮扫描确认 `#if 2==0`、LPV 残留、负底数 pow、全局非常量初始化器四类模式全树零残留），但"他厂驱动编译一次"自 09-13 起始终未排期 |
| P5 | **Voxy（C5）未接线** | check_pack 唯一 WARN，`voxy_opaque/translucent.glsl` 仍为占位；`VOXY_SUPPORT` 靠 `lib/uniforms.glsl:110-112` 的 bootstrap const 维持选项可注册。已知有主，非缺陷 |

已解除的顽固问题（本轮验证）：N1 假控件（§1.4）、N9/T6 分支内导数（deferred.fsh:100-101、lit.fsh:44-48、surface.glsl:306-310 三处均前置）、T3 云雨天泄漏（scene.glsl:46-49 + weather.glsl:124-127 + clouds.fsh:21-26 三处联动正确）、T4 末地强制 bloom（shaders.properties:64 已改 `=BLOOM`）、T5 star_visibility 巧合通道（end_blackhole.glsl:72 入口显式重置）、T1 负底数幂（end_blackhole.glsl:115-118 改自乘）、N7 闪电零向量（blocklight.glsl:165）、R2/R6 格式与注释矛盾（water_buffer_formats.glsl:16-17 colortex2=R11F_G11F_B10F，settings.glsl 注释已改写）。

---

## 5. 性能

**结构性优化（本轮验证仍生效）**：bloom 捕获 0.25 分辨率 + tapScale 足迹补偿（bloom.glsl:97-99，与 `size.buffer.colortex2` 的配对有注释约束）；末地两段式天空（0.75 几何 + 全分辨率星场）与 294 槽天体烘焙；黑洞 48 步上限 + 空域跳过 + 候选过滤；背光面跳过阴影采样（diffuse.glsl:343-346）；SC-39 把 96 步积水反射收回稀疏水坑（门控修复后）；`pow.glsl` 平方链；云色惰性求值（首 hit 才算 palette/sky）。

**当前成本热点（全部有界、多数有门控；无"必挂"级回归）**：

| 热点 | 量级 | 门控 | 评估 |
|---|---|---|---|
| 雨天 `rainy_air`（deferred.fsh:72-96，调用点 ：152） | 每不透明像素 10 步 ×（云噪声 1 fetch + 阴影 gather） | `astraRainFactor ≥ 0.01` + 天光可达 | 雨天全屏成本，刻意设计；建议实机关注 |
| 积水反射 puddle_reflection | 每触发像素 96+12 步深度采样 | SC-39 收窄到稀疏水坑；**F2 漏洞使雨丝贴天空像素也付全价** | 修 F2 后回到设计意图 |
| 水下光束 march（light_shafts.glsl:71-107） | 4-10 样本 ×（阴影采样 + 焦散 9 tap×2 fetch ≈18 fetch） | `UNDERWATER_LIGHT_SHAFTS && SHADOWS && 强度>0` | 水下最重路径，量级与 Solas 参考相当 |
| 末地黑洞（end_blackhole.glsl:79-81,125-170） | `bodies[73]+indices[73]` 局部数组（~584 B）逐像素复制 + 动态索引（局部内存慢路径）；48 步 march 内每步最多 2 次段求交 | 仅末地天空（0.75 分辨率）+ deferred 星点像素 | 有界；"每像素 12 次"的旧说法已由代码注释自纠（:123-124），cost_census 应按新模型登记 |
| 水面 `water_sample_path`（water.glsl:31-110） | 反射锥 4 footprint×4 tap + 折射 + 直射回退，每 tap 2 纹理 | `SCREENSPACE_REFLECTIONS/REFRACTION` | 单像素最坏 ~96 fetch，与历史审计"96 步高于参考 24-32"同源，维持原评估 |

**结论**：维持历史审计的判断并更新——"没有已知且可安全落地的性能项"在源码层面仍成立，但它的前提（人肉扫描）没有变，P1 的护栏缺口因此仍是性能维度的第一风险。

---

## 6. 已验证的关键点（本次真正检查过的风险）

1. **colortex0-9 缓冲写读矩阵**逐 pass 复核：写读配对、清屏色、`colortex6Clear=false` 的一帧滞后、末地 deferred/deferred1 的 colortex9 时序均自洽；**唯一断点即 F1 的 colortex5.a**。
2. **历史审计修复核验**：§2/§4 表中 11 项历史 finding 在当前工作区逐一找到了修复代码（行号见 §4 末段），无"注释说修了、代码没修"的情况。
3. **回归模式扫描**：`#if 2==0` 恒假分支、LPV 未移植符号、`pow(负底数)`、全局非常量初始化器（bloom 两文件已函数内局部化）四类历史问题模式全树零命中。
4. **check_pack.py 与 cost_census.py 实跑**：11 项 0 FAIL / 1 WARN；循环清单与源码现状一致（clouds 64 步、黑洞 48 步、deferred 96 步、阴影 4/16 tap 等均在对账范围内）。
5. **可移植性抽查**：全树 `pow((` 形态仅剩 sRGB/solas 色域变换，底数均有非负来源；`encode/decode_unit_vector` 与 `water_pack/unpack_surface_height` 的量化边界（255/256、65535）配对正确。

---

## 7. 建议（按优先级）

1. **修 F1**（删 `lit.fsh:362` 或改走正确通道）——一行删除，恢复文档化契约；同步改写 `lit.fsh:357-361` 的三处失实注释。
2. **修 F2**（天空清屏 alpha 或门控加 skylight 非零条件）——同时是雨天性能回收。
3. **先提交再继续**：把 42 个未提交文件按"SC-39 修复 / 性能轮 / 文档"拆成 2-3 个提交（P3）。这是防止两轮关键修复意外丢失的最低成本动作。
4. **安排一次实机集中验证**（P2）：末地、雨天积水、水下光束、月相、SC-39 的三处行为修正、性能轮的 pow 链——积压清单已跨 6 轮。
5. F3/F4/F6/F7 与 S1/S2 的补记可合并为一次清理提交；F5 按 `pow.glsl` 自定的对拍流程补齐。
6. 维持 §13.3 对 cost_census 的定位决定，但把"新增/修改循环必须报上界"写进任务模板（P1 的零成本部分缓解）。

---

## 附录：本次审查未覆盖的内容

- **游戏内画面正确性与帧率**：全部未覆盖（无实机）；本报告所有"影响"均为源码级推断。
- **Iris 之外的环境**（OptiFine、其他 Iris 版本）、多人与服务器场景、除 RTX 4050/NVIDIA 572.83 外的驱动与厂商。
- `_analysis/` 参考包内容仅用于出处核对，未审查其本身。
- `qa/` 下 130+ 历史日志仅抽样（最新编译日志与校验器输出）。
- 风格与命名一致性未作为 finding 输出（无一条 Minor 因风格而起）。

---
---

# 8. 专项复盘：水下光束与"水上看水下"的浅→深色彩过渡为什么一直没有实现

针对用户点名的两个验收项——**①水下光束；②从水面上看水下时，水体颜色随深度由青绿色自然过渡到深蓝色**——本节把两条链路逐环追完，给出可从源码直接证明的根因。标 ✅ 的结论是源码算术可证的；标 ⚠️ 的是量级估算，需实机确认。

**一个统一的判断**：Astra 的水在空气侧只有"**吸收窗口**"语义（`water_surface_medium` = 床色 × 透射率），没有"**参与介质**"语义（in-scatter + 体积光）。用户要的两件事——浅→深的色彩过渡、水面上能看到的水下光柱——缺的其实是同一个东西：**空气侧的体积项**。这套拆分是 SC-34-F1/SC-35 有意为之（防止当年"灰蓝滤镜"回潮，见 `absorption.glsl:55-57` 注释），所以修复方向应是"加一个受控的、谱序正确的水上体积项"，而不是简单回退旧实现。

## 8.1 浅→深"青绿→深蓝"过渡出不来：三个可证根因

**R-A ✅【谱序错了：默认水型的深水收敛于绿色，数学上不可能到蓝】**
`absorption.glsl:20-29` 的三条谱（每格吸收系数，红/绿/蓝）：
- COLD：`(1.000, 0.220, 0.080)` —— 绿吸收 0.22 **>** 蓝吸收 0.08 → 深水**蓝**主导 ✅
- BALANCED（默认 `WATER_CHARACTER=1`）：`(1.000, 0.060, 0.100)` —— 绿吸收 0.06 **<** 蓝吸收 0.10 → 绿比蓝存活更久 → 深水收敛于**暗青绿**，永远不会变蓝 ❌
- TROPICAL：`(2.000, 0.055, 0.080)` —— 同样绿 < 蓝 → 深水偏绿 ❌

即三档里只有默认不选的 COLD 能给出"深蓝端点"。算出实际透射曲线（`appearanceDepth = clamp(深度+1, 0, 16)`，BALANCED，100% 强度）：深度 0 → `(0.37, 0.94, 0.90)`（青）；深度 5 → `(0.0025, 0.70, 0.55)`（青绿）；深度 ≥16 → `(0, 0.36, 0.18)`（暗绿）。**用户看到的就是"青绿有了，深蓝没有"——这不是调参没调好，是谱的绿/蓝排序决定的。**

**R-B ✅【外观深度的 +1 偏移与 16 格封顶同时抹掉了两端】**
`absorption.glsl:58-62`：`appearanceDepth = clamp(depth + 1.0, 0.0, 16.0)`。
- **+1 偏移**：脚踝深的浅水（depth≈0.3）直接按 1.3 格算，红通道先被吃掉 `1-exp(-1.3)≈73%`——浅水端没有"清澈见底"的起点，过渡从半饱和开始；
- **16 格封顶**：16 格以深全部同色，"越来越深"的线索在中等深度就饱和，深水端没有继续压暗/变蓝的过程。

**R-C ✅【水上路径没有 in-scatter：水体没有自己的颜色，只有"被染色的床"】**
水上折射背景的唯一介质处理是 `water.glsl:79-81` 的 `water_surface_medium`（纯乘法透射）。物理观感里"深蓝"主要来自**水的背散射**——床的直接可见度随深度衰减、水的本色随之填进来。Astra 在空气侧刻意砍掉了这一项（`absorption.glsl:55-57` 注释明示），结果：
- 中等深度：水 = 变暗变绿的床，读作"浑"而不是"深"；
- 床不可见处（深湖/远海，`water.glsl:37-38` 对 `anchorDepth >= 0.999999` 整体拒绝）→ `water.glsl:293-299` 的 `deepFallback = astra_water_segment(vec3(0), ...)` ✅ 恒等于 `vec3(0)`（`scene.glsl:105-107` 对 `radiance=0` 的透射仍是 0）→ **透射项为纯黑**，画面只剩 Fresnel×天空反射。开阔深水不是"深蓝的水体"，是"黑色的镜子"。
- 旁证：水深感知的另外两条数据通路**全部有生产者、无消费者**——`shadow_water_depth()`（`shadowmap.glsl:217`，全树零调用）与 colortex5→colortex6 状态链（§2-F1）。"按真实水深驱动水色"的机制在包里存在过骨架，但从没接到照明上。

**R-D ⚠️ 次要：床的照明不随水深衰减**（`scene.glsl:236-238`"床与岸受同样日照"）——净效果与透射暗化等价，此项不独立致错，但意味着焦散/直射在 15 格深与 1 格深同亮，削弱深度线索。

### 8.1.1 建议改法（按侵入性排序，全部可离线用 Python 对拍验证曲线端点）

1. **谱序修正（最小改动）**：把 BALANCED 改为绿吸收 > 蓝吸收，例如 `(1.000, 0.140, 0.055)`；TROPICAL 保留绿主导（热带浅海观感）但在注释里写明"深水偏绿是本档设计"。改完用脚本打印 0→24 格透射曲线确认端点：浅 `(≈0.5, 0.87, 0.90)`、深 `(0, ≈0.05, ≈0.28)`。
2. **深度插值谱（推荐，保持浅端不变）**：浅水谱 `(1.0, 0.05, 0.09)` 与深水谱 `(1.0, 0.30, 0.05)` 按 `clamp(appearanceDepth/16,0,1)` 插值——浅端照旧青绿，深端单调转蓝，一处改动同时满足"自然过渡"。
3. **加受控的水上 in-scatter（补"水体感"与深水端点）**：`transmitted = 床×T + k × waterBodyColor × (1-T)`，其中 `waterBodyColor` 取表面谱自身的平衡色（入射天光 × 散射反照率，**不是**水下体积色，避免当年灰蓝滤镜回潮），k≈0.5–0.8。深水处 T→0，颜色收敛到 `k×waterBodyColor`——深蓝端点从此不依赖床色。同时把 `deepFallback` 从 `vec3(0)` 改成这个 `waterBodyColor`（`water.glsl:294-298` 一行），远海立即从"黑镜"变"深蓝水体"。
4. **重标定外观深度**：`+1.0 → +0.25`、上限 `16 → 24`，浅端更清、深端更晚饱和；与 1/2 联动调。
5. 顺带把 §2-F1 的 colortex5.a 修复后，把"床的直射光按真实水柱深衰减"（用 `shadow_water_depth()` 或状态链）列为 v1.1 候选——它让焦散随深度衰减，是"深度感"的第三条线索。

## 8.2 水下光束弱/不可见：三个可证根因

链路本身是通的（composite2 使能条件、march、colortex1 全分辨率、composite3 resolve、encode `^0.25`/decode `×0.25→^4×128` **确认为互逆**——本次逐环验过）。问题出在可见性门与能量标定：

**R-E ✅【前向散射门用的是"空气太阳向量"，正午光束精确为零——而正午恰是光束应最强的时刻】**
`light_shafts.glsl:48`：`VoL = pow(clamp(dot(ray, normalize(view_player(lightVector))), 0, 1), 1.5)`，`ray` 是看向水下某点的方向（多半向下）。太阳高度 -40° 轨道正午约 50°：**任何向下视线的 `dot(ray, 太阳) < 0 → VoL = 0`**，且正午 `time≈1` 使 `mix(0.25+0.25·VoL, 0.45·VoL, 1) = 0` → `visibility = 0` → `light_shafts.glsl:56` 整体早退。**正午垂直向下看水下：一根光束都不会有。** 讽刺的是相位项用的是折射后太阳（`:112-114` 的 `refractSun`，正午直视下方 `dot≈0.85`，相位满格）——门说"正午没有光束"，相位说"正午光束最强"，两个窗口互相矛盾。光束只存在于低/中太阳角 + 朝太阳方向看的窄窗口里。

**R-F ✅【能量被四层乘法压到显示值的约 1–5%，处在不可见边缘】**（量级估算 ⚠️，但每一步都是源码算术）
每样本贡献链（`light_shafts.glsl:92-106`）：阴影可见度(≤1) × **焦散调制³** × ÷max(3, d×0.1) × weight(≤1/7)。其中焦散调制是最大的一刀：`caustics.glsl:109` 的 `mix(caustics*0.16+0.2, 1.0, 0.3-0.3·isEyeInWater)` 在水下取**低支** `caustics×0.16+0.2 ≈ 0.2–0.42`（注释写"raw underwater"，实际公式给的是 0.16 倍压缩+0.2 抬底），立方后 **0.008–0.074**。叠加 ÷3 与 weight 后，7 样本积分 `integral ≈ 0.01–0.05`（线性域）；经 `/128→^0.25` 编码、composite3 以 `^2.2` 域加回、final 的 `solas_water_display`（×4.7 + 曲线 + `^1/2.2`）——**最终显示亮度约 1–5%**，在多数水色/曝光下肉眼不可辨。

**R-G ✅【光束能量与 WATER_CAUSTICS 选项耦合】**光束颜色取自 `shadowcolor0.gba`（`light_shafts.glsl:105`），而水caster的染色只在 `WATER_CAUSTICS` 开启时被焦散调制（`shadow.fsh:57-66`）；关焦散会同时改变光束的颜色与能量——两个本应独立的选项互相干扰，调参时互相污染。

### 8.2.1 建议改法

1. **把 `refractSun` 提前到循环前计算，VoL 门改用它**（`light_shafts.glsl:48` 一处）：正午看水下立即恢复满格前向散射；低角度窗口行为不变（折射角随太阳降低而变平，朝向门自然跟随）。这是单点收益最大的一处。
2. **重标定能量链（一次只动一层，实机 A/B）**：焦散调制给下限，如 `pow(max(focus,0.35),3)`（把最暗处从 0.8% 抬到 4%）；`/max(3.0, d*0.1)` → `/max(2.0, d*0.06)`；末端 `×(4.0+sun*8.0)` 上探 `×(6.0+sun*14.0)`。
3. **解耦 WATER_CAUSTICS**：光束色改用固定 `solasWaterSqrt` 染色（`shadow.fsh` 的焦散染色只管海床），或光束读取时对 shadowcolor0 只取染色、不再继承焦散幅度。
4. **先测量再调参**（对齐项目"先数值后画面"的教训）：加一个临时 debug 选项把 `integral` 的量级写进输出（如 colortex1.b 或分屏显示），用三档太阳角各截一帧确认数量级，再逐层标定。另可加一条 qa 脚本：按 `light_shafts` 的公式链用 Python 重建 `integral→显示亮度` 的传递曲线（与 pow.glsl 的对拍文化一致）。
5. **补"水上看水下"的光束（可选，属 8.1 的同一机制）**：`water_composite.fsh:25` 目前只在 `isEyeInWater==1` 合成光束；从水面上透过水面看水下光柱需要空气侧也消费 colortex1（按折射界面的 48 格距离上限截断）。若确认需求，与 8.1.1-3 的 in-scatter 同一处合成，避免两条路径各写一遍介质。

---

# 9. 整体性能优化建议

按"每像素成本 × 生效面积"排优先级。所有建议遵守项目已有规矩：等价性对拍（`shadow_filter_equiv.py` 模式）、数学助手 Python 逐点校验（`pow.glsl` 模式）、改一处实机 A/B 一次。

## 9.1 第一梯队（每像素主路径，收益最大）

**P-1 天空求值进 LUT 或加早退——全包最大的每像素 ALU 项。**
`scene.glsl:155-160`：户外每个受光片元都会走到 `astra_sky_radiance(direction)`（`skyStrength` 恒 >0，早退条件几乎不触发），即完整的 Complementary 三向天空（factors + palette + GetSky）+ 晨昏大气 + 高光肩——含 2 个 vec3 非整数幂（2.9/0.90）、1 个**变指数** `pow(abs(VdotS), glareScatter)`（`sky_gradient.glsl:246`）等多次超越函数，估算每片元 150–300 ALU；`astra_reflection_sky`（每个水面像素最多 2 次）同样付这笔钱。可选方案：
- a. **每帧小 LUT**：2D（视线仰角 × 太阳高度）+ 天气/晨昏插值，用包已在用的 custom image 机制（下界体素光已开了 CUSTOM_IMAGES 先例）由一个 1 像素级 pass 或 compute 烘焙，片元改查表 + 双线性。这是 Complementary/Photon 的通行做法（性能调研文档已记录 Photon 大气查表）。
- b. **低雾早退 + 近场近似**：`fog.a < 0.02` 时用 zenith/horizon 两常数的便宜混合替代完整天空，`fog.a` 达阈值才走全量。改动小，代价是近场雾色少一点方向细节。
- c. 至少把 palette 的两个 vec3 pow 与变指数 glare pow 移出热路径（查表/多项式/整数幂链）。

**P-2 阴影硬件 PCF 混合模式转正——最高频纹理路径。**
默认软件模式每受影像素 4 gather×2 深度 + 材质 fetch（≈9–10 次纹理访问）；`SHADOW_FILTER_MODE=1` 已实现但因"中心材质近似"不敢转默认。建议做**混合模式**：深度比较走硬件（4 次 `sampler2DShadow`），材质只在 `transparentWeight > 0` 时逐角点 `texelFetch shadowcolor0`（保留逐角染色，去掉中心近似）——语义与软件路径等价、纹理次数降到 4–6；用 `shadow_filter_equiv.py` 扩展做数值对拍后转默认。历史 R3 的顾虑即被解除。

**P-3 积水反射与雨天链路（与 §2-F2 联动）。**
- 修 F2：雨丝贴天空像素不再白跑 96+12 步；
- `puddle_reflection` 加距离门（>32 格退天空回退）+ 前段大步长（当前 1.25/pixels 固定步，96 步可减半再靠已有 6 步细化兜精度）；
- `rainy_air`（deferred.fsh:81-93，雨天每不透明像素 10 步）加距离上限（`exp(-t*0.008)` 在 t>150 后贡献有限）并把步数降到 6–8，或移到与 godrays 同构的 0.5x 缓冲。

## 9.2 第二梯队（分场景 march，按场景回收）

| 项 | 现状 | 建议 |
|---|---|---|
| 水下光束 march | 全分辨率 7–10 样本 ×（阴影 + 焦散 9tap×2fetch + 染色 fetch）≈ 每水下像素 100–150 次纹理访问 | march 降 0.5x（colortex1 本就半尺寸可回退，resolve 已是 4-tap 上采样结构）；焦散调制复用海床焦散场或降为 2 tap——水下纹理访问降到 ~40 |
| 水面 `water_sample_path` 反射锥 | 4 footprint × 4 tap × 2 纹理 | `roughness` 低于阈值（平静水面）退单 tap；锥形 4 footprint 仅高粗糙度启用 |
| 云 march | 每天空像素至多 64 步 × 2 fetch | 上限 32 + 远距步距放大（LOD）；首 hit 后已 break，主要是上限与步距 |
| 末地黑洞 | 每像素复制 `bodies[73]+indices[73]`（~584 B 局部数组 + 动态索引慢路径） | 天体数据已在 colortex8 烘焙——改为按需 `texelFetch`，去掉逐像素数组复制；候选过滤保持 |
| 雨涟漪 | 每雨天地表像素 2 层 × 2 tap flipbook | 第二层 fetch 移到 `strength ≥ 0.75` 门后（当前是乘 0.15 但照样采样） |

## 9.3 第三梯队（结构/显存/杂项）

- **F5 收尾**：23 处字面整数幂迁 `pow.glsl` 助手（fog/twilight 在每像素路径）。
- **astraRipple3 删除或接线**（F6）：省 ~3.7 MB 显存与一次注册。
- **colortex1 维度白分配**（T7，已知接受）：若 Iris 后续支持按维度 size 指令再回收；现阶段在文档标注即可。
- **godrays 链**：默认关、结构已是半分辨率两段式 ✓ 无动作。
- **CPU 侧**：custom uniforms 卸载已充分 ✓ 无动作。

## 9.4 配套要求（防"性能优化变行为回退"）

1. 每项改动先跑 `compile_glsl.py` 全档矩阵 + `check_pack.py`（现有流程）；
2. 数值类改动（P-2 混合 PCF、9.2 的降采样）必须先有对拍脚本证据，参考 `shadow_filter_equiv.py` 的等价性报告格式；
3. 标定类改动（8.2.1-2、9.1 的 LUT）必须实机 A/B——这是当前验证体系唯一真正的空白（§4-P2），性能优化恰是最依赖实机数据的类别；
4. 建议把 8.1.1 的透射曲线脚本与 8.2.1-4 的光束传递曲线脚本沉淀进 `qa/tools/`——两者都是"先数值后画面"的探针，可复用于后续所有水色/光束调参。
