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

RESOLVE_FRAGMENT = """#version 400 compatibility
#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/global/water/light_shafts.glsl"
uniform sampler2D probeTexture;
uniform int probe;
void main() {
    vec2 uv=vec2(0.5);
    float distanceToEye=52.0;
    if(probe==1) distanceToEye=4.0;
    if(probe==2) distanceToEye=100.0;
    if(probe==3) { uv=vec2(1.0); distanceToEye=128.0; }
    if(probe==4) { uv=vec2(0.0); distanceToEye=128.0; }
    gl_FragColor=vec4(water_shafts_resolve(probeTexture,uv,distanceToEye),1.0);
}
"""

def resolve_checks():
    # A black near surface beside a coloured far shaft, repeated vertically.
    # At distance 52 both depth weights match, so each side contributes one half.
    fixture=np.zeros((2,2,4),dtype=np.float32)
    fixture[:,0,3]=4.0/128.0
    fixture[:,1,:3]=(np.array([0.2,0.6,1.0])/128.0)**0.25
    fixture[:,1,3]=100.0/128.0
    data=render(RESOLVE_FRAGMENT,5,texture_data=fixture)[:,0,0,:3]
    expected=np.array([0.2,0.6,1.0])
    checks={
        'resolve averages decoded additive intensity':bool(np.max(abs(data[0]-expected*0.5))<2e-6),
        'resolve rejects far shafts at a near silhouette':bool(data[1].max()<1e-6),
        'resolve preserves far shaft colour':bool(np.max(abs(data[2]-expected))<2e-6),
        'resolve sky and clamped bright edge stay finite':bool(np.isfinite(data).all() and np.max(abs(data[3]-expected))<2e-6),
        'resolve clamped black edge stays black':bool(data[4].max()==0),
    }
    print(json.dumps({'resolve_scope':'synthetic texture; gamma-domain additive intensity, not scene radiance',
                     'equal_weight_mix':data[0].tolist(),'near_edge_leak':float(data[1].max()),
                     'far_colour':data[2].tolist(),'sky_edge':data[3].tolist()},indent=2))
    return checks

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
    checks.update(resolve_checks())
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
