# Nostalgia Shader 5.1 研读报告（Astra 可借鉴点）

> 源码：`reference_shaderpacks/nostalgia-shader/`；对照对象：`Astra/shaders/`。
> 本报告只引用包内真实文件与行号，所有行号在写完后已重新打开抽查核对。

## ① 包概览

- 版本与作者：v5.1，作者 RRe36（`shaders/lang/en_US.lang:1-2`：`Nostalgia Shader by RRe36` / `v5.1`）。
- 许可证：保留所有权利（`LICENSE:1-2`：`Copyright (C) 2025 RRe36 / All Rights Reserved unless otherwise explicitly stated.`），条款为自定义版权许可（禁止复制、改编与再分发，违反可按 DMCA 追责，每个着色器文件头部均重复此声明，如 `shaders/program/grade/grading.fsh:1-18`）。
- 唯一例外：`shaders/lib/academy/` 下的 ACES 组件带 AMPAS 官方许可（`lib/academy/aces.glsl:20-49`：worldwide royalty-free non-exclusive right to copy, modify, create derivatives），允许在保留版权声明的前提下复用。
- 风格定位：「旧世代观感 + 现代管线」。现代部分是完整的 HDR 管线（ACES 色彩学、TAAU、屏幕空间路径追踪 SSPT、SVGF 去噪、体积云雾）；「旧观感」则由后期栈实现——胶片模拟曲线 RFilmEmulation（`program/grade/grading.fsh:346-376`）、可选输出位深量化 + Bayer 抖动（`program/grade/final.fsh:43-53`）、老式 BSL 镜头光斑（`grading.fsh:227-282`）。默认 4 档画质 profile，Ultra 才开 SSPT/SVGF/云阴影（`shaders/settings.glsl:5-8`）。
- 架构定位：延迟光照（gbuffers 写材质，deferred 阶段算阴影/间接光），天空以「等距柱状天空捕获图集」预渲染后在每像素应用（见 ②）。

## ② 架构与特性清单

### 世界 0 管线一览（顺序即 Iris 程序执行序）

1. gbuffers：solid/forward 写 albedo+材质（solid 走延迟、半透明走 forward），实体/手持同构。
2. deferred 阶段：skyboxPrep（天空图集+云阴影）→ skyboxApply → deferred.fsh（VPS 阴影 sigma 预计算，`world0/deferred.fsh:143`）→ deferred1/12（直接光照）→ deferred2 SSPT（可选）→ deferred3 accumulate → deferred4-8 SVGF 去噪 ×5 → deferred9 indirectAO。
3. composite 阶段：composite（reflection capture，可选）→ composite1（体积云+雾主 march，输出散射/透射率）→ composite3（雾合成+折射）→ composite4 TAAU prepass → composite5 TAA → composite6 FXAA → composite7-9 镜头光斑 → composite10-14 Bloom → composite15 色调映射+调色 → final（锐化+构图+抖动）。
   证据：`world0/composite1.fsh:22-28`（RENDERTARGETS 0,5,7,8：sceneColor/fogScattering/fogTransmittance/cloudPostFog）、`world0/composite4.fsh:22`、`world0/composite5.fsh:22`、`world0/composite6.fsh:22`、`world0/composite15.fsh:22`、`world0/final.fsh:22`。

### 滤镜 / 色彩管线（重点）

- 后期链顺序（world0）：composite4 TAAU prepass → composite5 TAA → composite6 FXAA → composite7-9 镜头光斑 → composite10-14 三级 Bloom → composite15 色调映射+调色（含曝光）→ final 锐化+抖动。证据：`world0/composite4.fsh:22`（taauPrepass）、`world0/composite5.fsh:22`（temporal）、`world0/composite15.fsh:22`（grade/grading）、`world0/final.fsh:22`（grade/final）。
- 色调映射可切换三个算子：默认 Academy 自定义 ACES（AP1→sRGB），另有 RRT-only、Hejl-Burgess、Reinhard-ACES（`program/grade/grading.fsh:29` 默认项；`grading.fsh:83-95` hejlBurgessAP1；`grading.fsh:96-111` tonemapReinhardACES；`lang/en_US.lang:259-262` 选项名）。ACES 参数可调：RRT 曝光偏置/gamma lift/glow gain/输入输出饱和偏置（`lang/en_US.lang:283-293`）。
- 调色拆成 HDR 段与 LDR 段：HDR 段做 vibrance+饱和+RGB 亮度增益（`grading.fsh:140-154` vibranceSaturation，按像素饱和度加权）；LDR 段（tonemap 之后）做亮度对比度与 gamma 曲线（`grading.fsh:156-158` brightnessContrast、`grading.fsh:136-138` applyGammaCurve；调用点 `grading.fsh:456-476`）。
- 胶片模拟 RFilmEmulation：按通道的 toe 斜率/滚降、中段增益、白区滚降，分段混合模拟胶片响应；下界用暖色 toe、主世界用冷色 toe（`grading.fsh:346-376`，维度分支在 `grading.fsh:347-355`），在 tonemap 前应用（`grading.fsh:465`）。
- 夜视药水效果实现为 Purkinje 偏移：把 HDR 转 XYZ 后算视杆亮度，向蓝绿去饱和色调混合（`grading.fsh:115-130`）。
- 暗角：径向距离 + 幂次可调（`grading.fsh:44-48` 设置；`grading.fsh:160-166` vignette 函数）。
- 输出抖动 + 位深量化：Bayer16 加到乘以 `2^screenBitdepth` 后的图上再取整，`screenBitdepth=8` 时等效普通抗色带抖动，调低即可出「老显卡色阶」（`program/grade/final.fsh:38-53`）。
- CAS 对比度自适应锐化：9-tap 方差估计对比度再加权（`final.fsh:57-87`，强度 `final.fsh:133`）。
- 摄影构图工具：三分线/自定义遮幅线绘制（`final.fsh:89-131`）。
- Bloom：三级降采样（bloom_0/1/2 各两 pass），「bloomyFog」按场景亮度把 bloom 混成雾感；雨天雨天缓冲高斯模糊后给 bloom 加权（`grading.fsh:381-421`，雨检测 `grading.fsh:180-188`）。
- 旧式镜头光斑：移植 BSL flare 生成器（`lib/frag/bslflare.glsl`），按 daytime 四段插值太阳色、遮挡检测（`grading.fsh:227-282`）。
- 曝光历史以 RGBA 的 a 通道随 TAA 缓冲一起时域传播（`grading.fsh:480-483`）。

### 曝光系统（重点）

- 两级结构：顶点阶段（composite15.vsh=exposure.vsh）做全屏 tile 统计算出一帧的平滑曝光；像素阶段（grading.fsh）再做每像素「局部曝光」插值。
- 亮度统计在 `viewSize*cube(0.25)` 分辨率的 tile 上进行（`program/grade/exposure.vsh:38`，数据来自 colortex5.a）。
- 高级模式（`settings.glsl:172` exposureComplexEnabled）：中心加权平均（`exposure.vsh:42-48` 径向四阶权重）+ 第二遍把 tile 分成亮于均值/暗于均值/中间三档，按可调百分比和权重合成加权亮度（`exposure.vsh:99-124` 分类，`exposure.vsh:132-135` 三档加权）。
- 目标曝光用 Reinhard 型标定曲线 + per-dimension 上下限钳制（`exposure.vsh:190-213`：下界 `exposureDarkClamp`、上界 `exposureBrightClamp`，主世界 0.08/8、下界 0.1/8、末地 0.1/20）。
- 非对称眼适应：变暗速度 0.075、变亮速度 0.05，按 frameTime/33ms 归一（`exposure.vsh:215-217`；像素级同款在 `grading.fsh:337-343`）。
- 局部曝光：每像素对 tile 亮度图做双三次采样，再与全局值按「亮度离均差/范围」自适应混合（`grading.fsh:286-305`）。
- 手动曝光覆盖：`settings.glsl:178-179`（manualExposureEnabled/manualExposureValue EV 值），应用为 `rcp(manualExposureValue)`（`grading.fsh:438-442`）。
- 曝光值参与 TAA：temporal 缓冲 a 通道携带曝光，TAA 在 Reinhard 编码后的空间做历史混合，保证曝光变化不炸历史（`program/post/temporal.fsh:393-400`）。

### 大气 / 雾

- 天空捕获图集：colortex10/11 为 1024x512（`shaders.properties:146-147`），equirect 投影 + 2 tile 布局（`lib/atmos/project.glsl:21-33`），deferred 阶段一次性渲染天空渐变+体积云+云阴影 alpha（`program/deferred/skyboxPrep.fsh:306-327`），之后每像素用 `projectSky` 查图。
- 云图集 alpha 通道同时烘焙云阴影图，供地面与雾采样（`skyboxPrep.fsh:327`；雾内读取 `world0/composite1.fsh:360`）。
- 体积云双层，参数化采样数/高度/厚度/最远距离（`settings.glsl:38-47`），步数按视角自适应缩短（`composite1.fsh:437-447`），fast multiscatter 近似（`settings.glsl:33`），二层可对一层投影（cloudLayerShadowing，`settings.glsl:36`）。
- 体积雾：按距离自适应步数 `fogMinSteps + stepCoeff*fogAdaptiveSteps`（`composite1.fsh:265-271`），雾密度由「时段八段插值 + 湿度」在 properties 里算成 uniform `fogDensityCoeff`（`shaders.properties:298-302`），mist 各向异性可调（`settings.glsl:54`）。
- 时域动画绑定世界时间而非客户端运行时，云在多人世界同步（`shaders.properties:203` worldAnimTime；`lang/en_US.lang:6-7` 说明）。
- 距离衰减雾（非体积）独立开关，起始/衰减可调（`settings.glsl:60-62`）。

### 水体

- 波浪：基于 noisetex 的立方插值高度场 + 4 octave 法线（`lib/atmos/waterWaves.glsl:20-40` waveNoiseCubic、`waterWaves.glsl:42-43` waterNormalOctaves/waterWaves）。
- 视差水面：沿切线视角步进高度场（Spectrum 式，`program/gbuffer/forward.fsh:223-249`），法线由高度差分（`forward.fsh:251-262`）。
- 折射：自定义 refract2 用平面法线与插值法线分别算方向（Spectrum 式，`world0/composite3.fsh:186`），折射后重新查深度防穿帮（`composite3.fsh:242-261`）。
- 水颜色/吸收/散射系数全可调（`settings.glsl:68-74`；`lang/en_US.lang:65-68` 四个系数）。

### 阴影与光照

- 变距半影阴影 VPS：deferred 阶段 6x6 采样估计遮挡深度方差，按距离放大半影半径（`world0/deferred.fsh:77-143`，`deferred.fsh:95-100` 迭代与半径，`deferred.fsh:130` sigma 计算）。
- 接触阴影：屏幕空间 16 步 stride 4 的射线步进，深度线性化用 textureGather 插值（`lib/light/contactShadow.glsl:47-75`）。
- SSPT（可选）：屏幕空间路径追踪算 GI+天光遮挡+自发光，SVGF 5 pass 去噪（`shaders.properties:155-160` 程序开关映射），默认关，fallback 为 SSAO（`settings.glsl:120-122`）。
- 光色/强度全参数化：日/月/天光/方块光各有强度与 RGB 乘子，方块光色温基准 2600K 可调（`settings.glsl:81-98`）。
- 方向性 lightmap 与光泄漏防止为可选项（`settings.glsl:77-78`）。
- 雨湿地面：三档 wetnessMode（水洼/全湿/关），水洼用噪声阈值 + 涟漪法线，材质 smoothness/emissive 被重写（`program/gbuffer/solid.fsh:279-314`），干旱生物群系权重在 properties 里插值（`shaders.properties:283-288`）。
- 风：宏阵风 + 旋转摆动的顶点动画（`lib/vertex/wind.glsl:33-42`）。

### 性能与时域

- TAAU：可调渲染比例 + Lanczos 重采样（`temporal.fsh:203-240`，置信度参数 `temporal.fsh:221`），FXAA 追加 pass（`settings.glsl:206`）。
- TAA 历史拒绝四件套：YCoCg AABB 裁剪（`temporal.fsh:186-201,289-303`）、色相角拒绝（`temporal.fsh:133-151`）、亮度差拒绝 + 抗闪烁（`temporal.fsh:364-370`）、运动中偏心拒绝（`temporal.fsh:353-354`）；历史帧数置信度存 aux 缓冲（`temporal.fsh:334-335,378-380`）。
- HDR 非变时域：TAA 输出乘曝光做 Reinhard 编码存储，曝光写入 a 通道（`temporal.fsh:393-400`）。
- 抖动序列用 Zombye 的 R2 低差异序列（`shaders.properties:193-199`）。
- 间接光默认 25% 分辨率 + reduction 可调（`settings.glsl:109`）。
- 程序级条件编译省 pass：SSPT/SVGF/capture 等按宏启停整个 program（`shaders.properties:155-163`）。
- 4 档 profile 从 Low（1024 阴影、无体积）到 Ultra 全开（`settings.glsl:5-8`）。
- 蓝噪声纹理驱动体积/阴影抖动（`shaders/image/bluenoiseUV8.dat` + `lib/frag/bluenoise.glsl`，天空图集烘焙处调用 `skyboxPrep.fsh:79`）。

### 相机类附加件（不属于 Astra 目标但说明其定位）

- DoF：30/45/60 采样三档 + 色散（`lang/en_US.lang:190-197`），焦点模式含 Auto+/Manual+（`grading.fsh:198-218` 焦点平面可视化）。
- 动态模糊：8 采样默认开（`settings.glsl:182-184`）。
- 变形宽银幕拉伸 anamorphStretch（`settings.glsl:156`）。

## ③ Astra 可借鉴点

### a) 滤镜管线分解（回应专项问题 a）

1. 「旧观感」= 胶片曲线 + 位深量化 + 抖动 + 暗角 + 老式光斑五个独立阶段，全部独立开关、按强度滑条调，互不耦合（`program/grade/grading.fsh:346-376,44-48`、`final.fsh:38-53`）。技术描述：把风格化拆成 tonemap 前的 HDR 胶片响应段与 tonemap 后的 LDR 段。对应 Astra：`Astra/shaders/lib/tonemap.glsl:191`（apply_tonemap 分发）与 `Astra/shaders/global/post/grading.glsl:175`（apply_grading）。迁移难点：低——Astra 已有五槽分级契约（grading.glsl:22），只需加一个「胶片模拟」槽在 apply_tonemap 之前；曲线本体约 30 行纯数学，可自行重写（避免照抄）。风格页可用。
2. Vibrance 与饱和度分离：vibrance 只补低饱和像素、避免肤色过饱和（`grading.fsh:140-154`）。对应 Astra：`lib/tonemap.glsl:206,211` 已有 apply_saturation/apply_vibrance 原语。迁移难点：无——只值得对比权函数实现细节，Astra 已覆盖。
3. 夜视/低照度的 Purkinje 偏移方向（`grading.fsh:115-130`）：Astra 若做夜间视觉反馈可参考「XYZ 视杆亮度→去饱和蓝绿」这一做法。对应 Astra：`global/post/grading.glsl:142`（apply_color_temperature 附近可挂）。迁移难点：中——需决定是否引入 XYZ 转换；非刚需。

### b) 曝光系统（回应专项问题 b）

4. 高级亮度统计：中心加权 + 亮/暗两档按百分比再加权，让画面「以主体定曝光」而非纯平均（`program/grade/exposure.vsh:42-48,99-135`）。对应 Astra：`global/post/exposure.glsl:82-92`（astra_ae_meter 中心高斯加权 log 平均）。迁移难点：中——Astra 已有单遍加权平均，加第二遍分类统计即可，但需要 A/B 验证收益。
5. 非对称眼适应 + 帧时间归一（`exposure.vsh:215-217`）：变暗快、变亮慢，模拟人眼暗适应更快。对应 Astra：`global/post/exposure.glsl:55-56`（AE_RATE_FAST 2.5 / AE_RATE_SLOW 0.5，方向语义相反但同思路）。迁移难点：低——Astra 已实现，仅参数语义需对齐确认。
6. 局部曝光（每像素对 tile 亮度图双三次采样再与全局混合，`grading.fsh:286-305`）：保留高光/阴影局部对比，避免全局曝光拉平画面。对应 Astra：`global/post/grading.glsl:131`（apply_auto_exposure 仅全局 gain）。迁移难点：高——需额外 tile 缓冲与 mip 化亮度图，且要过 TAA（Nostalgia 把曝光塞进 temporal.a，`temporal.fsh:393-400`）。
7. 曝光钳制分维度常量化（`exposure.vsh:190-199`）：下界/上界由设置值乘维度常数。对应 Astra：`global/post/grading.glsl:112-120`（grading_dimension_exposure）+ `exposure.glsl:47-48`（AE_MIN/MAX_GAIN）。迁移难点：低——Astra 已有维度曝光概念，把钳制按维度常量化是几行改动。

### c) 大气/雾更省的做法（回应专项问题 c）

8. 天空+云+云阴影一次性烘进 equirect 图集（1024x512，含 2 tile），之后所有像素与体积雾只需查图（`program/deferred/skyboxPrep.fsh:306-327`、`shaders.properties:146-147`、`lib/atmos/project.glsl:21-33`）。Astra 已有 `lib/sky_reflection_cache.glsl` 与 `global/atmosphere/cloud_shadow_cache.glsl`，思路相近；Nostalgia 值得对照的点是把「云阴影」放进同一图集 alpha 通道而非独立缓冲（`skyboxPrep.fsh:327`）。迁移难点：不确定——需先比对 Astra cloud_shadow_cache 的分辨率/更新频率再判断是否更省。
9. 雾步数按「视线段长/渲染距离」自适应（`composite1.fsh:265-271`），且把时段密度乘子放在 properties 预计算（`shaders.properties:298-302`），着色器内零成本。对应 Astra：`global/atmosphere/volume_fog.glsl:11-30`（步数有界但不确定是否随距离自适应）。迁移难点：低。注：Nostalgia 雾散射/透射率分缓冲存储后由 composite3 合成（`composite1.fsh:22-28` RENDERTARGETS），这种「雾算两次（体渲染一次、贴地一次）」的结构与 Astra 的 volume_main/volume_slot 是否等价，不确定。
10. 体积动画绑定世界时间（`shaders.properties:203,260-266`）：云同步多人、暂停时静止，且用 worldTime 分段函数算云光翻转。对应 Astra：`global/atmosphere/clouds_planar.glsl`（现状不确定是否用 frameTimeCounter）。迁移难点：低——uniform 换源即可，但会改变现有动态观感，属设计决策。

### d) 老式观感技法做成 Astra「风格」页（回应专项问题 d）

11. 可选输出位深量化 + Bayer 抖动（`final.fsh:38-53`）：8bit 时即普通抗色带，6/4bit 直接复古老游戏色阶。对应 Astra：`global/post/grading.glsl:218`（apply_output_dither，已有 IGN 抖动）+ `lib/bayer.glsl`。迁移难点：低——在现有 dither 前加一个 round-to-bitdepth 变体即可，天然适合风格页，不影响写实默认。
12. 暗角（`grading.fsh:160-166`）：Astra 已有但默认关（`lib/settings.glsl:232`、`program/display.fsh:162`），无需迁移，可作为风格页项直接复用。
13. 扫描线类效果 Nostalgia 没有实现（全包 grep 无 scanline）；颗粒（film grain）同样未实现——它靠位深量化与胶片曲线承担「颗粒感」。因此 Astra 风格页若要做扫描线/颗粒需另找参考源，本包只能提供「抖动量化」与「胶片曲线」两项。
14. 老式 BSL 光斑（`grading.fsh:227-282`）与摄影构图工具（`final.fsh:100-131`）：前者与 Astra 写实定位冲突且 BSL 系代码版权风险高，不建议；后者仅调试用途，无迁移价值。

## ④ Astra 已有对应实现

| Nostalgia 特性 | Astra 对照 | 两边优劣 |
|---|---|---|
| ACES AP1→sRGB tonemap（`grading.fsh:29,467`） | `lib/tonemap.glsl:176`（aces_tonemap）、`:191` 分发，默认 Uchimura | Astra 四算子可选且有 AgX；Nostalgia 的 ACES 参数面更全（RRT bias/lift/sat 前后段分离，`lang/en_US.lang:283-293`）。不确定 Astra 的 aces_tonemap 是否为 Narkowicz 简化版（`:170` rrt_and_odt_fit 命名一致，疑似），若追求 Nostalgia 观感需换 AMPAS 原版——其许可允许（`lib/academy/aces.glsl:20-49`） |
| Vibrance/饱和分离（`grading.fsh:140-154`） | `lib/tonemap.glsl:206-220` 原语 + `lib/settings.glsl:209,211` 滑条 | 等价，Astra 已覆盖 |
| 亮度/对比/gamma 分级（`grading.fsh:136-158`） | `global/post/grading.glsl:163`（apply_tonal_balance）、`lib/settings.glsl:213` | Astra 多了色温滑条（`settings.glsl:215`）与维度分级（`grading.glsl:112-120`），分级框架不逊于对方 |
| 自动曝光+眼适应（`exposure.vsh:190-217`） | `global/post/exposure.glsl:82-92` 计光、`global/post/grading.glsl:131` 挂接；默认关（`lib/settings.glsl:206`） | Nostalgia 默认开且是产品核心观感；Astra 实现已具备（有界 gain、双速率适应、log 编码防浮点抖动 `exposure.glsl:62-69`），差在「是否默认开」与「局部曝光」。两边亮暗统计细节孰优不确定（需 A/B） |
| TAA 四重拒绝 + TAAU（`temporal.fsh:203-387`） | `lib/taa_state.glsl`、`lib/taa_reactive.glsl`、`program/taa_resolve.fsh`；抖动为 8 帧 Halton（`lib/taa_jitter.glsl:4`） | Nostalgia 的色相角拒绝与曝光不变历史编码是明确亮点；Astra 的 reactive 拒绝思路不同，孰优不确定，未逐行比对 Astra resolve，不妄断 |
| 天空图集（`skyboxPrep.fsh:306-327`） | `lib/sky_reflection_cache.glsl`、`program/sky_irradiance.fsh` | 思路同族；Astra 另有 SH9 方向性天光（`lib/sky_sh9.glsl`），天光质量预期更高；云阴影缓存方式差异见 ③-8 |
| 体积雾自适应步数（`composite1.fsh:265-271`） | `global/atmosphere/volume_fog.glsl:11-30` 有界步长 | 步数自适应程度不确定，需读 Astra march 循环才能下结论 |
| 水波/视差/折射（`forward.fsh:223-262`、`composite3.fsh:186-261`） | `lib/solas_water.glsl`、`global/water/surface.glsl`、`global/water/refraction.glsl` | Astra 有 SSR+解析焦散+水下光束，水体规模大于本包；本包视差水面（per-pixel 高度步进）是否 Astra 已有，不确定 |
| 变距半影阴影（`world0/deferred.fsh:77-143`） | `global/lighting/shadowmap.glsl`（含彩色阴影 tint，`:47`） | Astra 的彩色阴影（shadowcolor0 GBA tint）是本包没有的；本包 VPS 软度是否 Astra 已等价实现，不确定 |
| 雨湿地面（`solid.fsh:279-314`） | `lib/wet_material.glsl`、`global/atmosphere/weather.glsl` | Astra 有雨湿系统，细节对比未做 |
| 输出抖动（`final.fsh:45-53`） | `global/post/grading.glsl:218`（IGN）+ `lib/bayer.glsl` | Astra 默认更现代（IGN），缺的是「可调位深」这一复古项 |
| Bloom 三级 + bloomyFog（`grading.fsh:381-421`） | `global/post/bloom.glsl`、`program/composite*.fsh` | Astra 2-pass；Nostalgia 三级链更平滑，收益不确定 |
| 风摆顶点动画（`lib/vertex/wind.glsl:33-42`） | `global/lighting/wind.glsl` | 两边都有；Nostalgia 用「宏阵风正弦+XY 旋转」结构，细节孰优未比对 |
| 接触阴影（`lib/light/contactShadow.glsl:47-75`） | 不确定 Astra 是否有屏幕空间接触阴影 | Nostalgia 16 步 stride 4，需查 Astra `global/lighting/shadowmap.glsl` 是否含同类 |
| 维度处理：下界/末地独立环境色滑条（`settings.glsl:25` 对应 DIMENSIONS 屏；`lang/en_US.lang:70-79`） | `global/dimension/nether.glsl`、`end.glsl` | Astra 维度光照规模（体素彩光/黑洞天空）远超本包；本包胜在用户可调性（RGB 滑条直出） |

## ⑤ 借鉴可行性（许可证层面）

- 包主体：保留所有权利的自定义许可（`LICENSE:1-2`，文件头同款声明如 `grading.fsh:1-18`）——禁止复制、改编、衍生。结论：**不得抄代码、不得逐行翻译、不得大段摘录 GLSL 进 Astra**；仅允许「技术思路级」借鉴（算法思想、阶段划分、参数化方式、管线结构），实现须自行从论文/数学定义重写。
- `lib/academy/`（ACES）：AMPAS 许可明确允许复制/修改/衍生，条件是保留版权声明与免责声明（`lib/academy/aces.glsl:20-49`）。结论：Astra 若引入 Academy 原版 ACES，可基于该文件族改写，但需在文件中保留 AMPAS 版权与许可文本。
- `lib/frag/bslflare.glsl` 是从 BSL 移植的第三方代码（同属保留所有权利体系），风险最高，直接排除。

## ⑥ Top5 优先建议（按 提升/工作量 排序）

1. **风格页：位深量化抖动 + 胶片模拟曲线两个开关**——工作量最低（grading.glsl 加一个槽 + settings 两个枚举，约半天），把「旧观感」做成可选风格而不动写实默认（对应 ③-1、③-11）。
2. **自动曝光默认重估 + 维度化钳制**——Astra 实现已完备（exposure.glsl），只需 A/B 决定是否默认开、并按维度常量化上下限（③-4、③-7），收益是开箱观感一致性，工作量小时级。
3. **ACES 参数面补全**——给 ACES 算子加输入曝光偏置/前段饱和等参数（Nostalgia 的做法见 `lang/en_US.lang:283-293`），配合 1 的风格页；中等工作量，观感控制力提升明显。
4. **TAA 色相角拒绝 + 曝光不变历史编码**——Nostalgia 的 hue rejection（`temporal.fsh:133-151,311`）与 Reinhard 空间混合（`temporal.fsh:393-400`）可显著减少彩色闪烁与曝光跳变炸历史；需读懂 Astra taa_resolve 后决定挂钩点，工作量中等偏上。
5. **云阴影并入天空缓存 alpha 通道**（③-8）——若 Astra 当前云阴影是独立 pass/缓冲，合并可省一张缓冲与一遍填充；工作量中，收益取决于现有 cloud_shadow_cache 的实现（需先核实）。

不建议迁移：SSPT/SVGF（Astra 走前向+AO 路线，架构不合）、视差水面（与 solas_water 体系冲突）、BSL 光斑、构图工具。
