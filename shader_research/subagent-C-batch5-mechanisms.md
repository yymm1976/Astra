# 第五批 33 个光影包逐包机制深挖（subagent-C）

只读调研。改动范围：仅新建本文件（`Astra/`、`reference_shaderpacks/`、`_analysis/batch5_unpack/` 均未修改）。

## 0. 方法与边界

- **取证方式**：全部结论来自逐文件读取与带行号检索（`ops_grep` 的 content 模式 + `node _analysis/show.js <文件>:<起>-<止>` 带行号打印）。**没有**任何结论来自包名、README 摘录或搜索摘要。
- **行号写法**：包内文件一律写作 `_analysis/batch5_unpack/<包名>/...:行号`；Astra 文件写 `Astra/shaders/...:行号`。
- **Astra 未实现的确认方式**：对 `Astra/shaders` 跑同一机制关键词，把**实际用的关键词和命中数**写在每条"现状证据"里（命中 0 才算缺口；命中非 0 的一律先读命中行再判断，已实现的直接剔除，见 §5）。
- **标注**：〔读源码〕= 我读了那段源码；〔推断〕= 由读到的代码推出的结论，未实测运行；未验证 = 没查到证据，写在 §6。
- **术语先说人话**（首次出现）：
  - **SMAA**：一种"找出画面里的硬拐角，然后只把这些拐角附近按预计算的图案重新混合"的抗锯齿方法（Astra 现在没有，只有 FXAA 和 TAA）。
  - **GI（全局光照）**：光打到墙后弹到别处、把阴影里也照亮的那部分光。
  - **SVGF / a-trous**：一种在屏幕空间上"按颜色相似度加权模糊"来给带噪点的 GI 结果去噪的方法；a-trous 指每轮只隔一个像素采样、逐步放大的多轮模糊。
  - **时域累积 / 重投影**：把上一帧的结果按摄像机运动"搬到"这一帧的位置再和本帧混合，用来摊平每帧只算一部分的采样量。
  - **双缓冲（ping-pong）**：两张一样的贴图轮流当"读的"和"写的"，避免一边读一边写同一张图。
  - **体素 floodfill**：把世界切成小方块（体素），亮度从发光方块往邻居一格一格传出去，像水面扩散。
  - **bent normal（弯曲法线）**：把"这一点的遮蔽主要来自哪个方向"存成一个方向，用来让环境光/天光不只是一团均匀亮。
  - **直方图自动曝光**：统计画面亮度的分布直方图，按目标分位数调整整体亮度。

## 1. 包规模与结构（第一列 = 该包着色器文件数：.glsl/.vsh/.fsh/.csh）

| 包 | 文件数 | 关键结构（节选） |
|---|---|---|
| velocity-shaders | 380 | `shaders/global/{shadows,lighting,blocklight_shadows,pbr,sky,water,wind_streaks}.glsl`、`global/post/{smaa,cas,ssao,taa,bloom}.glsl`、`program/composite1..13+deferred1+clrwl_shadow` |
| luster-shaders | 647 | `include/lighting/{cloud_shadows,indirect_lighting/{gtao,sspt,temporal}}`、`include/post_processing/taa.glsl`、`include/camera/local_exposure.glsl`、`program/{d4_sspt,d5_sspt_accumulate,d6_sspt_filter,c19_color_grading}` |
| escheridia | 114 | `prepare.csh`（compute floodfill）、`voxels.glsl`、`lib/shadows/*`、`lib/atmosphere/clouds.glsl` |
| verlixia / truelightfx / prismarine-shader | 496 / 286 / 286 | `lib/antialiasing/taa.glsl`、Chocapic 血统的 TAA/TAA_SELECTIVE |
| muuf-a.g.i-shaders | 300 | `MuufLib/lighting/GlobalIllumination.glsl`（RSM/SSGI）、`InternalLib/Deferred0-2.glsl` |
| fantasy-shader-unbound | 337 | `lib/antialiasing/taa.glsl`、`lib/misc/voxelization.glsl`、`program/shadowcomp.glsl`（Complementary 血统） |
| kute | 259 | `global/post/{smaa,taa,cas}.glsl`（mellow 血统） |
| the-better-default | 15 | `gbuffers_terrain.fsh`(364)、`gbuffers_entities.fsh`(159)、`shadow.vsh`(52) |
| smaa-mc | 8 | 不是 Iris 光影包，是 **Minecraft 原版 post_effect 资源包**：`assets/minecraft/post_effect/end_of_frame.json`、`assets/grindstone_smaa/shaders/post/{0_edge_detect,1_bw_calc,2_blend}.fsh`、`grindstone_cas/.../3_cas.fsh` |
| taa | 27 | `shaders/bsl_lib/antialiasing/taa.glsl`(97)、`bsl_lib/unsharp_mask.glsl`(17)、`lib/jitter.glsl`(19) |
| anti-aliasing | 76 | `world0|world-1|world1` 三份 `final.fsh`(205)+jitter TAA；**无 FSR/EASU/RCAS 命中（grep `FSR|EASU|RCAS|DLSS` = 0）** |
| lumeau | 43 | `lib/shadow.glsl`(65)、`lib/lighting.glsl`(48)、`prog/*.fsh` |
| lantern-shader / raincore | 32 / 36 | `lib/dofoffsets.glsl`(62)、`lib/dither.glsl`(34)、`main/composite0-6`（景深+抖动滤镜） |
| relumination | 18 | `lib/lights.glsl`(49)、`world0/composite.fsh`(106)、`composite9.fsh`(35) |
| highframes-plus | 76 | 每维度一套 `deferred/composite/final`，无独立后处理库 |
| realisticallyoptimized | 20 | `lib/shadows.glsl`(32)、`final.fsh`(109)，卡通化 |
| tilde | 22 | `lib/effect.glsl`(211)（世界弯曲） |
| crumb | 154 | `lib/fast_taa.glsl`(186)、`lib/volumetric_clouds*.glsl`、SSR |
| artshade | 241 | `lib/clouds.glsl`(478)、`lib/shadow_filter.glsl`(139)、`lib/ss_shadow.glsl`(148)、`lib/taa.glsl`(106) |
| wispy-shader | 203 | `global/post/{taa,cas}.glsl`、Mellow 血统，含 FSR 锐化选项 |
| terders-potato / essentials / wither-rose / body-camera / cursed-fog / ctrvcr / ch-motion / thunders-mb / motion-blur-fx | 42/41/17/87/81/59/17/14/34 | 整活或单功能覆盖类 |
| aquarium | 0 | 目录只有 `data/` 与 `pack.mcmeta`，**没有 `shaders/`** → 不是光影包〔读结构〕 |

## 2. 候选机制（按价值排序，每条六项）

### C1. luster：屏幕空间路径追踪 GI（SSPT）＋SVGF 去噪＋方差自适应时域累积〔读源码〕价值高/成本高
- **机制**：半分辨率（可切 1/1、1/2、1/3）跑一条屏幕空间光线追踪，命中点取该点自身的直射光/自发光当作间接光；第一帧用 7×7 边缘感知空间滤波补足采样；随后每帧做"深度拒绝＋方差自适应 alpha"的历史累积，再用 5 次 a-trous SVGF 迭代降噪。
- **出处**：
  - 追踪与 BRDF：`luster-shaders/shaders/include/lighting/indirect_lighting/sspt.glsl:4-6`（"Screen-space path traced emission + indirect lighting"）、`:58-62`（余弦半球采样 cosineVector）、`:67-70`（命中判定：10% 相对视深阈值）、`:77-90`（screenspaceRT / hitEmission）、`:100-140`（hitDirectLight / brdfWeight）
  - 历史累积：`luster-shaders/shaders/program/d5_sspt_accumulate.fsh:5-16`（含 `world_age_changed` 检测世界变化）、`:132-133`（7×7 gather，法线＋深度加权，同时构建方差矩）、`:254-272`（4 个历史偏移、10% 相对深度拒绝）、`:281-297`（alpha 排程 `max(0.01*minAccumMult, 1.0/frames)`，并按 lightmap 差做自适应拒绝）、`:302-308`（方差矩混合）
  - SVGF：`luster-shaders/shaders/program/d6_sspt_filter.fsh:5`（"One a-trous SVGF filter iteration ... instantiated five [times]"）、`:75-99`（3×3 高斯 sigma 估计）、`:100`（atrousSVGF(texel,size)）
  - 分辨率分档：`luster-shaders/shaders/shaders.properties:222-242`（`indirectResReduction` 1/2/3 → colortex17-20 的 size.buffer 在 1.0/0.5/0.333/0.25 之间切换）
  - 开关：`luster-shaders/shaders/shaders.properties:79-80,547-550`（`program.world0/deferred4.enabled = ssptEnabled`，屏单 `screen.indirect_lighting = ssptEnabled [sspt_filter] ssptFullRangeRT indirectResReduction ssptBounce`）
- **Astra 现状证据**：`Astra/shaders` 关键词 `sspt`=0、`ssgi|screen.?space.?gi`=0、`svgf|atrous|bilateral`=0、`gtao|hbao`=0。Astra 没有任何屏幕空间间接光、也没有任何降噪器（`Astra/shaders` 无对应文件）。间接光只能靠 (a) 天光球谐 + bent normal（`Astra/shaders/lib/ao_resolve.glsl:13-52`、`Astra/shaders/global/lighting/diffuse.glsl:425-427,493`）和 (b) 下界体素光（`Astra/shaders/program/nether_light.csh:1-8`）。→ 这是**机制级空白**。
- **迁移落点与代价**：新增一条 `deferred` 后置链（追踪→累积→滤波），至少 3 个 program + 4 张半分辨率附件（历史色、历史方差/ghat、当前结果、法线深度打包）；Astra 已有 `size.buffer` 分档与 `program.*.enabled` 基建可直接复用（列进 `Astra/shaders/shaders.properties` 的屏单与 options，参照现行 `SCREENSPACE_AO` 的组织方式）。代价：屏幕空间光线追踪在 Iris/GLSL 下是纯手工实现（无硬件 RT），半分辨率 + 时域累积下每帧仍要多次全屏 pass；要处理 TAA 抖动与历史一致（Astra 的 TAA 在 `Astra/shaders/program/taa_resolve.fsh`，需要把 GI 的抖动/history 与它对齐，否则会互相污染）。
- **风险**：①屏幕空间方法天生有"离屏/背面信息缺失"，luster 用 `ssptFullRangeRT` 开关和 10% 深度阈值兜底，直接照搬会在开阔地形产生漏光；②Astra 已有 TAA（YCoCg 逐角钳制 + reactive），GI 历史与 TAA 历史是两套时域，交集处理不当会出重影；③显存：4 张半分辨率 RGBA16F 在 4K 下约 4×8MB，可接受，但全分辨率档要小心。
- **许可**：luster-shaders 自有许可，**允许"examine and learn from Luster Shaders's source code"**（`_analysis/batch5_unpack/luster-shaders/LICENSE:12`），但 **禁止未经书面许可再分发/发布含 Luster 原创材料的衍生作品**（`:17-25`）。同时 `:33` 声明本包"substantially based upon Photon"，Photon 部分走 Photon 许可。**结论：可以读、可以学思路，代码不能直接搬进 Astra 后发布。**

### C2. velocity：完整空间域 SMAA（edge/search/blend 三 pass + 外部 area/search 纹理）〔读源码〕价值高/成本中
- **机制**：标准 SMAA：先做边缘检测写 `colortex2`（.rg 水平/垂直边缘，.ba 邻域权重），再用预计算的 search 纹理（`/lib/smaaSearch.png`，66×33）快速跳到边缘两端，用 area 纹理（`/lib/smaaArea.png`，160×560）取混合权重，最后按权重对两个邻居做加权混合。
- **出处**：
  - `velocity-shaders/shaders/global/post/smaa.glsl:1-10`（redmean 颜色差）、`:24-34`（search_length，`SEARCH_TEX_SIZE = vec2(66,33)`，读 colortex5）、`:36-83`（四个方向的 SMAASearch，读 colortex2 的 .rg）、`:85-88`（sample_area，坐标 `16*round(4*vec2(e1,e2))+vec2(d1,d2)+0.5`，除以 `vec2(160,560)`）
  - 三个消费者（依次覆写同一张 colortex2）：
    ① 边缘检测 `velocity-shaders/shaders/program/composite9.fsh:6-7`（`DRAWBUFFERS:2`，输出 `SmaaEdges`）、`:12-16`（对左/上邻取 redmean）、`:18-19`（`Threshold = SMAA_THRESHOLD`，并用 `Threshold /= 2 - isOutdoorsSmooth` 在地下提高灵敏度）、`:22-27`（无边缘写 0 返回）、`:29-43`（取右/下/左二/上二求 `MaxD`，用 `Edges *= step(max(MaxD.x,MaxD.y), D*2)` 抑制"旁边有更强边缘"的像素——这是**简化的局部对比度抑制**）
    ② 搜索 + 权重：`velocity-shaders/shaders/program/composite10.fsh:14`（读 colortex2.rg 边缘）、`:19-24`（三组偏移，含 `SMAA_SEARCH_DISTANCE`）、`:27-44`（水平搜索 + `sample_area` 写 Color.rg）、`:46-63`（垂直写 Color.ba）、`:65`（`SmaaEdges = Color`，权重写回 colortex2）
    ③ 混合：`velocity-shaders/shaders/program/composite11.fsh:11-29`（4 邻域权重、按 `max(L,R) > max(D,U)` 选方向、两次 textureLod 加权混合）
  - 资源与开关：`velocity-shaders/shaders/shaders.properties:28-29`（`texture.composite.colortex3=/lib/smaaArea.png`、`colortex5=/lib/smaaSearch.png`）、`:32`（search 纹理 0.25 分辨率）、`:60-71`（`program.world0/composite9|10|11.enabled=SMAA`，四个维度入口各三条）、`:166`（屏单含 SMAA_THRESHOLD / SMAA_SEARCH_DISTANCE）、`velocity-shaders/shaders/lang/en_US.lang:68-73`（选项说明）
- **Astra 现状证据**：`Astra/shaders` 关键词 `SMAA`=0、`smaa|areaTex|searchTex`=0、`\blca\b`=0。Astra 只有 FXAA（`Astra/shaders/global/post/fxaa.glsl`）与 TAA（`Astra/shaders/program/taa_resolve.fsh`），抗锯齿档位在 `Astra/shaders/lib/settings.glsl:276-277`（ANTIALIASING 三档互斥）。→ 缺口。
- **迁移落点与代价**：需要 3 个额外全屏 pass + 2 张 `lib/*.png` 资源（`Astra/shaders` 目前没有任何 sampler 外部查找纹理的 AA 资源）；`shaders.properties` 用 `program.<name>.enabled=SMAA` 挂开关（Astra 已有该写法）。代价：多 3 个 pass + 每像素最多约 32 步搜索；和现有 TAA 同时开要决定互斥（Astra 已有 ANTIALIASING 互斥档，扩一档即可）。
- **风险**：①与 TAA 同时开启可能双重平滑；②search/area 纹理必须按 AMD 原版尺寸与量化解码，图片压缩/格式（RGBA8）搞错会安静地出糊边；③velocity 的实现只做空间 SMAA（**没有** T2x 时域版本，`smaa.glsl` 里没有历史/history 变量），不要以为它顺带解决了时域。
- **许可**：velocity **MIT**（`_analysis/batch5_unpack/velocity-shaders/LICENSE:1-2`，"Permission is hereby granted, free of charge ... to deal in the Software without restriction"），来源是 mellow 分支（README:1）。SMAA 算法本身出自 Jimenez 等人的公开论文/参考实现（velocity 的 `global/post/smaa.glsl` 未附额外条款）。→ **可以代码级借鉴，保留版权与许可声明。**

### C3. smaa-mc：SMAA 的 LCA（局部对比度自适应）＋对角搜索＋角点圆化；CAS 的"更好对角线"〔读源码〕价值中/成本低
- **机制**：①边缘检测时除了基础阈值，还用 `SMAA_LCA` 判定"附近有更高对比度边缘就跳过本边缘"，省搜索；②除了水平/垂直搜索，还有对角方向搜索（`SMAA_SEARCH_DIAG`）；③对拐角做圆化处理（`SMAA_CORNER` 百分比），修短边拐角。
- **出处**：`smaa-mc/assets/grindstone_smaa/shaders/post/0_edge_detect.fsh:27`（`edges = greaterThanEqual(delta, (SMAA_THRESHOLD*SMAA_THRESHOLD).xx)`）、`:41-45`（LCA：`delta >= max(delta_max)/SMAA_LCA^2`）；`smaa-mc/assets/grindstone/shaders/include/config.glsl:3,7,11,15,19`（阈值 0.1 / LCA 1.1 / 搜索 32 / 对角 16 / 角点 25 / CAS 锐度，并注明"SMAA_SEARCH_DIAG=0 关闭对角处理""SMAA_CORNER=0 关闭角点处理"）；`smaa-mc/assets/grindstone_smaa/shaders/post/1_bw_calc.fsh:16,27-51,82,99`（`area_diag` 与对角搜索循环）、`:106`（area）、`:158-161`（corner_rounding）
- **Astra 现状证据**：`SMAA`=0、`\blca\b`=0（`Astra/shaders`）。Astra 完全没有 SMAA 相关代码，所以 LCA/对角/角点这三样当然也不存在。**注意 velocity 的 SMAA 只有简化版局部对比度抑制**（`composite9.fsh:35-41` 的 `Edges *= step(max(MaxD.x,MaxD.y), D*2)`，硬编码 2 倍、无可调因子），**没有** `SMAA_LCA` 可调系数、对角搜索与角点圆化（对它 grep `LCA|corner|diagonal` 只命中 `search_length` 一类）——两条实现要分开看。
- **迁移落点与代价**：如果采纳 C2，这三项是同一套代码里的可选分支，增量很小（几十行 + 2 个阈值宏）。若只做"最小 SMAA"，可以先跳过对角搜索省性能。
- **风险**：`smaa-mc` 是**原版 1.21.2 post_effect 资源包**（`smaa-mc/assets/minecraft/post_effect/end_of_frame.json:7,52,57,66-68` 声明 `"fragment_shader": "grindstone_smaa:post/2_blend"`），它的 uniform/采样器命名与 Iris 的 `colortex` 体系完全不同，**不能直接复制文件**，只能按算法重写成 Iris 版本（velocity/kute 的实现就是现成的 Iris 化参照）。edge 检测里 `discard` 的写法（`0_edge_detect.fsh:47,50`）在 Iris 多附件绘制下要换掉。
- **许可**：smaa-mc **MIT**（`_analysis/batch5_unpack/smaa-mc/LICENSE:1-3`，"Copyright (c) 2024-2026 Luracasmus"）。→ 可借鉴。

### C4. escheridia：多帧体素 floodfill（双缓冲 ping-pong ＋ 摄像机位移重投影 ＋ 6 邻域递增衰减）〔读源码〕价值中高/成本中高
- **机制**：把玩家周围 `VOXEL_AREA`³（32/64/128/256 可选）的世界体素化到两张 3D 图；compute 每帧对每个体素取上一帧的 6 个轴向邻居亮度，做 `max(邻居) - 1/15` 的传播（每格衰减 1/15），与自身自发光取 `max`，写回；两张 3D 图按 `mod(frameCounter,2)` 交换读写位置（同一张贴图上下两层当双缓冲）；读取时按 `cameraPositionInt - previousCameraPositionInt` 把历史格子平移回当前相机（等于免费获得"上一帧位置"的重投影）。
- **出处**：`escheridia/shaders/prepare.csh:5`（local_size 8×16×1）、`:9-20`（四档 workGroups）、`:34-45`（双缓冲偏移与 `camshift`）、`:58-85`（+X/-X/+Y/-Y/+Z/-Z 六个 imageLoad，每次 `light - 1./15.`，取 max，负值截零）、`:116-117`（imageStore 写回）；`escheridia/shaders/voxels.glsl:15-22`（由 `feetPlayerPos + at_midBlock/64 + cameraPositionFract + VOXEL_RADIUS` 定位体素，仅 `mod(gl_VertexID,4)==0` 的顶点写）、`:27-38`（按 mc_Entity 编码发光种类，`imageAtomicMax` 写入体素化图）；采样侧 `escheridia/shaders/gbuffers_terrain.fsh:91-99`（unpackUnorm4x8 + 3D 纹理三线性插值 + 双缓冲偏移）、`:116-119`（`VOXEL_FADE_START/END` 边界淡出）；配置 `escheridia/shaders/lib/common.glsl:29-33`（`#define FLOODFILL`、`VOXEL_AREA 128`、`MAX_FLOODFILL_INTENSITY 3.0`）；3D 图分配 `escheridia/shaders/shaders.properties:43-66`（`image.floodfill = voxelFloodfill RGBA RGBA8 BYTE false false 128 256 128`）；屏单 `escheridia/shaders/shaders.properties:95`（`screen.Voxel-Lighting = FLOODFILL VOXEL_AREA`）
- **Astra 现状证据**：`floodfill`=0（`Astra/shaders`）。但 Astra **已有近似机制**：`Astra/shaders/program/nether_light.csh:1-8` 明写 "Solas 3.7b voxel-source / empty-cell propagation pattern, adapted to Astra's bounded **same-frame** volume (64^3 around the player, **eight diffusion steps, no history**)"，并且 `:6-8` 明确写过"上一帧的 frame stamp 既没必要、又是 parity-broken"。体素化写入方式 Astra 也有：`Astra/shaders/program/shadow.vsh:45-49,91`（uimage3D + `imageAtomicMax(astraVoxelImage,cell,astra_voxel_encode(kind,solid))`），下界用两张 3D 图含 ping-pong 采样（`nether_light.csh:18-19`）。→ **真正的差异只有"跨帧传播 + 摄像机位移重投影"这一条**（Astra 是每帧从头 8 步同帧扩散），不是"体素 GI"整体缺失。
- **迁移落点与代价**：把 `NETHER_VOXEL_LIGHT` 的单帧 8 步换成"每帧 1 格 + 历史复用"需要：新增历史 3D 图（或双缓冲）×2、把 8 步循环改成 1 步、加摄像机位移平移、并调整衰减常数（1/15 对应 max 15 格的传播距离，Astra 现在是 8 步固定）。代价不大（改一个 .csh + 定义），但**传播速度从 8 格/帧变成 1 格/帧**，玩家移动或炸洞后需要多帧才能收敛。
- **风险**：①Astra 代码注释里已经写明它对 frame stamp 的历史方案做过取舍（`nether_light.csh:6-8`），重开会踩同一个坑（parity 破面）——这是"与现行实现取舍冲突"的地方，必须显式评估；②体素分辨率 128³×2 层 RGBA8 = 16MB/张、两套 3D 图，Astra 现在是 64³，显存与带宽都要重算；③仅覆盖下界时收益小，扩展到主世界要重新解决主世界体素化来源（escheridia 是在顶点着色器里按 `mod(gl_VertexID,4)==0` 写体素，需要 `gl_VertexID`；Astra 的 `shadow.vsh` 已经在写体素，可复用）。
- **许可**：escheridia **MIT**（`_analysis/batch5_unpack/escheridia/LICENSE:1-2`，"Copyright (c) 2025 jrwilliamson"）。注意 `escheridia/shaders/voxels.glsl:2-10` 附了一段第三方来源声明："This code is from the VOXELIZING TUTORIAL by timetravelbeard … if you use this code as is, please leave this header. feel free to use this code in any shaders."（允许在任意光影中使用，但保留该头部）。

### C5. velocity：火把光（方块光）的屏幕空间遮挡〔读源码〕价值中高/成本中
- **机制**：从像素的"方块光份额"（由 lightmap.x 平滑得到，并随天空光衰减）算出屏幕空间 8 方向梯度；梯度太小就跳过；否则沿梯度方向做 8 步屏幕空间深度步进，用"深度差在 margin 与 2.5 之间"判定被挡，遮挡随步进衰减（`1 - 0.6*T`），最终按 `BLOCKLIGHT_SHADOW_STRENGTH * Share * Occlusion` 压暗颜色。
- **出处**：`velocity-shaders/shaders/global/blocklight_shadows.glsl:1-7`（编码/解码 share）、`:9-17`（`blocklight_share`：`smoothstep(0.15,1.0,Lightmap.x)`，主世界再乘 `(1-0.8*SkyShare)`）、`:23-33`（8 方向梯度，RADIUS=6，读 colortex0 的 alpha）、`:35-49`（8 步遮挡，`MaxDist = clamp(220/(Depth+2),10,60)`，`Margin = 0.12+0.03*Depth*T`）、`:51-57`（应用）；调用点 `velocity-shaders/shaders/program/deferred1.fsh:88`、份额来源 `velocity-shaders/shaders/program/gbuffers_terrain.fsh:183`；开关 `velocity-shaders/shaders/shaders.properties:131`（`screen.SHADOW_SETTINGS=BLOCKLIGHT_SHADOWS BLOCKLIGHT_SHADOW_STRENGTH ...`）、默认强度 `velocity-shaders/shaders/lib/settings.glsl:360`（`#define BLOCKLIGHT_SHADOW_STRENGTH 0.75`）
- **Astra 现状证据**：对 `Astra/shaders/global/lighting/blocklight.glsl` grep `occlu|gradient|depth_|screen.?space` = **0 命中**；对全 `Astra/shaders` grep `blocklight_|blockLightShadow|torch.?shadow` = 9 命中，全部是"强度/抑制/手持光"一类常量与下界体素光（如 `Astra/shaders/global/dimension/nether.glsl:13,101,169-184`），没有屏幕空间遮挡。→ 主世界的方块光**不做遮挡**，火把光会穿过墙照到背面（下界因为走了体素光而没这个问题）。
- **迁移落点与代价**：新增一个共享函数（约 50 行，无需新附件——只需要 colortex0 的 alpha 与 depthtex1，Astra 现在有这两个），在 `Astra/shaders/program/deferred2.fsh` 或环境光合成处调用一次。代价：每像素最多 8 步屏幕步进（可用 Dither 抖动降噪，Astra 已有抖动基建）。
- **风险**：①velocity 用 colortex0.a 传 share，Astra 的 colortex0 语义不同，需要另找载体（Astra 的方块光强度在 `blocklight.glsl` 里现算，可以直接传参）；②屏幕空间遮挡在屏幕边缘/前景物体处会漏（velocity 的 `Pos != clamp(Pos,...)` 直接 break，等于边缘不遮）；③与下界体素光路径要分开，避免双重压暗。
- **许可**：velocity MIT（同上）。

### C6. verlixia / kute：用 Catmull-Rom（三次）插值取历史颜色〔读源码〕价值中/成本低
- **机制**：重投影得到上一帧 UV 后，不直接用双线性，而是取 5 个 texel 做 Catmull-Rom 三次重建（更锐利的历史，减少 TAA 拖糊）。
- **出处**：`verlixia/shaders/lib/antialiasing/taa.glsl:63-64`（注释 "Catmull-Rom sampling from Filmic SMAA presentation"，函数 `textureCatmullRom(sampler2D colortex, vec2 texcoord, vec2 view)`）、`:154`（`tempColor = textureCatmullRom(colortex2, prvCoord, view)`）；kute 同源简化版 `kute/shaders/global/post/taa.glsl:27`（`texture_catmullrom_fast`）、`:94`
- **Astra 现状证据**：`Astra/shaders` 关键词 `catmull` = **0**；Astra 的历史是**双线性**且逐贡献者校验：`Astra/shaders/program/taa_resolve.fsh:1`（"validated bilinear history"）、`:62`（`taa_history(...)`）、`:39-42`（`textureGather` 取 2×2 上下界）。→ 采样方式不同，属可替换细节。
- **迁移落点与代价**：改 `Astra/shaders/program/taa_resolve.fsh:62-84` 的历史取样函数，需要 5 个 texelFetch（现在是 1 次 gather + 双线性）。**代价提示**：Astra 现有实现的重点是"逐贡献者深度校验"，换成 Catmull-Rom 会把 4 个贡献者变成 16 个（4×4），校验逻辑要重写，否则会破坏它现有的"插值深度不能代表任一真实表面"防线（`taa_resolve.fsh:60` 注释）。
- **风险**：Catmull-Rom 会引入轻微过冲（ringing），在深度断裂处容易带出鬼影；Astra 的历史校验是刻意设计的，改动要重跑现有的验证流程。与现行 TAA 取舍**不冲突**（旧结论没有涉及历史插值方式），但属于"改动核心 TAA"的动作，需单独评估。
- **许可**：verlixia **包内无 LICENSE/README**（目录列出为空）→ 默认保留所有权利，**不可代码级借鉴**；kute **MIT**（`_analysis/batch5_unpack/kute/LICENSE:1-2`，"Copyright (c) 2025 James"）→ 可以从 kute 取这条（它是简化版 `texture_catmullrom_fast`）。

### C7. luster：TAA 的方差裁剪（YCoCg 域，gamma 随距离变化）〔读源码〕价值中/成本低
- **机制**：3×3 邻域取一阶/二阶矩，用 `sigma` 收缩 AABB（`min = max(min, mu - gamma*sigma)`），gamma 随像素到摄像机距离在 0.75→1.25 之间插值（远处更信任历史、时序更稳）；裁剪在 YCoCg 空间做（原文注释说这样 AABB 更紧）。
- **出处**：`luster-shaders/shaders/include/post_processing/taa.glsl:98-128`（3×3 fetch、对角线 tap 的 min/max）、`:142-152`（`#ifdef TAA_VARIANCE_CLIPPING`、注释 "An Excursion in Temporal Supersampling"、`float gamma = mix(0.75, 1.25, linear_step(0.25, 1.0, distance_factor))`）、`:154-158`（`sigma = sqrt(moments[1] - mu*mu)`、收缩 min/max）、`:161-166`（YCoCg 域 AABB 裁剪）
- **Astra 现状证据**：`Astra/shaders` 关键词 `\bvariance\b` = 3 命中，且**全部在注释里**、与 TAA 无关（`global/dimension/overworld.glsl:49`、`global/water/caustics.glsl:11`、`program/nether_reflection_resolve.fsh:57,64,72`）。Astra 的 TAA 钳制是"2×2 gather 直接取 min/max"的 AABB（`Astra/shaders/program/taa_resolve.fsh:39-42`），**没有方差项、没有 gamma、没有距离自适应**。→ 缺口（属可替换细节）。
- **迁移落点与代价**：只改 `taa_resolve.fsh` 的钳制段：把 2 次 textureGather（4 个角）扩成 3×3（10 次 texelFetch）或保留 gather 再补对角线；新增一个距离因子（Astra 已有 view depth）。代价：每像素多几次取样；yCoCg 转换 Astra 已有（`taa_resolve.fsh:24`）。
- **风险**：Astra 的 TAA 有 reactive/colorTrust（`:135-146`），方差收缩会改变有效混合率，需重新调参，否则可能出现"静止时纹路锁死、运动时抖动"的两极表现。
- **许可**：luster 同 C1（可学不可搬）。**替代来源**：`taa`（BSL 复刻）用的是纯邻域 AABB 无方差（`_analysis/batch5_unpack/taa/shaders/bsl_lib/antialiasing/taa.glsl:65-75`），帮不上；方差裁剪本身出自 Salvi 的 "An Excursion in Temporal Supersampling"（公开论文），实现可自写。

### C8. luster：局部曝光（细节尺度 + 区域尺度双重 dodge & burn）〔读源码〕价值中/成本低
- **机制**：以"全局测光的锚点 `anchor_log`"为中心，取本像素 log2 亮度 ±2 像素的 4 个轴向 + 4 个对角邻域做带指数权重的双边平均，得到精细 EV，限制在 ±0.667 档；另外用一个很低分辨率的 LOD 亮度的区域 EV（限制在 ±LOCAL_EXPOSURE_RANGE），两者按 `LOCAL_EXPOSURE_REGIONAL` 混合，最后乘 `LOCAL_EXPOSURE_DETAIL`。意在"亮天空压暗一点、暗谷提亮一点"，且明确不替代用户的全局曝光。
- **出处**：`luster-shaders/shaders/include/camera/local_exposure.glsl:6-8`（AP1 亮度）、`:11-71`（9 tap、`w = 2.0*exp2(-d*1.442695)`）、`:73-83`（`adaptation = 0.28`、`ev = (anchor_log - local_log)*adaptation`、`clamp(..., -0.6666667, 0.6666667)`）、`:85-100`（区域尺度：`region_lod = ceil(log2(...)*0.02)`、`region_ev` 用 `LOCAL_EXPOSURE_RANGE` 夹取、`mix(ev, region_ev, LOCAL_EXPOSURE_REGIONAL)`）；应用点 `luster-shaders/shaders/program/c19_color_grading.fsh:56,122-123`
- **Astra 现状证据**：`Astra/shaders` 关键词 `localExposure` = 0、`histogram|percentile|cdf` = 0。Astra 有曝光相关变量（`taa_resolve`/调色环节使用），但没有"按像素/区域重新分配曝光"的机制。→ 缺口。
- **迁移落点与代价**：在 Astra 的调色/曝光环节（`Astra/shaders/program/` 里做 color grading 的那个 pass）加一个 9 tap 的 EV 计算并乘进曝光，约 60 行，无需新附件（luster 读的是自己的 HDR 中间缓冲 colortex5，Astra 对应的是调色前的 HDR 缓冲）。
- **风险**：①局部曝光会改变画面整体对比，属于"观感取向"改动，需和现有色调映射一起看；②与 `HDR 宽色域` 的既有取舍**不是同一件事**（那条否决讲的是色域/传输曲线，不是曝光重分配），但需要显式确认不与其冲突；③9 tap 在低分辨率缓冲上的代价可忽略，但要注意别在已经过 TAA 的缓冲上做（会与时域互相影响）。
- **许可**：luster 同 C1。

### C9. luster：云影的立体投影 + 三层云分别积分 + bicubic 采样〔读源码〕价值中/成本中
- **机制**：云影图 512²，投影用"球面立体投影"（`p.xy / (1+|p|)` 与逆变换），所以整片天穹都能覆盖、没有固定世界范围截断；渲染时对积云/高积云/卷云三层各自按光方向求球面交点与光程，用 `exp(-extinction * thickness / |light_dir.y| * density)` 累乘；采样用 bicubic；并按"当前点是否高于云层"与"太阳高度角"淡出。
- **出处**：`luster-shaders/shaders/include/lighting/cloud_shadows.glsl:7`（`cloud_shadow_res = ivec2(512)`）、`:9`（`cloud_shadow_extent = 256.0/(CLOUDS_SCALE/10.0)`）、`:11-32`（正向/逆向立体投影）、`:34-59`（`get_cloud_shadows`：范围外返回 1、高度淡出 `smoothstep(0.05,0.15,light_dir.y)`、`bicubic_filter`）、`:63-133`（`render_cloud_shadow_map`：积云/高积云/卷云三段各自求交与消光）
- **Astra 现状证据**：`Astra/shaders` 关键词 `cloud_shadow` = 15 命中 → **Astra 已有云影缓存**：`Astra/shaders/global/atmosphere/cloud_shadow_cache.glsl:7`（`ASTRA_CLOUD_SHADOW_EXTENT = 512.0`，平面世界 XZ 范围）、`:13-18`（`astra_cloud_plane_transmission`：单次 `astra_cloud_coarse` 采样 + `smoothstep` 门限）、`:34-40`（按平面 UV 取值、边缘回落到直接求值）、`Astra/shaders/program/cloud_shadow_cache.fsh:12-29`（生产者）。`Astra/shaders` 的 `bicubic` = **0**、`equirect|stereographic` = **0**。→ **机制不是空白，差异是三点**：(a) 投影方式（平面 512 格 vs 立体全天穹）；(b) 单次粗采样 vs 三层云分别积分；(c) 双线性 vs bicubic。
- **迁移落点与代价**：只取 (c) 最便宜——把 `cloud_shadow_cache.glsl:40` 的 `textureLod` 换成 bicubic 需要自己写 16 tap（Astra 无内置 bicubic）；取 (b) 要在 `astra_cloud_plane_transmission` 里按 Astra 现有的云层参数增加层；取 (a) 会改动整个缓存坐标系与所有消费者，**代价高且与现有 snapped anchor/CPU 调度设计纠缠**（`cloud_shadow_cache.glsl:3-5` 记录了 Astra 对这套设计的取舍）。
- **风险**：①Astra 的平面投影是刻意选择（注释写明"plane mapping, snapped anchor, transition and storage are original"，并说明参考了 Refrax/Hysteria 只取想法），换投影会牵动 anchor 对齐与 CPU 调度重算；②三层云积分意味着更多噪声采样，Astra 的 `astra_cloud_coarse` 是低成本字段，直接叠三层会明显变贵。
- **许可**：luster 同 C1（云部分很多来自 Photon，见 LICENSE:33；Photon 许可允许研读与一定范围再分发，但对收费平台另有限制，具体口径见项目既有 `Astra/THIRD-PARTY.md` 流程）。

### C10. luster：直方图测光的自动曝光（三群体加权 + 目标 CDF）〔读源码 + 选项〕价值中/成本中
- **机制**：把画面亮度做成直方图（`HISTOGRAM_BINS` 档），对阴影群体单独加权（`HISTOGRAM_SHADOW_WEIGHT`），按目标分位数（`HISTOGRAM_TARGET`）反查亮度来决定全局曝光。
- **出处**：`luster-shaders/shaders/lang/en_US.lang:1110-1115`（`option.HISTOGRAM_BINS` "number of histogram bins"、`option.HISTOGRAM_TARGET` "target brightness for auto exposure"、`option.HISTOGRAM_SHADOW_WEIGHT` "Weight of the shadow population in the three-…"）
- **Astra 现状证据**：`Astra/shaders` 关键词 `histogram|percentile|cdf` = **0**；Astra 的曝光来自固定/环境驱动的全局值，没有画面分布测光。→ 缺口。
- **迁移落点与代价**：需要一张直方图附件 + 一个统计 pass（compute 或下采样循环）+ 读回曝光。注意：Iris 的 compute 可以写 image，但"同一帧内读回直方图再用于调色"需要跨帧（上一帧直方图驱动本帧曝光，luster 就是这么做的）。代价中等（新附件 + 1-2 个 pass + 时域平滑，否则亮度会闪）。
- **风险**：①自动曝光在快速明暗切换（下矿洞/进洞穴）会"呼吸"，必须做时域平滑；②与 C8 局部曝光叠加会双重补偿，需要决定二者只留一个或明确分工（luster 是两个都有且声明"区域补偿由全局曝光系统负责、局部只做细节"，这个分工值得照抄）。
- **许可**：luster 同 C1。

### C11. velocity：阴影距离末端的"动态阴影 → lightmap 静态遮蔽"交叉淡出〔读源码〕价值中/成本低
- **机制**：按到玩家距离算 `Fade = smoothstep(Dist*SHADOW_FADE_START, Dist, len_sq(PlayerPos))`；`Fade<1` 时算动态阴影，`Fade>0` 时用 `get_shadow_static(LightmapCoords.y) = smoothstep(0.82, 0.95, Skylight)` 当作静态遮蔽，最后 `Shadow = mix(ShadowD, ShadowS, Fade)`。也就是阴影贴图边界外不再是"没有阴影"，而是换成原版 lightmap 的天空光遮蔽值。
- **出处**：`velocity-shaders/shaders/global/shadows.glsl:1-6`（`shadow_fade`）、`:26-31`（`get_shadow_static`）、`:33-58`（`get_shadow_dynamic`）、`:49-55`（Taps 2/4 两档栅格 PCF）；**调用点** `velocity-shaders/shaders/global/lighting.glsl:172`（`float Fade = shadow_fade(PlayerPos, shadowDistance)`）、`:174-185`（`if(Fade<1.0)` 算动态、`if(Fade>0.0)` 算静态、`Shadow = mix(ShadowD, ShadowS, Fade)`）、`:206`（阴影关闭时完全用静态）；常量 `velocity-shaders/shaders/lib/settings.glsl:357`（`#define SHADOW_FADE_START 0.85`，八档选项）
- **Astra 现状证据**：`Astra/shaders` 关键词 `shadow_fade` = **0**；Astra 的做法是把阴影**淡出到 0**：`Astra/shaders/global/lighting/shadowmap.glsl:109-123`（`shadow_map_fade` 返回 `1 - smoothstep(shadowDistance-24, shadowDistance-8, boxDist)`）、`:136-140`（`shadow_coverage = fade * shadow_uv_coverage`）、`:117-119` 注释说明这是为了"避免突然跳出（popping）"，曾把 16/4 改成 24/8。→ **Astra 有淡出，但没有"淡到 lightmap 静态遮蔽"这条替代路径**（Astra 是淡到没有动态阴影，之后走的是无阴影分支）。
- **迁移落点与代价**：在 `Astra/shaders/global/lighting/` 的直射光合成处加一个"静态遮蔽"项（用 lightmap 天空光分量做 `smoothstep`），并按同一 fade 做 mix，约 20 行。
- **风险**：①Astra 的 `shadow_coverage` 语义可能与 velocity 不同（Astra 是乘在阴影上的覆盖率、0 表示什么要先确认消费端）；②用 lightmap 做静态遮蔽会让"远处本来能看到的软阴影"变成硬边（那是原版 lightmap 的分辨率），视觉上是取舍而不是纯改进。
- **许可**：velocity MIT。**这条与旧结论冲突**，见 §4。

## 3. 已读但**不**作为候选的（Astra 已有 / 已否决 / 证据不足）

| 项 | 包与行号 | 剔除理由 |
|---|---|---|
| GTAO + bent normal | `luster.../gtao.glsl:8,22,37,63-64,77-88`（integrate_arc、GTAO_HORIZON_STEPS、bent_normal 输出） | Astra **已有**半分辨率 AO + 每像素 bent normal + 边缘感知重建：`Astra/shaders/lib/ao_resolve.glsl:13-52`、以及用 bent normal 换 SH 天光（`global/lighting/diffuse.glsl:425-427,493`）。差异只在"地平线弧积分 vs Astra 现有估计器"与参数，不构成机制缺口。 |
| 邻域 AABB 时域钳制 | `taa/shaders/bsl_lib/antialiasing/taa.glsl:65-96`（8 邻域 min/max + 速度指数混合） | Astra 的 TAA（`program/taa_resolve.fsh:39-42,135-154`）已有 gathering AABB + reactive + 逐贡献者校验，比这套更严。 |
| 8 帧抖动序列 | `anti-aliasing/shaders/lib/jitter.glsl:3-17`、`taa/shaders/bsl_lib/util/jitter.glsl` | Astra 已有 TAA 抖动（`taa_resolve.fsh:88-90` `astra_jitter_uv()`）。该包无 FSR/EASU/RCAS（grep = 0），整包=TAA+锐化，无新机制。 |
| RSM GI | `muuf-a.g.i-shaders/shaders/MuufLib/lighting/GlobalIllumination.glsl:1-3`（`CalcRSM`）、`InternalLib/Deferred0.glsl:258-272` | **功能未完成且默认关闭**：`MuufLib/settings.glsl:209-210` 原文 `//#define RSM // this feature isn't done yet, still have a bug!`。不作为建议。 |
| 棋盘格阴影采样 | `lumeau/shaders/lib/shadow.glsl:25-32`（`shadow_checkboard`） | **死代码**：调用点被注释掉 —— `lumeau/shaders/deferred.fsh:40` 原文 `//if (shadow_checkboard(viewPos))`。不作为建议。 |
| FSR 锐化选项 | `wispy-shader/shaders/lang/en_US.lang:137`（`option.FSR_SHARPNESS`） | 属已否决方向（FSR）。 |
| 世界弯曲 | `tilde/shaders/lib/effect.glsl`(211 行) | 属已否决方向（世界弯曲）。 |
| TAA_SELECTIVE（实体/粒子/手不做时域） | `prismarine-shader/shaders/lang/en_US.lang:721-722`、`lib/settings.glsl:236`（默认注释掉）、`program/composite7.glsl:28`、`gbuffers_entities.glsl:326-338` | 与 Astra 已有 reactive/colorTrust 机制重叠，且会让实体边缘失去 TAA；默认不启用。低价值。 |
| TAA_MODE 0/1（速度混合 vs 固定 0.5） | `verlixia.../taa.glsl:164-179` | 固定 0.5 混合是更弱的方案；Astra 现有混合率已更细（`taa_resolve.fsh:146-154`）。 |
| 廉价 SSR | `crumb/shaders/lib/config.glsl:31-34`（`REFLECTION_SLIDER 0` "Flipped image: Inaccurate but quick"） | Astra 已有反射/水面折射链（`Astra/shaders/program/nether_reflection_resolve.fsh` 等），且该做法是低质量近似。 |
| resize / 分档调度（通用） | 全批：只有 artshade(8)/velocity(3+12)/motion-blur-fx(3)/crumb(1)/muuf(1) 用 `program.*.enabled` | **不是缺口**：Astra 已有 `program.*.enabled`（`shaders.properties:106,109,117,120,127,132,140,143`）和大量 `size.buffer` 分档（`:152-164` AO 半分辨率、`:18-26` 散射 0.25/0.5/1）。velocity 的 SMAA 用 `program.*/composite9-11.enabled=SMAA` 只能算 C2 的实现细节。 |

## 4. 与旧结论冲突及新证据

1. **与 `shader_research/SUMMARY-batch5.md` §⑨13 的"velocity 的 `shadow_fade`/`get_shadow_static` 没有调用点、README 承诺的阴影末端淡出不存在"冲突。**
   **新证据（读源码）**：`velocity-shaders/shaders/global/lighting.glsl:172` 调用 `shadow_fade(PlayerPos, shadowDistance)`；`:174-185` 用 `Fade` 分别在 `<1.0`/`>0.0` 分支调 `get_shadow_dynamic` 与 `get_shadow_static`，并有 `Shadow = mix(ShadowD, ShadowS, Fade)`；`:206`（`DYNAMIC_SHADOWS==0` 分支）再次调用 `get_shadow_static`。`get_shadow_static` 另有定义处 `global/shadows.glsl:26-31`。→ 旧结论为误判（当时可能只在该文件内搜索）。
2. **与 `SUMMARY-batch5.md` C03 把 SMAA 记为"Astra 卡在 colortex7"相关的含义冲突**（§⑧ 已承认"不引入 SMAA 的书面理由已过时"）。
   **新证据**：velocity 的 SMAA 是**完整可用**三 pass 实现且用选项名挂在 `program.*.enabled`（`shaders.properties:60-71`），并自带 area/search 纹理（`:28-29`），不需要 Astra 的 colortex7；`smaa-mc` 还给出了额外的 LCA/对角/角点参数。→ 现在应当把它当作**可实施候选**而不是"卡死的旧结论"。
3. **与"Astra 已用体素光解决方块光遮挡、无需屏幕空间遮挡"的隐含假设冲突**（下界确实有体素光，但主世界没有）。
   **新证据**：`Astra/shaders/global/lighting/blocklight.glsl` 对 `occlu|gradient|depth_|screen.?space` **0 命中**；Astra 全库 `blocklight_|blockLightShadow|torch.?shadow` 的 9 条命中里没有屏幕空间遮挡，且下界体素光受 `NETHER_VOXEL_LIGHT` 与维度限制（`global/dimension/nether.glsl:172-184`）。velocity 的 `deferred1.fsh:88` 证明该机制在**主世界**每像素生效。→ 主世界方块光遮挡是真实缺口。

## 5. Astra 现状基线（本轮实测，含关键词与命中数）

对 `Astra/shaders` 的检索（caseInsensitive，`ops_grep`）：
- `sspt` = 0；`ssgi|screen.?space.?gi` = 0；`svgf|atrous|bilateral` = 0；`gtao|hbao` = 0
- `SMAA` = 0；`\blca\b` = 0；`catmull` = 0；`histogram|percentile|cdf` = 0；`localExposure` = 0；`bicubic` = 0；`equirect|stereographic` = 0；`shadow_fade` = 0；`floodfill` = 0
- `\bvariance\b` = 3（**全部是注释，且与 TAA 无关**：`global/dimension/overworld.glsl:49`、`global/water/caustics.glsl:11`、`program/nether_reflection_resolve.fsh:57,64,72`）
- `bent.?normal` = 10（**已有**：`lib/ao_resolve.glsl:13-52`、`global/lighting/diffuse.glsl:425-427,493`）
- `cloud_shadow` = 15（**已有**：`global/atmosphere/cloud_shadow_cache.glsl`、`program/cloud_shadow_cache.fsh`）
- `imageAtomic|image3D|sampler3D` = 11（**已有**：`program/shadow.vsh:45-49,91`、`program/nether_light.csh:13-19`）
- `blocklight_|blockLightShadow|torch.?shadow` = 9（有强度/抑制/下界体素光，**无**屏幕空间遮挡）
- `corner` = 27（**与 SMAA 角点无关**，是几何拐角/角落语境；因为 `SMAA`=0，可判定不存在 SMAA 角点圆化）

其他已确认的 Astra 基建（用于判断"是不是缺口"）：`global/post/fxaa.glsl`（FXAA）、`program/taa_resolve.fsh`（TAA：gather AABB + 逐贡献者校验 + reactive + 非抖动历史）、`lib/settings.glsl:276-277`（ANTIALIASING 互斥档）、`shaders.properties:106-143`（`program.*.enabled`）、`shaders.properties:18-26,152-164`（`size.buffer` 分档）、`global/atmosphere/cloud_temporal.glsl` 与 `global/water/temporal.glsl`（云/水的时间重投影）。

## 6. 未验证项（明确不知道）

- luster 的 `HISTOGRAM_*` 直方图统计**具体实现文件与行号**未定位（只在 `lang/en_US.lang:1110-1115` 找到选项文案），机制描述属〔推断〕；若要用，需先在 `luster-shaders/shaders/include/` 里定位实际统计代码。
- `luster d6_sspt_filter` 的"实例化五次"来自文件头注释（`:5`），**没有**在 `shaders.properties` 里逐一核对五次 dispatch 的具体声明（只确认了 `deferred4/5.enabled = ssptEnabled`）。
- ~~velocity 边缘检测 pass 未逐行读~~ **已补读**：`composite9.fsh`(45 行)、`composite10.fsh`(67 行) 全文已读，见 C2 三个消费者（注意 `composite10.fsh:7` 也声明 `SmaaEdges`，因为两个 pass 轮流覆写同一张 colortex2）。仍未做：SMAA 在远处/高对比度场景的实际效果对比（没有运行验证）。
- lantern-shader / raincore 的景深（`lib/dofoffsets.glsl`）与 Astra 现有 DOF/散景的重叠程度**未核实**（本轮没有检索 Astra 的 DOF 实现），故只列为"未发现机制级新做法"。
- crumb 的 `fast_taa.glsl`(186 行) 与膨胀云、SSR 未逐行读；仅由 `config.glsl:31-34` 判定其反射为可切换的低质量近似。
- artshade 的 `ss_shadow.glsl`(148)/`shadow_filter.glsl`(139) 未读；它在本轮只被用于确认"program.enabled/size.buffer 分档不是缺口"。
- prismarine 与 truelightfx 的 118 个 .glsl 文件数量相同但 `lib/antialiasing/taa.glsl` 的 md5 不同（`119ae4d…` vs `494847c…`），**未**做全量 diff，无法断言"完全同源"。
- `aquarium` 只确认目录结构（`data/` + `pack.mcmeta`，无 `shaders/`）与 0 个着色器文件，**未**读 `data/` 内部内容。
- 所有性能结论（"半分辨率够不够快""显存多少"）都是按分辨率与格式估算的〔推断〕，**没有**在任何 GPU 上实测。

## 7. 跳过包与许可口径（逐包）

许可原文摘录均来自包内 LICENSE/README（`node _analysis/lic.js` 逐包读取，行号给的是摘录所在文件）。

| 包 | 处置 | 包内许可原文要点 |
|---|---|---|
| velocity-shaders | **深挖（C2、C5、C11）** | `LICENSE:1-2` MIT，"Permission is hereby granted, free of charge ... without restriction"；README:1 说明是 mellow 的分支 |
| luster-shaders | **深挖（C1、C7、C8、C9、C10）** | `LICENSE:12` 允许 "Examine and learn from Luster Shaders's source code"；`:17-25` 禁止未获书面许可再分发/发布衍生作品；`:33` 声明基于 Photon，Photon 部分走 Photon 许可 |
| escheridia | **深挖（C4）** | `LICENSE:1-2` MIT（Copyright (c) 2025 jrwilliamson）；`shaders/voxels.glsl:2-10` 第三方声明：体素化来自 timetravelbeard 教程，"feel free to use this code in any shaders"（保留头部） |
| smaa-mc | **深挖（C3）** | `LICENSE:1-3` MIT（2024-2026 Luracasmus） |
| kute | 仅取其 Catmull-Rom 取样（C6） | `LICENSE:1-2` MIT（2025 James） |
| verlixia | 仅参考（C6），无许可 | **无 LICENSE/README**；与本包结构几乎一致的 prismarine 同样无许可 → 默认保留所有权利，**不可借用代码** |
| truelightfx | 仅参考 | `LICENSE.md:1-3` MIT（2021 Septonious / 2026 TrueLightFX） |
| prismarine-shader | 仅参考 | **无 LICENSE/README** → 默认保留所有权利 |
| muuf-a.g.i-shaders | 剔除（RSM 未完成） | `README.md:8` "You can't: distribute this shader without my permission"；`:9` 说明使用了其他光影的函数（见 credit.txt）→ 非自由许可 |
| fantasy-shader-unbound | 跳过 | `License.txt:1` "Complementary License Agreement 1.5"（自定义许可，条款严格）→ **不可代码级借鉴** |
| artshade | 跳过（已有旧结论覆盖其调度部分） | `LICENSE.txt:1-6` "All rights reserved"，只允许个人游戏/视频/截图等用途（"PERMITTED USE" 段） |
| the-better-default | 跳过 | **无 LICENSE/README**；其 `blocker` 相关命中（`gbuffers_terrain.fsh:45-79`、`gbuffers_entities.fsh:31-53`）是**半透明遮蔽体着色（彩色阴影/透射）**，Astra 的彩色阴影链已在别处覆盖，本轮未作为候选 |
| taa | 跳过（C7 对照） | `License.txt:1` "Licensed MPL-2.0"；README:1 "Hardfork of VanillAA" |
| anti-aliasing | 跳过 | **无 LICENSE/README**；无 FSR/EASU/RCAS 命中 |
| lumeau | 跳过（棋盘格是死代码） | `LICENSE:1-2` MIT（2025 Neoz30） |
| crumb | 跳过 | **无 LICENSE/README** |
| highframes-plus | 跳过（机制薄：只有基础 shadow/deferred/composite） | `LICENSE:1-3` CC BY 4.0，"Adapt … even commercially"（须署名） |
| realisticallyoptimized | 跳过（卡通化，`lib/shadows.glsl` 仅 32 行） | `LICENSE:1-2` MIT（2026 Bitupan Borah） |
| relumination | 跳过（18 个文件，灯色/调色为主） | `LICENSE:1` GPLv3 |
| lantern-shader | 跳过（景深/抖动观感滤镜） | `LICENSE:1` GPLv3 |
| raincore | 跳过（同上，结构与 lantern 同源） | `LICENSE:1` GPLv3 |
| tilde | 跳过（世界弯曲，已否决） | `README.md:1-4` 只有说明（"only modifies the geometry…"，Iris 1.21.4），无 LICENSE |
| wispy-shader | 跳过（Mellow 血统 + FSR 选项） | `LICENSE:1-3` MIT（2025 TheCMK / 2026 l_aggy）；README 说明基于 Mellow |
| terders-potato-shader | 跳过 | `README.txt:1-3` 只有安装说明，无许可条文 |
| essentials-shader | 跳过（轻量整合，无独立机制） | `README.md:1-2` 只有一句描述，无许可条文 |
| wither-rose | 跳过（调色板/像素化观感） | `LICENSE:1` GPLv2；README 讲配色风格 |
| aquarium | 跳过（**不是光影包**：无 `shaders/`，只有 `data/` 与 `pack.mcmeta`，0 个着色器文件） | 包内无许可文件 |
| body-camera-shader | 按任务要求快速跳过（纯主题滤镜） | 无许可文件 |
| cursed-fog | 快速跳过（同上） | 无许可文件 |
| ctrvcr | 快速跳过（复古整活） | `LICENSE:1` Apache 2.0（`README.md` 为 Modrinth 介绍） |
| ch-motion | 快速跳过（单功能） | 无许可文件 |
| thunders-mb | 快速跳过（单功能动态模糊） | `LICENSE:1` CC BY-NC-SA 4.0（**禁止商业**） |
| motion-blur-fx | 快速跳过（单功能动态模糊） | `README.md:1-4` 说明"无历史缓冲"，无许可条文 |

## 8. 一句话总结

第五批 33 包里真正值得动的机制集中在三个包：**luster 的 SSPT 屏幕空间 GI + SVGF 降噪 + 方差自适应时域累积**（Astra 完全没有 GI/降噪，代价最高）、**velocity/smaa-mc 的完整空间 SMAA（后者还带 LCA/对角搜索/角点圆化）**（Astra 只有 FXAA+TAA，可行性最好）、以及**escheridia 的多帧体素 floodfill**（Astra 的同帧体素光明确写了"no history"，是机制差异但要重开已被权衡过的历史方案）。主世界火把光的屏幕空间遮挡（velocity）是成本最低的真实缺口。
