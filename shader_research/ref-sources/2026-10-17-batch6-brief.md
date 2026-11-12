# 第六批调研共用简报（只读调研，2026-10-17）

你在为 Minecraft Iris 光影包项目 Astra 做只读外部调研。工作目录 C:\Users\杨铭\Desktop\MC模组开发\Astra光影开发。

## 硬性要求
1. 不修改 Astra/、reference_shaderpacks/、docs/ 下任何文件。只允许在 shader_research/ref-sources/ 下新增小型材料文件（确有必要才存）。
2. 先读以下排除清单，凡其中已覆盖的候选、已驳回项、已裁决不做项，一律不得再列为新候选：
   - docs/参考与取舍.md（含"不重新尝试的旧方案"与"候选进入条件"）
   - shader_research/SUMMARY-final.md（第1-4批汇总）
   - shader_research/SUMMARY-batch5.md（第五批 A01-A31、B01-B12、C01-C10、V1/V5 等）
   - shader_research/2026-10-17-可参考机制调研-Astra缺口.md（最新8+1条候选与"明确不建议做"清单）
   - shader_research/2026-10-06-recent-online-shader-updates.md（近期发布已查范围）
3. 判"Astra 没有"必须实测：用 grep 工具在 Astra/shaders 全树搜关键词，记录关键词与命中数；有命中要读源码确认是否等价实现。关键词命中不等于机制存在（空 #ifdef、注释也算命中）。
4. 每条候选必须给全七项：机制名／一句话通俗原理／出处（文件:行号或 URL+分支/版本）／Astra 缺口证据（关键词+命中数）／落地位置建议（Astra 哪个文件哪个函数附近）／成本估计（新附件、新 pass、每像素采样数）／许可（能否代码级借用）。证据强度标注〔读源码〕〔实测工具〕〔推断〕。
5. 性能收益无实机依据一律写"未验证"。不报纯风格向、不报宣传文案无源码支撑的项。
6. 结果直接返回 markdown 候选条目列表，按性价比排序，5-15 条实质候选，宁缺毋滥。最后附一节"查过但判定 Astra 已有/已覆盖的项"简表（防止主代理重复派查）。

## Astra 能力基线速览（仍须自行 grep 验证）
已有：畸变阴影图+16角点PCF+彩色阴影+静态阴影兜底、SH9方向性天光、SSAO(12点金角)、SSS植被透光、SSR/水下反射/折射/解析焦散、ITT水下波场+分色吸收+8点光束、物理天空+平面云(时域历史+云柱裁剪)+独立云影缓存+日月贴图过滤+星表/银河、雨湿地面+稀疏积水+雨涟漪、手持光分色+方向感、下界64³体素彩光(9阶段同帧传播)+岩石/砖反光+局部彩光、末地Kerr黑洞+吸积盘+引力透镜、Bloom、4种色调映射(Uchimura默认)、颜色分级、FXAA/TAA(3×3方差裁剪YCoCg)、自动曝光(64tap对数域,默认关)、暗角、Purkinje、解析高度雾、步进体积雾(默认关)、godrays遮挡积分、闪电照明、植被摇曳(距离权重)、平面云倒影、水面天空反光缓存(128×64/256×128)、湿雪基础路径。

引擎：Iris 1.11.2+mc26.2；已声明 optional 特性仅 CUSTOM_IMAGES COMPUTE_SHADERS；colortex0-31 仅 colortex7 空闲；colortex0 为 R11F_G11F_B10F 无 alpha；有 customTexture(15处)、compute 链(下界体素+末地星表)、image3D。

无（主代理已 grep 实测 0 命中）：DOF、运动模糊、镜头光晕/炫光、色散、SMAA、CAS锐化、PCSS、GTAO、SSGI、RSM、froxel雾、发光矿石、积雪渐变、雪脚印、热浪扭曲、局部曝光、直方图曝光、3D蓝噪声、流星/极光、程序化传送门纹理、玩家挤开植物、阵风亮度调制、附魔glint增强、信标光束特效、末影水晶特效、水下气泡。

## 本地材料位置
- reference_shaderpacks/ 7包: solas-shader、complementary-reimagined、photon-shader、rethinking-voxels、makeup-ultra-fast-shaders、mellow、arc-shader
- _analysis/batch5_unpack/ 33个解包包(velocity/kute/escheridia/luster/muuf/artshade/verlixia/TrueLightFX/prismarine/fantasy/lumeau/relumination/ctrvcr/wispy/crumb/terders/essentials/highframes-plus/motion-blur-fx等)
- _analysis/irispk/ Iris 1.11.2+mc26.2 解包844类（引擎键与uniform权威依据）
- shader_research/ref-sources/grindstone(SMAA+CAS MIT)、contour(描边思路)
- _analysis/mr_top200_projects.json、mr_recent_projects.json
- ITT 3.2: _analysis/latest-2026-09-10/iterationT-3.2.0/；Steadfast 0.8.0: _analysis/steadfast-2026-10-02/
