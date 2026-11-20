#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/util.glsl"
#include "/lib/vegetation.glsl"

/* Shared vertex stage for terrain, entities, blocks and the held item.
 *
 * Everything it produces is in camera relative world space rather than view space.
 * That is not cosmetic: the lighting, the shadow lookup and the fog all want world
 * directions, and converting once here is cheaper than converting back per
 * fragment, where the work would repeat for every pixel of every surface.
 */

in vec2 mc_Entity;

out vec2 texcoord;
out vec2 lightmapCoord;
out vec3 playerPosition;
out vec3 playerNormal;
out vec4 tint;
out float blockId;

void main() {
    vec4 viewPosition = gl_ModelViewMatrix * gl_Vertex;
    vec3 worldPosition = (gbufferModelViewInverse * viewPosition).xyz;
    vec3 worldNormal = normalize(mat3(gbufferModelViewInverse) * (gl_NormalMatrix * gl_Normal));

    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lightmapCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    tint = gl_Color;

    // The wind field must be sampled in absolute world coordinates. Sampling it in
    // camera relative space would attach the gust pattern to the player and the
    // whole forest would slide along with the camera.
    float weight = aetherisWindWeight(mc_Entity.x, gl_MultiTexCoord0.y);
    if (weight > 0.0) {
        worldPosition += aetherisWindOffset(worldPosition + cameraPosition, weight);
        viewPosition = gbufferModelView * vec4(worldPosition, 1.0);
    }

    gl_Position = gl_ProjectionMatrix * viewPosition;

    playerPosition = worldPosition;
    playerNormal = worldNormal;
    blockId = mc_Entity.x;
}
