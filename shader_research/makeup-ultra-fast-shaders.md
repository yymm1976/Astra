# MakeUp - Ultra Fast 9.5f 研究报告（Astra 视角）

参考包路径：`reference_shaderpacks/makeup-ultra-fast-shaders/`（下文 MakeUp 侧引用省略此前缀，行号均为包内真实行号）。
Astra 侧引用基于 `Astra/shaders/`。

---

## ① 包概览

- **版本**：9.5f，适配 OptiFine 与 Iris 1.5.1+，宣称覆盖 MC 1.12+ 至 26.x（README.md:5-7、README.md:17）。
- **作者**：Javier Garduño（GitHub: javiergcim/MakeUpUltraFast，README.md:27）。
- **许可证**：**LGPL-3.0-or-later**（LICENSE:1-2 为 "GNU LESSER GENERAL PUBLIC LICENSE Version 3"；每个 .glsl 文件头均带 "Javier Garduño - GNU Lesser General Public License v3.0"，如 lib/config.glsl:4）。README.md:23-30 另给出口头放宽："可无限制使用、可为任何目的修改"，并"请求（非要求）"加署名与官方链接。README 的放宽不能替代 LGPL 的署名/声明义务，但它表明作者明确欢迎拿去做底子——ForDevelopers.EN.md:3-5 更是直接写明"It is my desire that MakeUp can be used as a basis for creating more and better shaders"。
- **体量与风格定位**：全部主 shader 逻辑仅约 4000 行（common/ + lib/ 合计），无 compute、无半分辨率中间缓冲、无 3D 噪声纹理；靠 2D 云纹理、少采样、CPU 预计算 uniform 和 8 个颜色缓冲（colortex0-3 + gaux1-4，见 common/final_fragment.glsl:4-18 的注释表）撑起"1300 万下载的低配高观感"定位。视觉基调由 8 套可选 COLOR_SCHEME 调色板（lib/color_utils.glsl:19-154）与单一 sigmoid 色调映射（lib/tone_maps.glsl:14-19）决定，属于"调色驱动"而非"模拟驱动"。
- **配置哲学**：8 档 profile（no_effects → shadowless_low/medium/high → low → medium → high → extremeplus，shaders.properties:4-11），每档由约 30 个开关组成线性降级链；用户可再在 GUI 里逐项覆写（screen 布局 shaders.properties:50-66）。

## ② 架构与特性清单

流水线：shadow（可整体关闭）→ prepare → gbuffers → deferred → composite → composite1 → composite2 → final。顶点/片元逻辑集中在 `common/`，`lib/` 为函数库，`src/` 为插入 main 的代码片段（组织方式见 ForDevelopers.EN.md:9-34）。

### 大气 / 雾 / 云
- **雾 = 逐像素天空梯度纹理**：prepare 阶段把"天顶→地平线"解析梯度写进 gaux4（prepare.fsh:17 `#define SET_FOG_COLOR`；common/prepare_fragment.glsl:45-53；src/writebuffers.glsl:9-13 写 DRAWBUFFERS:17）。每个 gbuffers 片元用一条 pow 曲线向 gaux4 采样到的"该像素的天空色"混合（src/finalcolor.glsl:10-33）。
- **雾曲线**：`frogAdjust = pow(clamp(gl_FogFragCoord/far,0,1)*fogIntensityCoeff, fogDensityCoeff)`（src/fog_vertex.glsl:27-31），密度系数 = 时段混合密度 × FOG_ADJUST（src/fog_vertex.glsl:4-14；lib/color_utils.glsl:172-179），雨天向 1 收紧（src/fog_vertex.glsl:29）。全在顶点算，片元只做一次 mix。
- **天空色在 XYZ 空间插值**：地平线/天顶色先 rgbToXyz、雨天向灰蓝混合（src/low_sky.glsl:5-17），插值后再 xyzToRgb（common/prepare_fragment.glsl:49-53），让 RGB 空间的梯度过渡更顺眼。
- **水下**：吸收是一条 pow（common/composite_fragment.glsl:109-114）；水下天空按仰角向水色染（common/deferred_fragment.glsl:189-194）；熔岩/雪用 isEyeInWater 2/3 各一条 mix（common/composite_fragment.glsl:115-117、214-225）。
- **下界雾**：距离开关 + `NETHER_SIGHT = min(far/2, 96)`（shaders.properties:48；lib/config.glsl:144-148；src/fog_vertex.glsl:34-55）。
- **平面体积云**：单 2D 512px 纹理（shaders.properties:35-41），视线与 [CLOUD_PLANE 319, CLOUD_PLANE_SUP] 云板求交后按 CLOUD_STEPS_AVG（默认 10）步采样（lib/volumetric_clouds.glsl:18-45），厚度即"上下表面差"，云边用 blur 带软化（lib/volumetric_clouds.glsl:60-71），V_CLOUDS=2 加第二张同纹采样做形态演化（lib/volumetric_clouds.glsl:47-50）。只在天空像素跑（common/deferred_fragment.glsl:125-146）；水面反射用半步数复用同一函数（common/water_blocks_fragment.glsl:190-192）。vanilla 云作为 V_CLOUDS=0 的回退（shaders.properties:26-28）。

### 水体
- **两档反射**：SSR_TYPE=0"翻转图"——把反射向量投影一次直接采样（lib/water.glsl:177-185，带上下边界 fade 与屏幕外折叠 lib/water.glsl:187-195）；SSR_TYPE=1 指数步进 10 步 + 二分收敛的 fastRaymarch（lib/water.glsl:9-97，步数 lib/config.glsl:151）。
- **法线波**：noisetex 三层 UV 滚动相加（lib/water.glsl:113-130），强度受 WATER_TURBULENCE 与雨天衰减（lib/water.glsl:127）。
- **折射**：屏幕 UV 按波法线偏移 0.075/(1+dist*0.4)，背景/水面深度差平方成吸收（lib/water.glsl:132-160）。
- **菲涅尔与天空反射色**：`fresnel = squarePow(1+NdotE)`（common/water_blocks_fragment.glsl:175-176）；反射底色直接用天顶/地平线色按仰角插值（common/water_blocks_fragment.glsl:182-188）。
- **解析太阳高光**：`smoothstep(0.995,1.0,dot)` × 天光可见度 × 雨衰减（lib/water.glsl:99-111，叠加于 lib/water.glsl:229-239）。
- **水下吸收滑条** WATER_ABSORPTION（lib/config.glsl:67）与水面染色 WATER_COLOR_SOURCE（common/water_blocks_fragment.glsl:246-250）。
- **玻璃**：独立 cristal_shader/cristal_reflection_calc 路径（lib/water.glsl:245-325），调用点 common/water_blocks_fragment.glsl:302-304。

### 阴影与光照
- **shadow pass 可整体关闭**：`program.shadow.enabled=SHADOW_CASTING`（shaders.properties:44-47）。关掉后用"假阴影"兜底：直射光强度 × `visibleSky^10`（pow 用连乘近似，src/light_vertex.glsl:115-129）。
- **分辨率/距离配对表**：SHADOW_DISTANCE_SLIDER × SHADOW_QTY_SLIDER 3×3 组合直接映射 shadowMapResolution 300→4080（lib/config.glsl:202-294），并配 SHADOW_FIX_FACTOR/SHADOW_DIST 扭曲参数；VOL_LIGHT=2 时才放开 shadowDistanceRenderMul=-1（lib/config.glsl:296-300）。
- **软阴影**：SHADOW_TYPE=1 用 dither 驱动的 4 采样旋转圆盘（lib/shadow_frag.glsl:12-31）；SHADOW_TYPE=0 退化为单采样硬件 shadow2D（lib/shadow_frag.glsl:10-11）。
- **彩色阴影**：shadowtex0/shadowtex1/shadowcolor0 三图 4 采样，逐样本判"半透明遮挡"（lib/shadow_frag.glsl:38-152），与体积光共用（common/composite_fragment.glsl:181-186）。
- **SHADOW_LOCK 阴影纹素吸附**：世界坐标按 SHADOW_LOCK 档位 floor 到纹素格，消闪烁（lib/config.glsl:204；common/solid_blocks_fragment.glsl:196-209）。
- **直射/环境光色**：dayBlend 三段抛物线混合（lib/day_blend.glsl:1-19），其中 dayMixer/nightMixer/dayNightMix 全部在 shaders.properties 里用 CPU 预计算为 custom uniform（shaders.properties:99-138），着色器零成本取用（用法 src/light_vertex.glsl:54-62）。
- **方块光**：色温 5 档（lib/color_utils.glsl:158-168），烛光曲线 `x*sqrt(x)+sixthPow(1.17x)`（src/light_vertex.glsl:17-29），手灯同曲线复用（src/light_vertex.glsl:20-27）。
- **洞穴最低环境光**：AVOID_DARK_LEVEL 防死黑（src/light_vertex.glsl:97-105；lib/config.glsl:70）。
- **MATERIAL_GLOSS**：按方块/实体 ID 分类（金属/沙/织物，lib/config.glsl:22-24）给一个极廉价的各向同性高光项（common/solid_blocks_fragment.glsl:231-247；lib/material_gloss_fragment.glsl 共 27 行）。
- **AO**：deferred 阶段深度螺旋采样 dbao，默认 5 步、每步正反两点（lib/ao.glsl:6-46），并按距离雾化衰减（common/deferred_fragment.glsl:166-181）；AO=0 时把 vanilla AO 阈值还回 0.7（lib/config.glsl:314-318）。
- **体积光两模式**：VOL_LIGHT=1 深度 godrays——向太阳屏幕位置走 4 步查深度（lib/volumetric_light.glsl:99-115，步数 lib/config.glsl:193）；VOL_LIGHT=2 用 shadow map 指数间隔 6 采样（lib/volumetric_light.glsl:21-52；彩色版 56-93）。强度/雨衰减/昼夜门控在 common/composite_fragment.glsl:138-212。
- **实体特判**：发光实体/闪电/火焰的廉价路径（common/solid_blocks_fragment.glsl:165-183、260-269）。

### 后处理
- **TAA**：16 点"五边形最大化抖动"在 shaders.properties 预计算为 taaOffset uniform（shaders.properties:143-186）；历史用 9 邻域方差凸包裁剪（lib/fast_taa.glsl:7-32），混合因子 `0.99 - smoothstep*0.33` 按冲突度收缩（lib/fast_taa.glsl:130-137），重投影在 composite2 顶点层做（common/composite2_fragment.glsl:58-84，调用 97-107）。无深度/法线拒绝，靠裁剪兜鬼影。
- **自动曝光**：顶点阶段 5 个 mipmap 采样估场景亮度，`exp(-x)*3.03+0.6` 曲线 + 按帧时间自适应（common/composite_vertex.glsl:73-87）。
- **Bloom**：单 pass mipmap 采样——colortex0 开 mipmap，在固定 LOD softLod 上黄金角螺旋 2×BLOOM_SAMPLES 对采（lib/bloom.glsl:7-34；LOD 由视口高度预计算 shaders.properties:224-228）；亮度提取 smoothstep(0.85,1.0)（common/composite_fragment.glsl:227-235）；合成在 composite1（common/composite1_fragment.glsl:65-68）。
- **色调映射**：单一 custom_sigmoid（lib/tone_maps.glsl:14-19），曝光乘法 + sigmoid 在 final（common/final_fragment.glsl:125-126）。
- **AA 链**：AA_TYPE 0-3 = 无 / 仅去噪 / TAA / TAA+FXAA311（lib/config.glsl:58；lib/fxaa.glsl 203 行；调用 common/final_fragment.glsl:119-121）。
- **其余**：CAS 锐化（lib/cas.glsl；common/final_fragment.glsl:100-117）、色差（lib/aberration.glsl）、运动模糊（lib/motion_blur.glsl；common/composite2_fragment.glsl:86-95）、DoF 噪声模糊（lib/blur.glsl；common/composite1_fragment.glsl:61-63）、色盲校正（lib/color_blindness.glsl）。

### 性能技术（降级 / 半分辨率 / 廉价近似）
- **没有半分辨率缓冲**：全管线 8 个缓冲均为全分辨率，成本控制全靠"少 pass、少采样、mipmap 复用、CPU 预计算"。这是它与 Astra（半分辨率 godrays、1/4-1/2 分辨率云网格、compute 体素）最根本的差异。
- **开关树**：8 档 profile 的降级顺序 = 阴影→AO→体积云→Bloom/VOL_LIGHT→彩色阴影→材质光泽→DoF（shaders.properties:4-11），每档同屏特性数严格递增。
- **CPU 预计算 uniform**：pixelSize、dayMixer 系列抛物线、taaOffset 16 点、ditherShift、softLod 全部在 shaders.properties 用 `variable/uniform` 指令算好（shaders.properties:89-96、99-138、143-210、224-228）。
- **mipmap 复用**：colortex1 的 mipmap 同时服务 AO 抖动与 Bloom/DoF（common/composite_fragment.glsl:2；common/composite1_fragment.glsl:4-9），一次 pass 拿多级模糊。
- **pow→sqrt 近似**：云密度 `sqrt(sqrt(x))≈x^0.25`（lib/volumetric_clouds.glsl:89-100）、假阴影 `x^10` 连乘（src/light_vertex.glsl:119-123）。
- **dither 家族策略**：固定/随 TAA 旋转（shifted 前缀）/eclectic 哈希扰动多套变体，并立规矩"同 pass 多效果共享一次 dither 计算"（lib/dither.glsl:1-27）。
- ** vanilla 资产回退**：云退回 vanilla（shaders.properties:26-28）、水退回 VANILLA_WATER、资源包水色可选源（lib/config.glsl:69、83）。
- **DH/Voxy 兼容**：DH 深度双源 + 过渡带 dither discard 防重叠（shaders.properties:219-222；common/solid_blocks_fragment.glsl:143-152），成套 *_dh/_voxy 变体文件。

## ③ Astra 可借鉴点

每条含：技术描述 / 包内出处 / 对应 Astra 模块 / 迁移难点估计。

1. **无阴影档的"假阴影"兜底**
   - 描述：SHADOW_CASTING 关闭时，直射光强度乘 `visibleSky^10`（露天=1、洞口快速压黑），一张阴影贴图都不用就有方向性明暗；树叶再单独 sqrt 软化（src/light_vertex.glsl:77-86）。
   - 出处：src/light_vertex.glsl:115-129。
   - Astra 模块：lib/settings.glsl（NO_SHADOWS/PERFORMANCE 档，Astra/shaders/shaders.properties:424-425 现为直接无影）+ global/lighting/diffuse.glsl。
   - 难点：低。核心是十几次乘加；需与 Astra 的 STATIC_SHADOW_FALLBACK（settings.glsl:85-86）语义划清：这是逐像素 skylight 幂衰减，不需要缓冲。

2. **雾色直接取"同像素天空色"**
   - 描述：prepare 阶段把解析天空梯度写成全屏纹理，gbuffers 雾混合直接采它——雾永远与地平线无缝衔接，且省掉雾色插值分支。
   - 出处：common/prepare_fragment.glsl:45-53；src/finalcolor.glsl:16-28；src/writebuffers.glsl:9-13。
   - Astra 模块：global/atmosphere/fog.glsl（Steadfast FogV2 派生，fog.glsl:5-13）与 program/sky.fsh/deferred.fsh 消费链。
   - 难点：中。Astra 雾色是参数化常量而非纹理（fog.glsl:13-15 明确此设计），要新增一个 prepare 级天空目标或复用 sky pass 输出；需评估与 AIR_PERSPECTIVE、BIOME_TINT 的叠加次序。

3. **水体"翻转图"反射档（SSR_TYPE=0）**
   - 描述：反射向量投影一次直接采样 + 边缘 fade + 屏幕外折叠，一次纹理采样即可有"水面有倒影"，作为最低档替代完整 SSR。
   - 出处：lib/water.glsl:176-198（reflection_calc 的 SSR_TYPE==0 分支）；档位映射 lib/config.glsl:31-45。
   - Astra 模块：global/water/raytrace.glsl（Astra 自研 24 步 SSR，raytrace.glsl:3-5）+ settings.glsl:139-140 SCREENSPACE_REFLECTIONS。
   - 难点：低-中。Astra 的 water_composite 结构固定，需加一档枚举（如 WATER_REFLECTION_TIER）并把 confidence 语义映射为 border fade。

4. **CPU 预计算昼夜混合 uniform**
   - 描述：dayMixer/nightMixer/dayNightMix/volumetricDayMixer 用 shaders.properties 的 `variable/uniform` 指令在 CPU 算好（两条抛物线 f/g），所有着色器免费取用，且这些函数正是阴影强度、体积光强度、雾密度的统一门控。
   - 出处：shaders.properties:99-138（含 f(x)/g(x) 公式注释 102-107）；lib/day_blend.glsl:1-19。
   - Astra 模块：lib/uniforms.glsl（custom uniform 注册）+ global/atmosphere/fog.glsl、global/post/godrays.glsl 的时段逻辑。
   - 难点：低。纯算式迁移；注意 Astra 的 twilight.glsl 已有自己的时段体系，需对齐相位。

5. **五边形 16 点 TAA 抖动表（CPU 预计算）**
   - 描述：抖动序列按"五边形对角遍历最大化相邻帧差异"设计，16 帧周期，直接以 vec2 uniform 下发，着色器零成本且相位均匀（作者注释见 shaders.properties:143-148）。
   - 出处：shaders.properties:143-186。
   - Astra 模块：lib/taa_jitter.glsl + settings.glsl:230-231（ANTIALIASING=2）。
   - 难点：低。Astra 已有 jitter 库，只是换序列与帧周期；需回归测试 cloud/underwater-shaft 两个独立历史对 jitter 的假设。

6. **单 pass mipmap Bloom 作为低档**
   - 描述：无需降采样链，colortex 开 mipmap 后在固定 LOD 上螺旋采样即得宽半径 bloom；LOD 随视口高度自适应。
   - 出处：lib/bloom.glsl:7-34；shaders.properties:224-228；亮度提取 common/composite_fragment.glsl:229。
   - Astra 模块：global/post/bloom.glsl + global/water/bloom_capture.glsl/bloom_resolve.glsl（2-pass，settings.glsl:217-218）。
   - 难点：低-中。Astra bloom 是 2-pass 采集+合成；加低档即"复用现有 capture 目标开 mipmap、去掉 resolve pass"；需要确认 Astra 缓冲格式（water_buffer_formats.glsl）是否允许 mipmap 指令。

7. **廉价深度 godrays 作为低档**
   - 描述：VOL_LIGHT=1：从像素向太阳屏幕位置 4 步走、只查 depthtex1 是否被挡（无需阴影贴图、无需 shadow pass），强度用"视线/中心线与光源方向夹角"的幂次门控（common/composite_fragment.glsl:166-178）。
   - 出处：lib/volumetric_light.glsl:99-115；common/composite_vertex.glsl:100-106（光源屏幕位置顶点算好）。
   - Astra 模块：global/post/godrays.glsl（Steadfast noisy godrays 派生，半分辨率）+ settings.glsl:221-223。
   - 难点：中。Astra GODRAYS 默认关闭但实现是 shadow-map 路线；加"depth-only 4-tap"档可与 NO_SHADOWS 档解耦（当前 godrays 依赖阴影链的假设需核对）。

8. **hot path 的 sqrt 近似与 dither 共享纪律**
   - 描述：云密度 `x^0.25=sqrt(sqrt(x))`、假阴影 `x^10` 连乘、多效果共享一次 dither 计算的编码规范。
   - 出处：lib/volumetric_clouds.glsl:89-100；src/light_vertex.glsl:119-123；lib/dither.glsl:1-27。
   - Astra 模块：global/atmosphere/clouds_planar.glsl（消费点，clouds_planar.glsl:5-9）、global/atmosphere/volume_fog.glsl、lib/bayer.glsl。
   - 难点：低，逐点替换 + A/B 截图对比。

9. **成套 DH 过渡兼容范式（观察项）**
   - 描述：DH 深度双源 min 合并、过渡带 `dither discard` 防远近地形重叠、dh_water 独立混合（blend.dh_water，shaders.properties:219-221）。
   - 出处：common/solid_blocks_fragment.glsl:143-152；lib/water.glsl:145-150。
   - Astra 模块：Astra 当前无 DH 集成（settings.glsl:310-313 VOXY_SUPPORT 仅为保留位）。
   - 难点：高（属新特性而非迁移），仅记录范式，不建议近期投入。

## ④ Astra 已有对应实现

| 特性 | MakeUp 做法 | Astra 对照 | 两边优劣（判断） |
| --- | --- | --- | --- |
| 距离雾 | pow 曲线 + 天空纹理雾色（src/fog_vertex.glsl:27-31） | global/atmosphere/fog.glsl，Steadfast FogV2 派生（fog.glsl:5-13） | Astra 曲线更物理（FogV2、有 border/cave/水下分媒体）；MakeUp 雾色与天空的耦合更无缝。雾色来源可互补，见 ③.2 |
| 天空 | 两色 XYZ 梯度（prepare_fragment.glsl:49-53） | global/atmosphere/sky_gradient.glsl，Complementary 三向模型（sky_gradient.glsl:5-6）；SKY_MODE=0 时 Minishita 物理大气 | Astra 观感与覆盖面占优；MakeUp 的 prepare-纹理化产物恰好是 ③.2 的载体 |
| 云 | 单 2D 纹理 10 步板层 march（volumetric_clouds.glsl:5-106） | global/atmosphere/clouds_planar.glsl，Complementary Reimagined 云模型 + 独立时域历史（clouds_planar.glsl:5-9；settings.glsl:109-115），CLOUD_QUALITY 三档 32/64/96 步 | Astra 形体/光照明显更好且已有低档；MakeUp 胜在纹理驱动成本恒定——Astra 无需借 |
| 水反射 | 翻转图 / 10 步二分 SSR（water.glsl:9-97、176-198） | global/water/raytrace.glsl 自研 24 步 SSR + sky 回退（raytrace.glsl:5-6） | Astra 质量占优但最低档缺位；MakeUp 翻转图是 PERF 档候选（③.3） |
| 水折射/吸收 | 屏幕偏移 + 深度差平方吸收（water.glsl:132-160） | global/water/refraction.glsl（逐 tap 深度拒绝）+ absorption.glsl Beer-Lambert 逆距离消光（absorption.glsl:6-14） | Astra 物理正确性占优；MakeUp 深度差平方曲线更"浓"但不分光谱。不确定 Astra 折射偏移量级是否可比 |
| 阴影 | 3×3 分辨率/距离配对 + 4 采样圆盘（config.glsl:222-294；shadow_frag.glsl:12-31） | global/lighting/shadowmap.glsl（Steadfast 派生），SHADOW_RESOLUTION/DISTANCE 独立滑条 + 足迹滤波两模式（settings.glsl:68-87） | Astra 更灵活；MakeUp"配对表"防低配选错组合的 UX 值得抄——Astra 可加预设绑定而非硬约束 |
| 彩色阴影 | 4 采样三图（shadow_frag.glsl:38-152） | COLORED_SHADOWS（settings.glsl:83-84），shadowmap.glsl 每角配 caster tint（shadowmap.glsl:15-16） | Astra 与滤波耦合更系统；MakeUp 实现更直白。无borrow必要 |
| 体积光 | 深度 4-tap / 阴影 6 采样两模式（volumetric_light.glsl:21-115） | global/post/godrays.glsl（半分辨率 Steadfast 派生）+ global/water/light_shafts.glsl | Astra 水下光轴独有且更精；MakeUp 的 depth-only 低档可补 NO_SHADOWS 档空缺（③.7） |
| AO | 深度螺旋 5 步，不依赖阴影（ao.glsl:6-46） | SCREENSPACE_AO（program/ssao.fsh + lib/ao_material.glsl/ao_resolve.glsl），但被门控为需 SHADOWS 且 AO_STRENGTH>0（settings.glsl:458-460） | 分歧点：Astra PERF 档当前 AO=off 且不可用；MakeUp 证明无阴影 AO 可行——若 Astra 的门控是有意为之（避免与 vanilla AO 双算），保留现状，仅作记录 |
| TAA | 9 邻域方差凸包裁剪 + 0.99 基混合（fast_taa.glsl:7-32、130-137） | ANTIALIASING=2 HDR TAA + lib/taa_jitter/taa_state/taa_reactive（settings.glsl:230-231） | Astra 有 jitter 投影与反应性控制，工程化程度高；MakeUp 的 CPU 预计算抖动表（③.5）与"裁剪半径进 history alpha"的紧凑历史格式值得对照 |
| 自动曝光 | 顶点 5-tap mipmap + exp 曲线（composite_vertex.glsl:73-87） | global/post/exposure.glsl 1×1 历史计量 pass（exposure.glsl:8-9、22）；AUTO_EXPOSURE 默认关（settings.glsl:206-208） | 成本同级、Astra 更可调；无需借。若追求极致可借 5-tap 顶点版做 PERF 档，收益有限 |
| Bloom | 单 pass mipmap 螺旋（bloom.glsl:7-34） | 2-pass capture+resolve（settings.glsl:217-218） | MakeUp 更省一个 pass（③.6）；Astra 质量更可控 |
| 色调映射 | 单 sigmoid（tone_maps.glsl:14-19） | lib/tonemap.glsl 四算子（Uchimura/AgX/ACES/Reinhard-Jodie，tonemap.glsl:4-15） | Astra 占优，无借 |
| FXAA | fxaa311（lib/fxaa.glsl） | global/post/fxaa.glsl（display-space，ANTIALIASING=1） | 功能等价，无借 |
| 方块光色温 | 5 档色温 + 烛光曲线（color_utils.glsl:158-168） | BLOCKLIGHT_STRENGTH + global/lighting/blocklight.glsl；色温档不确定（settings.glsl 中未见色温枚举） | Astra 有无色温不确定，不编造；曲线本身是廉价易抄的观感项 |
| 下界光照 | 仅雾距 + omni tint（fog_vertex.glsl:34-55） | NETHER_VOXEL_LIGHT 64³ 体素 8 步传播（settings.glsl:180-185）+ 九段 compute | Astra 全面占优，无借 |
| 末地 | 静态盘亮化 + 简化体积光（deferred_fragment.glsl:130-133、154-165） | Kerr 黑洞天空 + 末地独立光照体系（global/dimension/end_*.glsl） | Astra 全面占优，无借 |

## ⑤ 借鉴可行性（许可证层面）

- **结论：可合法借鉴，是本工作区已研究包中义务最轻的一个。** LICENSE:1-2 为 LGPL-3.0；GLSL 源码按 LGPL 属"源代码形式交付"，Iris/OptiFine 在加载时才编译链接。
- **"链接无关性"义务在 shader 场景的解释**：LGPL 的核心义务是允许用户替换/重链该库并重连成_combined work_。GLSL 没有目标代码、没有静态链接——光影包以纯源码分发，用户本来就能直接改任何 .glsl 并由 Iris 重新编译，"relink"义务天然满足；也因此 LGPL 第 4 条关于对象代码/installation information 的条款没有适用对象。主要义务收敛为：保留版权与许可声明、对修改部分作声明、随包附带 LGPL 许可文本（或指明出处）。
- **与 Astra 现行 GPL-3.0-or-later 的合并**：Astra 的 Steadfast 派生文件为 GPL-3.0-or-later（global/atmosphere/fog.glsl:5-8、global/lighting/shadowmap.glsl:5-8）。LGPLv3 §4 允许把 LGPL 库并入后**整体按 GPL-3.0 分发**（或 Astra 也可选择把新借文件单独立为 LGPL 保持双轨）。无论哪种：文件头标注 "Portions Copyright Javier Garduño, LGPL-3.0"、列出改动、在 THIRD-PARTY.md 记账（Astra 已有此惯例：lib/tonemap.glsl:4 记 MIT 链、lib/solas_water.glsl:4-5 记 Solas）。
- **README 的额外许可**：README.md:23-30 的"无限制使用"是作者对本包的放宽陈述，可作为协商余地，但不能据此跳过 LGPL 署名义务——按 LGPL 从严执行即可，成本极低。
- **最适直接改编的文件**（自包含、与管线耦合小）：lib/volumetric_light.glsl、lib/bloom.glsl、lib/fast_taa.glsl、lib/water.glsl（SSR_TYPE=0 分支）、lib/volumetric_clouds.glsl、src/light_vertex.glsl、src/fog_vertex.glsl、shaders.properties:89-228 的预计算段。注意：即使逐函数摘抄，也按上面口径留痕。
- **风险提示**：本报告给出的是工程口径而非法律意见；Astra 对 GPL 部分本就有发布门（fog.glsl:10 提及 design.md 9.3 + SC-14 待决），LGPL 引入是否并入同一发布门需统帅决策。

## ⑥ Top5 优先建议（按 提升/工作量 排序）

1. **PERFORMANCE/NO_SHADOWS 档加"假阴影"**（③.1）——十几行乘加，让 Astra 最低档从"平光"变"有方向感"，观感提升最大、工作量最小。落点 global/lighting/diffuse.glsl + 档位开关。
2. **水体翻转图反射低档**（③.3）——PERFORMANCE 档水面从"无反射"变"有天空/景物倒影"，一次纹理采样。落点 global/water/raytrace.glsl + settings 枚举。
3. **深度 godrays 低档**（③.7）——4-tap depth-only，让 GODRAYS 在无阴影链/低配档可用。落点 global/post/godrays.glsl 旁路。
4. **mipmap 单 pass Bloom 低档**（③.6）——省一个 pass，PERF 档也能开 Bloom。落点 global/post/bloom.glsl + 缓冲格式核对。
5. **CPU 预计算昼夜/抖动 uniform**（③.4+③.5）——把昼夜抛物线与 TAA 抖动表搬进 shaders.properties，全着色器减负。落点 lib/uniforms.glsl、lib/taa_jitter.glsl、shaders.properties。

（③.2 天空纹理雾色观感收益好但动雾管线结构，列为 6 号观察项；③.8 属随手优化。）

---

### 附：本次自抽查记录
报告完成后已重开源文件复核下列引用（≥8 条，共 60+ 条抽查）并全部一致：shaders.properties:4、27、36、45、111、151、227；lib/config.glsl:31、81、164、193、226、317；src/light_vertex.glsl:123；src/fog_vertex.glsl:28；src/finalcolor.glsl:16；src/low_sky.glsl:14；src/writebuffers.glsl:11；lib/water.glsl:9、127、184；lib/volumetric_clouds.glsl:91；lib/volumetric_light.glsl:29、99；lib/fast_taa.glsl:7；lib/bloom.glsl:7；lib/ao.glsl:6；lib/shadow_frag.glsl:12；lib/color_utils.glsl:17、174；lib/tone_maps.glsl:14；common/composite_vertex.glsl:74；common/composite_fragment.glsl:2、110、229；common/composite1_fragment.glsl:66；common/composite2_fragment.glsl:101；common/water_blocks_fragment.glsl:176；common/deferred_fragment.glsl:176；common/prepare_fragment.glsl:51；common/final_fragment.glsl:14；Astra/shaders/shaders.properties:424-425；Astra/lib/settings.glsl:182、218、222、459；Astra/global/atmosphere/fog.glsl:5、8、10、13；Astra/global/atmosphere/sky_gradient.glsl:5-6；Astra/global/atmosphere/clouds_planar.glsl:7、9；Astra/global/water/raytrace.glsl:5-6；Astra/global/water/absorption.glsl:6；Astra/global/post/exposure.glsl:8-9、22；Astra/global/post/godrays.glsl:5；Astra/global/lighting/shadowmap.glsl:15-16；Astra/lib/tonemap.glsl:4；Astra/lib/solas_water.glsl:4。初稿中 8 处 Astra 头注引用行号偏差已全部修正（fog/sky/clouds/raytrace/absorption/exposure/godrays/shadowmap/tonemap/solas_water）。
