"""Read pack scheduling through the installed Iris parser, without starting Minecraft."""
from pathlib import Path
import subprocess
import tempfile
import zipfile
import re

ROOT = Path(__file__).resolve().parents[2]
MC = Path('D:/zhenhebao/.minecraft')
IRIS = MC / 'versions/生电优化整合包 (Fabric)/mods/iris-fabric-1.11.2+mc26.2.jar'
JDK = Path.home() / 'AppData/Roaming/.minecraft/runtime/java-runtime-epsilon/bin'
JAVA = '''
import java.nio.file.*;
import java.util.*;
import com.google.common.collect.ImmutableList;
import net.irisshaders.iris.shaderpack.include.*;
import net.irisshaders.iris.shaderpack.option.*;
import net.irisshaders.iris.shaderpack.preprocessor.PropertiesPreprocessor;
public class IrisPropertyInspection {
 public static void main(String[] args)throws Exception {
  Path root=Path.of(args[0]);
  var entries=ImmutableList.<AbsolutePackPath>builder();
  try(var files=Files.walk(root)) {files.filter(p->p.toString().endsWith(".fsh")||p.toString().endsWith(".vsh"))
    .filter(p->root.relativize(p).getNameCount()==1 || (root.relativize(p).getNameCount()==2 && root.relativize(p).getName(0).toString().startsWith("world")))
    .forEach(p->entries.add(AbsolutePackPath.fromAbsolutePath("/"+root.relativize(p).toString().replace('\\\\','/'))));}
  var graph=new IncludeGraph(root,entries.build(),false);
  if(!graph.getFailures().isEmpty())throw new RuntimeException(graph.getFailures().toString());
  var options=new ShaderPackOptions(graph,Map.of());
  String output=PropertiesPreprocessor.preprocessSource(Files.readString(root.resolve("shaders.properties")),options,List.of());
  Files.writeString(Path.of(args[1]),output);
  for(String line:output.split("\\n"))if(line.startsWith("program.composite")||line.startsWith("size.buffer")||line.startsWith("shadow."))System.out.println(line);
  var resolved = new java.util.Properties();
  resolved.load(new java.io.StringReader(output));
  var dimensions = resolved.getProperty("size.buffer.colortex6").split(" ");
  var scale = new net.irisshaders.iris.gl.texture.TextureScaleOverride(dimensions[0],dimensions[1]);
  System.out.println("Iris resolved colortex6: " + scale.getX(1920) + "x" + scale.getY(1080));
  if(scale.getX(1920)!=1 || scale.getY(1080)!=1)throw new AssertionError("Water-state buffer must be one pixel");
 }
}
'''

def main():
    with tempfile.TemporaryDirectory(prefix='astra-iris-properties-') as directory:
        temp = Path(directory)
        jars = [IRIS]
        with zipfile.ZipFile(IRIS) as archive:
            for name in archive.namelist():
                if name.endswith('.jar') and 'jcpp-' in name:
                    path = temp / Path(name).name
                    path.write_bytes(archive.read(name))
                    jars.append(path)
        for name in ('guava', 'failureaccess', 'slf4j-api', 'fastutil', 'gson', 'joml', 'lwjgl', 'lwjgl-opengl'):
            found = sorted(p for p in (MC / 'libraries').rglob(name + '-*.jar') if re.match(re.escape(name) + r'-\d', p.name))
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
        cp = ';'.join(str(p) for p in [temp, *jars])
        subprocess.run([str(JDK/'javac.exe'), '-cp', cp, str(stub), str(java)], check=True)
        result = subprocess.run([str(JDK/'java.exe'), '-cp', cp, 'IrisPropertyInspection', str(ROOT/'Astra/shaders'),
                                 str(ROOT/'qa/iris-properties-resolved.txt')], capture_output=True, text=True)
        print(result.stdout + result.stderr)
        return result.returncode

if __name__ == '__main__':
    raise SystemExit(main())
