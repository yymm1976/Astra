#include "/lib/settings.glsl"
#ifdef ASTRA_SPATIAL_AA
    #include "/lib/uniforms.glsl"
    #include "/lib/pow.glsl"
    #include "/global/post/grading.glsl"
    #ifdef ASTRA_SMAA
    #include "/lib/encoding.glsl"
    #include "/global/post/smaa_blend.glsl"
    uniform sampler2D colortex7;
    #else
    #include "/global/post/fxaa.glsl"
    #endif
    uniform sampler2D colortex13;
    in vec2 texcoord;
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    flat in int displayOrdinaryWater;
    #endif
    void main() {
        #if defined DIMENSION_NETHER && DEBUG_NETHER_LIGHT > 0
        // Diagnostic cells and receiver colours bypass spatial AA and output dither.
        gl_FragColor=vec4(texture(colortex13,texcoord).rgb,1.0);
        return;
        #endif
        bool geometryOnly = false;
        #if !defined DIMENSION_NETHER && !defined DIMENSION_END
        geometryOnly = displayOrdinaryWater != 0;
        #endif
        #ifdef ASTRA_SMAA
        vec3 color = astra_smaa_blend(colortex13,colortex7,texcoord);
        #else
        vec3 color = astra_fxaa(colortex13,texcoord,geometryOnly);
        #endif
        color = apply_output_dither(gl_FragCoord.xy,color);
        gl_FragColor = vec4(clamp(color,0.0,1.0),1.0);
    }
#else
    #include "/program/display.fsh"
#endif
