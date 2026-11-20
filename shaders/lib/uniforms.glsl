#ifndef AETHERIS_UNIFORMS_GLSL
#define AETHERIS_UNIFORMS_GLSL

/* Iris supplied uniforms.
 *
 * Only declarations here. Samplers are declared by the library that samples them,
 * because in Iris declaring a sampler is what makes the matching buffer or
 * texture available to that program.
 *
 * Space conventions, which are the easiest thing to get wrong:
 *   - sunPosition, moonPosition and shadowLightPosition are in *view* space.
 *     Multiply by mat3(gbufferModelViewInverse) for a world space direction.
 *   - gbufferModelView is the view matrix without hand bobbing, so terrain and
 *     the sky agree.
 *   - cameraPosition is the camera position in blocks, world space.
 */

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;

uniform vec3 cameraPosition;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 shadowLightPosition;

uniform vec3 fogColor;

uniform float frameTimeCounter;
uniform float sunAngle;
uniform float rainStrength;
uniform float wetness;
uniform float near;
uniform float far;

uniform float viewWidth;
uniform float viewHeight;
uniform int isEyeInWater;

#endif
