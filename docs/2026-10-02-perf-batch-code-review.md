# Astra 性能优化批次审查报告（2026-10-02）

- 审查基线：`main`（merge base）→ 当前工作树，含 9 个分支提交 + 未提交大批改动
- 审查对象：`Astra/shaders/` 全部改动（以下 `file:line` 均相对 `Astra/shaders/`）
- 审查方式：只读。全程未修改仓库内任何代码文件
- 审查模式：变更审查（只审本批 diff 引入的问题，不评论未改动代码的既有缺陷）

---

## 1. 结论

**不能按现状提交。**

原因不在着色器数学：链接层面在目标 GPU 上是干净的（`qa/tools/compile_glsl.py` 四档 profile 实测 `linked=444 / failed=0 / compute=36`，RTX 4050 Laptop / 驱动 572.83 / GL 4.6）。真正阻塞的是两条工程性问题：

1. **打包完整性**：38 个被已跟踪文件 `#include` 的新模块没有纳入 git，按仓库出包必然编译失败。
2. **Iris 选项发现性**：本批三个关键开关 Iris 根本登记不到，画质档位里的对应 token 全部空转——也就是说"性能优化"里最重要的一档降本措施从未真正生效。

其次，本批有相当一部分内容不是优化，而是**以优化名义发生的视觉/语义变更**，其中 4 处直接改动或撤销了此前有实测数据、有用户反馈记录的标定值。这类改动需要实机 A/B 才能定性，而 `docs/2026-10-02-summary-optimizations.md:109` 自己写着"游戏加载表现、画面取舍及帧率变化尚未确认"。

严重度分布：2 Critical / 11 Important / 7 Minor。

---

## 2. Critical（提交前必须处理）

### C1 · 38 个被 include 的新模块 + 1 张已注册纹理未纳入 git

**验证方法**：遍历 `HEAD` 已跟踪文件的全部 `#include` 目标，逐个比对 git 索引。

**结果**：38 个 include 目标在磁盘上存在但未被跟踪（去重后 25 个文件）。范围包括本批的运行时主干：

| 未跟踪文件 | 被谁 include |
|---|---|
| `program/display.fsh` | `program/final.fsh` |
| `global/post/fxaa.glsl` | `program/final.fsh` |
| `lib/taa_jitter.glsl` | `lib/transforms.glsl` |
| `lib/color_controls.glsl` | `global/post/grading.glsl` |
| `program/ssao.fsh`、`program/volume_main.fsl` 系列 | `program/deferred.fsh` |
| `global/atmosphere/volume_fog.glsl`、`cloud_shadow_cache.glsl` | `program/scene.glsl` |
| `global/water/shaft_history.glsl` | `program/scattering.fsh` |
| `lib/sky_directional.glsl`、`sky_reflection_cache.glsl` | `global/lighting/diffuse.glsl`、`global/dimension/overworld.glsl` |
| `lib/nether_fog_density.glsl`、`nether_voxel_grid.glsl` | `global/dimension/nether*.glsl`、`shadow.vsh` |
| `program/nether_reflection.fsh`、`nether_reflection_resolve.fsh` | `world-1/composite.fsh`、`world-1/composite1.fsh` |
| `lib/surface_buffers.glsl`、`rock_material.glsl`、`wet_material.glsl`、`ao_material.glsl`、`rain_particles.glsl`、`taa_state.glsl`、`taa_reactive.glsl` | `program/lit.fsh`、`lit.vsh`、`program/clouds.fsh` |
| `global/atmosphere/clouds_screen.glsl`、`lib/ao_resolve.glsl` | `program/deferred.fsh` |
| `lib/environment_brdf.glsl` | `program/scene.glsl` |

`git status --porcelain --untracked-files=all` 统计 `Astra/shaders` 下未跟踪文件 **86 个**（全仓 12539 个）。

另外：`shaders.properties:421` 注册了 `textures/astra-end-flow-mips.png`（514×1043，2.05 MiB），文件在盘上但**未跟踪**。按 git 出包时它是空纹理，`global/dimension/end_kerr.glsl:180-186` 的 `level >= 0.5` 分支全部采空，圆盘流动细节在高 mip 归零。

**为什么这条对基线 diff 不可见**：工作区里"缺失 include 目标 = 0"这个结论只在文件齐全时成立。`git diff main` 看不到未跟踪文件，所以审查、`check_pack`、编译验证会一致给出绿灯，而按 git 出的包是坏的。

---

### C2 · 三个布尔选项 Iris 登记不到，profile token 空转

**证据来源**：我自己运行仓库自带的 `qa/tools/check_pack.py` → **17 项检查 8 FAIL**，其中 `#11` 逐字输出：

```
boolean option CLOUD_TEMPORAL is only referenced through defined() program/cloud_screen.fsh
  - with no #ifdef/#ifndef site, so Iris never discovers it:
    no GUI row and its profile token is inert (SC-28)
（另有 DIRECTIONAL_SKYLIGHT、SCREENSPACE_AO 各一条）
```

**对照源码**：
- `lib/settings.glsl:113` `#define CLOUD_TEMPORAL`（硬编码为开）
- `lib/settings.glsl:37` `//#define DIRECTIONAL_SKYLIGHT`
- `lib/settings.glsl:39` `//#define SCREENSPACE_AO`
- 全包唯一的裸 `#ifdef` 站点在 `lib/settings.glsl:491 / :474 / :477`，消费侧全是复合形式（如 `program/cloud_screen.fsh:8` `#if defined CLOUD_TEMPORAL && defined ASTRA_CLOUD_TEMPORAL`）

**后果**（这才使它成为 Critical 而非风格问题）：
- `profile.PERFORMANCE / NO_SHADOWS / BALANCED / ULTRA`（`shaders.properties:449-452`）四条都写了正向 token `CLOUD_TEMPORAL`，但**关不掉**：`colortex24/25` 半/全屏云历史与 `prepare1` 的解析步进在最低档照付。`lib/settings.glsl:111-112` 承诺的退路（"关掉即释放历史目标"）在游戏内不可达。
- 新的 SH9 方向性天光整链（`program/sky_irradiance.fsh`、`lib/sky_sh9.glsl`、`lib/sky_directional.glsl`、`prepare3`、`colortex18/26/27`，门控在 `shaders.properties:115`）用户**永远打不开**。
- `ASTRA_SSAO` 需要 `SCREENSPACE_AO`，用户无从开启。

**作者本人知道这条规则并在同一批里用对了**：`global/atmosphere/volume_fog.glsl:4-6` 写着
`// Bare option site (check_pack #11 / SC-28): Iris discovers VOLUMETRIC_FOG from this` + 裸 `#ifdef VOLUMETRIC_FOG`。新模块没照做。

**附带同源问题**：四条 profile 都写了 `sunPathRotation=-40.0`，`check_pack #2` 判 **unknown token**（空转）；`#3` 判 `lang/en_US.lang`、`lang/zh_CN.lang` 有 `sunPathRotation` 键而无对应选项。

---

## 3. Important（继续前建议修 / 需你确认）

### I1 · 有实测记录的标定被回退：水下焦散高度缩放

`global/water/caustics.glsl:11` 与 `:27` 重新引入 `* 0.4 * (WATER_WAVE_HEIGHT * 0.01)`，并把 `:4` 注释写成 "Keep the reference bump (0.4), offset (0.5)…"。

而 `main` 的 `caustics.glsl:8-10` 正是**为删掉这个缩放而留下的实测记录**：

> `2026-09-11: Astra had scaled the height by 0.4 and halved the tap offset, which shrank the measured caustic field to p90 = 0.06 (max 0.18) - a flat wash instead of the reference's bright moving network, which is what the user saw as "no caustics".`

`main:16` 是 `return mix(a, b, 0.40);`，无 0.4 缩放。默认 `WATER_WAVE_HEIGHT=100` 时本批把高度场削到 40% —— 即把一次有 p90 测量值支撑的视觉修复，以"保持参考实现"的名义改回去了。

**额外耦合**：该高度经 `solas_water_shadow` → `program/shadow.fsh:69` 写进 `shadowcolor0`，而 `shadowcolor0` 正是水下光束唯一的光源载体（`global/water/light_shafts.glsl:81`），于是"波浪高度"滑块现在直接缩放光束亮度。`main` 不耦合。

---

### I2 · 有用户反馈记录的标定被再改动：水下雾、日射眩光、色调提升

`lib/solas_water.glsl:79-97` 三处均非等价改写（`git diff main` 实测）：

| 项 | main | 工作树 | 有效变化 |
|---|---|---|---|
| 水下雾 | `density = UNDERWATER_FOG_DENSITY/40`；`1-exp(-3.0*d*0.01*density)` | `/120`；`1-exp(-6.0*d*0.01*density)` | 指数降为原来的 **2/3** |
| 日射眩光乘数 | `glare * 16.0 * …` | `glare * 4.0 * …` | **降到 1/4** |
| 水下色调 | `solas_water_tonemap_curve(color * 4.7)` | `color * 5.2` | 提亮 |

被删掉的 `main` 注释是用户原话支撑的标定：

> `2026-09-11 user round: "水下就像加了一层蓝色滤镜，水底的方块都是蓝的". At the old 6.0/0.01 coefficient the fog already reached 45% at ten blocks and 70% at twenty…`

注意 `main` 当时已经是从 `6.0/0.01` 减半到 `3.0/0.01` 的结果，本批又把它挪回 `6.0` 但同时把密度基从 `/40` 提到 `/120`（净 2/3）。新增的两处跳过我核验为**确属零贡献**（`fogAmount <= 0` 时返回 `vec4(0)` 不改 `mix`；glare 门控与乘数 `astraSolasTimeBrightness * eyeSky` 同时为 0），逻辑安全 —— 问题只在"这也是一处外观变更，且注释里的新说法没有任何实测数据支撑"。

---

### I3 · 焦散峰值：producer 保留、consumer 夹掉

- `program/shadow.fsh:28` `// Solas caustic transmission can exceed one; retain its peaks in GBA.` + `:33 const int shadowcolor0Format = RGBA16F;`
- `global/lighting/shadowmap.glsl:127` `transmission = clamp(caster.gba, vec3(0.0), vec3(1.0));`

生产端专门用半浮点保留 >1 的峰值，消费端第一行就把它夹回 [0,1]。两边直接矛盾，`:28` 的注释现在是假的。同时 `shadowmap.glsl:122` 的 `#ifdef COLORED_SHADOWS` 分支已经把 `caster.gba` 取走，`:127` 在其后无条件覆盖。

`main` 对应位置：`:148 vec3 transmission = vec3(0.0);`、`:153 transmission = isEyeInWater == 1 ? caster.gba : vec3(1.0);`（无 clamp）。默认值 0.0 → 1.0 的翻转影响面较小（`COLORED_SHADOWS` 在 `lib/settings.glsl:85` 默认开，且四档 profile 都是正向 token），只在用户主动关掉彩色阴影时才咬人。

---

### I4 · 光束早退条件与 `shadowcolor0` 白清屏冲突（后果未证实）

`global/water/light_shafts.glsl:78` 新增 `if (shadow0 >= 0.999) continue;`。我读到 `:77-84` 的实际累加式：

```glsl
float shadow0 = dot(shadow_gather_visibility(shadowtex0, pos.xy, pos.z), weights);
if (shadow0 >= 0.999) continue;
float shadow1 = shadow_opaque_visibility(pos);
if (shadow1 <= 0.0) continue;
vec3 shadowCol = textureLod(shadowcolor0, pos.xy, 0.0).gba;
vec3 shadow = clamp(shadow1 * shadowCol * shadowCol, vec3(0.0), vec3(8.0));
integral += shadow * intensity * coverage;
```

`shadow_gather_visibility` 返回的是**可见度**，而 `lib/settings.glsl:522 const vec4 shadowcolor0ClearColor = vec4(1.0, 1.0, 1.0, 1.0);` 是**白清屏**。也就是说"完全可见"的样本并非零贡献 —— 它携带 `shadowCol²` 的焦散调制。跳过它等于在开阔无遮挡区域丢掉焦散网络，只在半影处保留。

它看起来无害的唯一原因是水面自己就是 `shadowtex0` 的遮挡体（`shaders.properties:268 shadowTranslucent=true` + `program/shadow.fsh:46` 水面 caster 不 discard），所以 `shadow0` 在多数区域本就 <1。一旦某 texel 没有水面 —— `shadow_map_fade` 边界带（`global/lighting/shadowmap.glsl:59-65`）、细流、半填充方格 —— 光束会被整段丢弃。

对照参考实现：`_analysis/Solas Shader V2.2b/shaders/lib/atmosphere/volumetricLight.glsl:73-83` 的 `shadow0` 是单点软件比较、`shadowCol` 仅在 `shadow0 < 1` 时读取；换成四角加权 + 白清屏后语义不等价。

**实际画面后果：未证实。** 最小验证 = 注释掉 `:78` 做 A/B。
附带成本判断：主体场景该跳过几乎不触发（收益≈0），而 `:77` 的四角 gather 是每个样本的**新增**开销。

---

### I5 · 光柱的三项标定被删 / 太阳方向被换

`global/water/light_shafts.glsl`：
- `:37` `vec3 lightDir = astra_world_light_direction();` —— 改用指向太阳的方向，`main` 用的是折射后方向
- `:36/:42-43` 依赖 `astraSolasTimeBrightness`（`shaders.properties:616`）与 `astraSolasShadowFade`
- `:10` `WATER_SHAFT_MAX_DISTANCE = 128.0`，`main` 是 `maxDist = 40.0` + break
- 从 `main` 删除的：折射太阳门、`sunGate` 日照门、逐样本焦散项，以及记录"正午归零"bug 的注释（配套探针 `qa/tools/shaft_refract_probe.py`）

删掉带探针的 bug 记录注释、把行进上限从 40 提到 128（3.2 倍体积），这不像是顺手做的性能改写。`shadowmap.glsl:74-75` 的内切圆丢弃半径未随 128 上限重新评估，水下远景形状会变。

参考实现对照：`_analysis/latest-2026-09-10/solas-shader/shaders/lib/atmosphere/volumetrics.glsl:117` 的 `VoL` 用的是**视图空间**方向。

---

### I6 · 云阴影语义翻转进入默认路径

`global/atmosphere/weather.glsl:134` 的返回值由 `main:127` 的 `return 0.0` 改为 `return 1.0`：

```glsl
// main:127        if (lightDir.y <= 0.01) return 0.0;
// worktree:134    if (lightDir.y <= 0.01 || astraCloudShadowFade <= 0.0) return 1.0;
```

同时把仰角淡出从调用点上移进场内（`global/atmosphere/cloud_shadow_cache.glsl:18` 的 `mix(1.0, 0.07, cloud * astraCloudShadowFade)`、`:25` 的提前返回）。

`CLOUD_SHADOWS` 关闭时（`lib/settings.glsl:108` 默认，四档 profile 全是 `!CLOUD_SHADOWS`）走的是 `program/scene.glsl:285-288`：

```glsl
if (isEyeInWater == 0 && astraRainFactor > 0.01) {
    float cloudLight = astra_cloud_transmission(playerPos + cameraPosition, astra_world_light_direction());
    params.directLightSurface *= mix(1.0, cloudLight, astraRainFactor * 0.75);
}
```

该分支基线**完全没有**高度淡出。方向像修 bug（低仰角时直射光不该被云影削到 7%），但这是外观变更，需实机确认并写进 changelog。
另外阴影密度由双八度 `astra_cloud_noise` 改为单八度 `astra_cloud_coarse`（`cloud_shadow_cache.glsl:16`），且淡出曲线重新锚定：基线 `smoothstep(0.0, 0.2, y)` → `shaders.properties:831` 的 `clamp((y-0.01)/0.19)`，中段最多约 3% 强度差。

---

### I7 · 默认档新增一趟全屏 pass，载体精度过剩

`shaders.properties:103-112`：`#if ANTIALIASING == 1` 才启用 `composite8` 三维度并分配 `colortex13=1.0 1.0`，`#else` 收为 `1 1` 并关闭。出厂默认 `lib/settings.glsl:242 #define ANTIALIASING 1`，`profile.BALANCED/ULTRA` 同为 1 —— 只有 `PERFORMANCE/NO_SHADOWS`（`ANTIALIASING=0`）免单。

`program/display.fsh:70-73` 写 `colortex13Format = RGBA16`，而 `:200-201` 存的是已 `clamp(0,1)` 的显示色 + 一路亮度 —— RGBA8 就够，RGBA16 只买带宽。1080p 每帧多约 16.6 MB 写一遍再整屏读一遍。

设计动机是正当的（FXAA 需要亮度通道，见 `global/post/fxaa.glsl:40-44` 全用 `.a`），但**这套 AA 子系统在本批是新增功能，不是优化项**，按"优化"口径评估预算会系统性误判。

---

### I8 · FXAA 水下几何门阈值不随深度尺度换算，实际几乎不放行任何剪影

`global/post/fxaa.glsl:38` `if (delta < max((1.0-depth)*0.08, 0.00001)) return center.rgb;`

`delta`（`:34-37`）是相邻纹素的**窗口深度**绝对差；`program/final.fsh:15` `geometryOnly = isEyeInWater == 1`。

我的计算（取 near=0.05 / far=192，`z = ((near+far) - 2·near·far/d) / (2·(far-near))`）：

| 视距 | 窗口深度 z | 阈值 `(1-z)*0.08` | 相邻方块深度差 | 判定 |
|---|---|---|---|---|
| 5 → 6 方块 | ≈0.9903 | 7.8e-4 | ≈1.0e-4 | `delta < 阈值` → **不 AA** |
| 100 → 101 方块 | ≈0.99971 | 2.3e-5 | ≈2.4e-6 | `delta < 阈值` → **不 AA** |
| 0.6 → 0.7 方块 | ≈0.9168 | 6.7e-3 | ≈1.2e-2 | `delta > 阈值` → AA |

只有约 1 方块内比值才大于 1。结果与 `:31-32` 自己声明的意图（"把 AA 限制在深度剪影上"）相反：想保留的近处"方块压方块"剪影基本不抗锯齿，而这 5 次深度取样每个水下像素都付。`0.08` 应记为需真机标定的量，或改成按线性视深的相对判据。

---

### I9 · 花/高草阴影剔除是本批新增，影响 BALANCED + ULTRA 户外

`program/shadow.vsh:90-104` 把 `10004 / 10005 / 10006`（`shaders/block.properties:37/40/43` = 花与浆果丛、高植物上/下半）连同 `10010` 一起剔出阴影图：

```glsl
if (noShadow || isGroundFoliage) { gl_Position = vec4(0.0, 0.0, 2.0, 1.0); … return; }
```

`main` 的 `shadow.vsh` 没有这条路径（那些 ID 只出现在体素 kind 表 `:66` 与波动分支 `:90-95,109`）。省的是阴影体素量，代价是花/高草不再投影。同文件 `:123` 的 `abs(gl_Normal.y) > 0.9` 较 `main` 的 `> 0.999` 放宽，会改变参与体素化的面集合。

---

### I10 · 末地显存 +73 MiB 且主世界照付；文档数字偏低 21 MiB

我读 PNG IHDR 实测（colorType=6 → RGBA8）：

| 文件 | 尺寸 | MiB | git 跟踪 |
|---|---|---|---|
| `textures/astra-end-transfer.png` | 4096×4096 | 64.00 | 是 |
| `textures/astra-end-transfer-meta.png` | 1024×1024 | 4.00 | 是 |
| `textures/astra-end-flow.png` | 1024×1024 | 4.00 | 是 |
| `textures/astra-end-flow-mips.png` | 514×1043 | 2.05 | **否** |
| 四张合计 | | **74.05** | |

注销 `blissNetherNoise`（512² ≈ 1.00 MiB）后**净 +73.05 MiB**；注册自定义纹理总量 9.77 → 82.81 MiB（`shaders.properties:418-421`）。
`customTexture.*` 在 Iris 没有维度或画质条件（同文件只有 `size.buffer.*` 支持 `#if`，见 `:167-197`），所以主世界、下界、所有档位都上传，其中一张占约 77%。

`docs/2026-10-02-uncommitted-changes-review.md:23` 记的是"净增约 52 MiB"，与实测差 21 MiB。**这条属于"已记录但未收口"，不是我中途误判的"完全未记录"。** 该文档 `:399` 已经建议按 `END_PRECESSION`/维度门控，但没有落地。

同处另有一笔：`shaders.properties:47 size.buffer.colortex9` 由 `main:38` 的 `0.75 0.75` 提到 `1.0 1.0` 且无 `#if`，约 15.8 MiB 全维度分配，而写/读者只有 `program/deferred.fsh:285` 与 `program/nether_reflection.fsh:106`。`shaders.properties:143` 附近的注释也自述了 `size.*` 不带维度命名空间。

---

### I11 · 下界在 BALANCED / ULTRA 是净增成本

`shaders.properties:275/277`（及 `:279/281` 的 world1）新启用原生分辨率的 `composite` / `composite1` 两趟；`program/nether_reflection.fsh:24` 的 `const bool colortex0MipmapEnabled = true;` 现在是全 pack 唯一一处（`main` 那处在水下路径 `program/water_bloom.fsh:5`）。

迁移方向是对的（全维度常付 → 单维度按需付，且 `:67 vec3 reflected = textureLod(colortex0, refPos.xy, lod).rgb;` 确实消费 mip），但下界现在独付一条全分辨率 mip 链，加上 `colortex28`（`:185`）pack 级分配而只有下界使用。

**同时：同 pass 读写同一附件的规范未定义面被扩大。** 我用传递闭包扫描统计：读+写同一 `colortex` 的站点 `main` 5 处 → 工作树 14 处（新增 9 处）。这是**既有惯用法被扩大，不是新出现的 bug 类**（`global/post/exposure.glsl:22-24` 已把这个约定文档化，包内多处以"同 texel 历史复用"为设计前提）。`program/nether_reflection.fsh:28` 以 9/28 为渲染目标，同时 `:102/:106` 以 `base + ivec2(x,y)` 的 2×2 邻域 `texelFetch` 这两张 —— 跨 texel 自读，规范上未定义，实际驱动行为**未证实**。

---

## 4. Important（配置面）· 仓库自己的 QA 门禁处于红状态

`check_pack.py` 实测 8 项 FAIL，除 `#11`（C2）外还有：

| 检查 | 内容 |
|---|---|
| `#2` / `#12` | 四档 profile 缺 `PURKINJE_STRENGTH`、`ROUGH_SKY_REFLECTIONS`；`sunPathRotation` 是 unknown token；`screen.*` 有 1 个未在 settings 定义的 token |
| `#3` | 两个 lang 文件有 `sunPathRotation` 键但无对应选项 |
| `#4` | `global/dimension/nether_volume.glsl` 为未接线孤儿（不在 `PENDING_CONSUMERS`）；`deferred.fsh` / `prepare2.fsh` 作为 layer-1 shell 直接 include `lib/settings.glsl`（违反设计 3.2 分层） |
| `#8` | `THIRD-PARTY.md` 的 `astra-only` 计数 35 与表达式差 123，需重跑 `provenance_steadfast.py` |
| `#13` | `ASTRA_VOLUME_BASE_EXTINCTION` / `ASTRA_VOLUME_RAIN_GAIN` 无任何读者 |
| `#15` | `global/post/fxaa.glsl` 把 MIT 正文放在 `lib/vendor/` 之外 —— 新引入，正是该检查要拦的 VanillaPlus 失效模式（4,384 / 11,373 行） |

`#13` 还给出：**100 / 156 个选项能翻转预处理分支，完整 pairwise 覆盖矩阵 = 321 行**，命令 `python qa/tools/compile_glsl.py --matrix`。我只跑了 4 档 profile（444 链接），覆盖率远低于此。

---

## 5. Minor

1. **`colortex1` 尺寸由水下采样滑块决定，空气 godrays 被连拖**：`shaders.properties:17-23` 的 `#elif UNDERWATER_SHAFT_SAMPLES < 7` → `0.25 0.25`，而空气消费端 `program/display.fsh:140` `godrays_box_filter(colortex1, …)` 也读它。只开 `GODRAYS`、关掉水下光柱但滑块停在 <7 的用户，空气光轴缓冲落到 0.25（1080p 下 480×270），低于 `properties:8-10` 自己声明的"半分辨率才承载得住该信号"。正确写法对照 `:189-197`（同一条件嵌套在 `UNDERWATER_LIGHT_SHAFTS` 内部）。
2. **循环不变量提升漏点**：`global/water/light_shafts.glsl:75` 的 `textureSize(shadowtex0, 0)` 在循环内，且 `shadow_gather_visibility` / `shadow_opaque_visibility` 内部各再查一次（`global/lighting/shadowmap.glsl:93/100/137/143`）；`:76-77` 重复实现了 `shadow_lobe_light` 已有的 gather + 角权（`:104-111`）。
3. **缓冲区语义改主后遗留声明**：`global/water/temporal.glsl:47-49,60-61` 声明 `colortex29` 存 SSR 元数据，而本批已把 29 改成光束历史缓冲（`program/scattering.fsh:83-86` 写、`global/water/shaft_history.glsl:7/38` 读）。整文件在永不定义的 `ASTRA_WATER_TEMPORAL` 下，当前不冲突，一旦被启用就是读写垃圾。
4. **硬编码分辨率**：`global/atmosphere/cloud_shadow_cache.glsl:32-35` 把缓冲尺寸 `256` 写进过渡带；改 `colortex14` 大小不会报错，只会让回退带与纹素不再对应而静默错位。同包已有正写：`global/atmosphere/volume_fog.glsl:225` 的 `vec2(textureSize(volumeBuffer, 0))`。`ASTRA_CLOUD_SHADOW_TEXEL`（`:8`）无读者。
5. **文档型常量与实现脱钩**：`global/atmosphere/volume_fog.glsl:46-53` 的 `0.004` / `2.2` 全仓唯一出现处就是定义本身，真值以字面量复制在 `shaders.properties:838`；`global/atmosphere/sky_minishita.glsl:5` 头注释仍列 `worldSunVector/sunProgress`，实际 `:94-125` 已改读 `astraMinishitaSun/Moon`。
6. **恒真分支 + 缩进混用**：`global/post/exposure.glsl:112-116` 已在水下提前 `return`，`:125` 的 `if (isEyeInWater == 0)` 包裹恒真（`lib/uniforms.glsl:79` 的 `isEyeInWater` 有 0/1/2/3 四值，一旦有人把 `:112` 收窄成 `== 1`，熔岩/粉雪会既不计量也不融合）；同文件混用 tab 与空格。AE 历史改 `RGBA32F`（`:30`）本身是对的 —— 8 位历史确实会把小步长适应舍掉。
7. **死代码**：`global/dimension/nether_volume.glsl` 无人 include 却仍声明并采样已注销的 `blissNetherNoise`（`:25/:36/:45`，`shaders.properties:678` 的说法成立）；`global/water/temporal.glsl:32-35` 已标 INACTIVE 却保留第三份 Halton 相位表（另两份 `lib/taa_jitter.glsl:12-19` 与 `shaders.properties:820-825` 我逐值核对等价），三处任一处单独改动都会让几何抖动与解析重投影错相。

---

## 6. 做得好的地方

1. **链接证据是真的**：`qa/tools/compile_glsl.py` 在目标 GPU 四档 profile `linked=444 / failed=0 / compute=36 / compute_capable=true`。同类改动常见的 uniform 缺失、非 `const` 循环上界、维度 `#define` 遗漏，我抽查未踩到 —— `world1/`、`world-1/` 每个入口都 `#define` 对应宏（仅 `world-1/shadowcomp[A-H].csh` 无且不需要）。
2. **带宽迁移方向正确且成体系**：删掉 `program/water_bloom.fsh:5` 的全分辨率场景 mip 链；bloom 捕获 0.5→0.25 且抽头 13→9→4（`shaders.properties:24-29`）；feature 关闭时把缓冲缩到 1×1 在 properties 里成体系（`:140-143`、`:160`、`:187`）；常量迁移到 CPU uniform（`:616`、`:778`、`:820-825`、`:838`）；`composite3` 全屏拷贝在 bloom 关闭时整个停掉。
3. **时间域自洽性罕见地扎实**：全场唯一抖动点 `program/lit.vsh:187`（21×3 个 gbuffers 壳共用同一份）；CPU Halton 表与 GLSL 逐值等价（x 八项、y 分母 18、`+0.0546875` = −mean(x)）；戳记 pass 排在消费之后（`program/taa_state.fsh:1`）；历史统一使用非抖动网格且三处消费方口径一致；`ASTRA_TAA` 门限在 `shaders.properties:81` 与 `lib/settings.glsl:496` 逐字相同。
4. **数值改写有等价性证明**：`program/deferred.fsh:118-143` 的指数递推（底数 `exp(-step·0.004)`、比 `exp(-step·0.008)`、10 样本、末乘 `stepLength`）与基线 `exp(-t·0.008)`、`t=(i+0.5)d/10` **逐项相等**；`:124-134` 用线性外推替换 `player_shadow` 对 `lib/transforms.glsl:107-115` 的仿射形式精确成立；`lib/tonemap.glsl` 的 `apply_contrast` 新旧式在 c<0.5 / =0.5 / >0.5 恒等；`display.fsh:48-64` 的 `godrays_box_filter` 按 `(1-f,1,1,f)/3` 逐权重复算为精确等价。
5. **代价有账可查**：`docs/2026-10-02-uncommitted-changes-review.md` 已记录 colortex9 提分辨率、TAA 新增全分辨率附件（`:231` 记 colortex15/16/22 合计 17 B/px ≈ 35 MB@1080p）、仅主世界特性 25–33 MB 常驻。数字按 I10 校正即可。
6. **清理是彻底的**：`end_ring.glsl` 删除后 include 闭包无残留（`end_ring_axis()` 迁至 `global/dimension/end_geometry.glsl:75`，外部唯一调用 `program/end_illumination.fsh:18` 有效）；`astra_wave_normal_at`、`astra_water_caustics_focus`、`ASTRA_CAUSTIC_STRENGTH`、`water_ssr_view_z`、`NETHER_FOG_NEAR_COEFF/FAR_COEFF/FAR_EXP/BLOCKLIGHT_EXPONENT` 全树引用均为 0。

---

## 7. 未能闭合的验证（必须诚实记录）

1. **TAA 全链路从未被链接验证过。** 四条 profile 的 `ANTIALIASING` 只有 0 和 1，而 `ASTRA_TAA` 要求 `== 2`（`lib/settings.glsl:496` / `shaders.properties:81`）。所以第 6.1 节那句"444 链接全过"**覆盖不到** `program/taa_resolve.fsh`、`program/taa_state.fsh`、`program/lit.vsh:12` 的顶点阶段 `colortex17` 采样、`program/composite6/7.fsh` 及其 `world-1`/`world1` 变体。
   我尝试补跑 `--set ANTIALIASING=2`（以及 `--undef BLOOM` 的显示臂），**因环境失败**：`compile_glsl.py` 需要 LWJGL 3.3.3，而默认根 `C:\Users\杨铭\AppData\Roaming\.minecraft` 下 `libraries` 目录不存在、`ASTRA_MC_ROOT` 为空，在 C:/D: 有限深度内也未搜到该 jar。要闭合这条，需要一个装了 LWJGL 3.3.3 的 Minecraft 根目录。
   另：`profile.*` 不含 `ANTIALIASING=2` 意味着 TAA 只能由用户手动选，而这条最复杂、最难回滚的路径至今零实机验证（`docs/2026-10-02-summary-optimizations.md:109` 自述）。
2. **完整选项矩阵未跑。** `check_pack #13` 给出需要 321 行才能覆盖 100 个可翻转分支的选项；我只跑了 4 档 profile。
3. **`ANTIALIASING=2` 下的反应遮罩行为未验证。** `program/lit.fsh:345-349` 把非不透明地形（水/实体/粒子/天气/云）一律标 `reactive=0`，`program/taa_resolve.fsh:103` 的 `valid = reactive < 0.95 && …` 因此对它们为假 → `resolved = current`（`:144`），而 `current` 是在**抖动 UV** 上取的一次双线性（`:58-60`）。也就是说这些像素等效于"整幅图平移半像素再采样"：锯齿没被平均掉，还多一层插值模糊。这是静态推演，未经实机确认。
4. **多处依赖 Iris/驱动运行时行为，静态无法证明**：custom RGBA16F image 是否走 `GL_LINEAR`（`global/dimension/nether_colored_light.glsl:23` 单 tap 等价性的前提）、无写者时 Iris 是否仍分配缓冲、`frameCounter` 是否有回绕上限（`lib/taa_state.glsl:18` 与 `lib/effect_history.glsl:22` 把它当不回绕单调计数用，而 `global/atmosphere/cloud_temporal.glsl:102` 自带 `% 2048` 约定，包内两套帧龄比较并存）、同 texel 自读的实际驱动行为。

---

## 8. 建议处理顺序

| 步 | 动作 | 理由 |
|---|---|---|
| 1 | 把 38 个 include 目标 + `astra-end-flow-mips.png` 纳入 git，并加一条 CI 检查「已跟踪文件的 include 目标必须已跟踪」 | C1 之外，真正的修复是给这条盲区加门禁 |
| 2 | 按 `volume_fog.glsl:4-6` 的写法给 `CLOUD_TEMPORAL` / `DIRECTIONAL_SKYLIGHT` / `SCREENSPACE_AO` 补裸 `#ifdef` 站点；删掉 profile 里的 `sunPathRotation` | 否则"性能优化"里最关键的一档降本从未生效 |
| 3 | 决定 I1–I6 六处外观变更的归属：确认保留的，写进 changelog 并撤销"性能"口径；不确认的，回退到 `main` 的标定值 | 它们混在优化里会让后续预算判断失真 |
| 4 | 修 I3（producer/consumer 对 `caster.gba` 的处理矛盾）与 I4（`:78` 早退做 A/B） | 前者是注释与实现互相打脸，后者是收益≈0 但每样本新增开销 |
| 5 | 补 `check_pack` 的 `#2/#3/#4/#8/#15` 四项，让仓库门禁回到绿 | 红状态下这些检查失去保护力 |
| 6 | 拿到 MC 根目录后跑 `--set ANTIALIASING=2` + `--matrix`，再做实机长时（>30 min）与跨维度/入水/传送实测 | 第 7 节的四条闭合 |

---

## 9. 审查中产生的一次自我纠正

报告中途我曾把 I10 判为"末地显存增量未记录"。核对 `docs/2026-10-02-uncommitted-changes-review.md:23/:350/:357/:399` 后确认**该代价已记录、并已建议按维度门控，只是未落地**，故定性改为"已记录但未收口"，并把增量数字从文档的 +52 MiB 校正为实测 +73.05 MiB。

同样被剔除的子代理误报：
- 水体子代理报的"同 pass 反馈环 Critical" —— 我用独立扫描证伪为既有惯用法（`main` 5 处 → 工作树 14 处，扩大而非新增），维度子代理独立复现同一结论。
- 水体子代理报的"正午海床衰减 128×" —— 我的算术约为 13×，量级不符。
- 配置子代理报的"`AUTO_EXPOSURE` 缺失" —— 更早已被证伪。
- 天空子代理对 `sky_irradiance.fsh:20` 的 0.08 半球假设判为 Important，另一路子代理判为"配对代数正确 ✅"。两者不矛盾：前者质疑假设的物理性，后者验算的是配对求和与原 128 样本式在**该假设下**相等。且 `docs/2026-10-02-project-performance-fixes.md:29` 已把它声明为建模常量 —— 属既有建模选择的搬运，不在本批新增缺陷之列，故未列入上面任何一节。
