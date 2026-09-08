# 第四轮实战根因与修复计划（2026-09-08）

**判断**：本轮只读，不改代码。基于最近六张实机图与三份参考实现（Steadfast 0.8.0、Solas V2.2b、Mellow 3.4）对比当前 Astra。

| 输入图 | 内容 | 现象 |
|---|---|---|
| 图 1 | 模范光影水面 | 参考：明亮青绿色，水下结构清晰 |
| 图 2 | Astra 水下 | 整个画面昏黑、无太阳穿水光束 |
| 图 3 | 模范光影水下 | 明亮水下、可见波动界面、太阳区域偏亮 |
| 图 4 | Astra 远景（前） | 玩家 (-155, 74.4, -564) 朝西南俯瞰 |
| 图 5 | Astra 远景（后） | 玩家 (-132.2, 74.4, -556.7) 朝同一方向、更靠东北 |
| 图 6 | Astra 水面 | 水色整体昏黑、无 teal/青透感，远水面细碎暗纹 |

裁决（用户原文）：① 水下阳光目标未达成；② 水色目标未达成；③ 阴影目标未达成（远处树影"靠近才出现"）。

---

## P0 修复：水下阳光光束（astra_water_sun_source 的水高闸门）

**位置**：`Astra/shaders/program/scene.glsl:79-82`
```glsl
float code = tap.caster.r;
if (code >= 0.999) return vec3(0.0);
float depth = decode_water_height(code) - (cameraPosition.y + playerPos.y);
if (depth <= 0.0) return vec3(0.0);
```

**问题**：`astra_water_sun_source(playerPos, viewRay)` 在 `light_shafts.glsl:51-60` 的水下视线积分中每一步都被调用。其当前实现先用 `shadow_read_tap` 取 `shadowcolor0.r`（最近 caster 的水高编码），非水直接 `return vec3(0.0)`。

**为什么目标不达成**：
- 水下视线积分 N 个 sample，每个 sample 都是水中某点。把它投影到太阳光视角下，水平方向的最近 caster 几乎全是**水底地形**（高度编码为 1.0，即 `WATER_HEIGHT_NONE`），不是水面。
- `if (code >= 0.999) return vec3(0.0);` 把这些 sample 全部吞掉，整条视线累计为 0。
- 只有当玩家**抬头看见水面**的那一两个 sample 才有机会命中 `shadowcolor0` 的水高编码块——但此时视线方向已接近垂直、cos 接近 0、phase 函数为侧向散射、`water_phase(dot(viewRay, lightDir))` 也很小。
- 结果就是**水下视线积分几乎全黑**，`composite → final` 解码后 `UNDERWATER_SHAFT_STRENGTH` 怎么也提不上来。

**对照 Solas V2.2b** `lib/atmosphere/volumetricLight.glsl:60-89`：完全没用 waterHeight 编码。它对每个 sample 直接 `ToWorld(ToView(vec3(texCoord, getLogarithmicDepth(currentDist))))`，获得世界坐标后 `ToShadow(worldPos)` 进入 sun 视角 NDC，再直接 `texture2DShadow(shadowtex0)` 比对深度；遮挡侧 source 为 0，否则按 `vlColor` 与 `currentSampleIntensity` 累加。这就是 underwater shafts 在 Solas 里始终能累积的原因。

**修复方案**：
1. 把 `astra_water_sun_source(vec3 playerPos, vec3 viewRay)` 改为 `astra_water_sun_source(vec3 surfaceWorld, float waterDepth, vec3 viewRay, float lightPathDistance)`：
   - `player_shadow` 在每个 sample **全分辨率**对 `worldPos = cameraPosition + rayOrigin + rayDir * sampleDist` 投影。
   - `shadow_read_tap` 已经返回 `opaqueVisibility / allVisibility`，不需要再读 waterHeight 编码。
   - 太阳方向的入水光学长度：传入 `waterColumnDepth / -lightDir.y`（光从太阳到水下点的垂直水程）。
   - 水入射 Fresnel（`water_light_entry`）和水程衰减（`water_transmission`）保持。
2. `astra_water_segment`（`scene.glsl:117-135`）与 `light_shafts.glsl:51-60` 的积分循环改成传 world-space sample 位置和当前视线段到水底的剩余深度，而不是 `playerPos`。
3. 视线上方无遮挡时，**不返回零**——此时 source = `direct_light × entry × transmission × phase × focus`。
4. `waterDepth` 由视线命中 surface 算得，而不是从 sample 自己附近的 caster 编码反推。
5. `UNDERWATER_SHAFT_SAMPLES` 默认 24，对应 96 段视野，**缩短 `light_shafts.glsl:54-55` 的 `begin = rayLength * ta * ta` 二次曲线，让靠近水底的 sample 同样被充分采样**（Solas 的 `currentDist = (i + dither) * minDist` 是线性均匀）。

**验证**：`qa/tools/light_shafts_probe.py` 用已知 shadowtex 输入在 RTX 4050 上跑线下数值：远距离水下视线积分 > 0；朝太阳方向积分 > 侧视；阴影覆盖率与 `opaqueVisibility = 0` 的 sample 一致为 0。

---

## P1 修复：水色偏黑（Astra 水面）

**位置**：
- `Astra/shaders/global/water/absorption.glsl:36-43` —— `water_medium(radiance, d, incidentLight) = radiance × T + incidentLight × σ_s/σ_t × (1-T)`
- `Astra/shaders/program/scene.glsl:62-66` —— `astra_underwater_color(viewDir) = astra_water_incident(eyeSky) × water_scattering_coefficient / water_extinction`
- `Astra/shaders/program/scene.glsl:53-61` —— `astra_water_incident(eyeSky) = mix(MIN_AMBIENT, sky_ambient * 0.01, smoothstep(0, 0.4, eyeSky))`

**问题分两层**：

1. **`incident` 颜色过暗**。`astra_water_incident(eyeSky)` 在 `eyeSky=1`（晴天玩家站在天空下）时 = `astra_sky_ambient() * 1.0 = (0.23, 0.38, 0.68)`。这是中性偏冷色但非常暗，**不到 Solas 直接拿 `waterColor = (0.30, 0.70, 0.85)` 当 base 的 35% 亮度**。`MIN_AMBIENT_COLOR = (0.0026, 0.0064, 0.008)`，cave fog 类似的暗蓝，下潜到深海混色后整个画面暗调主导。

2. **`σ_s / σ_t` 比值过低**。`water_extinction = abs + sctr`，在 BALANCED profile：
   - abs = (0.240, 0.035, 0.060) × 1.0 = (0.240, 0.035, 0.060)
   - sctr = (0.014, 0.045, 0.035) × 0.40 = (0.0056, 0.018, 0.014)
   - σ_s/σ_t = (0.023, 0.338, 0.190)——绿光为红光的 14.7 倍，看起来青绿但每个通道绝对值小（最大绿 0.338），整体灰。
3. `underwaterColor` 真正用于 `astra_apply_medium`（scene.glsl:197-206），作为水面像素 fog 的 lerp 终点。`fog = 1 − exp(-0.06 × d × 0.40) = 1 − exp(-0.024d)`，32 格处 fog=0.54，64 格 fog=0.79，**远水面几乎全是这个暗青绿色 fog**。

**对照 Steadfast** `environment/water/absorption.glsl`：
- `WaterAbsorption(depth)` 用 `exp(depth × BALANCED)`，depth 0-1 (屏幕深度归一化)，并且 `depth > 0.0 ? DARK_UNDERWATER : 1.0`，**空气侧 (refractive path) 始终是 1.0，无衰减**。
- 物理深度是屏幕归一化的，不是 blocks；色调靠 `−vec3(16, 3, 1)` 直接控制比例。

**对照 Solas V2.2b** `lib/water/waterFog.glsl:1-32`：
- `fog = 1.0 − exp(WATER_FOG_EXPONENT × length(viewPos) × 0.01 × density)`（指数系数 ~ −6）
- `waterFogColor = mix(waterColor, fogColor × 0.5, 0.25)`，预设明亮 waterColor
- 水下还 `×=(0.5 + 0.5 × eBS)` 提亮
- 朝太阳方向加 `glare = 0.01/(1 − 0.99 × glare) − 0.01`，**朝太阳 ~10× 提升**（这就是 Solas 水下"朝光发亮"的关键）

**修复方案**：
1. `astra_water_incident` 不再用 σ_s/σ_t 反推 incident。改成直接走天空与环境的明亮颜色：
   ```glsl
   vec3 astra_water_incident(float skylight) {
       float access = smoothstep(0.0, 0.35, skylight);
       vec3 outdoor = astra_sky_ambient();   // 不再 × 0.01
       return mix(MIN_AMBIENT_COLOR * 1.5, outdoor, access);
   }
   ```
   `MIN_AMBIENT × 1.5` 防止洞穴水变全黑。

2. `astra_underwater_color` 不再用 σ_s/σ_t 反推，改成类似 Solas：
   ```glsl
   vec3 astra_underwater_color(vec3 viewDir, float sunGlow) {
       float eyeSky = clamp(float(eyeBrightnessSmooth.y) / 240.0, 0.0, 1.0);
       vec3 base = mix(MIN_AMBIENT_COLOR, astra_sky_ambient(), eyeSky);
       float VoL = clamp(dot(normalize(viewDir), normalize(worldSunVector)) * 0.5 + 0.5, 0.0, 1.0);
       float glare = mix(0.0, 1.0 / max(1.0 - 0.99 * VoL, 1e-3) - 1.0, skyVisibilityDay);
       return base * (0.5 + 0.5 * eyeSky) + astra_direct_light() * glare * 0.10 * eyeSky;
   }
   ```
   朝光区域乘 glare（≤ 100 默认下最多 ≈16），中视线疲劳测的体感等价 Solas。

3. `astra_apply_medium` 水下像素混合：`mix(color, fog.rgb, fog.a)` 中的 `fog` 改成 `mix(color, astra_underwater_color(viewDir, VoL), fogFactor)`，让 fogFactor 增加时颜色趋向"天空+直视太阳提亮"，不是单纯雾色。

4. 调整 `UNDERWATER_FOG_DENSITY` 默认值 40 → 28（与 Solas `1 − exp(−6 × d × 0.01)` 在 32 格处 fog ≈ 0.61 接近）。再校 `WATER_ABSORPTION` 100 → 80（吸收过量）。

**验证**：`qa/tools/water_color_probe.py`：把 `astra_underwater_color` 输出与 `Steadfast` 在 24、48、96 块处归一化色相比较（取样 `qa/probes/`）；颜色 [R, G, B] 应在 ±15% 内，且 G > R, R ≥ 0.1。

---

## P2 修复：阴影"靠近才出现"（shadowDistance / profile 不匹配）

**位置**：
- `Astra/shaders/global/lighting/shadowmap.glsl:50-56` —— `shadow_box_distance` 用 L∞（切比雪夫），`shadow_map_fade` 在 `shadowDistance − 16` 至 `shadowDistance − 4` 渐隐。
- `Astra/shaders/shaders.properties:127` —— `profile.BALANCED=... SHADOW_DISTANCE=128 ...`
- `Astra/shaders/shaders.properties:126,128` —— `PERFORMANCE=96`，`ULTRA=192`

**问题**：
- MC 26.2 Fabric 实例默认 render distance = 16 chunks = 256 blocks。地形加载到 256 blocks 远，但 SHADOW_DISTANCE 只有 128 / 192。
- `shadow_box_distance = max(|x|, max(|y|, |z|))` —— 任何一个轴超 128 之外，对应 playerPos 上没有阴影（`shadow_map_fade → 0` → `shadow_coverage = 0`）。
- 用户在 `(−155, 74.4, −564.2)` 朝西南的远景：视野覆盖 −155 周围 ~50 blocks 的近景，加上远到 200+ blocks 远的森林。x 轴和 z 轴上超过 128 的位置（远景树、世界边缘）**完全没有阴影**——靠近玩家移动到 ≤ 128 blocks 内才出现。
- 这是典型的"shadow map frustum 比实际 render distance 小一半"的症状，按物理就是"远处物体投影出 frustum"。

**对照 Steadfast** `shaders.properties`：默认 `shadowDistance = 256`，选项 `[64 80 96 112 128 160 192 256]`。Steadfast 用户报告这是合理的。

**修复方案**：
1. 默认 profile 提升：
   - `PERFORMANCE`: `SHADOW_DISTANCE 96 → 192`
   - `BALANCED`:    `SHADOW_DISTANCE 128 → 256`
   - `ULTRA`:       `SHADOW_DISTANCE 192 → 256`（实际已达上限）
2. 检查 `entityShadowDistanceMul = 0.5`（settings.glsl:198），同步更新 PERF/BAL/ULTRA 的"实体阴影距离"——已以 0.5 倍跟随，刚好是 96/192，128/256，128/256，OK。
3. 选项范围 `[64 80 96 112 128 160 192 256]` 已经把 256 列为最高；保留 [384 512] 不必要，避免 SHADOW_RESOLUTION 不够时拖累阴影质量。
4. `shadow_box_distance` 的 fade 带宽 16/4：16 偏短，玩家快速移动会看到阴影裁切边界闪。扩展成 `(shadowDistance − 24, shadowDistance − 8)`，渐隐带更宽。
5. **不在范围**：让 shadowDistance 跟随 renderDistance（Iris const 是 `#define`，无法在 .properties 动态改），保留默认 profile 单一值。

**验证**：
- `qa/tools/shadow_frustum_probe.py`：在 player +x, +z 各 100、150、200、256 blocks 处放可投影立方体，验证 `shadow_coverage` 从 0.95 → 0.0 平滑过渡；图标覆盖范围与 render distance 一致。
- 编译：所有 profile × `lit.fsh`, `shadow.fsh`, `shadow.vsh`, `water.glsl`, `composite.fsh`, `final.fsh` 在 RTX 4050 / OpenGL 4.6 上 GLSL 链接 0 失败（`qa/glsl-shadow-fade-*.log`）。

---

## 修复顺序与工作量评估

| 优先级 | 项目 | 代码触碰位置 | 估计触碰量 | 预计工时 |
|---|---|---|---|---|
| **P0** | 水下阳光 shafts 解 waterHeight 闸门 | `program/scene.glsl:70-100`, `global/water/light_shafts.glsl:51-63`, `program/scene.glsl:117-135` | 3 文件 ~80 行 | 半天 |
| **P1** | 水色 incident/sun-dir glare 仿 Solas | `program/scene.glsl:53-66`, `program/scene.glsl:62-66`, `lib/settings.glsl:107,137` | 3 文件 ~30 行 + 2 个 default | 半天 |
| **P2** | shadowDistance profile 默认值上调 | `shaders.properties:126-128`, `lib/settings.glsl:185-187`（不动 const） | 2 文件 + 4 行 fade 改 | 2 小时 |

**总工时预算**：1.5 工作日内完成三处修复 + 同等深度验证。修复后必须执行之前定义的 §十四格式六项 R/T 验证 + 编译，重复 `qa/sc35-probe/`、`qa/water-path-followup/`、`qa/water_color_probe.py` 的图像采集路径。

**不实施**：
- 不用 Solas 一字不差搬 lighting 系数（涉及 license undeclared 风险，看 THIRD-PARTY）。
- 不动 `shadowHardwareFiltering = false` 与 16-tap exact PCF（SC-23 round-trip 已确认）。
- 不引入新的渲染 pass / 缓冲 / varying。
- 不增大 shadow map resolution（BALANCED 2048 已经够；继续加大拖累 4050 显存）。

---

## 修复后必须验证的对照清单

**水下阳光**：
- 朝太阳：可见 1-3 处青绿色光柱，沿太阳方向行 ~24-48 块。
- 侧对太阳：水柱亮度高于背对。
- 岸侧树荫下：明暗交错的 shafts 与方向性阴影并存。

**水色**：
- 浅水清澈见底：水底沙色按距离衰减，近 60%、16 格 30%、32 格 15%。
- 水面颜色：近岸明亮青绿、远岸 teal，与 Steadfast 图 1 同机位对比偏差 ≤ ±20/255。

**阴影**：
- 玩家位置 (-155, 74.4, -564) 朝西南：远 200 blocks 处的树仍投阴影。
- 玩家位置逐步靠近：移动中阴影位置平滑过渡，无突变 / 撕裂 / 翻转。
- 远处阴影 200-256 blocks 边界：渐隐带覆盖，避免硬边。

所有验证完毕、未达以上对照项前不打包。
