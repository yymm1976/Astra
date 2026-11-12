# Shrimple v0.12 研究报告 — Astra 可借鉴点

> 研究对象：`reference_shaderpacks/shrimple/`（约 697 个 shader 文件）
> 对照目标：`Astra/shaders/`（Iris 专用，前向光照）
> 本文所有 `文件:行` 引用均基于包内相对路径 `shaders/`（Astra 引用基于 `Astra/shaders/`）。

## ① 包概览

- **版本**：v0.12（任务给定；包内 `info/programs.txt`、`info/buffers.txt` 记录程序与缓冲清单）。
- **作者**：Joshua Miller（GitHub: Null-MC），`LICENSE:1-3`。
- **许可证**：**All Rights Reserved**。`LICENSE:1-3` 写明 "All Rights Reserved / Copyright (c) 2023 Joshua Miller"；其后 `LICENSE:5-11` 只是无担保免责声明，**没有任何复制/修改/再分发的授权条款**。readme 未提及代码许可，仅致谢贡献者（`readme.md` Special Thanks 一节，阴影过滤与 dithering 改进由 Tech 协助）。
- **限制**：不可复制源码、贴图（`textures/caustics.dat`、`ripples.dat`、`clouds.dat`、`noise.png`）、lang/properties 文本；只允许借鉴思想与算法，独立实现。
- **风格定位**：readme.md:1-11 自述 "maintain a minimal vanilla aesthetic, while adding some optional features"——原版观感为底、特性全可开关。四档 profile 一键切换：VANILLA（关阴影关体积）/ SHADOWS / LIGHTS（彩色光源）/ RTX（逐光 DDA 追踪）（`shaders.properties:1-4`）。
- **mod 支持**：Distant Horizons、Create、PhysicsMod、BigGlobe 等（readme.md Mod Support 一节），DH 支持深度嵌入（几乎每个深度采样处都有 `DISTANT_HORIZONS` 分支）。

## ② 架构与特性清单

### 阴影与光照
- **PCF 圆盘采样**：黄金角螺旋分布 + 每像素随机旋转矩阵（IGN dither 驱动），SSBO 可用时用预生成偏移数组：`lib/shadows/distorted/render.glsl:47-60`（彩色路径）、`render.glsl:102-117`（标量路径）。默认仅 6 采样（`lib/common.glsl:223`）。
- **PCSS 半影**：`SHADOW_FILTER==2` 时先做 blocker search 求平均阻挡距离，再按 `blockerDistance/(PENUMBRA_SCALE*maxPcf)` 插值采样半径（`lib/shadows/distorted/render.glsl:140-178` 搜索、`render.glsl:206-208` 半径插值）；默认 4 采样搜索 + 半影系数 16（`lib/common.glsl:224,230`）。
- **世界单位采样半径**：`GetShadowPixelRadius` 把"块"为单位的模糊半径经 shadowProjection 换算成纹素半径，使软度不随阴影图分辨率漂移（`lib/shadows/distorted/render.glsl:122-136`）。
- **彩色阴影**：shadowtex0/1 + shadowcolor0 三图配对；透射色做 `sqrt(lum)/lum` 亮度保持归一，再用 alpha 二次方压暗（`lib/shadows/distorted/render.glsl:75-84`、`render.glsl:192-201`）。体积光里同款处理（`lib/fog/fog_volume.glsl:372-376`）。
- **硬件阴影比较**：`SHADOW_ENABLE_HWCOMP` + `IRIS_FEATURE_SEPARATE_HARDWARE_SAMPLERS` 时直接用 `shadowtex0HW` 采样器（`lib/shadows/distorted/render.glsl:29-38`）。
- **延迟阴影 pass**：阴影过滤不在 gbuffers 里算，而是统一在 `program/deferred_shadow_opaque.fsh`（413 行）算完写入缓冲 `outShadow = vec4(shadowFinal, sssFinal)`（`deferred_shadow_opaque.fsh:351-409`），半透明再读——同一像素的整套过滤只算一次。
- **屏幕空间接触阴影**：`SHADOW_SCREEN` 沿光线在屏幕空间步进深度缓冲（默认 12 步），斜率判据 `step(traceDist, sampleDiff * ShadowScreenSlope)` 判遮挡，补 shadow map 分辨率不足的近距遮挡（`deferred_shadow_opaque.fsh:264-349`，判据在 339；开关与步数 `lib/common.glsl:227,229`）。
- **CSM（SHADOW_TYPE 2/3）**：4 tile 级联，逐 tile 用主相机视锥切片求 XY 包围盒做贴合（`lib/shadows/cascaded/prepare.glsl:34-51`，含 `SHADOW_CSM_FITRANGE`/`OVERLAP`，`lib/common.glsl:234-238`）。
- **SSS**：阴影采样时给每个采样点加 `InterleavedGradientNoiseTime` 驱动的随机深度偏移，模拟次表面透光（`lib/shadows/distorted/render_sss.glsl:1-25`，入口 `render_sss.glsl:29`）。
- **方块光三档**：BASIC（lightmap）→ LPV（3D 纹理传播，`lib/lpv/`，`LPV_SIZE` `lib/common.glsl:246` 一带选项）→ TRACED（SSBO 光源网格 + DDA 遮挡追踪，`lib/lighting/voxel/` 14 个文件；`readme.md` FAQ 确认默认关、RTX 档开）。
- **天空辐照度图**：compute 单 workgroup（`program/prepare_sky_irradiance.csh:10`）对 8x8 等距矩形贴图做半球余弦卷积，供环境光查询（`prepare_sky_irradiance.csh:19-66`）。
- **PBR/POM**：法线/高光/自发光/孔隙度/SSS 材质、视差置换 + 曲面细分（`shaders.properties` MATERIAL_OPTIONS 屏一节）。

### Godrays / 体积光
- **统一体积 pass**：没有独立"godrays"程序，日光束就是雾体积里的太阳散射。`ApplyVolumetricLighting` 半/四分之一分辨率光线步进（`lib/fog/fog_volume.glsl:9` 起；分辨率档 `VOLUMETRIC_RES` `lib/common.glsl:315`），默认 48 采样（`lib/common.glsl:313`）。
- **非均匀步长**：`VL_STEP_POWER=160` 把采样点按 `pow(t,1.6)` 扭曲，密度向相机侧集中，且每步乘 dither 抖动（`lib/fog/fog_volume.glsl:154-171`）。
- **逐采样阴影**：每个体素样本直接采 shadowtex（1 tap，非过滤），支持级联与畸变两条路径（`lib/fog/fog_volume.glsl:301-367`）。
- **空气/水密度混合**：同一条 ray 按多层水体深度切段，逐段换密度、吸收、散射与相函数（`lib/fog/fog_volume.glsl:198-239`）。
- **水下光束 + 焦散调制**：水中段用 HG 相函数 `HG(VoL,0.36)`（`lib/fog/fog_volume.glsl:4-6`），样本亮度乘焦散纹理（`lib/fog/fog_volume.glsl:388-397`）。
- **云影参与**：体积样本逐点采样云影（`lib/fog/fog_volume.glsl:399-415`）。
- **方块光入雾**：TRACED 模式逐样本查 SSBO 光源网格并 DDA 遮挡（`lib/fog/fog_volume.glsl:434-481`），LPV 模式查 3D 纹理（`fog_volume.glsl:483` 起）。
- **闪电照明**：雷暴时逐样本叠加定向闪电贡献（`lib/fog/fog_volume.glsl:425-429`）。

### 水体与水下
- **波浪**：基于 Shadertoy MdXyzX 的迭代正弦波叠加求高度与位移（`lib/water/water_waves.glsl:1` 注明出处，`water_waves.glsl:24-53`），含拖曳项 `DRAG_MULT`；可选曲面细分置换（WATER_TESSELLATION_QUALITY）。
- **焦散**：专用纹理 `textures/caustics.dat` 在 shadow view 空间按 XY 查找，`4*pow(c,4+4*WaveStrength)+0.9` 拉峰值（`lib/lighting/caustics.glsl:16-25`）。
- **水下雾**：自定义水雾色 `2*scatter*absorb/(color+1)` 压到 0-1（`lib/fog/fog_water_custom.glsl:16-19`），雾远端 `16/密度` 块（`fog_water_custom.glsl:23`）；FANCY 档走真正的体积散射（上节）。
- **多层水体**：`WATER_DEPTH_LAYERS` 1-6 层，写读两侧 `lib/water/water_depths_write.glsl`/`water_depths_read.glsl`，体积光按层切介质（`lib/common.glsl:142`，读取见 `lib/water/water_depths_read.glsl`）。
- **波纹/泡沫**：雨滴涟漪纹理 `textures/ripples.dat`；水 bump 与泡沫（`lib/water/foam.glsl:5-23`）。
- **折射**：折射强度/模糊/Snell 窗口三选项（shaders.properties MATERIAL_REFRACT_OPTIONS 一节）。

### 大气 / 雾
- 雾分 vanilla/custom/volume 三型 + 洞穴雾 + 边界雾（shaders.properties FOG_OPTIONS 一节）。
- **曲线世界**：可选行星曲率，`GetWorldCurvedPosition` 把本地坐标按球面弯折（cr0420 方案，`lib/world/curvature.glsl:15-25`），天空追踪与雾都带 `WORLD_CURVE_RADIUS` 分支。
- 下界/末地烟雾（WORLD_NETHER_SMOKE / WORLD_END_SMOKE）与专属环境光。

### 后处理
- **TAA**：速度缓冲重投影 + 邻域 AABB 钳制 + 可选 Catmull-Rom 历史采样（锐化）：`lib/effects/taa.glsl:1-15`（钳制）、`taa.glsl:58`（Catmull-Rom）、`taa.glsl:59-66`（累积权重）；另有 `taa_epic.glsl` 高配版。
- **Bloom**：8 级降采样 + 8 级升采样独立程序对（`program/composite_bloom_down_1..8.fsh`、`composite_bloom_up_1..8.fsh`）。
- **SSAO**：半球采样循环，半径/强度/偏置可调（`lib/effects/ssao.glsl:19-27`）。
- **SSR**：深度 tile 加速的屏幕空间反射（`lib/effects/ssr.glsl:6-15`），粗糙度散射选项。
- DoF/景深 + 色差、自动曝光（POST_EXPOSURE）、tonemap/饱和度/对比度（shaders.properties POST_OPTIONS 一节）。

### 植被与湿地面（对照 Astra 雨湿地面）
- **摇曳植被**：顶点阶段风吹动画（WORLD_WIND_STRENGTH），由 block.properties 里的材质标志驱动。
- **雨湿地面**：孔隙度材质（MATERIAL_POROSITY / MATERIAL_POROSITY_DARKEN）+ 水洼（WORLD_WETNESS_PUDDLES 0-4，`lib/common.glsl:111`），湿感 = 颜色压暗 + 法线/反射参数切换， puddle 档位控制积水面积。
- **雨滴涟漪**：`textures/ripples.dat` 帧序列纹理在水面/湿地播放，与 Astra 的程序化雨纹是两条路线。

### 天空与云
- 自定义天空三型（SKY_TYPE 0/1/2）+ 可调日月亮度与三段天光颜色（shaders.properties SKY_OPTIONS 一节）。
- 云分 vanilla / 2D / 体积云（SKY_CLOUD_TYPE），体积云带独立追踪八度数与地面投影（`RENDER_CLOUD_SHADOWS_ENABLED`，消费见 `lib/fog/fog_volume.glsl:399-415`）。
- 星空强度、云影亮度均可调（`lib/common.glsl:239-240` 附近的 SHADOW_CLOUD_*）。

### 性能与时域
- 体积光半/四分之一分辨率 + 专用模糊（`lib/common.glsl:315,318`）。
- IGN 时域抖动贯穿阴影、体积光、SSR、SSAO：TAA 开时用 `InterleavedGradientNoiseTime`（帧间滚动），关时退化静态噪声（`lib/fog/fog_volume.glsl:16-21`、`lib/effects/ssr.glsl:12-15`）。
- `IRIS_FEATURE_SSBO`/`IRIS_FEATURE_SEPARATE_HARDWARE_SAMPLERS` 特性探测，逐处提供无 SSBO 回退路径（如 `lib/shadows/distorted/render.glsl:53-61`）。
- DH 全覆盖：深度/阴影/雾每个环节都有 DH 分支。
- 体积光像素化/低分辨率 + 上采样模糊（VOLUMETRIC_RES 2/1/0 三档 + VOLUMETRIC_BLUR_SIZE），阴影也有像素化选项 SHADOW_PIXELATE 供低端档。
- 采样数全部可调且默认值保守：VL 48 步、PCF 6 点、PCSS 4 点、SSS 4 点、SSAO/SSR/TAA 各自独立档位——"默认能跑，档位拉满"的参数哲学。
- 阴影与体积光的结果在 deferred 侧复用（见上"延迟阴影 pass"），gbuffers 与 composite 各取所需，避免同一像素重复整套过滤。

## ③ Astra 可借鉴点

> 难度估计：低 = 改一处采样循环；中 = 新增一个选项 + 局部重构；高 = 跨 pass 架构改动。

1. **世界单位阴影模糊半径 + 每像素旋转抖动**
   - 技术描述：把用户"软度"定义为世界块数，经 `GetShadowPixelRadius` 换算纹素（`lib/shadows/distorted/render.glsl:122-136`）；采样盘用黄金角分布并按 IGN 随机角旋转（`render.glsl:47-60`），6 采样即可得均匀软影，TAA 负责去噪。
   - Astra 模块：`Astra/shaders/global/lighting/diffuse.glsl:277-286`（现为固定 ±对角纹素偏移 `SHADOW_SOFTNESS`）。
   - 迁移难点：低。Astra 已有 `lib/dither.glsl` 与 TAA；只需加换算常量与旋转。注意 Astra 刻意"无旋转采样模式"求静态稳定（diffuse.glsl:267-268 注释），需保留关闭档。

2. **PCSS 阻挡搜索（半影随遮挡距离增长）**
   - 技术描述：先 N 点搜索平均阻挡距离，再 `minRadius + (maxRadius-minRadius) * blockerDist/(PENUMBRA_SCALE*maxRadius)` 得采样半径（`lib/shadows/distorted/render.glsl:140-178,206-208`）。近接触硬、远距离软，物理直觉强。
   - Astra 模块：`Astra/shaders/global/lighting/diffuse.glsl:254-292`（surface_shadow_light）+ `shadowmap.glsl`。
   - 迁移难点：中。多一轮 4-6 采样；Astra 的 gather 逐角保留 caster 身份，需决定 blocker 搜索是否也要彩色感知（Shrimple 不感知）。

3. **屏幕空间接触阴影（SHADOW_SCREEN）**
   - 技术描述：从像素沿光线在屏幕空间步进 12 步，深度斜率判据补测 shadow map 漏掉的近距遮挡，同时喂 SSS 距离（`program/deferred_shadow_opaque.fsh:264-349`，判据 339 行）。
   - Astra 模块：无对应实现；最接近的落点是 `global/lighting/shadowmap.glsl` 新增函数，由 E1/表面路径调用。
   - 迁移难点：中高。Astra 前向架构没有独立 deferred 阴影 pass，屏幕追踪要在 gbuffers 内做（每像素重复）或引入 Astra 现无的小型 deferred 阴影缓冲。

4. **体积光非均匀步长 + 分辨率/抖动组合**
   - 技术描述：`pow(t,1.6)` 步长扭曲把 48 采样的有效密度堆向相机，IGN 时间抖动 + TAA 去噪（`lib/fog/fog_volume.glsl:154-171`；分辨率档 `lib/common.glsl:315`）。
   - Astra 模块：`Astra/shaders/global/atmosphere/volume_fog.glsl`（226 行，射线步进体积雾）。
   - 迁移难点：低。改步长分布表达式即可；需确认与 Astra 半分辨率时域历史复用不冲突。

5. **水下光束的焦散调制**
   - 技术描述：体积步进的水中段样本亮度乘焦散纹理，光束里出现晃动焦散纹（`lib/fog/fog_volume.glsl:388-397` + `lib/lighting/caustics.glsl:16-25`）。
   - Astra 模块：`Astra/shaders/global/water/light_shafts.glsl:57-74`（march 循环，已有 shadowcolor 透射，无焦散项）。
   - 迁移难点：中。Astra 焦散是解析噪声（`global/water/caustics.glsl:9-10`），可复用其函数；march 每样本多一次噪声查表，注意 48 步成本。

6. **专用焦散纹理（替代解析焦散的外观选项）**
   - 技术描述：预烘 caustics 纹理按 shadow-view XY 查找 + 幂次拉峰（`lib/lighting/caustics.glsl:16-25`），观感比噪声叠加更"网状"。
   - Astra 模块：`Astra/shaders/global/water/caustics.glsl`。
   - 迁移难点：低（代码），但**纹理资产必须自制**（Shrimple 的 caustics.dat 不可复制）；作为 Astra 现有解析焦散之外的选项而非替换。

7. **TAA 历史采样 Catmull-Rom 锐化**
   - 技术描述：重投影命中后用 Catmull-Rom 采历史代替双线性，缓解历史模糊（`lib/effects/taa.glsl:58`），配合邻域钳制（`taa.glsl:1-15`）。
   - Astra 模块：`Astra/shaders/lib/taa_state.glsl`、`taa_reactive.glsl`（Astra TAA 具体历史滤波方式未逐行核实，此处不确定其是否已有等效实现）。
   - 迁移难点：低-中。4-9 tap 的凸组合；需先核实 Astra 现状再决定。

8. **多层水体深度（WATER_DEPTH_LAYERS）**
   - 技术描述：把视线穿过的多段水写进缓冲，体积与雾按层切介质（`lib/common.glsl:142`，`lib/water/water_depths_write.glsl`/`water_depths_read.glsl`，体积消费 `lib/fog/fog_volume.glsl:198-215`）。
   - Astra 模块：`Astra/shaders/lib/water_buffer_formats.glsl`（或 `global/water/medium_state.glsl`）——Astra 水缓冲当前层数未核实，不编造。
   - 迁移难点：高。新增缓冲格式 + 写/读 pass；对玻璃夹水等场景收益明显，建议最后做。

## ④ Astra 已有对应实现（对照与优劣）

- **阴影过滤（专项 a）**：Astra `global/lighting/shadowmap.glsl:89-101` 用硬件 `textureGather`/sampler2DShadow 一次取 4 深度，`shadowmap.glsl:102-131`（shadow_lobe_light）逐角保留透明 caster 身份，`global/lighting/diffuse.glsl:266-287` 按 SHADOW_FILTER_QUALITY 叠 2/4 个对角 lobe（即"8 配对角点"= 4 gather × 2 组）。**Astra 优**：零旋转噪声、一次 gather 顶 4 tap、每角 caster 精确保留（Shrimple 的彩色路径整盘共享一次 shadowcolor 采样，混合边缘更糊）；**Shrimple 优**：世界单位半径、PCSS 半影、SSS 抖动。Astra 半影固定不随遮挡距离增长——这是最明确的差距。
- **Godrays（专项 b）**：Astra `global/post/godrays.glsl:53-88` 是 GPU Gems 3 式屏幕空间深度步进（8 采样 + Bayer8 抖动，`godrays.glsl:63-73`），且 `godrays.glsl:54-61` 明确在体积雾开启时让位（防重复散射）。Shrimple **没有屏幕空间 godrays**，日光束完全由 `fog_volume.glsl` 射线步进承担。**Astra 优**：屏幕空间束近乎免费、offscreen 衰减成熟；**Shrimple 优**：物理式逐样本阴影/相函数/介质切换，束内可见焦散与云影。两者是同一目标的两条路线，Astra 已有可选世界射线步进体积雾补位，无需搬 Shrimple 的做法。
- **水下光束**：Astra `global/water/light_shafts.glsl:28-82`（专用水下 march：可见水段界定、Solas 混合分布采样、彩色阴影）+ `light_shafts.glsl:85-117`（4 旋转双线性足迹 + 距离权重 resolve + 第四根压缩存储）。Shrimple 水下光束 = fog_volume 内水中段样本，无独立 resolve 链。**Astra 优**：专用水下链路更完整（时域历史 + 半分辨率滤波）；**Shrimple 优**：与空气体积共用一套积分器、带焦散调制——Astra 缺的正是束内焦散（见③-5）。
- **水下视觉（专项 c）**：Astra `global/water/absorption.glsl:13-16` Beer-Lambert 系数 + 分深度双端光谱（`absorption.glsl:18-30` 注释段），焦散/折射/SSR/光束/粒子各有独立模块。Shrimple 水下 = 指数雾 + 体积散射 + 焦散纹理 + 多层深度。**Astra 优**：光谱物理与模块化更细；**Shrimple 优**：多层水体介质切换、FANCY 档水下体积散射一体化。Astra 的吸收/散射已是独立可调（absorption.glsl:12 注释），无需借其参数化方式。
- **天光方向性**：Shrimple 用 8x8 天空辐照度卷积图（`program/prepare_sky_irradiance.csh:19-66`）；Astra 用 SH9（`Astra/shaders/lib/sky_sh9.glsl`，205 行）。两者同层级，SH9 带宽更省、辐照度图精度上限更高；Astra 无需改。
- **雨湿地面**：Shrimple 走材质孔隙度 + 涟漪纹理帧序列 + puddle 档位（`lib/common.glsl:111`）；Astra 走 wetness 参数链（`Astra/shaders/global/atmosphere/weather.glsl` 与表面路径，具体水洼形态实现未逐行核实，不编造）。**Shrimple 优**：涟漪动画有专用纹理资产、观感成熟；**Astra 优**：湿感与雨雾/反射的联动更成体系（其结论留待专项复核）。
- **TAA**：Shrimple `lib/effects/taa.glsl` 是"速度重投影 + 邻域钳制 + Catmull-Rom"的紧凑版（71 行）另有 epic 版；Astra 的 TAA 状态机（`lib/taa_state.glsl`、`taa_reactive.glsl`、`taa_jitter.glsl`）粒度更细、含反应性分离。**Astra 优**：工程化程度高；**Shrimple 优**：Catmull-Rom 历史采样是现成的小改进点（③-7）。
- **大气/雾**：Shrimple 有曲线世界与体积雾一体（`lib/world/curvature.glsl:15-25`）；Astra 有分层雾/空气透视与可选体积雾（`global/atmosphere/fog.glsl`、`volume_fog.glsl`）。曲线世界属风格化选项而非质量提升，Astra 无需跟进。
- **工程拆分（专项 d）**：697 文件中 lib 149 + program 136 + world0/world1/world-1 各 147（本报告开头 find 统计），即 **3 个维度目录是 program 的整份复制**（`shaders/world0/composite10.fsh` 与 `shaders/program/composite10.fsh` 同名同源，Iris 逐维度目录要求 + 构建产物），`shaders/template/` + PoTater 生成属性文件（template/readme.md:1）。真实独立逻辑约 285 个文件。lib 粒度极细（`hg.glsl`、`fresnel.glsl`、`blackbody.glsl` 单函数单文件）。**结论**：world 复制是构建产物不是设计（Astra 用 `#ifdef` 分维度更省，无需学）；lib 细粒度对"一个函数一个文件、include 树即依赖图"的 review 友好性有真实优势，但 Astra 现有 `lib/` 按主题聚合（15-30 行的 settings/uniforms 也已单列）粒度已足够，再细分是过度拆分。Shrimple 真正值得学的拆分点是其"算法在 lib、调度在 program"的严格分层——Astra 同样如此（如 godrays.glsl 只放算法、composite.fsh 调度），两边一致。

## ⑤ 借鉴可行性（许可证层面）

- `LICENSE:1-3` 为 **All Rights Reserved**：**禁止**复制、改编、翻译 Shrimple 的任何源码、注释结构、贴图（caustics.dat / ripples.dat / noise.png）、lang 与 properties 文本到 Astra。
- 可行路径：仅借鉴**算法思想与技术参数思路**（PCSS、步长扭曲、屏幕空间阴影等均为图形学通用技术，非该包独创），由 Astra 侧独立实现并写自己的注释；实现时对照本文引用行号回看逻辑，不逐行转录。
- 与 Astra 现状兼容：Astra 已含 Steadfast（GPL）派生组件，接受第三方思想不受影响；但**任何 Shrimple 代码级移植都会引入无授权素材**，红线下禁止。
- 结论：**思想层面可借鉴，代码/资产层面不可移植**。③ 中所有条目均按"独立重写"估计工作量。

## ⑥ Top5 优先建议（按 提升/工作量 排序）

1. **阴影世界单位半径 + IGN 旋转盘（③-1）**：改动集中在 `diffuse.glsl` 一个循环，直接消除"软度随分辨率/档位漂移"，提升/工作量比最高。保留 Astra 现有无抖动档作为稳定选项。
2. **PCSS 阻挡搜索（③-2）**：接触硬 + 远软是 Shrimple 阴影口碑的核心来源；在 1 的采样框架上加一轮 4 点搜索即可，成本与效果成正比。
3. **水下光束焦散调制（③-5）**：Astra 水下表现已强，束内焦散是现成函数（Astra 自己的 caustics.glsl）+ march 一行乘法的差距，观感提升立竿见影。
4. **体积光非均匀步长（③-4）**：`volume_fog.glsl` 步长分布改 `pow(t,k)` + 时间抖动，近景雾密度感受明显变好，工作量半天级。
5. **屏幕空间接触阴影（③-3）**：补 shadow map 近距分辨率短板，但需要 Astra 决定落在前向逐像素还是引入小 deferred 阴影缓冲，工作量中高，建议在前四项落地后再评估。

## 附：引用自抽查记录（验收标准 2）

写完报告后重新打开源文件核对以下 12 条 `文件:行`（grep -n 复验命中行号，非誊写）：

| # | 引用 | 复验内容（该行实际文本片段） | 结果 |
|---|------|------------------------------|------|
| 1 | `LICENSE:1-3` | "All Rights Reserved / Copyright (c) 2023 Joshua Miller" | 一致 |
| 2 | `shaders.properties:1,4` | profile.VANILLA / profile.RTX 定义行 | 一致 |
| 3 | `lib/common.glsl:220,223,224,227,229,230` | SHADOW_FILTER 2 / PCF 6 / PCSS 4 / SHADOW_SCREEN / STEPS 12 / PENUMBRA 16 | 一致 |
| 4 | `lib/shadows/distorted/render.glsl:57` | `float theta = i * GoldenAngle + PHI;` | 一致 |
| 5 | `lib/shadows/distorted/render.glsl:140` | `float FindBlockerDistance(...)` | 一致 |
| 6 | `lib/shadows/distorted/render.glsl:122` | `vec2 GetShadowPixelRadius(...)` | 一致 |
| 7 | `program/deferred_shadow_opaque.fsh:339` | `shadowTrace *= step(traceDist, sampleDiff * ShadowScreenSlope);` | 一致 |
| 8 | `lib/fog/fog_volume.glsl:154,388-397,483` | `#define VL_STEP_POWER 160` / 焦散调制块 / `GetLpvFogBlockLight(lpvSample)` | 一致 |
| 9 | `lib/lighting/caustics.glsl:16-17,25` | causticCoord / texCaustics / `4.0 * pow(causticLight, ...)` | 一致 |
| 10 | `lib/fog/fog_water_custom.glsl:16,23` | `2.0 * RGBToLinear(WaterScatterColor) * RGBToLinear(WaterAbsorbColor)` / `waterFogFar = min(16.0 / WaterDensityF, far)` | 一致 |
| 11 | `lib/effects/taa.glsl:58` | `sampleHistoryCatmullRom(uvPrev)` | 一致 |
| 12 | `program/prepare_sky_irradiance.csh:10,19` | `workGroups = ivec3(1,1,1)` / `vec3 CalculateIrradiance(...)` | 一致 |

Astra 侧引用（shadowmap.glsl:89-131、diffuse.glsl:254-292、godrays.glsl:53-88、light_shafts.glsl:28-117、absorption.glsl:13-16）均在阅读原文时按行号截取，同批复核一致。

—— 完 ——
