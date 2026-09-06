# Astra 任务计划 — 高级Ⅰ（B 系）

> 梯度定位：**有完整成熟参考实现的独立模块改编**。照参考改编即可做对，不需要自行设计，不需要架构决策。能落在本档的任务绝不升级。
> 上位规格：[design.md](design.md)。升档路径：卡住两轮带证据上报顶级Ⅱ；架构问题直接报顶级Ⅱ。

## 任务清单

| # | 里程碑 | 任务 | 内容 | 验收标准 | 依赖 | 状态 |
|---|---|---|---|---|---|---|
| B1 | M2 | 阴影模块 | `shadow.fsh/vsh` + `global/lighting/shadowmap.glsl`：扭曲、sampler2DShadow 硬件 PCF + 4-tap 软化、自适应 normal-offset bias、彩色阴影（shadowcolor0 GBA）、水面高度写 R 通道、静态回退与 5–10 格交叉淡化、`entityShadowDistanceMul`；**（SC-13 结论下放，依 §4.1 决议）**ENGINE KNOBS 三条增补：`entityShadowDistanceMul = ENTITY_SHADOW_DISTANCE / SHADOW_DISTANCE`（比例，三档均 0.5；Iris 若不接受该表达式则退化为字面量 0.5）、`SHADOW_SOFTNESS` 作 4-tap 核 texel 半径（tap 数固定 4、≤16 texel）、`const bool shadowHardwareFiltering = true;` | 影内外过渡无硬边；染色玻璃投彩影、透明玻璃不投影；`NdotL≤0` 不采阴影 | E1、Z5 | ✅（模块+shadow pass；lit 接线归 E1，实机验收待 SC-6） |
| B2 | M2 | 雾模块 | `fog.glsl`：FogV2 全家族（大气 pow3 + 边界 + 洞穴切换 + 失明/熔岩/水下）+ 空气透视（视向-太阳夹角染色）+ biome tint；`skyFogStrength` 低时跳过天空色 | 六种雾情境截图各一张、切换无闪跳；晨昏地平线随视角染色 | E1、D2 | ✅（模块；lit/sky 消费归 E1/D2，实机验收待 SC-6） |
| B3 | M2 | 植被摇曳 | `wind.glsl` + lit.vsh 顶点位移（树叶/作物/植物），风参数走 Z3 custom uniforms | 温和摇曳、默认开可关、无撕裂 | E1、Z3 | ✅（模块；lit.vsh 调用点归 E1，实机验收待 SC-6） |
| B4 | M4 | godrays | `composite.fsh` + `post/godrays.glsl`：半分辨率 R8 两段式、8 深度采样 + Bayer8 起步、CPU 三重淡出预算 | 直视光源有效果、被遮挡即消失；曝光≤0 整 pass 早退；默认关 | E1、Z3 | ✅（密度图段+pass 启用条件；final 平滑上采样归 E1/C6，实机验收待 SC-6） |
| B5 | M4 | bloom | `composite1.fsh` + `post/bloom.glsl`：半分辨率软阈值 mipmap 采集（两 pass 方案） | 高光溢出自然无灰雾感；0.5x 无明显闪烁 | E1、Z3 | ✅（采集段+mipmap 链；final 合成归 E1/C6，实机验收待 SC-6） |

## 协作规则

- 只改编、不设计：每个模块先找到 `_analysis/` 中的对应参考实现，理解后按 §3.2 命名规范重写；文件头注明来源，登记 THIRD-PARTY.md。
- B4/B5 在 final 链中的插接点以 E1 决议为准（design.md §2.2 的 pass 表）；不得私改 pass 顺序、私开缓冲。
- 验收双闸门：任务表标准 + tasks-standard.md Z7 回归清单；都过才改 ✅。
- 卡住两轮无进展：带失败证据上报顶级Ⅱ，不得硬凑；成功经验不反哺架构（无决议权）。
- 上报与接手：按 [escalations.md](escalations.md) 流程执行（登记→认领→结论下放→闭环）；上报中的任务状态标 🔶。

## 完成记录（每任务一行）

> 共同边界：E1 未冻结（tasks-top-2.md 状态 ⬜），本批**只写模块主体与各自拥有的 pass 程序**，
> program/lit.*、program/final.*、gbuffers 包装、维度壳一律未动；接口契约（参数、调用时机、
> 消费者）写在各模块文件头。实机验收全部待 SC-6（⏸），视觉项零证据，判 ✅ 的依据是
> "照参考改编完成 + 静态校验不劣化 + 接口与台账落档"，视觉判据留给 E4/Z7 实机环节。

- **B1 ✅**：`global/lighting/shadowmap.glsl`（Steadfast 表达式级移植：4-tap 硬件 PCF 宏
  `SHADOW_PCF4`、`shadow_map_position()` 自适应 normal-offset bias、`shadow_mapping()` 含
  5–10 格静态/实时交叉淡化与 SSS 0.7071 地板、水面高度编解码对、`shadow_map_fade()` 供 C2）+
  `program/shadow.vsh/fsh`（水面高度写 R、GBA 染色、`block.10010` 玻璃剔除出 clip space）+
  `lib/settings.glsl` ENGINE KNOBS 三条增补（SC-13，其中 `entityShadowDistanceMul` 写成
  `ENTITY_SHADOW_DISTANCE * (1.0 / SHADOW_DISTANCE)`——裸相除是整数除法会得 0，这是对决议
  表达式的一个必要改写，语义不变；Iris 接受性待 SC-6，退化预案已写入行内注释）。彩色阴影
  组合 `all + tint * opaque * (1 - all)` 为 Astra 推导（Steadfast 无彩色阴影，Mellow/Solas 的
  深度比较式不适用于 sampler2DShadow），已登记台账。
- **B2 ✅**：`global/atmosphere/fog.glsl`（FogV2 六情境齐全；`skyFogStrength` 接 SKY_FOG_STRENGTH
  并保留低值清零优化；FOG_DENSITY/UNDERWATER_FOG_DENSITY 就地接入）。**雾色为参数而非
  uniform**：Steadfast 的 caveFogColor/underwaterFogColor 是 CPU custom uniform，但 Astra 的
  Z3 uniform 集冻结在 SC-14、雾色归 D2/C1 的调色板，故改为 `FogParams` 结构体传入。空气透视
  `fog_air_perspective()` 与 biome tint `fog_biome_tint()` 为自实现（Refrax 仅思路）。
- **B3 ✅**：`global/lighting/wind.glsl`（`wind_displacement()` 逐行移植；`wave_foliage()` 把
  Steadfast lit.vsh 里的 WaveFoliage 材质无关化——isLeaves/isGroundFoliage 布尔由调用方从
  材质 ID 解出，E1 冻结后接线）。WAVING_FOLIAGE_STRENGTH 在此接入；`windStrength` uniform
  数值上即 Steadfast 的 windStrengthHalf（峰值位移 = 2×windStrength），已在文件头说明。
- **B4 ✅**：`global/post/godrays.glsl`（8 深度采样 + Astra 自写 bayer8 起步抖动）+
  `program/composite.fsh`（曝光≤0 整 pass 早退 + RENDERTARGETS:1）+ `program/composite.vsh`
  （**lightScreenPos 由顶点级 `gbufferProjection * vec4(lightVector, 0)` 算出**，替代 Steadfast
  的 screenLightVector/windowToScreenGodrays 两个 CPU uniform——避免动 SC-14 冻结的 Z3 uniform
  集；代价是每帧 4 顶点一次矩阵乘，纯算术不违反 §5 CPU 卸载）+ `shaders.properties` 补
  `program.composite.enabled=GODRAYS`（Z3 完成记录明确留给 B4 的启用条件）。final 段平滑上采样
  的输出契约（R8 未缩放、曝光与强度都不在此段施加）写在 composite.fsh 文件头。
- **B5 ✅**：`global/post/bloom.glsl`（Refrax 公式级移植：软阈值 knee `bloom_prefilter` + 13-tap
  下采样 `bloom_capture`；Astra 自定：BLOOM_SOURCE_CLAMP=16 抗无 TAA 火花、多级合成
  `bloom_composite` 权重 0.40/0.30/0.20/0.10 递减 + additive，防灰雾）+ `program/composite1.fsh`
  （`colortex2MipmapEnabled = true`——mipmap 链就是多级来源，两 pass 替代 Mellow 六 pass 金字塔）+
  `shaders.properties` 补 `program.composite1.enabled=BLOOM`。**PROVENANCE 标记已按 §9.2 加在
  文件头并登记台账**（发布前须重写）。
