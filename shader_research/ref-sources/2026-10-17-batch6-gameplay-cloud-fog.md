# Batch6 本地参考包深挖：玩法联动视觉 / 云机制 / 体积雾

日期 2026-10-17。方法：只读逐包读源码 + grep 命中计数。证据强度标注〔读源码〕（已读文件行号）/〔实测工具〕（grep 命中数）。所有性能/收益判断无实机依据处写"未验证"。不修改 Astra/、reference_shaderpacks/、docs/。

排除清单已遵守：batch5 A/B/C/V 全部、2026-10-17 机制报告 8+1 条、docs/参考与取舍.md 不重做清单、SUMMARY-final 排除项、风格向，均不列为新候选（命中者进文末"查过判定"表并注明）。

许可缩写：MIT/Apache=可代码级；CLA=Complementary/RV/fantasy/luster/artshade/muuf/verlixia/prismarine 禁代码级仅思路；Photon=条件再分发可研读公式；LGPL=MakeUp；无LICENSE=dercode 默认保留所有权利仅思路且谨慎。

---

## 候选（按性价比排序）

### 候选1 地面雨滴溅落闪光（Rain Splash Speckle）
- 通俗原理：下雨时朝上的湿地面随机闪出小亮点，模拟雨滴砸地的水花反光；用屏幕坐标噪声取一个值，乘雨强和"面朝上"程度后加到颜色上。
- 出处：velocity-shaders `program/deferred1.fsh:119-131`（HELIOS_RAIN_SPLASH：upDot>0.6 朝上、distSq<900 近处、splashNoise=noisetex(屏幕坐标+时间)、splash=noise^8*rainStrength*INTENSITY、Color+=vec3(0.7,0.75,0.85)*splash*upDot）；开关 `lib/settings.glsl:241-242`（INTENSITY 0.4）。〔读源码〕
- Astra 缺口：grep splash/ripple 在 weather.glsl 命中的是 astra_rain_ripple（涟漪法线扰动，weather.glsl:76-90、lit.fsh:263-265,362-366），是"水面涟漪"不是"地面亮光斑点"；无 splash 亮度叠加机制。〔实测工具〕
- 落地位置：`Astra/shaders/program/deferred.fsh` 或 lit.fsh 地形分支，复用 weather.glsl 的 astraRainFactor/astra_rain_exposure(skyLight)（weather.glsl:3-10）当 isOutdoors 门控，noisetex 已有。
- 成本：低。后处理/光照 pass 内 1 次噪声采样 + 掩码加法，不新增 pass、不新增 march。帧率收益未验证。
- 许可：MIT（velocity LICENSE 确认 MIT，TheCMK 2026），可代码级。〔读源码〕

### 候选2 天气驱动渐变积雪（Snow Accumulation）
- 通俗原理：下雪时朝上、露天、远离强光源的表面逐渐"积"起一层雪：用面朝上程度+天光衰减+噪声阈值算出积雪量，把反照率混向雪色、压低粗糙度、加细颗粒法线和高度起伏。
- 出处：arc-shader `lib/world/weather.glsl:46-105` ApplySnow（NoU 朝上、accum=2*(0.96875-skyLight) 天光衰减、weatherNoise 噪声阈值、albedo mix 雪色、f0=0.04、dFdx/dFdy 高度法线、hash 细颗粒、smoothness/scattering）；调用 `lib/lighting/pbr_gbuffers.glsl:213-219`（isEyeInWater!=1 且非水/熔岩）；uniform `shaders.properties:295` skySnow=if(biome_precipitation==PPT_SNOW,rainStrength,0)、`:368` biomeSnow、`:371/:394` smooth。〔读源码〕
- Astra 缺口：grep snow 在 glsl 仅 7 文件（scene/grading/wind/volume_fog/settings/uniforms），weather.glsl 有 puddle/wet_ground（:21-75）但无积雪；snow 无 accumulation 实现。〔实测工具〕
- 与排除项关系：SUMMARY-final 排除的是"渐变积雪 Complementary snowyWorld.glsl CLA 1.5 仅思路级"——那是 Complementary 的 CLA 实现。本候选是 arc-shader 的 MIT 实现，可代码级，许可与来源均不同，机制是天气驱动渐变（非 SNOWY_WORLD 全覆盖创作开关）。
- 落地位置：`Astra/shaders/program/lit.fsh` 地形分支，与 puddle/wet_ground 并列（沿用 weather.glsl:21-75 的信号分离模式）；shaders.properties 加 skySnowSmooth/biomeSnowSmooth uniform。
- 成本：中。需 uniform + 地形 material 路由 + 法线/粗糙度修改；无新增 pass。帧率收益未验证。
- 许可：MIT（arc-shader），可代码级。〔读源码〕

### 候选3 程序化熔岩表面（Procedural Lava）
- 通俗原理：不用原版熔岩贴图，改用世界坐标噪声当"压力场"，压力高处温度高、按黑体辐射算出红→黄→白的颜色，压力低处冷却变暗变粗糙，再用高度场扰动法线让表面有流动起伏。
- 出处：arc-shader `lib/world/lava.glsl:26-65` ApplyLavaMaterial（LavaFBM 9 倍频、temp=1000+15000*t、albedo=blackbody(temp)*t*2、smoothness 随温度降、emission=saturate(3t)、dFdx/dFdy 高度法线）；调用 `lib/lighting/pbr_gbuffers.glsl:165`（materialId==BLOCK_LAVA，LAVA_FANCY）。〔读源码〕
- Astra 缺口：lit.fsh:322-327 netherLava 仅色调微调（albedo*=vec3(0.82,1,1)）、:401-406 仅压亮度（color*=0.8/(1+peak*0.18)），无程序化表面；astra_blackbody_rgb 已存在于 end_blackhole.glsl:10 可复用。〔实测工具/读源码〕
- 落地位置：`Astra/shaders/program/lit.fsh` netherLava 分支（:322-327）扩展到全维度熔岩，复用 end_blackhole.glsl:10 astra_blackbody_rgb；block.properties:130 已有 10030=lava 路由。FBM 倍频可从 9 降到 4-5 省成本。
- 成本：中低。逐像素 FBM（可减倍频）+ 黑体色 + 法线扰动，无新增 pass。帧率收益未验证。
- 许可：MIT（arc-shader），可代码级。〔读源码〕

### 候选4 末影水晶晶核发光细分（End Crystal Core Emission）
- 通俗原理：末影水晶只有中间红色晶核该亮，其余玻璃壳保持通透；用颜色检测（红多绿少）判定晶核像素，单独给高发光，而非整颗实体均匀发光。
- 出处：complementary-reimagined `lib/materials/materialHandling/entityIPBR.glsl:6-12`（entityId==50000：lmCoordM.x*=0.7 压方块光、color.g*1.2<color.r 判晶核 → emission=12*color.g、color.r*=1.1）。〔读源码〕
- Astra 缺口：entity.103 名单含 end_crystal（entity.properties:21）→ lit.vsh:113 material=10u 统一发光实体处理，但 lit.fsh ASTRA_ENTITY 分支（:329-332）只做 entityColor 混合，无晶核颜色检测细分。〔实测工具/读源码〕
- 落地位置：`Astra/shaders/program/lit.fsh` ASTRA_ENTITY 分支（:329-332），material==10u 内按 albedo 颜色检测加 emission。
- 成本：低。逐像素颜色比较 + emission，无新增 pass/uniform。帧率收益未验证。
- 许可：CLA（Complementary），仅思路级，需自写实现。〔读源码〕

### 候选5 平面云多重散射相位 + Powder 效应（Cloud Silver Lining）
- 通俗原理：云朝太阳一侧该有明亮"银边"、背光侧该更暗，这不是线性混合能给的；用相位函数（前向瓣+后向瓣）描述光偏向，再用 powder 效应（越厚越吸光、边缘反而透亮）和多次散射迭代让银边和暗部同时成立。
- 出处：photon-shader `include/sky/clouds/common.glsl:57-84`（clouds_phase_single=klein_nishina(2600)+HG(0.8) 前向 max + 0.2*HG(-0.2) 后向；clouds_phase_multi=0.65HG(g.x)+0.10HG(g.y)+0.25HG(-g.z)；clouds_powder_effect=pi*density/(density+0.15) 按 cos_theta mix）；`cumulus.glsl:135-188` clouds_cumulus_scattering（8 次迭代：scatter*=falloff*powder、extinct*=0.4、phase_g*=0.8、powder=sqrt(powder) 逐轮放松）。〔读源码〕
- Astra 缺口：clouds_planar.glsl:496-502 仅 VdotSM2*light 线性 mix + cloudShading，无相位函数/powder/多次散射；grep multi_scatt|psiMS|henyey|silver 在 clouds_planar 0 有效命中（:516 仅注释 moon lobe）。〔实测工具〕
- 落地位置：`Astra/shaders/global/atmosphere/clouds_planar.glsl:496-502` 光照项，把 powder/phase 公式加到现有 2 次密度采样上（不新增 march）。Photon 系数按 AGENTS.md 不直接搬，作公式参考自调。
- 成本：中。逐采样公式改动，march 步数不变。帧率收益未验证。
- 许可：Photon 条件再分发，可研读公式自写实现（非代码级复制）。〔读源码〕

### 候选6 体积雾半分辨率渲染 + 空间滤波（默认开的低成本路径）
- 通俗原理：体积雾逐像素步进很贵，改成在半分辨率的小缓冲上算、再放大贴回全分辨率，配合一次空间滤波抹平放大块状；这是让"默认关闭的步进体积雾"变得可默认开启的直接降本手段。
- 出处：photon-shader `program/c0_vl.fsh:129`（view_texel=gl_FragCoord.xy*taau_render_scale*rcp(VL_RENDER_SCALE)）+ `settings.glsl:310` VL_RENDER_SCALE 0.50；消费 `c14_color_grading.fsh:201-205`（fog_transmittance 从 colortex3，pow(...,BLOOMY_FOG_INTENSITY)）。luster-shaders `program/c1_blend_layers.fsh:229-243`（fog colortex6/7 + FOG_SMOOTHING 空间滤波 include/fog/smoothing.glsl:11）、`settings.glsl:342` VL_RENDER_SCALE 0.50。〔读源码〕
- Astra 缺口：volume_fog.glsl 全分辨率逐像素 march（ASTRA_VOLUME_STEPS 12/24/48，:32-41），VOLUMETRIC_FOG 默认关（settings.glsl:229 //#define VOLUMETRIC_FOG 注释态）；grep temporal|history|reproject 在 volume_fog 0 命中（无时域累积）。〔实测工具〕
- 落地位置：`Astra/shaders/global/atmosphere/volume_fog.glsl` + 新增半分辨率 buffer pass（shaders.properties buffer 配置 + 一个低分辨率 program + 上采样合成）。Astra 已有 CLOUD_TEMPORAL（settings.glsl:120）可参考时域路线，但本候选核心是空间降采样。
- 成本：中高。需额外低分辨率缓冲 + 上采样 pass，但把全分辨率 march 降为 1/4 像素量，是"默认开"的关键。帧率收益未验证（需实机）。
- 许可：Photon 可研读（思路/公式）；luster CLA 禁借代码仅思路。〔读源码〕

### 候选7 天气系统驱动云型演化（温度/湿度/风 → 云参数）
- 通俗原理：云不该只随"下雨/不下雨"变，而该随空气温度、湿度、风缓慢演化：湿度高积云多、温度低卷云多、风大云拉长；这些量再随生物群系（沙漠/雪原/丛林）和时间随机漂移，让云型有地域和时辰差异。
- 出处：photon-shader `include/weather/core.glsl:9-116`（Weather{temperature,humidity,wind}，noise_1d(world_age*speed) 慢随机 + biome_temperature/humidity influence + wetness）；`include/weather/clouds.glsl:118-185` get_clouds_parameters（l0 积云/层云 blend、l1 高积云 coverage、cirrus/cirrocumulus amount、crepuscular_rays_amount 全由 weather 驱动）；uniform `shaders.properties:527-536`（biome_arid/snowy/taiga/jungle/swamp/temperate=smooth(biome_category==CAT_x)、biome_temperature=smooth(temperature*2-1,1000,1000)、biome_humidity=smooth(rainfall*2-1,1000,1000)）。〔读源码〕
- Astra 缺口：grep temperature|humidity 在 Astra 51 命中全是 COLOR_TEMPERATURE/黑体（end_blackhole/end_kerr），无天气温湿度系统；clouds_planar.glsl:111 coverage 仅单 astraRainFactor 项。〔实测工具〕
- 落地位置：`Astra/shaders/shaders.properties` 加 biome_temperature/humidity/biome_category uniform（Astra 已有 biome 检测，shaders.properties:812-816 nether biome 同款写法）+ `clouds_planar.glsl:111` coverage 路由。Astra 是 4 档平面云，可先驱动 coverage/形状随湿度温度变（思路级，不搬 Photon 多层体积云）。
- 成本：中高。需 uniform 体系 + 云参数路由；无新增 pass。帧率收益未验证。
- 许可：Photon 条件再分发，可研读思路自写。〔读源码〕

### 候选8 屏幕雨滴 / 出水镜头水流（Screen Raindrops & Water Exit）【许可风险】
- 通俗原理：下雨时屏幕"镜头"上挂水珠（静止的+向下滑的），出水后屏幕残留水流向下淌并折射画面、带头部高光，入水瞬间有一次性溅屏；用网格分配水珠位置、泪滴形状函数算折射和高光。
- 出处：dercode `program/Post/Final.glsl:564-699` applyLensWater（rainStrength 驱动网格雨滴 RAIN_DROP_COUNT_X/Y、tearDrop:370 形状、static+sliding、出水 WATER_EXIT_STREAMS 锯齿水流+头部高光、入水 enterWater splash）；uniform `shaders.properties:142-144`（exitWater=smooth(inWaterFade)、enterWater=smooth(isEyeInWater==1)）；rainDropShape:829。〔读源码〕
- Astra 缺口：grep droplet|screenRain|screen_rain|rainOnScreen 在 Astra 0 命中；display.fsh:139 isEyeInWater==1 有水下处理但无出水水滴/水流；bubble=0。玩法联动视觉中 Astra 全空白维度。〔实测工具〕
- 落地位置：`Astra/shaders/program/display.fsh`（isEyeInWater 分支 :139 附近）+ exitWater/enterWater uniform（shaders.properties，用 isEyeInWater 平滑）。
- 成本：中。后处理 pass 内网格循环 + 折射采样；雨滴数量可控。帧率收益未验证。
- 许可：⚠ dercode 无 LICENSE 文件（glob 多次 0 命中），默认保留所有权利，仅可思路级参考且需谨慎，不可代码级复制。〔实测工具〕

---

## 查过但判定已有 / 已覆盖 / 已排除（简表）

| 机制 | 出处（文件:行） | 判定理由 |
|---|---|---|
| 发光矿石 GLOWING_ORE | complementary terrainIPBR.glsl:79-82,557,663-746 + blocklightColors.glsl:100,122-131 | 与 batch5"逐像素发光 oreGlowMask(realisticallyoptimized)+HSV 发光(TrueLightFX)"同类；彩色方块光与 SUMMARY-final"方块光颜色表(amethyst)"排除同类 |
| 程序化末地传送门 | complementary endPortalEffect.glsl:1-101 / photon gbuffers_all_solid.fsh:135-165 draw_end_portal | 与 batch5 B11 lumeau prog/block.fsh:44-62（MIT 可代码级）程序化末地传送门同类，已排除 |
| 信标光束着色 | complementary gbuffers_beaconbeam.glsl:70-102 | docs/参考与取舍.md 风格向"信标光束风格"排除；beacon 彩色方块光(lightVoxelization:371+blocklightColors:46)与"方块光颜色表"排除同类 |
| SNOWY_WORLD 全世界覆雪 | complementary snowyWorld.glsl / RV terrainMaterials.glsl:364,1273,1469,1549 | SUMMARY-final"渐变积雪 Complementary CLA 1.5 仅思路级"排除（注：arc MIT 天气驱动渐变积雪是候选2，来源/机制/许可均不同） |
| 生物群系雾散射调色板 | photon weather/fog.glsl:10-110（7 群系 rayleigh 加权） | Astra fog.glsl:235-241 已有 fog_biome_tint 生物群系雾染色，功能已覆盖（实现不同：Photon 改散射系数，Astra 事后颜色 mix） |
| Nether 体积烟 | arc smoke.glsl:21-74 GetVolumetricSmoke + deferred5.fsh:491 | Astra nether_volume.glsl:3-4 已记 Bliss 派生体积烟"Retired C3"退役（无当前 producer），同类替换需用户再裁决，非新候选 |
| 大气多重散射 LUT (Hillaire) | arc hillaire_render.glsl:11-18 + texMultipleScattering TEXTURE_3D | 需切换 Hillaire 预计算大气，与 Astra sky_minishita.glsl 梯度天空架构冲突，成本高 |
| 附魔 glint 增强 | makeup glint_blocks_fragment.glsl:15-20 / complementary gbuffers_hand.glsl:147-150 IRIS_INLINE_GLINT | MakeUp 本地 9.5f glint 无实质增强（仅 texture*tintColor/exposure 归一）；Complementary inline glint 平方增强为 CLA 思路级，且 Astra glint 已走独立 unlit pass（gbuffers_armor_glint.fsh→unlit.fsh）遵循 vanilla |
| 水下气泡柱 | — | 本地包无特殊着色实现：complementary/photon/makeup 仅 block.properties 珊瑚/water mechanics 名单，bubble 0 有效命中，跳过不报 |
| 营火烟特殊着色 | complementary blocklightColors.glsl:67,95 + terrainIPBR.glsl:1995-2037 | 本地包无营火烟专属体积/粒子着色，仅方块光色+材质名单，跳过不报 |
| Photon 曙暮光射线 crepuscular | photon weather/clouds.glsl:175-182 + sky/crepuscular_rays.glsl:26,133-136 | Astra 已有 GODRAYS 体积光（lang/en_US.lang:101-172），功能已覆盖 |

---

## 备注
- 候选1/2/3 许可最干净（MIT 可代码级），缺口明确，成本最低，建议优先。
- 候选5/6/7 是任务点名的云/体积雾机制，Photon 可研读公式但系数按 AGENTS.md 不直接搬。
- 候选8 价值高（Astra 玩法联动全空白）但 dercode 无 LICENSE，仅思路级且需谨慎。
- 所有"帧率收益未验证"均因无实机依据，按硬约束标注。
