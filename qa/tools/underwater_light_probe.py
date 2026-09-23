#!/usr/bin/env python3
"""GPU arithmetic checks for the live caustic, beam and water spectrum helpers.

Synthetic inputs only: neither scene visibility nor perceived quality is inferred.
Caustic correlation is reported, not used as a substitute for observing repetition.
"""
import json
import numpy as np
from live_glsl_probe import render, require, SHADERS

FRAGMENT = """#version 400 compatibility
#include "/lib/settings.glsl"
uniform float frameTimeCounter;
uniform sampler2D solasWaterNoise;
uniform int probe;
#include "/global/water/caustics.glsl"
#include "/lib/water_light_field.glsl"
#include "/global/water/absorption.glsl"
void main() {
    vec2 uv=gl_FragCoord.xy/256.0;
    if(probe<4) {
        float field=solas_water_caustics(vec3((uv.x-0.5)*16.0,7.0,(uv.y-0.5)*16.0));
        gl_FragColor=vec4(field,0,0,1);
    } else if(probe==4) {
        float azimuth=uv.x*6.2831853;
        float elevation=(uv.y-0.5)*3.14159265;
        vec3 ray=vec3(sin(azimuth)*cos(elevation),sin(elevation),cos(azimuth)*cos(elevation));
        gl_FragColor=vec4(astra_water_phase(ray,normalize(vec3(0,1,1))),0,0,1);
    } else if(probe==5) {
        gl_FragColor=vec4(astra_water_beam_tint(vec3(1),uv.x*40.0),1);
    } else if(probe==6) {
        gl_FragColor=vec4(astra_water_beam_limit(vec3(0.2,0.6,1.0)*uv.x*100.0),1);
    } else if(probe==7) {
        gl_FragColor=vec4(exp(-8.0*water_surface_absorption(9.0)),1);
    } else {
        gl_FragColor=vec4(astra_water_beam_limit(astra_water_beam_tint(vec3(0),uv.x*40.0)),1);
    }
}
"""

def main(shafts_only=False):
    data=render(FRAGMENT,9)
    phase=data[4,:,:,0]
    tint=data[5,:,:,:3]
    limited=data[6,:,:,:3]
    field=data[:4,:,:,0]
    spectrum=data[7,0,0,:3]
    shaft_source=(SHADERS/'global/water/light_shafts.glsl').read_text(encoding='utf-8')
    checks={
        'all sampled values finite and nonnegative':bool(np.isfinite(data).all() and (data>=0).all()),
        'phase preserves backscatter and directional contrast':bool(phase.min()>0 and phase.max()>4*phase.min()),
        'white caster acquires water chroma at every distance':bool((tint[:,:,2]>tint[:,:,1]).all() and (tint[:,:,1]>tint[:,:,0]).all()),
        'black caster adds no beam':bool((data[8,:,:,:3]==0).all()),
        'limiter bounds HDR without bleaching hue':bool(limited.max()<1 and np.max(abs(limited[:,:,0]-limited[:,:,2]*0.2))<1e-6 and np.max(abs(limited[:,:,1]-limited[:,:,2]*0.6))<1e-6),
        'live march calls measured phase tint and limiter':all(name+'(' in shaft_source for name in ['astra_water_phase','astra_water_beam_tint','astra_water_beam_limit']),
    }
    if not shafts_only:
        checks.update({
            'caustic field is nonconstant and bounded':bool(np.std(field)>0.01 and field.max()<10),
            'caustics animate':bool(np.mean(abs(field[0]-field[1]))>0.01),
            '8-block surface transmission removes red and retains blue':bool(spectrum[0]<0.01*spectrum[1] and spectrum[1]>0.12 and spectrum[2]>0.30),
        })
    # Off-origin autocorrelation reports repeated spacing without declaring a look solved.
    spectrum2=np.fft.rfft2(field[0]-field[0].mean())
    correlation=np.fft.irfft2(abs(spectrum2)**2,s=field[0].shape).real
    correlation/=correlation[0,0]
    print(json.dumps({'scope':'GPU helpers on synthetic inputs; no in-game appearance verdict',
                     'caustic_percentiles':np.percentile(field,[0,50,95,99,100]).tolist(),
                     'x_correlation_1_to_8_blocks':correlation[0,16:129:16].tolist(),
                     'phase_range':[float(phase.min()),float(phase.max())],
                     'surface_transmission_8_blocks':spectrum.tolist()},indent=2))
    return require(checks)

if __name__=='__main__':
    raise SystemExit(main())
