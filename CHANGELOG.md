# Changelog

All notable changes to Aetheris Shaders are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

A release is made when there is something worth installing, not when a number changes.

## [1.5.5] - 2026-12-01

Three changes, all art direction rather than correctness.

### Changed

- **Clouds are stylised.** Fewer and larger masses (one feature per ~300 blocks instead of
  230), a flat full base that reaches density inside the first tenth of the slab, crowns that
  rise steeply so the silhouette is domed, and edge erosion cut to a sixth of what it was and
  confined to the top third — heavy erosion is what makes procedural clouds look like mush at
  this resolution. Lighting is graphic rather than photographic: the lit and shaded tones sit
  further apart, the terminator between them is narrowed with a smoothstep so a mass reads as
  a lit crown over a shaded body, and the skirt uses a smoothstep instead of a power curve for
  a cleaner edge. The cirrus veil is dimmed to an accent.
- **Fog obeys its slider, and there is far less of it.** The distance haze was 1/320, which
  put visible haze on anything past about forty blocks — most of a six-chunk render distance.
  It is 1/900, the height term is at 45%, and the render-distance fade that hides the edge of
  the world is now scaled by `FOG_DENSITY` and starts later. That fade was previously applied
  unconditionally, which is exactly why setting `FOG_DENSITY` to 0 still left a band of haze
  at the far plane and the fog felt like it had no control. 0.0 is now genuinely clear air;
  the default is 0.5 instead of 1.0.
- **Water is sea coloured.** The green channel absorbs faster (0.115 against 0.088) and the
  in-scattering is blue dominant, so ten blocks of water reads deep blue rather than cyan, and
  shallows read turquoise rather than green. The underwater tint follows the same palette, and
  the cheap cloud sample used by water reflections matches the new deck.

## [1.5.4] - 2026-12-01

A full pass over the pack rather than a reaction to a log line: one reported error fixed, and
every remaining program checked against the transform path Iris actually takes for it.

### Fixed

- **`gbuffers_line` and `gbuffers_basic` removed.**
  `lines: 0:1(10): error: the compatibility profile is not supported` names Iris' line
  program. In `TransformPatcher`, `isLines()` forces the **core** branch whatever profile is
  declared, and that branch patches the version *number* but never sets `profile = CORE`;
  only the legacy branch does. So `#version 330 compatibility` reached Mesa unchanged, and
  this driver has no compatibility profile above GL 3.0, so it refused the program outright.
  Iris draws lines itself when a pack does not ask it to, and nothing in this pack's look
  depended on shading them.

### Verified rather than changed

- **Buffer wiring is consistent end to end.** The colour pipeline is `colortex0` throughout:
  every `gbuffers_*` writes it, `composite` reads and writes it, `final` reads it. The water
  mask and surface normal are in `colortex2`, written by `gbuffers_water` at
  `RENDERTARGETS: 0,2` and read by `composite`. Nothing still refers to the `colortex1` that
  1.5.0 removed, and `depthtex1` remains only where opaque-only depth is genuinely wanted
  (the water column and the reflection march).
- All 22 program names are programs Iris actually has.
- All 46 stages compile as GLSL 3.30 core after the rewrite Iris performs.
- `near`/`far`, `depthtex0/1`, `shadowtex0`, `gtexture` and `mc_Entity` are used the way
  Iris documents them; no reserved word is used as an identifier; no built-in is shadowed.

### Added

- The compiler check now **links** each program's vertex and fragment stage as well as
  compiling them separately. Varying mismatches, duplicate output locations and names
  declared in only one stage all fail there, and Iris fails on all of them.
- The validator now fails on a wrapper named for a program Iris does not have. Iris ignores
  such a file in silence and draws that geometry with its own shader, which is
  indistinguishable from "the pack is doing nothing" for that pass.

## [1.5.3] - 2026-12-01

Iris reported `'RGBA16F' undeclared` in composite, and it was right: the buffer format
directives were in the wrong place and in the wrong form.

### Fixed

- **`const int colortex0Format = RGBA16F;` moved into a comment block in `composite.fsh`.**
  Iris consumes that directive only when it finds it in the program file; one inside an
  include is not consumed, so it goes to the driver, where `RGBA16F` is not an identifier and
  the program fails to compile. It is now in the documented form — a commented block at the
  top of `shaders/composite.fsh` — which the loader still reads and the compiler ignores.

### Fixed in the check, not the pack

- `tools/glsl_check.py` no longer strips those directives before compiling. It was stripping
  them to keep glslang quiet, which made the check *more lenient than Iris* and is exactly
  why it passed a pack that Iris rejects. A code-form directive now fails CI instead of
  being papered over.

## [1.5.2] - 2026-12-01

The parse error from the log, and the reason it took six releases to find it.

### Fixed

- **`vec3 flat` in `atmosphere.glsl`.** `flat` is a reserved interpolation qualifier in GLSL
  3.30, so a local variable of that name is a syntax error. Iris' ANTLR parser rejected the
  entire composite translation unit with `no viable alternative at input 'vec3 flat'`. Every
  pass includes `atmosphere.glsl`, so one identifier broke every program at once. Renamed to
  `flattened`.
- The whole class was scanned afterwards: `flat` was the only reserved word used as an
  identifier anywhere in the pack, and no built-in function name is shadowed by a
  declaration.

### Added

- **`tools/glsl_check.py`, run in CI on every push.** It compiles all 46 stages with
  `glslangValidator` after doing what Iris does to the source: resolve `#include`, rewrite
  `#version 330 compatibility` to core, rename and declare the legacy built-ins, and remove
  the `colortexNFormat` directives that Iris consumes itself. Its first run compiled 45 of
  46 stages, and the only complaint was this reserved word — the pack had never been through
  a compiler before a release until now. That is the actual fix for "one error at a time
  from the log".

## [1.5.1] - 2026-11-30

The pack failed with a real exception at last: `java.lang.NumberFormatException: For input
string: "2"`. That named the bug exactly.

### Fixed

- **A space in a render target list.** `gbuffers_water` declared
  `/* RENDERTARGETS: 0, 2 */`. Iris parses each entry of that list with `Integer.parseInt`,
  so the second entry arrives as `" 2"` and the load dies. The documentation writes the
  directive as `X,Y,Z` for this reason. It is `0,2` now.
- The validator rejects whitespace inside a target list, so this cannot ship again. Its first
  version fired on its own pattern: `\s*` swallowed the space before `*/`, so a correct `0,2`
  was captured as `"0,2 "` and reported. It trims first now.

## [1.5.0] - 2026-11-30

The pack still would not apply, so this release was built by comparing it file by file
against **Nova Shaders**, which loads on the same machine. That comparison settled two things
and corrected one wrong assumption.

### Fixed

- **The colour pipeline uses one buffer now, the way Nova and the Iris 1.21.5 template do.**
  `composite` declares `RENDERTARGETS: 0`, reads `colortex0` and writes `colortex0` — the
  loader keeps two physical textures per attachment and flips them, so that is a ping-pong
  rather than a feedback loop — and `final` reads `colortex0`. There is no `colortex1` any
  more, and therefore no way for the last pass to read an attachment nothing has written.
- **Buffer formats are declared once, as real code**, in `lib/body/composite.fsh`. They used
  to sit inside a block comment repeated across four programs: a loader that does not read
  inside comments would have silently given every buffer the default RGBA8, and four
  declarations of the same attachment are four chances to disagree.
- **The archive now holds `pack.mcmeta`, `LICENSE` and the notices** alongside `shaders/`,
  and `tools/package.sh` fails the build if any of them is missing. That is the layout Nova
  ships and the one its own build script asserts.

### Changed

- **The presets, the settings screen and the `#if SHADOWS` conditional are back.** 1.4.0
  removed them on the theory that Iris' option menu was the failure. Nova ships the same
  `screen`/`sliders`/`profile.*`/`#if` set and loads, so the theory was wrong and the feature
  is restored, along with the brief's three cost profiles.
- The probe pack is no longer built or shipped.

## [1.4.1] - 2026-11-29

The pack still fails to apply after 1.4.0, and four attempts at diagnosing it from the source
have not converged. This release stops adding hypotheses and makes the failure measurable
instead.

### Added

- **A probe pack.** Every release now attaches `Aetheris-Probe-<version>.zip` alongside the
  real pack: one program, two files, no `shaders.properties`, no `#include`, no block map, no
  language file — the smallest thing that can be called a shader pack, shaped exactly like the
  Iris 1.21.5 template. It renders the world unlit, so a successful load is unmistakable
  rather than "looks about the same". If the probe loads and Aetheris does not, the fault is
  here; if the probe also fails, the fault is the install.
- `docs/TROUBLESHOOTING.md` opens with that test and what each outcome means.

### Changed

- Nothing in the renderer. Deliberately: this release exists to get one real data point
  rather than to change behaviour on another guess.

## [1.4.0] - 2026-11-28

The pack still would not load after 1.3.0, so this release stops guessing which directive
threw and rebuilds the configuration around the one thing known to load: the Iris 1.21.5
template (`ascpixi/minecraft-shader-template`, itself the ShaderLABS Base-330 skeleton).
Notably, that template ships **no `shaders.properties` at all**, and its programs use
`RENDERTARGETS`, not `DRAWBUFFERS`.

### Changed

- **`shaders.properties` reduced to six vanilla-feature switches.** Everything removed —
  `screen`, `screen.*`, `sliders`, `profile.*` and the `#if` block — has one thing in common:
  each makes Iris look an option name up in the set it discovered from the shader sources,
  and a name that does not resolve aborts the load with an exception whose message is empty.
  That is exactly the `No value present` on screen. `blend.*`, `shadow.enabled`, `separateAo`
  and `oldLighting` went with them: Iris already defaults `gbuffers_water` to the blend this
  pack needs, and the rest were refinements that are not worth a failed load.
- **Every program declares `/* RENDERTARGETS: ... */` instead of `/* DRAWBUFFERS: ... */`**,
  matching the template and every current pack. Iris accepts both spellings, but the modern
  one is the path that is actually exercised by the pack this was built against.
- **The in-game settings screen and the three presets are gone for now**, because that screen
  is precisely what could not load. The tunables remain in `shaders/lib/settings.glsl` as
  compile-time defaults, and the README lists the four lines to change for the Performance
  and Visual cost profiles. They return once the pack is confirmed to load.

### Added

- The validator accepts both target-list spellings and checks the target count against the
  number of declared fragment outputs either way.

## [1.3.0] - 2026-11-27

This release is about one thing. Selecting the pack made Iris report that it had encountered
a problem while applying, the details pane showed nothing usable, and the cause turned out to
be this pack's own option declarations.

### Fixed

- **Every slider was declared as a `const`, and Iris does not accept that.** Iris' option
  parser registers a const option only when its name is in a fixed list
  (`OptionAnnotatedSource.VALID_CONST_OPTION_NAMES`: `shadowMapResolution`, `shadowDistance`,
  `voxelDistance`, `sunPathRotation`, `ambientOcclusionLevel`, `superSamplingLevel`,
  `noiseTextureResolution` and the shadow map flags). A
  `const float SUN_STRENGTH = 2.10; // [...]` is rejected with a diagnostic that only ever
  reaches the log, so twenty of the pack's options did not exist. `shaders.properties` then
  referred to all twenty from `screen.SCENE`, `screen.WATER`, `screen.COLOUR`, `sliders` and
  every `profile.*` line, and Iris builds the shader pack menu out of exactly those
  references — that is the step that failed while applying. Every user option is a `#define`
  now, which is what Iris expects and what the rest of the ecosystem ships.
- `SUN_STRENGTH`'s default was not one of its own allowed values, and the `0.8` and `1.25`
  softness values that two presets set were missing from `SHADOW_SOFTNESS`'s list.
- **The shadow pass declares a colour output again.** 1.2.0 removed it to save a 2048x2048
  RGBA8 write, 16.7 MB per frame that nothing reads. The saving is real, but a gbuffers-style
  program with no fragment output at all is the least ordinary construct in this pack, it
  cannot be verified without running the game, and it is not worth a few percent of bandwidth
  against the whole pack failing to load.

### Added

- `docs/TROUBLESHOOTING.md`. Iris' details pane is not ours to fix, so the page says how to
  get a real error out of the log instead: debug mode, `patched_shaders/`, and the exact
  strings to search for, with a table of what each one means. It also lists the pack parsing
  rules that are invisible from inside the GLSL — the const-option whitelist, the
  leading-comment rule on valued `#define`s, the allowed-values lists.
- Four more validator rules, each one a rule Iris actually enforces: a const option must use
  a whitelisted name, every fragment stage must declare an output, a conditional in
  `shaders.properties` must name a real option, and a value set by a preset must be one of
  that option's allowed values.

## [1.2.0] - 2026-11-26

Completes the pack against the brief and against Iris' documented behaviour. Two of the
fixes here change the image in ways that were plainly wrong before, and both were invisible
from inside the code until the pipeline was traced end to end.

### Fixed

- **The shadow pass never alpha tested.** Minecraft 1.17 and later do the cutout in the
  shader, not in fixed function state, so a shadow fragment stage that writes depth
  unconditionally gives every leaf block and every flower the shadow of a solid cube. The
  pass now carries the texture coordinate and applies the same coverage preserving
  threshold the visible pass uses, so the silhouette that casts the shadow is the silhouette
  that is drawn.
- **Lava and glowstone were shaded as ordinary lit surfaces** when they arrive through the
  translucent pass. They now take their material from the block ID, which is the emissive
  path.
- **Ambient occlusion read the wrong depth buffer** for translucent pixels: the normal taps
  came from `depthtex1` while the surface being shaded came from `depthtex0`, so behind a
  pane of glass the occlusion floated on the wall behind instead of sitting on the glass.

### Changed

- **The shadow pass is depth only.** It declares no colour output and no `DRAWBUFFERS` line,
  so Iris allocates no `shadowcolour0` and the pass stops writing a 2048x2048 RGBA8
  attachment that nothing in the pack reads: about 16 MB of write bandwidth per frame on a
  25 GB/s bus.
- **Contact shadows are used, not just written.** The shadow map is sampled for occlusion as
  well as for light, inside twenty blocks and folded out before that bound, so the corner
  where two blocks meet and the foot of a wall read as contact rather than as a flat
  junction. It multiplies the ambient term only; direct sunlight is already answered by the
  shadow lookup.
- `UNDERWATER_TINT` is a real option. The label existed with no option behind it. It now
  scales both the colour of the underwater medium and its density, and at 1.0 it gives
  exactly the previous look.

### Added

- Two more Iris rules in the validator: a stage that uses the compatibility built-ins must
  declare the compatibility profile, because that is the condition under which Iris patches
  them and it throws while transforming a vertex stage otherwise; and `mc_Entity` must be a
  `vec2`, as Iris documents it.

## [1.1.0] - 2026-11-25

The first release after 1.0.0, and the first one whose Iris loading path was checked against
Iris' own documentation and transform source rather than against OptiFine lore. It also
folds in two fixes that were written for a 1.0.1 that was never committed and never
published.

### Fixed

- **A duplicate uniform declaration in the composite translation unit.** `colortex0` was
  declared both by `lib/body/composite.fsh` and by `lib/water_composite.glsl`, which the
  former includes. Two declarations of the same uniform in one unit are a redefinition and
  Mesa rejects the program for it. One rejected program is enough for Iris to drop the pack
  and render the game as if no shader were selected, which is exactly the reported symptom:
  the pack looked identical to vanilla.
- `block.properties` used backslash line continuations. The Java properties format allows
  them; a loader that reads the file line by line does not, and a continuation line parsed
  as a bare key is at best ignored and at worst rejects the file. Every entry is now one
  line.
- A local named `near` in the shadow contact term shadowed Iris' `near` uniform. Legal, and
  not worth the risk.
- Screen space ambient occlusion oriented its reconstructed normal away from the camera, so
  the occlusion samples sat inside the surface. Creases read as fully lit and open surfaces
  as fully occluded. The normal is now oriented by the vector to the eye rather than by the
  sign of its z component.
- `normalize(toEye + lightDir)` in the water glitter term is undefined when the eye is
  exactly opposite the light relative to the surface, and one NaN spreads through the
  tonemapper and blacks out the frame. Guarded with an epsilon.

### Changed

- **Water is recognised three ways instead of one.** The block ID from `block.properties`
  stays primary; Iris' legacy numbering (8 and 9, used when the file is absent) and the
  render type in `mc_Entity.y` are now fallbacks, and the render type keeps lava out of the
  water branch when the ID map has not resolved. The whole water pipeline hanging on one
  file being parsed was the largest silent failure point in the pack.
- **The water data buffer is `RGBA16F` instead of `RGBA8`.** The surface normal was packed
  into two 8 bit channels, which left roughly 40% quantisation noise on the finest wave
  octave. The buffer is written only on water pixels and read once, so 4 extra bytes per
  pixel are affordable and the surface stops being steppy.
- `separateAo = true`. Vanilla's smooth lighting occlusion now arrives in the vertex colour's
  alpha, which is where the lighting model always assumed it was, instead of being baked
  into the albedo. The translucent pass takes its blend alpha from the texture rather than
  from the vertex colour so this cannot make glass more transparent at its edges.
- The cloud coverage mapping was recalibrated. A single octave of value noise concentrates
  around 0.5, so the previous base threshold left only about a fifth of the sky carrying
  cloud and the deck read as wisps rather than as weather. `CLOUD_COVERAGE` now spans a
  sparse deck at 0 to an overcast one at 1, and the cheap cloud sample used by water
  reflections matches it.

### Added

- The static validator rejects a second global declaration of the same name, which is the
  class of error that took the pack down to vanilla.
- The README states plainly that this pack is Iris only, and which directives make it so.

## [1.0.0] - 2026-11-24

First release. A complete, independent shader pack: three passes (shadow, geometry,
composite) plus a final grade pass, built and tuned for an Intel HD Graphics 5500.

### Added

**Water**

- Water is no longer shaded in the geometry pass. `gbuffers_water` writes only a surface
  normal and a mask, leaving the opaque scene intact in `colortex0`, which is what makes
  true refraction possible without a second copy of the frame.
- Screen space reflection with geometric step growth, hitting geometry then falling back
  to a sky reflection that includes one layer of cloud.
- Per channel absorption over the water column depth read from the two depth buffers:
  red extinguishes at 0.42 per block against 0.055 for blue.
- Refraction offset by the surface slope, rejected where the sample would pull dry land
  into the shoreline.
- Five-component directional wave normals with constant steepness across the octaves, plus
  a two-octave non-repeating ripple near the eye, faded by distance.
- Schlick Fresnel at water's real F0 of 0.02, and two sun glitter lobes.
- Vanilla water texture modulation preserved through the data buffer, so the surface still
  reads as Minecraft's water.

**Sky and atmosphere**

- One Rayleigh plus Mie atmosphere model drives the sun colour, the sky's warm band, the
  cloud lighting and the fog tint, so they cannot disagree at sunrise.
- Physically tinted sun and moon discs, and a procedural star field in two brightness
  layers.
- Fog that fades to the sky's own horizon colour, evaluated from the same function.

**Clouds**

- Volumetric-style slab march with front-to-back transmittance accumulation.
- Density field from a fixed anisotropic domain shear, a height-rising threshold that turns
  a noise field into cumulus, and edge erosion above the base.
- Analytic per-sample lighting with a normalised Mie forward lobe for silver linings, and a
  horizon LOD that cross-fades to a low frequency field instead of aliasing into dots.
- Separate cirrus veil above the deck.

**Vegetation**

- Leaf transmission with a fourth power backlit rim term, tinted by the foliage albedo.
- Steeper than terrain ambient response for foliage.
- Wind from a smooth travelling gust field in absolute world space, with amplitude
  modulation, matched exactly between the visible and shadow passes.
- Wind weight derived from the texture's v coordinate, because no function of world height
  can distinguish a plant's base from its tip.

**Lighting**

- Forward lighting in the geometry pass, with wrapped diffuse, hemisphere ambient, a deep
  blue night floor, and block light only partly occluded by vertex AO.
- One 2048 shadow map with a per-pixel rotated nine-tap golden angle spiral, split depth and
  normal bias, and edge and range fades.
- Screen space ambient occlusion in composite, faded out entirely by 46 blocks so it never
  touches the fog.
- ACES tone mapping, white balance, saturation, contrast and a controlled vignette.
- FXAA operating on the HDR image so tone mapping happens once.

**Project**

- Static validation covering includes, brace and preprocessor balance, function resolution,
  sampler validity, cross-stage varying agreement, `DRAWBUFFERS` counts and option
  consistency. Run on every push and every pull request.
- Packaging into a correctly rooted installable zip, uploaded as a build artifact.
- Release automation: bumping `VERSION` on `main` builds, validates and publishes a release
  with the zip attached.
- Three presets that differ in rendering cost, not in labels.
- `block.properties` ID map with a graceful fallback if it is ever unreadable.

### Validation

- Automated static validation passes on `main` (Ubuntu, Python 3): includes, brace and
  preprocessor balance, function resolution, sampler validity, cross-stage varying
  agreement, `DRAWBUFFERS` counts, option consistency, block ID agreement, packaging.
- It found two genuine compile errors before this release, both fixed:
  `water_composite.glsl` called `aetherisUnpackWaterNormal` without including
  `water.glsl`, and `composite.vsh` / `final.vsh` carried no option constants because
  `uniforms.glsl` did not include `settings.glsl`.

### Known limitations

- No bloom. A two-pass blur chain is not affordable at 720p on 24 execution units, and a
  cheap single-pass one does not look like bloom.
- No volumetric light shafts. The Mie forward scattering in the sky and the fog is the
  substitute.
- No temporal reprojection anywhere. Every pass is stateless, which avoids ghosting and
  TAA smearing but means the dither patterns are the antialiasing for the cloud and
  reflection marches.
- Reflection fallback includes one cloud layer, not the full march, because a full march per
  reflected ray would double the cloud cost.
- Water geometry is not displaced.
- Eye adaptation and motion blur are deliberately absent.
- Statically validated only. Not yet run in Minecraft.
