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
        // This ray approaches the camera, then hits the visible floor. It starts
        // just above the floor: from y=+1 the crossing falls on a stride step so
        // coarse that the candidate has already left the bottom of the frustum.
        vec4 hit = water_raytrace(depthtex1, vec3(0,-1,-12), normalize(vec3(0,-1,1)),
                                  vec3(0,-1,0));
        gl_FragColor = vec4(hit.xy, hit.a, 1.0);
    } else if (probe == 5) {
        float d = uv.x * 40.0;
        vec3 c = vec3(0.7,0.8,0.9), source = vec3(0.2,0.3,0.4);
        vec3 split = water_medium(water_medium(c,d*0.3,source),d*0.7,source);
        gl_FragColor = vec4(abs(split-water_medium(c,d,source)),1);
    } else if (probe == 7 || probe == 8 || probe == 14 || probe == 15) {
        // Full astra_water on the sky-miss path: air side, background entirely sky.
        // 7/8 put the surface below the eye, 14/15 above it (the waterfall seen
        // against the sky); x.5 modes are 2 blocks away, the others 40.
        bool aboveEye = probe >= 14;
        float distance = (probe % 2) == 1 ? 2.0 : 40.0;
        vec3 pos = vec3(0.0, aboveEye ? 1.0 : -1.0, -distance);
        gl_FragColor = vec4(astra_water(vec3(0.0), 1.0, pos, pos, vec3(0,1,0), 0.045,
                                        1.0, true, false, vec3(0,1,0)).rgb, 1.0);
    } else if (probe >= 9 && probe <= 12) {
        // A/B of the two sky-miss fallback expressions on identical geometry. x
        // sweeps the camera distance 1..49 blocks. The mode picks which side of the
        // eye the surface sits on: below it, the refracted ray leaves the water
        // DOWNWARD and a miss means "no geometry in range"; above it, the ray leaves
        // UPWARD into real sky - the waterfall-against-the-sky case. Odd = superseded.
        bool aboveEye = probe >= 11;
        float distance = 1.0 + uv.x * 48.0;
        vec3 pos = vec3(0.0, aboveEye ? 1.0 : -1.0, -distance);
        vec3 normal = aboveEye ? vec3(0,-1,0) : vec3(0,1,0);
        vec3 transmittedWorld = normalize(refract(normalize(pos), normal, 1.0 / WATER_IOR));
        vec3 result;
        if ((probe % 2) == 1) {
            result = astra_water_segment(vec3(0.0), pos, pos + transmittedWorld * 96.0, 1.0);
        } else {
            float farField = clamp(-pos.z * (1.0 / 24.0), 0.0, 1.0);
            result = water_surface_medium(texture(colortex4, uv).rgb,
                                          mix(0.25, 23.0, farField), astra_water_incident(1.0));
        }
        gl_FragColor = vec4(result, 1.0);
    } else if (probe == 13) {
        // Fog alone, x swept over the same distances: what astra_apply_medium mixes
        // the water result into.
        float distance = 1.0 + uv.x * 48.0;
        vec4 fog = astra_fog(vec3(0.0, -1.0, -distance), 1.0);
        gl_FragColor = vec4(fog.rgb, fog.a);
    } else if (probe == 16 || probe == 21) {
        // The two analytic sky lookups considered for the fallback background, on the
        // shipped ramp and the below-eye geometry. Rejected in favour of the scene copy,
        // kept so the choice is measured: a sky model that disagrees with the rendered
        // sky shows up as a seam right where mix(straight, ...) hands over.
        float distance = 1.0 + uv.x * 48.0;
        vec3 pos = vec3(0.0, -1.0, -distance);
        vec3 transmittedWorld = normalize(refract(normalize(pos), vec3(0,1,0), 1.0 / WATER_IOR));
        vec3 background = probe == 16 ? astra_reflection_sky(transmittedWorld, 0.045)
                                      : astra_sky(transmittedWorld);
        float farField = clamp(-pos.z * (1.0 / 24.0), 0.0, 1.0);
        gl_FragColor = vec4(water_surface_medium(background, mix(0.25, 23.0, farField),
                                                astra_water_incident(1.0)), 1.0);
    } else if (probe == 17 || probe == 18) {
        // The absorption-depth helper alone. 17 is a vertical wall seen from air, with
        // x sweeping the camera-to-background distance; 18 is a top face with x sweeping
        // the water column. rgb is depth / 48 and alpha the raw depth.
        bool topFace = probe == 18;
        float distance = 1.0 + uv.x * 48.0;
        vec3 faceNormal = topFace ? vec3(0,1,0) : vec3(0,0,1);
        vec3 point = topFace ? vec3(0.0, -distance, -20.0) : vec3(0.0, -1.0, -distance);
        float depth = water_surface_absorption_depth(vec3(0.0), point, faceNormal);
        gl_FragColor = vec4(vec3(depth / 48.0), depth);
    } else if (probe == 19 || probe == 20) {
        // Colour A/B of the side-face fix on identical wall geometry: 19 uses the
        // unbounded dot product (the superseded behaviour), 20 the shipped helper.
        float distance = 1.0 + uv.x * 48.0;
        vec3 point = vec3(0.0, -1.0, -distance);
        vec3 faceNormal = vec3(0,0,1);
        float depth = (probe == 19) ? dot(vec3(0.0) - point, faceNormal)
                                    : water_surface_absorption_depth(vec3(0.0), point, faceNormal);
        gl_FragColor = vec4(water_surface_medium(vec3(0.5,0.5,0.45), depth,
                                                astra_water_incident(1.0)), 1.0);
    } else {
        vec3 viewRay = normalize(screen_view(vec3(uv, 0.5)));
        if (viewRay.y <= 0.02) {
            gl_FragColor = vec4(texture(colortex4,uv).rgb,1);
            return;
        }
        vec3 pos = viewRay * (2.0 / viewRay.y);
        WaterSurface wave = water_surface(pos,vec3(0,1,0),frameTimeCounter,true);
        gl_FragColor = astra_water(vec3(0),1,pos,pos,-wave.normal,
                                  wave.roughness,1.0,true,false,vec3(0,-1,0));
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
  // shaders.properties:214/218/219 compute these on the CPU. Unbound they read 0, and
  // BORDER_FOG's smoothstep(borderFogDistance-8, borderFogDistance, d) = 1 for every d,
  // so every air-side fragment came out as border fog instead of water.
  uf("borderFogDistance",far);
  uf("atmosphereFogCoefficient",(1.0f + 0.01f * Math.max(0.0f, far - 200.0f))
                                * (float) Math.pow(0.60f / far, 3));
  BufferedImage noise=ImageIO.read(Path.of(args[2]).toFile());float[] noiseData=new float[noise.getWidth()*noise.getHeight()*4];
  for(int y=0;y<noise.getHeight();y++)for(int x=0;x<noise.getWidth();x++){
   int c=noise.getRGB(x,y),i=(y*noise.getWidth()+x)*4;noiseData[i]=((c>>16)&255)/255f;
   noiseData[i+1]=((c>>8)&255)/255f;noiseData[i+2]=(c&255)/255f;noiseData[i+3]=1;}
  texture(2,GL_RGBA8,noise.getWidth(),noise.getHeight(),GL_RGBA,noiseData);u1("steadfastWaterNoise",2);
  int target=texture(3,GL_RGBA32F,W,H,GL_RGBA,(float[])null);
  int fb=glGenFramebuffers();glBindFramebuffer(GL_FRAMEBUFFER,fb);glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,target,0);
  glDrawBuffer(GL_COLOR_ATTACHMENT0);glReadBuffer(GL_COLOR_ATTACHMENT0);glViewport(0,0,W,H);
  for(int mode=0;mode<=21;mode++){
   float[] depth=new float[W*H],color=new float[W*H*4];
   for(int y=0;y<H;y++)for(int x=0;x<W;x++){
    float rx=((x+.5f)/W*2-1)/f,ry=((y+.5f)/H*2-1)/f;
    float z=-far;boolean solid=false;float r=.15f,g=.35f,bl=.7f;
    if(mode==2){z=x<W/2?-4:-12;solid=true;r=x<W/2?.9f:.1f;g=x<W/2?.85f:.2f;bl=x<W/2?.75f:.3f;}
    else if(ry<0 && mode<7){z=3/ry;solid=-z<far;boolean check=(((int)Math.floor(-z*rx)+(int)Math.floor(-z))&1)==0;
      r=check?.7f:.12f;g=check?.65f:.36f;bl=check?.45f:.2f;}
    else if(mode<7 && Math.abs(rx*18)<5 && ry*18>3){z=-18;solid=true;r=.12f;g=.42f;bl=.18f;}
    int q=y*W+x;depth[q]=solid?(a*z+b)/(-z)*.5f+.5f:1;color[q*4]=r;color[q*4+1]=g;color[q*4+2]=bl;color[q*4+3]=1;
   }
   int dt=texture(0,GL_R32F,W,H,GL_RED,depth),ct=texture(1,GL_RGBA8,W,H,GL_RGBA,color);u1("depthtex1",0);u1("colortex4",1);
   u1("probe",mode==6?3:mode);uf("frameTimeCounter",mode==6?2:0);
   u1("isEyeInWater",mode>=7?0:1);
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
                        str(OUT), str(shaders / "textures/steadfast-water-noise.png")], check=True)
    data = [struct.unpack("<" + "f"*(128*128*4), (OUT/f"{i}.f32").read_bytes()) for i in range(22)]
    sample = lambda mode,x,y: data[mode][(y*128+x)*4:(y*128+x)*4+4]
    spread = lambda mode: max(abs(data[mode][q+k]-sample(mode,64,64)[k])
                              for q in range(0,128*128*4,28) for k in range(3))
    # Modes 9..13 and 16..21 map x to the camera distance, so a column is one sample.
    sweep = lambda mode: {round(1.0 + 48.0*(x+0.5)/128.0, 1):
                          [round(v, 5) for v in sample(mode,x,64)]
                          for x in (0, 2, 7, 19, 41, 63, 126)}
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
        "air_sky_miss_near": sample(7,64,64),
        "air_sky_miss_near_spread": spread(7),
        "air_sky_miss_far": sample(8,64,64),
        "air_sky_miss_far_spread": spread(8),
        "waterfall_sky_miss_near": sample(15,64,64),
        "waterfall_sky_miss_far": sample(14,64,64),
        "miss_fallback_superseded": sweep(9),
        "miss_fallback_candidate": sweep(10),
        "miss_fallback_superseded_above_eye": sweep(11),
        "miss_fallback_candidate_above_eye": sweep(12),
        "air_fog_sweep": sweep(13),
        "miss_fallback_reflection_sky_background": sweep(16),
        "miss_fallback_air_sky_background": sweep(21),
        "absorption_depth_wall": sweep(17),
        "absorption_depth_top_face": sweep(18),
        "wall_absorption_unbounded": sweep(19),
        "wall_absorption_bounded": sweep(20),
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
    # P1-17, side face: a water block shows a side face only where its neighbour along
    # that normal is not water, so at most one block of water lies along it. A top face
    # keeps its real, unbounded column.
    assert all(v[3] <= 1.0 + 1e-4 for v in result["absorption_depth_wall"].values())
    assert result["absorption_depth_top_face"][48.4][3] > 47.0
    assert (result["wall_absorption_bounded"][48.4][0]
            > 3.0 * result["wall_absorption_unbounded"][48.4][0])
    # P1-17, sky miss: the superseded fallback carried no background and its depth came
    # from the ray's own angle, so it was one constant at every distance. The shipped one
    # releases the near field, never drops below the old value, and blue-shifts with depth.
    superseded, shipped = (result["miss_fallback_superseded"],
                           result["miss_fallback_candidate"])
    assert max(max(abs(a - b) for a, b in zip(v, superseded[1.2]))
               for v in superseded.values()) < 1e-4
    distances = sorted(superseded)
    assert sum(shipped[1.2][:3]) > 2.0 * sum(superseded[1.2][:3])
    assert all(shipped[k][i] >= shipped[l][i] - 1e-5
               for k, l in zip(distances, distances[1:]) for i in range(3))
    assert all(shipped[k][i] >= superseded[k][i] - 1e-5
               for k in distances for i in range(3))
    assert shipped[48.4][0] < shipped[48.4][1] < shipped[48.4][2]
    # Shipped-file coverage: modes 7/8/14/15 run the real astra_water(). The first two
    # asserts below pass on the superseded fallback too (HEAD: 7.8x near/far, still
    # blue-shifted), so they only pin the released shape. The last one is the guard:
    # the old fallback traced 96 blocks along the ray, so a waterfall miss and a
    # horizontal miss at the same camera distance differed an order of magnitude in
    # g/b; the ramp depends on distance alone, so they now agree. Reverting only the
    # fallback block in program/water.glsl trips it and nothing else here.
    near, far = result["air_sky_miss_near"], result["air_sky_miss_far"]
    assert sum(near[:3]) > 4.0 * sum(far[:3])
    assert far[0] < far[1] < far[2]
    assert all(abs(w - n) < 1e-3
               for w, n in zip(result["waterfall_sky_miss_near"], near))

if __name__ == "__main__":
    main()
