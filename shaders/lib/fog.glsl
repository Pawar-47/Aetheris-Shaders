#ifndef AETHERIS_FOG_GLSL
#define AETHERIS_FOG_GLSL

#include "/lib/atmosphere.glsl"

/* Fog and atmosphere depth.
 *
 * Applied forward, in the geometry pass, on the lit colour. Doing it here rather
 * than in composite means the composite pass never has to visit an opaque pixel
 * unless ambient occlusion is going to touch it, which on this hardware is most of
 * the frame budget saved.
 *
 * Three terms, and they are separate on purpose:
 *
 *   1. Height fog. Exponential density above a base height, integrated along the
 *      ray with a two point approximation. This is what puts a valley in mist and
 *      leaves a mountain top in clear air.
 *   2. Distance haze. Exponential in distance, tinted to the sky's own horizon
 *      colour so distant terrain dissolves into the same colour as the sky behind
 *      it. There is no seam because there is no second palette.
 *   3. A sun facing glow. The Mie forward lobe again, so looking towards the sun
 *      through haze lifts it, which is most of what reads as atmosphere rather than
 *      as a grey veil.
 *
 * The render distance fade is not aesthetics, it is hiding the point where the world
 * stops existing. On an i3 the render distance is going to be six to eight chunks
 * and that edge is otherwise very visible.
 */

const float FOG_BASE_HEIGHT = 58.0;

/* The colour underwater fog goes to. Shared with composite, which uses it to fill
 * the sky when the eye is submerged: there is no sky down there, only water. */
vec3 aetherisUnderwaterTint(AetherisSky sky, vec3 direction) {
    vec3 deep = vec3(0.016, 0.072, 0.098) * (0.30 + 1.05 * sky.day);
    float towardsSun = saturate(dot(direction, sky.sunDir) * 0.5 + 0.5);
    return deep + sky.sunRadiance * (0.020 * towardsSun) + sky.night * vec3(0.004, 0.010, 0.020);
}

vec3 aetherisApplyFog(vec3 colour, vec3 playerPos, AetherisSky sky) {
    float distance = length(playerPos);

    // ---------------------------------------------------------------- underwater
    if (isEyeInWater == 1) {
        // Short range, strong absorption, and brighter towards the surface. Water
        // is the one medium where a heavy handed fog is correct: this is how a lake
        // actually looks from inside.
        float amount = 1.0 - exp(-distance * (0.085 * FOG_DENSITY));
        return mix(colour, aetherisUnderwaterTint(sky, normalize(playerPos)), saturate(amount));
    }

    // ------------------------------------------------------------------- in the end
    // The End and the Nether both have their own vanilla fog colour and no sky to
    // speak of. Blending towards it keeps those dimensions looking like themselves
    // instead of like an overworld with the saturation turned down.
    // fogColor is a strong, saturated colour in those dimensions and near black in
    // the overworld, so its luminance is a reliable discriminator.
    float vanillaLuma = luma(fogColor);
    if (vanillaLuma > 0.0015) {
        float amount = 1.0 - exp(-distance * (0.030 * FOG_DENSITY));
        return mix(colour, fogColor * 0.85, saturate(amount) * 0.92);
    }

    // ---------------------------------------------------------------- height fog
    float cameraHeight = cameraPosition.y;
    float fragmentHeight = cameraHeight + playerPos.y;

    float nearDensity = exp(-max(cameraHeight - FOG_BASE_HEIGHT, 0.0) * (1.0 / FOG_HEIGHT));
    float farDensity  = exp(-max(fragmentHeight - FOG_BASE_HEIGHT, 0.0) * (1.0 / FOG_HEIGHT));

    // Weighted towards the far end: on a ray that climbs, most of the path really is
    // near the far end, and on a flat ray the two agree anyway.
    float heightTerm = nearDensity * 0.35 + farDensity * 0.65;

    // Rain thickens the air substantially, which is most of what sells a storm.
    float density = heightTerm * FOG_DENSITY * (1.0 + 1.40 * sky.rain);

    float amount = 1.0 - exp(-distance * density * (1.0 / 320.0));

    // Hide the edge of the render distance. Ramped over the last fifth so it reads
    // as haze closing in rather than as a wall.
    amount = max(amount, smoothstep(far * 0.80, far * 0.995, distance) * 0.94);

    // ------------------------------------------------------------------- haze tint
    vec3 direction = normalize(playerPos);
    vec3 haze = aetherisHazeColour(direction, sky);

    // Forward scattering: the haze brightens when looking into the light.
    float glow = miePhaseNormalised(dot(direction, sky.lightDir), 0.70);
    haze += (sky.sunRadiance + sky.moonRadiance) * (0.16 * glow);

    return mix(colour, haze, saturate(amount));
}

#endif
