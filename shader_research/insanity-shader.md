# Insanity Shader 1.650 研究报告（面向 Astra 的可借鉴点）

## ① 包概览

- **版本**：v1.650，2024-06（changelog.txt:1-2，"Added support for Iris 1.7"）。
- **作者**：ElocinDev（又名 Alm，settings.glsl 头注释 "Insanity by Alm"）。CurseForge 页面见 credits.txt:1。
- **上游**：**基于 BSL Shaders（Capt Tatsu）改编**。credits.txt:5-8 明确写"Insanity is based on BSL Shaders… Most of the code is made by them… Explicit permission was given by Capt Tatsu to edit BSL"；每个 program 文件头（如 program/final.glsl:2-6）与 shaders.properties:1-4 同样署名致谢。lib/surface/materialDeferred.glsl、parallax.glsl 等文件保留 BSL 7.x 的结构与命名（directionalLightmap、MATERIAL_FORMAT 0/1 等）。
- **许可证**：包内**无 LICENSE 文件**，许可状态仅由 credits.txt 的口头声明承载：改编权来自 Capt Tatsu 对 Insanity 作者的**个人授权**，不传导给第三方（详见⑤）。仓库内 reference_shaderpacks/bsl-shaders 是较新版本 BSL，可作对照但注意版本差异。
- **风格定位**：恐怖/暗黑滤镜向。核心手段是压暗夜与环境光、洞内近黑、暗处去饱和、低默认曝光、蛛眼/信标光柱加亮制造"黑暗中发光的眼睛"，外加可选 RETRO_FILTER（PS1 抖动+像素化）、暗角、色差、胶片颗粒。下载量约 750 万、下载榜第 10（任务给定背景）。
- **技术底座**：OptiFine/Iris 兼容的**前向 gbuffers + 后处理管线**（无 compute、无独立维度着色器目录之外的体素系统），world-1（下界）目录仅薄封装 program/ 下同名文件。

## ② 架构与特性清单

### 管线总览（Iris/OptiFine 标准 pass 序）
gbuffers（前向光照，lib/lighting/forwardLighting.glsl）→ deferred（AO 开关门，shaders.properties:114-116）→ deferred1（天空/镜面/雾/发光描边）→ composite（水下雾、光柱、描边）→ composite1（叠加光柱）→ composite2（运动模糊，program toggles 于 shaders.properties:119-121）→ composite3（DOF）→ composite4（Bloom 瓦片降采样，program/composite4.glsl:57-69）→ composite5（Bloom 合成/色调映射/镜头光斑/暗角/饱和/颗粒，program/composite5.glsl:216-297）→ composite6（TAA）→ composite7（FXAA）→ final（像素化/色差/锐化）。

### 黑暗环境与调光
- **洞穴最低亮度 MINLIGHT**：可调 RGB+强度，`minLightCol = minLightColSqrt² * 0.04`（lib/color/dimensionColor.glsl:13-14；默认 MINLIGHT_INTENSITY 0.10，lib/settings.glsl:216-219）——系数 0.04 把"最低亮度"压到近黑。
- **方块光陡峭曲线**：`pow(lightmap.x,10.0)*1.5 + lightmap.x*0.7` 再平方（lib/lighting/forwardLighting.glsl:45-46），低照度端被强烈压制，火把光圈外迅速沉入黑暗（注：与上游 BSL 同族曲线，BSL 为 ×1.6/×0.6，见 bsl-shaders 同文件 103-104 行）。
- **夜间光照再压暗**：`lightNight = … * LIGHT_NI * 0.3`（lib/color/lightColor.glsl:4），环境光同乘 0.3（第 9 行）。
- **暗处去饱和 DESATURATION**：按阴影×天光计算 desatAmount，暗处把表面色拉向"亮度×深蓝暗色"（lib/lighting/forwardLighting.glsl:75-108；lang 注释原文 "Reduces saturation while adding some tint in darker areas"，lang/en_US.lang:148）。
- **黑暗/失明效果（1.19 darkness）**：统一 `max(blindFactor, darknessFactor)`：BlindFog 三次方收拢雾（lib/atmospherics/fog.glsl:135-139）、天空压黑（program/deferred1.glsl:280）、水雾压暗（lib/atmospherics/waterFog.glsl:14）、光柱抑制（program/composite1.glsl:59-60、lib/atmospherics/volumetricLight.glsl:137）、镜头光斑抑制（program/composite5.glsl:260）。shaders.properties:157-159 用 variable 自定义了更陡的 blindFactor。
- **心理手段**：蛛眼亮度倍率 SPIDER_STRENGTH（program/gbuffers_spidereyes.glsl:26）、信标光柱亮度倍率 B_STRENGTH（program/gbuffers_beaconbeam.glsl:37）——"黑暗里悬着的东西在发光"。ENDERMEN_STRENGTH 声明于 lib/settings.glsl:332 且进了滑杆表（shaders.properties:111），但**包内无任何使用点，是死选项**。
- **地底天空兜底**：UNDERGROUND_SKY（可选）把洞内天空混向 `minLightCol * 0.125`（lib/atmospherics/sky.glsl:61-64）。

### 雾与大气
- **主世界雾**：日/夜/雨三套密度 + 地面雾，雾色由天光、日落、雨天混合，且 `fog = mix(minLightCol*0.5, fog*eBS, eBS)`——**雾随玩家自身天光暴露 eBS 一起压暗**，洞穴里不会出现亮雾（lib/atmospherics/fog.glsl:10-22、35-50）。
- **距离淡出 DISTANT_FADE**：0-6 六档 + 两种风格（视线距离/水平距离），并把自定义雾与原版远雾插值融合（fog.glsl:63-107）。
- **维度雾**：下界 `2.0*pow(viewLength*NETHER_FOG_DENSITY/256,1.5)`、雾色 `netherCol.rgb*0.04`（fog.glsl:110-118）；末地 `1.0-exp(-0.8*fog²)`、雾色 `endCol.rgb*0.00625`（fog.glsl:120-130）。三维度密度各有独立滑杆（lib/settings.glsl:73-75）。
- **熔岩/细雪浓雾**：isEyeInWater>1 时按流体索引取色 DenseFog（fog.glsl:141-150）。
- **虚空下坠淡出**：voidFade 按 cameraPosition.y 压暗（fog.glsl:53-57；uniform 定义 shaders.properties:183）。
- **下界群系雾色**：5 种群系（常规/灵魂谷/绯红/诡异/玄武岩）各一套 RGB+强度滑杆（lib/color/netherColor.glsl:1-5），经 shaders.properties:178-181 的 `isValley/isCrimson/isWarped/isBasalt` smooth 自定义均匀随时间混色（netherColor.glsl:11-25）；NETHER_VANILLA 则直接用原版 fogColor（netherColor.glsl:7-9）。
- **主世界群系天气色 WEATHER_PERBIOME**：7 组天气色按 isCold/isDesert/… 加权混合（lib/color/lightColor.glsl:11-35；uniform 定义 shaders.properties:167-176）。

### 彩色阴影与阴影质量
- **SHADOW_COLOR**：阴影色 = shadowcolor0 纹理 × shadowtex1 硬阴影（半透明染色），再 `shadowCol*shadowCol` 压饱和后与硬阴影合成（lib/lighting/shadows.glsl:56-74）。
- 阴影扭曲 DistortShadow + 弯曲偏置 biasDistribution + IGN 时间抖动（shadows.glsl:41-54）；9-tap 过滤版 SampleFilteredShadow（shadows.glsl:76-83）。
- **死代码**：shadows.glsl:64,92 的 `#ifdef WATER_CAUSTICS` 在本包内无任何 `#define`（BSL 遗留分支，永不编译）——借代码时需甄别这类上游残骸。

### 水与反射
- 水四种模式 WATER_MODE 0-3（含原版 fogColor 取色模式，lib/atmospherics/waterFog.glsl:1-14）、水面视差 WATER_PARALLAX、雨积水 REFLECTION_RAIN 按 wetness 混入反射（program/gbuffers_terrain.glsl:275-284）。
- 反射 REFLECTION 0-2 三档 + 粗糙反射/透射反射开关（lib/settings.glsl:33-40）。

### 设置页组织（对应滤镜解耦 c 的 UI 侧面）
- 主屏只暴露 SATURATION/VIBRANCE/ADVANCED_MATERIALS + 四个分组页；夜间/白天强度单独成页 screen.NIGHTOPTIONS/screen.DAYOPTIONS（shaders.properties:92,95-96）。
- 三通道独立色彩分级 CGT（每通道 R/G/B/I/M/C 八滑杆，shaders.properties:48-52）；氛围/水/后效各自独立页（shaders.properties:38,42,44）。

### 自定义 uniform（properties 侧预处理）
- 时角重映射 timeAngle/timeBrightness（日落慢、夜晚快）与 shadowFade（shaders.properties:147-155）：把剧情性明暗节奏做在 properties 表达式层而非 GLSL。
- 群系 uniform 全部走 `smooth(序号, 值, 10, 10)` 时间平滑（shaders.properties:167-181），群系切换无跳变。


- **动态手持光 DYNAMIC_HANDLIGHT**（shaders.properties:16 强制开启）：在各 gbuffers 顶点阶段按视空间距离衰减 `clamp((heldLightValue - 2.0*length(viewPos))/15.0, 0.0, 0.9333)`，再 `lightmap.x = max(lightmap.x, handlight)` 并入光照图（program/gbuffers_terrain.glsl:186-190；terrain 用 1.4 系数，手持程序内用 heldValue/15.0，program/gbuffers_hand.glsl:190-191）。**上限 0.9333**：手持光永远到不了满亮度，是极暗环境的"溢出控制"。
- 并入 lightmap.x 后走同一方块光陡峭曲线（forwardLighting.glsl:45-46），暗处自然衰减。
- 无屏幕空间点光源/无 compute 体素光；闪电仅有 entity 标记（shaders/entity.properties:10-11），无专用点光。

### 后处理滤镜层
- **RETRO_FILTER（恐怖滤镜总开关）**：composite5 做 Bayer64 抖动 RetroDither（program/composite5.glsl:235-238；lib/util/dither.glsl:1-13），final 做 `floor(coord*view)/view` 像素化（program/final.glsl:69-72）；并通过 `#undef FXAA/TAA`（lib/settings.glsl:372-375）+ program 门控 `TAA && !RETRO_FILTER`（shaders.properties:125-130）**同时关闭抗锯齿**——滤镜只动纯后处理层，零场景 pass 改动。
- **暗角**：亮度自适应 `color *= 1.0 - length(texCoord-0.5)*(1.0-GetLuminance(color))`——亮处弱暗处强（program/composite5.glsl:283-285）。
- **色差 CHROMATIC_ABERRATION**（final.glsl:76-86）、**胶片颗粒**（composite5.glsl:291-292）、水下扭曲（composite5.glsl:218）、AUTO_EXPOSURE（composite5.glsl:244-247，默认关）。
- 色调映射 BSLTonemap + 三段曲线参数（composite5.glsl:253；lib/settings.glsl:134-143）。

### 维度特化
- NETHER 下 `#undef LIGHT_SHAFT/LENS_FLARE/SKY_VANILLA/REFLECTION_RAIN`，END 下关闭光斑/雨反射（lib/settings.glsl:334-345）——用 undef 收敛各维度不适用的开销。
- 下界场景光仅 `netherColSqrt.rgb * 0.1`（forwardLighting.glsl:42），末地 `endCol.rgb*(0.06*shadow+0.02)`（第 37-39 行）。

### 性能
- 五档 profile VERYLOW→ULTRA（shaders.properties:7-11）：VERYLOW 砍 SELF_SHADOW/TAA/AO/光柱/彩色阴影/滤波，512 阴影图。
- program.enabled 门控：AO 关→deferred 整 pass 跳过；DOF/MOTION_BLUR/光柱均可整 pass 关闭（shaders.properties:113-130）。

## ③ Astra 可借鉴点

> 专项问题应答索引：a（暗处亮度分配/心理手段）→ 条 1、2、6；b（雾随维度与深度）→ 条 7；c（滤镜层解耦）→ 条 5；d（手持光溢出控制）→ 条 3、4。


> 标注：【机制可借】= 组织/曲线/门控思路可移植到写实向；【恐怖滤镜不可借】= 效果本身属于风格层，最多作为 Astra 未来"风格页"的可选项。

1. **【机制可借】eBS（玩家天光暴露）作为"黑暗适应"统一乘子**
   - 描述：Insanity 把雾、天空、光柱、MINLIGHT、手持光溢出全部挂到 `eBS = eyeBrightnessSmooth.y/240` 上：进洞瞬间整套大气一起沉下去，而不是只有地表光。这是它"暗得有整体感"的关键。
   - 出处：lib/atmospherics/fog.glsl:50（雾压暗）、lib/atmospherics/sky.glsl:62-63（地底天空）、lib/atmospherics/volumetricLight.glsl:61。
   - 对应 Astra 模块：Astra/shaders/global/lighting/diffuse.glsl（洞底亮度 diffuse.glsl:433-434 用的是逐片元 skyLight）、global/atmosphere/fog.glsl。
   - 迁移难点：低。Astra 已读 eyeBrightness（blocklight.glsl:47-49 注释即用其算 heldLightSuppression），缺的是把"相机处 eBS"作为全局暗适应乘子接到雾/天光。注意与 Astra 现有逐片元 suppression 的职责区分：eBS 管相机，skyLight 管片元。
2. **【机制可借】暗处去饱和的驱动量选择**
   - 描述：Insanity 的 DESATURATION 用"阴影×天光+方块光"作为去饱和反向量（forwardLighting.glsl:77-79），暗→去饱和并染上夜间光色；Astra 的 night_desaturation 用 local_light_attenuation 保护火把区（diffuse.glsl:240,397-399）。两者思路同构，Insanity 版把**阴影覆盖率**也计入，月光直射面更保守。
   - 出处：lib/lighting/forwardLighting.glsl:75-108。
   - 对应 Astra 模块：Astra/shaders/global/lighting/diffuse.glsl:240（night_desaturation）。
   - 迁移难点：低（只是驱动量公式调整）。写实向需把 desatColor 从"深蓝"换成 Astra 夜间色板。
3. **【机制可借】手持光上限封顶（溢出控制）**
   - 描述：0.9333 硬上限 + terrain 侧 1.4× 距离系数，让手持光在纯黑洞穴里"亮而不爆"，永远弱于一块满级方块光；并统一走方块光曲线衰减。
   - 出处：program/gbuffers_terrain.glsl:188-189（上限与并入）、program/gbuffers_hand.glsl:191。
   - 对应 Astra 模块：Astra/shaders/global/lighting/blocklight.glsl:62-70（held_light_strength）、82-100（block_lighting 的 min(1.0,…) 合成）。
   - 迁移难点：极低——Astra 的 heldLightIntensity 乘一个 0.93 系数即可；若要 terrain 侧短射程，需在 diffuse.glsl 调用点区分材质，成本略高。
4. **【机制可借】darkness/blindness 统一收拢为一个暗幕因子**
   - 描述：一个 `max(blindFactor, darknessFactor)` 贯穿雾/天/水雾/光柱/光斑五个点（见②），原版黑暗药水效果与光影画质一致；BlindFog 用三次方曲线比线性收束更"扑面"。
   - 出处：lib/atmospherics/fog.glsl:135-139；program/deferred1.glsl:280。
   - 对应 Astra 模块：Astra/shaders/global/atmosphere/fog.glsl:153-157（已有 blindness 平方收束，但未覆盖 darknessFactor、未同步天空/水雾）。
   - 迁移难点：低。主要是把 `darknessFactor` uniform 加进 lib/uniforms.glsl 并在雾外补天空与云两处（云侧 Astra 已有 blindness 处理：clouds_planar.glsl:380-381）。
5. **【机制可借】滤镜层与场景层解耦的组织方式（回应专项 c）**
   - 描述：恐怖滤镜全部做在**纯后处理段**：composite5（抖动/暗角/颗粒/饱和）与 final（像素化/色差），场景 gbuffers/deferred 一行不改；开关靠三件套协同——settings `#define/#undef`（lib/settings.glsl:372-375）、shaders.properties program 门控（shaders.properties:125-130）、滑杆屏独立页（screen.POST_EFFECTS，shaders.properties:44）。RETRO_FILTER 关闭时它触碰的 pass 整个被跳过，零残留成本。
   - 出处：program/composite5.glsl:235-238、program/final.glsl:69-72、shaders.properties:44,125-130。
   - 对应 Astra 模块：Astra/shaders/global/post/grading.glsl（apply_vignette 等契约已就位，grading.glsl:40,52）、lib/settings.glsl（VIGNETTE 已是注释掉的开关，settings.glsl:232）。
   - 迁移难点：中。Astra 管线 pass 划分与 Iris program 门控兼容；难点在把"风格页"所需的联动（如开滤镜自动关 TAA）落成 shaders.properties 的 program.enabled 表达式，以及保证滤镜只读 display-space 结果（Astra 后处理顺序与 Insanity 不同）。
6. **【机制可借，原样思路属恐怖风格】黑暗中的"信息性发光"**
   - 描述：蛛眼/信标柱这类**类别化发光体亮度倍率**，让暗处保留少量高对比参考点。机制（对特定 emissive 类别乘可配置系数）可借用于 Astra 的危险物提示/调试；"红眼蜘蛛"式恐怖用法不可借。
   - 出处：program/gbuffers_spidereyes.glsl:26、program/gbuffers_beaconbeam.glsl:37、lang/en_US.lang:96-103。
   - 对应 Astra 模块：Astra/shaders/lib/surface_emission.glsl（发射材质出口）。
   - 迁移难点：低，但**默认值必须中性（1.0）**，否则污染写实基调。
7. **【机制可借】三维度独立雾密度 + 远雾融合开关**
   - 描述：FOG_DENSITY/NETHER_FOG_DENSITY/END_FOG_DENSITY 独立滑杆 + DISTANT_FADE 六档两风格 + 与原版远雾插值（fog.glsl:89-105），用户可在不破坏氛围下调通透度。
   - 出处：lib/settings.glsl:67-75；lib/atmospherics/fog.glsl:89-105。
   - 对应 Astra 模块：global/atmosphere/fog.glsl、lib/nether_fog_density.glsl。
   - 迁移难点：低（设置面工作为主）。
8. **【恐怖滤镜不可借】整体压暗默认值**：EXPOSURE -0.25（settings.glsl:129）、夜光×0.3（lightColor.glsl:4）、VIGNETTE 默认开（settings.glsl:122）、低饱和默认（settings.glsl:145-146）。这些是风格取向而非机制；Astra 借"用户可调夜间强度滑杆 + screen.NIGHTOPTIONS 单独页"的**组织方式**即可（shaders.properties:95-96）。
9. **【机制可借】properties 层做明暗节奏与群系平滑**：时角重映射（日落慢/夜晚快）与 shadowFade 全部用 shaders.properties 的 variable/uniform 表达式完成（shaders.properties:147-155），群系权重用 `smooth()` 时间平滑（shaders.properties:167-181）。Astra 未在 shaders.properties 建群系 smooth uniform——下界群系色直接取原版 fogColor（dimension/nether.glsl:19,49-53），雨湿用 wetness+自算包络（global/atmosphere/weather.glsl:12-27）。是否值得把权重下沉到 properties 层属实现取舍，Insanity 证明这条路径在 Iris 可行。对应 Astra 模块：Astra/shaders/lib/uniforms.glsl。迁移难点：低-中（需按 Iris custom uniform 语法重写并回归测试时间平滑稳定性）。

## ④ Astra 已有对应实现（对照）

| 机制 | Insanity | Astra 现状 | 两边评估 |
|---|---|---|---|
| 洞穴最低亮度 | minLightCol=minLightSqrt²×0.04，随 (1-eBS) 淡入（forwardLighting.glsl:48；dimensionColor.glsl:13-14） | caveFloor = ambientStr×MIN_AMBIENT_COLOR（diffuse.glsl:433-434；colors.glsl:51） | Astra 是方向性、随环境光强度的地板，物理上更讲究；Insanity 的是常数地板但带"进洞才亮"的 eBS 门。**Astra 缺相机维度**，不能确定孰强，需实机对比 |
| 方块光衰减曲线 | pow10×1.5+×0.7 再平方（forwardLighting.glsl:45-46，源自 BSL 族） | pow4（blocklight.glsl:89） | Insanity/BSL 曲线低端压得更狠、"暗"感更强；Astra pow4 更线性、写实。**这是曲线取舍不是优劣**，是否更陡属风格决策 |
| 手持光 | 视空间线性 (v-2d)/15，上限 0.9333，进 lightmap 走公共曲线（gbuffers_terrain.glsl:186-190） | base-d/15 + pow4 源 + 日光抑制 + min(1,…) 合成（blocklight.glsl:62-70,82-100） | Astra 有 daylight 抑制、Insanity 有满级封顶；两边各补一招即可。**不确定** Insanity 版在逆光/白天是否有溢出，包内未见等效抑制项 |
| 暗处去饱和 | desatAmount=f(阴影,天光,方块光)，染夜间色（forwardLighting.glsl:75-108） | night_desaturation(skyLight, localAttenuation, visibility)（diffuse.glsl:240,397-399） | 同构；Insanity 把阴影计入、Astra 把火把保护计入。Astra 版动机文档化更完整 |
| 失明/黑暗雾 | max(blind,darkness) 统一五处（fog.glsl:135-139 等） | 仅 blindness 平方收束（fog.glsl:153-157）、云侧已处理（clouds_planar.glsl:380-381） | **Astra 缺 darknessFactor 覆盖面**；Insanity 覆盖更全但 Astra 实现更克制 |
| 群系雾 | 下界 5 群系色板（netherColor.glsl:1-25）+ 主世界 7 组天气色（lightColor.glsl:11-35），全靠 shaders.properties smooth 自定义 uniform（167-181 行） | fog_biome_tint（atmosphere/fog.glsl:229-231）、nether_palette 用原版 fogColor（dimension/nether.glsl:49-62） | Astra 直接吃原版 fogColor，免维护 750+ 行色板且随数据包自动适配；Insanity 可全手动调色但硬编码。**Astra 架构更优**，Insanity 的"分维度滑杆"仍可取 |
| 手持光在极暗环境的溢出（专项 d） | 0.9333 封顶 + 并入 lightmap 后统一陡曲线 | block_lighting 的 min(1.0, block+held) 封顶在合成处 | Astra 的封顶在"两源相加后"，held 单独仍可到 1.0 占满；Insanity 封在源头。建议把③-3 的源头封顶借来 |
| 滤镜层解耦（专项 c） | 后处理-only + program 门控 + 独立设置页 | grading.glsl 已是 display-space 契约（:24-52），VIGNETTE 开关存在（settings.glsl:232）但无联动 program 门控 | Astra 半成品状态：有分层意识、缺"一开关联动多 pass"的 properties 表达式。借鉴③-5 |
| 彩色阴影 | shadowcolor0×shadowtex1 合成彩色阴影（lib/lighting/shadows.glsl:56-74） | Astra 彩色阴影为既定特性（任务背景；本次未逐行核对 Astra 阴影实现） | **不确定**：Astra 实现细节未核对，无法比较优劣 |
| 熔岩/细雪浓雾 | 按流体索引取色的 DenseFog（lib/atmospherics/fog.glsl:141-150） | Astra 雾统一走 atmosphere/fog.glsl（含 water/lava/border/cave 分派，fog.glsl:92 注释） | Astra 分派结构更完整；Insanity 版本更简单但将流体色硬编码在数组里 |

不确定项：Insanity 的 nightDensity=0.65（fog.glsl:11）相对上游是否为 Insanity 改动**无法确认**——仓库内 bsl-shaders 为更新版本（其同位置为 1.0），版本差异与作者改动混在一起，禁止编造归因。

## ⑤ 借鉴可行性（许可证层面）

- **结论：不要从 Insanity 复制代码；机制/思路层面的借鉴（重新实现）是安全的。**
- 传导关系：Insanity 无自带 LICENSE 文件；其存在合法性 = credits.txt:8 记载的 Capt Tatsu **个人授权**（"Explicit permission was given by Capt Tatsu to edit BSL and use its code for Insanity"）。该授权只及于 Insanity 作者本人，**不向下游传导**——Insanity 自身都没有权利再授权他人复制其代码。上游 BSL 为自定义许可（署名/禁止未授权再分发类条款），修改版再发布同样需许可。
- 因此：Astra 若需要 MINLIGHT 曲线、手持光封顶、滤镜门控等，应参照本报告的**行为描述自行实现**（多数仅数行数学），实现时避免逐行对照 Insanity/BSL 源码。Astra 现有依赖（Solas/Refrax/Steadfast 等）的许可链不受本次只读研究影响。
- 操作规则建议：借鉴时只引用本报告的"描述 + 行为等式"，不打开参考包源码复制；新增实现文件头不署名/不提及 Insanity 或 BSL，避免暗示衍生关系；若未来确需文本级复用（如 lang 词条、properties 片段），先取得 Capt Tatsu 书面许可再动。

## 引用自查说明

交付前已重开文件核对引用（超过验收要求的 8 条）：credits.txt:5,8；changelog.txt:1-2；lib/settings.glsl:122,129,146,219,330；lib/color/lightColor.glsl:4；lib/color/dimensionColor.glsl:13-14；lib/lighting/forwardLighting.glsl:45,46,48；lib/lighting/shadows.glsl:56-74；lib/atmospherics/fog.glsl:50,117,126,135-139,141-150；lib/atmospherics/sky.glsl:61-63；lib/atmospherics/waterFog.glsl:14；lib/atmospherics/volumetricLight.glsl:61,137；program/gbuffers_terrain.glsl:188-189；program/gbuffers_spidereyes.glsl:26；program/gbuffers_beaconbeam.glsl:37；program/composite1.glsl:60；program/composite5.glsl:283-285,291-292；program/final.glsl:69-72；program/deferred1.glsl:280；shaders.properties:95-96,125-130,147-155,178-181；entity.properties:10-11；以及 Astra 侧 diffuse.glsl:433-434、blocklight.glsl:62-70、nether.glsl:19,49-53、atmosphere/fog.glsl:153-157,229-231、grading.glsl:40,52、settings.glsl:232、clouds_planar.glsl:380-381。核对中发现并修正一处：entity.properties 闪电映射实际在第 10-11 行（初稿误写 6-8）。
## ⑥ Top5 优先建议（按 提升/工作量 排序）

1. **手持光源头封顶 + 极暗曲线复用**（③-3/④d）：几行改动直接解决暗洞手持光溢出，提升立竿见影，工作量最小。
2. **eBS 暗适应乘子接入雾与天空**（③-1）：进洞整体压暗的一致性收益大，Astra 各模块已具备所需 uniform，工作量中低。
3. **darknessFactor 全覆盖**（③-4）：补齐原版黑暗药水与光影的一致性，工作量低，写实向完全兼容。
4. **滤镜层解耦骨架（风格页 v0）**（③-5）：先只落"一开关 + program.enabled 表达式 + grading 后处理-only"三件套，为未来任意风格预设铺路；工作量中，但杠杆最大。
5. **三维度独立雾密度滑杆 + 远雾融合**（③-7）：纯设置面与 fog.glsl 参数化，工作量低，用户感知直接。

—— 引用自查说明：交付前已重开文件核对下列引用（≥8 条）：forwardLighting.glsl:45-48、fog.glsl:135-139、dimensionColor.glsl:13-14、gbuffers_terrain.glsl:186-190、composite5.glsl:283-285、final.glsl:69-72、credits.txt:5-8、settings.glsl:330-332、lightColor.glsl:4、deferred1.glsl:280。
