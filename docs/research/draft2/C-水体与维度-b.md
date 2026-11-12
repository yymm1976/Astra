# C-水体与维度（第二份，-b）：水体/水下 + 末地 + 下界

> 只读研究笔记。外部源码来自本机解包副本（不写入）。Astra 侧只读检索，未修改任何文件。
> 版本锚点：solas ea1b4db main、photon 5c79f54 main、bliss 81e403e Stable、cr c09950d main、piscium f2401e9 main；Astra 取自工作区当前源码。
> 强度约定：**[源码]**＝逐字读到的行；**[推断]**＝据源码推导，可能被编译器优化或默认配置不执行；**[未验证]**＝没做到。

## 0. 结论摘要（先说结果）

1. **Solas 的水面法线是"视差位移 + 4 次高度查表中心差分"，不是 Gerstner**；色散只靠两张噪声图混合，没有波长-频率物理关系。Photon 才有真正的 Gerstner（重力色散 `w=sqrt(g*k)`），且分成"顶点位移 1 波"和"像素法线 3 波 + 视差 4 步"两层。[源码]
2. **Solas 的焦散不是屏幕空间积分，而是在 shadow pass 里把水面本身写成"会聚增益"**，写进 `shadowcolor0`，再由接收方当阴影乘法器用。这个技巧 Astra 已经在用（`shadow_water_caustic_gain`）。[源码]
3. **Photon 的焦散用 `dFdx/dFdy` 的"面积比"（雅可比）算**，代价极低（无额外采样），本质是"折射后面积收缩率"。这是本轮最便宜、最可借的一条。[源码]
4. **Piscium 的焦散是全 GPU 光子追踪 + Hi-Z 屏幕空间求交 + imageAtomicAdd 累加**，每帧一次 compute，分辨率跟阴影图同尺寸。这是质量上限参考，不是性能参考。[源码]
5. **Photon 的水下体积雾把"消光系数 / 散射系数 / 多次散射近似"组织成三常量**（吸收 R/G/B 水下、散射标量），单次 march 内 4 次相位迭代而非 4 次独立 march，且步数随射线长度 16→25 自适应、上限 50 格。[源码]
6. **Solas 的末地黑洞是纯解析 2D 屏幕极坐标近似**：`worldPos.xz/(len+worldPos.y)` 的球极投影 + 若干 pow/sin 环形，无光线追踪、无查表；而 Astra 已经是"离线 atlas 光路 + 逐帧查表"。两者不在一个量级。[源码]
7. **Solas 的下界烟雾是"三次矩形裁剪 + 16 次固定采样"**：距离<128、y∈(40,255)、有体积光照开关才执行，属于"整块裁掉体积光"的实例。[源码]
8. **Astra 的下界体积模块 `global/dimension/nether_volume.glsl` 当前是死代码**（文件自述"no current volume producer"，`shaders.properties` 也注明 inactive）。改它不会有画面效果。[源码]
9. Astra 的水体已覆盖：Beer-Lambert 三段谱（shallow/middle/deep）、Fresnel 介电方程、Caustics 波前 Hessian、ITT 波场、屏幕空间反射预算。**缺口在：没有 Gerstner 色散波、没有水下体积雾的多次散射近似、末地下界体积光被裁掉后无替代层次**。[源码+推断]

---

## 1. 水面波浪模型：Solas 的"噪声视差法线"

**技术目标**：在不做顶点位移的前提下，让水面有看得见的起伏与近处视差，同时让法线在远处自动变平，避免高频噪点。

**实现位置**（solas ea1b4db main）

`shaders/lib/water/waterNormals.glsl:1-31` 高度场：
```glsl
float getWaterHeightMap(vec3 worldPos, vec2 offset) {
    float noise = 0.0;
    vec2 wind = vec2(frameTimeCounter) * 0.5 * WATER_NORMAL_SPEED;
	offset /= 256.0;
	worldPos.xz -= worldPos.y * 0.2;
```
`shaders/lib/water/waterNormals.glsl:17-19`（默认分支 `WATER_NORMALS == 3`）：
```glsl
	float noiseA = texture(noisetex, (vec2(worldPos.x, worldPos.z * 0.75 + worldPos.x * 0.25) - wind) / 256.0 + offset).r;
	float noiseB = texture(noisetex, (worldPos.xz + wind) / 48.0 + offset).r;
    noiseA *= noiseA * 1.5;
```
`shaders/lib/water/waterNormals.glsl:36-39` 视差：
```glsl
	for(int i = 0; i < 4; i++) {
		float height = -1.25 * getWaterHeightMap(parallaxPos, vec2(0.0)) + 0.25;
		parallaxPos.xz += height * viewVector.xy / viewDistance;
	}
```
`shaders/lib/water/waterNormals.glsl:47-55` 四点差分：
```glsl
	float h0 = getWaterHeightMap(waterPos, vec2( WATER_NORMAL_OFFSET, 0.0));
	float h1 = getWaterHeightMap(waterPos, vec2(-WATER_NORMAL_OFFSET, 0.0));
	float h2 = getWaterHeightMap(waterPos, vec2(0.0,  WATER_NORMAL_OFFSET));
	float h3 = getWaterHeightMap(waterPos, vec2(0.0, -WATER_NORMAL_OFFSET));
	float xDelta = (h1 - h0) / WATER_NORMAL_OFFSET;
	float yDelta = (h3 - h2) / WATER_NORMAL_OFFSET;
	vec3 normalMap = vec3(xDelta, yDelta, 1.0 - (xDelta * xDelta + yDelta * yDelta));
```
默认配置（`shaders/lib/common.glsl:459-463`）：
```glsl
#define WATER_NORMALS 3 //[0 1 2 3]
#define WATER_NORMAL_BUMP 0.5 //[0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
#define WATER_NORMAL_OFFSET 0.5 //[0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
#define WATER_NORMAL_DETAIL 0.30 //[0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50]
```

**算法机制**
1. 世界坐标先做 `worldPos.xz -= worldPos.y * 0.2`，即"竖直面上把高度折进水平坐标"，让水墙（流水侧面）也有滚动纹理。这是 Solas 对"瀑布/水墙"的统一处理。
2. 两层噪声：A 是粗尺度（周期约 256 格），B 是细尺度（约 48 格），按 `WATER_NORMAL_DETAIL` 混合。`noiseA *= noiseA * 1.5` 让粗尺度更"尖"（平方运算压低中值、抬高波峰）。
3. 视差：用 **4 次** `getWaterHeightMap` 反向迭代，每次把采样点沿屏幕投影的视线方向推 `height * viewVector.xy/viewDistance`，模拟"眼睛透过波峰看波谷"的位移。
4. 法线：在视差后的位置上再做 **4 次** 高度采样（`±WATER_NORMAL_OFFSET`），中心差分得斜率。
5. 法线强度用 `0.35 * (1 - pow8(fresnel))` 调制（`waterNormals.glsl:57`），即"正对着看时波纹最弱、掠射时最强"——物理上接近但并非严格 Fresnel 加权。

**开销与代价**
- 每像素 **16 次噪声纹理采样**：视差 4 次 × 内部 A/B 两层 = 8，差分 4 次 × 2 层 = 8。[源码计数]
- 无历史缓冲、无 mip 选择、无屏幕足迹过滤：远处水面必然走样（这正是默认必须把 `WATER_NORMAL_OFFSET` 设成 0.5 这种偏大值来压噪的原因）。
- 只影响法线，**不改变几何**：水面永远是水平平面，浪高不产生轮廓或遮挡。

**适用范围与失效边界**
- 默认 `WATER_NORMALS 3` 生效；设 0 时整段被 `#if` 剔除（`gbuffers_water.glsl:229-233`）。[源码]
- `OVERWORLD` 分支额外乘 `(WATER_NORMAL_BUMP + wetness * 0.5)`（`waterNormals.glsl:27`），雨天水波更明显；下界/末地没有这个加成。
- 视差迭代没有收敛判定、没有边界保护：掠射角时位移会非常大，可能采到远离真实水面的位置。这是"水面近处扭曲感过强"的常见来源。[推断]

**与 Astra 的关系**
Astra 已用 Solas 这套的改写版，且加了屏幕足迹带限：
- `Astra/shaders/global/water/caustics.glsl:13-17`：
```glsl
float solas_water_surface_height_resolved(vec3 p, vec2 offset, vec2 resolved) {
    vec2 wind=vec2(frameTimeCounter*0.75*(WATER_WAVE_SPEED*0.01));
    p.xz-=p.y*0.2;
    offset/=256.0;
```
- `Astra/shaders/global/water/caustics.glsl:35`：`if (all(lessThanEqual(resolved, vec2(0.0)))) return face;` —— 远处直接返回几何法线，**比 Solas 省掉全部采样**，这是 Astra 已做对的优化。
- Astra 另外还有 Steadfast 波场（`Astra/shaders/global/water/surface.glsl:79-95` 的 `WATER_RIPPLES`/`WATER_CRESTS` 参数表）和 ITT 波场（`Astra/shaders/lib/itt_water_waves.glsl`）。**三条并存**。

---

## 2. Photon 的 Gerstner 波：色散 + 顶点/像素分层

**技术目标**：让波浪有物理正确的"长波跑得快、短波跑得慢"（深水色散关系），并把几何起伏与法线细节分成两级预算。

**实现位置**（photon 5c79f54 main）

`shaders/include/surface/water_normal.glsl:6-17`：
```glsl
float gerstner_wave(
    vec2 coord,
    vec2 wave_dir,
    float t,
    float noise,
    float wavelength
) {
    // Gerstner wave function from Belmu in #snippets, modified
    const float g = 9.8;

    float k = tau / wavelength;
    float w = sqrt(g * k);
```
`shaders/include/surface/water_normal.glsl:13` 明确写了出处：`// Gerstner wave function from Belmu in #snippets, modified` —— **借用自 Belmu**，不是原创。同一段在 `shaders/include/vertex/displacement.glsl:31-47` 原样复制了一份（顶点用）。

`shaders/include/surface/water_normal.glsl:103-118` 多层叠加：
```glsl
    for (uint i = 0u; i < WATER_WAVE_ITERATIONS; ++i) {
        height += gerstner_wave(
                      coord * frequency,
                      wave_dir,
                      t,
                      wave_noise[i] * noise_strength,
                      wave_length
                  )
            * amplitude;
        amplitude *= persistence;
        frequency *= lacunarity;
        wave_length *= 1.5;
        wave_dir *= wave_rot;
```
`shaders/include/surface/water_normal.glsl:144-147` 求法线（3 次求值）：
```glsl
    const float h = 0.1;
    float wave0 = get_water_height(coord, wave_dir, wave_rot, t);
    float wave1 = get_water_height(coord + vec2(h, 0.0), wave_dir, wave_rot, t);
    float wave2 = get_water_height(coord + vec2(0.0, h), wave_dir, wave_rot, t);
```
`shaders/include/vertex/displacement.glsl:56-63` 顶点只算 1 波：
```glsl
    float wave = gerstner_wave(
        world_pos.xy * wave_frequency,
        wave_dir,
        frameTimeCounter * wave_speed,
        0.0,
        wavelength
    );
    wave = (wave * 0.05 - 0.025) * (skylight * 0.9 + 0.1);
```
默认次数（`shaders/settings.glsl:455`）：`#define WATER_WAVE_ITERATIONS 3 // [1 2 3 4 5 6 7 8]`

**算法机制**
1. `k = 2π/λ`，`w = sqrt(g·k)` —— 深水重力波色散关系。每次叠加时 `wave_length *= 1.5`、`frequency *= lacunarity(1.7)`、`amplitude *= persistence(0.5)`，得到一组互不重复的波长。
2. `height` 用 `sqr(sin(x)*0.5+0.5)`，即**平方后的正弦**——峰尖谷宽，比原始正弦更接近真实波峰。注意这已不是严格 Gerstner（Gerstner 会给水平位移），只是"带色散的正弦高度场"。
3. 每次叠加前 `wave_dir *= wave_rot` 把波向旋转黄金角（`water_normal.glsl:40-47`），避免同向叠加出现规则条纹。
4. 法线用 3 次求值（1 基准 + 2 偏移），**不是** 4 次中心差分，省一次全波求值。
5. 每次 `get_water_height` 内部先做 `WATER_WAVE_ITERATIONS` 次噪声采样（`water_normal.glsl:79-82`）来扰动相位，所以**一次法线 = 3 × 3 = 9 次高度求值 × 3 次噪声采样 = 27 次纹理采样**。[源码计数，默认 ITERATIONS=3]

**开销与代价**
- 27 次纹理采样/像素，比 Solas 的 16 次更多，但换来色散与峰形。
- 视差另算：`get_water_parallax_coord`（`water_normal.glsl:169-207`）用 4 步 while 循环，步数固定 `const int step_count = 4;`，每步再调一次 `get_water_height`（3 波 × 3 采样）——**开着 `WATER_PARALLAX` 时再乘 5**。默认确实开着（`settings.glsl:444` `#define WATER_PARALLAX`）。[源码]
- 顶点位移只有 1 波、1 次噪声（`noise = 0.0` 传入），幅度 `0.05` 格，即 **5 厘米**。所以 Photon 的"几何起伏"极其微弱，主要视觉来自法线。

**适用范围与失效边界**
- `WATER_DISPLACEMENT` 默认开（`settings.glsl:445`）。带 LOD 时向渲染边界衰减（`displacement.glsl:65-72`），避免与原版地形接缝。
- 法线强度受 `normal_influence` 调制，掠射角保护在 `water_normal.glsl:156-160`：
```glsl
    normal_influence *= smoothstep(
        0.0,
        0.15,
        abs(dot(flat_normal, normalize(world_pos - cameraPosition)))
    ); // prevent noise when looking horizontally
```
- **失效边界**：`WATER_WAVE_ITERATIONS` 提高会线性放大采样数（8 时 72 次采样）；流水让 `wave_rot` 变成单位矩阵（`water_normal.glsl:40-41`），此时没有黄金角去相关，容易出现条纹。

**与 Astra 的关系**
Astra **没有 Gerstner**（全仓 grep `gerstner|Gerstner` 零命中）。Astra 走两条路：
- Steadfast 值噪声波场 + 解析梯度（`Astra/shaders/global/water/surface.glsl:44-49`，注释说明"一次 textureGather 取四角，比中心差分省一半 ALU"）；
- ITT 六层波场 + 解析微分（`Astra/shaders/lib/itt_water_waves.glsl:3-5`）。

即 Astra 是"用噪声+解析导数代替色散波"，采样更省但**没有波长-速度的物理关系**。这是取舍点，不是缺陷。

---

## 3. 水面法线 / 反射 / 折射的一致性（Solas 的实现顺序）

**技术目标**：同一帧里，法线既驱动高光、又驱动反射方向、又驱动折射偏移，三者必须用同一个法线，否则会出现"高光在动、折射不动"的割裂感。

**实现位置**（solas ea1b4db main）

`shaders/programs/gbuffers_water.glsl:227` 基础 Fresnel（用**几何法线**）：
```glsl
	float fresnel = clamp(1.0 + dot(normalize(normal), nViewPos), 0.0, 1.0);
```
`shaders/programs/gbuffers_water.glsl:236` 折射量（用**波法线与几何法线之差**）：
```glsl
		refraction = (newNormal.xy - normal.xy) * 0.5 + 0.5;	
```
`shaders/programs/gbuffers_water.glsl:274-276` 反射用 Fresnel（几何法线 × Snell 窗）：
```glsl
		float fresnel = clamp(1.0 + dot(normalize(normal), nViewPos), 0.0, 1.0) * snellWindow;
		getReflection(albedo, viewPos, newNormal, fresnel, lightmap.y);
		albedo.a = fmix(albedo.a * snellWindow, 1.0, fresnel);
```
`shaders/programs/gbuffers_water.glsl:268` Snell 窗：
```glsl
		float snellWindow = clamp(pow4(length(worldPos.xz) * 0.05), 0.05 + float(isEyeInWater == 0) * 0.95, 1.0);
```
`shaders/lib/pbr/waterReflection.glsl:63-65` 合成：
```glsl
	vec3 finalReflection = max(mix(falloff, reflection.rgb, reflection.a), vec3(0.0));
	albedo.rgb = mix(albedo.rgb, finalReflection, fresnel);
```

**算法机制**
1. 先用几何法线算 `fresnel`，传给 `getWaterNormal`，后者用 `0.35*(1-pow8(fresnel))` 决定波纹强度——**掠射角波纹更强**。
2. 折射用 `newNormal.xy - normal.xy` 的差，而非 `newNormal.xy` 本身。这样"平面水"不产生折射偏移，只有波峰波谷才偏——避免整片水面被整体推歪。**这是 Astra 值得对照的一条**。
3. `snellWindow` 用小半径 `length(worldPos.xz)` 的四次幂做径向渐变，在水下把反射压到 0.05，模拟"水下看水面是透明窗"。这是**纯艺术近似**，不是物理 Snell 窗（真正的窗边界由临界角决定，与距离无关）。[源码+推断]
4. 反射先屏幕空间 ray march，未命中回退天空 `getAtmosphere()`，再按 `waterSkyOcclusion` 混合（`waterReflection.glsl:38-54`）。

**开销与代价**
- SSR 上限写死 30 步（`shaders/lib/pbr/raytracer.glsl:47` `for (int i = 0; i < 30; i++) {`），外层 `Raytrace(..., 6, 1.0, 0.1, 1.6, ...)`（`waterReflection.glsl:11`）传 `refinementSteps = 6`。
- 每次 SSR 迭代一次 depth 采样，命中后再 `texture(gaux1, ...)` 取色。
- `gaux1` 在 Solas 里**没有找到写入方**（全仓 grep 只有读取与 uniform 声明）——[未验证]，不下结论。

**适用范围与失效边界**
- 只在 `#ifdef WATER_REFLECTIONS`（默认开，`common.glsl:458`）下执行。
- `isEyeInWater == 0` 才做天空回退（`waterReflection.glsl:38`）：水下直接用 `albedo.rgb` 或维度底色做 falloff，没有天空反射。这是**水下反射被刻意简化**处。
- 屏幕边缘：`borderFade = clamp(13.333 * (1.0 - border), 0.0, 1.0)` 与 `screenFade` 相乘，边缘淡出到 falloff 色，没有重投影/历史补偿。

**与 Astra 的关系**
Astra 对应实现更细：
- `Astra/shaders/global/water/raytrace.glsl:18-27` 按质量档给明确预算（`ASTRA_WATER_RAW_BUDGET` 12/20/40，`RAW_REFINE` 4/4/8），注释说明 ceiling 只降不升。
- `Astra/shaders/global/water/refraction.glsl:33-37` 用 `textureGather` 一次取 2×2 深度足迹，而非 Solas 的单点采样；该文件 54-58 行注释明确解决"轮廓像素把颜色和深度混错"。
- Astra 的折射接受判定在 `Astra/shaders/program/water.glsl:38-40`：`water_side_acceptance` 用 `smoothstep(-0.02, 0.02, ...)` 做 2 厘米软过渡，**比 Solas 的硬 `z1 > z0` 更稳**。

---

## 4. 吸收散射：三种系数组织方式

**技术目标**：让"浅水清、深水暗、水下偏青"有可调、可复现的参数结构，而不是拍脑袋调色。

### 4.1 Solas：一路指数 + 三通道不同幂（艺术化）

`shaders/lib/water/waterFog.glsl:1-6`：
```glsl
vec4 getWaterFog(inout vec3 colorMult, vec3 viewPos) {
	float absorption = length(viewPos) * 0.01 * WATER_FOG_DENSITY;
		  absorption = 1.0 - exp(WATER_FOG_EXPONENT * 2.0 * absorption);
	colorMult.r *= 1.0 - absorption;
	colorMult.g *= 1.0 - absorption * absorption * 0.5;
	colorMult *= 1.0 - absorption * absorption * absorption * 0.5;
```
调用方（`shaders/programs/gbuffers_water.glsl:191-195`）：
```glsl
		waterFog = getWaterFog(colorMult, viewPos - oViewPos);
		albedo.rgb = waterFog.rgb * 3.0;
		albedo.g *= 1.0 + (0.5 - waterFog.a * 0.35); //Correciton
		albedo.a = min(0.1 + 3.0 * WATER_A * waterFog.a * (0.75 - float(isEyeInWater == 1) * 0.25), 0.8);
```
默认 `WATER_FOG_EXPONENT -2.00`、`WATER_FOG_DENSITY 3.00`（`common.glsl:467-468`）。

**机制**：**不是 Beer-Lambert**。用 `exp(-2.0 * density * 0.01 * dist)` 得单一标量，再红乘 `(1-a)`、绿乘 `(1-a²/2)`、全体乘 `(1-a³/2)`，即"红衰减最快、绿次之、蓝最慢"的**差分幂次**近似，Solas 自己的艺术构造，无物理出处。[源码]
**代价**：2 次 `exp`、无纹理、无历史。
**边界**：距离是 `viewPos - oViewPos`，即"相机到背景点"的向量长度，**不是水柱厚度**。空中斜看浅水时该长度远大于实际水深，会把浅水渲成深水。这是 Solas 水体"整体偏青"的根源。[推断，依据 waterFog.glsl:2 与 gbuffers_water.glsl:191 传参]

### 4.2 Photon：标准 Beer-Lambert，三个常量

`shaders/include/fog/water_fog_vl.glsl:24-32`：
```glsl
    const vec3 absorption_coeff
        = vec3(
              WATER_ABSORPTION_R_UNDERWATER,
              WATER_ABSORPTION_G_UNDERWATER,
              WATER_ABSORPTION_B_UNDERWATER
          )
        * rec709_to_working_color;
    const vec3 scattering_coeff = vec3(WATER_SCATTERING_UNDERWATER);
    const vec3 extinction_coeff = absorption_coeff + scattering_coeff;
```
默认（`settings.glsl:469-472`）：R 0.20 / G 0.08 / B 0.04 / 散射 0.03；水面上另一套（`settings.glsl:464-467`）R 0.39 / G 0.14 / B 0.07 / 散射 0.01。

**机制**：两组系数（水面上/水下）分开，`extinction = absorption + scattering`，单位每米，直接进指数。
生物群系水色在 `shaders/include/fog/simple_fog.glsl:185-195` 用反解转吸收系数：
```glsl
    const vec3 forest_absorption_coeff
        = -density_scale * log(vec3(0.1245, 0.1797, 0.7108));
...
    vec3 biome_absorption_coeff = -density_scale * log(biome_water_color + eps)
        - forest_absorption_coeff;
```
即"给定想要的水色，反推出让其看起来如此的吸收系数"——**逆向参数化**，比手调 RGB 好用。

### 4.3 多次散射近似（Photon 有，Solas 没有）

`shaders/include/fog/simple_fog.glsl:216-220` 与 `238`：
```glsl
    // Multiple scattering approximation from Jessie
    vec3 scattering_albedo = scattering_coeff / extinction_coeff;
    vec3 multiple_scattering_factor = 0.84 * scattering_albedo;
    vec3 multiple_scattering_energy
        = multiple_scattering_factor / (1.0 - multiple_scattering_factor);
...
    scattering *= 1.0 + multiple_scattering_energy; // multiple scattering
```
**机制**：几何级数 `f/(1-f)` 做"无限次散射能量和"，`f = 0.84 × 单散射反照率`。经验闭式解，**不是**多步 ray march。代价 3 次除法。出处：注释写明 `from Jessie`。

### 4.4 Astra 现状

`Astra/shaders/global/water/absorption.glsl:14-19` 已有按维度分离的 Beer-Lambert：
```glsl
vec3 water_absorption_coefficient() {
    #ifdef DEBUG_DISABLE_WATER_ABSORPTION
    return vec3(0.0);
    #else
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    return vec3(0.032, 0.014, 0.012) * (WATER_ABSORPTION * 0.01);
```
`Astra/shaders/global/water/absorption.glsl:101-108` 浅/中/深连续混合：
```glsl
    vec2 depthBlend = vec2(appearanceDepth / (appearanceDepth + 4.0),
                          depthSquared / (depthSquared + 324.0));
    vec3 pathTransmission = exp(-appearanceDepth * water_surface_absorption(depthBlend))
                          * (1.0 - haze);
    scattering = water_body_color(depthBlend) * clamp(incidentLight, 0.0, 2.0)
               * (1.0 - pathTransmission);
```
Astra 的 `appearanceDepth` 来自"水面自身平面到背景命中点的垂直距离"（`program/water.glsl:56-59` 注释明确修掉了"斜看整条运河被当水深"的旧 bug），**这一点比 Solas 正确**。
**缺口**：Astra **没有** Photon 那样的多次散射能量项（grep `multiple_scattering` 零命中）。

---

## 5. 水下体积光与雾的协调

### 5.1 Photon：单次 march，内部做多次散射迭代

`shaders/include/fog/water_fog_vl.glsl:39-48`：
```glsl
    if (sky || ray_length > max_ray_length) {
        ray_length = max_ray_length;
    }
    // Adjust step count based on ray length
    uint step_count
        = uint(float(min_step_count) + step_count_growth * ray_length);
    step_count = min(step_count, max_step_count);
```
常量（`water_fog_vl.glsl:9,17-19`）：`max_ray_length = 50.0`、`min_step_count = 16`、`max_step_count = 25`、`step_count_growth = 0.5`。

`shaders/include/fog/water_fog_vl.glsl:125-142` 四次相位迭代：
```glsl
        for (uint i = 0u; i < multiple_scattering_iterations; ++i) {
            float mie_phase
                = 0.7 * henyey_greenstein_phase(LoV, 0.5 * anisotropy)
                + 0.3 * isotropic_phase;
            // Sunlight/moonlight
            scattering += light_color * caustics * mie_phase
                * light_transmittance * transmittance * scattering_amount;
```
`water_fog_vl.glsl:123-124` 与 `138-141`：
```glsl
        float anisotropy = 1.0;
        float scattering_amount = 1.0;
...
            anisotropy *= 0.5;
            scattering_amount *= 0.5;
            light_transmittance = sqrt(light_transmittance);
```
`water_fog_vl.glsl:147-149` 收尾：
```glsl
    scattering
        *= (1.0 - step_transmittance) * scattering_coeff / extinction_coeff;
    transmittance = pow(transmittance, vec3(0.75));
```

**机制**
1. 每条射线 16~25 步（按长度线性增长，50 格封顶）。
2. 每步读 **2 次阴影图**（`texelFetch(shadowtex0)` + `texelFetch(shadowtex1)`，`water_fog_vl.glsl:87-88`），并用 `abs(depth0 - shadow_screen_pos.z)` 反推"沿光线到遮挡物的距离"，再乘 `light_dir.y` 得"到天空的近似穿透距离"（`water_fog_vl.glsl:96-104`）——**用阴影图反推体积厚度**，不需额外深度胶囊。
3. 每步 **2 次噪声采样**做焦散（`water_fog_vl.glsl:117-121`）。
4. 每步 **4 次**相位/散射迭代（不是 4 次 march），每次把 `anisotropy`、`scattering_amount` 减半、`light_transmittance` 开方——"多次散射 = 各向异性递减 + 透射率递减"的经验近似。**这 4 次迭代不额外采样纹理**，纯 ALU。
5. `pow(transmittance, 0.75)` 是艺术补偿（远处不至于全黑）。

**开销**：每像素 16~25 × (2 次阴影 fetch + 2 次噪声 + 4 次 ALU 相位) ≈ **32~50 次纹理读取**，在 **1/1 分辨率**的 `c0_vl` pass 里跑。Photon 最贵的一项。

**与 Astra 的关系**
Astra 独立光束在 `Astra/shaders/global/water/light_shafts.glsl:1-7` 声明出处（IterationT 3.2.0 + Solas 的光照分离），步数用 `ASTRA_SHAFT_SAMPLES` 控制（`light_shafts.glsl:23-27`），优化档压到 **7 步**：
```glsl
#if !defined ASTRA_OVERWORLD_OPTIMIZED || UNDERWATER_SHAFT_SAMPLES < 7
    #define ASTRA_SHAFT_SAMPLES UNDERWATER_SHAFT_SAMPLES
#else
    #define ASTRA_SHAFT_SAMPLES 7
#endif
```
**Astra 比 Photon 省 2~3 倍步数**，代价是没有那 4 次相位迭代——这可能正是"水下光束偏硬/偏单薄"的原因之一。[推断，未做画面对比]

### 5.2 Solas：水下体积光复用主 VL，用 `isEyeInWater` 改参数

`shaders/lib/atmosphere/volumetrics.glsl:56-58`：
```glsl
    intensity = intensity * float(isEyeInWater == 0) + float(isEyeInWater == 1) * (1.0 + VoLClamped * VoLClamped * 2.0) * (0.25 + sunVisibility * 1.75);
    #else
    intensity *= fmix(pow4(1.0 - VoUClamped), 0.125 + timeBrightness * 0.5, float(isEyeInWater == 1));
```
`shaders/lib/atmosphere/volumetrics.glsl:63`：
```glsl
    distanceFactor = float(isEyeInWater) * 5.0 + closedSpaceFactor * 2.0;
```
`shaders/lib/atmosphere/volumetrics.glsl:232` 水下把光束染成水色：
```glsl
                    vlSample = clamp(shadow1 * (1.0 - shadow0) * doShadowColor * shadowCol * shadowCol * mix(vec3(0.25), waterColor * lShadowCol, float(isEyeInWater == 1)) + shadow0 * vlCol * float(isEyeInWater == 0), 0.0, 1.0);
```
**机制**：Solas 没给水下单独写 march，而是用三个标量改主 VL：强度乘 `(1+2VoL²)`、最大距离缩小 5 倍（`distanceFactor` 越大 `maxDist` 越小，见 `volumetrics.glsl:182-184`）、颜色混入 `waterColor`。**最省事**：0 额外代码路径。

---

## 6. 末地：Solas 的解析黑洞 vs Astra 的离线光路

### 6.1 Solas：纯解析屏幕空间近似（无追踪、无查表）

`shaders/lib/atmosphere/endNebula.glsl:50-61`：
```glsl
    vec3 blackHoleColor = vec3(5.6, 3.2, 0.7) * endLightCol;
    float absVoU = abs(VoU);
    float sqrtabsVoU = sqrt(absVoU);
    float blackHoleSize = END_BLACK_HOLE_SIZE;
    float hole = pow(pow4(pow32(VoS)), blackHoleSize);
    float gravityLens = hole;
    hole *= hole;
    hole *= hole;
    vec3 wSunVec = mat3(gbufferModelViewInverse) * sunVec;
    vec2 sunCoord = wSunVec.xz / (wSunVec.y + length(wSunVec));
    vec2 blackHoleCoord = worldPos.xz / (length(worldPos) + worldPos.y) - sunCoord;
```
`shaders/lib/atmosphere/endNebula.glsl:122-134` 环与光子环：
```glsl
    float torus = 1.0 - clamp(length(blackHoleCoord), 0.0, 1.0);
            torus = pow(pow(torus * torus, 1.0 + (180.0 - abs(sunPathRotation)) / 8.0 * (0.5 + 0.5 * sqrtabsVoU)), sqrt(blackHoleSize) * 1.5);
    vec2 noiseCoord = blackHoleCoord - hole * hole;
...
    color += fmix(blackHoleColor, vec3(4.0 + hole * hole * 2.0), hole * hole) * hole * hole * 3.0 * blackHoleNoise;
    color *= 1.0 - hole;
    color += vec3(photonRing);
```
`shaders/lib/atmosphere/stars.glsl:16-20` 星场被"洞"吸走：
```glsl
                #ifdef END_BLACK_HOLE
                float baseRing = pow10(pow32(VoL));

                planeCoord *= clamp(1.0 - baseRing * 4.0, 0.0, 1.0);
                planeCoord += baseRing;
                #endif
```

**机制**
1. `worldPos.xz / (len + worldPos.y)` 是**球极投影**（方向向量映到 2D 平面），得到"仰角压缩"的天空坐标。黑洞位置是先算太阳方向再同样投影得到的 `sunCoord`，然后相减——所以黑洞**永远在太阳方向**。
2. `hole = pow(pow4(pow32(VoS)), size)` 中 `VoS = clamp(dot(view, sunVec), 0, 1)`，`pow32` 让它极窄，`pow4` 再压，指数 `size` 可调大小。本质是 `cos(θ)^(128*size)` 的锥形衰减，**不是引力透镜**。
3. `gravityLens = hole` 只用来位移星云坐标（`endNebula.glsl:80` `nebulaCoord += warping * gravityLens;`）——"引力透镜"实际只是把星云纹理在洞附近拉一下。
4. 光子环是 `pow2(hole*3)` 加阈值截断（`endNebula.glsl:117-119`），纯手调亮环。
5. 吸积盘（`END_DISK`）是另一套体 ray march（`volumetricClouds.glsl:409-547`），64 步上限。

**开销**：解析部分约 2 次噪声采样 + 若干 `pow`（`pow32` 多数驱动展开成乘法）。吸积盘另算：最多 64 步 × 2 次噪声（`getEndCloudSample` 调两次，主光一次、阴影方向一次）= **约 128 次采样**，且每步 1 次阴影图读取（`volumetricClouds.glsl:509`）。

**失效边界**
- `#ifdef END_BLACK_HOLE` 才生效；默认开（`common.glsl:326`），但 `common.glsl:829-835` 在非 END 维度 `#undef` 掉。
- `END_TIME_TILT`、`END_67` 默认**关闭**（`common.glsl:329-330` 是注释行），倾斜动画不执行。[源码]
- 黑洞位置锁死太阳方向，**永远不会出现在视野侧面**，也无法"飞过去"。

### 6.2 Astra：离线 atlas + 逐帧查表

`Astra/shaders/global/dimension/end_kerr.glsl:3-9`：
```glsl
// Static curved-path transfer with restrained Kerr-like image deformation.
// The atlas is produced by qa/tools/build_end_transfer.py, never traced per frame.
const float END_KERR_SPIN = 0.94;
uniform sampler2D astraEndTransfer;
uniform sampler2D astraEndFlow;
uniform sampler2D astraEndFlowMips;
uniform sampler2D astraEndTransferMeta;
```
`Astra/shaders/global/dimension/end_blackhole.glsl:22-23`：
```glsl
// Static light-path transfer plus animated emission: runtime contains no light-ray march.
#include "/global/dimension/end_kerr.glsl"
```
`Astra/shaders/global/dimension/end_disc_profile.glsl:11`：
```glsl
const float END_SHADOW_TAN = 0.32; // 17.74-degree apparent shadow radius.
```

**对比结论（可改变工程判断）**：Solas 的"黑洞"是**屏幕空间美术贴片**，Astra 已是**带光路积分的离线烘焙**。两者不能互抄。Astra 真正缺的不是黑洞（已远超 Solas），而是**星场与星云的稳定性**——Solas 用 `planeCoord += frameTimeCounter * 0.001`（`stars.glsl:23`）让星场缓慢漂移，Astra 用离线星表 + `colortex31` 查表（`Astra/shaders/lib/end_star_catalogue.glsl:5-23`）。[源码]

---

## 7. 下界：Solas 的三重裁剪 + Astra 的死代码

### 7.1 Solas：`NETHER_SMOKE` 在固定范围内 16 步 march

`shaders/lib/atmosphere/volumetrics.glsl:1-7` 噪声函数：
```glsl
#ifdef NETHER_SMOKE
float getNetherFogSample(vec3 fogPos) {
    float t = frameTimeCounter;

    fogPos.y -= t * 2.0;
    fogPos.x += cos(fogPos.y * 0.09 + fogPos.z * 0.007 + t * 0.13) * 6.0;
```
`shaders/lib/atmosphere/volumetrics.glsl:287-291` 三重裁剪：
```glsl
            if (lWorldPos < 128.0 && rayPos.y > 40.0 && rayPos.y < 255.0) {
                float fogSample = getNetherFogSample(rayPos * NETHER_SMOKE_FREQUENCY + wind2 * NETHER_SMOKE_SPEED);
                float fade = clamp(rayPos.y / 40.0, 0.0, 1.0) * (1.0 - clamp(rayPos.y / 255.0, 0.0, 1.0));
                vlSample += netherColSqrt * netherColSqrt * netherColSqrt * netherColSqrt * fogSample * (1.0 + fogSample) * 16.0 * fade;
            }
```
`shaders/lib/atmosphere/volumetrics.glsl:135` 与 `172`：
```glsl
    vlIntensity = NETHER_SMOKE_STRENGTH;
...
    int sampleCount = VL_SAMPLES;
```
`shaders/lib/atmosphere/volumetrics.glsl:168` 下界风场：
```glsl
        vec3 wind2 = vec3(-sin(frameTimeCounter * 0.3) * 0.2, -4.0 * frameTimeCounter, cos(frameTimeCounter * 0.5) * 0.4);
```
**还有一道整块关断**（`shaders/lib/common.glsl:837-838`）：
```glsl
#ifdef NETHER
#undef VL
```

**机制**
1. **整块关断**：`#ifdef NETHER` 时 `#undef VL`，主体积光在下界**完全不编译**。这是"整块裁掉体积光"的实例。
2. 下界烟雾**复用 VL 的 march 循环**（`vlSample += ...`），但 `vlIntensity` 被覆写成 `NETHER_SMOKE_STRENGTH`（默认 0.8，`common.glsl:341`），即"借循环、换光源"。
3. **三重空间裁剪**：距离 <128、y∈(40,255)，每步只做 **1 次** `getNetherFogSample`（内部 `n0`+`n1` = 2 次采样 + 插值）。
4. 步数 `VL_SAMPLES` 默认 8（`common.glsl:272`），`LOW` 档直接 `!VL` 关掉（`shaders.properties:14`）。

**开销**：8 步 × 2 次噪声 = 16 次采样/像素，**且 y<40 或 y>255 或距离>128 的像素一次都不采**。这就是"低可见度环境的层次与性能控制"的答案：**用空间范围换工作量**。

### 7.2 Bliss：三个独立密度项、一次 march 里加三遍

`shaders/lib/nether_fog.glsl:81-88`：
```glsl
			float plumeDensity = min(densityVol * pow(min(max(100.0-progressW.y,0.0)/30.0,1.0),4.0), pow(clamp(1.0 - length(progressW-cameraPosition)/far,0.0,1.0),5.0));
			plumeDensity *= NETHER_PLUME_DENSITY;
			float plumeVolumeCoeff = exp(-plumeDensity*dd*dL);
			vec3 lighting = vec3(1.0,0.4,0.2) * exp(-15.0*densityVol) * (clearArea*clearArea*0.9+0.1);
			color += (lighting - lighting * plumeVolumeCoeff) * absorbance;
			absorbance *= plumeVolumeCoeff;
```
`shaders/lib/nether_fog.glsl:92` 与 `103`：
```glsl
			float hazeDensity = 0.001;
...
			float ceilingSmokeDensity = 0.001 * pow(min(max(progressW.y-40.0,0.0)/50.0,1.0),3.0);
```
`shaders/lib/nether_fog.glsl:71-73` 指数分布步进：
```glsl
	for (int i = 0; i < SAMPLECOUNT; i++) {
		float d = (pow(expFactor, float(i+dither)/float(SAMPLECOUNT))/expFactor - 1.0/expFactor)/(1-1.0/expFactor);
		float dd = pow(expFactor, float(i+dither)/float(SAMPLECOUNT)) * log(expFactor) / float(SAMPLECOUNT)/(expFactor-1.0);
```
**机制**：一个循环叠三层介质（plume / haze / ceiling），每层各自 `exp(-density*dd*dL)` 再乘当前 `absorbance`。haze **故意不更新 absorbance**（注释 `dont make haze contrube to absorbance.`），是纯叠加。`SAMPLECOUNT = 16` 写死（`nether_fog.glsl:46`）。

### 7.3 Astra 现状：`nether_volume.glsl` 是死代码

`Astra/shaders/global/dimension/nether_volume.glsl:3-4`：
```glsl
// Retired C3 research module. The active Nether uses homogeneous fog; this file
// has no current volume producer, sampler bindings or program include.
```
`Astra/shaders.properties:886`：
```
# The legacy nether_volume.glsl module is inactive; no active pass samples its noise.
```
全仓 grep `nether_volume` 只有该文件自身定义和这条注释，**没有任何 include**。[源码]

Astra 下界当前走**均匀雾 + 方向光照模型**（`Astra/shaders/global/dimension/nether.glsl:73` `float densityScale = NETHER_FOG_DENSITY * 0.01 * astra_nether_biome_density();`），以及手工的熔岩方向光（`nether.glsl:156-158`）：
```glsl
	float lavaDir = absNdotN * 0.5 + max(0.0, -NdotU);
	sceneLighting += NETHER_LAVA_LIGHT_COLOR * (lavaDir * lavaDir)
	               * (0.7 + 0.35 * NETHER_VS_BRIGHTNESS);
```
**本轮最重要的工程判断**：Astra 下界"层次不足"不是体积雾写得不好，而是**体积雾根本没接上**。要提升下界观感，第一步是「把 `astra_bliss_fog` 接进 composite 链」，不是调参。[源码+推断]

---

## 8. 节省/花费清单

| 实现 | 减少了什么 | 增加了什么 | 频次/分辨率 |
|---|---|---|---|
| Solas 波浪 | 只用 2 张噪声图，无几何位移 | 每像素 16 次采样 | 全分辨率，每帧 |
| Photon Gerstner | 顶点只 1 波 | 法线 9 次高度求值 ×3 采样 = 27 次 | 全分辨率，每帧 |
| Photon 焦散（雅可比） | **无额外采样**，只用 dFdx/dFdy | ALU | shadow pass，每纹素 |
| Piscium 焦散 | — | 全屏光子追踪 + Hi-Z，`imageAtomicAdd` | 阴影图分辨率，每帧 |
| Solas 焦散 | 复用 shadow pass | shadowcolor0 写 1 遍 | 阴影图分辨率 |
| Photon 水下雾 | 步数 16→25 自适应、50 格封顶 | 每步 2 阴影 fetch + 2 噪声 + 4 次 ALU 相位迭代 | 1/1 分辨率 |
| Solas 下界烟雾 | y∉(40,255) 或 >128 格直接跳过；`#undef VL` 整块关断 | 8 步 × 2 采样 | 1/1 分辨率 |
| Astra 水面法线 | 远处 `resolved<=0` 直接返回几何法线，0 采样 | — | 全分辨率 |
| Astra 光束 | 优化档步数压到 7（Photon 16~25） | 少 4 次相位迭代 | 1/4~1/2 分辨率（任务背景所述） |

---

## 9. 建议主代理重点复用的 3~6 条

1. **Photon 的"雅可比焦散"（`photon shaders/program/shadow.fsh:139-148`）值得试**：`old_area`/`new_area` 用 `dFdx/dFdy` 求，零额外采样；Astra 现在用 Hessian 波前曲率（`Astra/shaders/lib/water_wave_lens.glsl:44-48`）。两者可互补——Hessian 给"会聚趋势"，雅可比给"实际屏幕面积比"，后者天然带抗锯齿。注意 Photon 默认 `//#define WATER_CAUSTICS`（`settings.glsl:446`）是关的。
2. **把 Photon 的 4 次相位迭代搬进 Astra 的 7 步光束**（`photon water_fog_vl.glsl:125-142`）：纯 ALU、零额外纹理采样，能直接改善"光束单薄"，成本几乎为零。
3. **接上 Astra 已有的 `astra_bliss_fog`**（`Astra/shaders/global/dimension/nether_volume.glsl:63`）：已写好、已调参（plume 0.55 / haze 0.90 / ceiling 0.70），只是没被 include。**最低成本的下界观感提升**。
4. **Solas 的"折射用波法线减几何法线"**（`solas programs/gbuffers_water.glsl:236`）比直接用波法线稳：应检查 Astra `program/water.glsl` 是否也是增量式；若是全量式，浅水会整体被推歪。
5. **Photon 的 `biome_water_coeff` 反解**（`simple_fog.glsl:185-195`）：把"想要的群系水色"反解成吸收系数，比手调 RGB 更不易调崩。Astra 的 `water_surface_absorption` 目前是硬编码三段谱。
6. **不要照搬 Solas 的黑洞**：`endNebula.glsl` 是纯 2D 屏幕近似、黑洞锁死太阳方向（`endNebula.glsl:60-61`），Astra 的离线 atlas 已更强。若末地"空间感不足"，方向应是**星场稳定性**（Solas 的 `planeCoord += frameTimeCounter * 0.001` 缓慢漂移），而非黑洞本身。

---

## 10. 未验证 / 缺口

- **未验证**：Solas `gaux1` 的写入方未在源码定位（`waterReflection.glsl:24` 读取，全仓无写入语句）。可能是 Iris 的 colortex 别名，本次没证实。
- **未验证**：所有"更好/更差"判断都没做画面 A/B，只有源码级推断。
- **未验证**：Piscium `CausticsPhotonTrace` 实际帧时间——只读代码，没跑。
- **未验证**：Photon `WATER_CAUSTICS` 默认注释掉（`settings.glsl:446`），默认构建里焦散不执行；引用其雅可比做法时必须先承认这点。
- **未核查**：Astra 是否有 `WATER_NORMALS` 之外的第二套波浪（未逐文件比对 `surface.glsl` 全部配置分支）。
