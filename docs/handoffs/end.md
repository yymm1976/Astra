# end → 主任务：公共接入交接单

## 2026-09-11 空间交会接续（当前）

用户已要求继续处理空间交会遮挡及剩余内容。本次用统一虚拟空间替换定时遮罩和末尾前景覆盖：环带、碎块、牧羊天体和岛群按射线距离合成；黑洞弯曲光路也经过这些几何。实体改为三维距离场，具备坑内、岛底及天体之间的遮光。

公共接入已经完成：末地专用 `world1/prepare` 生成 1×1 `colortex8` 的当前帧光照状态，供天空和地形共同读取；天空只在 deferred 绘制一次，反射使用同一场景；末地专属紧泛光、8% 暗角与细颗粒已接入。天空菜单新增 20～60 分钟的环进动周期选项。无需其他任务补接接口。

完整实现、文件入口与边界见 [空间交会实现记录](../2026-09-11-end-spatial-implementation.md)。用户已明确选择“保留真实交会与既定轨道周期（当前实现）”，设计书开头已记录该决定：不再硬性要求 10 秒完全不可察觉或每周期仅一次、持续 40～70 秒的环食。本轮剩余代码接入已完成，没有待其他任务补接的接口；没有游戏内最终效果或帧率结论。

## 2026-09-11 末地环接手记录（上一轮）

当前任务以 `docs/2026-09-11-end-final-design.md` 的 L2 环系为目标。下方旧微调交接描述的是历史实现，不代表当前源码；尤其旧紫色雾、directionShade 和旧调色数值不应直接用于当前环系。

本次修改：

- `Astra/shaders/global/dimension/end_system.glsl`：统一环带碎块与牧羊天体的轨道函数；尘埃和缝内细线按径向角速度连续平流，使用圆周纹理坐标避免方位角接缝。64 个碎块的中心主要分布于 A/B 环，另有 6 个位于外晕，避开两条主缝。
- 同文件：两颗牧羊天体各自驱动周围物质清除与渐细尾迹，开环位置与天体共用轨道；表面增加三个不同尺度的凹坑及反向坡度坑沿。
- 同文件：7 个岛体改用各自固定轨道面、不同半径与 24～50.3 分钟周期，其中 2 个反向；增加岛底悬垂岩片与缺口。岛体仍在环带、星空及黑洞之后合成，作为前景遮挡它们。
- `Astra/shaders/global/dimension/end_blackhole.glsl`：将原先横向实心细条遮挡替换为沿环面投影方向移动的分层消光遮罩，复用 A/B 环与环缝密度；第二颗牧羊天体的相位影响遮罩内部密度，使相邻进动周期的遮挡细节不同。沿用 36 分钟一次、60 秒渐变与地形同步减光的既有接口。

尚未解决：

- 环食仍是按时间表移动的前景遮罩，尚非远景环面、牧羊天体与黑洞统一空间模型求出的交会。不能因此认定设计书的完整环食要求已完成。
- 现有碎块和岛体仍为带解析明暗的方向性轮廓，坑内遮蔽与多天体前后顺序尚未使用完整立体几何求解。
- 本次没有游戏内画面依据，环带可读性、静止感、岛形识别和透镜交错的最终视觉表现尚未确认；黑洞本体的完整规格仍属独立待完成内容。

公共接入要求：本次无新增 uniform、共享渲染阶段或配置接口需求。

---

本文件是 `end` worktree 向主任务（水体 / 公共照明 / 阴影 / 合成）申请公共接入的唯一出口。
任务范围见 `docs/parallel-development/end.md`。**不通过直接编辑共享文件绕过边界。**

## 填写字段（与任务书一致，不得省略）

- **接口**：需要主任务提供的函数 / uniform / 变量名，写准确名称
- **调用位置**：文件路径 + 行号 或 shader 阶段
- **参数**：类型、取值范围、单位、语义
- **原因**：不这么做会怎样；为什么无法在本 worktree 内解决
- **本侧已完成**：`end` 侧已经改动的文件（仅限 `Astra/shaders/global/dimension/end.glsl` 及 `global/end/`）
- **主任务侧待办**：需要对方具体改什么

## 待处理

### H1 — End 环境光的逐顶点 AO（vanillaAO）通道

- **接口**：在 `astra_light()` / `end_lighting()` 链路上增加一个逐顶点 AO 标量（Iris terrain pass 的 `glColor.a`）
- **调用位置**：`program/scene.glsl:171-183`（`astra_light` 签名）→ `global/dimension/end.glsl:end_lighting()`
- **参数**：`float vanillaAO`，范围 0..1，语义为 chunk 网格顶点烘焙 AO（Iris/Optifine 惯例，1 = 无遮挡）
- **原因**：Complementary r5.9 末地漫射为 `pow2(directionShade * vanillaAO) * (...)`（lib/lighting/mainLighting.glsl:613），且 End 分支对 AO 做 `pow(vanillaAO, 0.75 + NdotUmax0 * 0.25)`（mainLighting.glsl:577-580）。本侧 2026-09-10 已移植 `pow2(directionShade)` 门控，但接口里没有 AO 通道，岛缘、沟壑、chorus 植物根部缺少逐顶点压暗， relief 只能到面法线粒度。AO 来自 gbuffers 顶点属性，属于 program/ 公共边界，本 worktree 不能自己接。
- **本侧已完成**：`end.glsl` 的 directionShade² 门控已留好乘法位（`sceneLighting *= directionShade * directionShade;` 一行），接入 AO 只需把它变成 `pow2(directionShade * vanillaAO)` 并在 End 分支套用参考的指数曲线。
- **主任务侧待办**：决定是否在 `EndParams`（或 `astra_light` 参数表）中透传 `glColor.a`；若透传，注意 overworld 的 `diffuse_lighting()` 是否也要同一通道（C1 决策）。

### H2 — `screenBrightness` uniform 冻结（Complementary 的 vsBrightness 平衡器）

- **接口**：冻结 uniform `float screenBrightness`（Iris 内置，原版"亮度"滑条）
- **调用位置**：`lib/uniforms.glsl`；消费点为 `global/dimension/end.glsl` 的环境/直射配比
- **参数**：`float`，0..1，玩家视频设置里的 Brightness 值
- **原因**：Complementary r5.9 的末地环境/直射配平为 `endLightBalancer = 0.2 * vsBrightness; lightColor = endLightColor*(0.35-endLightBalancer); ambientColor = endLightColor*(0.2+endLightBalancer)`（lib/colors/lightAndAmbientColors.glsl:82-87，vsBrightness = clamp(screenBrightness,0,1)，lib/common.glsl:748）。没有该 uniform 就无法逐字移植这个平衡器——高亮度玩家会得到更平的环境光、低亮度玩家得到更强的方向对比。本侧当前用固定配比（Astra 既有 0.85 ambient / 0.50 sky-light），不等于参考行为。
- **本侧已完成**：无（等接口）。
- **主任务侧待办**：在 `lib/uniforms.glsl` 冻结 `uniform float screenBrightness;`（与 `nightVision` 同组）；本侧随后把 82-87 行表达式逐字接入 `end_lighting()`。

### H3 — `darknessFactor` uniform（补全 maxBlindnessDarkness）

- **接口**：冻结 uniform `float darknessFactor`（Iris 内置，Warden 黑暗效果强度）
- **调用位置**：`lib/uniforms.glsl`；消费点为 `global/dimension/end.glsl:end_sky()` 与 `end_fog()`
- **参数**：`float`，0..1
- **原因**：参考的天空衰减是 `color.rgb *= 1.0 - maxBlindnessDarkness`（program/deferred1.glsl:386），其中 `maxBlindnessDarkness = max(blindness, darknessFactor)`（shaders.properties:275）。Astra 只冻结了 `blindness`（lib/uniforms.glsl:48），本侧已按 `blindness` 移植；Warden 的 Darkness 效果下末地天空仍然全亮，与地形雾黑不一致。
- **本侧已完成**：`end_sky()` 末尾的 `* (1.0 - blindness)`。
- **主任务侧待办**：冻结 `uniform float darknessFactor;`；本侧把 `(1.0 - blindness)` 换成 `(1.0 - max(blindness, darknessFactor))`。注意主世界雾/天空是否也要同一处理（C1/B2 决策）。

## 待用户决策（不需要公共接入，记录在此）

### D1 — `END_VOID_MIN_STRENGTH`（远距雾下限 0.55）是泛亮残留的最大单项

- **接口**：无（本 worktree 自有常量，`end.glsl:331`，Astra 自有设计，参考包无对应实现）
- **调用位置**：`end_fog()` — `mix(END_VOID_MIN_STRENGTH, 1.0, end_void_depth_gate(worldY))`
- **参数**：0..1，岛平面以上雾强度的下限
- **原因**：按现值推算（END_VOID_REACH=32、END_VOID_SATURATION=3、END_VOID_RESIDUAL=0.05、END_FOG_DENSITY=100）：距相机 32 格以外、岛面高度的地形 fogFactor ≈ 0.55，64 格以外仍 ≈ 0.55（t 截断于 1）——远景地形一半以上被雾色 (0.019, 0.0095, 0.033) 覆盖，与暗侧面亮度同量级，轮廓被雾化。本轮任务只点了"天空、星云、环境照明"三项，雾不在其列，故未改。
- **本侧已完成**：无。建议值 0.40–0.45（保留"岛上看不到清澈地平线"的设计意图，削弱远景泛灰）。
- **主任务侧待办**：无。等杨间拍板数值后在 `end.glsl` 单行改。

### D2 — endSkyColor / endLightColor 的幅度移植未做（跨管线不可验证）

- **接口**：无
- **原因**：参考 `endSkyColor = vec3(0.095,0.07,0.15)*1.65`（lib/common.glsl:817）、`endLightColor = vec3(0.68,0.51,1.07)`（lightAndAmbientColors.glsl:82）处于 Complementary 自己的 tonemap 前空间，幅度约为 Astra 现行线性值的 6–8 倍；没有双方 tonemap 曲线的标定就无法验证逐字幅度移植，按"别猜"原则保留 Astra 现行 Mellow 调色板幅度。色相证据：Astra `END_AMBIENT_COLOR` 归一化 (1, 0.72, 1.54) vs 参考 endLightColor (1, 0.75, 1.57)，已同色，无需移植。
- **本侧已完成**：在 `end.glsl` 文件头 provenance 块记录了该结论。
- **主任务侧待办**：无。若日后要对齐参考亮度，需要先标定 `global/post/grading.glsl`（C6）与 Complementary final 链的曝光关系。

### D3 — 末地体积光柱（DrawEnderBeams）未做

- **接口**：deferred/composite 链上的 raymarch 挂点 + `far`/`shadowMapResolution`/`renderDistance` 等参数
- **原因**：参考的末地光柱是完整体积光追踪（lib/atmospherics/volumetricLight/volumetricLight.glsl + enderBeams.glsl，END_BEAM_INTENSITY/CENTER_ALT/HEIGHT 滑条），挂在 composite 链上，属于 program/ 公共边界且超出"微调"范围。参考里星野的天顶压暗与地平线高度门（enderStars.glsl 的 beamFactor 项）就是为给光柱让位服务的——本侧没有光柱，故星野形状也未跟随参考改动。
- **本侧已完成**：无。
- **主任务侧待办**：如要做，先由主任务在 composite 链提供挂点与参数，本侧可在 `global/end/` 下落 `ender_beams.glsl`。

## 已接入

无。

---
本文件由 `docs/parallel-development/end.md` 第 9 行、第 15 行要求建立。
