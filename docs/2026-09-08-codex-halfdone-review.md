# Codex 半成品改动 — 只读审查（2026-09-08 16:5x）

> 状态：历史审查，仅适用于文中审查时的源码；当前入口及已纠正结论见 [文档索引](README.md)。条目未逐项标为当前缺陷，也不表示全部已经解决。

**范围**：只读。未修改任何 shader / properties / 代码。仅编译验证（不写入 Astra）。
**对象**：Codex 在 16:24–16:28 的改动（限额中断前的最后一批）。

---

## 一、Codex 实际改了什么

### 新增 4 个文件

| 文件 | 作用 |
|---|---|
| `shaders/global/water/medium_state.glsl` | 水体状态编解码：RG 打包世界水面高度（1/16 格精度，[-1024,3072)），B=sky access，A=validity。读 `colortex6` |
| `shaders/program/water_state.fsh` | 新 composite 内容：遍历 `colortex5` 的 20×12 固定网格，找最近水面，写 `colortex6` |
| `shaders/composite2.fsh` / `.vsh` | 新 pass，承载原 `composite.fsh` 的散射内容（转发到 `program/scattering.fsh`） |
| — | `program/scattering.fsh` = 原 composite 逻辑（未重写，直接沿用） |

### 修改 8 个文件（16:24–16:28）

`program/scene.glsl`、`program/lit.fsh`、`program/composite.fsh`、`global/water/light_shafts.glsl`、`global/water/absorption.glsl`、`global/lighting/diffuse.glsl`、`lib/settings.glsl`、`shaders.properties`

### **未改**（mtime 早于 15:00）

- `program/water.glsl`（13:52）— 水面合成未动
- `global/lighting/shadowmap.glsl`（14:31）— **阴影 fade / box distance 未动**

---

## 二、Codex 的思路（与我的方案不同，但方向对）

**我的方案**（`docs/2026-09-08-fourth-round-rootcause-and-fixplan.md`）：取消 `astra_water_sun_source` 对 shadow map 水高编码的依赖，每个积分 sample 直接 `player_shadow + shadow_read_tap` 比对 shadowtex（仿 Solas `volumetricLight.glsl:60-89`）。

**Codex 的方案**：保留 shadow map 采样，但把"水面高度"的来源换成**屏幕空间水体状态**：

```
gbuffers_water (lit.fsh:97-99)  →  colortex5：打包水面世界高度（每片元）
        ↓
composite (water_state.fsh)     →  colortex6：全屏搜最近水面，1 个状态（保留上帧）
        ↓
scene.glsl:104 / light_shafts.glsl:48 / diffuse.glsl:177
                                →  water_volume_state() 读水面高度
```

配套的关键改动（`scene.glsl:88`）：
```glsl
float visibility = tap.opaqueVisibility;   // 原为 max(opaque - all, 0)
```
水不再计入遮挡——**只有不透明地形挡太阳**。这一条和 `diffuse.glsl:200` 的 `transmitted * tap.opaqueVisibility` 是同一个修正，方向正确。

**评价**：这个方案比我提的更"重"（多两个 buffer、一个 pass、全屏搜索），但它额外解决了"树影覆盖水面时水体被误判成空气"的问题（`medium_state.glsl:3-4` 注释），这是我没考虑到的。思路成立。

---

## 三、三个目标的达成状态

| 目标 | 状态 | 说明 |
|---|---|---|
| **水下阳光** | 🟡 架构已就位，未实测 | P0 根因（水高编码闸门）已解除。但有 1 帧延迟 + 首帧 fallback，需实测 |
| **水色** | 🟡 只调了系数，做了一半 | `astra_water_incident` 的 `×0.01` 未动，未加朝太阳 glare |
| **阴影距离** | 🔴 **完全未做** | `SHADOW_DISTANCE` 仍 128，profile 未改，`shadow_map_fade` 未改 |

---

## 四、问题清单（按影响分级）

### P0-1 · `size.buffer.colortex6=1 1` 疑似全分辨率 → 性能灾难

`shaders.properties:15`。`water_state.fsh` 注释写 "One pixel per frame"，但：
- Iris 的 `size.buffer` 语义：值 ≤ 1 视为**比例**，> 1 视为**像素**。`1 1` 极可能是 **100% 全分辨率**
- 若如此：`water_state` 的 20×12 = **240 次 texelFetch/像素**，1080p 下 ≈ 5 亿次纹理读取/帧
- 而消费端 `medium_state.glsl:16` 只读 `texelFetch(colortex6, ivec2(0), 0)` —— 一个像素

**必须实测帧率确认**。若确为全分辨率，改成明确的像素尺寸（如 `2 2`）即可，无需改逻辑。

### P0-2 · 阴影（图 4/5 树影）**完全没修**

- `lib/settings.glsl:59` — `#define SHADOW_DISTANCE 128`（未变）
- `shaders.properties` profile — `PERFORMANCE=96 / BALANCED=128 / ULTRA=192`（未变）
- `global/lighting/shadowmap.glsl:53-56` — `shadow_map_fade` 仍是 `smoothstep(shadowDistance-16, shadowDistance-4, boxDistance)`（未变）
- 唯一改动是 `settings.glsl:187` `shadowDistanceRenderMul 1.0 → 1.5`，但这**只影响 Iris 渲染 shadow map 时的 culling 范围**，不影响接收端 fade

→ **用户看到的"远处树影靠近才出现"不会有任何改善**。这是三个目标里唯一零进展的。

### P1-1 · 水色只调系数，未改公式

`scene.glsl:54-62` 未动：
```glsl
vec3 outdoor = astra_sky_ambient() * (SKYLIGHT_STRENGTH * 0.01);   // ×0.01 仍在
astra_underwater_color = incident * σ_s / σ_t;                      // 反推仍在
```

新系数（`absorption.glsl`）实测效果，BALANCED / WATER_ABSORPTION=100 / FOG_DENSITY=40：

| | 旧 | 新 |
|---|---|---|
| absorption | (0.240, 0.035, 0.060) | (0.135, 0.012, 0.028) |
| scattering | (0.014, 0.045, 0.035) | (0.012, 0.030, 0.040) |
| `underwater_color` | (0.005, 0.129, 0.057) | **(0.008, 0.190, 0.247)** |
| 10 格透射 | (0.079, 0.449, 0.387) | (0.247, 0.787, 0.644) |

- 亮度确实提升（绿 1.5×、蓝 4.4×）
- 但 **蓝 (0.247) > 绿 (0.190)** → 偏**蓝青**，与 Steadfast 的青绿（teal）目标有偏差
- 绝对亮度 0.247 vs Solas `waterColor` ≈ 0.7–0.85，仍差 ~3 倍
- 红透射 0.079 → 0.247（3 倍），水下可能偏"浑浊/发灰"

### P1-2 · gbuffers 读 colortex6 有 1 帧延迟

`composite` 在 `gbuffers_*` **之后**。`diffuse.glsl:177` 在 gbuffers_terrain 中读 colortex6，读到的是**上一帧**的值。
- 依赖 `colortex6Clear = false` 保留上帧内容
- 入水第一帧 `volume.a ≤ 0.5` → 回退到旧的 shadow 水高编码路径（`scene.glsl:80-83`）
- `water_state.fsh:38-49` 有 shadow map fallback 补救，但只覆盖"第一帧"

### P2-1 · `program.composite.enabled=true` 无条件

`shaders.properties:27`。即使 GODRAYS 和 UNDERWATER_LIGHT_SHAFTS 全关，water_state 仍每帧跑。应挂到与 composite2 相同的条件上，或至少与 shafts 联动。

### P2-2 · `astra_water_segment` 的隐式契约未写注释

`scene.glsl:138-139` 传 `start.y + cameraPosition.y` 作为 `surfaceHeight`：
```glsl
sum += astra_water_sun_source(start + ray * (0.5*(a+b)), ray,
                              start.y + cameraPosition.y) * weight;
```
`depth = surfaceHeight - (cameraPosition.y + playerPos.y)` 化简为 `-ray.y * 0.5*(a+b)`，即"从段起点到采样点的垂直水程"。

**只有当 `start` 恰好是入水点时物理正确**（`water.glsl:99` 和 `:146` 两处调用确实满足）。但：
- 契约没写进注释，后续改动极易踩坑
- 水下**向上**反射（`water.glsl:146` belowWater 分支，ray.y > 0）时 `depth < 0` → `return vec3(0)` → 全反射区无太阳散射，偏暗

### P2-3 · 20×12 固定网格可能漏检

`water_state.fsh:14-15` 只采样 240 个屏幕点。深水或水面只占屏幕一小角时可能一个都命中不了 → `best.a < 0.5` → 回退旧路径。

### P2-4 · 新 buffer 未登记

`colortex5` / `colortex6` 未进 `design.md` §2.3 缓冲表，`THIRD-PARTY.md` 也未说明。

---

## 五、已确认没问题的项

- **GLSL 编译全绿**：BALANCED `linked=76 failed=0`；PERFORMANCE+ULTRA `linked=152 failed=0`（RTX 4050 / OpenGL 4.6 / 驱动 572.83）。日志 `qa/glsl-codex-check-balanced.log`、`qa/glsl-codex-check-profiles.log`
- **无断链 include**：`composite2.fsh → program/scattering.fsh` 存在
- **colortex5 的 blend 配置正确**：`blend.gbuffers_water.colortex5=SRC_ALPHA ONE_MINUS_SRC_ALPHA ...`，而水面片元写 a=1.0、非水面写 a=0.0，二值 alpha 使混合**退化为选择**，不会破坏 16-bit 高度编码
- **`visibility = tap.opaqueVisibility`（scene.glsl:88 / diffuse.glsl:200）正确**：水不挡太阳，只有地形挡

---

## 六、接续建议（按顺序）

1. **先补 P2 阴影**（唯一零进展，且是用户明确点名的第三项）：`SHADOW_DISTANCE` 128→256、profile 同步、`shadow_map_fade` 渐隐带 16/4→24/8。约 2 小时，风险低。
2. **实测 colortex6 尺寸**：进游戏看帧率。若暴跌，把 `size.buffer.colortex6=1 1` 改成明确像素尺寸。
3. **再测水下/水面**，拿到实测图后再决定水色是继续调系数还是改公式（去 `×0.01` + 加朝太阳 glare）。
4. 补 `design.md` §2.3 的 colortex5/6 登记。

**不建议**在拿到实测图之前继续调水色系数——现在手里只有编译通过，没有任何观感证据。
