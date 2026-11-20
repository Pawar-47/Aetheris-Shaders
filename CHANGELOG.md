# Changelog

All notable changes to Aetheris Shaders are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

A release is made when there is something worth installing, not when a number changes.

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
