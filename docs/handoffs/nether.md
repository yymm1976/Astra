# nether → 主任务：公共接入交接单

本文件是 `nether` worktree 向主任务（水体 / 公共照明 / 阴影 / 合成）申请公共接入的唯一出口。
任务范围见 `docs/parallel-development/nether.md`。**不通过直接编辑共享文件绕过边界。**

## 填写字段（与任务书一致，不得省略）

- **接口**：需要主任务提供的函数 / uniform / 变量名，写准确名称
- **调用位置**：文件路径 + 行号 或 shader 阶段
- **参数**：类型、取值范围、单位、语义
- **原因**：不这么做会怎样；为什么无法在本 worktree 内解决
- **本侧已完成**：`nether` 侧已经改动的文件（仅限 `Astra/shaders/global/dimension/nether.glsl` 及 `global/nether/`）
- **主任务侧待办**：需要对方具体改什么

---

## 上报清单（按处理方分类，可直接转交）

### A. 需要主任务改公共文件 —— 3 条，且都是「不给我就抄不动」

| 编号 | 需要什么 | 落在哪个公共文件 | 不给会怎样 |
|---|---|---|---|
| **P-001** | 熔岩专属材质 id | `program/lit.vsh:25-29` | 参考最有效的防刺眼手段（`lmCoordM = vec2(0.0)`，不让光源被自己的光照亮）无法实现。**默认配置下参考就靠这个 + `×0.84`，我们两条都没有。** |
| **P-002** | `uniform float screenBrightness;` | `lib/uniforms.glsl` | 下界光照无法随游戏内亮度设置变化；本侧只能用写死的 0.5（一个猜测值），与参考行为不一致 |
| **P-003** | 5 个下界生物群系布尔 uniform | `shaders.properties` | 只能用参考的模式 2；参考的**默认**模式 3（五张硬编码调色板 + 15 帧平滑过渡）抄不了 |

三条的完整字段（接口 / 调用位置 / 参数 / 原因 / 本侧已完成 / 主任务侧待办）见本文件下方对应章节。

### B. 需要架构师拍板 —— 3 条 design.md 冲突

| # | 事项 | 冲突点 |
|---|---|---|
| 1 | **熔岩光照的高度/深度锚定已删除** | design.md 4.5 明写「随高度/深度变化，贴近熔岩面更浓更亮」；参考的熔岩项**没有高度项**，它的垂直变化在 `netherStorm`（锚点 Y=28，下方衰减 10×） |
| 2 | **暗区呼吸已删除** | design.md 4.5 的 Astra 自有项，参考无对应机制 |
| 3 | **`nether_sky()` 渐变天空 / `nether_fog()` 熔岩加法：尚未动，等指示** | 参考两者都是 `netherColor` **平铺**；照抄即删 design.md 4.5 的两条要求 |

### C. 本侧已做但**没有画面验证** —— 3 条不确定度必须如实转述

| # | 结论 | 不确定度 |
|---|---|---|
| 1 | 混合律由加法改为「平方和再开方」 | **确定**：这是参考 `mainLighting.glsl:613-616` 的原文，不是估计 |
| 2 | 「Astra 环境光比参考暗约 18 倍」 | **估计，非实测**。依据：两包 `EXPOSURE`/`TM_EXPOSURE` 都是 1.00、调色白点都在 1 附近 → 比例大致可比；但两包的 tonemap 算子不同（Astra 自有 vs 参考 Uncharted2），所以这个倍数只能当量级参考 |
| 3 | 移植后的视觉结果 | **完全未验证**。没有 Iris 实例，也没有把改动同步到任何游戏实例。编译通过（`linked=234 failed=0`）**不代表画面达标**，任务书对此有明确禁令 |

### D. 结构上无法照抄 —— 2 条，属能力缺口而非参数问题

1. **`netherStorm` 的体积 raymarch**：`sampleCount = maxDist / 8`，256 格 = 32 次采样 × 4 倍频噪声。
   与 design.md 5「前向、零 compute」直接冲突。
2. **彩色光体积（`coloredLightFog` + `lightVoxelization`）**：参考默认关闭，但整套需要 Iris 自定义图像通道，
   属新增基础设施。

### E. 参考位置（其它分支也可用）

Complementary r5.9 已复制到主目录只读参考区：

```
C:\Users\杨铭\Desktop\MC模组开发\Astra光影开发\_analysis\Complementary r5.9\
    Reimagined\shaders\...     （426 个文件）
    Unbound\shaders\...        （426 个文件）
```

来源 Modrinth（`complementary-reimagined` / `complementary-unbound`），版本 r5.9，2026-09-02。
`/_analysis/` 已 gitignore，不进版本控制。两个风格源码完全一致，只有默认设置不同。

---



## ⚠ 先更正两条已作废的条目

本文件此前登记的 H-001、H-002 建立在同一个**错误前提**上：以为下界的 `lit.fsh` 会走
`global/lighting/diffuse.glsl` 的 `diffuse_lighting()`。核实源码后该前提不成立，两条均**撤回**。

**依据**（`program/scene.glsl:171-201`，`astra_light()`；**行号为撰写当时**，见下条更正）：

```glsl
#if defined DIMENSION_NETHER
    NetherParams params = NetherParams(fogColor, nightVision, astraHeldLightBase);
    return nether_lighting(albedo, normal, playerPos, blocklight, emissive, portal,
                           frameTimeCounter, params);      // ← 第 178 行，直接返回
#elif defined DIMENSION_END
    ...
#else
    LightParams params = ...;
    if (isEyeInWater == 0 && shadow_water_depth(playerPos, shadowPos) > 0.0) {
        water_reference_lighting(params.skyAmbient, params.directLightSurface);  // ← 第 191 行
    }
    ...
    vec3 color = diffuse_lighting(...);                     // ← 第 198 行
#endif
```

- **H-001 撤回**：`diffuse.glsl:238` 的 `solasMinLight` 改动位于 `diffuse_lighting()` 内部，
  下界在 178 行就已返回，**永远走不到**。下界与 `MIN_AMBIENT_COLOR` 的接触点只有两处
  ——`ambient_strength()`（返回标量 `0.67 + y*0.33`，`diffuse.glsl:85-87`）和本侧自身的
  下限项——两者同源，**不存在口径分裂**。`end.glsl` 同理。
- **H-002 撤回**：`program/scene.glsl:190-193` 的 `water_reference_lighting()` 位于 `#else`
  分支内，下界不可达。`reference_light.glsl` 虽然在第 15 行被所有维度 include，但里面只有
  纯函数、无副作用、下界不调用它。

**2026-09-21 复核（上面的行号不重写，就地登记）**：`astra_light()` 现为
`program/scene.glsl:218-250`，下界早返回在第 **225** 行——H-001 的论证照旧成立。
`reference_light.glsl` 的 include 现在在 `scene.glsl:22`。上表引的那行
`if (isEyeInWater == 0 && shadow_water_depth(...))` **在今天的源码里已经不存在**：
`shadow_water_depth()`（`global/lighting/shadowmap.glsl:225`）与
`water_reference_lighting()`（`global/water/reference_light.glsl:123`）经逐字节全包扫描
各只有 1 处出现，都是定义本身，全包零调用者。于是 H-002 的结论比当初的论证更强——
不只是"下界不可达"，而是所有维度都不再经过它。两条撤回都不需要翻案；改动的只是
证据的行号，以及"上表那段代码是当前源码"这一条不再成立。

**2026-09-21 B3 后续**：`reference_light.glsl` 与其在 `scene.glsl:22` 的 include 已**删除**（同一扫描确认零调用），H-002 的证据链随之终结 —— 上文"在第 15 行被所有维度 include"与"include 现在在 `scene.glsl:22`"两处描述的是删除前的状态。`shadow_water_depth()`（`global/lighting/shadowmap.glsl`）同样零调用者，但它的删除需要改 `shadowmap.glsl`，不在本单白名单内，**只登记不删**。

**2026-09-21 卡 D 后续（本行所依赖的第二个符号也删了）**：`shadow_water_depth()` 已**删除**，改动面 = `global/lighting/shadowmap.glsl` 的第 223–237 行（T10 留下的"零调用/删除属于那个决策"标死注释 5 行 + 函数 10 行），删除后文件 243 → 227 行；全仓 `grep shadow_water_depth` 在 `Astra/` 下**零出现**（此前是"1 处定义 + 0 调用"），默认档编译门复跑 `failed=0`。**路径更正**：上文 `:105` 写的 `global/lighting/shadowmap.glsl:225` 与卡 D 工单写的 `program/shadowmap.glsl` **都不是删除时的位置**——实测定义在 `global/lighting/shadowmap.glsl:228`，`program/shadowmap.glsl` 这个文件在包内**不存在**。H-002 的两条撤回至此全部落到"符号已不存在"，本段与上文 B3 段共同构成该决策的完整记录。

---

## 尚未解决（本轮遗留，需目视决策）

### N-001 熔岩海附近的雾密度不随高度/深度变化

- **状态**：未实现，未擅自补上
- **位置**：`global/dimension/nether.glsl` `nether_fog()` 内，`fogFactor` 与 `proximity`
- **现状**：`fogFactor` 在 `proximity` 计算之前就已定稿，`proximity` 只影响雾的颜色与云层调制。
  原注释写着「denser AND brighter close to the sea」，**只有 brighter 是真的**，注释已在本轮改正。
- **参数**：若要补上密度项，可用 `fogDensity += k * proximity * (1.0 + nether_lava_submersion(worldY))`，
  `k` 的量级参考 `NETHER_FOG_NEAR_COEFF = 0.0040`（每格）。取满时 `concentration = 2.0`，相当于每格 +0.008。
- **原因**：熔岩海上方的能见度是空间雾最直观的一环，加密度会明显缩短可视距离，
  **属于必须看画面才能定的量**，在无 Iris 实例（SC-6）的前提下不猜。
- **本侧已完成**：注释改正，行为未变
- **待办**：主任务或用户给出目标能见度，或授权本侧给一个保守初值再目视迭代

### N-002 近中性生物群系在熔岩海附近仍有残留浅白

- **状态**：已大幅收敛，未完全消除
- **位置**：`nether.glsl` `nether_fog()` 的加法辉光项
- **参数**：以灵魂沙谷一类近中性 tint 为例（`normalize()` 后约 `0.577`，四次方根后约 `0.871`），
  在 `concentration` 取满 `2.0`（熔岩面以下）、云层 `cloudy` 取满时，最终送进
  `mix(sceneColor, fog.rgb, fog.a)` 的雾色：

  | | R | G | B |
  |---|---|---|---|
  | 改前 | 1.92 | 1.17 | 0.96 |
  | 改后 | 1.10 | 0.89 | 0.82 |

- **原因**：剩下这部分是**中性 tint 本身的性质**，不是可算的溢出。该 tint 三通道几乎相等，
  云层项与天空项又按 tint 等量加到三个通道上，所以即便峰值压回 1 附近，
  颜色仍然接近中性亮色。要真正压下去只能降低 `NETHER_CLOUD_FOG_SCALE`（现 0.10）
  或辉光强度，而那两个数是观感量，**需要画面**。
- **本侧已完成**：见「本轮已完成」三条
- **待办**：目视决定是否继续压低云层/辉光幅度；若压低，注意 4.5 要求的「随高度/深度变化」
  会一起变弱

### N-003（低优先）下限亮度耦合到共享文件

- **状态**：登记
- **位置**：`nether.glsl` `nether_lighting()` 的 `floorLuma`
- **参数**：`floorLuma = dot(MIN_AMBIENT_COLOR, vec3(0.2126, 0.7152, 0.0722))`，
  `MIN_AMBIENT_COLOR = (MIN_AMBIENT * 0.001) * MIN_AMBIENT_TINT`（`lib/colors.glsl:49`）
- **原因**：本侧现在只取 `MIN_AMBIENT_COLOR` 的**亮度**、把色相换成生物群系 tint。
  如果主任务将来改动 `MIN_AMBIENT_TINT`，本侧下限的亮度会跟着变——这是预期的耦合
  （用户选项的数值语义必须一致），但**改动前请知会一声**。
- **本侧已完成**：无
- **待办**：无，仅知会

---

## 本轮已完成（均在本 worktree 内，仅动 `Astra/shaders/global/dimension/nether.glsl`）

### 参考基准：Complementary r5.9（2026-09-02）

已下载到 `Astra并行开发/nether/_analysis/complementary/`（`.gitignore` 已忽略，不进版本控制），
含 `Reimagined` 与 `Unbound` 两个风格，源码在各自的 `shaders/` 下。

用户红线是「岩浆一定不能又红又亮」。参考对熔岩的处理如下：

| 项 | Complementary r5.9 | Astra 改动前 |
|---|---|---|
| 熔岩色常量 | `lib/common.glsl:815` `lavaLightColor = vec3(0.15, 0.06, 0.01)` | `vec3(1.60, 0.42, 0.08)` |
| 色相比 | 1 : 0.4 : 0.0667 | 1 : 0.2625 : 0.05（更红） |
| 熔岩项位置 | `mainLighting.glsl:519` 加进 ambient，再乘 albedo | 同（加进 lighting，再乘 albedo） |
| 峰值贡献 | `(0.259, 0.1035, 0.0173)`（含基础 ambient 里的 `0.5*lavaLightColor`） | `(0.96, 0.252, 0.048)` |
| 熔岩方块自身 | `specificMaterials/terrain/lava.glsl:1` `color.rgb *= 0.84`（**变暗**）；`:15` `lmCoordM = vec2(0.0)`（不被自己的光照明）；`:16` 发光强度由自身亮度驱动 | 被 `NETHER_EMISSIVE_BOOST = 1.35` **提亮** |

峰值 R 0.96 对参考的 0.259 是 **3.7 倍**，对参考的定向项 0.1575 是 **6.1 倍**；且更偏红。
位置没错（参考的熔岩项同样不做距离衰减），**是量级错了**。

1. **熔岩辉光的量级与色相对齐参考**
   `NETHER_LAVA_GLOW_COLOR` 由 `vec3(1.60, 0.42, 0.08)` 改为 `vec3(1.60, 0.64, 0.107)`
   （即参考色相 1 : 0.4 : 0.0667 缩放到同样的 HDR 高位）；
   `NETHER_LAVA_GLOW_INTENSITY` 由 `0.30` 降到 `0.08`。
   峰值 = `1.60 * 0.08 * 2.0（潜没）* 1.0（朝向）` = `(0.256, 0.102, 0.017)`，
   落在参考的 `(0.259, 0.1035, 0.0173)` 上。
2. **熔岩方块的自我提亮加上亮度余量上限**
   `nether_lighting()` 中把自发光提亮乘以 `max(0, 1 - Rec.709 亮度(albedo))`。
   `block.properties:52` 把 `minecraft:lava` / `minecraft:magma_block` 放进发光组 10022，
   `program/lit.vsh:29` 把 10021..10027 全部映射为材质 `10u`，于是熔岩表面吃到 `1.35` 的加法提亮，
   亮部像素在 tonemap 之前就冲到 1.35——这才是「又亮、瞎眼」的主因。
   改后暗的自发光体（菌光体、洞穴藤蔓、灯笼）仍保留大部分提亮，**已经接近 1 的表面不再被推过 1**。
3. **加法项改用折算过的熔岩色**
   新增 `NETHER_LAVA_ADD_COLOR = NETHER_LAVA_GLOW_COLOR * (1.0 / 1.60)`，雾色与天空熔岩池改用它。
   `NETHER_LAVA_GLOW_COLOR` 是 HDR 光照常量，在光照路径乘 albedo ≤ 1 是安全的；
   加法路径没有 albedo 吸收这段余量。
4. **加法辉光改用饱和响应收敛**
   `fogColor += (…) * concentration` 改为 `fogColor += vec3(1.0) - exp(-glow * concentration)`，
   可证明不超过 1，并保持对高度/深度的单调响应。
   熔岩海附近（中性 tint、浓度取满）的雾色混合值：**`(1.92, 1.17, 0.96)` → `(0.92, 0.85, 0.80)`**，
   三通道全部落回 1 以内。
5. **天空熔岩池同改**：明亮地平线 `R 1.13 + 0.35 = 1.48` → `1.13 + 0.22 = 1.35`。
6. **环境光下限重染为生物群系色相**
   `lighting += MIN_AMBIENT_COLOR * directional` 改为沿 tint 重新定向的等亮度形式。
   `MIN_AMBIENT_TINT = vec3(0.33, 0.8, 1.0)`（`lib/colors.glsl:48`）是为主世界夜晚选的冷蓝，
   在下界这种红橙维度里会把暗部中和掉。以 `MIN_AMBIENT = 8` 与下界荒地雾色计算：
   暖项 `(0.02997, 0.01868, 0.01868)`，蓝下限再加 `(0.00264, 0.00640, 0.00800)`，
   B 抬高 43%、R/G 比从 1.60 掉到 1.30。改后**亮度严格不变**，只有色相方向变暖。
7. **注释改正**：`nether_fog()` 中关于「雾更稠」的描述（见 N-001）。

**编译校验**：`qa/tools/compile_glsl.py` → `linked=234 failed=0`（3 档配置，RTX 4050 / GL 4.6，未写日志）。
**这是编译校验，不是画面验证。** 本轮未同步到游戏实例。

**未触碰**：`nether_atmosphere_tint()`（生物群系辨识度依赖它）、云层噪声频率/速度/频带常量
（`NETHER_CLOUD_SCALE = 0.192`、`NETHER_CLOUD_BAND_OFFSET = 38.4` 与 `lib/noise.glsl` 的
`/noiseTextureResolution * 0.75` 约定一致，已核对，**不得改动**）、波浪/噪声注册/阴影数据输出
（本文件本就不含这三者）。

---

## 公共接入需求

### P-001 需要熔岩专属的材质 id（在 `program/lit.vsh`，公共边界）

- **状态**：待处理，本侧已用亮度余量做临时缓解（见「本轮已完成」第 2 条），但做不到参考的效果
- **接口**：`program/lit.vsh:25-29` 的 `astra_material()`
  ```glsl
  if (id >= 10021 && id <= 10027) return 10u;    // 全部发光组压成同一个材质号
  ```
- **调用位置**：`program/lit.vsh:29`（写入 `faceData` 的材质位），下游
  `program/scene.glsl:174` `float emissive = material == 10u ? 1.0 : 0.0;`
- **参数**：`block.properties:52` 的组 `10022`（Orange）当前同时含
  `minecraft:lava`、`minecraft:magma_block`、`minecraft:torch`、`minecraft:glowstone` 之外的一批方块
  （`wall_torch`、`jack_o_lantern`、`fire`、`cave_vines`、`campfire`、`lantern`、`shroomlight`）
- **原因**：`10u` 是一个不可分的掩码，`nether.glsl` 拿不到「这是熔岩」的信息，因此无法只对熔岩
  施行参考的做法。参考对熔岩做了三件 Astra 现在做不到的事：
  1. `specificMaterials/terrain/lava.glsl:1` → `color.rgb *= 0.84`（**降低**反照率）
  2. 同文件 `:15` → `lmCoordM = vec2(0.0)`（**不让光源被自己的光照亮**；熔岩是 15 级光源，
     自身 lightmap ≈ 1.0，`nether_block_lighting()` 会再叠一份它自己发出的光）
  3. 同文件 `:16` → `emission = GetLuminance(color.rgb) * 7.48 + 0.5`（发光强度由自身亮度驱动）
  第 2 条是「又亮」的第二个来源，且**只能靠材质区分**：亮度余量那招对它无效。
- **本侧已完成**：熔岩辉光量级与色相对齐参考；自发光提亮加亮度余量上限（`nether.glsl`
  `nether_lighting()` 第 4 项）。**`lmCoordM` 那一条在 `global/dimension/nether.glsl` 内无解。**
- **主任务侧待办**：给熔岩（及 `magma_block`）一个独立材质号，例如在 `astra_material()` 里
  把 `10022` 拆成「熔岩」与「其他橙色发光体」，或在 `lit.vsh` 里单列一个
  `if (id == 10022 && <熔岩判定>) return 11u;`。定了号头之后本侧可以在 `nether_lighting()`
  里为它跳过 `nether_block_lighting()` 并按参考的 0.84 处理。
  **这是一个能力缺口，不是观感偏好；没有它，「光源不被自身照亮」无从实现。**

### P-002 需要 `screenBrightness`（在 `lib/uniforms.glsl`，公共边界）

- **状态**：待处理；本侧已用常量顶上，下界光照暂时不随游戏亮度设置变化
- **接口**：`uniform float screenBrightness;` —— Iris 内建，即原版亮度滑条（0..1，默认 0.5；
  大于 1.0 表示 fullbright 类模组）
- **调用位置**：补进 `lib/uniforms.glsl` 的冻结清单；下游
  `global/dimension/nether.glsl` 的 `NETHER_VS_BRIGHTNESS`
- **参数**：`float`，0..1
- **原因**：参考 `common.glsl:748` `float vsBrightness = clamp(screenBrightness, 0.0, 1.0);`，
  它参与三处：
  | 位置 | 表达式 | vb 的取值区间 |
  |---|---|---|
  | 环境 | `(0.9 + 0.45 * vsBrightness)` | 0.90 ~ 1.35 |
  | 熔岩 | `(0.7 + 0.35 * vsBrightness)` | 0.70 ~ 1.05 |
  | 下限 | `vec3(0.005625 + vsBrightness * 0.043)` | 0.0056 ~ 0.0486 |

  `nether.glsl` 的模块契约是「不自行打开 uniform」（文件头 Uniforms 段），
  所以现在写死 `NETHER_VS_BRIGHTNESS = 0.5`。后果：游戏内调亮度不影响下界光照，
  且 0.5 本身是一个取值猜测。
- **本侧已完成**：三处表达式已按参考照抄，`vsBrightness` 用常量 0.5 代入
- **主任务侧待办**：在 `lib/uniforms.glsl` 声明 `screenBrightness`，本侧把常量换成 uniform

### P-003 逐字移植 `NETHER_COLOR_MODE 3` 需要 5 个生物群系布尔（`shaders.properties`）

- **状态**：未做；本侧移植的是参考的**模式 2**
- **接口**：`inNetherWastes` / `inCrimsonForest` / `inWarpedForest` / `inBasaltDeltas` / `inSoulValley`
- **参数**：`smooth(50..54, if(in(biome, BIOME_*), 1, 0), 15, 15)` —— 15 帧升降平滑
- **原因**：参考的**默认**是模式 3，用五张硬编码调色板：
  `(0.4,0.14,0.06) / (0.36,0.07,0.05) / (0.18,0.10,0.25) / (0.25,0.235,0.23) / (0.10,0.24,0.24)`，
  并借 15 帧平滑在跨群系时渐变。抄它需要往 `shaders.properties` 加 5 条 uniform 与 biome 常量。
- **本侧已完成**：模式 2 的表达式 `fogColor * 0.6 + 0.2 * normalize(fogColor + 0.0001)`，
  只需 `fogColor` 即可实现，且**保留了原版雾色的绝对亮度差**（灵魂沙谷暗、下界荒地亮），
  修掉了旧 `nether_atmosphere_tint()` 归一化导致的亮度序丢失
- **主任务侧待办**：定是否要模式 3（调色板 + 平滑过渡）

### 其余依赖已核对，无需改动

| 依赖 | 来源 | 位置 |
|---|---|---|
| `ambient_strength()` | `global/lighting/diffuse.glsl` | scene.glsl:16（先于 nether.glsl 的 :19） |
| `held_light_strength()` | `global/lighting/blocklight.glsl` | scene.glsl:9 |
| `MIN_AMBIENT_COLOR` | `lib/colors.glsl` | 由本文件 include |
| `noise()` / `noisetex` | `lib/noise.glsl` | 由本文件 include |
| `nether_sky` 作为雾的天空项 | `astra_reflection_sky()` | scene.glsl:44-46 已按维度分派到 `nether_sky`，**无需改动** |

## 本轮「照抄」造成的删除与偏离（需你确认）

用户指示「不要自己写，抄明白就行」。本轮把下界光照改为逐字移植 Complementary r5.9，
因此删掉了若干 Astra 自有实现。**任何一条你说退回，一句话即可恢复。**

### 已删除（与 design.md 4.5 冲突，请重点确认）

| # | 删除内容 | 参考为什么没有 |
|---|---|---|
| 1 | 熔岩光照的**高度/深度锚定**（`0.75 - 0.25*worldNormalY` + 熔岩面以下 proximity 上升） | `mainLighting.glsl:519` 的熔岩项没有高度项；参考的垂直变化在 `netherStorm`（锚点 Y=28，下方衰减 10×） |
| 2 | **暗区呼吸** `NETHER_DARK_BREATHING` / `NETHER_BREATHING_PERIOD` | 参考没有对应机制 |
| 3 | 夜视色 `NETHER_NIGHT_VISION_TINT = vec3(0.2,0.3,0.2)`（偏绿） | 参考为 `vec3(0.5,0.5,0.75)`（蓝白），已照抄 |
| 4 | `NETHER_AMBIENT_INTENSITY = 0.030` 与 `pow(tint, 0.75)` 的环境项 | 参考为 `(netherColor + 0.5*lavaLightColor) * (0.9 + 0.45*vsBrightness)` |
| 5 | 我上一轮自造的两件：`floorLuma` 生物群系重染、`emissiveHeadroom` 亮度余量 | 均已被参考的 `GetMinimumLighting` 与平方和开方合成取代 |

删除后这些常量变成未使用的死常量（`NETHER_AMBIENT_INTENSITY`、`NETHER_DARK_BREATHING`、
`NETHER_BREATHING_PERIOD`、`NETHER_TAU`、`NETHER_NIGHT_VISION_TINT`）。**保留未删**，
以便随时退回。

### 已记录的偏离（无法照抄的部分）

| 项 | 参考 | 本侧 | 原因 |
|---|---|---|---|
| `vsBrightness` | `clamp(screenBrightness, 0, 1)` | 常量 `0.5` | Astra 无该 uniform，本模块不得自行打开 → **P-002** |
| `vanillaAO` | `glColor.a`（下界另有 pow 重加权） | `1.0` | `nether_lighting` 的参数表由 `program/scene.glsl:178` 固定，本模块拿不到 |
| `to_linear` | 参考在显示域直接运算 | 在 `nether_color()` 末尾转线性 | Astra 光照到合成是线性 HDR，直接喂显示域颜色会整体偏暗 |
| 方块光 `blockLighting` | 彩色方块光体系 + `sqrt(b²+h²)` | Astra 自有的 `nether_block_lighting()`（pow 2.75） | 参考的彩色光体系是基础设施级改动 |
| `emission` | `GetLuminance(color.rgb) * 7.48 + 0.5`（在 `lava.glsl` 内） | Astra 自有的 `nether_emissive_boost()` | 需要熔岩专属材质 id → **P-001** |

### 尚未动、待你定的两处（都是 design.md 4.5 明确要求）

1. **`nether_sky()` 的红/橙渐变天空 + 熔岩池**：参考是 `netherColor` **平铺**
   （`program/deferred1.glsl:376`，无天顶/地平线之分）。照抄等于删掉这条设计。
2. **`nether_fog()` 的熔岩加法项 + 云层项**：参考的边界雾是 `netherColor` **平铺**
   （`mainFog.glsl:47-48`），熔岩影响全部来自 `netherStorm`（默认开）与
   `coloredLightFog`（默认关）。照抄等于删掉雾里的熔岩。

### 两处色彩体系不一致 —— 已记录为「待决策」，未改行为（2026-09-10 审核轮）

光照用新移植的 `nether_color()`，而天空与雾仍用旧的 `nether_atmosphere_tint()`。
两者对同一 `fogColor` 给出不同的量级与色相：以灵魂沙谷一类中性 tint 为例，
`nether_atmosphere_tint()` 给 `(3.325, 1.995, 1.165)`，`nether_color()` 给 `(1.339, 0.803, 0.466)`
—— 约 2.5 倍量级差且色相不同，所以场景光照与地平线（雾+天空）可能读作两个色温。

**本轮按用户「涉及取舍的决策保留在文件中」的指示处理：不改行为，把决策写进代码。**
`nether.glsl` 的 `nether_atmosphere_tint()` 函数上方现有 `⚠ OPEN DECISION` 段，写明
消费方、实测差值、为何留着（统一属可见设计变更，需 SC-6 目视）、以及推荐解
（把雾与天空也切到 `nether_color()`，然后退休该函数）。等 4.5 的三条待定项一并拍板后一次改完。

## 2026-09-10 审核轮补记（代码改动 + 防误修标记）

本轮由审核方（非本 worktree 作者）执行三项**不改变行为**的改动，全部集中在 `nether.glsl`：

1. **`directionShade` 二次平方加了防误修警告**（`nether_lighting()` 内，两处）。
   该值在 `mainLighting.glsl:518` 被平方一次，又在 `:613` 的 `pow2(directionShade * vanillaAO)`
   被平方第二次，最终门控是 4 次方；而 `end.glsl` 走的是同一 block 的 `!defined NETHER` 分支、
   在 `:518` **没有**平方，所以只平方一次。**这个不对称是参考原文，不是转写失误**——
   代码里现已写明「DO NOT FIX」，避免后来者把它「修」成一次平方（那样会把下界明暗对比整体拉平 4 倍）。
   已对照 `_analysis/Complementary r5.9/Reimagined/shaders/lib/lighting/mainLighting.glsl` 逐行核实。
2. **5 个死常量加了 `⚠ DEAD (rollback only)` 标记**：`NETHER_AMBIENT_INTENSITY`、
   `NETHER_NIGHT_VISION_TINT`、`NETHER_DARK_BREATHING`、`NETHER_BREATHING_PERIOD`、`NETHER_TAU`。
   它们在本轮换源后已无消费者（本文件即 `.md` 上文「已删除」清单的对应常量），保留是为了一句话回退；
   标记同时写明「若换源确定保留则与 `NETHER_AMBIENT_INTENSITY` 一并删除」，避免长期悬挂。
3. **`NETHER_NIGHT_VISION_TINT` 的死亡原因写清了**：参考的夜视是 `vec3(0.5, 0.5, 0.75)`（蓝白，
   `minimumLighting.glsl:14`），Astra 旧值是偏绿的 `vec3(0.2, 0.3, 0.2)`；这条色相变更属已记录偏离。

**验证**：`qa/tools/compile_glsl.py` → `linked=234 failed=0`（RTX 4050 / GL 4.6，3 档 profile）。

### 关于 `frameTimeCounter` 的单位（不属于本文件，但请勿误改同类映射）

审核期为排查「云/星漂移是否快 20 倍」的疑问，从随包 `iris-neoforge` jar 反查了
`nether/../sky-clouds` 用到的 `frameTimeCounter`：其实现在
`nether.irisshaders.iris.uniforms.SystemTimeUniforms$Timer.beginFrame(long)`
每帧累加 `delta/1000`，并在 3600 处回绕——**单位是秒，不是刻**。
所以 `wind = frameTimeCounter`（参考 `syncedTime`，同为秒）一类映射是**正确**的，
不要把「20 tick/s」的换算加进去。本文件的下界云（`nether_cloud_glow(..., frameTimeCounter)`）
沿用同一约定，也无需换算。

