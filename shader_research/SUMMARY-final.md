# Astra 光影包参考调研 — 最终汇总报告

调研方式：本地 7 个参考包 grep + 在线批次 1–4（raw.githubusercontent / Modrinth）+ 夜空专项。
证据分级：【实测】= 跑了工具或读了源码；【推断】= 由谱系、结构或未核实的摘要得出，使用前必须核。
借用流程不变：读思路 → 独立重写 → 文件头标注来源 → 登记 `Astra/THIRD-PARTY.md`；直接搬代码仅限 MIT / LGPL / GPL。

---

## 一、结论速览

- 调研约 40+ 个包，筛出 **5 项第一级候选**（低成本、Astra 确认未有、许可明确或待核但倾向可用）、**5 项第二级**（中等成本或需先核实）、**6 项仅思路**（许可限制）。
- 排除三类：Astra 已有实现（含本轮新确认的星空锚定、解析高度雾）、许可禁止直接借用的包、超出 Iris 管线范围的 Dirt-RT。
- 本轮修正两条旧结论：一是星体锚定已实现（shaders.properties:756），不再是候选；二是解析高度雾已有（global/atmosphere/fog.glsl:40-63），glimmer 的 fog.glsl 项作废。

---

## 二、第一级候选（建议优先）

### 1. 关闭阴影贴图 mipmap —— 一行配置，纯省显存

【实测】Astra 全包无 generateShadowMipmap 指令（grep 0 命中）。Iris 默认会为阴影贴图生成 mipmap（逐级缩小的纹理副本），供按 lod 采样的软阴影用。但 Astra 所有阴影采样都是直接读 shadowtex1（global/lighting/shadowmap.glsl:348，texture(shadowtex1, ...)），从不按 lod 取值——这些 mipmap 是白生成的，白占显存。
【实测】来源：butter（MIT，MakeUp 6.80L 衍生）lib/config.glsl:140-141 设 generateShadowMipmap = false。
建议：在 lib/settings.glsl 阴影段加一行 const bool generateShadowMipmap = false; 改动前先在实例里确认本机 Iris 版本行为（ShaderDoc 对该指令覆盖不全）。

### 2. PCSS 阴影软化（可变半影）

【实测】Astra 无任何半影（penumbra）/遮挡体搜索实现：grep penumbra 0 命中；blocker 的命中只是保守深度注释（shadowmap.glsl:220、program/shadow.vsh:89），不是 PCSS。
PCSS 是什么：现在 Astra 的阴影模糊半径固定——无论遮挡物远近，边缘糊的程度一样。PCSS 先在阴影贴图里搜一小圈，找"遮挡体离接收点多远"（blocker search），再按这个距离放大模糊半径：近遮挡锐利、远遮挡柔软，和现实影子一致。
【实测】来源：Shrimple lib/shadows/distorted/render.glsl:140-178（blocker 搜索 + 半影计算）。
许可：Shrimple 许可未核实（【推断】社区普遍称 MIT，使用前必须查仓库 LICENSE）。核实前按"仅思路"处理。

### 3. 世界空间阴影模糊（降噪替代加大贴图）

【实测】grep 阴影模糊变体 0 命中——Astra 阴影没有独立的空间模糊 pass，抖动噪声靠 TAA 收敛。
做法：把带噪声的阴影结果写进一张中间缓冲，下一 pass 按世界空间距离（几厘米固定半径，用深度反推）加权模糊。好处是模糊核在"世界里的厘米数"上恒定，镜头拉近拉远都稳，且能把低分辨率阴影贴图的锯齿糊掉而不增加贴图分辨率。
【实测】来源：Shrimple render.glsl:122-136（世界空间半径换算）。
许可：同上待核。与第 2 项同源，可一起评估。

### 4. 星形镜头炫光

【实测】Astra 的 glare 14 处命中全部是雾-地平线光晕（global/atmosphere/scene.glsl:190-220 一带），没有镜头炫光；lens_flare 0 命中。
做法：在最终合成附近，从太阳/月亮屏幕位置沿几条放射状叶片（如 6 叶、可调角度）画衰减光条，强度乘天空可见度与遮挡测试。它与现有"泛光"不同——泛光是画面亮区扩散，炫光是光源方向的放射条纹，二者可共存。
【实测】来源：Noble（GPL-3.0，master）include/post/glare.glsl。GPL 允许移植代码，但移植后 Astra 相关文件需按 GPL 处理并登记 THIRD-PARTY.md。

### 5. colortex0 关闭清屏（低置信，先验证收益）

【实测】Astra 已有 20+ 处 colortexNClear = false（历史缓冲、TAA 状态等），但主颜色缓冲 colortex0 未设 colortex0Clear = false（lib/settings.glsl:759 只设了 clearColor）。stracciatella（与 drdestens 共享 ShaderCore，许可待核）lib/setup.glsl:29-33 用它跳过每帧对主缓冲的清屏。
【推断】收益取决于 Astra 合成链是否每帧完整覆写 colortex0——若是，关掉清除是免费的；若有依赖清除初值的路径（如半透明叠加）会出残影。实施前必须沿 composite→final 链核一遍写覆盖。

---

## 三、第二级候选（中等成本 / 需先核实）

1. **水下 SSR 加固**【推断】dercode（自称 Bliss 衍生，引用前需与上游核实）lib/Surface/ScreenSpaceReflections.glsl:65-76,94-112,124-145：水下折射面 SSR 的边缘与未命中处理加固。Astra SSR 未命中回退已有，水下场景的加固分支未核。许可待核。
2. **末地黑洞引力透镜**【实测】lumina（GPL-3.0）eventHorizon.glsl:105-147：对末地黑洞周围的采样方向做偏折，背景星空产生扭曲。Astra 末地有吸积盘但无透镜扭曲。GPL 可搬代码；收益偏装饰性，优先级看用户。
3. **粒子独立简化光照**【实测】blocky-shader gbuffers_textured_lit.fsh:12-20 + composite_frag.glsl:61-65,318-320：粒子用极简光照（省阴影/法线采样），雾在合成后统一补，避免每个粒子重复算雾。许可待核。
4. **屏幕空间彩色方块光合并（时间累积瓦片）**【实测】stracciatella B1 + zayko MCBL（colortex5→6→32×18 瓦片时间累积）。Astra 彩色方块光是常量级（block.properties:94 分组 + blocklight.glsl:24 常量表），这是另一条路线（屏幕空间采集真实发光块），不冲突但工程量中等。
5. **单像素聚合 + 纹理广播（SALS）**【推断】把同像素多采样合并为一次、经纹理广播分发，属 G-buffer 带宽优化；细节未深读，Astra 是否有等价路径未核。

---

## 四、仅思路（许可限制，不得搬代码）

| 特性 | 来源（文件:行号） | 许可 | 一句话 |
|---|---|---|---|
| 体素彩色光传播 LPV | just-colored-lighting main_f.glsl:1612-1785；每帧 8 位光场 -1/255 抗重影 voxel_photons.csh:381-383 | ARR | 每帧把发光块光子注入 3D 纹理传播；Astra 下界 64³ 体素 GI 已有基础，思路可续 |
| 渐变积雪 | Complementary Reimagined lib/materials/materialMethods/snowyWorld.glsl（法线朝上>0.9 + 天光>0.9 + 方块光抑制；noisetex 混雪色/压粗糙度/压发光） | Complementary 1.5 | 逐面渐变积雪，Astra 雪只有基础路径 |
| HiZ 阴影剔除 | amethyst shadowcomp.glsl:11-12,72-89 | CLA 1.5 | 用深度金字塔整块跳过阴影计算 |
| 方块光颜色表 | amethyst blocklightColors.glsl:11-177 | CLA 1.5 | 按方块 id 精细配 15 级光色（Astra 现表是按色系粗分组） |
| SDF+DDA 光追 | spring pathTracing.glsl:246-423 | CC-BY-NC-SA-4.0 | 有向距离场加速的体渲染，NC 禁商用 |
| 阴影内变暗+去饱和 / 3 段方块光衰减 | Insanity lib/lighting/forwardLighting.glsl:75-108；Hysteria include/light/handheld_lighting.glsl:31-45 | 待核（Chocapic13 谱系） | 阴影里颜色情绪化处理；方块光按亮度分 3 段衰减曲线 |

---

## 五、排除项（有证据，勿再议）

**Astra 已有（本轮 grep/读码确认或既往确认）**：扭曲阴影贴图、PCF、彩色阴影（light_shafts.glsl:124 采 shadowcolor0）、水下吸收/散射/光束/焦散、SSR、下界 IPBR 反射 + 64³ 体素 GI、末地吸积盘、Uchimura 色调映射、分析式水面法线、保守深度阴影、TAA/FXAA、云阴影缓存、SSAO（半分辨率+golden-angle，ssao.fsh）、SSS（global/lighting/sss.glsl）、Purkinje（grading.glsl:132）、AUTO_EXPOSURE（64-tap，colortex10 历史）、月相天空、水洼/雨涟漪/湿润地面（weather.glsl:21-101）、手持光（CPU+GPU 完整链）、雪基础路径、**星空锚定**（shaders.properties:756 astraClockAngle=worldTime*0.000261799387799；stars.glsl:7 注释明说替换了 frameTimeCounter 漂移——nightsky 摘要里"主世界缺 worldTime"的说法已过时）、**解析高度雾**（fog.glsl:40-63 谷雾，两 smoothstep 一 mix；glimmer fog.glsl:76-151 项作废）、单星色温（stars.glsl:39-47 有意选择调色板而非逐星黑体，不建议改）、batch4 §2.5 八个技术系列（顶点帧常量、SSR 回退、分析天空反射、雨天阈值、半分辨率 AO、无阴影回退、云透射截断、TAA 邻域裁剪）。

**许可禁止直接借用**：Photon（条件再分发）、kuda（Agreement.txt:9-15）、amethyst/lumina/pyvtron（CLA/版权钩）、Pegasus/Simply Upscaled/just-colored-lighting（ARR）、Bloop/spring（NC）、Fantasy Reimagined（Complementary 1.5）、What42 2.2（I Like Vanilla）。

**超范围**：Dirt-RT（Vulkanite RT-core，非 Iris 管线）。

**反面案例**：stereos-default+ 2.4——每采样无条件读 shadowtex0+shadowtex1+shadowcolor0，零创新，引以为戒。

**纯减法/零增益**：dreamlight（Mellow 重制）、monophonic（Exposa lite）。

---

## 六、缺口（本轮未完成，接手者从这里继续）

- RenderPearl（MIT）：compute/SSBO 用法、CAS/SMAA 归属未在线核实到文件级。
- Pixel Perfect 1.5.2（LGPLv3，Modrinth ZvitaqQh）特性未深入。
- 本地 7 包之外的未映射副本（bliss、kappa、nostalgia、hysteria、super duper vanilla）未纳入本轮证据。
- 许可待核名单：Shrimple、stracciatella、dercode、blocky-shader、lux、Insanity/Hysteria 谱系细节。