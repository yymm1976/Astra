#ifndef ASTRA_LIB_UNIFORMS_GLSL
#define ASTRA_LIB_UNIFORMS_GLSL

#ifndef EXTERNALLY_DEFINED_UNIFORMS

// Astra v1 - lib/uniforms.glsl
// Uniforms: declares them (this is the declaration home)
// Owner: E1 extends with any additional built-in the modules it wires in need; the
//        Z3 block below is the GLSL counterpart of the CPU-precomputed custom
//        uniforms in shaders.properties.

// ------------------------------------------------------------
// Z3 custom uniforms (CPU-precomputed; see "CUSTOM UNIFORMS" section of shaders.properties)
// Do NOT recompute these in-shader (design.md section 5 CPU offload).
// ------------------------------------------------------------
uniform vec3  lightVector;             // normalized shadow light (sun by day, moon by night)
uniform vec3  worldSunVector;          // world-space SUN direction (independent of shadow light)
uniform float sunProgress;             // 0 at sun horizon, 1 at zenith
uniform float moonProgress;            // same, for the moon
uniform float skyVisibilityDay;        // skylight collapse around dusk/dawn
uniform float astraTwilightFactor;      // shared, rain-aware twilight envelope (also underwater)
uniform vec3  astraSkyColorM;           // rain-adjusted sqrt(skyColor), CPU palette terms
uniform vec3  astraSkyNoonBase;         // pow(astraSkyColorM, 2.9)
uniform vec3  astraSkyNightUp;          // weather-adjusted night palette
uniform vec3  astraSkyNightMiddle;
uniform vec3  astraCloudNoonAmbient;    // pow(max(skyColor,0), 0.75) * 0.85
uniform float borderFogDistance;       // == far
uniform float atmosphereFogCoefficient;// pow(d,3) fog coefficient (distance-normalized)
uniform float dayUnderwaterFogFade;    // underwater fog day/night ramp
uniform float windStrength;            // base wind strength (rain-aware); WAVING_FOLIAGE_STRENGTH scales in-shader
uniform vec4  windTheta;               // XYZ = direction thetas, W = magnitude theta
uniform float godraysExposure;         // base exposure * view-angle fade * offscreen fade
uniform float astraMoonIllumination;   // moon disc lit fraction: 1 full, 0 new
uniform float astraMoonLimbSign;       // terminator side: +1 below moonPhase 4, -1 above (which
                                       // limb that is in world space is unverified; checklist 7b)
uniform float astraMoonLightScale;     // direct moonlight multiplier the phase applies

// ------------------------------------------------------------
// Iris/OptiFine built-ins referenced by lib/ and global/ (declared once here so a
// module never depends on which pass happens to include it first)
// ------------------------------------------------------------
uniform sampler2D solasWaterNoise;
// Rain ripple flipbooks (shaders.properties customTexture.astraRipple1/2).
uniform sampler2D astraRipple1;
uniform sampler2D astraRipple2;
uniform float temperature;
uniform float rainfall;
uniform int   frameCounter;            // lib/dither.glsl
uniform float frameTimeCounter;        // lib/noise.glsl wind/water scroll
uniform vec3  cameraPosition;          // world-space camera
uniform int   isEyeInWater;            // 0/1/2/3 air|water|fire|powder snow
uniform mat4  gbufferModelView;
uniform mat4  gbufferModelViewInverse;
uniform mat4  gbufferProjection;
uniform mat4  gbufferProjectionInverse;
uniform mat4  shadowModelView;         // global/lighting/shadowmap.glsl
uniform mat4  shadowProjection;
uniform mat4  shadowModelViewInverse;  // program/shadow.vsh: shadow view -> camera-relative world point
uniform float blindness;               // global/atmosphere/fog.glsl (0..1, vanilla darkness effect)

// ------------------------------------------------------------
// Pass-local depth/screen targets. Declared here rather than in the program that
// uses them so a module never depends on which pass happens to declare it first;
// Iris binds only what the linked program actually references.
// ------------------------------------------------------------
uniform sampler2D depthtex0;           // nearest depth including translucent geometry

// E1 built-ins and CPU values; Voxy must provide the complete set when overriding.
uniform sampler2D gtexture;
uniform sampler2D depthtex1;           // opaque scene depth paired with deferred colortex4
uniform float viewWidth;
uniform float viewHeight;
uniform float alphaTestRef;
uniform float rainStrength;
uniform float astraRainFactor;
uniform float screenBrightness;
uniform float darknessFactor;
uniform float astraNetherWastes;
uniform float astraNetherCrimson;
uniform float astraNetherWarped;
uniform float astraNetherBasalt;
uniform float astraNetherSoul;

uniform float nightVision;
uniform ivec2 eyeBrightnessSmooth;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform vec4 entityColor;
uniform vec4 lightningBoltPosition;
// Do not declare moonPhase here: Iris registers it with uniform1i, and a float
// declaration makes Iris disable the binding (see the moon block in shaders.properties).
uniform int entityId;
uniform int blockEntityId;
uniform int currentRenderedItemId;
uniform int renderStage;
uniform float astraHeldLightBase;
uniform float astraBlocklightSuppression;
uniform float astraHeldLightSuppression;

// Mod availability does not select a coordinate system. Only C5's actual LOD
// entry may request these; native geometry and post passes keep gbuffer matrices.
#ifdef ASTRA_VOXY_PASS
uniform mat4 vxModelView;
uniform mat4 vxModelViewInv;
#endif

// Iris keeps a boolean option only when some compiled shader source references it;
// lib/settings.glsl alone is not enough (Iris's option scanner skips that file), and
// the log then shows "Unable to resolve shader pack option menu element VOXY_SUPPORT".
// This is a bootstrap reference for the option itself: voxy.json still holds an empty
// patch and voxy_opaque.glsl / voxy_translucent.glsl are stubs, so the owning task (C5)
// must replace this with real Voxy support. It deliberately guards nothing else.
#ifdef VOXY_SUPPORT
const bool astraVoxyBootstrap = true;
#endif

#endif // EXTERNALLY_DEFINED_UNIFORMS

#endif
