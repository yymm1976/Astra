# UShader v2.2 调研报告（面向 Astra）

> 引用约定：`P:` = `reference_shaderpacks/ushader/` 下的相对路径；`A:` = `Astra/shaders/` 下的相对路径。
> 所有行号在成稿后逐条重新打开源文件核对（见附录），无法确认的行号一律未写。

---

## ① 包概览

- **名称/版本**：UShader，v2.2。出处 `P:shaders/lang/en_US.lang:1-2`（`option.INFO=UShader by RRe36` / `value.INFO.0=v2.2`）。与任务书所给版本一致。
- **作者**：RRe36。许可证文件 `P:LICENSE:1`（`Copyright (C) 2025 RRe36`），`P:LICENSE:2`（`All Rights Reserved unless otherwise explicitly stated.`）。包内各 lib 源文件另带 per-file 头（(C) 2022 RRe36，指向 `https://rre36.com/copyright-license`，并提及 DMCA 惩罚条款，见 `P:shaders/lib/atmos/air/atmosphere.glsl:1-18`）。
- **规模**：348 个文件、约 2.9 MB；`shaders.properties` 19 KB / `settings.glsl` 12 KB。
- **管线形态**：**延迟渲染**。gbuffers 只写 albedo/G-buffer（`P:shaders/program/gbuffer/solid.fsh:20-24`，blend 全关 `P:shaders/shaders.properties:128-144`），光照在 deferred 链完成：deferred4 = 主光照与 RTAO（`P:shaders/world0/deferred4.fsh` 引 `P:shaders/program/deferred/PTLight.fsh`），deferred6-10 = SVGF 多尺度滤波（`P:shaders/world0/deferred6.fsh:22` 起，SVGF_SIZE 32→16→8→4→2），deferred12 = albedo × (direct+indirect+emission) 合成（`P:shaders/world0/deferred12.fsh:79-143`）。三个维度（world0/world-1/world1）共用同一套 program 源，用 `#define DIM` 分叉（`P:shaders/world-1/deferred4.fsh`、`P:shaders/world1/deferred4.fsh`）。
- **风格定位**：物理化、写实、偏"地形摄影"观感。核心卖点是行星尺度解析大气 + 体积云/雾/水同源散射体系 + 屏幕空间路径式间接光（RTAO）+ 相机化后处理（f-stop/DoF/镜头耀斑/CAS）。画质优先于性能（Performance 档强制 0.5 分辨率渲染，`P:shaders/shaders.properties:5`）。

---

## ② 架构与特性清单

### 大气与云
- 行星尺度解析大气：半径 6371 km 球体 + 110 km 大气层，Rayleigh/Mie/臭氧三系数（`P:shaders/lib/atmos/air/const.glsl:36-50`）；双尺度高度指数密度 + 臭氧峰层（`P:shaders/lib/atmos/air/density.glsl:22-33`）。
- 每个视线路径样本**向光源方向积分 airmass**（每步做 8 次步进的 shadow-ray，`P:shaders/lib/atmos/air/density.glsl:39-65`），主循环 `P:shaders/lib/atmos/air/atmosphere.glsl:135-173`。
- 近似多次散射（multiScattering 累加 + 亮度加权 illuminance，`P:shaders/lib/atmos/air/atmosphere.glsl:164,193-198`）；地面反弹光 PLANET_BOUNCELIGHT（`:71,166-168,200`）。
- 从高空渲染行星表面：OrenNayar+GGX 着地表面的"从太空看地球"（`:38-67,110-130`）。
- 月相遮挡月光（`RMoonPhaseOcclusion`，`P:shaders/shaders.properties:258-260`，使用于 `P:shaders/lib/atmos/air/atmosphere.glsl:189`）。
- 天空以**等距柱状天空图**存在 256×384 小缓冲 colortex4 三段中：段0=晴空、段1=逐方向透射率、段2=含云天空（RTAO/反射采样用）（`P:shaders/lib/atmos/project.glsl:21-45`，`P:shaders/world0/prepare.fsh:53-72`，缓冲尺寸 `P:shaders/shaders.properties:150`）。
- 体积积云：逐样本早退的多八度 3D 值噪声 + 3D curl 噪形变 + 局部覆盖图（`P:shaders/lib/atmos/CloudsCommon.glsl:111-166`，curl 纹理绑定 `P:shaders/shaders.properties:147-148`）；距离 UV 压缩防地平线频闪（`:117`）。
- 云相位：多瓣混合 + **不对称度随局部光深增长**（银边效果，`P:shaders/lib/atmos/CloudsCommon.glsl:41-68`；调用点 `P:shaders/world0/deferred.fsh:213,218-219`）；能量守恒反弹估计 `estimateEnergy`（`:28-30`，调用 `P:shaders/world0/deferred.fsh:209-216`）。
- 光行进步长指数增长（basestep 5.0 × 2^n，`P:shaders/lib/atmos/CloudsCommon.glsl:168-191`）；天空 OD 步长随高度自适应（`:192-211`）；两者均有蓝噪声抖动变体（`:213-262`）。
- 卷云平面层：多八度域扭曲 `P:shaders/lib/atmos/CloudsCommon.glsl:277-339`，与体积云同 March 串联 `P:shaders/world0/deferred.fsh:273-371`。
- 云影图：colortex4（256×384）下 3/4 区域的 alpha 通道烧入云透射率图（积云 40 步 + 卷云行进，雨天回退；分辨率常量名义 512，实受缓冲宽 256 限制），供地形直光/雾/水三处读取（`P:shaders/world0/prepare1.fsh:284-356,383-391`，读取 `P:shaders/world0/composite.fsh:95-103`、`P:shaders/world0/deferred3.fsh:272-280,420-422`，常量 `P:shaders/lib/internal.glsl:43-44`）。
- 彩虹选项 rainbowsEnabled（`P:shaders/settings.glsl:2`）。
- 大气浓度随时间/湿度动态变化（CPU custom uniform：Rayleigh/Mie/臭氧按晨昏时段加权 + wetness×16，`P:shaders/shaders.properties:267-286`）；云量/雾浓度同样动态（`:292-315`）。
- 动画时钟 worldAnimTime = worldDay%48+worldTime（`P:shaders/shaders.properties:156`），可冻结并偏移（`P:shaders/settings.glsl:165-166`）。

### 水体
- 波形：4 八度域扭曲 FBM，方向逐倍旋转，gbuffer 法线与 shadow 焦散共用同一高度场（`P:shaders/lib/atmos/waterWaves.glsl:40-88`）。
- shadowcomp 中计算**水面焦散**：对折射光线做 Jacobian 投影近似 `projectedCaustic`（`P:shaders/program/shadow/comp0.fsh:73-86`），并沿阴影射线在 solid/water 深度间做 Beer 吸收，写入 shadowcolor0 供地面着色（`:121-137`）。
- 体积水：水面下水 slab 的 3-12 步自适应行进 + 阴影 + 云影，`volumetricWater`（`P:shaders/world0/composite.fsh:333-428`）；非体积回退 `waterFog`（`P:shaders/lib/atmos/fog.glsl:21-32`）。
- 屏幕空间折射：`refract2`（含平面法线修正，注明来自 Spectrum by Zombye）+ slab 厚度行进 + 边缘回退 + 深度复检（`P:shaders/world0/composite.fsh:437-507`）。
- 半透明按反照率着色混合 `blendTranslucencies`（`P:shaders/world0/composite.fsh:527-534`）。

### 阴影与光照
- 影色三重采样：shadowtex0/1 + shadowcolor0，`textureGather` 双图 bilinear + **边缘锐化**（平均可见度 re-threshold）+ min-color 抑制彩边（`P:shaders/world0/deferred3.fsh:100-160`）。
- R2 旋转盘滤波迭代数可调 6-30（`:139-148`，`P:shaders/settings.glsl:82`）；法线相关 bias 按分辨率对数缩放（`:162-165,410-413`）。
- SSS：5 组对称 shadowtex1 径向采样 + 反照率归一散射 + HG 相位（`:199-270`）。
- 接触阴影：屏幕空间 stride 行进 + 深度"ascribe"厚度 + 线性化后插值深度（`P:shaders/lib/light/contactShadow.glsl:20-90`，启用 `P:shaders/settings.glsl:81`）。
- DSSAO：深度域 AO，反 bleed 项，"based on BSL Shaders by Capt Tatsu with permission"（`P:shaders/world0/deferred3.fsh:301-351`）。
- RTAO：每像素 1-6 根余弦射线（R2 拟随机 + hash 抖动），命中采样 IndirectSources 缓冲（=直光×albedo，`P:shaders/world0/deferred3.fsh:433-435`），miss 采样天空图 → **一跳 GI**（`P:shaders/program/deferred/PTLight.fsh:196-243`，天空采样 `:230`）。
- 时域累积：4-tap 双线性深度拒绝 + 256 帧历史（`P:shaders/program/deferred/PTLight.fsh:322-378`）。
- SVGF à-trous：方差由 3×3 亮度矩 + 历史帧数调制，参数随收敛自适应（sigmaBias/maxDelta/normalExp 均 frames 驱动，`P:shaders/program/deferred/filter.fsh:129-148`）；法线+深度+亮度联合边停权 `:167-176`；方差播种 `P:shaders/world0/deferred5.fsh:61-63`。
- 方向性 lightmap：用 skylight 的屏幕导数估计光方向并压暗背光面（`P:shaders/program/gbuffer/solid.fsh:349-368`，默认关 `P:shaders/settings.glsl:55`）。
- 方块光颜色按 lightmap 指数梯度（近处偏暖、远处收敛本色，`P:shaders/world0/deferred3.fsh:354-359`）。

### 后处理
- TAAU：以 0.5/0.75 分辨率渲染整个场景，temporal pass 完成 Lanczos-tonemapped 采样 + Catmull-Rom 历史 + YCoCg AABB 裁剪（注明 from SixthSurge）+ 离中心拒绝 + luma 拒绝（`P:shaders/program/post/temporal.fsh:147-197,238-326`，`ResolutionScale` 定义 `P:shaders/lib/internal.glsl:50`）。
- FXAA 后备 + TAAU_FXAA_PostPass（`P:shaders/settings.glsl:160-162`）。
- 泛光：chocapic13 式多级降采样链（`P:shaders/program/post/bloom_0.fsh:25-107`）；pass1 顺带产出 4×4 亮度格供复杂曝光（`:44-60,77`）。
- 复杂曝光：亮度格中心加权均值 + 亮/暗百分位阈值（`P:shaders/program/grade/exposure.vsh:36-100`）。
- 泊松盘 Bokeh DoF（30/45/60 样本三档）+ f-stop/传感器宽物理相机模型 + 色散（`P:shaders/program/post/lens_1.fsh:54-56,84-148`）。
- 三段镜头耀斑链：阈值提取→ghosts→halo（`P:shaders/program/post/lens_0.fsh:41` 起，参数 `P:shaders/program/post/lens_1.fsh:163-168`）。
- Purkinje 夜视偏蓝（`P:shaders/program/grade/grading.fsh:74-94`）；输出色域/ EOTF 变换（BT709/P3/Adobe，`:132-198`）。
- CAS 锐化 + 8bit 拜耳抖动输出（`P:shaders/program/grade/final.fsh:55-85,36-51`）；构图辅助线工具 `:98-129`。
- 运动模糊、暗角（`P:shaders/settings.glsl:154-156,69`）。

### 维度特化
- 下界：`NOSHADOWMAP`（`P:shaders/lib/internal.glsl:22-24`）；RTAO 照常运行但 miss 采样 AmbientColor，环境色由 **vanilla fogColor 混合 netherSkylightColor** 得到（生物群系自适应，`P:shaders/world-1/deferred4.vsh:58-59`、`P:shaders/lib/atmos/colorsNether.glsl:26-30`）。
- 下界 composite 与主世界共用折射/半透明逻辑（`P:shaders/world-1/composite.fsh:129-208`）；simpleFog 走 DIM 分支（`P:shaders/lib/atmos/fog.glsl:2-18`）。
- 末地：中心岛屿**漩涡体积烟雾**（半径依赖旋转 + 高度重映射 + 多八度扭曲噪声，`P:shaders/world1/composite.fsh:123-182`）+ 岛心发光 `endSmokeGlow`（HSV 随机色相，`:168-177`）；雾 = haze+smoke 双介质行进（`:190-229`）。
- 末地 RTAO 同样以 DIM=1 复用 PTLight（`P:shaders/world1/deferred4.fsh`）。

### 性能与与时域
- 三档 profile：Performance 强制 0.5 分辨率 + 关 RTAO/体积雾/水（`P:shaders/shaders.properties:5-7`）。
- 云的 9 帧 checkerboard 时域超分：棋盘采样表 + 像素年龄 + Catmull-Rom 历史（`P:shaders/lib/frag/checkerboard.glsl:20-50`；渲染侧 `P:shaders/world0/deferred.fsh:376-424`；累积侧 `P:shaders/world0/deferred1.fsh:192-260`）。
- 雾散射/透射写入独立缓冲、后续 pass 应用，可选空间平滑（`P:shaders/world0/composite.fsh:539-563`，平滑采样 `P:shaders/world0/composite3.fsh:229,439-447`）。
- 体积雾**平行阴影空间行进**：shadow clip 坐标与 world 步进同步插值，每步免矩阵乘（`P:shaders/world0/composite.fsh:214-222,298-314`）。
- RGBE 打包 HDR 到 8bit 对（直光/影色/天空缓冲复用，`P:shaders/world0/deferred3.fsh:282-290`、`P:shaders/lib/util/encoders.glsl`）。
- `/time set` 跳变检测：smoothWorldTime 与 sunDirZ 差值超阈值置 WorldTimeChange，强制历史失效（`P:shaders/shaders.properties:247-248`，消费 `P:shaders/world0/deferred1.fsh:222`）。
- 3D 纹理 curl 噪声资产（`P:shaders/shaders.properties:147-148`）。

### 材质与表面
- labPBR 解码 + Hammon 漫反射（`P:shaders/lib/brdf/labPBR.glsl`、`P:shaders/lib/brdf/hammon.glsl`，调用 `P:shaders/world0/deferred3.fsh:382,391`）。
- POM：纹理序贯线性搜索 + 距离淡出（24-48 块）+ 切线空间自阴影 + 图集坐标重映射（`P:shaders/program/gbuffer/solid.fsh:136-212`）。
- 湿润系统：噪声水洼掩码 + **生物群系干燥度 uniform**（`RW_BIOME_Dryness`，`P:shaders/shaders.properties:250-255`）+ 雨涟漪法线 + 粗糙度/光滑度联动（`P:shaders/program/gbuffer/solid.fsh:238-274`）。
- 风动画：宏观阵风正弦 + 3D 噪声微动，旋转坐标系（`P:shaders/lib/vertex/wind.glsl:34-67`）。
- 粗糙反射：GGX facet 重要性采样 + 双 SSR 变体（粗糙面用低质 `screenspaceRT_LR`，`P:shaders/world0/composite3.fsh:95-115,354-394`）；skyOcclusion 由 lightmap.y 阈值驱动（`:328`）。

---

## ③ Astra 可借鉴点

判定基准：Astra 是 Iris 专用、**前向**地形光照、三选一 AA（关/FXAA/TAA）、SH9 方向性天光、半分辨率平面云带独立时域、水面 SSR+折射+解析焦散+水下光束、下界九段 compute 体素彩光、末地 Kerr 黑洞天空。

1. **云 9 帧 checkerboard 时域超分**
   - 要点：把云渲染降到 1/9 像素/帧（3×3 棋盘轮转采样），用像素年龄（存 8bit 打包）驱动累积权重，子像素偏移修正采样网格，丢弃项=出屏/地形遮挡/时间跳变。
   - 出处：`P:shaders/lib/frag/checkerboard.glsl:20-37`（轮转表）、`P:shaders/world0/deferred.fsh:393-421`（1/9 采样渲染）、`P:shaders/world0/deferred1.fsh:198-260`（年龄加权累积，`:231-243` 权重公式）。
   - Astra 对应：`A:global/atmosphere/clouds_screen.glsl:17-24`（半分辨率 colortex24 已就位）、`A:global/atmosphere/cloud_temporal.glsl:59-121`（已有独立时域 resolve/reproject）。
   - 难点/工作量：中。Astra 时域管线已具备 reproject+历史校验，只需把采样网格从半分辨率全像素改为 3×3 轮转 + 年龄通道；主要风险是 Astra 云是平面层（非体积），1/9 采样对细碎云边缘的增益需实测。

2. **时间跳变历史失效（WorldTimeChange）**
   - 要点：CPU 端用 `smooth(sunDirZ, frameTime*8, frameTime*8)` 与 sunDirZ 比对，偏差>0.9 判定 /time set 或昼夜跳变，置 uniform 强制所有时域历史重建。
   - 出处：`P:shaders/shaders.properties:247-248`、消费点 `P:shaders/world0/deferred1.fsh:222`。
   - Astra 对应：`A:lib/effect_history.glsl:22-37` 的 `astra_effect_history_valid()` 目前只校验分辨率/水位/盲视/位移>8/投影矩阵，**没有时间跳变项**；`A:program/taa_resolve.fsh:93-94` 的历史有效性同样不感知。
   - 难点/工作量：低。在 effect_history_state 一处加 uniform 与一项校验即可，收益覆盖云/反射/雾全部历史缓冲。

3. **阴影"锐化 gather"滤波与彩色影边抑制**
   - 要点：textureGather 同时取 shadowtex0/1 四邻 + shadowcolor0 四邻做 bilinear；对平均可见度做二次 threshold（锐化软边），再用 min(rgb) 与均值的距离把半影边缘的彩色影色替换为最暗样本，防染色玻璃边缘漏彩。
   - 出处：`P:shaders/world0/deferred3.fsh:100-121`（gather 组装）、`:139-159`（R2 盘 + sharpenBorders + colorMin 混合）。
   - Astra 对应：`A:global/lighting/shadowmap.glsl:137`（硬件比较滤波）、`:190`（Steadfast normal offset）——Astra 无彩边抑制路径。
   - 难点/工作量：低-中。Astra 若引入 colored shadow 的锐化边界处理，只需在 shadow_mapping 采样处加 min-color 后处理；gather 双图结构依赖 shadowtex0/1 分离，Astra 已具备。

4. **shadowcomp 水面焦散 + 穿水吸收（水底光斑）**
   - 要点：在 shadow pass 后的 shadowcomp 里，对水 matID 用折射光 Jacobian 求 `sqrt(det(dP_refr)/det(dP))` 焦散增益，再沿阴影射线在 solid 与水面深度间做 Beer-Lambert，把结果写 shadowcolor0——地面直光采样影色时自然带出焦散与水体染色。
   - 出处：`P:shaders/program/shadow/comp0.fsh:73-86`（焦散投影）、`:121-137`（吸收合成，`#ifdef shadowcompCaustics` 开关 `P:shaders/lib/internal.glsl:46`）。
   - Astra 对应：`A:global/water/caustics.glsl:38-52`（Solas 式高度场散度焦散，用于表面与 VL）；水底地面没有几何折射焦散。
   - 难点/工作量：中。Astra 前向管线中 shadow.fsh 后需新增一个 shadowcomp pass；波形法线可直接复用 `A:global/water/surface.glsl` 的高度场。注意与现有 `solas_water_shadow` 的取值域衔接。

5. **屏幕空间接触阴影**
   - 要点：沿光方向在屏幕空间做 stride 行进，用 AscribeDepth 给深度厚度容差、线性化后再插值的深度（先线性后插值减少自阴影伪影），命中即完全遮蔽直光——补足 shadowmap 分辨率不足的小尺度接触。
   - 出处：`P:shaders/lib/light/contactShadow.glsl:25-46`（ascribe/线性化插值）、`:47-90`（主循环），调用 `P:shaders/world0/deferred3.fsh:392-394`。
   - Astra 对应：`A:global/lighting/shadowmap.glsl:84,190`（现有 PCF/offset 不含屏幕空间层）。
   - 难点/工作量：中。Iris 前向下可在 diffuse 直光处追加；stride+dither 的噪声需依赖 Astra 现有 TAA/蓝噪声抖动序列（`A:lib/taa_jitter.glsl:8-33`）。

6. **体积雾平行阴影空间行进**
   - 要点：起止点各自变换到 shadow clip 后，shadow 坐标与 world 坐标同插值共步进，每步省两次矩阵乘；warp 后仍逐样本采样 shadowtex0/1 + 影色。
   - 出处：`P:shaders/world0/composite.fsh:214-222`（shadow 步进向量）、`:298-314`（每步采样+云影叠加）。
   - Astra 对应：`A:global/atmosphere/volume_fog.glsl:91-98`（每样本 `distort(player_shadow(...))` 现算）。
   - 难点/工作量：低。纯局部优化，不改外观；Astra 云影 B2 缓存可同样挂进该循环。

7. **多瓣云相位 + 不对称度随光深增长（银边）+ 能量守恒反弹**
   - 要点：`cloudPhaseNew = 0.7·HG(g1) + 0.2·HG(-g2)·backscatter + 0.1·CS`，g 向量 `pow(vec3(0.55,0.45,0.95), 1+OD·σt)` 随局部光深前移；反弹项用 `estimateEnergy(r)=r/(1-r)` 估计多重散射能量。
   - 出处：`P:shaders/lib/atmos/CloudsCommon.glsl:28-30,56-68`；调用与 phaseG 构造 `P:shaders/world0/deferred.fsh:209-219`。
   - Astra 对应：`A:global/atmosphere/clouds_planar.glsl:107-121`（覆盖门控+噪声结构，相位简单）。
   - 难点/工作量：低-中。只替换相位与能量估计函数，不动 Astra 云的 March 结构。

8. **云内光行进的指数步长与高度自适应天空 OD**
   - 要点：向光 OD 行进步长按 2^n 指数增长（远密度廉价化）；向上 OD 步长随当前高度在云层内线性缩短。
   - 出处：`P:shaders/lib/atmos/CloudsCommon.glsl:168-191`（light OD）、`:192-211`（sky OD）。
   - Astra 对应：`A:global/atmosphere/clouds_planar.glsl:81` 起（trace 位置调制）。
   - 难点/工作量：低。步长调度即可移植。

9. **下界环境色由 vanilla fogColor 驱动（生物群系自适应）**
   - 要点：`AmbientColor = mix(netherSkylightColor, LinearToRec2020(normalize(toLinear(fogColor))), 0.9) * 0.3`，让不同下界生物群系（玄武岩三角洲/灵魂沙峡谷…）的环境基调跟随原版雾色。
   - 出处：`P:shaders/world-1/deferred4.vsh:58-59`、`P:shaders/lib/atmos/colorsNether.glsl:26-30`。
   - Astra 对应：`A:global/dimension/nether*.glsl` 与 `A:lib/nether_fog_density.glsl`（九段 compute 体素彩光 + 固定基调）。
   - 难点/工作量：低。在调色板处把基调色改为 fogColor 混合；注意 Astra 的 Rec2020 工作色彩空间与 P 一致（`A:lib/uniforms.glsl` 侧已具备转换）。

10. **末地岛心漩涡烟雾 + 发光辉光**
    - 要点：以岛心为轴的半径依赖旋转场 + 高度重映射的多八度扭曲值噪声；靠近岛心的烟雾按 `glowProximity` 发光，色相由 3D 噪声驱动 HSV 渐变。
    - 出处：`P:shaders/world1/composite.fsh:123-182`（密度+辉光）、`:196-229`（haze+smoke 双介质行进）、开关 `P:shaders/settings.glsl:51-52`。
    - Astra 对应：`A:global/dimension/end*.glsl`、`A:lib/end_surface.glsl`（Kerr 天空与地表光照未覆盖体积烟雾）。
    - 难点/工作量：中。可挂在 Astra 末地雾/体积路径上，注意与 Kerr 黑洞天空的叠加次序。

11. **RGBE 打包 HDR 进 8bit 通道**
    - 要点：直光、albedo、影色等大动态值以 RGBE 编码挤进 pack2x8 对，省 RGBA16F 带宽；解码/编码集中在 encoders.glsl。
    - 出处：`P:shaders/world0/deferred3.fsh:282-290`（packLightingAlbedo）、`P:shaders/world0/deferred12.fsh:56-77`（unpack 复用）、实现 `P:shaders/lib/util/encoders.glsl`。
    - Astra 对应：G-buffer/直光缓冲现用 float 缓冲（`A:lib/settings.glsl` 布局）。
    - 难点/工作量：中。属于带宽优化，需全链路一致替换，收益在 4K/高分辨率下才明显。

12. **物理相机 Bokeh DoF（f-stop/传感器宽 + 色散）**
    - 要点：CoC 由 f-stop 与传感器宽度导出；泊松盘 30/45/60 三档；色散沿散景圆偏移 R/B 通道。
    - 出处：`P:shaders/program/post/lens_1.fsh:54-56`（相机常量）、`:84-148`（Bokeh 主循环、`:144-148` 色散）。
    - Astra 对应：无 DoF 模块（`A:global/post/` 仅 bloom/godrays/grading/exposure/fxaa）。
    - 难点/工作量：中。独立新功能，不与现有 pass 冲突；需要中心深度平滑 uniform。

13. **SVGF 式帧数自适应去噪（先验可复用部分）**
    - 要点：即使不搬整套 SVGF，其"累积帧数驱动滤波强度"的思路（sigmaBias=4/frames、normalExp 随 frames 2→8、方差按历史长度归一）可单独用于 Astra 未来任何随机采样效果（AO/雾/反射）。
    - 出处：`P:shaders/program/deferred/filter.fsh:129-148`（参数自适应）、`P:shaders/world0/deferred5.fsh:61-63`（方差按 frames 归一）。
    - Astra 对应：`A:lib/ao_resolve.glsl:9-17`（AO resolve 已有边停权，但权重不含帧数自适应）。
    - 难点/工作量：低（仅取思路）/高（整套 SVGF）。

14. **大气/云/雾浓度的 CPU 动态 uniform**
    - 要点：晨昏 8 时段加权 + wetness 联动，把 Rayleigh/Mie/臭氧、云量、雾 Mie 系数做成 3 个 vec3 custom uniform，着色器零成本拿到"天气感"。
    - 出处：`P:shaders/shaders.properties:267-286`（大气）、`:292-304`（云）、`:311-315`（雾）。
    - Astra 对应：`A:shaders.properties`（Astra 有 weather/biome tint 但无按时段的散射系数动态）。（与批次一"CPU 预计算 custom uniform"主题重复，本条仅补充 UShader 的具体配方）
    - 难点/工作量：低。

---

## ④ Astra 已有对应实现（对照表）

| 能力 | UShader 做法（P:） | Astra 做法（A:） | 差异与取舍 |
|---|---|---|---|
| SSR | 固定 10-16 步 + 首步最近纹元早检，粗糙面另设低质变体（`P:shaders/world0/composite3.fsh:125-175,377-378`） | 30 步预算 + 6 步 refine，jitter 感知投影（`A:global/water/raytrace.glsl:21-24,37-50`） | Astra 采样预算更高、抖动兼容更好；UShader 更省但水面外用途（粗糙反射）更广 |
| 折射 | 厚度折射：沿 slab 距离折射 + 平面法线修正 + 边缘平方回退（`P:shaders/world0/composite.fsh:437-507`） | 法线扰动 + textureGather 深度域防穿帮 + 可视度渐隐（`A:global/water/refraction.glsl:7-24`） | UShader 折射角物理正确（水下物位置偏移真实）；Astra 更省（一次 gather），误差来自法线近似 |
| 水体吸收 | `volumetricWater` 行进 + `waterAttenCoeff` 常数（`P:shaders/world0/composite.fsh:333-428`） | 光谱吸收/散射分离 + 散射反照率单散射源（`A:global/water/absorption.glsl:51-69`） | Astra 更物理、深水颜色渐变更可控；UShader 颜色偏艺术化 |
| 焦散 | shadow map 空间折射 Jacobian，照亮水底（`P:shaders/program/shadow/comp0.fsh:73-86`） | 高度场散度焦散，用于表面/ VL 染色（`A:global/water/caustics.glsl:38-52`） | 误差来源不同：UShader 几何精确但依赖 shadow 精度；Astra 便宜但平面近似 |
| 云影缓存 | 体积云+卷云透射率烧入小缓冲 alpha，雨态回退（`P:shaders/world0/prepare1.fsh:284-356`） | 平面映射云影缓存 colortex14 + 边缘回退解析（`A:global/atmosphere/cloud_shadow_cache.glsl:10-36`） | UShader 含云体厚度信息（边缘更硬/更真实）；Astra 更省（平面一次采样），误差来自忽略云厚 |
| TAA | TAAU：半分辨率渲染+时域上采样，Catmull-Rom+离中心拒绝（`P:shaders/program/post/temporal.fsh:263-326`） | 全分辨率 HDR TAA，YCoCg AABB + 反应路径（`A:program/taa_resolve.fsh:93-114`） | 目标不同：UShader 换性能，Astra 换清晰度；Astra 的历史校验更严格 |
| AO | 深度域 DSSAO（BSL 授权）+ RTAO 一跳 GI（`P:shaders/world0/deferred3.fsh:310-351`、`P:shaders/program/deferred/PTLight.fsh:196-243`） | 半分辨率 SSAO + bent normal + SH9 方向性天光（`A:lib/ao_resolve.glsl:9-17`、`A:lib/sky_directional.glsl:12-23`） | Astra 的方向性间接（bent normal×SH9）与 RTAO 的 hit 采样间接源殊途同归；RTAO 需要延迟架构才划算 |
| SSS | 5 组径向 shadowtex1 采样 + HG 相位（`P:shaders/world0/deferred3.fsh:235-269`） | wrap 混合 + 叶片专用 in-shadow 因子，复用单次阴影读取（`A:global/lighting/sss.glsl:39-46,106-112`） | Astra 零额外阴影采样更省；UShader 对厚半透明体（冰/肉块）更准 |
| 湿润 | 噪声水洼 + 生物群系干燥度 + 涟漪法线（`P:shaders/program/gbuffer/solid.fsh:238-274`） | block id 分类的湿润材质/光泽（`A:lib/wet_material.glsl:7-23`） | 互补：P 的空间随机水洼观感好，Astra 的分类驱动更稳；可叠加 |
| 风 | 宏观阵风正弦 + 3D 噪声微动（读 uniform，`P:shaders/lib/vertex/wind.glsl:34-67`） | 无 uniform 波函数 + 阵风交叉耦合（`A:global/lighting/wind.glsl:99-147`） | Astra 设计更省（CPU 无关）；P 的阵风包络形状更"风" |
| 复杂曝光 | 亮度格 + 亮/暗百分位（`P:shaders/program/grade/exposure.vsh:36-100`） | 1×1 历史纹测光（`A:global/post/exposure.glsl:22-25`） | （与批次一"复杂自动曝光"主题重复）P 的百分位对大面积天空更稳，Astra 更省 |
| 云时域 | 9 帧 checkerboard + 像素年龄（`P:shaders/world0/deferred1.fsh:198-260`） | 半分辨率 + 独立 reproject 历史（`A:global/atmosphere/cloud_temporal.glsl:59-121`） | Astra 每帧全像素半分辨率；P 的 1/9 采样率更低一档，画质代价是棋盘伪影需靠年龄权重压制 |

哪边更省的小结：阴影采样类（SSS/云影/AO）Astra 普遍更省；UShader 省在"低分辨率化"（TAAU、云 1/9 采样、RGBE 带宽）而非"少采样"。

---

## ⑤ 借鉴可行性（许可证层面）

- 许可证文本：`P:LICENSE`（98 行）。定性条款：`:1-2` All Rights Reserved；`:44-48` 传播仅限作者官方链接、独立托管分发被禁止；`:97-98` 作者可随时修改条款。
- **读思路后独立重写（推荐路径）**：版权保护表达而非思想；本报告 ②③ 列出的算法思路（checkerboard 超分、SVGF 自适应、shadowcomp 焦散等）属于业界公有方法（SVGF 为 2017 公开论文技术、checkerboard 超分是渲染惯例），独立实现 + Astra 自有代码组织不触碰 `P:LICENSE` 条款。仍建议在 Astra 的参考来源台账注明"思路参考 UShader v2.2"以保持溯源惯例（与批次一"读思路 + 独立重写 + 台账登记"口径一致）。
- **直接抄代码（高风险）**：`P:LICENSE:75-81`（Section 4）明确：把本项目源码部分用于另一个原创项目**必须取得作者明确许可**，且需显著署名、禁止货币化。RRe36 的 per-file 头还点名 DMCA 与信息社会指令惩罚（`P:shaders/lib/atmos/air/atmosphere.glsl:13-15`）。Astra 若公开发布，任何结构相似的移植（包括"改名重排"的弱改写）都落入 Section 4 管辖，未经许可不可做。
- 私有修改可自由进行（`P:LICENSE:56-58`），但这只覆盖对 UShader 本身的私人改动，与把代码搬进 Astra 无关。
- 结论：本报告 ③ 的全部条目按"思路级"推进合规；涉及逐行级复用的候选（如 contactShadow.glsl 这类标注"from Spectrum"的第三方混入代码，另受 Spectrum 许可证约束）一律不碰源码，只读论文/公开描述后重写。

---

## ⑥ Top5 优先建议（按 收益/工作量 排）+ 暂缓项

1. **时间跳变历史失效**（③-2）：几行 uniform + 一项校验，修复 `/time set`、睡觉跳时后云/反射/雾的拖影。收益/成本比最高。
2. **云 9 帧 checkerboard 时域超分**（③-1）：Astra 云时域管线现成，采样率从 1/4 降到 1/9 是纯性能收益；与 ⑥-1 的跳变重置天然配套。
3. **阴影彩边抑制（min-color + 边缘锐化）**（③-3）：彩色阴影已是 Astra 既有特性，补上边界处理是画质净增，改动局限在 shadowmap.glsl。
4. **shadowcomp 水面焦散 + 穿水吸收**（③-4）：水底光斑是观感差异最大的一项；Astra 已有波形高度场与 shadow.fsh，新增一个 shadowcomp pass 即可。
5. **体积雾平行阴影空间行进**（③-6）：零外观变化的纯优化，且可顺带把 B2 云影缓存接入同循环。

暂缓项及理由：
- **行星尺度解析大气重写**（③-8/②大气组）：工作量高、且 Astra 天空（Complementary 系三向球面模型，`A:global/atmosphere/sky_gradient.glsl:5-8`）已与其调色体系深度耦合，重写会牵连 SH9/雾/云供色全链。
- **TAAU 低分辨率渲染**（③-13 关联 ②后处理）：需要整管线以 ResolutionScale 双网格运行（MipBias、缓冲尺寸、所有 pass 坐标），Astra 现为全分辨率前向，重构代价远超本批收益。
- **RTAO 一跳 GI**（③-3 之外的 PTLight 全套）：依赖 IndirectSources 延迟缓冲 + SVGF 去噪，前向架构下要把直光结果重新编码回屏幕缓冲，违背 Astra 单 pass 光照的省电初衷；若未来做 SSAO 增强再评估。
- **末地烟雾**（③-10）：观感收益大但与 Kerr 黑洞天空的合成次序需要试做验证，且 Astra 末地当前无体积路径，挂载点需要设计——列为次批候选。
- **Purkinje / 复杂曝光 / CPU 动态 uniform**：与批次一已有主题重复（④表注），除非 UShader 配方被单独点名，否则不重复立项。

---

## 附：自抽查记录（成稿后逐条重新打开源文件核对）

1. `P:shaders/lang/en_US.lang:1-2` — 第1行 `option.INFO=UShader by RRe36`，第2行 `value.INFO.0=v2.2`。✅ 与 ① 所述一致。
2. `P:LICENSE:75-81` — 第77-78行为 "Using parts of this projects source code as part of another, original project requires explicit permission from this projects author."，第80-81行为 credit 与 monetization 禁止。✅ 与 ⑤ 引述一致。
3. `P:shaders/lib/atmos/air/atmosphere.glsl:135-173` — 135 行为 `for (uint i = 0; i < airScatterIterations; ++i)` 主循环起点，152-156 行为 `getAirmass`/`sunlightAtten`，164 行 multiScattering 累加，172 行 transmittance 乘步进透射。✅。
4. `P:shaders/lib/atmos/CloudsCommon.glsl:168-191` — 168 行 `float cloudVolumeLightOD(vec3 pos, const uint steps) {`，169-170 行 `basestep = 5.0; exponent = 2.0;`，182 行 `stepsize *= exponent;`。✅ 指数步长属实。
5. `P:shaders/world0/deferred3.fsh:100-160` — 100 行 `vec4 GetShadowBilinear(...)`，105-106 行 textureGather(shadowtex1/shadowtex0)，139 行 R2 盘循环，151 行 sharpenBorders，157 行 colorMin 混合。✅。
6. `P:shaders/world0/deferred1.fsh:222` — `bool DiscardHistory = offscreen || Discoccluded || WorldTimeChange != 0;`。✅ 与 ③-2 引述一致。
7. `P:shaders/program/shadow/comp0.fsh:121-137` — 121 行 `if (matID == 102 || matID == 103) {     //Water`，123 行 `#ifdef shadowcompCaustics`，133 行 `vec3 absorb = exp(...)`，136 行 `data0 = vec4(absorb * 0.25, 1.0);`。✅。
8. `P:shaders/program/deferred/PTLight.fsh:196-243` — 196 行 `vec3 RaytraceAO(...)`，204 行 R2 拟随机序列，216 行 GenerateCosineVectorSafe，230 行 `radiance += texture(colortex4, projectSky(worldDir, 2)).rgb * brdf * Occlusion;`（天空图采样）。✅。
9. `P:shaders/program/deferred/filter.fsh:129-148` — 129 行 `#ifdef RTAO_ENABLED` 起 frames 读取，135 行 `sigmaBias = (4.0 / max(frames, 1.0)) + 0.25;`，148 行 normalExp 随 frames 混合。✅。
10. `P:shaders/lib/frag/checkerboard.glsl:27-37` — `temporalOffset9[9]` 九元素轮转表，首个元素 `ivec2(0,0)`。✅。
11. `P:shaders/world0/deferred1.fsh:231-243` — 231 行 `float Samples = max(PixelAge - 9, 1.0);`，237-239 行 PixelDelta 子像素权重，249 行 `FinalColor = mix(historyColor, currentColor, AccumulationWeight);`。✅。
12. `P:shaders/shaders.properties:247-248` — 247 行 `variable.float.smoothWorldTime = smooth(sunDirZ, frameTime*8.0, frameTime*8.0)`，248 行 `uniform.int.WorldTimeChange = if(abs(smoothWorldTime - sunDirZ) > 0.9, 1, 0)`。✅。
13. `P:shaders/world-1/deferred4.vsh:58-59` — 58 行 `AmbientColor = netherSkylightColor;`，59 行 `AmbientColor = mix(AmbientColor, LinearToRec2020(normalize(toLinear(fogColor))), 0.9) * 0.3;`。✅ 与 ③-9 引述一致。
14. `P:shaders/world1/composite.fsh:123-182` — 123 行 `vec2 smokeDensity(...)`，136 行半径依赖 `rotatePos`，170-177 行 `#ifdef endSmokeGlow` 辉光段。✅。
15. `P:shaders/world0/composite.fsh:214-222` — 214-219 行 shadowStartPos/shadowEndPos 变换，221 行 `vec3 shadowStep = (shadowEndPos - shadowStartPos) / float(steps);`。✅。
16. `P:shaders/world0/deferred.fsh:213,218-219` — 213 行 `vec3 phaseG = pow(vec3(0.55, 0.45, 0.95), vec3((1.0 + (lightOD + density * rLength) * sigmaT)));`，218-219 行 `stepScatter.x/y += baseScatter * cloudPhaseNew(...)`。✅。
17. `P:shaders/program/post/temporal.fsh:296-297` — 296 行 `vec2 pixelOffset = 1.0 - abs(2.0 * fract(HistoryUV * viewSize) - 1.0);`，297 行 OffcenterRejection 计算。✅。
18. `P:shaders/program/gbuffer/solid.fsh:238-274` — 238 行 `void getWetness(...)`，241 行含 `RW_BIOME_Dryness`，268 行 `wetnessOut = sqr(linStep(noise, 0.35, 0.57));`。✅。
19. `P:shaders/program/grade/exposure.vsh:36-40` — 36 行 `ivec2 tiles = ivec2(viewSize * cube(0.25) - 1);`，38 行 `#ifdef exposureComplexEnabled`，40 行 `float getExposureLuma() {`。✅。
20. `P:shaders/lib/internal.glsl:43-44` — `#define cloudShadowmapRenderDistance 4e3` / `#define cloudShadowmapResolution 512`。✅（注：② 中"256² 云影图"表述以缓冲实际网格 colortex4 256×384 的下 3/4 区域为准，分辨率常量名义为 512，两处描述已在 ② 内核对措辞，坐标映射见 `P:shaders/world0/prepare1.fsh:384-386` 与 `P:shaders/world0/composite.fsh:100`）。

---

*报告生成：2026-10-02。调研范围仅为上述白名单目录；未对 Astra 与参考包做任何写操作。*
