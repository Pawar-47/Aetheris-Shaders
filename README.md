# Aetheris Shaders

A Minecraft Java shader pack for Iris, written from scratch for one specific machine:
an Intel Core i3-5005U with Intel HD Graphics 5500 and 8 GB of RAM on Linux Mint.

Aetheris is not a BSL fork, a BSL derivative, or a reskin of one. It is an independent
implementation, structured and tuned around the limits of a 24 execution unit Broadwell
integrated GPU, with BSL Shaders as its artistic reference. Where BSL's look comes from a
particular way of handling light, atmosphere and water, this pack studies that principle
and re-derives its own version of it at a fraction of the cost.

**Status: 1.0.0. Statically validated, not yet run in a game.** See
[What has and has not been verified](#what-has-and-has-not-been-verified) before you
expect anything from it.

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
5. Start with the **Balanced** preset. It is the default for a reason.

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

Three real presets, each a genuinely different rendering cost and not a relabelling.

| Preset | Shadows | AO | Water reflections | Clouds | FXAA |
|---|---|---|---|---|---|
| **Performance** | pass disabled entirely | off | off | 5 steps, no detail octave, no cirrus | off |
| **Balanced** (default) | 2048, 6 taps, 96 blocks | 6 samples | 8 steps | 8 steps, detail, cirrus | on |
| **Visual** | 2048, 9 taps, 128 blocks | 9 samples | 10 steps | 12 steps, detail, cirrus | on |

Performance removes whole passes rather than shaving quality everywhere: no shadow
render pass, no ambient occlusion, no reflection march, no antialiasing pass. The pack
still looks like Aetheris, because the things that define its look — the atmosphere
model, the sky, the water body colour, the wave normals, the sun disc, the tone curve —
are all still there.

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
is what makes cheap night scenes look like a dimmed day. Soft shadows from one 2048 map
with a per-pixel rotated nine-tap spiral.

---

## What has and has not been verified

This is important, and it is stated plainly rather than buried.

**Verified in CI** — this passes on `main`. It has already earned its keep: during
development it found two genuine compile errors (a missing include in the composite path,
and two vertex stages carrying no option constants) that would have sent the whole pack
back to vanilla rendering.

- Every `#include` resolves to a file that exists.
- Braces and `#if`/`#endif` balance in every translation unit.
- Every function called is defined in the same unit or is a GLSL built-in — this is what
  catches a misspelled or missing library function.
- Every sampler is one Iris actually binds.
- Every varying a fragment stage reads is written by its vertex stage with the same type.
  These are link errors that no per-file check can see.
- `DRAWBUFFERS` lists exactly as many targets as the fragment stage declares outputs.
- `shadowMapResolution` and `shadowDistance` are declared exactly once per unit.
- Every option named in `shaders.properties` exists in `settings.glsl`, and every option
  has a label.
- `block.properties` IDs agree with the constants in `vegetation.glsl`.
- The pack zips into the correct layout.

**Not verified**

- GPU compilation. No GLSL compiler was run against this pack. `glslangValidator` is not
  usable here at all: gbuffer programs depend on the OpenGL compatibility profile, and
  `gl_ModelViewMatrix`, `gl_Vertex`, `gl_Color` and `gl_MultiTexCoord1` have no core GLSL
  equivalent, so a generic validator rejects the entire pack for reasons that say nothing
  about whether it works in Iris.
- Runtime behaviour in Minecraft, on this GPU or any other.
- Frame rate. The budget reasoning in `docs/PERFORMANCE.md` is arithmetic, not a
  measurement.
- Visual quality. Every colour and every constant was chosen by design and by reference to
  what these techniques look like in other packs. None of it has been looked at on screen.

The first person to load this pack is the first person to see it. Expect to need to tune
it. `DEVELOPMENT_CHECKPOINT.md` lists exactly which numbers are most likely to need it and
in which direction.

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
