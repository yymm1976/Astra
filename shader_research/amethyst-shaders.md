# Amethyst Shaders 2.4 → Astra 光影可借鉴点调研报告

- 生成方式：子代理（worker）只读调研；未运行游戏、未改参考包，仅新建本文件。
- 包版本：`amethyst-shaders` 2.4（作者 gamerbenyt，下载量 434,246，批次二索引）。调研日期 2026-10-02。
- 参考根：`reference_shaderpacks/amethyst-shaders/`。引用约定：`P:` = 该包内相对路径；`A:` = `Astra/shaders/` 相对路径。**所有行号均为本次实际读取所得**，自抽查见附录。
- 实测规模：`shaders/` 348 文件，其中程序源码 336 个、18,447 行；整包磁盘 1,643 KB（批次二索引记 0.45MB，与解包实测不符，见备注）。3 张 PNG（noise/cloud-water/cucumber）未逐一读取。
- 血缘（关键）：`P:shaderFile_Versions.txt:1-2` 为 `ComplementaryReimagined_r5.5.1.zip`、`ComplementaryUnbound_r5.5.1.zip`；`P:License.txt:1` = "Complementary License Agreement 1.5"。本包是 **Complementary Reimagined r5.5.1 的 Modified Pack**，非独立实现——故 ③ 段大量标注"与批次一重复"（批次一 `complementary-reimagined.md` 已调研同一上游的更新版本）。

## ① 概览

- 组织：`shaders/program/*.glsl` 是唯一实体源码（模板 `P:shaders/program/template.glsl:1-42`）；`world0/`、`world1/`、`world-1/` 各放薄壳，仅 `#version` + 维度/程序宏 + include（`P:shaders/world0/deferred1.fsh:1-6`、`P:shaders/world0/shadowcomp.csh:1-6`）。同一程序 3 份薄壳，改实体只改 `program/`。
- 卖点档位：彩光体素分辨率 128/192/256/384/512/768/1024，POTATO~MEDIUM 档为 0（`P:shaders/shaders.properties:2-8`）；源文件默认 `COLORED_LIGHTING 0`（`P:shaders/lib/common.glsl:32`）。
- 门控：需 Iris 自定义图像、`SHADOW_QUALITY > -1`、非 Mac、非 DH（`P:shaders/lib/common.glsl:32-49`）；Mac 强制置 0（`P:shaders/shaders.properties:69-71`）。
- 许可：`P:License.txt` 91 行，唯一例外文件 `P:shaders/lib/materials/materialMethods/anisotropicFiltering.glsl:2`（MPL-2.0）。详见 ⑤。
- 非借鉴观察：fork 自加选项 `AMETHYST_COOL`（`P:shaders/lib/common.glsl:18`）只在声明与语言文件（`P:shaders/lang/en_US.lang:191-199`）出现，无代码分支引用，2.4 里是惰性选项。根目录 `shaderFile_*.placebo`（122 B 文本，`P:shaderFile_A.placebo:1`）是防误放 zip 的占位，与渲染无关。

## ② 架构特性清单（按子系统，全部 `P:文件:行号`）

**1. 程序组织与设置**：三世界薄壳 + `program/` 实体（`P:shaders/world0/deferred1.fsh:1-6`、`P:shaders/program/template.glsl:1-42`）。208 行 properties：8 档 profile（`:2-8`）、screen 菜单（`:11-62`）、程序开关（`:94-116`）、image 尺寸表（`:135-169`）、自定义纹理（`:176-179`）、属性侧 `smooth()` 变量（`:181-208`）。缓冲格式与 clear 标志集中（`P:shaders/lib/pipelineSettings.glsl:1-31`）。

**2. 彩光体素（重点）**：体积尺寸与有效距离 `P:shaders/lib/misc/voxelization.glsl:4-10`（`(N, N*0.5, N)`，`effectiveACLdistance = min(N, shadowDistance*2)`）；越界判定 `:20-28`；消费采样（奇偶帧读不同副本）`:30-80`；方块→ID 二分表 `:82-298`（0/1 保留，2..84 光源，200+ 染色，254/255）；采集写入口 `:300-324`（跳过 `mat<10000`、`mat%4==1`、水 32000）。传播 compute `P:shaders/program/shadowcomp.glsl`：`local_size 8³` 与各档 workGroups `:14-29`；7 点平均除 7.2 `:49-60`；背后早退 `:11-12, 72-89`；半速率双缓冲+位移重投影 `:94-118`；染色乘子与自发光取 max `:120-128`。光色表 `P:shaders/lib/colors/blocklightColors.glsl:1, 11-16, 18-177`，染色表 `:179-219`。消费：主光照 `P:shaders/lib/lighting/mainLighting.glsl:365-413`（alpha 额外光 `:386-387`、饱和度 `:395-397`、距离 fade `:399-412`）、手持光 `:415-461`、彩光雾 `P:shaders/lib/atmospherics/fog/coloredLightFog.glsl:1-51`。采集端 image 声明 `P:shaders/program/shadow.glsl:236-242`、include `:253-259`、每 quad 单顶点写 `:300-307`。

**3. 阴影/彩色阴影/光柱**：阴影采样+彩色阴影 `P:shaders/lib/lighting/shadowSampling.glsl:10-24`；光柱色独立缓冲 `P:shaders/program/shadow.glsl:161, 187-195`；体积光彩色采样 `P:shaders/lib/atmospherics/volumetricLight.glsl:176-189, 240-262`；水下焦散在 shadow pass 内（`P:shaders/program/shadow.glsl:96-141`，批次一已覆盖）。

**4. 大气**：双云模型按 define 选/叠加 `P:shaders/lib/atmospherics/clouds/mainClouds.glsl:37-42, 44-70`、`P:shaders/lib/common.glsl:517-527`、开关 `P:shaders/shaders.properties:33-36`；星空/极光/夜星云/彩虹/末地星与光柱见 `P:shaders/lib/atmospherics/*.glsl`；下界风暴层 `netherStorm.glsl`（批次一已覆盖）。

**5. 后处理**：TAA（Reprojection、邻域 AABB clamp、Catmull-Rom 可选）`P:shaders/lib/antialiasing/taa.glsl:1-176`；FXAA 独立 pass `P:shaders/program/composite7.glsl` + `P:shaders/shaders.properties:107-111`；世界模糊/DOF、镜头光斑、色差、锐化、运动模糊（批次一已覆盖）。

**6. 材质/IPBR**：`P:shaders/lib/materials/materialHandling/*`、`materialMethods/*`（生成法线、涂层、POM、反射、折射、摇摆、连接玻璃）、`specificMaterials/*`。占用体素被材质侧二次读取：`materialMethods/connectedGlass.glsl:64,79,91,95,103`、`wavingBlocks.glsl:137-138`、`specificMaterials/translucents/netherPortal.glsl:61`、`specificMaterials/others/endPortalEffect.glsl:83`。

**7. 维度与调试**：world-1/world1 物理隔离；下界群系权重属性化（`P:shaders/shaders.properties:201-207`）。调试件 `P:shaders/lib/misc/showLightLevels.glsl`、`colorCodedPrograms.glsl`、`P:shaders/lib/textRendering/textRenderer.glsl:1-329` 与 6 个 `error_*.glsl`。

## ③ 可借鉴点（14 条；技术 / `P:` / `A:` / 工作量）

> "与批次一重复" = 批次一报告已提取同方向（同一上游），保留作"同方向多次出现"的收敛证据。

**1. 体素光传播的时域摊销（半速率 ping-pong + 相机位移重投影）**
- 技术：双缓冲按帧奇偶各更新一半体积，另一半用 `previousPos = pos - (floor(previousCameraPosition) - floor(cameraPosition))` 搬上帧场址，靠 7 点平均多帧迭代收敛，代替同帧多趟。
- `P:shaders/program/shadowcomp.glsl:99-118`、`:69-70`、`:49-60`。
- `A:program/nether_light.csh:1-8`（自述"有界同帧体积、八步扩散、无历史"）、`A:world-1/shadowcomp.csh:2` 与 `A:world-1/shadowcompA..H.csh:2`（`ASTRA_LIGHT_STEP 0..8` 九段）。
- 工作量：**中高**。这是"主世界彩光低成本"的核心：下界九段链路搬去主世界成本约 9 倍；P 每帧 1 次 dispatch、只算半体积。代价是移动光源/破坏方块后的收敛滞后与重投影残影。

**2. 相机背后体积整块跳过**
- 技术：`dot(normalize(cell-0.5), 相机前向) < 0` 的格只做历史复制、不做平均；仅开彩光雾时保留历史。
- `P:shaders/program/shadowcomp.glsl:11-12, 72-89`。`A:program/nether_light.csh:48-105`（全量，无方向剔除）。
- 工作量：**低**。

**3. 体积规模与有效距离档位化（含消费端距离回退）**
- 技术：`N ∈ {128..1024}`，体积 `(N, N/2, N)`；`effectiveACLdistance = min(N, shadowDistance*2)`；主光照按切比雪夫距离把彩光 fade 回普通 blocklight。
- `P:shaders/lib/misc/voxelization.glsl:4-10`、`P:shaders/shaders.properties:135-169`、`P:shaders/lib/lighting/mainLighting.glsl:399-412`。
- `A:lib/nether_voxel_grid.glsl:29-31`（固定 64³/±32）、`A:lib/nether_voxel_grid.glsl:18-27`（注释列出必须同步的四处字面量）、`A:global/dimension/nether.glsl:172-175`。
- 工作量：**中**。标注：**与批次一重复**（`complementary-reimagined.md` §2.7 已记七档与 Mac 禁用）。

**4. 占用图用 8 位而非 32 位**
- 技术：`voxel_img` 用 `r8ui`（1 B/格），把空气/普通/光源/染色压进 8 位（0/1、2..84、≥200），`imageStore` 直写而非位域原子聚合。
- `P:shaders/shaders.properties:142`、`P:shaders/lib/misc/voxelization.glsl:82-298`。
- `A:shaders.properties:693`（r32ui）、`A:program/shadow.vsh:42-52`（bit8 solid + bit0-7 species）。
- 工作量：**低**；Astra 的 12 物种 + solid 完全装得进 8 位，64³ 省 0.75 MiB（见 ④）。

**5. 每类光源"颜色即射程"规则 + alpha 附加光**
- 技术：光色不决定亮度而决定传播距离与相邻主色（`P:shaders/lib/colors/blocklightColors.glsl:19-24`）；每族不同量级（火系≈2、发光石/蛙明灯≈4、岩浆/传送门≈4-5、末地棒以"总值 12"为全表基准 `:32`）；`a > 0` = 无视亮度图额外发光（岩浆 0.8 `:46`、传送门 0.4 `:62`、蜡烛 0.004 `:61`）。
- `P:shaders/lib/colors/blocklightColors.glsl:11-16, 18-177`。
- `A:program/nether_light.csh:37-47`（12 类表）、`A:program/nether_light.csh:53-60`（自述单一 ×2.0 无法复现 per-kind radiance）、`A:global/dimension/nether_colored_light.glsl:9-12`。
- 工作量：**低**。

**6. 染色玻璃/冰作为体积滤色器（id ≥ 200 传播 tint）**
- 技术：染色玻璃写 `200 + 颜色索引`，传播循环对这类格 `light.rgb *= specialTintColor[i]`，色光穿过玻璃被染色，无需额外通道。
- `P:shaders/lib/colors/blocklightColors.glsl:179-219`、`P:shaders/lib/misc/voxelization.glsl:287`、`P:shaders/program/shadowcomp.glsl:120-124`。
- `A:program/shadow.fsh:50-58` + `A:global/lighting/shadowmap.glsl:120-127`（只有平面阴影染色），体积侧无 tint。
- 工作量：**低-中**，彩光观感性价比最高的一条。

**7. 占用体素图的材质侧二次利用（不新增 pass）**
- 技术：同一张体素图兼作局部方块语义图：连接玻璃判同族邻格、摇摆方块判遮挡、传送门/末地门读相邻格决定边缘特效。
- `P:shaders/lib/materials/materialMethods/connectedGlass.glsl:64,79,91,95,103`、`wavingBlocks.glsl:137-138`、`P:shaders/lib/materials/specificMaterials/translucents/netherPortal.glsl:61`、`others/endPortalEffect.glsl:83`。连接玻璃仅在无 Iris 连接纹理时启用（`P:shaders/lib/common.glsl:42-44`）。
- `A:program/shadow.vsh:57-83`（Astra 也写了 solid/species），但只有 `A:program/nether_light.csh:50` 在读。
- 工作量：**低-中**。

**8. 角落漏光修正放在消费端**
- 技术：数 6 个正交邻居里"实心/染色"数，`>= 3` 时把传播值按中心格 texel 夹紧 `min(volume, center*1.5)`，一次 6-texel 读取换掉更多传播迭代。
- `P:shaders/lib/misc/voxelization.glsl:37-57, 61-76`（法线偏移取 0.55 的理由见 `P:shaders/lib/lighting/mainLighting.glsl:373`）。
- `A:lib/nether_voxel_grid.glsl:51-58`（仅边界距离）、`A:global/dimension/nether_colored_light.glsl:16`。
- 工作量：**低**。

**9. 彩光饱和度滑块（彩光与单色 blocklight 做 mix，含手持光）**
- 技术：`specialLighting` 与 `blockLighting` 按 `COLORED_LIGHT_SATURATION * 0.01`（默认 105）mix，手持光色同样 mix。
- `P:shaders/lib/lighting/mainLighting.glsl:395-397, 434-437`、`P:shaders/lib/common.glsl:36`、`P:shaders/shaders.properties:62`。
- `A:lib/settings.glsl:53-58`（只有强度/抑制）。工作量：**低**。

**10. 彩光参与雾/体积（步长 8 + dither + 各向异性距离度量 + pow 压缩）**
- 技术：沿视线 8 格步长采样体素光，dither 抖动消条带；距离权重按体积各向异性补偿（y×2/3/4）；命中不透明物提前 break；`pow(sum/sampleCount, 0.25)` 压暗防过曝。
- `P:shaders/lib/atmospherics/fog/coloredLightFog.glsl:4-11, 22-34, 35-39, 50`。
- `A:global/dimension/nether_volume.glsl:22-57`（密度只来自 `blissNetherNoise`）；`astraLightSamplerA` 全仓仅出现于 `A:global/dimension/nether_colored_light.glsl:8,23` 与 `A:program/nether_light.csh:16`。
- 工作量：**中**。

**11. 光柱色独立 shadowcolor 缓冲（归一化+平方，复用 .a 存水面高度）**
- 技术：shadow pass 同写 `shadowcolor0`（透射染色）与 `shadowcolor1`（光柱色）：`color2.rgb = normalize(pow(color1.rgb,0.25))*0.5`（归一化压暗，避免与染色同强）；体积光 `*4.0` 后平方成"强而窄"响应；`color2.a` 编码水面高度供水下光柱门控。
- `P:shaders/program/shadow.glsl:161, 187-195`、`P:shaders/lib/atmospherics/volumetricLight.glsl:176-189, 252`。
- `A:global/water/light_shafts.glsl:71`（直接读 `shadowcolor0.gba`）、`A:lib/settings.glsl:519`；全仓无 `shadowcolor1` 读取。
- 工作量：**中**。

**12. 采集去重：每 quad 只一个顶点写体素**
- 技术：写入位置取方块中心（`gl_Vertex.xyz + at_midBlock/64`），同 quad 四顶点同格，故 `gl_VertexID % 4 == 0` 才写，写入降为 1/4。
- `P:shaders/program/shadow.glsl:300-307`。`A:program/shadow.vsh:57-83`（每顶点 `imageAtomicMax`，调用点 `:87-89`）。工作量：**低**。

**13. 水坑体素化（128² R8UI 深度图，仅 translucent 阶段写）**
- 技术：独立 128² `r8ui` 平面图，shadow pass 的 `TERRAIN_TRANSLUCENT` 阶段对非水表面写固定深度 10，`scenePos.y >= -3.5` 过滤；得到"水坑在哪、多深"的世界空间图，用于波纹/反光，而非逐方块湿感。
- `P:shaders/lib/misc/puddleVoxelization.glsl:1-35`、`P:shaders/shaders.properties:171-173`、`P:shaders/lib/common.glsl:508-511`。
- `A:lib/wet_material.glsl:7-21`（按方块类别的湿感参数）、`A:lib/rain_particles.glsl:10-19`（仅粒子过滤）。工作量：**中**。

**14. 属性侧 `smooth()` 预平滑的 uniform 与群系权重**
- 技术：把属性语言可算的量（雨强、洞穴判定、干/雨/雪群系、5 个下界群系、Pale Garden）预 `smooth()` 成防抖 uniform。
- `P:shaders/shaders.properties:181-208`。
- `A:shaders.properties:729-737`（Astra 已有同类预计算）、`A:lib/nether_fog_density.glsl:7-14`（群系权重现算，无时域平滑）。工作量：**低**。标注：**与批次一重复**（`complementary-reimagined.md` §2.7 末条）。

## ④ Astra 已有对应实现对照表

字节口径：`r8ui`=1 B/格、`r32ui`=4 B/格、`rgba16f`=8 B/格。

| 主题 | P | A | 哪边更省、误差来源 |
|---|---|---|---|
| 彩光体素范围 | 主世界+下界+末地共用一套（`P:shaders/lib/common.glsl:32-49`） | 仅下界且需 `NETHER_VOXEL_LIGHT`+`SHADOWS`（`A:program/shadow.vsh:87-89`、`A:lib/settings.glsl:182`） | A 省（主世界零开销）。误差：主世界无彩光，只有亮度图 tint（`A:global/lighting/blocklight.glsl:84-102`）。 |
| 体积规模 | 128~1024 可选，`(N,N/2,N)`，128 档=1,048,576 格（`P:shaders/shaders.properties:142-144`） | 固定 64³=262,144 格（`A:shaders.properties:693-695`） | A 省 4 倍（比最大档差千倍）。误差：A 只 ±32 格、八步扩散，超出回退亮度图（`A:global/dimension/nether.glsl:172-175`）。 |
| 体积内存/带宽 | 17 B/格（1+8+8），128 档≈17 MiB | 20 B/格（4+8+8），64³≈5 MiB | P 格式更省（占用图 r8ui vs r32ui，每格省 3 B）；总量仍由格数主导，A 远小。误差：无。 |
| 传播调度 | 1 次 dispatch/帧，半速率+重投影，跨帧收敛（`P:shaders/program/shadowcomp.glsl:94-118`） | 9 次 dispatch/帧（`A:world-1/shadowcomp*.csh:2`），带共享内存 halo tile（`A:program/nether_light.csh:19-36`） | P 每帧算力低得多；A 当场收敛。误差：P 收敛滞后/残影；A 八步在体积边缘截断（`A:global/dimension/nether_colored_light.glsl:9-12` 淡出）。 |
| 光源分类/颜色 | 84 类 ID + 每族独立颜色与射程 + alpha 附加光（`P:shaders/lib/colors/blocklightColors.glsl:18-177`） | 12 类，统一 ×2.0（`A:program/shadow.vsh:70-82`、`A:program/nether_light.csh:37-60`） | A 省（表小）。误差：A 自述无法复现 per-kind radiance（`A:program/nether_light.csh:53-59`），无体积内染色、无 alpha 额外光。 |
| 染色玻璃 | 体积 tint（`P:shaders/program/shadowcomp.glsl:120-124`）+ 阴影贴图 tint（`P:shaders/lib/lighting/shadowSampling.glsl:17`） | 仅阴影贴图 tint（`A:program/shadow.fsh:50-58`、`A:global/lighting/shadowmap.glsl:120-127`） | A 省。误差：A 的彩光不进散射/彩雾，玻璃后墙面的彩光缺失。 |
| 彩光与雾/光柱 | 彩光进体积雾与光柱（`P:shaders/lib/atmospherics/fog/coloredLightFog.glsl:1-51`、`P:shaders/lib/atmospherics/volumetricLight.glsl:176-189`） | 雾只吃 `blissNetherNoise`（`A:global/dimension/nether_volume.glsl:22-57`）；光柱色取 `shadowcolor0.gba`（`A:global/water/light_shafts.glsl:71`） | A 省。误差：A 的体素彩光不出现在下界雾里。 |
| 占用图复用 | 4 处材质侧消费（`P:shaders/lib/materials/...`） | 仅传播 compute 读（`A:program/nether_light.csh:50`） | P 复用率高（无额外 pass）。误差：A 无（只是未利用）。 |
| 漏光修正 | 消费端 6 邻居 clamp（`P:shaders/lib/misc/voxelization.glsl:37-57`） | 仅边界淡出（`A:global/dimension/nether_colored_light.glsl:16`） | P 多 6 次 texel 读取；A 更省。误差：A 墙角可能漏光（P 也承认 0.5 偏移会闪 slab，`P:shaders/lib/lighting/mainLighting.glsl:373`）。 |
| TAA | 速度混合因子 + 邻域 AABB clamp（`P:shaders/lib/antialiasing/taa.glsl:17-53`） | 逐双线性 contributor 深度校验 + reactive 拒历史（`A:program/taa_resolve.fsh:28-50`、`A:lib/taa_reactive.glsl:7-9`） | P 便宜，A 更稳（拒绝插值深度）。误差：P 会拖影/发糊，A 覆盖率可能偏低。 |
| 云 | r5.5.1 Reimagined + 可叠加 Unbound（`P:shaders/lib/atmospherics/clouds/mainClouds.glsl:37-42`） | 已移植 r5.9 Reimagined（`A:global/atmosphere/clouds_planar.glsl:5-19`） | A 领先一代；P 唯一可借鉴点是"双模型叠加"。 |

## ⑤ 许可可行性与"重写 vs 抄"边界

**许可证事实（`P:License.txt`，91 行）**：`:1` 标题 "Complementary License Agreement 1.5"；`:9-13` "Normal Usage" 明确不含重分发（部分）包与修改代码；`:21-22` 定义 "Modified Pack"（代码被有意改动）；`:38-41` 允许游玩与内容创作；`:43-49` 允许放进整合包重分发（需显著署名、问题自担）；`:51-69` 允许作为 Modified Pack 重分发，四个条件——显著署名原包并链官网（53-55）、许可文件原样保留且随原包更新（56-60）、包名不得含 "Complementary" 且与原名至少 3 字符差（61-65）、观感必须在含白天主世界的多个场景明显不同（66-69）；`:71-76` 未在 Grants 明确覆盖的一切使用/分发按 **All Rights Reserved**，唯一例外是自带其它许可声明的文件；`:78-80` 仅对"本文件所在版本"有效；`:84-92` 追诉条款。

**包内其它许可**：全包仅两处出现 "license" 字样——`P:License.txt` 与 `P:shaders/lib/materials/materialMethods/anisotropicFiltering.glsl:1-4`（MPL-2.0，文件级 copyleft）。未见 GPL/MIT/CC 声明、CREDITS 或 NOTICE。

**判定**

1. 该许可**未给第三方"取用代码"的授权**：1.3 只豁免"整包做成 Modified Pack 再分发"（附署名/保留许可/改名/观感显著不同），2.1 把"任何部分的使用与分发"按保留所有权利兜底。片段搬进 Astra 不构成 Modified Pack，落在 2.1 禁止区。
2. 2.2 只对 2.4 版有效；上游署名对象是 EminGT 的 Complementary（`P:shaders/program/template.glsl:1-3`），不是 amethyst 作者。
3. Astra 既有约定：专有来源只能"重写后再发布"（`A:global/lighting/blocklight.glsl:20-21`、`A:global/water/surface.glsl:13`，均注明 REWRITE REQUIRED + 发布门 9.3/SC-14）。本次按同一标准。

**重写 vs 抄边界**

- 可抄（技法/常识，无版权表达）：体素↔世界坐标换算、7 点平均/6 邻居 max 扩散核、ping-pong 帧奇偶、`gl_VertexID % 4` 去重、档位映射结构、image 尺寸与 workGroups 的整除关系。
- 必须重写（创造性表达或具体数值串）：`blocklightColors.glsl` 的 84 条颜色/强度表、`specialTintColor` 的 17 色值、`GetSpecialBlocklightColor`/`GetVoxelIDs` 完整分支与注释、workGroups 七档常量表、`shaders.properties` profile 行、`block.properties` 标签清单、`lang/en_US.lang` 文案、许可文本本身。
- 换名与避免混淆：Astra 不得使用 "Amethyst"/"Complementary" 名号；若要以 Modified Pack 形式直接分发本包（而非借鉴思想），才需满足 1.3 全部四项。
- 例外文件：`anisotropicFiltering.glsl`（MPL-2.0）若取用，仅该文件需按 MPL-2.0 提供源码；建议避开，自研各向异性过滤。
- 结论：**只借鉴思路、全部重写**是唯一可行路径；③ 段所有条目均按此口径。

## ⑥ Top5 与暂缓项

**Top5（收益/成本排序）**

1. **时域摊销传播（半速率+重投影+背后早退）**——彩光从下界推广到主世界的成本分水岭：1 次 dispatch/帧 vs 现有 9 次全量。`P:shaders/program/shadowcomp.glsl:72-118`，`A:program/nether_light.csh:1-8`。工作量中高。
2. **染色玻璃体积滤色 + 角落漏光夹紧**——消费端小改、观感明显、不增 pass（③-6、③-8）。工作量低。
3. **per-family 光色/射程表 + alpha 附加光**——直接回应 Astra 自述局限（`A:program/nether_light.csh:53-59`），12 类扩到约 20 类并给每族系数。工作量低。
4. **占用图 r8ui 化 + 材质侧复用**——省 3/4 占用带宽，并把体素图用于连接玻璃/边缘特效，零新 pass（③-4、③-7）。工作量低-中。
5. **体积规模/有效距离档位化 + 消费端距离回退**——给 `NETHER_VOXEL_LIGHT` 增 64/96/128 三档与"超出即回退亮度图"（Astra 已有半套），为主世界彩光铺路（③-3）。工作量中。

**暂缓**

- **彩光雾/彩光柱（③-10、③-11）**：需同时改雾、光柱与 shadowcolor 输出三处，收益偏观感，优先级低于 Top5。
- **水坑体素化（③-13）**：需新增 image + 采集分支 + 消费端；`wet_material.glsl` 已覆盖大部分雨天观感。
- **双云模型叠加（`P:shaders/lib/atmospherics/clouds/mainClouds.glsl:37-42`）**：Astra 云已移植 r5.9，比本包更新；移植 Unbound 体积云成本高。
- **像素化阴影/方块光/AO**（`P:shaders/lib/lighting/mainLighting.glsl:35-58`、`P:shaders/lib/common.glsl:549-557`）：与批次一重复（`complementary-reimagined.md` §2.3），且与 Astra 写实定位不符。
- **屏上文字调试（`P:shaders/lib/textRendering/textRenderer.glsl:1-329`）**：工具价值，非画面；QA 阶段单独评估。

## 附录：自抽查（成稿后重开源文件核对行号，共 12 条）

核对方法：成稿后用 `sed -n '<行号>p'` 逐条打印被引用行，与正文比对；以下为实际打印结果摘要。

| # | 引用 | 核对结果 |
|---|---|---|
| 1 | `P:shaders/shaders.properties:142` | 一致：`image.voxel_img = voxel_sampler red_integer r8ui ... 128 64 128` |
| 2 | `P:shaders/lib/misc/voxelization.glsl:5` | 一致：`voxelVolumeSize = ivec3(COLORED_LIGHTING_INTERNAL, *0.5, ...)` |
| 3 | `P:shaders/lib/misc/voxelization.glsl:10` | 一致：`effectiveACLdistance = min(float(COLORED_LIGHTING_INTERNAL), shadowDistance * 2.0)` |
| 4 | `P:shaders/program/shadowcomp.glsl:59` | 一致：`return light / 7.2;`（7 点平均的除数） |
| 5 | `P:shaders/program/shadowcomp.glsl:100-102` | 一致：`if (posM.x < 0.5) { ... return; }`（半速率分支） |
| 6 | `P:shaders/lib/colors/blocklightColors.glsl:19-21` | 一致："colors do not determine the intensity ... how long the color will travel" |
| 7 | `P:shaders/lib/lighting/mainLighting.glsl:396` | 一致：`specialLighting = mix(blockLighting, specialLighting, COLORED_LIGHT_SATURATION * 0.01)` |
| 8 | `P:shaders/lib/atmospherics/fog/coloredLightFog.glsl:50` | 一致：`return pow(lightFog / sampleCount, vec3(0.25));` |
| 9 | `P:License.txt:56-60` | 一致：1.3.b "license file must still be left inside the Modified Pack ..." |
| 10 | `A:lib/nether_voxel_grid.glsl:29-31` | 一致：`ASTRA_NETHER_VOXEL_SIZE 64` / `HALF_EXTENT 32.0` / `INV_SIZE (1.0/64.0)` |
| 11 | `A:program/nether_light.csh:53-59` | 一致："One multiplier for every species cannot reproduce the reference's per-kind radiance ..." |
| 12 | `A:shaders.properties:693-695` | 一致：`astraVoxelImage ... r32ui ... 64 64 64`；`astraLightA/B ... rgba16f ... 64 64 64` |

补充核对（正文引用）：`P:shaders/program/shadow.glsl:301` = `if (gl_VertexID % 4 == 0) {`；`P:shaders/lib/misc/voxelization.glsl:287` = `... 200 + (mat - 31000) / 2; // Stained Glass+`；`P:shaders/lib/atmospherics/volumetricLight.glsl:252` = `texture2D(shadowcolor1, coord).a`；`A:global/water/light_shafts.glsl:71` = `textureLod(shadowcolor0, pos.xy, 0.0).gba`。
