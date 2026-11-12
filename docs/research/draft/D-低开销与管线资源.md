# D — 低开销 / 极致性能设计与管线资源调度

只读研究笔记。研究范围：Steadfast(b0bebea)、MakeUp(13ac348)、RendererPearl(0642536)、Glimmer(6a59109)、Rethinking Voxels(1fd788f)、DrDesten(badf964)、Miniature(bdb6e00)、I Love Vanilla(485f800)、Super Duper Vanilla(1ca20aa)。
所有引文均转录自本机副本（%TEMP%/dsh-ptc-plus-Walbj7/spr/...），行号按该副本计。

强度标注：
- **[源码]** 直接读到实现，行号与原文可核对。
- **[推断]** 由源码结构推出，但可能被编译器优化掉、或被默认配置绕过。
- **[未验证]** 需要实机或抓帧才能确定。

---

## 1. 用属性文件把整个 pass 关掉，而不是在 shader 里写 if

**技术目标**：省掉一整趟全屏绘制，而不是让每个像素在 shader 里空跑。

**实现位置（源码）**

Steadfast 用 ```program.<name>.enabled=<选项>``` 把 pass 是否执行交给选项，而不是交给 shader 内部分支：

```pipeline/pipeline.properties:29-32```
```
# Disable programs when we don't have the corresponding effect, saves a bit of
# performance.
program.composite.enabled=GODRAYS
program.deferred1.enabled=ROUGH_REFRACTION
```

Glimmer 用同一个机制，并且写成 ```PROGRAM_DISABLED``` 这种永不成立的名字，同时按维度分别关：

```shaders/shaders.properties:87-92```
```
program.world0/prepare1.enabled=ROUGH_SKY_REFLECTIONS
program.world0/prepare3.enabled=ATMOSPHERIC_FOG

program.world0/shadowcomp.enabled=FLOODFILL
```

```shaders/shaders.properties:117-125```
```
program.world1/prepare1.enabled=PROGRAM_DISABLED
...
#if !(defined DISTANT_HORIZONS || defined VOXY)
program.world1/composite.enabled=PROGRAM_DISABLED
#endif
```

DrDesten 用布尔表达式组合开关，一次关掉一串只有某个功能才需要的 pass：

```drdesten/shaders/shaders.properties:196-198```
```
program.world-1/deferred.enabled=SCREEN_SPACE_AMBIENT_OCCLUSION
program.world0/deferred.enabled=SCREEN_SPACE_AMBIENT_OCCLUSION
program.world1/deferred.enabled=SCREEN_SPACE_AMBIENT_OCCLUSION
```

```drdesten/shaders/shaders.properties:200-213```
```
program.world-1/composite8.enabled=DEPTH_OF_FIELD || TAA
...
program.world-1/composite11.enabled=BLOOM || MOTION_BLUR
```

ILV 用配置常量决定整批 pass：

```ilv/shaders/shaders.properties:347-354```
```
#if BLOOM_ENABLED == 0
	program.world-1/composite10.enabled = false
	program.world0/composite10.enabled = false
```

**算法机制**：这些行被 Iris 在**建管线时**读取（不是每帧每像素），决定某个 program 是否被链接与调度。因此省下的是「整趟 draw call + 该趟的片元着色 + 可能的附件写入」。它与 ```#ifdef``` 的区别是：```#ifdef``` 至少要编译出一个（空）program 并仍然跑光栅化，而 ```.enabled``` 是让这一趟不存在。Steadfast 甚至让被禁用的 composite 文件只剩一行 include：```shaders/composite.fsh``` 全文 21 行，主体只有 ```#include "program/post/noisy_godrays.fsh"```。

**开销与代价**：省一整趟 分辨率 × 采样数 的片元作业。代价是选项组合爆炸：每个新选项要在 3 个维度（world0/world1/world-1）各写一遍，漏写就出现「另一维度还在跑旧 pass」。Glimmer 与 ILV 都出现同一段开关写三遍的重复。

**适用范围与失效边界**：只对「整趟可以不存在」的效果有效。若某趟仍必须写一个附件（例如给后续 pass 提供深度或状态），只能保留。

**与 Astra 的关系**：Astra 已经在做，而且更激进——```Astra/shaders/shaders.properties``` 共 1172 行，含 127 条 ```.enabled``` 语句，并且把**缓冲区尺寸**与 pass 开关写在同一个 ```#if``` 里（```shaders.properties:108-142```：TAA 关闭时同时把 colortex15/16/22/17 压到 1×1 并关掉 composite6/7）。这一条不需要向外部学，**但可反过来复用 Steadfast 的组织习惯**：Steadfast 把开关集中在 ```pipeline/pipeline.properties``` 并在注释里写清「为什么这趟可以不存在」，Astra 现在的开关分散且注释密度不均。

---

## 2. 硬编码「本趟唯一的量化目标」，用 8 位而不是 16 位

**技术目标**：同一张缓冲，把每纹素字节数从 8 字节（RGBA16F）降到 4 字节甚至 1 字节，并写明理由。

**实现位置（源码）**

```steadfast/shaders/legacy/pipeline.glsl:82-104```
```
// This is a very compact floating-point color format using 32 bits just as
// RGBA8 does, while permitting HDR colors.
...
const int colortex1Format = R8;
```

同文件 95-104 行把理由写全了（本笔记最有价值的作者自述之一）：

```
// Godrays format is just a single color channel, 8 bits is enough.
//
// Originally I used 16 bits, but it turns out that if we do not scale the
// result, since we are smoothing the result anyways and the noise acts as a
// dither, there is actually zero noticeable difference between 8 bits and 16
// bits. So switching to 8 bit halves the required memory bandwidth on both ends
// basically for free, compared to using 16 bits.
```

水面遮罩用带符号 16 位存「水位编码」（并解释为什么不用 R16）：

```steadfast/shaders/legacy/pipeline.glsl:134-139```
```
// Encoded water height
//
// We would prefer to use R16 but R16 is not in OpenGL 3. R16_SNORM is, though.
const int R16_SNORM = 0;
const int shadowcolor0Format = R16_SNORM;
```

ILV 连 4 位精度的 RGBA4 都用上了：

```ilv/shaders/basics/settings.glsl:27-28```
```
const int   colortex8Format       = RGBA4;
const int   colortex9Format   = RGBA8;
```

**算法机制**：带宽 = 分辨率 × 每纹素字节 × 读写次数。16F→8 位直接砍一半这条链路的读写带宽；不需要 alpha 的 HDR 目标用 R11F_G11F_B10F，保持 32 位/纹素却有 HDR 范围。关键前提是**不缩放数值**（Steadfast 明写：在这里缩放到 [0,1] 再在消费端还原，纯粹是精度损失）。

**开销与代价**：精度换带宽。8 位加抖动加后续模糊确实肉眼看不出差异，但前提是这张缓冲**本身要被平滑**；若下游直接用它做硬阈值，8 位会露台阶。

**适用范围与失效边界**：适用于「低对比度、最终被模糊或被乘进颜色」的中间量（光柱、AO、遮罩）。不适合颜色本体（会色带），不适合需要 HDR 动态余量的累积缓冲。

**与 Astra 的关系**：Astra 同思路且分层：```Astra/shaders/program/scattering.fsh:86-99``` 空中光柱用 RG16F，只有编译进水下光柱时才升级到 RGBA16F；同文件 10-19 行明确写「不在这里缩放，避免精度损失」，且注明这一结论来自 Steadfast。**Astra 的空白是没有 8 位中间量**：现有最低到 RG16F 与 R8（```Astra/shaders/lib/taa_reactive.glsl:7``` 用 R8 存反应性掩码）。若 Astra 存在「只被模糊消费」的中间缓冲，R8 是可直接试的一档。

---

## 3. 减少 varying（顶点到片元的数据通路），把每面常量打包成一个 32 位整数

**技术目标**：Minecraft 的顶点到片元带宽是真实瓶颈，减少每顶点插值数据。

**实现位置（源码）**

```steadfast/src/lib/encoding/face.slang:30-41```
```
// The current encoding is: Octahedral X (9 bits), Octahedral Y (9 bits),
// and material ID (4 bits).
...
// There is a fixed amount of buffer space available on graphics hardware for
// transferring data from the vertex shader to the fragment shader, and this is
// a common bottleneck in Minecraft, so packing this data into a single 32-bit
// value helps reduce this bottleneck.
```

同文件 43-50 行注明二十面体编码出处是 Meyer 等人 2010 年 EGSR 论文，属**借用公开论文**，不是原创。

RendererPearl 用 GLSL 的 location/component 指定打包位置：

```renderpearl/shaders/lib/v_data_lit.glsl:1-13```
```
VertexData {
	layout(location = 0, component = 0) vec2 coord;
	layout(location = 1, component = 0) flat uint misc_packed;
	// ^uint4    bool1      unorm11 none15 bool
	// ^emission handedness alpha   none   is_water_or_metal
...
		layout(location = 1, component = 1) flat uint snorm4x8_octa_tangent_normal;
```

```renderpearl/DEV.md:73-76``` 给出打包原则并注明来自 AMD RDNA 性能指南：

```
> "When bit-packing fields into a G-Buffer, put highly correlated bits in the Most Significant Bits (MSBs) and noisy data in the Least Significant Bits (LSBs)." ([AMD RDNA Performance Guide](https://gpuopen.com/learn/rdna-performance-guide/))
```

DrDesten 从另一头做同一件事：把插值限定符做成开关。

```drdesten/shaders/lib/stddef.glsl:10-18```
```
#ifdef OPTIMIZE_INTERPOLATION

#define OPT_FLAT flat
#define OPT_NOPERSPECTIVE noperspective

#else 

#define OPT_FLAT smooth
#define OPT_NOPERSPECTIVE smooth
```

**算法机制**：每个 varying 在每个被光栅化的像素上都要算一次插值。把法线(3)+切线(3)+材质(1)+朝向(1) 从若干 float 压成 1 个 ```flat uint```，等于 4~8 个分量降到 1 个，且 flat 不参与插值；片元端做一次位解码。

**开销与代价**：换片元端解码算术和量化误差（9 位法线有可见角度台阶，硬表面不明显、平滑法线可能显现）。DrDesten 的 flat 用法代价更小，但必须保证「整个三角形共享同一值」成立。

**适用范围与失效边界**：只对**逐三角形常量**成立（面法线、材质、朝向）。平滑法线不适用——Steadfast 自己在 ```lit.vsh:315-323``` 承认 PhysicsMod 的雪会破坏这个假设。

**与 Astra 的关系**：Astra 已有同类实现：```Astra/shaders/program/lit.vsh:143``` 是 ```faceData = pack_octahedral(normal, 9) | (material << 18);```，```Astra/shaders/program/lit.fsh:53``` 用 ```flat in uint faceData;``` 接收，量化函数在 ```Astra/shaders/lib/encoding.glsl:47-63```。**Astra 缺的是显式的 varying 预算审计与 DrDesten 那种 flat/noperspective 开关**：lit.vsh 仍单独传 ```cameraRelativePosition```、```surfaceShadowCoordinate```、```tint``` 等，没有集中审计过「哪些是真需要插值的」。

---

## 4. 把逐像素的矩阵反算当作「比传 varying 更便宜」的默认选择

**技术目标**：省掉顶点到片元的位置数据，改在片元里从深度反算世界坐标。

**实现位置（源码）**

```steadfast/src/program/world/lit.fsh:227-232```（作者在代码里直接下了结论）
```
	// It is cheaper to do this transform back from the fragment coordinates in
	// the fragment shader rather than passing these positions as varyings from
	// the vertex shader, as the cost of buffering and interpolating is more
	// expensive than the following matrix math.
	float3 ndcPos = gl_FragCoord.xyz * float3(windowToNdc, 2.0) - 1.0;
	float4 viewPosH = mul(inverseProjectionMatrix, float4(ndcPos, 1.0));
```

Steadfast 还顺手消除矩阵乘法里用不到的部分：

```steadfast/src/program/world/lit.vsh:171-178```
```
		// transpose(inverse(gbufferModelViewInverse))
		// = transpose(gbufferModelView)
		//
		// Note that the transpose operations are cheap because they are
		// just renaming / excluding variables used for the underlying matrix
		// multiplication, and the multiplies by 0.0 will be optimized out.
		float3 world = mul(
			transpose(gbufferModelView),
```

**算法机制**：一个 vec3 varying 等于每像素插值 3 个分量加顶点阶段存一次；片元端一次 4×4×4 乘法（现代 GPU 上是常数条 FMA）。Steadfast 判定后者更便宜——**这是作者结论（推断，未给测量）**，但与自己另一处实现互相印证：```copy_and_fog.fsh:86-89``` 同样用 ```texelFetch(colortex0, int2(gl_FragCoord), 0)``` 拷贝，而不写全屏 quad 的 UV 插值。

**开销与代价**：片元端多一小段算术，换掉 varying 带宽。对移动 GPU（Tile-based）收益更明显，因为 varying 要走 tile 内存。

**适用范围与失效边界**：只在「位置能从深度精确重建」时成立。一旦顶点被位移（树叶风、水面波），深度重建的位置与位移后位置不一致，必须传 varying——Astra 与 Steadfast 都在风摆分支里重算 viewPos 正是这个原因（Astra：```lit.vsh:295-303```；Steadfast：```lit.vsh:330-333```）。

**与 Astra 的关系**：Astra 混合使用两种方式。```Astra/shaders/program/lit.vsh:304``` 传 ```cameraRelativePosition = playerPos;```（因为树叶与水需要位移后的位置），而拷贝类 pass 走 texelFetch。**未核查** Astra 是否有独立的「纯静态不透明几何」路径可以只靠深度重建从而砍掉这个 varying。

---

## 5. 用「每帧一次」的自定义 uniform 把逐像素工作搬到 CPU

**技术目标**：把只与时间、视角有关而与像素无关的量，移出片元着色器。

**实现位置（源码）**

```steadfast/pipeline/uniforms/uncategorized.properties:567-576```
```
# The final godrays exposure is the product of the view-angle fade and the time-of-day
# exposure value.
uniform.float.godraysExposure=godraysBaseExposure * godraysViewAngleFade * godraysOffscreenFade

# Godrays are the color of the direct light. Pre-multiply in the exposure value so
# the shader can skip a multiply for free.
uniform.vec3.godraysColor=vec3( \
	directLightSurface.r * godraysExposure, \
```

后处理里先短路再采样：

```steadfast/src/program/post/postprocessing.fsh:47-52```
```
float3 smoothGodrays() {
	if (godraysExposure <= 0.0) {
		return float3(0.0);
	}
```

MakeUp 把大段三角与幂运算变成 ```variable.``` 链式展开，注释直接写动机：

```makeup/shaders/shaders.properties:91```
```
# Many values are precalculated to avoid their later or repetitive calculation.
```

```makeup/shaders/shaders.properties:94-96```
```
uniform.float.pixelSizeX = 1.0 / viewWidth
uniform.float.pixelSizeY = 1.0 / viewHeight
uniform.float.aspectRatioInverse = 1.0 / aspectRatio
```

DrDesten 把 TAA 抖动偏移在 CPU 上算成 vec2：

```drdesten/shaders/shaders.properties:105-108```
```
uniform.vec2.taaOffset=vec2( \
    (frac(1./1.32471795724474602596 * frameCounter + 0.5) - 0.5) / viewWidth, \
    (frac(1./1.75487766624669276004 * frameCounter + 0.5) - 0.5) / viewHeight \
)
```

**算法机制**：Iris 在 CPU 侧求值这些表达式（每帧或值变化时），以 uniform 注入。省掉的是「每像素重复算同一个与像素无关的值」——典型如 pow、normalize、三角函数、除法。

**开销与代价**：几乎零代价（CPU 端每帧几次浮点）。风险在表达力：Iris 表达式语言受限（Astra 自己在 ```Astra/shaders/lib/settings.glsl:791-792``` 记录了「clear color 必须是 4 参数、每参数是纯字面量」的解析限制），复杂逻辑写不进去。

**适用范围与失效边界**：只对与像素无关的量成立。一旦依赖像素坐标或深度就不能搬。

**与 Astra 的关系**：Astra 已达标且理由更细——```Astra/shaders/program/scattering.fsh:16-19``` 明确写 godraysExposure「全部 CPU 侧」、GODRAYS_STRENGTH 留到第 2 阶段合成「这样调滑块不需要重跑这一趟」。差别在 Steadfast 会显式做「预乘进颜色，省一次乘法」这种微观清洁，Astra 未系统做。

---

## 6. 用噪声抖动加更少样本，替代「多采样平滑」

**技术目标**：把每像素的采样次数降下来，靠抖动与后续平滑掩盖。

**实现位置（源码）**

```steadfast/src/program/post/godrays.slang:35-36```（两组固定参数）
```
static const GodraysSettings NOISY_GODRAYS = GodraysSettings(8u, 0.83, 0.5);
static const GodraysSettings SMOOTH_GODRAYS = GodraysSettings(8u, 0.75, 0.0001);
```

```steadfast/src/program/post/godrays.slang:38-46```（出处标注）与 59-61 行（真正的省法）
```
// Godrays function based on GPU Gems 3:
//
// "Chapter 13. Volumetric Light Scattering as a Post-Process"
...
// - By varying the starting position using noise, we can get away with a
//   much-reduced sample count
```
```
	uv += step * 1.5 * Bayer8(pixelCoord);
```

**算法机制**：光线步进本来是「一个位置沿射线累加 N 次」。改为每个像素抖动起点（这里用 8×8 Bayer 有序抖动，```lib/bayer8.slang```），使相邻像素采样点错开，空间上把 N 次采样等效扩成 N × 像素数，再靠平滑收敛。**注意 Steadfast 用 Bayer 矩阵而不是噪声纹理，即不接受随机噪点，只要结构化抖动**——这与「蓝噪声加时域」路线不同，不引入帧间闪烁。

**开销与代价**：采样次数从常规 30~60 降到 8，但引入空间图案（Bayer 的交叉纹在极暗场景可能可见）与「必须平滑」的强耦合。Steadfast 因此把分辨率也砍到一半（```pipeline/pipeline.properties:56-58```）。

**适用范围与失效边界**：只在「结果会被低通」时成立。若下游是硬阈值或逐像素比较，抖动反而变成噪点。

**与 Astra 的关系**：Astra 有同构机制但未核实抖动类型——```Astra/shaders/lib/bayer.glsl``` 存在，且 ```Astra/shaders/program/scattering.fsh``` 的光柱走半/四分之一分辨率。**未核查** Astra 是否像 Steadfast 一样把抖动写进采样起点（而不是写进最终亮度），这决定它是否会把抖动图案带进最终画面。

---

## 7. 用「固定小表」替代解析天空与雾公式

**技术目标**：把每像素的多次散射积分换成一次查表。

**实现位置（源码）**

Glimmer 采用 Hillaire 的大气模型，拆成四张 LUT（transmittance / multiple scattering / sky-view / aerial perspective），尺寸声明在 properties：

```glimmer/shaders/shaders.properties:13-16```
```
image.sunTransmittanceLUT = sunTransmittanceLUTTex RGBA RGBA16F HALF_FLOAT false false 256 64
image.multipleScatteringLUT = multipleScatteringLUTTex RGBA RGBA16F HALF_FLOAT false false 32 32
image.skyViewLUT = skyViewLUTTex RGBA RGBA16F HALF_FLOAT false false 200 200
image.aerialPerspectiveLUT = aerialPerspectiveLUTTex RGBA RGBA16F HALF_FLOAT false false 32 32 32
```

片元端只剩一次纹理采样：

```glimmer/shaders/lib/atmosphere/sky/sky.glsl:33-38```
```
  // Non-linear mapping of altitude angle. See Section 5.3 of the paper.
  float v =
      0.5 + 0.5 * sign(altitudeAngle) * sqrt(abs(altitudeAngle) * 2.0 / PI);
  vec2 uv = vec2(azimuthAngle / (2.0 * PI), v);

  return texture(skyViewLUTTex, uv).rgb;
```

```glimmer/shaders/lib/atmosphere/fog.glsl:20-22```
```
vec3 atmosphericFog(vec3 color, vec3 viewPos) {
  vec3 pos = mapAerialPerspectivePos(viewPos);
  vec4 fog = texture(aerialPerspectiveLUTTex, clamp01(pos));
```

同目录 ```hillaireCommon.glsl:29-31``` 还注明作者把 skyViewLUT 的竖直分辨率从论文值翻倍（注释原文：```// Doubled the vertical skyViewLUT res from the paper, looks way better for sunrise.```）——说明这张表的尺寸是主观可调的质量旋钮，不是固定常数。

**算法机制**：表由 compute shader（```shaders/program/setup.csh```、```setup1.csh```、```prepare.glsl```、```prepare3.glsl```）每帧或每隔若干帧刷新；消费端只用一次采样加少量算术（角度压缩、非线性的 v 映射）。省掉的是「每像素沿视线做 N 步散射积分」。

**开销与代价**：固定显存（256×64 + 32×32 + 200×200 + 32³，共数十 KB 级，远小于一张全屏 RGBA16F）；代价是表的刷新频率与视角依赖——skyViewLUT 依赖相机高度与太阳方向，太阳动或相机动就要重刷，否则出现「天空跟着相机走」的错误。aerialPerspectiveLUT 是 32×32×32 的体积表，三维采样比一次二维贵。

**适用范围与失效边界**：适用于「视角内变化平滑、与场景几何无关」的大气量。对与几何强相关、有硬边界的量（云边缘、体积光遮挡）不适用——Glimmer 的云就不走这张表。

**与 Astra 的关系**：Astra 有同构但更小的表：```Astra/shaders/lib/sky_gradient_cache.glsl:10-26``` 用 65/129/257 三档（按 CLOUD_QUALITY）的二维表缓存「平滑天空基底」，并在注释里划清边界——只含平滑基底，不含眩光、天体、星星、抖动、介质；尺寸调度在 ```Astra/shaders/shaders.properties:63-88```。**Astra 没有的是多散射 LUT 与 aerial perspective 表**，即 Astra 的雾仍逐像素解析求值。这是真实可选项，但属于功能扩展而非纯优化。

---

## 8. 半分辨率加专用下采样核，以及「模糊目标按需降级」

**技术目标**：把只当模糊源使用的缓冲降分辨率，同时保持屏幕空间足迹不变。

**实现位置（源码）**

```steadfast/pipeline/pipeline.properties:56-62```
```
# Render godrays buffer at half resolution
# Keep this in sync with the windowToScreenHalf custom uniform.
size.buffer.colortex1=0.5 0.5

# Downsampled refraction/reflection buffer for rough refraction (blur).
# Keep this in sync with the windowToScreenHalf custom uniform.
size.buffer.colortex6=0.5 0.5
```

配套的自定义 uniform（```pipeline/uniforms/uncategorized.properties:508-510```）：

```
# Same as windowToScreen, but accounting for half-resolution rendering used by
# godrays and rough refraction
uniform.vec2.windowToScreenHalf=vec2(1.0 / (0.5 * viewWidth), 1.0 / (0.5 * viewHeight))
```

下采样核借用 COD:AW 的 Jimenez 13 taps，出处写得清楚：

```steadfast/src/lib/kernels/jimenez_downsample.slang:17-27```
```
// This is a high-performance, high-quality, and temporarlly-stable downsampling
// filter originally intended for bloom, but also useful for any sort of blur.
//
// See "Next Generation Post Processing in Call of Duty: Advanced Warfare" on
// https://www.iryoku.com/publications. This implementation is a translation
// of the diagram on Slide 152 ("DOWNSAMPLING - OUR SOLUTION") in the attached
// PowerPoint presentation.
//
// This implementation consists exclusively of texture sampling and fused
// multiply-add instructions.
float3 JimenezDownsampleBlur(sampler2D source, float2 uv, float2 pxToUv) {
```

调用点极短（```src/program/post/refraction_blur.fsh:24-27```）：

```
void main() {
	float2 uv = gl_FragCoord.xy * windowToScreenHalf;
	float3 blur = JimenezDownsampleBlur(colortex4, uv, windowToScreenHalf);
```

**算法机制**：13 次纹理采样、权重和为 1，一次同时完成降采样与低通。因为是固定权重核（不依赖邻域统计），天然时域稳定，不会像双边上采样那样抖动。

**开销与代价**：半分辨率使片元数变成 1/4；每片元 13 次采样。净效果相对全分辨率 5 taps 的核，采样总数下降但单像素成本上升；收益来自「输出本来就要模糊」。风险在必须与自定义 uniform 手工同步尺寸——Steadfast 注释里两次写 Keep this in sync，说明这是真实的手工耦合缺陷。

**适用范围与失效边界**：只适用于被模糊消费的目标。不能用于需要保留硬边的场景（会连带把边缘糊掉）。

**与 Astra 的关系**：Astra 已在用半/四分之一分辨率与 size.buffer 联动（见 ```Astra/shaders/shaders.properties:18-34``` 的光柱三档，```35-44``` 的 Bloom 采集从 0.5 降到 0.25 并在注释里自报「片元数降 4 倍，1080p: 518k 到 130k」）。**Astra 的尺度切换条件比 Steadfast 复杂得多**（含功能组合、采样数阈值），也就在「多处条件必须与消费者一致」上更容易出错：```Astra/shaders/program/scattering.fsh:2-3``` 已显式声明「尺寸只在 properties 声明一次，本 pass 不假设全分辨率」。对照 Steadfast，可借鉴的具体点只有一个：**把尺寸换算常量也做成 uniform 而不是在 shader 里写死 0.5**，让尺寸表与着色器只有一个真相来源。

---

## 9. 缓冲区合并：一张目标按用途分时段复用

**技术目标**：减少 buffer 数量，降低显存占用与附件切换开销。

**实现位置（源码）**

Rethinking Voxels 的格式表在注释里写明「这张缓冲在不同阶段承担不同角色」：

```rv/shaders/lib/pipelineSettings.glsl:2-8```
```
const int colortex0Format = RGBA16F;		//main color
const int colortex1Format = RGBA8;			//smoothnessD & materialMask & skyLightFactor & SSS
const int colortex2Format = RGBA16F;		//taa, previous depth
const int colortex3Format = RGB8;			//*cloud map on deferred* & translucentMult & bloom & final color
const int colortex4Format = RGBA8;			//volumetric cloud linear depth & volumetric light factor & normals in composite
```

DrDesten 同样在格式行尾注明「一张两用」：

```drdesten/shaders/lib/setup.glsl:8-12```
```
const int colortex4Format = R11F_G11F_B10F; // DOF 2 (DOF1 is colortex0) & Bloom
...
const int colortex7Format = RG16;          // PBR: Roughness, Reflectance, Height, Emission
```

RendererPearl 只留一张颜色目标，把反照率与光照都写进 colortex1（lit.fsh 输出单附件）：

```renderpearl/shaders/prog/lit.fsh:3```
```
/* RENDERTARGETS: 1 */
```

**算法机制**：把「生命周期不重叠」的数据放进同一张纹理的不同时段。省下的是**显存占用**与**附件数量**（MRT 越多，每次写越贵），不直接省 ALU。要成立必须证明「读旧值之前已经写完整张」，否则串数据。

**开销与代价**：可读性下降（同一张缓冲三种含义），并且需要严格的分阶段屏障；一旦某个 pass 提前读，错误极其隐蔽。

**适用范围与失效边界**：只在生命周期不重叠时成立。同一帧内 TAA 需要「上一帧」与「本帧」并存时不能复用（这也是 Rethinking Voxels 另开 colortex2 与 colortex12 的原因）。

**与 Astra 的关系**：Astra 用同一手法并且把「为什么可以不清」写成注释：```Astra/shaders/lib/water_buffer_formats.glsl:16-19```
```
// Enabled Bloom capture overwrites every texel before display builds its mip
// chain. The scene snapshot is likewise fully written by deferred composition
// before water/refraction can sample it; neither target needs a frame-start fill.
const bool colortex2Clear = false;
```
Astra 的缓冲数量明显多于上述任何一家（colortex 编号已用到 31，见 ```Astra/shaders/shaders.properties:76-78```）。**这说明「合并缓冲」在 Astra 还有空间，但也说明 Astra 的每个目标都绑定了一个明确的跨帧语义**（历史、状态、连续性），不能像 DrDesten 那样随手双用。任何合并都要先证明生命周期不重叠。**未核查** Astra 是否存在同帧内生命周期不重叠、却仍分开两张的缓冲对。

---

## 10. 缓冲区清屏的取舍：明确写下「为什么可以不清」

**技术目标**：省掉每帧对全屏缓冲的填充，或至少说明为什么不能省。

**实现位置（源码）**

Steadfast 明写「清成零更快、但我看不出差别」——这是一条罕见的**否证**记录，价值高于任何正面宣传：

```steadfast/shaders/legacy/pipeline.glsl:125-132```
```
// By default, Iris clears colortex0 specifically to the fog color. We do not
// need this behavior, so clear to zero. On some drivers this is supposedly
// faster, though I noticed no difference.
const float4 colortex0ClearColor = float4(0.0, 0.0, 0.0, 0.0);

// For consistency, also clear colortex1 to zero. This in particular has no
// performance difference but it is unusual compared to all other textures
const float4 colortex1ClearColor = float4(0.0, 0.0, 0.0, 0.0);
```

Rethinking Voxels 用清屏色当「哨兵值」，而不是当性能旋钮：

```rv/shaders/lib/pipelineSettings.glsl:20-26```
```
const bool colortex0Clear = true;
const vec4 colortex0ClearColor = vec4(2.0, 2.0, 2.0, 2.0);
const bool colortex1Clear = false;
const bool colortex2Clear = false;
const bool colortex3Clear = true;
const bool colortex4Clear = false;
const bool colortex5Clear = false;
```
（2.0 这个超出常规 HDR 范围的值本身就是可检测的初值。）

**算法机制**：清屏是一次与分辨率成正比的填充。省掉它的前提是「本帧一定有人写满整张」。用哨兵色则相反：不清，但保留一个可识别的初值以便判定「这块没被写过」。

**开销与代价**：省的是每帧每纹素一次写。代价是正确性完全依赖「写满」这个不变量，一旦某个 pass 因选项关闭而没写满，就会读到上一帧残留——这类 bug 表现为「切换选项后第一帧花屏」。

**适用范围与失效边界**：见上。Steadfast 的注释说明在它测试的环境里这条优化**没有可测收益**，所以不应把它当默认优化项。

**与 Astra 的关系**：Astra 系统性做了，注释质量高于外部：```Astra/shaders/lib/settings.glsl:791-805``` 有一整段说明 clear color 必须写成 4 个字面量参数（Iris 解析限制，SC-23），并逐个解释 ```colortex3ClearColor``` 的 alpha 为什么必须是 0（否则会打开 puddle 门控）。**这条 Astra 领先，不需要借鉴**；Steadfast 那句「该驱动上据说更快，但我看不出差别」可作为 Astra 未来写性能断言的措辞参考。

---

## 11. 用「重建单一渲染目标」替代多目标 MRT

**技术目标**：让每趟只写一个附件，把数据压进一张高精度图。

**实现位置（源码）**

RendererPearl 的 lit 只写 colortex1（```prog/lit.fsh:3``` 的 ```/* RENDERTARGETS: 1 */```），把色调、法线、材质都挤到同一目标的位域里；对应的布局表在 ```DEV.md:97-104```：

```
┌ lightList ----┐
|data     |color|
└1 4 9 9 9┴5 5 6┘
 | | | | | | | |
 | | | | | └[color (GRB)] (unorm)
 | | └[player feet space position (XYZ)] (uint)
 | └[intensity] (uint)
 └["wide" flag] (bool)
```

**算法机制**：MRT 数量是 G-buffer 阶段的固定成本（每多一个附件，光栅化多一路写）。把数据打包进一张 32 位或 64 位目标能显著降低这个固定成本，代价是片元端要位解码。

**开销与代价**：片元解码算术加严格位预算。超过位数就得加目标或降精度。

**适用范围与失效边界**：只在「总量塞得进固定位数」时成立。RendererPearl 是 G-buffer 极简路线（前向加延迟混合），不适合高复杂度 G-buffer。

**与 Astra 的关系**：Astra 已经在用打包（```faceData``` 的 32 位），但**仍是多目标 MRT 架构**（gbuffers 阶段有 19/20/28 等多个目标，见 ```Astra/shaders/shaders.properties:175-193``` 的分配）。**未核查** Astra gbuffers 阶段实际写几个附件、是否有低价值目标可合并——这需要读各 gbuffers_*.fsh 的 DRAWBUFFERS 与 RENDERTARGETS；本轮未逐文件核。

---

## 12. 用「量化位置」把阴影与光照查询的空间一致性买回来

**技术目标**：让相邻像素、相邻帧落在同一个查询点上，得到可复现、不闪烁的结果。

**实现位置（源码）**

Miniature 把世界坐标按固定间距吸附：

```miniature/shaders/common/math.glsl:50-52```
```
vec3 bandify(vec3 value, float bands) {
   return (floor(value*bands + 0.01) + 0.5) / bands;
}
```

```miniature/shaders/common/getLightStrength.fsh:11-15```
```
#if SHADOW_PIXEL > 0
      vec3 pos = world2feet(bandify(feet2world(feetPos), SHADOW_PIXEL));
#else
      vec3 pos = feetPos;
#endif
```

MakeUp 做同类但更激进的「阴影锁定」——把阴影查询位置吸附到指定纹素：

```makeup/shaders/common/solid_blocks_fragment.glsl:224-233```
```
        #if SHADOW_LOCK > 0
            vec3 offsetVector = vNormal * 0.002;
            vec3 preSnapPos = vWorldPos + offsetVector;
            float texelSize = SHADOW_LOCK;
            vec3 absPos = preSnapPos + cameraPosition;
            // Redondeo al bloque
            vec3 snappedAbsolute = floor(absPos * texelSize) / texelSize;
            snappedAbsolute += 0.5 / texelSize; // Centrar en el texel
            vec3 final_world_pos = (snappedAbsolute - cameraPosition) + vBias;
            vec3 shadow_real_pos = get_shadow_pos(final_world_pos);
```

选项声明在 ```makeup/shaders/lib/config.glsl:204```（默认关闭）：

```
#define SHADOW_LOCK 0 // [0 16 32 64 128 256]
```

**算法机制**：把查询点吸附到网格后，一片表面上相邻像素的查询位置相同，采样到同一个阴影纹素，不产生「每像素独立抖动」的高频噪声，也就不会被 TAA 放大成闪烁。这是**用空间精度换时间稳定性**。

**开销与代价**：位置不再精确，阴影会出现与网格同尺度的台阶与错位（MakeUp 用 ```vNormal * 0.002``` 的微小偏移加 ```vBias``` 缓解）。性能上几乎免费（几次 floor 与 snap）。

**适用范围与失效边界**：适用于「查询梯度本身小于网格」的场景（开阔地阴影）。对高频几何（树叶、铁栏杆）会明显露台阶。**注意默认值是 0，即默认不启用**——不能因为文件存在就断言它运行时生效。

**与 Astra 的关系**：Astra **有相关但不是同一手段**的机制：```Astra/shaders/program/lit.vsh:305-331``` 让原生接收者携带未畸变坐标，并按 shadowReceiver 的 NdotL 余量提前放弃投影（含 ```#ifdef SSS_FOLIAGE``` 分支对树叶放宽到 -0.60）。这是**减少无意义查询**而不是**吸附查询点**。**未核查** Astra 是否存在对静态面片按阴影纹素量化的路径。

---

## 13. 廉价替代：把世界空间的量换成屏幕空间的近似

**技术目标**：用屏幕空间一趟代替世界空间的体积积分。

**实现位置（源码）**

Steadfast 的光柱完全不做体积步进，只在深度图上沿射线取 8 个深度值判断「是不是天空」：

```steadfast/src/program/post/noisy_godrays.fsh:20-24```
```
float godraysSample(GodraysSampler sampler, float2 uv) {
	// The sky should have a depth value of 1.0. This is one of the few places
	// where == works reliably.
	return float(texture(sampler, uv).r == 1.0);
}
```

也就是说：**光柱强度等于沿屏幕射线的天空像素比例**，与介质密度剖面无关。

**算法机制**：真正的体积光要沿视线累积消光与相位；这里只统计「穿过天空的比例」并乘一个随时间与视角变化的曝光。省掉的是每步的介质查询与相位函数。

**开销与代价**：物理上是错的（没有消光曲线、没有相位、没有远近衰减），但结构对、成本极低。Steadfast 自己承认它是唯一的后处理效果，并在 profile 里把它当首要削减对象（```pipeline/profiles.properties:138-140```，注释原文：```Godrays are surprisingly expensive (being our only post-process effect right now...)```）。

**适用范围与失效边界**：只在「天空是光源、遮挡物是剪影」时成立。云、体积雾、水下会被判错——这也是 Astra 把光柱拆成空中、水下、树影三套的原因。

**与 Astra 的关系**：Astra 走更贵但更准的路线（```Astra/shaders/program/scattering.fsh``` 与 ```Astra/shaders/global/water/light_shafts.glsl``` 都存在）。对照价值是：**Astra 应该能给出「哪一档配置可退化为屏幕空间近似」的穷举**，而不是所有配置都跑积分。Astra 已有 0.25/0.5/1.0 三档（```shaders.properties:18-34```），但那是改分辨率而不是改算法——**未核查**是否存在「低配走屏幕空间-only」的路径。

---

## 14. 上游溯源（区分原创与借用）

读到明确引用标注的实现：

| 实现 | 出处（源码原文标注） | 位置 |
| --- | --- | --- |
| 二十面体法线编码 | Meyer et al. 2010, EGSR | ```steadfast/src/lib/encoding/face.slang:43-50``` |
| 正交基构造 | "Building an Orthonormal Basis, Revisited", JCGT | ```steadfast/src/lib/encoding/face.slang:141-142``` |
| Jimenez 降采样 | COD:AW, Slide 152 | ```steadfast/src/lib/kernels/jimenez_downsample.slang:20-23``` |
| 屏幕空间光柱 | GPU Gems 3, Chapter 13 | ```steadfast/src/program/post/godrays.slang:38-41``` |
| 阴影 Bias（对比参考） | Complementary Reimagined b511bc0 / Photon e253cef | ```steadfast/src/program/world/lit.vsh:216-228``` |
| G-Buffer 位打包顺序 | AMD RDNA Performance Guide | ```renderpearl/DEV.md:73``` |
| 大气 LUT | Hillaire 论文（Section 5.3 引用） | ```glimmer/shaders/lib/atmosphere/sky/sky.glsl:33``` |

**判读**：Steadfast 的原创部分集中在「把 Minecraft 特有的瓶颈（varying 带宽、阴影畸变、水吸收）与标准技术结合」这一步，算法内核基本都是公开论文或博客的忠实实现。因此**引用风险低，但也就没有独家秘方**——可以直接对照公开资料实现，不必依赖这些包的具体实现。

---

## 建议主代理重点复用的 3~6 条

1. **把「varying 预算」当成一条显式设计约束来审计**（对照 ```steadfast/src/lib/encoding/face.slang:38-41``` 与 ```renderpearl/shaders/lib/v_data_lit.glsl:1-13```）。Astra 已有 32 位 ```faceData```，但 ```cameraRelativePosition```、```surfaceShadowCoordinate```、```tint``` 等仍是独立 varying；列一张「逐项是否必须插值」的表，是零风险的收益入口。

2. **给「只被模糊消费」的中间量试 8 位**（依据 ```steadfast/shaders/legacy/pipeline.glsl:95-104``` 的作者结论：不缩放加后续平滑等于 8 位与 16 位无可见差异）。Astra 目前最低到 RG16F；这条能直接砍一半带宽，且失败模式是可见色带、容易回退。

3. **把尺寸换算系数做成 uniform 而不是在 shader 里写死 0.5**（对照 ```steadfast/pipeline/uniforms/uncategorized.properties:508-510``` 与它自己两次 Keep this in sync 的手工耦合警告）。Astra 的 buffer 尺寸表已高度条件化（```Astra/shaders/shaders.properties:18-34```、```35-44```），单一真相来源能直接消掉一类「尺寸与消费者不一致」的隐患。

4. **把 .enabled 开关集中化，并给每一条写「为什么这趟可以不存在」**（对照 ```steadfast/pipeline/pipeline.properties:29-32``` 与 ```glimmer/shaders/shaders.properties:117-125``` 的按维度关断）。Astra 的 127 条开关功能上更强，但分散在 1172 行里且维度三连写；集中化是纯组织收益，同时能发现「某维度忘了关」的现存漏洞。

5. **考虑一张 aerial-perspective 三维表替代逐像素雾积分**（对照 ```glimmer/shaders/shaders.properties:13-16``` 与 ```glimmer/shaders/lib/atmosphere/fog.glsl:20-22```）。Astra 已有 sky gradient 表（```Astra/shaders/lib/sky_gradient_cache.glsl:10-26```）但没有雾表；这是把「每像素 N 步」降为「一次三维采样」的现成范式。注意这是功能扩展，需先确认 Astra 雾目前确实逐像素积分（本轮未逐行核）。

6. **查证「空间吸附」能否只用于静态面片，从而缓解树叶阴影闪烁**（对照 ```makeup/shaders/common/solid_blocks_fragment.glsl:224-233``` 与 ```miniature/shaders/common/getLightStrength.fsh:11-15```）。直接照搬会让树叶轮廓变方块，但只对静态方块面吸附、对树叶保留逐像素查询，是这两家都没做、而 Astra 的分材质体系（```Astra/shaders/program/lit.vsh:143``` 的 material 位段）天然支持的一种折中。这是本轮最有价值但也最需要验证的一条。
