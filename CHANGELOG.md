# Changelog

All notable changes to Aetheris Shaders are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

A release is made when there is something worth installing, not when a number changes.

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
