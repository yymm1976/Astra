# Astra × 20 款参考光影包调研汇总（SUMMARY）

> 依据：`shader_research/` 下 20 份单包报告（2026-10-02）综合而成。所有 出处/行号/数字 均转引自各报告原文，本文件不新造出处。
> 共识度标记：「N 包印证」= N 份报告独立记载同一技术方向；未标共识度的为单一来源，不代表业界共识。Astra 侧路径相对 `Astra/shaders/`，参考包侧路径相对 `reference_shaderpacks/<slug>/shaders/`（沿用各报告约定）。
> 报告间互相矛盾的结论一律在 ④ 末「矛盾并列」如实并列，不做裁断。

## ① 执行摘要

1. 总结论：Astra 的前向架构、SH9 方向性天光、独立时域历史的水体/云、下界体素彩光与 Kerr 末地天空在 20 款参考包中已属第一梯队，借鉴应统一沿用「读思路 + 独立重写 + 文件头致谢 + THIRD-PARTY.md 台账登记」口径；仅 MIT（Mellow/Miniature）、LGPL（MakeUp）、GPL 家族（Ebin）允许代码级改编。
2. 发现一：共识度最高的是工程件而非算法——CPU 预计算 custom uniform（12 包印证）、程序级 pass 熔断（10 包印证）、PCSS/软阴影采样（7 包印证），均为低风险快赢。
3. 发现二：水体是共识第二密集区——水洼孔隙度响应（7 包）、SSR miss 回退（6 包）、折射二次校验（4 包）、翻转图低配反射（3 包）、水下光束焦散调制（3 包），直指 Astra 核心卖点的补强。
4. 发现三：下界体素光的最大差距在「时域乒乓 + 跨帧累积」（7 包印证）与「体积雾耦合彩光场」（3 包印证）；后处理端 Purkinje（5 包）与复杂自动曝光（5 包）性价比最高，云侧「天空缓存含云行」（6 包）是现有缓存体系的直接增量。
5. 发现四：许可证是硬边界——20 包中 16 包为保留所有权利/自定义专有（其中 Complementary 系 1.3.e「不得附加其它许可」与 Astra 现行致谢模式存在口径冲突），仅 4 包开放代码级借鉴；且 Ebin 包内 LICENSE.md 实为 GPLv3、与外部标注 AGPL-3.0-only 不符，发布前必须确认（见 ③④）。

## ② 主题化借鉴矩阵

### ②-1 阴影与光照

| 借鉴点（技术一句话） | 来源包（共识度） | 代表性包内出处 | 对应 Astra 模块 | 档位 |
|---|---|---|---|---|
| PCSS blocker search 变焦半影（接触硬、远距软） | Photon、Shrimple、Ebin、Bliss、Nostalgia、Kappa、Sildur（7 包印证） | Shrimple `lib/shadows/distorted/render.glsl:140-178,206-208`；Ebin `lib/Fragment/ComputeSunlight.fsh:126-144`；Bliss `dimensions/composite.fsh:481-545` | `global/lighting/shadowmap.glsl`、`diffuse.glsl` | 中期 |
| R2/黄金角旋转盘抖动 PCF | VPS、FastPBR、Shrimple、Solas（4 包印证） | VPS `program/gbuffer/forward.fsh:107-111,154-179`；FastPBR `program/gbuffer/forward.fsh:137-185` | `global/lighting/diffuse.glsl:266-287` | 快赢 |
| 世界单位阴影模糊半径（软度不随影图分辨率漂移） | Shrimple（单源） | `lib/shadows/distorted/render.glsl:122-136` | `global/lighting/diffuse.glsl:277-286` | 快赢 |
| 云影进入 PCSS 半影（阴天大片软影） | Photon（单源） | `include/lighting/shadows/pcss.glsl:246-248` | `global/atmosphere/cloud_shadow_cache.glsl` + 阴影采样 | 快赢 |
| 云影缓存湿天联动与太阳高度淡出 | Kappa（单源） | `world0/prepare2.fsh:591-597` | `global/atmosphere/cloud_shadow_cache.glsl` 写入端 | 快赢 |
| 云影与云密度严格同源（影子=天上的云） | BSL、Solas、Photon（3 包印证） | BSL `lib/lighting/shadows.glsl:295-375`；Solas `lib/lighting/cloudShadows.glsl`（`volumetrics.glsl:236-244` 调用） | `program/cloud_shadow_cache.fsh` + `global/atmosphere/clouds_planar.glsl` | 中期 |
| 彩色阴影雨天自动关闭 | Solas（单源） | `lib/lighting/shadows.glsl:23-26` | `global/lighting/shadowmap.glsl` | 快赢 |
| 像素化阴影风格档 | Mellow、Miniature、Complementary（3 包印证） | Mellow `global/lighting/shadows.glsl:63-73`；Miniature `common/getLightStrength.fsh:11-15` | `global/lighting/shadowmap.glsl` + `lib/settings.glsl` | 快赢 |
| 屏幕空间接触阴影 | VPS、Nostalgia、Shrimple、Kappa（4 包印证） | VPS `lib/light/contactShadow.glsl:47-90`；Shrimple `program/deferred_shadow_opaque.fsh:264-349` | `global/lighting/shadowmap.glsl`（前向落点需设计） | 长期 |
| 手持光连续衰减 + 玩家中心光心 + 源头封顶 | Hysteria、Insanity、BSL（3 包印证） | Hysteria `include/light/handheld_lighting.glsl:31-45`；Insanity `program/gbuffers_terrain.glsl:186-190`（0.9333 封顶） | `global/lighting/blocklight.glsl:62-70` | 快赢 |
| 方块光陡峭/三段衰减曲线 | Hysteria、Insanity（BSL 族）（2 包印证） | Hysteria `include/light/diffuse_lighting.glsl:30-39`；Insanity `lib/lighting/forwardLighting.glsl:45-46` | `global/lighting/blocklight.glsl:89-90` | 快赢 |
| 暗处去饱和驱动量计入阴影覆盖率 | Insanity、Ebin（2 包印证） | Insanity `lib/lighting/forwardLighting.glsl:75-108`；Ebin `lib/Fragment/ComputeShadedFragment.fsh:194-198` | `global/lighting/diffuse.glsl:240`（night_desaturation） | 快赢 |
| eBS（玩家天光暴露）暗适应统一乘子 | Insanity、BSL（2 包印证） | Insanity `lib/atmospherics/fog.glsl:50`；BSL `lib/atmospherics/sky.glsl:64-67` | `global/lighting/diffuse.glsl` + `global/atmosphere/fog.glsl` | 中期 |
| IPBR 自发光启发式（矿石/光源亮度提取） | Complementary、Miniature（2 包印证） | Complementary `lib/materials/materialHandling/terrainIPBR.glsl:79-82`；Miniature `program/textured_lit.fsh:87-93` | `lib/surface_emission.glsl` + `block.properties` | 快赢 |
| IPBR 程序化生成法线（无资源包凹凸） | Complementary、Solas、SDV（3 包印证） | Complementary `lib/materials/materialMethods/generatedNormals.glsl:10-55`；SDV `lib/PBR/integratedPBR.glsl:19-39` | `program/lit.vsh/.fsh` | 中期 |
| GriAndEmin 防漏光偏置 | Bliss（单源；Photon 同款注明经许可借用 `pcss.glsl:201-205`） | Bliss `lib/Shadows.glsl:1-25` | `global/lighting/shadowmap.glsl` | 中期 |
| SSRT 阴影距离外屏幕空间接力 | Photon（单源） | `include/lighting/shadows/ssrt.glsl:10-33` | `global/lighting/shadowmap.glsl` | 长期 |
| RSM GI（阴影图直接采通量/深度/法线） | Ebin（单源，GPL 可改编） | `lib/Fragment/ComputeGI.fsh:51-80` | 新子系统（Astra 无 GI） | 长期 |

### ②-2 水体

| 借鉴点 | 来源包（共识度） | 代表性包内出处 | 对应 Astra 模块 | 档位 |
|---|---|---|---|---|
| 水洼掩码 + 孔隙度材质响应（分层暗化/涟漪） | BSL、Hysteria、Photon、Nostalgia、Kappa、Sildur、Shrimple（7 包印证） | BSL `lib/reflections/rainPuddles.glsl:1-23,78-86`；Hysteria `include/misc/rain_puddles.glsl:38-57` | `lib/wet_material.glsl` + `global/atmosphere/weather.glsl` | 中期 |
| 室内/洞内积水排除门（blocklight+skylight 门控） | Hysteria、BSL（2 包印证） | Hysteria `include/misc/rain_puddles.glsl:23` | `global/atmosphere/weather.glsl:67` | 快赢 |
| SSR miss 回退（天空缓存/历史帧/场景 capture） | Photon、VPS、Kappa、FastPBR、Sildur、SDV（6 包印证） | Photon `include/lighting/specular_lighting.glsl:250-256`；FastPBR `world0/composite3.fsh:223-225` | `global/water/raytrace.glsl` + `lib/sky_reflection_cache.glsl` | 中期 |
| SSR 行进效率细节（边界预裁剪/自适应步长/相对深度阈值/首步抖动） | VPS、Miniature、Sildur（3 包印证） | VPS `lib/frag/reflection.glsl:229-231,240-257,246`；Miniature `common/getReflectionColor.fsh:33-35,60` | `global/water/raytrace.glsl:46-111` | 快赢 |
| 翻转图单次投影反射（低配档/miss 填缝） | Complementary、MakeUp、Mellow（3 包印证） | MakeUp `lib/water.glsl:176-198`；Mellow `global/water.glsl:41-66` | `global/water/raytrace.glsl` + settings 枚举 | 快赢 |
| 折射二次校验 + 深度差限幅 | Complementary、Photon、Hysteria、Nostalgia（4 包印证） | Complementary `lib/materials/materialMethods/refraction.glsl:25-42`；Photon `program/c1_blend_layers.fsh:290-304` | `global/water/refraction.glsl` | 快赢 |
| 岸线泡沫（深度差 + 噪声阈值） | Complementary、SDV、Shrimple（3 包印证） | Complementary `lib/materials/specificMaterials/translucents/water.glsl:211-248`；SDV `main/gbuffers/gbuffers_water.glsl:250,280-282` | `global/water/surface.glsl` | 中期 |
| Gerstner 色散波 + 高度变化调幅 | Photon、Kappa（2 包印证） | Photon `include/surface/water_normal.glsl:16-77`；Kappa `lib/atmos/waterWaves.glsl:49-127` | `lib/solas_water.glsl`（与焦散高度场联动） | 中期 |
| 雨天波幅耦合 | Solas（单源） | `lib/water/waterNormals.glsl:26-30` | `global/water/caustics.glsl` 幅值项 | 快赢 |
| 分通道水下吸收 + 可调指数 | Solas（单源） | `lib/water/waterFog.glsl:2-6,8-9` | `global/water/absorption.glsl`、`lib/solas_water.glsl:83-90` | 中期 |
| Snell's window（水下透光孔） | Bliss、Hysteria、Solas、Shrimple（4 包印证） | Bliss `dimensions/all_translucent.fsh:772-774`；Solas `shaders/programs/gbuffers_water.glsl:268-272` | `global/water/optics.glsl` / `surface.glsl` | 快赢 |
| 水下光束焦散调制 | Bliss、Shrimple、Photon（3 包印证） | Shrimple `lib/fog/fog_volume.glsl:388-397`；Bliss `dimensions/composite2.fsh:303` | `global/water/light_shafts.glsl:57-74` | 快赢 |
| 水下 UV 扭曲 + 雾色偏（水下视觉链） | Unbound、Insanity、SDV、Sildur（4 包印证） | Unbound `program/final.glsl:95-98`、`lib/common.glsl:790,799`；Sildur `final.fsh:259-263` | `program/final.fsh` + `global/water/absorption.glsl` | 快赢 |
| 焦散深度双淡出 + 地面阴影调制 | Sildur（单源） | `gbuffers_water.fsh:406-429` | `global/water/caustics.glsl` 消费端 | 中期 |
| 多层水体深度介质切换 | Shrimple（单源） | `lib/water/water_depths_write/read.glsl` | `lib/water_buffer_formats.glsl` / `medium_state.glsl` | 长期 |

### ②-3 大气与云

| 借鉴点 | 来源包（共识度） | 代表性包内出处 | 对应 Astra 模块 | 档位 |
|---|---|---|---|---|
| 天空缓存增烘「含云行/含雾区」（云阴影可入 alpha） | Bliss、VPS、Kappa、Nostalgia、Sildur、FastPBR（6 包印证） | VPS `program/deferred/skyboxPrep.fsh:250-270`；Nostalgia `program/deferred/skyboxPrep.fsh:306-327`；Bliss `dimensions/deferred.fsh:246-297` | `lib/sky_reflection_cache.glsl` + `program/sky_reflection_cache.fsh` | 快赢 |
| 逐日天气系统（滑条档/湿温风状态机） | Bliss、Kappa、Photon、Nostalgia（4 包印证） | Bliss `shaders.properties:367-380`（DAY0-DAY9）；Kappa `shaders.properties:353-398` | `global/atmosphere/weather.glsl` + shaders.properties | 中期 |
| 云时间上采样（棋盘 4×/checkerboard） | Photon、Hysteria、Kappa（3 包印证） | Photon `program/d2_clouds_upscaling.fsh:157-179,302-350`；Hysteria `shaders/settings.glsl:147` | `program/cloud_screen.fsh` + `cloud_temporal.glsl` | 中期 |
| 云动画绑定世界时间（worldAnimTime/TIMELAPSE） | Kappa、VPS、Nostalgia、FastPBR、SDV（5 包印证） | Kappa `shaders.properties:218`；SDV `shaders.properties:390-405` | `lib/uniforms.glsl` + `clouds_planar.glsl` | 快赢 |
| 体积云多重散射能量估计（储备） | Kappa、Photon、VPS、Bliss（4 包印证） | Kappa `world0/deferred.fsh:274-307`；Photon `include/sky/clouds/cumulus.glsl:164-186` | 无（Astra 为平面云） | 长期 |
| 极光系统（kpIndex 叙事/体积化/造型） | Solas、Mellow、BSL、Complementary（4 包印证） | Solas `lib/atmosphere/aurora.glsl:62` + `planarClouds.glsl:73-108`；Mellow `global/atmosphere/sky.glsl:88-124` | `global/atmosphere/` 新模块 | 中期 |
| 月相支持 | Complementary、Sildur（2 包印证，侧重不同：光照联动 vs 月盘减影绘制） | Complementary `lib/common.glsl:267-272`；Sildur `deferred.fsh:182-229` | 光照管线 + `global/atmosphere/` | 中期 |
| 雾色与天空输出同源 | Sildur、Complementary、MakeUp（3 包印证） | Sildur `deferred.fsh:782-785`；Complementary `lib/atmospherics/fog/mainFog.glsl:45-50`；MakeUp `common/prepare_fragment.glsl:45-53` | `global/atmosphere/fog.glsl` | 中期 |
| Chapman/解析透射率兜底函数 | Photon、FastPBR（2 包印证） | Photon `include/sky/atmosphere.glsl:492-522`；FastPBR `lib/atmos/air/density.glsl:5-14` | `global/atmosphere/fog.glsl`、`lib/twilight.glsl` | 中期 |
| 体雾非均匀步长（pow(t,k) 相机侧加密） | Shrimple、Complementary、Solas（3 包印证） | Shrimple `lib/fog/fog_volume.glsl:154-171`；Solas `lib/atmosphere/volumetrics.glsl:192-194` | `global/atmosphere/volume_fog.glsl` | 快赢 |
| 雾/云步数随穿越距离自适应 | Nostalgia、Kappa、Hysteria、FastPBR、VPS、Unbound（6 包印证） | Nostalgia `world0/composite1.fsh:265-271`；Kappa `world0/deferred.fsh:201-207` | `global/atmosphere/volume_fog.glsl:11-30` | 中期 |
| 雨天阴影衰减必配天光补偿（防死黑配对） | SDV（单源） | `lib/lighting/complexShadingForward.glsl:120-126` | `global/lighting/shadowmap.glsl` + `diffuse.glsl` | 快赢 |

### ②-4 下界与体素光

| 借鉴点 | 来源包（共识度） | 代表性包内出处 | 对应 Astra 模块 | 档位 |
|---|---|---|---|---|
| 体积雾耦合体素彩光场（岩浆湖彩色光柱） | RV、Unbound、Solas（3 包印证） | Unbound `lib/atmospherics/fog/coloredLightFog.glsl:1-52`；RV `volumetricBlocklight.glsl:81-83`、`coloredLightFog.glsl:1-56` | `global/dimension/nether_volume.glsl` in-scatter 项 | 快赢 |
| 体素场时域乒乓 + 相机搬移 + 跨帧累积 | BSL、Ebin、Bliss、Solas、Mellow、Photon、RV（7 包印证） | Ebin `program/shadowcomp.glsl:53-93`（双缓冲+0.99）；BSL `program/shadowcomp.glsl:108`（相机位移补偿）；RV `shadowcomp1.glsl:31-50` | `program/nether_light.csh`、`lib/nether_voxel_grid.glsl` | 中期 |
| 主世界彩光推广（floodfill 三维度统一） | Ebin、BSL、Photon、Mellow、Complementary（5 包印证；Mellow 报告明确不建议直接搬，见④-l） | Ebin `shaders.properties:97-99`；Complementary `shaders.properties:163-191`（ACT 七档） | `program/nether_light.csh` 扩展 | 长期 |
| SDF 多分辨率距离场 + 光源 coneTrace 软阴影 | RV（单源） | `shadowcomp_sdf_loop.glsl:66-78`、`voxelReading.glsl:65-108` | `program/nether_light.csh` 新段 | 长期 |
| 逐像素光源列表 + GGX 彩光高光 | RV（单源） | `prepare4_csh.glsl:5-18,372,398-410` | `global/dimension/nether_colored_light.glsl` | 长期 |
| 光源亚体素中心（非格点亮源） | RV、Ebin（2 包印证） | RV `program/shadow.glsl:483-499` + `final.glsl:146-155`；Ebin `program/gbuffers_shadow.glsl:171-185` | `program/shadow.vsh:47-84` | 中期 |
| 半透明体彩光染色 + 体积外平滑退路/log 压缩 | RV（单源） | `voxelReading.glsl:91-99`；`mainLighting.glsl:86,550-554` | `program/nether_light.csh` + `nether_colored_light.glsl` | 中期 |
| 下界风暴/烟羽体积层 | Complementary、RV、Bliss、Solas（4 包印证） | Complementary `lib/atmospherics/netherStorm.glsl:1-22`；Bliss `lib/nether_fog.glsl:20-30` | `global/dimension/nether_volume.glsl`、`lib/nether_fog_density.glsl` | 中期 |
| 下界群系 smooth uniform 平滑过渡 | Complementary、BSL、Insanity、Ebin、Kappa（5 包印证） | Complementary `shaders.properties:266-270`；Ebin `shaders.properties:84-94` | `lib/uniforms.glsl` + `global/dimension/nether.glsl` | 快赢 |

### ②-5 后处理与调色

| 借鉴点 | 来源包（共识度） | 代表性包内出处 | 对应 Astra 模块 | 档位 |
|---|---|---|---|---|
| TAA pixel-age 等权收敛 | Photon（单源） | `program/c4_taa_exposure.fsh:306-311` | `program/taa_resolve.fsh` | 快赢 |
| TAA offcenter rejection | Photon、Kappa、Mellow（3 包印证） | Kappa `program/post/temporal.fsh:311`；Mellow `global/post/taa.glsl:142-147` | `program/taa_resolve.fsh` | 快赢 |
| TAA 最近深度锚点重投影 | Photon、Sildur、Mellow、FastPBR（4 包印证） | Photon `program/c4_taa_exposure.fsh:104-125`；Mellow `global/post/taa.glsl:62-73` | `program/taa_resolve.fsh` | 中期 |
| TAA 色相角拒绝 + 曝光不变历史编码 | Nostalgia（单源） | `program/post/temporal.fsh:133-151,393-400` | `lib/taa_state.glsl` + `global/post/exposure.glsl` | 中期 |
| TAA Catmull-Rom 历史采样 | BSL、Solas、Complementary(Unbound)、Shrimple、Sildur、Mellow、Kappa（7 包印证） | Shrimple `lib/effects/taa.glsl:58`；Sildur `composite2.fsh:119-141` | `program/taa_resolve.fsh`（Astra 现状先核实） | 中期 |
| Purkinje 夜视蓝移 | Mellow、Bliss、Photon、Nostalgia、Kappa（5 包印证） | Mellow `lib/tonemap.glsl:69-79`；Bliss `dimensions/composite11.fsh:147-161` | `global/post/grading.glsl` / `lib/tonemap.glsl` | 快赢 |
| rod exposure 视杆曝光通道 | Bliss（单源） | `dimensions/deferred.vsh:253-264` | `global/post/exposure.glsl` | 快赢 |
| 复杂自动曝光（加权 tile + 明暗百分位钳制） | Nostalgia、Kappa、FastPBR、Photon、Bliss（5 包印证） | Nostalgia `program/grade/exposure.vsh:42-135`；FastPBR `program/grade/exposure.vsh:38-75` | `global/post/exposure.glsl:82-92` | 中期 |
| 局部曝光 | Nostalgia、Kappa（2 包印证） | Nostalgia `program/grade/grading.fsh:286-305` | `global/post/grading.glsl` | 长期 |
| Bloom 瓦片法/对比度整形（Ebin 为 GPL 可改编替代） | Ebin、Solas、Complementary、BSL、Bliss、Nostalgia（6 包印证） | Ebin `program/composite3.glsl:54-102`（GPL）；Solas `lib/post/getBloom.glsl:5,19-26` | `global/post/bloom.glsl`（现挂 Refrax REWRITE REQUIRED） | 快赢 |
| mipmap 单 pass Bloom 低配档 | MakeUp（单源） | `lib/bloom.glsl:7-34` | `global/post/bloom.glsl` | 中期 |
| ACES 参数面补全（AMPAS 原版许可可用） | Nostalgia、Kappa、Photon（3 包印证） | Nostalgia `lib/academy/aces.glsl:20-49`；Kappa `program/grade/grading.fsh:91` | `lib/tonemap.glsl:176` | 中期 |
| tonemap 三段风格化（暗部抬升/白路径/暗部去饱和） | Unbound（单源） | `program/composite5.glsl:66-88` | `lib/tonemap.glsl` + `global/post/grading.glsl` | 快赢 |
| BSL 三段式 tonemap（去饱和→映射→再饱和） | BSL（单源） | `program/composite5.glsl:233-260` | `lib/tonemap.glsl` | 中期 |
| 保亮度三区调色（加法偏移 + 亮度守恒） | Mellow（单源） | `program/final.fsh:457-467` | `global/post/grading.glsl`（LOOK_*） | 快赢 |

### ②-6 性能与低配档

| 借鉴点 | 来源包（共识度） | 代表性包内出处 | 对应 Astra 模块 | 档位 |
|---|---|---|---|---|
| 程序级 pass 熔断（program.*.enabled 布尔组合） | Complementary、Mellow、VPS、Sildur、Insanity、BSL、Nostalgia、Kappa、Solas、Ebin（10 包印证） | Complementary `shaders.properties:99-113`；Sildur `shaders.properties:9-13` | `shaders.properties`（GODRAYS/VOLUME_FOG/SSR 关闭时禁 pass） | 快赢 |
| CPU 预计算 custom uniform（dayMixer/抖动表/雾密度） | MakeUp、Mellow、SDV、Insanity、BSL、Complementary、Kappa、VPS、Nostalgia、FastPBR、Solas、Ebin（12 包印证） | MakeUp `shaders.properties:89-228`；SDV `shaders.properties:439-446` | `lib/uniforms.glsl`、`lib/taa_jitter.glsl`、shaders.properties | 快赢 |
| TAAU/渲染缩放正交旋钮 | Photon、Nostalgia、Hysteria、FastPBR、Kappa、Bliss（6 包印证） | Hysteria `shaders/settings.glsl:412` + `shaders.properties:1-2`（0.50/0.66）；Kappa `lib/internal.glsl:26` | 全 pass uv 缩放（Astra 现无） | 长期 |
| 假阴影兜底（NO_SHADOWS 档 visibleSky 幂衰减） | MakeUp（单源） | `src/light_vertex.glsl:115-129` | `lib/settings.glsl` + `global/lighting/diffuse.glsl` | 快赢 |
| depth-only 4-tap godrays 低档 | MakeUp（单源） | `lib/volumetric_light.glsl:99-115` | `global/post/godrays.glsl` | 快赢 |
| 前向雾完全雾化 discard | Miniature（单源） | `program/textured_lit.fsh:60-62` | `program/lit.fsh` | 快赢 |
| 实体阴影三档剔除 + 20% 距离 | Miniature（单源；Astra 是否缺该项未核实，见④-g） | `shaders.properties:26-38` + `shader.h:35` | `shaders.properties` + `lib/settings.glsl:339-359` | 快赢 |
| 顶点 hash 水波低档 | Miniature（单源） | `common/getWaterWave.vsh:1-12` | `program/water.glsl` / `lit.fsh:125` | 快赢 |
| 云图视差云低档（无 3D 噪声/无历史） | SDV（单源） | `lib/rayTracing/volumetricClouds.glsl:7-57` | `global/atmosphere/clouds_planar.glsl` 低档 | 中期 |
| 半分辨率反射缓冲 | Complementary（单源） | `shaders.properties:118-122` | `lib/water_buffer_formats.glsl` | 中期 |
| USE_LQ_DEPTH 1/4 深度统一消费 | Mellow（单源） | `program/deferred.fsh:328` | SSR/SSAO/体积雾深度读取 | 长期 |
| Iris 特性协商降级（optional features + 回退） | Complementary、Miniature、Hysteria、Shrimple（4 包印证） | Complementary `shaders.properties:116-122`；Shrimple `lib/shadows/distorted/render.glsl:53-61` | `shaders.properties`（按需） | 中期 |
| profile 增量式/链式定义（防漏改） | Kappa、VPS、Miniature、Ebin（4 包印证） | Kappa `shaders.properties:5-9`；Miniature `shaders.properties:1-4` | `shaders.properties:424-427`（现为全量枚举） | 快赢 |
| 「贵而低感知默认关」默认值审计 | Sildur、Unbound（2 包印证） | Sildur `shaders.settings:72-126`；Unbound `lib/common.glsl:147-155` | `lib/settings.glsl` 各默认值 | 快赢 |

### ②-7 工程组织与设置系统

| 借鉴点 | 来源包（共识度） | 代表性包内出处 | 对应 Astra 模块 | 档位 |
|---|---|---|---|---|
| world 薄壳 + 共享 program 源（Astra 已同构，方向印证） | BSL、Mellow、Ebin、Solas、Bliss、Miniature（6 包印证） | Ebin `shaders/world0/composite2.fsh:1-7`；Mellow `world0/deferred.fsh:1-4` | `world-1/`、`world1/` 现有结构 | 快赢（仅需维持） |
| dimension.properties 模组维度兜底（world_modded=*） | Mellow（单源） | `dimension.properties:4` | Astra 根目录 + world-1/world1 | 快赢 |
| 空 #ifdef 保选项技巧 | Mellow（单源） | `lib/settings.glsl:346-399` | `lib/settings.glsl` | 快赢 |
| DONTOPTIMIZE 防发布脚本优化 const | Mellow（单源） | `lib/settings.glsl:273-276` | 发布流程 | 快赢 |
| lang 注释统一带性能开销标注 | Mellow（单源） | `lang/en_US.lang:2` | `shaders/lang/` | 快赢 |
| RGBE8 打包直射光×阴影供合成段复用 | FastPBR（单源） | `program/gbuffer/forward.fsh:187-195` | 水面太阳高光链路（新缓冲） | 中期 |
| 调试 Showbuffer 视图 | Sildur（单源） | `shaders.settings:131` + `final.fsh:278-298` | `program/`（开发用） | 中期 |
| 「思想来源」登记纪律（文件头 + THIRD-PARTY.md 台账） | Bliss、BSL、Solas、Sildur、Kappa、VPS 等 ⑤ 节一致建议 | Bliss ⑤：重写后仍登记「思想来源：Bliss 2.1.2」 | `Astra/THIRD-PARTY.md` + 各文件头 | 快赢（流程既有，持续执行） |
| 光色顶点阶段 flat varying 下沉 | Mellow（单源；报告明确不建议整体搬，仅借「关键帧权重下沉 CPU」） | `global/lighting/light_colors.vsh:1-9` | `global/lighting/diffuse.glsl` | 长期 |

### ②-8 可选风格页

| 借鉴点 | 来源包（共识度） | 代表性包内出处 | 对应 Astra 模块 | 档位 |
|---|---|---|---|---|
| 位深量化抖动（复古色阶） | Nostalgia、Insanity、FastPBR（3 包印证） | Nostalgia `program/grade/final.fsh:38-53`；Insanity `program/composite5.glsl:235-238` + `final.glsl:69-72` | `global/post/grading.glsl:218` + `lib/bayer.glsl` | 快赢 |
| 胶片模拟曲线（HDR 段 toe/滚降） | Nostalgia（单源） | `program/grade/grading.fsh:346-376` | `lib/tonemap.glsl`（apply_tonemap 前加槽） | 中期 |
| 老式解析镜头光晕（默认关） | Unbound、BSL、Solas、Sildur（4 包印证；Nostalgia 的 BSL 系 flare 版权风险高，排除） | Unbound `lib/misc/lensFlare.glsl:58-126`；Sildur `composite1.fsh:180-603` | `program/final.fsh`（风格页开关） | 中期 |
| 远景光斑 bokeh | Unbound（单源） | `lib/misc/distantLightBokeh.glsl:1-27` | `lib/surface_emission.glsl` + gbuffers | 中期 |
| 亮度补偿暗角 | Unbound、Insanity（2 包印证） | Unbound `program/final.glsl:155-159`；Insanity `program/composite5.glsl:283-285` | `global/post/grading.glsl:189`（apply_vignette） | 快赢 |
| 滤镜层解耦骨架（风格页 v0：一开关 + program 门控 + 后处理 only） | Insanity（单源） | `shaders.properties:44,125-130` + `lib/settings.glsl:372-375` | `global/post/grading.glsl` + `shaders.properties` | 中期 |
| 三关键帧调色覆盖层（日/夜/暮菜单微调） | SDV（单源） | `world0/world.glsl:49-101` | `global/post/grading.glsl` + `lib/colors.glsl` | 中期 |
| 信息性发光倍率（类别化 emissive 系数） | Insanity（单源，机制可借、恐怖用法不可借） | `program/gbuffers_spidereyes.glsl:26`、`gbuffers_beaconbeam.glsl:37` | `lib/surface_emission.glsl` | 长期 |

## ③ 许可证红线表

判定均以各报告 ①⑤ 节为准。

| 包 | 许可证实况 | 能否抄代码 | 义务 / 红线 |
|---|---|---|---|
| complementary-reimagined | Complementary License Agreement 1.7（License.txt:1，自定义非 OSI） | 不能（整段搬运即成 Modified Pack） | 改编须：署名+官网链接、原样保留并随更新同步 License.txt、改名（不得含 Complementary、≥3 字母差异）、视觉显著不同、不得附加其它许可（1.3.e，License.txt:77-79）、显著人写增量；读思路+独立重写无障碍 |
| complementary-unbound | 同上 CLA 1.7 | 不能 | 同上；1.3.e 与 Astra 自有第三方声明体系直接冲突（见④-a） |
| bsl-shaders | 保留所有权利；包内无 LICENSE/授权文件 | 不能 | 仅思路/公式/参数方向级借鉴；选项命名与噪声纹理（tex/noise.png）也不可照搬 |
| photon-shader | 自定义许可（P:LICENSE:1-18）：明确允许查阅学习（:10）；在收益平台（Modrinth/CurseForge）再分发需书面许可（:12） | 抄代码高风险（或成衍生作品+触发平台条款） | 独立重写可行；搬运需 SixthSurge 书面许可；其借自 Complementary 的片段注明 "used with permission"（pcss.glsl:201-205） |
| solas-shader | 包内无 LICENSE，按默认版权保留所有权利；Astra THIRD-PARTY.md:28 已登记 V2.2b「未声明（默认版权）」 | 不能 | 思路级 + 登记 + 发布前重写；把 3.7b 新代码 include 进 Astra V2.2b 血统文件同样需授权 |
| bliss-shader | Chocapic13 条款（LICENSE.md:1-6）：不得声称代码为自己的；衍生须命名 "(Chocapic13' Shaders edit)"；署名；禁变现链接；个别第三方 MIT 片段 | 不能 | 重写后仍应登记「思想来源：Bliss 2.1.2」（④-m）；MIT 头片段可单独取用但须保留许可头 |
| rethinking-voxels | Complementary License Agreement 1.5 | 不能 | 同 Complementary 系义务；`positionHashing.glsl:1-8` 为 CC-BY-SA 4.0，连用需署名或自写哈希 |
| makeup-ultra-fast-shaders | LGPL-3.0-or-later（LICENSE:1-2）；README 另有口头放宽（非许可条款） | 能 | 保留版权与许可声明、声明修改、随包附 LGPL 文本；LGPLv3 §4 允许并入后整体按 GPL-3.0 分发；是否并入 SC-14 发布门待决（④-e） |
| super-duper-vanilla | FlameRender Studios License v1.6（专有）；修改版再分发须整体改用同许可+改名+署名（1.4）；仅调数值不构成修改版（0.6.a） | 不能 | 与 Astra GPLv3（Steadfast 派生 shadowmap）直接冲突：GPL 代码无法并入专有修改版（④-f）；云图/噪声贴图资源同样不可拷贝 |
| mellow | MIT（LICENSE:1-9，(c) 2026 TheCMK） | 能 | 保留版权与 MIT 文本；文件头 Immediate source 注释 + THIRD-PARTY.md 登记；注意逐文件中继（tonemap_operators.glsl 内嵌 Seguin MIT/BakingLab；PBRNeutral 为 Apache-2.0，Astra 不引入）；不用 Mellow 名字与素材（礼貌请求）；GPLv3 模块内容不得流入纯 MIT 新文件 |
| miniature-shader | MIT（任务给定 + Modrinth 登记；包内无 LICENSE 文件） | 能 | 保留声明即可；建议落独立小文件避免与 GPL 派生文件混同；最终许可文本需统帅补一次确认（报告⑤风险点） |
| nostalgia-shader | 保留所有权利自定义许可（LICENSE:1-2，文件头 DMCA 声明） | 不能；例外：`lib/academy/` ACES 为 AMPAS 许可可改写 | 仅思路级；AMPAS 组件须保留其版权与许可文本；`lib/frag/bslflare.glsl`（BSL 系第三方）排除 |
| hysteria-shaders | AGNYA License Rev 1.3（LICENSE.md:3）：私有修改允许（§2）；公开分发修改版需许可（§3）；部分源码用作另一原创项目需许可+署名+禁变现（§4） | 不能（其 Photon 来源部分为 MIT） | 需同类代码优先从 Photon 上游取 MIT 版本（④-o）；Astra 公开分发含其派生内容还须遵守「不得更换许可证、禁止变现」 |
| kappa-shader | 保留所有权利（LICENSE:1-2）；§4 同 Hysteria（部分源码用于另一项目需许可） | 不能 | 思路级借鉴；物理常数等公有事实可独立使用 |
| vanilla-plus-shader | 保留所有权利（LICENSE:2；§4=LICENSE:75-78） | 不能 | 思路级；R2/VNDF/介电 Fresnel 按公开论文原始出处实现；包内 BSL/Spectrum 第三方代码同样受限；作者归属矛盾见④-矛4 |
| shrimple | All Rights Reserved（LICENSE:1-3），无任何授权条款 | 不能 | 源码/贴图（caustics.dat 等）/lang/properties 均不可复制；思想级独立实现 |
| fastpbr | 自定义版权协议（LICENSE:1-2）；§4 部分源码用作另一项目需许可+署名+禁商业化 | 不能 | 思路级；报告摘录均 ≤5 行研究性引用 |
| insanity-shader | 包内无 LICENSE 文件；合法性仅系于 credits.txt:5-8 的 Capt Tatsu 个人授权，不向第三方传导 | 不能 | 最保守解读：只按报告行为描述重写，不打开源码复制；新增实现文件头不署名 Insanity/BSL |
| ebin-resurrected | 包内 LICENSE.md:1-4 为 GPLv3 全文（与外部标注 AGPL-3.0-only 不符，见④-j）；GPL 家族强 copyleft | 能 | 随包提供许可文本+版权声明+标注修改；照 Steadfast 先例做文件头+THIRD-PARTY.md 登记；`lightColors.glsl` 配色取自 Complementary（专有）不得连搬 |
| sildurs-vibrant-shaders | 保留所有权利（shaders.settings:8-11 明文禁止未授权再分发/修改/镜像） | 不能 | 禁止任何代码级搬运含「换名照抄」；思路级黑盒参考并在模块头注明 |

## ④ 存疑与待核实清单

### ④-1 统帅移交待处置项（逐条保留原出处；只汇编不决策）

| # | 事项 | 出处报告 | 建议核实方式 |
|---|---|---|---|
| a | Complementary 条款 1.3.e「改编不得附加其它许可条款」与 Astra 现有「文件头致谢+THIRD-PARTY.md」模式的口径冲突 | complementary-reimagined.md（①⑤）、complementary-unbound.md（⑤） | 统帅决策是否统一 THIRD-PARTY 口径；对照两包 License.txt:58-80/77-79 原文 |
| b | Astra TAA 是否含 YCoCg AABB 裁剪未核实 | bsl-shaders.md（②④） | 读 `program/taa_resolve.fsh:109-118`；注意 photon-shader.md ④ 已给出相反证据（见矛1） |
| c | Astra 云影缓存与 clouds_planar 密度场是否已同源未核实 | bsl-shaders.md（③-3） | 对照 `program/cloud_shadow_cache.fsh` 与 `global/atmosphere/clouds_planar.glsl` 的噪声函数 |
| d | Astra nether_volume 体积 march 是否已在别处采样彩光场未核实 | rethinking-voxels.md（④） | 通读 `global/dimension/nether_volume.glsl` 全文（报告仅核对了前 40 行） |
| e | MakeUp（LGPL）代码借用是否并入 SC-14 发布门统一决策 | makeup-ultra-fast-shaders.md（⑤） | 统帅决策项 |
| f | SDV 专有条款与 Astra 现有 GPLv3 来源（Steadfast 派生 shadowmap）的冲突 | super-duper-vanilla.md（④⑤） | 确认 shadowmap.glsl GPLv3 头与 FlameRender 1.4 条款互斥后只做思想级借鉴 |
| g | Astra shaders.properties 是否确实缺 shadowEntities/shadowPlayer 程序级开关 | miniature-shader.md（③-6、④） | grep 全部 shaders.properties 与 lib/settings.glsl（原报告仅单次 grep 非穷尽） |
| h | Astra aces_tonemap 疑似 Narkowicz 拟合而非 AMPAS 原版 | nostalgia-shader.md（④） | 读 `lib/tonemap.glsl:170-176`（rrt_and_odt_fit 命名一致）确认后再按其 Top5-3 补参数面 |
| i | Hysteria 报告对 Astra f0/反射调制是否存在于 water 模块未核对 | hysteria-shaders.md（④-c） | 检索 `global/water/` 与 `lib/wet_material.glsl` 的 f0 写入路径 |
| j | Ebin 包内 LICENSE.md 为 GPLv3 全文，与 Modrinth 标注 AGPL-3.0-only 不符 | ebin-resurrected.md（①⑤） | 发布前向上游/Modrinth 页面确认真实许可；静态分发下两者义务实践等价 |
| k | Insanity 包内无 LICENSE 文件，结论基于 credits.txt 口头授权+上游 BSL 许可的最保守解读 | insanity-shader.md（①⑤） | 如需文本级复用，先取 Capt Tatsu 书面许可 |
| l | Mellow 报告将「顶点光色管线、主世界体素彩光」列为明确不建议直接搬 | mellow.md（③6/③7、⑥） | 作为约束保留；仅当用户明确要主世界彩光时再立项 |
| m | Bliss 建议将「思想来源：Bliss 2.1.2」补进 Astra/THIRD-PARTY.md 台账 | bliss-shader.md（⑤） | 登记动作本身，无需代码核实 |
| n | Photon 报告建议 TAA 四件套与云影-半影联动为最低工作量快赢 | photon-shader.md（⑥） | 与 b) 一并确认 taa_resolve 现状后实施 |
| o | Hysteria 报告建议：将来若需同类代码，优先从 Photon 上游取 MIT 代码而非 AGNYA 包 | hysteria-shaders.md（⑤） | 采购顺序约束，无代码核实 |
| p | Solas 报告建议：无 LICENSE 包统一走「结构借鉴+独立重写+登记」前置约束 | solas-shader.md（⑤） | 流程约束，无代码核实 |

### ④-2 报告内「不确定」补充汇编（影响借鉴决策者）

| # | 事项 | 出处报告 | 建议核实方式 |
|---|---|---|---|
| q | Astra 水下光束是否已有「水下看水面」光束染色 | complementary-unbound.md（④） | 读 `global/water/light_shafts.glsl` 全文（报告未逐行核对到该分支） |
| r | Astra 水面是否有 Snell's window 等价项 | bliss-shader.md（③-6）、solas-shader.md（③-a-5） | 读 `global/water/optics.glsl` 与 `surface.glsl` |
| s | Astra 云/雾风场时间源（frameTimeCounter vs 世界时间）未核对 | kappa-shader.md（③-10）、nostalgia-shader.md（③-10） | 读 `clouds_planar.glsl` 与 wind 相关 uniform |
| t | Astra cloud_shadow_cache 分辨率/更新频率未核实（决定云阴影并入天空缓存 alpha 是否更省） | nostalgia-shader.md（③-8） | 读 `global/atmosphere/cloud_shadow_cache.glsl:6-15` 与 `program/cloud_shadow_cache.fsh` |
| u | Astra volume_fog 步数是否随距离自适应未核实 | nostalgia-shader.md（③-9） | 读 `global/atmosphere/volume_fog.glsl:11-30` march 循环 |
| v | Astra 波场是否有几何位移层 | sildurs-vibrant-shaders.md（④） | 读 `global/water/surface.glsl` 是否写顶点位移 |
| w | Astra AO 门控（PERF 档 AO=off 且要求 SHADOWS）是否为有意设计 | makeup-ultra-fast-shaders.md（④ 分歧点） | 统帅确认设计意图后决定是否借「无阴影 AO」 |
| x | Astra SH9 投影源（解析天空还是 capture）未核对 | kappa-shader.md（④） | 读 `lib/sky_sh9.glsl` 投影输入端 |

### ④-3 报告间矛盾并列（如实并列，不裁断）

1. **Astra TAA YCoCg AABB**：bsl-shaders.md ④「若 Astra 未含可低成本补（未核实）」 vs photon-shader.md ④「Astra 已有 YCoCg 方差裁剪（1.25σ 固定值，`taa_resolve.fsh:109-118`）」——影响 TAA 类借鉴点基线（涉 b/n）。
2. **Astra 雨湿水洼/涟漪**：bsl-shaders.md ④「Astra 目前未见水洼掩码与涟漪（不确定）」 vs sildurs-vibrant-shaders.md ④「`weather.glsl:21` 起 astra_puddle 掩码与涟漪环」——影响水洼借鉴点（②-2 首行）的起点判断。
3. **Complementary r5.9.3 bloom 机制**：complementary-reimagined.md ②「tile 内容做 bloom^4 阈值（composite5.glsl:113-116）」 vs complementary-unbound.md ②「1/4 gamma 存储=无阈值软截断（composite4.glsl:50、composite5.glsl:111-116）」——同一文件两份报告表述不同。
4. **VPS 作者归属**：任务背景称 Sixthsurge（Photon 作者），vanilla-plus-shader.md ① 以包内证据（lang/LICENSE/版权头）判定为 RRe36，报告按代码事实写作。
5. **Astra 手持光有无**：solas-shader.md ④ 列「手持光源：Astra 无」；而 hysteria/insanity/mellow 报告均按 Astra 已有对照（`blocklight.glsl:62-70`、HANDHELD_LIGHTING）。Solas 侧「缺」应理解为「缺该组织方式/参数面」。

## ⑤ 落地路线图

### 快赢 Top10（跨包择优；工作量档位：半天内/数天/一周+）

| # | 快赢项 | 来源包 | 工作量 |
|---|---|---|---|
| 1 | 程序级 pass 熔断：GODRAYS/VOLUME_FOG/SSR 关闭时整 pass 禁用 | Complementary（`shaders.properties:99-113` 等，10 包印证） | 半天内 |
| 2 | 手持光重做：连续衰减（去 15 格硬边）+ 玩家中心光心 + 源头封顶 0.93 | Hysteria（`handheld_lighting.glsl:31-45`）+ Insanity（0.9333 封顶）+ BSL | 半天内 |
| 3 | 云影进入半影半径 + 云影缓存湿天/太阳高度联动 | Photon（`pcss.glsl:246-248`）+ Kappa（`prepare2.fsh:591-597`） | 半天内 |
| 4 | Purkinje 夜视蓝移挂 grading 链 | Mellow（`tonemap.glsl:69-79`）+ Bliss + Photon + Nostalgia + Kappa（5 包印证） | 半天内 |
| 5 | 前向地形雾完全雾化 discard | Miniature（`textured_lit.fsh:60-62`） | 半天内 |
| 6 | NO_SHADOWS 档假阴影兜底（visibleSky 幂衰减） | MakeUp（`light_vertex.glsl:115-129`） | 半天内 |
| 7 | 雨天波幅耦合 + 波形风格档（幅值项接 astraRainFactor） | Solas（`waterNormals.glsl:26-30`，报告估半天级） | 半天内 |
| 8 | 水下光束焦散调制（march 内乘焦散项） | Bliss（`composite2.fsh:303`）+ Shrimple（`fog_volume.glsl:388-397`）+ Photon | 数天 |
| 9 | 天空缓存增烘「含云行」（云阴影可入 alpha 一并设计） | VPS（`skyboxPrep.fsh:250-270`）+ Bliss + Nostalgia + Kappa + Sildur + FastPBR（6 包印证） | 数天 |
| 10 | TAA pixel-age 等权收敛 + offcenter rejection | Photon（`c4_taa_exposure.fsh:306-311,363-372`）+ Kappa + Mellow | 数天 |

### 中期（数天～一周+，按依赖排序）

- 折射二次校验+深度差限幅、SSR 行进效率细节（Complementary+Photon+Hysteria+Nostalgia+VPS+Miniature，4/3 包印证各）——数天。
- SSR miss 回退接入 sky_reflection_cache（Photon+VPS+Kappa+FastPBR 等 6 包印证）——数天。
- 云影-云密度同源化重构（BSL `shadows.glsl:295-375`；先核实④-c）——数天。
- 分通道水下吸收+可调指数（Solas `waterFog.glsl:2-9`，报告估一天内含重校常数）——数天。
- eBS 暗适应贯穿（雾/天空/云）+ darknessFactor 全覆盖（Insanity+BSL）——数天。
- 方块光三段衰减曲线 + 暗处去饱和驱动量调整（Hysteria+Insanity+Ebin）——数天。
- 水洼掩码+孔隙度两层暗化+室内积水门（BSL+Hysteria 等 7 包印证；先核实④-矛2）——数天～一周+。
- PCSS blocker search + R2 盘采样（Shrimple+Ebin+VPS+FastPBR 等 7 包印证；Ebin 版 GPL 可改编）——数天～一周+。
- 复杂自动曝光（中心加权+明暗百分位钳制）（Nostalgia+Kappa+FastPBR+Bliss+Photon，5 包印证）——数天。
- 体量雾耦合彩光场（RV+Unbound+Solas）——数天（RV 报告估 ~20 行）。
- 下界风暴/烟羽层（Complementary+RV+Bliss+Solas；涉 settings.glsl:177 既有决策，需统帅拍板）——数天。
- 逐日天气系统（Bliss+Kappa+Photon+Nostalgia）——一周+。
- 极光系统（Solas kpIndex 叙事+Mellow/BSL/Complementary 造型；Solas 报告估 2-3 天）——数天～一周+。
- ACES 参数面补全 / tonemap 三段风格化 / 保亮度三区调色（Nostalgia+Kappa+Photon；Unbound；Mellow）——数天，属美术取向需统帅拍板。

### 长期储备（一周+ 或需立项）

- 主世界彩光推广：Ebin floodfill 三件套整体改编（GPL 可改编）为首选路线；BSL/Photon/Mellow/Complementary 对照（Mellow 报告持保留意见，见④-l）。
- SDF+coneTrace 光源软阴影 → 逐像素光源列表+GGX 彩光高光（RV，两期推进）。
- 场景球面 capture（SSR miss 场景级回退）（VPS `capture.fsh:93-154` + Kappa `composite2.fsh:477-492`）。
- 体积云多重散射能量估计（Kappa+Photon+VPS+Bliss；需先立体积云载体）。
- TAAU/渲染缩放正交旋钮（Photon+Nostalgia+Hysteria+FastPBR+Kappa+Bliss，6 包印证）。
- RSM GI（Ebin `ComputeGI.fsh:51-80`，需重排影图输出通道）。
- WSR 世界空间反射（Complementary `worldSpaceRef.glsl`，报告定为很高难点）。
- labPBR/POM 材质子系统（VPS+FastPBR+SDV 参照；含金属 n/k 表与 VNDF 底座）。
- 多层水体深度介质切换（Shrimple）。

---

*本汇总只汇编与转引，不替代任何单包报告；各条实施前请回到对应报告核对上下文与不确定项（④）。*

## ⑥ Astra 实施接续（2026-10-02）

依照用户要求，本轮已落地公共参数 CPU 预计算、Bloom 关闭时的水下阶段合并、零贡献空气光束阶段关闭、Bloom 4 / 9 / 13 次采样分档、短射线体积雾自适应、实体投影开关、玩家中心连续手持光、TAA 纹素中心可信度、可选夜间蓝移与零偏移折射早退。代码位于 `Astra/shaders/`，菜单及预设已同步。

上文是调研时的路线图，不能将所有建议当成当前缺失功能：Astra 已有静态阴影兜底、含云球面天空缓存、焦散阴影供水下光束消费、YCoCg 方差裁剪、雨湿材质和自适应云步数。水面 SSR 历史此前已退出渲染，摘要的“水体独立历史”应区分水下光束历史与水面反射。

具体参数、Top10 对照、未采用原因和已有能力见[实施记录](../docs/archive/实现与取证.md#record-017)；当前选项见[颜色与性能设置](../docs/实现与限制.md)。游戏加载表现、画面及帧率变化尚未确认。
