# R6 / T3 屏幕可见云独立时域历史 —— 交接记录

- 状态：代码完成（生产 / 存储 / 重投影 / 消费 / 回退阀 / 文档全部落地；无游戏画面与帧时验证，见第 5 节）
- 认领 / 完成：ZCode 会话，2026-09-27
- 对应父项：T3「实体 / 水 / 云仍未完成」中的云项（R6）；总表 [itt32-initial-implementation](../2026-09-26-itt32-initial-implementation.md) 第 1 节
- 范围声明：**本任务只建立屏幕可见云（colortex12 链）自己的历史**。球面反射环境图（colortex11，`prepare` → clouds_planar 反射板）与世界云影（colortex14，`prepare2` → cloud_shadow_cache）**尚未获得专用时域历史**，不据屏幕云完成宣称所有云数据均已时域处理。

## 1. 现状与问题

- 生产：`Astra/shaders/prepare1.fsh` → `program/cloud_screen.fsh`（半分辨率）→ colortex12 = `vec4(cloud.rgb*cloud.a, cloud.a)`（预乘散射色 + 覆盖率），逐帧全量重算，无任何历史。半分辨率 + IGN 抖动 → 云边闪烁无时域抑制。
- 消费（同帧、prepare1 之后）：
  1. `program/sky.fsh`（gbuffers_skybasic/skytextured）取 `astra_screen_cloud(...).a` 衰减日月盘；
  2. `program/deferred.fsh` 云合成段：地形像素 `astra_screen_cloud(texcoord, ray, opaqueDistance)`（地形入/近云板时走 `clouds_planar.glsl:astra_planar_cloud` 局部步进）、天空像素同函数（1e20 全板）。
- 场景 TAA：deferred 对 `sheet.a>0.001` 的像素置 colortex16 reactive=1，`taa_resolve.fsh` 对 reactive≥0.95 的像素完全拒绝历史 → 云信号不进场景 TAA 历史，云区域每帧全刷新。
- 三张云相邻数据坐标/深度/生产时序互不相同：colortex11 是经纬环境图（prepare，无深度）、colortex12 是屏幕射线云（prepare1，无地形）、colortex14 是世界 XZ 云影（prepare2，无屏幕语义）→ **不共享历史**，本任务不扩大范围。

## 2. 设计（定稿）

### 2.1 代表世界位置（生产侧估计量）

- 定义：**当前列积分的透射权重一阶矩**。现有模型（`clouds_planar.glsl:astra_planar_cloud`）在首个通过存在门（`astra_cloud_existence_gate`）的样本处 `break`，单一命中点即全部可见密度的位置 → 一阶矩解析地退化为**首个命中样本的世界坐标 `tracePos`**（`cameraPosition + nPlayerPos * sampleDistance`）。该点由积分本身产生，不引入第二次步进。
- 实现：`clouds_planar.glsl` 增加 out 参数重载 `astra_planar_cloud(worldDir, maxRayDistance, out representativeWorld)`；原二参/一参入口成为丢弃 out 的薄包装。返回值与原实现逐位一致（唯一新增是在命中 `break` 前记录 `tracePos`），既有语义（密度模型、colortex11/14 相关调用）不变。fallback（若审查否决此改动）：在 cloud_temporal.glsl 用公共门函数复制无着色的门步进，代价是半分辨率空射线最多多 64 次粗噪声查询。
- 退化规则：
  - **空云**（整列未过门 / 射线不穿板 / 水平圆柱裁剪 `break`）：无命中 → `representativeWorld = vec3(0)`，α=0 → 无有效代表位置 → 本帧使用当前云结果（不 blend），历史覆盖率写 0。
  - **厚云**（相机近/入板，区间从 0 起）：命中位于板入口附近 → 代表位置有效，仍为世界坐标，不受相机远近影响。
  - **多段云**（一列穿过多个云胞，中间有缝）：现有模型只积分第一个胞 → 代表位置 = **最近（第一）云胞**的命中点；后续云胞不入代表（与积分语义一致，交接为已知限制）。
- 语义：`representativeWorld` 是世界坐标（云场锚定世界，不随相机）；存储时转为**沿本帧射线距离** `r = length(representativeWorld - cameraPosition)`（射线由纹素 uv 唯一决定，可任意帧重建位置，且避免世界坐标超出 half-float 量程）。

### 2.2 历史布局（新缓冲，索引自 24 起）

| 项 | colortex24（解析输出 + 颜色历史） | colortex25（代表元数据历史） |
|---|---|---|
| 格式 | RGBA16F | RGBA16F |
| 尺寸 | `size.buffer.colortex24=0.5 0.5`（与 12 同栅格） | `size.buffer.colortex25=0.5 0.5` |
| 内容 | rgb = 时域混合后**预乘**云色；a = 时域混合后覆盖率 | r = 代表距离 r；g = 时间戳 `fract(frameTimeCounter/64)*64`；b = viewWidth（视口指纹）；a = 当帧覆盖率（>0 即有效代表） |
| 清屏 | `Clear=false`，ClearColor 0（0 = 空云，首次自然回退当前帧） | 同左 |
| 生产者 | `program/cloud_screen.fsh`（prepare1 槽，`RENDERTARGETS: 12,24,25`） | 同左 |
| 消费者 | `global/atmosphere/clouds_screen.glsl:astra_screen_cloud_sample` → deferred 云合成 + sky.fsh 日月衰减 | 仅 cloud_screen.fsh 自身（翻页读上一帧） |
| 生命周期 | 持久（跨帧历史）；CLOUD_MODE≠1 时缩 1×1、无读写 | 同左 |
| 关闭行为 | `ASTRA_CLOUD_TEMPORAL` 不定义（非平面云，或 `ASTRA_CLOUD_NO_TEMPORAL 1` 手动阀）→ prepare1 只写 colortex12（`RENDERTARGETS: 12`），消费端回读 colortex12，行为与今日一致；尺寸门 `#if CLOUD_MODE == 1`（properties 预处理器只见注册选项，故阀开时缓冲仍按 0.5×0.5 分配但无引用，约 7.9 MiB，仅限手动回退者） | 同左 |

### 2.1b 菜单 / 默认行为（验收 #7）

- **不依赖 TAA** → 验收 #7 的「菜单写明 TAA 依赖」条件分支不触发；功能随 `CLOUD_MODE=1`（平面云）默认启用，TAA 关闭时由本模块自行声明前帧 uniform、自带全局门，正确维护自身状态。
- **无 GUI 行是被迫的**：check_pack #1 选项注册表上限 80，当前已满（81 即 FAIL）；且 shaders.properties 的 `#if` 只解析注册选项，手动宏无法驱动缓冲尺寸门。因此未新增 `CLOUD_TEMPORAL` 选项（曾尝试，#1/#2/#12 三项挂）。
- 回退阀：`lib/settings.glsl` 的 `#define ASTRA_CLOUD_NO_TEMPORAL 0` 改 1 → `ASTRA_CLOUD_TEMPORAL` 不定义，全链编译裁掉，回到未滤波 colortex12 路径。
- 中英 lang 无本任务键（无 GUI 行即无键可写，非遗漏）；README 两处已写明默认行为与无菜单项原因。若统帅决定必须有 GUI 行，需先裁决退役一个既有选项或上调 80 上限。

### 2.3 时域解析（每半分辨率纹素）

写入 colortex24 的值 = `mix(current, history, w)`，**颜色与 alpha 用同一权重、同一 tap（预乘空间双线性）** → 无黑边、无 alpha/color 采样错位。基权 `w = 0.90`（历史占 90%，指数滑动平均）。

**重投影（真实前帧参数，非地形深度、非仅相机旋转）**：
1. 风平移补偿：`astra_modify_trace_pos` 对 z 施加 `-= frameTimeCounter` ⇒ 固定噪声特征满足 `z_world = c + t`，即特征以 **+1 世界单位/秒沿 +z** 平移。前帧特征位置 `P_prev = hitWorld - vec3(0,0,dt)`，dt 来自历史时间戳（64s 回绕修正）。
2. `prevPlayer = P_prev - previousCameraPosition` → `clip = gbufferPreviousProjection * (gbufferPreviousModelView * vec4(prevPlayer,1))` → `uvPrev`。平移 + 旋转 + 投影全用前帧真实矩阵；TAA 关闭时这三个 uniform 由本模块自行声明（`lib/uniforms.glsl` 仅在 ASTRA_TAA 下声明它们），**云历史不依赖 TAA**。
3. 门（任一不过 → w=0，用当前云结果）：
   - `frameCounter <= 1`（启动/重载）；
   - dt ∉ [0, 0.5]s（/time set、大跳帧、维度离开 >0.5s 后回归——期间 prepare1 不运行，时间戳差即为离开时长）；
   - `|gbufferProjection[i] - gbufferPreviousProjection[i]| > 1e-4`（FOV/纵横比/视口改动，同 `taa_state` 判据）；
   - `|meta.b - viewWidth| > 8`（视口指纹第二重）；
   - 当前 α ≤ 0（空云无代表位置——任务明确要求此时用当前结果）；
   - `uvPrev` 越出 [1.5 纹素, 1-1.5 纹素]（屏幕外进入 → 直接采用当前帧，不硬拉历史）；
   - 历史覆盖率 ≤ 0（该处上一帧无云：新建云、覆盖率上调 → 干净浮现）。
4. 变化钳制（不硬拒绝，降低 w）：反预乘后亮度相对变化 `1-smoothstep(0.20,0.80,ΔL/L)`（天气色板/日照变化）；覆盖率相对变化 `1-smoothstep(0.35,0.90,Δα/α)`（天气覆盖突变 → 快速收敛而非拖影）。覆盖率下调的纹素因 α_cur=0 已直接干净收敛，无残留拖尾。
5. **逆一致性检查（评估后弃用，留档）**：曾设计用历史代表距离重建前帧位置再投影回本纹素做一致性校验；因 IGN 抖动使命中点沿射线抖动至多一个步长（近云大区间时角误差可达数十个半分辨率纹素），任何可行容差都既放行抖动又拦不住真实失配——该失配场景（FOV/时间/维度）已被全局门覆盖。历史代表距离仍按存储契约保留（colortex25.r）。

### 2.4 失效条件清单（逐条）

| 条件 | 处理 |
|---|---|
| 相机穿云（进入/穿出云板） | 积分区间从 0 起，命中仍有效；重投影用世界锚定场 + 真实前帧相机，相机运动全量可逆 → 正常 blend；穿出后 α=0 → 干净收敛（2.3 门 5） |
| 云层内地形（地形深度在板内/近板出口） | **消费端不使用历史**：`astra_screen_cloud` 的局部步进分支（`opaqueDistance < interval.y*1.02+4.0`）原样保留，该分支直接 `astra_planar_cloud(ray, opaqueDistance)`，无限远云历史不可能覆盖近处地形 |
| 屏幕外进入 | uvPrev 越界门（2.3 门 7）→ w=0，当前帧直接成立；云入场不等待历史 |
| 天气覆盖突变（rainFactor/CLOUD_COVERAGE 阶跃） | 下调侧 α_cur=0 → 干净收敛；上调侧历史 α_h=0 → w=0；已有云的色板漂移由变化钳制加速刷新（2.3 门 8） |
| 维度切换 | 去 nether/end 期间 prepare1 停用（world-1/world1 门）不写历史；回归后时间戳差 = 离开时长，>0.5s 即拒绝（门 2）。**已知软化**：<0.5s 的快速往返不做硬门，依赖云场世界锚定的天然连续性 + 变化钳制收敛；若实测有残影，接续位置在 cloud_temporal.glsl 门 2 收紧或加维度指纹位 |
| 视口/分辨率变更 | 投影逐列比较（门 3）+ viewWidth 指纹（门 4）双保险 |
| 时间中断（/time set、存档时间跳变、长时间暂停） | 时间戳 64s 回绕差 dt ∉ [0,0.5] → 拒绝（门 2）；暂停 dt=0 视为合法（风位移为 0，重投影仍精确） |
| 历史缓冲被清/首次启用 | ClearColor=0 → 历史 α=0 → 门 8 → 当前帧直通 |

### 2.5 帧内读写顺序（独立链，不读写同纹理同帧值）

```
prepare   → colortex11（不动）
prepare1  → program/cloud_screen.fsh：
            写 colortex12（现行积分，语义不变）
            读 colortex24/colortex25 = 上一帧附件（Iris 缓冲翻页：写入方读自身缓冲
              读到的是 alt/前帧内容，包内既有先例 taa_resolve.fsh↔colortex15；
              不假设读到本帧写入值）
            写 colortex24（本帧解析输出 = 新颜色历史）、colortex25（新代表元数据）
prepare2  → colortex14（不动）
gbuffers  → program/sky.fsh 经 clouds_screen.glsl 读 colortex24.a 衰减日月（跨 pass，同帧值）
deferred  → 云合成段经 clouds_screen.glsl 读 colortex24（地形近板走局部步进，
            不碰历史）；colortex16 reactive 语义不变
composite6/7（场景 TAA）→ 不读云缓冲；云像素因 reactive=1 继续被场景 TAA 拒绝
```

### 2.6 与场景 TAA 的关系

- 场景 TAA 对云区域**维持保守屏蔽**（reactive=1 → 历史权重 0）：不降低、不改 taa_resolve/taa_reactive。云信号因此不会进入场景 TAA 历史，不存在同一云信号的双重积累。
- 云自身的时域稳定性来自 colortex24 独立历史（本任务），与 ANTIALIASING 无关：TAA 关闭时云历史照常维护自己的状态（前帧 uniform 自声明、自带全局门）。

## 3. 资源占用推导

1080p（1920×1080），半分辨率栅格 960×540 = 518,400 纹素：
- colortex24 RGBA16F = 8 B/纹素 → 3.96 MiB（持久）
- colortex25 RGBA16F = 8 B/纹素 → 3.96 MiB（持久）
- 合计 ≈ 7.92 MiB；默认关闭或 CLOUD_MODE≠1 时两缓冲 1×1（≈32 B），pass 内代码被宏裁掉，消费端回 colortex12。
- 当前每帧历史解析开销：每个云网格纹素至多 9 次读取（当前位置 meta 1 次，四个历史角点各 meta / 颜色 1 次）。颜色读取在对应角点通过拒绝条件后执行；历史解析不新增步进或噪声查询，prepare1 的积分本体独立计算。网格随 CLOUD_QUALITY 配置。
- 以上不含驱动开销，无帧时数据。

## 4. 已完成

- 本交接文档（设计先行，随实现更新）。
- `clouds_planar.glsl` out 参数重载（代表位置；返回值逐位不变，两个旧签名成为丢弃 out 的薄包装）。
- `global/atmosphere/cloud_temporal.glsl`（历史解析模块：缓冲登记、前帧 uniform 自声明、重投影、门与钳制、混合）。
- `cloud_screen.fsh` 三目标写入（条件 RENDERTARGETS 12 / 12,24,25）。
- `clouds_screen.glsl` 消费端切换（colortex12 ↔ colortex24；deferred.fsh 与 sky.fsh 的四个调用点自动继承，**这两个消费文件零改动**）。
- `settings.glsl`：`ASTRA_CLOUD_NO_TEMPORAL` 手动回退阀 + `ASTRA_CLOUD_TEMPORAL` 宏（settings.glsl:112、414-415）。
- `shaders.properties`：colortex24/25 条件尺寸门（:130-141）。
- README 两处（大气功能行、实现状态与边界行）；lang 无键可写（见 2.1b）。
- 编译与检查验证（第 7 节）。

## 5. 未完成 / 风险

- **无游戏画面、无帧时数据**（qa 无主世界离线出图能力，与全仓声明一致）。基权 0.90、亮度钳制 (0.20,0.80)、覆盖率钳制 (0.35,0.90)、时间窗 [0,0.5]s 均为源码推导初值，需实机 A/B；标定落点 `cloud_temporal.glsl` 常量区。
- 功能**默认随平面云启用**（GUI 行被注册表 80 上限挡住，见 2.1b）：未验证的时域链直接进入默认画面是最大风险；所有门失败均回退当前帧，但正常路径的混合观感未经确认。
- 手动回退阀开启时 colortex24/25 仍按 0.5×0.5 分配（约 7.9 MiB 无引用浪费）；仅影响手动改 settings 的用户。
- 维度 <0.5s 快速往返无硬门（2.4 表「维度切换」行）；逆一致性检查弃用的理由见 2.3 末。
- 球面反射云（colortex11）与世界云影（colortex14）的专用时域历史：**未做**（范围外）。
- 多段云只代表第一（最近）云胞，与积分语义一致；全列一阶矩需改积分本体，超出 clouds_planar.glsl 语义禁改边界。

## 6. 下一处接续位置

- 基权 / 钳制 / 时间窗标定：`Astra/shaders/global/atmosphere/cloud_temporal.glsl` 常量区（`ASTRA_CLOUD_TEMPORAL_WEIGHT` 及两处 smoothstep）。
- 维度硬门：<0.5s 往返残影出现时，在 `astra_cloud_temporal_resolve` 的 dt 门追加维度指纹（需要新的存储位，候选 colortex25.b 与 viewWidth 合并编码或升 RGBA32F）。
- GUI 行：若统帅裁决退役既有选项或上调 80 上限，把 `CLOUD_TEMPORAL // [false true]` 注册进 settings/`screen.SKY`/四档 profile，并把尺寸门从 `#if CLOUD_MODE == 1` 改回 `#if defined CLOUD_TEMPORAL && CLOUD_MODE == 1`。
- 球面反射板与云影的时域化：参照 2.2/2.3 骨架各自建独立历史，入口分别在 `program/`（prepare 槽 colortex11 生产者）与 `program/cloud_shadow_cache.fsh`（colortex14 生产者）。

## 7. 证据

关键源码定位：
- 代表位置产生：`global/atmosphere/clouds_planar.glsl:238`（`astra_planar_cloud(worldDir, maxRayDistance, out representativeWorld)`）、`:384`（命中 break 前 `representativeWorld = tracePos`，即 cameraPosition + nPlayerPos×sampleDistance）
- 历史解析：`global/atmosphere/cloud_temporal.glsl:astra_cloud_temporal_resolve`（门序：frameCounter→投影列比较→dt/视口指纹→重投影越界→历史覆盖率→亮度/覆盖率钳制→预乘混合）；风平移推导注释在同文件
- 生产写入：`program/cloud_screen.fsh`（条件 `/* RENDERTARGETS: 12,24,25 */`；gl_FragData[0]=colortex12 原样、[1]=解析结果、[2]=元数据）
- 消费：`global/atmosphere/clouds_screen.glsl:astra_screen_cloud_sample`（ASTRA_CLOUD_TEMPORAL 下采样 colortex24）→ `program/deferred.fsh:233`（地形合成，近板局部步进分支不消费历史）与 `:271`（天空合成）、`program/sky.fsh:85/126`（日月盘衰减）
- 开关：`lib/settings.glsl:112`（`ASTRA_CLOUD_NO_TEMPORAL 0` 阀）、`:414-415`（宏定义）；尺寸门 `shaders.properties:136-141`

- `python qa/tools/check_pack.py`：开工前基线 `17 checks: 3 FAIL`（#4 root deferred.fsh shell 直含 settings、#11 SC-28、#15 fxaa 许可文本，EXIT=3）；交付前 `17 checks: 3 FAIL, 0 WARN, 14 PASS`（同一 #4/#11/#15），**FAIL 数不增**。期间一次回归（#1 选项计数 81、#2 profile 缺 token、#12 tier differential）由移除 GUI 选项改手动阀修复。
- `python qa/tools/compile_glsl.py`（真实 OpenGL 4.3 前端，D:\zhenhebao\.minecraft LWJGL 3.3.3）：
  - 四档默认（BALANCED/ULTRA 平面云=1 → 启用路径）→ `RESULT linked=420 failed=0 compute=36`
  - BALANCED + `--set ASTRA_CLOUD_NO_TEMPORAL=1`（回退阀）→ `RESULT linked=105 failed=0`
  - ULTRA + `--set ANTIALIASING=2`（TAA 开，验证前帧 uniform 不重复声明）→ `RESULT linked=105 failed=0`
  - BALANCED + `--set CLOUD_MODE=2`（关云，缓冲缩 1×1 无消费者）→ `RESULT linked=105 failed=0`
  - 过程中抓到并修复的真实编译错：①模块与 pass 各自的 `const int RGBA16F` 在 Iris 预处理器下双定义冲突（#ifndef 对非选项宏恒真）→ 模块改为复用 pass 的定义；②`(vec3, out vec3)` 调用无对应重载 → 改为显式三参调用。
- 无画面 / 帧时证据，未宣称任何观感或性能收益。
