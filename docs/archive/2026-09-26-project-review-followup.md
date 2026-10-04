# 2026-09-26 全量源码审查与直接修复（续）

本轮针对工作区当前实现，保留开始时已有的未提交修改。审查范围包括三个维度的着色器入口、共享渲染模块、缓冲读写与透明混合、阴影及体素光、水体、大气、末地天空、后处理、选项和预设、中英文界面、资源引用及项目工具源码。此前的日期报告只作背景。

## 本轮修复

| 优先级 | 问题与触发条件 | 已实施修复 | 文件（相对 `Astra/shaders/`） |
|---|---|---|---|
| P1 | 水下焦散生成最高 2.60 倍的增益，但阴影颜色附件沿用归一化格式；接收端再次把结果限制到 1，亮斑增益在两处丢失 | 主世界启用焦散时声明 `shadowcolor0Format = RGBA16F`；接收端保留超过 1 的直射贡献，只限制环境光混合权重，避免负环境光；夜间去饱和仍按 0–1 可见度处理 | `program/shadow.fsh`、`global/lighting/diffuse.glsl` |
| P1 | 粉雪状态 `isEyeInWater == 3` 没有对应雾分支；天空无几何深度，跳过了岩浆、粉雪和失明遮挡 | 在共享介质入口处理粉雪；在天空、云及日月合成之后应用对应遮挡，并把同一结果写入天空副本；不在这些状态下向地形叠加平面云 | `program/scene.glsl`、`program/deferred.fsh` |
| P1 | 失明时雨中散射与空气光束仍在雾之后叠加；末地水下提前返回水介质，绕过失明；末地岩浆分支还会覆盖失明颜色 | 关闭失明状态下的两条空气散射路径；让非主世界水下进入已有失明处理，并统一末地岩浆与失明的优先顺序 | `program/deferred.fsh`、`program/scattering.fsh`、`program/final.fsh`、`program/scene.glsl`、`global/dimension/end.glsl` |
| P2 | 水下光束只判断阴影贴图的方形 XY 边界，未处理有效投影圆、深度范围与边缘衰减 | 使用共享 `shadow_coverage()`，范围外不读取阴影，边缘按覆盖率衰减 | `global/water/light_shafts.glsl` |
| P2 | 手持物品按 `currentRenderedItemId` 读取 100xx 材质类，项目却没有物品编号表，玻璃、冰、末地石、黑曜石和发光物品的专用分支缺少输入 | 新增 `item.properties`，沿用现有材质类；不把未激活灯、矿石、锚和传感器的物品形式当作激活的发光体 | `item.properties` |
| P2 | 下界雾代码和界面说明支持 0，实际选项取值却从 25 开始 | 补全 0–20 的选项取值，默认仍为 70 | `lib/settings.glsl` |
| P2 | Voxy 仍为空适配入口，设置说明却宣称能启用远景渲染 | 中英文界面明确标为尚未实现，说明开关当前不产生渲染效果 | `lang/en_US.lang`、`lang/zh_CN.lang`、`lib/settings.glsl` |
| P2 | 雨纹生成工具在模块导入时立即生成并写入图片，输出位置依赖调用目录；倾角摘要把编码后的蓝通道直接当作法线 Z | 写入移至显式 `main()` 入口，输出定位到项目纹理目录；倾角计算先将通道解码回 −1–1 | `qa/tools/gen_rain_ripple.py`（相对项目根目录） |

新增物品表的来源说明同步登记在 `Astra/THIRD-PARTY.md`。

## 依据与范围

- Iris 的 [物品编号表说明](https://shaders.properties/current/reference/miscellaneous/item_properties/) 明确说明 `currentRenderedItemId` 来自 `item.properties`，与方块表分开。
- Iris 的 [玩家状态说明](https://shaders.properties/current/reference/uniforms/status/) 将介质值 2、3 分别定义为岩浆和粉雪。
- Iris 的 [阴影颜色附件说明](https://shaders.properties/current/reference/buffers/shadowcolor/) 说明默认格式为 RGBA，通常使用 RGBA8；[格式指令说明](https://shaders.properties/current/reference/constants/buffer_format/) 支持对 `shadowcolor0` 显式指定格式。此次修改同时处理了写入格式和接收端数值范围。
- 当前着色器 include 与配置中纹理引用均可定位到文件；两份语言文件各有 186 个不重复键，键集合一致。工具源码的入口与模块级写入行为也纳入审查。

浮点阴影颜色附件每像素由通常的 4 字节增加到 8 字节。2048² 时每张附件增加约 16 MiB，实际分配量还取决于引擎的附件副本；该格式仅用于开启焦散的主世界链。下界和末地保持原格式。

本轮结论来自源码、资源与接口文档审查，没有启动游戏，因此不对修改后的画面观感、加载情况或帧率作结论。Voxy 仍是未完成功能，本轮修正的是界面承诺。
