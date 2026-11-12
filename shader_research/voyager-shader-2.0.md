# Voyager shader 2.0（voyager-shader-2.0）可借鉴点调研报告 · 面向 Astra

> 生成方式：**子代理调研**（执行者子智能体成稿，非主代理自撰）；包版本：**2.0.8**（作者 6ix7even，下载 743,377，`reference_shaderpacks/INDEX-batch2.md:23`）；调研日期：**2026-10-02**。
> 引用约定：`P:` = `reference_shaderpacks/voyager-shader-2.0/` 相对路径；`A:` = `Astra/shaders/` 相对路径。**行号全部来自本次逐文件实读**，成稿后另做 12 条抽查（附录）。
> 定位（批次二索引原话）：高下载写实向；**PBR 材质与水面反射的折中做法**。

## ① 概览

- 包体：264 文件、约 0.35 MB；顶层只有 `changelogs.txt`（2595 B）与 `shaders/`；贴图仅 64×64 噪声与 voronoi（`P:shaders/shaders.properties:67-68`），全程序化、无 LUT 资产。
- **许可证：包内无 LICENSE、无版权声明**。全包文本检索 `licen|copyright|保留|许可` **零命中**（实测）——不存在可引用的许可原文行号，仅为致谢注释（`P:shaders/lib/brdf.glsl:1-4`、`P:shaders/lib/encode.glsl:1`、`P:shaders/program/shaders1/common/volumetric/clouds_3D.glsl:1`、`P:shaders/program/shaders1/common/atmosphere/projection.glsl:1-2`、`P:shaders/program/shaders2/common/taa.glsl:1-2`、`P:shaders/program/shaders2/common/aces/aces.glsl:1-2`）。沿用批次二索引结论：**保留所有权利**（`INDEX-batch2.md:23`）。
- 版本自述（`P:changelogs.txt:1` 写作 “2..0.8”）：Lab PBR metal/emissive 修复（`:18,36`）、sunlight into SH 重做（`:32`）、云影默认关（`:34`）、低配地形反射修复（`:49`）、TAA 拖影修复（`:6`）、云/雾/光性能改进（`:14`）。
- 管线：**全延迟**。GBuffer 只有 colortex9（RGBA32UI：albedo/specular/八面体法线/id+lightmap，`P:program/shaders0/gbuffers0.glsl:86-87,171-174`），延迟端解包 `P:program/shaders1/struct.glsl:12-32,47-55`。pass 映射：deferred0-7=light0..light5、composite0=light6（体积水雾/光/雾）、composite1=light7（主光照+反射/折射/雾）、composite10-14=camera0..4、final=camera5（各 `P:shaders/world0/*.fsh:12`）。
- 设置组织与 Astra 一致：选项宏在 `P:shaders/lib/settings/{terrain,atmosphere,light,camera}.glsl`，screen/slider/profile 在 `P:shaders/shaders.properties:96-146`。
- 本副本事实：`P:program/buffers.glsl:61-103` 的 colortex 格式声明整块被块注释包裹（`:62-78` 仍是缓冲布局的唯一文档），`:48-49,:53-59` 为激活常量；下文引用按“注释即文档”。

## ② 架构特性清单（按子系统）

**GBuffer/管线**：单张 32 位整数 GBuffer `P:program/shaders0/gbuffers0.glsl:171-174`（packUnorm4x8×2 + encode_unit_vector + id/lightmap）；blend/alphaTest 全关 `P:shaders.properties:70-93`；阴影 pass 复用 gbuffers1 写 colortex0/1（含 dFdx 面积比焦散）`P:program/shaders0/gbuffers1.glsl:60-62,67-79,99-104`；雨/附魔 gbuffers2→colortex14 `P:program/shaders0/gbuffers2.glsl:48-49,56-62`；程序熔断 `P:shaders.properties:171-182`；打包库 `P:lib/encode.glsl:1-65`。

**大气**：物理散射 Chapman+Schueler `P:program/shaders1/common/atmosphere/atmosphere.glsl:31-47,49-62,64-115,133-168`；球面 3×2 tile 投影（Ymir/RRe36 致谢）`P:program/shaders1/common/atmosphere/projection.glsl:1-2,4-24,26-55`；每帧只更左上 tile、16 步 `P:program/shaders1/light0.glsl:22-42`；太阳/月/行星/星合成 `P:program/shaders1/light7.glsl:41-91`；大气常量 `P:program/shaders1/struct.glsl:282-325`。

**云/体积**：3D 云密度（voronoi 天气图+perlin）`P:program/shaders1/common/volumetric/clouds_3D.glsl:21-61`、raymarch `:79-174`；2D 平面云 `P:program/shaders1/common/volumetric/clouds_2D.glsl:1-32,53-122`；云时域（屏幕速度+深度指数权重，上限 0.95）`P:program/shaders1/light1.glsl:93-112`、天空投影云 `:118-130`；云影图 1024/500 `P:program/shaders1/struct.glsl:449-451`，写 colortex15.y `P:program/shaders1/light3.glsl:25-70,102-104`；体积光/雾/水雾以 VL_LOD=sqrt(0.15) 写 colortex3/4/5 `P:program/shaders1/light6.glsl:46-112`，composite1 4-tap 深度加权滤波合成 `P:program/shaders1/light7.glsl:121-151,207`；H-G 三相 `P:program/shaders1/common/volumetric/volumetric_fog.glsl:37-46`；体积阴影复用 shadowtex `P:program/shaders1/common/volumetric/volumetric_shadow.glsl:11-61`。

**光照/阴影/AO/GI**：Hammon 漫反射 `P:lib/brdf.glsl:104-124`、GGX 球面积分近似 `:126-156`、相关 G2 `:78-83`、Fresnel 三分支 `:53-65`；SH9 顶点 12 步锥/球积分 `P:program/shaders1/common/indirect/skylight.glsl:1-23,38-84`、片元重建 `:86-95`；扭曲 `P:lib/distortion.glsl:8-21`；PCSS blocker search `P:program/shaders1/common/shadow/pcss.glsl:1-25`；彩色阴影+焦散 `P:program/shaders1/common/shadow/shadow.glsl:4-25,27-68`；屏幕空间接触阴影 `P:program/shaders1/common/shadow/contact.glsl:1-40`（diffuse 内对手/基础材质跳过 `P:program/shaders1/common/diffuse.glsl:98-99`）；SSAO/RTAO `P:program/shaders1/common/indirect/ao.glsl:1-35,39-67`；RSM GI `P:program/shaders1/common/indirect/rsm.glsl:13-84`；à-trous 3×3 `P:program/shaders1/common/indirect/filter.glsl:6-42`；间接光时域 `P:program/shaders1/light3.glsl:89-100`；自发光/方块光/手持光启发式 `P:program/shaders1/common/diffuse.glsl:4-28,30-48,61,106`。

**水体（重点）**：解析波（alt_ext 出处）`P:program/shaders0/common/water_normal.glsl:1-2,5-36`、视差 `:39-55`、有限差分+距离衰减 `:57-87`；POM `P:program/shaders0/common/parallax.glsl:10-45`；光学常数表 `P:program/shaders1/struct.glsl:57-81`、金属 n/k `:83-107`；2 样本 VNDF SSR+miss 回退 `P:program/shaders1/common/specular/reflection.glsl:62-119`、步进 `P:program/shaders1/common/specular/raytrace.glsl:1-43`；折射深度二次校验 `P:program/shaders1/light7.glsl:93-117`；水雾 `P:program/shaders1/common/volumetric/volumetric_waterfog.glsl:1-63`；水色四预设 `P:program/shaders1/struct.glsl:538-604`；雨洼 `P:program/shaders1/common/specular/puddle.glsl:1-21`。

**后处理**：曝光=中心 mip 单采+1 像素历史+双速度 `P:program/shaders2/camera0.glsl:7-26,45-59`、参数 `P:program/shaders2/struct.glsl:51-73`；TAA=SMAA 滤波历史+RGB AABB+3×3 最近深度速度 `P:program/shaders2/common/taa.glsl:4-32,62-135`，camera1 合并 `P:program/shaders2/camera1.glsl:11-19`，抖动 CPU 预计算 `P:shaders/shaders.properties:56-63`；运动模糊 `P:program/shaders2/camera2.glsl:16-38`；Bloom=mip 链瓦片 `P:program/shaders2/camera3.glsl:1,13-21`、`P:program/shaders2/common/bloom.glsl:1-39,40-93`，合成 `P:program/shaders2/camera4.glsl:64-66`；DoF 40 tap `P:program/shaders2/common/dof.glsl:45-89`；六种 tonemap（含 ACES RRT+ODT）`P:program/shaders2/common/tonemap.glsl:1-97`、`P:program/shaders2/camera4.glsl:20-36`、`P:program/shaders2/common/aces/aces.glsl:1-18`；调色 `P:program/shaders2/common/color_correction.glsl:1-48`；final 风格件 `P:program/shaders2/camera5.glsl:19-44,84-111,113-146,148-161`。

**工具库**：黄金角盘/锥采样、gauss `P:lib/common.glsl:5-38`、bicubic `:84-122`；blue_noise（frame_16 旋转）/voronoi（depthtex2=voronoi.png）/perlin_fbm `P:lib/noise.glsl:27-36,48-60`；色域工具 `P:lib/color.glsl:30-32,46-68`；深度/速度 `P:lib/position.glsl:22-39`；宏与 pow 族 `P:lib/constant.glsl:1-42`。

## ③ 可借鉴点（15 条）

1. **球面“天空+云”环境缓存、稀疏 tile 帧更新**：3×2 tile 投影，每帧只更新左上 tile，反射端同一投影反查。
   P: `program/shaders1/common/atmosphere/projection.glsl:4-24,26-55`；`program/shaders1/light0.glsl:22-42`；`program/shaders1/light1.glsl:118-130`；`program/shaders1/common/specular/reflection.glsl:30-50`
   A: `lib/sky_reflection_cache.glsl:9-30`；`lib/sky_directional.glsl:12-25`；`lib/sky_sh9.glsl:47-51,69-80`
   工作量：中（Astra 已有缓存，缺“云行 + 粗糙度分级”）。
2. **粗糙反射：2 样本 GGXVNDF + SSR miss 回退环境**：`steps1=2u` 重要性采样半矢，命中取场景、miss 取天空缓存；每样本乘相关 G2/Fresnel 后平均；低配=完美镜面+一次环境采样。
   P: `program/shaders1/common/specular/reflection.glsl:62-119`（VNDF `:82-84`、回退 `:102-106`、低配 `:113-120`）；`program/shaders1/common/specular/raytrace.glsl:1-43`
   A: `global/water/raytrace.glsl:58-124`；`program/water.glsl:174-187,264-298,424`
   工作量：中。**与批次一重复**：SSR miss 回退环境（SUMMARY ②-2，6 包印证）；增量在“2 样本 VNDF 同时服务粗糙反射”。
3. **材质级光学常数覆盖表**：ID→水 0.021/0.20/1.33283、冰 0.018/0.22/1.309、玻璃 0.042/0.52/1.517、黏液 0.036/0.44/1.484；金属走 n/k 表。
   P: `program/shaders1/struct.glsl:57-81,83-107`；展示 `program/shaders0/gbuffers0.glsl:95-97,171-174`
   A: `program/water.glsl:225-231,257`；`lib/wet_material.glsl:14-21`
   工作量：低。**坑**：`:83-107` 金属分支自第二项起条件全为 `==231`（`:89,92,95,98,101,104`），除 230/231 均不可达，不可照抄。
4. **零纹理解析波浪 + 水面视差**：sin/exp2 相位波 + 两次有限差分法线 + 切线空间步进视差；细节按 `exp2(-dist*0.01)` 衰减抗闪。
   P: `program/shaders0/common/water_normal.glsl:5-36,39-55,57-87`
   A: `global/water/caustics.glsl:6-12,27-37`；`global/water/surface.glsl:317-319,362-378`
   工作量：中。**与批次一重复**：波浪/焦散（solas-shader 报告）。**许可风险**：函数来自 Shadertoy（`P:.../water_normal.glsl:1-2`），只能重写。
5. **LabPBR 全通道 GPU 打包/解包**：一张 RGBA32UI 存 albedo/spec/法线/id+lightmap；解包 `roughness=1-spec.x, f0=spec.y, porosity=spec.z, emissive=spec.w`。
   P: `program/shaders0/gbuffers0.glsl:171-174`；`program/shaders1/struct.glsl:12-32,47-55`
   A: `program/lit.fsh:287-310`；`lib/surface_buffers.glsl:14-25`
   工作量：低。**与批次一重复**：LabPBR 通道消费（fastpbr 报告 `:18`）。
6. **雨洼孔隙度驱动 roughness/f0**：噪声×光照×朝上法线×孔隙度反比×wetness；孔隙度<64.5/255 时 `roughness→0, f0→0.20`。
   P: `program/shaders1/common/specular/puddle.glsl:11-19`；调用 `program/shaders1/light5.glsl:36`、`program/shaders1/light7.glsl:179`
   A: `lib/wet_material.glsl:14-21`（自述艺术参数 `:15`）
   工作量：低。**与批次一重复**：孔隙度/水洼 7 包（fastpbr/bsl/complementary-*/solas/shrimple/hysteria/mellow）。
7. **云影图：单通道、与云同源、多消费者复用**：1024/500 世界空间写 colortex15.y，地形阴影/体积雾/水雾/接触阴影共用同一采样。
   P: `program/shaders1/light3.glsl:25-70,102-104`；消费 `program/shaders1/common/diffuse.glsl:50-58,100,108`、`program/shaders1/light6.glsl:19-27`、`program/shaders1/common/volumetric/volumetric_shadow.glsl:60`
   A: `global/atmosphere/cloud_shadow_cache.glsl:7-38`；`program/cloud_shadow_cache.fsh`
   工作量：低-中。**与批次一重复**：云影与云密度同源（BSL/Solas/Photon 3 包，bsl 报告 `:97-100`）。
8. **多重散射廉价近似**：内层 8 次循环三路 H-G，系数 `a*=0.6,b*=0.4,c*=0.8` 逐次衰减；powder `1-0.97*exp2(-density*24)`。
   P: `program/shaders1/common/volumetric/clouds_3D.glsl:126-149`；`.../clouds_2D.glsl:82-101`；`.../volumetric_fog.glsl:101-121`；`.../volumetric_light.glsl:51-70`
   A: `global/atmosphere/volume_fog.glsl:70-76,86-106`；`lib/volume_integral.glsl:33-56`
   工作量：中。**与批次一重复**：体积云多重散射（kappa `:86`、hysteria `:53`）。
9. **RSM GI + à-trous 3×3 + 时域累积**：从 shadowtex0/1 与 shadowcolor0/1 取深度/反照率/法线/光图，黄金角旋转 + 光图一致性 mask，3×3 双边滤波后按屏幕速度累积。
   P: `program/shaders1/common/indirect/rsm.glsl:13-84`；调用 `program/shaders1/light2.glsl:32-35`；滤波 `.../filter.glsl:6-42`、`program/shaders1/light4.glsl:24-32`；时域 `program/shaders1/light3.glsl:89-100`
   A: 无对应（Astra 间接=SH9+方块光，见 `global/lighting/diffuse.glsl`）
   工作量：高。**与批次一重复**：RSM（ebin 报告 `:74,104,146` 已判“需重排影图输出”）。
10. **屏幕空间接触阴影**：视空间 8 步深度步进，相对深度阈值 0.05、strength 1.0，草方块特调（0.65/0.05）。
    P: `program/shaders1/common/shadow/contact.glsl:1-40`；参数 `program/shaders1/struct.glsl:530-533`
    A: `global/lighting/shadowmap.glsl:84-137`；`global/lighting/diffuse.glsl:254-286`
    工作量：中。**与批次一重复**：接触阴影 4 包（bliss/shrimple/kappa/nostalgia）。
11. **TAA 的 SMAA 滤波历史重采样**：历史 5-tap SMAA 滤波；3×3 AABB（5 点 rounded 包络）裁剪；速度由 `closest_fragment_3x3(depthtex0)` 重投影；投影权重。
    P: `program/shaders2/common/taa.glsl:4-32,62-69,86-135`；`program/shaders2/camera1.glsl:11-19`
    A: `program/taa_resolve.fsh:30-51,100-133`
    工作量：低-中。**与批次一重复**：SMAA/时域（mellow 报告 `:24`、solas 报告 `:57`）。**坑**：`taa.glsl:49-57` 缺花括号导致 `position.z` 每行无条件写入，速度选择失效，不可照抄。
12. **自动曝光：相机参数模式 + 中心 mip 测光**：`texture2_lod(colortex7, vec2(0.5), log2(max2(texel)))` 单点测光 + 1 像素历史 + 双速度；另有光圈/ISO/快门公式。
    P: `program/shaders2/camera0.glsl:7-26,45-51`；参数 `program/shaders2/struct.glsl:51-73`
    A: `global/post/exposure.glsl:82-101,105-143`
    工作量：低。**与批次一重复**：复杂自动曝光 5 包（bliss/bsl/photon/nostalgia 等）。
13. **Bloom：mip 链瓦片采样**：把开 mipmap 的颜色缓冲当金字塔，逐 LOD“瓦片偏移+3×3 高斯”，按 `1/(i+1.2)` 加权，6 档合成；与曝光耦合、水下单独强度。
    P: `program/shaders2/camera3.glsl:1,13-21`；`program/shaders2/common/bloom.glsl:1-39,40-93`；合成 `program/shaders2/camera4.glsl:64-66`
    A: `global/post/bloom.glsl:5-15,41-47`（capture 0.25x + 4 mip；自标 Refrax 派生、REWRITE REQUIRED）
    工作量：低。**与批次一重复**：bloom mip/瓦片（ebin 报告 `:102`、makeup 报告 `:54,163`）。
14. **RGBE8 共享指数编码用于 HDR 后处理缓冲**：`encodeRGBE8` 压进 RGBA8（尾数 128/255、指数+127），pass 间传递省带宽。
    P: `lib/encode.glsl:18-31`；使用 `program/shaders1/light5.glsl:42`、`program/shaders1/light7.glsl:97,191`、`program/shaders1/common/specular/reflection.glsl:97`
    A: 现状为浮点缓冲（`global/post/bloom.glsl:26` 注明 colortex0=R11F_G11F_B10F），无共享指数编码
    工作量：低（纯函数）+ 量化验证。
15. **半分辨率 LOD 常量体系与边界判定**：ATMOSPHERE_LOD=sqrt(0.25)、CLOUDS_LOD=sqrt(3.0)、VL_LOD=sqrt(0.15)、INDIRECT_LOD=2.5；`saturate(coord)==coord` 判有效区，无效区写恒等值（散射 0/透射 1）防双线性与时域串色。
    P: `lib/settings/atmosphere.glsl:3-6`；`lib/settings/light.glsl:1`；`program/shaders1/light2.glsl:19-24`；`program/shaders1/light6.glsl:47-50`；`program/shaders1/light1.glsl:79-85`
    A: `lib/settings.glsl:137-139`；`global/atmosphere/volume_fog.glsl:33-40`
    工作量：低。**与批次一重复**：半分辨率/棋盘（SUMMARY ②-3）。

## ④ Astra 已有实现对照（含“哪边更省、误差来源”）

| 主题 | Voyager（P:） | Astra（A:） | 哪边更省 / 误差来源 |
|---|---|---|---|
| 天空/云环境缓存 | 球面投影+每帧稀疏 tile（`light0.glsl:22-42`、`projection.glsl:4-24`） | 固定 258×128 缓存+SH9（`lib/sky_reflection_cache.glsl:6-30`、`lib/sky_directional.glsl:12-25`） | **A 更省**（固定小缓存、无每帧散射更新；V 缓存区随 viewport 与 CAPTURE_LOD 缩放且每帧仍要算该区 16 步）。误差：A 查询固定 mip0（`sky_reflection_cache.glsl:29`），入射辐射无粗糙度分级，粗糙度只靠方向抬升+向环境色收敛（`global/dimension/overworld.glsl:47-60`）；V 缓存按 RGBA16F 文档并以 `saturate_16` 钳位（`program/buffers.glsl:62-64`、`light0.glsl:41-42`），太阳附近动态范围受限。 |
| 水面反射 | 2 样本 VNDF SSR+miss 回退+低配镜面（`specular/reflection.glsl:62-119`） | 两阶段 SSR+置信度/厚度/范围淡出（`global/water/raytrace.glsl:58-124`），合成 `program/water.glsl:174-187,424` | **V 更省**（2 样本、64 步上限、低配 1 采样），**A 更准**。误差：V 单次深度命中无厚度（`raytrace.glsl:29`），粗糙反射靠 2 样本平均→闪烁，靠 TAA 掩；反射色经 RGBE8 存储（`reflection.glsl:97`）有 8 位尾数量化。 |
| 水体光学常数 | ID 覆盖表（`struct.glsl:57-81`）+ 金属 n/k（`:83-107`） | 固定 0.025 f0+pow5 Fresnel（`program/water.glsl:225-231`）；润湿为艺术参数（`lib/wet_material.glsl:14-21`） | 双方都省，误差不同：V 覆盖资源包 PBR（一致但失忠实），金属表有 `==231` 缺陷；A 无法表达玻璃/黏液/金属差异。 |
| 体积云/雾积分 | 嵌套三路散射+系数衰减（`clouds_3D.glsl:126-149`、`volumetric_fog.glsl:101-121`） | 闭式单散射分段积分+分段合成（`lib/volume_integral.glsl:33-56,67-78`、`volume_fog.glsl:86-106`） | **A 更省**（解析积分无内循环）；**V 更厚**（多散射近似）。误差：A 无多重散射，厚云/雾偏平；V 系数衰减非能量守恒。 |
| 时域（TAA） | SMAA 滤波历史+RGB AABB+3×3 最近深度速度（`taa.glsl:4-32,86-135`） | 逐 contributor 校验双线性+YCoCg 统计裁剪+反应式掩码（`program/taa_resolve.fsh:30-51,100-133`） | **V 更省**（历史 5 tap，但速度源有缺陷 `taa.glsl:49-57`）；**A 更稳**（物体运动矢量另行提供 `taa_resolve.fsh:79-82`）。误差：V 无物体运动矢量，快速旋转/遮挡边界错。 |
| 自动曝光 | 中心 1 次 mip+1 像素历史+双速度（`camera0.glsl:7-26`） | 64 tap 加权网格+1×1 历史+log 双速率+有界（`global/post/exposure.glsl:82-101,105-143`） | **V 更省**；**A 更稳**（NaN 兜底/上下限）。误差：V 只测中心（主体偏心即失准），历史与运动模糊共用 colortex8.w；A 成本 64 texelFetch。 |
| 云影 | 1024/500 单通道，地形/雾/水共用（`light3.glsl:25-70,102-104`） | 512 范围/2 块纹素+边缘回真实场（`cloud_shadow_cache.glsl:7-38`） | **V 的复用最省**（一次采样服务四类）；**A 更精**（不 clamp 世界查询）。误差：V 固定 500 距离，远云影丢失。 |
| 大气 | 逐像素物理散射 LUT（16 步）+Chapman（`atmosphere.glsl:31-62,64-115`） | 解析调色板+SH9+四时段色板（`lib/sky_sh9.glsl:47-51,69-80`、`lib/color_controls.glsl:55-64`） | **V 像素成本省**（1 次 LUT 采样）但每帧维护 LUT；**A 无 LUT 更新成本**但方向性靠 SH9。误差：V LUT 为 RGBA16F 文档+钳位（同上），太阳/地平线动态受限；A 非光谱散射，需手调四配色。 |

## ⑤ 许可可行性与“重写 vs 抄”边界

- **结论**：包内无许可文件，按索引为“保留所有权利”→ **只读思路、独立重写**；不得逐行翻译、改名、搬函数体/常数表/注释结构。
- **可安全借鉴的思想层**：③ 全部 15 条（稀疏 tile 缓存、2 样本 VNDF、孔隙度映射、单云影缓存多消费、mip bloom、单像素曝光历史、SMAA 滤波历史、RGBE8、半分辨率边界判定）。
- **不能搬的具体物**：解析波函数（Shadertoy 来源，`P:water_normal.glsl:1-2`，许可未知，双风险）；金属 n/k 数值（应从公开光学数据自行查证）；球面投影（V 自述获 Ymir/RRe36 授权 `projection.glsl:1-2`，不随包转让）；ACES RRT/ODT 代码（源头另有许可，Astra 已有自有 vendor 链，见 `A:lib/tonemap.glsl:4-17`）。
- **落地流程**：沿用 Astra 现行口径——文件头“idea only/原实现”+ THIRD-PARTY.md 台账（先例 `A:lib/tonemap.glsl:4-17`、`A:lib/wet_material.glsl:4-6`）。

## ⑥ Top5 与暂缓项（“PBR 材质与水面的折中”结论）

**Top5**：①环境反射粗糙度分级（mip+环境 BRDF；P `light0.glsl:22-42`、`reflection.glsl:63-64,108-111`；A `lib/sky_reflection_cache.glsl:29` 固定 mip0；低-中）；②粗糙反射 2 样本 GGXVNDF+miss 回退（P `reflection.glsl:82-119`；A `global/water/raytrace.glsl:120`+`program/water.glsl:281-298`；中）；③LabPBR 孔隙度落地（P `puddle.glsl:11-19`；A `lib/wet_material.glsl:15` 自述艺术参数；低）；④云影缓存参数化+多消费者统一（P `light3.glsl:25-70`、`light6.glsl:19-27`；A `cloud_shadow_cache.glsl:7-38`；低）；⑤曝光相机模式/中心测光档（P `camera0.glsl:45-51`、`struct.glsl:51-73`；A `global/post/exposure.glsl:62-76`；低）。

**暂缓**：完整 ACES RRT+ODT（`P:aces/*`，A 已有 4 算子，收益仅风格）；3D 体积云+行星大气全模型（`clouds_3D.glsl`，工程量大）；相机风格件（DoF/运动模糊/鱼眼/宽银幕/暗角，批次一多包重复）；RSM GI/接触阴影/PCSS（批次一重复，RSM 需重排影图）；解析波浪（许可双风险+与 Solas 链重复）。

**折中结论（牺牲的物理正确性 × 换取 × 落点行号）**
1. 水面反射是 2 样本蒙特卡洛、无环境预滤波（`reflection.glsl:63-64,82-119`，噪声化步长 `raytrace.glsl:10`）→ 换速度，代价噪点/闪烁靠 TAA 掩。
2. 材料常数按 ID 覆盖 LabPBR（`struct.glsl:57-81`）；非金属一律 `f0_to_ior(albedo)`（`brdf.glsl:49-64`）、金属仅 2 种可用（`struct.glsl:89-104` 重复条件）、能量用 `albedo*=1-f0`（`diffuse.glsl:85`）→ 换资源包稳定性，代价参数不忠实。
3. 多次散射用三次经验衰减冒充（`clouds_3D.glsl:130-149`、`volumetric_fog.glsl:101-121`，`a*=0.6,b*=0.4,c*=0.8`）→ 换体积感，非能量守恒。
4. 低配直接放弃 SSR（`reflection.glsl:113-120`）→ 只有完美镜面+Fresnel。
5. 测光只信画面中心一次 mip 采样（`camera0.glsl:13-18`）→ 换掉全画面统计，主体偏心时失准。
6. 云/间接光时域为固定权重+屏幕速度（`light1.glsl:99-112`、`light3.glsl:95-98`）→ 无状态有效性/反应式拒绝，遮挡突变留拖影。

## 附录：成稿后行号自抽查（12 条，全部通过）

成稿后重新打开源文件用 `grep -n` 核对行号原文（`$P=reference_shaderpacks/voyager-shader-2.0/shaders`，工作目录同报告头）。实测：

1. `P:.../specular/reflection.glsl:63-64` → `63: const int steps0 = REFLECTION_QUALITY;`、`64: const uint steps1 = 2u;` 一致。
2. `P:.../light3.glsl:102-104` → `102: buffers1.x = depth0;`、`103: buffers1.y = clouds_shadowmap(...)`、`104: buffers1.zw = texture2(colortex15,...)` 一致。
3. `P:.../struct.glsl:57-60` → `57: if(ID == 2){`、`58: s.roughness = 0.021;`、`60: s.ior = 1.33283;` 一致。
4. `P:.../struct.glsl:83-107` → `83: ==230`，`86/89/92/95/98/101/104: ==231` 重复条件实证，一致。
5. `P:.../specular/puddle.glsl:11-19` → `11: float puddle = saturate(noise / 1.2) * lightmap;`、`17: if(porosity < 64.5/255.0){`、`18-19: roughness/f0 mix` 一致。
6. `P:.../camera0.glsl:13-18` → `13: float lod = log2(max2(texel));`、`15: texture2_lod(colortex7, vec2(0.5), lod)`、`18: texture2(colortex8, vec2(0.5)).w` 一致。
7. `P:.../light0.glsl:22,41-42` → `22: vec2 tile = (min(...)*exp2(-CAPTURE_LOD))*vec2(3.0,2.0);`、`41-42: saturate_16` 一致。
8. `P:.../projection.glsl:50-51` → `50: vec2 project_sphere(vec3 dir) {`、`51: return project_sphere(dir, CAPTURE_LOD);` 一致。
9. `P:shaders/shaders.properties:50,57,60` → `50: uniform.int.frame_8=...`、`57: variable.float.frame_x=...`、`60: uniform.vec2.jitter=...` 一致。
10. `P:.../water_normal.glsl:1-2` → `1: //Wave water from alt_ext`、`2: //https://www.shadertoy.com/view/4dBcRD` 一致。
11. `A:lib/sky_reflection_cache.glsl:29` → `29: return textureLod(colortex11, vec2(u, v), 0.0).rgb;` 一致（固定 mip0 实证）。
12. `A:global/water/raytrace.glsl:15-22` → 三档 `BUDGET=16/40/30`、`REFINE=4/8/6` 一致；另核 `A:program/water.glsl:227,230`（`water_fresnel` 与 `0.025+0.975*pow5`）、`A:lib/wet_material.glsl:15`、`A:global/post/exposure.glsl:82,105,142`、`A:global/dimension/overworld.glsl:47,50`、`A:program/taa_resolve.fsh:79-82` 均与正文一致。

抽查后按实测修正的表述（不影响行号）：④ 段删去对 V 缓存区尺寸的估算（只留 `light0.glsl:22` 公式出处），并把两处 “`saturate_16` 量化”改为“RGBA16F 文档格式+钳位导致动态范围受限”（依据 `program/buffers.glsl:62-64`、`light0.glsl:41-42`）。
