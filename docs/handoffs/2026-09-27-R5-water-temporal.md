# R5 / T3 水时域处理 —— 交接记录

- 状态：**代码完成（首个分项 = 水面 SSR 命中辐射历史链，生产 / 存储 / 消费 / 拒绝规则全部落地；其余分项明确未覆盖，见第 1、3 节。无游戏画面与帧时验证，见第 6 节）**
- 认领 / 完成：ZCode 会话，2026-09-27
- 对应父项：T3「实体 / 水 / 云仍未完成」中的水项（R5）；总表 [itt32-initial-implementation](../2026-09-26-itt32-initial-implementation.md) 第 1、6 节
- 上游依赖：R2 介质归属（[R2 交接](2026-09-27-R2-overworld-volume.md)——colortex4「未施加观察介质」语义、`astra_volume_prefix_medium` 前缀接口、吸收单次应用；本链全部沿用，未改动介质路径）；R4 结论（Iris 1.11.2 无实体前帧输入——本链不需要实体运动数据，仅依赖相机级前帧矩阵）；R6 先例（独立于 TAA 的自维护历史、settings.glsl 手动回退阀、缓冲翻页读前帧、`fract(frameTimeCounter/64)*64` 时间戳）
- 范围声明：**本任务只建立「水上水面 SSR 命中辐射」一个分项的时域历史**。水面着色整体、环境反射 fallback、折射背景、水下视角界面、水下相机腿均未获得历史；不得据本链宣称 R5 完成。

## 1. 信号分项表（水面要累积的信号，各自运动 / 遮挡含义与覆盖状态）

| 分项 | 信号内容 | 运动含义 | 遮挡含义 | 状态 |
|---|---|---|---|---|
| SSR 命中辐射 | `water_raytrace` 命中点处经 `water_sample_path` 从 colortex4+depthtex1（不透明快照）传输的辐射 | 命中点是场景世界点；水面几何静止（波仅法线扰动），相机运动全量可逆 | depthtex1 不透明快照 + 界面侧接受测试（生产端既有） | **本任务交付完整链** |
| 水面着色整体 | `astra_water` 最终混合输出 | Fresnel / 法线时变，无单一对应几何 | 与折射共享界面 | 未覆盖。最终混合色；不做「套不透明地形速度」的假分解 |
| 环境反射（天空 fallback） | `astra_reflection_sky` 解析天空 | 天空辐射随时间连续变化，无屏幕对应点 | 无 | 未覆盖。解析求值无噪声源、无命中元数据可存；接续时需先定义「代表方向/可见性」类元数据 |
| 折射背景 | `water_sample_path(refractedUV,...)` 传输的河床/背景 | 背景世界点经折射线着点 | depthtex1 + 折射深度跳变拒绝 | 未覆盖（独立链待建）。**「折射深度跳变」拒绝规则归属此分项**（见 5.2） |
| 水下视角界面（solas） | `solas_underwater_interface` 的 SSR/折射（water.glsl:148 的 march） | 自下而上看水面 | 自有路径 | 未覆盖（本期未动） |
| 水下相机腿整体 | isEyeInWater==1 的全局场景 | — | — | 未覆盖。场景 TAA 维持 `taa_resolve.fsh:92` 的水下 reactive=1，本期未改 |

## 2. 首个完整链：SSR 命中辐射（生产 → 存储 → 消费）

### 2.1 实际调用关系（生产者 → 消费者，file:symbol）

```
SCREENSPACE_REFLECTIONS（既有用户开关）+ !ASTRA_WATER_NO_TEMPORAL（手动阀）
  └ lib/settings.glsl:432-434 → ASTRA_WATER_TEMPORAL

每帧（gbuffers_water 槽，root / world-1 / world1 三入口同享 program/lit.fsh）：
program/water.glsl:229  water_raytrace(depthtex1, viewPos, reflectedRay, viewGeometric)
  → hit = (hitUV, hitDepth, confidence)；hitUV 含当前抖动（global/water/raytrace.glsl:26 water_ssr_project 用 astra_jitter_clip）
program/water.glsl:236  water_sample_path(hit.xy, ...) → reflected 辐射 + 路径有效性
                        （读 colortex4 + depthtex1，界面侧 water_side_acceptance，air 侧再过 astra_fog）
program/water.glsl:252  astra_water_ssr_temporal(hit.a>0, reflected, reflectionWeight, hitPos,
                                                playerPos+cameraPosition, out historyMeta)
  └ global/water/temporal.glsl:103 astra_water_ssr_temporal
      ├ 前帧表面点重投影：temporal.glsl:128-131（gbufferPreviousModelView/Projection
      │   × (surfaceWorld - previousCameraPosition) + 前帧抖动 astra_water_previous_jitter_uv:77-90）
      ├ 读前帧：temporal.glsl:137-141（colortex29 元数据最近邻 + colortex28 辐射双线性，
      │   同 pass 自反馈翻页——taa_resolve.fsh↔colortex15、R6 cloud_screen.fsh↔colortex24/25 同款机制）
      ├ 门与拒绝（2.3/2.4）→ 混合 temporal.glsl:190-194
      └ 返回 vec4(混合辐射, 混合有效性) + metaOut(命中偏移, 时间戳)
program/water.glsl:255-257  gl_FragData[3]=colortex28（新历史）、gl_FragData[4]=colortex29（新元数据）；
                            reflection = blended.rgb * reflectionWeight（仅 hit.a>0）
其后（不变）：astra_scene_highlights(water.glsl:325)、Fresnel 混合（:396）、astra_apply_medium（:399）
                            ——历史存的是 Fresnel 前、shoulder 前的辐射，不会被重复压缩
```

生产含命中位置（colortex29.rgb）、深度对应（当前命中 + 存储命中双重位置/深度校验，temporal.glsl:160-183）、有效性（colortex28.a / 当前 confidence = hit.a × 路径有效性）。命中点法线未存：本链的对应性测试用「存储命中世界位置 ↔ 当前帧 depthtex1 重建位置」比对，强于法线比对（法线是位置的派生证据）；水面自身波形法线不参与任何存储或拒绝逻辑（见 2.4）。

### 2.2 新增资源登记（自 28 起；与 shaders.properties、docs/handoffs/ 全部记录核对无冲突，R2 占 23、R6 占 24/25、R1 占 26/27）

| 项 | colortex28 | colortex29 |
|---|---|---|
| 格式 | RGBA16F（lit.fsh:35） | RGBA16F（lit.fsh:38） |
| 附件槽位 | `gl_FragData[3]`（水 pass 非 TAA / TAA 两态一致；见 §8 修复记录） | `gl_FragData[4]`（同左） |
| 尺寸 | `1.0 1.0`（SSR 开，properties:150）；SSR 关缩 `1 1`（properties:153） | 同左（properties:151/154） |
| 内容 | rgb = 时域混合后 SSR 命中辐射（HDR，Fresnel 前）；a = 混合后有效性 [0,1]，0 = 无有效历史 | rgb = 命中点 − 产生它的水面点（player-relative 世界轴差，帧无关，幅度被 water_raytrace 的 64–128 格范围约束，half float 精度足够）；a = 时间戳 `fract(frameTimeCounter/64)*64` |
| 清屏 | `Clear=false`、ClearColor 0（lit.fsh:36-37）；首帧 / 被清读 validity 0 → 干净回退当前帧 | 同左（lit.fsh:39-40） |
| 写顺序 | 仅水 pass 写；读写顺序 = 同一调用点先读（翻页=前帧）后写，无同帧自读假设（temporal.glsl 头注释） | 同左 |
| 生产者=消费者 | `program/water.glsl`（gbuffers_water 槽）↔ `global/water/temporal.glsl:astra_water_ssr_temporal` | 同左 |
| 生命周期 | 持久跨帧历史；每个水片段每帧重写自己的槽位 | 同左 |
| 关闭行为 | `SCREENSPACE_REFLECTIONS` 关 → 缓冲 1×1、blend 指令不发（properties:288-291）、模块编译为空（temporal.glsl:40 `#ifdef ASTRA_WATER_TEMPORAL`）；手动阀 `ASTRA_WATER_NO_TEMPORAL`（settings.glsl:147）=1 时链全裁、缓冲保持分配但无引用（properties 预处理器只见注册选项，R6 同款取舍） | 同左 |
| 非水片段 | 冰 / 玻璃 / 其它透明物共享 gbuffers_water，零初始化写 validity 0（lit.fsh:356-365），既不是未定义附件值、也不获得水的历史身份 | 同左 |

### 2.3 坐标约定（每个 UV 是否含当前抖动）

| 量 | 抖动 | 依据 |
|---|---|---|
| colortex28/29 存储栅格 | **每帧各自的抖动栅格**（水几何经 lit.vsh astra_jitter_clip 抖动后光栅化，写入位置 = 本帧 gl_FragCoord） | lit.vsh:176（现 lit.vsh 未改动，抖动加入 gl_Position） |
| `water_raytrace` 返回 hit UV | 含**当前**抖动 | global/water/raytrace.glsl:26 `astra_jitter_clip(gbufferProjection * …)` |
| `screen_view(hit.xyz)` 还原的视点 | 已扣除当前抖动（screen_view 内减 astra_jitter_uv） | lib/transforms.glsl:19-24；water.glsl:233 |
| 前帧历史读取 UV | 前帧矩阵（不含前帧抖动）重投影静止表面点 **+ 前帧抖动偏移**（Halton 表按 `(frameCounter+7)%8` 复制，含 lib/taa_jitter.glsl:14 的均值修正；TAA 关时为 0） | temporal.glsl:77-90、128-131；前帧矩阵不含抖动的约定同 taa_resolve.fsh:55-57 |
| 存储命中位置 | 世界轴差值，无抖动概念（抖动只作用于光栅化，不作用于世界坐标） | temporal.glsl:108 |
| 命中对应校验的当前帧投影 | 含**当前**抖动（depthtex1 是抖动光栅化的），比对前 `screen_view` 再扣回 | temporal.glsl:172-186 |

### 2.4 波形参数真实前帧值机制

- 波场是 `(世界位置, frameTimeCounter)` 的纯函数：surface.glsl 的采样坐标 = `time * rippleScroll[i] + 拉伸坐标`（surface.glsl:198-199、230-231、255-256），`time = frameTimeCounter * (WATER_WAVE_SPEED*0.01)` 由 lit.fsh 传入。因此**任一历史时刻的波场都可由真实前帧时间精确重求**，不需要近似外推。
- 真实前帧时间的两条获取途径：(a) colortex17 第二像素（metadata v2 前帧时间，仅 TAA 开时写入）；(b) **本链 colortex29.a 时间戳（与 TAA 无关）**——64 秒回绕修正后 `prevTime = frameTimeCounter - dt` 即上一帧真实 frameTimeCounter。
- 本链刻意**不**重求前帧波场：`water_surface`（surface.glsl:298-361）只改 `surface.normal` 与 roughness，从不改几何位置，水面点静止 → 相机级重投影精确（这正是任务书「水波主要表现为时变法线，不能把纹理相位速度当作真实几何顶点速度」的利用方式）；波运动在两帧之间对辐射的影响由命中对应容差（`0.25 + 0.05×|命中偏移|`，temporal.glsl:161）度量，而不是被换算成速度。未来需要显式前帧波值的分项（如折射链要存视差采样位、或要做光线方向变化加权）从 (b) 取 prevTime 重求 `surface_gradient` 即可，机制已就位。

### 2.5 拒绝 / 失效条件清单（每条：处理 + file:line）

| 条件 | 处理 | 证据 |
|---|---|---|
| SSR 失去命中（本帧 hit.a≤0） | 不消费；槽位写无效（validity 0），下一帧不再读到旧辐射 | temporal.glsl:114；water.glsl:252 无 hit 时仍调用以失效槽位 |
| 表面离开屏幕 / 首次进入 | 前帧重投影越出 [1.5 纹素边界] → 只用当前帧 | temporal.glsl:133-135 |
| 存储命中离开屏幕 | 存储命中重投影到当前帧 NDC 越界 → 拒绝 | temporal.glsl:170-176 |
| 命中物体变化（①当前命中点与存储命中点错位：反射路径上物体移动/进出，如实体横穿反射） | `|view_player(hitViewPos) − expected| > 0.25 + 0.05·|命中偏移|` → 拒绝 | temporal.glsl:160-166 |
| 命中物体变化（②存储命中处场景变化：物体移除/换块） | 存储命中重投影到当前 depthtex1：命中处变天空（depth≥0.999999）→ 拒绝；重建世界位置与存储位置差超容差 → 拒绝 | temporal.glsl:177-183 |
| 折射深度跳变 | **不适用本链**（折射背景分项未建链，规则归属第 1 节该分项）；本链中同类语义 = ②的深度/位置比对 | 见 5.2 |
| 透明覆盖 | 结构性免疫：生产与存储只用 depthtex1+colortex4（排除透明层的不透明快照），透明层从不进入历史；水界面侧接受测试在生产端既有 | water.glsl:57-61、:75-129（既有代码，未改） |
| 水界面切换（相机进/出水、熔岩/细雪） | 链仅在 `water && !belowWater && isEyeInWater==0` 时消费/写入，其余状态写无效标记；0↔1 切换帧必然经过「写无效」 | water.glsl:250；lit.fsh:352-361 零初始化 |
| 时间中断（/time set、暂停、维度往返 >0.5s、缓冲被清） | 时间戳回绕修正后 dt ∉ [−0.07, 0.5] → 拒绝（−0.07 覆盖 RGBA16F 在 [32,64) 的 ulp=0.03125 量化） | temporal.glsl:145-152 |
| 投影变化（FOV/纵横比/远近面） | 4 列逐列比较 gbufferProjection vs Previous（同 taa_state / cloud_temporal 判据） | temporal.glsl:117-122 |
| 启动 / 重载 | frameCounter ≤ 1 → 拒绝 | temporal.glsl:114 |
| 历史 NaN/Inf（缓冲重分配残留等） | history 或 meta 任一非有限 → 拒绝 | temporal.glsl:142-144 |
| 亮度漂移（日照、天气色板、命中滑过明暗边界） | 不硬拒绝；权重 × `1−smoothstep(0.20,0.80,ΔY/maxY)` | temporal.glsl:185-193 |
| 分辨率变更（不改 FOV/纵横比） | 无 viewWidth 指纹（rgb 三通道被命中偏移占满，R6 有空余通道而本链没有）；由内容校验自愈——重分配后的旧内容与当前 depthtex1 不匹配即被①②拒绝，一帧后重写；抖动补偿的亚像素误差 ≤0.44px 且随帧重写 | 备注，见第 6 节风险 |

## 3. 未覆盖分量（如实声明，不据单分项宣称 R5 完成）

见第 1 节表：**水面着色整体、环境反射 fallback、折射背景（含折射深度跳变拒绝）、水下视角界面（solas）、水下相机腿整体**均无历史，保持当前帧。README 已同步列出。

## 4. 已改文件（本任务全部改动）

新增：
- `Astra/shaders/global/water/temporal.glsl` — 水专用时域模块（缓冲采样声明、前帧抖动表、`astra_water_ssr_temporal`：重投影 / 门 / 双重命中校验 / 混合）。Astra 自有实现，无参考包源码（THIRD-PARTY.md 无需新行）
- `docs/handoffs/2026-09-27-R5-water-temporal.md` — 本文档

修改：
- `Astra/shaders/lib/settings.glsl` — `ASTRA_WATER_NO_TEMPORAL 0` 手动阀（:136-147 注释+阀）、`ASTRA_WATER_TEMPORAL` 派生宏（:427-434）
- `Astra/shaders/program/water.glsl` — include temporal.glsl（:19）；SSR 分支重构：`reflected`/`hitPos` 提出作用域（:230-231），时域消费与 colortex28/29 写入（:240-259）
- `Astra/shaders/program/lit.fsh` — 水 pass RENDERTARGETS 四态条件（:49-66：TAA±TEMPORAL → `0,5,16,28,29` / `0,5,28,29` / `0,5,16` / `0,5`）；colortex28/29 格式与清屏登记（:23-41，仅水 pass 单元可见）；非水片段零初始化（:352-361）〔2026-09-27 槽位错绑修复更正：非 TAA+TEMPORAL 态列表已统一为 `0,5,16,28,29`（见 §8），RENDERTARGETS 条件现位于 :49-69，零初始化现位于 :356-365〕
- `Astra/shaders/shaders.properties` — colortex28/29 条件尺寸门（:144-155）；`blend.gbuffers_water.colortex28/29=off`（:285-291，SSR 开时发出）
- `Astra/README.md` — 水面 SSR 命中辐射历史功能行（含覆盖边界与资源量）、待办行改为「实体时域增强及水时域的其余分量仍未完成」
- lang：**无键可写**（无 GUI 行即无键，R6 同款；非遗漏）

## 5. 交付对照（验收标准逐条）

1. 本文档含：状态✓、已改文件✓、调用关系✓、分项表✓、坐标约定✓、波形前帧机制✓、失效条件清单✓、资源登记✓、已完成✓、未完成✓、接续位置✓。
2. 完整链 + 拒绝规则 file:line：见 2.1 / 2.5。
3. 分项历史而非最终混合色：混合对象是 `water_sample_path` 传输的命中辐射（water.glsl:252），位于 Fresnel 混合（:396）与 `astra_scene_highlights`（:325）之前；未使用不透明地形速度；未把纹理相位/法线变化当速度（2.4）。
4. 坐标约定复用 TAA 当前/历史网格语义（2.3）；真实前帧波形参数机制（2.4，colortex29.a 时间戳 + colortex17 前帧时间参照）。
5. 水吸收与相机介质各只应用一次：本链不改任何介质路径；`astra_fog` / `astra_volume_prefix_medium` / colortex4 语义零改动（第 1 节介质表沿用 R2）。
6. TAA 关：链自带前帧 uniform 声明（temporal.glsl:63-67）与前帧抖动表（:77-90），编译与逻辑均不依赖 colortex17/ASTRA_TAA；无有效运动证据的分量（实体横穿等被拒绝的帧）保持当前帧；reactive 逻辑零改动（lit.fsh:486-488 未动，水仍 material 1 → reactive=1）；冰/玻璃零初始化隔离（lit.fsh:352-361）。
7. 剩余未覆盖分量在本文档第 1/3 节与 README 列明。
8. 新缓冲 28/29 与 properties/handoffs 核对无冲突（check #14：30 buffer 含 28=1、29=1）；选项注册表 80 上限遵守（未新增 GUI 选项，手动阀 + README 说明，R6 先例）。
9. check_pack 基线与交付复跑见第 7 节。
10. 驱动级编译验证见第 7 节。

## 6. 未完成 / 风险 / 下一处接续位置

- **无游戏画面、无帧时数据**（qa 无主世界离线出图能力）。基权 0.85、容差 `0.25+0.05d`、时间窗 [−0.07,0.5]、亮度钳制 (0.20,0.80) 均为源码推导初值，需游戏内 A/B；标定落点 `temporal.glsl` 常量区（:71）与 :161/:152/:190。
- 功能**默认随 SSR 启用**（GUI 行被注册表 80 上限挡住）：未验证的时域链直接进入 SSR 用户画面是最大风险；所有门失败均回退当前帧，但正常路径的混合观感未经确认。手动阀 `ASTRA_WATER_NO_TEMPORAL 1` 可立即回到原始路径（缓冲保持分配、约 31.6 MiB 无引用浪费，仅影响手动改 settings 的用户）。
- 分辨率变更（同纵横比）无指纹门：依赖内容校验自愈（2.5 末行）；若实测首帧异常，接续位置 = 把 colortex29.a 升级为「时间戳 + viewWidth/256 打包」或升 RGBA32F。
- 反射光路中亮度相近的移动物体可能产生 1–2 帧轻微混合残影（亮度钳制只能压不能清零；完全清零需存命中法线或对当前命中加邻域一致性检验——留作接续项，代价是每水像素额外重建）。
- 时域化仅覆盖命中辐射；`reflectionWeight`（当前路径有效性）未做时域，低有效性帧仍按当前帧权重输出——保守正确，但边缘噪声未获得时域抑制。
- **下一处接续位置（按优先级）**：
  1. 折射背景链：复用 2.1–2.5 骨架，生产在 water.glsl:335-336 的 `water_sample_path(refractedUV,…)` 调用点，新增命中/背景元数据缓冲（候选 colortex30 起），拒绝规则补「折射深度跳变」（对 refractedUV 处 depthtex1 做帧间比对）；colortex29.a 的时间戳机制直接可用。
  2. 反射光路实体残影硬化：存命中法线（候选 colortex30）或当前命中邻域一致性检验（temporal.glsl 校验段之后）。
  3. 水下视角界面（solas）与水面着色整体：需先定义可重建的分解（存分解分量而非混合色），入口 `solas_underwater_interface`（water.glsl:139-172）。
  4. 若统帅裁决必须有 GUI 行：退役一个既有选项或上调 80 上限后，把 `WATER_TEMPORAL // [false true]` 注册进 settings/`screen.WATER`/四档 profile，并把尺寸门从 `#if defined SCREENSPACE_REFLECTIONS` 改为二者与。

## 7. 证据

- `python qa/tools/check_pack.py`（仓库根目录）：开工基线 `17 checks: 3 FAIL, 0 WARN, 14 PASS`（#4 include 图 shell 直含 settings、#11 SC-28 DIRECTIONAL_SKYLIGHT/SCREENSPACE_AO、#15 fxaa 许可文本；既有，与本任务无关）；交付前复跑 **`17 checks: 3 FAIL, 0 WARN, 14 PASS`，FAIL 数不增**。期间 #14 缓冲清单从 28 buffer 增至 30 buffer（colortex28=1、colortex29=1，声明唯一且被消费），模块数 76→77、可达 74→75（temporal.glsl 已接线），无其它项变化。
- `python qa/tools/compile_glsl.py`（真实 OpenGL 4.6 前端，NVIDIA RTX 4050 Laptop，LWJGL 位于 D:\zhenhebao\.minecraft）：
  - BALANCED 默认档（SSR 开、TAA 关，链启用）→ `RESULT linked=105 failed=0 compute=9`
  - ULTRA + `--set ANTIALIASING=2`（TAA 开，验证前帧 uniform 不重复声明、RENDERTARGETS 0,5,16,28,29）→ `RESULT linked=105 failed=0 compute=9`
  - PERFORMANCE（SSR 关，缓冲缩 1×1、链编译剔除）→ `RESULT linked=105 failed=0 compute=9`
  - BALANCED + `--set ASTRA_WATER_NO_TEMPORAL=1`（手动回退阀）→ `RESULT linked=105 failed=0 compute=9`
  - BALANCED + `--set SCREENSPACE_AO=` + `--match gbuffers`（SSAO 开，验证 RGBA16F 补集声明逻辑）→ `RESULT linked=60 failed=0 compute=0`
  - 过程中抓到并修复的真实编译错（两处）：
    1. 零初始化块未限定水 pass → world1/gbuffers_weather（ASTRA_WEATHER，仅 2 个输出）出现 `error C5121: multiple bindings to output semantic "COL0"`——加 `ASTRA_WATER_PASS` 前置条件修复；
    2. TAA 开时 `lib/surface_buffers.glsl:5` 已声明 `const int RGBA16F`（SSAO||TAA 门下），我的 `#ifndef RGBA16F` 看不见 const 声明 → 33 个 gbuffers 单元 `error C1038: declaration of "RGBA16F" conflicts`——登记块收紧到 `ASTRA_WATER_PASS && ASTRA_WATER_TEMPORAL` 并按补集（`!ASTRA_SSAO && !ASTRA_TAA`）声明修复。
- 无画面 / 帧时证据，未宣称任何观感或性能收益。

## 8. 修复记录（2026-09-27：非 TAA 态水时域槽位错绑，独立审查 Critical）

- **问题**：非 TAA（ANTIALIASING=1，出厂默认）+ `ASTRA_WATER_TEMPORAL` 时，水 pass RENDERTARGETS 为 4 附件 `0,5,28,29`，位置 2=colortex28、位置 3=colortex29；而历史写入硬编码 `gl_FragData[3]`/`gl_FragData[4]`（water.glsl:255-256、lit.fsh 零初始化）→ 混合辐射落进 colortex29（元数据槽）、`gl_FragData[4]` 超出附件数被静默丢弃、colortex28 全程无人写（Clear=false → 恒为 0，validity=0）→ temporal.glsl 读 validity 0 即拒绝、每帧回退当前帧，链路在默认配置下失效。TAA 态（5 附件）映射正确。
- **修复**：选「统一 RENDERTARGETS 列表」方案——非 TAA+TEMPORAL 态列表由 `0,5,28,29` 改为 `0,5,16,28,29`（lit.fsh:65，附槽位对齐注释），使两态槽位恒定；water.glsl 与 lit.fsh 的历史写入点零改动。
- **未选「按状态切换槽位宏」的原因**：water.glsl 在 lit.fsh:16 被 include，位于 RENDERTARGETS 条件区（:49-69）之前，宏在该区定义对 water.glsl:255-256 不可见；要可见需把宏定义提到 :16 之前（越出本修复的白名单区域）或在 water.glsl 内另起一套状态切换（两套机制、改动更大），均不满足「改动最小」。
- **两态槽位映射（修复后）**：

  | 附件位 | 非 TAA+TEMPORAL（ANTIALIASING≠2） | TAA+TEMPORAL（ANTIALIASING=2） |
  |---|---|---|
  | [0] | colortex0（场景色） | 同左 |
  | [1] | colortex5（水面高度/有效性） | 同左 |
  | [2] | colortex16（绑定不写：reactive 写入 lit.fsh:503 在 ASTRA_TAA 门内；非 TAA 无读者，deferred.fsh 的 colortex16 读取也在 ASTRA_TAA 门内） | colortex16（reactive） |
  | [3] | colortex28（水历史辐射；写点 water.glsl:255、非水零初始化 lit.fsh:363） | 同左 |
  | [4] | colortex29（历史元数据；写点 water.glsl:256、非水零初始化 lit.fsh:364） | 同左 |

- **验证**：`compile_glsl.py --profiles BALANCED`（非 TAA 态）与 `--set ANTIALIASING=2`（TAA 态）各一轮，均 `failed=0`；`check_pack.py` FAIL 数不增（基线 3：#4/#11/#15）；`git diff --stat` 仅 `program/lit.fsh` 与本文档。
- **风险**：非 TAA 态水 pass 多绑一个 R8 附件（colortex16，Clear=true 每帧清屏、无读写方），代价可忽略；colortex16 在非 TAA 下的内容与修复前一致（恒为清屏值 0）。

## §9 2026-09-28 退役批注

本文件 §2–§7 记录的 SSR 命中辐射时域链与 §8 的修复（"0,5,16,28,29 不得改回"约束）已于 2026-09-28 整体退役：

- 根因一：链路绑定在几何阶段（gbuffers 水 pass）上，而该阶段不存在 composite 阶段的翻页读写契约，"读自身写缓冲"的前提不成立（lib/settings.glsl 现注释与 docs/2026-09-28-water-material-lighting.md）。
- 根因二：出厂默认 FXAA 档 colortex16 缩为 1×1，却被绑进全分辨率水通道 RENDERTARGETS，附件尺寸钳制绘制范围——这就是用户报告"水面消失、像一层带滤镜的膜"的直接原因（该列表形态源自 §8 修复）。
- 处置：colortex28/29 附件、声明、混合与零初始化全部移除（properties 保留 1×1 占位并注明 reserved）；program/water.glsl 不再 include 本模块；水面回归当帧反射/折射；§8 的槽位约束随之作废，不得据其恢复旧列表。
- 本模块文件保留为研究记录，已在 qa/tools/check_pack.py 的 PENDING_CONSUMERS（owner：R5 residual）与 GUARD_SYMBOL_SOURCES（ASTRA_WATER_TEMPORAL）登记。水时域若重启，需先落 composite 阶段生产者与独立历史目标，再按 §4 布局接线。
