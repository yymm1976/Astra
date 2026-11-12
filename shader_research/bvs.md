# BVS - Best Vanilla Shader v1.9.3 研读报告（面向 Astra 的可借鉴点）

- **对象**：`reference_shaderpacks/bvs/`（83 文件，324 KB）；**版本** 1.9.3、**作者** LoLip_p（`reference_shaderpacks/INDEX-batch2.md:25`、`P:PATREON.txt:1`）。
- **生成方式**：子代理调研（行号全部来自本次实际读取；成稿后自抽查见附录）；**调研日期** 2026-10-02。
- **引用**：`P:` = 相对 `reference_shaderpacks/bvs/`；`A:` = 相对 `Astra/shaders/`。

---

## ① 包概览

极小体量的"原版观感 + PBR + 阴影"包：无 LUT、无体积雾、无 TAA、无 compute/自定义图像，全部工具代码只有 690 字节的 `P:shaders/lib/util/dither.glsl`。下载量 653,921（`reference_shaderpacks/INDEX-batch2.md:25`）说明"极简但能打"在真实用户里成立——Astra 缺的不是又一个完整包，而是**能放进最低档位的极小实现**。

**许可证（口径偏差点，必读）**：批次二索引记录为 **CC-BY-4.0（可合法借鉴）**，来源是 Modrinth API 元数据（`reference_shaderpacks/INDEX-batch2.md:25`；同文件 `:70-71` 把它列入"代码级借鉴风险最低"的五包）。但**包内不存在任何许可证正文本文件**：`ls -la` 只有 `PATREON.txt`（19 字节）与 `shaders/`；`find -iname "*license*"` 无命中；`unzip -l reference_shaderpacks/zips/bvs.zip | grep -ci license` = 0；对 `shaders/` 全目录 grep `license|copyright|CC-BY` 只命中人名。因此**无法给出"包内 LICENSE 原文行号"**，可给的最接近替代：

| 用途 | 位置 | 内容 |
|---|---|---|
| 许可结论来源 / 风险归类 | `reference_shaderpacks/INDEX-batch2.md:25`、`:70-71` | "CC-BY-4.0（可合法借鉴）"；五包低风险名单含 bvs |
| 作者链接 | `P:PATREON.txt:1` | `patreon.com/lolip_p` |
| 包内署名（设置页 / 长文案） | `P:shaders/settings.glsl:1`、`P:shaders/lang/en_US.lang:21` | `#define BY 0 // By LoLip_p`；Discord/YouTube 链接 |
| 源文件头（5 处） | `P:shaders/world0/composite.fsh:3`、`world0/final.fsh:3`、`world0/final.vsh:3`、`world-1/final.fsh:3`、`world1/final.fsh:3` | `// Shader by LoLip_p` |

该偏差已列入备注第 1 条。

---

## ② 架构与特性清单

### 2.1 管线（关键差异：没有 deferred）
```
gbuffers_*（albedo / lightmap / normal）
 → composite.fsh  阴影 + 光照贴图 + 雾 + AO   ← 占 deferred 的位置
 → composite1.fsh SSR + AO 合成   （P:shaders/shaders.properties:23：SSR || AO 才启用）
 → composite2.fsh DOF + 自动曝光  （P:shaders/shaders.properties:24：DOF || AUTO_EXPOSURE）
 → final.fsh      FXAA 或运动模糊 + 调色
```
- 无用到的 pass 由 `program.*/composite*.enabled` 整程序关掉（`P:shaders/shaders.properties:23-24`）；无 `.csh`、无 `prepare*`、无 `taa_*`。
- 三维度：`world0` 全量 38 文件；`world1`/`world-1` 各 16 文件（5 个精简 gbuffers + composite1/2 + final，例 `world1/gbuffers_basic.fsh` 全 30 行）；路由 `P:shaders/dimension.properties:1-5`。

### 2.2 G-buffer 布局与程序间契约
colortex0 = albedo + 覆盖度 a（`P:shaders/world0/gbuffers_terrain.fsh:69-70`）；colortex2 = RG lightmap 坐标 / B 直接光 / A 覆盖度（`:71`）；colortex3 = SSR 用 2 通道法线，非水体写 `vec2(0.001)`（`gbuffers_water.fsh:52`），实体掩码写 `vec3(1,0,0)`（`gbuffers_entities.fsh:54`）；colortex4 = 视空间几何法线 `*0.5+0.5`（`gbuffers_terrain.fsh:72`）；colortex5/6 = 曝光历史 / AO(R)（`composite2.fsh:154-156`、`composite.fsh:387-389`）。格式常量在包内是**注释状态**（`world0/composite.fsh:33-41`、`world-1/composite1.fsh:7-12`）——抄注释不等于生效。

### 2.3 光照与阴影
曲线 `1.75*x³`（`P:shaders/world0/composite.fsh:153-157`）与 `x⁴`（`:159-162`），常用其天空分量 `.g` 压阴影/环境（`:320`、`:373`）；光吸收 `LIGHT_ABSORPTION` 从火把项扣天空暴露，只扣有火把处（`:171-191`，扣减 `:184-186`）。日间标量 `state`（04:00 前→1、20:00-21:40 回落）在 `:45-55`，另 7 处同款定义（`gbuffers_terrain.vsh:43`、`gbuffers_water.vsh:24`、`gbuffers_entities.vsh:21`、`gbuffers_clouds.vsh:13`、`gbuffers_skybasic.fsh:26`、`dh_terrain.fsh:34`、`dh_water.fsh:34`），夜间补光链 `:279-285`、`:324-328`。阴影：半透明透射 `:92-105`；PCF `(2*SOFT+1)²` 抽 + 每像素 hash 旋转（`:126-142`，`1/resolution` 折进旋转矩阵 `:130`）；距离衰减 `1-pow(1-fade,10)`（`:144-147`）；像素阴影吸附 `:118-120`；扭曲 `distort.glsl:1-7`，阴影顶点端同源 `shadow.vsh:8-13`。

### 2.4 环境光遮蔽
全分辨率 + 深度重建位置 + colortex4 法线；金螺旋 `spiralAO`（`P:shaders/world0/composite.fsh:224-239`：`phase=hash12((uv+frameTimeCounter)*100)*6.28`、`radius += step`、`phase += 2.4`），单抽评分 `doAO`（`:213-221`）；距离淡出 `pow(smoothstep(0,1,1-d/(far/1.5)),0.25)` 且 `fade>0.15` 才采样（`:343-361`）。

### 2.5 天空 / 云 / 天气 / 星
天空现算：`fogify(x,w)=w/(x²+w)` 混合 `skyColor`/`fogColor`（`P:shaders/world0/gbuffers_skybasic.fsh:22-24`、`:38-48`，`upDot` 由 `gbufferModelView[1].xyz` 得 `:39`）；星点靠 `gl_Color` 的 R=G=B 灰阶判据（`gbuffers_skybasic.vsh:15`，用 `:53-55`）；云用引擎原生几何（`gbuffers_clouds.vsh:25-45`、`.fsh:11-23`，靠 `gl_Fog.color.rgb != 0` 判贡献 `:17-20`）；雨条 alpha/色调重算（`gbuffers_weather.fsh:17-19`）。

### 2.6 水体
`block.1000 = water`（`P:shaders/block.properties:1`）判定 `int(mc_Entity.x+0.5)==1000`（`gbuffers_water.vsh:80`）；水下 lightmap 偏移 `LC += vec2(0.2)` 与岩浆 albedo（`gbuffers_terrain.fsh:33-38`）；水面法线由噪声扰动只写 colortex3（`gbuffers_water.fsh:39-46`）；波浪双正弦、仅 y 位移（`gbuffers_water.vsh:79-88`）。

### 2.7 顶点动画
区块加载动画 `effect()`：`offset = 0.03/(d-1)+0.03+0.05*d²`、`pos.y += offset*10`、`d=length(pos.xz)/far`（`P:shaders/world0/gbuffers_terrain.vsh:55-67`，水方块同款 `gbuffers_water.vsh:53-65`）；摇曳仅对 `10106/10018`（`P:shaders/block.properties:6-15`），位移夹到本方块剩余空间 `clamp(wave,-fy,1-fy)`（`gbuffers_terrain.vsh:79-90`）。

### 2.8 远景观测（DH）
`dh_terrain`/`dh_water` 是自成一套的前向着色：自带曲线副本（`P:shaders/world0/dh_terrain.fsh:60-94`、`dh_water.fsh:78-94`）、自带 state、用 `dhNearPlane/dhFarPlane` 做雾交接（`dh_terrain.fsh:165-167`）、`if (depth != 1.0) discard;` 让位近景（`:113-117`）；入口直接拿 DH 属性（`dh_terrain.vsh:14-32`）。

### 2.9 后处理
FXAA 3.11（`P:shaders/world0/final.fsh:24-184`，12 级步长数组 `:17`）；运动模糊（`:194-233`，Bayer64 抖动 `:241`）；DOF 60 抽常数表（`composite2.fsh:19-100`）；自动曝光（`:107-120`、`:142-156`，**tonemap 逗号运算符缺陷 `:125`**）；调色（`final.fsh:250-258`）；Bayer 递归链（`lib/util/dither.glsl:5-12`）。

### 2.10 设置与 2.11 bvs 明确没有的
设置：3 档 profile 打包 AO/波浪/摇曳/阴影距离与分辨率/`program.enabled`（`P:shaders/shaders.properties:8-10`，第三档原拼写 `MIMIMALISM`）；screen 分组 `:13-19`（5 个活动子页，Bloom 页 `:15` 被注释）；滑块 `:21`；7 语言 UI。**没有**：TAA/时域累积、体积雾与光轴、程序化云、延迟管线、LUT/SH 天空、彩色点光、SSS、自定义图像/compute、复杂方块分类（只有水 1000/岩浆 1001/树叶 10018/藤蔓 10106 四类）。

---

## ③ Astra 可借鉴点（13 条）

**1. 单标量"日间状态"驱动全管线（含夜间补光）** — `P:shaders/world0/composite.fsh:45-55`、`:271`、`:279-285`、`:324-328` / `A:lib/twilight.glsl` + `A:global/lighting/diffuse.glsl`（无 state 概念）/ **小**。`LightmapColor *= mix(5,1,state)`（`:324`）、`lightBrightnessV += 0.2*(1-state+rain*state)`（`:285`）这类非物理补偿正是原版夜景观感来源；风险：与 Astra 色温/环境分档打架（⑥）。新方向。

**2. 每像素旋转 + `1/resolution` 折进旋转矩阵** — `P:shaders/world0/composite.fsh:126-130`（`:130` 原注释 "small speedup"）/ `A:global/lighting/shadowmap.glsl:102-131` / **很小**。Astra 已删 noisetex（`A:lib/settings.glsl:337`），hash 取角正合适；但 Astra 无 TAA（`A:lib/dither.glsl:5-7`），**只借静态相位，不借逐帧相位**。批次一重复：是。

**3. AO：每像素相位螺旋 + 距离淡出** — `P:shaders/world0/composite.fsh:224-239`、`:213-221`、`:343-361` / `A:program/ssao.fsh:62-104`（固定 12 抽、无相位、无距离项）、`A:lib/ao_resolve.glsl:54-91` / **小**。无 TAA 时固定采样环必然条带；淡出须落在 `extra = max(vertexAO - min(vertexAO, visibility), 0)`（`A:lib/ao_resolve.glsl:89`）。批次一重复：是。

**4. 一行 `fogify` 地平线天空-雾混合** — `P:shaders/gbuffers_skybasic.fsh:22-24`、`:38-48` / `A:global/atmosphere/sky_gradient.glsl:172-195` / **小**。1 除法给出极简档天空。批次一重复：是。

**5. 顶点级"区块加载动画"偏移** — `P:shaders/world0/gbuffers_terrain.vsh:55-67`、`:73-77`、`gbuffers_water.vsh:53-65` / **Astra 无**（全仓 `grep -rn chunk` 零命中）/ **小**。**抄时必须补**：bvs 的 `shadow.vsh:8-13` 未套同一偏移 → 模型/阴影错位；Astra 须在 `A:program/lit.vsh` 与 `A:program/shadow.vsh` 同源求值。新方向。

**6. 顶点位移夹到本方块剩余空间（不做顶点分类）** — `P:shaders/world0/gbuffers_terrain.vsh:79-90`、`gbuffers_water.vsh:79-88` / `A:lib/wind.glsl:167-211`（需 `at_midBlock.y<0` 门控 `:156-157`）/ **小**。不需分类，代价是波形硬截断。批次一重复：是。

**7. 到玩家距离驱动的阴影偏移** — `P:shaders/world0/composite.fsh:84-90`、`:93` / `A:global/lighting/shadowmap.glsl:189-196` / **很小**。非法线偏移，斜面更易漏光。批次一重复：是。

**8. 极便宜的自动曝光：读 colortex0 单个 mip 中心像素** — `P:shaders/world0/composite2.fsh:107-120`、`:142-156` / `A:global/post/exposure.glsl:82-101`、`:55-58` / **小**。采样 64→1，但无 NaN/历史有效性保护；**勿同时搬 `:122-128` 的 Tonemap**（`:125` 逗号运算符丢弃右值）。批次一重复：是。

**9. 相机运动模糊：深度重投影 + 9 抽 + 抖动首抽** — `P:shaders/world0/final.fsh:194-233`（`:196`/`:215`/`:218`/`:225-229`）/ **Astra 无**（`grep -rln "MOTION_BLUR\|MotionBlur"` 零命中）/ **小**（约 40 行）。只用相机位移重投影（`:208-213`），**不含物体运动**，移动实体会被错误拉花。批次一重复：是。

**10. 60 抽金螺旋景深 + 每抽 mip LOD** — `P:shaders/world0/composite2.fsh:19-80`、`:82-100`（`:86` 的 fovScale、`hand = z<0.56`）/ **Astra 无** / **小**。批次一重复：是。

**11. 远景观测的第二套前向着色 + 除式雾交接（本包最高价值项）** — `P:shaders/world0/dh_terrain.fsh:111-170`（`:165-167` 交接、`:113-117` 让位、`:60-94` 曲线副本）、`dh_terrain.vsh:14-32` / Astra 的 Voxy 是空壳：`A:voxy_opaque.glsl:1-5`（`// TODO(C5)`）、`A:voxy.json` 0 字节、`A:lib/settings.glsl:319` 连开关都是注释态 / **中**。`(d-near)/(far-d)` 在 `d→far` 前即饱和到 1，天然无接缝；`depth != 1.0`（`:113-117`）是浮点精确比较，移植应改 `> 0.9999`。新方向。

**12. 无 3D 纹理的立方噪声（z 切片两抽插值）** — `P:shaders/world0/dh_terrain.fsh:96-105`、`:132-135` / `A:lib/settings.glsl:337`（noisetex 已删除）、`A:global/water/particles.glsl:24`（现用整型 hash）/ **小**（采样源须换 hash）。新方向。

**13. 原版细节两处 1-3 行改法** — (a) 星点灰阶判据 `P:shaders/world0/gbuffers_skybasic.vsh:15`、`.fsh:53-55`，可整段跳过程序化星场（`A:global/atmosphere/stars.glsl`、`A:lib/settings.glsl:100`）；(b) 雨条重着色 `P:shaders/world0/gbuffers_weather.fsh:17-19`，对照 `A:lib/rain_particles.glsl:10-19` + `A:global/atmosphere/weather.glsl:21-40`（互补）/ 均 **小**。(a) 新方向，(b) 批次一重复。

**③ 汇总**：③2 PCF、③3 SSAO、③4 天空雾、③6 摇曳/水波、③7 bias、③8 自动曝光、③9 运动模糊、③10 景深、③13(b) 雨 均已在批次一出现（③2 八份、③8 十一份、③9 七份，其余二至五份；详见 `shader_research/` 非 batch2 报告）。③1、③5、③11、③12、③13(a) 为新增方向。

---

## ④ Astra 已有对应实现对照

| 子系统 | bvs（P） | Astra（A） | 哪边更省 | 误差来源 / 结论 |
|---|---|---|---|---|
| 半透明+彩色阴影 | `world0/composite.fsh:92-105`：每抽 2 次 Visibility + 1 次 shadowcolor0 | `A:global/lighting/shadowmap.glsl:102-131`：1 次 gather 得 4 角，仅确有半透明时 `texelFetch`（`:115-128`） | **A 明显更省** | P 单点采样色近似透射、`a` 兼作水量与玻璃染色；A 逐角保留 caster，更准。不要移植 P |
| 软阴影 | `world0/composite.fsh:107-150`：`(2*SOFT+1)²` 抽 × 每抽 3 纹理 | `shadowmap.glsl:102-131`、硬件比较 `:89-95` | A 省 | P 逐帧旋转（`:126`）无 TAA 时会闪 |
| AO | `world0/composite.fsh:213-239`：全分辨率 16 抽 | `A:program/ssao.fsh:22-117`：半分辨率 12 抽 + 双边放大 `A:lib/ao_resolve.glsl:19-52` | A 省 | P 直乘 albedo（`world0/composite1.fsh:132-136`）会压暗自发光/天空；A 只压环境项（`ao_resolve.glsl:84-90`）且输出 bent normal |
| 阴影偏移 | `world0/composite.fsh:84-90` | `shadowmap.glsl:189-196`、`shadowGrazingBias` `:153` | 相当 | P 非法线偏移，斜面漏光风险高 |
| 光照贴图曲线 | `world0/composite.fsh:153-169`（`1.75x³`/`x⁴`） | `A:global/lighting/blocklight.glsl:84-108`（`pow4` + 天空抑制 + 手持光 `min(1,a+b)`） | 相当 | P 是手感曲线；A 的抑制项有出处。P 的 `LIGHT_ABSORPTION`（`:184-186`）可作 A 侧廉价对照 |
| 2 通道法线 | `world0/gbuffers_water.fsh:22-24` / `world0/composite1.fsh:36-44` | `A:lib/encoding.glsl:30-45`、量化 `:51-63` | 相当（A 解码少一次 sqrt） | P 编码在 `z→-1` 误差集中；A 八面体全域均匀，已更优 |
| SSR | `world0/composite1.fsh:59-95`（15 抽、`maxf=3` `:68`、`cdist` 淡出 `:46-48`/`:84`、`F0=0.09` `:117-128`） | `A:program/deferred.fsh:34`、开关 `A:lib/settings.glsl:137` | A 更完整 | P 的 `inc=2.2`/`ref=0.2` 手调步长掠射角会漏；`:97-104` 的 `blur()` 调用点被注释（`:133`），**死代码** |
| 自动曝光 | `world0/composite2.fsh:113-120`：1 抽 mip + 1 texel 历史 | `A:global/post/exposure.glsl:82-101`、`:105-143` | **P 采样数省**；A 鲁棒性省 | P 无 NaN/历史有效性保护；A 有（`:99`、`:110-116`） |
| Tonemap | `world0/composite2.fsh:122-128`（缺陷 `:125`） | `A:lib/tonemap.glsl:191-203` | A | P 实际只是除以白点；且 `world0/final.fsh:250` 用 `pow(color,0.45)`、`world1/final.fsh:21`/`world-1/final.fsh:21` 用 `pow(color,0.8)`，三维度不一致 |
| FXAA | `world0/final.fsh:24-184`（3.11 全文 + 12 级数组 `:17`） | `A:global/post/fxaa.glsl:24-93`（Arc 派生，24 次 luma 读 + 深度轮廓门 `:30-39`） | **A 省** | P 用全局 `finalUv` 产生副作用（`:10`、`:177-182`）且无 clamp 采样；A 显式声明不做 HDR/log 解码（`fxaa.glsl:5`） |
| 运动模糊 / 景深 | `world0/final.fsh:194-233` / `world0/composite2.fsh:19-100` | **均无** | P 有 A 无 | 见 ③9、③10 的误差来源 |
| 远景地形（DH/Voxy） | `world0/dh_terrain.fsh:111-170` + `world0/dh_water.*` | `A:voxy_opaque.glsl:1-5`（stub）、`A:voxy.json` 0 字节 | **P 有 A 无** | 见 ③11；A 侧连入口都没接 |
| 区块加载动画 | `world0/gbuffers_terrain.vsh:55-67` | 无 | P 有 A 无 | P 未在 `world0/shadow.vsh:8-13` 同源 → 自身模型/阴影错位 |

---

## ⑤ 许可可行性与"重写 vs 抄"的边界

### 5.1 CC-BY-4.0 的三项义务
1. **署名（BY）**：本包无随包署名指引，可用的是包内自带署名——作者 `LoLip_p`（`P:shaders/settings.glsl:1`）、作品名与来源（`reference_shaderpacks/INDEX-batch2.md:25`）、链接 `patreon.com/lolip_p`（`P:PATREON.txt:1`，另有 YouTube/Discord `P:shaders/lang/en_US.lang:21`）。实务上写入 Astra 台账（制度已存在：`Astra/THIRD-PARTY.md:1-12`）并保留 `LoLip_p` 字样。
2. **标示修改**：只要不是逐字节拷贝，就必须注明"已作修改"。Astra 现有派生文件都带来源头（例 `A:lib/distort.glsl:4-6`、`A:global/lighting/shadowmap.glsl:4-12`），照此办理。
3. **不得附加更严限制**：不能把 CC-BY 部分声明为保留所有权利。与 Astra 自身 GPL 派生文件的组合 → 见 5.4。

### 5.2 三条边界
- **可逐字搬**：纯数学/算法表达的小函数（见 5.3），加署名与修改说明。
- **必须改写**：与 Astra 模块职责重叠、或需接 Astra 缓冲/选项体系者——AO（`P:world0/composite.fsh:213-239` 直乘 albedo 不能要）、SSR、PCF、光照贴图曲线、调色（理由见 ④：A 侧更省或记账更正确）。
- **绝对不要抄**：`world0/composite2.fsh:122-128` 的 Tonemap（`:125` 逗号运算符）；`world0/composite1.fsh:97-104` 的 `blur()`（`:133` 调用已注释）；`world0/dh_terrain.fsh:150` 的 `LightmapColor *= pow(LightmapColor, vec3(1.0/2.2))`（自幂，近乎笔误）。
- **注释型陷阱**：`world0/composite.fsh:33-41`、`world-1/composite1.fsh:7-12` 的 `colortexNFormat` 全是注释，格式并未生效。

### 5.3 最值得直接搬的函数（点名）
| 函数 / 代码块 | 位置 | 搬运后要做的改动 |
|---|---|---|
| `hash12` | `P:shaders/world0/composite.fsh:57-63` | 无（Astra 无 noisetex，正缺） |
| `spiralAO` + `doAO` | `P:shaders/world0/composite.fsh:213-221`、`:224-239` | 只取采样分布，评分按 A 侧记账重写 |
| `fogify` | `P:shaders/gbuffers_skybasic.fsh:22-24` | 无 |
| `DistortPosition` | `P:shaders/world0/distort.glsl:1-7` | **不可直接替换**：A 侧 `undistort`（`A:lib/distort.glsl:33-42`）有解析逆，P 的 `+0.1` 版本无逆 |
| `MotionBlur` | `P:shaders/world0/final.fsh:194-233` | 改名 + 接 Astra 曝光链；保留"物体运动不参与"的局限 |
| `dofOffsets[60]` + `DepthOfField` | `P:shaders/world0/composite2.fsh:19-80`、`:82-100` | 同上；`hand` 判据换 Astra 深度阈值 |
| 曝光 mip 采样式 | `P:shaders/world0/composite2.fsh:113-120` | 只学采样方式，勿搬 Tonemap |
| `effect()` 区块动画 | `P:shaders/world0/gbuffers_terrain.vsh:55-67` | 必须同时接 `A:program/shadow.vsh` |
| `starData` 灰阶判据 | `P:shaders/world0/gbuffers_skybasic.vsh:15` | 无 |
| DH 雾交接式 | `P:shaders/world0/dh_terrain.fsh:165-167` | 接 Voxy 的 near/far 语义 |

（另有 `Bayer2..256` 递归链 `P:shaders/lib/util/dither.glsl:5-12`、`Noise3D` 切片插值 `P:shaders/world0/dh_terrain.fsh:96-105`、天气条重着色 `P:shaders/world0/gbuffers_weather.fsh:17-19` 三处也可搬，但 Astra 已有等价物或需换采样源，见 ③12、③13b。）

**一句话边界**：本包算法表达简单，**逐字搬 + 署名 + 标修改在 CC-BY-4.0 下是干净做法**；真正要警惕的是**质量**——至少 3 处缺陷与 2 处注释格式（5.2）。

### 5.4 Astra 侧接收条件（工程约束，非法律意见）
- Astra 当前许可证是过渡性"个人使用"（`Astra/LICENSE:1-5` 原文 "PERSONAL USE ONLY"），按模块登记台账；任何代码级引入都必须先在 `Astra/THIRD-PARTY.md` 登记，并另行考虑发布门。
- Astra 现有派生文件语境是 GPL-3.0-or-later + 附加条款（`A:lib/distort.glsl:4-6`、`A:global/lighting/shadowmap.glsl:8-12`）。**CC-BY-4.0 与 GPLv3 的兼容性本报告不自行判定**，需统帅/法务确认（备注第 2 条）。

---

## ⑥ Top 5 与暂缓项

**Top 5（收益/工作量）**
1. **DH/Voxy 远景前向着色 + 除式雾交接**（③11）：Astra 唯一"缺就永远缺"的功能空白，入口是 stub（`A:voxy_opaque.glsl:1-5`），bvs 有完整可跑的对照；工作量中。
2. **区块加载动画**（③5）：20 份批次一报告零命中，成本 1 除 + 1 平方/顶点；前提是先在 `A:program/shadow.vsh` 同源求值。
3. **每像素相位螺旋 AO + 距离淡出**（③3）：无 TAA 下固定采样环必然条带，改动集中在 `A:program/ssao.fsh:62-104` 与 `A:lib/ao_resolve.glsl`。
4. **相机运动模糊 + 60 抽景深**（③9、③10）：Astra 完全缺失的两项后处理，几十行、不新增缓冲；须写明"物体运动不参与"。
5. **雨条重着色 + 星星灰阶判据**（③13）：各 1-3 行，提升"原版观感"档辨识度，可作独立选项。

**暂缓项**
- ③1 夜间补光链：本质是"在错误白平衡上打补丁"（`P:world0/composite.fsh:324-328`），会与 `A:lib/twilight.glsl` + ambient 分档打架，建议只在 NO_SHADOWS 档试验。
- ③2 PCF 与 ③7 偏差：A 侧已更省更准，只取"`1/resolution` 折进 mat2"这一条微优化。
- ③12 `Noise3D`：Astra 已无 noisetex，移植后只剩"量化到方块"一句值得借。
- P 的全部 tonemap/调色：3 处缺陷都在这一带（5.2），收益为负。
- P 的半透明阴影（`world0/composite.fsh:92-105`）：A 侧逐角处理且省一个数量级采样。
- `world1/world-1` 精简实现：Astra 的维度差异远超 BVS（末地黑洞/Kerr、下界体素彩光），价值低于 ③11。

---

## 附：自抽查记录（成稿后重新打开源文件核对）

核对方式：对每个被引用的 P/A 文件用 `awk 'NR==n||(NR>=a&&NR<=b)'` 打印指定行后逐字比对。共 10 组，含 **4 处已修正** 的错误。

1. 署名三行：`P:PATREON.txt:1`=`patreon.com/lolip_p`、`P:shaders/settings.glsl:1`=`#define BY 0 // By LoLip_p`、`P:shaders/lang/en_US.lang:21`=`option.BY.comment=§9Discord...` —— 一致（① 署名行据此成立）。
2. `P:shaders/world0/composite.fsh` 全部被引段 —— 逐段打印一致；`:130` 注释原文 "We can move our division by the shadow map resolution here for a small speedup" 核对为原文；`:127` 的 noisetex 版本确为注释（支撑"只能借 hash 路线"）。
3. `P:shaders/world0/final.fsh` 全部被引段 —— 一致；**修正**：正文原并列写 `world1/world-1` 为 `pow 0.8/0.45`，实际 0.45 只在 `world0/final.fsh:250`，两维度均为 0.8，已分别标注。
4. `world0/composite1.fsh`、`world0/composite2.fsh` 全部被引段 —— 一致；`:125` 原文确为 `color = color / vec3(TONEMAP_WHITE), vec3(1.0 / TONEMAP_WHITE);`（"死代码/缺陷"结论成立）。
5. `world0/distort.glsl`、`world0/shadow.vsh`、`world0/dh_terrain.fsh`、`dh_terrain.vsh`、`dh_water.fsh` 全部被引段 —— 一致；**修正 3 处**：噪声应用原引 `:136-139`（136 为空行、139 是 `lightBrightness *= 1.0f - rainStrength;`）已改 `:132-135`；入口原引 `:3-32` 跨过声明段已改 `:14-32`；`dh_water` 原引 `:111-167` 过宽已收窄。（③5 的阴影不同源结论成立。）
6. ③5/③6/③13 全部的 `gbuffers_*`、`clouds`、`skybasic`、`weather`、`entities` 引用（正文所列各段）—— 一致。
7. `block.properties:1`、`:6-7`、`:15`；`dimension.properties:1-5`；`shaders.properties:8-10`、`:13-19`、`:21`、`:23-24`；`lib/util/dither.glsl:5-12` —— 一致；**修正**：原写"screen 分组 6 页"，实际为 5 个活动子页 + 1 个注释页（`:15`）。`smoothTransition` 重复定义经 `grep -rc` 命中 8 文件，正文已按 8 处写明。
8. `world1/gbuffers_basic.fsh` —— **修正**：原写"全 12 行"，`wc -l` = 30，已改 30 行并补内容描述。
9. 「包内无 LICENSE」：`find -iname "*license*"` 无命中、`ls -la` 仅 19 字节 `PATREON.txt`、`unzip -l zips/bvs.zip | grep -ci license` = 0 —— 一致（①/⑤ 免责声明成立）。
10. A 侧 26 个被引位置逐点打印比对全部一致（覆盖 `lib/settings.glsl`、`lighting/shadowmap.glsl`、`program/ssao.fsh`、`lib/ao_resolve.glsl`、`post/exposure.glsl`、`lib/tonemap.glsl`、`post/fxaa.glsl`、`lib/encoding.glsl`、`lib/distort.glsl`、`lib/wind.glsl`、`lib/rain_particles.glsl`、`atmosphere/weather.glsl`、`atmosphere/sky_gradient.glsl`、`water/particles.glsl`、`lighting/blocklight.glsl`、`program/deferred.fsh`、`voxy_opaque.glsl`、`shaders.properties`、`LICENSE`、`THIRD-PARTY.md`）。注明 3 处：`A:lib/settings.glsl:319` 确为 `//#define` 注释态；`A:voxy.json` 0 字节；`A:LICENSE:1-5` 原文 "PERSONAL USE ONLY"。范围端点修正 2 处：`exposure.glsl:55-61`→`:55-58`、`tonemap.glsl:191-204`→`:191-203`。另核验 `A:lib/color_controls.glsl`、`A:global/atmosphere/stars.glsl`、`clouds_planar.glsl`、`clouds_screen.glsl`、`A:lib/bayer.glsl` 均存在。

**未核对项（明确声明）**
- 未逐行读 `A:global/water/*` 全部文件（只抽读 `surface.glsl:322-360` 与 `particles.glsl:24`），④ 表水体行未展开 Solas 水体的完整代价对比。
- 未读 `A:global/dimension/end*.glsl`/`nether*.glsl`（bvs 两维度只有 5 个精简 gbuffers，已列 ⑥ 暂缓）。
- 未做任何实机运行：④ 表"哪边更省"基于采样数与纹理读取次数的静态计数，非 GPU 计时。
