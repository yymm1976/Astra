# simplicissimus 性能调研（batch4）

日期：2026-10-03。范围：只读调研，产物仅本文件；行号相对 `reference_shaderpacks/simplicissimus/shaders/`。
去重基线：`shader_research/SUMMARY.md`、`SUMMARY-batch2.md`、`SUMMARY-batch3.md`、`docs/2026-10-02-shader-reference-performance.md`、`docs/2026-10-03-batch3-selected-optimizations.md`（下称「五份材料」），以及任务背景列出的 Astra 已实现手段。

## 概况

- 定位：Modrinth v1.3a，234,519 下载。极简向、保留原版观感、只加动态阴影（lang/en_US.lang 内选项仅阴影/TAA/风/雾/labPBR/bloom 等少量）。作者 RRe36（shaderLABS 社区成员）。
- 血统：RRe36 自研，全部代码头为 `Copyright (C) 2022 RRe36`；与已研究的 Potato Shaders、Soft Voxels Lite 同作者但**不同代码库**（本包为 legacy `#version 120` + gbuffers 前向光照，#version 120、`gl_FragData`、`DRAWBUFFERS`；Potato 为现代结构），不构成同源包，故按完整包调研，不做「只报增量」。局部血统：`lib/shadowmap.glsl:14`「method based on code from robobo1221」；`program/temporal.glsl:37`「Temporal Reprojection based on Chocapic13's approach」；`deferred.fsh:44` + lang「promo-outline effect from CaptTatsu's BSL shaders」；`gbuffers_solid.fsh:151`「thanks for this fix in ymir niemand」。
- 许可：包内 `LICENSE`（98 行）为 RRe36 自定义许可，首行「All Rights Reserved unless otherwise explicitly stated」；§2 允许私有修改，§3 公开修改需作者明确授权且同许可，§4「Using parts of this projects source code as part of another, original project requires explicit permission」→ **不能代码级搬运**，只可按 Astra 现行「读思路 + 独立重写 + THIRD-PARTY.md 登记」口径（与 batch3 Potato/SVL 同作者同处理）。
- 规模：`shaders/` 树 118 文件 / 5,020 行（.fsh/.vsh/.glsl 口径）；其中 world-1、world1 两目录多为 15 行包装器，主世界代码约 2,900 行。

## 管线与调度

- program 清单（主世界，shaders/ 根）：`shadow`(vsh/fsh)、`gbuffers_basic/solid/terrain/textured/textured_lit/entities/hand/water/weather/skybasic/skytextured/beaconbeam/clouds`、`deferred`、`composite`、`composite1`（仅 `#include "/program/temporal.glsl"`）、`composite2`、`final`。world-1 另含 `prepare`（背景常量填充）与独立 `composite/composite1/composite2/composite3/final`；world1 同构。
- 开关：`shaders.properties:15 program.composite2.enabled=(bloom || useMotionblur)`；`:1 vignette=false`；`:2 separateAo=true`；`:4-8 sun/moon/fog/oldLighting/oldHandLight/supportsColorCorrection`。无 `program.*.enabled` 的其它条目、无预设 profile 系统。
- CPU custom uniform（`shaders.properties:34-96`）：upvec/sunvec/moonvec/lightvec 的归一化与视图/世界空间变换；`taaOffset` 的 frameCounter%8 八相表（:68-88）；四相白天权重 `daytime` 的 pow 组合（:90-96）。
- 分辨率/缓冲分档：**无 `size.buffer`、无自定义 colortex 格式**（`deferred.fsh:20-25` 的 RGB16/RGBA16 块整段在注释内）；`composite2.fsh:24` 仅在 bloom 时声明 `colortex0MipmapEnabled`；`program/temporal.glsl:18 colortex1Clear=false`（TAA 历史不清除）。MRT 按需：opaque 写 0,2（`gbuffers_solid.fsh:313`）、半透明写 3,2（:317）、sky 只写 0（`gbuffers_skybasic.fsh:138`）、TAA 写 0,1（`program/temporal.glsl:88`）、composite2 写 0,2（`composite2.fsh:170`）。
- 固定常量：`shadowMapResolution 2560` 硬编码在每个程序的常量区（如 `gbuffers_solid.fsh:25`）；无阴影距离/实体阴影/culling 属性和 `shaders.properties` 条目。

## 分模块性能手法清单

### 调度与阶段启停
- `shaders.properties:15` — bloom 与 motionblur 都关时 composite2 整 pass 停调度（五份材料已列为共识手段）。
- `shaders.properties:1` — 关闭原版暗角 pass（Iris 管线级开关，batch3 §2.1 已列）。
- `deferred.fsh:18,77-94` — deferred 只在 `promoOutline_enabled` 时有内容；默认关闭时退化为纯拷贝（见「反面印证」）。
- `world-1/prepare.fsh:20-23` — 下界用一次全屏常量雾色填充背景，替代天空几何/解析计算。
- `world-1/gbuffers_solid.fsh:37-39`、`world1/gbuffers_solid.fsh:38` — 下界/末地 gbuffers 完全不包含阴影采样与彩光代码（维度编译期砍链；Astra 维度独立程序目录已同型）。

### 地形光照与阴影
- `gbuffers_solid.vsh:110-123` — 阴影坐标在**顶点**阶段算好（`transMAD` 投影 + `warpShadowmap` 畸变），带法线偏移偏置。
- `gbuffers_solid.vsh:114` — 偏置同时按距离 `min(0.1+len/200,0.5)`、背光角 `(2-max(N·L,0))` 与分辨率对数项 `log2(max(128-res*0.2,e))/e` 缩放；`:192` 另加 `0.08*(2048/res)` 的 texel 偏置。
- `gbuffers_solid.fsh:249-257` — 主 pass 用硬件 `shadow2D`（:69-70 声明 `shadowHardwareFiltering`）；彩色阴影仅在 `|shadowtex0-shadowtex1|>0.05`（存在透明遮挡）且 `diffuse>0` 时才读 `shadowcolor0`（:253-255）——Astra 已有「遮挡时才读彩色阴影」「背光跳过」。
- `gbuffers_solid.fsh:78-92` — `hq_shadows`（默认关）：IGN 噪声给每像素旋转方向，2 次对角 tap + 中心 0.5 加权（3 tap 小核）。
- `gbuffers_solid.fsh:110-140` — `pixel_shadows`（默认关，WIP）：世界位置量化到 `pixel_shadow_res` 网格 + 沿光向偏置 + 深度 `-0.05/res`，即像素化/像素锁定阴影。
- `gbuffers_solid.fsh:104-108` + `gbuffers_solid.vsh:225-245` — 按 mc_Entity 列表给草/叶/发光块设 `noDiffuse=0.8` 漫反射下限，避免植物死黑。
- `lib/shadowmap.glsl:14-27` — robobo1221 径向畸变公式。
- `shadow.vsh:65-93` — 阴影 pass 的风位移只在 `windLod = length(position.xz) < 64.0`（:68）内执行，64 格外影子不再摆动。
- `shadow.fsh:25-27` — 阴影片元仅做纹理拷贝，另对 `blockEntityId==138`（信标）discard。
- `gbuffers_solid.fsh:259` — `shadow=min(shadow,diffuse)` 防止背光面漏光。

### 云
- `gbuffers_clouds.fsh:89-108` — 原版云几何 + 解析相位/天光着色（非 raymarch）；`:113` `alpha<0.01` discard。
- `gbuffers_clouds.vsh:56-59,67,85-89` — `instanceId` 支持双层云（第二层 +60 格、tint.a 减半、UV 翻转），由一个 pass 画两层（`cloud_twolayer` 默认关）。
- `gbuffers_skybasic.fsh:79-125` — 可选第二云层：平面求交后 1 次纹理采样，500–2500 格距离淡出（`s_secondCloudLayer` 默认关）。

### 雾与大气
- `gbuffers_skybasic.fsh:40-77` — 天空完全解析（零纹理采样）；星点在 `gbuffers_skybasic.vsh:89-91` 用 `gl_Color.r==g==b && r>0` 判定为 varying，`getSky` 内加回（:74）。
- `composite.fsh:56-82` — 主世界解析雾：高度项 `exp(-|UpDot|*0.6)`、太阳辉光 `pow6/pow3`、距离项 `1-exp2` 与 `dist=len/far` 归一化。
- `composite.fsh:124` — `if (scenedepth0 != 1.0 && matID > 0.01)`：用 colortex2 材质掩码跳过天空与无几何像素（天空/云的雾已在各自 pass 内完成）。
- `lib/fog.glsl:14-28` — 复用原版 `gl_Fog` 参数的解析雾备用路径。

### 水与水下
- `gbuffers_water.fsh:17-18` — `#define translucency` 复用 `gbuffers_solid.fsh` 全套前向着色。
- `gbuffers_solid.fsh:317-319` — 半透明写 colortex3（颜色）+ colortex2 的 .g 通道写水位掩码 `water`（`gbuffers_solid.vsh:164-166` 按 mc_Entity 8/9 置位）。
- `composite.fsh:84-97,129-147` — 双深度水柱：以 `scenepos1-scenepos0`（水面后深度差）为水内路径长度做指数吸收水雾，再按 colortex3 的 alpha 合并；`isEyeInWater==1` 时对全屏做水雾（:146）。
- `composite.fsh:99-106,147` — 岩浆雾常量色（`isEyeInWater==2`）。
- 无折射、无 SSR、无焦散、无水波法线（定位即「只加阴影」）。

### 粒子·实体·天气
- `gbuffers_solid.fsh:209-211` — 非半透明 alpha<0.1 discard（cutout 剔除）。
- `gbuffers_solid.fsh:236-239` — `isParticle` 直接置 `diffuse=1.0` 跳过 N·L 与背面判定。
- `gbuffers_weather.fsh:26-33` — 雨条只做 `texture*lightmap*color` + HDR 压缩，不进光照/阴影链。
- `gbuffers_entities.fsh`、`gbuffers_hand.fsh` 均为 `gbuffers_solid` 的 `#define` 特化包装（:14-16），无独立开销。

### 后处理与缓冲内存
- `program/temporal.glsl:18,80-91` — TAA 单 pass 同时写 colortex0（当前）与 colortex1（历史，不清除），省一次拷贝/ping-pong pass。
- `program/temporal.glsl:38-48` — Chocapic 式重投影；`:43` 用 `float(depth>0.56)` 门控是否加相机位移（手部不搬）。
- `program/temporal.glsl:50-78` — 3×3 当前帧邻域 min/max 钳制 + `taaClamp` 到 65535 + 速度项 `clamp(1-sqrt(len)/1.999)*0.35+0.6`。
- `composite2.fsh:42-77` — bloom：8 个尺度 × 49 tap 的 7×7 权重循环（最坏约 392 次采样，见反面印证）。
- `composite2.fsh:97-153` — 运动模糊：7 样本；`:140-143` 出屏即 break 并按实际样本数归一；`:107` bayer16 起点抖动；`:124-125` 模糊量除以 `frameTime*30` 并 clamp。默认关。
- `program/final.glsl:55-73` — final 读 colortex2 七个缩放坐标做 bloom 叠加；`:116-127` bayer16 位深抖动；`:231-254` 输出色域变换（P3/Rec2020/AdobeRGB 矩阵）；`:282-313` 主函数。
- `lib/common.glsl:14-20` — `compressHDR = color/8.0`、`decompressHDR = color*8.0`：以缩放存储扩大默认色深缓冲的可表示范围，每个 pass 压缩/解压往返（见反面/无法判定）。
- `gbuffers_solid.fsh:304`、`composite.fsh:149`、`program/final.glsl:284` — 压缩/解压调用点。

## 反面印证

1. `deferred.fsh:77-94`：promo outline 默认关（`:18`），该 pass 仍是全屏「读 colortex0 → 原样写回 colortex0」，每帧白付一次采样+写带宽与一次 draw；应有 `program.deferred.enabled` 门控或并入相邻 pass。
2. `composite2.fsh:42-77`：bloom 用 8 个缩放层各 49 次采样（最坏约 392 次），无阈值预滤波、无 mip 链、依赖隐式 LOD；Astra 的 0.25 捕获 + mip 链 + tap 分档显著更省，不值得借鉴。
3. `composite2.fsh:19` 与 `program/final.glsl:42`：bloom 的两处 `#define bloom` 独立开关；且 `colortex0MipmapEnabled` 声明在 composite2 的 bloom 分支内（`composite2.fsh:24`），而 final 读的是 colortex2 的缩放坐标（`program/final.glsl:60-64`）——colortex2 的 mipmap 从未声明，bloom 路径能否正确工作存疑（并入「无法判定」）。
4. `world-1/gbuffers_solid.fsh:45-46`（`world1/gbuffers_solid.fsh:45-46` 同款）：`lmaps` 先用 lightmap 纵轴采样计算，随即被 `pow(lmapcol,...)` 覆盖——天空光行采样是死代码/逻辑错，说明该包下界/末地光照未复核。
5. 全包无任何阴影投射剔除/距离属性（无 shadowTerrain/shadowEntities/shadowDistance 之类），影子开销只靠固定 2560 影图与「64 格外不摆风」，缺少 Astra 已有的实体投影开关、材质级提前退出等分层手段。
6. `program/temporal.glsl:38-48` 重投影不校验历史深度（只有 3×3 钳制兜底），靠钳制换稳定；Astra 有深度/反应掩码/植被运动历史校验，不应退回到该做法。
7. `composite.fsh:56-82` 与 `gbuffers_skybasic.fsh:51-74`、`gbuffers_clouds.fsh:79-87`：同一套雾/太阳辉光表达式在 3 个 pass 各写一遍（参数略异），复用与维护性差（非纯性能项，但属工程反面）。

## 新颖借鉴点

- A（低代价可直接排期）：**无**
- B（中代价需接线）：**无**
- C（大工程战略项）：**无**

逐候选去重（每条含 Astra 侧证据）：

| 候选（本包出处） | 去重依据 |
|---|---|
| 顶点阴影坐标 + 法线偏移偏置（`gbuffers_solid.vsh:110-123,192`） | Astra `program/lit.vsh:181` 已同型调用 `shadow_map_position`；偏置族已在 SUMMARY ②-1「GriAndEmin 防漏光偏置」「阴影畸变/偏置形式对照」列出；Astra `global/lighting/shadowmap.glsl:242-243` 已有径向+N·L 偏置 |
| hq_shadows 旋转 3-tap 核（`gbuffers_solid.fsh:78-92`） | SUMMARY ②-1 已列「R2/黄金角旋转盘抖动 PCF」；Astra `global/lighting/diffuse.glsl:271-273` 注释明确拒绝旋转核（与用户反馈的稳定性取向一致） |
| pixel_shadows 世界网格量化（`gbuffers_solid.fsh:110-140`） | SUMMARY ②-1「像素化阴影风格档」、batch3 §2.2「像素锁定阴影」均已列 |
| 场景色 /8 压缩存储（`lib/common.glsl:14-20`） | batch3 §3.4 Potato「场景色 /4 压缩（低）」已列；Astra 用 R11F_G11F_B10F（`lib/surface_buffers.glsl:14`）等显式格式，无新增收益证据 |
| TAA 双写 + 历史不清除 + 速度权重（`program/temporal.glsl:18,43,75,88`） | batch3 §3.3 VanillAA「TAA 不单开 pass、历史原地保留（colortex2Clear=false）」已列；Astra `program/taa_resolve.fsh:20` `RENDERTARGETS: 0,15` 已双写、`:148-152` 已有运动量可信度 |
| 阴影 pass 风距离门控 64 格（`shadow.vsh:68-90`） | Astra `global/lighting/wind.glsl:236-243` + `program/shadow.vsh:132` 已有 128–192 格渐弱/跳过（更细且与主 pass 同源） |
| 双深度水柱水雾（`composite.fsh:84-97,135`） | SUMMARY-batch2 ②-2 / ⑤-1 eclipse「双深度水柱低配水雾」已列；Astra `global/water/absorption.glsl` 按距离吸收已实现 |
| 材质掩码跳过天空雾（`composite.fsh:124`） | Astra 天空在 `program/deferred.fsh:305-336` 解析并就地算介质，等价机制已内化，无新面 |
| CPU custom uniform（`shaders.properties:34-96`） | Astra 已实现且更全（任务背景与五份材料共识 12 包印证） |
| composite2 熔断（`shaders.properties:15`） | 五份材料 10+ 包印证，Astra 已实现 |
| 天空解析 + 无纹理星点（`gbuffers_skybasic.fsh:40-77`） | Astra 程序化天空/星点已有（`global/atmosphere/stars.glsl` 等） |

结论：**该包没有 Astra 未实现、且未被五份材料列出的性能手法**；其价值在「极简管线承认不做的部分」与上面的反面印证。

## 无法判定项

1. `deferred.fsh:20-25` 缓冲格式块整段注释 → 各 colortex 实际格式取决于 Iris 默认值；`compressHDR /8`（`lib/common.glsl:14-20`）的净带宽收益与色深损失无法静态判定。
2. `hq_shadows`（`gbuffers_solid.fsh:19`）与 `pixel_shadows`（`:110`）都是硬编码注释 define，未进 `sliders=`/`options=` 注册（lang 里存在选项名），实际默认两者皆关；引用其开销时须注意。
3. TAA 历史 `colortex1` 格式未声明；`program/temporal.glsl:35` 的 `taaClamp` 上界 65535 暗示 16F，但包内无证据。
4. bloom 两处独立开关 + colortex2 mipmap 未声明（见反面 3）：bloom 路径的静态可工作性无法判定。
5. `gbuffers_solid.vsh:148-161` 的风材质列表与 `block.properties` 的 240/241（双层植物）在 1.14+ 分支的完整对应关系未逐版本核对；`world-1`/`world1` 的 vsh 是否也挂风（未逐行读完两个 72 行文件）需在采纳任何风相关结论前复核。
