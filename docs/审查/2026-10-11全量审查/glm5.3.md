# Astra 独立全量代码审查（GLM5.3）

- 审查入口：`group/auto-glm-5-3`（用户指定入口；不声称知道路由后台实际提供商）。
- 审查方式：独立读取当前工作区源码、配置与现行文档，不读取其他审查者意见，不参加实施，不使用子代理。审查对象为工作区现状，不限 `git diff`。
- 环境边界：未启动游戏、未运行QA/额外门禁、未做实机画面或整帧性能采集。没有整帧数据，不能推断原生1080p平均144FPS或95%帧≤6.94ms达标；GPU开销只描述源码级工作与已知边界，不虚构FPS。
- 审查时点：本报告以当前工作区的稳定源码为最终依据；主代理已按最新要求暂停源码修改。此前曾发现部分文件在审查过程中被主代理修正，本报告已按当前实际文件重新复核，不把旧状态继续列为未处理问题。
- 本报告按用户指定九个模块完整覆盖；“没有发现P0/P1/P2”仅指在本次源码证据与覆盖深度内没有可证实问题，不表示实机观感已确认。

## 汇总

| 严重度 | 问题 |
|---|---|
| P1 | 薄水层仍生产1024×1024水下光束源图和mip链，但主消费链在薄水层不消费，形成确定无效GPU工作。 |
| P2 | `docs/实现与限制.md` 称水下界面“仍读RG”，与当前直接调用同一波场函数的实现不一致。 |
| P2 | `Astra/shaders/global/water/temporal.glsl` 是无活跃引用的退役历史文件，但保留 `colortex29` 读写语义，易被误接线。 |
| P2 | 中英文设置页对主世界预算的“水下32～48格合并远景柔化采样”和“每个采样点查询遮挡”描述与现行源码不一致。 |

当前源码已经修正的交界不列为问题：原版太阳资源独立注册、水下原版太阳1.12角尺寸对应、平面云透射星场、水路远侧12粗查询且湿润地形不受该上限。树叶缺失、光束观感、阴影残余锯齿和水路开销的主要结论见对应模块，不把独立呈现或源码推断冒充实机解决。

## 1 入口、调度、GLSL条件、附件格式、清屏、mip、翻转、资源与宿主兼容

### 覆盖

- `Astra/shaders/shaders.properties:14-25`：`colortex1` 按空气godrays/水下光束条件选择半尺寸或四分之一尺寸；无消费者时为1×1。
- `shaders.properties:34-47`：Bloom开启时 `colortex2/7` 缩到四分之一；`shaders.properties:318-330` 按Bloom条件启停 `composite1/3/4`，下界和末地禁用3/4。
- `shaders.properties:197-217`：主世界 `colortex28` 全尺寸，`colortex29=1024 1024` 仅在水下光束+阴影+水波+强度条件启用；`prepare4` 条件开启，`prepare5` 与world-1/world1的4/5显式禁用。
- `shaders.properties:383-386`：主世界、下界、末地的deferred入口均开启；`shaders.properties:367-381` 按Bloom、SSR与阴影条件控制维度相关composite/shadow入口。
- `shaders.properties:515-536`：`ittWaterNoise` 与 `astraSunTexture` 独立注册；原版太阳按MC26.x/旧版路径选择资源。`astraSunTexture` 由 `program/water.glsl:601-620` 消费，`ittWaterNoise` 由 `lib/itt_water_waves.glsl:7` 消费。
- `Astra/shaders/prepare4.vsh:1-2` 与 `program/itt_water_normal_cache.vsh:9-18`：顶点阶段计算水下光束源窗口；`prepare4.fsh`/`itt_water_normal_cache.fsh:9-27` 声明RGBA16F、`colortex29Clear=false`，RG为斜率、B为碰撞光量，零号像素只存窗口偏移。
- `program/scattering.vsh:24-57`：水下光束在薄水层、无有效水位或波幅关闭时顶点裁剪/输出无效；`program/scattering.fsh:79-85` 显式声明清零。`global/water/light_shafts.glsl:65-69` 在消费程序声明 `colortex29MipmapEnabled=true`，依赖本地Iris的消费前mip顺序。
- `program/water_composite.vsh:9-22`：仅Bloom开启且水下才绘制水下合成；Bloom关闭时由 `program/display.fsh:132-147` 承接。
- `lib/water_buffer_formats.glsl:12-30`：0/2/7为R11F_G11F_B10F；主世界Bloom时4为RGB16F。`program/display.fsh:118-124` 水下在所有AA模式下直接读4，避免TAA低精度二次压缩。
- 宿主边界：`shaders.properties:851` 声明 `iris.features.optional=CUSTOM_IMAGES COMPUTE_SHADERS`；README和 `docs/实现与限制.md` 均说明这不是缺能力时的完整替代实现。

### 问题

- **P1 性能：薄水层仍生产无人消费的1024²源图与mip链。**
  - 触发条件：主世界开启水下光束、阴影、水波与强度；`isEyeInWater==1` 且 `water_is_thin_sheet()==true`。
  - 依据：`program/itt_water_normal_cache.vsh:10` 仅按 `isEyeInWater==1` 放行；`itt_water_normal_cache.fsh:18` 同样只检查眼在水中。该文件已包含 `medium_state.glsl`（vsh:5），可低成本判断薄水层。相反，`program/scattering.vsh:31-36` 在薄水层直接返回，`program/water_composite.fsh:25-27` 不消费光束，`program/display.fsh:140-142` 的关闭Bloom路径仅 `ordinaryWater` 时消费。
  - 错误结果：1024×1024 RGBA16F源图生产与mip链继续执行，主光束结果不进入普通水路；具体毫秒/FPS未知，但这是可从调度条件证实的无效GPU工作。
  - 建议：在 `itt_water_normal_cache.vsh` 与 `.fsh` 使用与消费端一致的 `water_is_thin_sheet()` 裁剪，保持附件条件与实际消费者一致。
- 其余入口、附件格式、清屏、mip声明、资源注册和宿主兼容声明未发现可证实P0/P1/P2。

### 疑点与缺失事实

- `colortex29` 的mip顺序依据本地Iris 1.11.2 `stageReadsFromAlt → setupMipmapping → setupState` 说明；本审查未运行引擎，无法直接验证所有宿主的实际顺序。
- 未逐行审计所有维度薄入口的宿主语法；只按调度、include和消费者关系核对。
- 未运行游戏，不能验证资源包实际提供方形太阳、界面/附件在驱动中的实际驻留和压缩。

## 2 阴影投射、接收、过滤、彩影、焦散与覆盖边界

### 覆盖

- `program/shadow.vsh:36,214` 输出未畸变投射物坐标；`program/shadow.fsh:33-72` 在材质/裁切分支前求真实三角面平面深度，非水投射物写 `max(gl_FragCoord.z, planeDepth)`，并声明 `depth_greater`。水投射物保留原深度，`shadow.fsh:99-116` 只为水面焦散写A通道。
- `program/lit.vsh:3-12` 为主世界非水/非天气接收面启用表面阴影平面路径；`program/lit.fsh:160-166` 在alpha discard与材质分支前调用 `astra_surface_shadow_set_plane`。
- `global/lighting/shadowmap.glsl:142-166` 建立接收面平面与像素世界宽度；`shadowmap.glsl:202-244` 将四个影图角中心逆投影到原接收面，参考深度取平面深度与中心深度较小值；硬件模式每个角独立gather比较。
- `shadowmap.glsl:246-355` 保持两深度图配对、彩色透射、水面高度/焦散与接收者世界Y配对；`shadowmap.glsl:109-122` 的覆盖渐退保留边界。
- `global/lighting/diffuse.glsl:277-346`：中档中心四角先判断均匀亮/暗；混合边缘按可见性梯度加两组偏移，额外权重上限0.58；额外半径限制在 `max(0.22格,0.75×接收面像素世界宽度)`；水下缺覆盖fallback为0，避免无影变阳光。
- 焦散：`global/water/caustics.glsl` 与 `shadow.fsh`/`shadowmap.glsl` 的水高/焦点/接收者Y配对已核对；`shadow_water_caustic_gain` 使用水下与水外不同对比度。

### 问题

- 没有发现新的P0/P1/P2阴影链问题。
- 用户反馈的边缘锯齿不能由源码判定已消除：中档只有中心足迹加两组定向额外足迹，额外半径受影图纹元/接收面像素近似限制；细投射物、低太阳角和径向影图纹元覆盖误差仍可能留下锯齿。`docs/实现与限制.md:15-17` 也承认低太阳角细边纹元覆盖误差仍存在。

### 疑点与缺失事实

- 未实机采样真实游戏边缘；源码无法证明游戏细边消失或仍残留到何种程度。
- 未逐行数学证明所有焦散参数的视觉正确性；只核对生产/消费字段和条件。

## 3 材质、直接/间接照明、AO、SSS、体素、实体与手

### 覆盖

- `program/lit.fsh:15-29,53-145`：主世界实体/透明实体声明 `colortex28=RG32F` 并包含实体记录；普通与透明实体程序通过 `ASTRA_ENTITY`/`ASTRA_LATE_ENTITY_SOURCE` 写入。
- `lib/water_entity_record.glsl:5-24`：半精度打包颜色/深度并加normal-bit bias；`program/water.glsl:54-91` 用同一记录恢复晚绘实体颜色和距离，保持颜色/深度配对。
- `program/deferred.fsh` 与 `program/lit.fsh` 的场景/不透明快照、AO、puddle、云/体积条件调用已按生产-消费关系核对；水下fallback为0。
- `lib/ao_resolve.glsl:20-98`：AO只作用于环境光，深度/法线一致才接受；vertexAO与SSAO取min而非乘；水下与手排除；方向性天光只替换环境天光份额。
- `global/lighting/sss.glsl:67-88,147-175`：叶片/地面植物不同wrap；透射项使用视角/光源关系和天光暴露，未新增第二次阴影读取。
- 下界体素光：`shaders.properties:816-846` 控制九个compute阶段；`program/nether_light.csh:1-128` 使用体素占用、source tiles和A/B体积图，逐步六邻传播并清零无源组。
- 实体TAA边界：`program/taa_resolve.fsh:99-105` 水下直接拒绝历史；实体缺少每实例前帧运动输入，仍不冒用相机运动。

### 问题

- 没有发现材质、直接/间接照明、AO、SSS、实体记录或手部链路的P0/P1/P2。
- 体素光和末地compute数学按调度、图像格式与输入/输出关系覆盖，未逐行证明物理传播正确性。

### 疑点与缺失事实

- 分数透明实体、多层玻璃/冰/水的完整排序仍是既有D01边界，不是本次发现的实现断裂。
- 未实机验证实体记录在所有透明实体材质上的覆盖顺序；只确认程序边界与混合条件。

## 4 水面波纹、反射、SSR、折射、介质、迟绘身体与界面两侧

### 覆盖

- `global/water/surface.glsl` 与 `program/lit.fsh:199-260`：水上Steadfast波面保留；水下水平面调用 `itt_water_wave_normal`；预算内一次薄层视差匹配原四步总推进量，波形/速度/幅度保留。
- `global/water/raytrace.glsl:15-55`：主世界预算为20总查询上限，远侧12粗+4细化；低档保持12总；远水按重要性最低6粗。`raytrace.glsl:247-265` 远侧12上限只作用于优化主世界水路；湿润地形和下界/末地不受该上限误伤。
- `raytrace.glsl:282-379`：粗查询重读自身深度；叶片预计交点只有仍落在原纹元才直接接受；`raytrace.glsl:383-430` 细化阶段对错层叶片重读候选四角，候选必须穿过自身纹元、原粗区间和反射侧。
- `program/water.glsl:184-280`：连续空气反射、水下反射与水底足迹共享逆投影/传输条件；实体、天空、断层、深度/路径差超界时逐角处理。
- `program/water.glsl:543-596`：竖流水界面使用真实几何法线与短水路；`program/water.glsl:638-747`：水下Snell窗口、全反射、玩家头部中心、折射天空与实体记录保持。
- 迟绘身体：`water_scene_endpoint`（`water.glsl:54-91`）将 `colortex28` 与同一屏幕射线深度配对；分数透明实体零输出通过混合保留旧记录，不擦除身体。
- 界面两侧：`water.glsl:638-747` 使用 `relativeEyePosition` 决定水下窗口中心，几何遮挡/反射仍用实际相机；头部跨水时采用相机实际水深。

### 问题

- 没有发现新的P0/P1/P2水面实现错误。
- **明确取舍而非误报**：树叶倒影缺失不能视为已解决。SSR只能反射屏幕内几何；屏外或被原视角遮蔽的叶片无法恢复。离散查询在复杂错层树冠仍会漏采，细化四角只改善可预测的错层/孔隙交点，不等于完整树冠接收。源码也没有放宽残差去“制造”树叶。

### 疑点与缺失事实

- 缺少实机同机位前后对比，不能确认当前树叶倒影是否达到用户期望。
- `global/water/refraction.glsl` 的核心判据通过调用点与主路径核对；未逐行证明所有非标准投影下的几何正确性。
- 水体身份和隐藏界面水位仍是D03限制；局部换池/多层水体不能完整证明。

## 5 水下光束源图、窗口、积分、消光、水位、雾、柔化与太阳

### 覆盖

- `lib/itt_water_waves.glsl:42-76`：六层权重2/6/8/13/30/20，空间尺度 `0.05/1.28`，最终按 `1.28/1.08` 与总权重79归一；解析噪声/波脊导数。
- `lib/itt_water_field.glsl:19-30`：B通道光量 = `(0.24+3.05×offset)^3 + 0.22×offset/(0.15+offset)`，经Fresnel与有界压缩，未门控场景遮挡/天气/眼深。
- `program/itt_water_normal_cache.vsh:10-18`：源窗口以折射光心和当前水深为中心，按16源格（1格）对齐；零号像素存窗口偏移。
- `global/water/light_shafts.glsl:20-25`：优化档最多7区间；`light_shafts.glsl:131-149` 每分段8点Gauss积分B光量，最多224次波纹读取；LOD按屏幕足迹限制到0..4。
- `light_shafts.glsl:96-123`：入口向水内偏0.18格，两深度差+水高匹配；接受点再查不透明遮挡；平面云影可选。消光分入射/观察两路，`light_shafts.glsl:178-185` 分别加散射损失。
- `light_shafts.glsl:152-225`：26格上限、14..26远端渐弱、0.08近处缓入、真实水位与当前折射光源；八点路径积分保持，无逐帧随机、独立历史或壳层点。
- 水下雾/柔化：`program/water_composite.fsh:17-31` 与 `program/display.fsh:132-147` 在Bloom开关两条路径调用 `water_diffuse_scene`；`lib/water_diffusion.glsl:23-110` 为2.5..18格渐入、1.2..3像素、强度0.48，手/界面/更近几何拒绝。
- 水下太阳：`program/lit.vsh:111-117` 原版日月quad放大1.12；`program/water.glsl:604-620` 水下透射太阳用0.672半宽（30/100×1.12）重建原版太阳UV，读取活动资源包贴图并保留贴图alpha；程序盘模式为解析圆盘，属配置分支。

### 问题

- 除模块1列出的薄水层源图浪费外，没有发现新的P0/P1/P2光束逻辑问题。
- **P2 文档不一致：`docs/实现与限制.md:62` 称“界面仍读RG”。**
  - 触发条件：阅读现行文档理解水下界面输入来源。
  - 依据：实际界面在 `program/lit.fsh:211-215` 直接调用 `itt_water_wave_normal()`；`colortex29.RG` 只由源图/光束路径使用，活跃代码没有界面读取RG的调用。
  - 结果：文档让人误以为界面与源图逐纹元共享同一读取来源。实际是同一波场函数、时间与尺度，但不是同一纹理读取。
  - 建议：将文档改为“界面直接调用同一波场函数，RG源图供光束/碰撞光量使用”，或真正改为读RG（后者无必要且增加耦合）。
- **P2 选项说明不一致：主世界预算注释仍写“水下32～48格合并远景柔化采样；光束每个采样点查询遮挡”。**
  - 触发条件：用户在设置页阅读“主世界性能预算”说明，或按注释理解源码行为。
  - 依据：`lang/zh_CN.lang:171` 与 `lang/en_US.lang:171` 均称水下diffusion在32..48格合并远景采样；实际 `lib/water_diffusion.glsl:23-110` 的渐入范围是2.5..18格、半径1.2..3像素，没有32..48格合并区间。语言又称“每个采样点查询遮挡”；实际 `global/water/light_shafts.glsl:196-218` 最多7个外层遮挡节点，每节点代表一个分段，分段内8个波纹点共享该节点遮挡，不是每个波纹点查询阴影。`docs/实现与限制.md:66-68` 的现行说明与源码一致。
  - 错误结果：设置页低估近中距柔化、夸大光束遮挡查询密度，用户可能据此选择错误档位或解释性能。
  - 建议：同步两处语言为“2.5..18格四方向柔化；每段8个波纹点共享对应遮挡节点”。文档与语言属于用户可见说明，二者应指向同一源码事实。

### 疑点与缺失事实

- 光束数量少且挤是观感目标，不是本审查能证实的bug：源码由波面碰撞光量、遮挡、消光和积分决定束形；没有实机画面无法确认“少且挤”是否改善。
- 水平界面与源图使用同一波场函数、时间与尺度，但不是同一纹理读取；这本身是合理实现边界，报告只澄清事实。
- 没有整帧或mip/源图分项计时，不能推断薄水层浪费的实际FPS影响。
- 首次深潜、换池、斜向深水投影时64格窗口覆盖不足是文档已声明的取舍。

## 6 天空、日月、星空、晨昏、云、天气及相关历史

### 覆盖

- `program/sky.fsh:64-121`：原版贴图/程序盘模式、太阳颜色、月亮与日月边界；`program/lit.vsh:111-117` 保持水外原版日月1.12尺寸。
- `global/atmosphere/stars.glsl:89-130`：星场按天球方向、日月遮蔽、天气/晨昏可见性输出；`program/water.glsl:725-739` 水下平面云模式叠加星场并用云透射遮挡，当前源码已接线。
- `lib/twilight.glsl:4-13` 与 `shaders.properties:594-626`：天空、云、地形、水共用同一晨昏包络；曲线端点/中段与日月运动边界保持。
- `global/atmosphere/clouds_planar.glsl:140-159,229-279`：稳定采样相位、屏幕云/倒影云/云影预算分离；水面透射太阳在 `water.glsl:632-635` 使用 `astra_planar_cloud(direction).a`。
- `global/atmosphere/cloud_temporal.glsl:64-191`：云历史只在真实参与搜索、无遮挡且运动缓慢的空边缘保留一帧；遮挡/快速运动/无效状态回当前帧，元数据不把空覆盖伪装成有效历史。
- `global/atmosphere/cloud_shadow_cache.glsl:9-38` 与 `program/cloud_shadow_cache.fsh:11-22`：云影缓存锚定、边缘回退与条件消费已核对。
- `global/atmosphere/weather.glsl`：雨水响应、湿面与积水分离，云影沿接收点与光源查询。

### 问题

- 没有发现P0/P1/P2天空、云、天气或历史链问题。

### 疑点与缺失事实

- 日出薄云边缘抖动、晨昏丝滑程度和水面高光形状均需实机观察；源码只证明历史拒绝与共享晨昏包络存在。
- 未逐行证明云光照模型所有近似在所有视角下无色阶/抖动，只按触发条件与输入/输出覆盖。

## 7 后处理、泛光、调色、AA、历史重投影与显示颜色域

### 覆盖

- `program/display.fsh:93-99`：FXAA准备路径写 `colortex13` RGBA16；`program/final.fsh:1-20` FXAA后输出并应用最终dither；TAA路径由final直接显示已解析的0。
- `program/display.fsh:118-127`：Bloom开启且水下直接读取RGB16F `colortex4`，所有AA模式一致；Bloom关闭时显示路径内合成水雾/光束。
- `program/display.fsh:132-147,148-167,222-245`：水下柔化、光束、泛光、空气godrays、失明、调色、显示曲线和最终输出顺序已核对。
- `global/post/bloom.glsl:24-26,59-145,147-179`：Bloom捕获四分之一尺寸、预过滤阈值1.0、捕获/合成mip对应；水下泛光走 `global/water/bloom_resolve.glsl`。
- `global/post/fxaa.glsl:9-100`：有界边搜索；水下 `geometryOnly` 只对深度边缘做AA，避免色彩细节被当作几何边。
- `program/taa_resolve.fsh:85-182`：水下/相机介质拒绝历史；静态表面按前帧投影/深度/颜色统计重投影；植被使用前帧运动；实体/水/云不冒用相机运动。
- `program/taa_state.fsh:13-23`：帧尺寸、帧号、介质、雨、风相位等状态记录；`lib/history_frame.glsl` 用于状态有效性。
- 显示颜色域：`program/display.fsh:226-245` 水下Solas曲线与空气/维度tone map分支独立，最终输出dither在AA后；`global/post/grading.glsl` 为唯一调色入口。

### 问题

- 没有发现P0/P1/P2后处理或AA链断裂。

### 疑点与缺失事实

- 未实机确认TAA/FXAA在真实边缘上的观感，也未知驱动实际色彩域/显示输出设置；源码只能确认内部颜色域顺序。
- 自动曝光默认关闭，未审查所有开启组合下的实机亮度表现。

## 8 下界、末地维度入口与独立效果

### 覆盖

- 下界：`shaders.properties:816-846` 按体素彩光条件开启九个shadowcomp；`program/nether_light.csh:1-128` 使用64³体素、source tiles、A/B图像与八步传播。`program/nether_reflection.fsh:19-149` 生产岩石反射与元数据，低/均衡档2×2格点；`program/nether_reflection_resolve.fsh:18-132` 按接收者材质、法线、平面和深度过滤。
- 末地：`shaders.properties:244-254` 开启End准备入口；`world1/prepare.fsh` 调用 `end_illumination.fsh`，`world1/prepare1.fsh` 调用反射缓存。`program/end_star_rows.csh` 与 `end_star_catalogue.csh` 生成紧凑星表，`program/end_sky_buffer.fsh` 生成原生分辨率天空/遮蔽数据，`end_illumination.fsh` 生成轨道/岛/星转数据。
- 维度隔离：world-1/world1的prepare4/5、Bloom水下合成、云历史/AO/体积组合按各自条件启停；下界28保持RGBA16F反射元数据，不与主世界RG32F实体记录混用。

### 问题

- 没有发现维度入口或独立效果调度层面的P0/P1/P2。

### 疑点与缺失事实

- 下界/末地数学模型未逐行完整审计；本次覆盖到调度、图像声明、输入/输出关系和关键消费者，不足以证明黑洞/星表/彩光传播所有参数在实机均正确。
- 未验证不同Iris/MC版本在所有维度下的实际加载兼容性。

## 9 选项档位、开关组合、性能热点与文档一致性

### 覆盖

- `shaders.properties:544-546,564-567` 与 `Astra/shaders/lang/zh_CN.lang`/`en_US.lang` 对齐：水体质量、云、阴影、Bloom、AA、水下光束、主世界预算的档位与预设组合已核对。
- `lib/settings.glsl:337-368`：主世界预算强制软件逐角比较，预算关闭/其他维度使用用户阴影过滤方式；README与语言说明一致。
- `shaders.properties:8-25,34-47,123-139,197-217`：关闭Bloom/AA/AO/体积/光束时对应附件缩为1×1或程序禁用，避免完整阶段运行。
- `Astra/README.md:9-17,35-41`：预算、宿主能力、SSR边界、Voxy骨架、旧历史未接线的说明与源码一致。
- 性能热点边界：水路查询上限、源图条件、Bloom捕获、云/AA/AO条件与文档一致；已知独立组件计时在文档中明确标注不能换算整帧FPS。

### 问题

- **P2 代码遗留：`Astra/shaders/global/water/temporal.glsl` 无活跃引用。**
  - 触发条件：任何后续开发把该文件当作现有水面历史实现接入。
  - 依据：`rg` 显示除该文件自身外没有活跃include；文件内仍声明 `colortex29` 读写/元数据语义（`temporal.glsl:53-65,107-146`），而当前 `colortex29` 已是1024² ITT波面/碰撞光量图，prepare5已退役。
  - 错误结果：当前渲染无影响；但旧语义与现行附件用途冲突，后续误接线会把波面源图当SSR历史读写。
  - 建议：删除该退役文件，或移动到明确的archive/退役说明中，避免与现行 `colortex29` 语义混用。
- **P2 选项说明不一致：主世界预算注释仍写“水下32～48格合并远景柔化采样；光束每个采样点查询遮挡”。**
  - 触发条件：用户在设置页阅读“主世界性能预算”说明，或按注释理解源码行为。
  - 依据：`lang/zh_CN.lang:171` 与 `lang/en_US.lang:171` 均称水下diffusion在32..48格合并远景采样；实际 `lib/water_diffusion.glsl:23-110` 的渐入范围是2.5..18格、半径1.2..3像素，没有32..48格合并区间。语言又称“每个采样点查询遮挡”；实际 `global/water/light_shafts.glsl:196-218` 最多7个外层遮挡节点，每节点代表一个分段，分段内8个波纹点共享该节点遮挡，不是每个波纹点查询阴影。`docs/实现与限制.md:66-68` 的现行说明与源码一致。
  - 错误结果：设置页低估近中距柔化、夸大光束遮挡查询密度，用户可能据此选择错误档位或解释性能。
  - 建议：同步两处语言为“2.5..18格四方向柔化；每段8个波纹点共享对应遮挡节点”。
- 其余选项组合、档位与文档一致性未发现可证实P0/P1/P2。

### 疑点与缺失事实

- 语言/文档中对原生效果的一般性描述与源码一致，但未验证每个手写组合在GUI中的实际显示排序。
- 没有整帧GPU数据，不能判断当前水路/阴影/光束相对Steadfast的实际整帧差距；源码只支持识别确定无效工作和结构性开销边界。
- 独立组件计时不是整帧证据，不能推断1080p平均144FPS达标。

## 审查结论

当前九个模块的活跃链路没有发现P0级错误。可证实的最重要问题是薄水层仍生产无人消费的1024²水下光束源图与mip链（P1性能），以及若干低风险文档/选项说明/遗留文件不一致（P2）。用户关注的树叶倒影、光束布局、阴影锯齿和水路开销均需实机事实：SSR屏幕空间限制、有限过滤近似和已知组件成本不能分别转化为“已解决”或“已达标”。
