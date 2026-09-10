// E2: retain unattenuated HDR in 4; medium is applied once to display buffer 0.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/program/scene.glsl"
uniform sampler2D colortex0;
uniform sampler2D colortex3;
in vec2 texcoord;
/* RENDERTARGETS: 0,4 */
#if !defined DIMENSION_NETHER && !defined DIMENSION_END
vec3 puddle_reflection(vec3 playerPos, vec3 normal) {
    vec3 ray = reflect(normalize(playerPos), normal);
    vec3 result = astra_sky(ray);
    #ifdef SCREENSPACE_REFLECTIONS
    vec3 origin = playerPos + normal * 0.08;
    float travel = 0.35;
    for (int i=0; i<24; ++i) {
        travel += 0.24 + float(i)*0.10;
        vec3 p = origin + ray*travel;
        vec3 viewPos = camera_relative_view(p);
        if(viewPos.z >= -0.05) break;
        vec3 uv = view_screen(viewPos);
        if(any(lessThan(uv.xy,vec2(0.002))) || any(greaterThan(uv.xy,vec2(0.998)))) break;
        float d = texture(depthtex0,uv.xy).r;
        if(d >= 0.999999) continue;
        vec3 hit = screen_view(vec3(uv.xy,d));
        float gap = hit.z-viewPos.z;
        if(gap > 0.0 && gap < 0.22 + travel*0.025) {
            float edge = smoothstep(0.0,0.08,min(min(uv.x,1.0-uv.x),min(uv.y,1.0-uv.y)));
            result = mix(result, texture(colortex0,uv.xy).rgb,edge);
            break;
        }
    }
    #endif
    return result;
}
vec3 rainy_air(vec3 endPoint) {
    if(astraRainFactor < 0.01 || isEyeInWater != 0) return vec3(0.0);
    float access = smoothstep(0.35,0.85,float(eyeBrightnessSmooth.y)/240.0);
    if(access <= 0.0) return vec3(0.0);
    vec3 L = normalize(view_player(lightVector));
    float distanceToEye = min(length(endPoint),100.0);
    vec3 ray = normalize(endPoint);
    float phase = 0.06 + 0.94*pow(max(dot(ray,L),0.0),8.0);
    float sum = 0.0;
    for(int i=0;i<10;++i) {
        float t = (float(i)+0.5)*distanceToEye/10.0;
        vec3 p = ray*t;
        float lit = astra_cloud_transmission(p+cameraPosition,L);
        #ifdef SHADOWS
        vec3 sp = distort(player_shadow(p))*0.5+0.5;
        sp.z -= 0.00002;
        lit *= mix(1.0,shadow_opaque_visibility(sp),shadow_coverage(p,sp));
        #endif
        sum += lit * exp(-t*0.008);
    }
    return vec3(1.0,0.91,0.78) * sum * (distanceToEye/10.0)
         * 0.003 * phase * astraRainFactor * access * skyVisibilityDay;
}
#endif
void main() {
    vec3 source = texture(colortex0, texcoord).rgb;
    float depth = texture(depthtex0, texcoord).r;
    vec3 displayed = source;
    if (depth < 0.999999) {
        uint lightData = uint(round(texelFetch(colortex3, ivec2(gl_FragCoord.xy), 0).r * 255.0));
        if ((lightData & 128u) != 0u) depth = ((depth * 2.0 - 1.0) / MC_HAND_DEPTH) * 0.5 + 0.5;
        vec3 playerPos = view_camera_relative(screen_view(vec3(texcoord, depth)));
        float skylight = float(lightData & 127u) / 127.0;
        #if !defined DIMENSION_NETHER && !defined DIMENSION_END
        vec4 surface = texelFetch(colortex3,ivec2(gl_FragCoord.xy),0);
        if(surface.a > 0.001 && isEyeInWater == 0 && (lightData & 128u) == 0u) {
            vec3 n = decode_unit_vector(surface.gb*2.0-1.0);
            float fresnel = 0.025+0.975*pow(1.0-max(dot(n,-normalize(playerPos)),0.0),5.0);
            source = mix(source,puddle_reflection(playerPos,n),surface.a*fresnel);
        }
        #endif
        displayed = astra_apply_medium(source, playerPos, skylight);
        #if !defined DIMENSION_NETHER && !defined DIMENSION_END
        displayed += rainy_air(playerPos);
        #endif
    }
    #if defined DIMENSION_END || defined DIMENSION_NETHER
    if (depth >= 0.999999) {
        displayed = astra_sky(normalize(view_player(screen_view(vec3(texcoord, 1.0)))));
        source = displayed;
    }
    #endif
    gl_FragData[0] = vec4(displayed, 1.0);
    gl_FragData[1] = vec4(source, 1.0);
}
