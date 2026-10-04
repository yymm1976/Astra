# R3 / B4 下界体素彩光布局与访问优化 —— 交接记录

2026-10-02 当前实现：空气接收格直接读取六邻居，取消共享块与工作组同步；九阶段、光源与衰减不变。此前源码读取数量减少的记录不再描述当前路径；采用直接路径的依据与处理见[接续记录](../2026-10-02-module-performance-refinements.md)。

- 状态：代码完成；驱动级编译未验证（环境缺 LWJGL，见第 7 节）；check_pack FAIL 数持平
- 认领：ZCode 会话，2026-09-27
- 对应父项：B4 彩光布局优化（总表 docs/2026-09-26-itt32-initial-implementation.md 第 3 节 B4）
- 前置：[S3 坐标整理](2026-09-27-S3-voxel-grid.md)（已完成，本任务未重复计入）
- 接续点：见第 8 节

## 1. 资源与读写关系（源码核对）

### 1.1 astraVoxelImage（R32UI，64³，声明 clear=true）

- 声明：`shaders.properties:559` `image.astraVoxelImage=astraVoxelSampler red_integer r32ui unsigned_int true false 64 64 64`
- 生产者：`program/shadow.vsh:50-76` `astra_voxel_write()`，每顶点一次 `imageAtomicMax`（shadow.vsh:75），guard `DIMENSION_NETHER && NETHER_VOXEL_LIGHT && SHADOWS`（shadow.vsh:33）。只写。
- 消费者：`program/nether_light.csh:50` `texelFetch(astraVoxelSampler,p,0)`，9 个阶段（step 0..8）每阶段每 cell 各 1 次只读 fetch。全仓仅此一处采样。
- 方向：shadow 光栅化写入 → 同帧 shadowcomp 0..8 只读。无回写、无跨帧历史。
- 编码：bit 8 = solid（阻挡扩散），bits 0-7 = 种类（0=已捕获空气、1=声明保留但 shadow.vsh 从不写出、2..8=彩色光源组、9/10/11=火/魂火/熔岩）。solid 与 kind 的区别保留（shadow.vsh:64-74：熔岩 solid=true 且 kind=11；火把 kind=2..8 solid=false）。
- 格式约束：imageAtomic* 只支持 r32ui/r32i 单一格式图像，所以捕获图**不能**缩到 R16UI/R8UI（这正是任务警示的「不支持原子操作的格式」）。

### 1.2 astraLightA（RGBA16F，64³，clear=false）

- 声明：`shaders.properties:560`
- 写入方：`nether_light.csh:101-102` imageStore，偶数步（0,2,4,6,8）。
- 读取方：奇数步（1,3,5,7）以 `texelFetch` 读邻居（改动前每 cell 6 次）；显示 `global/dimension/nether_colored_light.glsl:8,23` 以 LINEAR `sampler3D` `textureLod` 读 `.rgb`。step 8 偶数 → 最终结果在 A，显示只依赖 A。

### 1.3 astraLightB（RGBA16F，64³，clear=false）

- 声明：`shaders.properties:561`
- 写入方：`nether_light.csh:103-104`，奇数步（1,3,5,7）。
- 读取方：偶数步（2,4,6,8）读邻居。链路外无消费者。

### 1.4 alpha 语义（核查结论，非假定）

- 两个体积每次 imageStore 都写 `vec4(color,1.0)`（nether_light.csh:102,104），所有读取只取 `.rgb`（nether_light.csh 邻居读、nether_colored_light.glsl:23）。
- 结论：alpha 当前被写但从不被读。本次**不**复用它，保持写 1.0。也不把 RGBA16F 改成「RGB 三通道」：RGB16F 不是合法 image 格式（imageStore 不支持），3 通道省字节的唯一出路是打包格式 r11f_g11f_b10f，见第 8 节评估。

### 1.5 九阶段邻域传播距离

- Iris 按 shadowcomp, shadowcompA..H 依序 dispatch：`world-1/shadowcomp.csh`(step 0) 与 `world-1/shadowcompA..H.csh`(step 1..8)，各自 `#define ASTRA_LIGHT_STEP n` 后 include `program/nether_light.csh`；`shaders.properties:543-551` 对 9 个阶段都 gate 在 `SHADOWS && NETHER_VOXEL_LIGHT`。
- step 0：仅重建发射（`emission(id)*2.0`，nether_light.csh:60），无邻居读取。
- step 1..8：6-邻域（±x,±y,±z 各 1 格）`max(color, neighbor*0.72)`，每步推进 1 格 → 影响半径 = 6-邻域图距 ≤ 8 格。solid cell 不扩散但每步重播自身发射（nether_light.csh:60 在扩散分支之外），这是单步依赖上一步体数据的必然结构，不是冗余。
- 阶段之间只有 Iris 的 dispatch 间隐式同步；同一 dispatch 的工作组之间无全局同步。`barrier()` 只用于工作组内共享内存同步（本次接入），不能也没有用来合并九个阶段。

### 1.6 每帧全局纹理访存量（改动前，可由源码推得）

64³ = 262,144 cell；RGBA16F 8 B/texel；R32UI 4 B/texel。计数口径 = shader 发出的全局纹理读取次数（DRAM 级流量受缓存影响，源码推不出，不作数）。

- 光体积邻居读：每步 6 方向界内相邻对 = 6 × 63 × 64² = 1,548,288 次 → 8 步 = 12,386,304 次 × 8 B = 99,090,432 B ≈ 94.5 MiB
- 占用体读：9 步 × 262,144 = 2,359,296 次 × 4 B = 9,437,184 B = 9 MiB
- 光体积写：9 步 × 262,144 × 8 B = 18,874,368 B = 18 MiB
- 显存驻留：astraVoxelImage 1 MiB + astraLightA/B 各 2 MiB = 5 MiB

## 2. 选定方案与理由：传播邻居读共享内存分块（访问改进）

对比过的候选：

1. **[已接入] 邻居读分块**：每步把「每 cell 6 次全局 texelFetch」改为「每工作组协作载入 (8+2)³=10³ 带晕影块到 shared memory，邻居改读 shared」。理由最充分：读写次数可由源码精确推得；数学不变（同样 max 链、同次序、OOB 填 0 与原 `continue` 等价：max(color, 0×0.72)=color，color 恒 ≥0）；无格式/属性/语言文件风险；结果逐位不变。
2. **[未接入] astraLightA/B 改 r11f_g11f_b10f**：显存 4 MiB→2 MiB 且带宽再减半，但该格式 imageStore-only（不支持 imageLoad），且 Iris image 指令对其 3D 组合的支持在本环境无法验证（无 LWJGL/GLSL 编译入口），一旦属性解析被拒整个光影加载失败，风险不可控 → 作为下一处接续（第 8 节）。
3. **[未接入] 捕获图 R32UI→R16UI**：被 1.1 的原子格式约束直接否决。
4. **[未接入] 用上一步 alpha 编码 solid 以省占用体读**：需每步加一次自身 cell 读取，RGBA16F(8B) 换 R32UI(4B) 反而 +字节，否决。
5. **[未接入] 减少传播轮数**：改变 8 格影响半径与收敛行为，属画质取舍；无用户要求且需要新选项/语言键，本轮不做（第 8 节留档）。

## 3. 开销变化推导（改动前后对照，口径：每帧、9 个阶段各 dispatch 一次）

| 项 | 改动前 | 改动后 | 变化 |
|---|---|---|---|
| 光体积全局读（次数） | 12,386,304（1,548,288/步 × 8 步） | 3,796,416（474,552/步 × 8 步） | **−8,589,888 次/帧（−69.4%）** |
| 光体积全局读（字节） | 99,090,432 B ≈ 94.5 MiB | 30,371,328 B ≈ 29.0 MiB | **−68,719,104 B ≈ −65.5 MiB/帧** |
| 占用体读 | 2,359,296 次 × 4 B = 9 MiB | 不变 | 0 |
| 光体积写 | 18,874,368 B = 18 MiB | 不变 | 0 |
| 显存驻留 | 5 MiB | 不变 | 0 |
| shared memory | 0 | +12,000 B/工作组（10³ × 12 B） | 片上新占用，非全局流量 |

改动后每步读取次数推导：每轴 8 个工作组的晕影范围 [8g−1, 8g+8] 裁剪到 [0,63] 后长度为 9+10×6+9=78，三维 78³=474,552 次界内载入/步（边界组出界晕影不 fetch、填 0）。改动前每步 = 6 × 63 × 64² = 1,548,288 次。

未量化的次级效应（源码推不出具体数字，不作声明）：邻居访问从全局纹理变为片上 shared 读取；剩余的全局读变成连续块状访问，缓存命中率应高于散布的 6 邻域访问。**本任务不填任何 FPS 数字。**

## 4. 已改文件与实际调用关系

- `Astra/shaders/program/nether_light.csh:19-36` — 新增（仅 step 1..8 编译进的）`ASTRA_LIGHT_TILE_DIM/CELLS` 与 `shared vec3 astraLightTile[1000]`，附访问语义与 barrier 范围注释。
- `Astra/shaders/program/nether_light.csh:61-100` — 邻居读接入分块：61-79 协作载入（奇偶步源体积选择保持原 ping-pong：奇步读 A、偶步读 B），82 `barrier()`（仅工作组内），85-98 `if(empty)` 内 6 邻域从 shared tile 取值；发射重播、0.72 衰减、越界语义、写入目标（102/104）全部不变。
- 实际调用关系：该文件就是既有链路本体——生产者（写 astraLightA/B）兼消费者（读 astraVoxelImage 与上一步的 astraLightA/B），经 `world-1/shadowcomp.csh + shadowcompA..H.csh`（各 `#define ASTRA_LIGHT_STEP n`）被 Iris dispatch；显示侧消费者 `global/dimension/nether_colored_light.glsl`（读 A 的 `.rgb`）与捕获侧生产者 `program/shadow.vsh`（写 astraVoxelImage）未改动。无新增独立模块、无新增 include。
- 未改：`shaders.properties`、`settings.glsl`、lang、README（无新增选项/格式，按验收标准 8 无需同步）。

## 5. 精度损失 / 范围变化

- **无精度损失、无范围变化**：读取的是同一批 texel，max 链与运算次序不变（且 max 对浮点次序本就精确），存的仍是 RGBA16F 原值；出界邻居从「跳过」改为「0 参与比较」，因 color 恒 ≥0 两者等价。改动前后体数据逐位一致。
- 颜色动态范围、发光编码（`emission(id)*2.0`、`frameTimeCounter` 闪烁）、遮挡（bit 8）与空体素（raw==0）的区别全部保留，未触碰。

## 6. 约定一致性（cameraPosition / 网格中心 / 边缘淡出 / 采样偏移）

- 本方案不改任何坐标约定：捕获侧 `program/shadow.vsh:56-57` 与显示侧 `nether_colored_light.glsl:14-23` 逐字未动，仍走 S3 的 `astra_nether_voxel_cell/position/edge/normalized`。
- 计算侧的整数格寻址改为由 `gl_WorkGroupID*gl_WorkGroupSize` 推工作组原点，与既定 64³、8³ 工作组网格是同一映射（`gl_WorkGroupSize` 直接反映 `layout(local_size_*=8)` 声明，不引入新字面量）；`texelFetch` 点访问不变，LINEAR 采样仍只在显示路径。改动前后语义可逐行对照。

## 7. 验证

- `python qa/tools/check_pack.py` 基线（改动前）：17 checks, **3 FAIL**（#4 include-graph 遗留、#11 Iris SC-28 两个布尔选项、#15 fxaa 许可文本），exit 3。
- 交付前复跑：见任务返回粘贴的输出，FAIL 数不得增加。
- **驱动级编译未运行**：`qa/tools/compile_glsl.py` 需要 Minecraft 根目录下的 LWJGL 3.3.3 jar；本机 `C:\Users\杨铭\AppData\Roaming\.minecraft\libraries` 无任何 lwjgl 目录，全盘常见启动器/gradle 缓存均未找到 `lwjgl-3.3.3.jar`，也无 glslangValidator。与 S3 记录的环境限制相同。已做的替代核对：逐行复查 tile 载入映射（载入 `i = x+10y+100z` 与读取 `q.x+10(q.y+10q.z)` 同构、覆盖 [0,999]）、barrier 处于分歧分支之前的均匀控制流、step 0 编译单元不含 shared/barrier、`gl_WorkGroupSize` 与既有 8³ 字面量一致。

## 8. 未完成 / 下一处接续位置

- **驱动级编译与游戏内冒烟**：环境恢复 LWJGL 后跑 `python qa/tools/compile_glsl.py --match shadowcomp --profiles BALANCED`（BALANCED/ULTRA 开 NETHER_VOXEL_LIGHT，PERFORMANCE 关）。
- **r11f_g11f_b10f 体积格式**（显存 4 MiB→2 MiB、读写字节再减半）：接续位置 = `shaders.properties:560-561` 两个 image 声明 + `nether_light.csh:17` image 声明（需 `layout(r11f_g11f_b10f)`，imageStore 传 vec4 丢 alpha）+ 显示采样器不用改（r11f_g11f_b10f 可 LINEAR 过滤）。前置条件：先确认 Iris 1.11.2 image 指令接受该 internalFormat 的 3D 图（建议在有 LWJGL 的环境里先用 `--match shadowcomp` 编译 + 游戏内确认 image 绑定不回退默认格式）；alpha 丢弃需同步改 1.4 节语义记录。精度损失要写明：11/10 位尾数（相对误差 ~2^-7）对 16F 的 ~2^-11，光值域 ≤2.0 在其表示范围内。
- **减少传播轮数**（若要再砍读写次数）：把 step 1..8 砍成 1..N，影响半径从 8 格降到 N 格、远端光源变暗——这是画质取舍而非等价优化；需新增 `NETHER_LIGHT_STEPS` 之类选项 + settings/lang/README/profile 同步，且 shadowcompE..H 的 `program.*.enabled` gate 要随选项切换。本轮未动。
- 占用体 R32UI 的 9 bit 有效位（bit8 solid + kind 0..11）无法在保原子操作下缩窄，除非把捕获改成 idempotent `imageStore`（同一 block 的顶点写同一 cell 同一值，块与块 cell 不相交）——这能去掉原子序列化但不减字节，且要重证「同 cell 无跨块竞争」，留作独立小任务。

## 9. 风险

- 未经驱动编译：若本机驱动对动态索引 shared 数组或该 barrier 用法有偏好（罕见，均属 GLSL 430 核心），需冒烟确认。
- 分块收益是「shader 发出的全局读取次数」，DRAM 实际节省取决于缓存；不声称帧时变化。
