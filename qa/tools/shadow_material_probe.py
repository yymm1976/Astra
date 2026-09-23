#!/usr/bin/env python3
"""GPU colour equivalence on mixed water, glass, opaque and map-edge footprints."""
import numpy as np
from live_glsl_probe import render, require

FRAGMENT='''#version 400 compatibility
#include "/program/scene.glsl"
uniform int probe;
void main() {
    vec2 uv=gl_FragCoord.xy/256.0;
    // Include out-of-range coordinates to exercise clamped edge footprints.
    gl_FragColor=vec4(shadow_lobe_light(uv*1.2-0.1,0.5),1);
}
'''

def main():
    checks={}
    for colored in (True,False):
        options={'COLORED_SHADOWS':'' if colored else None}
        software=render(FRAGMENT,2,{**options,'SHADOW_FILTER_MODE':'0'})
        hardware=render(FRAGMENT,2,{**options,'SHADOW_FILTER_MODE':'1'})
        error=float(np.max(abs(software-hardware)))
        print(f'coloured={colored}, maximum per-channel error={error:.9g}')
        checks[f'paired RGB agrees, coloured={colored}']=error<2e-6
        checks[f'nondegenerate shadow result, coloured={colored}']=bool(software[:,:,:,:3].std()>0.1)
    return require(checks)

if __name__=='__main__':
    raise SystemExit(main())
