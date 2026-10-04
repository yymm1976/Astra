# 各分支会话引言

用途：在每个 worktree 开新会话时，把对应段落**整段贴进去**作为开场。
任务范围与禁令仍以该 worktree 的 `AGENTS.md` 与 `docs/parallel-development/<分支>.md` 为准，
引言只补三件任务书里没有的东西：**参考源码在哪、怎么做才对、容易踩什么坑。**

最后更新：2026-09-10（nether 分支完成后）

---

## 一、共享上下文（四段引言都以此为前提）

### 参考源码已就位

```
C:\Users\杨铭\Desktop\MC模组开发\Astra光影开发\_analysis\
    Complementary r5.9\Reimagined\shaders\...   （426 个文件）
    Complementary r5.9\Unbound\shaders\...      （426 个文件）
```

来源 Modrinth（`complementary-reimagined` / `complementary-unbound`），版本 **r5.9，2026-09-02**。
两个风格源码**完全一致**，只有默认设置不同。`/_analysis/` 已 gitignore，不进版本控制。
原有参考：`Mellow Shader v3.4`、`Solas Shader V2.2b`、`Steadfast-0.8.0`、`Refrax_v1.3.1`。

### 工作方式硬约束（nether 分支的教训）

1. **不要自己写，照抄参考。** 参考里能读到的表达式一律逐字移植，并在注释里写清来源文件与行号。
   需要自己推导形态或量级的，先停下来问，不要「我觉得这样更好」。
   失败案例：nether 分支前两轮自己造了两版公式，第三轮读到参考后全部推倒。
2. **结论必须带证据。** 文件路径 + 行号 + 实测数值。不写「可能存在风险」这类没有落点的话。
3. **编译通过 ≠ 画面达标。** 任务书对此有明确禁令。没有 Iris 实例就如实说「未画面验证」。
4. **拿不准的写进 `docs/handoffs/<分支>.md`，不要闷头猜。** 字段固定：
   接口 / 调用位置 / 参数 / 原因 / 本侧已完成 / 主任务侧待办。

### 校验工具

```bash
python qa/tools/compile_glsl.py          # 编译链接全部 pass，输出 RESULT linked=N failed=0
python qa/tools/compile_glsl.py --match <路径片段>   # 只编译匹配的 pass
```

**不要加 `--log`** —— 那会产生任务书未要求的产物。
需要 GPU 与 Java 17（本机均有）。它只做编译链接校验，不做任何画面判断。

### Git 纪律（重要）

- **分支名不能带斜杠。** 本仓库里 git 写不了二级引用：写 `refs/heads/<x>/<y>` 会把整个
  `<x>/` 目录递归删掉、一次带走该命名空间下全部分支，且**返回 exit 0 无任何报错**。
  已改成 `codex-<分支名>`；不要改回去。
- **不要提交 `AGENTS.md`。** 五个 worktree 里同名同路径，合并进 main 必然五方冲突。
- 提交前先 `git status`。若引用意外消失，恢复方式是
  `printf '<sha>\n' > .git/refs/heads/<分支名>`（git 能正常读取手工写入的引用）。
- 不新增哈希、基线、冒烟、测试、备份、回滚类产物（任务书禁令）。
- 不同步到用户游戏实例，不合并其他分支。

---

## 二、end（末地）× `codex-end`

```
你在 worktree C:\Users\杨铭\Desktop\MC模组开发\Astra并行开发\end，分支 codex-end。
先读 AGENTS.md 与 docs/parallel-development/end.md，只处理末地。

你能直接编辑的只有 Astra/shaders/global/dimension/end.glsl；需要专属模块放 global/end/ 下。
public 边界（program/、lib/、shaders.properties、global/water/、lighting/shadowmap.glsl、
lighting/diffuse.glsl、global/post/、block.properties）一律不碰，需要接入就写
docs/handoffs/end.md。

任务：微调末地天空、星云和环境照明，保持地形轮廓可辨，减少泛亮。
用户已确认阴影修好，必须保留；波浪、噪声注册、阴影数据输出不得换回旧实现。

★ 参考源码已下载：_analysis\Complementary r5.9\{Reimagined,Unbound}\shaders\
  末地相关的关键位置：
    lib/common.glsl:817, 818              endSkyColor = vec3(0.095,0.07,0.15)*1.65
                                         （另一个常量 endOrangeCol = vec3(1.0,0.3,0.0)）
    lib/colors/lightAndAmbientColors.glsl:82-87
                                         lightColor = endLightColor*(0.35-0.2*vsBrightness)
                                         ambientColor = endLightColor*(0.2+0.2*vsBrightness)
                                         endLightColor = vec3(0.68,0.51,1.07)
    program/gbuffers_skytextured.glsl:111-113   末地天空贴图 = vec4(endSkyColor, 1.0)
    program/deferred1.glsl:382-388      末地天空分支：endSkyColor + GetEnderStars(...)
    lib/atmospherics/enderStars.glsl    末地星空
    lib/atmospherics/volumetricLight/   末地光柱（volumetricLight.glsl）
    lib/lighting/mainLighting.glsl:574-583  各维度 AO 的指数分支
    选项：screen.END_SETTINGS —— END_BEAM_INTENSITY / END_STAR_INTENSITY /
          END_BEAM_CENTER_ALT / END_BEAM_HEIGHT / END_FLASHES
    注意 lib/lighting/minimumLighting.glsl:2 是 `#if !defined END` —— 末地没有暗部下限。

★ 风格硬约束：不要自己写，照抄参考。参考能读到的表达式逐字移植，注释写清来源文件:行号。
  需要自己推导的地方先停下问，别猜。参考里没有对应实现的（Astra 自有设计）保留并标注。

★ 编译校验：python qa/tools/compile_glsl.py（不要加 --log）。
  编译通过不代表画面对了；没有 Iris 实例就如实说未验证。

★ 拿不准的写进 docs/handoffs/end.md，字段：接口 / 调用位置 / 参数 / 原因 /
  本侧已完成 / 主任务侧待办。需要公共接入时写在那里，不要改共享文件绕过边界。

★ Git：分支名不得带斜杠（本仓库 git 写不了二级引用，会一次删掉整个命名空间）；
  不要提交 AGENTS.md；不要新增哈希/基线/冒烟/测试/备份类产物；不同步到游戏实例。
```

---

## 三、sky-clouds（天空与云）× `codex-sky-clouds`

```
你在 worktree C:\Users\杨铭\Desktop\MC模组开发\Astra并行开发\sky-clouds，分支 codex-sky-clouds。
先读 AGENTS.md 与 docs/parallel-development/sky-clouds.md，只处理天空与云。

你能直接编辑的：
  Astra/shaders/global/atmosphere/sky_minishita.glsl
  Astra/shaders/global/atmosphere/sky_gradient.glsl
  Astra/shaders/global/atmosphere/clouds_planar.glsl
  Astra/shaders/global/atmosphere/stars.glsl
public 边界（program/、lib/、shaders.properties、global/water/、lighting/shadowmap.glsl、
lighting/diffuse.glsl、global/post/、block.properties）一律不碰。

任务：改善天空、云层与星空的形状、过渡和观感。
★ 水面反射依赖天空：改变函数接口或光照输出之前，必须在 docs/handoffs/sky-clouds.md 提出。
  参考里同样的耦合写在 lib/colors/skyColors.glsl 与 lib/materials/materialMethods/
  worldSpaceRef.glsl（天空被反射采样）。

★ 参考源码已下载：_analysis\Complementary r5.9\{Reimagined,Unbound}\shaders\
  天空与云相关的关键位置：
    lib/atmospherics/sky.glsl            GetSky() 主入口
    lib/colors/skyColors.glsl            正午/日落/夜晚三套天空色（noonUpSkyColor 等），
                                         全部在 #ifdef OVERWORLD 内
    lib/atmospherics/clouds/             云（含 Unbound / Reimagined 两种风格）
    lib/lighting/cloudShadows.glsl:20-26 云影，用 eastVec/northVec 投影
    lib/atmospherics/stars.glsl          星空
    lib/atmospherics/nightNebula.glsl    夜空霓虹云
    lib/atmospherics/auroraBorealis.glsl 极光
    lib/atmospherics/rainbow.glsl        彩虹
    lib/atmospherics/fog/mainFog.glsl:98-121
                                         GetAtmFogColor / GetAtmFogAltitudeFactor
                                         （太阳方向、雨、昼夜混合的大气雾色）
    选项：screen.CLOUD_SETTINGS、screen.ATMOSPHERE_SETTINGS、NIGHT_NEBULAE、AURORA_STYLE 等
  注意：参考的天空是一个「上/中/下」三向的球面模型（VdotU / VdotS），不是单条渐变。

★ 风格硬约束：不要自己写，照抄参考。逐字移植 + 注释写清来源文件:行号。
  需要自己推导的地方先停下问。参考没有的（Astra 自有设计）保留并标注。

★ 编译校验：python qa/tools/compile_glsl.py（不要加 --log）。
  编译通过不代表画面对了；没有 Iris 实例就如实说未验证。

★ 拿不准的写进 docs/handoffs/sky-clouds.md，字段见任务书。

★ Git：分支名不得带斜杠；不要提交 AGENTS.md；不要新增哈希/基线/冒烟/测试/备份类产物；
  不同步到游戏实例。
```

---

## 四、terrain-foliage（陆地材质与植被）× `codex-terrain-foliage`

```
你在 worktree C:\Users\杨铭\Desktop\MC模组开发\Astra并行开发\terrain-foliage，
分支 codex-terrain-foliage。
先读 AGENTS.md 与 docs/parallel-development/terrain-foliage.md，只处理陆地材质与植被。

你能直接编辑的：
  Astra/shaders/global/lighting/wind.glsl
  Astra/shaders/global/lighting/sss.glsl
其他材质需要新增模块时放 global/materials/ 下；主入口接入由主任务处理。
public 边界（program/、lib/、shaders.properties、global/water/、lighting/shadowmap.glsl、
lighting/diffuse.glsl、global/post/、block.properties）一律不碰。

任务：微调植被摆动与材质透光外观。
★ 树叶投射与可见模型必须保持一致；已修好的阴影数据输出禁止修改。
★ 注意 lighting/wind.glsl 与 lighting/sss.glsl 是 public 边界里 diffusion 的**邻居**：
  global/lighting/diffuse.glsl 属公共边界，不要碰；你只动 wind 与 sss 两个文件。

★ 参考源码已下载：_analysis\Complementary r5.9\{Reimagined,Unbound}\shaders\
  植被与材质相关的关键位置：
    lib/materials/materialMethods/wavingBlocks.glsl
        摆动主入口 DoWave() / DoWave_Leaves()，含每个方块的参数
        :150-153  藤蔓用 DoWave_Leaves(playerPos.xyz, worldPos, 0.75)（减幅防穿模）
        :154-157  #if defined NETHER || defined DO_NETHER_VINE_WAVING_OUTSIDE_NETHER
                  垂泪藤 / 缠怨藤摆动
    lib/materials/materialHandling/terrainIPBR.glsl
        按材质 id 分发到 specificMaterials/terrain/ 下 38 个模块
    lib/materials/specificMaterials/terrain/*    按方块的光照/法线/平滑处理
    lib/lighting/mainLighting.glsl:107-115
        subsurfaceMode == 1 → NdotU = 1.0, NdotL = dot(upVec, lightVec)
        subsurfaceMode == 2 → 另一套 wrap（叶子的「透光」就在这里）
    lib/materials/materialHandling/terrainIPBR.glsl:2135, 2230, 2248, 2633
        用 NdotE 判定叶片侧向
    选项：screen.IPBR_SETTINGS（GENERATED_NORMALS / COATED_TEXTURES）、
          WAVING_SPEED、WAVING_I、GLOWING_LEAVES 类。
  注意：参考的摆动是**每方块独立参数**，不是一套全局频率；Astra 的 wind.glsl 结构可能不同，
  移植时要讲清是「照抄参数」还是「照抄形状」，并在注释里写明。

★ 风格硬约束：不要自己写，照抄参考。逐字移植 + 注释写清来源文件:行号。
  需要自己推导的地方先停下问。参考没有的（Astra 自有设计）保留并标注。

★ 编译校验：python qa/tools/compile_glsl.py（不要加 --log）。
  编译通过不代表画面对了；没有 Iris 实例就如实说未验证。

★ 拿不准的写进 docs/handoffs/terrain-foliage.md，字段见任务书。

★ Git：分支名不得带斜杠；不要提交 AGENTS.md；不要新增哈希/基线/冒烟/测试/备份类产物；
  不同步到游戏实例。
```

---

## 五、ui-language（界面与配置文案）× `codex-ui-language`

```
你在 worktree C:\Users\杨铭\Desktop\MC模组开发\Astra并行开发\ui-language，
分支 codex-ui-language。
先读 AGENTS.md 与 docs/parallel-development/ui-language.md，只处理界面与配置文案。

你能直接编辑的：
  Astra/shaders/lang/zh_CN.lang
  Astra/shaders/lang/en_US.lang
Astra/shaders/shaders.properties 是公共边界，不要碰 —— 菜单结构改动一律写在
docs/handoffs/ui-language.md，由主任务接入。

任务：整理选项名称、说明和中英一致性。
★ 不得调整默认参数、不得删除现有选项。改名/改说明可以，改值和删项不行。

★ 参考源码已下载：_analysis\Complementary r5.9\{Reimagined,Unbound}\shaders\
  语言与菜单相关的关键位置：
    lang/en_US.lang                      1188 行，本分支的主要参照
    shaders.properties                   screen.* 分组、sliders= 列表、profile.* 结构
  值得照抄的几处约定：
    1. 三段式命名：option.<KEY>（名称）、option.<KEY>.comment（说明）、
       value.<KEY>.<值>=（枚举值的显示文本，例：value.NETHER_VIEW_LIMIT.256.0=16 Chunks）
    2. 颜色标记：§e...§r 标「影响性能的选项」，§c[-]§r 标「调高会掉帧」——
       这是玩家能一眼看出来的风险提示，位置与措辞都值得学
    3. 说明写「Determines ... / Adjusts ...」+ 后果，不写「是否启用」这类废话
    4. 每个 screen.* 分组是「<empty> <empty> 项1 项2 <empty> <empty> 项3」的列布局，
       <empty> 是占位，控制两列排布的留白
  注意 Complementary 的 lang 只有 en_US，没有中文对照；Astra 有 zh_CN，中英一致性是
  Astra 独有的要求，这部分的判断标准只能来自 Astra 自己的术语习惯。

★ 风格硬约束：不要自己写，照抄参考的措辞风格与结构约定。
  但★这条有例外★：文案的「内容」必须对得上 Astra 的实际选项语义，
  不能为了像参考而改掉 Astra 参数的含义。措辞照抄、语义照实。

★ 拿不准的写进 docs/handoffs/ui-language.md，字段：接口 / 调用位置 / 参数 / 原因 /
  本侧已完成 / 主任务侧待办。
  菜单结构改动必须走 handoff，注明：选项键名 / 落在 shaders.properties 的哪个位置 /
  类型与取值范围 / 默认值（只报不改）/ 原因。

★ Git：分支名不得带斜杠；不要提交 AGENTS.md；不要新增哈希/基线/冒烟/测试/备份类产物；
  不同步到游戏实例。
```

---

## 附：四段引言里共同引用的 nether 分支产出（可一并转交）

| 文件 | 内容 |
|---|---|
| `nether/docs/handoffs/nether.md` | 上报清单（P-001~P-003 公共接入请求、3 条 design.md 冲突、不确定度说明） |
| `nether/docs/2026-09-10-complementary-r5.9-nether-report.md` | 参考的下界全量分析，14 节 + 证据清单。**读它比读参考源码快** |
| `nether/docs/2026-09-10-complementary-r5.9-nether-teardown.md` | 同上的第一版，细节更多但结构较差 |

**最值得其它分支直接借用的一条经验**（报告 §0）：
参考的合成律是「**平方和再开方**」而不是加法累加 ——

```glsl
// lib/lighting/mainLighting.glsl:613-616
vec3 finalDiffuse = pow2(directionShade * vanillaAO)
                  * (blockLighting + pow2(sceneLighting) + minLighting)
                  + pow2(emission);
finalDiffuse = sqrt(max(finalDiffuse, vec3(0.0)));
```

加法累加结构上可以过曝，平方和开方结构上有界。任何涉及多光源项相加的分支都值得检查一下
自己是哪种。
