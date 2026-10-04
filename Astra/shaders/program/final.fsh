#include "/lib/settings.glsl"
#if ANTIALIASING == 1
    #include "/lib/uniforms.glsl"
    #include "/lib/pow.glsl"
    #include "/global/post/grading.glsl"
    #include "/global/post/fxaa.glsl"
    uniform sampler2D colortex13;
    in vec2 texcoord;
    void main() {
        #if DEBUG_VERTEX_AO == 1
            gl_FragColor = vec4(textureLod(colortex13,texcoord,0.0).rgb,1.0);
        #else
            bool geometryOnly = false;
            #if !defined DIMENSION_NETHER && !defined DIMENSION_END
            geometryOnly = isEyeInWater == 1 && !water_is_thin_sheet();
            #endif
            vec3 color = astra_fxaa(colortex13,texcoord,geometryOnly);
            color = apply_output_dither(gl_FragCoord.xy,color);
            gl_FragColor = vec4(clamp(color,0.0,1.0),1.0);
        #endif
    }
#else
    #include "/program/display.fsh"
#endif
