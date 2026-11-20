#ifndef AETHERIS_SHADOW_GLSL
#define AETHERIS_SHADOW_GLSL

#include "/lib/util.glsl"

/* Shadow mapping.
 *
 * One depth map, no cascades. Performance uses a fixed symmetric four-tap kernel
 * and Iris culls geometry outside the useful shadow frustum/radius. Balanced and
 * Visual use the six- and nine-tap rotated spiral kernels.
 *
 * The low-cost kernel avoids per-pixel hash and trigonometric work. The same depth
 * reads also supply near-field contact darkening, so contact shadows do not launch
 * a second sampling loop.
 *
 * shadowtex0 carries the alpha tested foliage as well as solid geometry, so tree
 * shadows have the shape of the leaves. shadowtex1 is opaque only and is not used:
 * cheaper in bandwidth by nothing, and worse looking by a lot.
 */

uniform sampler2D shadowtex0;

/* The first four taps form a symmetric 2x2 kernel for the low-cost profile.
 * Higher sample counts use the remaining spiral points with per-pixel rotation. */
const vec2 SHADOW_TAPS[9] = vec2[9](
    vec2(-0.5, -0.5), vec2(0.5, -0.5),
    vec2(-0.5, 0.5), vec2(0.5, 0.5),
    vec2(-0.9658, 0.1147), vec2(0.7211, 0.6739),
    vec2(-0.0712, 0.4619), vec2(0.2957, 0.1311),
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
/* One shadow-map walk supplies both the filtered directional shadow and the
 * near-field contact term. This reuses the same depth reads instead of running a
 * second four-tap loop for contact darkening. */
float sampleShadow(vec3 playerPos, vec3 normal, float NdotL,
                   float eyeDistance, out float contact) {
    contact = 1.0;
#if SHADOWS == 0
    return SHADOW_LIT;
#else
    float slope = 1.0 - clamp(NdotL, 0.0, 1.0);
    vec3 position = playerPos + normal * (0.055 + 0.130 * slope);
    vec4 clip = shadowProjection * (shadowModelView * vec4(position, 1.0));
    if (clip.w <= 0.0) return SHADOW_LIT;

    vec3 ndc = clip.xyz / clip.w;
    vec2 uv = ndc.xy * 0.5 + 0.5;
    if (uv.x <= 0.002 || uv.x >= 0.998 || uv.y <= 0.002 || uv.y >= 0.998) return SHADOW_LIT;

    float receiverDepth = ndc.z * 0.5 + 0.5;
    float distance01 = saturate(eyeDistance / shadowDistance);
    float depthBias = 0.00022 + 0.00160 * slope;
    float band = 0.00040 + 0.00125 * distance01;
    float radius = SHADOW_SOFTNESS * mix(0.85, 3.40, distance01) * (0.75 + 0.85 * slope);
    float texel = radius / float(shadowMapResolution);

#if SHADOW_SAMPLES == 4
    const int taps = 4;
#else
#if SHADOW_SAMPLES == 9
    const int taps = 9;
#else
    const int taps = 6;
#endif
    float angle = 6.28318531 * fract(aetherisHash(gl_FragCoord.xy) + 0.5);
    float c = cos(angle);
    float s = sin(angle);
#endif

    float lit = 0.0;
    float contactOccluded = 0.0;
    float contactBias = 0.0006 + 0.0012 * slope;
    const float contactRange = 0.012;

    for (int i = 0; i < taps; i++) {
#if SHADOW_SAMPLES == 4
        vec2 offset = SHADOW_TAPS[i] * texel;
#else
        vec2 offset = rotate2(SHADOW_TAPS[i], c, s) * texel;
#endif
        float storedDepth = texture(shadowtex0, uv + offset).r;
        lit += smoothstep(receiverDepth - depthBias, receiverDepth - depthBias + band, storedDepth);
        float contactDelta = receiverDepth - storedDepth;
        if (contactDelta > contactBias && contactDelta < contactRange) {
            contactOccluded += 1.0 - contactDelta / contactRange;
        }
    }

    lit /= float(taps);
    contactOccluded /= float(taps);
    contact = mix(1.0, 1.0 - 0.35 * contactOccluded, (1.0 - distance01) * 0.85);

    float edge = min(min(uv.x, uv.y), min(1.0 - uv.x, 1.0 - uv.y));
    float edgeFade = smoothstep(0.0, 0.06, edge);
    float farFade = 1.0 - smoothstep(shadowDistance * 0.72, shadowDistance, eyeDistance);
    return mix(SHADOW_LIT, lit, edgeFade * farFade);
#endif
}

#endif
