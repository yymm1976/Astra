#ifndef ASTRA_HISTORY_FRAME_GLSL
#define ASTRA_HISTORY_FRAME_GLSL
// Shared by the frame predicates evaluated in vertex stages. Ordered threshold
// comparisons alone do not reject NaN, including NaN from infinity - infinity.
bool astra_history_frame_inputs_valid() {
    vec3 travel = cameraPosition - previousCameraPosition;
    vec4 effects = vec4(blindness, darknessFactor, frameTimeCounter, lightningBoltPosition.w);
    if (any(isnan(travel)) || any(isinf(travel)) || length(travel) > 8.0
        || any(isnan(effects)) || any(isinf(effects))) return false;
    for (int i = 0; i < 4; ++i) {
        vec4 projectionDelta = gbufferProjection[i] - gbufferPreviousProjection[i];
        if (any(isnan(projectionDelta)) || any(isinf(projectionDelta))
            || any(greaterThan(abs(projectionDelta), vec4(0.0001)))
            || any(isnan(gbufferPreviousModelView[i]))
            || any(isinf(gbufferPreviousModelView[i]))) return false;
    }
    return true;
}
#endif
