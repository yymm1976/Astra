# IterationT 3.2.0 优化设计专项阅读 + Astra 取舍

配套文档：`docs/2026-09-11-iterationt-3.2-source-review.md`（那份偏"效果/算法设计"，本份专看**性能**）。
来源：`_analysis/latest-2026-09-10/iterationT-3.2.0`。

前提：ITT 画质上限很高、硬件要求也高，但**它的成本是被精心分级和摊销过的**，不是"堆出来"的。
Astra 的定位是极致优化，所以下面每条都给出"抄 / 不抄 / 改造后抄"的结论。

---

## 1. 先看它的成本结构

| 维度 | ITT 3.2 | Astra 现状 |
|---|---|---|
| 画质档位 | **5 档**（Low/Medium/High/Ultra/Extreme） | 3 档（流畅/均衡/极致） |
| 根层 pass | 45 个 `.fsh`、17 个 composite | 4 个 composite |
| 缓冲 | 8 张 colortex，仅 1 张降分辨率 | 8 张，godrays 用 0.5x |
| 阴影采样 | 4 → 32（VPS_QUALITY 五档） | 固定 16 抽头 |
| GI | RSM，**0.25/0.5 分辨率** + 时域 + 空间滤波 | 无 |
| 大气 | **预算 LUT**（493 行 Bruneton 实现） | 每像素直算 |
| 云 | NUBIS 体积云，5 步探测 + 自适应步长 | 平面云 |
| 时域 | TAA（默认开） | **无 TAA**（设计前提） |

**第一个结论**：ITT 的成本控制不靠"某个绝招"，而是**三件事叠加**——
① 贵的 pass 在低档位**根本不编译**；② 能预计算的预计算；③ 能摊销到多帧/低分辨率的就摊销。

---

## 2. 逐条设计（含证据与取舍）

### A. 程序级 gating：低档位省掉整条 pass ★★★ 必抄

`shaders.properties:61-105` 用 `program.*.enabled=<选项>` 把整条 pass 挂到选项上：

```
program.deferred1.enabled=GI_RSM        # GI 整条 deferred 不开就不跑
program.deferred4.enabled=CLOUD_SHADOW  # 云影
program.composite3.enabled=ENABLE_PBR   # PBR（两段）
program.composite6.enabled=DOF
program.composite9..13.enabled=BLOOM    # bloom 五段
program.gbuffers_spidereyes.enabled=EYES_LIGHTING
```

配合 Low 档把 `GI_RSM=false / GTAO=false / DOF=false / VOLUMETRIC_CLOUDS=false / VFOG=false`
全部关掉——**Low 档编译并运行的程序数量远少于 High**，不是"跑同样的 pass 但少采样"。

**取舍：抄，但要知道我们已经做了一半。** 核对现状：Astra 的 `shaders.properties` 里
**已有 22 条 `program.*.enabled`**（`program.composite1.enabled=BLOOM`、
`program.composite4.enabled=BLOOM`、`world-1/composite3/4.enabled=false` 等），
方向与 ITT 一致。**真正的缺口**是那些"目前只靠着色器内早退"的效果：
godrays（`#ifndef GODRAYS return`）、水下光束（`#ifdef ASTRA_UNDERWATER_SHAFTS` 只是分支）、
水面散射（composite2 恒开）。这些应当改成 `program.*.enabled` 门控——
**关掉就等于不编译、不运行、不烧带宽**，而不是跑进去再 `return`。

### B. 质量旋钮成组缩放 + 低档直接关特性 ★★★ 必抄

五档把每个采样数一起缩放（`shaders.properties:317-321`）：

| 选项 | Low | Medium | High | Ultra | Extreme |
|---|---|---|---|---|---|
| VPS_QUALITY（阴影） | 4 | 12 | 16 | 24 | 32 |
| GI_QUALITY | 8 | 12 | 16 | 24 | 32 |
| GI_RENDER_RESOLUTION | 0.25 | 0.25 | 0.5 | 0.5 | 0.5 |
| GTAO_QUALITY / SLICE | 2/2 | 3/2 | 3/3 | 4/4 | 6/5 |
| SSS_QUALITY | 4 | 4 | 6 | 8 | 16 |
| VFOG_QUALITY | 4 | 4 | 6 | 6 | 12 |
| CLOUD_QUALITY | 1.0 | 1.0 | 1.0 | 1.6 | 2.5 |
| DOF_QUALITY | — | — | — | 15 | 20 |
| 特性开关 | 关/关/关 | 开 | 开 | 开 | 开 |

注意 GI 在 Low/Medium 直接降到 **0.25 分辨率**——降分辨率比减少采样数更有效。

**取舍：抄，但保持 3 档。** Astra 应把每个效果的主采样数做成"跟着档位走"的显式常量，
而不是让用户在一个固定算法上滑样本数。我们的 `UNDERWATER_SHAFT_SAMPLES`（4/7/10）已经是这个思路。

### C. 预计算大气 LUT ★★★ 抄（我们有现成的成本痛点）

`Lib/BasicFounctions/PrecomputedAtmosphere.glsl`（**493 行**）是完整的 Bruneton 预计算散射：

- `GetScatteringTextureUvwzFromRMuMuSNu`（r, μ, μ_s, ν 四维参数化压进 3D 纹理坐标）
- `GetTransmittanceTextureUvFromRMu`、`GetCombinedScattering`、`GetExtrapolatedSingleMieScattering`
- 查表就是一句：`textureLod(colortex8, vec3(uv, 32.5/33.0), 0.0)`
- LUT 存在 `colortex8`，并且 `size.buffer.colortex8=2.0 2.0`（**半分辨率**）、RGBA8

**这是 ITT 最值钱的优化。** 对比 Astra：`global/water/reference_light.glsl::waterRef_SkyColor`
**每像素**算一次物理大气（两次大气采样点、每点再做视线与太阳方向的光学深度积分、双散射），
几十行超越函数，而且水、雾、天空多个消费者各调一次。

**取舍：抄。** 把大气预算成一张 LUT 是本项目最该做的一步。而且我们已经有
`colortex8` 空着、已有 8 张缓冲的布局。

### D. 时域摊销（TAA + 蓝噪声时间抖动）★☆☆ 不抄，但要理解代价

`Lib/BasicFounctions/TAA.glsl`（381 行，YCoCg 邻域裁剪 + 双三次历史重投影）
配合 `TemporalNoise.glsl` 的 11 行：

```glsl
vec2 BlueNoiseTemproal(){
    return fract(texelFetch(noisetex, ivec2(gl_FragCoord.xy) % 64, 0).xy
                 + vec2(goldenRatio, plasticRatio) * vec2(frameCounter % 64));
}
```

**空间蓝噪声 + 时间黄金比偏移**。这是它敢在 VPS(4~32)、VFOG(4~12)、GI(8~32) 里用这么少采样的根本原因：
采样噪声被跨帧累积平均掉，单帧不干净但**时域上是干净的**。

**取舍：不抄 TAA**（Astra 的设计前提是无 TAA、前向一次算完，引入会推翻既有取舍）。
但要把代价说清楚：**我们每个效果只能用空间手段去噪**，所以
① 采样数不能低到 ITT 那个量级；② 抖动必须用**空间**低差异序列（Bayer / R1 / R2）而不是时间偏移；
③ 宁可用更聪明的解析近似（如焦散的几何聚焦量）也不要用少采样 + 时域平均。

**可以借的那一半**：`Sequences_R1/R2`（黄金比/塑胶比低差异序列）与 `bayer2..128` 递归构造，
都是**纯空间**的，Astra 可以直接用，用来替代我们现在手写的 `fract(sin(dot(...)))` hash。

### E. 多分辨率 + 时域 + 空间去噪（GI 三段式）★★☆ 改造后抄思路

`GlobalIllumination.glsl::RSM` → `GI_TemporalFilter` → `GI_SpatialFilter`：
先算**低分辨率且带噪**的间接光，再时域累积，再空间去噪。三段式而不是"一次算对"。

**取舍：不抄 GI**（RSM 需要额外 shadow 通道与时域），但**三段式的思路可以用在我们的雨环/光束上**：
低分辨率算 + 空间去噪 + 与全分辨率信号叠合。

### F. 半分辨率缓冲 ★★☆ 抄

`size.buffer.colortex8=2.0 2.0` —— 整包只降了这一张，因为它是 LUT，不需要全分辨率。
Astra 目前 godrays 用 0.5x（`colortex1`），是同类做法。

**取舍：抄，扩大使用面。** 可考虑把"雨滴溅射累积"、"云影"这类低频信号放进半分辨率缓冲。

### G. 硬件阴影过滤 + mipmap ★★★ 必抄（**核对后发现我们关着**）

`composite.fsh:44-52` 生效声明：

```
const bool shadowHardwareFiltering1 = true;
const bool shadowtex0Mipmap        = true;
const bool shadowtex0Nearest       = false;
```

并在 `#ifdef MC_GL_VENDOR_NVIDIA` 下把 `shadowtex1` 声明为 `sampler2DShadow`（硬件比较采样）。

**核对结果：Astra 现在是 `shadowHardwareFiltering = false`**（`lib/settings.glsl:228`），
而 ITT 是 `true`。我们等于放弃了硬件比较采样，用手写抽头去模拟——**这是白扔的性能**。

**取舍：抄，且这是本轮最便宜的一条。** 改成 `true` 并相应声明
`shadowtex0Mipmap`，可以把手写 PCF 的抽头数降下来。需要实机确认一次采样质量
（硬件过滤的半影比手写更"方"，可能要配 `SHADOW_SOFTNESS` 微调）。

### H. 把两个压倒性成本旋钮直接暴露给用户 ★★★ 必抄

```glsl
const int   shadowMapResolution = 2048; // [1024 2048 4096 8192 16384 32768]
const float shadowDistance      = 192.0;// [64.0 96.0 128.0 192.0 256.0 384.0 512.0 768.0 1024.0 1536.0 2048.0]
```

阴影分辨率与距离是**成本的第一、第二项**，ITT 让用户直接选，范围给得非常宽
（1024→32768，64→2048）。另一处**核对出的具体差距**：`shadowDistanceRenderMul` ITT 是 1.0，**Astra 是 1.5**
（`lib/settings.glsl:208`）——意味着我们把投射体渲染到接收距离的 1.5 倍远，这部分几乎全是
看不见的开销。`shadowIntervalSize` ITT 是 4.0、**Astra 是 0.5**（差 8 倍，`settings.glsl:211`），
这个值控制顶点吸附的间隔，值得单独实测：间隔小通常更稳但顶点处理更频繁。

**取舍：抄。** Astra 的 `SHADOW_RESOLUTION` 只有三档值、`SHADOW_DISTANCE` 也是。
我们应该给出更宽的可选档，并把"默认档"定在实测最优性价比处。

### I. MRT 一次写多张缓冲省 pass ★★☆ 抄

`/* DRAWBUFFERS:13 */`（composite5 同时写 colortex1 与 colortex3）、`DRAWBUFFERS:1 3` 等。
阴影、VFOG、GI 都靠 MRT 并行输出，避免"再开一个 pass 写另一张"。

**取舍：抄。** Astra 的水面 pass 已经用了 `RENDERTARGETS: 0,5`，可以把这个做法推广到
"雾 + 光照标记"这类本来就同时产出的数据。

### J. 带宽压缩：位打包 / 法线编码 / YCoCg ★★☆ 抄

- `Pack2x8 / Pack2x16 / Unpack*`：两次要数据塞进一个通道
- `EncodeNormal / OctWrap`（八面体编码）：一张 RG16 存世界法线
- `RGB_To_YCoCg / YCoCg_To_RGB`：色度拖影更小，且 YCoCg 常用于压缩
- 大量缓冲区用 RGBA16 而不是 RGBA32F

**取舍：抄。** Astra 的 `colortex3` 已经在做类似的事（R 光照标记 / GB 积水法线 / A 覆盖），
方向一致；可以进一步把高精度不需要的缓冲降格式。

### K. 廉价数学工具箱 ★★☆ 抄（长期积累）

`Lib/Utilities.glsl`（302 行）：

| 函数 | 实现 | 场景 |
|---|---|---|
| `fsqrt(x)` | `intBitsToFloat(0x1fbd1df5 + (floatBitsToInt(x) >> 1))` | 任意"够用就行"的开方 |
| `fsign(x)` | 位掩码 | 无分支符号 |
| `facos(x)` | `(-0.156583*\|x\| + hPI) * fsqrt(1-\|x\|)` | 替代 `acos` |
| `bayer2..bayer128` | `bayer4 = bayer2(0.5a)*0.25 + bayer2(a)` 递归 | 空间抖动，无纹理 |
| `Sequences_R1/R2` | `fract(0.5 + n/φ)` 等 | 固定采样数的低差异分布 |
| `AlmostIdentity(x,m,n)` | 两分支三次多项式 | 替代 `clamp`+`smoothstep` 链 |
| `textureSmooth()` | 坐标量化到 64 格 + `curve()` 平滑后 `textureLod` | 用最近邻纹理拿到平滑插值 |

**取舍：抄。** 这些是"极致优化"该有的家底，且**全部与 TAA 无关**，可以逐条替换我们现在的写法。

### L. 几何步进探测（空区跳过）★★☆ 改造后抄

`NUBIS.glsl:77`：`for (int i = 0; i < 5; i++, stepLength *= 1.5)` —— 先用 5 步、
每步 ×1.5 的**几何增长**粗探云层位置，再在命中区做细步进。
`NUBIS.glsl:130`：`marchingSteps = floor(marchingSteps * CLOUD_QUALITY)` —— 质量档直接乘步数。

**取舍：抄思路。** 我们的水下光束(VFOG)目前是**均匀间距**，可以改成"先粗探阴影边界、
再在明暗过渡带加密"，同采样数下光束边缘更软——**正好治"像实体锥"**。

### M. 提前退出 ★★★ 抄

全包 51 处 `return / break` 早退：体积雾的 `if (transmittance < 0.0001) break;`、
VL 的 `if (rayLength > endDistance) break;`、天空/雾的距离早退等。
黑色部分直接跳过剩余积分——**不透明介质一旦挡住就没有后续意义**。

**取舍：抄。** 我们的 nether 体积雾、光束都应加 transmittance 早退（现在只在黑色体积里加了）。

### N. 不锁缓冲格式 ★☆☆ 参考，不照抄

ITT 把整块 `colortex*Format / Clear` 声明**注释掉**（`composite.fsh:11-56`），
完全用 Iris 默认值。好处是少一层出错面；代价是拿不到精细的带宽优化。

**取舍：不照抄。** Astra 有 `lib/water_buffer_formats.glsl` 显式声明，
对带宽敏感的项目应该继续显式控制——但可以借它"少即是多"的精神，别为了 HDR 全开 RGBA32F。

### O. 厂商分支 ★☆☆ 按需

`MC_GL_VENDOR_NVIDIA` 出现在 7 个文件（AMD/Intel 各 0）。主要用于：
`shadowtex1` 用 `sampler2DShadow` 走硬件比较；VFOG 在 NVIDIA 上读 `shadowtex1` 而非 `shadowtex0`。

**取舍：可抄但优先度低。** 目标机器是 RTX 4050，NVIDIA 分支收益直接；
但双路径意味着双份维护与双份测试，先做通用优化。

### P. 可选超分 FSR ★☆☆ 不抄（当前）

`FsrEASU.glsl` 存在且 `composite16` 会 include，但选项默认是 `//#define FSR`（**关闭**）。
说明作者把它当可选项而非默认路径。

**取舍：不抄。** Astra 主打"清爽原味 + 性能"，超分会引入锐化/边缘伪影，
与"不抢戏"的定位冲突。真要做也应该作为独立档位，而不是默认。

---

## 3. 给 Astra 的取舍清单（按"省下的毫秒/工作量"排序）

| 优先级 | 项 | 预计收益 | 风险/成本 | 与现有设计冲突 |
|---|---|---|---|---|
| P0 | **大气预算成 LUT** | 高（每像素省几十次超越函数，且被多处复用） | 中：要写 LUT 生成 pass + 改造 consumers | 无 |
| P0 | **程序级 gating：把可选效果挂到 `program.*.enabled`** | 高（关掉＝不编译不跑不烧带宽） | 低 | 无 |
| P1 | **廉价数学工具箱**（fsqrt/fsign/facos/Bayer/R1R2/AlmostIdentity/textureSmooth） | 中：全局摊薄 | 低 | 无（与无 TAA 兼容） |
| P0 | **`shadowHardwareFiltering` false→true + mipmap** | 中：省掉手写 PCF 抽头（当前是白扔） | 低：改 directive，需实机看一次质量 | 无 |
| P1 | **`shadowDistanceRenderMul` 1.5→1.0** | 中：少渲染不可见的投射体 | 低：改常量，需实机确认远处阴影不缺失 | 无 |
| P1 | **体积步进的空区跳过 + transmittance 早退** | 中：光束/雾 | 低 | 无 |
| P2 | **拓宽阴影分辨率/距离可选档位** | 低（但对用户是刚需） | 低 | 无 |
| P2 | **半分辨率缓冲用于低频信号** | 低-中 | 低 | 无 |
| P2 | **位打包 / 法线编码压带宽** | 低-中 | 低 | 无 |
| P3 | 厂商分支（NVIDIA 硬件阴影） | 低 | 中：双路径维护 | 无 |
| — | TAA / GI / FSR / 体积云 | 高画质 | 高 | **与"无 TAA、前向一次算完"冲突，不做** |

---

## 4. 一句话结论

ITT 3.2 值得我们学的不是某个算法，而是三条成本纪律：
**① 贵的 pass 在低档位根本不编译；② 能预算的绝不每像素算；③ 能摊销到低分辨率/多帧的就不全价算。**
Astra 放弃了第③条（无 TAA），所以必须把第①②条做到位，并且在"单帧就得干净"的约束下
优先选**解析近似**（如焦散的几何聚焦量）而不是"少采样 + 靠时域洗噪"。

## 5. 授权

IterationT 归档不含许可文件，按专有处理。本笔记只记录设计思路与取舍；
任何代码级移植须逐条登记 `THIRD-PARTY.md`，并受 `design.md` 9.3 发布闸门约束。
