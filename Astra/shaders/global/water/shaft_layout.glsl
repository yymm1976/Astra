#ifndef ASTRA_WATER_SHAFT_LAYOUT_GLSL
#define ASTRA_WATER_SHAFT_LAYOUT_GLSL
// Camera distance attenuates nearby and far scattering. It never places light
// sources, moves water entry points or carves a ring of emitters around the eye.
const float WATER_SHAFT_NEAR_START = 0.08;
const float WATER_SHAFT_NEAR_END = max(0.3,float(UNDERWATER_SHAFT_DISTANCE));
const float WATER_SHAFT_FAR_START = 14.0;
const float WATER_SHAFT_FAR_END = 26.0;
#endif
