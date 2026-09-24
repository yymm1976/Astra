#!/usr/bin/env python3
"""Execute the shipped cloud march with an instrumented empty density field.

Counts density reads only. No Minecraft terrain, cloud appearance or GPU timing
is simulated. Sky and terrain use the same sampling schedule up to the endpoint.
"""
import json
import numpy as np
from live_glsl_probe import render, require

FRAGMENT = """#version 400 compatibility
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/pow.glsl"
uniform int probe;
float densityReads=0.0;
vec4 emptyCloud(vec2 coordinate) { densityReads+=1.0; return vec4(0.0); }
#define cameraPosition vec3(0.0,64.0,0.0)
#define textureLod(s,u,l) emptyCloud(u)
#include "/global/atmosphere/clouds_planar.glsl"
#undef textureLod
void main() {
    vec3 direction=vec3(sqrt(0.99),0.1,0.0);
    vec4 cloud;
    if(probe==0) cloud=astra_planar_cloud(direction,1100.0);
    else if(probe==1) cloud=astra_planar_cloud(direction,1220.0);
    else if(probe==2) cloud=astra_planar_cloud(direction,1500.0);
    else cloud=astra_planar_cloud(direction);
    gl_FragColor=vec4(densityReads,cloud.a,0.0,1.0);
}
"""

def main():
    data=render(FRAGMENT,4)
    counts=data[:,:,:,0]
    print(json.dumps({'scope':'live GLSL sample count, synthetic empty density; no frame-time claim',
                     'camera_y':64,'direction_y':0.1,'slab_entry':1190,'slab_exit':1370,
                     'read_ranges_before_inside_after_sky':[[float(x.min()),float(x.max())] for x in counts]},indent=2))
    return require({
        'terrain before cloud entry performs no density read':bool((counts[0]==0).all()),
        'terrain at 1220 keeps only two front samples':bool((counts[1]==2).all()),
        'terrain beyond layer preserves all twelve samples':bool((counts[2]==12).all()),
        'sky retains the original twelve-sample schedule':bool((counts[3]==12).all()),
        'empty field remains transparent':bool((data[:,:,:,1]==0).all() and np.isfinite(data).all()),
    })

if __name__=='__main__':
    raise SystemExit(main())
