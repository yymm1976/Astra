"""Driver-level geometry and light-path verification; no Minecraft state is changed.

已失效（2026-09-21 标注弃用 / DEPRECATED）——本工具不再为阴影链路提供有效验收。

口径（一句话）
    自 2026-09-09 影图换源（Mellow 方形扭曲 → Steadfast 径向投影）起，本工具对当前包必然判 FAIL。
    **它变红不代表回归，不要再拿它当验收依据、也不要把它记成新增回归。** 本工单只做标注，
    **不重写它的模型**——保留这处可复现的失败作为证据。

失败形态（2026-09-21 复跑，退出码 1；日志 qa/b4-validate-shadow-water-2026-09-21-rerun.log）
    Shadow plane: pixels=27556, max depth error=0.1107716904917071
    Exception in thread "main" java.lang.RuntimeException: Shadow plane mismatch
        at RenderPathValidation.main(RenderPathValidation.java:58)
    抛异常的是第一个门（影面深度模型，现 :121-:122 的两条断言，B4 核查时 :64-:65），工具在此即退出。

内嵌参考模型的位置
    `JAVA = r'''` 起的整个字符串字面量：现占 **:65-:183**（B4 核查时是 :8-:126；本段说明加在
    该块之前，整块下移 57 行）；Java 行与 Python 行的换算现为 **Java 行 = Python 行 − 64**
    （B4 核查时为 − 7）。定位请以 `plane(`、`Math.max(Math.abs(qx),Math.abs(qy))`、
    `m/(.2+.8*m)`、`GL_TRIANGLES` 这些串为准；模型核心现占 **:114-:118**（B4 核查时 :57-:61）：
        :114  r = max(|qx|,|qy|)           → 方形（Chebyshev）范数
        :116  m/(.2+.8*m) 二分求逆          → 方形 warp，常数 0.2/0.8 硬编码（= shadow_map_bias 0.8）
        :118  .5 + .1*(plane)              → 深度尺度 z*0.2
    这套形态精确等于 2026-09-08 那版 Astra（git 6fcb0fd；本工具在 git 里只有那一个提交、此后未改）。

当前实现的位置
    Astra/shaders/lib/distort.glsl:16-42——
        :16-17  SHADOW_DISTORT_FACTOR = 25.6 / SHADOW_DISTANCE（BALANCED 档 D=256 → a=0.1）
        :19-21  因子 = length(pos) + a          → 径向（Euclidean）范数
        :24-31  前向 warp pos.xy/factor、pos.z*0.5   → 深度尺度 z*0.5
        :33-42  解析逆 p = q*a/(1-|q|)
    范数、常数、深度尺度三项同时不同，是结构性不一致而非参数漂移。

只改模型也不够（要过门需 512² 量级的网格）
    工具只画 2 个三角形（现 :109，B4 核查时 :52）。径向映射把屏幕→源的局部放大率 a/(1-|q|)²
    从中心到边缘拉开约 100 倍，线性插值不再等于解析平面值，残差 ~0.06，比 2e-6 的判门大四个
    数量级。同一 256×256 栅格下的实测收敛：2 tri 0.0608｜8 tri 0.0485｜8×8 0.00851｜32×32 0.00059｜
    64×64 0.00015｜512×512 ~2.3-2.5e-6（仍贴在门限上）。即：必须同时改**测量方式**
    （加密到 512²-1024² 网格，约 5×10⁵-2×10⁶ 个三角形），单纯把公式改对仍会红。

从未执行的三段
    因第一段抛异常，后三段判定（太阳可见性 / 边界过冲 / 33 帧固定接收点位移，现 :123-:179，
    B4 核查时 :66-:120）在当前包上**一行都没跑过**，状态未知——既不能记 PASS，也不能记 FAIL。

复现（本工具自身不写任何仓库文件，除 qa/render-path-verification.log 这一份运行产物）
    python qa/tools/validate_shadow_water.py
"""
from pathlib import Path
import subprocess
import tempfile
from compile_glsl import Expander, parse_profiles, lwjgl_classpath, DEFAULT_MC_ROOT

ROOT = Path(__file__).resolve().parents[2]

# DEPRECATED 2026-09-21 (B4). Do not "fix" this file by syncing the model below to
# lib/distort.glsl: that alone would still fail (2 triangles cannot resolve the radial
# warp; ~512^2 needed). A red run from this tool is NOT a regression - see the module
# docstring for the measured evidence. The model is kept verbatim as a failure record.
DEPRECATED = ("DEPRECATED 2026-09-21 (B4): validate_shadow_water.py no longer provides valid "
              "acceptance for the shadow path. Its embedded Java model (below) is the pre-2026-09-09 "
              "square distort while the pack ships the radial one (Astra/shaders/lib/distort.glsl:16-42), "
              "and fixing the formula alone would still fail (2-triangle raster needs ~512^2). "
              "A red run is NOT a regression; the last 3 sections never ran. See the module docstring.")

JAVA = r'''
import java.nio.file.*;
import static org.lwjgl.glfw.GLFW.*;
import org.lwjgl.opengl.GL;
import static org.lwjgl.opengl.GL33.*;
public class RenderPathValidation {
 static int program;
 static int shader(int type,String path)throws Exception{
  int s=glCreateShader(type);glShaderSource(s,Files.readString(Path.of(path)));glCompileShader(s);
  if(glGetShaderi(s,GL_COMPILE_STATUS)==0)throw new RuntimeException(glGetShaderInfoLog(s));return s;
 }
 static int link(String v,String f)throws Exception{
  int p=glCreateProgram();glAttachShader(p,shader(GL_VERTEX_SHADER,v));glAttachShader(p,shader(GL_FRAGMENT_SHADER,f));glLinkProgram(p);
  if(glGetProgrami(p,GL_LINK_STATUS)==0)throw new RuntimeException(glGetProgramInfoLog(p));return p;
 }
 static void matrix(String n){float[] m={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1};glUniformMatrix4fv(glGetUniformLocation(program,n),false,m);}
 static void f(String n,float x){glUniform1f(glGetUniformLocation(program,n),x);}
 static void v(String n,float x,float y,float z){glUniform3f(glGetUniformLocation(program,n),x,y,z);}
 static int tex(int unit,int format,int w,int h,int channels,float[] data){
  glActiveTexture(GL_TEXTURE0+unit);int t=glGenTextures();glBindTexture(GL_TEXTURE_2D,t);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);
  glTexImage2D(GL_TEXTURE_2D,0,format,w,h,0,channels,GL_FLOAT,data);return t;
 }
 static void sampler(String n,int u){glUniform1i(glGetUniformLocation(program,n),u);}
 static float plane(float x,float y){return .31f*x-.23f*y+.12f;}
 static void vertex(float x,float y){glVertex3f(x,y,plane(x,y));}
 static void quad(){glBegin(GL_TRIANGLES);glVertex2f(-1,-1);glVertex2f(1,-1);glVertex2f(1,1);glVertex2f(-1,-1);glVertex2f(1,1);glVertex2f(-1,1);glEnd();}
 public static void main(String[] a)throws Exception{
  if(!glfwInit())throw new RuntimeException("GLFW init");glfwWindowHint(GLFW_VISIBLE,GLFW_FALSE);
  glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR,4);glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR,0);
  glfwWindowHint(GLFW_OPENGL_PROFILE,GLFW_OPENGL_COMPAT_PROFILE);
  long win=glfwCreateWindow(256,256,"Astra render path validation",0,0);glfwMakeContextCurrent(win);GL.createCapabilities();
  System.out.println("GPU: "+glGetString(GL_RENDERER));
  int fb=glGenFramebuffers();glBindFramebuffer(GL_FRAMEBUFFER,fb);
  int color=tex(5,GL_RGBA32F,256,256,GL_RGBA,null),depth=tex(6,GL_DEPTH_COMPONENT32F,256,256,GL_DEPTH_COMPONENT,null);
  glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,color,0);
  glFramebufferTexture2D(GL_FRAMEBUFFER,GL_DEPTH_ATTACHMENT,GL_TEXTURE_2D,depth,0);
  glDrawBuffer(GL_COLOR_ATTACHMENT0);glReadBuffer(GL_COLOR_ATTACHMENT0);
  if(glCheckFramebufferStatus(GL_FRAMEBUFFER)!=GL_FRAMEBUFFER_COMPLETE)throw new RuntimeException("FBO");
  program=link(a[0],a[1]);glUseProgram(program);matrix("shadowModelViewInverse");matrix("shadowModelView");matrix("gbufferModelViewInverse");
  tex(0,GL_RGBA32F,1,1,GL_RGBA,new float[]{1,1,1,1});sampler("gtexture",0);f("alphaTestRef",.1f);
  glMatrixMode(GL_PROJECTION);glLoadIdentity();glMatrixMode(GL_MODELVIEW);glLoadIdentity();
  glViewport(0,0,256,256);glEnable(GL_DEPTH_TEST);glClearDepth(1);glClear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT);
  glColor4f(1,1,1,1);glNormal3f(0,1,0);
  glBegin(GL_TRIANGLES);vertex(-.8f,-.8f);vertex(.8f,-.8f);vertex(.8f,.8f);vertex(-.8f,-.8f);vertex(.8f,.8f);vertex(-.8f,.8f);glEnd();
  float[] depths=new float[256*256];glReadPixels(0,0,256,256,GL_DEPTH_COMPONENT,GL_FLOAT,depths);
  double maxError=0;int count=0;
  for(int y=12;y<244;y++)for(int x=12;x<244;x++){
   float z=depths[y*256+x];if(z>=1)continue;
   double qx=(x+.5)/128-1,qy=(y+.5)/128-1,r=Math.max(Math.abs(qx),Math.abs(qy));
   // Independent numerical inversion of the forward warp, rather than the shader inverse.
   double lo=0,hi=10;for(int k=0;k<60;k++){double m=(lo+hi)/2;if(m/(.2+.8*m)<r)lo=m;else hi=m;}
   double scale=(lo+hi)/2/Math.max(r,1e-12);
   double expected=.5+.1*(.31*qx*scale-.23*qy*scale+.12);
   maxError=Math.max(maxError,Math.abs(z-expected));count++;
  }
  System.out.println("Shadow plane: pixels="+count+", max depth error="+maxError);
  if(count<20000||maxError>2e-6)throw new RuntimeException("Shadow plane mismatch");
  program=link(a[2],a[3]);glUseProgram(program);glDisable(GL_DEPTH_TEST);
  matrix("shadowModelView");matrix("shadowProjection");matrix("gbufferModelViewInverse");
  v("cameraPosition",0,-3,0);v("worldSunVector",0,1,0);v("lightVector",0,1,0);
  f("skyVisibilityDay",1);f("sunProgress",1);
  float[] all=new float[256*256],opaque=new float[all.length],caster=new float[all.length*4];
  for(int y=0;y<256;y++)for(int x=0;x<256;x++){int i=y*256+x;all[i]=.4f;opaque[i]=x<128?.4f:1f;caster[i*4]=x<128?1f:80f/127.5f;caster[i*4+1]=caster[i*4+2]=caster[i*4+3]=1;}
  tex(0,GL_DEPTH_COMPONENT32F,256,256,GL_DEPTH_COMPONENT,all);sampler("shadowtex0",0);
  tex(1,GL_DEPTH_COMPONENT32F,256,256,GL_DEPTH_COMPONENT,opaque);sampler("shadowtex1",1);
  tex(2,GL_RGBA32F,256,256,GL_RGBA,caster);sampler("shadowcolor0",2);
  tex(3,GL_RGBA32F,1,1,GL_RGBA,new float[]{.5f,.5f,.5f,1});sampler("noisetex",3);
  quad();float[] result=new float[256*256*4];glReadPixels(0,0,256,256,GL_RGBA,GL_FLOAT,result);
  double dark=0,lit=0;for(int y=0;y<256;y++)for(int x=0;x<256;x++){int i=(y*256+x)*4;for(int k=0;k<3;k++){
   if(!Float.isFinite(result[i+k]))throw new RuntimeException("Non-finite source");
   if(x<120)dark=Math.max(dark,result[i+k]);if(x>136)lit=Math.max(lit,result[i+k]);}}
  System.out.println("Solar source: opaque max="+dark+", open-water max="+lit);
  if(dark>1e-7||lit<.01)throw new RuntimeException("Solar visibility mismatch");
  glUniform1i(glGetUniformLocation(program,"mode"),1);quad();glReadPixels(0,0,256,256,GL_RGBA,GL_FLOAT,result);
  double overshoot=0;for(int x=96;x<160;x++)for(int k=0;k<3;k++){
   float left=result[(128*256+64)*4+k],right=result[(128*256+192)*4+k],value=result[(128*256+x)*4+k];
   overshoot=Math.max(overshoot,Math.max(value-Math.max(left,right),Math.min(left,right)-value));
  }
  System.out.println("Opaque/water edge: lighting overshoot="+overshoot);
  if(overshoot>2e-6)throw new RuntimeException("Edge exceeds its physical endpoints");
  // Regression for the six-image rejection: water identity is independently
  // known, while EVERY nearest-caster marker says non-water. Opaque shadows
  // must survive and the open half must still receive solar energy.
  for(int i=0;i<all.length;i++)caster[i*4]=1f;
  tex(2,GL_RGBA8,256,256,GL_RGBA,caster);sampler("shadowcolor0",2);
  tex(4,GL_RGBA8,1,1,GL_RGBA,new float[]{64f/255f,0,1,1});sampler("colortex6",4);
  glUniform1i(glGetUniformLocation(program,"isEyeInWater"),1);
  glUniform1i(glGetUniformLocation(program,"mode"),0);
  quad();glReadPixels(0,0,256,256,GL_RGBA,GL_FLOAT,result);
  dark=0;lit=0;
  for(int y=0;y<256;y++)for(int x=0;x<256;x++)for(int k=0;k<3;k++){
   float value=result[(y*256+x)*4+k];
   if(!Float.isFinite(value))throw new RuntimeException("Non-finite volume source");
   if(x<120)dark=Math.max(dark,value);if(x>136)lit=Math.max(lit,value);
  }
  System.out.println("Independent water volume, no water caster: opaque max="+dark+", open max="+lit);
  if(dark>1e-7||lit<.01)throw new RuntimeException("Missing caster still suppresses known water source");
  // A fixed world receiver must not inherit main-view translation when projected
  // by the independent shadow camera. Include negative section crossings.
  glUniform1i(glGetUniformLocation(program,"mode"),2);
  double motionError=0;
  for(int frame=0;frame<33;frame++){
   float cx=-144.25f+frame*.53f,cy=74.4f,cz=-564.2f+frame*.17f;
   v("cameraPosition",cx,cy,cz);
   float yaw=frame*.13f,c=(float)Math.cos(yaw),s=(float)Math.sin(yaw);
   float[] mainInverse={c,0,-s,0,0,1,0,0,s,0,c,0,cx%16,cy%16,cz%16,1};
   glUniformMatrix4fv(glGetUniformLocation(program,"gbufferModelViewInverse"),false,mainInverse);
   quad();float[] sample=new float[4];glReadPixels(128,128,1,1,GL_RGBA,GL_FLOAT,sample);
   motionError=Math.max(motionError,Math.max(Math.abs(sample[0]+128),Math.max(Math.abs(sample[1]-63),Math.abs(sample[2]+564))));
  }
  System.out.println("Fixed receiver under 33 main-camera moves/rotations: max world error="+motionError);
  if(motionError>1e-4)throw new RuntimeException("Main-view translation displaced the shadow receiver");
  int err=glGetError();if(err!=GL_NO_ERROR)throw new RuntimeException("GL error "+err);
  System.out.println("PASS: actual shadow producer plane and occluded/transmitted solar source");
  glfwDestroyWindow(win);glfwTerminate();
 }
}
'''

def main():
    print(DEPRECATED)
    print()
    shaders = ROOT / 'Astra/shaders'
    profile = parse_profiles(shaders / 'shaders.properties')['BALANCED']
    profile['SHADOW_RESOLUTION'] = '256'
    with tempfile.TemporaryDirectory(prefix='astra-render-path-') as directory:
        temp = Path(directory)
        vertex = temp / 'shadow.vsh'
        fragment = temp / 'shadow.fsh'
        vertex.write_text(Expander(shaders, profile).expand(shaders / 'shadow.vsh', root=True), encoding='utf-8')
        fragment.write_text(Expander(shaders, profile).expand(shaders / 'shadow.fsh', root=True), encoding='utf-8')
        solar_vertex = temp / 'solar.vsh'
        solar_vertex.write_text('#version 400 compatibility\nvoid main(){gl_Position=gl_Vertex;}\n', encoding='utf-8')
        solar_fragment = temp / 'solar.fsh'
        solar_fragment.write_text('''#version 400 compatibility
#include "/program/scene.glsl"
uniform int mode;
void main(){
 if(mode==2){gl_FragColor=vec4(player_shadow(vec3(-128,63,-564)-cameraPosition)+cameraPosition,1);return;}
 float x=(gl_FragCoord.x/256.0*2.0-1.0)*0.1;
 if(mode==1){
  LightParams params=LightParams(vec3(.23,.38,.68),vec3(1.05,.93,.78),0,1,0,1,vec4(0));
  vec3 direct;
  vec3 color=diffuse_lighting(vec3(1),vec3(0,1,0),vec3(0),
   vec3(gl_FragCoord.x/256.0,.5,.5),.5,0,false,false,false,params,direct);
  gl_FragColor=vec4(color,1);return;
 }
 gl_FragColor=vec4(astra_water_sun_source(vec3(x,0,0),vec3(0,1,0)),1);
}
''', encoding='utf-8')
        solar_fragment.write_text(Expander(shaders, profile).expand(solar_fragment, root=True), encoding='utf-8')
        java = temp / 'RenderPathValidation.java'
        java.write_text(JAVA, encoding='utf-8')
        cp = lwjgl_classpath(DEFAULT_MC_ROOT)
        subprocess.run(['javac', '-cp', cp, str(java)], check=True)
        result = subprocess.run(['java', '-cp', cp + ';' + str(temp), 'RenderPathValidation',
                                 str(vertex), str(fragment), str(solar_vertex), str(solar_fragment)],
                                text=True, capture_output=True, encoding='utf-8', errors='replace')
        output = result.stdout + result.stderr
        (ROOT / 'qa/render-path-verification.log').write_text(output, encoding='utf-8')
        print(output)
        return result.returncode

if __name__ == '__main__':
    raise SystemExit(main())
