#ifndef AETHERIS_CLOUDS_GLSL
#define AETHERIS_CLOUDS_GLSL

#include "/lib/atmosphere.glsl"

/* Clouds.
 *
 * Not boxes, and not a painted dome. A slab, walked front to back, accumulating
 * transmittance. That is what gives a deck depth: back puffs are genuinely hidden
 * behind front ones and a continuous tonal ramp runs across a single puff instead
 * of one flat tone.
 *
 * The density field is where the organic shape comes from:
 *
 *   1. A fixed anisotropic shear of the domain. Storm-topped blobs are round,
 *      evenly spaced and cartoon-like; stretched ellipses at an angle to each
 *      other read as weather.
 *   2. A threshold that rises with height inside the slab. Near the base almost
 *      half of the field is dense, so bottoms are flat and continuous; by the top
 *      only the tallest peaks survive, so crowns break into separate rounded
 *      puffs. The union of those silhouettes is what the eye reads as fluffy.
 *   3. Edge erosion from a higher frequency octave, scaled in only above the
 *      base, so the base stays solid and the crowns stay ragged.
 *
 * The transform is fixed, never animated. Domain warping the field every frame
 * makes clouds shear and swim, which is the single most common way procedural
 * clouds look cheap.
 *
 * Lighting is analytic per sample: dark base, bright crown, thick cores greyed
 * out, plus a forward scattering lift from the Mie lobe. No shadow lookups and no
 * per-sample light march, which is what keeps this affordable on 24 execution
 * units.
 */

/* Where the deck sits. Kept local: the altitude is an option, the thickness is a
 * property of the look and not something worth exposing. */
const float CLOUD_THICKNESS = 74.0;

/* Field frequency in the horizontal plane, per block, before CLOUD_SCALE. One feature
 * every ~300 blocks gives fewer, larger masses: the deck reads as a handful of defined
 * shapes rather than as a scattering of small puffs, which is the point of a stylised
 * sky. */
const float CLOUD_FIELD_SCALE = 1.0 / 300.0;

/* Absorption per block of density. Chosen so a solid core about seventy blocks
 * deep goes opaque in three or four steps. */
const float CLOUD_ABSORPTION = 0.043;

/* Density at one point in the slab.
 *
 * g is height inside the slab, 0 at the base and 1 at the top. horizonMass is a
 * low frequency sample used to stabilise the deck where one march step spans
 * hundreds of blocks. shade returns how far round a puff this sample sits from the
 * light, 0 lit and 1 in shade, derived from the noise gradient that was already
 * computed. */
float aetherisCloudDensity(vec2 worldXZ, float g, vec2 wind, vec2 lightXZ,
                           float horizonMass, float horizonBlend, out float shade) {
    // Stretch and skew the domain so masses are broad and irregular rather than
    // round, evenly spaced puffs.
    vec2 p = worldXZ * CLOUD_FIELD_SCALE * CLOUD_SCALE + wind;
    vec2 q = vec2(p.x + p.y * 0.22, p.y * 0.82 - p.x * 0.15);

    vec3 field = valueNoiseGradient(q);
    float mass = mix(field.x, horizonMass, horizonBlend);

    // The gradient of the field points towards thicker cloud. Where it points at
    // the light this sample is on the far side of a puff and belongs in shade;
    // where the field thins towards the light it is a lit face. The gradient was
    // free: valueNoiseGradient hashed the same four corners valueNoise would.
    shade = saturate(dot(field.yz, lightXZ) * 3.6);

    // Erode the crowns only, and lightly. This one constant decides whether the deck reads
    // as weather or as shape: heavy erosion gives realistic wispy edges and, at this
    // resolution, mush. A sixth of it, confined to the top third, leaves the silhouettes
    // clean and lets the flat base and the rounded crown do the work.
#if CLOUD_DETAIL == 1
    float erosion = valueNoise(q * 4.7 + vec2(31.7, 17.3)) - 0.5;
    mass += erosion * 0.06 * smoothstep(0.55, 1.0, g);
#endif

    // Coverage, not a soft threshold. This is the single change that turns the deck from
    // drizzle into drawn cloud: subtract a coverage constant from the field, clamp at zero,
    // and the silhouette gains an edge instead of fading out over a long ramp. The constant
    // grows with height inside the slab, so the base stays continuous and the crowns break
    // into separate puffs. MakeUp shapes its clouds the same way.
    // A value-noise field sits around 0.5, so this is where the coverage constant has to
    // live: 0.505 at the default keeps about half the base sheet and leaves the crowns to
    // the height term below. Making it too small turns the sky into one solid overcast, which
    // is the failure mode to watch for when tuning this.
    float coverage = mix(0.64, 0.34, saturate(CLOUD_COVERAGE));
    coverage += smoothstep(0.05, 0.85, g) * mix(0.30, 0.16, CLOUD_SOFTNESS);

    float noise = (mass - coverage) * mix(7.0, 3.0, CLOUD_SOFTNESS);
    noise = max(noise, 0.0);

    // A flat, full base. The shelf reaches most of full density within the first tenth of
    // the slab, so bottoms are straight lines rather than gradients: flat bottoms and domed
    // tops are what the eye reads as a cloud rather than as a smudge.
    noise *= mix(0.70, 1.0, smoothstep(0.0, 0.10, g));

    // Defined cores. x / sqrt(x^2 + k) saturates quickly, so a puff gets a body and a crisp
    // border instead of a long soft ramp, and k is the only thing bounding how hard that
    // border is.
    float knee = mix(0.10, 0.60, CLOUD_SOFTNESS);
    return noise * inversesqrt(noise * noise + knee);
}

/* Draw the cumulus deck over an existing sky colour. */
vec3 aetherisRenderClouds(vec3 dir, AetherisSky sky, vec3 skyColour) {
#if CLOUDS == 0
    return skyColour;
#else
    float dirY = dir.y;

    // A ray parallel to the slab would divide by zero and reveals nothing anyway.
    if (abs(dirY) < 1.5e-3) return skyColour;

    float baseY = CLOUD_ALTITUDE;
    float topY = baseY + CLOUD_THICKNESS;
    float camY = cameraPosition.y;

    // Where the ray enters and leaves the slab. Taking min and max rather than
    // assuming an order covers all three cases: eye below the deck, inside it, and
    // above it looking down. Clamping a negative entry to zero instead hung a ghost
    // of the deck above itself, which is a bug worth not reintroducing.
    float tBottom = (baseY - camY) / dirY;
    float tTop = (topY - camY) / dirY;
    float tNear = min(tBottom, tTop);
    float tFar = max(tBottom, tTop);

    // Past this a puff is smaller than a pixel and the skyline only smears.
    const float farLimit = 9000.0;
    if (tFar <= 0.0 || tNear > farLimit) return skyColour;

    tNear = max(tNear, 0.0);
    tFar = min(tFar, farLimit);
    if (tFar <= tNear) return skyColour;

    vec2 wind = vec2(frameTimeCounter * 0.0200, frameTimeCounter * 0.0081) * CLOUD_SPEED;
    float stepLength = (tFar - tNear) / float(CLOUD_STEPS);

    // Horizontal direction to the light. The field's own slope along it decides
    // which side of a puff a sample is on, which separates a lit crown from a shaded
    // flank without a light ray for every sample.
    vec2 lightXZ = normalize(vec2(sky.lightDir.x, sky.lightDir.z) + vec2(1.0e-4, 0.0));

    // Near the horizon one step covers hundreds of blocks, so high frequency detail
    // would alias into dots. Cross-fade to a broad low frequency field there.
    float horizonLod = smoothstep(26.0, 170.0, stepLength);
    float horizonBlend = horizonLod * 0.82;

    // The stabilising low frequency sample is taken once, midway, rather than at
    // every step.
    vec2 midXZ = cameraPosition.xz + dir.xz * (tNear + tFar) * 0.5;
    vec2 midQ = vec2(midXZ.x + midXZ.y * 0.22, midXZ.y * 0.82 - midXZ.x * 0.15);
    float horizonMass = valueNoise(midQ * CLOUD_FIELD_SCALE * CLOUD_SCALE + wind);

    // Ordered dither hides march banding in the body without the crawl of a random
    // jitter, and is switched off at the horizon where the LOD already smooths.
    float jitter = aetherisDither(gl_FragCoord.xy) * (1.0 - horizonLod);
    float t = tNear + stepLength * (jitter + 0.5);

    // The Mie lobe is evaluated once, and only if this ray actually meets any
    // density. Most empty sky rays then skip it entirely.
    float scattering = 0.0;
    bool scatteringReady = false;

    float transmittance = 1.0;
    float absorbed = 0.0;
    float lit = 0.0;

    for (int i = 0; i < CLOUD_STEPS; i++) {
        float sampleY = camY + dirY * t;
        float g = saturate((sampleY - baseY) / CLOUD_THICKNESS);

        vec2 p = cameraPosition.xz + dir.xz * t;
        float shade;
        float density = aetherisCloudDensity(p, g, wind, lightXZ, horizonMass, horizonBlend, shade);

        if (density > 0.004) {
            if (!scatteringReady) {
                scattering = miePhaseNormalised(dot(-dir, sky.lightDir), 0.72);
                scatteringReady = true;
            }

            // Dark base, bright crown, thick cores grey. sqrt is the cheap stand in
            // for pow(g, 1.5).
            float heightLight = 0.10 + 0.90 * (g * sqrt(g));
            heightLight *= 1.0 - density * 0.40;
            heightLight *= 1.0 - shade * 0.78;
            heightLight = mix(heightLight, 1.0, scattering * 0.70);

            // Near the horizon the march is too sparse to integrate honestly, so cap
            // the per-step optical depth and let the deck fade into the haze instead
            // of building a solid wall along the skyline.
            float opticalDepth = density * stepLength * CLOUD_ABSORPTION;
            opticalDepth = min(opticalDepth, mix(6.0, 0.55, horizonLod));

            float absorb = 1.0 - exp(-opticalDepth);
            lit += heightLight * absorb * transmittance;
            absorbed += absorb * transmittance;
            transmittance *= 1.0 - absorb;

            if (transmittance < 0.03) break;
        }

        t += stepLength;
    }

    float alpha = 1.0 - transmittance;
    if (alpha < 0.004) return skyColour;

    // The two tones a cloud can be. Both are built from the same ambient and sun as
    // the terrain, so a sunset that turns the ground orange turns the clouds orange
    // by the same amount rather than by a hand matched value.
    vec3 shadeTone = sky.ambientSky * 1.20 + vec3(0.010, 0.013, 0.021) * sky.night;
    vec3 litTone = sky.ambientSky * 5.60 + sky.sunRadiance * 0.85;

    // A stylised deck is graphic rather than photographic: the two tones sit further apart
    // than a real cumulus, and the terminator between them is narrowed so a mass reads as a
    // lit crown over a shaded body instead of as a smoothly shaded sphere.
    float shape = saturate(lit / max(absorbed, 1.0e-4));
    shape = smoothstep(0.18, 0.82, shape);

    vec3 cloudColour = mix(shadeTone, litTone, shape);

    // Rain flattens the deck into an overcast sheet.
    cloudColour = mix(cloudColour, vec3(luma(cloudColour)) * vec3(0.80, 0.84, 0.90), sky.rain * 0.70);

    // Soften the skirt. A smoothstep keeps the core at full opacity and still takes the
    // edge to nothing, which reads as a cleaner silhouette than a straight power curve.
    alpha = alpha * alpha * (3.0 - 2.0 * alpha);

    // Grazing rays skim the slab rather than entering it. Fade them out instead of
    // letting the deck smear along the skyline.
    alpha *= smoothstep(0.006, 0.055, abs(dirY));

    return mix(skyColour, cloudColour, saturate(alpha));
#endif
}

/* A thin cirrus veil, above the cumulus.
 *
 * Drawn after the cumulus because it sits higher, so it overlays. Two stretched
 * noise samples and no march: at this altitude a curtain of ice crystals really is
 * close to a 2D transparency layer, and the cheapness is what makes it worth
 * having at all.
 */
vec3 aetherisRenderCirrus(vec3 dir, AetherisSky sky, vec3 skyColour) {
#if CLOUDS == 0 || CLOUD_CIRRUS == 0
    return skyColour;
#else
    float dirY = dir.y;
    if (dirY < 0.015) return skyColour;

    // Project onto a much higher, flatter plane than the cumulus deck.
    float horizonFade = smoothstep(0.015, 0.22, dirY);
    if (horizonFade < 0.001) return skyColour;
    float planeDistance = (1700.0 - cameraPosition.y) / dirY;
    if (planeDistance <= 0.0) return skyColour;

    vec2 wind = vec2(frameTimeCounter * 0.0092, frameTimeCounter * 0.0035) * CLOUD_SPEED;
    vec2 p = (cameraPosition.xz + dir.xz * planeDistance) * (1.0 / 900.0) + wind;

    // Stretched hard along x and squashed on y: cirrus is streaked by wind shear,
    // not puffy.
    vec2 streak = vec2(p.x * 0.34, p.y * 1.85);
    float threshold = mix(0.62, 0.42, saturate(CLOUD_COVERAGE));
    float veil = fbm2(streak);
    if (veil < (threshold - 0.28) / 0.72) return skyColour;
    float wisps = valueNoise(streak * 2.7 + vec2(9.0, 4.0));
    float density = saturate((veil * 0.72 + wisps * 0.28 - threshold) * 2.6);
    if (density < 0.01) return skyColour;

    // Thin ice catches the sun almost additively: it is bright on the sun side and
    // nearly invisible away from it.
    float forward = dot(dir, sky.lightDir);
    float glow = saturate(forward) * saturate(forward);
    vec3 tint = sky.ambientSky * 2.6 + sky.sunRadiance * (0.35 + 0.85 * glow);

    // Fade out at the horizon so the veil does not become a hard band.
    return mix(skyColour, tint, saturate(density) * 0.18 * horizonFade);
#endif
}

#endif
