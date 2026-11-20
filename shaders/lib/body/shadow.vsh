#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/util.glsl"
#include "/lib/vegetation.glsl"

/* Shadow map rendering.
 *
 * A single pass, and it has to produce vertices in exactly the same world place as
 * the main pass or the moving foliage will not cast the shadow of what is on
 * screen. Both stages therefore reconstruct camera relative world space and call
 * the same aetherisWindOffset with the same absolute world position, so the shadow
 * of a swaying leaf sways with it rather than sliding out from under it.
 */

in vec2 mc_Entity;

out float blockId;

void main() {
    vec4 shadowViewPosition = gl_ModelViewMatrix * gl_Vertex;
    vec3 worldPosition = (shadowModelViewInverse * shadowViewPosition).xyz;

    float weight = aetherisWindWeight(mc_Entity.x, gl_MultiTexCoord0.y);
    if (weight > 0.0) {
        worldPosition += aetherisWindOffset(worldPosition + cameraPosition, weight);
        shadowViewPosition = shadowModelView * vec4(worldPosition, 1.0);
    }

    gl_Position = gl_ProjectionMatrix * shadowViewPosition;

    blockId = mc_Entity.x;
}
