#!/usr/bin/env python3
"""Offline probe for the 2026-09-22 End "universe" pass.

Measures, on the GPU and from the real translation unit (includes expanded, no edits to
Astra/), the quantities this pass introduced or retuned, so they can be checked without
an in-game screenshot:

    R = end_starfield() luminance        -> star counts per square degree (local maxima of
                                            the rendered field, so one star counts once,
                                            not once per lit pixel) and the brightest star
    G = 0                              -> retired ISM channel
    B = shadow angular radius (radians)  -> black-hole silhouette from the TU's own
                                            atan(END_SHADOW_TAN)
    A = photon-ring half-width (radians) -> the shell sigma the ring is drawn with, at this
                                            pass's own pixel footprint

The probe renders an equirectangular 2048x1536 panorama with a cos(lat) weight, so the
counts are reported per square degree of sky rather than per pixel. It is a measurement,
not a gate; the assertions below only reject a degenerate result (all-zero star field, nonzero retired band, ring thicker than the shadow).

Re-run: python qa/tools/end_universe_probe.py
"""

from pathlib import Path
import subprocess
import sys
import tempfile

import numpy as np

from compile_glsl import lwjgl_classpath, DEFAULT_MC_ROOT
from live_glsl_probe import expand_includes

W, H = 2048, 1536

JAVA = r'''
import java.nio.file.*;
import java.io.*;
import static org.lwjgl.glfw.GLFW.*;
import org.lwjgl.opengl.GL;
import static org.lwjgl.opengl.GL11.*;
import static org.lwjgl.opengl.GL20.*;
import static org.lwjgl.opengl.GL30.*;
public class EndUniverse {
 public static void main(String[] args) throws Exception {
  int W=Integer.parseInt(args[2]), H=Integer.parseInt(args[3]);
  if(!glfwInit()) throw new RuntimeException("GLFW");
  glfwWindowHint(GLFW_VISIBLE,GLFW_FALSE);
  long w=glfwCreateWindow(W,H,"End universe probe",0,0); glfwMakeContextCurrent(w); GL.createCapabilities();
  int fs=glCreateShader(GL_FRAGMENT_SHADER); glShaderSource(fs,Files.readString(Path.of(args[0])));glCompileShader(fs);
  if(glGetShaderi(fs,GL_COMPILE_STATUS)==0) throw new RuntimeException(glGetShaderInfoLog(fs));
  int vs=glCreateShader(GL_VERTEX_SHADER);glShaderSource(vs,"#version 430 compatibility\nvoid main(){gl_Position=gl_Vertex;}");glCompileShader(vs);
  int p=glCreateProgram();glAttachShader(p,fs);glAttachShader(p,vs);glLinkProgram(p);
  if(glGetProgrami(p,GL_LINK_STATUS)==0) throw new RuntimeException(glGetProgramInfoLog(p));glUseProgram(p);
  int tex=glGenTextures();glBindTexture(GL_TEXTURE_2D,tex);glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA32F,W,H,0,GL_RGBA,GL_FLOAT,(java.nio.ByteBuffer)null);
  int fb=glGenFramebuffers();glBindFramebuffer(GL_FRAMEBUFFER,fb);glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,tex,0);
  glUniform1i(glGetUniformLocation(p,"worldTime"),0);
  glUniform1i(glGetUniformLocation(p,"worldDay"),0);
  glViewport(0,0,W,H);glBegin(GL_TRIANGLES);glVertex2f(-1,-1);glVertex2f(3,-1);glVertex2f(-1,3);glEnd();glFinish();
  float[] data=new float[W*H*4];glReadPixels(0,0,W,H,GL_RGBA,GL_FLOAT,data);
  try(DataOutputStream out=new DataOutputStream(new BufferedOutputStream(new FileOutputStream(args[1])))) {for(float v:data)out.writeFloat(v);}
  glfwDestroyWindow(w);glfwTerminate();
 }
}
'''

PREAMBLE = '''#version 430 compatibility
uniform sampler2D noisetex;
uniform float frameTimeCounter;
const int noiseTextureResolution=256;
// lib/settings.glsl:106; end_geometry's analytic body path reads it at file scope.
#define END_PRECESSION_MINUTES 36
'''

MAIN = '''
void main(){
 vec2 uv=gl_FragCoord.xy/vec2(float(%d),float(%d));
 vec3 light=normalize(vec3(0.0,0.35,-1.0));
 float a=(uv.x-0.5)*END_TAU;
 float b=(uv.y-0.5)*END_PI;
 vec3 ray=vec3(sin(a)*cos(b),sin(b),-cos(a)*cos(b));
 // Same footprint the real passes use, so the measured ring width is the rendered one.
 float cone=max(max(length(dFdx(ray)),length(dFdy(ray))),0.00002);
 vec3 stars=end_starfield(ray,light,cone);
 vec3 ism=vec3(0.0); // Retired layer: kept as a zero channel in this report.
 float shellWidth=max(radians(0.014),cone*1.2);
 float critical=atan(END_SHADOW_TAN);
 gl_FragColor=vec4(dot(stars,vec3(0.2126,0.7152,0.0722)),
                   dot(ism,vec3(0.2126,0.7152,0.0722)),
                   critical,shellWidth);
}
''' % (W, H)

# The End void literal in end_system.glsl's end_background(), in luminance form. Reported
# so the ISM peak can be stated against the black floor rather than against zero.
VOID_LUM = 0.2126 * 0.000015 + 0.7152 * 0.000025 + 0.0722 * 0.00006


def shader_source(shader_root: Path) -> str:
    source = expand_includes(
        '#include "/lib/pow.glsl"' + chr(10)
        + (shader_root / 'global/dimension/end_blackhole.glsl').read_text(encoding='utf-8'),
        shader_root)
    # No colortex8 is bound offline; use the analytic body path.
    assert source.count('#define ASTRA_END_BODY_CACHE') == 1
    source = source.replace('#define ASTRA_END_BODY_CACHE',
                            '// probe: body cache off (no colortex8 offline)')
    return PREAMBLE + source + MAIN


def measure(root: Path) -> dict:
    shader_root = root / 'Astra/shaders'
    source = shader_source(shader_root)
    cp = lwjgl_classpath(DEFAULT_MC_ROOT)
    with tempfile.TemporaryDirectory(prefix='astra-end-universe-') as tmp:
        t = Path(tmp)
        (t / 'EndUniverse.java').write_text(JAVA, encoding='utf-8')
        (t / 'end.frag').write_text(source, encoding='utf-8')
        subprocess.run(['javac', '-cp', cp, str(t / 'EndUniverse.java')], check=True)
        subprocess.run(['java', '-cp', cp + ';' + str(t), 'EndUniverse',
                        str(t / 'end.frag'), str(t / 'probe.bin'), str(W), str(H)], check=True)
        raw = np.fromfile(t / 'probe.bin', dtype='>f4').reshape(H, W, 4)
    # Rows come out bottom-up; row r is gl_FragCoord.y = (H-1)-r, so the latitude factor
    # must be rebuilt the same way the shader built b.
    rows = (H - 1) - np.arange(H)
    b = ((rows + 0.5) / H - 0.5) * np.pi
    weight = np.cos(b)[:, None] * np.ones((1, W))
    star = raw[..., 0]
    ism = raw[..., 1]
    # Local maxima: one count per star however many pixels its profile covers. Ties are
    # kept (>= on every neighbour), which can double-count a perfectly flat peak but
    # cannot miss one.
    peak = np.ones_like(star, dtype=bool)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dy == 0 and dx == 0:
                continue
            peak &= star >= np.roll(np.roll(star, dy, 0), dx, 1)
    return {
        'star': star, 'ism': ism, 'weight': weight, 'peak': peak,
        'critical': float(raw[..., 2].mean()), 'shell_width': float(raw[..., 3].mean()),
    }


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    m = measure(root)
    star, ism, weight, peak = m['star'], m['ism'], m['weight'], m['peak']
    total_weight = float(weight.sum())
    sky_deg2 = 41252.95

    def per_deg2(mask):
        # The panorama covers the whole sphere, so a count over all pixels divided by the
        # sky area is already the density; a cos(lat) weight would double-count it.
        return float(mask.sum()) / sky_deg2

    density = per_deg2(peak & (star > 1e-5))
    density_bright = per_deg2(peak & (star > 3e-2))
    brightest = float(star.max())
    ism_peak = float(ism.max())
    band_share = float((weight * (ism > 3.0 * VOID_LUM)).sum() / total_weight * 100.0)
    shadow_deg = np.degrees(m['critical']) * 2.0
    ring_fwhm_deg = np.degrees(m['shell_width']) * 2.355

    print('End universe probe (%dx%d equirectangular, worldTime=0, worldDay=0)' % (W, H))
    print('%-48s %s' % ('star density, any star (per deg^2)', '%.2f' % density))
    print('%-48s %s' % ('star density, lum > 3e-2 (per deg^2)', '%.2f' % density_bright))
    print('%-48s %.5f' % ('brightest star luminance', brightest))
    print('%-48s %.3e' % ('ISM peak luminance', ism_peak))
    print('%-48s %.3e' % ('End void floor luminance (end_background literal)', VOID_LUM))
    print('%-48s %.1f' % ('ISM peak / void floor', ism_peak / VOID_LUM))
    print('%-48s %.1f%%' % ('sky above 3x void floor inside the ISM band', band_share))
    print('%-48s %.2f' % ('black-hole silhouette diameter (deg)', shadow_deg))
    print('%-48s %.2f' % ('black-hole silhouette radius (deg)', np.degrees(m['critical'])))
    print('%-48s %.3f' % ('photon-ring FWHM (deg)', ring_fwhm_deg))

    failures = []
    if not 0.5 < density < 30.0:
        failures.append('star density out of plausible range: %.2f /deg^2' % density)
    if density_bright >= density:
        failures.append('the bright layer is not sparser than the field '
                        '(%.2f vs %.2f /deg^2)' % (density_bright, density))
    if brightest < 1e-3:
        failures.append('brightest star is degenerate: %.3e' % brightest)
    if not 0.5 < np.degrees(m['critical']) < 20.0:
        failures.append('silhouette radius out of range: %.2f deg' % np.degrees(m['critical']))
    if ring_fwhm_deg >= np.degrees(m['critical']):
        failures.append('photon ring (%.2f deg) is not thinner than the silhouette radius '
                        '(%.2f deg)' % (ring_fwhm_deg, np.degrees(m['critical'])))
    if failures:
        print()
        for f in failures:
            print('FAIL ' + f)
        return 1
    print()
    print('all probe bounds hold')
    return 0


if __name__ == '__main__':
    sys.exit(main())
