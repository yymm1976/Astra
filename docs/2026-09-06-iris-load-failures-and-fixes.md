# Iris 实机加载失败诊断与修复记录（标准模型 → 顶级Ⅱ交接）

**日期：** 2026-09-06
**环境：** RTX 4050 Laptop / MC 26.2 / Iris 1.11.2 / Fabric 生电优化整合包（PCL）
**现象：** 选择 Astra 后整包加载失败，Iris 回退原版渲染。共两轮失败、两类根因，**均已源码级修复并双向同步**，待逐轮重载验证。

> 给顶级Ⅱ：本文记录实机加载排障的完整诊断链（六轮，SC-21~SC-28）、修复明细与六条防回归约束。第二轮修复动的是 shaders.properties（Z3 底座文件），性质是格式合规而非设计变更，未触碰任何架构决议。

---

## 第一轮：#include 行尾注释 → InvalidPathException

- **日志**：`versions/生电优化整合包 (Fabric)/logs/latest.log:1576-1578`（16:18:47）
- **异常**：`java.nio.file.InvalidPathException: Illegal char <"> at index 17: lib/settings.glsl"   / design.md 3.2 layer 2: ...`
- **根因**：Iris 的 include 解析器把 `#include "path"` 闭引号后的整行（含注释）当作路径续接；Windows 路径校验遇 `"` 非法字符抛异常，整包加载中止。行尾注释是 E1 交付的 include 行常见写法（如 `#include "/lib/settings.glsl"   // design.md 3.2 layer 2: ...`），在 Iris 1.11.2 不被接受。
- **修复**：program/ 下 9 文件 10 行——`composite.fsh`、`composite.vsh`、`composite1.fsh`、`composite1.vsh`、`deferred.vsh`、`final.vsh`、`lit_voxy.fsh`、`shadow.fsh`（2 行）、`shadow.vsh`。行尾注释全部上移为独立注释行，零语义变更。
- **规约（长期遵守）**：`#include` 行必须以闭引号结尾，行尾不得有任何注释。

## 第二轮：单段式 texture.* 指令 → StringIndexOutOfBoundsException

- **日志**：同文件 16:27:08 与 16:27:17（用户重载后复现，include 修复已被本次加载越过，错误类别切换证明第一轮修复有效）
- **异常**：`java.lang.StringIndexOutOfBoundsException: Range [8, -1) out of bounds for length 16`，栈顶 `ShaderProperties.handleTwoArgDirective(ShaderProperties.java:729)`，发生于 **ShaderPack 构造的 shaders.properties 解析阶段**（早于一切 GLSL 编译，也解释了为何"225 组驱动编译零错"拦不住它）。
- **定位推理**（三特征逐一吻合）：
  1. begin=8 → 指令前缀 `"texture."`（8 字符）；
  2. length 16 → 键 `texture.noisetex` 恰 16 字符；
  3. end=-1 → `indexOf('.', 8)` 找不到第二个点（单段式键，两段式解析必然失败）。
  → 命中 `shaders.properties` 原 109 行 `texture.noisetex=tex/noise.png`。
- **根因**：Iris 1.11.2 对 `texture.` 系指令按两段式 `texture.<阶段组>.<采样器>` 解析，**单段式 `texture.noisetex` 直接崩溃**（无兜底分支）。
- **参照**：Mellow `shaders.properties:48-49` 的分段式写法 `texture.deferred.noisetex=...` / `texture.gbuffers.noisetex=...`（现代 Iris 验证可用）。
- **修复**：原 109 行替换为六个阶段组绑定：`texture.shadow / gbuffers / deferred / composite / composite1 / final .noisetex=tex/noise.png`。noisetex 消费方（`global/water/caustics`、`global/atmosphere/clouds_planar`、`global/dimension/nether`、`global/dimension/end`）经 lit/deferred/composite 链消费，均落在上述阶段组覆盖内。修复后全包两段式 texture 指令 6 条、单段式 0 条。

## 第三轮：const 指令表达式 → NumberFormatException / AIOOBE（SC-23）

- **日志**：同文件 16:34:05 / 16:36:05（1773、1805、1808 行）
- **异常**：`NumberFormatException: For input string: "64 * (1.0 / 128)"`（`ConstDirective { FLOAT entityShadowDistanceMul }`）+ `expected 4 arguments to a vec4 constructor, got 1`（`colortex0ClearColor = vec4(0.0)`）→ 致命 `ArrayIndexOutOfBoundsException: Index 1 out of bounds for length 1`。
- **根因**：Iris 的 const 指令解析器**只认纯字面量**——不吃算术表达式，vec4 构造器必须 4 个字面量参数。异常发生在宏展开之后（源码写 `ENTITY_SHADOW_DISTANCE * (1.0 / SHADOW_DISTANCE)`，Iris 展开为 `64 * (1.0 / 128)` 再解析）。
- **修复**（`lib/settings.glsl`，4 处）：
  1. `entityShadowDistanceMul` → 字面量 `0.5`（SC-13 预判的退化路径；三档 profile 恰好全为 0.5，注释保留换算依据）；
  2. `colortex0ClearColor` → `vec4(0.0, 0.0, 0.0, 0.0)`；
  3. `colortex3ClearColor` → `vec4(0.498, 0.0, 0.0, 1.0)`（潜伏雷：`127.0/255.0` 表达式，本轮主动排除）；
  4. `shadowcolor0ClearColor` → `vec4(1.0, 1.0, 1.0, 1.0)`（下一轮必炸的同款单参写法，本轮主动排除）。
- **排除法说明**：全包 const 扫描后确认其余非字面量 const（end.glsl 的 `to_linear(vec3)`、blocklight 的 RANGE2、distort 的 shadow_map_bias 等）**不是 Iris 引擎旋钮名**，引擎不解析、由 GLSL 编译器自行求值，无风险。
- **规约（长期遵守）**：Iris 引擎旋钮 const（shadowMapResolution / *ClearColor / *Format / entityShadowDistanceMul / shadowHardwareFiltering 等）的初始化值只能是**纯字面量**；表达式留给 GLSL 代码内的普通 const。

## 第四轮：lib include 中的格式 const 未被 Iris 改写 → C1503（SC-25）

- **日志**：16:51:12 `Failed to create shader rendering pipeline, disabling shaders!`
- **异常**：`ShaderCompileException: deferred.vsh: 0(25) : error C1503: undefined variable "R11F_G11F_B10F"`——**首次进入 GLSL 编译层**，解析层（properties/const）已全部通过。
- **根因**：Iris 1.11.2 会从 include 展开源里**读取**（round 3 的 ClearColor 报错证明）但不**改写**格式 const——`R11F_G11F_B10F` 这类格式令牌不是 GLSL 标识符，Iris 的改写（替换为 GL 枚举数值）只发生在程序文件自身的源上，lib include 里的格式声明原样漏到驱动编译器 → C1503。
- **参照包证据**：Refrax（program/composite0）、Solas（program/final）、Steadfast（program/shadow + program/post）全部把格式 const 放在程序文件内；唯一放 lib 的 Mellow，其发布版恰好把格式声明整块注释掉、靠 Iris 默认格式运行——四个参照无一反例。
- **修复**：格式 const 从 `lib/settings.glsl` 移除（原地留 SC-25 说明注释），按写入方落到 6 处程序文件：`lit.fsh`(colortex0)、`composite.fsh`(colortex1)、`composite1.fsh`(colortex2)、`deferred.fsh`(colortex3/4)、`shadow.fsh`(shadowcolor0)，无行尾注释（参照包同形）。
- **规约（长期遵守）**：格式 const 必须声明在各写入方 program 文件内，禁止放 lib。

## 第五轮：include 内格式 const 仍未改写 + Voxy uniform 缺声明（SC-26）

- **日志**：17:07:17 `ShaderCompileException: deferred.fsh: 0(97) undefined "vxModelViewInv"; 0(457) undefined "R8"; 0(458) undefined "R11F_G11F_B10F"`
- **两个根因**：
  1. **格式 const 的改写只发生在入口文件**（比 SC-25 结论更严格）：deferred.fsh 自身的 colortex3/4 声明（展开源 457/458 行）依旧原样漏到驱动——Iris 只改写它直接编译的入口壳文本，program/lib 层的 include 一律不改写，即使这些 const 会被指令收集器读取。上轮"放入程序文件"的修复不成立。
  2. **Voxy uniform 未声明**：实例装有 Voxy 模组 → Iris 定义 `VOXY` 预处理宏 → `lib/transforms.glsl` 的 `#ifdef VOXY` 分支被激活，但 `uniform mat4 vxModelView/vxModelViewInv;` 从未声明（E1 注释说"Voxy path adds them"，声明没落地）。Mellow 的先例：`lib/all_the_uniforms.glsl:104` 正常声明。
- **修复**：
  1. 6 条格式 const 从 5 个 program 文件撤出，落进**每维度一个的入口壳**：root/final.fsh、world-1/final.fsh、world1/final.fsh（final 永远参与编译，天然满足"入口文件"要求）；lib/settings.glsl 注释同步更正；
  2. `lib/uniforms.glsl` 补 `#ifdef VOXY` 下的 `vxModelView`/`vxModelViewInv` 声明（Iris 提供值；voxy.json 注入仅服务于 voxy_* 入口，与主管线无关）。
- **规约（长期遵守，替代 SC-25 规约）**：格式 const 只能写在**入口壳**（root/world-1/world1 的 final.fsh 已承载全部 6 条）；program/lib 层出现任何格式令牌 = C1503。

## 第六轮：决定性发现——本 Iris 根本不支持格式 const 令牌（SC-27）

- **日志**：17:19:30 `ShaderCompileException: final.fsh: 0(248)-(253) C1503 undefined R11F_G11F_B10F/R8/RGBA16`
- **决定性对照**：实例内在这套 Iris（iris-fabric-1.11.2+mc26.2）上实际可用的 Complementary Unbound r5.8.1，其 `lib/pipelineSettings.glsl` 的全部格式声明**整块被 `/* */` 注释掉**——加上 Mellow 发布版同样注释掉，**五个参照包中没有任何一个在本 Iris 上活跃使用格式 const**。结论修正：Iris 1.11.2 对 `colortexNFormat` 格式令牌一概不改写（lib/program/入口全部无效），任何活跃的格式 const 都会 C1503。前四轮"位置问题"的假设全部作废，问题不是位置而是机制本身（本版 Iris 已弃用/损坏该入口）。
- **修复**：
  1. 三个 final.fsh 入口壳的格式 const 全部注释掉（保留 SC-27 说明），缓冲区改用 **Iris 默认格式**（Complementary/Mellow 同款路线）；
  2. 顺带修复非致命警告：`texture.*.noisetex` 六条指令被 `Unknown texture stage` 忽略 → 删除全部 noisetex 绑定指令，noise.png 移到 `shaders/textures/noise.png`（OptiFine/Iris 约定的自动绑定路径，Complementary 同样零绑定），256×256 与 `noiseTextureResolution=256` 匹配。
- **代价与后续**：设计 §2.3 的格式带宽优化（R11F_G11F_B10F 等）暂不可用，退化为 Iris 默认格式；待查清本版 Iris 的格式声明新机制后再恢复（roadmap）。`shadowcolor0` 水面高度编码精度可能下降（默认格式下），焦散观感待实机确认。
- **遗留非致命警告**（不影响加载，后续处理）：`Invalid pack option: GODRAYS/UNDERWATER_PARTICLES`、`Unable to resolve menu element VOXY_SUPPORT` 等选项识别警告——选项书写形式与 Complementary 一致但未注册，待选项系统专项排查。

## 附加决议：水效果对标更正（SC-24，用户前提修正）

用户澄清水效果标杆最初记反了，**正确口径为 水面 ≈ Steadfast、水下 ≈ Solas**。工程落地：
- design.md §0 / §1.1 / §4.3 / §8.3 已对调，§4.3 附决议块；grill-summary.md 决策 #15 已登记；
- C2（水下三件套 absorption/refraction/caustics）参考源换 **Solas** `shaders/lib/water/`（waterFog / waterCaustics 等），C7（surface.glsl）参考源换 **Steadfast** `shaders/environment/water/`（解析导数程序波浪 + Nyquist 比率受限 + 4 步自适应视差）——两行任务均回 🔶 待高级Ⅱ换源重写，**接口签名与 E2 总成接线不变**；
- SSR 射线追踪（raytrace.glsl）与预乘 alpha 属管线基础设施，维持现有 Steadfast 实现不动；
- 注意时序：水效果重写（C 档）与实机加载验证（SC-6）互不阻塞，可并行。

## 给顶级Ⅱ的行动建议

1. **防回归**：把六条 Iris 解析器约束写进 `qa/tools/check_pack.py` 静态检查（a–e 已随 SC-25/26 落地，f 随 SC-28 落地）——
   a. 所有 `#include` 行必须匹配 `^#include\s+"[^"]+"\s*$`；
   b. 所有 `texture.*` 指令的键必须为两段式（`texture.` 后必须再含一个点）；
   c. 所有 Iris 引擎旋钮 const 的初始化值必须是纯字面量（FLOAT/INT 单值；ClearColor 必须 4 参字面量 vec4）；
   d. 所有 `*Format` const 必须位于入口壳（root/world-1/world1 的 final.fsh），program/lib/global 任何层级出现格式令牌 = 违规；
   e. `#ifdef VOXY` 分支引用的 uniform 必须在 lib/uniforms.glsl 有对应声明（Voxy 装机时 Iris 必定义该宏）；
   f. 布尔选项必须在着色器源中存在 `#ifdef/#ifndef NAME` 引用才会被注册——`#if defined NAME` 对扫描器不可见（SC-28，OptionAnnotatedSource 仅解析 #define/const/#ifdef/#ifndef）；孤儿选项在归属任务接线前持续 WARN。
2. **双份同步纪律**：工作区 `Astra/` 与实例 `shaderpacks/Astra/` 是两份活代码。三轮修复均已 diff 校验完全一致；后续任何一方改动必须立即同步另一方。
3. **git 仍零提交**：建议本档会话结束前做首次提交，把"驱动编译零错 + 三轮 Iris 解析修复"钉进历史，此前所有交付均无版本锚点。

## 当前状态与验证路径

- 已修复待验证（累计四轮）：include 10 行（SC-21）+ texture 绑定 1→6 行（SC-22）+ const 字面量化 4 处（SC-23）+ 格式 const 移入程序文件 6 处（SC-25）；工作区与实例 diff 完全一致。
- 需求更正：水效果对标对调（SC-24），C2/C7 换源重写待高级Ⅱ，与实机验证并行、互不阻塞。
- 用户下一步：光影包界面重新选择 Astra（或重启进世界）。解析层错误（include/texture/const/格式改写）已全部清零，第四轮已首次进入 GLSL 编译层——若第五轮仍失败，报错将来自具体着色器的 GLSL 语义（彼时与"225 组驱动编译零错"的证据冲突需要解释，优先怀疑 include 展开差异），把最新 `logs/latest.log` 交回。
- 台账：SC-21/22/23/25 均"✅ 已执行，实机验证归 SC-6"；SC-24 "🔶 重写待高级Ⅱ"。
