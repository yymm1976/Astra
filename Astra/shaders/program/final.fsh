// Astra E1. Only one output transfer; C6 grading consumes sRGB (SC-16).
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/encoding.glsl"
#include "/lib/tonemap.glsl"
#include "/global/post/grading.glsl"
#include "/global/water/light_shafts.glsl"
#include "/lib/solas_water.glsl"
#ifdef UNDERWATER_PARTICLES
    #include "/lib/transforms.glsl"
    #include "/global/water/absorption.glsl"
    #include "/global/water/particles.glsl"
#endif
#ifdef BLOOM
    #include "/global/post/bloom.glsl"
    uniform sampler2D colortex2;
    const bool colortex2MipmapEnabled = true;
#endif
#if defined GODRAYS || defined ASTRA_UNDERWATER_SHAFTS
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
        hdr += bloom_composite(colortex2, texcoord, BLOOM_STRENGTH * 0.01);
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
            hdr += vec3(1.0, 0.91, 0.76) * (density / 9.0)
                   * godraysExposure * (GODRAYS_STRENGTH * 0.01);
        }
    #endif
    #endif
    #endif
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    if (isEyeInWater == 1) {
        float rayLength;
        vec3 viewPos = water_shafts_view(texcoord, rayLength);
        vec3 shafts = vec3(0.0);
        #ifdef ASTRA_UNDERWATER_SHAFTS
            shafts = water_shafts_resolve(colortex1, texcoord, rayLength)
                   * (UNDERWATER_SHAFT_STRENGTH * 0.01);
        #endif
        hdr = solas_water_composite(hdr, viewPos, shafts) * (1.0 - clamp(blindness, 0.0, 1.0));
    }
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
    vec3 displayColor = srgb_encode(apply_tonemap(apply_exposure(hdr)));
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
        if (isEyeInWater == 1) displayColor = solas_water_display(apply_exposure(hdr));
    #endif
    displayColor = apply_grading(displayColor);
    displayColor = apply_vignette(displayColor, texcoord);
    displayColor = apply_output_dither(gl_FragCoord.xy, displayColor);
    gl_FragColor = vec4(clamp(displayColor, 0.0, 1.0), 1.0);
}
