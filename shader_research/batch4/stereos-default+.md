# stereos-default+ v2.4 性能调研（第四批 batch4 · 只读）

> 日期：2026-10-03。范围：只读调研，未改动任何参考包或 Astra。
> 路径约定：本文 file:line 相对 `reference_shaderpacks/stereos-default+/shaders/`（仅该目录）;Astra 侧相对 `Astra/shaders/`（写 `A:`）。
> 去重基线：已读 `shader_research/SUMMARY.md`、`SUMMARY-batch2.md`、`SUMMARY-batch3.md`、`docs/2026-10-02-shader-reference-performance.md`、`docs/2026-10-03-batch3-selected-optimizations.md`；其中列过的借鉴点一律不计为新颖点。
> 版本/下载量（v2.4、404,156）来自任务简报；包内无 pack.json/README，未能本地复核。

## 概况

- 定位：原版+风格向极简光影，卖点是阴影、水面与岩浆顶点波动；除 `composite` 一次光照合成外没有自定义大气/水/云/后处理（README 缺失，定位按任务简报与代码事实描述）。
- 血统：4 个天空文件明示取自 XorDev's "Default Shaderpack" 模板（`gbuffers_skybasic.fsh:1-7`、`gbuffers_skybasic.vsh:1-7`、`gbuffers_skytextured.fsh:1-7`、`gbuffers_skytextured.vsh:1-7`），其余为 OptiFine 时代自研极简代码；未发现与已调研 62 包同源（无 BSL/Complementary/Bliss 代码头或文件布局）。与 batch3 的 VanillAA/YoFPS 同属「原版向」，但无 BSL TAA/Chocapic 抖动痕迹。
- 许可：包内无 LICENSE/README（全包 `find -iname "*licen*"/"*readme*"` 无命中）；除上述 4 个天空文件带 XorDev 公共模板声明（「You can do whatever you want with this code! Credit is not necessary」，`gbuffers_skybasic.fsh:2-4`）外，其余文件无版权声明 → 按默认「保留所有权利」处理，只可思路级借鉴、代码不可搬；Modrinth 索引许可未在本地核实（见备注）。
- 规模：64 文件（全部位于 `shaders/`，含 lang/block.properties）；代码文件 17 个 `.fsh/.vsh/.glsl`，共 1,359 行。维度树：包根（主世界默认）+ `world-1/`（下界）+ `world1/`（末地）+ `world7/`（仅 1 组 textured 程序）。

## 管线与调度

- program 清单（包根，主世界默认）：`shadow`、`composite`、`final`、`gbuffers_terrain/textured/entities/basic/skybasic/skytextured/spidereyes/armor_glint`。**没有** `deferred*`、`gbuffers_water`、`gbuffers_weather`、`gbuffers_hand`、`gbuffers_clouds`、Bloom/TAA/SSR 程序；`world-1/` 增加 `gbuffers_hand`，`world1/` 增加 `gbuffers_hand/armor_glint`，`world7/` 仅 `gbuffers_textured`。
- 调度与开关：`shaders.properties:1-12` 只有 4 个滑块与 3 个 screen 分组，**没有任何** `program.*.enabled`、`size.buffer.*`、profile 或 buffer 格式声明；质量全部由 shader 内 `#define ... //[值列表]` 承担（`composite.fsh:3-5`、`gbuffers_terrain.vsh:3-5`）。
- 缓冲：仅 colortex0/1/2（`gbuffers_terrain.fsh:14-17` 的 `DRAWBUFFERS:012`，分别存 albedo、法线、光图），`composite.fsh:39-43` 的格式声明整段被注释（实际格式交给 Iris 默认）。无独立分辨率缓冲、无历史缓冲。
- 阴影：`shadow.fsh:10` 单采样输出 casters；`composite.fsh:102-124` 在屏幕空间重建阴影坐标并做 (2N+1)² 旋转核 PCF，N=1..5（`composite.fsh:3`）→ 9~121 tap；默认影图 4096（`composite.fsh:4`，滑块 256..4096）。
- 维度定制：`world-1/composite.fsh:84-92` 与 `world1/composite.fsh:84-92` 编译期删除了 `Visibility/TransparentShadow/getShadow` 全部函数与调用，只留 `lightmap + Ambient` 常数环境光（下界 Ambient=0.05、末地 0.025）；`world1/gbuffers_terrain.fsh` 删除水下染色分支。`shadow` 程序在所有维度仍存在（下界 shadow.vsh 仍按 `mc_Entity.x == Lava` 位移，`world-1/gbuffers_terrain.vsh:45-51`）。

## 分模块性能手法清单

### 调度与阶段启停
- `shaders.properties:4-5,12` — 阴影采样数与影图分辨率是唯二性能滑块；无阶段级启停（对比 Astra 已实现：`A:shaders.properties:88-167` 的 program 启停、`A:shaders.properties:18-145` 的 size.buffer 分档）。
- `composite.fsh:50-51` — `ShadowSamplesPerSize/TotalSamples` 由滑块常量推导循环上界，编译期展开固定 tap 数。
- `world-1/composite.fsh:84-92`、`world1/composite.fsh:84-92` — 维度定制程序：下界/末地整段去掉阴影采样（0 次 shadowtex/shadowcolor 查询）。

### 地形光照与阴影
- `composite.fsh:129-134` — `Depth == 1.0` 天空像素直接写 `albedo^1.9` 返回，跳过光图/法线/阴影。
- `composite.fsh:90-100` — 每次阴影采样对 `shadowtex0`、`shadowtex1` 各做一次深度比较并读 `shadowcolor0.rgb`，无「先判遮挡再读彩色」门控。
- `composite.fsh:102-124` — 4 角点（`floor` 到纹素 + `subpixel` 权重）双线性重建得到基础可见度；`composite.fsh:110-113` 用 noisetex 每像素取旋转角、构造旋转核 `mat2(...)/shadowMapResolution`；`composite.fsh:115-121` 双层循环累积 vec3（彩色阴影同核平均）。
- `composite.fsh:138-152` — `NdotL=max(dot(N,L),0)`，雨天 (`rainStrength>0.1`) 把 NdotL 向 0.05 混合、夜间时段（worldTime 12700~23500）压到 0.005。
- `gbuffers_terrain.fsh:14-17` — 法线与光图经 varying 直接写入 colortex1/2（顶点已算好，片元零解码）。
- `shadow.vsh:8-13` — 阴影投影顶点级畸变（`distort.glsl:1-4` 的 `length` 缩放），与 composite 端同一函数配对。

### 云
- 无云程序（无 `gbuffers_clouds`），云由原版渲染，shader 侧零成本；同时也没有任何自定义云外观/云影。

### 雾与大气
- 无自定义雾：地形/实体/水程序不写雾，仅天空程序使用原版固定管线 `gl_Fog`（`gbuffers_skybasic.fsh:24-28`，`gl_FogFragCoord` 在 `gbuffers_skybasic.vsh:26` 由 `length(pos)` 写入）。这是「不实现」而非「优化实现」。

### 水与水下
- `gbuffers_terrain.vsh:39-52` — 水/岩浆顶点波动：两条 `sin` 叠加，`WaveDisplacement = clamp(Waves, -FractY, 1.0-FractY)` 夹在方块空间内（`FractY = fract(vworldpos.y+0.001)`），再按 `WaveAmount` 位移 `vpos.y`。
- `world-1/gbuffers_terrain.vsh:45-51` — 下界只对岩浆做波动，且加 `worldPos.y <= 31.99` 高度门（只动岩浆海表面）。
- `gbuffers_terrain.fsh:19-25` — 水下/岩浆内视时对 albedo 做固定混合染色（`mix(vec3(0.2,0.3,0.5), albedo, 0.25)` 等）；无折射、无反射、无吸收、无焦散。

### 粒子·实体·天气
- `gbuffers_textured.fsh:11-17`、`gbuffers_entities.fsh:11-17`、`gbuffers_basic.fsh:11-17` — 与地形同一三目标写出，无额外分支。
- 无 `gbuffers_weather` 程序 → 雨雪按原版渲染，shader 零成本。
- `gbuffers_spidereyes.fsh:8-12`、`gbuffers_armor_glint.fsh:10-15` — 直接输出 gcolor，不参与光照。

### 后处理与缓冲内存
- `final.fsh:7-9` — 单次 `pow(1/2.2)` 输出；无 Bloom/TAA/曝光/FXAA/调色。
- 全链 3 张全屏缓冲 + 1 张阴影图；无任何历史/临时缓冲，无 mip。

## 反面印证

1. **每 tap 无条件读三条阴影纹理**（`composite.fsh:94-100`）：高档 11×11=121 次采样 × (shadowtex0+shadowtex1+shadowcolor0) ≈ 363 次纹理读/像素，且彩色阴影没有「先判不透明遮挡」；比 Astra 的「配对四角核 + 覆盖早退 + 仅遮挡时读 shadowcolor0」（`A:global/lighting/diffuse.glsl`、`A:global/lighting/shadowmap.glsl`）贵一个量级，不学。
2. **雨天重复调用 getShadow**（`composite.fsh:139-146`）：先算 `Diffuse`（内部一次完整核循环），雨天分支再把 NdotL 混合后又调用一次 `getShadow` 重算，正常路径每像素至少多一轮全核采样。
3. **时段硬编码的夜间灯光替换**（`composite.fsh:143-151`）：`worldTime` 落入夜间就把 NdotL 压到 0.005，相当于夜间阴影静默消失；这是画质妥协，不是性能机制，不作为借鉴。
4. **无 program/资源级调度**：没有 `program.*.enabled`、没有关闭阴影时缩缓冲、没有 profile；低配只能全局降采样数/分辨率。与 Astra 已实现的「阶段启停 + size.buffer 分档 + 关闭时资源缩编」纪律相反（`A:shaders.properties:18-167`）。
5. **地形无雾**：不写雾不是优化取舍，而是功能缺失（把「少写代码」当省性能）；Astra 的前向雾是需求项，不能照此裁。

## 新颖借鉴点

**无（A=0 / B=0 / C=0）。** 全包可提炼的手法都能落入下面三类，故不凑数：

- 已列/同构（去重排除）：顶点水波夹进方块空间 → batch2 §②-2 已列（tea/bvs/sildurs，快赢）；旋转抖动核 → Astra 明确拒绝（`A:global/lighting/diffuse.glsl:270-273`「a stable bilinear footprint needs neither a rotating sample pattern nor temporal antialiasing」）+ batch1 已列；阴影 4 角双线性重建 → batch2 §②-1「软阴影核与偏置解耦」/batch3「阴影 4 角双线性重建」同构；`rainStrength`/夜间 NdotL 混合与天空深度早退 → 与 Astra 的静态阴影兜底、unlit 天空路径等价。
- 维度整段删阴影 → Astra 已有维度独立程序与 shadow fsh 的维度编译分支（`A:program/shadow.fsh:29,45,71`），不构成新手法。
- 天空 `gl_Fog`、单次 gamma final → 属功能缺失/等价实现，无迁移价值。

结论：本包的性能价值是**反面对照**（见上节）而非可排期的借鉴点。

## 无法判定项

- 包内无 LICENSE/README/pack.json：Modrinth 索引登记的许可与版本只能依赖任务简报，未能本地复核（卡点：无离线元数据）。
- 无「接近但不确定是否已列」的手法：`TransparentShadowHardness`（`composite.fsh:98`）用 `(hardness - shadowcolor0.r)` 缩放透射色，属彩色阴影强度塑形；batch2 §②-1「彩色阴影边界/强度塑形」（ushader/eclipse/lumina）已覆盖，判为已列。
