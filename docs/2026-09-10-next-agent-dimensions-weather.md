# 最新画面反馈：末地、下界与降雨续作清单

这是当前优先交接入口。用户要求先完整记录待办，以便额度中断后由其他 Agent 接替。所有未明确标为完成的项目均未完成；旧文档的“已实现”不代表视觉达到要求。

## 用户最新结论与目标

末地目前可接受，但恒星太小，整体宇宙感不足；主岛还需提亮；星星太多、闪烁太快。下界基础环境过暗，缺乏光影的空间感。降雨过密、过整齐，近镜头遮挡严重；积水数量过多；河流海洋水方块也要有雨滴击中效果；原版蓝色溅水粒子仍需去除或替换。

## 待办（执行者逐项更新，禁止笼统写全部完成）

- [x] R1 从官方作者/项目页面核实并下载最新 Complementary，记录版本、下载来源、获取日期与源码位置。用途：群系颜色和基础环境。
- [x] R2 同样获取最新 Bliss。用途：体积雾、烟柱和空间层次；不要把噪声重新贴到地形端点。
- [x] R3 同样获取最新 Solas。用途：熔岩、普通火、灵魂火等彩色光；比较 Bliss 对应实现，选择可落地的光源表示和传播路径。
- [x] E1 恒星成为有规模的宇宙视觉主体：扩大角尺寸，设计表面、边缘、日冕与周围空间的层次，不仅是放大小白圆。保持无末地大气云；星云可保留。恒星方向必须与地形阴影一致。— 角半径 0.019→0.072（约 8.3° 角直径），加表面 cell 纹理、limb 明暗、11 瓣流苏日冕与 halo；仍以地形阴影同一 `lightVector` 定位。
- [x] E2 适度提高末地基础亮度与恒星受光，保留阴影和黑曜石材质层次，不能通过整体泛白处理。— 地形亮度 ×1.22，走 `end_lighting` 的平方根组合，不是整体加白。
- [x] E3 减少恒星背景星点数量，降低闪烁速度；调查 floor 网格随时间平移是否让星点重生成，而不是实际闪烁。静态星位配低频独立亮度变化。— 星点网格常量 1228.8→850，阈值 0.75→0.82 且乘性提到 8；删除 `coord + time*0.001` 造成的逐帧位置重算（原“floor 网格平移”就是它），闪烁改为每颗星独立低频正弦（周期约 26 秒）。
- [x] N1 参考最新 Complementary 修正下界基础环境亮度，保留五群系差别和跨群系渐变。— 照明入口改用 `nether_palette` 直接取值，去掉重复 sRGB 解码；五群系权重与 `smooth(...,8,8)` 跨群系渐变保留。
- [x] N2 从 Bliss 梳理体积雾/烟柱：沿射线积分、密度所在空间、遮挡、颜色和高度层次，注明要新增的 pass/纹理/数据。不采用表面终点采噪声冒充体积效果。— 接入 Bliss Stable 原噪声与沿程积分（`nether_volume.glsl`，16 步、`borderFogDistance`∩12×16 长度），plumes/haze/ceiling 三段独立吸收与散射；素材为原文件（sha256 一致）。
- [x] N3 从 Solas/Bliss 梳理熔岩、火焰、灵魂火彩色光：发光材质分类、光源位置表示、邻近表面照明和遮挡；不能把所有方块光统一染色冒充不同光源。— 自写受限子集：64³ 占用/光源体积、同帧 8 步传播、火/灵魂火/熔岩独立材质与颜色、固体（bit 8）阻挡传播、空单元才扩散、逐帧帧戳（bit 16）使未加载区块自动失效。**不是 Solas 的完整体积**（无 128+ 档、无跨帧历史、无 LPV）。
- [x] W1 降雨减量、打散规律排列：控制每片雨幕覆盖率，随机位置/长度/出现相位，近镜头淡出。调查 weather UV 拉伸与重复导致的长整齐线条；不仅调透明度。— 雨滴改由世界高度 + 时间驱动（去掉被拉伸的 UV.y），按世界列哈希打散，覆盖率约 22%，近镜头 `smoothstep(1.8,5.5)` 淡出。
- [x] W2 积水改为稀疏、成片、尺度更大的低洼视觉分布；保留露天、向上面、湿度与干燥限制，避免全地形密集小点。— 噪声频率降到 1/4（成片尺度约 10–20 格），阈值 0.16–0.48 → 0.43–0.66；实测该噪声下覆盖约 19%（峰值）至 35%，仍受湿度/天光/向上法线约束。
- [x] W3 河流海洋水方块接入降雨圆环/扰动：与原水波叠加；用雨量、天空暴露与表面朝向控制；不改变已经修复的水波纹理绑定和折射路径。— 水面法线叠加 `astra_puddle_normal` 的 xz 分量，按雨量与天光暴露缩放；独立噪声绑定与折射路径未动。
- [x] W4 定位原版蓝色溅雨粒子的实际渲染入口/材质识别方式，去除或替换为中性透明水花；不能误删其他蓝色粒子、药水或水下特效。— 引擎侧确认无粒子类型 ID（Iris 无 `particle.properties`，`gbuffers_particles*` 只管半透明层），改按图集精灵区域识别：`assets/minecraft/particles/splash.json` 仅 splash_0..3 四帧 8×8，位于粒子表最外行/列，故取 UV>0.875 的 6% 区域，把蓝色偏置换成中性冷灰并把 alpha 降到 55%。**待实机确认区域是否命中**。
- [ ] D1 更新第三方来源与实际完成记录，执行必要的着色器编译；同步已完成改动到整合包 Astra。编译结果不等于画面满意。— 台账与 QA 记录已更新；编译已过（见下）；同步到实例尚未执行。

## 当前源码与入口

项目：C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发
安装目录：D:/zhenhebao/.minecraft/versions/生电优化整合包 (Fabric)/shaderpacks/Astra

- 末地：Astra/shaders/global/dimension/end.glsl；program/scene.glsl；program/deferred.fsh；shaders.properties 的 world1/shadow。
- 下界：global/dimension/nether.glsl；lib/uniforms.glsl；shaders.properties 的 astraNether 五群系权重。
- 下界体积光（N3）：program/shadow.vsh（imageAtomicMax 写入）；world-1/shadowcomp.csh 与 shadowcompA..H.csh（9 步传播）；program/nether_light.csh（传播内核）；global/dimension/nether_colored_light.glsl（消费）；shaders.properties 的 `NETHER_VOXEL_LIGHT` 选项与 `image.*`/`compute.*` 指令。
- 下界体积雾（N2）：global/dimension/nether_volume.glsl；textures/bliss-nether-noise.png。
- 降雨：program/lit.fsh 的 ASTRA_WEATHER 分支；gbuffers_weather.*；program/sky.fsh。
- 积水与雨环：global/atmosphere/weather.glsl；program/deferred.fsh。colortex3 的 R 为光照标记，GB 为积水法线，A 为积水覆盖。
- 水面：program/water.glsl、global/water/surface.glsl、program/lit.fsh 的 ASTRA_WATER_PASS。
- 粒子（W4）：gbuffers_textured_lit.*（原版不透明粒子路径）与 gbuffers_particles_translucent.*（半透明路径）共同 include program/lit.fsh；`ASTRA_PARTICLE` 分支即识别代码。
- 旧参考：_analysis/Complementary r5.9、_analysis/Solas Shader V2.2b。**最新版已获取**，见下节。

## 必须保留的已知修复

主世界阴影用户已确认改善：shadow.fsh 显式输出避免透明叶片因数据 alpha 被裁掉；不要改回旧 gl_FragData 写法。可见几何/阴影共用植被摆动。水波独立 steadfastWaterNoise/solasWaterNoise 绑定保留。末地 deferred 全屏背景填充修复了黑色天空分界，world1 阴影已开启。

## 最新截图

- 末地恒星：C:/Users/杨铭/AppData/Local/Temp/codex-clipboard-7ed905c3-62f4-4114-ad64-a7cf86e2116c.png
- 末地主岛：C:/Users/杨铭/AppData/Local/Temp/codex-clipboard-b280fa9e-f7c0-43d3-af3c-76403f0f2055.png
- 雨天：C:/Users/杨铭/AppData/Local/Temp/codex-clipboard-2c1c7b3b-adf3-4396-a1d8-7440144909cc.png

## 本轮已获取的参考源码

- bliss-shader 2.1.2，发布：2025-11-23T03:14:46.231498Z；目录 `_analysis/latest-2026-09-10/bliss-shader`；[下载来源](https://cdn.modrinth.com/data/ZvMtQlho/versions/kC2Y8q1P/Bliss_v2.1.2_%28Chocapic13_Shaders_edit%29.zip)。
- solas-shader 3.7b，发布：2026-08-23T09:13:09.670686Z；目录 `_analysis/latest-2026-09-10/solas-shader`；[下载来源](https://cdn.modrinth.com/data/EpQFjzrQ/versions/KcfQaN5J/Solas%20Shader%20V3.7b.zip)。
- complementary-reimagined r5.9，发布：2026-09-02T10:48:56.090028Z；目录 `_analysis/latest-2026-09-10/complementary-reimagined`；[下载来源](https://cdn.modrinth.com/data/HVnmMxH1/versions/111gsk0f/ComplementaryReimagined_r5.9.zip)。
- complementary-unbound r5.9，发布：2026-09-02T10:49:24.206713Z；目录 `_analysis/latest-2026-09-10/complementary-unbound`；[下载来源](https://cdn.modrinth.com/data/R6NEzAwj/versions/w6dISYOd/ComplementaryUnbound_r5.9.zip)。
- bliss-Stable Stable，发布：branch snapshot 2026-09-10；目录 `_analysis/latest-2026-09-10/bliss-Stable`；[下载来源](https://codeload.github.com/X0nk/Bliss-Shader/zip/refs/heads/stable)。

---

# 接替轮（2026-09-10 晚）：交接复核与 N3 可行性修复

## 复查结论：交接文档自述与代码不符之处

1. “N3 代码已加入”不成立：`world-1/shadowcomp1..8.csh` 用**数字后缀**，而 Iris 的 compute 数组只读 `<name>` 与 `<name>A..Z`（`ProgramSet.readComputeArray`，27 槽）。这 8 个传播步从未被加载，实际只有 step 0 生效。已改名为 `shadowcompA..H.csh`。
2. 同因：`shadow.vsh` 的体素写入缺 420+ 守卫，`NETHER_VOXEL_LIGHT` 是全局选项，导致主世界与末地阴影着色器也声明 `uimage3D` 并编译失败（离线编译 3 处 FAIL）。已加 `DIMENSION_NETHER &&` 守卫。
3. 离线编译工具的 Iris 前置宏与 Iris 1.11.2 不一致：`MC_RENDER_STAGE_SUN/MOON/CUSTOM_SKY` 写成 3/4/7，真实枚举序数是 4/5/3（`WorldRenderingPhase`）。这会让 `program/sky.fsh` 的星/日/月分支永久不命中。已按枚举全量重写并在 `check_pack.py` 加 SC-31 防漂移。
4. `compile_glsl.py` 只编译 vsh/fsh 对，`.csh` 零覆盖；`check_pack.py` 对 `image.*`/`compute.*`/`features.*` 一无所知。两者已扩展。
5. `iris.features.required=CUSTOM_IMAGES` 会在特性不可用时弹 `FeatureMissingErrorScreen` 并整体禁用光影；已改 `optional` 并把 `image.*` 指令放进 `#ifdef NETHER_VOXEL_LIGHT`（否则 Iris 对“有 image 无特性位”直接抛 `IllegalStateException`）。
6. 台账 astra-only 计数停在 16，实算 22；`astraSolas*` 记为 9 条，实为 11 条。已更正。
7. `lib/water_buffer_formats.glsl` 的 `const int colortex*Format` 曾被记为“Iris 禁止”，实为误判：Bliss 与 Complementary 两个参考包都这么写。SC-27 规则已改为“名称合法 + 字面量或全大写 token + 每缓冲仅一处声明”。

## 本轮实际改动

- **Iris 可行性**：`optional` 特性位；9 个 compute 各自 `compute.world-1.<name>.enabled=NETHER_VOXEL_LIGHT`；图像声明与代码同门控；新增 `NETHER_VOXEL_LIGHT` 选项（默认开、PERFORMANCE 档默认关）。
- **N3 正确性**：占用编码改为 bit 0-7 光源种类 / bit 8 固体 / bit 16 帧戳；只有空单元扩散、固体阻挡、邻居无本帧帧戳则跳过（避免跨未加载区块漏光）；消费端按帧戳忽略过期单元。
- **N2 合成**：确认 `result*volume.a + volume.rgb` 即单次散射形式，双雾层各自持有透射率属预期分层而非重复吸收；加入三个密度标度常量（plume 0.55 / haze 0.30 / ceiling 0.35）并把该结论写进注释，避免下轮再当 bug 修。
- **W4**：见上方条目，改为图集区域识别 + 中性化。
- **工具链**：`compile_glsl.py` 支持 `.csh`（自带 4.3 上下文与 `compute_capable` 报告）、`--no-compute`、修正 `--undef` 对默认开启选项的处理；`check_pack.py` 新增 SC-29（image 字段合法性/数量上限/采样器被引用）、SC-30（compute 目录与字母后缀规则、无门控告警）、SC-31（渲染阶段名合法性）；`walk_shader_files` 纳入 `.csh`；第 6 项改为扫描整棵 include 树（修掉 `lib/solas_water.glsl` 声明被漏看造成的误报）。

## 验证结果（可复现）

- `python qa/tools/compile_glsl.py` → `linked=261 failed=0 compute=27 compute_capable=true`（日志 `qa/glsl-2026-09-10-p0-final.log`、`...-w4-particle.log`）。三档 261 个程序 = 234 个 vsh/fsh 对 + 27 个 compute（9 步 × 3 档）。
- 关闭态回退：`python qa/tools/compile_glsl.py --undef NETHER_VOXEL_LIGHT --no-compute` → `linked=234 failed=0`（与 Iris 在选项关闭时不加载 compute 一致）。
- `python qa/tools/check_pack.py` → **0 FAIL / 2 WARN / 9 PASS**（历史 4 项 FAIL 全部消除；余下 2 项为已知 WARN：VOXY_SUPPORT 未接线、无 staged texture 指令）。
- 改名前后 compute 均编译通过（`qa/glsl-2026-09-10-compute-first.log`、`...-compute-renamed.log`）。

## 下一步（交回用户实机确认，未测试项不得写成已完成）

1. 同步到实例并实机进世界：`python qa/tools/sync_to_instance.py`。
2. 下界看三件事：体积光是否有颜色空间感（火/灵魂火/熔岩应分别偏橙、青、橙红）；传播是否被墙挡住；走动/换区块后有无残留光斑（帧戳机制的直接判据）。
3. 雨天看三件事：雨滴是否不再成整齐长条；积水是否成片且稀疏；河流/海洋水面是否有雨环。
4. 溅水粒子：确认蓝色是否消失，且**未误伤**其他蓝色粒子（药水、水下、sculk 灵魂）。若区域未命中或误伤，只需调 `program/lit.fsh` 的 `ASTRA_PARTICLE` 分支里的 UV 区间。
5. 末地：恒星大小/层次是否够，星点数量与闪烁是否合适，主岛是否提亮且仍保留黑曜石层次。
6. 仍未完成：D1 的“同步到实例”一步，以及以上任何视觉不达标项的回调。

## 第二次复跑（同日深夜）：N3 逻辑仿真与 VOXY 选项修复

- 新增 `qa/tools/nether_voxel_model.py`（离线复刻占用编码 + 九步传播，4 条不变量）。它抓到两个
  编译/静态校验发现不了的缺陷：
  1. **传播循环从未执行**：写入端对普通方块写 `kind=1`，传播判据 `id==0`，两者永不相等 →
     8 步扩散是死代码，彩色光只停在光源自身格子（这正是"下界缺乏光影空间感"的根因）。
     已改为：空气写 `kind=0`、固体写 `kind=1`，判据 `(id == 0u) && !solid`。
  2. **帧戳偶数帧为 0**，与"从未写入"的图像初始值撞车，未渲染格子被当成新鲜空气 → 光会穿过
     未加载区域。已改为 `(1 - (frameCounter & 1)) << 16`，在 0b01/0b11 间交替，永不为 0。
  修后仿真四条不变量全 PASS（墙后 0.0000、空气受光 1.0800、衰减 d1 1.0800→d8 0.1083→d9 0.0000）。
- **实机日志实证缺陷**：`latest.log` 记录
  `Unable to resolve shader pack option menu element "VOXY_SUPPORT"`。该选项只在 `lib/settings.glsl`
  声明，而 Iris 的选项扫描跳过此文件，故选项被丢弃。已在 `lib/uniforms.glsl` 加引导引用
  （附带说明：voxy.json 仍是空 patch，C5 落地后应替换）。`check_pack` 第 11 项由 WARN 转 PASS。
- 复核结论修订：**下界体积光在本轮之前是完全无效果的**，不是"观感偏弱"。实机若仍看不到空间感，
  应查传播是否真的在跑（选项需开、须在下界、阴影渲染距离覆盖光源），而不是继续调强度。
- 复跑证据：`linked=261 failed=0 compute=27`（qa/glsl-2026-09-10-n3-fixed.log）；
  关闭态 `linked=234 failed=0`（...-n3-fixed-off.log）；`check_pack` 0 FAIL / 1 WARN / 10 PASS。
- 实例已再次同步（缺失 0 / 内容差异 0）。
