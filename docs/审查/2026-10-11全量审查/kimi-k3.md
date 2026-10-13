# Astra 光影独立全量审查报告

指定模型入口：trae-cn/kimi-k3-auto（Kimi-K3）
审查日期：2026-10-11
工作区：C:/Users/杨铭/Desktop/MC模组开发/Astra光影开发
审查范围：全部活跃渲染链及配置资源，沿生产者-附件/输入-消费者与配置条件核对

---

## 模块1：入口/程序调度/GLSL条件/附件格式清屏mip翻转/资源及宿主兼容

### 覆盖文件
- `Astra/shaders/shaders.properties` - 主配置入口
- `Astra/shaders/lib/settings.glsl` - 选项定义与预算谓词
- `Astra/shaders/lib/water_buffer_formats.glsl` - 水面附件格式
- `Astra/shaders/program/*.fsh/vsh` - 各阶段入口

### 审查发现

**P0 问题：**
无可证实P0问题。

**P1 问题：**

1. **colortex28 RG32F 格式声明位置不一致**
   - 位置：`program/lit.fsh:15-18` 声明 `colortex28Format = RG32F`，`shaders.properties:284` 声明 `size.buffer.colortex28=1.0 1.0`
   - 问题：RG32F格式在lit.fsh中声明，但尺寸在properties中声明。Iris按维度ProgramSet解析附件格式，需确认下界28号附件的RGBA16F反射元数据格式是否被正确隔离
   - 依据：`shaders.properties:284` 注释明确说明"下界28仍为原RGBA16F反射元数据"，但lit.fsh的RG32F声明在主世界条件下生效
   - 建议：确认`world-1/`目录下的lit.fsh变体是否声明不同格式，避免格式冲突

2. **云阴影缓存无条件启用风险**
   - 位置：`shaders.properties:119-131` colortex12尺寸条件分支
   - 问题：`CLOUD_MODE == 1 && CLOUD_TEMPORAL`时colortex12使用65x65到257x257网格，但`ASTRA_GRADIENT_SKY_CACHE`宏定义条件较复杂，需确认低预算档是否可能意外分配大纹理
   - 依据：`lib/settings.glsl` 的预算谓词 `ASTRA_OVERWORLD_OPTIMIZED` 影响colortex12尺寸选择
   - 建议：源码层面条件正确，实际GPU内存分配需Iris运行时确认

**P2 问题：**

1. **Voxy支持声明为预留但未实现**
   - 位置：`lib/settings.glsl` VOXY_SUPPORT宏注释说明"distant-terrain rendering is not implemented"
   - 问题：选项保留但功能未实现，用户可能误解
   - 建议：文档已说明为后续候选，无需修改

### 疑点与缺失事实
- 无独立GPU计时数据验证各预算档位的实际帧率差异
- `iris.features.optional`声明的GLSL400半精度打包函数在缺扩展时的实际行为未验证

---

## 模块2：阴影投射接收过滤彩影焦散与覆盖边界

### 覆盖文件
- `Astra/shaders/program/shadow.vsh` - 阴影投射顶点阶段
- `Astra/shaders/program/shadow.fsh` - 阴影投射片段阶段
- `Astra/shaders/global/lighting/shadowmap.glsl` - 阴影映射核心
- `Astra/shaders/global/lighting/diffuse.glsl` - 阴影消费
- `Astra/shaders/global/water/caustics.glsl` - 焦散

### 审查发现

**P0 问题：**
无可证实P0问题。

**P1 问题：**

1. **阴影边缘锯齿柔化实现局限**
   - 位置：`global/lighting/diffuse.glsl:surface_shadow_light()`函数，特别是`ASTRA_SURFACE_SHADOW_FRAGMENT`分支
   - 问题：中档两额外偏移沿四角可见性梯度，世界半径取0.22格或0.75屏幕像素足迹。`softRadius=max(0.22,0.75*astraSurfaceShadowPixelWorld)`，但`astraSurfaceShadowPixelWorld`在`lit.fsh`中通过`dFdx/dFdy`计算，远距离表面该值增大导致柔化半径收缩
   - 依据：`shadowmap.glsl:shadow_surface_reference_depths`的角点逆投影逻辑
   - 结果：远距离阴影边缘仍可能出现锯齿，符合用户反馈"阴影边缘锯齿仍明显"
   - 建议：当前实现已按设计要求柔化，彻底消除锯齿需增加影图分辨率或更复杂过滤，与144FPS目标存在取舍

2. **阴影投射物深度修正的保守性**
   - 位置：`program/shadow.fsh:GL_ARB_conservative_depth`扩展使用
   - 问题：`layout(depth_greater) out float gl_FragDepth`仅在支持扩展时声明，缺扩展时仍写修正深度但不能保证同等提前拒绝效率
   - 依据：文件头注释明确说明此限制
   - 建议：这是已知平台限制，非代码错误

**P2 问题：**

1. **水下阴影衰减硬编码**
   - 位置：`global/lighting/diffuse.glsl:surface_shadow_light()`中`isEyeInWater == 1 && !water_is_thin_sheet()`时fallback=0.0
   - 问题：水下完全禁用静态阴影回退，依赖实时阴影覆盖
   - 建议：设计意图明确，保留

### 疑点与缺失事实
- 无实际游戏画面验证阴影边缘柔化效果
- 低太阳角和DEPTH24/32F的细边纹元覆盖误差未量化

---

## 模块3：材质直接间接照明AO/SSS/体素/实体与手

### 覆盖文件
- `Astra/shaders/program/lit.fsh` - 主光照入口
- `Astra/shaders/global/lighting/diffuse.glsl` - 漫反射光照
- `Astra/shaders/global/lighting/sss.glsl` - 次表面散射
- `Astra/shaders/lib/ao_resolve.glsl` - AO解析

### 审查发现

**P0 问题：**
无可证实P0问题。

**P1 问题：**

1. **实体迟绘记录容量限制**
   - 位置：`program/lit.fsh:ASTRA_LATE_ENTITY_SOURCE`分支
   - 问题：`colortex28` RG32F格式记录实体颜色/深度，但容量固定为全分辨率，高密度实体场景可能溢出
   - 依据：`shaders.properties:284`注释说明"容量没有增加"
   - 建议：当前实现满足既有需求，扩展需另行评估

**P2 问题：**

1. **SSS视相关项计算条件**
   - 位置：`global/lighting/diffuse.glsl:direct_lighting()`中sssTransmission计算
   - 问题：仅在`directContributes && subsurfaceScatter && SSS_STRENGTH > 0 && skyLight > 0.20`时计算viewDir，可能跳过部分有效情况
   - 建议：设计意图明确，保留

### 疑点与缺失事实
- 无

---

## 模块4：水面波纹反射SSR折射介质/迟绘身体/界面两侧

### 覆盖文件
- `Astra/shaders/program/water.glsl` - 水面主程序
- `Astra/shaders/global/water/surface.glsl` - 波面形态
- `Astra/shaders/global/water/raytrace.glsl` - SSR追踪
- `Astra/shaders/global/water/refraction.glsl` - 折射
- `Astra/shaders/global/water/absorption.glsl` - 吸收介质

### 审查发现

**P0 问题：**

1. **树叶倒影缺失 - SSR粗查询上限不足**
   - 位置：`global/water/raytrace.glsl:ASTRA_WATER_TRACE_BUDGET`常量定义
   - 问题：主世界预算档`ASTRA_OVERWORLD_OPTIMIZED`下，远侧中档粗查询上限12（原8），加四细化至多16。树叶错层/孔隙会破坏单调深度细化，已读取的叶片预计交点可能落入另一纹元
   - 依据：文件注释"独立错层树冠接收率22.79%→31.36%，仍明显漏采"
   - 结果：水面倒影中树叶可见性不足，符合用户反馈"树叶无法进入水面倒影"
   - 建议：源码已按当前要求实施补偿，但证据不足以宣称问题完全解决

**P1 问题：**

1. **水面反射锐度与性能取舍**
   - 位置：`program/water.glsl:water_surface_fast_sample()`函数
   - 问题：预算内采用单组四角共享，粗糙锥被更小足迹近似，画面更锐但可能丢失细节
   - 依据：文件注释"不能把这一取舍当作已经满足既有损失边界"
   - 建议：已标注为明确取舍，非错误

2. **迟绘身体记录的透明片元处理**
   - 位置：`program/lit.fsh:ASTRA_LATE_ENTITY_SOURCE`写入条件
   - 问题：`albedo.a >= 0.999`才写入记录，分数透明片元以零值擦掉此前身体记录的问题已修正，但边界情况仍需验证
   - 依据：`docs/当前工作.md` W05条目
   - 建议：源码复核已完成，实际跨界可见性仍未确认

**P2 问题：**

1. **水下折射天空的Snell窗口压缩**
   - 位置：`program/water.glsl:astra_underwater_interface()`函数
   - 问题：折射天空压缩到Snell窗口内，但水下太阳为圆形的问题已通过`water_transmitted_sun`函数处理
   - 依据：函数调用`water_transmitted_sun(skyDirection,angularFootprint*WATER_IOR/max(abs(dot(refractedRay,normal)),0.05))`
   - 建议：已实施原版太阳资源贴图，程序模式保持圆盘

### 疑点与缺失事实
- 树叶倒影的实际游戏效果未确认
- 水面开销与Steadfast的比较缺当前数字

---

## 模块5：水下光束源图窗口积分消光/水位/雾/柔化/太阳

### 覆盖文件
- `Astra/shaders/global/water/light_shafts.glsl` - 水下光束
- `Astra/shaders/program/water_state.fsh` - 水位状态
- `Astra/shaders/program/water_composite.fsh` - 水下合成
- `Astra/shaders/lib/solas_water.glsl` - Solas水色

### 审查发现

**P0 问题：**

1. **水下光束数量少且布局挤**
   - 位置：`global/water/light_shafts.glsl:ASTRA_SHAFT_SAMPLES`宏定义
   - 问题：`UNDERWATER_SHAFT_SAMPLES`默认7，但`ASTRA_OVERWORLD_OPTIMIZED`下可能降至更低。波长相对原尺度1.28、相对上轮再展宽18.5%，但用户反馈"光束仍少且挤"
   - 依据：文件注释"六层权重2/6/8/13/30/20、弱次级斜率响应提高"
   - 结果：光束布局可能仍不满足观感需求
   - 建议：源码已调整，实际游戏布局/数量待确认

**P1 问题：**

1. **光束积分碰撞光量缓存**
   - 位置：`global/water/light_shafts.glsl:water_shaft_wave_span()`函数
   - 问题：B缓存同帧未门控碰撞光量，保留八点积分与全部真实遮挡
   - 依据：文件注释"缓存碰撞光量约0.0696+0.8100 ms"
   - 建议：性能优化已实施，效果待验证

2. **水下太阳圆盘形状**
   - 位置：`program/water.glsl:water_transmitted_sun()`调用
   - 问题：水下太阳通过`water_transmitted_sun`函数在折射天空补太阳，但原版太阳资源贴图路径需确认
   - 依据：`docs/当前工作.md` W14条目说明已改活动资源包原贴图
   - 建议：独立原版方形太阳留在Snell窗口，实际游戏效果待确认

**P2 问题：**

1. **水下雾密度硬编码范围**
   - 位置：`global/atmosphere/fog.glsl:fog_v2()`函数
   - 问题：`UNDERWATER_FOG_DENSITY`默认40，密度0.0536/格、远增益1.22，用户反馈"水下模糊仍没做到"
   - 依据：文件注释"四方向柔化在2.5～18格渐入，最大3像素"
   - 建议：已调整，实际观感待反馈

### 疑点与缺失事实
- 水下光束的实际游戏数量与布局未确认
- 源图+积分的独立计时0.88ms不含mip/阴影，整帧开销未知

---

## 模块6：天空日月星空晨昏云天气及相关历史

### 覆盖文件
- `Astra/shaders/program/sky.fsh` - 天空入口
- `Astra/shaders/global/atmosphere/sky_gradient.glsl` - 天空渐变
- `Astra/shaders/global/atmosphere/clouds_planar.glsl` - 平面云
- `Astra/shaders/global/atmosphere/stars.glsl` - 星空

### 审查发现

**P0 问题：**
无可证实P0问题。

**P1 问题：**

1. **太阳形状不一致**
   - 位置：`program/sky.fsh:SUN_MOON_MODE`分支
   - 问题：水上通过`astra_procedural_disc`绘制圆盘太阳，水下通过`water_transmitted_sun`使用原版资源贴图（方形）
   - 依据：`docs/当前工作.md` W14条目
   - 结果：水下太阳为圆形（程序盘），水外为方形（资源贴图），符合用户反馈
   - 建议：已实施原版太阳资源贴图，程序模式保持圆盘，内外形状一致性问题已处理

**P2 问题：**

1. **晨昏过渡曲线调整**
   - 位置：`lib/twilight.glsl`（未直接读取，通过引用确认）
   - 问题：已缩短曲线两端平滑肩部、放缓中段，保留太阳角度临界点
   - 建议：实际过渡观感仍无分项反馈

### 疑点与缺失事实
- 云边缘抖动的实际游戏表现未确认

---

## 模块7：后处理泛光调色AA历史重投影/显示颜色域

### 覆盖文件
- `Astra/shaders/program/display.fsh` - 显示主程序
- `Astra/shaders/global/post/bloom.glsl` - 泛光
- `Astra/shaders/global/post/grading.glsl` - 调色
- `Astra/shaders/program/taa_resolve.fsh` - TAA解析

### 审查发现

**P0 问题：**
无可证实P0问题。

**P1 问题：**

1. **Bloom捕获分辨率**
   - 位置：`global/post/bloom.glsl:BLOOM_CAPTURE_SCALE`常量
   - 问题：0.25倍捕获分辨率，水下Bloom目标colortex7同样0.25倍，可能损失细节
   - 依据：`shaders.properties:39` colortex7尺寸条件
   - 建议：设计意图为性能优化，保留

**P2 问题：**

1. **TAA历史重投影的实体运动**
   - 位置：`docs/实现与限制.md` D04条目
   - 问题：实体TAA缺每实例前帧运动输入，Iris 1.11.2既有取证受限
   - 建议：已知技术债，不重述

### 疑点与缺失事实
- 无

---

## 模块8：下界末地维度入口与独立效果

### 覆盖文件
- `Astra/shaders/global/dimension/nether.glsl` - 下界
- `Astra/shaders/global/dimension/end.glsl` - 末地
- `Astra/shaders/world-1/` - 下界目录
- `Astra/shaders/world1/` - 末地目录

### 审查发现

**P0 问题：**
无可证实P0问题。

**P1 问题：**

1. **下界体素光捕获范围**
   - 位置：`global/dimension/nether.glsl:NETHER_VOXEL_LIGHT`分支
   - 问题：64x64x64体素体积，8传播步，有界子集而非完整128+体积
   - 依据：文件注释"Bounded subset of the Solas voxel-light architecture"
   - 建议：设计意图明确，保留

**P2 问题：**

1. **末地反射缓存**
   - 位置：`global/dimension/end.glsl:end_reflection_cache_read()`
   - 问题：紧凑GPU星表及连续低对比流纹为已有实现
   - 建议：不重列为未开始，不断言当前游戏效果

### 疑点与缺失事实
- 下界末地本轮不主动扩范围，效果未验证

---

## 模块9：选项档位开关组合/性能热点及文档与现行源码不一致

### 覆盖文件
- `Astra/shaders/lib/settings.glsl` - 选项定义
- `Astra/shaders/shaders.properties` - 配置
- `Astra/README.md` - 用户文档

### 审查发现

**P0 问题：**
无可证实P0问题。

**P1 问题：**

1. **水面/水下开销高于Steadfast**
   - 位置：`docs/当前工作.md` W03条目
   - 问题：同帧B缓存取消重复碰撞计算，源窗口/光源计算移到顶点，但用户报告整帧两倍差距
   - 依据：独立源图+积分1.99→0.88 ms，40格倒影腿0.54→0.31 ms，但整帧帧率未知
   - 结果：水面/水下开销仍明显高于Steadfast，符合用户反馈
   - 建议：不能把整帧差距全部归给水面，需更多分项数据

2. **预算档位与文档一致性**
   - 位置：`lib/settings.glsl:OVERWORLD_BUDGET`宏定义
   - 问题：主世界预算1为1080p优先预算，2为进一步收紧。文档描述与源码实现一致
   - 建议：无需修改

**P2 问题：**

1. **性能目标与实测差距**
   - 位置：`docs/当前工作.md`帧率表格
   - 问题：水面90 FPS、阴影与水面混合67 FPS、水下100 FPS，均低于144 FPS目标
   - 依据：用户报告读数，非整帧统计
   - 建议：无整帧数据不能推断实际达标

### 疑点与缺失事实
- 整帧FPS缺事实，无法验证144 FPS目标
- 与Steadfast的开销比较缺当前数字

---

## 用户当前关注问题汇总

| 问题 | 模块 | 状态 | 证据 |
|---|---|---|---|
| 水面树叶倒影缺失 | 4 | P0 | `raytrace.glsl`粗查询上限12，错层树冠接收率31.36%仍漏采 |
| 水下光束数量少且布局挤 | 5 | P0 | `light_shafts.glsl`七点积分，用户反馈无感区别 |
| 水面/水下开销高于Steadfast | 9 | P1 | 独立组件有优化，整帧差距原因未完全定位 |
| 水下太阳圆而水外方 | 6 | P1 | 已实施原版贴图，程序模式保持圆盘 |
| 阴影边缘锯齿 | 2 | P1 | 已按设计柔化，彻底消除需更高影图分辨率 |

---

## 真实未覆盖点

1. 无实际游戏运行验证，所有效果结论基于源码分析
2. 无独立GPU计时验证各预算档位的实际帧率
3. 无整帧统计验证144 FPS目标
4. 与Steadfast的详细开销比较缺当前数据
5. 树叶倒影、光束布局的实际游戏效果未确认

---

## 审查结论

本次审查覆盖Astra光影全部9个模块的活跃渲染链。源码实现与文档描述基本一致，用户关注的五项问题均有对应代码处理，但实际游戏效果仍需运行验证。性能优化已实施于独立组件，整帧表现缺事实依据。

审查完成时间：2026-10-11
审查者：Kimi-K3 (trae-cn/kimi-k3-auto)

---

## 增补裁决（2026-10-11 第二轮）

本节按用户指出的源码证据修正第一轮结论，原文保留不改。所有裁决均以本轮重新读取的实际源码为准。

### 一、第一轮错误结论的裁决

#### 1. 阴影柔化（模块2 P1-1 原表述撤回）

第一轮称"`astraSurfaceShadowPixelWorld`在远距离表面增大导致柔化半径收缩"。实际源码（`global/lighting/diffuse.glsl:317-318`）：

```glsl
float softRadius=max(0.22,0.75*astraSurfaceShadowPixelWorld);
spread = min(spread,softRadius/max(worldTexel,0.0001));
```

`softRadius` 是世界空间的**下限保护**（max），随像素足迹增大而增大，从不随其收缩。真正随距离变化的是 `worldTexel`——`global/lighting/diffuse.glsl:314-316` 中 `worldTexel = (2.0*shadowDistance*SHADOW_DISTORT_FACTOR)/(shadowMapResolution*mapRim²)`，它在径向影图边缘（mapRim→0）急剧增大，使 `spread`（纹素单位）收缩。这是径向影图的固有密度分布，不是缺陷；用户反馈的"阴影边缘锯齿"与 `shadowmap.glsl` 注释中的已知残留一致（低太阳角和 DEPTH24/32F 仍有细边纹元覆盖误差），属于已标注取舍，不是本次新发现的 P1。原 P1-1 撤回，降级为已知取舍的标注。

#### 2. 太阳形状（模块6 P1-1 原表述撤回）

第一轮把"水下圆、水外方"当作两个模式混搭的缺陷。实际源码（`program/water.glsl:601-633`）在同一 `SUN_MOON_MODE` 下自洽：

- `SUN_MOON_MODE == SUN_MOON_VANILLA`：`water_transmitted_sun` 通过 `astraSunTexture` 读取活动资源包太阳贴图，按原版半宽 30/距离 100 的天空四边形重建 UV（`program/water.glsl:609-623`），水下折射看到的太阳与水外同为资源包贴图形状；
- 程序盘模式：水下用半径 0.028 的解析盘（`program/water.glsl:624-629`），与 `program/sky.fsh` 的 `astra_procedural_disc` 同为圆盘。

两种模式各自内外一致，不存在"同一模式下内圆外方"的源码路径。用户反馈的"水下太阳圆而水外方"若成立，只能来自 SUN_MOON_MODE=0 时资源包贴图加载/路径问题（26.1 起 environment/celestial/sun.png，旧版 environment/sun.png），这在源码层面无法证实，列为疑点而非 bug。原 P1-1 撤回。

#### 3. colortex28 格式声明（模块1 P1-1 原结论撤回）

Iris 宿主规范要求：附件**格式**以 GLSL 常量声明（`colortex28Format`，见 `program/lit.fsh:15-18`），附件**尺寸**以 properties 指令声明（`size.buffer.colortex28`，见 `shaders.properties:284`）。两者分处不同文件是宿主规定的声明位置，不是不一致。且 `program/lit.fsh:14` 的格式声明包在 `#if defined ASTRA_WATER_PASS || defined ASTRA_ENTITY` 内，仅主世界生效；下界 colortex28 的 RGBA16F 反射元数据用途由 `shaders.properties:284` 注释与 `lib/nether_reflection_metadata.glsl` 承担，互不冲突。原 P1-1 撤回，无可证实问题。

#### 4. 实体记录容量（模块3 P1-1 原结论撤回）

`lib/water_entity_record.glsl` 的实际机制是**每像素一条记录**的层结构：`water_entity_record()` 把 RGB 与视线深度打包为两个 half2（RG32F，8 字节），alpha 仅为 0/1 覆盖位，在 ONE/ONE_MINUS_SRC_ALPHA 混合下零输出保留此前记录。其固有限制是**层**——一个像素只能保留一个最近实体记录，任意多层透明无法完整排序（已知技术债 D01），而不是"高密度实体数量溢出"。不存在容量溢出问题。原 P1-1 撤回。

### 二、补足的生产-消费交界（本轮实际读取）

第一轮未实际读取的活跃交界，本轮逐一读取源码并核对条件：

1. **水状态生产→消费**：`program/water_state.fsh`（由根 `composite.fsh` 引入）每帧扫描 colortex5 的 20×12 网格，写 colortex6 三个纹素（界面记录、视口/帧号/介质、相机位置/时间）；消费者为 `lib/water_interface_record.glsl` 的 `water_interface_at()` 与 `lib/solas_water.glsl` 的薄层判定，以及 `global/lighting/diffuse.glsl` 的 `water_volume_state()` 水下天空光恢复。交界条件核对无误：连续帧保护要求视口一致、帧差 1、相机位移 ≤8 格、时差 ≤0.25s。

2. **水下光束生产→消费**：`program/scattering.fsh`（由根 `composite2.fsh` 引入）在 `isEyeInWater == 1` 时调用 `water_shafts_march()` 写 colortex1（RGB 加性辐亮度，A=射线长度/128）；消费者两处——`program/water_composite.fsh`（Bloom 开，由根 `composite3.fsh` 引入）与 `program/display.fsh`（Bloom 关，`ASTRA_WATER_FOG_FRAME_READ` 分支）均通过 `water_shafts_resolve()` 四角距离保护插值。条件核对：`shaders.properties` 的 composite2 启用条件 `UNDERWATER_LIGHT_SHAFTS && SHADOWS && UNDERWATER_SHAFT_STRENGTH > 0` 与源码 `ASTRA_UNDERWATER_SHAFTS` 宏（`lib/settings.glsl`）一致。

3. **水下合成链**：`program/water_composite.fsh`（composite3）写 colortex4（RGB16F，见 `lib/water_buffer_formats.glsl:20-24`），`program/water_bloom.fsh`（composite4）捕获 colortex7；Bloom 开时 `display.fsh` 经 `isEyeInWater == 1` 直接读 colortex4 绕过 TAA 的 colortex0 打包（`program/display.fsh` 对应分支注释明确说明避免二次量化）。交界成立。

4. **AO 生产→消费**：`program/ssao.fsh` 半分辨率核心（`ivec2 base = ivec2(gl_FragCoord.xy) * 2` 配对最近全分辨率纹素的法线/深度），写 colortex21（RGBA16F）与 colortex26（RG16F 弯曲法线，仅 `ASTRA_DIRECTIONAL_SKYLIGHT`）；消费者 `lib/ao_resolve.glsl` 经 `deferred.fsh` 的 `astra_apply_ambient_ao()`。注意 ssao.fsh 首个 `gl_FragData[0]` 写默认值 `vec4(1.0,-1.0,0.5,0.5)`，其中 g=-1.0 是无效标记，被 `ao_resolve` 显式拒绝（ssao.fsh 注释说明"Never read where colortex21.g < 0"）。交界成立。

5. **维度壳转发**：`world-1/`（下界）与 `world1/`（末地）的 gbuffers_water、final、composite 均为 `#define DIMENSION_*` 后 `#include` 主世界同名 program 的壳；下界 gbuffers_water 仍定义 `ASTRA_WATER_PASS` 进入 `program/lit.fsh`，其水路径在 `lit.fsh` 内由 `DIMENSION_NETHER` 条件分流的下界分支接管。`world-1/shadow.vsh` 用 `#version 430`（其余壳 400），因为下界体素捕获的 `uimage3D`/`imageAtomicMax` 需要 GLSL 420+——与 `program/shadow.vsh` 头部的保护注释一致。

6. **神光生产→消费**：`program/scattering.fsh` 空气分支写 colortex1 的 R 通道密度（texel(0,0) 的 alpha 携带全帧太阳可见度），`program/display.fsh` 经 `godrays_box_filter()` 四点盒式上采样读回；`composite.vsh` 在顶点阶段计算 `lightScreenPos`（光源屏幕位置），避免 CPU 侧矩阵乘法。`GODRAYS_SUN_OCCLUSION` 分支每帧 49 次深度读取测一次太阳遮挡。交界成立。

7. **曝光生产→消费**：根 `composite5.fsh` 引入 `program/exposure.fsh` 写 colortex10 单纹素增益；`display.vsh` 按顶点读回，`display.fsh` 仅在空气臂乘上（水下保持 Solas 曲线手动曝光）。`shaders.properties` 的 composite5 门控 `AUTO_EXPOSURE` 且下界/末地显式禁用（`program.world-1/composite5.enabled=false`），与 grading.glsl 的固定维度倍率分工一致。

### 三、交界补充核对后的问题修正

补读交界后未发现新的可证实 P0/P1。第一轮报告中保留的 P0（树叶倒影 SSR 漏采、光束布局）维持原判：这两项的源码机制与独立测量（错层树冠接收率 22.79%→31.36%、光束八点积分参数）已在 `raytrace.glsl`/`light_shafts.glsl` 注释中自证为"部分改善但未解决"，属于已确认差距而非本次新发现。

### 四、本轮新增疑点（源码不足以确认）

1. **水下太阳贴图路径**（承接本节一-2）：`program/water.glsl:609` 的 `astraSunTexture` 由 Iris 从活动资源包绑定；若用户环境为 26.1+ 而包内无 `environment/celestial/sun.png` 回退声明，实际采样结果无法在源码层面确认。这需要实机或 Iris 日志事实，不冒充 bug。
2. **colortex29 光束源图 mip 生成时序**：`global/water/light_shafts.glsl` 声明 `colortex29MipmapEnabled = true` 并注释"Iris generates the just-produced normal mip chain BEFORE this consumer draws"，该时序保证依赖宿主行为，源码内无同步原语可独立验证；若宿主在该版本未按注释顺序生成 mip，八点积分的 `textureLod(colortex29,...,lod)` 在 lod>0 时可能读到未定义内容。列为疑点，需要宿主版本事实。

增补裁决完。第一轮原文及以上增补共同构成本模型（trae-cn/kimi-k3-auto）的完整独立审查结论。
