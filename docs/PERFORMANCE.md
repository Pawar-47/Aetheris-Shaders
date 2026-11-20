# Performance design: preserve effects, reduce their cost

## Target and evidence

The target is one laptop: Intel Core i3-5005U (2 cores / 4 threads, 2.00 GHz), Intel HD
Graphics 5500 (Broadwell Gen8), 8 GB RAM, Linux Mint, Minecraft Java 1.21.5, Iris 1.8.x
and Sodium.

Intel's 5th-generation graphics developer guide lists three texture samplers and a
24-EU HD 5500 design (23 active EUs on some Core i3 SKUs). The GPU shares system memory
with the CPU. The often-quoted 25.6 GB/s is a theoretical dual-channel peak, not a measured
bandwidth figure for this laptop; the actual 8 GB channel configuration is not yet known.
Both memory traffic and texture sampling matter. The CPU has only two physical cores, so
chunk building and draw submission compete with the game and driver.

This document describes the algorithms and configured budgets. It does **not** claim a
measured frame rate or a guaranteed millisecond budget. No benchmark from the target laptop
has been recorded yet.

## Design rule

The Performance profile must retain the visual feature set. It may reduce resolution,
distance, sample count, strength and iteration count, but it must not achieve its speed by
turning off:

- dynamic shadows and near-field contact darkening;
- screen-space ambient occlusion;
- water refraction, absorption and reflections;
- procedural clouds, cloud detail and cirrus;
- FXAA;
- bloom;
- screen-space light shafts;
- material gloss;
- vegetation wind and water waves.

The validator checks that the Performance profile leaves these effects enabled.

## Rendering pipeline

1. **Shadow pass:** one shadow depth map. The low-end profile uses 1024 resolution and a
   64-block shadow distance. It uses four depth taps per shadowed fragment. Shadow culling
   remains enabled; no second cascade is rendered.
2. **Geometry / gbuffers:** forward lighting is evaluated where the surface albedo is
   already available. This avoids writing and rereading full-resolution albedo and normal
   G-buffers. The material gloss path uses a bounded analytic highlight for selected blocks.
3. **Composite:** sky and clouds are drawn for sky pixels; water is shaded only where its
   mask is set; AO is applied only to scene pixels and fades out with distance.
4. **Composite1 and composite2:** bloom and light shafts share two intermediate buffers at
   25% of screen width and height. That is 6.25% of the full-resolution pixel count. The
   first pass extracts bright regions and samples the projected sun ray; the second applies
   a five-tap blur.
5. **Final:** FXAA is applied to the scene, the low-resolution effects buffer is sampled,
   then exposure, tone mapping, colour grading and display encoding are performed.

The extra post-processing stages are deliberately low resolution. They are not full-screen
multi-pass blur chains, and they do not require a companion resource pack.

## Per-effect budgets in Performance

| Effect | Performance setting | Cost-control method |
|---|---:|---|
| Shadows | 1024 map, 64 blocks, 4 taps | One map, short range, compact kernel, shadow culling |
| Contact darkening | Reuses the same 4 shadow reads | No separate contact-shadow sampling loop |
| SSAO | 4 samples | Reconstruct normal with screen-space derivatives instead of four neighbouring depth reads; fade beyond 46 blocks |
| Water reflections | 5 march steps | Bounded geometric step growth; water pixels only; sky fallback on a miss |
| Water refraction / absorption | Enabled | Existing water data buffer and bounded per-pixel work |
| Cumulus clouds | 5 march steps | Fixed loop bound, early termination on low transmittance, horizon LOD |
| Cloud detail and cirrus | Enabled | Reduced-cost detail evaluation and early horizon rejection |
| Vegetation wind | Enabled | Shared deterministic wind function for visible and shadow passes |
| Water waves | Enabled | Analytic wave normals; no vertex displacement |
| FXAA | Enabled | Single final pass, no temporal history buffer |
| Bloom | Enabled | Bright extraction and blur in quarter-width/quarter-height buffers |
| Light shafts | 4 radial samples | Screen-space sky visibility checks in the same low-resolution pass |
| Material gloss | Enabled, strength 0.25 | Multiply-based Blinn-Phong highlight, restricted to mapped block IDs |

The values are compile-time shader options exposed through Iris' settings screen. They are
not adaptive FPS controls: a shaderpack cannot be assumed to have reliable access to a
frame-time feedback controller. Choose a profile or adjust its exposed values manually.

## Details and limitations

### Shadows

A single map avoids the geometry submission cost of cascades. The Performance profile uses
a 1024 map and 64-block distance with four taps. Iris' `shadow.culling=true` and
`shadowDistanceRenderMul=1.0` make the configured radius participate in actual shadow-pass
geometry culling, rather than only shrinking the projection matrix. The four low-cost taps
use a symmetric 2x2 kernel; higher profiles use more samples and per-pixel rotation. The
same depth reads also estimate the near-field contact term, avoiding a second four-tap loop.

This is still a real shadow pass. It is not replaced with fake vertex shading or disabled
to obtain the Performance preset.

### Ambient occlusion

AO remains enabled with four samples. The view-space centre position is reconstructed once,
and its derivatives supply a normal estimate. This removes four neighbouring depth-buffer
reads compared with the earlier finite-difference implementation. A footprint guard rejects
unstable normals at hard silhouettes, and the effect fades out before distant fog dominates.

### Water

Refraction, channel-dependent absorption, in-scattering, Fresnel and reflections remain.
The Performance profile bounds the screen-space reflection march to five steps. A ray that
misses or leaves the screen falls back to the analytic sky reflection, including a cheap
single-sample cloud approximation. This keeps the water reflective without running a full
cloud march for every reflected ray.

### Clouds

The cloud slab still uses front-to-back transmittance accumulation. Five fixed steps are
used in Performance; detail erosion and the high cirrus veil remain enabled. The horizon
cross-fades to a broad low-frequency field so a coarse march does not turn distant clouds
into crawling dots. The loop is statically bounded; no unbounded while loop is used.

### Bloom and light shafts

Both effects share two buffers configured to 0.25 x 0.25 of the display dimensions. At
1280x720, each is 320x180 pixels, not 1280x720. Bloom extracts values above a configurable
brightness threshold and the second pass softens them with five texture taps.

The light-shaft effect projects the sun into screen space and takes four samples along the
ray from each low-resolution output pixel. Samples contribute only when the depth buffer
indicates visible sky and the sampled scene colour is bright enough. This is a deliberately
cheap **screen-space approximation** of volumetric light shafts. It is not a physical 3D
volume integration, and it does not model light scattering through every world-space voxel.

### Material gloss

A curated material ID maps selected metal and polished blocks to a simple Blinn-Phong
highlight. The exponent is evaluated with multiplies rather than a per-fragment pow.
This adds a controlled specular cue without PBR texture maps, extra resource packs or
additional geometry passes. It is not physically based metal rendering.

### Anti-aliasing

FXAA remains enabled in Performance. Temporal AA is not implemented: it would require
history buffers, reprojection and rejection logic, and can ghost moving foliage and water.
The shader instead uses FXAA in the final pass and spatial dithering where appropriate.

## Profiles

| Profile | Shadow map / distance / taps | AO | Reflection steps | Cloud steps | Shafts |
|---|---|---:|---:|---:|---:|
| Recommended for HD 5500 / Performance | 1024 / 64 / 4 | 4 | 5 | 5 | 4 |
| Balanced | 2048 / 80 / 6 | 6 | 6 | 8 | 6 |
| Visual | 2048 / 128 / 9 | 9 | 10 | 12 | 8 |

All three profiles keep the effects listed above enabled. They differ in cost and strength,
not in whether the features exist.

## Benchmark protocol still required

A useful target-machine comparison must use the same Minecraft version, Iris and Sodium
versions, world, camera position, render distance, resolution, weather and time of day.
Record at least:

- average FPS and 1% low, or frame time in milliseconds;
- resolution and render distance;
- profile and any changed shader options;
- GPU/CPU utilisation and temperature if available;
- whether the scene contains water, dense foliage, shadows and visible clouds.

Test the Performance profile first at 1280x720 and 6 chunks, then compare Balanced. Do not
change several settings between measurements. The numbers in this file are algorithmic
budgets, not benchmark results.
