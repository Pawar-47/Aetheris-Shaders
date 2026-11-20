# Changelog

All notable changes to Aetheris Shaders are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

A release is made when there is something worth installing, not when a number changes.

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
