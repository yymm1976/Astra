# A-阴影与光照颜色（B 线）— 外部光影源码取证笔记

> 只读研究产出。没有修改 Astra 的源码、配置、资源、AGENTS.md 或 docs 正文，没有执行 git 操作。
> 本文件是唯一写入物。

## 取证范围与版本

| 简称 | 仓库 | 分支 | commit | 本地副本根目录 |
|---|---|---|---|---|
| photon | sixthsurge/photon | main | 5c79f54 | `spr/photon/photon-main` |
| cr | ComplementaryReimagined | main | c09950d | `spr/cr/ComplementaryReimagined-main` |
| solas | Solas-Shader | main | ea1b4db | `spr/solas/Solas-Shader-main` |
| bliss | Bliss-Shader | Stable | 81e403e | `spr/bliss/Bliss-Shader-Stable` |
| luster | Luster | main | e79cd85 | `spr/luster/Luster-e79cd85…` |

**关于 luster**：luster 是 Photon 的 fork。我比对过两侧文件集合（photon 631 个文件，luster 637 个，luster 独有的多是改名的 `lib/light/*`）。它的 `lib/light/pcss.glsl` 与 `lib/light/distortion.glsl` 是 Photon 同名文件的改名拷贝，逻辑逐行一致。**因此 luster 不作为独立技术成果引用**，只在它能证明「Photon 的某个做法被另一个作者原样保留」时提一句。

**证据强度标记**：每条都写明是「读了源码」（可直接按行号核对原文）还是「根据源码的推断」（可能被编译器优化，或默认配置根本走不到那条分支）。没读到证据的写「未验证」。

---

## 1. Photon：四次方范数畸变，以及「逐采样反畸变」为什么合法

**技术目标**：把有限的阴影贴图分辨率堆在玩家附近；同时让接收端能便宜且精确地把任意一个采样偏移还原回未畸变空间。

**实现位置**

`photon/shaders/include/lighting/shadows/distortion.glsl:6-9`

```glsl
// Euclidian distance is defined as sqrt(a^2 + b^2 + ...). This function instead
// does quartic_root(a^4 + b^4 + ...). This results in smaller distances along
// the diagonal axes
float quartic_length(vec2 v) { return sqrt(sqrt(pow4(v.x) + pow4(v.y))); }
```

`photon/shaders/include/lighting/shadows/distortion.glsl:11-13`

```glsl
float get_distortion_factor(vec2 shadow_clip_pos) {
    return quartic_length(shadow_clip_pos) * SHADOW_DISTORTION
        + (1.0 - SHADOW_DISTORTION);
```

`photon/shaders/include/lighting/shadows/distortion.glsl:16-18`

```glsl
vec3 distort_shadow_space(vec3 shadow_clip_pos, float distortion_factor) {
    return shadow_clip_pos
        * vec3(vec2(rcp(distortion_factor)), SHADOW_DEPTH_SCALE);
```

**算法机制**

畸变因子是「裁剪空间半径」的一个函数，用的是四次方范数 `(x^4+y^4)^(1/4)`，不是欧氏长度。四次方范数在对角方向给出更小的半径，所以同一个 `SHADOW_DISTORTION` 常数下，对角线方向的压缩比轴向更弱——贴图密度分布更接近方形而不是圆形。因子先乘 `SHADOW_DISTORTION` 再加 `(1-`SHADOW_DISTORTION`)`，所以中心处因子为 1（不缩放），越往外压缩越强。Photon 默认 `SHADOW_DISTORTION = 0.85`（`photon/shaders/settings.glsl:139`），即几乎完全按半径线性压缩。

关键在于 `distort_shadow_space` 把 xy **除以**因子、z **乘以** `SHADOW_DEPTH_SCALE`（= 0.2，见 `photon/shaders/settings.glsl:138`）。四次方范数是**一次齐次**的：`quartic_length(s·v) = s·quartic_length(v)`（s>0）。所以对任意已经畸变过的坐标 `uv`，`uv / get_distortion_factor(uv)` 正好把它还原。这就是为什么 PCSS/PCF 里每个采样点都能单独反畸变，不需要构建逆矩阵：

`photon/shaders/include/lighting/shadows/pcss.glsl:121-125`

```glsl
            = vogel_disc_sample(i, step_count, dither * tau) * filter_radius;

        vec2 uv = shadow_clip_pos.xy + offset;
        uv /= get_distortion_factor(uv);
        uv = uv * 0.5 + 0.5;
```

另外 `distortion.glsl:26-31` 里有一个显式反畸变函数 `undistort_shadow_space`。我 grep 过全仓，它只有定义、没有调用点（唯一命中就是 `distortion.glsl:26` 那一行），所以默认路径就是上面那个逐采样除法。**这是读了源码的结论。**

**开销与代价**

每次采样多两次 `sqrt` 加一次倒数。**不占显存，不加 pass。**压缩的代价是贴图外圈纹元变大，但因子本身连续，不会出现接缝。

**适用范围与失效边界**

`SHADOW_DISTORTION = 1.0` 时中心因子为 0，会除零，代码没有防护。默认给 0.85 而不是 1.0，推测与此有关，但源码没有注释说明，**这是推断**。`SHADOW_DEPTH_SCALE` 必须与写端一致，写端见第 2 节。

**与 Astra 的关系**

Astra 已经有等价能力，而且公式不同。`Astra/shaders/lib/distort.glsl:25-27`：

```glsl
float get_distort_factor(vec2 pos) {
    return length(pos) + SHADOW_DISTORT_FACTOR;
}
```

Astra 用的是 `length(pos) + SHADOW_DISTORT_FACTOR`（欧氏长度加常数，Steadfast 血统），而 `Astra/shaders/lib/distort.glsl:20` 是 `const float SHADOW_DISTORT_FACTOR = SHADOW_DISTORT_CORE / shadowDistance;`，配合 `Astra/shaders/lib/distort.glsl:16` 的 `const float SHADOW_DISTORT_CORE = 25.6;`。文件头 `lib/distort.glsl:9-15` 的注释解释了为什么把细节锚在「块数」而不是固定比例。

Astra 的反畸变是解析逆 `a/(1-|q|)`（`lib/distort.glsl:45`），不是逐采样除法。

判断：**Astra 不需要照搬四次方范数。** Photon 的逐采样除法成立，靠的是「因子对半径线性」这个性质；Astra 的 `length+a` 对半径同样线性（只是多了常数项），所以也能逐采样反解，只是 Astra 已经用解析逆覆盖了同一需求（`Astra/shaders/program/shadow.fsh:61` 用 `undistort` 取回光线）。**Astra 的畸变体系不比 Photon 弱。**


---

## 2. Photon：写读两端的深度缩放，以及只用法线偏移的 bias

**技术目标**：在不产生 peter-panning（影子与投射物分离）的前提下压住阴影痤疮。

**实现位置**

写端 `photon/shaders/program/shadow.vsh:123-126`

```glsl
    vec3 shadow_clip_pos = project_ortho(gl_ProjectionMatrix, pos);
    shadow_clip_pos = distort_shadow_space(shadow_clip_pos);

    gl_Position = vec4(shadow_clip_pos, 1.0);
```

bias `photon/shaders/include/lighting/shadows/distortion.glsl:36-44`

```glsl
vec3 get_shadow_bias(vec3 scene_pos, vec3 normal, float NoL, float skylight) {
#if defined WORLD_END
    skylight = 1.0;
#endif

    // Shadow bias without peter-panning
    return 0.25 * normal * clamp01(0.12 + 0.01 * length(scene_pos))
        * (2.0 - clamp01(NoL));
}
```

**算法机制**

读端拿到的 z 先乘 0.2 再映射到 [0,1]（调用处的 `* 0.5 + 0.5`），写端做同一个 0.2。bias 只有一项：沿法线推 `0.25 * (0.12 + 0.01*|pos|) * (2 - clamp01(NoL))`。三个因子分别是固定基数、随距离线性增长（远处纹元更大）、随掠射角增长（NoL 越小偏移越大，最多翻倍）。

注意函数签名吃了 `skylight` 参数，但**函数体里除了 `WORLD_END` 强制置 1 之外完全没有用到它**（`distortion.glsl:36-44` 全文就是这几行）。也就是说 Photon 的「bias 按天光调整」只服务于末地分支，主世界没有这条。

**开销与代价**

零采样、零显存，纯算术。

**适用范围与失效边界**

只有法线偏移，没有 receiver-plane 重建，没有斜率缩放（slope-scaled bias）。极低太阳角（NoL→0）时靠 `(2-NoL)` 最多翻倍，等于固定的上界 `0.5*(0.12+0.01d)` 块；d=100 时约 0.25 块。比 Astra 现有的做法粗。**这是读了源码的结论。**

**与 Astra 的关系**

Astra 的 bias 分两级，而且带平面修正。`Astra/shaders/global/lighting/shadowmap.glsl:404-412`：

```glsl
    // Steadfast's normal offset is paired with its radial projection. All PCF
    // taps compare the same Z; no screen-derivative plane inversion is involved.
    // 1.5 is a world-block coefficient applied to dimensionless map radius.
    // The shadow projection is orthographic (w=1), not camera perspective depth.
    float bias = 1.5 * length(raw.xy)
               + shadowGrazingBias * (1.0 - max(ndotl, 0.0));
    vec3 shadowPos = distort(player_shadow(playerPos + worldNormal * bias)) * 0.5 + 0.5;
    shadowPos.z -= 0.00001;
    return shadowPos;
```

主世界项是 `1.5 * length(raw.xy) + 0.20*(1-max(ndotl,0))`——**随贴图半径线性增长**（畸变后半径越大的地方纹元越大），外加一个掠射项。末地支路更细，按纹元尺寸乘 cot 斜率（`shadowmap.glsl:381-395`，注释里算了 0.09375 块/纹元 × cot(23°)=0.221 块的自阴影误差）。

判断：**Photon 的公式比 Astra 简单，唯一共同点是「按贴图半径线性」，而 Astra 已经有了。不建议移植。**

---

## 3. Photon：PCSS 可变半影 + 最小滤核 + 小半影反锐化（本笔记最核心的一条）

**技术目标**：接触处锐利、远处柔和，同时不让抖动吃掉锐度。这是 Astra 已知痛点「树叶/植物阴影移动时闪烁」与「树干斜亮带」最接近的参考答案。

**实现位置**

半影来源（VPS 开启时）`photon/shaders/include/lighting/shadows/pcss.glsl:243-252`

```glsl
    }

    float penumbra_size = 16.0 * SHADOW_PENUMBRA_SCALE
        * (shadow_screen_pos.z - blocker_search_result.x)
        / blocker_search_result.x;
    penumbra_size
        *= 5.0 - 4.0 * cloud_shadows; // Increase penumbra radius inside cloud
                                      // shadows, nice overcast look
    penumbra_size = min(penumbra_size, SHADOW_BLOCKER_SEARCH_RADIUS);
    penumbra_size *= shadowProjection[0].x;
```

最小滤核与步数缩放 `pcss.glsl:101-111`

```glsl
    // penumbra_size > max_filter_radius: blur
    // penumbra_size < min_filter_radius: anti-alias (blur then sharpen)
    float distortion_factor = get_distortion_factor(shadow_clip_pos.xy);
    float min_filter_radius = 2.0 * shadow_map_pixel_size * distortion_factor;

    float filter_radius = max(penumbra_size, min_filter_radius);
    float filter_scale = sqr(filter_radius / min_filter_radius);

    int step_count
        = int(SHADOW_PCF_STEPS_MIN + SHADOW_PCF_STEPS_SCALE * filter_scale);
    step_count = min(step_count, SHADOW_PCF_STEPS_MAX);
```

反锐化 `pcss.glsl:174-185`

```glsl
    float rcp_steps = rcp(float(step_count));

    // sharpening for small penumbra sizes
    float sharpening_threshold
        = 0.4 * max0((min_filter_radius - penumbra_size) / min_filter_radius);
    shadow = linear_step(
        sharpening_threshold,
        1.0 - sharpening_threshold,
        shadow * rcp_steps
    );

    return shadow * color;
```

**算法机制（数据怎么流动）**

1. 先在 `shadowtex0`（含半透明）上做遮挡体搜索，拿到平均遮挡深度 `blocker_depth`。搜索用 Vogel disc，步数 3（带 SSS 时 12），见 `pcss.glsl:29-55`。
2. 用相似三角形算半影：`16 * PENUMBRA_SCALE * (receiver_z - blocker_z) / blocker_z`。接收面离遮挡体越远，半影越大。之后用 `min(..., SHADOW_BLOCKER_SEARCH_RADIUS)` 封顶，最后乘 `shadowProjection[0].x` 从裁剪空间换到贴图空间。
3. **最小滤核**：`min_filter_radius = 2.0 * texel * distortion_factor`，也就是「永远至少滤两个纹元」。这一条正是「接触处不闪烁」的关键——半影公式在接触处会给出接近 0 的半径，直接用它的话所有采样点都落在同一个纹元里，等于硬边，移动时就是二值跳变。
4. 实际核半径 `filter_radius = max(penumbra, min_filter_radius)`，步数按 `(filter_radius/min_filter_radius)^2` 缩放——即**面积比例**，从 6 起、上限 12。
5. 因为核被抬到了最小半径，本该锐利的地方被过度模糊了，所以**再锐化回来**：`sharpening_threshold = 0.4 * (min_filter - penumbra)/min_filter`。接触处半影接近 0，阈值接近 0.4，把平均后的 [0,1] 值用 `linear_step(0.4, 0.6, x)` 拉成接近阶跃；半影大于等于最小核时阈值降到 0，什么都不做。这是一条「先模糊、再反锐化、只在小半影生效」的自适应链。

**开销与代价（静态推断，不是实测）**

- 遮挡体搜索：3 次 `texelFetch(shadowtex0)`（不能用硬件比较，因为要读原始深度求平均）。默认 `SSS_STEPS = 12`（`photon/shaders/settings.glsl:131`）时，带 SSS 的材质是 12 次。
- PCF 主体：`step_count` 默认 `MIN=6 / MAX=12 / SCALE=1.0`（`photon/shaders/settings.glsl:133-135`），即**每像素 6~12 次 `texture(shadowtex1)`（硬件 2D 比较采样），前 4 次还要额外做彩色阴影采样**。
- 提前退出：`pcss.glsl:155-160` 在累计 4 次之后，若全在影内或全在影外就直接返回。**这是每像素条件分支**，同一 warp 内不一致时两边都要走（静态推断，具体取决于驱动）。
- 不需要历史缓冲，不需要额外附件，纯前向每像素开销。

**适用范围与失效边界**

- 整段包在 `#if defined SHADOW && (defined WORLD_OVERWORLD || defined WORLD_END)`（`pcss.glsl:4`），**下界根本不编译这段**。
- VPS 是可选宏，但 `photon/shaders/settings.glsl:125` 默认就是 `#define SHADOW_VPS`，而且 `settings.glsl:120-124` 默认同时打开 `SHADOW`/`SHADOW_SSRT`/`SHADOW_PCF`/`SHADOW_COLOR`。所以默认配置下走的就是上面这条路径。
- 遮挡体搜索在贴图之外的采样**没有做 uv 裁剪**——`pcss.glsl:43-49` 直接 `texelFetch`。而 luster 的同名函数补了裁剪：

`luster/shaders/lib/light/pcss.glsl:66-68`

```glsl
        if (clamp01(uv) != uv) {
            continue; // out of shadow map: undefined texelFetch
        }
```

这说明 Photon 版在贴图边缘会读未定义纹元，luster 作者补的正是这个缺口。**这是读了两个仓库源码的对照结论**，不是推断。

**与 Astra 的关系**

Astra **完全没有 PCSS**。我 grep 过 Astra 全仓，`blocker`/`penumbra`/`pcss` 的命中只有注释文字，没有遮挡体搜索。

Astra 现在用的是**固定足迹、四叶瓣、不旋转**的方案，`Astra/shaders/global/lighting/diffuse.glsl:341-354`：

```glsl
        for (int lobe=0;lobe<lobeCount;++lobe) {
            #if SHADOW_FILTER_QUALITY == 1
            // Fixed radius/weights across texel boundaries. Gating extra lobes
            // on centre visibility clipped their support and made stair bumps.
            vec2 offset=vec2((lobe & 1)==0 ? -1.0 : 1.0,
                             (lobe & 2)==0 ? -1.0 : 1.0)*(0.70710678*spread);
            #else
            vec2 offset = vec2((lobe & 1) == 0 ? -1.0 : 1.0,
                               (lobe & 2) == 0 ? -1.0 : 1.0)*spread;
            #endif
            filtered += shadow_lobe_light_inside(shadowPos.xy+offset/float(shadowMapResolution),
                shadowPos.z,receiverWorldY,shadowSize,opaqueFirst)
                /float(lobeCount);
        }
```

并且有「按世界纹元宽度钳制柔度」的一段，`Astra/shaders/global/lighting/diffuse.glsl:315-327`：

```glsl
        // Bound world softness, but retain at least half the requested texel
        // spread: shrinking all four lobes onto the same bilinear footprint
        // at the map rim would bring back hard steps on distant leaf shadows.
        // The minimum is texture-relative, fixed across frames, and never
        // exceeds the user's softness. Coarse distant maps can therefore blur
        // beyond the preferred world radius; coverage still fades at the rim.
        float mapRim = max(1.0-length(shadowPos.xy*2.0-1.0),0.0001);
        // Inverse radial derivative: p = a*q/(1-|q|), so dp/d|q| =
        // a/(1-|q|)^2. The squared rim is the widest texel axis, not a duplicate.
        float worldTexel = (2.0*shadowDistance*SHADOW_DISTORT_FACTOR)
                         / (float(shadowMapResolution)*mapRim*mapRim);
        float softRadius=max(0.22,0.75*sqrt(astraSurfaceShadowPixelWorldSquared));
        spread = clamp(softRadius/max(worldTexel,0.0001),0.5*spread,spread);
```

**判断（优先级最高的一条）**：Astra 的「接触处锐利 + 不闪烁」是靠**固定足迹 + 不旋转 + 世界纹元下限**达成的，代价是**柔度不能随距离增长**——`spread` 的上限就是 `SHADOW_SOFTNESS`（默认 2，见 `Astra/shaders/lib/settings.glsl:88`），远处阴影不会像 Photon 那样自然变柔。Photon 用「最小滤核保下限 + PCSS 抬上限 + 小半影反锐化」给出了同时满足两端的结构性方案。**要解决「树干斜亮带」这类半影方向性伪影，Photon 的 blocker→penumbra 链路正是 Astra 结构上缺的一环。**

---

## 4. Photon：Vogel disc + 帧间旋转抖动，以及「抖了但不闪」的两个前提

**技术目标**：用很少的样本覆盖较大的核，并让残余噪声在时间维度上均化。

**实现位置**

`photon/shaders/include/utility/sampling.glsl:4-11`

```glsl
vec2 vogel_disc_sample(int step_index, int step_count, float rotation) {
    const float golden_angle = 2.4;

    float r = sqrt(step_index + 0.5) / sqrt(float(step_count));
    float theta = step_index * golden_angle + rotation;

    return r * vec2(cos(theta), sin(theta));
}
```

抖动源 `photon/shaders/include/lighting/shadows/pcss.glsl:229-230`

```glsl
    float dither = texelFetch(noisetex, ivec2(gl_FragCoord.xy) & 511, 0).b;
    dither = r1(frameCounter, dither);
```

**算法机制**

Vogel disc 是等面积的向日葵螺旋（`r = sqrt(i+0.5)/sqrt(N)`），比固定网格更均匀。旋转量来自一张噪声纹理的蓝噪声，再以黄金比例的倒数按帧号推进（`photon/shaders/include/utility/random.glsl:10-13`），是低差异序列而不是纯随机，因此任意相邻两帧的样本集互补，时间平均收敛快。

「抖了但不闪」靠两点：(a) 第 3 节的最小滤核——核永远至少 2 纹元，所以抖动不是在一个纹元里跳；(b) 反锐化把被抬高的核重新压回硬边。两者配合，抖动只作用在真正的半影区。

**开销与代价**

`r1` 是两次乘加加 fract；采样坐标多一次乘。零显存。

**失效边界**

没有 TAA 时，抖动会直接表现为每帧变化的噪声。Photon 有 TAA（`program/c4_taa_exposure.fsh`），所以没问题。但源码里**没有把抖动与 TAA 绑定的开关**，所以「必须配 TAA」是**推断**。

**与 Astra 的关系**

Astra 明确不用旋转。`Astra/shaders/global/lighting/diffuse.glsl:373-376`：

```glsl
        #elif SHADOW_FILTER_QUALITY == 0
        // Keep individual depth/caster pairs; a stable bilinear footprint needs
        // neither a rotating sample pattern nor temporal antialiasing.
        #if !defined DIMENSION_NETHER && !defined DIMENSION_END
```

**判断**：这是两条互斥的工程路线。Astra 的选择在「不闪」上更稳（没有时间噪声），代价是柔度上限被锁死。**不要在还没有 PCSS 的前提下给 Astra 加旋转抖动**——那会把稳定的固定足迹换成每帧噪声，正好命中已知痛点。


---

## 5. Photon：彩色阴影、光缝掩盖，以及半透明走独立的投影位置

**技术目标**：彩色玻璃和水应该有染色阴影；但不能在彩色阴影与不透明阴影的接缝处露出亮线；同时水焦散不能吃到「防漏光偏移」。

**实现位置**

`photon/shaders/include/lighting/shadows/pcss.glsl:67-85`

```glsl
#ifdef SHADOW_COLOR
    ivec2 texel = ivec2(shadow_screen_pos.xy * shadow_map_res);

    float depth = texelFetch(shadowtex0, texel, 0).x;
    vec3 color = texelFetch(shadowcolor0, texel, 0).rgb * 4.0;
    float weight = step(depth, shadow_screen_pos.z);

    vec3 averageColor = vec3(0.0);
    for (int i = 0; i < 9; ++i) {
        averageColor
            += texelFetch(shadowcolor0, texel + blur_kernel_offsets_3x3[i], 0)
                   .rgb;
    }
    // hide sunlight seams between colored shadow and opaque shadows
    weight *= step(eps, max_of(averageColor));

    color = color * weight + (1.0 - weight);

    return shadow * color;
```

半透明用独立位置 `pcss.glsl:261-270`

```glsl
#ifdef SHADOW_COLOR
    // Calculate position without light leaking fix applied, for colored shadow
    // Applying light leaking fix to translucent shadows causes artifacts on
    // water caustics
    vec3 shadow_view_pos_translucent
        = transform(shadowModelView, scene_pos + bias);
    vec3 shadow_clip_pos_translucent
        = project_ortho(shadowProjection, shadow_view_pos_translucent);
    vec3 shadow_screen_pos_translucent
        = distort_shadow_space(shadow_clip_pos_translucent) * 0.5 + 0.5;
```

**算法机制**

`shadowtex1` 是**只含不透明**遮挡物的深度，`shadowtex0` 是含半透明的。所以「`shadowtex0` 命中而 `shadowtex1` 未命中」意味着这一层是半透明，读 `shadowcolor0` 的染色。染色以 4 倍存储（写端 0.25、读端 ×4.0）以保住 8 位精度。

光缝掩盖用的是 3×3 平均色：如果周围一圈全黑（`max_of(averageColor) < eps`），就把权重清零退回白光——避免半透明阴影与不透明阴影交界处出现一条透光的缝。

半透明**故意不加防漏光偏移**（用 `scene_pos + bias` 而不是 `+ bias + edge_factor`），注释给的理由是「会把伪影加到水面焦散上」。

**开销与代价（静态推断）**

开启 `SHADOW_COLOR` 时，每个像素**前 4 次** PCSS 采样各多一次 `texelFetch(shadowtex0)` 加一次 `texelFetch(shadowcolor0)`，即额外 8 次纹理读取/像素；基础路径再多 9 次（3×3 平均）。默认 `photon/shaders/settings.glsl:124` 是开的。

**与 Astra 的关系**

Astra 已经有更强的版本——它把每个角点的深度和染色**配对**处理，而不是整像素混合。`Astra/shaders/global/lighting/shadowmap.glsl:293-300`：

```glsl
    vec4 transparentWeight = max(opaqueVisibility-allVisibility, vec4(0.0)) * weights;
    // Preserve each corner's discrete caster, including mixed water/glass edges.
    if (any(greaterThan(transparentWeight, vec4(0.0)))) {
        #if !defined DIMENSION_NETHER && !defined DIMENSION_END && !defined COLORED_SHADOWS && !defined WATER_CAUSTICS
        // Both caster responses are white with these options off. The paired
        // depths already supply the complete result, with no caster payload.
        return light + vec3(dot(transparentWeight, vec4(1.0)));
        #endif
```

而且有专门的快速路径（`shadowmap.glsl:301-318`）：四个角点全是水时用 `textureGather` 一次取四个高度，避免四次完整 RGBA 读取。

**判断**：**Astra 的彩色阴影结构比 Photon 更细**（逐角点保留 identity，`shadowmap.glsl:181-183` 注释明说「Keep them separate until each corner's tint/water identity is resolved」）。Photon 的 3×3 平均掩盖光缝是个小技巧，但 Astra 用「逐角点不混合」从根上避免了混色，不需要它。**不移植。**

---

## 6. Photon：屏幕空间阴影 SSRT，作为阴影距离外的替代

**技术目标**：阴影贴图覆盖不到的远处，用屏幕空间光线步进补上，而不是退回「天光够亮就当没影子」。

**实现位置**

`photon/shaders/include/lighting/shadows/ssrt.glsl:20-22`

```glsl
    const uint step_count = uint(SHADOW_SSRT_STEPS);
    const float step_ratio = 2.0; // geometric sample distribution
    const float z_tolerance = 10.0; // assumed thickness in blocks
```

光线长度被**世界尺度**钳制，`ssrt.glsl:33-40`

```glsl
    float ray_length = min_of(
        abs(sign(ray_dir_screen) - ray_origin_screen)
        / max(abs(ray_dir_screen), eps)
    );
    ray_length = min(
        ray_length,
        max(0.1, exp(-max0(length(ray_origin_view) * 0.025 - 1.0)))
    );
```

命中判据 `ssrt.glsl:83-85`

```glsl
        bool inside = depth != 0.0 && depth < dithered_pos.z
            && abs(z_tolerance - (z_ray - z_sample)) < z_tolerance;
        hit = inside || hit;
```

**算法机制**

在屏幕空间沿光方向步进，步长按几何级数增长（`step_ratio = 2.0`），每一步把屏幕坐标换回视空间深度做比较。命中条件是「这条屏幕光线穿到某个已经存在的表面后面，并且穿透厚度小于 `z_tolerance = 10` 块」——10 块是「假设的遮挡体厚度」，超过就认为穿过了薄物（比如树叶），继续往前走。光线长度同时受屏幕边界和世界距离限制，世界那一项是 `max(0.1, exp(-max0(|origin|*0.025 - 1)))`。另外每个片段把光线方向扰动 `0.03` 球面采样（`ssrt.glsl:126-127`）来制造软边。

**开销与代价（静态推断）**

默认 `SHADOW_SSRT_STEPS = 10`（`photon/shaders/settings.glsl:122`）次 `texelFetch(depthtex1)`，再加每次的矩阵变换。**只对阴影距离外的像素执行**（`program/d4_deferred_shading.fsh:504` 的 `if (shadow_distance_fade >= eps)` 门控）。是全分辨率每像素，不是半分辨率。

**适用范围与失效边界**

- 只有屏幕里有的东西能挡住——屏幕外、背后的遮挡物一律当作不存在。
- 与阴影贴图按 `shadow_distance_fade` 混合（`d4_deferred_shading.fsh:522-526`）。
- `photon/shaders/program/voxy_translucent.glsl:12-13` 在 Voxy 半透明程序里显式 `#undef SHADOW_SSRT`，说明这条路径与 LoD/半透明有已知冲突。

**与 Astra 的关系**

Astra **没有 SSRT**（grep `SSRT` 与 `raymarch_shadow` 都是零命中）。远处的做法是 `static_shadow()`，`Astra/shaders/global/lighting/shadowmap.glsl:417-419`：

```glsl
float static_shadow(float skyLight) {
    return smoothstep(13.5 / 15.0, 14.5 / 15.0, skyLight);
}
```

即「天光 ≥14.5/15 就当全亮」。这正是 Photon 用 SSRT 替代的那个退路。

**判断**：SSRT 是大工程（需要深度附件、矩阵、按帧预算），而且它的失效边界（屏幕外无效、穿透厚度假设）意味着它救不了「远处树影投在地上」这种最主要的需求——树在屏幕外的时候它什么都看不到。**不建议为当前痛点引入 SSRT。**

---

## 7. Photon：阴影距离淡出与洞内假阴影

**实现位置** `photon/shaders/include/lighting/shadows/common.glsl:5-27`

```glsl
float get_shadow_distance_fade(vec3 scene_pos, vec3 shadow_screen_pos) {
    float effective_shadow_distance = min(shadowDistance, far);
    return linear_step(
        0.1,
        1.0,
        pow32(
            max(max_of(abs(shadow_screen_pos.xy * 2.0 - 1.0)),
                length_squared(scene_pos) * rcp(sqr(effective_shadow_distance)))
        )
    );
}

// Fake, lightmap-based shadows for outside of the shadow range or when shadows
// are disabled
float get_lightmap_shadows(float skylight) {
    return smoothstep(13.5 / 15.0, 14.5 / 15.0, skylight);
}

// Prevents light leaking in caves by cancelling out sunlight in very low
// skylight
float get_lightmap_light_leak_prevention(float skylight) {
    return smoothstep(0.0 / 15.0, 2.0 / 15.0, skylight);
}
```

**算法机制**

淡出因子同时吃「贴图 uv 是否到边缘」和「世界距离是否到 shadowDistance」，取两者最大之后用 32 次幂——幂次极高，所以过渡带非常窄，几乎是硬切换。`get_lightmap_shadows` 把天光 13.5~14.5 之间映射成「有影子→无影子」，用作阴影贴图之外的退路；`get_lightmap_light_leak_prevention` 用一个 0~2/15 的 smoothstep 把极暗处的方向光彻底掐掉，防止洞里漏进阳光。

**与 Astra 的关系**

Astra 在做同一件事，但用世界块数而不是 uv，`Astra/shaders/global/lighting/shadowmap.glsl:116-123`：

```glsl
    #else
    // SC-35 shadow round: 16/4 -> 24/8. The old band ended 4 blocks inside
    // the map edge and faded the last visible shadows on top of the larger
    // 256-block map; the wider band keeps coverage gradual instead of popping.
    return 1.0 - smoothstep(shadowDistance - 24.0, shadowDistance - 8.0,
                            shadow_box_distance(playerPos));
    #endif
}
```

注释记录了这轮调参的原因（16/4 改成 24/8，为了不 popping）。而 `static_shadow` 用的阈值正是 13.5/14.5（`shadowmap.glsl:418`），与 Photon 完全相同——**这是两家共同收敛出来的做法，说明阈值本身不是问题所在**。

**判断**：无新信息。Astra 按块数淡出比 Photon 的 uv+距离双重判据更直观，注释里的调参理由也更清楚。**不移植。**


---

## 8. Bliss：对数畸变，把纹元尺寸分布拉平

**技术目标**：径向畸变 `p/(|p|+a)` 在中心附近纹元变化剧烈、外圈又变得很快；Bliss 想让每个环带上的纹元数更均匀。

**实现位置** `bliss/shaders/lib/Shadow_Params.glsl:4-26`

```glsl
const float k = 1.8;
const float d0 = 0.04  + max(64.0 - shadowDistance, 0.0)/64.0  * 0.26;
const float d1 = 0.61;
float a = exp(d0);
float b = (exp(d1)-a)*150./128.0;

// thank you Espen
// #ifdef DISTANT_HORIZONS_SHADOWMAP
//   float b = (exp(d1)-a)*min(dhRenderDistance, shadowDistance)/shadowDistance;
// #else
//   float b = (exp(d1)-a)*min(far+16.0*3.5, shadowDistance)/shadowDistance;
// #endif

vec4 BiasShadowProjection(in vec4 projectedShadowSpacePosition) {
  
  float distortFactor = log(length(projectedShadowSpacePosition.xy)*b+a)*k;
  projectedShadowSpacePosition.xy /= distortFactor;
  return projectedShadowSpacePosition;
}

float calcDistort(vec2 worldpos){
  return 1.0/(log(length(worldpos)*b+a)*k);
}
```

**算法机制**

畸变因子不是 `length + a`，而是 `log(length*b + a) * k`。对 log 求导得 `1/(length*b + a)`——也就是说**纹元的世界尺寸随半径按 1/r 衰减**，而不是径向投影的 `1/(r+a)^2`。这让外圈的纹元不会膨胀得那么快。

`calcDistort` 返回 `1/畸变因子`，供**核半径**使用：`bliss/shaders/dimensions/composite.fsh:507` 的 `rdMul = distortFactor*(1+mult)*d0*k/shadowMapResolution`——核半径直接与「该处的纹元世界尺寸」挂钩。这是 Bliss 版的「按纹元标定过滤半径」。

**开销与代价**

每像素一次 `log`（比 sqrt 贵），外加若干乘加。零显存。

**失效边界**

`d0` 依赖 `shadowDistance`（`Shadow_Params.glsl:5`：`0.04 + max(64-distance,0)/64*0.26`），也就是**换阴影距离就要重调常数**，否则畸变曲线会错位。源码里「thank you Espen」下面留了 Distant Horizons 的替代式，说明作者自己也在为多场景适配这个常数。

**与 Astra 的关系**

Astra 用解析的纹元宽度换算代替经验常数，`Astra/shaders/global/lighting/diffuse.glsl:321-327`（见第 3 节已引）。注释里推导了 `dp/d|q| = a/(1-|q|)^2`，所以 `worldTexel = 2*distance*FACTOR/(res*mapRim^2)`。

**判断**：**Astra 的解析纹元宽度严格优于 Bliss 的经验 log 拟合**——不需要随 shadowDistance 重调常数。**不移植。** 但 Bliss 有一点值得记：它把核半径显式表达成「纹元数 × 局部纹元尺寸」，而 Astra 是在 `diffuse.glsl:327` 用 `clamp(softRadius/worldTexel, 0.5*spread, spread)` 做的，思路相同。

---

## 9. Bliss：Gri/Emin 阴影修正，以及两遍 PCSS（模糊与锐化分离）

**技术目标**：同时压住 peter-panning 和 light leaking（洞里漏光），并让半影半径由遮挡体距离决定。

**实现位置**

bias 修正 `bliss/shaders/lib/Shadows.glsl:1-26`

```glsl
// Emin's and Gri's combined ideas to stop peter panning and light leaking, also has little shadowacne so thats nice
// https://www.complementary.dev/reimagined
// https://github.com/gri573
void GriAndEminShadowFix(
	inout vec3 WorldPos,
	vec3 FlatNormal,
	float VanillaAO,
	float SkyLightmap
){

	float MinimumValue = 0.05;

	// give a tiny boost to the distance mulitplier when shadowmap resolution is below 2048.0
	float ResMultiplier = 1.0 + (shadowDistance/8.0)*(1.0 - min(shadowMapResolution,2048)/2048.0)*0.3;

	float DistanceMultiplier = max(1.0 - max(1.0 - length(WorldPos) / shadowDistance, 0.0), MinimumValue) * ResMultiplier;

	vec3 Bias = FlatNormal * DistanceMultiplier;

	// stop lightleaking by zooming up, centered on blocks
	vec2 scale = vec2(0.5); scale.y *= 0.5;
	vec3 zoomShadow =  scale.y - scale.x * fract(WorldPos + cameraPosition + Bias*scale.y);
	if(SkyLightmap < 0.1) Bias = zoomShadow;

	WorldPos += Bias;
}
```

第一遍算 blocker 与半径 `bliss/shaders/dimensions/composite.fsh:503-539`

```glsl
					float mult = maxshadowfilt;
					float avgBlockerDepth = 0.0;
					vec2 scales = vec2(0.0, Max_Filter_Depth);
					float blockerCount = 0.0;
					float rdMul = distortFactor*(1.0+mult)*d0*k/shadowMapResolution;
					float diffthreshM = diffthresh*mult*d0*k/20.;
					float avgDepth = 0.0;

					for(int i = 0; i < VPS_Search_Samples; i++){

						// vec2 offsetS = SpiralSample(i, 7, 8, noise) * 0.5;
						vec2 offsetS = CleanSample(i, VPS_Search_Samples - 1, noise) * 0.5;
						
						float weight = 3.0 + (i+noise) *rdMul/SHADOW_FILTER_SAMPLE_COUNT*shadowMapResolution*distortFactor/2.7;
						
						float d = texelFetch2D(shadow, ivec2((projectedShadowPosition.xy+offsetS*rdMul)*shadowMapResolution),0).x;
						float b = smoothstep(weight*diffthresh/2.0, weight*diffthresh, projectedShadowPosition.z - d);

						blockerCount += b;

						#ifdef DISTANT_HORIZONS_SHADOWMAP
							avgDepth += max(projectedShadowPosition.z - d, 0.0)*10000.0;
						#else
							avgDepth += max(projectedShadowPosition.z - d, 0.0)*1000.0;
						#endif
						
						avgBlockerDepth += d * b;
					}
					
					gl_FragData[0].g = avgDepth / VPS_Search_Samples;
					gl_FragData[0].b = blockerCount / VPS_Search_Samples;
					
					if (blockerCount >= 0.9){
						avgBlockerDepth /= blockerCount;
						float ssample = max(projectedShadowPosition.z - avgBlockerDepth,0.0)*1500.0;
						gl_FragData[0].r = clamp(ssample, scales.x, scales.y)/(scales.y)*(mult-minshadowfilt)+minshadowfilt;
					}
```

**算法机制**

Gri/Emin 修正：法线偏移量随距离**减小**（`1 - dist/shadowDistance`，下限 0.05），这与 Photon 的「随距离增大」相反。理由大概是外圈纹元本来就很大，不需要再堆偏移。当 `SkyLightmap < 0.1`（暗处）时改用 `zoomShadow`——一个**以方块为周期、把位置往块中心吸附**的偏移，专门治洞穴漏光。

两遍 PCSS：`composite.fsh` 在第一遍算三个量写进 `gl_FragData[0]`：`.g = 平均深度差`、`.b = blocker 比例`、`.r = 滤波半径`（`clamp(ssample, 0, Max_Filter_Depth)/Max_Filter_Depth*(max-min)+min`）。第二遍（`composite1.fsh:641-696`）用双边上采样把这三通道按深度边缘过滤后，再用 `.r` 当核半径做最终 PCF。

**开销与代价（静态推断）**

多一个 pass（本来就有 composite，不算新增）加一次双边上采样（4 邻居 × 3 通道）。默认 `VPS_Search_Samples = 4`、`SHADOW_FILTER_SAMPLE_COUNT = 13`（`bliss/shaders/lib/settings.glsl:145,151`）——**即最终 PCF 每像素 13 次采样**，比 Photon 的 6~12 略多。`Min/Max_Shadow_Filter_Radius = 5.0/30.0`（`settings.glsl:146-147`）。

**失效边界**

`Variable_Penumbra_Shadows` 默认开着（`settings.glsl:144`），但整段在 `#ifdef OVERWORLD_SHADER` 内。第一遍里有个 `if (LabSSS > -1)`，而 `LabSSS` 由 `clamp((-64+SpecularTex*255)/191, 0, 1)` 得到（`composite.fsh:458`），**永远 ≥0，所以这个条件恒真**——是个死条件（读源码可见，属实现残留）。

**与 Astra 的关系**

Astra 的漏光处理是「把参考点往块中心混」，而不是整体吸附（`Astra/shaders/global/lighting/diffuse.glsl:303` 的 `opaqueFirst`，以及 `program/lit.fsh:176` 的 `astra_surface_shadow_set_plane`）。Astra **没有**「按天光切换成块中心吸附」这条硬切换。

**判断（可考虑，但倾向不做）**：Bliss 的 `if (SkyLightmap < 0.1) Bias = zoomShadow;` 是非常便宜的洞内防漏光手段（零采样，只是把参考点吸附到块中心）。但它是**硬切换**，而 Astra 现有做法是连续混合，后者不会在阈值处跳变。**Astra 现有做法更好，不建议换成硬切换。**

---

## 10. CR：叶片阴影的「逐采样深度偏移」——直接针对树叶闪烁

**技术目标**：树叶是薄片、又在风里动。用同一个深度参考做多次平面偏移采样，会让叶片的「洞」以采样顺序为序在深度上一致，边缘变成二值跳变。

**实现位置** `cr/shaders/lib/lighting/shadowSampling.glsl:44-66`

```glsl
    vec3 SampleTAAFilteredShadow(vec3 shadowPos, float offset, int shadowSamples, bool leaves, float colorMult, float colorPow) {
        vec3 shadow = vec3(0.0);
        float gradientNoise = InterleavedGradientNoiseForShadows();

        #if !defined GBUFFERS_ENTITIES && !defined GBUFFERS_HAND && !defined GBUFFERS_TEXTURED
            offset *= 1.3875;
        #else
            shadowSamples *= 2;
            offset *= 0.69375;
        #endif

        float shadowPosZM = shadowPos.z;
        for (int i = 0; i < shadowSamples; i++) {
            vec2 offset2 = offsetDist(gradientNoise + i, shadowSamples) * offset;
            if (leaves) shadowPosZM = shadowPos.z - 0.12 * offset * (gradientNoise + i) / shadowSamples;
            shadow += SampleShadow(vec3(shadowPos.st + offset2, shadowPosZM), colorMult, colorPow);
            shadow += SampleShadow(vec3(shadowPos.st - offset2, shadowPosZM), colorMult, colorPow);
        }

        shadow /= shadowSamples * 2.0;

        return shadow;
    }
```

叶片标记来源 `cr/shaders/lib/lighting/mainLighting.glsl:250-254`

```glsl
                                } else if (subsurfaceMode == 2) {
                                    leaves = true;
                                    offset = 0.0005235 * lightmapYM + 0.0009765;
                                    shadowPos.z -= 0.000175 * lightmapYM;
                                    subsurfaceHighlight = lightFactor * 0.6;
```

**算法机制**

普通 PCF 是「同一个深度参考、不同的 xy 偏移」。CR 对叶片**额外给每个采样一个不同的深度**：`shadowPosZM = shadowPos.z - 0.12*offset*(noise+i)/samples`。`offset` 是核半径，所以越靠外的采样，参考深度越往光源方向推，相当于沿光方向把采样点排成一条斜线。效果是叶片的「厚度」在采样核里被抹开，边缘的可见度变成渐变而不是阶跃。

同时 `leaves` 只在 `subsurfaceMode == 2`（树叶材质）时置真（`mainLighting.glsl:251`），普通方块、地面草、实体都不走这条。

**开销与代价**

零额外采样，每个采样只多一次乘加。

**失效边界**

只对 `GBUFFERS_TERRAIN` 且材质被 `leaves.glsl` 标成 `subsurfaceMode == 2` 的像素生效，其余材质没有这条。**这是读了源码的结论。**

**与 Astra 的关系**

Astra 处理叶片闪烁走的是完全不同的机制——在阴影 pass 里用解析平面重建深度，避免裁剪贴图的洞在畸变三角形上滑动。`Astra/shaders/program/shadow.fsh:88-100`：

```glsl
    bool analyticPlane = abs(shadowCasterPlaneNormal.z)>1e-6;
    if (waterCasterKind==0 && (analyticPlane || abs(shadowDet)>1e-20)) {
        vec2 plane=analyticPlane ? -shadowCasterPlaneNormal.xy/shadowCasterPlaneNormal.z
            : vec2(shadowDy.y*shadowDx.z-shadowDx.y*shadowDy.z,
                   shadowDx.x*shadowDy.z-shadowDy.x*shadowDx.z)/shadowDet;
        float planeDepth=(shadowUndistortedPosition.z
            +dot(ray-shadowUndistortedPosition.xy,plane))*0.25+0.5;
        // Receiver and caster must describe the same inverse-warped plane.
        // Clamping this to raster depth preserves the triangle's diagonal error
        // on one side, including static trunks. Correction can go either way;
        // declaring depth_greater would therefore be invalid for solid casters.
        gl_FragDepth=planeDepth;
    }
```

以及裁剪贴图的逆畸变修正 `program/shadow.fsh:62-85`（`shadowTexcoord` 沿光线重新插值，并在本 quad 的 atlas 矩形内裁剪）。

**判断（可考虑，但要小心）**：Astra 已经解决了「洞滑动」这一层（写端），但**接收端的采样策略仍然只有一个参考深度**。CR 的逐采样深度偏移是接收端的补充手段：即使写端完美，薄片边缘在移动时仍会因采样顺序产生二值感。这条成本极低（零额外采样），可以作为「树叶阴影闪烁」的下一根杠杆。

**风险**：Astra 的 `surface_shadow_light` 是多叶瓣 × 四角点的结构（`diffuse.glsl:341-354`），逐采样深度意味着四角点的 references 不再是同一个值，会与 `shadow_surface_reference_depths` 的「每角点独立参考」优化交互。硬件 gather 分支（`shadowmap.glsl:228-253`）已经支持四个不同参考（看 `shadowmap.glsl:241-246` 的循环），但**这是推断，需要实测**。

---

## 11. CR：把采样预算按距离分档（以及 Astra 为什么已经否决了它）

**实现位置** `cr/shaders/lib/lighting/mainLighting.glsl:264-277`

```glsl
                        int shadowSampleBooster = int(subsurfaceMode > 0 && lViewPos < 10.0);
                        #if SHADOW_QUALITY == 2 // Medium
                            int shadowSamples = 2 + 2 * shadowSampleBooster;
                        #elif SHADOW_QUALITY == 3 // High
                            int shadowSamples = 4 + 4 * shadowSampleBooster;
                        #elif SHADOW_QUALITY == 4 // Very High
                            int shadowSamples = 8 + 8 * shadowSampleBooster;
                        #elif SHADOW_QUALITY == 5 // Ultra
                            int shadowSamples = 16 + 16 * shadowSampleBooster;
                        #else
                            int shadowSamples = 0;
                        #endif

                        shadowMult *= GetShadow(shadowPos, lightmap.y, offset, shadowSamples, leaves, playerPos);
```

**算法机制**

采样数按 `SHADOW_QUALITY` 分档（中=2、高=4、极高=8、Ultra=16），并且**靠近相机（<10 块）的次表面材质采样数翻倍**（`shadowSampleBooster`）。这是「把采样预算花在看得清的地方」的显式写法。

**与 Astra 的关系**

Astra 的采样数只按 `SHADOW_FILTER_QUALITY` 分档（四角点 × 1/2/4 叶瓣），**不看距离**；只有 `ASTRA_OVERWORLD_OPTIMIZED` 预算分支按 24~32 块把两叶瓣降到一叶瓣（`diffuse.glsl:355-372`）。而 `diffuse.glsl:305-307` 的注释明确说这轮把「距离折叠」改成了「每距离保持稳定足迹」。

**判断**：CR 的「近处加倍」与 Astra 刚撤销的「远处减半」是同一枚硬币的两面；Astra 撤销的理由（远处轮廓丢边）是实测反馈，所以**不建议回头加距离分档**。


---

## 12. Solas：极简阴影 + 帧号递进抖动 + 常量深度偏移

**实现位置**

坐标 `solas/shaders/lib/util/ToShadow.glsl:1-13`

```glsl
vec3 ToShadow(vec3 worldPos) {
    vec3 shadowPos = mat3(shadowModelView) * worldPos + shadowModelView[3].xyz;
		 shadowPos = projMAD(shadowProjection, shadowPos);
    float distb = sqrt(shadowPos.x * shadowPos.x + shadowPos.y * shadowPos.y);
    float distortFactor = distb * shadowMapBias + (1.0 - shadowMapBias);

    shadowPos.xy /= distortFactor;
    shadowPos.z *= 0.2;
    shadowPos = shadowPos * 0.5 + 0.5;
    shadowPos.z += 0.0512 / shadowMapResolution;
    
    return shadowPos;
}
```

采样 `solas/shaders/lib/lighting/shadows.glsl:41-60`

```glsl
void computeShadow(inout vec3 shadow, vec3 shadowPos, float offset, float subsurface, float skyLightMap) {
    float shadow0 = 0.0;
    vec3 shadowColor = vec3(0.0);    

    float blueNoiseDither = texture2D(noisetex, gl_FragCoord.xy / 512.0).b;
    #ifdef TAA
         blueNoiseDither = fract(blueNoiseDither + 1.61803398875 * mod(float(frameCounter), 3600.0));
    #endif

    int shadowSamples = 2;

    for (int i = 0; i < shadowSamples; i++) {
        vec2 shadowOffset = offsetDist(blueNoiseDither + i, shadowSamples) * offset;
        shadow += SampleShadow(vec3(shadowPos.st + shadowOffset, shadowPos.z));
        shadow += SampleShadow(vec3(shadowPos.st - shadowOffset, shadowPos.z));
    }

    shadow /= shadowSamples * 2.0;

}
```

写端 `solas/shaders/programs/shadow.glsl:148-155`

```glsl
	gl_Position = shadowProjection * shadowModelView * position;

	float dist = sqrt(gl_Position.x * gl_Position.x + gl_Position.y * gl_Position.y);
	float distortFactor = dist * shadowMapBias + (1.0 - shadowMapBias);
	
	gl_Position.xy *= 1.0 / distortFactor;
	gl_Position.z = gl_Position.z * 0.2;
}
```

**算法机制**

畸变是经典 OptiFine 式 `distb * shadowMapBias + (1-shadowMapBias)`，其中 `solas/shaders/lib/common.glsl:7` 是 `const float shadowMapBias = 1.0 - 25.6 / shadowDistance;`。

深度用**常量偏移**：`shadowPos.z += 0.0512 / shadowMapResolution`（`ToShadow.glsl:10`）——偏移量以「纹元」为单位，与距离无关。这与 Astra 的 `1.5*length(raw.xy)`（随半径增长）形成鲜明对比。

采样只有 **2 个**（`shadows.glsl:50`），对称 ±，方向由 `offsetDist(蓝噪声 + 黄金比例×帧号)` 给出（`shadows.glsl:47,53`），形状是 `vec2(cos,sin)*1.4*x/s`。

深度比较用 `clamp((depth - ref)*65536, 0, 1)` 把 16 位深度差变成软边（`shadows.glsl:12`）——这是个便宜的「软比较」，等于给深度一个极小的过滤带。

**开销与代价**

**每像素 2 次采样**，是这批仓库里最省的。代价是柔度很有限：核半径靠 `offset = 0.001`（`gbuffersLighting.glsl:154`）一个常量加上距离变量。

**与 Astra 的关系**

Astra 用硬件比较采样（`SHADOW_FILTER_MODE`），比 Solas 的「读原始深度再 clamp」更准——Astra 的软件分支是 `step(references, textureGather(depths, uv, 0).wzxy)`（`Astra/shaders/global/lighting/shadowmap.glsl:186-189`）。

**判断**：Solas 的**常量深度偏移**是反面教材——Astra 的注释明确解释了为什么要随半径增长（`shadowmap.glsl:404-409`：畸变后外圈纹元更大）。**不移植。** 值得记的只有「2 采样 + 蓝噪声旋转」这个极低配档位，要做最低画质档可以参考。

---

## 13. Photon：统一视觉体系的代码证据——太阳色 = 大气透过率

**技术目标**：让「太阳照到地面的颜色」和「天空看起来的样子」由**同一个物理量**驱动，而不是两套独立的调色。

**实现位置** `photon/shaders/include/lighting/colors/light_color.glsl:62-77`

```glsl
vec3 get_light_color() {
    vec3 light_color
        = sunlight_color * atmosphere_transmittance(light_dir.y, planet_radius);
    light_color = atmosphere_post_processing(light_color);
    light_color *= mix(
        get_sun_exposure() * get_sun_tint(),
        get_moon_exposure() * get_moon_tint(),
        step(0.5, sunAngle)
    );
    light_color *= clamp01(
        rcp(0.02) * light_dir.y
    ); // fade away during day/night transition
    light_color *= 1.0 - 0.25 * pulse(abs(light_dir.y), 0.15, 0.11);

    return light_color;
}
```

太阳常数来源 `photon/shaders/include/sky/atmosphere.glsl:14-20`

```glsl
const vec3 sunlight_color = vec3(
    1.051,
    0.985,
    0.940
); // Color of sunlight in space, obtained from AM0 solar irradiance spectrum
   // from https://www.nrel.gov/grid/solar-resource/spectra-astm-e490.html using
   // the CIE (2006) 2-deg LMS cone fundamentals
```

**算法机制**

`light_color = 太空太阳色 × 大气透过率(太阳仰角) × 大气后处理 × 曝光 × 色调`。关键在于 `atmosphere_transmittance(mu, r)`——这是**和天空渲染、云、雾、曙暮光共用的同一个函数**。

同一函数在四处被调用（逐个核对过）：

- 天空自身 `photon/shaders/include/sky/sky.glsl:188`
- 卷云 `photon/shaders/include/sky/clouds/cirrus.glsl:293`
- 曙暮光 `photon/shaders/include/sky/crepuscular_rays.glsl:119`
- 方块云 `photon/shaders/include/sky/blocky_clouds.glsl:246`

并且每一个后面都紧跟同一句后处理：

`photon/shaders/include/sky/clouds/cirrus.glsl:294`
```glsl
        = sunlight_color * atmosphere_transmittance(sphere_pos, light_dir);
    light_color = atmosphere_post_processing(light_color);
```

`photon/shaders/include/sky/crepuscular_rays.glsl:119-120`
```glsl
    vec3 light_color
        = sunlight_color * atmosphere_transmittance(light_dir.y, planet_radius);
    light_color = atmosphere_post_processing(light_color);
```

**这就是「统一视觉体系」的代码级证据**：不是靠文档约定，而是靠「所有人都调同一个函数、且都跟同一句后处理」。饱和度提升/雨天去饱和（`atmosphere_post_processing`）因此对天空、云、光束、地面直射光**同时**生效，不会出现「天变暖了但地面没变」。

两条实现路线并存：LUT（`atmosphere.glsl:527-535`）与 Chapman 函数解析近似（`atmosphere.glsl:536-568`）。LUT 尺寸 `transmittance_res = ivec2(256, 64)`（`atmosphere.glsl:25`）。但这套代码里**只定义了 LUT 分支，没有任何程序把 `ATMOSPHERE_TRANSMITTANCE_LUT` 定义出来**（grep 全仓，只有 `atmosphere.glsl` 内部三处命中），所以默认走 Chapman 解析式。**这是读了源码加 grep 的结论。**

散射 LUT 倒是真的预烘焙成文件，`photon/shaders/shaders.properties:407-408`

```
# atmospheric scattering LUT
texture.deferred.depthtex0 = image/atmosphere/scattering.dat TEXTURE_3D RGB16F 32 64 32 RGB HALF_FLOAT
```

即 `32×64×32 RGB16F` 的 3D 纹理。但仓库里**没有生成脚本**——`scripts/` 下只有 find_replace、gen_include_guard、gen_slider_values、rename_include 四个 Python 脚本（我列过目录）。

**与 Astra 的关系**

Astra **已有同构的体系，而且更彻底**。`Astra/shaders/global/dimension/overworld.glsl:13-23`：

```glsl
vec3 astra_sky_radiance(vec3 worldDir) {
#if SKY_MODE == SKY_GRADIENT
	vec3 sky = astra_gradient_sky(worldDir);
#else
	vec3 sky = astra_minishita_sky(worldDir);
#endif
    vec3 direction=normalize(worldDir);
    sky=astra_twilight_atmosphere(sky,direction);
    sky *= astra_sky_color_gain(direction.y, skyVisibilityDay, astraTwilightFactor, astraDawnBlend);
	sky = astra_twilight_highlights(sky);
#ifdef LIGHTNING_FLASH
```

`astra_sky_radiance` 被五处消费：`program/sky_irradiance.fsh:29`、`program/deferred.fsh:430`、`program/scene.glsl:199`、`program/sky_reflection_cache.fsh:20`、`global/dimension/overworld.glsl:60`。

日/月光色由 Iris 表达式统一给出（`Astra/shaders/shaders.properties:856,860-864`），曙暮光包络也是统一的（`shaders.properties:699-700`）：

```
variable.float.astraTwilightEnvelope=astraTwilightRiseEase * (1.0 - astraTwilightFadeEase)
uniform.float.astraTwilightFactor=astraTwilightEnvelope * (1.0 - 0.7 * rainStrength)
```

**判断**：Astra 的「统一体系」是**表达式层 + 函数层双统一**（Photon 只有函数层）。**这条 Astra 已经做到了，不需要移植。** Photon 唯一多出的一点是 `atmosphere_post_processing` 的饱和度提升同时作用于直射光和天空，形成整体饱和度一致；Astra 的对应物分散在 `lib/color_controls.glsl:85-95`（只给空气光柱）和 `shaders.properties:853`（环境光去雨）。

---

## 14. Photon：把光照颜色塞进天空图的额外一列（零成本跨 pass 传递）

**实现位置** `photon/shaders/program/d0_sky_map.fsh:136-148`

```glsl
    ivec2 texel = ivec2(gl_FragCoord.xy);

    if (texel.x == sky_map_res.x) { // Store lighting colors
        sky_map = vec3(0.0);
        switch (texel.y) {
            case 0:
                sky_map = light_color;
                break;

            case 1:
                sky_map = ambient_color;
                break;
        }
```

**算法机制**

天空图尺寸是 `sky_map_res = ivec2(191,108)`（`photon/shaders/include/sky/projection.glsl:8`），但实际绘制只用 `texel.x < 189`（`sky.glsl:229` 有 `% (sky_map_res.x - 4)`）。第 `x == 191` 列被拿去存两个标量颜色：第 0 行存 `light_color`、第 1 行存 `ambient_color`。这样后续 pass 只要 `texelFetch` 这一列就能拿到本帧的日/月光色和环境色，**不需要额外的 1×2 纹理，也不需要重复计算**（那些计算里有 `atmosphere_transmittance` 和多次 pow）。

**开销与代价**

贴图多 2 个纹元。零额外采样。

**与 Astra 的关系**

Astra 的同类数据走 **Iris 表达式 uniform**（`shaders.properties` 里的 `uniform.vec3.astraSunPalette` 等），由 CPU 侧按帧算好注入。这比 Photon 的「渲进纹理再读回」更干净，而且不占附件。

**判断**：**Astra 的方式更好**（Photon 这么做是因为它要在 GPU 上算 `atmosphere_transmittance`，而 Astra 把颜色曲线搬到了 CPU）。**不移植。**

---

## 15. Photon：从天光图投影出 SH9（每帧一次 compute）

**实现位置** `photon/shaders/program/d4a_generate_sky_sh.csh:78-95`

```glsl
void main() {
#ifndef SH_SKYLIGHT
    return;
#endif

    const uint sample_count = 256;
    uint i = uint(gl_LocalInvocationID.x);

    // Calculate SH coefficients for each sample

    float skylight_boost = get_skylight_boost();

    vec3 direction = uniform_hemisphere_sample(vec3(0.0, 1.0, 0.0), r2(int(i)));
    vec3 radiance
        = texture(colortex4, project_sky(direction)).rgb * skylight_boost;

    mat3 coeff = sh_coeff_order_2(direction);

```

**算法机制**

256 个线程，每个线程取一个半球均匀方向，采样**已经渲染好的天空图**（`colortex4`）得到辐射度，乘 9 个 SH 基函数，用 subgroup 归约求和，最后 9 个 vec3 写进 `colorimg4`。因为采样的是渲染结果，太阳盘、米氏散射、云、极光**全部自动进入 SH**，不需要在 SH 生成器里重算一遍大气。

消费端 `photon/shaders/include/lighting/diffuse_lighting.glsl:169-177`

```glsl
#if defined WORLD_OVERWORLD && defined PROGRAM_DEFERRED4 && defined SH_SKYLIGHT
    sh3 sky_sh_compat = sh3(sky_sh_0, sky_sh_1, sky_sh_2);

    vec3 skylight = sh_evaluate_irradiance(sky_sh_compat, bent_normal, ao);
    skylight = mix(skylight_up, skylight, sqr(light_levels.y));
#else
    vec3 skylight = ambient_color * ao;
    vec3 skylight_up = skylight;
#endif
```

注意 `mix(skylight_up, skylight, sqr(light_levels.y))`：天光 SH 的贡献按天光的平方加权。洞里（天光低）时退化成「顶上来的均匀光」，露天时才是完整的定向 SH。

**开销与代价**

每帧 1 个 workgroup（256 线程）、256 次天空图采样、9 次归约。**每帧一次，不是每像素。** 需要 `MC_GL_KHR_shader_subgroup_arithmetic`，没有时退化成 shared memory 的 8 级手写归约（`csh:127-169`，注释说明 Intel 不喜欢循环里的 barrier）。

**与 Astra 的关系**

Astra 有同构但更贵的东西：`Astra/shaders/program/sky_irradiance.fsh:13-36` 用 9 个片元各做 64 次 `astra_sky_radiance` 查询：

```glsl
    bool oddY = coefficient == 1 || coefficient == 4 || coefficient == 5;
    float hemisphereWeight = oddY ? 0.92 : 1.08;
    for (int row = 0; row < 4; ++row) for (int column = 0; column < 16; ++column) {
        float y = (float(row) + 0.5) * 0.25;
        float angle = (float(column) + 0.5) * (2.0 * ASTRA_SH9_PI / 16.0);
        float r = sqrt(max(1.0-y*y, 0.0));
        vec3 direction = vec3(r*cos(angle), y, r*sin(angle));
        #if CLOUD_MODE == CLOUD_PLANAR
        vec3 radiance = astra_cached_reflection_sky(direction);
        #else
        vec3 radiance = astra_sky_radiance(direction);
        #endif
        float basis[9];
        astra_sh9_basis(direction, basis);
        sum += max(radiance, vec3(0.0)) * basis[coefficient]
             * (hemisphereWeight * 4.0*ASTRA_SH9_PI/128.0);
    }
```

区别在于：Photon 采样的是**已经渲染好的天空图**（1 次纹理读），Astra 采样的是**天空函数本身**（每次要跑 `astra_minishita_sky` 或 `astra_gradient_sky`）。Astra 少一次天空渲染，但 SH 生成阶段更贵；而且 Astra 的 64 次里把 128 个立体角贡献压缩成 64 次查询（`sky_irradiance.fsh:16-20` 的注释解释了配对）。

消费端 `Astra/shaders/lib/sky_directional.glsl:12-26`

```glsl
vec3 astra_directional_sky_coeffs(vec3 coefficients[9], vec3 normal, vec3 palette) {
    vec3 mean = coefficients[0] * ASTRA_SH9_K0;
    // Zero order near zero: fall back to the old facing rule. Bounded output
    // (0.34..1.0 * palette), so a bent-vs-geometric difference stays bounded too.
    if (max(mean.r, max(mean.g, mean.b)) < 0.00001) return palette * (0.67 + normal.y * 0.33);
    vec3 diffuse = max(astra_sh9_diffuse_radiance(coefficients, normal), vec3(0.0));
    // 0.67 is the average of the old directional multiplier over the sphere.
    return palette * 0.67 * clamp(diffuse / max(mean, vec3(0.00001)), 0.0, 2.0);
}

vec3 astra_directional_sky(vec3 normal, vec3 palette) {
    vec3 coefficients[9];
    for (int i = 0; i < 9; ++i) coefficients[i] = texelFetch(colortex18, ivec2(i,0), 0).rgb;
    return astra_directional_sky_coeffs(coefficients, normal, palette);
}
```

**判断**：两边都做了，**Astra 的「SH 归一化后再乘 palette」这一层比 Photon 直接用的多**（`clamp(diffuse/mean, 0, 2)` 加 0.67 平均系数加零阶退化），鲁棒性更好。**不移植。**


---

## 16. Photon：曝光→线性调色→tonemap→感知调色的完整顺序与职责

**实现位置** `photon/shaders/program/c19_color_grading.fsh:147-190`

```glsl
    scene_color = texelFetch(colortex5, texel, 0).rgb;

    float exposure = texelFetch(colortex5, ivec2(0), 0).a;

#ifdef BLOOM
    vec3 bloom = get_bloom();
    float bloom_intensity = 0.12 * BLOOM_INTENSITY;

    scene_color = mix(scene_color, bloom, bloom_intensity);

#ifdef BLOOMY_FOG
    float fog_transmittance = texture(colortex3, uv * taau_render_scale).x;
    scene_color = mix(
        bloom,
        scene_color,
        pow(fog_transmittance, BLOOMY_FOG_INTENSITY)
    );
#endif
#endif

    scene_color *= exposure;

#ifdef VIGNETTE
    scene_color *= vignette(uv);
#endif

    scene_color = grade_input(scene_color);

#ifdef TONEMAP_COMPARISON
    scene_color
        = uv.x < 0.5 ? tonemap_left(scene_color) : tonemap_right(scene_color);
#else
    scene_color = tonemap(scene_color);
#endif

    scene_color = clamp01(scene_color * working_to_display_color);
    scene_color = grade_output(scene_color);
```

**算法机制与职责划分**

| 阶段 | 所在颜色域 | 做什么 |
|---|---|---|
| bloom 混合 | ACEScg 线性 HDR | `mix(scene, bloom, 0.12*intensity)` |
| 曝光 | 线性 HDR | 从 `colortex5` 的 alpha（第 0 纹元）读全局曝光，整帧乘 |
| `grade_input` | ACEScg 线性 | 亮度、**log2 域对比度**（围绕 `log2(0.18)`）、饱和度、白平衡矩阵 |
| `tonemap` | → 显示线性 | 单一算子 |
| 换色域 | 显示线性 | 乘 `working_to_display_color`（ACEScg→Rec.709） |
| `grade_output` | 近似感知（sqrt） | HSL 分色相饱和度（橙 30°、青 210°、绿 90°）、gain、sqr 还原 |

三处值得记的设计：

1. **对比度在 log2 域做**（`c19:74-77`），中点是 0.18（18% 灰）。这是「按感知亮度压对比」而不是按线性值，改对比度不会把高光提前压死。
2. **HSL 分色相调色**（`c19:101-127`），注释注明灵感来自 Lux Shaders 的 Tech（`c19:101`）。这是「橙色暖、青色冷」那类影视调色最常见的实现方式。
3. **调色分两段**：`grade_input` 在 tonemap **之前**（管动态范围与白平衡），`grade_output` 在 tonemap **之后**（管色相与感知饱和度）。两者的定义域在注释里写死（`c19:63-64` 与 `c19:95-96`）。

**曝光本身**

`photon/shaders/program/c4_taa_exposure.fsh` 里，曝光是在 TAA 同 pass 里测的，存在 `result.a`（`c4:383-386`）。同一个 pass 还做 YCoCg 方差裁剪：

`photon/shaders/program/c4_taa_exposure.fsh:195`
```glsl
    a = rgb_to_ycocg(reinhard(a));
```

`photon/shaders/program/c4_taa_exposure.fsh:225-233`
```glsl
    // Strictness parameter, higher gamma => more temporally stable but more
    // ghosting
    float gamma = mix(0.75, 1.25, linear_step(0.25, 1.0, distance_factor));

    vec3 mu = moments[0];
    vec3 sigma = sqrt(moments[1] - moments[0] * moments[0]);

    min_color = max(min_color, mu - gamma * sigma);
    max_color = min(max_color, mu + gamma * sigma);
```

注意 `reinhard(a)` 先做——**HDR 值先被压到 [0,1) 再做 YCoCg AABB**，否则 AABB 在 HDR 上毫无意义。`gamma` 随 `distance_factor`（运动量）从 0.75 到 1.25：运动大时更宽松（更稳但更易拖影），静止时更紧（更锐）。

**与 Astra 的关系**

Astra 的顺序是 `auto_exposure → apply_exposure → apply_scene_grading → tonemap → srgb_encode → apply_grading → vignette → dither`，见 `Astra/shaders/program/display.fsh:272-303`：

```glsl
    vec3 displayHDR = ordinaryWater ? hdr*1.6 : display_air_hdr(hdr);
    vec3 displayLinear = apply_tonemap(apply_scene_grading(apply_exposure(displayHDR)));
    #else
    #ifdef DIMENSION_END
    vec3 exposed=apply_exposure(hdr);
```

```glsl
    vec3 displayColor = srgb_encode(displayLinear);
    displayColor = apply_grading(displayColor);
    displayColor = apply_vignette(displayColor, texcoord);
    #ifdef ASTRA_DISPLAY_PREPARE
    displayColor = clamp(displayColor, 0.0, 1.0);
    ASTRA_DISPLAY_OUT = vec4(displayColor, dot(displayColor,vec3(0.299,0.587,0.114)));
    #else
    displayColor = apply_output_dither(gl_FragCoord.xy, displayColor);
    ASTRA_DISPLAY_OUT = vec4(clamp(displayColor, 0.0, 1.0), 1.0);
```

两家的分层**几乎一一对应**：Astra 的 `apply_scene_grading` 对应 Photon 的 `grade_input`，`apply_grading` 对应 `grade_output`，Astra 多一个显式的 `srgb_encode` 步骤（Photon 用矩阵换色域）。Astra 的曝光是 8×8 = 64 tap 的画面测量加 1 texel 历史（`Astra/shaders/global/post/exposure.glsl:36-70`），比 Photon 的「同 pass 顺带测」更明确，但两者都是每帧一个全局标量。

**判断**：**职责划分上 Astra 已经不缺。** 唯一可借的是 Photon 的「运动量驱动方差裁剪严格度」（`c4:227`）。Astra 现在固定是 `1.25*sigma`（`Astra/shaders/program/taa_resolve.fsh:162-164`）：

```glsl
                mean /= 9.0;
                vec3 sigma = sqrt(max(second/9.0-mean*mean,vec3(0.0)));
                lo = max(lo,mean-1.25*sigma);
                hi = min(hi,mean+1.25*sigma);
                vec3 bounded = clamp(historyColor, lo, hi);
```

Astra 另外用 `motion` 只调**混合权重**（`taa_resolve.fsh:166,172`：`mix(0.92,0.70,motion)`），没有调裁剪框宽度。**这是可选的微调，不是缺陷。**

---

## 17. Photon：方块光经验衰减曲线（含白天抑制与近光源高光）

**实现位置** `photon/shaders/include/lighting/diffuse_lighting.glsl:40-66`

```glsl
float get_blocklight_falloff(float blocklight, float skylight, float ao) {
    float falloff = pow8(blocklight) + 0.18 * sqr(blocklight)
        + 0.16 * dampen(blocklight); // Base falloff
    falloff *= mix(
        cube(ao),
        1.0,
        clamp01(falloff)
    ); // Stronger AO further from the light source
    falloff *= mix(
        1.0,
        ao * dampen(abs(cos(2.0 * frameTimeCounter))) * 0.67 + 0.2,
        darknessFactor
    ); // Pulsing blocklight with darkness effect
    falloff *= 1.0 - 0.2 * time_noon * skylight
        - 0.2 * skylight; // Reduce blocklight intensity in daylight
    falloff += min(
        2.7 * pow12(blocklight),
        0.9
    ); // Strong highlight around the light source, visible even in the daylight
    falloff *= smoothstep(
        0.0,
        0.125,
        blocklight
    ); // Ease transition at edge of lightmap

    return falloff;
}
```

**算法机制**

`pow8(blocklight)` 主导主衰减（几乎是指数），`0.18*sqr` 补中段，`0.16*dampen` 补底段。然后三项修饰：AO 在远处更强（`mix(cube(ao), 1, clamp01(falloff))`）、白天压制（`-0.2*time_noon*skyLight - 0.2*skyLight`）、光源附近加一个 `min(2.7*pow12, 0.9)` 的高光（注释说「白天也看得见」）。最后 `smoothstep(0, 0.125, blocklight)` 把光图边缘抹平。

**与 Astra 的关系**

Astra 是 `pow4(blockLight)` 加 `1 - sqrt(skyLight)*suppression`，`Astra/shaders/global/lighting/blocklight.glsl:106,116`：

```glsl
	float blockLightIntensity = pow4(blockLight) * (BLOCKLIGHT_STRENGTH * 0.01);
    // The caller supplies final held intensity; legacy amplitude callers raise
    // it exactly once in block_lighting or their dimension-specific composer.

    // With no block or held source, daylight suppression has nothing to dim.
    // Keep the same exact zero without evaluating either square-root response.
    if (blockLightIntensity == 0.0 && heldLightIntensity == 0.0) return vec2(0.0);

	#ifdef BLOCKLIGHT_SUPPRESSION
        if (blockLightIntensity != 0.0)
		    blockLightIntensity *= 1.0 - sqrt(skyLight) * blocklightSuppression;

        if (heldLightIntensity != 0.0) {
		    float heldLightSkyLight = sqrt(max(skyLight, heldLightSuppression));
		    heldLightIntensity *= 1.0 - heldLightSkyLight * blocklightSuppression;
        }
```

**判断**：Photon 的 `pow8` 比 Astra 的 `pow4` 衰减快得多，而且多了「光源附近高光」这一项（Astra 没有）。**「光源附近高光」是唯一值得考虑的点**——它让火把贴着墙面时不至于整片均匀发亮，而是有个亮核。但这是**观感选择，不是缺陷修复**，优先级低。

---

## 18. Solas：把昼夜光色写成关键帧再插值

**实现位置** `solas/shaders/lib/color/lightColor.glsl:1-16`

```glsl
#if defined OVERWORLD
float timeBrightnessSqrt = sqrt(timeBrightness);
float mefade = 1.0 - clamp(abs(timeAngle - 0.5) * 8.0 - 1.5, 0.0, 1.0);
float dfade = 1.0 - pow(1.0 - timeBrightness, 1.5);

vec3 lightSun = fmix(fmix(fmix(lightSunrise, lightMorning, timeBrightnessSqrt), fmix(lightEvening, lightSunset, 1.0 - timeBrightnessSqrt), mefade), lightDay, dfade);
vec3 ambientSun = fmix(fmix(fmix(ambientSunrise, ambientMorning, timeBrightnessSqrt), fmix(ambientEvening, ambientSunset, 1.0 - timeBrightnessSqrt), mefade), ambientDay, dfade);

vec3 lightColRaw = fmix(lightNight, lightSun, sunVisibility);
vec3 lightColSqrt = fmix(lightColRaw, lightColRaw * weatherCol, wetness * 0.75);
vec3 lightCol = pow(lightColSqrt * (1.0 - wetness * 0.5), vec3(2.0 - wetness));

vec3 ambientColRaw = fmix(ambientNight, ambientSun, sunVisibility);
vec3 ambientColSqrt = fmix(ambientColRaw, ambientColRaw * weatherCol, wetness * 0.75);
vec3 ambientCol = ambientColSqrt * ambientColSqrt;

```

**算法机制**

五组关键帧（sunrise/morning/day/evening/sunset，加 night），用两个时间权重 `timeBrightnessSqrt` 与 `mefade` 做**双层 mix**：先在内层按 `timeBrightnessSqrt` 在「晨→昼」和「昏→昼」之间插，再用 `mefade`（只在日出/日落附近非零）在两者之间插；最后按 `sunVisibility` 与夜色混合。

关键帧常量在 `solas/shaders/lib/common.glsl:707-716`，形如 `normalize(vec3(LIGHT_DR,LIGHT_DG,LIGHT_DB)/255.0) * LIGHT_DI`——**先归一化色相再乘强度**，这是保证「改强度不改色相」的常见写法。

**与 Astra 的关系**

Astra 把同一件事搬到了 CPU 侧（Iris 表达式），`Astra/shaders/shaders.properties:846-864`，用 `astraAmbientDay`/`astraAmbientNight`/`astraTwilightFactor` 三个权重插值，而且额外做了雨天去饱和（`shaders.properties:852-853`）。

**判断**：**Astra 的做法更好**（CPU 每帧算一次，对比每像素插值）。**不移植。**

---

## 19. CR：直射色与环境色分开定义、分开插值

**实现位置** `cr/shaders/lib/colors/lightAndAmbientColors.glsl:6-17` 与 `56-60`

```glsl
            vec3 noonClearLightColor = vec3(0.65, 0.55, 0.375) * 2.05; //ground and cloud color
        #else
            vec3 noonClearLightColor = vec3(0.4, 0.75, 1.3); //light shaft color
        #endif
        vec3 noonClearAmbientColor = pow(skyColor, vec3(0.75)) * 0.85;

        #ifndef COMPOSITE1
            vec3 sunsetClearLightColor = pow(vec3(0.64, 0.45, 0.3), vec3(1.5 + invNoonFactor)) * 5.0; //ground and cloud color
        #else
            vec3 sunsetClearLightColor = pow(vec3(0.62, 0.39, 0.24), vec3(1.5 + invNoonFactor)) * 6.8; //light shaft color
        #endif
        vec3 sunsetClearAmbientColor   = noonClearAmbientColor * vec3(1.21, 0.92, 0.76) * 0.95;
```

```glsl
        vec3 dayLightColor   = mix(sunsetClearLightColor, noonClearLightColor, noonFactorDM);
        vec3 dayAmbientColor = mix(sunsetClearAmbientColor, noonClearAmbientColor, noonFactorDM);

        vec3 clearLightColor   = mix(nightClearLightColor, dayLightColor, sunVisibility2);
        vec3 clearAmbientColor = mix(nightClearAmbientColor, dayAmbientColor, sunVisibility2);
```

**算法机制**

直射色（`*LightColor`）和环境色（`*AmbientColor`）**分开定义、分开插值，从不互相推导**。环境色的日光态是 `pow(skyColor, 0.75)*0.85`——**从天色推导**，所以「天变蓝地面也变蓝」；直射色则是硬编码的暖白。黄昏的环境色是「正午环境色 × (1.21, 0.92, 0.76)」——**在正午色上乘一个暖色偏移**，而不是重新定义。

**与 Astra 的关系**

Astra 也是直射/环境分离（`astraSunPalette` 与 `astraAmbientPalette`，`shaders.properties:853,860-863`），而且环境光在黄昏也是「日间色 × 暖偏移」（`shaders.properties:848-851`）。

**判断**：结构一致，**无新信息**。


---

## 20. Astra 侧对照汇总（本节是核对结果，不是外部结论）

| 能力 | Astra 现状 | Astra 证据位置 |
|---|---|---|
| 径向畸变 + 解析逆 | 有（Steadfast 血统，锚在块数） | `lib/distort.glsl:16-47` |
| 畸变写读一致 | 有 | `program/shadow.vsh:242` + `lib/transforms.glsl:124-132` |
| 法线偏移 bias | 有，随贴图半径线性 + 掠射项 | `global/lighting/shadowmap.glsl:403-412` |
| receiver-plane 重建 | **有，比外部更细** | `global/lighting/shadowmap.glsl:148-170, 206-227`；`program/shadow.fsh:88-100` |
| 逐角点深度/染色配对 | **有，比 Photon 更细** | `global/lighting/shadowmap.glsl:254-340` |
| 硬件比较 gather | 有（可切软件） | `global/lighting/shadowmap.glsl:178-204` |
| 阴影距离淡出 | 有（按块数） | `global/lighting/shadowmap.glsl:109-123` |
| 假阴影退路 | 有（天光阈值） | `global/lighting/shadowmap.glsl:417-419` |
| **PCSS / 遮挡体搜索** | **无** | grep `blocker`/`penumbra` 只命中注释 |
| **半影随距离变化** | **无** | `global/lighting/diffuse.glsl:313` 的 spread 是常数上限 |
| **小半影反锐化** | **无** | grep `sharpen`/`linear_step` 在阴影链无命中 |
| **采样旋转/抖动** | **刻意不用** | `global/lighting/diffuse.glsl:373-376` 注释 |
| **薄片逐采样深度偏移** | 无 | `shadow_lobe_light_inside` 只有一个 referenceDepth |
| 彩色阴影 | 有（逐角点） | `global/lighting/shadowmap.glsl:293-340` |
| 水面焦散 focus | 有（A 通道） | `program/shadow.fsh:127-147` |
| 天空 SH | 有（64 查询 × 9 系数） | `program/sky_irradiance.fsh:13-36` |
| 统一大气驱动 | 有（函数层 + 表达式层） | `global/dimension/overworld.glsl:13-23`；`shaders.properties:699-700` |
| 自动曝光 | 有（64 tap + 1 texel 历史） | `global/post/exposure.glsl:36-70` |
| TAA 方差裁剪 | 有（YCoCg + 1.25σ） | `program/taa_resolve.fsh:152-174` |
| 色调映射分层 | 有（与 Photon 同构） | `program/display.fsh:272-303` |
| 叶片透光 | 有（wrap + 视角透射） | `global/lighting/sss.glsl:79-88` |
| **屏幕空间远阴影 SSRT** | 无 | grep `SSRT` 零命中 |
| **彩色光照 LPV** | 无 | Photon 的 `COLORED_LIGHTS` 默认也是关的（`photon/shaders/settings.glsl:57`） |

---

## 建议主代理重点复用的 3~6 条

1. **Photon 的「最小滤核 + 反锐化」组合**（`photon/shaders/include/lighting/shadows/pcss.glsl:101-111` 与 `174-185`）：这是「接触处锐利」和「不闪烁」能同时成立的**结构性理由**——把核下限抬到 2 纹元消除二值跳变，再用随半影自动退化的锐化把接触处的锐度补回来。Astra 现在只有下限（`diffuse.glsl:327` 的 `0.5*spread`），没有补回锐度的那一半，所以阴影整体偏软。

2. **Photon 的 blocker→penumbra 相似三角形链路**（`pcss.glsl:243-252`）：Astra 的 `spread` 上限是常数，远处阴影永远只有 2 纹元的柔度，「树干斜亮带」这类方向性伪影在结构上无法收敛。引入这一条才能让柔度随遮挡距离增长，同时保持近处由第 1 条约束。

3. **CR 的叶片逐采样深度偏移**（`cr/shaders/lib/lighting/shadowSampling.glsl:58`）：零额外采样成本，只多一次乘加。Astra 已经在写端解决了裁剪洞滑动（`program/shadow.fsh:62-100`），但接收端仍然只有一个参考深度；这条正好补另一端，是「树叶阴影闪烁」成本最低的下一根杠杆。落地前需确认 Astra 的硬件 gather 分支能接受四角点不同参考（`shadowmap.glsl:241-246` 已支持循环，但要实测）。

4. **Photon 在贴图边缘裁剪遮挡体搜索采样**（对照 luster 版 `luster/shaders/lib/light/pcss.glsl:66-68`）：Photon 原版在 `pcss.glsl:43-49` 直接 `texelFetch` 未裁剪的 uv，luster 作者补了 `if (clamp01(uv) != uv) continue;`。若引入 PCSS，这一条必须一起带上，否则贴图边缘会读未定义纹元。

5. **Photon 的「运动量驱动方差裁剪严格度」**（`photon/shaders/program/c4_taa_exposure.fsh:227`）：Astra 的裁剪框固定 `1.25σ`，只用运动量调混合权重（`taa_resolve.fsh:162-172`）。把 `gamma` 也做成运动的函数（静止时更紧、运动时更松）是两行改动，可能同时改善静止画面的锐度与运动时的拖影。

6. **明确不要做的事**：不要给 Astra 加采样旋转抖动（会正面命中「树叶阴影闪烁」痛点）；不要引入 SSRT（屏幕外无效，救不了远处树影投地）；不要换成 Bliss 的对数畸变（Astra 的解析纹元宽度更严格，而且不需要随 `shadowDistance` 重调常数）；不要换成 Bliss 的硬切换块中心吸附（Astra 的连续混合不会在阈值跳变）。

---

## 未验证 / 缺口清单

- **所有「开销」都是静态推断**（采样次数、纹理读取次数、pass 数、分辨率），我没有运行任何光影，没有 GPU 计数器。**本笔记不含任何 FPS、毫秒或百分比收益。**
- Photon 的 `ATMOSPHERE_SCATTERING_LUT` 3D 纹理（32×64×32 RGB16F）由外部脚本生成，**仓库内没有生成脚本**，我无法确认其内容与精度。
- Photon 的 `ATMOSPHERE_TRANSMITTANCE_LUT` 分支在本仓库中**没有程序定义该宏**，因此默认走 Chapman 解析式——这是 grep 结论，但我没有检查是否存在构建期注入。
- CR 的 `colortex18` 屏幕空间阴影只在 `VOXY_OPAQUE` 下被消费（`mainLighting.glsl:301`），其生产者未在本仓库找到（`pipelineSettings.glsl:15` 只声明了格式）。**未验证其实际生成逻辑。**
- Bliss 的 `composite.fsh` 里 VPS 第一遍的分辨率我未确认（文件里没有明显的降分辨率声明），因此「两遍 PCSS 的额外开销」只能说「多一个 pass 加一次双边上采样」，不说具体像素数。
- Astra 侧我只读了与阴影/光照/色调相关的文件，**没有通读 `program/` 下全部 60+ 个 program**。因此「某能力不存在」的结论仅限我 grep 过的关键词（`blocker`、`penumbra`、`pcss`、`SSRT`、`sharpen`、`linear_step`）。若需要更强的不存在性证明，需要更系统的符号扫描。
