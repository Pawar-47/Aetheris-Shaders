#ifndef AETHERIS_SHADOW_GLSL
#define AETHERIS_SHADOW_GLSL

#include "/lib/util.glsl"

/* Shadow mapping.
 *
 * One depth map, one golden angle spiral, no cascades. The HD 5500 renders the
 * shadow pass at the cost of a second full geometry submission, so a second
 * cascade would nearly double the vertex load of the whole pack for a benefit only
 * visible past a hundred blocks, which is inside the fog anyway.
 *
 * The spiral is jittered per pixel with the Bayer pattern: a fixed eight tap
 * spiral leaves a recognisable, static stipple on every soft edge, while rotating
 * it per pixel turns the same eight taps into coherent dither that reads as a
 * smooth penumbra.
 *
 * shadowtex0 carries the alpha tested foliage as well as solid geometry, so tree
 * shadows have the shape of the leaves. shadowtex1 is opaque only and is not used:
 * cheaper in bandwidth by nothing, and worse looking by a lot.
 */

uniform sampler2D shadowtex0;

/* Nine points on a golden angle spiral, spread over roughly the unit disc. */
const vec2 SHADOW_TAPS[9] = vec2[9](
    vec2(-0.6134,  0.7898),
    vec2( 0.9239,  0.3827),
    vec2(-0.2452, -0.9705),
    vec2( 0.3827, -0.9239),
    vec2(-0.9658,  0.1147),
    vec2( 0.7211,  0.6739),
    vec2(-0.0712,  0.4619),
    vec2( 0.2957,  0.1311),
    vec2(-0.4091, -0.3551)
);

/* Fully lit return value for the cases that must not sample at all. */
const float SHADOW_LIT = 1.0;

/* Shadow factor for a surface.
 *
 * playerPos is camera relative world space, normal is the geometric normal in the
 * same space, NdotL the angle to the casting light. Returns 1.0 fully lit, 0.0
 * fully shadowed.
 *
 * The bias is split into two parts on purpose. A constant depth bias cannot be
 * both small enough to stop light leaking under a wall and large enough to stop
 * acne on a surface edge on to the light, so the normal offset grows with the
 * slope and the depth bias only has to cover a couple of texels.
 */
float sampleShadow(vec3 playerPos, vec3 normal, float NdotL) {
#if SHADOWS == 0
    return SHADOW_LIT;
#else
    float slope = 1.0 - clamp(NdotL, 0.0, 1.0);

    // Push the sample off the surface along the normal. This is a world space
    // offset, so it also fixes shadow acne that comes from the terrain's own
    // stair stepping, which a depth space bias alone cannot.
    vec3 position = playerPos + normal * (0.055 + 0.130 * slope);

    vec4 clip = shadowProjection * (shadowModelView * vec4(position, 1.0));
    if (clip.w <= 0.0) return SHADOW_LIT;

    vec3 ndc = clip.xyz / clip.w;
    vec2 uv = ndc.xy * 0.5 + 0.5;

    // Outside the map is lit, not dark: an object beyond the shadow distance
    // should not sit under a hard black border.
    if (uv.x <= 0.002 || uv.x >= 0.998 || uv.y <= 0.002 || uv.y >= 0.998) return SHADOW_LIT;

    float receiverDepth = ndc.z * 0.5 + 0.5;

    float distance01 = saturate(length(playerPos) / shadowDistance);
    float depthBias = 0.00022 + 0.00160 * slope;
    float band = 0.00040 + 0.00125 * distance01;

    // The penumbra widens with distance because one shadow texel covers more world
    // out there, and with slope because that is where a shadow stretches and its
    // stored depth loses resolution.
    float radius = SHADOW_SOFTNESS * mix(0.85, 3.40, distance01) * (0.75 + 0.85 * slope);
    float texel = radius / float(shadowMapResolution);

    // Per pixel rotation of the whole spiral. Two pixels sixteen steps apart in the
    // Bayer pattern differ by a large angle, so neighbouring pixels cover
    // completely different parts of the disc.
    float angle = 6.28318531 * fract(aetherisHash(gl_FragCoord.xy) + 0.5);
    float c = cos(angle);
    float s = sin(angle);

    float lit = 0.0;
#if SHADOW_SAMPLES == 4
    const int taps = 4;
#elif SHADOW_SAMPLES == 9
    const int taps = 9;
#else
    const int taps = 6;
#endif

    for (int i = 0; i < taps; i++) {
        vec2 offset = rotate2(SHADOW_TAPS[i], c, s) * texel;
        float storedDepth = texture(shadowtex0, uv + offset).r;
        // A smooth band rather than a hard step. A surface within one depth quantum
        // of its own shadow then receives partial light instead of flickering
        // between black and white, which is exactly what shadow acne is.
        lit += smoothstep(receiverDepth - depthBias, receiverDepth - depthBias + band, storedDepth);
    }
    lit /= float(taps);

    // Fade to lit at the rim of the map and at the far end of the shadow range, so
    // there is no visible ring where shadows simply stop.
    float edge = min(min(uv.x, uv.y), min(1.0 - uv.x, 1.0 - uv.y));
    float edgeFade = smoothstep(0.0, 0.06, edge);
    float farFade = 1.0 - smoothstep(shadowDistance * 0.72, shadowDistance, length(playerPos));

    return mix(SHADOW_LIT, lit, edgeFade * farFade);
#endif
}

/* Cheap contact darkening in the shadow lookup itself.
 *
 * A surface pressed against another surface reads as a soft dark line even where the sun
 * is not involved. This is not a real occlusion test; it darkens where the stored shadow
 * depth is a little in front of the receiver, which is where contact happens. Four taps
 * from the same spiral, and it is only called inside twenty blocks.
 *
 * The test is deliberately "strictly in front, and not far in front". The obvious form,
 * step(storedDepth, receiverDepth + eps), also counts the surface's own stored depth: on a
 * vertical face the normal offset moves the receiver sideways rather than towards the
 * light, so its light space depth does not change, every tap reads as an occluder, and
 * every wall in the world loses half its ambient. Range is expressed in shadow map depth,
 * where 0.012 is roughly one block of contact at ninety six blocks of shadow distance. */
float sampleShadowContact(vec3 playerPos, vec3 normal, float NdotL) {
#if SHADOWS == 0
    return 1.0;
#else
    float slope = 1.0 - clamp(NdotL, 0.0, 1.0);
    vec3 position = playerPos + normal * (0.045 + 0.110 * slope);

    vec4 clip = shadowProjection * (shadowModelView * vec4(position, 1.0));
    if (clip.w <= 0.0) return 1.0;

    vec3 ndc = clip.xyz / clip.w;
    vec2 uv = ndc.xy * 0.5 + 0.5;
    if (uv.x <= 0.002 || uv.x >= 0.998 || uv.y <= 0.002 || uv.y >= 0.998) return 1.0;

    float receiverDepth = ndc.z * 0.5 + 0.5;
    float texel = 2.2 / float(shadowMapResolution);

    float bias = 0.0006 + 0.0012 * slope;
    const float contactRange = 0.012;

    float occluded = 0.0;
    for (int i = 0; i < 4; i++) {
        float storedDepth = texture(shadowtex0, uv + SHADOW_TAPS[i] * texel).r;
        float delta = receiverDepth - storedDepth;
        if (delta > bias && delta < contactRange) {
            occluded += 1.0 - delta / contactRange;
        }
    }
    occluded *= 0.25;

    float distance01 = saturate(length(playerPos) / shadowDistance);
    return mix(1.0, 1.0 - 0.35 * occluded, (1.0 - distance01) * 0.85);
#endif
}

#endif
