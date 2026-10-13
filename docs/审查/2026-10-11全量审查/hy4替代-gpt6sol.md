# Astra 独立全量源码审查：hy4 替代 gpt6sol

日期：2026-10-11。实际会话入口：`gpt-6-sol`，用户指定的本机目录入口为 `codex/gpt-6-sol`。替代原因：原 `hy4-preview` 请求因 429 中止，用户已授权改由 GPT6Sol 继续独立审查。入口标识来自本次任务与会话指派，不声称从服务端另行鉴定了底层权重。

本报告独立覆盖九模块，没有继承原模型的审查结论，没有读取其他审查报告或主审裁决，没有参与修复。先读取了 personal-dev-workflow 的相关要求、`docs/当前工作.md`、`docs/实现与限制.md`、根 README 及其当前入口。文档用于确定保留行为和已承认边界，问题依据来自现行代码的数据流。审查范围包含现有实现和本轮变化，并非仅 Git 差异。唯一写入是本报告。

代码根目录为 `C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/Astra/shaders/`；下文覆盖清单中的文件名均相对该目录。问题位置给出绝对文件链接与实际行号。P0 表示整体不可用或严重破坏，P1 表示主要功能错误，P2 表示局部功能或配置说明错误。没有将未得到当前游戏事实的效果反馈升级成已证实问题。

本次确认 **0 个 P0、0 个 P1、3 个 P2**：方向天光与 AO 同开时的错误 bent normal、水下太阳在中心过地平线时硬切断、Bloom 选项说明遗漏预算覆盖条件。水下月盘没有补绘属于已读到的功能边界，未作为新 BUG。没有整帧数据，不能判断原生 1080p 平均 144 FPS 是否达成，也不能给出相对 Steadfast 的当前整帧差值。

## 1. 入口、程序调度、GLSL、附件、资源与宿主

**实际覆盖文件与交界。** 逐个读取根目录、`world-1/`、`world1/` 的全部现有 `.vsh/.fsh/.csh` 包装入口，包括各类 gbuffers、prepare、deferred、composite、final、shadow、主世界 shadow_solid、下界 shadowcomp 至 shadowcomp8、末地 setup 至 setup2。结合 `shaders.properties` 全部调度/尺寸/混合/纹理/图像/表达式声明，读取 `lib/settings.glsl`、`uniforms.glsl`、`transforms.glsl`、`encoding.glsl`、`water_buffer_formats.glsl`、`scene_buffer_formats.glsl`、`cloud_buffer_formats.glsl`、`surface_buffers.glsl`，以及 `program/deferred_slot0.fsh`、`deferred_slot1.fsh`、`deferred_slot2.fsh`、`volume_slot.fsh`、`composite.fsh/.vsh` 和公共全屏顶点入口。也读了 `voxy.json`、两份 Voxy emit 入口及 `program/lit_voxy.fsh`。

主世界 prepare 的低频天空表、环境反射、云影、SH9 和水波源图条件分别与实际 include 相配。deferred 的排列按平面云、SSAO、体积雾的存在选择，场景合成位于最后；debug 模式走直接场景显示。透明几何之后 composite 更新水位，按条件安排 Bloom、空气/水下散射、水下合成、曝光、TAA、状态写入与 FXAA 显示。下界重定向反射与 Bloom 槽，末地重定向天空和照明槽，未将根目录的水下程序视作它们的活跃消费者。

**附件核对。**

| 输入/附件 | 生产者 → 消费者与格式要点 |
| --- | --- |
| depthtex0 / depthtex1 | 最近表面 / 不透明背景。deferred 读取 0；水反射与背景配对读取 1，并用实体记录补充迟绘端点。手的压缩深度在对应重建路径另处理。 |
| 0 / 4 | 几何 HDR 场景 → deferred 的显示场景与背景副本。0 为 R11F_G11F_B10F；4 在主世界有效 Bloom 路径为 RGB16F，其余路径沿用声明的紧凑格式。水下 Bloom 合成会再次写 4，发生于水背景消费之后。 |
| 1 | scattering 写 RGBA16F。空气 RGB/alpha 与水下 RGB/端点距离有不同含义；消费按介质分开。尺寸由有效空气光束或水下区间数决定，无消费者时为 1×1。 |
| 2 / 7 | 空气/一般 Bloom 与普通水下 Bloom 的四分之一尺寸紧凑 RGB 捕获。mip 请求在显示消费者声明，源图生产在前。 |
| 3 / 5 / 6 | 3 为 RGBA8 光照标记、法线和地形附加量；5 为水界面高度/侧面记录；6 为 3×1 RGBA32F 水位和连续帧信息。6 不逐帧清空，消费有帧戳/相机/时间保护。 |
| 8 / 9 / 11 / 12 / 14 / 18 | 末地 316×1 RGBA32F 照明/形体数据；9 依维度为末地天空或下界反射；11 为环境图；12 按条件复用低频天空表或当前屏幕云；14 R16 云影；18 为 9×1 SH9。没有把跨维度同号附件解释成同一有效负载。 |
| 13 / 15 / 16 / 17 / 22 | FXAA 的 RGBA16 显示颜色/亮度；TAA 的 RGBA16F 历史颜色/深度；R8 reactive；4×1 RGBA32F 历史状态；RGBA16F 植被运动。关闭相应路径时调度与尺寸同步收缩。 |
| 19 / 20 / 21 / 26 / 27 | 环境光、RGBA8 法线/AO、半尺寸 RGBA16F AO/深度/法线、RG16F bent normal、方向天光响应。只有实际 SSAO/方向天光组合产生相应数据。 |
| 23 / 24 / 25 | RGBA16F 体积雾 S/T；平面云颜色和代表距离/状态历史。23 的清空值是恒等介质；24/25 由独立云历史保护消费。 |
| 28 / 29 / 30 / 31 | 主世界 28 是清空的 RG32F 实体四项半精度打包记录，下界 28 是 RGBA16F 反射元数据；29 是 1024² RGBA16F 同帧波斜率/碰撞光量和零号窗口元数据；30 是下界 3×1 效果历史状态；31 是末地 1024×384 RGBA32F 星表。 |

核对了目标输出槽、每附件混合覆盖、持久附件有效标记和同帧交接。主世界实体记录采用有限正浮点载体，打包偏移使最低有效载体不是易丢失的非正规数；零输出的覆盖 alpha 为 0，通过 28 的独立混合保留此前记录。其余几何元数据附件关闭颜色混合，水界面记录由自身有效 alpha 控制。代码并没有给紧凑 RGB 附件虚构可保存的 alpha。

资源覆盖包括 `textures/` 中全部 PNG 文件的尺寸/通道头信息、已有 `.png.mcmeta` 和所有活跃绑定：64² Steadfast/ITT 噪声、512² Solas 噪声、256²云水噪声、128×7680 的两张活跃雨涟漪表、4096²末地传输图、1024²传输元数据和流场、514×1043 流场 mip 图集。核对了重复/钳制与用途；第三张雨涟漪、Bliss 下界噪声没有活跃绑定。太阳纹理由宿主活动资源包提供，26.1 前后的路径分支不同。

为核对宿主的同帧纹理交接，按需读取了 `_analysis/iris-runtime/CompositeRenderer.txt`、`ShadowCompositeRenderer-recheck.txt`、`ComputeProgram-lifecycle.txt`、`IrisImages-lifecycle.txt`、`ImageClearPass-nether-source-activity.txt` 的相关字节码。`CompositeRenderer.txt:613` 起实际先按 `stageReadsFromAlt` 选择纹理并生成 mip，再在 :620 调用 setupState；compute 路径及 shadow composite 的 memoryBarrier 调用也可直接读到。这支持现行“在消费程序请求上游 mip”的安排，不把 shader 注释当作宿主证据。

**覆盖结论：没有在此模块确认新的 P0/P1/P2。** GLSL400 主世界实体/水入口显式要求 packing 扩展；下界顶点图像写入和 compute 使用 GLSL430；末地 setup2 的空 dispatch 保留了前一 setup 写入后的宿主交接位置。包装入口与程序输出没有发现可证实的槽位错接。

**边界与缺失事实。** Voxy 仍是明确的空实现；完整三维度需要 compute/custom images，`iris.features.optional` 并不构成无这些能力时的完整实现。这些是现有能力边界，不新增兼容性 BUG。没有读取本次实际加载的资源包太阳像素、全部宿主实现或当前驱动状态；PNG 内每个 texel 的数值正确性也没有逐项鉴定。不能由本地字节码推断所有 Iris 版本相同。

## 2. 阴影投射、接收、过滤、彩影、焦散与覆盖边界

**实际覆盖文件与交界。** `program/shadow.vsh/.fsh`、主世界 `shadow_solid` 入口；`global/lighting/shadowmap.glsl`、`diffuse.glsl`、`wind.glsl`；`lib/distort.glsl`、`transforms.glsl`、`water_wave_lens.glsl`；`global/water/caustics.glsl`；`program/lit.vsh/.fsh` 的投影传递和片元导数入口；settings 的实际分辨率/覆盖/实体距离常量及 properties 的 culling、实体/地形提交、阴影混合声明。

投射链是方块身份与风摆 → 共用世界/影空间转换 → 径向 XY 投影和 Z 压缩 → 阴影深度与 shadowcolor0 配对记录。主世界非水投射片元先求原投影平面导数，使用保守深度修正；水平水面保存有效世界水高和焦散响应，非水保存无水标记及逐投射物彩色透射。solid 入口只在其限定的无 alpha 裁切地形入口省略贴图读取，没有删除公共投影或波动结构。

接收链中 lit 传未畸变投影，片元在材质分支/alpha 裁切之前计算接收面斜率；shadowmap 在四个影图纹元中心逆径向投影，参考深度取中心与外推平面的较小值，再分别与 shadowtex0/1 比较，最后双线性混合。软件 gather 的角序与硬件四次 compare gather 的选角对应。水和玻璃透射身份、彩色记录与深度角点保持逐项配对。主世界水底焦散的曲率波场与体积光束的 ITT 碰撞光量是两个用途，消费链没有额外把水底焦散叠入光束。

中档原生接收面中心完全亮/完全不透明暗时停止，混合边缘追加两组，权重连续且方向沿中心可见性梯度；高档四组，低档一组。世界单位软半径限制与用户柔和度共同作用。覆盖同时检查世界距离、径向影图边界和 Z 范围；水光束的体积查询不借用表面斜率。末地使用自己的正交范围与源方向，下界影阶段承担体素采集，未误读为主世界式投影消费者。

**覆盖结论：没有确认新的 P0/P1/P2。** 正常投射/接收结构没有被本报告建议替换。影图内先比较再插值、角点颜色配对、有限接收面深度限制均实际存在。

**取舍影响与疑点。** 中档中心四角未覆盖的极细投射物可能不触发额外组；预算上限、远端高草裁剪和影图有限覆盖会损失部分细边。这是已说明的过滤/覆盖取舍。用户“锯齿仍明显”缺少当前太阳方向、接收距离、档位和改动后游戏画面，不能仅凭此推断新深度错误，也不能宣布现行沿梯度柔化已经解决。

## 3. 材质、直接/间接照明、AO、SSS、体素、实体与手

**实际覆盖文件与交界。** `block.properties`、`entity.properties`、`item.properties`；`program/lit.vsh/.fsh`、`unlit.fsh`、`scene.glsl`、`ssao.fsh`、`sky_irradiance.fsh`；`global/lighting/diffuse.glsl`、`blocklight.glsl`、`sss.glsl`、`wind.glsl`；`lib/ao_material.glsl`、`ao_resolve.glsl`、`sky_directional.glsl`、`sky_sh9.glsl`、`wet_material.glsl`、`rock_material.glsl`、`surface_emission.glsl`、`environment_brdf.glsl`、`surface_buffers.glsl`、`color_controls.glsl`、`colors.glsl`；下界体素生产与消费另详模块8。

方块/物品/实体映射经 lit 顶点写入 faceData，片元按 material 消费，覆盖水、树叶/植物、玻璃冰、发光与门户、末地石、岩石、湿材质及实体染色。AO 与材质 alpha 分离；SSS 包含 wrap 与有限反向透光，手持光使用玩家头部相对位置并与普通方块光分工。动态植物顶点与影图使用同一风函数；TAA 的前帧植物位置从未形变位置重新计算。实体/手及透明路径的响应和元数据槽按宏组合核对，未把不参与 AO 的对象算入其有效采样集合。

SSAO 生产链是符合条件的全尺寸地形法线/AO → 半尺寸最近合格接收点和局部深度核 → 21/26 → deferred 按深度、法线一致性重建 → 只扣除环境光额外遮蔽，并在双开方向天光时重算 SH9。直接光、发光、手持光没有被整帧乘一个 SSAO 标量。

### P2-A：bent normal 只累积遮挡方向，可能转向遮挡物

- **触发条件：** 主世界 `SCREENSPACE_AO`、`DIRECTIONAL_SKYLIGHT`、`SHADOWS` 同时开启，AO_STRENGTH>0，空气侧合格地形接收点附近有少量凸起遮挡物；其余核点是天空、同平面或超出半径。默认双关不触发，但该组合是 GUI 提供的有效功能。
- **准确位置：** [ssao.fsh:90](C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/Astra/shaders/program/ssao.fsh:90)、:95、:98 的提前 continue；[ssao.fsh:113](C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/Astra/shaders/program/ssao.fsh:113) 仅对剩余遮挡点累积 `direction*seen`；:129 直接归一化。消费是 [ao_resolve.glsl:83](C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/Astra/shaders/lib/ao_resolve.glsl:83) 至 :89 的 SH 天光差值。
- **具体错误与依据：** 当前方向集合不是未遮挡半球的平均，而是“通过遮挡筛选的真实表面方向”平均。以向上法线、半径1格为例，唯一贡献点 delta=(0.60,0.06,0) 满足高度偏置；它的 sampleBlocked 约0.026、seen约0.934，满足 :129 条件。其余平地/天空点全部被跳过，bent normal 因而变成几乎横向、朝这个凸起点的方向；标量 AO 却只降低约0.4个百分点。这样很小的接触遮蔽可以令天光朝向转约84°，SH 有方向差异时会产生相应错误增亮/变色/变暗。代码注释所称的未遮挡方向均值与实际累积集合不相符。
- **建议：** 用完整可见半球方向集的估计，或从有已知无遮挡均值的法线方向响应中扣除遮挡方向矩；低有效覆盖时保持几何法线。不要直接将少量剩余遮挡物方向归一化成无遮挡方向。此建议不改变标量 AO、SSS、正常阴影结构。

**覆盖结论：本模块确认上述一个 P2，没有确认 P0/P1。** 未据此否定独立的方向天空光或标量 AO 链。

**缺失事实。** 实体没有可靠的每实例前帧变换是已知边界；当前 reactive 处理不是实体运动重建。没有当前材质资源包及具体实体绘制时序画面，不扩展成所有实体/手均有错误。

## 4. 水波、反射/SSR、折射、介质、迟绘身体与两侧界面

**实际覆盖文件与交界。** `program/water.glsl` 全部主/次分支、`lit.vsh/.fsh` 水和实体入口、`deferred.fsh` 的 0/4 分工；`global/water/surface.glsl`、`raytrace.glsl`、`refraction.glsl`、`absorption.glsl`、`optics.glsl`、`medium_state.glsl`；`lib/water_entity_record.glsl`、`water_interface_record.glsl`、`water_surface_budget.glsl`、`environment_brdf.glsl`、`itt_water_waves.glsl`、`solas_water.glsl`、`water_wave_lens.glsl`、`wet_material.glsl`。太阳窗口交界详模块5，水位和整体介质详模块5/7。

已认可的世界波面仍由四涟漪+两波脊及原权重、速度、幅度形成。预算内单次视差共享噪声四角的键仅在同周期格命中；新小数位置重新插值，跨格重读，没有把旧位置梯度当作新位置梯度。远处细波足迹进入 roughness；水下水平面使用 ITT 法线，其他维度沿各自水波分支。

SSR 从镜头空间射线进入投影空间，按 depthtex1 的深度查询限额推进，预计叶片交点和细化四角的候选必须同时满足粗区间、自身纹元和反射侧条件。命中坐标再交由颜色/端点配对层，而非取一张模糊颜色配一个无关深度。连续背景的快速足迹在无实体、无天空角、同侧且传输容差内共享一次路径传输；断层、实体、体积空气差异回到逐角路径。手动档更宽反射核与预算单足迹区别实际存在。

迟绘身体链：实体不透明片元在施介质前写 28 → `water_entity_decode` 恢复颜色/自身 view depth → 水路径将其与 depthtex1 背景比较选择端点 → 普通水平面、侧流水、窗口、折射距离共用该选择。分数透明实体不写有效身体记录，独立混合保留先前不透明记录。冰反射只用环境，不进入普通水平水的 SSR/水深逻辑。侧面薄水沿独立配对背景和短水路，不生成水平 Snell 天空窗口。

水上水平面将界面到背景的水中传输与相机到界面的空气段分开；水下窗口用精确 Fresnel/TIR，几何与反射射线来自实际相机，窗口水平中心由玩家头部锚定。透射空气段另处理空气雾/体积，整体相机水段在后序只处理一次。对用户认可的第三人称窗口近似，不能因其不是完全相机物理窗口而新增 BUG。

**覆盖结论：本模块没有另行确认 P0/P1/P2。** 模块5的水下太阳问题属于此界面与天空的交界，不重复计数。

**已知影响与未确认项。** 屏外或被原视角遮挡的树叶没有屏幕深度；有限粗查询仍可能跨过错层树冠。现行自纹元接受解决的是已采交点身份，不保证采到全部叶片。预算反射渐退、单足迹锐化、连续水底共享传输、深水散射与迟绘单层记录各有明确条件；它们的存在不证明用户“树叶倒影缺失”已解决，也不能以该旧反馈证明目前仍有某个颜色槽错误。分数透明实体、多层透明排序和水体拓扑属于已承认边界。

## 5. 水下光束、源图窗口、八点积分、消光、水位、雾、柔化与太阳

**实际覆盖文件与交界。** `program/itt_water_normal_cache.fsh/.vsh`、`scattering.fsh/.vsh`、`water_state.fsh`、`water_composite.fsh/.vsh`、`water_bloom.fsh`、`display.fsh/.vsh`；`global/water/light_shafts.glsl`、`shaft_layout.glsl`、`medium_state.glsl`、`absorption.glsl`、`caustics.glsl`、`particles.glsl`；`lib/itt_water_field.glsl`、`itt_water_waves.glsl`、`water_palette.glsl`、`water_interface_record.glsl`、`water_diffusion.glsl`、`solas_water.glsl`、`solas_water_frame.glsl`；与 `program/water.glsl::astra_underwater_interface/water_transmitted_sun`、shadowmap 及 properties 的资源条件相接。

源图生产使用 64格/1024² 世界窗口，16源格为一步移动；零号像素保存窗口格偏移，普通 texel 保存斜率及未加几何门控的非线性碰撞光量 B。前帧水高用于选择覆盖中心，本帧水高用于实际积分。消费裁在窗口内部，mip 足迹与绝对格对齐，边缘渐弱；没有循环平铺源图或读零号元数据充当波纹光量。

水位从已绘 5 的水平/侧面记录、前帧受保护状态和影图水高补充中选择，写到6。普通水体条件、薄侧流水、可靠水平高度及观察起点与水面的关系分别控制光束消费者。没有可靠水位时光束退出但水雾继续，不能把退出当成可靠的隐藏水位恢复。

积分射线起点由逆投影处理镜头摆动，depthtex0 端点和手部排除与合成相接；14～26格的远端衰减和26格积分上限与48格端点重建标记区分。每区间四个外层 Gauss 遮挡位置，用正权重分成连续完整分段；**每段内部仍有八个 Gauss 波纹光量点**，没有被替换成平均法线或屏幕模糊。入水点偏移0.18格，用 opaque/all 阴影差和水高匹配证明透水，再查询接受点不透明遮挡。入射水路与观察水路各自指数消光；四个外层节点的可见性/消光代表各自分段，八个内部点不各查一次影图。Fresnel 在碰撞光量中一次施加，强度也在既定光源分工中施加，未确认重复乘用户强度。

同帧1的 RGB 存实际光束亮度，alpha 存端点距离；全尺寸 resolve 使用四角端点保护和弱支持渐退，只有满足远端标记的连续足迹使用线性读取。Solas 水雾转换后加线性光束，再进入统一显示。柔化只读场景0与深度，不读1；界面/手排除、近景深度保护和远雾退出保持；Bloom 开关两条路径调用同一柔化/水雾函数。近中景四方向核是明确的新增成本，不视作光束积分的替代。

### P2-B：水下太阳中心穿过地平线时发生额外硬切断

- **触发条件：** 普通水平水下窗口存在透射天空，未处于全反射，太阳位于日出/日落地平线附近，云/几何未完全遮住太阳；两种 SUN_MOON_MODE 都有该分支。最明确的是晴天原版贴图仍有部分位于地平线上方时。
- **准确位置：** [water.glsl:607](C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/Astra/shaders/program/water.glsl:607) 在源中心 `worldSunVector.y<=0` 时直接返回零；[water.glsl:631](C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/Astra/shaders/program/water.glsl:631) 本来又有连续高度可见性；该连续函数在 [solas_water_frame.glsl:15](C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/Astra/shaders/lib/solas_water_frame.glsl:15)。外部太阳在 [sky.fsh:67](C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/Astra/shaders/program/sky.fsh:67) 或 :89 的实际贴图/圆盘分支中没有这个中心高度硬退出。
- **具体错误与依据：** `solas_sun_visibility` 在太阳中心 y→0+ 时趋近0.4，到了0又被 :607 强制归零；不是自然趋零。原版有限宽度太阳可在中心略低于地平线时仍有上半部可见，程序圆盘也有有限角半径。水下补盘则将整个可见部分一并删除，且过零前后具有跳变。该问题与原版方形贴图是否已接通是两个事实；当前贴图路径存在，不能据此称“仍然圆形”。
- **建议：** 让补绘太阳按与外部一致的有限光盘、逐方向地平线和连续可见性决定，去除额外的中心高度二值退出或使其只在整个光盘已经不可见的范围发生。保留原版贴图 UV/alpha、程序模式半径、Snell 折射方向、云遮挡和 TIR 退出。此处不建议改变照明光源切换或光束积分。

**覆盖结论：本模块确认上述一个 P2，没有确认 P0/P1。** 已认可的八点分段积分不需要因本报告被移除。

**已知边界与缺事实。** 64格源窗口深潜/斜向覆盖有限，原28个外层遮挡点仍可能遗漏更细遮挡，影图不能完整代替折射后的水下几何。这些已有近似影响光束连续性，但不能自动断言是“数量少且挤”的新根因。用户没有当前改动后的完整场景/水深/时间/档位事实，不能给束数量或布局达标结论。

水下天空补绘当前只有太阳：环境图刻意不含日月盘，`water.glsl:738` 只添加 `water_transmitted_sun`，非平面云分支调用的 `astra_overworld_sky` 同样没有月盘。源码足以确认这一边界；当前要求明确针对太阳，当前说明也明确只补太阳，没有证据把月盘补绘升级为这轮必需功能，故不列新 BUG。若主审将内外日月整体一致纳入范围，此处是明确接续位置。

## 6. 天空、日月、星空、晨昏、云、天气及其历史

**实际覆盖文件与交界。** `program/sky.fsh`、`lit.vsh` 天体顶点分支、`sky_gradient_cache.fsh`、`sky_reflection_cache.fsh`、`cloud_shadow_cache.fsh`、`prepare_cloud_shadow.fsh`、`cloud_screen.fsh/.vsh`、`clouds.fsh`、`deferred.fsh`；`global/dimension/overworld.glsl`；`global/atmosphere/sky_gradient.glsl`、`sky_minishita.glsl`、`stars.glsl`、`clouds_planar.glsl`、`clouds_screen.glsl`、`cloud_shadow_cache.glsl`、`cloud_temporal.glsl`、`weather.glsl`、`fog.glsl`、`volume_fog.glsl`；`lib/sky_gradient_cache.glsl`、`sky_reflection_cache.glsl`、`cloud_sample_grid.glsl`、`cloud_history_frame.glsl`、`history_frame.glsl`、`twilight.glsl`、`rain_particles.glsl`，properties 中所有天空/天气/光源表达式及两语言相应说明。

天空基础颜色与 glare 分工，prepare 写低频12，方向消费者按同一表节点取样；11 的环境图带经度环绕或填充边界，rough 模式由后序 mip 请求生成。反射环境刻意不含日月尖锐盘；可见天体由 skytextured 单独输出，后序云按覆盖统一遮挡。原版模式采宿主 sprite，程序模式区分太阳与月亮，并应用月相。程序月相的直边终止线和 faint earthshine 是写明的艺术近似，没有冒报天文学错误。

主世界星点来自固定天球图与天气/时间可见性；原版星几何被抑制，未发现重复星层。太阳方向与真正 shadow light 身份分开，CPU 表达式建立连续方向和晨昏因子，地形、云、雾及倒影消费同一入口。日夜直接光接近地平线时自身有连续门控；不能把这一照明门控与模块5的额外可见光盘硬退出混为一谈。

平面云使用世界位置、固定射线相位和受限搜索；24/25 独立历史以代表距离重投影，匹配前帧戳、视口、介质、矩阵、时间/效果状态和深度。四角历史贡献各带自己的元数据。缓慢空边缘最多延续一帧，当前输出空元数据使下一帧不再复活；快速运动、未搜索、遮挡或禁止状态不进入这一延续。TAA jitter 与云自身覆盖网格位移分别补偿，云历史不依赖 ANTIALIASING=2。

云影缓存14以世界锚点覆盖云平面，边界渐退/缓存外使用原平面计算；天气、体积、清天云影条件分别检查。CLOUD_SHADOWS 关闭不等于所有雨天照明都不得用云遮挡，这是现有分工。天气入口对雨幕和雪有温度分支，湿地与积水受 skyLight、雨量、群系、朝向和材质条件限制；涟漪动画跨帧取样与资源尺寸对应。

**覆盖结论：除模块5已计的一处天体交界 P2，没有在本模块确认独立的 P0/P1/P2。** 没有从存在历史图推断云边缘已在实际日出画面稳定。

**取舍和缺事实。** 受限粗搜索、首命中细化、缓存角分辨率、云代表距离与一帧空边缘延续会损失薄云细节或改变短时覆盖，是当前明确近似。没有当前天气过程、资源包天体 alpha、不同 FOV 日出画面和游戏云边缘帧序列；用户旧的薄云抖动不能单独定位新的历史错误。

## 7. 后处理、Bloom、调色、AA、历史重投影与显示颜色域

**实际覆盖文件与交界。** `program/composite1.fsh/.vsh`、`water_bloom.fsh`、`water_composite.fsh/.vsh`、`exposure.fsh/.vsh`、`taa_resolve.fsh/.vsh`、`taa_state.fsh`、`display.fsh/.vsh`、`final.fsh/.vsh`、`effect_history_state.fsh`；`global/post/bloom.glsl`、`exposure.glsl`、`grading.glsl`、`fxaa.glsl`、`godrays.glsl`、`end_sky_tonemap.glsl`；`global/water/bloom_capture.glsl`、`bloom_resolve.glsl`；`lib/tonemap.glsl`、`encoding.glsl`、`taa_jitter.glsl`、`taa_reactive.glsl`、`taa_state.glsl`、`history_frame.glsl`、`effect_history.glsl`、`dither.glsl`、`bayer.glsl`、`pow.glsl`，以及相关附件格式、program.enabled 和混合声明。

常规颜色从贴图 sRGB 解码进入线性 HDR；Solas 水雾内部明确进入其参考平方根/近 gamma 域，再还原线性加光；下界反射的参考颜色域局部 encode/decode 包在该效果内部。未把这些局部艺术域直接视作漏解码。常规显示曝光 → 色调映射 → sRGB → 调色；普通水下走自身显示曲线；末地天空另以亮度保持色相映射。最终输出 dither 在空间 AA 后，避免把同一显示转换执行两次。

Bloom 捕获有阈值、肩部和源峰上限，2/7 的 mip 合成在显示完成。Bloom 为0或关闭时 ASTRA_BLOOM 不存在，其生产、mip、显示读取同步退出。普通水下开启 Bloom 时先柔化/水雾/光束写4再捕获7；关闭时 display 完成同样的水下合成。空气 composite1 在普通水下不读未合成场景作为 Bloom 源。末地石额外泛光使用材质身份和不透明深度条件，不把所有岩石都认作末地石发光。

TAA 颜色历史15配有自身深度和状态17；相机重投影与植物前帧运动22分工，历史四角逐项做深度拒绝，reactive 从16扩张，最后在当前邻域 YCoCg 范围限制。非空气介质禁用 jitter/历史，手与实体按 reactive 分支处理；不能把实体缺前帧输入写成“已经运动补偿”。云历史另有自己的合法条件。FXAA13含显示颜色和对应亮度，final 根据 AA模式读取13或执行显示；末地保留其特定几何边界处理。

**覆盖结论：没有在此模块确认新的 P0/P1/P2。** Bloom 的 GUI 说明问题在模块9计数，未将预算内捕获核变化本身标为合成 BUG。

**取舍与缺失事实。** 四分之一 Bloom、高亮采样遗漏、FXAA 对子像素细节的能力、TAA 对快速动态材质的 reactive 降权属于既有选择。没有当前显示设备颜色管理、实际 framebuffer 色彩状态、自动曝光开关后的画面时间过程或驱动历史驻留信息，不能宣布显示颜色在所有宿主正确，也不能虚构相关开销。

## 8. 下界、末地入口与全部活跃独立效果

**实际覆盖文件与交界。** `world-1/` 和 `world1/` 全部入口，`program/scene.glsl` 的维度分派；`global/dimension/nether.glsl`、`nether_colored_light.glsl`、`nether_reflection.glsl`；`program/nether_light.csh`、`nether_reflection.fsh`、`nether_reflection_resolve.fsh`、`effect_history.vsh`、`effect_history_state.fsh`；`lib/nether_voxel_grid.glsl`、`nether_reflection_metadata.glsl`、`nether_fog_density.glsl`、`effect_history.glsl`。末地覆盖 `global/dimension/end.glsl`、`end_blackhole.glsl`、`end_kerr.glsl`、`end_plasma.glsl`、`end_system.glsl`、`end_geometry.glsl`、`end_disc_profile.glsl`；`program/end_illumination.fsh`、`end_reflection_cache.fsh`、`end_sky_buffer.fsh`、`end_star_rows.csh`、`end_star_catalogue.csh`；`lib/end_light.glsl`、`end_surface.glsl`、`end_star_catalogue.glsl`、`end_reflection_cache.glsl`、末地色调映射及四张传输/流场图与其元数据。

下界体素链是阴影顶点按方块中心将 kind/solid 位 imageAtomicMax 写入64³整数图 → shadowcomp0 创建发光种子并记录2纹元的活动区域 → 后续8步在A/B RGBA16F图间交替六邻居传播 → 最终偶数步A被 lit 取样。活动区域用16格粗 tile 位图，传播裁剪按本步能够到达的邻域扩张；裁剪组仍写零避免旧光留存。局部原色、实心阻挡、边界渐退和实体/手的普通光分工实际存在。此链仅 SHADOWS、NETHER_VOXEL_LIGHT、BLOCKLIGHT_STRENGTH>0 时调度和分配，未把关闭效果的空 compute 分派误算为活跃成本。

下界独立照明包含群系 palette/density 平滑、参考 lightmap 与方向/AO、手持与发光/门户。当前下界雾是独立距离/介质分支；虽然读取了保留的 `nether_volume.glsl`，实际 include 没有通向该模块、Bliss 噪声没有绑定。它的 additive haze 注释或旧实现不能作为当前下界渲染 BUG。

下界岩石反射在 composite 读3的法线/粗糙度和 depthtex0/1，低中档仅2×2接收格点追踪；9/28分别存反射颜色/接收身份，30保存独立历史状态。历史四角配对身份、法线、接收深度后参与重投影，resolve 在接收岩石平面上过滤，不把发光纹理本身做一张无身份大模糊。NETHERRACK_GLOW 控制下界岩粗糙反射响应，不变成自发光。

末地 setup 写512行星表元数据/前缀地址，setup1按行格点写presence，setup2保留宿主交接。prepare 向附件8写照明、7个活跃外侧形体位置/基与形状数据；几何和独立天空使用同一 end_light_direction 与缓存。主体天空通过原生尺寸附件9生成，opaque depth 像素不做完整天空；deferred 合成天空、清晰光子环与经透镜映射的滤波星点，避免缓存星层重复。11用于反射环境，低粗糙度靠近黑洞/形体或缓存存在大色差/可见性差时回到实际求值。

Kerr 传输图按两阶映射读有限坐标，逐角排除无效分支并约束跨分支插值；传输元数据用于发射方向/盘面侧；流场用带边界的显式 mip 图集，色温、频移、热点、等离子层、极向喷流分别合成。活跃天体形体是66～72，0～65与旧全体 SDF helper 是保留研究路径，未宣称当前每像素计算全部73个物体。末地固定源方向、正交阴影、表面直接/环境光和天空遮食缓存消费一致。

**覆盖结论：没有在下界或末地活跃链确认新的 P0/P1/P2。** 没有将保留的非活跃下界体积模块、退役天体集合或 Voxy 空壳当作现行效果错误。

**边界与缺失事实。** 体素由可提交方块顶点和固定64³范围构成，不能还原精细孔洞；岩石稀疏追踪与较宽误差允许范围是明确参考近似。末地天空是纹理传输/有限层和有限 SDF形体组合，并非完整相对论体积求解。没有当前实际下界群系交界、末地纹理所有数值来源、资源替换后的图集一致性、显存峰值和实体提交统计；不能据附件名义尺寸宣称驱动驻留或当前维度画面达标。

## 9. 选项、档位、组合、性能热点与当前说明

**实际覆盖文件与交界。** `lib/settings.glsl` 所有开关/数值/颜色/预算/派生宏和宿主常量；`shaders.properties` 的四档 profile、screens、sliders、program.enabled、尺寸条件及全部自定义表达式；`lang/zh_CN.lang`、`en_US.lang` 的相关开关、档位、依赖和成本说明；根 README、docs 当前入口、实现与限制及 Astra README。追踪了 SHADOWS/COLORED_SHADOWS/SSS、SSAO/方向天光、云模式/质量/历史、体积雾/GODRAYS、水反射/折射/水波/光束、Bloom/强度0、三种AA、主世界预算0/1/2、debug、维度重定向和本轮各相关条件。

四档均选择主世界优先预算，不强开用户默认关闭的方向天光/SSAO/体积雾；高档仍受主世界预算上限，因此高档选项数字不代表实际4096影图或原生云。预算关闭才恢复相应原始质量分支，主世界软件影图比较覆盖 SHADOW_FILTER_MODE 是已有明确选择；下界末地不受主世界预算宏影响。单选AA没有在同帧同时消费两个最终颜色路径。水波关闭/有效源图条件不满足时，源图和实际波光消费受到各自条件约束，不以存在 UNDERWATER_LIGHT_SHAFTS 开关就推定有有效波源。

### P2-C：Bloom 质量说明没有说明主世界预算将其统一覆盖为四次捕获

- **触发条件：** 主世界 OVERWORLD_BUDGET=1或2、BLOOM有效，用户查看或切换 BLOOM_QUALITY 的均衡/高档。这也是所有预设选择的预算环境。
- **准确位置：** [zh_CN.lang:25](C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/Astra/shaders/lang/zh_CN.lang:25) 与 [en_US.lang:25](C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/Astra/shaders/lang/en_US.lang:25) 将4/5/13次和中心+轴向/圆盘核直接描述为质量档行为；实际 [bloom.glsl:82](C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发/Astra/shaders/global/post/bloom.glsl:82) 在 ASTRA_OVERWORLD_OPTIMIZED 时统一 taps=4，:92～103在质量>0时使用四对角足迹，根本不执行五轴点或十三点核。所有 profile 的预算声明位于 shaders.properties:564 起。
- **具体错误与依据：** 用户在默认预算下选均衡或高档，实际采样次数均为4且这两档使用同一预算核，说明却让其预期5/13次与更密核，并称水下同档位。该错误是选项解释不完整；四点预算本身是已有取舍，不是程序缺陷，也不据此宣称画面超出用户认可损失。
- **建议：** 两语言说明增加预算适用条件和实际四点覆盖规则，说明预算关闭/其他维度才按4/5/13原始档执行。保留现行预算核，主审可独立决定是否进一步调整呈现。

**覆盖结论：本模块确认上述一个说明类 P2，没有确认 P0/P1 或未经实际成本支持的性能 BUG。**

另有仅作为说明维护落点的源码注释不一致：settings.glsl:337仍说主世界预算使用硬件比较，实际:365～366固定软件，现行中文/英文说明已正确；settings.glsl:202～203声称能力不足时余下包仍工作，与现行 README/实现与限制明确的无完整替代路径不符；shaders.properties:8写光束最多积分48格，而实际 light_shafts.glsl:161/:187受26格远端常量限制，48用于端点重建。它们不另外增加程序 BUG，也不覆盖当前说明中已正确写明的边界。

**可从源码定位的工作量，不能换算 FPS。**

| 活跃路径 | 实际工作与条件 | 当前不能断言的事实 |
| --- | --- | --- |
| 水下光束 | 普通水、有效水位和源图时，1024²六层源图写入及其消费 mip；均衡半尺寸七区间×四遮挡节点×八波纹点，最多224次波纹读取/积分片元，阴影遮挡可提前跳过整个分段。 | 224不是每点均查影图；单独源图/积分数字不包含当前完整帧。 |
| 水面/窗口 SSR | 限额深度查询、候选自身纹元求交、逐颜色端点介质、实体记录、连续足迹共享；反射权重/距离/质量决定哪些工作实际发生。 | 当前树叶提升后的更远粗查询也有额外代价，不能只数减少的噪声读取。 |
| 水下显示 | 四方向场景与深度柔化、RGB16F水下合成4、半尺寸光束重建，Bloom开时另有四分之一捕获7。 | 附件精度提升、额外柔化读取、带宽和缓存行为不能从局部算术直接抵消。 |
| 阴影/云 | 预算1536与112覆盖、中心混合边缘才追加影图组；云四分之一细节层、有限搜索、当前环境/云影缓存与历史重投影。 | caster提交、混合边缘比例、缓存有效覆盖和宿主成本需要实际场景事实。 |
| 可选AO/体积 | SSAO半尺寸12点深度核，双开方向光另写/读26并做SH重算；体积雾低12/中24/高48步并有自适应。 | 默认关不代表这些组合可忽略；本报告已沿生产和消费读过。 |
| 下界/末地 | 下界9个64³compute阶段及活动区域裁剪、稀疏岩石反射；末地native天空、低尺寸反射缓存、7形体求交、星表与流场取样。 | compute调度数/名义容量不是GPU实际耗时或驱动驻留。 |

原生1080p输出保持，云/光束/Bloom的细节分辨率单独降低；不是用降低整帧输出冒充达标。没有当前整帧数据，也没有同场景、同选项、同硬件的当前 Steadfast 帧事实；“明显高于 Steadfast”的用户反馈是定位背景，不能让本报告生成一个新性能数值或宣称已经消除。

## 实际覆盖结束位置与仍缺事实

九模块均已独立读到现有包装入口、公共实现及关键生产—附件/输入—消费者；没有未读的活跃模块。源码文件以程序/include和条件分支为阅读单位，辅助纯常量、编码、色彩、资源声明也纳入阅读。保留/退役模块与资源已区分：旧水历史没有活跃 include/宏，Bliss下界体积没有活跃调用，末地旧0～65集合没有活跃全体求交入口，Voxy属于已知空壳。

没有读取其他审查者意见、主审裁决、整批旧报告，也没有将文档中独立驱动呈现或旧计时当成本次游戏事实。没有新增独立图像产物；本次结论停在源码和按需宿主字节码能够证明的层面。

仍缺的是：五项变化后的当前游戏效果；实际活动资源包天体/材质像素；本次完整帧耗时与帧分布；实际驱动分配/驻留及完整宿主运行状态；复杂水体拓扑与迟绘透明排序的可见场景事实。资源PNG读到了结构和绑定，未逐texel鉴定末地传输图的生成数值。上述缺失不等于有某个未覆盖源码模块，也不允许将局部表现或源码工作量写成游戏问题已解决。
