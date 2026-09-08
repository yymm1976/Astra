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

// SC-35 render-origin contract (Iris on 26.x): gbufferModelViewInverse[3] is a
// NONZERO section-origin translation T that slides with the player. Full-affine
// point transforms therefore yield (camera-relative + T); mixing those with
// cameraPosition or length() anchored effects to the render origin instead of
// the world (moving torch ball, swimming waves/caustics, fog distance error).
// Working packs keep the rotation part only (Mellow lib/transformations.glsl,
// Solas lib/util/ToWorld.glsl). Shadow rendering has its OWN model-view matrix;
// the main camera's inverse-view translation must not enter that pipeline.
vec3 view_camera_relative(vec3 x) {
    return mat3(gbufferModelViewInverse) * x;
}

vec3 camera_relative_view(vec3 x) {
    return mat3(gbufferModelView) * x;
}

// Camera-relative world point -> shadow NDC. Iris ShadowRenderer supplies its
// MODELVIEW directly to Sodium ChunkRenderMatrices. Sodium GLDrawContext already
// subtracts the entire camera position in u_RegionOffset (integer + fraction).
// Adding gbufferModelViewInverse[3] here displaced ALL receivers as the eye moved.
vec3 player_shadow(vec3 player_pos) {
    vec3 shadow_pos = project_and_divide(shadowProjection,
        (shadowModelView * vec4(player_pos, 1.0)).xyz);
    return shadow_pos;
}

#endif
