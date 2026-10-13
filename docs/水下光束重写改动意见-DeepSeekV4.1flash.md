# 水下光束重写改动意见

> **标注（产出模型）：DeepSeek V4.1 flash**
> 文档性质：一次性改动意见（提案）。**本轮未改任何着色器代码**，只读代码与两份参考后给出结论与方案。
> 写入日期：2026-10-10。工作区状态：分支 `codex/fix-render-handoff`，工作树含上一轮未提交的光束重写改动。
> 生效范围建议：用户在本文末尾「需要裁决的四项」给出选择后，可执行内容并入 [实现与限制](实现与限制.md)，执行结果并入 [当前工作](当前工作.md)，本文随后可删。

---

## 0. 结论摘要

现版本把「束形从哪来」换成了一个两种参考都没有的机制：**一张预烘的 2D 波面光量图（其中 R×G 的乘积自成束形）**，再用 7 个区间的端点遮挡线性插值去乘它。结果是束的明暗边界不再由真实光路（地形/树叶/船底/方块在阳光方向上的遮挡）决定，而由世界空间的一张固定纹路决定——所以它必然表现为：**成排的、与场景无关的粗亮条（柱子感）、位置随机且不随遮挡改变（乱）、图案与太阳/云/遮挡无关（固定）、最细的两层波面被生产端自己的抗混叠滤波滤掉、再被 mip 与四分之一分辨率抹平（无质感）**。

本文对其中三处数字做过一次按真实噪声贴图（`Astra/shaders/textures/itt-water-noise.png`）的数值复算，据此修正了早期版本的软限幅后果、包络漂移速度与碰撞距离公式，并新发现「生产端 Nyquist 滤波砍掉 ITT 层 1/2」这一项（§2.8、§11）；五份同类文档的交叉复核见 [水下光束同类意见复核](水下光束同类意见复核-DeepSeekV4.1flash.md)。

两份参考的水下体积光都**没有**「预烘束形图」这一层：

- **ITT 3.2**：每个样点做一次真实影图遮挡测试（`UnderwaterVolumetricFog.glsl:63-68`），再乘该样点沿折射阳光方向投到波面的**碰撞光量**（`:72-74`），束形 100% 来自遮挡几何；纹理由波面随时间流动产生。
- **Solas**：每个样点用 `shadowtex1`（不透明）与 `shadowtex0`（含半透明水）之差 `shadow1·(1−shadow0)` 取出「穿过水面进来的那一束光」，并在水下**关闭**无遮挡基础项（`volumetrics.glsl:232`）——束形由水面与地形在阳光方向的真实透光决定。

现版本相比上一轮设计（`design.md:297`，2026-09-07 的 E2 决议）**是回退**：原设计明确要求「`shadowtex1` 阻止实体漏光，`shadowtex0` 与 `shadowcolor0.R` 确认光线经过水面」，而当前 `global/water/light_shafts.glsl` 只用了 `shadowtex1`，把「光从水面进来的确认项」整个丢掉了。

因此建议不是继续调这张图，而是**删除这张图承担的「束形」职责**，回到两份参考一致的架构：**逐样点真实传输（Solas 的透光/遮挡分工）+ 流动波面光量（ITT 的碰撞光量）**，并把 ITT 的大波峰从「独立取幂的包络」还原为「只通过波面法线/碰撞光量起作用」。

现成可行、代价可控的第一步（阶段 0）只需改 `light_shafts.glsl` 与生产者，就能去掉柱子感与无质感的大半，且不动数据流。

---

## 1. 本文依据

| 对象 | 位置 | 说明 |
|---|---|---|
| ITT 3.2.0 | `_analysis/video-2026-10-01/iterationt/source/shaders/` | 用户指定参考之一的**本地原实现** |
| Solas V2.2b | `reference_shaderpacks/solas-shader/shaders/` | 用户指定参考之二 |
| 现行实现 | `Astra/shaders/` | 分支 `codex/fix-render-handoff` 工作树 |
| 现行文档 | `docs/当前工作.md`、`docs/实现与限制.md`、`docs/参考与取舍.md` | 只用于对齐现行边界，不作为观感结论 |
| 设计合同 | `.specs/astra-shader/design.md`（§2.2/§2.3/§4.3） | E2/SC-33 决议：本文多处引用其原文以指出回退 |

**两条硬约束（来自现行文档与代码，影响方案选择）：**

1. **水下没有时域抗锯齿可用。** `lib/taa_jitter.glsl:11,28` 在 `isEyeInWater != 0` 时返回零抖动；`program/taa_resolve.fsh:101-106` 对非空气介质直接放弃历史。因此 **ITT 的「逐帧抖动 + TAA 累积」不可照搬**（正式版还要考虑官方 TAA 同理退出）。
2. **性能目标是原生 1080p 平均 ≥144 FPS**（`docs/当前工作.md:6`）。所以方案必须给出样点数与分辨率的分档，并且不能靠「更多步数」掩盖结构错误。

---

## 2. 现行实现到底在算什么（逐行取证）

调用链：`program/itt_water_normal_cache.fsh`（prepare4，512×512 → colortex29 生产者）→ `program/scattering.fsh`（composite2，逐像素积分写 colortex1）→ `program/display.fsh:133-142` 或 `program/water_composite.fsh:20-30`（`water_shafts_resolve` 四角重建）→ `lib/solas_water.glsl:98-118`（`+ shafts`）。

### 2.1 源：一张图，束形 = R×G

`program/itt_water_normal_cache.fsh:32-50` 每个 texel 输出：

- `R = transmission × energy`
  - `transmission = 1 − water_fresnel(dot(lightDir, normal))`（`:36-37`，物理合理），
  - `energy = bound((0.2 + 2.8·landingOffset)³)`（`:42-46`）。`landingOffset = 2·N.y·|N.xz| / sqrt((1−2N.y²)² + 0.0625)`（`:42-43`）是 ITT `CalculateWaterCaustics` 的投影距离的平滑化改写。
  - **这里必须给一组实测数（本文用 Node 按同一 64×64 噪声贴图复算了 128² 格窗口、0.25 格步长，见 §12 复核）**：`landingOffset` 的实际分布是 p10=0.031 / p50=0.095 / p90=0.219 / **max=0.582**，即 `caustic=0.2+2.8·LO ∈ [0.2, 1.83]`、`caustic³ ∈ [0.008, 6.13]`。重标定后：**软限幅只压缩高端约 2.5 倍（6.13→2.42），中位数几乎不变（0.100→0.098）**，R 的动态度仍有约 110:1（p99/p1）。
  - **所以「软限幅把束内对比抹平」这个说法不成立**（本文早期版本、hy4 的 R2、GLM 的 P0-4 都高估了它）：配合同一复算，ITT 的 `caustic³` 在同一波场上的中位数是 0.107，与 Astra 未压缩前的 0.100 几乎相同——**Astra 的碰撞光量与 ITT 的对比量级一致，差别只在高端的 2.5 倍和后续的滤波**。
- **`G = pow(itt_water_beam_envelope(worldXZ), mix(10,6,clearDay))`（`:47-49`）**。
- `BA` = 局部折射斜率。

`lib/itt_water_waves.glsl:85-109` 的 `itt_water_beam_envelope` 是**新增机制，两份参考都没有**：它把 ITT 最后两层（权重 30/79 与 20/79 的大波峰）单独取出，把空间与时间同时乘 `0.30`（`scale`），除以 45 归一化到 `[0,1]`，再取 6～10 次幂。取幂后只剩**细窄亮纹**。

**实测（同一复算脚本，128² 格窗口）**：包络本身 mean=0.71、p50=0.75、**28% 面积落在 ≥0.85**；取 6 次幂后 mean=0.265、`>10%·max` 覆盖 **62% 面积且只连成 5 个大连通区**；取 10 次幂后 mean=0.168、覆盖 40% 面积（19 个连通区）。也就是说它**不是「稀疏小点」，而是「几块巨大的亮区」**——这与用户看到的「几根粗柱子」在数量级上吻合。纹路特征间距（自相关）为 **11.5 格（x）× 25 格（z）**（各向异性 2.2:1），漂移速度实测 **约 1.5 格/秒**（即穿过自身一个纹距约 8 秒）。

对比 G 与 R 的强弱：G=`pow(env,6)` 的动态度 p99/p1 实测 **4.4×10³**，R 只有 **1.1×10²**，两者相关系数仅 **0.046**——**束形确实由 G 决定，R 只是叠加在其上的弱纹理**。这正是「柱子感 + 位置与光路无关」的量化证据。

消费者把它当**辐照度乘数**用（`light_shafts.glsl:162`：`irradiance = max(wave.r,0)·clamp(wave.g,0,1)`）。于是**束的亮纹位置完全由这张图的 G 通道决定**，与地形遮挡无关。

### 2.2 遮挡：只在 8 个区间端点求值，区间内线性插值

`light_shafts.glsl:140` `stepLength = min(48, 26)/7 ≈ 3.71`；`:150` 循环 7 个区间；`:148`/`:154` 只在 `begin`、每个 `segmentEnd` 调 `water_shaft_path_visibility`（`:96-112`），区间内部用 `mix(startVisibility, endVisibility, nodes[node])`（`:167`）线性过渡。

而且这个可见性**只查不透明影图**：`shadow_opaque_visibility`（`global/lighting/shadowmap.glsl:259-270`，采样 `shadowtex1`）。`shadowtex0`（含水面的完整影图）与 `shadowcolor0`（Astra 自己的水面高度 + 焦散 focus 记录，`program/shadow.fsh:88-102`）在体积光束里**完全没有被读**——这正是 `design.md:297` 原设计要求的「确认光线经过水面」那一项。

后果：细于 3.71 格的遮挡结构（树叶间隙、栏杆、船底、半砖）在区间内被抹成斜坡；水面本身不作为透光界面参与；体积里没有任何「光从水面折射下来」的信息。

### 2.3 采样与滤波：三重模糊叠加

1. **源图预滤**：`sourceLod = clamp(log2(max(0.25, stepLength·|entryRay.xz|·0.25)/0.25), 0, 3)`（`:146-147`），`textureLod`（`:161`）。水平视线且太阳中等高度时 `|entryRay.xz|≈1`，`stepLength·|entryRay.xz|·0.25 ≈ 0.93` → **lod≈1.9，相当于 4 倍模糊**；太阳低时 `|entryRay.xz|` 增大，可达 lod 上限 3（8 倍模糊）。
2. **积分只有 28 个光量点**（7 区间 × 4 点 Gauss），无抖动，无时域手段。
3. **分辨率与重建**：`shaders.properties:18-33`，主世界预算下 `size.buffer.colortex1=0.25 0.25`（1080p → 480×270），再由 `water_shafts_resolve`（`:184-228`）四角双线性 + `depthWeight = max(1−|Δd|·0.25, 0)²`（`:218-220`）重建；端点距离差 ≥4 格即丢弃该角。

### 2.4 相位：用局部斜率冒充光向

`:168-170`：
```glsl
vec3 localSource = normalize(vec3(wave.b, 1.0, wave.a));
integral += transmission * (irradiance * visibility * water_shaft_phase(ray, localSource) * ...)
```
ITT 的原式（`UnderwaterVolumetricFog.glsl:83-85`）是：
```glsl
vec3 lightVector = refract(worldShadowVector, vec3(0.0,-1.0,0.0), 1.0/1.2);
float LdotV = dot(lightVector, worldDir);
float phace = MiePhaseFunction(0.7, LdotV);
```
即**用整帧固定的折射太阳方向**做相位：亮度在「看向太阳」时最高，屏幕上平滑变化。现版本把它替换成**逐 texel 的波面斜率**，相位项于是随波面高频抖动，并且失去了「朝太阳方向更亮」的物理行为。这是纯粹的移植偏差，也是「毫无质感」的直接来源之一（亮斑随波面颗粒化，不成束）。

### 2.5 距离：硬截断 + 双层淡出

`global/water/shaft_layout.glsl:5-8`：近端 `0.08→max(0.3, UNDERWATER_SHAFT_DISTANCE)` 淡入，远端 `14→26` 淡出为零；`light_shafts.glsl:117` 把积分长度硬截在 `min(48,26)=26` 格。`lang/zh_CN.lang:215-216` 把 `UNDERWATER_SHAFT_DISTANCE` 标成「光束近处衰减距离」，但用户面板上它看起来像距离档——**语义与命名不一致**（现行实现只影响近端淡入）。

ITT 是 40 格范围、权重 `1/max(3, 0.1·d)`（`:74`）连续衰减、**没有近端淡出**；Solas 是 `maxDist = shadowDistance/(1+5) ≈ 19`（shadowDistance 112 时）/`≈32`（192 时），指数间距 8 样点、无近端淡出。

### 2.6 合成：迎光峰值被关闭，全部亮度压在这一条通路上

`lib/solas_water.glsl:80-92`：只要 `ASTRA_UNDERWATER_SHAFTS` 打开，水雾就 `fog *= response.x`——**丢掉 Solas 原来的迎光角向峰值 `glare`**，改由体积光束承担全部迎光亮度（`:98-118` 在解码后 `+ shafts`）。所以只要这套体积是错的，水下迎光观感就没有第二来源兜底。

### 2.7 其它取证

- **两个互不相同的波场同时存在**：`lib/water_wave_lens.glsl`（Solas 噪声，两倍频五阶，Hessian → `astra_water_caustic_focus` → `shadowcolor0.a`，供床面焦散与表面照明）与 `lib/itt_water_waves.glsl`（ITT 六层，供水下界面法线与体积光束）。床面焦散的图案与体积光束的图案**不是同一个波场**，位置天然对不上。
- **mip 生成时机**：`const bool colortex29MipmapEnabled = true;` 写在 `light_shafts.glsl:70`，即**消费它的 composite2 内**。实例 Iris 的 `CompositeRenderer` 语义（`_analysis/iris-runtime/CompositeRenderer.txt:331-350,587-618`：`ProgramDirectives.getMipmappedBuffers()` → pass 结束后 `setupMipmapping` → `generateMipmaps`）说明：mip 在**该 pass 结束后**才重建，所以 composite2 内部 `textureLod(..., lod>0)` 读到的是**上一帧生成的 mip**；生产者（prepare4）自己没有声明该项。
- **死代码**：`global/water/shaft_history.glsl`（75 行）已无任何 include 引用（全仓 grep 为 0）；`shaft_layout.glsl` 仅被 `light_shafts.glsl` 引用。

### 2.8 生产者自身的 Nyquist 滤波：ITT 最细的两层根本没进这张图（新发现）

`lib/itt_water_waves.glsl:26-28` 每个噪声层都乘一个解析度因子：
```glsl
float frequency = 64.0*max(length(worldUV[0]),length(worldUV[1]));
float resolved = 1.0-smoothstep(0.5,1.25,footprint*frequency);
return vec3(mix(0.5,value,resolved),transpose(worldUV)*gradient*resolved);
```
生产者传的 `footprint = ITT_WATER_FIELD_CELL = 0.25`（格）。按同一复算脚本逐层算出（`|j|max` 为该层 uv 每格变化率）：

| ITT 层 | 权重 | \|j\|max | 频率(周期/格) | 噪声胞元(格) | **resolved@0.25** |
|---|---:|---:|---:|---:|---:|
| L1 | 1 | 0.14500 | 9.28 | 0.11 | **0.000（整层被滤掉）** |
| L2 | 4 | 0.06888 | 4.41 | 0.23 | **0.101** |
| L3 | 8 | 0.02366 | 1.51 | 0.66 | 1.000 |
| L4 | 16 | 0.02197 | 1.41 | 0.71 | 1.000 |
| L5 | 30 | 0.00989 | 0.63 | 1.58 | 1.000 |
| L6 | 20 | 0.00494 | 0.32 | 3.16 | 1.000 |

结论：**0.25 格的纹素不足以承载 0.11/0.23 格的胞元，图层 1 全部、层 2 九成被生产端自己的抗混叠滤掉了**。这不是 mip 或消费端的问题，而是「一张 0.25 格/纹素的图」这个载体本身的物理上限——ITT 的细腻流动感恰恰主要来自这两层（它们梯度大、周期短、移动最快）。要找回它只有三条路：把图提到 1024²（0.125 格/纹素，层 1 的 resolved 可回升到约 0.5～0.9）、把覆盖缩到 64 格保持 512²、或放弃 LUT 改为每样点现场求值（成本见 §6）。

**但只提密度只兑现一半（本文后续补算）**：两级滤波是串联的。按层把「生产者 `resolved` + 消费端 mip 有效核」一起算：现状的可见细纹其实**只剩 L5/L6（1.58/3.16 格）**（消费端 0.92 格核把 L3/L4 也归零）；只把生产者提到 0.0625 格/纹素，下限推进到 L3≈0.66 格；**必须同时把消费端的 `sourceLod` 从「按积分足迹」改成屏幕足迹驱动（或近处 lod 0），才能拿到 L1/L2**。因此本项（阶段 0.6）与 0.3（去 mip 预滤）是配套项。

该事实已由 step5（§2.2，独立复算出同一 L1 频率 9.28、resolved 0.00）与 hy4 修订版（§3.4/§10c）分别发现；本文的补充是用代码自身的度量（`64·max(|col|)`）给出逐层精确值，并把 L2 定为 0.101（step5 写 0.20）、纠正 hy4 表里整体错开一层的层号。

---

## 3. 两份参考的真实机制（原文取证）

### 3.1 ITT 3.2：逐样点遮挡 × 逐样点碰撞光量

`Lib/IndividualFounctions/UnderwaterVolumetricFog.glsl:39-96`（由 `composite5.fsh:273` 在 `isEyeInWater == 1` 时调用）：

```glsl
const float range = 40.0;                    // :40  范围固定 40 格
endPos = mix(worldDir*range, endPos, step(length(endPos), range));  // :45 无远处淡出
const float steps = VFOG_QUALITY;            // :50  默认 6（Lib/Settings.glsl:310）
const float stepLength = range/steps;        // :51  ≈6.67 格
float noise = BlueNoiseTemproal().y;         // :53  逐像素逐帧抖动（整条射线同一位移）
for (float i = 0.0; i < steps; i++){
    float rayLength = (i+noise)*stepLength;
    vec3 rayPos = startPos + rayDir*rayLength;
    vec3 shadow = step(shadowProjPos.z+1e-06, textureLod(shadowtex1, xy, 0).x); // :63-68 逐样点真实遮挡
    float caustics = CalculateWaterCaustics(rayPos);   // :72
    shadow *= caustics*caustics*caustics;              // :73 碰撞光量三次方
    shadow /= max(3.0, rayLength*0.1);                 // :74 距离权重
    shadow *= pow(vec3(0.1,0.6,1.0)*0.99, vec3(rayLength*0.04*WATERFOG_DENSITY)); // :76 分色消光
    result += shadow;
}
result *= range/steps;                       // :81 黎曼和归一
result *= colorShadowlight * (0.04*phace*SUNLIGHT_INTENSITY*UNDERWATER_VFOG_DENSITY); // :87
result *= globalCloudShadow;                 // :93 云影：整帧标量（非空间图案）
```

要点（与本项目差异最大的四处）：

1. **束形 = 逐样点遮挡测试**（`:63-68`），单点、二值、无插值。束的边界就是遮挡物的阴影边界。
2. **纹理由 `CalculateWaterCaustics` 提供**。注意这里有一个容易读错的坑：ITT 有两份**同名不同体**的实现，分别位于不同编译单元——`composite5.fsh`（水下体积雾所在单元）里只有 `UnderwaterVolumetricFog.glsl:3-36` 那一份（单点、无抖动版），而 `composite.fsh:102` 引入的 `Lib/BasicFounctions/Sunlight_Shadow.glsl:257-289` 是 3×3 抖动版（供水面焦散用）。composite5 用的是前者：
   - `GetWavesNormalFromTex`（`UnderwaterVolumetricFog.glsl:3-20`）把世界坐标按 `coord=worldXZ; coord.x/z += position.y·lightVector.xz/lightVector.y; coord*=0.02; coord=fract(coord);` 折到一张 50 格平铺的波面法线 LUT（`colortex7`），**只按入射 XZ 查，不滤波、不 mip**（`textureLod(...,0.0)`）。
   - 于是「光量」是倒下点与样点距离的函数，是**波面法线的二维函数**——**这是它和 Astra 现版本唯一一致的地方：二维 LUT 本身没错**。
   - 相位是**整帧固定**的折射太阳方向（`:83-85`），不是局部斜率。
3. **云影无条件参与**（`:93`）：`globalCloudShadow` 来自 `GetSmoothCloudShadow()`（`Lib/IndividualFounctions/CloudShadow.glsl:55-63`），是**整帧一个标量**——遥感云缓冲区的一个 texel，另按湿度线性抬高；它不提供空间结构，只让整片水下光随云经过而整体明暗呼吸（云的空间结构仍由 `:63-68` 的遮挡测试给出）。Astra 没有这条整帧调制：它的云影只以 `astra_cloud_transmission` 在入水点取一次，且被 `CLOUD_SHADOWS` 门控（默认关）。
4. **逐帧抖动 + TAA 累积**（`:53` 用 `BlueNoiseTemproal()`）：这是 ITT 用 6 个样点就能得到细束的关键。**Astra 水下无 TAA，此项不可照搬**（见 §1 硬约束 1；ITT 自己在无 TAA 时退化为 `bayer64` 静态抖动，见 `VolumetricFog.glsl:74-78`，可作对照）。

对照：ITT 的**空气**体积雾（`Lib/IndividualFounctions/VolumetricFog.glsl:69-270`）用的是同一套骨架，但更完整：指数间距 `exponential = pow(11.0,(i+noise)/steps)`（`:135`）、前到后透射率累计（`:212-235`）、双/四项相位（`:8-18`）、`VFOG_STAINED` 分支用 `shadowtex0/1` 差分 + `shadowcolor0` 颜色取「穿过半透明的染色光」（`:183-200`）——**即 ITT 自己也有 Solas 那条半透明差分通路**。

### 3.2 Solas V2.2b：透光与遮挡分离，水下只留「穿过水面的那束光」

`lib/atmosphere/volumetrics.glsl`：

```glsl
// :186-205 采样分布：几何间距 + 权重∝距离（无 TAA 也能用，抖动可固定）
float currentDist = exp2(dither);
for (int i=0; i<sampleCount; i++, currentDist *= 2.0){
    if (isRayMarcherHit(currentDist, maxDist, linearZ0, linearZ1, translucent)) break;
    vec3 sampleWorldPos = nWorldPos*currentDist;
    float currentSampleIntensityVL = pow(currentDist/maxDist/sampleCount, vlSamplePersistence);
// :219-232 每个样点：shadowtex0=含半透明，shadowtex1=仅不透明
shadow0 = texture2DShadow(shadowtex0, sampleShadowPos);
if (shadow0 < 1.0 && doShadowColor > 0.9) shadow1 = texture2DShadow(shadowtex1, sampleShadowPos);
vlSample = clamp(
    shadow1*(1.0-shadow0)*doShadowColor*shadowCol*shadowCol
        * mix(vec3(0.25), waterColor*lShadowCol, float(isEyeInWater==1))
    + shadow0*vlCol*float(isEyeInWater==0), 0.0, 1.0);
// :295-298 位于半透明界面之后的样点，整体乘以折射背景色（transluent = colortex1）
if (linearZ0 < currentDist) vlSample *= translucent;
}
vl *= totalVisibility;                        // :304
```

要点：

1. **水下项 = `shadow1·(1−shadow0)`**：在不透明图里是亮的、在含半透明图里被挡住 → 语义唯一：**光是从半透明物（水面）透过来的**。`shadow0·vlCol`（纯无遮挡基础项）在水下被显式乘 0。
2. **颜色来自 caster 记录**（`shadowCol` = `shadowcolor0`，被 `shadowCol²` 压过）；Astra 的 `shadowcolor0` 存的是**水面高度 + 焦散 focus**（`global/lighting/shadowmap.glsl:75-99`、`program/shadow.fsh:88-102`），所以 Astra 的对应物应是 `shadow_water_transmission()/shadow_water_caustic_gain()` 的标量，而不是颜色。
3. **分布**：`exp2(dither)·2^i` 几何间距 + 权重 `currentDist/maxDist/sampleCount`（`:192-205`）；`dither` 在无 TAA 时是**纯空间蓝噪声、逐帧不变**（`programs/composite1.glsl:130-134`）。这条对本项目最有用：**没有 TAA 也能工作**。
4. **距离角色**：`distanceFactor = 5·isEyeInWater + …` → `maxDist = shadowDistance/(1+distanceFactor)`（`:63`），水下约 19～32 格；**无近端淡出**。
5. 参数：`VL_SAMPLES=8`（`lib/common.glsl:271`）、`VL_STRENGTH=1.25`（`:270`）。

### 3.3 两份参考的共同点（也就是现版本缺的东西）

| 共同点 | ITT | Solas | Astra 现状 |
|---|---|---|---|
| 束形来自逐样点真实遮挡 | ✅ `:63-68` | ✅ `:221-232` | ❌ 8 个区间端点 + 线性插值 |
| 水面参与体积的方式 | △ 几何经水面（用波面法线 LUT 把光折下来），但水面本身不作遮挡体（NVIDIA 分支用 `shadowtex1`）；仅 `VFOG_STAINED` 分支有半透明差分（空气雾） | ✅ 水面作为半透明投射体：`(1−shadow0)` 差分 + `shadowCol` | ❌ 只查 `shadowtex1`，水面完全不在体积光路里 |
| 相位用固定的折射光向 | ✅ `:83-85` | ✅ `VoL` | ❌ 逐 texel 波面斜率 |
| 云影参与 | ✅ 整帧标量乘子（`UnderwaterVolumetricFog.glsl:93`） | ✅ `VC_SHADOWS` 卷云噪声 / cloudShadows | ⚠️ 仅 `CLOUD_MODE==PLANAR && CLOUD_SHADOWS` 时在入水点取一次，而 `CLOUD_SHADOWS` 在 BALANCED/PERFORMANCE 档默认关闭（`shaders.properties:559-562`） |
| 距离衰减连续、无硬截断 | ✅ `1/max(3,0.1d)` | ✅ 权重∝距离 | ❌ `1−smoothstep(14,26,d)` 归零 |
| 有可验证的「关掉太阳就消失」通路 | ✅ | ✅ | ⚠️ 有 `directLight`/`sunSource` 项，但束形与光路无关联，难以据此验证 |

---

## 4. 症状 → 机制归因

| 用户描述 | 直接机制 | 证据 | 置信度 |
|---|---|---|---|
| **像柱子** | ①光量图是 XZ 的二维函数，采样点沿视线移动的横向位移只有几格（≈ 水深×tanθ_water，10 格深、22° 时约 4 格），远小于纹距 11.5～25 格 → 一条亮脊在整条水柱内近乎不位移，同一像素沿水深亮度近乎不变；②决定束形的 G 动态度 4.4×10³ 远大于 R 的 1.1×10²（相关系数 0.046），且只连成 5 个巨大连通区 → 「几根粗柱子」 | `light_shafts.glsl:133-136,159-162`；生产者 `itt_water_normal_cache.fsh:48-50`；§2.1 实测 | 高 |
| **位置乱七八糟** | 亮带位置由 `pow(envelope,6~10)` 的波峰纹路决定，与上方真实遮挡物无关（G 与 R 几乎不相关，R 才携带与水面的关系）；且与床面焦散不是同一波场 | `itt_water_waves.glsl:85-109`；`light_shafts.glsl:162`；两个波场见 §2.7 | 高 |
| **固定位置** | ①场是**世界锚定**的：图案由一张 2D 图决定，与太阳/云/地形/遮挡无关，只有整帧强度随它们变化；②包络特征漂移实测 1.5 格/秒 ≈ 8 秒才走完一个纹距，且决定屏幕图案的是它这块「慢成分」；③真正快的成分（ITT 层 1/2 与 R 的细结构）分别被生产者的 Nyquist 滤波和消费端 mip 预滤抹掉（§2.8）——**动的被滤掉，剩下慢的** | §2.1、§2.8 实测；`shaders.properties:559-562` | 高 |
| **毫无质感** | 三重低通 + 一重门控：①生产者自身按 0.25 格足迹做 Nyquist 滤波，**ITT 层 1 完全被滤掉（resolved=0.000）、层 2 只剩 0.101**；②消费端按积分足迹预滤到 lod≈1.9（等效 0.93 格模糊），而 R 的结构尺度实测只有 0.5～2.5 格；③28 个固定 Gauss 点无抖动；④1/16 像素数渲染再四角重建；⑤相位被局部斜率颗粒化 | `light_shafts.glsl:144-147,161,213-223`；`itt_water_waves.glsl:27`；`shaders.properties:18-33`；§2.1/§2.8 实测 | 高 |
| 束内没有「光从水面上折下来」的感觉 | 体积完全不读 `shadowtex0`/`shadowcolor0`，与 `design.md:297` 的原设计不符 | `light_shafts.glsl:96-112` | 高（代码事实） |
| 迎光处整体偏暗/不自然 | 有光束时水雾的角向峰值被跳过，体积成为唯一迎光来源 | `lib/solas_water.glsl:80-92` | 中（需画面确认） |
| 移动时束纹轻微「滞后/拖影」 | colortex29 的 mip 在消费 pass 结束后才重建，同帧读到上一代 mip；生产者自己没声明 | `light_shafts.glsl:70`；`CompositeRenderer.txt:331-350` | 中（Iris 语义已核，需实机确认可见度） |

---

## 5. 改动意见

### 5.0 总原则

1. **束形只由「沿阳光方向的真实遮挡」决定**（ITT `:63-68` / Solas `:221-232`），二维 LUT 只能承担**束内光量细节**（ITT 的碰撞光量），不能再承担束形。
2. **水面必须是体积的透光界面**（Solas `(1−shadow0)` 差分），这同时补回 `design.md:297` 的原设计项。
3. **大波峰回到「作用于波面法线」**，不再作为独立包络取幂。
4. **一切取舍都要能在「关掉太阳应消失、遮挡变化应改变束形」这条可验证判据下通过**，否则不成立。
5. 不照搬 ITT 的逐帧抖动（水下无 TAA），改用 Solas 的几何间距 + 静态空间抖动。

### 5.1 阶段 0：低成本纠正移植偏差（建议先做，可单独验收；0.1/0.6 证据最强）

只改 `lib/itt_water_waves.glsl`、`program/itt_water_normal_cache.fsh`、`global/water/light_shafts.glsl`、`lib/solas_water.glsl`，**不动数据流**：

| # | 改动 | 位置 | 具体做法 |
|---|---|---|---|
| 0.1 | **删除 G 包络** | `itt_water_normal_cache.fsh:48-49`；`light_shafts.glsl:162` | 源图 G 写 1.0（或直接弃用），`irradiance` 只取 `max(wave.r,0)`；`itt_water_beam_envelope()` 从 `itt_water_waves.glsl` 删除（该函数为 Astra 新增，不涉及参考来源登记；`itt_water_wave_normal` 及其六层/梯度实现保持不动） |
| 0.1b | **放宽碰撞光量的软限幅（低优先，可选）** | `itt_water_normal_cache.fsh:45-46` | 实测该项**只压缩高端 2.5 倍**（6.13→2.42，中位数不变），不是「无质感」的主因，因此降级为可选。若要做，把系数 0.25 改到 0.05～0.08（渐近值 20～13），并接受峰值升高带来的高光风险。**附更正（2026-10-11）**：本文早前写「不要照 GLM 的 P0-4 把三次方移到消费端（Jensen 不等式）」是误读——GLM 是让**缓冲存线性量**（未立方）再在消费端立方，这属于正确的前置滤波做法，与「缓冲存法线」（step5 路径 B／grok4.7）同构；Jensen 只适用于「缓冲里已是三次方值再滤波」的写法。若走「缓冲存线性量／法线」的路线，本项连同 §5.1 0.3 的 LOD 修正应一起做 |
| 0.2 | **相位改回固定折射太阳方向** | `light_shafts.glsl:168-170` | 改为 ITT 原式：`vec3 lightVector = -refract(-itt_water_light_direction(shadowModelViewInverse), vec3(0,-1,0), 1.0/1.2)`（在 `scattering.vsh` 里算好、经 flat varying 传入），`phase = MiePhaseFunction(0.7, dot(lightVector, ray))`；`wave.ba` 不再进入相位 |
| 0.3 | **去掉 mip 预滤** | `light_shafts.glsl:146-147,161` | 改为屏幕导数驱动的 lod：`textureGrad(colortex29, uv, dFdx(uv)*EXTENT, dFdy(uv)*EXTENT)`，或直接 lod 0；同时把 `const bool colortex29MipmapEnabled = true;` **从 `light_shafts.glsl:70` 移到生产者** `program/itt_water_normal_cache.fsh`（若保留 mip 通路） |
| 0.4 | **距离权重连续化、范围放宽** | `shaft_layout.glsl:5-8`；`light_shafts.glsl:165-166` | 参照 ITT `:74`：去掉 `1−smoothstep(14,26,d)`，改为 `1/max(3.0, d·0.1)`；积分上限从 26 提到 40 格（`WATER_SHAFT_FAR_END=40`，仍受 `astraWaterShaftRange` 与预算控制）；近端淡出保留但缩到 ≤1 格（避免糊脸，文档已允许） |
| 0.5 | **恢复水雾迎光峰值** | `lib/solas_water.glsl:80-92` | 至少让 `response.y` 的角向项以较低权重继续存在（如 `fog *= response.x + glare*response.y*0.5`），避免体积成为唯一迎光来源；若新方案已能提供迎光亮度，再决定是否彻底移除 |
| 0.6 | **让 ITT 层 1/2 重新进入光量图（本文新发现，建议与 0.1 同批试）** | `lib/itt_water_field.glsl:4-5`、`program/itt_water_normal_cache.fsh:33` | 维持 128 格覆盖则把图提到 1024²（`ITT_WATER_FIELD_SIZE=1024`，成本 4 倍但只在生产端一次/帧），或把覆盖缩到 64 格保持 512²。理由见 §2.8：0.25 格/纹素下层 1 被完全滤除、层 2 只剩 10%，而它们正是 ITT 流动细腻感的来源。**注意**：若同时改窗口大小，`water_shaft_field_origin` 的格偏移协议与 `ITT_WATER_FIELD_CELL` 常量必须同步（`lib/itt_water_field.glsl:7`） |

预期效果：柱子感与「纹路固定」明显减弱（束形改由 R 的焦散光量 + 真实遮挡决定），远距离不再整齐消失，最细的一两层波面回到图里。**这一步不解决「束形仍由二维图决定」的根本问题**，但能立刻把画面从「成排柱子」拉回「随波面流动的光量变化」。

**顺序建议**：0.1（去门控）与 0.6（补回细层）是本文实测证据最强的两项，建议同批先做并各自单独存图；0.2/0.3/0.4 紧随其后；0.1b/0.5 量级最小，可放最后。

### 5.2 阶段 1：结构重写（推荐主体）

**目标架构（两份参考的组织，Astra 的数据）**

```
每像素（水下、非薄层）：
  起点 P0 = 相机；终点 Pe = min(最近不透明面, 40 格)
  样点集合 {d_i}：Solas 几何间距 currentDist = exp2(dither)*2^i
                 dither = 静态空间蓝噪声（无 TAA → 逐帧不变）
                 i ∈ [0, N)，N = 6/8/12/16 按档
  对每个样点 P_i = P0 + ray*d_i：
      V0 = 过滤后的 shadowtex0 可见性（含半透明=水面）
      V1 = 过滤后的 shadowtex1 可见性（仅不透明）
      entry_i = clamp(V1 - V0, 0, 1)          // Solas：光从水面透过来的那一项
      light_i = entry_i * waterTint           // 水体染色（Astra 用调色常量，非 shadowcolor0 颜色）
      light_i *= collisionLight(entryXZ_i)    // ITT：波面法线算出的碰撞光量（束内细节，不软限幅）
      light_i *= phase(dot(refractedSun, ray))// ITT：整帧固定
      light_i *= exp(-sigma_c * max(sunPath_i + viewPath_i, 0)) // 分色消光
      sum += light_i * weight_i
  输出 = sum * frameStrength（日月/天气/晴天/失明/阴影渐退）
```

**关键取舍与理由**

1. **`entry_i = clamp(V1−V0,0,1)` 必须在样点处求值**（不是在端点）：这是 Solas 的原文语义，并且它天然实现「水面是透光界面」：水下的光只能从水面进来。Astra 需要新增一个过滤版 `shadowtex0` 可见性函数（与既有 `shadow_opaque_visibility` 同形，`global/lighting/shadowmap.glsl:259-270`）。**建议本期不读 `shadowcolor0`**：Astra 的 `shadowcolor0` 存的是水高与焦散 focus 而非颜色，若在体积里读它就会把 Solas 波场（`water_wave_lens`）的焦散图案引入体积，与 ITT 波场的光量图案撞车（见 §7 裁决项 1）。
2. **`collisionLight` 继续用二维 LUT，但只保留 ITT 的碰撞光量**：源图 R 通道保留（并把软限幅解开，见 §5.1 0.1b），G 通道弃用（写 1 或不写），读取时**不预滤**。这与 ITT `GetWavesNormalFromTex` 读取二维 LUT 的做法同构；**束形不再由它决定**，它只给束内纹理和流动感。若未来要做严格逐样点版本，可改用 ITT 六层直接求值或缓存法线（见 §11 差异 1 的等价性说明；成本见 §6）。
3. **采样分布用 Solas 而不是 ITT**：`exp2(dither)*2^i` + 权重 `∝ 距离`（`volumetrics.glsl:192-205`），`dither` 取静态空间蓝噪声。理由：水下无 TAA，ITT 的均匀 6 样点靠时域累积，照搬会在移动时明显条带；Solas 的分布对静态抖动更宽容，且近距离样点更密（本项目最关心近处可读）。
4. **必须补回云影调制**：ITT 无条件乘整帧云影标量（`:93`）；Astra 的 `astra_cloud_transmission`（`global/atmosphere/weather.glsl:131-145`）其实更强（按可见云场在云平面上投影、逐入水点取值，非平面模式自动返回 1），但目前只在 `CLOUD_MODE==CLOUD_PLANAR && CLOUD_SHADOWS` 时被调用，而 `CLOUD_SHADOWS` 在 BALANCED/PERFORMANCE 档默认关闭。建议：**体积里无条件调用它**（与 ITT 一致），若不希望与用户选项脱钩，则至少在 BALANCED/ULTRA 默认打开 `CLOUD_SHADOWS`。否则「固定感」只修一半。
5. **删除生产者对上一帧水深的依赖**：窗口中心改为相机 XZ（`itt_water_normal_cache.fsh:20-27`），窗口对齐仍取 16 格倍数；这样 `D03` 里「换池/首次深潜覆盖不足」的失效模式消失，也不需要 `water_shaft_field_origin` 依赖上一帧状态。
6. **分辨率**：`size.buffer.colortex1` 从 `0.25` 提到 `0.5`（`shaders.properties:18-33`），保留既有四角 + 距离保护重建（`light_shafts.glsl:213-223`），但把 `depthWeight` 的容差从 4 格放宽到 ~8 格、并去掉 `:226-227` 的二次近端淡出（近端淡出已由采样权重承担）。理由：0.25× 是低通里最贵的一层（4 倍像素），而重建是现成的。

**逐文件改动清单**

| 文件 | 动作 |
|---|---|
| `global/water/light_shafts.glsl` | 重写 `water_shafts_march`：删除区间/Gauss 结构（`:140-175`）、`water_shaft_path_visibility`（`:96-112`）改为「单样点 `V1`/`V0` 双查 + entry 项」；保留 `water_shafts_view`（`:37-64`）、相位（改参数来源）、消光（`:137` 保留）、`water_shafts_resolve`（`:184-228`，按 §5.2.6 调整权重） |
| `global/water/shaft_layout.glsl` | 改为：`NEAR_FADE`（≤1 格）、`FAR_END = 40`、`DIST_WEIGHT` 由 `1/max(3,0.1d)` 统一承担；删除 `14/26` 常量 |
| 新增 `global/lighting/shadowmap.glsl` 内函数 | `shadow_all_visibility(vec3 shadowPos)`（与 `shadow_opaque_visibility` 同形，采样 `shadowtex0`） |
| `lib/itt_water_waves.glsl` | 删除 `itt_water_beam_envelope`；保留六层/梯度/解析梯度（`itt_water_wave_normal` 不变） |
| `program/itt_water_normal_cache.fsh` | 输出改为 `R = 碰撞光量`（保留现有 `energy = bound(caustic³)` 但解开软限幅；是否保留 `transmission` 因子见 §7 裁决项 2），G 写 1 或不写；窗口中心改相机 XZ |
| `program/scattering.vsh` | 增传固定的折射太阳方向（供相位）与水色相关量；`waterShaftSurface` 与 `waterShaftSource.w`（整帧强度）保留；`waterShaftFieldOrigin` 按最终是否保留二维 LUT 决定去留 |
| `program/scattering.fsh` | 保持 composite2 位置；水下分支保留；**确认 colortex1 尺寸改动后 alpha 编码仍为 `min(d,48)/128`**（`:96-99`） |
| `lib/solas_water.glsl` | 按 0.5 调整迎光峰值；`solas_water_composite` 的 `+shafts` 位置不变（解码后线性相加，与 ITT 的 `color +=` 一致） |
| `global/water/shaft_history.glsl` | 删除（死代码） |
| `shaders.properties` | `size.buffer.colortex1` 0.5；移动 `colortex29MipmapEnabled` 声明到生产者；`screen.WATER` 与档案里的 `UNDERWATER_SHAFT_*` 说明同步（见 §5.3） |

### 5.3 阶段 2：选项、标签与死代码

| 项 | 现状 | 建议 |
|---|---|---|
| `UNDERWATER_SHAFT_DISTANCE` | 名义「近处衰减距离」，实际只控制近端淡入终点（`shaft_layout.glsl:6`） | 保留语义但改名为「近处淡出（格）」，默认 1；或把它改成真正的**远距上限**（40/32/24 三档），近端淡出固定 1 格。二选一，不要维持「面板像距离、代码是近端」 |
| `UNDERWATER_SHAFT_SAMPLES` | 4/7/10，主世界最多 7（`light_shafts.glsl:22-26`） | 改为 6/8/12/16（`6/8/12` 对应三档，16 给 ULTRA），并在 lang 里如实写成「样点数（遮挡细节），不影响光束数量」 |
| `UNDERWATER_SHAFT_STRENGTH` | 只乘一次（`display.fsh:139`/`water_composite.fsh:27`） | 保持不变；不要在新方案里再加一层 |
| lang | `lang/zh_CN.lang:213-221`、`lang/en_US.lang:213-221` | 与上面两项同步；删除「光束位置始终由水面与光源决定」这类在旧结构下无法兑现的描述，改为「遮挡与透光决定位置」 |
| 死代码 | `shaft_history.glsl`、`shaft_layout.glsl` 的单点引用 | 前者删除；后者并入 `light_shafts.glsl` 顶部常量（少一个文件、少一处不同步风险） |
| mip | 声明在消费 pass | 移入生产者；若最终决定完全不滤（用 `textureGrad`），则删除该声明并同时去掉 `size.buffer.colortex29` 的 mip 需求 |

### 5.4 阶段 3（可选，需裁决）：统一波场与云影

- **统一波场**：把 `shadowcolor0.a` 的焦散 focus（现由 Solas 噪声场 `astra_water_wave_lens` 生成，`lib/water_wave_lens.glsl:22-52`）改用 **ITT 波面**计算，使「床面焦散 / 水下界面法线 / 体积入光」三者同源。收益：床面亮纹与体积光束位置一致（ITT/Solas 都有这个性质，Astra 现在没有）；代价：①改动床面焦散观感，属 W03/W12 邻域，必须用户点头；②技术上要另算二阶导——现有 `water_wave_lens` 用五阶插值保证曲率连续，而 ITT 的 crest 层（`itt_water_waves.glsl:30-41`）在 `|x|=0.2` 处只有 C¹ 分段，直接求 Hessian 会得到不连续的聚焦，需要额外平滑；因此这一步建议单独排期、不与光束重写同批。
- **云影**：把 `astra_cloud_transmission` 作为体积的无条件乘子（对齐 ITT `:93`），或把 `CLOUD_SHADOWS` 在 BALANCED/ULTRA 默认打开。

---

## 6. 成本估算（供性能裁决，非实测）

以 1080p、水下像素占比取 40% 估算：

| 方案 | 纹理读/水下像素 | 等效全屏读/帧 | 备注 |
|---|---|---|---|
| 现状（0.25×，28 光量点 + 16 影图） | ~46（但只在 1/16 像素） | ≈ 3.1M | 低分辨率是最大画质损失项 |
| 阶段 0（仅纠正偏差） | ~30（仍 0.25×） | ≈ 2.2M | 不变架构，画质提升来自去包络/去预滤 |
| 阶段 0.6（光量图 512²→1024²） | 生产端 4 倍（每帧一次，只在人在水下时） | 消费端不变 | 让层 1/2 回到图里（§2.8），比消费端省一个数量级 |
| 推荐（0.5×，8 样点 × (V0+V1) + 8 次 LUT） | 8×3=24 | ≈ 6.3M | 约现状 2 倍，仍是「百万级」量级 |
| 全分辨率 + 16 样点 | 16×3=48 | ≈ 25M | 从 0.04～0.1ms 量级升到 0.2～0.5ms，需实测 |

说明：影图读是小尺寸（1024/2048²）深度比较，缓存命中率高，比一般纹理读便宜；`shadow_opaque_visibility` 的硬件 PCF 分支（`shadowmap.glsl:259-266`）已具备。**结论：推荐档（0.5×、8 样点）预计落在可接受范围，但必须实测后再决定是否给 ULTRA 上 16 样点/全分辨率。**

---

## 7. 需要用户裁决的五项

1. **波场是否统一**（§5.4）：统一到 ITT 波面（改床面焦散图案）／保持两波场但体积只读 ITT 光量（推荐，改动小、床面不动）。
2. **源图 R 是否继续含 Fresnel 透射因子**：ITT 的体积雾不含 Fresnel；Astra 现在含。含则更物理但会与 Solas 的 `(1−shadow0)` 透光项有轻微重复计数；不含则更接近两份参考的叠加方式（推荐：**不含**，把透射交给 `entry_i` 项）。
3. **云影是否默认参与**：当前 BALANCED/PERFORMANCE 档 `CLOUD_SHADOWS` 关闭，体积因此缺失整帧/云场尺度的调制（「固定感」的一半来源）。建议在体积里无条件调用 `astra_cloud_transmission`（该函数在非平面云模式下自动返回 1，安全），若不希望与用户选项脱钩，则至少在 BALANCED/ULTRA 默认打开 `CLOUD_SHADOWS`。
4. **分辨率与样点分档**：是否接受把 colortex1 从 0.25× 提到 0.5×、样点改为 6/8/12（推荐），以便把性能预算从「低分辨率」换成「更多结构」。若必须严格守住 144 FPS 而不动分辨率，则阶段 0 + 阶段 1b（只加逐样点遮挡，不加分辨率）仍是净改善。
5. **光量图是否加分辨率（本文新发现，见 §2.8）**：0.25 格/纹素让 ITT 的层 1 被完全滤掉、层 2 只剩 10%。若承认 ITT 的细腻感主要来自这两层，就必须扩图（128 格 → 1024²，或覆盖缩到 64 格保持 512²）；这会改变 `ITT_WATER_FIELD_SIZE/EXTENT/CELL` 与格偏移协议。若判断「先把门控与遮挡修好、细层以后再说」，则本条延后，但请把结论写明，不要把它当成已解决。

---

## 8. 实施顺序与验收

**顺序**：阶段 0（可单独验收）→ 阶段 1（结构）→ 阶段 2（清理）→ 阶段 3（可选）。

**每次改动必须先有的判据（可判定，不依赖形容词）：**

1. **锚定判据**：在一座桥/一棵树/一艘船下方静止观察，光束的明暗边界必须与这些遮挡物投影到水下的边界一致；移动相机时，同一束光在世界中的位置不变，只是被新的遮挡改变。→ 若束纹随相机平移而滑动或整体跟随，即为失败。
2. **光源判据**：遮住太阳（或用指令把时间推到夜晚），水下体积光应基本消失；阴天/雨天应显著减弱。→ 若仍成排出现，说明束形仍来自与光路无关的图案。
3. **动态判据**：静止不动观察 10 秒，束内纹理应随波面流动；云影参与时，整体亮度应随云缓慢移动。
4. **近处判据**：手、方块边缘、水草在 1～2 格内不应被糊掉；近端淡出只允许 ≤1 格。
5. **性能判据**：在原生 1080p、均衡档、同一水下机位记录 30 秒平均帧与 95 分位帧时间，与改动前的同机位读数对比；**不能由源码推断收益**。
6. **对照判据**：同机位与本地 ITT 3.2 / Solas 截图并排比较，只比较「束形是否由遮挡决定、纹理是否流动、范围是否连续」三项，不做强度绝对值的等同比对。

**建议新增一个只读调试视图**（临时或 DEBUG 选项）：在水下把 colortex1 直接显示（黑底亮束）+ 显示 `entry_i` 项（V1−V0）与 `collisionLight` 各自的单通道视图。这三张图能把「束形来自哪里」一次看清楚，也是这轮返工之所以反复的根因——之前没有能直接看见「束形归谁」的手段。

---

## 9. 附：关键数值对照

| 项 | ITT 3.2 | Solas V2.2b | Astra 现状 |
|---|---|---|---|
| 范围 | 40 格（`UnderwaterVolumetricFog.glsl:40`） | `shadowDistance/(1+5)`≈19/32 格（`volumetrics.glsl:177-184`） | 26 格硬截断（`shaft_layout.glsl:8`） |
| 样点 | 6（可选 4…128），逐帧抖动 + TAA | 8（5…16），几何间距 + `dither` | 7 区间 × 4 Gauss = 28 光量点，无抖动 |
| 遮挡求值 | 每样点 1 次（`shadowtex1`，NVIDIA 分支） | 每样点 1～2 次（`shadowtex0` + 必要时 `shadowtex1`） | 8 个求值点（起点 + 7 个区间端点）：每点 2 次 `shadowtex1`（入水点与样点各一），**不读 `shadowtex0`** |
| 水面透光 | 源侧（波面法线投影） | `(1−shadow0)` 差分 | **无** |
| 相位 | 固定折射光向，`Mie g=0.7` | `VoL`（`calculateVLParameters`） | 逐 texel 波面斜率，`g=0.45`、40% 定向 |
| 消光 | 分色 `(0.1,0.6,1.0)`，`0.04·density` | 走水雾 | 分色 `(0.1,0.6,1.0)`，`0.04·density·0.01`（等价量级） |
| 云影 | 整帧标量乘子（`UnderwaterVolumetricFog.glsl:93`） | `VC_SHADOWS`/cloudShadows | 默认不生效（被 `CLOUD_SHADOWS` 门控） |
| 分辨率 | 全分辨率（composite5 主输出） | 全分辨率（composite1 主输出） | 1/16 像素数（0.25×） |
| 束形来源 | 逐样点遮挡 | 逐样点遮挡 + 水面透光 | **预烘 2D 图的包络（pow 6~10）** |

---

## 10. 本文未做的事

- 未修改任何着色器、属性或选项文件；未同步开发实例；未跑任何实机截图或帧率读数。
- 未给出「已修复」结论：所有观感判断需按 §8 的判据实机核对。
- 未裁决 §7 的五项；未把结论并入 [实现与限制](实现与限制.md) 与 [当前工作](当前工作.md)（按文档约定，应在用户选定方案后执行）。

---

## 11. 本文自校（2026-10-11 数值复核后修正）

对全文做了一次按真实噪声贴图的数值复核（脚本与复现方式见 [水下光束同类意见复核](水下光束同类意见复核-DeepSeekV4.1flash.md)），**本文有三处数值被推翻，已就地改正**：

| 位置 | 原写法 | 复核后 |
|---|---|---|
| §2.1 / 症状表「位置乱七八糟」 | 「软限幅把碰撞光量压成 2.0～3.99、纹理在这一步丢了」 | **错**。实测 `landingOffset ≤ 0.582`、`caustic³ ≤ 6.13`、软限幅只压缩高端 2.5 倍、中位数不变（0.100→0.098）。已降级为可选低优先项（§5.1 0.1b） |
| §2.1 / 症状表「固定位置」 | 「纹距 5～27 格、漂移约 0.5 格/秒、10～54 秒走完一个纹距」 | **漂移速度错 3 倍、纹距不准**。实测特征间距 11.5 格（x）× 25 格（z），漂移 **1.5 格/秒**（约 8 秒一个纹距）。「固定感」的机制改写为「世界锚定的慢成分主导 + 快成分被两级滤波抹掉」（新增 §2.8） |
| §12 差异 1 | `dist = sqrt(tan²2θ + 4)`（含 +2 常数） | **公式错**。除以自身 y 分量后 y 恒为 1，`lookupCenter` 的 +1 恰好抵消，正确结果是纯水平的 `|tan2θ|`（已数值逐点验证）。hy4 的 `2|n_xz|` 是其小角近似，量级结论不变 |

另新增 **§2.8**：生产者自身的 Nyquist 滤波（footprint=0.25 格）把 ITT 层 1 完全滤除（resolved=0.000）、层 2 只剩 0.101——这是「毫无质感」里最直接的一层（已由 step5 §2.2 与 hy4 修订版独立发现，见复核报告 §4.1）。相应地新增阶段 0.6 与裁决项 5。

---

## 12. 与同目录另三份同类意见的关系

本节只记差异，便于五份一起读。同目录另有 `grok4.7-水下光束重写意见.md`、`光束重写改动意见-GLM5.3.md`、`水下光束重写意见-hy4.md`（含 00:41 修订版）、`光束重写意见-step5.md`（均 2026-10-10～11）。**五份的完整交叉复核（含数值复算与逐份裁决）见 [水下光束同类意见复核](水下光束同类意见复核-DeepSeekV4.1flash.md)**；下面只保留与本提案直接相关的两处。

**两处需要用户注意的差异：**

1. **缓存里存「法线」还是存「碰撞光量」**。grok4.7 建议缓存只存法线、碰撞在每样点现场算（等价于 ITT `deferred.fsh:11,22-31` + `GetWavesNormalFromTex` 的原始分工，这是 ITT 的真实架构）。本文建议缓存直接存碰撞光量、按投影入口 XZ 读取。两者在数学上等价，推导（本次数值复核已逐点验证，见 §11）：`lookupCenter = worldPos+(0,1,0)`；`R = refract((0,1,0), N, 1.0)`（GLSL 在 eta=1 且 dot(N,I)>0 时返回**反射**方向）`= (0,1,0) − 2cosθ·N`；除以自身 y 分量后 y 恒为 1，因此 `lookupCenter − R/R.y` 的 y 分量恰好抵消，`dist` **是纯水平的 `|tan2θ|`**（θ 为波面倾角；hy4 写的 `2|n_xz|` 是它的小角近似，θ≤15° 时误差 <11%，量级结论一致）。所以它只依赖入口处的法线、与样点深度无关，确实是入口 XZ 的二维函数，可以预先算好。差别只在成本与灵活度：**存法线**每样点多一次法线解码与一次碰撞算术，但同一张缓存还能供水面/界面共用；**存光量**每样点省下这部分算术（8～16 个样点省 8～16 次）。这不是正确性问题，可按性能实测二选一。
2. **水下透光项的颜色来源**。grok4.7 写「水下透明颜色应来自 Astra 现有 `shadowcolor0` 的投射颜色」。据本仓源码，这条若照字面实现会出错：Astra 的 `shadowcolor0` 对水平水面写的是**编码水高（R）与焦散 focus（A）**，GB 明确标注无读者（`program/shadow.fsh:88-102`）；只有**非水**半透明投射物（玻璃等）才在 GBA 存染色（`program/shadow.fsh:104-127`、`global/lighting/shadowmap.glsl:88-99`）。所以水下体积的染色应取 Astra 的水色常量（如 `lib/water_palette.glsl:9` 的 `astraWaterShaftTintSqrt`）或专用的透射色，**不能直接读 `shadowcolor0`**；需要颜色而不是标量时，应新增记录而不是改变现有语义。

其它各家与本提案的差异及裁定（GLM5.3 的「单入口」前提不成立与「加时域抖动靠 TAA」应驳回、hy4 的 R2 量级与 R4 机制、`colortex1` 实为 0.25× 等）已集中写在 [复核报告](水下光束同类意见复核-DeepSeekV4.1flash.md) 的 §2、§3、§5，不在本文重复。
