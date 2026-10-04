# R4 / T3 实体运动 —— 交接记录

- 状态：调查完成，三档结论 = **完全不支持**；R4 留为「受输入限制，未实现」；shader 源码零改动
- 认领：ZCode 会话，2026-09-27
- 对应父项：T3 动态累积增强之 R4（实体 / 方块实体 / 手持物运动）；背景 [itt32-initial-implementation](../2026-09-26-itt32-initial-implementation.md) 第 1、6 节
- 实际改动：仅本记录（新建）；无任何 shader / properties / lang / README 改动
- 基线：开工 `python qa/tools/check_pack.py` → `17 checks: 3 FAIL, 0 WARN, 14 PASS`（#4 / #11 / #15，均为既有，与本任务无关）；交付前复跑结果见文末

## 已知输入与缺口（调查前置清单）

引擎确实提供的（与实体相关）：

| 输入 | 语义 | 为什么不够 |
|---|---|---|
| `gbufferPreviousModelView` / `gbufferPreviousProjection` | 官方定义「The value of gbufferModelView in the previous frame.」 | 相机级矩阵，不含实体自身变换；相机 previousModelView 不是实体前帧模型矩阵 |
| `cameraPosition` / `previousCameraPosition`（含 Fract/Int） | 相机位移 | 只能做相机级重投影，等价于「实体不动」假设 |
| `entityId` / `blockEntityId` / `currentRenderedItemId` / `vehicleId` | entity.properties / block.properties 的**类型**映射；不在映射表时为 65535 | 材质 / 类型 ID：同类实体共用同一值，不能当全局唯一实例 ID |
| 顶点属性 `gl_Vertex` `gl_Color` `gl_Normal` `gl_MultiTexCoord0/1` `vaUV1` `mc_Entity` `mc_midTexCoord` `at_tangent` `at_midBlock` `mc_chunkFade` | 每顶点当前帧数据 | 无前帧位置、无速度、无实例身份 |
| `gl_ModelViewMatrix`（gbuffers 内） | 含实体 / 方块实体 / 手持实例偏移的**当前帧**矩阵 | 引擎不暴露它的前帧值 |
| `entityColor`、`renderStage`、fog 组等 rendering uniform | 受伤闪红 / 渲染阶段 | 与运动无关 |
| shaders.properties 自定义 uniform（`uniform.*` / `variable.*`） | 每帧每 pass 求值一次的帧级值 | 无法 per-draw-call / per-instance 求值 |
| SSBO（Iris only） | 包自写数据 | 引擎不注入实体数据，仍无源头 |

缺口（实现运动链必需而引擎不给）：

1. 每实例前帧模型矩阵，或每顶点前帧位置，或每顶点速度——三者皆无。
2. 跨帧实例身份或「前帧变换有效」标志（区分生成 / 消失 / 传送 / 动画断续）——无。
3. 手持物前帧模型视图（vanilla 手部摆动 / 挥动动画每帧改变其模型矩阵）——无。

## 接口证据

### 结论：完全不支持（per-instance 运动输入缺席）

### A. Iris 官方文档（current 版，覆盖 ≥1.10.5；对应本工作区 Iris 1.11.2）

1. **属性总表** <https://shaders.properties/current/reference/attributes/overview/>
   完整列表（侧栏 + 正文）：at_midBlock、at_tangent、ftransform、gl_Color、gl_Normal、gl_Vertex、mc_chunkFade (Iris Only)、mc_Entity、mc_midTexCoord、gl_MultiTexCoord0、gl_MultiTexCoord1、vaUV1 (1.17+)。正文引文：「Attributes are per-vertex data available only in the vertex stage.」——**没有 `at_velocity`，没有任何前帧位置 / 运动属性**。
2. **矩阵总表** <https://shaders.properties/current/reference/uniforms/matrices/>
   列表含 `gbufferPreviousModelView` / `gbufferPreviousProjection`，引文：「The value of gbufferModelView in the previous frame.」——**只有相机级前帧矩阵，没有 per-entity previous model matrix**。
3. **ID 组** <https://shaders.properties/current/reference/uniforms/id/>
   entityId 引文：「This uniform stores the ID (from entity.properties) of the current entity. Value is 0 if no entity.properties is present. Value 65535 if entity.properties is present and the entity is not in the file.」——类型映射而非实例身份；blockEntityId / vehicleId (1.10.4+) / currentRenderedItemId 同理。
4. **Camera / Player 组** <https://shaders.properties/current/reference/uniforms/camera/>
   索引内 previous 相关仅 `previousCameraPosition(Fract/Int)`——相机位移。
5. **Rendering 组** <https://shaders.properties/current/reference/uniforms/rendering/>
   索引：alphatestref、atlassize、blendfunc、chunkoffset、entitycolor、far、fogcolor、fogdensity、fogend、fogmode、fogshape、fogstart、near、renderstage、skycolor、texturefilteringmode——无运动项。

搜索过的位置与关键词：`/current/reference/attributes/`、`/current/reference/uniforms/{overview,camera,id,matrices,rendering,status,system,world,biome}/`、GitHub releases.atom（内容止于 1.7.3，参考价值有限）；关键词 `at_velocity`、`velocity`、`previous`、`instance`、`instanceId`、`midpoint`、`per-entity`、`motion`、`entity transform`。未找到任何 per-instance 运动接口。

### B. 工作区参考包（佐证：没有任何活跃包在 Iris 上拿到过实体运动数据）

- Bliss `_analysis/refs-2026-09-24/bliss-shader/shaders/dimensions/all_solid.vsh:83-84`：`// in vec3 at_velocity;` / `// out vec3 velocity;`——**整段被注释**，是被放弃的实验，不是可用接口。
- Pixel Perfect `_analysis/refs-2026-09-27/pixel-perfect-shaders/source/shaders/program/base_gbuffers/base.vsh:28` 声明 `in vec3 at_velocity;`，`:498-503` 的使用分支为 `#if defined gc_entities && !defined IS_IRIS` → **在 Iris 上是死代码**，Iris 路径走 `PREV_CLIP`（相机级重投影，`:510-512`）。且该属性不在官方属性总表中：未绑定属性读回常量 0，不能当作真实运动数据来源。
- Complementary r5.9 Reimagined `_analysis/Complementary r5.9/Reimagined/shaders/lib/misc/reprojection.glsl:9-29`：仅 `gbufferPreviousModelView/Projection + cameraOffset` 的相机级重投影。
- Mellow v3.4 / Refrax v1.3.1 / Solas V2.2b / Steadfast 0.8.0：grep `at_velocity|previousModel` 零命中。
- Iris 源码转储（字节码）：`_analysis/astra-sc34/CommonTransformer.txt:99,172,224` 只注册 `at_midBlock`；`SodiumTransformer.txt:431-570` 只转写 `mc_Entity`；两目录 grep `previous` 仅命中 `MatrixUniforms.txt:62-92` 的 `MatrixUniforms$Previous`（相机级注册）；`velocity|midpoint|instanceId` 零命中。`VanillaTransformer.txt:24,34` 的 `EntityPatcher.patchEntityId` 与 `IrisRenderingPipeline.txt:949-950` 的 `IdMap.getEntityIdMap` 证实 entityId 只是 entity.properties 映射。
- [itt32-initial-implementation](../2026-09-26-itt32-initial-implementation.md):102,162 既有判断「尚无实体运动矢量」「R4 先厘清引擎能够提供的实体运动数据」与本文结论一致。

### C. 被排除的替代路径（契约禁止或物理错误，列出以防后续重提）

- 同类型实体共享一份位置（entityId 推速度）：同类实体各自速度不同，且契约明令禁止。
- 当前世界位置 ± 相机差冒充物体速度：即相机级重投影，`taa_resolve.fsh:65-69` 对所有像素已完成；对自主移动 / 顶点动画的实例是「假设它不动」。
- 减小 reactive 权重替代运动实现：契约明令禁止；实体的收益本来就是时域降噪，降权只保留噪点。
- 用未绑定属性（如声明 `at_velocity` 读常量 0）：静默走「无运动」分支，是编造接口的另一种形式。

## 状态（三档之一）

**完全不支持** → 依契约走「代码零改动」分支：

- R4 实体 / 方块实体 / 手持物运动链不实现；三者在 `program/lit.fsh:422` 保持默认 `reactive = 1.0`（当前帧重建、历史写入 -1 深度），这是契约要求的现状，不是可让步项。
- colortex22 既有字段（RG 位移 / B 前帧预期对数深度 / A 有效性）、taa_state metadata 版本 2 语义、植被路径、深度拒绝、状态变化、颜色约束、透明层独立混合、视口变化处理——全部未触碰。

## 已改文件

- `docs/handoffs/2026-09-27-R4-entity-motion.md`（新建，本记录）。
- shader / properties / lang / README：零改动（完全不支持分支的契约要求；不存在「必要微调」项——维持 reactive=1 即正确现状）。

## 实际调用关系（现状核实，供下一棒接续）

薄入口（`Astra/shaders/`，全部 `#include "/program/lit.vsh|fsh"`）：

| 入口 | defines | TAA 现状 |
|---|---|---|
| gbuffers_entities / gbuffers_entities_translucent | `ASTRA_ENTITY`（后者加 `ASTRA_TRANSLUCENT`） | reactive=1（lit.fsh:422 默认） |
| gbuffers_block / gbuffers_block_translucent | `ASTRA_BLOCK`（后者加 `ASTRA_TRANSLUCENT`） | 同上 |
| gbuffers_hand / gbuffers_hand_water | `ASTRA_HAND`（后者加 `ASTRA_TRANSLUCENT`） | 同上；不透明手在 colortex3.a 高位打手标记（lit.fsh:487-489），deferred 单独重投影 |
| gbuffers_textured / gbuffers_textured_lit / gbuffers_spidereyes / gbuffers_armor_glint / gbuffers_basic / gbuffers_beaconbeam | 无实体 define（beaconbeam 加 `ASTRA_BEAM`+`ASTRA_TRANSLUCENT`） | reactive=1 |

数据链（运动数据真实存在时才走通，目前只有植被）：

1. `program/lit.vsh:10-16` TAA varying 契约：`taaPreviousClip` / `taaPreviousViewDepth` / `taaFoliageValid`；`:142-164` 仅在 `ASTRA_TERRAIN && !ASTRA_TRANSLUCENT` 且植被材质（2/4/5/6）且 `astra_taa_state_valid(colortex17)` 时填充（:148-162 前帧形变 + `gbufferPreviousModelView/Projection`）。
2. `program/lit.fsh:419-450`：`reactive` 默认 1.0；地形不透明非手持可按材质 / 植被 motionValid 降为 0（:423-429）；colortex22 写出（`gl_FragData[3]`，RENDERTARGETS 0,3,16,22 的槽 3 / SSAO 版 0,3,16,22,19,20 同槽）仅在 `motionValid`（:439-448）。
3. `program/taa_resolve.fsh:71-75` 消费 colortex22（`a>0.5` 时以 `texcoord+位移` 取历史、B 通道当预期深度）；:30-50 逐贡献者历史验证；:78 深度容差；:81-96 邻域约束（reactive 3×3 膨胀 :89）；:98-112 状态校验、越界拒绝、颜色约束、运动感知权重；:113-116 reactive 像素历史写 -1 深度持久化。
4. `program/taa_state.fsh:13-19` metadata 版本 2（像素 2 = 维度标记、前帧雨量、前帧摇曳强度、`2.0`）；`lib/taa_state.glsl:13-35` 校验（帧连续、视口、介质、维度、相机位移 ≤8、blindness/darkness/闪电、投影一致性）。

## 后续接口需求（引擎侧，可执行清单）

按覆盖能力排序；未提供前 R4 保持「受输入限制，未实现」：

1. **首选：每顶点前帧位置或速度**（唯一能覆盖骨骼 / 顶点动画的形态）：`in vec3 at_prevPosition`（玩家相对空间、未抖动、含 partialTick 插值与相机位移语义说明）或 `in vec3 at_velocity`（每帧视图空间位移）。生成 / 传送 / 断续帧由引擎置零或置无效标志。
2. **次选：每实例前帧模型矩阵 + 实例身份**：`uniform mat4 <previousInstanceModelView>` 与跨帧稳定的 `uniform int <instanceId>`。只能覆盖刚体根变换（见下节限制），配合实例身份可拒绝生成 / 消失 / 传送。
3. **手持物**：`<previousHandModelView>`（含摆动 / 挥动 / 装备切换动画）；手持物模型矩阵每帧变化，相机级矩阵覆盖不了。
4. **有效性标志**：每实例或每顶点「前帧变换有效」（0 = 本帧新生 / 传送 / 动画断续），或实例身份 + 上一帧实例快照查询。

若以上任一项落地，先在本文档追加真实证据（file:line 或 URL+引文），再按下节接续位置开工。

### 数据布局预留（未接线；区分来源时先定布局再动 colortex22）

当前 colortex22 = RG 前帧 UV 位移、B 前帧预期对数深度、A 有效性（植被写 1.0）。若未来需要区分来源（植被 / 不透明实体 / 透明实体 / 手持），建议先扩 A 通道为编码值（低位有效性、高位来源 2bit：0=植被 1=不透明实体 2=透明实体 3=手持），RG/B 语义不变；旧消费者 `taa_resolve.fsh:72` 以 `>0.5` 判有效，编码值 ≥1.0 时旧判定仍为真，新判定读低位。任何接线前必须同步更新本节与消费段，不得先覆盖后定义。

## 生成 / 消失 / 传送 / 动画断续的预定处理（为下一棒定义，本期未实现）

- 生成（本帧新出现的实例）：接口有效标志=0 → 保持 reactive=1，只做当前帧重建，不读历史。
- 消失：实体移开后暴露的背景由现有 `taa_resolve.fsh:113-116` 负深度机制拒绝旧实体像素，无需新逻辑。
- 传送：引擎无标志时无法区分「快」与「传送」→ 预定依赖接口需求 4 的有效标志；无标志的兜底是玩家相对位移超阈值（与 `lib/taa_state.glsl:21` 相机 8.0 阈值同语义）即拒绝，但兜底本身不是实现依据。
- 动画断续（帧间拓扑 / 贴图变化）：颜色约束（:104-109 的 change 权重）只抑制颜色突变，不解决几何对应；此类实例保持 reactive=1。

### 刚体变换覆盖不了的骨骼 / 顶点形变范围（明确说明）

vanilla 实体动画（四肢摆动、头部转向、物品挥动、死亡翻倒、苦力怕膨胀）在 CPU 上按骨骼烘焙进顶点后才上传；即便引擎提供每实例前帧模型矩阵，也只能重投影实例根变换，骨骼相对根的顶点级位移无对应历史——这部分顶点若按刚体重投影会采到错误表面。方块实体同理（箱子开合、钟摆动、活塞推动为逐顶点或矩阵 + 顶点混合）。因此接口需求 1（每顶点数据）是唯一完整方案；只有需求 2（矩阵）时，正确做法是仅对「根变换 + 可证明无顶点动画」的实例解除隔离，其余保持 reactive=1，由下一棒按引擎给到的形态划分。

## 已完成

- 接口证据调查：官方文档 current 全量索引 + 5 个工作区参考包 + 2 组 Iris 源码转储（引文见「接口证据」节）。
- 三档结论判定（完全不支持）并按契约落「代码零改动」分支。
- 现状链路核实：薄入口、lit.vsh/fsh、taa_resolve.fsh、taa_state.fsh、taa_state.glsl、uniforms.glsl、taa_reactive.glsl 逐一读过，接续点落到行号。
- 本文档全部小节（已知输入与缺口、证据、状态、数据布局预留、边缘情况预定处理、接口需求、接续位置）。

## 未完成

- R4 运动链本体：实体 / 方块实体 / 手持物前帧位置采集、colortex22 扩展消费、动态隔离解除——受引擎输入限制，未实现（等接口需求落地）。
- 透明实体（gbuffers_entities_translucent、gbuffers_hand_water）运动范围划定：依附于运动链本体，未划定（契约要求不自动复用不透明实体方案）。

## 下一处接续位置

若引擎提供真实接口，按此顺序接线（先补证据到本文档，再动代码）：

1. `Astra/shaders/lib/uniforms.glsl:56-60`（`#ifdef ASTRA_TAA` 块旁）声明真实存在的新 uniform / 属性声明层。
2. `Astra/shaders/program/lit.vsh:142-164`：仿植被 varying 链为 `ASTRA_ENTITY` / `ASTRA_BLOCK` / `ASTRA_HAND` 采集前帧位置；有效标志经 `flat varying` 传下。
3. `Astra/shaders/program/lit.fsh:439-448`：解除运动写出段的 `ASTRA_TERRAIN && !ASTRA_HAND` 限制前，先按上文数据布局预留扩展 A 通道来源位，并单独划定透明实体 / 手持范围（RENDERTARGETS 分支 :39-62 需同步核对槽位）。
4. `Astra/shaders/program/taa_resolve.fsh:71-75`：按来源位消费；保持 :30-50 历史验证、:98-112 颜色 / 状态约束、:113-116 负深度不变。
5. 回归参照：植被路径（lit.vsh:146-163、lit.fsh:425-448、taa_resolve.fsh:71-75）与本任务零接触，接线后必须逐帧比对植被行为不变。

## 检查记录

- 开工基线：`python qa/tools/check_pack.py` → `17 checks: 3 FAIL, 0 WARN, 14 PASS`（#4 include graph、#11 Iris parser contracts、#15 vendor isolation；均为既有）。
- 交付前复跑：`17 checks: 3 FAIL, 0 WARN, 14 PASS`（与本记录同批交付，未新增 FAIL）。
