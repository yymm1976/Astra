// Astra E1. Only one output transfer; C6 grading consumes sRGB (SC-16).
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/transforms.glsl"
#include "/lib/pow.glsl"
#include "/lib/twilight.glsl"
#include "/lib/encoding.glsl"
#include "/lib/tonemap.glsl"
#include "/global/post/grading.glsl"
#include "/global/water/light_shafts.glsl"
#include "/lib/solas_water.glsl"
#include "/lib/water_buffer_formats.glsl"
#ifdef UNDERWATER_PARTICLES
    #include "/global/water/absorption.glsl"
    #include "/global/water/particles.glsl"
#endif
#ifdef BLOOM
    #include "/global/post/bloom.glsl"
    uniform sampler2D colortex2;
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
        uniform sampler2D colortex7;
        #include "/global/water/bloom_resolve.glsl"
    #endif
    const bool colortex2MipmapEnabled = true;
#endif
#ifdef GODRAYS
#ifndef DIMENSION_NETHER
#ifndef DIMENSION_END
    uniform sampler2D colortex1;
#endif
#endif
#endif
uniform sampler2D colortex0;
in vec2 texcoord;
void main() {
    vec3 hdr = max(texture(colortex0, texcoord).rgb, vec3(0.0));
    #ifdef BLOOM
        #if !defined DIMENSION_NETHER && !defined DIMENSION_END
        if (isEyeInWater == 1) getBloom(hdr, texcoord, texture(depthtex0, texcoord).r);
        else
        #endif
        {
            float bloomStrength=BLOOM_STRENGTH*0.01;
            #if !defined DIMENSION_NETHER && !defined DIMENSION_END
            bloomStrength*=1.0-0.28*astra_twilight_strength();
            #endif
            hdr += bloom_composite(colortex2,texcoord,bloomStrength);
        }
    #endif
    #ifdef GODRAYS
    #ifndef DIMENSION_NETHER
    #ifndef DIMENSION_END
        if (isEyeInWater == 0 && godraysExposure > 0.0) {
            vec2 stepUV = 1.0 / vec2(textureSize(colortex1, 0));
            float density = 0.0;
            for (int y = -1; y <= 1; ++y)
                for (int x = -1; x <= 1; ++x)
                    density += texture(colortex1, clamp(texcoord + vec2(x,y)*stepUV,
                               stepUV*0.5, 1.0-stepUV*0.5)).r;
            #ifdef GODRAYS_SUN_OCCLUSION
                // Program/scattering.fsh probes the solar disc once per frame and leaves
                // the result here. A format without an alpha channel reads back 1.0, so
                // the worst this carrier can do is nothing.
                density *= texelFetch(colortex1, ivec2(0), 0).a;
            #endif
            hdr += vec3(1.0, 0.91, 0.76) * (density / 9.0)
                   * godraysExposure * (GODRAYS_STRENGTH * 0.01);
        }
    #endif
    #endif
    #endif
    #ifdef UNDERWATER_PARTICLES
        if (isEyeInWater == 1 && blindness < 1.0) {
            // Final sees the nearest translucent surface too. Deferred particles
            // were overwritten by the later alpha=1 water composition.
            float depth = texture(depthtex0, texcoord).r;
            vec3 particleView = screen_view(vec3(texcoord, depth));
            float sceneDistance = depth < 0.999999 ? length(particleView) : 65536.0;
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
        float depth=texture(depthtex0,texcoord).r;
        float distanceToEye=depth >= 0.999999 ? 65536.0
                            : length(screen_view(vec3(texcoord,depth)));
        float obscured=smoothstep(3.0,28.0,distanceToEye);
        hdr *= mix(1.0,mix(0.40,0.001,obscured),dark);
    }
    // Underwater uses Solas' own display curve (its domain keeps the reference's
    // gamma-blend order). The two paths are exclusive, so pick one up front - the
    // previous shape computed the full Uchimura+sRGB chain first and discarded it for
    // every underwater pixel (consolidated review D4 / Hunyuan A1). TONEMAP_OPERATOR
    // applies to the air path only; lang documents that.
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    vec3 displayColor = isEyeInWater == 1
        ? solas_water_display(apply_exposure(hdr))
        : srgb_encode(apply_tonemap(apply_exposure(hdr)));
    #else
    vec3 displayColor = srgb_encode(apply_tonemap(apply_exposure(hdr)));
    #endif
    displayColor = apply_grading(displayColor);
    displayColor = apply_vignette(displayColor, texcoord);
    displayColor = apply_output_dither(gl_FragCoord.xy, displayColor);
    gl_FragColor = vec4(clamp(displayColor, 0.0, 1.0), 1.0);
}
