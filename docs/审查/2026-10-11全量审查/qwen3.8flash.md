# Astra 全量代码审查 — 指定入口 group/qwen3.8flash

审查日期：2026-10-11。指定模型入口：`group/qwen3.8flash`（用户称 Qwen3.8flash）。本报告只声明该指定入口，不声称知道分组路由后台的实际提供商。本报告是本任务唯一允许写入的文件；只读源码、配置、现有文档与 `_analysis` 本地参考；未读取任何其他审查者的报告，未参与实施，未启动游戏，未执行安装、发布或 Git 写操作，未调用子代理。

审查对象为 `Astra/shaders/` 当前实际文件。修复阶段已结束、主代理暂停改动后文件保持稳定；审查进行中主代理曾改动三处，本报告一律以改动后的当前文件为准核对相关交界（见下一节），不把已改掉的旧代码列作未处理问题，并注明发现时刻。所有结论区分三种证据强度：**源码确定**（当前文件可直接读出）、**本地宿主取证推断**（`_analysis/iris-runtime` 反编译文本，未在游戏内复核）、**缺事实**（需要实际画面或整帧数据）。

## 审查中已改动的三处（按当前文件核对）

1. `shaders.properties:517-523` 噪声资源独立注册。当前：`steadfastWaterNoise` 仅在 `WATER_WAVES` 下注册（518）；`solasWaterNoise` 无条件（520）；`ittWaterNoise` 在 `WATER_WAVES || (UNDERWATER_LIGHT_SHAFTS && SHADOWS && UNDERWATER_SHAFT_STRENGTH>0)` 下注册（521-523）。逐个核对消费者：`global/water/surface.glsl:19` 与 `lib/itt_water_waves.glsl:7`（后者被 `program/itt_water_normal_cache.fsh:8` 和 `program/lit.fsh:36` 在 `ASTRA_WATER_PASS`＋非下界末地下包含）使用 itt 图；`lib/water_wave_lens.glsl`、`global/atmosphere/weather.glsl:42`、`global/atmosphere/stars.glsl:75,82` 使用 solas 图（星空银河带因此需要无条件注册，正确）。注册条件与实际使用条件相符，**源码确定**无缺口。
2. `program/water.glsl:609-621` 原版太阳尺寸对应。注释与代码现声明 `lit.vsh` 把太阳四边形 X/Z 乘 1.12，水路 `spriteUV` 除以 `0.672*alignment`（= 0.6×1.12）。核对生产者 `program/lit.vsh:111-117`：`ASTRA_SKY_TEXTURED && SUN_MOON_MODE == SUN_MOON_VANILLA` 下对日/月阶段确实 `vertex.xz *= 1.12`。外部与水下透射太阳的角足迹配对一致，此项**已修好，不再列为问题**。资源路径 `shaders.properties:526-531` 按 `MC_VERSION >= 260100` 分叉，与唯一消费者 `program/water.glsl:601-602` 的 `SUN_MOON_MODE == SUN_MOON_VANILLA` 门控配对。
3. `global/water/raytrace.glsl:257-264` 远侧 12 粗查询上限现仅给水路（`surfaceBudget || underwater` 用 12，否则 8），湿润地形恢复原来的 8。**湿地方向的疑问已解决**。同一 263-264 行对空气侧水平水面在全部距离生效这一点仍在，作为 W14 相关发现列在模块 4。

---

## 模块 1：入口 / 程序调度 / GLSL 条件 / 附件格式·清屏·mip·翻转 / 资源与宿主兼容

**覆盖文件与交界**：`shaders.properties` 全部 1066 行（缓冲尺寸 1-100、格式与程序开关 101-260、pass enabling 296-400、自定义纹理 514-536、screen/profile/sliders 541-573、image/compute 808-861）；`lib/settings.glsl` 全部 749 行（含 343-346、680-748 的派生宏）；`lib/uniforms.glsl`；`lib/{water,scene,cloud}_buffer_formats.glsl`；根 pass 壳**全部**（`composite{,1..9}.{fsh,vsh}`、`prepare{,1,2,3,4}.{fsh,vsh}`、`deferred{,1,2,3}.{fsh,vsh}`；`prepare5.*` 与 `world-1/prepare5.*` 确认不存在，properties:213 显式禁用该 key）；`program/` 渲染链入口 41 个；`world1/composite.fsh`（End 的 composite 是 `end_sky_buffer.fsh`）、`world1/deferred1.fsh`（→ `deferred.fsh`）、`world-1/{composite,composite1,composite9}.fsh`（下界反射载波/解析/历史状态）；`lib/{transforms,taa_jitter}.glsl`；`_analysis/iris-runtime/{CompositeRenderer.txt,PackRenderTargetDirectives-new-reports.txt}`。交界：properties 的条件语言 ↔ `settings.glsl` 的宏派生 ↔ 每个 `#include` 生产者-消费者；`RENDERTARGETS` 槽位 ↔ `size.buffer.*` / `const int colortexNFormat` / 清屏常量。

**发现的问题**

- **P2（文档与宿主语义）** 项目内流传的"Iris 在该 pass **结束后**才重建 mip，因此消费者程序里声明 `colortexNMipmapEnabled` 读到上一代"这一说法与本地运行时取证不符。`_analysis/iris-runtime/CompositeRenderer.txt` 的 pass 绘制例程顺序是：绑定 FBO → 若 `Pass.mipmappedBuffers` 非空则遍历并调用 `setupMipmapping(RenderTarget, Pass.stageReadsFromAlt.contains(id))`（字节码行 590-617，其中 `setupMipmapping` 在 331-350 直接调 `IrisRenderSystem.generateMipmaps`），**之后**才 `setupState()`（行 620）、`Program.use` 与绘制。也就是说，在消费 pass 内声明 mipmap 会让该 pass 自己刚生成的纹理先重建 mip 链再绘制，`docs/实现与限制.md:66` 所描述的"composite2 在绘制前生成本帧波面/碰撞光量 mip"与实际行为一致；而 `docs/当前工作.md:22` 以"读到上一代 mip"为理由拒绝"mip 移到生产者"，其前提在取证文本中得不到支持。这条影响模块 5 的 `global/water/light_shafts.glsl:69` 与模块 6 的 `program/prepare_cloud_shadow.fsh:5` 的设计理由表述，不影响当前渲染结果。依据：本地反编译文本；缺失事实：未在运行实例上复核（本次审查不启动游戏）。
  建议：把该前提在负责说明的位置改准为"消费者声明即同帧生成（本地 CompositeRenderer 取证）"，不要把上一代 mip 继续当作拒绝依据。
- **P2（静默溢出风险）** 末地星表容量余量已被用到只剩约 4 行。`lib/end_star_catalogue.glsl:5-12` 定义 `ROWS=512`、`EQUATOR_CELLS=1200`、`WIDTH=1024`、`METADATA=512`；`size.buffer.colortex31=1024 384`（`shaders.properties:67`）即容量 393,216 纹元。按 `program/end_star_rows.csh:13-16` 的 `columns(row)=max(floor(1200*sin((row+0.5)*PI/512)+0.5),1)` 复算，Σcolumns + 512 = **391,670**，最大写入行 `slot/1024 = 382 < 384`，当前**能装下**。`program/end_star_catalogue.csh` 的边界保护是 `cell.x>=1200 || cell.y>=512` 直接 return，写入目标为 `slot%1024, slot/1024`，没有对 384 行的上界检查，因此今后任何把 `END_STAR_ROWS` 或 `END_STAR_EQUATOR_CELLS` 调大的改动都会静默越界写入。
  建议：在两个 .csh 里把 384 与容量复算式写成配对注释，或在 catalogue 写入前加一次 slot >= 1024*384 的丢弃保护。
- **P2（死文件与现行语义冲突）** `global/water/temporal.glsl` 头部第 4 行自述 "RETIRED: no active include"。全库检索确认无任何 `#include` 引用它、`ASTRA_WATER_TEMPORAL` 从未定义（源码确定）。它仍声明 `uniform sampler2D colortex28 / colortex29`，而这两个附件现在的含义是迟绘身体记录与 ITT 波面源图（`program/lit.fsh:79-144`、`shaders.properties:200-212`）。文件不参与渲染，但会误导后续按名字或声明检索的读者。
  建议：删除该文件，或在首行显式指向现行说明并去掉那两个附件声明。

**疑点与缺失事实**

- `world1/setup.csh`（行前缀）与 `world1/setup1.csh`（星表填充）之间的调度次序我未能在本地取证中直接确认；properties:816 只对 shadowcomp 系列记录了 `readProgramArray` 的加载顺序。当前结论依赖"setup、setup1、setup2 按编号顺序派发"这一假设，另有 `world1/setup2.csh` 是单调用空派发、其注释（行 3-5）声称用宿主 barrier 让 catalogue 写入对片段采样器可见。若该顺序假设不成立，末地星表首帧可能读到未写完的目录；这属于缺事实，不是可证实的 bug。
- 未发现附件格式、清屏色与翻转条件方面的矛盾：`lib/water_buffer_formats.glsl:16-27` 的 colortex4 在 `ASTRA_BLOOM` 且非下界末地下用 RGB16F、否则 R11F_G11F_B10F，与 `docs/实现与限制.md:76` 说明一致；`colortex3` 清屏 `vec4(0.498,0,0,0)`（`lib/settings.glsl:739`）的 alpha=0 正是静水掩码零值，与 `program/deferred.fsh` 的积水门配对；`colortex23` 恒等清屏 `vec4(0,0,0,1)`（743）与 `lib/volume_integral.glsl:81-83` 的 identity 段定义一致；blend 覆盖使用裸 pass 名（363-364）与 properties:356-359 记录的"Iris 1.11.2 按 `ProgramSource.getName()` 查表，即 pack-global"事实相符。
  同一维度内的格式冲突也核对过：colortex9（`lib/scene_buffer_formats.glsl:7` RGBA16F）、colortex11（主世界 R11F_G11F_B10F 对末地 RGBA16F）、colortex28（主世界 `program/lit.fsh:22` RG32F 对下界 `program/nether_reflection.fsh:15` RGBA16F）在不同维度声明不同格式，但本地取证显示 `RenderTargets` 是每个维度管线各自构造（`_analysis/iris-runtime/IrisRenderingPipeline-recheck.txt:492,510` 用该管线的 `PackDirectives` 新建），并由 `PipelineManager.pipelinesPerDimension` 按维度缓存（`PipelineManager-lifecycle.txt:5,33-61`），`BufferFlipper` 同样是每管线一个实例，因此这些同名附件不会互相覆盖对方的纹理。源码加本地取证，非缺陷。
- 未发现 GLSL 条件编译层面的不可达或悬空引用：`lib/transforms.glsl`、`lib/uniforms.glsl`、各 slot 选择器（`program/deferred_slot0.fsh:6-16`、`slot1:4-14`、`slot2:2-6`、`volume_slot.fsh:7-11`）的 `ASTRA_SSAO` / `ASTRA_VOLUME_FOG` / `DEBUG_VERTEX_AO` 组合与 `shaders.properties:262-294` 的 pass 启用矩阵互相对应；`ASTRA_SSAO` 在 `lib/settings.glsl:687-689` 定义，`#include "/program/ssao.fsh"` 确实经由 deferred slot 到达（我先前一次检索因输出折叠误判为不可达，已按实际文件纠正）。
- 维度几何壳已核对：我枚举了 `world-1` 与 `world1` 全部 63 个 `.vsh` 壳，除 `world-1/shadow.vsh` 用 `#version 430`（其注释说明 voxel 捕获声明 `uimage3D` 与 `imageAtomicMax` 需要 420+）外，其余都是 `#version` 加 `#define DIMENSION_*` 加单一 `#include` 的薄壳，实际逻辑全在已审的 `program/` 入口里。

**已认可取舍的影响**：`shadow.culling=false`（properties:351-353）保留视野外投射体，代价是阴影阶段几何量不按视锥裁剪，这是文档已记录的既有取舍，本次不作为问题。

---

## 模块 2：阴影投射 / 接收 / 过滤 / 彩影 / 焦散与覆盖边界

**覆盖文件与交界**：`program/shadow.vsh`（220 行）、`program/shadow.fsh`（149 行）、`global/lighting/shadowmap.glsl`（437 行全部）、`global/lighting/diffuse.glsl`（637 行全部）、`program/lit.vsh`（222 行）、`program/lit.fsh`（583 行全部）、`global/water/caustics.glsl`、`lib/water_wave_lens.glsl`、`lib/water_surface_budget.glsl`、`shaders.properties` 阴影段（299-316、544）、`lib/settings.glsl` 阴影派生段。交界：投射端的接收面与水位高度编码（`shadowcolor0`、`WATER_HEIGHT_NONE`、`decode_water_height`）↔ 接收端的 `distort`、四角权重、`shadow_gather_visibility_inside`；`lit.fsh` 的水与非水分支 ↔ `program/water.glsl`、`global/water/light_shafts.glsl` 对同一阴影契约的复用。

**发现的问题**

- **无可证实的实现缺陷**。投射与接收结构是用户明确保留的形态：保守深度 `max(gl_FragCoord.z, planeDepth)` 加受保护的 `layout(depth_greater)`，接收面宏只在非水非天气的主世界启用（`lit.vsh:3-5`、`lit.fsh:3-6`），逐角 `min(referenceDepth, plane-projected)`，Q1 = 中心 + 两个沿梯度方向的瓣（0.58 倍边距）、Q2 = 四瓣，柔化半径 `max(0.22, 0.75*astraSurfaceShadowPixelWorld)`。这些内部自洽，且与水面/水下消费者读到的采样契约一致。
- **P1（边缘锯齿的原因集合，非单一 bug）** 触发条件：主世界任意档位下的阴影边缘。可核对的两条原因：其一，四个质量档全部 `ANTIALIASING=0` 或 `1`（`shaders.properties:564-567`），而 `ASTRA_TAA` 要求 `ANTIALIASING == 2`（`lib/settings.glsl:713-715`），因此出厂任何档位都没有时域滤波参与阴影边缘，边缘量化只能靠 `SHADOW_SOFTNESS` 与 `SHADOW_FILTER_QUALITY` 的有限柔化承担；其二，独立投影长度在 12/48/80 格分别为 2.010/2.021/2.063 格（`docs/当前工作.md` W13 条目），距离驱动的 penumbra 展宽很弱，`SHADOW_SOFTNESS=2` 加 Q1 两组偏移在远处不足以覆盖一个像素以上的量化边缘。具体错误结果即用户报告的阴影边缘锯齿仍明显。这两条是**源码确定**的配置与参数事实；把它们与游戏内观感连线仍缺画面证据。
  建议：优先评估把某档（最自然的是 ULTRA）改为 ANTIALIASING=2，因为阴影与植被细边的锯齿在没有时域滤波时没有别的收敛路径；继续加大柔化半径会同时糊掉接触影，不是等效解法。
- **P2（覆盖边界的分维度不统一）** 非水维度的 `softRadius` 走 `1.5*length(raw.xy)+0.20*(1-ndotl)`，与主世界的 0.22/0.75 像素世界足迹公式不同。在 `shadowDistanceReductionFactor<1` 的远端表现为柔化宽度与分辨率解耦。属已记录的近似，不作为缺陷指控。
- **焦散**：`global/water/caustics.glsl` 用 `astra_water_wave_lens` 的曲率聚光 `0.30+0.70*clamp(1/|area|,0.25,4)`，解析梯度、曲率与足迹过滤共用同一频率（1.35/0.045 与 0.65/0.22），细层不可解析时平滑退出，与 `docs/实现与限制.md:112` 一致；**无可证实问题**。

**疑点与缺失事实**：用户报告的水面/水下开销高于 Steadfast 与阴影的关系无法归因——最新 67 FPS 是混合场景的整帧读数（`docs/当前工作.md` 已说明不能把整帧归给阴影），我没有分项耗时，因此不推断阴影开销占比。

**已认可取舍的影响**：`SHADOW_FILTER_MODE=0`、Q1 两组额外偏移、32 格内接触影保留、`ENTITY_SHADOW_DISTANCE` 64/96 分档、投影覆盖半径允许缩短至多 20%（`docs/实现与限制.md` 观感边界表），均按用户允许范围实现；影响是远处边缘对比继续偏低。

---

## 模块 3：材质直接 / 间接照明、AO、SSS、体素光、实体与手

**覆盖文件与交界**：`program/scene.glsl`（351 行全部，含 4-85 的 include 图）、`global/lighting/{sss,blocklight,wind}.glsl`（全部）、`program/lit.fsh` 附件槽位表（53-145）与写入段（382-410、442-443、509-518）、`program/deferred.fsh:261-272`、`lib/{ao_material,ao_resolve,surface_buffers,sky_directional,sky_sh9,environment_brdf,water_entity_record,encoding}.glsl`、`program/ssao.fsh`（134 行全部）、`program/sky_irradiance.fsh`（37 行全部）、`lib/sky_sh9.glsl`（205 行全部）、`program/unlit.fsh`、全部 `gbuffers_*.fsh` 壳与 `entity/item/block.properties`、`shaders.properties` 的 AO 与 bits 段（143-163、440-512）。交界：`lit.fsh` 生产者 colortex19/20/27/22 ↔ `ssao.fsh` 读 colortex20 与 depthtex0 ↔ `deferred.fsh` 经 `ao_resolve.glsl:55-97` 与 `sky_directional.glsl` 消费 colortex18/21/26/27；`sky_irradiance.fsh` 生产 ↔ `lib/ao_resolve.glsl:82` 与 `sky_directional.glsl:24` 消费。

**发现的问题**

- **无可证实的实现缺陷**，本模块的读写契约链核对通过：
  - 附件槽位：`program/lit.fsh:53-145` 的 16 种 `RENDERTARGETS` 组合按 `ASTRA_TAA × ASTRA_SSAO × ASTRA_DIRECTIONAL_SKYLIGHT × ASTRA_TRANSLUCENT × ASTRA_LATE_ENTITY_SOURCE` 穷举，`ASTRA_AMBIENT_SLOT`/`ASTRA_NORMAL_SLOT`/`ASTRA_SKY_RESPONSE_SLOT`/`ASTRA_LATE_ENTITY_SLOT` 在每种组合下都被显式定义，写入用宏而非硬编码下标，与 `shaders.properties:147-161` 的尺寸门控条件逐项一致（同一组 `defined SCREENSPACE_AO && defined SHADOWS && AO_STRENGTH > 0 && DEBUG_VERTEX_AO == 0`；`lib/settings.glsl:687-689` 少写 `DEBUG_VERTEX_AO` 一项，但外层 683 行已含 `DEBUG_VERTEX_AO == 0`，等价）。
  - SH 数学：`program/sky_irradiance.fsh:21-34` 的 4×16 上半球求积，权重 `4*PI/128` 配 128 个立体角元、`hemisphereWeight` 1.08/0.92 分配上下半球填充，`oddY` 对应 l=1 的 Y 奇项符号；按 `lib/sky_sh9.glsl:47-51` 的归一化常数复核 `astra_sh9_irradiance` 的 A0=PI、A1=2PI/3、A2=PI/4，与该文件自述的一致性检查（:159-161）成立。colortex18 的 9 个系数用 `int(gl_FragCoord.x)` 分列，与两个消费者的 `for(i<9) texelFetch(colortex18,ivec2(i,0),0).rgb`（`ao_resolve.glsl:82`、`sky_directional.glsl:24`）匹配，`size.buffer.colortex18=9 1`（`properties:135`）恰好容纳。
  - AO：`program/ssao.fsh:41-134` 半分辨率、12 点固定黄金角圆盘，`ASTRA_DIRECTIONAL_SKYLIGHT` 同时产出弯曲法线到 colortex26（RG16F），且弯曲方向不乘 `AO_STRENGTH`（:109-113 注释与实现一致）；退化时回落到几何法线（:128-130），并显式避免 `screen_view` 在无效深度上的使用（:42-47,65）。接收端 `ao_resolve.glsl` 用 agreement≥0.85 与 Δlog2 depth≤0.05 判定可复用，`extra = vertexAO - min(vertexAO, visibility)`，SH 重评估换用弯曲法线。链条闭合。
  - 体素光与手：直接照明、手持光、自发光、`BLOCKLIGHT_SUPPRESSION` 的分支与 `global/lighting/blocklight.glsl` 一致；`unlit.fsh` 与 spidereyes 不消费阴影；手位在 `program/water.glsl`、`global/water/light_shafts.glsl:48-49` 与 `lib/ao_material.glsl` 三处按同一 `MC_HAND_DEPTH` 契约处理，三处一致。
- **P2（配置导致的间接照明不对称，非缺陷）** `program/scene.glsl:307-345` 只在 `CLOUD_MODE == CLOUD_PLANAR` 时对直接光做云与雨衰减，其他云模式透射恒为 1.0（`global/atmosphere/weather.glsl:131-144` 说明如此）。影响：选 vanilla 云的用户看不到任何云遮光变化，与该选项的门控一致，属取舍。
- **P2（成本结构，不报 FPS）** 迟绘实体记录 `colortex28` 在全分辨率（`shaders.properties:200`）且不随场景 AA 或 SSR 开关缩尺寸；`blend.gbuffers_entities{,_translucent}.colortex28=ONE ONE_MINUS_SRC_ALPHA`（363-364）意味着它每帧重写整屏。这是 W14 树叶倒影与 W05 跨界身体的必要成本，不是错误；我没有依据把它写成开销高的定量结论。

**疑点与缺失事实**：`entity/item/block.properties` 只用于材质覆盖选择，我读了文件本身但没有逐条对照材质 ID 语义。实体 TAA 缺每实例运动输入这一已知限制（`docs/当前工作.md` D04）意味着手部与实体在 `ANTIALIASING=2` 下的历史仍不可靠；由于出厂没有任何档位启用 2，这条目前只在用户手动改档时才会暴露。

**已认可取舍的影响**：`PURKINJE_STRENGTH=0`、`DIRECTIONAL_SKYLIGHT` 与 `SCREENSPACE_AO` 在所有 profile 关闭（`shaders.properties:564-567`），因此出厂档位的间接照明只有 ambient 加上不带 SH 的分支；影响是暗部方向感弱，属配置结果而非实现遗漏。

---

## 模块 4：水面波纹 / 反射 SSR / 折射 / 介质 / 迟绘身体 / 界面两侧

**覆盖文件与交界**：`program/water.glsl`（1008 行，分段全读，含 1-50 契约注释、341-380 足迹共享、569-596 竖流界面、598-636 `water_transmitted_sun`、638-747 水下窗口、750-905 主入口）、`global/water/{raytrace,refraction,surface,optics,absorption,medium_state,particles,temporal,caustics,bloom_capture}.glsl`、`lib/{water_surface_budget,water_interface_record,solas_water,solas_water_frame,water_diffusion,water_wave_lens,water_palette,water_entity_record,taa_jitter}.glsl`、`program/lit.fsh` 记录写入（26-29、442-443）、`gbuffers_water.fsh` 与 `world-1`/`world1` 的对应壳、`docs/实现与限制.md:21-33,104-105,110`。交界：`lit.fsh` colortex28 生产者 ↔ `water.glsl:57-84,99-101,422-427,519-522` 消费者；`raytrace.glsl` 预算常量 ↔ `water.glsl:825-858` 的 `queryImportance`/`surfaceBudget`/`underwater` 传参 ↔ `program/deferred.fsh:62` 积水路径。

**发现的问题**

- **P1（树叶倒影：近场粗查询被裁到 12，与文档口径不符）** 触发条件：主世界 `OVERWORLD_BUDGET>=1`（四档全为 1）、从空气看水平水面、接收距离小于 48 格。当前 `global/water/raytrace.glsl:263-264` 对 `surfaceBudget && !underwater` **在所有距离无条件**套用 `min(coarse, mix(12, 6, surfaceSimplification))`，而 `lib/water_surface_budget.glsl:6-16` 的 `astra_water_surface_simplification()` 在非 `ASTRA_OVERWORLD_AGGRESSIVE` 下是 `smoothstep(48.0, 96.0, receiverDistance)`，即 48 格内为 0。结果：48 格内的空气侧水面反射粗查询被固定为 **12**（加 4 细化共 16 总），而同一函数 257-260 行的 32 格渐入本来已经把 12 这个上限只用于 32 格之外；`raytrace.glsl:28-37` 的注释和 `docs/实现与限制.md:29` 都写"32 格内 16 粗 + 4 细化 = 20"。两处口径对不上，实际效果是把为 W14 补偿而放宽的 12 上限同时压到了近场，削弱近处树叶与细几何的 SSR 命中率。这**不是**主代理已改掉的湿地形那半（那是 259 行的 `8.0` 分支），是仍在当前文件里生效的另一条。依据：源码确定。
  依据补充：建议把 263-264 行的 min 用 smoothstep(32.0, 48.0, receiverDistance) 渐入，或与 257-260 行的渐入合并成分段上限，使 32 格内保持 ASTRA_WATER_COARSE_STEPS=16；同一次改动把 28-37 行注释与 docs/实现与限制.md:29 改准。
- **P1（树叶倒影：默认档位反射足迹退化为单点）** 触发条件同上，`WATER_EFFECT_QUALITY=1` 加 `ASTRA_OVERWORLD_OPTIMIZED`。`program/water.glsl:355-361` 在该宏下 `maxFootprints = 1`；837-852 行的粗糙半径只在 `!ASTRA_OVERWORLD_OPTIMIZED && WATER_EFFECT_QUALITY > 0` 时计算，预算内 `radius` 恒为 0。于是命中后的 `water_sample_path` 只有一个双线性点，没有粗糙锥多采样。`docs/实现与限制.md:104` 自报独立单层孔隙场接收率 86.94%→88.05%、复杂错层树冠 22.79%→31.36% 且仍有显著 SSR 遗漏，与该结构一致。这是"更锐但更漏采"的取舍叠加，影响就是 W14 未解。我没有游戏画面证据说明恢复近场 20 后树叶必然出现，因此不宣称问题已解决。
  建议：若主代理判定剩余漏采主要来自足迹退化，可只在细化分支或粗区间失败的路径上恢复多足迹（例如半径不可用时才扩到 5 组），代价集中在少数像素；这属于新的开销取舍，需用户确认。
- **P2（迟绘身体记录的有效位判据）** `lib/water_entity_record.glsl:14` 把有效记录写成 alpha=0，而非法清除用 `vec4(0.0)`，两者在 `water.glsl` 侧靠颜色与深度分量区分。设计有意（分数透明片元不再擦掉身体记录，对应 W05 修复），但两个语义共用一个 alpha 字段容易被后续改动误读；`global/water/temporal.glsl` 里同名附件的已退休历史语义加重了这个混淆。列为可维护性问题。
- **已核查并排除的疑点（不是问题）**：`global/water/refraction.glsl:35,65` 用未抖动的 `view_screen` UV 与 `gl_FragCoord.z` 比较，看似与 TAA 抖动不一致；但 `lib/taa_jitter.glsl:8-11,26-29,35-37` 在 `isEyeInWater != 0` 时抖动偏移返回零，`astra_jitter_clip` 共用该偏移，因此水下比较两侧同域，不存在错位。写明此结论以免重复怀疑。
- **未发现问题交界**：界面两侧的 `water_side_acceptance` 正负 2 厘米渐退、`water_surface_absorption_depth` 用几何而非 skylight 代理限制侧脸吸收深度（40-50 行）、介质单雾（`astra_apply_medium` 在一条水路只施一次）、薄层与竖流的 `water_is_thin_sheet()` 分支互斥，在源码层自洽。

**疑点与缺失事实**：`docs/实现与限制.md:31` 说"为树叶质量补偿，主世界远侧反射查询允许更多粗点"，与 263-264 行把近场一并裁到 12 的实际效果矛盾。需要主代理确认放宽的意图是否包含近场，这决定上面的 P1 应修成恢复近场 16 粗、还是只恢复 48 格外的 6 渐退。768×432 扇面呈现的 0.0512→0.0553 ms 是 GPU 绘制中位耗时，不是游戏帧时，不能作为达标证据。

**已认可取舍的影响**：低菲涅尔跳过追踪、单足迹预算采样、重雾远景跳过柔化、SSR 不能反射屏外几何（`docs/实现与限制.md:23,29`）均为用户允许的近似；影响集中表现为远处与孔隙漏采，以及倒影比参考包更锐但更空。

建议给出的四条修复取向（按我的判断排序）：先解 263-264 行的近场 12 上限（它是纯配置后果，改动面最小），再决定是否为树叶恢复部分多足迹，其余两条属于口径与可维护性。

---

## 模块 5：水下光束（源图 / 窗口 / 积分 / 消光 / 水位 / 柔化 / 太阳）

**覆盖文件与交界**：`global/water/{light_shafts,shaft_layout}.glsl`（全部：20-25 采样数、36-63 端点重建、65-123 入口遮挡、124-151 八点波面积分、152-226 march 主体、228-266 解析端）、`lib/{itt_water_field,itt_water_waves,solas_water,water_diffusion,water_palette,water_surface_budget}.glsl`、`program/{scattering.fsh,scattering.vsh,itt_water_normal_cache.fsh,itt_water_normal_cache.vsh,water_composite.fsh,water_bloom.fsh,display.fsh}`、`prepare4.{fsh,vsh}` 与 `composite2.{fsh,vsh}` 壳、`shaders.properties:8-26,199-217,317-321`、`lib/settings.glsl:717-724`、`_analysis/iris-runtime/CompositeRenderer.txt`（mip 次序，见模块 1）。交界：prepare4 源图的 colortex29 RG/B ↔ composite2 消费并声明 `colortex29MipmapEnabled` ↔ composite3 与 `display.fsh:22` 的 `water_shafts_resolve(colortex1,...)`；`scattering.vsh` 的平坦 varying ↔ 纹元 (0,0) 的格偏移；`lib/solas_water.glsl` 的雾与光束共享 `waterFogFrameResponse`。

**结构核对（源码确定，无实现缺陷）**：源图 1024² RGBA16F 覆盖 64 格世界窗口、格距 0.0625，窗口原点按 16 纹元 = 1 格对齐（`program/itt_water_normal_cache.vsh:16-18`），像素 (0,0) 只传格偏移（`itt_water_normal_cache.fsh:21-23`），消费者 `water_shaft_field_origin`（`lib/itt_water_field.glsl:16-18`）读回；B 通道是同帧未门控碰撞光量（Fresnel 透射 × `(0.24+3.05*off)^3` 加 `0.22*off/(0.15+off)`）。march 侧 `marchLength = min(rayLength, min(astraWaterShaftRange, WATER_SHAFT_FAR_END))`（`light_shafts.glsl:161`），4 节点 Gauss 区间乘以每区间 8 节点波面积分（131-150、188-219 行），入口用 `worldOrigin + source*(depth/source.y)` 的折射投影（174 行）配 `entryRay` 平面视图，遮挡走真实阴影（96-122 行），消光分入射与视程两组系数（182-185、214-215 行）。八点路径积分保持，未退化为壳层点，符合用户保留要求。长度语义分开承担：积分用 `marchLength`（161、170 行裁到水面交点），写入附件 alpha 的是端点 `rayLength/128`（162、225 行），预算下再由 `program/scattering.fsh:98-101` 裁成 `48/128` 标记；解析端 `water_shafts_resolve`（244-266 行）按每个纹元自身 alpha 与本体端点距离做深度权重拒绝，所以"alpha 保留端点、积分窗口单独受限"是配对设计，不是遗漏。窗口边缘 2-3 格二次渐弱（144-145 行）与不循环平铺（`water_shaft_wave_segment`，82-95 行）配对。

**发现的问题**

**P1（光束少且挤的原因集合）** 触发条件：主世界水下、晴天或有月、`OVERWORLD_BUDGET>=1`。以下每条都可在当前文件确认，共同产生用户报告的现象：

1. 采样数被预算钉死：`global/water/light_shafts.glsl:21-25` 在 `ASTRA_OVERWORLD_OPTIMIZED` 且 `UNDERWATER_SHAFT_SAMPLES >= 7` 时把宏设为 7；`shaders.properties:564-567` 四个 profile 全部 `OVERWORLD_BUDGET=1`，因此 ULTRA 的 10 永不生效。区间上限 7 意味着积分窗 `min(48,26)=26` 格内最多 7 段，束的角分辨率受此限制。
2. 薄层与静水直接关闭：`program/scattering.vsh:31-41` 与 `light_shafts.glsl:164-167`（`!WATER_WAVES || WATER_WAVE_HEIGHT==0`）以及 167 行的 `waterShaftSource.w<=0 || waterShaftSurface.y<0.5` 早退；体积状态 `a<=0.5` 的薄水面（0.125-0.375）不出束。
3. 入口证据苛刻：96-114 行要求阴影图中存在解码高度与 `entry.y+cameraPosition.y` 相差小于 0.75 格、且向内偏移 0.18 格的水投射体，四角权重乘积非零才继续；岸边第一格之外很容易整段为 0。
4. 距离与窗口衰减：`shaft_layout.glsl:5-8` 近端 0.08 到 `UNDERWATER_SHAFT_DISTANCE` 渐入、14 到 26 格渐出，26 格以外完全无光；叠加 64 格窗口边缘 2-3 格再乘一次衰减，可用范围被裁到中段。
5. 前向眩光被替换：`lib/solas_water.glsl:80-92` 在 `ASTRA_UNDERWATER_SHAFTS` 下 `fog *= response.x`，把 `glare` 项整体丢弃。用户可能把那层束的辉光算作束本身的一部分，开启光束后它必然消失，这让"束看起来更少"更明显。

具体错误结果：可见束数量少、间距挤、且用户对上轮改动无可感区别（`docs/当前工作.md` W04 自述）。我的判断是优先动第 1 条（让上限随 `WATER_EFFECT_QUALITY` 放开，或在 `marchLength` 明显短于积分窗时减少区间、把预算集中到中段）与第 3 条（把 0.75 格高度匹配改为与 `WATER_WAVE_HEIGHT` 相关），而不是继续加大 `UNDERWATER_SHAFT_STRENGTH`，后者只把已有的少数束提亮。

**P1（水下太阳圆、水外方）** 触发条件：`CLOUD_MODE == CLOUD_PLANAR`（BALANCED/ULTRA）且水下看水面窗口。当前 `program/water.glsl:724-740` 取 `astra_cached_reflection_sky(skyDirection, skyRoughness)`，该表由 `program/sky_reflection_cache.fsh:11-12` 用 **`astra_sky_radiance`** 生成，其中包含解析 glare 瓣（`global/atmosphere/sky_gradient.glsl:216-248`，`visfactor/(1-(1-visfactor)*VdotSM4)`，朝日指数 3、朝月 6）与 `astra_twilight_highlights`（`global/dimension/overworld.glsl:22`）。glare 是圆角强度峰；非 `ROUGH_SKY_REFLECTIONS` 分支只取 level 0（`lib/sky_reflection_cache.glsl:60-64`，带 gutter 的线性过滤），进一步把峰底糊圆。外部天空则是原版方形 sprite（`program/sky.fsh:67-86`，由 `program/lit.vsh:111-117` 乘 1.12）。新增的 `water_transmitted_sun`（`water.glsl:738-739`）把方形太阳**加**在这个圆形 glare 之上（730-739 行先 `sky = 缓存表`，`sky += astra_star_field(...)`，随后 `sky += water_transmitted_sun(...)`），因此水下同时出现圆底与方芯。依据：源码确定；缺失事实：游戏内圆形与方形的主观突出程度未确认，`docs/实现与限制.md:110` 记录的只有本机 26.2 独立 Snell 呈现里方形太阳落在透射窗口内。修复方向（交主代理裁决）：在 `SUN_MOON_MODE == SUN_MOON_VANILLA` 下让写入反射表的天空不含解析瓣（表只存 `astra_get_sky_base` 的平滑基，瓣与盘由消费者按需添加），这样内外都只由方形 sprite 承担太阳形状。

**P2（1×1 附件上的读取约束）** `shaders.properties:206-212` 在无光束配置下把 `colortex29` 缩到 `1 1` 并禁用 prepare4；`program/scattering.vsh:56` 读取其 (0,0) 纹元。该读取受 `ASTRA_UNDERWATER_SHAFTS` 门控，因此当前安全；若今后出现非门控消费者，会读到无意义的单纹元。作为约束记录，非问题。

**疑点与缺失事实**：源图内存不是矛盾：`docs/当前工作.md` W03 的"每张含 mip 增加约 5.33 MiB"说的是相对旧 RG16F 格式的**增量**，`docs/实现与限制.md:70` 的"约 10.67 MiB"是 RGBA16F **总量**。复算（1024² 基级乘以 4/3 链系数）：RG16F 总量 5.333 MiB、RGBA16F 总量 10.667 MiB、两者差恰为 5.333 MiB，两个数字同时成立。我先前把它记为口径冲突是错的，撤回该条；剩下的只是 `docs/实现与限制.md:70` 那句"10.67 MiB 而非 5.33 MiB"容易被读成否定增量，建议在该行补一个"（5.33 为增量）"限定词。。`docs/实现与限制.md:102` 的 1.99→0.88 ms 与 0.0696+0.8100 ms 都明确"未计入 mip 生成、场景阴影、游戏其它阶段或整帧"，不能换算整帧收益，我不用它推断 FPS 达标与否。独立呈现的 0.25/4/12 格眼深平均蓝光量 0.09614/0.08897/0.07563 显示响应仍随深度减弱，但那是呈现数值，不等于游戏内束的数量与布局。

**已认可取舍的影响**：64 格窗口与边缘渐弱、非完整光子输运、蓝通道平均绝对差 0.002854（非线性光量先于 mip 过滤，`docs/实现与限制.md:102`）为已声明近似；影响是深水与窗口边缘的束偏冷偏暗。

---

## 模块 6：天空 / 日月 / 星空 / 晨昏 / 云 / 天气及历史

**覆盖文件与交界**：`global/atmosphere/{sky_gradient,sky_minishita,stars,clouds_planar,clouds_screen,cloud_temporal,cloud_shadow_cache,weather,fog,volume_fog}.glsl`（`sky_gradient.glsl:161-270` 全部有效函数、`volume_fog.glsl:56-185` march 主体）、`lib/{twilight,sky_reflection_cache,sky_gradient_cache,cloud_sample_grid,cloud_buffer_formats,cloud_history_frame,volume_integral}.glsl`、`program/{sky.fsh,sky_gradient_cache.fsh,sky_reflection_cache.fsh,prepare_cloud_shadow.fsh,cloud_shadow_cache.fsh,cloud_screen.fsh}` 与 `prepare.fsh`/`prepare1.fsh` 根壳、`gbuffers_skybasic.fsh`/`gbuffers_skytextured.fsh`、`global/dimension/overworld.glsl`（102 行全部）、`program/deferred.fsh` 天空合成段（233-238、342-359、367-393、395-437）、`shaders.properties:68-95,176-196,226-255`。交界：prepare 与 prepare1 谁写 colortex11/12、`ASTRA_GRADIENT_SKY_CACHE` 与 `ASTRA_SKY_CACHE_WRITE` 的互斥、云历史 24/25 与原始云附件 12 的所有权切换、`sky.fsh` 与 deferred 的单次评估、表生成与 `water.glsl` 消费端的云调用配对。

**覆盖结果**

未发现可证实的实现缺陷，四处重点交界核对通过：

- 生产与消费不重叠、不自采样：`prepare.fsh:2-8` 用 `ASTRA_GRADIENT_SKY_CACHE` 决定本帧产出的是梯度表（12）还是反射环境（11）；`sky_reflection_cache.fsh:3` 定义 `ASTRA_SKY_CACHE_WRITE`，`global/dimension/overworld.glsl:4,55` 与 `sky_gradient.glsl:205` 都用 `!defined ASTRA_SKY_CACHE_WRITE` 把生产者排除在"把自己的目标当采样器"之外；`shaders.properties:228-242` 的门控与 `lib/settings.glsl:708-711` 的宏条件在 `SKY_MODE × CLOUD_MODE × CLOUD_TEMPORAL` 组合上等价，`prepare1` 只在梯度表启用时接管反射环境，避免两个 pass 同时写 11。表尺寸与 GLSL 常量配对：`lib/sky_gradient_cache.glsl:12-20` 的 65/129/257 与 `shaders.properties:70-79` 完全一致，奇数尺寸保留零角节点。
- 天空只评估一次：`sky.fsh:138` 在下界与非 vanilla 云模式返回黑，由 deferred 合成；末地天空在 `deferred.fsh:367-393` 从 colortex9 合成，与 `world1/composite.fsh`→`end_sky_buffer.fsh` 的分工不重复。
- mip 与翻转配对：`program/prepare_cloud_shadow.fsh:4-6` 只为 colortex11 在 `ROUGH_SKY_REFLECTIONS && CLOUD_PLANAR` 下声明 mips，写入者是更早的 prepare/prepare1，`lib/sky_reflection_cache.glsl:25-65` 用显式 `textureLod(..., level)` 跨 mip 并在经度接缝手工插值，与 `CompositeRenderer` 取证次序相容；`shaders.properties:60-64` 的 256/258 宽度切换与 `sky_reflection_cache.glsl:7,11-14,60-61` 的 gutter 数学一致。
- 星场与云透射：`program/water.glsl:731-734` 的 `astra_star_field(skyDirection)*(1.0-astra_planar_cloud(skyDirection).a)` 只在 `CLOUD_MODE == CLOUD_PLANAR` 分支的 `#ifdef STARS` 内执行，避免与 736 行的 `astra_overworld_sky`（内部已含星点，`global/dimension/overworld.glsl:96-98`）重复相加；同帧第二次 `astra_planar_cloud` 的代价只落在折射天空未被几何完全遮挡的像素上（`geometryCoverage < 1.0` 分支）。低频反射表刻意排除星点，这里是补偿，逻辑正确。它同时意味着表生成（`sky_reflection_cache.fsh:22`）与水路各跑一次云 march，是模块 9 记录的成本点。

**P2（注释与实际内容不符）** `global/dimension/overworld.glsl:42-43` 断言反射"deliberately omits sun/moon discs and the star field"。星点与 sprite 盘确实不在表里，但解析 glare 瓣在：`astra_sky_radiance`（13-29 行）→ `astra_gradient_sky` → `astra_get_sky(..., doGlare = true, ...)`（`sky_gradient.glsl:266-267`）→ 瓣项由 `sky_reflection_cache.fsh:12` 写入 colortex11 → 被所有反射消费者（`overworld.glsl:58`、`water.glsl:730`、`sky_irradiance.fsh:27`）读取。因此反射环境没有排除日月的低频光晕，只排除了盘。影响：该注释会误导"反射里没有太阳"的推理（模块 5 的圆方问题正落在这条交界上），并且 SH 辐照度里也携带这个瓣。依据：源码确定。

**P2（云柱近似）** `global/atmosphere/clouds_planar.glsl:286-475` 在首个通过门限的采样处 break，并把该单点当作整列结果，之后靠 1-2 步入口细化与 `edgeWidth` 足迹柔化；`ASTRA_CLOUD_LOW_TIER` 与均衡档的 `sampleCount` 为 4-6 / 6-16（255-279 行），完整档 8-96（276-277 行）。文档已承认"不能称完整连续体积求解"（`docs/实现与限制.md:33`）。影响：薄云覆盖偏差、柱内亮度不随深度变化，W07 的薄云边缘稳定依赖 `cloud_temporal.glsl` 的相位保护而非连续求解。

**疑点与缺失事实**：晨昏过渡（W09）与日出薄云抖动（W07）的实际画面状态未确认，文档本身标注"实际观感待反馈"。`VOLUMETRIC_FOG` 在四档全关，因此 `volume_fog.glsl` 与 `lib/volume_integral.glsl` 这条链在当前出厂配置下不参与渲染；我核对了它的解析补段（`volume_fog.glsl:173-180`）与 colortex23 恒等清屏配对，正确性只对启用该选项的用户有意义。

**已认可取舍的影响**：Minishita 自述的地平线橄榄色（2 采样过消光）、`ASTRA_SKY_HORIZON_ELEVATION=0.10` 抬升、`DAY_GAIN=22` 补偿缺失的 ambient floor 都是已记录近似；`CLOUD_SHADOWS` 全档关闭使云影只在雨天被消费（`program/cloud_shadow_cache.fsh:12-19`），影响是晴天没有云影但省下一次缓存写与一次查表。

---

## 模块 7：后处理（泛光 / 调色 / AA / 历史 / 重投影 / 显示颜色域）

**覆盖文件与交界**：`program/{display.fsh,display.vsh,final.fsh,taa_resolve.fsh,taa_state.fsh,exposure.fsh,water_composite.fsh,water_bloom.fsh,composite.fsh,composite1.fsh}`、`lib/{taa_jitter,taa_state,taa_reactive,effect_history,history_frame,encoding,dither,tonemap,color_controls,solas_water}.glsl`、`global/post/{bloom,fxaa,godrays,exposure,grading}.glsl`（`grading.glsl:1-150` 契约注释与全部函数入口、`tonemap.glsl:197` 的 `apply_tonemap`）、`composite8.fsh` 的 `ASTRA_DISPLAY_PREPARE`、`shaders.properties:32-47,98-132,322-342`、`_analysis/iris-runtime/FinalPassRenderer.txt`。交界：deferred 的反应图 16 → `taa_state`/`taa_resolve` → 历史 15/17 → `display`/`final` 显示链；colortex4 与 colortex0 的水下/空气双臂选择；FXAA 输入 colortex13 的 luma-in-alpha；Bloom 的 0.25 尺寸捕获与 `BLOOM_CAPTURE_SCALE`。

**覆盖结果**

未发现可证实的实现缺陷。时域链逐条核对通过：colortex16 只在 `ASTRA_TAA` 下声明 R8 并清零（`lib/taa_reactive.glsl:3-10`）；`program/deferred.fsh:241-251,355-357,378-379,414-424` 写反应量，`taa_reactive_neighbourhood` 用 3×3 早退（34-57 行）；历史深度用 `log2(1+viewDepth)` 编码进 colortex15 的 alpha，`-1.0` 为无效与拒绝（100-104、117、181 行）；植被运动 UV 由 `lit.fsh:509-518` 写入 colortex22；1.25 倍标准差的 YCoCg 裁剪、相位相关的中心信任与水面旁路都按条件生效；`ANTIALIASING != 2` 时 `shaders.properties:110-119` 把 15/16/22/17 全部缩到 `1 1` 并禁用 composite6/7，与 `ASTRA_TAA` 未定义一致，不存在半开状态。

- 显示域次序：`global/post/grading.glsl:22-64` 声明的五槽契约（exposure 在 tonemap 之前、grading 在显示域、dither 在 clamp 之后）与 `program/display.fsh:226-240` 的实际调用顺序一致；`lib/tonemap.glsl:197` 的四个算子都返回显示线性，由单次 `srgb_encode` 编码（`grading.glsl:62-64` 记录 SC-16 已解决）；`lib/dither.glsl:9-19` 的非动画 IGN 与显示链的抖动位置配对，帧索引不参与，符合其头部说明。
- 泛光：`global/post/bloom.glsl` 的捕获比例与 `shaders.properties:32-36,43-46` 的 0.25 一致；`program/display.fsh` 内对 colortex7 与 colortex2 的 `MipmapEnabled` 声明都在读取者自身 pass，按模块 1 的取证即同帧生成。
- 重投影：`lib/taa_state.glsl`、`program/taa_resolve.fsh` 与 `lib/history_frame.glsl` 的帧/视口连续性判据（配合 `program/water_state.fsh:15-25` 的 `frameCounter % 4096` 与 `viewWidth/viewHeight` 全等校验）在窗口尺寸变化与时间不连续处都判无效，未见把上一代内容误接受的路径。

**P2（水下与空气显示域不对称）** `program/display.fsh:226-228`：普通水走 `solas_water_display(apply_exposure(hdr))`，不经过 `display_air_hdr`（85-91 行），因此 Purkinje 与自动曝光都不作用于水下；空气臂是 `srgb_encode(apply_tonemap(apply_exposure(display_air_hdr(hdr))))`。`TONEMAP_OPERATOR` 只作用于空气（注释在 220-221 行，lang 已文档化）。影响：用户切换色调算子时水下不变；`AUTO_EXPOSURE` 开启时水下仍按手动滑条。这是有意的域配对（保持参考包的 gamma 混合次序），但需要主代理确认"水下不吃自动曝光"是用户接受的口径，否则夜里水下与空气亮度会脱节。

**P2（FXAA 输入的结构约束）** `program/final.fsh:12-19` 与 `global/post/fxaa.glsl:16-25` 依赖 colortex13 的 alpha 通道携带 luma，且水下用 `geometryOnly` 变体。该约束只在 `ANTIALIASING == 1` 时成立（`shaders.properties:122-131` 据此启用 composite8 与 1.0 尺寸），配置自洽；记录为后续改动时不可破坏的配对。

**疑点与缺失事实**：本模块没有整帧测量，我不能给出任何 ms 或 FPS 数字，也不能说后处理开销低于 Steadfast。`global/post/end_sky_tonemap.glsl`（末地天空专用曲线）与 `lib/tonemap.glsl` 的每个算子数值只读了入口与调用次序，未做逐算子观感判断。

---

## 模块 8：下界 / 末地维度入口与独立效果

**覆盖文件与交界**：`global/dimension/{nether,nether_volume,nether_colored_light,nether_reflection,end,end_system,end_geometry(1-90 行布局与共用基),end_blackhole,end_kerr,end_disc_profile}.glsl`、`lib/{nether_voxel_grid,nether_fog_density,nether_reflection_metadata,end_light,end_surface,end_star_catalogue,end_reflection_cache}.glsl`、`program/{nether_light.csh,end_star_rows.csh,end_star_catalogue.csh,end_illumination.fsh,end_sky_buffer.fsh,end_reflection_cache.fsh,nether_reflection.fsh,nether_reflection_resolve.fsh}`、`world-1/{shadowcomp..shadowcomp8}.csh`、`world-1/shadow.vsh`、`world1/{setup,setup1,setup2}.csh`、`world1/{composite,deferred,deferred1,prepare,prepare1}.fsh` 与 `world-1/{composite,composite1,composite9}.fsh` 壳、`lib/transforms.glsl` 末地阴影基、`shaders.properties:48-52,65-67,200-225,248-254,365-380,808-861`。交界：`NETHER_VOXEL_LIGHT` 门控的 image 声明 ↔ 九步 shadowcomp 链 ↔ 接收端采样器；colortex9 在末地作天空生产、在下界作反射载波的复用；colortex11 在主世界是天空环境、在末地由 `world1/prepare1.fsh`→`end_reflection_cache.fsh` 写反射。

**覆盖结果**

未发现可证实的实现缺陷。核对到的关键契约：

- 下界体素光链闭合：`program/nether_light.csh` 以 `ASTRA_LIGHT_STEP` 0..8 分支（由 `world-1/shadowcomp{,1..8}.csh` 设定），step0 用 `imageAtomicOr` 建 16 格源活动位图到 `astraNetherSourceTiles`（2×1 r32ui，`shaders.properties:858`，clear=true），step>0 用 `astra_nether_group_has_source`（字 (0,0) 与 (1,0) 覆盖 64 位对 64 个 tile）门控，A/B 按奇偶乒乓，最终 step8（偶）写 `astraLightA`，而接收端 `global/dimension/nether_colored_light.glsl:8,23` 只采样 `astraLightA`。image 声明与消费者共用同一 `#if defined SHADOWS && defined NETHER_VOXEL_LIGHT && BLOCKLIGHT_STRENGTH > 0`（`shaders.properties:827,854`），关选项时既无派发也无采样；4 个 image 不超过宿主 15 上限（851-853 行）。`shaders.properties:819-824` 记录的"只有 `program.*` 接受维度命名空间、旧 `compute.world-1/...` 拼写无人解析"与现行 key 写法一致。
- 附件复用不冲突：`program/nether_reflection.fsh:13-18` 显式 `colortex9Clear = false` 并说明复用原生末地天空目标（该生产者在下面从不运行），与 `world1/composite.fsh`→`end_sky_buffer.fsh` 的维度分工一致；`shaders.properties:223-225` 把 composite9 在主世界与末地关闭、在下界按 `SCREENSPACE_REFLECTIONS` 启用，`world-1/composite9.fsh` 带 `#define DIMENSION_NETHER`。`program/end_reflection_cache.fsh:1,10` 声明末地拥有 colortex11 且格式为 RGBA16F，与主世界的 R11F_G11F_B10F 不同但按维度分开编译，互不干扰；`lib/end_reflection_cache.glsl:25-47` 用 `textureSize` 自适应，不假设主世界尺寸。
  同一逻辑也覆盖下界的 colortex28：`program/nether_reflection.fsh:15-18` 以 RGBA16F 加 `clear=false` 使用它作反射元数据，而主世界 `program/lit.fsh:22-24` 以 RG32F 加 `clear=true` 使用它作身体记录；两者的声明都在各自维度内，消费者（`program/water.glsl:17` 与 `program/nether_reflection.fsh:10`）也各自按维度分支，未发现把另一种编码当自己编码读的路径。
- 末地布局与时间基：`global/dimension/end_geometry.glsl:26-38` 的 colortex8 槽位表（0 食、1..73 体记录、74 环轴、75..293 基缓存、294..314 形状、315 星场旋转）与 `shaders.properties:48` 的 `size.buffer.colortex8=316 1` 一致；`end_cycle_seconds`（41-45 行）只用 `worldDay`/`worldTime`，不用 `frameTimeCounter` 或宿主时钟，符合其注释约定；`program/end_illumination.fsh` 的 74 号体环轴与 0 号槽的 32 采样盘通量、7 个缓存岛食与上述布局配对。

**P2（星表容量余量与行数约束）** 见模块 1 的复算：391,670 对 393,216，余量约 4 行。本模块补一条：`program/end_star_rows.csh:7,10` 的 `local_size_x=64` 与 `workGroups=ivec3(1,1,1)` 加每 lane 8 行正好覆盖 512 行；若 `END_STAR_ROWS` 改成 64 的非整数倍会直接漏掉尾部行，当前无缺口，属约束。

**P2（下界反射的档位退化）** `program/nether_reflection.fsh:39-41` 在 `WATER_EFFECT_QUALITY < 2` 时只用 2×2 接收者格点，由 `program/nether_reflection_resolve.fsh:18-50` 跨匹配面还原，后者在 `WATER_EFFECT_QUALITY == 2` 时用不同 stride（38-40 行）。BALANCED 的 `WATER_EFFECT_QUALITY=1`（`shaders.properties:566`）因此走格点路径，粗糙岩石反射比最高档更颗粒化；`nether_rock_fresnel` 的 0.35 因子（`global/dimension/nether_reflection.glsl:8-23`）是为扩大斜射角而做的调整，属已记录的观感决定。

**疑点与缺失事实**：`end_kerr.glsl`、`end_blackhole.glsl`、`end_system.glsl`、`end_disc_profile.glsl` 的函数清单我全部读过并核对了调用者，但未逐条核对每个光子轨道阶次与频移近似的标定值；`global/dimension/end.glsl` 的着色合成分支、`lib/end_surface.glsl`、`program/end_sky_buffer.fsh` 与 `end_illumination.fsh` 只读了接口与槽位表段。下界与末地的 `gbuffers_*` 与合成壳已全部枚举并核对为薄壳（见模块 1），不构成缺口。若主代理需要末地或下界的视觉回归结论，需要额外画面事实。`astraEndTransfer*` 与 `astraEndFlow*` 图像内容本身未打开验证。

---

## 模块 9：选项档位 / 开关组合 / 性能热点 / 文档与现行源码不一致

**覆盖文件与交界**：`lib/settings.glsl`（749 行全部）、`shaders.properties` 的 screen（541-549、865-888）、profile（553-567）、sliders（572）、全篇 `#if` 条件、`lang/{en_US,zh_CN}.lang`（各 421 行）、`gbuffers_*.fsh` 壳与 `entity/item/block.properties`、`docs/当前工作.md`（全部）、`docs/实现与限制.md`（重点 20-115）、`README.md` 指向的入口。交界：每个 GUI 选项 ↔ `settings.glsl` 的 `#define` ↔ 至少一个消费者；profile 的值 ↔ `shaders.properties` 的尺寸与程序门控 ↔ GLSL 宏；文档陈述 ↔ 现行源码。核对方式：把全部 `screen.*` 项与 `settings.glsl` 的 `#define`（含 `//#define` 注释态布尔约定）交叉比对；把全部 screen 项与两个 lang 的 `option.` 键交叉比对。

**发现的问题**

**P1（ULTRA 的水下光束采样数是死值）** `shaders.properties:567` ULTRA 设 `UNDERWATER_SHAFT_SAMPLES=10`，而 `global/water/light_shafts.glsl:21-25` 在 `ASTRA_OVERWORLD_OPTIMIZED`（`lib/settings.glsl:352-354`，即 `OVERWORLD_BUDGET>0`）且值不小于 7 时把宏钉为 7；四个 profile 全部 `OVERWORLD_BUDGET=1`（`shaders.properties:564-567`）。错误结果：ULTRA 与 BALANCED 的该项在出厂配置下渲染结果完全相同，用户在最高档看到的束密度与均衡档无差别（正是模块 5 的现象）。修复取向二选一：让采样上限随 `WATER_EFFECT_QUALITY` 放开，或把 `OVERWORLD_BUDGET` 与 ULTRA 解耦。

**P1（出厂任何档位都没有时域抗锯齿）** `shaders.properties:564-567`：PERFORMANCE 与 NO_SHADOWS `ANTIALIASING=0`，BALANCED 与 ULTRA `ANTIALIASING=1`；`lib/settings.glsl:713-715` 要求 `ANTIALIASING == 2` 才定义 `ASTRA_TAA`。错误结果：`program/taa_resolve.fsh`、`program/taa_state.fsh` 与 colortex15/16/17/22 整条时域链在出厂档位从不运行（`shaders.properties:100-120` 相应把尺寸缩到 `1 1` 并禁用 composite6/7，这部分自洽），因此阴影细边、植被细线与薄云边缘只剩 FXAA 一档，而 FXAA 对几何边缘无效。它与模块 2 的 P1 以及 W07/W13 的"无可感区别"反馈直接相关。取向：若这不是刻意决定，把 ULTRA 改为 `ANTIALIASING=2` 并评估新增两个全屏 pass 的成本；若是刻意决定，在 `docs/实现与限制.md` 显式写明出厂档位无时域滤波、锯齿只能靠柔化与抖动抑制。

**P2（PERFORMANCE 与 NO_SHADOWS 档内的冗余组合）** `shaders.properties:564` 在开 `UNDERWATER_LIGHT_SHAFTS` 的同时设 `UNDERWATER_SHAFT_SAMPLES=4`，`shaders.properties:19-23` 依此把光束附件缩到 0.25 尺寸；`shaders.properties:565` 则同时写 `!SHADOWS` 与 `SHADOW_SOFTNESS=2`、`COLORED_SHADOWS`、`SHADOW_DISTANCE=192`，这些在阴影关闭时无效（该档也正确写了 `!UNDERWATER_LIGHT_SHAFTS`）。四个 profile 一致地保留关闭选项的数值（`!SCREENSPACE_AO` 配 `AO_STRENGTH=75`），属可读性而非错误。PERFORMANCE 是四档里唯一"阴影开但光束仍走 4 区间"的组合，同一附件尺寸与宏在不同档位含义变化较大，建议在文档给一张"档位实际生效值"表，把被宏裁掉的值标注为无效。

**P2（选项与标签覆盖完整性，核对通过）** 每个 `screen.*` 项都在 `lib/settings.glsl` 有对应 `#define`（或 37、39、116、146、169、204、227、246、250、257、343 行的注释态布尔约定），唯一例外 `sunPathRotation` 是宿主内建 uniform，正确；161 个 `option.` 键在 `lang/en_US.lang` 与 `lang/zh_CN.lang` 中一一对应，无缺失、无多余；`sliders=`（`shaders.properties:572`）覆盖全部滑条型选项，含 78 个颜色分量与 `PURKINJE_STRENGTH`；嵌套 screen（COLORS→SKY_COLORS→DAY_COLORS 等）闭环，没有指向不存在屏幕的 `[X]`。

**P2（文档与源码口径清单，定位到行；第 2 项是我先前的误判，已撤回）**

1. `docs/实现与限制.md:29` 与 `global/water/raytrace.glsl:28-37` 注释都写"32 格内 16 粗 加 4 细化 = 20"，但 263-264 行对空气侧水面在所有距离额外加 `min(..., 12)`（模块 4 的 P1）。
2. （本轮撤回，经复算确认不是冲突）`docs/当前工作.md` W03 的"增加约 5.33 MiB"与 `docs/实现与限制.md:70` 的"约 10.67 MiB 而非 5.33 MiB"不是矛盾：前者是相对 RG16F 的增量、后者是 RGBA16F 总量，复算同时成立（模块 5）。需要修的只是 `docs/实现与限制.md:70` 的措辞，让"而非 5.33"不被读成否定增量。
3. `docs/当前工作.md:22` 以"读到上一代 mip"为理由拒绝"mip 移到生产者"，与本地 `CompositeRenderer.txt` 取证不符（模块 1）。
4. `global/dimension/overworld.glsl:42-43` 的反射排除日月说法与实际包含 glare 瓣不符（模块 6）。
5. `docs/实现与限制.md:66` 的"至多 28 个遮挡点及 224 个波纹读取"与当前实现仍数值相符（7 区间 × 4 节点 × 8 波面点），但现在是不上限而非典型值，因为 `ASTRA_SHAFT_SAMPLES` 被裁到 7；`docs/当前工作.md` W03 那句"取消每段最多 224 次重复碰撞计算"指的是源图缓存后不再逐样点重算碰撞。表述容易误读，数字本身不是错的。

**性能热点（只描述源码结构，不给 FPS）** 结构性开销位置：全分辨率 colortex28 记录（`shaders.properties:200`）与两处 blend 覆盖；1024² 源图含 mip 链（206-212 行）；光束 march 的 7 区间 × 4 节点阴影查询上限（`global/water/light_shafts.glsl:187-219`，每节点一次 `shadow_gather_visibility_inside` 加一次 `shadowcolor0` 四角采集）；`CLOUD_QUALITY=2` 时 8-96 采样的平面云 march（`global/atmosphere/clouds_planar.glsl:276-277`）与 257² 天空表、1.0 云附件（`shaders.properties:75-76,87-88`）；`WATER_EFFECT_QUALITY=2` 时 9 组反射足迹（`program/water.glsl:357-358`）；`program/water.glsl:733` 与表生成（`program/sky_reflection_cache.fsh:22`）在同帧各跑一次云 march；末地 colortex9 原生尺寸解析（`shaders.properties:49-52`）。这些只是开销所在的结构位置；没有整帧数据就不能推断 1080p/144 FPS 是否达标，也不应引用任何 ms 数字。`docs/当前工作.md` 的 67/90/100 是用户场景读数且条件不完整，不能用于分项归因。

**疑点与缺失事实**：`Astra/README.md` 与 `Astra/THIRD-PARTY.md` 我只确认存在与出现在本轮改动清单中，未逐条核对来源声明与现行文件头 provenance 注释是否一致；`entity.properties`/`item.properties`/`block.properties` 的具体条目语义未逐条核对；lang 的 `screen.*` 分组标题键我确认数量一致但未逐条读文案。

---

## 严重问题摘要

P0：无。本轮未发现会导致编译失败、黑屏、维度不可用或数据损坏的可证实缺陷。

P1 七条标签、六类问题（模块 9 的两条档位失效同源，合并叙述）：模块 2 的阴影锯齿原因集合（出厂无时域滤波 加 penumbra 展宽过弱）；模块 4 的近场反射粗查询被裁到 12（与文档口径矛盾，直接削弱 W14）；模块 4 的默认档反射足迹退化为单点；模块 5 的光束少且挤的五条原因集合；模块 5 的水下圆形太阳来自反射表的解析 glare 瓣与新增方形 sprite 叠加；模块 9 的两条档位失效（ULTRA `UNDERWATER_SHAFT_SAMPLES=10` 被宏裁掉；四档均无 `ASTRA_TAA`，与模块 2 同源）。

P2：mip 时序的文档前提与宿主取证不符；源图内存口径的措辞（5.33 为增量、10.67 为总量，我先前误判为冲突已撤回）；末地星表容量余量与行数约束；`global/water/temporal.glsl` 死文件语义冲突；反射排除说明与实际不符；云柱单点近似；显示域水下不对称；下界反射格点退化；profile 冗余组合与文档口径清单五条（模块 9），其中源图内存一条经复算确认不是冲突、只余措辞问题。

## 未覆盖清单（如实）

- `world-1/` 与 `world1/` 的 `gbuffers_*` 与合成壳已全部枚举并核对为薄壳（`#version` + `#define DIMENSION_*` + 单一 include，指向已审的 `program/` 入口），这一项不再是缺口；仍缺的是这些入口在维度宏下的实际画面表现。
- `global/dimension/end.glsl` 的着色合成分支、`lib/end_surface.glsl`、`program/end_sky_buffer.fsh` 与 `end_illumination.fsh` 的完整实现（后者只读接口与槽位表）、`end_kerr.glsl`/`end_blackhole.glsl`/`end_system.glsl` 内部每个近似的数值标定。
- `global/post/end_sky_tonemap.glsl`；`lib/tonemap.glsl` 中四个算子的逐条数值；`global/post/bloom.glsl` 与 `godrays.glsl` 的每个滤波系数。
- `global/water/particles.glsl` 的粒子外观分支细节与 `lib/water_palette.glsl` 的全部调色条目。
- `world-1/shadow.fsh`、`world1/shadow.fsh`、`program/clouds.fsh`（vanilla 云直通，平面云与下界末地 discard 避免二次绘制）与根 `shadow_solid.{fsh,vsh}` 的投射排除条件我已补读；未追的是 Sodium/Oculus 在 SOLID alpha 关断下把哪一类模型路由到 `shadow_solid`，那属于宿主行为而非包内代码。
- `Astra/README.md`、`Astra/THIRD-PARTY.md` 的逐条来源核对；`entity/item/block.properties` 的逐条材质语义；`lang` 的逐条文案。
- 末地 `astraEndTransfer*` / `astraEndFlow*` 图像内容本身。
- 未启动游戏、未做任何整帧测量；因此实际游戏画面是否已改善、整帧性能是否达标，对本报告所有条目都是缺失事实，我没有把源码推断或独立呈现写成游戏内已解决。
