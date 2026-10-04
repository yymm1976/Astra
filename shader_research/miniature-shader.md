# Miniature Shader 2.19 研究报告（面向 Astra）

> 引用格式：`shaders/…:行号` 均指 `reference_shaderpacks/miniature-shader/shaders/` 下的文件；`Astra/…:行号` 指本工作区 `Astra/shaders/` 下的文件。调研日期：2026-10-02。全包 106 个文件、约 1754 行 GLSL/配置（wc 实测），本报告基于全量通读。

## ① 包概览

- **名称/版本**：Miniature Shader 2.19（版本号来自任务指定；包内 lang 与 shaders.properties 均未自写版本号，包目录下没有 LICENSE / README 文件，仅 `shaders/` 一层）。
- **作者**：Bob je（Modrinth 页面信息；包内文件未署名——`shaders/lang/en_US.lang` 全文 82 行无作者项）。网络访问被禁止，作者与版本未能从包内自证，见备注。
- **许可证**：MIT（任务给定；Modrinth 登记为 MIT）。含义：**抄代码合法，只需保留版权与许可声明**（详见⑤）。
- **风格定位**："轻量增强原版"（vanilla-plus）：保留原版天空配色、原版云与原版 lightmap 调色板，在其上加阴影、SSR、风格化雾与 End 星野。470 万下载的卖点不是画质上限，而是"几乎免费的全特性"。
- **代码形态**：GLSL 120、兼容管线（`ftransform`/`gl_Color`/`gl_TextureMatrix`）。无 composite/deferred 链——**除 final 外零后处理 pass**（world0 下后处理程序只有 `world0/final.fsh:1-5` 一个壳）。全部逻辑集中在 8 个共享 program（`program/*.vsh/.fsh`），每个 world 文件是 4-6 行的 `#define + include` 壳（`world0/gbuffers_terrain.fsh:1-6`）。设置集中在 `shader.h`（114 行）。
- 设置 UI 同样极简：7 个 screen 声明（`shaders.properties:6-14`）、`COLORS_SCREEN.columns=3`（`shaders.properties:11`）、一整行 `sliders=` 列表（`shaders.properties:16`）——参数即 UI，无额外布局成本。
- 全包没有 compute、没有 SSBO/uniform buffer；唯一的"高级"用法是 line 顶点着色器里的 `gl_VertexID` 奇偶分支（`program/line.vsh:24`）。
- **极小体量如何覆盖全特性**：三件事——(1) **只用原版数据**：不生成天空/云/雾色，直接采样引擎的 `fogColor/skyColor/lightmap`（`common/getFogColor.vsh:4-9`、`common/getAmbientColor.glsl:2-3`）；(2) **顶点做重活**：光照、雾、水波、法线全部顶点级计算（`program/textured_lit.vsh:119-124`、`program/translucent.vsh:63-69`），fragment 只做采样与混合；(3) **单缓冲复用**：一个 `/* DRAWBUFFERS:067 */`（`program/textured_lit.fsh:130`）同时写 albedo、法线、反射率，final 一个 pass 消费（`program/final.fsh:16-58`）。

## ② 架构与特性清单

### 工程组织

- 4 个 profile 纯靠链式继承定义，一行一档：LOWEST 关阴影/关反射/最低 SSR 步数，LOW→HIGH 只改 shadowMapResolution/shadowDistance/SSR 参数（`shaders.properties:1-4`）。
- program 开关用预处理器写进 shaders.properties：实体阴影三档（SHADOW_ENTITY -1/0/1 → `shadowEntities/shadowBlockEntities/shadowPlayer`，`shaders.properties:26-38`）；旧版 MC 直接禁用 line program（`shaders.properties:42-46`）；无自定义天空需求时禁用 clouds/skybasic program（`shaders.properties:48-51`）。
- Iris 特性可选声明：`iris.features.optional=BLOCK_EMISSION_ATTRIBUTE`（`shaders.properties:40`），运行时用 `#ifdef IRIS_FEATURE_BLOCK_EMISSION_ATTRIBUTE` 分支（`program/textured_lit.vsh:5-7,73-77`）。
- 块数据走 block.properties ID：10008 水、10068 熔岩、10072 火、10014 矿石、10031/10059 薄植被，20001-20017 反射块（`block.properties:1-6,9-25`）。
- 兼容 Colored Wheel 光照模组：`MOD_COLORWHEEL` 分支调用 `clrwl_computeFragment`（`program/textured_lit.fsh:74-79`），shadow 侧有独立 clrwl 壳（`world0/clrwl_shadow.vsh:3`）。
- 兼容 Voxy 支持.chunk：translucent 里有 VOXY 分支，用 `calcFogMix(feetPos, 0.3, far)` 与原版外观插值（`program/translucent.vsh:24-26,56-58`、`program/translucent.fsh:61-65`），`getFogMix.vsh:15-18` 为 Voxy 固定 far=48000。
- `entity.properties`/`item.properties` 为空文件（0 行）——实体/物品着色完全靠 entityId 常规管线，不为特例开子程序。
- 维度映射只有 3 行：world0=通配、world-1=下界、world1=末地（`dimension.properties:1-3`）；nether/end 差异全部用 `THE_NETHER/THE_END` 宏在同一套共享 program 内分支（`world-1/gbuffers_terrain.fsh:3-5`）。

### 大气 / 雾

- 雾混合因子：距离 + "圆柱距离"（`max(length(xz), |y|)`）双取大，同时覆盖视距雾与垂直雾（`common/getFogMix.vsh:4-11`）。
- 主世界雾密度随时间：日出日落窗口的线性斜坡，clamp 到用户滑条区间，再乘 `(1-rainStrength)`（`common/getFogMix.vsh:37-44`）。
- 雾色 = 引擎 `fogColor` 混 `skyColor`，随高度上移更贴近天顶色（`common/getFogColor.vsh:6`）。
- 完全雾化的像素直接 `discard`，省掉后续全部着色（`program/textured_lit.fsh:60-62`）。
- 原版天空保留，仅在地平线做 `fogify(upDot, 0.05)` 压暗（`program/skybasic.fsh:22`）； blindness/水下等状态雾走引擎 `fogEnd<far` 检测自动接管（`common/getFogMix.vsh:26-30`）。
- 星空/日月贴图不做任何自定义——`program/skybasic.fsh:16-24` 全函数只有 9 行，其余天色全部交给引擎。
- End 星野：纯解析式，用球面角 `atan/acos` 切片 + `exp(fract(...)*-drag)/invDist` 生成星点，无一采样（`world1/gbuffers_skytextured.fsh:22-33`）。
- 云 = 原版云贴图，仅做两件事：雾色乘 0.6 拉灰、按"视线与日/月夹角 + 太阳高度"挖掉银边（`program/clouds.fsh:20-25`）。

### 水体

- 水波是**顶点级法线扰动**：每块坐标 hash 出相位，`pow3(sin/cos(t))` 两个正交波，幅度随距离衰减、只在水平面法线（`|normal.y|>0.8`）上生效（`program/translucent.vsh:60-69`、`common/getWaterWave.vsh:1-12`）。
- 无噪声纹理、无视差、无 SSRI：水"质感"来自原版水贴图的亮度重映射（`rescale` 到 WATER_GLINT_CUTOFF）加亮度底（`program/translucent.fsh:44-47`）。
- "移动的水保留全部纹理"——流动水面直接返回纹理强度 1，静止水面用块 hash 决定保留量（`common/getWaterTextureStrength.vsh:1-13`）。
- 水的 alpha/亮度被 clamp 成 `max(r,g)*WATER_B` 与 `WATER_A`，即用颜色通道反推透明度（`program/translucent.fsh:54`）。
- 法线以 **NDC 编码**写入 colortex6，final 里再还原——注释明说是为了规避 view bobbing 的 modelview 抖动（`program/translucent.vsh:75`、`program/final.fsh:23-26`）。

### 阴影与光照

- 单 tap 阴影：失真（`xy /= 0.8|x|+0.2`，`common/getShadowDistortion.glsl:2`）→ 采样 `shadowtex1` → 斜率偏差 `3.0*(depth-uv.z)/shadowProjection[2].z`（`common/getLightStrength.fsh:21-33`）。
- 阴影距离平方衰减淡出 + 包围盒/`diffuse>0` 早退（`common/getLightStrength.fsh:17,25-30`）。
- SHADOW_PIXEL：世界坐标量化到 N 格再查阴影，一行实现"像素化风格阴影"（`common/getLightStrength.fsh:11-15` + `shader.h:28`）。
- 阴影不是彩色 shadowmap，而是常量 tint `SHADOW_COLOR = (1-darkness) + blueness*vec3(0,1/3,1)`（`shader.h:112`），`common/getLightStrength.fsh` 只输出标量遮挡。
- 太阳/月光色：3 行解析式——红化项随太阳高度、夜晚切 MOON_COLOR、暗部去饱和（`common/getLightColor.vsh:1-8`）。
- 环境光 = 原版 lightmap 纹理采样 + 对其 g 通道做 4 次多项式拟合的白日增益（`common/getAmbientColor.glsl:2-14`）。
- 火把光 = inner/middle/outer 三段色渐变 + `slopeTo1` 内芯，手持光源用 `heldBlockLightValue - √2·d` 衰减并入（`common/getTorchColor.fsh:6,13-17`）。
- Lambert 带 wrap：`clamp(2.5·NdotL, -0.3333, 1.0)`，薄面（草花）固定 0.75（`common/getDiffuse.vsh:9-10`）；diffuse 还被雾/雨/水下三因子连乘（`common/getDiffuse.vsh:3-7`）。
- FLAT_LIGHTING 选项：顶点里用 `lightNormal.x²·0.6 + y²·0.25·(3+y) + z²·0.8` 复刻原版面向光，替代 NdotL（`program/textured_lit.vsh:104-112`）。
- 发光体：Iris BLOCK_EMISSION_ATTRIBUTE 或熔岩/火 ID 给 `lightSourceLevel`，雾对发光体平方化减弱（`program/textured_lit.vsh:73-77,116`）。
- 矿石发光：albedo 亮度重映射后按 `isOre/3` 混入暖白（`program/textured_lit.fsh:87-93`）。
- End 环境光常量 `END_AMBIENT` 加微小法线扰动（`program/textured_lit.vsh:79-81`、`shader.h:110`）。
- 下界"调色"是 gbuffers 内的饱和度保留：亮度低于阈值时向灰度收缩（`program/textured_lit.fsh:120-126`）。
- 阴影 pass 极简：顶点里一次失真 + 火（10072）alpha 归零不投影（`program/shadow.vsh:10,13`），fragment 只做 alpha 裁剪（`program/shadow.fsh:11-13`）。
- 雨雪只有透明度调节 `albedo.a *= WEATHER_OPACITY`（`program/weather.fsh:11`），不做风摆、不做溅落。
- 非光照几何（basic/line）基本是原版直通：basic = 纹理 × lightmap × 顶点色三乘（`program/basic.fsh:9-11`）；line 在屏幕空间做等宽线扩宽，纯 NDC 运算（`program/line.vsh:20-26`）。
- 手持光源是"旧式"实现（`shaders.properties:18` `oldHandLight=true`）：`heldBlockLightValue` 以 √2 步长随距离衰减直接并进火把光（`common/getTorchColor.fsh:6`），枚举值定义在 `shader.h:63-65`。

### 后处理（唯一 pass：final）

- 无泛光、无 tonemap、无 FXAA、无 TAA——后处理链 = 1 个 final，只做反射（world0 后处理仅 `world0/final.fsh:1-5`；全包无任何 composite/deferred 文件）。
- SSR：线性步进 + 自适应步长 `lengthR += max(step·|Δz|·invR, 1.0)`（`common/getReflectionColor.fsh:60`），命中后二分细化（`common/getReflectionColor.fsh:41-51`），`R.z >= -0.05` 整支早退（`common/getReflectionColor.fsh:15`）。
- 深度容差随距离与掠射角放大：`epsilon = 1 + 0.1·max(distanceEpsilon, grazingEpsilon)`（`common/getReflectionColor.fsh:33-35`）。
- 自遮挡判定：命中点深度必须真的在当前像素前面（`common/getReflectionColor.fsh:53-56`）。
- 屏幕边缘 vignette 衰减反射权重，遮住 SSR 拉花（`common/getReflectionColor.fsh:3-9`）。
- 粗糙度 = 对量化后的世界坐标 hash 出随机向量抖动法线，步长随像素距离放大（`program/final.fsh:42-45`）。
- 反射开关的粒度在材质端不在 pass 端：水面强度 REFLECTIONS 与方块强度 BLOCK_REFLECTIONS 是两个独立滑条（`shader.h:22-23`），共用同一个 final SSR pass。
- 无 TAA、无时域历史：所有效果单帧自洽，天然规避时域工程的全部成本与鬼影风险（对比 Astra 的半分辨率云时域与 TAA 链）。
- 反射率输出端：`(albedoLuma - minLuma)·strength` 的 luma 门槛，暗处不出反射（`program/textured_lit.fsh:134`）。

### 性能技术

- profile 阶梯只动 5 个数字（阴影分辨率/距离/SSR 三参）即成 4 档（`shaders.properties:1-4`）。
- 实体阴影距离默认压到主阴影的 20%（`shader.h:35` `entityShadowDistanceMul=0.2`），加上 SHADOW_ENTITY 三档可整类剔除。
- `rain.depth=false`（`shaders.properties:21`）：雨不做深度，直接从反射/折射链中消失。
- `occlusion.culling=true` + 雾 discard（见上）+ `fogMix>0.999` 早退是它的填充率三板斧。
- 阴影 interval refocus（`shader.h:33` `shadowIntervalSize=7.0`，lang 解释见 `lang/en_US.lang:49-50`）让 256 分辨率档也可用。
- 全部"体积感"（雾/水下/End 星）都是解析式或单次采样，无 ray march。
- 管线级便宜开关直接写死：`separateAo=true`（AO 独立通道，`shaders.properties:19`）、`beacon.beam.depth=true`（`shaders.properties:20`）、`particles.ordering=mixed`（`shaders.properties:22`）、`oldLighting=false`（`shaders.properties:24`，关掉引擎旧式方向光，交给自己的 FLAT_LIGHTING）。
- 变量级复用：`getFogMix` 被 terrain/translucent/skybasic/clouds 四类 program 共享（`common/getFogMix.vsh:14-57`），靠 `GBUFFERS_SKYBASIC/GBUFFERS_CLOUDS` 宏分支差分，一份实现零拷贝。
- 反射链无专用缓冲布局：colortex6/7 是普通 RGBA 附件，粗糙度塞在 `.y`、识别位塞在 `.z==0.5`（`program/final.fsh:18-22`），省掉独立的 buffer 声明段。

## ③ Astra 可借鉴点

**a) 廉价雾模型 → Astra 的距离雾与可选体积雾**

1. **完全雾化 discard**。技术描述：雾因子是顶点 varying，fragment 开头 `if (fogMix > 0.999) discard;`，把视距外/厚雾像素的整段着色（shadowmap 采样、环境光、torch）全部跳过。出处：`program/textured_lit.fsh:60-62`。对应 Astra：`Astra/shaders/program/lit.fsh`（前向地形主着色，418 行）。难点：低——Astra 已是前向光照，fog 因子在 lit 链路里现成；只需确认 HDR 输出端 discard 后 colortex 清屏值与雾色一致。这是对 Astra 填充率最直接的一条。
2. **圆柱距离雾**（视距 + 垂直双域 max）。出处：`common/getFogMix.vsh:4-11`。对应 Astra：`Astra/shaders/global/atmosphere/fog.glsl`（fog_v2 的 `cube(fragDistance)`，`fog.glsl:128-131`）。难点：低，但 Astra 的 pow(d,3) + valley mist 已覆盖同一视觉域，属于"可选项"而非补缺。
3. **时间窗雾密度**。日出日落斜坡 + 滑条 clamp + 雨衰减三合一，无常量纹理。出处：`common/getFogMix.vsh:37-44`。对应 Astra：`fog.glsl:146-150` 的雨天增益与 `fog_air_perspective`（`fog.glsl:208-222`）。难点：低；Astra 若想要"黄昏雾更浓"只需一条 worldTime 斜坡。

**b) 后处理链的廉价实现 → Astra bloom/后处理**

4. **"一个 final pass"的裁剪思路**。技术描述：Miniature 没有任何泛光/tonemap/FXAA，后处理唯一职责是 SSR；画面成立靠 gbuffers 端的颜色管理（lightmap 调色 + 雾色统一）。出处：全包文件清单 + `program/final.fsh:16-58`。对应 Astra：`Astra/shaders/global/post/bloom.glsl`（两 pass + mip 链，`bloom.glsl:45,50-60`）、`global/water/bloom_capture.glsl:7-9`、`bloom_resolve.glsl:4-6`。难点：无代码迁移——价值在于确认 Astra 的 `profile.PERFORMANCE` 已 `!BLOOM`（`Astra/shaders/shaders.properties:424`）走的就是同一路线，不必为低档位补一个"廉价 bloom"。
5. **NDC 编码法线 + final 还原**。技术描述：法线不乘 normal matrix 直接写 NDC，final 用 `eye2view` 还原，规避 view bobbing 抖动并省顶点变换。出处：`program/translucent.vsh:75`、`program/final.fsh:23-26,38`。对应 Astra：`Astra/shaders/program/water.glsl`（法线进 SSR/折射）。难点：中——Astra 是 #400 线性 HDR 管线，法线缓冲布局不同，收益主要是"法线缓冲可以存得更省"这一思路。

**c) 对 PERFORMANCE / NO_SHADOWS 档可直接抄的裁剪思路**

6. **SHADOW_ENTITY 三档 + 20% 实体阴影距离**。技术描述：`shadowEntities/shadowBlockEntities/shadowPlayer` 三个布尔由一个枚举在 shaders.properties 里预处理器生成（`shaders.properties:26-38`），配合 `entityShadowDistanceMul=0.2`（`shader.h:35`）。对应 Astra：`Astra/shaders/shaders.properties:424-425`（PERFORMANCE/NO_SHADOWS profile）、`Astra/shaders/lib/settings.glsl:339-359`（已有 entityShadowDistanceMul 分档）。难点：低——Astra 已有距离分档，缺的是"整类实体剔除"的 program 级开关（grep 未在 Astra shaders.properties 中发现 shadowEntities 配置，不确定项见备注）。
7. **SHADOW_PIXEL 像素化阴影档**。技术描述：世界坐标 bandify 到 N 格再查阴影，一行把阴影变成风格化块状，可配低分辨率 shadowmap。出处：`common/getLightStrength.fsh:11-15`、`shader.h:28`。对应 Astra：`Astra/shaders/global/lighting/shadowmap.glsl`（gather/PCF 4 角采样，`shadowmap.glsl:84-144`）。难点：低-中——Astra 需在 filter mode 枚举（`settings.glsl:33-34` 的 SHADOW_FILTER_SOFTWARE/HARDWARE）里加第三档"stylized"，并让 colored-shadow/SSS 路径接受单 tap。
8. **反射块 LUT + luma 门槛**。技术描述：18 项 `(强度,最低亮度,粗糙度)` 常量表按 mc_Entity 索引，反射率还乘 albedo 亮度门槛，暗面不反光。出处：`common/blockReflectivity.glsl:4-23`、`program/textured_lit.fsh:134`、ID 表 `block.properties:9-25`。对应 Astra：可挂进 `Astra/shaders/program/lit.fsh` 的输出缓冲，替代 PERFORMANCE 档被关掉的 SSR/SSAO（`shaders.properties:424` `!SCREENSPACE_REFLECTIONS`）。难点：中——Astra 需要一块法线+反射率缓冲与一个消费 pass；MIT 允许整表照抄（保留声明即可）。

**d) 水体与阴影的最小可看实现**

9. **顶点级 hash 水波（廉价档）**。技术描述：无噪声纹理、无视差，每块一个 hash 相位的双正交波，幅度随距离衰减，雨天可整体关闭。出处：`common/getWaterWave.vsh:1-12`、`program/translucent.vsh:60-69`。对应 Astra：`Astra/shaders/lib/solas_water.glsl`（Solas 多层法线体系）与 `program/water.glsl:152-175`。难点：低——可作为 Astra `WATER_WAVES`（`settings.glsl:130`）的第三档"stylized/low"，把顶点扰动直接接进现有 normal 组装点（`lit.fsh:125`）。
10. **单 tap + 斜率偏差阴影（最小可看）**。技术描述：一次 `shadowtex1` 采样，斜率偏差用 `shadowProjection[2].z` 归一，距离平方淡出 + 包围盒早退。出处：`common/getLightStrength.fsh:21-33`。对应 Astra：`shadowmap.glsl:177-194`（distort + normal offset）、`shadowmap.glsl:84-144`（4 角 gather）。难点：低——公式可直接作为 Astra SOFTWARE 滤波在最低质量（SHADOW_FILTER_QUALITY=0）下的 1-tap 路径。
11. **SSR 自适应步长三件套**。技术描述：步长按射线未命中深度差放大（`lengthR += max(step·|Δz|·invR, 1)`）、深度容差随距离/掠射角膨胀、命中后按深度差决定是否二分——三行公式把步数压到 10-16 步仍能命中远物。出处：`common/getReflectionColor.fsh:33-35,41,60`。对应 Astra：`Astra/shaders/program/water.glsl` 的 SSR 反射链（PERFORMANCE 档外的档位）。难点：低——纯公式替换，不改缓冲与 pass 结构；注意 Astra 是线性深度域，需要一次换算。

## ④ Astra 已有对应实现（对照与优劣）

| 特性 | Miniature | Astra 对应 | 双边优劣 |
|---|---|---|---|
| 距离雾 | 解析雾 + 圆柱域 + 时间窗（`getFogMix.vsh:4-44`） | `Astra/shaders/global/atmosphere/fog.glsl:101-190` fog_v2（pow(d,3)+边界雾+洞穴/失明/水下/雨） | Astra 全面更强（高度谷雾、群系 tint、空气透视都是 Miniature 没有的）；Miniature 胜在顶点级成本与 discard 裁剪 |
| 体积雾 | 无（无任何 ray march） | `Astra/shaders/global/atmosphere/volume_fog.glsl:31-73`（12-48 步 HG 相位积分） | 不可比：Astra 独有；Miniature 的"省"恰好证明低档位关掉它（Astra 已 `!VOLUMETRIC_FOG`）是合理路线 |
| 泛光 | 无 | `Astra/shaders/global/post/bloom.glsl`（soft-knee 预滤波 + 13-tap + mip 链） | Astra 独有；Miniature 靠"不泛光"成立，说明低档砍掉 bloom 不伤骨架 |
| 水体 | 顶点 hash 波 + 贴图 glint + 单 pass SSR | `Astra/shaders/lib/solas_water.glsl:19-109`、`program/water.glsl`（SSR/折射/吸收/焦散/水下光束） | Astra 远强；Miniature 的顶点波与"移动水面保纹理"（`getWaterTextureStrength.vsh:1-13`）值得作为低档选项 |
| 阴影 | 单 tap + 常量 tint + 像素化档 | `Astra/shaders/global/lighting/shadowmap.glsl`（彩色 shadowcolor、water-height 编码、gather 滤波） | Astra 远强（彩色阴影/SSS 是 Miniature 完全没有的）；Miniature 的早退与 SHADOW_PIXEL 是低档补充 |
| 天空/云 | 原版天空云 + 解析 End 星 | `Astra/shaders/global/atmosphere/sky_gradient.glsl`、`sky_minishita.glsl`、`clouds_planar.glsl`（半分辨率+时域历史） | Astra 强一个量级；Miniature 保留原版云的做法等价于 Astra 的 `CLOUD_MODE=0` |
| 质量档 | 4 档链式 profile（`shaders.properties:1-4`） | `Astra/shaders/shaders.properties:424-427`（PERFORMANCE/NO_SHADOWS/BALANCED/ULTRA） | 同构；Astra 档位内容更满，Miniature 演示了"档位只调 5 个参数"的极简维护性 |
| 手持动态光照 | `heldBlockLightValue` 距离衰减并入火把光（`common/getTorchColor.fsh:6`） | `Astra/shaders/shaders.properties:403` 有 HANDHELD_LIGHTING/HANDHELD_LIGHT_STRENGTH 选项 | 两边都有；Astra 实现文件未核验，优劣不确定 |
| End 星野 | 解析星点，零采样（`world1/gbuffers_skytextured.fsh:22-33`） | `Astra/shaders/global/atmosphere/stars.glsl`（存在性确认，内容未逐行核验） | 不确定——Astra 星野复杂度大概率更高，但不做断言 |
| 调色/tonemap | 无（仅下界饱和度保留，`textured_lit.fsh:120-126`） | `Astra/shaders/lib/tonemap.glsl`（230 行多算子）+ 颜色分级 | Astra 独有 |

不确定项（禁止编造，如实标注）：Astra `program/lit.fsh` 是否已有等价的雾 discard、是否采样原版 lightmap 纹理，本报告未逐行核验 `lit.fsh` 全文，不做断言；Astra 是否缺 shadowEntities 程序级开关仅来自一次 grep（`shaders.properties` 无 `shadowEntities` 命中），非穷尽确认。

## ⑤ 借鉴可行性（MIT 义务）

- Miniature 为 MIT（任务给定，Modrinth 同）：复制或衍生其代码（如 18 项反射率 LUT、水波公式、SHADOW_PIXEL bandify、SSR 自适应步长）**只需在发布物中保留其版权声明与 MIT 许可文本**，可闭源、可再授权，与 Astra 现有的 GPL（Steadfast 源，`Astra/shaders/global/atmosphere/fog.glsl:5-9`）部分不冲突，但**同一文件不要混入未重写的 GPL 代码后再按 MIT 处理**。
- 操作建议：凡照抄的片段集中登记进 `Astra/THIRD-PARTY.md`（现行惯例，见 `Astra/shaders/lib/solas_water.glsl:4-5` 的登记方式），并附 Miniature 的 MIT 文本。
- 边界区分：本报告③中标注"思路借鉴"的条目（雾 discard、档位裁剪、时间窗密度）是通用图形技术，不构成衍生作品；标注"可照抄"的条目（反射率 LUT、水波/SSR 公式）复制时才触发 MIT 声明保留义务。
- 落地顺序建议：MIT 片段的引入放在独立小文件（如 `lib/` 下单建模块），使许可声明与代码体一一对应，避免混入 Steadfast GPL 衍生文件（`fog.glsl`/`shadowmap.glsl` 等文件头已自证其 GPL 来源）。
- 风险点：包内无 LICENSE 文件（本目录核实仅 `shaders/`），版权行"Copyright (c) Bob je"需从 Modrinth 页面抄录——本任务禁网，最终文本需统帅补一次确认。

## ⑥ Top5 优先建议（按 提升/工作量 排序）

排序原则：先砍渲染开销大头（填充率、shadow pass 负载），再给低档位补回视觉缺失（反射、水的最低可看形态），最后是数行级锦上添花。

1. **前向地形雾 discard**（`textured_lit.fsh:60-62` → `Astra/shaders/program/lit.fsh`）：一行级改动，直接省掉雾内像素的阴影/光照着色，全档位受益。
2. **SHADOW_ENTITY 三档 + 程序级实体剔除**（`shaders.properties:26-38` + `shader.h:35` → `Astra/shaders/shaders.properties` PERFORMANCE/NO_SHADOWS）：profile 一处改动，shadow pass 负载立减，补齐 Astra 距离分档之外的"整类剔除"。
3. **18 项反射块 LUT 低档反射**（`blockReflectivity.glsl:4-23` → `lit.fsh` + 一个小消费 pass）：给 PERFORMANCE 档在 SSR/SSAO 全关时补回"湿石/金属高光感"，MIT 可整表照抄。
4. **单 tap 阴影最小档**（`getLightStrength.fsh:21-33` → `shadowmap.glsl` SOFTWARE 路径最低质量）：给 SHADOW_FILTER_QUALITY=0 一个真正的 1-tap 路径，低端卡换"能开阴影"。
5. **顶点 hash 水波廉价档 + 时间窗雾密度**（`getWaterWave.vsh:1-12`、`getFogMix.vsh:37-44` → `lit.fsh:125` 法线组装点 / `fog.glsl`）：两者都是数行级，分别作为 WATER_WAVES 第三档与黄昏雾增益，性价比一致垫后但零风险。
