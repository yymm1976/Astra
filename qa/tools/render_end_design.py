"""Render the actual End GLSL with LWJGL in a hidden window, without Minecraft."""
from pathlib import Path
import argparse, subprocess, tempfile
import numpy as np
from PIL import Image
from compile_glsl import lwjgl_classpath, DEFAULT_MC_ROOT

JAVA = r'''
import java.nio.file.*;
import java.io.*;
import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.nio.ByteBuffer;
import static org.lwjgl.glfw.GLFW.*;
import org.lwjgl.opengl.GL;
import static org.lwjgl.opengl.GL11.*;
import static org.lwjgl.opengl.GL13.*;
import static org.lwjgl.opengl.GL20.*;
import static org.lwjgl.opengl.GL30.*;
public class EndPreview {
 static void bindImage(int program,String name,String file,int unit) throws Exception {
  int location=glGetUniformLocation(program,name); if(location<0) return;
  BufferedImage image=ImageIO.read(new File(file));
  ByteBuffer pixels=org.lwjgl.BufferUtils.createByteBuffer(image.getWidth()*image.getHeight()*4);
  for(int y=0;y<image.getHeight();y++) for(int x=0;x<image.getWidth();x++) {
   int c=image.getRGB(x,y);pixels.put((byte)(c>>16)).put((byte)(c>>8)).put((byte)c).put((byte)(c>>24));
  }
  pixels.flip();glActiveTexture(GL_TEXTURE0+unit);int texture=glGenTextures();glBindTexture(GL_TEXTURE_2D,texture);
  glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8,image.getWidth(),image.getHeight(),0,GL_RGBA,GL_UNSIGNED_BYTE,pixels);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
  glUniform1i(location,unit);
 }
 public static void main(String[] args) throws Exception {
  if(!glfwInit()) throw new RuntimeException("GLFW");
  glfwWindowHint(GLFW_VISIBLE,GLFW_FALSE);
  long w=glfwCreateWindow(1024,768,"End offline",0,0); glfwMakeContextCurrent(w); GL.createCapabilities();
  int fs=glCreateShader(GL_FRAGMENT_SHADER); glShaderSource(fs,Files.readString(Path.of(args[0])));glCompileShader(fs);
  if(glGetShaderi(fs,GL_COMPILE_STATUS)==0) throw new RuntimeException(glGetShaderInfoLog(fs));
  int vs=glCreateShader(GL_VERTEX_SHADER);glShaderSource(vs,"#version 430 compatibility\nvoid main(){gl_Position=gl_Vertex;}");glCompileShader(vs);
  int p=glCreateProgram();glAttachShader(p,fs);glAttachShader(p,vs);glLinkProgram(p);
  if(glGetProgrami(p,GL_LINK_STATUS)==0) throw new RuntimeException(glGetProgramInfoLog(p));glUseProgram(p);
  int tex=glGenTextures();glBindTexture(GL_TEXTURE_2D,tex);glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA32F,1024,768,0,GL_RGBA,GL_FLOAT,(java.nio.ByteBuffer)null);
  int fb=glGenFramebuffers();glBindFramebuffer(GL_FRAMEBUFFER,fb);glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,tex,0);
  glUniform1i(glGetUniformLocation(p,"worldTime"),Integer.parseInt(args[2]));
  glUniform1i(glGetUniformLocation(p,"worldDay"),Integer.parseInt(args[3]));
  glUniform1f(glGetUniformLocation(p,"frameTimeCounter"),Float.parseFloat(args[5]));
  glUniform1i(glGetUniformLocation(p,"panorama"),Integer.parseInt(args[4]));
  if(args.length>6) {bindImage(p,"astraEndTransfer",args[6],1);bindImage(p,"astraEndFlow",args[7],2);}
  if(args.length>8) bindImage(p,"astraEndTransferMeta",args[8],4);
  if(args.length>11) glUniform3f(glGetUniformLocation(p,"previewLook"),
      Float.parseFloat(args[9]),Float.parseFloat(args[10]),Float.parseFloat(args[11]));
  if(args.length>12) glUniform1i(glGetUniformLocation(p,"previewForeground"),Integer.parseInt(args[12]));
  int pass=glGetUniformLocation(p,"offlinePass"), resolution=glGetUniformLocation(p,"previewResolution");
  if(pass>=0) {
   int sw=1024*3/4, sh=768*3/4;
   glActiveTexture(GL_TEXTURE3);int skyTex=glGenTextures();glBindTexture(GL_TEXTURE_2D,skyTex);
   glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA16F,sw,sh,0,GL_RGBA,GL_FLOAT,(java.nio.ByteBuffer)null);
   glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
   glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);
   int skyFb=glGenFramebuffers();glBindFramebuffer(GL_FRAMEBUFFER,skyFb);glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,skyTex,0);
   glUniform1i(pass,0);glUniform2f(resolution,sw,sh);glViewport(0,0,sw,sh);
   glBegin(GL_TRIANGLES);glVertex2f(-1,-1);glVertex2f(3,-1);glVertex2f(-1,3);glEnd();
   glBindFramebuffer(GL_FRAMEBUFFER,fb);glUniform1i(pass,1);glUniform1i(glGetUniformLocation(p,"offlineSky"),3);
   glUniform2f(resolution,1024,768);
  }
  glViewport(0,0,1024,768);glBegin(GL_TRIANGLES);glVertex2f(-1,-1);glVertex2f(3,-1);glVertex2f(-1,3);glEnd();glFinish();
  float[] data=new float[1024*768*4];glReadPixels(0,0,1024,768,GL_RGBA,GL_FLOAT,data);
  try(DataOutputStream out=new DataOutputStream(new BufferedOutputStream(new FileOutputStream(args[1])))) {for(float v:data)out.writeFloat(v);}
  glfwDestroyWindow(w);glfwTerminate();
 }
}
'''

def sample_bilinear(data,x,y):
    h,w=data.shape[:2]
    x=np.clip(x,0,w-1); y=np.clip(y,0,h-1)
    ix=np.floor(x).astype(int); iy=np.floor(y).astype(int)
    fx=(x-ix)[...,None]; fy=(y-iy)[...,None]
    a=data[iy,ix]*(1-fx)+data[iy,np.minimum(ix+1,w-1)]*fx
    b=data[np.minimum(iy+1,h-1),ix]*(1-fx)+data[np.minimum(iy+1,h-1),np.minimum(ix+1,w-1)]*fx
    return a*(1-fy)+b*fy

def end_bloom(pixels):
    # Same 13 taps, threshold, source ceiling and four End mip weights as GLSL.
    h,w=pixels.shape[:2]; ch,cw=h//4,w//4
    yy,xx=np.meshgrid((np.arange(ch)+0.5)*h/ch-0.5,(np.arange(cw)+0.5)*w/cw-0.5,indexing='ij')
    capture=np.zeros((ch,cw,3))
    taps=[(0,0,.125),(-1,-1,.125),(1,-1,.125),(-1,1,.125),(1,1,.125),(-2,0,.0625),(2,0,.0625),(0,-2,.0625),(0,2,.0625),(-2,-2,.03125),(2,-2,.03125),(-2,2,.03125),(2,2,.03125)]
    for dx,dy,weight in taps:
        c=sample_bilinear(pixels,xx+dx*2,yy+dy*2)
        brightness=c.max(axis=2,keepdims=True)
        soft=np.clip(brightness-1,0,1)**2/2.0001
        excess=np.minimum(np.maximum(soft,brightness-1.5),16)
        capture+=c*excess/np.maximum(brightness,1e-5)*weight
    yy,xx=np.meshgrid((np.arange(h)+.5)/h,(np.arange(w)+.5)/w,indexing='ij')
    result=np.zeros_like(pixels)
    for level,weight in enumerate([.50,.25,.15,.10]):
        result+=sample_bilinear(capture,xx*capture.shape[1]-.5,yy*capture.shape[0]-.5)*weight*.35
        if level<3:
            nh,nw=capture.shape[0]//2,capture.shape[1]//2
            capture=capture[:nh*2,:nw*2].reshape(nh,2,nw,2,3).mean(axis=(1,3))
    return result

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--seconds',type=float,default=0)
    parser.add_argument('--panorama',action='store_true')
    parser.add_argument('--output',default='qa/end-design/close.png')
    parser.add_argument('--width',type=int,default=1600)
    parser.add_argument('--height',type=int,default=900)
    parser.add_argument('--fov',type=float,default=62.0)
    parser.add_argument('--no-bloom',action='store_true')
    parser.add_argument('--view',choices=('blackhole','island','jet'),default='blackhole')
    parser.add_argument('--aim-offset',type=float,default=38.0,help='look offset along the spin axis for the jet view, in degrees')
    parser.add_argument('--foreground',action='store_true',help='show an analytic End island composition guide')
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[2]
    shader=root/'Astra/shaders/global/dimension'
    source='#include "/lib/pow.glsl"'
    source+=(shader/'end_blackhole.glsl').read_text(encoding='utf-8')
    source+='\n#include "/lib/end_surface.glsl"'
    import re as _re
    root_shaders=root/'Astra/shaders'
    for _ in range(64):
        m=_re.search(r'#include "([^"]+)"',source)
        if not m: break
        source=source[:m.start()]+(root_shaders/(m.group(1).lstrip('/'))).read_text(encoding='utf-8')+source[m.end():]
    else:
        raise RuntimeError('include expansion did not terminate')
    # The offline TU binds no colortex8, so the body cache would place every body at the
    # origin with zero radius and the entry segment would report a hit for every
    # lens-crossing ray. Use the analytic body path, and supply the one settings value
    # that path needs (lib/settings.glsl:106).
    assert source.count('#define ASTRA_END_BODY_CACHE')==1
    source=source.replace('#define ASTRA_END_BODY_CACHE','// offline: body cache off (no colortex8)')
    source='#define END_PRECESSION_MINUTES 36\n#define ASTRA_END_SKY_BUFFER\n'+source
    source='''#version 430 compatibility
uniform sampler2D noisetex;
uniform float frameTimeCounter;
const int noiseTextureResolution=256;
uniform int panorama;
uniform int offlinePass;
uniform vec2 previewResolution;
uniform sampler2D offlineSky;
uniform vec3 previewLook;
uniform int previewForeground;
'''+source+'''
// Preview-only geometry; surface response is shared with the game shaders.
const vec3 previewPillars[6]=vec3[6](vec3(20.0,-27.0,114.0),vec3(-29.0,-3.0,129.0),
 vec3(1.0,39.0,108.0),vec3(-49.0,-39.0,120.0),
 vec3(48.0,27.0,102.0),vec3(-9.0,-48.0,136.0));
bool preview_box(vec3 origin,vec3 ray,vec3 lo,vec3 hi,out float t,out vec3 normal) {
 vec3 safe=vec3(ray.x<0.0 ? -max(abs(ray.x),1e-6) : max(abs(ray.x),1e-6),
                ray.y<0.0 ? -max(abs(ray.y),1e-6) : max(abs(ray.y),1e-6),
                ray.z<0.0 ? -max(abs(ray.z),1e-6) : max(abs(ray.z),1e-6));
 vec3 entry=min((lo-origin)/safe,(hi-origin)/safe);
 vec3 leave=max((lo-origin)/safe,(hi-origin)/safe);
 t=max(entry.x,max(entry.y,entry.z));
 if(t<=0.0 || t>min(leave.x,min(leave.y,leave.z))) return false;
 normal=entry.x>=entry.y && entry.x>=entry.z ? vec3(-sign(safe.x),0,0)
       :entry.y>=entry.z ? vec3(0,-sign(safe.y),0) : vec3(0,0,-sign(safe.z));
 return true;
}
float preview_shadow(vec3 point) {
 for(int i=0;i<6;i++) {
  vec3 pillar=previewPillars[i]; float t; vec3 n;
  if(preview_box(point,end_light_direction(),vec3(pillar.x-3.0,70.0,pillar.y-3.0),
                 vec3(pillar.x+3.0,pillar.z,pillar.y+3.0),t,n)) return 0.0;
 }
 return 1.0;
}
vec4 preview_island(vec3 ray,float cone) {
 vec3 eye=vec3(70.0,80.0,0.0);
 float nearest=1e7; vec3 normal=vec3(0,1,0); bool obsidian=false;
 if(ray.y < -0.0001) {
  float t=(70.0-eye.y)/ray.y; vec3 p=eye+ray*t;
  if(t>0.0 && length(p.xz)<93.0) nearest=t;
 }
 for(int i=0;i<6;i++) {
  vec3 pillar=previewPillars[i]; float t; vec3 n;
  if(preview_box(eye,ray,vec3(pillar.x-3.0,70.0,pillar.y-3.0),
                 vec3(pillar.x+3.0,pillar.z,pillar.y+3.0),t,n) && t<nearest) {
   nearest=t; normal=n; obsidian=true;
  }
 }
 if(nearest>1e6) return vec4(0.0);
 vec3 p=eye+ray*nearest;
 float grain=fract(sin(dot(floor(p*12.0),vec3(127.1,311.7,59.3)))*43758.5453);
 grain=mix(grain,0.5,smoothstep(0.025,0.14,nearest*cone));
 vec3 albedo=obsidian ? vec3(0.008,0.007,0.017)*mix(0.45,2.5,grain)
                     : vec3(0.51,0.48,0.35)*mix(0.72,1.16,grain);
 float visibility=preview_shadow(p+normal*0.002);
 vec3 color=end_surface_diffuse(albedo,normal,visibility,0.0);
 if(dot(normal,end_light_direction())>-0.01) {
  float tone=dot(albedo,vec3(0.2126,0.7152,0.0722));
  float roughness=obsidian ? mix(0.39,0.23,clamp(tone*22.0,0.0,1.0)) : mix(0.86,0.62,tone);
  color+=end_surface_specular(end_surface_bevel(normal,p,nearest*cone),-ray,roughness,visibility,0.0);
 }
 return vec4(color,1.0);
}
void main(){
 vec2 uv=gl_FragCoord.xy/previewResolution;
 vec3 light=end_light_direction();
 vec3 ray;
 if(panorama==1){float a=(uv.x-.5)*END_TAU;float b=(uv.y-.5)*END_PI;ray=vec3(sin(a)*cos(b),sin(b),-cos(a)*cos(b));}
 else ray=normalize(end_basis(normalize(previewLook))*vec3((uv*2.0-1.0)*vec2(1.333333,1)*tan(radians(35.0)),1.0));
 float cone=max(length(dFdx(ray)),length(dFdy(ray)));
 end_sky_ray_cone=cone;
 vec3 starRay=end_lensed_background(ray);
 vec3 starDx=dFdx(starRay),starDy=dFdy(starRay);
 if(offlinePass==0) {
  vec3 color=vec3(0);astra_end_blackhole(color,ray,light);gl_FragColor=vec4(color,end_star_visibility);
 } else {
  vec4 sky=texture(offlineSky,uv);
  vec3 color=sky.rgb+end_crisp_photon_ring(ray,cone);
  if(sky.a>0.0) color+=end_starfield_filtered(starRay,cone,starDx,starDy)*sky.a;
  if(previewForeground>0) {vec4 terrain=preview_island(ray,cone);color=mix(color,terrain.rgb,terrain.a);}
  gl_FragColor=vec4(color,1.0);
 }
}
'''
    source=source.replace('vec2(1024,768)',f'vec2({args.width},{args.height})')
    source=source.replace('vec2(1.333333,1)',f'vec2({args.width/args.height:.9f},1)')
    source=source.replace('radians(35.0)',f'radians({args.fov*0.5:.9f})')
    if args.view=='island':
        look=np.array([-np.cos(np.deg2rad(12.0)),np.sin(np.deg2rad(12.0)),0.0])
    else:
        light=np.array([-np.cos(np.deg2rad(23.0)),np.sin(np.deg2rad(23.0)),0.0])
        offset=args.aim_offset if args.view=='jet' else 0.0
        right=np.cross(np.array([0.0,1.0,0.0]),light)
        right/=np.linalg.norm(right)
        up=np.cross(light,right)
        disc_axis=up*np.cos(np.deg2rad(18.0))+right*np.sin(np.deg2rad(18.0))
        look=light*np.cos(np.deg2rad(offset))+disc_axis*np.sin(np.deg2rad(offset))
        look/=np.linalg.norm(look)
    java=JAVA.replace('1024,768',f'{args.width},{args.height}').replace('1024*768',f'{args.width}*{args.height}')
    java=java.replace('1024*3/4',f'{args.width}*3/4').replace('768*3/4',f'{args.height}*3/4')
    cp=lwjgl_classpath(DEFAULT_MC_ROOT)
    out=root/args.output;out.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='astra-end-') as tmp:
        t=Path(tmp);(t/'EndPreview.java').write_text(java,encoding='utf-8');(t/'end.frag').write_text(source,encoding='utf-8')
        subprocess.run(['javac','-cp',cp,str(t/'EndPreview.java')],check=True)
        seconds=args.seconds
        subprocess.run(['java','-cp',cp+';'+str(t),'EndPreview',str(t/'end.frag'),str(t/'pixels.bin'),str(int(seconds%1200*20)),str(int(seconds//1200)),str(int(args.panorama)),str(seconds),str(root_shaders/'textures/astra-end-transfer.png'),str(root_shaders/'textures/astra-end-flow.png'),str(root_shaders/'textures/astra-end-transfer-meta.png'),str(look[0]),str(look[1]),str(look[2]),str(int(args.foreground))],check=True)
        pixels=np.fromfile(t/'pixels.bin',dtype='>f4').reshape(args.height,args.width,4)[::-1,:,:3]
    assert np.isfinite(pixels).all(), 'Non-finite radiance'
    np.save(out.with_suffix('.npy'),pixels)
    # Same Uchimura constants and sRGB transfer as Astra's default air display.
    x=np.maximum(pixels,0)
    if not args.no_bloom: x=x+end_bloom(x)
    m=0.22; l0=(1-m)*0.4; s0=m+l0; s1=s0; c2=1/(1-s1)
    toe=np.clip(x/m,0,1); w0=1-toe*toe*(3-2*toe)
    w2=(x>=s0).astype(float); w1=1-w0-w2
    mapped=m*np.power(x/m,1.33)*w0+x*w1+(1-(1-s1)*np.exp(-c2*(x-s0)))*w2
    display=np.where(mapped<=0.0031308,mapped*12.92,1.055*np.power(np.maximum(mapped,0),1/2.4)-0.055)
    Image.fromarray(np.uint8(np.clip(display*255,0,255))).save(out)
    print(f'{out} | max={pixels.max():.4f}, median={np.median(pixels):.6f}, finite=true')

if __name__=='__main__':main()
