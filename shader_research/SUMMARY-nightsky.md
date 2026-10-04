# 夜空专题调研：银河群星特色光影盘点与 Astra 夜空借鉴点（SUMMARY-nightsky）

后续实施（2026-10-04）：已选取天体锚定、平滑星点、弱冷暖闪烁、亮星层次与星量选项，并补齐星光的 TAA 反应值。当前实现及报告纠正见[夜空选择优化](../docs/2026-10-04-nightsky-selected-optimizations.md)。下文的 Astra 现状与行号描述调研时的源码，新增银河、极光等仍属于候选。

日期：2026-10-03。上承 `SUMMARY-batch3.md`（其中 3.1 节已把 AstraLex「星座分桶」列为候选；本报告把夜空从特性侧深挖到底）。
研究对象 14 个 = 已入库大包的夜空子系统补挖 8 个 + 本轮新下载主题包 6 个（全部解压在 `reference_shaderpacks/<slug>/`，zip 在 `reference_shaderpacks/zips/`）。
执行方式：Astra 夜空基线通读 → 每包由只读调研代理定位夜空实现并逐文件读 → 每条借鉴点先对 `Astra/shaders` grep 确认无等价实现才列入。
本报告为纯调研产出，不含对 Astra 的代码改动。包内 file:line 相对 `reference_shaderpacks/<slug>/shaders/`（多数省略 world0/program 子目录，按文件名 find 可定位）；Astra 侧相对 `Astra/`。

## 一、Astra 夜空基线（去重底线）

| 项 | 现状 | 证据 |
|---|---|---|
| 群星 | 仅 89 行程序化点星，移植自 Complementary r5.9 (Reimagined)：三连噪声哈希 + 球面投影格胞 + 阈值；固定色 vec3(0.38,0.4,0.5)；无闪烁（settings 注释写 "subtle twinkle" 但实现没有）；无星量档（上游 NIGHT_STAR_AMOUNT 0-4 只搬了默认档 star-=0.7） | global/atmosphere/stars.glsl:31-70；lib/settings.glsl:100 |
| 星空运动 | starCoord.x += 0.006*frameTimeCounter 的水平漂移——与日月运行完全解耦、暂停仍走、无逐日差异 | stars.glsl:43 |
| 消费端 | deferred.fsh:315、scene.glsl:54、water.glsl:270 经 overworld.glsl:88-94 调用；反射天空缓存刻意不含星（overworld.glsl:38-40） | 同左 |
| 时间源 | **主世界无 worldDay/worldTime/sunPathRotation/sunAngle uniform 声明**（lib/uniforms.glsl 全无；仅末地 end_geometry.glsl:19-20 声明过 worldDay/worldTime 并在用）——迁移一切「天体锚定/逐夜变化」特性的前置工程 | 调研代理取证 + 审查复核 |
| 银河带 | 无实现（主世界空白） | 全库仅注释提及（end_kerr.glsl:171、end_sky_buffer.fsh:1），无实现代码 |
| 星云 | 仅末地：end_kerr.glsl:196-230（CU nightNebula 立方值噪声 + 五倍频 fBm）；主世界空白 | 同左 |
| 极光 | 无；clouds_planar.glsl:44 自己标注 AURORA_STYLE / NIGHT_NEBULAE 附加项 NOT PORTED（云不被夜空染色是已知缺口） | 同左 |
| 星座/流星/行星 | 无实现 | meteor/constellation 全库 0 命中；planet 仅 sky_minishita.glsl:79 注释 |
| 夜空大气 | sky_gradient（239 行，三段夜色渐变）+ sky_minishita（135 行 Rayleigh/Mie，:19 记录 "no ambient floor 故 DAY_GAIN=22" 已知问题；无臭氧通道） | 同左 |

结论：Astra 的星空是 CR 谱系的最小移植，与其「群星」定位不匹配；夜空是当前最能强化身份的模块，且 Astra 自己的 NOT PORTED / DAY_GAIN 记录已指出两处现成缺口。

## 二、圈选与排除

### 2.1 研究对象（14 个）

**已入库包的夜空子系统补挖（9 款，8 个研究方向，CR 双包合并）**：AstraLex 93.0、Photon v1.3b、Bliss 2.1.2、Complementary Reimagined r5.9.3、Complementary Unbound r5.9.3、Solas（包内无版本串）、Kappa 5.3、Nostalgia 5.1、Insanity 1.600。
**新下载主题包（6，Modrinth 下载量为 2026-10-03 时点）**：

| 包 | 版本 | 下载量 | 规模 | 血统 | 定位 |
|---|---|---|---|---|---|
| auroras-shaders | 1.9 | 917,635 | 306 文件 | CU r5.0.1 编辑 | 彩色 Vanilla+，自加程序夜星云 |
| aurora-fantasy | 5.5.2 | 176,010 | 359 文件 | 自研（含世界日极光/萤火虫） | 奇幻夜景三件套 |
| aurorart | 1.0.0 | 5,143 | 429 文件 | Complementary License 1.6（CR 深改） | 闪烁星网+流星雨+curl 体积极光 |
| dreamers-shaders | 1.2 | 5,539 | 427 文件 | Complementary 衍生 | 「每晚极光」+品红星云+下界火光极光 |
| aurora-astral | 1.0 | 4,080 | 361 文件 | MakeUp Ultra Fast 深改 | 星界裂缝+解析球巨型行星 |
| eternal-prism | 0.6.0-beta | 1,072 | 33 文件 | 小型自研 | 星夜主题（方向域 fbm 极光色带/3D 云/活水） |

### 2.2 排除说明

- Modrinth「星空特色」独立小包生态薄弱：galaxy-shader（806 DL，把方块变成星空的整活包）、vivid-realism（979 DL，来源可疑的 "Claude AI shader"）、reasonableView（220 DL）、cinematic-villa "Aurora Enhanced"（5.6K）、super-ugly-shaders（整活）均不入选。
- 真正的夜空标杆集中在已入库大包内，故采取「补挖存量 + 少量新血」策略；上轮 62 款中未做夜空补挖的（Mellow、Hysteria、MakeUp 等）无夜空特色或已被血统覆盖（Aurora Astral 即 MakeUp 深改）。
- **前提更正**：调研证实 Bliss 2.1.2 副本内无任何极光/银河/星云代码（grep aurora/milky/galaxy 仅命中一幅画像名），「Bliss 带极光」的普遍印象不适用于本副本；Insanity 的极光也是 BSL 基线原样携带、非其增量。

## 三、跨包特性矩阵

| 包 | 群星 | 银河带 | 星云 | 极光 | 星座 | 流星 | 行星 | 天体锚定 | 云/反射耦合 |
|---|---|---|---|---|---|---|---|---|---|
| AstraLex | 双层+天区闪烁+月掩 | 贴图 | 贴图 | 30 层平面 | **星表+分桶连线** | 大圆轨道 | 贴图 | 月锚四元数 | 反射（自带 bug） |
| Photon | 黑体色温+逐星闪烁 | 贴图 2048² | — | 体积 64 步 Worley | — | — | — | **shadowModelViewInverse** | 环境光注入 |
| Solas | 双尺度+亮星种群 | 贴图+程序双层 | 程序三频 | 体积 kp 指数+遮挡反馈 | — | 每日方向表 | — | worldDay（流星/极光）；星野仍 frameTimeCounter 漂移、未锚定 | 遮挡+照明云 |
| CR / CU | （Astra 移植源） | — | 3 层 fbm | 25/10 层双风格 | — | — | — | syncedTime | 云 +0.1/+0.2 |
| AuroraRT | 3×3 邻域累积+halo | — | 尘埃暗带版 | curl 域扭曲 15/30 步 | — | 解析流星雨 | — | syncedTime | 云+反射 |
| auroras-shaders | CU 同款 | — | 3 层视差+潮汐 | CU 25 层 | — | — | — | — | 云 +0.1/+0.2 |
| Bliss | hash 整数格双线性 | — | — | —（本副本无） | — | — | — | worldTime 旋转 | — |
| Kappa | 单层双色 | — | — | — | — | — | — | worldTime+25° 倾角 | ×大气透射 |
| Nostalgia | 每星色温+亮度 | — | — | — | — | — | — | worldTime+平面滚转 | — |
| Insanity | =BSL | — | — | =BSL（24/12 步） | — | — | — | — | — |
| Dreamers | =CU | — | 品红系+连续时间形变 | 每晚出现+下界火光版 | — | — | — | — | 云染色+反射 |
| Aurora Fantasy | 双层 cell+软光斑 | — | — | worldDay 逐夜调色 | — | — | — | sunAngle/sunPath | 萤火虫+反射 |
| Aurora Astral | cubic+sunAngle 旋转 | — | 3 帧图集星云 | — | — | — | **解析球 Colossus** | sunAngle | 反射掩码增亮 |
| BSL（基线） | CR 谱系 | — | — | 平面投影 24/12 步 | — | — | — | — | — |

## 四、借鉴点（经去重，按「Astra 夜空价值」分层）

### 4.1 前置工程（先做，否则后面全是空中楼阁）

1. **引入 worldTime/worldDay/sunPathRotation/sunAngle uniform** — Astra 主世界路径完全缺失（仅末地 end_geometry.glsl:19-20 声明过 worldDay/worldTime 并在用）；Astra 已有 CPU 表达式管线（shaders.properties 自定义表达式）可承载归一化与平滑，模式与 10-02 的帧不变量移交一致。来源佐证：Photon/Kappa/Nostalgia/AuroraRT 全部用 worldTime 驱动星象；Aurora Fantasy 用 worldDay 做逐夜变化。代价：低。
2. **星空挂天体坐标** — 三种做法任选：Photon 用 `shadowModelViewInverse` 把视线变换到日月天球（include/sky/sky.glsl:130-143，Astra scene/deferred 已有该矩阵）；Aurora Fantasy 用 sunPathRotation 倾斜 + sunAngle 旋转（stars.glsl:46-65）；Kappa/Nostalgia 用 worldTime/2400 平面旋转+25° 滚转（deferred2.fsh:125-127 / skyboxApply.fsh:31-34）。替换掉 stars.glsl:43 的 frameTimeCounter 漂移后，星象与月亮同升落、每夜可复现。代价：低-中。

### 4.2 A 组：低代价、直接强化「群星」身份

| 借鉴点 | 机制 | 来源 file:line | Astra 侧证据 |
|---|---|---|---|
| 每星黑体色温 + 逐星相位闪烁 | hash 通道取 temp=mix(4500,8500)→blackbody()；twinkle=1-noise.z*cos(t*2+tau*noise.w) | photon-shader/include/sky/stars.glsl:6-25 | Astra stars.glsl:69 全星固定色且无闪烁（settings 注释与实现不符）；末地已有可复用先例 astra_blackbody_rgb（end_blackhole.glsl:5、end_system.glsl:77,96） |
| 双层星 + 亮星种群 | 第二层 484 格网亮度×100（AstraLex stars.glsl:9-10,38-52）；同 hash 第二阈值 pow2(max(n-0.95))*2048 得少量亮星（Solas stars.glsl:34-38） | 见左 | astra_stars 单层 |
| 星整数格双线性稳定 | hash 场 4 点双线性插值 + exp 收窄，快速转头不闪跳 | bliss-shader/lib/stars.glsl:30-56 | Astra floor(coord*1024) 无插值 |
| 星野随世界时间自转+倾角/滚转 | 已并入 4.1.2；Kappa 25° 倾角、Nostalgia 平面 25° 滚转 | kappa-shader/world0/deferred2.fsh:125-127；nostalgia-shader/program/deferred/skyboxApply.fsh:31-34 | 现为解耦漂移 |
| 解析流星雨叠加层 | 星格 hash>0.991 触发、对角平流 streak 头尾渐变、0.997 火球；无纹理几行代码。**照搬须自加夜/雨掩码（RT 原码白天也会出流星）** | aurorart/lib/atmospherics/stars.glsl:3-29,135 | 全库无流星 |
| 流星每日方向表版 | 10 条起终点按 worldDay%10 轮换 + 日概率 + 全局爆发包络 | solas-shader/lib/atmosphere/stars.glsl:55-148 | 同上 |
| 星量档位补全 | 上游 NIGHT_STAR_AMOUNT 0/1/3/4 档未搬 | complementary-reimagined/lib/atmospherics/stars.glsl:15-40 | stars.glsl:61 写死 -=0.7 |
| 星云内透星 | rgb *= 1.5+10*pow2(max0(n1*n2-0.6))，星点从星云里闪亮 | complementary-reimagined/lib/atmospherics/nightNebula.glsl:85-102（auroras-shaders 同款 :85-87） | 末地星云无此层 |
| 极光/星云染云 | clouds += aurora*0.1 + nebula*0.2 | complementary-reimagined/lib/atmospherics/clouds/mainClouds.glsl:132-136（CR/CU/AuroraRT/Dreamers 同构） | clouds_planar.glsl:44 自己标注 NOT PORTED——补上即还账 |
| 臭氧吸收通道 | sky_density 返回 vec3(Rayleigh,Mie,Ozone)，35km 双指数峰并入消光——夜天顶深蓝/暮光紫的物理来源 | bliss-shader/lib/ROBOBO_sky.glsl:52-59,136-139 | sky_minishita 只有 (R,M) 二元 |
| 假多次散射 ambient | 循环后整体乘 averageSkyCol 当各向同性 ambient——正好解 Astra "no ambient floor / DAY_GAIN=22" 记录的问题 | bliss-shader/lib/ROBOBO_sky.glsl:152-162 | sky_minishita.glsl:19 |
| 星野×大气透射 | 星与日月乘同一 LUT 透射，近地平变暗变色 | kappa-shader/world0/deferred2.fsh:256-284 | Astra 星无大气消光，地平恒星过亮 |

### 4.3 B 组：中代价、构成夜空主体特性

| 借鉴点 | 机制 | 来源 file:line | 说明 |
|---|---|---|---|
| 纹理银河带 | 静态 equirect 贴图（Solas 512×1024 repeat+blur / Photon 2048×1024），lon/lat 或球面投影 1 次采样；密度 pow(alpha,6-3*space) | solas-shader/lib/atmosphere/milkyWay.glsl:27-44 + shaders.properties:128-129；photon-shader/include/sky/sky.glsl:99-119 | Astra 主世界最大空白；可离线烘焙贴图避开素材问题；与末地程序星云差异化 |
| 银河↔星野密度反馈 | 银河亮度反哺星阈值 `0.825-nebulaFactor*0.125`，银河带内星更密 | solas-shader/lib/atmosphere/milkyWay.glsl:40 → stars.glsl:33；photon-shader stars.glsl:47-50 | 一行阈值，观感增益大 |
| 主世界程序星云 | CU 家族 3 层 perlin-fbm（5/8 octave）+ 潮汐阈值 + 方位角躲日月；AuroraRT 加尘埃暗带（dust 把 rgb 压到 5%、alpha 30%） | complementary-reimagined/lib/atmospherics/nightNebula.glsl:24-102；aurorart/nightNebula.glsl:96-98 | 复用 Astra 已移植的 GetStarCoord/star hash；须与末地 end_kerr 版本差异化 |
| 极光：CR 骨架起步 | 平面求交+分层+抖动，25/10 双档采样，visibility 早退，style1 锯齿/style2 平滑双档 | complementary-reimagined/lib/atmospherics/auroraBorealis.glsl:2-56；common.glsl:435-438 | Astra 可先拿 complementary-cloud-water.png 当噪声源 |
| 极光：进阶变体 | Photon 体积 Worley 双风场挤出 64 步+13 组世界日色表+稀有度；Solas kp 指数（worldDay 取模+雪地+3）+ auroraOcclusion 反压银河+极光照云照地；AuroraRT curl 域扭曲 15/30 步 | photon-shader/include/sky/aurora.glsl:9-86 + aurora_colors.glsl:8-92；solas-shader/lib/atmosphere/aurora.glsl:62-207 + lighting/gbuffersLighting.glsl:250-283；aurorart/auroraBorealis.glsl:44-111 | 建议路线：CR 骨架 → 视觉成立后再上 kp/环境光 |
| 极光能量归一合成 | weightedColor/totalEnergy 归一再乘 softEnergy=1-exp(-E*0.6)，多层重叠无色阶；雨天留 5.5% 残余 | aurora-fantasy/lib/aurora.glsl:148-176,44-47 | 任何极光实现都该带的合成纪律 |
| 极光「每晚出现」节奏 | AURORA_CONDITION=0 全夜档，不靠随机；worldDay 哈希当晚色板/速度（nightSeedA/B） | dreamers-shaders/lib/atmospherics/auroraBorealis.glsl:2-13；aurora-fantasy/lib/aurora.glsl:75-85 | Astra 可做成条件档位预设 |
| 极光作环境光源 | 极光色加进 sky_color/ambient_color（0.40/0.10） | photon-shader/program/d0_sky_map.vsh:149-151 + d1_clouds.vsh:113；solas gbuffersLighting.glsl:250-283 | Astra astra_sky_ambient 可直接挂极光项 |
| 星座连线星表 | 单位向量星表+线段索引+星座前缀分桶，只遍历最近 1-2 桶（最坏 ~8 星）；大圆判线+极坐标十字光晕 | astralex/lib/atmospherics/shiningstars.glsl:35-129 + toitoiles.glsl:1-2400 | batch3 已列候选；对「群星」身份是最强叙事件；注意数据体积与档位 |
| 天空特征→反射掩码增亮 | 用 wash 差求局部开口覆盖率，避免 Fresnel 把夜空大件压没 | aurora-astral/lib/water.glsl:318-328 | Astra 反射通道已有（overworld.glsl:47-60），此为增强策略 |
| 下界火光极光 | 同一极光函数换火红配色 | dreamers-shaders/lib/atmospherics/netherAurora.glsl:2,38 | Astra nether 可复用 |

### 4.4 C 组：大工程、后置观察

| 借鉴点 | 机制 | 来源 file:line | 说明 |
|---|---|---|---|
| 解析球巨型行星 | 无几何解析球 + 差分纬向剪切 + 双层视差 + sunDir 局部光向球面 Lambert+limb；RGB 预乘辐射 + alpha=被替换天空能量统一合成 | aurora-astral/lib/colossus_planet.glsl:110-385,357-385 | Astra 无任何天空行星；公式自足；可先给末地 |
| 星界裂缝（有符号场） | 双缎带相位漂移 + sqrt 软钳最小间距 + 有符号裂纹场与主带取并集 + 3 帧 2048 图集 40 分钟交叉溶解 | aurora-astral/lib/cosmic_rift.glsl:208-346,363-477,750-793,133-148 | 数学量大；「群星」身份的远期大件 |
| 贴图星空板 | 旋转矩阵+针孔投影采样 planet/nebula/galaxy 三张 PNG（967²/1048×1089/1025²），colortex9/10/11 绑定 | astralex/lib/atmospherics/skyimage.glsl:3-52 + shaders.properties:531-546 | 需自备素材、内容不随参数变化；与程序方案二选一 |
| 萤火虫世界格粒子 | 3D 世界格锁定粒子群+屏幕射线求交+reactiveMask 防 TAA 拖影 | aurora-fantasy/lib/fireflies.glsl:56,79-97,278 | 独立大系统，非夜空本体 |

### 4.5 反面警示（不要照抄）

1. **AstraLex STARS_REFLECTION 疑似失效**：waterReflectionStuff.glsl:20-27 改的是局部副本、stars1 恒为 0——勿照抄其反射星空接线。
2. **AuroraRT 流星无夜/雨掩码**：GetMeteorShower 无条件叠加，白天也会出流星（stars.glsl:135）——照搬必须补 invNoonFactor2/invRainFactor。
3. **Solas 星空块无深度门**：仰视天空的地形像素仍会白算星野/流星（deferred1.glsl:286-350 之间无 z 判断）——Astra 应像 CR/Kappa 一样用 z0==1.0 / !landMask 门控。
4. **Aurora Fantasy 的 STARS_COVERAGE 是死设置**（config 里存在但 shader 未读取），其 cubic_uv 分面投影与 Astra 已弃用该投影的决定冲突——保留球面投影。
5. **Insanity 对 BSL 是倒退**（删月相数据表、雾色疑似笔误），其夜空无增量；BSL 极光引用时标注 BSL 而非 Insanity。
6. **AstraLex 双层星第二层 1024/484 格网在低仰角会摩尔纹**（格网类星场的通病），迁移时保留 CR 的球面投影衰减。

## 五、建议落地顺序（呼应「Astra 是群星」）

1. 前置 uniform + 天体锚定（4.1）——星空与月同步，是所有后续特性的地基，也是观感违和的最大单点修复。
2. 星本体升级（4.2 前四条）——色温/闪烁/双层/亮星/格双线性，全部是 astra_stars 内的几行级改动。
3. 补两笔旧账（4.2 的染云 NOT PORTED、sky_minishita 的 DAY_GAIN/臭氧）——Astra 自己记录过的缺口。
4. 银河带（4.3 首条）+ 密度反馈——「群星」身份的主视觉，一张离线烘焙贴图 + 一次采样。
5. 流星（4.2）——夜空事件感，性价比最高的小件。
6. 极光（4.3）——CR 骨架起步，条件档位 + 能量归一 + 环境光注入逐级上。
7. 星座连线星表（4.3）——身份叙事件，复用末地星表索引思想。
8. 行星/裂缝/萤火虫（4.4）——远期大件后置。

## 六、逐包调研摘要

### 6.1 AstraLex 93.0（夜空最重的一个）
全套夜空：双层程序星（月锚天球投影+3 次 sin-hash+覆盖阈值+天区相位闪烁+月面遮蔽，lib/atmospherics/stars.glsl:1-91）；星座连线/亮星（shiningstars.glsl:35-129 + 数据表 toitoiles.glsl:1-2400，单位向量星表+线段索引+前缀分桶，大圆判线）；极光（aurora.glsl:10-95，30 层平行高度平面+折叠噪声丝+幂色带+exp2 衰减）；流星（shootingstars.glsl:1-81，noisetex 取两点单位球大圆插值+pow30 末端淡出）；行星/星云/银河贴图板（skyimage.glsl:3-52，旋转矩阵+针孔投影，colortex9/10/11 绑定 PNG）；月锚四元数（moonrot.glsl:1-43 把 up 旋到 up/uSunVec 角平分）。全部只在 skybasic 天空像素+反射分支；LOW/MEDIUM 关极光/行星/星云/银河，ULTRA/LEX 才开反射。性能：贴图特性单次采样无循环；极光按 sampleCount 30/15 分档。

### 6.2 Photon v1.3b
夜空子系统最完整的大包：黑体色温星场（stars.glsl:6-60，投影+600、4 格 cubic 插值、temp=mix(4500,8500)→blackbody、逐星 cos 闪烁、银河亮处阈值降低星更密）；纹理银河带（sky.glsl:99-119，2048×1024 equirect、tint、2× 饱和）；体积极光（aurora.glsl:9-86，1000-3000m 圆柱 64 步、noisetex.y 双 Worley 风场挤出、高度包络；aurora_colors.glsl:8-92 十三组世界日色表+worldDay%5 稀有度+雪地分档）；极光注入环境光（d0_sky_map.vsh:149-151）；**天球锚定 = ray_dir × shadowModelViewInverse**（sky.glsl:130-143）；月亮 noisetex+相位光向（sky.glsl:46-96）。性能：极光只算云缓冲分辨率与 191×108 天空图，不进全分辨率；星每像素 4 次 hash 无循环。

### 6.3 Solas（版本号包内无据）
四件套齐全且互相反馈：星野三层（stars.glsl:5-49，双尺度格相乘+亮星种群）；银河带（milkyWay.glsl:27-44，512×1024 贴图经 depthtex2 采样器绑定，repeat+blur，zx 交换=银道面转 90°）；程序星云（同文件 7-26，三频噪声+地平弧掩码，被极光遮挡压制）；体积极光（aurora.glsl:62-207，kp 指数=worldDay 取模+雪地+3，双周期 pulse，高度绿→紫渐变+高 kp 转红，auroraOcclusion 反压银河）；流星每日方向表（stars.glsl:55-148，worldDay%10 轮换+爆发包络）；极光反哺照明（gbuffersLighting.glsl:250-283）。星野/银河/极光/流星只改 skyColor 且 z0==1.0 写回；隐患：无深度门（见 4.5.3）。

### 6.4 Complementary Reimagined / Unbound r5.9.3（Astra 直系源头）
星场+极光+星云三件套（stars.glsl:3-48 / auroraBorealis.glsl:1-72 / nightNebula.glsl:1-103 / enderStars.glsl:5-33 / enderBeams.glsl）；月面噪声陨石坑+月牙（gbuffers_skybasic.glsl:95-165）；夜幕三段渐变。**与 Astra 移植版差异清单**：NIGHT_STAR_AMOUNT 0/1/3/4 档未搬；上游星场进反射而 Astra 刻意省去；时基 syncedTime（含 worldDay）vs Astra frameTimeCounter；月面细节未搬；极光/星云/末地星/光柱未搬。CU 与 R 仅 SHADER_STYLE 一行之差（common.glsl:15，style2=平滑极光+程序日月盘默认）。性能：极光 25/10 双档+visibility 早退；星云 nebulaFactor<0.001 早退、NIGHT_NEBULAE 默认 OFF；反射夜空特效受 SKY_EFFECT_REFLECTION 档位控制。

### 6.5 AuroraRT 1.0.0（CR 深改）
CR 星场升级为 3×3 邻域累积+高斯核+halo（stars.glsl:46-138）；**解析流星雨**（同文件 3-29，hash>0.991+对角平流+火球，无夜/雨掩码 bug 见 4.5.2）；星云加尘埃暗带+内嵌星点+HDR 软膝（nightNebula.glsl:63-130）；极光重写为 curl 域扭曲 15/30 步 raymarch，noisetex RGB 一纹理三用（r=帘、g/b=流线）（auroraBorealis.glsl:1-115）；青紫夜底+magicGlow 呼吸；云/反射耦合（mainClouds.glsl:101-107、reflectionBackground.glsl:44-50）；syncedTime 驱动星/星云相位。性能：极光按 pass 分档且只算天空像素；星云 5/8 octave 档。

### 6.6 auroras-shaders 1.9
CU r5.0.1 编辑：星/极光与 CU 同源（排除）；自加程序夜星云（nightNebula.glsl:16-95，三层缩放+时间漂移视差+阈值潮汐+星点透亮）；极光像素化样式可选（auroraBorealis.glsl:33-39 floor 量化）。无银河/星座/流星/行星。星云 OCTAVE 挂 DETAIL_QUALITY；与 CU 的差异主要在默认档与细节参数。价值：星点透星与三层视差两条已并入 4.2/4.3。

### 6.7 Bliss 2.1.2
**本副本无极光/银河/星云**（前提更正）。夜空=hash 点星（lib/stars.glsl:21-56，整数格+四邻域双线性+exp 收窄）+ Robobo 物理大气 LUT（ROBOBO_sky.glsl:52-165，Rayleigh/Mie/臭氧三通道+假多次散射 ambient）+ worldTime 旋转（composite1.fsh:939-943，绕天轴每游戏日 1 rad）。星×大气透射之外的合成次序与 Astra 不同（星不进 LUT）。价值全在臭氧与 ambient 两条（4.2）。

### 6.8 Kappa 5.3
夜空最小化：单层星（deferred2.fsh:123-144，worldTime 平移+25° 倾角、蓝/红双色混合、sqrt(daytime.w) 淡入）+ 256×384 三格天空 LUT（prepare.fsh:23-80，sqrt 纬度 warp 提高地平角分辨率）+ 星×大气透射（deferred2.fsh:256-284）。价值：透射乘法与 sqrt-warp 思路（4.2/4.3）；星象相位锁定 worldTime。

### 6.9 Nostalgia 5.1
星场随游戏时间整圈旋转+平面 25° 滚转（skyboxApply.fsh:31-34）；每星色温（青白↔暖红低频混合）+ 亮度 ×1..2（:38-48）；256² 捕获夜空渐变/月晕供天空/雾/反射/skylight 复用（skyboxPrep.fsh:32-61，Astra 反射缓存不含星，属策略差异）。价值：色温与滚转两条（4.2）。

### 6.10 Insanity 1.600
相对 BSL 无夜空增量（星场/极光同为 BSL 原样，仅 dither 种子与改名；还删了 BSL 八相月面数据表、fogCol 疑似笔误）。唯一素材是 BSL 基线极光（bsl-shaders/lib/atmospherics/clouds.glsl:526-599，平面投影 24/12 步）——引用须标注 BSL。

### 6.11 Dreamers 1.2
「每晚出现」的极光（AURORA_CONDITION=0 全夜档，无随机门控）；层叠双色丝状（品红→青绿）；星云连续时间形变（syncedTime*0.003，跨天连续推进）；下界火光极光（netherAurora，同函数换色）；云染色+反射耦合。星与 Astra 逐行同源（排除）。

### 6.12 Aurora Fantasy 5.5.2
极光 worldDay 逐夜调色（nightSeedA/B 哈希当晚双色调+速度 0.68-1.34）；能量归一合成+雨天 5.5% 残余；星域挂 sunPathRotation/sunAngle 天体坐标（stars.glsl:46-65）；世界格萤火虫群（fireflies.glsl，含 reactiveMask 防 TAA 拖影）；极光入水反。警示：STARS_COVERAGE 死设置、cubic_uv 与 Astra 投影决策冲突。

### 6.13 Aurora Astral 1.0（MakeUp 深改）
星界裂缝（cosmic_rift.glsl:208-346 缎带几何+845-935 图集星云+479-502 八面体星点+363-477 有符号裂纹场；3 帧 2048 图集 40 分钟交叉溶解）；解析球巨型行星 Colossus（colossus_planet.glsl:110-385，白天层，与夜间裂缝互斥）；预乘 alpha 统一合成（:20-21,1320-1346）；反射掩码增亮（water.glsl:318-328）。死代码：lib/atmosphere.glsl 定义了 Rayleigh/Mie 但无人 include。

### 6.14 Eternal Prism 0.6.0-beta
33 文件小包；夜空特色以「星夜」为卖点但实现规模小：极光是方向域 fbm 色带函数（composite.fsh:47-53，:172 直接调用），无 raymarch；星野/星云/银河带在 composite.fsh:63-98，机制与 4.2/4.3 已列条目同族，无独立新机制（细节从略；3D 云/活水属功能向）。

## 七、许可与借鉴方式

- 本轮 14 个对象中未见明确允许代码级复用的新许可（AuroraRT 为 Complementary License 1.6、Aurora Astral 为 MakeUp 系深改、AstraLex/Insanity 为 BSL 系、Kappa/Nostalgia 为 RRe36 保留权利、CR/CU 为 Complementary License）。
- 一律思路级重写并登记 `Astra/THIRD-PARTY.md`；星空本体已是 CR r5.9 移植（THIRD-PARTY 已有记录），后续从 CR 谱系扩展沿用同一口径。
- 贴图方案（AstraLex 星空板、Solas/Photon 银河贴图）需自备素材或离线烘焙，注意素材许可。

## 八、无法判定与实机验证清单

1. 所有观感结论均源码级推断，采纳前需实机 A/B（尤其极光各风格的取色与 Astra 夜色调的适配）。
2. Photon 极光像素路径（colortex9/10→d2 上采样→11/12→d4）只核对到 d2 读写声明，未逐行确认。
3. Solas milkyWay.png 的 alpha 是否承载额外信息；Solas 包内无版本串，版本归属未定。
4. Aurora Astral 星云图集为 11.7MB 生成 PNG，「40 分钟溶解」的实际观感与显存代价未验证。
5. CR 双包解压目录 diff 仅 1 行不同，是否与上游发行版一致未复核（疑为整理产物）。
6. worldTime/worldDay 引入后与 Astra 现有 CPU 时间表达式的归一化口径需对齐（worldDay 变化时刻的跳变处理）。
7. 银河贴图若离线烘焙，分辨率/暗带对比度与 1 次采样的观感需实机验证。
