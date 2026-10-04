#ifndef ASTRA_CLOUD_SHADOW_CACHE_GLSL
#define ASTRA_CLOUD_SHADOW_CACHE_GLSL
// Reference cloud-shadow caches (Refrax/Hysteria): idea only. Astra's plane mapping,
// snapped anchor, transition and storage are original. Uses the existing cloud field.
// SUMMARY CPU scheduling and source-height fade ideas: Kappa/VPS/Nostalgia.
// Included by scene.glsl after clouds_planar, before weather.
const float ASTRA_CLOUD_SHADOW_EXTENT = 512.0;

vec2 astra_cloud_shadow_anchor() {
    return astraCloudShadowAnchor;
}

float astra_cloud_plane_transmission(vec3 hit) {
    float gate = astra_cloud_existence_gate(0.0);
    float n = astra_cloud_coarse(hit,ASTRA_CLOUD_ALTITUDE);
    float cloud = smoothstep(gate-0.025,gate+0.025,n);
    return mix(1.0,0.07,cloud * astraCloudShadowFade);
}

#ifndef ASTRA_CLOUD_SHADOW_WRITE
uniform sampler2D colortex14;
#endif
float astra_cloud_shadow_at(vec3 hit) {
    if (astraCloudShadowFade <= 0.0) return 1.0;
    #ifdef ASTRA_CLOUD_SHADOW_WRITE
        return astra_cloud_plane_transmission(hit);
    #else
        vec2 uv = (hit.xz-astra_cloud_shadow_anchor())/ASTRA_CLOUD_SHADOW_EXTENT+0.5;
        // Express the border in actual texels, including non-square grids.
        vec2 border = min(uv,1.0-uv)*vec2(textureSize(colortex14,0));
        float edge = min(border.x,border.y);
        // Do not clamp a world-space query to the map edge: use the actual field there.
        if (edge <= 0.5) return astra_cloud_plane_transmission(hit);
        float cached = textureLod(colortex14,uv,0.0).r;
        if (edge >= 8.0) return cached;
        float weight = smoothstep(0.5,8.0,edge);
        return mix(astra_cloud_plane_transmission(hit),cached,weight);
    #endif
}
#endif
