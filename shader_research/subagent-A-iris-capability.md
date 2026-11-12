# 子代理 A：本机 Iris 引擎能力面调研（Astra 未使用部分）

调研对象与版本声明（先说清楚证据来源，后面所有"读源码"都指这几份）：
- 本机实例的光影加载器是 **iris-fabric 1.11.2 + Minecraft 26.2**。该版本的 class 文件解包在 `_analysis/irispk/`（844 个 `.class`，包名 `net/irisshaders/iris/...`）。本文所有反编译证据来自对该目录做 `javap -p -c` 的结果，转存文本放在 `_analysis/_javap_out/` 与 `_analysis/_javap_out2/`。转存件是临时产物，可以重新生成；行号指的是这些转存文本里的行。
- 版本号来自解包目录所属的 iris-fabric 构建（1.11.2+mc26.2）。`_analysis/irispk/net/irisshaders/iris/BuildConfig.class` 里 `IS_SHARED_BETA`、`BETA_TAG`、`BETA_VERSION` 都不是编译期常量（javap 只列出字段名、没有值），所以包装版本号不能从字节码里再确认一次，只能沿用解包目录的命名。〔读源码〕
- 旧版参照：`_analysis/irispk/iris_ShaderProperties_1.20.6.java` 与 `_analysis/irispk/iris_WorldRenderingPipeline_1.20.6.java` 是 **1.20.6 时代**的反编译源码。凡是引用它们的地方，本文都会注明"旧版 1.20.6"，并说明它和本机 1.11.2 的差别；**不能**把 1.20.6 的行为当作本机行为。
- 文档参照：`_analysis/shaderdoc_iris-features.md`（ShaderDoc 的 iris-features 页副本）与在线 ShaderDoc（本次另抓了 `buffers/ssbo`、`buffers/custom_images`、`buffers/image_format`、`programs/prepare`、`programs/overview` 五页，存进 `_analysis/shaderdoc_web/`）。文档只用来解释语义，**凡是文档与字节码冲突的地方一律以字节码为准**，下文冲突处已逐条标出。

术语先说一句话（给非渲染专业的读者）：
- *附件（attachment / colortex）*：一屏大小的中间图像，着色器可以把这一帧需要的信息写进去、后面的程序再读出来。
- *Mipmap*：同一张图按 1/2、1/4… 逐级缩小的副本，用于远处的模糊采样，代价是额外显存。
- *Early-Z（提前深度测试）*：显卡在实际跑片元着色器之前，先用深度把被挡住、肯定看不见的像素剔除掉。着色器里一旦出现 `discard`（丢弃该像素），这条优化就失效，因为显卡要等算完才知道要不要丢。
- *Compute shader（计算着色器，文件后缀 `.csh`）*：不画三角形、只做通用计算的着色器，Iris 用 `image.*` 自定义图像或 SSBO 当它的输入输出。
- *SSBO（着色器存储缓冲对象）*：一块可以按任意结构读写、还能跨帧保留的显存缓冲，比"图像"更自由。
- *uniform*：由引擎每帧算好、喂给着色器的只读变量，例如"当前时刻""玩家是否在地面"。

---

# 第一部分：能力边界与默认值（对应必答清单 a、b、c、d、e）

## (a) 引擎配置键：完整清单、默认值与实际收益

### 结论先行
Astra 的 `shaders.properties` 里**完全没有出现**的引擎配置键，按本次字节码核对共 23 个（下面给出每一条的 grep 结果）。其中**真正能带来性能或正确性收益的只有 3 个**：`allowConcurrentCompute`、`voxelizeLightBlocks`、`gbuffers_terrain_solid`（后者属于程序面，见 (e)）；`frustum.culling` 与 `occlusion.culling` 只是把引擎默认值写死（防跨版本漂移），价值是"工程整洁"；其余的价值很小或需要重做子系统，本文逐条说明并明确不建议哪些。

### 键的完整清单与默认值（证据：`_analysis/_javap_out2/PackDirectives.txt` 构造函数字节码）
下面每一条的默认值都是从字节码里读出来的：在读取 `ShaderProperties.getXxx()` 之后，紧接着是一条 `iconst_0`（默认 false）或 `iconst_1`（默认 true），再进入 `OptionalBoolean.orElse`。这是"没有显式声明时引擎采用哪个值"的直接证据。〔读源码〕

| 配置键 | 默认值 | 字节码证据（PackDirectives.txt） | Astra 现状 |
| --- | --- | --- | --- |
| `allowConcurrentCompute`（旧名 `concurrentCompute`） | false | 265 到 274 行 | 未声明 |
| `separateEntityDraws` | false | 173 到 182 行 | 未声明 |
| `voxelizeLightBlocks` | false | 161 到 170 行 | 未声明 |
| `frustum.culling` | **true** | 197 到 206 行 | 未声明（用默认） |
| `occlusion.culling` | **true** | 221 到 230 行 | 未声明（用默认） |
| `skipAllRendering` | false | 185 到 194 行 | 未声明 |
| `supportsColorCorrection` | false | 253 到 262 行 | 未声明 |
| `rain.depth` | false | 125 到 134 行 | 未声明 |
| `backFace.*`（solid / cutout / cutoutMipped / translucent） | 不是布尔默认值，是背面剔除开关 | ShaderProperties 解析点 1633 到 1660 行附近 | 未声明 |
| `separateAo` | false | 137 到 146 行 | Astra 有独立的 `separateAo`（3 处命中），已用 |
| `breaksAnisotropy` | false | 149 到 158 行 | 未声明 |
| `underwaterOverlay` | false | 29 到 38 行 | 未声明（Astra 自写水下叠加，行为上等价） |
| `vignette` | false | 41 到 50 行 | 未声明（Astra 自写暗角，行为上等价） |
| `sun` / `moon` / `stars` / `sky` / `weather` / `weatherParticles` | true | 53 到 124 行 | `stars=false` 已声明；其余用默认 |
| `oldLighting` / `oldHandLight` | false / **true** | 233 到 242 行 / 277 到 286 行 | `oldHandLight=false` 已声明 |
| `prepareBeforeShadow` | false | 305 到 314 行 | 未声明 |
| `endFlashShadows`（解析名 `endFlashShadows`，字段 `supportsEndFlash`） | false | 209 到 218 行 | 未声明 |
| `dhShadow.enabled` | false | ShaderProperties 解析点 1743 到 1754 行 | 未声明 |
| `particles.before.deferred` | false | ShaderProperties 解析点 1749 到 1754 行 | Astra 用的是 `particles.ordering=mixed`，实际等价 | 
| `allowConcurrentCompute` 的旧名：`concurrentCompute` | 不解析 | `_analysis/irispk/` 全目录 grep：`concurrentCompute` 只出现在 PackDirectives 与 ShaderProperties 的字段名与 getter，没有对应的字符串键 | 不适用 |
| `dimension.properties` | 不存在时不启用维度文件夹重定向 | `_analysis/irispk/net/irisshaders/iris/shaderpack/ShaderPack.class` 常量池含字符串 `dimension.properties` | 未提供该文件 |
| `flip.<program>.<buffer>` | 未声明时按引擎默认的隐式翻页 | ShaderProperties 解析点 1128 到 1145 行；`PackDirectives.getExplicitFlips` 被 `CompositeRenderer`、`ShadowCompositeRenderer` 消费 | 未声明（只有 :948 的注释里出现过 "flip" 字样） |
| `block.properties` 的 `renderStage` | 该键不在 `shaders.properties` 里，是方块匹配属性 | `uniform/CommonUniforms.class` 暴露 `renderStage` 这个 GLSL 变量（见 (b)） | Astra 已在 GLSL 里用 `renderStage`（20 处） |

### 逐个键的实际作用（只写有机制说明的）

**`allowConcurrentCompute`（性能，价值：大）**
- 机制：Iris 每发一次 compute dispatch 之前，默认会插一条显存屏障（`glMemoryBarrier` 的 `GL_SHADER_STORAGE_BARRIER_BIT`，数值 8232），保证这一组 compute 的写入对下一个程序可见，代价是同一组内的 compute 被**串行**执行。声明 `allowConcurrentCompute=true` 后这条屏障被跳过，同一组内的 dispatch 可以由显卡并行/重叠执行。
  证据：`_analysis/_javap_out2/ComputeProgram.txt` 的 `dispatch(float,float)` 字节码第 2 到 37 行——取当前 pipeline，调用 `WorldRenderingPipeline.allowConcurrentCompute()`，**为 false 时**才把 8232（`GL_SHADER_STORAGE_BARRIER_BIT`）加进屏障位掩码；第 50 到 57 行在有屏障位时执行 `IrisRenderSystem.memoryBarrier`。〔读源码〕
  另有一处无条件屏障：`_analysis/_javap_out2/CompositeRenderer.txt` 第 145 到 210 行，循环 dispatch 完之后执行一次 8232 屏障。所以开启后**组间**仍然同步，只是**组内**不再逐次同步。〔读源码〕
- 消费链：`PackDirectives.getConcurrentCompute()` 读到值后存进 `IrisRenderingPipeline.allowConcurrentCompute` 字段（`_analysis/_javap_out2/IrisRenderingPipeline.txt` 第 285 到 286 行），再由上面那条 `dispatch` 读取。〔读源码〕
- 参考出处（语义）：`_analysis/shaderdoc_iris-features.md:422-434`（"This value controls if compute shaders within the same pass are allowed to run concurrently"，键名 `allowConcurrentCompute`）。
- Astra 现状证据：对 `Astra/shaders`（425 个文件）grep 关键词 `allowConcurrentCompute` 与 `concurrentCompute`，均 **0 命中**；唯一含 "flip" 的 :948 行是注释，与本键无关。
- 迁移落点与代价：`Astra/shaders/shaders.properties:883` 那一行 `iris.features.optional=CUSTOM_IMAGES COMPUTE_SHADERS` 附近加一行 `allowConcurrentCompute=true`，不改任何 GLSL。代价是一次实机对照测。受益面是 `world-1/` 的九个 shadowcomp 计算阶段（`Astra/shaders/shaders.properties:860-878` 声明）与 `world1/setup.csh` 三连计算（`Astra/shaders/world1/setup.csh`、`setup1.csh`、`setup2.csh`）。
- 风险与前置核实：这些阶段之间存在**数据依赖**（第 0 阶段重建的活动数据被后续阶段采样，见 `Astra/shaders/shaders.properties:889` 的注释）。如果 Iris 的组内屏障正是这些依赖成立的原因，开启后会读到上一帧或半成品。**必须先实机验证末地与下界的体素光/星空在开启后无异常，且要开调试输出看时序**；不能只凭"帧数涨了"就采用。〔推断 + 待实测〕
- 许可注意：这是引擎配置键，不涉及任何参考包的代码许可。

**`voxelizeLightBlocks`（正确性 + 性能，价值：中偏大，取决于是否要做"光源方块参与光照"）**
- 机制：让"光源方块"（游戏里那个透明的 light block，用命令才能拿到、亮度可调）在阴影通道或主通道里参与渲染。它被渲染成一个退化（面积为零）的隐形四边形，四个点都落在方块中心，`at_midBlock` 为 0，`lmcoord.xy` 两个分量都等于该光源的亮度值。
  证据（文档）：`_analysis/shaderdoc_iris-features.md:485-492`。
  证据（字节码）：`_analysis/_javap_out2/PackDirectives.txt` 第 161 到 170 行读到 `getVoxelizeLightBlocks()`，默认 `iconst_0` 即 false；`shouldVoxelizeLightBlocks()` 的消费者是 `_analysis/irispk/net/irisshaders/iris/shaderpack/materialmap/WorldRenderingSettings.class`、`net/irisshaders/iris/compat/sodium/mixin/MixinChunkMeshBuildTask.class`（Sodium 的区块网格构建）与 `IrisRenderingPipeline` 第 979 到 980 行（写进 `WorldRenderingSettings`）。〔读源码〕
- Astra 现状证据：grep `voxelizeLightBlocks` 在 `Astra/shaders` **0 命中**。Astra 现有的 `BLOCKLIGHT_STRENGTH`/`NETHER_VOXEL_LIGHT` 体素光是从屏幕空间/深度重建的（`Astra/shaders/shaders.properties:840-878`，配套图像 `astraVoxelImage` 等，`shaders.properties:888-892`），**不是**从几何体素化来的。
- 迁移落点与代价：`Astra/shaders/shaders.properties:886-893` 那个 `#if` 块内加 `voxelizeLightBlocks=true`；消费端要新写一个只处理退化四边形（UV 为 0、位置在方块中心、亮度在 `lmcoord`）的分支，落在 `Astra/shaders/program/lit.fsh` 与体素光写入路径。代价是新的着色器分支加实机验证。
- 风险与前置核实：必须核实 Sodium（或本机实际的区块渲染器）下这条路径是否真的会拿到退化四边形；Astra 走的是"重建式"体素光，加入几何式光源会**两套机制叠加**，要先确认不会双计。没有实测不要开。
- 许可注意：引擎特性，不涉及参考包许可。

**`separateEntityDraws`（工程整洁，价值：小）**
- 机制：为 true 时，半透明实体与半透明方块实体的绘制被推迟到 deferred（延迟着色）之后，分别进 `gbuffers_entities_translucent` 与 `gbuffers_block_translucent` 两个程序。证据：`_analysis/shaderdoc_iris-features.md:494-499`；字节码 `_analysis/_javap_out2/PackDirectives.txt` 第 173 到 182 行（默认 false），消费者 `IrisRenderingPipeline` 第 482、984 到 985 行写入 `WorldRenderingSettings`。
- Astra 现状证据：grep `separateEntityDraws` **0 命中**；但 Astra **已经有** `Astra/shaders/gbuffers_entities_translucent.fsh`、`gbuffers_block_translucent.fsh`、`gbuffers_particles_translucent.fsh` 三个文件以及对应 `blend.*` 声明（`Astra/shaders/shaders.properties:371、410-411、413、419-422`）。也就是说：程序文件与混合声明都已就位，只有"让引擎真的把这些绘制路由进来"的开关没打开。
- 迁移落点与代价：`Astra/shaders/shaders.properties` 加 `separateEntityDraws=true`，一行；同时按 `shader_research/SUMMARY-batch5.md` 第 37 行（V5 条目）记录的纪律，把 `iris.features.optional` 追加 `ENTITY_TRANSLUCENT`（该键同样 0 命中）。
- 风险：会把半透明实体的**绘制时机**从"deferred 之前"挪到"之后"，光照/雾/水合成的可用信息改变，画面可能有明暗差异；必须与 V5 同组实机验证。在验证之前不建议开。
- 许可注意：不涉及参考包许可。

**`flip.<program>.<buffer>`（工程整洁，价值：小）**
- 机制：显式声明某个程序在写入某个附件之后要不要把它与"另一面"（乒乓缓冲的另一半）互换。Iris 默认会在多处隐式翻页；显式声明可以让着色器代码里"我现在读的是上一帧还是这一帧"的假设写实。
  证据：ShaderProperties 解析点 `_analysis/_javap_out2/ShaderProperties.txt` 第 1128 到 1145 行（`ldc "flip."`，走 `handleTwoArgDirective`）；读取方 `CompositeRenderer`、`ShadowCompositeRenderer`、`ProgramDirectives`（`_analysis/irispk/` 全目录 grep `getExplicitFlips`）。
- Astra 现状证据：grep `flip.` 在 `Astra/shaders` 只有 **1 处命中且是注释**：`Astra/shaders/shaders.properties:948` 的 "no shadow-source flip"。
- 迁移落点与代价：`Astra/shaders/shaders.properties` 的 cloud 历史相关位置（`shader_research/SUMMARY-batch5.md` 第 27 行已记录 `global/atmosphere/cloud_temporal.glsl:11-14` 依赖隐式翻页）。代价接近零。
- 风险：声明错方向会让历史缓冲读到当前帧，产生拖影或闪烁；必须逐程序核对"谁写、谁读、读的是哪一面"。
- 价值判断：**仅工程整洁**。它不产生新的画面效果、也不省性能，只是把已有的隐式行为写清楚。

### 明确不建议的键（避免下次再查）
- `skipAllRendering`（默认 false）：开启等于整帧不渲染，只对"用光影包做纯计算/截图工具"有意义。Astra 是正常游玩包，**不建议**。
- `prepareBeforeShadow`（默认 false）：把 prepare 阶段挪到阴影之前。Astra 现有 `prepare.fsh` 系程序写的东西不依赖阴影结果，挪动没有收益，**不建议**。
- `endFlashShadows`（默认 false）：让末地末影龙的死亡闪光参与阴影。Astra 的末地闪光已有自己的实现，开启会改变阴影信息语义，**不建议**。
- `dhShadow.enabled`（默认 false）：需要 Distant Horizons（远景 LoD 模组）路径。Astra 无 DH 路径，**不建议**（`shader_research/SUMMARY-batch5.md` 第 116 行已把整条 DH 方向判为不立项）。
- `rain.depth` 与 `beacon.beam.depth`（默认 false）：写深度缓冲，会改变 TAA 历史与 SSAO 判据，属于"要实测才知道好坏"的开关，价值不确定。**本次不建议直接开**（旧批次 V6 已把它们列为待实测项）。

### 参考出处汇总（a）
- `_analysis/_javap_out2/PackDirectives.txt`（构造函数 29 到 333 行）：全部默认值。
- `_analysis/_javap_out2/ShaderProperties.txt`（解析点 1560 到 1790 行）：全部键名与处理函数。
- `_analysis/_javap_out2/ComputeProgram.txt`（`dispatch` 方法）：`allowConcurrentCompute` 的唯一运行时消费点。
- `_analysis/shaderdoc_iris-features.md`：422-434、485-492、494-499 行。
- 旧版差异：`_analysis/irispk/iris_ShaderProperties_1.20.6.java` 是 1.20.6 版本源码，键名与默认值仅作对照，本报告未用它下任何结论。

---

## (b) 内置 uniform：哪些存在、语义是什么、能不能替代 Astra 的 CPU 表达式

### 结论先行
本次核对把三件事分开了：**真正存在的**、**只作为采样器存在的**、**本机 1.11.2 里根本不存在的**。必答清单里 `centerDepthSmooth`、`cloudHeight`、`logicalHeightLimit` 三者容易被混为一谈，实测结果如下。

### 存在且有价值的（可作为新效果输入）
| uniform | 语义 | 证据 | Astra 现状 | 价值 |
| --- | --- | --- | --- | --- |
| `eyeAltitude`（float） | 眼睛相对世界最低点的绝对高度（不是相对海平面） | `_analysis/_javap_out/uniform_CameraUniforms.txt` 常量池含 `eyeAltitude`（同类还含 `cameraPositionInt`/`cameraPositionFract`、`previousCameraPosition`） | grep 0 命中 | 小／中：高度驱动的雾、水下衰减、洞穴压暗可以做而不用 CPU 表达式 |
| `aspectRatio`（float） | 视口宽高比 | `_analysis/_javap_out/uniform_ViewportUniforms.txt`（同类含 `viewWidth`、`viewHeight`） | grep 0 命中；Astra 现在若有归一化需求是自己写表达式 | 小：省一次 CPU 表达式，语义等价 |
| `is_on_ground`（bool） | 玩家不飞且站在地面上为 true | `_analysis/_javap_out/uniform_CommonUniforms.txt` 常量池 | grep 0 命中 | 小：脚部湿痕/扬尘一类可选效果 |
| `hideGUI`（bool） | 隐藏 HUD 时为 true（F1 或截图） | `_analysis/_javap_out/uniform_CommonUniforms.txt` 第 146 行起：`UniformUpdateFrequency.PER_FRAME` 注册 `hideGUI`，取值来自 `Minecraft.gui.hud` 的可见性 | grep 0 命中 | 中：可用于"截图模式放开 TAA 历史钳制"（旧批次 A14 已论证），属于画面质量向 |
| `thunderStrength`（float） | 雷暴强度，相当于把 OptiFine 的 `rainStrength` 用在雷雨上 | `_analysis/_javap_out/uniform_IrisExclusiveUniforms.txt`；文档 `_analysis/shaderdoc_iris-features.md:170-177` | grep 0 命中 | 中：雷暴闪电与"阴沉度"可以独立于普通降雨驱动 |
| `cloudHeight`（float） | 当前维度原版云的高度（方块）；无云维度返回 NaN | `_analysis/_javap_out2/WorldInfoUniforms.txt` 常量池（`bedrockLevel`、`cloudHeight`、`heightLimit`、`logicalHeightLimit`、`hasCeiling`、`hasSkylight`、`ambientLight` 同处一类）；文档 `_analysis/shaderdoc_iris-features.md:254-262` | grep 0 命中 | 中：Astra 自己画云，这个值可以用于把自绘云与原版云层高对齐（仍是"可选对齐"，不是必须） |
| `logicalHeightLimit`（int） | 维度的"逻辑高度"上限（紫颂果/传送门能把玩家送到的高度） | 同上，`_analysis/_javap_out2/WorldInfoUniforms.txt` | grep 0 命中 | 小：末地/下界的高度相关归一化可以少写一点表达式 |

### 只作为采样器存在（不要当成 uniform 用）
- **`centerDepthSmooth` 不是本机 1.11.2 的 uniform，而是一个采样器**。证据：`_analysis/irispk/` 全目录 grep `centerDepthSmooth` 命中 `pathways/CenterDepthSampler.class`、`pipeline/CompositeRenderer.class`、`pipeline/FinalPassRenderer.class`、`pipeline/transform/transformer/CompositeDepthTransformer.class`；在全部 `uniform_*.txt` 中 0 命中。`IrisRenderingPipeline` 第 1035 到 1056 行构造 `CenterDepthSampler` 时读取 `PackDirectives.getCenterDepthHalfLife()`（半衰期来自 `const float centerDepthHalfLife`）。所以正确用法是 `uniform sampler2D centerDepthSmooth`，语义是"带时间平滑的上一帧场景深度"，用于景深自动对焦。〔读源码〕
  这一条同时纠正常见说法：旧批次 `shader_research/SUMMARY-batch5.md:24` 把它列为"内置 uniform"不准确；它存在，但形态是采样器。
- **`cloudHeight` 与 `logicalHeightLimit` 也不在扁平 `uniform_*` 清单里**：它们定义在嵌套类 `IrisExclusiveUniforms\$WorldInfoUniforms` 中（对应源文件里的静态内部类）。用"grep `_analysis/_javap_out/uniform_*.txt` 全 0 命中"得出"本版本不存在"的结论是**错的**。〔读源码〕

### 本机 1.11.2 里不存在的
- `atmosphere`：在 `_analysis/irispk/` 全 844 个 class 中 **0 命中**（以字符串 `atmosphere` 扫描），不是这个版本的 uniform。注意不要在 Astra 侧用同一个词去反证：Astra 有目录 `Astra/shaders/global/atmosphere/`，该词在 Astra 侧有命中，但那是目录/注释文本，不是引擎 uniform。〔读源码〕
- 其余必答清单里的名字（`sunAngle`、`worldTime`、`worldDay`、`sunPathRotation`、`moonPhase`）都存在，且 Astra **已经在用**（`Astra/shaders/shaders.properties:760` 用 `worldTime*0.0002617994`，以及 `worldDay`、`moonPhase`、`sunPathRotation` 的自定义表达式）。证据：`_analysis/_javap_out/uniform_WorldTimeUniforms.txt`（`worldTime`、`worldDay`、`moonPhase`）、`uniform_CelestialUniforms.txt`（`sunAngle`、`sunPosition`、`moonPosition`、`shadowAngle`、`shadowLightPosition`、`upPosition`）；`sunPathRotation` 另在 `PackDirectives.class`、`ShadowMatrices.class`、`ShadowRenderer.class`、`CelestialUniforms.class` 中出现。**因此"主世界星空缺 worldTime/worldDay/sunPathRotation"这个前提不成立，不需要新增。**〔读源码〕

### 参考出处（b）
- `_analysis/_javap_out/uniform_*.txt`（20 个 uniform 类的 javap 常量池）。
- `_analysis/_javap_out2/WorldInfoUniforms.txt`（嵌套类，含 7 个世界信息 uniform）。
- `_analysis/irispk/` 全目录字符串扫描（844 个 class）。
- `_analysis/shaderdoc_iris-features.md`：157-340、244-262 行。

---

## (c) customTexture / TEXTURE_3D / SSBO / compute / image3D 的能力边界

### 纹理目标（TextureType）：**不支持数组纹理**
- 本机 1.11.2 的 `TextureType` 枚举只有四个常量：`TEXTURE_1D`、`TEXTURE_2D`、`TEXTURE_3D`、`TEXTURE_RECTANGLE`。
  证据：`_analysis/_javap_out2/TextureType.txt`（`javap -p` 列出的 `public static final` 字段）。
- `SAMPLER_2D_ARRAY` 与 `TEXTURE_2D_ARRAY` 在整个 844 个 class 里 **0 命中**。所以**这个版本不能用数组纹理**（`sampler2DArray`）做自定义纹理或自定义图像。
- 自定义图像与自定义纹理支持 1D、2D、3D，以及 `size.buffer` 那种"屏幕尺寸相对大小"声明。

### 自定义图像 `image.<name>`：格式、尺寸、数量上限
- 语法（本机字节码验证）：`image.<imageName> = <samplerName> <format> <internalFormat> <pixelType> <shouldClearOnNewFrame> <isRelative> <X> <Y> [Z]`。
  证据：`_analysis/_javap_out2/ShaderProperties.txt` 第 2080 到 2210 行的解析分支——先按空格切分；当字段数为 8 且 `isRelative` 为 true 时，尺寸读 float 并构造 `TEXTURE_2D` 加相对标志；字段数为 7 时是 `TEXTURE_1D`（读整数 X）；字段数为 8 时是 `TEXTURE_2D`（读整数 X、Y）；字段数为 9 时是 `TEXTURE_3D`（读整数 X、Y、Z）；其他字段数走 `Iris.logger.error` 并直接返回，即**这个 image 声明被丢弃**。〔读源码〕
- 数量上限：**本机不在 Iris 侧硬编码**。`ShaderProperties` 里没有任何"图像数量上限"检查（对该文件全文核对 `MAX_IMAGE`、`irisCustomImages.size()` 一类模式无命中），真正的上限来自驱动暴露的 `GL_MAX_IMAGE_UNITS`（`_analysis/_javap_out2/ImageLimits.txt` 构造时调用 `IrisRenderSystem.getMaxImageUnits()`）。
  文档差异提示：`_analysis/shaderdoc_iris-features.md:565` 说"最多 8 张"，在线 ShaderDoc 已改成"最多 16 张（Iris 1.6.4 之前是 8）"。本机 1.11.2 的行为是"按驱动上限"。Astra 自己在 `Astra/shaders/shaders.properties:885` 记的是 "Iris 1.11.2 caps custom images at 15"——这条**与本次核对的字节码不一致**（Iris 侧没有常量 15），建议以后按驱动能力描述，不要写死数字。〔读源码 + 推断〕
- 像素格式（`format`）的合法值（`_analysis/_javap_out2/PixelFormat.txt`）：`RED`、`RG`、`RGB`、`BGR`、`RGBA`、`BGRA`，以及各自的 `_INTEGER` 变体。
- 内部格式（`internalFormat`）的合法值（`_analysis/_javap_out2/InternalTextureFormat.txt`，共 55 个）：归一化 R/RG/RGB/RGBA 的 8/16 位与 SNORM 变体、半浮点 16F 与 32F 全系、整数 I 与无符号 UI 的 8/16/32 位、以及 `RGB10_A2`、`RGB10_A2UI`、`R11F_G11F_B10F`、`RGB9_E5`、`RGBA4`、`RGB5_A1`、`RGB565`、`R3_G3_B2`、`RGBA2`。
- Astra 现状证据：已用 4 张自定义图像（`Astra/shaders/shaders.properties:888-892`：`red_integer/r32ui` 的 64³ 体素占用图、2×1 的源分块图、两张 `rgba/rgba16f` 的 64³ 传播图）。`TEXTURE_3D` 与 `image3D` 已用。
- 结论：**图片面没有"没用到"的大能力**。唯一明确缺的是**数组纹理**（见上），而数组纹理在本版本里根本不存在，不是"没用"。

### SSBO `bufferObject.<index>`：本机上限比文档更宽
- 语法两种：固定大小 `bufferObject.<index> = <总字节数>`；屏幕相对 `bufferObject.<index> = <每像素字节数> <isRelative> <scaleX> <scaleY>`。
  证据：`_analysis/_javap_out2/ShaderProperties.txt` 第 2640 到 2760 行——按空格切分后，字段数不超过 2 走固定大小分支，否则读 `isRelative`、`scaleX`、`scaleY`。〔读源码〕
- 索引上限：字节码里是 `if (index > 12) → Iris.logger.fatal("SSBO's cannot use buffer numbers higher than 12, they're reserved!") → 丢弃`。也就是**合法索引是 0 到 12，共 13 个**。
  证据：`_analysis/_javap_out2/ShaderProperties.txt` 第 2663 到 2678 行（固定大小分支）与第 2721 到 2736 行（相对大小分支），两处都是 `bipush 12` 后 `if_icmple`。〔读源码〕
  **与文档冲突**：`_analysis/shaderdoc_iris-features.md:525` 与在线 `buffers/ssbo` 页都写 "index 0 to 8"。本机实际更宽（0 到 12）。用文档时要以 0..12 为准，但也不要故意贴上限。
- 大小下限：`byteSize < 1` 会被静默丢弃（字节码里 `lload 4; lconst_1; lcmp; ifge`；小于 1 直接 return）。所以 `bufferObject.0 = 0` 不是"空缓冲"，而是"没声明"。
- 特性标志：使用 SSBO 必须声明 `iris.features.*` 里的 `SSBO`（`_analysis/_javap_out2/FeatureFlags.txt` 含 `SSBO` 常量）。
- Astra 现状证据：grep `bufferObject.` 与 `SSBO` 在 `Astra/shaders` **0 命中**；`Astra/shaders/shaders.properties:883` 声明的是 `CUSTOM_IMAGES COMPUTE_SHADERS`，没有 `SSBO`。Astra 的体素光用 4 张自定义图像实现，没有用 SSBO。
- 价值判断：**中**。SSBO 相对自定义图像的优势是"任意结构 + 不受图像单位限制"。Astra 现在用图像是够的；只有在体素数据体积超出图像寻址或需要更灵活结构时才值得迁移。**不建议为了"用上 SSBO"而迁移**。

### compute：本机支持情况
- `compute` 程序存在且 Astra 已用。证据：`_analysis/_javap_out2/ComputeProgram.txt`、`_analysis/_javap_out2/ComputeSource.txt`、`_analysis/_javap_out2/ComputeDirectiveParser.txt` 均存在；Astra 侧有 `Astra/shaders/program/end_star_catalogue.csh`、`end_star_rows.csh`、`nether_light.csh`、`world1/setup.csh`、`world1/setup1.csh`、`world1/setup2.csh`、`world-1/shadowcomp.csh` 到 `shadowcomp8.csh` 共 15 个计算着色器文件。
- 工作组分发支持相对屏幕尺寸与绝对尺寸（`ComputeProgram.getWorkGroups(float,float)`、`setWorkGroupInfo(Vector2f, Vector3i, FilledIndirectPointer)`），还支持间接分发（`IrisRenderSystem.dispatchComputeIndirect`）。`indirect.<program>` 指令键存在但 Astra 0 命中。
- 特性标志：`COMPUTE_SHADERS`（Astra 已声明）。

### 参考出处（c）
- `_analysis/_javap_out2/TextureType.txt`、`PixelFormat.txt`、`InternalTextureFormat.txt`、`PixelType.txt`、`ImageInformation.txt`、`ImageLimits.txt`、`ComputeProgram.txt`、`ProgramImages.txt`（枚举常量与构造签名）。
- `_analysis/_javap_out2/ShaderProperties.txt`：2080-2210（image 解析）、2640-2760（bufferObject 解析）。
- `_analysis/shaderdoc_iris-features.md`：515-562（SSBO）、563-610（自定义图像）。
- 在线：`_analysis/shaderdoc_web/ssbo.html`、`image_format.html`、`custom_images.html`。

---

## (d) 渲染目标：colortex0-31、shadowcolor0-7、shadowtex0HW/1HW

### colortex
- 基线支持的是 **colortex0 到 colortex31**，共 32 个。证据：`_analysis/_javap_out2/PackRenderTargetDirectives.txt` 第 241 行起的静态初始化——`LEGACY_RENDER_TARGETS` 是 8 个旧名（`gcolor`、`gdepth`、`gnormal`、`composite`、`gaux1`…`gaux4`）；紧接着是一个循环，从 0 到 31（`bipush 32; if_icmpge`）逐个加入 `BASELINE_SUPPORTED_RENDER_TARGETS`。超过 31 不在基线集合内，能不能用取决于驱动与 Iris 的运行时检查。〔读源码〕
- 每个附件的格式由 `<bufferName>Format`（旧名 `<bufferName>Format` 与 `GAUX4FORMAT` 注释形式）指定；`PackRenderTargetDirectives` 用 `InternalTextureFormat.fromString` 解析，解析失败时只 `warn` 并保留默认。特殊规则：`colortex1`（旧名 `gdepth`）在 `acceptDirectives` 第 51 到 65 行被检查，如果请求格式是 `RGBA` 会被强制改成 `RGBA32F`。
  证据：`_analysis/_javap_out2/PackRenderTargetDirectives.txt` 第 106 到 140 行（`acceptBufferDirectives` 接 `<name>Format`、`<name>Clear`、`<name>ClearColor` 三个常量指令）、第 190 到 205 行（RGBA→RGBA32F）。〔读源码〕
- Astra 现状：已在 `shaders.properties` 声明 `size.buffer.*` 覆盖 colortex1/2/6 到 31（缺 0、3、4、5、7 等，属正常留白）。可用的格式值就是 (c) 里那 55 个 `InternalTextureFormat` 常量。

### shadowcolor
- **shadowcolor0 与 shadowcolor1 是无条件存在的**；shadowcolor2 到 shadowcolor7 需要特性标志 `HIGHER_SHADOWCOLOR`。
  证据：构造 `ShadowRenderTargets`（`_analysis/_javap_out2/ShadowRenderTargets.txt` 第 38 到 60 行）时，先查 `WorldRenderingPipeline.hasFeature(FeatureFlags.HIGHER_SHADOWCOLOR)`，为真取 8，为假取 2，然后按这个大小分配 `new RenderTarget[size]`、`new InternalTextureFormat[size]`。〔读源码〕
  `PackShadowDirectives` 的颜色采样设置遍历 0 到 7（`_analysis/_javap_out2/PackShadowDirectives.txt` 第 317 到 410 行，`bipush 8` 的双重循环），所以 8 个键名都解析，但只有前 2 个在未声明特性标志时真正分配。
  另有一个特殊采样器名 `shadowcolorimg0` / `shadowcolorimg1`（`_analysis/_javap_out2/IrisImages.txt` 常量池），用于把 shadowcolor 当"图像"写入。
- Astra 现状：grep `shadowcolor` 有命中（`Astra/shaders/block.properties` 与着色器里用它做彩色阴影），但**没有声明 `HIGHER_SHADOWCOLOR`**，也 `shadowcolor2` 以上 0 命中。也就是说 Astra 只用了无条件存在的 shadowcolor0/1。
- 价值判断：**仅工程整洁／大工程前置**。更多彩色阴影附件是"反射阴影贴图（RSM，把场景颜色与法线写进阴影侧附件再在屏幕空间做间接光）"的**前置条件**。但 RSM 本身是完整子系统（新附件、新采样、新去噪），不是打开一个开关就有画面。**不建议**为"用上 shadowcolor2-7"而开；只有将来立项做 RSM 时再开。注意"前置存在"与"值得做"是两件事。

### shadowtex0HW / shadowtex1HW
- 存在，但**只在硬件过滤（hardware filtering）开启时注册**，并且要求特性标志 `SEPARATE_HARDWARE_SAMPLERS`。
  证据：`_analysis/_javap_out2/IrisSamplers.txt` 第 425 到 452 行：`if (ShadowRenderTargets.isHardwareFiltered(0) && <boolean 参数>) → addDynamicSampler(..., "shadowtex0HW")`，索引 1 同理注册 `shadowtex1HW`。那个 boolean 参数的来源是 `FeatureFlags.SEPARATE_HARDWARE_SAMPLERS`——`_analysis/_javap_out2/CompositeRenderer.txt` 第 1019 到 1021 行在调用 `IrisSamplers.addShadowSamplers(holder, targets, buffers, boolean)` 前读取该标志；`FinalPassRenderer` 与 `ShadowCompositeRenderer` 同样读取。〔读源码〕
- 语义：开启后 `shadowtex0`/`shadowtex1` **不再**是硬件比较采样器，硬件过滤要通过 `shadowtex0HW`/`shadowtex1HW` 拿，软件过滤仍走原来的名字，于是可以在同一帧里同时用两种过滤。
- Astra 现状：grep `shadowtex0HW`、`shadowtex1HW` **0 命中**；Astra 用的是软件 PCF（`lib/settings.glsl:685-691` 里的 `shadowHardwareFiltering` 开关）。
- 价值判断：**小**。Astra 的阴影过滤是自写 PCF，换成硬件比较采样器会改变过滤形状与偏移标定（`Astra/shaders/lib/distort.glsl` 的换算基于当前做法），收益是采样数减少。**本次不建议**：收益不确定而返工面大。

### 参考出处（d）
- `_analysis/_javap_out2/PackRenderTargetDirectives.txt`（静态初始化 + acceptDirectives）。
- `_analysis/_javap_out2/ShadowRenderTargets.txt`（构造函数 38-60 行）。
- `_analysis/_javap_out2/PackShadowDirectives.txt`（颜色/深度采样 220-470 行）。
- `_analysis/_javap_out2/IrisSamplers.txt`（425-452 行）、`CompositeRenderer.txt`（1019-1021 行）、`FeatureFlags.txt`。
- `_analysis/shaderdoc_iris-features.md`：501-513（独立硬件采样器）、509-513（扩展 shadowcolor）。

---

## (e) 程序层面：本机存在但 Astra 未用的阶段

### 本机 1.11.2 支持的全部程序名与阶段
证据（枚举常量）：
- `_analysis/_javap_out2/ProgramId.txt` 的常量池给出：`Shadow`、`ShadowSolid`、`ShadowCutout`、`ShadowWater`、`ShadowEntities`、`ShadowLightning`、`ShadowBlock`、`Basic`、`Line`、`Textured`、`TexturedLit`、`SkyBasic`、`SkyTextured`、`Clouds`、`Terrain`、`TerrainSolid`、`TerrainCutout`、`DamagedBlock`、`Block`、`BlockTrans`（文件名 `gbuffers_block_translucent`）、`BeaconBeam`、`Item`、`Entities`、`EntitiesTrans`（`gbuffers_entities_translucent`）、`Lightning`、`Particles`、`ParticlesTrans`（`gbuffers_particles_translucent`）、`EntitiesGlowing`、`ArmorGlint`、`SpiderEyes`、`Hand`、`Weather`、`Water`、`HandWater`、`DhTerrain`、`DhWater`、`DhGeneric`、`DhShadow`、`Final`。
- `_analysis/_javap_out2/ProgramArrayId.txt` 给出六个可编号阶段：`Setup`、`Begin`、`ShadowComposite`、`Prepare`、`Deferred`、`Composite`。
- `IrisRenderingPipeline` 构造函数实际引用了 `ProgramArrayId.Begin`、`Prepare`、`Deferred`、`Composite`、`ShadowComposite`（`_analysis/_javap_out2/IrisRenderingPipeline.txt` 常量池），Setup 由单独的 `createSetupComputes` 处理（同文件 1457 行）。〔读源码〕
- 在线文档 `programs/overview`（本次抓取）给出执行顺序：setup（仅计算）→ begin → shadow → shadowcomp → prepare → gbuffers（不透明）→ deferred → gbuffers（半透明）→ composite → final。`programs/prepare`（本次抓取）写明 prepare 跑在阴影之后、gbuffers 之前。〔读文档〕

### Astra 已用与未用
已用（grep 与文件核对）：`prepare*`（`prepare.fsh` 到 `prepare4.fsh` 及顶点版）、`deferred1-3`（目前只有 `.vsh` 文件）、`composite` 到 `composite9`、`final`、`shadow` 与 `shadow_solid`、`world1/setup.csh` 与 `setup1/setup2.csh`、`world-1/shadowcomp.csh` 到 `shadowcomp8.csh`、`gbuffers_*` 共 25 类。

未用（逐项 grep 结果）：
| 程序名 | Astra grep 结果 | 备注 |
| --- | --- | --- |
| `gbuffers_terrain_solid` | **0 命中**（`gbuffers` 目录下无同名文件） | 见下方"价值：大"分析 |
| `gbuffers_terrain_cutout` | **0 命中** | 同上 |
| `begin.csh`（begin 阶段） | **0 命中** | 见下方 |
| `gbuffers_entities_glowing` | **0 命中** | 价值小 |
| `dh_terrain` / `dh_water` / `dh_generic` / `dh_shadow` | **0 命中** | 需要 Distant Horizons，Astra 无该路径，**不建议** |
| `voxy_*` | **0 命中（且引擎侧 0 命中）** | 见下方"澄清" |
| `gbuffers_entities_translucent` / `gbuffers_block_translucent` / `gbuffers_particles_translucent` | **有文件、有 blend 声明** | 缺的是 (a) 里的 `separateEntityDraws` 开关 |

### 澄清：`voxy_*` 不是 Iris 程序
在 `_analysis/irispk/` 全 844 个 class 中，字符串 `voxy` 与 `voxy_` 均 **0 命中**。Astra 侧的 `voxy_` 命中来自 `Astra/shaders/lib/uniforms.glsl:162`、`program/lit_voxy.fsh:4`、`voxy_opaque.glsl:1-2`，配套还有 `Astra/shaders/voxy.json` 与 `voxy_translucent.glsl`；这些是 **Voxy 模组自己**的接口约定，不是 Iris 的程序名。所以"要用 voxy_* 阶段"这个方向不成立。〔读源码〕

### 值得关注的三个程序面

**`gbuffers_terrain_solid` / `gbuffers_terrain_cutout`（价值：大，前提是实测）**
- 机制：Iris 1.6 起把地形拆成"实体地形"（solid，完全不透明）与"镂空地形"（cutout，有透明孔洞）两个独立程序。文档明确说明：使用核心（core）配置文件时，实体地形程序里可以**安全地不使用 `discard`**，从而保住 early-Z（提前深度测试）。
  证据：`_analysis/shaderdoc_iris-features.md:26-44`。
- Astra 现状：`Astra/shaders/gbuffers_terrain.vsh` 与 `.fsh` 存在，但**没有** `gbuffers_terrain_solid` 与 `gbuffers_terrain_cutout` 文件，也没有在 `shaders.properties` 里声明。地形走的是共享的 `Astra/shaders/program/lit.fsh`，而那里存在多处 `discard`：`Astra/shaders/program/lit.fsh:180`（通用丢弃）、`:290`（`albedo.a < 0.32` 的镂空阈值）、`:297` 与 `:300`（`albedo.a < alphaTestRef`）、`:305`（`albedo.a <= 0.0`）。
  grep 证据：`gbuffers_terrain_solid` 与 `gbuffers_terrain_cutout` 在 `Astra/shaders`（425 文件）均 0 命中。
- 迁移落点与代价：新增 `Astra/shaders/gbuffers_terrain_solid.fsh` 与 `.vsh`（小的入口文件，包含 `/program/lit.fsh` 并定义一个"我不需要 discard"的宏，把 `:290`、`:297`、`:300`、`:305` 四个镂空判断编译掉）；`gbuffers_terrain_cutout` 保持现有 `discard` 分支。工作集中在 `Astra/shaders/program/lit.fsh` 的宏分层，不是重写。
- 风险与前置核实：Iris 判定"实体/镂空"的规则必须先核实（哪些方块落在 solid）；判断错会让本该镂空的叶子/草被整片填实。**没有实机验证不要合并。** 另外 core 配置下 Iris 才会注入正确的 `discard` 语义，需要确认本机跑的是 core 还是 compatibility profile。这是本报告里**收益最明确**的程序面改动：early-Z 对地形填充率的影响通常比多算几次采样更直接。
- 许可注意：这是引擎特性，不涉及参考包代码。

**`begin` 阶段（价值：仅工程整洁／小）**
- 机制：begin 是在阴影之前跑的全屏合成式通道，用来准备阴影通道需要的数据（文档 `_analysis/shaderdoc_iris-features.md:88-96`；在线 `programs/overview` 的执行顺序也把它排在 shadow 之前）。
- Astra 现状：`begin.csh` **0 命中**；Astra 把阴影前需要准备的数据放在 `world1/setup.csh`（setup 只在加载/改分辨率时跑一次）或者干脆在顶点/片元里算。
- 价值判断：**小**。Astra 目前没有"每帧阴影前需要现算的全屏数据"这个需求；引入 begin 只会多一个通道。**不建议**为对称性引入。

**`setup.csh` 的通用计算能力（Astra 只在一个维度用了）**
- 机制：setup 是只计算、只在包加载或分辨率变化时跑一次的阶段，可用 `_a` 到 `_z` 后缀挂多个（文档 `_analysis/shaderdoc_iris-features.md:98-107`）。
- Astra 现状：`Astra/shaders/world1/setup.csh`、`setup1.csh`、`setup2.csh` 只在 `world1`（末地）目录下存在；主世界与下界没有 setup。
- 价值判断：**仅工程整洁**。末地星表在加载期预先算好是正确用法。主世界没有同类"加载期常量表"需求（噪声纹理由引擎提供、体素光要每帧更新）。**不建议**为了统一而在其他维度补 setup。

### 参考出处（e）
- `_analysis/_javap_out2/ProgramId.txt`、`ProgramArrayId.txt`（枚举常量池）。
- `_analysis/_javap_out2/IrisRenderingPipeline.txt`（构造函数中的 ProgramArrayId 引用、`createSetupComputes` 1457 行）。
- `_analysis/shaderdoc_iris-features.md`：24-107（新程序）。
- 在线：`programs/overview`、`programs/prepare`（本次抓取，存 `_analysis/shaderdoc_web/`）。

---

# 第二部分：每条的能力价值判断汇总

| 条目 | 价值 | 一句话理由 |
| --- | --- | --- |
| `allowConcurrentCompute=true` | **大**（前提：实测数据依赖安全） | 直接去掉同一组内逐次 compute 的显存屏障，Astra 有 12 个计算阶段 |
| `gbuffers_terrain_solid` | **大**（前提：核实 solid 判定规则） | 保住地形的 early-Z，省的是填充率而不是采样数 |
| `voxelizeLightBlocks=true` | 中偏大（前提：不与现有重建式体素光双计） | 让光源方块以几何方式进入光照，省掉一部分屏幕空间重建工作量 |
| `SSBO`（`bufferObject.*`） | 中（仅在数据形态需要时） | 任意结构、不受图像单位限制；Astra 现在用图像已够，不建议无理由迁移 |
| `thunderStrength` | 中 | 雷暴强度可独立驱动，现用 `rainStrength` 近似 |
| `hideGUI` | 中 | 可做"截图模式放开 TAA 历史钳制" |
| `cloudHeight` / `logicalHeightLimit` / `eyeAltitude` / `aspectRatio` / `is_on_ground` | 小 | 省一两个 CPU 表达式，或做可选的高度驱动效果 |
| `shadowcolor2-7` + `HIGHER_SHADOWCOLOR` | 仅工程整洁（RSM 前置） | 附件本身不产生画面，RSM 才是完整子系统 |
| `shadowtex0HW` / `shadowtex1HW` + `SEPARATE_HARDWARE_SAMPLERS` | 小 | 换硬件比较采样器要重标定现有 PCF |
| `separateEntityDraws` + `ENTITY_TRANSLUCENT` | 仅工程整洁 | Astra 的程序文件与 blend 声明已就位，只差路由开关 |
| `flip.*` | 仅工程整洁 | 把隐式乒乓翻页写实，不省性能、不加效果 |
| `begin` 阶段 | 小，**不建议** | Astra 没有"每帧阴影前全屏准备"的需求 |
| `frustum.culling` / `occlusion.culling` 写死默认值 | 仅工程整洁 | 防跨版本默认值漂移，行为零变化 |
| `dh_*` 程序与 `dhShadow.enabled` | **不建议** | Astra 没有 Distant Horizons 路径 |
| `voxy_*` | **不成立** | 不是 Iris 程序名，是 Voxy 模组接口 |
| `dimension.properties` | 小 | 给自定义维度独立入口；Astra 三维度用目录已够 |
| `skipAllRendering` / `prepareBeforeShadow` / `endFlashShadows` / `rain.depth` / `beacon.beam.depth` / `backFace.*` / `breaksAnisotropy` | **不建议** | 分别服务于整帧跳过、阶段重排、末影龙闪光阴影、雨幕写深度、信标光束写深度、背面剔除、各向异性失效；Astra 均无对应需求 |

---

# 第三部分：给主代理的三条最确定结论

1. **`allowConcurrentCompute` 是本轮唯一"性能收益明确、改动一行"的引擎键**，而且它的生效机制已经从字节码读实：未声明时 Iris 在每次 compute dispatch 前插 `GL_SHADER_STORAGE_BARRIER_BIT`（8232）屏障，声明为 true 则跳过。风险点是 Astra 的 shadowcomp 链存在真实数据依赖，必须先实机验证再采用。（证据：`_analysis/_javap_out2/ComputeProgram.txt` 的 `dispatch` 方法；`_analysis/_javap_out2/PackDirectives.txt:161-182`；`Astra/shaders/shaders.properties:860-878`。）

2. **"Astra 缺 `worldTime`/`worldDay`/`sunPathRotation`"这个前提是错的**：三者在本机 1.11.2 都存在，而且 Astra 已经在用（`Astra/shaders/shaders.properties:760` 用 `worldTime`，另有 `worldDay`、`moonPhase`、`sunPathRotation` 的自定义表达式）。同时纠正两处易错：`centerDepthSmooth` 在本版本是**采样器**（`CenterDepthSampler`）不是 uniform；`cloudHeight` 与 `logicalHeightLimit` 存在，但定义在嵌套类 `IrisExclusiveUniforms\$WorldInfoUniforms` 里，用"扁平 `uniform_*` 清单 0 命中"判定"不存在"会得出错误结论。（证据：`_analysis/_javap_out/uniform_WorldTimeUniforms.txt`、`uniform_CelestialUniforms.txt`、`_analysis/_javap_out2/WorldInfoUniforms.txt`、`_analysis/irispk` 全目录字符串扫描。）

3. **程序面唯一值得立项的是 `gbuffers_terrain_solid`（以及配套的 `gbuffers_terrain_cutout`）**：Iris 允许实体地形程序不使用 `discard` 从而保住 early-Z，而 Astra 的地形走共享的 `Astra/shaders/program/lit.fsh`，其中 `lit.fsh:290/297/300/305` 有四处镂空丢弃，等于对所有地形都关掉了 early-Z。此外本报告同时否掉了两个常见候选：`voxy_*` 不是 Iris 程序（844 个 class 中 0 命中），`dh_*` 需要 Distant Horizons 而 Astra 无该路径。（证据：`_analysis/shaderdoc_iris-features.md:26-44`；`_analysis/_javap_out2/ProgramId.txt`；`Astra/shaders/program/lit.fsh`；`Astra/shaders` 全目录 grep。）

---

# 附：本次实际执行的 grep 关键词与结果（"Astra 没有"的证据）

搜索根目录：`Astra/shaders`，共 425 个文件（含全部 `.glsl`、`.fsh`、`.vsh`、`.csh`、`.properties`、`.json`、`.lang`）。匹配方式为逐行子串匹配（不是正则、不看大小写以外的变体）。

**0 命中（确认 Astra 未使用）**：
`allowConcurrentCompute`、`concurrentCompute`、`separateEntityDraws`、`voxelizeLightBlocks`、`dimension.properties`、`frustum.culling`、`occlusion.culling`、`skipAllRendering`、`endFlashShadows`、`dhShadow`、`prepareBeforeShadow`、`particles.before.deferred`、`underwaterOverlay`、`dhClouds`、`rain.depth`、`beacon.beam.depth`、`breaksAnisotropy`、`backFace.solid`、`generateShadowMipmap`、`generateShadowColorMipmap`、`shadowtexNearest`、`voxelDistance`、`oldLighting`、`supportsColorCorrection`、`alphaTest.`、`indirect.`、`fallbackTex`、`bufferObject.`、`TEXTURE_3D`（作为 `.properties` 键或程序名；GLSL 里用的是 `image3D`/`sampler3D`）、`SAMPLER_2D_ARRAY`、`shadowtex0HW`、`shadowtex1HW`、`HIGHER_SHADOWCOLOR`、`SEPARATE_HARDWARE_SAMPLERS`、`ENTITY_TRANSLUCENT`、`SSBO`、`gbuffers_terrain_solid`、`gbuffers_terrain_cutout`、`begin.csh`、`setup.csh`（作为不带维度前缀的声明；实际存在的是 `world1/setup.csh`）、`dh_terrain`、`dh_water`、`dh_generic`、`dh_shadow`、`entities_glowing`、`centerDepthSmooth`、`aspectRatio`、`hideGUI`、`thunderStrength`、`is_on_ground`、`eyeAltitude`、`cloudHeight`、`logicalHeightLimit`。

**命中但需要排除的假阳性（避免误判为"已使用"）**：
- `flip.`：仅 `Astra/shaders/shaders.properties:948` 一处，内容是注释文本 "no shadow-source flip"，**不是配置键**。
- `vignette`（10 处）、`sun=`（1 处）、`moon=`（2 处）、`sky=`（7 处）、`weather=`（2 处）：这些命中都是 GLSL 里的**局部变量名或函数名**（例如 `Astra/shaders/global/post/grading.glsl:235` 的 `apply_vignette` 函数、`Astra/shaders/lib/twilight.glsl:44` 的局部变量 `sun`），**不是 `shaders.properties` 里的引擎配置键**。
- `noiseTextureResolution`：仅 `Astra/shaders/lib/settings.glsl:461` 的一个 GLSL 常量声明，不是引擎指令。
- `voxy_`：Astra 侧有命中（`lib/uniforms.glsl:162`、`program/lit_voxy.fsh:4`、`voxy_opaque.glsl:1-2`），但那是 Voxy 模组接口文件的文本，不是 Iris 程序名。Iris 侧以字符串 `voxy` 扫描 844 个 class，0 命中。0 命中清单里其余名字都在 Astra 侧实测过，只有这一项例外，所以单列到这里。
- `shadowDistance`（18 处）与 `shadowIntervalSize`（2 处）：`shadowDistance` 在 `Astra/shaders/lib/settings.glsl` 里是 GLSL 常量（下游使用者如 `global/lighting/diffuse.glsl:315`、`global/lighting/shadowmap.glsl:120`），`shadowIntervalSize` 在 `lib/settings.glsl:454` 与 `:456` 被定义为 0.0 或 0.5 的 GLSL 常量。这两个名字在 Iris 里**同时**是配置键和 GLSL 常量，Astra 使用的是后者，**引擎指令本身未声明**。
- `shadowHardwareFiltering`（6 处）：全部在 `Astra/shaders/lib/settings.glsl:685-691`，是 GLSL 常量。

**确认已在用（不属于本轮缺口）**：`worldTime`、`worldDay`、`moonPhase`、`sunPathRotation`、`renderStage`（GLSL 变量，20 处）、`image.`（`shaders.properties:888/890/891/892`）、`image3D`、`customTexture.*`、`shadowcolor`、`size.buffer.*`（colortex1/2/6-31）、`blend.*`、`particles.ordering=mixed`、`separateAo`、`shadow.culling=false`（`shaders.properties:361`）、`oldHandLight=false`、`stars=false`、`clouds=off`、`iris.features.optional=CUSTOM_IMAGES COMPUTE_SHADERS`（`shaders.properties:883`）。

---

# 附：本次没有确认的事项（明确写"未确认"，不要当成结论）

1. `allowConcurrentCompute=true` 在 Astra 的实际场景下**是否真的提升帧数**——未实测。本次只读到了"屏障被跳过"这个机制，没有任何运行时数据。
2. Astra 的 shadowcomp 链内部各阶段之间的数据依赖**具体强度**（是否每一阶段都依赖上一阶段，还是存在可安全并行的分支）——未逐阶段核对九个 `.csh` 的读写关系。
3. 本机跑的是 core profile 还是 compatibility profile——这直接决定 `gbuffers_terrain_solid` 去掉 `discard` 是否安全（文档说的是 core profile 下安全）。未在实例中确认。
4. Iris 把哪些方块判为 solid、哪些判为 cutout 的**具体规则**——未读 `compat/sodium` 与 `mixin` 下的网格构建代码，无法给出分类清单。
5. `voxelizeLightBlocks` 在 Astra 使用的区块渲染路径（是否 Sodium）下**是否真的会下发退化四边形**——只确认了 `WorldRenderingSettings` 与一个 Sodium mixin 会读这个标志，没有跟踪到实际顶点提交。
6. `shadowcolor2-7` 在声明 `HIGHER_SHADOWCOLOR` 后**是否受驱动 draw buffer 数量限制**而实际不可用——`PackShadowDirectives` 的键会解析，`ShadowRenderTargets` 会分配 8 个，但最终 framebuffer 的 draw buffer 数量取决于驱动，未在本机确认。
7. 在线 ShaderDoc 的 `miscellaneous/shader_properties` 页面本次返回 404（`Astra` 侧无影响，但该页的"全部配置键一览"没有取到，本文的键清单完全来自字节码，反而更可靠）。
8. `_analysis/irispk` 的版本号只由解包目录命名给出，`BuildConfig` 里没有可读的版本常量，无法在字节码层面再确认一次。

---

生成时间：本次会话。本报告全部为只读调研，未修改 `Astra/` 或 `reference_shaderpacks/` 下任何文件；新增的仅本文件与 `_analysis/shaderdoc_web/` 下 4 个文档抓取件、`_analysis/_javap_out2/` 下若干反编译文本。
