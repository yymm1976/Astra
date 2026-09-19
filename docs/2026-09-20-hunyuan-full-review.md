# Astra 全面代码审查报告

> **审查方：混元四**
> **日期**：2026-09-20　**版本**：工作区 `7e3f51c` + 39 项已修改 + 26 项未跟踪
> **性质**：**只读审查。本次未修改任何代码文件、未修改任何着色器源码**，仅新增本报告。
> **方法**：全树静态扫描（246 个着色器源文件）+ 项目自带校验器实跑 + GPU 编译实跑 + 历史审查报告逐条回溯核验 + `design.md` 蓝图逐节比对。
> **未做的事**：无游戏内验证，**所有画面与帧率结论都不在本文范围内**。

---

## 0. 总体结论

| 维度 | 评级 | 说明 |
|---|---|---|
| 构建健康度 | **良好** | GPU 实跑 `267 linked / 0 failed / 27 compute`；`check_pack` **0 FAIL / 1 WARN / 10 PASS** |
| 架构纪律 | **中上** | 三层分层基本成立；但存在 8 处 `global → global` include，与 `design.md` §3.2 决议文字冲突且校验器不覆盖 |
| 代码质量 | **中上** | 注释密度与"为什么"质量高于同类项目；但源码自述的返工记录显示三轮连续出现同一失效模式（见 §7） |
| 文档一致性 | **不足** | **`Astra/README.md` 有 7 处事实错误**，其中效果三对标方向写反；`design.md` §12 状态停在 09-07 |
| 可回滚性 | **不足** | 09-16 与 09-17 两轮改动全部未提交，最近提交点仍是 09-13 的审计报告 |
| 性能 | **中** | 无实测帧率；逐像素热点已受控，但 **pass 层面有 3 个空转/无效调度的全屏 pass，以及 `composite4` 的 144 抽头 + 主缓冲恒开 mipmap 黑洞**（§12） |
| **两个长期未达成的水效果** | **未达成** | **水下光束（B1）链路闭合但量级被压 8–20 倍；水上看水下的青绿→深蓝（B2）效果其实已存在于 `WATER_COLD` 档，默认档的绿蓝系数方向相反**。详见 §11 |
| **与另两份审查的交叉核验** | — | 2026-09-20 另有 GLM-5.3-Flash 与 Qoder 两份报告。**三方独立得出同一批核心结论**；我采信其 6 条我漏掉的发现（含 3 条 P1），并**修正我自己的 3 条结论**。详见 §13 |

**一句话判断**：**没有 P0 级缺陷**——代码能编译、契约自洽、无崩溃级热点。真正拖后腿的不是着色器，是**这四件事**：README 描述的是一个 2026-09-05 的项目、工作区半个月没有提交点、一个反复出现的流程失效模式（注释说意图、代码做别的事，而验证只看"能否编译"）、以及两个水效果长期停在"差一点"的状态（§11）。

**最高优先级五件事**：提交工作区（A3）→ 重写 README（A2）→ 修 `final.fsh` 水下重复 tonemap（A1）→ 水下光束方向因子解耦（B1）→ 默认水色档改向深蓝（B2）。

---

## 1. 项目规模（实测）

| 项 | 数量 |
|---|---|
| 着色器源文件 | **246**（`.fsh` 96 / `.vsh` 86 / `.glsl` 54 / `.csh` 10） |
| 着色器总行数 | **9,741** |
| 顶层目录分布 | `<root>` 58 / `world-1` 59 / `world1` 54 / `global` 35 / `program` 25 / `lib` 15 |
| 用户选项 | **67**（布尔 27 / 滑块与枚举 40） |
| 编译入口 | **182** 个（54 个 lib/global 模块中 52 个可达，2 个等 C5） |
| 语言文件 | `zh_CN` 173 条 / `en_US` 173 条 |
| 台账 | `THIRD-PARTY.md` 48 行，42 KB |

**体量最大的五个文件**（审读重点）：

```
457  global/lighting/diffuse.glsl
377  program/lit.fsh
364  global/water/surface.glsl
364  lib/settings.glsl
325  global/atmosphere/clouds_planar.glsl
310  program/water.glsl
```

---

## 2. 验证结果（本次实跑，非引用历史）

| 校验 | 结果 |
|---|---|
| `qa/tools/compile_glsl.py`（真实 GPU，全档） | **`linked=267 / failed=0 / compute=27 / compute_capable=true`**（RTX 4050 Laptop + NVIDIA 572.83） |
| `qa/tools/check_pack.py` | **0 FAIL / 1 WARN / 10 PASS**（WARN 仍是已知的 voxy C5 未接线） |
| `qa/tools/cost_census.py` | 已按 09-13 §13.1 要求改为诚实的"源码清单"，明确声明不作为运行时上界 |
| 三维度入口覆盖 | 20 对 `gbuffers_*` × 3 维度全覆盖，无缺失 |
| 纹理引用完整性 | `shaders.properties` 引用的 7 个 `textures/*.png` **全部存在** |

**结论**：编译与契约层面是健康的。下文所有问题都**不是**"编译不过"，而是校验器覆盖不到的一类。

---

## 3. 问题清单

### 3.1 P1 —— 应尽快处理

#### A1（P1）`program/final.fsh`：水下路径重复计算一整次 tonemap + sRGB 后被丢弃

```glsl
:88  vec3 displayColor = srgb_encode(apply_tonemap(apply_exposure(hdr)));
:89  #if !defined DIMENSION_NETHER && !defined DIMENSION_END
:90      if (isEyeInWater == 1) displayColor = solas_water_display(apply_exposure(hdr));
:91  #endif
```

- **问题**：第 88 行无条件执行完整的 `apply_exposure → apply_tonemap → srgb_encode`；水下时第 90 行**整体覆盖**其结果。即水下每一像素都白算一次 Uchimura tonemap（含多次 `pow`/`mad`）与一次 sRGB 编码。
- **量级**：1080p 水下全屏 ≈ **207 万像素/帧**的确定性浪费，且水下正是 design §8 验收的典型场景之一。
- **与历史的关系**：这是新引入的结构问题，09-13 报告未覆盖（当时 final 的分支形状不同）。
- **建议**：改为二选一结构——
  ```glsl
  #if !defined DIMENSION_NETHER && !defined DIMENSION_END
  vec3 displayColor = isEyeInWater == 1
      ? solas_water_display(apply_exposure(hdr))
      : srgb_encode(apply_tonemap(apply_exposure(hdr)));
  #else
  vec3 displayColor = srgb_encode(apply_tonemap(apply_exposure(hdr)));
  #endif
  ```
  行为完全不变（两条分支本来互斥），纯消除冗余。

#### A2（P1）`Astra/README.md` 有 7 处与实现/蓝图冲突的事实错误

| # | README 原文 | 实际情况 | 证据 |
|---|---|---|---|
| 1 | "水下 ≈ Steadfast、水面 ≈ Solas" | **方向写反**。SC-24 决议已更正为**水面 ≈ Steadfast、水下 ≈ Solas** | `design.md` §0 第 15 行、`docs/2026-09-06-*` |
| 2 | "零 compute" | 实际 **10 个 `.csh` + 27 个 compute 程序**（下界体素光） | `shaders.properties:339-347`、`compile_glsl` 实跑 |
| 3 | "33 个模块中仅 8 个可达""lit/final 未接线（E1 未冻结）" | 实测 **52/54 可达**，lit/final 早已接线出图 | `check_pack #4` 实跑 |
| 4 | "`surface.glsl`、`raytrace.glsl` 暂无生产者（已上报 SC-15）" | 两者早已实现并集成（364 行 / SSR 24+6 步） | `program/water.glsl`、`global/water/raytrace.glsl:63,87` |
| 5 | "本机无可运行的 Iris 实例…冒烟/截图/帧率均未执行" | 已有实例同步工具与同步记录 | `qa/tools/sync_to_instance.py`、`qa/session-log.md` 尾轮"Copied 3 / Missing 0" |
| 6 | 三档 Profile 表："流畅 阴影 1024/96 格"、"极致 4096/192 格/16 texel" | 实际：`SHADOW_DISTANCE` 流畅 **192** / 极致 **256**；`SHADOW_SOFTNESS` 极致 **8** 非 16 | `shaders.properties:166,168` |
| 7 | "出厂分级 饱和 112 / 自然饱和 115 / 对比 104" | 实际 **100 / 100 / 102**（09-07 轮下调） | `lib/settings.glsl:177,179,181` |

- **另有一处次要**："截图集…当前仅有占位文件" —— `qa/screenshots/` 实际已有 24 个文件（09-06 二十张 + 09-07 四张）。
- **影响**：README 是唯一面向用户的发布物。第 1 条尤其严重——它把验收口径（design §8 第 3 项）写成了被推翻的版本，任何人照 README 验收都会得出相反结论。
- **建议**：整体重写 README 的「特性」「三档 Profile」「已知问题」「2026-09-06 开发状态」四节；把「已知问题」里 09-05/06 骨架期的条目整体替换为当前真实缺口（无帧率实测、Voxy 未接线、26.x 未冒烟、文档滞后）。

#### A3（P1）工作区半个月无可回滚点

```
git log   → 最近提交 7e3f51c "Add the full pack audit"（09-13）
git status→ 39 个已修改（含 lib/settings.glsl、program/lit.fsh、program/deferred.fsh、
            program/final.fsh、program/scene.glsl、shaders.properties 等核心文件）
            26 个未跟踪（含 lib/pow.glsl、17 个 qa/glsl-*.log、3 份 docs）
```

- **影响**：09-16 视觉体验轮与 09-17 SC-39 轮的全部改动**没有任何提交点**。SC-39 是一轮三次返工的改动（见 §7），一旦需要回退只能靠人肉 diff。
- **与历史的关系**：09-13 报告 R7 已提出，本次仍未解决，故上调至 P1。
- **建议**：按主题拆三次提交——① `lib/pow.glsl` + 数学助手替换（性能轮）；② 积水/涟漪/雨天反射（SC-39）；③ 其余视觉轮改动 + 文档。

#### B1（P1）水下光束：链路闭合，但积分量级被压低 8–20 倍

- **先排除接线问题**：链路是完整闭合的 —— `composite2` → `program/scattering.fsh:39` `water_shafts_march()` 写 `colortex1` → `composite3` → `program/water_composite.fsh:19` `water_shafts_resolve()` → `solas_water_composite()`。启用条件、pass 时序、`ASTRA_SHAFT_MARCH_PASS` 定义全部正确。**不是没接线，是量级不够。**
- **四个可定位的衰减点**（数值复现见 §11.1）：
  1. `light_shafts.glsl:52-54` 的 `visibility` 被两个**几何互斥**的方向因子相乘压制，最优 0.107 vs 理论上限 0.85；
  2. `light_shafts.glsl:67` 采样只覆盖到 18.6 格（名义 40），步距 2.86 格；
  3. `light_shafts.glsl:77` 用圆形判据剔除方形 shadow map，损失 21.5% 面积；
  4. `lib/solas_water.glsl:100` 旧的角向亮晕 `glare*16.0` **未被 SC-33 移除**，与光束同向竞争，正对太阳时把光束占比压到 10.4%。
- **建议**：见 §11.1.5，按性价比排序为 方向因子解耦 → 采样分布修正 → 圆形判据改方形 → 移除 `glare*16` → 加可开关的 `colortex1` 调试视图。

#### B2（P1）水上看水下的深浅过渡：效果已在 `WATER_COLD` 档，默认档方向相反

- **根因**：`global/water/absorption.glsl:28` 默认档 `WATER_BALANCED` 的系数为 `vec3(1.000, 0.0600, 0.1000)`（R/G/B 衰减）。**绿衰减 0.06 < 蓝衰减 0.10 → 蓝比绿衰减更快 → 越深越绿**，与"深蓝"需求相反。
- **决定性事实**：`WATER_COLD`（档 0）的系数是 `vec3(1.000, 0.2200, 0.0800)`，绿衰减 **大于** 蓝衰减，其色相轨迹正是**浅处青 → 深处深蓝**（15 格处归一化色相 `(0.00, 0.10, 0.90)`）。**用户要的效果已经存在，只是不在默认档。**
- **另两个叠加问题**：`absorption.glsl:60` `appearanceDepth` 被 `clamp(…, 0, 16)`，15 格以上色相**完全冻结**；`water_surface_medium` 只有吸收项、无 in-scattering，深处三通道同时趋于 0 → 表现为"发黑"而非"深蓝"。
- **建议**：见 §11.2.4。最小改动是对调默认档的绿蓝衰减关系，并放宽深度上限。

---

### 3.2 P2 —— 应排期处理

#### A4（P2）`program/lit.fsh:231` 在非统一控制流内取 `dFdx/dFdy`

```glsl
:189  if (material == 11u) {          // ← 末地石材质分支，material 是 flat varying
      ...
:231      float footprint = max(length(dFdx(texcoord)), length(dFdy(texcoord))) * 256.0;
:232      gloss = mix(gloss, 0.48, smoothstep(0.6, 2.4, footprint));
```

- **问题**：`material` 在 quad 内可不同（末地石与其他方块交界），该分支是非统一控制流；规范上分支内导数未定义，GPU 按 quad 取值的差值在交界处无意义。
- **后果**：末地石与相邻材质交界的 quad 上 `footprint` 跳变 → `gloss` 突变 → **高光颗粒在方块边界大小跳变**。与该项目没有 TAA/AA 的前提叠加，表现为边界闪烁。
- **与历史的关系**：N9（`deferred.fsh` 星点）与 T6（`lit.fsh:47` 涟漪）**都已按同一手法修好**，这处漏网。
- **建议**：沿用 `lit.fsh:47` 的既有手法——把 footprint 提到 `if (material == 11u)` 之外、alpha 丢弃之后计算。成本可忽略。

#### A5（P2）09-17 轮的改动没有任何归档文档

- **证据**：`docs/` 最新文件是 `2026-09-16`；着色器源码最后修改是 **2026-09-17 00:58**（`global/atmosphere/weather.glsl` 等 13 个文件）。09-16/09-17 两轮只存在于**未提交**的 `qa/session-log.md` 与 `qa/glsl-sc39-*.log`。
- **影响**：SC-39 三次返工的教训（含"`colortex0.a` 不存在，我上一轮的断言是编造的"）目前只写在未入库的日志里。下一个接手的人看不到。
- **建议**：补 `docs/2026-09-17-sc39-puddle-reflection.md`，把三次返工与两道新校验规则沉淀下来。

#### A6（P2）8 处 `global → global` include，与 `design.md` §3.2 决议冲突且校验器不覆盖

```
global/atmosphere/clouds_planar.glsl → /global/atmosphere/sky_gradient.glsl
global/atmosphere/stars.glsl         → /global/atmosphere/sky_gradient.glsl
global/dimension/end.glsl            → /global/dimension/end_blackhole.glsl
global/dimension/end_blackhole.glsl  → /global/dimension/end_system.glsl
global/dimension/end_ring.glsl       → /global/dimension/end_geometry.glsl
global/dimension/end_system.glsl     → /global/dimension/end_ring.glsl
global/dimension/nether.glsl         → /global/dimension/nether_colored_light.glsl
global/water/light_shafts.glsl       → /global/water/caustics.glsl
```

- **冲突点**：`design.md` §3.2 的 E1 决议明文写"**global 不 include 其他 global**"。
- **为什么校验器没抓到**：`check_pack #4` 只校验 lib/program 方向的层违规，对 global 内部依赖不作判断，所以仍是 PASS。
- **判断**：**当前无功能缺陷**，末地 5 模块（`end → end_blackhole → end_system → end_ring → end_geometry`）已形成一条清晰的单向链、无环。这是受控演进而非腐化。
- **建议**：二选一——① 更新 `design.md` §3.2 决议，正式承认"大气"与"末地"两个子分层；② 把 `end_*` 收敛到 `global/dimension/end/` 子目录并在 `check_pack #4` 显式放行。**不要维持"决议说不行、代码在这么做、校验器不管"的三不管状态。**

#### A7（P2）`size.buffer.colortex1` 无维度守卫（历史 T7，本轮复核后维持登记）

- **证据**：`shaders.properties:8-13` 的尺寸条件只判 `UNDERWATER_LIGHT_SHAFTS && SHADOWS`，不含维度判断。主世界开启水下光束时 `colortex1` 为全分辨率，下界/末地同样按全分辨率分配，但两维度的 `composite2` 已禁用（`properties:58,63`），**该缓冲在这些维度既不写也不读**。
- **说明**：09-13 §13.3 以"properties 尺寸指令是公共配置，不能套用入口 GLSL 的 `DIMENSION_*` 宏"为由不采纳自动守卫，**该理由成立**，本轮不推翻。此处仅作为显存浪费登记。
- **建议**：若不接受自动守卫，请在 `properties` 该段注释里写明"下界/末地会按此尺寸分配但不使用"，避免下次又被当成新缺陷查一遍。

---

### 3.3 P3 —— 清理项

| # | 问题 | 位置 | 说明 |
|---|---|---|---|
| **A8** | 5 个枚举 token 常量零引用 | `lib/settings.glsl:20,23,28,30,31` | `SKY_MINISHITA`、`SUN_MOON_DISCS`、`WATER_BALANCED`、`SHADOW_FILTER_SOFTWARE`、`SHADOW_FILTER_HARDWARE`。历史 N8，09-13 §13.3 明确不采纳（保留来源结构）。**仅登记一处副作用**：`SHADOW_FILTER_*` 两个 token 与 `SHADOW_FILTER_MODE == 1` 的判定并存，读代码的人会以为改枚举值就够 |
| **A9** | `end_blackhole.glsl:76` 的 `dFdx` 分支仍是活路径 | `global/dimension/end_blackhole.glsl:73-77` | `ASTRA_END_SKY_BUFFER` 未定义时走该分支；`program/sky.fsh`（`gbuffers_skybasic`）属于此路径。风险低（末地天空主体由 `end_sky_buffer` 承担），但建议让 sky.fsh 也走 buffer 路径或把 cone 显式传参 |
| **A10** | `design.md` §12 计划状态停在 2026-09-07 | `design.md:474-487` | 代码已推进到 09-17。M1–M4 状态、SC-35 之后的决议均未回填 |
| **A11** | `design.md` §0/§2.1 边界声明与实现冲突 | `design.md:18,48` | "零 compute""v1 不做彩光" vs 实际的下界体素彩色光（10 compute + 3 自定义图像 + `NETHER_VOXEL_LIGHT` 选项）。属**受控演进**，但该例外从未写回边界声明 |
| **A12** | `docs/` 平铺 53 份文档 | `docs/` | 09-13 §8 与 §12.15 两次建议归档（按 `rounds/reviews/design` 分目录），未执行 |

---

## 4. 2026-09-13 报告声称已修复项的回溯核验

**这是本次审查的重点之一**：上一份报告 §13.2 声称处理了 12 项。逐条对照当前源码核实，结论如下。

| 原条目 | 声称的处理 | 核验结果 | 证据 |
|---|---|---|---|
| **N1** `ENTITY_SHADOW_DISTANCE` 假控件 | 接入全部合法组合 | ✅ **已修复** | `lib/settings.glsl:227-323` 的 8×5 字面量表。抽样复核：`SHADOW_DISTANCE=256 / ENTITY=64 → 0.1666667 = 64÷256÷1.5` ✓；`192/48 → 0.1666667` ✓；`256/96 → 0.25` ✓。错误注释（"三档恒为 0.5"）已删除 |
| **N2** 全局非常量初始化器 | 局部化/删除 | ✅ **已修复** | 全树扫描 **0 处**顶层初始化式引用 uniform |
| **N3** `#if 2 == 0` 死分支 | 删除 | ✅ **已修复** | `global/water/bloom_resolve.glsl` 无该模式 |
| **N4** LPV 未移植宏残留 | 删除 | ✅ **已修复** | `nether_volume.glsl` 无 `LPV_FOG_ILLUMINATION`，无 `LPV_VL_FOG_ILLUMINATION` / `EXCLUDE_WRITE_TO_LUT` |
| **N7** 闪电 `normalize` 无防御 | 加下限 | ✅ **已修复** | `global/lighting/blocklight.glsl` 已改为有下限的长度归一化 |
| **N9** 末地星点分支内导数 | 提到分支外 | ✅ **已修复** | `program/deferred.fsh:101` 现位于 `main()` 顶部、`if (depth…)` 之外 |
| **T1** `pow(负底数, 2.0)` | 改自乘 | ✅ **已修复** | `end_blackhole.glsl:115-118` 现为 `shellOffset*shellOffset` / `haloOffset*haloOffset` |
| **T3** `CLOUD_OFF` 雨天泄漏 | 只在 PLANAR 绘制 | ✅ **已修复（且修全了）** | `scene.glsl:46` `#if CLOUD_MODE == CLOUD_PLANAR`；**关键补充**：`weather.glsl:124` `astra_cloud_transmission` 同样有 `#if CLOUD_MODE != CLOUD_PLANAR → return 1.0`，光照侧也没漏 |
| **T4** 末地强制 bloom | 服从 BLOOM | ✅ **已修复** | `final.fsh:16` `#ifdef BLOOM`；`properties:64` `program.world1/composite1.enabled=BLOOM` |
| **T5** `end_star_visibility` 靠初始值巧合 | 入口显式重置 | ✅ **已修复** | `end_blackhole.glsl:72` 函数入口 `end_star_visibility=0.0;` |
| **T6** 涟漪足迹分支内导数 | 提到分支外 | ✅ **已修复** | `lit.fsh:44-48` 位于 `main()` 顶部、alpha 丢弃之前 |
| **T8** `final` 死声明 colortex1 | 只在 GODRAYS 声明 | ✅ **已修复** | `final.fsh:25-31` |
| **T2/T10** 注释失实 | 据实改写 | ✅ **已修复** | `settings.glsl:223-226` 注释已与 Iris 实际公式（`× shadowDistanceRenderMul`）一致 |
| **R1/cost_census** 工具夸大能力 | 改为诚实清单 | ✅ **已修复** | `cost_census.py` 输出首行即声明"lexical, NOT fetches/pixel"，末尾附人工工作量说明 |

**结论：上一轮报告声称的修复全部真实落地，无一条是"报告说修了但没修"。** 这一点值得明确记录——它说明该项目的修复记录是可信的。

---

## 5. 与 `design.md` 蓝图的一致性

| 蓝图条款 | 实现状态 | 判定 |
|---|---|---|
| §1.2 Iris 专用、不写 OptiFine 回退 | 全树无 `IS_IRIS` / `IS_OPTIFINE` 分支 | ✅ 一致 |
| §1.2 远景仅 Voxy | `voxy.json` 空、`VOXY_SUPPORT` 默认关 | ✅ 一致（功能待 C5） |
| §2.2 不建 `world0/` | 只有 `world-1/` 与 `world1/` | ✅ 一致 |
| §2.2 维度上下文只由目录注入 | 三维度入口壳仅为 `#version + 宏 + include` | ✅ 一致 |
| §2.4 无 AA pass | 无 TAA/FXAA/SMAA | ✅ 一致 |
| §3.3 选项 60–80 | **67** | ✅ 一致 |
| §3.3 GUI 主屏 + 7 分类 | 实测 FOG/LIGHTING/PERFORMANCE/POST/SHADOWS/SKY/WATER | ✅ 一致 |
| §3.3 zh_CN 全覆盖 | 173 条，check_pack #3 PASS | ✅ 一致 |
| §4.1 光照清单（含闪电、SSS、手持光、彩色阴影、静态回退） | 全部有实现 | ✅ 一致 |
| §4.3 水面 = Steadfast / 水下 = Solas（SC-24） | 实现遵循更正后方向 | ✅ 一致（**但 README 写反，见 A2-1**） |
| §4.5 下界/末地独立设计 | `global/dimension/` 下 11 个模块 | ✅ 一致 |
| §9.2 出处台账 | 48 行 + check_pack #8 PASS | ✅ 一致 |
| **§2.1 "极简前向，零 compute"** | 实际 10 个 `.csh` / 27 compute | ⚠️ **偏离**（受控演进，见 A11） |
| **§0 "v1 不做…彩光…"** | 实现了下界体素彩色光 | ⚠️ **偏离**（受控演进，见 A11） |
| **§8 验收 2：144/90/60 FPS** | **无任何实测帧率数据** | ❌ **未达成**（从 09-06 到 09-17 一直是缺口） |
| **§8 验收 1：1.21.x 与 26.1/26.2 编译零错误** | 仅 26.2 + Iris 1.11.2 单环境验证 | ❌ **未达成**（1.21.x 与 26.1 未冒烟） |
| **§6 双版本冒烟计划（D1）** | `MC_VERSION` 守卫仍为空，`iris.features.required` 未声明 | ⚠️ 依 SC-11 属"零版本分歧代码"的合规状态，但冒烟未执行 |

**判断**：架构与功能规格层面**高度忠于蓝图**。缺口集中在**验收数据**（帧率、双版本）与**边界声明的回填**（compute / 彩光），前者是执行缺口，后者是文档回填滞后。

---

## 6. 性能评估

### 6.1 已受控的热点（`cost_census` 实测输出 + 人工核对）

| 位置 | 上界 | 门控 | 判定 |
|---|---|---|---|
| `deferred.fsh:32` 积水 SSR | 96 步 | `colortex3.a > 0.15`（稀疏水坑遮罩） | **已受控**——这正是 SC-39 的修复目标 |
| `deferred.fsh:81` 雨天空气 | 10 步 | `astraRainFactor < 0.01` 早退 | 可接受 |
| `end_blackhole.glsl:125` 黑洞步进 | 48 步 × 最多 2 次段扫 | 空域跳过 + 候选过滤 | 有界；`cost_census` 已诚实标注"96 不是总工作量" |
| `end_geometry.glsl:175` | 96 步 | 跨步约束 | 有界 |
| `light_shafts.glsl:71` 水下光束 | 7/10 步（选项） | 距离与可见度早退 | 可接受 |
| `diffuse.glsl:265` 阴影过滤 | `SHADOW_FILTER_TAPS` | 背光面整块跳过（`facingAway`） | 已优化 |
| `nether_volume.glsl:90` | 16 步 | transmittance 早退 | 可接受 |
| `raytrace.glsl:63/87` SSR | 24 + 6 步 | 权重为零时不追踪 | 可接受 |
| `end_illumination.fsh:35` | 256 | 仅槽 0 一个像素 | 可忽略 |

### 6.2 本轮新增的性能问题

- **A1（P1）**：`final.fsh` 水下每像素多一次 tonemap + sRGB。这是着色器内部**唯一一处确定性、无条件、可立即回收**的浪费。
- **pass 层面还有更大的三块**（`composite2` 全屏写 0、`composite3` 全屏纯拷贝、`composite4` 全屏 discard 且单次 144 次采样 + 主缓冲恒开 mipmap），典型场景下合计约 **621 万像素/帧**的空转或无效调度。**详见 §12**，那是本节之外独立成章的部分。
- 09-17 轮新增的 `lib/pow.glsl` 整数幂替换方向正确，且该轮已自查出"运行时指数走平方链是负优化"并回退，当前状态（仅字面整数指数走助手）是合理的。

### 6.3 结构

| 项 | 值 |
|---|---|
| 全屏 pass | `composite` / `composite1` / `composite2` / `composite3` / `composite4` / `deferred` / `final`（主世界）；两维度裁剪 3/4 |
| 降分辨率缓冲 | `colortex2` 0.25、`colortex9` 0.75、`colortex6/8` 整数尺寸 |
| 格式声明 | `colortex0/4` = `R11F_G11F_B10F`、`colortex8` = `RGBA32F`、`colortex9` = `RGBA16F`；`colortex2` 已按 09-13 §13.2 改为 `R11F_G11F_B10F` |
| 唯一遗留浪费 | `colortex1` 维度无关分配（A7） |

---

## 7. 顽固问题：一个反复出现的失效模式

这是本次审查**最重要的一节**。它不是代码缺陷，而是流程缺陷——但它已经连续三轮造成缺陷。

### 7.1 事实链

从源码注释与 `qa/session-log.md` 可以直接读到三轮自述：

1. **09-16 轮**：三处错误，共同点是"**注释描述了意图、代码做了别的事，而我的验证只看'能否编译'与'逻辑是否自洽'**"。
   - 植被透光方向写反（`vdotl <= 0.0` 把整个效果判死，**该效果从未生效**）；
   - 水坑反射用了广域潮湿遮罩而非稀疏遮罩，昂贵的 96 步反射仍跑遍全湿世界；
   - `pow` 助手第一版在指数 10 处错达 **1371 倍**。
2. **09-17 轮**：按要求"自己再审一遍"，**又发现四处自身错误，其中三处是修上一轮问题时新引入的**：
   - 把遮罩写进 `colortex0.a`，并注释断言"R11F_G11F_B10F 的 A 通道是未用填充"——**该断言是编造的**，该格式根本没有 alpha，读取恒为 1.0，症状与原错误完全相同；
   - `power()` 是负优化，而上一轮刚给它做过"正确性"背书；
   - 末地光照改动第二次尝试仍未达成目的（可读性收益实测为 **1.00x**）。
3. **09-13 报告 §13.1** 已经纠正过一轮类似问题（"不能从静态扫描得出'没有第二处必挂热点'"、"功能存在不等于视觉完成"）。

### 7.2 判断

**失效模式是稳定的**：断言 → 用"注释读起来对"代替"数值/声明查过" → 编译通过即放行 → 下一轮发现代码做的是别的事。

09-17 轮补的两道校验（数学助手逐点比对、压缩类函数全量程验证单调性）**只覆盖"新写的数学"，没覆盖"对已有系统行为的断言"**——这正是第三轮四处错误里三处的成因。该轮自己也识别到了这一点，并已把断言纳入复核范围（`colortex` 格式与 blend 状态、每个写入通道的读写者、每个 pass 的 RENDERTARGETS）。

### 7.3 建议（这是我认为最该落地的一条）

1. **把"对系统行为的断言"变成可查的事实，而不是注释**。`colortex0.a` 那次错误的根因，是一个人写了"这个格式有未用的 A 通道"而没有去读 `lib/water_buffer_formats.glsl:12`。建议在 `check_pack` 增加一条低成本静态规则：**收集全树所有 `colortex<N>Format` 声明，与所有 `.<a>`/`colortexN.a` 写入点比对，对无 alpha 通道格式的 alpha 写入直接 FAIL**。这条规则能一次性挡住整类"编造的格式断言"。
2. **延续 09-17 已建立的做法**：任何"亮度不变""端点相等""等价替换"的声明，必须附数值验证，不能只写在注释里。
3. **保留"自己再审一遍"这个动作**——它在 09-17 抓出了四处自身错误，是本项目目前最有效的手段。

---

## 8. 建议（按可执行顺序）

| 优先级 | 动作 | 对应 |
|---|---|---|
| **1** | 提交工作区：按 `lib/pow.glsl` 性能轮 / SC-39 积水轮 / 其余视觉轮 + 文档 拆三次提交 | A3 |
| **2** | 重写 `Astra/README.md` 的特性、Profile、已知问题、开发状态四节；**至少先改正被写反的效果三对标方向** | A2 |
| **3** | 修 `final.fsh:88-91` 的重复 tonemap（行为不变，纯消除冗余） | A1 |
| **4** | **性能优化（低风险三项先行）**：`size.buffer.colortex7=0.25 0.25` → `colortex1` 水下光束降 `0.5 0.5` → `deferred.enabled` 条件化 + `ASTRA_SCENE_COPY` 同步。**落地后立即测一次帧率拿首个真实基线** | **§12.9 1→2→3** |
| **5** | **水下光束**：解耦 `visibility` 的方向因子（§11.1.2）→ 修正采样分布 → 圆形判据改方形 → 移除 `solas_water_fog` 的 `glare*16` → 加 `colortex1` 调试视图 | **B1** |
| **6** | **水色深浅**：默认档改为"蓝衰减 < 绿衰减"→ 放宽 16 格深度上限 → 加受控 in-scattering → 把三档实际观感写进 lang | **B2** |
| **7** | 把 `lit.fsh:231` 的 footprint 提到 `if (material == 11u)` 之外 | A4 |
| **8** | 补 `docs/2026-09-17-sc39-puddle-reflection.md`，沉淀三次返工与两道校验规则 | A5 |
| **9** | 给 `check_pack` 加一条规则：无 alpha 通道格式的 alpha 写入 → FAIL（见 §7.3） | §7.3 |
| **10** | 二选一处理 `global → global` include：更新 `design.md` §3.2 决议，或收敛末地子层并在校验器显式放行 | A6 |
| **11** | 回填 `design.md` §12 状态、§0 边界（compute / 彩光例外）、§8 验收项的实际完成情况 | A10 / A11 |
| **12** | 补齐验收数据：三档帧率实测 + 1.21.x / 26.1 双版本冒烟（这是 design §8 第 1、2 项，目前零数据） | §5 |
| **13** | 性能优化中风险项（拿到基线后评估）：水下合成并入 final 删 composite3 → `rainy_air` 降分辨率 → `getBloomTile` 改 mip 采样 | §12.9 4→5→6 |
| **14** | `properties` 的 `colortex1` 段加注释说明维度无关分配；`docs/` 按主题归档 | A7 / A12 |

---

## 9. 已核查并排除（避免重复排查）

| 疑点 | 结论 | 依据 |
|---|---|---|
| `ENTITY_SHADOW_DISTANCE` 是否仍是假控件 | **不是**。它在 `lib/settings.glsl` 内部被 8×5 条件表消费（我的"假控件"扫描会排除 settings.glsl 自身，初判为误报，已人工复核） | `settings.glsl:227-323` |
| `GODRAYS` / `UNDERWATER_PARTICLES` / `VIGNETTE` 全树无 `#define` | **非缺陷**。这是 Iris 对 boolean 选项的标准注入方式（注释掉的 `#define` = 关闭态） | `settings.glsl:124,189,195` + `screen.*` / `profile.*` 双向一致 |
| `VOXY_SUPPORT` 只在 `lib/uniforms.glsl` 被引用 | **非缺陷**，且注释已明示"Iris 保留此选项仅因 uniforms 引用它；真正的 Voxy 集成仍属 C5" | `settings.glsl:203-206` |
| `light_shafts.glsl:95,105` 直接采样 `shadowtex1`/`shadowcolor0` 但无 `SHADOWS` 守卫 | **非缺陷**。整段在 `#ifdef ASTRA_SHAFT_MARCH_PASS` 内，而该宏由 `ASTRA_UNDERWATER_SHAFTS` 派生，后者要求 `SHADOWS` | `settings.glsl:344-350`、`light_shafts.glsl:26` |
| 下界 shadow pass 关闭（`=NETHER_VOXEL_LIGHT`）是否导致下界读到空 shadow map | **非缺陷**。下界走 `nether_lighting`，不传 `shadowPos`，全树 nether 相关文件零 `shadowtex`/`shadowcolor` 引用 | `scene.glsl:223-226` + 全树引用统计 |
| `world1`/`world-1` 缺 `composite2/3/4` | **非缺陷**，是刻意的维度裁剪 | `properties:41-44,57-58,62-63` |
| `lit.fsh` 是否重复写 `gl_FragData[1]`（water pass） | **非缺陷**。water pass 同时定义 `ASTRA_TRANSLUCENT`，`#ifndef ASTRA_TRANSLUCENT` 被跳过 | `lit.fsh:353` vs `:364` |
| 纹理资源缺失 | **全部存在**（7/7） | 磁盘核对 |
| `end_*` 模块依赖是否有环 | **无环**，单向链 `end → end_blackhole → end_system → end_ring → end_geometry` | include 图 |
| 水下光束是否"没接线" | **不是**。composite2 写 → composite3 读 → `solas_water_composite` 消费，宏定义与启用条件全部正确。问题在量级，不在接线 | §11.1.1 |
| 水下光束的编码/解码是否自洽 | **自洽**。编码 `pow(I/128, 0.25)`，解码 `pow(4 抽头均值, 4)*128`，往返误差 <1%（RGBA8 量化后） | §11.1 数值复现 |
| 水上看水下的深度参数是否算错 | **没算错**。`dot(origin - point, faceNormal)` 即垂直水柱高度；折射关闭时走 straight 分支同样调用 `water_surface_medium` | `water.glsl:80,95` |

---

## 10. 本次审查未覆盖的内容

- **游戏内画面正确性**：全部未覆盖（无实机截图比对）。
- **帧率实测**：零数据，`design.md` §8 第 2 项无法判定。
- **Iris 之外的环境**：未评估 OptiFine 兼容性（本包按设计不兼容）。
- **他厂驱动编译**：仅在 RTX 4050 + NVIDIA 572.83 上验证；09-13 §13.1 已把 N2/T1 的跨驱动结论下调为"风险存在但不能断言厂商行为"，本轮未新增驱动证据。
- **多人/服务器场景**：未评估。
- **`_analysis/` 参照包**：5194 个文件未纳入本次审查范围（按项目约定属参考副本）。

---

# 11. 专项：两个长期未达成的水效果根因分析

**应杨间要求补充（2026-09-20）。** 针对"水下光束"与"水上看水下由浅到深青绿→深蓝"两个长期未达成项，做端到端链路核查与数值复现。

**方法**：源码直读 + 离线数值复现（Python 复现 GLSL 公式，只读源码、不改动任何项目文件）。
**纪律**：**无实机画面，本文不宣称"看起来对不对"，只给可离线判定的量级与色相事实。**

---

## 11.1 水下光束（`UNDERWATER_LIGHT_SHAFTS`）

### 11.1.1 先排除接线问题——链路是闭合的

| 环节 | 位置 | 状态 |
|---|---|---|
| pass 启用 | `shaders.properties:33-37` `program.composite2.enabled` = `GODRAYS \|\| (UNDERWATER_LIGHT_SHAFTS && SHADOWS && STRENGTH>0)` | ✅ BALANCED 成立 |
| 宏定义 | `settings.glsl:344-350` `ASTRA_UNDERWATER_SHAFTS`；`scattering.fsh:26` `ASTRA_SHAFT_MARCH_PASS` | ✅ |
| 写入 | `program/scattering.fsh:39` `gl_FragData[0] = water_shafts_march(texcoord)`，`RENDERTARGETS: 1` | ✅ |
| 缓冲尺寸 | `shaders.properties:8-13` 水下光束开时 `colortex1 = 1.0 1.0` | ✅ |
| 读取 | `program/water_composite.fsh:8,19` 读 `colortex1` → `water_shafts_resolve()` | ✅ |
| 消费 pass | `composite3.fsh` → `program/water_composite.fsh`，`properties:39` 恒 `true` | ✅ 在 composite2 之后 |
| 合成 | `lib/solas_water.glsl:106-112` `solas_water_composite(..., shafts)` | ✅ |

**结论：不是没接线、不是没编译、不是时序错。问题纯粹在数值量级。**

### 11.1.2 衰减点 1（主因）：`visibility` 被两个几何互斥的方向因子相乘

`global/water/light_shafts.glsl:47-56`：

```glsl
float VoU = 1.0 - pow(clamp(ray.y, 0.0, 1.0), 1.5);      // 朝上看 → 0
float VoL = pow(clamp(dot(ray, normalize(view_player(lightVector))), 0.0, 1.0), 1.5);  // 不朝太阳 → 0
float visibility = sunGate * 0.85;
visibility *= pow(VoU, 1.5);
visibility *= mix(0.25 + VoL * 0.25, VoL * 0.45, time);
```

太阳在水面**上方**，故 `L.y > 0`。于是 `VoU` 要求视线朝下（否则衰减），`VoL` 要求视线朝上朝太阳（否则衰减）——**两者在几何上无法同时满足**。

正午（`sunY = 0.766`，`time = 1.0`，7 采样）实测：

| 视线姿态 | `VoU` | `VoL` | `visibility` |
|---|---|---|---|
| 水平朝太阳方位 | 1.000 | 0.110 | **0.042** |
| 斜上 17° 朝太阳 | 0.836 | 0.364 | **0.106** |
| 斜上 30° 朝太阳 | 0.646 | 0.536 | **0.107** |
| 正朝太阳 | 0.330 | 1.000 | **0.072** |
| 水平背对太阳 / 向下看 | 1.000 | 0.000 | **0.000** |

**理论上限 0.85，实际最优 0.107 —— 损失 8 倍；常见姿态（水平）只有 0.042，损失 20 倍。**

### 11.1.3 衰减点 2 与 3：采样覆盖不足、边界判据错误

- **采样覆盖只有名义的一半**（`light_shafts.glsl:66-72`）：`maxDist = 40` 名义，但 `minDist = maxDist/SAMPLES*0.5 = 2.857`，实测 7 个样本落在 **1.4 / 4.3 / 7.1 / 10.0 / 12.9 / 15.7 / 18.6 格** —— 只覆盖到 **18.6 格**。源码注释自己也承认"about 17 blocks for the 7-sample preset, not 40"。步距 **2.86 格**远大于光束的横向尺度 → 连续光柱被采样成离散斑块。
- **圆形判据剔除方形缓冲**（`light_shafts.glsl:77`）：
  ```glsl
  if (length(pos.xy * 2.0 - 1.0) >= 1.0) continue;
  ```
  shadow map 是方形 `[0,1]²`，该判据是它的**内切圆** → 四个角 **21.5%** 的采样被无条件丢弃。视线越平、采样点越靠边缘，光束断裂越严重。
  （对照：`global/lighting/shadowmap.glsl:73-74` 的末地分支已经改用方形边界，此处未同步。）

### 11.1.4 衰减点 4：旧的角向亮晕未被移除，与光束同向竞争

SC-33 决议要求"以有遮挡的水下散射替换 `scene.glsl` 的角向亮晕"。`scene.glsl` 的那处确实移除了，但 **`lib/solas_water.glsl:97-100` 的 `solas_water_fog()` 里仍保留**：

```glsl
float glare = clamp(dot(ray, lightDir) * astraSolasShadowFade * 0.5 + 0.5, 0.0, 1.0);
glare = 0.01 / (1.0 - 0.99 * glare) - 0.01;
fog *= (0.1 + solas_sun_visibility() * 0.4)
     * ((0.5 + 0.5 * eyeSky) + glare * 16.0 * astraSolasTimeBrightness * eyeSky);
```

`glare` 用的是 `dot(ray, lightDir)`，与光束的 `VoL` **同源同向**。数值复现（30 格视线、`eyeSky=0.5`、无障碍）：

| 视线姿态 | `glare` | `fog.rgb`(绿) | `color*color` | `+shafts` | **光束占比** |
|---|---|---|---|---|---|
| 水平朝太阳 | 0.016 | 0.161 | 0.229 | 0.070 | 23.4% |
| 斜上 17° 朝太阳 | 0.030 | 0.181 | 0.243 | 0.175 | **41.8%** |
| 斜上 30° 朝太阳 | 0.046 | 0.206 | 0.260 | 0.175 | **40.2%** |
| 正朝太阳 | **0.990** | **1.593** | 0.979 | 0.113 | **10.4%** |

**正对太阳（光束本应最强）时 `fog` 被放大 8.7 倍到 1.59，反而把光束占比压到 10.4%。** SC-33 只做了一半。

### 11.1.5 数值结论与建议

**量级结论**：理想条件下（无障碍、30 格视线、朝太阳）`shafts` 在 gamma 域贡献 **0.07–0.17**，占比 **23%–42%** —— 理论可见。但真实场景叠加遮挡、21.5% 边界剔除、2.86 格稀疏采样后会显著衰减。**按项目纪律（无实机），我不宣称"看不见"；我给出的是四个可离线定位、且方向明确的衰减源。**

**建议（按性价比）**：

1. **解耦方向因子**（收益最大）。水下光束的方向性应只由"视线与太阳夹角"决定，即只保留 `VoL`。`VoU` 的"别朝上看水面"属于界面/Snell 窗的职责，不该做乘性压制。最小改动：把 `pow(VoU, 1.5)` 的指数降到 ≤ 0.5 并加下限（如 `mix(0.35, 1.0, VoU)`），避免把最优姿态压到 0.1。
2. **修正采样分布**：让样本铺满 `maxDist`（去掉 `* 0.5`，或 `minDist = maxDist / SAMPLES`），并把 `UNDERWATER_SHAFT_SAMPLES` 默认从 7 提到 10–12（ULTRA 已是 10）。
3. **圆形判据改方形**：`max(abs(pos.x*2.0-1.0), abs(pos.y*2.0-1.0)) >= 1.0`，与 `shadowmap.glsl:73-74` 保持一致。
4. **移除或大幅衰减 `solas_water_fog` 的 `glare * 16.0` 项**，把角向亮度交给光束——这正是 SC-33 的意图，只做了一半。
5. **加一个可开关的调试输出**（直接把 `colortex1` 显示出来）。当前无法离线区分"没算出来"与"被淹没"，这一个开关能把整类争论变成一次截图可判的事实。

---

## 11.2 水上看水下的深浅过渡（青绿 → 深蓝）

### 11.2.1 路径确认

水上看水下的透射路径：`program/water.glsl:80`（`water_sample_path` 内）

```glsl
if (inWater) color = isEyeInWater == 0
    ? water_surface_medium(color, dot(origin - point, faceNormal))
    : water_medium(color, length(point - origin), astra_water_incident(skylight));
```

- `isEyeInWater == 0`（相机在空气中）+ `inWater`（是水体）→ 走 `water_surface_medium` ✅
- 深度参数 `dot(origin - point, faceNormal)` = 水面片元到床面的**垂直水柱高度** ✅ 计算正确
- 折射关闭时（PERFORMANCE）走 `:95` 的 straight 分支，同样调用 `water_surface_medium` ✅

**结论：路径与深度计算都正确。问题在光谱系数、深度封顶、以及缺少散射项。**

### 11.2.2 根因 1（决定性）：默认档的绿蓝衰减关系与需求相反

`global/water/absorption.glsl:20-30`：

```glsl
#if WATER_CHARACTER == WATER_COLD
    vec3 coefficient = vec3(1.000, 0.2200, 0.0800);   // 绿衰减 > 蓝衰减 → 蓝保留多
#elif WATER_CHARACTER == WATER_TROPICAL
    vec3 coefficient = vec3(2.000, 0.0550, 0.0800);
#else  // WATER_BALANCED —— 默认档
    vec3 coefficient = vec3(1.000, 0.0600, 0.1000);   // 绿衰减 < 蓝衰减 → 绿保留多
#endif
```

`water_surface_medium` 是纯吸收 `radiance * exp(-d * coefficient)`，**衰减系数越小 → 该通道保留越多 → 越深越主导色相**。

复现 `water_surface_medium(vec3(1.0), d)` 的归一化色相：

| 水深 | `WATER_COLD`(0) | `WATER_BALANCED`(1) **默认** | `WATER_TROPICAL`(2) |
|---|---|---|---|
| 0 格 | (0.18, 0.38, 0.44) 偏蓝 | (0.17, 0.43, 0.41) 青 | (0.07, 0.47, 0.46) 青 |
| 2 格 | (0.04, 0.38, 0.58) 偏蓝 | (0.03, 0.51, 0.46) 青 | (0.00, 0.52, 0.48) 青 |
| 5 格 | (0.00, 0.30, 0.70) **偏蓝** | (0.00, 0.56, 0.44) **偏绿** | (0.00, 0.54, 0.46) 偏绿 |
| 8 格 | (0.00, 0.22, 0.78) **偏蓝** | (0.00, 0.59, 0.41) **偏绿** | (0.00, 0.56, 0.44) 偏绿 |
| 12 格 | (0.00, 0.14, 0.86) **偏蓝** | (0.00, 0.63, 0.37) **偏绿** | (0.00, 0.58, 0.42) 偏绿 |
| 15 格+ | (0.00, 0.10, 0.90) **深蓝** | (0.00, 0.65, 0.35) **偏绿** | (0.00, 0.60, 0.40) 偏绿 |

> 判读阈值：绿 > 蓝 ×1.15 记"偏绿"，蓝 > 绿 ×1.15 记"偏蓝"，否则记"青"。

**决定性事实**：

- **`WATER_COLD`（档 0）的轨迹就是"浅处青 → 深处深蓝"**：0 格 `(0.18, 0.38, 0.44)`，15 格 `(0.00, 0.10, 0.90)`。
- **默认档 `WATER_BALANCED` 深处是 `(0.00, 0.65, 0.35)`，绿/蓝 = 1.90 —— 越深越绿，方向相反。**

**也就是说：这个效果已经存在于 `WATER_COLD` 档，用户一直没看到，只是因为默认档的绿蓝系数关系与它相反。**

### 11.2.3 根因 2、3：深度封顶 + 缺少 in-scattering

- **深度封顶**（`absorption.glsl:59-60`）：
  ```glsl
  float appearanceDepth = clamp(depth + 1.0, 0.0, 16.0);
  ```
  水深超过 **15 格**后 `appearanceDepth` 恒为 16，**色相完全冻结**（上表 20 格与 30 格结果与 15 格完全相同）。深水区没有"继续变深"的过渡。
- **只有吸收、没有 in-scattering**（`absorption.glsl:58-62`）：
  ```glsl
  return radiance * exp(-appearanceDepth * water_surface_absorption());
  ```
  对比同文件 `water_transport()`（`:45-51`）有散射源项 `+ incidentLight * scatteringAlbedo * (1.0 - transmission)`。**纯 Beer-Lambert 吸收让三通道同时趋于 0**，深处表现为"发黑的暗水"；真实的深蓝来自水体散射把蓝光送回视线，必须靠散射项。
  注：`program/scene.glsl:56-57` 的注释明确写着 *"Do not add the blue underwater volume source to this branch"* —— 这是当初为防止"水下相机整个变绿"而定的约束，但它同时也把"深蓝"这条路径堵死了。

### 11.2.4 建议

1. **最小改动、收益最大**：对调默认档的绿蓝衰减关系，让**蓝衰减小于绿衰减**。例如 `WATER_BALANCED` 改为 `vec3(1.000, 0.1000, 0.0600)` —— 复现显示 16 格处绿 `0.202` / 蓝 `0.383`，绿/蓝 = 0.53 → **偏蓝**。浅处的青绿由散射与天空反射供给，深段由吸收选择性留下蓝。
   - 若希望保留"浅处更青绿"，更稳妥的是**加深依赖**：用两个系数在 0–6 格与 6 格以上之间插值，让浅段偏青、深段偏蓝，而不是单一指数。
2. **放宽深度上限**：`clamp(depth + 1.0, 0.0, 16.0)` → 32–48，或随 `WATER_ABSORPTION` 缩放，让深水区继续过渡。
3. **给 `water_surface_medium` 加受控的散射源项**，用 `water_scattering_coefficient()`（R 0.011 / G 0.032 / **B 0.076**，天然偏蓝）作为源——这样深处是"蓝"而不是"黑"。
   - **注意**：该系数目前乘 `UNDERWATER_FOG_DENSITY`，接入空气侧路径需单独标定，避免把水下相机的体积也染蓝——这正是 `scene.glsl:56-57` 那条注释要防的，改的时候要同时满足两条约束。
4. **把三档语义写进 lang**：`zh_CN.lang` / `en_US.lang` 目前对 `WATER_CHARACTER` 只写"水色调色板"之类，用户无法知道 **COLD 才是"深蓝"档**。把三档的实际观感（冷=深蓝 / 平衡=青绿 / 热带=浅青）写进注释，这是一个零成本但直接解决"用户找不到"的改动。

---

---

# 12. 性能优化建议（整体）

**应杨间要求补充（2026-09-20）。**

**纪律**：本节全部基于静态分析与数值推算，**没有实机帧率**。所有"预期收益"是按像素数与采样次数推算的量级，不是测量值；凡涉及画面的改动都标注了需实机对拍。

## 12.1 先看全屏 pass 清单：三个 pass 在典型场景下不干活

1080p 单帧全屏像素 ≈ **207 万**。主世界 pass 链的实际工作：

| pass | 程序 | 目标缓冲 | 分辨率 | 相机不在水中、BALANCED 档时的实际工作 |
|---|---|---|---|---|
| `composite` | `water_state.fsh` | colortex6 | **1×1** | 1 像素，可忽略 ✅ |
| `composite1` | bloom 采集 | colortex2 | 0.25 | 13 抽头 ✅ 已优化 |
| `composite2` | `scattering.fsh` | colortex1 | **1.0** | ⚠️ **全屏写 `vec4(0.0)`** |
| `composite3` | `water_composite.fsh` | colortex0 | 1.0 | ⚠️ **全屏纯拷贝** |
| `composite4` | `water_bloom.fsh` | colortex7 | **1.0（未声明）** | ⚠️ **全屏 `discard`** |
| `deferred` | `deferred.fsh` | colortex0 + colortex4 | 1.0 | 介质/SSR/雨空气 ✅（但恒开） |
| `final` | `final.fsh` | 屏幕 | 1.0 | ✅ |

**典型场景下约 414 万像素/帧（composite2 + composite3）是纯浪费，另有 207 万（composite4）在做无效调度。** 这三项是本节收益最大的部分。

---

## 12.2 【收益最大】`composite4` + `colortex7`：单 pass 性能黑洞

**证据链**：

1. `program/water_bloom.fsh` 写 `colortex7`，而 `shaders.properties` **没有 `size.buffer.colortex7`** → 该缓冲是**默认全分辨率**。
2. `computeBloom()`（`bloom_capture.glsl:29-38`）调用 `getBloomTile` **4 次**，每次内含 `6×6` 二重循环、各 **36 次** `texture(colortex0, …)`（`:16-23`）→ 合计 **144 次采样/像素**。
3. 依赖 `const bool colortex0MipmapEnabled = true`（`water_bloom.fsh:5`）→ **主缓冲 colortex0 恒开 mipmap**，每帧额外生成 mip 链，并多占约 33% 显存，而它只服务于这个水下才跑的 pass。
4. `program.composite4.enabled=BLOOM`（`properties:40`）→ BALANCED 档恒开；非水下时每个像素执行 `if (isEyeInWater != 1) discard;`（`:10`），仍是全量片元调度。

**量级**：水下 1080p = 207 万 × 144 ≈ **2.98 亿次纹理采样/帧**。
对照主 bloom（`composite1`，0.25 分辨率 13 万像素 × 13 抽头 ≈ **170 万次**）→ **约 175 倍**。

**根因判断**：Solas 原作的 `computeBloom` 跑在**低分辨率 bloom tile** 上；适配到 Astra 时挂在了全分辨率 pass 上，而分辨率约定没有跟着降下来。这不是算法问题，是**适配时的分辨率失配**。

**建议**：

1. **`size.buffer.colortex7=0.25 0.25`**（首选，一行改动）。水下 bloom 是低频模糊量，降分辨率完全够 → 采样数 2.98 亿 → **约 1860 万**。
2. 或把 `getBloomTile` 的 36 抽头改为高层 mip 单次采样（参照 `global/post/bloom.glsl:104` 的 13 抽头写法），4 tile → 4 次采样。
3. 复核 `colortex0MipmapEnabled` 是否仍需恒开；若 colortex7 已降分辨率，可重新评估其收益比。

---

## 12.3 `composite3`：非水下时是全屏纯拷贝

```glsl
// program/water_composite.fsh:12-26
vec3 color = texture(colortex0, texcoord).rgb;
if (isEyeInWater == 1) { …水下合成… }
gl_FragData[0] = vec4(color, 1.0);
```

`program.composite3.enabled=true`（`properties:39`）**硬编码** → 相机不在水里时（绝大多数时间），这就是 **207 万像素的读 + 写，什么都不做**。

**建议**（按侵入性递增）：

1. **把水下合成并入 `final.fsh`**，删除 composite3。`final.fsh:90` 已经有 `isEyeInWater == 1` 分支（`solas_water_display`），两者语义一致。**需同时把 `composite4` 的水下 bloom 采集顺序一并调整**（bloom 应在合成之后采集），故标为中等风险，需实机对拍。
2. 保留 pass 但降分辨率 —— **不可行**，它写的是 colortex0。
3. 最小改动：在文件头注释写明"非水下时本 pass 为纯拷贝，成本 207 万像素/帧"，避免下次被当成新问题重新查一遍。

---

## 12.4 `composite2`：非水下 + GODRAYS 关时是全屏写 0

```glsl
// program/scattering.fsh:36-49
if (isEyeInWater != 0) {
    #ifdef ASTRA_UNDERWATER_SHAFTS
        if (isEyeInWater == 1) { gl_FragData[0] = water_shafts_march(texcoord); return; }
    #endif
    gl_FragData[0] = vec4(0.0); return;
}
#ifndef GODRAYS
    gl_FragData[0] = vec4(0.0); return;   // ← BALANCED 档走这里
#endif
```

BALANCED 档 `!GODRAYS` + `UNDERWATER_LIGHT_SHAFTS` 开 → `composite2.enabled=true`，相机不在水中时对全屏写 0。

**讽刺的连锁**：正因为水下光束要求 `size.buffer.colortex1=1.0 1.0`（`properties:8-10`），这个"写 0"的 pass 被提升到**全分辨率** —— 一个只在潜水时有效的效果，让 99% 时间里的空转 pass 也变成了全分辨率。

**建议**：

1. **水下光束是低频量**，`colortex1` 用 `0.5 0.5` 即可（`water_shafts_resolve` 本来就是 4 抽头重建）。这样"写 0"与 march 同时降到 1/4。
2. 或把水下 march 迁到 deferred / composite3，令 `program.composite2.enabled=GODRAYS`，非 GODRAYS 档完全不跑该 pass。

---

## 12.5 `deferred` 恒开，且写两个全分辨率缓冲

- `program.deferred.enabled=true`（`properties:68`）**硬编码**，而 `design.md` §2.2 要求启用条件为 `SSR || 折射 || WATER_ABSORPTION > 0`。三档 `WATER_ABSORPTION=100` 故恒开**当前合规**，但用户把三项水效果都关掉时它仍在跑。
- `/* RENDERTARGETS: 0,4 */` → 每像素写 2 个 `R11F_G11F_B10F`（各 32 bit）= **8 字节 × 207 万 ≈ 16.6 MB/帧 纯写入**，不含读取与 `ASTRA_SCENE_COPY`（`settings.glsl:353` 无条件定义）带来的 colortex4 常驻显存。
- **建议**：`program.deferred.enabled` 改为 `#if defined SCREENSPACE_REFLECTIONS || defined SCREENSPACE_REFRACTION || WATER_ABSORPTION > 0`，并让 `ASTRA_SCENE_COPY` 随同一条件定义。

## 12.6 `deferred` 内的两块逐像素重活

- **`puddle_reflection`（`deferred.fsh:32`，96 步）**：SC-39 已用稀疏水坑遮罩（`colortex3.a > 0.15`）门控，**当前受控**。若实机仍偏重，可改为按距离自适应步数（近 96 / 远 32）。
- **`rainy_air`（`deferred.fsh:81`，10 步）**：每步 `astra_cloud_transmission`（云噪声）+ `shadow_coverage` + `shadow_opaque_visibility`。**雨天全屏每像素最多 10 次云噪声 + 10 次阴影采样**，是雨天掉帧的主要来源。它的贡献是低频体积辉光 → 建议降到半分辨率，或步数减到 6。画面需对拍。

## 12.7 雨天的纹理采样成本

`lit.fsh` 雨天路径的不透明像素额外采样：

| 来源 | 采样 | 次数 |
|---|---|---|
| `weather.glsl:29-30` `astra_puddle` | `solasWaterNoise` | 2 |
| `weather.glsl:113` `astra_rain_ripple` | `astraRipple1` | 1 |
| `weather.glsl:114-115` | `astraRipple2`（`smoothstep(0.75,1.0,strength)*0.15`） | 条件 1 |

合计 **3–4 次额外纹理采样/像素**；其中 `astra-ripple-2/3.png` 是 128×7680 的大图（556 KB / 848 KB），采样局部性差。

**建议**：`astra_puddle` 的两层噪声（0.65 / 0.35 权重）可合并为一层，收益差异不明显；`astraRipple2` 的 `smoothstep(0.75,1.0,…)*0.15` 改成硬阈值 `if`，可省掉大量像素的一次大图采样。

## 12.8 其它（P3）

| 项 | 现状 | 判断 |
|---|---|---|
| 阴影软件路径（`diffuse.glsl:285-290`） | 4 lobes × 2 gather = 8 次 `textureGather` + 4 次 `shadowcolor0` fetch；已有 `facingAway` 早退（约一半像素跳过） | **保持默认**。`SHADOW_FILTER_MODE=1` 是 8 抽头替代，但按 09-13 §13.1 的修正"等价性限于标量过滤模型"，等实机对拍后再动 |
| 末地 | `end_sky_buffer` 0.75 分辨率 ✅；黑洞 48 步 × 最多 2 次段扫 ✅ 有界 | 末地最重的仍是全分辨率的 deferred 与 final，可沿用 12.5/12.6 的结论 |
| 下界 | `nether_volume` 16 步 + `nether_colored_light` 8 次 texelFetch；shadow pass 仅在 `NETHER_VOXEL_LIGHT` 时启用 ✅ | 合理。体素光已有 compute 版本 ✅ |
| `lib/pow.glsl` 整数幂替换 | 09-17 已落地，且已自查回退"运行时指数走平方链"的负优化 | ✅ 无需再动 |

---

## 12.9 优化执行顺序（按收益 / 风险比）

| 序 | 改动 | 预期收益 | 风险 |
|---|---|---|---|
| **1** | `size.buffer.colortex7=0.25 0.25` | 水下最大单项：2.98 亿 → ~1860 万次采样 | **低**（纯分辨率，模糊量本就低频） |
| **2** | `colortex1` 水下光束降到 `0.5 0.5` | composite2 的"写 0"与 march 各降 4 倍 | **低**（4 抽头重建本来就在做） |
| **3** | `program.deferred.enabled` 条件化 + `ASTRA_SCENE_COPY` 同步 | 三项水效果全关时省 ~16.6 MB/帧 写带宽 | **低** |
| **4** | 水下合成并入 `final.fsh`，删 composite3 | 省一个 207 万像素的全屏拷贝 | **中**（需调整 bloom 采集顺序，要对拍） |
| **5** | `rainy_air` 降半分辨率或减到 6 步 | 雨天掉帧主因 | **中**（画面需对拍） |
| **6** | `getBloomTile` 36 抽头改 mip 单次采样 | 水下再由 ~1860 万 → ~50 万 | **中**（模糊核形状会变，需对拍） |

**建议先落地 1 → 2 → 3（三项均为低风险、可独立回滚），测一次帧率拿到首个真实数据点，再评估 4/5/6。**

之所以强调这个顺序：本项目**至今零帧率数据**（design §8 第 2 项），任何"优化"在没有基线前都无法证明是收益。先拿基线，再动中风险项。

---

---

# 13. 交叉核验：GLM-5.3-Flash 与 Qoder 两份报告的取舍

**应杨间要求补充（2026-09-20）。** 对象：`docs/2026-09-20-glm53flash-full-review.md`、`docs/2026-09-20-qoder-full-review.md`。

**方法**：对两份报告的 P1/Important 与主要 P2 逐条回源码复现证据，分四类处置——✅ 采信（我复现了证据）／⬆️ 升级或修正（证据成立但定性、量级或适用范围需调）／❌ 不采信（有反证）／⚠️ 需实机定论。
**纪律**：不改代码；核验只引用源码行号与可离线复算的算术。

---

## 13.1 采信，且是我自己的报告漏掉的（补入，按严重度）

### C1（P1）`lit.fsh:362` —— SC-39 引入的静默回归，一条语句废掉 colortex5 的 rgb 与 a

两份报告都指出，Qoder 补上了我没想到的一环（blend）。我核验后确认**比 GLM 说的更严重**：

| 环节 | 位置 | 事实 |
|---|---|---|
| 水 pass 的 `gl_FragData[1]` 是 colortex5 | `lit.fsh:23` `RENDERTARGETS: 0,5` | ✅ |
| SC-39 把 `.a` 改写 | `lit.fsh:362` `gl_FragData[1].a = material == 0u ? clamp(puddle,0,1) : 0.0` | 水面 `material=1u` → **a = 0** |
| blend 因子用 SRC_ALPHA | `shaders.properties:54` `blend.gbuffers_water.colortex5 = SRC_ALPHA ONE_MINUS_SRC_ALPHA ONE ONE_MINUS_SRC_ALPHA` | **src.a = 0 → colortex5.rgb 也完全不写** |
| 唯一消费者被废 | `water_state.fsh:19` `if (data.a < 0.5) continue;` | 20×12 = 240 个网格样本恒跳过 → colortex6 永不更新 |
| 三条注释断言与代码相反 | `lit.fsh:341 / 346-349` | "Nothing reads colortex3.a""has no reader""translucents and weather: 0 via the else-branch" —— 全伪 |

SC-39 之前 `.a` 是 `1.0`（水面有效性标志），blend 正常写入；**这一行改动同时让 rgb 与 a 双双失效**。

**我在 §9「已核查并排除」里没有覆盖这条，是我的遗漏。** 严重度 P1：契约破坏 + 三处失实注释，且正是本项目反复出现的失效模式（§7）。建议按 Qoder §3.7 Step 1 处理（水面有效性改走 colortex5.b 共位打包，或水 pass 用第三槽），并把 `blend.gbuffers_water.colortex5` 改为 `off`。

### C2（P1）末地强制暗角与抖动，`VIGNETTE` / `DITHERING` 在末地失效

```glsl
// global/post/grading.glsl:156-173
vec3 apply_vignette(vec3 displayColor, vec2 screenUV) {
    #if defined DIMENSION_END
        return displayColor*(1.0-0.08*falloff);     // ← 抢占 #elif
    #elif defined VIGNETTE
        float falloff = pow(length(offset) * VIGNETTE_STRENGTH, VIGNETTE_FALLOFF);
```
`apply_output_dither`（`:181-193`）是同构写法，`#if defined DIMENSION_END` 排在 `#elif defined DITHERING` 之前。后果：

- 末地固定 **0.08** 暗角，`VIGNETTE_STRENGTH` / `VIGNETTE_FALLOFF` 全部失效；
- 末地固定 **1/255** 抖动，`GRADING_DITHER_STRENGTH` 失效；
- 三档 profile 均为 `!VIGNETTE`（`properties:166-168`），`settings.glsl:195` 亦注释掉 → **用户关掉的选项在末地变成写死值**；
- design §4.4 把"暗角（默认）"列为**不做项** → 末地强制暗角与蓝图意图直接冲突。

严重度 P1：控制项无效，与 N1 同类的"假旋钮"。建议：End 分支降为**对选项结果的叠加**（先按选项算，再追加最小暗角），而不是抢占 `#elif` 链。

### C3（P1）叶片透光乘子是"变暗"，不是"增益"

`diffuse.glsl:192-193`：
```glsl
visibility *= mix(vec3(mix(0.30, 0.62, sssTransmission)), vec3(1.0), sssTransmission);
```
展开 = `0.30 + 1.02t − 0.32t²`。**t = 0（无透射）时乘 0.30** —— 叶片被压到 30%，而 `SSS_STRENGTH` 越高（t→1）反而回到 1.0。语义与"透光增益"相反，也与 design §4.1 的 SSS 描述不符。

注：09-16 轮修的是"方向写反（效果从未生效）"，这条是**幅度语义**问题，两者不同，不是重复。建议改为 `mix(vec3(1.0), 1.0 + gain, t)`，让 t 只加不减。

### C4（P2，实为性能 P1）`puddle_reflection()` 在 `mix` 实参位置无条件求值

```glsl
// program/deferred.fsh:146-147
source = mix(source, puddle_reflection(playerPos, n), standingWater*upFacing*rippled*fresnel);
```
`mix` 的 `b` 实参**无条件求值** → 即使权重为 0，**96 步 + 6 步细化照跑**。

**这修正了我 §12.6 的判断。** 我在那里写"SC-39 已用稀疏水坑遮罩门控，当前受控"——**过于乐观**：`standingWater > 0.15` 只挡住 4 个因子里的 1 个，`upFacing` / `rippled` / `fresnel` 三个都不挡函数调用。与 §12.4 的 F2（半透明覆盖天空的像素）叠加后，雨天这部分浪费比我在 §12 估计的更大。

建议：把四个条件合并进 `if` 再调用。这是全包最容易做、收益最直接的性能修复之一。

### C5（我自己的结论需下调）水下光束量级：我漏算了焦散 c³ 这一层

我在 §11.1.5 写"理想条件下 `shafts` 贡献 23%–42%，理论可见"。**我的模拟把 `astra_water_caustics_shaft_at` 假设成了 1.0，漏掉了这一层衰减。** 核验：

```glsl
// caustics.glsl:109（水下 isEyeInWater=1）
return mix(caustics * 0.16 + 0.2, 1.0, 0.3 - 0.3 * float(isEyeInWater));  // → caustics*0.16 + 0.2
// :118  astra_water_caustics_shaft_at = c * c * c
```
典型 `c³ ≈ 0.08–0.5`（GLM R-F 估 0.008–0.074、Qoder F-04 估 0.06–0.5，区间有重叠）。乘上后 `integral` 从 ~0.17 降到 ~0.02–0.08，`shafts` 占比从 23–42% 降到 **约 3–15%**。

**处置**：以两份报告为准，**我 §11.1.5 的"理论可见"下调为"处于不可见边缘"**。GLM 与 Qoder 在这一点上都比我的估计更接近真相。

### C6（性能）焦散被放进光束循环 —— 全包最大单项成本，我 §12 的排序要修正

取样链逐层核验：

| 层 | 位置 | 取样数 |
|---|---|---|
| `solas_water_height` | `caustics.glsl:14,15` 两次 `textureLod` | 2 |
| `astra_wave_normal_at` | `:56,:57` 各两次 `solas_water_height` | 4 × 2 = **8** |
| `astra_water_caustics_focus` | `:94-95` 3×3 网格 × `astra_wave_normal_at` | 9 × 8 = **72** |
| `astra_water_caustics_shaft_at` | `:117` 调 focus 后立方 | **72（每光束样本一次）** |

- `UNDERWATER_SHAFT_SAMPLES=7`（默认）→ **504 次取样/像素**
- `=10`（ULTRA）→ **720 次/像素**
- 对比我 §12.2 认定的最大项 `composite4`（144 次/像素）→ **光束 march 还大 3.5–5 倍**

Qoder 的 72 次是对的；GLM 的"9tap×2fetch ≈ 18"漏算了 `astra_wave_normal_at` 内部的 4 次高度采样。

**处置**：**水下最贵的不是 composite4，是 composite2 的光束 march。** 我 §12 的排序修正为：`光束焦散（504–720） > composite4（144）`。且 §12 第 1 项建议（colortex7 降分辨率）仍然成立，但不再是唯一最大项。

---

## 13.2 采信但需调整定性的

| 项 | 我的核验 | 处置 |
|---|---|---|
| GLM F2（积水反射天空像素） | 纯天空像素 `depth >= 0.999999`，被 `deferred.fsh:106` 挡住，**不进入**分支。只有**半透明覆盖天空**的像素（雨丝/粒子/信标光柱，`RENDERTARGETS: 0` 不写 colortex3 但写 depthtex0）才命中 | ✅ 采信，但**适用范围收窄**为"半透明覆盖天空的像素"，不是"所有天空像素" |
| Qoder F-02（deferred vs 半透明顺序） | design 与历史 audit 断言"deferred 先于半透明"，而 `deferred.fsh:107-108` 消费 `gbuffers_hand` 写的 HAND 位 —— 两条断言确实互斥 | ⚠️ **需实机探针定论**。Qoder 自己也标了"未做实机验证"。**不采信任何一方的结论** |
| Qoder F-07（composite3 同缓冲读写 UB） | Iris 对 colortex 有 ping-pong（flip），历史 audit §12.9 已记录"flip 由引擎按写入才翻转管理" | ❌ **不采信"UB"**。`:23` 的 `clamp(color,0,1)` 是 Solas 域适配（其 composite 期望归一化输入），也非缺陷 → 降为 P3 |
| GLM F5 / Qoder F-36（pow 残留） | 我的全树扫描：字面整数指数 `pow` 约 **30 处**（fog/twilight/end_system/lit/nether/…）；GLM 计 23、Qoder 计 6 | ✅ 采信"约定未完整迁移"这一结论；**数量以我的扫描为准** |
| Qoder F-11 / 历史 T11（`fade=1.0`） | 确凿四处（`surface.glsl:201,213,233,258`） | ✅ 采信。历史 13.3 以"可读性"为由不采纳；**Qoder 的性能角度（远处水面永远按最近档算）是新论据** → 升为 P2 |
| Qoder F-30（基线锚点） | 核验：BALANCED 与 settings.glsl 逐项比对，**唯一偏离项是 `SSS_STRENGTH`（settings=100 / 三档=60）**，其余 66 项一致 | ✅ 采信。这是基准测试的锚点问题，改为"默认值对齐 profile"或在注释列出偏离项 |
| Qoder F-23（版本不一致） | 确凿：`#version 430` 用于 10 个文件（`world-1/shadow.vsh` + 9 个 `shadowcomp*.csh`），其余 159 个是 400 | ✅ 采信为 P3。compute 用 430 合理，**但 `shadow.vsh` 与 root/world1 不同版本应统一** |
| Qoder F-28/F-32/F-33（死链） | 核验：`biomeTemperatureSmooth`、`biomeHumiditySmooth`、`sunrise`、`shadow_water_depth`、`water_volume_state` 全树 **0 消费者**；`lib/noise.glsl` 三个导出函数 0 外部调用 | ✅ 采信。均为"注释承诺 × 代码未接"的实例 |

## 13.3 三份报告的一致性矩阵

| 结论 | 混元四（我） | GLM-5.3-Flash | Qoder | 状态 |
|---|---|---|---|---|
| 无 P0 | ✅ | ✅ | ✅ | **三方一致** |
| 水下光束：链路闭合、问题在量级而非接线 | ✅ | ✅ | ✅ | **三方一致** |
| 方向门 `VoU × VoL` 几何互斥 | ✅ 最优 0.107 | ✅ 正午向下看 = 0 | ✅ 正午恒 0 | 一致；GLM/Qoder 的**姿态更贴近实际**（俯视海底才是典型） |
| 水色：默认档绿蓝系数反了，COLD 档才是深蓝 | ✅ | ✅ | ✅ | **三方独立得出同一结论** |
| 深度 clamp 16 冻结 / 缺 in-scatter | ✅ | ✅ | ✅ | **三方一致** |
| 三个全屏 pass 空转 | ✅ §12 | 未提 | 部分（F-12/F-18） | 我独有 |
| composite4 144 抽头 + colortex0 恒开 mipmap | ✅ §12.2 | 未提 | 未提 | 我独有 |
| 焦散 72 次 × 光束样本 = 504–720 | ❌ 漏 | ❌ 低估为 18 | ✅ 72 | **Qoder 独有且正确** |
| `lit.fsh:362` 缓冲写错 | ❌ 漏 | ✅ F1 | ✅ F-01（更完整） | 两家独有 |
| 末地强制 vignette/dither | ❌ 漏 | 未提 | ✅ F-27 | Qoder 独有 |
| 叶片透光乘子反了 | ❌ 漏 | 未提 | ✅ F-08 | Qoder 独有 |
| 工作区未提交 | ✅ 39+26 | ✅ 42 | ✅ 74 | 口径不同，结论一致 |
| 零帧率数据 / 实机积压 | ✅ | ✅ | ✅ | **三方一致** |

## 13.4 必要性结论：该做的与不该做的

**该做（两方以上一致 + 我复现了证据）**

1. `lit.fsh:362` 改道 + `blend.gbuffers_water.colortex5=off` + 删三条失实注释（C1）
2. 末地 vignette/dither 降为叠加，不再抢占 `#elif`（C2）
3. 叶片透光乘子改"只加不减"（C3）
4. `puddle_reflection` 调用移入 `if` 内（C4）
5. 光束：方向门改用 `refractSun` + 焦散降到单 tap（72→~10）+ 加 `colortex1` 调试视图（§11.1.5 + C5/C6）
6. 水色：默认档谱序改向 + 放宽 16 格 + 加受控 in-scatter（§11.2）
7. **先提交、再测一次帧率拿基线**（三份报告都把它列为前置）

**不该做（我判断为过度或证据不足）**

- ❌ 不要因为"光束看不见"就降低 `UNDERWATER_SHAFT_SAMPLES`（Qoder §7.3 同）—— 那是"少花钱买看不见的东西"，掩盖真问题
- ❌ 不要采信"composite3 同缓冲读写是 UB"—— Iris 有 ping-pong
- ❌ 不要在修 F-19（`caustics.glsl:37` 的 `#endif` 提前闭合）/ F-23 之前做大范围重命名或风格统一 —— 会让下一次 diff 审查失效
- ❌ 不要把 `cost_census` 硬接成 check_pack 门禁 —— 09-13 §13.3 的理由仍成立（无配置预处理、调用图、计时的工具不能充当保证）
- ⚠️ F-02（pass 顺序）不要据任一方的推断改代码 —— 先做实机探针

**我对自己结论的三处修正**（记录在此，避免下次沿用旧值）

| 原结论 | 修正后 |
|---|---|
| §11.1.5 光束"理论可见，贡献 23–42%" | 漏算焦散 c³，下调为 **3–15%，处于不可见边缘** |
| §12.2 "composite4 是最大单项（144 次/像素）" | **光束焦散 504–720 次/像素更大**，排序修正 |
| §12.6 "积水反射已受控" | 门控只挡 4 个因子中的 1 个，**另外 3 个不挡函数调用** |

---

*本报告由混元四完成。审查过程中未对项目任何代码文件、配置文件或资源文件做任何修改。*
*§11 的数值为离线复现（Python 复现 GLSL 公式），非实机测量；§12 的收益为按像素数与采样次数的推算；§13 的核验只引用源码行号与可离线复算的算术。三者均不宣称画面结论。*
