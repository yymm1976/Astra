# 本地工具配置

工具从命令行参数、环境变量、系统常见 Minecraft 目录依次取路径。仓库不再指定某一台机器的盘符或实例名称。

| 参数 / 环境变量 | 含义 |
|---|---|
| `--minecraft-root` / `ASTRA_MC_ROOT` | 含 `libraries/` 的 Minecraft 根目录 |
| `--instance` / `ASTRA_MC_INSTANCE` | 含 `mods/`、`config/`、`shaderpacks/` 的游戏实例目录 |
| `--iris-jar` | 调度读取工具使用的 Iris jar，覆盖实例自动查找 |
| `--java-home` / `JAVA_HOME` | 调度读取工具使用的 JDK 根目录；未指定时使用 PATH |
| `--dest` | 同步工具的明确目标包目录，优先于实例查找 |
| `--reference` / `ASTRA_STEADFAST_PROPERTIES` | Steadfast 0.8.0 的 `shaders.properties` 路径 |

自动查找遇到多个实例或多个 Iris jar 会要求明确选择，不会按文件名猜测版本。编译工具及其 GPU 辅助脚本仍依赖 Windows 的 LWJGL 3.3.3；取消固定路径不表示已完成跨平台驱动适配。

`inspect_iris_properties.py` 读取四档配置，用安装版本的 Iris 解析选项和布尔条件。三个画质档参与递增比较，NO_SHADOWS 单独要求关闭阴影。它读取调度配置，不测游戏帧率。

`compile_glsl.py` 不带 `--profiles` 时仍只选择 PERFORMANCE、BALANCED、ULTRA。需要四档时明确指定 `--profiles PERFORMANCE NO_SHADOWS BALANCED ULTRA`；历史 270 次链接记录不能因此改称四档。

## 参考副本

`_analysis/` 是可选的本地参考资料，不随仓库提供。用于表达式分类的文件来自作者发布的 [Steadfast 0.8.0](https://modrinth.com/shader/steadfast-shaders/version/0.8.0)：解包后将其 `shaders/shaders.properties` 传给 `--reference`，或放到默认位置 `_analysis/Steadfast-0.8.0/shaders/shaders.properties`。不要用其他版本代替该来源。

缺少参考文件时，独立分类工具输出明确提示、退出码为 2，且不输出伪造计数；正常完成为 0。`check_pack.py` 则只把无法执行的表达式比较标为 WARN，继续其余项目。

其他历史调研需要其文中指定的包版本；最新下载包不能证明旧版本的实现细节。来源文件与模块对应关系见 [THIRD-PARTY.md](../../Astra/THIRD-PARTY.md)。
