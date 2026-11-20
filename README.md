# Aetheris Shaders

A Minecraft Java shader pack for Iris, written from scratch for one specific machine:
an Intel Core i3-5005U with Intel HD Graphics 5500 and 8 GB of RAM on Linux Mint.

Aetheris is not a BSL fork, a BSL derivative, or a reskin of one. It is an independent
implementation, structured and tuned around the limits of a 24 execution unit Broadwell
integrated GPU, with BSL Shaders as its artistic reference. Where BSL's look comes from a
particular way of handling light, atmosphere and water, this pack studies that principle
and re-derives its own version of it at a fraction of the cost.

**Branch build: 1.6.1 (perf/full-feature-performance).** CI logs show static validation,
GLSL compilation/linking of all 46 stages, option and block-ID checks, and ZIP packaging
succeeded. The workflow's final state is still reported as in progress, despite the logs
showing artifact upload completed. This is not an in-game verification: Iris loading,
visual output and frame rate on the target laptop remain untested. No 1.6.1 GitHub Release
has been published from this branch. See [verification status](#what-has-and-has-not-been-verified).

### Iris, not OptiFine

This pack is written for **Iris 1.8.x on Minecraft 1.21.5**, and follows the Iris 1.21.5
shader template layout: `RENDERTARGETS` instead of the OptiFine-era `DRAWBUFFERS`, and
`mc_Entity` for block identity. It is not tested under OptiFine and is not meant to be.

---

## Target hardware

| Component | Specification |
|---|---|
| CPU | Intel Core i3-5005U, 2.00 GHz, 2 cores / 4 threads |
| GPU | Intel HD Graphics 5500 (Broadwell GT2, 24 EU, 0.30-0.90 GHz, shared memory) |
| RAM | 8 GB |
| OS | Linux Mint |
| Minecraft | Java Edition 1.21.5, SK Launcher |
| Shader loader | Iris 1.8.x |
| Optimisation | Sodium |

This is a single-machine project. It is not trying to be all things on all GPUs. The
defaults in `shaders/lib/settings.glsl` are the settings this hardware was designed
against, not a compromise between a laptop and a desktop.

---

## Installation

1. Install **Iris 1.8.x** and **Sodium** for Minecraft 1.21.5.
2. Download `Aetheris-Shaders-<version>.zip` from
   [Releases](../../releases).
3. Drop it in `.minecraft/shaderpacks/` without unzipping it. On Linux Mint that is
   usually `~/.minecraft/shaderpacks/` or inside the SK Launcher instance folder.
4. In game: `Options -> Video Settings -> Shader Packs -> Aetheris Shaders`.
5. Press **Ctrl + D** on that screen first if anything goes wrong: it enables Iris' debug
   mode, which writes the post-processed source to `patched_shaders/` and makes every error
   in `logs/latest.log` point at a real file and line. See
   [Troubleshooting](docs/TROUBLESHOOTING.md).

If Iris refuses to apply the pack, install `Aetheris-Probe-<version>.zip` from the same
release first. It is two files and no configuration, and it answers one question: whether
*any* shader pack loads on your setup at all. If the probe loads and Aetheris does not, the
fault is here and `logs/latest.log` will name it; if the probe also fails, the problem is the
Iris install, the Minecraft version, or where the zip was placed.

No resource pack is required and none is provided. Every effect in this pack is
achieved in shader code over vanilla assets.

### Suggested companion settings

These are outside the pack and are the difference between playable and not on this GPU:

- Render distance **6 to 8 chunks**
- **Smooth Lighting: Maximum**
- **Fancy/Fast graphics** as you prefer; clouds can stay on in vanilla because the pack
  disables them, and the setting no longer matters
- Resolution **1280x720 or lower**, fullscreen off. This is the single biggest lever
  there is
- Sodium's **Chunk Builder** on "Multi-threaded" to use both cores of the i3

---

## Presets

The low-end preset is deliberately **feature-preserving**. Performance mode reduces the
cost of each effect; it does not remove shadows, AO, water reflections, clouds, antialiasing,
bloom, light shafts or material gloss. “Recommended for HD 5500” is the default profile and
uses the same settings as “Performance”; “Balanced” and “Visual” spend progressively more
GPU time for higher quality.

| Preset | Shadows | AO | Water reflections | Clouds | Post effects |
|---|---|---|---|---|---|
| **Recommended / Performance** | 1024 map, 64 blocks, 4 taps | 4 samples | 5 steps | 5 steps, detail and cirrus on | FXAA, bloom, 4-step screen-space shafts, gloss |
| **Balanced** | 2048 map, 80 blocks, 6 taps | 6 samples | 6 steps | 8 steps, detail and cirrus on | FXAA, bloom, 6-step shafts, gloss |
| **Visual** | 2048 map, 128 blocks, 9 taps | 9 samples | 10 steps | 12 steps, detail and cirrus on | FXAA, bloom, 8-step shafts, gloss |

Bloom and light shafts use two buffers at 25% of the screen width and height (6.25% of
full-resolution pixels), followed by one final upsample. The Performance profile keeps
these effects enabled with lower sample counts and strengths. The implementation is
intended to keep the visual feature set while bounding its cost on the HD 5500; actual FPS
and image quality still need to be measured in Minecraft.

---

## What it does

### Water

The strongest feature, and the one with the most deliberate engineering behind it.

The translucent pass **writes no colour for water at all**. It writes only the surface
normal and a mask, leaving `colortex0` holding the opaque scene underneath. That single
decision is what allows real refraction without a second copy of the frame: the composite
pass samples the actual lake bed at an offset along the surface slope, and what it reads
is genuinely what is under the water, not a screen-space blur of something that already
had water mixed into it.

Two things downstream of that decision were wrong until 1.1.0 and are worth stating,
because both are the kind of fault that does not look like a fault:

- The data buffer was `RGBA8`, so the packed normal carried about 40% quantisation noise on
  the finest wave octave — steppy water, not smooth water. It is `RGBA16F` now, written
  only on water pixels and read once.
- Water was recognised by one signal: its block ID from `block.properties`. It is now
  recognised by the ID, by Iris' legacy IDs 8 and 9, and by the render type in
  `mc_Entity.y`, with the render type keeping lava out of the branch when the ID map has
  not resolved. If all three fail, water falls through to the plain translucent path and
  looks like vanilla water, which is a very quiet way for the pack's headline feature to
  disappear.

From there, in the order light actually takes:

1. **Refraction**, offset by the surface slope, rejected where the sample would drag dry
   land into the water at a shoreline.
2. **Absorption**, per channel: red dies about eight times faster than blue, which is why
   deep water is blue-green and shallow water is not.
3. **In-scattering**, the light that bounced around inside the body.
4. **Reflection**: a screen-space march with geometric steps that grow with distance,
   falling back to a sky reflection that includes one layer of cloud so the water is not
   reflecting an empty blue void.
5. **Fresnel**, Schlick with water's real F0 of 0.02.
6. **Glitter**: two sun lobes, a tight one that rides individual wave crests and a broad
   one that gives the surface a sheen towards a low sun.
7. **The underwater medium**, one option that scales both its colour and its density, so a
   lake seen from inside reads as a body of water rather than as a blue filter over the
   screen.

The wave normals are five directional components whose amplitude falls with wavelength at
a constant ratio. That ratio is the wave steepness, and holding it constant across the
octaves is what makes the sum read as one body of water instead of five sine waves. The
three finest fade with distance, because beyond thirty blocks a one-block wavelength is
below a pixel and can only alias into crawling glitter.

Water geometry is not displaced. Vanilla water is a flat plane, and moving its vertices
tears the surface at every biome and chunk boundary for almost no visual return — at eye
level, all the information in water is in its normal, not its silhouette.

### Sky and atmosphere

One atmosphere model drives everything. The sun and moon tint and dim through an
exponential Rayleigh plus grey Mie atmosphere, with optical path length from
`airmass(cosZenith) = 1/sqrt(cosZenith² + eps)` — finite at the horizon, one inverse
square root, no `acos`. The sky's own dome gradient is driven by that transmittance, so
the warm band appears exactly where the physical path length peaks instead of following a
hand-keyframed sunset ramp. The fog fades to the *same function* evaluated at the horizon,
which is why there is no seam where the world ends.

Honest scope: the dome's luminance ramp is authored, not integrated. A full single
scattering integrator was evaluated and rejected for 1.0.0 — four times the cost per sky
pixel, and without a sun disc to calibrate against, as likely to produce a flat cyan sky
as a beautiful one. `docs/PERFORMANCE.md` states this without dressing it up.

### Clouds

A slab, walked front to back, accumulating transmittance — not a painted dome, and not
boxes. Depth comes from that accumulation: back puffs are genuinely hidden behind front
ones and a tonal ramp runs across a single puff.

Organic shape comes from three things done deliberately:

1. A **fixed anisotropic shear** of the domain, so masses are broad ellipses at an angle
   to each other instead of round, evenly spaced puffs. The transform is never animated:
   domain-warping a field every frame makes clouds shear and swim, which is the most
   common way procedural clouds look cheap.
2. A **threshold that rises with height** inside the slab. Near the base almost half the
   field is dense so bottoms are flat and continuous; by the top only the tallest peaks
   survive so crowns break into separate rounded puffs. The union of those silhouettes is
   what the eye reads as fluffy.
3. **Edge erosion** from a higher frequency octave, scaled in only above the base.

Lighting is analytic per sample — dark base, bright crown, thick cores grey — plus a
forward scattering lift from a normalised Mie lobe. No shadow lookups and no per-sample
light march, which is what keeps this affordable on 24 execution units. A thin cirrus veil
sits above the deck, drawn with two stretched noise samples and no march.

### Vegetation

Shader code cannot change the shape of a vanilla leaf block or a grass tuft, and this pack
ships no resource pack. What it can do is decide how those flat quads are lit and how they
move, and that is where every improvement here comes from.

- **Leaf transmission**: a leaf is a thin translucent membrane, and the light that comes
  through it is tinted by what the pigment did not absorb and is strongest when you are
  looking into the light. Fourth power rim term, so a canopy against a low sun glows and
  the same canopy with the sun behind you does not.
- **Steeper ambient than terrain**: leaves are thin, so the difference between a face
  looking up and one looking down is larger than for a wall. This is the single biggest
  visual difference between vanilla foliage and shader foliage.
- **Wind** driven by a smooth travelling gust field sampled in absolute world space, not
  by a per-block hash. A per-block random phase makes every leaf block move on its own and
  tears the canopy apart at the block seams. Amplitude is modulated by the same field, so
  vegetation moves in patches as gusts cross it with calm space in between.
- **Wind weights come from the texture's v coordinate, not from world height.** A plant's
  base and its tip are exactly one block apart in world space, and every 1-periodic
  function of height returns the same value for both — a pack that sways grass by
  `fract(worldPos.y)` is swaying nothing at all.
- The **shadow pass calls the same wind function with the same absolute position**, so a
  swaying leaf's shadow sways with it.

Block identity comes from `shaders/block.properties`. If that file is ever missing every
block reports ID 0 and the pack degrades gracefully: foliage gets plain terrain shading
and wind stops.

### Lighting

Forward lighting, in the geometry pass, where the albedo already is. On a 25 GB/s shared
memory bus that avoids an albedo and normal buffer write and read every frame at full
resolution, and avoids a second round of shadow lookups for the same fragment. Overdraw is
the cost, and on Minecraft terrain it is small.

Wrapped diffuse so a block's terminator is not a hard painted line. Hemisphere ambient
that gives every shape a top-lit gradient. Block light only partly occluded by vertex AO,
so a torch can still reach into a corner. A deep blue night floor, because a neutral one
is what makes cheap night scenes look like a dimmed day. The Performance profile uses one 1024 shadow map with four taps; higher profiles increase
map resolution, distance and taps. The directional shadow and near-field contact term
reuse the same depth reads.

Two things about that pass are worth naming, because both were wrong at some point and
neither is visible from inside the shading code:

- **The shadow pass applies the cutout.** Minecraft 1.17 and later do it in the shader, not
  in fixed function state, so a shadow fragment stage that writes depth unconditionally
  gives every leaf block and every flower the shadow of a solid cube. The pass carries the
  texture coordinate and uses the same coverage threshold as the visible pass.
- **The same map is sampled for occlusion, not just for light**, inside twenty blocks and
  folded out before that bound. That is what makes the corner where two blocks meet and the
  foot of a wall read as contact rather than as a flat junction. It multiplies ambient only.

The pass writes a colour target it never reads, because this pass exists for its depth.
1.2.0 removed that write to save 16.7 MB per frame and 1.3.0 put it back: a gbuffers-style
program with no fragment output is the least ordinary thing this pack could ask a loader to
accept, and it is not worth a few percent of bandwidth against a failure to load.

---

### Post-processing and material response

Bloom is extracted from the lit scene into a low-resolution buffer and softened with a
five-tap blur. Light shafts are a bounded screen-space radial sample from the projected sun,
accumulated only where the depth buffer says the sample is sky. They are a **volumetric-style
screen-space approximation**, not a full 3D participating-media simulation. Both effects
share the same low-resolution pipeline. Material gloss is a simple Blinn-Phong highlight
for a curated set of metallic/polished block IDs; it is not PBR and requires no companion
resource pack.

---

## What has and has not been verified

The evidence below is tied to the perf/full-feature-performance branch at commit
4a6b686a3a4f5dae2ae0fd4fd8bc5298f2630746.

**Completed steps in the recorded GitHub Actions job**

- Static validation completed successfully.
- The GLSL check reported: **“All 46 stages compile, and every program links.”**
- The block ID map and material constants agreed, including the new gloss material ID.
- Every settings option had a language label.
- The packaging script produced Aetheris-Shaders-1.6.1.zip with 85 files (146,284 bytes
  uncompressed; 64,357 bytes uploaded as the CI artifact).
- The artifact upload step reported success.

The Actions API still reports that run as in progress even though the job log reaches the
successful artifact-upload message. I therefore do not label the workflow's final conclusion
green until GitHub records a terminal result.

**Not verified**

- The pack has not been confirmed loading in Iris on Minecraft 1.21.5.
- The shader output has not been visually inspected in a live world.
- No FPS, frame-time, GPU temperature or memory measurements have been taken on the
  Core i3-5005U / HD 5500.
- CI's GLSL transformation is a useful compatibility check, but it is not a substitute for
  Iris' own shader preprocessing and a real OpenGL driver.

Do not treat the 1.6.1 artifact as a tested release. The next meaningful test is to install
that exact artifact in the SK Launcher instance, enable Iris debug mode, and capture
logs/latest.log plus the rendered result. If the pack loads, benchmark the same scene at a
fixed resolution and render distance before changing the defaults.

---

## Repository layout

```
shaders/
  shaders.properties     options, presets, blend states, what to suppress
  block.properties       block ID map for vegetation, water and emissive blocks
  lang/en_us.lang        option labels
  <program>.vsh/.fsh     thin wrappers, one pair per Iris program
  lib/                   the actual implementation
    settings.glsl        every option and constant
    uniforms.glsl        Iris uniform declarations, and the space conventions
    util.glsl            colour space, hash, noise, dither
    atmosphere.glsl      the sun/sky/fog colour model
    sky.glsl             dome, sun, moon, stars
    clouds.glsl          the cumulus march and the cirrus veil
    shadow.glsl          shadow sampling
    lighting.glsl        the forward surface lighting model
    vegetation.glsl      foliage identity, wind, leaf transmission
    water.glsl           wave normals and packing
    water_composite.glsl refraction, absorption, reflection, Fresnel, glitter
    ssao.glsl            screen space ambient occlusion
    fog.glsl             height fog, distance haze, underwater
    post.glsl            FXAA, tonemap, grade
    depth.glsl           depth and screen space conversions
    body/                one body per pass family, included by the wrappers
  composite1/2          low-resolution bloom and screen-space light-shaft stages
tools/
  validate.py            static validation, run in CI
  package.sh             builds the installable zip
docs/PERFORMANCE.md      the hardware budget and why each decision follows from it
```

---

## Licence

MIT. See [LICENSE](LICENSE).

No third-party shader code is included. See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)
for the techniques and published material that were studied, and what was and was not
taken from them.

Aetheris is a separate project from Nova Shaders and SiraLite Shaders and shares no code
with either.
