# Vanilla Plus Shader 3.3 研究报告（面向 Astra 的借鉴点）

- 参考包源码：`reference_shaderpacks/vanilla-plus-shader/`；下文 VPS 文件均相对其 `shaders/` 目录，Astra 文件均相对 `Astra/shaders/`。
- 报告日期：2026-10-02。

## ① 包概览

- **版本与作者**：v3.3，作者 RRe36（`lang/en_US.lang:1-2`：`option.INFO=Vanilla Plus by RRe36`、`value.INFO.0=v3.3`；每个源文件头部版权块亦为 `Copyright (C) 2025 RRe36`）。
- **许可证**：保留所有权利（`LICENSE:2` "All Rights Reserved unless otherwise explicitly stated."）。关键条款：第 1 节限制只经官方链接分发；第 3 节公开修改版须获作者明确许可且含足量原创内容、同许可证、注明出处；**第 4 节（`LICENSE:75-78`）明确：把本包源代码的一部分用作另一个原创项目的组成部分，需要作者明确许可**。
- **风格定位**：原版增强（vanilla-plus）路线——保留原版方块观感，强化水、软阴影、体积云、后处理；自称"Vanilla Plus"，画质档 Fast/Default/Fancy 由组合式 profile 定义（`shaders.properties:1-3`）。目标版本为 1.16.5 一代（`shaders.properties:92-93`，仅 world0/world-1/world1 三套程序，无 1.17+ 特性），纯 forward 渲染（gbuffers 内直接算直射光，`program/gbuffer/forward.fsh:215` 起 main），与 Astra 同为前向管线。
- **注意**：任务背景称该包为 Sixthsurge（Photon 作者）出品；包内证据（lang、LICENSE、版权头）一致指向 RRe36。本文按代码事实写作 RRe36；VPS 与 Photon 的代码血缘仅在个别注明出处处成立（见②）。
- **目标版本与程序集**：仅 1.16.5 一代（`shaders.properties:92-93`），三套世界程序（world0 主世界 / world-1 下界 / world1 末地）共享 `program/` 与 `lib/`，世界差异用 `DIM` 宏分流（如 `forward.fsh:308`）。
- **关键缓冲布局**：colortex3 = 256x256 天空图集（`shaders.properties:133`）；colortex9/10 = 1024x512 球面场景 capture（`:134-135`）；colortex8 = 原版 `clouds.png` 云密度源（`:138-139`）；噪声纹理 `img/noise2D.png`（`:137`）。
- **画质档差异**：Fast 关闭云/godrays/自定义水法线与水色/SSAO/反射；Default 在其上开云与 godrays；Fancy 再开水法线、水色、SSAO、反射（`shaders.properties:1-3`）。Astra 的 PERFORMANCE/BALANCED/ULTRA 是同一思路的平铺写法（`Astra/shaders/shaders.properties:424-427`）。

## ② 架构与特性清单

### 水体
- 波浪法线（可关，Fancy 开）：世界坐标 3 倍频旋转采样噪声求梯度，距离自适应步长与振幅衰减（`program/gbuffer/forward.fsh:200-211`，`lib/atmos/waterWaves.glsl:38-78`，倍频数 `waterWaves.glsl:38`；距离衰减 `waterWaves.glsl:62-64`）。噪声用 256 周期 texelFetch+三次插值（`waterWaves.glsl:20-36`）。
- 水面材质参数：ID 102（`shaders/block.properties:2` 映射 water）在 gbuffer 内设 roughness 0.01 / f0 0.02（`world0/composite1.fsh:411-412`）。
- 精确介质 Fresnel（介电公式而非 Schlick 近似）（`lib/frag/reflection.glsl:40-52`）。
- SSR：屏幕空间方向行进，16 步（`lib/frag/reflection.glsl:216-264`，步数 `:217`）；射线终点先投影出屏幕方向并用 `minOf(maxLength)` 裁剪到屏幕边界（`:229-231`）；首步用蓝噪声抖动（`:246`）；命中判定用线性深度的相对阈值（初始 0.25 `:240-243`，行进中 0.5 `:255-257`）；另有 8 步低配版 `screenspaceRT_LR`（`:266-303`）供粗糙反射用。
- 反射 fallback：SSR 未命中读球面投影天空 capture，带天空遮挡权重（`lib/frag/reflection.glsl:329-363`，`readSkyCapture :307-309`）。
- 折射与吸收：无屏幕空间折射位移；半透明在 gbuffer 写入 tint（`forward.fsh:280-284`，alpha 取 sqrt），composite 中按 `sqr(吸收)` 乘底色再混入半透明色（`world0/composite1.fsh:391`），并先在水面与水底深度之间做一段水雾（`:380-391`）。
- 水下雾：按可调三通道系数归一化后取倒数得消光系数，`exp(-dist*coeff)` 消光 + 单次散射色（`world0/composite1.fsh:97-123`，归一化 `:103-114`，散射 `:118`）；`isEyeInWater==1` 时全程应用（`:526-528`），水下禁用 godrays（`world0/composite2.fsh:77`）。
- 半透明辅助通道关闭混合：水面写进 colortex1/2 的数据不受 alpha 混合污染（`shaders.properties:123-130`，gbuffers_water/hand_water 与 entities 的 colortex1/2 均 `blend=off`），使下游可把"实体/水"当不透明数据读。

### 阴影与光照
- 硬件 PCF + 手工双线性彩色阴影：每迭代先 `textureGather` shadowtex0/1 各得 4 个比较结果，再 texelFetch 4 个阴影色 texel 手工双线性，逐角配对"遮挡×颜色"（`program/gbuffer/forward.fsh:131-152`，硬件过滤声明 `:82`，取色 `:120-124`）。
- R2 低差异序列生成旋转对称盘形采样：迭代数 `shadowFilterIterations`（默认 4，`settings.glsl:141`），半径 `shadowmapPixel.x*sqrt2*shadowFilterSize`（`forward.fsh:158`），每迭代蓝噪声抖动起点（`:163-164`，R2 定义 `:107-111`，注释注明序列出处 `:104-105`）。
- 彩色阴影：半透明投射物颜色乘进阴影（`forward.fsh:125-129`），树叶阴影可关（`settings.glsl:144`）。
- 阴影贴图径向扭曲，bias 0.85（`lib/light/warp.glsl:18-32`）。
- 屏幕空间接触阴影（注明移植自 Spectrum/Zombye）：16 步、步距 4 像素，线性化后插值深度以减少自遮挡误判（`lib/light/contactShadow.glsl:47-90`，出处声明 `:20-23`，插值线性深度 `:34-46`）。
- SSAO（注明经许可取自 BSL）：4 步旋转采样（`program/deferred/ssao.fsh:48`，`:57`）。
- 漏光防护：lightmap 天光低处压直射（`forward.fsh:304-306`）。
- 半透明面的自遮蔽：按 tint 不透明度平方压直射（`forward.fsh:296-302`）。

### 大气 / 雾 / 云
- 天空 capture 图集：colortex3 为 256x256（`shaders.properties:133`），上下两行分别为"晴空"与"含体积云的天空"，由 deferred 阶段一次性烘焙（`program/deferred/skyboxPrep.fsh:250-270`），投影函数 `lib/atmos/project.glsl:22-33`；雾色与反射 fallback 都从中取样（`composite1.fsh:360`）。
- 体积云：以原版 `clouds.png` 为密度源（`shaders.properties:138-139`），多层相位+能量守恒的多次散射估计 `EstimateEnergy`，自适应步数（`world0/composite1.fsh:134-233`，步数自适应 `:176-180`）；夜间熄灭由 `cloudLightFlip` 驱动（`shaders.properties:240`）。
- 距离雾：`1-exp` 平方衰减 + 视线水平压低（`composite1.fsh:83-95`）；全时段参数（日出/正午/日落/夜 × RGB×强度）全部可调（`settings.glsl:52-91`），另有 SEUS/Chocapic 等整套预设（`lang/en_US.lang:10-16`）。
- Godrays：以 `shadowLightPosition` 为源的屏幕空间径向步进（`world0/composite2.fsh:74-105`，循环 `:105`），默认 8 步（`settings.glsl:116`）。
- 风摆植被：宏观阵风+细波两层正弦（`lib/vertex/wind.glsl:34-47`）。

### 后处理
- Reinhard 色调映射（`program/grade/grading.fsh:196`，应用 `:457`）。
- 颜色分级：vibrance/saturation/gamma/brightness/contrast/三通道亮度，另有"视锥重叠模拟"矩阵做色度保持（`grading.fsh:48-60`）。
- 镜头特效：DoF（composite10，`shaders.properties:145` 条件启用）、动态模糊/legacy 光斑（composite11）、彩虹光晕光斑（`program/post/lens1.fsh:187-245`，雨天自动压暗 `:245`）、曝光自动+手动（`settings.glsl:185-191`）、泛光（`program/post/bloom.fsh`）。
- 细节锐化：3x3 unsharp 掩模（`program/grade/final.fsh:79-82`）；出图抖动（`final.fsh:45,156`）。

### 性能与时域
- TAA：Chocapic 式重投影（`program/post/temporal.fsh:47-58`），3x3 邻域钳制防鬼影（`:76-79`），按速度自适应混合权重（`:83-85`）；抖动序列直接写在 `shaders.properties:159-179`（8 帧偏移）。
- 场景颜色球面 capture：colortex9/10（各 1024x512，`shaders.properties:134-135`）存球面投影的场景色+场景位置，deferred 程序做时域重投影与距离有效性检验（`program/deferred/capture.fsh:93-154`，不清缓冲 `:24-25`），供粗糙反射与 SSR fallback 使用；默认关闭（`settings.glsl:164`）。
- 管线裁剪：`program.*.enabled` 按开关跳过整条 pass（`shaders.properties:141-150`）。
- 自定义 uniform：`worldAnimTime`（世界日+日内时间，`shaders.properties:156`）驱动云形变化。
- 材质编码：LabPBR 兼容，f0 通道 230-237 编码 8 种金属复折射率表（`lib/frag/reflection.glsl:10-19,21-37`）；反射辅助量（阴影色/反照率）打包 RGBE8（`forward.fsh:181-189`）。
- 噪声基建：蓝噪声 + 时间性梯度噪声两套 dither 库在各 composite 复用（`world0/composite1.fsh:76-77` 的 include），配合每 pass 单一抖动源，减少 pass 间噪声互相打架。
- 低分辨率缓冲读取用双三次插值（`world0/composite1.fsh:79` include `lib/util/bicubic.glsl`），天空图集与 capture 读回时减少块状感。
- 原版映射：水在 `shaders/block.properties:2` 固定映射（着色器内为 matID 102，`forward.fsh:268` 判定），发光方块另列 ID 段（`block.properties:24-25`）。

## ③ Astra 可借鉴点

1. **R2 盘形抖动 PCF（软阴影采样模式）**
   - 技术描述：在固定 lobes 之上叠加低差异盘形采样：每迭代角度来自 R2 序列、半径 sqrt(rand) 均匀盘面，蓝噪声抖动起始，迭代数与半径可设为画质选项；配合 gather 保持每角"深度比较×阴影色"配对。
   - 出处：`program/gbuffer/forward.fsh:107-111,154-179`；迭代/半径选项 `settings.glsl:140-141`。
   - 对应 Astra：`global/lighting/diffuse.glsl:266-287`（`surface_shadow_light` 的固定轴向 2/4 lobes 循环）+ `global/lighting/shadowmap.glsl:102-131`（`shadow_lobe_light`）；选项入口 `lib/settings.glsl:69,81`。
   - 迁移难点：低-中。Astra 均衡档（SHADOW_FILTER_QUALITY=1）现为静态 8 配对角点，改采样位置只需换 offset 生成；但引入抖动噪声后必须依赖 Astra TAA 消噪，且彩色阴影的逐角 caster 重组逻辑要保持"每 lobe 内部配对"，`STATIC_SHADOW_FALLBACK` 语义不变。
2. **SSR 的屏幕边界预裁剪 + 首步抖动 + 相对深度命中阈值**
   - 技术描述：射线先投影为屏幕向量并按各轴到边界距离取最小步数，避免出屏浪费；首步用噪声抖动去 banding；命中用"线性深度相对差 < 阈值"而非固定世界距离，近处严、远处松。
   - 出处：`lib/frag/reflection.glsl:229-231`（边界裁剪）、`:246`（首步抖动）、`:240-243,255-257`（相对阈值 0.25/0.5）。
   - 对应 Astra：`global/water/raytrace.glsl:46-112`（`water_raytrace`：世界空间步长 1.6 倍递增 + 区间二分细化 + 置信度）。
   - 迁移难点：低。三者均为局部改动：边界裁剪可并入 `water_ssr_gather_uv_valid` 逻辑；抖动可复用 Astra 的 dither 库；相对阈值可与现有 `residual` 置信度合并。注意 Astra 近期刚修过"反射空气段起点"问题（`raytrace.glsl:60-61` 的法线侧判定），改动不得破坏该判定。
3. **场景颜色球面 capture（SSR miss 的场景级 fallback）**
   - 技术描述：把已着色场景按球面经纬投影写入一张低分辨率图集（含场景位置与"距离有效性"），逐帧时域重投影累积；SSR 未命中时先查 capture 中是否有更近的场景点，没有再退到天空，使远处地形也能进入反射。
   - 出处：`program/deferred/capture.fsh:93-154`；读取端 `lib/frag/reflection.glsl:329-363`；分辨率 `shaders.properties:134-135`。
   - 对应 Astra：`lib/sky_reflection_cache.glsl`（现有 256x128 天空/云缓存，仅天空色）+ `program/sky_reflection_cache.fsh` + `program/scene.glsl:62-69`（`astra_reflection_sky`）。
   - 迁移难点：中-高。需新增一张 MRT 与一个 deferred pass、处理 Astra 的云时域历史与 capture 时域累积的相互作用、以及在水下/下界等介质切换时的失效策略；可先做成可选开关。
4. **天空图集加"含云行"**
   - 技术描述：同一张天空缓存里烘焙两行——纯晴空与叠加云后的天空；雾色、水反射 fallback 可按需取用，避免每像素重复算云。
   - 出处：`program/deferred/skyboxPrep.fsh:250-270`（两行写入）；读取 `composite1.fsh:360`。
   - 对应 Astra：`lib/sky_reflection_cache.glsl`（把单行 256x128 扩为两行或加倍高度）+ `program/sky_reflection_cache.fsh`。
   - 迁移难点：低。Astra 缓存已有经纬映射与 gutter 处理，仅需加一行写入与采样选择；注意与 `ASTRA_CLOUD_NO_TEMPORAL`、半分辨率云历史的读取时机。
5. **精确介质 Fresnel / 金属复折射率（为 LabPBR 铺路）**
   - 技术描述：介电用完整 Rs/Rp 公式而非 Schlick；金属按 LabPBR f0≥230 从 8 组 (n,k) 表取复折射率算彩色 Fresnel；粗糙反射用 GGX VNDF 采样（Hemisphere 投影法）+ 旋转矩阵对齐法线。
   - 出处：`lib/frag/reflection.glsl:40-52`（介电）、`:54-74`（导体）、`:10-19,21-37`（编码表）、`:178-215`（VNDF，注明源自 Spectrum `:173-176`）。
   - 对应 Astra：`global/water/optics.glsl:6-16`（已有正确的介电公式，含全内反射）；Astra 尚无 LabPBR 材质管线（`lit.fsh` 仅水/冰/岩石/黑曜石特判）。
   - 迁移难点：高。VNDF 与金属表本身可独立实现（算法出自公开论文，VPS 也注明引自 Spectrum），但要先建 LabPBR specular 通道解码与材质缓冲，属新子系统而非补丁。
6. **`program.*.enabled` 管线裁剪与组合式 profile**
   - 技术描述：关闭某开关时整条 composite pass 不再运行；画质档用 `profile.X=profile.Y +增量` 串联定义。
   - 出处：`shaders.properties:141-150`（enabled 条件）、`:1-3`（组合 profile）。
   - 对应 Astra：`shaders.properties:424-427`（Astra 已用平铺式 profile，BALANCED 为均衡档）；Astra 是否已有条件启用 pass 未确认。
   - 迁移难点：低。纯 properties 改动；收益是低端档减少空 pass 开销。
7. **水雾消光系数归一化**
   - 技术描述：把三通道雾色系数归一化后取倒数再整体归一，保证任意颜色下消光单调且不超量，散射色由天光驱动。
   - 出处：`world0/composite1.fsh:103-118`。
   - 对应 Astra：`global/water/absorption.glsl:58-72`（Beer-Lambert，系数按水深分段插值）与 `lib/solas_water.glsl:83-100`。
   - 迁移难点：低，但 Astra 现行方案物理性更强（吸收/散射分离、随深度变色），仅当需要"用户可调雾色"暴露项时才值得参考其归一化技巧。

### 专项问题回应（任务定位 a–d）

- **a) 水 SSR 与折射的实现细节**：SSR 见②水体与③2——VPS 用"屏幕空间向量 + 边界最小步数裁剪 + 相对线性深度阈值"的 16 步行进，无二分细化；折射上 VPS 没有屏幕空间位移（`composite1.fsh:391` 只是半透明层合成），Astra 的 `global/water/refraction.glsl:10-21` 已是更强的实现，无需回搬。VPS 值得摘的是三个行进细节（③2）。
- **b) 软阴影/PCF 采样模式**：VPS = R2 抖动盘 × gather 配对重组（③1）。Astra 均衡档的 8 配对角点可直接复用其 `shadow_lobe_light`（`shadowmap.glsl:102-131`），把 `diffuse.glsl:277-286` 的静态 offset 换成 R2 盘即可，硬件 gather 路径不用动——这是最平移的一条。
- **c) 水下视觉与雾**：VPS 水下 = 单一消光雾 + godrays 关闭（`composite2.fsh:77`）+ 光束无专门实现；Astra 已有吸收/散射分离、光束与焦散，全面更强。唯一可参考的是③7 的"用户可调雾色→消光系数归一化"技巧，以及 VPS 把水面-水底之间的那一段距离单独做一次水雾（`composite1.fsh:380-385`）——Astra 若在水面上看水下尚未按这段距离积分，可核对（不确定，未逐一验证 Astra 该路径）。
- **d) 与 Photon 共享工程技巧中 VPS 更精简、更值得摘取的**：① 天空图集（VPS 两行 256x256，`skyboxPrep.fsh:250-270`，比 Photon 的方案小且够用）；② `program.*.enabled` pass 裁剪（`shaders.properties:141-150`）；③ R2 采样比 Photon 的多迭代 PCF 更省（4 迭代起步，`settings.glsl:141`）；④ 把 TAA 抖动序列放进 properties 而非着色器（`shaders.properties:159-179`），省一行着色器逻辑。这四条都是"低工作量、可独立摘取"的工程件。

## ④ Astra 已有对应实现（对照）

| VPS 特性 | VPS 出处 | Astra 对照 | 对比结论 |
|---|---|---|---|
| 水 SSR | `lib/frag/reflection.glsl:216-303` | `global/water/raytrace.glsl:46-112` | Astra 更强：区间二分细化、法线侧判定防水下地面截断、置信度输出；VPS 优点仅在屏幕边界裁剪与首步抖动（见③2）。VPS 16 步固定更省 |
| 折射 | 无屏幕折射位移，仅半透明层混合 `world0/composite1.fsh:391` | `global/water/refraction.glsl:10-21`（折射 UV 位移 + 出水深度检查） | Astra 更强；VPS 水下看水面时基本无折射畸变 |
| 水吸收/水下雾 | `world0/composite1.fsh:97-123,526-528` | `global/water/absorption.glsl`、`lib/solas_water.glsl:83-119` | Astra 更强：物理吸收（随深度变色）+ Solas 散射/色调映射链；VPS 是可调系数的简化消光 |
| 波浪法线 | `lib/atmos/waterWaves.glsl:38-78` | `global/water/surface.glsl`（Steadfast 波场 + Nyquist 滤波 + 四步视差） | Astra 更强；VPS 的距离衰减思路与 Astra 足迹控制同义 |
| 水面 Fresnel | `lib/frag/reflection.glsl:40-52` | `global/water/optics.glsl:6-16` | 对等（Astra 同为精确介电公式且处理全内反射） |
| 彩色阴影 | `program/gbuffer/forward.fsh:120-152`（gather 配对重组） | `global/lighting/shadowmap.glsl:102-131` | 对等且 Astra 更细：逐角保留独立 caster 身份（水/玻璃混合边缘），VPS 双线性混合颜色 |
| PCF 采样模式 | `forward.fsh:107-111,154-179`：R2 抖动盘 + gather，默认 4 迭代 | `global/lighting/diffuse.glsl:266-287`：静态 8 配对角点（均衡档） | 各有优劣：VPS 更软、各向同性、噪声依赖 TAA；Astra 无噪声、成本固定、但方向性条纹感更明显（尤其 SHADOW_SOFTNESS 大时）。结论："不确定"项——Astra TAA 对抖动噪声的实际容忍度未实测 |
| 接触阴影 | `lib/light/contactShadow.glsl:47-90` | 未发现对应实现 | VPS 独有（同为 Spectrum 血缘，可按③5 方式自行实现） |
| SSAO | `program/deferred/ssao.fsh:48,57` | `lib/ao_material.glsl`+`lib/ao_resolve.glsl`、开关 `SCREENSPACE_AO` | Astra 有实现；内部算法未比对，不定优劣 |
| 体积云 | `world0/composite1.fsh:134-233`（世界射线步进+多次散射估计） | `global/atmosphere/clouds_planar.glsl`+`cloud_temporal.glsl`（半分辨率平面云+独立时域历史） | 路线不同：VPS 视觉上限更高、成本高；Astra 若将来补体积云档可参考其 `EstimateEnergy` 能量守恒简化 |
| 天空缓存 | `program/deferred/skyboxPrep.fsh:250-270`（晴空/含云两行） | `lib/sky_reflection_cache.glsl`（单行经纬缓存 + gutter） | VPS 多"含云行"，见③4 |
| Godrays | `world0/composite2.fsh:74-105` | `global/post/godrays.glsl` | Astra 有实现；实现细节未比对，不定优劣 |
| TAA | `program/post/temporal.fsh:47-88` | `lib/taa_state.glsl`、`lib/taa_jitter.glsl` | Astra 有实现；细节未比对，不定优劣 |
| 色调映射/分级 | `program/grade/grading.fsh:196,457` | `global/post/grading.glsl`、`lib/color_controls.glsl` | Astra 有实现；曲线差异未比对 |
| 雨湿地面 | 无（VPS 仅雨天压光斑/泛光，`program/grade/grading.fsh:412-423`） | `global/atmosphere/weather.glsl:3-27`（水洼+湿地面两套信号） | Astra 独有，无对照 |
| SH9 方向性天光 | 无对应（VPS 用 lightmap 幂次近似天光，`forward.fsh:314-316`） | `lib/sky_sh9.glsl` | Astra 独有 |
| 下界/末地独立光照 | 仅 world-1/world1 通用 forward（无五类群系雾、无体素彩光） | `global/dimension/`、`program/nether_light.csh` 等 | Astra 独有且远超 VPS |
| 风摆植被 | `lib/vertex/wind.glsl:34-47`（双层正弦阵风） | `global/lighting/wind.glsl`（存在性确认，实现未比对） | 不定优劣 |
| 泛光/曝光 | `program/post/bloom.fsh`、`program/post/exposureDownscale.fsh` | `global/post/bloom.glsl`、`global/post/exposure.glsl`（存在性确认，实现未比对） | 不定优劣 |

## ⑤ 借鉴可行性（许可证层面）

- VPS 许可证为"保留所有权利"（`LICENSE:2`），且第 4 节（`LICENSE:75-78`）明确要求：将本项目源代码的一部分用于另一个原创项目需作者明确许可，并需署名、禁止变现。**因此禁止把 VPS 源码（含直接翻译/重命名的衍生物）复制进 Astra**。
- 可行路径：仅借鉴算法思想与参数化思路（R2 序列、SSR 边界裁剪、两行天空图集、capture 球面投影），在 Astra 中独立实现；这些底层算法（R2 准随机序列、GGX VNDF、介电 Fresnel）另有公开论文/规范出处，VPS 自己也注明了来源（`forward.fsh:104-105`、`reflection.glsl:173-176`），按论文原始出处实现是安全路线。
- 注意：VPS 内的 BSL SSAO、Spectrum 接触阴影等第三方代码同样受其各自许可约束，不能借"VPS 有"就认为 Astra 可搬。这与 Astra 现行做法一致（Steadfast GPLv3 部分在文件头声明来源与许可证，见 `global/lighting/shadowmap.glsl:4-12`）。
- 结论：**思想层面借鉴=可行；代码层面引入=需向 RRe36 取得明确许可，默认不做**。
- 补充：VPS 每个源文件头部都带 DMCA/信息社会指令追责声明（如 `world0/composite1.fsh:3-19`）；Astra 现行的文件头来源声明做法（`global/lighting/shadowmap.glsl:4-12`，注明 Steadfast 与 GPLv3）可继续作为引用外部成果的署名模板，但 VPS 属"需许可"而非"可署名引用"类别。

## ⑥ Top5 优先建议（按 提升/工作量 排序）

1. **PCF 采样改 R2 抖动盘 + gather（③1）**——提升大（软阴影观感直接向 VPS/Photon 靠拢）、工作量低-中，且只动 `diffuse.glsl`/`shadowmap.glsl`/settings。
2. **水 SSR 加屏幕边界裁剪 + 首步抖动 + 相对深度阈值（③2）**——提升中-大（去 banding、减少无效步）、工作量低，局部改 `raytrace.glsl`。
3. **天空缓存加"含云行"（③4）**——提升中（雾色/反射带云观感）、工作量低，动 `sky_reflection_cache.glsl` 与对应 program。
4. **场景颜色球面 capture（③3）**——提升大（水面反射从"天空+SSR"升级为"场景级"）、工作量中-高，建议做成 Fancy 档可选开关。
5. **LabPBR 金属/粗糙反射子系统（③5）**——提升最大（覆盖所有资源包材质）、工作量高，属长线项，可先落 Fresnel/VNDF 数学底座再逐步接材质管线。

实施顺序提示：1→2→3 相互独立且都不触碰 Astra 的时域系统，可分别小步交付；4 依赖 3 的图集骨架，宜在同一次改 `sky_reflection_cache` 时一起设计；5 建议在 1-4 稳定后单独立项。所有条目按⑤的结论独立实现，不复制 VPS 代码。

## 备注

- ③4/⑥3 中"含云行"的采样时机需与 Astra 半分辨率云的时域历史对齐，实施前建议确认 `program/sky_reflection_cache.fsh` 的执行序。
