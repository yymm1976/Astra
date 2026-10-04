# 下一批 Agent 任务提示词：R1–R6

更新于 2026-09-27。唯一开发总表是 [持续待办](2026-09-26-itt32-initial-implementation.md)。本文件接续已经写入的 H1 方向性天光、H2 标量 AO、T3 植被运动链；[旧提示词 S1–S4](archive/2026-09-27-agent-task-prompts.md) 已交付，不要重复领取。

**当前六项均为待领取，没有后台 Agent 在执行。** 每项代码块可直接复制给负责该任务的 Agent。它们包含实际接线任务，不再把“只写一个数学模块”当作完整功能。

## 分工与共享文件

| 任务 | 当前状态 | 交付目标 | 文件重叠与顺序 |
|---|---|---|---|
| R1 / H2 增强 | 待领取 | bent normal 参与方向性天光，保留标量 AO | 与 R2、R4、R5 共享 lit / scene / deferred，整合时串行 |
| R2 / H3 | 待领取，建议优先 | 可选主世界步进体积雾与完整介质合成 | 大范围共享主链；一次由一个负责人完成 |
| R3 / B4 | 待领取 | 下界体素光的实际资源或访问改进 | compute 模块相对独立；properties 的 image 声明仍须协调 |
| R4 / T3 实体 | 待领取 | 引擎支持范围内的实体运动与时域处理 | 先查真实输入；与 R5 共享运动消费者，串行整合 |
| R5 / T3 水 | 待领取 | 水反射 / 折射分层时域处理 | 依赖 R2 的介质约定落定，避免两边同时重写 water / scene |
| R6 / T3 云 | 待领取 | 云运动、代表深度、独立历史与合成 | 云模块可独立编写；prepare / deferred / properties 整合需协调 |

R3 的独立模块可与 R2 并行开发，R6 的独立云历史模块也可先做；此处不授权无人协调地同时改共享文件。开始写共享文件前，阅读本表和其他交接记录，记录本任务实际占用。总待办由主任务汇总，各 Agent 维护自己的交接记录；不要覆盖别人的进度。

共同资源约定：colortex0–22 均已有归属，第 6 节列出新增 18–22。23–31 只是尚未登记的候选索引，使用前必须核对当时源码与其他任务记录，并把选中的格式、尺寸、生产者、消费者、清理 / 跨帧保留、关闭行为写入自己的交接记录。不要把“同样是深度 / 法线 / 云”当成可随意复用的依据。

每项开始即建立自己的 docs/handoffs/2026-09-27-R*.md，至少写明：状态、已改文件、实际调用关系、资源归属、已完成、未完成、下一处接续位置。完成一个子步骤就更新；额度中断时也能从文件继续。任务完成必须同时有生产者和消费者；尚欠接口或引擎支持时如实留未完成，不通过放松动态遮罩宣称完成。遵循当前用户的 AGENTS.md 工作流禁令，不增加用户未要求的流程。不自行提交，不撤销工作区既有修改，不自行启动其他 Agent。

## R1：bent normal 与方向性天光

~~~text
你负责 Astra 的 R1 / H2 bent normal 增强。先阅读当前用户 AGENTS.md、docs/2026-09-26-itt32-initial-implementation.md 第 6 节，以及 docs/2026-09-27-next-agent-task-prompts.md 的共同约定；立即建立 docs/handoffs/2026-09-27-R1-bent-normal.md 并持续记录剩余工作。

当前已有：prepare3 产生 colortex18 的 SH9；lit 输出 colortex19 未遮蔽环境光与顶点 AO、colortex20 几何法线；deferred 产生 colortex21 半分辨率标量 AO；deferred2 仅对环境分项应用 min(vertexAO, SSAO)。本任务完成 bent normal 的实际生产、保边重建和 SH 天光消费，不能只输出一张方向图。

先读 Astra/shaders/program/ssao.fsh、lib/ao_resolve.glsl、lib/sky_directional.glsl、lib/sky_sh9.glsl、global/lighting/diffuse.glsl、program/scene.glsl、program/lit.fsh、program/deferred.fsh。相对于几何法线计算可见半球的代表方向；写明估计量、采样权重、退化到几何法线的条件，不用未经方向加权的深度差直接充当 bent normal。法线统一为世界坐标，重建位置继续走带 TAA 抖动约定的 transforms。

重要数据边界：colortex21.BA 现在存几何法线，供保边合成使用；不能直接改成 bent normal 后让消费者继续拿它判几何边界。colortex19.RGB 含洞穴最低亮度、天光和晨昏补光，并非纯天光。必须单独保留可重新求值的天光贡献与材质响应，再以 bent normal 求 SH 天光；不能用新旧 SH 比值整体缩放 colortex19，也不能调暗直射、方块光或自发光。零阶接近零时应有有界处理。

保留标量 AO 独立工作：方向性天光关闭时仍可用 AO；AO 关闭时 H1 不受影响；TAA 不成为硬依赖。保留当前 AO 只处理主世界空气侧普通不透明地形、要求实时阴影的约定，除非本任务明确解决独立顶点 AO 输入。新方向无效、轮廓无法匹配或无可见样本时使用原几何法线。开启与关闭的实际菜单含义必须在中英文说明中写清。

允许改 AO / SH 模块和必要的 lit、diffuse、scene、deferred 接线；共享 settings、properties、lang 只修改此任务的键，不整段覆盖。新增缓冲先登记归属，不能复用 TAA、云或介质数据。保持已有来源声明，只登记实际采用的参考代码。

交付实际可调用代码、README 使用与限制、独立交接记录。记录方向分量怎样和原天光 / 标量 AO 合成、所有缓冲格式及生命周期、仍未完成的部分；没有游戏画面或帧时依据就明确写没有，不声称观感或性能收益。
~~~

## R2：主世界体积雾

~~~text
你负责 Astra 的 R2 / H3 可选主世界体积雾，完成整条渲染路径。阅读当前用户 AGENTS.md、docs/2026-09-26-itt32-initial-implementation.md 和 docs/2026-09-27-next-agent-task-prompts.md 的共同约定。开始即建立 docs/handoffs/2026-09-27-R2-overworld-volume.md，逐步记录实际剩余工作。

已有 Astra/shaders/lib/volume_integral.glsl 是纯积分模块，尚无主世界消费者。它以每格散射源、每格消光和格数步长产生 vec4(S,T)，近远段按 Snear + Tnear*Sfar、Tnear*Tfar 合成；大 sigma*L 与零长度处理已经补正，不重新复制旧版本。阅读该文件和 S2 交接，再读 program/deferred.fsh、program/scene.glsl、global/atmosphere/fog.glsl、global/post/godrays.glsl、global/water/*、program/water.glsl、global/atmosphere/clouds_screen.glsl 与云影模块。

实现低分辨率、有界距离 / 步数的世界射线积分，具备高度密度、日月方向散射、天空入射、阴影范围处理和云影。输出散射 S 与透射 T，按 scene*T+S 合成。首版手动可选，独立于 TAA；采样不能靠开启 TAA 才可解释。不包含局部烟雾体或多次散射 GI。天气、密度和各向异性参数要有有限范围，水下介质沿用专用链。

先在交接记录画清每段介质的归属，再写消费代码：colortex4 是未施加观察介质的场景，水反射 / 折射会重新沿自己的路径处理；不能把观察雾先烘进去。现有距离雾、AIR_PERSPECTIVE、deferred 的 rainy_air 和显示阶段 GODRAYS 可能覆盖同一段空气，新路径必须替代或明确拆开，不能简单叠加。既要考虑不透明地形终点，也要考虑透明层、水面、天空和云在射线上的位置；不可让地形深度代表所有透明层的终点。需要在透明材质内部查询前缀介质时，提供明确接口，不凭背景总透射率猜测。

现有 AO 开启时 root deferred 输出 colortex21，deferred2 才合成场景；关闭 AO 时原 deferred 直接处理场景。新调度必须适配两种情况，且保留 AO、原始场景拷贝、TAA 遮罩的所有写入。下界和末地使用专用阶段，不加入主世界体积效果。不要复用 colortex12 / 14 的云数据或 colortex15–22。

允许新增 global/atmosphere 下的体积模块、program 下的生产 / 合成阶段和必要薄入口，修改 scene / deferred / water 中介质消费点。settings、properties、lang、README 仅同步自己的选项和资源；新索引先登记。独立模块编写期间，不与其他 Agent 同时改共享文件。

交付必须包括实际步进、阴影 / 云影消费、S/T 保存、保边合成、透明与水界面顺序、旧雾协调、关闭路径、菜单说明。不能只交付一层全屏光束或数学模块就标记 H3 完成。记录取舍和当前证据范围；如果一部分透明介质路径仍欠缺，就明确留未完成及下一处接续位置。
~~~

## R3：下界彩光的资源与访问优化

~~~text
你负责 Astra 的 R3 / B4 下界体素彩光优化。阅读当前用户 AGENTS.md、docs/2026-09-26-itt32-initial-implementation.md、docs/2026-09-27-next-agent-task-prompts.md 的共同约定和 docs/handoffs/2026-09-27-S3-voxel-grid.md。建立 docs/handoffs/2026-09-27-R3-voxel-layout.md 并持续写进度。

现有 S3 只统一了 64³ 体素坐标、中心 / 边界及采样约定，尚无布局收益。本任务需要实际减少资源占用或冗余访问。先阅读 Astra/shaders/lib/nether_voxel_grid.glsl、program/shadow.vsh、program/shadow.fsh、program/nether_light.csh、global/dimension/nether_colored_light.glsl、global/dimension/nether_volume.glsl、world-1 中相关 compute 入口、shaders.properties 的自定义 image 声明。

把 R32UI 原子捕获和两个 RGBA16F 体积的生产者、消费者、各阶段读写方向、alpha 语义、九阶段邻域传播距离记清。选择一种有明确依据的格式或访问改进并真正接入。颜色动态范围、发光编码、遮挡与空体素的区别要保留；压缩必须说明精度损失或范围变化。不因 RGB 看似三通道就假定 alpha 空闲，也不把不支持 imageStore / 原子操作的格式直接套上去。

工作组之间没有可依赖的全局同步，不能把九个传播阶段塞进一次 dispatch 后调用 barrier() 冒充同等结果。若减少传播轮数导致影响半径或收敛行为变化，应作为明确的画质取舍并保留用户可理解的选项，不能声称等价优化。保持捕获与显示对 cameraPosition、网格中心、边缘淡出和采样偏移的同一约定。

允许修改体素网格、捕获 / 传播 / 彩光读取文件及相关 image 键；不改主世界 lit、AO、TAA、云链。不重排整个 properties 文件。新增选项或格式改变同步 README、中英文说明和来源记录。优先完成有明确字节数或读写次数变化的改进；没有帧时依据时只报告可由源码推得的变化，不能填写猜测的 FPS 提升。

交付实际优化、资源归属与开销推导、精度 / 半径取舍、关闭行为和交接文档。若候选方案都不满足当前 API 或数据范围，把阻碍和下一处接续位置写清，不能将已完成的 S3 坐标整理再次算作 B4 完成。
~~~

## R4：实体运动与 TAA

~~~text
你负责 Astra 的 R4 / T3 实体运动。先阅读当前用户 AGENTS.md、docs/2026-09-26-itt32-initial-implementation.md 第 1、6 节及 docs/2026-09-27-next-agent-task-prompts.md 共同约定。建立 docs/handoffs/2026-09-27-R4-entity-motion.md，开始就列出已知输入和缺口。

当前 TAA 已有相机重投影及植被前帧形变。colortex22 是 RG 历史 UV 位移、B 前帧预期对数深度、A 有效性；历史位于未抖动的输出网格。实体、方块实体和手持物仍 reactive=1。阅读 Astra/shaders/lib/uniforms.glsl、lib/taa_state.glsl、program/lit.vsh/fsh、program/taa_resolve.fsh、program/taa_state.fsh、实体 / 方块实体 / 手持物薄入口和当前工作区可用的 Iris 接口源码。

首先确认目标 MC 26.2 / Iris 1.11.2 是否提供每实例前帧变换、顶点位置或运动属性，记录真实接口证据。entityId 是材质 / 类型映射，不能当全局唯一实例 ID；相机 previousModelView 也不是实体前帧模型矩阵。不得编造 uniform、用同类型实体共享一份位置，或只以当前世界位置和相机差冒充物体速度。若纯光影包取不到所需输入，应明确该项的引擎阻碍和需要的确切数据；不要擅自扩成 Java 模组项目。

若输入足够，实现当前顶点对应的前帧位置、与现有历史一致的投影、预期深度和有效性。处理生成 / 消失 / 传送 / 动画断续，说明刚体变换覆盖不了的骨骼或顶点形变范围。只有运动数据真实有效的实例才能解除动态隔离，其余保持当前处理。透明实体和手持物单独划定范围，不自动复用不透明实体方案。

尽量扩展 colortex22 已有运动接口，保持植被路径和 metadata 版本语义；需要区分类型 / 来源时先定义数据布局再接线，不能覆盖字段后让旧消费者误读。保留深度拒绝、状态变化、颜色约束、透明层独立混合和视口变化处理。

允许修改实体薄入口、lit、uniforms 中真实支持的声明、运动模块和 taa_resolve；共享文件串行整合。不改水、云或 AO 效果。交付代码及交接记录；若引擎不支持，就把 R4 留为“受输入限制，未实现”，列出可执行的后续接口需求，不以减小 reactive 权重替代运动实现。
~~~

## R5：水反射与折射的时域处理

~~~text
你负责 Astra 的 R5 / T3 水时域处理。阅读当前用户 AGENTS.md、docs/2026-09-26-itt32-initial-implementation.md、docs/2026-09-27-next-agent-task-prompts.md 共同约定，以及 R2 已存在的介质交接。建立 docs/handoffs/2026-09-27-R5-water-temporal.md，持续记录进度。若 R2 正在改 water / scene，先完成自己的独立模块，共享接线等待明确写入顺序。

阅读 Astra/shaders/program/water.glsl、global/water/surface.glsl、raytrace.glsl、refraction.glsl、optics.glsl、absorption.glsl、program/lit.vsh/fsh、program/scene.glsl、lib/taa_reactive.glsl、program/taa_resolve.fsh。当前水面 reactive=1，水下全局不积累；colortex4 是未施加观察介质的背景。水波主要表现为时变法线，不能把纹理相位速度或法线变化直接当作真实几何顶点速度。

先明确要累积的信号：水面着色、SSR 命中辐射、环境反射、折射背景具有不同运动与遮挡含义。优先在各自分项上保存历史及所需命中位置 / 深度 / 法线 / 有效性，完成生产与消费；不能只在最终混合色上套不透明地形速度。SSR 失去命中、离开屏幕、命中物体变化、折射深度跳变、透明覆盖与水界面切换都要明确拒绝旧贡献。

复用 TAA 当前与历史网格的坐标约定，记录每个 UV 是否含当前抖动，明确波形参数如何获得真实前帧值。水吸收和相机介质分别只应用一次；不要把 colortex4 改成已经叠加观察雾的颜色。TAA 关闭时水原有显示仍完整；没有有效运动证据的分量继续当前帧，不把 reactive 直接统一改小。冰与玻璃不能因共用函数而意外获得水的历史身份。

允许新增水专用时域模块及资源、调整 water / lit / scene / 必要 composite 接线。不得挪用 0–22 已有缓冲；新增资源记录格式、读写顺序、历史保留与失效条件。共享 settings / properties / lang 只修改本任务范围。保留现有水来源声明，新增部分说明来源。

交付至少一种完整水分项历史链及其与现有水面合成的关系，明确剩余未覆盖的反射、折射或水下分量。README 和交接如实描述覆盖范围，R5 不能在只完成一个分项时标成全部完成。没有画面或帧时数据不作观感和性能保证。
~~~

## R6：云层独立历史

~~~text
你负责 Astra 的 R6 / T3 云时域处理。阅读当前用户 AGENTS.md、docs/2026-09-26-itt32-initial-implementation.md、docs/2026-09-27-next-agent-task-prompts.md 共同约定。建立 docs/handoffs/2026-09-27-R6-cloud-temporal.md，持续写出剩余工作和接续入口。

当前 colortex12 是半分辨率屏幕云的预乘散射颜色与覆盖率；11 是经纬天空反射环境图；14 是世界平面云影。三者坐标、深度与生产时序不同，不能直接共享同一历史。先读 Astra/shaders/program/cloud_screen.fsh、global/atmosphere/clouds_screen.glsl、clouds_planar.glsl、cloud_shadow_cache.glsl、program/deferred.fsh、program/sky.fsh、program/taa_resolve.fsh、prepare/prepare1/prepare2 薄入口及 properties。

本任务完成屏幕可见云自己的历史，不扩大为反射图和云影同时累积。云积分时产生可用于重投影的代表世界位置 / 深度，例如透射权重下的一阶矩，并清楚定义空云、厚云和多段云的退化规则。根据实际密度场的平移 / 形变与真实前帧参数重投影；云不能沿地形深度或只按相机旋转复用历史。需要明确哪些运动可逆、哪些非刚性变化只能拒绝或降低权重。

历史至少保存预乘云色和覆盖 / 透射语义，配套代表深度 / 有效性；颜色与 alpha 使用相同有效样本，避免云边黑边和残影。处理相机穿云、云层内地形、屏幕外进入、天气覆盖突变、维度 / 视口 / 时间中断。保留原云层内局部步进路径，不能用无限远云历史覆盖近处地形。

新历史应有独立读写顺序，不能读写同一纹理并假定可见性。记录它相对 prepare1、天空和 deferred 的消费顺序。场景 TAA 不再错误重复积累同一云信号；若继续保守屏蔽云区域，要说明云稳定性来自独立云历史。没有有效代表位置时使用当前云结果，不能仅把场景 reactive 调小。若云历史选项依赖 TAA，菜单应明确；否则在 TAA 关闭时也应正确维护自己的状态。

允许修改屏幕云生产 / 采样模块、新增云历史和薄入口、必要的 sky / deferred 连接。不要改 colortex11 / 14 的现有用途，不覆盖其他任务的新资源。共享 properties、settings、lang 按本任务键整合，保留云密度与散射来源声明。

交付完整屏幕云历史链、菜单 / 默认行为、资源占用推导及独立交接文档。明确球面反射云与世界云影尚未获得专用历史；不能据屏幕云完成宣称所有云数据均已时域处理。
~~~
