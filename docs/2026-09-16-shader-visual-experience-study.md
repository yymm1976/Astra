# 五款光影的视觉体验源码调研与 Astra 适配建议

日期：2026-09-16。

本轮继续阅读已取得的官方发行源码：Steadfast 0.8.0 beta、Complementary Reimagined r5.9.3、BSL 10.1.5、Photon v1.3b、MakeUp Ultra Fast 9.5e。版本来源见 [此前的性能调研](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/docs/2026-09-16-popular-shader-performance-study.md>)。

下文的“源码做法”是所读版本实际存在的逻辑；“Astra 建议”是结合当前代码与用户反馈作出的设计判断。部分效果受宏和材质选项控制，存在实现不代表每个预设都开启。成本是新增计算方式的相对判断，没有不同光影同场景的 GPU 时间数据。本轮产物为调研文档。

## 1. 最值得先做的事

Astra 已经具备晨昏统一权重、暖直射与环境补光、云体高度着色、天空反射、水深吸收、末地石高光和 Bloom。继续单纯增加亮度、饱和度、雾量，会把已有问题重新放大。

最有价值的补强是：

1. **夜晚用适量失色、冷暖分离和可读的背光面表达夜色。** 减少对远景压黑的依赖，保护火把附近的暖色。
2. **植物透光随视线和光源夹角变化。** 草叶、树冠在朝阳方向有亮边，石头和泥土不一起发光。
3. **材质有区别。** 末地石的细碎微光、冰的表层纹理与高光、水的反射和透射分别控制。
4. **薄雾的高度、方向和时段有区别。** 河谷与远山有空气感，近处保持清楚；保留当前较短的晨昏窗口。
5. **维护运动时的画面稳定性。** 细水纹、星点和云边的过滤应与屏幕尺寸相适应，不能只在静止截图中细腻。

## 2. Steadfast：少量规则建立自然的明暗与夜色

### 源码做法

- 环境光按面的朝向调节，并在天空光不足处保留最低照明；其注释明确把这是作为低成本间接光观感的近似，而非真实全局光照。
- 夜间失色权重由天空暴露度、夜间强度以及方块光决定；调用时把手持光与方块光取最大值，因此火把附近不会与月光区一起失色。
- 方块光和手持光以有限范围衰减，并在强日光中压低存在感，避免白天到处是橙色光斑。
- 水吸收独立于表面波纹。其水下照明还特意保护部分方块光，避免水下建筑的灯光被水色完全吞没。这是艺术处理，不能当作通用物理公式。

依据：[方向环境光、夜间失色及局部光合成](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/steadfast-shaders/source/shaders/environment/lighting/diffuse.glsl>)；[按深度的水色吸收](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/steadfast-shaders/source/shaders/environment/water/absorption.glsl>)。

### Astra 建议

当前 [地表照明](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/Astra/shaders/global/lighting/diffuse.glsl>) 已有方向环境光、夜间填充和距离调节，[局部照明](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/Astra/shaders/global/lighting/blocklight.glsl>) 已有手持光与日间压制。这些不应重复重写。

真正可补的是**有局部光保护的轻度夜间失色**。可以在地表照明阶段，按夜间权重、天空暴露度和局部光衰减，轻微降低月光区域的材质饱和度。保留草地纹理与方块侧面亮度，火把照亮处仍有暖色。无需新增全屏阶段，成本低。

不宜直接照用 Steadfast 的天空光三次方衰减：Astra 刚减轻阴影过黑，照搬会重新压低半遮蔽区域。其吸收色值也不是 Astra 浅水青色的现成答案，两者水深归一化及照明组合不同。

## 3. Complementary：用材质响应让原版纹理显得有层次

### 源码做法

**光照分工明确。** 昼夜、雨天分别配置直射光与环境光；云层由对应的直射和环境颜色生成两组颜色。地表着色里还有受朝向和天空暴露度限制的假反弹光，以及按场景照明与植物类型调整的原版 AO。

依据：[日月直射和环境光配色](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/complementary-reimagined/source/shaders/lib/colors/lightAndAmbientColors.glsl>)；[云的两组照明颜色](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/complementary-reimagined/source/shaders/lib/colors/cloudColors.glsl>)；[透光、反弹光近似、AO 和高光合成](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/complementary-reimagined/source/shaders/lib/lighting/mainLighting.glsl>)。

**草、树叶、石头使用不同材质响应。**

- 草方块的草面根据绿色通道决定光滑度，泥土部分进入另一套材质逻辑；不是把整个草方块统一染成金黄。
- 树叶启用独立透光模式，根据颜色设置光滑度和高光强度，并在掠射角压制部分高光。
- 末地石用纹理红色通道的高次项控制光滑度，让部分纹理位置有更强的反光。
- 冰在透明材质路径里另设光滑度和高光参数，没有与水共用同一套表面响应。

依据：[草方块与泥土材质分流](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/complementary-reimagined/source/shaders/lib/materials/materialHandling/terrainIPBR.glsl>)；[树叶](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/complementary-reimagined/source/shaders/lib/materials/specificMaterials/terrain/leaves.glsl>)；[末地石](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/complementary-reimagined/source/shaders/lib/materials/specificMaterials/terrain/endStone.glsl>)；[冰与其他透明材质](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/complementary-reimagined/source/shaders/lib/materials/materialHandling/translucentIPBR.glsl>)。

**纹理细节也会按距离收敛。** 生成法线从相邻纹理取样，限制在图集单块范围内，并用屏幕导数扩大取样间距、降低无法分辨的法线扰动。纹理覆层噪声则随 mip 层级减弱。这样近处有细节，远处不必仍保持强烈颗粒。

依据：[图集边界与屏幕足迹约束](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/complementary-reimagined/source/shaders/lib/materials/materialMethods/generatedNormals.glsl>)；[随 mip 减弱的纹理覆层](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/complementary-reimagined/source/shaders/lib/materials/materialMethods/coatedTextures.glsl>)。

### Astra 建议

Astra 的 [植物透光](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/Astra/shaders/global/lighting/sss.glsl>) 主要是 N·L 包裹响应；[照明合成](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/Astra/shaders/global/lighting/diffuse.glsl>) 尚缺同等级的视线相关透光亮边。补入低强度的朝光透射项，按草／树叶分类，并受光源颜色、遮挡和天气约束，能直接增强日出时树冠与草丛的层次。已有遮挡结果应复用，不为亮边再读一轮阴影。

[末地石现有高光](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/Astra/shaders/program/lit.fsh>) 已有窄高光加宽高光，不能再描述成“没有反光”。它目前主要按观察方向、法线和光源计算，缺少纹理调制。优先借鉴纹理控制粗糙度／高光强弱的思想，使用已有纹理样本，让少量矿物颗粒在黑洞方向发亮；低成本且比全表面增强镜面反射更符合需求。

生成法线属于第二步：会增加邻域取样，并需要可靠的切线、图集边界和距离过滤。不能用无约束高频噪声把石头做成闪烁的砂纸。

## 4. BSL：柔和的亮部、层次明确的空气与湿润地面

### 源码做法

- 地表照明区分环境色、直射色、局部光和最低照明；基础植物散射由视线与光源夹角驱动，雨天减弱。另有材质亮度平衡、夜雨失色选项。
- 雾色结合视线朝向、高度角、太阳方向与距离；雾密度再受天气、昼夜、室内暴露度及可选高度衰减影响。
- Bloom 由多个空间尺度重建，再与原图混合。其这条路径并非简单将宽泛辉光一直累加到场景上，因此不能把效果归因于“Bloom 更强”。
- 水坑结合世界空间噪声、湿度、朝上程度、天空暴露和材质高度。湿润程度改变粗糙度、最低反射率及底色暗化；孔隙度让不同材质的变化不同。
- 水坑涟漪在掠射视角减小法线扰动，减少远处反射破碎的倾向。

依据：[照明与基础植物散射](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/bsl-shaders/source/shaders/lib/lighting/forwardLighting.glsl>)；[方向、高度与天气雾](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/bsl-shaders/source/shaders/lib/atmospherics/fog.glsl>)；[多尺度 Bloom、曝光与调色](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/bsl-shaders/source/shaders/program/composite5.glsl>)；[水坑、涟漪及湿材质响应](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/bsl-shaders/source/shaders/lib/reflections/rainPuddles.glsl>)。

### Astra 建议

Astra 已有多尺度 Bloom、稀疏水坑、涟漪足迹过滤与朝上表面限制。可补强的是：

- 让**潮湿地面和有积水的地面分开**：潮湿区域轻微变暗、略增高光，只有少量积水区域出现清晰反射。
- 将水坑涟漪再与视角结合，掠射观察时减小法线扰动；这只能改善扰动造成的破碎，不能替代对 SSR 草丛交点的正确处理。
- 将太阳核心、近端辉光、宽端 Bloom 分别控制，保留方形轮廓与亮部颜色层次。
- 用高度与距离共同控制薄雾，而非整屏提白。

代价：湿润底色与粗糙度调节通常较低；增加新的反射或多道模糊会提高成本。BSL 的完整材质高度／孔隙度路径需要相应输入，Astra 可先采用有限材质分类近似。

## 5. Photon：让光照、空气与材质遵循同一空间关系

### 源码做法

**环境光带方向。** 在支持的主世界延迟路径与开关下，用球谐系数和弯曲法线求天空照明；其他路径使用环境颜色近似。植物散射有随配置切换的透射深度模型或柔化近似，也有适用于草叶的 sheen。

依据：[方向天空光、反弹近似与植物散射](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/photon-shader/source/shaders/include/lighting/diffuse_lighting.glsl>)。

**空气随高度和时段变化。** 解析雾先积分高度密度，再分别返回散射和透射；散射区分光源方向。天气参数包含清晨、中午、傍晚、午夜及蓝调时刻权重，并结合生物群系和湿度。解析路径也使用有限次多重散射近似，并非完整物理求解。

依据：[高度密度积分及散射／透射](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/photon-shader/source/shaders/include/fog/overworld/analytic.glsl>)；[时段与天气参数](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/photon-shader/source/shaders/include/weather/fog.glsl>)。

**高光有材质与光源尺寸约束。** 材质区分粗糙度、基础反射率、金属、透光与孔隙度。光源高光采用有限角尺寸的 GGX 近似，并对峰值设上限以免冲坏 Bloom；新月时关闭对应月亮高光。

依据：[材质参数](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/photon-shader/source/shaders/include/surface/material.glsl>)；[有限尺寸光源与高光峰值限制](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/photon-shader/source/shaders/include/lighting/specular_lighting.glsl>)。

**夜色与曝光是两套控制。** Purkinje 效应按暗处视觉响应改变色彩，并减弱方块光区与地下的影响。自动曝光可选简单或直方图统计，使用历史曝光和不同明暗适应速率平滑变化。

依据：[暗视觉颜色变化](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/photon-shader/source/shaders/include/misc/purkinje_shift.glsl>)；[曝光统计及时间平滑](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/photon-shader/source/shaders/program/c4_taa_exposure.vsh>)。

### Astra 建议

优先借鉴低成本版本：用朝上、侧面、朝下的环境光分配代替单一颜色乘统一强度；使用限定范围的高度薄雾；按材质粗糙度控制高光宽度与峰值。完整球谐天空光还需要生成／更新系数及遮蔽数据，属于更大的结构调整。

Photon 的圆形太阳面积光近似不应原样用于 Astra 的可见日月。可以学习“高光有有限宽度和能量上限”，保留方形日月主题；末地高光方向继续取黑洞。

Astra 当前固定曝光有稳定性优势。近期不必为获得柔和画面立刻加入全局自动曝光：先平衡光照和亮部肩部；自动曝光会额外引入转头时明暗变化。若后续采用，需要明确统计、适应速度与亮度范围，不能只把上一帧均值乘回来。

## 6. MakeUp：用协调的配色和简单材质高光提高观感

### 源码做法

- 每套配色分别配置直射光、天顶、地平线和水色，再经共同的昼夜混合函数过渡；夜间亮度含月相影响。
- 材质高光用反射方向与日月方向的对齐度、幂指数和材质强度形成，在主世界还结合天空光与雨量。其末地使用固定方向，这一部分不适合 Astra 的黑洞光源。
- 云的二维密度决定上下表面及厚度，首次有效接触位置参与云体颜色；薄边与厚云体使用不同的亮度响应。
- AO 与 TAA 都有成本：AO 循环读取周围深度；TAA 用当前邻域的均值／方差约束历史颜色。不能只移植历史混合而省略稳定性处理。

依据：[成套配色与月相亮度](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/makeup-ultra-fast-shaders/source/shaders/lib/color_utils.glsl>)；[时段混合](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/makeup-ultra-fast-shaders/source/shaders/lib/day_blend.glsl>)；[轻量高光](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/makeup-ultra-fast-shaders/source/shaders/lib/material_gloss_fragment.glsl>)；[厚度与云边着色](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/makeup-ultra-fast-shaders/source/shaders/lib/volumetric_clouds.glsl>)；[深度 AO](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/makeup-ultra-fast-shaders/source/shaders/lib/ao.glsl>)；[历史颜色约束](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/_analysis/performance-study-2026-09-16/makeup-ultra-fast-shaders/source/shaders/lib/fast_taa.glsl>)。

### Astra 建议

很适合借鉴其成套配色组织与轻量材质高光。Astra 的实际差距是各模块的响应仍不够一致，不是缺少另一套色调映射函数。

可将月相对直射月光的影响做成小幅变化，同时让环境光保持可读。不能把新月环境光也一起归零。云方面先调整厚度、明暗面和边缘分工，保留当前方块造型；不直接搬入 MakeUp 的强边缘增亮系数，以免重现泛白。

## 7. 水体与动态稳定性：跨光影最重要的两条经验

**水色必须沿完整光路判断。** Steadfast 将深度吸收与入射光关联，BSL 的水雾颜色受环境光照控制，Photon 的水下体积同时累计透射和散射。说明白天水面偏蓝不能只怪吸收色值，还要看水底照明、天空反射比例、观察角度以及输出色彩空间。

Astra 当前 [水面光路](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/Astra/shaders/program/water.glsl>) 已有 Fresnel、屏幕空间反射／折射、共享天空和有遮挡的太阳高光，[介质吸收](<C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/Astra/shaders/global/water/absorption.glsl>) 也已拆分相关路径。后续视觉补强应围绕浅水保留水底纹理、低角度反射天空、太阳方向出现局部暖亮带；避免增加一层固定青色覆盖所有深度。

**动态稳定也是画质。** Complementary 的生成法线、Astra 已有的水波足迹过滤、Photon 的云重建与 MakeUp 的历史颜色约束，都在处理同一类问题：屏幕已经不能分辨的细节不应继续产生强烈明暗变化。

Astra 近期适合优先完善高光宽度、距离过滤和固定世界坐标细节。全场景 TAA、低分辨率云重建、自动曝光应分别评估其数据依赖；移动实体、挥动植物、末地公转与吸积盘都存在独立运动，不能仅靠相机矩阵把旧画面混回来。

## 8. 建议给 Astra 的实施顺序

| 顺序 | 具体方向 | 可见收益 | 新增成本与注意点 |
| --- | --- | --- | --- |
| 1 | 夜间局部失色，保护火把颜色；重分配背光环境光 | 夜晚仍有纹理，远处暗而不死黑 | 低；使用现有天空光和局部光数据 |
| 2 | 草叶、树冠的视线相关透光亮边 | 朝阳真正落在植物上，近中景更生动 | 低；复用遮挡，限制强度与材质 |
| 3 | 末地石纹理调制微高光，冰表层独立粗糙度 | 材质区别清楚，反光不盖住纹理 | 低至中；先用已有纹理，生成法线另算 |
| 4 | 有高度、方向、短时段权重的薄雾 | 河谷和远山有纵深，晴天近处清楚 | 中；先解析近似，不增加全屏长步进 |
| 5 | 潮湿地面与稀疏积水分离，涟漪随视角收敛 | 雨景更丰富、反射更稳定 | 低至中；保持用户要求的较少水坑 |
| 6 | 云体／云边亮度分工，水面与天空保持同一配色 | 晨昏联动更完整 | 低至中；优先调整已有着色 |
| 7 | 亮部肩部、局部高光峰值与多尺度 Bloom 配合 | 方形太阳清楚，亮部仍有颜色 | 通常低；不靠全局增曝光提亮暗部 |
| 后续 | 完整 TAA、球谐天空光、体积彩色光、自动曝光 | 能解决更广泛的稳定性和照明问题 | 中至高；各自需要缓存、更新与失效处理 |

这里的优先级依据用户反馈与当前 Astra 的具体缺口。最先值得补的是夜色、植物和材质响应；已有的阴影、天空、水体和后处理结构足以支撑这几项，收益不依赖先增加一套昂贵的全局光照。

