#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"

/* Trimmed vertex stage for the small passes: weather, glint, beacon beams,
 * lightning, spider eyes and the block damage overlay.
 *
 * No wind and no normal matrix. These cover a handful of pixels each, several of
 * them have no meaningful normal at all, and several do not carry a lightmap, so
 * the cheap version is both faster and less likely to produce something strange.
 */

in vec2 mc_Entity;

out vec2 texcoord;
out vec4 tint;
out vec3 playerPosition;

void main() {
    vec4 viewPosition = gl_ModelViewMatrix * gl_Vertex;
    gl_Position = gl_ProjectionMatrix * viewPosition;

    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    tint = gl_Color;
    playerPosition = (gbufferModelViewInverse * viewPosition).xyz;
}
