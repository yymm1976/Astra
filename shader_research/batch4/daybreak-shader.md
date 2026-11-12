# daybreak-shader × Astra 性能调研（batch4）

- 调研日期：2026-10-03。数据时点：包内容为本地解压快照（`reference_shaderpacks/daybreak-shader/`，来自 `reference_shaderpacks/zips/daybreak_0.2 .zip`）；下载量与版本以任务书给定（Modrinth v0.2，175,564 下载，Alpha 阶段）为准，包内无版本/作者声明可复核。
- 引用约定：`P:` = `reference_shaderpacks/daybreak-shader/shaders/`（本包 shader 根即 `shaders/`，行号相对该目录）；`A:` = `Astra/shaders/`（工作树当前状态）。
- 去重口径：动笔前已读 `shader_research/SUMMARY.md`、`SUMMARY-batch2.md`、`SUMMARY-batch3.md`、`docs/2026-10-02-shader-reference-performance.md`、`docs/2026-10-03-batch3-selected-optimizations.md`；下文每条候选均在 `Astra/shaders` 做过关键词 grep（结果随条附出），命中等价实现或材料已列的均转入「去重排除」。

---

## 一、概况

| 项 | 事实 | 证据 |
|---|---|---|
| 版本/定位 | v0.2（zip 名 `daybreak_0.2 .zip`，文件时间 2024-04~06）；原版+、带屏幕空间反射、Alpha 阶段 | zip 内文件时间；`P:composite.fsh` SSR 段 |
| 血统 | **无法从包内判定**：无 README/CREDITS/版权头、无 ShaderCore 类共享库、无 worldN 薄壳，代码组织自成一系，未发现与任何已研究引擎的同构证据 | 全包 find 无 md/txt/credits；`P` 下仅 28 个文件 |
| 许可 | **全包无 LICENSE/README/版权文件**（对 28 个文件逐一 find，0 命中）→ 按保留所有权利处理，只能读思路独立重写并登记 | `find daybreak-shader -iname "*licen*" -o -iname "*readme*" -o -iname "*.txt" -o -iname "*.md"` 为空 |
| 规模 | 28 文件 / 800 行（`cat` 全部文件 `wc -l`，含 block.properties；任务书给 799，同一量级）；64 KB | `find | wc -l`=28；`cat $(find -type f) | wc -l`=800 |
| 程序集（关键） | 仅 7 类程序：`gbuffers_basic`、`gbuffers_line`、`gbuffers_skybasic`、`gbuffers_skytextured`、`shadow`、`dh_terrain`、`composite`（末 pass）。**无** `gbuffers_terrain/textured/water/entities/hand/weather/clouds`、无 `deferred`、无 `final`、无 world 目录、无 `shaders.properties`/`lang` | 全包文件清单；`gbuffers_basic.fsh` 1 行 `#include "/programs/lit_frag.glsl"` |
| 缓冲 | 5 张全分辨率 RGBA：colortex0 颜色+伪透明度、colortex1 高光（r=perceptualSmoothness, g=reflectance）、colortex2 法线、colortex3 反照率、colortex4 天光；composite 再读回全部 | `P:gbuffers_basic.fsh`→`P:programs/lit_frag.glsl:39-44`（DRAWBUFFERS:01234） |
| 组织 | `shaders/` 根为 1 行 `#include` 壳，实现在 `shaders/programs/`；`block.properties` 仅 1 行（water=1000） | `P:shadow.fsh`、`P:gbuffers_basic.fsh` 等；`P:block.properties:1` |

---

## 二、管线与调度

- 管线顺序（包内可确定的部分）：`gbuffers_*`（basic/line/skybasic/skytextured）→ `shadow`（8192 阴影图 + 畸变，`P:programs/shadow_vert.glsl`、`P:programs/shadow_frag.glsl:3`）→ `dh_terrain`（DH 地形，光照后做深度剔除）→ `composite`（SSR + 输出）。
- **无 `shaders.properties`**：没有 `program.*.enabled`、没有 `size.buffer` 分档、没有 `alphaTest`/`blend`/`flip` 声明、无 GUI。全部效果（SSR、阴影）常开，运行时无法降档（详见「反面印证」）。
- 硬编码设置：`const int shadowMapResolution = 8192;` 直接写在 shadow 程序源码（`P:programs/shadow_frag.glsl:3`、`P:programs/dh_shadow_frag.glsl:3`）；`const bool colortex0MipmapEnabled = true;` 写在 `P:composite.fsh:3`（Iris 源码内声明机制，Astra 同样在用，见去重排除）。
- 覆盖缺口：缺失的渲染阶段由 Iris 内置回退程序承担，因此 5 张自定义 GBuffer 与 composite SSR 的实际覆盖面无法从包内判定（见「无法判定」）。

---

## 三、分模块性能手法清单

### 3.1 调度与阶段启停
- 无。没有任何 program 级开关、分辨率分档、关闭时资源缩编或阶段熔断；这是 28 文件全量（`P` 根目录列表可证）。

### 3.2 地形光照与阴影
| # | 位置 | 机制（一句话） |
|---|---|---|
| 1 | `P:programs/functions.glsl:42-43` | 阴影为单 tap 硬阴影：`step(z, texture(shadowtex0))` 与 `step(z, texture(shadowtex1))` 各查一次，无 PCF/核 |
| 2 | `P:programs/functions.glsl:44-54` | shadowcolor0 无条件采样一次，仅在「在阴影中且非不透明遮挡」分支使用（彩色阴影） |
| 3 | `P:programs/functions.glsl:56-60` | 玩家距离 100→150 格 `smoothstep` 把阴影乘子淡回 1（影距外不投影） |
| 4 | `P:programs/functions.glsl:62-68` | 环境 = `(blockLight + 0.2*skyLight) * brdf(diffuseOnly)`；直射 = `skyLight*shadowMultiplier*brdf`（每个像素 2 次完整 brdf） |
| 5 | `P:programs/brdf.glsl:3,16,29-30` | brdf 每次调用内重复 `pow(roughness,2)`、`pow(1-VdotH,5)`、`pow(alpha,2)`、`pow(NdotH,2)`，无预算/无简化路径 |
| 6 | `P:programs/lit_frag.glsl:52-57` | alpha<0.1 先 discard；`P:programs/lit_frag.glsl:62-72` 用 dFdx/dFdy 重建几何法线 + TBN |
| 7 | `P:programs/lit_frag.glsl:77-82` | 水方块（blockId 1000，`P:block.properties:1`）把法线强制为几何法线、固定 reflectance/smoothness |
| 8 | `P:programs/lit_frag.glsl:85` | 仅把天光以 x=1/32 固定列采样写进 colortex4，方块光另在 functions 内单独采样（每像素 2 次 lightmap 采样） |

### 3.3 云
- 无。包内无云程序、无云代码（`gbuffers_clouds` 缺省，由 Iris 回退）。

### 3.4 雾与大气
- 仅两条复用函数：`fogify(x,w)=w/(x*x+w)` 有理衰减与 `calcSkyColor`（`P:composite.fsh:43-50`、`P:gbuffers_skybasic.fsh:12-19`）；无地形雾、无大气散射、无体积雾；天空为 `skyColor→fogColor` 两点混合。

### 3.5 水与水下
- 仅材质覆盖（见 3.2 #7）与 DH 透明度混合（`P:programs/lit_frag.glsl:93-95`）；无水波、无吸收、无水下处理、无反射水面；`P:composite.fsh` 的 SSR 对任意 rough<0.2 表面生效，不区分水面。

### 3.6 粒子·实体·天气
- `P:programs/functions.glsl:69-71`：`renderStage == MC_RENDER_STAGE_PARTICLES` 时跳过 brdf，直接 `ambient + skyLight*albedo`。
- 无天气程序、无粒子专用程序；线条程序只是原版线宽的移植（`P:gbuffers_line.vsh:5-6`）。

### 3.7 后处理与缓冲内存
| # | 位置 | 机制（一句话） |
|---|---|---|
| 1 | `P:composite.fsh:127` | SSR 门控：`roughness < 0.2 && depth != 1` 才进入（天空/粗糙面整段跳过） |
| 2 | `P:composite.fsh:133` | 射线起点沿法线偏移 `mix(0.01,1.5,smoothstep(0,far,dist))`，近处小偏移防自交、远处大偏移防漏检 |
| 3 | `P:composite.fsh:138-140` | 先把 `skyLight * calcSkyColor(ray.dir)` 写入 reflectionColor 作为未命中回退（解析天空近似） |
| 4 | `P:composite.fsh:144-148` | 固定 1000 次循环，步长 `mix(.02,5.0,smoothstep(100,1000,i))` 随迭代序号增长；无距离上限、无迭代预算分档 |
| 5 | `P:composite.fsh:162-164` | 射线出屏立即 break（唯一提前退出） |
| 6 | `P:composite.fsh:166-183` | 命中判定：线性深度差在 `(0, stepSize*4]` 内即接受，命中后从 colortex0 取色并再乘一次 brdf(Fresnel)，break；无二分细化、无置信度 |
| 7 | `P:composite.fsh:190` | 反射按 `mix(reflectionColor, 0, pow(roughness,.1))` 混入主色 |
| 8 | `P:composite.fsh:77-107,152-177` | DH 路径：逐像素做投影矩阵及其 `inverse()`（`:97`）、双投影/双深度混合；无缓存 |
| 9 | `P:programs/dh_terrain_frag.glsl:70-80` | DH 地形在完成整套光照计算之后才用 vanilla 深度做 `discard`（只省写带宽，不省着色） |
| 10 | `P:composite.fsh:78,81,192` | 每像素多次 gamma pow 往返（读缓冲 pow 2.2、写回 pow 1/2.2），colortex3 再解一次 |

---

## 四、反面印证（不建议学）

1. **1000 次固定 SSR 循环且无预算分层**：唯一提前退出是出屏；接受阈值与步长耦合（`stepSize*4`，远处容差最大 20 格），既贵又不稳（`P:composite.fsh:144-183`）。Astra 的有限步进 + 二分细化 + 置信度（`A:global/water/raytrace.glsl:128-134`）是明确更强的形态。
2. **逐像素矩阵求逆**：DH 分支里 `inverse(customGbufferProjection)` 每像素执行（`P:composite.fsh:97`），应上提为帧常量。
3. **参数化 brdf 用运行期 bool 分支复用**（`P:programs/brdf.glsl:1,37-43`）：`diffuseOnly`/`reflectionPass` 两个 bool 让同一个函数在三种意义间切换，每次调用都要带分支；Astra 采用编译期特化（`A:program/*`+宏）更省。
4. **5 张全分辨率 GBuffer**（色/高光/法线/反照率/天光，`P:programs/lit_frag.glsl:39-44`）：反照率与天光均可由已有数据推导，属额外带宽。
5. **alpha 阶段无任何设置面**：`shadowMapResolution=8192` + SSR 常开且不可关（包内无 properties），无法为低端机降档；与 Astra 的 program 熔断/缓冲分档纪律相反。
6. **DH 深度剔除顺序错误**（`P:programs/dh_terrain_frag.glsl:70-80`）：`discard` 放在光照之后，热路径上仍然跑完 brdf；有意义的做法是把可判定的剔除提到光照前（对照 stracciatella 报告的 C1）。
7. **gamma 往返**：`pow(2.2)` 写、`pow(1/2.2)` 读（`P:programs/lit_frag.glsl:98`、`P:composite.fsh:78-81,192`），把缓冲当 sRGB 用，色深/带宽都不划算。

---

## 五、新颖借鉴点

**A/B/C 计数：0 / 0 / 0 —— 本包无 Astra 未实现且值得排期的性能手法（结论：无）。**

判断依据：本包可工作的机制（SSR、单 tap 阴影、彩色阴影、解析天空回退、粒子短路、有理雾衰减、源码内 const 声明）在 Astra 中已有更强或等价的实现，或已列于五份去重材料；其余为缺失/半成品（程序集不完整）。逐条排除见下表。

### 去重排除（每条：包内出处 → Astra/材料侧证据）

| 机制 | 包内出处 | 排除依据 |
|---|---|---|
| SSR 有限步进/出屏退出/细化/置信度 | `P:composite.fsh:127-186` | Astra 已有「SSR 有限步进 + 二分细化 + 出屏退出 + 置信度」（任务背景；`A:global/water/raytrace.glsl:128-134` 置信度实现）；材料 SUMMARY §2.5-5 已列 |
| SSR 解析天空回退 | `P:composite.fsh:138-140` | Astra 已有天空反射缓存回退（`A:lib/sky_reflection_cache.glsl`）；材料 SUMMARY ②-2「SSR miss 回退」已列 |
| 阴影距离淡出 | `P:programs/functions.glsl:56-60` | 材料 SUMMARY-batch2 ②-1「阴影越界钳制/淡出」（redhat/bsl-classic）已列 |
| 彩色阴影读到才用 | `P:programs/functions.glsl:44-54` | Astra 已实现「遮挡时才读彩色阴影」（任务背景） |
| 单 tap 硬阴影 | `P:programs/functions.glsl:42-43` | Astra 已有「阴影核分档 + coverage 早退 + 背光跳过」（任务背景）；单 tap 是降级不是新手法 |
| 粒子光照短路（renderStage） | `P:programs/functions.glsl:69-71` | Astra 同族短路已存在：天气/降水走简化光照（`A:program/lit.fsh:248-253`），粒子另有编译期特化（`A:lib/rain_particles.glsl:9`、`A:program/lit.fsh:171` 的 `ASTRA_PARTICLE`） |
| 有理衰减 `w/(x²+w)`（fogify） | `P:composite.fsh:43-45`、`P:gbuffers_skybasic.fsh:12-14` | 材料 SUMMARY-batch3 §2.1/§3.13（Builder's QOL `lib/math.glsl:9-12` 有理衰减）已列为 A 组候选；`docs/2026-10-03-batch3-selected-optimizations.md` 已按「收益存疑」暂缓 |
| 源码内 const 声明缓冲属性（colortex0MipmapEnabled / shadowMapResolution） | `P:composite.fsh:3`、`P:programs/shadow_frag.glsl:3` | Astra 已用该机制：`A:prepare2.fsh:6`、`A:program/display.fsh:36,39`、`A:program/nether_reflection.fsh:24`；分辨率硬编码 8192 反而是开销项 |
| alpha 早退 discard | `P:programs/lit_frag.glsl:52-57` | Astra 前向同序早退（`A:program/lit.fsh:186,189` 的 alphaTest 拒绝先于光照），无新增量 |
| DH 深度剔除 | `P:programs/dh_terrain_frag.glsl:70-80` | DH-only；Astra 无任何 DH/Voxy 光栅程序（见 stracciatella 报告 C1 与「无法判定」），且本包顺序为反例 |

---

## 六、无法判定

1. **程序集不完整导致实际覆盖面不可判定**：本包唯一完整光照管线挂在 `gbuffers_basic`（`P:gbuffers_basic.fsh`→`P:programs/lit_frag.glsl`），未提供 `gbuffers_terrain/textured(_lit)/water/entities/weather`；在 Iris 上这些阶段将回退内置程序，自定义 GBuffer 与 composite SSR 对主地形/水面的真实覆盖无法从包内判定。因此「1000 步 SSR 的实际帧代价」也无法按包内代码评估（若主地形不走本包程序，SSR 几乎不触发；任务书所载 175k 下载的实机表现不能由本快照推出）。
2. **DH 片元深度剔除的意图**：`P:programs/dh_terrain_frag.glsl:70`（已算光）与 `:78-80`（discard）之间的顺序，无法判定作者意图是性能（省写）还是正确性兜底（防重叠闪烁）；两种解读都不构成可借鉴手法。
3. **作者/版本/下载量不可复核**：包内无任何署名或版本文本，Modrinth v0.2 与 175,564 下载为任务书给定，未在包内找到可核验证据。
