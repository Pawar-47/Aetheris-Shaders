# Performance notes: why this pack looks like this

The target is an Intel HD Graphics 5500: Broadwell Gen8, 24 execution units, 16 wide SIMD,
0.30 to 0.90 GHz, no dedicated memory. It shares a roughly 25.6 GB/s bus with a Core
i3-5005U and its 8 GB of DDR3.

That works out to somewhere around 0.4 to 0.7 TFLOP/s at full clocks, with texture
throughput as the harder limit. The CPU side matters too: two cores at 2.0 GHz with no
turbo is not much room to build chunks in.

This file records the arithmetic and the decisions that follow from it, so that each
choice can be checked rather than taken on trust.

---

## The fill rate budget

At 1280x720 there are 921,600 pixels. At 60 fps a frame is 16.7 ms, and a shader pack has
to leave most of that to the game, to Sodium's chunk draws, to the shadow pass geometry and
to the driver. A realistic target is **4 to 6 ms of fragment work produced by the pack
itself**, which on this part is roughly **2 to 3 GFLOP per frame** at best.

Divide that by 921,600 pixels and the whole screen has a budget of about **2,000 to 3,000
arithmetic operations per pixel across every pass**, and considerably fewer texture fetches
because Gen8 has 4 texture units and they are the bottleneck well before the ALU is.

That single number explains nearly every decision in this pack.

---

## Decision: three passes, not seven

The pack renders in this order:

1. **shadow** — one depth map, one geometry submission
2. **gbuffers_*** — one geometry submission, forward lit
3. **composite** — sky, clouds, water, ambient occlusion
4. **final** — FXAA, tonemap, grade

Four fullscreen-ish operations, two of which are fullscreen. There is no bloom chain (three
to five passes), no volumetric light pass, no deferred geometry pass, no temporal
antialiasing with its history buffer, and no depth of field.

A 720p fullscreen pass that fetches one texel per pixel already costs about 0.9 million
fetches. Four extra fullscreen passes is 3.7 million extra fetches before any of them does
anything interesting. That is not affordable here.

---

## Decision: forward lighting, not deferred

Lighting happens in the geometry pass, where the albedo already is.

Cost of deferred instead:

- A full resolution albedo buffer write in geometry, then a full resolution read in
  composite. At 1280x720 with RGBA16F that is 7.4 MB written plus 7.4 MB read **per frame**
  on a 25.6 GB/s bus shared with the CPU. Roughly 0.6 ms of pure bandwidth, before anything
  is computed.
- A full resolution normal buffer, same again.
- A view position reconstruction per pixel in the lighting pass.
- The shadow lookup happens in the deferred pass, so it happens once per *pixel* rather
  than once per *fragment*, which is a win — but only where overdraw is high, and Minecraft
  terrain overdraw is low.

What forward gives up is screen space ambient occlusion applied before lighting. AO is
applied in composite as a multiplier over the lit result, which cannot distinguish sunlight
from ambient. That is a real inaccuracy and it is accepted: it is a second order error next
to the bandwidth it saves.

AO is additionally **faded out completely by 46 blocks**, so most of a typical frame skips
it entirely — a single depth fetch and a branch.

---

## Decision: bounded loops the user can turn down

Every loop in the pack is bounded by a constant, and every one of those constants is
exposed:

| Loop | Balanced | Cost |
|---|---|---|
| Shadow taps | 6 | 6 shadow fetches per lit, shadowed fragment |
| AO samples | 6 | ~10 depth fetches per pixel within 46 blocks |
| Reflection steps | 8 | 8 depth fetches + 1 colour fetch, water pixels only |
| Cloud steps | 8 | 8 density evaluations, sky pixels only |

None of them use a `while` with an early out as the primary control, because the compiler
cannot bound a `while` and the branch cost on Gen8 is not free. Early outs exist inside the
loops (`break` when transmittance is negligible, `continue` when a sample is off screen) but
the trip count the compiler sees is constant.

---

## Decision: work is skipped by region, not just by quality setting

The composite pass visits three kinds of pixel and does very different work on each:

- **Sky** (depth = 1): the dome, clouds. Expensive but it is the point of the pack.
- **Water** (flagged in `colortex2`): full surface shading. Only water pixels pay.
- **Opaque** (everything else): one texture fetch, an AO lookup if within 46 blocks, done.
  **No fog** — fog was applied forward in the geometry pass, where the albedo exists and
  where it happens once per visible fragment rather than once per pixel behind overdraw.

That last line is the whole performance story at a glance. Most of a typical frame costs one
fetch.

Clouds and reflection rays are both gated on the branch that reaches them, and both
evaluate their expensive phase function only after a sample proves there is density or a
hit.

---

## Decision: no bloom

Bloom needs a bright pass, a downsample chain and an upsample. Even the cheapest version is
three passes.

A single-pass approximation at full resolution was considered: 13 taps at doubled offsets.
That is 12 million texture fetches per frame to add a soft glow, which is more than the
entire water system costs. It was rejected rather than made cheap enough to be pointless.

The substitute is the tonemap. ACES rolls highlights off over about two stops instead of
clipping them, so a bright sky and a sunlit water surface keep their shape without a glow
layer. It is not the same effect and the README does not pretend it is.

---

## Decision: cloud march at eight steps

Eight samples through a 74 block slab is a step every nine blocks. That sounds too coarse
and would be, except for two things:

1. The density field is low frequency by construction — one feature per ~230 blocks — so
   eight samples across a mass is enough to resolve its shape.
2. The lighting is analytic per sample, not integrated along a light ray. There is no
   second march that would need more samples to converge.

Cylindrical bands from a coarse march are hidden by a Bayer jitter on the ray start plus
the smooth transmittance accumulation. Near the horizon the march steps span hundreds of
blocks, and there the code deliberately **cross-fades to a broad low frequency field** with
capped optical depth and a fade into the haze, rather than pretending the fixed budget can
resolve something that far away.

12 steps in the Visual preset is the most this GPU should ever see.

---

## Decision: one 2048 shadow map, 96 blocks

Shadow resolution per block is `2 * shadowDistance / shadowMapResolution`. At 96 blocks and
2048 that is 9.4 cm per texel, which is fine with a six tap spiral. At 128 blocks and 2048
it is 12.5 cm and still acceptable.

A second cascade would nearly double the geometry submission cost of the entire pack for a
benefit visible only beyond a hundred blocks — which is inside the fog anyway, on this
render distance.

`SHADOWS = 0` sets `shadow.enabled = false` in `shaders.properties`, which removes the
render pass entirely rather than leaving it running unsampled. That is about a third of the
vertex work back.

The pass is depth only: no colour output and no `DRAWBUFFERS`, so Iris allocates no
`shadowcolour0` buffer and the pass does not write a 2048x2048 RGBA8 attachment every
frame. That attachment is 16.7 MB, and writing it once per frame at 40 fps is about
670 MB/s of the 25 GB/s bus for data nothing reads. The one fetch the pass does pay for is
the texture sample in the fragment stage, which is the cutout — without it every leaf casts
the shadow of a full block, so it is not optional.

---

## Decision: camera-relative world space throughout

All lighting, shadow transforms and fog are done in camera relative world space, converted
once in the vertex stage. The alternative, converting per fragment, repeats the work for
every pixel of every surface. The cost of the conversion is one matrix multiply per vertex,
which is nothing.

---

## Decision: sRGB conversion by polynomial in the hot path

`sRGBToLinear` uses a cubic fit of the inverse sRGB transfer (`x(x(0.305x + 0.682) + 0.0125)`)
rather than `pow`. It runs once per visible fragment in the geometry pass. At 720p the
difference is about 2.8 million `pow()` calls per frame, and on Gen8 `pow` is a sequence of
instructions rather than a single one.

The exact piecewise curve is still used on the way out, in `final`, where it is one pixel
per screen pixel and the accuracy matters for how the image is displayed.

`pow()` also appears in the water glitter, where the exponent is a chain of multiplies
instead, and in `exp()` for fog and absorption, which cannot be avoided and are worth it.

---

## What is most likely to need tuning

Arithmetic cannot pick a colour. When the pack is first run, these are the numbers most
likely to be wrong and the direction to move them:

| Symptom | Setting | Direction |
|---|---|---|
| Scene too bright or washed out | `COLOR_EXPOSURE` | down |
| Shadows too dark, detail lost | `AMBIENT_STRENGTH` | up |
| Shadows too flat and grey | `AMBIENT_STRENGTH` | down |
| Sky too saturated or too pale | `ZENITH_DAY` in `lib/atmosphere.glsl` | desaturate / raise |
| Sunset band too strong or too weak | the `0.80` in `aetherisSkyGradient` | up / down |
| Water too dark | `WATER_EXTINCTION` in `lib/water_composite.glsl` | down |
| Water too clear, no depth | `WATER_CLARITY` | down |
| Reflections too strong at steep angles | the `0.02` F0 in `aetherisWaterSurface` | up |
| Water glitter too harsh | the `5.4` multiplier in the glitter term | down |
| Clouds too flat or too soft-edged | `CLOUD_COVERAGE` | down for more edge |
| Too many clouds | `CLOUD_COVERAGE` | down |
| Clouds too small and busy | `CLOUD_SCALE` | up |
| Foliage too bright | the `0.85` on the transmission rim | down |
| Wind too strong | the `0.055 + 0.085 * gust` in `aetherisWindOffset` | down |
| Fog too thick | `FOG_DENSITY` | down |

Frame rate first, then colour. A pack that looks right at 15 fps is not usable.
