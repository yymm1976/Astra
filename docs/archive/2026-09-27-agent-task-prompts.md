# 可分发给其他 Agent 的任务与完整提示词

更新：2026-09-27。S1–S4 已由其他 Agent 交付，主任务已完成源码复核并补正 S2/S4；下面的提示词保留为原任务范围说明，不需要再次分发。当前状态和下一步开发顺序见 [持续待办第 5 节](../2026-09-26-itt32-initial-implementation.md#5-s1s4-复核结果与下一步开发建议2026-09-27)。

剩余的 H1/H2/H3/B4 整项都涉及渲染架构，不按简单任务分发。下面拆出四个范围较小的代码子任务；S1/S2 偏独立数学模块，S3/S4 偏现有代码整理。它们交付后仍有主任务接线工作，不能把父任务直接标为完成。

## 分配表与文件所有权

| 任务 | 对应父项 | 相对难度 | 当前状态 | 独占修改范围 | 完成后仍由主任务处理 |
|---|---|---|---|---|---|
| S1：SH9 数学模块 | H1 方向性天光 | 中等，范围独立 | 已完成（模块代码完成，H1 待接入） | 新增 `lib/sky_sh9.glsl`；S1 交接记录 | 天空采样、系数生产与存储、几何光照消费 |
| S2：体积散射积分模块 | H3 主世界体积雾 | 较小 | 模块完成，数值边界已补正；H3 待接入 | 新增 `lib/volume_integral.glsl`；S2 交接记录 | 射线步进、阴影 / 云影、缓冲与介质顺序 |
| S3：彩光坐标约定集中 | B4 彩光布局 | 较小 | 已完成（代码完成且已接线；B4 布局优化未完成） | 新增 `lib/nether_voxel_grid.glsl`；`program/shadow.vsh`、`program/nether_light.csh`、`global/dimension/nether_colored_light.glsl`；S3 交接记录 | 格式压缩、存储布局与传播调度优化 |
| S4：植被显式时间接口 | T3 动态累积增强 | 中等，范围独立 | 代码完成，强度语义已补正；历史链待接入 | `global/lighting/wind.glsl`；S4 交接记录 | 前帧参数保存、运动数据、TAA 历史策略 |

表内着色器路径都相对于 `Astra/shaders/`。S1–S4 的修改文件互不重叠，可同时分发；一个任务只交给一个 Agent。更轻的任务优先分配 S2、S3。S1/S2 完成的是可接入模块，S3/S4 则应真正接回现有调用。

主任务保留：H1/H2/H3 的阶段接入、AO 环境光拆分、B4 格式与传播改变、TAA 运动历史。`settings.glsl`、`uniforms.glsl`、`shaders.properties`、`program/lit.*`、`deferred.fsh`、`display.fsh`、`taa_*`、维度入口、语言文件、README、THIRD-PARTY 和总待办均由主任务统一修改。S3 对 `program/shadow.vsh` 的授权是明确例外，主任务在 S3 交付前不要同时编辑该文件的体素坐标部分。

## 共同约束（每份提示词均要求先读）

1. 工作区：`C:\Users\杨铭\Desktop\MC模组开发\Astra光影开发`。源代码以当前文件为准；已有未提交改动要保留。历史调研中的“无 TAA”等判断已经过时。
2. 用户工作流禁令原意必须保留：除非用户在当前请求明确要求，不得主动提出、执行、要求、报告哈希、基线、冒烟、测试、备份、回滚，或换名添加等价流程。不要为了通用流程增加步骤、产物或汇报。
3. 直接完成分配范围内的代码，不停留在方案。不要自行再分派任务，不提交或发布，不修改其他 Agent 的文件，不整文件覆盖刚被别人修改的内容。
4. 只写本任务允许的文件。需要跨越范围时，把具体文件、需要的接口和原因写入本任务交接记录；继续完成不依赖它的部分，不自行改共享调度或分配新缓冲。
5. GLSL 以当前工程约定为准。新模块使用 include guard；数学模块不依赖 sampler、image、帧状态或私有 uniform。既有源文件的来源声明保留。新增数学实现自行编写，不从许可不明的参考包复制表达式或注释。
6. 不提前添加尚未接入的用户设置，不修改默认画质参数。父项“完成”必须包含接线；仅有库函数时明确写“模块代码完成，待主任务接入”。
7. 各 Agent 只维护自己的交接记录，避免争写总待办。交接记录保持简短，包含：当前状态、实际改动路径、可供调用的接口、关键数值 / 坐标约定、剩余工作。开始工作时写清当前接续点；中断前留下具体未完成项。不要附带无关流程产物。
8. 返回用户时说明真正完成的代码、尚未完成的接入和实际限制；没有游戏画面或帧时依据就不要声称效果、速度已改善。

## S1 完整提示词：H1 的 SH9 数学模块

复制下面整段给一个 Agent：

```text
请在工作区 C:\Users\杨铭\Desktop\MC模组开发\Astra光影开发 实施 S1：为 Astra 的 H1 方向性天光编写独立 SH9 数学模块。直接写代码，完成后写明剩余接入，不只给建议。

先读：
- docs/2026-09-27-agent-task-prompts.md 的“共同约束”与 S1。
- docs/2026-09-26-itt32-initial-implementation.md 的 H1、H2 说明。
- Astra/shaders/global/lighting/diffuse.glsl 中的环境项，以及天空辐射函数的现有输入约定。

允许修改：
- 新增 Astra/shaders/lib/sky_sh9.glsl。
- 新增或更新 docs/handoffs/2026-09-27-S1-sh9.md。
其他文件只读，不接渲染阶段、不分配 colortex、不修改现有环境光。

目标与接口：
1. 实现世界坐标下的九项实球谐基函数，明确索引顺序、轴方向、归一化和输入方向约定。使用同一约定完成投影与求值，不把九个任意方向样本当成九个系数。
2. 建议接口：
   void astra_sh9_clear(out vec3 coefficients[9]);
   void astra_sh9_accumulate(inout vec3 coefficients[9], vec3 unitDirection, vec3 radiance, float solidAngle);
   vec3 astra_sh9_irradiance(vec3 coefficients[9], vec3 unitNormal);
   vec3 astra_sh9_diffuse_radiance(vec3 coefficients[9], vec3 unitNormal);
   如果 GLSL 风格需要调整签名，在交接记录给出最终声明；保持这些语义。
3. coefficients 保存辐射亮度在球面上的积分系数。accumulate 的 solidAngle 是外部提供的立体角权重；模块不猜测样本数，不再暗中除以采样次数。
4. irradiance 做余弦核卷积；diffuse_radiance 对应单位反照率朗伯表面的出射量，即辐照度除以 π。两者分开命名，避免接入时多乘或少乘一次 π。
5. 系数允许为负，不能逐项截为非负。若处理低阶重建的负值，只在最终物理输出处处理并说明限制。
6. 以推导说明约定：常量环境 L 对任意单位法线得到辐照度 πL；单位反照率的漫反射输出为 L；零环境输出为零。权重覆盖整个球面时总立体角应为 4π。将这些写在必要注释或交接记录中，不增加运行工具。
7. 不把日月圆盘、采样布局、下半球辐射或天气艺术参数塞进数学模块。这些输入由 H1 生产阶段决定。

交付：
- 有完整实现、include guard、单位和坐标约定的模块。
- 交接记录写明最终接口、系数排列和归一化、预期输入范围，以及主任务还需完成的采样 / 存储 / 调用。
- 状态写“模块代码完成，H1 待接入”，不要把 H1 标为完成，也不要修改公共待办表。
```

## S2 完整提示词：H3 的散射与透射积分模块

复制下面整段给另一个 Agent：

```text
请在工作区 C:\Users\杨铭\Desktop\MC模组开发\Astra光影开发 实施 S2：为主世界体积雾编写独立的分段单次散射积分模块。直接写代码；这次不接整套雾效果。

先读：
- docs/2026-09-27-agent-task-prompts.md 的“共同约束”与 S2。
- docs/2026-09-26-itt32-initial-implementation.md 的 H3。
- Astra/shaders/global/atmosphere/fog.glsl、global/dimension/nether_volume.glsl 和 program/scene.glsl 的现有雾合成方式，只读。

允许修改：
- 新增 Astra/shaders/lib/volume_integral.glsl。
- 新增或更新 docs/handoffs/2026-09-27-S2-volume-integral.md。
不要改现有雾函数、设置、阶段入口或下界效果，不引入新缓冲。

目标与接口：
1. 用 vec4 表示一段介质：rgb 是积分后的散射 S，a 是透射 T。空段为 S=0、T=1，不使用“alpha 是不透明度”的约定。
2. 建议提供：
   vec4 astra_volume_identity();
   vec4 astra_volume_segment(vec3 sourcePerLength, float extinctionPerLength, float distanceBlocks);
   vec4 astra_volume_compose(vec4 nearSegment, vec4 farSegment);
   vec3 astra_volume_apply(vec3 background, vec4 volume);
3. extinctionPerLength 单位为每格，distanceBlocks 单位为格；sourcePerLength 是每单位长度的散射源项，调用方已经乘入散射系数和入射光。模块不能再次把它当成天空颜色乘密度。
4. 均匀段按 Beer–Lambert 消光与解析源项积分计算；sigma 接近零时采用正确极限，而不是用 max(sigma,epsilon) 改变零消光但源项非零的语义。小光学厚度时避免 1-exp(-tau) 的消减损失。
5. 零长度为恒等段；输入的负长度、负消光采取明确且温和的处理，注明契约。大光学厚度保持有限输出，透射在 [0,1]。
6. 前后组合顺序固定：S = S_near + T_near*S_far，T = T_near*T_far。最终合成为 background*T+S。不能反过来衰减前段散射。
7. 不实现噪声、密度场、阴影、云影、深度重建或相位函数；不要把此任务扩大成整套步进体积雾。主任务会给分段积分传入已计算的源项。
8. 在注释或交接中说明零长度、零源项、零消光和极大光学厚度的解析行为，以及前后段的顺序；不增加运行工具。

交付：
- 不依赖 uniform / texture 的完整数学模块。
- 交接记录列最终签名、单位、稳定性处理和源项约定。
- 明确“模块代码完成，H3 的步进、缓冲、透明层和旧雾整合尚未完成”，不要改公共待办表。
```

## S3 完整提示词：彩光体素坐标集中

复制下面整段给另一个 Agent：

```text
请在工作区 C:\Users\杨铭\Desktop\MC模组开发\Astra光影开发 实施 S3：把下界彩光的体积范围与坐标约定集中到一个共享模块，并实际接回现有捕获、传播和采样。此任务是 B4 的前置整理，不是格式压缩。

先读：
- docs/2026-09-27-agent-task-prompts.md 的“共同约束”与 S3。
- Astra/shaders/program/shadow.vsh 的 astra_voxel_write。
- Astra/shaders/program/nether_light.csh。
- Astra/shaders/global/dimension/nether_colored_light.glsl。
- shaders.properties 中 astraVoxelImage、astraLightA/B 的定义，以及 world-1 下实际存在的 compute 入口，只读。

允许修改：
- 新增 Astra/shaders/lib/nether_voxel_grid.glsl。
- Astra/shaders/program/shadow.vsh，仅体素坐标计算与相关 include。
- Astra/shaders/program/nether_light.csh，仅范围约定与相关 include。
- Astra/shaders/global/dimension/nether_colored_light.glsl，仅体积坐标、边界与归一化约定。
- docs/handoffs/2026-09-27-S3-voxel-grid.md。
不要编辑 wind.glsl，它由 S4 负责。不要编辑 shaders.properties 或 compute 入口。

实施要求：
1. 集中当前固定 64³ 尺寸、32 格中心偏移和归一化比例；给出明确的 ASTRA_NETHER_VOXEL_* 名称及必要坐标函数。
2. 保持捕获和消费共用“camera-relative position + fract(cameraPosition) + half extent”的约定。函数尽量通过参数接收相机小数部分，不新建 uniform。
3. 捕获点仍用 floor 得到整格，传播仍用整数 texelFetch；显示采样继续采用 p/64 的归一化线性采样及现有法线偏移 / 边缘衰减。
4. 特别注意 shadow.vsh 中 at_midBlock/64.0 的 64 是属性单位换算，不是体积尺寸。不能机械地把所有 64 替换为体积常量；法线偏移 0.65、边缘阈值和编码位也不属于尺寸常量。
5. 不改变 R32UI / RGBA16F、原子写入、发光种类、solid 编码、清零方式、光强、0.72 衰减或 A/B 奇偶读写。
6. 保持现有步数与调度。Iris 读取的 workGroups 字面声明、local_size 和 properties 的 image 尺寸保持原样；在交接记录中明确这些是外部接口字面量，仍需与固定尺寸一致。不要假装只改一个常量就支持任意尺寸。
7. 新模块不带 image 声明；shadow.vsh 中的引入和调用遵守原下界 / 彩光 / 阴影条件，避免影响主世界、末地和关闭彩光的路径。
8. 保留来源说明，只做约定集中，不声称这一整理本身降低了显存或提高了帧率。

交付：
- 共享模块已经被上述三个实际消费者使用，不是只增加一个无人调用的文件。
- 在交接记录说明替换的坐标表达式、刻意保留的不同单位常数、外部尺寸声明，以及 B4 尚未处理的格式 / 存储 / 调度问题。
- 状态写“S3 代码完成；B4 布局优化未完成”，不要改公共待办表。
```

## S4 完整提示词：植被可按显式时间求形变

复制下面整段给另一个 Agent：

```text
请在工作区 C:\Users\杨铭\Desktop\MC模组开发\Astra光影开发 实施 S4：为现有植被形变增加显式时间、天气和强度输入，使后续 TAA 能在已知历史参数时求同一顶点的前帧位置。本次只改形变模块，不改 TAA。

先读：
- docs/2026-09-27-agent-task-prompts.md 的“共同约束”与 S4。
- Astra/shaders/global/lighting/wind.glsl 全文，尤其现有来源声明及 wind_wave_shape / wind_wave / wave_foliage。
- Astra/shaders/program/lit.vsh、program/shadow.vsh 的 wave_foliage 调用，只读。
- 持续待办中 T3 的当前帧保守策略。

允许修改：
- Astra/shaders/global/lighting/wind.glsl。
- docs/handoffs/2026-09-27-S4-foliage-time.md。
不要修改 program/shadow.vsh，它的体素坐标部分由 S3 负责；也不要改 lit.vsh、uniforms、历史缓冲或 TAA 遮罩。

实施要求：
1. 新增返回位移的显式求值接口，例如：
   vec3 astra_foliage_displacement(vec3 undeformedWorldPosition, float timeSeconds,
       float rainAmount, float strengthScale, bool isLeaves, bool isGroundFoliage, bool topOfFoliage);
2. 接口接收未形变的绝对世界位置；返回世界轴向的位移，不改写输入位置。timeSeconds 是秒；strengthScale=1 对应当前 100% 强度；rainAmount 沿用当前 rainStrength 的语义。
3. 新接口及其内部显式求值函数不能暗中读取 frameTimeCounter、cameraPosition 或 rainStrength。需要的量全部由参数传入，避免调用方要求前帧却仍用当前帧条件。
4. 保留原 wave_foliage 签名，用当前 cameraPosition、frameTimeCounter、rainStrength 和已有强度选项调用新接口，再把位移加到 playerPos。保持主视图与阴影现有调用无需改动。
5. 保留风形状、170.0 时间缩放、叶片空间缩放与轴向比例、草的根部锚定、雨量幅度和当前强度系数；不要顺手改艺术参数或做新材质分类。发现原有 wind_wave 还有调用时保留其兼容接口，避免删除正在使用的入口。
6. 非植被、被锚定的草根顶点和零强度应有原有的零位移语义。叶片与草地的判定优先级延续现有行为。
7. 不新增前帧 uniform，不用“当前时间减一个固定帧长”假冒历史时间；也不要取消 TAA 的植被 reactive 标记。主任务拿到真实前帧状态并接好运动链后再启用累积。
8. 原有风形变来自既有参考实现，必须保留其来源和许可说明；这次只是 Astra 接口拆分，不把整个模块重标为原创。

交付：
- 新显式接口有实际实现，现有 wave_foliage 已转用它；当前帧的主视图与阴影继续共用同一算法。
- 交接记录列出最终接口、输入单位、包装函数怎样传参，以及主任务必须补齐的未形变位置、前帧时间 / 雨量等数据。
- 状态写“S4 代码完成；植被历史形变接线与 TAA 动态累积仍未完成”，不要改公共待办表。
```

## 主任务接收后的接续顺序

1. 根据各自交接记录更新总待办的子项状态；缺少实际文件或仍有函数空壳时保留未完成。
2. H1 消费 S1，再完成天空生产、环境项接入和设置。H2 仍由主任务处理环境光分项与 AO。
3. H3 消费 S2，完成当前场景的步进、散射 / 透射缓冲及透明顺序。
4. B4 在 S3 集中约定之后继续处理真正的布局 / 格式问题，不因去掉重复常量就标为完成。
5. T3 增强在 S4 之后补充真实前帧参数与运动数据，再调整植被历史权重。实体、水和云仍需各自方案。

共用文件的 UI、预设、中文 / 英文说明、来源台账和总 README 由主任务在功能接入时统一更新。S1–S4 的交接记录仅负责保留各 Agent 的进度与未完成内容，不替代总待办。
