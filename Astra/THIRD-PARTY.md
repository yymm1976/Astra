# Astra — 第三方出处台账（THIRD-PARTY.md）

> 本地参考副本不随仓库提供。Steadfast 0.8.0 的获取位置、目录布局及替代路径参数见 [工具配置](../qa/tools/README.md#参考副本)。

依据 design.md §9.2 建立，**每新增一个来自参考包的文件/片段即登记**，保持台账与实际代码零偏差。
抽查方法：对表中每一行，打开对应文件核对文件头出处注释与内容来源。
Steadfast 借用行例外——其分类计数由 `python qa/tools/provenance_steadfast.py --quiet` 实算，
`python qa/tools/check_pack.py` 第 8 项把本文件出现的每一处计数与实算值比对，不一致即 FAIL。

参考包许可事实（design.md §9.1）：

| 包 | 版本 | 许可 | 借用政策（个人使用期） |
|---|---|---|---|
| Mellow | v3.4 | 根许可证 MIT（`Copyright (c) 2026 TheCMK`）**但包内逐文件中继第三方声明** | 自由，保留出处注释——注释必须是**该文件里实际声明的那个持有人**，不是包根持有人。2026-09-21 T16 实测：`lib/tonemap_operators.glsl:80-84` 内嵌 glsl-tone-map 的 MIT 原文（`Copyright (C) 2019 Damien Seguin`），同文件 `:23` 一行 URL 注释把 ACES 两矩阵与 `RRTAndODTFit`/`ACES_slow` 指向 **TheRealMJP/BakingLab**（该仓库 `LICENSE` = MIT / `Copyright (c) 2016 MJP`，`ACES.hlsl` 头部另把 fit 署名给 Stephen Hill `@self_shadow`），同文件 `:228-232` 把 `PBRNeutralToneMapping` 标为 **Apache-2.0 / Copyright (c) 2024 The Khronos Group**（根目录另附 `LICENSE-APACHE`），`global/post/cas.glsl:1-7` 是 AMD 自己的 MIT 头。详见下文 2026-09-21 T16 节 |
| Steadfast | 0.8.0 | GPLv3 + 两条 §7 附加条款（作者 coderbot） | 自由；文件头保留 GPL 声明。**7b**：任何传播 Steadfast 或其修改版的页面须在主文靠前处原样给出署名句（含 Modrinth/CurseForge/GitHub 三个下载源）。**7c/7e**：传播修改版时，人类可读名称与文件名必须以 `(edit of coderbot's Steadfast)` 结尾（文件名可用后缀 `-edit-of-coderbot-Steadfast`），且 "Steadfast" 不得出现在该括号之外的名称里 |
| Complementary | r5.9（Reimagined / Unbound，2026-09-02） | **Complementary License Agreement 1.7**（专有，非 GPL；`License.txt` 随包，1.2/1.3 节允许 modpack 收录与 Modified Pack 再分发但有条件） | 个人使用期自由；**发布前须按 design.md §9.3 / SC-14 重做发布门决策**。已在 `global/lighting/wind.glsl`、`global/lighting/sss.glsl`（树叶分支）、`global/atmosphere/{sky_gradient,stars,clouds_planar}.glsl`、`global/dimension/end.glsl`（方向门控）、`global/dimension/nether.glsl`（下界光照逐字移植）落地。登记日 2026-09-10 |
| Refrax | v1.3.1 | 保留所有权利 | 允许借鉴；结构级照抄须逐处登记 |
| Solas | V2.2b | 未声明（默认版权） | 同上 |

## 登记表

| 模块路径 | 来源包（源文件） | 借用类型 | 许可 | 文件头标记 |
|---|---|---|---|---|
| `shaders/lib/tonemap.glsl` | **逐算子持有人（2026-09-21 T16 两次更正，原记"整文件 = Mellow (MIT) by TheCMK"不成立）**：**(1)** `uchimura_tonemap_full`/`uchimura_tonemap`/`agx_cdl`/`agx_punchy`/`agx_tonemap` 及其四张 AgX 矩阵 = 上游 **glsl-tone-map**（`Copyright (C) 2019 Damien Seguin`，MIT）逐字代码，经 Mellow v3.4 `lib/tonemap_operators.glsl:103-226` 中继（Mellow 在该文件 `:80-84` 原样保留 Seguin 的 MIT 声明，Astra 移植时丢掉了它——本轮已补）；**(2)** `aces_tonemap`/`rrt_and_odt_fit`/`aces_input_mat`/`aces_output_mat` = 上游 **BakingLab**（`TheRealMJP/BakingLab` 的 `BakingLab/ACES.hlsl`，仓库 `LICENSE` = MIT / `Copyright (c) 2016 MJP`，该文件头部另把此 fit 署名给 Stephen Hill `@self_shadow`），经 Mellow `lib/tonemap_operators.glsl:23-60` 中继——Mellow 在该处只留了一行 URL 注释而没登记持有人，Astra 保留了同一行注释也没登记，本轮已补；**(3)** 仅 `reinhard_jodie` 与 `apply_saturation/apply_vibrance/apply_contrast` 的持有人是 TheCMK：Mellow `lib/tonemap_operators.glsl:1-21`（`ACESFilm` 与 `reinhard_jodie`）与 `lib/tonemap.glsl`（grading 三函数在 `:21-37`）实测**不含任何** http / 版权 / 许可注释。`reinhard_jodie` 的算法本身公开（`https://64.github.io/tonemapping/`），Mellow 与 Astra 用的是 `get_luminance(v)` 变体，glsl-tone-map 那份 `reinhardJodie.glsl` 用 `const vec3 lw` + `dot`，两者不同源。Mellow 第 1 个算子 `ACESFilm`、第 5 个 `PBRNeutralToneMapping`（Khronos，Apache-2.0）与 `Lottes` **均未移植**，故本包不触发 Apache 条款 | 逐行移植（重命名为 snake_case；仅保留设计 §4.4 四算子）。机械复测：`python qa/tools/verify_tonemap_chain.py`——去空白与行注释后按上游函数名逐字符比对，七个函数里六个逐字相同（uchimura 7 参 317 字符、uchimura 1 参 130、agxPunchy 57、agx 56、`rrt_and_odt_fit` 86、`aces_tonemap` 114，后两者在 HLSL→GLSL 机械翻译（`float3`→`vec3`、去 `f` 后缀、`mul(M,v)`→`M * v`、`saturate`→`clamp(…, 0, 1)`）之后与 BakingLab 原件逐字符相同），`agx_cdl` = 上游 612 字符 + Astra 自加的一处 `max(color * slope + offset, vec3(0.0))` 保护（分数次幂遇到负底数在 GLSL 里无定义，Mellow 与上游都没有这一处）；四张 AgX 矩阵 36 个值和两个 EV 常量、两张 ACES 矩阵 2×9 个值与上游逐值相同（HLSL 按行写、GLSL `mat3()` 按列写，实测为同一线性映射）；同脚本另测 Mellow 侧六个函数与两张 ACES 矩阵均等于上游（中继未改写），唯一例外是 Mellow 的派发包装 `ACES_slow` 比 `ACESFitted` 多进出各一道 gamma（`pow(color, vec3(1/2.2))` 与 `to_linear(color)`），Astra 未继承该包装、直接对应 BakingLab 原件。两份上游原件随包在 `shaders/lib/vendor/glsl-tone-map/` 与 `shaders/lib/vendor/bakinglab/`。 | MIT（三个持有人：Damien Seguin 2019 段 + MJP 2016 段 + TheCMK 段） | 文件头 `// Immediate source: Mellow v3.4 by TheCMK (MIT)` + `Copyright (C) 2019 Damien Seguin, MIT` 与 `Copyright (c) 2016 MJP, MIT` 两段短注，分别指向 `lib/vendor/glsl-tone-map/LICENSE.md` 与 `lib/vendor/bakinglab/LICENSE.txt`（许可正文只在 vendor 目录一份，见 `shaders/lib/vendor/README.md` 反规范条） |
| `shaders/lib/encoding.glsl` | Mellow v3.4（`lib/util.glsl` 的 encodeUnitVector/decodeUnitVector/get_luminance、`lib/transformations.glsl` 的 to_linear） | 逐行移植（重命名）+ Astra 增补（srgb_encode/srgb_decode 为 IEC 标准式；pack_octahedral/unpack_octahedral/pack_u16 自写封装） | MIT | 文件头 `// From Mellow v3.4 (MIT) by TheCMK`。2026-09-21 T16 逐文件复核：所引的 `lib/util.glsl` 与 `lib/transformations.glsl` 内部**没有**任何第三方中继声明，持有人即 TheCMK，与被中继的 `lib/tonemap_operators.glsl` 不同 |
| `shaders/lib/transforms.glsl` | Mellow v3.4（`lib/transformations.glsl`） | 逐行移植（删除 DH 分支；Voxy 矩阵分支改由入口专属 ASTRA_VOXY_PASS 控制，SC-32） | MIT | 文件头 `// From Mellow v3.4 (MIT) by TheCMK`。2026-09-21 T16 逐文件复核：本行所引的 Mellow 源文件（`lib/transformations.glsl`）内部**没有**任何第三方中继声明，持有人即 TheCMK，与被中继的 `lib/tonemap_operators.glsl` 不同 |
| `shaders/lib/pow.glsl` | 思路参考：Complementary r5.9 / Photon v1.3b / Refrax v1.3.1 / rethinking-voxels 的整数幂平方链助手（见文件头清单） | 仅思路（全部函数 Astra 自写并经 Python 逐点对拍） | 各参考包许可不动本文件；本文件随 Astra 主许可 | 文件头列明四家出处 |
| `shaders/global/lighting/blocklight.glsl` | Steadfast 0.8.0 diffuse.glsl 的手持光、方块光；Refrax v1.3.1 thunder.glsl 的闪电点光 | 表达式移植 / 改编，双来源 | 各段沿用来源许可，Refrax 段保留发布前重写标记 | 文件头列出两段来源及 REWRITE REQUIRED |
| `shaders/lib/colors.glsl` | Steadfast 0.8.0 shaders.properties 的方块光、最小环境光颜色；Refrax v1.3.1 thunder.glsl 的闪电色 | 双来源常量移植 | 各段沿用来源许可，Refrax 段保留发布前重写标记 | 文件头列出两段来源及 REWRITE REQUIRED |
| `shaders/lib/distort.glsl` | Steadfast 0.8.0（`lib/distort.glsl`，作者 coderbot） | 径向扭曲与 Z 缩放表达式移植；Astra 增补解析逆变换。2026-09-09 与 shadow_map_position 成套替换原 Mellow 方形扭曲，删除无调用的 compute_bias。**2026-09-20 改常数为按影距归一**：Steadfast 的裸 `0.20` 是其 160 格影距下的调参产物（核半径 = 因子 × 影距 = 32 格），Astra 出厂 256 格沿用会把高解析核推到 51.2 格、近场密度减半；现改为 `SHADOW_DISTORT_CORE = 25.6`（格）`/ float(SHADOW_DISTANCE)`，近场纹素密度与影距解耦，滑条只改变覆盖距离，代价是短影距下外圈空转面积增大（D=64 时 49.0%，D=256 时 17.4%，`shadowDistanceRenderMul = 1.5` 在上游侧部分利用该外圈）。为此新增本文件对 `lib/settings.glsl` 的显式 include——这是包内第一处 lib→settings 直接包含（其余 22 处全在 `shaders/program/` 入口，靠包含顺序拿到选项），settings.glsl 自带包含守卫，入口已包含时本行不重复展开，作用是让常量初始化式不隐式依赖包含顺序 | GPLv3 + §7 两条附加条款 | 文件头 GPL 来源说明 |
| `shaders/lib/dither.glsl` | Mellow v3.4（`lib/noise.glsl` 的 ign/dither） | 逐行移植（Astra 无 TAA，dither 固定为静态 IGN） | MIT | 文件头 `// From Mellow v3.4 (MIT) by TheCMK`。2026-09-21 T16 逐文件复核：本行所引的 Mellow 源文件（`lib/noise.glsl`）内部**没有**任何第三方中继声明，持有人即 TheCMK，与被中继的 `lib/tonemap_operators.glsl` 不同 |
| `shaders/lib/bayer.glsl` | 无参考（自写：教科书式 Bayer 递归构造，公共域模式） | 自写 | — | `// written for Astra` |
| `shaders/shaders.properties` 的 `CUSTOM UNIFORMS` 段 | Steadfast 0.8.0（coderbot）；其中 9 条 `astraSolas*` 改写自 Solas V2.2b 时间/日相表达式 | 表达式级移植；当前 57 条（32 `uniform.*` + 25 `variable.*`）：verbatim=14 literal-suffix=2 rewritten=6 astra-only=35。2026-09-25 将天空和云的逐帧颜色公式移至 CPU，新增 5 个 uniform 和 3 个中间变量；分类方法与名称见下节 | Steadfast 部分：GPLv3 + §7 两条附加条款；Solas 部分沿用其来源登记 | 段内保留 Steadfast 表达式级移植说明；astra-only 仅表示 Steadfast 无同名定义，不代表没有其他来源 |
| `shaders/block.properties` 基础表（10001–10007、10021–10027） | Mellow v3.4（`block.properties` 现代分支） | 逐行移植（数据表；删除 floodfill 10020） | MIT | 文件头注明 |
| `shaders/block.properties` Astra 补全区（10010、10011，以及并入 10002/10004/10022/10025/10026/10027 的原版补漏 ID） | 无参考（自组：原版 1.21.x 事实 ID 数据） | 自写（2026-09-05 修正：block.properties 无 `+=` 追加运算符，原 6 条 `block.N+=` 行会整行替换基础表，已并入对应基础行） | — | 文件头注明 |
| `shaders/entity.properties` | Refrax v1.3.1 / Solas V2.2b 的 `entity.properties`（仅分类思路） | 结构借鉴（分组方案自组，ID 内容为原版事实数据） | Refrax：专有 / Solas：未声明 | 文件头注明 |
| `shaders/global/lighting/shadowmap.glsl` | Steadfast 0.8.0（`environment/lighting/shadowmap.glsl` 的 ShadowMapping/SampleShadows/静态回退、`program/world/lit.vsh` 的 ShadowMapPosition、`program/shadow/shadow.vsh` 的水面高度编码） | **表达式级移植**（snake_case 重命名；shadowMapResolution/shadowDistance/entityShadowDistanceMul/shadowHardwareFiltering 上移到 lib/settings.glsl 不在此重复；彩色阴影组合与焦散接口为 Astra 增补）。**2026-09-20 两处偏置与畸变常数解耦**：掠射项原借用 `SHADOW_DISTORT_FACTOR`（当时恰为 0.20 格），该常数已改为按影距归一后不再代表格数，故改用文件内 `shadowGrazingBias = 0.20`（出厂默认数值不变）；末地分支的固定 `+0.015` 格并入单一纹素倍率 `0.46`（= 原 0.30 加 0.015 格在 2048 档下的纹素数），使该项整体随 SHADOW_RESOLUTION 缩放而非部分冻结 | GPLv3 + §7 两条附加条款 | 文件头 GPL 声明 |
| `shaders/program/shadow.vsh` | Steadfast 0.8.0（`program/shadow/shadow.vsh`） | **表达式级移植**（block.properties 原始 ID 判据替代其 materialID 解码；玻璃剔除坐标由 `vec4(-1.0)` 修正为 `vec4(0,0,2,1)`——原写法落在远平面角上，裁剪不可靠） | GPLv3 + §7 两条附加条款 | 文件头 GPL 声明 |
| `shaders/program/shadow.fsh` | Steadfast 0.8.0（`program/shadow/shadow.fsh`）+ Solas V2.2b（`program/shadow.glsl` 的半透明染色混合思路） | **表达式级移植**（Steadfast 壳）+ 结构借鉴（Solas 染色公式）；`smoothstep(1.0, 0.9, a)` 透明度判定与 srgb_decode 为 Astra 组合 | Steadfast：GPLv3 + §7 / Solas：未声明 | 文件头 GPL 声明（Steadfast 部分） |
| `shaders/global/atmosphere/fog.glsl` | Steadfast 0.8.0（`environment/fog.glsl` 的 FogV2） | **表达式级移植**（雾色改为参数而非 custom uniform——Astra 的 Z3 uniform 集冻结于 SC-14，雾色归 D2/C1；FOG_DENSITY/UNDERWATER_FOG_DENSITY/SKY_FOG_STRENGTH 在此接入；空气透视与 biome tint 为 Astra 自实现，Refrax 仅思路） | GPLv3 + §7 两条附加条款 | 文件头 GPL 声明 |
| `shaders/global/lighting/wind.glsl` | **2026-09-10 换源：Complementary r5.9（`lib/materials/materialMethods/wavingBlocks.glsl` 的 GetRawWave:5-16 / GetWave:18-33 / DoWave_Leaves:52-67 / DoWave_Foliage:35-50）** — 换源前为 Steadfast 0.8.0（`environment/wind.glsl` 的 WindDisplacement + `program/world/lit.vsh` 的 WaveFoliage），现仅保留历史出处行，无 Steadfast 表达式残留 | **表达式级移植 / 形状级逐字**（两条波形、共享的 GetRawWave 与振幅链逐字照抄；材质无关化沿用 Astra 接线：materialID 判据改为调用方布尔参数；WAVING_FOLIAGE_STRENGTH 映射参考 WAVING_I、雨增益保留 Astra 自有 Steadfast 期响应） | **Complementary License 1.7（专有）** — 本文件已无 Steadfast 派生表达式，故不再适用 GPL 条款；文件头以「Historical provenance」段说明换源前后的关系 | 文件头含 Complementary r5.9 逐处 file:line 出处、`Historical provenance` 段与发布门提示 |
| `shaders/global/post/godrays.glsl` + `shaders/program/composite.fsh`（pass 体） | Steadfast 0.8.0（`program/post/noisy_godrays.fsh`） | **表达式级移植**（起步抖动换 Astra 自写 lib/bayer.glsl；`windowToScreenGodrays`/`screenLightVector` 两个 CPU uniform 改为 composite.vsh 顶点级投影，避免动 Z3 冻结的 uniform 集） | GPLv3 + §7 两条附加条款 | 文件头 GPL 声明 |
| `shaders/global/post/bloom.glsl` + `shaders/program/composite1.fsh`（pass 体） | Refrax v1.3.1（`lib/bloom.glsl` 的 bloomPrefilter 软阈值、`program/bloom_downsample.fsh.glsl` 的 13-tap 下采样） | **公式级移植**（Refrax 建 6 级图集再两级模糊；Astra 改为 mipmap 链 + 两 pass，多级合成权重与 additive 合成为 Astra 自定） | 专有（保留所有权利） | `// PROVENANCE: adapted from Refrax v1.3.1 (proprietary) - REWRITE REQUIRED before distribution` |
| `shaders/program/scattering.fsh` 的 `godrays_sun_visibility()` 与 `shaders/program/final.fsh` 的读回 | LIGHT Shaders 1.8.0（Chocapic13' 谱系）。思路出处按 2026-09-20 调研记录（§2.11、§6 P1-6）：`composite.fsh:423-433` 角落像素的日面深度遮挡探测 → `:582` 写入 alpha 广播 → `final.fsh:329` 读回乘到光束强度上。**这三处 file:line 抄自该调研，本轮未在本地重验**（原包目录已清理，`_analysis/study-2026-09-20/` 现仅剩 ComplementaryUnbound_r5.9.3）；本轮结论只依赖「有这种架构」这一条，不依赖具体行号 | **仅思路（IDEA ONLY）**：只取「一个像素做日面窗口探测 + 用 alpha 广播给后续 pass」这一架构。全部具体决定为 Astra 自写：7×7 抽、±12 像素半窗、深度源取 **depthtex1**（只用不透明深度，玻璃与水面不得误杀光束）、越界抽点不计入分母（与在窗抽点归一，而非按 0 计）、无在窗抽点时失败开放返回 1.0、载体复用 `colortex1` 的 texel (0,0) alpha（不新增缓冲、不新增 pass）、消费点为阶段 2 的一次 `texelFetch`。选项 `GODRAYS_SUN_OCCLUSION` 默认关闭，待实机 A/B | Chocapic13 Sharing Agreement（只读思路，不得照搬表达式） | 函数头注释 `Idea from Chocapic13' LIGHT (Sharing Agreement)` |
| `shaders/lib/settings.glsl` 的 ENGINE KNOBS 增补（entityShadowDistanceMul / shadowHardwareFiltering，SC-13） | Mellow v3.4（`lib/settings.glsl:268` 的 entityShadowDistanceMul 比例形式、`global/configurations.glsl:17` 的不带后缀 shadowHardwareFiltering） | 仅思路/形式参考（表达式为 Astra 写法；2026-09-20 起为 8×5 字面量表 `ENTITY/(SHADOW×1.5)`，见 lib/settings.glsl:230-326，规避 Iris 的算术解析限制） | MIT | 行内注释注明 |
| `shaders/program/composite.vsh` 的 lightScreenPos 投影 | 无参考（自写：gbufferProjection * vec4(lightVector, 0)，W=0 方向投影） | 自写 | — | `// written for Astra` |
| `shaders/global/lighting/diffuse.glsl` | Steadfast 0.8.0（`environment/lighting/diffuse.glsl`） | **表达式级移植**（Astra 改动：不复现 Steadfast 的 `SurfaceFragment` struct——GBuffer 解码归 E1；`lightVector`（视图空间、冻结集内）经 `lib/transforms.glsl view_player()` 重建世界向量；`NIGHT_DESATURATION_EFFECT` 不在 design.md 4.1 范围，已丢弃） | GPLv3 + §7 两条附加条款 | 文件头 GPL 派生声明（整段 derivative + GPL-3.0-or-later） |
| `shaders/global/lighting/sss.glsl` | **双来源（2026-09-10 起）**：树叶分支 = Complementary r5.9（`lib/lighting/mainLighting.glsl:111-113` 的 `NdotL = mix(NdotL, 1.0, 0.35)`，subsurfaceMode == 2，`:118` max0 自clamp）；地面植被分支与强度混合 = Steadfast 0.8.0（`environment/lighting/diffuse.glsl` 的前向散射包裹项） | **表达式级移植** + Astra 增补强度控制（Steadfast 无 SSS 滑条：`sss_wrap()` 以 plain Lambert 到全强度 wrap 的 mix 表达，100 即逐字等价、0 即关闭；与 B1 `shadow_mapping()` 的除数归一化不得重复施加。参考的平坦直射 NdotLM=1.0、前向高光与影缘天光混合三项需扩 diffuse.glsl 接口，见 docs/handoffs/terrain-foliage.md 待办 3） | 树叶分支：**Complementary License 1.7（专有）**；地面分支：GPLv3 + §7 两条附加条款 | 文件头双来源声明（含 Steadfast GPL 派生段） |
| `shaders/global/water/absorption.glsl` | 历史参考 Solas waterFog 与 Steadfast 吸收预设；当前距离输运与光谱参数由 Astra 编写 | 当前实现自写，历史改编记录保留 | 既有来源记录不变 | 文件头 Historical references 与 written for Astra |
| `shaders/global/water/caustics.glsl` | Solas V2.2b waterCaustics.glsl 的噪声高度场；Astra 解析波焦散 | 水面高度场改编自 Solas；当前聚焦场为独立解析实现 | Solas 部分沿用来源登记 | 文件头 Adapted from Solas，并区分可见水面与解析焦散 |
| `shaders/global/water/refraction.glsl` | Steadfast 0.8.0 environment/water/refraction.glsl，coderbot | 改编 | GPL-3.0-or-later 与 §7 附加条款 | 文件头 Adapted from Steadfast |
| `shaders/global/water/particles.glsl` | 无参考（四包均无屏幕空间悬浮颗粒实现，检索命中的 particle 全为原版粒子 gbuffers 路径；观感对标 Solas 水下） | 自写（三层壳距 + 3D cell 整型 hash motes；hash 为公共域乘-移位模式，与 end.glsl 星野同构独立声明） | — | `// written for Astra (self-authored)` |
| `shaders/global/water/surface.glsl` | **Steadfast 0.8.0（`environment/water/surface_noise.glsl` + `surface_noise_waves.glsl` + `parallax.glsl` + `lib/valueNoise.glsl`/`valueNoiseDerivatives.glsl`）— SC-24 换源，2026-09-06 起由"自写解析波"改为 Steadfast 派生** | **表达式级移植**（ripple[4]+crest[2] 噪声波场、解析导数梯度、Nyquist 比率受限、4 步自适应视差；Astra 改动：两个噪声 lib 内联并加 `surface_` 前缀（与 Solas 出身的 caustics 同编译单元）；删 textureGather/FDM 回退分支；`WATER_AA` 四档固定 BALANCED；切线空间视线由 `worldPos - cameraPosition` 现算且 Z 取 -abs(y)；roughness = 被滤掉的坡度能量，为本包对 Steadfast 的增补） | GPLv3 + §7 两条附加条款 | 文件头 GPL 派生声明 |
| `shaders/global/dimension/nether.glsl` | Solas V2.2b（`lib/common.glsl` 的维度裁剪、其多云雾噪声塑形结构）+ Mellow v3.4（`lib/colors.glsl` 下界调色与 `global/lighting/lighting.glsl` 下界光照分支：思路与数值参考）+ **Complementary r5.9（2026-09-10 新增：`lib/lighting/mainLighting.glsl:506-519` 下界方向项与熔岩项、`:613-616` 平方和开方合成、`lib/colors/lightAndAmbientColors.glsl:80-81` 下界 ambient、`lib/lighting/minimumLighting.glsl:1-17` 暗部下限、`lib/common.glsl:811` netherColor 模式 2、`:815` lavaLightColor）** | 结构借鉴（Solas 在 voxel/LPV 光线步进内评估 cloudy fog，本包无体积体，故改逐片元评估，只借噪声塑形结构；Mellow 侧无表达式移植）；`NetherParams` struct 形参与 `fogColor` 需求为 Astra 自定；**2026-09-10 新增 Complementary 表达式级移植**（下界光照整段逐字照抄，含 `directionShade` 的二次平方；`vsBrightness` 因缺 uniform 以常量 0.5 顶替、`vanillaAO` 取 1.0，两项偏离已上报） | Solas：未声明 / Mellow：MIT / **Complementary：专有（License 1.7）** | `// PROVENANCE: adapted from Solas V2.2b (licence undeclared) - REWRITE REQUIRED before distribution` + Complementary 逐处 file:line 出处 |
| `shaders/global/dimension/end.glsl` | Mellow v3.4（`lib/colors.glsl:42,70,74,78,82` 调色数值；`global/atmosphere/sky.glsl:54-65,105-131` 星野与末地天空；`global/atmosphere/fog.glsl:37-50` 真空雾；`global/lighting/lighting.glsl:44-46,80-81,127` skylight 常量与阴影旁路）+ Solas V2.2b（`lib/atmosphere/skyEffects.glsl:6-27,48-91` 星野/星云结构）+ Refrax v1.3.1（`lib/atmosphere.glsl:174-209` 星野、`:390` 末地雾色、`:393-408` 末地天空）+ **Complementary r5.9（2026-09-10 新增：`lib/lighting/mainLighting.glsl:507-512` 末地方向门控、`:613` 的 `pow2(directionShade)` 门控、`lib/lighting/minimumLighting.glsl:2` 的 `#if !defined END` 暗部下限排除、`program/deferred1.glsl:386` 的 `1.0 - maxBlindnessDarkness` 天空压暗）** | 数值/思路参考（Mellow 调色与真空雾参数为其公开数值，表达式自写）；Solas 结构借鉴并降配（9 次查表降到 4 次、去掉螺旋域扭曲）；**Refrax 记为结构级**（雾色与天空地平线色同源、双正弦闪烁、立方面星野三项同源），Astra 侧已把星野重写为绕倾斜极旋转的 3D 晶格 + 天底立体投影、闪烁项改为权重与共轭相位形式，以脱离 Refrax 的表达式；**2026-09-10 新增 Complementary 表达式级移植**（方向门控与暗部下限为逐字移植，`sqrt` 折块光未移植、AO 通道缺失已上报） | Mellow：MIT / Solas：未声明 / Refrax：专有 / **Complementary：专有（License 1.7）** | `// PROVENANCE: rewritten for Astra - REWRITE REQUIRED before distribution`（Solas 条目下）+ Complementary 段 `REWRITE REQUIRED`（1.7 许可）+ 逐条 file:line 出处注释 |
| `shaders/global/post/grading.glsl` | Mellow v3.4（`program/final.fsh:56-76` 的 vibrance→saturation→contrast 链序与显示空间标定）+ Refrax v1.3.1（其 grade pass 的出厂数值区间与 film-look 思路） | 仅思路（链序沿用已移植的 `lib/tonemap.glsl` 中 Mellow 算子的调用次序；Refrax 侧明写 IDEA ONLY、无代码移植，并丢弃其内置 auto-warmth（§4.4 未要求））；四套预设参数为 Astra 自写出厂值，色调对标尚待用户目视确认 | Mellow：MIT / Refrax：专有 | 文件头两段 `PROVENANCE`（Refrax 段标 `IDEA ONLY, no code`） |

| `shaders/global/water/light_shafts.glsl` | Solas V2.2b volumetricLight.glsl 与 composite3/5，Septonious | 改编；Astra 使用受限步进与按距离重建，历史 IterationT 实现已被替换 | Solas 部分沿用来源登记 | 文件头 Adapted from Solas |
| `shaders/program/scene.glsl`（2026-09-21 T14 新增 `CLOUD_SHADOWS` 地面云影臂） | BSL（`lib/lighting/shadows.glsl:295-374` 的 `GetCloudShadow()`：2D 云噪声沿光向投到地面，`:325` 的 `CLOUD_REVEAL` 再打孔洞透射）+ Complementary r5.9 Reimagined（`lib/lighting/cloudShadows.glsl:60` 的 `cloudSample *= sqrt3(1.0 - abs(EdotL))` 地平线衰减） | **仅思路、零表达式移植**：Astra 侧全部复用既有自有件——被追迹的密度场是 `global/atmosphere/weather.glsl:122-136` 的 `astra_cloud_transmission`（本包自写单平面追迹，每片元 2 次 `textureLod`），遮蔽门是 `global/lighting/shadowmap.glsl:239-241` 的 `static_shadow`，权重 0.75 与 `smoothstep(0.0, 0.2, cloudLightDir.y)` 衰减为 Astra 自写；BSL 的 `CLOUD_REVEAL` 透射与其噪声选择、Reimagined 的 `gaux4` 云阴影回读均未实现也未复制 | BSL：All Rights Reserved / Complementary：License 1.7（两者均专有）——本轮为思路级、无上游代码或公式进入本包，故条款不触发；若日后升级为表达式移植须走 `shaders/lib/vendor/` 流程 | 消费点行内 `PROVENANCE ... IDEA ONLY, no code and no formula transplanted`（格式同 `global/post/grading.glsl:234`） |
| `shaders/global/post/exposure.glsl`（2026-09-21 T15 新增 `AUTO_EXPOSURE`） | Refrax v1.3.1：`program/exposure.fsh.glsl:27-55` 的屏幕空间自动曝光结构（5×5 网格 + 高斯权重 + `log2` 几何均值 + `clamp(KEY/avgLum, MIN, MAX)` + texel 历史 + 变暗/变亮不对称速率）、`lib/post.glsl:9-18` 的 `sceneExposure()` 消费与下界/末地旁路（消费点 `program/grade.fsh.glsl:161-163`）、`lib/settings.glsl:91-98` 的常量形态 | **仅思路、零表达式移植**：Astra 侧全部自写——8×8 跨步 `texelFetch` 网格（弃 Refrax 的 `texture()` + `fract(uv*64.0)` 抖动：1 像素视口内导数无定义）、`exp(-abs(d)²·2.1)` 角点权重 0.35、逐抽 `AE_CLIP=4.0` 高光截断（Photon 建议的性质一）、有效性改用 `.a` 位（Refrax 的 `prev<=0.0` 会把触底增益误判为无历史）、混合在 `log2` 域做（线性域会让"变亮"永远滞后于"变暗"）、一个量化码的死区吸附防 8-bit 历史抖动、水下冻结历史、常量全部为 Astra 自定（KEY 0.18 / MIN 0.60 / MAX 2.20 / FAST 2.5 / SLOW 0.5，均给出推导而非照抄 0.22/0.70/2.60/2.20/0.90）、载体为 `size.buffer.colortex10=1 1`（非 Refrax 的 `EXPOSURE_REGION`） | Refrax：专有（保留所有权利，允许借鉴；结构级照抄须逐处登记）——本轮为思路级、无上游代码或公式进入本包 | 文件头 `PROVENANCE ... IDEA ONLY, no code and no formula transplanted`（形态同 `global/post/grading.glsl`） |

## 第三方隔离目录 `shaders/lib/vendor/`

依据 design.md §9.2 与借鉴调研 P2-10 建立，规则正文在 `shaders/lib/vendor/README.md`。约定：

- 第三方原始文件与许可证原文只允许出现在 `shaders/lib/vendor/<upstream>/`，一个上游一个目录。
- 该目录下**除目录自带 README.md 外**的每个文件——许可证原文、上游原件、编译进包的上游模块——
  都要在本文件按它自己的全路径登记一行；目录本身由 `shaders/lib/vendor/<upstream>/` 一行覆盖。
- 每个上游目录必须带许可证原文；许可证正文只存这一份，包内其他文件出现 MIT/BSD/GPL 正文段落即 FAIL
  ——参照包同一个错误的代价：VanillaPlus 224 份文件头 = 4,384 行 / 38.5%，Sildur's 8.2%，LIGHT 11.3%。
- 本文件上方登记表登记的仍是**实际参与编译的 Astra 文件**；vendor 目录里的原件不重复登记为模块行。
- 机械检查：`python qa/tools/check_pack.py` 第 15 项。

## Steadfast 借用复核（机械可验证）

水下光束当前来源以登记表和文件头为准：现实现改编自 Solas V2.2b，SC-33 自写版本与后来的 IterationT 版本均为历史实现，不再描述当前文件。

- 复核命令：`python qa/tools/provenance_steadfast.py`（逐条比对 `Astra/shaders/shaders.properties`
  与 `_analysis/Steadfast-0.8.0/shaders/shaders.properties` 的 `uniform.*`/`variable.*` 定义；
  Steadfast 对同名保留多条历史定义，任一相同即计 verbatim）。
- 台账声明计数：`verbatim=14 literal-suffix=2 rewritten=6 astra-only=35`，合计 **57** 个名称，32 个 `uniform.*` 与 25 个 `variable.*`，无同名重复。`astra-only` 仅指 Steadfast 无同名定义；其他来源仍按文件和表达式登记。
- **verbatim（14）**：sunVector、lightVector、worldSunVector、skyVisibilityDay、borderFogDistance、
  renderDistanceFogTweak、windChaos、windTheta、LdotF、clipLightVector、
  godraysBaseExposure、godraysExposure、godraysDayExposureMorning（0.24）、
  godraysNightExposure（0.16）。
- **literal-suffix（2）**：sunProgress、dayUnderwaterFogFade — 与 Steadfast 生效定义仅
  `2`→`2.0` / `4`→`4.0` 字面量后缀差异。
- **rewritten（6）**：godraysDayExposureNoon（0.20 → 0.10）、godraysMaxAngle（60° 余弦为 0.5）、
  godraysViewAngleFade（夹取 0..1）、ndcLightVector（投影分母防零）、
  godraysOffscreenFade（夹取 0..1，防负曝光）、atmosphereFogCoefficient（Astra 侧
  `renderDistanceFogTweak * pow(0.60 / borderFogDistance, 3.0)`，去掉 Steadfast 定义尾部的
  `* mix(1.0, atmosphereFogStrengthNoon, noonFogProgress) * fogInCaveAdjustment` 两个因子）。
  更正记录（2026-09-21）：本行此前漏列 atmosphereFogCoefficient，且台账声明计数行曾声称它已由
  rewritten 归入 verbatim——两处均不成立，分类脚本与上述实算表达式都判 rewritten（verbatim
  名称清单同时多出一个名字、合计与声明数对不上，正是这一处漏列所致）。
  （moonrise/sunrise 已随 2026-09-20 死 uniform
  清理删除——它们无着色器消费者，见 consolidated review E3。）
- **astra-only（35）**：moonProgress、windStrength、
  astraHeldLightBase、astraBlocklightSuppression、astraHeldLightSuppression（E1 总成 2026-09-06 新增，
  CPU 标量表达式自写），SC-24/33 水体链的 9 条 `astraSolas*`：
  astraSolasTAlin、astraSolasTAmin、astraSolasTAfrc、astraSolasTAfrs、astraSolasTAmix、
  astraSolasHA、astraSolasTimeAngle、astraSolasTimeBrightness、astraSolasShadowFade
  （Solas 时间/日相表达式，Astra 侧自行改写并加 `astra` 前缀，无 Steadfast 同名定义），
  2026-09-10 新增的 astraRainFactor（`smooth(71, rainStrength, 3, 0.8)` 平滑雨量）、
  astraNetherWastes、astraNetherCrimson、astraNetherWarped、astraNetherBasalt、astraNetherSoul
  （Complementary r5.9 群系权重写法，名字与阈值由 Astra 自定），
  以及 2026-09-16 新增的共享晨昏包络 astraTwilightRise / astraTwilightFade /
  astraTwilightEnvelope / astraTwilightFactor（同一 smoothstep 包络在天空、云、雾、地表、
  diffuse 与水下之间共用的 CPU 侧单次求值，Steadfast 无对应定义）；
  2026-09-21 新增的月相标量 astraMoonIllumination / astraMoonLimbSign /
  astraMoonLightScale（三者由 `program/sky.fsh` 与 `global/dimension/overworld.glsl` 里
  原有的逐片元公式逐字搬上来，Steadfast 无同名定义，见 survey P0-4）。
  2026-09-25 新增 astraSkyDrySquared / astraSkyRoot / astraSkyColorM /
  astraSkyNoonBase / astraSkyNightWeather / astraSkyNightUp / astraSkyNightMiddle /
  astraCloudNoonAmbient，来自既有 Complementary 派生天空与云的逐片元公式，改为 CPU 每帧计算；
  这八个名称不在 Steadfast 中，原公式来源不因计算位置改变。
  注：`astraSolas*` 现在声明在 `lib/solas_water.glsl`（水体模块自持）；`check_pack.py`
  第 6 项已改为扫描整棵 include 树，不再因只查 `lib/uniforms.glsl` 而误报。
- 更正记录（2026-09-05）：本行原写"结构借鉴（表达式与分节模式，数值为 Astra 自定；
  worldSunVector 改锚定 sunPosition 而非 shadow light）"——两点均不成立：表达式为逐字复制，
  且 Steadfast 自己的 `worldSunVector` 已由 `sunVector`（= `sunPosition`/100）构造，与 Astra 逐字相同。

## 发布闸门提示（design.md §9.3）

- 上表中 Mellow 来源行（MIT）：公开发布仅须保留署名，无需重写。
- Steadfast 来源行（**表达式级移植**，40 条 custom uniform 表达式中 17 条逐字或近似逐字、7 条同名改写；另有 9 个 GLSL 文件为 Steadfast 代码派生，见下条范围更正）：发布前两选一——
  (a) 把这 24 条重写为 Astra 自有表达式；(b) 整包按 GPLv3 发布并满足 §7b 署名句。
  若按"Steadfast 修改版"传播，§7c/7e 还要求人类可读名称与文件名以 `(edit of coderbot's Steadfast)`
  结尾——Astra 现名不满足，故该项已上报（见 escalations.md SC-14），不在本档自决。
  个人使用期（不分发）不受上述发布条款约束。
- **范围更正（2026-09-05 登记；2026-09-06 SC-24 换源、2026-09-10 地形植被轮换源后两次更新）**：上面 (a) 只覆盖 `shaders.properties` 的 21 条表达式，不覆盖 GLSL 侧。`grep -rl "^// From Steadfast" shaders/` 现命中 **9 个文件**——`global/lighting/`（diffuse、sss、shadowmap）、`global/atmosphere/fog.glsl`、`global/post/godrays.glsl`、`global/water/surface.glsl`、`lib/distort.glsl`、`program/water.glsl`、`program/shadow.vsh`、`program/shadow.fsh`——它们与那 21 条同属 §7 条款的作用域。**名单已两次变动**：`global/water/` 的 absorption、caustics、refraction 经 SC-24 换源为 Solas 派生（11 → 9）；`global/lighting/wind.glsl` 经 2026-09-10 地形植被轮换源为 Complementary 派生、不再命中本 grep（同时 `lib/distort.glsl`、`program/water.glsl` 进入名单，故计数仍为 9）；`sss.glsl` 仍命中（地面植被分支为 Steadfast 派生），但其树叶分支已换为 Complementary。故 (a) 的真实工作量是「21 条表达式 + 9 个文件的表达重写」，(b) 则是整包转 GPLv3。SC-14 仍是 ⏸ 待用户拍板，本条只更正其影响面，不改候选与结论。
- **Complementary 来源行（新增，2026-09-10）**：`global/lighting/wind.glsl`、`global/lighting/sss.glsl`（树叶分支）、`global/atmosphere/{sky_gradient,stars,clouds_planar}.glsl`、`global/dimension/{end,nether}.glsl` 现为 Complementary r5.9 派生，许可为**专有**的 Complementary License Agreement 1.7（非 GPL、非 MIT）。发布前须与 (a)/(b) 一并决策——两个来源的条款要求不同（Complementary 允许 Modified Pack 再分发但有条件；Steadfast §7c/7e 另有改名要求），发布门需按最严者合并处理。登记日 2026-09-10。
- Refrax/Solas 来源行：`global/post/bloom.glsl`（B5，2026-09-05）已从"仅思路"升级为**公式级移植**
  （软阈值 + 13-tap 下采样），文件头已带 `// PROVENANCE: adapted from Refrax v1.3.1 (proprietary)
  - REWRITE REQUIRED before distribution`，**发布前须重写**（思路保留、表达自写）；其余行仍为
  结构借鉴/仅思路级别。Solas 侧现为**六行**：三行结构借鉴（`program/shadow.fsh` 的染色思路、`global/dimension/nether.glsl` 的 cloudy-fog 噪声塑形、`global/dimension/end.glsl` 的星野与星云查表结构）+ **三行表达式级移植（SC-24，2026-09-06）**——`global/water/` 的 absorption（waterFog）、caustics（waterCaustics）、refraction（composite4 REFRACTION 段），三文件头均带 `// From Solas V2.2b` + `REWRITE REQUIRED` 标记；若再升级为逐行移植，同样须加标记并在此更新。
- C 系列（C1..C6）2026-09-05 新登记的 8 行已进上表：5 行为 Steadfast 代码派生（GPL 面扩大），3 行为 Solas/Mellow/Refrax 的结构与思路级借鉴。`check_pack.py` 第 8 项现为 PASS（台账行数与带出处头的文件双向对齐）。

2026-09-25 更正：以上 SC-24 的三文件统一来源及头部标记描述仅记录当时状态。当前 absorption 为 Astra 距离输运实现，caustics 保留 Solas 水面高度场并采用独立解析聚焦场，refraction 改编自 Steadfast；light_shafts 改编自 Solas。blocklight 与 colors 的双来源已补入登记表。

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

## 2026-09-10 参考水面／水下依赖接入

本节为上述历史水光条目的当前实现补充。当前使用范围仍为用户授权的本地开发与实例。

| 文件 | 当前来源 |
|---|---|
| global/water/surface.glsl、refraction.glsl、absorption.glsl、program/water.glsl 空气侧 | Steadfast 0.8.0，coderbot，既有 GPL-3.0-or-later 及 Section 7 条款继续适用；恢复波场、视差、折射推进、吸收和 Fresnel 关系 |
| global/water/caustics.glsl、lib/solas_water.glsl、global/water/light_shafts.glsl | Solas V2.2b，Septonious；表达式级适配 waterNormals/waterCaustics、waterFog、lightColor、volumetricLight、post/tonemap 及 composite3/4/5/14；不是仅思路借鉴 |
| program/shadow.fsh、global/lighting/diffuse.glsl、program/water.glsl 水下侧 | 在既有出处之上接入 Solas 焦散投射、环境／直射混合、界面法线与 Fresnel/alpha 组合 |
| textures/solas-water-noise.png 及 .mcmeta | 来自用户提供的 Solas V2.2b shaders/tex/noise.png 及其采样元数据（素材为用户提供的现成数据文件，非 Astra 自写代码）。**2026-09-21 B7 补登记（原行缺字节数与哈希）**：png **678019 字节**，sha256 前缀 **`9184f93b83f0ebb2`**，与本地 `_analysis/Solas Shader V2.2b/shaders/tex/noise.png` 逐字节相同（同目录 `latest-2026-09-10/solas-shader` 的那份是 636978 字节 / 前缀 `912e47e64b5b5ec6` 的另一构建，**不**匹配，勿引错）；该 png 是唯一带 iTXt/iCCP/pHYs 的文件，内嵌 XMP 显示其为 Affinity Photo 1.8.2 于 2020-09-20 产出、标题 `noisetex` 的既有美术资产。.mcmeta **67 字节**，sha256 前缀 **`e9c800d49d941e58`** |
| textures/steadfast-water-noise.png 及 .mcmeta | 64×64 RGBA8（4096 个像素的 alpha 恒为 255，每通道满量程、std≈74），线性重复采样，以匹配 Steadfast 的 noiseTextureResolution=64。**2026-09-21 B7 就地更正——原写「按当前 Iris 1.11.2 的 NativeImageBackedNoiseTexture 所用 Java Random(0) 填充规则生成」已被实测推翻**：Iris 侧 `NoiseTexture.generateNoise()` 是每像素 3 字节的 `byte[3*w*h]`，由**一次** `new java.util.Random(0L).nextBytes()` 填满，再经 `texImage2D(…, 32849=GL_RGB8, 6407=GL_RGB, …)` 直接上传 GPU，**从不编码 PNG**（反编译件 `_analysis/astra-sc34/NoiseTexture.txt`；该件里的类名是 `net.irisshaders.iris.targets.backed.NoiseTexture`，与旧登记所写的 `NativeImageBackedNoiseTexture` 也对不上）；而本文件的像素在任何测试过的排列下都无法由 `Random(0)` 复现（只有第 0 个像素在 R/B 互换下「相等」，第 1 个像素即分岔；首 64 字节在 4 MB 的 `Random(0)` nextBytes 流中零命中；py `random`/numpy 的其余 seed-0 RNG 亦不符）。**确实成立的只有编码器**：用 Pillow 默认档 `compress_level=6` 从本文件自身的像素重存，可逐字节复现 **14561 字节**、sha256 前缀 **`b9502f10ec238b90`**（`compress_level` 2–5 输出同长度但另一哈希，7–9 为 14557 字节）。**结论：本文件的像素来源在仓库内无法复算**——既不能证明它是第三方美术资产，也不能证明是 Astra 自生成，`qa/tools/` 内也没有任何工具能重算它（`provenance_steadfast.py` 只分类表达式文本，不读 png）。**处置方向待用户裁定：重生成、替换还是保留，本条一律不决定**，与 16.4 里三条美术资产同归 SC-14 发布门。.mcmeta **67 字节**，sha256 前缀 **`e9c800d49d941e58`**（与 solas 那份逐字节相同） **2026-09-21 卡 D 追加：与 Steadfast 发行包的字节级比对**（本轮实测）——对 `Steadfast-0.8.0.zip` 的**全部 122 个成员**逐一取值比对：**包内不含任何图片文件**（`.png/.jpg/.jpeg` 计数为 **0**），也不存在与本 PNG 字节相同的成员（探针输出 `byte-identical members anywhere in the zip: NONE`）；本地解包树 `_analysis/Steadfast-0.8.0/` 同样 **0 个图片与 .mcmeta**、无字节孪生件。因此「本文件取自 Steadfast 的噪声纹理」这一**命名假设在字节层未获证实**：既不能确认逐字节复制（也就无从据其登记许可证），也不能据此否认；文件名与 64×64（`noiseTextureResolution=64`）只是**命名与规格**上的印证。**本轮未替换、未重生成任何纹理**，处置方向仍待用户裁定。（本行第 195 行；同一发现也解释了为何 16.4 的「三条逐字节复制的第三方 png」清单里没有本文件） **2026-09-21 E 轮追加：用户裁定「重生成」，纹理已替换**——新增 `qa/tools/regenerate_steadfast_noise.py`，以进程内 splitmix64（SEED=20260921，每像素 3 次抽取、各通道取低字节，alpha 恒 255）填 64×64 RGBA8，Pillow 默认档 `compress_level=6` 编码：**新 png 14517 字节，sha256 前缀 `181f0d9779e136e2`**（旧 14561 字节 / `b9502f10ec238b90` 只存于 git 历史，其无法复算的来源争议就此封存）。采样规格与 `.mcmeta`（67 字节，`e9c800d49d941e58`）不变；本行出处登记随之改写为：**Astra 自生成（2026-09-21 起按上列生成器可复算），无第三方出处，不占 16.4 美术资产清单**，SC-14 就本文件而言已闭合，其余三条美术资产仍留发布门 |
| shaders.properties | 接入并加前缀的 Solas 时间表达式，以及两组独立纹理绑定 |
| program/lit.vsh、lit.fsh、scene.glsl、scattering.fsh、final.fsh | **自写**（Astra 管线适配/组合层，非借用行）：调用及组合以上对应来源，仍保留 Astra 的 SSR、天空、局部光和部分后处理。本行的出处由被调用的各模块行各自登记，此处不重复登记 |

具体已接入与仍有差异的模块见 docs/2026-09-10-reference-effects.md；不得把本轮表达式移植描述为完整包逐像素复现。


### 2026-09-10 水体入射光、反射与合成补齐

- `shaders/global/water/reference_light.glsl` adapted from Steadfast 0.8.0 `environment/sky/minishita.glsl` and the matching `shaders.properties` atmospheric/light expressions. Prefix and water-path integration changes by Astra; retains Steadfast GPL-3.0-or-later and additional Section 7 terms already recorded above. **[2026-09-21 B3 已删除该文件]**：159 行、19 个 `waterRef_*` 与 `water_reference_lighting()`经全包扫描零调用（唯一提及是 `program/scene.glsl` 的 include），文件与其 include 一并删除；本条登记作为历史移植事实保留。
- `shaders/lib/solas_water.glsl` additionally adapts Solas V2.2b `lib/atmosphere/sky.glsl` and the default minimum-light constants.
- `shaders/global/water/bloom_capture.glsl` and `bloom_resolve.glsl` adapt Solas V2.2b `lib/post/computeBloom.glsl` and `getBloom.glsl`, retaining tile layout, sample weights, encoding and blend equations; sampler names and default option expressions adapted. Solas attribution and license treatment remain as recorded above.
- `program/water_composite.fsh` and `program/water_bloom.fsh` integrate those reference operations into Astra pass order.

- `shaders/textures/complementary-cloud-water.png`: Complementary r5.9 Reimagined `lib/textures/cloud-water.png`, retained unmodified for the ported cloud sampler; same Complementary attribution and license terms recorded above. **2026-09-21 B7 补登记（原行缺字节数与哈希）**：**128888 字节**，sha256 前缀 **`49174f769c70f0d1`**，与本地三个 Complementary 副本逐字节相同（r5.9 Reimagined、r5.9 Unbound、`study-2026-09-20/ComplementaryUnbound_r5.9.3`）；256×256 RGBA8，无 `.mcmeta`。

### 2026-09-10 维度与天气重做

- `global/dimension/end.glsl`：适配 Solas V2.2b `lib/atmosphere/skyEffects.glsl` 星分布与星云、`common.glsl` 末地配色、`fog.glsl` 远雾、`gbuffersLighting.glsl` 阴影混合。恒星圆盘、全屏接入与提亮响应由 Astra 实现；无末地大气云。
- `global/dimension/nether.glsl` 与群系 uniforms：Complementary r5.9 `lib/common.glsl` NETHER_COLOR_MODE 3 配色及 `shaders.properties` 群系识别模式，保留既有参考照明。删除 Astra 旧端点噪声雾。
- `global/atmosphere/weather.glsl`：积水的湿度/天光/向上法线/双层纹理因子参考 Solas `lib/pbr/generatedPBR.glsl`；阈值、圆环法线、云透射及管线组合由 Astra 实现。
- `program/lit.fsh` 雨滴形状、`program/deferred.fsh` 积水射线和雨雾散射为 Astra 实现，使用上列参考模块提供的天空/噪声。上述参考的授权说明沿用本文件已有登记。

### 2026-09-10 下界体积光与体积雾（N2/N3）

- `shaders/global/dimension/nether_volume.glsl`：适配 X0nk Bliss Stable `lib/nether_fog.glsl`（沿程 16 步积分、Plumes/floorPlumes/Erosion/Roof 与 Floor 高度衰减结构、haze/ceiling smoke 三段合成）。Astra 侧改动：加入 `ASTRA_NETHER_PLUME_SCALE`/`ASTRA_NETHER_HAZE_SCALE`/`ASTRA_NETHER_CEILING_SCALE` 三个密度标度，并按 Astra 的单次散射合成约定重写注释；采样步数、积分长度与参考不同（Astra 为 16 步、`borderFogDistance` 与 12×16 取小），不是逐像素复现。
- `shaders/textures/bliss-nether-noise.png`：Bliss Stable `shaders/texture/noises.png` 原文件复制，未修改（sha256 前缀 `77d1aa0c2195a4f6`，512×512 RGBA8 与源一致）。Bliss 用 `texture.noise = texture/noises.png` 的自动绑定；Astra 因 `noisetex` 已占用为自有的 256×256 噪声，改用 `customTexture.blissNetherNoise` 独立绑定，因此**采样过滤/包裹参数与参考不同**（Astra 为 Iris 自定义纹理默认值），这是已知保真差异。
- `shaders/program/nether_light.csh`、`shaders/global/dimension/nether_colored_light.glsl`、`shaders/world-1/shadowcomp{,A..H}.csh`、`shaders/program/shadow.vsh` 的下界体积光写入：架构参照 Solas V3.7b（`lib/vx/voxelization.glsl`、`programs/shadowcomp.glsl`、`shadow.glsl` 的 `voxel_img` 体素化与空单元传播模式），但**不是 Solas 实现的移植**：Astra 是自写的受限子集——64³ 体积、玩家周围约 32 格、同帧 8 步传播、无跨帧历史、无 LPV 照明、无 128+ 体积档位；占用/光源编码（bit 8 固体、bit 16 帧戳）、逐帧失效与边界淡出由 Astra 自行设计。Solas 的许可证状态与既有登记一致。
- `shaders/program/shadow.vsh` 的 `imageAtomicMax` 写入与 `shaders/program/nether_light.csh` 的传播：Astra 自写。
- `shaders/global/dimension/nether.glsl` 的 `astra_nether_colored_light` 消费点与 `program/scene.glsl` 的体积雾合成：Astra 自写。

### 2026-09-11 末地空间交会接续：当前实现说明

当前 `end_blackhole.glsl` 的 `bh_Blackbody` **已替换为自写实现**（2026-09-23 更新）：现为
`astra_blackbody_rgb`，直接在 610/545/465 nm 三个波长采样普朗克定律并按峰值归一。
为降低星点与盘面的逐像素开销，先前每个响应带的三点积分改为单点采样，每次调用共三个指数运算；
唯一物理常数为 `c2 = hc/k`，不含任何 CIE 拟合样条、色度矩阵或
参考常量表，职责仍是黑体温度→RGB。本包因此不再持有 IterationT 的 `Blackbody` 表达式。旧文件里的
WarpSpace、旋转矩阵、纹理噪声、FBM、pcurve、IGN 等未被当前渲染路径使用的移植函数此前已移除；
不能再用下方历史记录的“四处适配”概括现有实现。

本次 `end_geometry.glsl`、`end_system.glsl`、`program/end_illumination.fsh` 的虚拟轨道、实体距离场、消光、求交和每帧可见性计算，以及 `end_blackhole.glsl` / `end_kerr.glsl` 当前解析透镜映射、盘面采样与光子环，为 Astra 在本任务中的代码实现。没有新增第三方贴图、模型或音频。现有后处理文件的原始来源不因增加末地专属分支而改变。

### 2026-09-23 末地巨型黑洞：连续光路与流体纹理

`textures/astra-end-transfer.png`、`textures/astra-end-transfer-meta.png` 与
`textures/astra-end-flow.png` 均由 Astra 自写的 `qa/tools/build_end_transfer.py` 生成：
依次存储中心引力近似下光线与有限厚度盘面的两次进入坐标、局部出射方向与上下表面标记、
周期多尺度随机场。共享盘面形状位于 `end_disc_profile.glsl`；`end_plasma.glsl` 的热冕/盘风
与喷流结构、`end_kerr.glsl` 的频移/热点/通量实现均为本任务自写。参考截图仅用于外观方向，
没有复制其中图像像素，也没有引入第三方
贴图或预计算数据库。运行时保留明确的 Kerr 视觉近似，不将中心引力积分宣称为完整 Kerr 解。

### 2026-09-11 末地黑洞与星空：移植 IterationT 3.2.0（历史实现）

- `shaders/global/dimension/end_blackhole.glsl`：**移植**（非思路借鉴）IterationT 3.2.0
  `shaders/Lib/IndividualFounctions/EndSky.glsl`（`CalculateStars`、`WarpSpace`、
  `RotateMatrix`、`Calculate3DNoise`、`CalculateCloudFBM`、`pcurve`、
  `BlackHole_AccretionDisc_Stars`）与 `shaders/Lib/Utilities.glsl`（`Blackbody`、
  `MiePhaseFunction`、`InterleavedGradientNoise`、`curve`/`saturate`/`remapSaturate`）。
  来源见 `_analysis/latest-2026-09-10/iterationT-3.2.0`（`sources.json` 同目录登记）。
  口径：**表达式级移植**——步进循环、密度场、Blackbody 色温、环面光子环均为参考原式；
  Astra 侧改编只有四处，均已在文件内逐条标注：（**2026-09-22 就地更正**：其中 `Blackbody` 色温
  一项已**替换为自写实现** `astra_blackbody_rgb`，其余三项与“步进循环/密度场”经 2026-09-11 接续
  重写后也已不是参考原式；本条只作历史记录）
  1. `noisetex` 采样改用 Astra 的 `noiseTextureResolution`（Astra 为 256，参考为 64）；
  2. `BlueNoiseTemproal()`（TAA 查询）改为参考同样提供的 `InterleavedGradientNoise`；
  3. `worldShadowVector` 改由 `end.glsl` 传入末地恒星方向；
  4. 新增 `ASTRA_END_STAR_GAIN`（=3.0）补偿 Astra 不同的曝光/tonemap 链，参考取值为 1.0。
- 授权：IterationT 归档内**不含任何许可文件**，按专有处理，与本文件既有的 Refrax 条目同级——
  仅限当前个人使用定位；发布前必须整段重写或取得授权（design.md 9.3 发布闸门）。
- 历史说明：本文件此前登记的 `end.glsl` 手写解析式黑洞已**整段移除**，改为调用上述移植模块；
  被移除的实现连同两次失败记录保留在 `docs/2026-09-10-next-agent-dimensions-weather.md`
  与 `qa/session-log.md` 中，供追溯。
- `shaders/program/lit.fsh` 的像素端焦散增量为 Astra 自写（见该处注释），用于在水面之上
  接收、阴影贴图投射路径无法实机验证时保证焦散仍然可见；Solas 的写入端口径仍保留在
  `program/shadow.fsh`。**2026-09-22 更正**：该增量现在只服务**水面之上**的接收点——
  水下由 `program/shadow.fsh` 烘进水面 caster 染色（Solas 口径）的那一份单独承担，避免在
  水下把相位相差一个水柱深度的两张图案相乘（见该处头注与 261 节）。

### 2026-09-11 水下焦散与光束：移植 IterationT 3.2.0

- **2026-09-22 就地更正：本条原登记的表达式已全部删除，不再是"在包"实现。**
  `shaders/global/water/caustics.glsl` 的 `astra_water_caustics_focus` 与
  `astra_water_caustics_shaft_at`（原登记为 IterationT 3.2.0
  `Lib/BasicFounctions/Sunlight_Shadow.glsl::CalculateWaterCaustics` 与
  `Lib/IndividualFounctions/UnderwaterVolumetricFog.glsl::CalculateWaterCaustics`
  的表达式级移植）已随 2026-09-22 四症轮**整段删除**，其唯一消费者
  `program/lit.fsh` 的水下焦散项改为直接求 Solas 派生的 `solas_water_caustics()`。
  因此 `global/water/caustics.glsl` 当前**只保留 Solas V2.2b 的双层漂移噪声高度场**
  （见上方第 46/192 行与本文件 2026-09-10 节），文件头
  `Adapted from Solas V2.2b lib/water/waterCaustics.glsl by Septonious`
  与该登记自洽：IterationT 相关表达式在本包内的在包计数**归零**。删除原因与实测
  （focus 场 92.3% 落在自身 0.2 clamp 地板上、退化为平底 0.44 乘子、无亮斑）
  见 `global/water/caustics.glsl` 头注与 `qa/underwater-light-*.log`。
- （以下为历史记录，已不适用）原登记的实现：三点法求波面法线、折射竖直光线、
  以落点与接收点的距离作为聚焦量，九抽头求和；Astra 适配三处并已在文件内标注——
  ① 参考从自维护的波法线缓冲读取，Astra 改由同一份 Solas 高度场中心差分求法线；
  ② 太阳方向改用 Astra 的 `lightVector`；③ 空间抖动替代参考的时间蓝噪声（Astra 无
  TAA，逐帧抖动会闪）。坡度尺度 0.75 为对真实噪声纹理的离线标定值，不是参考常数。
- **资产边界（2026-09-11 修正）**：首次引入涟漪贴图时曾直接复制参考的
  `RippleAnimation1/2/3.png`。用户明确指出**不得挪用参考的图像资产**，已全部删除。
  现在 `shaders/textures/astra-ripple-1..3.png` 由
  `qa/tools/gen_rain_ripple.py` **自行生成**（显式物理模型：扩散并衰减的圆形波包，
  求梯度得到法线图），与参考资产无关。
  **2026-09-21 B7 补登记（原行只有一个 glob 文件名，无字节数、无哈希，是登记最薄的一组）**：
  三张均为 128×7680 RGBA8（128×128 瓦片 × 60 帧竖排），分别 **287512 / 556938 / 848759 字节**，
  sha256 前缀 **`33a5cfacf7424d69` / `1f35d37fe8b6d181` / `969ed94d92eaf53b`**。
  该脚本以 seed 101/202/303 驱动 numpy PCG64（不是 `java.util.Random`），其逻辑按内存重放
  （输出到 BytesIO、不写盘）可从脚本逐字节复现上述三组哈希，是包内唯一有完整工具留痕的 PNG；
  另注 `astra-ripple-3.png` 没有任何 `customTexture` 绑定（只有 1/2 被 `shaders.properties` 引到）。
  边界原则：**代码级移植按专有处理并登记；图像/音频等美术资产一律不得取用。**
- `shaders/global/water/light_shafts.glsl`：**历史实现，现已由 Solas 改编版本替换**。当时结构移植参考的
  `UnderwaterVolumetricFog`——`caustics³` 调制、`1/max(3, d*0.1)` 距离衰减、
  折射太阳方向的相函数、起始采样点远离相机。步进距离改为沿射线真实距离。
- 授权：IterationT 归档无许可文件，按专有处理，与本文件既有的 Refrax 条目同级，
  仅限当前个人使用定位；发布前必须重写或取得授权。


### 2026-09-11 下界与性能接续

- nether.glsl 的群系色/环境色继续来源于 Complementary r5.9；雾取消独立颜色解码，保持与环境照明的输入一致。
- 方块光组合参考 Solas 3.7b lib/lighting/gbuffersLighting.glsl 的体素替换、独立手持光和自发光排除；0.95 混合上限沿参考，按实际体素亮度渐入是 Astra 八格传播范围的适配。
- nether_volume.glsl 继续为 Bliss nether_fog.glsl 派生。指数样点递推是同一表达式的代数改写；顶层烟雾色改为 Complementary 群系色。
- nether_light.csh 参考 Solas shadowcomp 的直接邻居光场读取；Astra 保留同帧 max 传播，不引入 Solas 时间历史。非发光实体输出恒零使邻居材质读取冗余。
- Steadfast/Mellow/ITT 本轮只用于性能结构对照，没有新增三者的表达式移植。既有来源与授权要求继续适用。

### 2026-09-13 晨昏光照联动
参考 Complementary r5.9 lightAndAmbientColors、mainLighting 的包裹法线响应、skyColors、mainFog、Unbound 云层密度结构及 reflectionBackground。Astra 的晨昏线性光色、方向天空目标、两次采样的云反射近似和距离收敛参数为适配实现。原有 Complementary 来源登记继续适用；未新增参考图像资产。详细路径见 docs/2026-09-13-complementary-dawn.md。

### 2026-09-21 T16 · P2-13「MIT 可署名复用清单」

**本条的实际产物不是清单，而是逐文件权属（chain-of-title）审计。** 调研 §7 给 P2-13 的前提「MIT ⇒ 本次唯一能直接搬的部分」不成立：一个包的根许可证不是包内任一份文件的持有人。实测——Mellow v3.4 根许可 MIT／`Copyright (c) 2026 TheCMK`，但 `lib/tonemap_operators.glsl`（253 行）里 Astra 在用的两个算子块都是中继：`:80-84` 原样保留了 glsl-tone-map 的 MIT 原文（`Copyright (C) 2019 Damien Seguin`）覆盖 `:86-226`（`Lottes`、`Uchimura`、AgX），`:23` 只有一行指向 BakingLab 的裸 URL 注释覆盖 `:23-60`（`RRTAndODTFit`、`ACES_slow`），`:228-232` 是 Khronos 的 Apache-2.0 原文覆盖 `:233` 的 `PBRNeutralToneMapping`。Astra 移植时把 Seguin 那段丢了，又原样继承了 BakingLab 那行「只有 URL、没有持有人」。本轮补齐两段，并按 `check_pack.py` 第 15 项把两份上游原件与其许可证归档进 `shaders/lib/vendor/`。同一审计方法对包内每一行借用有效，不只对 MIT 有效。

#### 16.1 `lib/vendor/` 逐路径登记（第 15 项要求，共 11 个文件／2 个上游目录）

| 路径 | 上游（源文件） | 在 Astra 里的角色 | 许可 |
|---|---|---|---|
| `shaders/lib/vendor/README.md` | 无参考（Astra 自写：目录约定与反规范条——许可正文每上游只存一份，禁止逐文件复制） | 第 15 项要求的约定文档 | — |
| `shaders/lib/vendor/glsl-tone-map/README.md` | 无参考（Astra 自写：取件 URL、tarball 摘要、六文件作用表、复算命令） | 本目录自述 | — |
| `shaders/lib/vendor/glsl-tone-map/LICENSE.md` | glsl-tone-map 2.3.1（npm `glsl-tone-map@2.3.1`，仓库 `dmnsgn/shaders-tone-map`）根 `LICENSE.md`，1057 字节，sha256 前缀 `84cc14c5d563a1ce` | 本目录全部上游文件的许可原文（唯一一份） | MIT／`Copyright (C) 2019 Damien Seguin` |
| `shaders/lib/vendor/glsl-tone-map/uchimura.glsl.orig` | 同上包 `uchimura.glsl`，1924 字节，sha256 前缀 `bc1d1dc6cd239cf8` | `lib/tonemap.glsl` 的 `uchimura_tonemap_full`／`uchimura_tonemap` 原件 | MIT（Seguin） |
| `shaders/lib/vendor/glsl-tone-map/agx.glsl.orig` | 同上包 `agx.glsl`，3772 字节，sha256 前缀 `a6f456911665c606` | `agx_cdl`／`agx_punchy`／`agx_tonemap`、AgX 常数与四张 inset/outset 矩阵原件 | MIT（Seguin） |
| `shaders/lib/vendor/glsl-tone-map/aces.glsl.orig` | 同上包 `aces.glsl`，508 字节，sha256 前缀 `9dba1fa9b194efe1` | **未移植**（Narkowicz 亮度曲线版 ACES）。留档为权属判别式旁证：`vec3 aces(vec3 x)` 与 `const float a = 2.51;` 两个串在 `lib/tonemap.glsl` 命中 0 | MIT（Seguin） |
| `shaders/lib/vendor/glsl-tone-map/acesHill.glsl.orig` | 同上包 `acesHill.glsl`，931 字节，sha256 前缀 `9f2ceac42f38b38e` | **未移植**（Seguin 对同一份 BakingLab fit 的 GLSL 移植，与 `aces.glsl` 数值近乎相同而注释不同）。留档为旁证：其独有注释在 `lib/tonemap.glsl` 命中 0／2 | MIT（Seguin） |
| `shaders/lib/vendor/glsl-tone-map/reinhardJodie.glsl.orig` | 同上包 `reinhardJodie.glsl`，449 字节，sha256 前缀 `9a05daa3fe1c88cc` | **未移植**。Astra 的 `reinhard_jodie` 是 TheCMK 变体（`get_luminance(v)`，Rec.601 权重），上游这份用 `const vec3 lw` + `dot`（Rec.709）。判别串 `reinhardJodie`／`dot(x, lw)` 在 `lib/tonemap.glsl` 命中 0 | MIT（Seguin） |
| `shaders/lib/vendor/bakinglab/README.md` | 无参考（Astra 自写：jsDelivr 取件 URL 与两条完整 sha256、同日复抓一致的记录、HLSL→GLSL 机械转写清单、Mellow 中继说明） | 本目录自述 | — |
| `shaders/lib/vendor/bakinglab/ACES.hlsl.orig` | `TheRealMJP/BakingLab` 的 `BakingLab/ACES.hlsl`，1322 字节，sha256 `0dab4dbfbd748dd4d6a3f38cef00155cfa4ffb5f6a8dddf4b3368aff52e4b23f` | `aces_input_mat`／`aces_output_mat`／`rrt_and_odt_fit`／`aces_tonemap` 原件（HLSL，`.orig` 后缀使其不进编译与静态检查） | MIT（`Copyright (c) 2016 MJP`，文件内把该 fit 署名给 Stephen Hill `@self_shadow`） |
| `shaders/lib/vendor/bakinglab/LICENSE.txt` | 同上仓库根 `LICENSE`，1060 字节，sha256 `751878625007bd944c6f0b8b43e1bbdf47da639975d49c358832043a31f1f3e8` | 本目录许可原文 | MIT |

`shaders/lib/vendor/glsl-tone-map/` 与 `shaders/lib/vendor/bakinglab/` 两个目录行同时覆盖各自 `README.md`（第 15 项的目录 README 例外）。`.orig` 后缀让 `walk_shader_files()` 的 `.glsl` 遍历看不见这些文件，第 4 项的模块普查与 `compile_glsl.py` 的编译计数不受影响（本轮实测 `#4` 仍为 54 文件／52 模块）。

#### 16.2 P2-13 十条逐条裁决（Astra 侧消费者按正则实测，2026-09-21）

| 件（调研 §6 P2-13 行次） | 参照侧实测 | Astra 侧实测 | 裁决 |
|---|---|---|---|
| 1 驱动兼容层 RenderPearl `prelude/compat.glsl:14-249` | 该文件 249 行，`:1` 是 `// see https://gist.github.com/Luracasmus/ff78f1998a5a440899e1904fa23cc9c6`——RenderPearl 自己也是中继，持有人是 gist 作者 | `IRIS_VERSION` 全包命中 0，无 `lib/compat.glsl` | **不引入**（零消费点）。将来若引入，登记对象是 Luracasmus 而不是 RenderPearl |
| 2 CAS 锐化（LIGHT 仅思路／RenderPearl、Mellow 的 AMD MIT 版） | Mellow `global/post/cas.glsl` 64 行，`:1-7` 是 AMD 的 MIT 原文（`Copyright © 2023 Advanced Micro Devices, Inc.`），持有人是 AMD 不是 TheCMK | `\bCAS\b`／`sharpen` 命中 1 处且是无关注释词（`program/deferred.fsh:135`），无锐化实现 | **不引入**（Astra 的锐化需求未立项）。引入时登记 AMD |
| 3 归一化相位函数（公开论文；Noble GPL 禁抄） | — | 已有自有／已登记实现：`global/atmosphere/sky_minishita.glsl:57` `astra_phase_rayleigh`、`:62` `astra_phase_mie`；水下 `global/water/reference_light.glsl:34` `waterRef_RayleighPhase`（Steadfast 派生）。HG／Schlick 命中 0 | **零改动**：无缺口，Noble 的 GPL 行本来不可抄 |
| 4 Vogel 圆盘／蓝噪声取点（Photon、Bloop 均思路） | — | `Vogel`、`blueNoise` 命中 0；Astra 抖动走自写 `lib/bayer.glsl`（消费点 `global/post/godrays.glsl` 6 处） | **零改动**：思路条目，无 MIT 可署名对象 |
| 5 `pack_unorm_2x8`（Photon、Bloop 语义规格） | — | 命中 0 | **零改动**：G-buffer 通道压力未成为问题 |
| 6 原版光贴图当 LUT Miniature `common/getAmbientColor.glsl:2` | 该文件 18 行，`:2` `vec4 ambient = texture2D(lightmap, vec2(AMBIENT_UV.s, skyLight));` 引用准确；**整个 `shaders/` 目录内无任何许可证明文件** | Astra 不采 lightmap 纹理（`AMBIENT_UV`、`texture(lightmap` 命中 0），走 E1 供的 `skyLight`／`blockLight` 标量（`global/lighting/blocklight.glsl:41`、`global/lighting/diffuse.glsl:305`） | **不引入**：无消费点。且调研「MIT」的前提在此不成立——**包里没有 LICENSE 就没有 MIT 可声明**，属未声明许可 |
| 7 16 格量化阴影采样 Miniature `common/getLightStrength.fsh:11-12` | 该文件 37 行，`:11-12` 为 `#if SHADOW_PIXEL > 0` 与 `world2feet(bandify(feet2world(feetPos), SHADOW_PIXEL))`，引用准确 | `SHADOW_PIXEL`、`bandify` 命中 0 | **不引入**：同上，且 Miniature 许可未声明 |
| 8 SMAA（Mellow 唯一 MIT 实装） | Mellow `global/post/smaa.glsl` 88 行**无任何署名头**，首行即 `redmean`，配 `img/smaaArea.png` 与 `img/smaaSearch.png`——面积／搜索纹理与 redmean 权重是 SMAA 官方参考实现（Jimenez 等）的特征，Mellow 亦为中继且未登记 | `SMAA`、`FXAA`、`areaTex`、`searchTex` 命中 0 | **不引入**：与 §7.B.10（当前阶段不引入 TAA／AA）一致。调研「Mellow = MIT 因此可搬」在权属上不成立 |
| 9 `get_min_light`（绑 `screenBrightness`／`nightVision`） | Mellow `lib/tonemap.glsl`（119 行）`:84-89`，体内三句：`clamp(MIN_LIGHT_AMOUNT + screenBrightness * 0.1 - 0.1, 0.0, 0.5)` → `to_linear` → `+= nightVision / 7` | Astra 无该函数；自有下界为 `MIN_AMBIENT_COLOR`（`global/lighting/diffuse.glsl:409`）与下界分支（`global/dimension/nether.glsl:149-152`）。`screenBrightness` 已冻结在 `lib/uniforms.glsl:67`，经 `sky_gradient.glsl:85` 与 `nether.glsl:23` 两个宏消费 7 处（`clouds_planar.glsl:127,131,134,135`；`nether.glsl:143,147,149`） | **零改动**：能力已在，且形态不同（Astra 按维度配平，不做全局最小亮度）。是否引入 `screenBrightness` 响应属实机标定问题，不在本条范围 |
| 10 primaries → RGB↔XYZ 矩阵（Bloop 的同一算法有 CIE 公开规范） | — | 无独立函数；仅 `lib/tonemap.glsl:156`／`:163` 两条注释继承自 BakingLab 的矩阵链命名（`lib/uniforms.glsl:26` 与 `shaders.properties:243` 的 `XYZ` 是风向 theta 的分量名，无关） | **零改动**：无消费点，且自写即与 Bloop 无关 |

**净结论**：十条在 Astra 侧的可用增量为 **0**。按上表"裁决"列的口径是 5 条不引入（件 1、2、6、7、8）+ 5 条零改动（件 3、4、5、9、10）；按"Astra 侧实测"列的口径是**八条零消费点**（件 1、2、4、5、6、7、8、10，其中件 2 的唯一命中是无关注释词）+ **两条能力已在**（件 3、9）。两种分法都是 10 条，本文此前写的"七条／三条"是把件 10 误归入"能力已在"，本轮按上表逐格改回。P2-13 的实际价值不在清单，而在它逼出的审计方法，已落成 `shaders/lib/vendor/` 与 16.3 的复算配方。

#### 16.3 复算配方（全部为 2026-09-21 实测值）

- **glsl-tone-map**：`https://registry.npmjs.org/glsl-tone-map/-/glsl-tone-map-2.3.1.tgz`，tarball 13228 字节，`sha256 = 106d5d84e22ee37023f862aa22bacfd6699582518b3721ad947bbc0fa3f666e5`，`sha1 = fae727df7a09227c8621b54deba18084c30c0889`；`package.json` 记 `license: MIT`、`repository.directory: packages/glsl-tone-map`。本目录 5 个 `.orig` 加 `LICENSE.md` 已逐字节比对为与该 tarball 一致。
- **BakingLab**：无版本发布，取 jsDelivr `@master`（2026-09-21 抓取并同日复抓，两次逐字节一致）：`https://cdn.jsdelivr.net/gh/TheRealMJP/BakingLab@master/BakingLab/ACES.hlsl`（1322 字节，sha256 见 16.1）与 `https://cdn.jsdelivr.net/gh/TheRealMJP/BakingLab@master/LICENSE`（1060 字节，sha256 见 16.1）。
- **机械复算**：`python qa/tools/verify_tonemap_chain.py`。本轮实测退出 0，输出：去空白与行注释后逐字符比对，`uchimura(vec3,float x7)` 317／317 相同、`uchimura(vec3)` 130／130、`agxPunchy(vec3)` 57／57、`agx(vec3)` 56／56、`RRTAndODTFit(vec3)` 86／86、`ACESFitted(vec3)` 114／114 相同，`agxCdl(...)` 上游 612 → Astra 627（Astra 自加一处 `max(…, vec3(0.0))`，分数次幂遇负底数在 GLSL 无定义，Mellow 与上游都没有）；AgX 6 个常数与 2×9 个 ACES 矩阵值逐值复现（HLSL 行主序 ⇄ GLSL 列主序为同一线性映射）；Mellow 侧六个函数与两张矩阵均等于上游，中继未改写；ACES 血统判别：BakingLab 独有注释命中 2／2、acesHill 独有注释命中 0／2 ⇒ 来源是 `ACES.hlsl`；`reinhard` 权重实测上游 `0.2126,0.7152,0.0722` 对 Astra `0.299,0.587,0.114` ⇒ 不同源；两个未移植旁证集各 0／2 命中，且脚本自行断言判别串在上游六份原件之间唯一。
- **归属更正的可复核面**：`lib/tonemap.glsl:4-17` 的文件头现在同时点名三个持有人并各自指向 vendor 里的许可原文；`global/post/grading.glsl:228-232` 是 Mellow 的思路级署名（调研 §11.B 原记 `:204-208` 已过期，`:204-208` 实为输出 dither 注释块）。

#### 16.4 顺带发现（登记，不在本条修）

- **同一 MIT 包内的近亲文件需要注释级判别式**：`aces.glsl` 与 `acesHill.glsl` 数值几乎一致，靠常数比对无法区分；`reinhardJodie.glsl` 的 Rec.709 三元组同时出现在 `agx.glsl` 的 EOTF 里（Astra `lib/tonemap.glsl:130` 的 `const vec3 lw` 属于已移植的 AgX 块），曾使「未移植」断言假阳性。复算脚本因此改为只用各文件唯一字符串，并自行断言唯一性。
- **美术资产与台账自订边界冲突**：`shaders/textures/bliss-nether-noise.png`（695035 字节，sha256 前缀 `77d1aa0c2195a4f6`，Bliss 原件逐字节复制）、`shaders/textures/complementary-cloud-water.png`（128888 字节，前缀 `49174f769c70f0d1`）、`shaders/textures/solas-water-noise.png`（678019 字节，前缀 `9184f93b83f0ebb2`）与本文件 `:270`「图像／音频等美术资产一律不得取用」相矛盾（该句的当前行号是 `:270`，原写 `:258` 与现文件不符，2026-09-21 B7 实测更正；`solas-water-noise` 另有「用户提供的现成数据文件」一句登记）。`steadfast-water-noise.png`（14561 字节，前缀 `b9502f10ec238b90`）**不属于「Astra 按规则生成」这一列**——2026-09-21 B7 复算把「按 Iris 1.11.2 `NativeImageBackedNoiseTexture` 的 `Random(0)` 规则生成」这条说明**推翻**了：Iris 那个类是 3 字节/像素、经 `GL_RGB8` 直接上传、**根本不落 PNG**，而本文件的像素在任何排列下都无法由 `Random(0)` 复现（详见上表该行与 `qa/b7-png-provenance-2026-09-21.log`）。确实成立的只有「编码器是 Pillow 默认档 `compress_level=6`」；**像素来源在仓库内无法复算**，因此它**既不能证明是第三方美术资产、也不能证明是 Astra 自生成**，且没有任何工具能重算它。**故其处置方向与前三个文件一并归 SC-14 发布门、待用户裁定：重生成、替换还是保留，本条不擅动。**
- **`.mcmeta` 不能用作资产来源判据**：`shaders/textures/` 下实测只有两个 `.mcmeta`——`solas-water-noise.png.mcmeta` 与 `steadfast-water-noise.png.mcmeta`，均 67 字节、内容逐字节相同（`{"texture":{"blur":true,"clamp":false}}`，CRLF，sha256 前缀 `e9c800d49d941e58`），而 `bliss-nether-noise.png` 与 `complementary-cloud-water.png` 根本没有 `.mcmeta`（本条初稿写「三个第三方 png 的 `.mcmeta` 均为 67 字节」，2026-09-21 复查目录实测更正）。关键在于这两个同哈希的 sidecar 一个属于第三方原件、一个属于 Astra 自生成资产，即 `.mcmeta` 携带的信息与来源无关；来源判定只能靠 png 本体哈希。
- **交接文档已过期（注释腐烂）**：`docs/handoffs/nether.md:24,252-272,320`、`docs/handoffs/end.md:55-62`、`docs/handoffs/sky-clouds.md:180` 仍写「Astra 无 `screenBrightness`／本侧只能用常量 0.5／1.0」，而 `lib/uniforms.glsl:67` 已声明且被两个宏消费（见 16.2 第 9 行）。P-002 与 H2 实为已落地，登记状态未更新。
- **§7「MIT ⇒ 可自由复用」的前提只在该包自己就是持有人时成立**：本轮实测四个参照包里 Mellow 的 `tonemap_operators.glsl`（中继 Seguin＋BakingLab）、`global/post/smaa.glsl`（无署名）、RenderPearl 的 `compat.glsl:1`（中继 gist）、Miniature（根本没有 LICENSE）四种失效形态各不相同；今后任何复用须逐文件跑一遍 16.3 的配方。
- **校验缺口（2026-09-21 B7 登记，未修）：本文件已为每张 PNG 记下字节数与 sha256 前缀，但没有任何机器校验它们。** `qa/tools/check_pack.py` 第 8 项只按**文件名**比对：`:613-616` 行把以 `|` 开头且含 `lib/`／`shaders/`／`program/`／`.properties` 的表行收进待检清单，`:637-645` 行再从每行的拼接文本里取出**第一个** `.png`/`.glsl`/`.fsh`/… 文件名，去 `PACK = Astra/shaders` 下找同名文件——**从不读取它的字节**；随后的 `:657-684` 行比对的是 Steadfast 表达式计数。全脚本不含 `hashlib`／`sha256`，`qa/tools/` 里也没有第二个门校验贴图字节（`gen_rain_ripple.py` 只写不读，`sync_to_instance.py` 的 sha256 只用于决定往实例同步时拷哪几个文件）。**因此替换或损坏任何一张 PNG 都能静默通过第 8 项**：本节登记的哈希目前只能靠人工按 B7 的方法复算（`qa/b7-png-provenance-2026-09-21.log` 第 1 节给出全部字节数与完整 sha256）。同一盲区的另一半：canonical `## 登记表`（`:18` 起）至今**零 PNG 行**，PNG 登记只散在上述散文与本节，第 8 项的表格扫描根本看不到这些文件（即 B7 报告里的 G1）。要闭环就须给第 8 项加一条读字节比哈希的检查——本条不擅自改门。

### 2026-09-22 部分方块的光泽与"发光体泛光"（E3）

- `shaders/block.properties` 新增 `block.10013..10016` 四类**发光体驱动的光泽岩**（下界岩／黑石-玄武岩族／深板岩族／石头-圆石族），`shaders/program/lit.vsh` 的 `astra_material()` 把它们映射到 4-bit 材质域的 **12..15**（该域此前只用到 0..11，这四个是全部剩余取值，因此**没有扩位**：`faceData` 的 bits 22..31 仍空，法线的 18 位打包布局未动），`shaders/program/lit.fsh` 新增 `material >= 12u && material <= 15u` 分支。ID 命名空间与类目理由写在 `block.properties` 该段注释里；全部 39 个方块名已对本机客户端 jar 的 `assets/minecraft/lang/en_us.json`（1884 个 vanilla block 名）逐个复核。
- 来源口径：**思路借鉴（idea only）**。对象是 Complementary r5.9 的 `lib/materials/specificMaterials/terrain/netherrack.glsl`、`blackstone.glsl`、`deepslate.glsl`、`stone.glsl` 以及 `lib/materials/materialHandling/terrainIPBR.glsl` 里这四类方块的派发处——即"每种地形材质自带一个 per-texel 光泽度，供该包的 SSR 映出附近的发光体"。**没有使用其中任何表达式**：参考那一串 `pow2(color.r) * 1.5`／`color.r`／`pow(color.g, 1.5) * 0.55`／`pow2(pow2(color.g)) * 2.0`／`dot(color.rgb, color.rgb) * 0.17` 在 Astra 侧命中 0。Astra 的实现是自写的三件：① 光泽 = 类别增益 ×（0.55 底线 + 纹理线性亮度对比），底线的作用是让近黑的黑石与接近白的方解石都落在可用区间；② 世界固定栅格的哈希颗粒 + 按视距收敛（不是参考的纹理直接读法）；③ 邻近门用**原版本方块光等级**（岩浆与火焰同为 15 级，每方块衰减一级），视角权重用与冰面同一形状的 Fresnel。
- 不引入体素泛洪、不新增 pass／缓冲／uniform、不新增任何用户可见选项：近邻信号取自片元自身的 `lightLevel.x`，因此本改动完全不含 `shadowcomp` 类通路，也没有新的 ray march。
- 授权：Complementary 为 **Complementary License Agreement 1.7（专有）**，按本文件开头表与 design.md §9.3／SC-14 的发布闸门处理，仅限当前个人使用定位；发布前须重做发布门决定。本条不含任何参考图像／音频资产。
- 量化留痕：`qa/tools/block_reflect_probe.py`（常量与分支守卫全部从**发货源文件解析**，不是转写；方块反照率取自本机客户端 jar 的 16×16 平均）与 `qa/block-reflect-2026-09-22.log`。

