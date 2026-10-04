# 2026-09-28：下界氛围/反光与水下的参考实现调研（供第三轮修复借用）

写作背景：用户实机反馈五项——水下光束不明显（只看得见几缕）、水下亮过头、方块焦散太整齐、下界岩仍然没有火焰和岩浆的反光、下界黑调过头——并要求优先借用 Complementary（下界）与 Solas（水下）的写法，避免从零自写。本文是修复负责人的对照报告：每节给 Astra 现状（数值与机制归因）、参考实现（file:line）、以及"建议直接移植 / 参考思路"清单。本文不含代码改动。

- 参考源码：`COMPL` = `_analysis/Complementary r5.9/Reimagined/shaders`（IPBR 默认配置）；`SOLAS` = `_analysis/Solas Shader V2.2b/shaders`；`ASTRA` = `Astra/shaders`。
- 行号基于 2026-09-28 22:56–23:04 对工作区的一次一致读取（未提交状态下行号会漂移，以符号名为准）。
- 借用须知见第 6 节：来源登记、已审不变量、选项上限、与第二轮已改内容的冲突面。

## 1. 水下光束不明显

Astra 现状（`global/water/light_shafts.glsl`，由 `program/scattering.fsh:79-89` march、`program/water_composite.fsh:16-25` resolve 加色）：

| 参数 | Astra | Solas |
|---|---|---|
| 最大光程 | 40 格（:48） | 128 格（volumetricLight.glsl:50） |
| 水下步长 | 按可见水段均分（第二轮） | 均分基础上**再减半**（:51 `minDist*(1-isEyeInWater*0.5)`） |
| 强度增益 | `mix(0.8,4.2,sun)`（:89），正午 4.2× | `waterColorSqrt*(4.0+8·sunVisibility)`，正午 **12×**（:125） |
| 光束图案 | 阴影 caster 衰减色 tint | `shadow1·pow2(shadowcolor0)`（焦散调制色），clamp 8 保 HDR（:113） |
| 角度/天气项 | `0.85·(0.22+0.78·VoL)`（:38-46） | 仰角项 `pow(1-VoU^1.5, 3·waterFactor)` + 阴天补偿 `(2-sunVisibility)`（:29-31）——Astra 移植时丢掉 |
| 存储与模糊 | `pow(integral/128,0.25)` + 4 tap resolve（:91,:105-118） | 同构压缩 + composite5 的 4 tap 十字模糊（composite5.glsl:53-61） |

数值归因：积分 ∝ 可见水段长度，`0.06·exp(-0.045d)` 的净系数近景仅 0.05–0.18/格，gamma 域加色后线性 0.002–0.03，接近不可见；`0.22+0.78·VoL` 把亮度集中到朝向折射太阳的视线（"几缕"）。光束不吃雾（在 fog mix 之后相加），被吃的是阴影硬门。

移植清单：
1. 水下步长减半 + 增益改 `水色√·(4+8·sun)`（SOLAS volumetricLight.glsl:51,125）——单项差距最大。
2. 光束 tint 换成阴影图焦散调制色：水下禁空旷直射项、只取 `shadow1·pow2(shadowcolor0)`、clamp 8（:113）。Astra 已有 `shadow_caster_data`/`shadow_coverage`（light_shafts.glsl:66-71）可承载。与第 3 节联动。
3. 补仰角项与阴天补偿（:29-31）。
4. 保留现有 march/resolve 双 pass 结构，可加 Solas 式十字模糊（composite5.glsl:53-61）。

## 2. 水下亮过头

Astra 现状：水下地形直射有效峰值 ≈2.25²≈5（`lib/solas_water.glsl:19-43` 的 terrain 分支强度平方），焦散最高再加 1.8×（`program/lit.fsh:348-365`），床面可到 ~9×albedo；**相机支路没有消光**——`program/scene.glsl:199-208` 的 `astra_apply_medium` 在水下直接 return（吸收消光只作用于界面支路），统一合成（`lib/solas_water.glsl:103-109`）把画面往亮青色雾目标 `solasWaterSqrt²·(0.1+0.4·sun)·眼适应项` mix，第二轮移除了上限 clamp，无任何净变暗项。

Solas 参照：
- **相机侧雾就是变暗器**：`fog=1-exp(-6·len·0.01·density)`（lib/water/waterFog.glsl:1-3，消光指数 6 vs Astra 的 2）；雾色乘 `(0.1+sunVis·0.4)·眼适应` + 前向眩光 `glare·16·eBS`（waterFog.glsl:8-16）；sqrt 域混合（composite4.glsl:114-119）。
- **LDR/HDR 分工**：地形直射（含焦散调制）clamp 到 1.0（lib/lighting/shadows.glsl:65-80）；HDR（clamp 8）只属于光束路径。水下变暗靠雾 + 水面遮挡（假阴影水下清零，shadows.glsl:89），不靠调大直射再靠雾拉回。
- 无水下专用曝光；水下没有专门的直射加亮分支（lib/lighting/lightColor.glsl 无 isEyeInWater 分支）。

移植清单：
1. 相机支路引入真实消光（指数向 Solas 的 6 对齐，或按 UNDERWATER_FOG_DENSITY 折算），替代"只 mix 亮雾"。
2. 采纳 LDR/HDR 分工：地形侧直射×焦散 clamp 1.0，HDR 上限只留给光束路径——这与第二轮"放开截断"相反，实机 A/B 后取舍并在交接记录写明。
3. 雾色改用 `(0.1+0.4·sun)·眼适应·眩光` 调制（waterFog.glsl:8-16），替代均匀亮青目标色。

## 3. 方块焦散太整齐

Astra 现状归因（`global/water/caustics.glsl`）：`astra_projected_caustic_gain`（:100-108，第二轮新函数）把 6 层**固定波长/固定方向**的平面波解析场（`solas_water_caustics` 本体 :49-96）沿光线-平面刚性投影——同一条光柱上所有深度共享同一图案（文件注释 :98-99 自认），且与水面法线用的噪声高度场完全解耦；唯一的局部变化是 footprint 距离衰减。固定频率 + 无波形耦合 = 网格感。

Solas 参照（焦散烘在阴影图，与波形同源）：
- 水面在 shadow pass 写 shadowcolor0：`albedo.rgb *= 0.25 + caustics*WATER_CAUSTICS_STRENGTH(4.0)`（program/shadow.glsl:50-55）。
- 图案 = `getWaterCaustics`（lib/water/waterCaustics.glsl:26-41）：与水面法线**共用同一张高度图**，5 tap opposing-gradient 乘积 `(Δx⁺·-Δx⁻ + Δy⁺·-Δy⁻)·48`（会聚透镜焦度量，大面积饱和）。
- 高度图双层**反向滚动**噪声：/256 尺度随 -wind、/48 尺度随 +wind，按 WATER_NORMAL_DETAIL 混合（waterCaustics.glsl:1-24），加深度斜切与 4 次视差位移（waterNormals.glsl:29-32）——图案永不重复对齐、与可见波形同步。
- 地形直射经 8 tap 旋转泊松阴影采样被该图案调制（shadows.glsl:65-80，替换直射项而非叠加）。

移植清单：
1. 焦散图案烘回 shadowcolor0（水面写调制值），lit.fsh 焦散块与 light_shafts 改读 caster 携带的图案——**一个机制同时解决症状 1 和 3**。注意第二轮刚把 shadowcolor0 清成"高度+透光"，恢复属加法；独立审查已确认旧消费者零残留，无冲突。
2. 焦散公式换成与法线共用高度图的 opposing-gradient 式（waterCaustics.glsl:26-41），替换固定平面波解析场。
3. 双层反向滚动噪声参数照搬（:4-21）。

## 4. 下界岩无火焰/岩浆反光

Astra 现状归因（`global/dimension/nether_reflection.glsl` + `program/deferred.fsh:160-166`）：
- **强度首要**：非掠射角 `weight ≈ 0.045·mix(0.35,1.0,smoothness)·confidence ≈ 2–4%`——命中也看不见。
- **时序疑点**：march 在 deferred（半透明之前）；若岩浆属半透明层则射线只能打到其下床面。但 Complementary 在 terrain 层处理 lava 材质（COMPL lib/materials/specificMaterials/terrain/lava.glsl 由 terrainIPBR 调用）——需实测 Astra 中岩浆的渲染层归属与 depthtex0 成员资格再定。
- fallback（体素梯度 lobe）无形状；火焰过细 + confidence 门（error 0.12–0.40、边距 smoothstep(0,0.04)）砍命中率。

Complementary 参照（下界无 GGX 高光，specular 全交给 SSR，common.glsl:588-589）：
- 光滑度 = `min1(pow2(color.r)·1.5)`（lib/materials/specificMaterials/terrain/netherrack.glsl:1-7）——Astra 已同思路。
- **强度门**：`fresnelM = max(fresnel-(1-smoothnessD)·0.7,0)/(1-(1-smoothnessD)·0.7)`，再 `·sqrt(smoothnessD)−dither·0.01`（program/deferred1.glsl:306-313）——中等光滑度也有可见反射。
- 反射内容全部是屏幕内真实像素：SSR 读 colortex0（已含 emission² 与方块光），岩浆/火自然在反射里，没有假方向高光。
- **miss 兜底 = 纹理保持**：`mix(reflection, max(color, reflection), 0.7)`（program/composite1.glsl:178-179），永不黑洞。
- **远处发光体 bokeh**：gbuffer 阶段按距离抬 emission（lava→4.5，terrainIPBR.glsl:236-239）+ deferred1 对最终色做 4 邻域 max 融合（deferred1.glsl:251-261）——岩浆湖成大亮斑，SSR 容易命中，画面"有火气"。
- 粗糙模糊四层：法线噪声扰动（composite.glsl:146-157）、命中点 mip LOD（lib/materials/materialMethods/reflections.glsl:194-200）、时域积累、5×5 高斯（reflectionBlurFilter.glsl:1-51）；全开约 55–90 采样/像素，只花在有菲涅尔的固体像素上。

移植清单：
1. **首要（纯公式替换）**：强度曲线换 Complementary 收紧式 + `sqrt(smoothness)` 门（deferred1.glsl:306-313）。
2. miss 兜底换纹理保持混合（composite1.glsl:178-179）；voxel 梯度 lobe 可保留为屏幕外补充，但不再承担主反射。
3. 远处发光体 bokeh 两段（抬 emission + 4 邻域 max）——反射命中率与"火气"观感双赢。
4. 结构验证点：确认岩浆渲染层归属；若需反射半透明层内容，把 march 移到 composite 阶段读 depthtex0/colortex0（Complementary 即 composite 阶段 march）；Astra 的 colortex3.a（光滑度）composite 可直接读，无需新缓冲。
5. 可选：命中点 mip LOD 采样（reflections.glsl:194-200）叠加现有 4 邻域。

## 5. 下界过暗

Astra 现状数值（`global/dimension/nether.glsl`，第二轮后）：振幅 `(0.54+0.24·B)`（:166-167）；palette 在 finalDiffuse 内平方（wastes 红 ≈0.4²·0.66²≈0.07，绿蓝≈0）；minLight 地板 ≈0.007（:173-176）；雾色 = palette²，体积烟密核 `exp(-15)·(0.50,0.12,0.025)` 近乎黑（nether_volume.glsl:124）；emission²=4.0 仅作用于自发光像素本身。

Complementary 参照：
- 振幅 `(0.9+0.45·B)`（lib/colors/lightAndAmbientColors.glsl:80-81）——比 Astra 现值高约 40%；palette 数值与 Astra 完全相同（common.glsl:799-814）。
- 混合结构与 Astra 同构：`pow2(directionShade·AO)·(blockLight + pow2(sceneLighting) + minLighting) + pow2(emission)`，然后**整体 sqrt**（lib/lighting/mainLighting.glsl:614-615）——Astra 第一轮把这个 sqrt 删了。
- **关键推导（供复核）**：感知亮度差在末端 gamma 编码。Complementary（gamma 空间 albedo）感知光指数 = 0.5/2.2 = **0.227**；Astra 现行（线性 albedo × 线性光 S）感知 = 1/2.2 = **0.4545**——阴影衰减陡一倍，这是"黑调过头"的数学主因。若 Astra 在线性域乘 `sqrt(S)`，感知指数回到 0.227，与 Complementary 完全一致。即第一轮"线性域不乘 sqrt"的论证只核对了 albedo 侧、漏了末端编码。**建议恢复 Complementary 完整结构（振幅 0.9+0.45B + 末端 sqrt），两处一起改才是它的观感曲线；实机 A/B 确认**。
- 朝下岩浆假反弹：`ambient += lavaLightColor·pow2(absNdotN·0.5+max0(-NdotU))·(0.7+0.35B)`（mainLighting.glsl:519）。
- AO 软化：`pow(pow1_5(AO), 1+0.5·NdotUmax0)·0.9+0.1`（:574-586）——墙面几乎不压暗，明显减"洞穴感"。
- 方块光陡曲线（pow4/pow2.25，峰值 ≈8，mainLighting.glsl:351-359）——近光源爆亮是"不闷"的主力。
- 岩浆 emission = `luminance·7.48+0.5`（lava.glsl:16）、火 2.35（terrainIPBR.glsl:242-250），配合 bloom 0.12——比 Astra 统一 4.0 高且随纹理变化。
- 空气里有东西：Nether Storm 体积灰烬（lib/atmospherics/netherStorm.glsl，NETHER_STORM_I 0.40，颜色 `netherColor·3.0`，composite1 合入）——Astra 的烟经第二轮压暗后近黑，可对照"亮烟"取值回调。

移植清单：
1. 振幅恢复 `0.9+0.45B` + 末端 `sqrt`（按上面推导，两处一起）。
2. 朝下假反弹与 AO 软化两行公式。
3. 体积烟颜色/亮度对照 Nether Storm 回调。
4. 岩浆/火 emission 量级对照重新标定（放弃统一平方，随纹理亮度变化）。

## 6. 移植注意事项（给修复负责人）

1. **来源登记**：借用 Complementary/Solas 的公式与结构须在 `Astra/THIRD-PARTY.md` 登记（两者已有条目可续写；check_pack #8 校验 provenance 台账）。
2. **已审不变量不得回退**：colortex4"未施加观察介质"语义、水通道两态 RENDERTARGETS 与 colortex16 1×1 尺寸门、colortex28/29 退役保留（1×1 占位）、`global/water/temporal.glsl` 保持未接线、check_pack FAIL ≤ 基线 3（#4/#11/#15）。
3. **选项注册表 80/80 满**：新调参优先用既有选项与 settings.glsl 常量，不加 GUI 行。
4. **与第二轮的冲突面**：本报告多处方向与第二轮相反（放开 clamp ↔ LDR/HDR 分工、焦散移接收面 ↔ 回烘阴影图、雾/烟压暗 ↔ 对照 Storm 回调、振幅下调 ↔ 恢复 0.9+0.45B）。按实机反馈回摆是合理的，但每一处回摆请在交接记录写明理由与证据，不要静默反转。
5. **缓冲与阶段**：若把下界反射 march 移到 composite 阶段，注意 colortex3.a（光滑度）与 colortex0（lit 场景）的读取时序与 world-1 stub 的 include 链；不新增全屏附件，先复用现有索引。

## 7. 第三轮接线补充（2026-09-28 晚，针对"按参考实现接对链路"的三个决策点）

修复负责人已确认三处与参考不一致：焦散被换成规则正弦波、光束叠加了额外衰减、下界反射在透明物体之前拿不到完整画面。接对时的具体决策点：

**（a）焦散回烘 shadowcolor0 的布局与格式**：第二轮后 shadowcolor0 的语义是 R=水面高度（`encode_water_height`，按 8-bit 半格步长设计）、GBA=中性透光。回烘时建议保持 R 不动（`decode_water_height` 的消费者 lit.fsh 焦散块与 light_shafts 都依赖它），把 Solas 式调制色放进 GBA：`tint·(0.25 + caustics·STRENGTH)`（SOLAS program/shadow.glsl:50-55）。**格式坑**：Solas 的 caustics·4 调制值会超过 1，其 shadowcolor0 为 RGBA16F；Astra 第二轮移除了 RGBA16F 覆盖，若沿用 >1 的强度需重新声明 16F（shadowcolor0 面积小，代价可忽略），或把调制值压到 ≤1 在读取端展开。消费端要改齐三处：diffuse/shadowmap 的 caster tint 路径（水下地形直射自动带上图案，Solas 的"替换直射"语义）、lit.fsh 焦散加法块（改读图案，或整体并入 tint 路径——二选一，别两处都叠）、light_shafts 的 beamTint。

**（b）光束衰减链的取舍**：可删的"额外衰减"是 `exp(-currentDist·0.045)` 权重与 `0.85·(0.22+0.78·VoL)` 可见性链——Solas 没有距离指数衰减，样本可见性由阴影采样本身承担，角度/天气项是仰角 `pow(1-VoU^1.5, 3·waterFactor)` 与 `(2-sunVisibility)`（volumetricLight.glsl:29-31）。`beam_limit/(1+peak)` 封顶与存储压缩保留（Solas 同构）。

**（c）下界反射的阶段迁移**：Complementary 的结构是 deferred1 算强度入缓冲 → composite 阶段 march（读 colortex0+depthtex）→ composite1 合成 + 纹理保持。Astra 对应做法：march 从 deferred.fsh 移到 composite 早期阶段（colortex0 此时已含透明层与发光体，depthtex0 同理；colortex3.a 光滑度可直接读）。三个注意：composite 阶段在 TAA resolve 之前、坐标带抖动，march 的投影要走 transforms 的现有抖动约定；确认 world-1 的 composite 阶段门不会把承载 pass 关掉（check #16 的 folder-gate 清单）；强度公式同时换成 Complementary 收紧式 + `sqrt(smoothness)` 门（deferred1.glsl:306-313），否则链路接对了依然看不见。另附验证点：岩浆预期在固体层（deferred 已可见）、火为 cutout，"拿不到完整画面"的主因更可能是下界传送门/半透明粒子与 confidence 门——迁移后可放宽 confidence（error 0.12–0.40、边距 smoothstep(0,0.04)）。

**顺序建议**：接线（a/b/c）→ 编译与 check_pack 门 → 实机确认三链路行为与参考一致 → 再按报告 §2/§5 处理亮度（LDR/HDR 分工 + 振幅/sqrt 一起动）。

