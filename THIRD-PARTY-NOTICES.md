# Third party notices

Aetheris Shaders is MIT licensed and contains no third party shader code. Nothing here
has been copied from BSL Shaders, Complementary Shaders, Spectrum, Nova Shaders, SiraLite
Shaders, or any other pack.

This file records what was studied and what, precisely, was and was not taken from it.
It exists because "inspired by" is not a licence term and it is worth being exact.

---

## Code

**None.** Every line of GLSL in `shaders/` was written for this project. No file, function,
constant table or shader stage was copied, ported or mechanically translated from another
shader pack.

## Techniques and published methods

These are mathematical techniques published in the open, in papers or in widely circulated
reference implementations. Algorithms and mathematical methods are not copyrightable, and
these are used as methods, implemented independently against the descriptions.

| Method | Where it comes from | How it appears here |
|---|---|---|
| ACES filmic tone curve, polynomial fit | Krzysztof Narkowicz, "ACES Filmic Tone Mapping Curve" (2016), a public fit of the ACES RRT+ODT | `acesTonemap` in `lib/util.glsl`, the standard 2.51/0.03/2.43/0.59/0.14 coefficients |
| Rayleigh and Mie scattering coefficients, Henyey-Greenstein phase | Standard atmospheric optics literature | `lib/atmosphere.glsl`, written from the physical relations, with the phase lobe renormalised so its forward peak is exactly 1.0 |
| Smooth airmass approximation | Classic atmospheric path-length approximation; related to Kasten-Young | `airmass()` in `lib/atmosphere.glsl`, reduced to `1/sqrt(cos²+eps)` |
| Schlick's approximation for Fresnel | Christophe Schlick (1994) | `aetherisWaterSurface` in `lib/water_composite.glsl`, written out as multiplies |
| Integer-free float hash and value noise | Dave Hoskins, "Hash without Sine" (MIT / public domain, 2014), a widely circulated public-domain technique | `aetherisHash` in `lib/util.glsl`, with own constants; `valueNoise` and `valueNoiseGradient` built on it |
| Bayer ordered dithering | Bryce Bayer, Kodak (1973) | The 4x4 matrix in `lib/util.glsl` |
| FXAA | Timothy Lottes, NVIDIA, "FXAA 3.11" (public domain reference implementation) | `aetherisFXAA` in `lib/post.glsl`, a compact reimplementation of the console variant, operating on HDR values |
| Screen space reflection by depth ray marching | Standard real-time rendering technique | `aetherisScreenReflection` in `lib/water_composite.glsl` |
| Hemisphere ambient, wrapped diffuse, Blinn-Phong specular | Standard real-time shading literature | `lib/lighting.glsl` |
| Golden angle spiral sampling | Standard quasi-random sampling technique | The shadow and AO tap tables |
| Cumulus density from a height-rising threshold | General approach to procedural cloud shaping | `aetherisCloudDensity` in `lib/clouds.glsl` — the specific field construction, shear and erosion are this project's |

No code was taken from any of these sources. What was taken is the underlying mathematics,
which is what a technique is.

## Structural reference

- **[ascpixi/minecraft-shader-template](https://github.com/ascpixi/minecraft-shader-template)**
  was read for its project layout, its approach to separating program wrappers from
  implementation bodies, and its CI and packaging structure. Its Gradle build and its
  Gradle based toolchain were **not** adopted: this pack has no build step, no dependency,
  and packages with `zip`. No file from that template is present in this repository. The
  `lib/body/` split used here is a common convention across many packs rather than
  something taken from that repository specifically.

## Assets

**None.** This pack ships no textures, no models, no sounds, no fonts and no data files
beyond its own configuration. It uses vanilla Minecraft's assets through the shader
pipeline and nothing else. There is no companion resource pack and none is required.

## Iris and Minecraft

- **Iris Shaders** — the shader loader this pack targets. Iris's own code is not included
  or modified. Its shader interface documentation and its uniform semantics are used as
  specified.

  Iris is also the authority the pack's compatibility was checked against, rather than
  OptiFine lore: the version statement rules, the `mc_Entity` attribute, the
  `shaders.properties` directives and the order in which buffer transformations run were
  all read from Iris's documentation, and its transformation source was read for behaviour
  only — what it replaces a legacy built-in with, and under which conditions it throws.
  Nothing was copied from it and no Iris code is redistributed here.
- **Minecraft** — assets are used through the game's own shader interface. No game assets
  are redistributed here.

## Development tooling

- **Python 3** — `tools/validate.py` uses only the standard library.
- **GitHub Actions** — `actions/checkout`, `actions/setup-python`,
  `actions/upload-artifact` (all MIT, GitHub) and `softprops/action-gh-release` (MIT).

## If you believe something is missing here

Open an issue. The intent is that this file is complete and accurate, not that it is
defensive.
