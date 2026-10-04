# dercode × Astra 性能调研（batch4）

- 调研日期：2026-10-03。数据时点：包内容为本地解压快照（`reference_shaderpacks/dercode/`）；版本/下载量以任务书给定（Modrinth v2.2，181,670 下载）为准，包内未找到版本字符串可佐证。
- 引用约定：`P:` = `reference_shaderpacks/dercode/shaders/`（本包 shader 根即 `shaders/`，行号相对该目录）；`A:` = `Astra/shaders/`。
- 去重材料：`shader_research/SUMMARY.md`、`SUMMARY-batch2.md`、`SUMMARY-batch3.md`、`docs/2026-10-02-shader-reference-performance.md`、`docs/2026-10-03-batch3-selected-optimizations.md` 全部读过；每条候选均附 `Astra/shaders` 多关键词 grep 结果。
- **血统判定（决定本文口径）**：`P:README.txt:10` 自述为 **DERIVATIVE MAIN 的重制版**，`:16` 说明原始 fork 自 **Bliss**、后迁到 Derivative。Bliss（批次一）与 Derivative（10-02 视频轮）均已研究，故本文按「只报相对增量的机制」处理；但未做逐文件 diff（无 Bliss/Derivative 同版本快照对齐），因此清单以「该包内可见 + 五份材料去重 + Astra grep」三重口径为准，凡材料已列的一律标注为已知/去重，不重复主张（见备注 1）。

---

## 一、概况

| 项 | 事实 | 证据 |
|---|---|---|
| 定位 | 写实+奇幻风格「全家桶」：GI（SSDO/RSM/SSIL/ReSTIR/NBGI/LPV）、主世界体素彩光、体积云、体积雾、SSR/世界反射、PBR/POM、大量摄影与整活后处理 | `P:lib/GI/`、`P:lib/lpv/`、`P:shaders.properties` 1009 行 |
| 血统 | Bliss → Derivative main 的重制分支；包内自述与 Complementary 无关；README 同时承认大量第三方源码「已获原作者批准」 | `P:README.txt:10,12,14,16` |
| 许可 | 包内仅 `README.txt`，**无 LICENSE 文件**；`:6-8` 写 All Rights Reserved © 2025 Mizore，`:10` 又写 "feel free to use the source however you want"，`:25` 要求公开 fork 标注 `[ DC FORK ]`——口径自相矛盾 | `P:README.txt:6-8,10,25`；`find -iname "*licen*"` 0 命中 |
| 规模 | 整包 **437 文件**；shader 代码 **31,184 行**（口径 `.glsl/.fsh/.vsh/.csh/.gsh`，任务书 31,151 系同口径快照差）；含 `.inc/.frag/.vert/.comp/.geom/.tes/.tcs` 共 **39,117 行**；另有 `P:Settings.glsl` 981 行、`P:shaders.properties` 1009 行、贴图/语言文件若干 | `find -type f \| wc -l`；`find ... -print0 \| xargs -0 wc -l` |
| 结构 | 根 `shaders.properties` + `Settings.glsl` + `lib/`（Atmosphere/GI/Lighting/Water/Surface/Post/Head/Util/Outline/OtherCommon/lpv）+ `program/`（Gbuffers/Shadow/Post/DH/voxy + Deferred0-8/composite 源）+ `world0/`、`world-1/`、`world1/` 薄壳（含各自 `.fsh/.vsh` 转发 `program/` 源，部分直接内联配置） | `P:world0/deferred.fsh:2`、`P:world0/composite2.fsh:2` |
| 工程特征 | 全包 GLSL **450 compatibility** + compute/image3D/SSBO；无 `size.buffer`、无 `scale.`（注释残留 `P:shaders.properties:358-360`）；缓冲分档靠 flip 表与 1/N 视口缩放 | `grep "size\." P:shaders.properties` 0 命中；`:356-360` |

---

## 二、管线与调度

- **program 清单**（`P:shaders.properties` + `find program`）：`gbuffers_`{terrain(+gsh/tcs/tes), water, entities, hand, hand_water, block(+gsh), textured, basic, beaconbeam, spidereyes, armor_glint, damagedblock, weather, skybasic, skytextured, clouds} → `shadow`（根 `P:shadow.vsh` 为 430 薄壳）→ `deferred`(=Deferred0 天空/云) → `deferred1`(1/N 云) → `deferred2`(时域重建 + GI/AO 累积) → `deferred3`(SSIL/GI/ReSTIR 或 SpatialFilter.frag) → `deferred4`(SpatialFilter.comp) → `deferred5`(水下/手持光反射) → `deferred6`(SSR/世界/混合反射) → `deferred7/8`(反射滤波 frag/comp) → `composite`(体积雾) → `composite1`(手电/整活后处理) → `composite2`(DoF) → `composite3`(Temporal=TAA) → `composite10/12/13`(Bloom 降采样+双向模糊) → `composite14`(运动模糊) → `composite15`(Grade) → `final`；另有 `physics_ocean`（复用 `Gbuffers/Water.frag`，`P:world0/physics_ocean.fsh:6`）、`dh_shadow/dh_terrain/dh_water`、`world1/vx_*`（Voxy）、`voxy_opaque/voxy_translucent`。
- **阶段启停**（`P:shaders.properties`）：`gbuffers_spidereyes` 挂 `ENTITY_EYES_LIGHTING`（:236-238）；`deferred3/4/7/8` 按 `MC_VERSION` 与 `GI_ENABLED||SSAO_ENABLED||SSGI_ENABLED||RESTIR_ENABLED`、`REFLECTION_FILTER&&SPECULAR_MAP` 整段停调度（:252-286）；`RippleSim/RippleSetup` 挂 `WATER_RIPPLES`（:291-295，见反面印证 2）；`composite2=DOF`、`composite10/12/13=BLOOM`、`composite14=MOTION_BLUR`（:297-321）。
- **分辨率/缓冲分档**：无 `size.buffer`；天空/云走 `TEMPORAL_UPSCALING`（2/3/4/6 档，默认 2）——`P:world0/deferred1.vsh:18` 顶点缩放 `2/TEMPORAL_UPSCALING` 把整 pass 缩为 1/N，`P:program/Deferred2.glsl:47-65` 用 4/9/16 相位棋盘表 + `P:program/Deferred1.glsl:378` 的 `texel*N+offset` 重建；`SKY_CAPTURE_RES` 常量表（`P:Settings.glsl:75-84`，默认 255×256）决定天空捕获带尺寸；GI 有 `GI_RESOLUTION`（`P:Settings.glsl:8`）、GI/SSAO 走 2×2 四像素打包（`P:program/Deferred2.glsl:230-244,265-273`）。
- **缓冲/乒乓**：`flip.deferred3/4.colortex8/9=true`（3-4 pass 乒乓）、`flip.deferred6.colortex0/1=false → composite15=true`（延迟清空）、`flip.composite1.colortex5=true`（P:shaders.properties:334-354）；`colortex29 R16F/clear=false`、`colortex26 RGBA16F/clear=false`、`colortex8 RG16F/clear=false`（:327-333）；体素/图集：`image.voxelGridA r8ui 128×64×128` + `image.lightimg0/1 rgba16f 128×64×128` + `image.rippleA/B rgba16f 128×128`（:242-247）；`buffers.ssbo.0 = photonics_volume`（:336，ReSTIR 用，`P:program/Deferred3.glsl:28,61,90`）。
- **CPU 侧帧不变量**：光源方向/归一化（`P:shaders.properties:112-122`）、雨湿/眼睛亮度/溺水/血量等 `smooth()`（:127-183）、下界群系平滑（:192-212）、世界时间与 `worldTimeChanged`（:214-216）、体素雾风/密度（:218-221）、Halton(2,3) 16 帧 TAA 抖动（:152-161）——均为材料 12 包共识项，去重。

---

## 三、分模块性能手法清单

### 3.1 调度与阶段启停

| # | 位置 | 机制 |
|---|---|---|
| 1 | `P:shaders.properties:252-286` | `deferred3/4`（GI/空间滤波）与 `deferred7/8`（反射滤波）按功能表达式整段停调度；MC≥1.16.5 用 compute 版（deferred4/8）、旧版退回 frag 版（deferred3/7） |
| 2 | `P:shaders.properties:297-321` | DoF/Bloom/MotionBlur 三个后处理段各自门控；`composite4`（Bloom 首降采样）恒 false |
| 3 | `P:shaders.properties:334-354` | flip 表实现乒乓与延迟清空：colortex8/9 在 deferred3/4 间乒乓，colortex0/1 延迟到 composite15 再 flip |
| 4 | `P:program/Deferred0.glsl:272-308` | 主天空 pass 内嵌「天空捕获带」：x=255 列为 6 texel 帧级光照（direct/sky/sun/moon/云天气），y<258 行为无云原始天空图，其余行才画含云天空；不新开天空缓存 pass |
| 5 | `P:world0/deferred1.vsh:18` | 顶点级 `gl_Vertex.xy*(2/N)-1` 把云 pass 缩到 1/N 分辨率（不改缓冲声明）；`P:program/Deferred1.glsl:378` 配棋盘相位索引 |
| 6 | `P:program/Deferred2.glsl:247-296` | 天空/云时域重建：帧内直接取 `texelFetch(colortex2, currentTexel)`，非选中相位取 Catmull-Rom 历史（:67-96），`MAX_BLENDED_FRAMES` 封顶 + 相机位移/像素速度调权（:284-290），`worldTimeChanged` 失效（:211,277） |

### 3.2 地形光照与阴影

| # | 位置 | 机制 |
|---|---|---|
| 1 | `P:lib/Lighting/SunLighting.glsl:62-83` | 阴影风格 1/2：单次 `textureLod(shadowtex1)` + `texelFetch` 比较，只有 `shadowtex0` 与 `shadowtex1` 判定不一致（半透明遮挡）才读 `shadowcolor0`（:77-79） |
| 2 | `P:lib/Lighting/SunLighting.glsl:90-113` | 默认 PCF：`PCF_SAMPLES`（16）旋转黄金角盘 + `sqrt(fi*rSteps)` 半径；逐 tap 沿用同一条彩色阴影门控 |
| 3 | `P:lib/Lighting/SunLighting.glsl:41-57` | PCSS blocker/SSS 共用一趟 8-tap 搜索：同时得 `searchDepth`（半影）与 `sssDepth` |
| 4 | `P:lib/Lighting/SunLighting.glsl:62-64` | 像素锁定阴影：世界坐标量化到 `SHADOW_PIXEL_SIZE`（默认 16）网格 |
| 5 | `P:lib/Lighting/SunLighting.glsl:141-200` | 屏幕空间阴影：12 步、出屏/深度≥1/遮蔽率<1e-2 早退（SHADOW_STYLE 0 档） |
| 6 | `P:lib/Lighting/AmbientOcclusion.glsl:26-34,147-205,209-260,287-296` | GTAO/HBAO/VXAO/UE4-AO 四套实现各自样本数与半径，最后连乘合成；VXAO 复用体素网格 |
| 7 | `P:lib/GI/GI_RSM.glsl:11-15` | RSM 近/远双段：`GI_RSM==1` 时再叠一次 `CalculateRSM_Far`（半相位抖动错开） |

### 3.3 云

| # | 位置 | 机制 |
|---|---|---|
| 1 | `P:lib/Atmosphere/VolumetricClouds.glsl:2-33` | 云采样/日照/天光三个独立预算：`CLOUD_CUMULUS_SAMPLES 32`、日照 4、天光 2；`minTransmittance 0.05` |
| 2 | `P:program/Deferred1.glsl:163-228` | 体积云 march：步数按 `\|worldDir.y\|` 混到 0.6×，`transmittance<minTransmittance` break、密度<1e-4 continue、越出云层 continue；噪声细节随距离降（`mix(noiseDetail,1,exp2(-dist*0.001))`） |
| 3 | `P:lib/Atmosphere/VolumetricClouds.glsl:89-108,150-165` | 密度 fbm 倍频数由 `steps` 参数决定、每级权重 ×0.5；`CLOUD_LOCAL_COVERAGE` 时先查局部覆盖，`localCoverage<0.1` 直接 return 0（空云区不进 fbm），阴影用同构密度再查一次 |
| 4 | `P:lib/Atmosphere/VolumetricSkyCloudLayer.glsl:2-51` | 三层「积云层」各带 enable/高度/厚度/覆盖/不透明度与各自采样预算（SKY_CLOUD_SAMPLES 24 / 光照 4），按层独立开关 |
| 5 | `P:lib/Atmosphere/PlanarClouds.glsl:293,328` | 卷云/卷积云为常数小循环（3 / 2 次采样），不随主云预算走 |
| 6 | `P:lib/Atmosphere/VolumetricClouds.glsl:203,223` | 日照/天光步进长度 = 云厚×0.2/样本数（固定短程），只在密度命中后调用 |

### 3.4 雾与大气

| # | 位置 | 机制 |
|---|---|---|
| 1 | `P:lib/Atmosphere/VolumetricFog.glsl:173-178` | 步数随射线长自适应：`VOLUMETRIC_FOG_SAMPLES*0.4 + rayLength*0.1`，上限为样本设置 |
| 2 | `P:lib/Atmosphere/VolumetricFog.glsl:236,247,304,366` | 四重早退：`rayPosition.y>384` continue、密度<1e-5 continue、透射<1e-3 break、投影出阴影图 continue |
| 3 | `P:lib/Atmosphere/VolumetricFog.glsl:266-269` | 体积阴影（日照）只在密度命中后做 4 步 `worldLightVector` 采样 |
| 4 | `P:program/Deferred0.glsl:2` + `P:shaders.properties:33-36` | `PRECOMPUTED_ATMOSPHERIC_SCATTERING`：3D LUT（`Final.lut` 256×128×33 RGBA16F）经 `texture.deferred.colortex4.1` 绑定到 deferred 阶段，替代部分解析大气散射 |
| 5 | `P:lib/Atmosphere/BiomeWeatherFog.glsl` / `BlizzardFog.glsl` / `NetherVolumetricFog.glsl` | 群系/天气雾为解析或低步数独立模型，按维度/天气门控（特性件，非核心手段） |

### 3.5 水与水下

| # | 位置 | 机制 |
|---|---|---|
| 1 | `P:lib/Surface/ScreenSpaceReflections.glsl:78-145` | SSR 步长按 `abs(depth-rayPos.z)*stepWeight` 自适应并夹在 `[1/屏,1/steps]`；命中后 5 步二分（:151-160）；`ValidateDepthContinuity` 四邻域方差校验交点（:65-76） |
| 2 | `P:lib/Surface/ScreenSpaceReflections.glsl:94-112,124-145` | 水下反射专用：`distRatio=len/viewDist`，抖动向 0.5 收敛（`mix(dither,0.5,distRatio*0.9)`）、容差×2×(1+4*distRatio)、前 4 步步长减半、远距（>0.8）直接接受命中 |
| 3 | `P:world0/deferred6.fsh:8-12,97-100` | `REFLECTION_TYPE 0/1/2`（SSR / 世界反射 / SSR+RSM 混合）；SSR 步数按 `(1-roughness)` 缩放 |
| 4 | `P:lib/Water/WaterReflection.glsl:153,265-276` | 波高场求交上限 60 步；粗糙度驱动射线锥偏移（`roughness*0.25`）后再取反射色 |
| 5 | `P:world0/deferred5.fsh`（691 行，`DRAWBUFFERS:04`） | 水下/水面反射独立 pass：含手持光、反射内雾与星空，避免与主 deferred 耦合 |
| 6 | `P:lib/Lighting/AmbientOcclusion.glsl:209-260` | VXAO 直接采样体素网格做近距 AO（体素彩光的二次利用） |

### 3.6 粒子·实体·天气

| # | 位置 | 机制 |
|---|---|---|
| 1 | `P:shaders.properties:71-73` + `P:program/Gbuffers/Textured.frag:7` | 粒子专用前向缓冲 colortex31（RGBA16F，clear=true），`RENDERTARGETS: 6,7,3,31` |
| 2 | `P:program/Post/DownSample0.glsl:84-88` | Bloom 首降采样单独 5-tap 读粒子缓冲，粒子辉光不进主色链 |
| 3 | `P:lib/Lighting/HeldLightShadow.glsl:161-178` | 手持光屏幕空间阴影：8 步、步长递增 0.3、深度/出屏/命中早退 |
| 4 | `P:world0/gbuffers_weather.fsh:9` | 雨/雪走 `RENDERTARGETS: 0,31`，与粒子共用独立缓冲 |
| 5 | `P:program/Shadow/Shadow.vert` + `P:shaders.properties:242` | 体素占用由 shadow pass 以 `imageAtomicMax` 写 `voxelGridA`（r8ui），不新开体素化 pass |

### 3.7 后处理与缓冲内存

| # | 位置 | 机制 |
|---|---|---|
| 1 | `P:program/Post/Final.glsl:154-171,1467-1492,1504-1527,1543-1591` | TAA：Catmull-Rom 历史（9-tap）或双线性；5/9 邻域 min/max/方差裁剪（1.25σ）；亮度差把混合权重推向 0.45；距离控制最大混合；可选锐化 |
| 2 | `P:program/Post/Final.glsl:1529-1541` | 无独立速度缓冲：用当前深度 + 相机位移反投影求 prevUV（比速度图省一附件，代价是物体运动不可见） |
| 3 | `P:lib/Post/DonorBloom.glsl:6-31` | 4-tap 双三次读 bloom 供体（colortex29 R16F），曝光归一后混入；雨天再混 |
| 4 | `P:program/Post/Grade.glsl:194-203,206-243` | Bloom 7 级 mip 逐级上采样平均（每级 4 tap），fog mask 可抬高 |
| 5 | `P:program/Post/DownSample.glsl:45-50`、`BlurH/V.glsl:20` | Bloom 链 `±BLUR_SAMPLES` 可分离模糊（9 tap） |
| 6 | `P:program/Deferred2.glsl:230-244,265-273` | GI/AO 结果按 2×2 四像素打包进一名缓冲（半个屏幕装 AO、半屏装深度/normal 历史），省一个附件 |
| 7 | `P:shaders.properties:327-335` | 只在必要处关闭清空（29/26/8）并延迟 flip，其余保持 Iris 默认 |
| 8 | `P:lib/OtherCommon/TemporalNoise.glsl:1-13` | 蓝噪声/Bayer 的时序推进（golden/plastic 比例 × frameCounter），供 GI/反射抖动 |

---

## 四、反面印证（不建议学）

1. **三个反射选项是死配置**：`PREV_REFLECTIONS` / `PREV_REFLECTION_SAMPLES 12` / `PREV_REFLECTION_BLEND 0.85` 在 `P:Settings.glsl:20-22` 定义，全包无消费者（`grep -rn "PREV_REFLECTION"` 仅 Settings.glsl 3 行命中）——菜单可调但行为恒为关。
2. **体素涟漪链无文件/无宏**：`program.world0/RippleSim` 与 `program.setup.RippleSetup` 挂 `WATER_RIPPLES`（`P:shaders.properties:291-295`），但 `WATER_RIPPLES` 全包从未定义（grep 仅 properties 命中）、`world0/` 下无 RippleSim/RippleSetup 程序文件、`image.rippleA/B`（:246-247）无读写者——缺文件的功能链。
3. **TSR 档位 0/6 不可用**：`TEMPORAL_UPSCALING` 下拉提供 `[0 2 3 4 6]`（`P:Settings.glsl:86`），但 `Deferred1/2` 只定义 2/3/4 的相位表（`P:program/Deferred2.glsl:47-65`）；选 6 无数组定义，选 0 时 `deferred1.vsh:18` 的 `2.0/TEMPORAL_UPSCALING` 除零。
4. **同帧两套天空/云输出并存**：`deferred0` 全屏画含云天空进 colortex5（`P:program/Deferred0.glsl:304-308`）供方向查询/反射（`P:world0/composite1.fsh:106,393`），同时 `deferred1` 又按 1/N 重画一遍云、`deferred2` 再时域重建进 colortex1（`P:program/Deferred2.glsl:247-296`，消费点 `P:world0/deferred5.fsh:225`、`P:world0/composite1.fsh:401-404`）——分工在源码无注释说明，存在重复计算嫌疑，不应照搬。
5. **Bloom 链取数偏多**：7 级 mip 平均（`P:program/Post/Grade.glsl:194-203`）后供体再 4-tap 双三次（`P:lib/Post/DonorBloom.glsl:6-26`），多于 Astra 现有 0.25 捕获 + 4 级 mip + 4/9/13 tap 分档。
6. **包内自述不适合弱机**：`P:README.txt:20` "THE SHADER IS EXTREMELY UNOPTIMIZED FOR WEAK/OLD GPUS"；决策面本身（1009 行 properties + 981 行 Settings + 每条效果一个循环预算）不构成可借的性能结构。
7. **compute/frag 双版本靠 MC_VERSION 编译期二选一**（`P:shaders.properties:252-286`）：同一效果两份实现，维护与编译成本高、收益仅是兼容旧版，Astra 无此需求。

---

## 五、新颖借鉴点

> 以下每条已先对 `Astra/shaders` 多关键词 grep，并与五份材料逐条对照；材料已列的同方向（CPU 预计算、program 启停、云步数分档/首次命中、SSR 有限步进+二分+置信度、TAA YCoCg、彩色阴影按需读、Bloom mip 分档、下界体素每帧 compute、静态大气 LUT、云时域超分、上帧 SSR、GI 长期方向等）一律不重复主张。

### A 组（低代价，可直接排期）

| # | 机制 | 来源 file:line | Astra 未实现证据（grep 关键词与结果） | 迁移代价 |
|---|---|---|---|---|
| A1 | **水下 SSR 三项硬化**：① 抖动随距离比向 0.5 收敛（`mix(dither,0.5,distRatio*0.9)`）② 深度容差 ×2×(1+4·distRatio)、前 4 步步长减半 ③ 交点用四邻域深度方差 `ValidateDepthContinuity` 校验，`distRatio>0.8` 直接接受命中（省掉细化） | `P:lib/Surface/ScreenSpaceReflections.glsl:65-76,94-112,124-145` | Astra 水下**确实走同一 SSR 路径**（`A:program/water.glsl:229` 在 `astra_underwater_interface` 内调 `water_raytrace`），但 `A:global/water/raytrace.glsl` 里 `isEyeInWater\|underwater\|distRatio\|continuity\|flicker` = 0 命中，容差/抖动全局固定（`A:global/water/raytrace.glsl:24,66,130-136`） | 在 `A:global/water/raytrace.glsl` 加 3 处条件（约 15 行）；需水下发 A/B 确认不改变现有命中连续性 |

### B 组（中代价，需接线）

无（本包可迁移的 B 级手段均已被材料覆盖或与 Astra 现有实现等价，见去重排除）。

### C 组（大工程/战略项）

| # | 机制 | 来源 file:line | Astra 未实现证据（grep 关键词与结果） | 迁移代价 |
|---|---|---|---|---|
| C1 | **SSIL 可见位掩码屏幕空间 GI**（半分辨率可选 + 两段地平线搜索 + 指数步长 + 时域位掩码累积 + bent normal 镜面遮蔽）：比 ReSTIR/RSM 便宜的一档屏幕空间间接光 | `P:lib/GI/GI_SSIL_Bitmask.glsl:1-25`（机制总览与 `SSIL_SLICES/STEPS/HALF_RES/EXP_STEPS` 开关）、`:82-180`（视空间取数/地平线扫描） | `grep -rn "SSGI\|SSIL\|ReSTIR\|RSM" A:shaders` = **0 命中**；Astra 无任何 GI 载体。注：材料已把 GI 列为长期方向且首选 RSM（Ebin GPL）与 ReSTIR 骨架，本项定位为「若立项做屏幕空间 GI，这是第三条更省的算法候选」，不重复主张方向本身 | 新 GI 子系统：gbuffer 别名、半分辨率 pass、时域历史与降噪，战略级；需先与 Astra 的 AO/阴影预算统一设计 |

### 去重排除（每条：包内出处 → 排除依据）

| 机制 | 包内出处 | 排除依据 |
|---|---|---|
| 云/天空 1/N 时域超分（棋盘相位 + Catmull-Rom 历史 + 帧数上限 + 像素速度调权） | `P:program/Deferred1.glsl:119-139,378`、`P:program/Deferred2.glsl:47-96,247-296`、`P:world0/deferred1.vsh:18` | 材料 batch2 ②-3「云时域超分」3 包印证、batch3 ⑤-2；Astra 已有 `A:global/atmosphere/cloud_temporal.glsl` + `A:program/cloud_screen.fsh`（`A:prepare1.fsh:2`）、`A:lib/effect_history.glsl:22-37` |
| 天空捕获带 + 单像素光照列内嵌既有 pass（无独立缓存 pass） | `P:program/Deferred0.glsl:272-308`、`P:world0/deferred1.vsh:19-28` | Astra 同帧天空缓存由 prepare 阶段写入（`A:prepare.fsh:2` → `A:program/sky_reflection_cache.fsh`），已是「几何前同帧」；「单像素聚合+广播」为 batch3 A 组已列（LIGHT/fantasy SALS） |
| 静态大气 3D LUT | `P:program/Deferred0.glsl:2`、`P:shaders.properties:33-36` | 材料 batch2 ②-3「静态大气资产」4 包印证 + ⑤-2 #3，已判「先做对照实验」 |
| PCSS blocker 搜索 / 接触硬化 / 世界单位半影 | `P:lib/Lighting/SunLighting.glsl:41-57` | 材料 batch1 ②-1（7 包印证）+ batch3 B（遮挡深度自适应半影）；Astra `grep "penumbra"` 0 命中属**已列未做项**，不新增主张 |
| 像素锁定阴影（世界网格量化） | `P:lib/Lighting/SunLighting.glsl:62-64` | 材料 batch3 B（simply-upscaled）已列 |
| 遮挡时才读 shadowcolor0 / 彩色阴影 tap 门控 | `P:lib/Lighting/SunLighting.glsl:77-79,102-107` | Astra 已实现（背景清单「遮挡时才读彩色阴影」；`A:global/lighting/shadowmap.glsl:152-169` 彩色/水面记录读取） |
| SSR 自适应步长 + 二分细化 + 出屏/深度退出 | `P:lib/Surface/ScreenSpaceReflections.glsl:78-160` | Astra 已有 `A:global/water/raytrace.glsl:45-137`（有限步进+递增 stride+同 texel 缓存+二分+置信度） |
| SSR 步数按 (1-roughness) 缩放 | `P:world0/deferred6.fsh:97-100` | 材料 batch1/10-02（Bliss「SSR 预算随 Fresnel 插值」已列，且 Astra 明确暂不采用） |
| 上一帧反射重投影 | `P:Settings.glsl:20-22`（无消费者，见反面 1） | 材料 batch3 B「上一帧重投影 SSR」已列；Astra 水反射历史模块 RETIRED，本轮无消费链 |
| 体积雾距离自适应步数 / 空区跳过 / 透射中断 / 阴影查表外提前 continue | `P:lib/Atmosphere/VolumetricFog.glsl:173-178,236-247,304,366` | Astra 已有（背景清单「体积雾自适应步进」；`A:global/atmosphere/volume_fog.glsl:139,195-254`） |
| 云步数分档 / 透射中断 / 密度跳过 / 按用途分预算 | `P:program/Deferred1.glsl:186-228`、`P:lib/Atmosphere/VolumetricClouds.glsl:2-33` | 材料 batch1/batch3（含 AstraLex「天空 10 步/反射 4 步」）已列；Astra 已有 `A:global/atmosphere/clouds_planar.glsl` 分档与首次命中 |
| 体素时域乒乓 + 相机搬移 + 跨帧累积 + shadow pass 体素化 | `P:shaders.properties:242-247`、`P:lib/Head/VoxelLight.inc:44-50`、`P:lib/lpv/lpv_render.glsl:14-19` | 材料 batch1 ②-4（7 包印证）+ batch3（Soft Voxels Lite「shadow pass 兼任体素化」、Amethyst 占用图）；Astra 下界已有六邻域 max + 源乒乓（`A:program/nether_light.csh:46-68`），跨帧策略 2026-10-03 文档明确暂缓 |
| GI/ReSTIR/RSM/NBGI/空间滤波全套 | `P:lib/GI/*`、`P:lib/Lighting/ReSTIR.glsl`、`P:program/SpatialFilter.comp:47-152` | 材料 batch1/batch2（RSM GI、ReSTIR 骨架、ReBLUR 降噪核）已列长期方向；Astra 无 GI 载体 |
| 屏幕空间接触阴影 / 屏幕空间阴影 | `P:lib/Lighting/SunLighting.glsl:141-200`、`P:lib/Lighting/HeldLightShadow.glsl:161-178` | 材料 batch1 ②-1（4+2 包）已列长期；手持光是特性而非本包独有优化 |
| 顶点级视口缩放实现低分效果 | `P:world0/deferred1.vsh:18` | 材料 batch3 B（ILV SSR 渲染比率 + 顶点视口缩放）已列 |
| 蓝噪声/Bayer 时序推进（golden/plastic） | `P:lib/OtherCommon/TemporalNoise.glsl:1-13` | 材料 batch3 A「R2 黄金比例低差异序列」同类已列；Astra 抖动已 CPU 化 |
| 相机位移补偿的历史深度拒绝 | `P:program/Deferred2.glsl:216-229` | 材料 batch3 云/下界时域重投影同类（相机搬移）已列；且属 GI 载体 |
| flip/延迟清空、blend off、无 alphaTest 覆写 | `P:shaders.properties:326-354`、`:79-106` | Astra 已有更细的 flip/size/blend 体系（`A:shaders.properties` 74 行 blend + RENDERTARGETS 变体）；本包无 alphaTest 行（第三方包已列） |
| 粒子独立前向缓冲 + Bloom 单取 | `P:shaders.properties:71-73`、`P:program/Post/DownSample0.glsl:84-88` | 视觉特性；性能价值是省一次全屏读，Astra bloom 已从捕获缓冲读，增量不足 |

---

## 六、无法判定

1. **TSR 档位 0/6 的预期行为**：源码层面 6 无相位表、0 除零（见反面 3），无法判定作者意图是「预留」还是坏档；不建议引用该选项结构。
2. **deferred0 全屏云天空与 deferred1/2 低分链的分工**：colortex5 被 `composite1.fsh:106,393` 当方向查询用、colortex1/2 供 deferred5/composite1 的可见天空与雾；两套输出是否重复计算、哪套最终上屏，未实机验证（反面 4 的「嫌疑」未证实）。
3. **`PRECOMPUTED_ATMOSPHERIC_SCATTERING` 的 LUT 精度与净收益**：`Final.lut` 为包内二进制资产，源码级无法评估其分辨率是否足够、与 Astra 解析天空的差值与成本比；材料已定「静态大气资产先对照」。
4. **1/N 云时域链与 TAA 的双重时域交互**：deferred2 已做时间累积，TAA 再做一次，鬼影/收敛特性无法从源码判定。
5. **RippleSim/RippleSetup 缺失**：若 `WATER_RIPPLES` 依赖外部注入宏或上游文件未随包发布，行为未知；按当前快照为死链。
6. **MC_VERSION 分支在目标环境的实际选取**：`#if MC_VERSION < 11605`（`P:shaders.properties:252`）决定走 frag 还是 compute 滤波，Iris 新版下取哪条只能实机确认。
7. **与 Bliss/Derivative 的增量边界**：本文按 README 血统声明处理，未做逐文件 diff；上表「去重排除」中凡属 Bliss/Derivative 既有机制者（如 1/N 云、捕获带、GI 链）未逐一回溯到上游文件，引用前应回上游快照核对（备注 1）。
8. **全部收益均为源码级推断**：包内无作者帧时数据，A1 的收益（水下远处反射提前接受、抖动稳定减少鬼影）与 C1 的成本均需 Astra 实机 A/B 后才可排期。
