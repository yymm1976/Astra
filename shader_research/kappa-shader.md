# Kappa Shader 5.3 研读报告（面向 Astra 的可借鉴点）

> 参考包路径：`reference_shaderpacks/kappa-shader/`。下文 Kappa 引用省略该前缀，行号均为文件真实行号；Astra 引用基于 `Astra/shaders/`。

## ① 包概览

- **名称/版本**：Kappa Shader，`value.INFO.0=v5.3`（shaders/lang/en_us.lang:2）。
- **作者**：RRe36。源文件版权头为 "Copyright (C) 2023 RRe36"（如 shaders/lib/internal.glsl:4），LICENSE 文件标注 2025。
- **许可证**：保留所有权利（LICENSE:1-2 "All Rights Reserved unless otherwise explicitly stated"）。要点（LICENSE 各节）：公开再分发只能用官方链接（§1）；私人修改允许但不得再分发（§2）；公开修改版需作者明确许可且须包含相当程度原创内容、同许可、署名（§3）；**将本项目部分源码用于另一个原创项目需作者明确许可 + 署名 + 禁止变现**（§4）。
- **风格定位**：写实/物理向旗舰。延迟渲染（gbuffers 写 GBuffer，deferred/composite 全屏重建）， Iris/OptiFine G7（shaders/shaders.properties:131-132）；内置 SSPT（屏幕空间路径追踪）+ SVGF 去噪，属"物理正确优先、性能靠分档兜底"的路线。
- **管线速览**：缓冲区用途清单集中在注释块 shaders/lib/pipeline.glsl:37-104（C0 场景色、C3 云重建/雾重建复用、C5 天空 capture、C8 云时域、C9/C10 雾时域、C11 间接光累积、C12/13 球面反射 capture）。

## ② 架构与特性清单

### 2.1 物理大气
- 真实尺度行星+大气：`planetRad = 6371e3`、`atmosDepth = 110e3`（lib/atmos/air/const.glsl:35-37），Rayleigh/Mie/臭氧系数 const.glsl:50-52；散射迭代 16 步、airmass 迭代 8 步（const.glsl:27-28）。
- 密度模型：Rayleigh 指数衰减 + 臭氧双指数（峰值 30km），并乘逐帧 `airDensityCoeff`（lib/atmos/air/density.glsl:22-33）；`getAirmass` 沿光线二次采样（density.glsl:39-65）。
- 天空渲染主函数 `atmosphericScattering`：sun+moon 双光源、Rayleigh+Klein-Nishina 相位（atmosphere.glsl:34-36, 94-95）、主循环内逐步透射+多次散射近似+行星反照弹光（atmosphere.glsl:132-170, 161, 163-165）、`ATMOS_RenderPlanet` 下用 OrenNayar+GGX 渲染行星地表并乘透射（atmosphere.glsl:122-127, 201-203）。
- 逐时刻大气动态：shaders.properties 用一天 8 时段加权出 `airDensityCoeff`（shaders.properties:343-346），日出/黄昏 Rayleigh/Mie/臭氧各不同。
- 天空低清 capture（atlas）：prepare2 一张 colortex5 同时放 clear-sky capture（下 2/3）与云反射（prepare2.fsh:602-627），分辨率约 `viewWidth/2 × viewHeight/2.5` 上限 300（shaders.properties:263-265）。

### 2.2 云
- 四层云系统（settings.glsl:49-57）：体积积云 `RSKY_SB_CloudVolume`、Cirrocumulus 平面层、Cirrus/Cirrostratus 平面层、Noctilucent 高层；几何参数集中在 lib/atmos/clouds/constants.glsl:4-22（积云 800m 起 2000m 厚）、48-83（各平面层高度/厚度/σ）。
- 天气图（weathermap）：512² 预计算到 colortex14（lib/internal.glsl:46；program/prepare/weathermap.glsl:19, 152-167），4 通道 = 底层覆盖/上层覆盖/铁砧(Anvil)/花椰菜(Cauliflower)，由湿度×温度等天气参数驱动（weathermap.glsl:86-88, 104-106）。
- 云形函数 `cloudCumulusShape`：天气图采样 + 高度分层侵蚀 + curl3D/shape3D/erosion3D 三张 3D 纹理（shaders.properties:174-176 以 TEXTURE_3D 预载）逐级侵蚀（lib/atmos/clouds/common.glsl:221-328，erosion 混合 247-255，细节侵蚀 299-312）。
- 体积云射线步进在 deferred.fsh `cloudSystem`：行星球面求交确定起止、按 `CLOUD_RENDER_LOD` 自适应步数（deferred.fsh:201-207）、透射阈值 0.05 提前退出（229）、光源 6 步指数增步 OD + 天空 4 步 OD（257-267，实现在 common.glsl:334-377，步长×2 指数）、HQ 多重散射 8 octave 能量估计（deferred.fsh:274-307）。
- 三层平面云（卷云等）也是"薄体积"：上下界间一步透射 + 3 步光照 OD（deferred.fsh:453-549），卷云形状用 curl 长度+多倍频 value 噪声（common.glsl:441-508），夜光云 common.glsl:734-778。
- 云动画时间源可选世界时间：`cloudTime = worldAnimTime * 1.8`（clouds/constants.glsl:28-29），而 `worldAnimTime = worldDay % 48 + worldTime / 24000.0`（shaders.properties:218）——云的演化与世界时间绑定，切档/重载不跳变。
- 云时域重建：3×3 checkerboard 子采样 + Catmull-Rom 历史采样 + pixel age(上限 256 帧) + 离屏/世界时间跳变重置（world0/deferred1.fsh:221-284，历史缓冲 colortex8/10 见 deferred1.fsh:22-26），闪电时向云图注入蓝紫闪亮（deferred1.fsh:279）。
- **云影**：独立 512² 云影图打包进天空 capture atlas 的 alpha 通道（internal.glsl:43-44 定义 8e3 距离/512 分辨率；prepare2.fsh:629-637 写入；40 步 marched 生成于 prepare2.fsh:518-599，雨天 `wetness` 直接压平透射 593-594）；地形直射光（deferred3.fsh:386-388）与体积雾/水内部（composite.fsh:334, 426-428）都乘它。

### 2.3 水体
- 波浪：Gerstner 变体多倍频（lib/atmos/waterWaves.glsl:49-127），振幅/陡度受天气湍流 `RWeatherParams.z` 调制（waterWaves.glsl:116），距离淡出（98-102）；另有 mode 1 简单噪声波（129-175）。
- 水面法线：8 步高度场视差（"based on spectrum by zombye"，world0/gbuffers_translucent.fsh:120-139）+ 距离自适应 dstep 差分法线（146-170）。
- 折射：composite.fsh 用 flat/细节双法线的 `refract2`（459-469）重建折射屏幕坐标，边缘平方淡出 + 深度有效性回退（498-539）。
- 体积水（水下/水内雾）：自适应步数（composite.fsh:369），每步在 shadowmap 空间步进取影（375-433），期间采样彩色阴影（419-425）并乘云影（426-428）；吸收/散射系数分离（lib/atmos/waterConst.glsl:27-36），解析积分 `attenMul`（437-440）。
- shadowcomp 水体着色：阴影 pass 内按水面上下深度差算吸收并可选投影焦散（program/shadow/comp0.fsh:120-136；投影焦散 `projectedCaustics` 用屏幕空间导数算聚焦增益 72-85；开关 `shadowcompCaustics` 默认关闭，internal.glsl:48）。
- 反射：SSR 命中用屏幕色，未命中回退到球面天空 capture（colortex12，1024×512，shaders.properties:184-185），`readSpherePositionAware` 带遮挡/位置感知（world0/composite2.fsh:275, 477-492）；粗糙面用 GGX facet 多次扰动反射（composite2.fsh:493-528）。
- 简化水雾回退 `waterFog`（lib/atmos/fog.glsl:8-19）。

### 2.4 阴影与光照
- 彩色阴影协议：shadowcolor0 预缩 0.25 存储（comp0.fsh:117-118），采样时 `mix(vec3(1.0), color.rgb * 4.0, a)`（composite.fsh:106-109），shadowtex0/1 差分判定彩色遮挡。
- 软阴影：VPS 方差阴影（`shadowVPSEnabled`，settings.glsl:123；sigma 存于 colortex3，deferred3.fsh:363-367）+ 迭代滤波（`shadowFilterIterations 15`，settings.glsl:126）；接触阴影（deferred3.fsh:349-351）；SSS 多模式（settings.glsl:127-128，deferred3.fsh:377-382）。
- 湿地面：`wetnessMode`/水坑涟漪（settings.glsl:159-160），湿表面反照率加深 `fauxPorosity`（deferred3.fsh:286-294, 345）。
- 间接光：SSPT 屏幕空间路径追踪（settings.glsl:132-140，program/deferred/sspt.fsh）+ SVGF 五 pass 去噪（settings.glsl:149-152，shaders.properties:190-194 按开关启用 deferred6-10）；SSAO 备选 `RINDIRECT_USE_SSAO`（settings.glsl:142）。
- 下界/末地：下界烟团体积+自发光（settings.glsl:87-91），末地烟辉光（settings.glsl:93-95）；world-1/world1 有独立 composite 链（shaders/world-1/composite.fsh 等）。

### 2.5 后处理
- 色调映射：`tonemapOperator ACES_AP1_SRGB` 等多算子（program/grade/grading.fsh:29），ACES 实现来自 RRe36 academy 库（grading.fsh:91 include lib/academy/aces.glsl），应用点 grading.fsh:466。
- 描评注释明确反对在色调映射后做 TAAU："Doing TAA(U) in a Tonemapped Color Space introduces lots of weird artifacts"（temporal.fsh:349-350）。
- 曝光：简单自动曝光 + `exposureComplexEnabled` 加权亮度 tile 版（program/grade/exposure.vsh:41, 57-80），带暗部/亮部百分比与权重钳制（settings.glsl:214-219），另有 `LOCAL_EXPOSURE` 局部曝光（settings.glsl:206）。
- TAA：YCC 色域邻域钳制（ClipAabb，program/post/temporal.fsh:185, 295-304）、离中心拒绝（TAA_OFFCENTER_REJECTION，temporal.fsh:311）、Catmull-Rom 历史采样 + Lanczos 当前帧上采样（temporal.fsh:322-360）；TAAU + FXAA 后处理（settings.glsl:237-239）。
- Bloom（含 bloomyFog，settings.glsl:192-194）、DoF/镜头光斑/动态模糊/晕影/普尔金耶效应（shaders.properties:60-96 的 GUI 分区）、CAS 锐化（shaders.properties:81）。

### 2.6 性能与时域
- 五档 profile：Low→Extreme **增量式继承**，每档只写相对上一档的开关增量（shaders/shaders.properties:5-9），例如 High = Medium + 体积云/水体/2048 阴影/VPS/SVGF，Extreme = Ultra + 云影 + indirectResReduction=1。
- 内部降采样全局系数 `ResolutionScale 0.75`（internal.glsl:26），雾/水 1/4 checkerboard 时域（composite.fsh:473-475, 581-586），云 1/9（deferred1.fsh:223-231），间接光 `indirectResReduction` 降采样（settings.glsl:131）。
- 程序按开关整 pass 裁剪：`program.world0/deferred1.enabled=(RSKY_SB_CloudVolume || ...)`（shaders.properties:187）。
- 时域历史校验：世界时间跳变 uniform `WorldTimeChange`（shaders.properties:315-316）令云历史整体作废（deferred1.fsh:246）。
- TAA 抖动用黄金比例/黎曼充分序列（shaders.properties:247-253，署名 Zombye）。

### 2.7 渲染 pass 顺序速览（world0）
- shadow（含 shadowcomp 水体着色，comp0.fsh）→ gbuffers（含 gbuffers_translucent 写水面波法线/半透明色到 C3，gbuffers_translucent.fsh）→ prepare/prepare2（C5 天空 capture + 云影 atlas，prepare2.fsh）→ weathermap（C14 天气图）→ deferred（体积云低清渲染 C3，deferred.fsh）→ deferred1（云时域重建，deferred1.fsh）→ deferred2/3（AO、阴影滤波与直射光合成，deferred3.fsh）→ deferred5-10（SSPT 与 SVGF，shaders.properties:189-194 按开关启用）→ composite（折射+体积雾/水+雾时域，composite.fsh）→ composite2（反射合成，composite2.fsh）→ grade（exposure/grading/final）→ post（bloom/TAA/FXAA）。
- 该顺序对应 Astra 的"前向 + composite 后处理"结构不可直接照搬，但"低清云先行 + 时域重建"与"阴影 pass 内预积分介质"两个思想与渲染器类型无关。

## ③ Astra 可借鉴点（按专项问题 a-d 组织）

1. **天气状态机（湿度/温度/湍流，世界日驱动 + 群系偏置）**
   - 描述：用 `sin/cos(worldDay*k)` 生成逐日平滑的湿度/温度/湍流三参数，叠加 `biome_category` 偏置与日内时段偏置，再喂给云覆盖、雾密度、波浪振幅、卷云类型（shaders.properties:353-398；卷云概率 419-430；群系雾偏置 437-462）。
   - 出处：shaders/shaders.properties:358-398。
   - 对应 Astra：global/atmosphere/weather.glsl（现有云影读取在 weather.glsl:139，说明该文件已承担天气门控）。
   - 迁移难点：中。逻辑本身便宜（无纹理），主要工作量是把三参数接进 Astra 云/雾/波的现有调用点，并避免与 Astra 现有雨湿系统打架。

2. **天气图预计算（512² 4 通道：覆盖/上层/铁砧/花椰菜）**
   - 描述：把"逐像素云覆盖决策"从 3D march 内搬到一张低清 pass，march 中只读图，可容纳积雨云铁砧、花椰菜顶等形态（program/prepare/weathermap.glsl:75-140, 152-167；云形消费 common.glsl:230, 249-263）。
   - 出处：program/prepare/weathermap.glsl:152-167。
   - 对应 Astra：global/atmosphere/clouds_planar.glsl（现用单张噪声纹理 + 常数阈值，clouds_planar.glsl:85-93）。
   - 迁移难点：中-高。Astra 是平面云，无需铁砧 3D 形态，但"低清覆盖图 → march 内一次采样"的结构可直接复用；需要新增一个 prepare pass 与纹理槽位。

3. **云影缓存的湿天联动与光照淡出**
   - 描述：云影图不只有云透射，还按 `wetness` 压平（雨天接近全阴）并按太阳高度淡出（prepare2.fsh:591-597），读取端地形与体积介质共用同一张图（deferred3.fsh:387；composite.fsh:427）。
   - 出处：world0/prepare2.fsh:591-597。
   - 对应 Astra：global/atmosphere/cloud_shadow_cache.glsl（Astra 已有 512 锚定缓存，cloud_shadow_cache.glsl:6-15）+ program/cloud_shadow_cache.fsh:22。
   - 迁移难点：低。Astra 缓存已存在，只需在写入端加 wetness/太阳高度调制，是纯增益小改动。

4. **体积云的多重散射能量估计与指数增步光照 OD**
   - 描述：光源 OD 用步长×2 的指数增步 6 步近似多次散射（common.glsl:334-357），散射项用 8 octave `(1-τ^p)` 能量和 + 非对称参数随 OD 演化（deferred.fsh:283-298）——这是"没有预计算传输 LUT 也能出体积感"的经典做法。
   - 出处：world0/deferred.fsh:274-307。
   - 对应 Astra：暂无体积云；若未来 Astra 升级体积云（或给平面云加 2-tap 以上光照）时参考。Astra 现平面云的两 tap 光 march 明确记载受"需要 shadow map"限制（clouds_planar.glsl:23-37 注释）。
   - 迁移难点：高（需要先有体积云载体）。仅作技术储备。

5. **shadowcomp 水体吸收 + 投影焦散进彩色阴影**
   - 描述：在 shadowcomp 里按"水面→水底"的 shadow 深度差算吸收，把着色后的阴影写进 shadowcolor0，陆地点采样彩色阴影即免费获得水下衰减色调；投影焦散（导数聚焦）可开关（comp0.fsh:120-136, 72-85）。
   - 出处：program/shadow/comp0.fsh:120-136。
   - 对应 Astra：global/water/caustics.glsl（现有解析焦散，caustics.glsl:3-10）与 global/lighting/shadowmap.glsl。
   - 迁移难点：中。Astra 已有解析焦散（按任务背景为已知特性），此条的价值是"把焦散/水色并入阴影通道"的整合思路，可减少地表侧逐像素开销；需核对 Astra shadowcolor 布局。

6. **球面天空 capture 反射 + 位置感知读取**
   - 描述：把天空+云渲染进一张等距柱状 capture（1024×512），SSR miss 时按反射方向查表，`readSpherePositionAware` 用遮挡系数与场景位置修正远距离偏差（composite2.fsh:275, 477-492；lib/frag/capture.glsl:25）。
   - 出处：world0/composite2.fsh:477-492。
   - 对应 Astra：lib/sky_reflection_cache.glsl（文件已存在；内部实现未逐一核对，不确定其查询方式是否同构）。
   - 迁移难点：低-中。Astra 已有天空反射缓存，可借鉴的是"云参与 capture + 遮挡感知读取"两个细节。

7. **复杂自动曝光（加权 tile 亮度 + 暗亮分域钳制）与局部曝光**
   - 描述：全屏 tile 亮度按画面位置二次权重平均，取暗部/亮部百分位合成曝光，配合 LOCAL_EXPOSURE 双向钳制避免局部过曝/欠曝（program/grade/exposure.vsh:41-80；settings.glsl:206-219）。
   - 出处：program/grade/exposure.vsh:57-80。
   - 对应 Astra：global/post/exposure.glsl（存在；Astra 设置项仅有 `EXPOSURE` 手动百分比与 `AUTO_EXPOSURE` 开关，lib/settings.glsl:204-206，其自动曝光实现细节未核对）。
   - 迁移难点：中。需要一个低清亮度中间缓冲与一个逐帧归约；对洞穴/日落场景观感提升明显。

8. **TAA 工程细节（YCoCg 钳制 + 离中心拒绝）**
   - 描述：历史帧先变换到 YCC 色域做 AABB 钳制（temporal.fsh:185, 295-304），再按历史像素与 texel 网格的偏心距离调整混合权重，减轻运动模糊（temporal.fsh:311, 360）；注释明确指出"在色调映射后做 TAAU 会引入伪影"（temporal.fsh:349-350）。
   - 出处：program/post/temporal.fsh:295-311。
   - 对应 Astra：lib/taa_state.glsl / lib/taa_reactive.glsl（Astra TAA 已有独立模块，具体钳制方式未核对）。
   - 迁移难点：低-中。离中心拒绝是几行改动；YCoCg 钳制若 Astra 已有则无必要。

9. **质量分档：增量式 profile（对照专项 d）**
   - 描述：`profile.High=profile.Medium <增量>` 的继承写法使每档 diff 一目了然，档位间增量 = 逐特性开关 + 分辨率/迭代数跳变（shaders.properties:5-9）：Low 关闭全部体积/SSPT，Medium +雾体积/接触阴影，High +云体积/水体/SVGF/2048 影，Ultra +大气 HQ/SSPT，Extreme +云影/4096 影。
   - 出处：shaders/shaders.properties:5-9。
   - 对应 Astra：Astra 四档 profile 为**全量枚举**（shaders.properties:424-427 每档完整列出所有选项）。两种写法等价，但增量式在加新选项时不易漏改某档。
   - 迁移难点：低。纯 shaders.properties 重写，不改 GLSL；注意 Iris 对 profile 继承的支持以 Astra 现有解析为准（Astra 若刻意全量枚举可能是为规避解析风险——不确定，需统帅确认）。

10. **云动画绑定世界时间（worldAnimTime）**
    - 描述：`worldAnimTime = worldDay % 48 + worldTime/24000`（shaders.properties:218）驱动云/雾噪声滚动（clouds/constants.glsl:28-29；composite.fsh:150-153），48 天循环、确定性、跨存档一致，且 `WorldTimeChange` 检测时间跳变作废历史（shaders.properties:315-316）。
    - 出处：shaders/shaders.properties:218。
    - 对应 Astra：global/atmosphere/clouds_planar.glsl（Astra 波浪用 frameTimeCounter，clouds 的风场时间源未核对——不确定）。
    - 迁移难点：低。一条 uniforms 定义 + 时间源替换，配合时域历史失效逻辑。

## ④ Astra 已有对应实现（对照与优劣）

- **物理大气（专项 a）**：Astra 用 `global/atmosphere/sky_minishita.glsl`（两次采样的 mini 物理大气，文件头自述"tiny spherical atmosphere, very few samples"，sky_minishita.glsl:1-12）+ `lib/sky_sh9.glsl`（9 项球谐方向性天光，sky_sh9.glsl:5-23）。Kappa 是逐像素 16 步 march + 双光源 + 多次散射近似 + 行星渲染：物理完整度显著更高，但每帧全屏成本也高一个量级。**Astra 的 SH9 思路（预投影天光）在"前向渲染 + 便宜"这点上优于 Kappa 的做法（Kappa 没有方向性天光投影，靠 capture 纹理）；大气真实感则是 Kappa 优**。不确定：Astra SH9 的投影源是解析天空还是 capture，未核对。
- **云（专项 b）**：Astra `global/atmosphere/clouds_planar.glsl`（半分辨率平面云，ASTRA_CLOUD_ALTITUDE=192 等常数 clouds_planar.glsl:56-64）+ `cloud_temporal.glsl`（独立时域历史，权重 0.90，cloud_temporal.glsl:21, 52）+ `cloud_shadow_cache.glsl`（世界空间 512 锚定缓存）。Kappa 是体积积云+三层平面云+天气图+9 相位时域。**对比**：Astra 的独立时域历史与 Kappa 的 deferred1 各自成体系，Astra 已覆盖"云与 TAA 解耦"这一最难点；Kappa 多出的是天气驱动形态、闪电增亮、云影湿天联动（③1/③3）。优劣各有，Astra 无需推倒。
- **水体（专项 c）**：Astra `global/water/`（raytrace.glsl 的 SSR 基于规范自研，raytrace.glsl:3-14；refraction.glsl、absorption.glsl、caustics.glsl 解析焦散、light_shafts.glsl 水下光束）+ `lib/solas_water.glsl`（Solas V2.2b 适配的水体光照配色，solas_water.glsl:4-5）。Kappa 是 Gerstner 波+视差+体积水阴影步进+shadowcomp 焦散，但**没有独立的水下光束模块**（不确定 Kappa 是否在水体积内隐式实现，未见专门文件）；Astra 的解析焦散 vs Kappa 默认关闭的投影焦散，Astra 默认体验更稳。**反射路径上 Kappa 的 SSR+球面 capture 混合（miss 回退 capture）比纯 SSR 稳定，值得 Astra 借鉴（③6）**。
- **阴影与光照**：Astra `global/lighting/shadowmap.glsl`（203 行，含彩色阴影选项 COLORED_SHADOWS，见 shaders.properties:424 profile 中该开关）。Kappa 的彩色阴影协议（0.25 预缩/×4 还原）与 VPS 软阴影更工程化；Astra 有 SH9 方向性天光而 Kappa 反而没有（其 `directionalLMEnabled` 默认关闭，settings.glsl:99）——**方向性天光这一点 Astra 占优**。
- **后处理**：Astra `global/post/`（bloom/exposure/fxaa/grading）+ `lib/tonemap.glsl`（含 Uchimura/AgX/ACES/Reinhard-Jodie 四算子 token，lib/settings.glsl:19-22）。Kappa 只有 ACES 系（grading.fsh:29）但配套曝光系统更完整（③7）。不确定：Astra 自动曝光的实现深度。
- **雾**：Astra `global/atmosphere/fog.glsl` + `volume_fog.glsl`（可选世界射线步进体积雾，volume_fog.glsl:7 `#ifdef VOLUMETRIC_FOG`）。Kappa 的体积雾含 3 成分（Rayleigh/Mie/Mist）动态密度 + 1/4 checkerboard 时域 + 群系雾偏置；Astra 若需升级，优先补"群系驱动的雾参数"（③1 的一部分）与雾时域。
- **性能分档（专项 d）**：见 ③9。Astra 全量枚举（shaders.properties:424-427）vs Kappa 增量继承（shaders.properties:5-9）。Astra 档位间的增量切分逻辑与 Kappa 一致（低档砍体积/反射/高分辨率影），组织方式不同。

## ⑤ 借鉴可行性（许可证层面）

LICENSE 为全权利保留（LICENSE:1-2）。**结论：禁止把 Kappa 源码（含片段）复制进 Astra；禁止"改写式搬运"后再分发而不获许可。** LICENSE §4 明确"将本项目部分源码用作另一个原创项目的一部分需作者明确许可 + 署名 + 禁止变现"。可行做法：
1. 只借鉴**算法思想、管线结构、参数组织**（如天气状态机思路、profile 增量结构、capture-atlas 布局思路），由 Astra 自行实现并注明"思路参考 Kappa"。
2. 参数数值（如 6371e3 行星半径、8.5km scale height 等物理常数）属于公有物理事实，可独立使用。
3. 如需移植任何非平凡代码段，须先取得 RRe36 书面许可——按 LICENSE §4 属硬性门槛。
（对照：Astra 已有先例是 Solas 适配并登记 THIRD-PARTY.md，lib/solas_water.glsl:4-5——Solas 许可与 Kappa 不同，不能类推。）

## ⑥ Top5 优先建议（按 提升/工作量 排序）

1. **云影缓存湿天联动**（③3）：在 Astra 现有 cloud_shadow_cache 写入端加 wetness/太阳高度调制。提升：雨天场景一致性明显；工作量：极小。
2. **群系/天气驱动的雾与空气透视参数**（③1 的雾部分）：把 biome 偏置 fog 参数法搬进 Astra 雾模块（自研实现）。提升：环境多样性；工作量：小-中。
3. **profile 增量式重构**（③9）：shaders.properties 重写为继承式，降低四档维护漏改风险。提升：工程健壮性；工作量：小（需先确认 Iris 解析兼容）。
4. **SSR miss 回退的天空 capture 查询**（③6）：Astra sky_reflection_cache 增加"SSR miss 时按方向查 capture + 遮挡感知"路径。提升：水面/湿地面反射稳定性；工作量：中。
5. **复杂自动曝光**（③7）：Astra exposure.glsl 增加 tile 亮度加权 + 暗亮分域。提升：洞穴/昼夜过渡观感；工作量：中。
（体积云多重散射 ③4 列为储备，不进 Top5——Astra 当前是平面云架构，直接收益低。）
