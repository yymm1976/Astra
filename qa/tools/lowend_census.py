"""Machine census across low-end reference packs and Astra.

Counts only what is directly comparable from source text: entry points, buffer
format/size declarations, stage-enable expressions, draw-buffer fan-out and file
size. It is a locator for reading, not an instruction count and not a timing.
"""
import os, re, sys, glob, json

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PACKS = {
    'Astra': 'Astra/shaders',
    'Steadfast': '_analysis/Steadfast-0.8.0/shaders',
    'Mellow': '_analysis/Mellow Shader v3.4/shaders',
    'Miniature': '_analysis/refs-2026-09-24/miniature-shader/shaders',
    'MakeUp-UF': '_analysis/lowend-refs-2026-09-25/makeup-ultra-fast-shaders/shaders',
    'Sildur-Fast': '_analysis/low-end-2026-09-25/sildur-fast/shaders',
    'Sildur-Vibrant': '_analysis/lowend-refs-2026-09-25/sildurs-vibrant-shaders/shaders',
    'Potato': '_analysis/lowend-refs-2026-09-25/potato-shaders/shaders',
    'Bloop': '_analysis/lowend-refs-2026-09-25/bloop-shaders/shaders',
    'Lite': '_analysis/lowend-refs-2026-09-25/lite-shaders/shaders',
    'Pegasus': '_analysis/lowend-refs-2026-09-25/pegasus/shaders',
    'RenderPearl': '_analysis/lowend-refs-2026-09-25/renderpearl/shaders',
    'BuildersQoL': '_analysis/lowend-refs-2026-09-25/builders-qol-shaders/shaders',
    'SimplyUpscaled': '_analysis/lowend-refs-2026-09-25/simply-upscaled/shaders',
    'SoftVoxelsLite': '_analysis/lowend-refs-2026-09-25/soft-voxels-lite/shaders',
    'ReShaded': '_analysis/lowend-refs-2026-09-25/re-shaded',
    'JustColoredLight': '_analysis/lowend-refs-2026-09-25/just-colored-lighting/shaders',
    'FastPBR': '_analysis/refs-2026-09-24/fastpbr/shaders',
    'Shrimple': '_analysis/refs-2026-09-24/shrimple/shaders',
}

STAGE = re.compile(r'^(gbuffers_|deferred|composite|final|shadow|prepare|begin)', re.I)


def read(p):
    try:
        return open(p, encoding='utf-8', errors='ignore').read()
    except OSError:
        return ''


def census(name, rel):
    d = os.path.join(ROOT, rel)
    if not os.path.isdir(d):
        return None
    files = [f for f in glob.glob(d + '/**/*', recursive=True) if os.path.isfile(f)]
    src = [f for f in files if f.lower().endswith(('.fsh', '.vsh', '.csh', '.glsl'))]
    props_path = os.path.join(d, 'shaders.properties')
    props = read(props_path)
    alltext = '\n'.join(read(f) for f in src)

    # entry points = stage-named files at any level
    entries = {os.path.basename(f).split('.')[0] for f in src
               if STAGE.match(os.path.basename(f))}

    fmt = set(re.findall(r'colortex(\d+)Format\s*=\s*([A-Za-z0-9_]+)', alltext))
    sized = set(re.findall(r'size\.buffer\.(\S+?)\s*=\s*([0-9.]+ [0-9.]+)', props))
    # downsampled distinct buffers
    # A fixed 316x1 End LUT is not a fractional-resolution render target; its texels
    # are per-consumer records (slot 0 alone runs the disc sampling), not a scaled grid.
    ds = {b for b, s in sized if all(0.0 < float(x) < 1.0 for x in s.split())}
    enabled = re.findall(r'^program\.(\S+?)\.enabled\s*=\s*(.+)$', props, re.M)
    tiers = re.findall(r'^profile\.(\S+?)=', props, re.M)
    uniform_lines = len(re.findall(r'^(?:uniform|variable)\.', props, re.M))

    # draw-buffer fan-out: max number of attachments written by one stage
    fanout = 0
    for f in src:
        t = read(f)
        for m in re.finditer(r'RENDERTARGETS:\s*([0-9,\s]+)', t):
            n = len([x for x in m.group(1).split(',') if x.strip()])
            fanout = max(fanout, n)
        for m in re.finditer(r'DRAWBUFFERS:\s*([0-9,\s]+)', t):
            # Legacy DRAWBUFFERS lists single-digit indices without commas:
            # "067" writes three attachments, not one.
            n = len(re.findall(r'\d', m.group(1)))
            fanout = max(fanout, n)

    lines = 0
    for f in src:
        lines += read(f).count('\n')

    return dict(name=name, src_files=len(src), entries=len(entries), glsl_lines=lines,
                fmt_decls=len(fmt), downsampled=len(ds), ds_list=sorted(ds)[:8],
                enabled_rules=len(enabled), tiers=len(tiers),
                uniform_expr=uniform_lines, max_fanout=fanout,
                props_bytes=len(props))


rows = []
for n, r in PACKS.items():
    c = census(n, r)
    if c:
        rows.append(c)
    else:
        rows.append(dict(name=n, missing=True))

hdr = f"{'pack':<17}{'src':>5}{'entry':>6}{'lines':>7}{'fmt':>5}{'ds':>4}{'enabl':>6}{'tier':>5}{'unif':>6}{'fan':>4}"
print(hdr)
print('-' * len(hdr))
for r in rows:
    if r.get('missing'):
        print(f"{r['name']:<17}  (not found)")
        continue
    print(f"{r['name']:<17}{r['src_files']:>5}{r['entries']:>6}{r['glsl_lines']:>7}"
          f"{r['fmt_decls']:>5}{r['downsampled']:>4}{r['enabled_rules']:>6}"
          f"{r['tiers']:>5}{r['uniform_expr']:>6}{r['max_fanout']:>4}")

print()
print('=== downsampled buffers per pack ===')
for r in rows:
    if r.get('missing'):
        continue
    print(f"{r['name']:<17} {r['ds_list']}")
