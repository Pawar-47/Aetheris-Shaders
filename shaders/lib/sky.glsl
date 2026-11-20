#ifndef AETHERIS_SKY_GLSL
#define AETHERIS_SKY_GLSL

#include "/lib/atmosphere.glsl"
#include "/lib/clouds.glsl"

/* The dome: gradient, stars, sun, moon, then the two cloud layers.
 *
 * Order matters. Stars and discs are part of the sky, so the clouds blend over
 * them and correctly occlude the moon. Drawing the moon after the clouds is how a
 * pack ends up with a moon visible through a thunderhead.
 */

/* Offset of dir from a direction, measured in the plane tangent to that direction.
 *
 * A tangent basis keeps the disc edge sharp. Using acos(dot()) instead loses all
 * its precision exactly at the edge, where it matters, and produces a ragged rim.
 * Only reached for pixels that face the sun or the moon. */
vec2 aetherisDiscOffset(vec3 dir, vec3 centre) {
    vec3 reference = abs(centre.y) > 0.99 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
    vec3 tangentX = normalize(cross(centre, reference));
    vec3 tangentY = cross(centre, tangentX);
    float forward = max(dot(dir, centre), 1.0e-3);
    return vec2(dot(dir, tangentX), dot(dir, tangentY)) / forward;
}

/* Star field.
 *
 * An equirectangular grid with one candidate star per cell, placed at a random
 * point inside it so the stars are round points and not whole cells. Two layers:
 * many faint stars and a few bright ones, which is what gives a real night sky its
 * sense of depth instead of an even sprinkle.
 *
 * Only ever evaluated at night, and only for sky pixels. */
vec3 aetherisStars(vec3 dir, AetherisSky sky) {
    if (sky.night < 0.02 || sky.rain > 0.75) return vec3(0.0);

    vec2 uv = vec2(atan(dir.z, dir.x) * 0.15915494, dir.y * 2.0);

    vec3 total = vec3(0.0);
    for (int layer = 0; layer < 2; layer++) {
        float scale = layer == 0 ? 210.0 : 84.0;
        float threshold = layer == 0 ? 0.955 : 0.988;

        vec2 scaled = uv * scale + float(layer) * 37.0;
        vec2 cell = floor(scaled);
        float pick = aetherisHash(cell + float(layer) * 19.3);
        if (pick < threshold) continue;

        vec2 local = fract(scaled);
        vec2 centre = vec2(aetherisHash(cell + 1.7), aetherisHash(cell + 4.3));
        float starDistance = length(local - centre);

        // Sharper and larger on the bright layer.
        float radius = layer == 0 ? 0.16 : 0.26;
        float core = smoothstep(radius, 0.0, starDistance);
        core *= core;

        float brightness = (pick - threshold) / (1.0 - threshold);
        total += core * (0.35 + 0.65 * brightness) * (layer == 0 ? 0.16 : 0.55);
    }

    // Fade the field out near the horizon and as day comes up.
    float fade = smoothstep(0.0, 0.28, dir.y) * (1.0 - sky.day) * (1.0 - sky.rain);
    return total * fade * vec3(0.92, 0.95, 1.10);
}

/* The sun.
 *
 * A tight body plus a broad Mie halo, and the halo is the part that sells it: the
 * disc alone at this angular size looks like a sticker, while the gradient around
 * it is what makes the whole dome read as a volume of air lit from one side. */
vec3 aetherisSunDisc(vec3 dir, AetherisSky sky) {
    float forward = dot(dir, sky.sunDir);
    if (forward < 0.86) return vec3(0.0);

    // The disc is MakeUp's shape: a radius from a size constant and a *cubed* smoothstep
    // across the angular distance. The cube is what gives it a soft edge and a solid core,
    // and that softness is what keeps it free of the stair-stepping a hard-edged circle shows
    // when it is only a few degrees across. At 1.0 this is already several times vanilla's
    // sun, which is the look being imitated.
    float size = 0.007 * SUN_SIZE;
    float body = smoothstep(1.0 - size, 1.0, forward);
    body = body * body * body;

    // Two lobes of the same phase function, wide and tight, approximating what a
    // real Mie halo does without the integral.
    float wide = miePhaseNormalised(forward, 0.62);
    float tight = miePhaseNormalised(forward, 0.92);
    float halo = wide * 0.42 + tight * 1.15;

    // MakeUp's reddening: the sun's own transmittance raised to a power that grows as it
    // approaches the horizon, so it goes orange and then deep red rather than just dimming.
    float horizonPower = pow(1.0 - saturate(sky.sunDir.y), 16.0) * 4.0 + 1.0;
    vec3 tint = pow(sunTransmittance(clamp(sky.sunDir.y, 0.0, 1.0)), vec3(horizonPower));

    vec3 colour = tint * (body * 26.0 + halo * 2.4);

    // The disc sinks out of sight smoothly, and rain swallows it.
    colour *= smoothstep(-0.06, 0.02, sky.sunDir.y) * (1.0 - sky.rain * 0.92);

    return colour;
}

/* The moon, with just enough mottling that it is not a flat coin. */
vec3 aetherisMoonDisc(vec3 dir, AetherisSky sky) {
    float forward = dot(dir, sky.moonDir);
    if (forward < 0.95 || sky.night < 0.02) return vec3(0.0);

    // The same MakeUp construction as the sun, at the moon's own size. Keeping the pair on one
    // construction is what stops them looking like two different packs.
    float size = 0.003 * SUN_SIZE;
    float body = smoothstep(1.0 - size, 1.0, forward);
    body = body * body * body;
    if (body <= 0.0) return vec3(0.0);

    vec2 offset = aetherisDiscOffset(dir, sky.moonDir);
    float maria = 0.78 + 0.22 * valueNoise(offset * 62.0);
    vec3 colour = vec3(0.86, 0.91, 1.08) * (body * maria * 3.4);

    colour *= (1.0 - sky.rain * 0.9) * smoothstep(-0.04, 0.05, sky.moonDir.y);
    return colour * sky.night;
}

/* Everything above the terrain, in one call. */
vec3 aetherisRenderSky(vec3 dir, AetherisSky sky) {
    vec3 colour = aetherisSkyGradient(dir, sky);

    colour += aetherisStars(dir, sky);
    colour += aetherisSunDisc(dir, sky);
    colour += aetherisMoonDisc(dir, sky);

    // Clouds last, so they occlude the discs rather than the other way round.
    colour = aetherisRenderClouds(dir, sky, colour);
    colour = aetherisRenderCirrus(dir, sky, colour);

    return colour;
}

#endif
