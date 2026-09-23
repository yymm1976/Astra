#!/usr/bin/env python3
"""Live GLSL emission checks: current identities, all face directions, RGB peaks.

No historical commit, screenshot threshold or copied CPU shading formula is used.
These checks establish arithmetic properties, not whether the glow looks right.
"""
import json
import numpy as np
from live_glsl_probe import render, require, SHADERS
FRAGMENT="""#version 400 compatibility
#include "/lib/surface_emission.glsl"
#include "/lib/end_surface.glsl"
uniform int probe;
void main() {
    vec2 uv=gl_FragCoord.xy/256.0;
    vec3 normal=vec3(0,1,0);
    if(uv.y<0.3333) normal=vec3(0,-1,0);
    else if(uv.y<0.6666) normal=vec3(1,0,0);
    vec3 position=vec3(uv.x*32.0,5.0,uv.y*32.0);
    if(probe<4) {
        gl_FragColor=vec4(astra_rock_emission(uint(12+probe),vec3(uv.x),position,
                                         normal,vec3(0,0,-4),1.0),1);
    } else if(probe==4) {
        gl_FragColor=vec4(astra_rock_emission(12u,vec3(uv.x),position,normal,vec3(0,0,-4),0.0),1);
    } else if(probe==5 || probe==6) {
        gl_FragColor=vec4(astra_end_stone_emission(probe==5?11u:0u,vec3(uv.x)),1);
    } else {
        vec3 bevel=end_surface_bevel(vec3(0,1,0),vec3(uv.x,1.0,uv.y),0.001);
        gl_FragColor=vec4(abs(bevel-vec3(0,1,0)),1);
    }
}
"""
def main():
    data=render(FRAGMENT,8)
    rock=data[:4,:,:,:3]
    lith=(SHADERS/'program/lit.fsh').read_text(encoding='utf-8')
    block=(SHADERS/'block.properties').read_text(encoding='utf-8')
    vertex=(SHADERS/'program/lit.vsh').read_text(encoding='utf-8')
    checks={
        'finite nonnegative emission':bool(np.isfinite(data).all() and (data>=0).all()),
        'rock ceiling holds including downward faces':bool(rock.max()<=2.601),
        'all four rock classes respond to nearby light':bool((rock.max(axis=(1,2,3))>0).all()),
        'zero emission without block light':bool((data[4,:,:,:3]==0).all()),
        'End stone has bounded emission':bool(data[5,:,:,:3].max()>0 and data[5,:,:,:3].max()<=0.191),
        'equally pale non-End-stone does not emit':bool((data[6,:,:,:3]==0).all()),
        'ordinary cube face catches the bevel':bool(data[7,:,:,:3].max()>0.01),
        'live terrain calls measured emission helpers':all(n+'(' in lith for n in ['astra_rock_emission','astra_end_stone_emission']),
        'End stone identity reaches material 11': 'block.10012=minecraft:end_stone' in block.replace(' = ','=') and 'if (id == 10012) return 11u;' in vertex,
    }
    print(json.dumps({'scope':'synthetic GPU inputs; no visual verdict',
                     'rock_RGB_max':rock.max(axis=(1,2)).tolist(),
                     'End_stone_RGB_max':data[5,:,:,:3].max(axis=(0,1)).tolist()},indent=2))
    return require(checks)
if __name__=='__main__':
    raise SystemExit(main())
