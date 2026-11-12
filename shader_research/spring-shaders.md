# spring-shaders（春 v2）面向 Astra 的可借鉴点调研

- 生成方式：批次二调研子代理（只读两包源码，行号全部实测）。
- 包：`spring-shaders` / Spring Shaders (Chun) v2，作者 ZYPanDa（中影），版本 260618，下载 297,502（`reference_shaderpacks/INDEX-batch2.md`、`shader_research/SUMMARY-batch2.md:77`）。
- 调研日期：2026-10-02。
- 引用约定：`P:` = 相对 `reference_shaderpacks/spring-shaders/`；`A:` = 相对 `Astra/shaders/`。
- 规模实测：512 个源码文件 / 20,626 行，其中 368 个（合计 1,919 行）是 1–8 行的包装壳，真实实现约 18.7k 行。

## ① 概览

**定位**：中文社区知名光影，自述为学习《Games202》的练习作品（`P:README.md:24`），结构参考 BSL（`:31`），部分代码由 AI 工具辅助生成（`:30`）。功能面见选项屏 `P:shaders/shaders.properties:14-72`：路径追踪 + 彩色光（体素 + SDF）、RSM、GTAO、PCSS、体积云/雾、大气散射 + 双重 LUT、TAA/RCAS/aniso、视差、雨湿涟漪、下界/末地色调、Bloom/DoF、HDR mod（`:56`）。

**架构**：
- 维度分派薄壳：`P:shaders/world0/deferred10.fsh:1-6`；`P:shaders/world1/deferred10.fsh:4,7` 加 `#define END` 指向 `P:shaders/program/world_1/*`；`P:shaders/world-1/deferred10.fsh:4,6` 加 `#define NETHER` 指向 `world__1/*`。共享库 `lib/`，选项单文件 `P:shaders/lib/settings.glsl`（661 行）。
- gbuffer 打包：c0=albedo、c4=`pack2x8To16(parallaxShadow, blockID/ID_SCALE)`+`pack4x8To2x16(specular)`、c5=octahedral 法线+lmcoord、c15=几何法线（`P:shaders/program/gbuffers_terrain.glsl:180-186`，解包 `P:shaders/lib/common/gbufferData.glsl:1-14`）。
- 体素链路：阴影 pass capture 写 `customimg0/4`（`P:shaders/program/shadow.glsl:131-132`）→ 时域重投影 0.98 混合 + prev 拷贝（`P:shaders/program/shadowcomp1_a.glsl:5-62`、`P:shaders/program/shadowcomp1_b.glsl:14-25`）→ 三轴 SDF（`P:shaders/program/shadowcomp_a/b/c.glsl`）→ DDA（`P:shaders/lib/lighting/pathTracing.glsl:246-423`）。体素 256×128×256（`P:shaders/lib/settings.glsl:345-346`）；image 注册与 `CUSTOM_IMAGES` `P:shaders/shaders.properties:211-220,120`。

**许可证（`P:LICENSE`）**：标题 `:1,57,62`；Section 1 `:71`、Adapted Material `:73`、NonCommercial 定义 `:125`（"not primarily intended for or directed towards commercial advantage or monetary compensation"）、P2P 共享仍非商业 `:129`；Section 2 Scope `:151`，`:161-164` 限定 "solely for NonCommercial purposes"（**NC 是范围限制，非 Section 3 条件**），(c) 禁下游追加限制 `:200`；Section 3 `:237`：Attribution `:242`（须声明曾修改 `:266-267`）、ShareAlike `:283`（禁追加条款 `:297`）；其余 `:303,327,356,385,395`。作者三条规则 `P:README.md:7,16,17,18`（署名 / 禁商用含付费墙与广告跳转 / 同许可开源）。

## ② 架构特性清单（按子系统）

- **阴影/AO**：blocker 搜索/PCF/PCSS `P:shaders/lib/lighting/shadowMapping.glsl:53-151`；彩色阴影 `:153-197`；VSSM `:198-229`；SSAO/HBAO/GTAO/多次弹射 `P:shaders/lib/lighting/SSAO.glsl:1-46,48-81,85-143,145-150`。
- **GI/PT**：RSM `P:shaders/lib/lighting/RSM.glsl:3-100,102-191,192-234,235-310,311-340`；PT 采样/SSR 二次追踪/AABB/曼哈顿 DF/DF-DDA/时域/去噪 `P:shaders/lib/lighting/pathTracing.glsl:10-78,80-234,241-423,426-541,542-593,608-712`。
- **随机源**：`temporalBayer64` `P:shaders/lib/common/noise.glsl:34`、时空蓝噪声 `:39-73,87,115-148`；TAA 用 `Halton_2_3[framemod8]` `P:shaders/program/gbuffers_terrain.glsl:325-328`。
- **大气/云/雾**：散射与 LUT `P:shaders/lib/atmosphere/atmosphericScattering.glsl:12-81,103-173,174-306,312-428`；体积云 `P:shaders/lib/atmosphere/volumetricClouds.glsl:18-115,116-201,203-313,314-352`；雾 `P:shaders/lib/atmosphere/fog.glsl:4-80,81-147,181-227,228-309,310-371`；2D 云/末地/天体 `P:shaders/lib/atmosphere/clouds2D.glsl:1-50`、`P:shaders/lib/atmosphere/endFog.glsl:209-283`、`P:shaders/lib/atmosphere/celestial.glsl:1-38`。
- **水体**：`P:shaders/lib/water/waterNormal.glsl:6-38,104-202,203-251,252-296`；`P:shaders/lib/water/waterReflectionRefraction.glsl:16-27,30-137,139-211,212-393`；`P:shaders/lib/water/waterCaustics.glsl:1-112`；`P:shaders/lib/water/waterFog.glsl:2-107`；`P:shaders/lib/water/translucentLighting.glsl:1`。
- **材质**：`P:shaders/lib/surface/parallaxMapping.glsl:18-52,133-204,205-359,369-412`；`P:shaders/lib/surface/PBR.glsl:87-119,139-151,233-270,326-357,366-389`；`P:shaders/lib/antialiasing/anisotropicFiltering.glsl:5-44`、`P:shaders/lib/camera/filter.glsl:6-33,197-241`；`P:shaders/lib/surface/ripple.glsl:4-71`；`P:shaders/lib/common/materialIdMapper.glsl:1-15`；GS `P:shaders/program/gbuffers_terrain.glsl:195,220-249`。
- **后处理/UI**：TAA `P:shaders/lib/antialiasing/TAA.glsl:7-142`；RCAS `P:shaders/lib/antialiasing/FSR.glsl:1-26`；曝光 `P:shaders/lib/camera/exposure.glsl:22-29`；色调映射 + simpleFilter `P:shaders/lib/camera/toneMapping.glsl:4-238,150-156`；Bloom/暗角 `P:shaders/lib/camera/bloom.glsl:5-34`、`P:shaders/lib/camera/postFX.glsl:1-8`；预设与 UI `P:shaders/shaders.properties:1-6,14-72,77-114`。

## ③ 可借鉴点（12 条）

**1. 三轴可分离距离变换（SDF）compute**
- 技术：X/Y/Z 三个 compute 各做前缀/后缀 min 并行扫描（shared 数组 + barrier），`d=min(x+prefMin,-x+sufMin)`，一次得到精确曼哈顿 DF（无需历史）。附带的体素时域重投影（`P:shaders/program/shadowcomp1_a.glsl:14-62`、`_b.glsl:14-25`：相机位移重投影 + 占用不一致弃历史 + `mix(cur,hist,0.98)`）是同一套基础设施。
- P: `P:shaders/program/shadowcomp_a.glsl:14-54`、`_b.glsl:15-56`、`_c.glsl:15-53`；地址换算 `P:shaders/lib/lighting/voxelization.glsl:4-7,26-35`
- A: 无；Astra 体素只有 64³ 光传播（`A:program/nether_light.csh:12-14`、`A:lib/nether_voxel_grid.glsl:29-37`）；时域版本可对照 `A:lib/effect_history.glsl:17-38`
- 工作量：中。**与批次一重复**（rethinking-voxels 的 SDF；差异点：不需历史也精确，`:24,34`）。

**2. 距离场加速的体素 DDA**
- 技术：标准 DDA（tDelta/tMax + tie + 法线优先级 x>y>z），空体素 DF 跳步：L1 半径 `d-1.5`、`dtSkip=remain*invRdL1`，d≤2 退化单步，跳后重建状态。
- P: `P:shaders/lib/lighting/pathTracing.glsl:246-423`（跳步 `:340-380`）、`:241-244`
- A: 无体素射线求交（`A:global/water/raytrace.glsl` 是屏幕空间深度行进）
- 工作量：中高（依赖第 1 条）。**与批次一重复**（rethinking-voxels 的 coneTrace）。

**3. TAA：色调映射空间裁剪 + 深度置信度 + 亮度差收缩**
- 技术：统计先 `RGB2YCoCgR(ToneMap(color))` 防超亮像素拉爆 AABB；`depth_confidence` 用上帧深度重投影一致性（相对差 0.0015→0.01）× 速度衰减；混合系数 `clamp(max(1-depthConf, smoothstep(0.01,0.15,lumDiff))*0.05, 0.02, 0.05)`。
- P: `P:shaders/lib/antialiasing/TAA.glsl:47-92`、`:7-32`、`:94-104`、`:243-252`
- A: `A:program/taa_resolve.fsh:103-138`（已有统计边界/运动权重）、`:30-54`
- 工作量：低。可借两点：统计放色调映射后、混合系数加亮度差项。**与批次一重复**（TAA 通用项）。

**4. PCSS 风格：blocker 搜索 + 解析 penumbra**
- 技术：黄金角螺旋搜 blocker 平均深度（`c<=0.8` 判无遮挡），`penumbra=100*(dReceiver-dBlocker)/dBlocker`，按距离与 `|N·L|` 加偏移，以 `baseSoftness+penumbra+rainStrength` 为半径做螺旋 PCF；植物固定 1.5。
- P: `P:shaders/lib/lighting/shadowMapping.glsl:53-85,87-115,119-151`
- A: 固定半径 `A:global/lighting/shadowmap.glsl:54`、grazing bias `:157-201`、gather lobe + 彩色透射 `:104-135`
- 工作量：中（Astra 无接触硬化，需加采样循环并按 `SHADOW_FILTER_QUALITY` 分档）。

**5. RSM GI 与泄漏两级抑制**
- 技术：逐样本用环带面积 `w_cur=(a²-b²)π`；双向余弦法线；天光取 `shadowcolor1.a` 并 `smoothstep(0,0.25)`；总亮度按 `RSM_SEARCH_RADIUS²/57600` 归一。泄漏抑制：沿 `mainDir` 屏幕空间步进折算泄漏 AO，体素版改 DDA 采样占用，消除屏外/背面泄漏。
- P: `P:shaders/lib/lighting/RSM.glsl:3-100`（权重 `:74-95`）、`:102-163`、`:164-191`
- A: 无 GI；间接光 = SH9 + 环境项（`A:lib/sky_sh9.glsl:135-170`、`A:global/lighting/diffuse.glsl:103`）；AO 重建 `A:lib/ao_resolve.glsl:19-52`
- 工作量：高（`A:program/shadow.fsh` 需输出通量/法线，重排彩色阴影）。**与批次一重复**（ebin）。

**6. 体积云光照 + 云影透射**
- 技术：(a) 衰减概率 `pow(ds,k)` 近似能量守恒；(b) powder `0.05+pow(ds, atten*height*POWDER)`；(c) 银边 = 双向相位取 max（0.2/0.5/0.5 与 0.99 窄瓣）；(d) 上方向环境额外采 `upWorldDir` 光路 × `0.15*isNoon`；另有沿光线积分云内密度的云影透射；march 有 `MAX_TOTAL_STEPS=256` 预算保护。
- P: `P:shaders/lib/atmosphere/volumetricClouds.glsl:116-169`、`:170-201`、`:77-115`、`:203-313`
- A: `A:global/atmosphere/clouds_planar.glsl:56-64,144,241`、`A:global/atmosphere/cloud_shadow_cache.glsl:7-24`、`A:lib/volume_integral.glsl:1-127`
- 工作量：低。误差来源：全闭式近似、光路只取 4/2 样本，云边缘靠模糊与时域掩盖。

**7. 体积雾远近分段步长**
- 技术：射线与雾层 AABB 裁剪后按 `shadowDistance` 分近段（`FOG_NEAR_UNIT` 密步长、逐点查阴影）与远段（`FOG_FAR_UNIT` 疏步长、免阴影）；`density<0.001` 早退；亮度与云同构。
- P: `P:shaders/lib/atmosphere/fog.glsl:228-309`、`:181-227`、`:81-147`
- A: `A:global/atmosphere/volume_fog.glsl:31-45`（步数档）、`:62-89`（高度消光/相位/入射）、`:91`（shadow 开关摊销）
- 工作量：低-中。

**8. 水体 SSR：精修 + 伪命中过滤 + 未命中点输出**
- 技术：步长指数增长 + bayer 起点抖动；穿面后 5 次二分精修；`tp_dist < ds_len*sqrt(1-cosA²)` 剔除擦边命中；命中天空判未命中；未命中输出最后有效点 `outMissPos`（供 PT 回退），另有"追到远端也算命中"兜底；DH/Voxy 采样 ×1.5。
- P: `P:shaders/lib/water/waterReflectionRefraction.glsl:30-137`、`isNotSky :16-27`、PT 版 `:80-185`
- A: 预算/精修 `A:global/water/raytrace.glsl:14-24`、投影有效性 `:44-68`
- 工作量：低-中。**与批次一重复**（rethinking-voxels 亦报 SSR→SDF rayTrace 回退，`:111`）。

**9. 焦散色散：沿高度梯度偏移 R/B**
- 技术：取高度场梯度方向，R/B 沿该方向 ±偏移后各自求拉普拉斯焦点亮度，按 `CAUSTICS_DISPERSION` 混合；亮度 `1-exp(-focus*exposure)` 后再 pow + 范围重映射。
- P: `P:shaders/lib/water/waterCaustics.glsl:26-35,37-74,78-81,83-112`
- A: `A:global/water/caustics.glsl:45-52`（单通道无色散）、`:54-59`（阴影侧同图案）
- 工作量：低（3 次额外高度求值）。误差来源：纯视觉近似。

**10. 雨湿地面 + 解析涟漪法线**
- 技术：`wetFactor=smoothstep(0.88,0.95,lmcoord.y)*rainStrength` × 群系降水 × 噪声（仅顶面），只在 `RIPPLE_DISTANCE` 内、有雨、顶面时用解析环 profile 扰动世界法线；湿度抬高 specular smoothness/F0。
- P: `P:shaders/program/gbuffers_terrain.glsl:117-137,155-163`、`P:shaders/lib/surface/ripple.glsl:4-9,10-50,51-65,66-71`、参数 `P:shaders/lib/settings.glsl:112-125`
- A: `A:lib/wet_material.glsl:7-12,16-21,23-28`（有材质分级湿响应，无涟漪/噪声/群系门控）
- 工作量：低。

**11. 色彩管线：CDL + 每算子 additive + AgX EV**
- 技术：(a) `simpleFilter=pow(color*slope,power)` 后按亮度混饱和再加 offset，接在曝光后、色调映射前；(b) 每算子配 additive 预曝光（ACES 0.75 / AgX 2.0 / Hable 1.8 / Hejl 0.75）；(c) AgX 用 `clamp(log2(color/0.18),±EV/2)` 归一后过 6 阶多项式，EV 默认 12。
- P: `P:shaders/lib/camera/toneMapping.glsl:150-156,158-184,106-148`；参数 `P:shaders/lib/settings.glsl:568-577,586,591-600`；顺序 `P:shaders/program/composite23.glsl:77,86`
- A: `A:lib/color_controls.glsl:29-53`、`A:global/post/grading.glsl:157-168,190-194`、`A:lib/tonemap.glsl:102-146`（已有 CDL，仅用于 AgX look）
- 工作量：低。Astra 缺 filterOffset（暗部提亮）。**与批次一重复**（AgX/CDL）。

**12. 一行式预设（profile）绑定质量 + 色调**
- 技术：`profile.Xxx = VAR=值 ...` 一行改多项；3 个只改色调 + 滤镜 + `BLOOM_AMOUNT`（Vivid = `FILTER_CONTRAST=1.1 FILTER_SLOPE_ALPHA=1.3 FILTER_SATURATE=1.05 TONE_MAPPING=AgX`）。
- P: `P:shaders/shaders.properties:1-6`
- A: `A:shaders.properties:444-447`（4 个 profile 只覆盖质量/功能）、`:700-714`（颜色另走 COLOR_STYLE/TINT）
- 工作量：低（1–3 行 Look profile）。

## ④ Astra 已有对应实现对照表

| 主题 | Spring（P:） | Astra（A:） | 哪边更省 | 误差来源 / 备注 |
|---|---|---|---|---|
| 色彩分级 | slope/offset/power/sat（settings.glsl:568-577 → composite23.glsl:77） | 色温+鲜艳+饱和+对比+三段 LOOK（grading.glsl:157-194）；tonemap 见 tonemap.glsl:102-146 | Astra 自由度更多 | Astra 无 offset（暗部提亮）、无换算子保亮 additive 表；Spring 无色温旋钮 |
| 曝光 | mip 全屏平均 + `pow(mix(1,t/avg,d),s)`（exposure.glsl:1-29） | 8x8 加权网格 + 历史 + 快慢时间常数 + 增益上下限（exposure.glsl:35-60） | Astra 更稳 | 无上下限，切维度会跳曝光 |
| AO | SSAO/HBAO/GTAO + 多次弹射（SSAO.glsl:1-150） | 12 步半分辨核 + bent normal（ssao.fsh:1-40,51-117），无多弹射 | 各有所长 | 多次弹射多项式（SSAO.glsl:145-150）Astra 零命中；bent normal 是 Astra 独有 |
| 阴影 | blocker 搜索 PCSS（shadowMapping.glsl:53-151） | 固定半径 gather lobe + 彩色透射（shadowmap.glsl:54,92-135） | Astra 保真更高 | Spring 有接触硬化；gather 更省采样 |
| RSM/GI | 完整 RSM（RSM.glsl:3-340） | 无 GI，SH9 + 环境项（sky_sh9.glsl:135-170, diffuse.glsl:103） | Astra 更省 | 需重排 shadowcolor 布局；低频噪 |
| 体素/PT | 256×128×256 + 3-pass SDF + DDA（pathTracing.glsl:246-423） | 64³ 下界彩色光传播（nether_light.csh, nether_voxel_grid.glsl:29-63） | Astra 更省 | 2 张 3D image + 3 csh 换 GI/软影 |
| 体积云 | 双层 march + 云影 + 时域（volumetricClouds.glsl:77-352） | 平面云 + 独立历史 + 云影缓存（clouds_planar.glsl:56-64,241, cloud_temporal.glsl:30-31） | Astra 更省 | 云影只 4 采样，边缘跳变 |
| 水面 | 双波场 + 视差 + 色散焦散 + SSR/PT 回退（waterNormal.glsl, waterCaustics.glsl:37-112, waterReflectionRefraction.glsl:30-137） | Solas 焦散 + Steadfast 表面 + SSR 精修（caustics.glsl:5-44, surface.glsl:3-24, raytrace.glsl:14-24,44-68） | Astra 更省 | Spring 色散为视觉近似；Astra 无色散/涟漪 |
| 湿润/雨 | 群系门控湿 + 解析涟漪（gbuffers_terrain.glsl:117-137, ripple.glsl:4-71） | 材质分级湿响应（wet_material.glsl:7-28） | Astra 更省 | 多约 6 次高度求值/像素换观感 |
| TAA | 深置信度 + 色调空间裁剪 + 自适应混合（TAA.glsl:7-142） | 历史重建 + 统计边界 + 反应位 + ANTIALIASING 0/1/2（taa_resolve.fsh:30-138, taa_state.glsl:13-35, settings.glsl:237-240） | Astra 状态管理更完整 | Spring 的色调空间统计与亮度差收缩是 Astra 缺的两点 |
| 选项/UI | 一行式 Look profile + 双语 lang（shaders.properties:1-6） | 4 个质量 profile + properties 表达式（shaders.properties:421-447,459-632） | Astra 表达力更强 | 缺"Look profile"一键风格切换 |
| 维度分派 | 薄壳 + world_1/world__1 私有实现（world1/deferred10.fsh:1-7） | `global/dimension/*` + DIMENSION_* 宏 | Astra 更省 | 维度体两套并行，维护成本高 |

## ⑤ 许可可行性与"重写 vs 抄"边界

**三条硬义务（原文行号）**
1. 署名：共享（含修改版）须保留作者标识与许可链接/全文，并声明"曾修改"（`P:LICENSE:242`、`:266-267`）。
2. 非商业：授权范围限定 "solely for NonCommercial purposes"（`:161-164`）；NonCommercial 定义 `:125`（不看是否盈利，看意图与导向），P2P 共享仍算非商业 `:129`；作者点名付费墙与广告跳转下载 `P:README.md:17,80`。
3. 相同方式共享：改编物必须用 BY-NC-SA 4.0 同类许可（`:283`），不得追加限制（`:297`、`:200`）。

**对 Astra 的具体风险**
- Astra 若上架带收益机制的平台（赞助/广告分成/付费墙下载），**直接触发 NC 违反**（依据 `P:LICENSE:125` 的意图导向）。
- SA 与 Astra 现有许可冲突是关键阻断点：`A:global/water/surface.glsl:3-24` 明确是 Steadfast（GPL-3.0-or-later + Section 7 附加条款）派生，`A:lib/tonemap.glsl:4-17` 是 MIT 系派生。若因搬运 Spring 代码而让整包改按 BY-NC-SA 发布，将与 GPL-3.0 的同类许可要求冲突（CC 的 NC 系列不能作为 GPL 兼容许可），无法同时满足两份许可。
- 结论：**对 Astra 只能是"读思路、独立重写"**。这是 NC/SA 与既有 GPL 派生文件的兼容性硬约束。

**可操作边界**
- 可以：读算法与公式并自行实现（数学与公开文献不受 Spring 版权约束；其上游亦为公开文献，见 `P:shaders/lib/lighting/RSM.glsl:1-2`、`P:shaders/lib/atmosphere/atmosphericScattering.glsl:1-10`）；常量量级可作调参起点。
- 不可以：复制函数体/分支结构/注释/参数表/命名与文件划分。`P:LICENSE:73` 对 Adapted Material 的定义很宽（含翻译、改编、修改），**连注释一起搬就落入 SA**；`P:shaders/lib/lighting/RSM.glsl:1-2` 这类署名注释本身是版权材料；本包结构参考 BSL（`P:README.md:31`），Astra 无需在结构上致敬它。
- 交付纪律：借鉴改动统一注释为"Astra 原创实现，思路来源：公开文献 + 对 spring-shaders 的只读分析"，不出现其代码行、注释与原值长表。

## ⑥ Top5 与暂缓项

**"清新"色调参数与落点（可直接对照 Astra 四种颜色方案）**

| 维度 | Spring 落点与默认值 | 说明 |
|---|---|---|
| 曝光 | `P:shaders/lib/camera/exposure.glsl:22-29`；`TARGET_BRIGHTNESS 0.11`、`LIGHT_SENSITIVITY 1.5`、`EXPOSURE_DELTA 0.55`（settings.glsl:555-559） | 整体压暗留高光余量 |
| 白平衡/色温 | `FILTER_SLOPE_R/G/B=1.0` + `FILTER_SLOPE_ALPHA` 总增益（settings.glsl:568-572），应用 composite23.glsl:77 | 靠 RGB slope 比例 |
| 对比 + 饱和 | `FILTER_CONTRAST 1.0` → `filterPower`、`FILTER_SATURATE 1.0`（settings.glsl:575-577）；`pow(color*slope,power)` + 亮度混饱和（toneMapping.glsl:150-156） | 幂函数对比 + 亮度线性混饱和 |
| 暗部提亮 | `FILTER_WHITE 0.0` → `filterOffset`（settings.glsl:573-574） | Astra 缺此项 |
| 色调映射 | 默认 AgX（settings.glsl:586），`AGX_ADDITIVE 2.0`（:593）、`AGX_EV 12.0`（:600），曲线 toneMapping.glsl:158-184 | 亮而不爆 |
| 时间性色温 | 白日 `IncomingLight=(1,1,1)×8.0`（settings.glsl:208-212）；夜间 `IncomingLight_N=(0.80,0.90,1.0)×0.125`（:214-218），应用 deferred11.glsl:68-69 | "清新"核心 |
| 人造光 | `artificial_color=(0.9,0.4,0.025)×1.0`（settings.glsl:360-364）、`GLOWING_BRIGHTNESS 0.5`（:358）、`SKY_LIGHT_BRIGHTNESS 5.0`（:359） | 冷暖对撞 |
| 水色 | `waterFogColor=(0.2,0.75,0.9)×1.0`（settings.glsl:467-471）、`UNDERWATER_BRI/CONTRAST 1.5`（:488-489） | 最直接的色彩锚点 |
| 维度色 | 末地 `(0.175,0.075,0.9)`（settings.glsl:651-655）；下界 `(0.9,0.3,0.06)`（:657-661） | 蓝紫 / 橙红 |
| 泛光/暗角/节奏 | `BLOOM_AMOUNT 0.02`、`RAIN_ADDITIONAL_BLOOM 0.04`（settings.glsl:539-540）；VIGNETTE 默认关闭（:603-609）；`NOON/NIGHT_DURATION 20/40`（:23-24） | 通透、过渡慢 |

对照 Astra：自由度更多（`A:lib/settings.glsl:245` COLOR_STYLE 0–3 + 60 组 `TINT_*`/`LOOK_*` + `COLOR_TEMPERATURE` `A:global/post/grading.glsl:157-168`），四方案见 `A:lib/color_controls.glsl:29-53`（1 暖 top 1.02/1.01/0.94；2 冷 0.91/1.00/1.09；3 柔 0.96 + 环境 ×1.12）。Spring 可用之处是**配方而非机制**：夜冷蓝比、极暖人造光、青蓝水雾、中性滤镜 + 弱泛光 + 无暗角；建议以 Look profile 做对照实验。

**Top5（收益/工作量）**
1. **TAA 色调空间统计 + 亮度差收缩**（③3）：`P:shaders/lib/antialiasing/TAA.glsl:47-104` → `A:program/taa_resolve.fsh:103-138`。低，直击拖影/火萤。
2. **雨湿涟漪 + 湿度噪声/群系门控**（③10）：`P:shaders/lib/surface/ripple.glsl:4-71` → `A:lib/wet_material.glsl:7-28`。低，补"雨后清新"缺口。
3. **Look profile 一键切四种颜色方案**（③12 + 上表参数）：`P:shaders/shaders.properties:1-6` → `A:shaders.properties:444-447`。低。
4. **体积云/雾光照项逐项比对**（powder、上向环境、银边取 max）（③6、③7）：`P:shaders/lib/atmosphere/volumetricClouds.glsl:116-201`、`P:shaders/lib/atmosphere/fog.glsl:181-227` → `A:global/atmosphere/clouds_planar.glsl:144,241`、`A:global/atmosphere/volume_fog.glsl:31-89`。低-中。
5. **水体 SSR 三处细节**（擦边过滤、命中天空排除、未命中点输出）（③8）：`P:shaders/lib/water/waterReflectionRefraction.glsl:16-27,30-137` → `A:global/water/raytrace.glsl:14-24,44-68`。低-中。

**暂缓项**
- 3-pass SDF + DDA 体素射线（③1、③2）：需 3 张 3D image + csh，且与批次一 rethinking-voxels 方向重复。
- RSM GI 与泄漏抑制（③5）：需重排 `A:program/shadow.fsh` 通道，与批次一 ebin 结论重复。
- 视差（含 voxel 高度）与 atlas 各向异性：批次一已判定会破坏 Astra 方向性天光/bent normal，收益低于成本。
- 大气 LUT（`P:shaders/lib/atmosphere/atmosphericScattering.glsl:103-306`）：批次二 SUMMARY 已排后（静态资产无法响应天气与四种颜色方案），与 reverie/musk-rose 同向。
- Gerstner 双波场与色散焦散：与批次一 photon 重复；Astra 水面已双 GPL 源，改动需同步两份契约。
- MotionBlur/DoF/Letterbox/HDR-mod 分支：非当前设计目标。

## 附录：自抽查记录（重开文件核对，2026-10-02）

方法：`sed -n '<行>p'` 打印引用行比对正文，共 10 组。

1. `P:shaders/lib/lighting/pathTracing.glsl:241` → `uint voxelManhattanDF(ivec3 v) {`；`:357` → `float dtSkip = remain * invRdL1;` 一致。
2. `P:shaders/program/shadowcomp_b.glsl:54` → `int d = min(y + prefMin, -y + sufMin);`；`P:shaders/lib/camera/toneMapping.glsl:150` → `vec3 simpleFilter(vec3 color, vec3 slope, vec3 offset, vec3 power, float sat) {` 一致。
3. `P:shaders/lib/antialiasing/TAA.glsl:52` → `vec3 C = RGB2YCoCgR(ToneMap(textureLod(colortex0, newUV, 0.0).rgb));` 一致。
4. `P:shaders/lib/settings.glsl:557` → `#define TARGET_BRIGHTNESS 0.11 ...`；`:569` → `#define FILTER_SLOPE_GREEN 1.0 ...` 一致。
5. `P:shaders/lib/atmosphere/volumetricClouds.glsl:186` → `float inScatter = GetInScatterProbability(height_fraction, density, attenuation, VoL);`；`P:shaders/lib/water/waterCaustics.glsl:99` → `vec3 offR = vec3( 0.0, shift * 0.66, 0.0 );` 一致。
6. `P:shaders/program/gbuffers_terrain.glsl:183` → `gl_FragData[1] = vec4(pack2x8To16(parallaxShadow, 0.0), pack2x8To16(blockID/ID_SCALE, wetFactor), pack4x8To2x16(specularTex));`；`:325-328` → `vec2 jitter = Halton_2_3[framemod8];` / `gl_Position.xy += jitter * TAA_JITTER_AMOUNT;` 一致（核对中把初稿误写的 `:252-258` 改正）。
7. `P:LICENSE:283` → `b. ShareAlike.`；`:297` → `3. You may not offer or impose any additional or different terms` 一致。
8. `A:lib/settings.glsl:245` → `#define COLOR_STYLE 0 // [0 1 2 3]`；`:239-240` → `#define ANTIALIASING 1 // [0 1 2]` / `// 0 off, 1 display-space FXAA, 2 HDR temporal AA with projection jitter.` 一致（核对中把初稿的 `:240-245` 改正）。
9. `A:lib/color_controls.glsl:36` → `const vec3 ASTRA_STYLE_TOP = vec3(0.91,1.00,1.09);`（COLOR_STYLE==2）；`A:global/post/grading.glsl:190` → `vec3 apply_grading(vec3 displayColor) {`；`A:lib/ao_resolve.glsl:19` → `float astra_ao_visibility(vec2 uv, float viewDepth, vec3 normal, out vec3 bentNormal) {` 一致。
10. `A:global/water/raytrace.glsl:15` → `const int ASTRA_WATER_TRACE_BUDGET = 16;` 一致（高档 40 在 `:18`，中档 30 在 `:21`；核对中把初稿误写的 `:20-30` 区间改正为 `:14-24`）。

抽查覆盖 10 组（体素 DDA、SDF、色调映射、TAA、体积云、焦散、gbuffer 打包、许可证、Astra 颜色/分级/AO/水体/AA），全部与正文一致；核对阶段共修正 3 处引用（第 6、8、10 条），正文 ③、④ 表、Top5 与 ⑥ 均已同步。
