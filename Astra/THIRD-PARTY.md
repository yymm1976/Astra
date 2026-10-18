# Astra — 第三方出处台账（THIRD-PARTY.md）

### 雨雾源色共用与末地高度层次

依据源码取证版线索回读Photon main快照`include/fog/end_fog_vl.glsl::end_fog_density`，仅参考“密度随高度变化”的思路，没有复制其指数衰减、坐标阈值、发光噪声或步进实现。Astra自写宽高度包络、实际空气段三点平均及远端渐隐恢复；不是Photon体积雾移植。雨雾光源改为复用包内既有太阳源色与微暖亮度归一函数，共用条件移到deferred顶点，原逐位置阴影/云判断保留。无新增外部代码或素材，原模块的派生归属继续适用。

### 选择性色彩、空气光束配色与云下柔化

参考新增调研所引Photon main的选择性色相调色及阴天柔化思路、ComplementaryReimagined main的`lib/colors/lightAndAmbientColors.glsl`地面/光束配色分工；本次读取报告对应本地分支快照。Astra自行编写RGB分量选择、显示亮度及通道余量限制、入射亮度归一的微暖空气光束色和已有云遮挡驱动的最多25%半径调整，没有复制HSL函数、色相隔离表达式、参考色表或半影倍率。水面单位视线复用和顶点高光配色沿用包内既有公式，原Steadfast、Complementary、Mellow及Solas派生归属继续适用；没有新增素材或vendor代码。

### 树隙阳光、天空亮源薄光晕与照明分离

参考本地Solas `lib/atmosphere/volumetrics.glsl::computeVolumetricLight/calculateVLParameters`、`lib/post/getBloom.glsl`，本地Photon及2026-10-17在线main的`program/c5_c10_bloom_downsample.fsh`、`include/lighting/colors/end_color.glsl`。仅采用真实阴影逐位置遮挡、遮挡后亮源扩散、直射与环境配色分离的思路，没有移植其循环、捕获核、色表、源强表达式或新增素材。Astra自行编写48格树隙光、HG相位参数、共享段透过比例、终点深度保护重建，以及可见天空捕获和统一显示光晕；复用现有阴影/Bloom模块的原归属继续适用。鲜艳度/饱和度合并及日月单侧求值是包内既有公式调整，Mellow等既有来源保留。当前行为、成本和限制见[实现与限制](../docs/实现与限制.md)。

### 2026-10-17：程序银河与带内微星

`global/atmosphere/stars.glsl`的银河亮度、静态中心权重、尘埃增强、同一星表中的暗弱候选及局部TAA反应值由Astra编写。Photon的`draw_galaxy/draw_stars`和Solas的`drawMilkyWay`只提供“银河结构与局部星点密度有关”的思路；未复制新的参考表达式、代码、全景图片或噪声素材。原模块的Complementary投影与可见性来源、既有Solas噪声素材归属继续保留。亮度为编译选项，不新增CPU颜色表达式、独立星场或绘制阶段；具体行为和开销见实现说明。

### 2026-10-17：SMAA 1x与实心地形入口

SMAA内核直接取自[iryoku/smaa的master分支SMAA.hlsl](https://github.com/iryoku/smaa/blob/master/SMAA.hlsl)，读取日期2026-10-17，保存为`shaders/lib/vendor/smaa/SMAA.glsl`；Jorge Jimenez、Jose I. Echevarria、Belen Masia、Fernando Navarro、Diego Gutierrez的版权及MIT式许可保留在源文件和同目录`LICENSE.txt`。本地改动为将原注释编码转为UTF-8，并将颜色及亮度边缘函数的无边缘discard改为写零返回，以匹配Astra无需清空的完整输出。采用high预设的水平/垂直、对角和角点处理。

`textures/smaa-area.png`与`smaa-search.png`复用本地Mellow的`shaders/img/smaaArea.png`和`smaaSearch.png`标准SMAA查找表；Mellow的Copyright (c) 2026 TheCMK及MIT许可完整保留于`lib/vendor/smaa/MELLOW-LICENSE.txt`，SMAA上游归属同时保留。Grindstone只用于研读阶段组织，没有复制其CC BY-SA的redmean.glsl或CAS实现。

三维度composite10/11包装、显示输入复用、单附件双图翻页、开关调度及在线性光量中执行的三像素最终混合由Astra接入编写；最终权重读取和单轴双区域插值沿用SMAA的邻域混合规则。实心/镂空地形入口使用本机Iris已有路由，不包含新的第三方表达式。实际行为及资源代价见[实现与限制](../docs/实现与限制.md)。

### 2026-10-16：下界砖反光、局部彩光与独立质量

第五批保留项采用范围：直接研读本地TrueLightFX的`directionalLightmap.glsl`及velocity-shaders的`program/deferred.fsh`、`global/water.glsl`，仅作机制比较，未复制其表达式。新增`lib/handheld_light.glsl`、`global/dimension/nether_light_debug.glsl`、下界六邻居光场方向估计和受矩阵形状保护的反投影由Astra编写。`lib/emitter_colors.glsl`仅集中包内既有体素发光色表，计算传播的脉动和源强度不变；Solas传播及Steadfast/Complementary照明的既有派生归属继续适用。手持身份输入依据Iris ShaderDoc，stars/oldHandLight指令依据本机Iris布尔解析，无新增第三方代码或素材。实现边界与未采用的共享粗深度见[参考与取舍](../docs/参考与取舍.md)。

通过Octocode读取本地Complementary的`terrainIPBR.glsl`下界砖分派与`mainLighting.glsl`，Photon的`diffuse_lighting.glsl`、`lpv/blocklight.glsl`和`colors/nether_color.glsl`，以及Solas的`gbuffersLighting.glsl`；另在线核对Complementary和Photon的main对应文件。参考的是材质单独赋予光滑度、局部彩光与普通光照共同维持可读性的分工，没有复制新的参考表达式、代码或素材，本地副本发布版本不以修改时间推定。

`block.10018`的砖材映射、第26位身份传递、`astra_nether_masonry_smoothness`的0.08～0.18范围、`nether_masonry_ambient`的暗砖面补光、彩光混合前的亮度支持和独立NETHER_REFLECTION_QUALITY接线由Astra编写。均衡九区域重建沿用包内已有Complementary派生接收面过滤结构，新增可分离权重及与低档方差对应的布局由Astra编写；原EminGT过滤、Solas传播及相关许可归属继续适用。没有新增第三方素材或vendor许可，当前实现与代价见[实现与限制](../docs/实现与限制.md)。

### 2026-10-14：性能与调色报告对应的改编范围

`lib/tonemap.glsl::astra_uchimura_peak` 是包内既有Uchimura默认参数的标量特化，沿用glsl-tone-map / Damien Seguin的MIT归属与现有许可文本。`astra_natural_uchimura` 的整体比例压缩和高亮趋白接线由Astra编写；Photon的输入/输出调色分工、Complementary的高亮趋白仅作概念参考，没有复制两包的调色函数、色表、选择性色相代码或新增素材。自然对比度的亮度幂、晨昏CPU表达式、云恒定颜色累加消除和空云历史读取提前裁减由Astra编写，保留相关模块原来源。来源与许可范围以本文件对应条目为准。

### 2026-10-12：针对水体、阴影、云与配色的优化

普通水下的分色透射、标量距离可见度、介质色、湿天气灰化及上下视线响应改编本地IterationT 3.2.0 composite1.fsh::WaterFog；深度响应和线性场景混合参考Lib/Programs/Final.glsl。Astra将指数系数折为常量、复用真实光程，按自身照明单位标定介质，采用两级较窄柔化；没有新增纹理或整套体积雾。水上单足迹透射路径及主世界4/9的精度分离由Astra接线。Solas的帧光照、薄流水及显示曲线继续保留归属；旧四方向扩散已退出。ITT既有许可与素材归属适用，这些公式改编不登记为仅思路参考。

主世界水面未消费切线的裁减、薄流水状态及太阳基底的顶点复用、折射回退同纹元格深度共享、实体深度延后解包，以及水上水平SSR四个计划查询的预取与保守顺序消费，由Astra编写；原Steadfast/Solas模块归属保持。主世界畸变核心与生效半径接线、原始NDC插值以保留平面导数精度及混合边缘固定对称过滤，由Astra编写；Steadfast径向投影的GPLv3及§7条款保持。云覆盖范围的稀疏探测、单调重建及颜色重新预乘由Astra编写，保留Complementary云体和既有历史实现归属。

清新配色只参考Steadfast 0.8.0本地天空/显示分工与既有画面，不复制其色表或切换显示算子。现行机制与代价在[实现与限制](../docs/实现与限制.md)，实际完成程度在[当前工作](../docs/当前工作.md)；下方日期条目保存各轮来源，不替代现行说明。

### 2026-10-07：下界轻量实现

- `program/nether_light.csh` 新增工作组光源汇总、两字源区域位图和保守可达查询，由 Astra 编写；Solas 3.7b 的源配色与六邻格传播架构、现有许可归属保持。
- `program/nether_reflection_resolve.fsh` 的五区域等能量／二阶矩核及 `global/dimension/nether.glsl` 的亮区颜色转换裁减为 Astra 自写。Complementary／EminGT 的接收面反射、颜色域照明及原许可保持；没有移植新的参考实现或素材。
- 本轮没有新增代码级第三方复用，不新增 vendor 许可。

### 2026-10-07：天空与阴影轻量接续

- `global/lighting/shadowmap.glsl` 与 `diffuse.glsl` 新增不透明影图优先顺序及全亮／全暗权重准备裁减，由 Astra 编写；既有 Steadfast 派生结构、GPLv3 与 §7 条款保持。
- 现行主世界原生接收面的未畸变NDC传递、片元重投影、静态方块法线平面斜率、逐角逆投影与有限面参考深度限制，非水投射物保守深度修正，中高档固定四组过滤及世界宽度限制，以及Iris主世界原点连续更新接线由Astra编写；沿用原Steadfast径向投影和阴影模块归属。Solas与Photon的片元投影、均匀遮挡拒绝提供思路参考，未复制新的阴影代码或素材。水面、体积和其它维度的既有配对保持；现态以实现说明为准。
- `lib/sky_gradient_cache.glsl` 的尺寸分档与配置映射，以及 `clouds_planar.glsl` 的环境专用搜索预算、`sky_reflection_cache.fsh` 的球面角度足迹接入，由 Astra 编写。原天空／云的 Complementary 来源及许可保持，没有新增移植代码或素材。
- 本轮不新增 vendor 许可原文；

### 2026-10-07：三项轻量水面实现

现行水路来源：`lib/itt_water_waves.glsl` 直接改编本地IterationT 3.2.0 `Lib/IndividualFounctions/WaterWaves.glsl` 的三次平滑噪声、AlmostIdentity、六层结构、坐标变换与滚动（权重及空间展宽由Astra调整）。Astra对同一层合成求解析梯度并过滤未解析的方差，代替参考的完整高度差分；光束与水下水平界面共用这些法线。`textures/itt-water-noise.png` 及其 `.mcmeta` 复制自同一参考包的 `texture/noise.png`。法线碰撞偏移、光量立方、折射投影、有限距离、分颜色消光、距离权重及线性加光改编 `UnderwaterVolumetricFog.glsl` 与 `composite5.fsh`；阴影矩阵Z轴方向沿用 `Lib/Programs/CompositeVS.glsl`，Cornette–Shanks公式改编 `Lib/Utilities.glsl`。掠射距离、光量上限与角度响应由Astra适配。

单张世界波面碰撞光量图、覆盖窗口、解析梯度接线、非线性光量先于mip过滤、按屏幕足迹读取mip、外层四点Gauss遮挡/消光与权重分段内八点光量积分、实际水位投影、逐点入口/接受点遮挡、近远衰减、真实眼点、手部排除和弱支持端点处理由Astra编写或适配。当前RG16F源图的普通像素R存光量，零号RG存窗口偏移；水平界面直接计算同一波场，不从源图读取斜率。入射/观察水路的独立消光、波长小幅展宽及碰撞响应调节为Astra调整。没有额外包络、固定圆形入口、格内发射点、四深度切片或反求光路。Solas `volumetrics.glsl` 的两影图入射透光与遮挡分离、有限距离与昼夜强度分工属于 **IDEA ONLY**；逐角深度差配对本包水面身份/水高由Astra编写，没有移植其显式发射几何或阴影颜色采样循环。无空气光柱时裁掉散射绘制、附件清零，以及水面齐次深度交点直解为Astra自写优化。主世界Bloom配置的水下合成颜色改用RGB16F，并在所有抗锯齿模式中直接显示此颜色以避免重复压缩，由Astra编写；保留原水雾和显示公式。Solas水雾/显示、光照颜色、侧面噪声及水底焦散素材，Steadfast空气水面波场和共用阴影模块归属保持。没有新增外部素材，现行机制见[实现与限制](../docs/实现与限制.md)，参考入口见[参考与取舍](../docs/参考与取舍.md)。下方历史条目中的旧通道及机制不作为当前实现说明。

`program/water.glsl` 的单足迹配对、四角共享逆投影、水深/雾量范围判断、失败后的端点复用、仅在失败时构造端点记录、延后颜色读取与空气段选择，`global/water/refraction.glsl` 的已读四角深度传递及同纹理格查询复用/重新选取最邻近深度，`global/water/raytrace.glsl` 的标准透视窗口深度判定、完整可见投影段查询及预测位置重新确认，以及 `lib/water_entity_record.glsl` 的覆盖与打包均为Astra适配。Steadfast提供连续四角接受与单次颜色读取的组织参考，没有提供这些新增具体算法；原文件派生归属及GPLv3/§7条款继续适用。`global/water/surface.glsl` 的单步视差与预算由Astra接线，沿用Steadfast原有高度插值、解析梯度与波脊表达式。先前新增的四角高度缓存及周期格键已移除，现直接读取高度并在位移位置求法线；不改其波场归属。波面单步视差、未消费反射锥裁减、已退出的四方向深度约束场景柔化、闲置水下合成绘制裁减及 `lib/water_wave_lens.glsl` 的水底聚光由Astra编写或适配；不把它们当作ITT移植范围。同帧碰撞光量缓存、顶点窗口计算、水下连续倒影的介质范围共享和反射细化时的自身纹元交点由Astra适配。水下透射窗口的原版太阳读取游戏活动资源包原有贴图，没有复制进光影包；程序模式继续解析盘，光色与云遮挡沿用现行天空，反射强度、细焦散和浅青配色为本地调整。既有体积散射分工参考范围保持；现行水雾公式与深度泛光改编范围见本页2026-10-12条目，没有移植专用DOF代码。现行行为见[实现与限制](../docs/实现与限制.md)，实际完成程度见[当前工作](../docs/当前工作.md)。

- `program/water.glsl` 连续足迹共享代表路径传输、硬件双线性颜色读取，参考 Steadfast 0.8.0 `environment/lighting/translucent.glsl:471–487`、`environment/water/refraction.glsl:168–177` 的组织思路。空间距离、界面侧、角点进入的渐退、原几何证据复用与共享系数接口由 Astra 编写；新增范围登记 **IDEA ONLY**。文件原有 Steadfast 派生结构及 GPLv3／§7 附加条款继续适用，不能将整个文件改记为自写。
- `global/water/raytrace.glsl` 与调用侧参考 Mellow `shaders/global/water.glsl:68–100`（`:89` 按 Fresnel 分配细化）的工作量分配思想。Astra 自写连续重要度、粗尾缩短、分数末次查询覆盖与重载接口，保持原命中细化；没有移植来源追踪、取整或步进表达式，登记 **IDEA ONLY**。
- `global/water/surface.glsl` 的两层细涟漪距离渐退及稳定粗糙度衔接，是在既有 Steadfast 派生波场上的 Astra 新增适配。`global/water/absorption.glsl` 将现行 Astra 连续水色拆出透射与散射系数，没有引入新参考色谱或公式。MakeUp `lib/water.glsl:213–238` 只用于佐证物体倒影／环境回填／独立太阳高光的分工，未新增移植其代码。
- 水面读取优化没有新增参考素材或代码片段；现行ITT光束的代码与噪声复用范围已在上方明确登记。既有Steadfast、Solas与其他被修改模块的归属继续适用；不以旧条目的“仅思路借鉴”覆盖当前代码级改编。

### 2026-10-06：整包轻量近似实现

本轮云粗搜索／二次边界细化与单点照明近似、下界 2×2 稀疏反射及 3×3 连续重建、水／积水共享短射线、波面视差松弛系数、Bloom 五点矩匹配、FXAA 搜索预算、阴影提交系数及实体距离配表、末地粗糙反射缓存容差由 Astra 编写或选择。继续沿用云／下界的 Complementary 派生、波面视差的 Steadfast GPLv3 与 §7 附加条款、FXAA 的 Arc MIT 及既有 Solas 噪声资源归属。未从新参考包复制代码或素材，未引入新第三方许可证；既有 vendor 原文与发布约束继续适用。下界反射元数据 B 已从 `256+flags` 改为 `512+flags`，下方旧布局记载为历史。见[现行实现说明](../docs/实现与限制.md)。

### 2026-10-06：末地连续流纹与温度描绘

`global/dimension/end_kerr.glsl` 盘面改用两尺度连续 Cartesian 流场与有界线性密度，由 Astra 编写，沿用既有原创流纹和周期 mip 图集；旧 `end_disc_noise/end_disc_detail` 的 Complementary / flytrap 五层程序细纹已从活动源码移除。下方这些函数和平方细节的条目保留历史出处，不能再描述当前材质。弱 `sqrt(radius)` 旋绕仍沿用 Solas 的既有结构归属，新的 .18 系数、足迹与动画接线由 Astra 选择。

盘面温度驱动暖红/冷蓝描绘、亮度归一及光子环冷暖标定由 Astra 编写，黑体辅助函数、频移强度、光路图集和遮挡保留。未新增第三方代码、素材或 vendor 许可；近期 GitHub 阅读仅为调研，没有移植 MakeUp / Luster 片段。参考精简未删除本包 vendor 的许可原文。见 [现行实现说明](../docs/实现与限制.md) 和 [线上更新调研](../shader_research/2026-10-06-recent-online-shader-updates.md)。

### 2026-10-04：SUMMARY-batch4 水体反射重复工作裁减

阅读本地 dercode `lib/Surface/ScreenSpaceReflections.glsl` 的水下路径后，选取减少当前反射开销的方向；没有复制其抖动、深度容差、方差查询、远距命中或细化代码。条件式 Z/W 重建复用、SSR 已知锚点深度传递、完整命中跳过备用水雾与天空分支跳过无贡献颜色读取均为 Astra 既有代码调整。`program/water.glsl` 的 Steadfast 衍生组合结构和 Solas／ITT 既有来源继续适用，没有新增第三方片段或素材；范围见[现行实现说明](../docs/实现与限制.md)。

### 2026-10-04：SUMMARY-nightsky 主世界群星选择优化

参考本地 Photon `include/sky/stars.glsl` 与 Bliss `lib/stars.glsl` 的固定格点四邻域连续重建，以及 Photon 的逐星颜色／相位思路；没有复制其函数或黑体拟合代码。整数格点随机数、双球面区域的平滑交叠、有限冷暖色板、弱闪烁、五档密度及星光贡献接入既有 TAA 反应遮罩由 Astra 编写。天体坐标使用既有太阳世界方向与 `sunPathRotation`，本地 Complementary `lib/util/commonFunctions.glsl::GetSunVector` 的方向约定用于确认天轴符号；未复制其太阳时间曲线。原 `stars.glsl` 保留的球面投影、地平线／日月遮蔽与天气／晨昏可见性继续归属 Complementary r5.9；本轮没有新增素材，范围见[现行实现说明](../docs/实现与限制.md)。

### 2026-10-04：水下曝光与模块衔接审查

普通水体曲线前曝光调整、薄水层在既有曝光／AO／体积雾／天空／FXAA／颗粒消费者中的判定衔接，以及水平水面投影入口的无贡献材质读取裁减，均为现有 Astra 模块调整。没有新增第三方代码片段或素材；被修改的 Solas、Steadfast、Complementary 及其他既有衍生模块继续保留原来源归属。范围见[现行实现说明](../docs/实现与限制.md)。

### 2026-10-03：SUMMARY-batch3 选择实施

参考 Potato 的风场距离门控思路，Astra 自行编写 128–192 格平滑衰减，并将摄像机相对距离接入当前模型、既有投影与上一帧植物位移；没有复制其风场、天光调制或原样硬截止。参考 Bloop 的单通道邻域 gather 思路，Astra 自行编写两次 gather 加两个独立角点的完整 3×3 反应遮罩聚合及边界回退，没有复制参考包遗漏一个角点的函数。参考 Builder's QOL 的帧量上提思路，把既有云白天光色与环境色公式移至 CPU 求值；其原 Complementary 衍生公式来源与许可继续适用。本轮没有新增第三方实现片段或素材，范围与取舍见[现行实现说明](../docs/实现与限制.md)。

### 2026-10-03：植物投影恢复与浅水／竖直水帘衔接

`lib/water_interface_record.glsl` 的介面类型标识、既有一像素介质记录的薄层分类与消费，以及 `program/water.glsl::astra_vertical_water_interface` 的短水路和有界反光由 Astra 编写。浅段吸收与补色参数、薄层照明／显示／雾接线和投影入口对植物的恢复均为现有模块的调整，没有新增第三方片段或素材。水平窗口与普通水体继续沿用既有 ITT／Solas／Steadfast 来源；此轮未移植新的流体拓扑查询或追踪器。竖直水帘的反光为外观近似，识别边界、开销和画面确认状态见[现行实现说明](../docs/实现与限制.md)。

### 2026-10-03：连续深度水色、弱浅水焦散与岸上开销裁减

连续深度权重、浅水吸收参数、接收面水深驱动的中性聚光与标量峰值压缩，以及水记录的两通道 gather 路径均由 Astra 编写。`global/water/raytrace.glsl` 的齐次投影复用、界面平面判据和本射线深度读取复用也是 Astra 编写；没有新增第三方片段。`global/lighting/diffuse.glsl` 依据既有叶片包裹方程排除零直射贡献查询，`program/water.glsl` 复用反射滤波的中心颜色；原 Steadfast 衍生模块许可继续适用。下方光学波场、Solas 色彩合成和其他既有出处保持归属，现行表面焦散不再使用固定青色乘聚光并逐通道截断。范围与尚未确认的帧率目标见[现行实现说明](../docs/实现与限制.md)。

### 2026-10-03：水下轻柔化、透明浅水与水下雨滴过滤

现已退出的自写 `lib/water_diffusion.glsl` 固定四点深度加权扩散、距离强度与窗口保留条件，以及 `global/water/absorption.glsl` 的透明浅水／青色中段／蓝色深段参数由 Astra 编写。朦胧观感参考用户提供的 ITT 3.2 画面，读取其 `composite1.fsh::WaterFog` 作为距离雾参考，没有移植新的模糊代码或素材。雨滴过滤移除摄像机在水外的限制，沿用下方已登记的 Photon／Hysteria 蓝色粒子识别机制。既有被修改模块的来源归属继续适用，具体范围见[现行实现说明](../docs/实现与限制.md)。

### 2026-10-03：光束逐步波面变化与水下全反射窗口

参照本地 ITT 3.2.0 `Lib/IndividualFounctions/UnderwaterVolumetricFog.glsl`、`Lib/BasicFounctions/Sunlight_Shadow.glsl` 的波面法线场投影，由 Astra 编写现有水面阴影记录的斜率/聚光缓存、每个体积步的水面位置查询及局部折射投影；没有移植 ITT 的法线附件和多层波形素材。`light_shafts.glsl::water_shaft_phase` 按 ITT `Lib/Utilities.glsl::MiePhaseFunction` 的 Cornette–Shanks 结构改编，使用 Astra 的归一化、底光与峰值限制。

`program/water.glsl` 根据 ITT `composite1.fsh` 的折射方向天空查询、全反射判断，以及 `composite2.fsh` 的反射组合组织，接入 Astra 已有介电方程和天空/云环境。菲涅尔计算、水路补全、缓存格式及主世界底面波场接线为 Astra 编写。Solas 的色彩合成域及侧面法线、Mellow 的 IGN、Steadfast 阴影和透明组合的既有出处继续适用。实现、数据格式和开销见[现行实现说明](../docs/实现与限制.md)。下方各历史条目中的旧通道格式、旧相位和法线描述以本节及说明中的现行为准。

### 2026-10-03：根据三张水下截图调整水体、光束与焦散

后续光束颗粒处理复用现有 Mellow v3.4（MIT，TheCMK）来源的 `lib/dither.glsl::ign`，没有新增参考片段。四角水面身份/深度/聚光配对及连续九点二次 B 样条重建由 Astra 编写，沿用现有压缩域与距离权重。读取预算变化、画面边界及动态效果确认状态见调整说明；本文件中既有 Mellow、Solas、Steadfast 与 ITT 来源登记继续适用。

用户后续反馈光束静止。Astra 自行编写 `lib/water_wave_lens.glsl`，将既有两层值噪声的斜率与曲率共享给光束偏转和焦散聚光，使用已有 Solas 噪声素材；根据现有水面状态按深度扰动光束阴影投影，并自行调整动画速度、历史时长与峰值上限。没有新增参考代码或素材；既有 Solas 与 ITT 来源归属继续适用，新增读取开销和局部折射近似见下方调整说明。

随后用户提供新版 Astra 截图：雾层与背光可见性已有改善，但聚光层次不足。Astra 将解析曲率的格点源从已平滑的绿色高度通道改为已有噪声图的独立蓝色通道，水下界面法线仍使用绿色通道；光束改为只对标量聚光增益取三次方，透射色保持一次乘入，并自定较淡的光束色。水雾青色略向蓝侧调整。没有新增素材、噪声读取次数或参考代码，既有来源归属继续适用。

- `lib/water_palette.glsl` 的共享水面/水下青色及密度参数由 Astra 编写，颜色方向参考用户提供的 ITT 3.2 截图。`lib/solas_water.glsl` 与 `solas_water_frame.glsl` 仍保留登记的 Solas 天空光色、最低照明常量与上下视线响应来源；当前水雾在线性光域合成，普通水下显示共用已登记的色调映射算子，独立 Solas 显示曲线已退出当前实现。现存 Solas 派生部分的许可与归属继续适用。
- `global/water/light_shafts.glsl` 的短水段积分、折射光源相位、聚光的三次方对比及距离衰减，改编自本地 ITT 3.2.0 `Lib/IndividualFounctions/UnderwaterVolumetricFog.glsl` 的结构。Astra 采用现有成对阴影深度与水面类型数据、48 格上限、递推透射与有界 HG 相位；没有移植 ITT 法线缓存、Cornette–Shanks 相位公式或额外附件。Solas 的四次方根存储/解码与既有历史来源继续保留，重建改为四角读取。
- `global/water/caustics.glsl` 的水下界面法线仍来自 Solas。新增聚光部分借鉴 ITT `Lib/BasicFounctions/Sunlight_Shadow.glsl::CalculateWaterCaustics` 的波面折射落点聚集思路，由 Astra 编写平滑值噪声的解析曲率、两个波层及落点面积倒数；没有复制其 3×3 落点循环或波形素材。现有 Solas 噪声素材来源继续适用。
- `global/lighting/diffuse.glsl` 的深水环境光接线、既有水面状态消费、`shaft_history.glsl` 的积分窗口中点改动由 Astra 编写；上述被修改模块的既有 Steadfast、Solas 与其他来源归属继续适用。实现范围见[现行实现说明](../docs/实现与限制.md)。

### 2026-10-03：轻量水下雾的距离响应

`shaders/lib/solas_water.glsl` 的现存 Solas V2.2b 派生部分继续保留 Septonious 及既有来源归属。距离雾、颜色吸收与方向性散射分开组织的参考为 IterationT 3.2.0 `shaders/composite1.fsh::WaterFog`；当前实际水段、线性合成、共享水面青色和密度参数由 Astra 编写，不移植 ITT 的光线步进或素材。当前实现与取舍见[实现与限制](../docs/实现与限制.md)。

### 2026-10-02：视频参考包性能机制与调色组织

已下载的 14 款参考光影、版本、来源和逐包性能机制见 [现行实现说明](../docs/实现与限制.md)，本地档案见 `_analysis/video-2026-10-01/sources.json`。Derivative 为 DureXXX 团队维护的 main 分支 25.1.0，IterationT 3.2.0 为公开镜像。

本轮新增的 `lib/color_controls.glsl`、分时天空通道、暗部 / 中间调 / 高光通道及菜单由 Astra 编写；配置组织借鉴 Mellow 的独立颜色方案、天空上下层与光源分组。阴影过滤预算、云 / 体积雾档位，以及 CPU 光源衰减为现有 Astra 模块的适配；依据参考包中的小采样核、降分辨率和帧不变量计算思路，没有新增参考 GLSL 或素材的直接移植。四种颜色方案的倍率为 Astra 自行设定。现有被修改模块的既有来源与许可归属继续适用。

### 2026-10-01：雨滴溅落粒子的颜色识别参考

`shaders/lib/rain_particles.glsl` 参考 Photon（SixthSurge / Benjamin Stott）的 `program/gbuffers_all_solid.fsh` 与 Hysteria（nvb-uy）的 `program/gbuffer/solid.glsl`：两者在粒子程序中识别蓝色溅落粒子并舍弃。Astra 采用该识别机制，自行编写雨量与摄像机条件、颜色判别函数，以及不透明/透明粒子入口接线；没有移植参考程序主体或素材。Photon 副本许可为 Photon Shaders License Agreement，Hysteria 副本为 AGNYA License Rev 1.3；参考副本路径及识别限制见 [现行实现说明](../docs/实现与限制.md)。

> 本地参考副本不随仓库提供。Steadfast 0.8.0 的获取位置、目录布局及替代路径参数见 [工具配置](../qa/tools/README.md#参考副本)。

依据 design.md §9.2 建立，**每新增一个来自参考包的文件/片段即登记**，保持台账与实际代码零偏差。
抽查方法：对表中每一行，打开对应文件核对文件头出处注释与内容来源。
Steadfast 借用行例外——其分类计数由 `python qa/tools/provenance_steadfast.py --quiet` 实算，
`python qa/tools/check_pack.py` 第 8 项把本文件出现的每一处计数与实算值比对，不一致即 FAIL。

参考包许可事实（design.md §9.1）：

| 包 | 版本 | 许可 | 借用政策（个人使用期） |
|---|---|---|---|
| Mellow | v3.4 | 根许可证 MIT（`Copyright (c) 2026 TheCMK`）**但包内逐文件中继第三方声明** | 自由，保留出处注释——注释必须是**该文件里实际声明的那个持有人**，不是包根持有人。2026-09-21 T16 实测：`lib/tonemap_operators.glsl:80-84` 内嵌 glsl-tone-map 的 MIT 原文（`Copyright (C) 2019 Damien Seguin`），同文件 `:23` 一行 URL 注释把 ACES 两矩阵与 `RRTAndODTFit`/`ACES_slow` 指向 **TheRealMJP/BakingLab**（该仓库 `LICENSE` = MIT / `Copyright (c) 2016 MJP`，`ACES.hlsl` 头部另把 fit 署名给 Stephen Hill `@self_shadow`），同文件 `:228-232` 把 `PBRNeutralToneMapping` 标为 **Apache-2.0 / Copyright (c) 2024 The Khronos Group**（根目录另附 `LICENSE-APACHE`），`global/post/cas.glsl:1-7` 是 AMD 自己的 MIT 头。详见下文 2026-09-21 T16 节 |
| Steadfast | 0.8.0 | GPLv3 + 两条 §7 附加条款（作者 coderbot） | 自由；文件头保留 GPL 声明。**7b**：任何传播 Steadfast 或其修改版的页面须在主文靠前处原样给出署名句（含 Modrinth/CurseForge/GitHub 三个下载源）。**7c/7e**：传播修改版时，人类可读名称与文件名必须以 `(edit of coderbot's Steadfast)` 结尾（文件名可用后缀 `-edit-of-coderbot-Steadfast`），且 "Steadfast" 不得出现在该括号之外的名称里 |
| Complementary | r5.9（Reimagined / Unbound，2026-09-02） | **Complementary License Agreement 1.7**（专有，非 GPL；`License.txt` 随包，1.2/1.3 节允许 modpack 收录与 Modified Pack 再分发但有条件） | 个人使用期自由；**发布前须按 design.md §9.3 / SC-14 重做发布门决策**。已在 `global/lighting/wind.glsl`、`global/lighting/sss.glsl`（树叶分支）、`global/atmosphere/{sky_gradient,stars,clouds_planar}.glsl`、`global/dimension/end.glsl`（方向门控）、`global/dimension/nether.glsl`（下界光照逐字移植）落地。登记日 2026-09-10 |
| Refrax | v1.3.1 | 保留所有权利 | 允许借鉴；结构级照抄须逐处登记 |
| Solas | V2.2b | 未声明（默认版权） | 同上 |

## 登记表

2026-10-06 主世界天空共享与阴影链处理：`lib/sky_gradient_cache.glsl` 的双角度坐标、257×257 同帧表及 prepare 调度由 Astra 编写；表内计算调用现有 `sky_gradient.glsl` 的 Complementary 衍生天空方程，原出处与许可继续适用，不将这些方程改记为 IDEA ONLY。根目录 `shadow_solid.vsh/fsh` 入口、`program/shadow.fsh` 的不透明专用分支与 `global/lighting/{shadowmap,diffuse}.glsl` 的接收面共享准备为 Astra 编写，原 Steadfast 及既有片段来源继续适用。没有新增参考包代码或素材。

2026-10-06 主世界云边缘与配色共享：`lib/cloud_sample_grid.glsl` 的子像素表复用 Astra 自有 `taa_jitter.glsl`，云网格偏移、历史坐标校准与消费滤波为 Astra 编写，没有新增上游代码或素材。`shaders.properties` 的云日夜／天气／亮度配色由现有 `clouds_planar.glsl` 中的 Complementary 衍生表达式移动而来，保持原出处与许可归属，不能因移到 CPU 求值而登记为 IDEA ONLY。

2026-09-27 空间抗锯齿与云影缓存：

- `shaders/global/post/fxaa.glsl` 改编自本地 Arc v0.15.2 `shaders/lib/fxaa_2.glsl` 的邻域边缘方向、双向端点搜索与亚像素偏移结构；根 `LICENSE` 的 MIT 全文及版权行存放在 `shaders/lib/vendor/arc/LICENSE.txt`，实际源码保留出处、SPDX 与许可路径。Astra 改用显示颜色 + alpha 亮度、限制边界坐标、只使用实际搜索到的端点、降低亚像素平滑权重，不移植 Arc 的 HDR/log 亮度或曝光恢复链。
- `program/display.fsh` 是 Astra 原 `program/final.fsh` 的场景组装与显示部分移动，原有来源继续适用；新增 `composite6` 薄入口、开关与 final AA 接线为 Astra 编写。
- `global/atmosphere/cloud_shadow_cache.glsl`、`program/cloud_shadow_cache.fsh`、根层 `prepare2` 借鉴 Refrax / Hysteria 预计算云影的思路，投影、网格锚点、边界过渡与 R16 存储均为 Astra 新写，没有复制它们的表达式。缓存的粗噪声场调用 Astra 已有 Complementary 派生云模块，来源声明沿用。

2026-09-27 可见云降分辨率：`program/cloud_screen.fsh`、`global/atmosphere/clouds_screen.glsl`、根层 `prepare1.vsh/fsh` 为 Astra 新写。参考包全景调研中的低分辨率云只提供思路，没有新增上游表达式；云模型继续使用现有 Complementary 派生模块。`clouds_planar.glsl` 抽出原来的层区间求交供合成复用；屏幕图的预乘表示、地形局部步进选择及天空 / 日月接线为 Astra 实现。

2026-09-26 首批 ITT 设计借鉴：

- `shaders/lib/nether_fog_density.glsl`：借鉴 ITT 3.2 按群系区分雾密度的思路；Astra 自定五组倍率与权重不足时的过渡，接入既有距离雾和 Bliss 体积雾。没有复制 ITT 表达式。
- `shaders/lib/wet_material.glsl`、`program/lit.vsh/fsh`、`block.properties`：借鉴材质湿润响应的分类思路；方块族、两位编码、暗化系数、有限直射光泽与积水分工均为 Astra 新写。
- `shaders/lib/sky_reflection_cache.glsl`、`program/sky_reflection_cache.fsh`、根层 `prepare.vsh/fsh` 与 `shaders.properties`：借鉴 ITT 的环境天空图供反射共用这一组织方式；258×128 布局、经度复制列、极点处理、生产/消费隔离和调度为 Astra 新写。
- 环境图调用现有 `sky_minishita.glsl`、`sky_gradient.glsl`、`clouds_planar.glsl` 和 `overworld.glsl`。其中 `sky_gradient.glsl`、`clouds_planar.glsl` 的 Complementary 来源声明继续适用；新增的缓存中点采样分支与反射入口替换为 Astra 代码，不代表原云模型改为自主来源。

| 模块路径 | 来源包（源文件） | 借用类型 | 许可 | 文件头标记 |
|---|---|---|---|---|
| `shaders/lib/tonemap.glsl` | **逐算子持有人（2026-09-21 T16 两次更正，原记"整文件 = Mellow (MIT) by TheCMK"不成立）**：**(1)** `uchimura_tonemap_full`/`uchimura_tonemap`/`agx_cdl`/`agx_punchy`/`agx_tonemap` 及其四张 AgX 矩阵 = 上游 **glsl-tone-map**（`Copyright (C) 2019 Damien Seguin`，MIT）逐字代码，经 Mellow v3.4 `lib/tonemap_operators.glsl:103-226` 中继（Mellow 在该文件 `:80-84` 原样保留 Seguin 的 MIT 声明，Astra 移植时丢掉了它——本轮已补）；**(2)** `aces_tonemap`/`rrt_and_odt_fit`/`aces_input_mat`/`aces_output_mat` = 上游 **BakingLab**（`TheRealMJP/BakingLab` 的 `BakingLab/ACES.hlsl`，仓库 `LICENSE` = MIT / `Copyright (c) 2016 MJP`，该文件头部另把此 fit 署名给 Stephen Hill `@self_shadow`），经 Mellow `lib/tonemap_operators.glsl:23-60` 中继——Mellow 在该处只留了一行 URL 注释而没登记持有人，Astra 保留了同一行注释也没登记，本轮已补；**(3)** 仅 `reinhard_jodie` 与 `apply_saturation/apply_vibrance/apply_contrast` 的持有人是 TheCMK：Mellow `lib/tonemap_operators.glsl:1-21`（`ACESFilm` 与 `reinhard_jodie`）与 `lib/tonemap.glsl`（grading 三函数在 `:21-37`）实测**不含任何** http / 版权 / 许可注释。`reinhard_jodie` 的算法本身公开（`https://64.github.io/tonemapping/`），Mellow 与 Astra 用的是 `get_luminance(v)` 变体，glsl-tone-map 那份 `reinhardJodie.glsl` 用 `const vec3 lw` + `dot`，两者不同源。Mellow 第 1 个算子 `ACESFilm`、第 5 个 `PBRNeutralToneMapping`（Khronos，Apache-2.0）与 `Lottes` **均未移植**，故本包不触发 Apache 条款 | 逐行移植（重命名为 snake_case；仅保留设计 §4.4 四算子）。来源比较入口：`qa/tools/verify_tonemap_chain.py`——去空白与行注释后按上游函数名逐字符比对，七个函数中，七参数uchimura在保留原权重和曲线表达式时加入T/S零贡献条件计算；五个未改编函数保留对应来源（uchimura 1 参 130、agxPunchy 57、agx 56、`rrt_and_odt_fit` 86、`aces_tonemap` 114，后两者在 HLSL→GLSL 机械翻译（`float3`→`vec3`、去 `f` 后缀、`mul(M,v)`→`M * v`、`saturate`→`clamp(…, 0, 1)`）之后与 BakingLab 原件逐字符相同），`agx_cdl` = 上游 612 字符 + Astra 自加的一处 `max(color * slope + offset, vec3(0.0))` 保护（分数次幂遇到负底数在 GLSL 里无定义，Mellow 与上游都没有这一处）；四张 AgX 矩阵 36 个值和两个 EV 常量、两张 ACES 矩阵 2×9 个值与上游逐值相同（HLSL 按行写、GLSL `mat3()` 按列写，实测为同一线性映射）；同脚本另测 Mellow 侧六个函数与两张 ACES 矩阵均等于上游（中继未改写；不代表Astra当前七参数uchimura仍逐字相同），唯一例外是 Mellow 的派发包装 `ACES_slow` 比 `ACESFitted` 多进出各一道 gamma（`pow(color, vec3(1/2.2))` 与 `to_linear(color)`），Astra 未继承该包装、直接对应 BakingLab 原件。两份上游原件随包在 `shaders/lib/vendor/glsl-tone-map/` 与 `shaders/lib/vendor/bakinglab/`。 | MIT（三个持有人：Damien Seguin 2019 段 + MJP 2016 段 + TheCMK 段） | 文件头 `// Immediate source: Mellow v3.4 by TheCMK (MIT)` + `Copyright (C) 2019 Damien Seguin, MIT` 与 `Copyright (c) 2016 MJP, MIT` 两段短注，分别指向 `lib/vendor/glsl-tone-map/LICENSE.md` 与 `lib/vendor/bakinglab/LICENSE.txt`（许可正文只在 vendor 目录一份，见 `shaders/lib/vendor/README.md` 反规范条） |
| `shaders/lib/encoding.glsl` | Mellow v3.4（`lib/util.glsl` 的 encodeUnitVector/decodeUnitVector/get_luminance、`lib/transformations.glsl` 的 to_linear） | 逐行移植（重命名）+ Astra 增补（srgb_encode/srgb_decode 为 IEC 标准式；pack_octahedral/unpack_octahedral/pack_u16 自写封装） | MIT | 文件头 `// From Mellow v3.4 (MIT) by TheCMK`。2026-09-21 T16 逐文件复核：所引的 `lib/util.glsl` 与 `lib/transformations.glsl` 内部**没有**任何第三方中继声明，持有人即 TheCMK，与被中继的 `lib/tonemap_operators.glsl` 不同 |
| `shaders/lib/transforms.glsl` | Mellow v3.4（`lib/transformations.glsl`） | 逐行移植（删除 DH 分支；Voxy 矩阵分支改由入口专属 ASTRA_VOXY_PASS 控制，SC-32）+ Astra共享投影眼点助手 | MIT | 文件头 `// From Mellow v3.4 (MIT) by TheCMK`。2026-09-21 T16 逐文件复核：本行所引的 Mellow 源文件（`lib/transformations.glsl`）内部**没有**任何第三方中继声明，持有人即 TheCMK，与被中继的 `lib/tonemap_operators.glsl` 不同 |
| `shaders/lib/pow.glsl` | 思路参考：Complementary r5.9 / Photon v1.3b / Refrax v1.3.1 / rethinking-voxels 的整数幂平方链助手（见文件头清单） | 仅思路（全部函数 Astra 自写并经 Python 逐点对拍） | 各参考包许可不动本文件；本文件随 Astra 主许可 | 文件头列明四家出处 |
| `shaders/global/lighting/blocklight.glsl` | Steadfast 0.8.0 diffuse.glsl 的手持光、方块光；Refrax v1.3.1 thunder.glsl 的闪电点光 | 表达式移植 / 改编，双来源 | 各段沿用来源许可，Refrax 段保留发布前重写标记 | 文件头列出两段来源及 REWRITE REQUIRED |
| `shaders/lib/colors.glsl` | Steadfast 0.8.0 shaders.properties 的方块光、最小环境光颜色；Refrax v1.3.1 thunder.glsl 的闪电色 | 双来源常量移植 | 各段沿用来源许可，Refrax 段保留发布前重写标记 | 文件头列出两段来源及 REWRITE REQUIRED |
| `shaders/lib/distort.glsl` | Steadfast 0.8.0（`lib/distort.glsl`，作者 coderbot） | 径向扭曲与 Z 缩放表达式移植；Astra 增补解析逆变换。2026-09-09 与 shadow_map_position 成套替换原 Mellow 方形扭曲，删除无调用的 compute_bias。**2026-09-20 改常数为按影距归一**：Steadfast 的裸 `0.20` 是其 160 格影距下的调参产物（核半径 = 因子 × 影距 = 32 格），Astra 出厂 256 格沿用会把高解析核推到 51.2 格、近场密度减半；现改为 `SHADOW_DISTORT_CORE = 25.6`（格）`/ float(SHADOW_DISTANCE)`，近场纹素密度与影距解耦，滑条只改变覆盖距离，代价是短影距下外圈空转面积增大（D=64 时 49.0%，D=256 时 17.4%，`shadowDistanceRenderMul = 1.5` 在上游侧部分利用该外圈）。为此新增本文件对 `lib/settings.glsl` 的显式 include——这是包内第一处 lib→settings 直接包含（其余 22 处全在 `shaders/program/` 入口，靠包含顺序拿到选项），settings.glsl 自带包含守卫，入口已包含时本行不重复展开，作用是让常量初始化式不隐式依赖包含顺序 | GPLv3 + §7 两条附加条款 | 文件头 GPL 来源说明 |
| `shaders/lib/dither.glsl` | Mellow v3.4（`lib/noise.glsl` 的 ign/dither） | 逐行移植（Astra 无 TAA，dither 固定为静态 IGN） | MIT | 文件头 `// From Mellow v3.4 (MIT) by TheCMK`。2026-09-21 T16 逐文件复核：本行所引的 Mellow 源文件（`lib/noise.glsl`）内部**没有**任何第三方中继声明，持有人即 TheCMK，与被中继的 `lib/tonemap_operators.glsl` 不同 |
| `shaders/lib/bayer.glsl` | 无参考（自写：教科书式 Bayer 递归构造，公共域模式） | 自写 | — | `// written for Astra` |
| `shaders/lib/vendor/arc/` | Arc v0.15.2 | FXAA 来源与许可隔离目录；实际改写在 `global/post/fxaa.glsl` | MIT | 目录 README 记录原文件与 Astra 适配 |
| `shaders/lib/vendor/arc/LICENSE.txt` | Arc v0.15.2 根 `LICENSE` | 保留 MIT 许可全文与 Copyright (c) 2022 Minecraft / Shaders | MIT | 许可正文集中存放，运行源码保留短出处 |
| `shaders/lib/vendor/musk-rose/` | Musk Rose Shaders 4.1（作者 Rin） | 环境 BRDF 来源与许可隔离目录；实际改写在 `lib/environment_brdf.glsl`（标量改编），本目录只存许可正文 | CC0-1.0 | 目录 README 记录历史来源与 Astra 适配边界 |
| `shaders/lib/vendor/musk-rose/LICENSE.txt` | Musk Rose Shaders 4.1 随附许可正文 | 保留 CC0 1.0 全文；该包许可本身不带要求保留的版权行 | CC0-1.0 | 许可正文集中存放，运行源码保留短出处 |
| `shaders/shaders.properties` 的 `CUSTOM UNIFORMS` 段 | Steadfast 0.8.0（coderbot）；其中 9 条 `astraSolas*` 改写自 Solas V2.2b 时间/日相表达式 | 表达式级移植；当前 200 个名称（68 `uniform.*` + 132 `variable.*`）：verbatim=12 literal-suffix=2 rewritten=6 astra-only=180。包含后来移至 CPU 的天空、云、水体、体积与群星表达式；分类范围和方法见下节 | Steadfast 部分：GPLv3 + §7 两条附加条款；Solas 部分沿用其来源登记 | 段内保留 Steadfast 表达式级移植说明；astra-only 仅表示 Steadfast 无同名定义，不代表没有其他来源 |
| `shaders/block.properties` 基础表（10001–10007、10021–10027） | Mellow v3.4（`block.properties` 现代分支） | 逐行移植（数据表；删除 floodfill 10020） | MIT | 文件头注明 |
| `shaders/item.properties` | 沿用 Astra 的 `block.properties` 材质分类，其中基础成员表来自 Mellow v3.4（TheCMK）；玻璃、冰、末地石与黑曜石沿用 Astra 分类 | 按物品注册名整理；省略仅方块存在的 ID 及依赖激活状态的发光体 | Mellow 来源数据沿用 MIT | 文件头说明来源与整理范围 |
| `shaders/block.properties` Astra 补全区（10010、10011，以及并入 10002/10004/10022/10025/10026/10027 的原版补漏 ID） | 无参考（自组：原版 1.21.x 事实 ID 数据） | 自写（2026-09-05 修正：block.properties 无 `+=` 追加运算符，原 6 条 `block.N+=` 行会整行替换基础表，已并入对应基础行） | — | 文件头注明 |
| `shaders/entity.properties` | Refrax v1.3.1 / Solas V2.2b 的 `entity.properties`（仅分类思路） | 结构借鉴（分组方案自组，ID 内容为原版事实数据） | Refrax：专有 / Solas：未声明 | 文件头注明 |
| `shaders/global/lighting/shadowmap.glsl` | Steadfast 0.8.0（`environment/lighting/shadowmap.glsl` 的 ShadowMapping/SampleShadows/静态回退、`program/world/lit.vsh` 的 ShadowMapPosition、`program/shadow/shadow.vsh` 的水面高度编码） | **表达式级移植**（snake_case 重命名；shadowMapResolution/shadowDistance/entityShadowDistanceMul/shadowHardwareFiltering 上移到 lib/settings.glsl 不在此重复；彩色阴影组合与焦散接口为 Astra 增补）。**2026-09-20 两处偏置与畸变常数解耦**：掠射项原借用 `SHADOW_DISTORT_FACTOR`（当时恰为 0.20 格），该常数已改为按影距归一后不再代表格数，故改用文件内 `shadowGrazingBias = 0.20`（出厂默认数值不变）；末地分支的固定 `+0.015` 格并入单一纹素倍率 `0.46`（= 原 0.30 加 0.015 格在 2048 档下的纹素数），使该项整体随 SHADOW_RESOLUTION 缩放而非部分冻结 | GPLv3 + §7 两条附加条款 | 文件头 GPL 声明 |
| `shaders/program/shadow.vsh` | Steadfast 0.8.0（`program/shadow/shadow.vsh`） | **表达式级移植**（block.properties 原始 ID 判据替代其 materialID 解码；玻璃剔除坐标由 `vec4(-1.0)` 修正为 `vec4(0,0,2,1)`——原写法落在远平面角上，裁剪不可靠） | GPLv3 + §7 两条附加条款 | 文件头 GPL 声明 |
| `shaders/program/shadow.fsh` | Steadfast 0.8.0（`program/shadow/shadow.fsh`）+ Solas V2.2b（`program/shadow.glsl` 的半透明染色混合思路） | **表达式级移植**（Steadfast 壳）+ 结构借鉴（Solas 染色公式）；`smoothstep(1.0, 0.9, a)` 透明度判定与 srgb_decode 为 Astra 组合 | Steadfast：GPLv3 + §7 / Solas：未声明 | 文件头 GPL 声明（Steadfast 部分） |
| `shaders/global/atmosphere/fog.glsl` | Steadfast 0.8.0（`environment/fog.glsl` 的 FogV2） | **表达式级移植**（雾色改为参数而非 custom uniform——Astra 的 Z3 uniform 集冻结于 SC-14，雾色归 D2/C1；FOG_DENSITY/UNDERWATER_FOG_DENSITY/SKY_FOG_STRENGTH 在此接入；空气透视与 biome tint 为 Astra 自实现，Refrax 仅思路） | GPLv3 + §7 两条附加条款 | 文件头 GPL 声明 |
| `shaders/global/lighting/wind.glsl` | **2026-09-10 换源：Complementary r5.9（`lib/materials/materialMethods/wavingBlocks.glsl` 的 GetRawWave:5-16 / GetWave:18-33 / DoWave_Leaves:52-67 / DoWave_Foliage:35-50）** — 换源前为 Steadfast 0.8.0（`environment/wind.glsl` 的 WindDisplacement + `program/world/lit.vsh` 的 WaveFoliage），现仅保留历史出处行，无 Steadfast 表达式残留 | **表达式级移植 / 形状级逐字**（两条波形、共享的 GetRawWave 与振幅链逐字照抄；材质无关化沿用 Astra 接线：materialID 判据改为调用方布尔参数；WAVING_FOLIAGE_STRENGTH 映射参考 WAVING_I、雨增益保留 Astra 自有 Steadfast 期响应） | **Complementary License 1.7（专有）** — 本文件已无 Steadfast 派生表达式，故不再适用 GPL 条款；文件头以「Historical provenance」段说明换源前后的关系 | 文件头含 Complementary r5.9 逐处 file:line 出处、`Historical provenance` 段与发布门提示 |
| `shaders/global/post/godrays.glsl` + `shaders/program/composite.fsh`（pass 体） | Steadfast 0.8.0（`program/post/noisy_godrays.fsh`） | **表达式级移植**（起步抖动换 Astra 自写 lib/bayer.glsl；`windowToScreenGodrays`/`screenLightVector` 两个 CPU uniform 改为 composite.vsh 顶点级投影，避免动 Z3 冻结的 uniform 集） | GPLv3 + §7 两条附加条款 | 文件头 GPL 声明 |
| `shaders/global/post/bloom.glsl` + `shaders/program/composite1.fsh`（pass 体） | 现行实现：Astra 自写；Refrax / MakeUp / Mellow 仅提供高亮筛选、低预算及 mip 组织思路（IDEA ONLY）。历史 Refrax 公式移植见下方 2026-09-05、10-01、10-02 记录，2026-10-05 已替换。 | 当前为自写积分激活曲线、中心加十二点圆盘高档核；既有自写低/均衡核、mip 加法权重及阶段接线保留。未移植 Ebin 或其他替代包代码。 | 当前代码随 Astra 主许可；历史 Refrax 专有归属保留追溯，原两处公式不再处于活动实现 | 文件头 `Original Astra HDR bloom` / `IDEA ONLY; no upstream filtering expression retained`，详见本文件 2026-10-05 增补 |
| `shaders/program/scattering.fsh` 的 `godrays_sun_visibility()` 与 `shaders/program/final.fsh` 的读回 | LIGHT Shaders 1.8.0（Chocapic13' 谱系）。思路出处按 2026-09-20 调研记录（§2.11、§6 P1-6）：`composite.fsh:423-433` 角落像素的日面深度遮挡探测 → `:582` 写入 alpha 广播 → `final.fsh:329` 读回乘到光束强度上。**这三处 file:line 抄自该调研，本轮未在本地重验**（原包目录已清理，`_analysis/study-2026-09-20/` 现仅剩 ComplementaryUnbound_r5.9.3）；本轮结论只依赖「有这种架构」这一条，不依赖具体行号 | **仅思路（IDEA ONLY）**：只取「一个像素做日面窗口探测 + 用 alpha 广播给后续 pass」这一架构。全部具体决定为 Astra 自写：7×7 抽、±12 像素半窗、深度源取 **depthtex1**（只用不透明深度，玻璃与水面不得误杀光束）、越界抽点不计入分母（与在窗抽点归一，而非按 0 计）、无在窗抽点时失败开放返回 1.0、载体复用 `colortex1` 的 texel (0,0) alpha（不新增缓冲、不新增 pass）、消费点为阶段 2 的一次 `texelFetch`。选项 `GODRAYS_SUN_OCCLUSION` 默认关闭，待实机 A/B | Chocapic13 Sharing Agreement（只读思路，不得照搬表达式） | 函数头注释 `Idea from Chocapic13' LIGHT (Sharing Agreement)` |
| `shaders/lib/settings.glsl` 的 ENGINE KNOBS 增补（entityShadowDistanceMul / shadowHardwareFiltering，SC-13） | Mellow v3.4（`lib/settings.glsl:268` 的 entityShadowDistanceMul 比例形式、`global/configurations.glsl:17` 的不带后缀 shadowHardwareFiltering） | 仅思路/形式参考（表达式为 Astra 写法；2026-09-20 起为 8×5 字面量表 `ENTITY/(SHADOW×1.5)`，见 lib/settings.glsl:230-326，规避 Iris 的算术解析限制） | MIT | 行内注释注明 |
| `shaders/program/composite.vsh` 的 lightScreenPos 投影 | 无参考（自写：gbufferProjection * vec4(lightVector, 0)，W=0 方向投影） | 自写 | — | `// written for Astra` |
| `shaders/global/lighting/diffuse.glsl` | Steadfast 0.8.0（`environment/lighting/diffuse.glsl`） | **表达式级移植**（Astra 改动：不复现 Steadfast 的 `SurfaceFragment` struct——GBuffer 解码归 E1；`lightVector`（视图空间、冻结集内）经 `lib/transforms.glsl view_player()` 重建世界向量；`NIGHT_DESATURATION_EFFECT` 不在 design.md 4.1 范围，已丢弃） | GPLv3 + §7 两条附加条款 | 文件头 GPL 派生声明（整段 derivative + GPL-3.0-or-later） |
| `shaders/global/lighting/sss.glsl` | **双来源（2026-09-10 起）**：树叶分支 = Complementary r5.9（`lib/lighting/mainLighting.glsl:111-113` 的 `NdotL = mix(NdotL, 1.0, 0.35)`，subsurfaceMode == 2，`:118` max0 自clamp）；地面植被分支与强度混合 = Steadfast 0.8.0（`environment/lighting/diffuse.glsl` 的前向散射包裹项） | **表达式级移植** + Astra 增补强度控制（Steadfast 无 SSS 滑条：`sss_wrap()` 以 plain Lambert 到全强度 wrap 的 mix 表达，100 即逐字等价、0 即关闭；与 B1 `shadow_mapping()` 的除数归一化不得重复施加。参考的平坦直射 NdotLM=1.0、前向高光与影缘天光混合三项需扩 diffuse.glsl 接口，见 docs/handoffs/terrain-foliage.md 待办 3） | 树叶分支：**Complementary License 1.7（专有）**；地面分支：GPLv3 + §7 两条附加条款 | 文件头双来源声明（含 Steadfast GPL 派生段） |
| `shaders/global/water/absorption.glsl` | 历史参考 Solas waterFog 与 Steadfast 吸收预设；当前距离输运与光谱参数由 Astra 编写 | 当前实现自写，历史改编记录保留 | 既有来源记录不变 | 文件头 Historical references 与 written for Astra |
| `shaders/global/water/caustics.glsl` + shadowcolor0 烘焙 | Solas V2.2b 水下界面法线与历史焦散；现行聚光借鉴 ITT 3.2 波面折射落点的思路 | Solas 法线保留；Astra 自写解析曲率与面积倒数，经阴影图供方块照明与体积光束共用；现行范围见 2026-10-03 三图反馈条目 | 既有 Solas 来源、噪声素材归属继续适用 | 文件头区分 Solas 法线和 Astra 聚光 |
| `shaders/global/water/refraction.glsl` | Steadfast 0.8.0 environment/water/refraction.glsl，coderbot | 改编 | GPL-3.0-or-later 与 §7 附加条款 | 文件头 Adapted from Steadfast |
| `shaders/global/water/particles.glsl` | 无参考（四包均无屏幕空间悬浮颗粒实现，检索命中的 particle 全为原版粒子 gbuffers 路径；观感对标 Solas 水下） | 自写（三层壳距 + 3D cell 整型 hash motes；hash 为公共域乘-移位模式，与 end.glsl 星野同构独立声明） | — | `// written for Astra (self-authored)` |
| `shaders/global/water/surface.glsl` | **Steadfast 0.8.0（`environment/water/surface_noise.glsl` + `surface_noise_waves.glsl` + `parallax.glsl` + `lib/valueNoise.glsl`/`valueNoiseDerivatives.glsl`）— SC-24 换源，2026-09-06 起由"自写解析波"改为 Steadfast 派生** | **表达式级移植**（ripple[4]+crest[2] 噪声波场、解析导数梯度、Nyquist 比率受限、4 步自适应视差；Astra 改动：两个噪声 lib 内联并加 `surface_` 前缀（与 Solas 出身的 caustics 同编译单元）；删 textureGather/FDM 回退分支；`WATER_AA` 四档固定 BALANCED；切线空间视线由 `worldPos - cameraPosition` 现算且 Z 取 -abs(y)；roughness = 被滤掉的坡度能量，为本包对 Steadfast 的增补） | GPLv3 + §7 两条附加条款 | 文件头 GPL 派生声明 |
| `shaders/global/dimension/nether.glsl` | Solas V2.2b（`lib/common.glsl` 的维度裁剪、其多云雾噪声塑形结构）+ Mellow v3.4（`lib/colors.glsl` 下界调色与 `global/lighting/lighting.glsl` 下界光照分支：思路与数值参考）+ **Complementary r5.9（2026-09-10 新增：`lib/lighting/mainLighting.glsl:506-519` 下界方向项与熔岩项、`:613-616` 平方和开方合成、`lib/colors/lightAndAmbientColors.glsl:80-81` 下界 ambient、`lib/lighting/minimumLighting.glsl:1-17` 暗部下限、`lib/common.glsl:811` netherColor 模式 2、`:815` lavaLightColor）** | 结构借鉴（Solas 在 voxel/LPV 光线步进内评估 cloudy fog，本包无体积体，故改逐片元评估，只借噪声塑形结构；Mellow 侧无表达式移植）；`NetherParams` struct 形参与 `fogColor` 需求为 Astra 自定；**2026-09-10 新增 Complementary 表达式级移植**（下界光照整段逐字照抄，含 `directionShade` 的二次平方；`vsBrightness` 因缺 uniform 以常量 0.5 顶替、`vanillaAO` 取 1.0，两项偏离已上报） | Solas：未声明 / Mellow：MIT / **Complementary：专有（License 1.7）** | `// PROVENANCE: adapted from Solas V2.2b (licence undeclared) - REWRITE REQUIRED before distribution` + Complementary 逐处 file:line 出处 |
| `shaders/global/dimension/end.glsl` | Mellow v3.4（`lib/colors.glsl:42,70,74,78,82` 调色数值；`global/atmosphere/sky.glsl:54-65,105-131` 星野与末地天空；`global/atmosphere/fog.glsl:37-50` 真空雾；`global/lighting/lighting.glsl:44-46,80-81,127` skylight 常量与阴影旁路）+ Solas V2.2b（`lib/atmosphere/skyEffects.glsl:6-27,48-91` 星野/星云结构）+ Refrax v1.3.1（`lib/atmosphere.glsl:174-209` 星野、`:390` 末地雾色、`:393-408` 末地天空）+ **Complementary r5.9（2026-09-10 新增：`lib/lighting/mainLighting.glsl:507-512` 末地方向门控、`:613` 的 `pow2(directionShade)` 门控、`lib/lighting/minimumLighting.glsl:2` 的 `#if !defined END` 暗部下限排除、`program/deferred1.glsl:386` 的 `1.0 - maxBlindnessDarkness` 天空压暗）** | 数值/思路参考（Mellow 调色与真空雾参数为其公开数值，表达式自写）；Solas 结构借鉴并降配（9 次查表降到 4 次、去掉螺旋域扭曲）；**Refrax 记为结构级**（雾色与天空地平线色同源、双正弦闪烁、立方面星野三项同源），Astra 侧已把星野重写为绕倾斜极旋转的 3D 晶格 + 天底立体投影、闪烁项改为权重与共轭相位形式，以脱离 Refrax 的表达式；**2026-09-10 新增 Complementary 表达式级移植**（方向门控与暗部下限为逐字移植，`sqrt` 折块光未移植、AO 通道缺失已上报） | Mellow：MIT / Solas：未声明 / Refrax：专有 / **Complementary：专有（License 1.7）** | `// PROVENANCE: rewritten for Astra - REWRITE REQUIRED before distribution`（Solas 条目下）+ Complementary 段 `REWRITE REQUIRED`（1.7 许可）+ 逐条 file:line 出处注释 |
| `shaders/global/post/grading.glsl` | Mellow v3.4（`program/final.fsh:56-76` 的 vibrance→saturation→contrast 链序与显示空间标定）+ Refrax v1.3.1（其 grade pass 的出厂数值区间与 film-look 思路） | 仅思路（链序沿用已移植的 `lib/tonemap.glsl` 中 Mellow 算子的调用次序；Refrax 侧明写 IDEA ONLY、无代码移植，并丢弃其内置 auto-warmth（§4.4 未要求））；四套预设参数为 Astra 自写出厂值，色调对标尚待用户目视确认 | Mellow：MIT / Refrax：专有 | 文件头两段 `PROVENANCE`（Refrax 段标 `IDEA ONLY, no code`） |

| `shaders/global/water/light_shafts.glsl` | Solas V2.2b volumetricLight.glsl 与 composite3/5，Septonious；现行积分结构另改编自 ITT 3.2 UnderwaterVolumetricFog.glsl | 保留 Solas 压缩域与既有来源；Astra 适配 ITT 短水段、相位、聚光对比与距离衰减，使用成对影图及四角重建；现行范围见 2026-10-03 三图反馈条目 | 既有来源归属继续适用 | 文件头分别说明 Solas 与 ITT |
| `shaders/program/scene.glsl`（2026-09-21 T14 新增 `CLOUD_SHADOWS` 地面云影臂） | BSL（`lib/lighting/shadows.glsl:295-374` 的 `GetCloudShadow()`：2D 云噪声沿光向投到地面，`:325` 的 `CLOUD_REVEAL` 再打孔洞透射）+ Complementary r5.9 Reimagined（`lib/lighting/cloudShadows.glsl:60` 的 `cloudSample *= sqrt3(1.0 - abs(EdotL))` 地平线衰减） | **仅思路、零表达式移植**：Astra 侧全部复用既有自有件——被追迹的密度场是 `global/atmosphere/weather.glsl:122-136` 的 `astra_cloud_transmission`（本包自写单平面追迹，每片元 2 次 `textureLod`），遮蔽门是 `global/lighting/shadowmap.glsl:239-241` 的 `static_shadow`，权重 0.75 与 `smoothstep(0.0, 0.2, cloudLightDir.y)` 衰减为 Astra 自写；BSL 的 `CLOUD_REVEAL` 透射与其噪声选择、Reimagined 的 `gaux4` 云阴影回读均未实现也未复制 | BSL：All Rights Reserved / Complementary：License 1.7（两者均专有）——本轮为思路级、无上游代码或公式进入本包，故条款不触发；若日后升级为表达式移植须走 `shaders/lib/vendor/` 流程 | 消费点行内 `PROVENANCE ... IDEA ONLY, no code and no formula transplanted`（格式同 `global/post/grading.glsl:234`） |
| `shaders/global/post/exposure.glsl`（2026-09-21 T15 新增 `AUTO_EXPOSURE`） | Refrax v1.3.1：`program/exposure.fsh.glsl:27-55` 的屏幕空间自动曝光结构（5×5 网格 + 高斯权重 + `log2` 几何均值 + `clamp(KEY/avgLum, MIN, MAX)` + texel 历史 + 变暗/变亮不对称速率）、`lib/post.glsl:9-18` 的 `sceneExposure()` 消费与下界/末地旁路（消费点 `program/grade.fsh.glsl:161-163`）、`lib/settings.glsl:91-98` 的常量形态 | **仅思路、零表达式移植**：Astra 侧全部自写——8×8 跨步 `texelFetch` 网格（弃 Refrax 的 `texture()` + `fract(uv*64.0)` 抖动：1 像素视口内导数无定义）、`exp(-abs(d)²·2.1)` 角点权重 0.35、逐抽 `AE_CLIP=4.0` 高光截断（Photon 建议的性质一）、有效性改用 `.a` 位（Refrax 的 `prev<=0.0` 会把触底增益误判为无历史）、混合在 `log2` 域做（线性域会让"变亮"永远滞后于"变暗"）、持久化 RGBA32F 历史保留微小增益变化，距目标约 0.51% 时吸附、水下冻结历史、常量全部为 Astra 自定（KEY 0.18 / MIN 0.60 / MAX 2.20 / FAST 2.5 / SLOW 0.5，均给出推导而非照抄 0.22/0.70/2.60/2.20/0.90）、载体为 `size.buffer.colortex10=1 1`（非 Refrax 的 `EXPOSURE_REGION`） | Refrax：专有（保留所有权利，允许借鉴；结构级照抄须逐处登记）——本轮为思路级、无上游代码或公式进入本包 | 文件头 `PROVENANCE ... IDEA ONLY, no code and no formula transplanted`（形态同 `global/post/grading.glsl`） |

## 第三方隔离目录 `shaders/lib/vendor/`

依据 design.md §9.2 与借鉴调研 P2-10 建立，规则正文在 `shaders/lib/vendor/README.md`。约定：

- 第三方原始文件与许可证原文只允许出现在 `shaders/lib/vendor/<upstream>/`，一个上游一个目录。
- 该目录下**除目录自带 README.md 外**的每个文件——许可证原文、上游原件、编译进包的上游模块——
  都要在本文件按它自己的全路径登记一行；目录本身由 `shaders/lib/vendor/<upstream>/` 一行覆盖。
- 每个上游目录必须带许可证原文；许可证正文只存这一份，包内其他文件出现 MIT/BSD/GPL 正文段落即 FAIL
  ——参照包同一个错误的代价：VanillaPlus 224 份文件头 = 4,384 行 / 38.5%，Sildur's 8.2%，LIGHT 11.3%。
- 本文件上方登记表登记的仍是**实际参与编译的 Astra 文件**；vendor 目录里的原件不重复登记为模块行。
- 机械检查：`python qa/tools/check_pack.py` 第 15 项。

## Steadfast 借用复核（机械可验证）

水下光束当前来源以本文件“现行水路来源”及文件头为准；下方SC-33及后续旧格式条目为历史归属，不描述当前世界光场。

- 复核命令：`python qa/tools/provenance_steadfast.py`（逐条比对 `Astra/shaders/shaders.properties`
  与 `_analysis/Steadfast-0.8.0/shaders/shaders.properties` 的 `uniform.*`/`variable.*` 定义；
  Steadfast 对同名保留多条历史定义，任一相同即计 verbatim）。
- 2026-10-04 当前源码分类：`verbatim=12 literal-suffix=2 rewritten=6 astra-only=180`，合计 **200** 个名称，68 个 `uniform.*` 与 132 个 `variable.*`。口径为当前属性文件内的所有自定义表达式名称，与 Steadfast 0.8.0 同名定义进行文本分类。
- **verbatim（12）**：sunVector、lightVector、worldSunVector、skyVisibilityDay、borderFogDistance、renderDistanceFogTweak、LdotF、clipLightVector、godraysBaseExposure、godraysExposure、godraysDayExposureMorning、godraysNightExposure。
- **literal-suffix（2）**：sunProgress、dayUnderwaterFogFade，仅幂指数的 `2`→`2.0` / `4`→`4.0` 后缀不同。
- **rewritten（6）**：atmosphereFogCoefficient、godraysDayExposureNoon、godraysMaxAngle、godraysOffscreenFade、godraysViewAngleFade、ndcLightVector。各自保留减弱雾系数、曝光／角度调整与夹取／分母防零等 Astra 改写。
- **astra-only（180）**：Steadfast 无同名定义。这里列举 astraHeldLightBase、astraBlocklightSuppression、astraHeldLightSuppression、九个 astraSolas* 时间／日相表达式、astraCloudNoonAmbient，以及后续天空、水体、群星等 CPU 共享表达式；完整名称以 `shaders/shaders.properties` 为准。这一类别只描述同名比较结果，不表示这些公式都由 Astra 原创；Solas、Complementary 等来源仍按登记表与文件头记录。
- 原 57 名称说明对应较早版本，已不能描述现有文件；报告中的 astra-only 数量也对应其审查时点。此次计数来自文本表达式分类，不包含运行画面或帧率结论。
- `astraSolas*` 的着色器声明在 `lib/solas_water.glsl`，其余声明按实际消费者所在 include 树查阅。
- 更正记录（2026-09-05）：本行原写"结构借鉴（表达式与分节模式，数值为 Astra 自定；
  worldSunVector 改锚定 sunPosition 而非 shadow light）"——两点均不成立：表达式为逐字复制，
  且 Steadfast 自己的 `worldSunVector` 已由 `sunVector`（= `sunPosition`/100）构造，与 Astra 逐字相同。

## 发布闸门提示（design.md §9.3）

- 上表中 Mellow 来源行（MIT）：公开发布仅须保留署名，无需重写。
- Steadfast 来源行（**表达式级移植**，40 条 custom uniform 表达式中 17 条逐字或近似逐字、7 条同名改写；另有 9 个 GLSL 文件为 Steadfast 代码派生，见下条范围更正）：发布前两选一——
  (a) 把这 24 条重写为 Astra 自有表达式；(b) 整包按 GPLv3 发布并满足 §7b 署名句。
  若按"Steadfast 修改版"传播，§7c/7e 还要求人类可读名称与文件名以 `(edit of coderbot's Steadfast)`
  结尾——Astra 现名不满足，故该项已上报（见 escalations.md SC-14），不在本档自决。
  个人使用期（不分发）不受上述发布条款约束。
- **范围更正（2026-09-05 登记；2026-09-06 SC-24 换源、2026-09-10 地形植被轮换源后两次更新）**：上面 (a) 只覆盖 `shaders.properties` 的 21 条表达式，不覆盖 GLSL 侧。`grep -rl "^// From Steadfast" shaders/` 现命中 **9 个文件**——`global/lighting/`（diffuse、sss、shadowmap）、`global/atmosphere/fog.glsl`、`global/post/godrays.glsl`、`global/water/surface.glsl`、`lib/distort.glsl`、`program/water.glsl`、`program/shadow.vsh`、`program/shadow.fsh`——它们与那 21 条同属 §7 条款的作用域。**名单已两次变动**：`global/water/` 的 absorption、caustics、refraction 经 SC-24 换源为 Solas 派生（11 → 9）；`global/lighting/wind.glsl` 经 2026-09-10 地形植被轮换源为 Complementary 派生、不再命中本 grep（同时 `lib/distort.glsl`、`program/water.glsl` 进入名单，故计数仍为 9）；`sss.glsl` 仍命中（地面植被分支为 Steadfast 派生），但其树叶分支已换为 Complementary。故 (a) 的真实工作量是「21 条表达式 + 9 个文件的表达重写」，(b) 则是整包转 GPLv3。SC-14 仍是 ⏸ 待用户拍板，本条只更正其影响面，不改候选与结论。
- **Complementary 来源行（新增，2026-09-10）**：`global/lighting/wind.glsl`、`global/lighting/sss.glsl`（树叶分支）、`global/atmosphere/{sky_gradient,stars,clouds_planar}.glsl`、`global/dimension/{end,nether}.glsl` 现为 Complementary r5.9 派生，许可为**专有**的 Complementary License Agreement 1.7（非 GPL、非 MIT）。发布前须与 (a)/(b) 一并决策——两个来源的条款要求不同（Complementary 允许 Modified Pack 再分发但有条件；Steadfast §7c/7e 另有改名要求），发布门需按最严者合并处理。登记日 2026-09-10。
- Refrax/Solas 来源行：`global/post/bloom.glsl`（B5，2026-09-05）已从"仅思路"升级为**公式级移植**
  （软阈值 + 13-tap 下采样），文件头已带 `// PROVENANCE: adapted from Refrax v1.3.1 (proprietary)
  - REWRITE REQUIRED before distribution`，**发布前须重写**（思路保留、表达自写）；其余行仍为
  结构借鉴/仅思路级别。Solas 侧现为**六行**：三行结构借鉴（`program/shadow.fsh` 的染色思路、`global/dimension/nether.glsl` 的 cloudy-fog 噪声塑形、`global/dimension/end.glsl` 的星野与星云查表结构）+ **三行表达式级移植（SC-24，2026-09-06）**——`global/water/` 的 absorption（waterFog）、caustics（waterCaustics）、refraction（composite4 REFRACTION 段），三文件头均带 `// From Solas V2.2b` + `REWRITE REQUIRED` 标记；若再升级为逐行移植，同样须加标记并在此更新。
- C 系列（C1..C6）2026-09-05 新登记的 8 行已进上表：5 行为 Steadfast 代码派生（GPL 面扩大），3 行为 Solas/Mellow/Refrax 的结构与思路级借鉴。`check_pack.py` 第 8 项现为 PASS（台账行数与带出处头的文件双向对齐）。

2026-09-25 更正：以上 SC-24 的三文件统一来源及头部标记描述仅记录当时状态。当前 absorption 为 Astra 距离输运实现，caustics 保留 Solas 水面高度场并采用独立解析聚焦场，refraction 改编自 Steadfast；light_shafts 改编自 Solas。blocklight 与 colors 的双来源已补入登记表。

## 2026-09-06 E1/E2 总成增量

| 模块 | 出处与变更 |
|---|---|
| program/lit.vsh、lit.fsh、scene.glsl、water.glsl、unlit.fsh、deferred.fsh、final.fsh | Astra自写组合逻辑；调用现有模块不改变其各自出处与许可。20对×3维度薄壳按E1表生成。 |
| global/water/surface.glsl | C7 SC-24 换源（2026-09-06）：Steadfast 噪声波场 + 解析导数 + 自适应视差，出处行见上表（GPL 派生，文件头带声明）。 |
| global/water/raytrace.glsl | SSR 基础设施，SC-24 明确不动；出处同原（屏幕射线，Khronos 语义参考）。 |
| global/atmosphere/sky_minishita.glsl、sky_gradient.glsl、stars.glsl、clouds_planar.glsl；global/dimension/overworld.glsl；program/sky.fsh、clouds.fsh | D2自写大气/星场/云与调用；Minishita使用固定2×1积分预算和公开散射公式。 |
| lib/tonemap.glsl | Z5执行E1线性输出契约修正；保留既有Mellow MIT出处。 |
| global/water/absorption.glsl、caustics.glsl、refraction.glsl、global/lighting/shadowmap.glsl、program/shadow.* | absorption/caustics/refraction 经 SC-24 换源为 **Solas 派生**（出处行见上表，2026-09-06）；shadowmap/shadow 为 Steadfast 派生，本次 C2/B1 修正深度单位、边界拒绝、足迹滤波、原点和摇曳同步，其原 Steadfast 派生说明继续适用。 |
| shaders.properties新增astraHeldLightBase/astraBlocklightSuppression/astraHeldLightSuppression | E1自写的CPU标量表达式，原28条借用分类不变；新增3条Astra独有，总计31条。 |

SC-14仍为未来发布的用户决策，不将本轮私人实例开发当作公开发布。

C5本轮仅根据本机Voxy 0.2.18-beta字节码确认空白配置跳过加载，voxy.json清空；未移植其代码或实现完整适配。

## SC-34-F1 来源与当前实现（2026-09-07）

本节及上表当前条目优先于 SC-24/33 历史实现描述。读取了本地三包：Steadfast 的 translucent/refraction/surface/lighting，Solas 的 gbuffers_water/composite4/waterFog/volumetricLight，Mellow 的 global/water 与 gbuffers_water/transformations。算法差异用于判断 Astra 接线，不移植参考包调色或增益。

| 模块 | 当前来源与变更 |
|---|---|
| `shaders/global/water/optics.glsl` | Astra 自写标准介电 Fresnel、Snell 入射光方向、归一化 HG 相函数；不是参考包表达式移植。 |
| `shaders/program/water.glsl` | 保留既有 Steadfast translucent 派生署名与 GPL/§7 说明；本轮重写物理界面、逐点颜色/深度传输、反射命中消费和折射天空重建。 |
| `shaders/global/water/raytrace.glsl` | Astra 自写 SSR；新增局部平面命中修正和几何约束，不复制参考包追踪器。 |
| `shaders/program/scene.glsl`、`shaders/global/water/light_shafts.glsl` | Astra 自写共享太阳源与分段积分；保留原 Solas 思路说明及依赖模块的来源。 |
| `shaders/global/lighting/diffuse.glsl`、`shaders/global/water/surface.glsl` | 保留 Steadfast 派生声明；分离 directRadiance、修正水面导数执行位置。 |
| `shaders/global/water/caustics.glsl`、`shaders/global/post/bloom.glsl` | 保留 Solas/Refrax 既有声明；焦散只作用于入水直射光，bloom 软阈值从既定阈值起算。 |

未改变既有私人实例开发范围；SC-14 不在本轮作发布决策。

## 2026-09-08 九图光路续修

重新对照本地 Mellow transformations、Steadfast shadow/translucent/absorption、Solas shadow/volumetricLight。lib/distort.glsl 的逆变换、shadow fragment 平面求交、阴影逐纹素照明合并、太阳源单位衔接和水面聚光场为 Astra 自写修改；原文件的 Mellow / Steadfast / Solas 历史出处与许可继续保留。

## 2026-09-08 最新六图退回后续修

`shaders/global/water/medium_state.glsl`、`shaders/program/water_state.fsh` 为 Astra 自写的界面高度编码与可见水面状态提取；`composite2.fsh/vsh` 为入口壳，`program/scattering.fsh` 承接原 composite 的散射实现及其已有依赖出处。太阳源、地形入水照明和焦散改为消费独立水体身份，遮挡仍读取 shadowtex1；未移植审查文档中的经验 glare 公式。吸收/散射参数仍是 Astra 自定，原 Steadfast/Solas/Mellow 衍生文件的许可声明保持。

## 2026-09-08 后续四图续修

依据本地 Iris/Sodium 顶点与矩阵输入纠正 shadow 坐标契约；保留 transforms 的 Mellow、shadow 的 Steadfast 出处。Astra 自写的界面透射谱与水下体积谱分离。`water_sun_focus` 是 Astra 的水面噪声聚光场，现同时供床面与光束使用；caustics.glsl 删除不再使用的 Solas 差分图案函数，保留其历史来源登记。原出处表中对旧差分图案的描述为历史记录，当前实现以本段为准。

## 2026-09-10 参考水面／水下依赖接入

本节为上述历史水光条目的当前实现补充。当前使用范围仍为用户授权的本地开发与实例。

| 文件 | 当前来源 |
|---|---|
| global/water/surface.glsl、refraction.glsl、absorption.glsl、program/water.glsl 空气侧 | Steadfast 0.8.0，coderbot，既有 GPL-3.0-or-later 及 Section 7 条款继续适用；恢复波场、视差、折射推进、吸收和 Fresnel 关系 |
| global/water/caustics.glsl、lib/solas_water.glsl、global/water/light_shafts.glsl | Solas V2.2b，Septonious；表达式级适配 waterNormals/waterCaustics、waterFog、lightColor、volumetricLight 及 composite3/4/5；现存天空光色与视线响应的来源归属保留，当前显示使用已登记的通用色调映射；不是仅思路借鉴 |
| program/shadow.fsh、global/lighting/diffuse.glsl、program/water.glsl 水下侧 | 在既有出处之上接入 Solas 焦散投射、环境／直射混合、界面法线与 Fresnel/alpha 组合 |
| textures/solas-water-noise.png 及 .mcmeta | 来自用户提供的 Solas V2.2b shaders/tex/noise.png 及其采样元数据（素材为用户提供的现成数据文件，非 Astra 自写代码）。**2026-09-21 B7 补登记（原行缺字节数与哈希）**：png **678019 字节**，sha256 前缀 **`9184f93b83f0ebb2`**，与本地 `_analysis/Solas Shader V2.2b/shaders/tex/noise.png` 逐字节相同（同目录 `latest-2026-09-10/solas-shader` 的那份是 636978 字节 / 前缀 `912e47e64b5b5ec6` 的另一构建，**不**匹配，勿引错）；该 png 是唯一带 iTXt/iCCP/pHYs 的文件，内嵌 XMP 显示其为 Affinity Photo 1.8.2 于 2020-09-20 产出、标题 `noisetex` 的既有美术资产。.mcmeta **67 字节**，sha256 前缀 **`e9c800d49d941e58`** |
| textures/steadfast-water-noise.png 及 .mcmeta | 64×64 RGBA8（4096 个像素的 alpha 恒为 255，每通道满量程、std≈74），线性重复采样，以匹配 Steadfast 的 noiseTextureResolution=64。**2026-09-21 B7 就地更正——原写「按当前 Iris 1.11.2 的 NativeImageBackedNoiseTexture 所用 Java Random(0) 填充规则生成」已被实测推翻**：Iris 侧 `NoiseTexture.generateNoise()` 是每像素 3 字节的 `byte[3*w*h]`，由**一次** `new java.util.Random(0L).nextBytes()` 填满，再经 `texImage2D(…, 32849=GL_RGB8, 6407=GL_RGB, …)` 直接上传 GPU，**从不编码 PNG**（反编译件 `_analysis/astra-sc34/NoiseTexture.txt`；该件里的类名是 `net.irisshaders.iris.targets.backed.NoiseTexture`，与旧登记所写的 `NativeImageBackedNoiseTexture` 也对不上）；而本文件的像素在任何测试过的排列下都无法由 `Random(0)` 复现（只有第 0 个像素在 R/B 互换下「相等」，第 1 个像素即分岔；首 64 字节在 4 MB 的 `Random(0)` nextBytes 流中零命中；py `random`/numpy 的其余 seed-0 RNG 亦不符）。**确实成立的只有编码器**：用 Pillow 默认档 `compress_level=6` 从本文件自身的像素重存，可逐字节复现 **14561 字节**、sha256 前缀 **`b9502f10ec238b90`**（`compress_level` 2–5 输出同长度但另一哈希，7–9 为 14557 字节）。**结论：本文件的像素来源在仓库内无法复算**——既不能证明它是第三方美术资产，也不能证明是 Astra 自生成，`qa/tools/` 内也没有任何工具能重算它（`provenance_steadfast.py` 只分类表达式文本，不读 png）。**处置方向待用户裁定：重生成、替换还是保留，本条一律不决定**，与 16.4 里三条美术资产同归 SC-14 发布门。.mcmeta **67 字节**，sha256 前缀 **`e9c800d49d941e58`**（与 solas 那份逐字节相同） **2026-09-21 卡 D 追加：与 Steadfast 发行包的字节级比对**（本轮实测）——对 `Steadfast-0.8.0.zip` 的**全部 122 个成员**逐一取值比对：**包内不含任何图片文件**（`.png/.jpg/.jpeg` 计数为 **0**），也不存在与本 PNG 字节相同的成员（探针输出 `byte-identical members anywhere in the zip: NONE`）；本地解包树 `_analysis/Steadfast-0.8.0/` 同样 **0 个图片与 .mcmeta**、无字节孪生件。因此「本文件取自 Steadfast 的噪声纹理」这一**命名假设在字节层未获证实**：既不能确认逐字节复制（也就无从据其登记许可证），也不能据此否认；文件名与 64×64（`noiseTextureResolution=64`）只是**命名与规格**上的印证。**本轮未替换、未重生成任何纹理**，处置方向仍待用户裁定。（本行第 195 行；同一发现也解释了为何 16.4 的「三条逐字节复制的第三方 png」清单里没有本文件） **2026-09-21 E 轮追加：用户裁定「重生成」，纹理已替换**——新增 `qa/tools/regenerate_steadfast_noise.py`，以进程内 splitmix64（SEED=20260921，每像素 3 次抽取、各通道取低字节，alpha 恒 255）填 64×64 RGBA8，Pillow 默认档 `compress_level=6` 编码：**新 png 14517 字节，sha256 前缀 `181f0d9779e136e2`**（旧 14561 字节 / `b9502f10ec238b90` 只存于 git 历史，其无法复算的来源争议就此封存）。采样规格与 `.mcmeta`（67 字节，`e9c800d49d941e58`）不变；本行出处登记随之改写为：**Astra 自生成（2026-09-21 起按上列生成器可复算），无第三方出处，不占 16.4 美术资产清单**，SC-14 就本文件而言已闭合，其余三条美术资产仍留发布门 |
| shaders.properties | 接入并加前缀的 Solas 时间表达式，以及两组独立纹理绑定 |
| program/lit.vsh、lit.fsh、scene.glsl、scattering.fsh、final.fsh | **自写**（Astra 管线适配/组合层，非借用行）：调用及组合以上对应来源，仍保留 Astra 的 SSR、天空、局部光和部分后处理。本行的出处由被调用的各模块行各自登记，此处不重复登记 |

具体已接入与仍有差异的模块见该轮详情记录（历史报告已于 2026-09-26 清理，可在 git 历史查阅）；不得把本轮表达式移植描述为完整包逐像素复现。


### 2026-09-10 水体入射光、反射与合成补齐

- `shaders/global/water/reference_light.glsl` adapted from Steadfast 0.8.0 `environment/sky/minishita.glsl` and the matching `shaders.properties` atmospheric/light expressions. Prefix and water-path integration changes by Astra; retains Steadfast GPL-3.0-or-later and additional Section 7 terms already recorded above. **[2026-09-21 B3 已删除该文件]**：159 行、19 个 `waterRef_*` 与 `water_reference_lighting()`经全包扫描零调用（唯一提及是 `program/scene.glsl` 的 include），文件与其 include 一并删除；本条登记作为历史移植事实保留。
- `shaders/lib/solas_water.glsl` additionally adapts Solas V2.2b `lib/atmosphere/sky.glsl` and the default minimum-light constants.
- `shaders/global/water/bloom_capture.glsl` and `bloom_resolve.glsl` adapt Solas V2.2b `lib/post/computeBloom.glsl` and `getBloom.glsl`, retaining tile layout, sample weights, encoding and blend equations; sampler names and default option expressions adapted. Solas attribution and license treatment remain as recorded above.
- `program/water_composite.fsh` and `program/water_bloom.fsh` integrate those reference operations into Astra pass order.

- `shaders/textures/complementary-cloud-water.png`: Complementary r5.9 Reimagined `lib/textures/cloud-water.png`, retained unmodified for the ported cloud sampler; same Complementary attribution and license terms recorded above. **2026-09-21 B7 补登记（原行缺字节数与哈希）**：**128888 字节**，sha256 前缀 **`49174f769c70f0d1`**，与本地三个 Complementary 副本逐字节相同（r5.9 Reimagined、r5.9 Unbound、`study-2026-09-20/ComplementaryUnbound_r5.9.3`）；256×256 RGBA8，无 `.mcmeta`。

### 2026-09-10 维度与天气重做

- `global/dimension/end.glsl`：适配 Solas V2.2b `lib/atmosphere/skyEffects.glsl` 星分布与星云、`common.glsl` 末地配色、`fog.glsl` 远雾、`gbuffersLighting.glsl` 阴影混合。恒星圆盘、全屏接入与提亮响应由 Astra 实现；无末地大气云。
- `global/dimension/nether.glsl` 与群系 uniforms：Complementary r5.9 `lib/common.glsl` NETHER_COLOR_MODE 3 配色及 `shaders.properties` 群系识别模式，保留既有参考照明。删除 Astra 旧端点噪声雾。
- `global/atmosphere/weather.glsl`：积水的湿度/天光/向上法线/双层纹理因子参考 Solas `lib/pbr/generatedPBR.glsl`；阈值、圆环法线、云透射及管线组合由 Astra 实现。
- `program/lit.fsh` 雨滴形状、`program/deferred.fsh` 积水射线和雨雾散射为 Astra 实现，使用上列参考模块提供的天空/噪声。上述参考的授权说明沿用本文件已有登记。

### 2026-09-10 下界体积光与体积雾（N2/N3）

- `shaders/global/dimension/nether_volume.glsl`：适配 X0nk Bliss Stable `lib/nether_fog.glsl`（沿程 16 步积分、Plumes/floorPlumes/Erosion/Roof 与 Floor 高度衰减结构、haze/ceiling smoke 三段合成）。Astra 侧改动：加入 `ASTRA_NETHER_PLUME_SCALE`/`ASTRA_NETHER_HAZE_SCALE`/`ASTRA_NETHER_CEILING_SCALE` 三个密度标度，并按 Astra 的单次散射合成约定重写注释；采样步数、积分长度与参考不同（Astra 为 16 步、`borderFogDistance` 与 12×16 取小），不是逐像素复现。
- `shaders/textures/bliss-nether-noise.png`：Bliss Stable `shaders/texture/noises.png` 原文件复制，未修改（sha256 前缀 `77d1aa0c2195a4f6`，512×512 RGBA8 与源一致）。Bliss 用 `texture.noise = texture/noises.png` 的自动绑定；Astra 因 `noisetex` 已占用为自有的 256×256 噪声，改用 `customTexture.blissNetherNoise` 独立绑定，因此**采样过滤/包裹参数与参考不同**（Astra 为 Iris 自定义纹理默认值），这是已知保真差异。
- `shaders/program/nether_light.csh`、`shaders/global/dimension/nether_colored_light.glsl`、`shaders/world-1/shadowcomp{,A..H}.csh`、`shaders/program/shadow.vsh` 的下界体积光写入：架构参照 Solas V3.7b（`lib/vx/voxelization.glsl`、`programs/shadowcomp.glsl`、`shadow.glsl` 的 `voxel_img` 体素化与空单元传播模式），但**不是 Solas 实现的移植**：Astra 是自写的受限子集——64³ 体积、玩家周围约 32 格、同帧 8 步传播、无跨帧历史、无 LPV 照明、无 128+ 体积档位；占用/光源编码（bit 8 固体、bit 16 帧戳）、逐帧失效与边界淡出由 Astra 自行设计。Solas 的许可证状态与既有登记一致。
- `shaders/program/shadow.vsh` 的 `imageAtomicMax` 写入与 `shaders/program/nether_light.csh` 的传播：Astra 自写。
- `shaders/global/dimension/nether.glsl` 的 `astra_nether_colored_light` 消费点与 `program/scene.glsl` 的体积雾合成：Astra 自写。

### 2026-09-11 末地空间交会接续：当前实现说明

当前 `end_blackhole.glsl` 的 `bh_Blackbody` **已替换为自写实现**（2026-09-23 更新）：现为
`astra_blackbody_rgb`，直接在 610/545/465 nm 三个波长采样普朗克定律并按峰值归一。
为降低星点与盘面的逐像素开销，先前每个响应带的三点积分改为单点采样，每次调用共三个指数运算；
唯一物理常数为 `c2 = hc/k`，不含任何 CIE 拟合样条、色度矩阵或
参考常量表，职责仍是黑体温度→RGB。本包因此不再持有 IterationT 的 `Blackbody` 表达式。旧文件里的
WarpSpace、旋转矩阵、纹理噪声、FBM、pcurve、IGN 等未被当前渲染路径使用的移植函数此前已移除；
不能再用下方历史记录的“四处适配”概括现有实现。

本次 `end_geometry.glsl`、`end_system.glsl`、`program/end_illumination.fsh` 的虚拟轨道、实体距离场、消光、求交和每帧可见性计算，以及 `end_blackhole.glsl` / `end_kerr.glsl` 当前解析透镜映射、盘面采样与光子环，为 Astra 在本任务中的代码实现。没有新增第三方贴图、模型或音频。现有后处理文件的原始来源不因增加末地专属分支而改变。

### 2026-09-23 末地巨型黑洞：连续光路与流体纹理

`textures/astra-end-transfer.png`、`textures/astra-end-transfer-meta.png` 与
`textures/astra-end-flow.png` 均由 Astra 自写的 `qa/tools/build_end_transfer.py` 生成：
依次存储中心引力近似下光线与有限厚度盘面的两次进入坐标、局部出射方向与上下表面标记、
周期多尺度随机场。共享盘面形状位于 `end_disc_profile.glsl`；`end_plasma.glsl` 的热冕/盘风
与喷流结构、`end_kerr.glsl` 的频移/热点/通量实现均为本任务自写。参考截图仅用于外观方向，
没有复制其中图像像素，也没有引入第三方
贴图或预计算数据库。运行时保留明确的 Kerr 视觉近似，不将中心引力积分宣称为完整 Kerr 解。

### 2026-09-11 末地黑洞与星空：移植 IterationT 3.2.0（历史实现）

- `shaders/global/dimension/end_blackhole.glsl`：**移植**（非思路借鉴）IterationT 3.2.0
  `shaders/Lib/IndividualFounctions/EndSky.glsl`（`CalculateStars`、`WarpSpace`、
  `RotateMatrix`、`Calculate3DNoise`、`CalculateCloudFBM`、`pcurve`、
  `BlackHole_AccretionDisc_Stars`）与 `shaders/Lib/Utilities.glsl`（`Blackbody`、
  `MiePhaseFunction`、`InterleavedGradientNoise`、`curve`/`saturate`/`remapSaturate`）。
  来源见 `_analysis/latest-2026-09-10/iterationT-3.2.0`（`sources.json` 同目录登记）。
  口径：**表达式级移植**——步进循环、密度场、Blackbody 色温、环面光子环均为参考原式；
  Astra 侧改编只有四处，均已在文件内逐条标注：（**2026-09-22 就地更正**：其中 `Blackbody` 色温
  一项已**替换为自写实现** `astra_blackbody_rgb`，其余三项与“步进循环/密度场”经 2026-09-11 接续
  重写后也已不是参考原式；本条只作历史记录）
  1. `noisetex` 采样改用 Astra 的 `noiseTextureResolution`（Astra 为 256，参考为 64）；
  2. `BlueNoiseTemproal()`（TAA 查询）改为参考同样提供的 `InterleavedGradientNoise`；
  3. `worldShadowVector` 改由 `end.glsl` 传入末地恒星方向；
  4. 新增 `ASTRA_END_STAR_GAIN`（=3.0）补偿 Astra 不同的曝光/tonemap 链，参考取值为 1.0。
- 授权：IterationT 归档内**不含任何许可文件**，按专有处理，与本文件既有的 Refrax 条目同级——
  仅限当前个人使用定位；发布前必须整段重写或取得授权（design.md 9.3 发布闸门）。
- 历史说明：本文件此前登记的 `end.glsl` 手写解析式黑洞已**整段移除**，改为调用上述移植模块；
  被移除的实现连同两次失败记录保留在历史交接记录（2026-09-26 已清理，可在 git 历史查阅）
  与 `qa/session-log.md` 中，供追溯。
- `shaders/program/lit.fsh` 的像素端焦散增量为 Astra 自写（见该处注释），用于在水面之上
  接收、阴影贴图投射路径无法实机验证时保证焦散仍然可见；Solas 的写入端口径仍保留在
  `program/shadow.fsh`。**2026-09-22 更正**：该增量现在只服务**水面之上**的接收点——
  水下由 `program/shadow.fsh` 烘进水面 caster 染色（Solas 口径）的那一份单独承担，避免在
  水下把相位相差一个水柱深度的两张图案相乘（见该处头注与 261 节）。

### 2026-09-11 水下焦散与光束：移植 IterationT 3.2.0

- **2026-09-22 就地更正：本条原登记的表达式已全部删除，不再是"在包"实现。**
  `shaders/global/water/caustics.glsl` 的 `astra_water_caustics_focus` 与
  `astra_water_caustics_shaft_at`（原登记为 IterationT 3.2.0
  `Lib/BasicFounctions/Sunlight_Shadow.glsl::CalculateWaterCaustics` 与
  `Lib/IndividualFounctions/UnderwaterVolumetricFog.glsl::CalculateWaterCaustics`
  的表达式级移植）已随 2026-09-22 四症轮**整段删除**，其唯一消费者
  `program/lit.fsh` 的水下焦散项改为直接求 Solas 派生的 `solas_water_caustics()`。
  因此 `global/water/caustics.glsl` 当前**只保留 Solas V2.2b 的双层漂移噪声高度场**
  （见上方第 46/192 行与本文件 2026-09-10 节），文件头
  `Adapted from Solas V2.2b lib/water/waterCaustics.glsl by Septonious`
  与该登记自洽：IterationT 相关表达式在本包内的在包计数**归零**。删除原因与实测
  （focus 场 92.3% 落在自身 0.2 clamp 地板上、退化为平底 0.44 乘子、无亮斑）
  见 `global/water/caustics.glsl` 头注与 `qa/underwater-light-*.log`。
- （以下为历史记录，已不适用）原登记的实现：三点法求波面法线、折射竖直光线、
  以落点与接收点的距离作为聚焦量，九抽头求和；Astra 适配三处并已在文件内标注——
  ① 参考从自维护的波法线缓冲读取，Astra 改由同一份 Solas 高度场中心差分求法线；
  ② 太阳方向改用 Astra 的 `lightVector`；③ 空间抖动替代参考的时间蓝噪声（Astra 无
  TAA，逐帧抖动会闪）。坡度尺度 0.75 为对真实噪声纹理的离线标定值，不是参考常数。
- **资产边界（2026-09-11 修正）**：首次引入涟漪贴图时曾直接复制参考的
  `RippleAnimation1/2/3.png`。用户明确指出**不得挪用参考的图像资产**，已全部删除。
  现在 `shaders/textures/astra-ripple-1..3.png` 由
  `qa/tools/gen_rain_ripple.py` **自行生成**（显式物理模型：扩散并衰减的圆形波包，
  求梯度得到法线图），与参考资产无关。
  **2026-09-21 B7 补登记（原行只有一个 glob 文件名，无字节数、无哈希，是登记最薄的一组）**：
  三张均为 128×7680 RGBA8（128×128 瓦片 × 60 帧竖排），分别 **287512 / 556938 / 848759 字节**，
  sha256 前缀 **`33a5cfacf7424d69` / `1f35d37fe8b6d181` / `969ed94d92eaf53b`**。
  该脚本以 seed 101/202/303 驱动 numpy PCG64（不是 `java.util.Random`），其逻辑按内存重放
  （输出到 BytesIO、不写盘）可从脚本逐字节复现上述三组哈希，是包内唯一有完整工具留痕的 PNG；
  另注 `astra-ripple-3.png` 没有任何 `customTexture` 绑定（只有 1/2 被 `shaders.properties` 引到）。
  边界原则：**代码级移植按专有处理并登记；图像/音频等美术资产一律不得取用。**
- `shaders/global/water/light_shafts.glsl`：**历史实现，现已由 Solas 改编版本替换**。当时结构移植参考的
  `UnderwaterVolumetricFog`——`caustics³` 调制、`1/max(3, d*0.1)` 距离衰减、
  折射太阳方向的相函数、起始采样点远离相机。步进距离改为沿射线真实距离。
- 授权：IterationT 归档无许可文件，按专有处理，与本文件既有的 Refrax 条目同级，
  仅限当前个人使用定位；发布前必须重写或取得授权。


### 2026-09-11 下界与性能接续

- nether.glsl 的群系色/环境色继续来源于 Complementary r5.9；雾取消独立颜色解码，保持与环境照明的输入一致。
- 方块光组合参考 Solas 3.7b lib/lighting/gbuffersLighting.glsl 的体素替换、独立手持光和自发光排除；0.95 混合上限沿参考，按实际体素亮度渐入是 Astra 八格传播范围的适配。
- nether_volume.glsl 继续为 Bliss nether_fog.glsl 派生。指数样点递推是同一表达式的代数改写；顶层烟雾色改为 Complementary 群系色。
- nether_light.csh 参考 Solas shadowcomp 的直接邻居光场读取；Astra 保留同帧 max 传播，不引入 Solas 时间历史。非发光实体输出恒零使邻居材质读取冗余。
- Steadfast/Mellow/ITT 本轮只用于性能结构对照，没有新增三者的表达式移植。既有来源与授权要求继续适用。

### 2026-09-13 晨昏光照联动
参考 Complementary r5.9 lightAndAmbientColors、mainLighting 的包裹法线响应、skyColors、mainFog、Unbound 云层密度结构及 reflectionBackground。Astra 的晨昏线性光色、方向天空目标、两次采样的云反射近似和距离收敛参数为适配实现。原有 Complementary 来源登记继续适用；未新增参考图像资产。详细路径见该轮登记记录（历史报告已于 2026-09-26 清理，可在 git 历史查阅）。

### 2026-09-21 T16 · P2-13「MIT 可署名复用清单」

**本条的实际产物不是清单，而是逐文件权属（chain-of-title）审计。** 调研 §7 给 P2-13 的前提「MIT ⇒ 本次唯一能直接搬的部分」不成立：一个包的根许可证不是包内任一份文件的持有人。实测——Mellow v3.4 根许可 MIT／`Copyright (c) 2026 TheCMK`，但 `lib/tonemap_operators.glsl`（253 行）里 Astra 在用的两个算子块都是中继：`:80-84` 原样保留了 glsl-tone-map 的 MIT 原文（`Copyright (C) 2019 Damien Seguin`）覆盖 `:86-226`（`Lottes`、`Uchimura`、AgX），`:23` 只有一行指向 BakingLab 的裸 URL 注释覆盖 `:23-60`（`RRTAndODTFit`、`ACES_slow`），`:228-232` 是 Khronos 的 Apache-2.0 原文覆盖 `:233` 的 `PBRNeutralToneMapping`。Astra 移植时把 Seguin 那段丢了，又原样继承了 BakingLab 那行「只有 URL、没有持有人」。本轮补齐两段，并按 `check_pack.py` 第 15 项把两份上游原件与其许可证归档进 `shaders/lib/vendor/`。同一审计方法对包内每一行借用有效，不只对 MIT 有效。

#### 16.1 `lib/vendor/` 逐路径登记（第 15 项要求，共 11 个文件／2 个上游目录）

| 路径 | 上游（源文件） | 在 Astra 里的角色 | 许可 |
|---|---|---|---|
| `shaders/lib/vendor/README.md` | 无参考（Astra 自写：目录约定与反规范条——许可正文每上游只存一份，禁止逐文件复制） | 第 15 项要求的约定文档 | — |
| `shaders/lib/vendor/glsl-tone-map/README.md` | 无参考（Astra 自写：取件 URL、tarball 摘要、六文件作用表、复算命令） | 本目录自述 | — |
| `shaders/lib/vendor/glsl-tone-map/LICENSE.md` | glsl-tone-map 2.3.1（npm `glsl-tone-map@2.3.1`，仓库 `dmnsgn/shaders-tone-map`）根 `LICENSE.md`，1057 字节，sha256 前缀 `84cc14c5d563a1ce` | 本目录全部上游文件的许可原文（唯一一份） | MIT／`Copyright (C) 2019 Damien Seguin` |
| `shaders/lib/vendor/glsl-tone-map/uchimura.glsl.orig` | 同上包 `uchimura.glsl`，1924 字节，sha256 前缀 `bc1d1dc6cd239cf8` | `lib/tonemap.glsl` 的 `uchimura_tonemap_full`／`uchimura_tonemap` 原件 | MIT（Seguin） |
| `shaders/lib/vendor/glsl-tone-map/agx.glsl.orig` | 同上包 `agx.glsl`，3772 字节，sha256 前缀 `a6f456911665c606` | `agx_cdl`／`agx_punchy`／`agx_tonemap`、AgX 常数与四张 inset/outset 矩阵原件 | MIT（Seguin） |
| `shaders/lib/vendor/glsl-tone-map/aces.glsl.orig` | 同上包 `aces.glsl`，508 字节，sha256 前缀 `9dba1fa9b194efe1` | **未移植**（Narkowicz 亮度曲线版 ACES）。留档为权属判别式旁证：`vec3 aces(vec3 x)` 与 `const float a = 2.51;` 两个串在 `lib/tonemap.glsl` 命中 0 | MIT（Seguin） |
| `shaders/lib/vendor/glsl-tone-map/acesHill.glsl.orig` | 同上包 `acesHill.glsl`，931 字节，sha256 前缀 `9f2ceac42f38b38e` | **未移植**（Seguin 对同一份 BakingLab fit 的 GLSL 移植，与 `aces.glsl` 数值近乎相同而注释不同）。留档为旁证：其独有注释在 `lib/tonemap.glsl` 命中 0／2 | MIT（Seguin） |
| `shaders/lib/vendor/glsl-tone-map/reinhardJodie.glsl.orig` | 同上包 `reinhardJodie.glsl`，449 字节，sha256 前缀 `9a05daa3fe1c88cc` | **未移植**。Astra 的 `reinhard_jodie` 是 TheCMK 变体（`get_luminance(v)`，Rec.601 权重），上游这份用 `const vec3 lw` + `dot`（Rec.709）。判别串 `reinhardJodie`／`dot(x, lw)` 在 `lib/tonemap.glsl` 命中 0 | MIT（Seguin） |
| `shaders/lib/vendor/bakinglab/README.md` | 无参考（Astra 自写：jsDelivr 取件 URL 与两条完整 sha256、同日复抓一致的记录、HLSL→GLSL 机械转写清单、Mellow 中继说明） | 本目录自述 | — |
| `shaders/lib/vendor/bakinglab/ACES.hlsl.orig` | `TheRealMJP/BakingLab` 的 `BakingLab/ACES.hlsl`，1322 字节，sha256 `0dab4dbfbd748dd4d6a3f38cef00155cfa4ffb5f6a8dddf4b3368aff52e4b23f` | `aces_input_mat`／`aces_output_mat`／`rrt_and_odt_fit`／`aces_tonemap` 原件（HLSL，`.orig` 后缀使其不进编译与静态检查） | MIT（`Copyright (c) 2016 MJP`，文件内把该 fit 署名给 Stephen Hill `@self_shadow`） |
| `shaders/lib/vendor/bakinglab/LICENSE.txt` | 同上仓库根 `LICENSE`，1060 字节，sha256 `751878625007bd944c6f0b8b43e1bbdf47da639975d49c358832043a31f1f3e8` | 本目录许可原文 | MIT |

`shaders/lib/vendor/glsl-tone-map/` 与 `shaders/lib/vendor/bakinglab/` 两个目录行同时覆盖各自 `README.md`（第 15 项的目录 README 例外）。`.orig` 后缀让 `walk_shader_files()` 的 `.glsl` 遍历看不见这些文件，第 4 项的模块普查与 `compile_glsl.py` 的编译计数不受影响（本轮实测 `#4` 仍为 54 文件／52 模块）。

#### 16.2 P2-13 十条逐条裁决（Astra 侧消费者按正则实测，2026-09-21）

| 件（调研 §6 P2-13 行次） | 参照侧实测 | Astra 侧实测 | 裁决 |
|---|---|---|---|
| 1 驱动兼容层 RenderPearl `prelude/compat.glsl:14-249` | 该文件 249 行，`:1` 是 `// see https://gist.github.com/Luracasmus/ff78f1998a5a440899e1904fa23cc9c6`——RenderPearl 自己也是中继，持有人是 gist 作者 | `IRIS_VERSION` 全包命中 0，无 `lib/compat.glsl` | **不引入**（零消费点）。将来若引入，登记对象是 Luracasmus 而不是 RenderPearl |
| 2 CAS 锐化（LIGHT 仅思路／RenderPearl、Mellow 的 AMD MIT 版） | Mellow `global/post/cas.glsl` 64 行，`:1-7` 是 AMD 的 MIT 原文（`Copyright © 2023 Advanced Micro Devices, Inc.`），持有人是 AMD 不是 TheCMK | `\bCAS\b`／`sharpen` 命中 1 处且是无关注释词（`program/deferred.fsh:135`），无锐化实现 | **不引入**（Astra 的锐化需求未立项）。引入时登记 AMD |
| 3 归一化相位函数（公开论文；Noble GPL 禁抄） | — | 已有自有／已登记实现：`global/atmosphere/sky_minishita.glsl:57` `astra_phase_rayleigh`、`:62` `astra_phase_mie`；水下 `global/water/reference_light.glsl:34` `waterRef_RayleighPhase`（Steadfast 派生）。HG／Schlick 命中 0 | **零改动**：无缺口，Noble 的 GPL 行本来不可抄 |
| 4 Vogel 圆盘／蓝噪声取点（Photon、Bloop 均思路） | — | `Vogel`、`blueNoise` 命中 0；Astra 抖动走自写 `lib/bayer.glsl`（消费点 `global/post/godrays.glsl` 6 处） | **零改动**：思路条目，无 MIT 可署名对象 |
| 5 `pack_unorm_2x8`（Photon、Bloop 语义规格） | — | 命中 0 | **零改动**：G-buffer 通道压力未成为问题 |
| 6 原版光贴图当 LUT Miniature `common/getAmbientColor.glsl:2` | 该文件 18 行，`:2` `vec4 ambient = texture2D(lightmap, vec2(AMBIENT_UV.s, skyLight));` 引用准确；**整个 `shaders/` 目录内无任何许可证明文件** | Astra 不采 lightmap 纹理（`AMBIENT_UV`、`texture(lightmap` 命中 0），走 E1 供的 `skyLight`／`blockLight` 标量（`global/lighting/blocklight.glsl:41`、`global/lighting/diffuse.glsl:305`） | **不引入**：无消费点。且调研「MIT」的前提在此不成立——**包里没有 LICENSE 就没有 MIT 可声明**，属未声明许可 |
| 7 16 格量化阴影采样 Miniature `common/getLightStrength.fsh:11-12` | 该文件 37 行，`:11-12` 为 `#if SHADOW_PIXEL > 0` 与 `world2feet(bandify(feet2world(feetPos), SHADOW_PIXEL))`，引用准确 | `SHADOW_PIXEL`、`bandify` 命中 0 | **不引入**：同上，且 Miniature 许可未声明 |
| 8 SMAA（Mellow 唯一 MIT 实装） | Mellow `global/post/smaa.glsl` 88 行**无任何署名头**，首行即 `redmean`，配 `img/smaaArea.png` 与 `img/smaaSearch.png`——面积／搜索纹理与 redmean 权重是 SMAA 官方参考实现（Jimenez 等）的特征，Mellow 亦为中继且未登记 | `SMAA`、`FXAA`、`areaTex`、`searchTex` 命中 0 | **不引入**：与 §7.B.10（当前阶段不引入 TAA／AA）一致。调研「Mellow = MIT 因此可搬」在权属上不成立 |
| 9 `get_min_light`（绑 `screenBrightness`／`nightVision`） | Mellow `lib/tonemap.glsl`（119 行）`:84-89`，体内三句：`clamp(MIN_LIGHT_AMOUNT + screenBrightness * 0.1 - 0.1, 0.0, 0.5)` → `to_linear` → `+= nightVision / 7` | Astra 无该函数；自有下界为 `MIN_AMBIENT_COLOR`（`global/lighting/diffuse.glsl:409`）与下界分支（`global/dimension/nether.glsl:149-152`）。`screenBrightness` 已冻结在 `lib/uniforms.glsl:67`，经 `sky_gradient.glsl:85` 与 `nether.glsl:23` 两个宏消费 7 处（`clouds_planar.glsl:127,131,134,135`；`nether.glsl:143,147,149`） | **零改动**：能力已在，且形态不同（Astra 按维度配平，不做全局最小亮度）。是否引入 `screenBrightness` 响应属实机标定问题，不在本条范围 |
| 10 primaries → RGB↔XYZ 矩阵（Bloop 的同一算法有 CIE 公开规范） | — | 无独立函数；仅 `lib/tonemap.glsl:156`／`:163` 两条注释继承自 BakingLab 的矩阵链命名（`lib/uniforms.glsl:26` 与 `shaders.properties:243` 的 `XYZ` 是风向 theta 的分量名，无关） | **零改动**：无消费点，且自写即与 Bloop 无关 |

**净结论**：十条在 Astra 侧的可用增量为 **0**。按上表"裁决"列的口径是 5 条不引入（件 1、2、6、7、8）+ 5 条零改动（件 3、4、5、9、10）；按"Astra 侧实测"列的口径是**八条零消费点**（件 1、2、4、5、6、7、8、10，其中件 2 的唯一命中是无关注释词）+ **两条能力已在**（件 3、9）。两种分法都是 10 条，本文此前写的"七条／三条"是把件 10 误归入"能力已在"，本轮按上表逐格改回。P2-13 的实际价值不在清单，而在它逼出的审计方法，已落成 `shaders/lib/vendor/` 与 16.3 的复算配方。

#### 16.3 复算配方（全部为 2026-09-21 实测值）

- **glsl-tone-map**：`https://registry.npmjs.org/glsl-tone-map/-/glsl-tone-map-2.3.1.tgz`，tarball 13228 字节，`sha256 = 106d5d84e22ee37023f862aa22bacfd6699582518b3721ad947bbc0fa3f666e5`，`sha1 = fae727df7a09227c8621b54deba18084c30c0889`；`package.json` 记 `license: MIT`、`repository.directory: packages/glsl-tone-map`。本目录 5 个 `.orig` 加 `LICENSE.md` 已逐字节比对为与该 tarball 一致。
- **BakingLab**：无版本发布，取 jsDelivr `@master`（2026-09-21 抓取并同日复抓，两次逐字节一致）：`https://cdn.jsdelivr.net/gh/TheRealMJP/BakingLab@master/BakingLab/ACES.hlsl`（1322 字节，sha256 见 16.1）与 `https://cdn.jsdelivr.net/gh/TheRealMJP/BakingLab@master/LICENSE`（1060 字节，sha256 见 16.1）。
- **机械复算**：`python qa/tools/verify_tonemap_chain.py`。本轮实测退出 0，输出：去空白与行注释后逐字符比对，`uchimura(vec3,float x7)` 317／317 相同、`uchimura(vec3)` 130／130、`agxPunchy(vec3)` 57／57、`agx(vec3)` 56／56、`RRTAndODTFit(vec3)` 86／86、`ACESFitted(vec3)` 114／114 相同，`agxCdl(...)` 上游 612 → Astra 627（Astra 自加一处 `max(…, vec3(0.0))`，分数次幂遇负底数在 GLSL 无定义，Mellow 与上游都没有）；AgX 6 个常数与 2×9 个 ACES 矩阵值逐值复现（HLSL 行主序 ⇄ GLSL 列主序为同一线性映射）；Mellow 侧六个函数与两张矩阵均等于上游，中继未改写；ACES 血统判别：BakingLab 独有注释命中 2／2、acesHill 独有注释命中 0／2 ⇒ 来源是 `ACES.hlsl`；`reinhard` 权重实测上游 `0.2126,0.7152,0.0722` 对 Astra `0.299,0.587,0.114` ⇒ 不同源；两个未移植旁证集各 0／2 命中，且脚本自行断言判别串在上游六份原件之间唯一。
- **归属更正的可复核面**：`lib/tonemap.glsl:4-17` 的文件头现在同时点名三个持有人并各自指向 vendor 里的许可原文；`global/post/grading.glsl:228-232` 是 Mellow 的思路级署名（调研 §11.B 原记 `:204-208` 已过期，`:204-208` 实为输出 dither 注释块）。

#### 16.4 顺带发现（登记，不在本条修）

- **同一 MIT 包内的近亲文件需要注释级判别式**：`aces.glsl` 与 `acesHill.glsl` 数值几乎一致，靠常数比对无法区分；`reinhardJodie.glsl` 的 Rec.709 三元组同时出现在 `agx.glsl` 的 EOTF 里（Astra `lib/tonemap.glsl:130` 的 `const vec3 lw` 属于已移植的 AgX 块），曾使「未移植」断言假阳性。复算脚本因此改为只用各文件唯一字符串，并自行断言唯一性。
- **美术资产与台账自订边界冲突**：`shaders/textures/bliss-nether-noise.png`（695035 字节，sha256 前缀 `77d1aa0c2195a4f6`，Bliss 原件逐字节复制）、`shaders/textures/complementary-cloud-water.png`（128888 字节，前缀 `49174f769c70f0d1`）、`shaders/textures/solas-water-noise.png`（678019 字节，前缀 `9184f93b83f0ebb2`）与本文件 `:270`「图像／音频等美术资产一律不得取用」相矛盾（该句的当前行号是 `:270`，原写 `:258` 与现文件不符，2026-09-21 B7 实测更正；`solas-water-noise` 另有「用户提供的现成数据文件」一句登记）。`steadfast-water-noise.png`（14561 字节，前缀 `b9502f10ec238b90`）**不属于「Astra 按规则生成」这一列**——2026-09-21 B7 复算把「按 Iris 1.11.2 `NativeImageBackedNoiseTexture` 的 `Random(0)` 规则生成」这条说明**推翻**了：Iris 那个类是 3 字节/像素、经 `GL_RGB8` 直接上传、**根本不落 PNG**，而本文件的像素在任何排列下都无法由 `Random(0)` 复现（详见上表该行与 `qa/b7-png-provenance-2026-09-21.log`）。确实成立的只有「编码器是 Pillow 默认档 `compress_level=6`」；**像素来源在仓库内无法复算**，因此它**既不能证明是第三方美术资产、也不能证明是 Astra 自生成**，且没有任何工具能重算它。**故其处置方向与前三个文件一并归 SC-14 发布门、待用户裁定：重生成、替换还是保留，本条不擅动。**
- **`.mcmeta` 不能用作资产来源判据**：`shaders/textures/` 下实测只有两个 `.mcmeta`——`solas-water-noise.png.mcmeta` 与 `steadfast-water-noise.png.mcmeta`，均 67 字节、内容逐字节相同（`{"texture":{"blur":true,"clamp":false}}`，CRLF，sha256 前缀 `e9c800d49d941e58`），而 `bliss-nether-noise.png` 与 `complementary-cloud-water.png` 根本没有 `.mcmeta`（本条初稿写「三个第三方 png 的 `.mcmeta` 均为 67 字节」，2026-09-21 复查目录实测更正）。关键在于这两个同哈希的 sidecar 一个属于第三方原件、一个属于 Astra 自生成资产，即 `.mcmeta` 携带的信息与来源无关；来源判定只能靠 png 本体哈希。
- **交接文档已过期（注释腐烂）**：`docs/handoffs/nether.md:24,252-272,320`、`docs/handoffs/end.md:55-62`、`docs/handoffs/sky-clouds.md:180` 仍写「Astra 无 `screenBrightness`／本侧只能用常量 0.5／1.0」，而 `lib/uniforms.glsl:67` 已声明且被两个宏消费（见 16.2 第 9 行）。P-002 与 H2 实为已落地，登记状态未更新。
- **§7「MIT ⇒ 可自由复用」的前提只在该包自己就是持有人时成立**：本轮实测四个参照包里 Mellow 的 `tonemap_operators.glsl`（中继 Seguin＋BakingLab）、`global/post/smaa.glsl`（无署名）、RenderPearl 的 `compat.glsl:1`（中继 gist）、Miniature（根本没有 LICENSE）四种失效形态各不相同；今后任何复用须逐文件跑一遍 16.3 的配方。
- **校验缺口（2026-09-21 B7 登记，未修）：本文件已为每张 PNG 记下字节数与 sha256 前缀，但没有任何机器校验它们。** `qa/tools/check_pack.py` 第 8 项只按**文件名**比对：`:613-616` 行把以 `|` 开头且含 `lib/`／`shaders/`／`program/`／`.properties` 的表行收进待检清单，`:637-645` 行再从每行的拼接文本里取出**第一个** `.png`/`.glsl`/`.fsh`/… 文件名，去 `PACK = Astra/shaders` 下找同名文件——**从不读取它的字节**；随后的 `:657-684` 行比对的是 Steadfast 表达式计数。全脚本不含 `hashlib`／`sha256`，`qa/tools/` 里也没有第二个门校验贴图字节（`gen_rain_ripple.py` 只写不读，`sync_to_instance.py` 的 sha256 只用于决定往实例同步时拷哪几个文件）。**因此替换或损坏任何一张 PNG 都能静默通过第 8 项**：本节登记的哈希目前只能靠人工按 B7 的方法复算（`qa/b7-png-provenance-2026-09-21.log` 第 1 节给出全部字节数与完整 sha256）。同一盲区的另一半：canonical `## 登记表`（`:18` 起）至今**零 PNG 行**，PNG 登记只散在上述散文与本节，第 8 项的表格扫描根本看不到这些文件（即 B7 报告里的 G1）。要闭环就须给第 8 项加一条读字节比哈希的检查——本条不擅自改门。

### 2026-09-22 部分方块的光泽与"发光体泛光"（E3）

- `shaders/block.properties` 新增 `block.10013..10016` 四类**发光体驱动的光泽岩**（下界岩／黑石-玄武岩族／深板岩族／石头-圆石族），`shaders/program/lit.vsh` 的 `astra_material()` 把它们映射到 4-bit 材质域的 **12..15**（该域此前只用到 0..11，这四个是全部剩余取值，因此**没有扩位**：`faceData` 的 bits 22..31 仍空，法线的 18 位打包布局未动），`shaders/program/lit.fsh` 新增 `material >= 12u && material <= 15u` 分支。ID 命名空间与类目理由写在 `block.properties` 该段注释里；全部 39 个方块名已对本机客户端 jar 的 `assets/minecraft/lang/en_us.json`（1884 个 vanilla block 名）逐个复核。
- 来源口径：**思路借鉴（idea only）**。对象是 Complementary r5.9 的 `lib/materials/specificMaterials/terrain/netherrack.glsl`、`blackstone.glsl`、`deepslate.glsl`、`stone.glsl` 以及 `lib/materials/materialHandling/terrainIPBR.glsl` 里这四类方块的派发处——即"每种地形材质自带一个 per-texel 光泽度，供该包的 SSR 映出附近的发光体"。**没有使用其中任何表达式**：参考那一串 `pow2(color.r) * 1.5`／`color.r`／`pow(color.g, 1.5) * 0.55`／`pow2(pow2(color.g)) * 2.0`／`dot(color.rgb, color.rgb) * 0.17` 在 Astra 侧命中 0。Astra 的实现是自写的三件：① 光泽 = 类别增益 ×（0.55 底线 + 纹理线性亮度对比），底线的作用是让近黑的黑石与接近白的方解石都落在可用区间；② 世界固定栅格的哈希颗粒 + 按视距收敛（不是参考的纹理直接读法）；③ 邻近门用**原版本方块光等级**（岩浆与火焰同为 15 级，每方块衰减一级），视角权重用与冰面同一形状的 Fresnel。
- 不引入体素泛洪、不新增 pass／缓冲／uniform、不新增任何用户可见选项：近邻信号取自片元自身的 `lightLevel.x`，因此本改动完全不含 `shadowcomp` 类通路，也没有新的 ray march。
- 授权：Complementary 为 **Complementary License Agreement 1.7（专有）**，按本文件开头表与 design.md §9.3／SC-14 的发布闸门处理，仅限当前个人使用定位；发布前须重做发布门决定。本条不含任何参考图像／音频资产。
- 量化留痕：`qa/tools/block_reflect_probe.py`（常量与分支守卫全部从**发货源文件解析**，不是转写；方块反照率取自本机客户端 jar 的 16×16 平均）与 `qa/block-reflect-2026-09-22.log`。



### 2026-10-01：下界接收面反射重建

`program/nether_reflection.fsh`、新增 `program/nether_reflection_resolve.fsh` 和 `global/dimension/nether_reflection.glsl` 继续改编 Complementary r5.9 Reimagined（EminGT）的 `program/composite.glsl`、`composite1.glsl`、`deferred1.glsl`、`lib/materials/materialMethods/reflections.glsl` 与 `reflectionBlurFilter.glsl`。本轮借用独立反射结果后在接收面过滤的结构、Gaussian/smoothness 步幅、纹理保留、Fresnel 雾衰减以及命中边缘/距离衰减公式。固定 3×3 核、置信度单独合成、几何平面拒绝、复用 Nether 的 colortex9 与阶段调度为 Astra 适配；没有移植独立反射历史、随机法线扰动、world-space tracing、默认未启用的生成法线或纹理涂层。既有 Complementary 许可约束继续适用。详见 `docs/2026-10-01-complementary-netherrack-reflection.md`。

同轮 `program/water.glsl` 的中心二项式反射足迹、方向导数与缺失覆盖适配由 Astra 编写，保留其 Steadfast/Solas 既有派生声明；Solas 雾公式仅改变 Astra 密度映射。End 温度与既有频移的连接为 Astra 原有实现的参数调整，没有新增外部黑洞代码或素材。

### 2026-09-27：Astra 可选 TAA

`lib/taa_jitter.glsl`、`lib/taa_reactive.glsl`、`lib/taa_state.glsl`、`program/taa_resolve.fsh`、`program/taa_state.fsh` 及三维度调度由 Astra 编写，没有移植参考光影的 TAA 源码。采用通用的 Halton 抖动、矩阵重投影、深度拒绝、YCoCg 邻域约束与动态区域标记；方法背景见 [Yang、Liu、Salvi 的 TAA 综述](https://behindthepixels.io/assets/files/TemporalAA.pdf)，运行接口见 [Iris 前帧矩阵](https://shaders.properties/current/reference/uniforms/matrices/) 与 [ColorTex 文档](https://shaders.properties/current/reference/buffers/colortex/)。这些资料是设计与接口依据，不构成源码移植声明。

`lib/transforms.glsl` 保留 Mellow 的既有来源；新增抖动坐标接入由 Astra 编写。FXAA 模块的 Arc MIT 声明继续适用，其显示准备入口现移至 `composite8`。


### 2026-09-27：方向性天光、标量 AO 与植被历史

新增 `lib/sky_sh9.glsl`、`lib/sky_directional.glsl`、`program/sky_irradiance.fsh` 和 prepare3 接线由 Astra 编写，使用通用实球谐基函数及余弦卷积。实际天空和云辐射仍来自本包现有模块，各模块原出处继续适用；本项不构成对整套天空代码的重新归属声明。SH9 方向采样与归一化连接没有复制参考光影的实现。

新增 `lib/ao_material.glsl`、`lib/surface_buffers.glsl`、`lib/ao_resolve.glsl`、`program/ssao.fsh`，以及 diffuse / scene 的环境分项、lit 的输出和 deferred2 合成连接由 Astra 编写。采用通用深度采样遮蔽与深度 / 法线保边方法，没有移植参考包 AO 源码。既有 diffuse 的 Steadfast 派生声明不变。

植被前帧参数保存、colortex22 运动编码与 TAA 消费由 Astra 编写。`global/lighting/wind.glsl` 的显式时间接口只是整理现有形变调用；风形变本体沿用既有 Complementary 派生出处及许可，不能因新增历史接口而改记为原创。S2 体积积分与 S3 体素坐标模块不代表 H3 / B4 效果已经完成，当前范围见持续待办。

### 2026-10-01 后续：独立反射历史与水下消噪

- `program/nether_reflection.fsh` 直接改编 Complementary r5.9 Reimagined `program/composite.glsl` 的随机粗糙法线、虚拟反射位置重投影、双 smoothstep 双线性取样、运动/法线/深度/视口有效性指数及 `0.035+0.09*s^8` 新样本比例；作者 EminGT，沿用既有 Complementary 许可登记。`nether_reflection_resolve.fsh` 恢复 `reflectionBlurFilter.glsl` 的接收面 5×5 Gaussian 结构，采用固定平均步幅 6，而非参考的逐帧随机步幅 3–9。
- 色彩历史、当前深度、世界法线和累计命中覆盖分别存入 Astra 的 9/28 附件；`lib/effect_history.glsl`、`program/effect_history_state.fsh` 的尺寸/帧/维度/眼睛状态/投影拒绝与状态附件由 Astra 编写。旧额外反射系数 0.50 撤去，材质×0.80 保留；不增加发光体亮度。
- `global/water/shaft_history.glsl` 的 `.7+.2*exp(-motion)` 时间混合参考 Solas V2.2b `lib/antialiasing/taa.glsl`，作者 Septonious，沿用既有 Solas 许可。Astra 只累计四次方根压缩体积光，使用水段中点重投影、端点距离拒绝和压缩值±0.08 的对比度界限；不是参考全场景 TAA 的 YCoCg 邻域裁剪。附件 29 与独立状态、RGBA16F 格式适配由 Astra 编写。
- `global/water/caustics.glsl` 的水面可见法线继续使用 Solas 波形与差分。新增仅对无法解析的可见波形 octave 方差淡出，像素足迹在 `program/lit.fsh` 分支前计算；这是 Astra 抗混叠适配，阴影焦散原高度场不变。没有滤波场景颜色或新增外部素材。
- End 天空保色调色映射及局部 g 的额外颜色指数由 Astra 编写，不是新的参考包算法。后者是明确的艺术化频移色差增强；实际强度仍使用原 g^4。取舍见实现声明。

后续用户反馈反射只在几乎贴着岩面时可见，`global/dimension/nether_reflection.glsl` 的共用岩石角度函数将参考 SSR-only 门限系数 `0.70` 改为 `0.35`。平方衰减、纹理光滑度、粗糙历史与几何掠射峰值保留。这是明确偏离 Complementary 默认角度曲线的 Astra 可见性标定，引用归属不变；没有新增借用算法或素材。公式量级与取舍见实现声明的“反射可见角度”章节。

### 2026-10-01 后续：照明层次、连续温度与吸积盘流动

- `global/dimension/nether.glsl` 保留 Complementary 原有方向遮蔽、AO、平方根混光及高亮边缘限制，新增仅普通接收面使用的线性弱补光、将有界体素光的替换比例0.95改为0.75。二者为 Astra 针对“不能用调黑制造层次”的照明适配；补光按朝向、遮蔽和照明量淡出，排除发光/传送门材质，没有复制新的参考公式或新增素材。
- `end_kerr.glsl::end_disc_detail` 沿用已登记的 Complementary / flytrap cubic noise 和五层半幅结构，采样域改为随盘旋转的 Cartesian 平面细胞，保留 Solas 来源的弱 `sqrt(radius)` 空间旋绕；旋绕系数1.8→0.65、特征尺寸/权重和按像素足迹收敛到均值为 Astra 选择。原长条极坐标细丝被替换，主相位恢复为既有 `end_orbital_rate(1.34)` 约244秒一圈；这不是 Solas 原涡旋或完整流体模拟。
- 吸积盘温度恢复单次局部频移 `T_observed=g*T_emitted`，取消额外g²和2.4倍色差放大，纹理密度不再驱动温度。物理规则和温度/密度分离的模型结构核对资料为 Eric Bruneton 的 [black_hole/model.glsl](https://ebruneton.github.io/black_hole_shader/black_hole/model.glsl.html)（DefaultDiscColor 与 BlackBodyColor）；未复制其源码、查表、轨道粒子或素材，故不引入新的代码派生许可。Astra 仍用原有局部Kerr近似、三波长色谱和g^4强度，6500K源温标是可见光描绘选择，不宣称完整物理求解。

### 2026-09-28：材质反射与下界色彩空间适配

本轮对照本地 Complementary r5.9 Reimagined 的 netherrack.glsl、endStone.glsl、reflections.glsl、mainLighting.glsl，采用纹理驱动光滑度、反射与自发光分离的机制。新增 lib/rock_material.glsl 的参数映射和 program/deferred.fsh 的下界场景反射连接由 Astra 编写；反射求交复用 Astra 既有 global/water/raytrace.glsl，没有复制 Complementary 的反射算法或新增素材。nether.glsl 保留原有 Complementary 来源声明，新增的是面向 Astra 线性色彩空间的适配。旧 E3 段描述的岩石额外着色已从活动代码移除，改动说明见 docs/2026-09-28-water-material-lighting.md。

### 2026-09-28 第二轮：局部反射和水下接口

新增 `global/dimension/nether_reflection.glsl` 由 Astra 编写，使用材质驱动的反射、带起点偏移的深度求交及现有体素灯光梯度近似局部高光；未复制 Complementary 的求交代码。对照资料仍为本地 Complementary r5.9 的 terrain/netherrack.glsl 与 materialMethods/reflections.glsl。水下可见法线现在复用已有 Steadfast 派生的 surface.glsl，许可声明保持在该文件中；水下折射位移仍保留 Solas 来源，其余介质 Fresnel 合成、按真实水段采样及接收面焦散连接由 Astra 编写。


### 2026-09-29：按参考源码替换下界反射与水下链路

本节描述当前实现，取代上面两条 2026-09-28 记录中已移除的算法归属说明。

- `global/dimension/nether_reflection.glsl` 现在实际改编自本地 Complementary r5.9 Reimagined：`lib/materials/materialMethods/reflections.glsl` 的 30 步求交、6 次细化及粗糙度 mip，`program/deferred1.glsl` 的材质 Fresnel，以及 `program/composite1.glsl` 的 0.7 纹理保留混合。采用参考的完整反射分支 Fresnel 配合屏幕空间求交；没有移植其世界空间追踪。Astra 适配内容为坐标、缓冲、屏幕边缘、颜色编码与后透明阶段接线。旧体素梯度高光已删除。
- `lib/rock_material.glsl` 的下界岩光滑度直接采用 `min(r*r*1.5,1)`，其他岩石参数未随之改写。`global/dimension/nether.glsl` 沿用并补齐 `mainLighting.glsl`、`minimumLighting.glsl`、`colors/lightAndAmbientColors.glsl`、`colors/blocklightColors.glsl` 与 `atmospherics/fog/mainFog.glsl` 的环境光、默认方块光曲线、最低光、AO、平方根混光和距离雾；保留 Astra 生物群系、强度选项及已有体素彩光接入。Complementary 的作者与既有许可说明继续适用。
- `global/water/caustics.glsl` 现在直接改编 Solas V2.2b 的 `lib/water/waterCaustics.glsl`、`waterNormals.glsl` 及 `program/shadow.glsl`：恢复 0.4 波幅、0.5 差分偏移、五点噪声曲率和 `0.25 + caustics*4` 透光。已删除 Astra 的六列正弦波焦散。焦散由水面阴影统一投射，供方块和体积光读取。
- `global/water/light_shafts.glsl` 使用 Solas `lib/atmosphere/volumetricLight.glsl` 的方向权重、线性/指数混合分布、阴影颜色平方、1.75 强度与 `4+sunVisibility*8` 水下乘数。Astra 将分布映射到实际可见水段，沿用距离保边重建，并限制极端情况下的指数；不再叠加旧自写光程吸收和压缩。
- `program/water.glsl` 的水下界面采用 Solas `program/gbuffers_water.glsl`、`lib/pbr/waterReflection.glsl` 的水色照明、0.5 Fresnel 上限和 0.70 alpha 关系，保留 Astra 当帧反射查询、折射边缘处理和颜色空间适配。`lib/solas_water.glsl` 水雾恢复参考的 -6 指数。原 Solas 作者 Septonious、许可及噪声素材归属继续适用。水上 Steadfast 波形保持其既有归属。

### 2026-09-30：水下光束滤波与岩石反射权重

- `global/water/light_shafts.glsl` 的 resolve 补入 Solas V2.2b `program/composite5.glsl` 的四个旋转双线性采样偏移，以及先平均四次方根存储、再四次方展开的顺序。Astra 将偏移映射到实际光束附件尺寸，并逐纹素保留距离权重（16 次读取），避免跨越海草/方块轮廓混合；不滤波场景颜色。沿用 Septonious 与既有 Solas 许可登记。
- `global/dimension/nether_reflection.glsl` 改用 Complementary r5.9 Reimagined `program/deferred1.glsl` 的 SSR-only Fresnel 分支：`fresnelFactor=(1-smoothness)*0.7`，`max(fresnel-fresnelFactor,0)/(1-fresnelFactor)`，随后平方并乘 `sqrt(smoothness)`。这取代上一节所述完整世界反射分支；Astra 未增加世界空间追踪。沿用 EminGT 与既有 Complementary 许可登记。
- `global/water/bloom_resolve.glsl` 保留 Solas 泛光结构，Astra 针对本轮模糊反馈把模糊混合系数 0.20 调至 0.12；属于本项目观感标定，不是参考默认值。未新增素材。

### 2026-09-30 后续：水下通透度与末地清晰度

- `lib/solas_water.glsl` 保留 Solas 水雾指数、混合顺序和显示曲线；Astra 将密度档位换算从 `/40` 改为 `/55`，水下显示增益从 4.7 改为 5.2。`global/water/bloom_resolve.glsl` 在既有对比度域只加入模糊结果相对原图的正差值，保留原图细节。这些是针对用户“仍糊、偏暗”的标定与合成调整，均非 Solas 默认参数；既有 Septonious 来源与许可登记继续适用。
- `global/dimension/end_system.glsl` 的球面星点目录由 Astra 编写，替代六个立方体面的格点投影；纬度行的格数按圆周长度缩放，经度索引循环，每行相位错开。继续复用 Astra 原有光谱、亮度种群和椭圆像素足迹，不是新借用的参考包算法。末地黑洞的附件分辨率改为原生大小，既有光路图集及素材来源保持其登记。

### 2026-09-30 再次反馈：高亮泛光、细节保护与源数据

- 水下 `global/water/bloom_capture.glsl` / `bloom_resolve.glsl` 已替换为本包 `global/post/bloom.glsl` 的 HDR 高亮预筛选、13 点下采样、mip 加法组合，退出此前 Solas 无阈值整幅场景柔光结构。复用部分属于已登记的 Refrax v1.3.1 衍生实现，原许可与发布前重写要求继续适用；水下 25% 强度系数、附件接线由 Astra 决定。此前 Solas 登记作为历史归属保留，现行水雾、光束与水面仍沿用各自的 Solas 归属。
- `global/post/fxaa.glsl` 原 Arc v0.15.2 MIT 边缘搜索与许可头保留。新增的深度轮廓门和水下/末地天空禁用颜色亚像素混合由 Astra 编写，不是 Arc 默认算法；理由是保存已解析的纹理、焦散与天空细节。取舍见本轮实现记录。
- `lib/rock_material.glsl` 下界岩使用 `0.80 * min(red*red*1.5,1)`：主体表达式来自已登记的 Complementary r5.9，新增 0.80 是用户要求进一步减弱反射后的 Astra 偏离，SSR 其他结构保持既有来源。
- 原创光路生成器 `qa/tools/build_end_transfer.py` 将坐标图集重生成为 4096，流场为 1024；保留原积分器和五层原始流场，新细纹为 Astra 生成的独立随机场乘法调制，无新外部素材。`end_kerr.glsl` 按实际纹理尺寸转换坐标/足迹；天空泛光减量由 Astra 决定，不提高原发射系数。

### 2026-09-30：依据 blur/glow/disk 调研的源码修复

- `lib/solas_water.glsl` 保留 Solas V2.2b `lib/water/waterFog.glsl` 的指数、glare 函数与混合顺序，Astra 将密度换算改为 `/100`、迎光系数从 16 减为 4，以满足用户拒绝远景雾幕与迎光泛白的要求。这些是明确偏离参考的画质标定；Septonious 与既有 Solas 许可登记继续适用。
- `global/dimension/nether_reflection.glsl::nether_rough_reflection` 借用 Complementary r5.9 Reimagined `lib/materials/materialMethods/reflectionBlurFilter.glsl` 的高斯空间重建结构及 smoothness 八次方半径收缩。Astra 改为命中源的固定 3×3、边界舍弃、归一化，不是参考接收面 5×5 法线/深度门或反射历史；额外 0.60 响应为减量决定。EminGT 与既有 Complementary 许可登记继续适用，详细偏离理由见实现记录。
- `global/dimension/end_kerr.glsl::end_disc_noise/end_disc_filaments` 的 cubic value noise 插值、五层频率翻倍／幅度减半及 smoothstep 重映射结构参考 Complementary `lib/atmospherics/nightNebula.glsl`，该原文件署名 nebula implementation by **flytrap** 并指向其 [2D nebula shader](https://godotshaders.com/shader/2d-nebula-shader/)。保留该原文件的作者归属以及既有 Complementary 来源登记。哈希使用 Astra 原有 end_hash2，周期极坐标索引和逐层像素足迹滤波为 Astra 适配。
- 同一细丝域的 `angle + sqrt(radius)*whirl` 结构改编自 Solas `lib/atmosphere/skyEffects.glsl::getSpiralWarping`；Astra 将其用于周期细丝采样，改用固定空间剪切与慢相位漂移，未移植参考 vortex 核心与着色。Septonious 与既有 Solas 来源登记继续适用。
- 新 mip 打包纹理由 `qa/tools/build_end_transfer.py` 从 Astra 既有原创流场按 box 平均生成，周期边缘、打包层选择和插值由 Astra 编写。未引入新的外部图片。末地反应遮罩和默认 FXAA 路径调整为 Astra 适配，Arc 既有 FXAA MIT 许可头保留。

### 2026-10-02：Steadfast 调研后的性能优化

- 本轮参考 Steadfast 0.8.0 的 CPU / GPU 计算分工、紧凑 HDR 存储和效果预算思路，具体缓冲调度、AO 七位打包、质量配置与水反射五点过滤由 Astra 编写；未新增从该包直接复制的表达式或素材。Astra 既有 Steadfast 派生模块和来源登记继续适用。
- `global/atmosphere/sky_gradient.glsl` 的帧内一致昼夜曲线、白天天空调色与眩光底色移至 `shaders.properties`。这些表达式继续沿用此前 Complementary r5.9 Reimagined 的来源、作者 EminGT 和既有许可，计算位置变更不改变出处；模块文件头列出的 Astra 输入映射与偏离仍适用。
- `global/atmosphere/sky_minishita.glsl` 共用日月视线积分位置及密度，源方向与权重改由公共参数提供，属于 Astra 现有散射实现的重组。`lib/transforms.glsl` 的新增公共光源接口由 Astra 编写，既有 Mellow MIT 坐标变换归属不变。
- `global/water/raytrace.glsl`、`global/water/surface.glsl`、`program/water.glsl` 的预算档位、无贡献反射跳过及掠射视差衰减为 Astra 适配；波形和水下界面继续沿用现有 Steadfast / Solas 归属。

### 2026-10-02：二十包 SUMMARY 的采用项

- 依据 `shader_research/SUMMARY.md` 及相应单包报告阅读思想，以下新增表达式和接线由 Astra 编写，没有新增从参考包直接复制的代码或素材。原文件已有改编代码的出处与许可继续适用。
- `lib/taa_jitter.glsl`、`shaders.properties`、`global/atmosphere/weather.glsl`：帧内公共参数转至 CPU 的组织方式参考 MakeUp、Mellow、SDV 等报告；Halton 表、居中值及天气表达式来自 Astra 已有实现。`global/atmosphere/cloud_shadow_cache.glsl` 与 `program/cloud_shadow_cache.fsh` 的共享锚点及高度淡出参考 Kappa / VPS / Nostalgia 的报告方向，使用 Astra 自有平面缓存接口。
- `global/atmosphere/volume_fog.glsl`：短射线少步的思想参考 Nostalgia / Kappa / Hysteria，近处加密的通用分段思想参考 Shrimple / Complementary / Solas；本轮次数公式、二次边界及分段积分接线由 Astra 编写。
- `global/post/bloom.glsl`：低 / 均衡捕获核由 Astra 编写，参考 MakeUp / Mellow 的小预算与 mip 组织思路。高档的既有十三点核及 prefilter 沿用 Refrax 原登记；本轮没有将整个 Bloom 文件重新归属为原创。
- `global/lighting/blocklight.glsl`：玩家光心、连续衰减及源头限幅的思想参考 Hysteria / Insanity / BSL 报告；新手持曲线由 Astra 编写，原文件的 Steadfast 与 Refrax 衍生登记继续适用。`program/taa_resolve.fsh` 的中心可信度思想参考 Photon / Kappa / Mellow，采用 Astra 自有权重及逐角点历史接口。
- `global/post/grading.glsl` 的可选夜间蓝移由 Astra 编写，思想来源为 Mellow / Bliss / Photon / Nostalgia / Kappa。`program/display.fsh` 的无 Bloom 阶段合并、实体投影名单和零贡献阶段配置属于 Astra 接线；现有 Solas 水下合成公式未重新归属。

### 2026-10-02：批次二 SUMMARY 的采用项

- `lib/environment_brdf.glsl` 的标量环境拟合改编自 Musk Rose Shaders 4.1（作者 Rin），本地出处 `reference_shaderpacks/musk-rose-shaders/shaders/programmes/utils/musk_rose_pbr.glsl::getEnvironmentBRDF`，包内许可 CC0-1.0。原来源的 UE4 mobile BRDF 链接保留在文件头；[许可全文](shaders/lib/vendor/musk-rose/LICENSE.txt) 随包保留。共享指数、零粗糙度归一化、0–1 限幅及水 / 冰 / 积水天空退路接线为 Astra 适配，原表面 Fresnel 不重复相乘。
- `lib/sky_reflection_cache.glsl` 的可选粗糙度 LOD、逐层周期接缝插值及 `prepare2` mip 调度由 Astra 编写；仅参考 Glimmer / Musk Rose / Voyager 报告关于共享环境与粗糙度的组织方向，没有复制 Glimmer 或 Voyager 的代码。天空与云缓存内容继续沿用各模块既有来源，HDR 格式保持原设定。
- `shaders.properties` 的周期时钟突变信号及 TAA、独立云、独立效果历史、曝光接入，以及 `global/atmosphere/volume_fog.glsl` 的原点 / 方向平行阴影空间射线，由 Astra 编写；仅参考 UShader 报告的方法，没有搬运 UShader 表达式。原坐标变换、光照、天气与积分模块的既有归属继续适用。
- 本轮没有引入参考包贴图、静态 LUT、SSDO、Builderb0y 阴影实现或 dirtyLens 素材。

### 2026-10-04：多报告处置增补（IDEA ONLY）

- `program/shadow.vsh`：参考本地 `reference_shaderpacks/just-colored-lighting/shaders/shadow.vsh:81,94–96` 在体素采集后将非可见维度的投射顶点移出裁剪区的思路。Astra 仅在下界应用，沿用本包已有裁剪表达和输出初始化约定；没有复制参考源码、命名、素材或公式，登记为 **IDEA ONLY**。该包按保留所有权利处理，不将此记录视为代码复用授权。体素写入先执行，末地及主世界仍保留投射。对应四报告总表的下界阴影栅格工作条目。
- 许可勘误以本地许可原文为准：renderpearl 是 MIT；aurora-fantasy / aurora-astral 是 LGPL-3.0；soft-voxels-lite 是 All Rights Reserved。这里只核正调研元数据，没有搬运这些包的源码或资产，故没有新增 vendor 许可文件。已有资产限制及历史待决项继续有效。
- 现行下界反射没有体素灯光梯度高光；现行下界混光仍包含 `sqrt` 和双域 `min`。上方历史记录须结合后续接续记录阅读，不再作为现行代码的完整描述。旧探针已明确标为历史，不用于支持现行数值。

### 2026-10-05：末地缓存、固定星表与 Bloom 自写替换

- `lib/end_reflection_cache.glsl`、`program/end_reflection_cache.fsh`、`world1/prepare1.fsh/vsh`：Astra 自写生产/消费、周期接缝、邻点接受条件及精细区域保留；复用已登记的 Astra 球面映射组织（ITT 环境共享仅 IDEA ONLY），缓存内容由现有末地模块计算，各模块既有来源继续有效。
- `lib/end_star_catalogue.glsl`、`program/end_star_rows.csh`、`program/end_star_catalogue.csh`、`world1/setup.csh`、`setup1.csh`、`setup2.csh`：Astra 自写紧凑布局、初始化与读取；原星格生成器、分布及 FP32 精度保留，没有引入外部星表、图片或替代生成公式。
- `global/post/bloom.glsl`：当前软阈值是自行推导的积分激活曲线，高档是中心加十二点等角圆盘核，已替换历史 Refrax 二次膝区与方形十三点核。低/均衡滤波、mip 权重、捕获比例和阶段接线继续为 Astra 自写；Refrax / MakeUp / Mellow 只保留一般组织思路，登记为 **IDEA ONLY**。没有移植 Ebin 代码，故没有新增 vendor 许可。历史 09-05/10-01/10-02 关于旧公式的记录保留追溯，不能再当作当前活动 Bloom 的归属。
- `global/water/bloom_capture.glsl` 共用上述自写 HDR 实现，当前出处注释已修准；水雾、光束和其他 Solas/ITT 来源不改归属。本轮只替换 Bloom 两处活动来源表达式，其他 Refrax/Solas/Complementary 等模块与素材的发布边界仍各自有效。
- 专用水波/云图片的条件登记是 Astra 配置调整，未修改图片、图集分辨率或新增素材。

## 2026-10-06 新增两报告处置：现行出处与契约更正

历史条目保留，现行处置见 docs/2026-10-06-two-reports-disposition.md 与两份作者报告末尾。

- K-M2：clouds_planar 的 ASTRA_CLOUD_STRETCH=9.0、ROUNDNESS=0.48 是现有 Astra 形状改编；引用的 Complementary reimaginedClouds.glsl:3-5 为4.2/0.125。保留现有数值，不能把它们称逐字参考值；原 Complementary 许可与出处不变。
- K-M6：SSS 的0.7071在 diffuse.glsl 的 astra_lighting→direct_lighting 调用处唯一施加，shadow_mapping内没有该系数；上表历史“B1归一化”说法不能用于再加一次系数。
- K-M8：地表云影主要读独立缓存 colortex14，边界外回 astra_cloud_transmission 原密度；地平线权重由 astraCloudShadowFade 的 CPU 表达式供给。旧weather每片元两次查询与GLSL smoothstep描述属于早期实现。BSL/Complementary仍是 IDEA ONLY；没有因此新复制其公式。
- Z-M5：Nether既有五群系调色数值及密度系数仅迁到properties CPU表达式，保留 Complementary/ITT 历史归属；coverage不足时原调用的fallback仍在GLSL处理。Z-M21 TAA帧有效性迁到Astra专用顶点，判据不变。
- 本轮没有采用42条借鉴候选的代码或新视觉算法，没有新增第三方代码级复用，因此无新增vendor许可原文。候选的接受方向/未实施理由不等于已移植登记；后续真正采用时必须重新按 IDEA ONLY 或代码级口径落实许可与台账。

## 2026-10-06 主世界 / 下界开销与流水修正

- `lib/nether_reflection_metadata.glsl` 的 RG 法线编码、B 标记及 flags 复用协议，以及反射恢复的齐次平面判据由 Astra 编写。现有追踪、历史和接收面反射结构继续沿用 Complementary / EminGT 的既有归属和许可；没有增加目标或复制新参考代码。
- `global/post/fxaa.glsl` 保留 Arc / Minecraft / Shaders 的 MIT 算法及 `/lib/vendor/arc/LICENSE.txt`；本轮主世界/下界的 gather 邻域组织和角点复用由 Astra 编写，原边缘搜索、阈值与柔化参数保持。末地继续用原采样组织。
- 下界暗处填充标定、体素捕获提交范围与未消费影图附件尺寸属于 Astra 的场景适配；Solas 彩光场、Complementary 光照的既有来源不变。主世界流水侧面稳定处理及浅层吸收标定由 Astra 编写，水平水面和水下窗口的 Steadfast / Solas / ITT 历史归属仍按原登记执行。
- 本轮没有新增第三方代码或素材，不新增 vendor 许可。

## 2026-10-06 作者回复复核：颗粒参考范围勘误（Z-B25 / N081）

上表 `shaders/global/water/particles.glsl` 的“无参考（四包均无屏幕空间悬浮颗粒实现）”与文件头 `:9-11` 的同类否定，不能用于概括当前参考资料：本地 `_analysis/Refrax_v1.3.1/shaders/lib/underwater.glsl:32-62` 确有 underwaterMotes，`:65-88` 有 underwaterBubbles，`lib/settings.glsl:374/:379` 均默认定义。motes 在 `:52-55` 查影图、`:57-61` 分别累积直射与环境；bubbles 的 `:86-87` 是视角瓣和天光，不具同样影图分层。旧记录的具体“四包”名单没有列明，本次不凭空补其历史检索范围；至少不能将上述否定用于排除现有 Refrax 源。

本次只纠正参考范围与证据措辞，不因 Refrax 有相似功能便推断 Astra 复制它。当前 Astra 的原创声明保留，未新增 Refrax 表达式、结构移植或素材，也未将此候选假登记为已移植。颗粒的影图分层仍为独立候选；未来实施必须据实际复用程度登记 IDEA ONLY 或代码级归属及相应许可。本条是现行台账补正，源码旧注释未改，阅读其否定句时应以此补正为准。

## 2026-10-07 整包审查：既有水路复用与注释落地

- `program/water.glsl` 的水下命中反射改为调用 Astra 已有 `water_sample_path`，由各颜色贡献自己的深度与界面侧决定水中传输；备用折射颜色显式读取第零层。调用组织由 Astra 编写，沿用包内已有光学与吸收模块，没有搬入新的外部公式或素材。Steadfast、Solas、ITT 等既有模块归属及发布限制继续有效。
- `program/scene.glsl` 的下界雾端点返回是对现有表达式的自行约分，部分雾混合方式不变；Mellow 编解码核心与 Astra 的 IEC 扩展归属保持。
- 10-06 Z-B25 / N081 关于 Refrax `underwaterMotes`、`underwaterBubbles` 的勘误现已落实到 `global/water/particles.glsl` 文件头，原“源码旧注释未改”仅描述当日状态。此次未采用 Refrax 影图分层或其颗粒表达式；Astra 自写颗粒声明仍有效。晶格、消费者与候选退出比例的注释同时对齐实际代码。
- 没有新增第三方代码级复用、资产或 vendor 许可；
