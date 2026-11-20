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
 10. No global name is declared twice in one translation unit. A second declaration of
     the same uniform or constant is a redefinition, and one rejected program is enough
     for Iris to drop the whole pack and render vanilla. This check exists because that
     is exactly what a duplicate `colortex0` did to 1.0.0.
 11. A stage that uses the compatibility built-ins declares the compatibility profile,
     because that is the condition under which Iris patches them, and `mc_Entity` is a
     `vec2` as Iris documents it. Both are Iris rules, not GLSL rules, and neither is
     visible to a generic validator.

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


def expand(path, included=None):
    """Recursively inline #include directives, returning one translation unit.

    Every file in this pack is wrapped in an #ifndef guard, so including it twice is
    a no-op in the preprocessor. The expansion here has to model that exactly, with
    one shared set per translation unit: a per-branch set only prevents cycles and
    would happily inline settings.glsl once per sibling that includes util.glsl,
    which then looks like hundreds of duplicate declarations that the compiler would
    never have seen.
    """
    if included is None:
        included = set()
    if path in included:
        return ""
    included.add(path)

    text = read_text(path)
    lines_out = []
    for line in text.splitlines(keepends=True):
        match = INCLUDE_RE.match(line)
        if not match:
            lines_out.append(line)
            continue
        included_path, _ = resolve_include(match.group(1), path)
        if included_path is None:
            lines_out.append("\n")
            continue
        lines_out.append(expand(included_path, included))
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
# Iris accepts both spellings. RENDERTARGETS is the current one and takes a comma separated
# list; DRAWBUFFERS is the OptiFine-era form and packs the digits together ("02").
RENDERTARGETS_RE = re.compile(r'/\*\s*(?:RENDERTARGETS|DRAWBUFFERS)\s*:\s*([0-9,\s]*)\*/')

# Globals in this pack sit at column 0 and function locals are indented, so anchoring
# at column 0 keeps a `const float a` inside one function from colliding with the same
# name inside another.
GLOBAL_DECL_RE = re.compile(
    r'^(?:uniform|const)\s+\w+\s+(\w+)\s*(?:\[[^\]]*\])?\s*(?:=|;)',
    re.MULTILINE)


def check_duplicate_declarations(label, stripped):
    """A second declaration of the same global name is a redefinition.

    This is the check that would have caught the duplicate `uniform sampler2D colortex0`
    that a composite body and one of its includes both declared. Nothing else here sees
    it: every file is individually valid, every include resolves, and every call has a
    definition. It only exists once the unit is assembled, which is exactly where a
    compiler finds it and where a per-file validator cannot.
    """
    seen = {}
    for match in GLOBAL_DECL_RE.finditer(stripped):
        name = match.group(1)
        line = stripped.count("\n", 0, match.start()) + 1
        if name in seen:
            fail("%s: '%s' is declared twice (lines %d and %d); a second global "
                 "declaration of the same name is a redefinition"
                 % (label, name, seen[name], line))
        else:
            seen[name] = line


def check_unit(label, text):
    stripped = strip_comments(text)

    declarations = [m.group(2) for m in UNIFORM_RE.finditer(stripped)
                    if m.group(1).startswith("sampler")]
    for name in declarations:
        if name not in IRIS_SAMPLERS:
            fail("%s: sampler '%s' is not one Iris binds" % (label, name))

    for match in MC_ENTITY_RE.finditer(stripped):
        if match.group(1) != "vec2":
            fail("%s: mc_Entity is declared as %s; Iris documents it as vec2"
                 % (label, match.group(1)))

    for stem in ("shadowMapResolution", "shadowDistance"):
        count = len(re.findall(r'const\s+\w+\s+%s\s*=' % stem, stripped))
        if count == 0:
            fail("%s: %s is not declared" % (label, stem))
        elif count > 1:
            fail("%s: %s is declared %d times" % (label, stem, count))

    check_balance(label, stripped)
    check_calls(label, stripped, collect_definitions(stripped))
    check_duplicate_declarations(label, stripped)


# Iris rewrites the version statement of every stage before compiling it. A stage that
# uses the compatibility built-ins has to ask for the compatibility profile: with a core
# or absent profile and a version of 150 or more, Iris throws while transforming a vertex
# stage, and one thrown program takes the whole pack back to vanilla rendering.
COMPAT_BUILTINS = (
    "gl_Vertex", "gl_ModelViewMatrix", "gl_ProjectionMatrix",
    "gl_ModelViewProjectionMatrix", "gl_NormalMatrix", "gl_TextureMatrix",
    "gl_MultiTexCoord", "gl_Color", "gl_Normal", "gl_FragData",
)

MC_ENTITY_RE = re.compile(r'^\s*in\s+(\w+)\s+mc_Entity\s*;', re.MULTILINE)


def check_version_statement(label, path, unit):
    header = None
    for line in read_text(path).splitlines():
        candidate = line.strip()
        if not candidate or candidate.startswith("//") or candidate.startswith("/*"):
            continue
        header = candidate
        break
    if header is None or not header.startswith("#version"):
        return  # reported by the caller

    parts = header.split()
    profile = parts[2] if len(parts) > 2 else None
    body = strip_comments(unit)
    for builtin in COMPAT_BUILTINS:
        if builtin not in body:
            continue
        if profile != "compatibility":
            fail("%s: %s uses %s but does not declare the compatibility profile; Iris "
                 "patches the legacy built-ins only when the version statement asks for it"
                 % (label, os.path.basename(path), builtin))
        break


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

    check_version_statement(label, vsh_path, unit_vsh)
    check_version_statement(label, fsh_path, unit_fsh)

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
    match = RENDERTARGETS_RE.search(read_text(fsh_path))
    if match:
        # \s* in the pattern swallows the space before */, so the captured text has to be
        # trimmed before it is tested for spaces *between* the entries.
        raw = match.group(1).strip()
        if "," in raw:
            if re.search(r'\s', raw):
                fail("%s: the render target list is '%s' and contains whitespace; Iris parses "
                     "each entry with Integer.parseInt, so '0, 2' throws NumberFormatException "
                     "for input string 2 and the pack will not load. Write it as 0,2"
                     % (label, raw))
            targets = len([t for t in raw.split(",") if t])
        else:
            # Legacy DRAWBUFFERS packs the indices together: "02" is two targets.
            targets = len(raw)
        if targets != outputs:
            fail("%s: the render target list names %d target(s) but the fragment stage "
                 "declares %d output(s)" % (label, targets, outputs))
    elif outputs > 1:
        fail("%s: %d outputs but no RENDERTARGETS line" % (label, outputs))

    if outputs < 1:
        fail("%s: the fragment stage declares no output at all; every program Iris runs against a "
             "colour target should write one" % label)


# Iris only recognises a fixed set of `const` option names. Everything else has to be a
# #define: OptionAnnotatedSource.parseConst rejects a const whose name is not in this
# list, so such a line is silently not an option, while shaders.properties can still
# refer to it from screen.*, sliders, #if and profile.*. That mismatch is what made 1.2.0
# fail to apply with an empty error, and it is invisible to every other check here.
IRIS_CONST_OPTIONS = set("""
shadowMapResolution shadowDistance voxelDistance shadowDistanceRenderMul
entityShadowDistanceMul shadowIntervalSize generateShadowMipmap generateShadowColorMipmap
shadowHardwareFiltering shadowtex0Mipmap shadowtexMipmap shadowtex1Mipmap shadowtex0Nearest
shadowtexNearest shadow0MinMagNearest shadowtex1Nearest shadow1MinMagNearest
wetnessHalflife drynessHalflife eyeBrightnessHalflife centerDepthHalflife sunPathRotation
ambientOcclusionLevel superSamplingLevel noiseTextureResolution
""".split())

OPTION_DEFINE_RE = re.compile(r'^#define\s+([A-Z0-9_]+)\s+(\S+)\s*//\s*\[([^\]]*)\]', re.MULTILINE)
OPTION_CONST_RE = re.compile(r'^const\s+(?:int|float|bool)\s+(\w+)\s*=\s*([^;]+);\s*//\s*\[([^\]]*)\]',
                             re.MULTILINE)


def parse_options():
    """Return {name: (default value, [allowed values])} for every option Iris accepts.

    This models Iris' own parser rather than the pack's intent, which is the whole point:
    an option Iris does not register cannot be shown, saved or applied, and a reference to
    it from shaders.properties is a load-time failure.
    """
    settings = read_text(os.path.join(SHADERS, "lib", "settings.glsl"))
    options = {}

    for match in OPTION_DEFINE_RE.finditer(settings):
        options[match.group(1)] = (match.group(2), match.group(3).split())

    for match in OPTION_CONST_RE.finditer(settings):
        name = match.group(1)
        if name not in IRIS_CONST_OPTIONS:
            fail("settings.glsl: '%s' is declared as a const option, but Iris only accepts a "
                 "fixed list of const option names; declare it with #define or it is not an "
                 "option at all" % name)
            continue
        options[name] = (match.group(2).strip(), match.group(3).split())

    for name, (value, allowed) in sorted(options.items()):
        if allowed and value not in allowed:
            warn("settings.glsl: the default of %s (%s) is not one of its allowed values; Iris "
                 "appends it, so the control shows a value that is not one of its stops"
                 % (name, value))

    return options


IRIS_PROGRAMS = set("""
gbuffers_basic gbuffers_line gbuffers_textured gbuffers_textured_lit gbuffers_skybasic
gbuffers_skytextured gbuffers_clouds gbuffers_terrain gbuffers_terrain_solid
gbuffers_terrain_cutout gbuffers_damagedblock gbuffers_block gbuffers_beaconbeam
gbuffers_entities gbuffers_entities_glowing gbuffers_entities_translucent
gbuffers_armor_glint gbuffers_spidereyes gbuffers_hand gbuffers_hand_water gbuffers_weather
gbuffers_water gbuffers_lightning gbuffers_particles gbuffers_particles_translucent
gbuffers_block_translucent shadow shadow_solid shadow_cutout final
""".split())

SUFFIXED_PROGRAMS = ("composite", "deferred", "begin", "prepare", "setup", "shadowcomp")


def check_program_name(name):
    """Fail on a wrapper Iris does not know.

    A file named for a program that does not exist is ignored in silence: no error, no
    warning, and that geometry is drawn by Iris' own shader instead. The visible result is
    that the pack looks like it is not doing anything for that pass, which is the hardest
    kind of failure to tell apart from a pack that is not loaded at all.
    """
    if name in IRIS_PROGRAMS:
        return
    for prefix in SUFFIXED_PROGRAMS:
        if name == prefix or (name.startswith(prefix) and name[len(prefix):].isdigit()):
            return
    fail("%s: Iris has no program by this name, so these files are ignored and that pass "
         "falls back to Iris' own shader — check the spelling" % name)


def check_options():
    options = parse_options()
    known = set(options)

    properties_text = read_text(os.path.join(SHADERS, "shaders.properties"))
    for line in properties_text.splitlines():
        stripped = strip_comments(line).strip()
        if not stripped:
            continue

        # Conditionals in shaders.properties are preprocessed against the pack's options.
        # A name that is not an option expands to nothing and the condition is then
        # malformed, which Iris reports only in its own log.
        if stripped.startswith("#if"):
            for token in re.findall(r'[A-Za-z_]\w*', stripped):
                if token in ("if", "ifdef", "ifndef", "defined", "elif"):
                    continue
                if token not in known:
                    fail("shaders.properties: '%s' names '%s' in a conditional, which is not an "
                         "option in settings.glsl" % (stripped, token))
            continue

        if stripped.startswith("#"):
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
                option, _, preset_value = token.partition("=")
                if option not in known:
                    fail("shaders.properties: %s sets '%s', which is not an option in settings.glsl"
                         % (key, option))
                    continue
                allowed = options[option][1]
                if allowed and preset_value not in allowed:
                    warn("shaders.properties: %s sets %s=%s, which is not one of that option's "
                         "allowed values" % (key, option, preset_value))


def check_performance_profile():
    """Keep the low-end preset feature-complete; quality may fall, effects may not vanish."""
    properties = read_text(os.path.join(SHADERS, "shaders.properties"))
    profile_line = next(
        (line.strip() for line in properties.splitlines()
         if line.strip().startswith("profile.PERFORMANCE")),
        None,
    )
    if not profile_line or "=" not in profile_line:
        fail("shaders.properties: profile.PERFORMANCE is missing")
        return

    values = {}
    for token in profile_line.split("=", 1)[1].split():
        if "=" in token:
            name, value = token.split("=", 1)
            values[name] = value

    required = {
        "SHADOWS": "1", "SSAO": "1", "WATER_REFLECTIONS": "1",
        "CLOUDS": "1", "CLOUD_DETAIL": "1", "CLOUD_CIRRUS": "1",
        "WATER_WAVES": "1", "ANTI_ALIASING": "1", "BLOOM": "1",
        "VOLUMETRIC_LIGHT": "1", "MATERIAL_GLOSS": "1",
    }
    for name, expected in required.items():
        if values.get(name) != expected:
            fail("profile.PERFORMANCE: %s must remain enabled (expected %s)" % (name, expected))

    if values.get("shadowDistanceRenderMul") != "1.0":
        fail("profile.PERFORMANCE: shadowDistanceRenderMul must enable real shadow-pass culling")

    lines = [line.strip() for line in properties.splitlines()]
    for buffer in ("colortex3", "colortex4"):
        prefix = "size.buffer.%s" % buffer
        if not any(line.startswith(prefix) and "0.25 0.25" in line for line in lines):
            fail("shaders.properties: %s must remain a quarter-resolution composite buffer" % buffer)

    for program in ("composite1", "composite2"):
        prefix = "program.%s.enabled" % program
        if not any(line.startswith(prefix) and ("BLOOM" in line or "VOLUMETRIC_LIGHT" in line)
                   for line in lines):
            fail("shaders.properties: %s must be conditionally enabled for retained low-resolution effects"
                 % program)


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

    # Iris never rewrites the version *profile* for its line programs. TransformPatcher takes
    # the core branch whenever isLines() is true, and that branch patches the version number
    # but does not set profile = CORE, so a compatibility version statement reaches the
    # driver, which on Linux/Mesa has no compatibility profile above GL 3.0 and refuses it:
    #   lines: 0:1(10): error: the compatibility profile is not supported
    # So a line program may exist, but it must be core.
    for name in ("gbuffers_line", "gbuffers_basic"):
        stages = programs.get(name)
        if not stages:
            continue
        for path in stages.values():
            header = ""
            for line in read_text(path).splitlines():
                candidate = line.strip()
                if candidate and not candidate.startswith("//"):
                    header = candidate
                    break
            if header.startswith("#version") and "compatibility" in header:
                fail("%s: '%s' is a line program, and Iris does not rewrite the version "
                     "profile for those; a compatibility profile reaches the driver and is "
                     "rejected. Either use #version 330 core with Iris' modern attributes, or "
                     "ship no %s program at all"
                     % (os.path.relpath(path, ROOT), header, name))

    for name, stages in sorted(programs.items()):
        check_program_name(name)
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
    check_performance_profile()

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
