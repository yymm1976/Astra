"""Read pack scheduling through the installed Iris parser, without starting Minecraft.

Two things come out of one run:

  * the raw-default resolution (what a fresh install gets) - written to
    qa/iris-properties-resolved.txt, the checked-in snapshot;
  * the per-TIER resolution. shaders.properties conditions buffer scales, pass gates and
    blend state on option macros, so each profile is fed through Iris's own
    PropertiesPreprocessor and the resulting schedule is compared. This is the survey 6
    P0-1 gate: a ladder only counts if picking a tier actually changes what the loader
    schedules, and the token lists in shaders.properties cannot show that.

Iris does the interpreting, not this file. Boolean pass gates are resolved with
ShaderPackOptions.getOptionValues(), and every profile token is echoed back through the
same store, so a token the loader would reject cannot slip through unnoticed. Nothing here
emulates #if expansion either - that is the shipped iris-fabric jar.
"""
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]
PACK = ROOT / "Astra" / "shaders"
MC = Path('D:/zhenhebao/.minecraft')
IRIS = MC / 'versions/生电优化整合包 (Fabric)/mods/iris-fabric-1.11.2+mc26.2.jar'
JDK = Path.home() / 'AppData/Roaming/.minecraft/runtime/java-runtime-epsilon/bin'
TIER_ORDER = ("PERFORMANCE", "BALANCED", "ULTRA")
JAVA = '''
import java.nio.file.*;
import java.util.*;
import com.google.common.collect.ImmutableList;
import net.irisshaders.iris.shaderpack.include.*;
import net.irisshaders.iris.shaderpack.option.*;
import net.irisshaders.iris.shaderpack.preprocessor.PropertiesPreprocessor;
public class IrisPropertyInspection {
 static Map<String,String> read(Path file)throws Exception {
  Map<String,String> map=new LinkedHashMap<>();
  for(String line:Files.readAllLines(file)){int i=line.indexOf('=');
   if(i>0)map.put(line.substring(0,i).trim(),line.substring(i+1).trim());}
  return map;
 }
 static Properties resolved(String output)throws Exception {
  Properties properties=new Properties();
  properties.load(new java.io.StringReader(output));
  return properties;
 }
 static boolean truthy(String value){return value.equals("true")||value.equals("1");}
 // A gate value is either a literal or, as with program.composite1.enabled=BLOOM, the name
 // of an option. Iris's own program loader resolves the second form; so does this.
 static String gate(ShaderPackOptions options,String value){
  if(value.equals("true")||value.equals("false")||value.equals("1")||value.equals("0"))
   return String.valueOf(truthy(value));
  return String.valueOf(options.getOptionValues().getBooleanValueOrDefault(value));
 }
 static void dump(String label,ShaderPackOptions options,String output,Map<String,String> wanted)throws Exception {
  System.out.println("===TIER "+label);
  Properties properties=resolved(output);
  for(String key:new TreeSet<>(properties.stringPropertyNames())) {
   String value=properties.getProperty(key);
   if(key.endsWith(".enabled")) {
    // Iris has a parser for the "program." family and for nothing else that ends in
    // ".enabled"; any other spelling is never read at load time.
    if(key.startsWith("program."))
     System.out.println("GATE "+key+"="+value+" EFFECTIVE="+gate(options,value));
    else System.out.println("DEADGATE "+key+"="+value);
   }
   else if(key.startsWith("size.buffer."))System.out.println("BUFFER "+key+"="+value);
  }
  // Echo every profile token back through the store the loader will read. A name Iris
  // never discovered is inert no matter what shaders.properties says about it.
  var bools=options.getOptionSet().getBooleanOptions();
  var strs=options.getOptionSet().getStringOptions();
  var values=options.getOptionValues();
  for(String name:new TreeSet<>(wanted.keySet())) {
   String kind=bools.containsKey(name)?"bool":(strs.containsKey(name)?"str":"unknown");
   String value=kind.equals("bool")?String.valueOf(values.getBooleanValueOrDefault(name))
    :(kind.equals("str")?values.getStringValueOrDefault(name):"");
   System.out.println("OVERRIDE "+name+" wanted="+wanted.get(name)+" kind="+kind+" value="+value);
  }
 }
 public static void main(String[] args)throws Exception {
  Path root=Path.of(args[0]);
  var entries=ImmutableList.<AbsolutePackPath>builder();
  try(var files=Files.walk(root)) {files.filter(p->p.toString().endsWith(".fsh")||p.toString().endsWith(".vsh"))
    .filter(p->root.relativize(p).getNameCount()==1 || (root.relativize(p).getNameCount()==2 && root.relativize(p).getName(0).toString().startsWith("world")))
    .forEach(p->entries.add(AbsolutePackPath.fromAbsolutePath("/"+root.relativize(p).toString().replace('\\\\','/'))));}
  var graph=new IncludeGraph(root,entries.build(),false);
  if(!graph.getFailures().isEmpty())throw new RuntimeException(graph.getFailures().toString());
  String source=Files.readString(root.resolve("shaders.properties"));
  // Raw defaults first: this is the snapshot the repository keeps.
  ShaderPackOptions defaults=new ShaderPackOptions(graph,Map.of());
  String defaultOutput=PropertiesPreprocessor.preprocessSource(source,defaults,List.of());
  // What the loader can actually toggle. A #define with a value list that never shows up
  // here is inert: the GUI has no row for it and no profile token can change it.
  for(String name:new TreeSet<>(defaults.getOptionSet().getBooleanOptions().keySet()))
   System.out.println("KNOWN bool="+name);
  for(String name:new TreeSet<>(defaults.getOptionSet().getStringOptions().keySet()))
   System.out.println("KNOWN str="+name);
  Files.writeString(Path.of(args[1]),defaultOutput);
  List<Path> tierFiles;
  try(var listing=Files.list(Path.of(args[2]))) {tierFiles=listing.sorted().toList();}
  for(Path file:tierFiles) {
   Map<String,String> wanted=read(file);
   ShaderPackOptions options=new ShaderPackOptions(graph,wanted);
   dump(file.getFileName().toString().replace(".options",""),options,
    PropertiesPreprocessor.preprocessSource(source,options,List.of()),wanted);
  }
  String[] dimensions = resolved(defaultOutput).getProperty("size.buffer.colortex6").split(" ");
  var scale = new net.irisshaders.iris.gl.texture.TextureScaleOverride(dimensions[0],dimensions[1]);
  System.out.println("Iris resolved colortex6: " + scale.getX(1920) + "x" + scale.getY(1080));
  if(scale.getX(1920)!=1 || scale.getY(1080)!=1)throw new AssertionError("Water-state buffer must be one pixel");
 }
}
'''


def profiles():
    """profile name -> {option: 'true' | 'false' | value}, as Iris stores overrides"""
    out = {}
    for line in (PACK / "shaders.properties").read_text(encoding="utf-8").splitlines():
        m = re.match(r"^profile\.([A-Z]+)=(.*)$", line)
        if not m:
            continue
        tokens = {}
        for token in m.group(2).split():
            if token.startswith("!"):
                tokens[token[1:]] = "false"
            elif "=" in token:
                name, raw = token.split("=", 1)
                tokens[name] = raw
            else:
                tokens[token] = "true"
        out[m.group(1)] = tokens
    return out


def parse_output(stdout):
    """tier -> (gates, buffers, echoes, dead gates), plus the option names the loader discovered"""
    tiers, known = {}, {"bool": set(), "str": set()}
    current = None
    for line in stdout.splitlines():
        kind, _, body = line.partition(" ")
        if kind == "===TIER":
            current = body.strip()
            tiers[current] = ({}, {}, {}, set())
        elif kind == "KNOWN":
            name, _, value = body.partition("=")
            known[name].add(value)
        elif current:
            gates, buffers, echoes, dead = tiers[current]
            if kind == "GATE":
                key, _, rest = body.partition("=")
                gates[key] = rest.partition("EFFECTIVE=")[2]
            elif kind == "DEADGATE":
                dead.add(body.partition("=")[0])
            elif kind == "BUFFER":
                key, _, value = body.partition("=")
                buffers[key] = value
            elif kind == "OVERRIDE":
                echoes[body.split(" ", 1)[0]] = (
                    body.partition("wanted=")[2].partition(" ")[0],
                    body.partition("kind=")[2].partition(" ")[0],
                    body.partition("value=")[2])
    return tiers, known


def declared_options():
    """lib/settings.glsl declarations: name -> 'bool' | 'str', as its value list says"""
    out = {}
    pattern = re.compile(r"^\s*(?://)?\s*#define\s+([A-Za-z_]\w*)\b.*//\s*\[(.*)\]\s*$")
    for line in (PACK / "lib/settings.glsl").read_text(encoding="utf-8").splitlines():
        m = pattern.match(line)
        if m:
            out[m.group(1)] = "bool" if set(m.group(2).split()) == {"false", "true"} else "str"
    return out


def main():
    prof = profiles()
    absent = [t for t in TIER_ORDER if t not in prof]
    if absent:
        print(f"FAIL profile(s) absent from shaders.properties: {absent}")
        return 1
    failures = []
    with tempfile.TemporaryDirectory(prefix='astra-iris-properties-') as directory:
        temp = Path(directory)
        jars = [IRIS]
        with zipfile.ZipFile(IRIS) as archive:
            for name in archive.namelist():
                if name.endswith('.jar') and 'jcpp-' in name:
                    path = temp / Path(name).name
                    path.write_bytes(archive.read(name))
                    jars.append(path)
        for name in ('guava', 'failureaccess', 'slf4j-api', 'fastutil', 'gson', 'joml',
                     'lwjgl', 'lwjgl-opengl'):
            found = sorted(p for p in (MC / 'libraries').rglob(name + '-*.jar')
                           if re.match(re.escape(name) + r'-\d', p.name))
            if found:
                jars.append(found[-1])
        # Only replace the game singleton/logging entry point. The parser, option
        # scanner and include graph are the installed Iris classes, unchanged.
        stub = temp / 'net/irisshaders/iris/Iris.java'
        stub.parent.mkdir(parents=True)
        stub.write_text('''package net.irisshaders.iris;
public class Iris {
 public static final IrisLogging logger = new IrisLogging("AstraParser");
 private static final net.irisshaders.iris.config.IrisConfig config =
  new net.irisshaders.iris.config.IrisConfig(java.nio.file.Path.of("unused.properties"), java.nio.file.Path.of("unused.json"));
 public static net.irisshaders.iris.config.IrisConfig getIrisConfig(){return config;}
}''', encoding='utf-8')
        java = temp / 'IrisPropertyInspection.java'
        java.write_text(JAVA, encoding='utf-8')
        tiers_dir = temp / 'tiers'
        tiers_dir.mkdir()
        for name, tokens in prof.items():
            (tiers_dir / f"{name}.options").write_text(
                "\n".join(f"{k}={v}" for k, v in tokens.items()), encoding="utf-8")
        cp = ';'.join(str(p) for p in [temp, *jars])
        subprocess.run([str(JDK/'javac.exe'), '-cp', cp, str(stub), str(java)],
                       check=True)
        result = subprocess.run(
            [str(JDK/'java.exe'), '-cp', cp, 'IrisPropertyInspection', str(PACK),
             str(ROOT / 'qa/iris-properties-resolved.txt'), str(tiers_dir)],
            capture_output=True, text=True)
        print(result.stdout + result.stderr)
        if result.returncode:
            return result.returncode
        tiers, known = parse_output(result.stdout)

    parsed = {t: tiers.get(t, ({}, {}, {}, set())) for t in TIER_ORDER}
    gates = {t: parsed[t][0] for t in TIER_ORDER}
    buffers = {t: parsed[t][1] for t in TIER_ORDER}
    on = {t: {k for k, v in gates[t].items() if v == "true"} for t in TIER_ORDER}
    if not all(gates[t] for t in TIER_ORDER):
        failures.append("the parser returned no pass gates for at least one tier")
    # A gate spelled outside the program.* family is not a gate: the loader never sees it,
    # so the pass runs in every tier while the properties file says otherwise.
    dead = sorted({k for t in TIER_ORDER for k in parsed[t][3]})
    if dead:
        failures.append("gate-shaped key(s) Iris never reads, so the pass dispatches in every "
                        "tier: " + ", ".join(dead))

    # 0. A #define with a value list is only an option if the loader found it.
    declared = declared_options()
    inert = sorted(f"{name} ({kind})" for name, kind in declared.items()
                   if name not in known[kind])
    print(f"{len(declared)} option(s) declared in lib/settings.glsl, "
          f"{len(known['bool'])} boolean + {len(known['str'])} string discovered by Iris")
    if inert:
        failures.append("declared but never discovered by the loader, so no GUI row and no "
                        "profile token can change it: " + ", ".join(inert))

    # 1. Every profile token must survive into the option store the loader reads.
    unknown, mismatched = set(), []
    for tier in TIER_ORDER:
        for name, (wanted, kind, value) in sorted(parsed[tier][2].items()):
            if kind == "unknown":
                unknown.add(name)
            elif value != wanted:
                mismatched.append(f"{tier}: {name}={wanted} resolves to {value!r}")
    if unknown:
        failures.append("profile token(s) for a name Iris never discovered, so they cannot "
                        "take effect at load time: " + ", ".join(sorted(unknown)))
    for message in mismatched:
        failures.append(message + " - the profile token does not take effect at load time")
    accepted = sum(len(parsed[t][2]) for t in TIER_ORDER)
    print(f"checked {accepted} profile option assignment(s) against the Iris option store")

    # 2. The ladder must only add work, never swap features between tiers.
    for cheap, rich in zip(TIER_ORDER, TIER_ORDER[1:]):
        dropped = {k for k in on[cheap] if k not in on[rich]}
        added = {k for k in on[rich] if k not in on[cheap]}
        print(f"{cheap} -> {rich}: +{len(added)} gate(s) on, -{len(dropped)} "
              f"| {len(on[rich])} on in {rich}")
        if dropped:
            failures.append(f"{cheap} runs pass(es) {rich} does not: "
                            + ", ".join(sorted(dropped)))
        if added:
            print(f"     added: " + ", ".join(sorted(added)))

    # 3. Canary: colortex1 is conditioned on UNDERWATER_SHAFT_SAMPLES, so an option map
    #    that never reached the preprocessor would leave all three tiers on one scale.
    scales = {t: buffers[t].get("size.buffer.colortex1") for t in TIER_ORDER}
    print("size.buffer.colortex1 by tier: " + " | ".join(f"{t}={scales[t]}" for t in TIER_ORDER))
    if len(set(scales.values())) < 2:
        failures.append("size.buffer.colortex1 did not vary by tier - either the "
                        "#if is inert or the per-tier option map was ignored")
    varied = {k for k in buffers["BALANCED"]
              if len({b.get(k) for b in buffers.values()}) > 1}
    print(f"size.buffer keys varying by tier: "
          + (", ".join(sorted(varied)) if varied else "none"))
    if not varied:
        failures.append("no size.buffer.* line varies across the three tiers")

    # 4. Picking a tier must change what the loader schedules. A step that changes neither
    #    a gate nor a buffer is knob-only (cost lives in the GLSL macros) and is reported,
    #    not failed, because the pack has no richer pass to promote at that step; the
    #    knob side of the same claim is gated by check_pack.py tier differential.
    for cheap, rich in zip(TIER_ORDER, TIER_ORDER[1:]):
        schedule_differs = on[cheap] != on[rich] or buffers[cheap] != buffers[rich]
        if not schedule_differs:
            print(f"NOTE {cheap} -> {rich} schedules identically; only shader-side cost "
                  f"knobs differ (gated by check_pack.py)")
    if on["PERFORMANCE"] == on["ULTRA"] and buffers["PERFORMANCE"] == buffers["ULTRA"]:
        failures.append("PERFORMANCE and ULTRA schedule the same work - the tier system is inert")

    for message in failures:
        print("FAIL " + message)
    print(f"{len(failures)} tier-differential failure(s)")
    return len(failures)


if __name__ == '__main__':
    raise SystemExit(main())
