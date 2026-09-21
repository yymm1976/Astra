# Astra

**Astra**（拉丁语：星辰）是一个 **Iris 专用** Minecraft Java 版光影包，设计哲学为 **"清爽原味 + 性能"**：不抢戏、快、细节克制，但在水、大气、色彩科学上达到一线水准。

> v1 开发中。效果三对标（SC-24 更正后口径）：水面 ≈ Steadfast、水下 ≈ Solas、整体色调 ≈ Refrax。

## 安装

1. 安装 [Iris](https://irisshaders.dev/)（含 Sodium）。
2. 将 `Astra/` 文件夹（或其 zip）放入 `.minecraft/shaderpacks/`。
3. 视频设置 → 光影包 → 选择 Astra。
4. 顶栏 profile 一键切换三档预设；详情见游戏内设置（七分类，zh_CN 全覆盖）。

**版本要求**：MC 1.21.x（含 1.21.4/1.21.5 方块集）与 26.1 / 26.2；仅支持 Iris（不写 OptiFine 回退）。远景仅支持 Voxy（实验性）。

> 26.x 兼容目前仅为设计声明：`MC_VERSION` 双版本守卫与 `iris.features.required` 尚未写入工程（D1 任务交付项），故 26.1/26.2 的实际可用性未经实机验证。

## 特性

- **极简前向管线**：全部主光照在 gbuffers 一次算完，无 TAA/G-buffer；下界体素彩色光为独立例外（9 个 compute 阶段 + 3 张自定义图像，NETHER_VOXEL_LIGHT 可关）；抗闪烁在源头解决（Nyquist 受限波形 + 足迹细节衰减 + IGN 抖动）
- **水系统**：多层流动法线水面、SSR（顶面专属，天空回退）、单跳折射（深度拒绝）、指数水下吸收（三档水性格）、6 层 crest 焦散、水下氛围
- **大气**：两套天空模型由 `SKY_MODE` 选择，**出厂默认不是 Minishita**——`lib/settings.glsl:85` 为 `SKY_MODE 1`（简易渐变），流畅/均衡两档都取这一档；Minishita 迷你物理大气（≈200 FLOPs）只挂在极致档（`shaders.properties:162` `SKY_MODE=0`）。另有 FogV2 雾家族、空气透视（晨昏地平线染色）、生物群系轻染色
- **光照**：自适应 normal-offset 彩色阴影（染色玻璃/水投彩影）、日光压制（替代自动曝光、无闪变）、静态阴影回退、植被透光与摇曳、手持光、闪电光照
- **色彩科学**：Uchimura/AgX/ACES/Reinhard-Jodie 四算子（水下始终使用 Solas 显示曲线）；当前出厂分级为 饱和 100/自然饱和 100/对比 102；全部风格参数集中在 `shaders/global/post/grading.glsl`
- **下界/末地一等公民**：独立光照路径与大气曲线，不是主世界参数回退

## 三档 Profile

| Profile | 目标（RTX 4050 @1080p） | 相对默认的取舍 |
|---|---|---|
| 流畅 | ≥144 FPS | 阴影 1024/192 格（实体 48），关闭 SSR/折射/Bloom/颗粒/高阶半透明 |
| **均衡（默认）** | ≥90 FPS | godrays 关；**"其余全开"不成立**——本档出厂关 8 项：云影、水下悬浮颗粒、自动曝光、体积光、体积光日面遮蔽、暗角、Voxy 支持、水下光束标定；其中 7 项三档皆关，只有体积光在极致档打开（`shaders.properties:160-162`） |
| 极致 | ≥60 FPS | 阴影 4096/256 格（实体 96）/8 texel 软化，godrays 开，平面云（均衡档同为平面云） |

profile 为完整显式配置（`shaders/shaders.properties`），游戏内顶栏一键切换。

## 已知问题（v1 开发期）

- **（以下为 2026-09-05 骨架期存档描述，已过时）** 特性清单是设计目标，不是当前画面：lib/ 与 global/ 的模块当时仅 8 个可达、lit/final 未接线。**当前状态（2026-09-21 复测）**：186 个编译入口、52/54 模块可达，lit/final 及主世界/下界/末地全链已接线出图（见 qa/glsl-audit-fixes.log 与 docs/2026-09-20 各审查报告）；剩余缺口为帧率实测、双版本冒烟与 Voxy 接线。出处为本次实跑 `python qa/tools/check_pack.py`（日志 `qa/checkpack-2026-09-21-b2.log`），第 4 项原样自报 `186 compiled entries, 54 lib/global modules, 52 reachable, 2 waiting on their owner task, 0 unwired-and-unregistered`——旧值 182 是 `b20abd0` 时的计数，此后新增入口使 HEAD 变为 186（对照见 `qa/b9-current-state-review-verify-2026-09-21.log:146`）；该项为 WARN（2 个待接线模块即上方 Voxy 缺口），整体 16 checks: 0 FAIL, 1 WARN, 15 PASS。
- **两个水模块暂无生产者**：`global/water/surface.glsl`（水面）与 `global/water/raytrace.glsl`（SSR）在任务计划中无人认领实现（E2 只声明集成、B1/C2/D2 供给项不含二者），已上报 SC-15。
- **无实机验证数据**：本机无可运行的 Iris 实例，加载冒烟、截图、帧率跑分均未执行（上报项 SC-6 待用户拍板）；上表性能目标为设计值，非实测值。
- **Voxy 支持为实验特性**：26.x 上的兼容性待 M3 实测（`VOXY_SUPPORT` 选项默认关）。
- **26.2**：新版本方块/实体差异待骨架冒烟确认（`block.properties`/`entity.properties` 头注跟踪）。
- **模组/自定义维度按主世界语义渲染**：v1 仅有根层默认链与 `world-1`/`world1` 两套下界、末地覆盖，未建模组维度专属壳与 `dimension.properties`；带自定义维度的模组包会继承根层效果（design.md §2.2 决议，专属壳列入 §11 v2）。
- **许可定位为个人使用**：发布前须走 design.md §9.3 发布闸门，见 `THIRD-PARTY.md`。

## 截图集

`../qa/screenshots/`（当前仅有占位文件——尚无实机截图；跑分与截图按里程碑 M1–M4 分目录补齐，见 `../qa/benchmarks.md`）。

## 许可与出处

- 当前为**个人使用**定位（`LICENSE` 为临时许可）。
- 第三方代码逐模块台账见 [THIRD-PARTY.md](THIRD-PARTY.md)：Mellow/MIT 逐行移植（6 个 lib 模块 + block 基础表）、Steadfast/GPLv3 + §7 附加条款的 custom uniform 表达式级移植（发布前须重写或整包转 GPL）、Refrax 与 Solas 仅分类思路级借鉴。

## 2026-09-06 开发状态

当前 lit/final 已接线，主世界/下界/末地共用统一入口；水面、折射、吸收、焦散、SSR及天空已集成。三档1080p的144/90/60 FPS是目标，尚无本轮游戏帧率证据，不作达标承诺。

Voxy暂不可用：在当前0.2.18-beta适配完成前，空白voxy.json用于不注册patch；打开VOXY_SUPPORT也不会启用LOD支持。原生几何可独立加载。模组维度仍继承根层主世界语义。

独立RTX4050驱动GLSL编译通过不代表Iris实际加载/版本兼容已通过；1.21.x/26.x仍需按实际运行材料确认。水下、水面、色调裁决目前均未放行。
