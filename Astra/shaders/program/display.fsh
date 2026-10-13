// Shared scene assembly/display transform. Invoked once: composite8 with FXAA,
// otherwise final. Output dither belongs after AA and is never stored in the AA input.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/transforms.glsl"
#include "/lib/pow.glsl"
#include "/lib/twilight.glsl"
#include "/lib/encoding.glsl"
#include "/lib/tonemap.glsl"
#include "/global/post/grading.glsl"
#ifdef DIMENSION_END
#include "/global/post/end_sky_tonemap.glsl"
#endif
#if !defined ASTRA_BLOOM && !defined DIMENSION_NETHER && !defined DIMENSION_END
#define ASTRA_WATER_FOG_FRAME_READ
#endif
#include "/lib/solas_water.glsl"
#include "/lib/water_buffer_formats.glsl"
#if !defined ASTRA_BLOOM && !defined DIMENSION_NETHER && !defined DIMENSION_END
    // With no post-water bloom capture, apply the same water medium here and
    // omit composite3's otherwise unconditional full-screen scene copy.
    #include "/global/water/light_shafts.glsl"
#endif
#if defined ASTRA_UNDERWATER_SHAFTS || (defined GODRAYS && !defined DIMENSION_NETHER && !defined DIMENSION_END)
uniform sampler2D colortex1;
#endif
#ifdef UNDERWATER_PARTICLES
    #include "/global/water/absorption.glsl"
    #include "/global/water/particles.glsl"
#endif
// Retain a bare public-option reference in the consumer for Iris discovery.
#ifdef BLOOM
#ifdef ASTRA_BLOOM
    #include "/global/post/bloom.glsl"
    uniform sampler2D colortex2;
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
        uniform sampler2D colortex7;
        const bool colortex7MipmapEnabled = true;
        #include "/global/water/bloom_resolve.glsl"
    #endif
    const bool colortex2MipmapEnabled = true;
#endif
#endif
#ifdef GODRAYS
#ifndef DIMENSION_NETHER
#ifndef DIMENSION_END

// Pair the four texel weights of three adjacent bilinear samples on each axis.
// For fractional texel position f the weights are (1-f, 1, 1, f) / 3.
// Unlike fixed offsets, these positions preserve the 3x3 box during upsampling.
float godrays_box_filter(sampler2D source, vec2 uv) {
    vec2 size = vec2(textureSize(source, 0));
    vec2 position = uv * size - 0.5;
    vec2 base = floor(position);
    vec2 f = fract(position);
    vec2 leftWeight = (2.0 - f) / 3.0;
    vec2 rightWeight = (1.0 + f) / 3.0;
    vec2 leftUV = (base - 0.5 + 1.0 / (2.0 - f)) / size;
    vec2 rightUV = (base + 1.5 + f / (1.0 + f)) / size;
    vec2 edge = 0.5 / size;
    leftUV = clamp(leftUV, edge, 1.0 - edge);
    rightUV = clamp(rightUV, edge, 1.0 - edge);
    return texture(source, leftUV).r * leftWeight.x * leftWeight.y
         + texture(source, vec2(rightUV.x, leftUV.y)).r * rightWeight.x * leftWeight.y
         + texture(source, vec2(leftUV.x, rightUV.y)).r * leftWeight.x * rightWeight.y
         + texture(source, rightUV).r * rightWeight.x * rightWeight.y;
}
#endif
#endif
#endif
uniform sampler2D colortex0;
#if defined ASTRA_BLOOM && !defined DIMENSION_NETHER && !defined DIMENSION_END
uniform sampler2D colortex9;
#endif
in vec2 texcoord;
#if !defined DIMENSION_NETHER && !defined DIMENSION_END
flat in int displayOrdinaryWater;
#if defined GODRAYS && GODRAYS_STRENGTH > 0 && !defined ASTRA_VOLUME_FOG && (defined GODRAYS_SUN_OCCLUSION || defined ASTRA_GODRAYS_CLOUD_OCCLUSION)
flat in float displayGodraysVisibility;
#endif
#ifdef AUTO_EXPOSURE
flat in float displayExposureGain;
#endif
vec3 display_air_hdr(vec3 hdr) {
    hdr = astra_purkinje(hdr);
    #ifdef AUTO_EXPOSURE
    hdr *= displayExposureGain;
    #endif
    return hdr;
}
#endif
#ifdef ASTRA_DISPLAY_PREPARE
    const int colortex13Format = RGBA16;
    /* RENDERTARGETS: 13 */
    #define ASTRA_DISPLAY_OUT gl_FragData[0]
#else
    #define ASTRA_DISPLAY_OUT gl_FragColor
#endif
void main() {
    #if DEBUG_VERTEX_AO == 1
    ASTRA_DISPLAY_OUT = vec4(texture(colortex0,texcoord).rgb,1.0);
    return;
    #endif
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    // The vertex stage reads the same current interface once per quad vertex.
    bool ordinaryWater = displayOrdinaryWater != 0;
    #else
    bool ordinaryWater = isEyeInWater == 1;
    #endif
    // TAA resolved colortex0 to an unjittered grid. Other scene buffers still
    // describe the rasterized frame, so sample them at its matching jittered UV.
    vec2 sceneUV = texcoord;
    #ifdef ASTRA_TAA
    vec2 edge = 0.5 / vec2(viewWidth, viewHeight);
    sceneUV = clamp(texcoord + astra_jitter_uv(), edge, 1.0 - edge);
    #endif
    #if defined ASTRA_BLOOM && !defined DIMENSION_NETHER && !defined DIMENSION_END
    // Water rejects scene TAA history and uses zero projection jitter. Read its
    // composed RGBA16F image directly in every AA mode: TAA's bypass copy into
    // packed colortex0 would quantize the smooth water gradient a second time.
    vec3 hdr = isEyeInWater == 1
        ? max(texture(colortex9, texcoord).rgb, vec3(0.0))
        : max(texture(colortex0, texcoord).rgb, vec3(0.0));
    #else
    vec3 hdr = max(texture(colortex0, texcoord).rgb, vec3(0.0));
    #endif
    #ifdef DIMENSION_END
    // Bloom and the End sky tone curve identify the same rasterized surface.
    float endSceneDepth = textureLod(depthtex0, sceneUV, 0.0).r;
    #endif
    #if !defined ASTRA_BLOOM && !defined DIMENSION_NETHER && !defined DIMENSION_END
    if (isEyeInWater == 1) {
        float rayLength, sceneDepth, mediumDistance;
        uint sceneFlags;
        vec3 viewPos = water_shafts_view(sceneUV, rayLength, sceneDepth, sceneFlags, mediumDistance);
        vec3 shafts = vec3(0.0);
        #ifdef ASTRA_UNDERWATER_SHAFTS
        if (ordinaryWater)
        shafts = water_shafts_resolve(colortex1, sceneUV, rayLength, sceneFlags)
               * (UNDERWATER_SHAFT_STRENGTH * 0.01);
        #endif
        hdr = solas_water_composite(hdr, viewPos, mediumDistance, shafts, sceneUV,!ordinaryWater)
            * (1.0 - clamp(blindness, 0.0, 1.0));
    }
    #endif
    #ifdef ASTRA_BLOOM
        #if !defined DIMENSION_NETHER && !defined DIMENSION_END
        if (ordinaryWater)
            getBloom(hdr, sceneUV);
        else
        #endif
        {
            float bloomStrength=BLOOM_STRENGTH*0.01;
            #ifdef DIMENSION_END
            // Restrict the optical halo of the sky photosphere; terrain retains
            // its own glow. Source radiance and disc exposure are unchanged.
            if (endSceneDepth >= 0.999999)
                bloomStrength *= 0.60;
            #endif
            #if !defined DIMENSION_NETHER && !defined DIMENSION_END
            bloomStrength*=1.0-0.28*astra_twilight_strength();
            #endif
            hdr += bloom_composite(colortex2,sceneUV,bloomStrength);
        }
    #endif
    #ifdef GODRAYS
    #ifndef DIMENSION_NETHER
    #ifndef DIMENSION_END
    #if GODRAYS_STRENGTH > 0 && !defined ASTRA_VOLUME_FOG
        if ((isEyeInWater == 0 || (isEyeInWater == 1 && !ordinaryWater))
            && godraysExposure > 0.0 && blindness <= 0.0001) {
            float sunVisibility = 1.0;
            #if defined GODRAYS_SUN_OCCLUSION || defined ASTRA_GODRAYS_CLOUD_OCCLUSION
                // Source visibility combines optional opaque-disc occlusion with
                // the screen cloud's current transmission; water keeps its own A.
                sunVisibility = displayGodraysVisibility;
            #endif
            if (sunVisibility > 0.0) {
                float density = godrays_box_filter(colortex1, sceneUV) * sunVisibility;
                hdr += vec3(1.0, 0.91, 0.76) * density
                       * godraysExposure * (GODRAYS_STRENGTH * 0.01);
            }
        }
    #endif
    #endif
    #endif
    #endif
    #ifdef UNDERWATER_PARTICLES
        // Darkness below measures the same nearest-surface eye distance on this
        // texel. Keep that measurement when the particle layer already paid for
        // it; every other path keeps its own existing measurement.
        bool particleDistanceValid = false;
        float particleDistance = 65536.0;
        if (ordinaryWater && blindness < 1.0) {
            // Final sees the nearest translucent surface too. Deferred particles
            // were overwritten by the later alpha=1 water composition.
            float depth = textureLod(depthtex0, sceneUV, 0.0).r;
            vec3 particleView = screen_view(vec3(sceneUV, depth));
            // Keep the sentinel predicate and its lazy length evaluation, so a
            // NaN depth cannot change the particle shells' occlusion decision.
            float sceneDistance = 65536.0;
            if (depth < 0.999999) {
                particleDistance = length(particleView);
                sceneDistance = particleDistance;
                particleDistanceValid = true;
            } else if (depth >= 0.999999) {
                // Sky keeps the same 65536 sentinel; a NaN depth falls through
                // and lets Darkness reproduce its original NaN result.
                particleDistanceValid = true;
            }
            vec3 rayDir = normalize(view_player(particleView));
            float eyeSky = clamp(float(eyeBrightnessSmooth.y) / 240.0, 0.0, 1.0);
            hdr += water_particles(rayDir, sceneDistance, eyeSky, frameTimeCounter);
        }
    #endif
    // Darkness belongs to the assembled scene: fog, clouds, water and the sky
    // must not escape it through different render paths. Apply after bloom and
    // shafts, before tone mapping, with one continuous distance response.
    float dark=clamp(darknessFactor,0.0,1.0);
    if (dark > 0.0) {
        float distanceToEye;
        #ifdef DIMENSION_END
        distanceToEye=endSceneDepth >= 0.999999 ? 65536.0
                            : length(screen_view(vec3(sceneUV,endSceneDepth)));
        #else
        #ifdef UNDERWATER_PARTICLES
        if (particleDistanceValid) {
            distanceToEye=particleDistance;
        } else
        #endif
        {
            float depth=textureLod(depthtex0,sceneUV,0.0).r;
            distanceToEye=depth >= 0.999999 ? 65536.0
                                : length(screen_view(vec3(sceneUV,depth)));
        }
        #endif
        float obscured=smoothstep(3.0,28.0,distanceToEye);
        hdr *= mix(1.0,mix(0.40,0.001,obscured),dark);
    }
    // Underwater uses Solas' own display curve (its domain keeps the reference's
    // gamma-blend order). The two paths are exclusive, so pick one up front - the
    // previous shape computed the full Uchimura+sRGB chain first and discarded it for
    // every underwater pixel (consolidated review D4 / Hunyuan A1). TONEMAP_OPERATOR
    // applies to the air path only; lang documents that.
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    // The vertex-provided auto-exposure gain belongs on this arm only (SC-41).
    // Underwater keeps the Solas curve on the manual slider; other dimensions
    // have no metering pass. display_air_hdr preserves Purkinje -> gain order.
    vec3 displayColor = ordinaryWater
        ? solas_water_display(apply_exposure(hdr))
        : srgb_encode(apply_tonemap(apply_exposure(display_air_hdr(hdr))));
    #else
    #ifdef DIMENSION_END
    vec3 exposed=apply_exposure(hdr);
    vec3 displayColor=srgb_encode(endSceneDepth>=0.999999
        ? astra_end_sky_tonemap(exposed) : apply_tonemap(exposed));
    #else
    vec3 displayColor = srgb_encode(apply_tonemap(apply_exposure(hdr)));
    #endif
    #endif
    displayColor = apply_grading(displayColor);
    displayColor = apply_vignette(displayColor, texcoord);
    #ifdef ASTRA_DISPLAY_PREPARE
    displayColor = clamp(displayColor, 0.0, 1.0);
    ASTRA_DISPLAY_OUT = vec4(displayColor, dot(displayColor,vec3(0.299,0.587,0.114)));
    #else
    displayColor = apply_output_dither(gl_FragCoord.xy, displayColor);
    ASTRA_DISPLAY_OUT = vec4(clamp(displayColor, 0.0, 1.0), 1.0);
    #endif
}
