# Development checkpoint

Aetheris Shaders. This file is the first thing to read when picking the project back up.
It records where things stand, what is proven, what is not, and what comes next, so that
work resumes from the exact point it stopped rather than from the beginning.

**Last updated:** at the 1.0.0 release commit.

---

## Current stage

**1.0.0 implemented, statically validated, awaiting its first run in Minecraft.**

Every pass is written and wired up. There is no placeholder, no stubbed function and no
`TODO` in the shader source. The pack packages into a correctly rooted zip.

The single biggest open item is that **nothing has been compiled by a GPU or looked at on
screen**. That is a limitation of where this was built, not an oversight, and it is stated
in the README rather than hidden.

---

## Completed

### Rendering pipeline

- [x] Pass topology: shadow -> gbuffers -> composite -> final. Four steps, two of them
      fullscreen. No bloom chain, no deferred geometry pass, no temporal anything.
- [x] Buffers: `colortex0` RGBA16F (forward lit scene), `colortex1` RGBA16F (composite
      output), `colortex2` RGBA8 (water surface normal and texture modulation).
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

---

## Latest successful validation

**Nothing has been run yet.** The pack was written in an environment with no shell, no
compiler and no Minecraft. The first validation run is the CI job on the initial push.

Update this section with the CI result, the run number and the date as soon as it is known.
Until then, treat the "Verified in CI" list in the README as *what the validator checks*,
not as *what has passed*.

If CI fails, the failure list is the to-do list. Do not mark anything above as verified
until CI is green.

---

## Known bugs and limitations

### Unverified by nature

1. **No GPU compilation has happened.** The most likely categories of failure, in
   descending order of probability:
   - A profile or option name that Iris parses differently than expected.
   - `mc_Entity` not being bound as declared, which would silently disable wind rather
     than crash.
   - `layout(location = N) out` combined with `DRAWBUFFERS` on the water program, which is
     the most intricate part of the interface usage in the pack.
   - `#version 330 compatibility` and the compatibility built-ins
     (`gl_ModelViewMatrix`, `gl_ModelViewProjectionMatrix`, `gl_TextureMatrix`,
     `gl_NormalMatrix`) on Mesa's Intel driver.
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
13. **Iris parses `block.properties` and binds `mc_Entity`.** If not, wind and the whole
    water path stop working silently, because water would then be treated as ordinary
    translucent geometry. This is the highest risk item in the pack.

---

## Next concrete tasks

In the order they should be done.

1. **Run CI and fix whatever it reports.** It is the only automated check there is.
2. **Load the pack in Minecraft 1.21.5 with Iris 1.8.x on the target machine.** Read
   `latest.log` for shader compile errors before worrying about anything else. Iris reports
   the failing stage and line.
3. **Confirm assumption 13 first.** If water is invisible or renders as flat translucent
   glass, `mc_Entity` or `block.properties` is the cause, not the water maths. Test by
   temporarily forcing the water branch on in `gbuffers_water.fsh`.
4. **Calibrate exposure.** Stand somewhere flat at noon, with `COLOR_EXPOSURE = 1.0`, and
   compare against the daylight target in `docs/PERFORMANCE.md`. Adjust `SUN_STRENGTH` and
   `AMBIENT_STRENGTH` before touching the palette.
5. **Calibrate the sunset.** The golden hour band strength (`0.80` in `aetherisSkyGradient`)
   and the anti solar cooling are the two most likely to be wrong.
6. **Measure.** Press F3, note frame time at 1280x720, and record it in the README. Then
   decide whether the Balanced preset should move.
7. **Tune the water** using the table at the end of `docs/PERFORMANCE.md`.
8. **Then** consider 1.1.0: bloom if the budget allows it after measurement, or a
   half-resolution cloud march into a separate buffer if the sky turns out to be the
   bottleneck.

---

## Interrupted operations

None. The 1.0.0 tree is complete and self-consistent as committed.

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
