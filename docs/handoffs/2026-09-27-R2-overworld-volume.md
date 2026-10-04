# R2 / H3 主世界步进体积雾 —— 交接记录

- 状态：代码完成（生产 / 合成 / 旧雾拆分 / 设置 / 文档全部落地；缺游戏画面与帧时验证，见第 7 节）
- 认领 / 完成：ZCode 会话，2026-09-27
- 对应父项：H3 主世界体积雾；提示词见 [next-agent-task-prompts](../2026-09-27-next-agent-task-prompts.md) R2 节
- 上游依赖：S2 积分模块 `Astra/shaders/lib/volume_integral.glsl`（`astra_volume_identity / segment / compose / apply`），交接 [S2](2026-09-27-S2-volume-integral.md)；接口未改动，只做消费

## 1. 每段介质归属（权威表）

| 介质段 | 开启 VOLUMETRIC_FOG 时归属 | 关闭时归属（现状不变） |
|---|---|---|
| 主世界空气（相机 → 不透明地形 / 透明层 / 水面） | 新体积雾：半分辨率步进 → colortex23 S/T → deferred 保边合成 `scene*T+S`（`program/deferred.fsh` 体积分支） | `fog_v2` 大气项 + morningFog + 天空收敛 + BIOME_TINT + AIR_PERSPECTIVE + rainy_air + 显示阶段 GODRAYS |
| 洞穴 / 低天光空气 | 体积雾的天空入射项下限 `MIN_AMBIENT_COLOR`（`astra_volume_incident`）；`CAVE_FOG` 色板与 `SKY_FOG_STRENGTH` 收敛被替代，交接为「开启体积雾时这两键对主世界空气不再生效」 | `fog_v2` 的 caveFogTransition 色板 |
| blindness（0<blindness） | 旧 `fog_v2` blindness 分支全权（体积早退 identity，两处互斥） | 同左 |
| 熔岩（isEyeInWater==2）/ 细雪（3） | 旧 `fog_v2` / powder-snow 臂（`astra_fog` 开头），体积 identity | 同左 |
| 水下相机腿（isEyeInWater==1） | 专用链：composite3 `solas_water_composite` + `water_medium`；体积臂要求 `isEyeInWater==0`，不参与 | 同左 |
| 水接口腿（相机 → 水面，air 侧） | `program/water.glsl:373 astra_apply_medium` → `astra_fog` 体积臂 → `astra_volume_prefix_medium`（共享密度模型重积分，非背景透射率猜测） | 旧 `astra_fog` |
| 水体内部（水面 → 河床） | `water.glsl water_medium / water_surface_medium`（colortex4 背景 + 自身吸收），colortex4 语义保持「未施加观察介质」 | 同左 |
| 透明层（玻璃 / 冰 / 粒子）前缀空气 | `lit.fsh` 既有 `astra_apply_medium` 调用 → 体积臂 → 前缀接口；材质内部无参与介质 | 旧 `astra_fog` |
| 平面云体（y≈192 云层） | 云介质仍归 B1 屏幕云 / planar 云链（colortex12、`astra_planar_cloud`）；体积只在光照侧消费云影 `astra_cloud_transmission`（colortex14 缓存或原场查询，B2），不把云当作步进介质、不在云体内步进 | 同左 |
| 下界 / 末地 | 不定义 `ASTRA_VOLUME_FOG`；`world-1/`、`world1/` 专用阶段，root 调度分支被维度宏挡住 | 不变 |

## 2. 阶段调度（AO 开 / 关两套）

`program/deferred.fsh`（场景合成）在两种 AO 配置下都执行，只是槽位不同；体积生产插在「不透明几何之后、透明几何之前」的空档：

| 配置 | deferred | deferred1 | deferred2 |
|---|---|---|---|
| 体积关 + AO 关 | 场景合成（program/deferred.fsh，现状） | 停用 | 停用 |
| 体积开 + AO 关 | **体积生产**（root deferred.fsh 薄入口新分支 → `program/volume_main.fsh` → colortex23） | **场景合成**（新 root `deferred1.fsh` → `program/volume_slot.fsh` → 非 SSAO 分支 → `program/deferred.fsh`） | 停用 |
| 体积关 + AO 开 | ssao（colortex21，现状） | 停用 | 场景合成（现状） |
| 体积开 + AO 开 | ssao（colortex21） | **体积生产**（`program/volume_slot.fsh` SSAO 分支 → `program/volume_main.fsh`） | 场景合成（program/deferred.fsh，读 colortex21 + colortex23） |

- properties 侧：`program.deferred1.enabled` 仅由 `#ifdef VOLUMETRIC_FOG` 控制；`program.world-1/deferred1.enabled=false`（下界不得继承 root deferred1）；`world1/deferred1` 是末地自有文件（end_sky_buffer），不动。
- 场景合成对 colortex0 / colortex4 / colortex16（TAA 遮罩）的全部写入不变，只是 AO 关 + 体积开时从 deferred 槽挪到 deferred1 槽；该槽位仍在透明几何之前，water / lit 透明分支（经 `scene.glsl`）可以消费同帧体积接口。
- 两个槽位里生产都在合成之前；colortex23 生产→消费跨一个 pass，flip 语义与现有 composite 链一致。

## 3. 新增资源登记

| 项 | 值 |
|---|---|
| 索引 | colortex23（23–31 为未登记候选索引，本任务登记 23；未复用 colortex12/14 云数据与 colortex15–22） |
| 格式 | RGBA16F（`const int colortex23Format = RGBA16F;`，program/volume_main.fsh） |
| 尺寸 | `size.buffer.colortex23=0.5 0.5`（开）；`1 1`（关，options 关闭时缩为 1×1） |
| 内容 | rgb = 积分散射 S（HDR 辐亮度），a = 透射比 T∈[0,1]；空段 = (0,0,0,1) |
| 清屏 | `colortex23ClearColor = vec4(0.0, 0.0, 0.0, 1.0)`（恒等段；生产 pass 全量写覆盖） |
| 生产者 | `program/volume_main.fsh` main（deferred 或 deferred1 槽） |
| 消费者 | `program/deferred.fsh` main → `astra_volume_resolve`（场景合成槽） |
| 生命周期 | 单帧；跨 pass 生产→消费，无历史 |
| 关闭行为 | pass 停用、缓冲 1×1、deferred 内采样代码被 `#ifdef ASTRA_VOLUME_FOG` 预处理掉，无读写 |

## 4. 旧雾协调（逐处）

1. `program/scene.glsl astra_fog` 主世界空气臂：体积开时在 powder-snow 检查之后提前返回 `vec4(S, 1-T)`（前缀接口），`fog_v2` 大气项、morningFog、`SKY_FOG_STRENGTH` 天空加项、`AIR_PERSPECTIVE`、`BIOME_TINT`、horizonConvergence 全部跳过（代码保留在 `#else` 侧，关体积时原样运行）。blindness / 熔岩 / 细雪 / 水下分支位置在体积臂之前或其条件之外，不被替代。
2. `program/deferred.fsh rainy_air`：体积开时不再加（`#if !defined ASTRA_VOLUME_FOG` 门）；雨对空气的加浓改由体积密度天气乘子承担。函数本体保留（关体积时使用）。
3. `global/post/godrays.glsl godrays_density`：体积开时返回 0.0（该空气段的太阳散射已由体积步进的阴影 + 云影 + HG 相位承担）。display 阶段加法（`program/display.fsh`）因此加零；`program/scattering.fsh` 仍会写 colortex1（少量浪费，文件不在本任务白名单，未改）。菜单说明注明两者同开时 GODRAYS 被体积替代。
4. 边界雾 `BORDER_FOG`：体积开时以「终端透射再乘 (1-borderFog)」折进合成（deferred 体积分支），不再走 `fog_v2` 内的 borderFog 项。
5. 水下 / 熔岩 / 细雪 / blindness：见第 1 节，未动。

## 5. 已改文件清单（本任务全部改动）

新增：
- `Astra/shaders/global/atmosphere/volume_fog.glsl` — 密度 / 相位 / 光源项 / 步进 / 前缀接口 / 保边 resolve
- `Astra/shaders/program/volume_main.fsh` — 生产阶段（colortex23，RENDERTARGETS 23）
- `Astra/shaders/program/volume_slot.fsh` — deferred1 槽位调度（薄入口）
- `Astra/shaders/deferred1.fsh` / `Astra/shaders/deferred1.vsh` — root deferred1 薄入口（主世界）
- `docs/handoffs/2026-09-27-R2-overworld-volume.md` — 本文档

修改：
- `Astra/shaders/deferred.fsh`（root 薄入口）— 新增 `#elif defined ASTRA_VOLUME_FOG → volume_main` 分支
- `Astra/shaders/program/deferred.fsh` — colortex23 采样 + 保边 resolve + `astra_volume_apply` 合成 + BORDER_FOG 折入 + rainy_air 关断
- `Astra/shaders/program/scene.glsl` — include 体积模块；`astra_fog` 新增体积臂（前缀接口）
- `Astra/shaders/global/post/godrays.glsl` — `godrays_density` 在体积开启时置零（替代，不再叠加）
- `Astra/shaders/lib/settings.glsl` — `VOLUMETRIC_FOG` / `VOLUME_FOG_DENSITY` 选项、`ASTRA_VOLUME_FOG` 宏、colortex23 清屏色
- `Astra/shaders/shaders.properties` — size.buffer.colortex23 条件尺寸、deferred1 门（含 `world-1` 显式停用）、screen.FOG、sliders、四档 profile 各加 `!VOLUMETRIC_FOG VOLUME_FOG_DENSITY=50` 两个 token
- `Astra/shaders/lang/en_US.lang` / `zh_CN.lang` — 2 个选项的标题与说明
- `Astra/README.md` — 功能清单、边界说明、待办行同步
- `Astra/THIRD-PARTY.md` 无改动：本任务未引入任何第三方表达（HG 相位为教科书式自有实现）

## 5.1 实际调用关系（生产者 → 消费者，file:symbol）

```
VOLUMETRIC_FOG（用户开关，默认关，独立于 TAA 与 SHADOWS）
  └ settings.glsl:ASTRA_VOLUME_FOG（主世界维度宏）

每帧（主世界，两种 AO 调度）：
  root deferred.fsh ─ #ifdef ASTRA_SSAO → program/ssao.fsh (colortex21，不变)
                      └ #elif ASTRA_VOLUME_FOG → program/volume_main.fsh   [体积开 + AO 关]
  root deferred1.fsh ─ program/volume_slot.fsh
                       ├ SSAO && VOLUME → program/volume_main.fsh          [体积开 + AO 开]
                       └ else           → program/deferred.fsh (场景合成)  [体积开 + AO 关]
  root deferred2.fsh ─ program/deferred.fsh                                  [体积开 + AO 开]
  world-1/deferred1 停用（program.world-1/deferred1.enabled=false）；world1/deferred1 为末地自有文件未动。

program/volume_main.fsh:main
  └ global/atmosphere/volume_fog.glsl:astra_volume_march(ray, dist, shadowMap=true, 24 步)
      ├ astra_volume_extinction(worldY)   — 高度密度（VOLUME_FOG_DENSITY × 天气乘子 × 高度衰减）
      ├ astra_volume_light(p, ray, L, …)  — astra_direct_light × astra_volume_phase(HG) ×
      │                                     astra_cloud_transmission(colortex14 缓存/原场) ×
      │                                     shadow_coverage + shadow_opaque_visibility（仅生产档）
      │                                     + astra_volume_incident（MIN_AMBIENT_COLOR 下限）
      ├ lib/bayer.glsl:bayer8             — 每像素静态抖动（稳定，不依赖 TAA）
      └ lib/volume_integral.glsl:astra_volume_compose/segment — 近→远段积分，192 格上限，
        超界走解析残余段（同密度模型、无阴影图明细）
  → colortex23（RGBA16F 0.5×0.5，rgb=S, a=T，全量写覆盖）

program/deferred.fsh:main（场景合成槽，deferred 或 deferred2）
  ├ astra_volume_resolve(colortex23, uv, depth, playerPos) — 深度感知 4-tap 保边上采样；
  │   tap 深度与本像素不一致 / 天空 tap 被剔除；全被剔除时回退 astra_volume_prefix_medium
  ├ BORDER_FOG 折入 T（乘 (1-borderFog)）
  └ astra_volume_apply(source, volume) = scene*T + S   ← 验收 #2 的消费点
      （colortex4 仍写未施加观察介质的 source；TAA reactive 写入不变）

透明介质前缀（明确接口，非背景透射率猜测）：
  program/scene.glsl:astra_fog → #ifdef ASTRA_VOLUME_FOG → astra_volume_prefix_medium(playerPos)
    （volume_fog.glsl，同一密度模型重积分 8 步，云影有、阴影图无——首版近似）
  消费者：program/water.glsl:astra_water(水面相机腿 :373)、water_sample_path 的空气传输雾(:126)、
  program/lit.fsh 透明分支 astra_apply_medium→astra_fog（lit 未改动，函数在 scene.glsl 内换臂）

旧雾拆分点：
  program/deferred.fsh  rainy_air 加法被 `#if … && !defined ASTRA_VOLUME_FOG` 关断
  global/post/godrays.glsl:godrays_density — ASTRA_VOLUME_FOG 时 return 0.0（display 阶段加零）
  program/scene.glsl:astra_fog  体积臂提前 return，fog_v2 大气项/morningFog/sky add/
                                AIR_PERSPECTIVE/BIOME_TINT 不再执行（代码保留给关闭态）
```

## 6. 已完成

- 交接记录（本文档）先行：介质归属表、双调度表、colortex23 登记、旧雾逐处处理。
- 生产：`program/volume_main.fsh` + `global/atmosphere/volume_fog.glsl`（真实世界射线步进：24 步、192 格上限、bayer 抖动、阴影图 + 云影 + HG 相位 + 天空入射 + 高度密度）。
- 合成：`program/deferred.fsh` 保边上采样 + `scene*T+S`（`astra_volume_apply`）；回退前缀接口。
- 调度：root `deferred.fsh` 新分支、新 root `deferred1.fsh/.vsh`、`program/volume_slot.fsh`；AO 开 / 关两套均在编译与链接层面验证。
- 旧雾协调：fog_v2 大气项 / AIR_PERSPECTIVE / BIOME_TINT / morningFog 被替代；rainy_air 关断；GODRAYS 在模块内置零；BORDER_FOG 折入 T；blindness / 熔岩 / 细雪 / 水下 / 下界 / 末地路径未动。
- 接口：`astra_volume_prefix_medium` 供水接口腿、透明层前缀与 SSR 传输雾使用（共享密度模型，非背景透射率推断）。
- 设置：`VOLUMETRIC_FOG`（默认关）+ `VOLUME_FOG_DENSITY` 滑块；各向异性为模块内有界常量 `ASTRA_VOLUME_PHASE_G 0.60`（选项注册表 80 上限，见备注）。中英 lang、README、四档 profile、screen.FOG、sliders 同步。
- 关闭路径：选项关 → `ASTRA_VOLUME_FOG` 不定义，模块编译为空、deferred1 停用、colortex23 缩 1×1 无消费者，全部旧雾原样运行。

## 7. 未完成 / 风险 / 下一处接续位置

- **无游戏画面、无帧时数据**（qa 无主世界离线出图能力，与 README 声明一致）。观感、密度默认值、192 格上限、24 步预算、HG g=0.60 均为源码推导的初始值，需游戏内 A/B 再标定。
- 首版近似（明确留待，不是完成项）：
  1. 前缀接口（水接口腿 / 透明层）不带阴影图，与相邻地形空气在明暗上可有轻微不一致；接续位置 `astra_volume_prefix_medium`（提高步数或传入阴影图开关）。
  2. 透明层（玻璃 / 冰）与地形分别对同一空气列取前缀，延续旧 fog 的既有双重计数近似；根治需改 lit 透明分支的介质语义（lit.* 禁改，超出本任务）。
  3. 手持物半分辨率 march 端点未做 MC_HAND_DEPTH 修正（手部像素在合成端经深度对比自动回退前缀，误差受限）。
  4. colortex1 在体积开启时仍被 scattering 写零密度（scattering.fsh 不在白名单）；微小浪费，无正确性影响。
- 下一处接续：R5（水时域）消费本文档的前缀接口约定；R6（云历史）不必感知本缓冲。若引擎/画面验证发现 Iris 1.11.2 拒绝 colortex23，回退方案与候选索引（24–31）见提示词共同约定。

## 8. 证据

关键源码定位（验收 #2 / #3 的 file:line）：
- 真实步进：`program/volume_main.fsh:28`（`astra_volume_march(..., true, ASTRA_VOLUME_STEPS)`）→ `global/atmosphere/volume_fog.glsl:106`（24 步 / 192 格上限 / bayer 抖动）
- S/T 保存：`program/volume_main.fsh:19`（`/* RENDERTARGETS: 23 */`，colortex23 = rgb S, a T）
- scene*T+S 消费：`program/deferred.fsh:212`（`astra_volume_apply(source, volume)`），采样入口 `program/deferred.fsh:204`（`astra_volume_resolve`，保边 4-tap + 前缀回退 `volume_fog.glsl:147/175`）
- 旧雾拆分：`program/deferred.fsh:232`（rainy_air 关断）、`global/post/godrays.glsl:54`（godrays_density 置零）、`program/scene.glsl:116`（astra_fog 体积臂提前返回，前缀接口 `astra_volume_prefix_medium`）
- 调度：root `Astra/shaders/deferred.fsh:7-13`（三路分支）、`program/volume_slot.fsh:6-9`（SSAO && VOLUME → 生产，否则场景合成）、`shaders.properties:111-118`（colortex23 尺寸 + deferred1 门 + world-1 停用）

- `python qa/tools/check_pack.py`（仓库根目录）：开工前基线 `17 checks: 3 FAIL`（#4 include 图 shell 直含 settings、#11 SC-28 DIRECTIONAL_SKYLIGHT/SCREENSPACE_AO、#15 fxaa 许可文本）；交付前 `17 checks: 3 FAIL, 0 WARN, 14 PASS`，**FAIL 数不增**，且 #4 中 `pending wiring: lib/volume_integral.glsl` 已消（模块已接线）。
- 离线驱动编译（`qa/tools/compile_glsl.py`，真实 OpenGL 4.3 前端，RTX 4050，四档 profile 全条目）：
  - `--profiles BALANCED --set VOLUMETRIC_FOG=`（体积开）→ `RESULT linked=420 failed=0 compute=36`
  - 四档原生默认（体积关）→ `RESULT linked=420 failed=0 compute=36`
  - `--profiles ULTRA --set VOLUMETRIC_FOG= --set SCREENSPACE_AO= --match deferred`（AO 开 + 体积开的调度链）→ `RESULT linked=6 failed=0`
  - `--set SCREENSPACE_AO=`（仅 AO 开）→ `RESULT linked=6 failed=0`
  - 过程中抓到并修复的真实编译错：`astra_volume_apply` 在 nether/end 编译单元越出 `#ifdef`（`2(282): error C1503`），已改为守卫内 if/else 后全绿。
- 无画面 / 帧时证据，未宣称任何观感或性能收益。
