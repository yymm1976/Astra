# 全量审查与参考调研汇总（2026-09-26）

本文是 2026-09-26 会话的一次性汇总，包含：全量代码审查结论与处置、Astra 各模块完成度评估、IterationT 3.2 分模块调研明细、水下链路接线审计、末地黑洞（Kerr 模块）深读与改进建议、文档清理记录。文中行号均以 2026-09-26 工作区源码为准。

取代并吸收 `2026-09-11-iterationt-3.2-source-review.md` 与 `2026-09-11-iterationt-optimization-review.md`（两份已随本轮文档清理移除，git 历史可查）。

审查基线：`68af9a1`（分支 `codex/fix-render-handoff`），55 个已跟踪改动 + 7 个未跟踪新文件，改动集与审查者独立取证逐文件对平。

---

## 一、全量代码审查（独立 code-reviewer，只读）

**判定：需修后复查（0 Critical / 2 Important / 3 Minor）**

### Important 1 —— QA 二进制证据早于它声称支撑的源码改动
- 位置：`qa/water-path-followup/results.json` 及同目录 14 对 `.f32`/`.png`
- 证据时间线：证据生成于 2026-09-24 01:13；而 `program/scene.glsl`（09-26 15:29）、`global/lighting/diffuse.glsl`（09-26 15:33）、`global/lighting/shadowmap.glsl`（09-25 13:46）、`program/water.glsl`（09-24 01:58，比证据晚 45 分钟）均在其后改动。HEAD `68af9a1` 提交于 09-25 22:55。
- 探针 include 树覆盖这些文件（`water_path_probe.py:16` → `program/scene.glsl` → `shadowmap.glsl`、`sky_gradient.glsl`；`water.glsl` 直接 include）。`b49e3d2`（09-25）整体重写了探针所走路径的阴影采样结构。
- 正向核验：按 `water_path_probe.py:228-267` 公式从当前 `.f32` 重算 `results.json` = **0 差异**（内部自洽）；被改动的 14 帧与 results.json 变更键一一对应。
- **处置**：用 `python qa/tools/water_path_probe.py` 对当前工作区重跑生成新证据（GPU/LWJGL 可用时）；失败则显式标注为 2026-09-24 历史快照，不得当作当前源码的验证材料。

### Important 2 —— 新增格式 const 与 .specs 明文禁令冲突，规格未随轮次修订
- 位置：`global/post/exposure.glsl:31`（`colortex10Format = RGBA32F`）、`program/shadow.fsh:34`（`shadowcolor0Format = RGBA16F`）
- `.specs/astra-shader/design.md:107`（SC-27「格式 const 一律注释」）、`:111`（SC-33「不增加活跃格式 const」）、`:534`（SC-41，2026-09-21）仍维持禁令；而仓库实际按 `qa/tools/check_pack.py:830-834` 记载的 SC-27 修订版（2026-09-10：全面禁令系误诊）运行，"设计文本未更新"一项已由 2026-09-20 的历史审查报告登记（该报告已于 2026-09-26 清理，git 历史可查），`.specs` 始终无修订条目。
- 机制本身与既有 `colortex0/2/4/7/8/9` 声明同形、带 `#ifndef` 守卫，风险在规格文本而非加载。
- **处置**：在 `.specs/astra-shader/design.md` 补 SC-27 修订决议（改述为：名称合法 + 全大写引擎 token + 每缓冲唯一声明 + `#ifndef` 守卫），并在 `escalations.md` 登记追认，同步 SC-41 括注。

### Minor（3 条）
1. **check_pack 格式契约不覆盖 `shadowcolor0Format`**：`qa/tools/check_pack.py:839` 正则只匹配 `colortex\d+Format|depthtex\d+Format`。→ 扩为 `(?:colortex|shadowcolor)\d+Format`。
2. **文档笔误**：`docs/2026-09-26-project-review-followup.md:15` 写 `lang/zh_cn.lang`，实际为 `lang/zh_CN.lang`。→ 改正。
3. **未点亮的非完整发光方块在下界体素体积中变成实心遮挡**：状态门控后 `redstone_torch:lit=false`、`campfire:lit=false`、`soul_campfire:lit=false` 不再落入 10021–10027 → `mc_Entity=0` → `shadow.vsh:64-66` 走 `kind=0u; solid=true`，与其注释「Water, plants and torches are not full cubes」相反。仅影响下界 `NETHER_VOXEL_LIGHT`、一格级。→ 本轮在 `block.properties` 注释写明现状与取舍；若后续要行为修复需与 `lit.vsh:31` 材质映射一并设计（并入 10003 会给未点亮火把 material 3，需先确认该材质无摆动/SSS 副作用）。

### 审查通过项（摘要）
- 09-26 两份文档的 21 条"已实施修复"逐条对 diff **全部有对应实现**，无虚报；量化声明全部为真（两语言 186 键集相等、BALANCED 与源码默认 0 不等、四档 profile 各 73 token、自定义纹理 10/10 存在）。
- 选项体系无不一致：check_pack #1/#2/#3/#7/#13 全 PASS；`NETHER_FOG_DENSITY` 档位含 0 且两条雾路同步归零；item.properties ↔ block.properties ↔ lang 三者互相对得上。
- 三个 qa/tools 脚本无回归：`check_pack.py` exit 0（16 PASS / 1 WARN，WARN 为既有 voxy 待接线登记）；`option_matrix.py` exit 0；`gen_rain_ripple` 导入无副作用。
- `light_shafts.glsl` 换用 `shadow_coverage` 的符号闭包经静态展开验证齐备，无缺符号回归。
- `.zcodeignore` 与 `.gitignore` 分工恰当，仓库无产物污染。

---

## 二、修复处置记录（本会话，已全部执行）

| Finding | 处置 | 证据 |
|---|---|---|
| Important 1 | **已修复**：探针在 D 盘 MC 根（含 LWJGL 3.3.3）重跑成功（exit 0），`results.json` + 22 组 `.f32/.png` 全部刷新为 2026-09-26 19:06（晚于全部源码改动），28 个顶层键与重跑前一致。执行说明：修复 worker 因默认 MC root 缺 LWJGL 3.3.3 而 BLOCKED，改由统帅以 `ASTRA_MC_ROOT=D:/zhenhebao/.minecraft` 代跑（未派工原因：环境变量级修复，单命令） | results.json mtime；探针 exit 0 |
| Important 2 | **已修复**：design.md 补 SC-27 修订条目（2026-09-26 追认）+ SC-41 括注同步；escalations.md 新增追认条目，列 exposure.glsl:31 与 shadow.fsh:34 两个实例 | design.md:109,536；escalations.md:111-121 |
| Minor 1 | **已修复**：check_pack 格式声明正则扩为 `(?:colortex\|shadowcolor\|depthtex)\d+Format`（worker 取超集以保留 depthtex 覆盖，判定正确） | check_pack.py:839 |
| Minor 2 | **已修复**：`zh_cn.lang` → `zh_CN.lang` | followup 文档 :15 |
| Minor 3 | **部分处理**：block.properties 加 2 行注释写明现状与取舍（行为保持不变；行为修复需与 lit.vsh 材质映射一并设计） | block.properties:83-84 |

补充清理：`docs/2026-09-24-reference-analysis.md`（09-24 轮次历史报告，未入索引、无引用）按同一准则补删，清理总数 49 → 50。

---

## 三、Astra 各模块完成度评估（2026-09-26 源码抽查）

| 模块 | 完成度 | 现状一句话 | 关键证据 |
|---|---|---|---|
| 主世界地形与植被 | 高 | lit 统一入口、材质分类、摆动与 SSS 全接线；Voxy 远景仍是空壳 | `block.properties:6-8`、`global/lighting/wind.glsl:135`、`program/lit.vsh:25-42`、`lib/settings.glsl:219-226` |
| 主世界光照与阴影 | 高 | 阴影/彩影/静态回退/方块光压制/云影/自动曝光全部实现，等待实机 | `global/lighting/shadowmap.glsl`、`program/scene.glsl:226`、`shaders.properties:171-174` |
| 水体（水面/水下） | 中高 | 波形/SSR/折射/吸收/焦散/光束/颗粒全套在位；实现密度最高但接线有 2 死端 + 2 偏差（见第五节） | `global/water/*.glsl` |
| 下界 | 中高 | 光照移植+体素彩光+体积雾落地；雾高密度项、熔岩专属材质（`lit.vsh:40` 把 10021..10030 全映射 10u）、五群系硬编码调色板仍缺 | `global/dimension/nether.glsl:77,147-198`、`nether_volume.glsl:25-60` |
| 末地（含黑洞/环系） | 中高 | Kerr 预计算盘面+环系+星野+照明缓存落地；光柱未做、倒角与环食仍是近似（详见第六节） | `global/dimension/end_blackhole.glsl:23-116`、`end_kerr.glsl` |
| 天空与云 | 中高 | 渐变天空/星野/平面云已换源重写；云影实现但三档全关、云自阴影未接 | `global/atmosphere/*.glsl`、`lib/settings.glsl:85-95` |
| 后期链 | 高 | 曝光/两段泛光/4 算子 tonemap/分级/抖动全链在位；两处标 UNVERIFIED | `program/final.fsh`、`lib/tonemap.glsl`、`global/post/exposure.glsl:45` |
| 选项体系与 UI | 高 | 73 选项 × 7 分类 × 四档 profile × 双语齐全 | `lib/settings.glsl`、`lang/zh_cn.lang`（146 行 option 条目） |
| 性能与档位 | 中 | 四档+NO_SHADOWS+低配优化落地；**全仓零帧率数据**（`qa/benchmarks.md:3`）、Voxy 未实现、无 TAA 降采样欠账 | `qa/open-premises.md:10` |

历史高危缺陷 F-1/F-2/F-6 已确认在当前源码修复（`nether.glsl:11` 真 `#ifdef`、`shaders.properties:104` 指向 `world1/deferred`、各档含 `DEBUG_VERTEX_AO`/`END_STONE_GLOW`/`NETHERRACK_GLOW`）。

### 主世界优化
- 已实现：四档含 NO_SHADOWS；低档关闭 9 阶段体素光；体素光 8 次点采样改 1 次硬件三线性；水下跳过空气 bloom 采集；云细节采样移到存在性判断后。
- 缺口：零帧率数据（P-4）；Voxy `TODO(C5)`（`voxy_opaque.glsl:4`、`program/lit_voxy.fsh:4`）；无 TAA 却有 5 张降采样缓冲的结构性欠账（文档登记，需实机核）；deferred 全分辨率双输出与 `ASTRA_SCENE_COPY` 恒开（`lib/settings.glsl:376`）；跨驱动编译未验（P-3）。

### 水下氛围
- 已实现：吸收/消光/水色、焦散（09-26 起 shadowcolor0 RGBA16F 保亮斑增益）、4/7/10 段光束、颗粒三层壳（默认关）、水体状态跨帧链。
- 缺口：**视觉裁决历史全为退回**（`visual-verdicts.md:68,91`，2026-09-08 旧记录，水链此后多轮重写）；水下整体亮度目标未达成且离线无绝对亮度判据（`qa/regression-checklist.md:74`）；焦散仍是小斜率聚焦代理（`2026-09-24-handoff-resolution.md:7`）；**接线审计发现 2 死端 + 2 偏差（第五节）**。

### 下界氛围
- 已实现：Complementary 光照移植（`nether.glsl:147-166`）、岩壁热辉（`:185-198`）、体素彩光 9 compute 阶段（`shaders.properties:380-389`）、体积雾三层（`nether_volume.glsl:25,39,60`）。
- 缺口：N-001 雾密度只随距离（`nether.glsl:77`，与 `design.md:319` 不符）；P-001 熔岩材质映射 bug（`lit.vsh:40`）；P-003 五群系硬编码调色板未移植；`netherStorm` 体积与彩色光体积未做；design 4.5「高度/深度锚定」在换源时被删、待拍板。

### 末地黑洞
- 已实现：Kerr 预计算光路（`end_blackhole.glsl:23-63`）、环系/73 天体（`end_geometry.glsl:1-40`）、星野双族+黑体色温、盘面等离子体与喷流（`end_plasma.glsl`）、照明缓存 32 样本 + `program/end_illumination.fsh` + colortex8、末地石微光。
- 缺口：末地光柱未做（全包 grep 零命中，`handoffs/end.md:91-96` 登记）；真外轮廓倒角未实现；环食是 `color *= 1-0.18*end_eclipse()` 的整屏乘性变暗（`end_blackhole.glsl:116`）非几何遮挡；`END_VOID_MIN_STRENGTH=0.55` 待拍板（`handoffs/end.md:75-82`）；全部结论停在离线层面。

---

## 四、IterationT 3.2 分模块调研明细

参考包：`_analysis/latest-2026-09-10/iterationT-3.2.0/shaders/`。标注 `[旧]` = 09-11 旧调研已记录，`[新]` = 本次新发现。

### 4.1 主世界（性能与画质）

**管线对比**：ITT 主世界约 25 个 pass（deferred 水面波法线 → GI 时域/空间 + GTAO → 天空+体积云+反射图一趟三用 → 云影模糊×2 → 缓冲回收 → 主光照 → SSR → 反射 à-trous×2 → 透明/折射/雾/DOF → TAA → 运动模糊 → bloom 五段 → tonemap+CAS → FSR）。成本纪律 = program 级 gating（`shaders.properties:61-119`）+ 五档 profile 显式开关（`:317-321`）+ colortex 图集复用。Astra 走"显式小缓冲（11 张 colortex + size.buffer）+ CPU 预计算 + 空间去噪"路线，bloom 已更省（两段 vs ITT 五段）。

技法清单（按价值排序）：

1. `[新]` 屏幕空间图集复用 | `deferred3.fsh:215-264` | 同一张 colortex 角区存天空反射图/云影/波法线/GI | Astra 用 size.buffer 多缓冲；借鉴取向：低频信号塞小缓冲，避免新增全屏缓冲
2. `[新]` VPS 变半影（接触硬化） | `Sunlight_Shadow.glsl:99-117` | 3×3 邻域深度差方差 → 半影宽度自适应，叶片/草最小宽度 | Astra 固定半径（`shadowmap.glsl:54` + `diffuse.glsl:264-269`）；用已采的 gather 深度顺带估方差，几乎免费
3. `[新]` 阴影 mip 化方差探测 | `Sunlight_Shadow.glsl:100-104` | 注意：该实现的 `shadowHardwareFiltering1` 整块被注释（`composite.fsh:11-56`），Iris 默认下 mip 捷径无效；Astra 若要借必须显式打开 mipmap 声明
4. `[新]` 阴影/SSS 采样分层门控 | `composite.fsh:290,307`、`Sunlight_Shadow.glsl:92` | 太阳项为 0 跳过 VPS；全黑跳过 SSS/焦散/高光；UV 越界直接 shadow=1 | Astra 无条件 4-lobe（`diffuse.glsl:260-270`）；天空/洞穴像素省 16 次采样
5. `[新]` 体积云四道成本阀 | `NUBIS.glsl:129-171` | 视角度 20→12 步、QUALITY 乘步数、密度≈0 continue、透过率<1e-4 break | Astra 平面云 6..64 步（`clouds_planar.glsl:238-270`），可补"视角度阀 + 粗探/细探"
6. `[新]` 云细节层只取前几步 | `NUBIS.glsl:45-83` | 顺光探测 ×1.5 步长几何增长，`i<3` 才采 3D 细节噪声 | Astra 每步固定 2 个 2D 噪声；细节层只近处取
7. `[新]` 云影图低频化 | `deferred3.fsh:256-264` + deferred4/5 + `CloudShadow.glsl:28-53` | 2 次密度探针写小图 + 两趟高斯 + bicubic | Astra 云影未启用（`settings.glsl:95` 注释、`scene.glsl:226` 钩子）；要更柔需"低频图 + 廉价模糊"，但用小缓冲别学全屏模糊
8. `[新]` 平面云单交点模型 | `PlanarClouds.glsl:106-157` | 1 次球面求交 + 1 密度 + 4 步照明探测，不沿视线步进 | 低档位把 64 步压到 1 步的样板
9. `[新]` 天空盒反射图一趟三用 | `deferred3.fsh:75-95,215-254` | 立方体展开天空反射图 + 云透射率 alpha + 太阳可见度 | Astra 反射靠 SSR + 解析天光；可给反射一个低频"天空+云"缓存
10. `[新]` 阴影 pass 顺带产 RSM | `Shadow_FS.glsl:79-91` | shadowcolor1=法线+skylight，零额外几何成本 | Astra `shadow.fsh:37` 只写 RT0；将来做云影/雾遮挡/低成本 GI 的储备
11. `[新]` 反射 à-trous 两趟去噪 | `ReflectionFilter.glsl:3-63` | 9-tap 边缘保持小波 | 仅当 Astra 把 SSR 扩到陆地/半分辨率时才需要
12. `[新]` 每 pass 常量上移 | `CompositeVS.glsl:72-157` | 顶点算太阳辐照度/云可见度 | Astra 已用 CPU custom uniforms（`shaders.properties:191-343`）更彻底；只需防退回 per-pixel（如 `fog.glsl:207` AIR_PERSPECTIVE 分支）
13. `[新]` 纹理采样 tap 预算跟档位 | `Terrain_FS.glsl:57-100,206-215` | 自算椭圆足迹各向异性采样，Low=0 / Extreme=16 | 作"每像素纹理采样预算"先例参考，别抄 16-tap 自算版

**不建议照搬**：外挂 3D 大气数据（33 MiB、与 Astra CPU/解析大气路线冲突）；deferred4/5 两趟全屏模糊只服务 11% 屏面积云影图；大面积屏内图集 + 缓冲回收拷贝（Astra 的显式分缓冲更省带宽、更可审计）。

### 4.2 水下

Astra 在水下整体领先（Beer-Lambert 吸收 `absorption.glsl:61-63`、每帧介质状态网格 `medium_state.glsl`、折射 UV 深度校验 `water.glsl:145-155`、颗粒三层壳 `particles.glsl:120`——ITT 无粒子）。值得拿的三条小项：

1. `[旧]` 焦散=几何聚焦量 | `Sunlight_Shadow.glsl:257-290` | Astra 已有解析 Jacobian（`caustics.glsl:102`）；**新细节：`:289` 用 `mix(c*0.16+0.2,1.0,0.3-0.3*isEyeInWater)` 让水下拿满强度、空气侧 0.7 的分维门控**，Astra 无此项
2. `[新]` 一行版吸收（低配降级） | `composite1.fsh:78-87` | `pow(vec3(0.1,0.6,1.0)*0.99, dist*ρ)` 单行逐通道衰减 | 可作 PERFORMANCE 档降级分支，不必替换现有 Beer-Lambert
3. `[新]` 1/d 距离淡化 | `composite.fsh:137,198-207,303` | 直射阳光乘 `tint/max(3,dist*0.1*ρ)` 距离反比 | 廉价深度色调，代替一次 exp

已覆盖项（不搬）：折射后太阳方向前向散射（Astra `solas_water.glsl:96-100` 已有 glare 项）、半浸没处理（Astra 介质网格更稳）、TIR alpha 传递（Astra 已有 totalReflection）、水下丢弃天空/日盘（`deferred.fsh:213-220` 已一致）、水下波法线取反（`caustics.glsl:24-35` 已覆盖）、玻璃染色吸收（Astra 在阴影侧实现更省 `shadowmap.glsl:126`）。

**不建议照搬**：一切时域方案（ITT 依赖 TAA，Astra 无 TAA 前提）；9-tap 焦散 + 波法线贴图缓冲（与 Astra 解析焦散 + shadow 编码水高打架）；PhysicsOceans 全物理波浪（需 GPU 位移网格 + CPU 同步）；水下天空图 tile（与 `astra_reflection_sky`/`solas_water_sky` 形成第二套天空模型）。

### 4.3 下界

Astra 领先项（勿回退）：熔岩方向热辉 `nether.glsl:162-198`、体素彩光 9 compute 阶段、16 步体积雾 raymarch `nether_volume.glsl:60-153`（ITT 下界无任何体积 pass）、逐维度曝光 `grading.glsl:114-118`（比 ITT 的 ×10 硬编码干净）。

可借鉴（按性价比）：

1. `[新]` **逐生物群系雾密度** | `NetherColor.glsl:19-26` | 每种群系自带密度系数（0.010/0.007/0.014/0.007/0.014）× NETHERFOG_DENSITY | Astra 只有逐群系颜色（`nether.glsl:54-62`），密度全局统一（`settings.glsl:171`）；一处改动得"群系呼吸感"
2. `[新]` **远景雾转 bloom（热霾辉光）** | `Final.glsl:113-132` | `bloomAmount=max(bloom*biomeOffset, min(fogFactor,0.92))`，远雾读作自发光霾 | Astra `final.fsh:60-74` 只有水下特例；近零成本
3. `[新]` 反射只加差分段雾 | `world-1/composite2.fsh:28-37`、`composite5.fsh:33-41` | `fogFactor=(1-exp2(-d·ρ))²`，反射路径只加增量 | 避免远处雾加两次；Astra `water.glsl:120-127` 用 mix 思路接近，可显式化
4. `[新]` **逐维度 const 覆盖** | `world-1/composite.fsh:11-46` | 下界 `shadowDistanceRenderMul=0.007`（无方向光，纯收益）；末地对照 `world1/composite.fsh` 用 1.0 | Astra `shaders.properties` 无逐维度覆盖机制，最值得抄的一条
5. `[新]` 自发光类别权重表 | `Blocklight.glsl:38-56` | glowstone/torch/fire/lava/soulFire/amethyst/endPortal 各自权重 ×|albedo| | 对照 `lib/surface_emission.glsl` 查漏（amethyst/redstoneTorch/oxidizedBulb 等）
6. `[新]` 下界 SSR 命中距离拉粗糙度 | `world-1/composite2.fsh:38-97` | VNDF 采样 + `hitDist=max(rDist*2,3*roughness)` 距离模糊 | Astra `raytrace.glsl` 目前按固定强度混合
7. `[新]` 自发光块自身压暗 | `Blocklight.glsl:17,28-73` | `lightmap=min(lightmap,1-0.13*lightSourceMask)` | Astra emissive 路径可对照

**不建议照搬**：下界专用 TAA（`TAA_Nether.glsl`，时域）；`Blocklight.glsl` 的 ×10/0.015 双口径曝光；热浪扭曲/灰烬粒子两边都是空白，可自研但注意无 TAA 下粒子会闪。

### 4.4 末地黑洞

IterationT **没有黑洞**，无可借鉴；改进路线见第六节。可借的只有通用工程手法（逐维度 const 覆盖、shadowcolor1 顺带产 RSM 的思路）。

---

## 五、水下链路接线审计（回答"是否有偏差 bug / 被阻断"）

**结论：存在正好是开发者担心的那类问题——2 个死端（算了没人读/选项无效）、2 个接线偏差、3 个疑点。**（默认档位：P=PERFORMANCE / N=NO_SHADOWS / B=BALANCED / U=ULTRA）

### 5.1 接线总表

| # | 效果 | 选项（各档默认） | 计算点 | 输出→消费链 | 判定 |
|---|---|---|---|---|---|
| 1 | 水下吸收/消光/水色 | `WATER_ABSORPTION=100`（四档同）、`WATER_CHARACTER=1` | `absorption.glsl:13-107` | `water_surface_medium`→`water.glsl:95-116`（水上界面腿）；`water_medium`→`scene.glsl:84-90`（仅 Nether/End 水下）、`water.glsl:230-231`（水下 SSR 腿）、`particles.glsl:138` | 通（但水下相机主色调不经它，见问题 2） |
| 2 | 水下焦散 | `WATER_CAUSTICS`：B/U 开、P/N 关 | caster `shadow.fsh:77-98`；空气侧像素端 `lit.fsh:320-358`；光束调制 `light_shafts.glsl:74-76` | `shadowcolor0=(height,tint)` → `shadowmap.glsl:120-127`(`caster.gba`) → `diffuse.glsl:322-347`（`isEyeInWater==1` 才取） | 通（水下唯一路径=阴影 caster；09-26 已保 >1 增益） |
| 3 | 水下体积光束 | `UNDERWATER_LIGHT_SHAFTS`：P/B/U 开、N 关；段数 4/4/7/10 | `scattering.fsh:79-89`→`light_shafts.glsl:29-90` | colortex1 → `water_composite.fsh:16-27`（×STRENGTH） → colortex0 → final | 通；`beam_limit` 峰值归一 `x/(1+peak)`，弱光束近似恒等，不会压没 |
| 4 | 水下颗粒 | `UNDERWATER_PARTICLES`：**四档全关** | `particles.glsl:120-147` | 唯一消费者 `final.fsh:91-101` | **默认不可见**（需手动开） |
| 5 | 介质状态网格 | 无选项，composite 恒开 | `water_state.fsh:9-52`（20×12 网格）→ colortex6 | colortex6 唯一读者是 `water_state.fsh:35` 自己 | **死端** |
| 6 | 水下光照混合 | 随 SHADOWS/SKYLIGHT | `diffuse.glsl:325-367`；`scene.glsl:73-77` astra_underwater_color | diffuse→lit→colortex0→final 通；**astra_underwater_color→只有 `fog.glsl:160-171`，不可达** | diffuse 通；`astra_underwater_color` **死端** |
| 7 | 水面下表面 | SSR/REFRACTION：B/U 开、P/N 关 | `water.glsl:134-167`、`lit.fsh:74-87` | lit→colortex0→deferred→composite3→final | 接线通，走向异常（问题 3/4） |
| 8 | 水下 bloom | 仅 B/U | capture `water_bloom.fsh:9-11`+`bloom_capture.glsl:5-42`；air 侧 `composite1.fsh:26-36` 水下写 0 | colortex7 → `final.fsh:61-73` | 接线完整；寻址语义可疑（问题 5，低置信） |
| 9 | 水下雾/blindness | `UNDERWATER_FOG_DENSITY=40`（四档同） | `solas_water.glsl:83-103` + `water_composite.fsh:16-27`（×1-blindness）；darkness `final.fsh:106-113` | colortex0→final | 通（blindness 由 composite3 兜底） |

无"ULTRA 才可见"的水下效果（唯一 ULTRA 限定是空气 GODRAYS）；N 档水下=无直射/无焦散/无光束/无 SSR。

### 5.2 问题清单（按严重度）

**P1-死端①：colortex5→water_state→colortex6 整链无屏幕消费者。** `medium_state.glsl:15` 的 `water_volume_state()` 全树唯一调用点是 `water_state.fsh:35`（回退路径自己）；colortex6 无其他 sampler 读者（全包 grep 0 命中）。`shaders.properties:79` 注释"Water state also supplies terrain lighting/caustics when shafts are disabled"不成立。复现：任何水下场景恒成立。整条跨帧介质状态机器在空转。

**P1-死端②：`astra_underwater_color()` 不可达 → `WATER_ABSORPTION`/`WATER_CHARACTER` 两个选项对水下相机无效。** `scene.glsl:172` 的 `isEyeInWater==1 && blindness<=1e-4` 在任何调用点都不成立——`scene.glsl:180-189` 对主世界水下提前 `return color`（不走 astra_fog）、Nether/End 水下 `:184` 直接 `return astra_water_segment`、`water.glsl:125` 又限定 `isEyeInWater==0`。水下相机看到的床与雾只由 `UNDERWATER_FOG_DENSITY` + Solas 常数决定。**复现判据：水下把 WATER_ABSORPTION 拉到 0，画面蓝绿雾与床色基本不变（只有反射/颗粒变清）。**

**P2-偏差①：水面下表面 fresnel 恒饱和 0.88，TIR 分支走不到。** `water.glsl:179-182` 对 `water && belowWater` 直接早退 → `optics.glsl:6-15` 的 `water_fresnel/totalReflection` 永不执行；`water.glsl:139` `clamp(1.0+dot(normal,incident),0,0.88)`，顶面从下看恒有 `dot(N,I)≥0` ⇒ 几乎全部像素 pin 在 0.88；`:150` `alpha=mix(0.70,1.0,0.88)=0.964` ⇒ 下表面约 96% 不透明。且该式方向与物理相反（正视=强反射、掠射可掉到 0）。复现：水下抬头看水面，"镜面"占绝对主导、看不清水上。注：`water.glsl:136-139` 注释自称参考包同形，需实机 A/B 定性。

**P2-偏差②：水下"透过水面看窗外"通道权重只剩 3.6%，且取到的是上一帧自身颜色。** `water.glsl:150/165-166`（alpha=0.964 → background 仅 1-alpha）；background 取 `texture(colortex4, uv)`，而 colortex4 由 `deferred.fsh:223-224` 从 colortex0 复制，水面像素的 colortex0 正是 gbuffers_water 自己的输出 ⇒ **自反馈**，不是天空/水上世界；同一问题也在 `water.glsl:358` deepFallback。且界面→床的第二段水柱不做 Beer-Lambert（`water.glsl:311/326-327` 传 `inWater=false`，对比反射腿 `:230-231` 传 true）。复现：水下透过平静水面看不到水上地形/天空的清晰像；贴脸看床比直接看更亮。

**P3-疑点①（需实机确认）：水下 bloom capture 与 resolve 寻址语义不匹配。** `bloom_capture.glsl:5-42` 把 4 个尺度**求和写进单张** colortex7，而 `bloom_resolve.glsl:7` 按 atlas 式 `coord/2^lod + offset` 采样；capture 的窗口测试在 1080p 只覆盖画面左上角若干窄带，其余写 0。空气侧读的是 colortex2 mip 链（`bloom.glsl:136-160`），与水下读 colortex7 level0 是两套语义。若成立，水下 bloom 实为"错位/近零的洗色"。

**P3-疑点②：焦散 caster 在 Nether/End 每帧照算。** `shadow.fsh:77-98` 的 `#ifdef WATER_CAUSTICS` 无维度守卫，而两个维度的照明走 `shadow_opaque_visibility`（`end.glsl:41-43`），无 `caster.gba` 读者；且此时 shadowcolor0 未声明格式=RGBA8，>1 增益被裁。下界/末地含水的阴影 pass 白算焦散场。

**P3-疑点③：光束颜色与 WATER_CAUSTICS 耦合。** `light_shafts.glsl:78` 的 `beamTint` 取 `shadowcolor0.gba`，而水 caster 的 gba 只在 `#ifdef WATER_CAUSTICS` 下才被焦散调制（关掉时恒 `vec3(1.0)`，`shadow.fsh:59-61`）⇒ 关焦散会改变光束的颜色/亮度标定（P 档尤其）。

### 5.3 确认无问题项

09-26 三处改动自洽（RGBA16F 声明链、`shadow_coverage` 共享、波浪参数接入）；光束量级链路完整（4 层门控 + 尺寸随段数切换）；颗粒不会被水吸收吞掉（不可见的原因就是选项四档全关）；水下雾/blindness/darkness 覆盖完整；焦散空气侧像素端只服务水上、无重复叠加；值域安全（R11F_G11F_B10F 无 alpha 误用、colortex6Clear=false、colortex7 归一化自洽）。

---

## 六、末地黑洞（Kerr 模块）深读与改进建议

### 6.1 当前模型精确描述

- **求交 = 预计算图谱查表，运行时零积分**：世界射线 gnomonic 投影 `q=(r·b0,r·b1)/(r·b2·0.32)`（`end_kerr.glsl:13-17`），加 `-0.055·spin` 轮廓偏移与 x 向 2.5% 拉伸（`:18-22`）；`end_disc_transfer` 2×2 texelFetch + 分支一致性插值（`:48`），order 0/1 各返回第 1/2 次盘面交会，x=±5.99/y=±2.99 外视为被捕获。
- **离线积分**（`qa/tools/build_end_transfer.py:37-59`）：1500 步定步长、中心引力 `a=-1.5·h²p/r⁵`（非 Kerr 测地线）；两张 2048×1024 半图存前后两次交会，量化进 RGBA8。
- 尺度：`END_SHADOW_TAN=0.32`→视半径 17.74°；`Rin=0.95`、`Rout=5.20`（`end_disc_profile.glsl:11-13`）；盘倾角 9.2°；屏幕基 roll 18°。`3√3M=1.0`、ISCO=1.1547。
- 合成顺序（`end_blackhole.glsl:23-83`）：远端背景→后侧等离子体→order1 二次像→光子环→order0 前景盘→前侧等离子体→极向喷流→透镜星野×backgroundVisibility。全分辨率端 `deferred.fsh:185-195` 再叠 crisp 光子环与透镜星野；高阶像只在 r 1.025–1.065 整体淡出，无 n≥2 细环。
- 多普勒/红移有表达但为局部近似：`end_frequency_shift` 用赤道 Kerr lapse/拖拽/圆轨道 ω，`beta≤0.82`、`g∈[0.25,2.0]`（`:89,93`）；温度×g、辐射×g⁴，再 2.4× 色差；6500K 白点 + 26000K 光球尺度。
- `Rin=0.95` 的意义：内边界藏在阴影视界（b_crit=1.0）之内，**看不到内孔/间隙**；通量 `F∝(1-1/√x)/x³` 峰在 1.29，观测到的"内缘"就是阴影边，表达不了真实 ISCO 内侧高温亮环。
- 阴影边界 `outside=smoothstep(1-aa,1+aa,r)`（`end_blackhole.glsl:30`）——单像素解析 AA，无抖动；星野边界靠 `starVisibility` 与足迹 `resolved` 收紧。天空主体 0.75 倍缓冲，环/星全分辨率。

### 6.2 近似与代价

| 位置 | 现在怎么做 | 视觉代价 |
|---|---|---|
| `build_end_transfer.py:19-21` | 中心引力替代 Kerr 光路 | 阴影不对称靠 `end_kerr_impact` 手调伪造，无真实拖拽像差 |
| `end_kerr.glsl:28-58` | 只存 2 次交会 | 临界曲线附近无高阶像堆叠，光子环外侧缺细密次级环 |
| `end_kerr.glsl:127-133` | 光环 = 固定宽 0.011、居中 r=1.007 的高斯 | 环宽不随放大率变化，无侧向增亮 |
| `end_kerr.glsl:77-94` | g 只由本地点半径+出射方向算 | 前后像共用同一 g 场，多普勒不对称弱于真实 Kerr |
| `end_kerr.glsl:95-114,184-240` | 热点 2 个、固定 60/90s、3 次流场读取 | 湍流尺度固定，远景细节靠衰减"消失" |
| `end_geometry.glsl:171-207` | 岛体 SDF 96 步、包围球 1.65w | 每像素每岛一次 march（环带处 7×96 步） |
| `end_system.glsl:44-46` | 未解析足迹按 `1.2/extent` 压暗 | **近临界曲线的星弧/爱因斯坦环被压暗而非拉成弧，透镜最强处反而最空** |
| `end_illumination.fsh:39-57` | 32 点 Fibonacci 采样源盘、逐点二元遮挡 | 源盘张角 ±59° 压成 32 个点样本，单次穿越期望命中 0.1–0.3 个样本 → **几何环食大概率几乎不可见** |
| `end_blackhole.glsl:116`、`deferred.fsh:192,195` | 遮挡比例→smoothstep(0,0.28)→全局乘暗 18% | 物理不一致：遮挡不该让源自身辐射与背景星野变暗；盘面内也看不到暗带 |
| `lib/end_surface.glsl:9-36` | 直射/高光乘 `(1-0.65·eclipse)`，环境光不变 | 地形全局均匀变暗，无空间半影 |
| `end.glsl:24-31` | `end_fog` 不受 eclipse 影响 | 环食时远景雾色不随光源衰减 |
| `end_geometry.glsl:75-125` | `end_ring_axis`/`end_orbit_position` 仅服务已删除的环带与 0–65 号天体 | `END_PRECESSION_MINUTES`（`settings.glsl:108`）只写进 colortex8 槽 74、运行时无人读，**选项空转** |

### 6.3 改进建议（按 收益×成本 排序）

1. **环食可见化（解析面积）** | 对每座岛把包围球投影到源盘平面，解析求"通量加权盘∩岛投影"面积占比，`blocked=Σ占比`（退一步：32→128 点，1×1 pass 成本可忽略）；饱和点 0.28 提为选项 | `end_illumination.fsh:39-59` | 成本低 | 无 TAA 风险
2. **遮蔽作用于图像而非全局** | 用同一遮挡几何算 q 空间阴影覆盖 `cover(q)`，乘到 `end_flow_material` 的 emission 与 `end_photon_radiance`；把 sky/星野的 18% 乘暗改为只作用于照明 | `end_blackhole.glsl:74,80-81,116`；`deferred.fsh:191-195` | 中 | 低（幅度需重标定）
3. **近临界曲线星弧** | 把 `resolved` 的压暗改为沿 `dx/dy` 主轴的各向异性 3 点重采样 + `1/det` 亮度守恒；抖动用像素内固定图案 | `end_system.glsl:44-46,69,91` | 中 | 中（禁帧内随机）
4. **光子环物理观感** | 加 n=1 解析细环（r≈1.033、宽 0.004、亮度 0.3×主环）；主环亮度改 `(1+0.6·beta_los)` 侧向增亮，环宽随放大率变化 | `end_kerr.glsl:123-154` | 低 | 无
5. **盘面湍流** | `end_flow_field` 加第 2 个相位偏移 parcel 采样（权重 0.35）做剪切平流；`filament` 阈值带随 footprint 缩放；不加帧内随机 | `end_kerr.glsl:171-209` | 低 | 无
6. **面积光地形照明** | 盘面按角径（内盘 ~19–33°）做 3 点解析面积光替换单方向 `max(dot,0)`；eclipse 只作用于对应采样方向 | `lib/end_surface.glsl:9-12`；`end.glsl:40-44` | 低 | 无
7. **性能阀** | 新增 `END_QUALITY`：plasma 层数 4→2、jet 开关、星野 3×3→1 格、光子环 7 岛遮挡循环 | `end_plasma.glsl:10-11,54`；`end_system.glsl:30-96`；`end_kerr.glsl:148-152` | 低 | 无
8. **选项面补齐** | 把 `END_SHADOW_TAN`（atlas 不读它，无需重建）、eclipse 强度 0.18/0.65、盘面亮度/色温尺度、透镜强度 1.85、自旋 0.94 提为选项；删除或重接空转的 `END_PRECESSION_MINUTES` | `end_disc_profile.glsl:11`；`end_kerr.glsl:5,77-94,165-166`；`end_blackhole.glsl:116` | 低 | 无
9. **星野可控** | 让 `STARS` 在末地生效并加 `END_STAR_DENSITY`（当前末地星野无条件绘制） | `end_system.glsl:24-98`；`settings.glsl:89` | 低 | 无
10. **n≥2 高阶像代理** | 在 r<1.08 区把 order1 亮度按 1/n 叠一份 0.3× 代理环（不动 atlas）；真正重建图谱需重跑 `build_end_transfer.py` | `end_blackhole.glsl:45,64-69` | 代理低 / 重建高 | 低

### 6.4 设计文档已否决/已决定（不得走回头路）

1. 天空独立尘环 + 66 个旧轨道天体/牧羊天体已退出绘制 → 不要提议加回来做环食；`END_PRECESSION_MINUTES` 空转正是其副作用。
2. 环食已是真实几何交会，用户明确保留；改进只能增强几何解，不能退回时间表遮罩。
3. 银河层与 `END_NEBULA` 已删除，不重新引入彩色片状天空。
4. 盘面 12 秒双图 crossfade 已被相位精确回绕取代（`end_kerr.glsl:190-197`）。
5. 运行时不做逐像素光路积分（`end_blackhole.glsl:16`）；2026-09-13 审计已判定"光子环外侧星场压缩"是设计书表述问题、实现更正确 → 不要直接删 `resolved`。
6. 另有已登记待办：体积光柱需 composite 挂点（`handoffs/end.md` D3）；`END_VOID_MIN_STRENGTH` 待用户拍板（D1）。

---

## 七、文档清理记录（本会话）

- 删除：`docs/2026-09-06` ~ `2026-09-24` 的 50 份历史轮次报告（含补删的 `2026-09-24-reference-analysis.md`：09-24 参考包研读轮记录，未入索引、无引用；全部已入 git 历史，可恢复）。
- 保留：`README.md`、6 份现行索引文档（09-24-handoff-resolution、09-25-low-end-optimization、09-25-survey-followup、09-25-full-audit、09-26-project-review×2）、`handoffs/`、`parallel-development/`、`images/`、3 份新调研文档（codex-refs-prompt、low-end-shaders-round3、lowend-cross-pack-survey）与本文。
- 引用修复：`Astra/THIRD-PARTY.md`（3 处）、`docs/handoffs/end.md`（2 处）、`docs/2026-09-25-full-audit.md`（1 处）改为"历史报告已清理，git 历史可查"表述；`docs/README.md` 索引更新。`docs/parallel-development/preambles.md:258-259` 引用的是并行 worktree 内的 `nether/docs/`，不受影响、未改动。

## 八、建议路线（四个优先项，按投入产出）

1. **下界氛围**（性价比最高）：逐群系雾密度（一处改动）→ 远雾转 bloom → 逐维度 `shadowDistanceRenderMul≈0` → 修 P-001 熔岩材质映射（`lit.vsh:40`，实打实的 bug）→ N-001 雾高度项。
2. **主世界优化**：阴影三重门控 + 变半影（`diffuse.glsl:260-270`、`shadowmap.glsl:54`）→ 平面云低档单交点 + 视角度阀 → 档位化采样预算。结构性欠账（Voxy、无 TAA 降采样链）单独立项。
3. **末地黑洞**：环食可见化（6.3-1）→ 遮蔽作用于图像（6.3-2）→ 光子环细环/侧向增亮（6.3-4）→ 盘面湍流（6.3-5）→ 光柱与倒角收尾 → `END_VOID_MIN_STRENGTH` 拍板。
4. **水下氛围**：先修接线（P1-② 选项不可达、P2-① fresnel 饱和、P2-② 自反馈）再谈新技法；焦散分维门控 + 1/d 低配分支随手带上；颗粒默认开启与否需要拍板。**所有水下与黑洞结论都需要实机画面定标——本次实例同步后游戏内验证是下一步的分水岭。**
