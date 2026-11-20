#ifndef AETHERIS_SSAO_GLSL
#define AETHERIS_SSAO_GLSL

#include "/lib/depth.glsl"

/* Screen space ambient occlusion.
 *
 * This is the one place the pack has to undo the choice to light forward: AO has to
 * be applied to the already lit image as a multiplier. Two consequences, both
 * handled here:
 *
 *   1. It cannot distinguish direct sun from ambient. Darkening a sunlit crease and
 *      a shaded one by the same amount is wrong but it is a second order error next
 *      to the big win, which is that corners stop floating.
 *   2. It must not touch the fog. AO is faded out completely by 46 blocks, well
 *      before the fog has accumulated, so the two never meet.
 *
 * The occlusion test works in view space: a sample point is placed a little way off
 * the surface along the normal, projected back to the screen, and compared against
 * the geometry stored there. If the stored geometry is nearer than the sample
 * point, that sample is behind a surface and contributes occlusion.
 *
 * Doing it in view space rather than with screen-space offsets means the sample
 * radius is a real distance in blocks, so it does not shrink on distant surfaces
 * the way a fixed pixel radius does.
 */

const float SSAO_RADIUS = 0.62;

/* Six points on a spiral, rotated per pixel by the Bayer pattern so the fixed
 * pattern does not show as banding in a smooth crease. */
const vec2 SSAO_TAPS[9] = vec2[9](
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

/* Returns a multiplier in [1 - strength, 1]. */
float aetherisSSAO(vec2 uv, float depth) {
#if SSAO == 0
    return 1.0;
#else
    float distance = linearizeDepth(depth);

    // Two fades: the far one saves the whole computation beyond 46 blocks, the near
    // one avoids a visible ring where AO stops.
    if (distance > 46.0) return 1.0;
    float fade = 1.0 - smoothstep(20.0, 46.0, distance);
    if (fade <= 0.001) return 1.0;

    vec3 centre = screenToView(uv, depth);
    vec2 texel = vec2(1.0 / viewWidth, 1.0 / viewHeight);

    // Surface normal from the depth buffer's own derivatives. Five taps, but four of
    // them are reused by nothing else and a normal is what separates a crease from a
    // silhouette.
    vec3 left  = screenToView(uv - vec2(texel.x, 0.0), texture(depthtex1, uv - vec2(texel.x, 0.0)).r);
    vec3 right = screenToView(uv + vec2(texel.x, 0.0), texture(depthtex1, uv + vec2(texel.x, 0.0)).r);
    vec3 down  = screenToView(uv - vec2(0.0, texel.y), texture(depthtex1, uv - vec2(0.0, texel.y)).r);
    vec3 up    = screenToView(uv + vec2(0.0, texel.y), texture(depthtex1, uv + vec2(0.0, texel.y)).r);

    vec3 normal = cross(right - left, up - down);
    float normalLength = length(normal);
    if (normalLength < 1.0e-9) return 1.0;
    normal /= normalLength;

    // Face the normal towards the camera. View space looks down -Z, so a normal with
    // a positive Z is pointing away.
    if (normal.z > 0.0) normal = -normal;

    // Any orthonormal pair will do, as long as it is stable when the normal is
    // vertical.
    vec3 reference = abs(normal.y) > 0.99 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
    vec3 tangent = normalize(cross(reference, normal));
    vec3 bitangent = cross(normal, tangent);

    float angle = 6.28318531 * fract(aetherisHash(gl_FragCoord.xy) + 0.42);
    float cosine = cos(angle);
    float sine = sin(angle);

#if SSAO_SAMPLES == 4
    const int taps = 4;
#elif SSAO_SAMPLES == 9
    const int taps = 9;
#else
    const int taps = 6;
#endif

    float occlusion = 0.0;
    float accepted = 0.0;

    for (int i = 0; i < taps; i++) {
        vec2 offset = rotate2(SSAO_TAPS[i], cosine, sine);

        // A hemisphere sample: offset in the tangent plane, lifted along the normal
        // so the sample point sits above the surface rather than inside it.
        vec3 samplePoint = centre
                         + (tangent * offset.x + bitangent * offset.y) * SSAO_RADIUS
                         + normal * (SSAO_RADIUS * 0.35);

        vec3 screenPoint = viewToScreen(samplePoint);
        if (!screenPositionValid(screenPoint)) continue;

        float storedDistance = linearizeDepth(texture(depthtex1, screenPoint.xy).r);
        float sampleDistance = -samplePoint.z;

        // Occluders only count when they are near this surface. Without the upper
        // bound a distant hill behind a fence post darkens the post, which is the
        // classic halo.
        float delta = sampleDistance - storedDistance;
        if (delta > 0.02 && delta < SSAO_RADIUS * 3.0) {
            occlusion += 1.0 - delta / (SSAO_RADIUS * 3.0);
        }
        accepted += 1.0;
    }

    if (accepted < 1.0) return 1.0;

    occlusion /= accepted;
    return 1.0 - occlusion * 0.85 * fade;
#endif
}

#endif
