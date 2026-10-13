# 水下光束彻底重写意见（hy4）

标注：hy4。日期：2026-10-10。

本文针对 **W04（水下光束像柱子、位置乱七八糟、固定、毫无质感）**，不是补丁清单。做三件事：症状的机制归因、逐项对照 ITT 3.2.0 / Solas V2.2b 与 Astra 现行实现、给出一套可执行的结构性替代方案。

本文**不修改任何源码**。落地按第 8 节的阶段顺序执行，每阶段回写 [当前工作](当前工作.md) 与 [实现与限制](实现与限制.md)。在那之前这两份文件里关于光束的描述仍然有效，不要按本文提前宣告已修复。

文中所有数字均由本机依据当前源码复算，计算过程见第 10 节，可复核。

---

## 1. 结论摘要

现行实现不是"参数没调好"，而是**多处各自成立的保守选择叠在一起**，把 ITT 那套对比强烈、方向性明确的体积光压成了几根均匀光柱。按影响力排序：

| # | 根因 | 位置 | 量化 |
|---|---|---|---|
| **R1** | 积分足迹过大 → 波面 mip 把细节滤掉了 | `light_shafts.glsl:140,146-147` | 每步足迹 **0.93 格 → LOD 1.9**，六层中**五层被滤掉**，只剩 L6，波面细节仅存 **24%** |
| **R2** | 相位函数被压平：g=0.45 且只掺 40% 定向 | `light_shafts.glsl:74-81` | 前向/后向 **4.3 : 1**，ITT 是 **182 : 1**，差 **42 倍** |
| **R3** | 焦散立方后被软饱和，饱和值仅 4.0 | `itt_water_normal_cache.fsh:46` | `|slope|≥0.25` 以上的全部明暗塌到同一水平（见 §10 表） |
| **R4** | 窗格原点依赖当帧水深估计 | `itt_water_normal_cache.fsh:25-26` | 每帧可能跳 **4 格**，光束整体平移 |
| **R5** | 相位用逐点局部折射方向而非全局光源方向 | `light_shafts.glsl:168` | 相位随波面高频抖动，闪烁来源 |
| **R6** | 大波峰 `pow(envelope,10)` 进一步压暗 | `itt_water_normal_cache.fsh:49` | 幂次过陡，非主要矛盾但叠加有害 |

**R1+R2+R3 三条合起来完整解释了"像柱子、毫无质感"**，R4 解释"位置乱七八糟"，R5 解释"抽动"。

**成本上重写可以更便宜**：现行每像素 **28 次波面采样 + 14 次遮挡调用**；方案建议 **12 步 × 1 次波面 + 12 次遮挡**，波面采样降到 12 次（**-57%**），且足迹小、细节多。

### 一处必须先纠正的既有认知

我在核对过程中发现，此前"ITT 大波峰波长 117/235 格、窗格里只有一两个峰"的判断**是错的**，源于把噪声图当 256×256 计算。实测 `Astra/shaders/textures/itt-water-noise.png` 是 **64×64 RGBA**（PNG 头与 `.mcmeta` 均为 64），而 `itt_wave_noise` 里坐标乘 64 正对应此尺寸。按 64 复算，六层特征尺度是 **0.11 ~ 1.58 格**（不是 9.5~235 格）。

这个纠正**加强了**原诊断而非削弱：波面细节本来就在亚米级，而现行积分足迹是 **0.93 格**，比最粗一层的特征尺度还大。所以"细节被滤掉"不是推测，是量级上的必然。

---

## 2. 症状 → 机制归因

### 2.1 "像柱子"

**先澄清：柱子的几何是物理正确的，不要推翻。**

水下平行光经水面折射后仍是平行光，强度沿传播方向只受吸收衰减，所以水下光束本来就是平行柱体。Astra 用一张 2D 波面光量图 + 沿光线投影来表示，与 ITT 同构（推导见 §3.2）。差别只在**柱体内部的明暗从哪来**：

- ITT：`caustics = 5.6·|波面斜率| + 0.2`，取**立方且不做饱和** → 柱内有 182:1 级的锐利明暗。
- Astra：立方后被软饱和压到上限 4.0（R3），再叠加一个 footprints 过大导致的 mip 平均（R1）。

两者叠加的结果是柱体内部被抹成近乎均匀的亮度 → 视觉上就是几根均匀发光的柱子。

### 2.2 "位置乱七八糟"

1. **窗格原点依赖水深（R4）**。`:25` 用 `depth`（当帧估计的水面高度）算窗口中心，量化到 4 格。水深估计一抖，窗口原点跳 4 格，整幅图案平移。
2. **边界 slab 裁剪**。`water_shaft_wave_segment`（`:82-95`）用 4 格边距做裁剪，而积分范围 26 格 → 相机靠近窗格边缘时大量区间被裁掉，光束忽有忽无。
3. **窗口覆盖不足**。128 格窗口配 26 格积分，斜阳时投影偏移可达 `depth·|slope|`，容易超出窗口 → 又依赖 1. 的水深补偿，形成耦合。

### 2.3 "固定"

图案锚在世界坐标、波也在动，理论上不该固定。但**主导层 L5/L6 特征尺度 0.71/1.58 格**（权重合计 63%），在 0.93 格足迹下 L5 已被滤掉一半、L6 勉强保留；而真正快速变化的细层 L1/L2（0.11 格，权重 6.3%）**100% 被滤掉**。

于是"动的成分被滤掉，留下的是不动的成分" → 固定。这与 R1 是同一个根因的两种表现。

### 2.4 "毫无质感"

- R1：细节只剩 24%，柱内无纹理。
- R2：相位方向性只有 ITT 的 1/42，失去"只有朝光才亮"的体积感。
- R3：明暗层次塌到上限 4.0，无高光。

---

## 3. ITT 3.2.0 原实现解剖

本地源码：`_analysis/video-2026-10-01/iterationt/source/shaders/`。

### 3.1 体积积分主体

`Lib/IndividualFounctions/UnderwaterVolumetricFog.glsl:39-96`：

```glsl
const float range = 40.0;
float startDist = length(startPos);            // composite5 传 vec3(0.0) → 0
endPos = mix(worldDir*range, endPos, step(length(endPos), range));
const float steps = VFOG_QUALITY;              // 4(Low) / 12(Ultra)
const float stepLength = range / steps;
float noise = BlueNoiseTemproal().y;           // 时域抖动

for (float i = 0.0; i < steps; i++) {
    float rayLength = (i + noise) * stepLength;
    vec3  rayPos = startPos + rayDir * rayLength;
    if (startDist + rayLength > range || rayLength > rayDist) break;

    vec3 shadowProjPos = ShadowScreenPos_From_WorldPos_Distorted(rayPos + gbufferModelViewInverse[3].xyz);
    vec3 shadow = vec3(step(shadowProjPos.z + 1e-06, textureLod(shadowtex1, shadowProjPos.xy, 0).x));

    rayLength += startDist;
    float caustics = CalculateWaterCaustics(rayPos);
    shadow *= caustics * caustics * caustics;              // ← 立方，无饱和
    shadow /= max(3.0, rayLength * 0.1);
    shadow *= pow(vec3(0.1,0.6,1.0)*0.99, vec3(rayLength*0.04*WATERFOG_DENSITY));
    result += shadow;
}
result *= range / steps;

vec3 lightVector = refract(worldShadowVector, vec3(0.0,-1.0,0.0), 1.0/1.2);
float phace = MiePhaseFunction(0.7, dot(lightVector, worldDir));   // ← 纯 Mie，g=0.7
result *= colorShadowlight * (0.04 * phace * SUNLIGHT_INTENSITY * UNDERWATER_VFOG_DENSITY);
result *= vec3(0.2, 0.65, 1.0);
result *= globalCloudShadow;
```

要点：**每步一次波面查询 + 一次阴影**，时域蓝噪声抖动，`range=40`，一个全局 Mie 相位。

### 3.2 焦散查询（关键，含推导）

`UnderwaterVolumetricFog.glsl:23-36`：

```glsl
float CalculateWaterCaustics(vec3 worldPos) {
    worldPos.xyz += cameraPosition;
    vec3 lookupCenter = worldPos;
    lookupCenter.y += 1.0;
    vec3 wavesNormal = GetWavesNormalFromTex(lookupCenter).xzy;
    vec3 refractVector = refract(vec3(0.0,1.0,0.0), wavesNormal.xyz, 1.0);
    vec3 collisionPoint = lookupCenter - refractVector / refractVector.y;
    float dist = distance(collisionPoint, worldPos);
    return dist * 2.8 + 0.2;
}
```

推导（此处极易误读，务必按此理解）：

- `wavesNormal` 经 `.xzy` 后 y 分量恒为 1.0（向上的法线）。
- `refract((0,1,0), N, eta=1.0)` 在 `dot(N,I)>0` 时退化为**反射**：`I − 2(I·N)N`。因 `I·N = N.y = 1`，得 `refractVector = (−2n.x, −1, −2n.y)`，向下。
- `collisionPoint − worldPos = (−2n.x, 0, −2n.y)`（y 方向 +1 偏移被抵消）。

**所以 `dist = 2·|n.xz|`，即 `caustics = 5.6·|波面斜率| + 0.2`。**

结论：**ITT 的水下体积光亮度 ∝ |波面斜率|³，不是聚焦强度**。这与真实焦散不同，但视觉上有效——波面起伏处亮、平坦处暗。

### 3.3 一处 ITT 的粗糙点（不要照搬）

`GetWavesNormalFromTex` 用 `lookupCenter.y`（**绝对世界 Y**，海平面约 62）做投影偏移，等价于把投影面设在 **y=0** 而非真实水面。太阳斜时偏移可达 62 格，远超纹理周期，被 `fract` 折叠成随机相位。

**即 ITT 的水下光束在位置上本来就与真实水面无关。** Astra 用 `surfaceY − P.y`（`light_shafts.glsl:128,133` 的 `entry`）是**更正确**的做法，**这条要保留 Astra 的，不要改回 ITT**。

### 3.4 波面分层与频率（已按 64×64 噪声图复算）

`Lib/IndividualFounctions/WaterWaves.glsl:31-75`，六层，`WAVE_SCALE=0.05`（`Lib/Settings.glsl:195`），噪声图 64×64：

| 层 | 特征尺度（格） | 频率（纹素/格） | 权重 | 占比 | 备注 |
|---|---:|---:|---:|---:|---|
| L1 | **0.108** | 9.280 | 1 | 1.3% | 最细 |
| L2 | **0.108** | 9.280 | 4 | 5.1% | |
| L3 | **0.443** | 2.260 | 8 | 10.1% | |
| L4 | **0.498** | 2.009 | 16 | 20.3% | |
| L5 | **0.711** | 1.406 | 30 | **38.0%** | AlmostIdentity 尖峰 |
| L6 | **1.581** | 0.633 | 20 | **25.3%** | AlmostIdentity 尖峰 |

L5+L6 占 63%，是主导项，特征尺度 **0.71 / 1.58 格**——这个尺度正是"束内可辨的亮纹"，也正是被 R1 的 0.93 格足迹直接抹掉的那一档。

### 3.5 波面法线缓存

`deferred.fsh:28`：`GetWavesNormal(vec3(causticsCoord.x, 1.0, causticsCoord.y), 25.0)`，写 `colortex7`（RGBA16）。

`causticsCoord = gl_FragCoord.xy * (50.0 / min(screenSize.y, 500))` → 1080p 下每纹素 **0.1 格**，覆盖约 **192×108 格**，`fract` 平铺。

**这一块 Astra 已更优**：`program/itt_water_normal_cache.fsh` 是 512×512 覆盖 128 格（0.25 格/纹素）的**世界对齐**图，不平铺、有 mip、只在水下生产。生产端 ITT 是全屏 ×18 次噪声读取，Astra 是 26 万像素 ×6 次 gather。**保留 Astra 的生产端，不要换回 ITT。**

### 3.6 相位

`Lib/Utilities.glsl:269-273`：

```glsl
float MiePhaseFunction(float g, float nu) {
    float gg = g*g;
    float k = 0.1193662*(1.0-gg)/(2.0+gg);
    return k*(1.0+nu*nu)*pow(1.0+gg-2.0*g*nu, -1.5);
}
```

g=0.7 时：`nu=1 → 1.811`，`nu=0 → 0.0134`，`nu=−1 → 0.00995`。**前向/后向 182:1**，前向/侧向 135:1。

---

## 4. Solas V2.2b 原实现解剖

本地源码：`reference_shaderpacks/solas-shader/shaders/lib/atmosphere/volumetrics.glsl`。

Solas 没有独立的水下光束 pass，水下体积光走通用 `computeVolumetricLight`，靠 `isEyeInWater==1` 分支切换。可借鉴的是**组织方式**，不是水下光学。

### 4.1 指数步进（最值得搬）

```glsl
float currentDist = exp2(dither);                            // :192
for (int i = 0; i < sampleCount; i++, currentDist *= 2.0) {  // :194
```

近处密、远处疏，天然给出"近处可读、远处自然衰减"，且远处步数稀疏省成本。

**但直接搬到水下光束要谨慎**（见 §6 判定）：水下光束的细节来自波面，而波面细节要求**足迹 ≲ 0.5 格**。指数步进在远端步长可达 13 格（N=8）或 4.4 格（N=12），远端细节同样被滤掉。指数步进解决的是"远处不该看清"，而水下光束远处本来就被吸收+雾衰减，**两者需求重叠但指数步进会把近端省下的预算浪费在过密的采样上**（N=12 时前三步步长 0.02/0.04/0.06 格，远细于 0.25 格纹素，纯属浪费）。

**结论：水下光束用等距步进，但把 range 收到 18~20 格**，比指数步进更直接地满足"足迹 ≤ 0.5 格"。

### 4.2 双重端点

```glsl
bool isRayMarcherHit(float currentDist, float maxDist, float linearZ0, float linearZ1, vec3 translucent) {
    bool isMaxReached            = currentDist >= maxDist;
    bool opaqueReached           = currentDist > linearZ1;
    bool solidTransparentReached = currentDist > linearZ0 && translucent == vec3(0.0);
    return isMaxReached || opaqueReached || solidTransparentReached;
}
```

`linearZ0`（含透明）/ `linearZ1`（不透明）两个端点同时参与终止判定。Astra 只用 `depthtex0` 单端点 + 手部修正（`light_shafts.glsl:46-51`）。**这条值得补**，与 D01（多层透明排序）相关但不依赖它——只需在 `water_shafts_view` 里多取一次 `depthtex1`。

### 4.3 距离/昼夜组织

```glsl
distanceFactor = float(isEyeInWater) * 5.0 + closedSpaceFactor * 2.0;   // :63
maxDist /= 1.0 + vlDistanceFactor;                                      // :183 → 水下范围压到 ~1/6
sampleCount += int(sunVisibility * (4 - dfade*3 + wetness*3));          // :174 晴天加步数
intensity = intensity * float(isEyeInWater==0)
          + float(isEyeInWater==1) * (1.0 + VoLClamped*VoLClamped*2.0) * (0.25 + sunVisibility*1.75);  // :56
currentSampleIntensityVL = pow(currentDist/maxDist/sampleCount, vlSamplePersistence);                  // :205
```

水下特有：`samplePersistence −= 0.25`（衰减更陡）、`distanceFactor = 5.0`（范围压缩）、强度用 `VoL²` 调制（**Solas 没有显式相位函数，用 VoL 强度代替**）。

### 4.4 入射/遮挡分离

```glsl
vlSample = clamp(shadow1*(1.0-shadow0)*doShadowColor*shadowCol*shadowCol
                 * mix(vec3(0.25), waterColor*lShadowCol, float(isEyeInWater==1))
                 + shadow0*vlCol*float(isEyeInWater==0), 0.0, 1.0);   // :232
```

`shadow0=shadowtex0`（不透明）、`shadow1=shadowtex1`（透明）。这就是"**入射透光**与**介质遮挡**分开算"。Astra 现行 `water_shaft_path_visibility`（`light_shafts.glsl:96-112`）把它拆成 entry（水面入射）与 point（体积遮挡）两处，**比 Solas 更贴合水下**，保留。

---

## 5. Astra 现行实现解剖

| 环节 | 文件 | 说明 |
|---|---|---|
| 光量生产 | `program/itt_water_normal_cache.fsh:16-51` | 512×512，128 格，只在水下 |
| 波面 | `lib/itt_water_waves.glsl` | ITT 六层**解析梯度**（非有限差分） |
| 大波峰 | `lib/itt_water_waves.glsl` `itt_water_beam_envelope` | 只取 L5/L6，`scale=0.30` |
| 参数广播 | `program/scattering.vsh:39-48` | 折射方向、水面高度、窗格原点 |
| 积分 | `global/water/light_shafts.glsl:113-182` | 7 段 × 4 点 Gauss |
| 遮挡 | `global/water/light_shafts.glsl:96-112` | entry + point 两处 |
| 相位 | `global/water/light_shafts.glsl:74-81` | g=0.45 + 40% 定向 |
| 组织 | `global/water/shaft_layout.glsl` | near 0.08→0.3，far 14→26 |
| 消费 | `program/water_composite.fsh:27`、`program/display.fsh:138` | 深度加权双线性上采样 |

### 5.1 现行几何是**正确的**，不要推翻

`light_shafts.glsl:133-135`：

```glsl
vec3 entry    = worldOrigin + source*(depth/source.y);
vec3 entryRay = ray - source*(ray.y/source.y);
```

设 `P = worldOrigin + ray·t`，沿 `source`（向下）反推水面入口 `E = P − source·(P.y − surfaceY)/source.y`，得

```
E.xz = [worldOrigin.xz + source.xz·depth/source.y] + t·[ray.xz − source.xz·ray.y/source.y]
     = entry.xz                                     + t·entryRay.xz
```

与代码一致。**"相机沿光线上升到水面再水平扫"就是正确的沿光线投影**，不要因为效果不好就推翻它。

**一处次要缺陷**：`entryRay` 未归一化，`|entryRay.xz|` 随几何在 0~1 间变化，使 `t` 与实际水平位移不成正比，`sourceFootprint`（`:146`）随之失准。建议归一化并显式补偿（见 §7.3）。

### 5.2 一处死代码

`global/water/shaft_history.glsl` 已无任何引用（全仓 grep 只剩自身），是四深度缓存时代的残留。**重写时直接删除**，不要"以防万一"保留。

---

## 6. 差异对照表（核心）

| 项 | ITT 3.2.0 | Solas V2.2b | Astra 现行 | 判定 |
|---|---|---|---|---|
| **相位函数** | 纯 Mie **g=0.7** | 无显式相位，用 `VoL²·(0.25+sunVis·1.75)` | Mie **g=0.45**，`mix(iso,dir,0.4)` | **改**。Astra 前向/后向 4.3:1，ITT 182:1 |
| **焦散饱和** | `caustic³`，**无饱和** | 不适用 | `e/(1+0.25e)`，饱和值 **4.0** | **改**。高斜率段层次全塌 |
| **大波峰幂次** | 参与总高度 | 不适用 | `pow(envelope, 10)` | **改**。`10` 过陡，降到 2~4 |
| **积分足迹** | 一步一采样，无足迹概念 | 指数步进 | `stepLength·|entryRay.xz|·0.25` = **0.93 格** | **改（R1，最优先）**。只存 24% 波面细节 |
| **每步成本** | **1 波面 + 1 阴影** | 1~2 阴影 + 云影 | **4 波面 + 2 阴影** | 改。改后波面采样 −57% |
| **积分范围** | **40** | `shadowDistance/(1+distanceFactor)` | **26** | 改：收到 **18~20**（为压足迹） |
| **端点** | 单 depth | **双 `linearZ0`/`linearZ1`** | 单 `depthtex0` + 手部修正 | 补：加 `depthtex1` 双端点 |
| **窗格原点** | `fract` 平铺，无原点概念 | 不适用 | **依赖当帧水深**，量化 4 格 | **改（R4）**：只锚相机 XZ |
| **窗格覆盖** | 192×108 格（平铺） | 不适用 | 128 格 + 4 格边界淡出 | 视 §7.2 实测决定是否扩到 192 |
| **云影** | `globalCloudShadow` 标量 | `VC_SHADOWS` 云影 | entry 处一次云透射 | 保留现做法 |
| **昼夜** | `SUNLIGHT_INTENSITY × UNDERWATER_VFOG_DENSITY` | `timeBrightness`/`sunVisibility` 多项 | `clearDay` 曲线 `mix(0.32,1.35)` | 保留，晴天侧可再放开 |
| **晴天增量** | 无 | **加步数** `sunVisibility×(4−dfade·3+wetness·3)` | 只改亮度 | **不加步数**（性能优先）。改用 envelope 幂次随 `clearDay` 下降实现"晴天更多更亮"，成本为零 |
| **生产端图** | 全屏 ×18 噪声，平铺 | 不适用 | 26 万像素 ×6 gather，世界对齐、有 mip | **Astra 更优，保留** |
| **时域** | 蓝噪声抖动 | dither（配 TAA） | 无抖动（水下无 TAA） | **不加时域抖动**（会噪）。靠步数与 mip，不靠时间累积 |

---

## 7. 重写方案

### 7.1 目标结构（四层，各层职责不再互相干扰）

```
层 A  光量场（世界对齐，同帧）   program/itt_water_normal_cache.fsh
      R = 透射 × caustic³（放宽饱和）
      G = 大波峰幅度（降低幂次）
      BA = 局部折射斜率（仅供相位；相位改用全局方向后此通道可退役）

层 B  积分（屏幕空间，低分辨率） global/water/light_shafts.glsl
      等距步进，每步 1 次波面 mip 采样 + 1 次体积遮挡
      目标是足迹 ≤ 0.5 格，不是步数更多

层 C  组织（每帧一次，顶点侧）   program/scattering.vsh
      折射方向、水面高度、窗格原点（只锚相机 XZ）
      距离/昼夜/天气/云影响应

层 D  合成                       program/water_composite.fsh / display.fsh
      深度加权双线性上采样（保留）
```

关键约束：**层 A 只负责"水面上每个点进来多少光"，不再决定"屏幕上哪里出现光束"。**

### 7.2 层 A：`program/itt_water_normal_cache.fsh`

**放宽软饱和（R3）**（第 46 行）：

```glsl
// 现状
float energy = caustic*caustic*caustic;
energy = energy/(1.0+0.25*energy);          // 饱和值 4.0

// 建议
float energy = caustic*caustic*caustic;
energy = energy/(1.0+0.04*energy);          // 饱和值 25
```

依据（§10 表）：`|slope|=0.25 → 4.1`（k=0.25 给 2.02，k=0.04 给 3.52，ITT 给 4.1）；`|slope|=0.6 → 45.1`（k=0.25 给 3.67，k=0.04 给 16.09）。现行在 `|slope|≥0.25` 之后几乎不再变化，**这正是"毫无质感"的直接数值来源**。

不要完全去掉饱和：裸 `caustic³` 在 AlmostIdentity 尖峰处可达 10²~10³，配合 mip 仍可能闪。取 **20~30**（系数 0.05~0.033），首落 **0.04**，按画面在 0.02~0.08 调。

**大波峰降低幂次（R6）**（第 49 行）：

```glsl
// 现状
envelope = pow(envelope, mix(10.0, 6.0, clearDay));

// 建议
envelope = pow(envelope, mix(4.0, 2.0, clearDay));
```

`clearDay` 高时降到 2.0，实现"晴天更多更亮"——**成本为零，不需要加步数**（对比 Solas §4.3 的加步数做法）。

**窗格原点不再掺水深（R4）**（第 25-26 行）：

```glsl
// 现状
vec2 centre = cameraPosition.xz - nominalDown.xz*(depth/max(-nominalDown.y,0.2));
vec2 originCell = floor((centre/ITT_WATER_FIELD_CELL - ITT_WATER_FIELD_SIZE*0.5)/16.0)*16.0;

// 建议：只锚相机 XZ，量化粒度降到 1 纹素
vec2 originCell = floor(cameraPosition.xz/ITT_WATER_FIELD_CELL) - ITT_WATER_FIELD_SIZE*0.5;
```

代价：窗口不再"预判"光从哪进来，斜阳时可能覆盖不足。**正确补救是扩大 `ITT_WATER_FIELD_EXTENT`（128 → 192，纹素保持 512，即 0.375 格/纹素），不是把水深塞回原点。** 若实测覆盖足够，保持 128 即可（0.25 格/纹素分辨率更好）。

### 7.3 层 B：`global/water/light_shafts.glsl`

**R1（最高优先级）：把积分足迹压下来。**

现状（`:140,146-147`）：

```glsl
float stepLength = min(astraWaterShaftRange,WATER_SHAFT_FAR_END)/float(ASTRA_SHAFT_SAMPLES);
float sourceFootprint = max(ITT_WATER_FIELD_CELL, stepLength*length(entryRay.xz)*0.25);
float sourceLod = clamp(log2(sourceFootprint/ITT_WATER_FIELD_CELL),0.0,3.0);
```

均衡档 `ASTRA_SHAFT_SAMPLES=7`、range=26 → `stepLength=3.71`，足迹 **0.93 格**，LOD 1.9，六层中**五层被滤掉**。

**建议配置（先落这一组，再按实测微调）**：

| 档位 | steps | range | 足迹 | LOD | 波面细节 | 波面采样 |
|---|---:|---:|---:|---:|---:|---:|
| 性能 | 8 | 16 | 0.50 | 1.00 | **62%** | 8 |
| 均衡 | **12** | **18** | **0.375** | **0.58** | **84%** | **12** |
| 极致 | 16 | 20 | 0.313 | 0.32 | **90%** | 16 |

对比现状 7 步 / range 26 / 足迹 0.93 / 细节 24% / 28 次采样：均衡档**细节 24% → 84%，采样 28 → 12**。

**注意**：range 从 26 收到 18 是**有意的**，不是退步。远端本来就被吸收+雾衰减；与其用 26 格但每步都糊，不如用 18 格但每步清晰。若实测发现远端光束截断生硬，优先调 `WATER_SHAFT_FAR_START/FAR_END` 的淡出曲线（`shaft_layout.glsl`），**不要**把 range 加回去。

**每步单采样替代 4 点 Gauss**：段内 4 点 Gauss 的前提是段内被积函数平滑。改小足迹后段长已小于特征尺度，Gauss 无意义。直接取段中点一次采样。

**归一化 `entryRay`**（§5.1）：

```glsl
vec2 entryDir = entryRay.xz;
float entryScale = length(entryDir);
vec2 entryUnit = entryScale > 1e-6 ? entryDir/entryScale : vec2(0.0);
// 水平位移 = t * entryScale，足迹用 stepLength*entryScale
```

**相位函数（R2）**：

```glsl
// 现状：g=0.45，40% 定向
// 建议：g=0.70，92% 定向
float water_shaft_phase(vec3 ray, vec3 source) {
    float cosine = clamp(dot(ray,source),-1.0,1.0);
    const float g = 0.70;
    float base = 1.0+g*g-2.0*g*cosine;
    float directional = (0.1193662*(1.0-g*g)/(2.0+g*g))
                      * (1.0+cosine*cosine)/(base*sqrt(base));
    return mix(0.07957747, directional, 0.92);
}
```

**相位入参改用全局折射方向（R5）**：

```glsl
// 现状
vec3 localSource = normalize(vec3(wave.b,1.0,wave.a));
... water_shaft_phase(ray, localSource)

// 建议
... water_shaft_phase(ray, waterShaftSource.xyz)
```

与 ITT 一致（ITT 的 `lightVector` 是全局的）。局部方向留给未来的"束内偏折"，先不引入。改后 `BA` 通道无消费者，可随之退役。

**遮挡降频**（`water_shaft_path_visibility`，`:96-112`）：

- **point 遮挡（体积内）每步保留**——光束阴影的来源，不能省。
- **entry 遮挡（水面上）降到每 3 步一次**，中间线性插值。水面上的遮挡（船、桥、悬崖）是大尺度特征，不需要逐步。

现状 7 interval × 2 调用 = 14 次；改后 12 步 × 1 + 4 次 entry = 16 次，但波面采样从 28 降到 12，**总量仍下降**。

**双端点（§4.2）**：`water_shafts_view` 增加一次 `depthtex1` 读取，供 `marchLength` 终止判定使用。与手部修正（`:49-50`）并存，手部优先。

### 7.4 层 C：`program/scattering.vsh`

- 新增 `flat out float waterShaftClearDay`，把 `clearDay`（`:41`）传给片元，供 §7.2 的 envelope 幂次使用。
- `visibility` 的晴天曲线 `mix(0.32,1.35,clearDay)`（`:44`）保留；若 §7.2 放宽饱和后整体偏亮，优先在此下调，**不要回去收紧饱和**。
- `waterShaftSource = vec4(waterLightDir, visibility)` 不变。

### 7.5 层 D：消费端

`water_shafts_resolve`（`:184-228`）的**深度加权双线性上采样**是正确的，保留。

- `astraWaterShaftRange`（`lib/water_palette.glsl:11`，现 48.0）应 ≥ `WATER_SHAFT_FAR_END`（将改 18~20），保持 48 不动即可。
- `UNDERWATER_SHAFT_SAMPLES` 语义从"段数（段内 4 点）"变为"步数（每步 1 点）"，滑杆范围建议 `[8 10 12 14 16 18]`。

### 7.6 删除清单

| 文件/代码 | 理由 |
|---|---|
| `global/water/shaft_history.glsl` | 全仓无引用，四深度缓存时代残留 |
| `program/prepare5.*` 相关调度引用 | 已在 `shaders.properties:217` 关闭，清理残留引用 |
| `colortex29` 的 `BA` 通道（折射斜率） | 相位改全局方向后无消费者（**在 R5 落地后**再删，不要提前） |

---

## 8. 落地顺序与验证点

**原则：一次只改一个根因，每步都要有画面或读数。** 不要一次性提交全部改动——出问题无法归因。

| 阶段 | 改动 | 验证点 | 通过判据 |
|---|---|---|---|
| **S1** | §7.3 R1：`ASTRA_SHAFT_SAMPLES` 7→12，`WATER_SHAFT_FAR_END` 26→18，4 点 Gauss → 段中点单采样，`entryRay` 归一化 | 正午浅水 + 斜阳深水各一张 | **柱内出现可辨纹理**；不应出现整屏发白 |
| **S2** | §7.3 R2+R5：相位 g 0.45→0.70、mix 0.4→0.92、入参改全局 | 同机位 + 朝光/背光对比 | 朝光明显变亮、侧向背向变暗；**不应抽动**（R5 应改善抽动） |
| **S3** | §7.2 R3：饱和 0.25→0.04 | 同机位对比 | 束内出现锐利明暗层次；**不应出现闪烁或爆点** |
| **S4** | §7.2 R4：窗格原点不掺水深 | 相机上下移动 2 格 | **光束不应整体平移/跳变** |
| **S5** | §7.2 R6 + §7.3 遮挡降频 + 双端点 | 帧率 + 同机位 | 细节不劣于 S3；**水下帧率不低于 S3** |
| **S6** | 调参：envelope 幂次、饱和系数、淡出曲线 | 三档 × 三机位 | 晴天更多更亮、近处可读、范围有限 |

**S1 是最关键的一步**，也是最能验证 R1 诊断的一步。若 S1 之后柱内纹理没有明显增加，说明根因判断有误，应回到 §2 重新归因，**不要继续往下调参**。

**每阶段都要记录**：机位、时间、档位、分辨率、帧率读数。没有读数的阶段不算完成。

---

## 9. 明确不做的事

避免又变成"在旧结构上打补丁"：

1. **不加回固定圆形入口、四水深聚光表、局部反求、逐格 DDA。** 这些已退出。"光束数量不够就加回发射点"是在掩盖根因。
2. **不加时域抖动/历史累积。** Astra 均衡档是 FXAA，水下无 TAA（见 [参考与取舍](参考与取舍.md)）。时域抖动在缺 TAA 时只表现为噪点。
3. **不靠积分步数实现"晴天更多更亮"。** 用 §7.2 的 envelope 幂次（成本为零）。
4. **不缩小窗格或加宽边界淡出来修"位置乱"。** 根因是原点掺水深（S4）。
5. **不把 ITT 的 `fract` 平铺搬回来。** 那是 ITT 掩盖窗口尺寸的权宜，Astra 有世界对齐图，不需要。
6. **不照搬 Solas 指数步进到水下光束。** 见 §4.1 分析：它在水下把预算浪费在过密的近端，同时远端足迹仍然过大。
7. **不动水下雾/深水遮蔽（W10/W11）与水面反射（W12）。** 本次只做 W04。
8. **不修改 `solas_water_composite` 的合成顺序。** 光束在线性域加在 `pow(...,2.2)` 之后，这个顺序是对的。

---

## 10. 数字复算过程（可复核）

所有数字由本机依据当前源码复算，脚本逻辑如下，可用 node 复现。

**（a）Mie 相位**（`Lib/Utilities.glsl:269-273`）：

```
g=0.45: fwd=0.51956  side=0.03278  back=0.02835   fwd/back=18.3   fwd/side=15.9
g=0.70: fwd=1.81100  side=0.01344  back=0.00995   fwd/back=182.0  fwd/side=134.7
```

Astra 现行（`mix(iso, dir, 0.4)`，`iso=1/4π=0.07957747`）：`fwd=0.25557, back=0.05909 → 4.33:1`
建议值（`mix(iso, dir, 0.92)`）：`fwd=1.67249, back=0.01552 → 107.75:1`

**（b）波面层频率**：按 `lib/itt_water_waves.glsl` 的 `itt_water_wave` 链条复算。每层的 `jacobian` 累积各层缩放，有效频率 `f = 64·max(|col0(T·J)|, |col1(T·J)|)`，其中噪声图 64×64（实测 PNG 头）。结果见 §3.4 表。

**（c）足迹 → 存活细节**：`resolved = 1 − smoothstep(0.5, 1.25, footprint·f)`（取自 `itt_wave_noise` 的 `resolved` 定义），按权重加权：

```
footprint  LOD    存活细节   存活层
0.93       1.90     24%     L6
0.65       1.38     41%     L6
0.50       1.00     62%     L5,L6
0.375      0.58     84%     L3,L4,L5,L6
0.313      0.32     90%     L3,L4,L5,L6
```

**（d）饱和影响**（`caustic = 5.6·|slope| + 0.2`，`e = caustic³`）：

```
|slope|  caustic   e=c³     k=0.25    k=0.04    ITT(无饱和)
0.05      0.48     0.1       0.11      0.11       0.1
0.10      0.76     0.4       0.40      0.43       0.4
0.15      1.04     1.1       0.88      1.08       1.1
0.25      1.60     4.1       2.02      3.52       4.1
0.40      2.44    14.5       3.14      9.19      14.5
0.60      3.56    45.1       3.67     16.09      45.1
0.90      5.24   143.9       3.89     21.30     143.9
```

k=0.25 时从 `|slope|=0.40` 起输出几乎不再增长（3.14 → 3.67 → 3.89），而 ITT 继续到 143.9。**这是"毫无质感"的数值证据。**

---

## 11. 与现有记录的关系

- 本文是**改动意见**，不是现状描述。落地前 [当前工作](当前工作.md) 的 W04 条目继续有效。
- 落地后需回写：`当前工作.md` 的 W04 行（新结构描述 + 实测读数）、[实现与限制](实现与限制.md) 的光束参数段、[参考与取舍](参考与取舍.md) 第 20 行的 ITT/Solas 分工描述。
- **需修正的既有表述**：[参考与取舍](参考与取舍.md) 与相关归档中若存在"ITT 大波峰波长 117/235 格"一类说法，源于把噪声图按 256 计算，应按 §1 更正为 0.71/1.58 格。此项不在本文直接改写别的文件，落地时一并处理。
- THIRD-PARTY 来源声明不变：ITT 3.2.0 提供波面/焦散/相位，Solas V2.2b 提供端点与距离组织参考。本文改动都在 Astra 自己的适配层内。
