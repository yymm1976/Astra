# 未提交改动审查报告（2026-09-27 ~ 10-02）

本报告只审查、不修改代码。范围为仓库最后一次提交 `9f1a931`（2026-09-26）之后**全部未提交的工作区改动**。方法为源码级审查：逐模块读改动与调用链、核对 docs 中的性能声称、核对 `shaders.properties` 的阶段与附件接线，并运行项目自带校验器 `qa/tools/check_pack.py`。**未做实机加载、画面比照或帧率测量**，凡涉及观感与帧率的结论都在文中标明为未确认。

> **基准时刻说明（重要）。** 审查期间工作区**被并发改写**：`git diff --shortstat` 从开始时的 `+3426/−3586` 变为约 30 分钟后的 `+3563/−3639`，期间 `tonemap.glsl`(19:21)、`end_system.glsl`/`end_blackhole.glsl`(19:20)、`light_shafts.glsl`/`nether.glsl`(19:19)、`lit.fsh`/`weather.glsl`/`diffuse.glsl`(19:17:58)、`lit.vsh`/`shaders.properties`/`uniforms.glsl`(19:17) 等文件相继被修改。因此**本报告的行号对应某个具体快照，个别行号可能已经偏移**；所有结论都已在当时的内容上复核，但请在改动停止后重新对照一次。本报告自身是本次审查唯一新增的文件。

## 0. 范围与量化

| 项 | 数量 |
|---|---|
| 已跟踪文件的改动 | 105 个（+3426 / −3586 行，忽略空白后 +3336 / −3496，即非换行符噪声） |
| 新增未被跟踪的着色器文件 | 85 个（约 2810 行，含 `program/`、`lib/`、`global/`） |
| 引用资料目录之外的新增文件 | 214 个（含 docs/、qa/、qa 日志） |
| 项目自带校验器 | **8 FAIL / 0 WARN / 9 PASS**（`python qa/tools/check_pack.py`，退出码 8） |

时间跨度覆盖 09-27 至 10-02 的多轮工作：ITT/R1–R6/S1–S4 交接落地、TAA/FXAA、水体材质、下界反射、10-01 与 10-02 三轮性能修复、以及末地盘面分辨率提升。

改动性质并非如描述的那样"大都是性能优化"。按本报告的分类：

- **真实净减（默认档）**：阴影 PCF 4→2 lobe、`deferred` 少一次 `colortex3` 读取、Bloom 捕获 13→9 次、`colortex2/7` 等附件按零贡献缩到 1×1、`composite2/3` 等阶段按零贡献停用、云步进像素数在 PERFORMANCE 档下降、约二十处精确等价的零贡献早退。
- **拿画质换成本**：一维 PCF（默认档）、水下焦散亮斑被夹平、**末地直射阴影整条失效**（下界经核对不受影响）、雨滴按颜色猜测剔除、掠射角云影反转（有意且已登记）、水体反射锥角点由固定 16 升至默认 20／ULTRA 36。
- **纯新增成本（默认关闭；打开后大于本模块省下的量）**：SSAO（约 29 读/半分辨率像素的生产者 + 5–20 读/全分辨率像素的合成 + 25–33 MB 附件）、方向性天光、主世界体积雾、粗糙天空反射、TAA（最多约 28 次纹理访问/像素 + 约 35 MB 附件）、下界 SSR（2 个全屏 pass + 全分辨率 HDR 附件）。整套**平面云生产链**（`prepare`/`prepare1`/`prepare2` 与 5 张新附件）也是本批全新加入。
- **工具链**：本批新增的 `sunPathRotation` 选项接线使 `compile_glsl.py` 在预检阶段就退出，**全批没有编译验证**；`check_pack.py` 现为 8 FAIL / 9 PASS。
- **资源膨胀**：末地传输图集 2048²→4096²、`astra-end-flow` 512²→1024²、新增 mip 图集，已注册自定义纹理显存净增约 **52 MiB（raw RGBA8，31→83 MiB）**；`colortex9` 由 0.75 提到 1.0。

## 1. 先修的发现

**F-0 本批把项目自己的编译校验工具链弄坏了，因此 10-02 的全部改动没有任何编译证据。**（已确认）

`Astra/shaders/lib/settings.glsl:339` 是 `const float sunPathRotation = -40.0; // [-60.0 … 60.0]`，而本批**新增**了它的选项接线：`shaders.properties` 里 `screen.SKY`（`:430`）、四档 `profile.*`（`:449-452`）与 `sliders=`（`:457`）都加入了 `sunPathRotation`。提交 `9f1a931` 的 `shaders.properties` 中该名字出现 **0 次**，`settings.glsl` 里那一行也没有值列表注释——即这四处接线是本窗口新加的。

由此产生三个后果，全部可由本机复现：

1. `qa/tools/compile_glsl.py` **在预检阶段直接退出**：它用 `DEFINE_RE`（只认 `#define`）解析选项，遇到 `sunPathRotation` 抛 `option not found in settings.glsl: sunPathRotation`，exit 1，**一个着色器都没编译**。`qa/review-2026-10-02-compile-stdout.txt` 全文只有这一行错误，正是当时的现场；本报告也用 `--profiles BALANCED --match prepare` 复现了同一失败。
2. `qa/tools/check_pack.py` #2 报 `1 screen token(s) not defined in settings.glsl: sunPathRotation` 与四档 `unknown token(s): sunPathRotation`；#3 报两种语言各有 1 个 key 无对应选项。同一个根因。
3. 结果是**本批所有改动的可编译性完全没有被验证过**：`qa/` 中最后一次成功编译是 `qa/glsl-2026-10-01-*.log`（10-01 16:05），而本批的云影链路、TAA 修改、`lit.fsh`/`diffuse.glsl`/`shaders.properties` 都在这之后。

需要说明的是：把 `sunPathRotation` 做成可调滑块本身是合理功能（它是 Iris 内建、以 `const float` 声明，Iris 会为其提供 GUI 行），**问题在工具没有跟上**——`check_pack.py` 的 `parse_settings()` 与 `compile_glsl.py` 的 `DEFINE_RE` 都只认 `#define` 形式的选项。建议把"Iris 内建、以 `const float ... // [取值]` 声明"识别为一类合法选项，而不是撤掉这个滑块。

这一条的重要性高于后面所有条目：它意味着本批是在**静态门禁为红、编译门禁完全不可用**的状态下累积的，且 10-02 傍晚工作区还在被继续改写（见 §0 的基准说明）。

### 1.1 重要

**F-1 `global/lighting/shadowmap.glsl:128` 把水下焦散唯一的增亮通道夹平。**（已确认代码路径，画面后果未实机验证）

本窗口把

```glsl
transmission = isEyeInWater == 1 ? caster.gba : vec3(1.0);
```

改成

```glsl
transmission = clamp(caster.gba, vec3(0.0), vec3(1.0));
```

而 `program/shadow.fsh:28` 的注释与 `:29-34` 的 `shadowcolor0Format = RGBA16F` 都是为"透射可以大于 1"而写；`global/water/caustics.glsl:54-58` 的 `solas_water_shadow` 返回 `mix(vec3(1),pow(water,0.75),…) * (0.25 + caustics*4.0)`，`caustics` 上界约 1.5 时该式可达 5~6。`shadow_lobe_light`（同文件 `:111`、`:129`）是 `light = dot(allVisibility,weights) + Σ transmission*transparentWeight[i]`，而 `Σ transparentWeight ≤ 1`、`Σ weights = 1`，因此夹到 ≤1 后这条路径**只能压暗、不可能再出现亮斑**。

建议按维度/介质条件化（`isEyeInWater == 1` 时保留 >1 峰值），而不是无条件夹。

**F-2 `program/lit.vsh:180-186` 在末地把 `surfaceShadowPosition` 强制为 0，使末地表面直射阴影整条失效；下界不受影响。**（已确认代码路径，画面后果未实机验证）

`git show HEAD:` 显示旧实现是无条件 `surfaceShadowPosition = shadow_map_position(...)`；新实现为

```glsl
#if defined SHADOWS && !defined DIMENSION_NETHER && !defined ASTRA_WEATHER
    surfaceShadowPosition = shadow_map_position(playerPos, normal,
                                dot(normal, astra_shadow_light_direction()));
#else
    // These lighting paths never consume a projected surface shadow coordinate.
    surfaceShadowPosition = vec3(0.0);
#endif
```

那句注释对**下界成立、对末地不成立**：

- **下界**：`scene.glsl:248-251` 的 `DIMENSION_NETHER` 分支调用 `nether_lighting(albedo, normal, playerPos, blocklight, emissive, portal, frameTimeCounter, params, vertexAO)`，**根本不传 `shadowPos`**，所以零化没有影响。（本报告初稿曾按"两个维度都消费"记录，核对调用链后修正：下界安全。）
- **末地**：`scene.glsl:252-255` 的 `DIMENSION_END` 分支把 `shadowPos` 传进 `end_lighting`，而 `global/dimension/end.glsl:40-45` 正是用它做真实阴影查询：
  ```glsl
  if(dot(normal,end_light_direction())>0.0) {
      float coverage=shadow_coverage(playerPos,shadowPos);
      if(coverage>0.0) visibility=mix(1.0,shadow_opaque_visibility(shadowPos),coverage);
  }
  ```
  传入 `vec3(0.0)` 时 `shadowmap.glsl:70` 的 `if (shadowPos.z <= 0.0 || shadowPos.z >= 1.0) return 0.0;` 先命中，`coverage` 恒为 0，于是 `visibility` 保持 1.0，连 `end_surface_visibility`（`end.glsl:48`，供 lit 阶段高光复用）也被一并置 1。**末地表面因此完全失去投影阴影**，而此时 `SHADOWS` 开启、`world1/shadow.enabled=SHADOWS`（`shaders.properties:282`）确实会产出末地阴影图。

建议：末地保留坐标计算（只排除 `ASTRA_WEATHER`），或把 `end_lighting` 的阴影分支一并收窄，并修正那句注释。

**F-3 三个新布尔选项按项目自订的 SC-28 规则可能注册不到 GUI。**

`.specs/astra-shader/escalations.md:57` 记录了一条经 Iris 1.11.2 字节码验证的规则：`OptionAnnotatedSource` 只解析 `#define`/`const`/`#ifdef`/`#ifndef`，**`#if defined NAME` 不可见**；布尔选项必须存在裸 `#ifdef`/`#ifndef` 引用才会注册，否则没有 GUI 行、且 profile 里的同名 token 无效。项目自己的 `check_pack.py:906-922` 就是这条规则的实现（并排除 `lib/settings.glsl`）。

实测各选项的裸 `#ifdef` 位置（非 settings.glsl 文件）：

| 选项 | 非 settings 裸引用 | settings 内 | 结论 |
|---|---|---|---|
| `SCREENSPACE_REFLECTIONS` | deferred.fsh, water.glsl, nether_reflection*.fsh | 0 | 正常 |
| `VOLUMETRIC_FOG` | volume_fog.glsl | 0 | 正常 |
| `ROUGH_SKY_REFLECTIONS` | sky_reflection_cache.glsl | 0 | 正常 |
| `ENTITY_SHADOWS` | shadow.vsh | 0 | 正常 |
| `VOLUME_FOG_ADAPTIVE` | volume_fog.glsl | 0 | 正常 |
| **`SCREENSPACE_AO`** | **无** | **0** | **全仓库无裸 `#ifdef`** |
| `DIRECTIONAL_SKYLIGHT` | 无 | 1 | 仅在 settings.glsl |
| `CLOUD_TEMPORAL` | 无 | 1 | 仅在 settings.glsl |

三者的默认值分别为 `//#define SCREENSPACE_AO`（关）、`//#define DIRECTIONAL_SKYLIGHT`（关）、`#define CLOUD_TEMPORAL`（开）。若规则成立：

- `SCREENSPACE_AO` 与 `DIRECTIONAL_SKYLIGHT` 默认关闭且无 GUI 行，**用户无法开启**，而 `Astra/README.md` 明确写"方向性天光与屏幕空间 AO 在四档预设中均关闭，需在「光照」页手动开启"——该指引无法执行，两个新功能实际不可达。
- `CLOUD_TEMPORAL` 默认开启，恰好与其 profile token 一致，故行为碰巧正确，但用户无法关闭。

`SCREENSPACE_AO` 是全仓库无裸 `#ifdef` 的一条，证据最硬。另两条的裸 `#ifdef` 确实存在于 `lib/settings.glsl`（`:474`、`:491`），只是被本仓校验器按设计排除；是否存在 "settings.glsl 内不算注册" 的额外层次，建议在游戏内用 Iris 选项页直接确认一次。

### 1.2 次要

**F-4 `program/nether_light.csh:88` 重新采用了本仓 09-25 已实测否决的共享内存分块。**

`docs/archive/2026-09-25-low-end-optimization.md:61` 原文："8³ 工作组配六面 halo，把空体积每组约 3072 次邻居读取压到 896 次加载，但会增加同步、共享存储和实心体素的不必要加载。在 RTX 4050 的同帧九次 dispatch 中，35% 合成实心占用时直接路径约 0.125 ms，共享路径约 0.150 ms；空体积与 80% 占用也更慢。正式源码保留原传播实现。"

本轮以源码读写计数（12.39M→3.80M）为由接入同一手法。早退 `:88` 只覆盖内部格（`i>=512` 的 halo 384 次加载无条件发出），正是 09-25 点名的"实心体素的不必要加载"。数学等价性经核对成立（见 §3），所以这是性能取舍问题，但方向与本仓同卡实测相反，且无新的实机复核。

**F-5 `global/lighting/diffuse.glsl:273-287` BALANCED 默认档的 PCF 降成一维。**

```glsl
#if SHADOW_FILTER_QUALITY == 1
vec2 offset = vec2(lobe == 0 ? -1.0 : 1.0) * (float(SHADOW_SOFTNESS)*0.5);
#endif
```

`offset.y` 恒为 0，竖直阴影边缘不再柔化。四个预设为 `SHADOW_FILTER_QUALITY` = 0/0/1/2（PERFORMANCE/NO_SHADOWS/BALANCED/ULTRA），即**默认档比上一版少一半核**。且 `SHADOW_FILTER_QUALITY == 0` 分支完全不读 `SHADOW_SOFTNESS`，与 `lib/settings.glsl:82` 的"medium/high filter quality only"说明存在口径差。

**F-6 `program/lit.fsh:159` + `lib/rain_particles.glsl:11` 用颜色阈值猜测粒子身份。**

`astra_splash_blue = b>0.74 && r<0.30 && g<0.46`，三个轴都比参考包 Photon 的 `r<0.29 && g<0.45 && b>0.75` 更宽松；门控只有 `rainStrength`/`isEyeInWater`，没有粒子身份判据。被删掉的旧 `lit.fsh` 注释当时明确否决过这个做法（"a guess that silently deletes potion or sculk particles is worse than leaving the splash in place"），新文件自己的注释也承认"matching blue particles can also be hidden"。误删范围（药水/附魔/sculk 粒子）未实机验证。

**F-7 `global/dimension/nether.glsl:67-71` 距离雾被整体移入 `#ifdef BORDER_FOG`。**

旧实现 `float fogDensity = fragDistance * NETHER_FOG_NEAR_COEFF;` 在 `#ifdef` 之外，即近程雾无条件存在；新实现 `float fogFactor = 0.0;` 后仅在 `#ifdef BORDER_FOG` 内赋值，且旧的 `1-exp(-x)` 也换成 `clamp(x,0,1)` 线性段。关掉 `BORDER_FOG` 后下界空气雾恒为 0，`nether_reflection.glsl:16-19` 的接收面雾衰减一并消失，反射不再随距离衰减。

**F-8 `global/atmosphere/weather.glsl:133` 掠射角云影语义反转（有意，但需登记）。**

`if (lightDir.y <= 0.01) return 0.0;` → `if (lightDir.y <= 0.01 || astraCloudShadowFade <= 0.0) return 1.0;`，即光源高度 ≤ 约 0.57° 时云影由"压暗"变为"不压暗"。`docs/2026-10-02-summary-optimizations.md` 第 1 节有散文说明（"低于有效高度时透射返回 1，避免低仰角直接变成全阴"），但未进入任何修复表，属有意变更而非回归。三个调用点中只有 `scene.glsl` 同步加了 `astraCloudShadowFade` 门，另两处靠 `cloud_shadow_cache.glsl:18,25` 内部兜底，未漏淡出。

**F-9 `shaders.properties:47` `colortex9` 全维度常驻全分辨率。**

该附件由 0.75 提到 `1.0 1.0`（该附件显存 +78%，1080p RGBA16F ≈ 16.6 MB），由末地盘面锐度与下界反射共用；Iris 的 `size.buffer.*` 键不带维度命名空间，因此这笔开销所有维度都付。下界 SSR 关闭时该图在两处都无人读写（阶段与 `colortex28` 都已回收，`colortex9` 没有）。

**F-10 `shaders.properties:17` `colortex1` 的 1×1 条件与 GLSL 判定不同源。**

属性端 `(!defined UNDERWATER_LIGHT_SHAFTS || !defined SHADOWS || UNDERWATER_SHAFT_STRENGTH == 0)` 少了 GLSL `ASTRA_UNDERWATER_SHAFTS`（`settings.glsl:501-504`）里的 `!DIMENSION_NETHER && !DIMENSION_END` 一层。下界开着水下光束时 `colortex1` 仍为 0.25/0.5，但两维度既不写也不读。方向安全（不会黑屏），只是与该行"unused effect combinations keep only one texel"的断言不符。

**F-11 死代码与死定义（6 处，均为维护性问题，不影响画面）。**

| 位置 | 问题 |
|---|---|
| `global/water/temporal.glsl`（184 行） | 全仓无 `#include`；函数体在 `#ifdef ASTRA_WATER_TEMPORAL` 内而该宏无定义点，整文件不参与编译。docs 已登记为退役 |
| `global/dimension/nether_volume.glsl` | 无 include，且**未登记进 `PENDING_CONSUMERS`**，导致 `check_pack.py` #4 FAIL |
| `global/atmosphere/volume_fog.glsl:49,53` | `ASTRA_VOLUME_BASE_EXTINCTION`、`ASTRA_VOLUME_RAIN_GAIN` 无读取者；真实数值在 `shaders.properties:828` 另写一份，改 GLSL 常量不影响画面（`check_pack.py` #13 FAIL） |
| `lib/sky_sh9.glsl:88,111,135` | `astra_sh9_clear`/`astra_sh9_accumulate`/`astra_sh9_radiance` 无调用者；生产者 `sky_irradiance.fsh` 内联展开，模块头部记录的 accumulate 契约没有执行点 |
| `shaders.properties:544-561` | `windStrength` / `windTheta` 仍由 CPU 每帧计算（含 4 个 `sin`），但 GLSL 侧已无读取者；`wind.glsl:65` 自己也写着"What the CPU uniforms did before" |
| `global/dimension/nether.glsl:89-91` | `skyFogStrength` 在本函数内恒被赋 0，`if (skyFogStrength > 0.0)` 不可达（既有） |

另有两处未接线但无害的资源：`textures/astra-ripple-3.png`（已从 `customTexture` 注销但文件仍在，未上传故不占显存）、`textures/bliss-nether-noise.png`（同理）。

### 1.3 水体通道

**F-12 `program/water.glsl:76` 反射锥角点相对 HEAD 是净增，不是 README 说的净减。**（已确认）

对比同一条代码：

| | HEAD | 现在 |
|---|---|---|
| 锥数 | `reflected && radius > 0.0 ? 4 : 1` | `reflected && radius > 0.35 ? maxFootprints : 1` |
| `maxFootprints` | 固定 4 | 1 / 5 / 9（按 `WATER_EFFECT_QUALITY`） |
| 每锥角点 | 4（2×2 双线性） | 4 |
| **最大角点读取** | **16** | PERFORMANCE 4、**BALANCED 20**、**ULTRA 36** |

`lib/settings.glsl:143` 的自述（"1/5/9 bilinear footprints"）与代码一致。因此相对最后一次提交，默认档 16→20（**+25%**）、ULTRA 16→36（**+125%**），只有 `radius ≤ 0.35` 的子像素锥由 16 降到 4。

`Astra/README.md` 写的"默认水反射宽过滤从最多 36 个角点减至 20 个"只在**同一未提交窗口内部的中间态**之间成立（某轮曾把默认设为 9 锥），相对 HEAD 方向相反。这是水体通道本轮唯一明确的采样增加项，也是文档口径需要修正的一处。

**F-13 `program/water.glsl:372` 新增的"未偏移路径"复用判据永不成立。**（已确认，结构性）

```glsl
vec2 refractedUV = water_refracted_uv(depthtex1, viewPos, viewNormal - viewGeometric);
unshiftedPath = all(equal(refractedUV, uv));   // uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight)
```

`refractedUV` 是投影重建的连续值（含 jitter），`uv` 恒为像素中心 `(i+0.5)/W`，两者最多差半像素且浮点路径不同，逐位 `equal` 不可能为真，故 `:387-389` 的 `straight = transmitted` 是死分支，第二次 `water_sample_path` 仍全量执行。`docs/2026-10-02-module-performance-review.md` 第 14 行本来就写明"不引入接近值阈值，不复用不同位置的样本"——即这是**有意的保守选择**，但结果是该条优化实际收益为零，docs 不应把它计入裁减。折射的零强度早退（文档第 6 节）确实成立。

**F-14 `qa/tools/underwater_light_probe.py:17` 引用了已删除的模块，探针 shader 已无法编译。**（已确认）

该文件仍 `#include "/lib/water_light_field.glsl"` 并在 `:28/:30/:32/:36` 调用 `astra_water_phase`/`_beam_tint`/`_beam_limit`，而 `lib/water_light_field.glsl` 已在本窗口删除、`Astra/shaders` 内已无任何残留引用。这是全仓库唯一残留，属删模块时漏改的工具。

**F-15 `global/water/temporal.glsl` 的附件契约已被现役代码占用，重新接线会同时污染两条链路。**（已确认，当前潜伏）

该 orphan 文件内部把 `colortex28` 当作"水面 SSR 命中辐亮度历史"、`colortex29` 当作"命中点偏移 + 时间戳"；而现役代码里 `colortex28` 是下界粗糙反射的法线/覆盖（`program/nether_reflection.fsh` 的 `RENDERTARGETS: 9,28`），`colortex29` 是水下光束历史（`program/scattering.fsh:83-86`）。照原样把它接回去会破坏下界反射与水下光束。建议在文件头显式标注"附件号已回收，接线前需重新分配"。

**F-16 `global/water/light_shafts.glsl:73` 删除 `beam_tint` 后，远场光束的距离衰减没有等价替代。**（代码事实已确认，观感未验证）

HEAD 有 `exp(-vec3(0.14,0.035,0.018)*d)` 与 `shade /= max(2.0, currentDist*0.06)` 两项；新 march 只有随距离增大的 `intensity = pow((currentDist/128.0)/count, 1.0 - time*0.5)`，即相对 HEAD 远场光束明显变亮。对照 Solas 参考的 `volumetricLight.glsl` 确认参考本身也没有这两项，属"对齐参考"的有意取舍而非抄漏。

### 1.4 TAA 与时域抗锯齿

出厂 `ANTIALIASING=1`（FXAA），四档 profile 都不含 TAA，**关闭时经核对为零成本**（`composite6/7` 的 9 处 properties 条件与 `settings.glsl:497` 逐字一致，`colortex15/16/22/17` 全部缩到 1×1，相关分支与抖动一并编译期剔除）。因此 TAA 本身不是性能项，而是"用带宽买画质"：开启后是本批最重的单项后处理。

**F-17 `program/taa_resolve.fsh:136` 历史权重是常数，不随帧时长归一，收益随帧率漂移。**（已确认源码事实，未实机量化）

```glsl
float weight = mix(0.92,0.70,motion) * (1.0-reactive) * h.a * colorTrust * centreTrust;
```

整个 pass 没有 `frameTime`/`frameTimeCounter` 参与混合（`frameCounter` 只用于状态校验与抖动索引）；同仓库 `cloud_temporal.glsl:86` 反而用 `float dt = frameTime` 做连续性判据。后果是 240 fps 下 0.92 的等效历元约 0.05 s（几乎不收敛，抗锯齿收益接近 0），30 fps 下约 0.4 s（收益大、拖影窗口也大）——同一画质档在不同帧率下表现不一致。

**F-18 `program/deferred.fsh:166-168` 在 `CLOUD_MODE==0` 时把整片天空标成 reactive。**（已确认，过保守但不产生鬼影）

```glsl
#if !defined DIMENSION_END && CLOUD_MODE == CLOUD_VANILLA
if (depth >= 0.999999) reactive = 1.0;
#endif
```

这比逐像素判据更宽：`CLOUD_MODE==1` 用的是 `if (sheet.a > 0.001) reactive = 1.0`，且 `clouds.fsh:43` 已单独为云片元写过 reactive。受影响的是 PERFORMANCE / NO_SHADOWS 两档（`CLOUD_MODE=0`），星点与天空渐变在该档不再抖动收敛。

**F-19 `program/deferred.fsh:169-172` 下界把 reactive 全屏下限抬到 0.65，使该维度 TAA 权重上限仅 0.35。**（已确认）

`reactive = max(reactive, 0.65)` → `(1.0-reactive) ≤ 0.35`。注释的理由是"animated smoke has no single geometric motion"，但静态下界岩石在 `lit.fsh:344` 本已被判 `reactive=0`（可精确重投影），一并被这条下限压掉。结果是下界既拿不到抗锯齿，又保留 1–2 帧的模糊核，净效果偏糊。

**F-20 TAA 开启时的负载：每像素最多约 28 次纹理访问，新增全分辨率附件约 35 MB@1080p。**（源码级计数已确认，带宽/帧时未实测）

`taa_resolve.fsh` + `lit.vsh:150-164`：`colortex0`（1 次双线性 + 9 邻域）、`depthtex0`、`colortex16`（≤9 次 3×3 膨胀）、`colortex15`（≤4 次双线性）、`colortex22`、`colortex17`（3 次），并写出 `colortex0`(4 B) + `colortex15`(8 B)；`colortex15/16/22` 为新增全分辨率附件，合计 17 B/px ≈ 35 MB@1080p（`shaders.properties:82-83` 只声明了 15、17，16/22 吃全分辨率默认值）。另外每个植被顶点要做 1–4 次顶点纹理取数（`colortex17`），植被密集场景是十万级 VTF/帧。

**F-21 TAA 全路径在 10-02 改动之后没有编译或实机证据。**（已确认）

`qa/` 中最新的 TAA 全量编译记录是 09-30 的 `linked=105 failed=0`（小矩阵记录停在 10-01 16:05），而 `lit.fsh`、`lib/taa_state.glsl`、`shaders.properties` 的最后修改都在 10-02 傍晚之后。本机复跑 `python qa/tools/compile_glsl.py --profiles ULTRA --set ANTIALIASING=2` 直接失败：缺少 LWJGL 3.3.3（`.minecraft/libraries` 与工作区均无该套 jar）。**这意味着本批着色器的可编译性在本次审查中没有被验证过**，属共同限制（见 §8）。F-0 给出了更根本的原因：编译工具本身在预检阶段就退出了。

### 1.5 AO 与 SSAO

SSAO 默认关闭（`settings.glsl:39` 注释掉），四档 profile 全部 `!SCREENSPACE_AO`，**关闭时经核对为零成本且与旧链等价**（19/20/21/26/27 全缩 1×1、`deferred2` 停用、`ao_resolve` 与调用点整体编译剔除）。但开启时它是纯新增开销，不替换任何既有 AO（只做 `min(vertexAO, SSAO)` 的环境项收紧）。

**F-22 `program/ssao.fsh:30-110` 生产者每半分辨率像素典型约 29 次纹素读取。**（静态计数已确认）

prologue 4×`depthtex0`（`:38`）+ ≤4×`colortex20`（`:41`）；12 点核每点 2 次（`colortex20:72` + `depthtex0:73`）= ≤24。折算到全分辨率约 7.2 读/像素，1080p 生产者约 1500 万次/帧。

**F-23 `lib/ao_resolve.glsl:32-90` + `program/deferred.fsh:184` 合成 pass 无条件付 5–20 次读取。**（静态计数已确认）

每个不透明可接收像素固定 1（`colortex20:56`）+ 4（`colortex21:32`）次，即使 SSAO 一点额外遮挡都没加；开方向性天光时再加 ≤4×26、1×27、9×18、1×19，上限 20 次。1080p 全分辨率额外 1040 万–4150 万次/帧，与生产者合计约 2500 万–5700 万次/帧。

**F-24 `program/ssao.fsh:71-73` 两次读取顺序颠倒，半径裁减省不了带宽。**（已确认）

`:72` 先读 `colortex20` 的资格位，`:73` 才读深度，而 `:74/:78/:82/:90` 的所有早退都需要深度。把深度读取提前，就能在天空样本与超出世界半径的样本上跳过那次资格读取。

**F-25 `program/ssao.fsh:64-67` 12 点核无噪声、无逐像素旋转。**（已确认，图案可见性未验证）

`angle = float(i)*2.39996323`、`r = sqrt((float(i)+0.5)/12.0)` 只依赖 `i`，无 `frameCounter` 或噪声项；唯一的空间滤波是 `ao_resolve` 的 4-tap 保边（`:38` 的 `pow(agreement,8)`），不消除固定图案。半分辨率输出上的静态结构化图案与远处轮廓串联无法离线判定。

**F-26 `shaders.properties:128-146` AO 附件按包全局分配，下界与末地承担死显存。**（已确认）

`:128` 的门不含维度条件，加维度守卫的是 `settings.glsl:473-479`；`world-1/world1` 只停用了 `deferred2`（`:145-146`）。1080p 下 19+20≈16.6 MB、21≈4.2 MB、26/27≈12.4 MB，合计 **25–33 MB** 在只跑主世界的功能上常驻。

**F-27 `program/lit.fsh:253-256` + `lib/surface_buffers.glsl:24` `colortex27` 实为无 alpha 的 `R11F_G11F_B10F`。**（已确认，口径不一致，实际风险低）

"写 alpha=1 保证覆盖"的注释理由不成立，且 `properties:345-407` 只给 19/20（还有 16/22）配了 blend 覆盖，`colortex27` 只出现在尺寸行。`docs/handoffs/2026-09-27-R1-bent-normal.md:61` 记的是 RGBA16F / 15.82 MiB，实际为 8.29 MB。无 A 时 GL 把源 alpha 读作 1.0，覆盖仍然成立。

**F-28 `program/lit.fsh:156` `rockSmoothness` 在主世界算完即弃。**（已确认）

消费者只有末地镜面（`:293`）与下界反射 mask（`:427`）。`astra_rock_emission` 在全包已 0 命中（函数与调用都已删），而 `block.properties:63-85` 仍写着 "see program/lit.fsh, branch `material >= 12u`"——该分支已不存在，属悬空注释。

**AO 侧核对成立**：`min()` 上限语义、7 位顶点 AO 经 RGBA8 往返精确（`(128+level)/255` 与 `round(a*255)-128` 互逆）、4-bit 材质来自 `faceData` 位 18..21 无 ID 冲突、AO 侧只存 1 位资格位、零权重早退在 `texelFetch` 之前（与包内另 7 处同一约定）、`deferred.fsh:188` 单次 `texelFetch` 供三用途且 `round(r*255)` 与 `float(lightData)/255` 精确互逆、关 AO 时 `resolve` 零成本、`deferred`/`deferred1`/`deferred2` 三种组合与 properties 门一一对应且无重复合成。

### 1.6 云

**先说一个容易误读的前提：整套平面云生产链是本批新增。** `git ls-tree 9f1a931` 显示 `prepare.fsh`/`prepare1.fsh`/`prepare2.fsh`、`colortex11/12/14/24/25`、`clouds_screen.glsl`/`cloud_temporal.glsl`/`cloud_shadow_cache.glsl`、`program/cloud_screen.fsh`/`program/cloud_shadow_cache.fsh` 在最后一次提交时**全部不存在**。所以这不是"改造现有云链"，而是新增一条链。

**F-29 `CLOUD_TEMPORAL` 不可发现，而这条时域历史恰好是未标定的。**（已确认，见 F-3）

后果比 F-3 里写的更具体：`docs/handoffs/2026-09-27-R6-cloud-temporal.md` 自己承认 0.90 基权是**未标定的初值**，选项恒开、四档 profile 的 token 无效，用户**没有任何关闭手段**；一旦出现鬼影无法回退。`Astra/README.md` 与 `docs/2026-10-02-colour-and-quality-options.md:48` 描述的这个开关用户拿不到。

**F-30 `program/cloud_screen.fsh:24` 生产者以 `1e20` 调用，地形早退只对消费者生效。**（已确认）

`clouds_planar.glsl:275-276` 的 `sampleDistance >= maxRayDistance → break` 早退本身有效，但两个生产者（`cloud_screen.fsh:24`、`sky_reflection_cache.fsh:14`）都传无限远，于是**每个被地形挡住、永远不会显示云的像素也要做一次全板步进**。基线（`9f1a931` 的 `deferred.fsh`）只在地形像素以 `cloudTerrainDistance` 步进（近处立即退出≈0），天空像素走一次全板步进。现在变成 `q × 全屏` 一次全板步进（`q` = 1/16、1/4、1 对应 `CLOUD_QUALITY` 0/1/2）。按天空占比 0.3 估算：PERFORMANCE 明显减少、BALANCED 大致持平、**ULTRA 的云步进像素数由 0.3 屏升到 1 屏**，是该档的净亏项。

**F-31 `docs/handoffs/2026-09-27-R6-cloud-temporal.md:108` 的采样账目过时约 3 倍。**（已确认）

文档写"至多 3 次缓冲采样（meta 最近邻 1 次 + 历史 2 次双线性）"；现行代码是 `cloud_temporal.glsl:84` 的 1 次 `metaHere` 加上 `:119-134` 的 2×2 循环每 tap 各 1 次 meta（`colortex25`）+ 1 次颜色（`colortex24`），即每半分辨率纹素**最多 9 次 `texelFetch`**。逐 tap 读 meta 是必需的（`:126-129` 逐纹素有效性/代表距离判定），是账目没更新，不是死读。

**F-32 `global/atmosphere/cloud_shadow_cache.glsl:8` 的 `ASTRA_CLOUD_SHADOW_TEXEL = 2.0` 无任何读者。**（已确认）

全仓只有该定义与 `shaders.properties:827` 的注释引用它；`shaders.properties:820` 实际硬编码 `floor(x/2.0)*2.0`。CPU 的 2 格吸附与 GLSL 的纹素尺寸只靠 `EXTENT 512 / size.buffer.colortex14=256 256` 隐式耦合——读写仍彼此一致，但改缓冲尺寸或 `EXTENT` 时，"2 格对齐网格"这条文档会静默失配。

**F-33 `program/clouds.fsh:26-31` 平面云模式下原版云几何仍被提交并逐片元 discard。**（已确认）

全仓 `gbuffers_clouds` 只命中 blend 指令（`properties:300/309/339`），没有任何 `.enabled=`。`discard` 不省顶点变换、光栅化和片元调用，所以"三层叠加"只消除到"一层着色 + 一层空转光栅"。

**云侧核对成立**：多层重复渲染确实已消除（平面云只由 `prepare1` 生产一次，`deferred` 与 `sky.fsh` 只消费）；地形早退非恒假；时域历史**真独立于 TAA**（`cloud_temporal.glsl:44-48` 在 `#ifndef ASTRA_TAA` 下自声明前帧 uniform，失效门自带时间中断/首帧/NaN/相机位移/投影逐列/帧序号/`dt∈[0,0.5]`/屏幕外/邻居有效性，不读任何 TAA 状态，TAA 关闭时抖动返回 0 故不存在"历史永不失效"）；抖动重投影符号自洽；云影锚点写读用同一 `astra_cloud_shadow_anchor()`，half-texel 也对齐；云历史的颜色读取确实在所有拒绝之后；云影近地平线的 CPU 单点曲线与 GLSL 只应用一次。

**附件账目有一处口径冲突（疑似）**：`colortex11` 258×128 R11F≈129 KiB、`colortex14` 256×256 R16=128 KiB、`colortex24/25` 各 3.96 MiB，合计 7.92 MiB；但 `cloud_temporal.glsl:11-13` 自述依赖 Iris 缓冲翻页，按 `Astra/README.md:66` 对 `colortex14` 的"双纹理"口径，两张历史附件应约 **15.8 MiB**。仓库内无法验证 Iris 的 alt 附件分配，故列为疑似。

## 2. 已核对成立的性能声称

以下逐项独立验算成立，可作为本批的可靠收益：

| 声称 | 核对结果 |
|---|---|
| Bloom 捕获默认 13→9 次场景读取 | **成立**。`bloom.glsl:110-135` 为 4/9/13 三档；均衡档 3×3 二项式的每轴二阶矩 = `0.5·(√3)² = 1.5`，与高档 13 点核逐轴矩 `(1+1+1)/2 = 1.5` **完全相等**，并非近似匹配 |
| 体积雾自适应步数表（32→4/4/8、96→6/12/24、192→12/24/48） | **成立**。`volume_fog.glsl:142` 为 `min(steps, max(4, ceil(steps·marchLength/192)))`，`ASTRA_VOLUME_MAX_DISTANCE=192`、`ASTRA_VOLUME_STEPS`=12/24/48、`ASTRA_VOLUME_PREFIX_STEPS`=4/8/12，逐格验算与 docs 表格一致 |
| 关闭自适应＝固定次数＋均匀分段 | **成立**。`int sampleCount = steps;` 在 `#ifdef VOLUME_FOG_ADAPTIVE` 之外，二次分段 `:152-153` 在之内 |
| 透射早退不吞掉远处余段 | **成立**。`if (volume.a < 0.002) break;` 之后的 `:164-171` 解析余段未被 `volume.a` 门住 |
| 平行阴影空间射线重组与旧路径等价 | **成立，且比 docs 的说法更强**。等价性不依赖"仿射"，而依赖阴影视图矩阵仿射 + 投影矩阵在齐次向量上线性 + 齐次除法与 `distort` 仍逐点执行，故 `c(t)=c0+t·cR` 与旧路径逐分量相同 |
| TAA 抖动八相位表 CPU 与 GLSL 一致 | **成立**。`shaders.properties:812-815` 与 `taa_jitter.glsl:12-19` 的 x/y 逐项相等（`−3/18 = −1/6` 等），有限周期居中常数 `0.0546875` 两侧相同，GLSL 回退表与 CPU 表的取用分支也一致 |
| 方向性天光配对数学与系数分配 | **成立**。偶基（0,2,3,6,7,8）→ 1.08、奇基（1,4,5）→ 0.92，**未互换**；与旧实现"下半球查镜像方向再乘 0.08"精确等价，128→64、1152→576 成立。SH 常数、L2 阶数、余弦卷积 `A_l`、投影/重建互逆均正确 |
| `deferred.fsh` 的 `colortex3` 合并为一次读取 | **成立**。`surface.r`→`lightData`、`surface.gb`→法线、`surface.a`→`standingWater`，删掉重复的 `texelFetch`，净 −1 次采样 |
| 阴影采样默认减半 | **成立**。4 lobe → 2 lobe（每 lobe 1 次 `shadowtex0` gather + 视情况 1 次 `shadowtex1` + 最多 4 次 `shadowcolor0`），约 −50%，但其中一半是拿画质换的（见 F-5、F-1） |
| 大雾零贡献早退（体积雾重建、水体过滤、AO 重建、TAA 零权重角点、下界反射元数据先行、末地盘面四角复用锚点、末地星光零可见度跳过等） | **成立**。均为读取前早退，未发现"先读后拒"的无效写法；`solas` 焦散那条除外（F-1 是值域问题而非顺序问题） |
| 阶段调度：属性端与运行期同源 | **成立**。`composite3`（关闭 Bloom 时合并水下合成）与 `composite2`（零强度/被体积雾替代的空气光束）的属性条件与其附件消费者的编译期守卫严格互补，未出现"删了 pass 却仍在读附件"的黑屏路径；`display.fsh` 不是第二套显示路径，`final.fsh` 是 FXAA/非 FXAA 选择器，二者启用条件互斥 |
| 下界体素零值早退不吞光 | **成立**。不发光实体格存的就是 0，发光格 `id>1` 仍取数，OOB 邻居在正衰减下保序 |
| 晨雾高度权重修正只乘一次 | **成立**。`fog.glsl:79-81` 返回 0.22–0.62，`scene.glsl:162-165` 单点直乘，无二次 `mix` |
| 天气/湿面/云影锚点等参数 CPU 化与 GLSL 逐项等价 | **成立**。`astraWetWeather`、云影锚点（192 格高度、2 格对齐）、云影高度淡出曲线 CPU 与 GLSL 两侧一致 |
| 折射零强度早退在所有写输出之前 | **成立**。`refraction.glsl:13` 是纯函数早返回（无 `out` 参数），调用端两条路径都完成 `colortex0`/`colortex5` 写入，不存在未定义附件；水下另用 `#if REFRACTION_STRENGTH > 0` 做编译期移除 |
| 零权重角点跳过不改变归一化 | **成立**。`water.glsl:100/103/136`、`light_shafts.glsl:105-111` 的跳过同时门控 `weights` 与 `sideSum`/`spatialWeight`，`/=weights` 的分母同步收缩 |
| 环境 BRDF 不引入能量增益 | **成立**。`environment_brdf.glsl:23` 的 `gain = brdf(r)/brdf(0)` 后 clamp 0–1，`r=0` 恒为 1、任何 `r` 都 ≤1；水体实际粗糙度 0.035–0.135 下比值为 0.99–1.0 |
| 天空缓存 mip 时序与接缝 | **成立**。mip 指令在 `prepare2.fsh:6`，Iris 在包含该指令的程序**之前**生成 mip，而 `colortex11` 只由 `prepare.fsh` 写入、此后无人重写，故 mip 不会失效；写入端列 `i` 位于经度 `(i+0.5)/256`、消费端 `x = uv*size-0.5` 正落在列心，缝内 `mix(last,first,fract(x))` 无 off-by-one；非 rough 分支的 `u=(fract*256+1)/258`、`v` 夹 `0.5/128` 与 258×128 吻合 |
| `colortex29` 的重置覆盖 | **成立**。时间跳变、分辨率、投影矩阵、水下进出、相机 8 格、frameTime 0.25 s 窗口都在 `effect_history.glsl:17-31`；RGBA16F、`clear=false`，同 pass 读写依赖 Iris 的 colortex 双缓冲翻转 |
| 末地不读天空缓存、不误用仅主世界的模块 | **成立**。`astra_reflection_sky`（`scene.glsl:62-71`）在末地走解析 `end_sky()`，在末地走 `nether_sky()`，只有主世界的 `astra_sky_reflection` 才读 `colortex11`；`ASTRA_SSAO`/`ASTRA_VOLUME_FOG`/`ASTRA_CLOUD_TEMPORAL` 都在 `settings.glsl:473-494` 带 `!NETHER && !END` 守卫 |

## 3. 管线接线核查

新增的 13 个 `program/*.fsh`（`ssao`、`taa_resolve`、`taa_state`、`display`、`volume_main`、`volume_slot`、`cloud_screen`、`cloud_shadow_cache`、`nether_reflection`、`nether_reflection_resolve`、`sky_irradiance`、`sky_reflection_cache`、`effect_history_state`）**全部可达**，不存在写了没接线的孤儿：

```
deferred.fsh(root)      → ssao.fsh / volume_main.fsh / program/deferred.fsh   (按 ASTRA_SSAO / ASTRA_VOLUME_FOG 三选一)
deferred1.fsh(root)     → volume_slot.fsh → volume_main.fsh 或 program/deferred.fsh
composite6 / 7 / 8 / 9  → taa_resolve / taa_state / display / effect_history_state
prepare / 1 / 2 / 3     → sky_reflection_cache / cloud_screen / cloud_shadow_cache / sky_irradiance
final.fsh               → display.fsh（非 FXAA）或自身 FXAA 分支
world-1/composite{,1}   → nether_reflection / nether_reflection_resolve
world1/prepare          → end_illumination（末地自己的 prepare，与根 prepare 不同）
world1/deferred         → end_sky_buffer；world1/deferred1 → program/deferred.fsh（DIMENSION_END）
```

维度拆分是有意的，并在 `shaders.properties:145-151` 等处写明：`world-1` 不继承根 `deferred1` 外壳，末地自带 `world1/deferred1`；`world1/composite9` 恒关且末地无该文件，故 `colortex30` 在末地从不写入——两条 `effect_history` 消费者（下界反射、水下光束）都由宏限死维度，**当前不会读到未初始化数据**，但这是靠"消费者恰好不重叠"维持的，属隐患而非现存缺陷。

`ASTRA_SSAO`、`ASTRA_VOLUME_FOG`、`ASTRA_CLOUD_TEMPORAL` 均在 `settings.glsl:473-494` 带 `!DIMENSION_NETHER && !DIMENSION_END` 守卫，所以末地不会读到无人生产的 `colortex23`，也不会误调用了仅主世界有效的 AO——这一层设计是干净的。

## 4. 显存与资源账

自定义纹理（解码后 raw RGBA8，未计 mipmap）：

（只统计真正写进 `customTexture` 注册表的纹理；`astra-ripple-3.png`、`bliss-nether-noise.png` 只在磁盘上，未注册故不上传。）

| 纹理 | 本窗口前 | 现在 | 变化 |
|---|---|---|---|
| `astra-end-transfer.png` | 2048² = 16 MiB | **4096² = 64 MiB** | **+48 MiB** |
| `astra-end-flow.png` | 512² = 1 MiB | 1024² = 4 MiB | +3 MiB |
| `astra-end-flow-mips.png` | —（新增） | 514×1043 ≈ 2.05 MiB | +2.05 MiB |
| `astra-end-transfer-meta.png` | 1024² = 4 MiB | 1024² = 4 MiB | 0（按 `build_end_transfer.py` 仍固定 1024²） |
| `bliss-nether-noise.png` | 512² = 1 MiB（当时已注册） | —（注销） | −1 MiB |
| 其余（涟漪 1/2、solas/steadfast 水噪声、云噪声） | 约 8.8 MiB | 约 8.8 MiB | 0 |

**净增约 52 MiB，已注册自定义纹理总量由约 31 MiB 升到约 83 MiB，其中 `astra-end-transfer` 一张占约 77%。** 若 MC 的 mipmap 档位 > 0，该图还会再增约 33%（≈ +21 MiB）。

这与 `qa/tools/build_end_transfer.py` 的 `SIZE = 4096` 一致，是刻意的画质提升（`build_flow_mips()` 为其生成手工 mip 图集，并配 `astra-end-flow-mips.png.mcmeta` 的 `{"texture":{"blur":true,"clamp":true}}`）。但需注意：`end_kerr.glsl:64` 用 `atlasSize.x/12.0` 推导足迹，图集分辨率翻倍会同时改变 mip 淡出的尺度；且该纹理作为 `customTexture` 在**所有维度**常驻，包括从未使用它的主世界与下界。

结论：这是本批最大的一笔资源支出，且属于画质而非性能。放进"性能优化"批次里与 §1 的各项带宽节省方向相反，建议在报告中单列。

## 5. 项目自带校验器结果

`python qa/tools/check_pack.py` → **8 FAIL / 9 PASS**，退出码 8。注意本轮 `check_pack.py` 自身被放宽过两处（见 §6），因此这不是"工具变严"造成的。

| # | 结论 | 要点 |
|---|---|---|
| 1 | PASS | 156 个选项，36 布尔 |
| 2 | **FAIL** | `sunPathRotation` 不是 settings.glsl 选项（Iris 内建），却出现在 `screen.SKY` 与四档 profile；`PURKINJE_STRENGTH`、`ROUGH_SKY_REFLECTIONS` 未被任何 profile 覆盖（四档 `quality complete=False`） |
| 3 | **FAIL** | 同 `sunPathRotation`：两种语言各有 1 个 key 无对应选项 |
| 4 | **FAIL** | `nether_volume.glsl` 孤儿且未登记；`deferred.fsh`、`prepare2.fsh` 两个 layer-1 外壳直接 include `lib/settings.glsl`，违反 design 3.2 分层 |
| 5,6,7,9 | PASS | 声明层、custom uniform 与 GLSL 声明、block/entity.properties、Bayer 矩阵 |
| 8 | **FAIL** | THIRD-PARTY.md 的 `astra-only` 计数 35 与表达式差异 121 不符，需重跑 `provenance_steadfast.py` |
| 10 | PASS | 最小 final 链存在 |
| 11 | **FAIL** | `colortex9Format` 被两处重复声明（`end_sky_buffer.fsh`、`nether_reflection.fsh`，取值一致故无冲突）；**SC-28 三条未注册选项**（见 F-3） |
| 12 | **FAIL** | `profile.BALANCED` 与 settings.glsl 默认值不一致（`PURKINJE_STRENGTH`、`ROUGH_SKY_REFLECTIONS` 未列出） |
| 13 | **FAIL** | 两个无读取者的 `#define`（见 F-11） |
| 14 | PASS | 32 个附件、110 条声明均活且唯一 |
| 15 | **FAIL** | `global/post/fxaa.glsl` 在 `lib/vendor/` 之外携带完整许可文本 |
| 16,17 | PASS | 维度门控键名、内建 uniform 类型面 |

**这批改动是在项目自带门禁为红的状态下留在工作区的。** 其中 #2/#3/#12 互相牵连（`sunPathRotation` 与两个未覆盖选项），#4 与 #11、#13 是新增文件/定义带来的，建议在提交前先清零。

## 6. 文档与工具一致性

- **docs 的算术经抽查可靠。** `2026-10-02-module-performance-review.md:29` 的 `8³+6×8²=896`、`:117` 的 `64³×(4+8+8)=5 MiB`、`:143` 的 `6K→6`、以及自适应步数表都验算正确；文档也反复声明"不能换算为固定 FPS"，这一点值得保留。
- **README 与实现有偏差（两处）。** 其一，`Astra/README.md` 写"方向性天光与屏幕空间 AO … 需在「光照」页手动开启"，但按 F-3 这两项目前无法开启。其二，README 称"默认水反射宽过滤从最多 36 个角点减至 20 个"，已独立复核为**方向相反**：相对 HEAD 是 16→20（见 F-12），该说法只在同一未提交窗口的中间态之间成立。
- **"参数移到 CPU"的叙事有一处反向残留。** F-11 表中的 `windStrength`/`windTheta` 是 CPU 仍在算、GPU 已不读，与"把公共参数移到 CPU 以省 GPU"的方向相反，属净增的 CPU 每帧成本。
- **`check_pack.py` 本轮被放宽两处**：选项数上限（原 60–80，现仅 `>= 60`）与 profile 完整性（现只要求"质量选项"子集，颜色类豁免）。同时也有收紧（`ANTIALIASING`/`SHADOW_FILTER_QUALITY`/`CLOUD_QUALITY`/`VOLUME_FOG_QUALITY` 加入单调性检查，`PENDING_CONSUMERS` 机制）。放宽本身合理，但上界消失后"选项膨胀"不再有任何自动约束，而本批正好新增了十数个选项与 66 个 RGB 通道。
- **`qa/tools/render_end_design.py`** 的预览端 `end_bloom` 权重由 `.35` 改为 `.21`，并新增 `astraEndFlowMips` 绑定与按 `shaders.properties` 读取 `colortex9` 缩放的逻辑——说明此前预览工具与着色器并不一致，之前的末地预览结论需重新看待。
- **文档索引漏登记一份。** `docs/README.md` 是仓库自定的文档入口，其"活跃文档"表列了 12 份，`docs/` 下实有 18 份（不含 README 自身）。逐个比对后，唯一被漏掉的是 `docs/2026-10-02-batch2-implementation.md`——而它正是"时间跳变停止沿用旧历史"、"体积雾平行阴影射线"、"粗糙天空反射"三项改动的实施记录，且 `docs/README.md` 在同一窗口被修改过。34 条索引引用全部可达，没有断链。

## 7. 建议的修复顺序

1. **F-0**（编译门禁失效）：修 `compile_glsl.py` / `check_pack.py` 对"以 `const float … // [取值]` 声明的 Iris 内建"的识别，先把编译验证恢复，再谈其他。**在编译门禁恢复之前，本批不宜合入。**
2. **F-1**（水下焦散夹平）与 **F-2**（末地直射阴影失效）：都是"改了生产者、忘了值域/消费者"，且影响既有画面，建议先条件化。
3. **F-3 / F-29**（`SCREENSPACE_AO`、`DIRECTIONAL_SKYLIGHT`、`CLOUD_TEMPORAL` 未注册）：给三者各补一处非 `settings.glsl` 的裸 `#ifdef` 站点，再在游戏内确认选项页出现。这是两个新功能的可用性前提，也是云历史唯一关闭手段的来源（`CLOUD_TEMPORAL` 的 0.90 基权尚未标定）。
4. **check_pack 清零**：F-11 的死定义与孤儿文件、`sunPathRotation`、两个未覆盖选项、`colortex9Format` 重复声明、THIRDPARTY 记账、fxaa 许可文本、`prepare2.fsh`/`deferred.fsh` 的分层违规。
5. **F-9 / F-26 / §4 资源账**：确认 4096² 传输图集、`colortex9=1.0`、AO 附件（25–33 MB 在下界/末地空转）是否为有意的画质投入；面向低配时考虑按维度或按档位回收。
6. **F-30**（云生产者不做深度过滤）：ULTRA 档的净亏项，低成本的缓解是让生产者以实际地形距离调用，或在平面云模式下 `program.gbuffers_clouds.enabled=false`（F-33）。
7. **F-4**（体素共享内存）：在实机上重跑 09-25 的同帧计时对照，再决定保留或回退。
8. **F-5、F-6、F-7、F-8、F-10、F-12、F-13、F-16、F-17~F-20、F-22~F-25、F-27、F-28、F-31、F-32**：画质/口径/维护类，按观感预算决定，并逐条补进 docs 的变更表（含把 R6 的采样账目更新为 9 次、把 `temporal.glsl` 标注为附件号已回收）。

## 8. 审查边界

- **未做着色器编译验证，而且原因是本批自己造成的。** 根因见 F-0：`compile_glsl.py` 被新增的 `sunPathRotation` 选项接线卡在预检阶段，一个着色器都没编译；本机同时缺 LWJGL 3.3.3，无法绕过。`qa/` 中最后一次成功编译是 10-01 16:05，早于本批的云链、TAA 与 `lit`/`diffuse`/`properties` 改动。因此**本批改动是否都能编译链接，本次审查没有任何证据**；`check_pack.py` 是纯静态检查，不能替代编译。这是本报告最重要的能力边界。
- **工作区在审查期间被并发改写**（详见 §0 的基准时刻说明）：`git diff` 规模在同一次审查内增长，多个文件在 19:17–19:21 相继被修改。行号对应快照，结论按当时内容复核；建议在改动停止后重新对照一次。
- 未运行游戏，未测帧率；所有"净收益/净亏损"都是**源码工作量**层面的账，不是实测耗时。驱动可能已消除部分原有重复表达式。
- F-3 依赖本仓自订的 SC-28 规则（有字节码依据但非本次独立复核）；另两条的最终判定应在 Iris 选项页确认。
- F-1、F-2、F-6、F-7、F-8 的**代码路径**已确认，**画面后果**未验证。F-2 的适用维度已按调用链修正为仅末地（下界不传 `shadowPos`）。
- 末地岛体 SDF 预求值、`end_system` 星场、吸积盘细节层裁减等末地改动只做了抽查（四角复用锚点、零可见度跳过星场均成立），未逐条复核 `end_geometry.glsl` 的每一步；末地文件在审查末尾仍被改写（`end_system.glsl`/`end_blackhole.glsl` 19:20、`tonemap.glsl` 19:21）。
- 本报告不含对参考包实现的研究结论；引用参考包处仅用于对照阈值宽严。
