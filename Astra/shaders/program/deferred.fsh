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
        float d = textureLod(depthtex0,uv,0.0).r;
        vec3 p = mix(qa,qb,t)/mix(ka,kb,t);
        vec3 prev = mix(qa,qb,previousT)/mix(ka,kb,previousT);
        float sceneZ = screen_view(vec3(uv,d)).z;
        if(d < 0.999999 && min(p.z,prev.z) <= sceneZ && max(p.z,prev.z) >= sceneZ-0.06) {
            float lo=previousT, hi=t;
            for(int j=0;j<6;++j) {
                float mid=(lo+hi)*0.5;
                vec2 mUV=mix(a,b,mid);
                float md=textureLod(depthtex0,mUV,0.0).r;
                float mz=(mix(qa,qb,mid)/mix(ka,kb,mid)).z;
                if(md < 0.999999 && mz <= screen_view(vec3(mUV,md)).z) hi=mid;
                else lo=mid;
            }
            uv=mix(a,b,hi);
            float hd=textureLod(depthtex0,uv,0.0).r;
            vec3 hp=mix(qa,qb,hi)/mix(ka,kb,hi);
            float error=screen_view(vec3(uv,hd)).z-hp.z;
            if(hd < 0.999999 && error >= 0.0 && error < 0.10 && length(hp-start)>0.06) {
                float edge=smoothstep(0.0,0.06,min(min(uv.x,1.0-uv.x),min(uv.y,1.0-uv.y)));
                float rangeFade=1.0-smoothstep(80.0,96.0,float(i));
                // The reflected hit is another pixel of the same scene, so it is
                // subject to the same highlight ceiling. Without this, a reflection of
                // the sun or of a bright sky region re-entered the frame above the
                // shoulder and was handed to the tonemapper unclipped twice.
                result=mix(result,astra_scene_highlights(textureLod(colortex0,uv,0.0).rgb),
                           edge*rangeFade);
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
    if(astraRainFactor < 0.01 || isEyeInWater != 0 || skyVisibilityDay <= 0.0) return vec3(0.0);
    float access = smoothstep(0.35,0.85,float(eyeBrightnessSmooth.y)/240.0);
    if(access <= 0.0) return vec3(0.0);
    vec3 L = normalize(view_player(lightVector));
    float distanceToEye = min(length(endPoint),100.0);
    vec3 ray = normalize(endPoint);
    float phase = 0.06 + 0.94*pow8(max(dot(ray,L),0.0));
    float sum = 0.0;
    for(int i=0;i<10;++i) {
        float t = (float(i)+0.5)*distanceToEye/10.0;
        vec3 p = ray*t;
        float lit = astra_cloud_transmission(p+cameraPosition,L);
        #ifdef SHADOWS
        vec3 sp = distort(player_shadow(p))*0.5+0.5;
        sp.z -= 0.00002;
        float coverage = shadow_coverage(p,sp);
        if (lit > 0.0 && coverage > 0.0)
            lit *= mix(1.0,shadow_opaque_visibility(sp),coverage);
        #endif
        sum += lit * exp(-t*0.008);
    }
    return vec3(1.0,0.91,0.78) * sum * (distanceToEye/10.0)
         * 0.003 * phase * astraRainFactor * access * skyVisibilityDay;
}
#endif
void main() {
    #if DEBUG_VERTEX_AO == 1
    vec4 ao = texture(colortex0,texcoord);
    gl_FragData[0]=ao;
    gl_FragData[1]=ao;
    return;
    #endif
    #ifdef DIMENSION_END
    vec3 ray=normalize(view_player(screen_view(vec3(texcoord,1.0))));
    float cone=max(length(dFdx(ray)),length(dFdy(ray)));
    vec3 endStarRay=end_lensed_background(ray);
    vec3 endStarDx=dFdx(endStarRay), endStarDy=dFdy(endStarRay);
    #endif
    vec3 source = texture(colortex0, texcoord).rgb;
    float depth = texture(depthtex0, texcoord).r;
    vec3 displayed = source;
    if (depth < 0.999999) {
        uint lightData = uint(round(texelFetch(colortex3, ivec2(gl_FragCoord.xy), 0).r * 255.0));
        if ((lightData & 128u) != 0u) depth = ((depth * 2.0 - 1.0) / MC_HAND_DEPTH) * 0.5 + 0.5;
        vec3 playerPos = view_camera_relative(screen_view(vec3(texcoord, depth)));
        float skylight = float(lightData & 127u) / 127.0;
        #if !defined DIMENSION_NETHER && !defined DIMENSION_END
        // colortex3: r = packed skylight (+hand flag), gb = wet/ripple normal (whose
        // amplitude is the standing-water width), a = the sparse standing-water mask
        // itself (program/lit.fsh).
        //
        // SC-39 (2026-09-17 correction, twice over). This gate was rewritten in the round
        // and got the signal wrong: it read the BROAD damp mask and derived a
        // standing-water weight from it with smoothstep(0.30, 0.85, wet). The damp mask
        // saturates to ~1 across all rain-wet terrain, so that weight was ~1 nearly
        // everywhere and the expensive puddle_reflection() (up to 96 depth taps plus a
        // six-step refine) still ran over the whole damp world - the exact "泛白的反射块"
        // symptom the round claimed to fix. The value computed for this purpose, the
        // sparse astra_puddle() coverage, was written nowhere.
        //
        // The next attempt then carried the mask in colortex0.a, which does not exist:
        // colortex0Format is R11F_G11F_B10F, an RGB format, so that write is dropped and
        // this read would have returned 1.0 for every pixel - the same fault again with a
        // different cause. The mask now travels in colortex3.a, which is RGBA8 by default
        // and whose alpha no consumer reads.
        //
        // The ripple tilt is kept as a second, monotone gate, so a fragment
        // whose mask is a rounding error above the threshold still cannot produce a
        // reflection on a normal that shows no water. It is NOT an independent signal:
        // the ripple amplitude itself scales with the same puddle mask
        // (global/atmosphere/weather.glsl), so this sharpens the threshold rather than
        // adding information (consolidated review F-16).
        vec4 surface = texelFetch(colortex3, ivec2(gl_FragCoord.xy), 0);
        float standingWater = clamp(surface.a, 0.0, 1.0);
        if (standingWater > 0.15 && isEyeInWater == 0 && (lightData & 128u) == 0u) {
            vec3 n = decode_unit_vector(surface.gb*2.0-1.0);
            // Reflection only from a surface that can actually reflect sky: a wall
            // sheds the water, and a downward-facing quad reflects the ground.
            float upFacing = smoothstep(0.55, 0.92, n.y);
            // Ripple presence. The normal's vertical component is 1 where
            // astra_rain_ripple wrote nothing (dry ground), so a 1/400 tilt in it is
            // already a fully formed ripple.
            float rippled = clamp((1.0 - n.y) * 400.0, 0.0, 1.0);
            float fresnel = 0.025+0.975*pow5(1.0-max(dot(n,-normalize(playerPos)),0.0));
            // Every factor gates the CALL, not just the mix weight: puddle_reflection
            // costs up to 96 depth samples plus a refine, and GLSL evaluates mix
            // arguments unconditionally. Water-surface, translucent and sky-clear
            // pixels all reach this branch (colortex3 keeps its clear values there),
            // so without the weight gate they each pay the march for a result whose
            // upFacing is zero (consolidated review A3 / Qoder F-15 / F-42).
            float weight = standingWater*upFacing*rippled*fresnel;
            if (weight > 0.001)
                source = mix(source,puddle_reflection(playerPos,n), weight);
        }
        #endif
        displayed = astra_apply_medium(source, playerPos, skylight);

        #if !defined DIMENSION_NETHER && !defined DIMENSION_END && CLOUD_MODE == CLOUD_PLANAR
        // F2 (2026-09-21): the sheet used to be composited ONLY on the far plane (the
        // `depth >= 0.999999` branch below), so every terrain pixel - i.e. everything a
        // player sees while standing above the layer and looking down - carried no cloud,
        // while the sky past the render distance did. The cloud-free disc around the player
        // is exactly the terrain footprint. Compose it here as well, but only when the sheet
        // really lies between the eye and this fragment: the eye must be outside the layer,
        // the travel direction must point at it, and the plane crossing must be nearer than
        // the terrain distance. The gate is evaluated BEFORE the call because GLSL evaluates
        // arguments unconditionally.
        //
        // Cost for normal ground play is one subtraction and one comparison per terrain
        // pixel: below the layer a downward ray gives planeDistance < 0, so the block exits
        // before any noise, march or texture fetch.
        float cloudLower = ASTRA_CLOUD_ALTITUDE - ASTRA_CLOUD_STRETCH;
        float cloudUpper = ASTRA_CLOUD_ALTITUDE + ASTRA_CLOUD_STRETCH;
        float cloudTerrainDistance = length(playerPos);
        vec3 cloudRay = normalize(view_player(screen_view(vec3(texcoord,1.0))));
        float cloudEntryPlane = cameraPosition.y > cloudUpper ? cloudUpper : cloudLower;
        float cloudPlaneDistance = (cloudEntryPlane - cameraPosition.y) / cloudRay.y;
        if ((cameraPosition.y > cloudUpper || cameraPosition.y < cloudLower)
            && cloudPlaneDistance > 0.0 && cloudPlaneDistance < cloudTerrainDistance) {
            vec4 sheet = astra_planar_cloud(cloudRay);
            if (sheet.a > 0.0) displayed = mix(displayed, sheet.rgb, sheet.a);
        }
        #endif
        #if !defined DIMENSION_NETHER && !defined DIMENSION_END
        displayed += rainy_air(playerPos);
        #endif
    }
    #if defined DIMENSION_END || defined DIMENSION_NETHER
    if (depth >= 0.999999) {
        #ifdef DIMENSION_END
        vec4 sky = texture(colortex9, texcoord);
        displayed = sky.rgb;
        float starVisibility = sky.a * (1.0-max(blindness,darknessFactor));
        displayed += end_crisp_photon_ring(ray,cone)
                   * (1.0-max(blindness,darknessFactor)) * (1.0-0.18*end_eclipse());
        if (starVisibility > 0.0)
            displayed += end_starfield_filtered(endStarRay, cone, endStarDx, endStarDy) * starVisibility
                       * (1.0-0.18*end_eclipse());
        #else
        displayed = astra_sky(normalize(view_player(screen_view(vec3(texcoord, 1.0)))));
        #endif
        source = displayed;
    }
    #endif
    #if !defined DIMENSION_END && !defined DIMENSION_NETHER && CLOUD_MODE != CLOUD_VANILLA
    if (depth >= 0.999999) {
        vec3 skyRay = normalize(view_player(screen_view(vec3(texcoord,1.0))));
        // Sun/moon were drawn additively over black in skytextured; their
        // phase texture and cloud transmission are already present in source.
        displayed = astra_sky(skyRay) + source;
        source = displayed; // Refraction/SSR background must also contain sky.
    }
    #endif
    gl_FragData[0] = vec4(displayed, 1.0);
    gl_FragData[1] = vec4(source, 1.0);
}
