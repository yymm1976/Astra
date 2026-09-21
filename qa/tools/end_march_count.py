#!/usr/bin/env python3
"""A4 counting probe: instrument the End black-hole march and count its work per pixel.

Reuses render_end_design.py's LWJGL harness (same classpath helper, same 1024x768
framebuffer, same ray construction) but replaces the radiance output with four counters
so the numbers are measured on the GPU, not estimated from the source:

    R = end_scene_segment() calls      (entry x2 + 2 per march step + escape)
    G = march loop iterations executed (END_MARCH_STEPS is 48; early breaks show up here)
    B = end_disc_sample() calls that cleared the 1e-5 early-out, i.e. the samples that
        actually reach end_noise3 (end_blackhole.glsl:48 is this file's only end_noise3)
    A = iterations of the empty-space loop over candidate bodies (end_blackhole.glsl:141)

Instrumentation is pure text substitution on a recursively expanded copy of the source,
held in a temp dir: nothing under Astra/ is touched.

Re-run: python qa/tools/end_march_count.py --panorama
This is a pinned measurement, not a gate.
"""

from pathlib import Path
import argparse
import re
import subprocess
import tempfile

import numpy as np

from compile_glsl import lwjgl_classpath, DEFAULT_MC_ROOT

JAVA = r'''
import java.nio.file.*;
import java.io.*;
import static org.lwjgl.glfw.GLFW.*;
import org.lwjgl.opengl.GL;
import static org.lwjgl.opengl.GL11.*;
import static org.lwjgl.opengl.GL20.*;
import static org.lwjgl.opengl.GL30.*;
public class EndCount {
 public static void main(String[] args) throws Exception {
  if(!glfwInit()) throw new RuntimeException("GLFW");
  glfwWindowHint(GLFW_VISIBLE,GLFW_FALSE);
  long w=glfwCreateWindow(1024,768,"End count",0,0); glfwMakeContextCurrent(w); GL.createCapabilities();
  int fs=glCreateShader(GL_FRAGMENT_SHADER); glShaderSource(fs,Files.readString(Path.of(args[0])));glCompileShader(fs);
  if(glGetShaderi(fs,GL_COMPILE_STATUS)==0) throw new RuntimeException(glGetShaderInfoLog(fs));
  int vs=glCreateShader(GL_VERTEX_SHADER);glShaderSource(vs,"#version 430 compatibility\nvoid main(){gl_Position=gl_Vertex;}");glCompileShader(vs);
  int p=glCreateProgram();p=glCreateProgram();glAttachShader(p,fs);glAttachShader(p,vs);glLinkProgram(p);
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

PREAMBLE = '''#version 430 compatibility
uniform sampler2D noisetex;
uniform float frameTimeCounter;
const int noiseTextureResolution=256;
#define END_NEBULA
uniform int panorama;
// lib/settings.glsl:106 (analytic body path needs it; the body-cache path did not)
#define END_PRECESSION_MINUTES 36
'''

# Counters sit at file scope ahead of every instrumented body, so the increments can live
# INSIDE the callees. Wrapper functions would need END_BODY_COUNT in their signature
# before end_geometry.glsl defines it, and the driver rejects that.
COUNTERS = '''
float probeSeg=0.0; float probeSteps=0.0; float probeDisc=0.0; float probeEmpty=0.0;
'''

MAIN = '''
void main(){
 vec2 uv=gl_FragCoord.xy/vec2(1024,768);
 vec3 light=normalize(vec3(0.0,0.35,-1.0));
 vec3 ray;
 if(panorama==1){float a=(uv.x-.5)*END_TAU;float b=(uv.y-.5)*END_PI;ray=vec3(sin(a)*cos(b),sin(b),-cos(a)*cos(b));}
 else ray=normalize(end_basis(light)*vec3((uv*2.0-1.0)*vec2(1.333333,1)*tan(radians(35.0)),1.0));
 vec3 color=vec3(0);
 astra_end_blackhole(color,ray,light);
 gl_FragColor=vec4(probeSeg,probeSteps,probeDisc,probeEmpty);
}
'''

NL = chr(10)
INC_POW = '#include "/lib/pow.glsl"'


def expand_includes(source, shader_root):
    """Recursively inline /path includes. The End chain is blackhole -> system -> ring ->
    geometry -> lib/end_light, four levels deep; render_end_design.py inlined only the
    first, which is why that tool stopped compiling after the split. Every inlined file is
    self-guarded by #ifndef and none re-includes a parent, so order does not matter."""
    for _ in range(64):
        m = re.search(r'#include "([^"]+)"', source)
        if not m:
            return source
        rel = m.group(1).lstrip('/')
        source = (source[:m.start()]
                  + (shader_root / rel).read_text(encoding='utf-8')
                  + source[m.end():])
    raise RuntimeError('include expansion did not terminate')


def instrument(source, DIAG=False):
    """Textual instrumentation placed INSIDE the callees: no signature changes, no forward
    declarations. Every substitution is asserted, so a source edit fails loudly instead of
    silently producing an un-instrumented probe."""
    body = source

    seg_head = '                       inout vec3 radiance,inout vec3 transmission) {'
    assert body.count(seg_head) == 1, body.count(seg_head)
    body = body.replace(seg_head, seg_head + NL + '    probeSeg+=1.0;')

    disc_head = ('void end_disc_sample(vec3 p,vec3 ray,float stepLength,mat3 disc,float cone,' + NL +
                 '                     inout vec3 radiance,inout vec3 transmission) {')


    assert body.count('for(int i=0;i<END_MARCH_STEPS;i++) {') == 1
    body = body.replace('for(int i=0;i<END_MARCH_STEPS;i++) {',
                        'for(int i=0;i<END_MARCH_STEPS;i++) { probeSteps+=1.0;')

    assert body.count('for(int j=0;j<candidateCount;j++) {') == 1
    body = body.replace('for(int j=0;j<candidateCount;j++) {',
                        'for(int j=0;j<candidateCount;j++) { probeEmpty+=1.0;')

    assert body.count('if(density<=0.00001) return;') == 1
    body = body.replace('if(density<=0.00001) return;',
                        'if(density<=0.00001) return; probeDisc+=1.0;')

    # diagnostic channel (opt-in): surface the lens discriminant on probeEmpty
    if DIAG:
        body = body.replace('    if(discriminant<=0.0 || projection<=0.0) {',
                            '    probeEmpty=discriminant;' + NL + 
                            '    if(discriminant<=0.0 || projection<=0.0) {')
    return PREAMBLE + COUNTERS + body + MAIN


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--seconds', type=float, default=0)
    ap.add_argument('--panorama', action='store_true')
    ap.add_argument('--output', default='qa/end-design/counts.npy')
    ap.add_argument('--diag', action='store_true')
    args = ap.parse_args()
    root = Path(__file__).resolve().parents[2]
    shader_root = root / 'Astra/shaders'
    # lib/pow.glsl is not on the blackhole include chain: the real translation units
    # (program/scene.glsl, program/sky.fsh) provide it before including this file, so the
    # offline TU has to supply it the same way.
    source = expand_includes(
        INC_POW + NL +
        (shader_root / 'global/dimension/end_blackhole.glsl').read_text(encoding='utf-8'),
        shader_root)
    # The offline TU has no colortex8, so ASTRA_END_BODY_CACHE would make every body
    # a zero-radius sphere at the origin and the entry segment would report a hit
    # for every lens-crossing ray (march never runs). Use the analytic body path
    # instead: end_geometry/end_ring derive the same bodies from worldTime.
    assert source.count('#define ASTRA_END_BODY_CACHE') == 1
    source = source.replace('#define ASTRA_END_BODY_CACHE',
                            '// probe: body cache off (no colortex8 offline)')
    source = instrument(source, DIAG=args.diag)

    cp = lwjgl_classpath(DEFAULT_MC_ROOT)
    out = root / args.output
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='astra-end-count-') as tmp:
        t = Path(tmp)
        (t / 'EndCount.java').write_text(JAVA, encoding='utf-8')
        (t / 'end.frag').write_text(source, encoding='utf-8')
        subprocess.run(['javac', '-cp', cp, str(t / 'EndCount.java')], check=True)
        subprocess.run(['java', '-cp', cp + ';' + str(t), 'EndCount', str(t / 'end.frag'),
                        str(t / 'counts.bin'), str(int(args.seconds % 1200 * 20)),
                        str(int(args.seconds // 1200)), str(int(args.panorama))], check=True)
        counts = np.fromfile(t / 'counts.bin', dtype='>f4').reshape(768, 1024, 4)[::-1]
    np.save(out, counts)

    seg = counts[..., 0]
    steps = counts[..., 1]
    disc = counts[..., 2]
    empty = counts[..., 3]
    print('counts written to %s' % out)
    print('%-14s %10s %10s %10s %10s' % ('channel', 'mean', 'median', 'p95', 'max'))
    for name, a in (('segments', seg), ('march steps', steps),
                    ('disc samples', disc), ('empty iters', empty)):
        print('%-14s %10.2f %10.1f %10.1f %10.1f'
              % (name, a.mean(), np.median(a), np.percentile(a, 95), a.max()))
    print()
    print('segment calls per pixel across the frame:')
    for q in (5, 25, 50, 75, 95, 99, 100):
        print('  p%-3d %8.0f' % (q, np.percentile(seg, q)))
    print()
    print('share of the 48-step budget actually executed (steps / 48):')
    print('  mean %.1f%%   median %.1f%%   p95 %.1f%%'
          % (100 * steps.mean() / 48, 100 * np.median(steps) / 48,
             100 * np.percentile(steps, 95) / 48))
    if steps.mean() > 0:
        print('  disc samples per executed step: %.3f   (1.000 = the disc is on every ray)'
              % (disc.mean() / steps.mean()))
        print('  empty-space iterations per executed step: %.3f' % (empty.mean() / steps.mean()))
    print()
    print('work mix (share of the four counters, mean per pixel):')
    tot = seg.mean() + steps.mean() + disc.mean() + empty.mean()
    for name, v in (('segments', seg.mean()), ('march steps', steps.mean()),
                    ('disc samples', disc.mean()), ('empty iters', empty.mean())):
        print('  %-14s %7.1f%%' % (name, 100 * v / tot))


if __name__ == '__main__':
    main()
