#ifndef ASTRA_NETHER_REFLECTION_GLSL
#define ASTRA_NETHER_REFLECTION_GLSL
// Adapted from Complementary r5.9 Reimagined by EminGT:
// materialMethods/reflections.glsl, deferred1.glsl and composite1.glsl.
// Uses Astra current-frame colour/depth and normal packing. See THIRD-PARTY.md.
#include "/lib/nether_fog_density.glsl"
float nether_rock_fresnel(float fresnel, float viewDistance, float smoothness) {
    // Complementary SSR-only uses 0.7 to hide incomplete screen-space coverage.
    // Astra widens the useful oblique angles to 0.35 at the user's request.
    // Keep the squared falloff, zero face-on response and grazing peak; do not
    // increase smoothness or emitter energy to expose these reflections.
    float factor = (1.0 - smoothness) * 0.35;
    float f = max(fresnel - factor, 0.0) / (1.0 - factor);
    float visibility = 1.0;
    #ifdef BORDER_FOG
    float density = NETHER_FOG_DENSITY*0.01*astra_nether_biome_density();
    visibility -= clamp(viewDistance/max(min(borderFogDistance,256.0),1.0)*density,0.0,1.0);
    #endif
    // Complementary composite1 consumes Fresnel already attenuated by receiver
    // fog. The reflected source's own fog does not replace this receiver leg.
    return f * f * sqrt(smoothness) * visibility;
}
vec4 nether_rock_trace(vec3 viewPos, vec3 viewDirection, float viewDistance,
                       vec3 normal, float fresnel, float smoothness, float dither, out float refDist) {
    refDist=0.0;
    float lViewPos = viewDistance;
    vec3 start = viewPos + normal * (lViewPos * 0.025 * (1.0 - fresnel) + 0.05);
    vec3 vector = normalize(reflect(viewDirection, normal)) * 0.5;
    vec3 point = start + vector;
    vec3 travel = vector;
    vec3 refPos = vec3(0.0);
    vec3 scenePos = vec3(0.0);
    float error = 1e10;
    float depth = 1.0;
    int refinement = 0;
    for (int i = 0; i < 30; ++i) {
        if (point.z >= -0.05) return vec4(0.0);
        refPos = view_screen(point);
        if (any(lessThan(refPos.xy, vec2(0.0))) || any(greaterThan(refPos.xy, vec2(1.0))))
            return vec4(0.0);
        depth = textureLod(depthtex1, refPos.xy, 0.0).r;
        scenePos = screen_view(vec3(refPos.xy, depth));
        error = length(point - scenePos);
        if (error * 0.33333 < length(vector)) {
            refinement++;
            if (refinement >= 6) break;
            travel -= vector;
            vector *= 0.1;
        }
        vector *= 2.0;
        travel += vector * (0.95 + 0.1 * dither);
        point = start + travel;
    }
    if (depth >= 0.999999) return vec4(0.0);
    float sceneDistance = length(scenePos);
    if (error * (1.0 - fresnel) >= 1.0 + sceneDistance * 0.2) return vec4(0.0);
    // The reference tolerates off-screen projection; Astra's buffers clamp at
    // the viewport, so fade inside it instead of accepting repeated edge texels.
    vec2 edge = abs(refPos.xy - 0.5) * 2.0;
    float confidence = clamp(1.0 - pow(max(edge.x, edge.y), 50.0), 0.0, 1.0);
    float receiverCoverage = clamp(sceneDistance-lViewPos+3.0,0.0,1.0);
    refDist=length(start-scenePos);
    // Keep the virtual-image distance even when this hit contributes no colour.
    if (confidence <= 0.0 || receiverCoverage <= 0.0) return vec4(0.0);
    float smoothness2 = smoothness * smoothness;
    float lodFactor = 1.0 - exp(-0.125 * (1.0 - smoothness2) * refDist);
    float lod = max(log2(max(viewHeight / 8.0 * (1.0 - smoothness2) * lodFactor, 1.0)) * 0.45 - 1.0, 0.0);
    vec3 reflected = textureLod(colortex0,refPos.xy,lod).rgb;
    // Complementary confidence suppresses bright edge streaks and hits in front
    // of the receiver. Its SSR-only background in the Nether is black.
    vec2 border = 1.0 - pow(edge / vec2(1.2,1.1), vec2(8.0));
    border.x = 1.0 - pow(edge.x / 1.2,16.0);
    float luminance = dot(srgb_encode(max(reflected,vec3(0.0))),vec3(0.2126,0.7152,0.0722));
    confidence *= pow(clamp(border.x*border.y,0.0,1.0),2.0+3.0*luminance);
    confidence *= receiverCoverage;
    return vec4(reflected, confidence);
}
#endif
