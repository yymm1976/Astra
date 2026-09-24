#!/usr/bin/env python3
"""Execute shipped GLSL helpers on synthetic inputs. No Minecraft scene is rendered.

The functions are expanded from Astra on every run; no copied Python shading model.
All temporary sources, binaries and readbacks stay in a temporary directory.
"""
from pathlib import Path
import subprocess
import tempfile
import numpy as np
from compile_glsl import Expander, DEFAULT_MC_ROOT, lwjgl_classpath

ROOT = Path(__file__).resolve().parents[2]
SHADERS = ROOT / 'Astra/shaders'
SIZE = 256
JAVA = r'''
import java.nio.file.*;
import java.io.*;
import java.nio.*;
import static org.lwjgl.glfw.GLFW.*;
import org.lwjgl.opengl.GL;
import static org.lwjgl.opengl.GL11.*;
import static org.lwjgl.opengl.GL13.*;
import static org.lwjgl.opengl.GL14.*;
import static org.lwjgl.opengl.GL20.*;
import static org.lwjgl.opengl.GL30.*;
public class LiveField {
 static int shader(int kind,String source) {
  int id=glCreateShader(kind); glShaderSource(id,source); glCompileShader(id);
  if(glGetShaderi(id,GL_COMPILE_STATUS)==0) throw new RuntimeException(glGetShaderInfoLog(id));
  return id;
 }
 public static void main(String[] args) throws Exception {
  if(!glfwInit()) throw new RuntimeException("GLFW initialization failed");
  glfwWindowHint(GLFW_VISIBLE,GLFW_FALSE);
  glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR,4); glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR,0);
  glfwWindowHint(GLFW_OPENGL_PROFILE,GLFW_OPENGL_COMPAT_PROFILE);
  long window=glfwCreateWindow(256,256,"GLSL field",0,0);
  if(window==0) throw new RuntimeException("OpenGL context unavailable");
  glfwMakeContextCurrent(window); GL.createCapabilities();
  int program=glCreateProgram();
  glAttachShader(program,shader(GL_VERTEX_SHADER,"#version 400 compatibility\nvoid main(){gl_Position=gl_Vertex;}"));
  glAttachShader(program,shader(GL_FRAGMENT_SHADER,Files.readString(Path.of(args[0]))));
  glLinkProgram(program);
  if(glGetProgrami(program,GL_LINK_STATUS)==0) throw new RuntimeException(glGetProgramInfoLog(program));
  glUseProgram(program);
  int tex=glGenTextures(); glBindTexture(GL_TEXTURE_2D,tex);
  glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA32F,256,256,0,GL_RGBA,GL_FLOAT,(java.nio.ByteBuffer)null);
  int fb=glGenFramebuffers(); glBindFramebuffer(GL_FRAMEBUFFER,fb);
  glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,tex,0);
  if(glCheckFramebufferStatus(GL_FRAMEBUFFER)!=GL_FRAMEBUFFER_COMPLETE) throw new RuntimeException("Framebuffer");
  // Optional synthetic mixed water/glass/opaque shadow footprint.
  for(int channel=0;channel<3;channel++) {
   String name=channel<2 ? "shadowtex"+channel : "shadowcolor0";
   int location=glGetUniformLocation(program,name);
   if(location<0) continue;
   boolean depth=channel<2;
   java.nio.FloatBuffer pixels=org.lwjgl.BufferUtils.createFloatBuffer(8*8*(depth?1:4));
   for(int y=0;y<8;y++) for(int x=0;x<8;x++) {
    int cell=(x+2*y)%3;
    if(depth) pixels.put(channel==0 ? (cell==0?0.8f:0.3f) : (cell==2?0.3f:0.8f));
    else { pixels.put(cell==1?0.5f:1.0f); pixels.put(cell==1?0.1f:0.9f);
           pixels.put(cell==1?0.6f:0.1f); pixels.put(cell==1?0.9f:0.25f); }
   }
   pixels.flip(); glActiveTexture(GL_TEXTURE0+channel+1);
   int input=glGenTextures(); glBindTexture(GL_TEXTURE_2D,input);
   glTexImage2D(GL_TEXTURE_2D,0,depth?GL_DEPTH_COMPONENT32F:GL_RGBA32F,8,8,0,depth?GL_DEPTH_COMPONENT:GL_RGBA,GL_FLOAT,pixels);
   glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);
   glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
   glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);
   glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);
   if(depth && args[3].equals("1")) {
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_COMPARE_MODE,GL_COMPARE_REF_TO_TEXTURE);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_COMPARE_FUNC,GL_LEQUAL);
   }
   glUniform1i(location,channel+1);
  }
  if(args.length > 4) {
   byte[] bytes=Files.readAllBytes(Path.of(args[4]));
   ByteBuffer pixels=org.lwjgl.BufferUtils.createByteBuffer(bytes.length);
   pixels.put(bytes).flip();
   glActiveTexture(GL_TEXTURE4);
   int input=glGenTextures(); glBindTexture(GL_TEXTURE_2D,input);
   glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA32F,Integer.parseInt(args[5]),Integer.parseInt(args[6]),0,GL_RGBA,GL_FLOAT,pixels);
   glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);
   glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
   glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);
   glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);
   glUniform1i(glGetUniformLocation(program,"probeTexture"),4);
  }
  glViewport(0,0,256,256);
  int count=Integer.parseInt(args[2]);
  try(DataOutputStream out=new DataOutputStream(new BufferedOutputStream(new FileOutputStream(args[1])))) {
   for(int mode=0;mode<count;mode++) {
    glUniform1i(glGetUniformLocation(program,"probe"),mode);
    glUniform1i(glGetUniformLocation(program,"isEyeInWater"),mode%2);
    glUniform1f(glGetUniformLocation(program,"frameTimeCounter"),mode*12.3f);
    glBegin(GL_TRIANGLES); glVertex2f(-1,-1); glVertex2f(3,-1); glVertex2f(-1,3); glEnd();
    float[] pixels=new float[256*256*4]; glReadPixels(0,0,256,256,GL_RGBA,GL_FLOAT,pixels);
    for(float v:pixels) out.writeFloat(v);
   }
  }
  glfwDestroyWindow(window); glfwTerminate();
 }
}
'''

def render(fragment, count, options=None, texture_data=None):
    with tempfile.TemporaryDirectory(prefix='astra-live-field-') as tmp:
        folder=Path(tmp)
        entry=folder/'entry.fsh'
        entry.write_text(fragment,encoding='utf-8')
        expander=Expander(SHADERS,options or {})
        source=folder/'expanded.fsh'
        source.write_text(expander.expand(entry,root=True),encoding='utf-8')
        (folder/'LiveField.java').write_text(JAVA,encoding='utf-8')
        cp=lwjgl_classpath(DEFAULT_MC_ROOT)
        try:
            subprocess.run(['javac','-cp',cp,str(folder/'LiveField.java')],check=True,capture_output=True)
            hardware=str((options or {}).get('SHADOW_FILTER_MODE','0'))
            fixture_args=[]
            if texture_data is not None:
                texture_data=np.asarray(texture_data,dtype=np.float32)
                assert texture_data.ndim==3 and texture_data.shape[2]==4
                texture_data.tofile(folder/'texture.bin')
                fixture_args=[str(folder/'texture.bin'),str(texture_data.shape[1]),str(texture_data.shape[0])]
            subprocess.run(['java','-cp',cp+';'+str(folder),'LiveField',str(source),str(folder/'readback.bin'),str(count),hardware]+fixture_args,
                           cwd=folder,check=True,capture_output=True)
        except subprocess.CalledProcessError as exc:
            raise RuntimeError(exc.stderr.decode('utf-8','replace')) from exc
        return np.fromfile(folder/'readback.bin',dtype='>f4').astype('float64').reshape(count,SIZE,SIZE,4)

def require(checks):
    for name, okay in checks.items():
        print(f'{"PASS" if okay else "FAIL"}: {name}')
    return 0 if all(checks.values()) else 1

def expand_includes(source, shader_root=SHADERS):
    with tempfile.TemporaryDirectory(prefix='astra-include-') as tmp:
        entry=Path(tmp)/'entry.glsl'
        entry.write_text(source,encoding='utf-8')
        return Expander(shader_root,{}).expand(entry)
