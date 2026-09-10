#ifndef ASTRA_GLOBAL_WATER_SURFACE_GLSL
#define ASTRA_GLOBAL_WATER_SURFACE_GLSL

// Astra v1 — global/water/surface.glsl
// From Steadfast 0.8.0 (GPLv3 + Section 7 additional terms) by coderbot
//   source: _analysis/Steadfast-0.8.0/shaders/environment/water/
//           surface_noise.glsl + surface_noise_waves.glsl + parallax.glsl
//           + lib/valueNoise.glsl / lib/valueNoiseDerivatives.glsl
// This file is a derivative of Steadfast and is licensed under the GNU General
// Public License v3 or later (GPL-3.0-or-later); see Astra/LICENSE and
// _analysis/Steadfast-0.8.0/LICENSE.md. Redistribution is permitted only under that
// license including Steadfast's Section 7 additional terms.
// Publish gate: design.md 9.3 + escalations.md SC-14 (⏸ pending user decision).
//
// Reference wave parameters, Nyquist filter and four-step parallax.
// The dedicated 64x64 texture reproduces this Iris runtime's default noise at
// Steadfast's requested resolution without altering Astra's other noise users.
// Names and option adapters are local; fixed loops keep screen derivatives valid.
uniform sampler2D steadfastWaterNoise;
const int steadfastNoiseResolution = 64;

struct WaterSurface {
	vec3 normal;
	float roughness;
};

// --- 内联 value noise（Steadfast lib/valueNoise.glsl + valueNoiseDerivatives.glsl） ---
// 与 Solas 出身的 caustics.glsl 同编译单元，故全部符号加 surface_ 前缀。

// Perlin fade 6t^5 - 15t^4 + 10t^3（C1 连续，其导数在格点处不跳变）。
vec2 surface_fade(vec2 t) {
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

// d(Fade)/dt = 30t^4 - 60t^3 + 30t^2。
vec2 surface_grad_fade(vec2 t) {
	return 30.0 * t * t * (t * (t - 2.0) + 1.0);
}

// Coherent value noise，`at` 以格为单位（+1.0 = 移动一格 = 一个纹素），返回 [0, 1]。
float surface_noise(vec2 at) {
	vec2 corner = floor(at);
	at = surface_fade(at - corner) + corner;
	// 格空间 → 纹素空间，并偏移半个纹素使格心落在 4 纹素中心（Steadfast 对齐，单次 fma）。
	at = at * (1.0 / float(steadfastNoiseResolution))
		+ (0.5 / float(steadfastNoiseResolution));
	// Parallax has divergent iteration counts; implicit derivatives are undefined there.
	return textureLod(steadfastWaterNoise, at, 0.0).x;
}

// 值噪声的解析梯度：一次 textureGather 取格点四角的 H 值，用 fade 导数加权差分。
// 比中心差分（3 次采样）省一半 ALU，这正是 Steadfast 选解析导数的原因。
vec2 surface_noise_gradient(vec2 at) {
	vec2 corner = floor(at);
	vec2 center = corner * (1.0 / float(steadfastNoiseResolution))
		+ (0.5 / float(steadfastNoiseResolution));
	vec2 offset = at - corner;

	// textureGather(steadfastWaterNoise, P) = vec4(H(x, y+1), H(x+1, y+1), H(x+1, y), H(x, y))
	vec4 corners = textureGather(steadfastWaterNoise, center);
	vec4 mixes = mix(corners.xwzw, corners.yzyx, surface_fade(offset).xxyy);
	return (mixes.zx - mixes.wy) * surface_grad_fade(offset);
}

// --- Steadfast 波场（surface_noise_waves.glsl） ---
// 参数经 Steadfast 校成 SEUS Renewed 的观感：ripple 是滚动拉伸的值噪声，
// crest 是"平底 + 网格跃变处起脊"的间歇波（本文件里的 crest 函数）。

#define SurfaceDegrees radians(1.0)

struct SurfaceWave {
	vec2  tileSize;    // 单格在 X/Z 上的尺寸（米 = 格）
	float shearAngle;  // 纵向剪切角（弧度），±90° 之外无定义
	float speed;       // 沿 heading 的速度（格/秒）
	float heading;     // 行进方向（弧度，Z 当单位圆的 Y）
	float weight;      // 相对幅度，除以总权重后才是实际幅度
};

const SurfaceWave WATER_RIPPLES[4] = SurfaceWave[](
	// 大尺度低频涟漪：1.5 x 2.0 m，剪切 30°，1.5 m/s，heading 252°
	SurfaceWave(vec2(1.5, 2.0),  30.0 * SurfaceDegrees, 1.5, 180.0 * SurfaceDegrees + 72.0 * SurfaceDegrees, 16.0),
	// 1.0 x 1.5 m，剪切 -36°，3 m/s，heading 234°
	SurfaceWave(vec2(1.0, 1.5), -36.0 * SurfaceDegrees, 3.0, 180.0 * SurfaceDegrees + 54.0 * SurfaceDegrees, 16.0),
	// 高频细涟漪：0.30 x 0.40 m，剪切 45°，1.5 m/s，heading 288°
	SurfaceWave(vec2(0.30, 0.40), 45.0 * SurfaceDegrees, 1.5, 270.0 * SurfaceDegrees + 18.0 * SurfaceDegrees, 4.0),
	// 0.15 x 0.20 m，剪切 -45°，0.5 m/s，heading 216°
	SurfaceWave(vec2(0.15, 0.20), -45.0 * SurfaceDegrees, 0.5, 180.0 * SurfaceDegrees + 36.0 * SurfaceDegrees, 1.0)
);

const SurfaceWave WATER_CRESTS[2] = SurfaceWave[](
	// 主波：3.0 x 4.0 m，剪切 30°，3 m/s，heading 243°（两条大涟漪的正中，三者同向成主波形）
	SurfaceWave(vec2(3.0, 4.0),  30.0 * SurfaceDegrees,  3.0, 180.0 * SurfaceDegrees + 63.0 * SurfaceDegrees, 32.0),
	// 低频消平铺感：6.0 x 8.0 m，剪切 -30°，12 m/s（快但幅度低），heading 252°
	SurfaceWave(vec2(6.0, 8.0), -30.0 * SurfaceDegrees, 12.0, 180.0 * SurfaceDegrees + 72.0 * SurfaceDegrees, 16.0)
);

// 逆格尺寸 + 剪切交叉项（Steadfast 的派生表，形式照搬）：
//   (1/tileX, 1/tileY, cot(shear)/tileX)
const vec3 rippleStretch[4] = vec3[](
	vec3(1.0 / WATER_RIPPLES[0].tileSize.x, 1.0 / WATER_RIPPLES[0].tileSize.y,
		(1.0 / tan(WATER_RIPPLES[0].shearAngle)) / WATER_RIPPLES[0].tileSize.x),
	vec3(1.0 / WATER_RIPPLES[1].tileSize.x, 1.0 / WATER_RIPPLES[1].tileSize.y,
		(1.0 / tan(WATER_RIPPLES[1].shearAngle)) / WATER_RIPPLES[1].tileSize.x),
	vec3(1.0 / WATER_RIPPLES[2].tileSize.x, 1.0 / WATER_RIPPLES[2].tileSize.y,
		(1.0 / tan(WATER_RIPPLES[2].shearAngle)) / WATER_RIPPLES[2].tileSize.x),
	vec3(1.0 / WATER_RIPPLES[3].tileSize.x, 1.0 / WATER_RIPPLES[3].tileSize.y,
		(1.0 / tan(WATER_RIPPLES[3].shearAngle)) / WATER_RIPPLES[3].tileSize.x));

const vec3 crestStretch[2] = vec3[](
	vec3(1.0 / WATER_CRESTS[0].tileSize.x, 1.0 / WATER_CRESTS[0].tileSize.y,
		(1.0 / tan(WATER_CRESTS[0].shearAngle)) / WATER_CRESTS[0].tileSize.x),
	vec3(1.0 / WATER_CRESTS[1].tileSize.x, 1.0 / WATER_CRESTS[1].tileSize.y,
		(1.0 / tan(WATER_CRESTS[1].shearAngle)) / WATER_CRESTS[1].tileSize.x));

// 速度 + 朝向 → 逐帧滚动向量（乘 -1：让 (0,0) 处的波看起来向 +X 移动了一个单位）。
const vec2 rippleScroll[4] = vec2[](
	-mat2(rippleStretch[0].x, rippleStretch[0].x / tan(WATER_RIPPLES[0].shearAngle),
	      0.0, rippleStretch[0].y)
	 * WATER_RIPPLES[0].speed
	 * vec2(cos(WATER_RIPPLES[0].heading), sin(WATER_RIPPLES[0].heading)),
	-mat2(rippleStretch[1].x, rippleStretch[1].x / tan(WATER_RIPPLES[1].shearAngle),
	      0.0, rippleStretch[1].y)
	 * WATER_RIPPLES[1].speed
	 * vec2(cos(WATER_RIPPLES[1].heading), sin(WATER_RIPPLES[1].heading)),
	-mat2(rippleStretch[2].x, rippleStretch[2].x / tan(WATER_RIPPLES[2].shearAngle),
	      0.0, rippleStretch[2].y)
	 * WATER_RIPPLES[2].speed
	 * vec2(cos(WATER_RIPPLES[2].heading), sin(WATER_RIPPLES[2].heading)),
	-mat2(rippleStretch[3].x, rippleStretch[3].x / tan(WATER_RIPPLES[3].shearAngle),
	      0.0, rippleStretch[3].y)
	 * WATER_RIPPLES[3].speed
	 * vec2(cos(WATER_RIPPLES[3].heading), sin(WATER_RIPPLES[3].heading)));

const vec2 crestScroll[2] = vec2[](
	-mat2(crestStretch[0].x, crestStretch[0].x / tan(WATER_CRESTS[0].shearAngle),
	      0.0, crestStretch[0].y)
	 * WATER_CRESTS[0].speed
	 * vec2(cos(WATER_CRESTS[0].heading), sin(WATER_CRESTS[0].heading)),
	-mat2(crestStretch[1].x, crestStretch[1].x / tan(WATER_CRESTS[1].shearAngle),
	      0.0, crestStretch[1].y)
	 * WATER_CRESTS[1].speed
	 * vec2(cos(WATER_CRESTS[1].heading), sin(WATER_CRESTS[1].heading)));

// 编译期归一化的逐层幅度（weight / totalWeight）。
const float rippleTotalWeight = WATER_RIPPLES[0].weight + WATER_RIPPLES[1].weight
	+ WATER_RIPPLES[2].weight + WATER_RIPPLES[3].weight
	+ WATER_CRESTS[0].weight + WATER_CRESTS[1].weight;

const float rippleMagnitude[4] = float[](
	WATER_RIPPLES[0].weight / rippleTotalWeight,
	WATER_RIPPLES[1].weight / rippleTotalWeight,
	WATER_RIPPLES[2].weight / rippleTotalWeight,
	WATER_RIPPLES[3].weight / rippleTotalWeight);

const float crestMagnitude[2] = float[](
	WATER_CRESTS[0].weight / rippleTotalWeight,
	WATER_CRESTS[1].weight / rippleTotalWeight);

// Steadfast 的原始梯度档。上一轮抬到 0.20 后，近岸与掠射角出现黑白细条；
// 回到 0.15 保留波脊形态，同时让 Nyquist 过滤前的法线摆幅与参考一致。
const float SURFACE_GRADIENT_STRENGTH = 0.15;

// 把平滑的层间过渡重铸成可见的"脊"：绝大部分区域平坦，网格跃变处起脊（0.5-0.5cos）。
float surface_crest(float h) {
	const float PI = 3.14159265359;
	return (-0.5 * cos(h * (PI * 2.0))) + 0.5;
}

// d(Crest)/dh，链式法则求梯度时用（mul -> sin -> mul）。
float surface_crest_derivative(float h) {
	const float PI = 3.14159265359;
	return PI * sin(h * (PI * 2.0));
}

// Nyquist 比率受限（Steadfast antialiasFactor）：对每一层噪声求"噪声纹素 : 屏幕像素"的
// 雅可比比值，比值升高就把该层淡向均值 0.5，而不是等它在屏幕上退化成白噪声再靠 TAA 救。
// Astra 固定 Steadfast 的 BALANCED 档 smoothstep(0.45, 0.55)。
float surface_antialias(vec2 ddxWorldPos, vec2 ddyWorldPos, vec3 stretch) {
	// 采样坐标的偏导 = 拉伸坐标的偏导（滚动项是常数），故直接对 dFdx/dFdy 做同样的变换。
	vec2 ddxAt = vec2(ddxWorldPos.x * stretch.x, dot(ddxWorldPos, stretch.zy));
	vec2 ddyAt = vec2(ddyWorldPos.x * stretch.x, dot(ddyWorldPos, stretch.zy));
	vec2 maxes = max(abs(ddxAt), abs(ddyAt));
	// A noise gradient followed by a nonlinear crest and Fresnel needs more than
	// two pixels per cell. Filter before it becomes a high-contrast reflection.
	return smoothstep(0.45, 0.55, max(maxes.x, maxes.y));
}

// 水面高度（0..1），视差步进用。approximate = true 时只算贡献最大的前两条涟漪
// （Steadfast NUM_BIG_RIPPLES = 2），4 步视差里省一半采样。
float surface_height(vec2 worldPos, vec2 ddxWorldPos, vec2 ddyWorldPos, float time, bool approximate, float distanceToCamera) {
	float height = 0.0;
	int ripples = approximate ? 2 : 4;
	// The reference approximation omits the two fine ripple layers.


	for (int i = 0; i < ripples; i++) {
		vec3 stretch = rippleStretch[i];
		vec2 at = time * rippleScroll[i]
			+ vec2(worldPos.x * stretch.x, dot(worldPos, stretch.zy));
		float aa = surface_antialias(ddxWorldPos, ddyWorldPos, stretch);
		float fade = 1.0;
		float filteredHeight = mix(surface_noise(at), 0.5, aa);
		// Removing a layer means fading its variation, not its DC component. A
		// distance-dependent mean shift otherwise moves the parallax intersection.
		height += rippleMagnitude[i] * mix(0.5, filteredHeight, fade);
	}

	for (int i = 0; i < 2; i++) {
		vec3 stretch = crestStretch[i];
		vec2 at = time * crestScroll[i]
			+ vec2(worldPos.x * stretch.x, dot(worldPos, stretch.zy));
		float aa = surface_antialias(ddxWorldPos, ddyWorldPos, stretch);
		float fade = 1.0;
		// Reference order: antialias the height before the crest remap.
		float filteredCrest = surface_crest(mix(surface_noise(at), 0.5, aa));
		height += crestMagnitude[i] * mix(0.5, filteredCrest, fade);
	}

	return height;
}

// 负梯度（-∇H），解析导数版（Steadfast WaterNGradientAnalytic）。
// `unresolved` 顺带累计被 Nyquist 滤掉的坡度能量，供 Astra 的 roughness 使用。
vec2 surface_gradient(vec2 worldPos, vec2 ddxWorldPos, vec2 ddyWorldPos, float time, float distanceToCamera, out float unresolved) {
	vec2 gradient = vec2(0.0);
	unresolved = 0.0;

	for (int i = 0; i < 4; i++) {
		vec3 stretch = rippleStretch[i];
		vec2 at = time * rippleScroll[i]
			+ vec2(worldPos.x * stretch.x, dot(worldPos, stretch.zy));
		float aa = surface_antialias(ddxWorldPos, ddyWorldPos, stretch);
		float fade = 1.0;

		vec2 waveGradient = (SURFACE_GRADIENT_STRENGTH * rippleMagnitude[i])
			* surface_noise_gradient(at);

		// 拉伸把 X 混进了噪声 Y，故 X 方向是方向导数 = dot(方向, 梯度)（Steadfast 注释）。
		vec2 scaled = vec2(dot(stretch.xz, waveGradient), waveGradient.y * stretch.y);
		gradient -= (1.0 - aa) * scaled * fade;
		// Do not feed the discarded high-frequency gradient back into roughness:
		// its animated magnitude would reintroduce shimmer through reflections.
		// 0.43 is a mean slope estimate for smooth value noise, independent of phase.
		unresolved += aa * (0.43 * SURFACE_GRADIENT_STRENGTH * rippleMagnitude[i]) * length(stretch) * fade;
	}

	for (int i = 0; i < 2; i++) {
		vec3 stretch = crestStretch[i];
		vec2 at = time * crestScroll[i]
			+ vec2(worldPos.x * stretch.x, dot(worldPos, stretch.zy));
		float aa = surface_antialias(ddxWorldPos, ddyWorldPos, stretch);
		float fade = 1.0;

		// crest 的链式法则：先取抗锯齿后的高度喂给 dCrest/dh，再对返回的梯度抗锯齿。
		float heightAt = mix(surface_noise(at), 0.5, aa);
		vec2 waveGradient = (SURFACE_GRADIENT_STRENGTH * crestMagnitude[i])
			* surface_noise_gradient(at) * surface_crest_derivative(heightAt);

		vec2 scaled = vec2(dot(stretch.xz, waveGradient), waveGradient.y * stretch.y);
		gradient -= (1.0 - aa) * scaled * fade;
		// The crest remap adds a mean derivative factor of about pi/sqrt(2).
		unresolved += aa * (0.43 * 2.22144147 * SURFACE_GRADIENT_STRENGTH * crestMagnitude[i]) * length(stretch) * fade;
	}

	return gradient;
}

// 4 步自适应视差（Steadfast WaterSurfaceParallaxMapping）：每步的步长按"当前高度与
// 表面高度之差"缩放 —— 越接近水面走得越慢，因此 4 步就够（常规视差要 8-32 步）。
//   tangentView: 切线空间视线向量，Z 为负 = 射入表面（见文件头的坐标约定说明）。
vec2 surface_parallax(vec2 worldPos, vec2 ddxWorldPos, vec2 ddyWorldPos, float time, vec3 tangentView, float distanceToCamera) {
	const float ITERATIONS = 4;
	float currentHeight = 1.0;
	// 把视线按 Z 归一到 -1 后即可丢掉 Z；夹一个下界避免掠射时横向步子爆炸。
	vec2 posStep = tangentView.xy / max(abs(tangentView.z), 0.0001);

	for (int i = 0; i < 4; i++) {
		float sampleHeight = surface_height(worldPos, ddxWorldPos, ddyWorldPos, time, true, distanceToCamera);
		float stepLength = (1.0 / ITERATIONS) * max(currentHeight - sampleHeight, 0.0);
		worldPos = (posStep * stepLength) + worldPos;
		currentHeight -= stepLength;
        // Fixed iteration count keeps subsequent screen derivatives defined.
	}

	return worldPos;
}

WaterSurface water_surface(vec3 worldPos, vec3 baseNormal, float time) {
	WaterSurface surface;
	vec3 faceNormal = normalize(baseNormal);
	surface.normal = faceNormal;
	surface.roughness = 0.045;


#ifdef WATER_WAVES
	vec2 ddx = dFdx(worldPos.xz);
	vec2 ddy = dFdy(worldPos.xz);

	float heightScale = WATER_WAVE_HEIGHT * 0.01;
	float waveTime = time * (WATER_WAVE_SPEED * 0.01);

	// 切线空间视线：X/Z = 世界水平，Z（高度轴）= -|Δy|，使上/下表面都满足
	// Steadfast 的"Z 为负 = 射入表面"约定。worldPos 是绝对世界坐标（lit.fsh
	// 传入 playerPos + cameraPosition，SC-35 起 playerPos 为真相机相对位置）。
	vec3 toSurface = worldPos - cameraPosition;
	vec3 tangentView = vec3(toSurface.x, toSurface.z, -abs(toSurface.y))
		/ max(length(toSurface), 1e-5);
	float distanceToCamera = length(toSurface);

	vec2 offsetPosition = surface_parallax(worldPos.xz, ddx, ddy, waveTime, tangentView, distanceToCamera);
    float parallaxStrength = clamp((48.0 - distanceToCamera) / 24.0, 0.0, float(abs(faceNormal.y) > 0.999));
    vec2 position = mix(worldPos.xz, offsetPosition, parallaxStrength);

	float unresolved;
	// The reference reuses the geometric footprint for the final normal.
	vec2 minusGradient = surface_gradient(position, ddx, ddy, waveTime, distanceToCamera, unresolved);

	// minusGradient = -∇H（噪声空间 y 即世界 Z），故世界法线 = (-∂H/∂x, 1, -∂H/∂z)；
	// 符号已烘进 surface_gradient 的减法里（Steadfast 同形）。
	vec3 upwardNormal = normalize(vec3(
		minusGradient.x * heightScale,
		1.0,
		minusGradient.y * heightScale));
	surface.normal = upwardNormal * sign(faceNormal.y);
    // Steadfast does not add a distance-dependent roughness lobe.
    surface.roughness = 0.0;
#endif

    // Select sideways geometry after all derivatives, including parallax and
    // roughness. A material/face branch before dFdx makes shoreline quads undefined.
    if (abs(faceNormal.y) <= 0.999) {
        surface.normal = faceNormal;
        surface.roughness = 0.045;
    }
	return surface;
}

#endif
