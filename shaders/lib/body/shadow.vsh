#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/util.glsl"
#include "/lib/vegetation.glsl"

/* Shadow map rendering.
 *
 * A single pass, and it has to produce vertices in exactly the same world place as the
 * main pass or the moving foliage will not cast the shadow of what is on screen. Both
 * stages therefore reconstruct camera relative world space and call the same
 * aetherisWindOffset with the same absolute world position, so the shadow of a swaying
 * leaf sways with it rather than sliding out from under it.
 *
 * texcoord is carried for the same reason. Minecraft 1.17 and later do their cutout in
 * the shader, not in fixed function state, so a pack that does not sample the texture in
 * its shadow fragment stage leaves every leaf and every tuft of grass casting the shadow
 * of the full block it lives in.
 */

in vec2 mc_Entity;

out vec2 texcoord;

void main() {
    vec4 shadowViewPosition = gl_ModelViewMatrix * gl_Vertex;
    vec3 worldPosition = (shadowModelViewInverse * shadowViewPosition).xyz;

    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

    float weight = aetherisWindWeight(mc_Entity.x, gl_MultiTexCoord0.y);
    if (weight > 0.0) {
        worldPosition += aetherisWindOffset(worldPosition + cameraPosition, weight);
        shadowViewPosition = shadowModelView * vec4(worldPosition, 1.0);
    }

    gl_Position = gl_ProjectionMatrix * shadowViewPosition;
}
