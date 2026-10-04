# Super Duper Vanilla 1.3.8 研读报告（面向 Astra 的可借鉴点）

> 研读对象：`reference_shaderpacks/super-duper-vanilla/`（下文行号均相对包根 `shaders/` 目录）。
> 对照目标：Astra（`Astra/shaders/`，Iris 专用、前向地形光照、原生观感增强取向）。

## ① 包概览

- **版本与作者**：Super Duper Vanilla v1.3.8（每个着色器文件头均有版本水印，如 `main/gbuffers/gbuffers_clouds.glsl:2`），作者 Eldeston，出品方 FlameRender™ Studios（`README.md:10`）。定位是复刻官方被砍掉的「Super Duper Graphics Pack」（超逼真预设）及其他流行 MC 作品的观感；CurseForge/Modrinth 合计数百万下载。仅保证 Iris 1.6.10+ / MC 1.18.2+，自 1.3.7 起 Optifine 不再优先维护（`README.md:46-48`）。
- **许可证**：FlameRender (C) Studios License v1.6（`LICENSE:1-2`），专有许可（非 OSI 开源）。关键条款：
  - 允许为个人使用修改（1.1，`LICENSE:23`）；
  - 允许以「修改版」形式再分发，但必须：改用同一许可、名字不得含 "Super Duper Vanilla"、附带许可与版权声明、显著署名原作者（1.4 a-d，`LICENSE:31-35`）；
  - 其余形式禁止再分发（2.1，`LICENSE:38`）；且「仅调整数值/设置」不构成修改版（0.6.a，`LICENSE:19`）。
- **风格定位**：「官方超逼真预设的现代复刻」——原生观感增强派：保留方块形状与贴图辨识度，靠色调分级、雾、水、云、动画提升质感，而非写实化重造。与 Astra 的取向同路，故其「观感配方」比单点技术更有参考价值。
- **工程风格**：单文件短小（lib 下多数 <100 行）、宏开关驱动、`shaders.properties` 自定义 uniform 表达式承担大量运行时计算（见②-性能）。

## ② 架构与特性清单

### 总体架构
- 前向 + 局部延迟混合：不透明地形在 `gbuffers_terrain` 写 G-buffer，在 `main/deferred1.glsl` 统一做复杂着色（`deferred1.glsl:296` 调 `complexShadingDeferred`）；水面/半透明前向着色（`main/gbuffers/gbuffers_water.glsl:296` 调 `complexShadingForward`），VL 与透明着色在 composite0。每个 program 文件头用一行注释标注该 pass 职责（如 `main/composite.glsl:14`）。
- 三维度共享同一套 program，由 `dimension.properties:10-15` 映射（world0=`*` 通配、world-1=下界+Undergarden、world1=末地），每维度一份 `world0/world-1/world1/world.glsl` 宏配置决定光照/云/雾密度。
- 设置系统：`lib/settings.glsl`（含 6 档 profile：POTATO→ULTRA，`shaders.properties:2-6`）+ 每维度调色子菜单（`shaders.properties:145-195`）。

### 大气 / 云
- **三档云类型** `CLOUD_TYPE [0 1 2]`（`lib/settings.glsl:88`）：0=原版云重着色（`gbuffers_clouds.glsl:19` 在非 0 时整体废draw，`:87-90` 用天光+太阳色+高度梯度给原版云简单着色并写入 HDR）；1=天空盒视差云；2=「Story Mode」准体积云。
- **云贴图驱动**：`textures/clouds.png`（256x256，双通道=两层云）绑定为 composite/deferred 阶段的 colortex0（`shaders.properties:376-377`），所有云采样都走 `texelFetch`，无 3D 噪声。
- **天空盒视差云**：沿视线在云图上按 `SKYBOX_CLOUD_STEPS` 步进采样，记录两层命中深度（`lib/atmospherics/skyRender.glsl:20-36`）；UV 由 `nEyePlayerPos.xz * (6/y)` 投到云高平面并随相机+时间平移（`skyRender.glsl:52-56`）。
- **双层云**：第二层用 `planeUv * 2.0` 更高频采样后与第一层取 max（`skyRender.glsl:58-60`，开关 `settings.glsl:89`）。
- **动态云**：`sin(fragmentFrameTime * FADE_SPEED)` 在两层云图之间交叉淡化，模拟云形演化；雨天直接切到两层取 max（更阴沉）并加 rainStrength 加权（`skyRender.glsl:62-68`，开关 `settings.glsl:90`）。
- **准体积云（CLOUD_TYPE 2）**：在 `y ∈ [-VOLUMETRIC_CLOUD_DEPTH, 0]` 的垂直包围盒内 raymarch 云图（`lib/rayTracing/volumetricClouds.glsl:13-21`），步数随穿越距离动态收缩（`:27-28`），返回两层云密度供天空与反射共用（`:45-50`）。
- **无时域**：云完全每帧解析计算，无历史缓冲/重投影；开销换取零 ghosting。
- **雾**：解析高度雾，公式来自 StackExchange（`lib/atmospherics/fogRender.glsl:8-10`），垂直密度在日/夜/暮三档间按 dayCycle 插值（`fogRender.glsl:14-19`，密度常量 `world0/world.glsl:39-47`）；Complementary 式边界雾 `exp2(-exp2(...))`（`fogRender.glsl:1-3`，应用于 `main/deferred1.glsl:316-318`）。
- **体积光**：7 步 shadowmap 射线步进（`lib/rayTracing/volumetricLight.glsl:1,49-54`），水下 VL 加密 6 倍（`:9-11`）；天空反射里放假 VL 项（`skyRender.glsl:238-254`）。
- **天空**：解析渐变+太阳/月亮光斑（`skyRender.glsl:83-106`）、noisetex 恒星（`:130-140`）、末地黑洞（`:280-296`）。

### 水体
- **程序法线**：从 noisetex 高度场三点差分生成法线 `H2NWater`（`lib/surface/water.glsl:12-24`），双层流动噪声 `getCellNoise`（`:1-9`）；参数 WATER_BLUR_SIZE/WATER_DEPTH_SIZE/WATER_TILE_SIZE 可调（`settings.glsl:141-143`）。
- **顶点波动**：cos 单波，仅水面方块 ID 11100-11199，幅度 0.05（`lib/vertex/waveWater.glsl:2-17`）。
- **风格化吸收**：与 opaque 深度差线性化后 `exp2(blockDepth * 0.25)` 同时压 albedo 与 alpha（`gbuffers_water.glsl:248,269-275`）。
- **岸边泡沫**：深度差取指数边缘亮度，加到水 albedo 上（`gbuffers_water.glsl:250,280-282`）。
- **SSR**：线性步进+积分二分细化（`lib/rayTracing/rayTracer.glsl:17-53`，注明基于 Belmu NobleRT / Shadax SSR，`:5-6`）；失手时把反射向量延伸到远平面投影回屏幕做「假 SSR」兜底（`lib/lighting/complexShadingDeferred.glsl:44-53`），最终混合天空反射或上帧颜色（`:55-63`，`PREVIOUS_FRAME` 无限反弹，`settings.glsl:73`）。
- **焦散在 shadow pass**：非透明物直接把 albedo 写进 shadowcolor0；水面像素用 `squared(0.256 + getCellNoise(uv))` 调制（`main/shadow/shadow.glsl:164-177`），配 `UNDERWATER_CAUSTICS [0 1 2]`（`settings.glsl:60`）。
- **水下雾**：`isEyeInWater` 分支把总密度乘 TAU、垂直密度乘 0.2（`fogRender.glsl:14-19`）。

### 阴影与光照
- **彩色阴影**：shadowtex0（全）→ shadowtex1（不透明）→ shadowcolor0 三级采样（`lib/lighting/shdMapping.glsl:21-35`）。
- **软阴影**：随机角旋转的 1-2 样本 PCF，TAA 开启时靠时间累积（`shdMapping.glsl:40-47`）；shadowDistance 128、实体阴影减半（`shdMapping.glsl:6-8`）。
- **法线偏置**：用 NLX/NLY/NLZ 三个点积构造偏置向量（`lib/lighting/complexShadingForward.glsl:66-74`）。
- **洞穴光泄漏修复**：`shdFactor *= min(1, (lmCoord.y + eyeBrightFact) * 4)`（`complexShadingForward.glsl:96-98`）。
- **SSS 近似**：材质标量 `material.ss` 混入背光方向漫射（`complexShadingForward.glsl:113-116`）。
- **SSAO**：4 样本视空间偏移 + 黄金比例抖动 swizzle（`lib/lighting/SSAO.glsl:15-25`），deferred1 里再做 2x2 box blur（`deferred1.glsl:179-189,303-306`）。
- **雨天阴影软化**：阴影随雨衰减 50% 并用天光补偿（`complexShadingForward.glsl:120-126`）。
- **方向光照贴图**：dFdx/dFdy 重建 lightmap 方向（`complexShadingForward.glsl:14-19`）。
- **积分 PBR**：从 albedo 自动生成坡度法线（`lib/PBR/integratedPBR.glsl:19-39`），亦可走 LabPBR 资源；雨湿响应 `enviroPBR`（`gbuffers_water.glsl:291-293`）。
- **方块光色温**：BLOCKLIGHT_R/G/B/I 可调（`settings.glsl:172-177`）。

### 后处理
- 管线（各文件 `:14` 头注释）：composite0 透明+VL → composite1 TAA → composite2 动态模糊 → composite3 DOF → composite4/5 两级 bloom → composite6 镜头光晕/自动曝光/tonemap/vignette/对比度饱和度 → composite7 FXAA → final 锐化/色差/复古滤镜。
- **TAA**：十字 5 邻域 AABB clamp + 0.1/0.9 时间混合（`lib/antialiasing/taa.glsl:14-21`）；抖动为 8 帧黄金比例序列 `frameMod * 0.20225425`（`shaders.properties:455-458`）。
- **自动曝光**：取屏幕中心 lod8 亮度，与上帧值做帧率无关的指数平滑，存进 colortex5 alpha 通道（`main/composite6.glsl:168-185`）。
- **Tonemap**：修改版 Reinhard extended（白点/肩部可调，`lib/post/tonemap.glsl:22-26`，参数 `settings.glsl:37-38`），后接对比度/饱和度（`composite6.glsl:199-200`）。
- **Bloom**：5 个尺寸递减 tile 求和，按 tonemap 前亮度加权叠加（`composite6.glsl:140-151`）。

### 维度特化
- 下界：无 WORLD_LIGHT、无云无天气、`WORLD_CUSTOM_SKYLIGHT 1.00`、使用原版雾色（`world-1/world.glsl:12-35`）。
- 末地：`WORLD_SUN_MOON 2` 切换为黑洞天空——`blackHole` 距离场 + `rot2D` 引力扭曲 + noisetex 吸积环（`skyRender.glsl:282-295`，`world1/world.glsl:12`）。
- 菜单按维度分组调色（`shaders.properties:145-195`）。

### 性能与时域
- **自定义 uniform 表达式**：几乎全部时域量在 `shaders.properties` 里预算——`dayCycle = 1 + sin(sunAngle*2π)`、`twilightPhase`（smoothstep）、`shdFade` 等（`shaders.properties:439-446`）；biome 感知的降雨 `isPrecipitationRain`（`:449`）。
- **TIMELAPSE_MODE**：动画时钟可在 `frameTimeCounter` 与平滑世界时间 `smooth(worldTime/24, 30)` 间切换，顶点/片段级独立配置（`shaders.properties:390-405`，开关 `settings.glsl:106`）。
- 云在反射中共用同一函数、VL 常量步数、profile 预设分级（`shaders.properties:2-6`）。
- 模组兼容：Distant Horizons 专用着色路径、Physics Mod 重制海浪（`settings.glsl:188-202`）。

## ③ Astra 可借鉴点

1. **岸边泡沫 + 深度风格化吸收（低成本高辨识度）**
   - 技术描述：用水的 gl_FragCoord.z 与 depthtex1（无水场景深度）线性化差值得到水层厚度，一条 `exp2` 曲线同时压暗水色与 alpha；同一边缘值直接加亮为泡沫线。
   - 包内出处：`main/gbuffers/gbuffers_water.glsl:248-282`。
   - 对应 Astra 模块：`Astra/shaders/global/water/absorption.glsl`、`Astra/shaders/lib/solas_water.glsl`（现有吸收偏 Solas 物理派）。
   - 迁移难点：低。Astra 水在 deferred 管线拿 depth 差更容易；主要风险是与现有 Solas 吸收叠加过暗，需并入现有吸收曲线而非并列相乘。
2. **雨天光照响应包（阴影衰减 + 天光补偿 + 雾加密）**
   - 技术描述：雨强直接进阴影项（衰减 50% 并以天光×ambient 补偿，避免雨天死黑）、雾垂直/总密度随雨改写、天空光斑与 VL 随雨淡出。
   - 包内出处：`lib/lighting/complexShadingForward.glsl:120-126`、`lib/atmospherics/fogRender.glsl:14-19`、`skyRender.glsl:273-279`。
   - 对应 Astra 模块：`Astra/shaders/global/atmosphere/weather.glsl`、`Astra/shaders/global/lighting/shadowmap.glsl`、`Astra/shaders/global/lighting/diffuse.glsl`。
   - 迁移难点：低-中。机制 Astra 大概率已有雏形（weather.glsl 存在），借鉴点在于「阴影衰减必配天光补偿」这个防死黑配对，以及雾密度三处联动的一致性。
3. **日/夜/暮三关键帧调色系统（可菜单调节）**
   - 技术描述：光照色与天空色各设日/夜/暮三组 RGB×强度关键帧，按 dayCycle/twilightPhase（properties 里预算的 smoothstep）插值；玩家可在菜单里逐通道微调。
   - 包内出处：`world0/world.glsl:49-101`（插值宏 `:95-101`）、`shaders.properties:145-174`。
   - 对应 Astra 模块：`Astra/shaders/global/post/grading.glsl`、`Astra/shaders/lib/colors.glsl`、`Astra/shaders/lib/twilight.glsl`。
   - 迁移难点：中。Astra 是物理天空（sky_gradient + SH9），整体替换会破坏物理一致性；建议只作为「艺术覆盖/微调层」叠加在物理解之上，而非替换。
4. **TIMELAPSE_MODE：动画时钟与世界时间解耦**
   - 技术描述：用 Iris 自定义 uniform 表达式 `smooth(worldTime/24, 30)` 生成平滑世界时间时钟，顶点（植被/水波）与片段（水法线/天空）可分别选择帧时钟或世界时钟，延时摄影时动画不闪烁。
   - 包内出处：`shaders.properties:390-405`。
   - 对应 Astra 模块：`Astra/shaders/lib/uniforms.glsl`、`Astra/shaders/global/lighting/wind.glsl`、`Astra/shaders/lib/solas_water.glsl`（当前用 frameTimeCounter）。
   - 迁移难点：低。纯 properties 侧表达式，不动 GLSL；需确认 Astra 目标 Iris 版本支持 `uniform.float` 的 `smooth()` 表达式。
5. **shadow pass 内焦散（把焦散成本摊进 shadowmap 彩色通道）**
   - 技术描述：焦散不是屏幕空间后处理，而是在 shadow fragment 里用流动噪声平方调制后写入 shadowcolor0，水下方块着色时随彩色阴影一起采样，一次采样同时拿到「彩色透明物阴影+焦散」。
   - 包内出处：`main/shadow/shadow.glsl:164-177`、`lib/surface/water.glsl:1-9`。
   - 对应 Astra 模块：`Astra/shaders/global/water/caustics.glsl`（现为 Solas 派生解析焦散）、`Astra/shaders/global/lighting/shadowmap.glsl`。
   - 迁移难点：中。Astra 已有解析焦散（质量更高），SDV 方案价值在「焦散只在水下+有阴影时出现」的耦合方式更省；若 Astra 焦散开销敏感可作低配档。
6. **单像素 lod8 自动曝光（极便宜的全局曝光估计）**
   - 技术描述：`textureLod(colortex4, vec2(0.5), 8)` 取中心区域低通亮度，与历史值做帧率无关混合，历史存于 colortex5.a，无 mipmap 链依赖之外的开销。
   - 包内出处：`main/composite6.glsl:168-185`。
   - 对应 Astra 模块：`Astra/shaders/global/post/exposure.glsl` 与 `Astra/shaders/exposure.fsh`（存在但实现未读，见④）。
   - 迁移难点：低（若 Astra 无自动曝光）或零（若已有）。先核对 Astra 现状再定。
7. **积分 PBR：albedo 自动法线/材质（大特性，长线）**
   - 技术描述：无资源包法线时，对 albedo 做小邻域亮度差分生成坡度法线，配合 LabPBR 检测自动降级；另配方向光照贴图增强面片感。
   - 包内出处：`lib/PBR/integratedPBR.glsl:19-39`、`lib/lighting/complexShadingForward.glsl:14-19`。
   - 对应 Astra 模块：`Astra/shaders/lib/rock_material.glsl`、`Astra/shaders/lib/ao_material.glsl`（材质系统）。
   - 迁移难点：高。涉及 gbuffers 全链路与材质编码，属独立立项而非借鉴点内可完成。
8. **CLOUD_TYPE 2 视差云作为性能档/远景区**
   - 技术描述：256x256 云图 + 垂直 raymarch 的准体积云，无历史缓冲、无 3D 噪声，总代码 <60 行；雨时自动压暗。
   - 包内出处：`lib/rayTracing/volumetricClouds.glsl:7-57`、`lib/atmospherics/skyRender.glsl:20-36`。
   - 对应 Astra 模块：`Astra/shaders/global/atmosphere/clouds_planar.glsl` + `Astra/shaders/program/cloud_screen.fsh`（半分辨率+独立时域，见④）。
   - 迁移难点：中。不是替换而是可加「云质量档位」：低档用云图视差、高档用现有平面云；需新增云图资源与采样路径。

## ④ Astra 已有对应实现（对照与优劣）

| 主题 | SDV 做法 | Astra 对应 | 对比结论 |
|---|---|---|---|
| 云 | 云图视差/准体积，无时域，天气直接改权重（②-大气/云） | `Astra/shaders/global/atmosphere/clouds_planar.glsl`（412 行）+ `program/cloud_screen.fsh` 半分辨率渲染 + `global/atmosphere/cloud_temporal.glsl` 独立时域历史（colortex24/25，注释明确与反射板/云影缓存不共享历史） | Astra 分辨率感与时域稳定性优；SDV 胜在开销极低、天气响应一行代码级。Astra 若要低配档可借③-8 |
| 水面波与法线 | noisetex 高度差分（`lib/surface/water.glsl:12-24`） | `Astra/shaders/lib/solas_water.glsl`（Solas V2.2b 改编，文件头注明来源与许可交接）+ `global/water/caustics.glsl` 同源 | Astra 的多层噪声法线更细腻；SDV 更便宜但观感平淡，不建议反向借鉴 |
| 水下表现 | shadowmap 焦散 + exp2 吸收（②-水体） | `Astra/shaders/global/water/` 下 absorption/caustics/refraction/raytrace/light_shafts 全套（`raytrace.glsl` 文件头注明为 Astra 原创实现，未纳入外部源码） | Astra 完整度显著更高；可借鉴的只有③-1 泡沫与③-5 焦散耦合方式 |
| SSR | 20 步+2 步二分，假 SSR 兜底（②-水体） | `Astra/shaders/global/water/raytrace.glsl`（114 行，texture-gather 投影语义） | Astra 更精细；SDV 的「失手回落天空反射」与「远平面投影兜底」思路通用，Astra 是否已有等效兜底未逐行核实（不确定） |
| 彩色阴影 | shadowtex0/1+shadowcolor0 三采样（`shdMapping.glsl:21-35`） | `Astra/shaders/global/lighting/shadowmap.glsl`（Steadfast 0.8.0 派生，GPLv3+第 7 条，文件头注明） | 两边都有；Astra 附带 GPLv3 来源约束，混入 SDV 代码会与⑤冲突，只能思想级借鉴 |
| 天空/暮色 | 三关键帧插值 + vanilla fog 混合（②-大气） | `Astra/shaders/global/atmosphere/sky_gradient.glsl`（289 行物理渐变）+ `lib/sky_sh9.glsl` SH9 方向性天光 | 取向不同：SDV 是艺术可控性，Astra 是物理一致性；只建议③-3 的覆盖层形态 |
| 末地黑洞 | 20 行 noisetex 吸积环（`skyRender.glsl:280-296`） | `Astra/shaders/global/dimension/end_blackhole.glsl`、`end_kerr.glsl`、`end_disc_profile.glsl` 等 8 个文件（Kerr 黑洞+黑体辐射，`end_blackhole.glsl` 头注明原创） | Astra 数量级领先，无可借鉴 |
| 雾 | 解析高度雾+边界雾+雨响应（②-大气） | `Astra/shaders/global/atmosphere/fog.glsl`、`volume_fog.glsl`（可选射线步进体积雾） | Astra 更重更物理；SDV 的「密度三处联动（雾/VL/反射假 VL）保持观感一致」值得校对 |
| TAA | 21 行：5 邻域 AABB + 0.1/0.9（`taa.glsl`） | `Astra/shaders/lib/taa_state.glsl`、`taa_reactive.glsl`、`program/taa_resolve.fsh`（分状态+反应式） | Astra 明显更先进；仅 8 帧黄金比例抖动序列（③外，`shaders.properties:455-458`）可对比 Astra 现有 jitter 序列 |
| 自动曝光 | 单像素 lod8+时域平滑（`composite6.glsl:168-185`） | `Astra/shaders/global/post/exposure.glsl`、`Astra/shaders/exposure.fsh` 存在，但本次未读其实现 | **不确定**：无法断言 Astra 是否已有自动曝光或是否时域稳定，采纳③-6 前必须先读这两个文件 |
| 色调映射 | Reinhard extended+对比度/饱和度（②-后处理） | `Astra/shaders/lib/tonemap.glsl`（Mellow v3.4/MIT 通道，Uchimura/AGX/ACES vendored 并附许可） | Astra 算子库更现代；SDV 的「白点/肩部直接暴露给玩家」的参数化思路可给 grading 菜单参考 |
| 方块光色温 | BLOCKLIGHT_R/G/B/I 菜单可调（`settings.glsl:172-177`） | `Astra/shaders/global/lighting/blocklight.glsl` 存在，实现未读 | **不确定**是否已有等效可调项 |

## ⑤ 借鉴可行性（许可证层面）

- **结论：不能逐行复制后再以 Astra 现行方式分发，除非接受 FlameRender 许可的全部再绑定条款。**
  - 该许可允许发布「修改版」，但要求修改版整体改用 FlameRender 许可、改名、附版权声明并显著署名（`LICENSE:31-35`）。Astra 若整体转为此许可，将与其现有第三方组成冲突——尤其是 Steadfast 派生的 GPLv3 代码（`Astra/shaders/global/lighting/shadowmap.glsl`），GPLv3 代码无法并入专有许可的修改版。
  - 仅改数值/设置不构成「修改版」（`LICENSE:19`），意味着照抄参数表发布同样受限。
- **安全路径**：借鉴「思想、公式、参数范围」并独立重写实现（版权保护表达，不保护思想/算法）；短小行业通用公式（Reinhard 变体、`exp2(-exp2())` 边界雾、StackExchange 高度雾）重写风险极低；云图/噪声贴图资源（`textures/clouds.png`、`noise.png`）同样受许可约束，不得直接拷贝，需自制等效资源。
- 若统帅希望实际移植某段代码（而非重写），需先决策接受 1.4 条款或联系作者授权；建议把该决策记入 Astra 的 THIRD-PARTY 流程。

## ⑥ Top5 优先建议（按 提升/工作量 排序）

1. **岸边泡沫 + 深度风格化吸收**（③-1）：工作量小、观感提升立竿见影，且 Astra 管线拿深度差比 SDV 更容易。
2. **雨天光照响应包**（③-2）：阴影衰减+天光补偿+雾密度联动的成套配方，直接提升雨天氛围且防死黑，改动集中在 2-3 个 Astra 文件。
3. **TIMELAPSE_MODE 世界时间时钟**（③-4）：纯 properties 侧小改动，为延时摄影/录屏用户消除动画闪烁，几乎零风险。
4. **云质量低档：云图视差云**（③-8）：为低配用户提供 SDV 级 <60 行云，保留高档现有平面云；需自制云图资源以规避许可。
5. **三关键帧暮色/夜色微调覆盖层 + 菜单参数化**（③-3 + 白点/肩部参数化思路）：工作量中等，但把「观感调校」从改代码变成拖滑条，长期收益大；须以不破坏物理天空为前提叠加。

（自动曝光③-6 未入 Top5：Astra 现状不确定，应先核对 `global/post/exposure.glsl` 再决定是否立项。）
