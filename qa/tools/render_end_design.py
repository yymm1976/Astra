"""Render the actual End GLSL with LWJGL in a hidden window, without Minecraft."""
from pathlib import Path
import argparse, subprocess, tempfile
import numpy as np
from PIL import Image
from compile_glsl import lwjgl_classpath, DEFAULT_MC_ROOT

JAVA = r'''
import java.nio.file.*;
import java.io.*;
import static org.lwjgl.glfw.GLFW.*;
import org.lwjgl.opengl.GL;
import static org.lwjgl.opengl.GL11.*;
import static org.lwjgl.opengl.GL20.*;
import static org.lwjgl.opengl.GL30.*;
public class EndPreview {
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
  glUniform1i(glGetUniformLocation(p,"panorama"),Integer.parseInt(args[4]));
  glViewport(0,0,1024,768);glBegin(GL_TRIANGLES);glVertex2f(-1,-1);glVertex2f(3,-1);glVertex2f(-1,3);glEnd();glFinish();
  float[] data=new float[1024*768*4];glReadPixels(0,0,1024,768,GL_RGBA,GL_FLOAT,data);
  try(DataOutputStream out=new DataOutputStream(new BufferedOutputStream(new FileOutputStream(args[1])))) {for(float v:data)out.writeFloat(v);}
  glfwDestroyWindow(w);glfwTerminate();
 }
}
'''

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--seconds',type=float,default=0)
    parser.add_argument('--panorama',action='store_true')
    parser.add_argument('--output',default='qa/end-design/close.png')
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[2]
    shader=root/'Astra/shaders/global/dimension'
    source='#include "/lib/pow.glsl"'
    source+=(shader/'end_blackhole.glsl').read_text(encoding='utf-8')
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
    source='#define END_PRECESSION_MINUTES 36'+chr(10)+source
    source='''#version 430 compatibility
uniform sampler2D noisetex;
uniform float frameTimeCounter;
const int noiseTextureResolution=256;
#define END_NEBULA
uniform int panorama;
'''+source+'''
void main(){
 vec2 uv=gl_FragCoord.xy/vec2(1024,768);
 vec3 light=normalize(vec3(0.0,0.35,-1.0));
 vec3 ray;
 if(panorama==1){float a=(uv.x-.5)*END_TAU;float b=(uv.y-.5)*END_PI;ray=vec3(sin(a)*cos(b),sin(b),-cos(a)*cos(b));}
 else ray=normalize(end_basis(light)*vec3((uv*2.0-1.0)*vec2(1.333333,1)*tan(radians(35.0)),1.0));
 vec3 color=vec3(0);astra_end_blackhole(color,ray,light);gl_FragColor=vec4(color,1);
}
'''
    cp=lwjgl_classpath(DEFAULT_MC_ROOT)
    out=root/args.output;out.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='astra-end-') as tmp:
        t=Path(tmp);(t/'EndPreview.java').write_text(JAVA,encoding='utf-8');(t/'end.frag').write_text(source,encoding='utf-8')
        subprocess.run(['javac','-cp',cp,str(t/'EndPreview.java')],check=True)
        seconds=args.seconds
        subprocess.run(['java','-cp',cp+';'+str(t),'EndPreview',str(t/'end.frag'),str(t/'pixels.bin'),str(int(seconds%1200*20)),str(int(seconds//1200)),str(int(args.panorama))],check=True)
        pixels=np.fromfile(t/'pixels.bin',dtype='>f4').reshape(768,1024,4)[::-1,:,:3]
    assert np.isfinite(pixels).all(), 'Non-finite radiance'
    np.save(out.with_suffix('.npy'),pixels)
    display=np.power(np.maximum(pixels,0)/(1+np.maximum(pixels,0)),1/2.2)
    Image.fromarray(np.uint8(np.clip(display*255,0,255))).save(out)
    print(f'{out} | max={pixels.max():.4f}, median={np.median(pixels):.6f}, finite=true')

if __name__=='__main__':main()
