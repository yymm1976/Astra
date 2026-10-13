# Astra/shaders 全量独立审查：step5 替代

日期：2026-10-11  
审查范围：当前工作树 `Astra/shaders/` 中由 Iris 调度的活跃着色器、资源声明、选项条件及各阶段生产/消费关系。实施前读取了 `docs/当前工作.md`、`docs/实现与限制.md` 和个人开发工作流中与审查相关的章节；源码决定本报告判断，Git 仅作只读查看。

用户指定的目标模型入口为 `codex/gpt-6-luna`。本会话没有模型切换或子 Agent 调用工具，因此我不能证明本次会话实际运行在该入口；本报告由当前可用的主会话完成，不将目标入口写作模型执行证明。

## 判定

- **P0：未发现源码可证实项。**
- **P1：未发现源码可证实项。**
- **P2：1 项。** 树叶倒影仍受屏幕空间深度步进限制，稀薄叶片会漏过射线并形成缺失区域；这是可由当前追踪方式确认的覆盖缺口。局部画面比例仍需实际场景观察。
- 光束稀疏、阴影细边锯齿和水面开销相对 Steadfast 的程度，源码能说明采样上限、分辨率和热点，不能据此证明具体画面或整帧速度。内外太阳圆盘路径在源码中使用相同的角尺寸/贴图尺度关系，没有发现确定的形状分支不一致。

## 九模块覆盖

### 1. 入口调度、资源格式、清屏、mip、翻转与宿主

入口从根目录 pass wrapper 进入 `program/`：主要光栅 wrapper 为 GLSL 400 compatibility；下界 `world-1/shadow.vsh`、`shadowcomp*.csh` 和末地 `setup*.csh` 使用 GLSL 430，以支持 3D integer image 原子操作和 compute。`shaders.properties` 明确启用主世界水状态、天空缓存、延迟槽、散射、Bloom、曝光、AA 和末地/下界覆盖；`composite.fsh` 写水体状态，`deferred*.fsh` 组合场景，随后依序进入 `composite1` 至 `composite8` 等阶段。根目录与 `world-1/`、`world1/` 各自有 wrapper，维度 pass 使用独立宏和附件约定。

生产输入与消费者的主要对应关系如下：

| 附件 | 生产与消费 | 资源行为及选项 |
|---|---|---|
| `colortex0` | GBuffer/`deferred` 场景 HDR；水、反射、后处理读取 | `R11F_G11F_B10F`；基本场景格式在 `lib/water_buffer_formats.glsl`。清屏色在 `lib/settings.glsl`。 |
| `colortex1` | `composite2` 的空气光束或水下积分；`display`/水体合成消费 | `RGBA16F`、显式清零；按空气光束或水下样本数取半分辨率/四分之一分辨率。 |
| `colortex2`,`colortex7` | Bloom 预滤波；分别由空气显示、水下 Bloom 消费 | Bloom 开启时四分之一分辨率；最终采样方才请求 mip。 |
| `colortex3`,`5`,`6`,`28` | 材质/水面 GBuffer、三 texel 水状态、实体颜色与线性视深 | `colortex3` 清值同时承载天空光标记和无效水面零值；`colortex5` 记录水界面；`colortex6` 为 3×1、`RGBA32F` 状态；`colortex28` 全分辨率，主世界 `RG32F`，末影反射重用时 `RGBA16F`。 |
| `colortex8`,`9`,`11`,`31` | 末地照明/本帧天空/星点目录，和下界粗糙岩石反射复用 | `colortex8` 316×1 `RGBA32F`；`9` 原生分辨率；`11` 小型环境缓存；`31` 1024×384 `RGBA32F`，只供末地 catalogue 初始化。 |
| `colortex10`,`15–18`,`19–27`,`29`,`30` | 曝光、TAA、AO/SH、波面光照场和屏幕历史 | 一 texel/低分辨率/固定世界网格按用途分配；写入程序声明具体格式和清屏行为。 |

`display.fsh` 对 Bloom 目标启用 mip，`light_shafts.glsl` 对刚写出的 `colortex29` 启用 mip；Iris 本地运行时材料显示组合 pass 按其声明生成 mip 并管理附件翻转。资源翻转没有在包属性里另列 `flip.*` 规则；历史数据依赖 Iris 的颜色附件翻转及本包内的帧、视口、维度/介质有效性检查。这个结论依赖 Iris 宿主语义；源码不能证明玩家当前安装版本、驱动和实际调度实例。`iris.features.optional=CUSTOM_IMAGES COMPUTE_SHADERS` 只声明可选宿主特性，本包没有完整的无 compute 下界/末地替代链；`docs/实现与限制.md` 所述 Iris 1.11.2 前提与源码一致。

### 2. 阴影投射、接收、过滤、彩影、覆盖和焦散

投射器是 `shadow.vsh` → `program/shadow.vsh` / `program/shadow.fsh`。主世界保持原有投影矩阵、阴影光方向和径向畸变；顶点阶段先保存未畸变坐标再畸变投影，片元阶段只在水面平面记录需要时修正深度。水面深度/高度记录进入 `shadowcolor0.r`，彩色透明体透射进入 GBA，水焦散焦点记在水记录 alpha。`shadow_solid` 入口保留被分配到 solid layer 的真实水模型记录。接收端 `global/lighting/shadowmap.glsl` 与 `diffuse.glsl` 按投影覆盖、世界位置和接收面深度先判定，再分别读取 opaque/all-caster 阴影并作过滤；表面和体积水使用水位记录；彩影颜色只沿对应 caster 透射路径混合。`sss.glsl` 和 `diffuse.glsl` 区分叶片 wrap、地面植被和一般材质的直接光及透射；阴影缺覆盖时按类型走受限 fallback。选项由 `SHADOWS`、`ENTITY_SHADOWS`、彩影、SSS 和 filter 质量控制。

未发现会改变正常阴影投射结构的源码回归。细边锯齿在高太阳角、远距离和有限阴影 texel 下仍是预期残余：`shadowmap.glsl` 以 `SHADOW_SOFTNESS/shadowMapResolution` 定义过滤尺度，并对覆盖边缘做 fade；当前预算还会限制实际 shadow resolution/distance。仅凭源码无法判定用户画面中的细锯齿来自覆盖边缘、投影 texel 还是场景/驱动状态。后续若处理，应从接收端 footprint/filter 和当前有效分辨率入手，并保留现有主世界投射/投影路径。

### 3. 材质、直接/间接光、AO、SSS、体素、实体和手

根 GBuffer wrapper 将地形、实体、手、粒子、天气、未着色材质和水分别标记后进入 `program/lit.vsh`、`lit.fsh` 或 `unlit.fsh`。`lib/ao_material.glsl` 分类 AO 接收对象；`global/lighting/diffuse.glsl` 组合天空/环境、块光、手持光、直接日月光、阴影和彩影；`sss.glsl` 处理叶类与地面植被两种 wrap/transmission。SSAO 由 `program/ssao.fsh` 从几何元数据生产，延迟槽消费；可选方向天空光经 `prepare3` 写 SH 系数，并在延迟合成重评。AO/方向光只在主世界且满足阴影、强度和调试条件时激活。

手部通过顶点分类写入 hand 位，延迟/水下路径在重建深度时作 hand depth 修正；实体在 `colortex28` 记录已着色颜色与线性视深，水折射的每个有效端点可读取它。主世界各 GBuffer 的 MRT 声明按 SSAO、TAA、方向光和水选项拆分，metadata attachment 在 properties 里关闭混色，避免跨绘制串值。下界体素路径由 shadow 顶点阶段用 `imageAtomicMax` 采集 64³ 占用/发光源，再由九次 `shadowcomp`（step0 加 8 次传播）通过 A/B 体积场六邻居传播；接收器在 `nether_colored_light.glsl` 消费。图像和九个阶段都被 `SHADOWS && NETHER_VOXEL_LIGHT && BLOCKLIGHT_STRENGTH > 0` 门控。

源码覆盖了配置分支，没有发现可确定的 P0/P1 材质错误。下界传播是明确的九次 dispatch 设计；图像能力缺失时无等价回退，属于包的宿主要求和能力限制。

### 4. 水波、SSR、折射、介质、迟绘实体与两侧界面

`program/lit.vsh`/`lit.fsh` 生产水面几何、波法线和界面记录；`water_state.fsh` 从 `colortex5` 的界面数据及屏幕深度/历史状态推断当帧水位/类型，跨帧中断时回退到阴影水位。`program/deferred.fsh` 对场景写主颜色与无介质水背景 `colortex4`；`program/water.glsl` 的 `water_scene_path_transfer`、`water_sample_path` 对每个水面 ray-hit 端点单独求空气/水中路径，分别应用吸收、散射和雾。对水平/垂直角点不会把四个不同 endpoint 混作同一深度；`colortex28` 实体记录随同路径运输，已知实体部分覆盖时与背景按 alpha 组合。水上外表面、人在水中看水平界面、竖直流体/边界各走不同分支，TIR 保留。`SCREENSPACE_REFLECTIONS`、`SCREENSPACE_REFRACTION`、`WATER_WAVES`、`WATER_EFFECT_QUALITY`、吸收、折射强度与水面外观选项分别限制对应分支。

当前主世界预算模式水 SSR 最高为 20 次粗采样加 4 次细化；质量 0 为 12+4，质量 2 原始设定为 40+8，但主世界优化分支仍会压到 20+4。反射/折射都是屏幕空间深度命中，不能恢复视野外或深度缓冲未覆盖的几何。

### 5. 水下光束

`prepare4` → `itt_water_normal_cache.fsh` 每帧在 1024² `colortex29` 上生产 ITT 波面坡度及碰撞光；`composite2` (`scattering.fsh`) 根据 `water_state` 的实际水平水位与折射光方向，向 `colortex1` 积分水下光束。接收端在 `water_composite.fsh`（Bloom 开启）或 `display.fsh`（关闭）按四个低分辨率角点分别核验视线路程，并加入吸收/散射、最终太阳直射、天气透射和水下色调。`water_shafts_view` 同时修正 hand depth；界面/手、波浪关闭或零高度、无有效水面/太阳的分支返回空光束。入水高度用 12×20 栅格扫描并带连续性状态，不以固定世界海平面代替实际水面。

内部波面窗口积分是现行生产代码中的 **8 点 Gauss 节点与权重**；节点用于每个外层细分 cell 中平均碰撞光。它外层再由 4–10 个配置段、每段 4 个 shadow/光路采样点积分，预算模式最多 7 段。光束输出按低配置可降为四分之一屏幕分辨率，高配置为半分辨率；优化预算把路径窗口限制到 48 blocks，整体最大路径 128 blocks。太阳遮挡使用 `depthtex1` 上每帧最多 7×7 个窗口采样，水下体积沿外层节点做阴影投射接收检查。此结构保留了用户认可的 8 点内部节点和世界波面。

这为“光束偏稀/拥挤”提供了可量化的源码候选：低样本配置是 4 段×4 点且四分之一屏幕输出；当前默认/平衡配置是 7 段、半屏幕输出。缓存 mip 按视线角 footprint 选择 LOD，波面光照在近/远距离做平滑衰减；接收端再按四角路程差淡出不匹配贡献。它不是运行画面判定，也不证明简单加样本会符合用户期望。光束是高热点：外层每条水下屏幕射线最多调用 4×段数次水下阴影路径判定，且每次会处理 opaque/all-caster gather 与水位记录；随后每个节点查询波面缓存。单看源码不能把这个成本换算为某块显卡上的整帧时长。

### 6. 天空、日月、星云、天气和历史

`gbuffers_skytextured` 由 `program/sky.fsh` 画原版或程序圆盘；天空底色、星场、屏幕云和天气/雨水反射分别由天空/延迟、`cloud_screen`、weather/water 路径生产。主世界低频环境缓存和云阴影缓存用于不同消费者；它们不是同一个屏幕云历史。屏幕云 temporal 使用 `colortex24/25` 保存 resolved cloud 与代表距离/帧/视口元数据，由 deferred 消费；没有历史的云分支写 raw `colortex12`。TAA 内另通过 reactive 标记拒绝移动云、星、太阳附近历史。末地星云/等离子体层由 `global/dimension/end_plasma.glsl` 参与 `end_system.glsl` 的背景生成；末地天空独立在 `world1/deferred` 生产原生分辨率 `colortex9`，延迟合成读取；星 catalogue 在 setup compute 初始化后供末地天空及光环使用。天气部分保留雨、潮湿面与水涟漪分工。

圆盘检查：vanilla 模式的外部 `sky.fsh` 直接采样当前 Minecraft 太阳 sprite；水下 `water_transmitted_sun` 用同一资源路径，并按 `lit.vsh` 的 `1.12` 顶点扩大比率还原相同外部角尺度。程序圆盘模式两处都使用 `0.028` 太阳角半径。源码中两支尺寸对应，没有发现“水下太阳必然变圆、外部必然方”的通路差异；最终外观仍取决于当前 Minecraft 资源路径实际解析的 sprite、角度和折射画面，本次没有观察游戏画面。

### 7. Bloom、调色、AA、历史和颜色域

`composite1` 从 HDR 场景生成 quarter-res `colortex2`；若水下且 Bloom 开启，水体合成后 `composite4` 另写 `colortex7`。最终 `display.fsh` 在实际读取前生成相应 mip 并合成 Bloom。自动曝光的 `composite5` 将 64 个场景采样压为 1×1 `colortex10`，随后 display 读取；下界和末地没有这个计量 pass，使用维度手动曝光。TAA `composite6` 读写 HDR `colortex0` 与 `colortex15`，逐个核验历史双线性贡献的深度，做 YCoCg 邻域限制，并使用 `colortex16` reactive mask；`composite7` 在 history consumer 之后写 `colortex17` 状态。水下介质会拒绝场景 TAA 历史。FXAA 路径由 `composite8` 生成 display-linear/sRGB 显示输入 `colortex13`，final 仅做 FXAA；TAA 路径 final 直接呈现 display。调色顺序为线性曝光→tone map→sRGB→显示域色调/饱和度/对比度→暗角→输出抖动；最终输出被 clamp 到显示范围。

这条链的格式、颜色域及 AA 互斥条件在当前源码中互相吻合；未发现可由代码直接确认的颜色空间双编码或 history 附件写读顺序问题。历史有效性与 buffer 翻转需要目标 Iris 运行时配合，不能由纯源码推断玩家当前画面是否出现残影。

### 8. 下界和末地独立全链

下界专用入口 `world-1/` 使用独立 `DIMENSION_NETHER` wrapper。石材 SSR 的 `composite` 生产 quarter 采样格点/原生颜色载体 `colortex9,28`；`composite1` 按接收面法线、flags 和共面条件重建到主场景。启用 Bloom 时 `composite2` 使用独立 Bloom capture；地下火光由前述九步 voxel 链供 `lit.fsh` 消费。下界有独立雾密度和颜色路径，AO 与末地/主世界路径不同；相机介质下反射主动退出。对应选项为屏幕反射、Bloom、下界体素光和阴影/块光强度。

末地专用 `world1/` 的 `prepare` 写光照/圆盘遮挡缓存 `colortex8`，`prepare1` 写星体环境缓存 `colortex11`，setup compute 初始化 `colortex31`；`deferred` 写 `colortex9` 原生天空/光环底图，`deferred1` 完成地形/天空合成。末地水体/过世界体积雾/屏幕云专用阶段在 properties 关闭；Bloom 由 end 条件修改 capture 和最终天空 tone map。末地阴影保留独立 `world1/shadow`，而主世界水下 shaft 与泛用 composite 阶段不调度。检查了入口、生产附件、末端消费者、选项 gates，没有发现维度 wrapper 把主世界介质/缓存误读进末地或下界的源码证据。无 compute 特性时，末地 star catalogue 也依赖 Iris compute；当前没有可用的无 compute 等价路径。

### 9. 选项组合、档位、性能热点与当前说明

四个档位在 `shaders.properties:564–567` 配置。所有性能档都选 `OVERWORLD_BUDGET=1`；`lib/settings.glsl` 将主世界阴影上限设为 1536/112 blocks，预算 2 才会压到 1024/112。因而 `ULTRA` 行虽然设置 4096/256/96，实际主世界 shadow uniforms 仍按预算封顶；下界与末地不受主世界 budget 宏影响。这是源码注释明确描述的预算上限，不据此报为 BUG，但它会让 Ultra 的“阴影分辨率/距离”设定不按字面生效。若 Ultra 需要真实 4096/256，应从档位预算选择与 profile 意图统一，或把有效上限在选项说明中说清楚。

水下 shafts 的 prepare 缓存 gate 还要求启用波浪且高度大于零；shafts 选项自身允许与波浪关闭组合，此时 `water_shafts_march` 会直接返回空体积。它是水波照明对波面数据的功能依赖，不是悬空采样，但界面没有把依赖写成联动条件；在此组合下用户会看到 shaft 选项开启而没有水下波面光束。建议说明这个依赖，或使选项组合表达一致。

可从源码定位的成本上限：主世界优化模式阴影 1536 texel 上限、阴影采样 gather/filter；水 SSR 20+4 最大步进及每 endpoint 的路径重建；迟绘实体颜色记录和折射双侧介质 transport；水下缓存固定写 1024²、每个有效视线最多 7×4 外层阴影积分样本加 8 点内部波面积分；Bloom 每最终像素读取四级；下界最多九次 64³ compute 调度。它们只是源码运算与分辨率描述，没有设备级 GPU 计时、玩家当前选项快照或整帧归因，不能据此声称水面/水下优于或劣于 Steadfast，更不能推出 144 FPS。可对照的本地 Steadfast 源码显示其水面使用四个 ripple、两个 crest、逐像素波高/法线和 ray march；Astra 的额外可见热点是双面介质路径、彩色影子/端点记录、复杂 screen trace，以及独立 1024² shafts producer。具体差值取决于场景中实际激活的功能和水像素覆盖率。

`docs/当前工作.md` 和 `docs/实现与限制.md` 的已完成描述没有替代本次源码判断。可从文档找到的问题背景只用于定位；实机加载的资源包、Iris/Minecraft 版本、GPU、当前画面和帧时间均为未知。单独组件的源码运算/独立画面结果不代表完整世界帧率。

## P2 详项

### P2 — 叶片屏幕空间反射仍会漏命中

**触发：** 水面启用 SSR；反射射线擦过薄叶、叶片洞隙、屏幕边缘或有限深度采样间隔。

**落点：** `Astra/shaders/global/water/raytrace.glsl:125` 的候选深度 footprint 验证，粗步进循环约 `282` 行，细化约 `385` 行及后续命中判定。主世界预算最多 20 粗步+4 细化（约 `38–53` 行），只从当前 `depthtex0/1` 和当前屏幕 texel 确认交点；没有树体几何/体素遮挡数据供该 SSR 重建。

**后果：** 叶片被当前相机看见，但水面反射射线未在离散 texel 上确认叶片时，倒影会有缺片或完全没有；提高水面颜色过滤不会找回缺少的射线命中。文档中独立复杂树冠画面仍有遗漏的记录与该限制相符，但不是游戏实机覆盖率证明。

**建议：** 若继续修复，先针对薄叶候选覆盖/射线步幅补足可确认的几何命中；比较更密深度搜索与使用额外几何信息的成本。保持世界波面与正常阴影投射路径不变；不要用独立简单场景改善代替最终游戏场景结论。

## 未能从源码确证的运行事实

实际载入的 Minecraft 太阳 sprite、Iris 版本和 GPU；当前光束是否按期望密度呈现；水体开销相较 Steadfast 的实测差值；太阳水下与外部最终画面；阴影细锯齿在用户指定场景中的来源；整帧是否达到任何目标帧率。本报告只确认当前源码路径及其条件，不把这些未知项写成已经解决或已经发生的实机结论。
