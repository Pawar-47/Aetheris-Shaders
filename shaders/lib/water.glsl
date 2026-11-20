#ifndef AETHERIS_WATER_GLSL
#define AETHERIS_WATER_GLSL

#include "/lib/util.glsl"

/* Water surface normals.
 *
 * Geometry is deliberately left alone. Vanilla water is a flat plane at block
 * height and displacing it in the vertex shader tears the surface open at every
 * chunk and biome boundary, and buys almost nothing: at eye level the visual
 * information in water is entirely in its normal, not its silhouette. So the waves
 * here are slope only.
 *
 * The wave set is five directional components whose amplitude falls with
 * wavelength at a constant ratio. That ratio is the steepness of the wave, and
 * keeping it constant across the octaves is what makes the result read as one body
 * of water rather than as five sine waves added together. It is also why the look
 * holds together when the wind is turned up: every scale gains equal slope.
 *
 * The two coarsest components are never faded out. The finer three fade with
 * distance, because at thirty blocks a one block wavelength is below one pixel and
 * can only alias into glitter that crawls when the camera moves.
 */

const vec2 WAVE_DIRECTION[5] = vec2[5](
    vec2( 1.0000,  0.0000),
    vec2( 0.6235,  0.7818),
    vec2(-0.3511,  0.9363),
    vec2( 0.8716, -0.4903),
    vec2(-0.7692, -0.6390)
);

/* Radians per block. Wavelengths from about fifteen blocks down to one. */
const float WAVE_FREQUENCY[5] = float[5](0.42, 0.78, 1.55, 3.10, 6.20);

/* Slope amplitude. Constant steepness: amplitude times frequency is nearly equal
 * across the set, which is the physical relation that makes the sum look natural. */
const float WAVE_AMPLITUDE[5] = float[5](0.055, 0.032, 0.016, 0.0075, 0.0032);

const float WAVE_RATE[5] = float[5](0.55, 0.78, 1.15, 1.75, 2.60);

/* The surface normal, in camera relative world space.
 *
 * worldPos is the fragment position, geometricNormal its unmodified normal, and
 * viewDistance the distance from the eye which drives the detail fade. */
vec3 aetherisWaterNormal(vec3 worldPos, vec3 geometricNormal, float viewDistance) {
#if WATER_WAVES == 0
    return geometricNormal;
#else
    // A vertical face is a waterfall or the side of a water column. Wind waves do
    // not exist there, and a horizontal wave field smeared onto a vertical plane
    // looks like television static.
    if (abs(geometricNormal.y) < 0.55) {
        // A slow, large scale wobble so a waterfall is not glassy, but no wave sum.
        vec2 p = vec2(worldPos.x + worldPos.z, worldPos.y) * 0.55;
        vec3 n = valueNoiseGradient(p + vec2(0.0, frameTimeCounter * 1.4));
        vec3 tangentNormal = normalize(vec3(n.y, 0.0, n.z) * 0.16 + geometricNormal);
        return tangentNormal;
    }

    vec2 p = worldPos.xz;
    float time = frameTimeCounter * WATER_WAVE_SPEED;
    float detail = 1.0 - smoothstep(26.0, 115.0, viewDistance);

    vec2 gradient = vec2(0.0);
    for (int i = 0; i < 5; i++) {
        // The two coarse components always run; the rest fade out with distance.
        float weight = i < 2 ? 1.0 : detail;
        if (weight <= 0.0) continue;

        float phase = dot(WAVE_DIRECTION[i], p) * WAVE_FREQUENCY[i]
                    + time * WAVE_RATE[i] * WAVE_FREQUENCY[i];
        gradient += WAVE_DIRECTION[i] * (cos(phase) * WAVE_AMPLITUDE[i] * WAVE_FREQUENCY[i] * weight);
    }

    // A non repeating ripple layer near the eye. Two octaves of the same gradient
    // noise the clouds use, drifting in two directions so it never looks like a
    // texture being scrolled.
    if (detail > 0.001) {
        vec2 q = p * 0.85;
        vec3 rippleA = valueNoiseGradient(q + vec2(time * 0.17, -time * 0.13));
        vec3 rippleB = valueNoiseGradient(q * 2.13 + vec2(-time * 0.24, time * 0.19));
        gradient += (rippleA.yz + rippleB.yz * 0.55) * (0.052 * detail);
    }

    gradient *= WATER_WAVE_HEIGHT;

    // The normal is the surface tilted by the wave slope. Building it directly from
    // the analytic gradient rather than from a normal map keeps it free of texel
    // aliasing and of the tiling pattern a sampled normal map would show across a
    // large lake.
    return normalize(vec3(-gradient.x, 1.0, -gradient.y));
#endif
}

/* Normal packed into two channels plus the vanilla texture's modulation.
 *
 * The surface normal's y component is always positive and follows from x and z, so
 * only two channels are needed. Reconstructing it saves a byte that the vanilla
 * water texture's own brightness variation uses instead, which is what keeps the
 * water recognisably Minecraft's water and not a generic procedural surface.
 */
vec4 aetherisPackWaterData(vec3 normal, float textureModulation) {
    return vec4(normal.x * 0.5 + 0.5, normal.z * 0.5 + 0.5, textureModulation, 1.0);
}

vec3 aetherisUnpackWaterNormal(vec4 data) {
    vec2 xz = data.rg * 2.0 - 1.0;
    float y = sqrt(max(1.0 - dot(xz, xz), 0.0));
    return normalize(vec3(xz.x, max(y, 0.02), xz.y));
}

#endif
