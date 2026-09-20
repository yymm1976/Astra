#!/usr/bin/env python3
"""Measure which mip level bloom_capture.glsl's bloom taps actually resolve to.

The tile bloom samples colortex0 with an implicit-LOD texture() call, and
program/water_bloom.fsh:5 declares colortex0MipmapEnabled, so the level comes from
screen-space derivatives of the tap coordinate. This probe feeds a texture whose
levels are constant and distinct, so the returned value decodes straight back to
the level the hardware picked:

    level L is filled with R = L/8; a trilinear read returns lambda/8 for the
    picked level lambda; getBloomTile then returns pow((lambda/8)/256, 1/8);
    therefore lambda = 2048 * value^8.

Modes 0 and 1 run the shipped getBloomTile, not a copy of its body; 2 to 5 are
calibration taps that never call it:
  mode 0 - the four lods computeBloom uses, at a pixel inside every tile region,
           for each render resolution. This is the resolution compensation that
           implicit LOD provides and that any explicit replacement must reproduce.
  mode 1 - the lod 3 tile under four sub-pixel coordinate shifts, one per channel,
           scanned across the region edge, to see what the level does where the
           data-dependent branch becomes non-uniform inside a 2x2 quad.
  mode 2 - calibration: plain implicit samples at four known texel footprints.
  mode 3 - calibration: explicit textureLod at four known levels.
  mode 4 - calibration: getBloomTile's return expression (clamp + pow(x, 1/8)) around
           a single explicit tap, so the pow round trip can be charged for a level
           error instead of the sampler.
  mode 5 - calibration: the same taps as mode 4 read raw, the control for mode 4.

Pass --baseline <results.json> to additionally require the measured levels to match
an earlier run; that is the gate a fix has to clear to prove it kept the image.

Accuracy, measured here rather than assumed: an absolute level is good to about a
tenth of a level, because the trilinear readback is nonlinear in the blend fraction
(readback_error_levels, from taps with no derivative in them at all). Differences
between two runs resolve 1/128 of a level, which is what the baseline gate uses.

It does not reproduce Iris or the game's buffers; it isolates the sampler behaviour.
"""
from pathlib import Path
import json
import math
import struct
import subprocess
import sys
import tempfile

from compile_glsl import Expander, parse_profiles, lwjgl_classpath, DEFAULT_MC_ROOT

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "qa" / "bloom-lod-probe"

# viewWidth/viewHeight are the render resolution the pack would see; each pair is
# tested at its own framebuffer size so one screen pixel is one framebuffer pixel.
RESOLUTIONS = [(480, 270), (640, 360), (960, 540), (1920, 1080)]

FRAGMENT = '''#version 400 compatibility
uniform sampler2D colortex0;
uniform float viewWidth;
uniform float viewHeight;
uniform int probe;
#include "/global/water/bloom_capture.glsl"
void main() {
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    // The same mapping computeBloom():31 builds, copied here so one tile can be
    // isolated per probe mode instead of summing all four.
    vec2 bloomCoord = uv * viewHeight * 0.8 / min(360.0, viewHeight);
    if (probe == 0) {
        // offset 0 keeps all four tile regions open at the sampled pixel.
        gl_FragColor = vec4(getBloomTile(2.0, bloomCoord, vec2(0.0)).r,
                            getBloomTile(3.0, bloomCoord, vec2(0.0)).r,
                            getBloomTile(4.0, bloomCoord, vec2(0.0)).r,
                            getBloomTile(5.0, bloomCoord, vec2(0.0)).r);
    } else if (probe == 1) {
        // The same tile under four sub-pixel coordinate shifts, one per channel. A
        // shift that puts the region boundary between two pixels which share a 2x2
        // quad is the case where a lane skipped the loop but still contributes to
        // the derivative; the four offsets together cannot all miss it.
        vec4 shift = vec4(1.0, 1.25, 1.5, 1.75);
        vec2 base = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
        float scale = viewHeight * 0.8 / min(360.0, viewHeight);
        gl_FragColor = vec4(
            getBloomTile(3.0, (base + vec2(shift.x, 0.0) / viewWidth) * scale, vec2(0.0)).r,
            getBloomTile(3.0, (base + vec2(shift.y, 0.0) / viewWidth) * scale, vec2(0.0)).r,
            getBloomTile(3.0, (base + vec2(shift.z, 0.0) / viewWidth) * scale, vec2(0.0)).r,
            getBloomTile(3.0, (base + vec2(shift.w, 0.0) / viewWidth) * scale, vec2(0.0)).r);
    } else if (probe == 2) {
        // Calibration A: known per-pixel texel footprint, implicit LOD. One screen
        // pixel spans K texels, so the level the driver picks must be log2(K).
        gl_FragColor = vec4(texture(colortex0, uv * 3.2).r,
                            texture(colortex0, uv * 4.8).r,
                            texture(colortex0, uv * 9.6).r,
                            texture(colortex0, uv * 25.6).r);
    } else if (probe == 3) {
        // Calibration B: explicit LOD, so the R = level/8 encoding, the trilinear
        // blend and getBloomTile's pow round trip are checked without derivatives.
        gl_FragColor = vec4(textureLod(colortex0, uv * 8.0, 1.5).r,
                            textureLod(colortex0, uv * 8.0, 2.5).r,
                            textureLod(colortex0, uv * 8.0, 3.5).r,
                            textureLod(colortex0, uv * 8.0, 4.5).r);
    } else if (probe == 4) {
        // Calibration C: getBloomTile's return expression around a single explicit
        // tap, at four levels that step through the fractional part. Whatever these
        // come back as, the taps had no derivative to be wrong about.
        gl_FragColor = vec4(pow(clamp(textureLod(colortex0, uv * 8.0, 2.00).rgb, 0.0, 1.0).r / 256.0, 0.125),
                            pow(clamp(textureLod(colortex0, uv * 8.0, 2.25).rgb, 0.0, 1.0).r / 256.0, 0.125),
                            pow(clamp(textureLod(colortex0, uv * 8.0, 2.50).rgb, 0.0, 1.0).r / 256.0, 0.125),
                            pow(clamp(textureLod(colortex0, uv * 8.0, 2.75).rgb, 0.0, 1.0).r / 256.0, 0.125));
    } else {
        // Calibration D: the same four taps without the pow. C minus D is the round
        // trip's error; D minus 2.00/2.25/2.50/2.75 is the readback's own error.
        gl_FragColor = vec4(textureLod(colortex0, uv * 8.0, 2.00).r,
                            textureLod(colortex0, uv * 8.0, 2.25).r,
                            textureLod(colortex0, uv * 8.0, 2.50).r,
                            textureLod(colortex0, uv * 8.0, 2.75).r);
    }
}
'''

JAVA = r'''
import java.nio.file.*;
import java.nio.*;
import static org.lwjgl.glfw.GLFW.*;
import org.lwjgl.opengl.GL;
import static org.lwjgl.opengl.GL33.*;
public class BloomLodProbe {
 static int program;
 static void uf(String n,float v){glUniform1f(glGetUniformLocation(program,n),v);}
 static void u1(String n,int v){glUniform1i(glGetUniformLocation(program,n),v);}
 static int shader(int type,String src){int s=glCreateShader(type);glShaderSource(s,src);glCompileShader(s);
  if(glGetShaderi(s,GL_COMPILE_STATUS)==0)throw new RuntimeException(glGetShaderInfoLog(s));return s;}
 // Level L is a constant R = L/8 so a trilinear read reports its own mip level.
 static int mipTexture(int unit,int w,int h){
  glActiveTexture(GL_TEXTURE0+unit);int t=glGenTextures();glBindTexture(GL_TEXTURE_2D,t);
  int levels=(int)(Math.floor(Math.log((double)Math.max(w,h))/Math.log(2.0))+1);
  for(int L=0;L<levels;L++){
   int lw=Math.max(1,w>>L),lh=Math.max(1,h>>L);
   ByteBuffer data=ByteBuffer.allocateDirect(lw*lh*4);
   for(int i=0;i<lw*lh;i++){data.put((byte)Math.round(255.0*L/8.0));data.put((byte)0);data.put((byte)0);data.put((byte)255);}
   data.rewind();
   glTexImage2D(GL_TEXTURE_2D,L,GL_RGBA8,lw,lh,0,GL_RGBA,GL_UNSIGNED_BYTE,data);
  }
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR_MIPMAP_LINEAR);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAX_LEVEL,levels-1);
  u1("colortex0",unit);return t;}
 public static void main(String[] args)throws Exception{
  int[][] res={{480,270},{640,360},{960,540},{1920,1080}};
  if(!glfwInit())throw new RuntimeException("glfwInit");
  glfwWindowHint(GLFW_VISIBLE,GLFW_FALSE);glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR,4);
  glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR,0);glfwWindowHint(GLFW_OPENGL_PROFILE,GLFW_OPENGL_COMPAT_PROFILE);
  long window=glfwCreateWindow(64,64,"Astra bloom LOD probe",0,0);glfwMakeContextCurrent(window);GL.createCapabilities();
  program=glCreateProgram();glAttachShader(program,shader(GL_VERTEX_SHADER,"#version 400 compatibility\nvoid main(){gl_Position=gl_Vertex;}"));
  glAttachShader(program,shader(GL_FRAGMENT_SHADER,Files.readString(Path.of(args[0]))));glLinkProgram(program);
  if(glGetProgrami(program,GL_LINK_STATUS)==0)throw new RuntimeException(glGetProgramInfoLog(program));
  glUseProgram(program);
  int fb=glGenFramebuffers();
  for(int[] r:res){
   int w=r[0],h=r[1];
   int target=glGenTextures();glBindTexture(GL_TEXTURE_2D,target);
   glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA32F,w,h,0,GL_RGBA,GL_FLOAT,(float[])null);
   glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);
   glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);
   glBindFramebuffer(GL_FRAMEBUFFER,fb);
   glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,target,0);
   for(int mode=0;mode<=5;mode++){
    int src=mipTexture(2,w,h);
    uf("viewWidth",w);uf("viewHeight",h);u1("probe",mode);
    glViewport(0,0,w,h);glDrawBuffer(GL_COLOR_ATTACHMENT0);glReadBuffer(GL_COLOR_ATTACHMENT0);
    glBegin(GL_TRIANGLES);glVertex2f(-1,-1);glVertex2f(1,-1);glVertex2f(1,1);glVertex2f(-1,-1);glVertex2f(1,1);glVertex2f(-1,1);glEnd();
    float[] result=new float[w*h*4];glReadPixels(0,0,w,h,GL_RGBA,GL_FLOAT,result);
    ByteBuffer bytes=ByteBuffer.allocate(result.length*4).order(ByteOrder.LITTLE_ENDIAN);
    for(float v:result)bytes.putFloat(v);
    Files.write(Path.of(args[1],w+"x"+h+"_"+mode+".f32"),bytes.array());
    glDeleteTextures(src);
   }
   glDeleteTextures(target);
  }
  System.out.println("Renderer: "+glGetString(GL_RENDERER));glfwDestroyWindow(window);glfwTerminate();
 }
}
'''


def decode(value):
    """getBloomTile returns pow((lambda/8)/256, 1/8); invert it to the mip level."""
    return 2048.0 * value ** 8


def decode_raw(value):
    """A direct colortex0 read returns R = level/8 without getBloomTile's pow."""
    return 8.0 * value


def predicted_lod(lod, view_height):
    """The derivative the taps produce: bloomCoord scales texCoord by F, so one
    screen pixel spans F*exp2(lod) texels and the trilinear level is log2 of that."""
    footprint = 0.8 * view_height / min(360.0, view_height)
    return lod + math.log2(footprint)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    shaders = ROOT / "Astra" / "shaders"
    profile = parse_profiles(shaders / "shaders.properties")["BALANCED"]
    with tempfile.TemporaryDirectory(prefix="astra-bloom-lod-") as td:
        temp = Path(td)
        fragment = temp / "probe.fsh"
        fragment.write_text(FRAGMENT, encoding="utf-8")
        fragment.write_text(Expander(shaders, profile).expand(fragment, root=True), encoding="utf-8")
        java = temp / "BloomLodProbe.java"
        java.write_text(JAVA, encoding="utf-8")
        cp = lwjgl_classpath(DEFAULT_MC_ROOT)
        subprocess.run(["javac", "-cp", cp, str(java)], check=True)
        run = subprocess.run(["java", "-cp", cp + ";" + str(temp), "BloomLodProbe",
                              str(fragment), str(OUT)], check=True,
                             capture_output=True, text=True)
    renderer = [line for line in run.stdout.splitlines() if line.startswith("Renderer: ")]

    # A pixel that is a factor-scale/32 fraction from the origin is inside every
    # tile region at any resolution; +2 keeps the whole 2x2 quad well inside.
    uv = 0.004
    # Mode 2's four channels are these per-pixel texel footprints; mode 3's are
    # these explicit levels. Both must come back as log2(footprint) and the level.
    FOOTPRINTS = (3.2, 4.8, 9.6, 25.6)
    LODDS = (1.5, 2.5, 3.5, 4.5)
    # Mode 4 and 5 tap these, stepping through the fractional part of one level, to
    # measure the probe's own readback error.
    POW_LEVELS = (2.0, 2.25, 2.5, 2.75)
    buffer = {}

    def load(width, height, mode):
        key = (width, height, mode)
        if key not in buffer:
            raw = (OUT / f"{width}x{height}_{mode}.f32").read_bytes()
            buffer[key] = struct.unpack("<" + "f" * (width * height * 4), raw)
        return buffer[key]

    def sample(width, height, mode, channel):
        x, y = int(uv * width) + 2, int(uv * height) + 2
        return load(width, height, mode)[(y * width + x) * 4 + channel]

    def footprint(view_height, lod):
        return 0.8 * view_height / min(360.0, view_height) * 2.0 ** lod

    levels = {}
    derivative_cal = {}
    encoding_cal = {}
    pow_cal = {}
    raw_cal = {}
    for width, height in RESOLUTIONS:
        key = f"{width}x{height}"
        levels[key] = {str(lod): round(decode(sample(width, height, 0, index)), 4)
                       for index, lod in enumerate((2.0, 3.0, 4.0, 5.0))}
        derivative_cal[key] = {str(k): round(decode_raw(sample(width, height, 2, index)), 4)
                               for index, k in enumerate(FOOTPRINTS)}
        encoding_cal[key] = {str(lod): round(decode_raw(sample(width, height, 3, index)), 4)
                             for index, lod in enumerate(LODDS)}
        pow_cal[key] = {str(lod): round(decode(sample(width, height, 4, index)), 4)
                        for index, lod in enumerate(POW_LEVELS)}
        raw_cal[key] = {str(lod): round(decode_raw(sample(width, height, 5, index)), 4)
                        for index, lod in enumerate(POW_LEVELS)}

    # The lod 3 region ends near here; each channel's real transition is read back
    # from the pixels, because whether it lands inside a 2x2 quad is the point.
    edge = int(1.0 / (0.8 * 1080 / min(360.0, 1080)) / 8.0 * 1920)
    y = int(uv * 1080) + 2
    row = load(1920, 1080, 1)
    deep = {}
    crossings = {}
    for channel, shift in enumerate((1.0, 1.25, 1.5, 1.75)):
        row_levels = {x: round(decode(row[(y * 1920 + x) * 4 + channel]), 4)
                      for x in range(edge - 6, edge + 5)}
        last_inside = max(pixel for pixel, level in row_levels.items() if level > 0.0)
        # The same predicate getBloomTile():15 evaluates, solved in python, to find
        # where the boundary should be before the GPU had a say.
        scale = 2.0 ** 3.0
        padding = 0.5 + 2.0 / 1920.0 * scale
        inside = [x for x in range(edge - 6, edge + 5)
                  if abs((x + 0.5 + shift) / 1920.0 * footprint(1080, 3.0) - 0.5) < padding]
        model_inside = max(inside)
        deep[str(shift)] = row_levels[edge - 6]
        crossings[str(shift)] = {
            "last_inside_pixel_expected": model_inside,
            "last_inside_pixel_measured": last_inside,
            # Quads are (2k, 2k+1), so an odd measured pixel means the branch flipped
            # on a quad edge: no quad had one lane inside and one outside.
            "transition_on_quad_edge": last_inside % 2 == 1,
            "level_at_transition": row_levels[last_inside],
            "levels": row_levels,
        }
    snapped = [shift for shift, v in crossings.items()
               if v["last_inside_pixel_expected"] != v["last_inside_pixel_measured"]]
    quad_aligned_only = all(v["transition_on_quad_edge"] for v in crossings.values())
    gated = [f"{width}x{height}:{lod}" for width, height in RESOLUTIONS
             for lod in (2.0, 3.0, 4.0, 5.0)
             if str(round(footprint(height, lod), 6)) in derivative_cal[f"{width}x{height}"]]
    # How far the tile's level sits from the level a plain implicit sample at the same
    # footprint picks, per gated pair. Both go through this probe's readback, so the
    # difference is the model's error and not the hardware's.
    cancellation_levels = {}
    for pair in gated:
        key, lod = pair.split(":")
        lod = float(lod)
        height = int(key.split("x")[1])
        step = str(round(footprint(height, lod), 6))
        cancellation_levels[pair] = round(levels[key][str(lod)] - derivative_cal[key][step], 4)
    # The readback's own error: mode 5 names an explicit level, so anything that comes
    # back other than that level is this probe, not the sampler. It taps a level and a
    # position outright, so it must read the same at every resolution.
    first_key = next(iter(raw_cal))
    assert all(calibration == raw_cal[first_key] for calibration in raw_cal.values()), raw_cal
    assert all(calibration == pow_cal[first_key] for calibration in pow_cal.values()), pow_cal
    readback_levels = {lod: round(raw_cal[first_key][lod] - float(lod), 4)
                       for lod in raw_cal[first_key]}

    result = {
        "scope": "Actual getBloomTile() against a per-level constant mipmap chain; "
                 "sampler behaviour only, not an Iris render",
        "renderer": renderer[0] if renderer else "not reported",
        "implicit_level": levels,
        "predicted_level": {f"{width}x{height}": {
            str(lod): round(predicted_lod(lod, height), 4)
            for lod in (2.0, 3.0, 4.0, 5.0)} for width, height in RESOLUTIONS},
        "naive_level": {lod: lod for lod in (2.0, 3.0, 4.0, 5.0)},
        "calibration_derivative": derivative_cal,
        "calibration_derivative_expected": {key: {
            str(k): round(math.log2(k), 4) for k in FOOTPRINTS} for key in derivative_cal},
        "calibration_encoding": encoding_cal,
        "calibration_encoding_expected": {key: {str(lod): lod for lod in LODDS}
                                          for key in encoding_cal},
        "calibration_pow": pow_cal,
        "calibration_pow_control": raw_cal,
        "calibration_pow_levels": {str(lod): lod for lod in POW_LEVELS},
        "footprint_gated_pairs": gated,
        "derivative_cancellation_levels": cancellation_levels,
        "readback_error_levels": readback_levels,
        "branch_transitions_on_quad_edge_only": quad_aligned_only,
        "shifts_the_driver_snapped": snapped,
        "region_edge_crossings_1920x1080": crossings,
    }
    (OUT / "results.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))

    # The encoding must round trip; that is what makes a decoded number a level.
    for key, measured in result["calibration_encoding"].items():
        for lod, level in measured.items():
            assert abs(level - float(lod)) < 0.05, (key, lod, level)
    # getBloomTile's return expression has to be neutral, or every decoded number in
    # this report is suspect: the same taps with and without the pow must agree.
    for key, measured in result["calibration_pow"].items():
        for lod, level in measured.items():
            assert abs(level - result["calibration_pow_control"][key][lod]) < 0.01, (key, lod, level)
    # What the trilinear readback costs: a level named outright must come back within
    # this much, so every other number here is only accurate to about a tenth of a
    # level. The error tracks the fractional part, not the resolution.
    assert max(abs(error) for error in result["readback_error_levels"].values()) < 0.15, result["readback_error_levels"]
    # The fixed-function LOD unit plus the readback: checked against log2(footprint)
    # with the same slack, because the readback error is in it too.
    for key, measured in result["calibration_derivative"].items():
        for k, level in measured.items():
            assert abs(level - result["calibration_derivative_expected"][key][k]) < 0.15, (key, k, level)
    # The load-bearing gate: the tile's level and a plain implicit sample at footprint
    # F*exp2(lod) are the same level, measured two different ways. Each goes through
    # the readback, and the step it resolves is 1/128 of a level, so the model's own
    # error has to be a few of those.
    for pair, delta in cancellation_levels.items():
        assert abs(delta) < 0.02, (pair, delta)
    for key, measured in result["implicit_level"].items():
        for lod, level in measured.items():
            assert abs(level - result["predicted_level"][key][lod]) < 0.15, (key, lod, level)
    # A naive textureLod(..., lod) replacement would sit log2(F) away from the level
    # the implicit read picks: 0.32 at the 270 and 360 heights, 0.26 at 540, 1.26 at
    # 1080. The largest gap is what a rewrite must not regress to.
    naive_gap = max(abs(level - float(lod))
                    for row in result["implicit_level"].values() for lod, level in row.items())
    assert naive_gap > 1.0, naive_gap
    # Resolution compensation is real: the same lod lands 1.39 levels apart between
    # the shortest and tallest tested height (1.585 analytically).
    span = [result["implicit_level"][f"{w}x{h}"]["3.0"] for w, h in RESOLUTIONS]
    assert max(span) - min(span) > 1.0, span
    # How the driver handles a quad that straddles the branch is what mode 1 is for.
    # While the taps derived their level there, the branch had to be evaluated per 2x2
    # quad for those derivatives to mean anything, and the boundary could land a pixel
    # away from where the predicate says (branch_transitions_on_quad_edge_only). Naming
    # a level frees the branch to run per pixel, so the boundary moves to the predicate
    # and a quad may straddle it. Either way the level must not move as the scanline
    # approaches that edge.
    for shift, crossing in crossings.items():
        assert abs(crossing["level_at_transition"] - deep[shift]) < 1e-3, (shift, crossing)
    assert len(set(deep.values())) == 1, deep
    assert next(iter(deep.values())) == levels["1920x1080"]["3.0"], deep

    if "--baseline" in sys.argv:
        baseline = json.loads(Path(sys.argv[sys.argv.index("--baseline") + 1]).read_text(encoding="utf-8"))
        # The probe resolves a level to 1/128 of a level (0.0078), so "the same level"
        # means the same number of twelfths; a tenth of a level would be 13 LSBs.
        tolerance = 0.02
        moved = {f"{key}:{lod}": round(level - baseline["implicit_level"][key][lod], 4)
                 for key, measured in result["implicit_level"].items()
                 for lod, level in measured.items()
                 if abs(level - baseline["implicit_level"][key][lod]) > 1e-4}
        for key, delta in moved.items():
            assert abs(delta) < tolerance, (key, delta)
        shifted = {}
        for shift, crossing in crossings.items():
            saved = baseline["region_edge_crossings_1920x1080"][shift]
            # The boundary may move when the branch stops being evaluated per quad; it
            # may move toward the predicate, never further away than the saved run did.
            assert abs(crossing["last_inside_pixel_measured"]
                       - crossing["last_inside_pixel_expected"]) <= abs(
                           saved["last_inside_pixel_measured"]
                           - saved["last_inside_pixel_expected"]), (shift, crossing, saved)
            if crossing["last_inside_pixel_measured"] != saved["last_inside_pixel_measured"]:
                shifted[shift] = [saved["last_inside_pixel_measured"],
                                  crossing["last_inside_pixel_measured"]]
            assert abs(crossing["level_at_transition"]
                       - saved["level_at_transition"]) < tolerance, shift
        result["baseline"] = {"file": sys.argv[sys.argv.index("--baseline") + 1],
                              "tolerance_levels": tolerance,
                              "level_deltas": moved,
                              "boundary_pixels_moved": shifted}
        (OUT / "results.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
        print(json.dumps(result["baseline"], indent=2))


if __name__ == "__main__":
    main()
