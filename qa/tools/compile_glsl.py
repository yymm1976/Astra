#!/usr/bin/env python3
"""Compile and link Astra shader entry pairs in a hidden OpenGL 4.0 context.

This is intentionally separate from check_pack.py. It expands Iris-style absolute
includes, applies one shaders.properties profile at a time, injects only the Iris
preprocessor constants needed by Astra, then asks the installed OpenGL driver to
compile and link each vertex/fragment pair. It never starts or edits Minecraft.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from minecraft_paths import default_minecraft_root
from shader_options import ALL_PROFILES, declaration, parse_profiles as expand_profiles


DEFAULT_MC_ROOT = default_minecraft_root()
INCLUDE_RE = re.compile(r'^\s*#include\s+["<]([^">]+)[">]\s*(?://.*)?$')

# Values below are the ordinals of Iris 1.11.2's WorldRenderingPhase enum, read
# from the installed iris.jar (net/irisshaders/iris/pipeline/WorldRenderingPhase).
# Iris injects them as "MC_RENDER_STAGE_<NAME>"; a wrong ordinal makes a
# renderStage comparison silently never fire, so this table must be re-verified
# against the jar whenever the Iris version changes.
RENDER_STAGES = (
    "NONE", "SKY", "SUNSET", "CUSTOM_SKY", "SUN", "MOON", "STARS", "VOID",
    "TERRAIN_SOLID", "TERRAIN_CUTOUT_MIPPED", "TERRAIN_CUTOUT", "ENTITIES",
    "BLOCK_ENTITIES", "DESTROY", "OUTLINE", "DEBUG", "HAND_SOLID",
    "TERRAIN_TRANSLUCENT", "TRIPWIRE", "PARTICLES", "CLOUDS", "RAIN_SNOW",
    "WORLD_BORDER", "HAND_TRANSLUCENT",
)

IRIS_PREAMBLE = """\
#define MC_VERSION 260200
""" + "".join(
    f"#define MC_RENDER_STAGE_{name} {index}\n"
    for index, name in enumerate(RENDER_STAGES)
) + """\
#define MC_HAND_DEPTH 0.125
"""

JAVA_SOURCE = r"""
import java.nio.file.Files;
import java.nio.file.Path;
import static org.lwjgl.glfw.GLFW.*;
import org.lwjgl.glfw.GLFWErrorCallback;
import org.lwjgl.opengl.GL;
import static org.lwjgl.opengl.GL20.*;
import static org.lwjgl.opengl.GL11.*;
import static org.lwjgl.opengl.GL14.*;
import static org.lwjgl.opengl.GL43.*;

public final class AstraShaderCompiler {
    private static String sourceMap(String path) {
        try { return Files.readString(Path.of(path)); }
        catch (Exception e) { return "(source map unavailable: " + e + ")"; }
    }

    private static int compile(int type, String sourcePath, String mapPath,
                               String label, String stage) throws Exception {
        int shader = glCreateShader(type);
        glShaderSource(shader, Files.readString(Path.of(sourcePath)));
        glCompileShader(shader);
        String log = glGetShaderInfoLog(shader);
        if (glGetShaderi(shader, GL_COMPILE_STATUS) == GL_FALSE) {
            System.err.println("COMPILE_FAIL\t" + label + "\t" + stage);
            System.err.print(log);
            System.err.println("SOURCE_MAP\t" + label + "\t" + stage);
            System.err.print(sourceMap(mapPath));
            glDeleteShader(shader);
            return 0;
        }
        if (!log.isBlank()) {
            System.out.println("COMPILE_LOG\t" + label + "\t" + stage);
            System.out.print(log);
        }
        return shader;
    }

    public static void main(String[] args) throws Exception {
        GLFWErrorCallback.createPrint(System.err).set();
        if (!glfwInit()) throw new IllegalStateException("glfwInit failed");
        glfwDefaultWindowHints();
        glfwWindowHint(GLFW_VISIBLE, GLFW_FALSE);
        glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
        glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
        glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_COMPAT_PROFILE);
        long window = glfwCreateWindow(32, 32, "Astra GLSL compiler", 0L, 0L);
        if (window == 0L) {
            glfwDefaultWindowHints();
            glfwWindowHint(GLFW_VISIBLE, GLFW_FALSE);
            glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
            glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 0);
            glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_COMPAT_PROFILE);
            window = glfwCreateWindow(32, 32, "Astra GLSL compiler", 0L, 0L);
        }
        if (window == 0L) throw new IllegalStateException("OpenGL 4.3/4.0 compatibility context failed");
        glfwMakeContextCurrent(window);
        GL.createCapabilities();
        boolean computeCapable = org.lwjgl.opengl.GL.getCapabilities().OpenGL43;
        System.out.println("OPENGL_VENDOR\t" + glGetString(GL_VENDOR));
        System.out.println("OPENGL_RENDERER\t" + glGetString(GL_RENDERER));
        System.out.println("OPENGL_VERSION\t" + glGetString(GL_VERSION));

        int failed = 0;
        int linked = 0;
        int computeCount = 0;
        for (String row : Files.readAllLines(Path.of(args[0]))) {
            if (row.isBlank()) continue;
            String[] p = row.split("\t", -1);
            String label = p[0];
            String kind = p[1];
            if (kind.equals("cs")) {
                computeCount++;
                if (!computeCapable) {
                    System.err.println("COMPUTE_UNAVAILABLE\t" + label);
                    failed++;
                    continue;
                }
                int cs = compile(GL_COMPUTE_SHADER, p[2], p[3], label, "compute");
                if (cs == 0) { failed++; continue; }
                int program = glCreateProgram();
                glAttachShader(program, cs);
                glLinkProgram(program);
                String log = glGetProgramInfoLog(program);
                if (glGetProgrami(program, GL_LINK_STATUS) == GL_FALSE) {
                    System.err.println("LINK_FAIL\t" + label);
                    System.err.print(log);
                    failed++;
                } else {
                    if (!log.isBlank()) {
                        System.out.println("LINK_LOG\t" + label);
                        System.out.print(log);
                    }
                    linked++;
                }
                glDeleteProgram(program);
                glDeleteShader(cs);
                continue;
            }
            int vs = compile(GL_VERTEX_SHADER, p[2], p[3], label, "vertex");
            int fs = compile(GL_FRAGMENT_SHADER, p[4], p[5], label, "fragment");
            if (vs == 0 || fs == 0) {
                if (vs != 0) glDeleteShader(vs);
                if (fs != 0) glDeleteShader(fs);
                failed++;
                continue;
            }
            int program = glCreateProgram();
            glAttachShader(program, vs);
            glAttachShader(program, fs);
            glLinkProgram(program);
            String log = glGetProgramInfoLog(program);
            if (glGetProgrami(program, GL_LINK_STATUS) == GL_FALSE) {
                System.err.println("LINK_FAIL\t" + label);
                System.err.print(log);
                failed++;
            } else {
                if (!log.isBlank()) {
                    System.out.println("LINK_LOG\t" + label);
                    System.out.print(log);
                }
                linked++;
            }
            glDeleteProgram(program);
            glDeleteShader(vs);
            glDeleteShader(fs);
        }
        System.out.println("RESULT\tlinked=" + linked + "\tfailed=" + failed
            + "\tcompute=" + computeCount + "\tcompute_capable=" + computeCapable);
        glfwDestroyWindow(window);
        glfwTerminate();
        if (failed != 0) System.exit(1);
    }
}
"""


def parse_profiles(properties: Path) -> dict[str, dict[str, str | None]]:
    return expand_profiles(properties.read_text(encoding="utf-8-sig"))


def apply_profile_settings(text: str, values: dict[str, str | None]) -> str:
    output: list[str] = []
    seen: set[str] = set()
    for line in text.splitlines():
        item = declaration(line)
        if not item or item.name not in values or (item.const_type and not item.levels):
            output.append(line)
            continue
        indent, name = item.indent, item.name
        seen.add(name)
        value = values[name]
        # A profile token may enable or disable an option whose factory default is
        # the opposite, so the original commented/uncommented state is dropped here
        # in favour of the profile value.
        if item.const_type:
            if item.const_type == "bool":
                value = "false" if value is None else "true" if value == "" else value
            elif value is None or value == "":
                raise ValueError(f"const option {name} requires a numeric value")
            suffix = " " + item.comment if item.comment else ""
            output.append(f"{indent}const {item.const_type} {name} = {value};{suffix}")
        elif value is None:
            output.append(f"{indent}// profile disables {name}")
        elif value == "":
            output.append(f"{indent}#define {name}")
        else:
            suffix = " " + item.comment if item.comment else ""
            output.append(f"{indent}#define {name} {value}{suffix}")
    missing = sorted(set(values) - seen)
    if missing:
        raise ValueError("option not found in settings.glsl: " + ", ".join(missing))
    return "\n".join(output) + "\n"


class Expander:
    def __init__(self, shader_root: Path, profile: dict[str, str | None]):
        self.shader_root = shader_root
        self.profile = profile
        self.ids: dict[Path, int] = {}

    def source_id(self, path: Path) -> int:
        path = path.resolve()
        if path not in self.ids:
            self.ids[path] = len(self.ids) + 1
        return self.ids[path]

    def expand(self, path: Path, root: bool = False, stack: tuple[Path, ...] = ()) -> str:
        path = path.resolve()
        if path in stack:
            raise ValueError("recursive include: " + " -> ".join(map(str, stack + (path,))))
        text = path.read_text(encoding="utf-8-sig")
        if path.name == "settings.glsl":
            text = apply_profile_settings(text, self.profile)
        parent_id = self.source_id(path)
        output: list[str] = []
        injected = False
        for line_number, line in enumerate(text.splitlines(), 1):
            if root and line.startswith("#version"):
                output.append(line)
                output.append(IRIS_PREAMBLE.rstrip())
                output.append(f"#line {line_number + 1} {parent_id}")
                injected = True
                continue
            match = INCLUDE_RE.match(line)
            if not match:
                output.append(line)
                continue
            include = match.group(1)
            child = (self.shader_root / include.lstrip("/")) if include.startswith("/") else (path.parent / include)
            if not child.is_file():
                raise FileNotFoundError(f"{path}:{line_number}: include not found: {include}")
            child_id = self.source_id(child)
            output.append(f"#line 1 {child_id}")
            output.append(self.expand(child, stack=stack + (path,)).rstrip())
            output.append(f"#line {line_number + 1} {parent_id}")
        if root and not injected:
            raise ValueError(f"entry has no #version: {path}")
        return "\n".join(output) + "\n"

    def write_map(self, path: Path) -> None:
        inverse = sorted((number, source) for source, number in self.ids.items())
        path.write_text("".join(f"{number}\t{source}\n" for number, source in inverse), encoding="utf-8")


def entry_sources(shader_root: Path) -> tuple[list[tuple[str, Path, Path]], list[tuple[str, Path]]]:
    """Every entry Iris can load, split by kind.

    Vertex/fragment pairs come from .fsh files with a matching .vsh in the same
    directory. Compute entries are the .csh files Iris loads for the
    ShadowComposite stage (world-1/shadowcomp*.csh in this pack); they compile
    and link on their own, with no vertex/fragment partner.
    """
    pairs: list[tuple[str, Path, Path]] = []
    computes: list[tuple[str, Path]] = []
    for directory in (shader_root, shader_root / "world-1", shader_root / "world1"):
        for fragment in sorted(directory.glob("*.fsh")):
            vertex = fragment.with_suffix(".vsh")
            if vertex.is_file():
                pairs.append((fragment.relative_to(shader_root).as_posix(), vertex, fragment))
        for compute in sorted(directory.glob("*.csh")):
            computes.append((compute.relative_to(shader_root).as_posix(), compute))
    return pairs, computes


def lwjgl_classpath(mc_root: Path) -> str:
    base = mc_root / "libraries" / "org" / "lwjgl"
    jars = [
        base / "lwjgl" / "3.3.3" / "lwjgl-3.3.3.jar",
        base / "lwjgl" / "3.3.3" / "lwjgl-3.3.3-natives-windows.jar",
        base / "lwjgl-glfw" / "3.3.3" / "lwjgl-glfw-3.3.3.jar",
        base / "lwjgl-glfw" / "3.3.3" / "lwjgl-glfw-3.3.3-natives-windows.jar",
        base / "lwjgl-opengl" / "3.3.3" / "lwjgl-opengl-3.3.3.jar",
        base / "lwjgl-opengl" / "3.3.3" / "lwjgl-opengl-3.3.3-natives-windows.jar",
    ]
    missing = [str(path) for path in jars if not path.is_file()]
    if missing:
        raise FileNotFoundError("missing LWJGL files; use --minecraft-root or set "
                                "ASTRA_MC_ROOT to a Minecraft root with LWJGL 3.3.3:\n"
                                + "\n".join(missing))
    return ";".join(map(str, jars))


def expand_row(tag: str, values: dict, overrides: dict, pairs: list, computes: list,
               shader_root: Path, directory: Path) -> list[str]:
    """Write one option configuration's expanded sources, and return their manifest rows."""
    profile_values = dict(values)
    profile_values.update(overrides)
    rows: list[str] = []
    for label, vertex, fragment in pairs:
        safe = re.sub(r"[^A-Za-z0-9_.-]", "_", tag + "_" + label)
        vertex_out = directory / (safe + ".vsh")
        fragment_out = directory / (safe + ".fsh")
        vertex_map = directory / (safe + ".vmap")
        fragment_map = directory / (safe + ".fmap")
        expander = Expander(shader_root, profile_values)
        vertex_out.write_text(expander.expand(vertex, root=True), encoding="utf-8")
        expander.write_map(vertex_map)
        expander = Expander(shader_root, profile_values)
        fragment_out.write_text(expander.expand(fragment, root=True), encoding="utf-8")
        expander.write_map(fragment_map)
        rows.append("\t".join(map(str, (
            tag + ":" + label, "vf", vertex_out, vertex_map, fragment_out, fragment_map))))
    for label, compute in computes:
        safe = re.sub(r"[^A-Za-z0-9_.-]", "_", tag + "_" + label)
        compute_out = directory / (safe + ".csh")
        compute_map = directory / (safe + ".cmap")
        expander = Expander(shader_root, profile_values)
        compute_out.write_text(expander.expand(compute, root=True), encoding="utf-8")
        expander.write_map(compute_map)
        rows.append("\t".join(map(str, (
            tag + ":" + label, "cs", compute_out, compute_map))))
    return rows


def covering_array_rows(shader_root: Path, profiles: dict, selected: list[str],
                        max_rows: int) -> tuple[list, list[str], set]:
    """The option matrix as (tag, settings.glsl overrides) rows.

    option_matrix lives next to this file; the sys.path line keeps the import working
    when compile_glsl is imported as a module instead of run as a script. The selected
    profiles seed the rows so the selected shipping configurations are always part of the
    compiled set, not just an extra sweep.
    """
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import option_matrix

    space = option_matrix.option_space(shader_root)
    seeds = [{name: info["default"] for name, info in space["options"].items()}]
    seeds += [{name: option_matrix.levels_from_profile(profiles[tag], name, info)
               for name, info in space["options"].items()} for tag in selected]
    rows, uncovered = option_matrix.covering_array(space, seeds, max_rows)
    work: list[tuple[str, dict]] = []
    notes: list[str] = []
    for index, row in enumerate(rows, 1):
        tag = f"M{index:03d}"
        work.append((tag, {name: option_matrix.to_override(name, level, space["options"][name])
                           for name, level in row.items()}))
        changed = sorted(f"{name}={level}" for name, level in row.items()
                         if level != space["options"][name]["default"])
        notes.append(f"{tag}\t" + (", ".join(changed) if changed else "(all defaults)"))
    return work, notes, uncovered


def main() -> int:
    repo_root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--shaders", type=Path, default=repo_root / "Astra" / "shaders")
    parser.add_argument("--minecraft-root", type=Path, default=DEFAULT_MC_ROOT)
    parser.add_argument("--profiles", nargs="+", default=list(ALL_PROFILES),
                        help="profiles to compile; in --matrix mode these also seed the rows")
    parser.add_argument("--matrix", action="store_true",
                        help="compile a pairwise covering array over every option that can "
                             "change a preprocessor branch, instead of the plain profiles")
    parser.add_argument("--matrix-rows", type=int, default=0, metavar="N",
                        help="stop the covering array after N rows. A truncated matrix still "
                             "reports the pairs it missed and exits non-zero")
    parser.add_argument("--batch-rows", type=int, default=8, metavar="N",
                        help="option configurations per driver run and per temporary "
                             "directory; bounds disk use (default 8)")
    parser.add_argument("--jobs", type=int, default=1, metavar="N",
                        help="batches to compile at once; each worker costs one driver "
                             "JVM (a few hundred MB), so 3 is a sane ceiling when free "
                             "memory is tight (default 1)")
    parser.add_argument("--match", help="compile only entries whose relative path contains this text")
    parser.add_argument("--no-compute", action="store_true",
                        help="skip .csh entries, mirroring what Iris does when every "
                             "program.<world>/shadowcomp*.enabled condition is false")
    parser.add_argument("--undef", nargs="*", default=[], metavar="MACRO",
                        help="compile-time profile override: remove these option defines")
    parser.add_argument("--set", action="append", default=[], metavar="MACRO=VALUE",
                        help="compile-time profile override; may be repeated")
    parser.add_argument("--log", type=Path, help="write the driver output to this UTF-8 log")
    args = parser.parse_args()

    shader_root = args.shaders.resolve()
    profiles = parse_profiles(shader_root / "shaders.properties")
    selected = [name.upper() for name in args.profiles]
    unknown = [name for name in selected if name not in profiles]
    if unknown:
        raise ValueError("unknown profiles: " + ", ".join(unknown))
    overrides: dict[str, str | None] = {name: None for name in args.undef}
    for item in args.set:
        if "=" not in item:
            raise ValueError("--set requires MACRO=VALUE: " + item)
        name, value = item.split("=", 1)
        overrides[name] = value
    uncovered: set = set()
    notes: list[str] = []
    if args.matrix:
        work, notes, uncovered = covering_array_rows(
            shader_root, profiles, selected, args.matrix_rows)
    else:
        work = [(name, profiles[name]) for name in selected]
    pairs, computes = entry_sources(shader_root)
    if args.no_compute:
        computes = []
    if args.match:
        pairs = [pair for pair in pairs if args.match in pair[0]]
        computes = [entry for entry in computes if args.match in entry[0]]
    if not pairs and not computes:
        raise ValueError("no shader entries selected")
    if not work:
        raise ValueError("no option configurations to compile")
    if args.batch_rows < 1:
        raise ValueError("--batch-rows must be at least 1")

    # Resolve option declarations before reporting unrelated JDK/library errors.
    settings = (shader_root / "lib/settings.glsl").read_text(encoding="utf-8-sig")
    for _, values in work:
        apply_profile_settings(settings, {**values, **overrides})

    javac = shutil.which("javac")
    java = shutil.which("java")
    if not javac or not java:
        raise FileNotFoundError("java and javac must be on PATH")
    classpath = lwjgl_classpath(args.minecraft_root)

    with tempfile.TemporaryDirectory(prefix="astra-glsl-") as temp_name:
        temp = Path(temp_name)
        java_file = temp / "AstraShaderCompiler.java"
        java_file.write_text(JAVA_SOURCE, encoding="utf-8")
        subprocess.run([javac, "-cp", classpath, str(java_file)], check=True)

        chunks = [work[i:i + args.batch_rows] for i in range(0, len(work), args.batch_rows)]
        output: list[str] = [note + "\n" for note in notes]

        def run_batch(index: int, chunk: list) -> tuple[str, int]:
            # One directory per chunk, deleted as soon as the driver has consumed it: a
            # whole option matrix would otherwise sit on disk as ~1.5 GB of sources.
            batch = temp / f"batch{index}"
            batch.mkdir()
            manifest_rows: list[str] = []
            for tag, values in chunk:
                manifest_rows += expand_row(tag, values, overrides, pairs, computes,
                                            shader_root, batch)
            manifest = batch / "manifest.tsv"
            manifest.write_text("\n".join(manifest_rows) + "\n", encoding="utf-8")
            result = subprocess.run(
                [java, "-Dfile.encoding=UTF-8", "-cp", classpath + ";" + str(temp),
                 "AstraShaderCompiler", str(manifest)],
                text=True, encoding="utf-8", errors="replace", capture_output=True,
            )
            # stderr, flushed: a full matrix is a dozen driver batches, so a silent
            # process is indistinguishable from a stalled one without this.
            print(f"BATCH {index + 1}/{len(chunks)} rows={chunk[0][0]}..{chunk[-1][0]} "
                  f"rc={result.returncode}", file=sys.stderr, flush=True)
            shutil.rmtree(batch, ignore_errors=True)
            return result.stdout + result.stderr, result.returncode

        # Each batch is its own driver JVM, so batches parallelise. Results are
        # reassembled in batch order, which keeps the log identical either way.
        if args.jobs > 1:
            with ThreadPoolExecutor(max_workers=args.jobs) as pool:
                results = list(pool.map(lambda ic: run_batch(*ic), enumerate(chunks)))
        else:
            results = [run_batch(index, chunk) for index, chunk in enumerate(chunks)]
        status = 0
        for text, returncode in results:
            output.append(text)
            status = status or returncode

        text = "".join(output)
        if args.matrix:
            counts = re.findall(r"^RESULT\tlinked=(\d+)\tfailed=(\d+)", text, re.M)
            text += ("RESULT_ALL\tbatches=%d\trows=%d\tentries_per_row=%d\tlinked=%d\tfailed=%d\n"
                     % (len(chunks), len(work), len(pairs) + len(computes),
                        sum(int(linked) for linked, _ in counts),
                        sum(int(failed) for _, failed in counts)))
        if uncovered:
            first = min(uncovered)
            text += (f"COVERAGE_INCOMPLETE\t{len(uncovered)} pair(s) never compiled together,"
                     f" for example {first[0]}={first[1]} with {first[2]}={first[3]}\n")
            status = status or 1
        sys.stdout.write(text)
        if args.log:
            log_path = args.log if args.log.is_absolute() else repo_root / args.log
            log_path.parent.mkdir(parents=True, exist_ok=True)
            log_path.write_text(text, encoding="utf-8")
        return status


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"compile_glsl.py: {error}", file=sys.stderr)
        raise SystemExit(2)
