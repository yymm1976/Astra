# KUDA Shaders 6.5.26 面向 Astra 的可借鉴点调研

- 生成方式：子代理调研（批次二续跑队列第 5 包；契约与 `ushader`/`glimmer`/`reverie`/`clarity`/`musk-rose` 相同）
- 包版本：6.5.26（`P:Changelog.txt:5`）；显示名 KUDA Shaders；作者 Titan1um（索引登记值，包内文本无作者名，仅 `P:Credits.txt:16` 提到 "KUDA-Shaders v5 and older"）
- 调研日期：2026-10-02
- 体量：105 文件 / 约 568 KB；shader 源码 101 文件、10,991 行（主世界 41 文件 4,760 行；下界 30 文件 3,117 行；末地 30 文件 3,114 行）
- 引用约定：`P:` 相对 `reference_shaderpacks/kuda-shaders/`；`A:` 相对 `Astra/shaders/`。行号全部来自本次实际读取。
- 本包关注点（逐字照发）：历史级国民光影的现行 Iris 移植；BSD-3-Clause 宽松，看"低饱和自然写实"的调校与轻量实现。

---

## ① 概览

### 1.1 目录与平台

```
kuda-shaders/
├── Agreement.txt / Changelog.txt / Credits.txt   # 无 LICENSE 文件（见 ⑤）
└── shaders/
    ├── *.fsh / *.vsh（41 个）   # 主世界（根目录 = overworld）
    ├── world-1/（30 个）        # 下界变体
    ├── world1/（30 个）         # 末地变体
    └── shaders.properties（31 行）
```

- 全部为 `#version 400 compatibility` 传统管线（`P:composite.fsh:1`）：无 compute、无 SSBO、无 TAA/时域累积，仅 `shadow2D` 硬件比较与 `GL_ARB_shader_texture_lod`（`P:composite1.fsh:2`）。
- 维度用整套目录副本而非增量：主世界 `composite.fsh` 600 行 → 下界 `P:world-1/composite.fsh` 245 行 / 末地 `P:world1/composite.fsh` 247 行；`gbuffers_terrain.fsh` 295 行 → 两侧 211 行。
- 包内无贴图资产（只有程序噪声 `noisetex` + 缓冲区），代码密度高。

### 1.2 主世界管线

| 顺序 | pass | 作用 | 关键行 |
|---|---|---|---|
| 1 | `shadow.*` | 阴影视图：同类植被摇曳 + 半径畸变（fsh 直通） | `P:shadow.vsh:45-90,120-122`、`P:shadow.fsh:28-32` |
| 2 | `gbuffers_*` | 8 缓冲：gcolor/gdepth/gnormal/composite/gaux1(手·半透明)/gaux2(法线)/gaux3(材质+光图)/gaux4(高光·湿度) | `P:gbuffers_terrain.fsh:279-293` |
| 3 | `composite.fsh` | 光照合成：阴影、环境/直射/反弹光、火把、自发光、焦散、体积光、低光脱色 | `P:composite.fsh:529-600` |
| 4 | `composite1.fsh` | 天空/日月星/2D 云、雾、水下雾、折射、SSR、湿润、自动曝光 | `P:composite1.fsh:660-694` |
| 5 | `composite2.fsh` | 运动模糊（默认关） | `P:composite2.fsh:43-101` |
| 6 | `composite3.fsh` | Bloom 金字塔：6 级 mip → gaux4，alpha 存亮度 | `P:composite3.fsh:88-106` |
| 7 | `final.fsh` | 水下折射、雾模糊、DOF、Bloom、变形镜头、脏镜头、噪点、色调映射、暗角、信箱 | `P:final.fsh:441-468` |

### 1.3 许可证（包内证据，与索引登记冲突）

- 包内**没有 LICENSE 文件**（全包仅 Agreement/Changelog/Credits 三个文本）。
- `P:Agreement.txt` 为限制性自定义协议，第 9–15 行：9 "modify my shaderpack ONLY for yourself!"；11 "not allowed to redistribute and/or reupload it!"；12 "not allowed to use content of my shaders!"；15 "please leave a note"。各 shader 文件头 13–18 行复述同一限制（如 `P:composite1.fsh:13-18`）。
- 批次二索引登记为 **BSD-3-Clause**（`reference_shaderpacks/INDEX-batch2.md:38`、`shader_research/SUMMARY-batch2.md:47,69`），但许可文本不在包内、无法自证。裁定见 ⑤ 与备注。

---

## ② 架构特性清单（按子系统）

### 2.1 缓冲与材质 ID

- 8 色缓冲角色以注释固定（`P:composite.fsh:588-595`、`P:composite1.fsh:690`、`P:gbuffers_terrain.fsh:281-288`）。
- 材质 ID 用浮点区间塞进已有缓冲，无额外缓冲：地形 0.0 默认 / 0.1 自发光 / 0.2 半透明（`P:gbuffers_terrain.fsh:274-277`）；水 0.01 / 0.1 水 / 0.2 冰 / 0.3 染色玻璃（`P:gbuffers_water.fsh:146-151`）；云 0.3（`P:gbuffers_clouds.fsh:64`）；手 0.5、持发光物 0.6（`P:gbuffers_hand.fsh:58-59`）；雨雪 0.7（`P:gbuffers_weather.fsh:55`）。
- 消费端做窄区间判定派生布尔集（`P:composite.fsh:144-156`、`P:composite1.fsh:115-122`）。`glowingEyes`（0.4）仅在 `P:composite.fsh:145` 读取，本版本无写入端，属死代码。
- gaux1 存"需二次打光的半透明/发光表面颜色+覆盖度"，gaux3 存"覆盖像素的材质与光图"（`P:composite1.fsh:646-658`、`P:gbuffers_water.fsh:164-166`）。
- HDR 预算：全管线把颜色除以 `maxColorRange=6.0` 存 RGBA16、读回再乘（`P:composite.fsh:41,597`、`P:composite1.fsh:665,692`、`P:final.fsh:42,449`）。

### 2.2 光照与阴影

- 全部打光在 `composite.fsh` 一个 pass：`minimumLight*0.02 + (ambient + (sunlight+caustics)*shading1 + bounced)*skyLightmap + torch`（`P:composite.fsh:547-576`），手部/半透明走 gaux3 光图副本（572-573）。
- 火把光锥随天光收缩 `tRadius *= mix(1.0,5.0,skyL*TimeDay)`（`P:composite.fsh:243-252`，消费 562-563）。
- 阴影：8/28 采样圆盘（`P:composite.fsh:163-215`）；`shadowSmoothnessFactor=0.65`，阴天 1.5×→5×（337-342）；逐像素斜率 bias `distortFactor²*(0.004*fix*tan(acos(direct))+0.0004*fix)`（379）；半透明 bias 0.001、手 0.0025；`shadowFade=clamp((1-dist/shadowDistance)*12,0,1)`（368）；整体再乘 `direct*(1-weatherRatio)*DayToNightFading`（416-420）。
- 反弹光 `pow(max(dot(normal,-lightVector),0),0.75)`、白天权重（`P:composite.fsh:426-435`）；自发光按原色亮度超 `cover=0.4` 线性推向 `exposure=2.5` 白（254-264）；低光眼去饱和 `desaturationAmount=0.7` 混向 `luma*lowlightColor`（266-275，颜色 `P:composite.vsh:160`）。
- 阴影投射端自做同一摇曳，并在投影后按半径削畸变（`P:shadow.vsh:45-90,104-113,120-122`）。

### 2.3 天空 / 大气 / 雾 / 云 / 体积光

- 调色板在顶点着色器预算：昼夜 4 段权重（`P:composite.vsh:104-120`、`P:composite1.vsh:108-120`）+ 5 组颜色（`P:composite.vsh:130-160`、`P:composite1.vsh:122-186`）+ 天气增白（`P:composite1.vsh:142-144,152-156,164-168,182-186`）。
- 天空二元 horizon/sky 混合 + 地平线压暗（`P:composite1.fsh:204-220`）；日月盘 `pow(sunVector,2000)*10`、`pow(moonVector,4000)*10*0.8` 且第二月亮分量做月牙、地平线消隐（251-280）；星空 3 倍频噪声 + 缓慢移动（222-249）。
- 2D 程序云层：原版云几何写黑并标材料 0.3（`P:gbuffers_clouds.fsh:56-64`），天空 pass 用 4 倍频噪声重绘；`fragpos` 与 `fragpos+lightVector*25` 双采样做云自阴影（`P:composite1.fsh:282-366`，采样点 297）。
- 雾 `exp(-pow(d*0.004,1.5))`、散射 `pow(dot(view,light),7.5)*0.7`、按空气密度重映射颜色 `pow(fogColor,1/infl)/pow(infl,0.4)`（`P:composite1.fsh:381-437`）；SSR 命中点复用同一函数（501）；水下雾 `fogDistance=0.067`、混向 `underwaterColor*0.15*max(eyeAdapt,0.4)`（439-454）。
- 体积光：阴影贴图空间行进、起点随机、结果写缓冲 alpha（`P:composite.fsh:437-485,597`）；天空 pass mip 重采样并与雾相加（`P:composite1.fsh:368-379,394-396,430`）。
- 焦散：同波面求导，`pow(luma(refract),5)*25`（`P:composite.fsh:305-333`，接入 566）。

### 2.4 水体

- 水族缓冲：`mc_Entity` 8/9 水、79 冰、90 传送门、95/160 染色玻璃（`P:gbuffers_water.vsh:75-79`）；写 gcolor/gdepth/gnormal/gaux2（`P:gbuffers_water.fsh:153-166`）。
- 波面 5 正弦 + 1 噪声、total×0.167、冰面停速、坐标预扭曲使垂直面也有波（`P:composite1.fsh:567-595`；同源 `P:gbuffers_water.fsh:45-71`；低频版 `P:gbuffers_water0.fsh:42-62`）；中心差分法线（`P:gbuffers_water.fsh:74-88,90-115`）。
- 反射：Chocapic13 血统分层递进射线（28 步、`ref=0.07` 细分、`inc=2.2` 步长增长、6 次收敛、边框 `1-cdist^10`），miss 回落程序化天空/太阳/云（`P:composite1.fsh:456-565`）。
- 折射：RGB 错位 ±0.007、强度 0.08 随深度衰减、gaux3 材质掩码防越界（`P:composite1.fsh:597-644`）；水面底色替换为 `vec3(0.3,0.65,1.0)*0.3`（`P:gbuffers_water.fsh:141`；未画出的水下副本 ×0.2，`P:gbuffers_water0.fsh:113`）；水下全屏正弦折射 0.003/速度 4.0（`P:final.fsh:152-162`）。

### 2.5 后处理

- 运动模糊：重投影 + 8 采样，速度钳 `motionblurAmount*0.01`（`P:composite2.fsh:43-88`）。
- Bloom：6 级 mip、每级 7×7 tent（`wg=(1-len/4)²*2^-0.5*20`）+ 固定偏移去相关，alpha 存场景亮度（`P:composite3.fsh:43-106`）；final 按 `pow(2..7,0.25)` 权重混合（`P:final.fsh:329-353`）；变形镜头取 mip4.5 双向 32 采样（355-385）。
- DOF：28 点圆盘 + 按 `factor` 选 mip；`HQFocus` 28 次深度均；`maxBlurFactor=0.6`、`blurStartDistance=100`、水下强制 0.75（`P:final.fsh:258-327`）。
- 色调映射（robobo1221 风格）：去饱和→对比→gamma2.2→`*1.7*exposure`→`1-exp(-x)`→gamma0.4545（`P:final.fsh:164-188`）。
- 其他：暗角 3.0/5.0（190-205）、信箱（207-217）、噪点 0.03（219-236）、色散 `offset 0.004*dist^2.5`（238-256）、雾模糊（414-437）、程序化脏镜头（120-150,387-411）。

### 2.6 下界 / 末地变体

- 下界：无太阳/环境项，打光 = `minimumLight*0.05 + 火把`（`P:world-1/composite.fsh:213`；调色板 `P:world-1/composite.vsh:54-60`）；final 开热浪 `heatwave`（偏移 0.0005、起雾距 75、频率 50/25，`P:world-1/final.fsh:41,176-188`）。
- 末地：打光 = `minimumLight*0.1*ambientColor(0.9,0.8,1.0) + 火把`（`P:world1/composite.fsh:215`、`P:world1/composite.vsh:55`）；final 开抖动 `jitter`（幅度 0.003、速度 0.4、行波阈值断续，`P:world1/final.fsh:40,424-455`）。

### 2.7 选项与预设

- 5 档预设链式一行（`P:shaders.properties:11-15`），GUI 14 页签（18-31）；选项沿用源码内 `#define X 默认值 // [可选值]`，同名选项多文件重复定义（如 `shadowSamples` 在 `P:composite.fsh:25`）。

---

## ③ 可借鉴点（12 条）

> 格式：技术 / `P:` / `A:` / 工作量 / 重复标注。数值均为包内默认值。

### K1 时间片混合调色板与全部出厂默认值（本包最重要产出）

- 技术：昼夜 4 段权重 + 日出日落细分权重，调色板按时段线性累加，再按 `weatherRatio` 二次增白；夜间低光统一偏冷蓝。出厂值：
  - 雾色：日出/日落 `(0.8,0.85,1.0)*0.7`，正午 `(0.77,0.83,1.0)*0.8`，午夜 `(0.65,0.8,1.0)*0.04`，雨天正午 `(0.9,0.95,1.0)*0.6` — `P:composite1.vsh:158-168`
  - 天空：正午 `(0.6,0.75,1.0)`，日出/日落 `(0.6,0.78,1.0)*0.7` — `P:composite1.vsh:136-144`
  - 地平线：正午 `(1.0,0.92,0.85)`（暖白），午夜 `(0.65,0.8,1.0)*0.06` — `P:composite1.vsh:146-156`
  - 云：正午白 `(1,1,1)`，日出/日落 `(1.0,0.8,0.65)` — `P:composite1.vsh:176-186`
  - 水下 `(0.3,0.7,1.0)` 全天、夜间 ×0.08 — `P:composite1.vsh:170-174`
  - 环境光 `(0.85,0.9,1.0)`、夜间 `(0.6,0.7,1.0)*0.04` — `P:composite.vsh:130-140`；直射正午 `(1.0,0.87,0.75)`、日出/日落 `(1.0,0.5,0.2)*0.8`、前后夜 `(1.0,0.3,0.1)*0.5` — `P:composite.vsh:142-148`
  - 火把 `(1.0,0.57,0.3)`、水色 `(0.7,0.85,1.0)`、**低光 `(0.65,0.8,1.0)`** — `P:composite.vsh:156-160`
  - 饱和/曝光/对比全 **1.0**，tonemap 曝光乘数 `1.7` — `P:final.fsh:24-27,179`；自动曝光量 `1.5` — `P:composite1.fsh:184-193`
- `A:` `shaders.properties:614-770`、`lib/color_controls.glsl:29-53`、`lib/settings.glsl:207-222`、`global/post/grading.glsl:110-196`、`lib/tonemap.glsl:191-224`
- 工作量：低（半天内，纯参数面）
- 重复标注：**部分与批次一重复**——"雾色与天空输出同源"（`SUMMARY.md:71`）、Purkinje 夜视蓝移 5 包印证（`SUMMARY.md:100`）。本包独有价值是一整套可对照数值表。

### K2 2D 程序云层 + 双采样云自阴影 + 天气云量曲线

- 技术：无 3D 噪声、无时域，4 倍频 2D 噪声按世界坐标/高度投影（`P:composite1.fsh:320-326`）；**同点前移 `lightVector*25` 再采一次作云自阴影**（297,328-330,341,358）；云量 `mix(0.6,0,sqrt(weatherRatio))`（332-336）；日出/日落染暖、夜间月光降至 0.05（347-349,353-355）；地平线淡出（339）。
- `P:` `composite1.fsh:282-366`（参数 287-291：`cloudCover 0.6/cloudOpacity 2.0/sunStrength 2.5/shadingStrength 0.15`）、`gbuffers_clouds.fsh:56-64`
- `A:` `global/atmosphere/clouds_planar.glsl:56-113`（半分辨率 3D + `cloud_temporal.glsl` + `cloud_shadow_cache.glsl`）
- 工作量：中（数天；仅"偏移自阴影"为半天级）
- 重复标注：**与批次一重复**——"云图视差云低档（无 3D 噪声/无历史）" SDV（`SUMMARY.md:123`）。

### K3 阴影图内行进式体积光 + alpha 复用 + 质量档 mip

- 技术：不做场景 march，只在阴影贴图空间按屏幕噪声起点行进累加 `shadow2D`（`P:composite.fsh:437-485`）；`vlRenderQuality=1/vlQuality` 控制步长，质量 >1 时转 mip 读取（`P:composite1.fsh:372-374`）；结果写 alpha（`P:composite.fsh:597`），雾按 `vlRaysStrength=0.5`、`minFogDensity 0.6` 吸收（`P:composite1.fsh:423-433`）；入水清零（396）；夜间/雨天乘 `DayToNightFading*(1-weatherRatio)`（375）。
- `A:` `global/atmosphere/volume_fog.glsl:114-201`、`global/post/godrays.glsl:53`、`program/display.fsh:95-97`
- 工作量：中（数天；雾吸收耦合为半天级）
- 重复标注：**部分与批次一重复**——"depth-only 4-tap godrays 低档"（`SUMMARY.md:119`）、"体雾非均匀步长"（`SUMMARY.md:73`）。

### K4 雾色随空气密度重映射 + 反射内复用同一雾

- 技术：`infl=mix(airDensity,1,TimeMidnight)`，`nFogColor=pow(fogColor,1/infl)/pow(infl,0.4)`（`P:composite1.fsh:411-415`），一个标量同时改浓度与色偏；`airDensity` 为用户滑条（默认 1.0，第 30 行）；散射使逆光发亮（408-418）；**SSR 命中点复用 `drawFog(...,true)`**（501）；雨天/午夜密度 ×2（389-390）。
- `A:` `global/atmosphere/fog.glsl:34-36,67-79,102-230`（Astra 有谷雾/晨雾/空气透视/群系染色）
- 工作量：低（半天内，公式需按 Astra 尺度重校）
- 重复标注：**与批次一重复**——"雾色与天空输出同源"（`SUMMARY.md:71`）。

### K5 解析波面（5 正弦 + 1 噪声）与中心差分法线，含垂直面

- 技术：`0.167*(noise*0.2+Σsin)`，先对世界坐标预扭曲使垂直墙面也有波（`P:composite1.fsh:571-589`；changelog "Proper water waves on vertical surfaces" `P:Changelog.txt:103`）；法线由 ±0.2 四点中心差分（`P:gbuffers_water.fsh:74-88`）；冰面停速（53）；低频版 6 次噪声平移（`P:gbuffers_water0.fsh:42-62`）。
- `A:` `global/water/surface.glsl:205-296`、`global/water/caustics.glsl:5-38`
- 工作量：低-中（半天内可作低配档波形）
- 重复标注：**与批次一重复**——"雨天波幅耦合 + 波形风格档"（`SUMMARY.md:240`）、"顶点 hash 水波低档"（`SUMMARY.md:122`）。

### K6 通道错位水下折射 + 水面掩码 + 深度衰减

- 技术：折射 UV 由波面梯度产生（`P:composite1.fsh:611-620`）；R/B 通道偏移 `±rgbOffset(0.007)` 产生色散（630-632）；强度 0.08 随 `exp(-pow(d*0.04,1.5))` 衰减（606）；**偏移后先用 gaux3 掩码验证仍是水/冰，否则退回原 UV**（624-627）。
- `A:` `global/water/refraction.glsl:11`、`global/water/absorption.glsl:13-56`
- 工作量：低（半天内）
- 重复标注：**部分与批次一重复**——"折射二次校验"（`SUMMARY.md:247`）；"零偏移折射早退"已在 Astra 落地（`SUMMARY.md:280`）。

### K7 Chocapic13 血统的分层递进 SSR

- 技术：命中后不结束，步长乘 `ref=0.07` 回退细分、连续命中 `maxf=6` 次才确认，未确认则乘 `inc=2.2` 继续（`P:composite1.fsh:456-526`，参数 460-463、判据 488、细分 511-518）；边框 `1-cdist^10`（496）；miss 用程序化天空+太阳+云重绘（548-551）；Fresnel `pow(1+NdotE,2)` 且太阳高光处强制 1（554-556）；强度由 gaux4 的 (反射/湿/水洼/湿度) 调制（539）。
- `A:` `global/water/raytrace.glsl:15-58`、`lib/sky_reflection_cache.glsl:20-31`
- 工作量：中（数天；细分判据为半天级）
- 重复标注：**与批次一重复**——"SSR 行进效率细节"（`SUMMARY.md:247`）、"SSR miss 回退天空缓存"（`SUMMARY.md:248`）。

### K8 量化湿身 + 噪声水洼掩码（一掩码两用：法线 + 高光）

- 技术：`getWetnessMap = pow(skyLightmap*max(dot(normal,up),0),7.5)` 后量化 10 档（`P:gbuffers_terrain.fsh:73-93`），无需引擎 wetness 状态；`drawRainPuddles` 4 倍频噪声减阈值，`cover 0.65/sharpness 3.0/size 0.5`，阈值随 `pow(wetness,0.5)` 由 1.8 降到 0.65（97-116）；同时用于法线扰动（219）与高光 `mix(minimumWetness*wetness, 0.8, puddle)`（232-241）。
- `A:` `lib/wet_material.glsl:8-23`、`global/atmosphere/weather.glsl:29-72`
- 工作量：低（半天内，参数对照/低配档）
- 重复标注：**与批次一重复**——"水洼掩码 + 孔隙度两层暗化 + 室内积水门"7 包印证（`SUMMARY.md:253`）。

### K9 地形 POM：步长按 pomDepth 缩放 + 距离淡出 + 顶部环绕保护

- 技术：`intervalMult=vec3(1,1,10/pomDepth)/pomSamples`，256 步上限、`maxOcclusionDistance=32` 外退回视差（`P:gbuffers_terrain.fsh:124-169`）；草/花顶部 `coord.t<mincoord` 时 `discard`（149-157）；`pomDepth` 默认 1.5、默认关闭（26-27）。
- `A:` 仅水面视差 `global/water/surface.glsl:293-296,341-347`；地形 POM 无实现
- 工作量：中-高（一周+，依赖材质包 PBR 管线）
- 重复标注：**与批次一重复**——"labPBR/POM 材质子系统"长期储备（`SUMMARY.md:271`）。

### K10 Bloom 六级 mip + 每级偏移去相关 + alpha 存亮度

- 技术：`composite3` 一次生成 6 级 mip，每级 7×7 tent + 固定偏移 `(0,0)/(0.3,0)/(0,0.3)/(0.1,0.3)/(0.2,0.3)/(0.3,0.3)`（`P:composite3.fsh:43-84,92-98`）；final 按 `pow(2..7,0.25)` 混合、`bmval=0.21/pow(7,0.25)`（`P:final.fsh:336-347`）；alpha 存亮度供变形镜头（`P:composite3.fsh:104`、`P:final.fsh:370-371`）。
- `A:` `global/post/bloom.glsl:32-167`、`program/composite1.fsh:20-25`（两 pass、4 级 mip、13/9/4 tap）
- 工作量：中（数天；每级偏移为半天级）
- 重复标注：**部分与批次一重复**——"mipmap 单 pass Bloom 低配档"（`SUMMARY.md:105`）。

### K11 DOF：28 点圆盘 + 按模糊量选 mip + 前/后景差异

- 技术：`factor=(depth-centerDepthSmooth)*blurFactor*7.5` 钳 ±0.6，采样用 `textureLod(...,mip*|factor|)` 以小核代大核（`P:final.fsh:282-320`）；`HQFocus` 28 次深度平均（273-280）；手部强制对焦（282）；水下强制 0.75（298-300）；可选距离模糊（290-293）。
- `A:` 无 DOF（全仓 `grep dof|bokeh` 零命中）
- 工作量：中-高（一周内；需新增对焦深度平滑与 TAA 顺序设计）
- 重复标注：批次一多包提及景深但未进 Top10。

### K12 维度屏幕扭曲：下界热浪 / 末地抖动

- 技术：下界在雾因子驱动下加正弦水平偏移（幅度 0.0005、频率 50/25、起雾距 75 块，`P:world-1/final.fsh:176-188`）；末地按三组行波阈值断续抖（幅度 0.003、速度 0.4，`P:world1/final.fsh:424-455`，调用 466）。均为最终 UV 偏移级改动。
- `A:` 无对应；最近者为 `global/dimension/end_kerr.glsl:175-176`、`global/dimension/end_system.glsl:62-78`（物理化流场）
- 工作量：低（半天内）
- 重复标注：批次一未出现同方向条目（新增）。

---

## ④ Astra 已有实现对照表

| 子系统 | KUDA 做法（`P:`） | Astra 做法（`A:`） | 哪边更省 | 误差/差异来源 |
|---|---|---|---|---|
| 天空/雾调色 | 顶点阶段 4+5 段权重累加 5 组颜色（`composite1.vsh:122-186`、`composite.vsh:130-160`） | CPU 表达式图（`shaders.properties:614-770`）+ tint（`lib/color_controls.glsl:29-53`） | Astra：每帧零成本；KUDA 每 pass 多 6 个 varying | KUDA 显式线性混合、可逐项对照；Astra 以 100=中性归一 |
| 打光合成 | 单 pass 全光照（`composite.fsh:547-576`） | `program/lit.fsh:200-254`、`global/lighting/diffuse.glsl:120,302` | KUDA 更省（无 AO/方向天光） | KUDA 无接触阴影/方向性天光遮蔽 |
| 阴影 | 8/28 圆盘手采样 + 斜率 bias + 阴天放大核（`composite.fsh:335-424`） | `global/lighting/shadowmap.glsl:54-90`（硬件 gather + 距离畸变） | Astra（gather 比 28 次采样省） | `tan(acos(direct))` 逐像素 bias 值得对照；核越大越糊 |
| 体积光/雾 | 阴影图内行进写 alpha（`composite.fsh:437-485`、`composite1.fsh:368-433`） | `global/atmosphere/volume_fog.glsl:114-201`、`global/post/godrays.glsl:53` | KUDA 更省（0 深度采样）；Astra 更准 | KUDA 无散射相位，godray 更条纹 |
| 云 | 2D 解析 4 倍频（`composite1.fsh:282-366`） | 半分辨率 3D + 时域（`clouds_planar.glsl:56-113`、`cloud_temporal.glsl`） | KUDA 更省；Astra 有视差与自阴影 | KUDA 无厚度/底影，唯一体积感来自偏移采样 |
| 水波 | 5 正弦 + 1 噪声（`composite1.fsh:567-595`） | 频谱 + Nyquist + 4 步视差（`global/water/surface.glsl:205-296`） | KUDA 更省；Astra 高频更稳 | KUDA 远距离爬行/闪烁（无 footprint 过滤） |
| SSR | 28 步 + ref/inc 细分收敛（`composite1.fsh:456-526`） | 预算 16/30/40 步（`global/water/raytrace.glsl:15-58`）+ 天空缓存回退（`lib/sky_reflection_cache.glsl:20-31`） | Astra（分档 + mip0 回退） | KUDA 用程序化天空重绘，随视角解析；Astra 缓存有球面映射失真 |
| 水下 | 双色混合 + 全屏正弦折射（`composite1.fsh:439-454`、`final.fsh:152-162`） | 光谱 Beer-Lambert（`global/water/absorption.glsl:13-56`）+ `lib/solas_water.glsl:115` | KUDA 更省（<10 行） | KUDA 深浅只由距离决定，无分通道吸收 |
| 湿身/水洼 | 天光×法线量化 10 档 + 噪声水洼（`gbuffers_terrain.fsh:73-122`） | 方块分类 4 类（`lib/wet_material.glsl:8-23`）+ 雨包络（`global/atmosphere/weather.glsl:29-72`） | KUDA 更省（无状态）；Astra 更可控 | KUDA 屋檐/洞口会误湿（只看天光×朝向） |
| Bloom | 6 级 mip + 偏移去相关 + alpha 亮度（`composite3.fsh:43-106`、`final.fsh:329-385`） | 两 pass 4 级、13/9/4 tap（`global/post/bloom.glsl:32-167`） | Astra（预算结构 + 档位）；KUDA 大尺度 halo 更平滑 | KUDA 固定偏移在小图可能出方向性纹路 |
| 材质 ID | 浮点区间 0.1 步进（`gbuffers_terrain.fsh:274-277` 等） | 位打包 `faceData`（`program/lit.fsh:24,104-108,200`） | Astra：32 位塞 15 类 + AO + 湿润 | KUDA 每类占一个 float 判定 |
| HDR 预算 | 全部 `/6.0` 压缩（`composite.fsh:41,597`、`composite1.fsh:692`） | 16F + YCoCg 方差裁剪（`SUMMARY.md:282`） | Astra（无量化损失） | KUDA 亮度 >6 截断；优点是不依赖 HDR 格式 |
| 后处理链 | 无时域/TAA（`final.fsh:441-468`） | `program/display.fsh:155-190` + `program/taa_resolve.fsh` | 视场景：KUDA 静止零鬼影、移动闪；Astra 稳但需 history | KUDA 阴影/反射边缘静止噪点可见 |

---

## ⑤ 许可可行性与"重写 vs 抄"边界

### 5.1 包内证据

- **无 LICENSE 文件**（全包仅 Agreement/Changelog/Credits）。`P:Agreement.txt:9-15` 为限制性协议：9 "modify my shaderpack ONLY for yourself!"；11 "not allowed to redistribute and/or reupload it!"；12 "not allowed to use content of my shaders!"；15 "please leave a note"。各 shader 头 13–18 行复述（`P:composite1.fsh:14-15`）。
- 代码含第三方血统：`P:composite1.fsh:458` "By Chocapic13"（SSR）、`P:composite3.fsh:45` "By Capt Tatsu"（Bloom）、`P:final.fsh:166` "Thanks to robobo1221"（tonemap）、`P:Credits.txt:10-16` 列举。即使上游按 BSD-3 登记，这些片段的授权来源需单独确认。

### 5.2 索引登记与包内证据冲突

索引登记 **BSD-3-Clause**（`INDEX-batch2.md:38`、`SUMMARY-batch2.md:47,69`），据此把本包列为"可复用，须保留版权声明"层；但该文本不在包内、无法自证。**裁定前按最保守解读执行：只借算法方向与参数对照，不搬代码**。

### 5.3 BSD-3-Clause 若成立的具体义务

1. 保留版权声明、三条许可条款与免责声明（源码/二进制再分发时随附完整文本，通常加文件头 + `THIRD-PARTY.md` 登记）。
2. 不得以作者/贡献者姓名或商标为衍生作品背书或推广（endorsement 条款）。
3. 不得附加额外限制（不能用更严协议再发布其代码）。
4. 修改文件应显著标注已修改。

### 5.4 "搬代码" vs "重写"的边界

- **可用**（BSD-3 成立且登记后）：不受版权保护的纯数学片段——`tan(acos(NdotL))` 斜率 bias、`pow(1+NdotE,2)` Fresnel、`exp(-pow(d*k,p))` 雾因子、tent 权重。
- **建议只读思路、独立重写**：整段函数结构（`draw2DClouds`/`raytrace`/`drawFog`/`calcBloom`/`renderDOF`），且含第三方血统标注；Astra 已有等价机制时按 Astra 约定重写（K1 进 `lib/settings.glsl`、K8 进 `lib/wet_material.glsl`）。
- **禁止**：复制贴图/噪声资产、逐字搬运整文件、用作者名背书、再分发本包。
- 登记纪律延续 `SUMMARY.md:141`：重写后文件头注明 "idea from KUDA Shaders 6.5.26"。

---

## ⑥ Top5 与暂缓项

### Top5（收益/工作量排序）

| # | 事项 | 依据 | 工作量 |
|---|---|---|---|
| 1 | K1 调色板出厂默认值对照（雾色/天空/曝光/饱和/低光冷色） | `composite1.vsh:122-186`、`composite.vsh:130-160`、`final.fsh:24-27` | 半天内 |
| 2 | K4 雾色随空气密度重映射 + SSR 命中点复用同一雾 | `composite1.fsh:411-415,501` | 半天内 |
| 3 | K2 云自阴影偏移采样（`lightVector*25`）+ 天气云量曲线 | `composite1.fsh:297,332-336,341,358` | 半天-数天 |
| 4 | K8 量化湿身（10 档）+ 水洼参数对照（0.65/3.0/0.5） | `gbuffers_terrain.fsh:73-122,232-241` | 半天内 |
| 5 | K6 RGB 错位折射 + 水面掩码保护 | `composite1.fsh:599-632` | 半天内 |

备选：K7 的 `ref/inc` 收敛判据（抗 SSR 漏检）、K12 维度扭曲（低成本氛围）。

### 暂缓项及理由

- **K9 地形 POM**：无材质包 PBR 管线，收益依赖外部资源；批次一已列长期储备（`SUMMARY.md:271`）。
- **K10 Bloom**：Astra 已成体系（两 pass 4 级 + 档位），额外 pass 边际收益低。
- **K11 DOF**：需新增对焦深度 uniform 并与 TAA 顺序协同设计，成本高于收益。
- **K3 体积光**：Astra 链路已更强，仅"超低配档"值得考虑。
- **K7 SSR 细节**：Astra 预算分档 + 天空缓存回退更成熟，只取收敛判据。
- **K12 热浪/末地抖动**：纯氛围装饰，优先级最低。
- 另两项**不建议迁移**：HDR `/6.0` 压缩（Astra 用 16F + YCoCg，无量化收益）、浮点材质 ID（Astra 位打包更省位，见 ④）。

---

## 附录：自抽查（成稿后重开源文件核对）

抽查方式：定稿后重新打开源文件读取引用行，核对内容与报告描述一致。

| # | 引用 | 核对结果 |
|---|---|---|
| 1 | `P:composite1.vsh:158-168` | 通过：158 `fogColor = vec3(0.0);`；160 正午 `(0.77,0.83,1.0)*0.8`；162 午夜 `(0.65,0.8,1.0)*0.04`；166 雨天正午 `(0.9,0.95,1.0)*0.6` |
| 2 | `P:composite.vsh:156-160` | 通过：156 `torchColor=(1.0,0.57,0.3)`；158 `waterColor=(0.7,0.85,1.0)`；160 `lowlightColor=(0.65,0.8,1.0)` |
| 3 | `P:composite1.fsh:184-193` | 通过：186 `exposureAmount=1.5`；188-189 eyeAdapt/午夜压制；191 返回 `1.0+aE_lightmap*exposureAmount` |
| 4 | `P:composite1.fsh:297` | 通过：`worldPos2 = gbufferModelViewInverse * vec4(fragpos + lightVector*25.0, 1.0)` |
| 5 | `P:composite.fsh:437-485` | 通过：437 `float getVolumetricRays()`；473 `vlRays += shadow2D(...)`；479 归一化 |
| 6 | `P:gbuffers_terrain.fsh:75-89` | 通过：75 `transitionMultiplier=7.5`；77 天光×朝上法线幂；89 第 10 档 `>0.47 -> 1.0` |
| 7 | `P:final.fsh:154-160` | 通过：154 `0.003`；155 `4.0`；158 正弦偏移；160 仅水下生效 |
| 8 | `P:world-1/final.fsh:176-188` | 通过：176 `#ifdef heatwave`；178 `0.0005`；181 `refractionStart=75.0`；188 偏移×fogFactor |
| 9 | `P:world1/final.fsh:426-455` | 通过：426 `jitterAmount=0.003`；427 `jitterSpeed=0.4`；455 `return vec2(coord.x+jitterX, coord.y)` |
| 10 | `A:global/water/surface.glsl:296` | 通过：`vec2 surface_parallax(...)`；同文件 205 `surface_height` |
| 11 | `A:global/post/grading.glsl:190-195` | 通过：190 `apply_grading`；192-194 vibrance→saturation→contrast；195 `apply_tonal_balance` |
| 12 | `A:shaders.properties:614,768` | 通过：614 `astraSkyNightUp=...`；768 `astraSkyDayUp=...` |
| 13 | `A:lib/settings.glsl:207-222` | 通过：207 `TONEMAP_OPERATOR 0`；209 `EXPOSURE 100`；211 `//#define AUTO_EXPOSURE`；214 `SATURATION 100`；216 `VIBRANCE 100`；218 `CONTRAST 102`；220 `COLOR_TEMPERATURE 0`；222 `#define BLOOM` |
| 14 | `A:lib/wet_material.glsl:16-23` | 通过：16 `astra_wet_material(uint)`；23 `astra_wet_gloss(...)` |
| 15 | `P:Agreement.txt:9-15` | 通过：9 "ONLY for yourself"；11 "not allowed to redistribute"；12 "not allowed to use content"；15 "please leave a note" |

抽查未发现行号偏移或描述不符项；报告内所有 `P:`/`A:` 行号均来自本次读取。
