# lymboshader 性能调研（第四批 batch4 · 只读）

> 日期：2026-10-03。范围：只读调研，未改动任何参考包或 Astra 源码。
> 路径约定：本文 file:line 相对 `reference_shaderpacks/lymboshader/`（该包 shader 根在 `shaders/` 子目录；下文无前缀路径均相对包根）。Astra 侧相对 `Astra/shaders/`（写 `A:`）。
> 去重基线：已读 `shader_research/SUMMARY.md`、`SUMMARY-batch2.md`、`SUMMARY-batch3.md`、`docs/2026-10-02-shader-reference-performance.md`、`docs/2026-10-03-batch3-selected-optimizations.md`；其中列过的借鉴点一律不计为新颖点。
> 版本/下载量（Modrinth v1.2、95,834）来自任务简报；包内无 pack.json/Modrinth 元数据，代码头自称「v2」（`shaders/final.fsh:8`），版本只能以任务简报为准（见备注）。

## 概况

- 定位：极简「原版观感」包，只有地形 gbuffers + final 两条自有管线，无阴影/反射/云/天气等子系统；readme 自述「想改什么就直接开 final.fsh」（`readme.txt:10-11`）。
- 血统：无独立 README/版权头，仅 `readme.txt:7` 署名 DorNell8；全包无第三方致谢、无与已研究 62 包相同代码头或模板痕迹（文件量过小亦难深比对），按自研极简处理。
- 许可：**包内无 LICENSE 文件**（整包仅 `readme.txt` + `shaders/`）；`readme.txt:10-11` 只有非正式「可以随便改」表述，未授予再分发/署名条款 → 按默认「保留所有权利」最保守处理，仅思路级。
- 规模：整包 7 文件；`shaders/` 6 文件共 204 行，其中代码 4 文件 166 行（`final.fsh` 133、`gbuffers_terrain.fsh` 15、`gbuffers_terrain.vsh` 11、`final.vsh` 7——与任务简报 166 行口径一致），另有 `shaders.properties` 7 行、`lang/en_US.lang` 31 行、包根 `readme.txt` 15 行。无 world-1/world1 目录（下界/末地沿用主世界程序），无非 shaders/ 代码目录。

## 管线与调度

- program 清单：`gbuffers_terrain`（fsh+vsh）、`final`（fsh+vsh），共 2 个自有程序。**没有** shadow、gbuffers_water/entities/weather/clouds/hand/sky*、deferred、composite、compute 等任何其它程序。
- 调度：`shaders.properties:1-8` 只有 3 个 screen 分组（BLUR/NOISE/FOG）+ 5 个滑块；**没有** `program.*.enabled`、`size.buffer.*`、profile、buffer 格式声明、`shadow.culling` 等调度/资源声明。质量全靠 `shaders.properties:3-5` 的 define 开关重编译。
- 缓冲：`gbuffers_terrain.fsh:14-15` 仅写 `DRAWBUFFERS:0`（albedo×glcolor×lightmap 的 LDR 值）；`final.fsh:102` 读 colortex0、`:118` 读 depthtex0，输出到显示缓冲（`:132`）。无 HDR、无 mip、无历史/中间缓冲。
- 无阴影图、无 deferred 光照阶段；全部「效果」集中在 final 一个全屏 pass（`:100-133`）。

## 分模块性能手法清单

### 调度与阶段启停
- `shaders.properties:1-8` — 无 program 启停/无 size.buffer/无 profile；低配的唯一手段是改 define 重编译。
- `final.fsh:13-20` — BLUR/NOISE/FOG 各只有一个编译期总开关（`BLUR_ENABLED`/`NOISE_ENABLED`/`FOG_ENABLED`）；开关关掉并不省掉对应采样（见反面印证 4）。

### 地形光照与阴影
- `gbuffers_terrain.fsh:10-15` — 全部「光照」= 顶点色 × 贴图 × lightmap 一次采样，写单缓冲；无阴影、无 AO、无天空光法线、无雾。
- `gbuffers_terrain.vsh:7-11` — 顶点只做 `ftransform` + 传 texcoord/lmcoord/glcolor，无任何光照/雾/波动计算。
- 无 shadow 程序、无 shadowtex 读取、无 PCF/SS 阴影；无 AO/接触遮蔽程序。

### 云
- 无 gbuffers_clouds 程序 → 云由原版几何/纹理渲染，shader 侧零成本；同时无自定义云色/云影/云预算。

### 雾与大气
- `final.fsh:118-125` — 雾 = `pow(depthtex0/1.001, 34)` → clamp → mix 到常数 `FOG_COLOR`；单次深度采样 + 单次 pow，**不线性化深度**（把非线性深度值直接当指数底做距离近似）。
- `final.fsh:120-121` — FOG_ENABLED 关闭时 fog 置 0，但 `:118` 的 depthtex0 采样已发生（编译期未能剪掉）。
- 无天空盒自定义、无大气散射、无体积雾。

### 水与水下
- 无 gbuffers_water 程序 → 无波浪/反射/折射；`final.fsh:127-130` 的 isEyeInWater 分支已被注释成 `//dont works kekw`。
- 水面几何由 `gbuffers_terrain.fsh:10-15` 一并渲染，只做贴图×lightmap，零附加成本。

### 粒子·实体·天气
- 无 gbuffers_entities/weather/textured/hand 等程序 → 这些几何沿用原版固定管线；本包只覆盖地形块。

### 后处理与缓冲内存
- `final.fsh:100-116` — 链：取 colortex0 → 转灰度 `dot(color, 1/3)`（`:103`）→ 帧时间噪声乘子（`:110-112`）→ 灰度高斯「bloom」（`:114`）→ 加回。
- `final.fsh:61-95` — 「bloom」为 25×25 不可分离高斯：核/权重片元内用 `normpdf` 现算（`:70-78`），双循环每像素 625 次 `texture(colortex0, ...)`（`:80-89`）。
- 全链 1 张全屏 LDR 缓冲 + depthtex0；无 mip、无历史、无 HDR、无独立分辨率缓冲。

## 反面印证

1. **final 内每像素 625-tap 不可分离高斯**（`final.fsh:61-95`，采样循环 `:80-89`）：单点 625 次纹理采样，是本包最大的固定开销；且 `#ifdef BLUR_ENABLED` 只决定返回值，未定义时仍跑满 625 次后才 `return vec4(0.0)`（`:90-94`）。与任务简报「没有垃圾代码」的定位相反。
2. **帧时间驱动的全屏 sin-hash 噪声**（`final.fsh:42-54` 定义，`:111` 使用）：每帧变化的乘性噪点，省不下什么，反而是画面噪点源。
3. **无 program/缓冲级调度**：无 `program.*.enabled`、无 `size.buffer.*`、无 profile、无 buffer 格式声明（`shaders.properties:1-8`）；对比 Astra 已有的阶段启停 + size.buffer 分档 + 关闭时资源缩编（`A:shaders.properties:18-95`、`A:shaders.properties:476-479`），本包低配路径只能整体重编译。
4. **「关了还付钱」**：FOG 关闭仍付 depthtex0 采样（`final.fsh:118` 在 `#ifndef` 之前）；BLUR 关闭仍付 625 次采样（`:90-94`）。
5. **「极简」= 不实现功能，而非优化实现**：无阴影/AO/云/水/天气子系统，画面接近原版；性能优势不可作为 Astra 削减依据（同 batch3 VanillAA/YoFPS 的「做减法」结论，`SUMMARY-batch3.md:159,285`）。
6. **非线性深度幂当雾用**（`final.fsh:123`）：`pow(depth, 34)` 只是把深度曲线放大成像雾，不具距离/介质语义，Astra 的 `A:global/atmosphere/fog.glsl` 不可照此简化。

## 新颖借鉴点

**无（A=0 / B=0 / C=0）。** 逐项核对结论：包内可辨识的机制只分三类——（i）比 Astra 少的子系统（不构成手法）、（ii）已被五份材料列为已实现/已列的常规项、（iii）反面对照。

- 去重排除：
  - 顶点/片元直通 + lightmap 光照（`gbuffers_terrain.fsh:10-15`）→ 属功能子集，不是优化机制。
  - 单 pass 后处理（`final.fsh`）→ batch3 §2.4 已就 YoFPS「单 pass 合并」判「不学」（`SUMMARY-batch3.md:118`）；Astra 阶段分档更细。
  - 灰度高斯「bloom」→ Astra 已实现 Bloom 0.25 捕获 + mip 链 + tap 分档；本包是更贵更差的同类，无借鉴。
  - 深度幂雾 → 与 Astra 多层雾模型（`A:global/atmosphere/fog.glsl`）相比属功能子集。
  - 帧时间噪声/雾 → Astra 已做帧不变量 CPU 化（任务简报已实现项）；本包并未预计算。
- 由于没有候选条目进入 A/B/C，无需对候选再作未实现 grep；对「bloom/fog」两族的 Astra 侧核对结论即为上表。

## 无法判定项

- **版本口径不符**：任务简报为 Modrinth v1.2，包内唯一版本线索是 `shaders/final.fsh:8` 的「v2 - added a fog」；无 pack.json/元数据可仲裁（下载量 95,834 亦无法本地复核）。
- **readme 的许可含义**：`readme.txt:10-11` 只表态允许修改，未涉再分发/署名；能否视为代码级借鉴许可无法从包内判定，本报告按最保守（仅思路级）处理。
- **625-tap 循环的编译器/驱动行为**：常量核 + 常量偏移在 GLSL 语义下仍是 625 次独立采样，但驱动是否做变换无法离线判定；报告按源码字面成本计。
