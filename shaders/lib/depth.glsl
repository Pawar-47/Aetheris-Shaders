#ifndef AETHERIS_DEPTH_GLSL
#define AETHERIS_DEPTH_GLSL

#include "/lib/util.glsl"

/* Depth and screen space conversions.
 *
 * Iris hands out a non linear depth value in [0, 1] straight from the depth
 * buffer. Everything downstream wants either a distance in blocks or a position
 * in view space, and doing that conversion once in the right place is worth more
 * than any micro optimisation in this file.
 */

uniform sampler2D depthtex0; // everything, including translucent and water
uniform sampler2D depthtex1; // opaque geometry only

/* Depth buffer value to view space distance in blocks. */
float linearizeDepth(float depth) {
    return (near * far) / (far - depth * (far - near));
}

/* Screen UV plus a depth buffer value to a position in view space. */
vec3 screenToView(vec2 uv, float depth) {
    vec4 clip = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 view = gbufferProjectionInverse * clip;
    return view.xyz / view.w;
}

/* Position in view space to screen UV, with the depth buffer value in z.
 * The caller must reject points behind the camera: there is no meaningful screen
 * position for them and the perspective divide explodes. */
vec3 viewToScreen(vec3 viewPos) {
    vec4 clip = gbufferProjection * vec4(viewPos, 1.0);
    return (clip.xyz / clip.w) * 0.5 + 0.5;
}

/* True when a projected point is actually in front of the camera and on screen. */
bool screenPositionValid(vec3 screenPos) {
    return screenPos.z > 0.0 && screenPos.z < 1.0
        && screenPos.x > 0.0 && screenPos.x < 1.0
        && screenPos.y > 0.0 && screenPos.y < 1.0;
}

/* Direction of the view ray through a screen pixel, in view space.
 *
 * Taken at the near plane rather than the far plane. Both give the same direction
 * for a perspective projection, but the far plane result is a vector of enormous
 * magnitude whose normalisation can go to infinity on some drivers. */
vec3 viewRayDirection(vec2 uv) {
    return normalize((gbufferProjectionInverse * vec4(uv * 2.0 - 1.0, 0.0, 1.0)).xyz);
}

/* Distance in blocks along the view ray for a screen pixel, from the opaque
 * depth buffer. Used by the ambient occlusion and the water absorption, both of
 * which care about the solid world rather than the water surface. */
float opaqueDistance(vec2 uv) {
    return linearizeDepth(texture(depthtex1, uv).r);
}

#endif
