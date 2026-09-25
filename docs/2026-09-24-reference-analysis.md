# 十个参考包研读与两项整改（2026-09-24）

本轮落地两项：水下光束逐 texel 解码后重建；平面云遇到不透明地形停止采样。分别完成三档编译，均为 `linked=270 failed=0 compute=27`。没有改 Kerr、没有引入 TAA 或历史累积，没有根据参考包另调发光强度。

**水下和主世界的观感、帧耗均需实机确认。** 本文的 GPU 数值来自合成输入和实际 GLSL 函数，不是 Minecraft 场景。没有这两个维度的离线出图，也没有用末地天空图片替代它们。

## 1. 阅读范围与现状订正

参考路径以下均相对于 `_analysis/refs-2026-09-24/`；Astra 路径相对于 `Astra/shaders/`。行号对应本次本地发布版和本轮完成后的源码，不是网上最新开发版。

- Miniature 已读完整的 shader 源码与 properties，包括根目录、common、program、三个 world 入口。相同文件内容合并阅读。按 `.glsl/.fsh/.vsh/.csh/.h/.properties` 口径共有 105 个文件、1771 个物理行；任务清单的 94 是 shader 阶段文件数，**不是每帧 94 个 pass**，1574 与这里包含 properties 的行数口径不同。
- 其余包按水、云、阴影、光照和配置的调用链选读；没有声称逐行读完所有包。Shrimple 先做词法开销清点，再读雾积分、实际 fog_filter、体积配置与合成调用者。高开销候选包括 `lib/sampling/bilateral_gaussian.glsl`（8 个循环、9 个采样调用点）、`lib/fog/fog_volume.glsl`（3、6）、`program/composite11.csh`（3、6）。其中 bilateral_gaussian 在两个合成程序中的 include 已注释，**实际体雾合成使用 `lib/sampling/fog_filter.glsl`，不能把清点第一名当作运行热点**。
- 清点脚本和输出留在 `_analysis/read_refs.py`、`_analysis/refs-2026-09-24-cost-census.txt`。它去除注释，统计循环与纹理调用点，仅用于定位源码；不代表展开后的指令数或 GPU 时间。
- 任务文件中的“末地石无发光、水下探针运行即失败”已落后于当前代码。前一轮已经接入材质身份发光、`separateAo`、实际 GLSL 探针；AO 的游戏实际输入仍未知。本轮在修改水下前执行两个现有入口，均可运行。前一轮状态详见 [交接处理记录](2026-09-24-handoff-resolution.md)。本轮没有重复把这些记作新成果。

## 2. 按对当前 Astra 的价值排序

以下成本是指定分支的源代码计数或逻辑数据量，忽略缓存、压缩、驱动合并及遮挡。半宽半高是四分之一像素数。默认值指源码默认宏，配置档可能覆盖。

### 1）FastPBR 2.0：把廉价 AO 与历史间接光分开

- `fastpbr/shaders/program/deferred/HBIL.csh:20`：compute 使用 8×4 工作组，`workGroupsRender=vec2(0.5)`。`:71` 的普通 SSAO 是 4 次循环，每次正反两个深度采样，即 8 次；`:304` 明确是默认 `AMBIENT_LIGHT_MODE=1` 的分支（`settings.glsl:42`），不是默认在跑 HBIL。
- `HBIL.csh:308` 的模式 2 才启用重投影。`:336` 至 `:375` 逐个读取四个历史 texel，先用相对距离差 `<0.1` 判有效，再混合颜色；累积最多 256 帧，混合下限 0.025。这里值得借鉴的是**判定与颜色保持同一 texel 对应**，不是帧间累积。
- 普通 AO 每个低分辨率像素 8 个邻深度读取，加调用处一个中心深度；`:392` 写一个 RGBA16F。1080p、未再缩放时，半分辨率写出逻辑量约 4.15 MB/帧。模式 2 另写两个 RGBA16F，且读历史，不能称为“免费 GI”。
- 默认关资源包反射、景深，开粗糙反射（4 samples）、SSR、TAA：`settings.glsl:79`、`:81`、`:83`、`:96`、`:128`。云也不是简单低成本版：`lib/atmos/clouds/common.glsl:3` 定义 60 samples。
- 对 Astra：四邻点先判距离再混合可用于当前帧水下重建，不需要新 pass/buffer；HBIL 则违反不引入历史的约束，不移植。不要因“Fast”包名直接采用它的整套管线。

### 2）Shrimple v0.12：散射、透射与距离配对重建

- 实际入口 `shrimple/shaders/lib/sampling/fog_filter.glsl:1`：空间 Gaussian 参数 `(1.6,1.6)`，深度参数 `0.2`；`:22` 至 `:35` 对每个低分辨率 texel 分别读取散射、透射和对应的全分辨率深度，`:52` 至 `:67` 加权归一化后再做 `scene * transmit + scatter`。调用在 `program/composite14.fsh:545`、`composite18.fsh:962`。
- `lib/common.glsl:313` 默认 48 积分步，`:315` 默认 `VOLUMETRIC_RES=1`，`:318` blur 半径 1；`shaders.properties:621` 的 res=1 是半宽半高，res=2 是四分之一宽高。默认重建 3×3×3=27 个纹理读取/全分辨率像素，不含 DH；半径 2 会成为 75 次。不能因为积分降采样就忽略重建成本。
- `lib/fog/fog_volume.glsl:14` 距离为空直接返回；`:17` 按 TAA 开关选择时间变化或静态抖动；`:6` 水相函数 HG 参数 0.36。`lib/common.glsl:352` 默认开 TAA，但体积方块光模式默认 0、天体体积开关注释（`:310` 至 `:311`），profiles 会覆盖相关路径。
- 对 Astra：同一 texel 的颜色和距离必须先配对，直接指导本轮修复；不采用 27-fetch 核。完整的独立透射 RGB 会增加或重分配 buffer，还要改水合成接口，属于结构重做。

### 3）Super Duper Vanilla 1.3.8：先限制可见云区间

- `super-duper-vanilla/shaders/lib/rayTracing/volumetricClouds.glsl:7` 同时接收视线、地形距离和是否天空；`:9` 将远端限到地形，`:13` 至 `:27` 与云上下平面相交后再定步数。`:45` 每步一次 `texelFetch`，从同一纹理的两个通道取云场。
- `lib/settings.glsl:88` 默认 CLOUD_TYPE=2、双层开；`:94` 最大 16 步、厚度 8 格。`main/composite.glsl:309`、`:316` 双层分别调用，故云段上限为 32 次场读取/像素，不是 16；预计算云纹理、合成及光照另算。距离还受 `shaders.properties:467` 的 `far*8*(1-rain*0.5)` 限制。
- `lib/settings.glsl:9` 默认 ANTI_ALIASING=2，合成程序 `main/composite6.glsl:180` 有前帧消费，不能把其动态噪声照搬到无历史管线；SSGI 默认关（`:66`）。
- 对 Astra：不透明终点限制完全不需要新 pass/buffer。本轮保留 Astra 天空的采样间隔，仅停止地形后的采样；没有复制该包的按截断长度重新分配步长，也没有照搬其可能出现零步数的边界写法。

### 4）Miniature 2.19：有限反射预算、前向光照与身份分类

- `miniature-shader/shaders/common/getReflectionColor.fsh:15` 拒绝朝相机的追踪方向；`:24` 主追踪默认 10 步，`:42` 命中后最多 4 步二分，`:55` 一次命中颜色采样。`shader.h:24` 至 `:26` 为 `10 / 1.6 / 4`；HIGH 档为 `16 / 1.2 / 8`（`shaders.properties:4`）。默认单条有效反射最多 14 次深度＋1 次命中颜色读取，不含 final 的起点/法线/元数据读取。
- `common/getLightStrength.fsh:25` 至 `:33` 先按距离、正面受光、阴影图范围筛选，之后只有一个阴影深度读取，无 PCF 循环。默认阴影 1024、128 格、实体比例 0.2（`shader.h:31` 至 `:35`），只在主世界启用（`:59`）。
- `program/textured_lit.vsh:115` 起把雾与部分光色放到顶点；`textured_lit.fsh:67`、`:116` 用 alpha 携带/消费 AO，`shaders.properties:19` 明确 separateAo。`textured_lit.vsh:92` 用方块 ID 标 ore，`textured_lit.fsh:87` 再做发光，避免“颜色像矿石就发光”。
- 没有 TAA、独立 deferred/composite 链；云用原版几何，水采用简化前向颜色/透明度。代价是功能与表达能力较少。它**仍在 `textured_lit.fsh:130` 写 MRT 0/6/7**，反射关时写零也不等于取消附件写入。
- 对 Astra：身份门控、明确质量预算适用；本轮不把现有 96 步薄植被 SSR 改成 10 步，也不把完整水雾改成 alpha 混合。删除 Astra 的 raw HDR 附件需要重新组织透明背景，不能仅参照它没有 deferred。

### 5）Photon v1.3b：显式介质积分与有限距离

- `photon-shader/shaders/include/fog/water_fog_vl.glsl:9` 上限 50 格；`:17` 至 `:19` 步数从 16 起，按距离每格加 0.5，上限 25。`:24` 至 `:32` 分离吸收、散射和消光；`:72` 提前计算每步透射，`:143` 乘入累计透射，`:146` 用每步积分系数完成归一化。
- 每步两个阴影深度 `texelFetch`（`:87`）、两个焦散噪声读取（`:116`），最多 100 次这类读取/低分辨率像素；`:124` 另有 4 次多重散射近似循环，HG 主参数 0.5，权重每次减半。不是四条新阴影光线，但有额外算术。
- `settings.glsl:310` VL scale 默认 0.5，`:456` 水下散射系数 0.03，`:470` TAA 开、`:472` TAAU 关、`:57` 彩色体素光关。`program/c0_vl.fsh:168` 采用随帧变化的抖动。
- `include/buffers.glsl:10` 至 `:11` 雾透射 RGBA16、散射 RGB16F；`shaders.properties:255` 至 `:256` 半分辨率。两附件逻辑写出约 7.26 MB/1080p 帧。`program/c1_blend_layers.fsh:193` 的 smooth_filter 是坐标五次平滑＋一次硬件采样，两个雾图总共两次调用，**不是深度双边滤波**。
- 对 Astra：适合指导介质接口和有限积分，不是现成“更便宜焦散”。现有 Solas gamma 域接口若换为线性散射/透射，需要整体改合成边界与至少一项 buffer 布局；本轮仅修压缩存储重建。

### 6）Bliss 2.1.2：用高度分层塑造下界体积感

- `bliss-shader/shaders/lib/nether_fog.glsl:15` 将地板 plume、顶部密度、侵蚀结合；`:26` 的 100/120 高度界限与 15/10 衰减尺度、`:27` 的地板 31/3，直接决定雾分层。`:46` 固定 16 步，`:52` 限远到 `min(far,192)`，`:58` 指数分布因子 11。
- `:85` plume 光色 `(1,0.4,0.2)` 随密度降低；`:90` haze 只加颜色、不消光；`:102` 顶部烟才改变消光。这是有意识的美术分工，不是严格物理散射。每步 cloudVol 两次噪声读取，基本雾段 32 次/低分辨率像素；可选 LPV 另算。
- `lib/res_params.glsl:16` 默认体雾 0.5 尺度，`lib/settings.glsl:164` 雾开、`:515` TAA 开、`:746` LPV 默认关、`:755` LPV 照雾默认关。开启项不能用默认成本来描述。
- 对 Astra：已有 `global/dimension/nether_volume.glsl` 是这一思路的适配，不能再把原作同一层当新增进展。岩石表面的泛光与体雾是两件事；继续提高 rockPeak 并不能补出局部遮挡或邻近光源方向。

### 7）Kappa 5.3：彩色阴影逐角点配对，几何法线参与偏置

- `kappa-shader/shaders/world0/deferred3.fsh:98`：两个比较 `textureGather` 配四个 caster 颜色读取，再按各角点的遮挡分类混合，避免把中心材质强加到水/玻璃边缘。`:137` 默认 15 个滤波位置（`settings.glsl:126`），主滤波最多 30 gather＋60 颜色读取/受光像素，blocker 搜索另算。
- 末地路径不同：`world1/deferred3.fsh:106` 是 15 次阴影比较＋15 次颜色采样；`:136` 沿光方向移动 `0.08*(2048/res)`，`:321` 至 `:324` 使用额外存下来的几何法线，偏移因子带距离 `min(0.1+distance/200,0.5)` 和角度。
- `settings.glsl:123` VPS 开，`:132` SSPT 开，默认 2 spp / 1 bounce（`:134`）、TAA 开（`:237`）。这些结果依赖它更完整的 G-buffer、间接光及历史路径。
- 对 Astra：当前角点材质配对已经具备；不能以中心 caster 简化来冒充等价硬件过滤。末地 bias 可以对照坐标方向与几何法线，但数值受投影与 texel 世界尺寸影响，不能直接套 0.08。将独立几何法线带到延迟阶段需要 buffer 空间；当前前向表面路径已有法线，不需要为此新增附件。

### 8）Visual Vibrance 0.3.5a：用光照贴图梯度给法线贴图方向感

- `visual-vibrance/shaders/lib/lighting/directionalLightmap.glsl:29` 求位置与 lightmap 导数；`:35` 在梯度有效时构造局部方向，`:50` 用映射法线与几何法线的受光差调 torch，最大乘子尺度 0.25；梯度近零有明确分支。该函数增加导数与向量算术，**不新增纹理读取、pass 或历史**。
- `lib/common/settings.glsl:23` 此功能默认开；`:47` TEMPORAL_FILTER 关、`:55` FXAA 开、`:18` FLOODFILL 关、`:86` 折射关、`:40` 阴影 4 samples。比“见到体素代码就认定默认使用”更有参考价值。
- 可选体素路径 `program/shadowcomp.csh:9` 为 256×128×256；`:28` 六邻点，`:29` 移动前帧体素坐标，`:37` / `:64` 按帧奇偶读写，`:44` 平均后乘 0.99。两个 RGBA16F＋一个 R32UI 逻辑容量 160 MiB，**属于跨帧传播**。
- 对 Astra：导数方向法可改善普通方块光法线质感，但不能替代真实 AO、墙后遮挡、熔岩位置。体素跨帧传播与约束冲突，不采用；Astra 64³、同帧八轮的容量只有上述体积的 1/32，但每帧反复读写，不能仅比较容量得出更快。

### 9）Nostalgia 5.1：云形状与低频光照分工，不以步数代表成本

- `nostalgia-shader/shaders/lib/atmos/clouds.glsl:41` 用四次场纹理读取做平滑云轮廓；`settings.glsl:34` rounding=4、主层 samples=14、高度160、厚度14、clip1200（`:38`），副层 samples=10（`:44`）。默认关云投影和层间阴影（`:35`），开云动态光和 TAA（`:31`、`:204`）。
- `world0/composite1.fsh:433` 把云终点截到地形；`:437` 至 `:441` 按射线长度调整步数，主层实际范围可到 21，不是固定14；`:448` 透射低于0.01时停止。
- `:464` 每个非空步另外做 5 次光向、4 次向上的密度采样。按同一四读场函数，主层每个非空步可达 `(1+5+4)*4=40` 读取，主层21步上限840（不含额外层遮挡），空步仅4读。这样解释“14步高质量云”的真正成本才有意义。
- 对 Astra：地形终点限制是可用思路；Astra 当前命中第一个有效点即退出，不是体积透射积分，不能直接把 0.01 终止阈值或14步数字套进去。更复杂的多方向云光照本轮不加。

### 10）AstraLex 93.0：选项要管到 pass 调度，但实现仍须审读

- `astralex/shaders/shaders.properties:7` 至 `:10` 用 LOW→MEDIUM→HIGH→ULTRA 继承明确组合；LOW 1024/192，ULTRA 3072/512，LOW 关闭 AO/光束/材质等。`:470` 至 `:501` 将光束、运动模糊、景深、两段 bloom、镜头与其他效果直接映射到 `program.*.enabled`，而不只是 fragment 内部返回零。
- 默认 `settings/globalSettings.glsl:216` AA=3、`:254` TAA_SHADOW_FILTER 开；`program/composite13.glsl:107` 才是对应 TAA 消费分支。关闭某效果省掉的 pass 数必须看这一映射，例如 bloom 是两个 composite pass。
- 反例也值得记录：`lib/lighting/shadows.glsl:70` 先跑一次3×3 Gaussian，`:72` 又采9次，`:76` 只除以9，因此普通滤波的白输入在 clamp 前不是1，而是10/9；这条分支实际18次主阴影比较，可选彩色再9颜色＋9比较。不能只看到数组长度9就抄走。TAA分支`:101` 是9比较，可选4颜色＋4比较。
- 对 Astra：真正关闭 shadow pass 的全局开关已在前轮接通；本轮不扩充菜单。保留依赖关系、按实际 draw 调度判断成本，比照抄巨大 profile 行更有价值。

## 3. 差距对照

| 薄弱处 | 参考依据与数值 | 当前 Astra（完成本轮后） | 差距性质 / 新资源 |
|---|---|---|---|
| 水下光束重建 | Shrimple `fog_filter.glsl:22` 逐点配距离；FastPBR `HBIL.csh:355` 先判定再混合 | `global/water/light_shafts.glsl:91` 四点逐个解码，距离0–128；`lib/solas_water.glsl:106` gamma域加光 | **本轮修复结构错误**；不新增pass/buffer。光束形状仍取决于低步数积分，不能由重建证明 |
| 水下介质/焦散 | Photon `water_fog_vl.glsl:17` 16–25步、`:72` 消光积分 | `light_shafts.glsl:48` 40格；档位4/7/10步；`global/water/caustics.glsl` 六波场；`shaders.properties:21` 1/4或1/2宽高 | 参数和介质接口均不同。完整迁移散射/透射需要新buffer或重排现有通道；本轮不做。重复点阵与颜色观感需实机确认 |
| deferred 全分辨率 MRT | Miniature `textured_lit.fsh:130` 前向MRT067，最终SSR，没有独立deferred | `program/deferred.fsh:11` 输出0/4；`:226` 两份RGB，`program/water.glsl:165` 读取未施介质的4 | **架构差异**。两R11G11B10写出8B/像素，1080p约16.59MB/帧；删4会破坏透明背景。单个4B附件写出约8.29MB/帧，能否免除它取决于水雾/反射的pass重排 |
| 平面云地形后浪费与穿透 | SuperDuper `volumetricClouds.glsl:9`、Nostalgia `composite1.fsh:433` 地形终点 | `clouds_planar.glsl:197` 新距离参数；`program/deferred.fsh:192` 传入地形距离 | **本轮修复结构错误**；不新增资源。仍保留6–64步及静态抖动，天空成本不变 |
| 主世界阴影成本/关闭档 | Miniature `getLightStrength.fsh:25` 条件后一次读；AstraLex properties `:470` pass控制 | `shaders.properties:52` separateAo / shadow.enabled；`:172` NO_SHADOWS；`global/lighting/shadowmap.glsl:143` 角点材质配对 | 简化采样是画质取舍，非等价调参；关闭档已存在。实体提交、阴影pass时间尚无实机数据 |
| 下界AO/岩石质感 | Miniature properties`:19` 与 `textured_lit.fsh:67`；VisualVibrance directionalLightmap`:29` | `program/lit.vsh:49` alpha→vertexAO；`lit.fsh:215` 消费，`:371` 诊断；`surface_emission.glsl:23` peak4.8，`:39` cap2.6 | AO数据供给已显式声明，运行值仍未知；岩石强度属于**参数/美术问题**，光源方向属于结构问题。本轮未改值，不能把体雾当表面改进 |
| 末地石发光 | Miniature `textured_lit.vsh:92` 方块ID；Kappa独立 emission 输出 `world1/deferred3.fsh:276` | `block.properties:45` end_stone分组；`surface_emission.glsl:7` material11门控；`global/post/bloom.glsl:117` 专用发光量 | 前轮已由颜色门控改成身份＋独立bloom源；当前结构具备，不需新buffer；强度、材质保留与泛光半径需实机确认 |
| 末地平行条纹 | Kappa `world1/deferred3.fsh:140` 沿光偏移、`:324` 几何法线偏移 | `global/lighting/shadowmap.glsl:236` 斜率项、`:246` 深度项；`lib/transforms.glsl:70` 自有末地投影 | 坐标结构与采样足迹不同，不能照搬Kappa常数。阴影图接收面问题需实机确认；本轮不改bias，不用时间抖动掩盖 |

## 4. 整改优先级与本轮取舍

| 优先级 | 改什么 / 参考依据 | 收益证据或可预期的局部收益 | 风险 / 决策 |
|---|---|---|---|
| 1，已做 | 水下重建，借鉴FastPBR逐点判定、Shrimple配对读取 | 解除第四根存储域平均造成的非线性压暗；消除先混合距离再判定 | 同一个亮暗混合位置会更亮；四个近邻替代原宽核后可能更显采样颗粒。必须实机观察，不能称“光束收敛” |
| 2，已做 | 云的不透明终点，参考SuperDuper/Nostalgia | 不再为地形后的云读取噪声，不能把后方命中叠到前方地形；合成场12→2读 | 山体/云交界外观改变。保留原采样格点，避免终点变化重新分配全部样本 |
| 3，未做 | 给Astra SSR建立可选的较低追踪预算，参考Miniature10+4与现有96+6 | 雨天有效水洼像素可少读深度；并非所有像素受益 | 现有96步特意处理薄植被；必须同时接受漏反射风险。不能仅调10步后声称等价 |
| 4，未做 | 无历史的低分辨率云＋当前帧深度重建，参考Shrimple/FastPBR空间配对 | 减少天空上的积分像素数，覆盖本轮优化不到的大面积天空 | **需要云颜色/覆盖率及距离buffer、新生成pass或复用pass与重建入口**；薄云、轮廓、静态噪声风险高。禁止借TAA补质量 |
| 5，未做 | 下界表面方向光/实际光源与遮挡，参考VisualVibrance、现有体素光 | 把法线质感与简单岩石增亮分开 | lightmap梯度不是实际光源方向；体素捕获缺口也未实机确认。先前的AO诊断可直接观察，无依据不再调peak |
| 6，未做 | 拆解raw HDR与displayed HDR的生命期，参考Miniature前向组织而非照删MRT | 若能复用现有场景目标，可减少全屏写出 | **管线改造**：水背景、SSR取样阶段、介质施加顺序必须一起设计；可能增加别处pass抵消节省，本轮无法给净收益 |

全部新增逻辑为 Astra 独立实现，仅学习上述数据配对和有限积分区间思路；没有逐行移植这批专有源码，因此没有新增第三方代码条目。原有 Solas/Complementary 来源注释保留。

## 5. 实际改动、数值与限制

### 第一项：水下

`global/water/light_shafts.glsl:91` 使用四个双线性角点的 `texelFetch`，各自先四次方解码再加权；RGB 和 alpha 在判断前都不经硬件插值。距离权重仍按每格0.25衰减，但不再把24格以上的差异钳成同一个权重。两端距离均限制0–128，权重和最低为 exp(-32)，归一化分母使用1e-30而非1e-5，避免远邻全被分母吃掉。`program/scattering.fsh` 更新了存储接口说明。

消费端 `lib/solas_water.glsl:106` 先进入 gamma 域、混雾、加 shafts、再作2.2次方。本轮保持它的**加法强度域**，没有将这里的数值称为物理线性辐亮度或改造完整水色管线。

先扩展现有水下探针覆盖实际 resolve，再修改shader。扩展时原路径明确不满足等权均值、远端颜色及边缘要求。现路径测量：

| 合成输入 | 原路径 | 修改后 |
|---|---|---|
| 黑色与(0.2,0.6,1.0)等权，距离权重相同 | (0.0125000,0.0375000,0.0625000) | (0.1000000,0.3000000,0.49999994) |
| 匹配远端彩色光束 | (0.1980293,0.5940881,0.9901465) | (0.2000000,0.6000000,0.99999982) |
| 屏幕亮边，接收距离封顶128 | (0.0632813,0.1898438,0.3164065) | (0.2000000,0.6000000,0.99999982) |
| 4格黑表面拒绝100格光束，泄漏max通道 | 3.738e-11 | 3.775e-11 |

最后一行没有改善声明，两条路径在这个特定极端输入都很小。接口仍4次纹理调用，但从4次线性读取改成4次点读取；不等同于已量出纹理带宽下降四倍。实际 RGBA8 量化、游戏深度边缘、运动、透明物体与有色投影不在这个浮点纹理算例中。

证据：[光束探针输出](../qa/refs-water-resolve.log)、[水下完整入口输出](../qa/refs-water-full.log)、[第一项三档编译](../qa/refs-water-compile.log)。新增覆盖放进现有 `qa/tools/underwater_light_probe.py`，`underwater_shaft_gate_probe.py` 仍调用它；GPU执行器增加可选合成纹理输入，没有拷贝一套Python着色函数冒充现行GLSL。

### 第二项：云

`global/atmosphere/clouds_planar.glsl` 增加带 `maxRayDistance` 的重载。原单参数天空入口仍使用完整距离。地形调用在原有云入口筛选后传入终点。原云层与可见水平范围确定的步长保持不变，每次密度读取前判断样本是否已到地形。

`qa/tools/cloud_occlusion_probe.py` 编译执行现行云函数，将噪声读取替换为计数的空密度场；它测的是控制流，**不输出云画面**。眼高64、视线y=0.1、云层183–201，交点1190–1370，原12步：

| 终点 | 密度读取数（256×256所有静态抖动位置） |
|---|---|
| 地形1100，在入口前 | 0 |
| 地形1220，在层内 | 2 |
| 地形1500，在层后 | 12 |
| 天空单参数入口 | 12 |

没有新pass、新buffer或画质档。64步上限仍在；若天空占满屏幕，这项不会减少它的云积分；原来先命中云并退出的像素也可能没有性能收益。

证据：[云控制流计数](../qa/refs-cloud-occlusion.log)、[第二项三档编译](../qa/refs-cloud-compile.log)。两次均运行任务要求的 `python qa/tools/compile_glsl.py --profiles PERFORMANCE BALANCED ULTRA`，结果均为270链接、0失败、27 compute；运行硬件为RTX4050 Laptop。编译不代表Iris实机集成和可见效果完成。

### 仍需实机确认与无法给出的结论

- 水下：光束颜色、亮暗混合后的强度、静态颗粒、轮廓漏光；焦散是否重复点阵、是否随观察移动闪烁。数值输出不能证明这些。
- 云：从云上看山体、云层与山体相交、远地形截断处是否稳定；没有整帧GPU计时，无法给出FPS增益。本轮也未解决原有“眼睛在云层内部时地形分支被外层条件排除”的显示缺口（`deferred.fsh:190`），仅修改该分支实际调用后的终点。
- 下界：`DEBUG_VERTEX_AO=1` 的真实输入变化尚未读取；熔岩湖正上方岩石朝下面、泛光是否发白仍需确认。没有重新替用户决定岩石峰值。
- 末地：石材身份与bloom通道已有代码，但发光观感未确认；掠射阴影条纹、bias造成的脱离和地表高光都未实机观察。9/25 后续已移除会突出内部接缝的格线倒角。本轮未改Kerr，也没有用其离线图证明其他内容。
- 边界：没有十包的统一游戏场景、GPU计时、厂商交叉数据，不能给参考包FPS排行。本文价值排序是针对当前Astra问题的可用性排序。
