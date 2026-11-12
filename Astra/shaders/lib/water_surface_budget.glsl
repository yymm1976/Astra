#ifndef ASTRA_WATER_SURFACE_BUDGET_GLSL
#define ASTRA_WATER_SURFACE_BUDGET_GLSL
// The receiver-distance ramp owns air-side reflection/refraction budgets.
// Depth haze follows the actual water leg in every Overworld budget. Callers decide
// whether a path belongs to a horizontal water surface, never wet terrain.
float astra_water_surface_simplification(float receiverDistance) {
    #ifdef ASTRA_OVERWORLD_OPTIMIZED
        #ifdef ASTRA_OVERWORLD_AGGRESSIVE
        return smoothstep(32.0, 64.0, receiverDistance);
        #else
        return smoothstep(48.0, 96.0, receiverDistance);
        #endif
    #else
        return 0.0;
    #endif
}
float astra_water_surface_haze(float waterPathLength, float receiverDistance) {
    #if !defined DIMENSION_NETHER && !defined DIMENSION_END && UNDERWATER_FOG_DENSITY > 0
        float farHaze = 0.15 * astra_water_surface_simplification(receiverDistance);
        // Continuous optical depth over the real interface-to-background water
        // leg: an extra ~0.067/block extinction, eased in over the first blocks
        // so a one-block pool keeps its neutral bed. This is a separate loss on
        // top of the affine transfer, kept well below the reference medium.
        float path = max(waterPathLength, 0.0);
        float opticalDepth = 0.067 * path;
        // Reciprocal cubic approximates extinction without an additional exp
        // for every transported corner. It stays monotone, positive and tends
        // to opaque. The spectral absorption remains in the caller.
        float transport = 1.0/(1.0+opticalDepth*(1.0+opticalDepth*(0.5+opticalDepth/6.0)));
        float depthHaze = (1.0-transport) * smoothstep(0.75,4.0,path);
        // Reuse the water-body source, not a white screen overlay. A lighter
        // medium stays lighter; the two ramps do not accumulate their losses.
        return max(farHaze, depthHaze)
             * min(float(UNDERWATER_FOG_DENSITY) / 40.0, 1.0);
    #else
        return 0.0;
    #endif
}
#endif
