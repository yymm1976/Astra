# 2026-09-30 实机反馈调研（第二轮）：水下远景糊 / 下界岩镜面感 / 吸积盘棉絮感

针对数据链修复后新一轮实机反馈的根因调研。**本文不含代码改动**；读取时点 2026-09-30 19:08（工作区未提交，行号漂移以符号名为准）。参考源码：`SOLAS` = `_analysis/Solas Shader V2.2b/shaders`、`CMP` = `_analysis/Complementary r5.9/Reimagined/shaders`、`ASTRA` = `Astra/shaders`。

先说本轮的背景性结论：数据链修复已生效——截图里水下的焦散网纹（新链路）、下界岩的反射（材质表修复后链路首次真正运行）都在工作。三个新症状都是"行为正确但参数/体系与参考有差距"或"参考自身的保守行为"，不再有链路级 bug。

## 1. 水下远景非常糊

变暗/软化项全清单（正午、面向太阳）：

| 项 | 位置 | 量级 | 性质 |
|---|---|---|---|
| 指数雾饱和 | `lib/solas_water.glsl:86-90` | k=0.0436/格（32 格→0.75，80 格→0.97），远景只剩雾色 | **参考行为**（Solas k=0.06 更浓 27%，`solas_water.glsl:84-85` 注释自认 Astra 映射更清淡） |
| 面向太阳 glare | `lib/solas_water.glsl:94-97` | `glare·16·timeBrightness·eBS`：面向太阳时雾色放大 **~13.6×**，太阳锥内远景洗成亮蓝白 | **参考行为**（与 SOLAS waterFog.glsl:10-19 逐字符相同——"逆光泛白"是 Solas 的设计意图） |
| 光束 resolve 半分辨率 16-tap | `light_shafts.glsl:79-104` + `shaders.properties:20-24` | 光束层模糊半径约为 Solas（全分辨率 4-tap）的 2 倍 | **Astra 特有**，但只软化加色光束层，不动场景本体 |
| 焦散网纹高对比 | `caustics.glsl:35-36`（0.25+4c，峰值 HDR，VL 内平方夹 8） | 近处网纹清晰 vs 远景全糊的反差放大"糊"的观感 | **参考参数原样**（SOLAS shadow.glsl:52-54 同式同值） |
| 排除项 | TAA 水下禁用（`taa_resolve.fsh:97`）、FXAA geometryOnly（`final.fsh:17-21`）、雾单次施加（`scene.glsl:206`）、水下 bloom 0.25 强度 | — | 非贡献项/已是抗糊措施 |

判定：**"糊"的数学本体是 Solas 同款的指数雾幕，面向太阳时被 glare 项放大 13 倍**——用户截图正是面向太阳构图。Astra 没有比参考多糊，反而清淡 27%。

可用杠杆（均为贴参考参数的标定，不是修 bug）：
1. `UNDERWATER_FOG_DENSITY`（现 40；Solas 等效 55——**Astra 已偏低**，进一步下调是偏离参考的画质决策，需明示）。
2. glare 的 16× 系数与 `0.1+0.4·sunVis` 雾色底（面向太阳的泛白强度）。
3. 光束 resolve 升到全分辨率 4-tap（对齐 Solas，顺带消掉光束层 2× 模糊）——成本与收益需实测。
4. **前提**：先拿 Solas 实机同角度（面向太阳水下远景）截图做基线对照——若 Solas 同样泛白，则当前观感即参考行为，是否保留属画质取舍而非缺陷。

## 2. 下界岩"镜面感"→"发光感"

**核心发现：fresnel 公式不是差距。** Astra `nether_reflection.glsl:51-53` 与 Complementary `deferred1.glsl:306-307,312-313` 逐项一致（收紧式 + 平方 + sqrt(s)，45° 混合比精确为 0）。真正的差距在三个体系：

| 体系 | Complementary（发光感） | Astra（镜面感） |
|---|---|---|
| 方块光峰值 | lm15 → **(8.56,5.02,3.72)**，无上限（mainLighting:353-355,547 + blocklightColors:9） | (4.40,2.58,1.91) = **51.4%**（`nether.glsl:111-112` 的 4.4 上限），且 steep 用 level⁸（参考 level⁴）→ 中段更暗 |
| 逐纹素发光 | 岩浆块亮纹素 `emission=4r⁴` + `maRecolor` 加色（terrainIPBR:1200-1218）；netherrack 部分 emission=0.2 | 无（E3 逐纹素光泽第一轮已删；`nether.glsl:189` 的 emission² 只覆盖发光体自身） |
| bloom | **scene⁴×128 无硬阈值**（composite5:114-116，强度 0.12）→ 0.35 亮度的受火岩石也泛暖光 | 硬阈值 1.0+knee 0.5（`bloom.glsl:27-30`）→ 受火岩石（~0.35）**完全不 bloom** |
| GGX 火旁高光 | 有（mainLighting:596-619，用 netherrack 自己的 smoothnessG） | 无对应项 |
| 距离 bokeh | 5-tap max，>60m 混入（deferred1:251-261） | 无（第二轮起一直未补） |
| SSR 像质 | 法线抖动 + **时域累积 ≈28 帧平均**（composite.glsl:138,202-211）+ 5×5 高斯（reflectionBlurFilter:6-27）+ mip → **柔光晕，无法辨认镜像** | 单帧 mip 1.6-2.3 → **稳定可辨认的镜像画面** |

为什么读起来像"整个画面镜面反射"：洞穴里看地面，绝大多数像素入射角 60–85°（越远越掠射）→ 混合比 6–38%；反射源是 colortex0 完整画面（含亮岩浆/传送门/雾色）；`max(base,reflected)·0.7` 让所有比岩石亮的反射纹素 ≥70% 存活；单帧无模糊无累积 → 稳定镜像；**且地面上没有任何与它竞争的发光信号**（方块光砍半、零 bloom、零逐纹素发光、零 bokeh）——SSR 成为唯一"有趣"信号。

**与硬约束的协调**（"不得加强发光体" vs "让像素发光"）：两者的界线是——发光体**自身**亮度（emission/boost）维持 1.35 不回加；"发光感"来自**环境响应体系**向参考对齐（方块光峰值、bloom 曲线、GGX、bokeh）。上一轮的"过红刺眼"= boost 2.00 + 无上限曲线 + 无 maRecolor 压制 + 硬阈值 bloom 的组合；本轮方案 = boost 1.35 保持 + 曲线峰值对齐 8.56 + **同时**移植岩浆块压制（`color.gb *= max(2.0-11g²,0.5)` 压黄白成纯红）与软 bloom 曲线——净观感对标 Complementary 参考而非回到刺眼。逐项 A/B 缺一不可。

改向清单（精确到落点）：
1. 方块光峰值对齐参考：`nether.glsl:111-112` 去掉 4.4 钳制（峰值 → 8.56），steep 项 level⁸ → level⁴（mainLighting:353-355 为准）——**必须与第 2/3 条同批落地**，单独抬峰会复现刺眼。
2. bloom 曲线换参考的 scene⁴×128 预滤波（composite5:114-116，强度 0.12 起步），替换硬阈值 1.0——受火岩石进入泛光，"火气"的主要来源。
3. 岩浆块压制与发光纹素：`terrainIPBR.glsl:1200-1218` 的 `4r⁴` emission、`gb·max(2.0-11g²,0.5)`、`maRecolor=emission·0.075` 打光后加色（加色落点参考 gbuffers_terrain:333-335）。
4. SSR 像质：加时域累积（composite.glsl:202-211 的重投影+minBlendFactor≈0.035）与 5×5 高斯（reflectionBlurFilter:6-27）——把"可辨认镜像"变"柔光晕"；或最低成本：下界 rock 类直接关 SSR 分支（参考的地面观感本就不靠 SSR，45°=0）。
5. GGX 火旁高光（mainLighting:596-619）与距离 bokeh（deferred1:251-261 + distantLightBokeh.glsl）——两个"火气"补全项。
6. 保持不变：fresnel 收紧式、纹理保持 mix、mip LOD——已与参考一致，不是差距。

## 3. 黑洞吸积盘"棉絮感"

实现事实：盘面材质**不是程序化噪声**，是一张 1024×1024 RGBA8 低频流纹理 `textures/astra-end-flow.png`（mcmeta 无 mipmap），三通道全部 `textureLod(..., 0.0)` 强制 LOD0（`end_kerr.glsl:172-184`）；盘渲染在专用全分辨率 pass（colortex9 RGBA16F，`end_sky_buffer.fsh`），但 `program/deferred.fsh:132-134` 把末地全部天空标为 reactive=1.0 → **TAA 对盘完全失效**；默认 FXAA 又被 `final.fsh:17-24` + `fxaa.glsl:30-39` 的平坦深度跳过——**盘面零 AA、零时间积累**。

棉絮感根因排序：
1. **单张 ~1.5–2 倍频的低频纹理被放大 2–4 px/纹素且强制 LOD0**（FFT 实测：90% 能量集中在最低 49 个频率 bin，主特征 20–100 纹素 → 屏幕上 40–360 px 的大软团）——棉絮主体。
2. **零 AA 零时域积累**：软团边缘、采样闪、静态 IGN dither 颗粒（±1 LSB，末地暗部门控）全部裸露。
3. **strands/grains 细丝通道欠采样 5–15×**（0.06–0.2 px/纹素），本该是细丝/火花，塌成软斑；`end_kerr.glsl:200-202` 的 footprint 衰减门在原生分辨率永不触发。
4. 排除：不是 TAA 拖尾（盘上 TAA 未生效）、不是逐帧噪声重掷（相位连续，运动=差速旋转整体搬移软纹理）。

提升路径（按参考出处）：
1. **纹理之上叠 3–5 倍频程序化 fbm**：大结构留给现有纹理，细丝由倍频提供，最高倍频取到屏幕 1–2 px，高频按 footprint 渐隐（复用 resolved 门）。出处：CMP nightNebula.glsl:41-52（fbmCloud + smoothstep 重映射）、SOLAS skyEffects.glsl:75-84（5 倍频 noisetex 累加）。
2. **旋臂式域扭曲替代整团旋转**：高频倍频放在被差速/螺旋剪切的域里，时间项极慢漂移（≤0.001 uv/s）——Astra 在 end_kerr.glsl:191-197 已记录过 winding/ghost 教训；螺旋写法见 SOLAS skyEffects.glsl:49-58。
3. **让盘面进时域**：收窄 `deferred.fsh:132-134` 的全屏 reactive 屏蔽（只屏蔽透镜星场/热点闪烁），配合 strands/grains 按 footprint 取 LOD 先消欠采样闪——参考包的慢速天空动画都在各自 TAA 下长期稳定。

## 4. 修复优先级建议（供修复负责人）

1. 下界"发光感"三件套同批落地：方块光峰值对齐 + bloom 软曲线 + 岩浆块压制/发光纹素（缺一会复现刺眼或没火气）；SSR 像质柔化或关断二选一。
2. 吸积盘：先做路径 3（reactive 收窄 + footprint LOD，成本最低、消闪），再上路径 1（fbm 倍频）。
3. 水下：先取 Solas 实机基线截图对照；确属参考行为后，是否调 fog density/glare 由用户画质取舍决定；光束 resolve 可低成本对齐全分辨率 4-tap。
4. 硬约束持续有效：发光体自身亮度（boost 1.35）不回加；环境响应体系对齐参考时逐项 A/B 并在声明章节记录。

## 5. 修复时的直接源码核实与勘误

本节追加于实际修复时，保留前文的调研时点与原始判断。以下均重新读取本地参考原文件和 Astra 消费路径，未按前文行号直接移植。

1. **方块光陡峭项应为八次方，Astra 原式正确。** Complementary `lib/lighting/mainLighting.glsl` 的实际表达式是 `pow2(pow2(lightmap.x * lightmap.x))`，即 level² 连续平方两次，得到 level⁸。前文提出改为 level⁴ 是误读，本轮没有采用。4.4 红通道上限确为 Astra 偏离参考的减量，当前仍保留；不能把它与曲线指数混为一个错误。
2. **scene⁴×128 是压缩存储解码，不能作为预筛选移植。** Complementary `program/composite4.glsl::BloomTile` 先平均原场景，再输出 `(bloom/128)^0.25`；`composite5.glsl::GetBloomTile` 的两次平方和 ×128 将其还原。参考确实没有高亮阈值，随后 `DoBloom` 将场景与模糊结果混合；前文把解码写成“预滤波曲线”不成立。本轮没有将其作用于原 HDR 颜色。
3. **terrainIPBR 中 4r⁴、绿色判断、gb 压色与 0.075 加色针对 magma_block。** 原文件 `lib/materials/materialHandling/terrainIPBR.glsl` 的所在分支明确为 `Magma Block`，不是流动/静止 lava。0.2 emission 也只属于这个岩浆块分支的暗色 netherrack 部分，不是普通下界岩的普遍自发光。该套代码不能视作所有岩浆的减亮公式。
4. **所列 GGX 在下界不执行。** `lib/common.glsl` 的 OVERWORLD / else 中，else 明确 `#undef LIGHT_HIGHLIGHT`；`mainLighting.glsl` 所列 GGX 又被该宏保护。它使用 lightVec 的定向光，并非火焰/岩浆逐光源高光。前文将其列为下界“火气补全项”错误，本轮没有新增伪对应项。
5. **“不是程序化噪声”应限于运行时。** `astra-end-flow.png` 实际由 Astra 自己的生成器计算出来；运行时使用烘焙后的低频纹理，确实没有细丝 fBm。对当前 1024 RGBA 图像去均值后计算二维 FFT，半径 49 频率范围内能量占比为 R 99.99%、G 99.95%、B 99.99%、A 99.94%，支持低频主导判断。该数字不等价于所有视角固定放大倍数。
6. **原生分辨率下 footprint 淡出并非永不触发。** Astra 在 `end_disc_transfer` 用图集四邻域的径向跨度进一步放大 imageFootprint。当前真实图集每隔 8 纹素取邻域，以 imageFootprint=0.004 代入原公式，合法同分支样本中有 332 个 sourceFootprint>0.08，最大约 0.8856。因此仅凭附件原生分辨率不能排除旧淡出门；该数字是图集公式的反例，不是游戏屏幕占比。
7. **相位取模不消除差速绕卷。** 原 `mod(time*omega(r),TAU)` 只限制数值范围；周期噪声的径向相位导数仍包含 `time*omega'(r)`，会随运行时间增长。旧注释的“不绕卷”理由不成立，本轮替换为固定空间螺旋剪切和慢速均匀相位漂移。

核实成立并据此处理的主项：Solas 的指数雾与迎光 glare 确实持续擦除远景对比度；Astra 下界 SSR 缺少参考的粗糙空间重建；End 全天空 reactive=1 和默认 FXAA 的深度门确实让盘面失去相应抗锯齿路径；纹理强制 LOD0 确实没有按缩小足迹过滤。

具体修复、借用、偏离与量级写在 `2026-09-28-water-material-lighting.md` 的“依据 blur/glow/disk 调研的修复”章节。保留发光体减量约束，没有执行提高发光体的建议。
