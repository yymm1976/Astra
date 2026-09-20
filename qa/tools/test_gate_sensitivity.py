"""Gate sensitivity: proves each anti-degradation check still fires.

check_pack.py reporting 0 FAIL says nothing by itself - a rule that cannot be broken
also cannot hold. Each scenario below copies the working pack into a temporary
directory, injects exactly one defect of the class survey 6 (P2-10, P2-11) watched a
reference pack ship or P2-18 watched this pack ship, and asserts the owning check
reports it and nothing else does. Two scenarios inject nothing: the pack as it stands,
and a prose mention of a buffer name, which is normal and must stay clean.

Usage:  python qa/tools/test_gate_sensitivity.py
Exit code = number of scenarios that did not behave as specified.
"""
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
ROOT = Path(tempfile.mkdtemp(prefix="astra-gate-"))
SHADERS = "Astra/shaders"
PROPS = f"{SHADERS}/shaders.properties"


def fresh(tag):
    dst = ROOT / tag
    shutil.copytree(REPO / "Astra", dst / "Astra")
    shutil.copytree(REPO / "qa" / "tools", dst / "qa" / "tools")
    src = REPO / "_analysis" / "Steadfast-0.8.0" / "shaders" / "shaders.properties"
    out = dst / "_analysis" / "Steadfast-0.8.0" / "shaders" / "shaders.properties"
    out.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, out)
    return dst


def patch(dst, rel, old, new):
    p = dst / rel
    text = p.read_text(encoding="utf-8")
    assert text.count(old) == 1, f"{rel}: anchor {old[:40]!r} found {text.count(old)}x"
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


def write(dst, rel, text):
    p = dst / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8")


MIT_BODY = ("/* Permission is hereby granted, free of charge, to any person obtaining a copy\n"
            "   of this software and associated documentation files. */\n")


def s0_baseline(dst):
    return None


def s1_block_comment_format(dst):
    patch(dst, f"{SHADERS}/lib/water_buffer_formats.glsl",
          "const int colortex7Format = RGBA16;",
          "/* const int colortex7Format = RGBA16; */")
    return ("14", "colortex7Format")


def s2_line_comment_clear(dst):
    patch(dst, f"{SHADERS}/lib/settings.glsl",
          "const vec4 colortex5ClearColor = vec4(0.0, 0.0, 0.0, 0.0);",
          "// const vec4 colortex5ClearColor = vec4(0.0, 0.0, 0.0, 0.0);")
    return ("14", "colortex5ClearColor")


def s3_phantom_buffer(dst):
    patch(dst, f"{SHADERS}/lib/water_buffer_formats.glsl",
          "const int colortex0Format = R11F_G11F_B10F;",
          "const int colortex0Format = R11F_G11F_B10F;\n"
          "const int colortex11Format = RGBA16F;")
    return ("14", "colortex11")


def s4_duplicate_clear(dst):
    patch(dst, f"{SHADERS}/lib/settings.glsl",
          "const vec4 colortex6ClearColor = vec4(0.0, 0.0, 0.0, 0.0);",
          "const vec4 colortex6ClearColor = vec4(0.0, 0.0, 0.0, 0.0);\n"
          "const vec4 colortex6ClearColor = vec4(0.0, 0.0, 0.0, 0.0);")
    return ("14", "colortex6ClearColor declared 2 times")


def s5_unregistered_vendor_file(dst):
    write(dst, f"{SHADERS}/lib/vendor/renderpearl/LICENSE.txt", "MIT licence text\n")
    return ("15", "vendor/renderpearl/LICENSE.txt")


def s6_vendor_dir_without_licence(dst):
    write(dst, f"{SHADERS}/lib/vendor/testup/README.md", "upstream: test\n")
    patch(dst, "Astra/THIRD-PARTY.md", "## 第三方隔离目录",
          "## 第三方隔离目录\n\n（测试注入）`shaders/lib/vendor/testup/` 已登记。\n")
    return ("15", "no licence text beside it")


def s7_licence_text_outside_vendor(dst):
    patch(dst, f"{SHADERS}/lib/tonemap.glsl", "vec3 reinhard_jodie(vec3 v) {",
          MIT_BODY + "vec3 reinhard_jodie(vec3 v) {")
    return ("15", "carries licence text")


def s8_prose_buffer_mention(dst):
    # control: naming a buffer in a comment is normal and must stay clean
    patch(dst, f"{SHADERS}/lib/water_buffer_formats.glsl",
          "const int colortex7Format = RGBA16;",
          "const int colortex7Format = RGBA16;\n"
          "// colortex12Format would be RGBA16F if anything ever wrote that buffer.")
    return None


def s9_namespaced_blend_key(dst):
    patch(dst, PROPS, "blend.shadow=off", "blend.shadow=off\nblend.world-1/shadow=off")
    return ("16", "blend.world-1/shadow")


def s10_root_gate_without_folder_mirror(dst):
    patch(dst, PROPS, "program.world1/shadow.enabled=SHADOWS\n", "")
    return ("16", "does not reach this folder")


def s11_gate_hidden_by_own_ifdef(dst):
    # the shape the pack shipped before P2-18: the gate only exists once the option is on
    patch(dst, PROPS, "program.world-1/shadowcomp.enabled=NETHER_VOXEL_LIGHT",
          "#ifdef NETHER_VOXEL_LIGHT\n"
          "program.world-1/shadowcomp.enabled=NETHER_VOXEL_LIGHT\n"
          "#endif")
    return ("16", "sits inside a NETHER_VOXEL_LIGHT branch")


def s12_gate_names_missing_pass(dst):
    patch(dst, PROPS, "program.world1/deferred1.enabled=true",
          "program.world1/deferred1.enabled=true\n"
          "program.world-1/gbuffers_nonexistent.enabled=true")
    return ("16", "exists in neither world-1/ nor the pack root")


def s13_gate_names_unknown_folder(dst):
    patch(dst, PROPS, "program.world1/prepare.enabled=true",
          "program.world1/prepare.enabled=true\n"
          "program.world9/composite.enabled=true")
    return ("16", "unknown dimension folder world9")


SCENARIOS = [
    ("baseline-no-defect", s0_baseline, None),
    ("prose-buffer-mention-control", s8_prose_buffer_mention, None),
    ("block-commented-colortex7Format", s1_block_comment_format, ("14", "colortex7Format")),
    ("line-commented-colortex5ClearColor", s2_line_comment_clear, ("14", "colortex5ClearColor")),
    ("phantom-buffer-colortex11", s3_phantom_buffer, ("14", "colortex11")),
    ("duplicate-colortex6ClearColor", s4_duplicate_clear, ("14", "colortex6ClearColor declared 2 times")),
    ("vendor-file-absent-from-ledger", s5_unregistered_vendor_file, ("15", "vendor/renderpearl/LICENSE.txt")),
    ("vendor-dir-without-licence", s6_vendor_dir_without_licence, ("15", "no licence text beside it")),
    ("licence-text-outside-vendor", s7_licence_text_outside_vendor, ("15", "carries licence text")),
    ("namespaced-blend-key", s9_namespaced_blend_key, ("16", "blend.world-1/shadow")),
    ("root-gate-without-folder-mirror", s10_root_gate_without_folder_mirror,
     ("16", "does not reach this folder")),
    ("gate-hidden-by-own-ifdef", s11_gate_hidden_by_own_ifdef,
     ("16", "sits inside a NETHER_VOXEL_LIGHT branch")),
    ("gate-names-missing-pass", s12_gate_names_missing_pass,
     ("16", "exists in neither world-1/ nor the pack root")),
    ("gate-names-unknown-folder", s13_gate_names_unknown_folder,
     ("16", "unknown dimension folder world9")),
]


def run(dst):
    proc = subprocess.run([sys.executable, str(dst / "qa" / "tools" / "check_pack.py")],
                          capture_output=True, text=True, encoding="utf-8", errors="replace")
    fails = re.findall(r"^\[FAIL\] #(\d+) (.*)$", proc.stdout, re.M)
    details = re.findall(r"^       - (.*)$", proc.stdout, re.M)
    return proc.returncode, fails, details


bad = 0
for name, inject, expect in SCENARIOS:
    dst = fresh(re.sub(r"[^a-z0-9]+", "-", name))
    applied = inject(dst)
    assert applied == expect, f"{name}: scenario did not apply as written"
    code, fails, details = run(dst)
    collateral = [f"{cid} {title[:60]}" for cid, title in fails if cid not in ("14", "15", "16")]
    if expect is None:
        ok = code == 0 and not fails
        detail = "0 FAIL" if ok else f"{len(fails)} FAIL"
    else:
        cid, needle = expect
        hit = next((d for d in details if needle in d), None)
        ok = any(cid == f for f, _ in fails) and hit is not None
        detail = f"fired #{cid}: {(hit or 'message not found')[:120]}"
    if collateral:
        detail += " | collateral: " + "; ".join(collateral)
    bad += 0 if ok else 1
    print(("PASS    " if ok else "MISFIRE ") + f"{name:38s} exit={code} {detail}")

shutil.rmtree(ROOT, ignore_errors=True)
print(f"\n{len(SCENARIOS) - bad}/{len(SCENARIOS)} scenario(s) behaved as specified")
sys.exit(1 if bad else 0)
