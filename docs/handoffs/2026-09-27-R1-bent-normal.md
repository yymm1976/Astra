# R1 / H2 bent normal 与方向性天光重评 — 交接记录

状态：**代码完成**。生产（半分辨率 bent normal）、保边重建、SH 天光重评消费、独立性门控、设置 / 中英文说明 / README 已全部写入工作区，并通过 6 组驱动编译（failed=0）与 check_pack（FAIL 数与基线持平）。**没有对应的游戏画面或帧时数据；不声称任何观感或性能收益。**

负责人：R1。缓冲索引选型：colortex24 / 25 已被 R6 云历史交接（docs/handoffs/2026-09-27-R6-cloud-temporal.md）先行登记，本任务按"从 24 起选、避开已登记索引"取 **colortex26 / colortex27**（选型时两者在 shaders.properties 与全部 handoff 记录中均无占用；R6 代码后落入了 24/25，与本任务无冲突）。

## 已改文件

| 文件 | 改动 |
|---|---|
| Astra/shaders/program/ssao.fsh | AO 核内新增 bent normal 生产（估计量见下）；`DIRECTIONAL_SKYLIGHT` 关闭时生产段整体编译移除，RENDERTARGETS 退回 21 |
| Astra/shaders/lib/ao_resolve.glsl | `astra_ao_visibility` 增加 bent 保边重建（out 参数）；`astra_apply_ambient_ao` 增加 SH 天光重评交换；新签名带 `skyPalette` 参数 |
| Astra/shaders/lib/sky_directional.glsl | 抽出 `astra_directional_sky_coeffs(coefficients, normal, palette)`（同一数学，两次求值共享一次 colortex18 读取）；`astra_directional_sky` 保持为加载包装 |
| Astra/shaders/global/lighting/diffuse.glsl | `diffuse_lighting` 新增 `out vec3 directionalSkyRadiance`；方向天光份额系数（除 SH 方向外的全部因子）单独追踪并输出 |
| Astra/shaders/program/scene.glsl | `astra_light` 新增 `out vec3 skyResponse` 并透传 |
| Astra/shaders/program/lit.fsh | RENDERTARGETS 增加 27 臂（TAA 与非 TAA 两路）；接收面写入 response，零填充写 alpha=1 以兼容无 blend 覆盖的默认混合 |
| Astra/shaders/lib/surface_buffers.glsl | colortex27 格式 / 清色常量（AO+方向天光同开时） |
| Astra/shaders/shaders.properties | colortex26/27 的 size.buffer 门控（94–112 行区域），未新增选项、未动他人键 |
| Astra/shaders/lang/en_US.lang、zh_CN.lang | DIRECTIONAL_SKYLIGHT 与 SCREENSPACE_AO 两条 comment 更新（仅这两键） |
| Astra/README.md | 实现状态与边界三条定点更新 |
| 本文件 | 交接记录 |

## 实际调用关系（生产者 → 消费者）

```
prepare3 (sky_irradiance.fsh) → colortex18 (SH9, 9x1 RGBA16F)  [原有]
gbuffers lit.fsh (diffuse.glsl:482 directionalSkyRadiance → scene.glsl:286 skyResponse
                 → lit.fsh:284) → colortex27 (RGB=可重评天光响应, 全分辨率)
deferred pass (root deferred.fsh 壳, ASTRA_SSAO 时 = program/ssao.fsh)
  → ssao.fsh:58-113 bent 估计 → colortex26 (RG=八面体 bent 世界方向, B=可见权重和, A=1)
  → ssao.fsh:104-106 标量可见度/对数深度/几何法线 → colortex21 (BA 语义不变, 几何法线)
deferred2 pass (deferred2.fsh 壳 → program/deferred.fsh)
  → deferred.fsh:149-150 astra_apply_ambient_ao(..., astra_sky_ambient())
  → lib/ao_resolve.glsl:19-46 astra_ao_visibility 内 4-tap 保边重建 bent (colortex26)
  → ao_resolve.glsl:69-79 用 colortex18 系数对 bent 与几何法线各求一次 S_SH，按
    response*(S_SH(bent)-S_SH(geo))*min(vertexAO,SSAO) 交换回场景 (85 行)
```

消费点证据：`program/deferred.fsh:149`（调用）→ `lib/ao_resolve.glsl:73-79`（SH 重评与交换）。colortex26 采样点：`lib/ao_resolve.glsl:39`。

## 估计量 / 采样权重 / 退化条件

- **估计量**：与标量 AO 同一 12 点 golden-angle 螺旋核上的"可见度加权未遮挡方向均值"。每个拿到真实场景点的样本贡献单位方向 δ̂_i（视空间，随后经 `view_player`（方向专用旋转）转世界空间），权重为该方向自身的未遮挡比例。**不是未经方向加权的深度差**。
- **权重**：单样本遮挡 o_i = max(dot(N,δ)−0.035,0)·|δ|⁻¹·(1−|δ|²/r²)，与标量 AO 逐样本表达式完全一致；该方向可见度 v_i = 1 − min(2.5·o_i, 1)（2.5 对应标量 resolve 的 (2.5/12)×12 满核尺度）。超出 AO 半径的样本计 v=1（与标量 AO 同样视为无遮挡）；离屏 / 天空 / 非接收面 / 退化样本为无信息，不计入。仅前向半球（dot(N_v,δ̂)>0）参与。**AO_STRENGTH 不进入**，方向保持几何量属性。
- **生产退化 → 几何法线**：Σv_i ≤ 0.5（无实质可见样本，如封闭角落）或 |Σ v_i·δ̂_i| ≤ 0.25（平坦 / 对称环，净方向为零）；回退时写入选中纹素几何法线（ssao.fsh:111-113）。
- **重建退化 → 几何法线**：4 tap 保边滤波（双线性轴权重 × exp2(−64·Δlogdepth) × agreement⁸，拒绝 Δdepth>0.05 或 agreement<0.85，与标量 AO 完全同权重）无匹配样本时（ao_resolve.glsl:44,46）。
- **重建坐标**：继续走带 TAA 抖动约定的 `screen_view`（lib/transforms.glsl，UV 扣除 `astra_jitter_uv()`），与改动前一致，无新坐标路径。

## 缓冲格式与生命周期（改动前后对照）

| 缓冲 | 改动前 | 改动后 |
|---|---|---|
| colortex18 | RGBA16F 9×1，prepare3→diffuse，逐帧重建 | 不变 |
| colortex19 | RGBA16F 全分辨率，lit→deferred2，未遮蔽环境 RGB+顶点 AO，逐帧清零 | **语义不变**（含旧 SH 天光的完整环境光，交换公式依赖此语义） |
| colortex20 | RGBA8 全分辨率，世界几何法线 RGB+有效性 | 不变（仍是 bent 重建的几何法线来源与几何边界判据） |
| colortex21 | RGBA16F 半分辨率，R 可见度、G 对数深度、BA 八面体**几何法线** | **BA 语义保持**（bent normal 另存 26，消费者仍拿 BA 判几何边界） |
| colortex22 / 23 / 24 / 25 | TAA 植被 / R2 体积 / R6 云历史 | 不变，未触碰 |
| **colortex26（新增）** | — | RGBA16F，半分辨率（仅 AO+方向天光同开），RG=八面体 bent 世界方向、B=可见权重和 Σv_i、A=1；deferred(ssao) 写 → deferred2 读；逐帧重建；关闭任一选项时 1×1 且不产出（生产段编译移除） |
| **colortex27（新增）** | — | RGBA16F，默认全分辨率（仅 AO+方向天光同开），RGB=可重评天光响应（材质响应 × 天光可达 × 夜视 / 晨昏距离因子，不含 SH 方向），A 恒 1（使默认混合下零填充也替换旧值）；不透明 gbuffers 写 → deferred2 读；逐帧清零；关闭任一选项时 1×1 且不写入 |

1080p 新增存储：colortex26 约 3.96 MiB + colortex27 约 15.82 MiB（RGBA16F）；仅"环境光接触遮蔽 + 方向性天光"同时开启时存在。方向分量（26）与响应分量（27）尺寸刻意不同：方向是半分辨率几何量（随 AO 网格保边重建），响应是全分辨率光照量（保留材质细节）。

## 与原天光 / 标量 AO 的合成方式

deferred2 中，`extra = vertexAO − min(vertexAO, SSAO)`：

```
scene' = scene − colortex19.rgb·extra + colortex27·(S_SH(bent) − S_SH(geo))·min(vertexAO, SSAO)
```

- 代数上精确：渲染像素含 D_geo·vertexAO；减去 colortex19.rgb·extra（= 整体环境 × extra）后，旧几何法线天光份额经 (S_SH(bent)−S_SH(geo))·min 项整体替换为新方向份额，最终 = 非环境光 + 环境非天光部分·min + 天光(bent)·min。
- **未整体缩放 colortex19**：交换只作用于单独保留的方向份额（colortex27）；洞穴最低亮度、晨昏补光、方块光、直射、自发光不经此项。
- **材质响应保留**：colortex27 在 lit 端把 albedo（含夜间去饱和后）、skyLight 可达、夜视保留比、夜间距离渐变全部乘好，deferred2 只换 SH 方向，不重建、不猜测材质。
- **零阶有界**：SH 零阶均值 < 1e-5 时 `astra_directional_sky_coeffs` 返回 palette·(0.67+y·0.33)（有界 0.34..1.0·palette），两方向之差有界（≤ palette·0.33·√2）；内部 diffuse/mean 另有 [0,2] 钳制；response ≥ 0 且为零（洞穴 / 夜视 / 非参与材质 / 水下）时整段跳过。
- 标量 AO 语义不变：`min(vertexAO, SSAO)` 仍整体作用于环境分项（含交换后的天光份额）。

## 独立性（实现门控 + 驱动编译证据）

| 组合 | 行为 | 编译 |
|---|---|---|
| 仅 AO 开 | 标量 AO 原样；26/27 为 1×1 不产出不消费（lit 27 臂、ssao 生产段、ao_resolve 交换段均在 `DIRECTIONAL_SKYLIGHT` 下编译移除） | PERFORMANCE+SCREENSPACE_AO：failed=0 |
| 仅方向天光开 | H1 原样（lit 内几何法线求值），无任何 AO 阶段 | PERFORMANCE+DIRECTIONAL_SKYLIGHT：failed=0 |
| AO 开、实时阴影关 | `ASTRA_SSAO = SCREENSPACE_AO && SHADOWS && AO_STRENGTH>0`（原有门，未改）→ 全链关闭 | PERFORMANCE+SCREENSPACE_AO+undef SHADOWS：failed=0 |
| 双关 / TAA 关 | 原路径逐位不变（TAA 不在本链任何门内） | PERFORMANCE 基线：failed=0 |
| 双开 + TAA | 7 附件臂（≤ GL 的 8） | BALANCED+双开：failed=0 |
| 调试模式 | DEBUG_VERTEX_AO=1 时 ASTRA_SSAO 关闭，全部编译移除 | PERFORMANCE+DEBUG_VERTEX_AO=1：failed=0 |

AO 原范围约定保持：`lib/ao_material.glsl` 未动（主世界空气侧普通不透明地形）；`separateAo`/阴影前提未动；独立顶点 AO 输入问题本任务未解决，故"要求实时阴影"保留。nether/end：world-1/world1 的 deferred2 均为空壳禁用；world-1/deferred.fsh（下界）共享 program/deferred.fsh，AO 调用点现按维度排除（原路径在该处因 colortex19.rgb=0 / colortex21 缺失本就恒等无操作）。

## 验证记录

- `python qa/tools/check_pack.py`：开工基线 **3 FAIL（#4/#11/#15）**；交付前复跑 **3 FAIL（#4/#11/#15，逐项与基线措辞一致），14 PASS，EXIT=3**（完整输出见 qa/r1_final_check_pack.txt）。期间并发 R6 曾短暂引入 #1/#2/#11/#12 的 CLOUD_TEMPORAL 相关 FAIL，R6 自己已修复，与本任务无关。#14 现覆盖 28 个缓冲，colortex26=1、colortex27=1 声明存活且被消费。
- `python qa/tools/compile_glsl.py --minecraft-root D:/zhenhebao/.minecraft`（RTX 4050 / GL 4.6.0 驱动真实编译）：六组配置 linked=105 failed=0 compute=9 全部通过（PERFORMANCE 基线 / +AO / +双开 / BALANCED+双开 / +AO−SHADOWS / DEBUG_VERTEX_AO=1；日志 qa/r1_compile_*.log）。
- Expander 展开核验：deferred2 展开源含 colortex26/27、astra_directional_sky_coeffs、skySwap、bentNormal；gbuffers_terrain（主世界/下界/末地）含 27 附件与 skyResponse 写入；下界 world-1/deferred.fsh 展开源含 ao_resolve 且经驱动编译通过。

## 已完成

- bent normal 真实生产（方向加权估计量，非深度差）、保边重建、SH 天光求值实际消费（消费点见上）。
- colortex19 合规处理：可重评天光份额与材质响应单独保留于 colortex27；无整体缩放；直射 / 方块光 / 自发光未触碰；零阶有界。
- colortex21.BA 几何法线语义保持。
- 独立性全组合门控与编译证据；AO 范围约定保持；无效方向 / 轮廓不匹配 / 无样本三路回退几何法线。
- 菜单语义、中英文说明、README、缓冲登记、交接记录。

## 未完成 / 当前限制

- 无游戏画面或帧时数据：方向修正的观感、12 样本估计的噪声表现、性能开销均未验证。
- bent normal 仅在"环境光接触遮蔽 + 方向性天光"同时开启时产出与消费（AO 合成是唯一消费者）；无 AO 时 H1 保持几何法线，这是约定内的行为而非缺陷。
- 估计量为 12 样本半分辨率量，方向平滑度受核半径与屏幕半径钳制（0.125 UV）限制；超出 AO 半径的样本按可见计，远处遮挡物对方向的贡献偏弱（与标量 AO 同一偏置，刻意保持一致）。
- 几何法线在 colortex20 为 8 bit，S_SH(geo) 重评存在 ≤1/255 法线量化误差（远小于其它项）。
- 未做时域：bent normal 逐帧重建，无历史，无 TAA 交互。

## 下一处接续位置

- 若要调方向响应强度 / 退化阈值：ssao.fsh:96（2.5 权重）、ssao.fsh:112（0.5/0.25 退化阈值）。
- 若要扩消费者（如水下 / 反射天光方向化）：colortex26/27 生命周期登记在本文件，先核对手册与 R6 的 24/25，再从 28 起选新索引。
- 若后续任务解决独立顶点 AO 输入，可解除"要求实时阴影"前提（shaders.properties:95 门与 lib/ao_material.glsl 约定一并复审）。
