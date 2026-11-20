# Current development checkpoint — 2026-11-20

## Active branch and scope

- Repository: Pawar-47/Aetheris-Shaders
- Work branch: perf/full-feature-performance
- Latest code-validation commit: 4395226889b8841fc89359a492eaa8f16b2ff183
- Latest README and performance documentation are updated in that same commit.
- Version file: 1.6.1
- Default branch: main; it has not been changed.
- The published v1.6.1 tag points to e2f7bb73c7848576895ae8041e8237e31970f1f3 on main. It predates this branch's feature-preserving pipeline.
- No new release has been published from this branch.

## Protected reference inputs

- The user-supplied `Shader.zip` was inspected read-only. SHA-256:
  `f49d9a9245bcdee742bba97c7d5001a3b4fcf43d501d672e3645b57637b9db4a`.
  The archive is not modified, committed or bundled into the shader release.
- The archive identifies MakeUp Ultra Fast v9.6. Its ZIP has no license file; the upstream
  [MakeUpUltraFast repository](https://github.com/javiergcim/MakeUpUltraFast) currently
  carries LGPL-3.0. No MakeUp source files are copied into Aetheris. Only high-level
  techniques are used as references, including bounded screen-space reflections, depth-
  gated light shafts, reduced sample budgets and low-resolution bloom. Any future source
  port requires a separate licence review and notices.
- The public
  [minecraft-shader-template](https://github.com/ascpixi/minecraft-shader-template) was
  consulted read-only at master commit
  `ab2b99c9e1715cb951936157fe3c2ef94890233b`. No files were changed there and no source
  files were copied into Aetheris. Its root had no LICENSE file at the inspected revision,
  so it remains a documentation/layout reference only.
- Only `Pawar-47/Aetheris-Shaders:perf/full-feature-performance` is modified. The Aetheris
  `main` branch, published v1.6.1 tag, uploaded ZIP and upstream template repository remain
  untouched.

- [x] The two low-resolution effect buffers use `R11F_G11F_B10F` (32-bit packed HDR)
  instead of `RGBA16F`: bloom/light-shaft energy is non-negative RGB and does not need alpha,
  halving intermediate-buffer storage and read/write traffic. CI guards these declarations.

## Completed in this continuation

- The Performance profile keeps dynamic shadows, AO, water reflections, volumetric clouds,
  FXAA, bloom, depth-gated volumetric light shafts and material gloss enabled.
- Shadow cost is reduced with one 1024 map, a 64-block radius, Iris shadow culling, a
  positive `shadowDistanceRenderMul`, a fixed four-tap kernel and contact-shadow reuse.
- AO reconstructs its surface normal from derivatives, avoiding four neighbouring depth reads.
- Bloom and light shafts share two quarter-resolution passes and one combined effect route.
- Both low-resolution effect buffers use `R11F_G11F_B10F` (32-bit packed HDR) rather than
  `RGBA16F` (64-bit); their non-negative RGB effect energy needs no alpha, halving their
  storage and read/write traffic. The validator guards the format declarations.
- Clouds reject empty/horizon regions early and avoid a second noise octave when the primary
  density cannot contribute.
- Material gloss is a forward-lighting lobe on tagged blocks; no PBR/resource pack is required.
- `tools/validate.py` checks the retained Performance features, culling, buffer scales,
  formats, program-enable expressions and composite1 → composite2 → final routing.
- The user-supplied archive and public template remain read-only; no source files are copied.
  See `docs/REFERENCE-PROVENANCE.md`.

## CI result

[GitHub Actions run 44800409615](https://github.com/Pawar-47/Aetheris-Shaders/actions/runs/44800409615)

- Tested commit: 4395226889b8841fc89359a492eaa8f16b2ff183
- Final conclusion: **completed / success**
- Static validation: passed.
- GLSL compile and program-link check: passed; all 46 stages compile and every program links.
- Block ID consistency: passed.
- Option-label check: passed.
- Compact effect-buffer format and quarter-resolution checks: passed.
- Packaging: passed; `Aetheris-Shaders-1.6.1.zip` generated.
- Artifact upload: passed; artifact ID 14660642752 (64,031 bytes). The nested installable ZIP
  contains 81 files and 4 directories (146,267 uncompressed bytes).

## Remaining verification boundary

The CI build is successful, but it is not a runtime test. Iris has not yet been confirmed
loading the pack on Minecraft 1.21.5 on the target Linux Mint machine. No live-world visual
review, FPS benchmark, frame-time capture, GPU temperature measurement or memory measurement
has been performed. Do not claim that the pack is runtime-tested or tuned to measured FPS.

## Next steps

1. Install the exact artifact from run 44800409615 in the target SK Launcher instance with
   Iris 1.8.x and Sodium. Enable Iris debug mode before applying it.
2. If it fails, diagnose the first concrete log or patched-shader error; do not guess from an
   empty on-screen details pane.
3. If it loads, capture screenshots and benchmark a repeatable scene at 1280x720 / 6 chunks.
   Compare Performance and Balanced without changing multiple variables at once.
4. Use those real measurements to tune the default settings.
5. Keep all work on this branch. Do not merge to main or publish a new release unless
   explicitly instructed.

---

## Historical checkpoint notes

The material below records earlier development history. Some next-task lists and validation
statements are superseded by the current checkpoint above; retain them as history rather than
treating them as the active plan.

# Development checkpoint

Aetheris Shaders. This file is the first thing to read when picking the project back up.
It records where things stand, what is proven, what is not, and what comes next, so that
work resumes from the exact point it stopped rather than from the beginning.

**Last updated:** at the 1.1.0 release commit.

---

**Current release:** 1.5.0 (`Aetheris-Shaders-1.5.0.zip`).
1.0.0 first release; 1.1.0 fixed a duplicate uniform that sent the pack back to vanilla
rendering; 1.2.0 completed the shadow pipeline; 1.3.0 fixed the option declarations; 1.4.0
stripped the configuration back to the shape of the Iris 1.21.5 template; 1.4.1 stops guessing
and adds a probe pack so the next report is a measurement rather than a symptom. The 1.0.1 tree
was never committed or published, so its fixes live in 1.1.0.

---

## Why 1.1.0 exists

The reported symptom was that the pack looked identical to vanilla. That is what Iris does
when a program fails to build: it drops the pack and renders the game as though none had
been selected. Re-reading the source against Iris' own shader documentation and its
transform source, rather than against OptiFine lore, found a real cause:

**`colortex0` was declared twice in the composite translation unit** — once in
`shaders/lib/body/composite.fsh` and once in `shaders/lib/water_composite.glsl`, which the
former includes. Two declarations of the same uniform are a redefinition, and Mesa rejects
the program for it. With the composite pass gone, so are the sky, the clouds, the water and
the grade: every part of the pack that is not vanilla-shaped.

Three more faults were found in the same pass and are fixed: a `block.properties` written
with backslash line continuations, a local shadowing the `near` uniform, and a water
detection path that depended entirely on one file being parsed as expected.

## Current stage

**1.5.2 implemented, compiled, still awaiting its first run in Minecraft.**

For the first time the pack has been through a compiler. `tools/glsl_check.py` compiles all
46 stages with `glslangValidator` in CI, after reproducing what Iris does to the source:
include resolution, `#version 330 compatibility` to core, the legacy built-ins renamed and
declared, and the `colortexNFormat` directives Iris consumes itself removed.

It immediately caught the error that was reported — `vec3 flat` in `lib/atmosphere.glsl`,
where `flat` is a reserved interpolation qualifier — and with that one identifier fixed, 46
of 46 stages compile. "Statically validated" meant something far weaker than that for the
first six releases, and that gap, not any single bug, is what made every previous diagnosis a
guess.


The failure now has a name: `java.lang.NumberFormatException: For input string: "2"`, which is
Iris parsing `/* RENDERTARGETS: 0, 2 */`. Each entry of that list goes through
`Integer.parseInt`, so the second arrives as `" 2"`. Iris' own documentation writes the
directive as `X,Y,Z`, without spaces, for that reason. Fixed in 1.5.1, and the validator now
rejects whitespace in a target list.


Four releases, three of them chasing a load failure, and the pattern is worth recording: every
time, the cause was found by reading Iris' own source rather than by reasoning about the pack,
and every fix removed a construct rather than adding one. 1.1.0 was a duplicate uniform, which
made Iris render vanilla. 1.3.0 was `const` option declarations, which Iris never registered.
1.4.0 removes the whole option-UI surface — `screen`, `sliders`, `profile.*`, `#if` — because
those are the only places Iris resolves an option name, and an unresolved name aborts the load
with an empty message. The configuration now matches the Iris 1.21.5 template, which loads with
no `shaders.properties` at all.

Every pass is written and wired up. There is no placeholder, no stubbed function and no
`TODO` in the shader source. The pack packages into a correctly rooted zip.

The single biggest open item is unchanged: **nothing has been compiled by a GPU or looked
at on screen.** What has changed is that the reason the pack could have been rendering
vanilla is identified and fixed, and the validator now has a check for that whole class of
error. That is not the same as knowing the pack works.

---

## Completed

### Rendering pipeline

- [x] Pass topology: shadow -> gbuffers -> composite -> final. Four steps, two of them
      fullscreen. No bloom chain, no deferred geometry pass, no temporal anything.
- [x] Buffers: `colortex0` RGBA16F (forward lit scene), `colortex1` RGBA16F (composite
      output), `colortex2` RGBA16F (water surface normal and texture modulation).
- [x] Buffer formats declared in `shaders/gbuffers_terrain.fsh`, `gbuffers_water.fsh`,
      `composite.fsh` and `final.fsh`.

### Water

- [x] `gbuffers_water` writes no colour; it writes a packed normal and mask to `colortex2`
      and leaves the opaque scene in `colortex0` intact. This is the load bearing decision
      the whole water design rests on.
- [x] Explicit blend state so alpha 0 means "contribute nothing" and alpha 1 means
      "overwrite", for both targets.
- [x] Five-component wave normals with constant steepness, plus a two-octave ripple, faded
      by distance.
- [x] Vertical faces (waterfalls) get a separate, low frequency wobble rather than a
      horizontal wave field smeared across a vertical plane.
- [x] Refraction by surface slope, rejected at shorelines.
- [x] Per channel absorption across the water column depth from `depthtex0` and `depthtex1`.
- [x] Screen space reflection with geometric step growth and a thickness test.
- [x] Reflection fallback to sky plus one cloud layer.
- [x] Schlick Fresnel at F0 0.02, two sun glitter lobes.
- [x] Vanilla water texture modulation carried through the data buffer.

### Sky, atmosphere, clouds

- [x] Rayleigh plus Mie transmittance driving sun, moon, sky band, cloud tint and fog.
- [x] Authored dome gradient, anti solar cooling, below horizon haze fade, vanilla fog
      colour folded in at 7% for the Nether and the End.
- [x] Sun disc with two Mie halo lobes, moon disc with procedural maria, two layer star
      field.
- [x] Cumulus slab march with front-to-back transmittance, height-rising threshold, fixed
      anisotropic shear, edge erosion above the base.
- [x] Horizon LOD cross-fade to a low frequency field with capped optical depth.
- [x] Analytic per-sample lighting with a normalised Mie forward lobe.
- [x] Cirrus veil on a separate higher plane.

### Vegetation

- [x] `block.properties` ID map, with graceful fallback to ID 0 if unreadable.
- [x] Leaf transmission with a fourth power backlit rim, tinted by foliage albedo.
- [x] Foliage ambient with a steeper up/down response than terrain.
- [x] Wind from a smooth travelling gust field in absolute world space.
- [x] Wind weight from the texture v coordinate, not world height.
- [x] Shadow pass calls the same wind function with the same absolute position.

### Lighting, fog, post

- [x] Forward lighting with wrapped diffuse, hemisphere ambient, blue night floor, block
      light partly occluded by vertex AO.
- [x] One shadow map, per-pixel rotated nine-tap spiral, split bias, edge and range fades.
- [x] Early out from the shadow lookup when it cannot change the result.
- [x] Height fog, distance haze from the sky's own horizon colour, Mie forward glow,
      render distance fade.
- [x] Underwater fog and underwater sky replacement.
- [x] Nether and the End handled through the vanilla fog colour.
- [x] Screen space ambient occlusion, faded out by 46 blocks.
- [x] HDR FXAA, ACES, white balance, saturation, contrast, vignette, 8 bit dither.

### Project

- [x] Three presets that differ in rendering cost.
- [x] Option labels in `shaders/lang/en_us.lang`.
- [x] `tools/validate.py`: includes, brace and preprocessor balance, function resolution,
      sampler validity, cross-stage varying agreement, `DRAWBUFFERS` counts, option
      consistency.
- [x] `tools/package.sh`: correctly rooted zip, deterministic.
- [x] `ci.yml`: validate, check block IDs against constants, check every option has a
      label, package, upload artifact.
- [x] `release.yml`: fires on `VERSION` change on main, validates, packages, publishes with
      the changelog entry as the release body.
- [x] README, CHANGELOG, LICENSE (MIT), THIRD-PARTY-NOTICES, `docs/PERFORMANCE.md`.

### 1.1.0 — Iris loading path

- [x] Duplicate `colortex0` declaration removed from the composite body. This is the one
      that would have sent Iris back to vanilla rendering.
- [x] `block.properties` rewritten with one block list per line, no continuations.
- [x] `near` local in the shadow contact term renamed; it shadowed an Iris uniform.
- [x] Water recognised by block ID, by Iris' legacy IDs 8 and 9, and by the render type in
      `mc_Entity.y`. The render type also keeps lava out of the water branch when the ID
      map has not resolved.
- [x] `colortex2` promoted from `RGBA8` to `RGBA16F`: the packed wave normal was losing
      about 40% of the finest octave to 8 bit quantisation.
- [x] `separateAo = true`, so vanilla's smooth lighting occlusion reaches the lighting model
      in the vertex alpha where the code always assumed it was. The translucent pass now
      takes its blend alpha from the texture so this cannot thin glass at its edges.
- [x] Cloud coverage mapping recalibrated; the previous base threshold left only about a
      fifth of the sky carrying cloud. The reflection's cheap cloud sample matches it.
- [x] `tools/validate.py` rejects a second global declaration of the same name.
- [x] The loading behaviour was checked against Iris' shader documentation and transform
      source, not against OptiFine. What that established: `#version 330 compatibility` is
      the correct declaration for a legacy vertex stage and Iris rewrites it to core with
      the built-ins patched; `mc_Entity` is a `vec2` and Iris patches the integer attribute
      itself; `shadow.enabled`, `separateAo`, `clouds`, `sun`, `moon`, `stars`, `vignette`
      and `underwaterOverlay` are all real directives; and Iris removes unused functions
      and patches varying mismatches, so neither is fatal.

### 1.2.0 — completeness pass

- [x] **The shadow pass now applies the cutout.** It carried no texture coordinate and wrote
      depth unconditionally, so every leaf block and every flower cast the shadow of a solid
      cube. This was the largest visual defect left in the pack and it was invisible from
      inside the shading code, because the visible pass was cutting out correctly.
- [x] The shadow pass is depth only: no colour output, no `DRAWBUFFERS`, no `shadowcolour0`.
      Saves a 2048x2048 RGBA8 write per frame, about 16.7 MB.
- [x] Contact shadows wired in. `sampleShadowContact` existed but was never called, so the
      brief's "contact shadows where affordable" was unimplemented. It now multiplies the
      ambient term inside twenty blocks, folded out before that bound.
- [x] Lava and glowstone take the emissive material in the translucent pass instead of the
      default path.
- [x] Ambient occlusion reads `depthtex0` for its normal taps, matching the surface it is
      shading. Behind glass it was occluding the wall behind the pane.
- [x] `UNDERWATER_TINT` promoted from a dangling label to a real option, scaling both the
      colour and the density of the underwater medium.
- [x] Validator gained the two Iris rules that are not GLSL rules: the compatibility profile
      must be declared wherever the legacy built-ins are used, and `mc_Entity` must be a
      `vec2`.
- [x] The composite and final vertex path was traced through Iris' `CompositeTransformer`:
      `gl_Vertex`, `gl_MultiTexCoord0`, `gl_TextureMatrix[0..7]` and
      `gl_ModelViewProjectionMatrix` are all replaced on the compatibility path, so the
      fullscreen quad is correct as written.

### 1.3.0 — the apply failure

- [x] **Root cause: every slider was a `const` option, which Iris does not accept.**
      `OptionAnnotatedSource.parseConst` registers a const option only if its name is in
      `VALID_CONST_OPTION_NAMES`; anything else gets a diagnostic that never reaches the
      user. Twenty options here were `const float`, so Iris had a menu referencing twenty
      options it had never registered, and building that menu is what threw while applying.
- [x] Every user option is a `#define` with its allowed values in a trailing comment.
- [x] `SUN_STRENGTH`'s default was not one of its own allowed values; the `0.8` and `1.25`
      softness values the presets set were missing from `SHADOW_SOFTNESS`'s list.
- [x] The shadow pass declares a colour output again; the 16.7 MB per frame it saves is not
      worth the load risk.
- [x] `docs/TROUBLESHOOTING.md`, including the parsing rules that are invisible in the GLSL.
- [x] Four more validator rules: const option names must be whitelisted, every fragment stage
      must declare an output, `#if` in shaders.properties must name a real option, and a
      preset value must be one of that option's allowed values.

### 1.4.0 — back to the template

- [x] `shaders.properties` reduced to six vanilla-feature switches. Every option-UI directive
      removed: `screen`, `screen.*`, `sliders`, `profile.*` and the `#if` block are the only
      constructs that make Iris resolve an option name, and that resolution is what threw.
      `blend.*`, `shadow.enabled`, `separateAo` and `oldLighting` went with them as
      refinements that are not worth a failed load.
- [x] Every program uses `/* RENDERTARGETS: ... */` instead of `/* DRAWBUFFERS: ... */`,
      matching the Iris 1.21.5 template.
- [x] Presets and the in-game settings screen removed for now; the README documents the four
      lines to change for the other two cost profiles.
- [x] The validator accepts both target-list spellings.
- [ ] Restore, one at a time and only after the pack is confirmed to load: `separateAo`,
      `oldLighting`, the feature blend overrides, then `screen`/`sliders`/`profile.*` for the
      presets. Each restored piece is a candidate for the failure, so each gets its own
      verification.

### 1.5.0 — compared against Nova Shaders

Nova Shaders loads on the target machine and Aetheris does not, so the pack was compared to
it file by file. That settled three things:

- [x] **One colour buffer, not two.** Nova's `composite` declares `RENDERTARGETS: 0`, reads
      `colortex0` and writes `colortex0`; the loader flips between physical textures, so it is
      a ping-pong. Aetheris now does the same and `final` reads `colortex0`. `colortex1` is
      gone, and with it the possibility of the last pass reading an unwritten attachment.
- [x] **Buffer formats declared once, as real code**, in `lib/body/composite.fsh`, instead of
      in a block comment repeated across four programs.
- [x] **The archive carries `pack.mcmeta`, `LICENSE` and the notices**, and `package.sh`
      fails if any is missing. That is Nova's layout, asserted by its own build script.
- [x] **The presets and settings screen are back.** 1.4.0 removed them on the theory that the
      option menu caused the failure; Nova ships the same `screen`/`sliders`/`profile.*`/`#if`
      directives and loads, so that theory was wrong.
- [x] `shaders.properties` no longer relies on `separateAo`, `oldLighting` or `blend.*`.

### 1.4.1 — making the failure measurable

- [x] A probe pack ships with every release: two files, one program, no `shaders.properties`,
      no `#include`, no block map, no language file — the Iris 1.21.5 template's
      `gbuffers_terrain` and nothing else. It renders unlit, so a successful load cannot be
      mistaken for "no change".
- [x] `tools/package.sh` emits `Aetheris-Probe-<version>.zip` next to the real pack, and the
      release workflow attaches both.
- [x] `docs/TROUBLESHOOTING.md` opens with the probe test and what each of the three outcomes
      means.
- [ ] **Waiting on one data point:** does the probe load? If yes, the fault is in this pack and
      `latest.log` will name the class and line. If no, the fault is the install and no further
      change to these shaders can fix it.
- [ ] Four hypotheses have been tried and disproven in sequence: the duplicate uniform (1.1.0,
      real defect, not the blocker), the `const` option declarations (1.3.0, real defect, not
      the blocker), the option-UI directives in `shaders.properties` (1.4.0), and
      `DRAWBUFFERS` vs `RENDERTARGETS` (1.4.0). The lesson is that reading the source has
      produced real fixes but cannot substitute for one log line.

---

## Latest successful validation

**CI green on `main` for 1.2.0.** The `Validate` workflow runs the static validation, the
block ID agreement check, the option label check, packaging and artifact upload, and the
`Release` workflow published `Aetheris-Shaders-1.2.0.zip` from the same commit. The 1.3.0 tree
had not been through it at the time this was written: the push that carries this file is what
runs it.

Worth stating plainly: two green CI runs shipped two packs that could not run. Every check in
`tools/validate.py` modelled *this pack's intent*, not Iris' parser. The four rules added in
1.3.0 are the first that model Iris' behaviour instead, which is why the const-option
whitelist is now enforced rather than assumed.

The validator earned its place during 1.0.0. It found:

1. Its own include-expansion bug: it inlined each guarded file once per sibling, which
   made `shadowMapResolution` look like it was declared nine times over.
2. A real compile error — `water_composite.glsl` called `aetherisUnpackWaterNormal`
   without including `water.glsl`. The composite pass would not have built, and the whole
   pack would have silently fallen back to vanilla rendering.
3. A real interface gap — `composite.vsh` and `final.vsh` were the only stages in the pack
   carrying no option constants, because `uniforms.glsl` did not include `settings.glsl`.

It did **not** find the duplicate `colortex0` that 1.1.0 removes. That was found by reading
the assembled composite translation unit against Iris' documentation. It is now the tenth
check in `tools/validate.py`, so the next one is caught automatically.

**What is still not verified is everything below "Unverified by nature": no GPU has
compiled this and no frame has been rendered.**

---

## Known bugs and limitations

### Unverified by nature

1. **No GPU compilation has happened.** With the duplicate declaration gone, the most
   likely remaining categories of failure, in descending order of probability:
   - A profile or option name that Iris parses differently than its documentation says.
   - `layout(location = N) out` combined with `DRAWBUFFERS` on the water program, which is
     the most intricate part of the interface usage in the pack.
   - RGBA16F blending on this driver. Float blending has been core on desktop GL since 3.0
     and Broadwell supports it, but if the water buffer comes out empty or black, the first
     thing to try is putting `colortex2` back to `RGBA8`.
   - `separateAo = true` behaving differently than expected. That changes how much ambient
     occlusion the image carries; it does not break anything.
2. **No frame rate has been measured.** The budget in `docs/PERFORMANCE.md` is arithmetic.
   It may be optimistic by a factor of two either way.
3. **No visual output has been seen.** Colours were chosen by design against the ACES
   curve. Expect exposure and saturation to need adjustment.

### Deliberate gaps

4. **No bloom.** Rejected on cost, not forgotten. See `docs/PERFORMANCE.md`.
5. **No volumetric light shafts.** The Mie forward scattering is the substitute.
6. **No temporal reprojection**, so no TAA and no temporal cloud accumulation. Every pass
   is stateless.
7. **Water geometry is not displaced**, and this is intentional.
8. **Reflection fallback has one cloud layer, not the full march.**
9. **Bloom aside**, eye adaptation and motion blur are absent by design.

### Assumptions that may not hold

10. **`sunPosition` is in view space.** The whole sky rotates if this is wrong, since it is
    the one place the conversion happens. It was taken from a pack known to work on this
    machine, but it has not been confirmed independently.
11. **`gl_Color.a` carries vanilla's smooth lighting AO.** If Iris supplies 1.0 instead, the
    pack loses vertex AO and looks flatter, but does not break. The compression to
    `0.45 + 0.55 * a` was chosen so a missing AO channel degrades to "fully lit".
12. **Water writes depth**, so `depthtex0` is the water surface and `depthtex1` the floor.
    If it does not, the water column depth falls back to a view distance term and deep water
    will not darken as much as it should.
13. **`block.properties` is parsed and `mc_Entity` is bound.** This used to be the highest
    risk item in the pack. It is now the most defended: water is recognised three ways, and
    if all three fail it falls through to plain translucent shading rather than breaking.
    Wind and leaf lighting still depend on the ID map alone.

---

## Next concrete tasks

In the order they should be done.

1. **Load the pack in Minecraft 1.21.5 with Iris 1.8.x.** Press Ctrl+D on the shader
   selection screen first: that writes the patched source to `patched_shaders/`, which is
   the only readable record of what Iris actually compiled. If it fails, follow
   `docs/TROUBLESHOOTING.md` and send the log lines rather than the on-screen message.
2. **Read the failure mode, not just the failure.** If the game looks exactly vanilla, the
   pack did not load: look for a compile error. If the screen is black or white, the pack
   loaded and a buffer link is wrong — `DRAWBUFFERS:1` on `composite.fsh`, and `final.fsh`
   reading `colortex1`, are the two lines to check. White specifically means `final` read
   `colortex1` before anything wrote it, because Iris clears that buffer to 1.0.
3. **Confirm water is recognised.** If water renders as flat translucent glass, all three
   signals in `aetherisIsWater` failed. Write `blockId` and `renderType` into the red and
   green channels of `final` for one run to see which.
4. **Calibrate exposure.** Stand somewhere flat at noon, with `COLOR_EXPOSURE = 1.0`, and
   compare against the daylight target in `docs/PERFORMANCE.md`. Adjust `SUN_STRENGTH` and
   `AMBIENT_STRENGTH` before touching the palette.
5. **Calibrate the sunset.** The golden hour band strength (`0.80` in `aetherisSkyGradient`)
   and the anti solar cooling are the two most likely to be wrong.
6. **Calibrate the cloud deck.** The base threshold in `aetherisCloudDensity` was moved from
   0.645 to 0.565 by reasoning about the noise distribution, not by looking at it. If the
   deck is now too heavy, `CLOUD_COVERAGE` is the slider; if it is too thin at the default,
   the threshold needs another 0.02 rather than the slider.
7. **Check the shadow cutout and the contact term.** Leaf shadows should now have the shape
   of the leaves rather than of the block. If the contact darkening reads as dirt rather
   than as contact, the `0.45` in `sampleShadowContact` is the number to lower; the twenty
   block bound in `aetherisShadeSurface` is the other.
8. **Measure.** Press F3, note frame time at 1280x720, and record it in the README. Then
   decide whether the Balanced preset should move.
9. **Tune the water** using the table at the end of `docs/PERFORMANCE.md`.
10. **Then** restore what 1.4.0 removed, one piece at a time, checking that the pack still
    loads after each: `separateAo`, then `oldLighting` and the blend overrides, then
    `screen`/`sliders`/`profile.*` for the presets. The last is the one that failed, so it
    goes last and only against an option set that is known to resolve.
11. After that, consider 1.5.0: bloom if the budget allows it after measurement, or a
    half-resolution cloud march into a separate buffer if the sky turns out to be the
    bottleneck.

---

## Interrupted operations

None in the 1.1.0 tree. The 1.0.1 tree was written but never committed and never released;
its two fixes are in 1.1.0, and its changelog entry was folded into the 1.1.0 entry rather
than left pointing at a release that does not exist.

---

## How to resume

```bash
git log --oneline -5          # see where things stopped
python3 tools/validate.py     # reproduce the automated check
./tools/package.sh            # build the installable zip
```

Then read the "Next concrete tasks" section above and start at the first item that is not
done. Do not restart the project and do not replace working implementations without a
technical reason; the water data-buffer design in particular is load bearing and everything
downstream assumes it.
