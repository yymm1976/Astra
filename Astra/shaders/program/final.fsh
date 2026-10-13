#include "/lib/settings.glsl"
#if ANTIALIASING == 1 && DEBUG_VERTEX_AO == 0
    #include "/lib/uniforms.glsl"
    #include "/lib/pow.glsl"
    #include "/global/post/grading.glsl"
    #include "/global/post/fxaa.glsl"
    uniform sampler2D colortex13;
    in vec2 texcoord;
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    flat in int displayOrdinaryWater;
    #endif
    void main() {
        bool geometryOnly = false;
        #if !defined DIMENSION_NETHER && !defined DIMENSION_END
        geometryOnly = displayOrdinaryWater != 0;
        #endif
        vec3 color = astra_fxaa(colortex13,texcoord,geometryOnly);
        color = apply_output_dither(gl_FragCoord.xy,color);
        gl_FragColor = vec4(clamp(color,0.0,1.0),1.0);
    }
#else
    #include "/program/display.fsh"
#endif
