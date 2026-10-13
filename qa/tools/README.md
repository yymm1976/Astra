# 本地工具配置

工具从命令行参数、环境变量、本地 `qa/local_paths.json`、系统常见 Minecraft 目录依次取路径。仓库代码不指定某一台机器的盘符或实例名称。

`qa/local_paths.json` 已排除版本控制，可填写 `minecraft_root` 与 `minecraft_instance` 两个字符串路径。本地实例仅用于其对应根目录；指定另一个根目录时，不会沿用本地实例。此机器已指向包含现有库文件的游戏目录。

| 参数 / 环境变量 | 含义 |
|---|---|
| `--minecraft-root` / `ASTRA_MC_ROOT` | 含 `libraries/` 的 Minecraft 根目录 |
| `--instance` / `ASTRA_MC_INSTANCE` | 含 `mods/`、`config/`、`shaderpacks/` 的游戏实例目录 |
| `--iris-jar` | 调度读取工具使用的 Iris jar，覆盖实例自动查找 |
| `--java-home` / `JAVA_HOME` | 调度读取工具使用的 JDK 根目录；未指定时使用 PATH |
| `--dest` | 同步工具的明确目标包目录，优先于实例查找 |
| `--reference` / `ASTRA_STEADFAST_PROPERTIES` | Steadfast 0.8.0 的 `shaders.properties` 路径 |

自动查找遇到多个实例或多个 Iris jar 会要求明确选择，不会按文件名猜测版本。编译工具及其 GPU 辅助脚本仍依赖 Windows 的 LWJGL 3.3.3；取消固定路径不表示已完成跨平台驱动适配。

`inspect_iris_properties.py` 读取四档配置，用安装版本的 Iris 解析选项和布尔条件。三个画质档参与递增比较，NO_SHADOWS 单独要求关闭阴影。它读取调度配置，不测游戏帧率。下界体素光门按现行 `program.world-1/shadowcomp` 加数字 `1..8` 的命名核对，并要求每档与 `shaders.properties` 里的资源门 `SHADOWS && NETHER_VOXEL_LIGHT && BLOCKLIGHT_STRENGTH > 0` 一致；某档没有覆盖到的选项取 `lib/settings.glsl` 的声明默认值，数值无法解析时明确报错，不会当成通过。

`compile_glsl.py` 不带 `--profiles` 时仍只选择 PERFORMANCE、BALANCED、ULTRA。需要四档时明确指定 `--profiles PERFORMANCE NO_SHADOWS BALANCED ULTRA`；历史 270 次链接记录不能因此改称四档。

`water_ssr_cost.py` 复用完整 `gbuffers_water` 入口做独立 GL_TIME_ELAPSED 计量（RTX4050、1080p、BALANCED），读取当前生产源码：`native` 为现态，`native_floor20`/`native_full_coarse`/`native_refraction_old` 只恢复对应改动前的渐入窗口、粗查询密度或冗余读取作对照，另有 `native_no_ssr`/`native_no_refraction`/`native_sequential` 分量开关与 `full/waves/trace/transmit` 隔离函数体；`--scene shore|canopy|wall60`、`--pitch` 选择场景与视向，`--image` 输出渲染帧用于逐位比较。它不是 Iris 补丁后的游戏绘制，结果不换算 FPS。

选项登记、配置覆盖与条件分析共用 `shader_options.py`，支持带取值注释的 `#define` 和 `const float/int/bool` 声明。未标注取值的引擎常量不计入用户选项。配置覆盖会保留 const 的类型和分号，选项错误先于 JDK／库路径错误报告。`sunPathRotation` 的消费者单独登记为 Iris 天体／阴影矩阵，不要求它在 GLSL 中另有计算引用；其他 const 仍须有实际消费者。

`underwater_light_probe.py`、`underwater_shaft_gate_probe.py`、`airside_water_probe.py`、`sc35_probe.py`、`bloom_lod_probe.py`、`block_reflect_probe.py`、`block_reflect_gates.py` 均已停用：旧水体接口已经变化，`noise.png` 输入及 `getBloomTile()` 已移除，`astra_rock_emission()` 与材质 12–15 的岩石发光类也已从包中删除，旧工具的解析表达式或自带片元不再适用于当前实现；shafts-only 入口原是旧水探针的关键字参数，停用后的 `main()` 不再接收它。这些同名入口只向标准错误说明停用原因与现行模块位置并返回 2；导入时不读取光影文件、不创建输出目录，也不加载旧 GPU／图像依赖。旧结果只对应历史实现，不能描述当前光束、波面透镜、吸收链、下界彩光或 Bloom 捕获。

`nether_light_probe.py` 与 `nether_heat_glow_probe.py` 按 2026-10-04 处置停用 CLI（输出停用说明并返回 2）；`nether_voxel_model.py` 保留为记录历史常量的离线模型，其顶部 “shipping” 用词不代表当前参数（10-08 审核 F6）。`validate_shadow_water.py` 是明确标注的旧模型，其红并不代表当前回归。

## 参考副本

`_analysis/` 是可选的本地参考资料，不随仓库提供。用于表达式分类的文件来自作者发布的 [Steadfast 0.8.0](https://modrinth.com/shader/steadfast-shaders/version/0.8.0)：解包后将其 `shaders/shaders.properties` 传给 `--reference`，或放到默认位置 `_analysis/Steadfast-0.8.0/shaders/shaders.properties`。不要用其他版本代替该来源。

缺少参考文件时，独立分类工具输出明确提示、退出码为 2，且不输出伪造计数；正常完成为 0。`check_pack.py` 则只把无法执行的表达式比较标为 WARN，继续其余项目。

其他历史调研需要其文中指定的包版本；最新下载包不能证明旧版本的实现细节。来源文件与模块对应关系见 [THIRD-PARTY.md](../../Astra/THIRD-PARTY.md)。
