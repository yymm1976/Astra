# Astra 审查总报告与修复工单（GLM-5.3-Flash 汇总，2026-09-20）

**性质**：本文件是三方审查（GLM-5.3-Flash / Qoder / 混元四，含各方二次更新）的**最终汇总**，同时是本次修复的**执行工单**。核验依据见 `2026-09-20-glm53flash-verification-review-r2.md`；本报告只保留"结论 + 修复动作"。
**修复纪律**：每项修复后跑 `qa/tools/check_pack.py` 与 `qa/tools/compile_glsl.py` 全档矩阵；视觉类改动（光束标定、水色、植被透光）标注"需实机对拍"，本轮只保证源码正确性与编译。

---

## 1. 三方收敛的核心结论（全部经源码与算术复核）

1. **无 P0**；构建健康（267 linked / 0 failed；check_pack 0 FAIL / 1 WARN）。
2. **两个"一直没实现"的水效果，根因已三方独立收敛**：
   - 水下光束：链路闭合，量级被四层衰减压没——方向门正午恒零（`light_shafts.glsl:48` 用空气太阳向量）、采样只覆盖 ~18.6/40 格、内切圆剔除 21.5% 样本、焦散调制³把能量压到 1–5%；
   - 青绿→深蓝：默认档 BALANCED 谱序绿(0.06)<蓝(0.10) → 深水收敛于绿；`clamp(depth+1,0,16)` 冻结深端；空气侧无 in-scatter 且深水回退**恒为零**（F-40）。
3. **最大确定性性能浪费**：`colortex3` 清屏 alpha=1.0（掩码量程最大值）让**所有水面与半透明像素**在 deferred 通过积水门并跑一次注定被丢弃的 96 步反射（F-42，GLM F2 的扩大版）。
4. **SC-39 静默回归**：`lit.fsh:362` 写错缓冲，叠 blend 使 colortex5 的 rgb+a 双双失效（F-01/C1）。
5. **两个方向性语义错误**：植被"透光"乘子实际恒变暗（F-08/C3）；晨雾权重端点写反（F-09）。
6. **A1**：水下像素白算整套 tonemap+sRGB（动态分支无法被编译器消除）。
7. **水下光束 march 每像素 504–720 次纹理采样**（9 tap × 4 高度 × 2 fetch = 72/样本，GLM 第一轮低估为 18，已按 Hunyuan C6/Qoder F-04 更正）——水下最贵单项。
8. 流程项：工作区 76 项未提交（本次提交即解决）、README 多处失实、零帧率实测、`qa/benchmarks.md` 全空。

**已否决的主张**（不再处理）：composite3 同缓冲读写"UB"（Iris flip 机制）；`#ifndef` 格式守卫"永真无意义"（说反）；"关焦散会黑掉光束"（实际是变亮变白，耦合方向记反）；deferred 恒开算未登记偏离（`design.md:493` 已记录）。**需实机探针后才动代码**：F-02（hand 与 deferred 的真实顺序）。

---

## 2. 修复工单（本批次全部执行）

### A. 缓冲与门控（正确性 + 最大性能回收）
- **A1** `lit.fsh`：删除 `:362`（colortex5.a 覆写），恢复"水面有效性"语义；重写 `:326-352` 三条失实注释；删除 `:371` 的 surfaceWet 死存储（变量保留供变暗用）。
- **A2** `settings.glsl:357`：`colortex3ClearColor.a` → `0.0`（掩码零值语义；`.r=127` 不动；唯一读者 `deferred.fsh:135` 已核）。
- **A3** `deferred.fsh:136-148`：四个权重因子并入门控，`weight > 0.001` 才调用 `puddle_reflection()`（F-15/F-42/C4 合并）。

### B. 水下光束（light_shafts.glsl / caustics.glsl / properties）
- **B1** 方向门：`refractSun` 提前计算，`VoL` 改用折射后太阳；删除循环后的第二段相位项与 `pow(VoU,1.5)`（up-look 已被 refractSun 排除）。
- **B2** 采样铺满 `maxDist`（去掉 `×0.5`）；内切圆判据改方形（与末地分支一致）。
- **B3** 焦散调制降采样：每样本改用 `solas_water_caustics`（72→10 fetch），归一为 `mix(0.25, 1.0, c)`；删除不再使用的 `astra_water_caustics_shaft_at`。
- **B4** 衰减与增益重标定：`/max(3.0,d*0.1)` → `/max(2.0,d*0.06)`；末端 `×(4+8·sun)` → `×(6+14·sun)`。**需实机对拍**。
- **B5** resolve 距离加权：四 tap 按 `depthtex0` 重建距离与 `rayLength` 差值加权（兑现 SC-33"距离加权重建"，`rayLength` 形参启用）。
- **B6** `size.buffer.colortex1` 恒 0.5（光束 march 与空气 godrays 同降 4×；注释说明下界/末地的已知闲置分配）。

### C. 水色（absorption.glsl / water.glsl / scene.glsl / design.md / lang）
- **C1** 谱序：BALANCED → `(1.000, 0.100, 0.060)`、TROPICAL → `(2.000, 0.080, 0.055)`（深水收敛蓝）；深度上限 16 → 24。
- **C2** 空气侧受控 in-scatter：`water_surface_medium` 增加 `incidentLight` 形参与 `body×(1−T)` 项（`water_body_color` 常量）；三处调用点同步；`deepFallback` 由恒零变为水体色（F-40 一并解决）；重写 `:55-57` 禁令注释。
- **C3** `design.md` 增补一条日期决议：水色分工更新（空气侧=青绿→深蓝行程）。
- **C4** lang：`WATER_CHARACTER` 三档写明实际观感（冷=深蓝 / 均衡=青绿→深蓝 / 热带=浅青）。

### D. 光照与后处理语义
- **D1** F-08：植被透光改 `visibility = mix(visibility, vec3(1.0), t×0.35)`（只加不减、可封顶）。**需实机对拍**。
- **D2** F-09：`fog_morning_air_weight` 端点反转 + `scene.glsl:150` 直接使用该权重（净端点回到文档值 0.62/0.22）。
- **D3** F-44/N-1：背光面不参与夜间失色（两处调用点按 `facingAway` 归零）；重写 `:358-360` 的 shadowFade 注释（正午/晨昏写反 + 自相矛盾）。
- **D4** A1：`final.fsh:88-91` 三元二选一结构。
- **D5** F-27：End 暗角/抖动改为叠加式（先按选项算，再叠加末地固定的 void 保护），选项在末地恢复语义。
- **D6** F-22：下界 skybasic 改写黑（deferred 已有重算，消除双算）。

### E. 卫生与死链（一次清完）
- **E1** F-19：`caustics.glsl` 守卫 `#endif` 移到文件尾。
- **E2** F-28：删 `biomeTemperatureSmooth/HumiditySmooth`（uniforms+properties）+ 改 `fog.glsl:225-226` 注释。
- **E3** F-32：删 `sunrise/moonrise`（properties 两行 + uniforms 声明 + 相关注释）。
- **E4** F-33：删 `lib/noise.glsl` + 两处 include + `noisetex` 声明 + `textures/noise.png`。
- **E5** F-52：删 `dither2` 形参、`end_sky` 死形参、`ReflectedFog` 恒真守卫。
- **E6** F-53：7 处 `SHADOW_FILTER_MODE == 1` 字面量改 `SHADOW_FILTER_HARDWARE` token。
- **E7** F-36：字面整数幂迁移（fog/end_system/shadow.fsh:65/lit/water/weather/deferred/bloom_resolve/end/overworld 等热路径；twilight 的 180/1400 需新助手，本轮保留 pow 并注记）+ `pow.glsl` pow100 注释更正（15 次乘）。
- **E8** F-39：`srgb_decode` 函数内钳负。
- **E9** F-14：deferred/end_sky_buffer 分支内采样改 `textureLod(…, 0.0)`。
- **E10** F-34/F-35：两处注释数值更正。
- **E11** F-23：`world-1/shadow.vsh` 补 `#version 430` 理由注释（imageAtomicMax 需 420+）。

### F. 配置与台账
- **F1** F-48/§12.2：`size.buffer.colortex7=0.25 0.25` + 注释。
- **F2** F-30：`SSS_STRENGTH` 默认 100 → 60（对齐 BALANCED，兑现"raw defaults = BALANCED"）。
- **F3** F-37：THIRD-PARTY.md 三处漂移修正 + 补 `pow.glsl` 行。
- **F4** F-41/A2：README 七处事实更正（三对标方向、compute、SKY_MODE、分级值、profile 表、状态段）。
- **F5** F-50/S1 + A6/A10/A11：`design.md` 一条汇总决议（varying 预算重订、compute/彩光例外、global→global 子分层承认、SKY_MODE 出厂=渐变）。

### G. 文档
- **G1** A5：新增 `docs/2026-09-17-sc39-puddle-reflection.md`（沉淀三次返工与教训）。
- **G2** N-2：新增 `qa/open-premises.md`（未决前提台账：F-02 探针、F-31 剩余半环、跨驱动、实机验证积压）。

### 明确不在本批次（附理由）
- F-02（pass 顺序）：需实机探针定论，见 open-premises。
- deferred 条件化 / composite3 并入 final / rainy_air 降采样 / 天空 LUT：性能优化且涉及行为取舍或前置决议，列为下一批（先拿帧率基线）。
- F-11（fade=1.0）、F-20/F-53 的零引用 token、cost_census 接门禁：既往已裁决保留 / 工具化另批。
- `UNDERWATER_SHAFT_SAMPLES` 不降档（三方一致：先修量级再谈采样数）。
