# 细读 IterationT 3.2：雨滴全貌、黑洞自转、宇宙感的来源

> **背景资料**：本文是参考源码研读记录，用于说明设计依据。最终效果定义见 docs/2026-09-11-end-final-design.md。

前一份同名文档结论不完整（我只读了黑洞函数和一个 20 行的天气 fsh 就下了判断），已删除重写。
本文只做源码研读与落地规划，**未改任何渲染代码**。所有条目标注了具体文件与行号。

---

## 一、雨滴的全貌：ITT 是三层结构，我之前一层都没做对

### 1.1 雨幕的形状与运动 —— `Lib/Programs/Gbuffers/Weather_VS.glsl`（全文 31 行）

```glsl
vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
vec4 worldPos = gbufferModelViewInverse * viewPos;

float angle = dot(worldPos.xyz + cameraPosition.xyz, vec3(3.0, 0.5, 3.0)) + frameTimeCounter * 0.2;
vec2 rot = vec2(sin(angle), cos(angle));
vec2 offset = (vec2(RAIN_WIND_X, RAIN_WIND_Z) + rot * RAIN_DISTURBANCE) * worldPos.y;

worldPos.xz += eyeBrightnessOneSmooth * offset;
```

**这是整片雨幕的顶点位移**，三个要点：

1. `offset ∝ worldPos.y` —— 位移**与高度成正比**，所以雨幕是**被风切变斜的帘子**，不是直上直下的竖线；
2. `rot` 由 `dot(worldPos, vec3(3,0.5,3)) + time*0.2` 决定 —— 每个世界位置有**不同相位**，且**随时间旋转** → 雨幕内部有**湍流**，不是一片刚体；
3. 参数在 `Lib/Settings.glsl:206-208`：`RAIN_WIND_X 0.1`、`RAIN_WIND_Z 0.05`、`RAIN_DISTURBANCE 0.05`，三者都是用户可调滑条。

> 我此前只调了 FS 里的颜色和不透明度，**完全没有动几何**。所以"太整齐"的第二个原因在这里：我们的雨幕是竖直的规则栅格，而参考的雨幕本身是**斜的、带湍流的**。

### 1.2 形状与颜色 —— `Weather_FS.glsl`（全文 20 行）

```glsl
vec4 tex = texture(tex, texCoord);
if (tex.a < 0.1) discard;
gbufferOutput0 = vec4(0.0, 0.0, 0.0, tex.a);
```

- 形状完全用原版 `assets/minecraft/textures/environment/rain.png`
- 输出**纯黑**，雨是"让背景变暗的水幕"

**原版纹理实测**（我解包量的）：64×256，**不透明像素仅 2.5%**，竖向雨丝长度 p10=1 / p50=2 / p90=9 / **max=16**。**原版本身就又稀疏又错落**——用它就对了。

### 1.3 落点涟漪 —— `Lib/IndividualFounctions/Ripple.glsl`

```glsl
vec2 coord = vec2(pos.x, fract(pos.z / 60.0) - frame);      // 世界空间平铺
float rp = 2.0 - (wet2 * wet2) * 1.2;                        // 湿度越高涟漪越柔
vec2 n1 = GetRainAnimationTex(gaux1, coord, rp);
vec2 n2 = GetRainAnimationTex(gaux2, coord, rp);
vec2 n3 = GetRainAnimationTex(gaux3, coord, rp);
n += n2 * saturate(downfall * 2.0);                          // 三层按雨量递进混合
n += n3 * saturate(downfall * 2.0 - 1.0);
n /= lod * 5.0 + 1.0;                                        // 距离衰减
wet = saturate(mix(downfall, wet, 1.0 - 0.4 * saturate(strength)));
```

- 涟漪是**预制 flipbook**，不是程序化噪声：`texture/RippleAnimation1/2/3.png`，各 **128×7680**（= 60 帧 ×128×128，带 `.mcmeta` 动画元数据）
- `frame = fract(floor(frameTimeCounter * 60.0) / 60.0)` —— **逐帧步进**（每秒 60 步），不是连续滚动
- 三层按 `downfall` 遮罩递进：小雨只有第一层，大雨三层叠加
- 湿度越低涟漪越锐（`rp`），并回写 `wet`

### 1.4 湿度与湿润表面 —— `Lib/Programs/Gbuffers/Terrain_FS.glsl:276+`

```glsl
float wet = wetness * (1.0 - eyeSnowySmooth) * (1.0 - eyeNoPrecipitationSmooth) + SURFACE_WETNESS;
wet *= saturate(abs(materialIDs - MATID_LAVA - 0.5) - 0.5);   // 排除熔岩/火
wet *= step(0.9, blockLight.y);                                // 需要天光
wet *= GetModulatedRainSpecular(mcPos);                        // 3D 噪声调制镜面
if (splashStrength > 0.0) rainNormal = GetRainNormal(mcPos, splashStrength, wet);
```

### 1.5 结论：我们与参考的差距

| 层 | ITT | 我们现状 |
|---|---|---|
| 雨幕几何 | VS 里按高度风切变 + 随时间旋转的湍流 | **无位移**，竖直规则栅格 |
| 形状 | 原版 `rain.png`（2.5% 覆盖、长短 1~16） | 程序化栅格（我上一轮重写的） |
| 颜色 | **纯黑**（致暗） | 灰色 0.62（仍发亮） |
| 落点涟漪 | 三张 60 帧预制 flipbook + 逐帧步进 | 程序化噪声环（`astra_puddle_normal`） |
| 湿度 | 累积 + 镜面调制 + 排除熔岩 | 有 `wetness` 但未接涟漪 |

**移植清单**：① 恢复原版 alpha + 近黑输出；② 在 `lit.vsh` 的 weather 分支加风切变位移（用 `RAIN_WIND_*`）；③ 涟漪改接 flipbook（需要引入三张 128×7680 贴图，约 6.7 MB）。

---

## 二、黑洞自转：参考的机制是"坐标缩放 + 噪声平移"，不是我加的开普勒项

`Lib/IndividualFounctions/EndSky.glsl:126-136`：

```glsl
#ifdef ACCRETIONDISC_DETAIL_ALONG_LONGTITUDE
    vec3 discCoord = vec3(r, p * (1.0 - radialGradient * 0.5), h * 0.1) * 3.5;
    float fbm = CalculateCloudFBM(discCoord, frameTimeCounter * vec3(0.1, 0.07, 0.0));
#else
    vec3 discCoord = vec3(r, 0.0, h * 0.1) * 3.5;
    float fbm = CalculateCloudFBM(discCoord, frameTimeCounter * vec3(0.03, 0.05, 0.0));
#endif
```

- `p` 是方位角，被 **`(1 - radialGradient * 0.5)` 按半径缩放**（内圈 0.5 → 外圈 1.0）
- 噪声场以 `frameTimeCounter * vec3(0.1, 0.07, 0)` **持续平移**（0.1 沿半径、0.07 沿方位）
- **同一份噪声平移量，除以更小的缩放系数 = 更大的角速度 → 内圈转得更快**。差速自转是坐标缩放**自然带出来**的，不需要额外的物理项
- 另有 `ACCRETIONDISC_DOPPLER_EFFECT`（`glow *= sin(p - 1.07) * 0.75 + 1.0`）

**这解释了为什么参考默认把 `ACCRETIONDISC_DETAIL_ALONG_LONGTITUDE` 关着**：关掉时 `discCoord.y = 0`，噪声里**根本没有方位角**，看起来是"静态纹理"；打开才有旋转。

我上一轮加了 `pow(r, -1.5)` 的显式开普勒项——**那是我的发明，不是参考的做法**。应当改为照抄上面这条分支。

另外注意：`mat3 rotation = RotateMatrix(0.1, 0.0, -0.35)` 是**常量**——参考里黑洞本体**不翻滚**，转的是盘内物质。所以"自转"= 物质环流，不是天体转向。

---

## 三、宇宙感的来源：ITT 的末地有**两个**天体，我之前漏了整个"行星系统"

`Lib/IndividualFounctions/EndSky.glsl` 里有两个独立的渲染函数：

### 3.1 黑洞 `BlackHole_AccretionDisc_Stars`（锚定在光方向）

`world1/composite.fsh:246` 调用：

```glsl
if (materialMaskSoild.sky > 0.5){
    finalComposite = vec3(0.0);
    BlackHole_AccretionDisc_Stars(finalComposite, worldDir, worldShadowVector);
    PlanetEnd2(finalComposite, vec3(0.0), worldDir, worldSunVector);
}
```

注意 `lightDir = worldShadowVector` —— **黑洞锚定在阴影光方向**，所以地形影子永远和它一致。

### 3.2 **带环行星** `PlanetEnd2`（这才是"公转"的来源）

`EndSky.glsl:82-95`：

```glsl
float angleX = -1.57079633 + (0.2 * sin(timeFactor + 3.0) - 0.1);   // 轴倾角缓慢摆动
float angleY = timeFactor;                                          // 公转/自转相位
mat3 eyeRoataionMatrix = eyeRoataionMatrixX * eyeRoataionMatrixY;
float ringAngle = 0.008 * sin(timeFactor + 4.6);                    // 环面摆动
```

周期在 `Lib/Settings.glsl:224`：

```glsl
#define END_PLANET_CYCLE 15.0 // [0.25 0.5 0.75 1.0 1.5 2.0 3.0 5.0 7.5 10.0 15.0 20.0 30.0 60.0]
```

`EndSky.glsl:6` 的换算：

```glsl
float timeFactor = fract(frameTimeCounter * ((1.0 / 60.0) / END_PLANET_CYCLE) + 0.282) * TAU;
```

**`END_PLANET_CYCLE` 的单位是分钟**：默认 **15 分钟一圈**，可选 0.25～60 分钟。
（`END_MANUAL_PLANET_CYCLE` / `END_MANUAL_PLANET_ANGLE` 可以手动定格相位，便于截图。）

行星本体的实现要点：

| 部件 | 做法 |
|---|---|
| 行星球体 | `Rground = 20e6`，`RaySphereIntersection` 求交 |
| 大气层 | `Ratmo = 20.1e6`，`MiePhaseFunction(0.8, VdotL)` 散射，厚度² 加权 |
| 地表着色 | `ppss()` 物理着色，反照率 `vec3(0.98,0.87,0.55)`（沙黄色） |
| **行星环** | `ringRadius = vec2(1.6, 2.6)`，环面上做 5 阶 FBM 噪声结构 |
| **环上的行星影** | `Disc(UdotN,...)` / `Disc(DdotN,...)` / `Disc(OLdotN,...)` 三个圆盘函数组合出「行星挡光的影带」 |
| 光晕 | `ring *= 1.0 + mie * 10.0 * planetShadow` |

### 3.3 `planetShadow`：公转如何影响世界

```glsl
float planetShadow = smoothstep(0.62, 0.35, timeFactor) + smoothstep(1.6, 1.87, timeFactor);
```

只用在**末地雾**上（`EndFog`，`EndSky.glsl:547-549`）：

```glsl
density *= MiePhaseFunction(0.3, VdotL) * 10.0 * planetShadow + 0.25;
density *= planetShadow * 0.93 + 0.07;
```

**所以"公转带动明暗变化"在参考里是这样实现的：行星公转到特定相位时，末地雾的密度/散射显著改变（相当于"我们被行星的影子扫过"），而不是去旋转阴影贴图。**

### 3.4 星场三种样式

`Lib/Settings.glsl:213`：`STAR_TYPE 1 // [0 1 2]`。`EndSky.glsl:420` 用 `#if STAR_TYPE > 0` 决定是否走 `CalculateStars`；`Skybasic_FS.glsl:16` 里 `#if STAR_TYPE < 2 discard`（即 TYPE 2 时星空改由原版/其他路径绘制）。

---

## 四、修正后的"宇宙感"要素表（我之前漏掉的是整块第 ② 行）

| 层 | 参考提供的 | 我们现状 |
|---|---|---|
| ① 背景 | 黑体色温星场（`STAR_TYPE` 三样式）+ 黑洞透镜 | ★ 已移植（部分透镜） |
| ② **行星系统** | **带环行星**：球体 + 大气散射 + 环 + 环上的行星影 + 15 分钟公转 | **✗ 完全没有** |
| ③ 主天体 | 黑洞：事件视界 + 光子环 + 吸积盘 + 多普勒 + 差速自转 | ★ 大部分已有 |
| ④ 天体力学 | `timeFactor` 驱动的公转/轴倾摆动/环面摆动；`planetShadow` 调制雾 | ✗ |
| ⑤ 光照互动 | 黑洞锚定光方向（影子一致）；行星影调制雾 | ☆ 只有锚定 |
| ⑥ 后处理 | bloom（已接）、`NETHER_END_BLOOM_BOOST` | ★ |

**一句话**：参考的"宇宙感"不是"一个黑黑洞"，而是**一个有行星系统的星系**——大小两个天体、各自的自转与公转、以及公转对环境的调制。

---

## 五、落地建议（按参考的实现方式，分三步）

| 步骤 | 内容 | 依据 |
|---|---|---|
| **第 1 步：雨滴照参考重做** | ① FS 改回"原版 alpha + 纯黑"；② VS 加风切变位移（`RAIN_WIND_*`）；③ 涟漪接 flipbook（三张 128×7680，6.7 MB） | §1 |
| **第 2 步：黑洞自转改回参考机制** | 撤掉我加的 `pow(r,-1.5)`，改用 `ACCRETIONDISC_DETAIL_ALONG_LONGTITUDE` 分支（`p*(1-rg*0.5)` + `shift vec3(0.1,0.07,0)`） | §2 |
| **第 3 步：移植 `PlanetEnd2` 行星系统** | 球体 + 大气 + 环 + 环上行星影 + `END_PLANET_CYCLE`（默认 15 分钟，可选 0.25～60）；`planetShadow` 接入末地雾 | §3 |

**关于"公转 + 影子跟着转方向"**，参考给的是另一种答案，需要你确认取哪一种：

- **参考的做法**：黑洞锚定光方向（地形影子永远和它一致），**行星**独立公转、通过 `planetShadow` 调制末地雾的明暗。地形影子的**方向**不随行星改变。
- **如果你要"地形影子方向也随天体转"**：那等于让该天体成为光源，方向由引擎的世界时间决定（约 20 分钟一圈，光影无法独立减慢）。参考没有这样做。

我建议按参考的三步走。**请确认是否照此执行**，以及涟漪 flipbook（+6.7 MB）是否接受。
