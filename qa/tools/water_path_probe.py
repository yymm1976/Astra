#!/usr/bin/env python3
"""Render Astra's actual water functions in a hidden GL context, with known geometry.

This isolates optical/edge behaviour; it does not reproduce Iris or the user's world.
No diagnostic define or shader is installed into the pack or Minecraft instance.
"""
from pathlib import Path
import json
import math
import struct
import subprocess
import tempfile

from compile_glsl import Expander, parse_profiles, lwjgl_classpath, DEFAULT_MC_ROOT

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "qa" / "water-path-followup"

FRAGMENT = '''#version 400 compatibility
#include "/program/scene.glsl"
#include "/program/water.glsl"
#include "/global/post/bloom.glsl"
uniform int probe;
void main() {
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    if (probe == 0) {
        bool tir;
        float f = water_fresnel(uv.x, WATER_IOR, tir);
        gl_FragColor = vec4(f, float(tir), 1.0-f, 1.0);
    } else if (probe == 1) {
        gl_FragColor = vec4(bloom_prefilter(vec3(uv.x * 2.0)), 1.0);
    } else if (probe == 2) {
        vec3 c;
        float valid = water_sample_path(uv + vec2(0.4/viewWidth,0), vec3(0,0,-2), vec3(0,0,1),
                                       false, true, 0.0, 1.0, c);
        gl_FragColor = vec4(c, valid);
    } else if (probe == 4) {
        // This ray approaches the camera, then hits the visible floor.
        vec4 hit = water_raytrace(depthtex1, vec3(0,1,-12), normalize(vec3(0,-1,1)), 0.045);
        gl_FragColor = vec4(hit.xy, hit.a, 1.0);
    } else if (probe == 5) {
        float d = uv.x * 40.0;
        vec3 c = vec3(0.7,0.8,0.9), source = vec3(0.2,0.3,0.4);
        vec3 split = water_medium(water_medium(c,d*0.3,source),d*0.7,source);
        gl_FragColor = vec4(abs(split-water_medium(c,d,source)),1);
    } else {
        vec3 viewRay = normalize(screen_view(vec3(uv, 0.5)));
        if (viewRay.y <= 0.02) {
            gl_FragColor = vec4(texture(colortex4,uv).rgb,1);
            return;
        }
        vec3 pos = viewRay * (2.0 / viewRay.y);
        WaterSurface wave = water_surface(pos,vec3(0,1,0),frameTimeCounter);
        gl_FragColor = astra_water(vec3(0),1,pos,pos,-wave.normal,
                                  wave.roughness,1.0,true,vec3(0,-1,0));
    }
}
'''

JAVA = r'''
import java.nio.file.*;
import java.nio.*;
import java.awt.image.BufferedImage;
import javax.imageio.ImageIO;
import static org.lwjgl.glfw.GLFW.*;
import org.lwjgl.opengl.GL;
import static org.lwjgl.opengl.GL33.*;
public class WaterProbe {
 static final int W=128,H=128;
 static int program;
 static void u1(String n,int v){glUniform1i(glGetUniformLocation(program,n),v);}
 static void uf(String n,float v){glUniform1f(glGetUniformLocation(program,n),v);}
 static void u3(String n,float x,float y,float z){glUniform3f(glGetUniformLocation(program,n),x,y,z);}
 static void matrix(String n,float[] v){glUniformMatrix4fv(glGetUniformLocation(program,n),false,v);}
 static int shader(int type,String src){int s=glCreateShader(type);glShaderSource(s,src);glCompileShader(s);
  if(glGetShaderi(s,GL_COMPILE_STATUS)==0)throw new RuntimeException(glGetShaderInfoLog(s));return s;}
 static int texture(int unit,int format,int w,int h,int components,float[] values){
  glActiveTexture(GL_TEXTURE0+unit);int t=glGenTextures();glBindTexture(GL_TEXTURE_2D,t);
  glTexImage2D(GL_TEXTURE_2D,0,format,w,h,0,components,GL_FLOAT,values);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_REPEAT);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_REPEAT);return t;}
 public static void main(String[] args)throws Exception{
  if(!glfwInit())throw new RuntimeException("glfwInit");
  glfwWindowHint(GLFW_VISIBLE,GLFW_FALSE);glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR,4);
  glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR,0);glfwWindowHint(GLFW_OPENGL_PROFILE,GLFW_OPENGL_COMPAT_PROFILE);
  long window=glfwCreateWindow(W,H,"Astra optical probe",0,0);glfwMakeContextCurrent(window);GL.createCapabilities();
  program=glCreateProgram();glAttachShader(program,shader(GL_VERTEX_SHADER,"#version 400 compatibility\nvoid main(){gl_Position=gl_Vertex;}"));
  glAttachShader(program,shader(GL_FRAGMENT_SHADER,Files.readString(Path.of(args[0]))));glLinkProgram(program);
  if(glGetProgrami(program,GL_LINK_STATUS)==0)throw new RuntimeException(glGetProgramInfoLog(program));glUseProgram(program);
  float f=1.428148f,n=0.05f,far=256f,a=-(far+n)/(far-n),b=-2*far*n/(far-n);
  float[] p={f,0,0,0,0,f,0,0,0,0,a,-1,0,0,b,0};
  float[] inv={1/f,0,0,0,0,1/f,0,0,0,0,0,1/b,0,0,-1,a/b};
  float[] identity={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1};
  matrix("gbufferProjection",p);matrix("gbufferProjectionInverse",inv);
  matrix("gbufferModelView",identity);matrix("gbufferModelViewInverse",identity);
  uf("viewWidth",W);uf("viewHeight",H);uf("sunProgress",1);uf("skyVisibilityDay",1);
  uf("far",far);u3("worldSunVector",0,1,0);u3("sunPosition",0,100,0);
  glUniform2i(glGetUniformLocation(program,"eyeBrightnessSmooth"),0,240);u1("isEyeInWater",1);
  BufferedImage noise=ImageIO.read(Path.of(args[2]).toFile());float[] noiseData=new float[noise.getWidth()*noise.getHeight()*4];
  for(int y=0;y<noise.getHeight();y++)for(int x=0;x<noise.getWidth();x++){
   int c=noise.getRGB(x,y),i=(y*noise.getWidth()+x)*4;noiseData[i]=((c>>16)&255)/255f;
   noiseData[i+1]=((c>>8)&255)/255f;noiseData[i+2]=(c&255)/255f;noiseData[i+3]=1;}
  texture(2,GL_RGBA8,noise.getWidth(),noise.getHeight(),GL_RGBA,noiseData);u1("noisetex",2);
  int target=texture(3,GL_RGBA32F,W,H,GL_RGBA,(float[])null);
  int fb=glGenFramebuffers();glBindFramebuffer(GL_FRAMEBUFFER,fb);glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,target,0);
  glDrawBuffer(GL_COLOR_ATTACHMENT0);glReadBuffer(GL_COLOR_ATTACHMENT0);glViewport(0,0,W,H);
  for(int mode=0;mode<=6;mode++){
   float[] depth=new float[W*H],color=new float[W*H*4];
   for(int y=0;y<H;y++)for(int x=0;x<W;x++){
    float rx=((x+.5f)/W*2-1)/f,ry=((y+.5f)/H*2-1)/f;
    float z=-far;boolean solid=false;float r=.15f,g=.35f,bl=.7f;
    if(mode==2){z=x<W/2?-4:-12;solid=true;r=x<W/2?.9f:.1f;g=x<W/2?.85f:.2f;bl=x<W/2?.75f:.3f;}
    else if(ry<0){z=3/ry;solid=-z<far;boolean check=(((int)Math.floor(-z*rx)+(int)Math.floor(-z))&1)==0;
      r=check?.7f:.12f;g=check?.65f:.36f;bl=check?.45f:.2f;}
    else if(Math.abs(rx*18)<5 && ry*18>3){z=-18;solid=true;r=.12f;g=.42f;bl=.18f;}
    int q=y*W+x;depth[q]=solid?(a*z+b)/(-z)*.5f+.5f:1;color[q*4]=r;color[q*4+1]=g;color[q*4+2]=bl;color[q*4+3]=1;
   }
   int dt=texture(0,GL_R32F,W,H,GL_RED,depth),ct=texture(1,GL_RGBA8,W,H,GL_RGBA,color);u1("depthtex1",0);u1("colortex4",1);
   u1("probe",mode==6?3:mode);uf("frameTimeCounter",mode==6?2:0);
   glBegin(GL_TRIANGLES);glVertex2f(-1,-1);glVertex2f(1,-1);glVertex2f(1,1);glVertex2f(-1,-1);glVertex2f(1,1);glVertex2f(-1,1);glEnd();
   float[] result=new float[W*H*4];glReadPixels(0,0,W,H,GL_RGBA,GL_FLOAT,result);
   ByteBuffer bytes=ByteBuffer.allocate(result.length*4).order(ByteOrder.LITTLE_ENDIAN);for(float v:result)bytes.putFloat(v);
   Files.write(Path.of(args[1],mode+".f32"),bytes.array());BufferedImage img=new BufferedImage(W,H,BufferedImage.TYPE_INT_RGB);
   for(int y=0;y<H;y++)for(int x=0;x<W;x++){int q=(y*W+x)*4;int c=0;for(int k=0;k<3;k++)c=(c<<8)|(int)(255*Math.max(0,Math.min(1,result[q+k])));img.setRGB(x,H-1-y,c);}
   ImageIO.write(img,"png",Path.of(args[1],mode+".png").toFile());glDeleteTextures(dt);glDeleteTextures(ct);
  }
  System.out.println("Renderer: "+glGetString(GL_RENDERER));glfwDestroyWindow(window);glfwTerminate();
 }
}
'''

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    shaders = ROOT / "Astra" / "shaders"
    profile = parse_profiles(shaders / "shaders.properties")["BALANCED"]
    profile.update(SHADOWS=None, UNDERWATER_LIGHT_SHAFTS=None)
    with tempfile.TemporaryDirectory(prefix="astra-water-probe-") as td:
        temp = Path(td)
        fragment = temp / "probe.fsh"
        fragment.write_text(FRAGMENT, encoding="utf-8")
        fragment.write_text(Expander(shaders, profile).expand(fragment, root=True), encoding="utf-8")
        java = temp / "WaterProbe.java"
        java.write_text(JAVA, encoding="utf-8")
        cp = lwjgl_classpath(DEFAULT_MC_ROOT)
        subprocess.run(["javac", "-cp", cp, str(java)], check=True)
        subprocess.run(["java", "-cp", cp + ";" + str(temp), "WaterProbe", str(fragment),
                        str(OUT), str(shaders / "textures/noise.png")], check=True)
    data = [struct.unpack("<" + "f"*(128*128*4), (OUT/f"{i}.f32").read_bytes()) for i in range(7)]
    sample = lambda mode,x,y: data[mode][(y*128+x)*4:(y*128+x)*4+4]
    result = {
        "scope": "Actual GLSL functions; synthetic depth/colour; no Iris injection or game-world visibility",
        "finite": all(math.isfinite(x) for frame in data for x in frame),
        "tir_grazing": sample(0,0,64),
        "fresnel_near_normal": sample(0,127,64),
        "bloom_max_below_white": max(sample(1,x,64)[0] for x in range(64)),
        "bloom_above_white": sample(1,127,64)[0],
        "sand_edge_near": sample(2,63,64),
        "sand_edge_far": sample(2,64,64),
        "towards_camera_reflection": sample(4,64,64),
        "medium_split_max_error": max(abs(v) for i,v in enumerate(data[5]) if i%4<3),
        "underside_temporal_mean_difference": sum(abs(data[3][(y*128+x)*4+k]-data[6][(y*128+x)*4+k])
            for y in range(72,128) for x in range(128) for k in range(3))/(56*128*3),
    }
    (OUT / "results.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))
    assert result["finite"]
    assert result["tir_grazing"][0] == 1
    assert 0.019 < result["fresnel_near_normal"][0] < 0.022
    assert result["bloom_max_below_white"] == 0
    assert result["bloom_above_white"] > 0
    assert result["towards_camera_reflection"][2] > 0
    assert result["medium_split_max_error"] < 1e-5
    assert result["underside_temporal_mean_difference"] > 1e-4

if __name__ == "__main__":
    main()
