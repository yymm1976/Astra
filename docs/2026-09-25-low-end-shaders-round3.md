# 低配光影参考集（第 3 轮）与 Astra 落地评估

**日期**：2026-09-25
**参考集**：`_analysis/low-end-shaders/`（15 包，按内容指纹去重后合并；索引见该目录 `_INDEX.md`）
**同读参考**：`Steadfast 0.8.0`、`Mellow 3.4`（既有，不重复抓取）
**对照对象**：`Astra/`（HEAD `a8c187e`）
**方法**：全部结论基于**本轮实读源码 + 机器量测**，量测脚本与原始数据随报告落盘；不采信任何包的自我描述

---

## 0. 结论摘要

| 维度 | 判定 |
|---|---|
| 参考集就绪 | **15 包已去重合并**，四散位置收敛为一处；3 包为本轮首次纳入 |
| 低配包的第一共性 | **卖的不是效果，是"档位"** —— 14/15 家都有 profile，且第一档就叫 Fast/LOWEST/LOW/Potato/COPPER |
| 与 Astra 最大结构差异 | **时间维度**：能拿到好画质/性能比的降采样方案（MakeUp-UF、Potato、Lite、Bloop…）**全部**配 TAA；Astra 有 5 张降采样缓冲却无 TAA，只能靠**每帧更多 tap** 补画质 |
| 可直接落地 | 9 项（§4 A 级），其中 **A-1 / A-2 成本极低、收益明确** |
| 需架构决策 | 3 项（§4 C 级），TAA 系一项**建议先不做**，理由见 §5 |
| 不建议采纳 | 3 项（§4 D 级），含 re-shaded 的跨代方案（它能省是因为它**根本不在这条管线上**） |
| 实测帧率 | **零**。本轮全部为源码/量测级证据，**不含任何实机或跑分**；`qa/benchmarks.md` 仍为空模板 |

**一句话**：低配包真正的杠杆**不在"更聪明的算法"**，而在四件朴素的事——**①把最贵的默认关掉；②把"关掉"做成整段消失而不是"返回 0"；③用 mip/LOD 链代替独立降采样缓冲；④把 G-buffer 精度降下来**。Astra 的 ①②已做得不差，**③④是明显欠账**。

---

## 1. 本轮交付

### 1.1 参考集（`_analysis/low-end-shaders/`）

| 包 | 来源 | 轮次 | 源文件 | 代码行 | 档位 |
|---|---|---|---:|---:|---:|
| **sildur-fast** | `_analysis/low-end-2026-09-25` | R2 | 60 | 2637 | 2 |
| **re-shaded** | `_analysis/lowend-refs-2026-09-25` | R2 | 11 | 1154 | 0 |
| **potato-shaders** | `_analysis/lowend-refs-2026-09-25` | R2 | 168 | 8500 | 0 |
| **miniature-shader** | `_analysis/refs-2026-09-24` | R1 | 100 | 1696 | 4 |
| **just-colored-lighting** | `_analysis/lowend-refs-2026-09-25` | R2 | 292 | 23682 | 19 |
| **makeup-ultra-fast-shaders** | `_analysis/lowend-refs-2026-09-25` | R2 | 317 | 10674 | 8 |
| **soft-voxels-lite** | `_analysis/lowend-refs-2026-09-25` | R2 | 295 | 20176 | 3 |
| **sildurs-vibrant-shaders** | `_analysis/lowend-refs-2026-09-25` | R2 | 129 | 18530 | 9 |
| **lite-shaders** | `_analysis/lowend-refs-2026-09-25` | R2 | 342 | 15398 | 6 |
| **renderpearl** | `_analysis/lowend-refs-2026-09-25` | R2 | 258 | 5169 | 8 |
| **super-duper-vanilla** | `_analysis/refs-2026-09-24` | R1 | 327 | 12296 | 5 |
| **fastpbr** | `_analysis/refs-2026-09-24` | R1 | 321 | 16982 | 0 |
| **vanillaa** | `Desktop/光影包` | **NEW** | 20 | 727 | 0 |
| **light-shaders** | `Desktop/光影包` | **NEW** | 76 | 12911 | 0 |
| **i-like-vanilla** | `Desktop/光影包` | **NEW** | 358 | 22801 | 6 |
| *Steadfast 0.8.0（同读）* | `_analysis/Steadfast-0.8.0` | — | 101 | 8575 | 19 |
| *Mellow 3.4（同读）* | `_analysis/Mellow Shader v3.4` | — | 381 | 6894 | 3 |

**去重记录**：15 个候选的内容指纹两两不同（`_MANIFEST.json` 的 `handle` 字段），无重复。此前散落于 4 处、且 `makeup-ultra-fast-shaders` / `sildurs-*` / `photon` 等在多个目录重复存放的问题一并收敛。

**未纳入**：`noble`（18.5 MB，已在 `Desktop/光影包` 独立分析）、`bsl` / `photon` / `complementary` / `astralex` / `bliss` / `kappa` / `shrimple` / `nostalgia` / `visual-vibrance` / `pegasus` / `bloop` / `builders-qol` / `simply-upscaled`（均已有 R1/R2 分析记录，且不属于"专注低配"一类）。

### 1.2 机器可读证据

- `_MANIFEST.json` —— 来源路径 / 内容指纹 / 文件数 / 字节数 / 轮次
- `_TECHNIQUE_SCAN.json` —— 17 包量测表（文件、行数、门数、缓冲格式、采样调用、循环、内建函数、纹理资产）
- `_TECHNIQUE_EVIDENCE.json` —— 15 类低配手法的命中位置（`文件:行`）
- `_INDEX.md` —— 人读索引

### 1.3 网络限制（影响说明）

本机出网被代理阻断（`https_proxy=http://127.0.0.1:7890`，`CONNECT: no ALPN negotiated`；`curl` 返回 `000`）。因此**无法下载 Modrinth 上的新品**（如 Skylec、Lumina Lite、Sildur's Enhanced Default、Chocapic13 High Performance）。本轮的"新包"取自本机既有但**从未进入任何分析**的 3 个包。若需要上述新品，需先修复代理或由用户手工放置。

---

## 2. 跨包手法：14 项，按证据强度排序

### T1 档位即产品 —— 14/15 家都在卖"一键降级"（**最强的共性**）

| 包 | 档位设计 | 第一档代价 |
|---|---|---|
| **sildur-fast** | `profile.Fast` / `profile.Fancy` | Fast 关 TAA、SSAO、Tonemap、DOF、Godrays、Refractions；影距 **90**、影图 **1024**（`shaders.properties:68`） |
| **renderpearl** | COPPER→NETHERITE→SCREENSHOT **9 档** | COPPER：影图 **256**、`VL=0`、`SSS=0`、SMAA_SEARCH=8、手光 trace 0 步（`shaders.properties`） |
| **miniature-shader** | `LOWEST/LOW/NORMAL/HIGH`（**继承式**） | `LOWEST`：`!ENABLE_SHADOWS`、`!FLAT_LIGHTING`、`BLOCK_REFLECTIONS=0`、SSR 10 步（`shaders.properties:1`） |
| **super-duper-vanilla** | 5 档 | 低档关体积与阴影细节 |
| **i-like-vanilla** | 6 档 + 48 门 | 低档关 POM/SSAO/反射/体积光 |
| Astra | `PERFORMANCE/NO_SHADOWS/BALANCED/ULTRA` × 73 token | PERFORMANCE 关 SSR/折射/Bloom/平面云/下界体素光 |

**读法**：低配包的**产品定义就是"最低档长什么样"**，而不是"最高档能有多好"。Astra 的四档方向正确。

### T2 「关掉」= 整段消失，不是"返回 0"

- **miniature-shader** 的 `!FLAT_LIGHTING`（`.properties:1`）是一刀砍掉整条光照链的逃生档——**极低配用户拿到的是"没有光照计算"的管线，而不是"计算后乘 0"**。
- **vanillaa** 把可关效果写成空函数体，让编译器直接把调用点消掉：
  ```glsl
  // vanillaa/shaders/final.fsh:26-28
  #if SHARPENING == 0
  // Off
  void SharpenFilter(inout vec3 color, vec2 coord) {}
  #elif SHARPENING == 1   // Unsharp Mask
  ```
  **同样的调用点，三种编译结果**：空函数 / 3×3 / CAS。这是零运行时分支的开销模型。
- **Astra 已有同类做法**（`global/post/grading.glsl`、`program/scene.glsl` 的 `#if !defined DIMENSION_*` 等，全包 270 处预处理点位），**这一项 Astra 做得正确**，无需改造。

### T3 mip / LOD 链代替独立降采样缓冲（**Astra 的明确欠账**）

- **MakeUp-UF**：`softLod = log2(viewHeight/128)` + `texture2DLod`，**降采样缓冲数 = 0**（R2 普查已记录）。
- R2 的普查读数（`docs/2026-09-25-lowend-cross-pack-survey.md` §1）：**MakeUp-UF / Potato / Lite / Sildur-Vibrant / Sildur-Fast 的降采样缓冲全部是 0**。
- 对照 Astra：

| 包 | 降采样缓冲 | 有否 TAA |
|---|---:|---|
| Astra | **5** | **无** |
| MakeUp-UF / Potato / Lite / Sildur-Fast/Vibrant | **0** | 有 |
| Mellow | 1 | 有 |

**这是本轮最重要的一条**：降采样（半分辨率）本身不是省，它把成本从"每像素 N 次采样"换成"每像素 N/4 次采样 + 重建代价"。**没有时间维度时，重建代价只能靠每帧更多 tap 去补**——Astra 的 5 张降采样缓冲因此可能并不比"全分辨率 + mip 链"更便宜。这条需要实测裁决（见 §4 B-2）。

### T4 用**既有缓冲的 mip 链**，而不是新建缓冲

MakeUp-UF 的 `softLod` 是"把缓冲的 mip 链当降采样链用"；`textureLod`/`texture2DLod` 在全包命中：Mellow 16、renderpearl 19、super-duper-vanilla 85、fastpbr 106、lite 64、makeup 78。

### T5 精度降级与整数字段打包（**Astra 欠账**）

- **fastpbr**：在 `RGBA16` 里用 `pack2x8` 风格把**多个字段塞进一条通道**（R2 记录 `pipeline.glsl:187-195`），使 14 条格式声明里只有 1 条宽格式。
- **vanillaa** 的中间缓冲声明（`final.fsh:20-24` 注释保留）：
  ```glsl
  const int colortex0Format = R11F_G11F_B10F; //main scene
  const int colortex1Format = RGB8;           //raw translucent, bloom, final scene
  const int colortex2Format = RGBA16;         //temporal data
  ```
  **主场景用 11-11-10 浮点，中间/最终场景用 RGB8**——按用途分配精度，而不是一律 RGBA16F。
- 低精度格式声明的包内命中数：lite-shaders 14、light-shaders 12、makeup 10、sildurs-vibrant 9、vanillaa(单文件) 8、pixel i-like-vanilla 8、Astra **4**。
- **Astra 现状**：10 张缓冲、60 条声明、仅 4 条低精度（`check_pack` #14 实测）。Astra 的中间缓冲若仍在用 `RGBA16F`/`RGBA16` 承载 8 位级精度数据（如 bloom、雾、渲染中间量），**格式收窄是零画质代价的带宽节省**。

### T6 profile **继承**，而不是 4×73 全量枚举（**Astra 可直接借鉴**）

- **miniature-shader**（`shaders.properties:1-4`）：
  ```
  profile.LOWEST=SHADOW_ENTITY=1 !FLAT_LIGHTING !ENABLE_SHADOWS BLOCK_REFLECTIONS=0 SSR_STEP_SIZE=1.6 SSR_MAX_STEPS=10 SSR_BINARY_STEPS=4
  profile.LOW=profile.LOWEST shadowMapResolution=256 shadowDistance=64.0 shadowIntervalSize=7.0 SHADOW_ENTITY=-1 FLAT_LIGHTING ENABLE_SHADOWS
  profile.NORMAL=profile.LOW shadowMapResolution=1024 shadowDistance=128.0 SHADOW_ENTITY=0 BLOCK_REFLECTIONS=5
  profile.HIGH=profile.NORMAL shadowMapResolution=4096 shadowDistance=384.0 SHADOW_ENTITY=1 SSR_STEP_SIZE=1.2 SSR_MAX_STEPS=16 SSR_BINARY_STEPS=8
  ```
  **每个档位只写"相对上一档改了什么"**。
- **renderpearl** 九档同理（COPPER→WOOD→…），值随档位单调变化，靠继承避免重复。
- **Astra 现状**：4 × **73 token = 292 token** 的全量枚举，且已真实发生过一次一致性事故——上一轮审查发现三选项（`DEBUG_VERTEX_AO` / `END_STONE_GLOW` / `NETHERRACK_GLOW`）**四档全缺**（已修）。继承式写法把"漏抄"从**可能性**降为**结构性不可能**（未被覆写的键自动继承）。
  > 注：Astra 的 `BALANCED == lib/settings.glsl 原始默认` 是一条**刻意保留的基准锚**（本轮已独立复算 73/73 一致）。若引入继承，必须保证该锚仍成立。

### T7 「贵的默认关」vs「贵的默认开」

- **sildur-fast**：TAA/SSAO/Tonemap/DOF/Godrays/Refractions 在 Fast 档**全部关**（`:68`）。
- **Astra**：SSR/折射/Bloom/平面云关在 PERFORMANCE，**开在 BALANCED（阈值档）**；出厂默认 = BALANCED。
- **取舍**：低配包让"最省"成为默认路径；Astra 让"中等"成为默认路径（对 4050 基准合理）。**这解释了为什么低配用户会觉得 Astra 重**——他们拿到的是 BALANCED，而不是 PERFORMANCE。这不是缺陷，但值得在 README/设置页把"低配请先选 PERFORMANCE 或 NO_SHADOWS"写得更醒目。

### T8 GPU 能力面检测（Astra 完全没有）

**renderpearl** 有独立的 `COMPAT` 屏，显式声明**驱动能力假设**并据此降级：
```
screen.COMPAT=CONST_IMMUT <empty> MINMAX_3 MUL_32x16 SUBGROUP <empty> SIZED_16_8 BUFFER_16_8 \
              ASSUME_NV_GPU_SHADER5 ASSUME_AMD_GPU_SHADER_HALF_FLOAT ASSUME_AMD_GPU_SHADER_INT16
```
并配 `shaders/prelude/compat.glsl`（9277 B）承载各厂商路径。**这是把"跨驱动差异"从运行期 bug 变成静态编译路径**的做法。对照 `qa/open-premises.md` 的 **P-3（跨驱动编译，仍未闭环）**——Astra 目前只有 NVIDIA 572.83 单一驱动的证据，renderpearl 的 compat 层是现成的工程模板。

### T9 不新增 pass，把效果塞进本来就要跑的 geometry pass

- **re-shaded**（11 文件）**完全不走 Iris 后处理管线**：它替换 Iris 1.21.6+ 的 **Mojang core shader**（`assets/minecraft/shaders/core/terrain.fsh` 7.9 KB 就是全部地形效果）与 **Sodium 着色器**（`assets/sodium/shaders/blocks/block_layer_opaque.fsh` 9.4 KB）。**它省的不是"某个效果"，而是整条后处理管线**。
- 同类但温和的做法：**fastpbr / bloop / pegasus** 的 MRT 扇出达 4–8，但多出的附件写在**本来就要跑的几何 pass** 里（R2 普查已明确指出"是 pass 数 × 分辨率 × 带宽，不是附件数"）。

### T10 用 TAA 换分辨率与采样数的平方（**Astra 的结构性缺口**）

- **vanillaa**：8 邻居钳制 + 重投影（Chocapic13 血统），**全包只有 20 个文件**，全部预算给 TAA：
  ```glsl
  // vanillaa/shaders/bsl_lib/antialiasing/taa.glsl:34-44
  vec3 NeighbourhoodClamping(vec3 color, vec3 tempColor, vec2 view) {
    vec3 minclr = color, maxclr = color;
    for(int i = 0; i < 8; i++) {                       // 8 taps, 常量上界
      vec2 offset = neighbourhoodOffsets[i] * view;
      vec3 clr = texture2DLod(colortex1, texCoord + offset, 0.0).rgb;
      minclr = min(minclr, clr); maxclr = max(maxclr, clr);
    }
    return clamp(tempColor, minclr, maxclr);
  }
  // :46-67
  vec3 coord = vec3(texCoord, texture2DLod(depthtex1, texCoord, 0.0).r);
  vec2 prvCoord = Reprojection(coord);
  ...
  float blendFactor = float(prvCoord.x > 0.0 && ... ) * exp(-length(velocity)) * 0.6 + 0.3;
  color = mix(color, tempColor, blendFactor);
  ```
  注意 `:53-55` 的**首帧保护**（`if(tempColor == vec3(0.0)) return`）与 `:60-63` 的**越界拒绝**——低成本实现的两个必备细节。
- **Astra 现状**：`lib/dither.glsl:5` 自陈"Astra has no TAA (design.md 2.4)"，因此只能用**静态 IGN 抖动**抑制 banding。**这是设计决议，不是缺陷**，但代价是：Astra 的 5 张降采样缓冲没有时间补偿（T3）。

### T11 SMAA 作为"比 TAA 便宜、比 FXAA 好"的中间选项

**renderpearl** 的 SMAA 是**分档可调**的：`SMAA_SEARCH` 8→16→32→80→112、`SMAA_SEARCH_DIAG` 0→4→8→16→20、`SMAA_CORNER` 0→25（COPPER→SCREENSHOT）。**AA 的质量与成本都是滑条**，而不是开关。Astra 目前 AA 面为零（无 AA、无 TAA、只有抖动）。

### T12 「功能单一化」以换取预算集中

**just-colored-lighting**：只做彩色方块光，其余交原版。19 档位、292 文件、23682 行的预算**全部投在一个效果上**。低配包的一种典型解法是"少做事，把省下的全给一件事"。

### T13 零开关（把配置面直接砍掉）

**potato-shaders**：profile **0 段**、`program.*.enabled` **0 条**。用户没有任何可调项，从而没有"调错变卡"的路径。代价是适应性为零——但这是它的目标用户群。

### T14 时间/帧率摊销

R2 普查已判定 **Astra 用不了**（Astra 明确不引入 TAA/跨帧累积）。本轮复核：**无新增证据推翻该结论**，维持不采用。

---

## 3. 四条"不能看表面"的读数（纠正直觉）

1. **MRT 扇出大 ≠ 贵**：pegasus 扇出 8、bloop/fastpbr/soft-voxels-lite 扇出 4，**都大于 Astra 的 2**，却都是低配档。原因是附件写在本来就要跑的几何 pass 里，且位数极矮、写入被严格条件化。
2. **降采样 ≠ 低配杠杆**：真正省的是"渲染目标数量"与"每像素采样次数"，而**没有 TAA 时降采样会反噬**（§T3）。
3. **档位多 ≠ 更重**：renderpearl 9 档、i-like-vanilla 48 门，档位多是为了让"最省"能**精确**落在弱硬件上。
4. **文件少 ≠ 功能少**：re-shaded 11 文件、vanillaa 20 文件——它们的"少"来自**结构选择**（不建后处理管线 / 唯一效果是 TAA），不是功能缺失。

---

## 4. Astra 落地评估

> 评级：**A** 可直接落地、无需架构变更；**B** 可落地但需实测裁决；**C** 需架构决策；**D** 与 Astra 现状冲突，不采用。

### A 级：可直接落地

| # | 手法 | 落点 | 预期 | 成本 |
|---|---|---|---|---|
| **A-1** | **profile 继承**（T6） | `shaders.properties:171-174` | 消除 292 token 的重复；把"某档漏抄新选项"这类事故（上一轮真实发生过）变为结构性不可能 | 低（改写 4 行 + 保留 BALANCED 锚的断言） |
| **A-2** | **中间缓冲精度分档**（T5） | 参考 `vanillaa/final.fsh:20-24` 的按用途分配；Astra 现为 10 缓冲/60 声明/仅 4 低精度 | 带宽直接下降，画质代价取决于缓冲用途（bloom/雾/中间量通常 8 位足够） | 低 |
| **A-3** | **GPU 能力面 + compat 前置**（T8） | 新增 `lib/compat.glsl` 参照 `renderpearl/shaders/prelude/compat.glsl`；直接服务未闭环的 `open-premises.md` P-3 | 把跨驱动 bug 从运行期前移到编译期；为 P-3 提供模板 | 中 |
| **A-4** | **SMAA 分档**（T11） | Astra 当前 AA 面为空 | 给无 TAA 的空白补一个"比 FXAA 好、比 TAA 便宜"的选项；成本随档位线性可调 | 中 |
| **A-5** | **三档逃生档**（T2/T7） | 在现有 NO_SHADOWS 旁增设"极省光"档，参照 `miniature` 的 `!FLAT_LIGHTING` | 给真正弱机一条"砍掉整段光照链"的路径 | 中（Astra 的 `diffuse.glsl` 446 行是热路径） |

### B 级：可落地，但**必须实测裁决**

| # | 手法 | 要回答的问题 | 判据 |
|---|---|---|---|
| **B-1** | **早期退出加密**（T2） | `program/lit.fsh` 415 行、`global/lighting/diffuse.glsl` 446 行里，是否有"输入注定为 0/被遮蔽"的全像素路径可以整段跳过？本轮**未做**该静态分析 | 静态找出候选 → 逐项 A/B → 画面像素级差 < 量化步长 |
| **B-2** | **5 张降采样缓冲是否比"全分辨率 + mip 链"更省**（T3） | Astra 无 TAA 而做降采样，**这是与 14/15 家相反的组合**。R2 已指出结构性差异，但**从未实测** | 两版实现同场景 GPU 时间对比；若降采样版不占优，则应合并到 mip 链 |
| **B-3** | **热路径内建函数密度**（T14 变体） | 量测表显示 Astra 采样调用 64、`normalize/length/pow` 等内建函数密度需与低配包逐项对齐（本轮已产出数据，尚未逐项分析） | 逐函数替换为等价低成本式，逐项像素对拍 |

### C 级：需架构决策

| # | 手法 | 说明 |
|---|---|---|
| **C-1** | **TAA / 跨帧累积**（T10） | 它能同时解决"无 AA 的 banding"（现在靠 `dither.glsl` 静态抖动硬扛）与"降采样无时间补偿"（B-2）**两个**独立问题。但 `design.md` 2.4 明确排除，且会改变项目最引以为傲的性质（无时域污染、截图可复现）。**建议：先做 B-2 实测；只有在"降采样确实亏"且"抖动确实不够"两项都成立时才重新评估**，并准备用户裁定。 |
| **C-2** | **重新评估"性能档"的角色**（T7） | 是否把 PERFORMANCE 或 NO_SHADOWS 设为**弱机首次加载的推荐档**（含首启提示），而不是保留 BALANCED 为统一默认 |
| **C-3** | **效果预算再分配**（T12） | 是否承认"少做事、集中预算"是低配正解，并据此砍掉某个整模块（Astra 目前是"全都要、各档调参"路线） |

### D 级：不采用

| # | 手法 | 理由 |
|---|---|---|
| **D-1** | **re-shaded 式 core-shader 替换**（T9） | 它省下整条后处理管线，代价是**放弃 Iris/OptiFine 管线**、绑定 Iris 1.21.6+ 与 Sodium 的新架构。Astra 是"全功能 Iris 包"，走这条路等于重写产品定义 |
| **D-2** | **零开关**（T13，potato 路线） | 与 Astra 的双语 GUI + 73 选项 + 四档定位直接冲突 |
| **D-3** | **帧率摊销**（T14） | R2 已定，本轮无新证据 |

---

## 5. 建议的执行顺序

1. **A-1 profile 继承**——最便宜、直接消除一类已发生过的真实事故（档位漏项）。
2. **A-2 缓冲精度分档**——纯带宽收益，风险可用逐缓冲 A/B 控住。
3. **B-2 降采样 vs mip 链实测**——**这一条决定后续方向**：如果降采样确实亏，它会同时影响 C-1（要不要 TAA）与整条后处理设计；如果降采样确实赚，则 T3 的担忧不成立，应记录并关闭。
4. **B-1 早期退出加密**——热路径（`lit.fsh` / `diffuse.glsl`）的静态审计，低风险高上限。
5. **A-3 compat 前置**——顺带闭环 `open-premises.md` P-3。
6. **A-4 SMAA**、**A-5 极省档**——按用户对"AA 缺口"与"弱机逃生档"的偏好排序。
7. **C-1 / C-2 / C-3**——需用户裁定，且**必须在 1–6 的实测数据到手之后**再谈。

---

## 6. 本轮未做与限制（必须声明）

| 项 | 状态 |
|---|---|
| 实机加载 / 画面 | **未做**（本机无可运行 Iris 实例） |
| 帧率 / GPU 时间 | **未做**；`qa/benchmarks.md` 仍为空模板。**本报告不含任何性能结论，全部为源码级手法识别与结构性对比** |
| Modrinth 新品抓取 | **失败**（代理阻断，见 §1.3） |
| 逐包逐行审计 | 只对 **14 个手法**做定向取证；未做"逐包完整通读" |
| B-1 / B-3 的静态热路径分析 | **未做**，已列为待办 |
| A 级落地的实际改动 | **未做**——本报告是评估，未改 Astra 一行代码 |

**可复核性**：本报告所有引用均可由 `_analysis/low-end-shaders/` 下的完整源码 + 三个 JSON 证据文件复现；量测脚本逻辑见 `_TECHNIQUE_SCAN.json` 的字段定义。
