# cyanide-shaders 性能调研（batch4）

日期：2026-10-03。范围：只读调研，产物仅本文件；行号相对 `reference_shaderpacks/cyanide-shaders/shaders/`（该包 shader 根即 `shaders/`，包根另有 AGREEMENT/CHANGELOG/CREDITS 三个 txt）。
去重基线：`shader_research/SUMMARY.md`、`SUMMARY-batch2.md`、`SUMMARY-batch3.md`、`docs/2026-10-02-shader-reference-performance.md`、`docs/2026-10-03-batch3-selected-optimizations.md`（下称「五份材料」），以及任务背景列出的 Astra 已实现手段。

## 概况

- 定位：Modrinth v1.1，150,284 下载（任务给定）。原版+ 观感增强，宣传「几乎不影响性能」；同时支持 OptiFine 与 Iris（`lib/Shaders.options:3` 的 `SHADERSMOD` 选项用于在 Iris 下修复天空）。其低成本的实际来源是**整包没有 shadow / deferred / composite / water 程序**，全部效果在 gbuffers 与 final 内完成（见「反面印证」1）。
- 血统：legacy OptiFine 模板（`#version 120`、`gl_FragData`、`ftransform`、`gl_TextureMatrix`、`gl_Fog`）。`block.properties:1-10` 文件头标明方块表来自 XorDev 的 "Default Shaderpack" 模板；`CREDITS.txt:8-11` 致谢 Akashii（原始 bloom 代码）与 XorDev（大气修正）。与已研究 62+ 包无同源代码证据，但属 OptiFine 经典模板谱系（与 batch3 VanillAA 等「原版复刻」同代际，无直接代码关系）。
- 许可：**包内无 LICENSE**；包根 `AGREEMENT.txt` 为自定义协议——第 1 节允许以其为底包/使用部分代码（条件：署名原作者、自身代码贡献显著、不得声称部分代码为原创、不得修改协议；若要以修改版变现需作者许可）。按五份材料对同类「自定义/口头协议」的惯例，代码级借鉴需先裁定（见「备注」），本报告只按事实登记。
- 规模：整包 38 文件；`shaders/` 树 35 文件；shader 代码（.fsh/.vsh/.glsl）**921 行**（wc -l 口径，与任务给定一致；另 `lib/Shaders.options` 56 行、`shaders.properties` 29 行、`lang/en_US.lang` 68 行、`block.properties` 9 行、包根 3 个 txt）。
- 结构：根目录 program = 主世界（`final`、`gbuffers_textured`、`gbuffers_clouds`、`gbuffers_skytextured`）；`world-1/` = 下界、`world1/` = 末地（各 6 个薄入口）。实现集中在 `program/{overworld,nether,end}/`，用 `#include` 拼装（如 `gbuffers_textured.fsh:5-6`）。全包无自定义缓冲、无阴影图、无纹理资源。

## 管线与调度

- program 清单（主世界）：`final`（vsh+fsh）、`gbuffers_textured`、`gbuffers_clouds`、`gbuffers_skytextured`，各含 vsh/fsh；下界/末地为 `final` + `gbuffers_textured` + `gbuffers_clouds`。**无 shadow、deferred、composite、water、weather、armor_glint 等程序**；无自定义 colortex 声明、无尺寸分档。
- `shaders.properties:23-27`：5 个 profile（Minecraft_Nostalgic / Performance / Default / Realistic / Vanilla），只用 `!FOG` / `!BLOOM` / `TONEMAPPING=n` 控制效果——**没有 `program.*.enabled`、没有 `size.buffer`、没有分辨率档**；`Performance` 档即 `!FOG !BLOOM TONEMAPPING=0`。
- `shaders.properties:1` `underwaterOverlay=false`；`:3-19` 为颜色/雾/后期菜单（`screen.LIGHTC` 4 列 RGB 滑条）；`:21` sliders 巨行。无任何 Iris 特性声明（optional features 均未用）。
- `lib/Shaders.options:7-9,15-16`：`FOG` 默认开、`BLOOM` 默认注释关；FOG_DENSITY/FOG_DIST 只在片元做一次乘法/线性缩放，无分档。
- `gbuffers_skytextured.fsh:6-11` / `.vsh:6-11`：`SHADERSMOD==1`（Iris）时整个天空程序为空体——用「空程序」绕开 Iris 下天空重复着色，属兼容 workaround，不是性能调度。
- 无 `blend.*`/`alphaTest.*` 声明；粒子/实体走同一 `gbuffers_textured`。

## 分模块性能手法清单

### 调度与阶段启停
- `shaders.properties:24` — Performance profile 关闭 FOG/BLOOM/tonemap（编译期宏），是包内唯一的成本控制手段。
- `lib/Shaders.options:7,15` — `FOG`/`BLOOM` 为编译期开关；关闭时对应计算从程序中消失。
- `gbuffers_skytextured.fsh:6-11` — Iris 模式天空程序空体（兼容用，非性能手法）。
- 无 program 级启停、无关闭时资源缩编、无缓冲尺寸分档。

### 地形光照与阴影
- `program/overworld/gbuffer/textured.glsl:61-66` — 顶点级伪方向光：`0.8 - 0.25*abs(nx*0.9 + nz*0.3) + ny*0.2` 乘进 `gl_Color`，与太阳方向无关，用来在没有阴影图时提供体积感。
- `program/overworld/gbuffer/textured.glsl:18` — 片元天光/方块光直接取 lightmap × `(0.85 - blindness)`；无 N·L、无阴影图、无彩色阴影、无 AO；全包 grep `shadowtex|shadowcolor` 零命中。
- `program/overworld/gbuffer/textured.glsl:62` — `mc_Entity==1`（block.properties 归组的草/花等平面受光方块）强制法线 +Y，供上面的伪光使用。

### 云
- `program/overworld/gbuffer/clouds.glsl:14-22` — 直接用原版云几何 + 纹理，片元只做 `1-blindness` 光照与 `gl_Fog` 线性雾；不渲染任何自定义云（零自绘云成本）。
- `program/overworld/gbuffer/clouds.glsl:36-45` — 顶点同样做视→世界变换后取 `length()` 作为雾距离（见反面印证 2）。

### 雾与大气
- `program/overworld/gbuffer/textured.glsl:25-26` — 雾二选一：水下 `1-exp(-density*dist)`、陆地 `clamp((dist - start*FOG_DIST)*scale,0,1)`；成本为每片元一次 mix。
- `program/overworld/gbuffer/skytex.glsl:14-34` — 天空色按 4 个时点权重逐像素混合并乘到天空纹理上（每像素 8 次乘法级）。
- `program/overworld/gbuffer/skytex.glsl:14-24` — 天空亮度/颜色常量全部逐片元重算，无帧级缓存。
- `lib/TimeCalculation.glsl:5-8` — 时点权重为文件作用域变量，凡 include 它的程序（含顶点阶段、final）每次调用重算 4 组 clamp 表达式（见反面印证 1）。

### 水与水下
- 全包无水体程序、无折射/反射/吸收/焦散；水下仅表现为 `program/overworld/gbuffer/textured.glsl:25` 的雾分支，且因 `isEyeInWater==0.9` 为死分支实际不生效（见反面印证 3）。

### 粒子·实体·天气
- `program/overworld/gbuffer/textured.glsl:19-22` — 实体/粒子共用同一 gbuffer：`color × lightmap × texture`，`MOB_FLASH` 时按 `entityColor` 混合；无额外分支。
- 无 `gbuffers_weather` 程序：雨/雪走原版渲染，包不付费。

### 后处理与缓冲内存
- `program/overworld/final.glsl:57-82` — Bloom：全分辨率、无阈值/亮度提取，`for (i=-8;i<8;i++)` 每轮 8 次 tap（共 128 次 `texture2D`），循环内 `sc -= 1.0` 与 `samples` 计数均运行时求值；`blm_amount`（:60）算出即未用。
- `program/overworld/final.glsl:84-102` — 每像素重算 4 时点亮度/光色并合成 `mixBT`。
- `program/overworld/final.glsl:106-116` — tonemap 五选一（Filmic / Uncharted2 / ACES 拟合 / Reinhard）。
- 全包仅单一颜色目标（`gl_FragData[0]`）+ 原版深度；无额外缓冲、无 mip、无历史。

## 反面印证

1. **时点权重逐调用重算**：`lib/TimeCalculation.glsl:5-8` 在 `final.fsh/.vsh`（root `final.fsh:5-7`）与 `gbuffers_textured.fsh/.vsh`、`gbuffers_skytextured.*` 中被 include；`program/overworld/final.glsl:86-102` 每个屏幕像素再乘一次。与 Astra 的「帧不变量/调色下沉 CPU」纪律完全相反。
2. **雾距离取世界坐标长度**：`program/overworld/gbuffer/textured.glsl:55-59` 与 `program/overworld/gbuffer/clouds.glsl:37-41` 先把视空间坐标乘 `gbufferModelViewInverse` 转回世界，再 `length(pos)` 写入 `gl_FogFragCoord`——旋转不改变长度，两次矩阵乘是冗余，且得到的是到世界原点的距离而非相机距离（雾会随玩家在世界中的位置漂移，疑似 bug；是否实机可见未验证）。
3. **水下雾死分支**：`program/overworld/gbuffer/textured.glsl:25` 用 `isEyeInWater==0.9` 判断水下——现代 Iris/OptiFine 的 `isEyeInWater` 为 int（0/1/2/3），该条件恒假，水下永远走线性雾；同包 `program/overworld/gbuffer/clouds.glsl:17` 用的是正确的 `>0`。
4. **Bloom 预算与结构**：`program/overworld/final.glsl:57-82` 全分辨率 128 tap、无阈值、无降采样、无 mip/tap 分档；开启 BLOOM 时成本高于 Astra 的 0.25 捕获 + mip 链 + tap 分档体系，观感也更糊。
5. **光照模型的全部代价控制来自省略**：无阴影图、无法线光照、无 SSR/体积/时域；顶点伪光（`program/overworld/gbuffer/textured.glsl:64`）是固定轴向衰减，正午与日落同形、不随太阳移动。对 Astra 无可迁移的工程手法。
6. **空程序体兼容 hack**：`gbuffers_skytextured.fsh:9-11` 在 Iris 下编译空体，而不是用 `program.*.enabled`（且无 main 的 GLSL 是否被 Iris 接受未实测）——不要学这种停用方式。
7. **配置层无联动**：`Shaders.options` 的 FOG/BLOOM 开关与 profile 是唯一联动；关 BLOOM 后 final 内仍执行亮度/光色计算（`program/overworld/final.glsl:84-102` 不在 `#ifdef BLOOM` 内），不存在「关闭时缩编计算」。
8. **`light = (0.85 - blindness) * lightmap`**（`program/overworld/gbuffer/textured.glsl:18`）：blindness∈[0,1] 做减法可把光变负；同包 clouds 用 `1-blindness` 乘。属明显实现瑕疵，不应模仿。

## 新颖借鉴点

- **A 组：无。**
- **B 组：无。**
- **C 组：无。**

理由（逐候选排除，均已对 Astra grep）：

| 候选 | 来源 | Astra 侧证据 / 排除依据 |
|---|---|---|
| 顶点级无阴影伪方向光（提供方向感） | `program/overworld/gbuffer/textured.glsl:61-66` | 类别已在 `SUMMARY-batch2.md` ②-1「无阴影档方向感」（drdestens/bvs，档位快赢）及 ⑤-3 #3 列出；Astra `Astra/shaders/program/lit.vsh:85-87` 已有完整法线打包，`Astra/shaders/global/lighting/diffuse.glsl:250-260` 有 `static_shadow` 兜底、`Astra/shaders/shaders.properties:235-240` 可整体关阴影（`program.shadow.enabled=SHADOWS`）。grep `0.8 - 0.25|abs\(normal|fake.*light` 零命中，但类别已列，且该式与太阳方向无关、比已列方案更粗 |
| 编译期效果开关（FOG/BLOOM/tonemap 宏 + profile 关效果） | `lib/Shaders.options:7-27` | Astra 已有 program 级熔断与档位（`Astra/shaders/shaders.properties:279` 等，10 包印证，SUMMARY ②-6 首行），本包弱于 Astra |
| 原版云几何 + gl_Fog 零成本云 | `program/overworld/gbuffer/clouds.glsl:14-22` | Astra `Astra/shaders/shaders.properties:314` 已 `clouds=off` 并自绘平面云；属功能取舍非手法 |
| 5 档 tonemap 多选 | `program/overworld/final.glsl:11-48` | SUMMARY ②-5 已列 ACES/Uncharted 等算子族（Nostalgia/Kappa/Photon 3 包印证）、Mellow 报告已列 4 算子，非新颖 |
| 天空 4 时点逐像素混色 | `program/overworld/gbuffer/skytex.glsl:14-34` | 与 Astra SH9 方向性天光/物理天空相比是低配做法；「帧不变量下沉 CPU」已在五份材料列为 Astra 已实现 |
| 单颜色目标极简管线 | 全包 | 属功能省略；Astra 已有多缓冲与阶段启停纪律，不构成可借鉴手法 |

## 无法判定项

1. **Iris 是否接受无 main 的空程序体**（`gbuffers_skytextured.fsh:9-11`）：若接受，则是「用空程序停用 pass」的低配替代；若报错则主世界天空路径可能整个失效。未实机加载验证。
2. **`gl_FogFragCoord` 取世界原点距离的实际观感影响**（反面印证 2）：理论上雾会随坐标漂移，但作者宣称支持 Iris+OptiFine 且被大量使用，是否存在引擎侧约定使长度恰好可用，未实测。
3. **`AGREEMENT.txt` 的代码级复用边界**：协议允许「使用部分代码」但要求显著修改/署名/不得修改协议，且变现需授权；与 Astra 现行 GPLv3/第三方登记体系是否兼容，需统帅裁定（本报告不代决）。
4. ENCR/ENCG/ENCB/ENCBR（附魔颜色）只在 `shaders.properties:21` 的 sliders 巨行中出现，`lib/Shaders.options` 与全部 .glsl 中零定义、零消费者（grep `ENCR|ENCB` 全包仅命中 :21）——残留/未接线选项，与性能无关。
