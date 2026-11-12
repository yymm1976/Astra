# Astra 现状事实索引（b 份）

> 只读研究产出。所有结论均来自 Astra 工作区源码，未读任何外部光影包；不修改任何源码、配置、资源、AGENTS.md、docs 正文，只写本笔记。
> 本文件是**事实索引**：只写"当前到底是什么"，不评价好坏、不提改进建议。
> 阅读范围：`Astra/shaders/` 下全部 pass 入口、被调用的 `global/` 与 `lib/` 模块、`shaders.properties`、`lib/settings.glsl`。
> 证据强度：**[源码]** 直接读到该行原文；**[推断]** 由源码结构推出、未经实机验证；**[未验证]** 需实机才能确认。
> 所有"采样次数 / 分辨率 / 频次"都来自源码常量或 `shaders.properties` 的 size 声明，**不是实测 FPS 或毫秒**。

---

## 0. 一句话总览

gbuffers 多附件写出场景 → deferred 的 4 个槽位按开关依次跑「屏幕云 → SSAO → 体积雾 → 场景合成」→ composite 链做水状态/水下光轴/泛光/自动曝光/TAA → display 做曝光+色调映射+调色 → final 做 FXAA 或 SMAA 再抖动。

---

## 1. pass 顺序：各阶段谁做什么

### 1.1 deferred 是"选择器"，不是固定四段

根目录 `deferred1/2/3.fsh` 只做转发：

`Astra/shaders/deferred1.fsh:2`
```glsl
#include "/program/deferred_slot1.fsh"
```

`Astra/shaders/deferred2.fsh:2`
```glsl
#include "/program/deferred_slot2.fsh"
```

`Astra/shaders/deferred3.fsh:3`
```glsl
#include "/program/deferred.fsh"
```

槽位 0 的选择逻辑（原文四支）：

`Astra/shaders/program/deferred_slot0.fsh:6`
```glsl
#if DEBUG_VERTEX_AO == 1
```

`Astra/shaders/program/deferred_slot0.fsh:8`
```glsl
#elif CLOUD_MODE == CLOUD_PLANAR
```

`Astra/shaders/program/deferred_slot0.fsh:9`
```glsl
#include "/program/cloud_screen.fsh"
```

`Astra/shaders/program/deferred_slot0.fsh:10`
```glsl
#elif defined ASTRA_SSAO
```

槽位 1、2：

`Astra/shaders/program/deferred_slot1.fsh:4`
```glsl
#if CLOUD_MODE == CLOUD_PLANAR
```

`Astra/shaders/program/deferred_slot1.fsh:6`
```glsl
        #include "/program/ssao.fsh"
```

`Astra/shaders/program/deferred_slot1.fsh:13`
```glsl
    #include "/program/volume_slot.fsh"
```

`Astra/shaders/program/deferred_slot2.fsh:2`
```glsl
#if CLOUD_MODE == CLOUD_PLANAR && defined ASTRA_SSAO && defined ASTRA_VOLUME_FOG && VOLUME_FOG_DENSITY > 0
```

`Astra/shaders/program/deferred_slot2.fsh:3`
```glsl
    #include "/program/volume_main.fsh"
```

**[源码]** 实际执行顺序由 `shaders.properties` 的 `program.deferred1/2/3.enabled` 决定（properties 295–325 行分"有平面云/无平面云"两支），不是恒定四段。

deferred 的顶点阶段在平面云模式下换成云屏幕空间顶点着色器：

`Astra/shaders/deferred.vsh:5`
```glsl
#if CLOUD_MODE == CLOUD_PLANAR && DEBUG_VERTEX_AO == 0
```

`Astra/shaders/deferred.vsh:6`
```glsl
#include "/program/cloud_screen.vsh"
```

### 1.2 各 pass 职责速查

| 程序 | include 主体 | 写（RENDERTARGETS） | 读 |
|---|---|---|---|
| prepare | sky_gradient_cache 或 sky_reflection_cache | 12 或 11 | 天空公式 |
| prepare1 | sky_reflection_cache | 11 | 天空公式 |
| prepare2 | prepare_cloud_shadow → cloud_shadow_cache | 14 | 云层密度 |
| prepare3 | sky_irradiance | 18 | 天空（64 方向） |
| prepare4 | **默认关闭** | — | — |
| shadow / shadow_solid | program/shadow.vsh·fsh | shadowtex0/1 + shadowcolor0 | 材质纹理 |
| gbuffers_* | program/lit.fsh 或 sky.fsh | 0,3,5,16,19,20,22,27,28 的组合 | 阴影/天空/水 |
| deferred / 1 / 2 / 3 | 见 1.1 | 0,4,(16) / 21,(26) / 23 | 3、12 或 24、20、23 |
| composite | water_state | 6 | colortex5 |
| composite1 | itt_water_normal_cache | 29 | 水波/光 |
| composite2 | scattering | 1 | 深度/阴影 |
| composite3 | water_composite | 9 | 0、1 |
| composite4 | water_bloom 或 composite1 | 2 | 0 或 9 |
| composite5 | exposure | 10 | 0 或 9 |
| composite6 | taa_resolve | 0,15 | 0、9、16、22 |
| composite7 | taa_state | 17 | — |
| composite8 | display（ASTRA_DISPLAY_PREPARE） | 13 | 0、1、2、9 |
| composite9 | effect_history_state | 30 | — |
| composite10 / 11 | smaa_edge / smaa_weights | 7 | 13 / 7 |
| final | display.fsh，或 FXAA/SMAA 混合 | 后台缓冲 | 13 / 7 |
| 末地 setup / setup1 / setup2 | end_star_rows / end_star_catalogue / 空 dispatch | 31 | — |

关键 RENDERTARGETS 原文：

`Astra/shaders/program/lit.fsh:88`
```glsl
            /* RENDERTARGETS: 0,3,16,22,19,20,27,28 */
```

`Astra/shaders/program/deferred.fsh:35`
```glsl
/* RENDERTARGETS: 0,4,16 */
```

`Astra/shaders/program/deferred.fsh:37`
```glsl
/* RENDERTARGETS: 0,4 */
```

`Astra/shaders/program/water_state.fsh:14`
```glsl
/* RENDERTARGETS: 6 */
```

`Astra/shaders/program/scattering.fsh:103`
```glsl
/* RENDERTARGETS: 1 */
```

`Astra/shaders/program/taa_resolve.fsh:22`
```glsl
/* RENDERTARGETS: 0,15 */
```

`Astra/shaders/program/display.fsh:108`
```glsl
    /* RENDERTARGETS: 13 */
```

`Astra/shaders/program/volume_main.fsh:28`
```glsl
/* RENDERTARGETS: 23 */
```

`Astra/shaders/program/cloud_screen.fsh:27`
```glsl
/* RENDERTARGETS: 24,25 */
```

`Astra/shaders/program/cloud_screen.fsh:31`
```glsl
/* RENDERTARGETS: 12 */
```

### 1.3 final 的两条路（取决于 AA 模式）

`Astra/shaders/program/final.fsh:2`
```glsl
#ifdef ASTRA_SPATIAL_AA
```

`Astra/shaders/program/final.fsh:29`
```glsl
        vec3 color = astra_smaa_blend(colortex13,colortex7,texcoord);
```

`Astra/shaders/program/final.fsh:31`
```glsl
        vec3 color = astra_fxaa(colortex13,texcoord,geometryOnly);
```

`Astra/shaders/program/final.fsh:37`
```glsl
    #include "/program/display.fsh"
```

---

## 2. colortex 编号 → 用途 → 尺寸 → 格式

尺寸取自 `shaders.properties` 的 `size.buffer.*`（未声明 = 原生分辨率）；格式取自各写入 pass 的 `const int colortexNFormat`。

| # | 用途（依据源码注释与消费者） | 尺寸 | 格式 | 写入者 | 读取者 |
|---|---|---|---|---|---|
| 0 | 场景 HDR 颜色 | 原生 | R11F_G11F_B10F | lit / deferred | water, taa_resolve, display, nether_reflection |
| 1 | 空气/水下光轴 | 0.25² / 0.5² / 1²（按开关） | RG16F（空气）或 RGBA16F（水下光轴） | scattering | display、water_composite |
| 2 | Bloom 捕获源 | 0.25²（开 Bloom） | R11F_G11F_B10F | composite1 / water_bloom | display（mip 读） |
| 3 | 材质+光照位标志（R=光照 7bit+手部 bit7，GB=法线，A=水洼/粗糙度） | 原生 | Iris 默认 RGBA8 | lit.fsh | deferred, ssao, volume_main, nether_reflection |
| 4 | 不透明场景副本（折射/SSR 背景） | 原生 | R11F_G11F_B10F | deferred | water.glsl |
| 5 | 水面界面记录 | 原生 | Iris 默认 RGBA8 | lit.fsh 水面分支 | water_state / water_interface_record |
| 6 | 水体体积状态（texel0 状态，texel1/2 元数据） | 3×1 | RGBA32F | composite（water_state） | medium_state 全体 |
| 7 | SMAA 边/权重 | 1² 或原生 | RGBA8 | smaa_edge / smaa_weights | smaa_weights / final |
| 8 | 末地几何/形状缓存（316 槽） | 316×1 | RGBA32F | prepare（end_illumination） | end_system 等 |
| 9 | 末地天空 / 主世界水下 HDR / 下界反射载体 | 原生 | RGBA16F | end_sky_buffer / water_composite / nether_reflection | deferred, display, taa_resolve, exposure |
| 10 | 自动曝光历史（1 texel） | 1×1 | RGBA32F | composite5（exposure） | display.vsh / grading |
| 11 | 天空反射环境 | 128×64 / 130×64 / 256×128 / 258×128 | RGBA16F | prepare / prepare1 | 水面反射、SSR 回退 |
| 12 | 低频天空表 或 原始屏幕云 | 65²/129²/257²（表）；0.25²/0.5²/1²（云） | RGBA16F | sky_gradient_cache 或 cloud_screen | clouds_screen |
| 13 | 显示预处理（AA 输入） | 原生（开 AA） | RGBA16 | composite8（display） | final |
| 14 | 世界空间云影透射 | 128² 或 256² | R16 | prepare2 | cloud_shadow_cache.glsl |
| 15 | TAA 历史（RGB + 深度打包进 A） | 原生（开 TAA） | RGBA16F | composite6 | 下一帧 taa_resolve |
| 16 | 反应性掩码 | 原生（开 TAA） | R8 | lit / deferred | taa_resolve |
| 17 | TAA 帧元数据（4 texel） | 4×1 | RGBA32F | composite7 | taa_resolve（vsh 一次读） |
| 18 | SH9 天空辐照度 | 9×1 | RGBA16F | prepare3 | sky_directional / ao_resolve |
| 19 | 环境光能量（AO 扣除用） | 原生 | R11F_G11F_B10F | lit | ao_resolve |
| 20 | 几何法线 + 顶点 AO 字节 | 原生 | RGBA8 | lit | ssao, ao_resolve |
| 21 | SSAO 可见度 | 0.5²（开 AO） | RGBA16F | deferred2 | ao_resolve |
| 22 | 植被运动矢量 | 原生（开 TAA） | RGBA16F | lit | taa_resolve |
| 23 | 体积雾 S/T | 0.25² 或 0.5²（开体积雾） | RGBA16F | volume_main | deferred |
| 24 | 屏幕云解算/颜色历史 | 0.25²/0.5²/1.0² | RGBA16F | cloud_screen | clouds_screen、deferred |
| 25 | 屏幕云逐 texel 元数据 | 同 24 | RGBA16F | cloud_screen | 下一帧 cloud_temporal |
| 26 | 半分辨率弯曲法线 | 0.5² | RG16F | deferred2（ssao） | ao_resolve |
| 27 | 方向天光可重估份额 | 原生 | R11F_G11F_B10F | lit | ao_resolve |
| 28 | 主世界：次表面实体放射+线性视深；下界：反射载体 | 原生 | RG32F（主世界）/ RGBA16F（下界） | lit / nether_reflection | water.glsl / nether_reflection_resolve |
| 29 | ITT 水面碰撞通量场 | 1024²（开时） | RG16F | composite1 | scattering.vsh、light_shafts |
| 30 | 效果历史状态（3 texel） | 3×1 | RGBA32F | composite9 | effect_history.glsl |
| 31 | 末地星表 | 1024×384 | RGBA32F | world1/setup*.csh | end_system |

格式原文：

`Astra/shaders/lib/water_buffer_formats.glsl:12`
```glsl
const int colortex0Format = R11F_G11F_B10F;
```

`Astra/shaders/lib/water_buffer_formats.glsl:15`
```glsl
const int colortex2Format = R11F_G11F_B10F;
```

`Astra/shaders/lib/water_buffer_formats.glsl:22`
```glsl
const int colortex4Format = R11F_G11F_B10F;
```

`Astra/shaders/lib/scene_buffer_formats.glsl:7`
```glsl
const int colortex9Format = RGBA16F;
```

`Astra/shaders/lib/surface_buffers.glsl:14`
```glsl
const int colortex19Format = R11F_G11F_B10F;
```

`Astra/shaders/lib/surface_buffers.glsl:17`
```glsl
const int colortex20Format = RGBA8;
```

`Astra/shaders/lib/surface_buffers.glsl:28`
```glsl
const int colortex22Format = RGBA16F;
```

`Astra/shaders/lib/surface_buffers.glsl:24`
```glsl
const int colortex27Format = R11F_G11F_B10F;
```

`Astra/shaders/lib/cloud_buffer_formats.glsl:13`
```glsl
const int colortex12Format = RGBA16F;
```

`Astra/shaders/lib/smaa_buffer.glsl:8`
```glsl
const int colortex7Format = RGBA8;
```

`Astra/shaders/lib/taa_reactive.glsl:7`
```glsl
const int colortex16Format = R8;
```

`Astra/shaders/global/atmosphere/cloud_temporal.glsl:31`
```glsl
const int colortex24Format = RGBA16F;
```

`Astra/shaders/global/atmosphere/cloud_temporal.glsl:37`
```glsl
const int colortex25Format = RGBA16F;
```

`Astra/shaders/global/post/exposure.glsl:32`
```glsl
const int colortex10Format = RGBA32F;
```

`Astra/shaders/program/end_illumination.fsh:15`
```glsl
const int colortex8Format = RGBA32F;
```

`Astra/shaders/program/lit.fsh:26`
```glsl
const int colortex28Format = RG32F;
```

`Astra/shaders/program/nether_reflection.fsh:15`
```glsl
const int colortex28Format = RGBA16F;
```

`Astra/shaders/program/taa_resolve.fsh:19`
```glsl
const int colortex15Format = RGBA16F;
```

`Astra/shaders/program/taa_state.fsh:9`
```glsl
const int colortex17Format = RGBA32F;
```

`Astra/shaders/program/volume_main.fsh:25`
```glsl
const int colortex23Format = RGBA16F;
```

`Astra/shaders/program/ssao.fsh:22`
```glsl
const int colortex21Format = RGBA16F;
```

`Astra/shaders/program/ssao.fsh:29`
```glsl
const int colortex26Format = RG16F;
```

`Astra/shaders/program/sky_irradiance.fsh:11`
```glsl
const int colortex18Format = RGBA16F;
```

`Astra/shaders/program/cloud_shadow_cache.fsh:7`
```glsl
const int colortex14Format = R16;
```

`Astra/shaders/program/water_state.fsh:13`
```glsl
const int colortex6Format = RGBA32F;
```

`Astra/shaders/program/itt_water_normal_cache.fsh:12`
```glsl
const int colortex29Format = RG16F;
```

`Astra/shaders/program/effect_history_state.fsh:8`
```glsl
const int colortex30Format=RGBA32F;
```

`Astra/shaders/lib/end_star_catalogue.glsl:12`
```glsl
const int colortex31Format = RGBA32F;
```

`Astra/shaders/program/display.fsh:105`
```glsl
    const int colortex13Format = RGBA16;
```

尺寸原文（节选）：

`Astra/shaders/shaders.properties:47`
```glsl
size.buffer.colortex6=3 1
```

`Astra/shaders/shaders.properties:48`
```glsl
size.buffer.colortex8=316 1
```

`Astra/shaders/shaders.properties:58`
```glsl
size.buffer.colortex10=1 1
```

`Astra/shaders/shaders.properties:78`
```glsl
size.buffer.colortex31=1024 384
```

`Astra/shaders/shaders.properties:236`
```glsl
size.buffer.colortex29=1024 1024
```

`Astra/shaders/shaders.properties:41`
```glsl
size.buffer.colortex2=0.25 0.25
```

`Astra/shaders/shaders.properties:202`
```glsl
size.buffer.colortex23=0.5 0.5
```

**flip 情况 [源码]**：整包没有一条 `flip.*` 指令；properties 明确写了原因：

`Astra/shaders/shaders.properties:163`
```glsl
# Iris flips written attachments automatically; an explicit true would flip twice.
```

历史读法靠"同一 pass 既写又读 → 读到上一帧"，cloud_temporal 头注释写明：

`Astra/shaders/global/atmosphere/cloud_temporal.glsl:11`
```glsl
// cloud_screen.fsh (deferred). It reads both through Iris's buffer flip - a program
```

---

## 3. 阴影：投射端、深度校正、过滤与 bias

### 3.1 两份 shadow 入口，同一主体

`shadow`（带 alpha 裁剪）与 `shadow_solid`（Iris 的不透明 Sodium 地形 OFF-alpha 通道）共用同一个 `program/shadow.vsh/fsh`：

`Astra/shaders/shadow_solid.vsh:5`
```glsl
#define ASTRA_SOLID_SHADOW
```

`Astra/shaders/program/shadow.fsh:103`
```glsl
    #ifdef ASTRA_SOLID_SHADOW
```

`Astra/shaders/program/shadow.fsh:46`
```glsl
/* RENDERTARGETS: 0 */
```

### 3.2 植被投射：texcoord 沿"未畸变真实光线"重算，再夹回图集矩形

顶点阶段把这片叶子的纹理包围盒传下来：

`Astra/shaders/program/shadow.vsh:172`
```glsl
        vec2 halfExtent = abs(gl_MultiTexCoord0.xy-mc_midTexCoord.xy);
```

`Astra/shaders/program/shadow.vsh:173`
```glsl
        shadowFoliageTexBounds = vec4(mc_midTexCoord.xy-halfExtent,mc_midTexCoord.xy+halfExtent);
```

片元阶段先取导数（必须在任何 alpha/材质分支之前），再用 2×2 伪逆把 texcoord 沿真实光线重投影，最后夹回矩形：

`Astra/shaders/program/shadow.fsh:58`
```glsl
    vec3 shadowDx=dFdx(shadowUndistortedPosition);
```

`Astra/shaders/program/shadow.fsh:73`
```glsl
        vec2 uvRawX=(shadowTexcoordDx*shadowDy.y-shadowTexcoordDy*shadowDx.y)/shadowDet;
```

`Astra/shaders/program/shadow.fsh:76`
```glsl
        shadowTexcoord+=uvRawX*rawDelta.x+uvRawY*rawDelta.y;
```

`Astra/shaders/program/shadow.fsh:83`
```glsl
        shadowTexcoord=clamp(shadowTexcoord,shadowFoliageTexBounds.xy+inset,
```

### 3.3 深度：改成"反畸变平面"的解析深度

**Astra 阴影最特殊的一处**：深度不是光栅化深度，而是按片元所在平面、沿畸变后的光线重新解算：

`Astra/shaders/program/shadow.fsh:87`
```glsl
    gl_FragDepth=gl_FragCoord.z;
```

`Astra/shaders/program/shadow.fsh:88`
```glsl
    bool analyticPlane = abs(shadowCasterPlaneNormal.z)>1e-6;
```

`Astra/shaders/program/shadow.fsh:93`
```glsl
        float planeDepth=(shadowUndistortedPosition.z
```

`Astra/shaders/program/shadow.fsh:99`
```glsl
        gl_FragDepth=planeDepth;
```

法线在顶点阶段先做投影缩放，供上面解析平面使用：

`Astra/shaders/program/shadow.vsh:232`
```glsl
    shadowUndistortedPosition = gl_Position.xyz/gl_Position.w;
```

`Astra/shaders/program/shadow.vsh:237`
```glsl
        shadowCasterPlaneNormal = (gl_NormalMatrix * gl_Normal)
```

### 3.4 径向畸变与纹元宽度换算

压缩强度锚在世界块上，不是固定常数：

`Astra/shaders/lib/distort.glsl:16`
```glsl
const float SHADOW_DISTORT_CORE = 25.6;
```

`Astra/shaders/lib/distort.glsl:20`
```glsl
const float SHADOW_DISTORT_FACTOR = SHADOW_DISTORT_CORE / shadowDistance;
```

`Astra/shaders/lib/distort.glsl:34`
```glsl
    float factor = get_distort_factor(pos.xy);
```

`Astra/shaders/lib/distort.glsl:35`
```glsl
    return vec3(pos.xy / factor, pos.z * 0.5);
```

`Astra/shaders/program/shadow.vsh:242`
```glsl
	gl_Position.xyz = distort(gl_Position.xyz / gl_Position.w) * gl_Position.w;
```

`Astra/shaders/program/shadow.fsh:61`
```glsl
    vec2 ray=undistort(vec3(gl_FragCoord.xy*(2.0/float(shadowMapResolution))-1.0,0.0)).xy;
```

### 3.5 Bias：没有常数表，只有"图半径线性项 + 掠射法线项"

`Astra/shaders/global/lighting/shadowmap.glsl:362`
```glsl
const float shadowGrazingBias = 0.20;
```

`Astra/shaders/global/lighting/shadowmap.glsl:408`
```glsl
    float bias = 1.5 * length(raw.xy)
```

`Astra/shaders/global/lighting/shadowmap.glsl:409`
```glsl
               + shadowGrazingBias * (1.0 - max(ndotl, 0.0));
```

`Astra/shaders/global/lighting/shadowmap.glsl:411`
```glsl
    shadowPos.z -= 0.00001;
```

### 3.6 过滤规模：4 个 lobe × 每个 4 个 depth 比较，**无旋转核**

`Astra/shaders/global/lighting/shadowmap.glsl:104`
```glsl
const float shadowTexelSpread = SHADOW_SOFTNESS * (1.0 / shadowMapResolution);
```

`Astra/shaders/global/lighting/diffuse.glsl:309`
```glsl
        const int lobeCount = 4;
```

`Astra/shaders/global/lighting/diffuse.glsl:313`
```glsl
        float spread = float(SHADOW_SOFTNESS)*0.5;
```

`Astra/shaders/global/lighting/diffuse.glsl:346`
```glsl
                             (lobe & 2)==0 ? -1.0 : 1.0)*(0.70710678*spread);
```

`Astra/shaders/lib/settings.glsl:88`
```glsl
#define SHADOW_SOFTNESS 2 // [1 2 4]
```

`Astra/shaders/lib/settings.glsl:73`
```glsl
#define SHADOW_FILTER_QUALITY 1 // [0 1 2]
```

偏移是四个固定对角方向，只有 `SHADOW_FILTER_QUALITY == 1` 时乘 0.7071；**没有任何逐帧旋转或泊松盘**。

### 3.7 距离缩放：软半径按"屏幕像素的世界尺寸"换算回纹元

`Astra/shaders/global/lighting/diffuse.glsl:324`
```glsl
        float worldTexel = (2.0*shadowDistance*SHADOW_DISTORT_FACTOR)
```

`Astra/shaders/global/lighting/diffuse.glsl:326`
```glsl
        float softRadius=max(0.22,0.75*sqrt(astraSurfaceShadowPixelWorldSquared));
```

`Astra/shaders/global/lighting/diffuse.glsl:327`
```glsl
        spread = clamp(softRadius/max(worldTexel,0.0001),0.5*spread,spread);
```

### 3.8 预算档（OVERWORLD_BUDGET > 0）：32 块内 2 lobe、之外 1 lobe

`Astra/shaders/lib/settings.glsl:376`
```glsl
#define OVERWORLD_BUDGET 1 // [0 1 2]
```

`Astra/shaders/global/lighting/diffuse.glsl:361`
```glsl
        float budgetNear = 1.0 - smoothstep(24.0, 32.0, length(playerPos));
```

`Astra/shaders/global/lighting/diffuse.glsl:365`
```glsl
            for (int lobe = 0; lobe < 2; ++lobe) {
```

`Astra/shaders/global/lighting/diffuse.glsl:364`
```glsl
            float budgetSpread = min(float(SHADOW_SOFTNESS), 2.0) * 0.5 * budgetNear;
```

### 3.9 一次 lobe 查询内部：四角配对（深度比较 + 遮挡物身份）

不是简单 PCF：每个角必须配自己的深度与自己的遮挡物 tint / 水位。

`Astra/shaders/global/lighting/shadowmap.glsl:174`
```glsl
vec4 shadow_corner_weights(vec2 f) {
```

`Astra/shaders/global/lighting/shadowmap.glsl:176`
```glsl
                (1.0-f.x)*f.y, f.x*f.y);
```

`Astra/shaders/global/lighting/shadowmap.glsl:188`
```glsl
    return step(vec4(referenceDepth), textureGather(depths, clamp(uv,edge,1.0-edge), 0).wzxy);
```

`Astra/shaders/global/lighting/shadowmap.glsl:274`
```glsl
    vec4 allVisibility = shadow_surface_visibility_inside(shadowtex0, uv, referenceDepths);
```

`Astra/shaders/global/lighting/shadowmap.glsl:293`
```glsl
    vec4 transparentWeight = max(opaqueVisibility-allVisibility, vec4(0.0)) * weights;
```

水面占多数的接收面走便宜路径：只 gather 高度、焦散焦点，不读 4 条完整 RGBA 记录：

`Astra/shaders/global/lighting/shadowmap.glsl:307`
```glsl
          vec4 waterHeights = textureGather(shadowcolor0, uv, 0).wzxy;
```

`Astra/shaders/global/lighting/shadowmap.glsl:308`
```glsl
          if (all(lessThan(waterHeights, vec4(WATER_HEIGHT_NONE)))) {
```

### 3.10 硬件比较模式（SHADOW_FILTER_MODE 1）

`Astra/shaders/lib/settings.glsl:72`
```glsl
#define SHADOW_FILTER_MODE 0 // [0 1]
```

`Astra/shaders/global/lighting/shadowmap.glsl:60`
```glsl
uniform sampler2DShadow shadowtex0;
```

`Astra/shaders/global/lighting/shadowmap.glsl:235`
```glsl
    // Hardware gather accepts only one reference. Select each corner from its
```

`Astra/shaders/global/lighting/shadowmap.glsl:242`
```glsl
    for (int i=0;i<4;++i) {
```

`Astra/shaders/lib/settings.glsl:706`
```glsl
const bool shadowHardwareFiltering = false;
```

### 3.11 投射端裁剪：只裁草/花，不裁树叶

`Astra/shaders/program/shadow.vsh:152`
```glsl
        if (dot(plantCenter, plantCenter) > 48.0 * 48.0) {
```

### 3.12 距离、覆盖淡出与圆盘边界

`Astra/shaders/lib/settings.glsl:82`
```glsl
#define SHADOW_DISTANCE 96 // [64 80 96 112 128]
```

`Astra/shaders/global/lighting/shadowmap.glsl:120`
```glsl
    return 1.0 - smoothstep(shadowDistance - 24.0, shadowDistance - 8.0,
```

`Astra/shaders/global/lighting/shadowmap.glsl:132`
```glsl
    float radialBorder = 0.5 * (1.0 - length(shadowPos.xy * 2.0 - 1.0));
```

### 3.13 下界：阴影贴图退化成体素抓取通道

`Astra/shaders/lib/settings.glsl:424`
```glsl
const int   shadowMapResolution = 64;
```

`Astra/shaders/lib/settings.glsl:425`
```glsl
const float shadowDistance = 48.0;
```

`Astra/shaders/program/shadow.vsh:109`
```glsl
    gl_Position = vec4(0.0, 0.0, 2.0, 1.0);
```

---


## 4. 云：步进、二分细化、LOD、时域历史

### 4.1 开关与默认

`Astra/shaders/lib/settings.glsl:111`
```glsl
#define CLOUD_MODE 1 // [0 1 2]
```

`Astra/shaders/lib/settings.glsl:112`
```glsl
#define CLOUD_QUALITY 2 // [0 1 2]
```

`Astra/shaders/lib/settings.glsl:126`
```glsl
#define CLOUD_TEMPORAL // [false true]
```

`Astra/shaders/lib/settings.glsl:753`
```glsl
    #define ASTRA_CLOUD_TEMPORAL
```

### 4.2 几何模型与出处（注释里逐条列出对照行）

`Astra/shaders/global/atmosphere/clouds_planar.glsl:8`
```glsl
//  Reference root: _analysis/Complementary r5.9/Reimagined/shaders/
```

`Astra/shaders/global/atmosphere/clouds_planar.glsl:9`
```glsl
//    lib/atmospherics/clouds/cloudCoord.glsl:4-28
```

`Astra/shaders/global/atmosphere/clouds_planar.glsl:58`
```glsl
const float ASTRA_CLOUD_NARROWNESS = 0.07;
```

`Astra/shaders/global/atmosphere/clouds_planar.glsl:61`
```glsl
const float ASTRA_CLOUD_STRETCH   = 9.0;
```

`Astra/shaders/global/atmosphere/clouds_planar.glsl:69`
```glsl
const float ASTRA_CLOUD_ALTITUDE = 192.0;
```

`Astra/shaders/global/atmosphere/clouds_planar.glsl:65`
```glsl
const float ASTRA_CLOUD_THRESHOLD_F = 4000.0;
```

密度存在性门与粗噪声：

`Astra/shaders/global/atmosphere/clouds_planar.glsl:117`
```glsl
    return 0.25 + layerThreshold * 0.5 + coverageBias;
```

`Astra/shaders/global/atmosphere/clouds_planar.glsl:130`
```glsl
    return 0.78 * astra_2d_cloud_sample(tracePosM.xz);
```

### 4.3 步进数：按层内穿越长度分档（不是固定循环）

| 档 | 步数范围 | 步长 |
|---|---|---|
| 低（CLOUD_QUALITY 0） | 4–12 | 自适应 |
| 中（1） | 6–16 | 自适应 |
| 高（2） | 4–512 | `max(4.0, planeDistanceDif/512.0)` |
| 反射环境（sky cache 写）+ 低 | 4–6 | 自适应 |
| 反射环境 + 中 | 4–8 | 自适应 |

`Astra/shaders/global/atmosphere/clouds_planar.glsl:293`
```glsl
    int sampleCount = clamp(int(ceil(planeDistanceDif/48.0)),4,12);
```

`Astra/shaders/global/atmosphere/clouds_planar.glsl:297`
```glsl
    int sampleCount = clamp(int(ceil(planeDistanceDif/32.0)),6,16);
```

`Astra/shaders/global/atmosphere/clouds_planar.glsl:295`
```glsl
    int sampleCount = clamp(int(ceil(planeDistanceDif/4.0)),4,512);
```

`Astra/shaders/global/atmosphere/clouds_planar.glsl:302`
```glsl
    float stepMult = max(4.0,planeDistanceDif/512.0);
```

`Astra/shaders/global/atmosphere/clouds_planar.glsl:288`
```glsl
    int sampleCount = clamp(int(ceil(planeDistanceDif/64.0)),4,6);
```

`Astra/shaders/global/atmosphere/clouds_planar.glsl:290`
```glsl
    int sampleCount = clamp(int(ceil(planeDistanceDif/48.0)),4,8);
```

### 4.4 低/中档：粗扫 + 2 次二分细化（反射环境 1 次）

`Astra/shaders/global/atmosphere/clouds_planar.glsl:392`
```glsl
        const int refineCount = 2;
```

`Astra/shaders/global/atmosphere/clouds_planar.glsl:390`
```glsl
        const int refineCount = 1;
```

`Astra/shaders/global/atmosphere/clouds_planar.glsl:394`
```glsl
        for (int refine=0; refine<refineCount; ++refine) {
```

`Astra/shaders/global/atmosphere/clouds_planar.glsl:395`
```glsl
            float middle = 0.5*(lowDistance+highDistance);
```

### 4.5 高档：区间积分 + 相邻段共用端点粗噪声

`Astra/shaders/global/atmosphere/clouds_planar.glsl:317`
```glsl
    vec3 initialPosition = cameraPosition+minPlaneDistance*nPlayerPos;
```

`Astra/shaders/global/atmosphere/clouds_planar.glsl:439`
```glsl
        float sampleAlpha = (1.0-exp(-columnDensity*segmentLength*ASTRA_CLOUD_DENSITY_EXTINCTION))
```

`Astra/shaders/global/atmosphere/clouds_planar.glsl:441`
```glsl
        float weight = (1.0-volumetricClouds.a)*sampleAlpha;
```

`Astra/shaders/global/atmosphere/clouds_planar.glsl:444`
```glsl
        representativeWorld += tracePos*weight;
```

`Astra/shaders/global/atmosphere/clouds_planar.glsl:609`
```glsl
        representativeWorld /= volumetricClouds.a;
```

低/中档的 alpha 是"首个命中 + 距离因子"：

`Astra/shaders/global/atmosphere/clouds_planar.glsl:596`
```glsl
        volumetricClouds.a = sqrt(cloudDistanceFactor * 1.33333)*columnDensity;
```

`Astra/shaders/global/atmosphere/clouds_planar.glsl:597`
```glsl
        volumetricClouds.rgb = colorSample;
```

### 4.6 每像素光照采样数：低/中 1 次，高 2 次

`Astra/shaders/global/atmosphere/clouds_planar.glsl:499`
```glsl
        light -= 2.0*(unshiftedLight ? coarseSample : astra_2d_cloud_sample(cLightPos.xz))*cloudShadingM;
```

`Astra/shaders/global/atmosphere/clouds_planar.glsl:502`
```glsl
		    light -= (unshiftedLight ? coarseSample : astra_2d_cloud_sample(cLightPos.xz)) * cloudShadingM;
```

`Astra/shaders/global/atmosphere/clouds_planar.glsl:485`
```glsl
		vec3 cLightPosAdd = astraWorldLightDirection * 0.08 * f.shadowTime;
```

### 4.7 屏幕云：每帧在云网格上跑一次；高档 4 条子像素射线

**分辨率**由 `size.buffer.colortex24/25` 决定（0.25² / 0.5² / 1.0²）。

`Astra/shaders/program/cloud_screen.fsh:51`
```glsl
    for (int sampleIndex=0;sampleIndex<4;++sampleIndex) {
```

`Astra/shaders/program/cloud_screen.fsh:52`
```glsl
        vec2 offset=vec2((sampleIndex & 1)==0 ? -0.25 : 0.25,
```

`Astra/shaders/program/cloud_screen.fsh:61`
```glsl
        sum += vec4(cloud.rgb*cloud.a,cloud.a);
```

**遮挡剔除**：不透明瓦片整块跳过 march；低质量档用 4 次 gather 覆盖 4×4 原生深度。

`Astra/shaders/program/cloud_screen.fsh:142`
```glsl
            occluded = opaqueDistance + 8.0 + interval.x * angularFootprint * 2.0 < interval.x;
```

`Astra/shaders/program/cloud_screen.fsh:131`
```glsl
            vec4 depths = textureGather(depthtex0, clamp(texcoord + offset, edge, 1.0 - edge), 0);
```

### 4.8 时域历史：写 24/25，靠"同 pass 读写"拿上一帧

`Astra/shaders/global/atmosphere/cloud_temporal.glsl:31`
```glsl
const int colortex24Format = RGBA16F;
```

`Astra/shaders/global/atmosphere/cloud_temporal.glsl:41`
```glsl
uniform sampler2D colortex24;
```

`Astra/shaders/global/atmosphere/cloud_temporal.glsl:37`
```glsl
const int colortex25Format = RGBA16F;
```

元数据编码（注释原文）：rgb 之外的 r=代表距离、g=帧号取模、b=视口指纹、a=覆盖率。

`Astra/shaders/global/atmosphere/cloud_temporal.glsl:35`
```glsl
// producing ray, g = frameCounter modulo 2048 (exact in half float), b = viewWidth
```

`Astra/shaders/global/atmosphere/cloud_temporal.glsl:72`
```glsl
    float stampNow = float(frameCounter % 2048);
```

`Astra/shaders/global/atmosphere/cloud_temporal.glsl:73`
```glsl
    metaOut = vec4(0.0, stampNow, viewWidth, current.a);
```

### 4.9 历史占比

`Astra/shaders/global/atmosphere/cloud_temporal.glsl:49`
```glsl
const float ASTRA_CLOUD_TEMPORAL_WEIGHT = 0.75;
```

`Astra/shaders/global/atmosphere/cloud_temporal.glsl:51`
```glsl
const float ASTRA_CLOUD_TEMPORAL_WEIGHT = 0.90;
```

`Astra/shaders/global/atmosphere/cloud_temporal.glsl:56`
```glsl
const float ASTRA_CLOUD_TEMPORAL_EMPTY_WEIGHT = 0.95;
```

`Astra/shaders/global/atmosphere/cloud_temporal.glsl:61`
```glsl
const float ASTRA_CLOUD_TEMPORAL_COVERAGE_FLOOR = 0.15;
```

### 4.10 拒绝条件（全部退回"当前帧"）

| # | 条件 | 原文 |
|---|---|---|
| 1 | 无有效历史帧 / 当前空且未采到可见 / NaN·Inf | 见下 |
| 2 | 高档：当前覆盖率为 0 | `if (current.a <= 0.0) return current;` |
| 3 | 元数据帧号不是上一帧 | 见下 |
| 4 | 视口宽度漂移 > 8px | 见下 |
| 5 | 空列但历史无覆盖或无距离 | 见下 |
| 6 | 重投影越界（离屏进入） | 见下 |
| 7 | 代表距离与期望差 > 16 + 3% | 见下 |

`Astra/shaders/global/atmosphere/cloud_temporal.glsl:77`
```glsl
    if (cloudFrameValid == 0 || (current.a <= 0.0 && !sampledVisible)
```

`Astra/shaders/global/atmosphere/cloud_temporal.glsl:84`
```glsl
    if (current.a <= 0.0) return current;
```

`Astra/shaders/global/atmosphere/cloud_temporal.glsl:95`
```glsl
    if (metaHere.g != float((frameCounter - 1) % 2048)
```

`Astra/shaders/global/atmosphere/cloud_temporal.glsl:96`
```glsl
        || abs(metaHere.b - viewWidth) > 8.0) return current;
```

`Astra/shaders/global/atmosphere/cloud_temporal.glsl:138`
```glsl
        || any(lessThan(uvPrev, margin)) || any(greaterThan(uvPrev, 1.0 - margin)))
```

`Astra/shaders/global/atmosphere/cloud_temporal.glsl:148`
```glsl
    float distanceTolerance = 16.0 + expectedDistance * 0.03;
```

`Astra/shaders/global/atmosphere/cloud_temporal.glsl:163`
```glsl
            || abs(meta.r - expectedDistance) > distanceTolerance) continue;
```

### 4.11 重投影假设：云场沿 +Z 每秒平移 1 格

**这是历史能用的关键前提**——把当前命中点沿 -Z 回退一帧时间，再用真实的上一帧矩阵投影（不是只用旋转）：

`Astra/shaders/global/atmosphere/cloud_temporal.glsl:119`
```glsl
    vec3 featurePrev = representativeWorld - vec3(0.0, 0.0, dt);
```

`Astra/shaders/global/atmosphere/cloud_temporal.glsl:120`
```glsl
    vec4 prevClip = gbufferPreviousProjection
```

`Astra/shaders/global/atmosphere/cloud_temporal.glsl:121`
```glsl
                  * (gbufferPreviousModelView * vec4(featurePrev - previousCameraPosition, 1.0));
```

配套要求：抖动相位必须**固定不逐帧旋转**：

`Astra/shaders/global/atmosphere/clouds_planar.glsl:159`
```glsl
    return fract(52.9829189 * fract(0.06711056 * gl_FragCoord.x + 0.00583715 * gl_FragCoord.y));
```

`Astra/shaders/global/atmosphere/clouds_planar.glsl:158`
```glsl
    // lattice phase itself can stay fixed without locking coverage into sheets.
```

### 4.12 历史权重的三个折减项

`Astra/shaders/global/atmosphere/cloud_temporal.glsl:214`
```glsl
        weight *= 1.0 - smoothstep(0.20, 0.80, abs(histY - curY) / max(max(histY, curY), 0.05));
```

`Astra/shaders/global/atmosphere/cloud_temporal.glsl:215`
```glsl
        weight *= 1.0 - smoothstep(0.35, 0.90,
```

`Astra/shaders/global/atmosphere/cloud_temporal.glsl:201`
```glsl
        weight = ASTRA_CLOUD_TEMPORAL_EMPTY_WEIGHT * emptyMotionWeight * coverage;
```

### 4.13 消费侧：deferred 两处读云

天空像素读已解算的 24；几何像素（落在云板内）现场跑一条被地形截断的 march：

`Astra/shaders/global/atmosphere/clouds_screen.glsl:108`
```glsl
vec4 astra_screen_cloud(vec2 uv, vec3 ray, float opaqueDistance, float angularFootprint) {
```

`Astra/shaders/global/atmosphere/clouds_screen.glsl:112`
```glsl
    if (opaqueDistance < interval.y * 1.02 + 4.0) {
```

`Astra/shaders/global/atmosphere/clouds_screen.glsl:120`
```glsl
    return astra_screen_cloud_sample(uv);
```

`Astra/shaders/program/deferred.fsh:368`
```glsl
            displayed = displayed * (1.0 - sheet.a) + sheet.rgb;
```

---


## 5. 水：模块分工与每像素采样规模

### 5.1 模块清单与职责

| 文件 | 职责 | 依据 |
|---|---|---|
| `global/water/surface.glsl` | 波浪法线（Steadfast 波场 + 解析梯度 + Nyquist 过滤） | 头注释指向 Steadfast `surface_noise*.glsl` |
| `global/water/optics.glsl` | 介质界面 Fresnel（IOR 1.333，全反射判定） | `WATER_IOR` |
| `global/water/caustics.glsl` | Solas 风格水面法线/焦散（侧面与非主世界路径） | 头注释 "Adapted from Solas V2.2b" |
| `lib/itt_water_waves.glsl` | ITT 六层波，用于水下界面与光轴 | 头注释 "IterationT 3.2.0 WaterWaves.glsl" |
| `global/water/raytrace.glsl` | 屏幕空间反射（SSR） | "no source shader code was incorporated" |
| `global/water/refraction.glsl` | 折射 UV 位移与端点配对 | "Adapted from Steadfast 0.8.0" |
| `global/water/absorption.glsl` | Beer-Lambert 吸收 + 单次散射源项 | SC-34 |
| `global/water/light_shafts.glsl` | 水下体积光束（Gauss-Legendre 4 节点 × N 区间） | "Adapted from IterationT 3.2.0" |
| `global/water/medium_state.glsl` | 水体体积状态位（colortex6 texel0） | — |
| `global/water/temporal.glsl` | **已退休**（无任何 include） | 文件头 "RETIRED" |
| `program/water.glsl` | 水面合成总入口 | — |

`Astra/shaders/global/water/optics.glsl:5`
```glsl
const float WATER_IOR = 1.333;
```

`Astra/shaders/global/water/absorption.glsl:19`
```glsl
    return vec3(0.032, 0.014, 0.012) * (WATER_ABSORPTION * 0.01);
```

`Astra/shaders/global/water/absorption.glsl:56`
```glsl
    return vec3(0.026, 0.045, 0.048) * (UNDERWATER_FOG_DENSITY * 0.01);
```

`Astra/shaders/global/water/absorption.glsl:73`
```glsl
    return radiance * transmission + incidentLight * scatteringAlbedo * (1.0 - transmission);
```

`Astra/shaders/lib/itt_water_waves.glsl:3`
```glsl
// IterationT 3.2.0 WaterWaves.glsl: six layers, weights, transforms, scrolling
```

### 5.2 水面法线：每像素 gather 次数

波场 = 4 层 ripple + 2 层 crest；默认 `WATER_WAVE_QUALITY 0` 只算前 2 层 ripple + 2 层 crest，其余层只贡献固定平均坡度到粗糙度：

`Astra/shaders/lib/settings.glsl:165`
```glsl
#define WATER_WAVE_QUALITY 0 // [0 1 2]
```

`Astra/shaders/global/water/surface.glsl:170`
```glsl
#define ASTRA_SURFACE_RIPPLE_LAYERS 2
```

`Astra/shaders/global/water/surface.glsl:57`
```glsl
	vec4 corners = textureGather(steadfastWaterNoise, center);
```

`Astra/shaders/global/water/surface.glsl:222`
```glsl
	for (int i = ASTRA_SURFACE_RIPPLE_LAYERS; i < 4; ++i) {
```

**[源码]** 每层波算一次 `textureGather`（4 个纹元）。默认档参与计算的层是 2 层 ripple + 2 层 crest，所以**每像素最多 4 次 gather**；`WATER_WAVE_QUALITY 2` 时 6 层，最多 6 次。被 Nyquist 完全过滤掉的层会 `continue` 跳过，不再 fetch。

`Astra/shaders/global/water/surface.glsl:256`
```glsl
        if (aa >= 1.0) {
```

`Astra/shaders/global/water/surface.glsl:259`
```glsl
            unresolved += (0.43 * SURFACE_GRADIENT_STRENGTH * rippleMagnitude[i]) * length(stretch);
```

`Astra/shaders/global/water/surface.glsl:356`
```glsl
        surface.roughness=0.035+0.10*sqrt(clamp(unresolved*0.08,0.0,1.0));
```

### 5.3 反射：SSR 步进预算（按水效果质量与预算档）

| 档 | 总预算 | 粗步 | 细化 |
|---|---|---|---|
| WATER_EFFECT_QUALITY 0 | 12 | 8 | 4 |
| 1（默认） | 20 | 16 | 4 |
| 2 | 40 | 32 | 8 |
| 主世界预算档 + quality>0 | 20（32 块外粗步压到 12） | 16→12 | 4 |

`Astra/shaders/lib/settings.glsl:181`
```glsl
#define WATER_EFFECT_QUALITY 0 // [0 1 2]
```

`Astra/shaders/global/water/raytrace.glsl:19`
```glsl
const int ASTRA_WATER_RAW_BUDGET = 12;
```

`Astra/shaders/global/water/raytrace.glsl:25`
```glsl
const int ASTRA_WATER_RAW_BUDGET = 20;
```

`Astra/shaders/global/water/raytrace.glsl:22`
```glsl
const int ASTRA_WATER_RAW_BUDGET = 40;
```

`Astra/shaders/global/water/raytrace.glsl:45`
```glsl
const int ASTRA_WATER_TRACE_BUDGET = 20;
```

`Astra/shaders/global/water/raytrace.glsl:48`
```glsl
const int ASTRA_WATER_FAR_COARSE_STEPS = 12;
```

`Astra/shaders/global/water/raytrace.glsl:348`
```glsl
    for (int i = 0; i < ASTRA_WATER_COARSE_STEPS; ++i) {
```

`Astra/shaders/global/water/raytrace.glsl:502`
```glsl
    for (int i = 0; i < ASTRA_WATER_REFINE_STEPS && high > low; ++i) {
```

每步的世界步长随深度放大：

`Astra/shaders/global/water/raytrace.glsl:304`
```glsl
    float stride = clamp(-viewPos.z * 0.0025, 0.08, 0.25);
```

`Astra/shaders/global/water/raytrace.glsl:312`
```glsl
    float coarseBudget = mix(float(max(6, ASTRA_WATER_COARSE_STEPS / 2)),
```

### 5.4 折射：**1 像素**配对读取，不是 2×2 足迹

`Astra/shaders/global/water/refraction.glsl:103`
```glsl
    float distance = min(abs(viewPos.z - backgroundZ), 32.0);
```

`Astra/shaders/global/water/refraction.glsl:54`
```glsl
// A refracted query reads ONE pixel: the texel containing its UV supplies the
```

`Astra/shaders/program/water.glsl:1121`
```glsl
                valid = water_transmission_sample(refractedUV,viewPos,viewGeometric,
```

### 5.5 反射命中后的取样：预算档用一次 2×2 gather 取代 5 个 2×2 锥

`Astra/shaders/program/water.glsl:421`
```glsl
        && water_surface_fast_sample(uv,size,origin,faceNormal,airReflection,submergedReflection,airTransmission,receiverDistance,skylight,
```

`Astra/shaders/program/water.glsl:285`
```glsl
    if (depths.x < 0.0) depths = textureGather(depthtex1,gatherUV,0).wzxy;
```

`Astra/shaders/program/water.glsl:286`
```glsl
    entityRecords = textureGather(colortex28,gatherUV,1).wzxy;
```

### 5.6 水面合成的开关与分支顺序

`Astra/shaders/program/water.glsl:941`
```glsl
        if (water && abs(geometric.y) <= 0.9)
```

`Astra/shaders/program/water.glsl:943`
```glsl
        if (water && belowWater) return astra_underwater_interface(color,viewPos,viewNormal,viewGeometric,
```

`Astra/shaders/program/water.glsl:961`
```glsl
        fresnel = (waterF0 + (1.0-waterF0) * pow5(clamp(1.0 + dot(incident, viewNormal), 0.0, 1.0))) * skylight;
```

`Astra/shaders/program/water.glsl:1015`
```glsl
    screenReflectionShare = (!belowWater && geometric.y > 0.9) ? smoothstep(0.36, 0.50, fresnel) : smoothstep(0.045, 0.085, fresnel);
```

`Astra/shaders/program/water.glsl:1028`
```glsl
        vec4 hit = water_raytrace(depthtex1, viewPos, reflectedRay, viewGeometric, 1e20, queryImportance,
```

`Astra/shaders/program/water.glsl:1225`
```glsl
    color = astra_apply_medium(color, playerPos, skylight);
```

### 5.7 水下体积光束：Gauss-Legendre 4 节点 × N 区间

**每像素内外层循环**：`ASTRA_SHAFT_SAMPLES` 个区间，每区间 4 个节点 → 默认 7×4 = **28 次可见性查询**（每次含一次 shadow gather）：

`Astra/shaders/global/water/light_shafts.glsl:236`
```glsl
    const vec4 nodes = vec4(0.0694318442,0.3300094782,0.6699905218,0.9305681558);
```

`Astra/shaders/global/water/light_shafts.glsl:237`
```glsl
    const vec4 weights = vec4(0.1739274226,0.3260725774,0.3260725774,0.1739274226);
```

`Astra/shaders/global/water/light_shafts.glsl:243`
```glsl
    for (int interval=0;interval<ASTRA_SHAFT_SAMPLES;++interval) {
```

`Astra/shaders/global/water/light_shafts.glsl:254`
```glsl
        for (int node=0;node<4;++node) {
```

`Astra/shaders/lib/settings.glsl:208`
```glsl
#define UNDERWATER_SHAFT_SAMPLES 7 // [4 7 10]
```

`Astra/shaders/global/water/light_shafts.glsl:26`
```glsl
    #define ASTRA_SHAFT_SAMPLES 7
```

区间长度与积分上限：

`Astra/shaders/global/water/light_shafts.glsl:235`
```glsl
    float stepLength = min(astraWaterShaftRange,WATER_SHAFT_FAR_END)/float(ASTRA_SHAFT_SAMPLES);
```

`Astra/shaders/global/water/light_shafts.glsl:13`
```glsl
const float WATER_SHAFT_MAX_DISTANCE = 128.0;
```

光束只在特定条件下编译/调度：

`Astra/shaders/lib/settings.glsl:779`
```glsl
    #define ASTRA_UNDERWATER_SHAFTS
```

`Astra/shaders/lib/settings.glsl:778`
```glsl
#if !defined DIMENSION_NETHER && !defined DIMENSION_END && UNDERWATER_SHAFT_STRENGTH > 0
```

`Astra/shaders/program/itt_water_normal_cache.fsh:18`
```glsl
    if (isEyeInWater != 1) discard;
```

### 5.8 水面状态扫描：复合 pass 每帧 12×20 = 240 次 texelFetch

`Astra/shaders/program/water_state.fsh:43`
```glsl
    for (int y = 0; y < 12; ++y) {
```

`Astra/shaders/program/water_state.fsh:44`
```glsl
        for (int x = 0; x < 20; ++x) {
```

`Astra/shaders/program/water_state.fsh:45`
```glsl
            vec2 uv = (vec2(x,y) + 0.5) / vec2(20.0,12.0);
```

### 5.9 水体高度的打包精度

`Astra/shaders/global/water/medium_state.glsl:19`
```glsl
    float q = clamp(floor((worldY + 1024.0) * 15.9375 + 0.5), 0.0, 65279.0);
```

`Astra/shaders/global/water/medium_state.glsl:24`
```glsl
    return (q.x * 256.0 + q.y) / 15.9375 - 1024.0;
```

### 5.10 已退休的水历史模块

`Astra/shaders/global/water/temporal.glsl:4`
```glsl
// RETIRED: no active include or ASTRA_WATER_TEMPORAL definition. Its historical
```

`Astra/shaders/global/water/temporal.glsl:36`
```glsl
// INACTIVE: the geometry-stage self-read/write used here has no composite
```

---


## 6. 光照与颜色：光源来源、加权、色调映射链顺序

### 6.1 三个光源的入口

| 光源 | 产生处 | 原文出处 |
|---|---|---|
| 太阳 | `astra_direct_light()` 的 sun 支 | `astraSunPalette * (SUNLIGHT_STRENGTH * 0.01)` |
| 月亮 | 同函数 moon 支 | `astraMoonPalette * (MOONLIGHT_STRENGTH * 0.0046) * ASTRA_TINT_MOON` |
| 天空环境 | `astra_sky_ambient()` | CPU 侧 `astraAmbientPalette` 乘三个增益 |
| 方块光 | `local_light_components()` | `pow4(blockLight) * (BLOCKLIGHT_STRENGTH * 0.01)` |
| 手持光 | `held_light_intensity()` | 四次幂的预计算版本 |

`Astra/shaders/global/dimension/overworld.glsl:73`
```glsl
        return astraSunPalette * (SUNLIGHT_STRENGTH * 0.01)
```

`Astra/shaders/global/dimension/overworld.glsl:84`
```glsl
    vec3 moon = astraMoonPalette * (MOONLIGHT_STRENGTH * 0.0046) * ASTRA_TINT_MOON;
```

`Astra/shaders/global/dimension/overworld.glsl:38`
```glsl
    return astraAmbientPalette * ASTRA_TINT_AMBIENT * ASTRA_STYLE_AMBIENT
```

`Astra/shaders/global/lighting/blocklight.glsl:106`
```glsl
	float blockLightIntensity = pow4(blockLight) * (BLOCKLIGHT_STRENGTH * 0.01);
```

`Astra/shaders/global/lighting/blocklight.glsl:84`
```glsl
    float distanceTerm = 1.0 + dot(toLight,toLight)/20.25;
```

### 6.2 环境光的方向性加权（"仿原版"0.67 + 0.33·N.y）

`Astra/shaders/global/lighting/diffuse.glsl:99`
```glsl
	return 0.67 + worldNormalY * 0.33;
```

`Astra/shaders/global/lighting/diffuse.glsl:109`
```glsl
	float skyLight = skyLightStrength * mix(0.25, 1.0, skyLightStrength);
```

`Astra/shaders/global/lighting/diffuse.glsl:110`
```glsl
	return ambientStrength * (MIN_AMBIENT_COLOR + skyLight * skyAmbient * (SKYLIGHT_STRENGTH * 0.01));
```

### 6.3 直接光的 facing 曲线（不是 Lambert）

`Astra/shaders/global/lighting/diffuse.glsl:169`
```glsl
		directLightStrength = smoothstep(-0.05, 0.05, ndotl);
```

`Astra/shaders/global/lighting/diffuse.glsl:172`
```glsl
        float highSun = astraSurfaceTimeWeights.z;
```

`Astra/shaders/global/lighting/diffuse.glsl:191`
```glsl
            directLightStrength *= mix(grazing, 1.0, highSun);
```

### 6.4 方块光的日光压制

`Astra/shaders/global/lighting/blocklight.glsl:116`
```glsl
		    blockLightIntensity *= 1.0 - sqrt(skyLight) * blocklightSuppression;
```

`Astra/shaders/global/lighting/blocklight.glsl:119`
```glsl
		    float heldLightSkyLight = sqrt(max(skyLight, heldLightSuppression));
```

`Astra/shaders/global/lighting/blocklight.glsl:129`
```glsl
        return BLOCKLIGHT_COLOR * min(1.0, components.x);
```

### 6.5 各光源在 composer 里的相加顺序

`diffuse_lighting()` 依次：环境天光 →（可选方向天光）→ 夜景折减 → 本地光（方块+手持）→ 闪电 → 直接光；最后乘 albedo。

`Astra/shaders/global/lighting/diffuse.glsl:502`
```glsl
	vec3 lighting = ambient_sky_lighting(max(ambientSkyLight, params.nightVision), ambientStr, params.skyAmbient);
```

`Astra/shaders/global/lighting/diffuse.glsl:579`
```glsl
	lighting += astra_local_light_radiance(localComponents);
```

`Astra/shaders/global/lighting/diffuse.glsl:583`
```glsl
		lighting += lightning_point_light(playerPos, worldNormal, skyLight, params.lightningBolt);
```

`Astra/shaders/global/lighting/diffuse.glsl:609`
```glsl
	directRadiance = surfaceColor * direct * params.directLightSurface;
```

`Astra/shaders/global/lighting/diffuse.glsl:616`
```glsl
    return surfaceColor * lighting + directRadiance;
```

### 6.6 色调映射链顺序（**这是完整顺序**）

源码注释就是唯一权威：

`Astra/shaders/global/post/grading.glsl:55`
```glsl
//   colortex0 -> apply_auto_exposure (optional) -> apply_exposure
```

`Astra/shaders/global/post/grading.glsl:56`
```glsl
//             -> apply_scene_grading -> tonemap
```

`Astra/shaders/global/post/grading.glsl:57`
```glsl
//             -> sRGB encode -> apply_grading
```

实际调用点（display.fsh）：

`Astra/shaders/program/display.fsh:272`
```glsl
    vec3 displayHDR = ordinaryWater ? hdr*1.6 : display_air_hdr(hdr);
```

`Astra/shaders/program/display.fsh:273`
```glsl
    vec3 displayLinear = apply_tonemap(apply_scene_grading(apply_exposure(displayHDR)));
```

`Astra/shaders/program/display.fsh:294`
```glsl
    vec3 displayColor = srgb_encode(displayLinear);
```

`Astra/shaders/program/display.fsh:295`
```glsl
    displayColor = apply_grading(displayColor);
```

`Astra/shaders/program/display.fsh:296`
```glsl
    displayColor = apply_vignette(displayColor, texcoord);
```

自动曝光增益在**线性域**、**只走空气支**：

`Astra/shaders/program/display.fsh:99`
```glsl
    hdr *= displayExposureGain;
```

`Astra/shaders/program/display.fsh:97`
```glsl
    hdr = astra_purkinje(hdr);
```

### 6.7 色调映射算子与选择

`Astra/shaders/lib/tonemap.glsl:227`
```glsl
vec3 apply_tonemap(vec3 x) {
```

`Astra/shaders/lib/tonemap.glsl:229`
```glsl
    #if TONEMAP_OPERATOR == TONEMAP_UCHIMURA
```

`Astra/shaders/lib/tonemap.glsl:231`
```glsl
    return astra_natural_uchimura(x);
```

`Astra/shaders/lib/tonemap.glsl:235`
```glsl
    #elif TONEMAP_OPERATOR == TONEMAP_AGX
```

末地走单独的天空曲线（区分天空像素与前景像素）：

`Astra/shaders/program/display.fsh:277`
```glsl
    vec3 displayLinear=endSceneDepth>=0.999999
```

`Astra/shaders/program/display.fsh:278`
```glsl
        ? astra_end_sky_tonemap(exposed) : apply_tonemap(exposed);
```

### 6.8 自动曝光：64 个采样点，1 texel 历史

`Astra/shaders/global/post/exposure.glsl:36`
```glsl
const int   AE_GRID           = 8;
```

`Astra/shaders/global/post/exposure.glsl:95`
```glsl
	for (int i = 0; i < AE_GRID * AE_GRID; ++i) {
```

`Astra/shaders/global/post/exposure.glsl:109`
```glsl
	return clamp(AE_KEY / max(avgLum, AE_FLOOR), AE_MIN_GAIN, AE_MAX_GAIN);
```

`Astra/shaders/global/post/exposure.glsl:57`
```glsl
const float AE_RATE_FAST      = 2.5;
```

`Astra/shaders/global/post/exposure.glsl:58`
```glsl
const float AE_RATE_SLOW      = 0.5;
```

`Astra/shaders/shaders.properties:371`
```glsl
program.composite5.enabled=AUTO_EXPOSURE
```

---


## 7. 体积雾 / 散射 / 体积光：分辨率、采样数、调度条件

### 7.1 体积雾：半分辨率射线步进，步数按质量 12 / 24 / 48

`Astra/shaders/lib/settings.glsl:245`
```glsl
#define VOLUME_FOG_QUALITY 0 // [0 1 2]
```

`Astra/shaders/global/atmosphere/volume_fog.glsl:33`
```glsl
#define ASTRA_VOLUME_STEPS 12
```

`Astra/shaders/global/atmosphere/volume_fog.glsl:39`
```glsl
#define ASTRA_VOLUME_STEPS 24
```

`Astra/shaders/global/atmosphere/volume_fog.glsl:36`
```glsl
#define ASTRA_VOLUME_STEPS 48
```

`Astra/shaders/global/atmosphere/volume_fog.glsl:40`
```glsl
#define ASTRA_VOLUME_PREFIX_STEPS 8
```

`Astra/shaders/global/atmosphere/volume_fog.glsl:42`
```glsl
#define ASTRA_VOLUME_MAX_DISTANCE 192.0
```

**分辨率**由 properties 决定（质量 0 时 0.25²，否则 0.5²）：

`Astra/shaders/shaders.properties:200`
```glsl
size.buffer.colortex23=0.25 0.25
```

`Astra/shaders/shaders.properties:202`
```glsl
size.buffer.colortex23=0.5 0.5
```

`Astra/shaders/program/volume_main.fsh:25`
```glsl
const int colortex23Format = RGBA16F;
```

**自适应步数**（VOLUME_FOG_ADAPTIVE）：按实际 march 长度按比例缩小，最少 4 步：

`Astra/shaders/global/atmosphere/volume_fog.glsl:152`
```glsl
    sampleCount = min(steps, max(4, int(ceil(float(steps) * marchLength / ASTRA_VOLUME_MAX_DISTANCE))));
```

`Astra/shaders/global/atmosphere/volume_fog.glsl:163`
```glsl
        left *= left;
```

`Astra/shaders/global/atmosphere/volume_fog.glsl:154`
```glsl
	float jitter = bayer8(gl_FragCoord.xy);
```

**每步采一个 shadow 可见性**（可选），关闭时只保留云影：

`Astra/shaders/global/atmosphere/volume_fog.glsl:142`
```glsl
    traceShadows = shadowMap && any(greaterThan(direct, vec3(0.0)));
```

`Astra/shaders/global/atmosphere/volume_fog.glsl:93`
```glsl
	vec3 light = direct * astra_cloud_transmission(playerPos + cameraPosition, lightDirWorld);
```

`Astra/shaders/global/atmosphere/volume_fog.glsl:101`
```glsl
			light *= mix(1.0, shadow_opaque_visibility(sp), coverage);
```

**上行采样**：4 个双线性 tap + 逐 tap 深度/材质一致性检验，全被拒时回退到前缀解析 march：

`Astra/shaders/global/atmosphere/volume_fog.glsl:252`
```glsl
	for (int y = 0; y < 2; ++y) {
```

`Astra/shaders/global/atmosphere/volume_fog.glsl:262`
```glsl
			if (tapDepth >= 0.999999 || referenceZ <= 0.0) continue;
```

`Astra/shaders/global/atmosphere/volume_fog.glsl:280`
```glsl
	if (weights < 1e-4) return astra_volume_prefix_medium(playerPos);
```

**相位函数**明确是单个 HG 叶瓣，g = 0.60：

`Astra/shaders/global/atmosphere/volume_fog.glsl:51`
```glsl
#define ASTRA_VOLUME_PHASE_G 0.60
```

`Astra/shaders/global/atmosphere/volume_fog.glsl:70`
```glsl
	return (1.0 - g2) / (12.5663706 * base * sqrt(base));
```

### 7.2 体积雾开关与前置条件

`Astra/shaders/lib/settings.glsl:742`
```glsl
    #define ASTRA_VOLUME_FOG
```

`Astra/shaders/lib/settings.glsl:741`
```glsl
#if !defined DIMENSION_NETHER && !defined DIMENSION_END && defined VOLUMETRIC_FOG && VOLUME_FOG_DENSITY > 0
```

`Astra/shaders/program/volume_main.fsh:32`
```glsl
    if ((isEyeInWater == 0 || water_is_thin_sheet()) && blindness <= 0.0001 && VOLUME_FOG_DENSITY > 0) {
```

**[源码]** 体积雾一开，屏幕空间光轴立刻让位（避免同一段空气被散射两次）：

`Astra/shaders/global/post/godrays.glsl:148`
```glsl
	#ifdef ASTRA_VOLUME_FOG
```

`Astra/shaders/global/post/godrays.glsl:126`
```glsl
		return 0.0;
```

### 7.3 空气光轴（composite2 / scattering.fsh）：半或四分之一分辨率，8 步

**分辨率**（properties 的条件链，0.25² / 0.5² / 1²）：

`Astra/shaders/shaders.properties:22`
```glsl
size.buffer.colortex1=0.25 0.25
```

`Astra/shaders/shaders.properties:24`
```glsl
size.buffer.colortex1=0.5 0.5
```

`Astra/shaders/program/scattering.fsh:99`
```glsl
const int colortex1Format=RG16F;
```

`Astra/shaders/program/scattering.fsh:94`
```glsl
const int colortex1Format=RGBA16F;
```

**每像素 8 次深度采样 + Bayer 抖动起点**：

`Astra/shaders/global/post/godrays.glsl:157`
```glsl
	const float NUM_SAMPLES = 8.0;
```

`Astra/shaders/global/post/godrays.glsl:158`
```glsl
	const float DENSITY = 0.83;
```

`Astra/shaders/global/post/godrays.glsl:167`
```glsl
	texCoord += deltaTexCoord * 1.5 * bayer8(gl_FragCoord.xy);
```

`Astra/shaders/program/scattering.fsh:152`
```glsl
	float density = godrays_density(texcoord, lightScreenPos);
```

**太阳遮挡探测**：49 次深度读取，**每帧一次**（只在 texel (0,0)）：

`Astra/shaders/program/scattering.fsh:65`
```glsl
	const int PROBE_TAPS = 7;
```

`Astra/shaders/program/scattering.fsh:162`
```glsl
            sourceVisibility = godrays_sun_visibility(lightScreenPos);
```

`Astra/shaders/program/scattering.fsh:159`
```glsl
		if (all(lessThan(gl_FragCoord.xy, vec2(1.0)))) {
```

### 7.4 世界空间树影光轴（ASTRA_TREE_SHAFTS）：0.25² 或 0.5²，8 或 12 步

`Astra/shaders/lib/settings.glsl:745`
```glsl
    #define ASTRA_TREE_SHAFTS
```

`Astra/shaders/global/post/godrays.glsl:58`
```glsl
    const int samples = 8;
```

`Astra/shaders/global/post/godrays.glsl:60`
```glsl
    const int samples = 12;
```

`Astra/shaders/global/post/godrays.glsl:46`
```glsl
    float reach = min(distanceBlocks,48.0);
```

`Astra/shaders/global/post/godrays.glsl:83`
```glsl
    integral *= astra_cloud_transmission(cameraPosition+origin+ray*(0.5*reach),light);
```

### 7.5 三者的调度互斥关系

| 效果 | 条件 | 分辨率 | 每像素采样 |
|---|---|---|---|
| 体积雾 | VOLUMETRIC_FOG + 密度 > 0，仅主世界 | 0.25²/0.5² | 12/24/48 步（自适应可降到 4） |
| 屏幕光轴 | GODRAYS 且**无**体积雾 | 0.25²/0.5² | 8 步 |
| 树影光轴 | GODRAYS 且**有** SHADOWS 且**无**体积雾 | 0.25²/0.5² | 8 步（预算档）/12 步 |
| 水下光束 | UNDERWATER_LIGHT_SHAFTS + SHADOWS + 主世界 | 0.25²/0.5²（样本 <7 时 0.25²） | 7 区间 × 4 节点 = 28 |

`Astra/shaders/shaders.properties:18`
```glsl
#if defined GODRAYS && GODRAYS_STRENGTH > 0 && (!defined VOLUMETRIC_FOG || VOLUME_FOG_DENSITY <= 0)
```

`Astra/shaders/shaders.properties:27`
```glsl
#if UNDERWATER_SHAFT_SAMPLES < 7
```

`Astra/shaders/shaders.properties:22`
```glsl
size.buffer.colortex1=0.25 0.25
```

---


## 8. 下界：nether_light 的 dispatch、64³ 体素与读取次数

### 8.1 三次资源：占用 + 两张同帧传播图

`Astra/shaders/shaders.properties:946`
```glsl
image.astraVoxelImage=astraVoxelSampler red_integer r32ui unsigned_int true false 64 64 64
```

`Astra/shaders/shaders.properties:949`
```glsl
image.astraLightA=astraLightSamplerA rgba rgba16f half_float false false 64 64 64
```

`Astra/shaders/shaders.properties:950`
```glsl
image.astraLightB=astraLightSamplerB rgba rgba16f half_float false false 64 64 64
```

`Astra/shaders/shaders.properties:948`
```glsl
image.astraNetherSourceTiles=astraNetherSourceSampler red_integer r32ui unsigned_int true false 2 1
```

`Astra/shaders/lib/nether_voxel_grid.glsl:35`
```glsl
#define ASTRA_NETHER_VOXEL_SIZE 64              // cells / texels per axis
```

`Astra/shaders/lib/nether_voxel_grid.glsl:36`
```glsl
#define ASTRA_NETHER_VOXEL_HALF_EXTENT 32.0     // blocks from the volume centre to a face
```

### 8.2 **9 次 dispatch**（step 0 建源 + step 1..8 扩散），每步 8×8×8 工作组 × 8³ invocation

`Astra/shaders/program/nether_light.csh:15`
```glsl
layout(local_size_x=8,local_size_y=8,local_size_z=8) in;
```

`Astra/shaders/program/nether_light.csh:16`
```glsl
const ivec3 workGroups=ivec3(8,8,8);
```

`Astra/shaders/world-1/shadowcomp.csh:2`
```glsl
#define ASTRA_LIGHT_STEP 0
```

`Astra/shaders/world-1/shadowcomp8.csh:2`
```glsl
#define ASTRA_LIGHT_STEP 8  // Iris ProgramSet loads numbered shadowcomp stages
```

**[推断]** 8×8×8 工作组 × 每组 512 个 invocation = 每次 dispatch 覆盖 64³ = 262144 个体素；9 次 dispatch 合计约 236 万次 invocation/帧。

九道阶段必须在 properties 里显式开关（源码说明了原因）：

`Astra/shaders/shaders.properties:902`
```glsl
# The nine stages have to be switched off from here rather than from inside the shader:
```

`Astra/shaders/shaders.properties:918`
```glsl
program.world-1/shadowcomp.enabled=true
```

`Astra/shaders/shaders.properties:926`
```glsl
program.world-1/shadowcomp8.enabled=true
```

`Astra/shaders/shaders.properties:416`
```glsl
#if defined SHADOWS && defined NETHER_VOXEL_LIGHT && BLOCKLIGHT_STRENGTH > 0
```

### 8.3 采样侧读取次数

**传播步（step ≥ 1）**：每个空体素读 6 个邻居（6 次 texelFetch），取最大值后乘 0.72 衰减：

`Astra/shaders/program/nether_light.csh:108`
```glsl
        const ivec3 dirs[6]=ivec3[6](ivec3(1,0,0),ivec3(-1,0,0),ivec3(0,1,0),ivec3(0,-1,0),ivec3(0,0,1),ivec3(0,0,-1));
```

`Astra/shaders/program/nether_light.csh:110`
```glsl
        for(int i=0;i<6;i++) {
```

`Astra/shaders/program/nether_light.csh:122`
```glsl
        color=max(color,incoming*0.72);
```

step 0 只写源，并做一次工作组内归约到 16³ tile 位图：

`Astra/shaders/program/nether_light.csh:93`
```glsl
    vec3 color=emission(id)*2.0;
```

`Astra/shaders/program/nether_light.csh:97`
```glsl
    if (gl_LocalInvocationIndex == 0u && astraGroupHasSource != 0u) {
```

`Astra/shaders/program/nether_light.csh:100`
```glsl
        imageAtomicOr(astraNetherSourceTiles, ivec2(int(index >> 5), 0), 1u << (index & 31u));
```

**显示侧（每像素）**：1 次三线性采样；开 `DIRECTIONAL_LOCAL_LIGHTING` 时再 6 次单侧差分采样 = **最多 7 次金属采样/像素**：

`Astra/shaders/global/dimension/nether_colored_light.glsl:23`
```glsl
    vec3 color=textureLod(astraLightSamplerA,astra_nether_voxel_normalized(p),0.0).rgb;
```

`Astra/shaders/global/dimension/nether_colored_light.glsl:45`
```glsl
    vec3 positive=vec3(dot(textureLod(astraLightSamplerA,uv+dx,0.0).rgb,luma),
```

`Astra/shaders/global/dimension/nether_colored_light.glsl:48`
```glsl
    vec3 negative=vec3(dot(textureLod(astraLightSamplerA,uv-dx,0.0).rgb,luma),
```

`Astra/shaders/global/dimension/nether_colored_light.glsl:65`
```glsl
        return 1.0+0.20*facing*confidence;
```

### 8.4 体素占用由投射阶段写入

`Astra/shaders/program/shadow.vsh:69`
```glsl
    vec3 center = (shadowModelViewInverse * gl_ModelViewMatrix * vec4(gl_Vertex.xyz + at_midBlock/64.0,1.0)).xyz;
```

`Astra/shaders/program/shadow.vsh:70`
```glsl
    ivec3 cell = astra_nether_voxel_cell(center, fract(cameraPosition));
```

`Astra/shaders/program/shadow.vsh:91`
```glsl
    imageAtomicMax(astraVoxelImage,cell,astra_voxel_encode(kind,solid));
```

`Astra/shaders/program/shadow.vsh:109`
```glsl
    gl_Position = vec4(0.0, 0.0, 2.0, 1.0);
```

### 8.5 显示侧的合成方式：替换 75% 的方块光

`Astra/shaders/global/dimension/nether.glsl:172`
```glsl
    #if defined NETHER_VOXEL_LIGHT && defined SHADOWS && BLOCKLIGHT_STRENGTH > 0
```

`Astra/shaders/global/dimension/nether.glsl:178`
```glsl
            vec3 voxel = astra_nether_colored_light(playerPos, worldNormal);
```

`Astra/shaders/global/dimension/nether.glsl:194`
```glsl
            blockLighting = mix(blockLighting,coloredLight,coverage*0.75);
```

### 8.6 已废弃（明确写为不活动）的下界体积模块

`Astra/shaders/shaders.properties:886`
```glsl
# The legacy nether_volume.glsl module is inactive; no active pass samples its noise.
```

---


## 9. 末地：黑洞 / 吸积盘 / 星场的入口与烘焙纹理消费者

### 9.1 入口链

`program/scene.glsl` 在 `DIMENSION_END` 下 include `end.glsl`；`end_sky()` 调 `astra_end_blackhole()`：

`Astra/shaders/global/dimension/end.glsl:27`
```glsl
    astra_end_blackhole(sky,normalize(dir),end_light_direction());
```

`Astra/shaders/global/dimension/end_blackhole.glsl:106`
```glsl
void astra_end_blackhole(inout vec3 color,vec3 originalRay,vec3 unusedLightDirection) {
```

天体系统本身（含盘、等离子层、光子环、背景）在 `end_blackhole_system()`；背对光源方向的射线直接跳过并只返回背景：

`Astra/shaders/global/dimension/end_blackhole.glsl:31`
```glsl
    if(dot(ray,end_light_direction())<=0.04) return end_background(ray,cone);
```

`Astra/shaders/global/dimension/end_blackhole.glsl:35`
```glsl
    vec2 q=end_kerr_screen(ray,kerrBasis);
```

`Astra/shaders/global/dimension/end_blackhole.glsl:40`
```glsl
    if(r>7.0) return end_background(ray,cone);
```

### 9.2 **没有任何逐帧光线追踪**：盘面来自离线烘焙 atlas

源码注释写得很直接：

`Astra/shaders/global/dimension/end_blackhole.glsl:22`
```glsl
// Static light-path transfer plus animated emission: runtime contains no light-ray march.
```

`Astra/shaders/global/dimension/end_kerr.glsl:4`
```glsl
// The atlas is produced by qa/tools/build_end_transfer.py, never traced per frame.
```

### 9.3 烘焙纹理与消费者

| 纹理 | properties 声明 | 消费者 |
|---|---|---|
| `astraEndTransfer` | customTexture.astraEndTransfer | `end_disc_transfer_impact()` 的四角 texelFetch |
| `astraEndTransferMeta` | customTexture.astraEndTransferMeta | `end_emission_frame_impact()` 的 textureLod |
| `astraEndFlow` | customTexture.astraEndFlow | `end_flow_sample()`、`end_plasma` 的细丝 |
| `astraEndFlowMips` | customTexture.astraEndFlowMips | `end_flow_mip_level()`（手工 mip 表） |

`Astra/shaders/shaders.properties:596`
```glsl
customTexture.astraEndTransfer=textures/astra-end-transfer.png
```

`Astra/shaders/shaders.properties:599`
```glsl
customTexture.astraEndFlowMips=textures/astra-end-flow-mips.png
```

`Astra/shaders/global/dimension/end_kerr.glsl:49`
```glsl
        coordinates[i]=end_decode_transfer(texelFetch(astraEndTransfer,cell+ivec2(i&1,i>>1),0));
```

`Astra/shaders/global/dimension/end_kerr.glsl:87`
```glsl
    vec4 meta=textureLod(astraEndTransferMeta,clamp(uv,vec2(0.0005),vec2(0.9995)),0.0);
```

`Astra/shaders/global/dimension/end_kerr.glsl:231`
```glsl
        vec4 lower=textureLod(astraEndFlow,uv,0.0);
```

`Astra/shaders/global/dimension/end_kerr.glsl:225`
```glsl
    return textureLod(astraEndFlowMips,coord,0.0);
```

`Astra/shaders/global/dimension/end_plasma.glsl:36`
```glsl
            float filament=textureLod(astraEndFlow,uv,0.0).a;
```

**[源码]** 每像素盘面查表的读取规模：主图 4 次 texelFetch（四角）+ 元数据 1 次 textureLod；前盘与后盘各一次 → 最多 8 次 texelFetch + 2 次 meta。流场采样按 mip 层数最多 2 次 textureLod/次调用，`end_flow_field()` 调 2 次 → 最多 4 次。

`Astra/shaders/global/dimension/end_blackhole.glsl:51`
```glsl
    vec3 primary=end_disc_transfer_impact(impact,0.0,aa,primaryFootprint);
```

`Astra/shaders/global/dimension/end_blackhole.glsl:75`
```glsl
        vec3 secondary=end_disc_transfer_impact(impact,1.0,aa,secondaryFootprint);
```

`Astra/shaders/global/dimension/end_kerr.glsl:249`
```glsl
    vec4 body=end_flow_sample(parcel*0.30+vec2(0.13,0.47),footprint*0.37);
```

`Astra/shaders/global/dimension/end_kerr.glsl:253`
```glsl
    vec4 detail=end_flow_sample(parcel*1.4+warp+vec2(0.37,0.19),footprint*4.0);
```

### 9.4 星场：GPU 星表 + 逐像素 3×3 单元遍历

星表由 compute 在 **setup 阶段**（不是每帧）生成，写入 colortex31；显示侧每像素查 3 行 × 最多 3 列：

`Astra/shaders/program/end_star_catalogue.csh:7`
```glsl
const ivec3 workGroups = ivec3(151,64,1);
```

`Astra/shaders/program/end_star_rows.csh:10`
```glsl
const ivec3 workGroups=ivec3(1,1,1);
```

`Astra/shaders/world1/setup2.csh:6`
```glsl
const ivec3 workGroups = ivec3(1,1,1);
```

`Astra/shaders/global/dimension/end_system.glsl:67`
```glsl
    for(int y=-1;y<=1;y++) {
```

`Astra/shaders/global/dimension/end_system.glsl:70`
```glsl
        vec3 rowData=end_star_row(row);
```

`Astra/shaders/global/dimension/end_system.glsl:84`
```glsl
            vec4 presence=end_star_presence(c.x,rowData.z);
```

**[推断]** setup2.csh 是"空 dispatch + 1 个 invocation"，注释说它的作用只是让 Iris 在 dispatch 前插入屏障，使星表写入对片元采样器可见。

`Astra/shaders/world1/setup2.csh:2`
```glsl
// Iris 1.11.2 dispatch inserts its host image/texture barrier BEFORE dispatch.
```

`Astra/shaders/world1/setup2.csh:4`
```glsl
// visible to fragment samplers. No recurring per-frame initialization dispatch.
```

### 9.5 末地天空写入 colortex9，由 deferred 消费

`Astra/shaders/program/end_sky_buffer.fsh:12`
```glsl
/* RENDERTARGETS: 9 */
```

`Astra/shaders/program/end_sky_buffer.fsh:20`
```glsl
    if (skyDepth < 0.999999) { gl_FragData[0] = vec4(0.0); return; }
```

`Astra/shaders/program/end_sky_buffer.fsh:22`
```glsl
    gl_FragData[0] = vec4(color, end_star_visibility);
```

`Astra/shaders/program/deferred.fsh:389`
```glsl
        vec4 sky = texelFetch(colortex9, ivec2(gl_FragCoord.xy), 0);
```

### 9.6 盘面自转速率

`Astra/shaders/global/dimension/end_kerr.glsl:98`
```glsl
float end_orbital_rate(float r) {
```

`Astra/shaders/global/dimension/end_kerr.glsl:102`
```glsl
    return 0.0475/(x*sqrt(x)+0.18*END_KERR_SPIN);
```

---


## 10. 两类清单

### 10.1 已确认存在（有源码入口、有调度点）

| 能力 | 确认依据（文件:行） |
|---|---|
| 按维度切 pass（world-1 / world1 覆盖根目录入口） | `world1/deferred.fsh`、`world-1/deferred.fsh` 各自 `#define DIMENSION_END` / `DIMENSION_NETHER` 后 include 主体 |
| 阴影贴图投射 + 四角配对过滤 + 彩色阴影 | 第 3 节全部条目 |
| 水面 SSR（12/20/40 预算，2 级细化） | 第 5.3 节 |
| 屏幕空间折射（1 像素配对） | 第 5.4 节 |
| Beer-Lambert 水体吸收 + 单次散射 | 第 5.1 节 |
| 水下 Gauss-Legendre 体积光束 | 第 5.7 节 |
| 平面云（4/6/16/512 步分档）+ 屏幕云缓存 | 第 4.3–4.7 节 |
| 云时域历史（24/25 + 距离/帧号/视口三重拒绝） | 第 4.8–4.12 节 |
| 空气 godrays（8 步）与树影光轴（8/12 步） | 第 7.3–7.4 节 |
| 体积雾（12/24/48 步，0.25²/0.5²） | 第 7.1 节 |
| TAA（YCoCg 方差裁剪 1.25σ + 反应性掩码） | `taa_resolve.fsh` |
| SMAA / FXAA | `program/final.fsh`、`program/smaa_edge.fsh`、`smaa_weights.fsh` |
| 自动曝光（64 tap，1 texel 历史，快慢不对称） | 第 6.8 节 |
| 完整色调映射链 | 第 6.6 节 |
| 下界 64³ 体素彩色光（9 次 dispatch） | 第 8 节 |
| 末地烘焙光路 atlas + 星表 | 第 9 节 |

TAA 方差裁剪原文：

`Astra/shaders/program/taa_resolve.fsh:155`
```glsl
                    vec3 sampleColor = taa_ycocg(max(texelFetch(colortex0,p,0).rgb,vec3(0.0)));
```

`Astra/shaders/program/taa_resolve.fsh:163`
```glsl
                lo = max(lo,mean-1.25*sigma);
```

`Astra/shaders/program/taa_resolve.fsh:164`
```glsl
                hi = min(hi,mean+1.25*sigma);
```

`Astra/shaders/program/taa_resolve.fsh:172`
```glsl
                float weight = mix(0.92, 0.70, motion) * (1.0 - reactive) * h.a
```

### 10.2 未找到入口（明确说"没找到"，并列出检索过的符号与路径）

以下条目我用 `grep` 在 `Astra/shaders/` 全目录检索，**命中 0 条**，因此在本工作区源码中找不到入口：

| 项目 | 检索过的模式 | 命中 |
|---|---|---|
| PCSS / 可变半影阴影 | `pcss`、`PCSS` | 0 |
| 接触阴影（contact shadow） | `contact_shadow`、`ContactShadow`、`contact shadow` | 0 |
| 光线追踪阴影 | `raytraced_shadow`、`rayTracedShadow`、`raytraced shadow` | 0 |
| 级联阴影（CSM） | `cascade`、`CSM` | 0 |
| 可变着色率 / VRS | `variable.?rate`、`VRS` | 0 |
| 超分（DLSS/FSR） | `DLSS`、`FSR`、`upscal` | 0 |
| 屏幕空间阴影 | `screen.?space.?shadow`、`SSShadow` | 0 |

另外，以下模块**文件存在但没有任何 pass 引用**（不是"没有此功能"，而是"代码在、不执行"）：

| 文件 | 状态 | 依据 |
|---|---|---|
| `global/water/temporal.glsl` | 完全无 include | 文件头写 `RETIRED: no active include`；`grep "water/temporal.glsl"` 只命中它自己 |
| `global/dimension/nether_volume.glsl` | 无 include | properties 注释 `The legacy nether_volume.glsl module is inactive`；`grep "nether_volume"` 命中 1 条（就是这条注释） |
| `program/prepare4.fsh` | `program.prepare4.enabled=false` | properties 第 244 行 |
| `voxy_opaque.glsl` / `voxy_translucent.glsl` | 空实现（TODO 占位） | `// TODO(C5)` 后只有空函数体 |

三条原文：

`Astra/shaders/global/water/temporal.glsl:4`
```glsl
// RETIRED: no active include or ASTRA_WATER_TEMPORAL definition. Its historical
```

`Astra/shaders/shaders.properties:886`
```glsl
# The legacy nether_volume.glsl module is inactive; no active pass samples its noise.
```

`Astra/shaders/shaders.properties:244`
```glsl
program.prepare4.enabled=false
```

`Astra/shaders/voxy_opaque.glsl:4`
```glsl
	// TODO(C5)
```

**[未验证]** 上表"文件存在但不执行"只表示**当前源码没有 include / enabled 路径**；如果 Iris 在某些版本下对 folder-gate 有额外回退规则，行为可能与源码字面不同。properties 自己就写了这一不确定性：

`Astra/shaders/shaders.properties:248`
```glsl
# is not confirmed in-game, so keep them rather than gamble on the fallback rule.
```

---

## 11. 附：本次检索范围与方法

- 全量列出 `Astra/shaders/` 下 460 个文件，按后缀筛出 `.fsh / .vsh / .csh / .glsl / .properties / .lang`。
- 逐字读取：全部 `program/*.fsh|vsh|csh` 入口与主体、`global/lighting/*`、`global/water/*`、`global/atmosphere/*`、`global/post/*`、`global/dimension/*`、`lib/*` 中被 include 的模块。
- 机械核对：所有引文都用同一份文件缓存逐行比对过（先定位行号，再逐字比较），没有凭记忆抄写。
- **本轮没有运行游戏、没有抓帧、没有 GPU 计时**。因此笔记中不含任何 FPS、毫秒或百分比收益；所有"成本"只描述"哪类 GPU 工作、多少次采样、多大分辨率、每帧还是每像素"。
