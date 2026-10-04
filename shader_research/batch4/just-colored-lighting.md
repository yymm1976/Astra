# just-colored-lighting v1.0.2 性能调研（第四批 batch4 · 只读）

> 日期：2026-10-03。范围：只读调研，未改动任何参考包或 Astra。
> 路径约定：本包 **shader 根目录即包根**（`shaders.properties` 在包根，Iris 以此为 shader 根）；下文 file:line 相对 `reference_shaderpacks/just-colored-lighting/`。包内另有一个 `shaders/` 子目录，它是活动代码的核心实现树（`composite/shadow/voxel_photons/gi` 等；任务简报的「18 文件 / 4,581 行」即该子目录口径），包根同名文件是 2-3 行的 `#include` 包装。
> 去重基线：已读 `shader_research/SUMMARY.md`、`SUMMARY-batch2.md`、`SUMMARY-batch3.md`、`docs/2026-10-02-shader-reference-performance.md`、`docs/2026-10-03-batch3-selected-optimizations.md`；其中列过的借鉴点一律不计为新颖点。
> 版本/下载量（v1.0.2、619,699）来自任务简报；包内无 pack.json/README，未能本地复核。

## 概况

- 定位：「为 Potato 级低配机做的快速光影」+ 主世界/下界体素洪泛彩色光照与自动光源识别；阴影为可选（SHADOWS 0~7 档，默认 define 0，菜单 profile 设 2/6）。全屏后处理默认 0 个额外 pass（见下）。
- 血统：全包 © timetravelbeard 2023-2025 自研（`settings.glsl:1`、`main_f.glsl:1`、`voxelizing.glsl:1`、`noise.glsl:1` 等），无 BSL/Complementary 代码头。与已研究包的交叉：batch3 §2.3/§3.11 的 Pegasus 自带 `gi.glsl` + `voxel_photons.csh`，与本包同名同构（体素太阳 GI、帧奇偶双缓冲、写入抑制），该机制已按 Pegasus 记入 batch3，本文只报增量与差异；Voxy/DH 集成方向已在 batch2 §②-7 列为中期，本包有完整可参考实现（`shaders/voxy.glsl`、`world0/voxy_opaque.glsl`、`dh_*` 程序）。
- 许可：包内**无 LICENSE**（全包 `find -iname "*licen*"` 仅命中 `licensed/` 目录名）；核心文件头声明「© … all rights reserved. You cannot modify, redistribute, or make derivative works of this. Do not steal any of this code or use "code snippets".」（`settings.glsl:1-5`、`main_f.glsl:1-5`、`shaders/voxel_photons.csh:1-5` 等）→ 只能思路级独立重写并在 THIRD-PARTY.md 登记，**不得复制任何代码片段/结构照抄**。第三方：`licensed/spaceConversions.glsl:1-4` 标注来自 Jessie-LC/open-source-utility-code（仅 Voxy 路径用，许可正文未随包）；`stuff/noise/blue/1.png` 蓝噪声贴图无来源说明。备注：Modrinth 公开分发与「不得修改/再分发」头部声明并存，按最保守解读处理。
- 规模：306 文件；shader 代码 292 文件 / 23,391 行（含 2 个备份 `.glsl` 与 `voxy bk.*`、`photonics/` 等非活动件，活动代码约 288 文件）。构成：包根 87 文件（共享 include + 全维度包装程序）、`world0/`、`world-1/`、`world1/` 各 60（维度包装）、`shaders/` 18 文件 4,581 行（composite/shadow/voxel_photons/gi/clouds 等核心实现）、`stuff/`+`holding/`+`photonics/`+`licensed/` 为库与实验件。

## 管线与调度

- program 清单（活动）：gbuffers_basic/block/damagedblock/entities/hand/hand_water/line/particles/spidereyes/terrain/textured/textured_lit/water/weather/armor_glint/beaconbeam/clouds/skybasic/skytextured + shadow（+ dh_shadow/dh_terrain/dh_water/dh_generic、clrwl_*、voxy_opaque/voxy_translucent）+ prepare(基座) + prepare_a/b/c/d（洪泛计算）。**无 final、无 deferred、无 TAA/Bloom/SSR 程序**。
- 阶段启停：`shaders.properties:180-182`（SHADOWS==0 → `program.shadow.enabled=false`）、`:183-185`（`program.dh_shadow`）、`:187-189`（BORDERS==0&&GODRAYS==0&&CLOUDS==0 → `program.composite.enabled=false`）。默认三项全 0 → composite 阶段整段停用，整帧只剩 gbuffers+shadow。
- 分辨率/缓冲分档：`shaders.properties:191-196`（`size.buffer.colortex1=0.5/0.25`，DH 深度备用目标）；`main_f.glsl:2390-2406` 仅 DH 边界开启时第二输出（R16F 深度），否则 `DRAWBUFFERS:0`。
- 体素资源与调度：CUSTOM_IMAGES 3D 图像按 VOXEL_AREA 档位声明（`shaders.properties:221-317`，32³~1024³，R32UI 占用 `clear=true` + RGBA8 彩色光 `W×2W×W` 纵向双缓冲）；SOLAR_GI≥3 另声明 128×256×768 GI 图像（`:319-321`，写出被注释，见反面印证）；手持光 2D 图像 128×128（`:396-398`）。洪泛 dispatch 数按 `LIGHT_UPDATE_SPEED` 1/3/5 阶梯：`<3` 停 prepare_a/b、`<5` 停 prepare_c/d（`:328-356`）；长名/矩阵见 `shaders/voxel_photons.csh:15-127`（WORK_GROUP_SIZE 64/128/256 编译期切换 local_size 与 workGroups 表）。
- 阴影：shadow pass 兼任体素化（`shaders/shadow.vsh:67-83`；下界另有 GRASS_SHADOWS=0 时草退化，`:90-92`）；下界整段顶点退化 `gl_Position=vec4(10.0)` 且 fsh 直接 discard（`shaders/shadow.vsh:94-96`、`shaders/shadow.fsh:2-7`）——下界保留 pass 只为体素写。
- 阴影采样档：`SHADOWS` 0~7（`settings.glsl:756`；`:820-833` 采样数/半影滑条）。1=单点、2=4 角双线性、3=crisp、4=4+4 混合、5=螺旋半影、6=螺旋 crisp、7=世界网格种子锁定（`shadows.glsl:9-37/40-66/73-171`）。

## 分模块性能手法清单

### 调度与阶段启停
- `shaders.properties:180-189` — 三处 program 级熔断；composite 默认成立（0 pass）。
- `shaders.properties:328-356` — 洪泛 dispatch 阶梯（1/3/5）。
- `shaders.properties:361-380` — `shadowEntities/shadowBlockEntities/shadowPlayer`（Iris）与 `voxelizeLightBlocks` 的程序级 caster 开关。
- `shaders.properties:199-200`、`:392-394` — CPU 表达式 uniform（`speed_smooth1` 的 smooth() 预平滑、夜视温度平滑）。
- `settings.glsl:972-974` — LIGHT_UPDATE_SPEED 1/3/5 + `FADE_LIGHT_UPDATES=1`、`FADE_LIGHT_UPDATES_AMOUNT=0.40`。
- `shaders.properties:219` — `iris.features.optional = FADE_VARIABLE`（分块加载渐显，配 `main_f.glsl:2117-2122` 融进雾量）。

### 地形光照与阴影
- `main_v.glsl:290-317` — 顶点级阴影坐标 + `lightDot` 打包进 `shadowPosv`（片元默认不重算；`main_f.glsl:741-771` 仅 PIXEL_LOCKED/`DUAL_DISTORT` 时重算）。
- `main_f.glsl:741-771` — 世界网格量化阴影位置（PIXEL_LOCKED_SHADOW_RES 默认 5555≈关闭）+ 按面倾角 bias（SHADOW_BIAS_PL）。
- `main_f.glsl:1845-1857` — `face_shading>0` 才 include `shadows.glsl`（背光跳过）；下界 `main_lighting=0` 整段跳过阴影。
- `shadows.glsl:9-37` — 4 角双线性重建可见度；`:40-66` 可选 8-tap 平均；`:73-111` 螺旋核，半径 ∝ |sdist|（近 PCSS），每像素噪声扰动；`:122-132` 世界/屏幕种子 + SHADOW_SUB_PIXEL_SEED_RES（低分辨率防闪）；`:226-240` 阴影距离边缘淡出（DH 另有淡出）；`:251-297` 只有受光像素才读 `shadowtex0/shadowcolor0`（彩色阴影门控）。
- `settings.glsl:820-833` — `SHADOW_SAMPLES8` 由浮点滑条推导循环常量（编译期展开量化 tap 数）。
- `voxelizing.glsl:100-102` — `mod(gl_VertexID,4)==0` 每 quad 单顶点写体素；`:159-181` 光源判定（renderStage/`at_midBlock.w`/entityId/硬编码 ID 组）；`:293-300` 光源色 = 图集最高 mip 一次采样（块平均色）+ 饱和度整形；`:404-428` 体素编码（.43 自发光、.1 半透明、.23 不透明、.31-.35 半砖/楼梯分面、>.4 全遮挡）；`:572-588` `imageAtomicMax` 占用写入（玻璃短路，`:487/499` 阻止同格再写）。
- `shaders/voxel_photons.csh:194-224` — 帧奇偶乒乓（同图沿 Y 双缓冲）+ 非 flip pass 的相机位移补偿；`:235-240` 逐邻居衰减系数（LIGHT_FALLOFF 1/2）；`:242-248` 质量≥2 才 include `gi.glsl` 与逐面透射；`:262-309` 逐面透射矩阵（玻璃染色归一化 + 楼梯/半砖分面权重）；`:313-317` 自发光/反弹格 rgb 直接透传；`:320-372` 6 邻域 max 洪泛；`:374-401` 写抑制（差值 <0.5/255 跳过 imageStore）与旧值混合（FADE_LIGHT_UPDATES）；`:404-487` 手持光图像更新与帧间衰减。
- `shaders/gi.glsl:8-11` — 仅天光 >0.01 才做太阳 GI；`:18-143` 空气格取 6 邻接固体块色与太阳方向点积加权（SOLAR_GI_DOT/REDUCE_GI_LEAKS）；`:145-252` 体素投影到 shadow space（沿用 distort）做单点/2/3/8/16 采样日照判定；`:254-379` 日照色（lightmap 天空色或自定义色）×彩色阴影×天光写入空气格作为光源（随后被洪泛传播）；`:381-403` TRACELESS_PT：用邻格与中心格差值塑形方向性 LPV。
- `main_f.glsl:1561-1805` — 消费端档位 1/2/3/4/7：1=法向偏移单采样；2=+镜面第二采样；3/4/7=梯度和非线性方向项 + 逐材质漫反射/镜面行为（详见新颖点）；`:1788-1805` 体素半径内以体素色替换光图手电光，超出按 `torch_fade`（`:788`）渐隐回光图。

### 云
- `shaders/composite.fsh:163-167` — 只有天空像素（深度≥0.999·far）执行云 raymarch，地形像素零成本。
- `shaders/clouds1.glsl:18`、`clouds2.glsl:22` — 视线朝下早退；`clouds1.glsl:35` 10 步、`clouds2.glsl:43` 11 步；`clouds2.glsl:63` 射线中段步长×3.5（加速）、`:69` 顶层切片、`:98-110` 5 步内阴影散射近似；`clouds1.glsl:91`/`clouds2.glsl:156` 无云时深度哨兵 1000。
- `shaders/composite.fsh:477-509` — godrays 循环复用 CLOUDS==3 的云深度做遮挡（不再单独采样云）。
- 云不进光照/无云影缓存、无时域历史。

### 雾与大气
- `main_f.glsl:2083-2135` — 前向雾：水下固定距离雾 + 线性雾 + 边界雾（rainStrength 放大），并融 CHUNK_FADE；无体积雾。
- `shaders/gbuffers_skybasic.fsh:55-66` — 解析天空 `mix(skyColor, fogColor, fogify(upDot))`（零纹理、零射线）；`:76-88` 星星走原版 `starData`。
- `main_f.glsl:278-292`、`:581-593` — 洞穴漏光抑制（eyeBrightness/高度混合，质量项）。
- THE_ONION/ONION_* 等大气缓存选项为死代码（见反面印证）。

### 水与水下
- `main_f.glsl:1023-1042` — FANCY_WATER：3 次 `fractal_noise_3d(4)` 差分得水面法线（仅水体 shader + PBR≥2）。
- `main_f.glsl:2084-2088` — isEyeInWater 距离雾（黑暗/失明缩短）。
- `pbr2.glsl:41-48`、`pbr3.glsl:54-60` — 解析天空反射（skyColor 近似）+ 太阳高光；**无 SSR、无反射缓冲**。
- `settings.glsl:157-176`、`:355-377` — WATER_STYLE/CAUSTICS/WATER_ABSORB/DIRTY_WATER/WATER_FOG/PEARL_WATER/REFRACTIONS 等水生效果选项均为死定义（见反面印证）。

### 粒子·实体·天气
- `main_v.glsl:329-340` — 粒子/手部在顶点阶段写体素（PARTICLES_LPV、HAND_LIGHT_CAPTURE_BACKUP，仅粒子 renderStage）。
- `voxelizing.glsl:440-444` — 粒子直接写彩色光图像（RGBA8）。
- `main_f.glsl:2226-2228` — 天气粒子 alpha 限幅（RAIN_OPACITY），无自定义雨雪几何。
- `main_f.glsl:2066-2068`、`:2222-2224` — 实体受伤色/名牌透明度；实体与地形共用 main_f 光照路径（`world0/gbuffers_entities.fsh:6-20`）。

### 后处理与缓冲内存
- 无 final/deferred/TAA/Bloom；composite 默认停用（`:188`），gamma 在 `main_f.glsl:2193-2195` 条件补偿。
- `A:shaders.properties:745-749` — Astra 侧 3 个自定义图像（occupancy R32UI `clear=true`；光场 A/B RGBA16F half_float 乒乓），对照本包 `shaders.properties:221-317`（R32UI 占用 + RGBA8 彩色光，尺寸随 VOXEL_AREA 档位）；
- 无任何历史缓冲/时域累积资源（TAA_ON/PTX 等选项无消费者）。

## 反面印证

1. **选项面与实现大面积脱节（约 20+ 死定义，含半成品）**：`TAA_ON`（`settings.glsl:220`）、`RAY_ACCELERATION/REFINER_STEPS_RAY/RAY_DIST`(:31-34)、`PATH_TRACING_RESOLUTION(_DIVIDER)`(:13,:271)、`THE_ONION/ONION_*/SKY_ONION_*`(:686-722)、`QUICK_CLOUDS/FOG_LAYERS/POOFY_LAYERS/CIRRUS_LAYERS`(:253-256)、`DOWNSAMPLING`(:356)、`KILL_SWITCH`(:26)、`SHADOWS==5/6/7` 之外的 SS_SHADOWS/SS_SUN_*（:657-664）、`DEFER_SHADING/UNDEFER_SHADING`(:272,:518)、水/折射/焦散全组（:355-377,:519-532）；`photonics/` 与 `shaders/composite_cloouds2.fsh` 无任何 include 点。半成品更强的证据：SOLAR_GI=1 的消费者在 `main_f.glsl:1719-1723`（`#if SOLAR_GI == 1` 采样 cSampler4_gi），而 `cimage4_gi` 只在 SOLAR_GI≥3 时声明（`shaders.properties:319-321`），且 `shaders/gi.glsl:411` 唯一写出被注释 → 该档位取不到有效数据；`shaders/clouds2.glsl:103-106` 引用未定义的 `fnoise_o3d` → CLOUDS==2 路径不可编译（grep 全包仅 3 处引用，无定义）。Astra 纪律对照：新增选项必须同时有消费点与资源声明，删除路径不得留下半个消费者（`Astra/shaders/program/nether_light.csh:12-17` 的 9 级 shadowcomp 启停即为正例）。
2. **云噪声成本**：sin-hash 程序噪声（`clouds.glsl:11-103`），每步 2-3 次 4 阶 3D value noise、每 octave 8 次 hash；天空像素 10-11 步固定无早退（只有透射/命中类信息才隐式衰减）。属「不预计算、不上贴图」的反面；Astra 平面云走 CPU 化调色与距离步数分档，不要引入此类逐采样重噪声。
3. **以时域滞后换 dispatch 数**：默认 `LIGHT_UPDATE_SPEED=1`（每帧 1 次洪泛）+ `FADE_LIGHT_UPDATES=1`（与旧值 0.40 混合，`shaders/voxel_photons.csh:379-392`）——用更新滞后/混色掩盖低传播率；`docs/2026-10-03-batch3-selected-optimizations.md` 已记 Astra 因噪点/内容有效性问题暂缓同类「分帧体素更新」，不作为借鉴。
4. **8bit 光场 + 量化修补**：彩色光场 RGBA8、占用/光源经 `packUnorm4x8`（`voxelizing.glsl:437`），需要 `FIX_BLOCKLIGHT_GHOSTS` 每帧减 1/255 防鬼影（`shaders/voxel_photons.csh:381-383`）；Astra 光场为 RGBA16F（`A:shaders.properties:748-749`），精度路径更稳，不建议为带宽回退到 8bit。
5. **资源分配与用途不匹配**（微）：手持光图像 128×128 实际只用 2×3 格（`shaders.properties:397` vs `shaders/voxel_photons.csh:407-486`）。
6. **逐邻居衰减**：洪泛对 6 个邻居逐个乘衰减（`shaders/voxel_photons.csh:322-372` 的 `LIGHT_FADE_VXFL`）；Astra 已在取 max 后只乘一次（`A:program/nether_light.csh:58-62` 注释：正衰减保持 max 序，等价且更省）——此处 Astra 反而更优，可直接作为「不学」对照。

## 新颖借鉴点

### 去重排除（grep 命中等价或已列，不作为新颖点）

| 本包手法（来源） | 已列位置 | Astra 现状证据 |
|---|---|---|
| 体素乒乓 + 相机位移 + 跨帧混合（`shaders/voxel_photons.csh:200-224,374-401`） | batch1 §②-4（7 包印证）「时域乒乓+相机搬移+跨帧累积」 | `A:program/nether_light.csh:53-68` 步奇偶 A/B；`A:shaders.properties:700-742` 9 级 shadowcomp |
| 体素更新速度档 + 写入抑制（`settings.glsl:972-974`；`voxel_photons.csh:374-401`） | batch3 §2.1 A 组（pegasus） | `A:program/nether_light.csh:43-64` 每步无条件写；grep `SAVE_WRITES|0.5/255` 0 命中 |
| 体素太阳 GI：shadowmap 日照注入 + 方向权重 + 泄漏抑制（`shaders/gi.glsl:8-11,145-252,254-379`） | batch3 §2.3 C 组（Pegasus 同名同构文件） | `A:program/nether_light.csh:19-29` 仅固定发射色；grep `shadowtex\|sun` 在该文件 0 命中 |
| 每 quad 单顶点写体素（`voxelizing.glsl:100-102`） | batch2 §②-4（amethyst） | `A:program/shadow.vsh:54-84` 无 `gl_VertexID` 门（grep 0 命中） |
| 图集最高 mip 取块平均色（`voxelizing.glsl:293-297`） | batch3 §3.15（Soft Voxels Lite） | Astra 无等价，但已列 |
| 螺旋核半径 ∝ 遮挡深度 + 世界网格种子（`shadows.glsl:73-141,122-132`） | batch1 §②-1 PCSS（7 包）+ batch3 §2.2 像素锁定（simply-upscaled） | Astra 配对四角核；旋转采样被明确拒绝（`A:global/lighting/diffuse.glsl:270-273`） |
| 彩色阴影仅受光像素才读（`shadows.glsl:251-297`） | Astra 已实现清单「遮挡时才读彩色阴影」 | `A:global/lighting/shadowmap.glsl` 链路 |
| 阴影距离边缘淡出 + DH 淡出（`shadows.glsl:226-240`） | batch2 §②-1 已列（redhat/bsl-classic） | Astra 静态阴影兜底/淡出 |
| 解析天空反射 + 太阳高光、无 SSR（`pbr2.glsl:41-48`、`pbr3.glsl:54-60`） | Astra 已实现清单「解析天空反射回退」 | `A:lib/sky_reflection_cache.glsl`、水面 SSR |
| 距离门控贴图过滤 CPF（`timetravelbeards_Better_3D_Textures.glsl:877,892-897`） | batch3 §2.1 已列（Simply Upscaled「距离门控贴图过滤」） | 已列；Astra 未接但为已知候选 |
| program 熔断 / size.buffer 分档 / CPU uniform / 维度独立程序 / 手持光连续衰减 | Astra 已实现清单 | `A:shaders.properties:88-167,191-196,554`；`A:global/lighting/blocklight.glsl:63-103` |

### A 组（低代价，可直接排期）

**A-1 体素彩光方向性梯度提取（免光线追踪的方向性 LPV）**
- 机制：对同一体素光场取「沿世界法向偏移采样 L」与「中心采样 L2」，用差值塑形出方向性分量：`dramaric=clamp(L-L2*0.8,0,1)*2`；`directional2=min(L2,pow(clamp((L-L2)*DBLX_MULT,0,1)))` 再按亮度/色相分解重建（保持色相）；档 7 再按材质粗糙度/SSS 混合进漫反射与镜面（`DIFFFUSE_VX_BEHAVIOR`/`SPECULAR_VX_BEHAVIOR`），晶体 SSS 走折射方向查找。
- 来源：`main_f.glsl:1612-1640`（档 3）、`:1641-1682`（档 4）、`:1684-1785`（档 7，含 `:1703-1717` 漫反射行为与 `:1736-1753` 镜面行为；档位由 `shaders.properties:14,16` 的 Fancy/Fancy_Fast profile 设 `FLOODFILL_LIGHTING:7`）；compute 端同思想见 `shaders/gi.glsl:381-403`（TRACELESS_PT）。
- Astra 未实现证据（grep）：`grep -rn "gradient|directional" global/dimension/ lib/nether_voxel_grid.glsl` 只命中 `global/dimension/end_geometry.glsl:230-233`（末地几何法线）与 `global/dimension/overworld.glsl:15`（天空），无体素光方向项；`grep -rn "astraLightSampler" .` 仅 `global/dimension/nether_colored_light.glsl:23` 一处 `textureLod` 单样本 + `program/nether_light.csh` 传播采样；消费者 `global/dimension/nether.glsl:173-179` 只做单样本 + coverage 淡入。
- 迁移代价：在 `A:global/dimension/nether_colored_light.glsl` 增加第二个偏移采样与方向权重（约 10-20 行 + 1 个强度/开关选项，无新 pass、无新缓冲），代价约 +1 次 texture3D；需 A/B 校准强度并与下界体积雾解耦验证（Astra 体积雾当前不采样光场）。

### B 组（中代价，需接线）

- 无。

### C 组（大工程战略项）

- 无（体素太阳 GI/多 bounce 相关代码在本包属半成品：`cimage4_gi` 写出被注释，`shaders/gi.glsl:411`，不足以作为 C 项依据）。

## 无法判定项

1. **逐面透射矩阵（楼梯/半砖/染色玻璃）**：`shaders/voxel_photons.csh:262-309` + `:313-317` + 编码 `voxelizing.glsl:404-428`。Astra 现在只区分 solid 位与 kind（`A:program/shadow.vsh:68-83`），无分面遮光。卡点：这是精度/画质机制而非省算力（会让更多格子透光、传播更贵），与性能目标方向相反；是否作为画质预算另立项需统帅判定。
2. **手持光颜色自动检测**：`voxelizing.glsl:451-568`（imageAtomicMax 到 `cimage_held_light`）、消费 `main_f.glsl:1355-1398`、帧间衰减 `shaders/voxel_photons.csh:404-487`、开关 `AUTO_HAND_HELD_COLOR_DETECTION`（`settings.glsl:1228`）。Astra 手持光是单一 `BLOCKLIGHT_COLOR`（`A:lib/colors.glsl:41`）+ CPU uniform（`A:shaders.properties:554`），无按物品取色。卡点：属功能借点（影响色板/风格一致性），非性能收益，且需确认不与 Astra 调色体系冲突，未列入 A/B/C。
3. **WORK_GROUP_SIZE 档（64/128/256）**：`shaders/voxel_photons.csh:15-127`，与 VOXEL_AREA 组合成手写表；Astra 固定 8×8×8/64³（`A:lib/nether_voxel_grid.glsl:18-31`、`A:program/nether_light.csh:13-14`）。卡点：通用 compute 占用率调参，缺「Astra 未实现即收益」的证据，需实机实测。
4. **下界 shadow pass 顶点退化、保留 pass 供体素写**：`shaders/shadow.vsh:94-96` + `shaders/shadow.fsh:2-7`。机制本身（顶点退化剔除投射）已在 batch3 §2.1 列过；本包新意在「整维度」范围。Astra 事实：下界 shadow 无任何消费者（grep `shadowtex|shadowcolor|surface_shadow` 在 `global/dimension/` 只命中 `global/dimension/end.glsl:45`，那是末地），但 `A:program/shadow.vsh:86-150` 仍完整光栅化（无维度退化分支，只有末地 `end_shadow_ndc`）。卡点：是否作为 batch3 条目的范围延伸采用，交统帅判定（若采用，需保留 `A:program/shadow.vsh:87-89` 的体素写入不受影响）。
5. **FADE_LIGHT_UPDATES 旧值混合**：`shaders/voxel_photons.csh:379-392`。与已列「体素更新速度档+写入抑制」「跨帧累积」部分重叠，纯增量只剩「用混合掩盖降频跳变」；Astra 已暂缓分帧更新，是否单取 fade 需实测。
6. **Iris 特性接口**：`oit = true`（`colorwheel.properties:4-13`）与 `IRIS_INLINE_GLINT/mc_sampleGlint/mc_hasGlint`（`main_f.glsl:2342-2383`）。Astra grep `oit|INLINE_GLINT|mc_sampleGlint` 均 0 命中；卡点：属 Iris 引擎特性（非本包自研实现），是否带来净性能收益无法从包内判定，且与 Astra 的透明度/伪发光处理可能冲突。
7. **非活动件未逐行评估**：`main_f (vx try1 1 backup).glsl`、`photonics/`、`shaders/composite_cloouds2.fsh`、`voxy bk.*`、`shaders/voxy.glsl`（1,666 行，仅 Voxy mod 路径生效）。若统帅要推进 Voxy 集成（batch2 已列中期），可另派一次针对 `shaders/voxy.glsl` 的专项。

## 备注（需统帅决策）

- [疑问] 任务简报的规模口径「shaders 树 18 文件 / 约 4,581 行」与整包实际（306 文件 / 23,391 行代码）不一致；已核实 18 文件/4,581 行对应包内嵌套 `shaders/` 子目录（composite/shadow/voxel_photons/gi 等核心实现）。本报告按实际全包调研，并保留该口径说明。
- [假设] file:line 采用「相对包根」路径（因该包 shader 根即包根）；若需与其它批次统一为「相对 `<slug>/shaders/`」，包根文件的引用需整体改写。
- [建议] 唯一 A 级借点是市场取向的「体素彩光方向性梯度」（免 PT 的方向性），如需排期建议先做下界单场景 A/B（强度/雾耦合/噪声）。
- [建议] 下界 shadow 光栅退化（无法判定 #4）成本极低、Astra 侧下界无 shadow 消费者，建议统帅确认是否并入 batch3 已列的「顶点退化剔除」条目一并实施。
- [疑问] 包内无 LICENSE 而头部明示「不得修改/再分发/不得用代码片段」，与 Modrinth 公开分发并存；本报告按最保守解读（只可思路级重写并登记）处理，若统帅掌握上游授权信息请复核。
