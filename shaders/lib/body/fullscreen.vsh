#include "/lib/uniforms.glsl"

/* Shared fullscreen vertex stage for composite and final.
 *
 * These passes are drawn as one quad over the whole screen, and gl_TextureMatrix[0]
 * is what Iris sets up to map that quad onto texel centres correctly. Reading
 * gl_MultiTexCoord0 directly is the same thing minus that correction, which shows
 * up as a half texel shift once the screen and the buffer disagree in size.
 */

out vec2 texcoord;

void main() {
    gl_Position = gl_ModelViewProjectionMatrix * gl_Vertex;
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}
