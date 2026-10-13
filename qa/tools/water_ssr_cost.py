from pathlib import Path
import sys, subprocess, tempfile, argparse

parser=argparse.ArgumentParser()
parser.add_argument('modes',nargs='*')
parser.add_argument('--pitch',type=float,default=0.7)
parser.add_argument('--height',type=float,default=2.0)
parser.add_argument('--image',action='store_true')
parser.add_argument('--scene',choices=['shore','canopy','wall60'],default='shore')
args=parser.parse_args()

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'qa/tools'))
from compile_glsl import Expander, parse_profiles, lwjgl_classpath, DEFAULT_MC_ROOT
from water_path_probe import JAVA

SHADERS=ROOT/'Astra/shaders'
profile=parse_profiles(SHADERS/'shaders.properties')['BALANCED']
profile.update(SHADOWS=None,UNDERWATER_LIGHT_SHAFTS=None,ANTIALIASING='0')

head='''#version 400 compatibility
#extension GL_ARB_shading_language_packing : require
#include "/program/scene.glsl"
#include "/program/water.glsl"
uniform float costHeight;
void main(){
 vec2 uv=gl_FragCoord.xy/vec2(viewWidth,viewHeight);
 vec3 ray=normalize(screen_view(vec3(uv,0.5)));
 vec3 worldRay=view_player(ray);
 if(worldRay.y>=-0.025){gl_FragColor=vec4(0.0);return;}
 vec3 pos=worldRay*(-costHeight/worldRay.y);
 vec3 viewPos=player_view(pos);
 vec3 geometric=vec3(0,1,0);
 WaterSurface wave=water_surface(pos,geometric,frameTimeCounter,true);
 vec3 viewNormal=normalize(player_view(wave.normal));
 vec3 viewGeometric=player_view(geometric);
'''
bodies={
 'full':'gl_FragColor=astra_water(vec3(0),1.0,pos,viewPos,wave.normal,wave.roughness,1.0,true,false,geometric,0.0);',
 'waves':'gl_FragColor=vec4(wave.normal,wave.roughness);',
 'trace':'vec3 reflected=reflect(ray,viewNormal); if(dot(reflected,viewGeometric)<=0) reflected=reflect(ray,viewGeometric); gl_FragColor=water_raytrace(depthtex1,viewPos,reflected,viewGeometric,1e20,1.0,false,true);',
 'transmit':'float d;float pd;vec2 refracted=water_refracted_scene_uv(viewPos,viewNormal-viewGeometric,uv,d,pd);vec3 color;float valid=water_transmission_sample(refracted,viewPos,viewGeometric,1.0,d,pd,color);gl_FragColor=vec4(color,valid);'
}

java=JAVA[:JAVA.index('  for(int mode=0;mode<=21;mode++){')]
java=java.replace('WaterProbe','WaterCost').replace('W=128,H=128','W=1920,H=1080')
java=java.replace('void main(){gl_Position=gl_Vertex;}',
 'flat out vec3 waterSunCentre;flat out vec3 waterSunRight;flat out vec3 waterSunVertical;void main(){waterSunCentre=vec3(0,.6,.8);waterSunRight=vec3(1,0,0);waterSunVertical=vec3(0,.8,-.6);gl_Position=vec4(gl_Vertex.xy,1.0003907-0.0500098*(sin(.6)-cos(.6)*gl_Vertex.y/1.428148),1);}').replace('GL_RGBA32F,W,H,GL_RGBA,(float[])null','GL_RGBA16F,W,H,GL_RGBA,(float[])null')
vertex='''#version 400 compatibility
uniform uint costFaceData;
uniform float costPitch;uniform float costHeight;
out vec2 texcoord;out vec2 lightcoord;out vec4 tint;out float vertexAO;
flat out uint faceData;out vec3 cameraRelativePosition;out vec3 surfaceShadowCoordinate;
flat out int waterMaterialThinSheet;
flat out vec3 waterSunCentre;flat out vec3 waterSunRight;flat out vec3 waterSunVertical;
void main(){
 float clipY=min(gl_Vertex.y,1.428148*tan(costPitch)-0.04);
 vec3 v=vec3(gl_Vertex.x/1.428148,clipY/1.428148,-1);
 float c=cos(costPitch),s=sin(costPitch);vec3 world=vec3(v.x,c*v.y+s*v.z,-s*v.y+c*v.z);
 float distance=-costHeight/world.y;cameraRelativePosition=world*distance;
 gl_Position=vec4(vec2(gl_Vertex.x,clipY)*distance,1.0003907*distance-.1000195,distance);
 texcoord=gl_Vertex.xy*.5+.5;lightcoord=vec2(248.0/256.0);tint=vec4(1);vertexAO=1;
 faceData=costFaceData;surfaceShadowCoordinate=vec3(0);
 waterMaterialThinSheet=0;waterSunCentre=vec3(0,.6,.8);
 waterSunRight=vec3(1,0,0);waterSunVertical=vec3(0,.8,-.6);
}'''
start=java.index('"#version 400 compatibility\\n')
stop=java.index('"));',start)+1
java=java[:start]+'"'+vertex.replace('\n','\\n')+'"'+java[stop:]
java+='''
  float pitch=Float.parseFloat(args[3]),height=Float.parseFloat(args[4]);
  float c=(float)Math.cos(pitch),s=(float)Math.sin(pitch);
  uf("costPitch",pitch);uf("costHeight",height);
  matrix("gbufferModelViewInverse",new float[]{1,0,0,0,0,c,-s,0,0,s,c,0,0,0,0,1});
  matrix("gbufferModelView",new float[]{1,0,0,0,0,c,s,0,0,-s,c,0,0,0,0,1});
  u1("isEyeInWater",0);uf("frameTimeCounter",17.25f);
  glUniform1ui(glGetUniformLocation(program,"costFaceData"),(1<<18)|(256<<9)|511);
  u3("astraWorldLightDirection",0,.6f,.8f);u3("worldSunVector",0,.6f,.8f);
  uf("astraSunSource",1);uf("astraDirectLightGate",1);
  u3("astraAmbientPalette",.4f,.5f,.6f);u3("astraSkyDayHorizon",.3f,.4f,.6f);
  uf("astraSolasTimeBrightness",1);uf("astraSolasShadowFade",1);
  float[] depth=new float[W*H],color=new float[W*H*4];
  for(int y=0;y<H;y++)for(int x=0;x<W;x++){
    float rx=((x+.5f)/W*2-1)/f,ry=((y+.5f)/H*2-1)/f;
    float worldY=c*ry-s,z=worldY<-.025f?(height+3)/worldY:-far;
    boolean solid=worldY<-.025f && -z<far;
    if(y>H*.88 && x>W*.3 && x<W*.7){z=-18;solid=true;}
    int q=y*W+x;depth[q]=solid?(a*z+b)/(-z)*.5f+.5f:1;
    color[q*4]=((x/32+y/32)%2==0)?.65f:.2f;color[q*4+1]=.4f;color[q*4+2]=.25f;color[q*4+3]=1;
  }
  texture(0,GL_R32F,W,H,GL_RED,depth);u1("depthtex1",0);
  texture(1,GL_R11F_G11F_B10F,W,H,GL_RGBA,color);u1("colortex4",1);
  texture(4,GL_RG32F,W,H,GL_RG,new float[W*H*2]);u1("colortex28",4);
  float[] sky=new float[256*128*4];java.util.Arrays.fill(sky,.4f);
  texture(5,GL_RGBA16F,256,128,GL_RGBA,sky);u1("colortex11",5);
  texture(6,GL_RGBA8,1,1,GL_RGBA,new float[]{1,1,1,1});u1("gtexture",6);
  matrix("shadowModelView",identity);matrix("shadowModelViewInverse",identity);
  matrix("shadowProjection",new float[]{1/112f,0,0,0,0,1/112f,0,0,0,0,-1/256f,0,0,0,0,1});
  for(int i=0;i<48;i++)draw();glFinish();
  double[] times=new double[11];
  for(int i=0;i<times.length;i++){
    int query=glGenQueries();glBeginQuery(GL_TIME_ELAPSED,query);
    for(int j=0;j<8;j++)draw();glEndQuery(GL_TIME_ELAPSED);
    times[i]=glGetQueryObjectui64(query,GL_QUERY_RESULT)/8e6;glDeleteQueries(query);
  }
  java.util.Arrays.sort(times);
  System.out.printf(java.util.Locale.ROOT,"%s median_ms=%.4f min_ms=%.4f max_ms=%.4f GPU=%s%n",args[1],times[5],times[0],times[10],glGetString(GL_RENDERER));
  if(args.length>5){
    float[] pixels=new float[W*H*4];glReadBuffer(GL_COLOR_ATTACHMENT0);
    glReadPixels(0,0,W,H,GL_RGBA,GL_FLOAT,pixels);
    java.awt.image.BufferedImage img=new java.awt.image.BufferedImage(W,H,java.awt.image.BufferedImage.TYPE_INT_RGB);
    for(int y=0;y<H;y++)for(int x=0;x<W;x++){
      int q=(y*W+x)*4,rgb=0;
      for(int component=0;component<3;component++){
        float value=Math.max(0,pixels[q+component]);value=value/(1+value);
        int channel=Math.round(255*(float)Math.pow(value,1.0/2.2));rgb=(rgb<<8)|channel;
      }
      img.setRGB(x,H-1-y,rgb);
    }
    javax.imageio.ImageIO.write(img,"png",new java.io.File(args[5]));
  }
  glfwDestroyWindow(window);glfwTerminate();
 }
 static void draw(){glBegin(GL_TRIANGLES);glVertex2f(-1,-1);glVertex2f(1,-1);glVertex2f(1,1);glVertex2f(-1,-1);glVertex2f(1,1);glVertex2f(-1,1);glEnd();}
}
'''

if args.scene=='canopy':
 java=java.replace('if(y>H*.88 && x>W*.3 && x<W*.7){z=-18;solid=true;}',
  'if(y>H*.56 && x>W*.18 && x<W*.82 && (x/5+y/7)%3!=0){z=-18-(x/13%3)*.8f;solid=true;}')
if args.scene=='wall60':
 # Far-region hits dominate the frame: every pixel whose bed would lie beyond
 # 60 blocks reflects off a 60-block wall instead, so the air-side surface
 # fading window (48..96) covers most receivers.
 java=java.replace('if(y>H*.88 && x>W*.3 && x<W*.7){z=-18;solid=true;}',
  'if(solid && -z>60.0){z=-60;}')

with tempfile.TemporaryDirectory(prefix='astra-water-cost-') as folder:
 temp=Path(folder)
 j=temp/'WaterCost.java';j.write_text(java,encoding='utf-8')
 cp=lwjgl_classpath(DEFAULT_MC_ROOT)
 subprocess.run(['javac','-cp',cp,str(j)],check=True)
 for mode in (args.modes or ['native','waves','trace','transmit']):
  if mode not in ['native','native_floor20','native_floor26','native_scalar_crossing','native_full_coarse','native_refraction_old','native_sequential','native_no_ssr','native_no_refraction','native_no_medium','native_no_glint','full','waves','trace','transmit']:
   raise SystemExit('Unknown cost component: '+mode)
  kind=mode.split('_')[0]
  fragment=temp/(mode+'.fsh')
  if kind=='native':
   native_profile=profile.copy();native_profile['SHADOWS']=''
   if mode=='native_no_ssr':native_profile['SCREENSPACE_REFLECTIONS']=None
   if mode=='native_no_refraction':native_profile['SCREENSPACE_REFRACTION']=None
   source=Expander(SHADERS,native_profile).expand(SHADERS/'gbuffers_water.fsh',root=True)
   if mode=='native_floor20':
    # Contrast only: restore the pre-change air-side horizontal water SSR entry
    # window (0.20..0.34) so earlier measurements can be re-run after the
    # source moved. Everything else in the branch stays identical.
    marker='smoothstep(0.36, 0.50, fresnel)'
    matches=source.count(marker)
    if matches!=1:raise RuntimeError(f'native_floor20 expected exactly one entry window, found {matches}')
    source=source.replace(marker,'smoothstep(0.20, 0.34, fresnel)',1)
   if mode=='native_floor26':
    # Restore only the previous 0.26..0.40 entry window for a paired comparison.
    marker='smoothstep(0.36, 0.50, fresnel)'
    matches=source.count(marker)
    if matches!=1:raise RuntimeError(f'native_floor26 expected exactly one entry window, found {matches}')
    source=source.replace(marker,'smoothstep(0.26, 0.40, fresnel)',1)
   if mode=='native_scalar_crossing':
    # Restore only the scalar air-side four-corner solver; retain all trace budgets.
    call='''accepted=water_ssr_footprint_crossing(sceneDepth,uv,pixel,depthSize,jitter,
                clipOrigin,clipDirection,sidePlane,halfTexel,vec2(coarseLow,coarseHigh),
                refineCorner,refineDepths,cachedDepth,intersection);'''
    batch=call.replace('water_ssr_footprint_crossing(', 'water_ssr_footprint_crossing_batch(',1)
    marker='bool accepted;\n            if (surfaceBudget && !underwater) '+batch+'\n            else '+call
    matches=source.count(marker)
    if matches!=1:raise RuntimeError(f'native_scalar_crossing expected exactly one solver dispatch, found {matches}')
    source=source.replace(marker,'bool '+call,1)
   if mode=='native_full_coarse':
    # Contrast only: restore the pre-change coarse density for above-water
    # surface-budget SSR, keeping the guard and all refinement intact.
    marker='coarseBudget = max(4.0, 0.5 * mix(coarseBudget, min(coarseBudget,6.0), surfaceSimplification));'
    matches=source.count(marker)
    if matches!=1:raise RuntimeError(f'native_full_coarse expected exactly one coarse budget target, found {matches}')
    source=source.replace(marker,'coarseBudget = mix(coarseBudget, min(coarseBudget,6.0), surfaceSimplification);',1)
   if mode=='native_refraction_old':
    # Restore the two former redundant colortex28/depth fetches on the
    # horizontal-bed air-side path: an unconditional refracted-texel depth
    # read and an always-reread entity record.
    marker='''float refractedDepth = backgroundDepth;
    if (any(notEqual(refractedPixel,backgroundPixel)))
        refractedDepth = texelFetch(depthBuffer,refractedPixel,0).r;'''
    matches=source.count(marker)
    if matches!=1:raise RuntimeError(f'native_refraction_old expected exactly one reuse target, found {matches}')
    source=source.replace(marker,'float refractedDepth = texelFetch(depthBuffer,refractedPixel,0).r;',1)
    marker='''valid = water_transmission_sample(refractedUV,viewPos,viewGeometric,
                                                  skylight,refractedDepth,pairedEntityDepth,
                                                  transmitted);'''
    matches=source.count(marker)
    if matches!=1:raise RuntimeError(f'native_refraction_old expected exactly one transmission target, found {matches}')
    source=source.replace(marker,'''valid = water_transmission_sample(refractedUV,viewPos,viewGeometric,
                                                  skylight,refractedDepth,transmitted);''',1)
   if mode=='native_sequential':
    marker='if (surfaceBudget && !underwater && standardProjection && suggestedTravel<=previous'
    if marker not in source:raise RuntimeError('four-query prefetch source target absent')
    source=source.replace(marker,'if (false && surfaceBudget && !underwater && standardProjection && suggestedTravel<=previous',1)
   if mode=='native_no_medium':source=source.replace('color = astra_apply_medium(color, playerPos, skylight);','color = color;')
   if mode=='native_no_glint':source=source.replace('if (!belowWater && fresnel > 0.0 && skylight > 0.0 && astraDirectLightGate > 0.0)', 'if (false)')
  else:
   fragment.write_text(head+bodies[kind]+'\n}\n',encoding='utf-8')
   source=Expander(SHADERS,profile).expand(fragment,root=True)
  fragment.write_text(source,encoding='utf-8')
  command=['java','-Xmx1G','-cp',cp+';'+str(temp),'WaterCost',str(fragment),mode,str(SHADERS/'textures/steadfast-water-noise.png'),str(args.pitch),str(args.height)]
  if args.image:
   image_path=Path(__file__).with_name(f'{mode}-{args.scene}-pitch{args.pitch}-height{args.height}.png')
   command.append(str(image_path))
  result=subprocess.run(command,capture_output=True,text=True,encoding='utf-8')
  print(result.stdout.strip(),flush=True)
  if result.returncode:print(result.stderr,flush=True);raise SystemExit(result.returncode)
  if args.image:print(f'Image: {image_path}',flush=True)
