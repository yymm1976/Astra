# Reverie 调研报告（面向 Astra）

> 引用约定：`P:` = `reference_shaderpacks/reverie_shader/` 下的相对路径；`A:` = `Astra/shaders/` 下的相对路径。
> 所有行号在成稿时重新打开源文件核对（见附录自抽查记录），未确认的行号不写。

## ① 包概览

- **名称/版本**：包内可确认的名称为 "Reverie Shader"（`P:shaders/lang/en_US.lang:4`，`option.INFO=Reverie Shader by`）。**包内未找到任何版本号字符串**（对 .lang/.properties/.glsl/.json 全文搜 "0.9"/"beta"/"version" 无命中；`P:shaders/program/voxy.json:2` 的 `"version": 1` 是 Voxy 数据格式版本，与包版本无关）。任务书标注的 "v0.9 Beta" 在包内无实文印证，仅作参考记录。
- **作者**：TheCMK（`P:LICENSE:1`，"Copyright (C) 2026 TheCMK"）。
- **许可证**：**保留所有权利**（`P:LICENSE:3` "All rights reserved unless otherwise explicitly stated."），附标准 AS-IS 免责声明（`P:LICENSE:5-11`）。包内唯一明确再授权的第三方代码是 AMD CAS 锐化（MIT 风格许可，`P:generic/post/cas.fsh:1-9`）。详见 ⑤。
- **风格定位**：物理大气驱动的"雾感暖调"写实包。三个可实证的风格抓手：① Mie 散射系数直接由雾量自定义 uniform 调制（`P:lib/atmosphere.glsl:2`，`BETA_M = 3.996e-6 * fogAmount`），雾即大气本身而非叠加层；② 晨昏密度因子让雾在清晨加重（`P:generic/shadow/vl.glsl:202-204`）；③ 暖阳/暖月光调色板（`P:lib/settings.glsl:90-96`，默认日色 R0.95/G0.85/B0.75）+ Purkinje 暗视效应（`P:lib/settings.glsl:39`）。
- **技术形态**：**延迟渲染**（G-buffer 打包在 colortex1/2，`P:generic/lighting/gbuffers.fsh:55-57`；光照合成在 deferred 链，`P:program/deferred2.fsh:30-77`），Iris 专用：必需特性 SSBO + CUSTOM_IMAGES + SEPARATE_HARDWARE_SAMPLERS + HIGHER_SHADOWCOLOR（`P:shaders/shaders.properties:10`），可选 REVERSED_CULLING / BLOCK_EMISSION_ATTRIBUTE / FADE_VARIABLE（`P:shaders/shaders.properties:9`）。三维度共享一份 `program/` 源码，由 `world0`/`world-1`/`world1` 目录下 3 行包装文件注入维度宏（见 ②-5）。

## ② 架构与特性清单

### ②-1 大气与云（本包最强子系统）

| 特性 | 出处 |
|---|---|
| Hillaire 式物理大气全套系数：地球/大气半径、Rayleigh/Mie 标高、臭氧层密度函数 | `P:lib/atmosphere.glsl:10-14`、`P:lib/atmosphere.glsl:58-61` |
| 散射系数运行时可调：BETA_R 乘 `betaRfact`、BETA_M 乘 `fogAmount`（雾=大气） | `P:lib/atmosphere.glsl:1-7`；uniform 定义 `P:shaders/shaders.properties:133,136` |
| Cornette-Shanks / Draine / hg_draine 混合相函数（d=10 常数拟合一组 gDraine/gHG/w） | `P:lib/atmosphere.glsl:22-52` |
| 透射率 LUT（256×64，12 步积分）compute 生成 | `P:program/prepare_a.csh:7-23`；LUT 声明 `P:shaders/shaders.properties:144` |
| 多次散射近似 LUT（32×32）：64 向 fibonacci 球采样 + workgroup shared 树归约，`L2/(1-fms)` 闭式解 | `P:program/prepare_b.csh:30-96`（公式在 :93） |
| 天空视图 LUT（128×64，随相机高度重定位，RGBM 编码） | `P:program/prepare_c.csh:7-29` |
| 16×16 环境辐照度探针：compute 内 256 方向卷积，一 workgroup 算完（含作者自嘲系数 ×4） | `P:program/prepare_d.csh:30-69` |
| 单次采样解析 aerial perspective：与 LUT 大气共用同一组 BETA 系数与多次散射 LUT | `P:generic/shadow/vl.glsl:181-246`（采样 LUT 在 :224-226） |
| RT 体素云 + RT aerial perspective：`workGroupsRender` 半分辨率 compute 一次完成 | `P:program/composite4.csh:10-14,16-97` |
| 云：4 阶多重散射近似（a/b/c 三常数衰减）、体积云+平面云双层合成 | `P:generic/clouds.glsl:6-10,21-34,204-236` |
| 云内闪电照亮（`lightningBoltPosition` 距离场） | `P:generic/clouds.glsl:121-124` |
| 3D worley 纹理（TEXTURE_3D customTexture）驱动的地面烟雾雾 | `P:program/composite4.csh:50`；纹理声明 `P:shaders/shaders.properties:86` |
| 天空：LUT 采样 + 假地平线（FakeSkyGround）+ 太阳/月亮圆盘（月亮用云噪声当月面纹理） | `P:generic/sky.glsl:76-95,69-74` |
| 星空（hash 网格）/银河纹理/极光（降雨门控 + 噪声位移） | `P:generic/sky.glsl:1-22,59-67,24-57` |

### ②-2 水体

| 特性 | 出处 |
|---|---|
| 32 oct 方向性正弦波场 + 域扭曲 + 解析导数法线（风向 uniform 驱动流向） | `P:generic/water.glsl:13-53` |
| 垂直水流法线修正 + 沿流向加速流动 | `P:generic/water.glsl:55-67` |
| 焦散：水噪声投影到阴影平面，`exp(-|h|*3)` | `P:generic/water.glsl:84-91` |
| 水面视差（4 步） | `P:generic/water.glsl:93-107` |
| 水下体积光：RT 档逐样本阴影 + 非 RT 档单样本，含各向同性多次散射闭式近似 `fms/(1-fms)` | `P:generic/shadow/vl.glsl:104-179`（近似在 :128-129） |
| SSR：线性步进 + 二分细化；DH 下翻转图回退；球面 capture 回退 | `P:generic/reflections.glsl:30-58,60-85,87-106` |
| 粗糙反射：VNDF GGX 采样（arXiv 2306.05044 实现）多重反弹 | `P:generic/reflections.glsl:1-28`、`P:program/composite2.fsh:104-127` |
| 金属 F0/F82 查表（8 组实测 n,k 值）+ Cook-Torrance 高光 | `P:lib/materials.glsl:49-79`、`P:program/composite2.fsh:139-155` |

### ②-3 阴影与光照

| 特性 | 出处 |
|---|---|
| PCSS blocker search（Vogel 盘 8 采样）+ PCF（12 采样）+ 每像素旋转 | `P:generic/shadow/main.glsl:61-80,42-59` |
| 透明阴影：shadowcolor0 彩色 × shadowtex1 透射，shadowcolor2 单通道水掩码 | `P:generic/shadow/main.glsl:25-40`（HIGHER_SHADOWCOLOR 消费端） |
| 水下地面焦散：阴影采样时按水掩码混入焦散 | `P:generic/shadow/main.glsl:196-199` |
| 硬件阴影比较采样器 `sampler2DShadow shadowtex0HW/1HW`（Iris SEPARATE_HARDWARE_SAMPLERS） | `P:lib/all_the_uniforms.glsl:124-125,204`；用于 :26,:31 |
| 云影：把采样点沿光方向投到云层平面采云噪声，晨间淡出 | `P:generic/shadow/main.glsl:1-23`（淡出在 :20） |
| 屏幕空间阴影接力（阴影距离外 12 步指数步长）作为可选 fallback | `P:generic/shadow/main.glsl:109-127`；开关 `P:lib/settings.glsl:76` |
| RSM 单次反弹 GI：Vogel 盘采样 shadowcolor0/1 + 深度，法线双侧余弦通量 | `P:generic/shadow/rsm.glsl:1-54`（法线单侧偏置在 :22） |
| GI/AO 联合去噪（深度+法线加权 7-tap） | `P:generic/shadow/rsm.glsl:56-86` |
| GTAO（4 切片，Kvaleya 实现）输出 AO + 弯折法线供环境光使用 | `P:generic/gtao.glsl:27-76`；存储 `P:program/deferred.fsh:33-36` |
| 洪泛体素彩光：deferred 直接采 3D 图 + sqrt 解压，帧奇偶双缓冲 | `P:generic/lighting/lighting.fsh:3-8,20-35` |
| SSS：双档强度 + 孔隙度雨天湿润压暗 albedo | `P:generic/lighting/lighting.fsh:92-100` |
| 相位 SSS（Cornette-Shanks g=0.6） | `P:generic/lighting/lighting.fsh:123-129` |

### ②-4 后处理

| 特性 | 出处 |
|---|---|
| 直方图自动曝光（SSBO atomicAdd 两级归约 + frameTime 适应），bruop 博客实现 | `P:program/composite21_a.csh:33-56`、`P:program/composite21_b.csh:18-53` |
| compute SMAA：边缘检测（redmean 色距 + 自适应阈值）→ 搜索/权重 → 混合，全在自定义图像上 | `P:program/composite50_a.csh:12-57`、`P:program/composite50_b.csh:12-138` |
| TAA：最近深度重投影 + AABB 裁剪 + offcenter 拒绝；另有 SMAA-T2x 时域分量 | `P:generic/post/taa.glsl:41-73,76-95` |
| 云/VL 时域上采样：子分辨率 buffer 重投影 + "上次更新位置"回退 + offcenter 拒绝 | `P:generic/post/taa.glsl:115-155`（云）、`:157-199`（VL） |
| 泛光：6x6/3x3 降采样核 + 附加混合 composite13-16 | `P:generic/post/bloom.glsl:3-35`；混合声明 `P:shaders/shaders.properties:241-244` |
| 5 种色调映射算子可选（Reinhard-Jodie/ACES/Uncharted2/AgX/直通） | `P:lib/tonemap.glsl:21-38` |
| Purkinje 暗视（XYZ 空间）+ 胶片颗粒（60fps 归一） | `P:lib/tonemap.glsl:58-74` |
| AMD CAS 锐化（MIT） | `P:generic/post/cas.fsh:11-45` |
| 体积数据半分辨率渲染：云 0.25×、VL 0.25×（VOLUMETRICS_RES 可选 0.125-1.0） | `P:lib/settings.glsl:163`、`P:program/composite4.csh:11` |

### ②-5 维度特化与工程结构

| 特性 | 出处 |
|---|---|
| 三维度共享源码：`world0/world-1/world1` 每个文件仅 3 行（#version + 维度宏 + include 同名 program 文件） | `P:world0/deferred2.fsh:1-3`、`P:world-1/deferred2.fsh:1-3`、`P:world1/deferred2.fsh:1-3` |
| compute 维度熔断：非主世界直接 `workGroups = ivec3(0,0,0)` | `P:program/prepare_d.csh:3-7`；另 `P:program/composite4.csh:10-14` |
| 下界：RT 体积雾（0 散射 1 吸收）+ 伪环境光（下方熔岩色/上方雾色）+ 雾色归一化天空 | `P:generic/shadow/vl.glsl:1-74`、`P:generic/lighting/lighting.fsh:67-73`、`P:generic/sky.glsl:97-101` |
| 末地：sunPathRotation=-135、纯白天灯、白星、黑天空 | `P:lib/settings.glsl:157-161`、`P:generic/sky.glsl:15-17,108-110` |
| 阴影 pass 顶点着色器直接 imageStore 体素化发光方块（硬编码 HSV 色表 + at_midBlock.w 亮度） | `P:program/shadow.vsh:29-48`；色表 `P:lib/voxelisation.glsl:14-46`；方块表 `P:block.properties:25-45`（block.10021-10027） |
| Jacobi 洪泛传播：每帧 1 步 6 邻域平均（/6.1 衰减），3D 图乒乓 | `P:program/begin.csh:16-44` |
| 程序级 pass 熔断（BLOOM/DOF/去噪/像素化等 12 个 compute/composite 门控） | `P:shaders/shaders.properties:148-197` |
| Voxy 支持：`map_voxy_param_to_varying` 桥接 + colortex16-18 + vxXxx uniforms | `P:generic/lighting/gbuffers.fsh:35-51`、`P:lib/all_the_uniforms.glsl:62-65,114-122,161-181` |

### ②-6 性能与时域

| 特性 | 出处 |
|---|---|
| 每帧常量走 SSBO（SunColor/AmbientColor/AvgLum/SunVisibility 等 10 项），全管线零 uniform 重复 | `P:lib/all_the_uniforms.glsl:127-138` |
| 帧奇偶双缓冲约定（体素洪泛、云/VL 棋盘格更新共用 frameCounter 奇偶） | `P:program/begin.csh:21`、`P:program/composite4.csh:104` |
| 棋盘格增量更新：每帧只更新 1/VOLUMETRICS_RES² 的云/VL 像素 | `P:program/composite4.csh:104`（`ivec2(frameCounter * VOLUMETRICS_RES, frameCounter) % VOLUMETRICS_RES_INV`） |
| 质量档位 TOASTER→ULTRA（5 档全参数联动） | `P:shaders/shaders.properties:37-41` |
| VL/云 adaptive_samples（视角贴地时减采样） | `P:generic/clouds.glsl:87`、`P:generic/shadow/vl.glsl:31` |
| 弯折法线时域去噪（单独通道，深度量化 16bit 校验） | `P:generic/post/taa.glsl:97-113` |

### ②-7 材质与表面

| 特性 | 出处 |
|---|---|
| G-buffer 极限打包：两个 RGBA16 内塞 albedo/ID/光滑度/F0/法线/光照/SSS/自发光/平法线（octahedral 编码） | `P:lib/materials.glsl:140-191`；缓冲格式 `P:lib/all_the_uniforms.glsl:220-238` |
| 材质 ID 走 block.properties 10004-10020（水面/SSS 双档/植物/树叶/洪泛透过） | `P:lib/materials.glsl:1-8`、`P:block.properties:2-23` |
| F0 字节段 230-237 保留为硬编码金属索引，255=彩色金属 | `P:lib/materials.glsl:81-101` |
| 季节 HSV 色调：worldDay%120 四季插值 + 温带生物群系红通道门控 | `P:generic/weather.glsl:1-31`；季节 uniform 链 `P:shaders/shaders.properties:124-127` |
| 植物摆动：windDirection 矢量驱动 3D 正弦场，雷暴增幅 | `P:generic/weather.glsl:33-64` |
| POM（80 步上限 + 12 格距离淡出） | `P:generic/lighting/gbuffers.fsh:59-92` |
| FADE_VARIABLE（mc_chunkFade）驱动的区块淡入，反射/高光/雾全链路乘 | `P:generic/lighting/gbuffers.vsh:60-61`、`P:program/composite2.fsh:127` |

## ③ Astra 可借鉴点

> 每条四要素：技术要点 / 本包出处 / Astra 对应模块 / 迁移难点与工作量。与批次一报告重复的主题在条末标注。

1. **LUT 物理大气三件套（透射率/多次散射/天空视图）** — 用 3 个 compute 在帧首生成 256×64 透射率、32×32 多次散射（`L2/(1-fms)` 闭式解）、128×64 天空视图 LUT，运行期天空/直射色/环境色全部查表，物理一致性由构造保证。
   - `P:program/prepare_a.csh:7-23`；`P:program/prepare_b.csh:42-96`；`P:program/prepare_c.csh:7-29`；`P:lib/atmosphere.glsl:79-100,120-191`
   - `A:global/atmosphere/sky_gradient.glsl:5-8`（现役 Complementary 三方向解析模型）；`A:lib/sky_sh9.glsl:47-50`
   - 难点：需要换掉整个天空管线而非叠加；Astra 是前向架构，天空在 gbuffers_sky 直接画，LUT 可以无缝喂给现有调用点；真正成本在 ozone/相函数/多散射参数整定与昼夜验证。**工作量：高**

2. **解析 aerial perspective 与天空同源** — 把雾做成"大气本身"：沿射线单次采样 `all_densities * StepSize * 强度` 得光学深度，直接复用 LUT 的 BETA 系数与多次散射纹理，高度雾、晨雾因子（worldTime 20000-24000 与 0-2000 两段平滑）、云覆盖乘子全部挂在同一公式上。雾与天空在色度上不可能打架。
   - `P:generic/shadow/vl.glsl:181-246`（强度 :199、晨雾 :202-204、多散射采样 :224-226）；RT 版 `P:program/composite4.csh:16-97`
   - `A:global/atmosphere/fog.glsl:67-79`（山谷雾）、`A:global/atmosphere/fog.glsl:110-176`（合成链）、`A:global/atmosphere/volume_fog.glsl:112-155`（RT 雾）
   - 难点：Astra 已有完整的山谷雾/洞穴雾/RT 雾三层体系，此条是"同源化改造"而非新增；可与条 1 绑定做，也可只用它的晨雾因子与"雾量=BETA_M"思路做轻量对齐。**工作量：高**（轻量版：中）

3. **`workGroupsRender` 半分辨率 compute 体积管线** — 云与 VL 不走 composite 光栅 pass，而是渲染型 compute（`const vec2 workGroupsRender = vec2(VOLUMETRICS_RES, VOLUMETRICS_RES)`）直接 imageStore 到自定义图像，天然支持任意降分辨率与 4×4 深度 culling（`max_depth_4x4`）。
   - `P:program/composite4.csh:10-14,99-152`（4×4 深度剔除 :107-108）
   - `A:global/atmosphere/clouds_planar.glsl:217-231`（现役全分辨率 64 采样平面云）；`A:shaders.properties:692-695`（Astra 已启用可选 CUSTOM_IMAGES+COMPUTE_SHADERS）
   - 难点：Astra 已有 compute 经验（下界 9 步链），但 `workGroupsRender` 语义、图像读写与现有 composite 链的衔接需要重新铺；云的屏幕空间合成点（`A:global/atmosphere/clouds_screen.glsl`）要改为采样图像。**工作量：中**

4. **棋盘格增量更新 + 时域上采样** — 半分辨率数据每帧只更新 1/16 像素（按 frameCounter 轮转），其余像素靠重投影历史；屏幕 pass 用"上次更新位置 + 深度校验 + offcenter 拒绝"三重判据混合当前低分辨率采样与历史。VL 上采样还有 3×3 邻域深度加权去像素化。
   - `P:program/composite4.csh:104`；`P:generic/post/taa.glsl:115-155`（LastUpdatePos :124、回退 :130-135）、`:157-199`（VL 版）
   - `A:global/atmosphere/cloud_temporal.glsl:27-57`（现役 colortex24/25 独立云历史，全分辨率）
   - 难点：Astra 云历史框架已经很完整，此条的价值在"增量更新"让更贵的云（体积云）也能上 0.25 分辨率；若不做条 3 则无意义，两者绑定。**工作量：中**

5. **SSBO 每帧常量缓冲** — 把太阳色/环境色/平均亮度/太阳可见度等 10 项全管线共用常量放进 std430 SSBO，compute 写、所有 pass 读，替代"每个 pass 重算或 uniform 透传"。
   - `P:lib/all_the_uniforms.glsl:127-142`；写入端 `P:program/composite21_b.csh:49-52`；`P:program/prepare.fsh` 同族直射色（`P:program/composite4.fsh:3` flat varying 注释可佐证其旧痛点）
   - `A:shaders.properties:455-460`（Astra 现役方案：CPU 预计算 custom uniform）
   - 难点：SSBO 是 Iris 必需特性档（Astra 现只声明 optional 两项）；收益主要在 compute 间共享与消除 flat varying 样板，量级不大但工程干净。**工作量：中**（与批次一 "CPU 预计算 custom uniform" 主题相关，但本条是 SSBO 替代方案，不重复）

6. **硬件阴影比较采样器** — `sampler2DShadow shadowtex0HW/1HW` + `shadowHardwareFiltering` 常量，PCF 主路径硬件双线性比较，省软件比较分支。
   - `P:lib/all_the_uniforms.glsl:124-125,204`；消费 `P:generic/shadow/main.glsl:26,31`
   - `A:global/post/godrays.glsl:30-32`（Astra 因"depthtex0 是普通 sampler"手写 GL_LEQUAL 比较——注释原文）；`A:global/lighting/shadowmap.glsl:176-194`
   - 难点：Iris 对 shadowtex 硬件采样有独立特性位（SEPARATE_HARDWARE_SAMPLERS），需要在 `A:shaders.properties` 声明并验证 Iris 版本兼容；godrays 的手写比较可直接替换。**工作量：低**

7. **阴影 pass 顶点体素化 + 洪泛彩光（主世界通用化）** — 发光方块在阴影 pass 顶点着色器写 3D 图（色相表 × at_midBlock.w 亮度），begin.csh 每帧跑 1 步 Jacobi 6 邻域传播，光照端直接采 3D 图（sqrt 解压）混合火把色。
   - `P:program/shadow.vsh:29-48`；`P:program/begin.csh:16-44`；色表 `P:lib/voxelisation.glsl:14-46`；消费 `P:generic/lighting/lighting.fsh:20-35`
   - `A:lib/nether_voxel_grid.glsl:29-48`、`A:shaders.properties:659-685`（Astra 下界已有 9 步 compute 链 + 64³ 双缓冲图——骨架同源，差距是 Astra 未覆盖主世界、且每帧 9 步而非 1 步累积）
   - 难点：把下界子系统参数化到主世界（染色光源色表要扩到主世界方块集、shadow pass imageStore 与现有 shadow.fsh 输出共存）；收益是主世界洞穴彩光，属于内容型卖点。**工作量：高**（与批次一 "下界体素光时域乒乓" 主题相邻：那条是下界域，本条是主世界推广，判定为部分重复）

8. **compute SMAA 作为 AA 第三档** — 边缘检测（redmean 色距 + 距屏幕中心自适应阈值）、SMAA 搜索/面积查表、混合权重，3 个 compute pass 在自定义图像上完成；T2x 时域累积可叠加。
   - `P:program/composite50_a.csh:12-57`；`P:program/composite50_b.csh:12-138`；门控 `P:shaders/shaders.properties:166-174`
   - `A:global/post/fxaa.glsl`（现役 FXAA 档）、`A:program/taa_resolve.fsh:1`（现役 TAA 档）
   - 难点：需要 2 张自定义图像 + 2 张查表纹理（smaaArea/smaaSearch），三 pass 编排；对"三选一 AA"的产品定位是加档而非替换。**工作量：中-高**

9. **GTAO 切片积分 + 弯折法线** — 4 切片 GTAO（交错角度表 + 蓝噪声抖动）同时输出 AO 与弯折法线，弯折法线喂给环境光查表，AO 只用于环境不用于直射。
   - `P:generic/gtao.glsl:27-76`；环境光消费 `P:generic/lighting/lighting.fsh:50-57`；存储 `P:program/deferred.fsh:33-36`
   - `A:lib/ao_resolve.glsl:19-47`（Astra 已有半分辨率弯折法线重建）、`A:lib/ao_resolve.glsl:52-64`（bent normal 重评 SH）、`A:lib/ao_material.glsl:3`
   - 难点：Astra 的弯折法线消费端（SH 重评）是现成的，只差 GTAO 生成端；但 Astra 是前向架构，GTAO 需要深度+法线 buffer（Astra 有 surface_buffers 体系，可行性需核实）。**工作量：中**

10. **统一风向场** — 一个 vec2 `windDirection` 自定义 uniform（重载随机 + 归一化），同时驱动水波流向、植物摆动方向、云位移；水波沿法线水平分量加速（`Coords.xz -= frameTimeCounter * normalize(WorldNormal.xz) * 8`）模拟下游变快。
    - `P:shaders/shaders.properties:138-139`；`P:generic/water.glsl:16,55-67`；`P:generic/weather.glsl:39-42`
    - `A:global/lighting/wind.glsl:135-147`（astra_wind_wave 现无水平漂移方向参数）、`A:shaders.properties:455-460`（CPU uniform 区）
    - 难点：低。加一个 CPU uniform + 两处消费端改参数。**工作量：低**（与批次一 "CPU 预计算 custom uniform" 主题部分重复——新增点在"一个风向统一三个子系统"）

11. **季节色调系统** — `worldDay%120` 划四季（每 30 天），HSL 三通道逐季参数在 HSV 空间插值染色，温带生物群系门控（红通道阈值判定），仅作用于 glcolor≠1 的植被染色。
    - `P:generic/weather.glsl:1-31`（四季插值 :14-19、生物群系门控 :21-24）；参数 `P:lib/settings.glsl:192-205`
    - `A:global/atmosphere/weather.glsl:1-10`（include 守卫 + `astra_rain_exposure` 降雨包络；Astra 现役 weather 文件与全库 grep 均无 season/worldDay 季节概念，`worldDay` 仅 `A:global/dimension/end_geometry.glsl:19` 用于末地轨道周期——对照位仅为放置点）
    - 难点：实现本身简单；风险是纯客户端 worldDay 与服务器时间/存档语义、以及与 Astra 生物群系色彩的叠加顺序。**工作量：中**

12. **水面阴影调制焦散** — 阴影 pass 把水掩码写进 shadowcolor2（R8），地形阴影采样时检测"透过水面被影"再乘解析焦散，等于给所有被水面遮蔽的地形免费加上焦散光斑，不需要 RT 焦散。
    - `P:generic/shadow/main.glsl:25-40`（水掩码 :36）、`:196-199`（焦散混入）；输出 `P:program/shadow.fsh:14-17`（RENDERTARGETS 0,2,1）
    - `A:global/water/caustics.glsl:5-13`（Astra 现役焦散基于 solas 水面高度场）、`A:global/water/caustics.glsl:17-35`
    - 难点：Astra 阴影 color 附件需要加一张 R8（或复用现有附件通道）；焦散函数 Astra 已有，直接复用。**工作量：低-中**

13. **重载随机化世界观参数** — shader 重载时随机出：Rayleigh 系数缩放、雾量、各向异性、云覆盖率偏移、云起始偏移、风向，用 `smooth(random(), …)` 长期平滑，同一存档每次重载得到不同的"今天"。
    - `P:shaders/shaders.properties:114-136`（randomFloat/randomA/randomB 链 :116-121、云 :129-131、雾 :133、betaR :136、风向 :138-139）
    - `A:shaders.properties:455-460`（CPU uniform 放置点）
    - 难点：低（纯 properties 层）；注意 SCREENSHOT_MODE 关闭随机（`P:shaders/shaders.properties:115-119` 的做法值得照抄）。**工作量：低**

14. **球面反射 capture 缓存** — 把屏幕空间色彩按方向球面坐标存进一张 2D 图（colortex11，alpha 存距离），SSR miss 先查 capture（8 步行进 + 距离带校验），缓存随相机移动按"上一帧方向差"重投影续期。
    - `P:program/composite.fsh:11-47`（球面映射 :14、屏幕回填 :19-30、重投影 :33-44）；消费 `P:generic/reflections.glsl:87-106`
    - `A:lib/sky_reflection_cache.glsl:9-20`（Astra 已有天空方向缓存，但只存天空色，不存屏幕地形）
    - 难点：增量是把"天空缓存"升级为"天空+地形 capture"；距离校验与重投影是主要工程量。**工作量：中**（与批次一 "SSR miss 回退" 和 "天空缓存含云行" 主题重复）

## ④ Astra 已有对应实现对照

| 主题 | Reverie 做法 | Astra 现状 | 差异评判 |
|---|---|---|---|
| 天空 | LUT 物理散射（`P:program/prepare_c.csh:7-29`），运行期查表 | 三方向解析渐变（`A:global/atmosphere/sky_gradient.glsl:5-8`，Complementary 系） | Astra 侧更省（无 LUT/无 compute），Reverie 侧更物理（瑞利/臭氧/多散射）；误差来源：解析模型的日出日落色带靠手调，物理模型靠参数，两者在同屏混合雾时后者自洽 |
| 环境光 | 16×16 辐照度探针 LUT + 天空视图均值（`P:program/prepare_d.csh:30-69`、`P:lib/atmosphere.glsl:228-240`） | SH9 方向性天光（`A:lib/sky_sh9.glsl:47-50`） | SH9 更省（9 系数 vs 探针 LUT+两次查表）；Reverie 探针含真实大气朝向分布，SH9 靠投影源保真；误差来源同上 |
| 雾 | 大气同源 aerial perspective + 晨雾因子（`P:generic/shadow/vl.glsl:199-204`） | 三层雾体系：山谷雾/洞穴雾/RT 雾（`A:global/atmosphere/fog.glsl:67-79`、`A:global/atmosphere/volume_fog.glsl:112-155`） | Astra 侧的功能覆盖更宽（洞穴雾 Reverie 无），Reverie 侧的"雾=大气"一致性与晨雾时段是 Astra 没有的表达；Astra 现役方案 GPU 成本更低 |
| 云 | 0.25 分辨率 compute 体积云 + 棋盘格时域（`P:program/composite4.csh:11,104`） | 全分辨率平面云 64 采样 + 独立时域历史（`A:global/atmosphere/clouds_planar.glsl:217-231`、`A:global/atmosphere/cloud_temporal.glsl:27-57`） | GPU 成本 Reverie 侧显著更省（分辨率差 16 倍 + 增量更新），但依赖 compute/自定义图像栈与上采样质量；Astra 侧更省开发成本、几何感更强的平面云保留 |
| 阴影 | PCSS + Vogel PCF + 硬件比较采样器（`P:generic/shadow/main.glsl:42-80`、`P:lib/all_the_uniforms.glsl:124-125`） | 软件比较 + 手写 LEQUAL（`A:global/lighting/shadowmap.glsl:176-194`、`A:global/post/godrays.glsl:30-32`） | 双方算法同代；Reverie 侧在硬件比较上更省（ALU→纹理单元），Astra 侧 godrays 的手写比较是明确可替换点 |
| AA | SMAA(compute)/TAA/TA 三档（`P:program/composite50_a.csh:6-10`、`P:shaders/shaders.properties:166-174`） | 关/FXAA/TAA 三档（`A:global/post/fxaa.glsl`、`A:program/taa_resolve.fsh:1`） | TAA 侧 Astra 更精（验证式历史/反应性掩码/去抖动输出，`A:program/taa_resolve.fsh:30-113`）；SMAA 档 Astra 缺失，静态画面锐度是 Reverie 卖点 |
| 自动曝光 | 256-bin 直方图 + SSBO atomicAdd（`P:program/composite21_a.csh:33-56`） | 采样点几何均值对数平均（`A:global/post/exposure.glsl:78-100`） | Astra 侧更省（无 SSBO/无 barrier）；直方图对高动态范围两端更稳，但 256-bin 对 MC 场景收益有限；误差来源：几何均值对极亮小目标（太阳）不敏感 |
| 方块光 | 洪泛体素彩光（`P:program/begin.csh:16-44`） | 光照图曲线 + 手持光（`A:global/lighting/blocklight.glsl:59-76`） | Astra 侧几乎零成本；彩光是不同产品维度不是替代关系；Reverie 洪泛每帧只走 1 步 Jacobi，故有 6-10 帧的传播延迟，光斑拖尾是已知代价 |
| 下界体积光 | shadow 顶点体素化 + 主世界/下界共用（`P:program/shadow.vsh:29-48`） | 专用 9 步 compute 链 64³（`A:shaders.properties:659-685`） | Astra 侧单帧收敛质量更高（9 步/帧），Reverie 侧复用阴影 pass 采集更省 CPU 派发；Astra 每帧 9 步属于过度收敛，可借其"每帧 1 步 + 历史累积"降载 |
| 水面波形 | 32 oct 正弦叠加 + 导数法线（`P:generic/water.glsl:13-53`） | Steadfast/Solas 噪声波场（`A:global/water/surface.glsl:65-130`、`A:lib/solas_water.glsl`） | Astra 侧观感更细腻（噪声场），Reverie 侧解析正弦更省纹理采样但远处频闪风险高；Astra 现役方案不弱，无迁移必要 |
| 色调映射 | 5 算子可选含 AgX（`P:lib/tonemap.glsl:26-38`） | AgX + ACES + Uchimura（`A:lib/tonemap.glsl:83-111`） | 双方同代，Astra 侧 AgX 有 CDL 调色扩展更完整；Reverie 的 Purkinje 在 composite 中段（`P:program/composite4.fsh:139`）而非最终 pass，Astra 侧放置点不同 |
| 湿润表面 | 孔隙度压暗 albedo（`P:generic/lighting/lighting.fsh:98-99`） | 湿度分类三档响应（`A:lib/wet_material.glsl:7-19`） | Astra 侧表达更细（分材质档位 + 光泽增益），Reverie 侧胜在与 SSS 槽位复用；Astra 现役方案保留 |

## ⑤ 借鉴可行性（许可证层面）

包内许可证实文（`P:LICENSE`，共 11 行）：

- 第 1 行：`Copyright (C) 2026 TheCMK`
- 第 3 行：`All rights reserved unless otherwise explicitly stated.`
- 第 5-11 行：标准 MIT 式免责声明段落（AS IS / 不担保适销性 / 责任上限），**但缺少 MIT 授权句**——即没有"特此免费授予任何人都可复制、修改、再分发"的许可条款。

两种情形的风险判定：

1. **读思路后独立重写**：可做。著作权保护表达（代码文本），不保护技术思路与算法本身。Hillaire 大气 LUT、PCSS、GTAO、SMAA、直方图曝光这些思路各有公开出处（Reverie 自己也在注释里引用：`P:generic/gtao.glsl:1` 注明 Kvaleya pastebin、`P:generic/reflections.glsl:1-2` 注明 arXiv 论文、`P:program/composite21_a.csh:1` 注明 bruop 博客、`P:generic/post/bloom.glsl:2` 注明 COD AW 演讲）。独立重写 + 在 Astra 文件头注明"思路参考自 Reverie（all-rights-reserved）+ 公开算法出处"，并在 THIRD-PARTY 台账登记，与批次一确立的口径一致。**注意**：Astra 现有 provenance 头有"ported from（移植自）"的写法（如 `A:global/atmosphere/sky_gradient.glsl:5`），这种写法隐含代码谱系，对 Reverie 源**不可使用**——只能写"思路参考"，不能出现 port/改写自的表述。
2. **直接抄代码**：禁止。Reverie 不是开源许可（无授权句的 all-rights-reserved 等于默认著作权全保留），任何逐行/近逐行复用、变量名与结构体的成段沿用（如 `P:lib/materials.glsl:140-191` 的 G-buffer 打包布局、`P:program/composite4.csh:104` 的棋盘格坐标公式这类"实现指纹"）都构成侵权风险。唯一例外是包内已带宽松许可的第三方件（`P:generic/post/cas.fsh:1-9` AMD CAS，其许可文本允许复制与再分发）——但该件源头是 AMD 官方仓库，应从 AMD 原仓获取并遵循其许可，而非从 Reverie 包内提取。

另注：HIGHER_SHADOWCOLOR（`P:shaders/shaders.properties:10`）与 FADE_VARIABLE（`P:generic/lighting/gbuffers.vsh:60-61`）是 Iris 特性而非 Reverie 专利，使用无许可问题。

## ⑥ Top5 优先建议（按 收益/工作量）+ 暂缓项

1. **硬件阴影比较采样器**（条 6）— 收益：ALU 软比较全量替换 + 顺带解决 godrays 手写 LEQUAL 的已知别扭；工作量：低（properties 声明 + 消费端改签名）。收益/工作量最高的一档。
2. **重载随机化世界观参数**（条 13）— 收益：整包"每次重载像换了张地图"的内容差异化，纯 properties 层零着色器风险；工作量：低。
3. **棋盘格增量更新 + 时域上采样接到现役云历史**（条 4）— 收益：给 Astra 云/雾体系拿到"贵效果降 16 倍成本"的通用件，与现有 colortex24/25 历史框架直接对接；工作量：中。前置依赖条 3 的 compute 化。
4. **compute 化体积管线（workGroupsRender 云 + 雾）**（条 3）— 收益：体积云在 Astra 从"不可负担"变"可负担"，同时是条 4 的载体；工作量：中（Astra 已有 compute 与自定义图像经验，`A:shaders.properties:692-695`）。
5. **LUT 物理大气 + 同源雾**（条 1+2 合并推进）— 收益：天空/雾/直射色/环境色的物理一致性，"雾感暖调"风格的大梁，是本报告中最难被竞品抄走的护城河；工作量：高，建议按"先透射率 LUT 替换直射色，再多次散射，再雾同源"三步走。

**暂缓项及理由**：

- **主世界洪泛彩光**（条 7）：与下界体素光子系统功能重叠、成本最高（shadow pass 体素化 + 洪泛 + 光照端三处改动），且每帧 1 步 Jacobi 的传播延迟会引入新的时域伪影调试面。等下界链路稳定后再评估推广。
- **compute SMAA**（条 8）：Astra 已有关/FXAA/TAA 三档，SMAA 是第四档锦上添花；3 pass 编排 + 2 张查表纹理的成本不低，收益面窄。等 AA 档位出现用户诉求再做。
- **RSM GI**（条 ②-3 所列）：Astra 前向架构没有现成的阴影图彩色附件与 G-buffer 法线布局，引入成本极高；且批次一已在 Ebin（GPL 可改编）下覆盖同一主题，若做 GI 优先走那条路线。
- **季节色调**（条 11）：实现简单但与服务器时间语义、Astra 生物群系染色叠加顺序需要设计决策，单独收益偏内容向；建议排在 1-5 之后。

## 附录：自抽查记录（成稿后逐一重开源文件核对）

1. `P:shaders/shaders.properties:10` — 重开核对：`iris.features.required=SSBO CUSTOM_IMAGES SEPARATE_HARDWARE_SAMPLERS HIGHER_SHADOWCOLOR`。属实。
2. `P:lib/atmosphere.glsl:2` — 重开核对：`float BETA_M = 3.996e-6 * fogAmount;`。属实（雾量调制 Mie 散射）。
3. `P:program/prepare_b.csh:93` — 重开核对：`vec3 MultiScattering = L2 / (1 - fms);`。属实（多次散射闭式解）。
4. `P:program/composite4.csh:104` — 重开核对：`vec2 FragPos = gl_GlobalInvocationID.xy * VOLUMETRICS_RES_INV + ivec2(frameCounter * VOLUMETRICS_RES, frameCounter) % VOLUMETRICS_RES_INV;`。属实（棋盘格增量更新）。
5. `P:generic/shadow/main.glsl:196-199` — 重开核对：`if(_IsWater > 0.001) { float Caustics = get_water_caustics(PlayerPos); ShadowTransparent *= mix(1, Caustics, _IsWater); }`。属实（阴影内焦散）。
6. `P:program/begin.csh:37` — 重开核对：`Light = max(vec4(0), Light / 6.1);`。属实（6 邻域平均含 0.1 衰减）。
7. `P:generic/lighting/lighting.fsh:98-99` — 重开核对：`float Porosity = Mat.SSS * 255.0 / 64.0; Mat.Albedo *= 1 - Porosity * 0.66 * Mat.Lightmap.y * wetness;`。属实（孔隙度湿润压暗）。
8. `P:generic/post/taa.glsl:124` — 重开核对：`ivec2 LastUpdatePos = FragCoord - FragCoord % VOLUMETRICS_RES_INV + ivec2(frameCounter * VOLUMETRICS_RES, frameCounter) % VOLUMETRICS_RES_INV;`。属实（云上采样的"上次更新位置"）。
9. `P:lib/all_the_uniforms.glsl:127-138` — 重开核对：`layout(std430, binding = 0) restrict buffer dataBuffer { vec3 SunColor; ... float SunVisibility; } dataBuf;`。属实（SSBO 常量缓冲）。
10. `P:shaders/shaders.properties:139` — 重开核对：`uniform.vec2.windDirection=vec2(randBSigned, sqrt(1 - randBSigned * randBSigned))`。属实（随机归一化风向）。
11. `P:program/shadow.vsh:42,44` — 重开核对：`imageStore(voxelImg_a, PlayerPosAbs, vec4(Color.rgb, 0));` / `imageStore(voxelImg_b, ...)`。属实（阴影 pass 顶点体素化，帧奇偶分写 a/b）。
12. `P:generic/weather.glsl:14` — 重开核对：`float TimeOfYear = worldDay % 120;`。属实（四季周期）。
13. `P:world-1/deferred2.fsh:1-3` — 重开核对：文件内容为 `#version 460 compatibility` / `#define DIMENSION_NETHER` / 空行 / `#include "/program/deferred2.fsh"`（实际 include 在第 4 行）。**修正**：报告中 wrapper 出处的准确行区间应为 1-4 行（含空行），本条按 1-4 理解。属实。
14. `P:generic/reflections.glsl:1-2` — 重开核对：`// "Sampling Visible GGX Normals with Spherical Caps"` / `// https://arxiv.org/abs/2306.05044`。属实（VNDF 论文出处）。
15. `P:LICENSE:3` — 重开核对：`All rights reserved unless otherwise explicitly stated.`。属实。

> 抽查发现的一处代码事实（非行号错误）：`P:generic/reflections.glsl:152` 存在一行空宏 `#ifdef `（#ifdef 后无标识符）。按 GLSL 预处理规范该行为可疑，实测该包以某种方式编译通过，提示此处可能依赖 Iris 预处理实现细节——若借鉴该文件结构需注意。
