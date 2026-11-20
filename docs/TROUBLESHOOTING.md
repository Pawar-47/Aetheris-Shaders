## First: the probe pack

Every release attaches two zips. `Aetheris-Probe-<version>.zip` is two files, one program,
no `shaders.properties`, no `#include`, no block map, no language file — the smallest thing
that can still be called a shader pack, shaped exactly like the Iris 1.21.5 template.

Install it the same way and look at the world:

- **The world is flat and brightly lit, no shadows, textures intact** → the probe loaded.
  Iris works, your install works, and the fault is inside Aetheris. The log will say where
  (see below).
- **Iris still reports a problem** → the fault is not Aetheris. It is the Iris version, the
  Minecraft version, or the folder the zip went into. Check that Iris and Sodium are both
  the builds for *your* Minecraft version, and that the zip is in the `shaderpacks` folder of
  the instance you are actually launching.
- **The pack appears in the list but the world looks untouched** → it loaded and did
  nothing, which is also information: the probe's whole point is that a loaded pack cannot
  look vanilla.


# Troubleshooting

## "Iris has encountered a problem while applying", and the details pane shows nothing

The details pane belongs to Iris, not to this pack, and it shows the Java exception that
aborted the load. When it shows nothing useful — or the words `No value present` — that is
normally an exception carrying no message. The actual explanation is in the log, and two
minutes there will name the file and the line.

A shader pack cannot log, so this page is the pack's error reporting.

### 1. Turn on Iris' debug mode

Open the shader selection screen and press **Ctrl + D**. Iris asks whether to enable debug
mode; accept. From then on it writes the *post-processed* source — the code after `#include`
resolution and after Iris' own transformations — to:

```
<game directory>/patched_shaders/
```

That folder is the most useful artefact when a pack fails. The file names match the
programs, and any compile error's line numbers refer to those files, not to the pack on
disk.

### 2. Find the error in the log

Open `<game directory>/logs/latest.log` and search for one of these:

| What you are looking for | What it means |
|---|---|
| `error:` with a GLSL line number | A compile error. The next line names the program and stage. |
| `TransformationException` or `ParsingException` | Iris could not transform the source. Its message names the construct it stopped on. |
| `No value present` | An empty `Optional.get()` inside Iris while parsing the pack. Not a GLSL problem — usually a reference in `shaders.properties` to something that is not an option. |
| `NumberFormatException: For input string: "2"` | A numeric list with a space in it. `RENDERTARGETS` entry parsing uses `Integer.parseInt`, so `0, 2` passes it `" 2"`. Write `0,2`. |
| `was not recognized as being a name of one of the configurable const options` | An option in `settings.glsl` that Iris does not register. See below. |
| `Ignoring this #define` | An option line Iris rejected. Causes: a `//` comment before the `#define` on a valued option, no `[...]` allowed-values list, or a value the list does not contain. |
| `Properties pre-processing failed` | `shaders.properties` or `block.properties` did not survive preprocessing. |
| `Unable to find sampler` / `not one Iris binds` | A sampler name Iris does not provide. |

### 3. What to report

Open an issue with the log lines above, the pack version from `VERSION`, your Minecraft and
Iris versions, and your GPU. Without them there is nothing useful anyone can do with "it did
not load".

---

## Known tripwires in Iris' pack parsing

These are not pack design choices; they are rules Iris enforces, and each one has cost a
release of this pack at least once. They are listed here because they are invisible from
inside the GLSL and only show up as a failed load.

- **A user option must be a `#define`, not a `const`, unless the name is one of Iris' own.**
  Iris' option parser accepts const options only for `shadowMapResolution`,
  `shadowDistance`, `voxelDistance`, `shadowDistanceRenderMul`, `entityShadowDistanceMul`,
  `shadowIntervalSize`, `sunPathRotation`, `ambientOcclusionLevel`, `superSamplingLevel`,
  `noiseTextureResolution` and the shadow map flags. A `const float MY_SLIDER = 1.0; // [...]`
  is rejected with a diagnostic that never reaches the user, so the option does not exist —
  and every reference to it from `shaders.properties` then fails at menu build time.
- **An option's default value should appear in its own allowed-values list.** Iris appends
  the default when it is missing, so the pack still loads, but the control then has a stop
  the user never asked for.
- **Every value a `profile.*` line sets should be one of that option's allowed values.**
- **A valued `#define` may not have a leading `//` comment on the same line.** Comments go
  on the line above. A leading comment is only legal on a bare boolean `#define`.
- **`block.properties` is read with `java.util.Properties` after preprocessing**, so `\` line
  continuations do work — but one block list per line is one less thing to depend on.
- **A gbuffers-style program should declare a fragment output.** Depth-only shadow programs
  exist in many packs, but this pack does not rely on one.
- **`#version 330 compatibility` is required wherever the legacy built-ins are used.**
  With a core or missing profile and a version of 150 or more, Iris throws while
  transforming a vertex stage.
