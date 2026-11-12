# Astra 对照本地参考包：尚未实现机制的可实施清单（B 组）

调研日期：2026-10-17。只读调研，未修改 Astra/ 或 reference_shaderpacks/ 下任何文件。
参考包路径一律相对 reference_shaderpacks/<slug>/shaders/；Astra 路径一律相对 Astra/shaders/。

## 读法说明（给非渲染专业读者）

- **阴影贴图**：游戏先用一张“从太阳视角拍下来的深度照片”记下谁挡住了光，渲染时再拿每个像素去这张照片里比深度，判断它是否在阴影里。这张照片叫阴影贴图（shadow map），上面的一格叫一个“纹元”（texel）。
- **级联（cascade）**：一张阴影贴图分辨率有限。级联是把这一张图切成几块：近处那块只盖身边几格、格子小所以清晰；远处那块盖得远、格子大所以糊。这样用有限分辨率同时照顾近处清晰与远处覆盖。“CSM”就是这种做法的缩写。
- **半影（penumbra）**：影子边缘那圈从全黑过渡到全亮的模糊带。遮挡物离被照面越远，这圈越宽。PCSS 就是想还原这个现象。
- **PCSS（百分比渐进软阴影）**：先在被比的那一格附近搜一圈，估出“挡住光的那个东西大概离线多远”，再按这个距离决定模糊半径——近的锐利、远的柔软。
- **SSGI（屏幕空间全局光照）**：用屏幕上已有的画面信息估计“光在这里被弹过一次之后又多亮一点”。不追踪真实光线，只做近似。
- **体素（voxel）**：把世界切成一个个小立方格，在格子里存光强或颜色，光在格子间扩散。Astra 下界已有一套 64³ 的体素光场。
- **AO（环境光遮蔽）/ GTAO**：AO 是缝隙和角落本该更暗的那一点点暗化；GTAO 是其中一种按“地平线角”算的算法，比撒点取平均更少噪点。
- **SMAA**：一种后处理抗锯齿。先找出画面里的边缘，再沿着边缘做混合，把阶梯状锯齿抹平。
- **色差（chromatic aberration）**：真实镜头里红绿蓝三种光折射角略有差别，画面四周边缘会出现轻微的红蓝分离。这是模拟镜头缺陷的效果。
- **视差遮蔽映射（POM / parallax）**：用贴图里画的“高度”信息偏移采样坐标，让平面看起来有起伏厚度。
- **SSBO**：着色器存储缓冲，用来装大量结构化数据的 GPU 内存块，可以用原子操作在多个着色器之间共享。
- **双边模糊**：按深度差给权重做模糊，同深度的邻居权重高、跨物体的邻居权重低，于是不会把两个物体的边界糊在一起。

证据强度统一标注：〔读源码〕= 我实际读了源文件并给出文件:行号；〔实测运行/工具〕= 我在本机跑过 grep/命令并给出实际输出；〔推断〕= 由结构或上文推得，未直接验证。本会话没有做任何实机画面或帧时测量，凡涉及耗时与画质收益的数值一律标“未验证”。

“6 个包”指 arc-shader、photon-shader、complementary-reimagined、mellow、solas-shader、rethinking-voxels（后两个没有独立 LICENSE 文件，见各条的“许可注意”）。

---

## 一、Arc：PCSS 遮挡搜索 + 变半影（最值得直接落地的一条）

### 机制

现在的 Astra 阴影模糊半径是固定的：不管挡住光的东西离被照面是半格还是二十格，影子边缘糊的程度一样。PCSS 分成两步——先在阴影贴图里取一小圈采样点，只统计那些“确实比被照面更靠近太阳”的点，把它们到被照面的平均距离算出来（这叫 blocker search，遮挡体搜索）；再用这个距离放大模糊半径，于是近的窄、远的宽。如果这一圈里一个遮挡物都没搜到，就说明这个像素本来就该是全亮的，直接跳过模糊。

### 参考出处〔读源码〕

- 遮挡体搜索与半影公式：arc-shader/shaders/lib/shadows/csm_render.glsl:118-153（函数 FindBlockerDistance）与 :155-167（GetShadowing 的 PCSS 分支）。
  - :144-146 取 shadowtex0 深度 texDepth；hitDist = max((shadowPos.z - shadowBias) - texDepth, 0.0)，即“这一格挡住光的那面比被照面靠前多少”。
  - :148-149：avgBlockerDistance += hitDist * (far * 3.0); blockers += step(0.0, hitDist);（把归一化深度差换算成世界距离的近似，只有 hitDist>0 的点计入）。
  - :152：return blockers > 0 ? avgBlockerDistance / blockers : -1.0;  没搜到遮挡物返回 -1。
  - :160-161：if (blockerDistance <= 0.0) return 1.0;  无遮挡直接全亮，这是 PCSS 最省的一刀。
  - :165：pixelRadius *= min(blockerDistance * SHADOW_PENUMBRA_SCALE, 1.0);  半影 = 遮挡距离 × 系数，并封顶在 1。
- 系数与采样数：arc-shader/shaders/lib/common.glsl:133 #define SHADOW_PCSS_SAMPLES 4；:141 #define SHADOW_PENUMBRA_SCALE 0.1；:132 #define SHADOW_PCF_SAMPLES 4。
- 采样点位置由一张预生成的 Vogel 圆盘（用黄金角均匀铺开的采样序列，比随机点均匀）提供，见第九条。
- 无 SSBO 时的退化写法（旋转步进 + 蓝噪声半径）：csm_render.glsl:125-141。

### Astra 现状证据

〔实测运行/工具〕在 Astra/shaders 全树用 ripgrep 搜多组关键词，确认没有遮挡搜索这类实现：

| 搜索关键词 | 命中数 |
|---|---|
| pcss、PCSS | 0 |
| penumbra、Penumbra、PENUMBRA | 0 |
| blocker、Blocker、BLOCKER、FindBlocker、avgBlocker | 3（见下） |
| vogel、Vogel、pcssDiskOffset、ssaoDiskOffset、pcfDiskOffset | 0 |

那 3 处 blocker 命中都不是遮挡搜索：block.properties（方块名单文件）、global/lighting/shadowmap.glsl、program/shadow.vsh，是既有的“保守深度”注释用词。

Astra 现有过滤的实际形态〔读源码〕：

- 半径来源是常量乘分辨率：global/lighting/shadowmap.glsl:104 `const float shadowTexelSpread = SHADOW_SOFTNESS * (1.0 / shadowMapResolution);`，SHADOW_SOFTNESS 默认 2，取值 1/2/4（lib/settings.glsl:86）。**没有任何一项依赖遮挡物距离。**
- 过滤主体：global/lighting/diffuse.glsl:277 的函数 surface_shadow_light(...)；四瓣固定偏移在 :324-337，const int lobeCount = 4; 在 :300；spread 由 :302-305 与 :315-318 决定（后者只用像素世界尺寸和贴图边缘换算，仍与遮挡距离无关）。每瓣内部用一次 textureGather 取四角（global/lighting/shadowmap.glsl:186-189 与 :197-204），即 4 瓣 × 4 角 = 16 次比较。
- 门槛：global/lighting/diffuse.glsl:296-337 只在 `ASTRA_SURFACE_SHADOW_FRAGMENT && SHADOW_FILTER_QUALITY > 0` 下走 4 瓣；预算路径（:338-355）只走 2 瓣甚至 1 瓣。

### 迁移落点与代价

- **落点**：在 global/lighting/diffuse.glsl 的 surface_shadow_light 里，:302-305 算出 spread 之后、:324 进入四瓣循环之前，插入一段遮挡搜索；把搜索结果乘进 spread，或让搜索失败时直接 return fallback。所有偏移必须走 Astra 自己的径向畸变换算，不能抄 ARC 的 shadowProjectionSize（那是级联专属）。
- **新增常数**：与 SHADOW_SOFTNESS 并列加两个档（搜索采样数、半影系数）。默认值在落地前必须实测确定，不能照搬 ARC 的 4 与 0.1。
- **每像素新增取数**：按 ARC 默认的 4 次遮挡搜索计，每个着色像素多 4 次 shadowtex1 取数（约等于现有 16 次比较的四分之一）。注意 Astra 现有路径是“每瓣一次 gather 拿 4 角”，遮挡搜索拿不到这种合并，只能一格格单独取；实际是“额外 4 次带硬件比较的单点采样”，不是免费。
- **无新增附件、无新增 pass、无新增声明**：shadowtex1 与 shadowtex0 现已绑定。Astra 的软件比较路径已用 textureGather(shadowtex1, ...)（global/lighting/shadowmap.glsl:188），说明 shadowtex1 作为普通 sampler2D 深度纹理可读，遮挡搜索可直接沿用这个既有读法。

### 风险与前置核实

1. **必须在游戏内并排对比再定档**（未验证）：半影变宽会让同一张 1536/2048 阴影贴图的有效清晰范围缩小。Astra 的观感边界表对阴影有明确上限（docs/实现与限制.md:90：“32 格内接触影保留，新增边缘偏移≤1像素、锯齿增加≤2像素”），变半影可能直接撞上这一条。落地前要在 32 格内的接触影上量一遍。
2. **不能照搬 ARC 的距离换算**：ARC 用 far * 3.0 把归一化深度差换成距离；Astra 的阴影投影是径向畸变的，线性深度换算写在 global/lighting/diffuse.glsl:315-316（worldTexel 那两行）。半影系数必须基于 Astra 自己的世界纹元宽度定标，否则近处会过糊、远处会失效。
3. **与预算路径的关系**：docs/实现与限制.md:90 写明预算档会把阴影柔化上限压到 2。遮挡搜索在均衡档要不要一起降采样数，需要落地时一并决定，不能在高档跑满 4 次而低档同样跑满。
4. **遮挡搜索读哪张深度图要核实**：ARC 固定读 shadowtex0（含透明物）。Astra 的 shadowtex0 与 shadowtex1 分工需按 program/shadow.fsh 的实际附件确认，不能假定与 ARC 相同。
5. **未验证**：是否真的在观感上“更像真实影子”，本会话没有任何游戏内画面。

### 许可注意

reference_shaderpacks/arc-shader/LICENSE:1 第一行是 MIT License，:5-10 授予 “use, copy, modify, merge, publish, distribute” 等权利，条件是 :12-13 要求在副本中保留版权与许可声明。**允许代码级借鉴**，但移植后必须在 Astra 相关文件头标注来源，并按项目规则登记 Astra/THIRD-PARTY.md。注意 LICENSE:3 的版权署名是 Copyright (c) 2022 Minecraft / Shaders，登记时照抄这个署名。

---

## 二、Arc：屏幕空间全局光照（SSGI）——用上一帧 HDR 当间接光来源

### 机制

每个不透明像素朝屏幕四周撒一小圈螺旋采样点，对每个点取出**上一帧画面**的颜色和它自己的深度，换算出一个“这点往这边反射过来多少光”的权重，累加之后当作间接光（被物体反弹一次的光）加到环境光上。它**不做光线步进**：没有射线前进、没有命中判断，只有一个固定螺旋加深度差权重。噪声靠两张牌压下去：一张按深度差加权的双边模糊（不跨物体边界糊），加上“颜色取自上一帧”这件事本身带来的时域平均。

### 参考出处〔读源码〕

- 生产：arc-shader/shaders/program/deferred4.fsh:109-184（函数 GetSpiralOcclusion）。
  - :128 `for (int i = 0; i < SSAO_SAMPLES; i++)`；:130 从 Vogel 圆盘取偏移乘以随步数递增的半径（:121 `float rStep = inv * rad;`）。
  - :142 出屏 continue；:147 深度取的是 BUFFER_DEPTH_PREV（上一帧深度）；:149-153 深度 ≥1.0（天空）跳过。
  - :158-163：用采样点与当前点的向量算出“从当前点看过去，那个点是不是在这个面朝向的一侧”（sampleNoLm = max(dot(viewNormal, sampleNormal) + SSAO_BIAS, 0.0)）。
  - :175 `float giF = sampleNoLm / (l + 1.0);`；:177-179 取 BUFFER_HDR_PREVIOUS（上一帧 HDR 颜色），先做 `sampleColor /= luminance(sampleColor) + 1.0`（色度归一，只保留“这里有多亮”的相对关系），再乘权重累加。
  - :183 `return vec4(20.0 * gi, ao) * inv;`  间接光被放大 20 倍后取平均（这个 20 是配套 SSGI_STRENGTH 口径的艺术系数）。
  - :301-310 是调用处：把当前点反投影到上一帧相机空间（:305-306），再调 GetSpiralOcclusion。
- 同一函数同时产出 AO：deferred4.fsh:165-168（AO_TYPE == AO_TYPE_SS 分支）。输出写 BUFFER_GI_AO：:82 `/* RENDERTARGETS: 9,10,1 */`；lib/constants.glsl:94 `#define BUFFER_GI_AO colortex9`；格式 lib/common.glsl:12 `const int colortex9Format = RGBA16F;`。
- 降噪：arc-shader/shaders/lib/lighting/pbr.glsl:169 `vec4 giaoDeferred = BilateralGaussianDepthBlurRGBA_7x(BUFFER_GI_AO, viewSize, depthtex0, viewSize, lightData.opaqueScreenDepthLinear, deferredSigma);`  一次 7×7 深度双边模糊。
- 消费：pbr.glsl:509-510 `#if defined SSGI_ENABLED && !(defined RENDER_WATER || ...) ... ambient += (giaoDeferred.rgb / sceneExposure) * SSGIStrengthF;`；强度 lib/common.glsl:203-204 的 SSGI_ENABLED 与 SSGI_STRENGTH 100，换算 :299 `const float SSGIStrengthF = SSGI_STRENGTH * 0.01;`。
- 另有 program/final.fsh:291-295 把同一张缓冲当调试视图显示。

### Astra 现状证据

〔实测运行/工具〕Astra/shaders 全树搜索：

| 搜索关键词 | 命中数 |
|---|---|
| SSGI、ssgi、screenSpaceGI、ScreenSpaceGI | 0 |
| BilateralGaussian、GaussianDepthBlur、bilateral、Bilateral | 0（该次 grep 返回空） |

Astra 的环境光侧是无追踪的：lib/ao_resolve.glsl:20-53 的 astra_ao_visibility 只做半分辨率 AO 的双边上采样与 bent normal（把周围未被遮挡采样的方向按权重平均出来的方向）重建；program/ssao.fsh:37-49 的 ASTRA_AO_SAMPLE_DISK[12] 是固定 12 点黄金角圆盘。没有任何“用上一帧颜色当反弹光”的读取。

### 迁移落点与代价

- **好消息**：Astra **已经有上一帧 HDR 可用**——program/taa_resolve.fsh:19-22 声明 `const int colortex15Format = RGBA16F; const bool colortex15Clear = false; /* RENDERTARGETS: 0,15 */`，colortex15 就是 TAA 的未抖动历史（同文件 :1-2 注明 “unjittered HDR output”）。ARC 的 BUFFER_HDR_PREVIOUS 对应的正是这类缓冲，不需要新增附件。
- **坏消息**：ARC 的跟随相机位移重投影（deferred4.fsh:305-306 用 gbufferPreviousModelView 与 previousCameraPosition）在 Astra 已有同类 uniform，所以这一步不需要新 uniform；但详见下面风险第 1 条。
- **落点**：可挂在现有 SSAO 生产位置（program/ssao.fsh）或 program/deferred*.fsh，并复用 colortex21 与 colortex26 之外的输出槽；若要新增一张 RGBA16F 缓冲，见第十一条的附件清单约束。
- **每像素新增取数**：ARC 默认 SSAO_SAMPLES 12（lib/common.glsl:196）。每个不透明像素新增 12 次“上一帧深度 + 上一帧颜色”取数（共 24 次），加一次 7×7 双边模糊（约 49 次带权读取；若降为 5×5 则 25 次）。**这是一条明确比现有 SSAO 更贵的路径。**
- **显式排除**：ARC 只在非水面、非手持、非半透明实体、非受击红闪时消费（pbr.glsl:509）；落地时要写清同样的排除条件，否则水面和手持物会出现上一帧颜色渗入。

### 风险与前置核实

1. **与 TAA 的先后是主要风险**：Astra 的 colortex15 只有在 TAA 开启（lib/settings.glsl:276-277 的 ANTIALIASING 三档互斥，2 为 HDR TAA）时才存在；TAA 关闭时**没有现成的上一帧 HDR**。落地前必须确认这一条：要么只在 TAA 档提供该效果，要么另给一张历史缓冲（那就是新附件）。**未验证。**
2. **Astra 有投影抖动、ARC 没有**：ARC 的屏幕空间螺旋假定重投影后像素位置稳定。Astra 是“场景抖动、历史与输出不抖”（docs/实现与限制.md:79 记载的既有分工），直接照搬螺旋会吃到抖动的相位误差。必须按 Astra 自己的抖动抵消方式修正偏移。**未验证，属落地前必做实验。**
3. **20.0 这个放大系数与 SSGI_STRENGTH 是一套口径**：单独搬其中一个会导致亮度量级完全不对。要么两者都按 Astra 的曝光口径重新推导，要么只借“用上一帧 HDR 当间接光”这个思路自己定系数。
4. **不能据此承诺帧率**：本会话无实机测量。建议先做只读的账面对比（把新增采样次数与现有 program/ssao.fsh 的 12 点比较），再决定是否开实验分支。

### 许可注意

同第一条：arc-shader/LICENSE:1-10 为 MIT，允许代码级借鉴，需保留 :12-13 的版权与许可声明，并登记 Astra/THIRD-PARTY.md。

---

## 三、Arc：点光源分箱（light binning）——把点光源做成按格索引的表

### 机制

把玩家周围的立体空间切成小立方格（bin），每格记录“有哪些点光源照得到这里”和“一共几个”。渲染时每个像素只查自己所在那一格的光源清单，逐个算，而不用遍历全场所有光源。光源清单本身存在一张大整数贴图里，光源的位置、颜色、半径存在一块 SSBO 里。为了避免同一个光源在同一格里被重复记录，每格还带一张按小块拆分的位掩码，用 atomicOr（原子位或，多线程同时写而不会互相覆盖）先判重。这一条给出的是 Astra 目前完全没有的输入维度：**带位置、半径、颜色的实心点光源**（可做带法线的漫反射与高光），而不只是“方块 id 到颜色”的表或体素光场。

### 参考出处〔读源码〕

- 数据布局：arc-shader/shaders/lib/ssbo/lighting.glsl:1-40。
  - :1 `#define LIGHT_MAX_COUNT 4200000000u`；:2 `#define LIGHT_MASK_SIZE (pow3(LIGHT_BIN_SIZE)/32)`。
  - :12-16 `struct SceneLightData { vec3 position; float range; vec4 color; };`；:18-21 `struct LightCellData { uint LightCount; uint[LIGHT_MASK_SIZE] Mask; };`。
  - :29-30 `uint SceneLightCount; SceneLightData SceneLights[];`（binding 2）；:39 `LightCellData[] SceneLightMaps;`（binding 3）。
  - :43-46 `layout(r32ui) uniform ... uimage2D imgSceneLights;`  一张整数图像存每个 bin 里的光源下标。
- 空间划分与对齐：:6-9（SceneLightGridSize = ivec3(LIGHT_SIZE_XZ, LIGHT_SIZE_Y, LIGHT_SIZE_XZ)、SceneLightSize = SceneLightGridSize * LIGHT_BIN_SIZE、LightGridCenter = SceneLightSize / 2、lightMaskBitCount = int(log2(LIGHT_BIN_SIZE))）；:48-51 `vec3 cameraOffset = fract(cameraPosition / LIGHT_BIN_SIZE) * LIGHT_BIN_SIZE;`（格子跟着相机走，但只在半格内对齐，避免每走一步整张表重建）；:65-72 下标与 UV 换算（GetSceneLightUV 把 gridIndex 拆成 4096 列与若干行块）。
- 写入（去重与登记）：:80-102 的 AddSceneLight(position, range, color)。
  - :86-89 由小块坐标算出掩码位 maskIndex 与 bit。
  - :91-92 `uint status = atomicOr(SceneLightMaps[gridIndex].Mask[intIndex], bit); if ((status & bit) != 0) return;`  已登记过就退出。
  - :94-95 `uint gridLightIndex = atomicAdd(SceneLightMaps[gridIndex].LightCount, 1u); if (gridLightIndex >= LIGHT_BIN_MAX_COUNT) return;`  每格封顶。
  - :97-102 再领一个全局光源下标，写 SceneLights[lightIndex]，再把下标写进 imgSceneLights。
- 邻格扩散（:104-133）：`neighborRange = max(range - 1.5, 0.0)`；对可能重叠的邻格做包围盒测试 :75-78 `dot(pointDist, pointDist) < pow2(lightRange)`，命中才把同一光源下标写进邻格。
- 消费：lib/lighting/pbr.glsl:386-454。:388 `int lightCount = GetSceneLights(lightFragPos, gridIndex);`；:396 `for (int i = 0; i < lightCount; i++)`；:399 距离超出 range 的 continue；:406-408 衰减 `lightAtt = 1.0 - saturate(lightDist / light.range); lightAtt = pow5(lightAtt);`；:413-418 半程向量与 N·L；:437-453 可选的 Burley 漫反射与高光 BRDF。
- 参数：lib/common.glsl:219 `LIGHT_BIN_MAX_COUNT 24`；:220 `LIGHT_BIN_SIZE 8`；:221 `LIGHT_SIZE_XZ 16`；:222 `LIGHT_SIZE_Y 8`（即 16×8×16 = 2048 格，每格 8 格边长，总体积 128×64×128 格）。图像附件声明：arc-shader/shaders/shaders.properties:71 `image.imgSceneLights=none red_integer r32ui unsigned_int false 4096 4096`。
- 光源清单本身：lib/lighting/colored_block.glsl:1-277（按方块 id 给颜色、半径、抖动、自发光；:275 `AddSceneLight(blockLocalPos + lightOffset, lightRange, vec4(lightColor, 1.0));`）。
- 写入挂点：program/shadow.gsh:100-111 在几何着色器里判 renderStage 属于四种地形阶段后调 AddSceneBlockLight(vBlockId[0], vOriginPos[0])（:109）。

### Astra 现状证据

〔实测运行/工具〕Astra/shaders 全树搜索：

| 搜索关键词 | 命中数 |
|---|---|
| lightBins、LightBin、LIGHT_BIN、binning、binIndex、clusterLight、tiledLight | 0 |
| std430、SSBO、ssbo、bufferObject | 0 |

即 Astra 目前**完全没有使用 SSBO**，也没有分箱或聚类光照。Astra 现有的局部彩光是下界 64³ 体素光的同帧八步扩散（program/nether_light.csh:1-2 原文 “Same-frame volume (64^3 around the player, eight diffusion steps, no history)”），以及 block.properties 的整方块分组（docs/实现与限制.md:110 有记载）。这两者与“上千个带位置、半径、颜色的实心点光源”不是同一种东西。

### 迁移落点与代价

- **新增硬件设施（最大代价）**：至少 1 个 SSBO 绑定（SceneLights[]）与 1 个 R32UI 的 image（imgSceneLights，ARC 用 4096×4096）。Astra 的 iris.features.optional 现已声明 CUSTOM_IMAGES 与 COMPUTE_SHADERS（shaders.properties），加 SSBO 需要追加声明并确认本机 Iris 支持（ARC 用 IRIS_FEATURE_SSBO 宏门控，说明它存在不支持路径）。
- **写入挂点**：ARC 在阴影几何着色器里顺手登记。Astra 没有几何着色器，地形顶点与片段入口是 program/lit.vsh 与 program/lit.fsh。**每个方块面都写入会导致实际写入量远大于 ARC**（ARC 靠几何着色器一次拿一个图元的方块 id，Astra 只能从顶点属性取）。这一点必须用实际写入计数核实。
- **消费挂点**：Astra 的彩色方块光消费在 global/lighting/blocklight.glsl:111-115 的 block_lighting()（纯标量乘 BLOCKLIGHT_COLOR）。接这套需要在这里插入逐光源循环。
- **每像素取数**：取决于格内光源数（ARC 上限 24）。注意 ARC 的循环对每个光源都从 SSBO 读一次 SceneLightData（:397），没有做本格筛选。Astra 若采用，需要自己加距离剔除或降低格内上限。**无实机测量。**
- **附件**：imgSceneLights 是 image 附件而非 colortex，不占 colortex 编号（不撞第五批汇总里“只剩 colortex7”的约束），但占一个新的 image 槽位。落地前要确认 Astra 现有三个 image（astraVoxelImage、astraLightA、astraLightB）之外还能否再加。

### 风险与前置核实

1. **与已有下界体素彩光的职责边界必须由用户裁决**（这是既有决定，不是新发现）：docs/参考与取舍.md 的“不重新尝试的旧方案”与 docs/实现与限制.md:110 记载下界已有同帧 9 阶段体素彩光。再上一套点光源分箱会出现两套彩光来源。落地前必须明确：是替换、是主世界专用、还是与体素光叠加。
2. **前车之鉴**：shader_research/SUMMARY-batch5.md 的 C06 记录，verlixia、TrueLightFX、Prismarine 三家都留着 `// #undef MULTICOLORED_BLOCKLIGHT //not working properly for some reason` 却默认启用。ARC 这一套是同类机制但实现不同，不能假定它没有同类问题。
3. **每像素 O(格内光源数) 的循环是真实开销**，与 Astra 现有“一次读取一张体素表”的模型完全不同。必须先在实验分支里测最坏情况（同格 24 个光源）的耗时。
4. **LIGHT_MAX_COUNT 与实际数组大小的关系**：ARC 用无界数组 SceneLights[] 声明，靠引擎侧缓冲大小决定上限。Astra 若采用，需要明确声明固定上限，否则行为依赖驱动。
5. **未验证**：本机 Iris 是否接受 `layout(r32ui) uimage2D` 与 atomicOr 组合，以及追加 SSBO 声明后是否影响编译。

### 许可注意

同第一条：arc-shader/LICENSE:1-13 为 MIT，允许代码级借鉴，保留声明并登记。

---

## 四、Photon：GTAO（按地平线角积分的地面环境光遮蔽）

### 机制

现在的 Astra 环境光遮蔽是“朝半球里固定 12 个方向撒点，取被遮住的比例”。GTAO 换一个思路：把半球切成若干**扇形切片**（slice），每个切片只沿左右两个方向推进若干步找“地平线角”（在这个方向上最先挡住视线的高度角），取两边较大的那个角，再用一个**解析公式积分**算出这个切片贡献了多少遮蔽。因为角度的积分是公式直接算出来的（不是采样），同样的噪声水平下需要的采样点数少、噪点更少；同时它顺手产出 bent normal。

### 参考出处〔读源码〕

- 解析弧积分：photon-shader/shaders/include/lighting/ao/gtao.glsl:10-13：`float integrate_arc(vec2 h, float n, float cos_n) { vec2 tmp = cos_n + 2.0 * h * sin(n) - cos(2.0 * h - n); return 0.25 * (tmp.x + tmp.y); }`。
- 单方向最大地平线角：:15-71 的 compute_maximum_horizon_angle。
  - :24 `float step_size = (GTAO_RADIUS * rcp(float(GTAO_HORIZON_STEPS))) * radius;`  步长按半径和步数定。
  - :28-37：先把“沿这个方向走一步落在屏幕哪里”算成 ray_step，再给起点一个抖动（`dither + max_of(view_pixel_size) * rcp_length(ray_step)`）避免规则条纹。
  - :39-46：循环里用 texelFetch 取深度；:44 `if (depth == 1.0 || depth < hand_depth || depth == screen_pos.z) continue;`  天空、手部、与自己同深度都跳过。
  - :58-62：距离衰减 `linear_step(GTAO_FALLOFF_START * GTAO_RADIUS, GTAO_RADIUS, len_sq * norm * rcp(radius))`，GTAO_FALLOFF_START 0.75 见 :8。
  - :64-67：`cos_theta = dot(viewer_dir, offset) * norm;` 再 `cos_theta = mix(cos_theta, -1.0, distance_falloff); max_cos_theta = max(cos_theta, max_cos_theta);`  取整段里最大的地平线角。
  - :70 `return fast_acos(clamp(max_cos_theta, -1.0, 1.0));`。
- 切片主循环：:103-152 的 compute_gtao。
  - :104 `float slice_angle = (i + dither.x) * (pi / float(GTAO_SLICES));`；:106 切片方向；:109-118 把法线投影到与视线垂直的平面上，求出法线相对切片的角 gamma。
  - :121-138：每个切片左右各调一次 compute_maximum_horizon_angle，得到两个地平线角。
  - :140 `ambient_sss += max0(max_horizon_angles.y - half_pi) * rcp_pi;`（顺手算一点次表面散射的量）。
  - :142-147：把两个角相对 gamma 夹到 ±90 度，再 `ao += integrate_arc(max_horizon_angles, gamma, cos_gamma) * len_sq * norm;`。
  - :150-151：bent normal 累加 `viewer_dir * cos(bent_angle) + ortho_dir * sin(bent_angle)`。
  - :154-160：多次弹射近似 `const float albedo = 0.2; ao /= albedo * ao + (1.0 - albedo);` 与 bent normal 归一化。
- 调用与半分辨率：photon-shader/shaders/program/d3_ao.fsh:84 `const float ao_render_scale = 0.5;`；:87-89 网格对齐；:156-175 选 AO 实现；:179-242 时域累积（max_accumulated_frames = 10.0、depth_rejection_strength = 16.0、offcenter_rejection_strength = 0.25；历史权重 :232 `pixel_age / (pixel_age + 1.0)`；bent normal 用 slerp 球面插值 :235）；:14-19 输出布局 ambient = (ao, ambient_sss, bent normal xy) 与 ambient_history_data = (depth, pixel age)，`/* RENDERTARGETS: 6,14 */`。

### Astra 现状证据

〔实测运行/工具〕Astra/shaders 全树搜索：

| 搜索关键词 | 命中数 |
|---|---|
| maximum_horizon、integrate_arc、GTAO_SLICES、GTAO | 0 |
| bentNormal、bent_normal | 9（全部在 lib/ao_resolve.glsl） |
| vogel、Vogel | 0 |

**必须说清的一点**：Astra 已经有一个叫 bent normal 的东西，但它**不是 GTAO 的 bent normal**。lib/ao_resolve.glsl:20-53 的 astra_ao_visibility 是把半分辨率 AO 结果的 4 个邻居按双线性权重、深度一致性和法线一致性的乘积加权平均出来的方向（:39 `weight=spatialWeight*exp2(-64.0*depthDifference)*pow8(agreement)`），也就是“把周围未被遮挡的采样方向按权重平均”。GTAO 的 bent normal 是每个切片的两个地平线角的平均方向（gtao.glsl:149-151）。两者用途相同（给天光重估一个方向），构造方式不同。因此**不能把“已经有 bent normal”当作“已经有 GTAO”**。

Astra 现有 AO 的生产细节〔读源码〕：program/ssao.fsh:22-34（colortex21 为 RGBA16F，存可见度与法线；colortex26 为 RG16F，存 bent normal；`/* RENDERTARGETS: 21,26 */`），:37-49 固定 12 点黄金角圆盘 ASTRA_AO_SAMPLE_DISK[12]，:57 水下非薄水层直接退出。文件头 :1 原文写 “no TAA dependency”，即当前 AO 不依赖时域累积。

### 迁移落点与代价

- **可以原地换内核**：Astra 的 AO 也是半分辨率，输出契约（可见度 + bent normal）与 GTAO 一致。替换点就是 program/ssao.fsh 里那 12 点圆盘的循环（:37-49 与调用处），下游 lib/ao_resolve.glsl 的双边上采样与 SH（球谐，用几个系数近似环境光方向分布）重估可以不动。
- **新增常数**：切片数、每切片步数、衰减起点。起步值应参考 Photon 的实际设置；本会话未读取 photon-shader 的 GTAO_SLICES 与 GTAO_HORIZON_STEPS 定义行，属**未验证**。
- **每像素取数**：GTAO 是每切片 2 次 compute_maximum_horizon_angle，每次 GTAO_HORIZON_STEPS 次取深度，即每切片 2 × HORIZON_STEPS 次。若取 2 切片 8 步，是 32 次；Astra 现在是 12 次。**这是约 2.5 到 3 倍的取数增量**，除非把切片与步数压得更低再靠时域累积补。
- **必须同时新增的机制**：Photon 的 GTAO 靠 d3_ao.fsh:179-238 的时域累积压噪点（最多累积 10 帧）。Astra 的 AO 现在是“无 TAA 依赖”的。**换 GTAO 就必须同时加一套 AO 历史缓冲**，否则噪点会比现在的 12 点圆盘更明显。这是这条最容易被低估的代价。

### 风险与前置核实

1. **历史缓冲的附件成本**：Photon 用两张（AO 与编码 bent normal 一张、历史数据一张，d3_ao.fsh:14-19 的 location 0 与 1）。Astra 现在 AO 无历史，加历史至少多一张 colortex。这与 shader_research/SUMMARY-batch5.md 第①节第2点“0-6、8-31 全部在用，只剩 colortex7 空闲”的约束直接冲突。**落地前必须先做附件规划。**
2. **bent normal 语义变化会影响天空重估**：lib/ao_resolve.glsl:42-48 现在把重建出的 bent normal 送去 astra_directional_sky_coeffs。换成 GTAO 的切片平均方向后，SH 重估的输入分布不同，天空颜色分布会变。这是画质风险，需要并排对比，不能只测帧率。
3. **抖动源要沿用 Astra 自己的**：Photon 用 noisetex 取两个通道做抖动（d3_ao.fsh:102-105，:152 再用 r2(frameCounter, dither) 做时间维展开）。Astra 用的是 lib/bayer.glsl 的 8×8 Bayer 与 IGN。换 GTAO 时抖动源要沿用自己的，不能引入 noisetex。
4. **未验证**：本会话没有读取 Photon 的 GTAO_SLICES 与 GTAO_HORIZON_STEPS 实际数值，也没有任何实机对比。上面 32 次只是按其循环结构的推算。

### 许可注意

reference_shaderpacks/photon-shader/LICENSE:1-3 是 “Photon Shaders License Agreement”；:5 原文 `All rights reserved unless otherwise explicitly stated.`；:7-14 列出允许的行为：个人使用、修改、**“Examine and learn from Photon Shaders's source code.”**（研读与学习）、以及有条件再分发——但 :12 明确 `You may not redistribute Photon Shaders or derivative works on platforms that provide direct or indirect monetary compensation to creators (e.g. Modrinth, CurseForge) without my explicit written permission.`；:16 要求随实质副本附带本许可全文。**结论：这是“有条件再分发”，不是无条件书面许可，也不是 MIT。** 研读并按机制自写没有问题；若要把 Photon 的代码直接带进 Astra 并在 Modrinth 或 CurseForge 之类有创作者收益的平台上发布，按 :12 需要 SixthSurge 的明确书面许可。GTAO 的数学本身是公开文献，实现可按公式自己写以规避这一条。

---

## 五、Photon：棋盘云上采样契约（低分辨率云重建到全屏）

### 机制

云渲染很贵，所以先按较低分辨率只算一部分像素（比如每 2×2 里算一个），然后放大回全屏。放大时不能简单插值——云是半透明的、会动、有遮挡关系。Photon 的做法是：目标像素看自己在棋盘格里的位置，如果这一帧正好是它被算过的那一格，就用本帧新算的结果；否则从上一帧历史里取，并把历史按当前帧的 3×3 邻域做软性的上下界夹取（避免拖影），再按像素年龄决定历史权重。

### 参考出处〔读源码〕

- 棋盘偏移表：photon-shader/shaders/include/utility/checkerboard.glsl:4-49（checkerboard_offsets_2x1、_2x2、_4x2、_3x3、_4x4 五种排布），:51-59 按 CLOUDS_TEMPORAL_UPSCALING 档位选表。
- 上采样主体：photon-shader/shaders/program/d2_clouds_upscaling.fsh:182-386。
  - :183-184 `const int checkerboard_area = CLOUDS_TEMPORAL_UPSCALING * CLOUDS_TEMPORAL_UPSCALING;`。
  - :186-191 dst_texel（目标全屏像素）与 src_texel（低分辨率源像素）的换算。
  - :250-254：closest_distance 取本帧与上一帧 4×4 区域里最近的云距离（texture_min_4x4），用于判断地形是否真的挡在云前面。
  - :257-267：被地形挡住就写回当前值并把像素年龄清零（相当于放弃历史）。
  - :270 云的重投影；:282-288 用 catmull-rom 双三次取历史（`catmull_rom_filter_fast(colortex11, ..., 0.5)`）。
  - :302-314 失配判定（出屏、被地形挡住、手部、NaN、世界年龄变化）。
  - :316-350 快速移动时的邻域夹取：velocity_factor 由相机位移与 frameTime 平方归一，大于 0.1 才做；3×3 邻域用“软最小与软最大”（:338-346：`aabb_min = min_of(b, d, e, f, h); aabb_min += min_of(aabb_min, a, c, g, i); aabb_min *= 0.5;`）。
  - :357-365 **棋盘的核心判断**：`ivec2 offset_0 = dst_texel % CLOUDS_TEMPORAL_UPSCALING; ivec2 offset_1 = clouds_checkerboard_offsets[frameCounter % checkerboard_area]; if (offset_0 != offset_1 && !disocclusion) { current = history; apparent_distance = min(apparent_distance, apparent_distance_history); ambient_scattering = history_data.z; }`。
  - :367-368 `float pixel_age = max0(history_data.y) * float(!disocclusion); float history_weight = 1.0 - rcp(max(pixel_age - checkerboard_area, 1.0));`。
  - :381-385 输出与像素年龄递增（`min(++pixel_age, CLOUDS_ACCUMULATION_LIMIT)`）。
- 低分辨率生产侧：program/d1_clouds.fsh:128 `const int checkerboard_area = ...`；:161-165 用 `clouds_checkerboard_offsets[frameCounter % checkerboard_area]` 选本帧要算的格。

### Astra 现状证据

〔实测运行/工具〕Astra/shaders 全树搜索 `checkerboard`、`Checkerboard`、`CHECKERBOARD` = **0 命中**。

Astra 的云是另一条路线：docs/实现与限制.md:9 明确“默认高档云独立于预算，保持原生尺寸、每像素4条固定子像素射线、4格目标积分间距和512段上限”。云历史存在，但存在形式是“真实移动 0.5 至 2.5 像素时逐渐退出历史”（同段），没有棋盘格上采样。

**与既有驳回项的区别**：docs/参考与取舍.md 的“不重新尝试的旧方案”里写有“高档云优先质量，不采用棋盘格替代四射线”。那一条针对的是**用棋盘格降低每像素射线数**。本条（Photon 的 d2）是**把已经算好的低分辨率云重建回全屏**的契约，两者是不同层次的东西；但最终都会触及“云的分辨率”这一条，因此落地时必须先取得用户对“高档云保持原生尺寸”这一既有边界的确认，不能自动开工。

### 迁移落点与代价

- 需要三件东西：一张低分辨率云颜色缓冲、一张云附加数据缓冲（距离、像素年龄、环境散射）、以及一张上一帧云历史。Photon 分别用 colortex9、colortex10、colortex11、colortex12（d2_clouds_upscaling.fsh:184-294 的读取点）。
- **Astra 已有云历史**（global/atmosphere/cloud_temporal.glsl 被 docs/实现与限制.md:9 引用），所以若要做，落点应接在现有云历史消费处，而不是新建一套。
- **每像素新增取数**：重建是每像素 1 次历史读取（catmull_rom_filter_fast 约 4 次 texelFetch），加最多 9 次邻域 texelFetch（只在快速移动时）。比现在“每像素 4 条射线”便宜得多——但这正是与既有边界冲突的地方。

### 风险与前置核实

1. **与现有用户边界直接冲突（必须前置裁决）**：docs/实现与限制.md:9 与 docs/参考与取舍.md 都写明高档云保持原生尺寸、不用棋盘格替代。本条只有在用户明确同意“允许云在低分辨率算再重建”之后才成立。
2. **云的遮挡关系依赖深度，棋盘格会让边缘错位**：Photon 必须靠 texture_min_4x4 与逐像素深度判定来纠正（d2_clouds_upscaling.fsh:250-267）。Astra 的云与地形遮挡处理在别处，落地前要核对两者是否会互相打断。
3. **未验证**：本会话没有读取 Photon 的 CLOUDS_TEMPORAL_UPSCALING 档位定义与 CLOUDS_ACCUMULATION_LIMIT 的数值。

### 许可注意

同第四条：photon-shader/LICENSE:5 保留所有权利；:10 允许研读学习；:12 禁止在有创作者收益的平台再分发衍生作品（需书面许可）。**可研读并按机制自写；直接搬代码后在有收益平台发布需要书面许可。**

---

## 六、Photon：阴影畸变与 PCSS 的关键公式（只作机制对照，不建议改 Astra 已有畸变）

### 机制与公式要点

Photon 的径向畸变不是常用的“按距离比例”，而是**四次方根长度**：`quartic_length(v) = sqrt(sqrt(v.x^4 + v.y^4))`。效果是对角线方向的距离比欧氏距离小，即畸变在斜方向更弱。偏移与反偏移是显式的一对函数（distort_shadow_space 与 undistort_shadow_space）。它的阴影 bias 是**法线偏移**形式（把采样点沿世界法线推出去一点），随距离和 N·L 变大，用来避免影子与物体脱开（peter-panning）。

### 参考出处〔读源码〕

- photon-shader/shaders/include/lighting/shadows/distortion.glsl:6-9 quartic_length 的注释与实现；:11-14 `float get_distortion_factor(vec2 shadow_clip_pos) { return quartic_length(shadow_clip_pos) * SHADOW_DISTORTION + (1.0 - SHADOW_DISTORTION); }`；:16-19 distort_shadow_space；:26-31 undistort_shadow_space（`shadow_clip_pos.xy *= (1.0 - SHADOW_DISTORTION) / (1.0 - quartic_length(shadow_clip_pos.xy));`）。
- 法线偏移 bias：:36-43 `return 0.25 * normal * clamp01(0.12 + 0.01 * length(scene_pos)) * (2.0 - clamp01(NoL));`；:33-35 注明来源是 Complementary Reimagined 的 Emin 并已获许可。
- PCSS 的关键量：pcss.glsl:26-27（shadow_map_res 与 shadow_map_pixel_size）；:102-110（distortion_factor、`min_filter_radius = 2.0 * shadow_map_pixel_size * distortion_factor`、`filter_radius = max(penumbra_size, min_filter_radius)`、`filter_scale = sqr(filter_radius / min_filter_radius)`、step_count 随后随半径增长）；:118-158 先跑 4 次，全亮或全暗提前退出（:154-158 `if (shadow > 4.0 - eps) return color; else if (shadow < eps) return vec3(0.0);`）；:175-181 半影窄于一个纹元时的锐化（`sharpening_threshold = 0.4 * max0((min_filter_radius - penumbra_size) / min_filter_radius);` 再做 linear_step）；:243-250 半影公式 `penumbra_size = 16.0 * SHADOW_PENUMBRA_SCALE * (shadow_screen_pos.z - blocker_search_result.x) / blocker_search_result.x;`，随后 `penumbra_size *= 5.0 - 4.0 * cloud_shadows;`（云影区加宽 5 倍），再 `penumbra_size = min(penumbra_size, SHADOW_BLOCKER_SEARCH_RADIUS); penumbra_size *= shadowProjection[0].x;`。
- pcss.glsl:29-62 的 blocker_search：:30 `int step_count = has_sss ? SSS_STEPS : 3;`；:36-37 搜索半径随太阳高度 `linear_step(0.2, 0.4, light_dir.y)` 变化；:44 用 vogel_disc_sample；:49-54 只累加 `step(depth, ref_z)` 为 1 的点；:57-61 返回 `vec2(blocker_depth, sss_depth)`。

### Astra 现状证据

〔实测运行/工具〕Astra 已有径向畸变（lib/distort.glsl、global/lighting/shadowmap.glsl 的 SHADOW_DISTORT_FACTOR，见 global/lighting/diffuse.glsl:315-316）；docs/参考与取舍.md 的“阴影矩阵、Bias 与过滤”一节明确要求“不能仅因 Photon 公式不同就断言缺少畸变补偿，也不能照搬它的 Bias 数值、投影比例或漏光修正”。**因此本条不构成迁移项，只作对照。**

差异点（可用于判断 Astra 现有畸变是否够用）：Photon 用的是四次方根距离，Astra 用的是 lib/distort.glsl 中的径向形式，两者的斜方向行为不同。**未验证哪一个在可见画面上的斜角漏光更少。**

### 迁移落点与代价

无迁移建议。若将来要比较，唯一可做的是一次只读的数值对照（把同一个世界坐标分别过两套畸变函数，看偏移差多少），不需要改任何代码。

### 风险与前置核实

- docs/参考与取舍.md 已把这条列为“不重新尝试”的对象。**若没有新的画面证据（例如斜角阴影出现可复现的漏光），不应重开。**
- Photon 的 bias 公式里 0.25 与 (2.0 - clamp01(NoL)) 是配套它的畸变与深度比例的，**数值不可照搬**（同段已写明）。

### 许可注意

photon-shader/LICENSE:5-10（保留所有权利、允许研读）。另需注意 distortion.glsl:33-35 自己注明 bias 方法来自 Complementary Reimagined 的 Emin 并获许可——**即 Photon 的许可不覆盖这一段的上游**。任何涉及该段的使用都必须回到 Complementary 的许可处理。

---
## 七、Complementary Reimagined：全屏色差（chromatic aberration）

### 机制

在最终显示阶段，按“像素离画面中心有多远”把红通道和蓝通道朝相反方向偏一点点采样，绿通道不动。画面中心没有偏移、越靠边越明显。它模拟真实镜头的色散。

### 参考出处〔读源码〕

- complementary-reimagined/shaders/program/final.glsl:102-106：

      #if CHROMA_ABERRATION > 0
          vec2 scale = vec2(1.0, viewHeight / viewWidth);
          vec2 aberration = (texCoordM - 0.5) * (2.0 / vec2(viewWidth, viewHeight)) * scale * CHROMA_ABERRATION;
          color.rb = vec2(texture2D(colortex3, texCoordM + aberration).r, texture2D(colortex3, texCoordM - aberration).b);
      #endif

  即偏移量正比于“离中心的偏移向量”，并被屏幕尺寸归一化，所以不同分辨率下观感一致。
- 模糊区专用版本（景深的每个采样点也带色差）：program/composite3.glsl:91-98 与 :107-113。:94-97 先把离中心偏移开方（chromaticScale = sign(chromaticScale) * sqrt(abs(chromaticScale))）让边缘增长更缓，再乘模糊圆半径 coc；:110-112 对 18 个模糊采样点分别取 R、G、B，红蓝各偏 aberration。
- 选项文案（含它自己的警告）：lang/en_US.lang:780-781 的 option.CHROMA_ABERRATION 与注释 Chromatic Aberration can cause the image to feel ...

### Astra 现状证据

〔实测运行/工具〕Astra/shaders 全树搜索 chromatic、Chroma、CHROMA、aberration、Aberration、dispersion = 2 命中，都不是色差：

- global/post/end_sky_tonemap.glsl:3 的注释 Astra sky-only chromaticity-preserving shoulder（讲的是保色相的色调曲线）；
- lib/twilight.glsl:78 的注释 for any chromatic midtone the ratio is NOT 1（讲的是调色曲线）。

**没有全屏色差实现。** Astra 现有“显示阶段的屏幕空间效果”只有 FXAA 与 TAA（lib/settings.glsl:276-277 三档互斥）与暗角（global/post/grading.glsl:235 的 apply_vignette）。第五批汇总已记录“屏幕空间相机效果整段空白（景深、运动模糊、镜头光晕、局部曝光、锐化全部 0 命中）”，色差同属该组。

### 迁移落点与代价

- **落点**：program/display.fsh（docs/实现与限制.md 与第五批汇总都把锐化一类挂在 program/display.fsh:258-264 附近）。必须在色调映射之后的显示空间做，因为偏移采样要在已经可以显示的颜色上取，而不是 HDR 上；CR 的 final.glsl 读的 colortex3 正是显示阶段的颜色。
- **每像素新增取数**：CR 是全屏固定 3 次取数（R、G、B 各一次，其中 G 那次是无偏移的原始读取，可以省掉），实际新增 2 次取数。这是本清单里最便宜的一条。
- **新增常数**：一个 0 到 2 的强度档。CR 的 CHROMA_ABERRATION 默认值本会话未读取，属**未验证**。
- **无新增附件、无新增 pass。**

### 风险与前置核实

1. **色差会破坏 TAA 的一致性**：program/taa_resolve.fsh:24-28 在 YCoCg 空间做邻域夹取（taa_ycocg 与 taa_rgb），YCoCg 依赖三通道的比例关系。若色差插在 TAA 之前，会把红蓝分开、破坏这个一致性。**因此必须放在 TAA 之后**（显示阶段天然满足）。
2. **Astra 的观感边界表**（docs/实现与限制.md:100）写“后处理与合成：保留输出分辨率及抗锯齿；颜色与深度配对、背景与一次施雾关系保持，不允许合成错误”。色差会改变输出像素与源像素的对应关系，**在边界上属于需要用户确认的新观感**，不能当作纯优化自动落地。
3. **字体与界面会一起被色差**：CR 是全屏后处理，界面也在内。Astra 若有不想被影响的对象（例如调试文字），需要单独排除。
4. **未验证**：CR 的 CHROMA_ABERRATION 实际默认值与它对画质的主观影响，本会话没有实机画面。

### 许可注意

reference_shaderpacks/complementary-reimagined/License.txt:1 是 Complementary License Agreement 1.7。:9-13 明确 Normal Usage 不含 Redistributing (parts of) The Pack 与 Modifying code of The Pack。**结论：不允许直接借用 CR 的代码。** 但色差的数学（按离中心距离偏移红蓝通道）是公开的通用做法，按公式自写没有障碍。CR 的 program/composite3.glsl:97 用的 15.0 与 final.glsl:104 的 2.0 是它自己的标定，自写时要按 Astra 的屏幕归一方式重定。

---

## 八、Mellow：SMAA 的完整落点与接线方式

### 机制

SMAA 分三遍做抗锯齿：第一遍找边缘（比较相邻像素的颜色差，超过阈值的算边缘，并把边缘的形状编码成两个通道）；第二遍沿水平与垂直方向分别搜索这条边的两个端点，用一张预计算的“面积查找图”查出混合权重；第三遍按权重把相邻像素混进来。查找图是两张提前算好的小图片（不是逐帧算的）：一张给出“搜索到多远就停”（search），一张给出“该混多少”（area）。

### 参考出处〔读源码〕

- 距离度量：mellow/shaders/global/post/smaa.glsl:1-10 的 redmean：float r = step(0.5, mix(a.r, b.r, 0.5)); return sqrt(dot(d*d, vec3(2.0 + r, 4.0, 3.0 - r)));（按人眼对红绿蓝的敏感度加权的颜色距离，权重随红色分量高低切换）。
- 两张查找贴图的换算：:24-34 的 search_length：const vec2 SEARCH_TEX_SIZE = vec2(66, 33);、Scale = SEARCH_TEX_SIZE * vec2(0.5, -1.0) + vec2(-1, 1);、Bias = SEARCH_TEX_SIZE * vec2(Offset, 1) + vec2(0.5, -0.5); 再各除以 vec2(64, 16)（原表尺寸），最后 texture(colortex5, Sample * Scale + Bias).r。
- 四向搜索：:36-83（SMAASearchXLeft、XRight、YUp、YDown）。循环条件 :38-40：while (texcoord.x > end && e.g > 0.8281 && e.r == 0.0)（0.8281 是“这还是一条边”的软截止；e.r==0 表示没有横向交叉边打断）。结束偏移 :45：float offset = fma(-(255.0 / 127.0), search_length(e, 0.0), 3.25);
- 面积查表：:85-88 的 sample_area：vec2 Coord = 16 * round(4 * vec2(e1, e2)) + vec2(d1, d2) + 0.5; return texture(colortex3, Coord / vec2(160, 560)).rg;（把两个边缘强度量化成 16 档、加上两个距离，映射到 160×560 的面积图）。
- 落点与接线（mellow/shaders/properties）：
  - 两张查找贴图的绑定：:51 texture.composite.colortex3=/img/smaaArea.png；:52 texture.composite.colortex5=/img/smaaSearch.png。
  - 三遍程序开关：:110-121 的 program.world0/composite9.enabled=SMAA、composite10、composite11（world0、world-1、world1、world_modded 各三条）。
  - 默认档位：:145 profile.FABULOUS=... SMAA ...。
- 实际 pass 实现（Mellow 把设置块抄进了每个程序，行号按 program/ 下的 .fsh）：
  - 第 1 遍（边缘与阈值）：mellow/shaders/program/composite9.fsh:347-351：float Threshold = SMAA_THRESHOLD; Threshold /= 2 - isOutdoorsSmooth; vec2 Edges = step(Threshold, D);  **室内（isOutdoorsSmooth 小）时阈值除以接近 2 的数，即更灵敏。**
  - 第 2 遍（混合权重）：mellow/shaders/program/composite10.fsh:350-455：四向搜索 :350-393、面积查表 :395、PosOffset 由 SMAA_SEARCH_DISTANCE 给出 :416、Coords.x = SMAASearchXLeft(...) :422、Color.rg = sample_area(d.x, d.y, eL, eR) :436。
  - 第 3 遍：mellow/shaders/program/composite11.fsh:270 起 #ifdef SMAA 的混合段。
- 档位与选项：mellow/shaders/program/composite9.fsh:175-176： #define SMAA_THRESHOLD 0.30 与 #define SMAA_SEARCH_DISTANCE 16 // [8 16 24 32 48 64]。

### Astra 现状证据

〔实测运行/工具〕Astra/shaders 全树搜索 SMAA、smaa = **0 命中**。

Astra 现有抗锯齿只有两档且互斥：lib/settings.glsl:276-277 的 ANTIALIASING（0 关、1 显示空间 FXAA、2 HDR TAA）；global/post/fxaa.glsl 是既有 FXAA。

**与既有驳回项的关系（重要）**：shader_research/SUMMARY-batch5.md 的 C03 已把 SMAA 归入“卡在只剩 colortex7 空闲”的三遍之一，并记录 Astra/THIRD-PARTY.md:465 已登记为不引入，给出的书面理由是“与 §7.B.10（当前阶段不引入 TAA／AA）一致”。但同一批汇总也指出：Astra **现在已经有 FXAA 与 TAA**（lib/settings.glsl:276-277 三档），**原登记的前提已经过时**。因此这是一条“需要重新裁决”的项，而不是不可推翻的既有裁决。本条据此保留，但必须由用户重新裁决后才能开工。

### 迁移落点与代价

- **需要两个中间目标同时活着**：第 1 遍写边缘图；第 2 遍同时读边缘图与两张查找表、写混合权重图；第 3 遍读混合权重图与场景色。即至少两张全分辨率缓冲。Astra 的附件余量参见 shader_research/SUMMARY-batch5.md 第①节第2点（只剩 colortex7）。**这是本条最大的阻碍，不是算法本身。**
- **两张查找表可以走 customTexture，不占 colortex**：Mellow 用 shaders/properties:51-52 把查找表绑到 colortex 槽上。Astra 已有 15 处 customTexture（第五批汇总记录），可以改用 customTexture 从而不挪用 colortex 编号。这一步是本条唯一能把附件成本压下来的办法。
- **每像素新增取数（1080p 量级推算）**：第 1 遍约 7 次取数（无边缘时提前退出）；第 2 遍是最贵的一段，含四向搜索与两次面积查表，量级在 60 到 90 次表读与运算；第 3 遍约 9 次取数。**合计高于 Astra 现有 TAA 解析。** 这一条与第七条（色差，2 次取数）不在一个量级。
- **接入方式**：应是 ANTIALIASING 的第 4 档，与 FXAA 和 TAA **互斥而非叠加**。

### 风险与前置核实

1. **与投影抖动的冲突（硬阻断）**：SMAA 假定输入没有亚像素抖动。Astra 的 TAA 档会给场景加投影抖动（program/taa_resolve.fsh:1-2 原文 unjittered HDR output，说明抖动加在场景阶段、输出不抖）。SMAA 与 Astra TAA 同开会让 SMAA 把抖动当成边缘。**要么互斥，要么只在无抖动档提供。**
2. **附件规划必须先做**：两个全分辨率中间目标在现有附件表里排不进去。落地前必须先确认“哪两张能在什么开关组合下同时存活”，不能假定 colortex7 够用。
3. **redmean 的许可问题**：第五批汇总记录 smaa-mc 那份 redmean.glsl 是 CC BY-SA 3.0（同一许可的传染性），并建议“那 8 行自己写”。Mellow 这份（global/post/smaa.glsl:1-10）虽然更短，但同源，**建议按公式自写而不是复制**。
4. **无边缘时提前退出的收益需实测**：第 1 遍无边缘时可以整体跳过后续，天空和纯色地面占屏比例高时收益明显；Astra 的地形细节多，实际比例未验证。

### 许可注意

reference_shaderpacks/mellow/LICENSE:1-7 是 MIT（Copyright (c) 2026 TheCMK），允许代码级借鉴，保留声明并登记。另有一份 LICENSE-APACHE（Apache 2.0 全文，:1-6）。**两份许可并存，落地前必须先确认要借用的具体文件受哪一份约束**（Mellow 的 read before you edit.txt 可能给出说明，本会话未读取，属**未验证**）。稳妥做法：只按机制自写，不复制。

---

## 九、Arc：Vogel 圆盘与逐帧预生成（对照记录，不作为迁移项）

### 机制

在一台只有 1 个线程的计算着色器里，每帧提前把“固定分布的圆盘采样点”算好写进一块缓冲区，之后各个着色器直接用，不用每像素重算 cos 与 sin。这种固定分布叫 Vogel 圆盘，用黄金角把点均匀铺开，比随机点分布更均匀、比网格更自然。

### 参考出处〔读源码〕

- 生成：arc-shader/shaders/program/setup.csh:8（layout (local_size_x = 1, local_size_y = 1, local_size_z = 1) in; 即单线程）、:20-24 GetVogelSample（float theta = index * GOLDEN_ANGLE + PHI; float r = sqrt((index + 0.5) * sampleCountF);）、:26-29 GetVogelDiskSample（return vogelSample.xy * vogelSample.z;）。
- 存储：arc-shader/shaders/lib/ssbo/vogel_disk.glsl:7-10（vec2 pcfDiskOffset[32]; vec2 pcssDiskOffset[32]; vec3 sssDiskOffset[32]; vec2 ssaoDiskOffset[32];）。
- 填充与栅栏：setup.csh:32-49（按各功能的采样数分别填充），:52 barrier();。
- 各功能的采样数来源：PCF :34-36、PCSS :38-40、SSS :42-44、SSAO :47-49。

### Astra 现状证据

〔实测运行/工具〕Astra/shaders 全树搜索 vogel、Vogel、VOGEL、goldenAngle、GOLDEN_ANGLE = **0 命中**。

但 Astra **已有等价的黄金角圆盘**，只是写成源码常量表：program/ssao.fsh:35-49 的 const vec2 ASTRA_AO_SAMPLE_DISK[12]，且 :35-36 注释原文说明其取舍：“Fixed golden-angle disk. Keep the original expressions as constants rather than rounded coordinates; every receiver uses the same twelve offsets.”（刻意保留原始表达式而不是四舍五入后的坐标）。

**按任务要求（Astra 已有等价实现则删除该条），这一条不作为迁移项。** 仅作实现形式的对照记录：Astra 用常量表换掉了每帧的缓冲区写入与 SSBO，代价是改采样数必须改源码，收益是零额外设施。

### 迁移落点与代价

无。唯一的可借用点是“预生成”这个形式：一旦将来 Astra 的采样数变成运行时可配（例如 PCSS 随半径变步数），预生成会比常量表合适。在 Astra 目前“固定模板加编译期档位”的做法下不需要。

### 风险与前置核实

无。

### 许可注意

不涉及借用。

---

## 十、Solas：水面视差位移的形式与 Astra 的现状（对照，及一条真实缺口）

### 机制

Solas 给水面做 4 步视差：每步读出当前采样位置的水面高度，把横坐标挪动“高度乘视线方向除以视距”这么一点，再读一次高度，迭代 4 次，得到最终用于求法线的位置。这 4 步是固定次数的，不是收敛式的。

### 参考出处〔读源码〕

- solas-shader/shaders/lib/water/waterNormals.glsl:33-42：

      vec3 getParallaxWaves(vec3 waterPos, vec3 viewVector, float viewDistance) {
          vec3 parallaxPos = waterPos;
          for(int i = 0; i < 4; i++) {
              float height = -1.25 * getWaterHeightMap(parallaxPos, vec2(0.0)) + 0.25;
              parallaxPos.xz += height * viewVector.xy / viewDistance;
          }
          return parallaxPos;
      }

- 消费：:45 vec3 waterPos = getParallaxWaves(worldPos + cameraPosition, viewVector, viewDistance); 随后 :47-55 在视差修正后的位置求 4 个方向的高度差得到法线。
- 另有地形用的完整视差遮蔽映射（POM）：lib/pbr/parallax.glsl:6-23 与 :44-61，参数 lib/common.glsl:212-215（PARALLAX、PARALLAX_DEPTH 0.20、PARALLAX_QUALITY 64、PARALLAX_DISTANCE 32），消费在 lib/lighting/gbuffersLighting.glsl:164-165（#if defined PBR && defined PARALLAX && defined GBUFFERS_TERRAIN ... shadow *= parallaxShadow;）。

### Astra 现状证据

〔实测运行/工具〕Astra/shaders 全树搜索 parallax、Parallax、PARALLAX、POM = 8 命中，全部集中在两处：

- global/water/caustics.glsl:31-39：**焦散已经有单步视差**——:36 vec2 parallaxStep = viewVector.xy / max(viewDistance, 0.0001); 与 :39 worldPos.xz += height * parallaxStep;。也就是 Solas 那套的 1 步版本（不是 4 步）。
- global/water/surface.glsl:7（注释列出来源文件）、:15（注释 Reference wave parameters and Nyquist filter. Surface parallax displacement）、:327（注释：Surface parallax is cancelled in every tier: the wave normal is always ...）。

docs/实现与限制.md:49 明确记载了这一决定：“主世界主要水面取消波面视差位移，法线直接在几何XZ求解析梯度；表面按质量保留4/5/6层波纹。水下水平界面、焦散与光束使用各自既有波场，**其他维度水下仍有Solas四步视差，不能说整包已移除**。”

### 迁移落点与代价

**本条不构成迁移项**：Solas 的水面 4 步视差 Astra 在其他维度已经有（文档明确记载），主世界的取消是有记录的主动决定（global/water/surface.glsl:327 的注释写了 cancelled in every tier 及其理由）。按任务要求（已有等价实现则删除），这一条作为对照保留、不作为建议。

**真正的缺口在地形侧**：Astra 搜索 POM = 0 命中（上面 8 处命中里没有一处是地形视差遮蔽映射）。地形视差遮蔽映射需要一个“高度图”来源。Astra 的材质走 block.properties 的 id 分类（block.properties:23 的手工发光分类、:40,:43,:46 的 10004/10005/10006 植物名单），本会话**没有核实** Astra 是否已有从资源包读法线或高度通道的能力，属**未验证**。

若将来要做，落点应在 program/lit.fsh 的材质分派处（与 docs/实现与限制.md:108 记载的“用 faceData 第 26 位传砖面身份、不扩展原 4 位材质字段”同一处），代价是每像素 64 次高度图取数（Solas 默认 PARALLAX_QUALITY 64），**代价极高**，必须先用低档（Solas 最低 32）实测。

### 风险与前置核实

1. **依赖资源包提供高度图**：没有带高度或法线通道的资源包，POM 无从谈起。落地前必须先确认 Astra 现有材质链能读到哪个通道。
2. **与既有决定的关系**：global/water/surface.glsl:327 已明确取消水面视差，地形 POM 是另一回事，但用户可能把“视差”当成同一个东西，需要说清区别后再请示。
3. **未验证**：Astra 的材质通道，以及 Solas 的 POM 在实机上的观感收益。

### 许可注意

reference_shaderpacks/solas-shader/ 下**没有 LICENSE 文件**（本会话用 glob 列出根目录，只有 drm/drm.readme 与 shaders/；用 grep 在 lib/common.glsl 搜 license、copyright、permission = 0 命中）。**结论：许可状态不明，不能假定允许借用。** 只能按机制（视差的迭代思想）自写，不能复制代码。若确要借用，需要先向作者确认许可。

---

## 十一、跨条目：共同代价与一次性的前置核实清单

1. **Astra 完全没有 SSBO**〔实测运行/工具〕：std430、SSBO、ssbo、bufferObject 在 Astra/shaders 全树 0 命中。第一条与第三条若落地，需要新引入这个设施，并在 shaders.properties 追加声明（现为 iris.features.optional=CUSTOM_IMAGES COMPUTE_SHADERS）。两条都要先核实本机 Iris 接受 SSBO 声明与 layout(r32ui) uimage2D。
2. **附件余量紧张**：第四条与第八条需要新的全屏或半屏缓冲。shader_research/SUMMARY-batch5.md 第①节第2点记录“0-6、8-31 全部在用，32 槽只剩 colortex7 空闲”，但同一份汇总第⑧节也自我更正“全树编号的并集不能证明所有组合的同时占用”。**任何新附件都必须按具体启用组合重新核算，不能引用并集结论。**
3. **alpha 通道陷阱**：Astra/shaders/program/deferred.fsh:295-299 写明主场景 colortex0Format 是 R11F_G11F_B10F（RGB 格式），写 .a 被丢弃、读回恒 1.0。上面各条若要从参考包搬“把信息编码进 alpha”的写法，会静默失效。
4. **抗锯齿与抖动的互斥关系**：Astra 是“场景抖动、历史与输出不抖”（docs/实现与限制.md:79；program/taa_resolve.fsh:1-2）。任何新的屏幕空间效果（第二、七、八条）都要先确定它处在抖动之前还是之后。
5. **色调映射的位置**：第五批汇总记录 CAS 一类必须挂在色调映射之后的显示空间。第七、八条同理（CR 的色差就在 final.glsl，Mellow 的 SMAA 也在 final 附近）。
6. **许可登记**：可代码级借用的只有 arc-shader（MIT）与 mellow（MIT 加 Apache 2.0，需先确认文件归属）；photon-shader 是有条件再分发；complementary-reimagined 与 rethinking-voxels 都是 Complementary License Agreement（禁止修改与再分发代码）；solas-shader 无许可文件。移植任何代码后按项目规则登记 Astra/THIRD-PARTY.md。

### 关于 rethinking-voxels 的说明（任务点名，但无独立可报项）

任务要求从 rethinking-voxels 与 solas 各挑 1 到 2 条最有价值的缺失机制。经只读核查，rethinking-voxels 的可比较部分与既有调查重合，理由如下：

- 它的核心设施是体素距离场：program/shadowcomp.glsl:14-18（layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in; 与 image3D distanceFieldI、iimage3D occupancyVolume、iimage3D voxelCols）、:37-38（shared float fullDist[10][10][10]）、:50-99（八方向距离写入）、:91-98（双缓冲按 (frameCounter+1)%2 分上下半区写入）；SDF 加速的光线步进在 program/shadowcomp_sdf_loop.glsl。
- shader_research/SUMMARY-final.md 第四节已记录：“SDF+DDA 光追 | spring pathTracing.glsl:246-423 | CC-BY-NC-SA-4.0”，并且 docs/参考与取舍.md 的“候选进入条件”写明“体素压缩、Voxy远景……均未列入实施”。rethinking-voxels 的 License.txt:1 是 Complementary License Agreement 1.5，:9-13 同样把“改代码”和“再分发部分”排除在正常使用之外，**不允许代码级借鉴**。
- 我另外核对了它是否实现“影片颗粒”：本会话用 sed 打印 shaders/program/composite5.fsh 第 130 到 200 行，只有设置块，没有 filmGrain 变量；用 grep 搜 filmGrain 在该目录 0 命中。**因此不另立条目。**

**结论：rethinking-voxels 不贡献新的可实施条目。** 若用户将来对体素距离场本身有兴趣，应从 docs/参考与取舍.md 的“候选进入条件”那一条走，而不是从本报告走。


---

## 附：本报告用到的全部 grep 关键词与实际结果

全部在 Astra/shaders 全树执行。命中数 0 表示该关键词在 Astra 源码里一次都没有出现。

| 关键词 | 命中结果 |
|---|---|
| SSGI、ssgi、screenSpaceGI、ScreenSpaceGI | 0 |
| cascade、CASCADE、Cascaded、CSM | 0 |
| penumbra、Penumbra、PENUMBRA | 0 |
| pcss、PCSS | 0 |
| blocker、Blocker、BLOCKER、FindBlocker、avgBlocker | 3（block.properties、global/lighting/shadowmap.glsl、program/shadow.vsh；均为既有注释用词，非遮挡搜索） |
| vogel、Vogel、VOGEL、goldenAngle、GOLDEN_ANGLE | 0 |
| maximum_horizon、integrate_arc、GTAO_SLICES、GTAO | 0 |
| bentNormal、bent_normal | 9（全部在 lib/ao_resolve.glsl；是半分辨率 AO 的方向重建，非 GTAO 的切片 bent normal） |
| SMAA、smaa | 0 |
| checkerboard、Checkerboard、CHECKERBOARD | 0 |
| lightBins、LightBin、LIGHT_BIN、binning、binIndex、clusterLight、ClusterLight、tiledLight、TiledLight | 0 |
| std430、SSBO、ssbo、bufferObject | 0 |
| filmGrain、FILM_GRAIN、grainAmount、GRAIN_ | 0 |
| dof（独立词）、DOF_、dofOffsets、dofScale | 0 |
| CoC（独立词）、coc（独立词）、circleOfConfusion | 0 |
| motionBlur、MOTION_BLUR、motion_blur、MB_ | 0 |
| colorLut、ColorLut、LUT_FILE | 0 |
| season、SEASON、autumn、AUTUMN、summerHue | 0 |
| pixelatedShadow、PIXELATED | 0 |
| chromatic、CHROMA、aberration | 2（global/post/end_sky_tonemap.glsl:3、lib/twilight.glsl:78，均为色调曲线注释，非色差） |
| parallax、Parallax、PARALLAX、POM | 8（global/water/caustics.glsl:31-39 的单步焦散视差；global/water/surface.glsl:7、:15、:327 的注释） |
| BilateralGaussian、GaussianDepthBlur、bilateral、Bilateral | 0（该次 grep 返回空） |
| motionBlur、MOTION_BLUR、velocity、Velocity | 2（global/water/temporal.glsl、program/taa_resolve.fsh；后者是既有注释 No object velocity is inferred from camera motion） |

### 未做过的核实（缺口，明确列出）

1. 本会话没有实机运行任何一版 Astra，没有帧时或画面数据。凡涉及耗时与观感收益的数值一律标“未验证”。
2. 没有读取 Photon 的 GTAO_SLICES、GTAO_HORIZON_STEPS、CLOUDS_TEMPORAL_UPSCALING 实际档位数值。
3. 没有核实 Astra 是否已有从资源包读法线或高度通道的能力（这决定第十条的地形视差是否可做）。
4. 没有读取 mellow 的 read before you edit.txt，因此未能区分它两份许可各自的适用范围。
5. 没有核实 Astra 的 shadowtex0 与 shadowtex1 分工（第一条遮挡搜索读哪张需要确认）。
6. 没有核实本机 Iris 是否接受 SSBO 声明与 layout(r32ui) uimage2D（第三条的前置条件）。

