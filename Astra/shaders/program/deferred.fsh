// E2: retain unattenuated HDR in 4; medium is applied once to display buffer 0.
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/program/scene.glsl"
uniform sampler2D colortex0;
uniform sampler2D colortex3;
#ifdef DIMENSION_END
uniform sampler2D colortex9;
#endif
in vec2 texcoord;
/* RENDERTARGETS: 0,4 */
#if !defined DIMENSION_NETHER && !defined DIMENSION_END
vec3 puddle_reflection(vec3 playerPos, vec3 normal) {
    vec3 ray = reflect(normalize(playerPos), normal);
    vec3 result = astra_reflection_sky(ray, 0.18)
                * smoothstep(-0.04, 0.04, ray.y);
    #ifdef SCREENSPACE_REFLECTIONS
    vec3 start = camera_relative_view(playerPos + normal * 0.025);
    vec3 direction = player_view(ray);
    float reach = direction.z > 0.0 ? min(32.0, (-0.06-start.z)/direction.z) : 32.0;
    if (reach <= 0.05 || start.z >= -0.06) return result;
    vec3 finish = start + direction * reach;
    vec2 a = view_screen(start).xy, b = view_screen(finish).xy;
    float ka = 1.0 / -start.z, kb = 1.0 / -finish.z;
    vec3 qa = start * ka, qb = finish * kb;
    float pixels = length((b-a) * vec2(textureSize(depthtex0, 0)));
    if (pixels < 1.0) return result;
    // Fixed screen footprint, perspective-correct depth: thin cutout plants no
    // longer fall between increasingly large world-space steps.
    float stepT = 1.25 / pixels;
    float previousT = 0.0;
    for (int i=0; i<96; ++i) {
        float t = min(float(i+1)*stepT, 1.0);
        vec2 uv = mix(a,b,t);
        if(any(lessThan(uv,vec2(0.002))) || any(greaterThan(uv,vec2(0.998)))) break;
        float d = texture(depthtex0,uv).r;
        vec3 p = mix(qa,qb,t)/mix(ka,kb,t);
        vec3 prev = mix(qa,qb,previousT)/mix(ka,kb,previousT);
        float sceneZ = screen_view(vec3(uv,d)).z;
        if(d < 0.999999 && min(p.z,prev.z) <= sceneZ && max(p.z,prev.z) >= sceneZ-0.06) {
            float lo=previousT, hi=t;
            for(int j=0;j<6;++j) {
                float mid=(lo+hi)*0.5;
                vec2 mUV=mix(a,b,mid);
                float md=texture(depthtex0,mUV).r;
                float mz=(mix(qa,qb,mid)/mix(ka,kb,mid)).z;
                if(md < 0.999999 && mz <= screen_view(vec3(mUV,md)).z) hi=mid;
                else lo=mid;
            }
            uv=mix(a,b,hi);
            float hd=texture(depthtex0,uv).r;
            vec3 hp=mix(qa,qb,hi)/mix(ka,kb,hi);
            float error=screen_view(vec3(uv,hd)).z-hp.z;
            if(hd < 0.999999 && error >= 0.0 && error < 0.10 && length(hp-start)>0.06) {
                float edge=smoothstep(0.0,0.06,min(min(uv.x,1.0-uv.x),min(uv.y,1.0-uv.y)));
                float rangeFade=1.0-smoothstep(80.0,96.0,float(i));
                result=mix(result,texture(colortex0,uv).rgb,edge*rangeFade);
                break;
            }
        }
        previousT=t;
        if(t>=1.0) break;
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
        #ifdef DIMENSION_END
        vec3 ray = normalize(view_player(screen_view(vec3(texcoord, 1.0))));
        vec4 sky = texture(colortex9, texcoord);
        float cone = max(length(dFdx(ray)), length(dFdy(ray)));
        displayed = sky.rgb + end_starfield(ray, end_light_direction(), cone) * sky.a
                  * (1.0-max(blindness,darknessFactor)) * (1.0-0.18*end_eclipse());
        #else
        displayed = astra_sky(normalize(view_player(screen_view(vec3(texcoord, 1.0)))));
        #endif
        source = displayed;
    }
    #endif
    gl_FragData[0] = vec4(displayed, 1.0);
    gl_FragData[1] = vec4(source, 1.0);
}
