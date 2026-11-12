# Glimmer Shaders 调研报告（面向 Astra）

引用约定：`P:x` = `reference_shaderpacks/glimmer-shaders/` 下相对路径；`A:x` = `Astra/shaders/` 下相对路径。所有行号在成稿时已打开源文件核对（见附录）。

---

## ① 包概览

| 项 | 内容 |
|---|---|
| 名称 | Glimmer Shaders（`P:shaders/lang/en_US.lang:1`） |
| 版本 | 任务书标称 v1.5.2。**包内无显式版本号**：`P:shaders/lib/version.glsl` 全文仅 `#version 430 compatibility`，lang 中亦无版本字符串。按任务书口径记为 v1.5.2，行号以本地解压副本为准 |
| 作者 | Josh Britain (jbritain)，jbritain.net（`P:LICENSE:3`；`P:shaders/lang/en_US.lang:3-4,7`；各 lib 文件头署名） |
| 许可证 | MIT（`P:LICENSE:1`，版权行 `:3`，保留声明条款 `:12-13`）。另有第三方资产：tonyMcMapface 3D LUT（`P:shaders/textures/tonyMcMapface.bin`）及其 MIT 许可文件 `P:shaders/textures/LICENSE-MIT_tony_mc_mapface` |
| 风格定位 | 任务书转述包描述"简单、高性能、仍然物理正确"。包内证据一致：四档 profile potato/toaster/igpu/dgpu（`P:shaders/shaders.properties:55-58`）、核心 glsl 合计约 7800 行、强依赖 Iris 高级特性（`P:shaders/shaders.properties:11` `iris.features.required=CUSTOM_IMAGES SSBO SEPARATE_HARDWARE_SAMPLERS BLOCK_EMISSION_ATTRIBUTE HIGHER_SHADOWCOLOR`）、Hillaire LUT 大气 + 前向 PBR 地形（`P:shaders/program/gbuffers_main.glsl`）、原生支持 DH/Voxy 远景与三维度全覆盖 |

**管线一图**：`shadow`（含 FLOODFILL 体素化）→ `setup/prepare` 系 compute（4 张大气 LUT + SSBO 光色）→ 前向 gbuffers 直接出着色结果（colortex0）→ c1/c2 散射频带与 godrays → c3 半透明合成（折射/SSR/水雾）→ c4 雾 → c48-c51 亮度/曝光/动态模糊 → c80-c88 bloom → c89 时域滤波 → c90 FXAA → final。所有 world 程序均为薄壳转发共享源（`P:shaders/world0/composite3.fsh:1-5` → `P:shaders/program/c3_translucents.glsl`），与 Astra 的 `program/lit.fsh` 模式同构。

---

## ② 架构与特性清单

### 大气与云
- Hillaire《Production Sky Rendering》四 LUT：sunTransmittance 256×64、multipleScattering 32×32、skyView 200×200、aerialPerspective 32³（`P:shaders/shaders.properties:13-16`）；生成程序 `P:shaders/program/setup.csh:16-57`（透射 LUT）、`P:shaders/program/setup1.csh:16-60`（多重散射 LUT）、`P:shaders/program/prepare.glsl:17-130`（skyView LUT，32 步）、`P:shaders/program/prepare3.glsl:19-122`（AP 3D LUT）
- 大气常量表（太阳/月亮角半径 0.2°/1°、辐照度 126e3×1e-6、瑞利/米氏/臭氧系数，单位兆米）：`P:shaders/lib/atmosphere/sky/hillaireCommon.glsl:13-42,44-62`
- 天空采样：LUT 查询 + 日盘遮挡透射 + IGN 抗色带 + 洞穴压暗（`P:shaders/lib/atmosphere/sky/sky.glsl:11-39,60-108`；抗色带 `:100-103`）；末地解析天空 `:53-58`
- 2D 平面云：16 八度 fBm + curl 扰动（`P:shaders/lib/atmosphere/clouds.glsl:21-35,67-120`）、双 HG 多重散射 + powder（`:41-65,163-173`）、解析透过率积分（`:175-184`）、闪电照亮（`:186-188`）、ANIME_CLOUDS 海报化（`:190-199`）
- 云影：单平面密度 × 斜线路径长（`P:shaders/lib/atmosphere/clouds.glsl:122-135`）
- 解析高度雾：视线与上/中/下三水平面求交，路径长 × 端点平均密度闭式求光学深度（`P:shaders/lib/atmosphere/fog.glsl:36-45,76-151`）；晨雾时间窗 `:48-54`；AP LUT 应用 `:20-27`
- 天空积分光色 SSBO：skylightColor 由 8×8 球面方向积分（`P:shaders/program/prepare2.glsl:26-45`），sunlightColor 从透射 LUT 取值并做日月切换淡出（`P:shaders/program/prepare.glsl:132-156`）；雨天变体（`P:shaders/lib/common.glsl:78-79`）
- sunVisibilitySmooth 单 float SSBO（雾/水雾/godrays 共享降级）：`P:shaders/program/c4_fog.glsl:23-53`

### 水体
- afl_ext《Very fast procedural ocean》波形法线：16 八度正弦变形波，纯解析无纹理（`P:shaders/lib/water/waveNormals.glsl:4-6,14-98`）
- 水面视差：8 步行进 + 内嵌二分细化（`P:shaders/lib/water/waterParallax.glsl:35-46`）
- 无限海平面：视线与 SEA_LEVEL 求交伪造远海（`P:shaders/program/c3_translucents.glsl:82-104`；雾通道 `P:shaders/program/c4_fog.glsl:101-111`）
- 折射：Snell + 全内反射检测 + 折射点深度回读（`P:shaders/program/c3_translucents.glsl:147-199`）
- DH 地形水遮挡伪阴影：水面到河床斜程算透射进水雾（`P:shaders/program/c3_translucents.glsl:212-236`）
- SSR + miss 回退"天空+云+带阴影耀光"（`P:shaders/lib/util/screenSpaceRayTrace.glsl:43-132`；`P:shaders/program/c3_translucents.glsl:253-405`）
- 水雾：σa+σs 合成 extinction，HG 散射，`color*T + scatter*(1-T)`（`P:shaders/lib/water/waterFog.glsl:18-50`）
- 雨天积水：噪声 + 坡度 + 天光门 + labPBR 孔隙度（`P:shaders/lib/water/puddles.glsl:9-45`）
- 焦散：caustics 贴图双通道 min，按 blocker 距离偏移采样（`P:shaders/lib/lighting/shadows.glsl:41-51,155-167`）

### 阴影与光照
- 彩色阴影：shadowtex0/1 双查 + shadowcolor0 pow2.2（`P:shaders/lib/lighting/shadows.glsl:22-39`）；防漏光格心量化 `:98-102`；距离淡出 pow5 + 天光 fakeShadow 兜底 `:76,111-115,174`；Vogel 盘 PCF `:146-152`（盘采样 `P:shaders/lib/common/util.glsl:112-119`）
- SSS：blocker search + albedo/√luminance 归一化透射（`P:shaders/lib/lighting/shadows.glsl:126-143`）
- Decima 面积光太阳：`getNoHSquared` + `areaLightNormalization`（`P:shaders/lib/lighting/brdf.glsl:21-73,146-153,180-187`）
- 金属菲涅尔：8 种金属 n,k 表 + 解析 F(NoV)（`P:shaders/lib/common/material.glsl:19-62`；`P:shaders/lib/lighting/brdf.glsl:91-104`）
- 方向光照贴图：屏幕空间导数修正 lightmap（`P:shaders/lib/lighting/directionalLightmap.glsl:19-69`）
- FLOODFILL 主世界体素彩光：256×128×256 R32UI 体素图 + 双缓冲 RGBA16F 光图 Jacobi 迭代（`P:shaders/shaders.properties:19-24`；`P:shaders/program/shadowcomp.csh:15-73`）；前向乒乓读取（`P:shaders/program/gbuffers_main.glsl:356-404`）
- 彩色方块光颜色表（注明来源 Complementary by Emin）：`P:shaders/lib/ipbr/blocklightColors.glsl:4-41`
- 手持光：lightmap 抬升兜底（`P:shaders/program/gbuffers_main.glsl:309-326`）、体素光加法（`:373-392`）、SSBO atomicMax 编码（`:224-227`，`P:shaders/lib/common.glsl:70`，仅见写入未见读取）
- 阴影空间：cubeLength 畸变 + 法线相关 bias（`P:shaders/lib/shadowSpace.glsl:30-36,58-69`）

### 后处理
- Bloom：COD:AW 五瓦片式，13-tap 降采样 + Karis 平均，3×3 升采样（`P:shaders/lib/post/bloom.glsl:18-37,39-67,69-147`；瓦片混合 `P:shaders/shaders.properties:168-171`）
- 自动曝光：亮度写入 colortex0.alpha（`P:shaders/program/c48_writeLuminance.glsl:35-41`），mip 顶层取均值 + SSBO 平滑（`P:shaders/program/c49_computeAutoExposure.glsl:36-51`），昼夜目标 + 简化 Purkinje（`P:shaders/program/c50_applyAutoExposure.glsl:42-70`）
- tonemap 七选一（AgX/Lottes/tonyMcMapface 3D LUT 等；3D 纹理挂载 `P:shaders/shaders.properties:28`）：`P:shaders/lib/post/tonemap.glsl:4-175`
- 对比度/饱和度矩阵（`P:shaders/lib/post/processing.glsl:6-49`）；FXAA 可调（`P:shaders/lib/post/FXAA.glsl`）
- 时域滤波：重投影 + 8 邻域 clamp + 0.7 混合（`P:shaders/program/c89_temporalFilter.glsl:37-90`）；TAA R2 抖动（`P:shaders/lib/TAA.glsl:5-11`）
- godrays 两档：屏幕空间径向 march / 影图空间体积 march（`P:shaders/program/c2_godrays.glsl:43-139`）；频带可见性门 `P:shaders/program/c1_godraysVisibility.glsl:39-49`

### 维度特化
- 三维度全为薄壳 + 共享 program（`P:shaders/world0/composite3.fsh:1-5`）
- 下界：无阴影直返（`P:shaders/lib/lighting/shadows.glsl:72-74`）、环境 ×4（`P:shaders/lib/lighting/shading.glsl:57-59`）、天空退化 fogColor 混合（`P:shaders/lib/atmosphere/sky/sky.glsl:61-65`）；末地：光色硬编码（`P:shaders/program/prepare.glsl:78-82`）、天光 lightmap=1（`P:shaders/program/gbuffers_main.glsl:202-204`）
- 末地折跃门：5 层平面噪声扫掠 + 时间滑窗（`P:shaders/lib/endPortal.glsl:5-53`）
- DH/Voxy：统一深度（`P:shaders/program/c0_combinedDepth.glsl:38-55`）、dhOverride（`P:shaders/lib/dh.glsl:23-43`）、远景 dither 淡化（`P:shaders/lib/dhBlend.glsl:35-54`）、DH 专用蓝噪声 AO（`P:shaders/program/d1_dhAo.glsl:42-99`）、远景噪声破重复（`P:shaders/program/gbuffers_distant.glsl:92-108`）、统一投影矩阵（SixthSurge 方案，`P:shaders/shaders.properties:180-205`）、Voxy 顶点发射（`P:shaders/program/gbuffers_voxy.glsl:19-46`）

### 性能与时域
- profile 熔断 + program.enabled 条件编译（`P:shaders/shaders.properties:55-58,87-171`）
- SSBO ×3（光色/天气计时/手持光 40B、sunVisibilitySmooth 4B、曝光 4B）：`P:shaders/shaders.properties:31-38`；定制贴图 `:26-29`
- 随机化三件套：IGN 帧偏移（`P:shaders/lib/common/util.glsl:10-16`）、蓝噪声 R2 滚动（`:133-151`）、快速 fsqrt/facos（`:123-131`）
- colortex0 不清空保留 mipmap（`P:shaders/lib/common.glsl:96`）；colortex7 天空球 512×512（`P:shaders/shaders.properties:173`）

### 材质与表面
- labPBR 解码：粗糙度平方、f0/金属 ID 229 分界、孔隙度/SSS 0.25 分界（`P:shaders/lib/common/material.glsl:88-125`）；水材质常量 `:76-86`
- POM：贴图集子区包裹 + 距离淡出层数 + 6 步二分 + POM 阴影（`P:shaders/lib/parallax.glsl:64-168`）
- 植被摇摆六分类 + 玩家推开（`P:shaders/lib/sway.glsl:80-113`）；花斑熔岩（`P:shaders/program/gbuffers_main.glsl:229-243`）；像素锁定光照（`P:shaders/lib/common/settings.glsl:48-49`；`P:shaders/lib/lighting/shadows.glsl:55-59`）
- IPBR：`at_midBlock.w` 块发光属性兜底自发光（`P:shaders/shaders.properties:11`；`P:shaders/program/gbuffers_main.glsl:49,259-266`）

---

## ③ Astra 可借鉴点

共 14 条。每条四要素 = 技术要点 / 本包出处(`P:`) / Astra 对应模块(`A:`) / 迁移难点与工作量。与批次一重复的主题在条末标注。

**1. Decima 面积光太阳高光（球面光源解析 GGX）**
- 技术要点：太阳按 0.2° 球面光源处理，`getNoHSquared` 解析求球面光源下 NdotH²，乘 `areaLightNormalization`，高光随粗糙度摊开且能量守恒，无采样成本。
- 出处：`P:shaders/lib/lighting/brdf.glsl:21-65,68-73,146-153,180-187`（算法 credit Decima GDC 2017，`:20`）
- Astra 对应：`A:global/lighting/diffuse.glsl:120-165`（direct_lighting 为漫反射曲线，无镜面项；水面高光在 `A:global/water/surface.glsl:23` 的表面参数链路内）
- 难点与工作量：**中**。需给 direct_lighting 增加 L/V/H 输入和高光支路；湿面（`A:lib/wet_material.glsl:23-28` 的 gloss 为外加项）可统一进 BRDF。数学可独立重写。

**2. 天空球 mip 金字塔粗糙度分级反射**
- 技术要点：prepare 阶段把"天空+云+雾"烘到球面贴图并开 mipmap，前向按 `log2(1+roughness*(mipCount-1))` 取层，配合 fresnelRoughness 做 `mix(diffuse, specular, fresnel)`。
- 出处：`P:shaders/program/prepare1.glsl:39-48`（烘制）、`P:shaders/lib/lighting/shading.glsl:83-101`（取层与混合）、`P:shaders/lib/common.glsl:122-127`（colortex7 mipmap）
- Astra 对应：`A:lib/sky_reflection_cache.glsl:22-32`（已有 256×128 缓存但只 `textureLod(...,0.0)` 单层）
- 难点与工作量：**低-中**。缓存已在，只需开 mip + 按 roughness 取层 + 给 lit 链路加环境镜面出口。
- （与批次一"天空缓存增烘"主题相邻，本条新增的是 mip 粗糙度分级机制）

**3. afl_ext 解析海浪波形法线（零纹理低配档）**
- 技术要点：16 八度变形正弦波直接给出高度导数，交叉积得世界法线，可按掠射角衰减；不依赖噪声贴图，约百行。
- 出处：`P:shaders/lib/water/waveNormals.glsl:8-98`
- Astra 对应：`A:global/water/caustics.glsl:3-23`、`A:global/water/surface.glsl:65,315-336`（现走 Solas 噪声纹理波场 + 足迹滤波）
- 难点与工作量：**低**。作 WATER_EFFECT_QUALITY=0 替代波源或 Voxy 远景水面兜底；需适配 rotate-to-face-normal（`P:shaders/lib/water/waveNormals.glsl:96`）。

**4. colortex0.alpha 亮度 mip 链自动曝光（低配档）**
- 技术要点：合成前把 luminance 写进 colortex0.alpha，mip 最顶层即全屏均值，SSBO 做指数平滑；比专用 metering pass 省。
- 出处：`P:shaders/program/c48_writeLuminance.glsl:35-41`、`P:shaders/program/c49_computeAutoExposure.glsl:36-51`、`P:shaders/program/c50_applyAutoExposure.glsl:42-70`
- Astra 对应：`A:global/post/exposure.glsl:82-99`（加权网格 metering）+ `A:global/post/exposure.glsl:105-141`（历史帧）
- 难点与工作量：**低**。作低配档变体；需补 Astra 网格版已有的地板/钳制/NaN 防护。
- （与批次一"复杂自动曝光"主题相邻，本条是其极省变体）

**5. sunVisibilitySmooth 单值 SSBO（跨效果共享太阳可见度）**
- 技术要点：每帧 1×1 compute 对太阳屏幕点查一次深度（或影图），指数平滑成 sunVisibilitySmooth；水雾、云雾、godrays、SSR 天空回退全用它降级。
- 出处：`P:shaders/program/c4_fog.glsl:23-53`、`P:shaders/lib/water/waterFog.glsl:42-44`、`P:shaders/program/c3_translucents.glsl:228-234`
- Astra 对应：`A:lib/solas_water.glsl:16`（solas_sun_visibility 现为各处即时计算）
- 难点与工作量：**低**。Astra 已有 effect 历史缓冲习惯（`A:lib/effect_history.glsl:17-40`），加一个 1×1 状态即可。

**6. 解析高度雾"平面夹逼 + 端点平均密度"**
- 技术要点：不 raymarch：视线与雾顶/中/底三水平面求交，地形深度截断路径，端点密度均值×路径长闭式求光学深度，上下两段相加；相机高于雾顶提前剔除。
- 出处：`P:shaders/lib/atmosphere/fog.glsl:76-151`（晨雾窗 `:48-59`；剔除 `:72-74`）
- Astra 对应：`A:global/atmosphere/fog.glsl:40-79`（已有山谷雾高度模型与 `fog_morning_air_weight`）
- 难点与工作量：**低**。Astra 解析雾已在，可借鉴的是三平面分段与晨雾/雷暴多源 fogFactor 叠加的整理方式。

**7. 2D 平面云的多重散射 + powder 能量守恒近似**
- 技术要点：平面云只取"视线穿越厚度"与"向日穿越厚度"两个密度积分，双 HG 4-octave 多重散射级数 + powder 项，配合 `(radiance - radiance*T)/σ` 解析积分，每像素仅 2 次密度查询即能量守恒。
- 出处：`P:shaders/lib/atmosphere/clouds.glsl:41-65,137-205`（`:149` IGN 抖动、`:165-173` powder、`:180-184` 解析积分）
- Astra 对应：`A:global/atmosphere/clouds_planar.glsl:116,204-320`（interval 追踪 + IGN 抖动）
- 难点与工作量：**中**。Astra 云已是半分辨率 + 时域历史方案；本条价值在"两次密度查询出守恒光照"的低档形态（CLOUD_QUALITY=0），以及云影与云体严格共用 `getCloudDensity` 的同源性。
- （多重散射主题与批次一"体积云多重散射能量估计（储备）"相邻，本条降到平面云低配档）

**8. 无限海平面（SEA_LEVEL 平面延展）**
- 技术要点：深度为远平面的像素向 SEA_LEVEL 求交，命中则当水面处理（法线置 up、albedo 清零、参与折射/SSR/水雾）；雾通道同样补一段。
- 出处：`P:shaders/program/c3_translucents.glsl:82-104`、`P:shaders/program/c4_fog.glsl:101-111`
- Astra 对应：Astra 无对应实现（`A:global/water/surface.glsl:302-303` 只处理真实水面几何）
- 难点与工作量：**中**。hit 后需伪造"水表面数据"供 `A:global/water/refraction.glsl:14-25` 与 raytrace 复用；观感收益大但易与 FANCY_TRANSLUCENTS 冲突，建议独立开关。

**9. 简化 Purkinje（HSV 蓝移）挂在曝光应用端**
- 技术要点：夜间按太阳高度 + eBS 混合系数，HSV 空间压 G 通道（视觉亮度权重）再转回，一行实现夜视蓝移，与曝光乘法同处。
- 出处：`P:shaders/program/c50_applyAutoExposure.glsl:56-62`
- Astra 对应：`A:global/post/grading.glsl:37`（apply_grading 入口约定）/ `A:lib/tonemap.glsl:4`
- 难点与工作量：**低**。常数与门控可独立重写。
- （与批次一"Purkinje 夜视蓝移"（5 包印证）主题重复）

**10. DH/Voxy 统一投影矩阵 + 远景 dither 淡化 + DH 专用 AO**
- 技术要点：main 与 DH 深度用同一张手工构造的 combined projection（CPU uniforms 拼矩阵）；远景按 `sqrt(clamp((1+far-l)/16))` 不透明度做 IGN/Bayer 随机 discard 与时域自然融合；DH 地形另做蓝噪声半球 AO。
- 出处：`P:shaders/shaders.properties:180-205`、`P:shaders/program/c0_combinedDepth.glsl:38-55`、`P:shaders/lib/dhBlend.glsl:35-54`、`P:shaders/program/d1_dhAo.glsl:64-97`
- Astra 对应：`A:lib/settings.glsl:319-322`（VOXY_SUPPORT 保留开关）、`A:lib/uniforms.glsl:140-144`（bootstrap）、`A:program/lit_voxy.fsh:1-8`（空壳，C5 归口）
- 难点与工作量：**高**。属新能力域；三项技术互相独立，C5 启动时可按序引入（统一深度 → 淡化 → AO）。

**11. 主世界 FLOODFILL 体素彩光（三维度统一）**
- 技术要点：R32UI 体素图存不透明度+发射色，双缓冲 RGBA16F 光图做 0.99 衰减 Jacobi 六邻域迭代；前向按 `frameCounter%2` 乒乓读取，支持方向光照贴图偏移采样与手持光加法。
- 出处：`P:shaders/program/shadowcomp.csh:15-73`、`P:shaders/shaders.properties:19-24,90`、`P:shaders/program/gbuffers_main.glsl:334-404`
- Astra 对应：`A:lib/nether_voxel_grid.glsl:29`（64³ 契约）+ `A:program/nether_light.csh:13-17,48`（传播 compute，双图 astraLightA/B）
- 难点与工作量：**高**。Astra 架构可直接复用（推广 nether_light.csh 调度到主世界，`A:global/lighting/blocklight.glsl:84-101` 的单色 BLOCKLIGHT_COLOR 换为体素 RGB），但显存（256×128×256 双 RGBA16F ≈ 64MB）与每帧 compute 成本需立项评估。
- （与批次一"主世界彩光推广（floodfill 三维度统一）"（5 包印证）主题重复）

**12. 方向光照贴图（屏幕空间导数法）**
- 技术要点：用 `dFdx/dFdy(lightmap)` 反推光照来向，按映射法线与几何法线差修正 lightmap，让 lightmap 突变产生"假方向光"；火把与天光各做一次，SSS 材质减弱。
- 出处：`P:shaders/lib/lighting/directionalLightmap.glsl:19-69`
- Astra 对应：`A:global/lighting/diffuse.glsl:120-175`（前向直射光）、`A:program/lit.fsh:240`（astra_light 调用点）
- 难点与工作量：**低-中**。纯前向、无缓冲依赖；2×2 导数在三角形单元间不连续，需配 IGN 抖动或 TAA。
- （与批次一 SDV 报告中"方向光照贴图"主题重复）

**13. 花斑熔岩 + IPBR 发光启发式**
- 技术要点：熔岩 albedo 乘 perlin 双频乘积造暗斑再靠 EMISSION_STRENGTH 提亮；无 labPBR 资源包时用 `at_midBlock.w` 块发光属性兜底自发光。
- 出处：`P:shaders/program/gbuffers_main.glsl:229-243,259-266`
- Astra 对应：`A:lib/surface_emission.glsl:6`（astra_end_stone_emission）+ `A:program/lit.fsh:240`
- 难点与工作量：**低**。纯 albedo/自发光端改动。
- （IPBR 发光启发式主题与批次一"IPBR 自发光启发式"（2 包印证）重复；花斑熔岩为新增小点）

**14. 天空采样 IGN 抗色带**
- 技术要点：天空 LUT 结果乘 `mix(0.9,1.1,IGN(gl_FragCoord))` 消除 LUT 梯度色带，代价两次乘法；同法用于云抖动、SSR 起步偏移。
- 出处：`P:shaders/lib/atmosphere/sky/sky.glsl:100-103`（模式）；随机源 `P:shaders/lib/common/util.glsl:10-16`
- Astra 对应：`A:lib/dither.glsl:10-12`（ign 已带 animate 帧参数）+ `A:global/atmosphere/sky_gradient.glsl:158`（astra_get_sky 已有 dither 形参）
- 难点与工作量：**低**。仅提示"逐帧变化的 IGN 优于静态抖动"细节。
- （与批次一低差异序列抖动主题（②-1 R2/黄金角条）相邻）

---

## ④ Astra 已有对应实现对照

| 主题 | Glimmer 做法（P:） | Astra 现状（A:） | 差异与评价 |
|---|---|---|---|
| 彩色阴影 | shadowtex0/1 双查 + shadowcolor0 pow2.2，逐样本混合 `P:shaders/lib/lighting/shadows.glsl:22-39` | 硬件 textureGather 一次取 4 角，仅对半透明权重>0 的角回读 shadowcolor0.gba `A:global/lighting/shadowmap.glsl:96-130` | Astra 更省（4 样本一次 gather、彩色回读按需）且逐角保留混合边缘；Glimmer 更平滑但采样贵。误差来源：Astra shadowcolor0 语义为 R=水高 GBA=色调 |
| 防漏光偏置 | 接收点沿法线偏 0.1 后 floor 到格心 `P:shaders/lib/lighting/shadows.glsl:98-102` | 法线相关 normal offset（`A:global/lighting/shadowmap.glsl:150` 注释段起） | 思路等价（偏接收点 vs 偏采样点）；Astra 连续偏移不依赖 block 尺寸假设 |
| 云影 | 每像素即时求交云平面 + 单次密度采样 `P:shaders/lib/atmosphere/clouds.glsl:122-135` | 512 范围缓存图 + 边缘回退实算 + 高度淡出 `A:global/atmosphere/cloud_shadow_cache.glsl:14-37` | Astra 更省（每帧一次区域烘焙）；Glimmer 优点是与云密度天然同帧同源 |
| 水雾/吸收 | σa+σs→extinction，HG 散射，守恒合成 `P:shaders/lib/water/waterFog.glsl:18-50` | 分通道吸收 + 浅水/深水双端色 `A:global/water/absorption.glsl:13-51` | Glimmer 更物理参数化（σa/σs 两旋钮），Astra 更美术可控；守恒两边都成立 |
| 折射 | Snell + 深度回读 + TIR `P:shaders/program/c3_translucents.glsl:147-199` | normalDelta 位移 + textureGather 深度范围校验 `A:global/water/refraction.glsl:8-25` | Astra 更省（位移法 + 双重校验）；Glimmer 的 TIR/水下 Snell 窗是 Astra 缺的观感项（批次一 Snell's window 条已列） |
| 水面 SSR | 步进×4 + 二分 6 步 + DH 深度分支 `P:shaders/lib/util/screenSpaceRayTrace.glsl:43-132` | 粗步+细化两级 + 置信度 + 距离淡出 `A:global/water/raytrace.glsl:61-122` | Astra 有厚度/边缘置信度，质量上限更高；Glimmer 的 miss 回退与批次一 SSR miss 回退条一致 |
| 雨天积水 | perlin + 坡度 + 天光门 + labPBR porosity `P:shaders/lib/water/puddles.glsl:9-45` | 方块类 wet_class + 三参数响应 `A:lib/wet_material.glsl:7-28` | Astra 不依赖 porosity 通道、资源包兼容面广；Glimmer 的 porosity 分支（`:29-34`）是更细的材质语义，可反哺批次一"孔隙度"条 |
| TAA 抖动 | R2 序列 8 帧 `P:shaders/lib/TAA.glsl:5-11` | 中心化 8 样本 Halton(2,3) + 有限周期均值扣除 `A:lib/taa_jitter.glsl:12-21` | 等价物；Astra 多做均值归零，收敛略优 |
| 时域历史 | 重投影 + 8 邻域 clamp + 0.7 混合 `P:shaders/program/c89_temporalFilter.glsl:48-90` | 带有效性检验（分辨率/维度/矩阵/致盲）的历史系统 `A:lib/effect_history.glsl:17-40` | Astra 稳健性更高；Glimmer 仅一层 colortex3，实现极简 |
| 自动曝光 | 亮度进 alpha + mip 链 + SSBO 平滑 `P:shaders/program/c48-c50` | 加权网格 log 域 metering + 编码历史 `A:global/post/exposure.glsl:82-141` | Glimmer 少一个专用 pass 但均值无中心权重、无百分位钳制；Astra 质量更高，低配档可借其形态 |
| 天空辐照→着色光色 | 球面 64 采样积分 skylightColor + TLUT 取 sunlightColor 存 SSBO `P:shaders/program/prepare2.glsl:26-45`、`P:shaders/program/prepare.glsl:132-156` | 9 系 SH9 烘焙 `A:program/sky_irradiance.fsh:19-32` + 方向取用 `A:lib/sky_directional.glsl:12-27` | Astra 保留方向性，Glimmer 只有标量色 + lightmap²，更省但更平。误差来源：Glimmer 辐照度量纲 126e3×1e-6 vs Astra palette 0-1，数值不可直换 |
| 体素彩光 | 256×128×256 双缓冲 Jacobi，全维度 `P:shaders/program/shadowcomp.csh:15-73` | 64³ 下界限定 + 同帧捕获/传播/显示契约 `A:lib/nether_voxel_grid.glsl:19-30` | 同构思想；Glimmer 三维度统一且体积更大，Astra 有意限下界控成本（与批次一 ②-4 结论一致） |
| 晨雾 | worldTime 时间窗 + 雨强叠加 `P:shaders/lib/atmosphere/fog.glsl:47-59` | `fog_morning_air_weight(worldY)` `A:global/atmosphere/fog.glsl:79` | Astra 按高度而非时间驱动；可叠加 |
| tonemap | AgX/ACES/Lottes/tonyMcMapface 七选一 `P:shaders/lib/post/tonemap.glsl:4-175` | Mellow(MIT) 传承的 Uchimura/AgX/ACES 集 `A:lib/tonemap.glsl:4-92` | Astra 已覆盖 AgX/ACES；Glimmer 独有的是 3D LUT 路径 |
| Bloom | 5 瓦片 + Karis `P:shaders/lib/post/bloom.glsl:39-147` | mip 链 capture/resolve + 13-tap 双滤波 `A:global/post/bloom.glsl:7,50,87,155` | Astra 已走 mip 链（批次一 MakeUp 条同款）；Karis 平均是可单独吸收的抗闪烁细节 |
| profile 组织 | 四档 potato→dgpu + program.enabled 熔断 `P:shaders/shaders.properties:55-58,87-171` | PERFORMANCE/NO_SHADOWS/BALANCED/ULTRA 全量枚举 `A:shaders.properties:444-447`；`A:shaders.properties:692` iris.features.optional | Glimmer 按硬件命名档位，沟通成本低；熔断写法两边同构 |
| 金属材质 | labPBR 金属 ID → n,k 表解析菲涅尔 `P:shaders/lib/common/material.glsl:30-62` | 无 specular 贴图采样（材质为风格化字段） | Astra 引入 labPBR 属独立立项；n,k 表为公有物理数据 |

**哪边更省的小结**：缓冲/采样类（彩色阴影、云影、折射、自动曝光、时域）Astra 普遍更省或更稳；光色与光照量纲类（SSBO 天空色、面积光 BRDF）Glimmer 更省。误差来源三：① Glimmer 全 HDR 线性 + 辐照度量纲 vs Astra palette 量纲，常数不可直搬；② Glimmer 逐像素即时计算、Astra 多处走缓存，时序假设不同；③ Glimmer 强制 Iris 高级特性（SSBO/CUSTOM_IMAGES），Astra 需保持 `iris.features.optional` 协商路线（`A:shaders.properties:692`）。

---

## ⑤ 借鉴可行性（许可证层面）

包内许可证原文（`P:LICENSE`，MIT）：
- `:1` `MIT License`
- `:3` `Copyright (c) 2024 Josh Britain (jbritain)`
- `:5-10` 授权任何人免费使用、复制、修改、合并、发布、分发、再许可、销售软件副本
- `:12-13` `The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.`（MIT 对"直接抄代码"的唯一实质义务：保留版权与许可声明）
- `:15-21` 免责声明（AS IS，无担保）

两种情形的风险评估：

1. **读思路后独立重写**：零义务、零风险。MIT 不要求注明灵感来源；按 Astra 既有"思想来源登记纪律"（批次一 ②-7 建议，`A:THIRD-PARTY.md` 台账）在文件头写一行 `// Idea source: Glimmer v1.5.2 (MIT)` 是推荐做法，属项目自律而非许可证义务。
2. **直接抄代码**：允许（含商用、再许可），但**必须在副本或实质性部分中保留 `P:LICENSE:3` 的版权行与本许可声明**（`:12-13`）。落地方式：移植文件头部保留 `Copyright (c) 2024 Josh Britain (jbritain), MIT`，并在 `A:THIRD-PARTY.md` 登记一份 MIT 全文或引用。MIT 与 GPL 兼容（MIT 代码可并入 GPL 项目），因此并入 Astra 现有 GPL-3.0 来源（Steadfast，见 `A:global/lighting/sss.glsl:18-21` 既有注记）无许可证冲突；Astra 真正的发区门槛仍来自 Complementary 专有来源，与 Glimmer 无关。

附加注意点：
- **tonyMcMapface 3D LUT 不是 jbritain 的代码**：`P:shaders/textures/LICENSE-MIT_tony_mc_mapface`（h3r2tic，MIT）。若连 `.bin` 贴图一起搬需同样保留该许可证文件；只抄 `P:shaders/lib/post/tonemap.glsl:160-171` 的采样函数则按普通 MIT 代码处理。
- **afl_ext 海浪**：`P:shaders/lib/water/waveNormals.glsl:4-6` 文件头已注明来源与 MIT，重写或搬运同属 MIT 义务范围。
- Glimmer 文件头普遍自带版权+MIT 声明（如 `P:shaders/lib/lighting/shading.glsl:1-13`），直接搬运时保留文件头即可同时满足 `:12-13`。

结论：Glimmer 是参考包中**许可证风险最低的一类**（对照批次一 ⑤ 的 Complementary/BSL 专有与 Shrimple LGPL 情形），"直接抄"仅剩"保留声明"一项行政义务。

---

## ⑥ Top5 优先建议（按 收益/工作量 排序）+ 暂缓项

1. **Decima 面积光太阳高光**（③-1，中）：给 direct_lighting 加解析高光支路，让晴天岩石/湿面/水面高光的能量与软硬随太阳角径正确，无采样成本——Astra 直射光目前没有这一层。
2. **天空缓存 mip 粗糙度分级**（③-2，低-中）：`A:lib/sky_reflection_cache.glsl` 已有缓存，开 mip + roughness 取层即得全材质廉价环境镜面，是现有资产上收益/成本比最高的一步。
3. **afl_ext 解析海浪低配档**（③-3，低）：约百行、零贴图依赖，补 WATER_EFFECT_QUALITY=0 与未来 Voxy 远景水面两个空位。
4. **sunVisibilitySmooth 单值共享**（③-5，低）：1×1 compute + 一个 float，让水雾/云雾/godrays 在日落、雨天、洞穴行为一致且各省一次判断。
5. **colortex0.a mip 自动曝光低配档**（③-4，低）：复用 bloom 已开的 colortex0 mip 链路，给低配档零额外 pass 的曝光。

暂缓项及理由：
- **主世界 FLOODFILL**（③-11）：64MB 级显存与每帧 compute 属立项级成本，批次一 ②-4 已列长期储备（5 包印证），无需因本包提前。
- **Hillaire LUT 大气全套**：Astra 解析梯度天 + minishita 已成体系，换 LUT 是推翻性改动；批次一 photon 报告已主张该主题，等其单独评审。
- **DH/VOXY 三件套**（③-10）：归口 C5，`A:program/lit_voxy.fsh` 骨架就绪前不动。
- **tonyMcMapface 3D LUT**：photon 批次一已主张，且涉及贴图资产引入流程。
- **方向光照贴图**（③-12）：与 TAA 的交互（导数不连续）需实测，先等 Astra TAA 档位稳定。

---

## 附：自抽查记录（成稿后重新打开源文件逐一核对）

1. `P:LICENSE:3` — 该行为 `Copyright (c) 2024 Josh Britain (jbritain)`，`:12-13` 为保留声明条款。✔
2. `P:shaders/shaders.properties:13-16` — 四张 LUT 的 image 声明（sunTransmittance/multipleScattering/skyView/aerialPerspective）。✔
3. `P:shaders/lib/lighting/brdf.glsl:21-65` — `getNoHSquared` 函数体（Decima 链接在 `:20`）；`:68-73` 为 `areaLightNormalization`。✔
4. `P:shaders/lib/lighting/shadows.glsl:126-143` — blocker search（`blockerDistance`）与 albedo 归一化透射（`exp(-blockerDistance * rcp(material.albedo / max(0.1, sqrt(luminance(...)))))`）在此范围。✔
5. `P:shaders/lib/atmosphere/clouds.glsl:122-135` — `getCloudShadow`（rayPlaneIntersection ×2 + 单次 getCloudDensity）。✔
6. `P:shaders/program/prepare2.glsl:26-45` — skylightColor 的 8×8 球面积分（`SKYLIGHT_SAMPLES 8` 在 `:27`）。✔
7. `P:shaders/program/gbuffers_main.glsl:356-404` — floodfill 分支：`frameCounter % 2` 乒乓读 `:359-363`，手持光加法 `:373-392`，getShadedColor `:394-403`。✔
8. `P:shaders/program/c3_translucents.glsl:82-104` — INFINITE_OCEAN 块（`SEA_LEVEL - cameraPosition.y` 求交、`color.rgb = vec3(0.0)`）。✔
9. `P:shaders/lib/post/tonemap.glsl:158-171` — `uniform sampler3D tonyMcMapfaceTex` 在 `:158`、`LUT_DIMS = 48.0` 在 `:167`。✔
10. `P:shaders/shaders.properties:180-205` — combined projection 段（`:181` 注明 BY SIXTHSURGE，`:186` fov，`:196-199` 四行 mat4）。✔
11. `P:shaders/program/c48_writeLuminance.glsl:35-41` — `color.a = luminance(color.rgb);` 在 `:41`。✔
12. `A:lib/sky_reflection_cache.glsl:22-32` — `astra_cached_reflection_sky` 内 `textureLod(colortex11, vec2(u, v), 0.0)` 固定 LOD 0。✔
13. `A:global/lighting/shadowmap.glsl:101-130` — `shadow_lobe_light`：`:108` allVisibility gather、`:112` opaqueVisibility gather、`:119-129` 逐角 shadowcolor0 回读。✔
14. `A:global/post/exposure.glsl:82-99` — `astra_ae_meter` 起于 `:82`，加权网格 log 域循环 `:84-99`（`float logSum = 0.0` 于 `:84`）。✔
15. `A:lib/wet_material.glsl:7-28` — `astra_wet_class` `:7-12`、`astra_wet_material` `:16-21`、`astra_wet_gloss` `:23-28`（初稿误记 10-15/21-25/28-33，按 grep 结果订正并同步正文）。✔
16. `A:lib/uniforms.glsl:140-144` — VOXY_SUPPORT 菜单元素说明与 `const bool astraVoxyBootstrap`。✔
17. `A:program/lit_voxy.fsh:1-8` — 8 行空壳（`TODO(C5): voxy_emitFragment`）。✔
18. `A:global/lighting/diffuse.glsl:165` — `directLightStrength = smoothstep(-0.05, 0.05, ndotl);`（direct_lighting 入口 `:120` 亦经 grep 确认）。✔
19. `A:lib/sky_directional.glsl:12-27` — `astra_directional_sky_coeffs` 起于 `:12`、`astra_directional_sky` 起于 `:22`（初稿误记 11-27，已订正）。✔
20. `P:shaders/program/shadowcomp.csh:44-45` — `light /= 6.0;` 在 `:44`、`light *= 0.99;` 在 `:45`（初稿 R5 写 45-46，重开核对后订正）。✔

### 五条 P: 行号复现抽查（交付时重开文件执行）

| # | 引用 | 重开核对结果 |
|---|---|---|
| R1 | `P:shaders/lib/lighting/brdf.glsl:68-73` | `areaLightNormalization` 函数体逐行吻合（roughnessSquaredLoH 分式） |
| R2 | `P:shaders/lib/water/waterFog.glsl:42-44` | `#if GODRAYS == 0 / scatter *= sunVisibilitySmooth; / #endif` 逐行吻合 |
| R3 | `P:shaders/program/c50_applyAutoExposure.glsl:56-62` | `// really shitty purkinje` 注释 + hsv/rgb 蓝移三行吻合 |
| R4 | `P:shaders/lib/dhBlend.glsl:35-54` | `dhBlend` 函数体（`opacity = sqrt(clamp((1 + far - l) / 16, 0.0, 1.0))` 在 `:38`）吻合 |
| R5 | `P:shaders/program/shadowcomp.csh:44-45` | `light /= 6.0; light *= 0.99;` 两行吻合（初稿误写 45-46，重开核对后订正） |
