# Ebin Resurrected v1.5.6 研读报告（Astra 视角）

> 研读对象：`reference_shaderpacks/ebin-resurrected/`（下文相对路径省略该前缀，行号以本地副本为准）。
> 本报告只读参考包与 `Astra/shaders/`，不改动任何源文件。

## ① 包概览

- **版本**：v1.5.6，lang 内置版本开关给出 `v1.5.6` 与 commit hash `7cc017c…`（`shaders/lang/en_US.lang:400-401`）。
- **作者**：原版 Ebin 出自 Bruce（`shaders/lang/en_US.lang:96` 注释提及 "Bruce's version of Ebin"）；Resurrected 续作维护者在包内**无署名证据**，不编造。
- **许可证**：包内 `LICENSE.md:1-4` 实际是 **GPLv3 全文**（"GNU GENERAL PUBLIC LICENSE Version 3"），全文 674 行、无 Affero 字样。任务契约所称 "AGPL-3.0-only" 与包内证据**不一致**（见备注 1）。两者义务差异对 Minecraft 光影分发几乎不影响：AGPL 多出的 §13 网络交互条款只在"用户通过网络与修改版交互"时触发供源义务，而光影包是静态文件分发，实践中义务与 GPLv3 相同——**提供源码、保留许可与版权声明、显著标注修改**（GPLv3 §5a/5b，即 LICENSE.md 内 "modified versions be marked as changed" 段）。
- **风格定位**：Chocapic13 血统的现代重制（无 TAA、IGN/蓝噪声单帧去噪），物理大气 + RSM GI + compute floodfill 彩色方块光 + 3D 云 + PCSS，默认 ACES 色调映射（`shaders/lang/en_US.lang:388` 注释："Modern versions of Ebin use the ACES tonemap"）。
- **组织结构**：`program/` 放共享实现，`world0/-1/1/` 只做 7 行薄壳（如 `shaders/world0/composite2.fsh:1-7` 定义 `WORLD_OVERWORLD` 后 include `/program/composite2.glsl`；下界复用同一套 composite0-3，`shaders/world-1/composite.fsh:4` 仅改 `WORLD_THE_NETHER`）。算法集中在 `lib/Fragment/*.fsh`。
- **档位**：POTATO→ULTRA 五档，全部由 `shaders/shaders.properties:39-43` 的 profile 定义（GI/AO/VL/caustics/floodfill 在 LOW 及以下全关，MEDIUM 只开 bloom，HIGH/ULTRA 全开）。

### 特性开关地图（settings 与菜单）

- GI/AO/VL 总开关与质量：`shaders/lib/Settings.glsl:99-103`（`VL_QUALITY 8 // [8 16 32 64]`）。
- GI 参数：半径/样本/半透/增亮在 `shaders/lib/Settings.glsl:106-110`（`GI_SAMPLE_COUNT 40`）。
- Bloom：`shaders/lib/Settings.glsl:112-114`（`BLOOM_AMOUNT 0.2`、`BLOOM_CURVE 1.5`）。
- floodfill 彩光：`shaders/lib/Settings.glsl:200` 定义 `FLOODFILL_BLOCKLIGHT`，`:202-204` 组合出 `SHADOWCOMP_ENABLED`；启用后由 `shaders/shaders.properties:97-99` 对三个维度的 shadowcomp 程序统一放行。
- 半分辨率 composite0：`shaders/lib/Settings.glsl:132`（`COMPOSITE0_SCALE 1.0 // [0.25 … 1.00]`），并在 `shaders/lib/Settings.glsl:134-136` 派生 `COMPOSITE0_ENABLED`。
- FXAA：`shaders/lib/Settings.glsl:206-208`。水面：caustics/refraction/可变波高在 `:154-160`。

## ② 架构与特性清单

### 管线骨架

composite0（可缩放分辨率：GI+AO→colortex5，VL→colortex6，`shaders/program/composite0.glsl:142` `/* RENDERTARGETS:5,6,12 */`）→ composite1（双侧上采样、延迟着色合成、3D 云，`shaders/program/composite1.glsl:167`）→ composite2（反射/折射/雾/云合成）→ composite3（Bloom 瓦片）→ final（FXAA/动态模糊/Bloom 应用/tonemap）。

### Colored light / 体积光

1. **compute floodfill 彩色方块光**：`shaders/program/shadowcomp.glsl:6-7` 用 `local_size 8×8×8`、`workGroups 16×8×16` 铺满 128×64×128 体素；`shaders/program/shadowcomp.glsl:69-78` 对 6 邻域取平均再乘 0.99 衰减（防正反馈），低于阈值清零。
2. **发光体注入在 shadow pass 顶点阶段**：`shaders/program/gbuffers_shadow.glsl:171-185`——`IPBR_EMITS_LIGHT(materialIDs)` 的方块用 `at_midBlock/64` 定位，`imageStore` 写入体素图：

   ```glsl
   if(IPBR_EMITS_LIGHT(materialIDs)){
       ivec3 voxelPos = mapPreviousVoxelPos(previousPosition + at_midBlock * rcp(64.0));
       if(isWithinVoxelBounds(voxelPos)) {
           vec3 lightColor = getLightColor(int(materialIDs));
   ```

3. **双缓冲 ping-pong**：`lightvoxel`/`lightvoxelf` 两张 RGBA16F image3D（`shaders/shaders.properties:32-33`），读偶帧写奇帧（`shaders/program/shadowcomp.glsl:24,86-90`），避免同帧读写竞争。
4. **相机重锚定**：网格以 `fract(cameraPosition)` 对齐亚格，网格随相机的整格位移用 `getPreviousVoxelOffset()` 平移扩散源（`shaders/lib/Voxel/VoxelPosition.glsl:6-8,28-30`）。
5. **光色表**：`shaders/lib/iPBR/lightColors.glsl:10-74` 按 iPBR ID 给 25+ 类发光方块配色；**该表注明取自 Complementary by Emin**（`shaders/lib/iPBR/lightColors.glsl:3-4` 给出 GitHub 链接）。
6. **着色采样**：`shaders/lib/Fragment/ComputeShadedFragment.fsh:157-176` 以 `sampler3D` 三线性插值采样体素色，取 `normalize()` 后只保留色相，强度仍走 vanilla lightmap 曲线（`:124` `2 * pow(torchlight, 5.06)`），出界/全黑回退单色 `torchColor`。
7. **手持光**：compute 端在网格中心注入手持光色（`shaders/program/shadowcomp.glsl:29-43`），着色端另有屏幕空间近似 `GetHeldLight`（`shaders/lib/Fragment/ComputeShadedFragment.fsh:26-48`）。
8. **阴影空间 VL**：`shaders/lib/Fragment/ComputeVolumetricLight.fsh:36-49` 把视线段投影到阴影图空间后按样本数**分层段**（每样本只在自己那 1/n 段内抖动）；`:52-75` 用硬件阴影比较器分离不透明/半透明遮挡，并单独累计**水阴影通道**；`:33` 限距 128 格。结果写 colortex6（`shaders/program/composite0.glsl:182-183`）。

### 水体

9. **4 层 FBM 波高**：`shaders/lib/Fragment/ComputeWaveNormals.fsh:25` 定义四层高度权重，`SetupWaveFBM`/`GetWaves` 在 `:42,56,91`；波法线在 gbuffers 内生成。
10. **解析焦散走阴影图 alpha**：`shaders/program/gbuffers_shadow.glsl:232-240` 在 shadow.fsh 里把水面片元 alpha 调制成焦散强度（`height*height*height*height` 后 `pow2`），后续 GI/VL 采样 shadowcolor0 时自然带焦散。
11. **SSR 与折射**：水面反射调用 `ComputeSpecularLighting`（`shaders/program/composite2.glsl:235-237,282-284`）；折射用 `ComputeSSRaytrace` 折射步进重定位背景色（`shaders/program/composite2.glsl:190-209`），水下雾 `waterdepthFog`（`:274-288`）。
12. **BIOME_WATER_TINT**：水色混合系数可调（`shaders/lib/Settings.glsl:159`；shadow 端使用 `:233`）。

### 大气 / 云

13. **Bruneton 预计算大气 LUT**：`shaders/shaders.properties:23-24` 把 `atmosphere.bin` 挂成 256×128×33 RGBA32F 的 TEXTURE_3D（colortex7）；`shaders/lib/Fragment/PrecomputedSky.glsl:17-63` 保留 Bruneton 参考实现的层化密度剖面结构（619 行）。
14. **实时单次散射兜底**：`shaders/lib/Fragment/ComputeAtmosphericSky.fsh:30-35`（`iSteps = 23` 主射线步进）。
15. **每帧派生日/天光颜色**：阳光色由大气透射率直接算出（`shaders/lib/Vertex/Shading_Setup.vsh:24-27`）：

    ```glsl
    sunlightColor = 7.0 * transmit + CalculateNightSky(sunVector, fakeTransmit) * 7.0 * (1.0 - timeHorizon) * isNight;
    skylightColor = SkyAtmosphere(normalize(vec3(0,1,0)), transmit) * 0.5 * mix(1.0, 0.5, biomePrecipness);
    ```

16. **3D 云**：`shaders/lib/Fragment/3D_Clouds.fsh`（318 行），光照模式三档（`:208-210` `#if CLOUD3D_LIGHTING == 1/2/3`），入口 `CalculateClouds3`（`:281`）；云渲染到 colortex5 并压缩存储 `sqrt(cloud.rgb/50)`（`shaders/program/composite1.glsl:221-224`），合成时对纯天空像素用 `textureGatherOffsets` 判定后走 `textureLod(VolCloudLOD)` 降采样（`shaders/program/composite2.glsl:261-265`）。
17. **群系天气平滑**：`shaders/shaders.properties:84-94` 用 `smooth(…, 100, 100)` 把降雨/群系可降水调成 100s 半衰期 uniform（biomeWetness 等）。

### 阴影与光照

18. **PCSS 变焦半影**：blocker search + Vogel 盘采样（`shaders/lib/Fragment/ComputeSunlight.fsh:12` `VogelDiscSample`、`:98,107` blocker search 参数、`:126-144` 半影循环）；参数在 `shaders/lib/Settings.glsl:80-85`。
19. **SSS**：`shaders/lib/Fragment/ComputeSunlight.fsh:29-44` `ComputeSSS` 用 blocker 距离做透射散射。
20. **RSM GI**：`shaders/lib/Fragment/ComputeGI.fsh:51-80` 直接从阴影图采反射率 GI——深度取 `shadowtex1` 的 mip（`:60`），通量取 `shadowcolor0`（`:75`），法线藏在 `shadowcolor1`（`:67`），`:54` 用 `dot(offset.xy, normal.xy)` 做伪半球剔除；样本表按档位预生成（`shaders/lib/Samples/GI.glsl:1`）。
21. **SSAO**：双距离采样（r 与 0.25r）+ Hammersley 盘，`shaders/lib/Fragment/ComputeSSAO.fsh:11-15`（默认仅 6 样本）。
22. **阴影图裁剪**：`shaders/program/gbuffers_shadow.glsl:102-141` `CullVertex` 对屏幕外且不投屏进光锥的顶点做位移裁剪；floodfill 开启时 `shadow.culling=reversed`（`shaders/shaders.properties:17-18`）。
23. **z 域收缩**：`zShrink=4`（`shaders/lib/Settings.glsl:63`）压缩阴影深度域以缓解远影丢失（`shaders/program/gbuffers_shadow.glsl:89`）。
24. **光照去饱和混合**：按各光源强度把 albedo 往亮度色拉，避免夜间/火光下过饱和（`shaders/lib/Fragment/ComputeShadedFragment.fsh:194-198`）。
25. **紧凑 G-buffer**：法线按位数打包（11-bit），4 通道打包工具在 `shaders/lib/Utility/encoding.glsl:58-78`（`Encode4x8F/Decode4x8F` 在 `:1,7`）。

### 后处理（Bloom 管线）

26. **单 pass Bloom 瓦片法**：colortex3 开 mipmap，`shaders/program/composite3.glsl:54-90` `ComputeBloomTile` 在 `Lod = log2(scale)` 上做 `cubesmooth` 伪高斯加权（`:78-80`）；`shaders/program/composite3.glsl:92-102` 叠 7 档（scale 4→256），顶点着色器把全屏三角形裁剪到实际用到的一角屏幕（`:21-25`）。
27. **Bloom 应用与曲线**：final 里逐瓦片读回、平均后套 `BLOOM_CURVE`（`shaders/program/final.glsl:154-178`），与 FXAA、动态模糊、vignette、tonemap 串联（`:198-202`）。
28. **四算子 tonemap**：`shaders/lib/Fragment/Tonemap.fsh:7-13` ACESFitted/Burgess/Uncharted2/Reinhard 切换，ACES 矩阵在 `:97,104`。
29. **FXAA 3.11**：`shaders/lib/Fragment/FXAA.glsl`（176 行），`:159` 仅为 TAA 预留的分支宏。

### 性能与时域

30. **无 TAA**：全包检索无 TAA 实现（`shaders/lib/Fragment/FXAA.glsl:159` 的 `#ifdef TAA` 是死分支）；GI/AO/VL 的单帧噪声靠 IGN 抖动（`shaders/program/composite0.glsl:153-157`）+ 上采样 mip 模糊压制。
31. **半分辨率复用**：composite0 顶点直接按 `COMPOSITE0_SCALE` 缩放（`shaders/program/composite0.glsl:42`）；composite1 用法线+深度双侧上采样恢复（`shaders/lib/Fragment/BilateralUpsample.fsh:5`），GI/AO 读 mip1、VL 读 mip3（`:55`），两张图开 mipmap（`shaders/program/composite1.glsl:70-78`）。
32. **floodfill 摊帧**：每帧只跑 1 次 1-邻域扩散 compute（≈20 格/秒传播），靠**跨帧累积**换取低成本大范围传播；代价是光源变化有延迟（`shaders/program/shadowcomp.glsl:53-93`）。
33. **半透明阴影**：`TRANSPARENT_SHADOWS`（`shaders/lib/Settings.glsl:79`）+ 硬件采样器分离（`IRIS_FEATURE_SEPARATE_HARDWARE_SAMPLERS`，`shaders/program/composite0.glsl:74-77`）。

33. **半透明阴影**：`TRANSPARENT_SHADOWS`（`shaders/lib/Settings.glsl:79`）+ 硬件采样器分离（`IRIS_FEATURE_SEPARATE_HARDWARE_SAMPLERS`，`shaders/program/composite0.glsl:74-77`）。
34. **末地星门**：`shaders/lib/Fragment/EndPortal.fsh:1` `CalculateEndPortal` 用两层噪声叠加造紫色星点；末地环境光在着色端单独提亮（`shaders/lib/Fragment/ComputeShadedFragment.fsh:137-139` 末地 `ambient *= 3`）。
35. **下界处理**：复用同一 composite 链，仅切宏；下界无日/天光（`shaders/lib/Fragment/ComputeShadedFragment.fsh:134-136` 下界 ambient 提到 `clamp(…, 0.05, 1.0)`），VL 直接短路返回（`shaders/lib/Fragment/ComputeVolumetricLight.fsh:9-11`）。

| # | 技术描述 | 包内出处 | 对应 Astra 模块 | 迁移难点 |
|---|---|---|---|---|
| 1 | **floodfill 彩光推广到主世界**（专项 a）：Ebin 的体素彩光本就三维度统一启用，主世界方案=shadow 顶点注入 + compute 单步扩散 + 双缓冲 + 相机重锚定 + 手持光中心注入，规模 128×64×128 RGBA16F×2 | `shaders/program/shadowcomp.glsl:53-93`；`shaders/program/gbuffers_shadow.glsl:171-185`；`shaders/lib/Voxel/VoxelPosition.glsl:6-8` | `Astra/shaders/global/dimension/nether_colored_light.glsl`（目前仅下界）；其网格常量在 `Astra/shaders/lib/nether_voxel_grid.glsl` | **中**。Astra 现有链路（shadow.vsh 捕获占据 + `program/nether_light.csh` 扩散，`lib/nether_voxel_grid.glsl:5-6`）结构与 Ebin 同构，主要差异是 Ebin 持久累积跨帧传播 vs Astra 同帧重建：改持久化需补相机重锚平移、双缓冲与边界清空逻辑；Iris 侧需 `IRIS_FEATURE_CUSTOM_IMAGES`（Astra 已用 custom image 采样，具备） |
| 2 | **Bloom 瓦片法**（专项 c）：单 pass 读 mipmap 链出 7 档瓦片（Astra 现为 capture 0.25x + 13-tap 下采样 + 4 mip 合成，5 档），且是 GPL 可合法改编 | `shaders/program/composite3.glsl:54-102`；`shaders/program/final.glsl:154-178` | `Astra/shaders/global/post/bloom.glsl`（`bloom.glsl:10-12` 自标 PROVENANCE=Refrax 派生、REWRITE REQUIRED）；消费端 `Astra/shaders/global/water/bloom_capture.glsl:7`、`bloom_resolve.glsl:4` | **低-中**。把 bloom_composite 的 mip 采样换成瓦片函数即可；建议保留 Astra 的软膝预滤波与 firefly clamp（Ebin 无预滤波，`composite3.glsl:84` 直接 pow2.2 采样），混血结构需重新调 BLOOM_AMOUNT/CURVE |
| 3 | **阴影空间 VL**（专项 b）：分层段抖动 + 半透明/水双通道阴影 + 硬件比较器，可产生染色玻璃彩色光柱与水面独立阴影通道；GPL 可改编 | `shaders/lib/Fragment/ComputeVolumetricLight.fsh:36-84` | `Astra/shaders/global/post/godrays.glsl`（屏幕空间 depth-march，Steadfast 派生）；下界密度体积 `Astra/shaders/global/dimension/nether_volume.glsl`（Bliss 派生，`:4-5`） | **中**。与 Astra 现有屏幕空间径向 godrays 是两条路线：阴影空间法不依赖太阳在屏内、天然支持彩色透射，但受 shadowDistance 限制（Ebin 限 128 格）；Astra 有 TAA 历史，需把 Ebin 的 IGN 单帧抖动接入 Astra 的时域累积而非裸输出 |
| 4 | **RSM GI**：从阴影图直接取通量/深度/法线做半球采样，与 Astra 已有的彩色阴影 shadowcolor 输出天然兼容 | `shaders/lib/Fragment/ComputeGI.fsh:51-80`；样本表 `shaders/lib/Samples/GI.glsl:1`；通量来源 `shaders/program/gbuffers_shadow.glsl:230-244` | Astra 无 GI（方向性天光用 SH9）；AO 为屏幕空间（对照 `Astra/shaders/global/lighting/`） | **高**。需要 shadowcolor0 输出通量、shadowcolor1 藏法线（Ebin 的 11-bit 法线藏法在 `shaders/lib/Utility/encoding.glsl:78`），Astra 影图布局不同要重排；40 样本半分辨率在无 TAA 的包里靠 mipmap 压噪，Astra 可借 TAA 收敛但预算要重估 |
| 5 | **PCSS 变焦半影**：blocker search + Vogel 盘 + 半影宽度随遮挡距离缩放 | `shaders/lib/Fragment/ComputeSunlight.fsh:12,98,107,126-144` | `Astra/shaders/global/lighting/shadowmap.glsl`（Steadfast 表达式级移植） | **低-中**。算法本身短小且 GPL 可搬；难点在 Astra 影图畸变（`lib/distort.glsl` 按影距归一）下重推 penumbra 的格距换算（Ebin 用 `penumbraWidthBlocks / shadowDistance`，见 `ComputeSunlight.fsh:129` 附近） |
| 6 | **光照去饱和混合**：按光强把 albedo 混向亮度色，压夜间过饱和；纯表达式，风格收益 | `shaders/lib/Fragment/ComputeShadedFragment.fsh:187-198` | Astra 着色合成链（`Astra/shaders/global/lighting/`） | **低**。无依赖，可直接试参数 |
| 7 | **焦散写进阴影图 alpha**：shadow.fsh 里用波高调制水面片元 alpha，GI/VL/焦散采样一次拿到 | `shaders/program/gbuffers_shadow.glsl:232-240` | `Astra/shaders/global/water/caustics.glsl`、`global/lighting/shadowmap.glsl` | **低-中**。思路可移植；Astra 影图 alpha 已有其他用途则需挪通道 |
| 8 | **群系天气 100s 平滑 uniform**：`smooth(if(biome_precipitation==…))` 造 biomeWetness 等 | `shaders/shaders.properties:84-94` | Astra 雨湿地面（`shaders/lib/wet_material.glsl` 及相关 uniform） | **低**。几行 properties；Astra 已有类似湿度的需确认是否已带平滑 |

**不建议搬**：`shaders/lib/iPBR/lightColors.glsl` 的配色数值表——上游是 Complementary（专有），Ebin 的 GPL 不会洗白该段（见备注 2）。

## ④ Astra 已有对应实现（对照）

- **彩光**：Astra `global/dimension/nether_colored_light.glsl:13-25`（Solas V3.7b 架构改编，同帧重建、无时域历史、`textureLod` 三线性采样 + 边缘保护，见文件头 `:4-7` 注释）vs Ebin floodfill（持久累积、ping-pong、fract 重锚定）。**优劣**：Ebin 传播半径随帧数增长且每帧只一个 6 邻域 pass，开销极低；Astra 同帧方案改光源即时生效、无拖尾伪影。Ebin 把色与强度解耦（色取 normalize、强度走 lightmap 曲线），Astra 采样直接拿 RGB——不确定 Astra 是否也解耦，需查 `nether_light.csh` 后定论。**能否推广到主世界**：可以，Ebin 本身就是三维度共用（`shaders/shaders.properties:97-99`），Astra 需要的只是把下界那套网格的重建策略换成/叠加持久扩散。
- **体积光**：Astra `global/post/godrays.glsl`（GPU Gems 屏幕空间 depth-march，Steadfast 派生，`godrays.glsl:5-9` 记录 GPL 出处）+ 下界 `nether_volume.glsl`（Bliss 派生密度体积，`:4-5`）vs Ebin 阴影空间分层段 VL（`ComputeVolumetricLight.fsh:36-84`）。**优劣**：Astra 法实现简单、距离不受影距限制；Ebin 法能吃彩色半透明阴影（染色玻璃光柱）且有独立水阴影通道，对屏外太阳不失效。
- **Bloom**（专项 c 对照）：Astra `global/post/bloom.glsl` = capture（0.25x，软膝预滤波+firefly clamp，`bloom.glsl:45` `BLOOM_CAPTURE_SCALE=0.25`）+ 合成 4 mip；Ebin = 7 瓦片、无预滤波、`cubesmooth` 核。**优劣**：Astra 有软膝与防闪烁、且少一张全屏 mipmap 链的带宽；Ebin 档数多、单 pass、核随档位自适应。Astra 的 bloom 模块挂着 Refrax REWRITE REQUIRED，Ebin 是现成的 GPL 替代结构。
- **FXAA**：Astra `global/post/fxaa.glsl`（Arc 派生）vs Ebin `FXAA.glsl`（FXAA 3.11 完整实现）。两边都有；Astra 有 TAA，FXAA 只是末级，维持现状即可。
- **大气/天空**：Astra 物理天空在 `global/atmosphere/`（渐变天空+分时通道，Mellow/Complementary 组织）；Ebin 用 Bruneton 预计算 LUT（256×128×33 3D 纹理）。**优劣**：Ebin 的 LUT 让"每帧日/天光颜色从大气透射率派生"（`Shading_Setup.vsh:24-27`）变得便宜且自洽——这点值得 Astra 参考；但预计算数据的离线生成工具链是额外工程。Astra 天空解析式的具体形式未逐行核对，此处不下结论。
- **云**：Astra 半分辨率平面云+独立时域历史 vs Ebin 2D/3D 云（3D 云画到 colortex5 再 `textureLod` 降采样合成，`composite2.glsl:261-265`）。**优劣**：Ebin 的"纯天空像素才降采样"判定（`textureGatherOffsets`）与 Astra 现有云降分辨率思路同源但更粗；Astra 有时域历史，质量路径不同。不确定 Astra 是否已有同款 gather 判定。
- **阴影**：Astra `global/lighting/shadowmap.glsl`（Steadfast 移植+彩色阴影/焦散接口）vs Ebin PCSS（`ComputeSunlight.fsh:126-144`）。Astra 代码中未检索到 pcss/penumbra/blocker 关键字（lib/、global/lighting/、program/ 的代码行 grep 无命中），**判断 Astra 当前是固定核**；不确定则以上述检索为准。
- **tonemap**：Astra `lib/tonemap.glsl`（glsl-tone-map/BakingLab/MIT 链）vs Ebin `Tonemap.fsh:7-13` 四算子。功能等价，无借鉴必要。

## ⑤ 借鉴可行性：GPL/AGPL 义务的落法

1. **事实先行**：包内 `LICENSE.md:1-4` 是 GPLv3 文本；任务契约写 AGPL-3.0-only。按证据保守处理：**把 Ebin 当作 GPL 家族强 copyleft 源**，义务=分发时（a）随包提供许可文本与版权声明，（b）提供所改编文件的完整源码（GLSL 明文本就随包），（c）显著标注哪些文件被修改过（LICENSE.md "modified versions be marked as changed" 要求）。若上游确为 AGPL-3.0-only，多出的 §13 网络条款对静态分发的光影包不构成额外动作。
2. **与 Astra 现有模式对照**：Astra 已有成熟的 per-file 台账——`Astra/THIRD-PARTY.md:20` 起是"参考包许可事实"表，`:30` 起是逐文件登记表（来源/借用类型/许可/文件头标记四列）；GPL 来源先例是 Steadfast：`lib/distort.glsl`、`global/lighting/shadowmap.glsl`、`global/post/godrays.glsl` 均按"文件头 GPL 声明 + 登记表登记 + 保留 §7 附加条款"处理（`THIRD-PARTY.md:25,55,63` 与 `godrays.glsl:5-9`）。**Ebin 改编文件照抄该先例即可**：文件头写 `Derived from Ebin Resurrected v1.5.6, Copyright (C) <原作者>, GPLv3`（或 AGPL）+ Astra 修改说明，`THIRD-PARTY.md` 许可事实表加一行 Ebin，登记表逐文件登记。
3. **与 MIT 来源的差异**：MIT（Mellow）只需头注；GPL 改编文件**本身必须整体按 GPL 分发**——Astra 目前是"分文件许可"混合体（MIT 段 + GPL 段 + 专有参照段），新增 Ebin 段不改变整体结构，但若未来想把 Astra 整包单许可发布，Ebin 段会强制该许可为 GPL——发布门前需统帅决策（见备注 3）。
4. **污染提醒**：`lightColors.glsl:3-4` 的配色值来自 Complementary（专有许可）；改编 Ebin 其他文件时**不得**连该表一起搬，否则引入 Complementary 许可义务（Astra 对 Complementary 已有单独登记通道，但那是既有登记，不是这次借 Ebin 的理由）。
5. **建议的文件头模板**（沿用 Steadfast 先例格式，参照 `godrays.glsl:5-9` 的写法）：

   ```text
   // Derived from Ebin Resurrected v1.5.6 (upstream license: GPL-3.0 per pack
   //   LICENSE.md; task brief states AGPL-3.0-only — confirm before publish),
   //   source file: shaders/program/shadowcomp.glsl
   // Astra changes: <逐条列出本文件的修改点>
   ```

   同时在 `THIRD-PARTY.md` 参考包许可事实表（`THIRD-PARTY.md:20` 起）加 Ebin 行，登记表加逐文件行；原始许可文本落 `shaders/lib/vendor/ebin-resurrected/`（比照 Mellow 中继的 vendor 目录模式）。

## ⑥ Top5 优先建议（按 提升/工作量 排序）

1. **Bloom 换 Ebin 瓦片法（可直接改编）**：GPL 合法搬运，一步消掉 `global/post/bloom.glsl` 的 Refrax REWRITE REQUIRED 义务，档数 5→7。提升中 / 工作量低——性价比最高。
2. **主世界 floodfill 彩光（可直接改编）**：shadowcomp + shadow 注入 + VoxelPosition 三件套整体搬，Astra 已有下界体素经验做地基；主世界火把/萤石/岩浆彩色渗光是肉眼大提升。提升高 / 工作量中-高。
3. **阴影空间 VL（可直接改编）**：`ComputeVolumetricLight.fsh` 91 行自包含，换取染色玻璃彩色光柱与水阴影通道，接入 Astra TAA 时域历史后质量更高。提升中 / 工作量中。
4. **PCSS 变焦半影（可直接改编）**：算法短小、GPL；在 Astra 畸变影图上重推格距换算即可。提升中 / 工作量低-中。
5. **RSM GI（可改编但改造大）**：上限最高（真实反弹光），但要重排 Astra 影图输出（通量+法线通道）并重估 40 样本预算；建议在 2、3 落地后再评估。提升高 / 工作量高。

## 附：引用自抽查记录

报告完成后重开源文件逐条核对（sed 取行回读），共 47 条全部一致，关键 20 条如下：

| 引用 | 核对结果 |
|---|---|
| `shaders/program/shadowcomp.glsl:6-7` | `local_size 8×8×8` + `workGroups 16×8×16`，一致 |
| `shaders/program/shadowcomp.glsl:78` | `color *= 0.99;`，一致 |
| `shaders/program/gbuffers_shadow.glsl:171-173` | `IPBR_EMITS_LIGHT` + `at_midBlock * rcp(64.0)`，一致 |
| `shaders/program/gbuffers_shadow.glsl:232-234` | 水面 alpha 焦散调制段起点，一致 |
| `shaders/lib/Voxel/VoxelPosition.glsl:3` | `VOXEL_MAP_SIZE ivec3(128, 64, 128)`，一致 |
| `shaders/lib/iPBR/lightColors.glsl:3-4` | "Colour values from Complementary by Emin"，一致 |
| `shaders/lib/Fragment/ComputeGI.fsh:54` | Faux-hemisphere 剔除行，一致 |
| `shaders/lib/Fragment/ComputeVolumetricLight.fsh:84` | `result.y /= waterSamples` 水通道归一，一致 |
| `shaders/program/composite3.glsl:92-95` | `ComputeBloom()` 七瓦片叠加起点，一致 |
| `shaders/program/final.glsl:177` | `BLOOM_CURVE` 应用行，一致 |
| `shaders/shaders.properties:32-33` | `image.lightvoxel(lef)` RGBA16F 128 64 128，一致 |
| `shaders/lib/Settings.glsl:132` | `COMPOSITE0_SCALE 1.0`，一致 |
| `shaders/lib/Fragment/BilateralUpsample.fsh:55` | VL mip3 采样，一致 |
| `shaders/program/composite2.glsl:261-265` | `textureGatherOffsets` + `textureLod(VolCloudLOD)`，一致 |
| `shaders/lib/Vertex/Shading_Setup.vsh:24,27` | sunlightColor/skylightColor 派生行，一致 |
| `shaders/lib/Fragment/FXAA.glsl:159` | `#ifdef TAA` 死分支，一致 |
| `LICENSE.md:1-4` | "GNU GENERAL PUBLIC LICENSE Version 3"，一致（无 AGPL 字样） |
| `shaders/lang/en_US.lang:400-401` | `v1.5.6` + commit hash，一致 |
| Astra `global/post/bloom.glsl:10-12,45` | Refrax PROVENANCE / REWRITE REQUIRED / 0.25，一致 |
| Astra `THIRD-PARTY.md:20,25,30` | 许可事实表 / Steadfast 行 / 登记表，一致 |
