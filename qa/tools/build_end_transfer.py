"""Build Astra's original, static light-path atlas; never runs during a game frame."""
from pathlib import Path
import argparse, re, subprocess, tempfile
import numpy as np
from PIL import Image
from render_end_design import JAVA
from compile_glsl import lwjgl_classpath, DEFAULT_MC_ROOT

ROOT = Path(__file__).resolve().parents[2]
SIZE = 4096
FRAGMENT = r'''#version 430 compatibility
uniform int panorama; // 0 = coordinates, 1 = local emission direction / face.
/*DISC_PROFILE*/
float discDistance(vec3 p,vec3 normal) {
    float h=dot(p,normal)/2.598076211;
    float r=length(p-normal*dot(p,normal))/2.598076211;
    return max(abs(h)-end_disc_half_height(r),max(END_DISC_INNER-r,r-END_DISC_OUTER));
}
vec3 acceleration(vec3 p,float l2) {
    float r2=dot(p,p);
    return -1.5*l2*p/(r2*r2*sqrt(r2));
}
void main() {
    vec2 uv=gl_FragCoord.xy/float(/*ATLAS_SIZE*/);
    int imageIndex=uv.y<0.5 ? 0 : 1;
    vec2 q=vec2((uv.x-0.5)*12.0,(fract(uv.y*2.0)-0.5)*6.0);
    const float impact=2.598076211;
    const float inclination=END_DISC_INCLINATION;
    vec3 normal=vec3(0.0,sqrt(1.0-inclination*inclination),inclination);
    vec3 discY=vec3(0.0,inclination,-normal.y);
    vec3 p=vec3(q*impact,80.0), v=vec3(0,0,-1);
    float l2=dot(p.xy,p.xy);
    vec3 a=acceleration(p,l2);
    vec2 hit=vec2(32.0);
    vec4 metadata=vec4(0.5,0.5,1.0,1.0);
    int crossings=0;
    for(int i=0;i<1500;i++) {
        float r=length(p);
        float ds=clamp(r*0.027,0.012,1.5);
        if(r<15.0 && abs(dot(p,normal))<0.95) ds=min(ds,0.036);
        vec3 next=p+v*ds+a*(0.5*ds*ds);
        vec3 na=acceleration(next,l2);
        vec3 nv=v+(a+na)*(0.5*ds);
        float h=discDistance(p,normal), nh=discDistance(next,normal);
        if(h>0.0 && nh<=0.0) {
            float fraction=h/(h-nh);
            vec3 at=mix(p,next,fraction);
            if(crossings==imageIndex) {
                hit=vec2(at.x,dot(at,discY))/impact;
                vec3 toward=-normalize(mix(v,nv,fraction));
                vec3 local=vec3(toward.x,dot(toward,discY),dot(toward,normal));
                metadata=vec4(local*0.5+0.5,dot(at,normal)>0.0 ? 1.0 : 0.0);
                break;
            }
            crossings++;
        }
        p=next; v=nv; a=na;
        if(length(p)<1.001 || (length(p)>90.0 && dot(p,v)>0.0)) break;
    }
    gl_FragColor=panorama==0 ? vec4(hit,0,1) : metadata;
}'''

def build_flow_mips():
    source=ROOT/'Astra/shaders/textures/astra-end-flow.png'
    level=np.asarray(Image.open(source).convert('RGBA'),dtype=np.float64)
    if level.shape[:2]!=(1024,1024):
        raise ValueError('End flow mip layout expects a 1024-square source')
    atlas=np.zeros((1043,514,4),dtype=np.uint8)
    row=0
    for index in range(1,11):
        h,w=level.shape[:2]
        level=level.reshape(h//2,2,w//2,2,4).mean(axis=(1,3))
        tile=np.pad(np.uint8(np.rint(level)),((1,1),(1,1),(0,0)),mode='wrap')
        atlas[row:row+tile.shape[0],:tile.shape[1]]=tile
        row+=tile.shape[0]
    output=source.with_name('astra-end-flow-mips.png')
    Image.fromarray(atlas,'RGBA').save(output)
    output.with_suffix('.png.mcmeta').write_text(
        '{"texture":{"blur":true,"clamp":true}}\n',encoding='utf-8')
    print(output)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--flow-mips-only',action='store_true')
    args=parser.parse_args()
    if args.flow_mips_only:
        build_flow_mips()
        return
    cp=lwjgl_classpath(DEFAULT_MC_ROOT)
    java=JAVA.replace('1024,768',f'{SIZE},{SIZE}').replace('1024*768',f'{SIZE}*{SIZE}')
    with tempfile.TemporaryDirectory(prefix='astra-transfer-') as tmp:
        t=Path(tmp)
        (t/'EndPreview.java').write_text(java,encoding='utf-8')
        profile=(ROOT/'Astra/shaders/global/dimension/end_disc_profile.glsl').read_text(encoding='utf-8')
        (t/'transfer.frag').write_text(FRAGMENT.replace('/*DISC_PROFILE*/',profile).replace('/*ATLAS_SIZE*/',str(SIZE)),encoding='utf-8')
        subprocess.run(['javac','-cp',cp,str(t/'EndPreview.java')],check=True)
        subprocess.run(['java','-cp',cp+';'+str(t),'EndPreview',str(t/'transfer.frag'),str(t/'transfer.bin'),'0','0','0','0'],check=True)
        xy=np.fromfile(t/'transfer.bin',dtype='>f4').reshape(SIZE,SIZE,4)[:,:,:2]
        subprocess.run(['java','-cp',cp+';'+str(t),'EndPreview',str(t/'transfer.frag'),str(t/'metadata.bin'),'0','0','1','0'],check=True)
        metadata=np.fromfile(t/'metadata.bin',dtype='>f4').reshape(SIZE,SIZE,4)
    # Two 16-bit fixed-point coordinates packed into RG / BA. Decoding is linear,
    # including across low-byte carries, so ordinary bilinear sampling is valid.
    fixed=np.rint(np.clip(xy/64.0+0.5,0,1)*65535).astype(np.uint16)
    rgba=np.stack([fixed[:,:,0]>>8,fixed[:,:,0]&255,fixed[:,:,1]>>8,fixed[:,:,1]&255],axis=2).astype(np.uint8)
    output=ROOT/'Astra/shaders/textures/astra-end-transfer.png'
    Image.fromarray(rgba,'RGBA').save(output)
    # Emitting rear surfaces exchange atlas order across the transparent outer
    # cutoff wall. Continue their direction into non-emitting neighbours before
    # downsampling: mixing a wall/default direction into them creates a false
    # Doppler/limb-darkening seam despite perfectly continuous hit coordinates.
    outer=float(re.search(r'END_DISC_OUTER\s*=\s*([0-9.]+)',profile).group(1))
    front_xy, rear_xy=xy[:SIZE//2],xy[SIZE//2:]
    front_frame, rear_frame=metadata[:SIZE//2],metadata[SIZE//2:]
    front_valid=np.max(np.abs(front_xy),axis=2)<31.5
    rear_valid=np.max(np.abs(rear_xy),axis=2)<31.5
    transparent_wall=np.linalg.norm(front_xy,axis=2)>=outer-0.002
    extend_rear=(~front_valid|transparent_wall)&rear_valid
    extend_front=~rear_valid&front_valid&~transparent_wall
    front_frame[extend_rear]=rear_frame[extend_rear]
    rear_frame[extend_front]=front_frame[extend_front]
    # Smooth direction metadata stays at 1024 square; the finer coordinate atlas
    # needs 64 MiB, but direction does not need another 64 MiB image.
    factor=SIZE//1024
    metadata=metadata.reshape(1024,factor,1024,factor,4).mean(axis=(1,3))
    Image.fromarray(np.uint8(np.clip(metadata,0,1)*255),'RGBA').save(output.with_name('astra-end-transfer-meta.png'))
    # Periodic original flow field: independent multiscale channels, no image assets.
    rng=np.random.default_rng(618)
    fields=[]
    for channel in range(4):
        field=np.zeros((1024,1024),dtype=np.float64)
        total=0.0
        for size,weight in [(3,0.30),(6,0.30),(12,0.22),(24,0.13),(48,0.05)]:
            grid=rng.random((size,size))
            coords=np.arange(1024)*size/1024
            base=np.floor(coords).astype(int)
            f=coords-base; f=f*f*(3-2*f)
            along=grid[:,base]*(1-f)+grid[:,(base+1)%size]*f
            field+=(along[base,:]*(1-f[:,None])+along[(base+1)%size,:]*f[:,None])*weight
            total+=weight
        field=np.clip((field/total-0.5)*1.65+0.5,0,1)
        if channel in (1,3):
            # Original, independent fine scales modulate existing strands/grains.
            # Multiplication only removes radiance; the previous peak is retained.
            detail=np.zeros_like(field)
            fine_rng=np.random.default_rng(930+channel)
            for fine_size,fine_weight in [(24,0.50),(48,0.35),(96,0.15)]:
                fine_grid=fine_rng.random((fine_size,fine_size))
                coords=np.arange(1024)*fine_size/1024
                base=np.floor(coords).astype(int)
                f=coords-base; f=f*f*(3-2*f)
                along=fine_grid[:,base]*(1-f)+fine_grid[:,(base+1)%fine_size]*f
                detail+=(along[base,:]*(1-f[:,None])+along[(base+1)%fine_size,:]*f[:,None])*fine_weight
            field*=0.78+0.22*np.clip((detail-0.5)*2.0+0.5,0,1)
        fields.append(field)
    Image.fromarray(np.uint8(np.stack(fields,axis=2)*255),'RGBA').save(output.with_name('astra-end-flow.png'))
    build_flow_mips()
    print(output)

if __name__=='__main__': main()
