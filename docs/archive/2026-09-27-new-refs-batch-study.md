# 新参考批次深度调研（2026-09-27）

> 后续源码对照与实施已记录于 [持续待办与实施记录](../2026-09-26-itt32-initial-implementation.md)。本文中“Astra 完全没有 AO / raymarch 雾”“colortex11 没烘云”“自动曝光需要 57 条 CPU uniform”等描述不适用于当前源码。SH9 系数数量不能当作方向采样数量；无 TAA 也不等于所有跨帧状态都不可用。FXAA、独立云影缓存及可选 TAA 首版已落地；TAA 的准确动态累积仍未完成；下文保留原调研记录，不直接作为实施清单。

本批从 Modrinth 新下载 10 个参考光影（工作区此前未收录），解包至 `_analysis/refs-2026-09-27/<slug>/source/`，逐包建立深度档案。`sources.json` 与 `fetch_batch.py` 留存完整获取元数据（版本/许可/URL）。文中行号以本批下载版本源码为准；原调研采用的“无 TAA”等路线假设已过时，当前约束与实施状态见文首链接。

上一批 34 包档案见 [2026-09-26-workspace-packs-survey.md](2026-09-26-workspace-packs-survey.md)；其结论涉及 full-review 报告处以 [itt32-design-study §6 更正](2026-09-26-itt32-design-study.md#6-对用户指定汇总的关键更正) 为准。

---

## 一、批次登记

| 包 | 版本 | 下载量 | 许可 | 定位 |
|---|---|---|---|---|
| rethinking-voxels | r0.1-beta9 | 1311 万 | LicenseRef-Complementary-Agreement | Complementary 重型分支：体素化彩光/GI/反射 |
| insanity-shader | v1.650 | 749 万 | LicenseRef-AGNYA-License | BSL 底盘风格化画质（BSL 改） |
| pastel-shaders | v1.200 | 500 万 | All Rights Reserved | BSL 血统柔和粉彩风格化 |
| hysteria-shaders | v1.2.1 | 344 万 | LicenseRef-AGNYA-License | Photon 底盘性能取向（Photon 改） |
| spooklementary | v2.0.4 | 308 万 | LicenseRef-Complementary-License | 恐怖向 Complementary 活跃分支 |
| noble | v1.9.8hf | 227 万 | **GPL-3.0** | NobleRT 屏幕空间光追旗舰，2026-09 仍更新 |
| vanilla-plus-shader | v3.3 | 216 万 | All Rights Reserved | 原版增强 + 怀旧 colorPreset（RRe36） |
| pixel-perfect-shaders | v1.5.2a | 81 万 | **LGPL-3.0** | 像素网格一致性 + 完整 TAA（"AA Buffet"） |
| arc-shader | v0.15.2 | 93 万 | **MIT** | 性能优先物理向，**全程不用 TAA** |
| ebin-resurrected | v1.5.6 | 60 万 | **AGPL-3.0** | 老牌真实向复活（jbritain，无蓝噪无 compute） |

许可分布对 Astra 明显比上一批友好：Arc(MIT)/Noble(GPL)/Ebin(AGPL)/PixelPerfect(LGPL) 四包可合法借鉴表达式；Pastel/VPS 仅登记机制；AGNYA 两包与 Complementary 系三包按各自许可处理。

---

## 二、十包档案

### 2.1 Rethinking Voxels r0.1-beta9 —— 体素化路线的同类参照（GPL 系）

Complementary Unbound 重型分支，全工作区唯一用**几何着色器**做体素化的包（3 个 .gsh）。26 program；体素链 = shadow.vsh 写 occupancy → shadow.gsh 三角形光栅化 → shadow.fsh 逐体素位域 → shadowcomp.csh 多级 SDF → shadowcomp1.csh 时域辐照度缓存 → prepare4.csh 每像素光列表 + 锥追踪。体积 `VX_VOL_SIZE` 96×64×96 ~ 512×128×512（`lib/common.glsl:22-28`），彩光可按 1/2..1/8 屏分辨率算（`:51`）。

| 技法 | 位置 | 机制 | Astra 现状 | 兼容性 |
|---|---|---|---|---|
| **阴影 pass 内几何光栅化体素化** | `program/shadow.glsl:279-564,526,686-693` | GS 为非自发光三角形多发一份，投影进 shadowmap 左下 0.1 角区当 scratch 画布，写完 discard；LOD 按距离 log2 放大格 | `shadow.vsh:74` 只在顶点 imageAtomicMax 写 64³，格均匀 | 兼容（一次性）；小物件（火把/栅栏/作物）获得正确体积 |
| **纹理 alpha 的 cutout 覆盖判定** | `program/shadow.glsl:205-227` | 块纹理 4 点最大 alpha（实体阈值 0.5、cutout 0.1）决定占用，bit8 标半透明 | 按 mc_Entity 整格二值分类——树叶要么全挡要么全透 | **兼容**：叶缝/十字草真实覆盖，现有 shadow.vsh 就能加 |
| occupancy 位域预算 | `program/shadow.glsl:371-383,500-517` | 一张 r32i：8 LOD 实体/半透明/lightLevel/光源/物种/entity/sky 位；颜色 4×13bit+指数另存 | r32ui 只有 solid 位 + 8 位物种 | 兼容：省掉第二三张自定义图（Iris 上限 15 张） |
| 多分辨率 SDF | `shadowcomp.glsl:46-129` + `shadowcomp_sdf_loop.glsl` | 8 个 LOD 位 → RGBA16F 3D 纹理 4 通道=4 级，按距离淡入 | 无 SDF | 部分兼容：同帧全量重建可搬；"上帧续算"是时域 |
| **低分辨率彩光 + 屏幕邻域匹配上采样 + 体素回落** | `prepare4_csh.glsl:6-18`、`prepare4_csh_a.glsl:1-50`（14×14 tile 滤波）、`mainLighting.glsl:480-505` | 低分计算→屏幕邻域螺旋 10 次找法线/深度匹配样本→找不到回落体素三线性 | 直接三线性采 64³ | **兼容**：Astra 扩体积/推主世界的唯一零时域路线，三段可独立落地 |
| 每屏像素光列表 + 锥追踪 | `prepare4_csh.glsl:196-419`、`voxelReading.glsl:65-133` | 共享内存排序去重光源，逐光源 coneTrace(SDF) | 8 步扩散无列表无方向 | **不兼容**（SDF+时域列表）；"每格只留最亮光源"原则可砍扩散步数 |
| 光源合并（clumping） | `shadowcomp.glsl:284-423` | 相邻同 species 光源 SSBO 哈希累加亚格位置/颜色 | imageAtomicMax 取 max 物种 id，同格多光源偏色 | 兼容：换成颜色累加即可 |
| 半透明光染色 | `voxelReading.glsl:91-99` | 半透明格命中锥追踪时颜色乘进光色（彩玻透光） | 无 | 兼容；需第二张颜色图 |
| 像素化光照重采样 | `mainLighting.glsl:63-90` | vxPos/lightmap/深度量化到固定网格 | 无 | 兼容；风格开关兼省采样 |

### 2.2 Spooklementary v2.0.4 —— Complementary 活跃分支的增量（Complementary 许可）

基线**早于**手上的 r5.9（体素内核是旧版 floodfill），价值在氛围特效 + 选项/GUI 重组。7 档 profile 把 `COLORED_LIGHTING`(0/256/512) 与反射/实体影绑档；SPOOKY_SETTINGS 主题子树。

| 技法 | 位置 | 机制 | 兼容性 |
|---|---|---|---|
| **含自身的 7 点归一化 floodfill** | `program/shadowcomp.glsl:55-74` | `light=(自身+6邻)/7.2`，比 6 邻 max 各向同性；lava/玻璃按 specialTintColor 直接染色 | 部分兼容（同帧版需按步数折算强度）——Astra 的 max·0.72 换成均值更平滑 |
| **墙角漏光抑制** | `lib/voxelization/lightVoxelization.glsl:48-88` | 6 邻实体数 ≥3 时把插值 clamp 到实体格自身光的 1.5 倍，挡对角渗透 | **兼容**：一条 min() 加进 nether_colored_light |
| 时域乒乓 + 相机位移重投影 | `shadowcomp.glsl:80-142` | 体素图不 clear，framemod2 乒乓，z>0.5 半区半率 | 不兼容（时域）；位移写法可改造 |
| 体积驱动的逐面材质 | `lavaEdge.glsl:1-40` | gbuffers 里 texelFetch 体素图判断岩浆顶层 2×2 邻域做边缘高光 | 兼容：Astra 64³ 图差一个 sampler3D 声明 |
| 世界时钟确定性事件调度 | `commonFunctions.glsl:503-541`、`powerOutage.glsl` | worldDay/worldTime 哈希激活窗口（零噪声零时域）；断电边界随 chunk 距离收缩 | 兼容：可做下界风暴/血月，替代被否决的体积风暴 |
| 彩色玻璃透射染色表 | `blocklightColors.glsl:227-260` | 体素 id≥200 玻璃携带 tint，光穿乘 tint；现成 28 色表 | 兼容 |
| GUI 组织 | `shaders.properties:2-16,177-205` | 7 档绑档 + 主题分屏 + image 声明按档展开体积 | 兼容（纯配置） |

### 2.3 Insanity v1.650（BSL 底盘）+ Hysteria v1.2.1（Photon 底盘）—— 同厂 A/B（AGNYA 许可）

**Insanity（画质取向）**：8 composite + 2 deferred；五档 profile 继承，`shaders.properties:114-130` 用 program toggle 关 AO/光轴/运动模糊/DOF/TAA/FXAA。**默认 TAA/AO/光轴全关照样跑彩色光轴与 SSAO——无 TAA 降噪的现成可行性证据。**

| 技法 | 位置 | 机制 | 兼容性 |
|---|---|---|---|
| 阴影贴图彩色光轴 | `lib/atmospherics/volumetricLight.glsl:40-144` | 7 步 `exp2(i+dither)-0.95` 对数步长反投 shadow space，取 shadowtex0/1+shadowcolor0 彩色 | 兼容 |
| 光轴合成 = 平方 + lod1.5 | `composite1.glsl:44-58` | `vl=texture2DLod(colortex1,1.5); vl*=vl;` 再乘色 | 兼容：两行可替换 Astra 的 3×3 箱式核 |
| 粗糙反射 mip 拼贴 | `roughReflections.glsl:1-50` | 30 步 raytrace 后 lod 由 `(1-smoothness)·dist` 推，5×5 邻域按 lod 偏移 | 兼容 |
| 方向光图 | `directionalLightmap.glsl:8-25` | dFdx/dFdy 反推光图梯度 | 兼容：两行让平面光照"有向" |
| 程序化雾=天空导数 | `sky.glsl:2-75`、`fog.glsl:63-133` | 雾色取自天空色，天地一致，四套曝光 | 兼容 |

**Hysteria（性能取向）**：17 composite + 5 deferred + 2 compute；"默认关 + 预设放行 + 分辨率杠杆"（lowest=TAAU 0.5+1024 影图）。约 40 个步数/预算参数直接暴露 UI。

| 技法 | 位置 | 机制 | 兼容性 |
|---|---|---|---|
| **体积雾三件套** | `include/fog/air_fog_vl.glsl:17-142` | 射线与 [SEA_LEVEL-24,320] 体腔求交早退 → `steps=8·Q+0.1·dist` 自适应 → 单步 `(1-exp(-od))/od` 解析散射 → 4 次多散射迭代相函数推向各向同性 | **兼容**：Astra 完全没有 raymarch 雾，这可从 PERFORMANCE 档开启；静态噪点配小核模糊 |
| 离线 Bruneton 大气 LUT 当 3D 贴图 | `shaders.properties:330`、`sky/atmosphere.glsl:19-21,300-358` | 散射 LUT 预烤成 `image/atmosphere/scattering.dat` 挂 TEXTURE_3D；无 LUT 退回 Chapman 近似 | 兼容：天空缓存可同机制扩透射率表 |
| 云棋盘时域上采样 + 3D 噪声 | `checkerboard.glsl:1-68`、`deferred1.glsl:239-300`、`deferred2.glsl:186-305`、`shaders.properties:333-337` | 每帧只更新 1/(N²) 子像素 + pixel_age 权重重投影；64³ worley + 32³ curl 贴图 | **部分兼容**：可落在 Astra colortex12 半分辨率云缓存上做"每帧 1/4 + 混合"质量档；移动滞后是代价 |
| 云阴影预渲染图 | `world0/prepare.fsh`、`light/cloud_shadows.glsl` | 云覆盖渲成低分辨率图，地表一次查表，遮挡越大阴影越软 | 兼容：可与云缓存同 pass 顺带产出 |
| VPS 软阴影 + 自适应 PCF | `light/shadows.glsl:114-190,244-264` | blocker search 估 penumbra，PCF 6~12 步随半径缩放，小于最小半径反而锐化；云影下 penumbra×5 | 兼容："接触硬远处软"，纯空间 |
| LPV 彩色方块光 | `lpv/voxelization.glsl`、`floodfill.glsl:41-69`、`setup.csh`+`shadowcomp.csh` | shadow 阶段体素化 + 每体素 6 邻域泛光单 compute，voxelDistance=32 | 兼容：主世界彩光的最简底盘 |
| 天空图+SH 一次成型 | `deferred0.glsl:195-197`、`settings.glsl:53` | 全向天空图同时喂反射与 SH 天空光 | 兼容：Astra colortex11 同构，加 9 点 SH 采样即得天光方向性 |

**双包对照**：光轴（屏幕空间 vs 世界空间体腔）、反射（mip 拼贴 vs 高光限定）、云（单层 shadowmap 取光 vs 棋盘时域+3D 噪声）、AO（SSAO 4 环 vs GTAO 2×3）、大气（全解析 vs 离线 LUT）、闸门（profile 继承 vs 默认关+放行）。Astra 停在 GPU Gems3 深度缓冲 8 步、无 AO、无体积雾、无 LUT——两包正好给出每种能力的两档实现。

### 2.4 Noble v1.9.8hf —— GPL 屏幕空间光追旗舰（表达式可直搬）

404 文件；核心旋钮全是"模式+比例"（AO={GTAO/SSAO/RTAO}×AO_SCALE 25-100、REFLECTIONS×SCALE×STRIDE）。注意 v1.9.8hf 的 buffer 格式声明块整段被注释（`include/internal_settings.glsl:27-121`），只能当文档读。

| 技法 | 位置 | 机制 | 兼容性 |
|---|---|---|---|
| **GTAO + bent normal** | `fragment/ambient_occlusion.glsl:73-121` | 2 slice×4 horizon steps，cos>0.95 早退，闭式 arc 积分，bent normal=两 horizon 平均 | **兼容**：把 temporalBlueNoise 换静态 bayer8/IGN + 3×3 空间滤波；正对 Astra 零 AO |
| 天光 SH9 + bent normal（真 GI） | `shadows_and_skylight.glsl:144-148`、`atmosphere.glsl:278-339` | 8×8 方向采样把大气投成 9 个 SH 系数，逐像素 bent normal 做 Lambert 卷积，AO 当 visibility | **完全兼容**：不发射线纯静态；Astra 有大气缓存可直接投 SH |
| DDA 屏幕空间光追 | `fragment/raytracer.glsl:32-117` | McGuire&Mara 2014；thickenDepth 把深度膨胀成视锥体素修薄面漏检；一个函数服务 RTAO/SSR/折射 | 兼容：Astra 水面 SSR 内核的直接升级件（jitter 传常数） |
| VNDF 粗糙反射单次 raytrace | `fragment/reflections.glsl:108-183` | 每样本抖动微面法线、单条 raytrace、miss 回退天光，fresnel·G2/G1 split-sum | 兼容（SAMPLES=1 + stride 48/64 + 空间模糊） |
| 反射 miss 回退天光+**云** | `reflections.glsl:29-65,180-186`、`math.glsl:209` | 0.25 球面投影 CLOUDMAP 进反射 | 兼容：Astra colortex11 缓存没烘云——补上水面就能反射出云 |
| 接触阴影 | `fragment/shadows.glsl:28-91` | 屏幕步进 stride=6，IGN 抖动，线性深度 gap 判据 | 兼容：解决贴图阴影看不到的贴地缝 |
| 系数藏进 9 个 texel | `illuminance_fetch.glsl:23-61` | 无 SSBO 时把 SH9 写进 buffer 前 9 texel 当常量用 | 兼容：省 buffer 的传递技巧 |
| AO 时间滤波 | `ambient_occlusion_write.glsl:146-168` | 历史累积混合 | **不兼容**（反面教材；应走 Ebin 双边升采样） |

### 2.5 Ebin Resurrected v1.5.6 —— AGPL 老派扎实链（无蓝噪无 compute）

全屏单 composite 链 + 宏开关；血统注释自证（bliss/chocapic Frisvad 切线、Zombye VNDF、Bruneton 大气）。与 visual-vibrance 同作者同 lib 布局；唯一噪声源 IGN。

| 技法 | 位置 | 机制 | 兼容性 |
|---|---|---|---|
| **shadowcolor1 法线 + 阴影图 LOD = 半分辨率 GI** | `Fragment/ComputeGI.fsh:10-83`、`gbuffers_shadow.glsl:244` | 阴影 pass 把法线写进 shadowcolor1；GI 在半分辨率对 radius 内 N 点 `texture2DLod(shadowtex1,depthLOD)` 取深度/法线/flux 做 1/d²·cos 加权，采样数随距离衰减 | **完全兼容**：不新增 GBuffer、远处自动降质；Astra shadowcolor1 有彩影通道可复用 |
| **双边升采样 GI/AO/VL** | `Fragment/BilateralUpsample.fsh:5-65` | 5×5 核，权重=max(0,1-\|Δdepth\|)·(dot(n,n')·0.5+0.5)；VL 额外 lod3 模糊 | **无 TAA 去噪的标准答案**（Noble 时间滤波的替代） |
| SSAO：Hammersley+Circlemap 双半径 | `Fragment/ComputeSSAO.fsh:15-56` | 4×4 常数索引代噪声图；每样本两半径 1.0/0.25；软边界 clamp | 兼容：6/8 样本的最省做法 |
| 解析求最大步数的 SSR | `Fragment/ComputeSpecularLighting.fsh:6-19,157` | GetMaxSteps 解"射线到屏幕边界/maxRayDepth"解析式反解步数，上限 75，步长几何增长 | 兼容：步数由几何算出，可直接换 Astra 循环头 |
| 反射 miss 回退天空+**体云** | `ComputeSpecularLighting.fsh:179-208` | 反射方向屏幕坐标 `textureLod(colortex5,...,VolCloudLOD)` 混云；屏幕边缘 pow4 淡出 | 兼容：Astra colortex12 平面云可接 |
| 体光线分段抖动 + 复用作雾色 | `ComputeVolumetricLight.fsh:14-45` | 每样本段内单独 IGN；透射存 colortex6.xy 喂光束与雾/水色 | 兼容：一次 VL 喂两处 |
| 网格吸附波噪声取点 + 波峰锐化 | `ComputeWaveNormals.fsh:3-34` | floor+cubesmooth 吸附到纹素中心；二次式压尖峰；波常数按高度权重 | 兼容：减"糊+游泳"，吸附本身防闪烁 |
| 预烘 3D 大气 LUT（256×128×33 RGBA32F bin） | `shaders.properties:19`、`PrecomputedSky.glsl:8-14` | 运行时零 raymarch | 对照项：Astra 实时路线更省，且 bin 非自由资产 |

### 2.6 Pastel v1.200 —— 粉彩风格化配方（ARR，只登记机制）

BSL v8 fork + Insanity 血统；全正向光照 + 8 段后期；12 档案（P/B/Y × LOW/MEDIUM/QUALITY/HQ）；15 组 8bit 色板 + CG_* 通道混合器。

| 技法 | 位置 | 机制 | 借鉴点 |
|---|---|---|---|
| **粉彩核心：阴影去饱和+环境染色** | `lighting/forwardLighting.glsl:75-108` | desatAmount 含 `sqrt(blockLight)` 显式保护项；desatColor 乘回亮度（×10）避免去饱和=变暗 | 核验/加固 Astra `diffuse.glsl:237,245,360,443` 的夜间去饱和，重点测"火把旁阴影面" |
| CG_* 通道混合器 | `composite5.glsl:161-170` | 9 权重 3×3 混合 + lift + 强度 + 全局 tint | "一键整包变味"最短路径，可加在 tonemap 后 |
| Bloom 幂空间混合 | `composite5.glsl:94-148` | `pow(color,exp2(BLOOM_CONTRAST·0.25))` 幂空间 mix 再开方，避免整屏发白 | 柔和感关键，一对 pow 即可 |
| 水下 sqrt 空间混合 + 屏扭 | `composite.glsl:120-125`、`composite5.glsl:67-81` | `mix(sqrt(c),sqrt(waterFog),a)` 再平方；±0.0005 cos/sin 扰 uv | 原版味过渡 + "活"感，3 行级 |
| 半透明 sqrt 存储/平方还原 | `gbuffers_skytextured.glsl:99` 等 | LDR 缓冲模拟原版 gamma 混合 | 登记参考；Astra R11F 精度足够 |

### 2.7 Vanilla Plus v3.3 —— 原版增强边界样本（ARR，只登记机制）

默认档只加云/雾/godrays/水雾/风/水面高光/SSR/bloom/TAA/vignette；下界末地几乎全用原版色派生；colorPreset 一键切 SEUS v08/Chocapic v3/Plunderpixel/Rudoplays 调色。下界专用瘦身 forward（166 行 vs 主 340 行，独立编译单元）。

| 技法 | 位置 | 机制 | 借鉴点 |
|---|---|---|---|
| **depth-only 4-step SSAO 直乘 C0** | `deferred/ssao.fsh:51-59,108` | 仅 depthtex0，每步正负各采（8 tap），antiBleed 抑误遮挡，无独立 AO 缓冲（BSL 改，经 Capt Tatsu 许可） | Astra 完全没有 AO——8 tap/零附加缓冲/静态 IGN，最低配的 AO 起点 |
| **godray 乘性遮蔽链** | `composite1.fsh:362-378`、`composite2.fsh:97-120` | 云透射率→godrayMask，半透明吸收平方再乘，被遮挡置 0；godrays 径向步进乘 directColor | 用 Astra 已有云密度/透射率调 godrays，"云缝光柱/水下光柱"改一处 mask |
| 单一源色派生整维调色板 | `atmos/colorsNether.glsl:26-32`、`colorsEnd.glsl:26-33` | 下界 ambient=fogColor·√2、sky+fog=fogColor·π，一个 uniform 定整维 | Astra 下界的极简降级路径；核对末地光色是否 vanilla 派生 |
| 水下：光谱消光+原版 tint 开关 | `composite1.fsh:97-123` | extinct=1/coeff 归一，`exp(-dist·extinct)`；`waterFogVanillaColor` 时切原版 fogColor | 对应 Astra WATER_CHARACTER 思路，"与原版一致"开关 |
| 输出位深真量化 dither | `grade/final.fsh:43-53` | `c·bits+bayer16-0.5→round/bits`，screenBitdepth 1..8 | banding 终极解；bayer8 扩一级即可 |
| godrayMask 思想同见 Pastel | `composite.glsl:131-136` | 同型 | — |

### 2.8 Pixel Perfect v1.5.2a —— 名不符实但有真金（LGPL）

**预期纠偏**：它**不是**"低分辨率渲染+智能上采样"整链——`size.*`/`scale.*` 命中 0、全部 colortex 全尺寸，"上采样"实为 TAA 历史帧重采样。真金在三处：放大核、世界锚定噪声、噪声资产。TEX_RES=16 texel/block、CUTOUT_ALIGN、pixelated shadows 的像素网格一致性思路自成一派。

| 技法 | 位置 | 机制 | 兼容性 |
|---|---|---|---|
| **9-tap Catmull-Rom 双三次放大核** | `lib/texture/bicubic_filter.glsl:4-57` | "双线性坐标当双三次用"，SIMPLIFY 可砍 5 tap | **完全兼容**：直接替换 Astra godrays/光柱/水下 bloom 的 3×3 box 4-tap 放大——全包最值钱一件 |
| TAA 内 4 邻域纯空间锐化 | `post/1.fsh:118-131,200-203` | `(c-avg)·1.2+avg`，avg 只取当前帧 4 对角邻域（出厂被注释） | 兼容：比 CAS 9 tap 更便宜的 unsharp |
| **世界锚定噪声坐标** | `lib/shading/get_shadow.glsl:36-50`、`common_defs.glsl:487-492` | 抖动噪声坐标用 `absolutePosition.xz + y·100`——相机移动不闪；TAA 开才加 frameCounter | 兼容：比基线已登记的 PIXEL_LOCKED_LIGHTING 更一行式的写法 |
| 3D 蓝噪声卷 + 输出降位抖动 | `shaders.properties:37-39`、`sample_noisetex.glsl`、`post/2.fsh:219-247` | 512×512×7 RGBA8 3D 纹理 8 通道，`tile()` 支持 sharp 量化两态；输出 `+1/256` 噪声判定逐通道降档，绕过 fp16→8bit 转换 | 兼容：蓝噪观感优于 IGN；sharp 态一图两用；`tex/noise/*.py` 可生成 |
| mip 当低分缓冲 | `post/1.fsh:69,223-260` | FAST_GI 用 `colortex1MipmapEnabled` + LOD 8 采光照缓冲，不额外分配 | 兼容：Astra size.buffer 小缓冲加 mipmap 可省独立模糊 pass |
| 远平面+天空掩码存 colortex1 | `buffer_usage.txt`、`post/0.fsh:74-117` | alpha=天空掩码，WATER_MIX_MODE 三态 | 兼容 |
| TEXTURE_FILTERING（t3ssel8r 纹理过滤） | `lib/texture/texture_filter.glsl:2-27` | **死代码**：全包无 textureFiltered() 调用点 | 要用须单独移植函数体，别照抄接线 |

### 2.9 Arc v0.15.2 —— 无 TAA 物理向的取舍清单（MIT，可直搬）

**全程不用 TAA/历史累积**（唯一跨帧物是 0.25× 预曝光缓冲）。取舍清单：FXAA 换 TAA、上帧彩缓冲换 SSR 稳定、单张 tile 纹理换 bloom 金字塔、LUT 换逐像素散射、RGBA32UI 打包换 gbuffer 张数、放弃 DH/Voxy。与 Astra 路线亲和度全场最高。67 选项内联在 `lib/common.glsl` 一处。

| 技法 | 位置 | 机制 | 兼容性 |
|---|---|---|---|
| **log-亮度缓冲上的 FXAA** | `lib/fxaa_2.glsl:8-14`、`final.fsh:191-196` | 邻域比较走 R16F 的 `log2(lum)`，`max(exp2(lum)-eps,0)·exposure` 还原；阈值与曝光解耦 | **完全兼容**：比 Complementary 全 HDR FXAA 省一档带宽；deferred 出口多写一张 R16F 即可 |
| **屏幕空间接触阴影** | `lib/shadows/contact.glsl:1-46` | 沿光方向步进 `mix(24,64,viewDist)` 自适应，静态 Bayer 起点 | **完全兼容**：补 Astra 没有的贴地接触阴影 |
| 单张纹理 bloom tile 金字塔 | `lib/camera/bloom.glsl:2-60`、`composite6-8.fsh` | 逐级 log2 缩小平铺进同一张 colortex（兼 HDR 透明缓冲），整数边界索取 | 兼容：省显存省 pass；Astra colortex2 可与水下缓冲合并 |
| mip 链自动曝光（GPU 内） | `lib/camera/exposure.glsl:29-55`、`composite2.fsh` | colortex5=0.25 预曝光 HDR 带 mipmap，`texelFetch(…, lod)` 逐级平均，无 CPU 回读 | 兼容：Astra colortex10 1×1 + 57 条 CPU uniform 的替代思路 |
| 4 级 CSM 打包单张 shadow map | `lib/shadows/csm.glsl:1-40`、`begin_a.csh` | `tile_dist={5,12,30,80}` 非线性级联，2×2 tile 位置由序号推出 | 兼容：近场 5/12 格级联治近场阴影糊（可只开 0/1 级） |
| 上帧 HDR+深度做 SSR | `lib/ssr.glsl:1-45,132` | 射线走上帧 0.25 彩缓冲+深度，`textureLod(...,lod)/exposure`，可选 HiZ | 兼容：免当前帧不完整问题 |
| **水下相机模糊 = 可分离高斯 13/23 tap 取 mip1** | `composite3-4.fsh:32-35`、`gaussian_7/17.glsl` | H 后 V，全部 `textureLod(...,1)` 预滤抑欠采样，仅水下执行 | **完全兼容**：极便宜的水下"介质感"补丁；mip1 是无 TAA 防闪烁关键 |
| 两段 LUT 天空 + SSBO uniform | `prepare1-2.fsh`、`lib/sky/hillaire*`、`lib/ssbo/scene.glsl` | 32 步 raymarch→256 列 sky LUT→32×16 辐照度 LUT；SSBO 场景 uniform，非 SSBO 平台退回顶点传参 | 兼容：辐照度 LUT 把天光变一次查表 |

---

## 三、跨批综合：最值得 Astra 消化的清单（合并上批视角）

### 3.1 体素/彩光路线（本批最大主题——RV+SPK+Hysteria 三包拼图）
1. **cutout 4-tap alpha 占用判定**（RV `shadow.glsl:205-227`）——叶缝/火把真实体积，现有 shadow.vsh 即可加，一次性零时域。
2. **floodfill 公式升级**：含自身 7 点归一化（SPK）+ 墙角 clamp（SPK）+ 同格颜色累加代 atomicMax（RV）——Astra 64³/8 步链上改公式即得。
3. **低分辨率彩光 + 屏幕匹配上采样 + 体素回落**（RV）——Astra 扩体积/推主世界彩光的唯一零时域结构。
4. **体素图当 3D 邻域查询**（SPK lavaEdge）——熔岩边/灵魂火边，差一个 sampler3D 声明。
5. 位域重排（RV）——一张 r32i 塞下 sky/物种/半透明/发光，省自定义图。
6. 时域方案（SPK 乒乓半率、RV SDF 续算）登记不采纳——与无 TAA 冲突。

### 3.2 AO/GI 空白补齐（Astra 完全没有 AO，本批给出四种免费/低配做法）
1. **depth-only SSAO 8 tap 直乘 C0**（VPS `ssao.fsh`，低配起点）。
2. **GTAO + bent normal + 天光 SH9**（Noble，GPL 可直搬——一次投入得 AO+方向性天光+GI 观感）。
3. **shadowcolor1 法线 + 阴影图 LOD GI + 双边升采样**（Ebin，AGPL；不想引入 AGPL 就只借结构）。
4. **半分辨率计算 + 双边升采样**（Ebin `BilateralUpsample.fsh`）——无 TAA 去噪标准答案，Noble 时间滤波的替代。

### 3.3 无 TAA 降噪范式（Insanity 是现成可行性证据）
低分辨率缓冲 → 静态 dither → 固定核/LOD 模糊 → 强度后置。具体件：Insanity 彩色光轴（7 步对数步长+shadowcolor0 彩色）、平方+lod1.5 合成、log-亮度 FXAA（Arc）、Ebin 双边升采样、水下可分离高斯取 mip1（Arc）。

### 3.4 体积雾（Astra 完全没有 raymarch 雾）
Hysteria 三件套（体腔裁剪+自适应步数+`(1-exp(-od))/od` 解析积分+4 次多散射）+ 云阴影预渲染图 + VPS godray 乘性遮蔽链——从 PERFORMANCE 档就能开。

### 3.5 清晰化/放大（补充上批 CAS/FXAA 之外）
1. **Catmull-Rom 双三次放大核**（PixelPerfect `bicubic_filter.glsl`）替换 godrays/bloom 的 box 4-tap——最值钱一件；LGPL 处理三选一（独立文件保许可/整包 GPL 路线/按原论文自写，推荐自写）。
2. 4 邻域纯空间 unsharp（PixelPerfect，4 tap < CAS 9 tap）。
3. 世界锚定噪声坐标 `x,z+y·100`（PixelPerfect）——一行式防闪烁。

### 3.6 天空/大气/云
离线 Bruneton LUT 当 3D 贴图（Hysteria）或两段 LUT+辐照度查表（Arc）；天空图+SH 一次成型（Hysteria，Astra colortex11 加 9 点 SH）；云棋盘时域上采样+3D worley 贴图（Hysteria，部分兼容可做质量档）；反射 miss 回退烘云进缓存（Noble/Ebin——Astra colortex11 没烘云，补上水面就能反射云）。

### 3.7 风格化/后期
粉彩去饱和配方（Pastel，含 blockLight 保护与亮度回乘）；CG 通道混合器（Pastel）；bloom 幂空间混合（Pastel）；godray 遮蔽链（VPS）；输出位深真量化 dither（VPS）；单源色派生整维调色板（VPS，降级路径）。

### 3.8 工程手法
单张 bloom tile 金字塔（Arc）；mip 链 GPU 自动曝光（Arc）；4 级 CSM 打包（Arc）；mip 当低分缓冲（PixelPerfect）；SH9 藏 9 texel（Noble）；profile 继承/绑档（Insanity/SPK）；下界独立编译单元瘦身（VPS）；SSBO 场景 uniform（Arc）。

---

## 四、与上批结论的增量与重叠

- **重叠确认**（上批已登记，本批再次出现，视为加强证据）：CAS/锐化共识（PixelPerfect/light-shaders/vanillaa）、profile 继承（astralex/Insanity）、阴影畸变（miniature/BSL）、粗糙反射 mip（bloop/BSL/Insanity）、colored light fog（CR/VP）、接触阴影（Noble/Arc 两种实现）。
- **本批独有**：几何着色器体素化与 cutout alpha 占用（RV）、floodfill 公式三件套（SPK）、GTAO bent normal+SH9（Noble）、shadowcolor1-GI（Ebin）、log-亮度 FXAA 与水下 mip1 高斯（Arc）、离线大气 LUT 当 3D 贴图（Hysteria）、godray 乘性遮蔽链（VPS）、Catmull-Rom 放大核（PixelPerfect）。
- **预期纠偏**：Pixel Perfect 名字暗示的"低清+智能上采样"不存在（TAA 系）；其 TEXTURE_FILTERING 是死代码；Arc 才是本批与 Astra 路线亲和度最高的包。

## 五、许可边界（本批）

| 许可 | 包 | 处理 |
|---|---|---|
| MIT | Arc | 表达式可直搬（保留 MIT 头） |
| GPL-3.0 | Noble | 可直搬（保留版权头；与 Astra 现有 GPL 血统同源） |
| AGPL-3.0 | Ebin | 可搬但合并后整体须按 AGPLv3 分发；不想引入则只借结构；THIRD-PARTY 须显式标注 |
| LGPL-3.0 | Pixel Perfect | 逐文件保留许可 / 整包 GPL 路线 / 按公开算法自写（推荐） |
| LicenseRef-Complementary(-Agreement) | RV、Spooklementary | 按各自协议；体素公式类改动建议自写等价 |
| LicenseRef-AGNYA | Insanity、Hysteria | 只登记机制；移植前须读其许可原文 |
| All Rights Reserved | Pastel、Vanilla Plus | 只登记机制与思路，禁止搬表达式 |

所有借规件在实施前仍须：①读许可原文确认条款；②在 `Astra/THIRD-PARTY.md` 登记出处；③符合 docs/README 的"出处按文件及表达式记录"纪律。
