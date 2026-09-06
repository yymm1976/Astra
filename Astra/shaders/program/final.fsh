// Astra E1. Only one output transfer; C6 grading consumes sRGB (SC-16).
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/encoding.glsl"
#include "/lib/tonemap.glsl"
#include "/global/post/grading.glsl"
#ifdef BLOOM
    #include "/global/post/bloom.glsl"
    uniform sampler2D colortex2;
    const bool colortex2MipmapEnabled = true;
#endif
#if defined GODRAYS && !defined DIMENSION_NETHER && !defined DIMENSION_END
    uniform sampler2D colortex1;
#endif
uniform sampler2D colortex0;
in vec2 texcoord;
void main() {
    vec3 hdr = max(texture(colortex0, texcoord).rgb, vec3(0.0));
    #ifdef BLOOM
        hdr += bloom_composite(colortex2, texcoord, BLOOM_STRENGTH * 0.01);
    #endif
    #if defined GODRAYS && !defined DIMENSION_NETHER && !defined DIMENSION_END
        if (godraysExposure > 0.0) {
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
    vec3 displayColor = srgb_encode(apply_tonemap(apply_exposure(hdr)));
    displayColor = apply_grading(displayColor);
    displayColor = apply_vignette(displayColor, texcoord);
    displayColor = apply_output_dither(gl_FragCoord.xy, displayColor);
    gl_FragColor = vec4(clamp(displayColor, 0.0, 1.0), 1.0);
}
