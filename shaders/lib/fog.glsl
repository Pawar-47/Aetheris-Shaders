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
    // The same authored sea colour the surface fades to, so the water you look at and the
    // water you look through are the same water.
    vec3 sea = vec3(float(WATER_RED), float(WATER_GREEN), float(WATER_BLUE)) / 255.0;
    sea *= sea;

    vec3 deep = sea * (1.35 + 3.20 * sky.day);
    float towardsSun = saturate(dot(direction, sky.sunDir) * 0.5 + 0.5);
    vec3 tint = deep + sky.sunRadiance * (0.020 * towardsSun) + sky.night * sea * 0.55;
    return tint * UNDERWATER_TINT;
}

vec3 aetherisApplyFog(vec3 colour, vec3 playerPos, AetherisSky sky) {
    float distanceToCamera = length(playerPos);

    // ---------------------------------------------------------------- underwater
    if (isEyeInWater == 1) {
        // Short range, strong absorption, and brighter towards the surface. Water
        // is the one medium where a heavy handed fog is correct: this is how a lake
        // actually looks from inside. The density follows UNDERWATER_TINT so that the
        // slider thins the medium as well as greying it; at 1.0 this is 0.085.
        float medium = 0.085 * FOG_DENSITY * (0.55 + 0.45 * UNDERWATER_TINT);
        float amount = 1.0 - exp(-distanceToCamera * medium);
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
        float amount = 1.0 - exp(-distanceToCamera * (0.030 * FOG_DENSITY));
        return mix(colour, fogColor * 0.85, saturate(amount) * 0.92);
    }

    // ---------------------------------------------------------------- height fog
    float cameraHeight = cameraPosition.y;
    float fragmentHeight = cameraHeight + playerPos.y;

    float nearDensity = exp(-max(cameraHeight - FOG_BASE_HEIGHT, 0.0) * (1.0 / FOG_HEIGHT));
    float farDensity  = exp(-max(fragmentHeight - FOG_BASE_HEIGHT, 0.0) * (1.0 / FOG_HEIGHT));

    // Weighted towards the far end: on a ray that climbs, most of the path really is
    // near the far end, and on a flat ray the two agree anyway. The 0.45 is what keeps
    // the default reading as air rather than as weather: Minecraft's scale is small
    // enough that a physically scaled height term looks like a permanent sea mist.
    float heightTerm = (nearDensity * 0.35 + farDensity * 0.65) * 0.45;

    // Rain thickens the air substantially, which is most of what sells a storm.
    float density = heightTerm * FOG_DENSITY * (1.0 + 0.90 * sky.rain);

    // Haze builds from FOG_START outward, not from the eye. Starting the ramp at zero is what
    // makes a pack look fogged rather than like it has air, and it is the one number that
    // was missing from the settings: distance now has a control instead of a constant.
    float hazeDistance = max(distanceToCamera - FOG_START, 0.0);
    float amount = 1.0 - exp(-hazeDistance * density * (1.0 / 520.0));

    // Hide the edge of the render distance, and let the same slider own it. Starting later
    // and scaling with the slider is what makes FOG_DENSITY = 0.0 mean clear air rather than
    // "clear air plus a band of haze at the far plane".
    float edgeFade = smoothstep(far * 0.92, far * 0.999, distanceToCamera) * 0.86;
    amount = max(amount, edgeFade * saturate(FOG_DENSITY));

    // ------------------------------------------------------------------- haze tint
    vec3 direction = normalize(playerPos);
    vec3 haze = aetherisHazeColour(direction, sky);

    // Forward scattering: the haze brightens when looking into the light.
    float glow = miePhaseNormalised(dot(direction, sky.lightDir), 0.70);
    haze += (sky.sunRadiance + sky.moonRadiance) * (0.10 * glow);

    return mix(colour, haze, saturate(amount));
}

#endif
