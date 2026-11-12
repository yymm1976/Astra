# vanilla-advanced（batch4 逐包性能调研）

> 版本：Modrinth v1.0.1（56,788 下载，任务给定）。调研日期 2026-10-03，纯只读。
> file:line 基准：`reference_shaderpacks/vanilla-advanced/shaders/`（包内 shader 根即 `shaders/`，题述基准一致）。
> Astra 侧路径相对 `Astra/shaders/`；「未实现证据」的 grep 命令与命中数照录于 §五、§六。
> 去重前置：已读 `SUMMARY.md`、`SUMMARY-batch2.md`、`SUMMARY-batch3.md`、`docs/2026-10-02-shader-reference-performance.md`、`docs/2026-10-03-batch3-selected-optimizations.md`。

## 一、概况

- **定位**：小型「原版观感 + 少量 PBR/体积光」包，目标是高性能、可在低配机运行（`readme.txt` 无正式定位声明；由 26 个代码文件的规模与固定开销可见取向）。总程序数只有 gbuffers 若干 + 1 个 composite + 1 个 shadow：**光照在 gbuffer 前向算完，所有全屏效果（体积光/水下/岩浆/细雪着色）合并进唯一 composite pass**。
- **血统**：ThePlaneGuy45 自研（`readme.txt:9` Copyright © 2023 ThePlaneGuy45）。植物波动函数取自 **Complementary Reimagined** 并自行修改（`readme.txt:5-6`），是包内唯一声明的外部来源；因此该项只能思路级重写（Complementary License Agreement，见 SUMMARY.md ③）。
- **许可**：包内**无 LICENSE 文件**；`readme.txt:11-15` 含 MIT 式授权正文（"Permission is hereby granted, free of charge... to deal in the Software without restriction"），`readme.txt:1` 另有署名要求与「未实质修改不得转售/据为己有」声明。整体按「MIT 式 + 署名请求」理解（最终口径需统帅确认）；Complementary 衍生波函数不在该授权覆盖内。
- **规模（整包口径，实测）**：全包 **30 文件**（含 macOS `.DS_Store`），其中 `shaders/` 代码文件 **26 个 / 730 行**；`shaders.properties` 4 行、`shaders/block.properties` 3 行、`readme.txt` 14 行。任务给定「约 29 文件 / 730 行」与实测一致（差 1 为 .DS_Store）。非 shaders/ 代码目录：无。

## 二、管线与调度

- **program 清单**（`shaders/` 根）：
  - gbuffers：`basic / textured / hand / armor_glint / skybasic / skytextured` 六个独立程序；`terrain / water / entities` 由 `gbuffer/gbuffers.glsl` 按 `#define` 共用同一源。
  - `composite`（`composite/composite.glsl`，唯一全屏 pass）、`shadow`（`shadow/shadow.glsl`）。
  - **未提供的程序**：`gbuffers_clouds / weather / beaconbeam / spidereyes / damagedblock / block / entities_glowing / hand_water / dh_* / voxy` 等，按 Iris 惯例回落原版渲染（本包不覆盖这些几何）。
- **调度与分辨率**：`shaders.properties` 仅 4 行——`screen=[SHADOWS] [WAVING_OBJECTS] [VOLUMETRICS] PBR` 与 4 个滑条（`AMBIENT / shadowMapResolution / WAVING_SPEED / WAVING_STRENGTH / VOLUMETRIC_STEPS / VOLUMETRIC_DENSITY`）。**无 `program.*.enabled`、无 `size.buffer`、无自定义 uniform、无 `profile`、无 `flip/blend`**；shadow pass 恒开，效果开关全部是编译期 `#define`（`util/common.glsl:1-25`：`SHADOWS`、`COLORED_SHADOWS`、`PBR`、`WAVING`、`VOLUMETRICS_ENABLED`、`CREPUSCULAR_FOG`）。
- **常量与缓冲**：`const float shadowDistance = 324.0`（硬编码，`util/common.glsl:1`）；`shadowMapResolution=1024` 滑条默认（`:9`）。不写任何延迟数据缓冲：gbuffer 片元只 `/* DRAWBUFFERS:0 */ gl_FragData[0] = color`（`gbuffer/gbuffers.glsl:211-212`、`gbuffers_terrain.fsh` 等）。
- **阴影 pass**：`shadow/shadow.glsl:45-59` 顶点应用与 gbuffer 相同的畸变收缩 `factor=length(gl_Position.xy)+0.1`；`shadow.glsl:34-41` 片元对水（blocktype 10000）写 `color.a=0`。

## 三、分模块性能手法清单

> 每条 = file:line + 机制一句话。标〔A 有同类/已列〕者在 §六 给去重证据。

### 调度与阶段启停
- `shaders.properties:1-4` — 仅 screen/sliders；所有功能开关为编译期宏，不存在 pass 级调度。
- `util/common.glsl:1-25` — 全部质量参数（阴影距离/波/体积光步数/密度）为 `#define`/`const`，改档需重编译。
- `gbuffer/gbuffers.glsl:9-10` — `float iausfndsjddd = VOLUMETRIC_STEPS; float unjasfgdujhs = VOLUMETRIC_DENSITY;`：假引用全局变量，强制 Iris 为不同滑条值生成独立程序变体（工程 hack，非性能机制）。

### 地形光照与阴影（前向、光照在 gbuffer 内完成）
- `gbuffer/gbuffers.glsl:133-137` — `shadowDot=clamp(dot(N,L), AMBIENT, 1)`；`if(shadowPos.w>0.01)`：背光面在采样阴影图之前整段跳过〔A 已有背光跳过〕。
- `gbuffer/gbuffers.glsl:92-105` — 阴影偏置：`bias = (length(xy)+0.1)²/(0.1·res)`（半径平方增长）且 `z -= bias/abs(NdotL)`；坐标除以 `(length(xy)+0.1)` 做畸变收缩。Astra 用 grazingBias + 法线偏移（`global/lighting/shadowmap.glsl:214-244`），更稳 → §六-2。
- `gbuffer/gbuffers.glsl:139-145` — 单次 `shadowtex1`（有不透明深度）比较得到硬阴影；开启彩色阴影时 `shadowtex0/1` 选择见 `:140-144`。
- `gbuffer/gbuffers.glsl:147-152` — 水下像素把阴影底噪抬到 `AMBIENT*1.7`（防死黑），其余 `AMBIENT`。
- `gbuffer/gbuffers.glsl:176-186` — **彩色阴影只在 `shadowtex0`（含透明）比不透明更近时读取** shadowcolor0，并把 tint 与 lightmap.x 混合〔A 已有「遮挡时才读彩色阴影」〕。
- `gbuffer/gbuffers.glsl:190-207` — `shadowDot=sqrt(...)` 与 AMBIENT 兜底，光照在 gbuffer 内直接乘入 albedo。
- `shadow/shadow.glsl:34-41` — shadow pass 对水写 alpha 0；`:45-59` 顶点复用 gbuffer 同一畸变系数（不引入额外纹理/矩阵）。

### 云
- 无云程序：`gbuffers_clouds` 缺失，原版云几何按原版渲染（本包不参与云计算）。

### 雾与大气
- `gbuffers_skybasic.vsh:5-8` — 天空/星空在**原版 skybasic 程序内**处理：逐顶点判断 star（`gl_Color.r==g==b>0`）并传 `starData`。
- `gbuffers_skybasic.fsh:18-34` — 天空色 = `mix(skyColor, fogColor, fogify(max(upDot,0),0.25))` 一次解析式，无延迟天空 pass、无 LUT、无步进；星空像素直接取顶点色。〔batch3 已列「解析 getSkyBasic」同型〕
- `composite/composite.glsl:26-43` — 复用的 `getShadowPos`：`factor=length(xy)+0.1` 畸变 + 半径平方偏置；用 `clamp(v)==v` 比较在端点算出「是否在阴影图内」标志 `w`（供体积光一次性越界判断）。
- `composite/composite.glsl:55-124` — 体积光：**把射线两端点各变换一次到阴影空间（sp0/sp1），循环内只做 `mix` 插值 + 1 次 shadowtex1 取数**，不再逐样本做齐次除法/畸变；只对向阳样本累积。
- `composite/composite.glsl:75-80` — 固定 march 距离 `castDist=20./VOLUMETRIC_STEPS`，步数与总距离解耦的密度归一化；`CREPUSCULAR_FOG` 加 `pow(worldTime/24000-1,6)` 昼夜因子。
- `composite/composite.glsl:87-120` — 每步先读 shadowtex1 判遮挡；未遮挡才处理着色（水下按高度混向深蓝；陆上按彩色阴影 tint × 密度混入）；`sp1.w<0`（整条射线出图）时跳过彩色分支。
- `composite/composite.glsl:123-127` — 水下/岩浆/细雪雾用单次 `mix` 常数色覆盖（无吸收积分）。

### 水与水下
- `util/common.glsl:58-72` — 水波：`sinp(x)sinp(z)` 单层正弦；位移幅度乘 `1/(length(screenSpacePosition)*0.2+1)` 距离衰减（远处波幅自动收敛，避免远处抖动）〔A 已有水面距离滤波/Nyquist，见 §六-5〕。
- `gbuffer/gbuffers.glsl:245-247` — 水方块（blocktype 10000）在顶点应用 `water_Wave`。
- `composite/composite.glsl:91-94` — 水下视角：按世界高度 `smoothstep` 混入深蓝雾色，不跑体积积分。
- `gbuffer/gbuffers.glsl:170-174` — 水面/含 PBR 时把 sheen 混入 alpha 作为加亮（不额外 pass）。

### 粒子·实体·天气
- `gbuffers_textured.fsh/.vsh` — 粒子/文字/物品等只做 `texture*glcolor*lightmap`（11 行级）；未提供 weather/beacon/spidereyes 等程序（回落原版）。
- `gbuffer/gbuffers.glsl:107-122` — 实体/地形片元直接取原版 `lightmap`；实体分支跳过光图 `abs()` 修正（`#ifndef ENTITIES`）。
- `gbuffer/gbuffers.glsl:238-249` — 顶点按 blocktype 10003/10002/10000 分派植物/水波动，只对这几类几何求波〔A 已有植被风场距离 LOD〕。

### 后处理与缓冲内存
- 无任何后处理程序：无 TAA/AA、无 Bloom、无曝光、无 tonemap（原版后期链）。`DRAWBUFFERS:0` 单目标写出（`gbuffer/gbuffers.glsl:211`）。

### 工程与设置系统
- `util/common.glsl:1-25` + `shaders.properties:1-4` — 选项走「编译期宏 + 少量滑条」；`block.properties:1-3` 用 10000-10003 四类 ID（水/植物/花草/树叶）驱动顶点波动。
- `gbuffer/gbuffers.glsl:253-258` — 实体/地形顶点构造 TBN（`at_tangent`），片元用 `normals` 贴图与 `specular` 贴图做廉价 PBR（`:116-121`）。

## 四、反面印证（不值得学的性能做法）

1. **固定 324 格阴影距离 + 1024 影图**（`util/common.glsl:1,9`）：面板不给 shadowDistance 滑条，低配机没有下调影子收集范围的入口，与「低配可跑」定位相悖；Astra 的 112 格性能档与分辨率/距离双滑条更合理。
2. **体积光固定 20 格、均匀步长、无距离/遮蔽自适应**（`composite/composite.glsl:75-84`）：无论视线多远都均分到全深度；Astra 已有 48 格光束上限 + 192 格体积雾上限 + 前缀/自适应步数（`global/atmosphere/volume_fog.glsl:36-58`），机制全面更强。
3. **所有效果合并单 composite、无 per-effect pass 门控**（`shaders.properties:1-4`）：关掉体积光/水下效果省不下这一趟全屏；与 SUMMARY-batch3 §2.4 已判「不学」的 YoFPS 单 pass 合并同型，Astra 不应回退。
4. **无任何时域/历史复用**（无 TAA/云历史/曝光）：低配以画质换开销的路线；Astra 的 TAA/云历史/曝光历史是有意保留的画质资产。
5. **bias 除以 |NdotL|**（`gbuffer/gbuffers.glsl:103`）：掠射角理论发散，仅靠 `>0.01` 门槛兜底；Astra 的 grazingBias/normal offset（`global/lighting/shadowmap.glsl:214-244`）是更稳定的形式。
6. **假引用全局变量强拉编译变体**（`gbuffer/gbuffers.glsl:9-10`）：说明选项系统未按 Iris 规范表达；Astra 的 `#ifdef` 空选项技巧（批次一已列 Mellow）更干净。
7. **Forward-only、零延迟数据**：省了 gbuffer 带宽/程序数，但因此做不了 AO/SSR/时域类效果；是设计取舍，不是 Astra 应学的优化（Astra 的延迟数据需求已定）。

## 五、新颖借鉴点

> 每条候选均先以多组关键词 grep `Astra/shaders` 验证；本包**没有**通过去重的「Astra 未实现」性能手法。

- **A 组（低代价可直接排期）**：无。
- **B 组（中代价需接线）**：无。
- **C 组（大工程战略项）**：无。

核对过程（候选 → 结论）：
- 背光面跳过阴影采样（`gbuffer/gbuffers.glsl:136`）→ Astra 已有：`global/lighting/diffuse.glsl:348-355` 在采样前按 facing 项早退。
- 彩色阴影仅在透明遮挡时读（`gbuffer/gbuffers.glsl:176-186`）→ Astra 已有（`program/shadow.fsh`、`global/lighting/shadowmap.glsl`；任务背景「遮挡时才读彩色阴影」）。
- 阴影偏置形式（`:92-105`）→ Astra 已有更强的 grazingBias/normal offset（`global/lighting/shadowmap.glsl:214-244`）。
- 体积光平行阴影空间行进（`composite/composite.glsl:69-84`）→ 已按 SUMMARY-batch2 ⑤-2 #4 落地到 Astra：`global/atmosphere/volume_fog.glsl:120-145`、`global/water/light_shafts.glsl:78-84`。
- 水体/岩浆/细雪雾一次 exp 着色（`composite/composite.glsl:91-127`）→ Astra 已有同型（`global/water/absorption.glsl`、`lib/solas_water.glsl`、`lib/nether_fog_density.glsl`）。
- 水面/植物波动 + 距离衰减（`util/common.glsl:58-72`、`gbuffer/gbuffers.glsl:238-249`）→ Astra 已有植被风距离 LOD（`global/lighting/wind.glsl:233-256`）与水面距离滤波（`global/water/surface.glsl:212-296`）。
- 解析双色天空（`gbuffers_skybasic.fsh:18-34`）→ SUMMARY-batch3 已列「地表像素只用解析 getSkyBasic」（Vanilletix），属已列方向。
- 廉价 PBR sheen / TBN（`gbuffer/gbuffers.glsl:116-121,154-174,253-258`）→ Astra 有完整 PBR 链路，无迁移价值。
- 编译期宏选项/少量滑条（`util/common.glsl`）→ Astra 已有更细的设置系统，无借鉴。

## 六、去重排除（Astra 已有等价实现/已列清单）

1. **体积光平行阴影空间行进**：Astra 已实现且保留逐样本齐次除法+畸变（`global/atmosphere/volume_fog.glsl:120-145`；`docs/2026-10-02-batch2-implementation.md` 记录）；water shafts 同样外提变换（`global/water/light_shafts.glsl:78-84`）。
2. **阴影偏置/畸变**：Astra `global/lighting/shadowmap.glsl:214-244`（grazingBias、法线偏移、径向 1.5×length 项）。
3. **彩色阴影读取门控**：任务背景已列 Astra 已实现；Astra `program/shadow.fsh:65-79` 仅在遮挡时写彩色 tint，消费端按 coverage 早退。
4. **背光/无直射跳过**：`global/lighting/diffuse.glsl:348-355`（facingAway 时 `visibility=1` 且不取样）；体积雾内 `direct<=0` 早退（`volume_fog.glsl:86-88`）。
5. **水面距离衰减/波动**：Astra 水面有 Nyquist 距离滤波与视差 4 步（`global/water/surface.glsl:212-296`），植被风有 128-192 格 LOD（`global/lighting/wind.glsl:233-256`）。
6. **单 pass 合并全效果**：SUMMARY-batch3 §2.4 已把 YoFPS 同型做法判为「不学」；Astra 的 program 阶段启停 + size.buffer 分档是既定纪律。
7. **解析天空/单色雾**：batch3 已列（Vanilletix getSkyBasic、YoFPS 解析 exp 雾）；Astra 天空/雾模型为有意保留的更高质量实现。

## 七、无法判定

1. **体积光端点线性 mix**（`composite/composite.glsl:69-84`）：把已除权的 `sp0/sp1` 在循环内直接 `mix`，省掉每样本齐次除法与阴影畸变重算；Astra 明确选择保留逐样本除法与畸变（`global/atmosphere/volume_fog.glsl:120-121` 注释、batch2 落地记录），因此这是「更快但近似」的另一取舍，画质（畸变非线性带来的阴影错位）需 A/B 才能判定，不建议无实测前采纳。
2. **shadow pass 水写 alpha=0**（`shadow/shadow.glsl:38`）：该 alpha 是否被 Iris 的 alphaTest 在阴影 pass 自动剔除、能否等价「水不投影」策略无法从包内源码判定；Astra 的水投影走 shadowcolor0 焦散记录（`program/shadow.vsh` 水分类 + `global/water/caustics.glsl`），属不同设计，不宜直接对照。

## 八、备注（供统帅）

- 许可：包内无 LICENSE 文件，readme 的 MIT 文本 + 署名/禁转售句子存在口径差；植物波动来自 Complementary Reimagined（`readme.txt:5-6`），只能思路级重写，不能随 MIT 文本一起搬。
- 本包程序数与效果数都很少，本次结论「无新颖性能点」；其价值主要在反面印证（§四）与「低配包也不该省的纪律」对照。
