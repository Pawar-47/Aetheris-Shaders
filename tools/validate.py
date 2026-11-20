#!/usr/bin/env python3
"""Static validation for the Aetheris Shaders pack.

This exists because Iris shader packs cannot be compiled by a generic GLSL
validator. Gbuffer programs depend on the OpenGL compatibility profile: gl_Vertex,
gl_ModelViewMatrix, gl_Color, gl_MultiTexCoord1 and the rest have no equivalent in
core GLSL, and tools such as glslangValidator do not implement them at all. Running
one over this pack produces a wall of errors that say nothing about whether the pack
works in Iris.

So this script checks the things that a real compiler *would* have caught, using the
rules of the Iris dialect specifically:

  1. Every #include resolves to a file that exists.
  2. Every declared program has both stages, and both start with #version.
  3. Braces and #if/#endif balance in every translation unit.
  4. Every function that is called is either defined in the same translation unit or
     is a GLSL built-in. This is the check that catches a misspelled or missing
     library function, which is the most likely way to break a pack like this.
  5. Every sampler is one that Iris actually binds.
  6. Every varying declared `in` by a fragment stage is declared `out` by the vertex
     stage with the same name and the same type. This catches the link errors that a
     per-file validator would never see, because they only exist across two stages.
  7. DRAWBUFFERS lists exactly as many targets as the fragment stage declares
     outputs.
  8. shadowMapResolution and shadowDistance are declared exactly once per unit.
  9. Every option referenced by shaders.properties exists in settings.glsl.

What this does NOT do, and what the README says plainly: it does not prove the pack
compiles on a GPU, and it cannot check runtime behaviour, visual quality or frame
rate. Those need Minecraft.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHADERS = os.path.join(ROOT, "shaders")

ERRORS = []
WARNINGS = []


def fail(message):
    ERRORS.append(message)


def warn(message):
    WARNINGS.append(message)


def read_text(path):
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        return handle.read()


def strip_comments(text):
    """Blank out comments while preserving line numbers."""
    out = []
    i = 0
    n = len(text)
    while i < n:
        if text.startswith("//", i):
            while i < n and text[i] != "\n":
                out.append(" ")
                i += 1
        elif text.startswith("/*", i):
            while i < n and not text.startswith("*/", i):
                out.append("\n" if text[i] == "\n" else " ")
                i += 1
            for _ in range(2):
                if i < n:
                    out.append(" ")
                    i += 1
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


INCLUDE_RE = re.compile(r'^\s*#include\s+"([^"]+)"', re.MULTILINE)


def resolve_include(spec, from_file):
    if spec.startswith("/"):
        candidate = os.path.join(SHADERS, spec.lstrip("/"))
    else:
        candidate = os.path.normpath(os.path.join(os.path.dirname(from_file), spec))
    if not os.path.isfile(candidate):
        fail("%s: includes %r, which does not exist" % (os.path.relpath(from_file, ROOT), spec))
        return None, ""
    return candidate, read_text(candidate)


def expand(path, seen=None):
    """Recursively inline #include directives, returning one translation unit."""
    if seen is None:
        seen = set()
    if path in seen:
        return ""
    seen = seen | {path}

    text = read_text(path)
    lines_out = []
    for line in text.splitlines(keepends=True):
        match = INCLUDE_RE.match(line)
        if not match:
            lines_out.append(line)
            continue
        included_path, included_text = resolve_include(match.group(1), path)
        if included_path is None:
            lines_out.append("\n")
            continue
        lines_out.append(expand(included_path, seen))
        if not lines_out[-1].endswith("\n"):
            lines_out.append("\n")
    return "".join(lines_out)


GLSL_BUILTINS = set("""
abs acos acosh all any asin asinh atan atanh bitCount bitfieldExtract bitfieldInsert
bitfieldReverse ceil clamp cos cosh cross dFdx dFdy degrees determinant distance dot
equal exp exp2 faceforward findLSB findMSB floatBitsToInt floatBitsToUint floor fma
fract frexp fwidth greaterThan greaterThanEqual imulExtended intBitsToFloat interface
interpolateAtCentroid interpolateAtOffset interpolateAtSample inverse inversesqrt
isinf isnan ldexp length lessThan lessThanEqual log log2 matrixCompMult max min mix mod
modf normalize not notEqual outerProduct packHalf2x16 packSnorm2x16 packUnorm2x16
pow radians reflect refract round roundEven shadow1D shadow1DProj shadow2D
shadow2DProj sign sin sinh smoothstep sqrt step tan tanh texelFetch texelFetchOffset
texture textureGather textureGrad textureGradOffset textureLod textureLodOffset
textureOffset textureProj textureProjGrad textureProjLod textureProjLodOffset
textureQueryLevels textureQueryLod textureSize transpose trunc uaddCarry uintBitsToFloat
umulExtended unpackHalf2x16 unpackSnorm2x16 unpackUnorm2x16
float int uint bool void vec2 vec3 vec4 ivec2 ivec3 ivec4 uvec2 uvec3 uvec4
bvec2 bvec3 bvec4 mat2 mat3 mat4 mat2x2 mat2x3 mat2x4 mat3x2 mat3x3 mat3x4 mat4x2
mat4x3 mat4x4 double dvec2 dvec3 dvec4
""".split())

KEYWORDS = set("""
if else for while do switch case default return break continue discard struct
layout const uniform in out inout flat smooth noperspective centroid invariant
precision highp mediump lowp attribute varying main defined
""".split())

# Uniforms and samplers that Iris supplies. A sampler name outside this list cannot
# be bound and would compile to something undefined.
IRIS_SAMPLERS = set("""
gtexture lightmap normals specular gaux1 gaux2 gaux3 gaux4 noisetex
depthtex0 depthtex1 depthtex2 shadowtex0 shadowtex1 shadowcolor0 shadowcolor1
gdepth gnormal gcolor gtexture1 gtexture2
""".split())
IRIS_SAMPLERS.update("colortex%d" % i for i in range(16))


def check_balance(label, text):
    depth = 0
    for line_number, line in enumerate(text.splitlines(), 1):
        depth += line.count("{") - line.count("}")
        if depth < 0:
            fail("%s: unbalanced closing brace near line %d" % (label, line_number))
            return
    if depth != 0:
        fail("%s: %d unclosed brace(s)" % (label, depth))

    stack = []
    for line_number, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("#if"):
            stack.append(line_number)
        elif stripped.startswith("#endif"):
            if not stack:
                fail("%s: #endif without #if near line %d" % (label, line_number))
                return
            stack.pop()
    if stack:
        fail("%s: %d unclosed #if (first at line %d)" % (label, len(stack), stack[0]))


DEFINITION_RE = re.compile(
    r'^\s*(?:void|float|int|uint|bool|vec2|vec3|vec4|ivec2|ivec3|ivec4|'
    r'mat2|mat3|mat4|AetherisSky)\s+(\w+)\s*\(',
    re.MULTILINE)

CALL_RE = re.compile(r'\b([A-Za-z_]\w*)\s*\(')


def collect_definitions(text):
    return set(DEFINITION_RE.findall(text))


def check_calls(label, text, definitions):
    for match in CALL_RE.finditer(text):
        name = match.group(1)
        if name in GLSL_BUILTINS or name in KEYWORDS:
            continue
        if name in definitions:
            continue
        if name.startswith("gl_"):
            continue
        fail("%s: call to undefined function or macro '%s'" % (label, name))
        # One report per name is plenty.
        definitions.add(name)


UNIFORM_RE = re.compile(r'^\s*uniform\s+(\w+)\s+(\w+)\s*;', re.MULTILINE)
OUT_RE = re.compile(r'^\s*(?:flat\s+|smooth\s+|noperspective\s+)?out\s+(\w+)\s+(\w+)\s*;', re.MULTILINE)
IN_RE = re.compile(r'^\s*(?:flat\s+|smooth\s+|noperspective\s+)?in\s+(\w+)\s+(\w*)\s*;', re.MULTILINE)
LAYOUT_OUT_RE = re.compile(r'layout\s*\(\s*location\s*=\s*(\d+)\s*\)\s*out\s+\w+\s+\w+\s*;')
DRAWBUFFERS_RE = re.compile(r'/\*\s*DRAWBUFFERS\s*:\s*([0-9]+)\s*\*/')


def check_unit(label, text):
    stripped = strip_comments(text)

    declarations = [m.group(2) for m in UNIFORM_RE.finditer(stripped)
                    if m.group(1).startswith("sampler")]
    for name in declarations:
        if name not in IRIS_SAMPLERS:
            fail("%s: sampler '%s' is not one Iris binds" % (label, name))

    for stem in ("shadowMapResolution", "shadowDistance"):
        count = len(re.findall(r'const\s+\w+\s+%s\s*=' % stem, stripped))
        if count == 0:
            fail("%s: %s is not declared" % (label, stem))
        elif count > 1:
            fail("%s: %s is declared %d times" % (label, stem, count))

    check_balance(label, stripped)
    check_calls(label, stripped, collect_definitions(stripped))


def declared_varyings(regex, text):
    stripped = strip_comments(text)
    result = {}
    for match in regex.finditer(stripped):
        type_name, var_name = match.group(1), match.group(2)
        if not var_name:
            continue
        # A "uniform" line cannot be reached here, but an out declaration inside a
        # struct definition could be. Structs are not used in this pack.
        result[var_name] = type_name
    return result


def check_program(name, vsh_path, fsh_path):
    label = name

    unit_vsh = expand(vsh_path)
    unit_fsh = expand(fsh_path)

    for path, unit in ((vsh_path, unit_vsh), (fsh_path, unit_fsh)):
        first = None
        for line in read_text(path).splitlines():
            candidate = line.strip()
            if not candidate or candidate.startswith("//") or candidate.startswith("/*"):
                continue
            first = candidate
            break
        if first is None or not first.startswith("#version"):
            fail("%s: %s does not start with #version"
                 % (label, os.path.relpath(path, ROOT)))

    check_unit(label + ".vsh", unit_vsh)
    check_unit(label + ".fsh", unit_fsh)

    if "void main" not in unit_vsh:
        fail("%s.vsh: no main" % label)
    if "void main" not in unit_fsh:
        fail("%s.fsh: no main" % label)

    vertex_out = declared_varyings(OUT_RE, unit_vsh)
    fragment_in = declared_varyings(IN_RE, unit_fsh)
    for var_name, type_name in sorted(fragment_in.items()):
        if var_name not in vertex_out:
            fail("%s: fragment reads varying '%s' that the vertex stage never writes"
                 % (label, var_name))
        elif vertex_out[var_name] != type_name:
            fail("%s: varying '%s' is %s in the vertex stage but %s in the fragment stage"
                 % (label, var_name, vertex_out[var_name], type_name))

    stripped_fsh = strip_comments(unit_fsh)
    outputs = len(LAYOUT_OUT_RE.findall(stripped_fsh))
    match = DRAWBUFFERS_RE.search(read_text(fsh_path))
    if match:
        targets = len(match.group(1))
        if targets != outputs:
            fail("%s: DRAWBUFFERS lists %d target(s) but the fragment stage declares %d output(s)"
                 % (label, targets, outputs))
    elif outputs > 1:
        fail("%s: %d outputs but no DRAWBUFFERS line" % (label, outputs))


def check_options():
    settings = read_text(os.path.join(SHADERS, "lib", "settings.glsl"))
    known = set(re.findall(r'^\s*#define\s+([A-Z0-9_]+)', settings, re.MULTILINE))
    known.update(re.findall(r'^const\s+(?:int|float|bool)\s+(\w+)\s*=', settings, re.MULTILINE))

    properties_text = read_text(os.path.join(SHADERS, "shaders.properties"))
    for line in properties_text.splitlines():
        stripped = strip_comments(line).strip()
        if not stripped or stripped.startswith("#"):
            continue
        key, _, value = stripped.partition("=")
        key = key.strip()
        # screen.columns and its siblings are layout metadata, not option lists.
        if key == "screen.columns":
            continue
        if key.startswith("screen.") or key in ("sliders",):
            for token in value.split():
                token = token.strip("\\")
                if token in ("*", "<empty>", "<profile>") or token.startswith("["):
                    continue
                if token not in known:
                    fail("shaders.properties: %s names '%s', which is not an option in settings.glsl"
                         % (key, token))
        elif key.startswith("profile."):
            for token in value.split():
                token = token.strip("\\")
                if "=" not in token:
                    continue
                option = token.split("=", 1)[0]
                if option not in known:
                    fail("shaders.properties: %s sets '%s', which is not an option in settings.glsl"
                         % (key, option))


def main():
    if not os.path.isdir(SHADERS):
        print("FATAL: no shaders/ directory")
        return 1

    programs = {}
    for entry in sorted(os.listdir(SHADERS)):
        if entry.endswith(".vsh"):
            programs.setdefault(entry[:-4], {})["vsh"] = os.path.join(SHADERS, entry)
        elif entry.endswith(".fsh"):
            programs.setdefault(entry[:-4], {})["fsh"] = os.path.join(SHADERS, entry)

    if not programs:
        fail("no shader programs found")

    required = ["composite", "final", "shadow", "gbuffers_terrain", "gbuffers_water"]
    for name in required:
        if name not in programs:
            fail("required program '%s' is missing" % name)

    for name, stages in sorted(programs.items()):
        if "vsh" not in stages:
            fail("%s has no vertex stage" % name)
            continue
        if "fsh" not in stages:
            fail("%s has no fragment stage" % name)
            continue
        check_program(name, stages["vsh"], stages["fsh"])

    # Library files that are not reached from any program are dead weight.
    reached = set()
    for stages in programs.values():
        for path in stages.values():
            for match in re.finditer(r'#include\s+"([^"]+)"', read_text(path)):
                spec = match.group(1)
                if spec.startswith("/"):
                    reached.add(os.path.normpath(os.path.join(SHADERS, spec.lstrip("/"))))
    body_dir = os.path.join(SHADERS, "lib", "body")
    if os.path.isdir(body_dir):
        for entry in sorted(os.listdir(body_dir)):
            full = os.path.join(body_dir, entry)
            if full not in reached:
                warn("lib/body/%s is not included by any program" % entry)

    check_options()

    for message in WARNINGS:
        print("warning: %s" % message)
    for message in ERRORS:
        print("error:   %s" % message)

    if ERRORS:
        print("\n%d error(s), %d warning(s)" % (len(ERRORS), len(WARNINGS)))
        return 1

    print("All %d programs passed static validation (%d warning(s))."
          % (len(programs), len(WARNINGS)))
    print("Note: this is static analysis. It does not prove the pack compiles on a GPU.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
