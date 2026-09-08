# Astra 任务计划 — 高级Ⅱ（C 系）

> 梯度定位：**跨 pass 交互或需要设计判断的模块**。参考实现不完整、需与多模块耦合、或含观感调校——需要真正理解管线，产出会被顶级Ⅱ集成。
> 上位规格：[design.md](design.md)。升档路径：架构/管线问题直接报顶级Ⅱ（E 系）；模块级困难可请顶级Ⅰ（D 系）协助。

## 任务清单

| # | 里程碑 | 任务 | 内容 | 验收标准 | 依赖 | 状态 |
|---|---|---|---|---|---|---|
| C1 | M2 | 光照模块 | `diffuse.glsl`、`blocklight.glsl`（含日光压制）、`sss.glsl`（植被经验近似）、手持光、闪电点光 | 仿原版方向性环境光 + skylight 立方衰减；日光压制生效无跳变；洞底 minAmbient 正确；"清爽"观感基线成立 | E1、B1 | ✅（模块本体；lit 接线归 E1，实机验收待 SC-6） |
| C2 | M2 | 水下子模块 | **SC-24 重定向（2026-09-06，用户更正：水下对标 Solas）**：`absorption.glsl`/`refraction.glsl`/`caustics.glsl` 参考源由 Steadfast 换为 **Solas**（`_analysis/Solas Shader V2.2b/shaders/lib/water/` 的 waterFog / waterCaustics、`program/composite4.glsl` 的 REFRACTION 段），观感重写为 Solas 水下；接口与签名冻结不变，E2 总成接线不动 | 水下 ≈ **Solas** 单项对标通过；焦散随阴影投射且随深度衰减 | E1、B1 | ✅ SC-24 换源已执行（2026-09-06：三件套 Solas 化，225 组驱动编译零错；实机目视对标待 SC-6/E4） |
| C3 | M3 | 下界特调 | `dimension/nether.glsl`：无日光光照路径（环境光=方块光+熔岩辉光+红底）、熔岩辉光雾（随高度/深度）、独立大气与雾曲线、发光体/传送门增亮 | design.md §4.5 下界条目逐项达成；帧率同主世界标准 | E1、C1 | ✅（模块本体；`fogColor` 与维度覆盖壳归 E1（SC-18），实机验收待 SC-6） |
| C4 | M3 | 末地特调 | `dimension/end.glsl`：真空暗天空 + 稠密星野（缓慢旋转）、褪色环境光、void 雾渐变、微星云（默认开低强度） | §4.5 末地条目逐项达成；截图可独立辨识为"设计过" | E1、D2 | ✅（模块本体；维度覆盖壳归 E1（SC-18）、天空消费归 D2，实机验收待 SC-6） |
| C5 | M3 | Voxy 接入 | `voxy.json`、`voxy_opaque/translucent.glsl`、`lit_voxy.fsh`（`EXTERNALLY_DEFINED_UNIFORMS` 模式，参照 Mellow/Steadfast 现成实现） | Voxy LOD 地形光照/水面与主世界一致；不兼容则出实验特性说明 | E1、D1 | 🔶 SC-17已下放：E1接口已冻结；26.2/Voxy0.2.18-beta实例已找到，C5调用映射与D1实际加载待续 |
| C6 | M4 | 色彩与风格层 | `grading.glsl` 预设定稿（原 T5 下放）：tonemap 选型执行、出厂参数校准（对 Refrax 参考图迭代，起始 饱和 1.12/自然饱和 1.15/对比 1.04）、IGN 抖动配合 | 色调对标 Refrax（用户目视确认）；风格参数 100% 集中在 grading.glsl | M2 完成 | 🔶 SC-16已解决并接入final（单次sRGB后分级）；预设不重写，色调对标待运行素材与用户目视 |

| C7 | M2 | 水面与SSR（SC-15指令下放） | **SC-24 重定向（2026-09-06，用户更正：水面对标 Steadfast）**：surface.glsl 参考源由 Solas 换为 **Steadfast**（`_analysis/Steadfast-0.8.0/shaders/environment/water/`——解析导数程序波浪、Nyquist 比率受限、4 步自适应视差），观感重写为 Steadfast 水面；raytrace.glsl（SSR 基础设施）不动；接口与签名冻结不变 | 水面 ≈ **Steadfast** 单项对标通过；接口符合 design §4.3；E2 集成后另作实机视觉裁决 | E1 | ✅ SC-24 换源已执行（2026-09-06：Steadfast 噪声波场 + 解析导数 + 视差；raytrace 未动；225 组驱动编译零错；实机目视对标待 SC-6/E4） |

## 协作规则

- 接口纪律与 B 系相同：只走 E1 冻结的 varyings/uniforms/缓冲，禁止私开。
- C2 按设计文档 §4.3 规格独立成模块，与水面的总成集成由 E2 负责——不越界做集成。
- C6 只调参数与预设；需要动管线/插入点（如换 tonemap 位置）属架构问题，报 E 系裁决。
- 验收双闸门：任务表标准 + Z7 回归清单；视觉类以参考截图对比为准。
- 卡住两轮无进展：带证据上报；架构变更请求写清"现状/问题/建议决议"三段，报 E 系。
- 上报与接手：按 [escalations.md](escalations.md) 流程执行（登记→认领→结论下放→闭环）；上报中的任务状态标 🔶。

## 完成记录（每任务一行）

> 共同边界（与 tasks-advanced-1.md B 系同）：E1 未冻结（tasks-top-2.md 仍 ⬜），本批**只写模块主体**，
> `program/lit.*`、`program/final.*`、`gbuffers_*` 包装、维度壳一律未动；接口契约（参数、调用时机、
> 消费者、未冻结项）写在各模块文件头。判 ✅ 的依据是"照 design.md §4 规格实现 + 静态校验不劣化
> （`check_pack.py` 现为 1 FAIL / 1 WARN / 9 PASS，唯一 FAIL 是 E1 的 #10 最小 final 链）+ 出处台账落档"；
> 实机与视觉判据零证据，全部留给 SC-6 解除后的 Z7/D1 环节。

- **C1 ✅**：`global/lighting/diffuse.glsl`（197 行：`ambient_strength()` 方向性环境光、
  `ambient_sky_lighting()` skylight 立方衰减、`direct_lighting()`、`diffuse_lighting()` 总成）
  + `blocklight.glsl`（133 行：`block_lighting()` 含日光压制、`held_light_strength()` 手持光衰减、
  `lightning_point_light()` 闪电点光）+ `sss.glsl`（60 行：`sss_wrap()` 植被经验近似 + `SSS_STRENGTH`
  滑条化）。日光压制"生效无跳变"与洞底 minAmbient 为静态推演结论，实机未证。
- **C2 ✅（SC-24 换源重写，2026-09-06）**：三个模块参考源由 Steadfast 换成 Solas 并重写本体——
  `absorption.glsl`（Solas waterFog：标量指数雾 1-exp(-6·d) 反解为逐通道 sigma = -ln(waterColor)，归一后红通道对齐 Solas 的 32 格 ≈0.85 雾浓度；三档 WATER_CHARACTER 只改水色）＋
  `refraction.glsl`（Solas composite4 屏幕空间扰动：剔沿视线分量 → vec2(1/aspect,1)·(proj[1][1]/1.37)/max(len,8)；textureGather min/max 深度拒绝保留）＋
  `caustics.glsl`（Solas waterCaustics：双层漂移噪声 5 点差分交叉相乘，替代六层 crest 表；Astra 的水深门控/48–64 淡出/footprint 抑制三包络保留）。
  签名全部未动：`water_absorption(float)`、`refract_trace(...)`、`water_caustics(playerPos, shadowPos, time, footprint)`——E2 接线（lit.fsh/scene.glsl/water.glsl）零改动。
  `check_pack.py` 与 `compile_glsl.py`（225 组三档）双通过。出处台账 3 行改 Solas + REWRITE REQUIRED 标记；
  §4.3 与 SC-19 的"焦散保留 crest 算法"表述已冲突，见下方提示。目视对标待 SC-6/E4。
  **悬浮颗粒接线（同日追加）**：`global/water/particles.glsl`（自写，四包均无屏幕空间悬浮颗粒实现，
  观感对标 Solas：三层壳距 3/6/12 格 + 3D cell 整型 hash motes + 慢闪烁 + 水吸收距离衰减 + 天光门控），
  接入 `program/deferred.fsh`（加进显示缓冲、不进 colortex4 的 SSR 背景）；deferred 启用条件加
  `|| defined UNDERWATER_PARTICLES`（E2 条件的一项同语法扩展，非新 pass/buffer）。SC-28 的
  UNDERWATER_PARTICLES 孤儿 WARN 已消（72/25 wired）；§4.3 水下氛围"悬浮颗粒"缺项补齐。
- **C7 ✅（SC-24 换源重写，2026-09-06）**：`surface.glsl` 由"自写正弦解析波"重写为 Steadfast 方案——
  `WATER_RIPPLES[4] + WATER_CRESTS[2]` 噪声波场（值噪声内联、surface_ 前缀防与 Solas caustics 冲突）、
  `surface_noise_gradient()` 一次 textureGather 解析梯度、`surface_antialias()` Nyquist 比率受限
  （固定 BALANCED 档）、`surface_parallax()` 4 步自适应视差（切线视线由 worldPos - cameraPosition 现算，
  Z 取 -abs(y) 使上下表面共用 Steadfast 约定）；roughness = 被 Nyquist 滤掉的坡度能量（对 Steadfast 的增补，
  供 E2 反射/SSR 消费）。签名未动：`water_surface(vec3, vec3, float) -> WaterSurface{normal, roughness}`。
  `raytrace.glsl` 未动（SSR 基础设施）。出处台账 surface 行由"自写"改为 Steadfast GPL 派生 + 文件头声明。
  225 组驱动编译零错。目视对标待 SC-6/E4。
  ⚠ **规格冲突提示（P2，已在最终报告中上报用户）**：design.md §4.3 决议行（SC-19/E2，2026-09-06）
  写"焦散 C2 保留 crest 算法"，而 SC-24（同日晚些）要求焦散换 Solas 高度差分——本批按 SC-24 执行
  （用户本次指令即换源），§4.3 该行文字待 E 系复核更新。
- **C3 ✅**：`global/dimension/nether.glsl`（481 行：`nether_lighting()` 无日光路径=方块光+熔岩辉光+红底、
  `nether_fog()` 熔岩辉光雾随高度/深度、`NetherParams` struct 传值避开冻结的 uniform 集、发光体/传送门增亮）。
  唯一需要 E1 供给的输入是 `uniform vec3 fogColor`，已在文件头标 ⚠ REQUIRED FROM E1。
- **C4 ✅**：`global/dimension/end.glsl`（778 行：`end_sky()` 真空暗天空 + `end_star_field()` 双层稠密星野、
  绕倾斜极**刚性旋转**（3D 晶格随视向旋转，非参考包的投影 2D 平移）、`end_nebula()` 微星云（默认开、4 次查表、
  比 Solas 的 9 次降配）、`end_fog()` 黑紫随深度 void 雾、`end_block_lighting()` 褪色环境光、
  `end_emissive_boost()` 含沿 Y 行进的光柱辉光）。§5 的抖动优先"查表"在本模块有一处记录在案的偏离：
  星野是稀疏点过程，256² 双线性表无法表达，仅该项用整数 hash，星云仍走 noisetex。
- **C5 🔶**：未实施，登记为 SC-17（前置三项全缺：E1 冻结、D1 的 26.x Voxy 冒烟、SC-6 实机环境；
  `check_pack.py` 无任何 Voxy 静态检查项，写出的映射层零可验证性）。C3 的 `nether_fog()` 已预留
  `borderFragDistance` 形参，接线时可直接复用。
- **C6 🔶**：`global/post/grading.glsl`（216 行）出厂参数与四套预设已交付——`apply_exposure()`、
  `apply_color_temperature()`、`apply_grading()`（vibrance 先于 saturation 再 contrast，链序照 Mellow）、
  `apply_vignette()`、`apply_output_dither()`（IGN，§5 要求）+ `grading_dimension_exposure()` 按维度补偿。
  未闭环的两点：① 插入点随 SC-16（四算子输出空间不一致，任何单一插入点都对部分算子错误，须 E1 裁决）；
  ② 验收标准本身写"用户目视确认"，且实机截图受 SC-6 阻塞。**本批不自行改管线。**
