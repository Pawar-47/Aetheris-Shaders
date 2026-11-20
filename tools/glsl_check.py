#!/usr/bin/env python3
"""Compile every program with glslangValidator, after undoing what Iris does to it.

Iris rewrites `#version 330 compatibility` into core and replaces the legacy built-ins
(`gl_Vertex`, `gl_ModelViewMatrix`, `gl_MultiTexCoord0`, ...) with its own attributes and
uniforms. glslangValidator knows nothing about any of that, which is why this pack has never
been compiled before a release: a generic validator rejects it for reasons that say nothing
about whether it works.

This script performs the minimum of the same rewrite itself, so what glslang ends up seeing
is ordinary GLSL 3.30 core:

  1. `#include` is resolved, exactly as Iris resolves it.
  2. `#version 330 compatibility` becomes `#version 330 core`.
  3. Each legacy built-in is renamed to a plain identifier and declared.

Everything else is the pack's own code, now parsed and type checked by a real compiler. That
is the check that was missing: it catches syntax errors such as `vec3 flat` (flat is a
reserved interpolation qualifier in GLSL 3.30), undefined functions, wrong argument counts
and type mismatches — before a release rather than after one.

If glslangValidator is not installed the script says so and exits 0, so it is harmless
outside CI, where the workflow installs it.
"""

import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import validate  # noqa: E402  (needs the path shim above)

SHADERS = validate.SHADERS

# Longest first: gl_ModelViewMatrix must not be rewritten inside gl_ModelViewProjectionMatrix.
LEGACY = [
    ("gl_ModelViewProjectionMatrix", "iris_ModelViewProjectionMatrix", "mat4"),
    ("gl_ModelViewMatrixInverse", "iris_ModelViewMatrixInverse", "mat4"),
    ("gl_ProjectionMatrixInverse", "iris_ProjectionMatrixInverse", "mat4"),
    ("gl_ModelViewMatrix", "iris_ModelViewMatrix", "mat4"),
    ("gl_ProjectionMatrix", "iris_ProjectionMatrix", "mat4"),
    ("gl_NormalMatrix", "iris_NormalMatrix", "mat3"),
    ("gl_TextureMatrix", "iris_TextureMatrix", "mat4[8]"),
    ("gl_MultiTexCoord0", "iris_MultiTexCoord0", "vec4"),
    ("gl_MultiTexCoord1", "iris_MultiTexCoord1", "vec4"),
    ("gl_MultiTexCoord2", "iris_MultiTexCoord2", "vec4"),
    ("gl_MultiTexCoord3", "iris_MultiTexCoord3", "vec4"),
    ("gl_Color", "iris_Color", "vec4"),
    ("gl_Normal", "iris_Normal", "vec3"),
    ("gl_Vertex", "iris_Vertex", "vec4"),
]

STUBS = """// --- synthetic declarations standing in for the compatibility profile ---
vec4 iris_Vertex;
vec3 iris_Normal;
vec4 iris_Color;
vec4 iris_MultiTexCoord0;
vec4 iris_MultiTexCoord1;
vec4 iris_MultiTexCoord2;
vec4 iris_MultiTexCoord3;
mat4 iris_TextureMatrix[8];
mat4 iris_ModelViewMatrix;
mat4 iris_ModelViewProjectionMatrix;
mat4 iris_ProjectionMatrix;
mat4 iris_ModelViewMatrixInverse;
mat4 iris_ProjectionMatrixInverse;
mat3 iris_NormalMatrix;
vec4 ftransform() { return vec4(0.0); }
// --- end of synthetic declarations ---
"""

STUB_LINES = STUBS.count("\n")


def rewrite(unit):
    """Turn an Iris compatibility-profile unit into plain GLSL 3.30 core."""
    lines = unit.splitlines(keepends=True)
    out = []
    for line in lines:
        if line.strip().startswith("#version"):
            out.append("#version 330 core\n")
        else:
            out.append(line)
    unit = "".join(out)

    # Iris consumes the buffer format directives itself: it reads `const int colortexNFormat`
    # to decide what to allocate, then removes the line, which is why packs can write
    # `= RGBA16F` and still compile in game. Remove them here for the same reason, or glslang
    # reports RGBA16F as an undeclared identifier and a constant initialiser that is not
    # constant. Every declaration is replaced by an empty line so the line numbers hold.
    unit = validate.re.sub(
        r'^[ \t]*const[ \t]+int[ \t]+(?:colortex|shadowcolor)\d+Format[ \t]*=[^\n]*',
        '', unit, flags=validate.re.MULTILINE)

    for old, new, _ in LEGACY:
        unit = validate.re.sub(r'\b%s\b' % old, new, unit)

    # Stubs go after the version line, which is the first line of every wrapper.
    head, sep, rest = unit.partition("\n")
    return head + sep + STUBS + rest


def check(name, path, stage, workdir):
    unit = rewrite(validate.expand(path))
    target = os.path.join(workdir, "%s.%s" % (name, "vert" if stage == "vert" else "frag"))
    with open(target, "w", encoding="utf-8") as handle:
        handle.write(unit)

    result = subprocess.run(
        ["glslangValidator", "-S", stage, target],
        capture_output=True, text=True)

    if result.returncode == 0:
        return None, unit, ""

    # glslang reports line numbers of the rewritten file; STUB_LINES at the top belong to
    # the stubs, so subtract them to point at the expanded unit, and show that line.
    message = (result.stdout + result.stderr).replace(target, os.path.basename(path))
    expanded = unit.splitlines()
    context = []
    for raw in message.splitlines():
        if ":" not in raw:
            continue
        parts = raw.split(":")
        for part in parts:
            if part.strip().isdigit():
                reported = int(part.strip())
                index = reported - STUB_LINES - 1
                if 0 <= index < len(expanded):
                    lo = max(0, index - 2)
                    hi = min(len(expanded), index + 3)
                    for offset in range(lo, hi):
                        marker = ">>" if offset == index else "  "
                        context.append("%s %s" % (marker, expanded[offset].rstrip()))
                    context.append("")
                break
    return message, unit, "\n".join(context)


def main():
    if shutil.which("glslangValidator") is None:
        print("SKIP: glslangValidator is not installed, so the GLSL check did not run.")
        print("      CI installs it with: apt-get install glslang-tools")
        return 0

    if not os.path.isdir(SHADERS):
        print("FATAL: no shaders/ directory")
        return 1

    workdir = tempfile.mkdtemp(prefix="aetheris-glsl-")
    failures = 0
    checked = 0

    try:
        for entry in sorted(os.listdir(SHADERS)):
            if not (entry.endswith(".vsh") or entry.endswith(".fsh")):
                continue
            path = os.path.join(SHADERS, entry)
            stage = "vert" if entry.endswith(".vsh") else "frag"
            name = entry[:entry.rindex(".")]
            message, _, context = check(name, path, stage, workdir)
            checked += 1
            if message is None:
                continue
            failures += 1
            print("=" * 70)
            print("%s (%s) does not compile:" % (entry, stage))
            print(message.rstrip())
            if context:
                print("")
                print("the expanded source around the report:")
                print(context)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)

    print("")
    if failures:
        print("%d of %d stages failed the GLSL check." % (failures, checked))
        return 1

    print("All %d stages compile as GLSL 3.30 core." % checked)
    return 0


if __name__ == "__main__":
    sys.exit(main())
