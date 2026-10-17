// E2: retain unattenuated HDR in 4; medium is applied once to display buffer 0.
// Overworld only: the matching vertex stage (program/deferred.vsh) declares and
// writes the same flat water kind under this condition. Nether/End keep the
// dimension early-out inside medium_state.glsl and must not declare the input.
#if !defined DIMENSION_NETHER && !defined DIMENSION_END
#define ASTRA_WATER_STATE_FRAME_READ
#endif
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/taa_reactive.glsl"
#include "/program/scene.glsl"
#ifdef SCREENSPACE_AO
#ifdef ASTRA_SSAO
#include "/lib/ao_resolve.glsl"
#endif
#endif
#if !defined DIMENSION_NETHER && !defined DIMENSION_END && CLOUD_MODE == CLOUD_PLANAR
    #include "/global/atmosphere/clouds_screen.glsl"
#endif
uniform sampler2D colortex0;
uniform sampler2D colortex3;
#ifdef ASTRA_VOLUME_FOG
// R2/H3: half-resolution S/T produced by program/volume_main.fsh this frame.
uniform sampler2D colortex23;
#endif
#ifdef DIMENSION_END
uniform sampler2D colortex9;
#endif
in vec2 texcoord;
#ifdef ASTRA_TAA
uniform sampler2D colortex16;
/* RENDERTARGETS: 0,4,16 */
#else
/* RENDERTARGETS: 0,4 */
#endif
#if !defined DIMENSION_NETHER && !defined DIMENSION_END
    #if defined SCREENSPACE_REFLECTIONS && (WATER_EFFECT_QUALITY < 2 || defined ASTRA_OVERWORLD_OPTIMIZED)
    #include "/global/water/raytrace.glsl"
    #endif
vec3 puddle_reflection_sky(vec3 ray, float noV) {
    return astra_reflection_sky(ray, 0.18) * smoothstep(-0.04, 0.04, ray.y)
         * astra_environment_reflection_gain(0.18, noV, 0.025);
}
vec3 puddle_reflection(vec3 playerPos, vec3 normal, vec3 incident, float noV) {
    vec3 ray = reflect(incident, normal);
    #if defined SCREENSPACE_REFLECTIONS && (WATER_EFFECT_QUALITY < 2 || defined ASTRA_OVERWORLD_OPTIMIZED)
    // Wet-ground budget: only patches near the camera keep a fine object
    // reflection. Past 64 blocks the tracer is skipped while the sky term, the
    // wet darkening, the rough material and the rain ripples all stay; 48..64 is
    // the same continuous collapse the water surface uses, so the handoff has no
    // hard edge. The measure is the wet surface's own camera distance,
    // length(playerPos), not the ray's travel length. Distance alone decides
    // this: a reflection-radiance contribution threshold was not needed, so no
    // weight threshold is raised for it.
    float geometryFade = 1.0;
    #ifdef ASTRA_OVERWORLD_OPTIMIZED
    geometryFade = 1.0 - smoothstep(48.0, 64.0, length(playerPos));
    #endif
    if (geometryFade > 0.0) {
        // Sparse wet patches do not need their own 96-step fine-pixel marcher.
        // Use the bounded water tracer with the original 32-block puddle reach;
        // the sky environment supplies distant or thin geometry it cannot resolve.
        vec3 start = camera_relative_view(playerPos + normal * 0.025);
        vec3 direction = player_view(ray);
        vec4 hit = water_raytrace(depthtex0,start,direction,normalize(player_view(normal)),32.0);
        if (hit.a > 0.0) {
            vec3 reflected = astra_scene_highlights(textureLod(colortex0,hit.xy,0.0).rgb);
            if (hit.a >= 1.0 && geometryFade >= 1.0) return reflected;
            vec3 sky = puddle_reflection_sky(ray, noV);
            vec3 geometric = hit.a >= 1.0 ? reflected : mix(sky,reflected,hit.a);
            return mix(sky, geometric, geometryFade);
        }
    }
    return puddle_reflection_sky(ray, noV);
    #elif defined SCREENSPACE_REFLECTIONS
    vec3 start = camera_relative_view(playerPos + normal * 0.025);
    vec3 direction = player_view(ray);
    float reach = direction.z > 0.0 ? min(32.0, (-0.06-start.z)/direction.z) : 32.0;
    if (reach <= 0.05 || start.z >= -0.06) return puddle_reflection_sky(ray, noV);
    vec3 finish = start + direction * reach;
    vec2 a = view_screen(start).xy, b = view_screen(finish).xy;
    float ka = 1.0 / -start.z, kb = 1.0 / -finish.z;
    vec3 qa = start * ka, qb = finish * kb;
    float pixels = length((b-a) * vec2(textureSize(depthtex0, 0)));
    if (pixels < 1.0) return puddle_reflection_sky(ray, noV);
    // Fixed screen footprint, perspective-correct depth: thin cutout plants no
    // longer fall between increasingly large world-space steps.
    float stepT = 1.25 / pixels;
    float previousT = 0.0;
    for (int i=0; i<96; ++i) {
        float t = min(float(i+1)*stepT, 1.0);
        vec2 uv = mix(a,b,t);
        if(any(lessThan(uv,vec2(0.002))) || any(greaterThan(uv,vec2(0.998)))) break;
        float d = textureLod(depthtex0,uv,0.0).r;
        // Sky has no crossing; retain march progress without reconstructing it.
        if (d >= 0.999999) {
            previousT=t;
            if(t>=1.0) break;
            continue;
        }
        vec3 p = mix(qa,qb,t)/mix(ka,kb,t);
        vec3 prev = mix(qa,qb,previousT)/mix(ka,kb,previousT);
        float sceneZ = screen_view(vec3(uv,d)).z;
        if(min(p.z,prev.z) <= sceneZ && max(p.z,prev.z) >= sceneZ-0.06) {
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
            if (hd >= 0.999999) {
                previousT=t;
                if(t>=1.0) break;
                continue;
            }
            vec3 hp=mix(qa,qb,hi)/mix(ka,kb,hi);
            float error=screen_view(vec3(uv,hd)).z-hp.z;
            if(error >= 0.0 && error < 0.10 && length(hp-start)>0.06) {
                float edge=smoothstep(0.0,0.06,min(min(uv.x,1.0-uv.x),min(uv.y,1.0-uv.y)));
                float rangeFade=1.0-smoothstep(80.0,96.0,float(i));
                // The reflected hit is another pixel of the same scene, so it is
                // subject to the same highlight ceiling. Without this, a reflection of
                // the sun or of a bright sky region re-entered the frame above the
                // shoulder and was handed to the tonemapper unclipped twice.
                vec3 reflected = astra_scene_highlights(textureLod(colortex0,uv,0.0).rgb);
                float confidence = edge * rangeFade;
                // A full-confidence hit owns the result; query the sky only
                // for misses and the existing screen/range transition.
                if (confidence >= 1.0) return reflected;
                return mix(puddle_reflection_sky(ray, noV), reflected, confidence);
            }
        }
        previousT=t;
        if(t>=1.0) break;
    }
    #endif
    return puddle_reflection_sky(ray, noV);
}
vec3 rainy_air(vec3 endPoint) {
    if(astraRainFactor < 0.01 || !(isEyeInWater == 0 || water_is_thin_sheet()) || skyVisibilityDay <= 0.0
            || blindness > 0.0001) return vec3(0.0);
    float access = smoothstep(0.35,0.85,float(eyeBrightnessSmooth.y)/240.0);
    if(access <= 0.0) return vec3(0.0);
    vec3 L = astra_world_light_direction();
    float endpointLength = length(endPoint);
    float distanceToEye = min(endpointLength,100.0);
    if (distanceToEye <= 0.0) return vec3(0.0);
    vec3 ray = endPoint / endpointLength;
    float phase = 0.06 + 0.94*pow8(max(dot(ray,L),0.0));
    float sum = 0.0;
    float stepLength = distanceToEye / 10.0;
    float attenuation = exp(-stepLength * 0.004);
    // Twice the optical depth uses the square of the same transmittance.
    float attenuationStep = attenuation * attenuation;
    #ifdef SHADOWS
    // Project this ray once; each sample retains its homogeneous divide and
    // nonlinear distortion, including any shadow-projection translation.
    vec4 shadowOrigin = shadowProjection * (shadowModelView * vec4(0.0,0.0,0.0,1.0));
    vec4 shadowStep = shadowProjection * (shadowModelView * vec4(ray * stepLength,0.0));
    #endif
    // Overworld budget only: the last two of the ten uniform midpoints reuse the
    // previous midpoint's visibility instead of projecting the shadow map again.
    // The handoff is a continuous distance weight, not a 32-block switch: it is
    // 0 within 32 blocks (all ten original queries), 1 from 40 blocks on (i = 7
    // and i = 9 take the previous paired value, eight real queries), and between
    // 32 and 40 all ten queries still run with i = 7 and i = 9 blending their own
    // result towards that previous value, so 40 is exactly the eight-query
    // answer and the two sides meet without a step. Every integration position,
    // its weight, stepLength, the fog/attenuation coefficients, the
    // cloud-transmission plus opaque-occlusion pairing and the clear-sky early-out
    // above stay exactly as they were. The reused taps are the two lightest of
    // the descending attenuation-weighted sum (<=20% of an unblocked ray), and
    // reusing the whole paired sample keeps its cloud term and its occlusion
    // consistent, so uniformly lit or uniformly occluded air keeps its brightness.
    #ifdef ASTRA_OVERWORLD_OPTIMIZED
    float reuseWeight = smoothstep(32.0, 40.0, endpointLength);
    float previousLit = 0.0;
    #endif
    for(int i=0;i<10;++i) {
        float sampleIndex = float(i) + 0.5;
        float t = sampleIndex * stepLength;
        vec3 p = ray*t;
        float lit;
        #ifdef ASTRA_OVERWORLD_OPTIMIZED
        // Past 40 blocks only these two taps skip their query: i = 7 takes i = 6,
        // i = 9 takes the midpoint at i = 8, which is still a real query, so the
        // reuse stays bounded to those two taps.
        if (reuseWeight >= 1.0 && (i == 7 || i == 9)) {
            lit = previousLit;
        } else
        #endif
        {
            lit = astra_cloud_transmission(p+cameraPosition,L);
            #ifdef SHADOWS
            if (lit > 0.0) {
                vec4 clip = shadowOrigin + shadowStep * sampleIndex;
                vec3 sp = distort(clip.xyz / clip.w) * 0.5 + 0.5;
                sp.z -= 0.00002;
                float coverage = shadow_coverage(p,sp);
                if (coverage > 0.0)
                    lit *= mix(1.0,shadow_opaque_visibility(sp),coverage);
            }
            #endif
            #ifdef ASTRA_OVERWORLD_OPTIMIZED
            // 32..40 only: the query still runs and slides from its own paired
            // result towards the previous sample's, keeping the weight continuous.
            if (reuseWeight > 0.0 && (i == 7 || i == 9))
                lit = mix(lit, previousLit, reuseWeight);
            #endif
        }
        #ifdef ASTRA_OVERWORLD_OPTIMIZED
        previousLit = lit;
        #endif
        sum += lit * attenuation;
        attenuation *= attenuationStep;
    }
    return vec3(1.0,0.91,0.78) * sum * stepLength
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
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END && CLOUD_MODE == CLOUD_PLANAR
    // Uniform control flow: local slab marches need the same angular filtering
    // as the screen-cache producer, even at divergent terrain silhouettes.
    vec3 cloudFootprintRay = normalize(view_player(screen_view(vec3(texcoord,1.0))));
    float cloudAngularFootprint = max(length(dFdx(cloudFootprintRay)), length(dFdy(cloudFootprintRay)));
    #endif
    vec3 source = texture(colortex0, texcoord).rgb;
    float depth = texture(depthtex0, texcoord).r;
    #ifdef ASTRA_TAA
    float reactive = texelFetch(colortex16, ivec2(gl_FragCoord.xy), 0).r;
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END && CLOUD_MODE == CLOUD_VANILLA
    if (depth >= 0.999999) reactive = 1.0;
    #endif
    #ifdef DIMENSION_NETHER
    // Animated lighting and screen-space reflections have no single geometric
    // motion. Keep their existing short history even with the smoke module retired.
    reactive = max(reactive, 0.65);
    #endif
    #endif
    vec3 displayed = source;
    if (depth < 0.999999) {
        vec4 surface = texelFetch(colortex3, ivec2(gl_FragCoord.xy), 0);
        uint lightData = uint(round(surface.r * 255.0));
        bool hand = (lightData & 128u) != 0u;
        if (hand) depth = ((depth * 2.0 - 1.0) / MC_HAND_DEPTH) * 0.5 + 0.5;
        // Terrain AO and medium reconstruction share the same view position.
        // Hand pixels have no AO eligibility and keep their corrected projection.
        vec3 viewPos = screen_view(vec3(texcoord, depth));
        #ifdef ASTRA_SSAO
        #if !defined DIMENSION_NETHER && !defined DIMENSION_END
        // The palette matches LightParams.skyAmbient in the lit pass, so the
        // SH re-evaluation at the geometric normal reproduces the rendered
        // directional term exactly (R1 bent-normal swap inside). Overworld
        // only: nether/end never produced colortex21 and their colortex19.rgb
        // is zero, so the call there was already a no-op.
        if (!hand && (isEyeInWater == 0 || water_is_thin_sheet()))
            source=astra_apply_ambient_ao(source,texcoord,-viewPos.z,
                                          astra_sky_ambient());
        #endif
        #endif
        vec3 playerPos = view_camera_relative(viewPos);
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
        float standingWater = clamp(surface.a, 0.0, 1.0);
        if (standingWater > 0.15 && (isEyeInWater == 0 || water_is_thin_sheet()) && (lightData & 128u) == 0u) {
            vec3 n = decode_unit_vector(surface.gb*2.0-1.0);
            // Reflection only from a surface that can actually reflect sky: a wall
            // sheds the water, and a downward-facing quad reflects the ground.
            float upFacing = smoothstep(0.55, 0.92, n.y);
            // Ripple presence. The normal's vertical component is 1 where
            // astra_rain_ripple wrote nothing (dry ground), so a 1/400 tilt in it is
            // already a fully formed ripple.
            float rippled = clamp((1.0 - n.y) * 400.0, 0.0, 1.0);
            // Fresnel is at most one. If this upper bound cannot reach the
            // existing reflection threshold, no view direction or trace is needed.
            float reflectionCoverage = standingWater * upFacing * rippled;
            if (reflectionCoverage > 0.001) {
                vec3 incident = normalize(playerPos);
                float noV = max(dot(n, -incident), 0.0);
                float fresnel = 0.025+0.975*pow5(1.0-noV);
                // Every factor gates the CALL, not just the mix weight: puddle_reflection
                // costs up to 96 depth samples plus a refine, and GLSL evaluates mix
                // arguments unconditionally. Water-surface, translucent and sky-clear
                // pixels all reach this branch (colortex3 keeps its clear values there),
                // so without the weight gate they each pay the march for a result whose
                // upFacing is zero (consolidated review A3 / Qoder F-15 / F-42).
                float weight = reflectionCoverage*fresnel;
                if (weight > 0.001)
                    source = mix(source,puddle_reflection(playerPos,n,incident,noV), weight);
            }
        }
        #endif
        // R2/H3: the buffered volume owns the ordinary overworld air segment. The
        // fallback keeps blindness, lava, powder snow and the underwater camera on the
        // legacy medium exactly as they were (handoff R2 sections 1/4). scene*T + S
        // adds the in-scatter once; colortex4 below stays unmediated.
        #ifdef ASTRA_VOLUME_FOG
        if ((isEyeInWater == 0 || water_is_thin_sheet()) && blindness <= 0.0001) {
            vec4 volume;
            if ((lightData & 128u) != 0u)
                volume = astra_volume_prefix_medium(playerPos);
            else
                volume = astra_volume_resolve(colortex23, colortex3, texcoord, -viewPos.z, playerPos);
            volume = astra_volume_border(volume, length(playerPos));
            displayed = astra_volume_apply(source, volume);
        } else
        #endif
        {
            displayed = astra_apply_medium(source, playerPos, skylight);
        }

        #if !defined DIMENSION_NETHER && !defined DIMENSION_END && CLOUD_MODE == CLOUD_PLANAR
        // Screen-cloud resolve clips against this surface, with a local march only
        // when the opaque endpoint lies within/near the cloud slab.
        if (isEyeInWater < 2 && blindness <= 0.0001
            && max(cameraPosition.y, cameraPosition.y + playerPos.y)
               >= ASTRA_CLOUD_ALTITUDE - ASTRA_CLOUD_STRETCH - 1.0) {
            float cloudTerrainDistance = length(playerPos);
            vec3 cloudRay = normalize(view_player(viewPos));
            vec4 sheet = astra_screen_cloud(texcoord, cloudRay, cloudTerrainDistance, cloudAngularFootprint);
            displayed = displayed * (1.0 - sheet.a) + sheet.rgb;
            // Carry the same cloud into the unmediated refractive background.
            // Do not copy displayed: that would carry camera fog a second time.
            source = source * (1.0 - sheet.a) + sheet.rgb;
            #ifdef ASTRA_TAA
            if (sheet.a > 0.001) reactive = 1.0;
            #endif
        }
        #endif
        #if !defined DIMENSION_NETHER && !defined DIMENSION_END && !defined ASTRA_VOLUME_FOG
        // With the volume on, this air segment's rain in-scatter belongs to the march
        // (bounded weather gain in astra_volume_extinction); adding rainy_air here
        // would scatter the same air twice (handoff R2 section 4.2).
        displayed += rainy_air(playerPos);
        #endif
    }
    #if defined DIMENSION_END || defined DIMENSION_NETHER
    if (depth >= 0.999999) {
        #ifdef DIMENSION_END
        // Native-resolution producer skips geometry texels. Point access keeps
        // their empty payload out of neighbouring sky silhouettes.
        vec4 sky = texelFetch(colortex9, ivec2(gl_FragCoord.xy), 0);
        displayed = sky.rgb;
        float starVisibility = sky.a * (1.0-clamp(blindness,0.0,1.0));
        #ifdef ASTRA_TAA
        // Opaque, slow disc regions can accumulate. Lensed stars/translucent
        // silhouettes stay reactive; bright photosphere changes use short history.
        reactive = mix(0.10,1.0,smoothstep(0.02,0.40,sky.a));
        if(max(sky.r,max(sky.g,sky.b))>6.0) reactive=max(reactive,0.65);
        #endif
        if (blindness < 1.0)
            displayed += end_crisp_photon_ring(ray,cone)
                       * ASTRA_TINT_END_SKY
                       * (1.0-clamp(blindness,0.0,1.0)) * (1.0-0.18*end_eclipse());
        if (starVisibility > 0.0)
            displayed += end_starfield_filtered(endStarRay, cone, endStarDx, endStarDy) * starVisibility
                       * ASTRA_TINT_END_SKY
                       * (1.0-0.18*end_eclipse());
        #else
        displayed = astra_sky(normalize(view_player(screen_view(vec3(texcoord, 1.0)))));
        #endif
        source = displayed;
    }
    #endif
    #if !defined DIMENSION_END && !defined DIMENSION_NETHER && CLOUD_MODE != CLOUD_VANILLA
    if (depth >= 0.999999) {
        #if CLOUD_MODE == CLOUD_PLANAR
        vec4 cloud = astra_screen_cloud_sample(texcoord);
        displayed = cloud.rgb;
        // Fully covered sky contributes neither atmosphere, stars nor a disc.
        // Do not build those layers only to multiply them by zero afterwards.
        if (cloud.a < 1.0) {
        #endif
        #if CLOUD_MODE == CLOUD_PLANAR
        vec3 skyRay = cloudFootprintRay;
        #else
        vec3 skyRay = normalize(view_player(screen_view(vec3(texcoord,1.0))));
        #endif
        // Sun/moon were drawn additively over black in skytextured. Their phase
        // is in source; current cloud transmission is applied at this composition.
        // Same composition as astra_overworld_sky, exposing the star contribution
        // to TAA without a second catalogue query or rejecting the entire sky.
        vec3 clearSky = astra_sky_radiance(skyRay);
        #ifdef ASTRA_TAA
        // source carries moving celestial sprites over the black sky-basic layer.
        if (max(source.r, max(source.g, source.b)) > 0.0) reactive = 1.0;
        #endif
        #ifdef STARS
            float pointStars;
            vec3 skyStars = astra_star_field(skyRay, pointStars);
            clearSky += skyStars;
            #ifdef ASTRA_TAA
            if (pointStars > 0.0) reactive = 1.0;
            #endif
        #endif
        #if CLOUD_MODE == CLOUD_PLANAR
            displayed += (clearSky + source) * (1.0 - cloud.a);
        }
            #ifdef ASTRA_TAA
            if (cloud.a > 0.001) reactive = 1.0;
            #endif
        #else
        displayed = clearSky + source;
        #endif
        source = displayed; // Refraction/SSR background must also contain sky.
    }
    #endif
    // Sky has no geometry depth, but still lies behind the camera's medium.
    // Apply this after celestial/cloud composition so neither can shine through.
    bool obscureSky = isEyeInWater >= 2 || blindness > 0.0001;
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END
    // Overworld water applies blindness in composite3 to the complete scene.
    obscureSky = obscureSky && isEyeInWater != 1;
    #endif
    if (depth >= 0.999999 && obscureSky) {
        vec3 skyPosition = view_camera_relative(screen_view(vec3(texcoord, 1.0)));
        displayed = astra_apply_medium(displayed, skyPosition, 1.0);
        source = displayed;
    }
    gl_FragData[0] = vec4(displayed, 1.0);
    gl_FragData[1] = vec4(source, 1.0);
    #ifdef ASTRA_TAA
    gl_FragData[2] = vec4(reactive, 0.0, 0.0, 1.0);
    #endif
}
