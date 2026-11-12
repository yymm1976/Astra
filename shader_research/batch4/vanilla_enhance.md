# vanilla_enhance 性能调研（batch4 · 只读）

日期：2026-10-03。范围：只读调研，产物仅本文件；未改动任何参考包或 Astra。
行号基准：相对 `reference_shaderpacks/vanilla_enhance/shaders/`（本包 shader 根即 `shaders/`，包根除此之外无其它目录）。
去重基线：`shader_research/SUMMARY.md`、`SUMMARY-batch2.md`、`SUMMARY-batch3.md`、`docs/2026-10-02-shader-reference-performance.md`、`docs/2026-10-03-batch3-selected-optimizations.md`（下称「五份材料」）+ 任务背景列出的 Astra 已实现手段。每条候选均已对 `Astra/shaders` 做多关键词 grep，见「候选去重排除明细」。

## 概况

- 定位：Modrinth v1.2（111,303 下载，任务简报口径）。轻量「原版增强」：只做观感增强（光照曲线、PBR 高光、风、解析云与雾、水下效果），**无阴影图、无延迟管线、无体积效果**。包内 `shaders.properties:1` 头注释自称 "Vanilla Enhanced 1.1 - Minecraft 26.2 compatibility"，与简报 v1.2 存在版本出入（[假设] 包内未同步更新，报告按简报 v1.2 记录）。
- 血统：包内无 README、无 LICENSE、无代码头署名，无法确认任何血统；全包 `#version 120` + `gl_FragData`，注释为土耳其语。与已研究的 62 包不存在可辨识同源关系（无 BSL/Complementary/Chocapic/Photon/Bliss 系代码头），故按完整包调研，不做「只报增量」。
- 许可：包内**无任何 LICENSE/README/版权文本**（整包 16 个文件全部位于 `shaders/`，`*licen*`/`*readme*`/`*.txt`/`*.json` 检索为零）→ 按默认版权保留（ARR）处理，只能读思路 + 独立重写 + THIRD-PARTY.md 登记；本报告不采用其任何代码。
- 规模：整包 16 文件 / 1,151 行（wc -l 口径，含 properties）；全在 `shaders/` 下，**无非 shaders/ 代码目录**。其中纯 shader 代码 14 文件（7 组 gbuffers fsh/vsh）/ 1,126 行（与简报口径一致）；另 `block.properties` 22 行、`shaders.properties` 3 行。

## 管线与调度

- program 清单（全部）：`gbuffers_basic`、`gbuffers_block`、`gbuffers_entities`、`gbuffers_skybasic`、`gbuffers_terrain`、`gbuffers_textured`、`gbuffers_textured_lit`（各 fsh/vsh 成对）。**没有 shadow / composite / deferred / final / water 程序**：阴影、延迟、后处理阶段整段缺席（依赖 Iris 缺件回退与本包不写 final；[假设] 具体回退链以 Iris 文档为准，工作区内无该文档可核）。
- `shaders.properties` 全文 3 行：`oldLighting=true`（:2）、`separateAo=false`（:3）。无 `program.*.enabled`、无 `size.buffer`、无 colortex 格式 / mipmap 声明、无 profile 预设、无 CPU custom uniform。
- 分辨率/缓冲分档：唯一的缓冲声明是 `gbuffers_terrain.fsh:3 /* DRAWBUFFERS:012 */`（写 colortex0/1/2）；其余程序走默认 DRAWBUFFERS:0。无任何 `size.buffer` 缩放。

## 分模块性能手法清单

### 调度与阶段启停

- `shaders.properties:2-3` — 仅两条管线级开关：`oldLighting=true`（光照模式交回引擎）、`separateAo=false`（AO 并入光图）；无 pass 门控、无资源分档（见「无法判定项」1）。
- 程序清单缺件即阶段缺席 — 包内不提供 shadow/composite/deferred 程序，阴影与后处理两段在 Iris 下自然不存在；这是功能裁剪而非调度优化（见「反面印证」）。

### 地形光照与阴影

- `gbuffers_terrain.fsh:294-295` — 地形光照全部来自 vanilla lightmap（`pow(lightmapColor,0.88)*0.9` 逐像素整形），无方向光计算、无阴影图查询；全包最省的一处是「不做」。
- `gbuffers_terrain.fsh:285-290` — PBR 昂贵段用 `smoothstep(0.18,0.45,光强)` 门控，光强过低时整段 `dynamicPBR` 结果被 mix 权重压掉（分支仍求值，属分支预测友好写法）。
- `gbuffers_terrain.fsh:138` / `:187` — 天空光段仅在 `skyLightWeight>0` 展开（含日/月方向归一化、反射方向、Fresnel），方块光段仅在 `blockLightWeight>0` 展开；暗处像素省去两段高光数学。
- `gbuffers_terrain.fsh:121-126` — 资源包法线仅当偏离中性 >0.01 时参与（法线纹理本身仍被无条件采样，见「反面印证」）。
- `gbuffers_entities.fsh:102-124` — 实体走另一套更简的近似光照（wrap 半兰伯特 + 固定 hemi + 一次 `pow` 高光），无阴影查询。
- `gbuffers_textured_lit.fsh:5-11`、`gbuffers_block.fsh:27-33` — 最简路径：`texture×glcolor×lightmap`，块实体只多一次雨天去饱和。

### 云

- `gbuffers_skybasic.fsh:130` — 视野仰角在云带外（`cloudMask<0.005`）直接返回天空色，不进 FBM。
- `gbuffers_skybasic.fsh:140-149` — 两层 FBM（合计 12 次 value noise，6 阶/层，:37-50）后低于阈值再次返回天空色；无质量档、无分辨率分档（见「反面印证」）。
- `gbuffers_skybasic.fsh:133-134` — `1/max(dir.y,0.08)` 透视投影 UV（数值保护下限）。

### 雾与大气

- `gbuffers_skybasic.fsh:83-117` — 天空为纯解析渐变（4 色 mix + 晨昏 peak + 仰角曲线），零纹理、零步进、零 LUT。
- `gbuffers_terrain.fsh:225-257` — 全解析 exp² 雾 + 昼夜/晨昏/雨三色混合，距离上限 `clamp(...,0.85)`；无体积步进、无高度雾。
- `gbuffers_entities.fsh:61-88` — 同型雾函数在实体程序复制一份（跨程序重复，非共享 include；见「反面印证」）。

### 水与水下

- `gbuffers_terrain.fsh:314-349` — 水下效果全部内联在 gbuffers：水色乘算（:318-322）、3 次 value noise 焦散（:59-70,324-330）、按距离指数吸收（:332-335）、粒子噪声（:337-340）、正弦近似 god rays（:342-347，`skyLight>0.4` 时才有）。水面本身无独立程序、无折射/反射/SSR。

### 粒子·实体·天气

- `gbuffers_entities.fsh:90-100` — 眼睛/红石光效只用两次颜色阈值判断（红、绿通道），无额外光源系统。
- `gbuffers_entities.vsh:21-35` — 实体摆动函数已写好但调用被注释（`:51`），实际零开销。
- `gbuffers_terrain.fsh:300-302`、`gbuffers_entities.fsh:159-161` — 雨天去饱和以 `rainStrength>0.01` 阈值门控。

### 后处理与缓冲内存

- 无自定义 composite/final — 后处理为零 pass；`gbuffers_terrain.fsh:360`（colortex1）/`:366`（colortex2）写了 G-buffer，但**包内无任何消费者**（见「反面印证」）。

## 反面印证（不值得学的性能做法）

- **写入无人消费的 MRT**：`gbuffers_terrain.fsh:3` 声明 `DRAWBUFFERS:012`，`:360` 写世界法线+金属度、`:366` 写打包世界坐标，但包内没有 composite/deferred/final 去读 colortex1/2——纯填充/带宽开销（注释自称 "composite için"（供 composite 用），实际无 composite）。
- **帧不变量逐像素重算**：`getSmoothDayNightColor()` 的 `worldTime` 多分支（`gbuffers_terrain.fsh:85-102`）在同一像素最多被调用 2 次（:164 在 dynamicPBR 内、:278 主流程；entities.fsh 同型 :109、:143）；日/月方向每像素 `normalize` + 视图→世界矩阵变换（terrain.fsh:142-155）。五份材料已列「帧不变量 CPU 预计算」（SUMMARY.md:116，12 包印证），本包是反面样本。
- **固定成本的噪声链**：云固定 2 层 ×6 阶 FBM（`gbuffers_skybasic.fsh:37-50,137-146`），无距离/质量降档；水下焦散固定 3 次 noise（:59-70）且对每像素求值，与「步数/质量分档」的既有共识相反。
- **死代码与歧义**：`gbuffers_terrain.fsh:363-364` 声明 `float near/far` 遮蔽同名 uniform；`:355-358` 重复且错位的注释；`gbuffers_terrain.vsh:145` 算出 `waveEffect` varying 但片元不声明（链接后无消费者）。
- **光照直接叠加**：`gbuffers_terrain.fsh:287-289` PBR 结果与光图因子叠乘（materials 已定 IPBR 类启发式），无能量守一处理——属画质问题，同时说明其「轻量」来自功能少而不是机制新。

## 新颖借鉴点（A/B/C）

- **A：0 条；B：0 条；C：0 条。** 本包没有 Astra 未实现且可吸收的新颖性能手法；其「轻量」来自不提供阴影/延迟/后处理/水体系统（见概况与反面印证）。
- 唯一未决候选 `oldLighting=true` 转入「无法判定项」1，未计入计数。

### 候选去重排除明细（机制 | 包内出处 | 排除依据）

| 候选机制 | 包内出处 | 排除依据 |
|---|---|---|
| 管线级 AO 归属开关 `separateAo=false` | shaders.properties:3 | Astra 已有同名条件开关：`Astra/shaders/shaders.properties:236,239`（`#ifdef SHADOWS` 下 true/false）、`Astra/shaders/program/lit.vsh:61` AO 契约注释；`grep -rn "separateAo" Astra/shaders` 命中 3 处 |
| 缺 program 即缺阶段（无 shadow/composite/deferred） | 程序清单 | 属功能裁剪；Astra 已有 program 级启停 96 处 `program.*.enabled`（`Astra/shaders/shaders.properties:88-104` 等，其中 52 处=false）与 `size.buffer` 分档（`Astra/shaders/shaders.properties:18-87`）；材料 SUMMARY.md:115,117 已列 |
| 风动画按块 ID 允许表 + 每类速度/强度 | gbuffers_terrain.vsh:29-72,89-110 | Astra 已有 `Astra/shaders/global/lighting/wind.glsl`（含 128–192 格距离 LOD，`Astra/shaders/global/lighting/wind.glsl:233-256`）；batch3 已把「植被风距离 LOD」列为 Astra 已实现（docs/2026-10-03-batch3-selected-optimizations.md:9） |
| 云带 mask 早退 / 密度阈值二次早退 | gbuffers_skybasic.fsh:130,149 | 同族「空区跳过/首次命中/距离 break」材料已列（SUMMARY-batch3.md:129）；Astra 平面云已有交段裁剪与整段返回（`Astra/shaders/global/atmosphere/clouds_planar.glsl:197-270`，grep `return`/`break` 命中） |
| 两层 FBM 解析云 | gbuffers_skybasic.fsh:137-146 | 属功能简化替代；Astra `Astra/shaders/global/atmosphere/clouds_planar.glsl` 为纹理+双尺度解析密度（:86-136），无借鉴需求 |
| 解析天空渐变（4 色 + 晨昏 peak） | gbuffers_skybasic.fsh:83-117 | 「解析天空/闭式散射」类已在 SUMMARY-batch2.md:58,69 列为对照项；Astra 天空模型覆盖更细 |
| exp² 解析雾 + 三色混合 | gbuffers_terrain.fsh:225-257（副本 entities.fsh:61-88） | SUMMARY-batch2.md:287 已判「雾模型整体…无借鉴价值」；原版 `gl_Fog` 复用亦见 SUMMARY-batch3.md:158（VanillAA） |
| 水下内联：吸收/3 次噪声焦散/正弦 god rays | gbuffers_terrain.fsh:314-349 | Astra 已有按距离吸收、shadowcolor0 解析焦散、水下光束独立历史（任务背景；SUMMARY.md:282 的接续说明） |
| 光强门控 PBR 分支 | gbuffers_terrain.fsh:285-290 | Astra `Astra/shaders/global/lighting/diffuse.glsl:257-296` 已有 facing/coverage 门控（同文件 `:331-343` 注释明示背光跳过省 shadow fetch） |
| 纹理亮度金属度启发式 | gbuffers_terrain.fsh:128-130 | 材料已列「IPBR 自发光启发式（亮度提取）」（SUMMARY.md:34）；Astra `Astra/shaders/lib/surface_emission.glsl` 已有材质级启发 |
| 实体简化方向光（wrap 半兰伯特 + hemi） | gbuffers_entities.fsh:102-124 | 材料已列「无阴影档方向感」（SUMMARY-batch2.md:24，drdestens/bvs 两包印证） |
| 雨天去饱和/阈值门控 | gbuffers_terrain.fsh:300-302 | 材料已列「雨量门槛/强度阈值门控」（SUMMARY-batch3.md:75,125） |
| 无效块 ID 钳制（`blockId<0/>250→0`） | gbuffers_terrain.vsh:140-142 | 健壮性处理，非性能手法 |

## 无法判定项

1. **`oldLighting=true`（shaders.properties:2）**：包内与工作区均无 OptiFine/Iris 属性文档；五份材料从未出现该属性；已研究的 42+20 包一律 `oldLighting=false`（grep reference_shaderpacks 多包命中 false，如 bsl-shaders:13、photon-shader:124、mellow:2，路径各相对其 `shaders/`）。batch2 miniature 报告仅记「oldLighting=false = 关掉引擎旧式方向光，交给自己的 FLAT_LIGHTING」。按此解读，`true` 只是保留引擎已计算的旧式顶点方向光——省的是「该包不写方向光」，而引擎顶点着色照常执行，对 Astra 不构成可吸收的 GPU 开销削减，且该属性是全局声明（非 profile 内），无法随画质档切换。**卡点：Iris/OptiFine 对该属性的确切行为与是否支持未验证；需要统帅提供平台文档或实机对比后才能升级/关闭该候选。**
2. 本包缺 shadow/composite/deferred 程序时 Iris 的回退行为（哪些程序回落到 gbuffers_textured/basic）未在本地核证——影响「阶段缺席」的描述强度，但不影响「无新颖手法」的结论。
