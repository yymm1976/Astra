# SC-35 视觉回归根因修复（2026-09-08）

本轮依据：用户 6 张实测截图（1/2/3/5 为 Astra，4/6 为模范光影）、磁盘与 Git 当前状态。当前模型独立完成，未使用子代理。探针与截图采样证据在 `qa/sc35-probe/`（results.json、shore/heldlight/waves PNG、f32 帧）。

## P0 根因档案（按任务 §十四格式）

### A. 跟玩家移动的亮斑（图 2 准星左侧）

- **现象**：草地上一片明显较亮区域；固定场景与太阳，只移动玩家时亮斑跟着走。
- **根因**：`gbufferModelViewInverse[3].xyz` 在 26.2/Iris 1.11.2 上是**非零的 render-origin 平移 T**（随玩家在 16 格 section 内滑动、跨界跳变；Mellow `lib/transformations.glsl:40`、Solas `lib/util/ToWorld.glsl:2` 均显式处理，本包 SC-19 旧注释亦有记载）。SC-34 把 `lit.vsh` 的 playerPos 从纯旋转改为全仿射变换后，playerPos 携带 T；`held_light_strength()` 用 `length(playerPos)`（diffuse.glsl:198），火把光球中心从玩家脚下偏移到 −T（最多约 27 格）。
- **首次出现的 pass**：`gbuffers_*` → `program/lit.fsh`（不透明光照，blocklight 合成），**不是 shadow map**。
- **为什么随玩家变化**：T 是相机 section 原点函数，玩家移动即变；光球随 −T 在视野中滑动。
- **实测**（qa/tools/sc35_probe.py，真实 GLSL）：修复前带 T 光球质心偏移 (−64.3, −24.9) px、峰值 1.18 HDR（喂 bloom）；修复后与 T=0 完全一致 (−0.5, −71.5) px、峰值 0.32。
- **具体修复**：transforms.glsl 确立契约——`view_camera_relative`/`camera_relative_view` 只用矩阵旋转部分（T-free）；`player_shadow` 内部显式 +T（阴影 pass 在 T 空间光栅化）；`shadow.vsh` 统一用 `gbufferModelViewInverse[3]` 减/加平移。`shadowModelViewInverse[3]` 含逆光源视图平移，不能替代 render-origin T。
- **防回归**：契约写在 transforms.glsl 注释；凡新增 playerPos 消费者不得再假设全仿射含 T。

### B. 跟视角上下移动的明暗断层（图 3 左下）

- **现象**：水中浅滩与深水之间存在硬性明暗分界，俯仰视角时分界线跟随画面移动。
- **根因**：`water_sample_path` 的二元拒绝（侧带 ±0.02 格）在折射命中岸线/界面上方时将整条路径直接切到深水 fallback，没有中间态。磁盘中一版未完成处置又把查询换成了 `depthtex0`，会把包含透明几何的最近深度与 deferred opaque 色副本错配，必须纠正；它不是原始根因，也不是可保留的修复。
- **首次出现的 pass**：`gbuffers_water`（`program/water.glsl` 折射路径），同样不是 shadow map。
- **为什么随视角变化**：折射命中面与拒绝边界由视线-界面几何决定，俯仰改变命中分布，边界在屏幕上跟随。
- **实测**：探针水线场景复现饱和深蓝 fallback 带与硬边（shore_pitch20/42.png）。
- **具体修复**：场景查询统一读 **depthtex1**，与 deferred opaque `colortex4` 配对；±0.02 格 side 带改为连续权重。有效折射路径保留，置信度不足的部分混合到未偏移的完整 opaque 光路；只有该回退也失效时才继续退到深水/天空。
- **防回归**：水面场景查询固定使用 `colortex4 + depthtex1`；`depthtex0` 只在透明阶段结束后用于最近深度。禁止再以“直线路径置信度更高”为由覆盖有效折射。

### C. 浅水方块边缘白色 halo（图 2）

- **现象**：池塘/浅滩水缘一圈白色发光轮廓。
- **根因（三条叠加）**：
  1. B 的深水 fallback 硬切使水体突然变暗，浅滩亮床在对比下读作“亮环”；
  2. 焦散包络 `depthFade` 在 0–8 格随深度线性拉满，水缘浅滩一圈最热，焦散亮纹描边（直方图 p99=0.49、max=1.02，乘 directRadiance 后读作白色描边）；
  3. 焦散采样坐标同样被 T 污染（caustics.glsl:142 `playerPos + cameraPosition`），图案跟玩家爬。
- **首次出现的 pass**：`gbuffers_water`（C-1）与 `program/lit.fsh` 焦散叠加（C-2/C-3）。
- **具体修复**：B 的 `depthtex1` 配对与完整光路回退；焦散软肩封顶 `0.40·(1−exp(−raw/0.40))`；并令焦散在界面下 0.15–0.75 格从零建立，再于 1.5–8 格衰减；T 契约修复使图案世界锚定。
- **为什么修复后不复发**：界面处焦散严格为零且峰值有界，不再把量化水高边界作为最热点；锚定修复后图案不再随玩家移动。是否完全低于游戏中实际 bloom 阈值仍由新截图确认，不用静态估算替代实测。

### D. 植株/阴影边缘白色描边（图 5）

- **现象**：水草叶片及其附近阴影边缘的白色描边、地形棱线上的白色折线。
- **根因**：第一条同 C-2/C-3——焦散只放大受光表面，于是会描出植株与阴影边界。第二条来自 `astra_water_sun_source`：旧式 `opaqueVisibility * (1-allVisibility)` 在两张 PCF 图同为 0.5 的不透明边缘产生 0.25 假水面透光，进入 half-resolution 水下光束。
- **首次出现的 pass**：`program/lit.fsh` 焦散叠加；假透光首次出现在 `composite` 的水下太阳积分。
- **具体修复**：同 C；水面透光覆盖改为 `max(opaqueVisibility-allVisibility,0)`。粒子同步减量（密度 0.35→0.16、半径 0.30→0.24、强度 0.10→0.045、大亮粒子占比 0.65→0.35）。

### 坐标契约的统一说明

T 污染同时解释了：手持光球偏移（A）、波浪/焦散/粒子图案游动（世界锚定失效，探针 wave_anchor delta 修复前 0.374 → 修复后 0.017，残差为视差固有）、水下雾距离 ±16 格误差（`astra_fog` 的 `length(playerPos)`）、阴影覆盖淡出窗口平移。修复后 playerPos 全包恢复"真相机相对"语义（Mellow 约定），阴影生产/消费在 T 空间自洽（水高编码 T.y 在编解码两侧消去）。

## P1 修复（对标图 4/6 实测色值）

色值采样（qa/tools/sc35_image_analysis.py）：参考浅水 (59,123,144)、中水 (62,89,118)、深水 (39,75,90)、参考水柱 (28,83,145)、光束区 (48,120,188)；Astra 图 1 水柱 (17,83,145)（色相已接近但偏暗）、图 5 整体再暗约 1.7×。

- **水色**：吸收系数 BALANCED (0.080,0.015,0.005)→(0.140,0.030,0.010)（COLD/TROPICAL 同步）；散射改**光谱** σs=(0.011,0.026,0.036)·密度（红散射压低保住选择性）。深水不再只是"蓝乘黑"，而是 浅青→青蓝→深青→青黑 的光谱衰减。
- **波浪条纹**：逐层距离衰减（涟漪 0.15–2 m 层数十格内淡出，3–8 m 主波保留为远距离大浪）；反射环境光收敛随粗糙度（远距离坡度方差）从 0.22 升到 1.0，远水面收敛为平滑天空光泽而不是密集横纹。
- **水下太阳/亮度**：光谱 σs 直接抬高水柱绿/青分量与光束（朝太阳前向散射不变，g=0.60）；地形直射走 entry·transmission 同一吸收，方向性阴影保留。强度不动，先实测。
- **粒子**：见 D。

## 验证记录

- 探针（真实 GLSL，合成几何）：`qa/sc35-probe/results.json`；修复前后对照数值见上。基线通过临时回退 transforms.glsl 捕获，随后已恢复。
- 编译（RTX 4050 / OpenGL 4.6 / 驱动 572.83）：BALANCED+PERFORMANCE+ULTRA 225 组（`qa/glsl-sc35-final-profiles.log`）；SHADOWS/COLORED_SHADOWS/WATER_CAUSTICS/SCREENSPACE_REFLECTIONS/SCREENSPACE_REFRACTION/UNDERWATER_LIGHT_SHAFTS 关闭及 WATER_ABSORPTION=0、UNDERWATER_FOG_DENSITY=0 各 75 组（`qa/glsl-sc35-final-*.log`），全部 linked，failed=0。
- `python qa/tools/check_pack.py`：0 FAIL，2 条既有 Voxy WARN。`git diff --check` 干净。
- 同步：9 个文件写入 `D:/zhenhebao/.minecraft/versions/生电优化整合包 (Fabric)/shaderpacks/Astra`；逐文件比较 `Content differences after copy: 0`。

## 下一轮实测清单（用户）

A. 固定视角，前后左右移动玩家：原移动亮斑（准星左侧）应消失；手持火把时光球应贴在玩家脚下附近。
B. 固定位置只上下转视角：图 3 左下原明暗断层应消解为连续水深渐变。
C. 浅水沙地/池塘边缘：白 halo 应消失；允许正常的浅水高亮与焦散细纹（不再描边、不爬行）。
D. 水草/植物及其阴影边缘：白描边应消失；焦散呈柔和亮斑。
E. 高处看整片湖：青蓝→深青黑的水深变化；远水面无密集横纹。
F. 贴近水面：波纹大尺度、连续；折射形变自然；水线无深色硬带。
G/H/I. 水下背对/侧对/正对太阳：水体明显更亮、太阳方向可辨、朝太阳有青绿色光晕与光束。
J. 岸边树荫下：水下方向性阴影与光束并存。

未验证不宣称：以上观感项均待本轮游戏画面裁决；E2/E4 不放行，E3 无本轮帧率结论。
