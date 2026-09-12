#ifndef ASTRA_LIB_TRANSFORMS_GLSL
#define ASTRA_LIB_TRANSFORMS_GLSL

// From Mellow v3.4 (MIT) by TheCMK - lib/transformations.glsl
// Renamed to snake_case per design.md 3.2; Distant-Horizons branches dropped
// (Astra v1 is Voxy-only, design.md 1.2). License: MIT - see THIRD-PARTY.md.
// Uniforms: gbufferProjection, gbufferProjectionInverse, gbufferModelView,
//           gbufferModelViewInverse, shadowModelView, shadowProjection
//           (declared in lib/uniforms.glsl)
//           (+ vxModelView, vxModelViewInv only for an explicit ASTRA_VOXY_PASS)

vec3 project_and_divide(mat4 projection_mat, vec3 x) {
    vec4 homogeneous_pos = projection_mat * vec4(x, 1.0);
    return homogeneous_pos.xyz / homogeneous_pos.w;
}

// [0,1] screen depth/uv -> view space
vec3 screen_view(vec3 x) {
    x = x * 2.0 - 1.0;
    return project_and_divide(gbufferProjectionInverse, x);
}

// view space -> player-relative world space (direction-only transform)
vec3 view_player(vec3 x) {
    #ifdef ASTRA_VOXY_PASS
        mat4 mat = vxModelViewInv;
    #else
        mat4 mat = gbufferModelViewInverse;
    #endif
    return mat3(mat) * x;
}

// player-relative world space -> view space (direction-only transform)
vec3 player_view(vec3 x) {
    #ifdef ASTRA_VOXY_PASS
        mat4 mat = vxModelView;
    #else
        mat4 mat = gbufferModelView;
    #endif
    return mat3(mat) * x;
}

// view space -> [0,1] screen space
vec3 view_screen(vec3 x) {
    x = project_and_divide(gbufferProjection, x);
    return x * 0.5 + 0.5;
}

// Point transforms include translation; view_player/player_view above transform
// directions only. Solas ToWorld and Steadfast lit use this affine contract.
// Native 26.2 normally supplies a pure rotation here; do not invent a nonzero
// section-origin translation, nor assume translation is absent on every path.
vec3 view_camera_relative(vec3 x) {
    return (gbufferModelViewInverse * vec4(x, 1.0)).xyz;
}

vec3 camera_relative_view(vec3 x) {
    return (gbufferModelView * vec4(x, 1.0)).xyz;
}

// Camera-relative world point -> shadow NDC. Iris ShadowRenderer supplies its
// MODELVIEW directly to Sodium ChunkRenderMatrices. Sodium GLDrawContext already
// subtracts the entire camera position in u_RegionOffset (integer + fraction).
// The point conversion above has already applied the main inverse view.
// Do not add its translation a second time here.
#ifdef DIMENSION_END
#include "/lib/end_light.glsl"
vec3 end_shadow_view(vec3 playerPos) {
    vec3 light = end_light_direction();
    vec3 right = normalize(cross(vec3(0.0,1.0,0.0),light));
    vec3 up = cross(light,right);
    return vec3(dot(playerPos,right),dot(playerPos,up),dot(playerPos,light))
         + vec3(0.0,0.0,shadowModelView[3].z);
}
#endif
vec3 astra_shadow_light_direction() {
    #ifdef DIMENSION_END
    return end_light_direction();
    #else
    return normalize(view_player(lightVector));
    #endif
}
vec3 player_shadow(vec3 player_pos) {
    #ifdef DIMENSION_END
    return project_and_divide(shadowProjection,end_shadow_view(player_pos));
    #else
    vec3 shadow_pos = project_and_divide(shadowProjection,
        (shadowModelView * vec4(player_pos, 1.0)).xyz);
    return shadow_pos;
    #endif
}

#endif
