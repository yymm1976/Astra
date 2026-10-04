# 视频参考光影：源码性能研究与 Astra 采用方案

日期：2026-10-02。目标：下载用户提供的视频与简介涉及的所有光影，分析各自降低渲染开销的方式，优先改善 Astra 主世界，并学习 Mellow 的配置组织。

原材料：[Bilibili 视频与用户提供的字幕](https://www.bilibili.com/video/BV1iZau6TEZT/)。字幕中的 FULTON、BLEASE、TROCAPIC13V6light、SUGERS、SDV 分别按 Photon、Bliss、Chocapic13 V6 Lite、Sildur’s Vibrant、Super Duper Vanilla 对应；简介中的 der 经用户确认是 Derivative，ITT 对应 IterationT。

## 下载范围

压缩包与解压源码保存在 `_analysis/video-2026-10-01/`。所有 14 个研究对象已下载，Sildur’s 另保留 Lite 与 Extreme 两版；Chocapic13 下载官方 V6 合集后单独解压其中的 Lite。完整文件入口见 [下载目录](../_analysis/video-2026-10-01/README.md)，逐文件来源见 [sources.json](../_analysis/video-2026-10-01/sources.json)。

| 光影 | 本次版本 | 来源 |
|---|---|---|
| Mellow | 3.4.1a | [Modrinth 作者发布页](https://modrinth.com/shader/mellow) |
| Photon | v1.3b | [Modrinth 作者发布页](https://modrinth.com/shader/photon-shader) |
| BSL | 10.1.8 | [Modrinth 作者发布页](https://modrinth.com/shader/bsl-shaders) |
| Bliss | 2.1.2 | [Modrinth 作者发布页](https://modrinth.com/shader/bliss-shader) |
| Complementary Reimagined | r5.9.3 | [Modrinth 作者发布页](https://modrinth.com/shader/complementary-reimagined) |
| Complementary Unbound | r5.9.3 | [Modrinth 作者发布页](https://modrinth.com/shader/complementary-unbound) |
| MakeUp UltraFast | 9.5f | [Modrinth 作者发布页](https://modrinth.com/shader/makeup-ultra-fast-shaders) |
| Chocapic13 V6 Lite | V6 Lite | [CurseForge 官方 V6 合集文件](https://www.curseforge.com/minecraft/shaders/chocapic13-shaders/files/2906904) |
| Sildur’s Vibrant | 2.02 Lite、Extreme | [Modrinth 作者发布页](https://modrinth.com/shader/sildurs-vibrant-shaders) |
| Super Duper Vanilla | 1.3.8 | [Modrinth 作者发布页](https://modrinth.com/shader/super-duper-vanilla) |
| Derivative | [main] 25.1.0 | [维护团队发布页](https://www.curseforge.com/minecraft/shaders/derivative-main/files/8529690) |
| Solas | 3.7b | [Modrinth 作者发布页](https://modrinth.com/shader/solas-shader) |
| Kappa | 5.3 | [Modrinth 作者发布页](https://modrinth.com/shader/kappa-shader) |
| IterationT | 3.2.0 | [公开 CurseForge 镜像](https://www.curseforge.com/minecraft/shaders/iterationt-3-2-0) |

Derivative 本次使用 DureXXX / Skeeder461 / M1zore 团队维护的 main 分支；原 HaringPro 分发入口当时重定向至不可访问的 MGC 页面，因此本次结论具体对应 main 25.1.0。IterationT 压缩包来自公开镜像，原作者发布身份未确认。

以下结论来自实际下载的源码与设置文件。视频中 275–600 FPS 的数字缺少统一设备、场景与设置条件，本报告不据此排名，也不把减少采样的比例等同于整帧 FPS 提升。

## 逐包分析

下面各节的文件位置均相对于该研究对象的 `shaders/`；名称与实际解压根目录在下载目录中对应。

### Mellow 3.4.1a

- `global/lighting/shadows.glsl:1–29`：彩色阴影先读不透明可见度，完全遮挡时提前返回；简单模糊只用四个偏移。`pcf` 则有固定 8 点预算。区别在于阴影模式的工作量，不能把最高质量模式的开销当成默认简单模式。
- `global/atmosphere/clouds.glsl:5–16`：平面云先查密度，空云直接返回，后续光照只发生在命中区域；体积云路径还有按视角调整步数、透射趋零时退出的策略。
- `shaders.properties:82–143`：小尺寸缓冲和效果阶段开关分别控制资源与执行，例如 `colortex5` 宽高各 1/4，Bloom、SMAA、DOF 等阶段按设置启停。关闭效果与停用整个绘制阶段是两种不同程度的节省。
- `shaders.properties:143–195`、`lib/colors.glsl`：FAST / FANCY / FABULOUS 调整效果，颜色方案独立；天空顶部、地平线、日光、环境光、末地、方块光、后期色彩分别设子页，RGB 三列排列。日光及天空又按白天、日出、日落、夜晚分组。

适合 Astra 的部分已采用：小预算阴影档位、低分辨率效果档位，以及独立颜色方案 / 分时天空 / 光源与显示调色分组。新增颜色是对现有 Astra 色彩的编译期倍率；四种方案由 Astra 自行配置。Astra 的云此前已有空区域筛除与首次命中后才求光照，本次继续使用这一结构。

### Photon v1.3b

- `shaders.properties:152–223`：阴影、彩色光与各维度阶段分别启停；主世界 shadow 由 `SHADOW` 控制，下界的 shadow 还服务彩色光，不能把所有维度按同一个开关处理。
- `shaders.properties:252–274`：天空与光照信息使用 192×108 缓存；雾 / AO 有半尺寸缓冲；云允许原生、1/2、1/3、1/4 尺寸。云重建与场景 TAA 各有自己的设置与资源。
- `include/buffers.glsl` 描述不同数据的格式与用途：场景颜色、遮蔽、透射、散射、云颜色与云位置数据分开，适合按信息需求分配带宽。
- `program/gbuffers_all_solid.fsh:420` 附近包含雨滴溅落粒子颜色判别；Astra 上一轮雨粒子修复的参考机制在这份新下载源码中也存在。

采用到 Astra：云质量现在控制屏幕云及其独立颜色 / 元数据网格，原有低尺寸天空环境缓存继续复用。场景 TAA 的开关不决定云历史是否存在。雨粒子仍沿用上一轮不透明 / 透明入口接线与颜色判别，相关限制见 [10-01 记录](2026-10-01-performance-review.md)。

### BSL 10.1.8

- `shaders.properties:4–8`：MINIMUM 去掉 AO、光束、阴影、彩色阴影、阴影过滤、TAA；LOW 只恢复较小阴影图；随后档位逐步加入效果。配置的意义是选择实际执行的功能组合。
- `lib/lighting/shadows.glsl:214`：过滤开关在 `SampleFilteredShadow` 与 `SampleBasicShadow` 间选择；过滤分支使用更多采样，直接采样分支便宜。
- 阴影分辨率与距离同时参与成本控制；分辨率决定图像像素，距离决定收集哪些世界几何，两者不能互相替代。

采用到 Astra：软件 / 硬件比较模式与采样预算分开配置；流畅档只用一个双线性区域，默认均衡档两区域，高档四区域。原有阴影分辨率、距离与实体距离设置保留，彩色玻璃与水依然逐角点配对。

### Bliss 2.1.2

- `lib/res_params.glsl` 的 `VL_RENDER_RESOLUTION` 与 `BLOOM_QUALITY` 控制有效计算尺寸，VL 可选 0.25 / 0.5 / 1.0；`dimensions/composite1.fsh` 等生产和读取端按同一缩放映射坐标。这是降分辨率计算与重建的组合，不能只改生产端。
- `dimensions/all_translucent.fsh:252–300`：SSR 预算从 15 到 `SSR_STEPS` 随 Fresnel 插值，把更多查询给更明显的反射。
- 全场景 TAA 放大依赖场景历史、渲染比例和重建约定，涉及几何、屏幕查询和最终显示的共同坐标。

采用到 Astra：为体积雾增加有效网格与步数档位，生产、保边读取都以纹理实际尺寸为准。Fresnel 降低 SSR 步数暂未采用：Astra 当前水面与积水的 96 步 / 6 次细化还承担命中连续性，随意改预算会改变命中结果；本轮优先减少反射外的重复计算。

### Complementary Reimagined r5.9.3

- `lib/atmospherics/clouds/reimaginedClouds.glsl:68–140`：先处理距离与几何端点，再判定噪声命中，只有命中才算云光照，找到对应云层后退出。
- `shaders.properties` 的预设把阴影、实体影、材质细节、反射、云、彩色光等分别分档，允许多个功能控制组合成一个画质预设。
- 同一套整体框架允许材质和大气效果复用缓存，颜色控制与效果预算分别有入口。

采用到 Astra：现有平面云保留粗密度判定与首次命中结构，新增 4–32 / 6–64 / 8–96 的距离自适应步数上限。平面云质量和云模式分开，降低采样不要求彻底关闭云。

### Complementary Unbound r5.9.3

- 与 Reimagined 共用大量调度和材质框架；具体云路径选择不同，不能当成完全独立的两套性能架构。
- `lib/atmospherics/clouds/unboundClouds.glsl:94–194`：先裁剪射线与云层平面的交段，使用按质量配置的步长；超出云层 / 距离退出，积累 alpha 超过 0.9 后直接结束。
- `shaders.properties:120–121`：反射缓冲使用独立 `REFLECTION_RES`；效果计算网格不必等于场景网格。

采用到 Astra：选用独立效果尺寸 / 预算的配置方式。Astra 平面云是首次命中模型，原有云交段裁剪已具备，不改成 Unbound 的多次体积累计；原有云 alpha、代表位置和历史重建约定保持一致。

### MakeUp UltraFast 9.5f

- `lib/shadow_frag.glsl:8–37`：简单阴影单次查询，柔和阴影四次；彩色阴影只在深度比较显示存在透明遮挡时读取颜色。开销受模式影响，而不是固定每个像素都读完整数据。
- `lib/ao.glsl` 使用 `AOSTEPS` 控制预算，并将视深度、比例与步长因子移到循环之外。
- `lib/bloom.glsl` 使用 `BLOOM_SAMPLES` 个四方向采样及显式 LOD，避免为了较宽的模糊在基础层做大量密集采样。
- `shaders.properties:4–11,44–47`：多种效果组合可选，阴影阶段按 `SHADOW_CASTING` 停用；其它效果的宏开关应与整阶段停用区别看待。

采用到 Astra：小型稳定阴影核和独立质量控制，沿用现有循环外公共项与 Bloom 的降尺寸 / LOD 结构。Astra 默认 FXAA 下使用固定阴影采样区域，避免依靠转动随机核与时域恢复才能稳定的方案。

### Chocapic13 V6 Lite

- 本次实际研究官方合集里的 `Chocapic13 V6 Lite.zip`，并非用 V9 代替视频指定的 V6。
- `gbuffers_terrain.fsh:78–99`：先判定有效阴影覆盖，再做固定四次硬件阴影查询；地形照明路径较短，没有现代多层 GI 的额外计算结构。
- `final.fsh:304–331`：反射射线越出屏幕或有效深度范围后退出；精细步骤限制在交点附近。
- 源码保留 RGB11F 色彩路径，体现基础照明与有限效果组合，而不是仅把阴影图设小。

采用到 Astra：固定、低预算、可独立运行的阴影模式，以及覆盖范围之外的静态阴影逻辑。屏幕边界退出与有限细化在 Astra 的反射路径中已经具备，继续保留。

### Sildur’s Vibrant 2.02 Lite / Extreme

- 另下载 Lite 后，可以具体看到低配默认设置：Lite `shaders.settings:38` 阴影图 512；部分 Bloom / 体积光宏默认关闭，TAA 仍默认打开。Lite 的性能不能用 Extreme 默认设置代替。
- 两版 `shaders.properties:9–13`：阴影阶段条件是 `Shadows || Volumetric_Lighting`，即使表面阴影关闭，体积光仍可能需要阴影图。反射、TAA 与后期阶段也有独立启停条件。
- 多个非必要几何程序按游戏版本条件关闭；这与设置一个片元内分支有不同的收益边界。

采用到 Astra：保持各阶段的实际依赖，低成本画质仍允许单独选云 / 雾质量；新增平面云关闭时原始云目标也缩至 1×1。Astra 的体积雾在关闭阴影时保留云影近似，不额外为它强制开启 shadow，这由本包自身光照模型决定。

### Super Duper Vanilla 1.3.8

- `shaders.properties:2–6`：POTATO 关闭体积光、阴影、SSAO、SSR 等功能；LOW / HIGH / ULTRA 再增加功能与射线步数，采样预算明确可见。
- `lib/rayTracing/rayTracer.glsl:1–54`：主步进与二分细化分别设置上限；出屏、手持物深度、无效交点等情况立即结束，只有发生交点才执行细化。
- 原版风格下较少的附加大气层与功能组合，也是其低档计算量的重要组成。

采用到 Astra：保留有限主步进 / 有限细化与无效路径退出，新增质量档位给已有大气效果。此包未发现与 Mellow 类似的一整组后期程序启停属性，不能把宏裁剪直接描述成全面停用绘制阶段。

### Derivative [main] 25.1.0

- `shaders.properties:57–60`：光源坐标的归一化因子与世界方向分量在 CPU 自定义表达式中计算，避免在着色器中重复做同一个帧不变量运算。
- `shaders.properties:154–190`：GI / SSAO / 反射过滤按维度与游戏版本路由到实际阶段；下界与主世界条件不同。
- `lib/Atmosphere/NUBIS.glsl:193–246`：云步数按视线仰角和质量调整；空密度跳过昂贵光照，透射低于 0.0001 结束。

采用到 Astra：将实际 shadow 光源的世界坐标变换、归一化、太阳 / 月亮判定、地平线衰减和雨量增益搬到 CPU。`astra_direct_light()` 只混合已调整的日月光与 `astraDirectLightGate`。使用 Astra 原有矩阵与光源切换约定，而不是把参考分支的光照坐标定义直接替换进来。

### Solas 3.7b

- `shaders.properties:14–17`：LOW 关闭体素雾、体积云、Bloom、生成材质等；MEDIUM 起用较少的 `VL_SAMPLES`；高档同时增加阴影距离、体素体积尺寸和体积光预算。
- `lib/atmosphere/volumetrics.glsl:79,172–200`：完全不可见时提前返回；步进预算有限，超过目标几何或最大距离后结束。
- 体素灯光与复杂体积层可提供额外效果，但其网格、传播与读写本身有持续成本，不能把复杂度扩大理解为低配优化。

采用到 Astra：体积雾质量分档及原有零密度 / 不参与介质退出；主世界继续使用有限的高度雾模型。现有下界体素光保持原有限网格，本轮不扩大网格，也不将下界彩光链引入主世界。

### Kappa 5.3

- `lib/internal.glsl:50`：间接光线性比例为 `sqrt(1 / indirectResReduction)`；参数表示面积缩减，不能把 reduction=2 错写成宽高都减半。
- `shaders.properties:183–208`：天空相关缓存有独立尺寸；SSPT 与 SVGF 过滤分别启停，多轮过滤只有相关功能开启才运行。
- 高成本光照通过降低采样、缓存和时域 / 空间恢复换取质量；历史数据与恢复阶段自身也占资源。

采用到 Astra：独立效果资源尺寸、关闭效果时停用生产并缩小无用资源的思路。Astra 已有云与水下光束的独立历史，沿用它们的边界条件；本轮不新增 SSPT / SVGF 链，避免为可选高级照明增加一组常驻绘制阶段。

### IterationT 3.2.0

- `Lib/IndividualFounctions/NUBIS.glsl:129–171`：按方向 / 质量确定云步数；空密度跳过光照，透射接近零时终止。
- `shaders.properties:61–62`：云影两个阶段由 `CLOUD_SHADOW` 控制；GI 质量与计算尺寸在预设中单独分档。
- 云、GI、反射、体积雾各自有预算；丰富画面源于多个效果组合，而不是一个能够同时省掉所有查询的替代项。

采用到 Astra：显式效果预算及空区域退出的思路，落实为云 / 体积雾质量配置。此镜像的来源不等于作者授权分发记录，本轮仅研究计算组织，新增代码与颜色表均由 Astra 编写。

## Astra 本轮实际改动

| 已采用手段 | 实际实现 | 生效范围与代价 |
|---|---|---|
| 小型阴影核分档 | `global/lighting/diffuse.glsl::surface_shadow_light`，4 / 8 / 16 个配对角点 | 主世界表面；默认均衡从四个区域减为两个；低 / 均衡更硬或略有方向性，高档保留原四区域 |
| 帧不变量交给 CPU | `shaders.properties` 的光源坐标、归一化、光源交接与地平线表达式；`lib/uniforms.glsl` 对应标量 | 主世界直射光，省去每次着色调用中的矩阵变换、归一化与三段平滑衰减 |
| 云独立分辨率 / 步数 | `CLOUD_QUALITY`，原始 / 历史 / 元数据目标同档配置；`clouds_planar.glsl` 4–32 / 6–64 / 8–96 | 平面云；低档减少薄云细节，高档增加像素与步数；历史仍独立于 TAA |
| 体积雾独立分辨率 / 步数 | `VOLUME_FOG_QUALITY`，1/4×12 / 1/2×24 / 1/2×48；接口前缀 4 / 8 / 12 | 仅可选主世界体积雾；原有保边重建读取真实纹理尺寸；低档可能减少光束细节 |
| 关闭平面云时缩小资源 | 非平面云的 `colortex12` 改为 1×1 | 云关闭 / 原版云时；原有云历史目标和生产阶段也按模式停用 |
| 画质与颜色分开 | 四档质量预设不再包含颜色方案、RGB 及后期调色设置 | 切换画质保留配色；原光照强度与效果开关仍由画质预设赋值 |
| 分层 RGB 与颜色方案 | `lib/color_controls.glsl`、天空 / 云 / 灯光 / 维度 / grading 入口及中英文菜单 | 19 组场景色与 3 组显示色共 66 通道；原生天空与中性分段调色省去新计算；不新增图像目标 |

设置说明见 [颜色与性能设置](2026-10-02-colour-and-quality-options.md)。本轮实现涉及的参考机制不是新的素材或整段算法移植，既有模块的许可与来源保留在 [THIRD-PARTY.md](../Astra/THIRD-PARTY.md)。

## 为什么优先这些主世界改动

主世界同时涉及世界与实体阴影、天空、云、雨湿地面、空气介质和水面反射。阴影过滤发生在大量地形像素上，因此默认档减少采样与光源衰减的重复计算比只调整某个远处特效更普遍。云和体积雾的像素数量、射线长度与每步查询叠加，独立质量控制能直接限制各自的计算量。

Mellow 的配置优势在于分别描述「希望画面是什么颜色」与「愿意为哪些效果付出计算量」。Astra 本轮开放了相同层次的控制，但保持自身天空模型、云积分、光照与末地结构；配色方案依据 Astra 现有值编写。

此前已有的 CPU 调色、雨雾常量外提、积水早退出、云首次命中、水下光束位置复用、TAA 有效历史条件，以及下界反射滤波整理继续保留，见 [上一轮性能记录](2026-10-01-performance-review.md)。

当前结果是可查阅的下载源码、逐包机制分析与实际代码修改。游戏加载、画面细节及帧时收益尚未确认；特别是两区域阴影的边缘方向性与低云档的薄云细节属于明确的画质取舍。
