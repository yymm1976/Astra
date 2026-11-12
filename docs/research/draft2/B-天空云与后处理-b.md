# B 方向研究笔记：天空 / 云 / 大气 / 雾 / 体积光 / 后处理与时域

> 只读研究。结论全部来自本机外部源码副本与本仓库 Astra 源码的逐行阅读。
> **证据强度标记**：`[源码]` = 读到实现并确认执行路径；`[推断]` = 依据源码静态推断，可能被编译器/默认配置改变，或未验证运行时开销；`[未验证]` = 没有证据。
> 不写任何 FPS / 毫秒 / 百分比收益；只描述减少了哪一类 GPU 工作（pass 数、分辨率、每像素采样、带宽）。

---

## 0. 引用坐标与默认配置前提

- photon：`sixthsurge/photon`，分支 `main`，commit `5c79f54`，路径前缀 `shaders/`。
- cr：`ComplementaryReimagined`，分支 `main`，commit `c09950d`，路径前缀 `shaders/`。
- solas：`Solas-Shader`，分支 `main`，commit `ea1b4db`，路径前缀 `shaders/`。
- piscium：`Alpha-Piscium`，分支 `main`，commit `f2401e9`，路径前缀 `shaders/`。
- bliss：`Bliss-Shader`，分支 `Stable`，commit `81e403e`，路径前缀 `shaders/`。

**默认配置前提（每条结论都依赖它，先单独列出）**：photon 的 `settings.glsl:201` 默认把云时域升采样开到 4×，`settings.glsl:207-210` 默认主步进 40(地平线)/20(天顶)、光照步 6、环境步 2：

```glsl
shaders/settings.glsl:201
  #define CLOUDS_TEMPORAL_UPSCALING 4 // [1 2 3 4]
shaders/settings.glsl:207-210
  #define CLOUDS_CUMULUS_PRIMARY_STEPS_H 40 // [1 2 3 4 ...（此处为 Iris 滑条枚举，原文把 1..64 全部列出，引用时截断）
  #define CLOUDS_CUMULUS_PRIMARY_STEPS_Z 20 // [1 2 3 4 ...（同上，截断）
  #define CLOUDS_CUMULUS_LIGHTING_STEPS 6 // [1 2 3 4 5 6 7 8 9 10 11 12]
  #define CLOUDS_CUMULUS_AMBIENT_STEPS 2 // [1 2 3 4]
```

`[源码]` 因此 photon 的云 pass 实际只覆盖 1/16 像素（4×4 棋盘格），其余 15/16 靠历史重建 —— 后面第 1 条的技术点就是围绕这个前提成立的。

---

## 1. Photon 云：1/16 分辨率主渲染 + 4×4 棋盘格时域重建（清晰度靠重建，不靠模糊）

**技术目标**：在不降低云边缘清晰度的前提下把主 raymarch 的像素数降到 1/16，同时避免"低分辨率 + 双线性放大"必然带来的糊边。

**实现位置**

```glsl
shaders/program/d1_clouds.fsh:128-129
const int checkerboard_area
    = CLOUDS_TEMPORAL_UPSCALING * CLOUDS_TEMPORAL_UPSCALING;

shaders/program/d1_clouds.fsh:161-162
    ivec2 checkerboard_pos = CLOUDS_TEMPORAL_UPSCALING * texel
        + clouds_checkerboard_offsets[frameCounter % checkerboard_area];

shaders/shaders.properties:329-331
#elif CLOUDS_TEMPORAL_UPSCALING == 4
size.buffer.colortex9  = 0.25 0.25
size.buffer.colortex10 = 0.25 0.25
```

**算法机制**（`[源码]`）

1. 主 pass `d1_clouds` 的每个片元不在自己的像素上算，而是先算一个 `checkerboard_pos`：把屏幕坐标乘以 4，再加上本帧的 4×4 棋盘格子偏移（偏移表在 `include/utility/checkerboard.glsl:32-49`），归一化回 `[0,1]` 后作为这一帧真正要跟踪的射线方向。也就是说相邻 16 个像素在 16 帧里轮流各自被真正 raymarch 一次。
2. 主 pass 写 1/4 分辨率图（`colortex9`，RGBA16F）+ 每像素元数据（`colortex10`，RG16F：视距、环境散射）。
3. 全分辨率 pass `d2_clouds_upscaling` 做重建：对每个全分辨率像素，先 `texelFetch` 自己那 1/4 分辨率的源 texel；再按 4×4 区域取"最近的云距离"并做一次重投影（`program/d2_clouds_upscaling.fsh:260-263`、`279`）。
4. **不做双线性放大**：历史用 Catmull-Rom 取（`d2_clouds_upscaling.fsh:291-295`）；当这一帧的棋盘格相位与本像素不匹配时，直接整块用历史（`d2_clouds_upscaling.fsh:367-374`）。

```glsl
shaders/program/d2_clouds_upscaling.fsh:367-371
    ivec2 offset_0 = dst_texel % CLOUDS_TEMPORAL_UPSCALING;
    ivec2 offset_1
        = clouds_checkerboard_offsets[frameCounter % checkerboard_area];
    if (offset_0 != offset_1 && !disocclusion) {
        current = history;
```

**开销与代价**（`[源码]` + `[推断]`）

- pass 数：云从 1 个全分辨率 raymarch pass 变成 2 个（1/16 raymarch + 1 个全分辨率重建）。`[源码]`
- 主 raymarch 的像素数降为 1/16；每像素采样次数不变（40/20 步 × 每步 1 次密度 + 命中时 6 次光照 + 2 次环境）。`[源码]` 因此 GPU 侧的"密度函数调用总数"约为原来的 1/16（`[推断]`，未实测）。
- 代价一：**历史必须存在**。全分辨率历史缓冲 `colortex11`（RGBA16F）+ 元数据 `colortex12`（RGB16F），两者都是全分辨率，带宽成本没有降。`[源码]` `include/buffers.glsl:15-16`。
- 代价二：重建需要每像素 4 次 `textureGather` 求 4×4 最小值（`d2_clouds_upscaling.fsh:109-133` 的 `texture_min_4x4`）。`[源码]`
- 代价三：云移动时必须有"速度感知"的重量裁剪，否则薄云会被拖尾。见下一条。

**适用范围与失效边界**

- 棋盘格 + 重投影只对"屏幕空间能表达的运动"有效。云在射线方向上推进（沿射线移动）无法被 2D 重投影抵消；photon 的做法是在重建时把云的世界速度算进去（`d2_clouds_upscaling.fsh:184-185` 把 `velocity * frameTime` 加回云位置），依赖 `daylight_cycle_enabled`。`[源码]`
- `world_age_changed`（世界时间跳变，如 `/time set`）会强制丢弃历史（`d2_clouds_upscaling.fsh:317`）。`[源码]`

**与 Astra 的关系**

Astra 已有类似结构但分辨率策略不同：`program/cloud_screen.fsh` 在 High 档是对**同一像素打 4 条子像素射线**，而不是降分辨率 + 时域重建：

```glsl
Astra/shaders/program/cloud_screen.fsh:51-53
    for (int sampleIndex=0;sampleIndex<4;++sampleIndex) {
        vec2 offset=vec2((sampleIndex & 1)==0 ? -0.25 : 0.25,
                         (sampleIndex & 2)==0 ? -0.25 : 0.25)*texel;
```

也就是说 Astra 现在用 4 倍采样换清晰度，没有用 1/16 采样 + 重建换性能。photon 这条路径是 Astra 云清晰度与成本之间**尚未使用的另一个极点**。

---

## 2. Photon 云 raymarch：步长按视角分档、不跳空、提前退出靠透射率

**技术目标**：在"不把云糊掉"的约束下减少无效步进。

**实现位置**

```glsl
shaders/include/sky/clouds/cumulus.glsl:220-222
    uint primary_steps = uint(
        mix(primary_steps_horizon, primary_steps_zenith, abs(ray_dir.y))
    );

shaders/include/sky/clouds/cumulus.glsl:255
    float step_length = ray_length * rcp(float(primary_steps));

shaders/include/sky/clouds/cumulus.glsl:280-283
    for (uint i = 0u; i < primary_steps; ++i) {
        if (transmittance < min_transmittance) {
            break;
        }
```

**算法机制**（`[源码]`）

- 步数在天顶与地平线之间按 `|ray_dir.y|` 线性插值（地平线 40、天顶 20，默认配置）；步长 = 区间长度 / 步数（等距，不增长）。注意与 `clouds_cumulus_optical_depth`（`cumulus.glsl:117-133`，`step_growth = 2.0` 的增长步长）区分：**主步进等距，光照步进递增**。
- 空样本不加速：`if (density < eps) { continue; }`（`cumulus.glsl:292-294`），步长不变。`[源码]` 即 photon 没有做"空区域跳跃"，只做了"空样本不付光照成本"。
- 唯一的提前退出是透射率下限 `min_transmittance = 0.075`（`cumulus.glsl:211`），命中后透射率一旦低于它就 break，最后再把透射率重新映射到 0（`cumulus.glsl:364-365`）。`[源码]`
- 远处的密度淡出用来掩盖最大射线长度截断（`cumulus.glsl:296-299`）。`[源码]`

```glsl
shaders/include/sky/clouds/cumulus.glsl:296-299
        // Fade away in the distance to hide the max ray length cutoff
        float distance_to_sample = distance(ray_origin, ray_pos);
        density
            *= smoothstep(1.0, 0.95, distance_to_sample * rcp(max_ray_length));
```

**开销与代价**

- 每步固定 1 次 3D noise 采样（`cumulus.glsl:80-83`：两张 3D worley 纹理，`0.0009` 与 `0.005` 两个尺度），命中后每步再加 6 次光照步 × 1 次密度 + 2 次环境步 × 1 次密度。`[源码]`
- 地平线视线最多 40 步 × (1 + 6 + 2) 次密度查询的最坏情况 = 360 次密度函数调用/像素（每像素 1~2 次 3D 纹理取）。`[推断]` 这是"最坏"，实际因为 `min_transmittance` 提前退出会低于此值。
- 没有空区域跳过意味着"看天空全是云缝"时成本与"全是云"几乎相同 —— 这是 photon 用 1/16 分辨率去摊平这块成本的原因。`[推断]`

**适用范围与失效边界**

- 等距步长在极长的地平线射线上会欠采样；photon 用 `max_ray_length = 2e4`（`cumulus.glsl:210`）+ 距离淡出来遮断，不是靠自适应步长解决。`[源码]`

**与 Astra 的关系**

Astra 走的是"分段 + 区间端点二分"路线，不是等距密集采样：

```glsl
Astra/shaders/global/atmosphere/clouds_planar.glsl:292-297
    #elif CLOUD_QUALITY == 0
    int sampleCount = clamp(int(ceil(planeDistanceDif/48.0)),4,12);
    #elif CLOUD_QUALITY == 2
    int sampleCount = clamp(int(ceil(planeDistanceDif/4.0)),4,512);
    #else
    int sampleCount = clamp(int(ceil(planeDistanceDif/32.0)),6,16);
```

并且 Astra 的 High 档用一个线性插值的占用区间来避免"整段冻结"（`clouds_planar.glsl:345-347`）：

```glsl
Astra/shaders/global/atmosphere/clouds_planar.glsl:345-347
        float occupiedStart = startSigned < 0.0 ? -startSigned/(endSigned-startSigned) : 0.0;
        float occupiedEnd = endSigned < 0.0 ? startSigned/(startSigned-endSigned) : 1.0;
        float occupiedMiddle = 0.5*(occupiedStart+occupiedEnd);
```

结论：Astra 的分段占用区间在"少采样"这一点上已经比 photon 的等距 40 步更省；photon 值得借鉴的不是步长，而是它把**相位/抖动固定**住（Astra 也做了，见 `clouds_planar.glsl:281` 的 `marchOffset = 0.5`）以及**每像素龄选 mip**（下一条）。

---

## 2b. Photon 云读取：按"像素龄"选择噪声 mip（新像素更模糊、老像素更清晰）

**技术目标**：刚出现的像素没有历史可借，直接显示全分辨率云会闪；老像素已经稳定，再用模糊的 mip 就是白白损失清晰度。

**实现位置**

```glsl
shaders/include/sky/clouds/sampling.glsl:7-14
    // Soften clouds for new pixels
    float pixel_age
        = texelFetch(colortex12, ivec2(uv * view_res * taau_render_scale), 0).y;
    float ld = 2.0 * dampen(max0(1.0 - 0.1 * pixel_age));

    apparent_distance
        = min_of(textureGather(colortex12, uv * taau_render_scale, 0));
    vec4 result = textureLod(colortex11, uv * taau_render_scale, ld);
```

**算法机制**（`[源码]`）

- `pixel_age` 从云历史缓冲 `colortex12` 的 y 通道读出（这个值由 `d2_clouds_upscaling.fsh:393` 的 `min(++pixel_age, CLOUDS_ACCUMULATION_LIMIT)` 维护，上限 20）。
- `ld` 是 mip 层级：像素龄 0 时 `dampen(1.0) = 1.0`，`ld = 2.0`（最糊）；像素龄 ≥ 10 时 `dampen(0) = 0`，`ld = 0`（全清晰）。中间是连续过渡。
- `dampen(x) = x * (2.0 - x)`（`include/global.glsl:144-147`）是一个"接近 sqrt 但更便宜"的曲线形状，避开了 `sqrt` 指令。
- 关键点：**模糊只作用于新像素**，而新像素本来就在时域上还没收敛，看得见的时间只有几帧。老像素用的是 `textureLod(..., 0.0)`，清晰度一点不丢。

**开销与代价**

- 每像素多 1 次 `texelFetch` 读像素龄 + 1 次 `textureGather` 读 4 个视距。`[源码]`
- `textureLod` 带显式 mip，需要 `colortex11` 有 mip 链；这是固定成本，不随像素变化。`[推断]`

**适用范围与失效边界**

- 像素龄靠历史累积，历史被拒（disocclusion）时会重置，于是该像素"永远年轻"、永远用最糊的 mip。photon 的做法是把 disocclusion 的像素直接 `history = current`（`d2_clouds_upscaling.fsh:320-323`），所以它们本来就只看当前帧，模糊影响有限。`[源码]` + `[推断]`
- `CLOUDS_ACCUMULATION_LIMIT` 默认 20（`settings.glsl:203`），即最多 20 帧后不再增长。`[源码]`

**与 Astra 的关系**

Astra 的云历史权重是**固定常数**，不随像素龄变化：

```glsl
Astra/shaders/global/atmosphere/cloud_temporal.glsl:48-52
#if CLOUD_QUALITY == 2
const float ASTRA_CLOUD_TEMPORAL_WEIGHT = 0.75;
#else
const float ASTRA_CLOUD_TEMPORAL_WEIGHT = 0.90;
#endif
```

`cloud_temporal.glsl` 里没有任何"像素龄/累积帧数"概念，权重只按亮度变化、覆盖率跳变、运动量三项衰减（`cloud_temporal.glsl:214-217`）。photon 的像素龄 mip 是 Astra 可以叠加的独立一层：它不改权重，只改"读历史时用多清楚的版本"。

---

## 3. Photon 云多重散射：8 次迭代，零额外纹理采样

**技术目标**：在只有单次散射光程（1 条光照步进链）的前提下，得到"厚云内部有多次散射的柔光"，且不增加任何纹理采样。

**实现位置**

```glsl
shaders/include/sky/clouds/cumulus.glsl:164-167
    for (uint i = 0u; i < 8u; ++i) {
        scattering.x += scatter_amount
            * exp(-extinct_amount * light_optical_depth) * phase
            * (1.0 - 0.5 * clouds_params.l0_shadow);

// （此处省略中间三项，原文 168-177 行，结构与上面同形）
shaders/include/sky/clouds/cumulus.glsl:178-184
        scatter_amount *= scattering_falloff * powder_effect;
        extinct_amount *= 0.4;
        phase_g *= 0.8;

        powder_effect = mix(powder_effect, sqrt(powder_effect), 0.5);

        phase = clouds_phase_multi(cos_theta, phase_g);
    }
```

**算法机制**（`[源码]`）

- 输入只有三样：单次散射光程 `light_optical_depth`（6 步光照步进的积分）、天空方向光程 `sky_optical_depth`（2 步）、地面反弹的估算光程 `ground_optical_depth`（解析式，`cumulus.glsl:334-336`，不需要额外采样）。
- 循环里每轮对这三条光学深度用**衰减后的**消光系数重新求 exp，同时把散射系数、相位不对称因子 g、粉末效应都按固定比例缩小/收敛。这是经典的"八度多重散射"（octave / energy approximation）：不改采样，只改权重。
- 相位每轮换成不同的 g（`clouds_phase_multi`，`common.glsl:71-78`，0.65/0.10/0.25 三瓣），模拟多次散射后的近各向同性。
- 作者在代码里明确写了这是"看起来对"而不是物理正确：`common.glsl:66-67` 注释 `// forwards lobe (max'ing them is completely nonsensical but it looks nice)`。`[源码]`

**开销与代价**

- 每命中样本 8 次循环，每次 3~4 个 exp + 1 次相位函数求值，**0 次纹理采样**。`[源码]`
- 相比"再加 8 步光照光线追踪"，省掉的是每样本 8 次密度查询（每次 2 张 3D 纹理取）。`[推断]` 这是"纯 ALU 换采样带宽"的典型交易，在采样受限的云 shader 里通常划算。`[推断]`

**适用范围与失效边界**

- 第 3 项（`scattering.x += ... * clouds_params.l0_shadow * 0.5`，`cumulus.glsl:171-174`）是"上一层云的假反弹光"，纯艺术项，不是物理。`[源码]`
- `extinct_amount *= 0.4` 让厚度超过约 3 个光学深度后不再变暗，所以极厚的云会偏亮；这是刻意的艺术取舍。`[源码]` + `[推断]`

**与 Astra 的关系**

Astra 的云**没有**多重散射八度循环。Astra 的云光照是两次 2D 密度采样（`clouds_planar.glsl:501-505`）：

```glsl
Astra/shaders/global/atmosphere/clouds_planar.glsl:501-505
		cLightPos += (1.0 + gradientNoise) * cLightPosAdd;
		    light -= (unshiftedLight ? coarseSample : astra_2d_cloud_sample(cLightPos.xz)) * cloudShadingM;
		cLightPos += gradientNoise * cLightPosAdd;
		    light -= (unshiftedLight ? coarseSample : astra_2d_cloud_sample(cLightPos.xz)) * cloudShadingM;
```

Astra 低/中档已经把它压到 1 次采样（`clouds_planar.glsl:498-499`）。所以 Astra 的云现在只有"亮面/暗面"，没有厚云内部的柔光。photon 这条 **8 次迭代 0 采样** 的做法是 Astra 可以直接加而不增加纹理带宽的一项（只需 ALU）。

---

## 4. Photon 云影贴图与体积光（crepuscular rays）：同一张 512² 云影图两用

**技术目标**：地面云影 + 天空光柱共用一张低分辨率云影图，避免各自重新 raymarch 云。

**实现位置**

```glsl
shaders/include/lighting/cloud_shadows.glsl:7-9
const ivec2 cloud_shadow_res = ivec2(512);

const float cloud_shadow_extent = 256.0 / (CLOUDS_SCALE / 10.0);

shaders/include/lighting/cloud_shadows.glsl:94-97
    shadow *= exp(
        -1.00 * distance_fade * extinction_coeff * clouds_cumulus_thickness
        * rcp(abs(light_dir.y) + eps) * density
    );
```

**算法机制**（`[源码]`）

1. prep pass `p0_clouds_prep` 在 512×512 上，沿光线方向在云层球壳取**一个**密度样本（`cloud_shadows.glsl:85-93`），然后用 `exp(-密度 × 厚度 / cos(仰角))` 直接得到透射率 —— 只有一个样本，不做光线步进。
2. 投影用 `x/(1+|x|)` 的立体角式畸变（`cloud_shadows.glsl:11-17`），让玩家附近分辨率更高。
3. 地面云影：双三次过滤采样（`cloud_shadows.glsl:55`），并按"是否在云层下方 / 太阳是否近地平线"淡出（`cloud_shadows.glsl:48-56`）。`[源码]`
4. 体积光 `draw_crepuscular_rays`：沿视线 20 步（地平线）/ 4 步（天顶），**每步只查这张云影图**（`crepuscular_rays.glsl:96-104`），不查密度场、不查阴影贴图。

```glsl
shaders/include/sky/crepuscular_rays.glsl:96-99
        float cloud_shadow = dot(
            texture(
                cloud_shadow_map,
                shadow_view_to_cloud_shadow_space(ray_position_shadow)
```

**开销与代价**

- prep：512×512 = 262144 个像素，每像素 1 次 3D noise 采样（云层）+ 1 次 2D 覆盖率采样。相比 1920×1080 全屏步进，这是 1/8 的像素量，且每像素只要 1 个样本。`[推断]`（像素数按 512² 与 1080p 比，`[源码]`）
- 体积光：每像素 20 步 × 1 次 2D 纹理取 = 20 次采样/像素（地平线方向）。`[源码]` 这是全分辨率、全屏的，因此是这条链里最贵的一环；photon 只在 `WORLD_OVERWORLD` 且未用 BLOCKY_CLOUDS 时开启（`d1_clouds.fsh:118-120`、`233-242`）。
- 存储：一张 512² RGB8 的 2 通道云影图。`[源码]` `include/buffers.glsl:12`

**适用范围与失效边界**

- 单样本云影 = 云影边缘由双三次过滤决定，不代表真实体积遮挡；太阳越低 `1/|light_dir.y|` 越大，云影被拉得越长越软，photon 用 `pulse(light_dir.y, -0.01, 0.2)` 在太阳近地平线时整体淡出（`cloud_shadows.glsl:81`）。`[源码]`
- 云影图不随太阳方向刷新，只随相机；因此快速改变时间（`/time set`）时云影会有一帧延迟。`[未验证]`

**与 Astra 的关系**

Astra 已有同构的缓存：`global/atmosphere/cloud_shadow_cache.glsl`，同样是"锚点 + 拉伸 + 边缘回退到实时求值"：

```glsl
Astra/shaders/global/atmosphere/cloud_shadow_cache.glsl:34-43
        vec2 uv = (hit.xz-astra_cloud_shadow_anchor())/ASTRA_CLOUD_SHADOW_EXTENT+0.5;
        // Express the border in actual texels, including non-square grids.
        vec2 border = min(uv,1.0-uv)*vec2(textureSize(colortex14,0));
        float edge = min(border.x,border.y);
        // Do not clamp a world-space query to the map edge: use the actual field there.
        if (edge <= 0.5) return astra_cloud_plane_transmission(hit);
        float cached = textureLod(colortex14,uv,0.0).r;
        if (edge >= 8.0) return cached;
        float weight = smoothstep(0.5,8.0,edge);
        return mix(astra_cloud_plane_transmission(hit),cached,weight);
```

但 Astra 的屏幕体积光是另一套：`global/post/godrays.glsl`（来自 Steadfast 的屏幕径向 godrays）与 `global/water/light_shafts.glsl`。Astra **没有**"沿视线步进并逐步查云影图"的水晶光柱实现 —— photon 的 `crepuscular_rays` 是 Astra 在"云影图已存在"的前提下可以低成本补上的一层。

---

## 5. Photon 大气：预烘 32×64×32 的 3D 散射 LUT，双光源 4 次采样

**技术目标**：把大气散射从"每像素 raymarch"降到"4 次 3D 纹理取"。

**实现位置**

```glsl
shaders/shaders.properties:408
texture.deferred.depthtex0 = image/atmosphere/scattering.dat TEXTURE_3D RGB16F 32 64 32 RGB HALF_FLOAT

shaders/include/sky/atmosphere.glsl:25-26
const ivec2 transmittance_res = ivec2(/* mu */ 256, /* r */ 64);
const ivec3 scattering_res = ivec3(/* nu */ 16, /* mu */ 64, /* mu_s */ 32);
```

**算法机制**（`[源码]`）

- 散射 LUT 是**离线烘焙的 RGB16F 3D 纹理**，32×64×32，作为 `sampler3D` 绑定到 `depthtex0`（与深度复用同一槽位，靠 `texture.deferred.depthtex0` 覆盖绑定）。运行时只做参数映射 + 采样。
- 一个 3D 纹理里塞了两半：u.x ∈ [0,0.5] 是 Rayleigh + 多次散射，u.x ∈ [0.5,1] 是 Mie 单次散射，后者乘上相位函数（`atmosphere.glsl:293-301`）。`[源码]`
- 双光源（太阳 + 月亮）各 2 次采样 = 4 次 3D 纹理取（`atmosphere.glsl:483-486`），代码注释明确写"避免重复计算"（`atmosphere.glsl:316-317`）。`[源码]`
- 参数映射用 Bruneton 2020 的解析式（`atmosphere.glsl:121-159` 保留完整许可证原文，`atmosphere.glsl:183-274`），并对 `mu > 0` 做 `mu *= sqrt(sqrt(mu))` 的拉伸，把地平线附近的采样密度让给人眼（`atmosphere.glsl:368-370`）。`[源码]`
- 有第二条路径：不定义 `ATMOSPHERE_TRANSMITTANCE_LUT` 时用 Chapman 函数解析近似（`atmosphere.glsl:538-568`），只做 exp，不采样。`[源码]`

**开销与代价**

- 运行时：每次天空求值 4 次 3D 采样（RGB16F，无 mip 但开了 `blur: true`/`clamp: true`，`image/atmosphere/scattering.dat.mcmeta`）。`[源码]`
- 离线：3D 纹理固定 32×64×32×3 通道×2 字节 ≈ 393KB（实测文件 393216 字节）。`[源码]` 与运行时分辨率无关，不随视距/画质变化。
- 代价：无法随天气/气压/行星半径实时变化 —— 换行星大气必须重新烘焙。`[源码]`（常量全部是编译期 `const`）

**适用范围与失效边界**

- LUT 只覆盖"从地表看出去"的 `r` 范围；`min_mu_s = -0.35`（`atmosphere.glsl:28`）之外的太阳仰角被裁掉。`[源码]`
- 高空（`eyeAltitude` 很大）时 LUT 的 `r` 维只有 64 档，且烘焙按地表 `r = planet_radius` 假设（`atmosphere.glsl:203`，`const float r = planet_radius;`）。`[源码]` 因此在云层高度以上，大气颜色会偏 —— photon 用 `analytic.glsl` 的高度雾补这一块。`[推断]`

**与 Astra 的关系**

Astra **没有**大气 LUT。在 Astra 源码里检索 `transmittance|LUT|lut` 只命中的是注释文本（如 `global/post/grading.glsl:187`），没有任何 LUT 生成 pass 或 LUT 采样。Astra 的天空是 Complementary 的三方向球形解析模型：

```glsl
Astra/shaders/global/atmosphere/sky_gradient.glsl:6-8
//  Astra v1 - overworld sky, ported from Complementary r5.9 (Reimagined).
//  This is the "up / middle / down" three-direction spherical model
//  (VdotU = view.up, VdotS = view.sun), NOT a single vertical gradient.
```

这意味着 Astra 的天空成本是纯 ALU（几个 mix/pow），比 photon 的 4 次 3D 采样更便宜，但**没有真正的大气透视与日落色散**。photon 这条路适合 Astra 在"末地/下界需要独立大气"或"想要更真实的空气透视"时作为选项，不适合替换现有天空。

---

## 6. Photon 高度雾：解析积分（exp 的闭式解）+ 4 次迭代多散射；raymarch 版本只在需要阴影时用

**技术目标**：让空气雾在没有阴影贴图时是 0 次采样、几次 exp 就能算完的解析式。

**实现位置**

```glsl
shaders/include/fog/overworld/analytic.glsl:16-21
    const vec2 mul = -rcp(air_fog_falloff_half_life);
    const vec2 add = -mul * air_fog_falloff_start;

    vec2 a = ray_origin_world.y * mul + add;
    vec2 p1 = exp2(ray_length * ray_direction_world.y * mul + a);
    vec2 p2 = exp2(a);
```

**算法机制**（`[源码]`）

- 密度是 `exp2(y * mul + add)` 的指数衰减廓线；沿射线的积分有闭式解，直接算出 Rayleigh/Mie 两个"空气质量"（airmass），再套 Beer-Lambert 得透射率与散射积分（`analytic.glsl:58-66`）。**每像素 2 次 exp2 即可**，采 0 次纹理。
- 多散射同样是 4 次迭代、零采样（`analytic.glsl:86-97`）；相位混合固定为 `0.7 * HG(g=0.5) + 0.3 * HG(g=-0.2)`（`analytic.glsl:69-70`）。
- 需要阴影（光柱）时才切到 raymarched 版本：`raymarched.glsl`，步数随射线长度自适应 `float(air_fog_min_step_count) + air_fog_step_count_growth * ray_length`，并夹在 8~25 之间（`raymarched.glsl:94-97` + `constants.glsl:4-6`）。

```glsl
shaders/include/fog/overworld/raymarched.glsl:94-97
    uint step_count = uint(
        float(air_fog_min_step_count) + air_fog_step_count_growth * ray_length
    );
    step_count = min(step_count, air_fog_max_step_count);
```

**开销与代价**

- 解析版：每像素 0 次纹理采样、约 6 次 exp/exp2、4 轮相位。`[源码]`
- raymarch 版（VL 开启，默认 `VL` 是开的：`settings.glsl:308`）：8~25 步 × 每步 1 次阴影贴图 `texelFetch` + 1 次密度（2 次 exp2），在 `VL_RENDER_SCALE 0.50`（`settings.glsl:326`）下即 1/4 像素。`[源码]`
- 因此 photon 默认是"解析雾 + 1/4 分辨率阴影体积光"两层，而不是"全屏体积雾"。`[源码]`

**适用范围与失效边界**

- 解析解要求密度廓线严格是指数；一旦有 3D 噪声（`AIR_FOG_CLOUDY_NOISE`，`raymarched.glsl:23-31`）就必须走 raymarch。`[源码]`
- 解析版没有阴影，云影只能靠 `shadow` 参数外部传入（`analytic.glsl:93`）。`[源码]`

**与 Astra 的关系**

Astra 的体积雾是纯 raymarch，步数由画质档决定：

```glsl
Astra/shaders/global/atmosphere/volume_fog.glsl:32-41
#if VOLUME_FOG_QUALITY == 0
#define ASTRA_VOLUME_STEPS 12
#define ASTRA_VOLUME_PREFIX_STEPS 4
#elif VOLUME_FOG_QUALITY == 2
#define ASTRA_VOLUME_STEPS 48
#define ASTRA_VOLUME_PREFIX_STEPS 12
#else
#define ASTRA_VOLUME_STEPS 24
#define ASTRA_VOLUME_PREFIX_STEPS 8
#endif
```

Astra 的普通空气雾本体在 `global/atmosphere/fog.glsl`（Steadfast FogV2 派生），是解析曲线，不是体积积分。两者分工与 photon 类似，但 Astra 没有"解析 + 4 次迭代多散射"这一层 —— 也就是说 Astra 的雾色只有单次散射项。

---

## 7. Photon Bloom：tile 金字塔，13-tap 降采样 + 可分离 9-tap 高斯 + 加权升采样

**技术目标**：用"纹理砖块"把所有 bloom mip 塞进同一张全分辨率纹理，省掉 mip 链的绑定与带宽。

**实现位置**

```glsl
shaders/program/c5_c10_bloom_downsample.fsh:15-17
#define bloom_tile_scale(i) 0.5 * exp2(-(i))
#define bloom_tile_offset(i) \
    vec2(1.0 - exp2(-(i)), float((i) & 1) * (1.0 - 0.5 * exp2(-(i))))

shaders/program/c12_bloom_gaussian_0.fsh:57-61
    for (int i = -4; i <= 4; ++i) {
        ivec2 pos = texel + ivec2(i, 0);
        float weight = binomial_weights_9[abs(i)]
            * float(clamp(pos.x, bounds_min.x + 2, bounds_max.x - 2) == pos.x);
        bloom_tiles += texelFetch(colortex0, pos, 0).rgb * weight;
```

**算法机制**（`[源码]`）

- 降采样：`c5..c10` 共 6 个 pass，每个 pass 用固定 13 个 tap 的 6×6 重叠盒式核（CoD:AW 的方案，`c5_c10_bloom_downsample.fsh:49-51` 明确注明出处），权重 0.125/0.0625/0.03125（`c5:52-130`）。
- 高斯：水平 9-tap + 垂直 9-tap 两次 pass，二项式权重 `0.2734375, 0.21875, 0.109375, 0.03125, 0.00390625`（`c12:28-29`），边界外 tap 权重直接置 0 并按 `weight_sum` 归一（`c12:59-65`）。
- 升采样：`c14..c18` 逐级混合，`src_weight = mix(0.25, 0.90, 0.5 * BLOOM_SPREAD)`（`c14:45`）。
- 关键省法：**所有 mip 都在同一张 `colortex0` 的不同区域**，靠 `bloom_tile_offset` 的 `1 - exp2(-i)` 布局；因此不需要创建 mipmap 链，也不需要 6 张独立纹理。`[源码]`

```glsl
shaders/program/c14_c18_bloom_upsample.fsh:45-47
    const float src_weight = mix(0.25, 0.90, 0.5 * BLOOM_SPREAD);
    bloom_tile = texelFetch(SRC_SAMPLER, texel, 0).rgb * (1.0 - src_weight); // Destination tile.
    bloom_tile += BLOOM_UPSAMPLING_FILTER(SRC_SAMPLER, uv_src).rgb * src_weight; // Source tile.
```

**开销与代价**

- pass 数：1（降采样起始）+ 5（后续降采样）+ 2（高斯）+ 5（升采样）= 13 个 bloom 相关 pass。`[源码]`（`program/` 下 `c5`–`c18`）
- 每像素采样：降采样 13 次；高斯 9 次 × 2；升采样 1 次 `texelFetch` + 1 次过滤采样。`[源码]`
- 但降采样与高斯的像素数随 mip 减少（第 i 级是 1/4^i），所以总采样数远低于"13 × 全屏"。`[推断]`

**适用范围与失效边界**

- tile 布局要求 `bloom_tile_offset` 与 `bloom_tile_scale` 在所有 4 个 shader 里逐字一致（同样的 `#define` 复制了 4 份：`c5:15-17`、`c12:14-16`、`c13:14-16`、`c14:15-17`）。改一处就必须改四处。`[源码]`
- 高斯 pass 对不属于任何 tile 的像素 `discard`（`c12:46-50`），并把 padding 区钳到最近 tile（`c13:47-69`）。`[源码]`

**与 Astra 的关系**

Astra 的 bloom 是"单 pass 捕获 + 硬件 mipmap"，不是 tile 金字塔：

```glsl
Astra/shaders/global/post/bloom.glsl:82-88
    #if defined ASTRA_OVERWORLD_OPTIMIZED || BLOOM_QUALITY == 0
    const int taps = 4;
    #elif BLOOM_QUALITY == 2
    const int taps = 13;
    #else
    const int taps = 5;
    #endif
```

Astra 用 `Iris` 的 mipmap 自动生成做金字塔（`bloom.glsl:59-61` 注释：`the buffer Iris produces here is what gets mipmapped`）。photon 的 tile 方案省掉的是"显式 6 个降采样/升采样 pass"，代价是每 pass 都要重算 tile 边界。对 Astra 而言，tile 方案只有在"mipmap 生成本身被证明是瓶颈"时才值得换。`[推断]`

---

## 8. Photon TAA：YCoCg + Reinhard 前置 + 方差裁剪 + 按像素龄的混合权重

**技术目标**：在 HDR 下不掉高光细节，同时把闪烁压到最低。

**实现位置**

```glsl
shaders/program/c4_taa_exposure.fsh:227-233
    float gamma = mix(0.75, 1.25, linear_step(0.25, 1.0, distance_factor));

    vec3 mu = moments[0];
    vec3 sigma = sqrt(moments[1] - moments[0] * moments[0]);

    min_color = max(min_color, mu - gamma * sigma);
    max_color = min(max_color, mu + gamma * sigma);
```

**算法机制**（`[源码]`）

1. 先把当前帧与历史都过一遍 `rgb / (rgb + 1.0)`（Reinhard，`c4:35`），在 SDR 域做裁剪，最后 `reinhard_inverse` 还原（`c4:376`）。这样高光不会压垮方差。
2. 3×3 邻域转 YCoCg（`c4:195-203`），先算软 min/max（HRA 的"两次 min 取平均"，`c4:209-215`），再与"均值 ± gamma×标准差"求交集（`c4:217-233`）。gamma 随距离在 0.75~1.25 之间变 —— 近处更激进（去鬼影），远处更保守（防闪烁）。`[源码]`
3. 混合权重不用固定值，而是 `alpha = max(1.0 / pixel_age, blend_weight)`，`blend_weight = mix(0.35, 0.10, distance_factor)`（`c4:311-312`）。效果是：静止像素快速收敛到"等权平均所有历史帧"，运动/新建像素立刻回到当前帧。`[源码]`
4. 额外的 offcenter rejection（`c4:366-373`）按重投影落点偏离像素中心的距离降权，减少运动模糊。`[源码]`

```glsl
shaders/program/c4_taa_exposure.fsh:311-312
    float blend_weight = mix(0.35, 0.10, distance_factor);
    float alpha = max(1.0 / pixel_age, blend_weight);
```

**开销与代价**

- 1 个 prep pass（`c3_taau_prep`）算 3×3 邻域的软 min/max 并写两张全分辨率缓冲（`c3:14-17` 的 `RENDERTARGETS: 1,2`）；1 个 resolve pass 再取一次 3×3 邻域算方差。`[源码]` 即每像素约 18 次全分辨率 fetch。`[源码]`
- 历史 `colortex5` 是 RGBA16F 全分辨率，且 `alpha` 通道兼职存曝光（`c4:383-387`）。`[源码]`

**适用范围与失效边界**

- 方差裁剪比 min/max 裁剪更容易产生闪烁（代码注释自己写了这一点，`c4:68-70`）：`// TAA_VARIANCE_CLIPPING // More aggressive neighborhood clipping method // which further reduces ghosting but can // introduce flickering artifacts`。`[源码]` 对树叶/植物这类高频细节，这就是"越裁越闪"的来源。
- `pixel_age` 存在历史 alpha 里，重建期间（渲染缩放 ≠ 1）会与技术性 alpha 冲突，photon 用 `float(clamp01(previous_uv) == previous_uv)` 判断离屏（`c4:303`）。`[源码]`

**与 Astra 的关系**

Astra 的 TAA 已经在做同类事（YCoCg、邻域、重投影、反应性），但裁剪是 min/max 而非方差：

```glsl
Astra/shaders/program/taa_resolve.fsh:144-146
    vec3 historyColor = taa_ycocg(h.rgb);

    float change = abs(historyColor.x - currentY) / max(max(historyColor.x, currentY), 0.05);
```

```glsl
Astra/shaders/program/taa_resolve.fsh:165-166
    vec3 bounded = clamp(historyColor, lo, hi);
    float motion = clamp(length((historyUV - texcoord) * vec2(size)) / 16.0, 0.0, 1.0);
```

所以 Astra 的 TAA 不是"缺方差裁剪"的问题；photon 值得借鉴的是**两条独立的重投影校验**：像素龄（`pixel_age`）与 offcenter rejection 分开算、再相乘（`c4:371-373`），以及**距离自适应的裁剪强度** gamma。Astra 现有 `change` 阈值是标量，没有随距离变化。

---

## 9. Complementary Reimagined 的云：根本没 raymarch —— 层平面命中 + 每命中 2 次光照采样

**技术目标**：用"命中第一个噪声阈值"代替体积积分，把云做成一层有厚度的壳。

**实现位置**

```glsl
shaders/lib/atmospherics/clouds/reimaginedClouds.glsl:17-19
    float threshold = clamp(abs(cloudAltitude - tracePos.y) / cloudStretch, 0.001, 0.999);
    threshold = pow2(pow2(pow2(threshold)));
    return noise > threshold * 0.5 + 0.25;

shaders/lib/atmospherics/clouds/reimaginedClouds.glsl:47-52
    #if CLOUD_QUALITY == 1 || !defined DEFERRED1
        int sampleCount = max(int(planeDistanceDif) / 16, 6);
    #elif CLOUD_QUALITY == 2
        int sampleCount = max(int(planeDistanceDif) / 8, 12);
    #elif CLOUD_QUALITY == 3
        int sampleCount = max(int(planeDistanceDif), 12);
```

**算法机制**（`[源码]`）

- 云的"体积"由 `cloudAltitude ± cloudStretch` 两个平面之间的垂直阈值曲线表示：离中心越远阈值越高（`pow2` 三次 = 八次方），于是只有噪声超过阈值的地方才是云。命中即 `break`（`reimaginedClouds.glsl:140`），不做透射率积分。`[源码]`
- 光照是**两次 2D 噪声采样**（`reimaginedClouds.glsl:111-119`），沿光线方向偏移 `0.08`（世界单位级别），不是光线步进。`[源码]`
- 噪声坐标用 `GetRoundedCloudCoord`（`cloudCoord.glsl:7-15`）把坐标量化到 1/256 的格点上，注释写着 `// Thanks to SixthSurge` —— 即 CR 借用了 Photon 作者的做法。`[源码]`
- 采样步长固定（`stepMult = planeDistanceDif / sampleCount`），采样数由两个平面间的距离决定，所以**云越厚/视线越斜，采样数越多**。`[源码]`

**开销与代价**

- 每像素最多 `sampleCount` 次纹理取（2D 云噪声），命中后 +2 次 2D 密度取 + 1 次天空求值（`reimaginedClouds.glsl:123` 的 `GetSky`）。`[源码]`
- 全分辨率执行，没有降分辨率、没有时域重建。`[源码]` 所以 CR 云的成本随屏幕像素线性增长 —— 与 photon 的 1/16 + 重建正好相反。
- 命中即断，所以"云稀"时成本低、"云满屏"时成本高；photon 的等距步进则相反（成本与覆盖无关）。`[推断]`

**适用范围与失效边界**

- 只有一层壳，没有体积厚度意义上的透光；云内部的结构完全由 2D 噪声 + 高度阈值伪造。`[源码]`
- 采样步长固定，云边缘会随 `planeDistanceDif` 抖动；CR 用 `dither` 打散（`reimaginedClouds.glsl:58`），代价是噪点，需要 TAA 收。`[源码]`

**与 Astra 的关系**

**Astra 的云模型直接来自这一份**。`clouds_planar.glsl` 头注释逐行标了出处：

```glsl
Astra/shaders/global/atmosphere/clouds_planar.glsl:11-12
//    lib/atmospherics/clouds/reimaginedClouds.glsl:3-5, 17-19, 30-146
//        cloudStretch / cloudTallness / cloudRoundness, the vertical noise
```

并且 Astra 的 `astra_cloud_existence_gate` 就是 CR 的 `threshold * 0.5 + 0.25`（`clouds_planar.glsl:116-118` 对 `0.25 + layerThreshold * 0.5 + coverageBias`）。因此 CR 这条路径对 Astra 的增量价值在于**参数与分支选择**（`CLOUD_QUALITY` 三档的采样公式、`interleavedGradientNoise` 抖动），而不是算法本身。

---

## 10. CR 体积光：近场幂分布采样 + 远场单样本，按 `vlSceneIntensity` 动态改采样数

**技术目标**：把光柱的采样预算集中在相机附近，远处只留一个样本。

**实现位置**

```glsl
shaders/lib/atmospherics/volumetricLight/volumetricLight.glsl:88-93
    #elif LIGHTSHAFT_QUALI_DEFINE == 2 // Medium (Default)
        #ifdef OVERWORLD
            int nearSamples = 10;
        #else
            int nearSamples = 15;
        #endif

shaders/lib/atmospherics/volumetricLight/volumetricLight.glsl:188-193
        if (i <= nearSamples) { // Actual light shaft sampling near-field section
            float t = (float(i) + dither) / float(nearSamples);
            nextDistance = pow(t, sampleDistribution) * activeThreshold;
            scenePos = rayDirection * nextDistance;

            if (nextDistance >= rayEnd) break;
```

**算法机制**（`[源码]`）

- 采样位置是 `t^sampleDistribution`（OVERWORLD 默认 2.0，`volumetricLight.glsl:109`），即近处密、远处疏，而不是等距。
- 远场只有 `farSamples = 1`（`volumetricLight.glsl:106`），从 `qualityThreshold = min(far, shadowDistance) * 0.98` 之后才开始用（`volumetricLight.glsl:113`、`179`）。`[源码]`
- 采样数会随"场景里有多少强光源"动态上调：`nearSamples = int(mix(float(nearSamples), 1.5 * nearSamples, vlSceneIntensity))`（`volumetricLight.glsl:134`）。`[源码]`
- 每个样本 1 次 `texelFetch` 阴影图（`volumetricLight.glsl:201`），命中半透明时再查 `shadowtex1`/`shadowcolor1`（`volumetricLight.glsl:208-211`）。`[源码]`

**开销与代价**

- 每像素 10（近）+ 1（远）= 11 个样本 × 1~3 次纹理取。`[源码]` 相比 photon 的 20 步全屏，样本更少但分布不同（CR 无早退，photon 有 `min_transmittance`）。`[推断]`
- 反射/合成 pass 里采样数直接减半（`volumetricLight.glsl:155-158` 的 `#ifdef COMPOSITE`）。`[源码]`

**适用范围与失效边界**

- 幂分布采样在长射线上会在远处留下可见的条带；CR 用 `dither`（每像素随机相位）+ 后处理模糊掩盖。`[源码]`
- `farSamples = 1` 意味着 `qualityThreshold` 之外的雾近似为常数 —— 天空方向的光柱基本是假的。`[推断]`

**与 Astra 的关系**

Astra 的体积雾已经是"近段/前缀段"两段式（`volume_fog.glsl:32-41` 的 `ASTRA_VOLUME_STEPS` 与 `ASTRA_VOLUME_PREFIX_STEPS`），思路与 CR 的 near/far 一致；但 Astra 用的是**等距**分段（步长 = 距离 / 步数），不是幂分布。把步长改成 `t^2` 分布是 Astra 可以用极小改动获得的"近处更密"收益。`[推断]`

---

## 11. Piscium 云：compute shader + Hi-Z 整工作组剔除 + 1/2.25~1/16 低分辨率 + 时域累积

**技术目标**：在"整片天空没有云"的像素组上完全不启动 raymarch；其余情况用低分辨率 + 时域累积补回精度。

**实现位置**

```glsl
shaders/techniques/atmospherics/clouds/RenderVolumetric.comp.glsl:269-277
void main() {
    if (gl_LocalInvocationIndex == 0) {
        vec2 groupCenter = vec2(gl_WorkGroupID.xy << 3u) + 4.0;
        vec2 hizCheckPos = groupCenter * UPSCALE_FACTOR / CHECK_MIP_FACTOR;
        shared_worldGroupCheck = hiz_groupSkyCheck4x4(hizCheckPos, CHECK_MIP_LEVEL);
    }
    barrier();

    if (shared_worldGroupCheck) {
        uvec2 workGroupOrigin = gl_WorkGroupID.xy << 3;
        uint threadIdx = gl_SubgroupID * gl_SubgroupSize + gl_SubgroupInvocationID;
        uvec2 mortonPos = morton_8bDecode(threadIdx);
```

```glsl
shaders/techniques/atmospherics/clouds/ss/Common.glsl:21-24
#elif SETTING_CLOUDS_LOW_UPSCALE_FACTOR == 2
#define UPSCALE_FACTOR 2.0
#define DOWNSCALE_DIVIDE(x) (x / 2)
#define RENDER_MULTIPLIER 0.5
```

**算法机制**（`[源码]`）

1. 云跑在 **compute shader** 里，工作组 8×8（`RenderVolumetric.comp.glsl:12`），并用 Morton 排序把工作组内的线程映射到屏幕（`RenderVolumetric.comp.glsl:280-281`），以改善 2D 缓存的局部性。`[源码]`
2. 每个工作组先由 1 个线程查一次 Hi-Z 深度金字塔：如果这一整块 8×8 都是天空（最远深度 ≤ 天顶），整组直接跳过。`[源码]`（`techniques/HiZCheck.glsl:29-35` 的 `hiz_furthest_load` 比较）
3. 低分辨率倍数 `UPSCALE_FACTOR` 从 1.0 到 4.0 共 7 档（`ss/Common.glsl:7-56`），对应主 raymarch 的像素数为 1/1 ~ 1/16。`[源码]`
4. 累积 pass `ss/Accum.comp.glsl`：4×4 Lanczos 采样当前帧的低分辨率结果（`Accum.comp.glsl:142-143`），同一次循环里顺便算 1 阶/2 阶矩（`Accum.comp.glsl:173-176`），然后用**椭球裁剪**（`Accum.comp.glsl:200-216`）拒绝历史；历史权重上限 64（`Accum.comp.glsl:125`）。`[源码]`

```glsl
shaders/techniques/atmospherics/clouds/ss/Accum.comp.glsl:204-207
                vec3 inSctrStddev = sqrt(max(inSctrMoment2 - inSctrMoment1 * inSctrMoment1, clippingEps));
                vec3 inSctrDelta = prevInSctrYCoCg - inSctrMoment1;
                inSctrDelta /= max(1.0, length(inSctrDelta / inSctrStddev / global_historyResetFactor));
                prevInSctrYCoCg = mix(prevInSctrYCoCg, inSctrMoment1 + inSctrDelta, clippingWeight);
```

**开销与代价**

- Hi-Z 剔除是**每工作组一次**的纹理取（1/64 像素），但要求深度金字塔已经建好（`techniques/HiZ.glsl` 是独立 pass）。`[源码]`
- 时域累积每像素 16 次历史 fetch（4×4），是这条链里最贵的固定成本，且与云是否命中无关。`[源码]`
- 低分辨率数据的存储是 `rgba32ui` 打包（`RenderVolumetric.comp.glsl:17` 的 `layout(rgba32ui)`），把 7 个 half 塞进 4 个 uint（`ss/Common.glsl:86-92`），省一半带宽。`[源码]`

**适用范围与失效边界**

- Hi-Z 剔除只用"最深/最远深度"，因此**被地形挡住的天空组不会被剔除**（只有整组都是天空才跳）。`[源码]`
- 时域累积需要历史重置因子 `global_historyResetFactor`；相机切换/传送时靠它衰减历史（`Accum.comp.glsl:124`）。`[源码]`

**与 Astra 的关系**

Astra 没有 compute shader 云，也没有 Hi-Z 剔除：`program/cloud_screen.fsh` 是普通全屏 fragment pass，逐像素判断区间是否为空（`cloud_screen.fsh:67` 的 `sampledVisible`）。Piscium 的"整块天空跳过"在 Astra 里可以直接用 `eyeBrightness`/区块级判断近似，但需要额外的深度金字塔 pass。`[推断]`

---

## 12. Piscium 多重散射：8 步光路 + 指数累积（不增加主采样），且明确引用中文技术博客

**技术目标**：让厚云内部有"逐次累积"的多次散射亮度，而不是靠相位函数硬调。

**实现位置**

```glsl
shaders/techniques/atmospherics/clouds/RenderVolumetric.comp.glsl:228-230
                                isotropicMS += isotropicMSW * exp(-(isotropicMSA + isotropicMSK) * isotropicMSU)
                                    * (1.0 - exp(-isotropicMSBuildRate * isotropicMSU));
                                isotropicMSOpticalDepth += isotropicMSDeltaOpticalDepth;
```

```glsl
shaders/techniques/atmospherics/clouds/Common.glsl:160-166
    vec3 fMS = (sampleScattering / sampleExtinction) * (1.0 - exp(-D * sampleExtinction));
    fMS = mix(fMS, fMS * 0.95, linearStep(0.9, 1.0, fMS));
    vec3 sampleMSIrradiance = sampleLightIrradiance;
    sampleMSIrradiance *= UNIFORM_PHASE;
    sampleMSIrradiance *= fMS / (1.0 - fMS);
    sampleIrradiance += sampleMSIrradiance;
```

**算法机制**（`[源码]`）

- 主 ray march 每个样本内部再跑 **8 步固定光照步**（`RenderVolumetric.comp.glsl:198-232`），每步累加一个带 `exp(-光学深度)` 衰减的逆散射项；`isotropicMSBuildRate` 让"累加到饱和"而不是线性叠加。`[源码]`
- 8 步之外，`clouds_computeLighting` 里还有一条**解析**多次散射近似：用 `fMS`（散射/消光比 × 饱和指数）算出一个"无限次散射的收敛值"，再除以 `(1 - fMS)`（`Common.glsl:160-166`），完全不需要额外采样。`[源码]`
- 出处明确写在文件头：`[WDT22] Wo De Tian ... "一个简单的体积云多重散射近似方法"` 与 `[ASH25] AshenOneArt ... HanPi Volume Cloud isotropic multiple-scattering derivation`（`Common.glsl:21-24`）。**这是借用，不是原创**，且是中文技术博客的推导。`[源码]`

**开销与代价**

- 每个"命中云"的样本多 8 次密度查询（每次 3~5 张 3D 噪声纹理取，`Cumulus.glsl:128-145`）。`[源码]` 这是 8 倍的光照步成本，只对命中样本付。
- 但 8 步是固定数、且用 `isotropicMSBoundaryWeight`（`Cumulus.glsl:113-126`，4 次额外的覆盖率采样）来加权，边界处成本更高。`[源码]`

**适用范围与失效边界**

- 只有当 `clouds_cu_density` 返回 true（即有云）时才跑这 8 步，空样本完全跳过。`[源码]`
- 该近似假设介质近似各向同性；强前向散射（银边）由单独的相函数 LUT 处理（`Mediums.glsl:38-50`）。`[源码]`

**与 Astra 的关系**

Astra 目前**没有任何多散射项**（见第 3 条）。Piscium 的 `fMS / (1 - fMS)` 解析式（`Common.glsl:160-166`）是三项里**最便宜**的一个：0 次纹理采样、3 个 exp。对 Astra 的"云边缘分层"问题，这是可以先试的最小改动。

---

## 13. Piscium 大气：运行时生成的 Transmittance / MultiScatter / SkyView 三张 LUT

**技术目标**：不预烘文件，按当前行星参数实时生成 LUT，支持运行时改大气。

**实现位置**

```glsl
shaders/techniques/atmospherics/air/lut/Common.glsl:21-31
#define TRANSMITTANCE_TEXTURE_WIDTH 256
#define TRANSMITTANCE_TEXTURE_HEIGHT 64
const vec2 TRANSMITTANCE_TEXTURE_SIZE = vec2(TRANSMITTANCE_TEXTURE_WIDTH, TRANSMITTANCE_TEXTURE_HEIGHT);
const vec2 TRANSMITTANCE_TEXEL_SIZE = 1.0 / TRANSMITTANCE_TEXTURE_SIZE;

#define MULTI_SCTR_LUT_SIZE 32

#define SKYVIEW_LUT_WIDTH SETTING_SKYVIEW_RES
#define SKYVIEW_LUT_HEIGHT SETTING_SKYVIEW_RES
#define SKYVIEW_LUT_LAYERS 4
#define SKYVIEW_LUT_DEPTH 8
```

**算法机制**（`[源码]`）

- 三张 LUT 全部由 compute pass 生成（`lut/GenerateTransmittance.comp.glsl`、`lut/GenerateMultiSctr.comp.glsl`、`lut/GenerateSkyViewLUT.comp.glsl`），参数映射直接照抄 Unreal 的 `RenderSkyCommon.hlsl`（`lut/Common.glsl:45-46` 的注释与链接）。`[源码]`
- SkyView LUT 把"天空方向"存成 4 层 × 8 深度 = 每层一对（散射、透射）切片（`lut/API.glsl:53-58`），采样时按 `layerIndex` 选切片。`[源码]`
- MultiScatter LUT 只存 32²，并按 `cosLightZenith` 与高度做线性映射（`lut/API.glsl:28-32`）。`[源码]`

**开销与代价**

- Transmittance 256×64、MultiScatter 32²、SkyView `SETTING_SKYVIEW_RES²`×4 层×8 深度；其中 SkyView 是最大的一张（128~1024 可配）。`[源码]`
- 生成是 compute pass，只在参数变化/初始化时跑，不每帧。`[源码]`（`Generate*.comp.glsl` 是独立 pass）
- 采样端：每像素 2~4 次 2D 纹理取（透射率 + 多散射），比 photon 的 4 次 3D 取便宜。`[源码]` + `[推断]`

**适用范围与失效边界**

- SkyView LUT 只覆盖"从相机所在高度看出去"，换高度要重算；Piscium 用 4 层来缓解。`[源码]`

**与 Astra 的关系**

同第 5 条：Astra 没有 LUT。区别是 photon 预烘成文件、Piscium 运行时算。对 Astra 这种"只有主世界一套大气"的情况，**预烘（photon 式）更省**；只有当 Astra 想要"下界/末地各自独立大气"时才需要 Piscium 式运行时生成。`[推断]`

---

## 14. 对照：Solas 与 Bliss 的昂贵写法（负面证据，同样是判断依据）

**技术目标**（作为反例）：说明"看起来一样"的实现成本可以差一个数量级。

**实现位置**

```glsl
shaders/lib/atmosphere/volumetricClouds.glsl:226
        int maxsampleCount = 24;

shaders/lib/atmosphere/volumetricClouds.glsl:246-250
            float rayLength = thickness * scale / 2.0;
                  rayLength /= (4.0 * nWorldPos.y * nWorldPos.y) * lengthScaling + 1.0;

            vec3 rayIncrement = nWorldPos * rayLength;
            int sampleCount = int(min(planeDifference / rayLength, maxsampleCount) + 4);
```

**算法机制**（`[源码]`）

- Solas：最多 24 步，但每个"有噪声"的样本再取 1 次低细节密度（`volumetricClouds.glsl:310` 的 `CloudSampleLowDetail`），即每样本 2 次密度函数（每次 2~4 张纹理取）。`[源码]` 它没有多散射八度，只有 powder（`volumetricClouds.glsl:313`）。
- Solas 的 bloom 是**单 pass 5 个 tile × 6×6 = 36 个 tap**（`lib/post/computeBloom.glsl:14-24`），即每像素 180 次纹理取：

```glsl
shaders/lib/post/computeBloom.glsl:14-19
		for(int i = 0; i < 6; i++) {
			for(int j = 0; j < 6; j++) {
				float wg = weight[i] * weight[j];
				vec2 pixelOffset = vec2((float(i) - 2.75) * pixelWidth, (float(j) - 2.5) * pixelHeight);
				vec2 sampleCoord = bloomCoord + pixelOffset * scale;
				bloom += texture2D(colortex0, sampleCoord).rgb * wg;
```

- Bliss：3D 噪声用**两次 2D 纹理取 + 一次按 y 的线性插值**伪造（`lib/volumetricClouds.glsl:62-65` 的注释 `//The y channel has an offset to avoid using two textures fetches`）：

```glsl
shaders/lib/volumetricClouds.glsl:62-65
	//The y channel has an offset to avoid using two textures fetches
	vec2 xy = texture2D(noisetex, coord).yx;

	return mix(xy.r,xy.g, f.y);
```

**开销与代价**（`[推断]`，仅静态推断，无实测）

- Solas bloom 的 180 次/像素是全分辨率一次 pass，明显高于 photon 的"13 次降采样 + 2×9 次分 mip 高斯"。`[源码]` 采样次数是确定的，是否成为瓶颈 `[未验证]`。
- Bliss 的"两次纹理取伪造 3D 噪声"是**降低带宽**的实用技巧：真 3D 纹理 1 次取 ≈ 2 次 2D 取 + 1 次 mix 的带宽，在体积云的每步都采样时量化差异可观。`[推断]`

**适用范围与失效边界**

- Bliss 的伪造 3D 噪声在 y 方向只有一层插值，斜向观察会有层状结构；它靠 `pos /= 18.` 的大尺度采样掩盖。`[源码]`

**与 Astra 的关系**

Astra 的云噪声来自 `complementaryCloudNoise`（2D），所以**已经是**Bliss 那条"2D 伪造"路线（`clouds_planar.glsl:96-100`）。Solas 的 bloom 写法对 Astra 是明确的反例，不需要考虑。

---

## 15. 建议主代理重点复用的 3~6 条

1. **8 次迭代的零采样多散射**（photon `include/sky/clouds/cumulus.glsl:164-185`）：Astra 的云现在只有亮面/暗面两档，加这一层只需 ALU、不加纹理带宽，直接对"云边缘分层"与厚云观感有用。
2. **解析多次散射的闭式收尾 `fMS/(1-fMS)`**（piscium `techniques/atmospherics/clouds/Common.glsl:160-166`）：比第 1 条更便宜（3 个 exp、0 采样），可作为先落地的最小改动。
3. **每像素龄选噪声 mip**（photon `include/sky/clouds/sampling.glsl:8-14`）：新像素用粗 mip、老像素用细 mip，是"不模糊云体"这一约束下最直接的一招，且与 Astra 现有的 `ASTRA_CLOUD_TEMPORAL_WEIGHT` 正交，可叠加。
4. **距离自适应的裁剪强度**（photon `c4_taa_exposure.fsh:227` 的 `gamma = mix(0.75, 1.25, ...)`）：Astra 的 TAA 裁剪阈值是标量，近处与远处用同一强度，这正是"树叶闪"与"远处云抖"无法同时最优的原因之一。
5. **整块跳过**（piscium `RenderVolumetric.comp.glsl:270-277` 的 Hi-Z 组剔除）：Astra 的云是全屏逐像素判断，天空占比高的视角（抬头/高空）浪费明显；这条需要额外深度金字塔，但与 Astra 现有的 `ASTRA_SKY_CACHE_WRITE` 低分辨率环境有协同。
6. **地面云影 + 体积光共用一张低分辨率云影图**（photon `include/lighting/cloud_shadows.glsl:7-9` + `crepuscular_rays.glsl:96-104`）：Astra 已有 `cloud_shadow_cache.glsl`，缺的只是"沿视线步进查这张图"的水晶光柱这一层。

---

## 16. 未核查 / 缺口

- photon 的 `ATMOSPHERE_TRANSMITTANCE_LUT` 实际是否定义：`atmosphere.glsl:501`/`527` 两处 `#if defined` 守卫，但**在整个仓库里没有找到 `#define ATMOSPHERE_TRANSMITTANCE_LUT`**（`grepRepo` 只命中守卫与使用处）。因此运行时走的是 Chapman 解析近似（`atmosphere.glsl:538-568`）。`[源码]` + `[未验证]`（可能由 Iris 的 `#define` 机制或未包含的文件提供）
- 所有"每像素采样次数"是按代码结构静态统计，没有在 GPU 上抓帧验证；`[推断]` 标记处均属此类。
- Astra 侧未逐一核查：`program/deferred.fsh` 对云历史的实际消费顺序、`clouds_screen.glsl` 的低分辨率重建细节。本笔记只核对了 `clouds_planar.glsl`、`cloud_temporal.glsl`、`cloud_screen.fsh`、`cloud_shadow_cache.glsl`、`bloom.glsl`、`volume_fog.glsl`、`taa_resolve.fsh`、`godrays.glsl`、`sky_gradient.glsl`。


---

## 17. 结论摘要（按技术主题，标注对 Astra 的用处）

用途分级：**A = 可直接落地**（改动小、不新增纹理带宽、与 Astra 现有结构不冲突）；**B = 有前置条件**（需要额外 pass 或缓冲）；**C = 不建议**（与 Astra 现有做法等价或更差）。

### 17.1 云 · 分辨率与重建

- photon 把主 raymarch 压到 1/16 像素（`settings.glsl:201` 的 `CLOUDS_TEMPORAL_UPSCALING 4` + `shaders.properties:330-331` 的 `0.25 0.25`），再用全分辨率 pass `d2_clouds_upscaling` 做棋盘格 + Catmull-Rom 历史重建（`d2_clouds_upscaling.fsh:367-371`）。清晰度靠重建，不靠降模糊。**B**：Astra 已有 `cloud_temporal.glsl` 的历史机制，但没有"降分辨率主渲染"这一半；要接先要新建 1/4 分辨率的云目标与棋盘格相位表。
- photon 读历史时按像素龄选噪声 mip：`sampling.glsl:10` 的 `float ld = 2.0 * dampen(max0(1.0 - 0.1 * pixel_age));`。新像素糊、老像素清晰。**A**：这是**本方向对 Astra 最有用的一条**。Astra 的历史权重是常数（`cloud_temporal.glsl:48-52` 的 0.75/0.90），没有任何"像素龄"概念；加这一层不改权重、不改缓冲布局，只给历史采样加一个 mip 选择。
- piscium 用 compute shader + Hi-Z 整工作组剔除（`RenderVolumetric.comp.glsl:270-277`），整块 8×8 全是天空就完全不启动。**B**：需要独立的深度金字塔 pass；Astra 目前是 fragment 全屏逐像素判断（`cloud_screen.fsh:51-56`）。

### 17.2 云 · 步进与提前退出

- photon 主步进**等距**、步数按 `|ray_dir.y|` 在地平线 40 / 天顶 20 之间插值（`cumulus.glsl:220-222`、`255`），空样本只 `continue` 不加速（`cumulus.glsl:292-294`），唯一提前退出是透射率下限 0.075（`cumulus.glsl:280-283`）。**C**：Astra 的区间端点二分 + 占用区间（`clouds_planar.glsl:345-347`）在"少采样"上更省，photon 这条路不值得抄。
- CR 命中即断（`reimaginedClouds.glsl:140`），成本随云覆盖率变化；photon 等距步进成本与覆盖率无关。两者是相反的交易，Astra 站在 CR 这一侧。**结论**：不要为了"空区域跳过"去改成等距。
- CR 体积光的幂分布采样 `nextDistance = pow(t, sampleDistribution) * activeThreshold;`（`volumetricLight.glsl:190`），近密远疏。**A**：Astra 的体积雾是等距分段（`volume_fog.glsl:32-41` 只控步数不控分布），把步长换成 `t^2` 分布是一处小改动。

### 17.3 云 · 光照与多重散射

- photon 的 8 次迭代零采样多散射（`cumulus.glsl:164-167`、`178-184`：`scatter_amount *= scattering_falloff * powder_effect;` / `extinct_amount *= 0.4;` / `phase_g *= 0.8;`）。**A**：Astra 的云只有两次 2D 密度采样（`clouds_planar.glsl:501-505`），没有厚云内部柔光。这条**只花 ALU、不花纹理带宽**，是解决"云边缘分层"最直接的一招。作者自己注明这是艺术近似（`common.glsl:66-67` 注释 `max'ing them is completely nonsensical but it looks nice`）。
- piscium 的**解析**多散射收尾 `sampleMSIrradiance *= fMS / (1.0 - fMS);`（`Common.glsl:160-166`）。**A**：比上一条更便宜（3 个 exp、0 采样），可作为先落地的最小改动。注意它是**借用**，出处写在 `Common.glsl:21-24`（`[WDT22]` 中文技术博客 + `[ASH25]` HanPi Volume Cloud 推导），不是原创，移植要遵守相应许可。
- photon 云影是**单样本** + `exp(-密度×厚度/|cos|)`（`cloud_shadows.glsl:94-97`），不步进。Astra 已有同构缓存（`cloud_shadow_cache.glsl:34-43`，边缘回退到实时求值）。**B**：Astra 缺的只是"沿视线步进查这张图"的水晶光柱这一层（photon `crepuscular_rays.glsl:96-99`）。

### 17.4 大气与雾

- photon 大气是**离线烘焙**的 32×64×32 RGB16F 3D LUT（`shaders.properties:408` 的 `texture.deferred.depthtex0 = image/atmosphere/scattering.dat TEXTURE_3D RGB16F 32 64 32 RGB HALF_FLOAT`），运行时双光源共 4 次 3D 采样（`atmosphere.glsl:483-486`）。映射用 Bruneton 2020（许可证原文保留在 `atmosphere.glsl:121-159`）。**B**：Astra 没有任何 LUT，天空是 Complementary 的三方向解析模型（`sky_gradient.glsl:6-8` 自述 `NOT a single vertical gradient`）。LUT 只在"要真实空气透视/日落色散"或"要给下界末地独立大气"时才值得加，否则是纯增成本。
- piscium 把同样的 LUT 改成**运行时 compute 生成**（`air/lut/Common.glsl:21-31` 的 256×64 / 32² / SkyView 4 层×8 深度）。**B**：只有 Astra 需要"多套大气且运行时切换"时才比 photon 的预烘更合适。
- photon 高度雾有**解析闭式解**版本（`analytic.glsl:16-21` 的 `exp2` 差分），0 次纹理采样、4 次迭代多散射（`analytic.glsl:86-97`）；只有需要阴影时才切 roymarch（`raymarched.glsl:94-97`，8~25 步、1/4 像素，`settings.glsl:326` 的 `VL_RENDER_SCALE 0.50`）。**A**：Astra 的 `fog.glsl`（Steadfast FogV2 派生）已经是解析曲线，但没有"解析 + 4 次迭代多散射"这一层，也就是说雾色只有单次散射项。这是**第二有用**的一条。

### 17.5 后处理与时域

- photon bloom 用 tile 金字塔把所有 mip 塞进一张全分辨率纹理（`c5_c10_bloom_downsample.fsh:15-17` 的 `bloom_tile_offset`），13-tap 降采样 + 可分离 9-tap 高斯 + 加权升采样。**C**：Astra 用 Iris 的 mipmap 自动生成（`bloom.glsl:59-61` 注释），tile 方案省的是显式 pass，代价是每 pass 重算边界 + 4 份重复的 `#define`。只有在 mipmap 生成被证明是瓶颈时才换。
- Solas 的 bloom 是单 pass 5 tile × 6×6 = 每像素 180 次纹理取（`computeBloom.glsl:14-19`）。**C（反例）**：明确不该学的写法。
- photon TAA 的裁剪强度随距离变：`c4_taa_exposure.fsh:227` 的 `float gamma = mix(0.75, 1.25, linear_step(0.25, 1.0, distance_factor));`，近处更激进（去鬼影）、远处更保守（防闪）。**A**：Astra 的裁剪是标量阈值（`taa_resolve.fsh:165` 的 `vec3 bounded = clamp(historyColor, lo, hi);`），近处与远处同一强度 —— 这正是"树叶闪"和"远处云抖"无法同时最优的原因之一。
- photon 的混合权重按像素龄：`c4:311-312` 的 `float alpha = max(1.0 / pixel_age, blend_weight);`，静止像素快速收敛到等权平均。**A**：与上一条同源，可以一起做。
- photon 自己注明方差裁剪更容易闪：`c4:68-70` 的注释 `// TAA_VARIANCE_CLIPPING // More aggressive neighborhood clipping method // which further reduces ghosting but can // introduce flickering artifacts`。**结论**：Astra 用 min/max 裁剪不是缺陷，不必为了"跟上 photon"改成方差裁剪。

### 17.6 三条最该先做的（按性价比排序）

1. **像素龄 → 历史 mip**（`sampling.glsl:10`）：**最低风险**。Astra 已有 `cloud_temporal.glsl` 的帧计数与历史，只差"把龄写成可见度/清晰度"这一步；不改缓冲、不改权重公式，直接缓解"云边缘分层 + 时间不稳定"。
2. **解析多散射收尾 `fMS/(1-fMS)`**（piscium `Common.glsl:160-166`）：3 个 exp、0 采样，能立刻让厚云有内部柔光。**注意**：借用自 `[WDT22]`/`[ASH25]`，落地前要确认许可与 `Astra/THIRD-PARTY.md` 记录。
3. **photon 8 次迭代零采样多散射**（`cumulus.glsl:164-184`）：纯 ALU，效果比第 2 条更明显（有相位/粉末/反弹三个分量），但代码量更大、且是"看起来对"的艺术近似。

其余（降分辨率重建、Hi-Z 剔除、LUT 大气、tile bloom）都属于 **B/C 级**：要么需要新增缓冲与 pass，要么与 Astra 现有更省的做法重复或更差。

---

*笔记结束。所有行号以对应本地副本为准；引用行均可用文本逐字搜索回原文件。*