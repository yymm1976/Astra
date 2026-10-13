#ifndef ASTRA_LIB_DITHER_GLSL
#define ASTRA_LIB_DITHER_GLSL

// From Mellow v3.4 (MIT) by TheCMK - lib/noise.glsl (ign / dither)
// Mechanical port. Output dither follows optional scene TAA and stays outside
// HDR history, so static IGN is intentional. License: MIT - see THIRD-PARTY.md.
// Uniforms: frameCounter (only when ign() is called with animate = true)

float ign(vec2 pos, const bool animate) {
    if (animate) {
        float frame_mod = frameCounter % 64;
        pos += 5.588238 * frame_mod;
    }

    return fract(52.9829189 * fract(0.06711056 * pos.x + 0.00583715 * pos.y));
}

float dither(vec2 pos) {
    return ign(pos, false);
}

#endif
