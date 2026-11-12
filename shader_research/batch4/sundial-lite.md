# sundial-lite（batch4 逐包性能调研）

> 版本：Modrinth v1.2.0（63,002 下载，任务给定）。调研日期 2026-10-03，纯只读。
> file:line 基准：`reference_shaderpacks/sundial-lite/shaders/`（包内 shader 根即 `shaders/`，题述基准一致）。
> Astra 侧路径相对 `Astra/shaders/`；所有「未实现证据」的 grep 命令与命中数照录于 §五、§六。
> 去重前置：已读 `SUMMARY.md`、`SUMMARY-batch2.md`、`SUMMARY-batch3.md`、`docs/2026-10-02-shader-reference-performance.md`、`docs/2026-10-03-batch3-selected-optimizations.md`，其中列出过的借鉴点一律不列为新颖。

## 一、概况

- **定位**：作者自述「在质量、性能与兼容性之间平衡」（`Readme.md:3`）。相对付费 full 版，Lite **不做体素化与世界空间光线追踪**，把体积光与反射「从算 2 次降到 1 次」，代价是失去多次弹射反射，换来性能与 mod 兼容（`Readme.md` 末段 Features 对照）。是一款功能面很宽（阴影/焦散/SSAO+SSGI/POM/SSR/物理大气/体积云×3 种/体积光/DoF/TAA/运动模糊/Bloom/曝光/RCAS/DH+Voxy+Colorwheel+Physics Mod）但声明为「性能与兼容优先」的延迟管线包。
- **血统**：GeForceLegend 自研（代码头逐文件 `GNU GPLv3.0. Copyright (C) 2026 GeForceLegend`，例 `programs/deferred/Deferred0.frag:12`）。未发现与已研究的 42+20 款同源；包内显式注明的外部算法来源：Shadertoy XcdBWf 可见性位掩码（CC0/MIT 双许可，`programs/deferred/Deferred12.frag:49-67`）、Intel YCoCg（`programs/composite/Composite9.frag:32-34`）、NVIDIA Morton/TEA（`libs/Common.glsl:219-304`）、AMD FidelityFX RCAS（`programs/composite/Final.frag:30-48`）、Polyphony Digital GT7 tonemap（MIT 片段，`programs/composite/Composite14.frag:249-277`）、Adobe F82 Fresnel（`libs/Common.glsl:119-125`）。
- **许可**：**GPL-3.0**（`LICENSE:1-2` 为 GPLv3 全文；`Readme.md:3` 明示 "using GNU General Public Licence 3.0"）。理论可代码级改编（义务：保留版权与许可、附全文、标注修改）；但 Astra 现状为混合许可（Steadfast 派生 GPLv3 + 其他来源），是否吸纳需走 SC-14/THIRD-PARTY 台账（见备注）。
- **规模（整包口径，实测）**：
  - `shaders/` 树共 **356 文件**；代码文件（.glsl/.fsh/.vsh/.csh/.vert/.frag/.comp）**341 个 / 10,407 行**。
  - 分目录：根入口 100 文件 / 397 行；`programs/` 47 文件 / **6,435 行**；`libs/` 12 文件 / 2,656 行；`settings/` 2 文件 / 185 行；`world-1/` 94 文件 / 360 行；`world1/` 94 文件 / 374 行。
  - **口径校正**：任务给定的「约 356 文件 / 3,972 行」= 全树 10,407 − `programs/` 6,435，即未计 `programs/` 子目录。入口（根/world-1/world1）确实薄（多为 4 行 include），但 `programs/`+`libs/` 是实质代码，不能按「多为薄入口」低估工作量。
  - 非 shaders/ 代码目录：无。资源：`shaders/textures/`（noise.png 64×64、rain_ripple.png、AtmosphereTransmittance.bin 256×256 RGB16）、`lang/`（en_us 425 行 / zh_cn 467 行）。
- **世界结构**：根目录 = 主世界；`world-1/`、`world1/` 为薄壳，include 同一批 `programs/**`，仅入口宏不同（根 `shadow.fsh:3 #define SHADOW_AND_SKY`；`world1/deferred11.fsh:3 #define THE_END`；`world-1/deferred12.fsh:3 #define BASIC_LIGHT 0.01`）。与 Astra 的 world 薄壳同构（SUMMARY.md ②-7 已列，仅维持）。

## 二、管线与调度

- **program 清单（根目录口径；world-1/world1 同集合）**：
  - gbuffers：`terrain / water / hand / hand_water / entities / entities_glowing / block / textured / basic / armor_glint / beaconbeam / spidereyes / damagedblock / weather / skybasic / skytextured / clouds（discard）/ physics_ocean_v2 / physics_ocean_shadow_v2 / dh_terrain / dh_water / voxy_opaque / voxy_translucent / clrwl_*`（Colorwheel 兼容）。
  - shadow：`shadow.fsh/vsh` + `clrwl_shadow_distort.csh`（Colorwheel 光源剔除 compute）。
  - deferred：`deferred`（Deferred0.frag，深度烘焙 + 上一帧位掩码重投影）、`deferred11`（直射光照 + PCSS + 屏幕空间阴影，写深度供 GI 累积）、`deferred12`（可见性位掩码追踪 + indirect 光照）、`deferred99`（默认禁用，仅 VOXY 时启用）。
  - composite 0-14 + final：0=反射追踪；1/2/3=反射过滤三段；4=天空与云（`!UNDERGROUND_MODE`）；5=半透明混合 + 体积光 + 体积雾 + 折射；6=DoF 深度准备；7=CoC spread + TAA velocity/权重；8=DoF 采样（`DEPTH_OF_FIELD`）；9=TAA 混合；10=Bloom mip 预滤 + 运动模糊 + 曝光；11/12/13=Bloom 可分离模糊；14=后处理（tonemap/暗角/色散/雨雾 bloom 混合）；final=RCAS 锐化。
- **调度（`shaders.properties`）**：
  - 程序门控只有 3 组（`:58-73`）：`program.composite1/2.enabled = REFLECTION`；`program.composite4.enabled = !UNDERGROUND_MODE`；`program.composite8.enabled = DEPTH_OF_FIELD`；`deferred99` 仅 `VOXY`（`:69-73`）。其余全屏 pass 常开。
  - 关闭原版项（`:1-5`）：`clouds=off`、`oldLighting=false`、`underwaterOverlay=false`、`vignette=false`、`sun=false`。
  - **无 `size.buffer`、无 `renderResMul`、无 `profile`**（grep 均为 0 命中）：全部效果按显示器全分辨率运行；质量只能靠编译期 `settings/GlobalSettings.glsl`、`settings/CloudSettings.glsl` 常量与少量滑条改采样数/步数，不能降缓冲分辨率。
  - `flip.*` 13 条（`:21-33`）声明跨 pass 原地复用；`blend.*` 覆写（`:35-56`）：全部 gbuffers 默认 `ONE ZERO ONE ZERO`（不写 alpha），`gbuffers_weather = ZERO ONE ONE ZERO`（只写 alpha，复用 colortex4 alpha 携带天气光照标量）。
  - 缓冲常量声明集中在 `programs/composite/Composite13.frag:24-61`：`colortex1/2/3/5/6/7Clear=false`、`colortex0ClearColor/c4ClearColor`、`noiseTextureResolution=64`、`sunPathRotation=-40`、`shadowMapResolution=2048`、`shadowDistance=120`、wetness/dryness halflife=100；**注意格式声明块（:24-38）整段在 `/* */` 内**（见 §七-3）。
  - CPU/帧级自定义 uniform（`:210-274`）：`screenSize/texelSize`；天气 `hasWeather/hasWeatherSmooth/hasRainSmooth`（`smooth()` 平滑）；`frameIndex/jitterX/Y/taaOffset/prevTaaOffset`（16 帧抖动序列）；`cameraMovement`；`shadowDirection/sunDirection/lightAngle`；**`shadowModelViewProj0-3`（把 shadowModelView×shadowProjection 的矩阵积在 CPU 展开成 4 个 vec3）**；`viewShadowDirection`；`sunlightColor`（地平吸收 + 日落钳制解析式）；`rainyMieBeta`。
  - 缓冲用途（据代码与常量）：c0=场景色+MAT 数据（RGB16）/c1=法线+材质（RGBA16）/c2=geoNormal+lightmap+matID/parallax（RGBA16）/c3=光照（RGBA16F，兼作 VBGI 辐射源）/c4=反射 + alpha 天气标量（RGBA16F）/c5=VB 位掩码历史（RGBA16F）/c6=R32UI 深度+辅助标量/c7=曝光/中心深度 + OptiFine 透射 LUT（RGBA32F）；`Composite10.frag:34` 打开 `colortex3MipmapEnabled` 供 Bloom 直采场景 mip 链。

## 三、分模块性能手法清单

> 每条 = file:line + 机制一句话。标〔A 有同类〕者表示 Astra 已有等价机制或已列入既有汇总（去重证据见 §六）。

### 调度与阶段启停
- `shaders.properties:58-73` — `program.*.enabled` 布尔组合按功能停整 pass（反射过滤 ×2、天空云、DoF、VOXY deferred99）〔A 有同类〕。
- `shaders.properties:1-5` — 关闭原版云/太阳/水下叠加/暗角，由自绘链接管〔batch3 已列，A 未实现，见备注〕。
- `shaders.properties:21-33` — 13 条 `flip.*`：声明读后写缓冲的原地乒乓，意图免除 Iris 的全屏拷贝（语义/收益见 §七-1）。
- `programs/composite/Composite2.frag:36-40` — 无反射贡献的像素直接 `discard`，不写 colortex4。
- `programs/composite/Composite4.frag:59-79` — 只有 `depth>=1` 的天空像素才跑解析大气/云；有几何深度的像素跳过整段。
- `programs/deferred/Deferred12.frag:395-438` — 只对 `abs(depth)<1` 的实心像素做 VB 追踪与 indirect 光照。
- `programs/composite/Composite0.frag:331-371` — 只有水面像素且 `reflectionStrength>1e-5` 才发射射线。
- `programs/composite/Composite10.frag:109-120` — 运动模糊只在选项开启时读 velocity 并混合。

### 地形光照与阴影
- `programs/deferred/Deferred11.frag:52-167` — PCSS：3×3 blocker search（:84-94）+ 9 样本黄金角旋转盘（:117-144），半影半径 ∝ 平均遮挡深度（:96）〔PCSS 为批次一/三已列方向〕。
- `programs/deferred/Deferred11.frag:95` — blocker 全亮（depthSum≥8.9999）或出界时整段跳过 PCSS，只乘 skyLight。
- `programs/deferred/Deferred11.frag:121-124` — `normalFactor≈0` 时跳过 shadowtex0 采样（背光/无漫反射面）。
- `programs/deferred/Deferred11.frag:134-143` — 透明阴影仅在 shadowtex0 遮挡时读 shadowcolor0〔A 已有「遮挡时才读彩色阴影」〕。
- `libs/Shadow.glsl:25-48` — 水面焦散在 shadow pass 按 texel 烘焙进 shadowcolor0（r=强度、y/z=高度分数、w=斜率），接收端一次取数〔A 已有解析焦散记录于 shadowcolor0〕。
- `libs/Shadow.glsl:89-96`、`programs/gbuffers/Shadow.vert:114-133`、`programs/gbuffers/Shadow.frag:88-89` — **单张阴影图象限打包**：不透明居 (0.75,0.75) 象限、透明 x-1、水 y-1；frag 按 texel 距中心 0.25×res 与 `fwidth(shadowOffset.x)` 剔除跨象限碎片，从而不给透明/水各开一个附件（见 §六-2 为何不作为借鉴点）。
- `programs/deferred/Deferred11.frag:169-258` — 屏幕空间阴影：12 步屏幕射线 + 命中后 textureGather 双线性深度细化（:245-250）〔接触阴影为批次一/二/三已列长期方向〕。
- `programs/deferred/Deferred0.frag:41-65` — 一次性把 POM/手部修正后的深度烘焙进 colortex6，供全链复用（下游不再重算视差求交）。

### 云
- `libs/Cloud.glsl:49-66` — 体素块状云用 Amanatides-Woo DDA 走 64² 噪声纹理定义的 3D 体素场，`nextVoxel.y>0.5`（出层）即 break，最多 10 步、每步 1 次纹理取数。
- `libs/Cloud.glsl:52-58` — 首次命中即记录 cloudPos/法线；`unHitted`（:275）只让深度推进到首次命中（首次命中结构，A 已有）。
- `libs/Cloud.glsl:225-291` — 真实云：先球面求交裁剪积分区间（:231-252），步数固定 16 档，`cloudTransmittance<0.0001` 透射中断（:274）〔A 已有透射中断〕。
- `libs/Cloud.glsl:168-223` — 云光照：光向双 march（太阳与月亮共用同一批步进，:181-194）；权重常量 `const` 预计算（:165-166）。
- `libs/Cloud.glsl:307-350` — 块状云影独立 DDA（5-10 步）供地形/体积光消费〔A 已有云影独立缓存，机制更强〕。
- `libs/Cloud.glsl:381-416` — 真实云影为**解析单平面采样**（求与云中面的交点后只采噪声，不 march），淡出用 exp2。
- `libs/Cloud.glsl:428-476` — 2D 平面云：单平面交 + 固定 octaves 噪声，命中后才算光照〔A 有同类〕。
- `libs/Cloud.glsl:352-379` — 云影 3D 噪声用 2 次 `textureGather` + y/z 通道混合得到 4×2 格点，2 条指令替代 8 次取数。

### 雾与大气
- `libs/Atmosphere.glsl:37-57` — 透射 LUT（256×256 RGB16，`shaders.properties:14-19` 以 Iris `customTexture`/OptiFine `colortex7` 双写法绑定）一次双采样同时取日/月两侧透射。
- `libs/Atmosphere.glsl:110-141` — 视线步进非均匀（stepUnit 线性增长：近密远疏），每步用解析密度 exp2 + LUT〔非均匀步长为批次一已列〕。
- `libs/Atmosphere.glsl:59-153` — 天空散射单次调用同时产出散射+透射；`planetIntersectionData`（:15-25）一次点积复用给大气/云/反射三处。
- `libs/Atmosphere.glsl:275-293` — 固体雾一次 exp2（含瑞利/米氏双通道）+ 相函数，g 随深度改变。
- `programs/composite/Composite5.frag:356-433` — 体积光：步进距离先由视界椭球公式封顶、再被吸收系数解析截断（:363-364，`min(64/|β|, 5000·e^(−6|β|))`）；步长/吸收指数外提到循环外（:367-373）；每步阴影坐标越界早退（:394-397）；透射递推（:430-431）〔A 已有体积雾自适应步进 + 光束距离上限，见 §六-5〕。
- `libs/Common.glsl:89-101` — `smooth3DNoise` 用 64² 纹理的 y/z 两通道 + `17/64·z` 偏移做 3D 值噪声，一次双线性取数 + 一次 z 混合。
- `programs/common/Common.vert:99-102` — `skyColorUp`（天空顶环境色）在全屏 pass 顶点阶段算一次，作为 flat 插值常量供片元〔顶点阶段下沉，A 有「顶点常量平替」家族〕。
- `programs/composite/Composite14.frag:456-457` — 雨雾与 bloom 的混合按 skyLight/深度解析式，无额外 pass。

### 水与水下
- `libs/Water.glsl:9-21` — Gerstner 近似：纹理噪声 warp 的 cos 波；高度层数与法线层数分开配置（:6-7）。
- `libs/Water.glsl:38-58` — **单次 `textureGather` 取格点四角，用 fade 导数加权差分同时得噪声值与解析梯度**（法线）；Astra 水波已用同型实现（`global/water/surface.glsl:51-65`，注释即写「一次 textureGather…解析梯度」）→ §六-3。
- `libs/Water.glsl:79-105` — 波形求交 5 步前进 + 5 步收敛，命中即 break；步长按切线方向投影自适应（:83-87）。
- `programs/composite/Composite0.frag:116-317` — 每像素 1 条 VNDF/分布射线 SSR：屏幕边界预算 `projIntersectionScreenEdge`（:150）、16 步 + 5 次二分（:183-217）、厚度阈值按手部/距离（:178-182）；未命中回退解析天空+云（:247-279）〔A 已有 SSR 有限步进+二分+出屏退出+置信度、miss 回退天空缓存〕。
- `programs/composite/Composite1.frag:29-40`、`Composite2.frag:29-41`、`Composite3.frag:28-104` — 三段粗糙度感知反射过滤：指数权重混合法线/粗糙度/深度项 + 蓝噪声偏移，逐级缩小半径；Astra 走「命中后按粗糙度变半径的加权场景采样」（`program/water.glsl:340-352` 经 `water_sample_path`）→ §六-4。
- `programs/composite/Composite5.frag:129-179` — 折射一次偏移 + 屏幕边界收缩 + 目标深度校验后才改写。
- `programs/composite/Composite5.frag:293-329` — 水下/岩浆/细雪雾各自一次吸收 exp + 一次散射，无 march。
- `libs/Atmosphere.glsl:299-316` — `waterFogAbsorption/Scattering` 与体积光共用同一吸收/散射系数表〔A 已有按距离水下吸收〕。

### 粒子·实体·天气
- `programs/gbuffers/Weather.frag:38-50` — 雨雪几何：单纹理两次采样 + 双色差判定雨/雪 + alpha 与雨滴尺寸裁剪；`albedo.w<max(0.1,alphaTestRef)` discard。
- `programs/gbuffers/Weather.frag:52-63` — 天气 pass 只输出一个标量到 colortex4 alpha（着色器混合覆盖为 `ZERO ONE ONE ZERO`，`shaders.properties:56`），复用途经：天气光照数据不另开缓冲〔批次三已列「效果量复用 alpha 通道」〕。
- `programs/gbuffers/Textured.frag:187/190/255` — 粒子/实体按色值与 alpha 早退 discard。
- `programs/gbuffers/Terrain.vert:58-122` — 顶点级材质解码：`material>1` 才进入特殊方块判定（常见方块 early break），波类型/种类用位域打包在 mc_Entity〔位打包为批次二已列，A 有 block.properties 材质分级〕。
- `programs/gbuffers/Terrain.vert:146-158` — atlas 图集边界（coordRange）在顶点算好随 `noperspective` 传递，供自定义各向异性过滤/视差在片元安全取样。
- `programs/gbuffers/Shadow.vert:75-112` — 植物波动在 shadow 顶点与 gbuffer 顶点用同一噪声函数/相位（投影与可见几何一致）〔A 已有植被风场 LOD 实现〕。
- `libs/Parallax.glsl:1-10` — 雨波纹用 60 帧滚动子图，一次采样（`gaux2=rain_ripple.png`）。
- `libs/Parallax.glsl:154-203` — 体素视差（POM）用 2D DDA 逐纹素步进 + tile 取模，命中即停。
- `libs/Parallax.glsl:16-58` — 内置各向异性过滤：由纹理梯度解析足迹（Shadertoy 4lXfzn），质量 0 时用蓝噪声单采样退路。

### 后处理与缓冲内存
- `programs/composite/Composite7.frag:107-166`、`Composite9.frag:128-149` — TAA：velocity 重投影（含手部/视差/负深度 LOD 分支）、blendWeight 由位移量与出屏/深度置信（`Composite7.frag:168-173`）门控。
- `programs/composite/Composite9.frag:35-88` — YCoCg 邻域 AABB/方差裁剪（9 texelFetch 两阶矩）；`:101-126` Catmull-Rom 5 抽头历史采样〔A 已有 YCoCg 钳制；Catmull-Rom 为批次一/二/三已列候选〕。
- `programs/composite/Composite7.frag:45-105` — 3×3 min/max 用 2 次 `textureGather` + 2 次角点 `texelFetch`（getClosestDepth/getFarthestPrevDepth）〔A 已有同型 TAA gather，`program/taa_resolve.fsh:28-40`〕。
- `programs/composite/Composite10.frag:34-57` — **Bloom 直采场景缓冲自带 mip 链**（`colortex3MipmapEnabled=true`），并以坐标指数位 `floatBitsToUint(1−coord)&0x7F800000` 识别当前像素所属 mip 区域，单 pass 完成预滤〔批次三已列「直采场景 mip」「mip 打包单 pass」〕。
- `programs/composite/Composite11.frag:27-48`、`Composite12.frag:16-39`、`Composite13.frag:63-88` — 打包 mip 上的可分离 5-tap 高斯（权重表）+ 相邻 texel 夹取到本 mip 窗口、mip 外 `discard`；末级 9-tap 盒式融合。
- `programs/composite/Composite14.frag:61-104` — 7 级 mip 固定权重合成，7 次采样完成全 Bloom〔A 已是 0.25 捕获 + 2 pass + 4 级 mip，已知方向〕。
- `programs/composite/Composite10.frag:59-85` — 曝光：8×8 网格在选定 mip 上采样（中心加权），变暗响应快于变亮（`step(curr,prev)*2+2`），1×1 历史（colortex7.w）〔复杂自动曝光为批次一已列，A 已有 64-tap+1×1 历史〕。
- `programs/common/Common.vert:58-60`、`programs/composite/Composite9.frag:167-179` — prevExposure/中心深度用 colortex6、colortex7 的固定 texel 传递，并在缓冲翻转时经顶点阶段搬运不丢信息。
- `programs/composite/Composite10.frag:87-101`、`Composite11.frag:50-75` — 运动模糊两段式：第一段按速度 N 抽头，第二段仅在屏幕速度 >1px 时补 5-tap〔运动模糊为批次二已列，A 未采用〕。
- `programs/composite/Final.frag:62-108` — AMD RCAS 3×3 锐化（噪声检测默认关）〔输出锐化/CAS 为批次二/三已列〕。
- `libs/Common.glsl:42-52` — `blueNoiseTemporal`：64² 噪声纹理 + 无理数逐帧偏移（R2 序列族，批次三已列为已列候选）。
- `libs/GbufferData.glsl:204-258` — 通道打包：`pack2x8Bit`（两 8bit→一个 16bit 通道）、`packM3P13`、`pack2x16Bit`、**`packF8D24`（8bit 帧数 + 23bit 深度打进一个 uint）**；`:312-359` 解包。
- `libs/GbufferData.glsl:444-458` — 屏幕空间射线的边界交点用位运算 min 取四边最早者（SSR/屏幕阴影/体积光复用）。

## 四、反面印证（不值得学的性能做法）

1. **零缓冲分档**：无 `size.buffer`/渲染缩放（grep 0），SSR、DoF、Bloom 中间级、TAA 历史全部全分辨率；低配只能砍步数/关功能，不能降缓冲分辨率。Astra 的 `size.buffer` 分档是更强纪律，不应回退。
2. **关过滤不收 pass 成本**：`REFLECTION_FILTER=0` 时 `composite1/2` 仍按 `REFLECTION` 全屏执行（`shaders.properties:58-59`；`Composite1.frag:36-38` 调用无条件，`Composite2.frag:36-40` 只对无反射像素 discard），精细过滤关闭后仍付两趟全屏 dispatch。
3. **PCSS/屏幕阴影无质量梯**：`Deferred11.frag:28-31` 把 PCSS（9 blocker + 9 PCSS）与 12 步屏幕空间阴影常开；屏幕阴影对远处像素仍完整追踪（`:218` 只是把结果按权重混回，追踪本身已付）。
4. **辅助标量寄生在深度/曝光缓冲的魔数 texel**：`Deferred0.frag:168-175` 写、`Common.vert:58-96` 读、`Composite6.frag:56-61` 再搬运；耦合紧、易错。Astra 用 1×1 专用缓冲（colortex10 曝光、colortex17 状态）表达同类契约更清晰。
5. **无质量预设层**：grep `profile` 0 命中，所有档位改动靠编辑 `settings/*.glsl` 常量重编译，滑条只覆盖采样/步数；对低配一体机不友好。Astra 的预设体系更优。
6. **格式声明悬空**：缓冲格式整段被 `/* */` 注释（`Composite13.frag:24-38`），HDR 中间格式是否生效无法从包内判定（见 §七-3），工程严谨性弱于 Astra 的显式 `const int colortexXFormat`。

## 五、新颖借鉴点

> 每条均先以多组关键词 grep `Astra/shaders` 验证「无等价实现」；Astra 侧证据附命令与命中数。

### A 组（低代价可直接排期）

无。

### B 组（中代价需接线）

无。

### C 组（大工程战略项）

1. **屏幕空间可见性位掩码 SSGI/SSAO（SSVBM，含时域重投影与帧数加权）**
   - 机制：对每个实心像素以 1 条（可配 1-8）屏幕射线、16 步（可配 4-128）行进；每步把遮挡体在半球上的角区间映射为 32 位掩码中的位（切片 CDF 映射 + 位运算，`Deferred12.frag:344-355`），把该步**新增可见**的角区位数作为权重，从上一 pass 的已着色场景（colortex3）累积一次辐射→屏幕空间 GI（`:357-364`）；全部遮挡位/32 计 AO（`:368-369`）；本帧结果与上一帧重投影结果按 `1/帧数` 混合（`:419-421`，帧数打包在 colortex3.w，`Deferred0.frag:176`），重投影用 2×2 加权双线性（`Deferred0.frag:100-134`）；射线步长按屏幕投影长度指数增长（`:278,301-302`）。整个 GI 只用 1 条屏幕射线/像素 + 位计数（`Common.glsl:42-47`），无光源列表、无体素、无 RT。
   - 来源：`programs/deferred/Deferred12.frag:236-374`（算法编辑自 Shadertoy XcdBWf，双许可 CC0/MIT，`:49-67`）、`programs/deferred/Deferred0.frag:100-134`、`libs/Common.glsl:42-47,306-327`。
   - Astra 侧未实现证据：`grep -rniE 'bitmask|occbits|countbits|vbgi|ssgi' Astra/shaders` → **0 命中**；`grep -rniE 'ssgi|screen.?space.?gi|global illumination|bounce'` → 仅 `global/lighting/wind.glsl:192` 注释含 "bounce"，无实现。Astra 现只有 12 样本黄金角 AO + bent normal（`program/ssao.fsh:65-104`），无任何 GI、无位掩码/可见性追踪。
   - 迁移代价：大工程——新增 trace pass（可半分辨率）、历史缓冲与重投影阶段、（可选）GI 接线到 indirect 光；建议先只做「位掩码 AO + 1 射线」A/B 再定。
   - 备注：既有 SUMMARY 已把「Astra 无 GI」与 RSM/ReSTIR/体素日照三条 GI 路线列为待决，但**本机制（角向位掩码屏幕空间 GI）与那三条均不同源**，且上游算法为 CC0/MIT，若统帅认为「GI 整体已有路线」可降级为储备（见返回备注）。

### 无法判定

1. **`flip.*` 13 条声明**（`shaders.properties:21-33`）：目的是读后写缓冲的原地乒乓、可能免除 Iris 一次全屏拷贝；Astra `grep -c 'flip\.' shaders.properties` = **0**。但 Iris 内部 flip 语义与真实收益无法从包内源码判定，需要 Iris 文档/实机 profile 才能确认是否值得补声明。
2. **体素块状云 DDA**（`libs/Cloud.glsl:17-112`）：Astra `grep -rniE 'nextlength|blocky|\bDDA\b'` = **0**，表示确未实现；但块状云是另一套云表示（风格档），不是对 Astra 平面云的优化，且「空区跳过/首次命中/距离 break」已按 SUMMARY-batch3 §2.5 #3 视为 Astra 已覆盖手段。是否作为新云档立项取决于产品取向。
3. **缓冲格式块被注释**（`programs/composite/Composite13.frag:24-38` 整段在 `/* */` 内）：包内无法判定 colortex3/4 是否真为 RGBA16F；若走 Iris 默认格式（可能 RGBA8）则 HDR/位掩码链路会被截断。这影响对其实测画质/性能的任何外推。

## 六、去重排除（grep 命中 Astra 等价实现/已列清单，不作为新颖点）

1. **阴影四象限打包 / 透明阴影同图偏移**（`Shadow.vert:114-133`、`Shadow.glsl:89-96`）：Astra 以单张 shadowcolor0 同时承载彩色阴影 tint 与水面焦散数据（`program/shadow.fsh:34-45,80-97`），无需第二附件；Astra 不存在 shadowcolor1，象限打包省不下附件/带宽，属等价实现。
2. **CPU 展开 shadowModelViewProj 矩阵积**（`shaders.properties:235-258`）：属 Astra 已实现的「帧不变量 CPU 预计算」机制的具体应用；Astra 亦在 CPU 侧展开光源/矩阵相关量为自定义 uniform（`lib/uniforms.glsl`、`shaders.properties` 光向量表达式，见 `docs/2026-10-02-shader-reference-performance.md` 采用表），仅未对 shadow MVP 做同样展开，收益=每像素省一次矩阵乘，登记为已知家族。
3. **纹理噪声 + textureGather 解析梯度水波**：Astra 水波已用同型（`global/water/surface.glsl:51-65` 注释明示一次 textureGather 解析梯度；`lib/water_wave_lens.glsl:9` 亦用 gather），且 Astra 另有 Nyquist 距离滤波（`surface.glsl:212-296`）。
4. **SSR 有限步进/二分/出屏/置信度/miss 回退**（`Composite0.frag:116-317`）：批次一/二/三已列且 Astra 已实现（`global/water/raytrace.glsl:28-111`、`program/water.glsl:340-363`）；Astra 反射命中另有按粗糙度变半径的加权场景采样（`water_sample_path`，`program/water.glsl:345-352`），与 sundial 三段过滤为同类机制。
5. **体积光视界/吸收截断与平行阴影空间行进**（`Composite5.frag:363-364,367-373`）：Astra 体积光已有 48 格固定上限（`lib/water_palette.glsl:11 astraWaterShaftRange=48`）与体积雾 192 格上限 + 自适应步数/前缀步（`global/atmosphere/volume_fog.glsl:36-58,120-145`），平行阴影空间行进已按 batch2 落地（`volume_fog.glsl:120-145`，逐样本保留除法）。
6. **云：透射中断/首次命中/空区/距离 break/云影独立缓存**：批次一/三已列且 Astra 已实现（`global/atmosphere/clouds_planar.glsl:274-321`、`cloud_shadow_cache.glsl`）；sundial 的解析云影（`Cloud.glsl:381-416`）弱于 Astra 的低分云影缓存。
7. **TAA YCoCg 钳制 / Catmull-Rom / gather 化**：批次一/二/三已列；Astra 已实现 gather（`program/taa_resolve.fsh:28-40`）与 YCoCg 方差裁剪（`docs/2026-10-02-batch2-implementation.md`/`taa_resolve.fsh`）。
8. **Bloom mip 打包/直采场景 mip、曝光方案、运动模糊、DoF、RCAS、色散、雨滴几何、程序门控、抖动 CPU 化、纹理 3D 值噪声**：均属批次一/二/三已列方向或 Astra 已有同类（mip 打包见 SUMMARY-batch3 §2.3「单 pass mip 打包 Bloom」与 A 组「Bloom 直采 colortex0 mip」；Astra 已删 noisetex，`lib/settings.glsl:341`，并已有 complementaryCloudNoise/steadfastWaterNoise/solasWaterNoise/blissNetherNoise 四处纹理噪声）。
9. **管线级开关（underwaterOverlay/vignette/sun/clouds=false）**：批次三 A 组已列（pixel-perfect/vanilletix），本包只是同型再例；Astra 目前仍未声明这些键（grep 0），但按去重纪律不列为本包新颖点（如需推进请走 batch3 遗留项）。
10. **DH/Voxy/Colorwheel/SuperResolution/Physics Mod 兼容层**：DH/Voxy 集成契约与 TAAU/渲染缩放分别为批次二、批次三已列；Colorwheel 光源剔除 compute（`clrwl_shadow_distort.csh`）与 Physics Mod 海面属兼容性特性，无 Astra 可吸收的一般性能点。

## 七、备注（供统帅）

- sundial-lite 为 GPLv3：若采纳 C-1，建议**按上游 Shadertoy CC0/MIT 原算法独立实现**（Astra 已有从公开许可上游重写的先例），避免 GPL 传染范围扩大；若直接改编包内 GPL 代码，需走 SC-14/THIRD-PARTY 决策。
- 本报告的行号以 2026-10-03 工作区快照为准；包内 `#include` 相对 shaders 根，行号未漂移。
