#ifndef ASTRA_LIB_DITHER_GLSL
#define ASTRA_LIB_DITHER_GLSL

// From Mellow v3.4 (MIT) by TheCMK - lib/noise.glsl (ign / dither)
// Mechanical port. Astra has no TAA (design.md 2.4), so dither() is static IGN -
// Mellow's own note: static interleaved gradient noise is the visually pleasing
// choice without TAA. License: MIT - see THIRD-PARTY.md.
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
