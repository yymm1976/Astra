# Astra — 第三方出处台账（THIRD-PARTY.md）

依据 design.md §9.2 建立，**每新增一个来自参考包的文件/片段即登记**，保持台账与实际代码零偏差。
抽查方法：对表中每一行，打开对应文件核对文件头出处注释与内容来源。
Steadfast 借用行例外——其分类计数由 `python qa/tools/provenance_steadfast.py --quiet` 实算，
`python qa/tools/check_pack.py` 第 8 项把本文件出现的每一处计数与实算值比对，不一致即 FAIL。

参考包许可事实（design.md §9.1）：

| 包 | 版本 | 许可 | 借用政策（个人使用期） |
|---|---|---|---|
| Mellow | v3.4 | MIT | 自由，保留出处注释 |
| Steadfast | 0.8.0 | GPLv3 + 两条 §7 附加条款（作者 coderbot） | 自由；文件头保留 GPL 声明。**7b**：任何传播 Steadfast 或其修改版的页面须在主文靠前处原样给出署名句（含 Modrinth/CurseForge/GitHub 三个下载源）。**7c/7e**：传播修改版时，人类可读名称与文件名必须以 `(edit of coderbot's Steadfast)` 结尾（文件名可用后缀 `-edit-of-coderbot-Steadfast`），且 "Steadfast" 不得出现在该括号之外的名称里 |
| Refrax | v1.3.1 | 保留所有权利 | 允许借鉴；结构级照抄须逐处登记 |
| Solas | V2.2b | 未声明（默认版权） | 同上 |

## 登记表

| 模块路径 | 来源包（源文件） | 借用类型 | 许可 | 文件头标记 |
|---|---|---|---|---|
| `shaders/lib/tonemap.glsl` | Mellow v3.4（`lib/tonemap_operators.glsl` + `lib/tonemap.glsl` 的 apply_saturation/vibrance/contrast） | 逐行移植（重命名为 snake_case；仅保留设计 §4.4 四算子） | MIT | `// From Mellow v3.4 (MIT) by TheCMK` |
| `shaders/lib/encoding.glsl` | Mellow v3.4（`lib/util.glsl` 的 encodeUnitVector/decodeUnitVector/get_luminance、`lib/transformations.glsl` 的 to_linear） | 逐行移植（重命名）+ Astra 增补（srgb_encode/srgb_decode 为 IEC 标准式；pack_octahedral/unpack_octahedral/pack_u16 自写封装） | MIT | 同上 |
| `shaders/lib/transforms.glsl` | Mellow v3.4（`lib/transformations.glsl`） | 逐行移植（删除 DH 分支；Voxy 矩阵分支改由入口专属 ASTRA_VOXY_PASS 控制，SC-32） | MIT | 同上 |
| `shaders/lib/distort.glsl` | Mellow v3.4（`lib/shadow_distort.glsl`） | 逐行移植（compute_bias 内保留其源自 Complementary 的授权注释） | MIT | 同上 |
| `shaders/lib/noise.glsl` | Mellow v3.4（`lib/noise.glsl` 的 noise/noise_water/fbm_fast） | 逐行移植（noise_water 的 WATER_NORMAL_* 宏适配为 WATER_WAVE_SPEED/HEIGHT） | MIT | 同上 |
| `shaders/lib/dither.glsl` | Mellow v3.4（`lib/noise.glsl` 的 ign/dither） | 逐行移植（Astra 无 TAA，dither 固定为静态 IGN） | MIT | 同上 |
| `shaders/lib/bayer.glsl` | 无参考（自写：教科书式 Bayer 递归构造，公共域模式） | 自写 | — | `// written for Astra` |
| `shaders/shaders.properties` 的 `CUSTOM UNIFORMS` 段 | Steadfast 0.8.0（`shaders/shaders.properties`，作者 coderbot） | **表达式级移植**（2026-09-05 复核更正：原记"结构借鉴"不成立）。Astra 侧 31 条：verbatim=14 literal-suffix=3 rewritten=7 astra-only=7（逐字相同 / 仅字面量后缀差异 / 同名改写 / 自写）；逐条名单与复核方法见下节 | GPLv3 + §7 两条附加条款 | 段内注释 `Expression-level port from Steadfast 0.8.0 (GPLv3 + Section 7 additional terms) by coderbot ...` |
| `shaders/block.properties` 基础表（10001–10007、10021–10027） | Mellow v3.4（`block.properties` 现代分支） | 逐行移植（数据表；删除 floodfill 10020） | MIT | 文件头注明 |
| `shaders/block.properties` Astra 补全区（10010、10011，以及并入 10002/10004/10022/10025/10026/10027 的原版补漏 ID） | 无参考（自组：原版 1.21.x 事实 ID 数据） | 自写（2026-09-05 修正：block.properties 无 `+=` 追加运算符，原 6 条 `block.N+=` 行会整行替换基础表，已并入对应基础行） | — | 文件头注明 |
| `shaders/entity.properties` | Refrax v1.3.1 / Solas V2.2b 的 `entity.properties`（仅分类思路） | 结构借鉴（分组方案自组，ID 内容为原版事实数据） | Refrax：专有 / Solas：未声明 | 文件头注明 |
| `shaders/global/lighting/shadowmap.glsl` | Steadfast 0.8.0（`environment/lighting/shadowmap.glsl` 的 ShadowMapping/SampleShadows/静态回退、`program/world/lit.vsh` 的 ShadowMapPosition、`program/shadow/shadow.vsh` 的水面高度编码） | **表达式级移植**（snake_case 重命名；shadowMapResolution/shadowDistance/entityShadowDistanceMul/shadowHardwareFiltering 上移到 lib/settings.glsl 不在此重复；彩色阴影组合与焦散接口为 Astra 增补） | GPLv3 + §7 两条附加条款 | 文件头 GPL 声明 |
| `shaders/program/shadow.vsh` | Steadfast 0.8.0（`program/shadow/shadow.vsh`） | **表达式级移植**（block.properties 原始 ID 判据替代其 materialID 解码；玻璃剔除坐标由 `vec4(-1.0)` 修正为 `vec4(0,0,2,1)`——原写法落在远平面角上，裁剪不可靠） | GPLv3 + §7 两条附加条款 | 文件头 GPL 声明 |
| `shaders/program/shadow.fsh` | Steadfast 0.8.0（`program/shadow/shadow.fsh`）+ Solas V2.2b（`program/shadow.glsl` 的半透明染色混合思路） | **表达式级移植**（Steadfast 壳）+ 结构借鉴（Solas 染色公式）；`smoothstep(1.0, 0.9, a)` 透明度判定与 srgb_decode 为 Astra 组合 | Steadfast：GPLv3 + §7 / Solas：未声明 | 文件头 GPL 声明（Steadfast 部分） |
| `shaders/global/atmosphere/fog.glsl` | Steadfast 0.8.0（`environment/fog.glsl` 的 FogV2） | **表达式级移植**（雾色改为参数而非 custom uniform——Astra 的 Z3 uniform 集冻结于 SC-14，雾色归 D2/C1；FOG_DENSITY/UNDERWATER_FOG_DENSITY/SKY_FOG_STRENGTH 在此接入；空气透视与 biome tint 为 Astra 自实现，Refrax 仅思路） | GPLv3 + §7 两条附加条款 | 文件头 GPL 声明 |
| `shaders/global/lighting/wind.glsl` | Steadfast 0.8.0（`environment/wind.glsl` 的 WindDisplacement + `program/world/lit.vsh` 的 WaveFoliage） | **表达式级移植**（材质无关化：WaveFoliage 的 materialID 判据改为调用方布尔参数，待 E1 接线；WAVING_FOLIAGE_STRENGTH 为 Astra 增补） | GPLv3 + §7 两条附加条款 | 文件头 GPL 声明 |
| `shaders/global/post/godrays.glsl` + `shaders/program/composite.fsh`（pass 体） | Steadfast 0.8.0（`program/post/noisy_godrays.fsh`） | **表达式级移植**（起步抖动换 Astra 自写 lib/bayer.glsl；`windowToScreenGodrays`/`screenLightVector` 两个 CPU uniform 改为 composite.vsh 顶点级投影，避免动 Z3 冻结的 uniform 集） | GPLv3 + §7 两条附加条款 | 文件头 GPL 声明 |
| `shaders/global/post/bloom.glsl` + `shaders/program/composite1.fsh`（pass 体） | Refrax v1.3.1（`lib/bloom.glsl` 的 bloomPrefilter 软阈值、`program/bloom_downsample.fsh.glsl` 的 13-tap 下采样） | **公式级移植**（Refrax 建 6 级图集再两级模糊；Astra 改为 mipmap 链 + 两 pass，多级合成权重与 additive 合成为 Astra 自定） | 专有（保留所有权利） | `// PROVENANCE: adapted from Refrax v1.3.1 (proprietary) - REWRITE REQUIRED before distribution` |
| `shaders/lib/settings.glsl` 的 ENGINE KNOBS 增补（entityShadowDistanceMul / shadowHardwareFiltering，SC-13） | Mellow v3.4（`lib/settings.glsl:268` 的 entityShadowDistanceMul 比例形式、`global/configurations.glsl:17` 的不带后缀 shadowHardwareFiltering） | 仅思路/形式参考（表达式为 Astra 写法：`ENTITY_SHADOW_DISTANCE * (1.0 / SHADOW_DISTANCE)` 规避整数除法） | MIT | 行内注释注明 |
| `shaders/program/composite.vsh` 的 lightScreenPos 投影 | 无参考（自写：gbufferProjection * vec4(lightVector, 0)，W=0 方向投影） | 自写 | — | `// written for Astra` |
| `shaders/global/lighting/diffuse.glsl` | Steadfast 0.8.0（`environment/lighting/diffuse.glsl`） | **表达式级移植**（Astra 改动：不复现 Steadfast 的 `SurfaceFragment` struct——GBuffer 解码归 E1；`lightVector`（视图空间、冻结集内）经 `lib/transforms.glsl view_player()` 重建世界向量；`NIGHT_DESATURATION_EFFECT` 不在 design.md 4.1 范围，已丢弃） | GPLv3 + §7 两条附加条款 | 文件头 GPL 派生声明（整段 derivative + GPL-3.0-or-later） |
| `shaders/global/lighting/sss.glsl` | Steadfast 0.8.0（`environment/lighting/diffuse.glsl` 的前向散射包裹项） | **表达式级移植** + Astra 增补强度控制（Steadfast 无 SSS 滑条：`sss_wrap()` 以 plain Lambert 到 Steadfast wrap 的 mix 表达，100 即逐字等价、0 即关闭；与 B1 `shadow_mapping()` 的除数归一化不得重复施加） | GPLv3 + §7 两条附加条款 | 文件头 GPL 派生声明 |
| `shaders/global/water/absorption.glsl` | 历史：SC-24 Solas `waterFog.glsl`、Steadfast 水体配置；当前为 Astra 方块距离 Beer-Lambert/单次散射重写 | Astra 自写传输公式及控制接线；2026-09-08 六图续修系数为 Astra 自定，历史参考保留 | 相关历史来源仍保留，非整包许可裁决 | 文件头列明历史参考与当前实现区别 |
| `shaders/global/water/caustics.glsl` | **Solas V2.2b（`lib/water/waterCaustics.glsl`，消费口径见 `program/shadow.glsl:52-54`）— SC-24 换源，2026-09-06 起不再是 Steadfast 派生** | **表达式级移植**（Solas 的双层漂移噪声高度场 + 五点差分交叉相乘 `max((xDeltaA·-xDeltaB + yDeltaA·-yDeltaB) * 48, 0)`；Solas 的四个 `WATER_NORMAL_*` 选项内联为局部常量（§3.3 选项数纪律）；水深门控/48–64 格连续淡出/footprint 连续抑制三项 Astra 包络不变） | Solas：未声明（默认版权） | 同上 |
| `shaders/global/water/refraction.glsl` | 历史：Solas V2.2b `program/composite4.glsl:91–111` 的 SC-24 屏幕偏移；SC-34-F1 已替换实际算法 | 当前为 Astra 自写的折射射线投影与深度平面迭代，颜色/水程采样由 program/water.glsl 负责；历史来源保留，不在本轮作整包许可放行 | 保留 Solas 历史来源说明 | `Historical provenance: From Solas V2.2b` |
| `shaders/global/water/particles.glsl` | 无参考（四包均无屏幕空间悬浮颗粒实现，检索命中的 particle 全为原版粒子 gbuffers 路径；观感对标 Solas 水下） | 自写（三层壳距 + 3D cell 整型 hash motes；hash 为公共域乘-移位模式，与 end.glsl 星野同构独立声明） | — | `// written for Astra (self-authored)` |
| `shaders/global/water/surface.glsl` | **Steadfast 0.8.0（`environment/water/surface_noise.glsl` + `surface_noise_waves.glsl` + `parallax.glsl` + `lib/valueNoise.glsl`/`valueNoiseDerivatives.glsl`）— SC-24 换源，2026-09-06 起由"自写解析波"改为 Steadfast 派生** | **表达式级移植**（ripple[4]+crest[2] 噪声波场、解析导数梯度、Nyquist 比率受限、4 步自适应视差；Astra 改动：两个噪声 lib 内联并加 `surface_` 前缀（与 Solas 出身的 caustics 同编译单元）；删 textureGather/FDM 回退分支；`WATER_AA` 四档固定 BALANCED；切线空间视线由 `worldPos - cameraPosition` 现算且 Z 取 -abs(y)；roughness = 被滤掉的坡度能量，为本包对 Steadfast 的增补） | GPLv3 + §7 两条附加条款 | 文件头 GPL 派生声明 |
| `shaders/global/dimension/nether.glsl` | Solas V2.2b（`lib/common.glsl` 的维度裁剪、其多云雾噪声塑形结构）+ Mellow v3.4（`lib/colors.glsl` 下界调色与 `global/lighting/lighting.glsl` 下界光照分支：思路与数值参考） | 结构借鉴（Solas 在 voxel/LPV 光线步进内评估 cloudy fog，本包无体积体，故改逐片元评估，只借噪声塑形结构；Mellow 侧无表达式移植）；`NetherParams` struct 形参与 `fogColor` 需求为 Astra 自定 | Solas：未声明 / Mellow：MIT | `// PROVENANCE: adapted from Solas V2.2b (licence undeclared) - REWRITE REQUIRED before distribution` |
| `shaders/global/dimension/end.glsl` | Mellow v3.4（`lib/colors.glsl:42,70,74,78,82` 调色数值；`global/atmosphere/sky.glsl:54-65,105-131` 星野与末地天空；`global/atmosphere/fog.glsl:37-50` 真空雾；`global/lighting/lighting.glsl:44-46,80-81,127` skylight 常量与阴影旁路）+ Solas V2.2b（`lib/atmosphere/skyEffects.glsl:6-27,48-91` 星野/星云结构）+ Refrax v1.3.1（`lib/atmosphere.glsl:174-209` 星野、`:390` 末地雾色、`:393-408` 末地天空） | 数值/思路参考（Mellow 调色与真空雾参数为其公开数值，表达式自写）；Solas 结构借鉴并降配（9 次查表降到 4 次、去掉螺旋域扭曲）；**Refrax 记为结构级**（雾色与天空地平线色同源、双正弦闪烁、立方面星野三项同源），Astra 侧已把星野重写为绕倾斜极旋转的 3D 晶格 + 天底立体投影、闪烁项改为权重与共轭相位形式，以脱离 Refrax 的表达式 | Mellow：MIT / Solas：未声明 / Refrax：专有 | `// PROVENANCE: rewritten for Astra - REWRITE REQUIRED before distribution`（Solas 条目下）+ 逐条 file:line 出处注释 |
| `shaders/global/post/grading.glsl` | Mellow v3.4（`program/final.fsh:56-76` 的 vibrance→saturation→contrast 链序与显示空间标定）+ Refrax v1.3.1（其 grade pass 的出厂数值区间与 film-look 思路） | 仅思路（链序沿用已移植的 `lib/tonemap.glsl` 中 Mellow 算子的调用次序；Refrax 侧明写 IDEA ONLY、无代码移植，并丢弃其内置 auto-warmth（§4.4 未要求））；四套预设参数为 Astra 自写出厂值，色调对标尚待用户目视确认 | Mellow：MIT / Refrax：专有 | 文件头两段 `PROVENANCE`（Refrax 段标 `IDEA ONLY, no code`） |

| `shaders/global/water/light_shafts.glsl` | Solas V2.2b `lib/atmosphere/volumetricLight.glsl`：视线阴影积分思路 | Astra 自写：按可见水程分段、共享入水日光/相函数/消光、编码及按实际深度重建；SC-34-F1 移除独立图案与额外增益 | 自写；所依赖阴影/变换模块仍按原许可 | `// Written for Astra (SC-33)` |

## Steadfast 借用复核（机械可验证）

SC-33 新增：`shaders/global/water/light_shafts.glsl` 为 Astra 自写；思路参考本地 Solas V2.2b `lib/atmosphere/volumetricLight.glsl` 与 `program/shadow.glsl` 的视线阴影累计和水面聚光。未移植 computeVL 表达式；固定分段积分、宽尺度图案、RGBA 编码和深度重建为独立实现。现有 `program/composite.fsh` 保留 Steadfast 空气光束消费者，并追加 Astra 水下消费者；所依赖的阴影和空间变换仍按上表各自来源登记。

- 复核命令：`python qa/tools/provenance_steadfast.py`（逐条比对 `Astra/shaders/shaders.properties`
  与 `_analysis/Steadfast-0.8.0/shaders/shaders.properties` 的 `uniform.*`/`variable.*` 定义；
  Steadfast 对同名保留多条历史定义，任一相同即计 verbatim）。
- 台账声明计数：`verbatim=14 literal-suffix=3 rewritten=7 astra-only=7`（合计 31 条；SC-32 改写光束四条表达式）——
  `check_pack.py` 第 8 项把这一行与脚本实算值比对，不一致即 FAIL。
- **verbatim（14）**：sunVector、lightVector、worldSunVector、skyVisibilityDay、borderFogDistance、
  renderDistanceFogTweak、windChaos、windTheta、LdotF、
  clipLightVector、godraysBaseExposure、godraysExposure、
  godraysDayExposureMorning（0.24）、godraysNightExposure（0.16）。
- **literal-suffix（3）**：sunProgress、sunrise、dayUnderwaterFogFade — 与 Steadfast 生效定义仅
  `2`→`2.0` / `4`→`4.0` 字面量后缀差异。
- **rewritten（7）**：moonrise（Steadfast 生效值为 `0.0`，Astra 写入实际曲线）、
  atmosphereFogCoefficient（去掉 Steadfast 的 noonFogProgress / fogInCaveAdjustment 两因子）、
  godraysDayExposureNoon（0.20 → 0.10）、godraysMaxAngle（60° 余弦为 0.5）、
  godraysViewAngleFade（夹取 0..1）、ndcLightVector（投影分母防零）、
  godraysOffscreenFade（夹取 0..1，防负曝光）。
- **astra-only（7）**：moonProgress、windStrength、biomeTemperatureSmooth、biomeHumiditySmooth、
  astraHeldLightBase、astraBlocklightSuppression、astraHeldLightSuppression（后 3 条为 E1 总成
  2026-09-06 新增，CPU 标量表达式自写）。
- 更正记录（2026-09-05）：本行原写"结构借鉴（表达式与分节模式，数值为 Astra 自定；
  worldSunVector 改锚定 sunPosition 而非 shadow light）"——两点均不成立：表达式为逐字复制，
  且 Steadfast 自己的 `worldSunVector` 已由 `sunVector`（= `sunPosition`/100）构造，与 Astra 逐字相同。

## 发布闸门提示（design.md §9.3）

- 上表中 Mellow 来源行（MIT）：公开发布仅须保留署名，无需重写。
- Steadfast 来源行（**表达式级移植**，17/31 条 custom uniform 表达式逐字或近似逐字；另有 11 个 GLSL 文件为 Steadfast 代码派生，见下条范围更正）：发布前两选一——
  (a) 把这 21 条重写为 Astra 自有表达式；(b) 整包按 GPLv3 发布并满足 §7b 署名句。
  若按"Steadfast 修改版"传播，§7c/7e 还要求人类可读名称与文件名以 `(edit of coderbot's Steadfast)`
  结尾——Astra 现名不满足，故该项已上报（见 escalations.md SC-14），不在本档自决。
  个人使用期（不分发）不受上述发布条款约束。
- **范围更正（2026-09-05，C 系列登记时实测；2026-09-06 SC-24 换源后更新）**：上面 (a) 只覆盖 `shaders.properties` 的 21 条表达式，不覆盖 GLSL 侧。`grep -rl "^// From Steadfast" shaders/` 现命中 **9 个文件**——`global/lighting/`（diffuse、sss、shadowmap、wind）、`global/atmosphere/fog.glsl`、`global/post/godrays.glsl`、`global/water/surface.glsl`（SC-24 换源新增）、`program/shadow.vsh`、`program/shadow.fsh`——它们与那 21 条同属 §7 条款的作用域。原 `global/water/` 的 absorption、caustics、refraction 三个文件经 SC-24 换源为 Solas 派生，2026-09-06 起移出本清单（11 → 9）。故 (a) 的真实工作量是「21 条表达式 + 9 个文件的表达重写」，(b) 则是整包转 GPLv3。SC-14 仍是 ⏸ 待用户拍板，本条只更正其影响面，不改候选与结论。
- Refrax/Solas 来源行：`global/post/bloom.glsl`（B5，2026-09-05）已从"仅思路"升级为**公式级移植**
  （软阈值 + 13-tap 下采样），文件头已带 `// PROVENANCE: adapted from Refrax v1.3.1 (proprietary)
  - REWRITE REQUIRED before distribution`，**发布前须重写**（思路保留、表达自写）；其余行仍为
  结构借鉴/仅思路级别。Solas 侧现为**六行**：三行结构借鉴（`program/shadow.fsh` 的染色思路、`global/dimension/nether.glsl` 的 cloudy-fog 噪声塑形、`global/dimension/end.glsl` 的星野与星云查表结构）+ **三行表达式级移植（SC-24，2026-09-06）**——`global/water/` 的 absorption（waterFog）、caustics（waterCaustics）、refraction（composite4 REFRACTION 段），三文件头均带 `// From Solas V2.2b` + `REWRITE REQUIRED` 标记；若再升级为逐行移植，同样须加标记并在此更新。
- C 系列（C1..C6）2026-09-05 新登记的 8 行已进上表：5 行为 Steadfast 代码派生（GPL 面扩大），3 行为 Solas/Mellow/Refrax 的结构与思路级借鉴。`check_pack.py` 第 8 项现为 PASS（台账行数与带出处头的文件双向对齐）。

## 2026-09-06 E1/E2 总成增量

| 模块 | 出处与变更 |
|---|---|
| program/lit.vsh、lit.fsh、scene.glsl、water.glsl、unlit.fsh、deferred.fsh、final.fsh | Astra自写组合逻辑；调用现有模块不改变其各自出处与许可。20对×3维度薄壳按E1表生成。 |
| global/water/surface.glsl | C7 SC-24 换源（2026-09-06）：Steadfast 噪声波场 + 解析导数 + 自适应视差，出处行见上表（GPL 派生，文件头带声明）。 |
| global/water/raytrace.glsl | SSR 基础设施，SC-24 明确不动；出处同原（屏幕射线，Khronos 语义参考）。 |
| global/atmosphere/sky_minishita.glsl、sky_gradient.glsl、stars.glsl、clouds_planar.glsl；global/dimension/overworld.glsl；program/sky.fsh、clouds.fsh | D2自写大气/星场/云与调用；Minishita使用固定2×1积分预算和公开散射公式。 |
| lib/tonemap.glsl | Z5执行E1线性输出契约修正；保留既有Mellow MIT出处。 |
| global/water/absorption.glsl、caustics.glsl、refraction.glsl、global/lighting/shadowmap.glsl、program/shadow.* | absorption/caustics/refraction 经 SC-24 换源为 **Solas 派生**（出处行见上表，2026-09-06）；shadowmap/shadow 为 Steadfast 派生，本次 C2/B1 修正深度单位、边界拒绝、足迹滤波、原点和摇曳同步，其原 Steadfast 派生说明继续适用。 |
| shaders.properties新增astraHeldLightBase/astraBlocklightSuppression/astraHeldLightSuppression | E1自写的CPU标量表达式，原28条借用分类不变；新增3条Astra独有，总计31条。 |

SC-14仍为未来发布的用户决策，不将本轮私人实例开发当作公开发布。

C5本轮仅根据本机Voxy 0.2.18-beta字节码确认空白配置跳过加载，voxy.json清空；未移植其代码或实现完整适配。

## SC-34-F1 来源与当前实现（2026-09-07）

本节及上表当前条目优先于 SC-24/33 历史实现描述。读取了本地三包：Steadfast 的 translucent/refraction/surface/lighting，Solas 的 gbuffers_water/composite4/waterFog/volumetricLight，Mellow 的 global/water 与 gbuffers_water/transformations。算法差异用于判断 Astra 接线，不移植参考包调色或增益。

| 模块 | 当前来源与变更 |
|---|---|
| `shaders/global/water/optics.glsl` | Astra 自写标准介电 Fresnel、Snell 入射光方向、归一化 HG 相函数；不是参考包表达式移植。 |
| `shaders/program/water.glsl` | 保留既有 Steadfast translucent 派生署名与 GPL/§7 说明；本轮重写物理界面、逐点颜色/深度传输、反射命中消费和折射天空重建。 |
| `shaders/global/water/raytrace.glsl` | Astra 自写 SSR；新增局部平面命中修正和几何约束，不复制参考包追踪器。 |
| `shaders/program/scene.glsl`、`shaders/global/water/light_shafts.glsl` | Astra 自写共享太阳源与分段积分；保留原 Solas 思路说明及依赖模块的来源。 |
| `shaders/global/lighting/diffuse.glsl`、`shaders/global/water/surface.glsl` | 保留 Steadfast 派生声明；分离 directRadiance、修正水面导数执行位置。 |
| `shaders/global/water/caustics.glsl`、`shaders/global/post/bloom.glsl` | 保留 Solas/Refrax 既有声明；焦散只作用于入水直射光，bloom 软阈值从既定阈值起算。 |

未改变既有私人实例开发范围；SC-14 不在本轮作发布决策。

## 2026-09-08 九图光路续修

重新对照本地 Mellow transformations、Steadfast shadow/translucent/absorption、Solas shadow/volumetricLight。lib/distort.glsl 的逆变换、shadow fragment 平面求交、阴影逐纹素照明合并、太阳源单位衔接和水面聚光场为 Astra 自写修改；原文件的 Mellow / Steadfast / Solas 历史出处与许可继续保留。

## 2026-09-08 最新六图退回后续修

`shaders/global/water/medium_state.glsl`、`shaders/program/water_state.fsh` 为 Astra 自写的界面高度编码与可见水面状态提取；`composite2.fsh/vsh` 为入口壳，`program/scattering.fsh` 承接原 composite 的散射实现及其已有依赖出处。太阳源、地形入水照明和焦散改为消费独立水体身份，遮挡仍读取 shadowtex1；未移植审查文档中的经验 glare 公式。吸收/散射参数仍是 Astra 自定，原 Steadfast/Solas/Mellow 衍生文件的许可声明保持。

## 2026-09-08 后续四图续修

依据本地 Iris/Sodium 顶点与矩阵输入纠正 shadow 坐标契约；保留 transforms 的 Mellow、shadow 的 Steadfast 出处。Astra 自写的界面透射谱与水下体积谱分离。`water_sun_focus` 是 Astra 的水面噪声聚光场，现同时供床面与光束使用；caustics.glsl 删除不再使用的 Solas 差分图案函数，保留其历史来源登记。原出处表中对旧差分图案的描述为历史记录，当前实现以本段为准。
