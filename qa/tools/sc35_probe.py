#!/usr/bin/env python3
"""SC-35 coordinate/artifact probe: runs Astra's REAL GLSL in a hidden GL context.

Isolates the four P0 suspects with synthetic-but-known inputs:
  mode 0  held-light ball under a render-origin translation T (held_light_strength)
  mode 1  wave-field world anchoring when camera+T move (water_surface normals)
  mode 2  caustics magnitude histogram over a world tile (caustics_pattern)
  mode 3  shoreline transmission band through astra_water at pitch -20 deg
  mode 4  same shoreline at pitch -42 deg

Nothing is installed into the pack or the Minecraft instance. Re-run after a
source fix: modes 0/1/3/4 must change (ball re-centres, waves re-anchor, the
shore band must shrink), mode 2 reports the pre/post caustics cap directly.
"""
from pathlib import Path
import json
import math
import struct
import subprocess
import tempfile

from compile_glsl import Expander, parse_profiles, lwjgl_classpath, DEFAULT_MC_ROOT

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "qa" / "sc35-probe"

FRAGMENT = '''#version 400 compatibility
#include "/program/scene.glsl"
#include "/global/water/caustics.glsl"
#include "/program/water.glsl"
uniform int probe;
uniform vec3 worldShift;   // probe 1: compare identical world points across cameras
uniform float pitchCos;    // probes 3/4: camera pitch (rotation about +x)
uniform float pitchSin;

// Analytic shoreline heightfield, camera-relative axes (y up).
// Flat riverbed at -3.4, gentle gravel bank rising through the water plane (-1.6)
// up to -0.8, so refraction hits land 0..0.8 blocks above the interface and the
// SC-35 soft acceptance band is exercised on screen.
float shoreHeight(float x, float z) {
    float bank = smoothstep(2.0, 14.0, -z + x * 0.15);
    return -3.4 + 2.6 * bank;
}
vec3 shoreAlbedo(float x, float z) {
    float pebble = 0.82 + 0.18 * sin(x * 7.1) * sin(z * 5.3);
    return vec3(0.62, 0.55, 0.44) * pebble;
}

void main() {
    vec2 ndc = vec2((gl_FragCoord.x / viewWidth) * 2.0 - 1.0,
                    (gl_FragCoord.y / viewHeight) * 2.0 - 1.0);
    if (probe == 0) {
        // Ground plane 1.7 below the eye; playerPos exactly as lit.fsh computes it.
        float f = 1.428148;
        vec3 rayDir = normalize(vec3(ndc.x / f, ndc.y / f, -1.0));
        vec3 viewPos = rayDir * (-1.7 / min(rayDir.y, -1e-4));
        vec3 playerPos = view_camera_relative(viewPos);
        vec3 blocklight = block_lighting(1.0, 0.0, held_light_strength(1.0, playerPos), 0.75, 1.0);
        gl_FragColor = vec4(blocklight, 1.0);
        return;
    }
    if (probe == 1) {
        // Fixed true camera-relative tile ahead of the camera; worldShift re-centres
        // the tile so both camera states sample the SAME world points. viewPos in
        // lit.fsh comes from the GAME model-view matrix (identity rotation here),
        // NOT from camera_relative_view - a round trip would cancel the render
        // origin translation this probe is meant to expose.
        vec3 truePos = vec3(ndc.x * 8.0, 0.0, -10.0 + ndc.y * 6.0) - worldShift;
        vec3 playerPos = view_camera_relative(truePos);
        WaterSurface waves = water_surface(playerPos + cameraPosition, vec3(0.0, 1.0, 0.0), 1.5);
        gl_FragColor = vec4(waves.normal.x * 8.0 + 0.5, waves.normal.z * 8.0 + 0.5, waves.roughness, 1.0);
        return;
    }
    if (probe == 2) {
        vec3 worldPos = vec3(200.0 + (gl_FragCoord.x / viewWidth) * 16.0, 60.0,
                             300.0 + (gl_FragCoord.y / viewHeight) * 16.0);
        float pattern = caustics_pattern(worldPos, 3.0, 0.01);
        gl_FragColor = vec4(pattern, pattern, pattern, 1.0);
        return;
    }
    // --- probes 3/4: full interface path across a shoreline ---
    float f = 1.428148;
    vec3 rayView = normalize(vec3(ndc.x / f, ndc.y / f, -1.0));
    mat3 pitchInv = mat3(1.0, 0.0, 0.0,
                         0.0, pitchCos, pitchSin,
                         0.0, -pitchSin, pitchCos);
    vec3 rayWorld = pitchInv * rayView;               // camera-relative world axes
    // Intersect the water plane (camera-relative y = -1.6) and the shore heightfield.
    float tWater = rayWorld.y < -1e-5 ? (-1.6 / rayWorld.y) : 1e9;
    float tHit = 1e9;
    float t = 0.0;
    for (int i = 0; i < 96; ++i) {
        t += 0.25;
        vec3 p = rayWorld * t;
        if (p.y <= shoreHeight(p.x, p.z)) { tHit = t - 0.125; break; }
        if (t > 160.0) break;
    }
    if (tHit < tWater) {
        // Opaque shore occludes the interface: emit the raw gravel like the opaque pass.
        vec3 p = rayWorld * tHit;
        gl_FragColor = vec4(shoreAlbedo(p.x, p.z), 1.0);
        return;
    }
    if (tWater > 200.0) {
        gl_FragColor = vec4(astra_sky(rayWorld), 1.0);
        return;
    }
    vec3 truePos = rayWorld * tWater;                 // interface, camera-relative
    vec3 viewPos = camera_relative_view(truePos);
    vec3 playerPos = view_camera_relative(viewPos);
    WaterSurface waves = water_surface(playerPos + cameraPosition, vec3(0.0, 1.0, 0.0), 1.0);
    gl_FragColor = astra_water(vec3(0.0), 1.0, playerPos, viewPos, waves.normal,
                               waves.roughness, 1.0, true, vec3(0.0, 1.0, 0.0));
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
public class SC35Probe {
 static final int W=192,H=192;
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
 static float[] matTranslate(float x,float y,float z){return new float[]{1,0,0,0,0,1,0,0,0,0,1,0,x,y,z,1};}
 static float shoreHeight(float x,float z){float b=(float)Math.min(1,Math.max(0,(-z+x*0.15f-2.0f)/12.0f));
  b=b*b*(3-2*b);return -3.4f+3.2f*b;}
 public static void main(String[] args)throws Exception{
  if(!glfwInit())throw new RuntimeException("glfwInit");
  glfwWindowHint(GLFW_VISIBLE,GLFW_FALSE);glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR,4);
  glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR,0);glfwWindowHint(GLFW_OPENGL_PROFILE,GLFW_OPENGL_COMPAT_PROFILE);
  long window=glfwCreateWindow(W,H,"Astra SC35 probe",0,0);glfwMakeContextCurrent(window);GL.createCapabilities();
  program=glCreateProgram();glAttachShader(program,shader(GL_VERTEX_SHADER,"#version 400 compatibility\nvoid main(){gl_Position=gl_Vertex;}"));
  glAttachShader(program,shader(GL_FRAGMENT_SHADER,Files.readString(Path.of(args[0]))));glLinkProgram(program);
  if(glGetProgrami(program,GL_LINK_STATUS)==0)throw new RuntimeException(glGetProgramInfoLog(program));glUseProgram(program);
  float f=1.428148f,n=0.05f,far=256f,a=-(far+n)/(far-n),b=-2*far*n/(far-n);
  float[] p={f,0,0,0,0,f,0,0,0,0,a,-1,0,0,b,0};
  float[] inv={1/f,0,0,0,0,1/f,0,0,0,0,0,1/b,0,0,-1,a/b};
  float[] identity={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1};
  matrix("gbufferProjection",p);matrix("gbufferProjectionInverse",inv);
  uf("viewWidth",W);uf("viewHeight",H);uf("sunProgress",1);uf("skyVisibilityDay",1);
  uf("far",far);u3("worldSunVector",0.3f,0.85f,0.2f);u3("sunPosition",30,85,20);
  glUniform2i(glGetUniformLocation(program,"eyeBrightnessSmooth"),0,240);
  u1("isEyeInWater",0);uf("blindness",0);uf("rainStrength",0);uf("nightVision",0);
  uf("frameTimeCounter",1);uf("borderFogDistance",256);uf("atmosphereFogCoefficient",0);
  u3("fogColor",0.5f,0.7f,0.9f);u3("skyColor",0.5f,0.7f,0.9f);
  uf("sunrise",0);uf("moonrise",0);uf("moonProgress",0);uf("dayUnderwaterFogFade",1);
  uf("astraHeldLightBase",0);uf("astraBlocklightSuppression",0);uf("astraHeldLightSuppression",0);
  u4("lightningBoltPosition");
  BufferedImage noise=ImageIO.read(Path.of(args[2]).toFile());float[] noiseData=new float[noise.getWidth()*noise.getHeight()*4];
  for(int y=0;y<noise.getHeight();y++)for(int x=0;x<noise.getWidth();x++){
   int c=noise.getRGB(x,y),i=(y*noise.getWidth()+x)*4;noiseData[i]=((c>>16)&255)/255f;
   noiseData[i+1]=((c>>8)&255)/255f;noiseData[i+2]=(c&255)/255f;noiseData[i+3]=1;}
  texture(3,GL_RGBA8,noise.getWidth(),noise.getHeight(),GL_RGBA,noiseData);u1("noisetex",3);
  int target=texture(4,GL_RGBA32F,W,H,GL_RGBA,(float[])null);
  int fb=glGenFramebuffers();glBindFramebuffer(GL_FRAMEBUFFER,fb);glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,target,0);
  glDrawBuffer(GL_COLOR_ATTACHMENT0);glReadBuffer(GL_COLOR_ATTACHMENT0);glViewport(0,0,W,H);
  String[] names={"heldlight_T0","heldlight_T","waves_camA","waves_camB","caustics","shore_pitch20","shore_pitch42"};
  for(int mode=0;mode<7;mode++){
   // per-mode camera state: [0]=T0 [1]=T=(9,4,12) [2]=camA [3]=camB(+1x,+1Tx) [4..6]=shore
   if(mode==0){matrix("gbufferModelView",matTranslate(0,0,0));matrix("gbufferModelViewInverse",matTranslate(0,0,0));u3("cameraPosition",100.3f,70,200.2f);}
   if(mode==1){matrix("gbufferModelView",matTranslate(-9,-4,-12));matrix("gbufferModelViewInverse",matTranslate(9,4,12));u3("cameraPosition",100.3f,70,200.2f);}
   if(mode==2){matrix("gbufferModelView",matTranslate(-9.3f,-4.1f,-12.7f));matrix("gbufferModelViewInverse",matTranslate(9.3f,4.1f,12.7f));u3("cameraPosition",100.3f,70,200.2f);u3("worldShift",0,0,0);}
   if(mode==3){matrix("gbufferModelView",matTranslate(-10.3f,-4.1f,-12.7f));matrix("gbufferModelViewInverse",matTranslate(10.3f,4.1f,12.7f));u3("cameraPosition",101.3f,70,200.2f);u3("worldShift",1,0,0);}
   if(mode>=4){
    matrix("gbufferModelView",matTranslate(0,0,0));matrix("gbufferModelViewInverse",matTranslate(0,0,0));
    u3("cameraPosition",0,71.6f,0);u3("worldShift",0,0,0);
    double pitch=mode==5?Math.toRadians(-20):Math.toRadians(-42);
    uf("pitchCos",(float)Math.cos(pitch));uf("pitchSin",(float)Math.sin(pitch));
    // bake depthtex1 + colortex4 for the shore at this pitch (terrain only)
    float[] depth=new float[W*H],color=new float[W*H*4];
    double pc=Math.cos(pitch),ps=Math.sin(pitch);
    for(int y=0;y<H;y++)for(int x=0;x<W;x++){
     float rx=(float)(((x+.5)/W*2-1)/f),ry=(float)(((y+.5)/H*2-1)/f);
     float wx=rx,wy=(float)(ry*pc+ps*-1),wz=(float)(ry*-ps+pc*-1);
     float len=(float)Math.sqrt(wx*wx+wy*wy+wz*wz);wx/=len;wy/=len;wz/=len;
     float t=0,th=1e9f;for(int i=0;i<640;i++){t+=0.25f;float px=wx*t,py=wy*t,pz=wz*t;
      if(py<=shoreHeight(px,pz)){th=t-0.125f;break;}if(t>160)break;}
     int q=y*W+x;
     if(th<1e8f){float vz=wz*th;depth[q]=(a*vz+b)/(-vz)*.5f+.5f;
      float px=wx*th,pz=wz*th;float peb=0.82f+0.18f*(float)Math.sin(px*7.1)*(float)Math.sin(pz*5.3);
      color[q*4]=0.62f*peb;color[q*4+1]=0.55f*peb;color[q*4+2]=0.44f*peb;color[q*4+3]=1;}
     else{depth[q]=1;color[q*4]=0;color[q*4+1]=0;color[q*4+2]=0;color[q*4+3]=1;}
    }
    texture(0,GL_R32F,W,H,GL_RED,depth);texture(1,GL_RGBA8,W,H,GL_RGBA,color);
    u1("depthtex1",0);u1("colortex4",1);
   }
   u1("probe",mode<2?0:mode<4?1:mode==4?2:mode==5?3:4);
   glBegin(GL_TRIANGLES);glVertex2f(-1,-1);glVertex2f(1,-1);glVertex2f(1,1);glVertex2f(-1,-1);glVertex2f(1,1);glVertex2f(-1,1);glEnd();
   float[] result=new float[W*H*4];glReadPixels(0,0,W,H,GL_RGBA,GL_FLOAT,result);
   ByteBuffer bytes=ByteBuffer.allocate(result.length*4).order(ByteOrder.LITTLE_ENDIAN);for(float v:result)bytes.putFloat(v);
   Files.write(Path.of(args[1],names[mode]+".f32"),bytes.array());BufferedImage img=new BufferedImage(W,H,BufferedImage.TYPE_INT_RGB);
   for(int y=0;y<H;y++)for(int x=0;x<W;x++){int q=(y*W+x)*4;int c=0;for(int k=0;k<3;k++)c=(c<<8)|(int)(255*Math.max(0,Math.min(1,result[q+k])));img.setRGB(x,H-1-y,c);}
   ImageIO.write(img,"png",Path.of(args[1],names[mode]+".png").toFile());
  }
  System.out.println("Renderer: "+glGetString(GL_RENDERER));glfwDestroyWindow(window);glfwTerminate();
 }
 static void u4(String n){glUniform4f(glGetUniformLocation(program,n),0,0,0,0);}
}
'''


def frame(name):
    data = struct.unpack("<" + "f" * (192 * 192 * 4), (OUT / f"{name}.f32").read_bytes())
    return data


def px(frame_data, x, y):
    i = (y * 192 + x) * 4
    return frame_data[i:i + 4]


def luminance(c):
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    shaders = ROOT / "Astra" / "shaders"
    profile = parse_profiles(shaders / "shaders.properties")["BALANCED"]
    profile.update(SHADOWS=None, UNDERWATER_LIGHT_SHAFTS=None)
    with tempfile.TemporaryDirectory(prefix="astra-sc35-probe-") as td:
        temp = Path(td)
        fragment = temp / "probe.fsh"
        fragment.write_text(FRAGMENT, encoding="utf-8")
        fragment.write_text(Expander(shaders, profile).expand(fragment, root=True), encoding="utf-8")
        java = temp / "SC35Probe.java"
        java.write_text(JAVA, encoding="utf-8")
        cp = lwjgl_classpath(DEFAULT_MC_ROOT)
        subprocess.run(["javac", "-cp", cp, str(java)], check=True)
        subprocess.run(["java", "-cp", cp + ";" + str(temp), "SC35Probe", str(fragment),
                        str(OUT), str(shaders / "textures/noise.png")], check=True)

    held_t0, held_t = frame("heldlight_T0"), frame("heldlight_T")
    def ball_center(data):
        total = sx = sz = 0.0
        for y in range(192):
            for x in range(192):
                wgt = luminance(px(data, x, y))
                total += wgt
                sx += wgt * (x - 96)
                sz += wgt * (y - 96)
        return (sx / max(total, 1e-9), sz / max(total, 1e-9)), max(
            luminance(px(data, x, y)) for y in range(192) for x in range(192))
    com0, peak0 = ball_center(held_t0)
    com1, peak1 = ball_center(held_t)

    waves_a, waves_b = frame("waves_camA"), frame("waves_camB")
    wave_delta = sum(abs(px(waves_a, x, y)[0] - px(waves_b, x, y)[0])
                     + abs(px(waves_a, x, y)[1] - px(waves_b, x, y)[1])
                     for y in range(192) for x in range(192)) / (192 * 192 * 2)

    caustics = frame("caustics")
    values = sorted(px(caustics, x, y)[0] for y in range(192) for x in range(192))
    direct = 0.35  # representative shallow riverbed directRadiance
    over_bloom = sum(1 for v in values if v * direct > 1.0) / len(values)
    percentile = lambda q: values[min(int(q * len(values)), len(values) - 1)]

    def shore_band(name):
        data = frame(name)
        # waterline = rows where both shore-occluded (albedo-ish) and water pixels meet.
        # Band darkness: darkest water-pixel luminance within the transition rows.
        rows_lum = []
        for y in range(192):
            lum = [luminance(px(data, x, y)) for x in range(192)]
            rows_lum.append(lum)
        transition_rows = []
        for y in range(1, 191):
            mean = sum(rows_lum[y]) / 192
            prev = sum(rows_lum[y - 1]) / 192
            nxt = sum(rows_lum[y + 1]) / 192
            if abs(nxt - prev) > 0.02:
                transition_rows.append(y)
        darkest = min((min(rows_lum[y]) for y in transition_rows), default=0.0)
        return {"transition_rows": len(transition_rows), "darkest_transition_luma": darkest}
    band20 = shore_band("shore_pitch20")
    band42 = shore_band("shore_pitch42")

    result = {
        "scope": "Real pack GLSL, synthetic geometry; SHADOWS/SHAFTS off; no Iris injection",
        "heldlight_com_offset_px_T0": [round(com0[0], 2), round(com0[1], 2)],
        "heldlight_com_offset_px_T": [round(com1[0], 2), round(com1[1], 2)],
        "heldlight_peak_hdr_T": round(peak1, 3),
        "wave_anchor_mean_delta": round(wave_delta, 5),
        "caustics_p50": round(percentile(0.50), 4),
        "caustics_p90": round(percentile(0.90), 4),
        "caustics_p99": round(percentile(0.99), 4),
        "caustics_max": round(values[-1], 4),
        "caustics_fraction_over_bloom": round(over_bloom, 5),
        "shore_pitch20": band20,
        "shore_pitch42": band42,
    }
    (OUT / "results.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
