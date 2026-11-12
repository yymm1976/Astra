#ifndef RF_COMETS_GLSL
#define RF_COMETS_GLSL

#if defined OVERWORLD_COMETS && defined OVERWORLD

#ifndef RF_MATH_GLSL
   #include "/common/math.glsl"
#endif

#ifndef TRANSFORMATIONS_GLSL
   #include "/common/transformations.glsl"
#endif

#ifndef RAIN_STRENGTH_UNIFORM
#define RAIN_STRENGTH_UNIFORM
uniform float rainStrength;
#endif

#ifndef SUN_POSITION_UNIFORM
#define SUN_POSITION_UNIFORM
uniform vec3 sunPosition;
#endif

#ifndef WORLD_TIME_UNIFORM
#define WORLD_TIME_UNIFORM
uniform int worldTime;
#endif

#ifndef WORLD_DAY_UNIFORM
#define WORLD_DAY_UNIFORM
uniform int worldDay;
#endif

#ifndef COMET_BRIGHTNESS
   #define COMET_BRIGHTNESS 1.0
#endif

const float RF_COMET_NIGHT0 = 13000.0;
const float RF_COMET_NIGHT1 = 23000.0;
const float RF_COMET_NIGHT_LEN = RF_COMET_NIGHT1 - RF_COMET_NIGHT0;

// MIT ref: David Hoskins — Hash without Sine (hash22)
// Source: https://www.shadertoy.com/view/4djSRW
// License text: THIRD_PARTY_NOTICES.md
vec2 cometHash22(vec2 p) {
   vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
   q += dot(q, q.yzx + 33.33);
   return fract((q.xx + q.yz) * q.zy);
}

float cometHash21(vec2 p) {
   return cometHash22(p).x;
}

void cometDayConfig(out float seed, out float timePhase, out float count) {
   int slot = int(mod(float(worldDay), 10.0));
   if (slot < 0) {
      slot += 10;
   }

   seed = float(COMET_DAY1_SEED);
   timePhase = float(COMET_DAY1_TIME);
   count = float(COMET_DAY1_COUNT);

   if (slot == 1) {
      seed = float(COMET_DAY2_SEED);
      timePhase = float(COMET_DAY2_TIME);
      count = float(COMET_DAY2_COUNT);
   } else if (slot == 2) {
      seed = float(COMET_DAY3_SEED);
      timePhase = float(COMET_DAY3_TIME);
      count = float(COMET_DAY3_COUNT);
   } else if (slot == 3) {
      seed = float(COMET_DAY4_SEED);
      timePhase = float(COMET_DAY4_TIME);
      count = float(COMET_DAY4_COUNT);
   } else if (slot == 4) {
      seed = float(COMET_DAY5_SEED);
      timePhase = float(COMET_DAY5_TIME);
      count = float(COMET_DAY5_COUNT);
   } else if (slot == 5) {
      seed = float(COMET_DAY6_SEED);
      timePhase = float(COMET_DAY6_TIME);
      count = float(COMET_DAY6_COUNT);
   } else if (slot == 6) {
      seed = float(COMET_DAY7_SEED);
      timePhase = float(COMET_DAY7_TIME);
      count = float(COMET_DAY7_COUNT);
   } else if (slot == 7) {
      seed = float(COMET_DAY8_SEED);
      timePhase = float(COMET_DAY8_TIME);
      count = float(COMET_DAY8_COUNT);
   } else if (slot == 8) {
      seed = float(COMET_DAY9_SEED);
      timePhase = float(COMET_DAY9_TIME);
      count = float(COMET_DAY9_COUNT);
   } else if (slot == 9) {
      seed = float(COMET_DAY10_SEED);
      timePhase = float(COMET_DAY10_TIME);
      count = float(COMET_DAY10_COUNT);
   }
}

float cometNightVis() {
   #ifdef GET_SKY_COLOR
      return smoothstep(0.55, 0.02, getSunVisibility());
   #else
      float sunUp = dot(normalize(sunPosition), gbufferModelView[1].xyz);
      float sunVis = clamp((sunUp + 0.1) * 4.0, 0.0, 1.0);
      return smoothstep(0.55, 0.02, sunVis);
   #endif
}

void cometPath(float seed, float idx, out vec3 p0, out vec3 p1) {
   vec2 h0 = cometHash22(vec2(seed + 0.13, idx + 1.7));
   vec2 h1 = cometHash22(vec2(seed + 4.91, idx + 8.2));
   vec2 h2 = cometHash22(vec2(seed + 11.4, idx + 2.6));
   vec2 h3 = cometHash22(vec2(seed + 19.7, idx + 14.5));

   float yaw = h0.x * TAU;
   vec3 dir = normalize(vec3(cos(yaw), mix(-0.08, 0.14, h0.y), sin(yaw)));

   float y0 = mix(400.0, 700.0, h1.x);
   float y1 = mix(400.0, 700.0, h1.y);
   float halfLen = mix(16000.0, 28000.0, h2.x);
   float miss = mix(220.0, 980.0, h3.x);
   float missAng = h3.y * TAU;
   vec2 nearXZ = cameraPosition.xz + vec2(cos(missAng), sin(missAng)) * miss;

   vec3 mid = vec3(nearXZ.x, mix(y0, y1, 0.5), nearXZ.y);
   p0 = mid - dir * halfLen;
   p1 = mid + dir * halfLen;
   p0.y = clamp(y0, 400.0, 700.0);
   p1.y = clamp(y1, 400.0, 700.0);
}

float cometProgress(float seed, float idx, float count, float timePhase, out float alive) {
   float u = cometHash21(vec2(seed + 2.3, idx + 0.41));
   float startFrac = fract((idx + u * 0.82) / max(count, 1.0) + timePhase);
   float durTicks = mix(55.0, 95.0, cometHash21(vec2(seed + 6.8, idx + 5.5)));
   float startTick = RF_COMET_NIGHT0 + startFrac * (RF_COMET_NIGHT_LEN - durTicks);
   float t = (float(worldTime) - startTick) / durTicks;
   alive = step(0.0, t) * step(t, 1.0);
   return clamp(t, 0.0, 1.0);
}

float cometRaySegment(vec3 orig, vec3 dir, vec3 a, vec3 b, out float tRay, out float tSeg) {
   vec3 ab = b - a;
   vec3 ap = orig - a;
   float ab2 = max(dot(ab, ab), 1.0e-6);
   float ad = dot(ab, dir);
   float apd = dot(ap, dir);
   float apab = dot(ap, ab);
   float denom = ab2 - ad * ad;

   if (abs(denom) < 1.0e-4) {
      tSeg = clamp(apab / ab2, 0.0, 1.0);
   } else {
      tRay = (ad * apab - ab2 * apd) / denom;
      tSeg = clamp((apab + tRay * ad) / ab2, 0.0, 1.0);
   }

   vec3 hitSeg = a + ab * tSeg;
   tRay = dot(hitSeg - orig, dir);
   return length((orig + dir * max(tRay, 0.0)) - hitSeg);
}

vec3 cometStreak(vec3 worldDir, float maxDist, vec3 p0, vec3 p1, float prog) {
   vec3 head = mix(p0, p1, prog);
   float tailProg = max(prog - 0.62, 0.0);
   vec3 tail = mix(p0, p1, tailProg);

   float tRay;
   float tSeg;
   float dist = cometRaySegment(cameraPosition, worldDir, tail, head, tRay, tSeg);
   if (tRay < 8.0 || tRay > maxDist) {
      return vec3(0.0);
   }

   float ang = dist / max(tRay, 12.0);
   float needle = 0.00055 / max(ang + 0.00055, 1.0e-6);
   needle = needle * needle;
   vec3 drag = vec3(END_STARS_DRAG.rgb);
   vec3 line = exp(-ang * drag * 8.5) * needle;
   float tip = exp(-ang * ang * 220000.0) * pow(tSeg, 10.0);
   float mag = max(max(line.r, line.b), tip);
   if (mag < 1.0e-4) {
      return vec3(0.0);
   }

   float along = pow(tSeg, 0.55);
   float fade = smoothstep(0.0, 0.04, prog) * smoothstep(1.0, 0.94, prog);
   vec3 headCol = vec3(0.95, 0.80, 1.0);
   vec3 tailCol = vec3(0.70, 0.28, 1.0);
   vec3 tint = mix(tailCol, headCol, pow(tSeg, 1.8));
   return (tint * line * 1.15 * along + headCol * tip * 2.2) * fade;
}

vec3 getOverworldComets(vec3 viewDir, float maxDist) {
   vec3 dir = normalize(viewDir);
   vec3 worldDir = normalize(mat3(gbufferModelViewInverse) * dir);
   float up = worldDir.y;
   if (up < -0.04) {
      return vec3(0.0);
   }

   float night = cometNightVis();
   float vis = night * (1.0 - rainStrength) * smoothstep(-0.04, 0.12, up);
   if (vis < 0.02) {
      return vec3(0.0);
   }

   float wt = float(worldTime);
   if (wt < RF_COMET_NIGHT0 || wt > RF_COMET_NIGHT1) {
      return vec3(0.0);
   }

   float seed;
   float timePhase;
   float count;
   cometDayConfig(seed, timePhase, count);
   count = min(floor(count + 0.5), 30.0);
   if (count < 0.5) {
      return vec3(0.0);
   }

   float cap = maxDist;
   vec3 col = vec3(0.0);

   for (int i = 0; i < 30; i++) {
      float idx = float(i);
      if (idx >= count) {
         continue;
      }

      float alive;
      float prog = cometProgress(seed, idx, count, timePhase, alive);
      if (alive < 0.5) {
         continue;
      }

      vec3 p0;
      vec3 p1;
      cometPath(seed, idx, p0, p1);
      col += cometStreak(worldDir, cap, p0, p1, prog);
   }

   return col * vis * COMET_BRIGHTNESS * 1.85;
}

#endif
#endif
