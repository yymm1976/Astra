#ifndef ASTRA_GLOBAL_WATER_PARTICLES_GLSL
#define ASTRA_GLOBAL_WATER_PARTICLES_GLSL

// Astra v1 — global/water/particles.glsl
// written for Astra (self-authored). No reference-pack expressions are ported.
//
// 水下悬浮颗粒（design.md §4.3 水下氛围行：水下雾 / 悬浮颗粒 / 雾色随深度渐变——本模块
// 补齐三项中的"悬浮颗粒"）。观感对标 **Solas 水下**（SC-24 口径）：少量、柔和、缓慢漂移
// 的白色微尘，随天光可见度变化，近处清晰、远处被水色吸收吞掉。四个参考包都没有屏幕空间
// 悬浮颗粒实现（检索命中的 `particle` 全是原版粒子 sprite 的 gbuffers 路径），故本模块为
// Astra 自写——发布闸门（SC-14）不受影响，无需 REWRITE 标记。
//
// 算法（解析 motes，非 raymarch）：
//   相机水下时，沿视线方向取 3 个固定距离的"壳层"（3/6/12 格，exp2 阶梯）。每层把壳层上的
//   世界位置量化进 3D 晶格（cell = 2 格），整型 hash 决定该 cell 是否有 mote、其在 cell
//   内的偏移、亮度与闪烁相位；径向 smoothstep 得到柔和圆点。比 screen-space 粒子便宜得多
//   （无纹理采样）。壳层仅用于稀疏近似，晶格固定在世界坐标中，相机平移时有相对运动。
//
// 无 TAA 约束（design.md 2.4，同 SC-19 对焦散的要求）：
//   - 闪烁是每 mote 独立相位的**慢速**正弦（周期数秒），不是帧号抖动；
//   - 半径固定、亮度连续，不做黑白突变。
//
// 噪声策略偏离登记：与 end.glsl 星野同一理由（design.md 5"噪声优先查表"的记录在案例外）——
// 稀疏点过程的 cell 中心/相位是离散量，noisetex 双线性查表无法表达，只能用整型 hash。
// hash 结构沿用 end_hash_uint 的乘-移位混合（Astra 已确立的公共域模式，非移植）。
//
// Interface contract:
//   vec3 water_particles(vec3 rayDir, float sceneDistance, float skylight, float time)
//     rayDir        — 视线方向（世界轴、相机原点，normalize(playerPos) 即可；天空像素给远平面方向）。
//     sceneDistance — 该像素已渲染几何的视距（格）；天空传大值（如 65536.0）表示"无遮挡"。
//                     壳层距离 >= sceneDistance 时该层（及更远层）被几何遮挡，逐层 break。
//     skylight      — 相机处的平滑天光（0..1；微尘位于眼前水体中）。
//     time          — frameTimeCounter。
//   返回**加性** HDR 光（在 final 中叠加；不进 colortex4 的 SSR 背景副本——反射背景不应
//   含雾中微尘）。
//
// Uniforms: isEyeInWater, cameraPosition, blindness, dayUnderwaterFogFade；time 由参数提供。
// Requires（program-ordered，SC-10 同层不互相 include）：
//     lib/settings.glsl（UNDERWATER_PARTICLES）、lib/uniforms.glsl（isEyeInWater）、
//     global/water/absorption.glsl（water_absorption，距离衰减）必须先于本文件被 include
//     ——final.fsh 保证 absorption 在闭包内。
// Owner: C2（UNDERWATER_PARTICLES 选项的接线方，SC-28 台账登记的归属）。
// Consumer: program/final.fsh（半透明完成后、tonemap 前；SC-32）。
// 选项门控沿用 caustics.glsl 的既有模式：函数恒有定义（关闭时为 0 向量的早退），
// #ifndef/#else 分流同时满足 SC-28 的注册规则（Iris 只认 #ifdef/#ifndef 引用）。

// 三层壳距（格）：近层细节、远层氛围；exp2 阶梯保证任意视距下首层都能覆盖。
const float PARTICLE_SHELL_BASE = 3.0;
const int   PARTICLE_SHELLS = 3;

// 晶格与 mote 形状。
// SC-35（2026-09-08 实测）：颗粒喧宾夺主——命中率 0.35→0.16、半径 0.30→0.24、
// 强度 0.10→0.045，静止画面中只保留非常轻微的水体悬浮物层次。
const float PARTICLE_CELL = 2.0;          // 每 2 格一个候选 cell
const float PARTICLE_DENSITY = 0.16;      // cell 命中率（Solas 观感：稀疏）
const float PARTICLE_RADIUS = 0.24;       // mote 半径（cell 的 24%）
const float PARTICLE_EDGE = 0.55;         // softstep 起始（越大越柔）

// 漂移：世界坐标中的缓水流与缓慢上升。
const vec3 PARTICLE_DRIFT = vec3(0.30, 0.045, -0.22);

// 亮度与颜色：白蓝微尘；峰值强度刻意低（HDR 加性，后接 tonemap）。
const float PARTICLE_INTENSITY = 0.045;
const vec3  PARTICLE_COLOR = vec3(0.72, 0.88, 1.0);
// 暗水底亮：无天光时保留 5% 可见度（深洞微尘几乎不可见，符合 Solas 观感）。
const float PARTICLE_DARK_BASE = 0.05;

// 闪烁周期下限（秒）：慢到肉眼读作"微尘反光"而不是噪点。
const float PARTICLE_SHIMMER_SPEED = 1.7;

// 整型 hash（公共域乘-移位混合，与 end.glsl 的 end_hash_uint 同构但独立声明——
// 同编译单元不允许重复定义，前缀区分）。
uint particles_hash_uint(uvec3 p) {
	uint h = p.x * 1597334677u + p.y * 3812015801u + p.z * 2798796415u;
	h = (h ^ (h >> 16)) * 2246822507u;
	h = (h ^ (h >> 13)) * 3266489909u;
	return h ^ (h >> 16);
}

float particles_hash1(uvec3 p) {
	return float(particles_hash_uint(p)) * (1.0 / 4294967296.0);
}

// 每层贡献：一个 cell 内的柔和圆点。
float particles_shell(vec3 pos, uvec3 seed, float time) {
	vec3 cell = floor(pos / PARTICLE_CELL);
	uvec3 id = uvec3(ivec3(cell)) + seed;

	// 存在性：先拒后算（~65% cell 直接归零，hash 只跑一次）。
	float present = particles_hash1(id);
	if (present > PARTICLE_DENSITY) { return 0.0; }

	// cell 内位置：两次 hash 各取一个分量拼偏移（另两个分量从 present 复用以省一次 hash）。
	float hx = particles_hash1(id ^ uvec3(0x9E3779B9u, 0u, 0u));
	float hy = particles_hash1(id ^ uvec3(0u, 0x9E3779B9u, 0u));
	// Keep the complete soft disc inside its cell; otherwise its clipped edge pops
	// when sampling moves into the adjacent cell.
	vec3 center = (cell + mix(vec3(PARTICLE_RADIUS), vec3(1.0 - PARTICLE_RADIUS),
		vec3(hx, hy, present / PARTICLE_DENSITY))) * PARTICLE_CELL;

	float d = length(pos - center) / PARTICLE_CELL;
	if (d > PARTICLE_RADIUS) { return 0.0; }

	// 径向柔和圆盘：中心亮、边缘渐隐（smoothstep 反向）。
	float disc = 1.0 - smoothstep(PARTICLE_RADIUS * (1.0 - PARTICLE_EDGE), PARTICLE_RADIUS, d);

	// 亮度：越过存在阈值越多越亮（少量亮尘、大量微尘，同 end.glsl 星等手法）+ 慢闪烁。
	// SC-35：压低大亮粒子的占比（0.65→0.35），静止截图不应先注意到颗粒。
	float mag = present * (1.0 / PARTICLE_DENSITY);
	float phase = particles_hash1(id ^ uvec3(0u, 0u, 0x9E3779B9u)) * 6.28318530718;
	float shimmer = 0.90 + 0.10 * sin(time * PARTICLE_SHIMMER_SPEED + phase);

	return disc * (0.30 + 0.35 * mag * mag) * shimmer;
}

vec3 water_particles(vec3 rayDir, float sceneDistance, float skylight, float time) {
	#ifndef UNDERWATER_PARTICLES
		return vec3(0.0);
	#else
	if (isEyeInWater != 1) { return vec3(0.0); }

	vec3 accum = vec3(0.0);
	for (int i = 0; i < PARTICLE_SHELLS; i++) {
		float shellDistance = PARTICLE_SHELL_BASE * exp2(float(i));   // 3 / 6 / 12
		if (shellDistance >= sceneDistance) { break; }                // 该层被几何遮挡，更远同样遮挡

		vec3 pos = cameraPosition + rayDir * shellDistance - PARTICLE_DRIFT * time;

		// 层种子错开（不同层的 mote 不对齐成"串"）。
		float contribution = particles_shell(pos, uvec3(uint(i) * 0x9E37u + 1u), time);
		contribution *= smoothstep(0.0, 0.75, sceneDistance - shellDistance);

		// 距离衰减：复用水下吸收（本模块在 absorption 之后被 program 顺序引入）。
		vec3 transmit = water_transmission(shellDistance);
		accum += contribution * transmit;
	}

	// 天光门控 + 恒定的低底亮。
	float visibility = mix(PARTICLE_DARK_BASE, 1.0, clamp(skylight, 0.0, 1.0));
	visibility *= (1.0 - clamp(blindness, 0.0, 1.0)) * mix(0.15, 1.0, dayUnderwaterFogFade);
	return PARTICLE_COLOR * (accum * visibility * PARTICLE_INTENSITY);
	#endif
}

#endif
