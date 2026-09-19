# 热门光影源码拆解：Steadfast 的成本控制与 Astra 可借鉴之处

日期：2026-09-16。重点追读阴影、水面、云、大气与后处理的调用路径、开关和数据流。以下结论来自指定版本源码，不是不同光影的帧率排名；源码读取次数也不能直接换算成增帧比例。

## 样本与来源

使用 Modrinth 官方项目 API 获取下载量与版本，并下载作者项目下发布的原始包解压。下载量为本次查询时的 Modrinth 项目累计值，未合并 CurseForge，也不是活跃用户数。Steadfast 作为重点学习对象，单独纳入，不把它列为下载量最高的包。

| 光影 | 本次版本 | Modrinth 下载量 | 阅读重点 |
| --- | --- | ---: | --- |
| [Complementary Reimagined](https://modrinth.com/shader/complementary-reimagined) | r5.9.3 | 66,084,013 | 按需阴影采样、反射分辨率、TAA 配套 |
| [BSL](https://modrinth.com/shader/bsl-shaders) | 10.1.5 | 28,994,396 | 紧凑缓存、分级阴影、多尺度 Bloom |
| [Photon](https://modrinth.com/shader/photon-shader) | v1.3b | 26,518,003 | 云的时域重建、覆盖率缓存、大气查表 |
| [MakeUp Ultra Fast](https://modrinth.com/shader/makeup-ultra-fast-shaders) | 9.5e | 12,644,781 | 少量采样、低成本云形、清楚的效果取舍 |
| [Steadfast](https://modrinth.com/shader/steadfast-shaders) | 0.8.0，beta | 27,275 | 从整个渲染流程控制开销 |

原包、解压源码与版本记录位于 [本次资料目录](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16>)；[sources.json](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/sources.json>) 保存具体发布地址。BSL 的可读 GLSL 来自官方发行包，并非把它误称为开放授权项目。这里给出的移植方向是技术思路，未把这些发行包的实现拷入 Astra。

## 一、Steadfast：应当学习的是整条成本链

### 1. 不需要的效果，连对应的渲染阶段都不执行

[程序开关与距离策略](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/steadfast-shaders/source/shaders/shaders.properties:28>) 将 composite 绑定 GODRAYS，将 deferred 绑定反射、折射或辅助吸收需求；光束中间图宽高各为 0.5。仅关闭效果公式，仍保留全屏读写，并不等于省掉这道阶段。

它还单独控制实体、方块实体的投影，关闭 DH 阴影。实体投影距离比例为 0.25，高档阴影距离 160，部分较低档降为 112、80。方块实体默认策略也较保守。

**适用于 Astra：** 梳理实际启用功能对应的必要输出，减少无用阶段和附件。实体、方块实体全部投影及 256 格接收范围、1.5 倍投影提交范围，是 Astra 额外付出的成本。必须把这类画质范围差异与算法效率分开；用户要求末地方块和实体投影，不能靠直接关掉它们来宣称优化成功。

### 2. 四次硬件 PCF，且只在需要直射光时采样

[阴影实现](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/steadfast-shaders/source/shaders/environment/lighting/shadowmap.glsl:28>) 开启硬件比较过滤，软阴影使用四次 sampler2DShadow 读取；每次可进行 2×2 深度比较和过滤。采样范围可能重叠，因此不能说成十六个独立采样点，更不能说性能必然提高四倍。

[背光面提前退出](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/steadfast-shaders/source/shaders/environment/lighting/diffuse.glsl:306>) 在普通表面直射贡献已接近零时退出；[投影范围外退出](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/steadfast-shaders/source/shaders/environment/lighting/shadowmap.glsl:215>) 在超出实时阴影范围时使用既有静态遮蔽结果。

**Astra 状态：** 背光面和范围外的跳过已存在。当前默认仍是软件模式：一个需要过滤的片元进行 16 组、每组两次深度读取，透明遮挡处还会增加材质读取。硬件模式已经实现，但它使用两个深度比较图和中心材质近似，与 Steadfast 的单个主要阴影采样器并不等价。参见 [Astra 阴影读取](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/Astra/shaders/global/lighting/shadowmap.glsl:36>)、[Astra 阴影合成](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/Astra/shaders/global/lighting/diffuse.glsl>)。

更有价值的进一步方向是：先确定是否完全可见，必要时才读取不透明深度和材质；硬件路径要处理好彩色玻璃、水面与不透明投影的交界。

### 3. 水面先求“大形状”，最后才求“细法线”

[四步视差](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/steadfast-shaders/source/shaders/environment/water/parallax.glsl:36>) 根据离表面的剩余高度缩小步长，最多四步，达到表面可提前结束。[近似高度与解析梯度](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/steadfast-shaders/source/shaders/environment/water/surface_noise.glsl:529>) 在近似高度计算中只保留前两层大涟漪，最终法线仍保留完整波层；[水面视差距离控制](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/steadfast-shaders/source/shaders/environment/lighting/translucent.glsl:80>) 又限制视差距离，并排除侧面。

**Astra 状态：** 已保留四步、近似高度两层涟漪、完整法线、48 格距离门槛，并在最近修改中补齐远处与非水面的跳过。不能把这些再记作待引入的新优化。此前工作说明中对 approximate 未生效的初步判断已更正，当前 [实际循环边界](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/Astra/shaders/global/water/surface.glsl:188>) 明确使用 approximate ? 2 : 4。

还需注意：只裁掉细波会改变高度均值。若改写近似策略，要维持高度、梯度、粗糙度的一致含义，不能单独删层导致水面漂移。

### 4. 解析求导减少重复纹理读取，屏幕足迹处理远处细节

[值噪声解析梯度](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/steadfast-shaders/source/shaders/lib/valueNoiseDerivatives.glsl:109>) 用一次 textureGather 得到四个格点，再计算插值函数的导数。相比为了求两个方向斜率反复评估完整高度场，这直接消除了重复工作。它不是“所有纹理读取变成一次”，每个波层仍有自身读取和运算。

水面还根据屏幕空间足迹过滤无法分辨的频率，防止远处细波变成闪烁与高亮条纹。

**Astra 状态：** 解析梯度和足迹过滤已继承。最近还加入完全滤除波层时跳过读取、保留未解析坡度能量的处理。Steadfast 另有基于几何求屏幕导数的方法；Astra 已在分支前取得 quad 导数，没必要为了模仿而增加射线与平面计算。

### 5. 反射采用总预算内的加速搜索和细化

[SSR 搜索与细化](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/steadfast-shaders/source/shaders/lib/raytrace.glsl:39>) 总循环上限 24 次，步长按 2 倍扩张；命中后缩小步长重新走上一段，最多四轮细化。这些细化共用 24 次预算，不是 24 次外面再乘四轮。命中厚度随步长变化；循环用尽时可返回保存的命中点。不过其出屏分支直接返回失败，并非所有退出都保留旧命中。

**Astra 状态：** 当前是最多 24 次搜索加 6 次二分细化。分离后的成本容易判断，但厚度、深度不连续和界面侧判定决定了草丛是否被拉成长条。对我们来说，保留草叶轮廓和水上／水下位置关系比机械追求更少步数重要。

### 6. 全屏共享的量提前计算，缓存只使用需要的精度

[共享照明参数](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/steadfast-shaders/source/shaders/shaders.properties:1458>) 将直射、环境光、光源方向等交给自定义 uniform。每个片元读取已经组合好的光照颜色，而不是重复展开与位置无关的大气和天气计算。

[主场景紧凑 HDR](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/steadfast-shaders/source/shaders/program/post/postprocessing.fsh:20>) 主场景使用 R11F_G11F_B10F；[场景副本与单通道数据](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/steadfast-shaders/source/shaders/program/post/copy_and_fog.fsh:19>) 副本同样是紧凑 HDR，独立标量用 R8。透明混合需要片元 alpha，不代表最终场景缓存也必须保存 alpha。

**Astra 状态：** 主色、副本和普通 Bloom 已是紧凑 HDR。可继续考虑把共享晨昏、直射、环境颜色搬到 uniform 或少量顶点的 flat 输出；不要把这类优化夸成确定的最大瓶颈。末地天体位置缓存已有 294×1，每帧求一次；这是同一思路的正确使用。

### 7. 云和光束选择了成本较低的模型

[薄云平面模型](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/steadfast-shaders/source/shaders/environment/clouds/cirrus.glsl>) 用射线和平面求交，多层二维噪声构造薄云；薄层混合还忽略小的 alpha 乘积项。它没有为这些薄云使用完整体积步进。

[半尺寸光束中间数据](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/steadfast-shaders/source/shaders/program/post/noisy_godrays.fsh>) 与 [屏幕空间光束合成](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/steadfast-shaders/source/shaders/program/post/postprocessing.fsh:35>) 将屏幕空间遮蔽与少量后处理采样结合，后者是一次初始读取加八次循环读取。

这些选择有视觉边界：薄云不等于厚实方块云，屏幕空间光束不等于带空间遮挡的水下光束。Astra 不能把用户要求的立体云和水下光束全部替换掉，再称作同效果提速。

### 8. 顶点到片元的数据也经过设计

[flat perFace 数据](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/steadfast-shaders/source/shaders/program/world/lit.vsh:80>) 使用单个 flat uint 传递每个面的信息；[材质与法线解码](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/steadfast-shaders/source/shaders/lib/encoding/face.glsl:154>) 对法线和材质打包。Astra 的 faceData 已继承相同方向。

Steadfast 的轻量还来自较简洁的前向照明与后处理组合。Astra 增加了末地天体、水下光束、雨天反射等内容，不能仅凭继承基础代码就期待相同帧率；每项新增效果需要明确自己占用哪些阶段和数据。

## 二、另外四款各自最值得借鉴的部分

### Complementary r5.9.3：把额外成本留给需要它的像素

- [按需读取透明阴影](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/complementary-reimagined/source/shaders/lib/lighting/shadowSampling.glsl:11>) 先读全遮挡图，出现遮挡才读不透明图，两者有差异时才取彩色材质。其普通开阔受光区域无需每次把三张图都读完。
- 同文件把 TAA 阴影路径和固定采样路径分开，实体／手持等路径调整样本数量；帧间变化的采样分布与 TAA 成套使用。
- [反射尺寸](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/complementary-reimagined/source/shaders/shaders.properties:115>) 和 [REFLECTION_RES 默认值](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/complementary-reimagined/source/shaders/lib/common.glsl:240>) 将对应反射缓存设为宽高各 0.5，可把该缓存阶段的片元数量降至四分之一。[反射的多条路径](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/complementary-reimagined/source/shaders/lib/materials/materialMethods/reflections.glsl:35>) 同时存在水面片元内的追踪，不能说整个水面开销都变成四分之一。

**对 Astra 的意义：** 优先学习分级读取与功能分支。Astra 目前没有完整 TAA 支撑，不宜直接套用逐帧变化的阴影样本，否则会重现移动时边缘发抖。反射降尺寸属于重建方案，需同时处理材质和深度边界。

### BSL 10.1.5：缓存复用和多尺度效果组织得很清楚

- [附件格式与用途](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/bsl-shaders/source/shaders/program/final.glsl:23>) 主场景使用紧凑浮点 HDR，辅助图按用途分配格式；一些附件在不同阶段承担不同工作，减少常驻独立数据。
- [彩色阴影按需采样](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/bsl-shaders/source/shaders/lib/lighting/shadows.glsl:90>) 在主体可见性小于阈值时才补充彩色阴影读取。开启过滤时是九个主样本，仍有自身成本，不应因为名气大就视为比四点路径更省。
- [Bloom 图集构造](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/bsl-shaders/source/shaders/program/composite4.glsl:31>) 将七个尺度打包到一张图的不同区域，仅在相应区域进行模糊；[Bloom 解码与合成](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/bsl-shaders/source/shaders/program/composite5.glsl:101>) 重建不同半径的光晕。中间值先以四次根编码，再以四次方还原；因此 RGB8 在这里不是直接装未编码的 HDR。

**对 Astra 的意义：** 学习附件生命周期和“精度与编码成对设计”。Astra 曾出现泛白、截断，不能仅看到 BSL 使用 RGB8 就照抄格式。现有四分之一尺寸 Bloom 和 mip 合成已经较简洁；BSL 的每个有效图块仍有 6×6 读取，整套替换不一定更省。

### Photon v1.3b：把重复计算转移到小图、查找表和历史帧

- [云时域倍率](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/photon-shader/source/shaders/settings.glsl:194>) 默认 CLOUDS_TEMPORAL_UPSCALING=4；[云缓冲尺寸](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/photon-shader/source/shaders/shaders.properties:260>) 对应四分之一宽高，云主阶段约为全尺寸的十六分之一片元。[轮换采样位置与云深度](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/photon-shader/source/shaders/program/d1_clouds.fsh:155>) 逐帧轮换位置，同时输出云的视距离。
- [历史重投影与失效处理](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/photon-shader/source/shaders/program/d2_clouds_upscaling.fsh:301>) 不只把旧帧混回来：它处理出屏、遮挡、手部、时间跳变、无效数值，并做邻域限制。前面的重投影函数还考虑云层风速。这些是低采样仍能稳定显示的必要成本。
- [预计算云覆盖率](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/photon-shader/source/shaders/program/p0_clouds_prep.fsh>)、[覆盖率的缓存坐标](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/photon-shader/source/shaders/include/sky/clouds/coverage_map.glsl>) 缓存共享二维覆盖率；[大气和噪声纹理](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/photon-shader/source/shaders/shaders.properties:346>) 使用 32×64×32 的 RGB16F 大气散射查找表，以及 64³ 的 R8 云噪声纹理。

**对 Astra 的意义：** 天空、云和雾可以复用同一大气结果；昂贵内容可以独立于地表处理。但 Photon 多了历史缓存、全尺寸重建和拒绝失效历史的成本，“十六分之一片元”绝不等于整包快十六倍。末地旋转天体与吸积盘的运动也不等于相机运动，若沿用云的旧帧重投影会有拖影风险。

### MakeUp 9.5e：便宜的模型，加上明确的质量选项

- [一或四次阴影采样](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/makeup-ultra-fast-shaders/source/shaders/lib/shadow_frag.glsl:7>) 提供一次硬件采样的像素阴影和四次采样的柔化阴影，彩色分支也按实际遮挡决定是否取颜色。
- [二维密度驱动的云层](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/makeup-ultra-fast-shaders/source/shaders/lib/volumetric_clouds.glsl:5>) 用二维密度推导云上下边界与局部厚度，简化着色，不为每个主步再嵌套完整光照步进。
- [反射质量与步数](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/makeup-ultra-fast-shaders/source/shaders/lib/config.glsl:30>) 将反射关闭、翻转画面近似、SSR 明确区分；SSR 上限为 10 次。[SSR 实现](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/makeup-ultra-fast-shaders/source/shaders/lib/water.glsl:9>) 先指数扩张，命中后缩步。

**必须看到取舍：** 翻转画面反射不适合修复 Astra 已经出现的草丛反射错位；10 步不能自动满足薄物体轮廓要求。该 SSR 出屏时先标记、仍继续循环，不能把它称为出屏立即退出的范例。源码关于 sqrt 替代幂函数“更快”的注释也只是作者判断，实际指令效率依赖编译器和 GPU。

## 三、Astra 的实际差距与落地方向

| 优先级 | 当前情况 | 借鉴后的方向 | 视觉与实现边界 |
| --- | --- | --- | --- |
| 高 | 默认软件阴影，16 组双深度采样 | 借鉴 Complementary 的分级读取；完善已有硬件 PCF 分支 | 彩色玻璃与水的材质边界必须正确；不能混淆过滤深度与过滤可见性 |
| 高 | 主世界在 skybasic 中求天空与云，随后可被地形覆盖 | 把昂贵天空部分组织到已知地形深度之后；沿用末地已使用的遮挡跳过思路 | 需要安排方形日月、云遮挡、透明物背景和反射副本的合成顺序 |
| 高 | 接收阴影范围较大，投影提交范围再乘 1.5，方块实体开启 | 结合近景清晰、远景环境光的风格，细分投影距离与对象成本 | 缩小距离是可见范围取舍，不能称为完全等价；保留末地方块与实体阴影 |
| 中 | 天空、雾、反射在各路径计算相关配色 | 优先共享每帧参数；较重的大气部分再考虑小型查找表 | 当前默认是较便宜的渐变天空；新增查表阶段未必划算 |
| 中 | 末地大部分渲染已有遮挡门槛、天体缓存及 0.75 尺寸天空图 | 先沿现有结构减少重复工作；时域重建作为独立的后续架构选项 | 保留细星、吸积盘动态、真实交会与轨道周期 |
| 中 | 多道水下与雨天合成，各自读取场景数据 | 按输入输出依赖合并可兼容的阶段，避免反复读写全屏颜色 | 不能跨越透明物绘制顺序合并，不能重复或漏掉介质衰减 |
| 已有 | 解析波浪梯度、近似高度、距离视差、屏幕足迹过滤 | 保留已有实现，集中处理真正额外的工作 | 不再重复宣称引入这些优化 |
| 已有 | 主色／副本紧凑 HDR、四分之一尺寸 Bloom、末地每帧天体缓存 | 维护格式与数据语义的一致性 | 不能为了省格式精度重新引入高亮截断和位置抖动 |

主世界天空调用可追到 [skybasic 入口](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/Astra/shaders/program/sky.fsh>) → [天空与云合成](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/Astra/shaders/program/scene.glsl:32>)。末地已有 [先判遮挡再求天空](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/Astra/shaders/program/end_sky_buffer.fsh>)，所以“先有可见性再做昂贵着色”在 Astra 内部已经有可参照的结构。

当前阴影设置见 [默认过滤模式](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/Astra/shaders/lib/settings.glsl:57>) 与 [投影范围倍率](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/Astra/shaders/lib/settings.glsl:214>)；预算差异要分别归到“阴影图绘制”和“表面阴影采样”，两者不是同一个瓶颈。

这次最有价值的原则是：先确认某项结果是否需要，再决定计算分辨率、频率与精度，最后优化公式。Steadfast 的节制、Complementary 的条件采样、Photon 的复用方式，比继续堆叠局部调参更值得 Astra 系统吸收。

## 四、本轮在 Astra 中落地的修改

### 阴影：保留采样覆盖，减少读取指令

默认软件路径保留四组双线性覆盖的 16 个深度比较点。每组通过 `textureGather` 同时读取四个深度值，分别比较后再加权；完全受光的组跳过不透明深度图，有透明遮挡差异的角点才读取材质。玻璃颜色和水面高度仍按离散角点解析，没有改成中心材质近似。

原来每次表面阴影固定执行 32 次标量深度读取，现在是 4 次全遮挡图 gather，加上最多 4 次不透明图 gather。一次 gather 仍访问四个纹素，不能把指令数变化解释成等比例带宽或帧率收益。已有硬件模式也加入第二张深度图的按需读取，默认选项未切换。

末地及体积光使用的单组软件可见性也改为一次 gather 后分别比较、加权；末地背光面与阴影图覆盖范围外的接收点直接跳过阴影查询。

### 主世界天空：在地形之后计算可见区域

方块云模式和关闭云模式下，`skybasic` 只输出黑色，`skytextured` 保留带月相和云遮挡的日月辐射。`deferred` 仅对没有不透明地形的像素计算原来的完整天空与云，再加入日月，并把完整结果写入反射／折射使用的场景副本。计算尺寸、云步数及云形状参数没有降低。

原版云模式保留原绘制顺序，避免把几何云错误当成日月叠加。云密度查询使用明确的纹理层级，避免搬到深度分支后依赖未定义的隐式导数。

### 共享参数与零贡献分支

晨昏权重移到 `shaders.properties` 每帧计算，天空、云、雾和地表读取同一个 uniform。原有太阳高度范围与雨量衰减保持一致；水下也读取完整权重，不使用会在水下清零的 `sunrise` 替代。晨昏权重为零时，相关方向散射、辉光和高亮压缩直接返回。

雨天光束在日光贡献为零时直接返回；云已完全遮光或采样点不在阴影覆盖范围内时，跳过没有贡献的阴影读取。

### 末地：保留轨道和细节，跳过已被遮挡的工作

- 完全不透星光的黑洞／天体像素，不再计算最终会乘零的全尺寸星场。
- 天体表面已经被自身完全遮挡时，不再遍历其他 73 个天体及环带求光源遮挡；发现其他实体完全遮挡后也跳过环带遮挡查询。
- 环带高频颗粒已经被屏幕足迹滤除时，不再计算对应噪声，仍保留原平均值。
- 天空射线足迹在地形可见性分支之前求出，避免轮廓处的分支影响吸积盘细节过滤。

以上 shader 修改均已随批次同步到游戏实例的 Astra 目录。本轮没有修改后的游戏帧率数据；这里记录的是具体计算路径的减少，不预报帧数或百分比。
