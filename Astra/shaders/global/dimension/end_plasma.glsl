#ifndef ASTRA_END_PLASMA_GLSL
#define ASTRA_END_PLASMA_GLSL
// Optical-depth proxies, not an X-ray spectrum or a magnetohydrodynamic solver.
// Four fixed samples serve the corona and the slower, broad disc wind together.
void end_plasma_layers(vec2 q,float sourceZ,float outside,
                       out vec4 behind,out vec4 ahead) {
    behind=vec4(0.0,0.0,0.0,1.0); ahead=behind;
    if(outside<0.001 || abs(q.x)>5.4 || abs(q.y)>3.0) return;
    const float cosIncl=0.987117;
    for(int i=0;i<4;i++) {
        float z=-3.3+float(i)*2.2;
        vec3 p=vec3(q.x,q.y*END_DISC_INCLINATION-z*cosIncl,
                    q.y*cosIncl+z*END_DISC_INCLINATION);
        float radius=length(p.xy), height=abs(p.z);
        float corona=exp(-pow((radius-1.35)/0.70,2.0)-pow(height/0.48,2.0))
                     *smoothstep(0.80,1.12,radius)*0.11;
        // Streamlines open gradually away from launch radii in the outer disc;
        // angular advection slows with height while material drifts outward.
        float launch=radius-height*0.48;
        float wind=smoothstep(1.55,2.05,launch)*(1.0-smoothstep(3.5,4.6,launch))
                   *smoothstep(0.07,0.24,height)*exp(-height*1.15);
        float windCore=0.0;
        if(wind>0.001) {
            float az=atan(p.y,p.x);
            vec2 uv=vec2(launch*0.75-height*0.18-frameTimeCounter*0.012,
                         az/END_TAU+frameTimeCounter*0.003/(1.0+height));
            float filament=textureLod(astraEndFlow,uv,0.0).a;
            wind*=0.18+0.82*smoothstep(0.35,0.70,filament);
            // Only the densest streamlines carry the ember accent; the body stays cool.
            windCore=smoothstep(0.48,0.82,filament);
        }
        float tau=(corona*0.22+wind*0.045)*outside;
        // Each sample represents a 2.2-unit depth interval. Split that interval
        // at the photosphere; assigning the entire cell to one side creates
        // hard diagonal bands when the moving surface crosses a sample centre.
        float nearFraction=clamp((z+1.1-sourceZ)/2.2,0.0,1.0);
        vec2 fraction=vec2(1.0-nearFraction,nearFraction);
        vec2 transmission=exp(-tau*2.2*fraction);
        // The disc is observed blue-white, so the plasma body follows it: a
        // blue-white corona over a blue-violet wind. Only the densest streamlines
        // take an ember tint, echoing the disc's dim outer tail instead of
        // introducing a second warm theme.
        vec3 emission=((vec3(0.55,0.72,1.00)*corona*0.72
                       +vec3(0.30,0.40,0.78)*wind*0.052)
                       +vec3(0.62,0.34,0.18)*wind*windCore*0.050)*outside;
        // Same depth convention as the photosphere: the near gas may veil its
        // light, while far gas is actually hidden by the opaque disc.
        ahead.rgb=ahead.rgb*transmission.y+emission*fraction.y;
        ahead.a*=transmission.y;
        behind.rgb=behind.rgb*transmission.x+emission*fraction.x;
        behind.a*=transmission.x;
    }
}
vec3 end_polar_jet(vec2 q,float aa,float outside) {
    float h=abs(q.y);
    if(h<0.95 || h>6.5 || abs(q.x)>0.25 || outside<0.001) return vec3(0.0);
    float opening=0.060*exp(-max(h-0.95,0.0)*2.3)+0.009+0.004*h;
    float coreWidth=0.006+0.002*h;
    float spine=exp(-q.x*q.x/(coreWidth*coreWidth+aa*aa));
    float sheathWidth=0.006+0.003*h;
    float sheath=exp(-pow(abs(q.x)-opening,2.0)/(sheathWidth*sheathWidth+aa*aa));
    float root=exp(-pow((h-1.22)/0.23,2.0));
    // Standing recollimation features plus two fading outward-moving shocks.
    float knots=0.38*exp(-pow((h-2.20)/0.13,2.0))
                +0.24*exp(-pow((h-3.65)/0.19,2.0));
    for(int i=0;i<2;i++) {
        float travel=mod(frameTimeCounter*0.085+float(i)*2.45,4.9);
        float envelope=smoothstep(0.0,0.4,travel)*(1.0-smoothstep(4.1,4.9,travel));
        knots+=0.52*envelope*exp(-pow((h-1.30-travel)/0.10,2.0));
    }
    float fade=exp(-max(h-1.0,0.0)*0.47)*(1.0-smoothstep(5.6,6.5,h));
    float side=q.y>0.0 ? 1.0 : 0.40;
    float brightness=spine*(0.070+knots*0.62)+sheath*(0.035+root*0.30+knots*0.18);
    return vec3(0.42,0.70,1.00)*brightness*fade*outside*side;
}
#endif
