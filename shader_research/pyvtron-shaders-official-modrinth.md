# Pyvtron Shaders V1.3.2 × Astra 可借鉴点调研

- 生成方式：子代理调研（只读包内文件，未修改 `Astra/` 任何文件）
- slug `pyvtron-shaders-official-modrinth`｜作者 Pyvton｜版本 V1.3.2（`P:Changelog.txt:1-5`）｜下载量 310,683
- 许可证：自定义，Modrinth 标记 `LicenseRef-Pyvton-Copyright-Claw-License`（原文 `P:LICENSE.txt`）
- 调研日期：2026-10-02
- 体量实测：174 文件；贴图 46.8 MB（占 ~96%），着色器源码 393.4 KB / 13,044 行（fsh+vsh+glsl，无 `.csh`）
- 引用约定：`P:` = 相对 `reference_shaderpacks/pyvtron-shaders-official-modrinth/`；`A:` = 相对 `Astra/shaders/`；行号全部来自本次实际读取。

## ① 概览

Pyvtron 是"以烘焙资产换运行时计算"的写实向包：全仓 `grep -i cloud` 零命中，主世界天空、云、星空全部来自一张 16384×6144 烘焙全景图集，水面反射复用同一张图（`clouds = off`，`P:shaders/shaders.properties:28`）；代价是 46.8 MB 贴图，其中 `P:shaders/Images/Skyboxes.png` 单文件 39,519,584 B（84%）。管线为前向 + 延迟：G-buffers 写 colortex0/1/2/4，`deferred`/`deferred1` 做水面与 PBR，`composite`→`composite6` 做体积光/运动模糊/反射/bloom，`final` 做 Uncharted2 映射与镜头特效。包自述不再兼容 OptiFine（`P:shaders/shaders.properties:31-95` 逐版本声明），实测依赖 Iris 特性。

### 许可证原文要点（`P:LICENSE.txt`）

| 行 | 要点 |
|---|---|
| 3 | `© 2025 - 2026 Pyvtron - All Rights Reserved` |
| 23 | 禁止换链上传/再分发；只许官方链接；禁付费下载站；**加入合集/整合包/网站须显式许可** |
| 25 | 服务器与启动器一律禁止内嵌（"There are no exceptions"）；光影网站可上传但须署名 |
| 28 | **仅允许个人私用修改**，私有版本不得发布/分享/分发 |
| 31-37 | 公开发布修改版需：显式书面许可（33）、有意义的原创（34）、**同许可**（35）、署名（36）、**禁任何变现**（37） |
| 41 | **跨项目使用代码/效果/贴图须显式许可** + 署名 + 非变现 |
| 44/47/50/52 | 免责；作者保留单方改许可权；视频创作可变现但不得直链且须署名；违者启动版权程序 |

各源文件头部同款声明，例 `P:shaders/Lib/HDR.glsl:5-7`、`P:shaders/Lib/Colors.glsl:5-7`。

### 资产清单（只登记尺寸/用途/采样点，未读二进制内容）

| 资产 | 实测 IHDR | 绑定 | 采样点 |
|---|---|---|---|
| `Images/Skyboxes.png` | 16384×6144，8bit，RGB，39.5 MB | `P:shaders/shaders.properties:189`（`texture.gbuffers.gaux4`） | 天空 `P:shaders/world0/gbuffers_skybasic.fsh:90-97`；水面 `P:shaders/world0/gbuffers_water.fsh:175-182`、`:332` |
| `Images/EndSkybox.png` | 16384×6144，8bit，RGB，9.3 MB | `:190`（`texture.gbuffers.colortex8`） | `P:shaders/world1/gbuffers_skytextured.fsh:19`、`:65` |
| `Images/Noise.png` | 470×470，8bit，RGBA，292 KB | `:188`（`texture.noise`） | `.x` 水波/焦散 `P:shaders/world0/gbuffers_textured.fsh:114-116`；`.a` 水洼 `:297`；`.b` 涟漪 `:308-316` |

三张 `.mcmeta` 均为 `{"texture":{"blur":true,"clamp":false}}`（`clamp:false` = 环绕寻址，是星空按时间旋转 UV 的前提）。

## ② 架构特性清单

**程序链与缓冲**：三世界目录全量复制（world0 25 对、world-1 23 对、world1 23 对 fsh/vsh，共 71 对），共享 `shaders/Lib/*.glsl` 15 个；world0 与 world-1 的 `composite.fsh` 经 diff 完全一致。输出槽位 `P:shaders/world0/gbuffers_textured.fsh:521`（`DRAWBUFFERS:0124`）、水面 `P:shaders/world0/gbuffers_water.fsh:469`（`:01`）、天空 `P:shaders/world0/gbuffers_skybasic.fsh:116`（`:061`，第 3 路写黑清天空材质）、雨 `P:shaders/world0/gbuffers_weather.fsh:55`（`:7`）。缓冲格式声明写在被注释块内（`P:shaders/world0/composite.fsh:28-36`），实际靠 `MAX_COLOR_RANGE = 14.0`（`P:shaders/Lib/HDR.glsl:13`）在读写两端归一化。全局 const：`sunPathRotation -30`（`:38`；末地 -70，`P:shaders/world1/composite.fsh:37`）、`shadowDistanceRenderMul`（`:40`）、`noiseTextureResolution = 1`（`:41`，与 470² 不匹配，见 ⑥）、`centerDepthHalflife`（`:44`）。程序级熔断仅 3 条（`P:shaders/shaders.properties:129-131`）。

**资产驱动天空（主线）**：`projectSky()` 手写立方体展开（`P:shaders/world0/gbuffers_skybasic.fsh:34-60`）：主轴选面 + `dir /= abs(主分量)` + `tileSizeDivide = 0.5*tileSize-1.5` 内缩消接缝，最后 `coord/resolution`；`resolution = ivec2(7680,4320)`（`:36`）仅作比例尺，与真实 16384×6144 仍按 1/4、1/3 分块对应，即 4 列×2 行、每格 4096×3072 的展开立方体（6 面各 1024²），共 8 个时段/天气天空。时段由 `time[]` 权重挑两张 tile 交叉淡化并叠雨/星 tile（`:62-102`），"太阳走位"由全景旋转 `worldTime/24000*5.0`（`:64`）伪装。星 alpha 复用为 `sunVisibility`：`:110-111` 写 `1.0-stars`，`P:shaders/world0/final.fsh:181` 读。水面同源反射见 `P:shaders/world0/gbuffers_water.fsh:325-339`。

**光照与材质**：材质 ID 塞进法线 alpha（`P:shaders/world0/gbuffers_textured.vsh:110` = 0.02 默认；水 0.1 `gbuffers_water.vsh:54`、门 0.17 `:57`、冰/玻璃 0.19 `:59`、半透明植被 0.2 `gbuffers_textured.vsh:165`、自发光 0.3 `:177`），±0.01 容差比较（`gbuffers_textured.fsh:87-95`）。方块表 `P:shaders/block.properties:4-32`、实体 `P:shaders/entity.properties:3-9`、物品 `P:shaders/item.properties:1`。直射+环境合成见 `gbuffers_textured.fsh:498-505`，含伪多次弹射 `bouncedLight()`（`:177-211`，bounce0..9 实为同一 dot 项重复累加）与次表面（`:215-224`）。火炬光解析曲线 `P:shaders/Lib/TorchLightmap.glsl:13-34`。阴影：`shadowDistance 128`/`shadowMapResolution 2048`（`gbuffers_textured.fsh:61-62`）、畸变+透视偏差（`:243-249`）、软阴影 4 tap（`:255-261`）、漏光修正（`:271-273`）。自发光两级门 `P:shaders/Lib/EmissiveLight.glsl:13-27`。低光去饱和 `P:shaders/Lib/LowLightEye.glsl:13-17`。昼夜权重 `P:shaders/Lib/TimeArray.glsl:13-21`（被 `Lib/Colors.glsl:16-35`、`Lib/TorchLightmap.glsl:17` 消费）。风：`gbuffers_textured.vsh:133-144` 按 12 个 block ID 分档，**阴影 vsh 同函数同步位移**（`P:shaders/world0/shadow.vsh:94-105`），阵风包络 `:59-62`。

**水体**：折射 UV 由波法线驱动并随视距衰减（`P:shaders/world0/gbuffers_water.fsh:346-377`）；SSR 450 样本（`P:shaders/Lib/Settings.glsl:76`；步长/细化量同为该常量，`gbuffers_water.fsh:266-270`），首步抖动 `:264`、`:275`，相对容差命中 `:293`，命中取 colortex0 + 边界掩码 `:306-315`；菲涅尔 `:330`；太阳盘解析 `:320-323`。焦散：噪声三向叠加 + 四尺度权重 + `exp(-depth*0.08)`（`gbuffers_textured.fsh:105-142`；水面另有一份常量不同的 `gbuffers_water.fsh:204-222`）。水下三件套 `P:shaders/Lib/UnderwaterFog.glsl:18-42`、`Lib/UnderwaterColor.glsl:17-24`、`Lib/UnderwaterDepth.glsl:13-33`。水体体积光 `gbuffers_water.fsh:379-435`（`while(i<40.0)` 屏幕空间步进）。

**大气与雾**：`P:shaders/Lib/VolumetricFog.glsl:1-58` 固定 `MAX_STEPS 100`/`STEP_SIZE 0.2`（`:3-4`），每步一次 `exp()`，覆盖 20 m；调用点 `gbuffers_water.fsh:452`、`deferred1.fsh:174`。下界/末地各一份复制版（`Lib/NetherVolumetricFog.glsl:14-15,23-59`、`Lib/EndVolumetricFog.glsl:14-15,37-59`），差异仅颜色与高度系数。环境色 `Lib/Colors.glsl:16-35`、下界色板 `Lib/NetherColors.glsl:18-25`。

**后处理链（world0）**：`composite` 预烘体积光遮挡（256 深度比较 → colortex4.a，`P:shaders/world0/composite.fsh:57-87`）；`composite1` 体积光双法并存（径向模糊 10/50/100 或阴影图行进，`:91-108`）+ 水下/失明雾、热浪/雨滴折射（`:165-234`），末尾把太阳像素可见性写 alpha（`:262-264`）；`composite2` 帧反馈运动模糊（`composite2.fsh:41-82`）；`composite3` SSR + 9 tap mip bloom（含未注册 `normaltex`，`composite3.fsh:21-76`）；`composite4` Bayer16（`:21-52`）+ 双向运动模糊（`:58-102`）；`composite5` 9 octave mip bloom + 雾散射合并（`:34-129,132-166`），曝光取 `colortex7.a` 原点（`:173`，来源可疑）；`composite6` 第二次 H 模糊（`composite6.fsh:19,34-65,85-101`）；`final` Uncharted2（`:31-67`）、解析镜头光晕（`:129-205`）、mip 景深（`:211-262`）、mip bloom（`:265-294`）、暗角/彩差/颗粒（`:296-339`）。

**时域/设置/工程**：无 TAA，时域仅两处帧反馈（上一帧矩阵运动模糊、colortex2 bloom 反馈），无历史失效判定。设置：7 档 profile 全量列参（`P:shaders/shaders.properties:197-203`）、13 组菜单（`:211-233`）、slider 一行（`:241`），profile 携带代码中不存在的 `VL_QUALITY`/`WATER_SAMPLES`。DH 按 `IS_IRIS && DISTANT_HORIZONS` 门控（`:139-180`），`dh_*.fsh/vsh` 用新式 `in/out`（`P:shaders/world0/dh_water.fsh:27-32`）。维度兜底 `P:shaders/dimension.properties:14-16`；`P:shaders/world-1/gbuffers_skybasic.fsh:33` 仍是硬编码红色占位。

## ③ 可借鉴点（14 条，工作量：快赢=半天内 / 中=数天 / 大=一周+）

1. **烘焙天空全景集替代运行时云大气**：8 张展开立方体（1024²/面）烘进单张图，运行时只做 UV 旋转 + 两 tile 交叉淡化；`clouds=off` 使包内零云代码。`P:shaders/gbuffers_skybasic.fsh:34-102` + `P:shaders/shaders.properties:28,189`｜`A:global/atmosphere/sky_minishita.glsl:77`、`A:global/atmosphere/clouds_planar.glsl`（413 行 raymarch）｜**大**（成本在美术资产）。**与批次一重复**：②-3"天空缓存增烘含云行"（6 包印证）+ musk-rose 的离线 LUT 预研 → 同方向第 3 次出现。
2. **无 samplerCube 的立方体展开映射**：主轴判决生成面内 UV，一张 2D 图集当 cubemap；内缩 1.5 px 消接缝。`P:shaders/gbuffers_skybasic.fsh:34-60`（DH 侧复制于 `P:shaders/world0/dh_water.fsh:48-51`）｜`A:` 无同类（`A:lib/sky_reflection_cache.glsl:20-29` 为经纬查表）｜**快赢**。
3. **同一天空资产同时服务天空与水面反射**：反射向量直接取天空 tile，SSR 仅在命中时覆盖。`P:shaders/world0/gbuffers_water.fsh:325-339`｜`A:global/water/raytrace.glsl:58-110` + `A:lib/sky_reflection_cache.glsl:20-29`（258×128 运行时缓存兜底）｜**小**。**与批次一重复**：②-2"SSR miss 回退"（6 包印证）；与批次二已收敛的"天空缓存按 roughness 分级"同向。
4. **日/月盘烘焙进图 + 星 alpha 传全局可见度**：免解析日月绘制与天空射线检测。`P:shaders/world0/gbuffers_skybasic.fsh:110-111`、`P:shaders/world0/final.fsh:181`｜`A:lib/sky_directional.glsl`、`A:global/post/godrays.glsl:53-88`｜**快赢**（资产路线下）。误差：依赖天空 pass 覆盖全屏与 0 号像素写入顺序（作者已在 `composite1.fsh:264` 用 `depthtex1` 另写一份兜底，说明已知此坑）。
5. **`time[7]` 单次算好的昼夜权重数组**：7 段差分 clamp 一次算出，环境色/日光/天空 tile/火炬/雾共用；夜间项兼作雨夜选择子。`P:shaders/Lib/TimeArray.glsl:13-21`（消费 `Lib/Colors.glsl:16-35`、`Lib/TorchLightmap.glsl:17`）｜`A:lib/twilight.glsl`、`A:global/atmosphere/sky_gradient.glsl`｜**快赢**。**与批次一部分重复**：②-6"CPU 预计算 custom uniform"同族，但"昼夜离散成 7 个权重"未在批次一出现。
6. **自发光 = 材质 ID × 亮度阈值两级门**：材质位只给候选权，亮度减 `cover` 后定强度并 `pow(clr,0.6)` 压高光，避免整块发亮。`P:shaders/Lib/EmissiveLight.glsl:13-27`｜`A:lib/surface_emission.glsl:6-13`（`smoothstep(0.55,0.90)` 孔隙门同思路）｜**快赢**。**与批次一重复**：②-1"IPBR 自发光启发式"（2 包印证）。
7. **火炬光解析曲线**：`max(exp(pow(lm+0.6,3.0))-1,0) * 亮度 * (1+NdotL*0.5) * mix(color.a,1,t)`，无光源列表/距离；海晶灯与普通火把分色温。`P:shaders/Lib/TorchLightmap.glsl:13-34`、`P:shaders/world0/gbuffers_textured.fsh:488-492`｜`A:global/lighting/blocklight.glsl`｜**快赢**。**与批次一重复**：②-1"方块光陡峭/三段衰减"（2 包印证）；固有误差：无距离与遮挡。
8. **软阴影固定 4 tap + 偏差/软度解耦**：软度 `1/res*0.7`（`P:shaders/world0/gbuffers_textured.fsh:228`）与偏差 `distortion²*0.0015*tan(acos(diffuse^1.1))`（`:248`）分离，4 tap 等权（`:255-261`）。｜`A:global/lighting/shadowmap.glsl:119`（4 tap）、`:192`（法线偏移评述）｜**快赢**。**与批次一重复**：②-1"世界单位阴影模糊半径"（Shrimple 单源）。
9. **双阶段体积光：先烘遮挡掩码，再做径向模糊**：昂贵阶段（256 深度比较）只在 `composite` 做一次写 alpha，廉价阶段（10/50/100 样本抖动径向模糊）在 `composite1` 复用。`P:shaders/world0/composite.fsh:57-87`、`P:shaders/world0/composite1.fsh:91-108`｜`A:global/post/godrays.glsl:53-88`（Astra 为单阶段 8 样本 + Bayer8 抖动）｜**小**。误差：遮挡被二值化；若体积雾接管需按 `A:global/post/godrays.glsl:54-61` 做去重门控。
10. **水体 SSR 的相对容差命中判据与步长增长**：`dist < pow(len(step)*pow(len(refine),0.11),1.1)*1.22` 三旋钮（步长/细化/最大细化）。`P:shaders/world0/gbuffers_water.fsh:263-318`（默认 450 样本，`P:shaders/Lib/Settings.glsl:76`）｜`A:global/water/raytrace.glsl:58-94`（粗/精区间 + `stride*1.6`，`:92`）、`A:lib/settings.glsl:139-142`（预算 16/30/40）｜**快赢**（作实验参数）。**与批次一重复**：②-2"SSR 行进效率细节"（3 包印证）。误差：450 次查询在 4K 不可接受；Astra 现缺首步抖动。
11. **粗糙度 → mip LOD 的"免费模糊"**：声明 `colortex5MipmapEnabled` 后 `texture2DLod(..., lodding*12*(0.5+dither*0.5)/dist)`，抖动藏 8 位 LOD 带阶；景深同理用 colortex4 mip。`P:shaders/world0/deferred1.fsh:71,82-104`、`P:shaders/world0/final.fsh:211-262`、`P:shaders/world0/composite1.fsh:175-187`｜`A:lib/sky_reflection_cache.glsl:29`（固定 lod 0）、`A:global/post/bloom.glsl:7-15`（Astra 已有 mip bloom）｜**小**。**与批次一/二重复**：同一处"天空缓存按粗糙度开 mip"在两批次已 2 次出现，本包给出可抄的抖动 LOD 细节（第 3 次）。
12. **分析式镜头光晕（11 组圆环，零贴图）**：太阳投影到屏幕空间后画差集圆环/水平线，色相分组，`sunPosition.z` 与 sunVisibility 门控。`P:shaders/world0/final.fsh:129-205`｜`A:` 无（Astra 后处理仅 bloom/exposure/fxaa/godrays/grading，暗角在 `A:global/post/grading.glsl:204-212`）｜**小**。**与批次一重复**：②-8"老式解析镜头光晕"（4 包印证）。
13. **上一帧矩阵驱动的运动模糊 + Bayer 有序抖动**：只需 previous 矩阵与相机位移求速度，clamp 上限，双向 N 样本，Bayer16 抖动起点。`P:shaders/world0/composite4.fsh:21-52,58-102`、`P:shaders/world0/composite2.fsh:41-82`｜`A:lib/effect_history.glsl:3-8`（Astra 已声明同一套 uniform，`:17-25` 有历史失效判定）｜**小-中**；需先与 TAA 协调；误差：无遮挡/速度缓冲，旋转时拖刷感。
14. **"资产换运行时"的判据本身**：把 39.5 MB 图集当"预计算大气解算器 + 体积云 + 反射探针"，一处资产服务天空/水面/DH 三个消费端。`P:shaders/shaders.properties:188-190`、`P:shaders/world0/gbuffers_water.fsh:147-186`、`P:shaders/world0/dh_water.fsh:48-51`｜`A:shaders.properties:411-416`（Astra 已有 9 个 customTexture）、`A:global/dimension/end_kerr.glsl:4`（离线 atlas，绝不逐帧追踪）｜**中**。判据：慢变、可离散化、当前每帧重复采样的量才值得烘；与天气/色板强耦合的量不值得（本包 8 个离散时段即是该判据的反面教材）。

## ④ Astra 已有对应实现对照表

| 子系统 | Pyvtron（P:） | Astra（A:） | 哪边更省 | 误差来源 / 结论 |
|---|---|---|---|---|
| 天空与云 | 8 张烘焙 tile（16384×6144 RGB，39.5 MB），零云代码 | `sky_minishita.glsl:77` 解析大气 + `clouds_planar.glsl` 平面云 + `cloud_temporal.glsl` | 运行时 Pyvtron 远省；显存/资产贵 ~40 MB | Pyvtron 天空无法响应天气/颜色方案，旋转是假的 → 不照搬，仅可做"夜间/雨夜低档单 tile"对照实验（与批次二 1.3 结论一致） |
| 天空反射兜底 | 反射向量直取天空图集 `gbuffers_water.fsh:332` | `lib/sky_reflection_cache.glsl:20-29`（258×128，lod 0） | Astra 省（19 KB vs 39.5 MB），Pyvtron 更清 | Astra 缺"按粗糙度取 LOD"（批次二已收敛）；本包 `deferred1.fsh:91` 的抖动 LOD 可直接补 |
| 水面 SSR | 450 样本 + 天空兜底 + 边界掩码（`gbuffers_water.fsh:263-339`） | `global/water/raytrace.glsl:58-110` 粗/精搜索，预算 16/30/40（`lib/settings.glsl:139-142`） | Astra 省一个数量级 | Pyvtron 容差式命中在薄几何会穿；Astra 缺首步抖动可补 |
| 焦散 | 噪声三向叠加 + 深度淡出（`gbuffers_textured.fsh:105-142`） | `global/water/caustics.glsl:45-58`（Solas 血统，`:13` 注释已做 band limit）+ `program/shadow.fsh:26` | 双方都便宜；Astra 多一条阴影侧焦散 | Pyvtron 无足迹滤波，远景闪；仅"四尺度权重"手势可参考 |
| 体积雾 | 固定 100 步 ×0.2 m，每步一次 `exp()`（`Lib/VolumetricFog.glsl:3-4,26-49`） | `global/atmosphere/volume_fog.glsl:31-40` 三档 12/24/48 + 前缀步，`lib/volume_integral.glsl:92-123` 解析积分 | Astra 明显更省更准 | Pyvtron 覆盖仅 20 m 且逐像素跑在 gbuffers/deferred → 作反例引用 |
| 体积光 | 掩码预烘 256 tap + 径向模糊 10/50/100（`composite.fsh:57-87`、`composite1.fsh:91-108`） | `global/post/godrays.glsl:53-88` 单阶段 8 样本，体积雾开启时返回 0（`:54-61`） | Astra 省（8 vs 256+N） | 可借"一次昂贵采样喂多消费端"；低档备选 |
| Bloom | 9 octave 双向 mip 抓取（`composite4/5/6.fsh`），带帧反馈与可疑曝光源（`composite5.fsh:173`） | `global/post/bloom.glsl:7-15` 两 pass mip 链，`:32-39` 软膝/过曝钳制 | Astra 省（2 pass vs 3+）且无残影 | Pyvtron 的 exposure 实为雨滴 buffer alpha（`gbuffers_weather.fsh:57`）→ 不借鉴 |
| Tonemap | Uncharted2 参数面（`final.fsh:31-67`） | `lib/tonemap.glsl:195-197`（AgX 与 ACES 可选） | 相当，Astra 算子更多 | Uncharted2 无引入必要 |
| 材质 ID | 法线 alpha 单浮点 ±0.01（`gbuffers_textured.vsh:110`、`:150-179`；比较 `gbuffers_textured.fsh:87-95`） | `lib/encoding.glsl:51-63` 八面体量化 + `program/lit.fsh:104-106` 位域（material = bit18..21） | Astra 省：ID 不占额外缓冲、无插值误差 | Pyvtron 方案寄生法线且脆弱 → Astra 更优，无需借鉴 |
| 湿材质/水洼 | 噪声 `.a` 掩码 + `.b` 涟漪，lightmap 亮度当室内门（`gbuffers_textured.fsh:295-337`） | `lib/wet_material.glsl:7-27` 4 档湿类 + `global/atmosphere/weather.glsl:64` | Astra 更完整（分类 vs 单掩码） | 仅"双相位噪声涟漪"手势可参考 |
| 自发光 | 材质 0.3 + 亮度阈（`Lib/EmissiveLight.glsl:13-27`） | `lib/surface_emission.glsl:6-13` + `blocklight.glsl` | Astra 更克制 | 同方向重复，无新增 |
| 低光适应 | 亮度^4 混向灰度（`Lib/LowLightEye.glsl:13-17`） | `global/post/grading.glsl`、`lib/tonemap.glsl` | 相当 | Pyvtron 只去饱和不蓝移；Astra 已覆盖 |
| 景深/运动模糊/光晕/暗角 | 四件套全开（`final.fsh:129-262`、`composite2/4.fsh`） | 仅暗角（默认关）与 bloom | 关掉最省；Pyvtron 因全开才需 6 个 composite | 风格页候选：解析 flare 与 mip DoF 最便宜，运动模糊需先与 TAA 协调 |
| 植被风 | vsh 与阴影 vsh 同函数同步位移（`gbuffers_textured.vsh:133-144` + `shadow.vsh:94-105`） | `global/lighting/wind.glsl:112-146,167,219` + `program/shadow.vsh:24` 已同构 | 双方一致 | 方向已被 Astra 采纳，无需动作 |
| 工程结构 | 三 world 目录全量复制，同一 bug 需改 3 处 | world 薄壳 + 共享 `program/*`（`gbuffers_terrain.fsh:1-3` 仅 3 行） | Astra 省维护 | 复制式结构是反例 |
| 距离渲染 | DH 双 pass + dhShadow 门控（`shaders.properties:139-180`） | `voxy.json` + `voxy_opaque/translucent.glsl` | 不可比（不同 mod） | 仅"DH 水面沿用同一天空资产"的一致性做法可参考 |
| 设置系统 | 7 档全量列参（`shaders.properties:197-203`），含 2 个死宏 | `A:shaders.properties:18-135` 按档位改 buffer 尺寸（增量） | Astra 更省且不易漏改 | 批次一 ②-6 结论一致；本包是反例 |

## ⑤ 许可可行性与"重写 vs 抄"边界

判定依据 `P:LICENSE.txt` 原文（自定义协议；名称含 "Copyright Claw" 无对应法律含义，以原文为准）：

- **只读思想可行**：协议不限制阅读；但 `:28` 的私有修改授权**仅限对该项目自身的使用**，不构成"搬进别的项目"的许可。
- **再分发禁止**：`:23` 禁换链/再分发/加入合集（合集需显式许可）；`:25` 服务器与启动器一律禁止内嵌。
- **改编发布需许可**：`:31-37` 要求显式书面许可 + 有意义的原创 + **同许可** + 署名 + 禁变现；`:35`/`:37` 与 Astra 现有第三方体系（含 `A:global/post/godrays.glsl:5-9` 的 GPL-3.0-or-later 来源）方向冲突，若走授权路线需统帅单独决策。
- **跨项目使用部分（代码/效果/贴图）须显式许可**（`:41`）：**本包代码与贴图都不得进入 Astra 仓库或发布物**，署名也不例外。
- `:47` 作者可单方改许可、`:52` 威胁版权程序 → 取最保守解读。

| 允许（重写） | 禁止（抄） |
|---|---|
| 只用不受版权保护的公开技术思想与算法（立方体展开映射、掩码+径向模糊、粗糙度→mip 抖动、4 tap PCF 与偏差分离等） | 复制任何代码片段/函数体/常量表/系数序列/注释文本，含改名与换序 |
| 依公开资料（GPU Gems 3、立方体展开数学、Uncharted2 论文）独立实现，命名/结构/注释自拟 | 使用 `Skyboxes.png`/`EndSkybox.png`/`Noise.png` 或其裁剪/重采样/调色衍生版（`:41` 明确含 textures） |
| 在 `Astra/THIRD-PARTY.md` 登记"思想来源：Pyvtron Shaders V1.3.2" | 使 Astra 发布物含本包任何字节或声称衍生关系（`:18` 的 distribute 涵盖任何渠道） |

结论：**只可只读思路、独立重写**，与批次二 1.4 的分层判定一致（`shader_research/SUMMARY-batch2.md`）。任何资产引入须先取得书面许可，并处理 `:35`/`:37` 冲突。

## ⑥ Top 5 与暂缓项

**Top 5**

1. **天空缓存按粗糙度开 mip + 抖动 LOD**：借鉴 `P:shaders/world0/deferred1.fsh:91` 的写法，落在 `A:lib/sky_reflection_cache.glsl:29`。快赢，且是批次一/二第 3 次收敛的同一处。
2. **低档双阶段体积光**：`P:shaders/world0/composite.fsh:57-87` + `composite1.fsh:91-108`，对照 `A:global/post/godrays.glsl:53-88`；注意按 `:54-61` 做体积雾去重门控。
3. **水面反射的天空兜底与首步抖动**：`P:shaders/world0/gbuffers_water.fsh:264,275,332,336-338` → `A:global/water/raytrace.glsl:58-110`；Astra 兜底通路已存在，仅缺抖动。
4. **昼夜权重数组 + 低光去饱和的简化写法**：`P:shaders/Lib/TimeArray.glsl:13-21`、`Lib/LowLightEye.glsl:13-17` → `A:lib/twilight.glsl`、`A:global/post/grading.glsl`；用于低配档。
5. **"哪些量值得烘成资产"的判据 + 现有 customTexture 机制复核**：`P:shaders/shaders.properties:188-190` 对照 `A:shaders.properties:411-416`；产出是设计判据而非代码。Astra 的末地 transfer atlas（`A:global/dimension/end_kerr.glsl:4`）已走正确形态。

**暂缓 / 不建议**

- 烘焙天空全景集本体：需 40 MB 级美术资产，且与 Astra 天气/四种颜色方案冲突；仅做小范围对照实验。
- 帧反馈 bloom（`P:shaders/world0/composite5.fsh:173` + `composite6.fsh:19-103`）：Astra 两 pass mip 链更省且无残影，且该链曝光源可疑。
- `P:shaders/world0/composite3.fsh:23,38-60` 的 SSR：采样未注册 `normaltex`、用 `BLOOM_SAMPLES` 当步数，是半成品（三个 world 目录重复同一份），不可照搬。
- 固定 100 步体积雾（`Lib/VolumetricFog.glsl:3-4` 等三份）：比 Astra 自适应步数 + 解析积分更贵，只作反例。
- `noiseTextureResolution = 1`（`P:shaders/world0/composite.fsh:41` 三处）与 470×470 噪声（`P:shaders/shaders.properties:188`）不匹配：噪声寻址行为需实机确认；本包所有噪声效果（水波/焦散/水洼/涟漪）都建立其上。
- `texture.gbuffers.colortex8 = Images/EndSkybox.png`（`:190`）：把颜色附件当输入贴图绑定，支持度存疑（Astra 自己的注释 `A:shaders.properties:409-410` 说明该机制只覆盖已注册 sampler）。
- `P:shaders/world-1/gbuffers_skybasic.fsh:33` 硬编码红色：工程卫生一般，引用其实现需逐条核实。
- `bouncedLight()` 的 bounce0..9（`P:shaders/world0/gbuffers_textured.fsh:177-211`）：同一 dot 项的重复计算，无物理意义。

## 附录：自抽查（成稿后重开源文件复核，16 条）

方法：成稿后对正文关键引用逐条 `sed -n '<行>p' <文件>` 重读（非记忆），下表为原始输出截断；16 条全部与正文一致。

| # | 引用 | 复核输出（截断） |
|---|---|---|
| 1 | `P:LICENSE.txt:28` / `:41` | `You are allowed to make private modifications of Pyvtron Shaders for personal use only…` / `Using individual parts of Pyvtron Shaders (such as code, effects, or textures) in other projects is only allow…` |
| 2 | `P:shaders/shaders.properties:28` / `:189` | `clouds = off` / `texture.gbuffers.gaux4 = Images/Skyboxes.png` |
| 3 | `P:shaders/world0/gbuffers_skybasic.fsh:36,90,110,116` | `const ivec2 resolution = ivec2(7680, 4320);` / `first = texture2D(gaux4, projectSky(pos.xyz, rotation + config[0].w) * vec2(0.25,0.5) + config[0].xy).rgb` / `gl_FragData[0] = vec4(skybox, 1.0 - stars);` / `/* DRAWBUFFERS:061 */` |
| 4 | `P:shaders/world1/gbuffers_skytextured.fsh:65` | `vec3 skybox = texture2D(colortex8, projCoord * vec2(0.25, 0.5) + vec2(0.0, 0.0)).rgb;` |
| 5 | `P:shaders/world0/gbuffers_water.fsh:264,332`；`gbuffers_textured.fsh:228,521` | `float dither = ditherGradNoise();` / `vec3 skyReflection = pow(getSkyTextureFromSequence(fragpos + reflectedVector), vec3(1.3));` / `float shadowSmoothnessFactor = 1.0 / shadowMapResolution * 0.7;` / `/* DRAWBUFFERS:0124 */` |
| 6 | `P:shaders/world0/gbuffers_textured.vsh:110`；`Lib/VolumetricFog.glsl:3`；`Lib/TorchLightmap.glsl:23` | `normal = vec4(normalize(gl_NormalMatrix * gl_Normal), 0.02);` / `#define MAX_STEPS 100` / `float torchLightmap = max(exp(pow(lightmap + 0.6, tRadius)) - 1.0, 0.0) * tBrightness * …` |
| 7 | `P:` `composite.fsh:41,70`、`deferred1.fsh:91`、`final.fsh:129,181,219`、`composite3.fsh:23`、`composite5.fsh:173`、`gbuffers_weather.fsh:57`、`world-1/gbuffers_skybasic.fsh:33` | 依次：`const int noiseTextureResolution = 1;`、`for (int i = 0; i < 256; i++) {`；`vec4 reflection = texture2DLod(colortex5, texcoord, (lodding * 12.0 * …`；`#ifdef LENS_FLARE`、`float sunVisibility = texture2D(colortex4, vec2(0.0)).a * distof;`、`const bool colortex4MipmapEnabled = true;`；`uniform sampler2D normaltex;`；`float exposure = textureLod(colortex7, vec2(0.0, 0.0), 0).a;`；`gl_FragData[0] = baseColor;`；`gl_FragData[0] = vec4(1.0, 0.0, 0.0, 1.0);` |
| 8 | `A:lib/sky_reflection_cache.glsl:29`；`lib/settings.glsl:139`；`lib/effect_history.glsl:5`；`lib/encoding.glsl:51` | `return textureLod(colortex11, vec2(u, v), 0.0).rgb;` / `// Water SSR total depth-query budget: 16/30/40 …` / `uniform mat4 gbufferPreviousModelView;` / `uint pack_octahedral(vec3 normal, const int bits) {` |
| 9 | `A:global/water/raytrace.glsl:92`；`water/caustics.glsl:45`；`post/godrays.glsl:5,63`；`post/bloom.glsl:32` | `stride = min(stride * 1.6, 8.0);` / `float solas_water_caustics(vec3 worldPos) {` / `// From Steadfast 0.8.0 (GPLv3 + Section 7 additional terms) by coderbot`、`const float NUM_SAMPLES = 8.0;` / `const float BLOOM_THRESHOLD = 1.0;` |
| 10 | `A:program/lit.fsh:104,106`；`shaders.properties:411`；`atmosphere/volume_fog.glsl:33`；`lighting/wind.glsl:112`；`program/shadow.vsh:24`；`dimension/end_kerr.glsl:4`；`atmosphere/sky_minishita.glsl:77`；`post/grading.glsl:204`；`lib/tonemap.glsl:195`；`lib/wet_material.glsl:7`；`lib/surface_emission.glsl:6` | 依次：`vec3 faceNormal = unpack_octahedral(faceData, 9);`、`uint material = (faceData >> 18) & 15u;`；`customTexture.steadfastWaterNoise=textures/steadfast-water-noise.png`；`#define ASTRA_VOLUME_STEPS 12`；`vec3 wind_wave_shape(vec3 pos, float wind) {`；`#include "/global/lighting/wind.glsl"`；`// The atlas is produced by qa/tools/build_end_transfer.py, never traced per frame.`；`vec3 astra_minishita_sky(vec3 worldDir) {`；`vec3 apply_vignette(vec3 displayColor, vec2 screenUV) {`；`#elif TONEMAP_OPERATOR == TONEMAP_AGX`；`uint astra_wet_class(int blockId) {`；`vec3 astra_end_stone_emission(uint material, vec3 albedo) {` |

未复核项声明：正文标注"存疑/需实机确认"的三处属行为问题而非行号问题（`noiseTextureResolution` 与 470² 噪声的匹配、`texture.gbuffers.colortex8` 的注册行为、`VL_QUALITY`/`WATER_SAMPLES` 死宏），报告只登记事实与出处（`P:shaders/world0/composite.fsh:41`、`P:shaders/shaders.properties:188-190`、`:197-203`），不声称其运行结果。
