# Solas Shader 3.7b 研究报告（面向 Astra）

> 引用格式：`shaders/…:行号` 均指 `reference_shaderpacks/solas-shader/` 下的文件；`Astra/…:行号` 指本工作区 Astra 包。
> 调研日期：2026-10-02。Astra 现持版本经其文件头自证为 **Solas V2.2b**（`Astra/shaders/lib/solas_water.glsl:4-5`），本报告重点回答 3.7b 相对它的分化。

## ① 包概览

- **名称/版本**：Solas Shader 3.7b（版本号来自本任务指定；包内 `drm/drm.readme` 与 lang 均未写版本号，包内未见 LICENSE 文件）。
- **作者**：Septonious（`drm/drm.readme:1`；`shaders/shaders.properties:21` 设置页首项 `SOLAS_BY_SEPTONIOUS`）。
- **分发声明**：仅有 CurseForge 与 Modrinth 两个官方下载源，出现在其它包内即视为"被盗代码"（`drm/drm.readme:2-3`）；lang 中 GitHub/Discord 链接仅作为联系渠道出现（`shaders/lang/en_US.lang` 内 `option.SOLAS_BY_SEPTONIOUS.comment`）。
- **许可证**：包内无开源许可证文本，按"保留所有权利（默认版权）"对待。Astra 侧的 `Astra/THIRD-PARTY.md:28` 也将其 V2.2b 登记为"未声明（默认版权）"并标了 REWRITE REQUIRED。含义：**读思路=可；抄代码=未获授权；改编后再发布=需作者许可**（详见⑤）。
- **风格定位**：写实自然风光向、重"氛围"（云/极光/星野/体积光），Iris 专用（含 Voxy、Distant Horizons 支持：`shaders/programs/voxyOpaque.glsl`、`shaders/programs/dh_water.glsl`）。档位 LOW→ULTRA（`shaders/shaders.properties:14-17`），默认 HIGH；设置项极多（8 屏，`shaders/shaders.properties:21-112`），几乎每个视觉量都可调。
- **代码形态**：所有 program 是 5 行壳文件 include 到 `shaders/programs/*.glsl`；设置集中在 `shaders/lib/common.glsl`（无独立 settings 文件）。

## ② 架构与特性清单

### 大气 / 云

- 体积云 + **动态天气驱动**：云量/云高/云厚/密度由 worldDay 多频正弦波函数逐日演化（`shaders/lib/atmosphere/volumetricClouds.glsl:8-24`）；云体垂直剖面用 LocalTop/BottomPenalty/TopPenalty 三段 smoothstep 塑形（`volumetricClouds.glsl:29-47`）。
- 平面云：3 套度噪声（base/breakup/detail）+ 域扭曲（sin/cos warp）+ 阈值 smoothstep（`shaders/lib/atmosphere/planarClouds.glsl:7-22,42-46`）；云照明用"沿光线偏移再采样一次噪声"求差近似受光面（`planarClouds.glsl:51,62-63`）。
- 极光：体积化 `computeVolumetricAurora`（`shaders/lib/atmosphere/aurora.glsl:62`）；可见度由"地磁指数 kpIndex"驱动——kpIndex 由 `worldDay` 取模合成，雪天加成，红相/绿相双色随 kp 演化（`planarClouds.glsl:73-108`），并可反哺云的照明色（`planarClouds.glsl:114-118`）。
- 雾：单一 `getNormalFog` 按维度分支；主世界密度由时间、群系 uniform（`shaders/shaders.properties:169-183` 的 isSnowy/isDesert/isSwamp…）与噪声漂移共同调制，含高度指数衰减（`shaders/lib/atmosphere/fog.glsl:45-70`）；末地雾的方向域沿 x 轴倾斜并藏有两个彩蛋（`fog.glsl:127-137`）。
- 星野/黑洞/流星：程序化星格 + **末地黑洞引力透镜**（星光域按视线-黑洞角 `pow10(pow32(VoL))` 收缩，`shaders/lib/atmosphere/stars.glsl:16-20`，星体本身挖洞 `stars.glsl:40-43`）；流星注明移植自 Euphoria Patches（经作者同意，`stars.glsl:48-49`）；末地星云以黑洞坐标为原点展开（`shaders/lib/atmosphere/endNebula.glsl:25`）。
- 天空：`getAtmosphere` 在 deferred1/water 统一调用（`shaders/programs/deferred1.glsl:220`、`shaders/programs/gbuffers_water.glsl:256`）。
- 原版云兼容开关与云雾/透明度设置（`shaders/shaders.properties:25`），shader 云与原版云二选一（`shaders/shaders.properties:10` `clouds=off`）。
- DH/Voxy 全套等价 program（`shaders/programs/dh_terrain.glsl`、`dh_water.glsl`、`voxyOpaque.glsl`、`voxyTranslucent.glsl`），DH 深度统一进雾/云/VL 的深度链（`shaders/lib/atmosphere/volumetrics.glsl:85-101`）。

### 水体

- **水波**：高度场 = 两层 noisetex 反向流动叠加，3 种风格可选（模式 3 用斜切坐标产生各向异性波向，`shaders/lib/water/waterNormals.glsl:16-19`）；`WATER_NORMAL_DETAIL` 控制两层混合、`WATER_NORMAL_BUMP` 控幅、`WATER_NORMAL_OFFSET` 控梯度步长（`common.glsl:458-462`）；**雨天波幅增强** `noise * (WATER_NORMAL_BUMP + wetness * 0.5)`（`waterNormals.glsl:26-30`）；4 步视差偏移（`waterNormals.glsl:33-42`）+ 4 tap 中心差分法线（`waterNormals.glsl:47-55`），法线强度按 Fresnel 衰减 `0.35 * (1.0 - pow8(fresnel))`（`waterNormals.glsl:57`）。
- **焦散**：与水面共用同一高度场， opposing-gradient 五点曲率取正部（`shaders/lib/water/waterCaustics.glsl:36-43`），在 shadow pass 烘进 shadowcolor0（`shaders/programs/shadow.glsl:63-71`，强度 `WATER_CAUSTICS_STRENGTH`），随彩色阴影自然进入水下照明与体积光束。
- **水下吸收/雾**：分段通道吸收——红按吸收一次方、绿按平方×0.5、全通道立方×0.5（`shaders/lib/water/waterFog.glsl:2-6`）：

  ```glsl
  colorMult.r *= 1.0 - absorption;
  colorMult.g *= 1.0 - absorption * absorption * 0.5;
  colorMult *= 1.0 - absorption * absorption * absorption * 0.5;
  ```

  雾量 `1-exp(WATER_FOG_EXPONENT * …)` 双指数可调（`waterFog.glsl:8-9`，`common.glsl:466-467`）；水下洞穴 glare 用 shadowFade 加门控（`waterFog.glsl:19-26`）； blindness/darkness 抑制（`waterFog.glsl:32-37`）。
- **水识别与折射**：`mc_Entity` ID `mat == 10001`（`shaders/programs/gbuffers_water.glsl:174`，`shaders/block.properties:3`）；水面把折射偏移编码进法线八面体写入 buffer2，连同水掩码 `refraction * water, water * 0.4 + 0.4`（`gbuffers_water.glsl:235-239,307-310`）；composite3 解码后按 `(0.79,0.81)` 魔数带识别水再搬移颜色与深度（`shaders/programs/composite3.glsl:38-55`）。
- **反射/斯涅尔窗**：SSR + 天空盒回退（`gbuffers_water.glsl:265-277`，`WATER_REFLECTIONS` → `lib/pbr/raytracer.glsl`）；水下仰视用 `pow4(length(worldPos.xz)*0.05)` 拟斯涅尔窗收 Fresnel（`gbuffers_water.glsl:268-272`）。
- 缓冲布局：colortex3 = RGBA16 "PBR 标量 + 水折射掩码"，colortex7 = RGBA16 Fresnel 数据，colortex1 = RGB8 存原始半透明层（`shaders/programs/final.glsl:31-36`）。

### 阴影与光照

- 硬件比较阴影 + 旋转圆盘 2 样本 PCF，抖动 = 蓝噪声 + TAA 黄金比逐帧旋转（`shaders/lib/lighting/shadows.glsl:9-13,41-58`）。
- 彩色阴影：shadowtex1/shadowcolor0 组合，**雨天整体关闭染色** `doShadowColor -= wetness`（`shadows.glsl:23-26`）；shadow pass 内烘焙半透明染色与焦散（`shaders/programs/shadow.glsl:58-74`）。
- SSAO：deferred 全屏法线由深度差分重建（`shaders/lib/lighting/ambientOcclusion.glsl:13-54`），AO 用 4 方向弧线步进 × 距离/FOV 缩放（`ambientOcclusion.glsl:56-115`），结果经 4 tap 深度加权上采样消费（`ambientOcclusion.glsl:117-149`）；deferred program 仅在 SSAO 开启时启用（`shaders/shaders.properties:222-224`）。
- 屏幕空间阴影：BSL 式指数步长 16 步射线（`shaders/lib/lighting/screenSpaceShadows.glsl:3-16`）。
- SSS：叶/植被 wrap 光照，`NoL = fmix(NoL, sss*…, subsurface * shadowVisibility * 0.65)`（`shaders/lib/lighting/gbuffersLighting.glsl:94-108`）。
- 体积光：指数分布步进 `currentDist = exp2(dither); *=2`（`shaders/lib/atmosphere/volumetrics.glsl:192-194`）；**室内探测**——沿屏幕一条线采 10 个深度求均值推 closedSpaceFactor 增强室内 VL（`volumetrics.glsl:41-47`）；云影 crepuscular rays（`volumetrics.glsl:236-244`）；LPV 雾与 VL 同循环双采样（`volumetrics.glsl:249-283`）。
- 手持光源 DYNAMIC_HANDLIGHT（`shaders/lib/lighting/handlight.glsl`，`gbuffers_water.glsl:122-125` 处挂接）。

### 后处理

- TAA：Catmull-Rom 历史重采样（Filmic SMAA，`shaders/lib/antialiasing/taa.glsl:13-38`）+ YCoCg 色域 8 邻域 AABB 裁剪（`taa.glsl:40-82`）+ 速度指数衰减混合（`taa.glsl:98-105`），在 composite15 应用（`shaders/programs/composite15.glsl:72`）。
- Bloom：5 级 tile，`bloom *= bloom; bloom *= bloom * 32.0` 的四次方对比度整形（`shaders/lib/post/getBloom.glsl:5`），按维度分强度（`getBloom.glsl:19-40`）；mipmap 在 composite14 开启（`shaders/programs/composite14.glsl:68-69`）。
- 色调映射：Uncharted2 变体 + 饱和/自然度分离控制（`shaders/lib/post/tonemap.glsl:1-24`，默认值 `common.glsl:447-451`）。
- 其余：DOF/动态模糊/镜头光晕（`lib/post/computeDOF.glsl`、`motionBlur.glsl`、`lensFlare.glsl` 215 行）、锐化与色差在 final（`shaders/programs/final.glsl:49-58`）、FXAA（`lib/antialiasing/fxaa.glsl`，默认关，`common.glsl:433`）。

### 维度特化

- 下界：voxel 洪泛彩光——compute shader `shadowcomp.csh`，8³ workgroup，双缓冲隔帧乒乓（`shaders/programs/shadowcomp.glsl:57-94`），发光体染色查表（`shadowcomp.glsl:74-77`，表在 `lib/vx/blocklightColor.glsl`）；体素图用 Iris custom images 声明 r8ui/rgba16f（`shaders/shaders.properties:193-219`），五个容量档（128→512）；LPV 雾在下界×0.75 强度（`volumetrics.glsl:142-143`）；下界烟雾体积化（`volumetrics.glsl:1-16,286-292`，`NETHER_SMOKE` 档 ULTRA 外可开）。
- 末地：`END_DISK` 末地盘状体积云，黑洞扭曲场参与云高（`volumetricClouds.glsl:429-470`）；黑洞/星云/闪光配置（`shaders/shaders.properties:35`）；末地专用太阳角（`common.glsl:12-13` `SUN_ANGLE_END`）；末地闪光 uniform（`shaders/programs/deferred1.glsl:38-41`）。
- 三维度共用同一套 program 文件树（world-1/world1 薄壳目录），维度差异全部走 `#ifdef NETHER/END`。

- 维度特化之外的通用底座：
  - 自带噪声贴图 `tex/noise.png`（`shaders/shaders.properties:126`）；银河贴图借 deferred depthtex2 通道在 HQ 下挂载（`shaders/shaders.properties:128-130`）。
  - 半透明/粒子 alphaTest 全面放宽以保留低不透明度（`shaders/shaders.properties:133-143`）；信标光柱写入深度（`shaders/shaders.properties:146`）。
  - 植被/树叶摆动四参数（`shaders/shaders.properties:112`）。
  - PBR 材质库按方块族拆分约 50 个文件（`shaders/lib/pbr/blocks/`：planks/copper/ores/terracotta…），另有 IPBR 程序化高光/发光/法线三件套（`GENERATED_SPECULAR/GENERATED_EMISSION/GENERATED_NORMALS`，法线由 albedo 梯度生成，`shaders/lib/pbr/generatedNormals.glsl`），视差与自阴影（`shaders/programs/gbuffers_terrain.glsl:150-156`）。
  - 颜色系统完全数据驱动：光照/环境光按 6 个时段 × RGB + 强度、按方块类型的 LPV 染色大表（`shaders/shaders.properties:53-99`），全部经设置页暴露。

### 性能与时域

- 档位预设串联（`shaders/shaders.properties:14-17`）；program 级裁剪：SSAO、shadowcomp 按开关启停（`shaders/shaders.properties:222-227`）。
- 云影 `getCloudShadow` 供 VL 与水面阴影共用，随 VC 参数联动（`shaders/lib/atmosphere/volumetrics.glsl:241` 调用点；实现在 `shaders/lib/lighting/cloudShadows.glsl`）。
- 自定义时间轴 uniform：timeAngle 线性化 + shadowFade 晨昏过渡（`shaders/shaders.properties:149-162`）——Astra 的 `astraSolas*` 系列 uniform 即改写自这一段。
- 抖动时域化统一模式：蓝噪声 + 黄金比 × frameCounter（`shadows.glsl:46-48`、`deferred1.glsl:240-242`）。
- VL 单帧一步完成（composite1 内，`shaders/programs/composite1.glsl:124,137`），**无**独立时域历史；Astra 的水下光束独立历史卷积是 Astra 自己的增强。
- 半分辨率技巧较少（AO 有 LOD 分支、bloom 走 tile），整体以全分辨率 + 少样本为主。

## ③ Astra 可借鉴点

**a) 水波生成（对照 `Astra/shaders/lib/solas_water.glsl` 及 `global/water/caustics.glsl`）**
1. 雨天波幅耦合：`waterNormals.glsl:26-30` 把 wetness 直接加进波幅，海面在雨中变糙。Astra 的雨效果走地面润湿/水洼涟漪（`Astra/shaders/global/atmosphere/weather.glsl`、`lib/wet_material.glsl:7-22`），开阔水面无此响应。对应模块：`Astra/shaders/global/water/caustics.glsl`（`solas_water_height` 的幅值项）。难点：低（一行幅值混合 + 与 `astraRainFactor` 接口对接）。
2. 各向异性波模式（3.7b 的 `WATER_NORMALS=3`）：斜切噪声坐标 + 平方整形（`waterNormals.glsl:16-19`），波纹有主导风向；Astra 现为固定 `.g/.g` 两层（`caustics.glsl:9-11`）。可作为 Astra `WATER_WAVES` 的风格档。难点：低（纯噪声采样改造，但需过 Steadfast 派生的 surface.glsl 许可界线，只借"坐标斜切"思路即可）。
3. Fresnel 衰减法线强度（`waterNormals.glsl:57`）：掠射角锁细节、正视角保平滑；Astra 用 footprint 滤波（`caustics.glsl:17-27`）达类似目的但机制不同，可叠加。难点：低。
4. 波形风格三选 + detail/bump/offset/speed 四旋钮的**暴露方式**（`common.glsl:458-462` + `shaders.properties:39`）：Astra 水参数较少，可借鉴其"一个高度场派生法线+焦散+涟漪"的参数面设计。难点：低-中（动 settings 与 lang）。
5. 斯涅尔窗（`gbuffers_water.glsl:268-272`）：水下仰视时按到水面的水平距离压 Fresnel，制造头顶透光孔。Astra 的 `global/water/optics.glsl` 是否已有等价项**不确定**（未核对），若无值得补。难点：低。

**b) 水面缓冲格式与水识别（对照 `Astra/shaders/lib/water_buffer_formats.glsl`）**
- Solas 用 `mc_Entity` 数字 ID（`gbuffers_water.glsl:172-175`）+ composite3 魔数带 `(0.79,0.81)` 识别水（`composite3.glsl:49`）——脆弱但零额外缓冲。Astra 用 material 位域（`Astra/shaders/program/lit.fsh:107` `material == 1u`）+ colortex3 标志位 `& 128u`（`Astra/shaders/global/water/light_shafts.glsl:17-18`），更稳。
- 3.7b 相对 Astra 所持旧版的**可见分化**：折射掩码与 PBR 标量合并进同一 RGBA16 colortex3（`final.glsl:33`）、冰/玻璃/传送门同 pass 分支处理（`gbuffers_water.glsl:172-176`）、体积云与半透明水面按云深度 discard 融合（`gbuffers_water.glsl:210-224`）。Astra 的 `water_buffer_formats.glsl:6-19` 只管格式精度，无对应物。**结论：Astra 体系更优，不建议反向迁移；仅"体积云与水面先后排序 discard"思路在 Astra 平面云半分辨率合成时可参考。**难点：不适用。

**c) 水下视觉（对照 `Astra/shaders/global/water/light_shafts.glsl`）**
1. 分通道吸收谱（`waterFog.glsl:2-6`）：Astra 的 `solas_water_fog` 是单标量指数（`Astra/shaders/lib/solas_water.glsl:83-90`，注释自认"密度映射更轻"）。把 r/g/全通道三段吸收搬进 `Astra/shaders/global/water/absorption.glsl`（其 THIRD-PARTY.md:75 本就登记过 Solas waterFog 血统）。难点：低-中（要重校 Astra 现有密度常数与 `medium_state.glsl` 的耦合）。
2. 可调指数 `WATER_FOG_EXPONENT`（`waterFog.glsl:3,9`）：清水/浊水一旋钮。难点：低。
3. 水下洞穴 glare 门控 caveFactor（`waterFog.glsl:19-26`）：Astra 已有 glare（`solas_water.glsl:94-97`）但无"洞口越深越亮"的空间门控。难点：低。
4. VL 水下参数组（`volumetrics.glsl:54-63`：水下 VoU/强度/距离因子/持久度四项修正）——Astra `light_shafts.glsl:37-42` 已吸收同等响应，**此项无新增可借**；但"closedSpaceFactor 用屏幕深度探针判室内"（`volumetrics.glsl:41-47`）Astra 无，可给水下/室内光束加成。难点：中（Astra 光束已改独立历史管线，插入点在 march 前的 visibility 项）。

**d) 非水系统的轻量技术**
1. Bloom 四次方对比度整形 + 逐维度强度（`getBloom.glsl:5,19-26`）：两行代码级。对应 `Astra/shaders/global/water/bloom_resolve.glsl`。难点：低。
2. AO 的法线重建 + 方向弧 AO（`ambientOcclusion.glsl:56-115`）：比 Astra 现有屏幕空间 AO 更抗带状；其"深度加权 4 tap 上采样"（`ambientOcclusion.glsl:137-146`）若 Astra 的 `lib/ao_resolve.glsl` 未含可借用。难点：中（Astra AO 与材质耦合，见④不确定性）。
3. TAA Catmull-Rom 历史采样（`taa.glsl:13-38`）：同时承担抗锯齿与轻微锐化，双通道 5 tap。对应 `Astra/shaders/lib/taa_state.glsl`。难点：中（Astra TAA 状态机不同）。
4. 彩色阴影雨天自动关闭（`shadows.glsl:23-26`）：一行省时 + 视觉更自然。对应 `Astra/shaders/global/lighting/shadowmap.glsl`。难点：低。
5. 极光系统（`aurora.glsl:62` + `planarClouds.glsl:73-108`）：kpIndex 天气叙事 + 体积化渲染，是 3.7b 对 Astra 特性表外最大增量。对应 `Astra/shaders/global/atmosphere/`（新模块）。难点：高。
6. 下界烟雾体积化（`volumetrics.glsl:1-16`）：纯噪声高度分层烟，无需体素体。对应 `Astra/shaders/global/dimension/nether_volume.glsl`。难点：中。
7. 雨水洼的法线扰动按孔隙度混合（`gbuffers_terrain.glsl:256-273`）：Astra 有润湿材质但可借"孔隙度调制法线混入比"的加权式。难点：低。
8. 云影接入水面前向光照（`gbuffers_water.glsl:118-120` 挂接 `lib/lighting/cloudShadows.glsl`）：Astra 的 `shadowmap.glsl`/`sky_reflection_cache.glsl` 若未采样云影，大场景水面高光会与云脱节。Astra 是否已有云影**不确定**。难点：中。
9. 流星（`stars.glsl:48` 起）：效果完成度高，但包内注明移植自 Euphoria Patches 且"经作者同意"——许可证上是他人授权链，Astra 只可借"周期+轨迹表"的结构思路自行实现。难点：低-中。

## ④ Astra 已有对应实现

| Solas 3.7b | Astra 对照 | 两边优劣 |
|---|---|---|
| 水光照/雾/色调（`waterFog.glsl`、`tonemap.glsl`） | `Astra/shaders/lib/solas_water.glsl:19-119` | 同源（V2.2b）。Solas 多用户旋钮与分通道吸收；Astra 把合成序保持 sqrt 域并接口化，工程上更干净 |
| 波形+焦散（`waterNormals.glsl`、`waterCaustics.glsl`、`shadow.glsl` 烘焙） | `Astra/shaders/global/water/caustics.glsl:5-52` | 五点曲率焦散两边一致；Astra 多 footprint 抗闪烁滤波与 surface-only 波段，Solas 多雨天波幅与三种风格 |
| 水下光束（`composite1`+`volumetrics.glsl`） | `Astra/shaders/global/water/light_shafts.glsl:27-117` | Solas 单帧全分辨率；Astra 半/低分辨率 + 独立体积历史 + 距离拒绝解卷（`light_shafts.glsl:100-116`），质量更高、成本更低——Astra 领先 |
| 水识别/折射（`composite3.glsl`） | `Astra/shaders/program/lit.fsh:107`、`global/water/refraction.glsl`、`lib/water_buffer_formats.glsl` | Astra 位域 + HDR 格式更稳；Solas 魔数带是历史包袱 |
| 彩色阴影（`shadow.glsl` program） | `Astra/shaders/global/lighting/shadowmap.glsl` | 两边都有；Solas 雨关染色的细节 Astra 是否有**不确定**（未逐行核对 shadowmap.glsl 的雨天分支） |
| 平面云（`planarClouds.glsl` 123 行） | `Astra/shaders/global/atmosphere/clouds_planar.glsl`（412 行，半分辨率+独立时域历史） | Astra 规模与时域领先；Solas 有极光反哺云色与域扭曲造型（`planarClouds.glsl:42-46,114-118`），Astra 是否已含类似扭曲**不确定** |
| 体积云（`volumetricClouds.glsl` 548 行） | Astra 为半分辨率平面云方案，无体积云（任务背景声明） | Solas 独有；仅可借其动态天气函数（③-5 关联项） |
| SSAO/SSS/手持光（`ambientOcclusion.glsl` 等） | `Astra/shaders/lib/ao_material.glsl`、`ao_resolve.glsl` | Astra AO 与材质系统整合；Solas 的法线重建弧线 AO 精度可能更高，**不确定**，需实测对比 |
| 体积光LPV/体素彩光（`shadowcomp.glsl`+`volumetrics.glsl`） | `Astra/shaders/global/dimension/nether_colored_light.glsl`、`nether_volume.glsl` | 同为 compute 洪泛；Solas 五档容量 + 隔帧乒乓（`shadowcomp.glsl:64-72`），Astra 九段分区——体系不同，Solas 的"发光体染色查表×洪泛半径"（`shadowcomp.glsl:74-77`）值得对照 |
| 末地天空/黑洞（`stars.glsl`、`endNebula.glsl`、END_DISK） | `Astra/shaders/global/dimension/end_blackhole.glsl`、`end_kerr.glsl`、`end_system.glsl` | Astra 的 Kerr 黑洞物理化程度远超 Solas 的 pow 挖洞；Solas 的"星云以黑洞为原点"构图（`endNebula.glsl:25`）或可作构图参考 |
| Bloom/后处理链 | `Astra/shaders/global/water/bloom_capture.glsl`、`bloom_resolve.glsl`、`global/post/grading.glsl`、`lib/tonemap.glsl` | Astra 有颜色分级；Solas 多 DOF/动态模糊/镜头光晕/色差（③-d-1 可低成本补） |
| 主世界天空 | `Astra/shaders/global/atmosphere/sky_gradient.glsl`（289 行）+ `lib/sky_sh9.glsl`（205 行） | Astra 的 SH9 方向性天光是 Solas 没有的体系（Solas 天光走分时段常量表 + skyColor 混合，`waterFog.glsl` 内可见）；Solas 的太阳散射宽度/密度公式与 Astra `solas_water_sky`（`lib/solas_water.glsl:46-81`）同源，3.7b 的 `sky.glsl` 仅 53 行，未见结构性增强 |
| 雾与空气透视 | `Astra/shaders/global/atmosphere/weather.glsl`、`global/post/godrays.glsl` | Solas 的群系 uniform 驱动密度（`fog.glsl:57-58`）与高度指数（`fog.glsl:55`）粒度更细；Astra 的雾结构**未逐行核对**，孰优不确定 |
| 时间轴 uniform | `Astra/shaders/lib/uniforms.glsl`（`astraSolas*` 系列） | Astra 直接改写了 3.7b 同源表达式（`shaders/shaders.properties:149-162`），两边当前应等价；3.7b 未见新增时间 uniform |
| 手持光源 | Astra 无（任务背景特性表未列） | Solas 的 DYNAMIC_HANDLIGHT（`lib/lighting/handlight.glsl` + 设置项 `shaders.properties:50`）是 Astra 缺的整特性，可作备选借鉴 |
| 水下悬浮颗粒 | `Astra/shaders/global/water/particles.glsl`（Astra 自写，`Astra/THIRD-PARTY.md:78` 登记） | Solas 3.7b 无对应实现（其观感对标项即 Astra 此特性），Astra 领先，无借鉴项 |

## ⑤ 借鉴可行性（许可证层面）

- 3.7b 包内无 LICENSE 文件，仅有来源声明与防盗声明（`drm/drm.readme:1-3`），即**默认版权、保留所有权利**。Astra 自身的 `Astra/THIRD-PARTY.md:28` 对 V2.2b 的登记（"未声明（默认版权）"+ REWRITE REQUIRED 注记）与之一致，说明 Astra 现行策略就是：**登记来源、只做思路/表达式级参考、发布前重写**。
- 结论：①研读、拆解算法思路并自写实现——可行；②逐行照抄 3.7b 代码进 Astra——不可行（未经授权）；③把 Astra 现有 V2.2b 血统文件继续对接 3.7b 新代码（如直接 include 3.7b 的 waterNormals.glsl）——同样需要先获 Septonious 授权，否则维持"结构借鉴 + 重写 + 文件头登记"的既有路线。本报告③的全部建议均按"思路级迁移、自写实现"给出。
- 操作建议：3.7b 相对 V2.2b 的新增量若要进入 Astra，统一走 Astra 现有流程——`Astra/THIRD-PARTY.md` 增补来源行（标 3.7b）、目标文件头加 PROVENANCE 注记、发布前重写为 Astra 风格；纯数值常量（吸收系数、波参数）建议重新拟合而非直接照搬，既降风险又顺带适配 Astra 的线性域管线。

## ⑥ Top5 优先建议（按 提升/工作量 排序）

1. **雨天波幅耦合 + 波形风格档**（③-a-1/a-2/a-4）：`caustics.glsl` 幅值项加 `astraRainFactor`，暴露 2-3 个水波旋钮。提升：雨天海面质感立现；工作量：半天级。
2. **分通道水下吸收 + 可调指数**（③-c-1/c-2）：把 `waterFog.glsl:2-9` 的三段谱吸收思路重写进 `absorption.glsl`/`solas_water_fog`。提升：水下红绿蓝分层衰减的"深水感"；工作量：一天内（含重校常数）。
3. **Bloom 对比度整形 + 逐维度强度**（③-d-1）：`bloom_resolve.glsl` 加四次方整形与 Nether/End 独立强度。提升：高光溢出更干净、下界泛光可控；工作量：小时级。
4. **室内探测增强体积光**（③-c-4 后半）：屏幕深度探针 → closedSpaceFactor，插入 `light_shafts` march 的 visibility。提升：洞穴/室内光束自然增强；工作量：一天级。
5. **体积极光系统**（③-d-5）：kpIndex 叙事 + 平面云照明反哺。提升：夜间天空从无到有的新特性；工作量：2-3 天（含调色），建议最后做。

验收提示：1/2/3 条改完后用雨天海面、潜入深水、高光场景三组对照截图即可判定收益；4/5 条建议各加独立开关，便于回归对比。

—— 完 ——
